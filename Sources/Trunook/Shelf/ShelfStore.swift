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

    /// Потолок кэша миниатюр. Больше, чем у самой полки, и намеренно: убранный
    /// файл нередко кладут обратно, а картинка стоит похода в QuickLook.
    /// Но и расти без края словарь не должен — за долгий день через полку
    /// проходят сотни файлов, и каждая миниатюра остаётся в памяти навсегда.
    static let thumbnailCacheLimit = limit * 2

    private static let thumbnailSize = CGSize(width: 128, height: 128)

    /// Порядок появления миниатюр: словарь его не хранит, а вытеснять надо
    /// самые давние.
    private var thumbnailOrder: [URL] = []

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
                self?.cache(image, for: item.url)
            }
        }
    }

    /// Не `private` ради проверки: миниатюры приходят из QuickLook, и вызвать
    /// его из теста нечем, а потолок кэша и правило «лежащее на полке
    /// не вытесняем» проверить надо.
    func cache(_ image: NSImage, for url: URL) {
        if thumbnails[url] == nil { thumbnailOrder.append(url) }
        thumbnails[url] = image
        trimThumbnails()
    }

    /// Вытесняет самые давние миниатюры сверх потолка — но только те, чьих
    /// файлов на полке уже нет: картинка того, что видно на экране, обязана
    /// пережить любую чистку.
    ///
    /// Словарь переписывается один раз, а не по записи за раз: он
    /// `@Published`, и каждое присваивание пересобирало бы полку заново.
    private func trimThumbnails() {
        guard thumbnailOrder.count > Self.thumbnailCacheLimit else { return }
        let onShelf = Set(items.map(\.url))
        var excess = thumbnailOrder.count - Self.thumbnailCacheLimit
        var doomed: Set<URL> = []
        for url in thumbnailOrder where excess > 0 {
            guard !onShelf.contains(url) else { continue }
            doomed.insert(url)
            excess -= 1
        }
        guard !doomed.isEmpty else { return }
        thumbnailOrder.removeAll { doomed.contains($0) }
        thumbnails = thumbnails.filter { !doomed.contains($0.key) }
        DebugLog.write("полка: миниатюр вытеснено \(doomed.count), осталось \(thumbnails.count)")
    }
}
