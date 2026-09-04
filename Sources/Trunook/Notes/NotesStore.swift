import TrunookXPC
import Foundation
import SQLite3

/// Хранилище заметок.
///
/// Системный SQLite, без сторонних библиотек — как у истории буфера обмена.
/// Причина та же: заметки обязаны пережить перезапуск, а держать их
/// в `UserDefaults` нельзя — там оказался бы весь оформленный текст,
/// и файл настроек читался бы при каждом запуске со всей этой начинкой.
///
/// Отличие от `ClipboardStore` одно, но важное: **путь к файлу приходит
/// в `init`**, а не выписан статическим свойством. У буфера он статический,
/// и проверить хранилище, не тронув настоящую базу человека, там нельзя
/// вовсе.
final class NotesStore {
    private var database: OpaquePointer?
    private let queue = DispatchQueue(label: "com.trunook.notes.store")

    /// SQLite должен скопировать переданную строку себе: иначе она успевает
    /// освободиться до выполнения запроса.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Обычное место базы. В тестах вместо него подставляется временный файл.
    static let defaultURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base
            .appendingPathComponent("Trunook", isDirectory: true)
            .appendingPathComponent("notes.sqlite")
    }()

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
            DebugLog.write("заметки: база не открылась — \(lastError)")
            database = nil
            return
        }

        execute("PRAGMA journal_mode = WAL;")
        execute("""
            CREATE TABLE IF NOT EXISTS notes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                rtf BLOB NOT NULL,
                plain TEXT NOT NULL,
                folded TEXT NOT NULL,
                createdAt REAL NOT NULL,
                updatedAt REAL NOT NULL,
                origin TEXT NOT NULL,
                titleByModel INTEGER NOT NULL,
                uid TEXT NOT NULL DEFAULT ''
            );
            """)
        execute("CREATE INDEX IF NOT EXISTS notes_time ON notes(updatedAt DESC);")
        migrate()
    }

    /// Достройка схемы на базе, заведённой прежней версией.
    ///
    /// `CREATE TABLE IF NOT EXISTS` существующую таблицу не меняет вовсе,
    /// поэтому новую колонку приходится добавлять руками — и только если её
    /// ещё нет: повторный `ALTER TABLE` это ошибка, а не тишина.
    ///
    /// Номер разливается всем накопленным заметкам сразу: без него заметка
    /// не нашла бы свой файл в хранилище после переименования.
    private func migrate() {
        guard !columnNames(of: "notes").contains("uid") else { return }
        execute("ALTER TABLE notes ADD COLUMN uid TEXT NOT NULL DEFAULT '';")
        execute("UPDATE notes SET uid = lower(hex(randomblob(16))) WHERE uid = '';")
        DebugLog.write("заметки: схема дополнена номером заметки")
    }

    private func columnNames(of table: String) -> Set<String> {
        guard let database else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK
        else { return [] }
        defer { sqlite3_finalize(statement) }

        var names: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) { names.insert(String(cString: name)) }
        }
        return names
    }

    private var lastError: String {
        database.map { String(cString: sqlite3_errmsg($0)) } ?? "база не открыта"
    }

    private func execute(_ sql: String) {
        guard let database else { return }
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(database, sql, nil, nil, &error) != SQLITE_OK, let error {
            DebugLog.write("заметки: \(String(cString: error))")
            sqlite3_free(error)
        }
    }

    // MARK: - Запись

    /// Кладёт новую заметку и возвращает назначенный ей идентификатор.
    ///
    /// Повторы здесь не отсеиваются, в отличие от буфера: две одинаковые
    /// заметки — это осознанно записанное дважды, а не случайно скопированное
    /// повторно. Слить их значило бы потерять одну.
    func insert(_ note: Note) -> Int64? {
        queue.sync {
            guard let database else { return nil }

            let sql = """
                INSERT INTO notes (title, rtf, plain, folded, createdAt, updatedAt, origin, titleByModel, uid)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                DebugLog.write("заметки: запись не подготовилась — \(lastError)")
                return nil
            }
            defer { sqlite3_finalize(statement) }

            bindBody(note, to: statement, from: 1)
            sqlite3_bind_double(statement, 5, note.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 6, note.updatedAt.timeIntervalSince1970)
            sqlite3_bind_text(statement, 7, note.origin.rawValue, -1, Self.transient)
            sqlite3_bind_int(statement, 8, note.titleByModel ? 1 : 0)
            sqlite3_bind_text(statement, 9, note.uid, -1, Self.transient)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                DebugLog.write("заметки: запись не легла — \(lastError)")
                return nil
            }
            return sqlite3_last_insert_rowid(database)
        }
    }

    /// Переписывает заметку целиком. `createdAt` не трогаем: заметка та же,
    /// изменилось только её содержимое.
    @discardableResult
    func update(_ note: Note) -> Bool {
        queue.sync {
            guard let database, note.isSaved else { return false }

            let sql = """
                UPDATE notes
                SET title = ?, rtf = ?, plain = ?, folded = ?, updatedAt = ?, titleByModel = ?
                WHERE id = ?;
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                DebugLog.write("заметки: правка не подготовилась — \(lastError)")
                return false
            }
            defer { sqlite3_finalize(statement) }

            bindBody(note, to: statement, from: 1)
            sqlite3_bind_double(statement, 5, note.updatedAt.timeIntervalSince1970)
            sqlite3_bind_int(statement, 6, note.titleByModel ? 1 : 0)
            sqlite3_bind_int64(statement, 7, note.id)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                DebugLog.write("заметки: правка не легла — \(lastError)")
                return false
            }
            return true
        }
    }

    /// Только имя — им правит фоновое именование, и трогать текст ему незачем.
    ///
    /// `folded` пересчитывается тут же: имя входит в поиск, и оставленный
    /// прежним отпечаток искал бы по старому названию. Порознь эти две
    /// колонки и разъезжаются.
    @discardableResult
    func rename(id: Int64, title: String, plain: String, byModel: Bool) -> Bool {
        queue.sync {
            guard let database else { return false }
            let sql = "UPDATE notes SET title = ?, folded = ?, titleByModel = ? WHERE id = ?;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return false
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, title, -1, Self.transient)
            sqlite3_bind_text(statement, 2, Note.folded(title: title, plain: plain), -1, Self.transient)
            sqlite3_bind_int(statement, 3, byModel ? 1 : 0)
            sqlite3_bind_int64(statement, 4, id)
            return sqlite3_step(statement) == SQLITE_DONE
        }
    }

    /// Общая часть записи и правки: то, что в обеих идёт одинаково.
    /// Порознь эти четыре привязки уже начинали расходиться порядком.
    private func bindBody(_ note: Note, to statement: OpaquePointer?, from index: Int32) {
        sqlite3_bind_text(statement, index, note.title, -1, Self.transient)
        _ = note.rtf.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index + 1, bytes.baseAddress, Int32(note.rtf.count), Self.transient)
        }
        sqlite3_bind_text(statement, index + 2, note.plain, -1, Self.transient)
        sqlite3_bind_text(statement, index + 3, note.folded, -1, Self.transient)
    }

    // MARK: - Чтение

    private static let columns = """
        id, title, rtf, plain, createdAt, updatedAt, origin, titleByModel, uid
        """

    /// Порядок выдачи: свои впереди, заметки хранилища следом, внутри
    /// каждой половины — свежие первыми.
    ///
    /// Хранилище бывает на тысячи заметок, и вперемешку по одной только дате
    /// своя заметка тонула бы в чужих: правку в Obsidian человек делает
    /// каждый день, а в приложении заметки заводит реже.
    private static let order = "origin = '\(Note.Origin.obsidian.rawValue)' ASC, updatedAt DESC"

    /// Все заметки, свежие первыми.
    func all(source: NoteSource = .all) -> [Note] {
        query("SELECT \(Self.columns) FROM notes\(Self.clause(source)) ORDER BY \(Self.order);") { _ in }
    }

    private static func clause(_ source: NoteSource) -> String {
        source.condition.map { " WHERE \($0)" } ?? ""
    }

    /// Поиск по ключевым словам.
    ///
    /// Каждое слово запроса ищется отдельно и должно найтись — иначе запрос
    /// из двух слов работал бы только при том же порядке и с тем же пробелом
    /// между ними, что в заметке.
    ///
    /// Сравнение идёт по сложенной колонке: `LIKE` в SQLite складывает
    /// регистр только для латиницы, и по-русски поиск иначе молчит.
    func search(_ text: String, source: NoteSource = .all) -> [Note] {
        let words = text.folded
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !words.isEmpty else { return all(source: source) }

        var conditions = words.map { _ in "folded LIKE ? ESCAPE '\\'" }
        if let extra = source.condition { conditions.append(extra) }
        let sql = """
            SELECT \(Self.columns) FROM notes \
            WHERE \(conditions.joined(separator: " AND ")) ORDER BY \(Self.order);
            """
        return query(sql) { statement in
            for (offset, word) in words.enumerated() {
                let pattern = "%" + Self.escaped(word) + "%"
                sqlite3_bind_text(statement, Int32(offset + 1), pattern, -1, Self.transient)
            }
        }
    }

    /// Проценты и подчёркивания в запросе — это буквы, а не образец поиска.
    /// Без экранирования один символ «%» находил бы вообще всё.
    private static func escaped(_ word: String) -> String {
        word
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    func note(id: Int64) -> Note? {
        query("SELECT \(Self.columns) FROM notes WHERE id = ?;") { statement in
            sqlite3_bind_int64(statement, 1, id)
        }.first
    }

    var count: Int { count(source: .all) }

    func count(source: NoteSource) -> Int {
        queue.sync {
            guard let database else { return 0 }
            var statement: OpaquePointer?
            let sql = "SELECT COUNT(*) FROM notes\(Self.clause(source));"
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil)
                == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(statement, 0))
        }
    }

    private func query(_ sql: String, bind: (OpaquePointer?) -> Void) -> [Note] {
        queue.sync {
            guard let database else { return [] }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                DebugLog.write("заметки: запрос не подготовился — \(lastError)")
                return []
            }
            defer { sqlite3_finalize(statement) }
            bind(statement)

            var result: [Note] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let note = Self.read(statement) else { continue }
                result.append(note)
            }
            return result
        }
    }

    private static func read(_ statement: OpaquePointer?) -> Note? {
        guard let titleText = sqlite3_column_text(statement, 1),
              let plainText = sqlite3_column_text(statement, 3),
              let originText = sqlite3_column_text(statement, 6),
              let origin = Note.Origin(rawValue: String(cString: originText))
        else { return nil }

        var rtf = Data()
        if let blob = sqlite3_column_blob(statement, 2) {
            rtf = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 2)))
        }

        return Note(
            id: sqlite3_column_int64(statement, 0),
            uid: sqlite3_column_text(statement, 8).map { String(cString: $0) } ?? "",
            title: String(cString: titleText),
            rtf: rtf,
            plain: String(cString: plainText),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
            origin: origin,
            titleByModel: sqlite3_column_int(statement, 7) != 0
        )
    }

    // MARK: - Уборка

    func delete(id: Int64) {
        queue.sync {
            guard let database else { return }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "DELETE FROM notes WHERE id = ?;", -1, &statement, nil)
                == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, id)
            sqlite3_step(statement)
        }
    }

    func deleteAll() {
        queue.sync {
            execute("DELETE FROM notes;")
            // Файл после чистки остаётся прежнего размера — возвращаем место
            // системе, иначе «очистить» не освобождало бы ничего.
            execute("VACUUM;")
        }
        DebugLog.write("заметки: очищены все")
    }
}
