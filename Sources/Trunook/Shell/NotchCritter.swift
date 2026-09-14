import TrunookXPC
import AppKit
import Combine

/// Кот, который живёт в чёлке.
///
/// Изредка, когда вырезу нечего показывать, он разыгрывает короткую сценку:
/// выглядывает из-под чёлки, дёргает ухом из-за её края, ловит лапой курсор,
/// зевает, свешивает хвост, выбегает на полосу меню, спит, гоняет клубок,
/// сердится и грозит кулаком.
/// Настройка «Оживлять вырез», включена по умолчанию.
///
/// Здесь — только когда и что. Рисует `CritterView`, решает, можно ли
/// играть прямо сейчас, контроллер: он знает, что показывает вырез.
final class NotchCritter: ObservableObject {
    enum Act: String, CaseIterable {
        /// Котик выглядывает из-под кромки чёлки и смотрит на курсор.
        case eyes
        /// Хвост свешивается из-под чёлки и виляет.
        case tail
        /// Котик выбегает из-за края чёлки, лежит буханкой и убегает обратно.
        case run
        /// Голова выглядывает из-за бокового края чёлки, дёргает ухом.
        case ears
        /// Лапа свисает из-под чёлки и ловит курсор.
        case paw
        /// Котик выбегает, засыпает буханкой — над ним «Z», — просыпается.
        case sleep
        /// Мордочка из-под чёлки широко зевает.
        case yawn
        /// Из-за чёлки выкатывается клубок, котик бежит за ним.
        case yarn
        /// Злой котик выбегает, садится и грозит кулаком.
        case angry

        var duration: TimeInterval {
            switch self {
            case .eyes: return 5
            case .tail: return 4.2
            case .run: return 7
            case .ears: return 4.5
            case .paw: return 4.5
            case .sleep: return 9.2
            case .yawn: return 4.6
            case .yarn: return 6.8
            case .angry: return 6.4
            }
        }

        /// Сценки, где котик смотрит на курсор.
        var followsCursor: Bool { self == .eyes || self == .paw || self == .yawn }
    }

    /// Идущая сценка. `nil` — кот спит.
    @Published private(set) var act: Act?
    /// Когда сценка началась: по времени от начала считаются все кадры.
    private(set) var startedAt = Date()
    /// Куда смотрят глаза: смещение курсора от середины чёлки, от −1 до 1
    /// по каждой оси.
    @Published var gaze: CGPoint = .zero
    /// Курсор совсем рядом — кот щурится.
    @Published var squints = false
    /// У какого края чёлки сценка: −1 левый, 1 правый. Выбирается заново
    /// на каждую сценку — котик живёт по обе стороны выреза.
    private(set) var side: CGFloat = 1

    /// Пора бы сыграть. Можно ли — решает тот, кто знает, что на экране.
    var onDue: (() -> Void)?

    private var dueTimer: Timer?
    private var endTimer: Timer?
    private var last: Act?

    func start() {
        schedule(after: CritterSchedule.nextDelay())
    }

    func stop() {
        dueTimer?.invalidate()
        dueTimer = nil
        endTimer?.invalidate()
        endTimer = nil
        act = nil
    }

    /// Сейчас было нельзя — спросить ещё раз скоро, а не через полчаса:
    /// иначе кот, пропустивший свой миг из-за плашки, молчал бы до вечера.
    func retrySoon() {
        schedule(after: CritterSchedule.retryDelay())
    }

    /// Сыграть сценку. Без выбора — случайную, не ту же, что в прошлый раз.
    func play(_ chosen: Act? = nil) {
        let next = chosen ?? CritterSchedule.pick(avoiding: last)
        last = next
        endTimer?.invalidate()
        gaze = .zero
        squints = false
        startedAt = Date()
        side = Bool.random() ? 1 : -1
        act = next
        DebugLog.write("кот: \(next.rawValue)")
        let timer = Timer(timeInterval: next.duration, repeats: false) { [weak self] _ in
            self?.finish()
        }
        RunLoop.main.add(timer, forMode: .common)
        endTimer = timer
    }

    /// Сценку перебили: пришла плашка, навели курсор, выключили настройку.
    func cancel() {
        guard act != nil else { return }
        finish()
        DebugLog.write("кот: сценка прервана")
    }

    private func finish() {
        endTimer?.invalidate()
        endTimer = nil
        act = nil
        schedule(after: CritterSchedule.nextDelay())
    }

    private func schedule(after delay: TimeInterval) {
        dueTimer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.dueTimer = nil
            self?.onDue?()
        }
        RunLoop.main.add(timer, forMode: .common)
        dueTimer = timer
    }
}

/// Расписание и выбор сценки — чистые функции, под тестом.
enum CritterSchedule {
    /// Между сценками — от двадцати до сорока минут. Чаще — надоест,
    /// реже — забудется, что кот вообще есть.
    static let interval: ClosedRange<TimeInterval> = 20 * 60...40 * 60
    static let retry: ClosedRange<TimeInterval> = 2 * 60...5 * 60

    static func nextDelay() -> TimeInterval { .random(in: interval) }
    static func retryDelay() -> TimeInterval { .random(in: retry) }

    static func pick(avoiding last: NotchCritter.Act?) -> NotchCritter.Act {
        let pool = NotchCritter.Act.allCases.filter { $0 != last }
        return pool.randomElement() ?? .eyes
    }
}

/// Можно ли коту выйти прямо сейчас.
struct CritterGate: Equatable {
    var enabled: Bool
    /// Вырезу нечего показывать: ни полосок, ни плашек, ни панелей.
    var isIdle: Bool
    /// Над настоящей чёлкой. На экране без неё в покое не рисуется ничего,
    /// и глазам с хвостом не из чего выглядывать.
    var hasNotch: Bool
    var reduceMotion: Bool
    var lowPower: Bool
    /// Сколько секунд назад человек трогал мышь или клавиатуру.
    var idleSeconds: TimeInterval
    /// Спереди окно на весь экран — фильм, презентация, игра.
    var fullScreen: Bool

    /// Человек за машиной, если трогал её меньше минуты назад. Иначе
    /// смотреть некому, а сценка ушла бы впустую.
    static let presenceWindow: TimeInterval = 60

    var canPlay: Bool {
        enabled && isIdle && hasNotch && !reduceMotion && !lowPower
            && idleSeconds < Self.presenceWindow && !fullScreen
    }

    /// Что мешает прямо сейчас — для журнала.
    var reason: String {
        if !enabled { return "выключено" }
        if !isIdle { return "вырез занят" }
        if !hasNotch { return "нет чёлки" }
        if reduceMotion { return "уменьшено движение" }
        if lowPower { return "энергосбережение" }
        if idleSeconds >= Self.presenceWindow { return "никого нет" }
        if fullScreen { return "окно на весь экран" }
        return "можно"
    }

    /// Секунды с последнего нажатия или движения мыши.
    static var secondsSinceInput: TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: UInt32.max)!
        )
    }

    /// Окно переднего приложения закрывает экран целиком.
    static func isFullScreen(on screen: NSScreen?) -> Bool {
        guard let screen, let front = NSWorkspace.shared.frontmostApplication else { return false }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windows.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { return false }
            return bounds["Width"] == screen.frame.width && bounds["Height"] == screen.frame.height
        }
    }
}
