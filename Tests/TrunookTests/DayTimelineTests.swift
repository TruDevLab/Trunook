import Foundation
import Testing
@testable import Trunook

@Suite("Шкала дня")
struct DayTimelineTests {
    /// Свой календарь с постоянным поясом: окно шкалы считается в минутах
    /// от полуночи, и пояс запуска не должен сдвигать ответ.
    private var calendar: Calendar {
        var made = Calendar(identifier: .gregorian)
        made.firstWeekday = 2
        made.timeZone = TimeZone(identifier: "UTC") ?? .current
        return made
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: hour, minute: minute))
            ?? Date()
    }

    private var day: Date { at(0) }

    /// «Сейчас» из другого дня: черта текущего времени тогда в окно
    /// не вмешивается, и проверять можно одну только раскладку дел.
    private var otherDay: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12)) ?? Date()
    }

    private func event(
        _ title: String,
        from: Date,
        to: Date?,
        allDay: Bool = false
    ) -> CalendarItem {
        CalendarItem(
            id: title,
            title: title,
            start: from,
            end: to,
            isAllDay: allDay,
            source: .event,
            link: nil,
            colorComponents: nil
        )
    }

    // MARK: - Окно

    @Test("Окно покрывает все дела и стоит по целым часам")
    func окноПоДелам() {
        let items = [
            event("встреча", from: at(10, 20), to: at(11, 15)),
            event("вторая", from: at(14, 5), to: at(14, 50)),
        ]
        let timeline = DayTimeline.make(items: items, day: day, now: otherDay, calendar: calendar)
        #expect(timeline.startMinute == 10 * 60)
        #expect(timeline.endMinute == 15 * 60)
    }

    @Test("Окно не уже трёх часов")
    func наименьшееОкно() {
        // День с одной получасовой встречей не должен превращаться в шкалу
        // из одного деления: встреча заняла бы всю высоту и перестала быть
        // событием во времени.
        let items = [event("одна", from: at(12), to: at(12, 30))]
        let timeline = DayTimeline.make(items: items, day: day, now: otherDay, calendar: calendar)
        #expect(timeline.endMinute - timeline.startMinute == DayTimeline.minimumSpan)
        #expect(timeline.startMinute <= 12 * 60)
        #expect(timeline.endMinute >= 13 * 60)
    }

    @Test("Пустой не сегодняшний день показывает рабочие часы")
    func пустойДень() {
        let timeline = DayTimeline.make(items: [], day: day, now: otherDay, calendar: calendar)
        #expect(timeline.startMinute == DayTimeline.quietStart)
        #expect(timeline.endMinute == DayTimeline.quietEnd)
        #expect(timeline.currentMinute == nil)
    }

    @Test("Сегодняшнее «сейчас» всегда попадает в окно")
    func сейчасВОкне() {
        // Черта текущего времени — главное, чем шкала отличается от списка.
        // За краем окна она не рисуется вовсе, поэтому окно тянется к ней,
        // даже если все дела давно кончились.
        let items = [event("утро", from: at(9), to: at(10))]
        let timeline = DayTimeline.make(items: items, day: day, now: at(19, 30), calendar: calendar)
        #expect(timeline.currentMinute == 19 * 60 + 30)
        #expect(timeline.startMinute <= 9 * 60)
        #expect(timeline.endMinute >= 19 * 60 + 30)
    }

    @Test("Черта времени чужого дня не показывается")
    func чертаТолькоСегодня() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let timeline = DayTimeline.make(items: [], day: tomorrow, now: at(12), calendar: calendar)
        #expect(timeline.currentMinute == nil)
    }

    // MARK: - Полосы

    @Test("Дела на весь день уходят из шкалы отдельным списком")
    func делаНаВесьДень() {
        // У них нет часа: полоса от края до края закрасила бы день целиком,
        // ничего о нём не сказав.
        let items = [
            event("отпуск", from: at(0), to: at(23, 59), allDay: true),
            event("встреча", from: at(10), to: at(11)),
        ]
        let timeline = DayTimeline.make(items: items, day: day, now: otherDay, calendar: calendar)
        #expect(timeline.allDay == [0])
        #expect(timeline.blocks.count == 1)
        #expect(timeline.blocks[0].index == 1)
    }

    @Test("Непересекающиеся дела стоят в одном столбце")
    func одинСтолбец() {
        let items = [
            event("первая", from: at(10), to: at(11)),
            event("вторая", from: at(11), to: at(12)),
        ]
        let timeline = DayTimeline.make(items: items, day: day, now: otherDay, calendar: calendar)
        #expect(timeline.blocks.allSatisfy { $0.lane == 0 && $0.lanes == 1 })
    }

    @Test("Одновременные дела разъезжаются по столбцам")
    func дваСтолбца() {
        let items = [
            event("первая", from: at(10), to: at(11)),
            event("вторая", from: at(10, 30), to: at(11, 30)),
        ]
        let timeline = DayTimeline.make(items: items, day: day, now: otherDay, calendar: calendar)
        #expect(Set(timeline.blocks.map(\.lane)) == [0, 1])
        // Ширина считается по связке целиком: соседние по времени встречи
        // разной ширины прочитались бы как разные по важности.
        #expect(timeline.blocks.allSatisfy { $0.lanes == 2 })
    }

    @Test("Ширина связки одна на все её дела, а следующая связка считается заново")
    func связкиСчитаютсяОтдельно() {
        let items = [
            event("а", from: at(10), to: at(12)),
            event("б", from: at(10, 30), to: at(11)),
            event("в", from: at(10, 45), to: at(11, 30)),
            event("после", from: at(14), to: at(15)),
        ]
        let timeline = DayTimeline.make(items: items, day: day, now: otherDay, calendar: calendar)
        let cluster = timeline.blocks.filter { $0.startMinute < 13 * 60 }
        #expect(cluster.count == 3)
        #expect(cluster.allSatisfy { $0.lanes == 3 })
        #expect(Set(cluster.map(\.lane)) == [0, 1, 2])

        let alone = timeline.blocks.first { $0.startMinute >= 13 * 60 }
        #expect(alone?.lanes == 1)
        #expect(alone?.lane == 0)
    }

    @Test("Освободившийся столбец занимает следующее дело")
    func столбецПереиспользуется() {
        // «б» кончается в 11:00, «в» начинается в 11:00 — значит «в» встаёт
        // в столбец «б», а не заводит третий: иначе связка с одной длинной
        // встречей расползалась бы вширь на весь день.
        let items = [
            event("а", from: at(10), to: at(13)),
            event("б", from: at(10), to: at(11)),
            event("в", from: at(11), to: at(12)),
        ]
        let timeline = DayTimeline.make(items: items, day: day, now: otherDay, calendar: calendar)
        #expect(timeline.blocks.allSatisfy { $0.lanes == 2 })
        #expect(timeline.blocks.first { $0.index == 2 }?.lane == 1)
    }

    @Test("Дело без конца получает наименьшую длину")
    func напоминаниеБезКонца() {
        // У напоминания конца нет вовсе, а нитка нулевой длины не видна
        // ни глазом, ни в раскладке: две таких подряд наложились бы.
        let items = [event("напоминание", from: at(10), to: nil)]
        let timeline = DayTimeline.make(items: items, day: day, now: otherDay, calendar: calendar)
        #expect(timeline.blocks[0].minutes == DayTimeline.minimumBlock)
    }

    @Test("Событие из соседних суток прижимается к краям дня")
    func событиеЧерезПолночь() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: at(22)) ?? at(22)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: at(3)) ?? at(3)
        let items = [event("поездка", from: yesterday, to: tomorrow)]
        let timeline = DayTimeline.make(items: items, day: day, now: otherDay, calendar: calendar)
        #expect(timeline.blocks[0].startMinute == 0)
        #expect(timeline.blocks[0].endMinute == 24 * 60)
    }

    @Test("Дело у самой полуночи не сплющивается в нитку")
    func делоВКонцеСуток() {
        let items = [event("поздняя", from: at(23, 55), to: nil)]
        let timeline = DayTimeline.make(items: items, day: day, now: otherDay, calendar: calendar)
        let block = timeline.blocks[0]
        #expect(block.endMinute == 24 * 60)
        #expect(block.minutes == DayTimeline.minimumBlock)
    }

    @Test("Порядок дел в исходном списке не теряется")
    func номераСохраняются() {
        // Полосы берут запись по номеру, а не по идентификатору: два
        // вхождения одного повторяющегося события в день делят его.
        let items = [
            event("повтор", from: at(12), to: at(13)),
            event("повтор", from: at(15), to: at(16)),
        ]
        let timeline = DayTimeline.make(items: items, day: day, now: otherDay, calendar: calendar)
        #expect(timeline.blocks.map(\.index) == [0, 1])
    }

    // MARK: - Укороченное окно

    @Test("Короткое окно встаёт вокруг «сейчас»")
    func окноВокругСейчас() {
        // Плитка не прокручивается, и день целиком влезает в неё только
        // сжатием часа до нечитаемого. Тогда показывается часть дня —
        // та, на которую смотрят.
        let items = [
            event("утро", from: at(9), to: at(10)),
            event("вечер", from: at(16), to: at(17)),
        ]
        let full = DayTimeline.make(items: items, day: day, now: at(12, 20), calendar: calendar)
        let short = full.limited(to: 4)
        #expect(short.hours == 4)
        #expect(short.startMinute == 12 * 60)
        #expect(short.currentMinute == 12 * 60 + 20)
    }

    @Test("Окно не вылезает за конец дня")
    func окноПрижатоККонцу() {
        let items = [event("поздняя", from: at(16), to: at(17))]
        let full = DayTimeline.make(items: items, day: day, now: at(16, 30), calendar: calendar)
        let short = full.limited(to: 3)
        #expect(short.endMinute <= full.endMinute)
        #expect(short.startMinute >= full.startMinute)
        #expect(short.hours == 3)
    }

    @Test("Не сегодняшний день начинается с первого дела")
    func окноОтПервогоДела() {
        let items = [
            event("первое", from: at(11), to: at(12)),
            event("последнее", from: at(19), to: at(20)),
        ]
        let full = DayTimeline.make(items: items, day: day, now: otherDay, calendar: calendar)
        let short = full.limited(to: 4)
        #expect(short.startMinute == 11 * 60)
    }

    @Test("Не поместившиеся дела уходят из раскладки и считаются")
    func скрытыеДелаСчитаются() {
        // Полоса, целиком оставшаяся за окном, рисовалась бы выше или ниже
        // шкалы: обрезка вида — не то место, где решают, что показывать.
        let items = [
            event("первое", from: at(9), to: at(10)),
            event("второе", from: at(11), to: at(12)),
            event("третье", from: at(16), to: at(17)),
            event("четвёртое", from: at(17), to: at(18)),
        ]
        let full = DayTimeline.make(items: items, day: day, now: otherDay, calendar: calendar)
        let short = full.limited(to: 4)
        #expect(short.blocks.map(\.index) == [0, 1])
        #expect(short.hidden(from: full) == 2)
    }

    @Test("Окно шире самого дня не укорачивает ничего")
    func окноБольшеДня() {
        let items = [event("одна", from: at(12), to: at(13))]
        let full = DayTimeline.make(items: items, day: day, now: otherDay, calendar: calendar)
        #expect(full.limited(to: 12) == full)
        #expect(full.limited(to: 12).hidden(from: full) == 0)
    }

    // MARK: - Подписи

    @Test("Шаг подписей растёт, пока они не перестанут тесниться")
    func шагПодписей() {
        #expect(DayTimeline.hourStep(hours: 3, fitting: 10) == 1)
        #expect(DayTimeline.hourStep(hours: 12, fitting: 6) == 2)
        #expect(DayTimeline.hourStep(hours: 24, fitting: 5) == 6)
        // Места нет вовсе — шаг всё равно не ноль: на него делят перебор
        // часов.
        #expect(DayTimeline.hourStep(hours: 9, fitting: 0) >= 1)
    }

    @Test("Доля минуты считается от окна, а не от суток")
    func доляМинуты() {
        let items = [event("встреча", from: at(10), to: at(14))]
        let timeline = DayTimeline.make(items: items, day: day, now: otherDay, calendar: calendar)
        #expect(timeline.fraction(of: timeline.startMinute) == 0)
        #expect(timeline.fraction(of: timeline.endMinute) == 1)
        #expect(timeline.fraction(of: 12 * 60) == 0.5)
    }

    @Test("Подписи часов без минут, окно — со временем")
    func подписи() {
        #expect(DayTimeline.hourLabel(minute: 14 * 60) == "14")
        #expect(DayTimeline.hourLabel(minute: 24 * 60) == "0")
        #expect(DayTimeline.rangeLabel(from: 9 * 60, to: 18 * 60) == "9:00 – 18:00")
    }

    // MARK: - Представление

    @Test("Представления ровно два, и каждое переключает в другое")
    func переключение() {
        #expect(CalendarDayView.list.other == .timeline)
        #expect(CalendarDayView.timeline.other == .list)
        #expect(CalendarDayView.allCases.count == 2)
    }

    @Test("У плитки шкалы есть вёрстка под каждый свой размер")
    func размерыПлитки() {
        // Набор закрытый: размер, под который вёрстки нет, показал бы
        // то же содержимое растянутым. В один ряд идёт лента, в два —
        // шкала с часами, и оба ряда в наборе есть.
        let sizes = HomeWidgetKind.timeline.allowedSizes
        #expect(!sizes.isEmpty)
        #expect(sizes.contains { $0.rows == 1 })
        #expect(sizes.contains { $0.rows == 2 })
        #expect(!sizes.contains(.small))
        #expect(HomeWidgetKind.timeline.defaultSize == sizes[0])
    }
}
