import Foundation
import Testing
@testable import Trunook

@Suite("Кот в чёлке")
struct CritterTests {
    private var free: CritterGate {
        CritterGate(enabled: true, isIdle: true, hasNotch: true, reduceMotion: false,
                    lowPower: false, idleSeconds: 5, fullScreen: false)
    }

    @Test("Выходит, когда ничто не мешает")
    func выходит() {
        #expect(free.canPlay)
        #expect(free.reason == "можно")
    }

    @Test("Каждое условие по отдельности не пускает")
    func условия() {
        var gate = free; gate.enabled = false; #expect(!gate.canPlay)
        gate = free; gate.isIdle = false; #expect(!gate.canPlay)
        gate = free; gate.hasNotch = false; #expect(!gate.canPlay)
        gate = free; gate.reduceMotion = true; #expect(!gate.canPlay)
        gate = free; gate.lowPower = true; #expect(!gate.canPlay)
        gate = free; gate.fullScreen = true; #expect(!gate.canPlay)
        gate = free; gate.idleSeconds = CritterGate.presenceWindow; #expect(!gate.canPlay)
        #expect(gate.reason == "никого нет")
    }

    @Test("Сценка не повторяет прошлую")
    func безПовтора() {
        for act in NotchCritter.Act.allCases {
            for _ in 0..<20 { #expect(CritterSchedule.pick(avoiding: act) != act) }
        }
    }

    @Test("Между сценками не меньше двадцати минут, повтор — через минуты")
    func расписание() {
        for _ in 0..<50 {
            #expect(CritterSchedule.interval.contains(CritterSchedule.nextDelay()))
            #expect(CritterSchedule.nextDelay() >= 20 * 60)
            #expect(CritterSchedule.retryDelay() <= 5 * 60)
        }
    }

    @Test("По умолчанию кот включён")
    func поУмолчанию() throws {
        let suite = "CritterTests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        #expect(Settings(defaults: defaults).critterEnabled)
    }
}
