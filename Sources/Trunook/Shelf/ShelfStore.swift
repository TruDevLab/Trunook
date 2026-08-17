import AppKit
import QuickLookThumbnailing
import TrunookXPC

/// Что лежит на полке прямо сейчас.
///
/// Только в памяти: полка — это перевалочный пункт между двумя окнами,
/// а не хранилище. Пережившая перезапуск полка ссылалась бы на файлы,
/// которых человек уже не помнит, и половина ссылок к тому моменту
/// протухла бы.
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    /// Миниатюры приходят с задержкой, поэтому лежат отдельно от самих
    /// записей: иначе каждая готовая картинка пересобирала бы весь список.
    @Published private(set) var thumbnails: [URL: NSImage] = [:]

    /// Потолок числа файлов. Больше на полке размером с панель всё равно
    /// не видно, а держать ссылки на сотню файлов бессмысленно.
    static let limit = 30

    private static let thumbnailSize = CGSize(width: 128, height: 128)

    var isEmpty: Bool { items.isEmpty }

    /// Положить файлы на полку. Уже лежащие не задваиваются.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        let existing = Set(items.map(\.url))
        let fresh = urls
            .map { ShelfItem(url: $0) }
            .filter { !existing.contains($0.url) }
        guard !fresh.isEmpty else { return 0 }

        // Свежие сверху: последнее положенное человек ищет первым.
        items = (fresh + items).prefix(Self.limit).map { $0 }
        fresh.forEach(loadThumbnail)
        DebugLog.write("полка: принято \(fresh.count), всего \(items.count)")
        return fresh.count
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        // Миниатюру не выбрасываем: тот же файл могут положить обратно,
        // а картинка стоит похода в QuickLook.
        DebugLog.write("полка: убрано, осталось \(items.count)")
    }

    func clear() {
        items.removeAll()
        DebugLog.write("полка: очищена")
    }

    /// Выбросить записи, чьи файлы уехали или удалены.
    func pruneMissing() {
        let before = items.count
        items.removeAll { !$0.exists }
        if items.count != before {
            DebugLog.write("полка: потеряно файлов \(before - items.count)")
        }
    }

    /// Значок файла, пока не готова миниатюра. Он есть всегда и сразу.
    func icon(for item: ShelfItem) -> NSImage {
        NSWorkspace.shared.icon(forFile: item.url.path)
    }

    private func loadThumbnail(_ item: ShelfItem) {
        guard thumbnails[item.url] == nil else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: Self.thumbnailSize,
            scale: 2,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            guard let rep else { return }
            let image = rep.nsImage
            DispatchQueue.main.async {
                self?.thumbnails[item.url] = image
            }
        }
    }
}
