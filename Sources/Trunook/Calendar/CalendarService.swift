import TrunookXPC
import Foundation
import EventKit
import AppKit
import SwiftUI

/// Читает встречи и напоминания из системного хранилища.
///
/// Рабочие календари — Exchange, Google, Яндекс — попадают сюда сами, если
/// подключены как учётные записи в системном Календаре. Отдельных интеграций
/// с их API не требуется.
final class CalendarService: ObservableObject {
    /// Ближайшие события, отсортированные по времени начала.
    @Published private(set) var upcoming: [CalendarItem] = []
    @Published private(set) var eventsAccess: EKAuthorizationStatus = .notDetermined
    @Published private(set) var remindersAccess: EKAuthorizationStatus = .notDetermined
    /// Календари и списки напоминаний, доступные для выбора в настройках.
    @Published private(set) var availableCalendars: [CalendarSource] = []
    @Published private(set) var availableReminderLists: [CalendarSource] = []

    private let store = EKEventStore()
    private let settings: Settings
    private var refreshTimer: Timer?
    /// Состояние доступа попадало в журнал хотя бы раз.
    private var accessLogged = false

    /// Насколько далеко вперёд смотрим.
    private static let horizon: TimeInterval = 24 * 3600

    init(settings: Settings = .shared) {
        self.settings = settings
        refreshAuthorization()
    }

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeChanged),
            name: .EKEventStoreChanged,
            object: store
        )
        // На первом запуске доступы спрашивает окно знакомства — там сначала
        // объясняют, зачем они. Молча выскочивший диалог система показывает
        // ровно один раз, и отказ на нём уже не переспросить.
        if settings.hasSeenWelcome { requestAccessIfNeeded() }

        // Раз в минуту: события могут начаться или закончиться сами по себе,
        // без изменений в хранилище.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        NotificationCenter.default.removeObserver(self, name: .EKEventStoreChanged, object: store)
    }

    @objc private func storeChanged() {
        refresh()
    }

    // MARK: - Доступ

    func refreshAuthorization() {
        let events = EKEventStore.authorizationStatus(for: .event)
        let reminders = EKEventStore.authorizationStatus(for: .reminder)

        // Окно знакомства опрашивает состояние раз в секунду: доступ выдают
        // в Системных настройках, и обратного вызова оттуда не приходит.
        // Без этой проверки журнал захлебнулся бы, а вьюхи перерисовывались
        // бы вхолостую.
        guard !accessLogged || events != eventsAccess || reminders != remindersAccess else {
            return
        }
        accessLogged = true
        eventsAccess = events
        remindersAccess = reminders
        DebugLog.write("доступ: календарь \(Self.describe(events)), "
                       + "напоминания \(Self.describe(reminders))")
    }

    private static func describe(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "не запрошен"
        case .restricted: return "ограничен"
        case .denied: return "запрещён"
        case .fullAccess: return "полный"
        case .writeOnly: return "только запись"
        @unknown default: return "неизвестно"
        }
    }

    /// Запрашивает доступ, если он ещё не определён. Система покажет диалог
    /// один раз; при отказе повторный запрос ничего не даст — там нужен путь
    /// через Системные настройки.
    func requestAccessIfNeeded() {
        if settings.calendarEnabled { requestEventsAccess() }
        if settings.remindersEnabled { requestRemindersAccess() }
        refresh()
    }

    /// Календарь и напоминания спрашиваются по отдельности: в окне знакомства
    /// это две самостоятельные строки, и нажатие на одну не должно поднимать
    /// диалог о другой.
    func requestEventsAccess() {
        guard eventsAccess == .notDetermined else { return }
        store.requestFullAccessToEvents { [weak self] granted, error in
            DispatchQueue.main.async {
                DebugLog.write("календарь: доступ \(granted ? "выдан" : "отклонён")"
                               + (error.map { ", \($0.localizedDescription)" } ?? ""))
                self?.refreshAuthorization()
                self?.refresh()
            }
        }
    }

    func requestRemindersAccess() {
        guard remindersAccess == .notDetermined else { return }
        store.requestFullAccessToReminders { [weak self] granted, error in
            DispatchQueue.main.async {
                DebugLog.write("напоминания: доступ \(granted ? "выдан" : "отклонён")"
                               + (error.map { ", \($0.localizedDescription)" } ?? ""))
                self?.refreshAuthorization()
                self?.refresh()
            }
        }
    }

    /// Разделы Системных настроек, куда ведём после отказа: повторный запрос
    /// система уже не покажет, и выдать доступ можно только там.
    enum PrivacyPane: String {
        case calendars = "Privacy_Calendars"
        case reminders = "Privacy_Reminders"
    }

    static func openPrivacySettings(_ pane: PrivacyPane = .calendars) {
        let address = "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)"
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Чтение

    func refresh() {
        var collected: [CalendarItem] = []

        if settings.calendarEnabled, eventsAccess == .fullAccess {
            collected += readEvents()
        }

        if settings.remindersEnabled, remindersAccess == .fullAccess {
            readReminders { [weak self] reminders in
                guard let self else { return }
                self.publish(collected + reminders)
            }
        } else {
            publish(collected)
        }
    }

    private func publish(_ items: [CalendarItem]) {
        let sorted = items.sorted { $0.start < $1.start }
        if sorted.count != upcoming.count {
            DebugLog.write("календарь: событий впереди — \(sorted.count)"
                           + (sorted.first.map { ", ближайшее «\($0.title)» в \($0.timeLabel)" } ?? ""))
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard sorted != self.upcoming else { return }
            self.upcoming = sorted
        }
    }

    /// Обновляет списки для настроек. Отдельно от чтения событий: списки
    /// нужны в окне настроек и когда сами события выключены.
    func refreshSources() {
        if eventsAccess == .fullAccess {
            availableCalendars = store.calendars(for: .event).map(CalendarSource.init)
        }
        if remindersAccess == .fullAccess {
            availableReminderLists = store.calendars(for: .reminder).map(CalendarSource.init)
        }
    }

    private func readEvents() -> [CalendarItem] {
        let calendars = store.calendars(for: .event)
        availableCalendars = calendars.map(CalendarSource.init)

        let enabled = settings.enabledCalendarIDs
        // Пустой набор означает «все»: так новый календарь, добавленный
        // в системе, появляется в вырезе сам, без похода в настройки.
        let selected = enabled.isEmpty ? calendars : calendars.filter { enabled.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { return [] }

        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-3600),
            end: now.addingTimeInterval(Self.horizon),
            calendars: selected
        )

        return store.events(matching: predicate).compactMap { event in
            // Отменённые и уже прошедшие показывать незачем.
            guard event.status != .canceled else { return nil }
            guard let start = event.startDate else { return nil }
            guard let end = event.endDate ?? event.startDate, end > now else { return nil }

            return CalendarItem(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? t("Без названия"),
                start: start,
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

    private func readReminders(completion: @escaping ([CalendarItem]) -> Void) {
        let now = Date()
        let lists = store.calendars(for: .reminder)
        availableReminderLists = lists.map(CalendarSource.init)

        let enabled = settings.enabledReminderListIDs
        // Пустой набор означает «все списки», в том числе новые.
        let selected = enabled.isEmpty ? lists : lists.filter { enabled.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else {
            completion([])
            return
        }

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: now.addingTimeInterval(-3600),
            ending: now.addingTimeInterval(Self.horizon),
            calendars: selected
        )
        store.fetchReminders(matching: predicate) { reminders in
            let items = (reminders ?? []).compactMap { reminder -> CalendarItem? in
                guard let components = reminder.dueDateComponents,
                      let due = Calendar.current.date(from: components)
                else { return nil }

                return CalendarItem(
                    id: reminder.calendarItemIdentifier,
                    title: reminder.title ?? t("Напоминание"),
                    start: due,
                    end: nil,
                    // У напоминания без времени компоненты содержат только дату.
                    isAllDay: components.hour == nil,
                    source: .reminder,
                    link: MeetingLink.extract(url: nil, location: nil, notes: reminder.notes),
                    colorComponents: ColorReader.srgbComponents(of: reminder.calendar)
                )
            }
            completion(items)
        }
    }
}

/// Календарь или список напоминаний — для выбора в настройках.
struct CalendarSource: Identifiable, Equatable {
    let id: String
    let title: String
    let colorComponents: [CGFloat]?

    init(_ calendar: EKCalendar) {
        id = calendar.calendarIdentifier
        title = calendar.title
        colorComponents = ColorReader.srgbComponents(of: calendar)
    }

    var color: Color {
        guard let colorComponents, colorComponents.count >= 3 else { return .accentColor }
        return Color(
            red: Double(colorComponents[0]),
            green: Double(colorComponents[1]),
            blue: Double(colorComponents[2])
        )
    }
}

/// Цвет календаря приходит в произвольном цветовом пространстве, а рисовать
/// его надо в sRGB. Отдельный тип, чтобы не расширять `CGColor` свойством
/// с именем существующего — такое расширение молча ушло бы в рекурсию.
enum ColorReader {
    static func srgbComponents(of calendar: EKCalendar?) -> [CGFloat]? {
        // На macOS цвет календаря приходит как NSColor, на iOS — как CGColor.
        guard let srgb = calendar?.color?.usingColorSpace(.sRGB) else { return nil }
        return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
    }
}
