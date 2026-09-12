import Foundation

/// Что помощник умеет сделать сам.
///
/// Устроено по образцу `HubEntry`: у каждого случая своё имя, подпись,
/// значок, проверка доступности и одно место вызова. Причина та же —
/// иначе список инструментов разошёлся бы с тем, что приложение
/// действительно умеет, на первой же правке.
enum AgentTool: String, CaseIterable, Identifiable {
    case createEvent = "calendar_create_event"
    case upcoming = "calendar_upcoming"
    case dayAgenda = "calendar_day_agenda"
    case startTimer = "timer_start"
    case stopTimer = "timer_stop"
    case startStopwatch = "stopwatch_start"
    case createReminder = "reminder_create"
    case weatherNow = "weather_now"
    case searchNotes = "notes_search"
    case createNote = "note_create"

    var id: String { rawValue }

    /// Имя на проводе. Латиницей и через подчёркивание — этого требует
    /// образец OpenAI `^[a-zA-Z0-9_-]{1,64}$`, и на латинских именах
    /// маленькие модели ошибаются заметно реже.
    var name: String { rawValue }

    /// Что инструмент делает с миром.
    ///
    /// Разрядов три, а не два, и середина здесь не мелочь. Подтверждения
    /// просит то, что пишет в чужое хранилище и чего приложением уже
    /// не отменить. Таймер в этот список не входит: его видно в чёлке,
    /// и гасится он одним нажатием — карточка между «поставь таймер»
    /// и поставленным таймером была бы лишним шагом, а не защитой.
    enum Kind {
        /// Только смотрит. Спрашивать разрешения не о чем.
        case read
        /// Делает, но обратимое и заметное.
        case act
        /// Пишет в календарь, напоминания или заметки.
        case write
    }

    var kind: Kind {
        switch self {
        case .upcoming, .dayAgenda, .weatherNow, .searchNotes: return .read
        case .startTimer, .stopTimer, .startStopwatch: return .act
        case .createEvent, .createReminder, .createNote: return .write
        }
    }

    var needsConfirmation: Bool { kind == .write }

    // MARK: - Как это зовётся для человека

    /// Подпись в настройках и в строке шага в ленте.
    var title: String {
        switch self {
        case .createEvent: return t("Создать встречу")
        case .upcoming: return t("Ближайшие дела")
        case .dayAgenda: return t("Дела на день")
        case .startTimer: return t("Поставить таймер")
        case .stopTimer: return t("Остановить таймер")
        case .startStopwatch: return t("Пустить секундомер")
        case .createReminder: return t("Создать напоминание")
        case .weatherNow: return t("Узнать погоду")
        case .searchNotes: return t("Поискать в заметках")
        case .createNote: return t("Создать заметку")
        }
    }

    var symbol: String {
        switch self {
        case .createEvent: return "calendar.badge.plus"
        case .upcoming: return "calendar"
        case .dayAgenda: return "list.bullet"
        case .startTimer, .stopTimer: return "timer"
        case .startStopwatch: return "stopwatch"
        case .createReminder: return "checklist"
        case .weatherNow: return "cloud.sun"
        case .searchNotes: return "text.magnifyingglass"
        case .createNote: return "square.and.pencil"
        }
    }

    // MARK: - Доступность

    /// Какой настройкой функция включается.
    ///
    /// Своих переключателей у инструментов нет нарочно: инструмент жив ровно
    /// пока жива его функция. Второй набор переключателей был бы вторым
    /// источником правды о том, что работает, — и на вопрос «почему помощник
    /// не ставит таймер» отвечать пришлось бы в двух местах.
    func isEnabled(_ settings: Settings) -> Bool {
        guard settings.agentEnabled else { return false }
        switch self {
        case .createEvent, .upcoming, .dayAgenda: return settings.calendarEnabled
        case .createReminder: return settings.remindersEnabled
        case .startTimer, .stopTimer, .startStopwatch: return settings.timerEnabled
        case .weatherNow: return settings.weatherEnabled
        case .searchNotes, .createNote: return settings.notesEnabled
        }
    }

    /// Почему выключен — для строки в настройках и для ответа модели.
    /// `nil` — включён.
    ///
    /// Исчезающая строка читается как «функцию убрали совсем», а погасшая
    /// с причиной — учит. То же правило, что и у плиток меню функций.
    func blockedReason(_ settings: Settings) -> String? {
        guard !isEnabled(settings) else { return nil }
        guard settings.agentEnabled else { return t("Помощник выключен в настройках.") }
        switch self {
        case .createEvent, .upcoming, .dayAgenda: return t("Календарь выключен в настройках.")
        case .createReminder: return t("Напоминания выключены в настройках.")
        case .startTimer, .stopTimer, .startStopwatch: return t("Таймер выключен в настройках.")
        case .weatherNow: return t("Погода выключена в настройках.")
        case .searchNotes, .createNote: return t("Заметки выключены в настройках.")
        }
    }

    static func named(_ name: String) -> AgentTool? { AgentTool(rawValue: name) }

    // MARK: - Описание для модели

    var schema: ToolSchema {
        ToolSchema(name: name, description: summary, parameters: parameters)
    }

    /// Что инструмент делает — читает модель.
    ///
    /// Через `t()`, как и указание «твой ответ прочитают вслух»: интерфейс
    /// трёхъязычный, и на английском окне модель должна получать английское
    /// описание и отвечать по-английски. Это не недоделка, а то, чего ждут.
    var summary: String {
        switch self {
        case .createEvent:
            return t("Завести встречу в календаре. Спрашивай только то, чего не хватает; остальное не выдумывай.")
        case .upcoming:
            return t("Что впереди на ближайшие сутки: встречи и напоминания по порядку.")
        case .dayAgenda:
            return t("Дела на названный день. Для вопросов про сегодня и завтра бери этот инструмент.")
        case .startTimer:
            return t("Поставить таймер на столько-то минут и пустить его.")
        case .stopTimer:
            return t("Остановить идущий таймер или секундомер.")
        case .startStopwatch:
            return t("Пустить секундомер с нуля.")
        case .createReminder:
            return t("Завести напоминание в Напоминаниях. Со сроком оно прозвенит, без срока просто ляжет в список.")
        case .weatherNow:
            return t("Погода сейчас и осадки на ближайшие часы.")
        case .searchNotes:
            return t("Поискать в записях человека по смыслу. Бери его всякий раз, когда спрашивают о том, что человек когда-то записал или мог записать.")
        case .createNote:
            return t("Сохранить заметку. Текст пиши целиком — человек его потом не допишет.")
        }
    }

    var parameters: [ToolSchema.Parameter] {
        switch self {
        case .createEvent:
            return [
                .init(name: "title", kind: .string, description: t("Название встречи."), isRequired: true),
                .init(name: "start", kind: .string, description: startDescription, isRequired: true),
                .init(name: "duration_minutes", kind: .integer, description: t("Сколько длится, минут. По умолчанию 60."), isRequired: false),
                .init(name: "all_day", kind: .boolean, description: t("Событие на весь день."), isRequired: false),
                .init(name: "location", kind: .string, description: t("Место."), isRequired: false),
                .init(name: "notes", kind: .string, description: t("Описание."), isRequired: false),
            ]
        case .upcoming:
            return [
                .init(name: "hours", kind: .integer, description: t("На сколько часов вперёд смотреть, от 1 до 24. По умолчанию 24."), isRequired: false),
            ]
        case .dayAgenda:
            return [
                .init(name: "date", kind: .string, description: tf("День: «%@» или словом — «сегодня», «завтра», «понедельник». По умолчанию сегодняшний.", "ГГГГ-ММ-ДД"), isRequired: false),
            ]
        case .startTimer:
            return [
                .init(name: "minutes", kind: .integer, description: t("На сколько минут, от 1 до 600."), isRequired: true),
            ]
        case .stopTimer, .startStopwatch, .weatherNow:
            return []
        case .searchNotes:
            return [
                .init(name: "query", kind: .string, description: t("О чём искать. Своими словами, не дословно вопросом."), isRequired: true),
            ]
        case .createReminder:
            return [
                .init(name: "title", kind: .string, description: t("Что напомнить."), isRequired: true),
                .init(name: "due", kind: .string, description: dueDescription, isRequired: false),
                .init(name: "list", kind: .string, description: t("Название списка напоминаний. Не знаешь — не указывай."), isRequired: false),
            ]
        case .createNote:
            return [
                .init(name: "text", kind: .string, description: t("Текст заметки."), isRequired: true),
                .init(name: "title", kind: .string, description: t("Название. Не указывай — приложение придумает само."), isRequired: false),
            ]
        }
    }

    /// Образец времени повторяется в описании каждого параметра нарочно.
    /// Сказанное один раз в системной реплике модель забывает к третьему
    /// инструменту, а прочитанное рядом с полем — нет.
    private var startDescription: String {
        tf("Начало, ровно «%@», местное время: без буквы T, без Z, без смещения.", AgentTime.format)
    }

    private var dueDescription: String {
        tf("Когда напомнить: «%@» или одна дата. Срока нет — не указывай вовсе.", AgentTime.format)
    }

    // MARK: - Что уходит модели

    /// Описания всех доступных сейчас инструментов.
    ///
    /// Пустой список означает «агента нет»: `ModelClient` тогда не кладёт
    /// поле `tools` вовсе, и запрос остаётся ровно таким, каким был
    /// до всей этой затеи.
    static func wire(for settings: Settings) -> [[String: Any]] {
        available(for: settings).map(\.schema.wire)
    }

    static func available(for settings: Settings) -> [AgentTool] {
        allCases.filter { $0.isEnabled(settings) }
    }

    /// Указание модели: где она во времени и как об этом говорить.
    ///
    /// Кладётся системной репликой первым, как и указание про чтение вслух.
    static func instruction(now: Date = Date(), calendar: Calendar = .current) -> String {
        tf("Сейчас %@. Ближайшие дни: %@. Даты и время присылай ровно в виде «%@» по местному времени: без буквы T, без Z, без смещения; день недели сам не считай — бери дату из списка выше. Можно назвать день словом: «сегодня», «завтра», «понедельник». Не выдумывай того, чего не знаешь: чего не хватает — спроси или возьми подходящий инструмент.",
           AgentTime.stamp(now: now, calendar: calendar),
           AgentTime.week(now: now, calendar: calendar),
           AgentTime.format)
    }
}
