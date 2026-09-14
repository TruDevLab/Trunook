import TrunookXPC
import Foundation

/// Какую погодную сценку играть и стоит ли — чистые правила, под тестом.
enum WeatherScenePick {
    /// Ветрено — от 30 км/ч: пять баллов, ветки качаются, пыль летит.
    static let windyFrom: Double = 30
    /// Затихло — ниже 22 км/ч. Разрыв между порогами нужен, чтобы ветер
    /// около 30 не включал и не выключал «ветрено» на каждой проверке.
    static let calmBelow: Double = 22

    /// Смена ясно — облачно случается по нескольку раз за час, и сценка
    /// на каждую надоела бы. Такие — не чаще раза в 40 минут.
    static let quietGap: TimeInterval = 40 * 60

    static func isWindy(wind: Double, wasWindy: Bool) -> Bool {
        wasWindy ? wind >= calmBelow : wind >= windyFrom
    }

    /// Осадки важнее ветра: под дождём ветер не главное, что видно в окно.
    static func scene(condition: WeatherCondition, windy: Bool) -> WeatherArt.Scene {
        switch condition {
        case .drizzle: return .drizzle
        case .rain: return .rain
        case .snow: return .snow
        case .thunder: return .thunder
        case .clear, .cloudy, .fog:
            if windy { return .wind }
            switch condition {
            case .clear: return .sun
            case .fog: return .fog
            default: return .clouds
            }
        }
    }

    /// Начало осадков и грозы показываются всегда: ради них сценки
    /// и заводились. Остальное — не чаще `quietGap`.
    static func shouldPlay(_ scene: WeatherArt.Scene, lastPlayedAt: Date?, now: Date) -> Bool {
        switch scene {
        case .drizzle, .rain, .snow, .thunder: return true
        case .sun, .clouds, .fog, .wind:
            guard let lastPlayedAt else { return true }
            return now.timeIntervalSince(lastPlayedAt) >= quietGap
        }
    }
}

/// Идущая погодная сценка. Когда её можно играть, решает контроллер —
/// он знает, что показывает вырез; здесь — очередь и время.
final class WeatherScenePlayer: ObservableObject {
    @Published private(set) var scene: WeatherArt.Scene?
    private(set) var startedAt = Date()
    /// Ветер дует справа налево.
    private(set) var mirrored = false

    /// Сменилась погода, а вырез был занят: сценка ждёт, но не вечно —
    /// дождь, показанный через час после начала, уже не новость.
    private(set) var pending: (scene: WeatherArt.Scene, since: Date)?
    /// Отложенная сценка вызвана отладкой: смотрящий на экран человек
    /// мышь не трогает, и правило «за машиной ли кто-то» её бы не пустило.
    private(set) var pendingIsDebug = false
    static let pendingLifetime: TimeInterval = 10 * 60

    /// Размер острова по ходу сценки: секунды от начала и размер. Пишет
    /// контроллер на тике; не публикуется — холст и так перерисовывается
    /// каждый кадр, а лишние обновления вида ни к чему.
    private var islands: [(at: TimeInterval, size: CGSize)] = []

    private var lastPlayedAt: Date?
    private var endTimer: Timer?

    /// Погода сменилась. Правило частоты проверяется здесь, а не при показе:
    /// отложенная сценка уже прошла его.
    /// `force` — отладка: правило частоты не мешает посмотреть сценку дважды.
    func queue(_ scene: WeatherArt.Scene, force: Bool = false, now: Date = Date()) {
        guard force || WeatherScenePick.shouldPlay(scene, lastPlayedAt: lastPlayedAt, now: now) else {
            DebugLog.write("погода: сценка \(scene.rawValue) пропущена — недавно уже была")
            return
        }
        pending = (scene, now)
        pendingIsDebug = force
    }

    /// Отложенная сценка, если она ещё не устарела.
    func due(now: Date = Date()) -> WeatherArt.Scene? {
        guard let pending else { return nil }
        guard now.timeIntervalSince(pending.since) < Self.pendingLifetime else {
            DebugLog.write("погода: сценка \(pending.scene.rawValue) устарела")
            self.pending = nil
            return nil
        }
        return pending.scene
    }

    func play(_ scene: WeatherArt.Scene) {
        pending = nil
        lastPlayedAt = Date()
        startedAt = Date()
        mirrored = Bool.random()
        islands = []
        self.scene = scene
        DebugLog.write("погода: сценка \(scene.rawValue)")
        endTimer?.invalidate()
        let timer = Timer(timeInterval: scene.duration, repeats: false) { [weak self] _ in
            self?.finish()
        }
        RunLoop.main.add(timer, forMode: .common)
        endTimer = timer
    }

    /// Остров сейчас такого размера.
    func noteIsland(_ size: CGSize, now: Date = Date()) {
        guard scene != nil, islands.last?.size != size else { return }
        islands.append((max(0, now.timeIntervalSince(startedAt)), size))
    }

    /// Каким остров был в миг `t` от начала сценки.
    func island(at t: TimeInterval) -> CGSize? {
        islands.last { $0.at <= t }?.size ?? islands.first?.size
    }

    func cancel() {
        guard scene != nil else { return }
        finish()
        DebugLog.write("погода: сценка прервана")
    }

    func stop() {
        pending = nil
        finish()
    }

    private func finish() {
        endTimer?.invalidate()
        endTimer = nil
        scene = nil
    }
}
