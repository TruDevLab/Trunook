import AppKit

/// Файл, лежащий на полке.
///
/// Пока файл лежит на полке, полка держит **ссылку**, а не копию: он
/// остаётся там же, где был. Переезжает он в момент, когда его с полки
/// вытаскивают, — и тогда исчезает и с полки, и из исходной папки.
///
/// Обратная сторона ссылки — файл может уехать или быть удалён и помимо
/// полки, поэтому существование приходится проверять при каждой отрисовке.
struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let addedAt: Date

    init(url: URL, addedAt: Date = Date()) {
        // Ссылки от разных источников приходят по-разному: одна с `/private`,
        // другая через симлинк. Без приведения к одному виду один и тот же
        // файл ложился бы на полку дважды.
        self.url = url.resolvingSymlinksInPath().standardizedFileURL
        self.addedAt = addedAt
    }

    var name: String { url.lastPathComponent }

    /// Папку показываем иначе и размером не меряем.
    var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Подпись под именем: размер файла либо слово «папка».
    var subtitle: String {
        if isDirectory { return t("папка") }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return url.pathExtension.uppercased()
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool {
        lhs.id == rhs.id && lhs.url == rhs.url
    }
}
