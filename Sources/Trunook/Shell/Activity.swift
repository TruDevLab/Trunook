import TrunookXPC
import AppKit
import Foundation

/// Кратковременное событие, которое временно расширяет свёрнутый вырез.
///
/// Содержимое раскладывается по бокам от аппаратной чёлки: слева значок,
/// справа значение. Середину закрывает сам вырез.
struct Activity: Identifiable, Equatable {
    let id = UUID()
    let kind: Kind
    /// Точка отсчёта для анимаций внутри плашки — например, бегущей строки.
    let createdAt = Date()

    enum Kind: Equatable {
        case meeting(item: CalendarItem, minutesBefore: Int)
        /// Ход и итог быстрой команды.
        case command(text: String, state: CommandState)
        /// Что-то скопировали. По этой плашке открывается история буфера.
        ///
        /// Записью целиком, а не парой «текст и вид»: с плашки скопированное
        /// можно отложить в заметки, а для этого нужен полный текст записи,
        /// не однострочная выжимка для показа. Двум спискам полей разойтись
        /// негде, когда список один.
        case clipboard(entry: ClipboardEntry)
        /// На полке лежат файлы. Держится, пока полка не опустеет.
        case shelf(count: Int)
        /// Вышло время таймера. Текст готовит контроллер: плашке незачем
        /// знать про помидоры.
        case timer(text: String)
        /// Погода: текст и значок готовит служба, плашка их только рисует.
        case weather(text: String, symbol: String)
        /// Экран перестали или снова стали гасить.
        case caffeine(change: CaffeineChange)
        /// Данных не несёт намеренно: сведения о треке доезжают порциями,
        /// и снимок, сделанный в момент переключения, застывал бы с прежним
        /// исполнителем и без обложки. Плашка читает их живьём.
        case trackChanged
        case powerConnected(percentage: Int)
        case powerDisconnected(percentage: Int)
        case lowBattery(percentage: Int)
        /// Обновление скачано и проверено, осталось нажать. Номер версии
        /// строкой: плашке незачем знать про выпуск целиком.
        case update(version: String)
        /// Собрана сводка новостей. По плашке она открывается.
        case digestReady(entries: Int)
        /// На сайте изменилось то, за чем следили. Кнопка открывает сайт.
        case siteChanged(name: String, text: String, url: URL)
        /// Пора сделать перерыв, попить воды или размяться. Вместе с плашкой
        /// выходит котик и показывает, что делать.
        case breakReminder(BreakKind)
        /// Наступило событие обратного отсчёта. Вместе с плашкой — залп
        /// конфетти из чёлки.
        case countdownReached(title: String)
        /// Записан заход воды. Итог дня плашка берёт у журнала живьём:
        /// в случае она несёт только что записанное.
        case waterLogged(portion: Int)
        /// Модель просит разрешения записать: встречу, напоминание, заметку.
        ///
        /// Предложением целиком, а не парой строк: нажатие уходит в тот же
        /// `confirmPendingAction`, что и у карточки в панели, и два описания
        /// одного предложения разошлись бы на первой же правке.
        case agentConfirm(PendingAction)
        /// Пора сделать то, о чём просили напомнить. Отдельно от встречи:
        /// у напоминания есть «готово», а у встречи его нет.
        case reminderDue(item: CalendarItem)
        /// Входящий звонок в чужом приложении.
        case incomingCall(CallInvite)
        /// Уведомление, присланное снаружи — скриптом, хуком, автоматикой.
        case external(ExternalNotice)
    }

    /// Чем важнее событие, тем выше приоритет. Событие с приоритетом ниже
    /// текущего не показывается вовсе: показать его с опозданием хуже,
    /// чем не показать — предупреждение о разряде, всплывшее через минуту
    /// после смены трека, только сбивает с толку.
    var priority: Int {
        switch kind {
        // Выше всего то, что **ждёт ответа прямо сейчас** и ждать не может:
        // звонок звонит двадцать секунд, и смена трека, перебившая его,
        // стоит пропущенного разговора.
        case .incomingCall: return 7
        // Следом — то, что ждёт ответа, но дождётся: предложение модели
        // и присланное снаружи висят без срока, и перебить их нельзя,
        // иначе вопрос исчезнет неотвеченным.
        case .agentConfirm: return 6
        case .external: return 6
        // Отклик на нажатие клавиши важнее всего остального: пользователь
        // ждёт его прямо сейчас и связывает со своим действием.
        case .command: return 5
        // Вровень со встречей: о напоминании просили сами, и его пропуск
        // так же необратим.
        case .reminderDue: return 4
        // Вровень со встречей: вышедшее время — то, ради чего таймер
        // и заводили, и пропустить его значит обессмыслить всю затею.
        case .timer: return 4
        // Встреча следом: её пропуск нельзя отменить, в отличие
        // от незамеченной смены трека или уровня заряда.
        case .meeting: return 4
        // Отклик на ⌘C: человек только что нажал клавиши и связывает
        // плашку со своим действием — но пропущенная встреча дороже.
        case .clipboard: return 3
        // Вровень с копированием: плашка полки тоже отклик на действие руками.
        case .shelf: return 3
        case .lowBattery: return 3
        // Вровень с копированием: это отклик на нажатие, и человек связывает
        // плашку со своим действием.
        case .caffeine: return 3
        // Ниже разряда: дождь через два часа подождёт, а батарея — нет.
        case .weather: return 2
        // Вровень с погодой. Обновление ждало сутки и подождёт ещё девять
        // секунд; встреча и вышедшее время — не подождут.
        case .update: return 2
        // Сводка — как обновление: подождёт, а не пропадёт — метка в чёлке
        // держится, пока её не откроют.
        case .digestReady: return 2
        // Цена изменилась сейчас, и через час может вернуться: выше сводки.
        case .siteChanged: return 3
        case .powerConnected, .powerDisconnected: return 2
        // Вровень с погодой: напоминание подождёт, пока вырез освободится.
        case .breakReminder: return 2
        // Ответ на только что сделанное нажатие: подождать ему нечего,
        // но и перебивать разряд батареи незачем.
        case .waterLogged: return 2
        // Вровень со встречей: событие ждали днями, и наступает оно один раз.
        case .countdownReached: return 4
        case .trackChanged: return 1
        }
    }

    var duration: TimeInterval {
        switch kind {
        case let .command(_, state):
            switch state {
            // Пока команда идёт, плашка висит: локальная модель на холодную
            // думает почти минуту, и молчаливое ожидание выглядит как отказ.
            // Снимет её итоговая плашка — у неё тот же приоритет.
            case .running: return 300
            // Ошибку читают, успех только замечают.
            case .failed: return 5
            case .done: return 3
            }
        // Дольше прочих: нужно время прочитать название и нажать «подключиться».
        case .meeting: return 9
        // Столько же: об окончании надо успеть узнать, даже отвернувшись.
        case .timer: return 9
        // Дольше прочих мелких: по плашке нужно успеть попасть курсором,
        // чтобы открыть историю.
        case .clipboard: return 4
        // Без срока: висит, пока на полке что-то есть.
        case .shelf: return .infinity
        case .lowBattery: return 4
        case .weather: return 4
        // Куда дольше прочих: в плашке кнопка, и в неё надо успеть попасть
        // курсором. Четырёх секунд на это не хватает, а наведение на вырез
        // уберёт её в любом случае.
        case .update: return 30
        // Столько же и по той же причине: по плашке надо успеть нажать.
        case .digestReady, .siteChanged: return 30
        // Столько же, сколько смене трека, и по той же причине: нажимают
        // по чашке в раскрытой панели, а плашку видно только после того,
        // как курсор ушёл, — ей нужно время пережить этот уход.
        case .caffeine: return 4
        case .powerConnected, .powerDisconnected: return 2.5
        // Столько же, сколько идёт сценка кота, и чуть дольше: котик
        // выходит из-за края плашки, и уйди она раньше — прятаться ему
        // было бы не за что.
        // Без срока: висит, пока человек не ответит «готово» или «пропустить»,
        // — и следующий отсчёт начинается только с ответа.
        case .breakReminder: return .infinity
        // Коротко: человек уже знает, что записал, — плашка лишь называет
        // итог дня.
        case .waterLogged: return 3.5
        // Полминуты — и вопрос уходит с глаз, но не пропадает: пока ответа
        // нет, плашка возвращается, как только вырез освободится
        // (`keepWaitingActivities`). Вечная плашка заняла бы вырез насмерть:
        // у неё высший приоритет, и ни встреча, ни таймер под ней
        // не показались бы вовсе — поймано на своём же снимке, где
        // напоминание «отброшено: показывается более важное».
        case .agentConfirm: return 30
        // Столько же и по той же причине, но возвращать нечего: присланное
        // ждёт ответа, и возврат им занимается сам `NotifyInbox`.
        case let .external(notice): return notice.waitsForAnswer ? 30 : notice.hold
        // Дольше обычного звонка: плашку снимает сам звонок — ответом,
        // отбоем или тишиной на том конце, — а срок тут страховка на случай,
        // если окно закрылось молча и наблюдатель об этом не сказал.
        case .incomingCall: return 45
        // Напоминание не возвращается: оно и так стоит в «Напоминаниях»
        // и позвонит само. Плашка — способ ответить не отвлекаясь, а не
        // единственное место, где о нём знают.
        case .reminderDue: return 30
        // Долго: наступившее событие не пропускают, отвернувшись на минуту.
        // Убирает крестик.
        case .countdownReached: return 60
        // Дольше остальных: длинному названию нужно время проехать.
        case .trackChanged: return 4
        }
    }


    /// По плашке можно нажать. Такие не убираются при наведении курсора:
    /// иначе до них было бы физически не дотянуться.
    var isInteractive: Bool {
        switch kind {
        // Обновление здесь по той же причине, что буфер и полка: в плашке
        // кнопка, и убирайся плашка от первого же движения курсора — до кнопки
        // было бы не дотянуться.
        // Напоминание и наступившее событие — из-за кнопок: не держись они
        // при наведении, до «готово» и крестика было бы не дотянуться.
        case .clipboard, .shelf, .update, .digestReady, .siteChanged, .breakReminder, .countdownReached,
             .agentConfirm, .reminderDue, .incomingCall, .external: return true
        default: return false
        }
    }

    static func == (lhs: Activity, rhs: Activity) -> Bool {
        lhs.id == rhs.id
    }
}

/// Что случилось с удержанием экрана.
///
/// Отдельным типом, а не флагом «включено», потому что случаев три, а не два:
/// истёкший срок — это не то же самое, что выключение рукой. Человек его
/// не нажимал, и не сказать ему об этом значит оставить его гадать, почему
/// экран вдруг снова гаснет.
enum CaffeineChange: Equatable {
    /// Включили. Минуты — заданный срок; ноль означает «без ограничения».
    case on(minutes: Int)
    case off
    case expired
}

enum CommandState: Equatable {
    case running
    case done
    case failed
}

extension Activity.Kind {
    /// Короткое имя для журнала отладки.
    var label: String {
        switch self {
        case .command: return "команда"
        case .clipboard: return "копирование"
        case .shelf: return "полка"
        case .timer: return "таймер"
        case .weather: return "погода"
        case .caffeine: return "бодрость"
        case .meeting: return "встреча"
        case .trackChanged: return "смена трека"
        case .powerConnected: return "зарядка подключена"
        case .powerDisconnected: return "зарядка отключена"
        case .lowBattery: return "низкий заряд"
        case .update: return "обновление"
        case .digestReady: return "сводка"
        case .siteChanged: return "сайт изменился"
        case .breakReminder: return "перерыв"
        case .waterLogged: return "вода записана"
        case .countdownReached: return "событие наступило"
        case .agentConfirm: return "предложение модели"
        case .reminderDue: return "напоминание"
        case .incomingCall: return "входящий звонок"
        case .external: return "присланное уведомление"
        }
    }
}

/// Решает, какое событие показывать прямо сейчас.
final class ActivityCenter: ObservableObject {
    @Published private(set) var current: Activity?

    private var dismissTimer: Timer?
    private let settings: Settings

    /// Что играет прямо сейчас — для объявления о смене трека.
    ///
    /// Замыканием, а не полем: плашка смены трека намеренно не несёт данных
    /// (сведения доезжают порциями и снимок застывал бы с прежним
    /// исполнителем), и текст для неё читается живьём в момент показа.
    var nowPlaying: (() -> NowPlaying?)?

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    /// Сказать вслух то, что показано.
    ///
    /// Плашка — сообщение о состоянии: она не забирает фокус и ничего
    /// не спрашивает. Для того, кто её не видит, она до сих пор не значила
    /// ровно ничего: вышло время таймера, разрядилась батарея, началась
    /// встреча, команда упала с ошибкой — всё это появлялось на экране молча.
    ///
    /// Одна точка на все четырнадцать видов событий: сюда они и так все
    /// приходят, и объявлять их по месту значило бы четырнадцать раз забыть.
    private func announce(_ activity: Activity) {
        let text = ActivityView.text(for: activity.kind, track: nowPlaying?())
        guard !text.isEmpty else { return }
        // Важное перебивает начатую фразу, остальное дожидается своей очереди:
        // разряженную батарею нельзя ставить в хвост за сменой трека.
        let level: NSAccessibilityPriorityLevel = activity.priority >= 4 ? .high : .medium
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: level.rawValue,
            ]
        )
    }

    /// Сколько плашка висит на самом деле: свой срок, растянутый настройкой.
    ///
    /// Отдельно от `Activity.duration` потому, что тот отвечает на вопрос
    /// «сколько этому событию нужно по существу» — девять секунд встрече,
    /// две смене питания, — а настройка на все эти сроки смотрит одинаково.
    /// Смешать их значило бы прописать множитель в четырнадцати местах.
    func hold(for activity: Activity) -> TimeInterval {
        let base = activity.duration
        guard base.isFinite else { return base }
        let scale = settings.activityHold
        guard scale != 1 else { return base }
        // Ноль — «пока не уберу»: убирает такую плашку наведение на вырез.
        guard scale > 0 else { return .infinity }
        return base * TimeInterval(scale)
    }

    func present(_ kind: Activity.Kind) {
        let activity = Activity(kind: kind)
        if let current, current.priority > activity.priority {
            DebugLog.write("событие \(kind.label) отброшено: показывается более важное")
            return
        }
        show(activity)
    }

    /// Показать событие вместо своего же, даже если то важнее.
    ///
    /// Нужна одному случаю, но случай настоящий: ручная проверка обновлений
    /// показывает «Проверяю…» плашкой команды (приоритет 5, висит до пяти
    /// минут), а готовое обновление — своей плашкой с приоритетом 2. Обычное
    /// правило отбрасывало готовое как менее важное, и человек пять минут
    /// смотрел на «скачиваю…» над давно скачанным — в журнале так и стояло:
    /// «событие обновление отброшено: показывается более важное».
    ///
    /// Заменяется только то, что узнаёт `replacing`: чужую плашку этим путём
    /// перебить нельзя.
    func present(_ kind: Activity.Kind, replacing: (Activity.Kind) -> Bool) {
        if let current, replacing(current.kind) {
            show(Activity(kind: kind))
            return
        }
        present(kind)
    }

    // MARK: - Пауза под курсором

    /// Сколько плашка висит после того, как курсор ушёл, если своего срока
    /// у неё оставалось меньше.
    ///
    /// Без запаса плашка пропадала от случайного движения: навёл, чтобы
    /// прочитать или нажать, чуть промахнулся краем — и её уже нет.
    static let graceAfterHover: TimeInterval = 5

    /// Сколько оставалось плашке, когда её поставили на паузу.
    private var remainingWhilePaused: TimeInterval?
    /// Когда сработает таймер — чтобы знать остаток при паузе.
    private var expiresAt: Date?

    /// Остановить или продолжить отсчёт плашки.
    ///
    /// Пока курсор над чёлкой или над самой плашкой, срок стоит: под рукой
    /// событие не истекает. Отпустили — отсчёт идёт дальше, но не меньше
    /// `graceAfterHover`.
    func hold(_ paused: Bool) {
        guard let current else { return }
        if paused {
            guard remainingWhilePaused == nil, let expiresAt else { return }
            remainingWhilePaused = max(0, expiresAt.timeIntervalSinceNow)
            dismissTimer?.invalidate()
            dismissTimer = nil
            self.expiresAt = nil
        } else {
            guard let left = remainingWhilePaused else { return }
            remainingWhilePaused = nil
            schedule(current, after: max(left, Self.graceAfterHover))
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        remainingWhilePaused = nil
        expiresAt = nil
        guard let current else { return }
        DebugLog.write("событие \(current.kind.label) убрано досрочно")
        self.current = nil
    }

    private func show(_ activity: Activity) {
        dismissTimer?.invalidate()
        dismissTimer = nil
        remainingWhilePaused = nil
        expiresAt = nil
        current = activity
        announce(activity)

        // Плашка полки висит без срока: она сообщает не о событии, а о том,
        // что файлы отложены и о них не забыли. Убирает её крестик или
        // опустевшая полка.
        let hold = hold(for: activity)
        guard hold.isFinite else {
            DebugLog.write("событие \(activity.kind.label) показано без срока")
            return
        }
        DebugLog.write("событие \(activity.kind.label) показано на \(hold) с")

        schedule(activity, after: hold)
    }

    private func schedule(_ activity: Activity, after seconds: TimeInterval) {
        dismissTimer?.invalidate()
        expiresAt = Date().addingTimeInterval(seconds)
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self, self.current == activity else { return }
            DebugLog.write("событие \(activity.kind.label) истекло")
            self.current = nil
            self.expiresAt = nil
        }
        // .common, иначе таймер замирает, пока пользователь тянет ползунок
        // или держит открытым меню.
        RunLoop.main.add(timer, forMode: .common)
        dismissTimer = timer
    }
}
