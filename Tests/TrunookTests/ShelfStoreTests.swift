import AppKit
import Foundation
import Testing
@testable import Trunook

@Suite("Полка")
struct ShelfStoreTests {
    /// Настоящие файлы во временной папке: полка держит ссылки и проверяет,
    /// на месте ли файл, — на выдуманных путях эта проверка бессмысленна.
    private func makeFiles(_ count: Int) throws -> (URL, [URL]) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("trunook-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let urls = try (0..<count).map { index -> URL in
            let url = root.appendingPathComponent("файл-\(index).txt")
            try Data("проба".utf8).write(to: url)
            return url
        }
        return (root, urls)
    }

    @Test("Один и тот же файл не ложится дважды")
    func безПовторов() throws {
        let (root, urls) = try makeFiles(1)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ShelfStore()
        #expect(store.add(urls) == 1)
        #expect(store.add(urls) == 0)
        #expect(store.items.count == 1)
    }

    @Test("Путь приводится к одному виду")
    func путиПриводятся() throws {
        let (root, urls) = try makeFiles(1)
        defer { try? FileManager.default.removeItem(at: root) }

        // Тот же файл, но записанный иначе — через лишний сегмент пути.
        let awkward = urls[0].deletingLastPathComponent()
            .appendingPathComponent(".")
            .appendingPathComponent(urls[0].lastPathComponent)

        let store = ShelfStore()
        store.add(urls)
        #expect(store.add([awkward]) == 0, "тот же файл лёг на полку дважды")
    }

    @Test("Свежее сверху")
    func свежееСверху() throws {
        let (root, urls) = try makeFiles(2)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ShelfStore()
        store.add([urls[0]])
        store.add([urls[1]])
        #expect(store.items.first?.url.lastPathComponent == urls[1].lastPathComponent)
    }

    @Test("Уехавший файл убирается с полки")
    func потерянныеУбираются() throws {
        let (root, urls) = try makeFiles(2)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ShelfStore()
        store.add(urls)
        try FileManager.default.removeItem(at: urls[0])
        store.pruneMissing()
        #expect(store.items.count == 1)
    }

    @Test("Полка не растёт выше потолка")
    func потолок() throws {
        let (root, urls) = try makeFiles(ShelfStore.limit + 3)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ShelfStore()
        store.add(urls)
        #expect(store.items.count == ShelfStore.limit)
    }

    /// Словарь миниатюр рос на каждый побывавший на полке файл и не убывал
    /// никогда: за долгий день это сотни картинок в памяти без потолка.
    @Test("Кэш миниатюр не растёт без края")
    func миниатюрыНеРастутБезКрая() throws {
        let (root, urls) = try makeFiles(ShelfStore.thumbnailCacheLimit + 5)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ShelfStore()
        let picture = NSImage(size: CGSize(width: 1, height: 1))
        for url in urls { store.cache(picture, for: url) }

        #expect(store.thumbnails.count <= ShelfStore.thumbnailCacheLimit)
    }

    /// Вытеснять то, что человек видит на экране, нельзя ни при каком
    /// переполнении: значок подменил бы миниатюру прямо под курсором.
    @Test("Миниатюра лежащего на полке переживает вытеснение")
    func лежащееНеВытесняется() throws {
        let (root, urls) = try makeFiles(ShelfStore.thumbnailCacheLimit + 5)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ShelfStore()
        let picture = NSImage(size: CGSize(width: 1, height: 1))
        // Первый файл кладётся на полку и получает миниатюру раньше всех —
        // то есть вытеснился бы первым, будь порядок единственным правилом.
        store.add([urls[0]])
        for url in urls { store.cache(picture, for: url) }

        #expect(store.thumbnails[urls[0]] != nil, "вытеснили миниатюру того, что на полке")
    }

    @Test("Очистка опустошает полку")
    func очистка() throws {
        let (root, urls) = try makeFiles(2)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ShelfStore()
        store.add(urls)
        store.clear()
        #expect(store.isEmpty)
    }
}
