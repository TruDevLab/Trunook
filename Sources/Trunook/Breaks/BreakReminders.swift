import AppKit
import TrunookXPC

/// О чём напоминать: сделать перерыв, попить воды, размяться.
enum BreakKind: String, CaseIterable, Identifiable {
    case rest
    case water
    case stretch

    var id: String { rawValue }

    /// Сценка кота, которая идёт вместе с плашкой.
    var act: NotchCritter.Act {
        switch self {
        case .rest: return .rest
        case .water: return .drink
        case .stretch: return .stretch
        }
    }

    /// Название в настройках.
    var title: String {
        switch self {
        case .rest: return t("Перерыв")
        case .water: return t("Вода")
        case .stretch: return t("Разминка")
        }
    }

    /// Текст плашки.
    var message: String {
        switch self {
        case .rest: return t("Пора сделать перерыв")
        case .water: return t("Попейте воды")
        case .stretch: return t("Время размяться")
        }
    }

    var symbol: String {
        switch self {
        case .rest: return "cup.and.saucer.fill"
        case .water: return "drop.fill"
        case .stretch: return "figure.cooldown"
        }
    }

    /// Промежутки на выбор в настройках, в минутах.
    static let choices = [20, 30, 45, 60, 90, 120]

    func minutes(in settings: Settings) -> Int {
        switch self {
        case .rest: return settings.breakReminderMinutes
        case .water: return settings.waterReminderMinutes
        case .stretch: return settings.stretchReminderMinutes
        }
    }

    func setMinutes(_ minutes: Int, in settings: Settings) {
        switch self {
        case .rest: settings.breakReminderMinutes = minutes
        case .water: settings.waterReminderMinutes = minutes
        case .stretch: settings.stretchReminderMinutes = minutes
        }
    }
}

/// Сколько человек проработал с последнего напоминания — чистые правила,
/// под тестом.
///
/// Считается **время за машиной**, а не время по часам: ушёл обедать —
/// напоминать о перерыве, едва вернулся, было бы издёвкой. Поэтому:
///
/// - пока человек трогает мышь или клавиатуру (`presence`), счёт идёт;
/// - отошёл ненадолго — счёт стоит, но не сбрасывается: пока читают,
///   мышь не трогают;
/// - отошёл надолго (`naturalBreak`) — перерыв и разминка уже случились сами,
///   их счёт начинается заново. Воду это не отменяет: отлучка не значит,
///   что человек попил.
struct BreakTracker: Equatable {
    /// Трогал машину меньше двух минут назад — работает.
    static let presence: TimeInterval = 120
    /// Не трогал пять минут — это уже перерыв.
    static let naturalBreak: TimeInterval = 300

    /// Секунды работы с последнего напоминания, по видам.
    private(set) var worked: [BreakKind: TimeInterval] = [:]

    /// Прошло `elapsed` секунд, человек не трогал машину `idle` секунд.
    /// Возвращает виды, которым пора напомнить, в порядке важности.
    mutating func advance(by elapsed: TimeInterval, idle: TimeInterval,
                          minutes: (BreakKind) -> Int) -> [BreakKind] {
        var due: [BreakKind] = []
        for kind in BreakKind.allCases {
            let interval = TimeInterval(minutes(kind)) * 60
            guard interval > 0 else {
                worked[kind] = 0
                continue
            }
            if idle >= Self.naturalBreak, kind != .water {
                worked[kind] = 0
                continue
            }
            if idle < Self.presence {
                worked[kind, default: 0] += elapsed
            }
            if worked[kind, default: 0] >= interval { due.append(kind) }
        }
        return due
    }

    /// Напоминание показано — счёт заново.
    mutating func reset(_ kind: BreakKind) {
        worked[kind] = 0
    }
}

/// Раз в полминуты сверяется с `BreakTracker` и сообщает, кому пора.
///
/// Показывать ли прямо сейчас, решает контроллер: вырез может быть занят
/// панелью или важной плашкой. Пока не показали, вид остаётся должным
/// и спрашивается на следующем тике, — напоминание откладывается, а не
/// теряется.
///
/// Показанное напоминание **ждёт ответа** (`awaiting`): плашка не уходит
/// сама, новые напоминания не выходят, а счёт до следующего такого же
/// начинается с нажатия «готово» или «пропустить», а не с показа.
final class BreakReminders {
    static let tick: TimeInterval = 30

    /// Пора напомнить. Возврат — показано ли: не показано — спросим снова.
    var onDue: ((BreakKind) -> Bool)?

    /// Напоминание на экране, которому ещё не ответили.
    private(set) var awaiting: BreakKind?

    private let settings: Settings
    private var tracker = BreakTracker()
    private var timer: Timer?
    private var lastTick = Date()

    init(settings: Settings) {
        self.settings = settings
    }

    func start() {
        lastTick = Date()
        let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func step() {
        let now = Date()
        // Не больше двух тиков разом: после сна машины прошли часы, но
        // человек их не работал.
        let elapsed = min(now.timeIntervalSince(lastTick), Self.tick * 2)
        lastTick = now
        let settings = self.settings
        let due = tracker.advance(by: elapsed, idle: CritterGate.secondsSinceInput) { $0.minutes(in: settings) }
        // По одному и только когда прошлому ответили: две плашки подряд
        // перебили бы друг друга.
        guard awaiting == nil, let kind = due.first else { return }
        if onDue?(kind) == true {
            awaiting = kind
            DebugLog.write("перерывы: напомнили — \(kind.rawValue)")
        }
    }

    /// Человек ответил. Счёт до следующего напоминания этого вида — с этой минуты.
    func answer(_ kind: BreakKind, done: Bool) {
        tracker.reset(kind)
        if awaiting == kind { awaiting = nil }
        DebugLog.write("перерывы: \(kind.rawValue) — \(done ? "готово" : "пропущено")")
    }

    /// Напоминание показано в обход счёта — отладкой.
    func debugAwait(_ kind: BreakKind) {
        awaiting = kind
    }
}
