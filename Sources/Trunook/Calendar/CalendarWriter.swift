import TrunookXPC
import Foundation
import EventKit

/// Чтение дня, разметка месяца и правка событий.
///
/// Отдельным расширением, а не в теле `CalendarService`: там служба отвечает
/// на один вопрос — «что впереди», — и отвечает им вырезу. Здесь другой
/// разговор: произвольный день, произвольный месяц и запись обратно.
/// Смешав их, пришлось бы объяснять в каждом методе, к какому из двух
/// он относится.
///
/// Записи без полного доступа не будет: `EKAuthorizationStatus.writeOnly`
/// разрешает завести событие, но не прочитать — а править вслепую нельзя.
extension CalendarService {
    /// События выбранного дня, включая прошедшие: это календарь, а не список
    /// того, что впереди. День без прошедших встреч выглядел бы пустым
    /// в шесть вечера, и человек решил бы, что их и не было.
    func events(on day: Date, calendar: Calendar = .current) -> [CalendarItem] {
        guard eventsAccess == .fullAccess else { return [] }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return items(from: start, to: end)
            .sorted { lhs, rhs in
                // События на весь день — первыми: у них нет часа, и вставать
                // им в общем ряду по полуночи значило бы обещать время,
                // которого нет.
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.start < rhs.start
            }
    }

    /// Числа месяца, в которые что-то есть, — по ним рисуются точки под датой.
    func markedDays(inMonthOf anchor: Date, calendar: Calendar = .current) -> Set<Int> {
        guard eventsAccess == .fullAccess else { return [] }
        let start = CalendarMonth.firstDay(ofMonthOf: anchor, calendar: calendar)
        guard let end = calendar.date(byAdding: .month, value: 1, to: start) else { return [] }
        var days: Set<Int> = []
        for item in items(from: start, to: end) {
            days.insert(calendar.component(.day, from: item.start))
        }
        return days
    }

    /// Календари, в которые вообще можно писать.
    ///
    /// Не те, что показываются в вырезе: список показываемых отбирает, что
    /// видно, а этот — куда можно положить. Выбрав календарь руками, человек
    /// говорит именно о втором, и молча отказывать ему потому, что календарь
    /// сейчас скрыт, было бы подменой его же решения.
    func writableCalendars() -> [CalendarSource] {
        guard eventsAccess == .fullAccess else { return [] }
        return store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map(CalendarSource.init)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Куда ляжет новое событие, пока человек не выбрал иначе.
    func defaultCalendarID() -> String? {
        defaultCalendar()?.calendarIdentifier
    }

    /// Полные поля события — то, что показывает окно правки.
    ///
    /// Спрашивается по записи из списка, а не по одному идентификатору:
    /// у всех вхождений повторяющегося события идентификатор общий, и найти
    /// нужное можно только вместе с его временем начала.
    func draft(for item: CalendarItem) -> EventDraft? {
        guard eventsAccess == .fullAccess,
              let event = occurrence(id: item.id, start: item.start)
        else { return nil }
        let start = event.startDate ?? item.start
        let end = event.endDate ?? start.addingTimeInterval(EventDraft.defaultDuration)
        return EventDraft(
            id: item.id,
            title: event.title ?? "",
            start: start,
            duration: max(EventDraft.step, end.timeIntervalSince(start)),
            isAllDay: event.isAllDay,
            location: event.location ?? "",
            notes: event.notes ?? "",
            link: MeetingLink.extract(url: event.url, location: event.location, notes: event.notes),
            calendarID: event.calendar?.calendarIdentifier,
            colorComponents: ColorReader.srgbComponents(of: event.calendar),
            attendees: Self.attendees(of: event),
            isRecurring: event.hasRecurrenceRules,
            originalStart: start
        )
    }

    /// Приглашённые — именами и ответами.
    ///
    /// Имени у участника может не быть вовсе: почтовые календари шлют один
    /// адрес. Тогда показывается он — «неизвестный участник» не отвечает
    /// ни на один вопрос, а адрес отвечает хотя бы на «кто это».
    private static func attendees(of event: EKEvent) -> [EventDraft.Attendee] {
        (event.attendees ?? []).map { participant in
            let address = participant.url.absoluteString
                .replacingOccurrences(of: "mailto:", with: "")
            let name = participant.name?.isEmpty == false ? participant.name! : address
            return EventDraft.Attendee(
                name: name,
                status: status(of: participant.participantStatus),
                isMe: participant.isCurrentUser
            )
        }
    }

    private static func status(of value: EKParticipantStatus) -> EventDraft.Attendee.Status {
        switch value {
        case .accepted: return .accepted
        case .declined: return .declined
        case .tentative: return .tentative
        default: return .pending
        }
    }

    /// То самое вхождение, по которому нажали.
    ///
    /// `event(withIdentifier:)` у повторяющегося события отдаёт **первое**
    /// вхождение, а не нужное: идентификатор у ряда один на всех. Сохранив
    /// правку в него, мы перенесли бы не ту встречу — и заметить это можно
    /// было бы только в Календаре, задним числом.
    ///
    /// Поэтому нужное ищется по дню и сверяется по времени начала.
    private func occurrence(id: String, start: Date) -> EKEvent? {
        guard let direct = store.event(withIdentifier: id) else { return nil }
        guard direct.hasRecurrenceRules else { return direct }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: start)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return direct
        }
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        let found = store.events(matching: predicate).first { event in
            guard event.eventIdentifier == id, let begins = event.startDate else { return false }
            // С точностью до минуты: у события на весь день начало — полночь,
            // и посекундного совпадения от хранилища ждать не приходится.
            return abs(begins.timeIntervalSince(start)) < 60
        }
        return found ?? direct
    }

    /// Записать. Возвращает `true`, если хранилище приняло.
    ///
    /// Повторяющееся событие правится **одним вхождением**, если человек
    /// не сказал иначе. Разница здесь молчаливая и необратимая: перенеся одну
    /// встречу на час, он не ждёт, что переедут все прошлые и будущие, —
    /// а откатить это в Календаре потом нечем. Выбор «всю серию» есть, но
    /// его надо сделать нарочно.
    @discardableResult
    func save(_ draft: EventDraft) -> Bool {
        guard eventsAccess == .fullAccess else {
            DebugLog.write("календарь: сохранять нечем — доступ не полный")
            return false
        }
        let event: EKEvent
        if let id = draft.id,
           let existing = occurrence(id: id, start: draft.originalStart ?? draft.start) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
        }
        // Выбранный человеком календарь важнее всего: и у нового события,
        // и у существующего — переложить встречу из личного календаря
        // в рабочий это то же самое действие, что и положить её туда сразу.
        if let chosen = draft.calendarID,
           let target = store.calendar(withIdentifier: chosen),
           target.allowsContentModifications,
           event.calendar?.calendarIdentifier != chosen {
            event.calendar = target
        }
        if event.calendar == nil { event.calendar = defaultCalendar() }
        guard event.calendar != nil else {
            DebugLog.write("календарь: некуда писать — календаря по умолчанию нет")
            return false
        }
        event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.isAllDay = draft.isAllDay
        event.location = draft.location.isEmpty ? nil : draft.location
        event.notes = draft.notes.isEmpty ? nil : draft.notes
        if draft.isAllDay {
            let day = Calendar.current.startOfDay(for: draft.start)
            event.startDate = day
            event.endDate = day
        } else {
            event.startDate = draft.start
            event.endDate = draft.end
        }
        let span: EKSpan = draft.editsSeries ? .futureEvents : .thisEvent
        do {
            try store.save(event, span: span, commit: true)
            DebugLog.write("календарь: сохранено «\(event.title ?? "")» "
                           + (draft.isNew ? "новым" : "правкой")
                           + (draft.isRecurring ? (draft.editsSeries ? ", весь ряд" : ", одно вхождение") : ""))
            refresh()
            return true
        } catch {
            DebugLog.write("календарь: не сохранить — \(error.localizedDescription)")
            return false
        }
    }

    /// Удалить. Тем же правилом, что и сохранение: одно вхождение, если
    /// не сказано иначе. Здесь это важнее вдвойне — удаление ряда не
    /// отменяется вовсе.
    @discardableResult
    func delete(_ draft: EventDraft) -> Bool {
        guard eventsAccess == .fullAccess, let id = draft.id,
              let event = occurrence(id: id, start: draft.originalStart ?? draft.start)
        else { return false }
        let span: EKSpan = draft.editsSeries ? .futureEvents : .thisEvent
        do {
            try store.remove(event, span: span, commit: true)
            DebugLog.write("календарь: удалено «\(event.title ?? "")»"
                           + (draft.isRecurring ? (draft.editsSeries ? ", весь ряд" : ", одно вхождение") : ""))
            refresh()
            return true
        } catch {
            DebugLog.write("календарь: не удалить — \(error.localizedDescription)")
            return false
        }
    }

    /// Куда пишутся новые события.
    ///
    /// Календарь по умолчанию системы, но только если он в выбранных: иначе
    /// заведённое событие ушло бы в календарь, которого человек в вырезе
    /// не видит, — и выглядело бы пропавшим.
    private func defaultCalendar() -> EKCalendar? {
        let enabled = settings.enabledCalendarIDs
        let writable = store.calendars(for: .event).filter { $0.allowsContentModifications }
        if let system = store.defaultCalendarForNewEvents,
           system.allowsContentModifications,
           enabled.isEmpty || enabled.contains(system.calendarIdentifier) {
            return system
        }
        if enabled.isEmpty { return writable.first }
        return writable.first { enabled.contains($0.calendarIdentifier) } ?? writable.first
    }

    /// Общее чтение отрезка: и день, и месяц спрашивают одно и то же.
    private func items(from start: Date, to end: Date) -> [CalendarItem] {
        let calendars = store.calendars(for: .event)
        let enabled = settings.enabledCalendarIDs
        // Пустой набор означает «все» — то же правило, что и у ленты выреза.
        let selected = enabled.isEmpty
            ? calendars
            : calendars.filter { enabled.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
        return store.events(matching: predicate).compactMap { event in
            guard event.status != .canceled, let begins = event.startDate else { return nil }
            return CalendarItem(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? t("Без названия"),
                start: begins,
                end: event.endDate,
                isAllDay: event.isAllDay,
                source: .event,
                link: MeetingLink.extract(
                    url: event.url,
                    location: event.location,
                    notes: event.notes
                ),
                colorComponents: ColorReader.srgbComponents(of: event.calendar)
            )
        }
    }
}
