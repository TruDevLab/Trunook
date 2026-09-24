import TrunookXPC
import AppKit
import Foundation

/// Сводка соседнего приложения Trudaybook (почта и календарь на шкале дня):
/// сколько писем не разобрано, сколько из них важных, главное письмо
/// и когда пришли сегодняшние письма.
///
/// Файлом, а не сетью и не своей схемой — тем же способом, каким Trudaybook
/// присылает плашки во входящие: `state.json` пишет Trudaybook, мы только
/// читаем. Адресов и текста писем в нём нет; тему главного письма
/// Trudaybook кладёт, только если это разрешено в его настройках.
struct TrudaybookSummary: Equatable {
    struct Letter: Equatable {
        let title: String
        let from: String
    }

    struct Mark: Equatable {
        let time: Date
        let important: Bool
        let done: Bool
    }

    let updated: Date
    let unresolved: Int
    let important: Int
    let top: Letter?
    let marks: [Mark]
    /// Trudaybook разрешил помощнику работать с почтой.
    let acceptsCommands: Bool

    /// Потолок файла: сводка — это десяток чисел и сотня отметок.
    static let maxFileSize = 256 * 1024
    /// Trudaybook переписывает сводку не реже раза в пять минут; тишина
    /// дольше четверти часа значит, что он закрыт.
    static let freshness: TimeInterval = 15 * 60

    init(updated: Date, unresolved: Int, important: Int, top: Letter? = nil, marks: [Mark] = [],
         acceptsCommands: Bool = false) {
        self.acceptsCommands = acceptsCommands
        self.updated = updated
        self.unresolved = unresolved
        self.important = important
        self.top = top
        self.marks = marks
    }

    /// Разбор файла. Всё, что не сошлось, — `nil`: плитка тогда скажет
    /// «нет сводки», а не покажет полуразобранные числа.
    init?(data: Data) {
        guard data.count <= Self.maxFileSize,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (json["version"] as? NSNumber)?.intValue == 1,
              let updated = Self.date(json["updated"]),
              let unresolved = (json["unresolved"] as? NSNumber)?.intValue
        else { return nil }
        self.updated = updated
        self.unresolved = min(max(unresolved, 0), 99_999)
        important = min(max((json["important"] as? NSNumber)?.intValue ?? 0, 0), self.unresolved)
        if let top = json["top"] as? [String: Any], let title = top["title"] as? String {
            self.top = Letter(title: String(title.prefix(120)), from: String(((top["from"] as? String) ?? "").prefix(60)))
        } else {
            top = nil
        }
        acceptsCommands = (json["commands"] as? NSNumber)?.boolValue ?? false
        let raw = (json["marks"] as? [[String: Any]]) ?? []
        marks = raw.prefix(500).compactMap { mark in
            guard let time = Self.date(mark["time"]) else { return nil }
            return Mark(time: time,
                        important: (mark["important"] as? NSNumber)?.boolValue ?? false,
                        done: (mark["done"] as? NSNumber)?.boolValue ?? false)
        }
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(updated)
        return age < Self.freshness && age > -60
    }

    /// Отметки писем на шкале выбранного дня — минутами от полуночи.
    func marks(on day: Date, calendar: Calendar = .current) -> [DayMailMark] {
        let start = calendar.startOfDay(for: day)
        return marks.compactMap { mark in
            let minute = Int(mark.time.timeIntervalSince(start) / 60)
            guard minute >= 0, minute < 24 * 60 else { return nil }
            return DayMailMark(minute: minute, important: mark.important, done: mark.done)
        }
    }
}

/// Письмо на шкале дня: во сколько пришло и разобрано ли.
struct DayMailMark: Equatable, Hashable {
    let minute: Int
    let important: Bool
    let done: Bool
}

/// Следит за сводкой Trudaybook: раз в минуту сверяет время правки файла
/// и перечитывает его, только если он изменился. Одна проверка атрибутов
/// файла в минуту — ничто рядом с пробуждениями самого выреза.
final class TrudaybookFeed: ObservableObject {
    static let shared = TrudaybookFeed()
    static let bundleID = "com.trudaybook.Trudaybook"

    @Published private(set) var summary: TrudaybookSummary?

    private let file: URL
    private var timer: Timer?
    private var modified: Date?

    init(file: URL? = nil) {
        self.file = file ?? Self.defaultFile
    }

    static var defaultFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Trudaybook/trunook/state.json")
    }

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Открыть Trudaybook.
    static func openApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        timer.allowCoalescing()
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Перечитать, если файл менялся. Пропал — сводки нет: Trudaybook
    /// убирает его, когда связь выключают.
    func refresh() {
        let date = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        guard date != modified else { return }
        modified = date
        guard date != nil, let data = try? Data(contentsOf: file) else {
            if summary != nil { summary = nil }
            return
        }
        let parsed = TrudaybookSummary(data: data)
        if parsed == nil { DebugLog.write("Trudaybook: сводка не разобралась") }
        if parsed != summary { summary = parsed }
    }

    /// Сводка, если она свежая.
    func current(at now: Date = Date()) -> TrudaybookSummary? {
        summary.flatMap { $0.isFresh(at: now) ? $0 : nil }
    }
}
