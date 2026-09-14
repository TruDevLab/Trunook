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

    @Test("Промежутки по частоте, первый выход — через минуты после запуска")
    func расписание() {
        for _ in 0..<50 {
            for frequency in CritterFrequency.allCases {
                #expect(frequency.interval.contains(CritterSchedule.nextDelay(frequency)))
            }
            #expect(CritterSchedule.firstDelay() <= 3 * 60)
            #expect(CritterSchedule.retryDelay() <= 2 * 60)
        }
        // Чем чаще, тем короче промежуток — и никакой не пересекается.
        #expect(CritterFrequency.often.interval.upperBound < CritterFrequency.normal.interval.lowerBound)
        #expect(CritterFrequency.normal.interval.upperBound < CritterFrequency.rare.interval.lowerBound)
    }

    @Test("По умолчанию — раз в 5–10 минут")
    func частотаПоУмолчанию() throws {
        let suite = "CritterFrequencyTests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        #expect(Settings(defaults: defaults).critterFrequency == .normal)
    }

    /// Спрайт с рваной строкой рисовался бы со сдвигом ряда.
    @Test("Спрайты поцелуйчика и головокружения ровные")
    func спрайтыПоцелуйчика() {
        let fists = [CritterArt.fistLoaf(frown: false, fist: nil), CritterArt.fistLoaf(frown: true, fist: true),
                     CritterArt.fistLoaf(frown: true, fist: false)]
        for sprite in [CritterArt.dizzy, CritterArt.glasses] + CritterArt.hearts + CritterArt.sparkle
            + CritterArt.grawlix + fists {
            #expect(sprite.cells.count == sprite.height)
            #expect(sprite.cells.allSatisfy { $0.count == sprite.width })
        }
    }

    private let area = CGRect(x: 16, y: 31, width: 568, height: 205)
    private let homes = [CGPoint(x: 230, y: 31), CGPoint(x: 370, y: 31)]

    /// Прогнать погоню кадрами по 1/30 секунды.
    private func run(_ hunt: inout HuntState, from: Double, to: Double, target: CGPoint) {
        var t = from
        while t < to {
            hunt.advance(to: t, start: CGPoint(x: 370, y: 31), target: target, area: area, homes: homes)
            t += 1.0 / 30
        }
    }

    @Test("Котик догоняет курсор и прыгает на него")
    func охотаПрыжок() throws {
        var hunt = HuntState()
        let cursor = CGPoint(x: 450, y: 120)
        var leapt = false
        var t = 0.0
        while t < 4 {
            hunt.advance(to: t, start: CGPoint(x: 370, y: 31), target: cursor, area: area, homes: homes)
            if hunt.pose == .leaping { leapt = true }
            t += 1.0 / 30
        }
        #expect(leapt, "так и не прыгнул")
        let position = try #require(hunt.position)
        #expect(hypot(position.x - cursor.x, position.y - cursor.y) < 3, "приземлился мимо курсора")
        #expect(hunt.pose == .sitting, "после прыжка сидит, а не прыгает на месте")
    }

    /// Курсор посреди экрана, ниже полосы, где котик бегает: прыгать некуда.
    @Test("На недосягаемый курсор не прыгает, а садится ближе всего")
    func охотаНедосягаемо() throws {
        var hunt = HuntState()
        var leapt = false
        var t = 0.0
        while t < 5 {
            hunt.advance(to: t, start: CGPoint(x: 370, y: 31), target: CGPoint(x: 300, y: 900), area: area, homes: homes)
            if hunt.pose == .leaping { leapt = true }
            t += 1.0 / 30
        }
        #expect(!leapt)
        let position = try #require(hunt.position)
        #expect(abs(position.y - area.maxY) < 3)
    }

    @Test("Время вышло — убегает за ближний край и пропадает")
    func охотаУбегает() throws {
        var hunt = HuntState()
        run(&hunt, from: 0, to: HuntState.huntTime + 1.9, target: CGPoint(x: 200, y: 60))
        #expect(!hunt.visible, "не успел убежать до конца сценки")
    }

    @Test("По умолчанию кот включён")
    func поУмолчанию() throws {
        let suite = "CritterTests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        #expect(Settings(defaults: defaults).critterEnabled)
    }
}
