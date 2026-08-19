import Foundation
import Testing
@testable import Trunook

@Suite("Встречи на одно время")
struct SimultaneousEventsTests {
    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    private func item(_ title: String, at start: Date) -> CalendarItem {
        CalendarItem(
            id: title,
            title: title,
            start: start,
            end: nil,
            isAllDay: false,
            source: .event,
            link: nil,
            colorComponents: [1, 1, 1]
        )
    }

    @Test("Одна встреча остаётся одной")
    func однаОстаётсяОдной() {
        let items = [item("созвон", at: noon), item("позже", at: noon.addingTimeInterval(3600))]
        #expect(items.startingTogether(limit: 3).map(\.title) == ["созвон"])
    }

    @Test("Накладка показывается целиком")
    func накладкаЦеликом() {
        let items = [
            item("созвон", at: noon),
            item("ретро", at: noon),
            item("позже", at: noon.addingTimeInterval(1800)),
        ]
        #expect(items.startingTogether(limit: 3).map(\.title) == ["созвон", "ретро"])
    }

    /// Встречи, заведённые разными людьми, расходятся на доли секунды —
    /// посекундное сравнение развело бы их по разным экранам.
    @Test("Секунды внутри одной минуты не разводят встречи")
    func секундыНеРазводят() {
        let items = [item("созвон", at: noon), item("ретро", at: noon.addingTimeInterval(37))]
        #expect(items.startingTogether(limit: 3).count == 2)
    }

    @Test("Соседняя минута — уже другое время")
    func соседняяМинутаОтдельно() {
        let items = [item("созвон", at: noon), item("ретро", at: noon.addingTimeInterval(90))]
        #expect(items.startingTogether(limit: 3).map(\.title) == ["созвон"])
    }

    @Test("Больше потолка в панель не лезет")
    func потолок() {
        let items = (1...5).map { item("встреча \($0)", at: noon) }
        #expect(items.startingTogether(limit: 3).count == 3)
    }

    @Test("Пустой список не падает")
    func пустой() {
        #expect([CalendarItem]().startingTogether(limit: 3).isEmpty)
    }

    /// Панель обязана вырасти под вторую встречу: иначе вторая строка
    /// нарисуется, а зона нажатий останется старой — ровно тот класс ошибок,
    /// ради которого расчёт состояния сведён в одно место.
    @Test("Вторая встреча растит панель")
    func втораяРаститПанель() {
        let one = NotchContent(events: [item("созвон", at: noon)])
        let two = NotchContent(events: [item("созвон", at: noon), item("ретро", at: noon)])
        #expect(two.extraHeight > one.extraHeight)
        #expect(two.extraHeight - one.extraHeight
                == NotchMetrics.eventRowHeight + NotchStyle.rowSpacing)
    }
}
