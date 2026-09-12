import TrunookXPC
import AppKit
import Foundation

/// Исполнитель того, о чём просит модель.
///
/// Отдельным объектом, а не в контроллере: тот и так за две с половиной
/// тысячи строк. И не в `AssistantSession`: та знает клиента модели,
/// буфер и адресата вставки — и знать про календарь с погодой не должна.
/// Службы приходят сюда в `init`, а наружу торчат два вопроса: «что с этим
/// делать» и «сделай».
final class AgentRunner {
    private let calendar: CalendarService
    private let timer: TimerService
    private let notes: NotesService
    private let weather: WeatherService
    /// Поиск по заметкам — по смыслу, а не по словам.
    private let retriever: NotesRetriever
    private let settings: Settings
    /// Номер для карточки: `PendingAction` обязан быть `Identifiable`,
    /// а два одинаковых предложения подряд — обычное дело.
    private var counter = 0

    init(
        calendar: CalendarService,
        timer: TimerService,
        notes: NotesService,
        weather: WeatherService,
        retriever: NotesRetriever = NotesRetriever(),
        settings: Settings = .shared
    ) {
        self.calendar = calendar
        self.timer = timer
        self.notes = notes
        self.weather = weather
        self.retriever = retriever
        self.settings = settings
    }

    /// Описания инструментов, доступных прямо сейчас.
    func tools() -> [[String: Any]] { AgentTool.wire(for: settings) }

    var hasTools: Bool { !AgentTool.available(for: settings).isEmpty }

    // MARK: - Что с этим делать

    /// Разбирает просьбу и решает её судьбу. Ничего не делает.
    func prepare(_ call: ToolCall, now: Date = Date(), calendar day: Calendar = .current) -> AgentAction {
        guard let tool = AgentTool.named(call.name) else {
            // Модель зовёт то, чего мы ей не давали. Молчать нельзя:
            // переписку, где у вызова нет ответа, строгий сервер отвергает
            // целиком, а модели нужен текст, чтобы извиниться по-человечески.
            return .refuse(AgentToolResult(
                text: t("Такого инструмента нет."),
                label: t("Неизвестное действие")
            ))
        }
        if let reason = tool.blockedReason(settings) {
            return .refuse(AgentToolResult(text: reason, label: tool.title))
        }

        switch tool {
        case .upcoming, .dayAgenda, .weatherNow, .searchNotes,
             .startTimer, .stopTimer, .startStopwatch:
            return .run(tool, call)
        case .createEvent:
            return prepareEvent(call, now: now, calendar: day)
        case .createReminder:
            return prepareReminder(call, now: now, calendar: day)
        case .createNote:
            return prepareNote(call)
        }
    }

    // MARK: - Сделай

    /// Смотрящее и обратимое. Пишущее сюда не попадает — оно идёт
    /// через `commit(_:)`, и только после нажатия человека.
    func run(_ tool: AgentTool, _ call: ToolCall, now: Date = Date(), completion: @escaping (AgentToolResult) -> Void) {
        switch tool {
        case .upcoming: completion(readUpcoming(call, now: now))
        case .dayAgenda: completion(readDay(call, now: now))
        case .weatherNow: readWeather(completion: completion)
        case .searchNotes: readNotes(call, completion: completion)
        case .startTimer: completion(startTimer(call))
        case .stopTimer: completion(stopTimer())
        case .startStopwatch: completion(startStopwatch())
        case .createEvent, .createReminder, .createNote:
            // Сюда не попасть: пишущее готовится карточкой.
            completion(AgentToolResult(
                text: t("Это действие требует подтверждения."),
                label: tool.title
            ))
        }
    }

    /// Человек нажал «Создать».
    func commit(_ pending: PendingAction) -> AgentToolResult {
        switch pending.payload {
        case let .event(draft):
            guard calendar.save(draft) else {
                return AgentToolResult(
                    text: t("Не вышло записать встречу в календарь."),
                    label: t("Встреча не создана")
                )
            }
            return AgentToolResult(
                text: tf("Встреча «%@» создана: %@.", draft.title, pending.detail),
                label: tf("Встреча «%@»", draft.title)
            )

        case let .reminder(title, due, hasTime, list):
            guard calendar.addReminder(title: title, due: due, hasTime: hasTime, listNamed: list) else {
                return AgentToolResult(
                    text: t("Не вышло завести напоминание."),
                    label: t("Напоминание не создано")
                )
            }
            return AgentToolResult(
                text: tf("Напоминание «%@» заведено: %@.", title, pending.detail),
                label: tf("Напоминание «%@»", title)
            )

        case let .note(title, text):
            guard let note = saveNote(title: title, text: text) else {
                return AgentToolResult(
                    text: t("Не вышло сохранить заметку."),
                    label: t("Заметка не создана")
                )
            }
            return AgentToolResult(
                text: tf("Заметка «%@» сохранена.", note.title),
                label: tf("Заметка «%@»", note.title)
            )
        }
    }

    /// Человек нажал «Отмена».
    ///
    /// Это не обрыв разговора, а сведение: модель узнаёт об отказе и
    /// договаривает словами. Оборвать всё можно закрытием панели.
    func declined(_ pending: PendingAction) -> AgentToolResult {
        AgentToolResult(
            text: t("Человек отказался. Не делай этого и не предлагай снова, пока не попросят."),
            label: tf("Отменено: %@", pending.title)
        )
    }

    // MARK: - Календарь: чтение

    private func readUpcoming(_ call: ToolCall, now: Date) -> AgentToolResult {
        // Двадцать четыре часа — не прихоть, а горизонт самой службы:
        // `upcoming` держит именно сутки и сводит в один список встречи
        // с напоминаниями. Просить больше значило бы завести второе чтение,
        // которое напоминаний уже не видит.
        let hours = AgentTime.minutes(call.integer("hours"), default: 24, in: 1...24)
        let until = now.addingTimeInterval(TimeInterval(hours) * 3600)
        let items = calendar.upcoming.filter { $0.start <= until }

        guard !items.isEmpty else {
            return AgentToolResult(
                text: tf("На ближайшие %d ч дел нет.", hours),
                label: t("Ближайшие дела")
            )
        }
        return AgentToolResult(
            text: tf("Дела на ближайшие %d ч:", hours) + "\n" + items.map(line(of:)).joined(separator: "\n"),
            label: t("Посмотрел ближайшие дела")
        )
    }

    private func readDay(_ call: ToolCall, now: Date) -> AgentToolResult {
        // Год тут **не** правится: у дел на прошедший день спрашивают
        // законно, и перекатывать такой запрос вперёд значило бы ответить
        // не о том.
        let day: Date
        if let raw = call.string("date") {
            guard let moment = AgentTime.parse(raw, now: now) else {
                return AgentToolResult(text: badDate, label: t("Не понял день"))
            }
            // День дальше года от сегодняшнего спрашивает не человек.
            //
            // Так модель, не знающая сегодняшнего числа, подставляет дату
            // своего обучения: на «что у меня сегодня» она прислала
            // «2023-10-10», приложение честно прочитало тот день и ответило
            // расписанием за позапрошлый год. Молчаливо подменить день своим
            // нельзя — спросили-то другое, — но и отвечать про него незачем.
            // Говорим, какое сегодня число: у круга есть ещё заходы, и модель
            // поправится сама.
            guard AgentTime.isPlausible(moment.date, now: now) else {
                DebugLog.write("помощник: «\(raw)» — день не из этого времени")
                return AgentToolResult(
                    text: tf("«%@» — это не тот год. Сейчас %@. Назови день заново или не указывай его вовсе, если спрашивают про сегодня.",
                             raw, AgentTime.stamp(now: now)),
                    label: t("День не из этого времени")
                )
            }
            day = moment.date
        } else {
            day = now
        }

        let items = calendar.events(on: day)
        let title = AgentTime.humanize(day, isDateOnly: true)
        guard !items.isEmpty else {
            return AgentToolResult(
                text: tf("На %@ дел нет.", title),
                label: tf("Посмотрел %@", title)
            )
        }
        return AgentToolResult(
            text: tf("Дела на %@:", title) + "\n" + items.map(line(of:)).joined(separator: "\n"),
            label: tf("Посмотрел %@", title)
        )
    }

    /// Одна строка расписания — для модели, а не для экрана.
    private func line(of item: CalendarItem) -> String {
        let when = item.isAllDay
            ? t("весь день")
            : AgentTime.humanize(item.start, isDateOnly: false)
        return "— \(when): \(item.title)"
    }

    // MARK: - Календарь: запись

    private func prepareEvent(_ call: ToolCall, now: Date, calendar day: Calendar) -> AgentAction {
        guard let title = call.string("title") else {
            return .refuse(AgentToolResult(
                text: t("Не сказано, как назвать встречу."),
                label: t("Не понял название")
            ))
        }
        guard let raw = call.string("start"),
              let parsed = AgentTime.parse(raw, now: now, calendar: day)
        else {
            return .refuse(AgentToolResult(text: badDate, label: t("Не понял время")))
        }
        // Год правится: встречу заводят в будущем, а модель, обученная
        // до 2025-го, пишет прошедший год и встреча исчезает из календаря.
        let moment = AgentTime.rollingForward(parsed, now: now, calendar: day)
        let allDay = call.flag("all_day") || moment.isDateOnly
        let minutes = AgentTime.minutes(call.integer("duration_minutes"), default: 60, in: 5...(24 * 60))

        let draft = EventDraft(
            id: nil,
            title: title,
            start: moment.date,
            duration: TimeInterval(minutes) * 60,
            isAllDay: allDay,
            location: call.string("location") ?? "",
            notes: call.string("notes") ?? "",
            link: nil,
            calendarID: calendar.defaultCalendarID(),
            colorComponents: nil,
            attendees: [],
            isRecurring: false,
            originalStart: nil
        )

        var detail = AgentTime.humanize(moment.date, isDateOnly: allDay, calendar: day)
        if !allDay { detail += " · " + draft.durationLabel }
        // Поправленный год называется вслух: человек этого не просил,
        // а промах модели тут молчаливый и дорогой.
        if moment.yearRepaired { detail += " · " + t("год поправлен") }

        return .confirm(pending(
            tool: .createEvent,
            call: call,
            payload: .event(draft),
            title: tf("Встреча «%@»", title),
            detail: detail,
            confirm: t("Создать")
        ))
    }

    private func prepareReminder(_ call: ToolCall, now: Date, calendar day: Calendar) -> AgentAction {
        guard let title = call.string("title") else {
            return .refuse(AgentToolResult(
                text: t("Не сказано, о чём напомнить."),
                label: t("Не понял напоминание")
            ))
        }

        var due: Date?
        var hasTime = false
        var detail = t("без срока")
        if let raw = call.string("due") {
            guard let parsed = AgentTime.parse(raw, now: now, calendar: day) else {
                return .refuse(AgentToolResult(text: badDate, label: t("Не понял время")))
            }
            let moment = AgentTime.rollingForward(parsed, now: now, calendar: day)
            due = moment.date
            hasTime = !moment.isDateOnly
            detail = AgentTime.humanize(moment.date, isDateOnly: moment.isDateOnly, calendar: day)
            if moment.yearRepaired { detail += " · " + t("год поправлен") }
        }

        return .confirm(pending(
            tool: .createReminder,
            call: call,
            payload: .reminder(title: title, due: due, hasTime: hasTime, list: call.string("list")),
            title: tf("Напоминание «%@»", title),
            detail: detail,
            confirm: t("Напомнить")
        ))
    }

    private func prepareNote(_ call: ToolCall) -> AgentAction {
        guard let text = call.string("text") else {
            return .refuse(AgentToolResult(
                text: t("Не сказано, что записать."),
                label: t("Не понял заметку")
            ))
        }
        let title = call.string("title")
        return .confirm(pending(
            tool: .createNote,
            call: call,
            payload: .note(title: title, text: text),
            title: title.map { tf("Заметка «%@»", $0) } ?? t("Новая заметка"),
            detail: preview(of: text),
            confirm: t("Записать")
        ))
    }

    /// Первая строка заметки, обрезанная до одной строки карточки.
    /// Высота карточки постоянна — панель не должна прыгать от длины текста.
    private func preview(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 60 else { return trimmed }
        return String(trimmed.prefix(60)) + "…"
    }

    private func saveNote(title: String?, text: String) -> Note? {
        // Цвет обязателен: заметка чёрным по чёрному выглядит пустой,
        // и понять, что текст на месте, человеку нечем.
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: Note.bodyFontSize),
            .foregroundColor: NSColor.white,
        ])
        // Название передаём готовым, когда оно есть: тогда служба не станет
        // спрашивать его у модели второй раз — а мы её уже спросили.
        return notes.save(attributed, origin: .agent, title: title)
    }

    // MARK: - Таймер

    private func startTimer(_ call: ToolCall) -> AgentToolResult {
        guard let raw = call.integer("minutes") else {
            return AgentToolResult(
                text: t("Не сказано, на сколько минут."),
                label: t("Не понял время")
            )
        }
        let minutes = AgentTime.minutes(raw, default: 25, in: 1...600)
        // Порядок обязателен: `select` сбрасывает начало отсчёта, и пуск
        // до него встал бы на прежней длительности.
        timer.select(mode: .timer)
        timer.select(minutes: minutes)
        timer.start()
        return AgentToolResult(
            text: tf("Таймер на %d мин пошёл.", minutes),
            label: tf("Таймер на %d мин", minutes)
        )
    }

    private func stopTimer() -> AgentToolResult {
        guard timer.isRunning else {
            return AgentToolResult(text: t("Таймер и так не идёт."), label: t("Таймер не шёл"))
        }
        timer.stop()
        return AgentToolResult(text: t("Остановил."), label: t("Таймер остановлен"))
    }

    private func startStopwatch() -> AgentToolResult {
        timer.select(mode: .stopwatch)
        timer.reset()
        timer.start()
        return AgentToolResult(text: t("Секундомер пошёл."), label: t("Секундомер пошёл"))
    }

    // MARK: - Заметки: чтение

    /// Что человек об этом записывал.
    ///
    /// Тем же путём, каким заметки ищет панель, — по смыслу, через вектор
    /// вопроса. Два поиска порознь разошлись бы на первой же правке,
    /// и голос отвечал бы не тем, чем панель.
    ///
    /// Пусто — не отказ и не ошибка: «ничего не записано» это ответ,
    /// и модель обязана его сказать, а не выдумать запись.
    private func readNotes(_ call: ToolCall, completion: @escaping (AgentToolResult) -> Void) {
        guard let query = call.string("query") else {
            completion(AgentToolResult(
                text: t("Не сказано, что искать."),
                label: t("Не понял запрос")
            ))
            return
        }
        retriever.context(for: query, budget: settings.voiceNotesContextLimit) { context in
            guard let context, !context.isEmpty else {
                completion(AgentToolResult(
                    text: tf("В записях про «%@» ничего нет.", query),
                    label: tf("Искал «%@» — пусто", query)
                ))
                return
            }
            completion(AgentToolResult(
                text: context,
                label: tf("Поискал «%@» в заметках", query)
            ))
        }
    }

    // MARK: - Погода

    private func readWeather(completion: @escaping (AgentToolResult) -> Void) {
        weather.snapshot { [weak self] snapshot in
            guard let self else { return }
            guard let snapshot else {
                completion(AgentToolResult(
                    text: t("Погоду узнать не вышло."),
                    label: t("Погода недоступна")
                ))
                return
            }
            var text = "\(snapshot.condition.title), \(self.weather.formatted(snapshot.temperature))"
            if let outlook = snapshot.outlook {
                text += ". " + tf("Через %d ч — %@, вероятность %d%%.",
                                  outlook.inHours,
                                  outlook.condition.title,
                                  outlook.probability)
            }
            completion(AgentToolResult(text: text, label: t("Посмотрел погоду")))
        }
    }

    // MARK: - Мелочи

    private var badDate: String {
        tf("Не понял, на какое время. Назови дату и время как «%@».", AgentTime.format)
    }

    private func pending(
        tool: AgentTool,
        call: ToolCall,
        payload: PendingAction.Payload,
        title: String,
        detail: String,
        confirm: String
    ) -> PendingAction {
        counter += 1
        return PendingAction(
            id: counter,
            tool: tool,
            call: call,
            payload: payload,
            title: title,
            detail: detail,
            confirm: confirm
        )
    }
}
