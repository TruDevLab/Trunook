import TrunookXPC
import Foundation

/// Что показывает мини-календарь и что сейчас правят.
///
/// Отдельный объект, а не значения в теле вида: `@State` в этом тулчейне
/// недоступен, а держать выбранный день, листаемый месяц и открытый черновик
/// негде — панель пересобирается на каждое нажатие.
///
/// Просмотр и правка живут вместе намеренно. Это одна работа: в календарь
/// заходят посмотреть день, находят в нём встречу, правят её и возвращаются
/// в тот же день. Разведи их по двум объектам — и пришлось бы передавать
/// между ними и день, и месяц, и то, куда возвращаться по закрытии.
final class CalendarPlanner: ObservableObject {
    /// Первое число листаемого месяца.
    @Published private(set) var month: Date
    /// Полночь выбранного дня.
    @Published private(set) var day: Date
    /// События выбранного дня.
    @Published private(set) var events: [CalendarItem] = []
    /// Числа месяца, в которые что-то есть.
    @Published private(set) var marked: Set<Int> = []

    /// Календари, в которые можно писать. Из них выбирают в окне правки.
    @Published private(set) var calendars: [CalendarSource] = []

    /// Событие, открытое на правку. `nil` — окна правки нет.
    @Published private(set) var draft: EventDraft?
    /// Закрыв правку, возвращаемся в календарь, а не в пустоту.
    ///
    /// Правку открывают из двух мест: из самого календаря и с главного
    /// экрана, нажатием по строке события. Возврат в календарь из главного
    /// экрана был бы подменой — человек туда не заходил.
    @Published private(set) var returnsToCalendar = false

    private let calendar = Calendar.current
    private unowned let service: CalendarService

    init(service: CalendarService, now: Date = Date()) {
        self.service = service
        let today = Calendar.current.startOfDay(for: now)
        day = today
        month = CalendarMonth.firstDay(ofMonthOf: today)
    }

    var grid: CalendarMonth { CalendarMonth.make(monthOf: month, calendar: calendar) }

    func isToday(_ date: Date) -> Bool { calendar.isDateInToday(date) }
    func isSelected(_ date: Date) -> Bool { calendar.isDate(date, inSameDayAs: day) }
    func hasEvents(_ date: Date) -> Bool {
        guard calendar.isDate(date, equalTo: month, toGranularity: .month) else { return false }
        return marked.contains(calendar.component(.day, from: date))
    }

    // MARK: - Просмотр

    /// Открыли календарь. Всегда с сегодняшнего дня: вернуться через неделю
    /// и увидеть прошлый вторник, на котором закрыли, — не то, зачем
    /// календарь открывают.
    func open(now: Date = Date()) {
        let today = calendar.startOfDay(for: now)
        day = today
        month = CalendarMonth.firstDay(ofMonthOf: today, calendar: calendar)
        reload()
    }

    func select(_ date: Date) {
        let picked = calendar.startOfDay(for: date)
        // Ткнули в хвост соседнего месяца — листаем туда же: клетка показывает
        // тот день, и остаться в прежнем месяце значило бы выбрать день,
        // которого в сетке уже не видно.
        if !calendar.isDate(picked, equalTo: month, toGranularity: .month) {
            month = CalendarMonth.firstDay(ofMonthOf: picked, calendar: calendar)
        }
        day = picked
        reload()
    }

    func step(months: Int) {
        month = CalendarMonth.shifted(month, byMonths: months, calendar: calendar)
        reload()
    }

    /// Перечитать день и разметку месяца.
    ///
    /// Зовётся и после правки: хранилище сообщает об изменениях своим
    /// уведомлением, но приходит оно не сразу, а список должен показать
    /// сохранённое тем же движением, каким его сохранили.
    func reload() {
        events = service.events(on: day, calendar: calendar)
        marked = service.markedDays(inMonthOf: month, calendar: calendar)
        calendars = service.writableCalendars()
    }

    // MARK: - Правка

    /// Открыть событие на правку.
    ///
    /// Из календаря — с возвратом в него, с главного экрана — без.
    func edit(_ item: CalendarItem, fromCalendar: Bool) {
        guard let found = service.draft(for: item) else {
            DebugLog.write("календарь: событие «\(item.title)» не найдено в хранилище")
            return
        }
        returnsToCalendar = fromCalendar
        draft = found
    }

    /// Завести новое на выбранный день.
    func compose(now: Date = Date()) {
        returnsToCalendar = true
        if calendars.isEmpty { calendars = service.writableCalendars() }
        draft = EventDraft.blank(
            on: day,
            calendarID: service.defaultCalendarID(),
            now: now,
            calendar: calendar
        )
    }

    /// Положить событие в другой календарь.
    func chooseCalendar(_ id: String) {
        change { var copy = $0; copy.calendarID = id; return copy }
    }

    /// Следующий календарь по кругу — то же движение, что и у переключения
    /// динамиков в панели встречи: список короткий, и перебор нажатием
    /// дешевле выпадающего меню, которое в вырезе пришлось бы куда-то класть.
    func cycleCalendar() {
        guard let draft,
              let next = Self.calendar(after: draft.calendarID, in: calendars)
        else { return }
        chooseCalendar(next)
    }

    /// Следующий за нынешним, по кругу.
    ///
    /// Чистой функцией и отдельно: круг легко замкнуть на единице —
    /// «следующий за последним» и «следующий за неизвестным» это два разных
    /// края, и оба возвращают первый, но по разным причинам. Проверяется
    /// тестом, а не перебором вручную в живом календаре человека.
    static func calendar(after current: String?, in list: [CalendarSource]) -> String? {
        guard !list.isEmpty else { return nil }
        // Календаря нет в списке вовсе — например, событие лежит в чужом,
        // доступном только на чтение. Тогда первый: перебор начинается
        // с начала, а не отказывается работать.
        guard let index = list.firstIndex(where: { $0.id == current }) else {
            return list[0].id
        }
        return list[(index + 1) % list.count].id
    }

    /// Правка полей. Замыканием, а не двусторонней связью: черновик
    /// публикуется целиком, и подменять его по кусочку значило бы завести
    /// столько же связей, сколько полей.
    func change(_ transform: (EventDraft) -> EventDraft) {
        guard let draft else { return }
        self.draft = transform(draft)
    }

    func changeTitle(_ text: String) {
        change { var copy = $0; copy.title = text; return copy }
    }

    func changeLocation(_ text: String) {
        change { var copy = $0; copy.location = text; return copy }
    }

    func changeNotes(_ text: String) {
        change { var copy = $0; copy.notes = text; return copy }
    }

    /// Правится один раз или весь ряд.
    ///
    /// Переключается только у повторяющегося события: у одиночного выбирать
    /// не из чего, и переключатель там обещал бы разницу, которой нет.
    func setEditsSeries(_ value: Bool) {
        change { draft in
            guard draft.isRecurring else { return draft }
            var copy = draft
            copy.editsSeries = value
            return copy
        }
    }

    func toggleAllDay() {
        change { var copy = $0; copy.isAllDay.toggle(); return copy }
    }

    /// Сохранить. Возвращает `true`, если правка закончена и окно можно закрыть.
    @discardableResult
    func save() -> Bool {
        guard let draft, draft.isSavable else { return false }
        guard service.save(draft) else { return false }
        // День уезжает за событием: перенеся встречу на завтра, человек
        // ждёт увидеть её, а не пустой сегодняшний день.
        select(draft.start)
        self.draft = nil
        return true
    }

    @discardableResult
    func deleteEditing() -> Bool {
        guard let draft, draft.id != nil else { return false }
        guard service.delete(draft) else { return false }
        self.draft = nil
        reload()
        return true
    }

    func cancelEditing() {
        draft = nil
    }
}
