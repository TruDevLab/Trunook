import Foundation

/// Заметка приложения глазами сверки.
struct SyncNote: Equatable {
    let id: Int64
    /// Постоянный номер. Он же лежит в шапке файла и переживает
    /// переименование заметки в Obsidian.
    let uid: String
    let updatedAt: Date
}

/// Файл своей подпапки, прочитанный целиком.
///
/// Свою папку читаем полностью на каждой сверке, в отличие от остального
/// хранилища. Она того стоит: там лежат только наши заметки, их десятки,
/// а взамен переименование файла в Obsidian перестаёт быть загадкой —
/// заметка узнаётся по номеру в шапке, а не по пути.
struct OwnFile: Equatable {
    let path: String
    /// Номер из шапки. `nil` — файл положил в нашу папку человек.
    let uid: String?
    let modified: Date
    let hash: String
}

/// Закладка прошлой сверки для своей заметки.
struct OwnBookmark: Equatable {
    let noteID: Int64
    let uid: String
    let path: String
    /// Отпечаток файла, каким мы его оставили.
    let hash: String
    /// Когда сверка последний раз сводила эти две стороны.
    let syncedAt: Date
}

/// Закладка зеркала — заметки хранилища, которую приложение только читает.
struct MirrorBookmark: Equatable {
    let noteID: Int64
    let path: String
    let modified: Date
    let size: Int
}

/// Что сверка велит сделать.
enum SyncAction: Equatable {
    /// Записать свою заметку в файл. `path` пуст, когда файла ещё нет
    /// и имя ему предстоит назначить.
    case writeOwn(noteID: Int64, path: String?)
    /// Принять правку из файла в свою заметку.
    case acceptOwn(noteID: Int64, path: String)
    /// Файл лежит в нашей папке, а заметки под него нет — завести.
    case adoptOwn(path: String)
    /// Заметку удалили в приложении — унести файл в Корзину.
    case trashOwn(path: String)
    /// Файл удалили в Obsidian — удалить заметку.
    case deleteOwn(noteID: Int64)
    /// Правка с обеих сторон.
    case conflict(noteID: Int64, path: String)
    /// Забыть закладку, за которой не стоит уже ничего.
    case forget(noteID: Int64)

    /// Завести зеркало заметки хранилища.
    case importMirror(path: String)
    /// Перечитать изменившееся зеркало.
    case updateMirror(noteID: Int64, path: String)
    /// Убрать зеркало из базы.
    case dropMirror(noteID: Int64)
}

/// Сверка базы с папкой — чистой функцией.
///
/// Ни одного обращения к диску здесь нет: на входе два снимка, на выходе
/// список действий. Сделано так ровно по той же причине, что и
/// `UpdateSchedule`: решение «кто кого перетирает» — самое опасное место всей
/// работы, и оно обязано проверяться тестом целиком, а не наблюдением
/// за живой папкой.
enum SyncPlan {
    // MARK: - Отказ

    /// Почему сверка не состоялась.
    enum Refusal: Equatable {
        /// Папки нет, она не читается или это не папка.
        case unreachable
        /// Файлов вдруг стало заметно меньше.
        case emptied(known: Int, found: Int)
    }

    enum Outcome: Equatable {
        case refused(Refusal)
        case actions([SyncAction])
    }

    struct Input {
        var vault: Vault
        /// Папка на месте и читается.
        var isReachable: Bool
        /// Читать ли остальное хранилище — не только свою подпапку.
        var indexVault: Bool
        var notes: [SyncNote]
        var bookmarks: [OwnBookmark]
        var ownFiles: [OwnFile]
        var mirrors: [MirrorBookmark]
        var otherFiles: [VaultFile]
        /// Сколько файлов было в прошлую сверку.
        var knownFiles: Int
    }

    /// Ниже этого числа проверка на опустевшую папку не работает: у хранилища
    /// из двух заметок удаление одной — это обычное дело, а не беда.
    static let emptinessFloor = 4

    // MARK: - Решение

    static func make(_ input: Input) -> Outcome {
        // Главная защита всей работы. Отключённый внешний диск, недокачанный
        // iCloud и переименованная папка выглядят одинаково — «файлов нет», —
        // и принять это за «человек всё удалил» значит вычистить базу и унести
        // в Корзину всё, что там ещё лежало.
        guard input.isReachable else { return .refused(.unreachable) }

        let found = input.ownFiles.count + input.otherFiles.count
        if input.knownFiles >= emptinessFloor, found * 2 < input.knownFiles {
            return .refused(.emptied(known: input.knownFiles, found: found))
        }

        var actions: [SyncAction] = []
        var claimed = Set<String>()

        let fileByUID = Dictionary(
            input.ownFiles.compactMap { file in file.uid.map { ($0, file) } },
            uniquingKeysWith: { first, _ in first }
        )
        let bookmarkByNote = Dictionary(
            input.bookmarks.map { ($0.noteID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let noteIDs = Set(input.notes.map(\.id))

        // MARK: Свои заметки

        for note in input.notes {
            let bookmark = bookmarkByNote[note.id]

            guard let file = fileByUID[note.uid] else {
                if bookmark == nil {
                    // Заметку ещё не выкладывали.
                    actions.append(.writeOwn(noteID: note.id, path: nil))
                } else {
                    // Файл был и исчез — значит его удалили в Obsidian.
                    actions.append(.deleteOwn(noteID: note.id))
                }
                continue
            }
            claimed.insert(file.path)

            guard let bookmark else {
                // Файл есть, а закладки нет: база о нём не знает. Такое бывает
                // после переустановки приложения. Файл в этом случае старше
                // не бывает — принимаем его.
                actions.append(.acceptOwn(noteID: note.id, path: file.path))
                continue
            }

            let localChanged = note.updatedAt > bookmark.syncedAt
            // Отпечаток, а не дата: свою собственную запись файловая система
            // отмечает свежей датой, и по дате сверка приняла бы её за чужую
            // правку — и так по кругу.
            //
            // Смена пути — тоже правка: имя файла и есть имя заметки, так что
            // переименование в Obsidian обязано доехать до списка в вырезе.
            let remoteChanged = file.hash != bookmark.hash || file.path != bookmark.path

            switch (localChanged, remoteChanged) {
            case (false, false):
                break
            case (true, false):
                actions.append(.writeOwn(noteID: note.id, path: file.path))
            case (false, true):
                actions.append(.acceptOwn(noteID: note.id, path: file.path))
            case (true, true):
                actions.append(.conflict(noteID: note.id, path: file.path))
            }
        }

        // MARK: Закладки без заметок

        // Заметку удалили в приложении. Файл под ней нужно унести в Корзину —
        // но только тот, что стоит под нашим же номером: файл, попавший
        // в папку иначе, к этой закладке отношения не имеет.
        for bookmark in input.bookmarks where !noteIDs.contains(bookmark.noteID) {
            if let file = fileByUID[bookmark.uid] {
                claimed.insert(file.path)
                actions.append(.trashOwn(path: file.path))
            }
            actions.append(.forget(noteID: bookmark.noteID))
        }

        // MARK: Чужие файлы в своей папке

        // Человек положил заметку в нашу подпапку прямо из Obsidian. Она
        // становится своей — папка для того и заведена.
        for file in input.ownFiles where !claimed.contains(file.path) {
            actions.append(.adoptOwn(path: file.path))
        }

        // MARK: Зеркала

        guard input.indexVault else {
            // Чтение хранилища выключили — зеркала уходят из базы. Свои
            // заметки и файлы это не трогает вовсе.
            actions.append(contentsOf: input.mirrors.map { .dropMirror(noteID: $0.noteID) })
            return .actions(actions)
        }

        let fileByPath = Dictionary(
            input.otherFiles.map { ($0.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set<String>()

        for mirror in input.mirrors {
            guard let file = fileByPath[mirror.path] else {
                actions.append(.dropMirror(noteID: mirror.noteID))
                continue
            }
            seen.insert(file.path)
            if changed(file.modified, mirror.modified) || file.size != mirror.size {
                actions.append(.updateMirror(noteID: mirror.noteID, path: file.path))
            }
        }

        for file in input.otherFiles where !seen.contains(file.path) {
            actions.append(.importMirror(path: file.path))
        }

        return .actions(actions)
    }

    /// Даты сравниваются с допуском в секунду.
    ///
    /// Дата правки приезжает из файловой системы дробной, а хранится
    /// в SQLite вещественным числом. Точное сравнение после такого круга
    /// то и дело врёт «изменилось», и хранилище перечитывалось бы целиком
    /// на каждой сверке.
    private static func changed(_ one: Date, _ other: Date) -> Bool {
        abs(one.timeIntervalSince(other)) > 1
    }
}
