import TrunookXPC
import AppKit
import Foundation

/// Заметка дня, общая с Trudaybook.
///
/// Trudaybook кладёт свою заметку дня файлом `ГГГГ-ММ-ДД.txt` в папку
/// `Application Support/Trudaybook/trunook/notes` (только если это в нём
/// включено). Здесь у каждого такого дня своя заметка «Trudaybook · 25 сентября»:
/// поправили файл — правится заметка, поправили заметку — пишется файл.
/// Кто правил последним, того и текст.
///
/// Раз в минуту, по времени правки файлов: заметку пишут руками, и минута
/// до соседа — не задержка. Удалённую здесь заметку Trudaybook не трогает,
/// а удалённый там файл не удаляет заметку здесь: стереть записанное
/// человеком из-за соседа — хуже, чем оставить лишнее.
final class DayNoteSync {
    private let notes: NotesService
    private let settings: Settings
    private let folder: URL
    private let defaults: UserDefaults
    private var timer: Timer?

    static let key = "trudaybookDayNotes"

    /// День → заметка и время правки файла, которое мы уже видели.
    struct Link: Codable, Equatable {
        var id: Int64
        var seen: Double
    }

    init(notes: NotesService, settings: Settings = .shared, folder: URL? = nil, defaults: UserDefaults = .standard) {
        self.notes = notes
        self.settings = settings
        self.defaults = defaults
        self.folder = folder ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Trudaybook/trunook/notes", isDirectory: true)
    }

    func start() {
        guard timer == nil else { return }
        sync()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.sync() }
        timer.allowCoalescing()
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private var links: [String: Link] {
        get {
            guard let data = defaults.data(forKey: Self.key) else { return [:] }
            return (try? JSONDecoder().decode([String: Link].self, from: data)) ?? [:]
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.key) }
    }

    /// День из имени файла: только `ГГГГ-ММ-ДД.txt`.
    static func day(fromFileName name: String) -> String? {
        guard name.hasSuffix(".txt") else { return nil }
        let key = String(name.dropLast(4))
        let parts = key.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        return key
    }

    /// Имя заметки: «Trudaybook · 25 сентября».
    static func title(for day: String, locale: Locale = Settings.shared.language.locale) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day) else { return "Trudaybook · \(day)" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        return "Trudaybook · " + formatter.string(from: date)
    }

    func sync() {
        guard settings.notesEnabled else { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        var links = self.links
        var changed = false
        for file in files {
            guard let day = Self.day(fromFileName: file.lastPathComponent),
                  let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modified = values.contentModificationDate,
                  (values.fileSize ?? 0) < 256 * 1024,
                  let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let link = links[day]
            let note = link.flatMap { notes.note(id: $0.id) }

            // Правили здесь, после того как видели файл, — пишем в файл.
            if let note, let link, note.updatedAt.timeIntervalSince1970 > link.seen + 1,
               note.plain.trimmingCharacters(in: .whitespacesAndNewlines) != text.trimmingCharacters(in: .whitespacesAndNewlines) {
                do {
                    try Data(note.plain.utf8).write(to: file, options: .atomic)
                    let written = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    links[day] = Link(id: note.id, seen: (written ?? Date()).timeIntervalSince1970)
                    changed = true
                    DebugLog.write("Trudaybook: заметка дня отдана в Trudaybook")
                } catch {
                    DebugLog.write("Trudaybook: заметка дня не записалась — \(error.localizedDescription)")
                }
                continue
            }

            // Файл не менялся с прошлого раза — делать нечего.
            if let link, abs(modified.timeIntervalSince1970 - link.seen) < 0.5, note != nil { continue }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let attributed = NSAttributedString(string: text)
            if let note {
                if note.plain != text { notes.save(attributed, origin: note.origin, editing: note.id) }
                links[day] = Link(id: note.id, seen: modified.timeIntervalSince1970)
            } else if let saved = notes.save(attributed, origin: .typed, title: Self.title(for: day)) {
                links[day] = Link(id: saved.id, seen: modified.timeIntervalSince1970)
                DebugLog.write("Trudaybook: заведена заметка дня")
            }
            changed = true
        }
        if changed { self.links = links }
    }
}
