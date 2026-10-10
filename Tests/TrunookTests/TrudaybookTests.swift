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
        // Замерший такт спрашивает «сейчас» из прошлого — свежий файл
        // от этого не становится «Trudaybook закрыт».
        #expect(parsed?.isFresh(at: now.addingTimeInterval(-4 * 3600)) == true)
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
        #expect(made.first?.origin == .trudaybook)
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

    @Test("Заметки дня, заведённые раньше обычными, получают свой вид")
    func заметкиДняПереносятся() throws {
        let (notes, settings) = isolatedNotes()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("daynotes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!
        let old = try #require(notes.save(NSAttributedString(string: "Старый день"), origin: .typed,
                                          title: "Trudaybook · 1 сентября"))
        let own = try #require(notes.save(NSAttributedString(string: "Своё"), origin: .typed))
        defaults.set(try JSONEncoder().encode(["2026-09-01": DayNoteSync.Link(id: old.id, seen: 0)]),
                     forKey: DayNoteSync.key)
        let sync = DayNoteSync(notes: notes, settings: settings, folder: folder, defaults: defaults)
        sync.start()
        sync.stop()
        #expect(notes.note(id: old.id)?.origin == .trudaybook)
        #expect(notes.note(id: own.id)?.origin == .typed)
        #expect(notes.trudaybookCount == 1)
    }

    @Test("Имя заметки дня — словами")
    func имяЗаметки() {
        #expect(DayNoteSync.title(for: "2026-09-25", locale: Locale(identifier: "ru_RU")) == "Trudaybook · 25 сентября")
        #expect(DayNoteSync.day(fromFileName: "2026-09-25.txt") == "2026-09-25")
        #expect(DayNoteSync.day(fromFileName: "25-09-2026.txt") == nil)
    }

    @Test("Прогноз недели: местные часы Open-Meteo — в абсолютное время")
    func прогнозНедели() throws {
        let answer = """
        {"utc_offset_seconds":10800,
         "hourly":{"time":["2026-09-25T09:00","2026-09-25T10:00"],"temperature_2m":[10.44,null],
                   "weather_code":[61,3],"precipitation_probability":[70,10]},
         "daily":{"time":["2026-09-25"],"weather_code":[61],"temperature_2m_max":[14.2],
                  "temperature_2m_min":[8.1],"precipitation_probability_max":[80],
                  "sunrise":["2026-09-25T06:44"],"sunset":["2026-09-25T18:43"]}}
        """
        let data = try #require(WeekForecastExport.export(from: Data(answer.utf8), now: now, place: "Москва"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["version"] as? Int == 1)
        #expect(json["place"] as? String == "Москва")
        let hours = try #require(json["hours"] as? [[String: Any]])
        // Час без температуры пропущен, 09:00 по Москве — 06:00 UTC.
        #expect(hours.count == 1)
        #expect(hours.first?["time"] as? String == "2026-09-25T06:00:00Z")
        #expect(hours.first?["temp"] as? Double == 10.4)
        let days = try #require(json["days"] as? [[String: Any]])
        #expect(days.first?["date"] as? String == "2026-09-25")
        #expect(days.first?["precip"] as? Int == 80)
        #expect(days.first?["sunrise"] as? String == "2026-09-25T03:44:00Z")
        #expect(days.first?["sunset"] as? String == "2026-09-25T15:43:00Z")
        #expect(WeekForecastExport.export(from: Data("{}".utf8), now: now, place: nil) == nil)
    }
}

