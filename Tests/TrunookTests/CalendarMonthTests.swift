import Foundation
import Testing
@testable import Trunook

@Suite("Раскладка месяца")
struct CalendarMonthTests {
    /// Понедельник первым и четыре дня в первой неделе — как в России
    /// и в ISO. Свой календарь, а не системный: тест не должен менять ответ
    /// от того, в какой стране его запустили.
    private var calendar: Calendar {
        var made = Calendar(identifier: .gregorian)
        made.firstWeekday = 2
        made.minimumDaysInFirstWeek = 4
        made.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .current
        return made
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    @Test("Сетка всегда шесть недель по семь дней")
    func размерСетки() {
        // Шесть, даже когда месяц укладывается в пять: панель, меняющая рост
        // при перелистывании, дёргала бы вырез на каждой стрелке.
        for month in 1...12 {
            let grid = CalendarMonth.make(monthOf: date(2026, month, 1), calendar: calendar)
            #expect(grid.weeks.count == CalendarMonth.rows)
            #expect(grid.weeks.allSatisfy { $0.days.count == 7 })
        }
    }

    @Test("Сетка начинается с начала недели, а не с первого числа")
    func началоСетки() {
        // 1 сентября 2026 — вторник. Первая клетка обязана быть понедельником
        // 31 августа, иначе первое число встало бы в колонку понедельника,
        // каким бы днём недели оно ни было.
        let grid = CalendarMonth.make(monthOf: date(2026, 9, 1), calendar: calendar)
        let first = grid.weeks[0].days[0]
        #expect(first.number == 31)
        #expect(first.isInMonth == false)
        #expect(calendar.component(.weekday, from: first.date) == calendar.firstWeekday)
    }

    @Test("Свои дни отделены от хвостов соседних месяцев")
    func хвостыПомечены() {
        let grid = CalendarMonth.make(monthOf: date(2026, 9, 1), calendar: calendar)
        let own = grid.weeks.flatMap(\.days).filter(\.isInMonth)
        #expect(own.count == 30)
        #expect(own.map(\.number) == Array(1...30))
    }

    @Test("Номера недель идут подряд")
    func номераНедель() {
        let grid = CalendarMonth.make(monthOf: date(2026, 9, 1), calendar: calendar)
        let numbers = grid.weeks.map(\.number)
        #expect(numbers.count == CalendarMonth.rows)
        // Подряд — с точностью до Нового года, где нумерация начинается
        // заново. Здесь его нет.
        #expect(zip(numbers, numbers.dropFirst()).allSatisfy { $1 == $0 + 1 })
    }

    /// Раз в году нумерация недель начинается заново, и сетка декабря
    /// перескакивает с пятьдесят второй на первую. Ошибка здесь молчаливая:
    /// её видно один месяц из двенадцати.
    @Test("Через Новый год нумерация начинается заново")
    func черезНовыйГод() {
        let grid = CalendarMonth.make(monthOf: date(2026, 12, 1), calendar: calendar)
        let numbers = grid.weeks.map(\.number)
        #expect(numbers.contains(1))
        #expect(numbers.first ?? 0 > 40)
    }

    @Test("Шаг по месяцам ведёт на первое число")
    func шагПоМесяцам() {
        let next = CalendarMonth.shifted(date(2026, 12, 15), byMonths: 1, calendar: calendar)
        #expect(calendar.component(.year, from: next) == 2027)
        #expect(calendar.component(.month, from: next) == 1)
        #expect(calendar.component(.day, from: next) == 1)
    }

    /// Тридцать первое января плюс месяц — в феврале такого числа нет.
    /// Сдвиг обязан привести к первому февраля, а не отступить на день назад
    /// и остаться в январе.
    @Test("Шаг с тридцать первого не застревает в прежнем месяце")
    func шагСКонцаМесяца() {
        let next = CalendarMonth.shifted(date(2026, 1, 31), byMonths: 1, calendar: calendar)
        #expect(calendar.component(.month, from: next) == 2)
        #expect(calendar.component(.day, from: next) == 1)
    }

    @Test("Подписей дней недели семь")
    func подписиДней() {
        let titles = CalendarMonth.weekdayTitles(calendar: calendar)
        #expect(titles.count == 7)
        #expect(titles.allSatisfy { !$0.isEmpty })
    }
}

@Suite("Правка события")
struct EventDraftTests {
    private var calendar: Calendar {
        var made = Calendar(identifier: .gregorian)
        made.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .current
        return made
    }

    private func draft(hour: Int = 14, minute: Int = 0, repeats: Bool = false) -> EventDraft {
        let start = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 12, hour: hour, minute: minute
        )) ?? Date()
        return EventDraft(
            id: "x",
            title: "Созвон",
            start: start,
            duration: 3600,
            isAllDay: false,
            location: "",
            notes: "",
            link: nil,
            calendarID: nil,
            colorComponents: nil,
            attendees: [],
            isRecurring: repeats,
            originalStart: start
        )
    }

    /// Разница молчаливая и необратимая: перенеся одну встречу на час,
    /// человек не ждёт, что переедут все прошлые и будущие, — а откатить
    /// это в Календаре потом нечем.
    @Test("Повторяющееся событие по умолчанию правится одним вхождением")
    func рядНеТрогаемБезСпроса() {
        #expect(draft(repeats: true).editsSeries == false)
        #expect(draft().editsSeries == false)
    }

    /// Найти нужное вхождение можно только вместе с его временем начала:
    /// идентификатор у всего ряда один. Начало запоминается при открытии
    /// и не едет вслед за правкой.
    @Test("Начало вхождения помнится отдельно от правленого")
    func началоВхожденияНеЕдет() {
        let moved = draft(repeats: true).movingStart(bySteps: 4)
        #expect(moved.originalStart == draft().start)
        #expect(moved.start != moved.originalStart)
    }

    /// Сдвигая начало, человек ждёт, что встреча поедет целиком, а не
    /// растянется. Длительность хранится отдельно ровно ради этого.
    @Test("Сдвиг начала везёт встречу целиком")
    func сдвигНачала() {
        let moved = draft().movingStart(bySteps: 2)
        #expect(moved.start == draft().start.addingTimeInterval(EventDraft.step * 2))
        #expect(moved.duration == draft().duration)
    }

    @Test("Сдвиг дня не трогает часа")
    func сдвигДня() {
        let moved = draft().movingDay(by: 1, calendar: calendar)
        #expect(calendar.component(.day, from: moved.start) == 13)
        #expect(calendar.component(.hour, from: moved.start) == 14)
    }

    /// Нулевая длительность в календаре выглядит поломкой, а не пометкой.
    @Test("Короче шага событие не сжимается")
    func потолокСжатия() {
        let squeezed = draft().stretched(bySteps: -100)
        #expect(squeezed.duration == EventDraft.step)
    }

    @Test("Длительность записывается часами и минутами")
    func записьДлительности() {
        #expect(draft().durationLabel == tf("%d ч", 1))
        #expect(draft().stretched(bySteps: 2).durationLabel == tf("%d ч %d мин", 1, 30))
        #expect(draft().stretched(bySteps: -3).durationLabel == tf("%d мин", 15))
    }

    /// Событие без названия в списке неотличимо от любого другого безымянного.
    @Test("Пустое название не сохраняется")
    func пустоеНазвание() {
        var empty = draft()
        empty.title = "   "
        #expect(!empty.isSavable)
        #expect(draft().isSavable)
    }

    /// Заводя событие, назначают его вперёд: время «14:37» пришлось бы
    /// править в любом случае.
    @Test("Новое событие встаёт на ближайшую четверть вперёд")
    func времяНового() {
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 12, hour: 14, minute: 37
        )) ?? Date()
        let made = EventDraft.blank(on: now, now: now, calendar: calendar)
        #expect(made.start > now)
        #expect(made.start.timeIntervalSince(now) <= EventDraft.step)
        #expect(made.isNew)
    }

    /// Округление вверх поздним вечером выносило событие в завтра — а день
    /// человек только что выбрал сам. Поймано живьём в 23:48.
    @Test("Поздним вечером новое событие остаётся в своём дне")
    func времяПередПолуночью() {
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 6, hour: 23, minute: 48
        )) ?? Date()
        let made = EventDraft.blank(on: now, now: now, calendar: calendar)
        #expect(calendar.isDate(made.start, inSameDayAs: now))
        #expect(calendar.component(.hour, from: made.start) == 23)
        #expect(calendar.component(.minute, from: made.start) == 45)
    }

    /// На чужой день угадывать нечего: начало рабочего дня промахивается реже.
    @Test("На другой день новое событие встаёт на десять утра")
    func времяНаЧужойДень() {
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 12, hour: 14, minute: 37
        )) ?? Date()
        let other = calendar.date(byAdding: .day, value: 3, to: now) ?? now
        let made = EventDraft.blank(on: other, now: now, calendar: calendar)
        #expect(calendar.component(.hour, from: made.start) == 10)
        #expect(calendar.component(.minute, from: made.start) == 0)
    }
}


@Suite("Ближайшее дело дня")
struct DayAgendaTests {
    private var calendar: Calendar {
        var made = Calendar(identifier: .gregorian)
        made.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .current
        return made
    }

    private func now(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 12, hour: hour, minute: minute
        )) ?? Date()
    }

    private func event(
        _ title: String,
        at hour: Int,
        minutes: Int = 60,
        allDay: Bool = false,
        day: Int = 12
    ) -> CalendarItem {
        let start = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: day, hour: hour
        )) ?? Date()
        return CalendarItem(
            id: title,
            title: title,
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            isAllDay: allDay,
            source: .event,
            link: nil,
            colorComponents: nil
        )
    }

    @Test("Ближайшее — первое, что ещё не кончилось")
    func первоеВпереди() {
        let day = [event("Утро", at: 9), event("Обед", at: 13), event("Вечер", at: 18)]
        let index = DayAgenda.nextIndex(in: day, now: now(10), calendar: calendar)
        #expect(index == 1)
    }

    /// Встреча, которая идёт, и есть то, куда человеку сейчас. Помечать
    /// вместо неё следующую значило бы торопить его мимо текущей.
    @Test("Идущее важнее ещё не начавшегося")
    func идущееПобеждает() {
        let day = [event("Утро", at: 9), event("Обед", at: 13)]
        let index = DayAgenda.nextIndex(in: day, now: now(9, 30), calendar: calendar)
        #expect(index == 0)
        #expect(DayAgenda.badge(for: day[0], now: now(9, 30)) == t("идёт"))
    }

    /// У дела на весь день нет часа, оно стоит первым в списке — и
    /// «ближайшим» было бы весь день подряд.
    @Test("Дело на весь день ближайшим не считается")
    func весьДеньНеСчитается() {
        let day = [event("Отпуск", at: 0, allDay: true), event("Обед", at: 13)]
        let index = DayAgenda.nextIndex(in: day, now: now(10), calendar: calendar)
        #expect(index == 1)
    }

    /// В будущем дне впереди всё, и пометка на первой строке значила бы
    /// просто «первая».
    @Test("В чужом дне ближайшего нет")
    func чужойДеньПустой() {
        let day = [event("Завтра", at: 9, day: 13)]
        #expect(DayAgenda.nextIndex(in: day, now: now(10), calendar: calendar) == nil)
    }

    @Test("Когда всё прошло, выделять нечего")
    func всёПрошло() {
        let day = [event("Утро", at: 9), event("Обед", at: 13)]
        #expect(DayAgenda.nextIndex(in: day, now: now(20), calendar: calendar) == nil)
    }

    @Test("Пустой день ничего не выделяет")
    func пустойДень() {
        #expect(DayAgenda.nextIndex(in: [], now: now(10), calendar: calendar) == nil)
    }

    /// Голое «40 мин» читалось бы длительностью встречи, а не временем
    /// до неё. В полоске чёлки слова «через» нет — там за него платят
    /// шириной острова, здесь ширины сколько угодно.
    @Test("Подпись у ещё не начавшегося считает время до него")
    func подписьДоНачала() {
        let обед = event("Обед", at: 13)
        #expect(DayAgenda.badge(for: обед, now: now(12, 20)) == tf("через %@", tf("%d мин", 40)))
    }
}


@Suite("Куда ляжет событие")
struct EventCalendarChoiceTests {
    private let list = [
        CalendarSource(id: "a", title: "Личный", colorComponents: nil),
        CalendarSource(id: "b", title: "Работа", colorComponents: nil),
        CalendarSource(id: "c", title: "Семья", colorComponents: nil),
    ]

    @Test("Перебор идёт по кругу")
    func поКругу() {
        #expect(CalendarPlanner.calendar(after: "a", in: list) == "b")
        #expect(CalendarPlanner.calendar(after: "b", in: list) == "c")
        #expect(CalendarPlanner.calendar(after: "c", in: list) == "a")
    }

    /// Событие может лежать в календаре, доступном только на чтение, —
    /// его в списке нет вовсе. Перебор тогда начинается с начала,
    /// а не отказывается работать.
    @Test("Неизвестный календарь начинает перебор с начала")
    func чужойКалендарь() {
        #expect(CalendarPlanner.calendar(after: "чужой", in: list) == "a")
        #expect(CalendarPlanner.calendar(after: nil, in: list) == "a")
    }

    @Test("Перебирать нечего, когда календарей нет")
    func пустойСписок() {
        #expect(CalendarPlanner.calendar(after: "a", in: []) == nil)
    }

    /// Круг на одном календаре замыкается сам на себя, а не выходит за край
    /// списка.
    @Test("Один календарь остаётся собой")
    func одинКалендарь() {
        let single = [CalendarSource(id: "a", title: "Личный", colorComponents: nil)]
        #expect(CalendarPlanner.calendar(after: "a", in: single) == "a")
    }
}
