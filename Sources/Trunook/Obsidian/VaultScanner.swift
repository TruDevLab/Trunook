import Foundation
import TrunookXPC

/// Обход хранилища и работа с его файлами.
///
/// Всё, что трогает чужой диск, собрано здесь одним местом — чтобы правило
/// «удаляем только в Корзину» нельзя было обойти по невнимательности из другого
/// файла. Решения о том, что кому делать, тут не принимаются вовсе: их
/// принимает `SyncPlan`, а это исполнитель.
enum VaultScanner {
    // MARK: - Обход

    /// Снимок заметок хранилища.
    ///
    /// `subfolder` сужает обход до одной папки — так берут свою подпапку,
    /// когда остальное хранилище читать не просили.
    ///
    /// Пустой ответ у недоступной папки — не «заметок нет», а «смотреть было
    /// негде». Отличать эти два случая обязан вызывающий: принять недоступный
    /// диск за пустое хранилище значит вычистить базу. Для того `isReachable`
    /// и проверяется первым делом.
    static func files(in vault: Vault, subfolder: String? = nil, limit: Int = Vault.maxFiles) -> [VaultFile] {
        guard vault.isReachable else { return [] }

        let root = subfolder.map { vault.url.appendingPathComponent($0, isDirectory: true) } ?? vault.url
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            // Скрытое пропускает сама система, но правило продублировано ниже
            // ещё и своим: пакеты и вложенные хранилища сюда тоже не нужны.
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let prefix = vault.url.path
        var result: [VaultFile] = []

        for case let url as URL in walker {
            if result.count >= limit {
                DebugLog.write("Obsidian: обход упёрся в потолок \(limit) файлов")
                break
            }
            guard Vault.isNote(url.lastPathComponent),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { continue }

            let size = values.fileSize ?? 0
            guard size <= Vault.maxFileBytes else { continue }

            let full = url.standardizedFileURL.path
            guard full.hasPrefix(prefix + "/") else { continue }
            let path = String(full.dropFirst(prefix.count + 1))
            guard !Vault.isSkipped(relativePath: path) else { continue }

            result.append(
                VaultFile(
                    path: path,
                    modified: values.contentModificationDate ?? .distantPast,
                    size: size
                )
            )
        }
        return result
    }

    /// Снимок только своей подпапки.
    static func ownFiles(in vault: Vault) -> [VaultFile] {
        files(in: vault, subfolder: vault.folder)
    }

    // MARK: - Чтение

    /// Текст заметки. `nil`, если файла нет, он велик или это не UTF-8.
    ///
    /// Чужую кодировку не угадываем. Подставить `isoLatin1` было бы хуже
    /// молчаливого отказа: кириллица превратилась бы в кашу, а каша
    /// доехала бы до поиска и до контекста модели как настоящий текст.
    static func text(at path: String, in vault: Vault) -> String? {
        let url = vault.fileURL(for: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard data.count <= Vault.maxFileBytes else { return nil }
        guard let text = String(data: data, encoding: .utf8) else {
            DebugLog.write("Obsidian: \(path) не в UTF-8, пропущен")
            return nil
        }
        return text
    }

    // MARK: - Запись

    /// Кладёт текст в файл, заводя недостающие папки по дороге.
    @discardableResult
    static func write(_ text: String, to path: String, in vault: Vault) -> Bool {
        let url = vault.fileURL(for: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            DebugLog.write("Obsidian: не записался \(path) — \(error.localizedDescription)")
            return false
        }
    }

    /// Заводит свою подпапку, если её ещё нет.
    @discardableResult
    static func ensureOwnFolder(in vault: Vault) -> Bool {
        do {
            try FileManager.default.createDirectory(at: vault.ownFolder, withIntermediateDirectories: true)
            return true
        } catch {
            DebugLog.write("Obsidian: не завелась папка \(vault.folder) — \(error.localizedDescription)")
            return false
        }
    }

    /// Переносит файл внутри хранилища, заводя папку назначения.
    @discardableResult
    static func move(_ path: String, to target: String, in vault: Vault) -> Bool {
        let from = vault.fileURL(for: path)
        let to = vault.fileURL(for: target)
        do {
            try FileManager.default.createDirectory(
                at: to.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: from, to: to)
            return true
        } catch {
            DebugLog.write("Obsidian: не переехал \(path) — \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Удаление

    /// Уносит файл в Корзину и отдаёт его новое место там.
    ///
    /// `removeItem` здесь не годится ни при каких условиях: это личные файлы
    /// человека, и ошибка сверки не должна быть безвозвратной. Корзина стоит
    /// ровно ничего и оставляет путь назад.
    ///
    /// Место в Корзине возвращается ради теста: без него проверка этой ветки
    /// оставляла бы мусор в Корзине человека на каждом прогоне `make test`.
    /// Служба им не пользуется.
    @discardableResult
    static func trash(_ path: String, in vault: Vault) -> URL? {
        do {
            var moved: NSURL?
            try FileManager.default.trashItem(at: vault.fileURL(for: path), resultingItemURL: &moved)
            return moved as URL?
        } catch {
            DebugLog.write("Obsidian: не унеслось в Корзину \(path) — \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Имена

    /// Свободное имя файла в своей подпапке.
    ///
    /// Две заметки одной минуты дают одно имя — `NoteMarkdown.fileName`
    /// считает его от даты. Разводим суффиксом, как это делает выгрузка
    /// в папку (`NotesService.exportAll`), а не датой посекунднее: секунды
    /// в имени файла человек читать не должен.
    static func freePath(fileName: String, in vault: Vault, taken: Set<String>) -> String {
        let base = (fileName as NSString).deletingPathExtension
        let candidate = vault.ownPath(fileName: fileName)
        guard taken.contains(candidate) || FileManager.default.fileExists(atPath: vault.fileURL(for: candidate).path)
        else { return candidate }

        var index = 2
        while index < 1000 {
            let next = vault.ownPath(fileName: "\(base)-\(index).md")
            if !taken.contains(next), !FileManager.default.fileExists(atPath: vault.fileURL(for: next).path) {
                return next
            }
            index += 1
        }
        return candidate
    }
}
