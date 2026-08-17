import TrunookXPC
import Foundation
import AppKit

/// Задача из Things на сегодня.
struct ThingsTask: Equatable {
    let title: String
    /// Время напоминания, если оно назначено.
    let remindAt: Date?
}

/// Задачи из Things 3 на сегодня.
///
/// Things не публикует задачи в EventKit, поэтому читаем их через AppleScript.
///
/// **Время напоминания через AppleScript недоступно.** Проверено на живых
/// задачах с назначенным напоминанием: `activation date` отдаёт сегодняшнюю
/// полночь, `due date` — `missing value`. В словаре Things свойства для
/// времени напоминания просто нет.
///
/// Время лежит в поле `reminderTime` базы Things, но она живёт в групповом
/// контейнере, куда без «Полного доступа к диску» не попасть. Разбор
/// `remindAt` оставлен готовым: если такое разрешение появится, сюда
/// достаточно подставить чтение базы, а планировщик уже подключён.
final class ThingsService: ObservableObject {
    @Published private(set) var tasks: [ThingsTask] = []
    @Published private(set) var isAvailable = false

    var todayTitles: [String] { tasks.map(\.title) }

    /// Задачи с назначенным временем — для планировщика предупреждений.
    var reminders: [CalendarItem] {
        tasks.compactMap { task in
            guard let remindAt = task.remindAt else { return nil }
            return CalendarItem(
                // Идентификатор устойчив между чтениями: по нему планировщик
                // помнит, что уже предупреждал об этой задаче.
                id: "things:\(task.title)@\(Int(remindAt.timeIntervalSince1970))",
                title: task.title,
                start: remindAt,
                end: nil,
                isAllDay: false,
                source: .things,
                link: nil,
                colorComponents: [0.36, 0.55, 0.94]
            )
        }
    }

    private let settings: Settings
    private var timer: Timer?
    /// Отдельно от `tasks`, чтобы отличить первое чтение от пустого списка.
    private var lastLoggedCount = -1

    /// NSAppleScript не потокобезопасен, поэтому все обращения — на одной
    /// выделенной очереди. На главном потоке их держать нельзя: обращение
    /// к чужому приложению занимает сотни миллисекунд.
    private let queue = DispatchQueue(label: "com.trunook.things")

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    func start() {
        refresh()
        // Раз в минуту, а не раз в пять: задачу заводят и тут же смотрят,
        // появилась ли она. Запрос лёгкий, Things отвечает за миллисекунды.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Печатает сырой ответ Things со всеми датами — чем именно он отвечает,
    /// по документации не понять.
    func dumpRaw() {
        queue.async {
            let source = """
            tell application "Things3"
                set output to ""
                repeat with t in to dos of list id "TMTodayListSource"
                    set output to output & (name of t) & " | activation=" & ¬
                        ((activation date of t) as string) & " | due=" & ¬
                        ((due date of t) as string) & linefeed
                end repeat
                return output
            end tell
            """
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source) else { return }
            let result = script.executeAndReturnError(&error)
            if let error {
                DebugLog.write("Things сырой: ошибка \(error[NSAppleScript.errorMessage] ?? error)")
                return
            }
            for line in (result.stringValue ?? "").split(separator: "\n") {
                DebugLog.write("Things сырой: \(line)")
            }
        }
    }

    /// Открывает список «Сегодня» в самом Things.
    static func openToday() {
        guard let url = URL(string: "things:///show?id=today") else { return }
        NSWorkspace.shared.open(url)
    }

    func refresh() {
        guard settings.thingsEnabled else {
            clear()
            return
        }

        // Запускать Things ради списка задач нельзя: AppleScript поднял бы
        // приложение молча, без ведома пользователя.
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.culturedcode.ThingsMac"
        }
        guard running else {
            clear()
            return
        }

        queue.async { [weak self] in
            let tasks = Self.readToday()
            DispatchQueue.main.async {
                guard let self else { return }
                if tasks.count != self.lastLoggedCount {
                    self.lastLoggedCount = tasks.count
                    let timed = tasks.filter { $0.remindAt != nil }.count
                    DebugLog.write("Things: задач на сегодня — \(tasks.count), с напоминанием — \(timed)")
                }
                self.tasks = tasks
                self.isAvailable = !tasks.isEmpty
            }
        }
    }

    private func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.tasks = []
            self?.isAvailable = false
        }
    }

    // MARK: - AppleScript

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func readToday() -> [ThingsTask] {
        // Список берём по идентификатору, а не по имени: имя "Today"
        // работает только в англоязычной сборке Things, а в локализованной
        // запрос падает с «не удается получить list».
        //
        // Дату собираем по компонентам, а не приводим к строке: строковое
        // представление даты в AppleScript зависит от локали системы.
        let source = """
        on pad(n)
            set s to n as string
            if length of s < 2 then set s to "0" & s
            return s
        end pad

        tell application "Things3"
            set output to ""
            repeat with t in to dos of list id "TMTodayListSource"
                set stamp to ""
                try
                    set d to activation date of t
                    if d is not missing value then
                        set stamp to (year of d as string) & "-" & my pad(month of d as integer) & "-" & my pad(day of d) & " " & my pad(hours of d) & ":" & my pad(minutes of d)
                    end if
                end try
                set output to output & (name of t) & tab & stamp & linefeed
            end repeat
            return output
        end tell
        """

        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return [] }
        let result = script.executeAndReturnError(&error)

        if let error {
            DebugLog.write("Things: \(error[NSAppleScript.errorMessage] ?? error)")
            return []
        }

        return (result.stringValue ?? "")
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.components(separatedBy: "\t")
                let title = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
                guard !title.isEmpty else { return nil }

                let stamp = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
                return ThingsTask(title: title, remindAt: reminderDate(from: stamp))
            }
    }

    /// Дата активации без времени означает «просто на сегодня», а не
    /// напоминание: для таких задач Things отдаёт полночь.
    private static func reminderDate(from stamp: String) -> Date? {
        guard !stamp.isEmpty, let date = dateFormatter.date(from: stamp) else { return nil }
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard (components.hour ?? 0) != 0 || (components.minute ?? 0) != 0 else { return nil }
        return date
    }
}
