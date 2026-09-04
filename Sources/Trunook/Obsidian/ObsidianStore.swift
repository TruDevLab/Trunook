import TrunookXPC
import Foundation
import SQLite3

/// Закладки сверки: что и куда мы в прошлый раз положили.
///
/// Живёт в той же базе, что и заметки, но отдельной таблицей и отдельным
/// объектом. Причина не в опрятности: закладка — это состояние **связи**
/// с чужой папкой, а не свойство заметки. Уйдёт хранилище — уйдут закладки,
/// а заметки останутся; и наоборот, выключенная синхронизация не должна
/// оставлять в таблице заметок колонок, которые никому не нужны.
///
/// Устройство скопировано с `NotesStore`: системный SQLite, своя
/// последовательная очередь, путь в `init` ради тестов.
final class ObsidianStore {
    private var database: OpaquePointer?
    private let queue = DispatchQueue(label: "com.trunook.obsidian.store")
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let url: URL

    init(url: URL = NotesStore.defaultURL) {
        self.url = url
        open()
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    // MARK: - Открытие

    private func open() {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            DebugLog.write("Obsidian: база закладок не открылась — \(lastError)")
            database = nil
            return
        }
        execute("PRAGMA journal_mode = WAL;")
        execute("""
            CREATE TABLE IF NOT EXISTS obsidian_files (
                noteID INTEGER PRIMARY KEY,
                uid TEXT NOT NULL,
                path TEXT NOT NULL,
                hash TEXT NOT NULL,
                modified REAL NOT NULL,
                size INTEGER NOT NULL,
                syncedAt REAL NOT NULL,
                own INTEGER NOT NULL
            );
            """)
        execute("CREATE INDEX IF NOT EXISTS obsidian_path ON obsidian_files(path);")
    }

    private var lastError: String {
        database.map { String(cString: sqlite3_errmsg($0)) } ?? "база не открыта"
    }

    private func execute(_ sql: String) {
        guard let database else { return }
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(database, sql, nil, nil, &error) != SQLITE_OK, let error {
            DebugLog.write("Obsidian: \(String(cString: error))")
            sqlite3_free(error)
        }
    }

    // MARK: - Чтение

    /// Закладки своих заметок — тех, что ходят в обе стороны.
    func own() -> [OwnBookmark] {
        rows(where: "own = 1").map {
            OwnBookmark(
                noteID: $0.noteID,
                uid: $0.uid,
                path: $0.path,
                hash: $0.hash,
                syncedAt: $0.syncedAt
            )
        }
    }

    /// Закладки зеркал — заметок хранилища, которые приложение только читает.
    func mirrors() -> [MirrorBookmark] {
        rows(where: "own = 0").map {
            MirrorBookmark(noteID: $0.noteID, path: $0.path, modified: $0.modified, size: $0.size)
        }
    }

    /// Сколько файлов было известно в прошлую сверку.
    ///
    /// По этому числу узнаётся опустевшая папка: отключённый диск и стёртое
    /// хранилище выглядят одинаково, и сравнивать не с чем, если не помнить,
    /// сколько файлов было.
    var knownFiles: Int {
        queue.sync {
            guard let database else { return 0 }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM obsidian_files;", -1, &statement, nil)
                == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(statement, 0))
        }
    }

    /// Номер заметки, за которой стоит этот путь.
    func noteID(forPath path: String) -> Int64? {
        rows(where: "path = ?") { statement in
            sqlite3_bind_text(statement, 1, path, -1, Self.transient)
        }.first?.noteID
    }

    private struct Row {
        let noteID: Int64
        let uid: String
        let path: String
        let hash: String
        let modified: Date
        let size: Int
        let syncedAt: Date
    }

    private func rows(where condition: String, bind: (OpaquePointer?) -> Void = { _ in }) -> [Row] {
        queue.sync {
            guard let database else { return [] }
            let sql = """
                SELECT noteID, uid, path, hash, modified, size, syncedAt \
                FROM obsidian_files WHERE \(condition);
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                DebugLog.write("Obsidian: закладки не прочитались — \(lastError)")
                return []
            }
            defer { sqlite3_finalize(statement) }
            bind(statement)

            var result: [Row] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let uid = sqlite3_column_text(statement, 1),
                      let path = sqlite3_column_text(statement, 2),
                      let hash = sqlite3_column_text(statement, 3)
                else { continue }
                result.append(
                    Row(
                        noteID: sqlite3_column_int64(statement, 0),
                        uid: String(cString: uid),
                        path: String(cString: path),
                        hash: String(cString: hash),
                        modified: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                        size: Int(sqlite3_column_int64(statement, 5)),
                        syncedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
                    )
                )
            }
            return result
        }
    }

    // MARK: - Запись

    /// Кладёт закладку своей заметки.
    ///
    /// Отпечаток здесь — не украшение: по нему следующая сверка узнаёт
    /// **свою же запись**. Событие файловой системы приходит на неё сразу
    /// же, и без отпечатка она выглядела бы чужой правкой.
    func put(own bookmark: OwnBookmark, modified: Date, size: Int) {
        write(
            noteID: bookmark.noteID,
            uid: bookmark.uid,
            path: bookmark.path,
            hash: bookmark.hash,
            modified: modified,
            size: size,
            syncedAt: bookmark.syncedAt,
            own: true
        )
    }

    /// Кладёт закладку зеркала.
    func put(mirror: MirrorBookmark, syncedAt: Date = Date()) {
        write(
            noteID: mirror.noteID,
            uid: "",
            path: mirror.path,
            hash: "",
            modified: mirror.modified,
            size: mirror.size,
            syncedAt: syncedAt,
            own: false
        )
    }

    private func write(
        noteID: Int64,
        uid: String,
        path: String,
        hash: String,
        modified: Date,
        size: Int,
        syncedAt: Date,
        own: Bool
    ) {
        queue.sync {
            guard let database else { return }
            let sql = """
                INSERT OR REPLACE INTO obsidian_files \
                (noteID, uid, path, hash, modified, size, syncedAt, own) \
                VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                DebugLog.write("Obsidian: закладка не подготовилась — \(lastError)")
                return
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, noteID)
            sqlite3_bind_text(statement, 2, uid, -1, Self.transient)
            sqlite3_bind_text(statement, 3, path, -1, Self.transient)
            sqlite3_bind_text(statement, 4, hash, -1, Self.transient)
            sqlite3_bind_double(statement, 5, modified.timeIntervalSince1970)
            sqlite3_bind_int64(statement, 6, Int64(size))
            sqlite3_bind_double(statement, 7, syncedAt.timeIntervalSince1970)
            sqlite3_bind_int(statement, 8, own ? 1 : 0)

            if sqlite3_step(statement) != SQLITE_DONE {
                DebugLog.write("Obsidian: закладка не легла — \(lastError)")
            }
        }
    }

    // MARK: - Уборка

    func forget(noteID: Int64) {
        queue.sync {
            guard let database else { return }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database, "DELETE FROM obsidian_files WHERE noteID = ?;", -1, &statement, nil
            ) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, noteID)
            sqlite3_step(statement)
        }
    }

    /// Забывает всё. Так выглядит выключенная синхронизация: связь с папкой
    /// разорвана, но ни одна заметка и ни один файл при этом не тронуты.
    func forgetAll() {
        queue.sync { execute("DELETE FROM obsidian_files;") }
        DebugLog.write("Obsidian: закладки очищены")
    }
}
