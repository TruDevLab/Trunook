import Foundation
import Testing
@testable import Trunook

@Suite("Заметки: закрепление и срок хранения записей")
struct NotePinAudioTests {
    private let day: TimeInterval = 24 * 3600

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("trunook-pins-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    private func note(
        _ title: String,
        created: Date = Date(),
        origin: Note.Origin = .typed,
        audio: String = "",
        keep: Bool = false
    ) -> Note {
        var note = Note(id: Note.unsaved, title: title, rtf: Data(), plain: title,
                        createdAt: created, updatedAt: created, origin: origin, titleByModel: true,
                        audio: audio)
        note.keepAudio = keep
        return note
    }

    private func service(_ store: NotesStore) throws -> NotesService {
        let suite = "NotePinAudioTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return NotesService(store: store, settings: Settings(defaults: defaults))
    }

    // MARK: - Срок хранения

    @Test("Бессрочно записи не уходят")
    func бессрочно() {
        let old = note("Старая", created: Date().addingTimeInterval(-400 * day), audio: "/tmp/a.m4a")
        #expect(AudioRetention.expiry(of: old, days: 0) == nil)
        #expect(AudioRetention.expired([old], days: 0, now: Date()).isEmpty)
    }

    @Test("Запись старше срока уходит, моложе — остаётся")
    func поСроку() {
        let now = Date()
        let old = note("Старая", created: now.addingTimeInterval(-8 * day), audio: "/tmp/a.m4a")
        let fresh = note("Свежая", created: now.addingTimeInterval(-6 * day), audio: "/tmp/b.m4a")
        #expect(AudioRetention.expired([old, fresh], days: 7, now: now).map(\.title) == ["Старая"])
    }

    @Test("Флаг «не удалять» и заметка без записи сроку не подвластны")
    func исключения() {
        let now = Date()
        let kept = note("С флагом", created: now.addingTimeInterval(-30 * day), audio: "/tmp/a.m4a", keep: true)
        let silent = note("Без записи", created: now.addingTimeInterval(-30 * day))
        #expect(AudioRetention.expired([kept, silent], days: 1, now: now).isEmpty)
    }

    @Test("Флаги записи переживают перечитывание базы")
    func флагиВБазе() throws {
        let url = temporaryURL()
        let store = NotesStore(url: url)
        let id = try #require(store.insert(note("Встреча", audio: "Trunook/Записи/a.m4a")))
        store.setKeepAudio(id: id, keep: true)
        #expect(NotesStore(url: url).note(id: id)?.keepAudio == true)
        #expect(store.expiringAudio().isEmpty)

        let cleared = Date().addingTimeInterval(1)
        store.clearAudio(id: id, at: cleared)
        let read = try #require(NotesStore(url: url).note(id: id))
        #expect(!read.hasAudio)
        #expect(!read.keepAudio)
        // Список по дате правки не сдвигается, а сверка изменение видит.
        #expect(read.updatedAt < cleared)
        #expect(read.syncedChangeAt > read.updatedAt)
    }

    // MARK: - Закрепление

    @Test("Закреплённые идут первыми в порядке закрепления")
    func порядок() throws {
        let store = NotesStore(url: temporaryURL())
        let now = Date()
        let first = try #require(store.insert(note("Первая", created: now)))
        let second = try #require(store.insert(note("Вторая", created: now.addingTimeInterval(60))))
        _ = store.insert(note("Свежая", created: now.addingTimeInterval(120)))

        store.setPinned(id: second, at: now)
        store.setPinned(id: first, at: now.addingTimeInterval(1))
        #expect(store.all(source: .own).map(\.title) == ["Вторая", "Первая", "Свежая"])
        #expect(store.pinned().map(\.title) == ["Вторая", "Первая"])
    }

    @Test("Больше трёх не закрепить, открепление освобождает место")
    func предел() throws {
        let store = NotesStore(url: temporaryURL())
        let notes = try service(store)
        let ids = try (0..<4).map { try #require(store.insert(note("Заметка \($0)"))) }
        let all = ids.compactMap(store.note(id:))

        let base = Date()
        for (offset, note) in all.prefix(3).enumerated() {
            #expect(notes.togglePin(note, now: base.addingTimeInterval(Double(offset))))
        }
        #expect(!notes.togglePin(all[3]))
        #expect(notes.pinned.count == Note.pinLimit)

        #expect(notes.togglePin(all[0]))
        #expect(notes.togglePin(all[3], now: base.addingTimeInterval(10)))
        #expect(notes.pinned.map(\.id) == [ids[1], ids[2], ids[3]])
    }

    @Test("Закреплённая заметка хранилища видна в списке без поиска")
    func хранилищеВСписке() throws {
        let store = NotesStore(url: temporaryURL())
        let vault = try #require(store.insert(note("Из хранилища", origin: .obsidian)))
        _ = store.insert(note("Своя"))
        #expect(store.all(source: .ownOrPinned).map(\.title) == ["Своя"])
        store.setPinned(id: vault, at: Date())
        #expect(store.all(source: .ownOrPinned).map(\.title) == ["Из хранилища", "Своя"])
    }
}
