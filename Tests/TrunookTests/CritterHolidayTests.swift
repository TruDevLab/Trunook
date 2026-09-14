import Foundation
import Testing
@testable import Trunook

@Suite("Праздничные сценки кота")
struct CritterHolidayTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }

    private func on(_ year: Int, _ month: Int, _ day: Int) -> [CritterHoliday] {
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        return CritterHoliday.on(date, calendar: calendar)
    }

    @Test("Праздники с постоянной датой")
    func постоянные() {
        #expect(on(2026, 12, 25).contains(.newYear))
        #expect(on(2027, 1, 1).contains(.newYear))
        #expect(on(2027, 1, 7).contains(.newYear), "православное Рождество")
        #expect(!on(2027, 1, 9).contains(.newYear))
        #expect(on(2026, 2, 14) == [.valentine])
        #expect(on(2026, 2, 23) == [.defenderDay])
        #expect(on(2026, 3, 8) == [.womenDay])
        #expect(on(2026, 5, 9) == [.victoryDay])
        #expect(on(2026, 6, 1) == [.childrenDay])
        #expect(on(2026, 10, 31) == [.halloween])
        #expect(on(2026, 9, 14).isEmpty)
    }

    /// Даты сверены с опубликованными календарями.
    @Test("Пасха — западная и православная")
    func пасха() {
        #expect(CritterHoliday.westernEaster(2026) == (4, 5))
        #expect(CritterHoliday.orthodoxEaster(2026) == (4, 12))
        #expect(CritterHoliday.westernEaster(2027) == (3, 28))
        #expect(CritterHoliday.orthodoxEaster(2027) == (5, 2))
        #expect(on(2026, 4, 5).contains(.easter))
        // Православная Пасха 2026 — в День космонавтики: оба праздника сразу.
        #expect(Set(on(2026, 4, 12)) == [.easter, .cosmonautics])
    }

    @Test("Китайский Новый год — по китайскому календарю")
    func китайский() {
        #expect(on(2026, 2, 17).contains(.lunarNewYear))
        #expect(on(2027, 2, 6).contains(.lunarNewYear))
        #expect(!on(2026, 2, 18).contains(.lunarNewYear))
    }

    @Test("В обычный день праздничных сценок нет")
    func обычныйДень() {
        for _ in 0..<200 {
            let act = CritterSchedule.pick(avoiding: nil)
            #expect(CritterHoliday.act(for: act) == nil, "в обычный день вышла \(act)")
        }
    }

    @Test("В праздник выходит и праздничная, и обычная")
    func праздник() {
        var festive = 0, everyday = 0
        for _ in 0..<400 {
            let act = CritterSchedule.pick(avoiding: nil, holidays: [.halloween])
            if act == .pumpkin { festive += 1 } else if CritterHoliday.act(for: act) == nil { everyday += 1 }
        }
        #expect(festive > 100 && everyday > 100)
    }

    @Test("У каждого праздника своя сценка")
    func сценки() {
        let acts = CritterHoliday.allCases.map(\.act)
        #expect(Set(acts).count == acts.count)
    }
}
