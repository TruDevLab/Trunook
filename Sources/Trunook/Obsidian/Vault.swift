import AppKit
import Foundation

/// Хранилище Obsidian — папка с файлами `.md` и служебной папкой `.obsidian`.
///
/// Значение, а не служба: путь приходит снаружи и здесь только разбирается.
/// **Ни одного предположения о том, где хранилище лежит, в коде нет** — папку
/// называет пользователь. Стандартного места у Obsidian не существует: одно
/// хранилище живёт в «Документах», другое на внешнем диске, третье внутри
/// iCloud или Dropbox. Угаданный путь здесь означал бы, что приложение
/// однажды напишет не в ту папку.
struct Vault: Equatable {
    /// Имя своей подпапки по умолчанию. Только её содержимое ходит в обе
    /// стороны; остальное хранилище приложение читает и не трогает.
    static let defaultFolder = "Trunook"

    /// Крупнее этого файл не заметка, а свалка: выгрузка переписки, вставленная
    /// таблица на десять тысяч строк, случайно переименованный дамп. Читать
    /// такое незачем — ни в поиск, ни в контекст модели оно всё равно не влезет.
    static let maxFileBytes = 256 * 1024

    /// Потолок обхода. Хранилище на двадцать тысяч заметок уже необычно;
    /// упереться в потолок лучше, чем читать диск без конца.
    static let maxFiles = 20_000

    /// Корень хранилища.
    let url: URL

    /// Имя своей подпапки внутри хранилища.
    let folder: String

    init(url: URL, folder: String = Vault.defaultFolder) {
        self.url = url.standardizedFileURL
        let trimmed = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        // Пустое имя подпапки означало бы «писать в корень хранилища»,
        // вперемешку с чужими заметками. Так себе умолчание.
        self.folder = trimmed.isEmpty ? Self.defaultFolder : trimmed
    }

    /// Хранилище, названное в настройках. `nil`, пока путь не выбран, —
    /// это обычное состояние, а не ошибка.
    init?(path: String, folder: String = Vault.defaultFolder) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.init(
            url: URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath),
            folder: folder
        )
    }

    // MARK: - Места

    /// Имя хранилища — имя его папки. Схема `obsidian://` знает хранилища
    /// именно по имени, а не по пути.
    var name: String { url.lastPathComponent }

    /// Своя подпапка: единственное место, куда приложение пишет заметки.
    var ownFolder: URL { url.appendingPathComponent(folder, isDirectory: true) }

    func fileURL(for path: String) -> URL {
        url.appendingPathComponent(path)
    }

    /// Своя ли это заметка — лежит ли путь внутри подпапки.
    func isOwn(_ path: String) -> Bool {
        path.hasPrefix(folder + "/")
    }

    /// Путь своей заметки по имени файла.
    func ownPath(fileName: String) -> String {
        folder + "/" + fileName
    }

    // MARK: - Состояние папки

    /// Папка на месте и читается.
    ///
    /// Проверка боем, как в `FilesAccess`: у TCC нет запроса «выдан ли
    /// доступ», а отключённый внешний диск отвечает тем же отказом, что
    /// и запрет. Разбирать причину незачем — делать в обоих случаях нечего.
    var isReachable: Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return false }
        return (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
    }

    /// Похоже ли на настоящее хранилище: Obsidian держит свои настройки
    /// в папке `.obsidian` внутри.
    ///
    /// Это подсказка, а не запрет: синхронизировать можно с любой папкой,
    /// где лежат `.md`. Но если человек указал папку мимо, сказать об этом
    /// стоит до первой записи, а не после.
    var looksLikeVault: Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(".obsidian").path)
    }

    // MARK: - Правила обхода

    /// Что в обход не идёт.
    ///
    /// Скрытые имена отсекаются целиком, и это закрывает сразу три случая
    /// одной строкой: служебную `.obsidian`, корзину хранилища `.trash`
    /// и недокачанные заглушки iCloud — те называются `.Имя.md.icloud`
    /// и тоже начинаются с точки.
    static func isSkipped(relativePath: String) -> Bool {
        let parts = relativePath.split(separator: "/")
        guard !parts.isEmpty else { return true }
        return parts.contains { $0.hasPrefix(".") }
    }

    /// Заметка — только `.md`. Всё прочее в хранилище (картинки, PDF,
    /// вложения, канвасы) читать незачем: искать по ним нечего.
    static func isNote(_ name: String) -> Bool {
        name.count > 3 && name.lowercased().hasSuffix(".md")
    }

    // MARK: - Ссылка в Obsidian

    /// Ссылка, открывающая заметку в самом Obsidian.
    ///
    /// Расширение снимается: `file` в этой схеме — имя заметки, а не имя
    /// файла. Косые в пути тоже уходят в проценты — это значение параметра
    /// запроса, и заметка из папки «Проекты» иначе разъехалась бы по нему.
    func openURL(for path: String) -> URL? {
        let file = path.hasSuffix(".md") ? String(path.dropLast(3)) : path
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let vault = name.addingPercentEncoding(withAllowedCharacters: allowed),
              let note = file.addingPercentEncoding(withAllowedCharacters: allowed),
              !vault.isEmpty, !note.isEmpty
        else { return nil }
        return URL(string: "obsidian://open?vault=\(vault)&file=\(note)")
    }
}

/// Установлен ли сам Obsidian.
///
/// Синхронизации он не нужен вовсе — хранилище это просто папка с `.md`,
/// и она работает, даже если Obsidian никогда не запускали. Но кнопку
/// «Открыть в Obsidian» показывать тогда незачем: она приведёт
/// к системному «нет приложения для этой ссылки».
enum ObsidianApp {
    static var isInstalled: Bool {
        guard let url = URL(string: "obsidian://open") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
    }
}
