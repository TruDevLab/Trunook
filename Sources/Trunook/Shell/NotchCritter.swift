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
        /// Котик перебирается через угол и бегает вверх ногами по нижней
        /// кромке чёлки — туда и обратно.
        case upside
        /// Из-за чёлки выкатывается клубок, котик бежит за ним.
        case yarn
        /// Злой котик выбегает, лежит буханкой и трясётся: во все стороны
        /// летят искры, от головы — ругательства значками.
        case angry
        /// Котик выбегает, лежит буханкой, хмурит брови галочкой и грозит
        /// кулаком.
        case fist
        /// Котик выбегает, садится и шлёт поцелуйчик — летит сердечко.
        case kiss
        /// Котик выбегает из-за одного края, кружится под чёлкой за своим
        /// хвостом и убегает за другой край.
        case chase
        /// Котик выбегает и гоняется за курсором: догнав, замедляется
        /// и прыгает на него; через несколько секунд убегает.
        case hunt
        /// Котик выбегает, надевает длинные узкие очки — с линзы срывается
        /// блик звёздочкой — и убегает прямо в них.
        case cool
        /// Котик выбегает, ложится и закуривает: огонёк, мигающий уголёк
        /// на затяжках, дым.
        case smoke

        // Праздничные — только в свой день, см. `CritterHoliday`.
        /// Новый год: котик в красной шапке и с белой бородой ныряет в сугробы под снегом из чёлки.
        case winter
        /// День защиты детей: за котиком выбегают три котёнка и кружат вокруг него.
        case kittens
        /// 8 Марта: котик выносит под чёлку букет и протягивает его.
        case flowers
        /// 23 Февраля: котик выезжает на танке, стреляет и уезжает.
        case tank
        /// Пасха: котик выкатывает крашеное яйцо, за ним скачет кролик; из яйца вылупляется цыплёнок.
        case easter
        /// Хэллоуин: котик с тыквой на голове говорит «BOOO!», из чёлки вылетают призраки.
        case pumpkin
        /// 14 Февраля: чёрный и белый котики встречаются под чёлкой и целуются, сыплются сердечки.
        case valentine
        /// 9 Мая: котик бежит, за ним тянется георгиевская ленточка.
        case ribbon
        /// Китайский Новый год: котик летит на золотом драконе.
        case dragon
        /// День космонавтики: котик вылетает на ракете, делает петлю и улетает в чёлку.
        case rocket

        var duration: TimeInterval {
            switch self {
            case .eyes: return 5
            case .tail: return 4.2
            case .run: return 7
            case .ears: return 4.5
            case .paw: return 4.5
            case .sleep: return 9.2
            case .upside: return 6.6
            case .yarn: return 6.8
            case .angry: return 6.4
            case .fist: return 6.6
            case .kiss: return 6.8
            case .chase: return 7.2
            case .hunt: return HuntState.huntTime + 2
            case .cool: return 7
            case .smoke: return 8
            case .winter: return 8.0
            case .kittens: return 9.0
            case .flowers: return 7.2
            case .tank: return 6.9
            case .easter: return 13.0
            case .pumpkin: return 7.0
            case .valentine: return 8.0
            case .ribbon: return 6.2
            case .dragon: return 7.0
            case .rocket: return 4.4
            }
        }

        /// Сценки, где котик смотрит на курсор.
        var followsCursor: Bool { self == .eyes || self == .paw || self == .hunt }
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
    /// Где курсор: от середины верхней кромки выреза, в точках, вниз
    /// по экрану — положительный `y`. Нужен охоте.
    @Published var pointer: CGPoint = CGPoint(x: 0, y: 200)
    /// Погоня идёт шагами от кадра к кадру: где котик сейчас, зависит
    /// от того, куда водили курсор, а не только от времени.
    private var hunt = HuntState()
    /// У какого края чёлки сценка: −1 левый, 1 правый. Выбирается заново
    /// на каждую сценку — котик живёт по обе стороны выреза.
    private(set) var side: CGFloat = 1

    /// Пора бы сыграть. Можно ли — решает тот, кто знает, что на экране.
    var onDue: (() -> Void)?

    private var dueTimer: Timer?
    private var endTimer: Timer?
    private var last: Act?

    /// Как часто выходить — спрашивается на каждую сценку, чтобы смена
    /// настройки действовала сразу, без перезапуска.
    var frequency: () -> CritterFrequency = { .normal }

    /// Первый выход после запуска — скоро, а не через полный интервал:
    /// приложение перезапускается при каждом обновлении, и при интервале
    /// в полчаса кот не выходил месяцами у того, кто часто обновляется.
    func start() {
        schedule(after: CritterSchedule.firstDelay())
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
    /// Сценка вызвана отладкой: по её концу штатный выход не переносится.
    private var playingDebug = false

    /// - Parameter debug: вызвана отладочным событием. Штатное расписание
    ///   она не трогает: иначе, пока сценки смотрят по одной, кот сам
    ///   не выходил бы вовсе — каждая отладочная заводила отсчёт заново.
    func play(_ chosen: Act? = nil, debug: Bool = false) {
        let next = chosen ?? CritterSchedule.pick(avoiding: last, holidays: CritterHoliday.on(Date()))
        playingDebug = debug
        last = next
        endTimer?.invalidate()
        gaze = .zero
        squints = false
        startedAt = Date()
        side = Bool.random() ? 1 : -1
        hunt = HuntState()
        act = next
        DebugLog.write("кот: \(next.rawValue)")
        let timer = Timer(timeInterval: next.duration, repeats: false) { [weak self] _ in
            self?.finish()
        }
        RunLoop.main.add(timer, forMode: .common)
        endTimer = timer
    }

    /// Шаг погони к мигу `t` сценки. Зовёт холст на каждом кадре.
    func advanceHunt(to t: TimeInterval, start: CGPoint, target: CGPoint,
                     area: CGRect, homes: [CGPoint]) -> HuntState {
        hunt.advance(to: t, start: start, target: target, area: area, homes: homes)
        return hunt
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
        // Отладочная сценка при заведённом штатном выходе его не переносит.
        if playingDebug, dueTimer != nil {
            playingDebug = false
            return
        }
        playingDebug = false
        schedule(after: CritterSchedule.nextDelay(frequency()))
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

/// Погоня за курсором — шагами, под тестом.
///
/// Котик бежит к курсору; близко — замедляется, подкрадываясь, и прыгает
/// на него. После прыжка сидит, пока курсор рядом, — иначе прыгал бы
/// на месте без конца. Курсор за пределами полосы, где котик бегает, —
/// садится как можно ближе и ждёт. Вышло время — убегает за ближний край
/// выреза.
struct HuntState {
    enum Pose { case running, leaping, sitting }

    static let huntTime: TimeInterval = 6
    static let speed: CGFloat = 150
    /// Ближе этого котик сбавляет ход — подкрадывается.
    static let slowWithin: CGFloat = 70
    /// С такого расстояния прыгает.
    static let leapWithin: CGFloat = 26
    static let leapTime: TimeInterval = 0.45
    static let landTime: TimeInterval = 0.6

    private(set) var position: CGPoint?
    private(set) var facingRight = true
    private(set) var pose: Pose = .running
    private(set) var visible = true
    private var lastTime: TimeInterval?
    private var leap: (from: CGPoint, to: CGPoint, start: TimeInterval)?
    private var landedAt: (point: CGPoint, until: TimeInterval)?
    private var home: CGPoint?

    /// Где рисовать: в прыжке котик летит дугой над прямой.
    var drawn: CGPoint {
        guard let position else { return .zero }
        return CGPoint(x: position.x, y: position.y - lift)
    }
    private var lift: CGFloat = 0

    mutating func advance(to t: TimeInterval, start: CGPoint, target rawTarget: CGPoint,
                          area: CGRect, homes: [CGPoint]) {
        var position = self.position ?? start
        let dt = CGFloat(min(0.1, max(0, t - (lastTime ?? t))))
        lastTime = t
        lift = 0
        defer { self.position = position }

        // Убегает.
        if t >= Self.huntTime, leap == nil {
            let goal = home ?? homes.min { distance($0, position) < distance($1, position) } ?? start
            home = goal
            pose = .running
            let left = distance(goal, position)
            if left < 2 { visible = false; return }
            facingRight = goal.x >= position.x
            position = move(position, toward: goal, by: 220 * dt)
            return
        }

        // В прыжке.
        if let leap {
            let k = min(1, (t - leap.start) / Self.leapTime)
            position = CGPoint(x: leap.from.x + (leap.to.x - leap.from.x) * CGFloat(k),
                               y: leap.from.y + (leap.to.y - leap.from.y) * CGFloat(k))
            lift = 16 * CGFloat(sin(k * .pi))
            pose = .leaping
            if k >= 1 {
                self.leap = nil
                landedAt = (leap.to, t + Self.landTime)
                pose = .sitting
            }
            return
        }

        let target = CGPoint(x: min(max(rawTarget.x, area.minX), area.maxX),
                             y: min(max(rawTarget.y, area.minY), area.maxY))
        let reachable = target == rawTarget

        // Приземлился: сидит, пока курсор рядом с местом прыжка.
        if let landed = landedAt {
            if t < landed.until || distance(target, landed.point) < 30 {
                pose = .sitting
                facingRight = target.x >= position.x
                return
            }
            landedAt = nil
        }

        let gap = distance(target, position)
        if reachable, gap < Self.leapWithin, t > 0.8 {
            leap = (position, target, t)
            facingRight = target.x >= position.x
            pose = .leaping
            return
        }
        guard gap > 2 else {
            pose = .sitting
            return
        }
        // Далеко — во весь дух, близко — подкрадывается.
        let pace = gap > Self.slowWithin ? Self.speed : max(40, Self.speed * gap / Self.slowWithin)
        if abs(target.x - position.x) > 1 { facingRight = target.x >= position.x }
        position = move(position, toward: target, by: pace * dt)
        pose = .running
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func move(_ from: CGPoint, toward to: CGPoint, by step: CGFloat) -> CGPoint {
        let gap = distance(from, to)
        guard gap > step, gap > 0 else { return to }
        return CGPoint(x: from.x + (to.x - from.x) * step / gap, y: from.y + (to.y - from.y) * step / gap)
    }
}

/// Как часто кот выходит в чёлку.
enum CritterFrequency: String, CaseIterable, Identifiable {
    case often
    case normal
    case rare

    var id: String { rawValue }

    /// Промежуток между сценками.
    var interval: ClosedRange<TimeInterval> {
        switch self {
        case .often: return 2 * 60...4 * 60
        case .normal: return 5 * 60...10 * 60
        case .rare: return 20 * 60...40 * 60
        }
    }

    var title: String {
        switch self {
        case .often: return t("Часто")
        case .normal: return t("Обычно")
        case .rare: return t("Редко")
        }
    }

    var hint: String {
        switch self {
        case .often: return t("Раз в 2–4 минуты.")
        case .normal: return t("Раз в 5–10 минут.")
        case .rare: return t("Раз в 20–40 минут.")
        }
    }
}

/// Расписание и выбор сценки — чистые функции, под тестом.
enum CritterSchedule {
    /// После запуска — через одну-три минуты.
    static let first: ClosedRange<TimeInterval> = 60...180
    /// Не вышло — через минуту-две: вырез занят обычно ненадолго.
    static let retry: ClosedRange<TimeInterval> = 60...120

    static func firstDelay() -> TimeInterval { .random(in: first) }
    static func nextDelay(_ frequency: CritterFrequency = .normal) -> TimeInterval { .random(in: frequency.interval) }
    static func retryDelay() -> TimeInterval { .random(in: retry) }

    /// Обычные сценки — без праздничных: те выходят только в свой день.
    static var everyday: [NotchCritter.Act] {
        NotchCritter.Act.allCases.filter { CritterHoliday.act(for: $0) == nil }
    }

    /// Какую сценку сыграть. В праздник — через раз праздничную, иначе
    /// праздник надоел бы к обеду, а обычный котик пропал бы на весь день.
    static func pick(avoiding last: NotchCritter.Act?, holidays: [CritterHoliday] = []) -> NotchCritter.Act {
        let festive = holidays.map(\.act).filter { $0 != last }
        if !festive.isEmpty, Bool.random() {
            return festive.randomElement() ?? .eyes
        }
        let pool = everyday.filter { $0 != last }
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

    /// Человек за машиной, если трогал её меньше трёх минут назад. Иначе
    /// смотреть некому, а сценка ушла бы впустую. Минуты было мало: пока
    /// читают, мышь не трогают, и кот не выходил как раз тогда, когда
    /// на экран смотрят.
    static let presenceWindow: TimeInterval = 180

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
