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
        #expect([CalendarItem]().upcomingSlots(limit: 3).isEmpty)
        #expect([CalendarItem]().groupedByStart().isEmpty)
    }

    // MARK: - Ближайшее время и следующее

    @Test("К ближайшей встрече добавляется следующая")
    func следующаяДобавляется() {
        let items = [
            item("созвон", at: noon),
            item("обед", at: noon.addingTimeInterval(3600)),
        ]
        #expect(items.upcomingSlots(limit: 3).map(\.title) == ["созвон", "обед"])
    }

    @Test("Дальше второго времени не заглядываем")
    func третьеВремяНеПоказываем() {
        let items = (0..<4).map { item("встреча \($0)", at: noon.addingTimeInterval(Double($0) * 3600)) }
        #expect(items.upcomingSlots(limit: 3).map(\.title) == ["встреча 0", "встреча 1"])
    }

    /// Накладка сегодня важнее планов на вечер: если ближайшее время занято
    /// целиком, следующему в панели места не остаётся.
    @Test("Полная накладка вытесняет следующее время")
    func накладкаВытесняетСледующее() {
        let items = [
            item("созвон", at: noon),
            item("ретро", at: noon),
            item("груминг", at: noon),
            item("обед", at: noon.addingTimeInterval(3600)),
        ]
        #expect(items.upcomingSlots(limit: 3).map(\.title) == ["созвон", "ретро", "груминг"])
    }

    @Test("Подложка на каждое время начала")
    func группыПоВремени() {
        let items = [
            item("созвон", at: noon),
            item("ретро", at: noon.addingTimeInterval(37)),
            item("обед", at: noon.addingTimeInterval(3600)),
        ]
        #expect(items.groupedByStart().map { $0.map(\.title) }
                == [["созвон", "ретро"], ["обед"]])
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

    /// Своё время — своя подложка, и панель растёт на её поля и зазор,
    /// а не только на высоту строки.
    @Test("Следующее время растит панель на целую подложку")
    func следующееВремяРаститНаПодложку() {
        let together = NotchContent(events: [item("созвон", at: noon), item("ретро", at: noon)])
        let apart = NotchContent(events: [
            item("созвон", at: noon),
            item("обед", at: noon.addingTimeInterval(3600)),
        ])
        #expect(apart.extraHeight > together.extraHeight)
    }

    /// Потолок размера окна обязан покрывать самый высокий возможный состав:
    /// панель, переросшая окно, обрезается по нему молча.
    @Test("Потолок покрывает любую панель")
    func потолокПокрываетПанель() {
        let worst = NotchContent(
            events: [
                item("созвон", at: noon),
                item("ретро", at: noon),
                item("обед", at: noon.addingTimeInterval(3600)),
            ],
            taskCount: NotchMetrics.maxVisibleTasks
        )
        #expect(worst.extraHeight <= NotchContent.maxExtraHeight)
    }
}
