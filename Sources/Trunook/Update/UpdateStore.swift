import TrunookXPC
import Foundation

/// Запись о том, что уже скачано и проверено.
///
/// Лежит рядом с готовым бандлом. Нужна, чтобы после перезапуска не качать
/// заново то, что уже лежит на диске, и чтобы при разборе полётов было видно,
/// какая именно сборка ждёт установки.
struct StagedUpdate: Codable, Equatable {
    let tag: String
    let version: String
    /// Номер сборки. В сравнении версий не участвует — он здесь только затем,
    /// чтобы две сборки одного номера различались в журнале.
    let build: String
    let checksum: String?
    let verifiedAt: Date
}

/// Папка, в которой ждёт своего часа скачанное обновление.
///
/// `Application Support`, а не `Caches`, и это не вкусовщина: содержимое
/// `Caches` система вправе выгрести в любой момент, в том числе посреди
/// загрузки трёх с половиной мегабайт.
enum UpdateStore {
    static let folder: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base
            .appendingPathComponent("Trunook", isDirectory: true)
            .appendingPathComponent("Update", isDirectory: true)
    }()

    static var stagedApp: URL { folder.appendingPathComponent("Trunook.app") }

    private static var manifest: URL { folder.appendingPathComponent("staged.json") }

    /// Куда класть образ на время загрузки. Удаляется сразу после распаковки:
    /// держать три с половиной мегабайта неделями незачем.
    static func imageFile(named name: String) -> URL {
        folder.appendingPathComponent(name)
    }

    @discardableResult
    static func makeFolder() -> Bool {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return true
        } catch {
            DebugLog.write("обновление: папка не создалась — \(error.localizedDescription)")
            return false
        }
    }

    /// Что лежит готовым. `nil` — либо ничего нет, либо запись не сходится
    /// с тем, что на диске.
    static func staged() -> StagedUpdate? {
        guard let data = try? Data(contentsOf: manifest) else { return nil }
        guard let record = try? decoder.decode(StagedUpdate.self, from: data) else {
            DebugLog.write("обновление: запись о скачанном не разобрана")
            return nil
        }
        // Запись без бандла — след неудачной прошлой попытки. Ей верить нельзя.
        guard FileManager.default.fileExists(atPath: stagedApp.path) else {
            DebugLog.write("обновление: запись есть, а бандла нет — чистим")
            clear()
            return nil
        }
        return record
    }

    static func write(_ record: StagedUpdate) {
        do {
            try encoder.encode(record).write(to: manifest, options: .atomic)
        } catch {
            DebugLog.write("обновление: запись о скачанном не сохранилась — \(error.localizedDescription)")
        }
    }

    /// Выносит папку целиком. Половина скачанного хуже, чем ничего: на неё
    /// нельзя ни поставить, ни положиться.
    static func clear() {
        try? FileManager.default.removeItem(at: folder)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
