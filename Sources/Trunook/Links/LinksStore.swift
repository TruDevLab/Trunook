import TrunookXPC
import Foundation
import SQLite3

/// Связь между двумя заметками, найденная моделью.
struct NoteLink: Equatable {
    let toID: Int64
    /// Насколько близки векторы: от порога до единицы.
    let score: Double
    /// Чем связаны — одной фразой от модели. Пусто, если модель промолчала,
    /// а близость всё равно высока.
    let reason: String
}

/// Векторы смысла и найденные по ним связи.
///
/// Отдельно от закладок сверки: связи живут и без Obsidian — их можно
/// показывать в панели заметки, даже когда хранилища нет вовсе. Одна таблица
/// на двоих связала бы две несвязанные вещи и уронила бы вторую вместе
/// с первой.
final class LinksStore {
    private var database: OpaquePointer?
    private let queue = DispatchQueue(label: "com.trunook.links.store")
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let url: URL

    init(url: URL = NotesStore.defaultURL) {
        self.url = url
        open()
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    private func open() {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            DebugLog.write("связи: база не открылась — \(lastError)")
            database = nil
            return
        }
        execute("PRAGMA journal_mode = WAL;")
        execute("""
            CREATE TABLE IF NOT EXISTS note_vectors (
                noteID INTEGER PRIMARY KEY,
                model TEXT NOT NULL,
                hash TEXT NOT NULL,
                vector BLOB NOT NULL
            );
            """)
        execute("""
            CREATE TABLE IF NOT EXISTS note_links (
                fromID INTEGER NOT NULL,
                toID INTEGER NOT NULL,
                score REAL NOT NULL,
                reason TEXT NOT NULL,
                decidedAt REAL NOT NULL,
                PRIMARY KEY (fromID, toID)
            );
            """)
    }

    private var lastError: String {
        database.map { String(cString: sqlite3_errmsg($0)) } ?? "база не открыта"
    }

    private func execute(_ sql: String) {
        guard let database else { return }
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(database, sql, nil, nil, &error) != SQLITE_OK, let error {
            DebugLog.write("связи: \(String(cString: error))")
            sqlite3_free(error)
        }
    }

    // MARK: - Векторы

    /// Все векторы, посчитанные этой же моделью.
    ///
    /// Модель в условии не для порядка: у разных моделей векторы разной длины
    /// и разного смысла, и сравнивать их между собой нельзя. Смена модели
    /// в настройках должна оставлять прежние векторы за бортом, а не путать
    /// их с новыми.
    func vectors(model: String) -> [(noteID: Int64, vector: [Float])] {
        queue.sync {
            guard let database else { return [] }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database, "SELECT noteID, vector FROM note_vectors WHERE model = ?;", -1, &statement, nil
            ) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, model, -1, Self.transient)

            var result: [(noteID: Int64, vector: [Float])] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let blob = sqlite3_column_blob(statement, 1) else { continue }
                let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 1)))
                result.append((sqlite3_column_int64(statement, 0), Embedding.vector(from: data)))
            }
            return result
        }
    }

    /// Отпечаток текста, по которому вектор считали. По нему видно,
    /// нужно ли считать заново.
    func hash(noteID: Int64, model: String) -> String? {
        queue.sync {
            guard let database else { return nil }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "SELECT hash FROM note_vectors WHERE noteID = ? AND model = ?;",
                -1, &statement, nil
            ) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, noteID)
            sqlite3_bind_text(statement, 2, model, -1, Self.transient)

            guard sqlite3_step(statement) == SQLITE_ROW,
                  let text = sqlite3_column_text(statement, 0)
            else { return nil }
            return String(cString: text)
        }
    }

    func put(noteID: Int64, model: String, hash: String, vector: [Float]) {
        queue.sync {
            guard let database else { return }
            let sql = """
                INSERT OR REPLACE INTO note_vectors (noteID, model, hash, vector) VALUES (?, ?, ?, ?);
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }

            let data = Embedding.data(from: vector)
            sqlite3_bind_int64(statement, 1, noteID)
            sqlite3_bind_text(statement, 2, model, -1, Self.transient)
            sqlite3_bind_text(statement, 3, hash, -1, Self.transient)
            _ = data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(data.count), Self.transient)
            }
            sqlite3_step(statement)
        }
    }

    // MARK: - Связи

    func links(from noteID: Int64) -> [NoteLink] {
        queue.sync {
            guard let database else { return [] }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "SELECT toID, score, reason FROM note_links WHERE fromID = ? ORDER BY score DESC;",
                -1, &statement, nil
            ) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, noteID)

            var result: [NoteLink] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let reason = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
                result.append(
                    NoteLink(
                        toID: sqlite3_column_int64(statement, 0),
                        score: sqlite3_column_double(statement, 1),
                        reason: reason
                    )
                )
            }
            return result
        }
    }

    /// Кладёт связи заметки взамен прежних.
    ///
    /// Именно взамен: заметку правят, смысл её меняется, и прежние связи
    /// становятся неверными. Копить их значило бы, что однажды написанное
    /// «связано с» уже никогда не отменить.
    func replace(from noteID: Int64, with links: [NoteLink], now: Date = Date()) {
        queue.sync {
            guard let database else { return }

            var wipe: OpaquePointer?
            if sqlite3_prepare_v2(
                database, "DELETE FROM note_links WHERE fromID = ?;", -1, &wipe, nil
            ) == SQLITE_OK {
                sqlite3_bind_int64(wipe, 1, noteID)
                sqlite3_step(wipe)
            }
            sqlite3_finalize(wipe)

            for link in links {
                var statement: OpaquePointer?
                let sql = """
                    INSERT OR REPLACE INTO note_links (fromID, toID, score, reason, decidedAt) \
                    VALUES (?, ?, ?, ?, ?);
                    """
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { continue }
                sqlite3_bind_int64(statement, 1, noteID)
                sqlite3_bind_int64(statement, 2, link.toID)
                sqlite3_bind_double(statement, 3, link.score)
                sqlite3_bind_text(statement, 4, link.reason, -1, Self.transient)
                sqlite3_bind_double(statement, 5, now.timeIntervalSince1970)
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            }
        }
    }

    // MARK: - Уборка

    /// Забывает заметку целиком: и её вектор, и связи в обе стороны.
    func forget(noteID: Int64) {
        queue.sync {
            guard let database else { return }
            for sql in [
                "DELETE FROM note_vectors WHERE noteID = ?;",
                "DELETE FROM note_links WHERE fromID = ?;",
                "DELETE FROM note_links WHERE toID = ?;"
            ] {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { continue }
                sqlite3_bind_int64(statement, 1, noteID)
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            }
        }
    }

    /// Так выглядит выключенный поиск связей: ни векторов, ни связей.
    func clearAll() {
        queue.sync {
            execute("DELETE FROM note_vectors;")
            execute("DELETE FROM note_links;")
        }
        DebugLog.write("связи: очищены")
    }
}
