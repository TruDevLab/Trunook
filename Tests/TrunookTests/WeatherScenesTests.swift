import Foundation
import Testing
@testable import Trunook

@Suite("Погодные сценки")
struct WeatherScenesTests {
    @Test("У каждой погоды своя сценка")
    func сценкиПоПогоде() {
        #expect(WeatherScenePick.scene(condition: .clear, windy: false) == .sun)
        #expect(WeatherScenePick.scene(condition: .cloudy, windy: false) == .clouds)
        #expect(WeatherScenePick.scene(condition: .fog, windy: false) == .fog)
        #expect(WeatherScenePick.scene(condition: .drizzle, windy: false) == .drizzle)
        #expect(WeatherScenePick.scene(condition: .rain, windy: false) == .rain)
        #expect(WeatherScenePick.scene(condition: .snow, windy: false) == .snow)
        #expect(WeatherScenePick.scene(condition: .thunder, windy: false) == .thunder)
    }

    /// Под дождём ветер не главное, что видно в окно.
    @Test("Ветер перебивает небо, но не осадки")
    func ветер() {
        #expect(WeatherScenePick.scene(condition: .clear, windy: true) == .wind)
        #expect(WeatherScenePick.scene(condition: .cloudy, windy: true) == .wind)
        #expect(WeatherScenePick.scene(condition: .rain, windy: true) == .rain)
        #expect(WeatherScenePick.scene(condition: .snow, windy: true) == .blizzard)
        #expect(WeatherScenePick.scene(condition: .snow, windy: false, heavy: true) == .heavySnow)
        #expect(WeatherScenePick.scene(condition: .snow, windy: true, heavy: true) == .blizzard)
    }

    /// Ветер около порога не должен включать и выключать «ветрено»
    /// на каждой проверке.
    @Test("У порога ветра есть запас")
    func запасПорога() {
        #expect(!WeatherScenePick.isWindy(wind: 29, wasWindy: false))
        #expect(WeatherScenePick.isWindy(wind: 30, wasWindy: false))
        #expect(WeatherScenePick.isWindy(wind: 25, wasWindy: true))
        #expect(!WeatherScenePick.isWindy(wind: 21, wasWindy: true))
    }

    @Test("Осадки показываются всегда, небо — не чаще раза в 40 минут")
    func частота() {
        let now = Date()
        let recent = now.addingTimeInterval(-10 * 60)
        let long = now.addingTimeInterval(-41 * 60)
        #expect(WeatherScenePick.shouldPlay(.rain, lastPlayedAt: recent, now: now))
        #expect(WeatherScenePick.shouldPlay(.thunder, lastPlayedAt: recent, now: now))
        #expect(!WeatherScenePick.shouldPlay(.sun, lastPlayedAt: recent, now: now))
        #expect(WeatherScenePick.shouldPlay(.sun, lastPlayedAt: long, now: now))
        #expect(WeatherScenePick.shouldPlay(.clouds, lastPlayedAt: nil, now: now))
    }

    /// Дождь, показанный через час после начала, уже не новость.
    @Test("Отложенная сценка устаревает")
    func устаревание() {
        let player = WeatherScenePlayer()
        let then = Date()
        player.queue(.rain, now: then)
        #expect(player.due(now: then.addingTimeInterval(60)) == .rain)
        #expect(player.due(now: then.addingTimeInterval(WeatherScenePlayer.pendingLifetime + 1)) == nil)
        #expect(player.pending == nil)
    }

    @Test("Сыгранная сценка снимает очередь и держит частоту")
    func игра() {
        let player = WeatherScenePlayer()
        player.queue(.sun)
        player.play(.sun)
        #expect(player.scene == .sun)
        #expect(player.pending == nil)
        player.stop()
        #expect(player.scene == nil)
        // Солнце только что было — второе подряд в очередь не встаёт.
        player.queue(.clouds)
        #expect(player.pending == nil)
        player.queue(.snow)
        #expect(player.pending?.scene == .snow)
    }

    /// Кадр в один и тот же миг обязан быть одинаковым: случайность —
    /// из номера частицы, а не из генератора.
    @Test("Шум частиц постоянен и лежит от 0 до 1")
    func шум() {
        for i in 0..<200 {
            let value = WeatherArt.noise(i, 7)
            #expect(value >= 0 && value < 1)
            #expect(value == WeatherArt.noise(i, 7))
        }
    }

    @Test("Спрайты ровные")
    func спрайты() {
        for sprite in [WeatherArt.cloud, WeatherArt.smallCloud, WeatherArt.bolt, WeatherArt.flake,
                       WeatherArt.sun(twinkle: false), WeatherArt.sun(twinkle: true, blink: true)] {
            #expect(sprite.cells.count == sprite.height)
            #expect(sprite.cells.allSatisfy { $0.count == sprite.width })
        }
    }
}
