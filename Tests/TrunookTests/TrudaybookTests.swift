import Foundation
import Testing
@testable import Trunook

/// Соседство с Trudaybook: его сводка и наш фокус.
@Suite("Trudaybook")
struct TrudaybookTests {
    private let now = ISO8601DateFormatter().date(from: "2026-09-25T10:00:00Z")!

    private func summary(_ json: String) -> TrudaybookSummary? {
        TrudaybookSummary(data: Data(json.utf8))
    }

    @Test("Сводка разбирается, числа не выходят за разумное")
    func разбор() {
        let parsed = summary("""
        {"version":1,"updated":"2026-09-25T09:59:00Z","unresolved":12,"important":40,
         "top":{"title":"Договор","from":"Козлов"},
         "marks":[{"time":"2026-09-25T07:12:00Z","important":true,"done":false},{"time":"не дата"}]}
        """)
        #expect(parsed?.unresolved == 12)
        // Важных не может быть больше, чем неразобранных.
        #expect(parsed?.important == 12)
        #expect(parsed?.top == TrudaybookSummary.Letter(title: "Договор", from: "Козлов"))
        #expect(parsed?.marks.count == 1)
        #expect(parsed?.isFresh(at: now) == true)
        #expect(parsed?.isFresh(at: now.addingTimeInterval(3600)) == false)
    }

    @Test("Чужая версия и мусор — не сводка")
    func мусор() {
        #expect(summary(#"{"version":2,"updated":"2026-09-25T09:59:00Z","unresolved":1}"#) == nil)
        #expect(summary(#"{"version":1,"unresolved":1}"#) == nil)
        #expect(summary("не json") == nil)
        #expect(TrudaybookSummary(data: Data(count: TrudaybookSummary.maxFileSize + 1)) == nil)
    }

    @Test("Отметки ложатся на свой день минутами от полуночи")
    func отметки() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parsed = TrudaybookSummary(updated: now, unresolved: 1, important: 0, marks: [
            .init(time: now, important: false, done: true),
            .init(time: now.addingTimeInterval(-86_400), important: true, done: false),
        ])
        #expect(parsed.marks(on: now, calendar: calendar) == [DayMailMark(minute: 600, important: false, done: true)])
    }

    @Test("Фокус — только рабочая фаза идущего таймера, и всегда со сроком")
    func фокус() {
        let until = FocusBeacon.deadline(mode: .timer, phase: .work, running: true, remaining: 600, now: now)
        #expect(until == now.addingTimeInterval(600))
        #expect(FocusBeacon.deadline(mode: .timer, phase: .rest, running: true, remaining: 600, now: now) == nil)
        #expect(FocusBeacon.deadline(mode: .timer, phase: .work, running: false, remaining: 600, now: now) == nil)
        #expect(FocusBeacon.deadline(mode: .stopwatch, phase: .work, running: true, remaining: 600, now: now) == nil)
    }

    @Test("Подпись плитки «Почта»")
    func подпись() {
        #expect(MailWidget.detail(TrudaybookSummary(updated: now, unresolved: 0, important: 0)) == t("всё разобрано"))
        #expect(MailWidget.detail(TrudaybookSummary(updated: now, unresolved: 5, important: 0)) == t("не разобрано"))
        #expect(MailWidget.detail(TrudaybookSummary(updated: now, unresolved: 5, important: 2)) == tf("важных: %d", 2))
    }

    @Test("Почта — без карточки, но и без отправки: только обратимое")
    func почтаОбратима() {
        #expect(AgentTool.mail.allSatisfy { !$0.needsConfirmation })
        #expect(AgentTool.mailUnread.kind == .read)
        #expect(!AgentTool.allCases.map(\.name).contains { $0.contains("send") })
    }

    @Test("Сводка говорит, разрешены ли команды")
    func флагКоманд() {
        let on = summary(#"{"version":1,"updated":"2026-09-25T09:59:00Z","unresolved":1,"commands":true}"#)
        let off = summary(#"{"version":1,"updated":"2026-09-25T09:59:00Z","unresolved":1}"#)
        #expect(on?.acceptsCommands == true)
        #expect(off?.acceptsCommands == false)
    }

    @Test("Ответ Trudaybook: успех, отказ, мусор")
    func ответ() {
        if case let .ok(json) = TrudaybookCommands.parse(Data(#"{"ok":true,"text":"Готово"}"#.utf8)) {
            #expect(json["text"] as? String == "Готово")
        } else { Issue.record("ожидался успех") }
        if case let .failed(error) = TrudaybookCommands.parse(Data(#"{"ok":false,"error":"Нет письма"}"#.utf8)) {
            #expect(error == "Нет письма")
        } else { Issue.record("ожидался отказ") }
        if case .ok = TrudaybookCommands.parse(Data("мусор".utf8)) { Issue.record("мусор не успех") }
    }

    @Test("Список писем раздаёт ярлыки, и по ярлыку уходит номер письма")
    func ярлыки() {
        let runner = AgentRunner(calendar: CalendarService(), timer: TimerService(), notes: isolatedNotes().service,
                                 weather: WeatherService())
        let result = runner.mailListResult([
            "ok": true, "total": 2,
            "letters": [
                ["id": "mail:a:9", "from": "Андрей Козлов", "title": "Договор", "time": "2026-09-25T07:12:00Z",
                 "important": true, "snippet": "Посмотрите правки"],
                ["id": "mail:a:3", "from": "Анна", "title": "Обед", "time": "2026-09-25T06:00:00Z"],
            ],
        ])
        #expect(result.text.contains("m1 · Андрей Козлов · «Договор»"))
        #expect(result.text.contains("Посмотрите правки"))
        #expect(runner.letterReference("m2") == "mail:a:3")
        #expect(runner.letterReference("M1") == "mail:a:9")
        #expect(runner.letterReference("Козлов договор") == "Козлов договор")
    }

    /// Заметки во временной базе и с настройками без модели — настоящих
    /// заметок человека тест не касается.
    private func isolatedNotes() -> (service: NotesService, settings: Settings) {
        let defaults = UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!
        let settings = Settings(defaults: defaults)
        settings.ollamaEnabled = false
        settings.notesTitleByModel = false
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID().uuidString).sqlite")
        let service = NotesService(store: NotesStore(url: url), titler: NoteTitler(settings: settings), settings: settings)
        return (service, settings)
    }

    @Test("Заметка дня ходит в обе стороны, и только по файлам дней")
    func заметкаДня() throws {
        let (notes, settings) = isolatedNotes()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("daynotes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!
        let sync = DayNoteSync(notes: notes, settings: settings, folder: folder, defaults: defaults)

        let file = folder.appendingPathComponent("2026-09-25.txt")
        try Data("Позвонить юристам".utf8).write(to: file)
        try Data("чужое".utf8).write(to: folder.appendingPathComponent("список.txt"))
        sync.sync()
        let made = notes.notes.filter { $0.plain == "Позвонить юристам" }
        #expect(made.count == 1)
        #expect(made.first?.title.hasPrefix("Trudaybook · ") == true)
        #expect(notes.notes.count == 1)

        // Повтор без правок — ничего нового.
        sync.sync()
        #expect(notes.notes.count == 1)

        // Правка здесь уходит в файл.
        let id = try #require(made.first?.id)
        notes.save(NSAttributedString(string: "Позвонить юристам и Козлову"), origin: .typed, editing: id,
                   now: Date().addingTimeInterval(120))
        sync.sync()
        #expect(try String(contentsOf: file, encoding: .utf8) == "Позвонить юристам и Козлову")
        #expect(notes.notes.count == 1)
    }

    @Test("Имя заметки дня — словами")
    func имяЗаметки() {
        #expect(DayNoteSync.title(for: "2026-09-25", locale: Locale(identifier: "ru_RU")) == "Trudaybook · 25 сентября")
        #expect(DayNoteSync.day(fromFileName: "2026-09-25.txt") == "2026-09-25")
        #expect(DayNoteSync.day(fromFileName: "25-09-2026.txt") == nil)
    }
}

