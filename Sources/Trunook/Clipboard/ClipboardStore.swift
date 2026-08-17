import TrunookXPC
import Foundation
import SQLite3

/// Хранилище истории буфера обмена.
///
/// Системный SQLite, без сторонних библиотек: история должна пережить
/// перезапуск, а держать её в UserDefaults нельзя — там оказались бы
/// изображения целиком, и файл настроек читался бы при каждом запуске
/// со всей этой начинкой.
final class ClipboardStore {
    private var database: OpaquePointer?
    private let queue = DispatchQueue(label: "com.trunook.clipboard.store")

    /// SQLite должен скопировать переданную строку себе: иначе она успевает
    /// освободиться до выполнения запроса.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static let fileURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base
            .appendingPathComponent("Trunook", isDirectory: true)
            .appendingPathComponent("clipboard.sqlite")
    }()

    init() {
        open()
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    // MARK: - Открытие

    private func open() {
        let url = Self.fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            DebugLog.write("буфер: база не открылась — \(lastError)")
            database = nil
            return
        }

        // Журнал с упреждающей записью: приложение пишет по одной записи
        // на каждое копирование, и обычный журнал заставлял бы переписывать
        // файл целиком.
        execute("PRAGMA journal_mode = WAL;")
        execute("""
            CREATE TABLE IF NOT EXISTS entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL,
                text TEXT NOT NULL,
                data BLOB,
                source TEXT,
                copiedAt REAL NOT NULL,
                fingerprint TEXT NOT NULL
            );
            """)
        execute("CREATE INDEX IF NOT EXISTS entries_time ON entries(copiedAt DESC);")
        execute("CREATE UNIQUE INDEX IF NOT EXISTS entries_fingerprint ON entries(fingerprint);")
    }

    private var lastError: String {
        database.map { String(cString: sqlite3_errmsg($0)) } ?? "база не открыта"
    }

    private func execute(_ sql: String) {
        guard let database else { return }
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(database, sql, nil, nil, &error) != SQLITE_OK, let error {
            DebugLog.write("буфер: \(String(cString: error))")
            sqlite3_free(error)
        }
    }

    // MARK: - Запись

    /// Кладёт запись. Повтор не плодит строку, а поднимает прежнюю наверх:
    /// человек скопировал то же самое — значит оно снова нужно, но история
    /// от этого расти не должна.
    @discardableResult
    func insert(_ entry: ClipboardEntry) -> Bool {
        queue.sync {
            guard let database else { return false }

            let sql = """
                INSERT INTO entries (kind, text, data, source, copiedAt, fingerprint)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(fingerprint) DO UPDATE SET
                    copiedAt = excluded.copiedAt,
                    source = excluded.source;
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                DebugLog.write("буфер: запись не подготовилась — \(lastError)")
                return false
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, entry.kind.rawValue, -1, Self.transient)
            sqlite3_bind_text(statement, 2, entry.text, -1, Self.transient)
            if let data = entry.data {
                _ = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, 3, bytes.baseAddress, Int32(data.count), Self.transient)
                }
            } else {
                sqlite3_bind_null(statement, 3)
            }
            if let source = entry.source {
                sqlite3_bind_text(statement, 4, source, -1, Self.transient)
            } else {
                sqlite3_bind_null(statement, 4)
            }
            sqlite3_bind_double(statement, 5, entry.copiedAt.timeIntervalSince1970)
            sqlite3_bind_text(statement, 6, entry.fingerprint, -1, Self.transient)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                DebugLog.write("буфер: запись не легла — \(lastError)")
                return false
            }
            return true
        }
    }

    /// Поднимает запись наверх, не создавая новую: так делает выбор
    /// из истории — использованное становится самым свежим.
    func touch(id: Int64, at date: Date = Date()) {
        queue.sync {
            guard let database else { return }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database, "UPDATE entries SET copiedAt = ? WHERE id = ?;", -1, &statement, nil
            ) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
            sqlite3_bind_int64(statement, 2, id)
            sqlite3_step(statement)
        }
    }

    // MARK: - Чтение

    func recent(limit: Int) -> [ClipboardEntry] {
        queue.sync {
            guard let database else { return [] }
            var statement: OpaquePointer?
            let sql = """
                SELECT id, kind, text, data, source, copiedAt
                FROM entries ORDER BY copiedAt DESC LIMIT ?;
                """
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return []
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, Int32(limit))

            var result: [ClipboardEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let entry = read(statement) else { continue }
                result.append(entry)
            }
            return result
        }
    }

    private func read(_ statement: OpaquePointer?) -> ClipboardEntry? {
        guard let kindText = sqlite3_column_text(statement, 1),
              let kind = ClipboardEntry.Kind(rawValue: String(cString: kindText)),
              let textValue = sqlite3_column_text(statement, 2)
        else { return nil }

        var data: Data?
        if let blob = sqlite3_column_blob(statement, 3) {
            data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 3)))
        }
        let source = sqlite3_column_text(statement, 4).map { String(cString: $0) }

        return ClipboardEntry(
            id: sqlite3_column_int64(statement, 0),
            kind: kind,
            text: String(cString: textValue),
            data: data,
            source: source,
            copiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
        )
    }

    // MARK: - Уборка

    func delete(id: Int64) {
        queue.sync {
            guard let database else { return }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database, "DELETE FROM entries WHERE id = ?;", -1, &statement, nil
            ) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, id)
            sqlite3_step(statement)
        }
    }

    func deleteAll() {
        queue.sync {
            execute("DELETE FROM entries;")
            // Файл после чистки остаётся прежнего размера — возвращаем место
            // системе, иначе «очистить» не освобождало бы ничего.
            execute("VACUUM;")
        }
        DebugLog.write("буфер: история очищена")
    }

    /// Убирает просроченное и лишнее.
    ///
    /// - Parameters:
    ///   - lifetime: сколько живёт запись. Ноль — не ограничивать сроком.
    ///   - limit: сколько записей держать, считая от свежих.
    func prune(lifetime: TimeInterval, limit: Int) {
        queue.sync {
            guard let database else { return }

            if lifetime > 0 {
                let deadline = Date().addingTimeInterval(-lifetime).timeIntervalSince1970
                var statement: OpaquePointer?
                if sqlite3_prepare_v2(
                    database, "DELETE FROM entries WHERE copiedAt < ?;", -1, &statement, nil
                ) == SQLITE_OK {
                    sqlite3_bind_double(statement, 1, deadline)
                    sqlite3_step(statement)
                }
                sqlite3_finalize(statement)
            }

            var statement: OpaquePointer?
            let sql = """
                DELETE FROM entries WHERE id NOT IN (
                    SELECT id FROM entries ORDER BY copiedAt DESC LIMIT ?
                );
                """
            if sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(limit))
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }
}
