import AppKit
import Foundation
import TrunookXPC

/// Что сейчас с синхронизацией — для карточки в настройках.
enum ObsidianState: Equatable {
    /// Выключено. Ни таймера, ни слежения, ни единого обращения к диску.
    case off
    /// Папка ещё не выбрана.
    case noFolder
    /// Папки нет, она не читается или это не папка.
    case unreachable
    /// Файлов вдруг стало вдвое меньше — сверка остановлена, ничего не тронуто.
    case emptied
    case syncing
    case synced(Date)
    /// Включено и настроено, но сверки ещё не было.
    case never
}

/// Синхронизация заметок с хранилищем Obsidian.
///
/// Устройство то же, что у `UpdateService`: таймер в `RunLoop.main` режимом
/// `.common`, пробуждение по возвращении из сна, отложенный первый заход.
/// Добавилось слежение за папкой — без него правка в Obsidian ждала бы
/// четверть часа.
///
/// **Выключенная настройка означает бездействие целиком.** Не «сверка
/// ничего не находит», а «служба не заведена»: ни таймера, ни потока
/// событий, ни одного чтения диска. Obsidian есть далеко не у всех,
/// и у тех, у кого его нет, приложение обязано вести себя ровно так же,
/// как до появления этой работы.
final class ObsidianService: ObservableObject {
    @Published private(set) var state: ObsidianState = .off

    /// Заметки изменились — списку в вырезе пора перечитаться.
    var onNotesChanged: (() -> Void)?

    private let store: NotesStore
    private let bookmarks: ObsidianStore
    private let settings: Settings
    private let watcher = VaultWatcher()

    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.trunook.obsidian.sync")
    private var isSyncing = false
    /// Подписаны ли на пробуждение. Флаг, а не безусловный отзыв подписки:
    /// `NSWorkspace.shared` — это AppKit, и трогать его из `deinit`, который
    /// случается на чужом потоке, незачем, пока подписки и не было.
    private var isObserving = false

    /// Как часто сверяться самому. Слежение за папкой ловит правки сразу,
    /// а этот заход подбирает то, что оно упустило: сон крышки, сетевой диск,
    /// сорвавшийся поток событий.
    private static let tick: TimeInterval = 15 * 60

    /// Первый заход не сразу: запуск занят разрешениями, календарём
    /// и списком моделей. Причина та же, что и у проверки обновлений.
    private static let firstDelay: TimeInterval = 30

    init(
        store: NotesStore = NotesStore(),
        bookmarks: ObsidianStore = ObsidianStore(),
        settings: Settings = .shared
    ) {
        self.store = store
        self.bookmarks = bookmarks
        self.settings = settings
    }

    deinit { stop() }

    // MARK: - Хранилище

    /// Хранилище, названное в настройках. `nil` — путь ещё не выбран.
    var vault: Vault? {
        Vault(path: settings.obsidianVaultPath, folder: settings.obsidianFolder)
    }

    /// Где лежит файл этой заметки. `nil` — заметка в хранилище не бывала.
    func path(ofNote id: Int64) -> String? {
        (bookmarks.own().first { $0.noteID == id }?.path)
            ?? (bookmarks.mirrors().first { $0.noteID == id }?.path)
    }

    // MARK: - Пуск и остановка

    func start() {
        stop()

        guard settings.obsidianEnabled else {
            state = .off
            return
        }
        guard let vault else {
            state = .noFolder
            return
        }

        state = settings.lastObsidianSync.map { .synced($0) } ?? .never

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstDelay) { [weak self] in
            self?.sync(manual: false)
        }

        let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
            self?.sync(manual: false)
        }
        // `.common`, иначе таймер встаёт, пока человек водит мышью по вырезу.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        watcher.onChange = { [weak self] in self?.sync(manual: false) }
        watcher.start(url: vault.url)

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(woke),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        isObserving = true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        watcher.stop()
        guard isObserving else { return }
        isObserving = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Настройки поменяли — служба поднимается заново или гаснет.
    ///
    /// Выключение забывает закладки: связь с папкой разорвана. Заметки
    /// хранилища при этом уходят из базы — они всего лишь зеркало, — а свои
    /// заметки и файлы на диске не трогаются вовсе.
    func settingsChanged() {
        let wasEnabled = state != .off
        start()
        guard wasEnabled, !settings.obsidianEnabled else { return }
        queue.async { [weak self] in
            self?.dropEverything()
        }
    }

    /// Папку для своих заметок переименовали или перенесли.
    ///
    /// Файлы едут за ней. Оставь их на прежнем месте — и следующая сверка
    /// увидела бы в старой папке чужие заметки (её содержимое перестало быть
    /// своим), а в новой пустоту, и завела бы всё заново вторым экземпляром.
    ///
    /// Старая папка не убирается, даже если опустела: это папка в личном
    /// хранилище человека, и решать за него, нужна ли она ещё, незачем.
    func folderChanged() {
        guard settings.obsidianEnabled, let vault else { return }
        queue.async { [weak self] in
            guard let self else { return }
            var moved = 0
            var taken = Set<String>()

            for bookmark in bookmarks.own() where !vault.isOwn(bookmark.path) {
                let name = (bookmark.path as NSString).lastPathComponent
                let target = VaultScanner.freePath(fileName: name, in: vault, taken: taken)
                guard VaultScanner.move(bookmark.path, to: target, in: vault) else { continue }
                taken.insert(target)
                moved += 1

                let values = try? vault.fileURL(for: target).resourceValues(
                    forKeys: [.contentModificationDateKey, .fileSizeKey]
                )
                bookmarks.put(
                    own: OwnBookmark(
                        noteID: bookmark.noteID,
                        uid: bookmark.uid,
                        path: target,
                        hash: bookmark.hash,
                        syncedAt: bookmark.syncedAt
                    ),
                    modified: values?.contentModificationDate ?? Date(),
                    size: values?.fileSize ?? 0
                )
            }
            DebugLog.write("Obsidian: папка сменилась, переехало файлов \(moved)")
            DispatchQueue.main.async { [weak self] in self?.sync(manual: true) }
        }
    }

    @objc private func woke() { sync(manual: false) }

    private func dropEverything() {
        for note in store.all(source: .vault) { store.delete(id: note.id) }
        bookmarks.forgetAll()
        DispatchQueue.main.async { [weak self] in self?.onNotesChanged?() }
        DebugLog.write("Obsidian: выключено, зеркала убраны, свои заметки целы")
    }

    // MARK: - Сверка

    func sync(manual: Bool) {
        guard settings.obsidianEnabled, let vault else {
            state = settings.obsidianEnabled ? .noFolder : .off
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        state = .syncing

        queue.async { [weak self] in
            guard let self else { return }
            let outcome = run(in: vault)
            _ = manual
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                isSyncing = false
                state = outcome
                if case .synced(let date) = outcome { settings.lastObsidianSync = date }
                onNotesChanged?()
            }
        }
    }

    /// Сверка прямо здесь, без очереди и без таймера.
    ///
    /// Ею пользуются тесты: дожидаться фонового захода в них не на чем,
    /// а проверять сверку по-настоящему — с живой папкой и живой базой —
    /// нужно обязательно. Чистое решение проверяет `SyncPlan`, а здесь
    /// проверяется исполнение.
    @discardableResult
    func syncSynchronously() -> ObsidianState {
        guard settings.obsidianEnabled else { return .off }
        guard let vault else { return .noFolder }
        let outcome = run(in: vault)
        if case .synced(let date) = outcome { settings.lastObsidianSync = date }
        state = outcome
        return outcome
    }

    private func run(in vault: Vault) -> ObsidianState {
        let files = VaultScanner.files(in: vault)
        let ownFiles = files.filter { vault.isOwn($0.path) }.compactMap { read(own: $0, in: vault) }
        let otherFiles = files.filter { !vault.isOwn($0.path) }

        let input = SyncPlan.Input(
            vault: vault,
            isReachable: vault.isReachable,
            indexVault: settings.obsidianIndexVault,
            notes: store.all(source: .own).map {
                SyncNote(id: $0.id, uid: $0.uid, updatedAt: $0.updatedAt)
            },
            bookmarks: bookmarks.own(),
            ownFiles: ownFiles,
            mirrors: bookmarks.mirrors(),
            otherFiles: otherFiles,
            knownFiles: bookmarks.knownFiles
        )

        switch SyncPlan.make(input) {
        case .refused(.unreachable):
            DebugLog.write("Obsidian: папка недоступна, сверка не тронула ничего")
            return .unreachable
        case .refused(.emptied(let known, let found)):
            DebugLog.write("Obsidian: было \(known) файлов, стало \(found) — сверка остановлена")
            return .emptied
        case .actions(let actions):
            apply(actions, files: files, in: vault)
            DebugLog.write("Obsidian: сверка прошла, действий \(actions.count)")
            return .synced(Date())
        }
    }

    /// Читает файл своей папки целиком: номер из шапки и отпечаток.
    private func read(own file: VaultFile, in vault: Vault) -> OwnFile? {
        guard let text = VaultScanner.text(at: file.path, in: vault) else { return nil }
        let uid = ObsidianMarkdown.value(of: ObsidianMarkdown.Key.uid, in: ObsidianMarkdown.split(text).front)
        return OwnFile(
            path: file.path,
            uid: uid,
            modified: file.modified,
            hash: VaultFile.hash(of: text)
        )
    }

    // MARK: - Исполнение

    private func apply(_ actions: [SyncAction], files: [VaultFile], in vault: Vault) {
        guard !actions.isEmpty else { return }
        VaultScanner.ensureOwnFolder(in: vault)

        let byPath = Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var taken = Set<String>()

        for action in actions {
            switch action {
            case .writeOwn(let noteID, let path):
                write(noteID: noteID, to: path, in: vault, taken: &taken)
            case .acceptOwn(let noteID, let path):
                accept(noteID: noteID, from: path, in: vault)
            case .adoptOwn(let path):
                adopt(path: path, in: vault)
            case .trashOwn(let path):
                VaultScanner.trash(path, in: vault)
            case .deleteOwn(let noteID):
                store.delete(id: noteID)
                bookmarks.forget(noteID: noteID)
            case .conflict(let noteID, let path):
                resolve(noteID: noteID, path: path, in: vault)
            case .forget(let noteID):
                bookmarks.forget(noteID: noteID)
            case .importMirror(let path):
                guard let file = byPath[path] else { break }
                importMirror(file: file, in: vault)
            case .updateMirror(let noteID, let path):
                guard let file = byPath[path] else { break }
                updateMirror(noteID: noteID, file: file, in: vault)
            case .dropMirror(let noteID):
                store.delete(id: noteID)
                bookmarks.forget(noteID: noteID)
            }
        }
    }

    // MARK: Своя заметка

    private func write(noteID: Int64, to path: String?, in vault: Vault, taken: inout Set<String>) {
        guard let note = store.note(id: noteID) else { return }
        let target = path ?? VaultScanner.freePath(
            fileName: ObsidianMarkdown.fileName(for: note),
            in: vault,
            taken: taken
        )
        taken.insert(target)

        let existing = path.flatMap { VaultScanner.text(at: $0, in: vault) }
        let text = ObsidianMarkdown.file(for: note, uid: note.uid, existing: existing)
        guard VaultScanner.write(text, to: target, in: vault) else { return }
        remember(noteID: noteID, uid: note.uid, path: target, text: text, in: vault)
    }

    private func accept(noteID: Int64, from path: String, in vault: Vault) {
        guard var note = store.note(id: noteID),
              let text = VaultScanner.text(at: path, in: vault)
        else { return }

        let attributed = ObsidianMarkdown.attributed(from: ObsidianMarkdown.readableBody(of: text))
        note.title = Self.title(ofPath: path)
        note.rtf = Self.rtf(of: attributed)
        note.plain = attributed.string
        note.updatedAt = Date()
        // Имя пришло из имени файла, а не от модели: переименовывать его
        // фоновому имядателю теперь незачем.
        note.titleByModel = true
        store.update(note)
        remember(noteID: noteID, uid: note.uid, path: path, text: text, in: vault)
    }

    private func adopt(path: String, in vault: Vault) {
        guard let text = VaultScanner.text(at: path, in: vault) else { return }
        let parts = ObsidianMarkdown.split(text)
        let uid = ObsidianMarkdown.value(of: ObsidianMarkdown.Key.uid, in: parts.front) ?? UUID().uuidString
        let attributed = ObsidianMarkdown.attributed(from: ObsidianMarkdown.stripLinks(from: parts.body))
        let created = ObsidianMarkdown.value(of: ObsidianMarkdown.Key.created, in: parts.front)
            .flatMap(ObsidianMarkdown.date(from:)) ?? Date()

        var note = Note(
            id: Note.unsaved,
            uid: uid,
            title: Self.title(ofPath: path),
            rtf: Self.rtf(of: attributed),
            plain: attributed.string,
            createdAt: created,
            updatedAt: Date(),
            origin: .typed,
            titleByModel: true
        )
        guard let id = store.insert(note) else { return }
        note.id = id

        // Номер проставляется в файл сразу: без него следующее переименование
        // в Obsidian выглядело бы как «эту удалили, ту завели».
        let stamped = ObsidianMarkdown.file(for: note, uid: uid, existing: text)
        guard VaultScanner.write(stamped, to: path, in: vault) else { return }
        remember(noteID: id, uid: uid, path: path, text: stamped, in: vault)
    }

    /// Правка с обеих сторон.
    ///
    /// Ни одна из версий не пропадает: наша ложится рядом отдельным файлом,
    /// а в заметку приезжает та, что лежит в хранилище — её человек видел
    /// последней и считает настоящей.
    private func resolve(noteID: Int64, path: String, in vault: Vault) {
        guard let note = store.note(id: noteID) else { return }
        let copy = ObsidianMarkdown.file(for: note, uid: note.uid, existing: nil)
        let base = (path as NSString).deletingPathExtension
        let name = "\(base) (\(t("конфликт")) \(Self.conflictStamp(Date()))).md"
        VaultScanner.write(copy, to: name, in: vault)
        DebugLog.write("Obsidian: спор о \(path), наша версия легла рядом")
        accept(noteID: noteID, from: path, in: vault)
    }

    // MARK: Зеркала

    private func importMirror(file: VaultFile, in vault: Vault) {
        guard let text = VaultScanner.text(at: file.path, in: vault) else { return }
        let attributed = ObsidianMarkdown.attributed(from: ObsidianMarkdown.readableBody(of: text))
        let note = Note(
            id: Note.unsaved,
            title: file.title,
            rtf: Self.rtf(of: attributed),
            plain: attributed.string,
            createdAt: file.modified,
            updatedAt: file.modified,
            origin: .obsidian,
            titleByModel: true
        )
        guard let id = store.insert(note) else { return }
        bookmarks.put(
            mirror: MirrorBookmark(noteID: id, path: file.path, modified: file.modified, size: file.size)
        )
    }

    private func updateMirror(noteID: Int64, file: VaultFile, in vault: Vault) {
        guard var note = store.note(id: noteID),
              let text = VaultScanner.text(at: file.path, in: vault)
        else { return }

        let attributed = ObsidianMarkdown.attributed(from: ObsidianMarkdown.readableBody(of: text))
        note.title = file.title
        note.rtf = Self.rtf(of: attributed)
        note.plain = attributed.string
        note.updatedAt = file.modified
        store.update(note)
        bookmarks.put(
            mirror: MirrorBookmark(noteID: noteID, path: file.path, modified: file.modified, size: file.size)
        )
    }

    // MARK: - Закладки

    /// Кладёт закладку по только что записанному тексту.
    ///
    /// Отпечаток берётся от текста, а не перечитыванием файла: перечитывание
    /// поймало бы уже чужую правку, если она случилась в этот самый миг,
    /// и следующая сверка сочла бы её нашей.
    private func remember(noteID: Int64, uid: String, path: String, text: String, in vault: Vault) {
        let values = try? vault.fileURL(for: path).resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        bookmarks.put(
            own: OwnBookmark(
                noteID: noteID,
                uid: uid,
                path: path,
                hash: VaultFile.hash(of: text),
                syncedAt: Date()
            ),
            modified: values?.contentModificationDate ?? Date(),
            size: values?.fileSize ?? text.utf8.count
        )
    }

    // MARK: - Связи в файле

    /// Пишет блок связей в файл заметки.
    ///
    /// Переписывается **только** то, что стоит между метками: остальной
    /// текст файла человек писал сам, и наша запись не имеет права его
    /// касаться. Пустой список снимает блок целиком.
    func writeLinks(_ rows: [String], forNote id: Int64) {
        guard settings.obsidianEnabled, let vault, let path = path(ofNote: id) else { return }
        queue.async { [weak self] in
            guard let self, let text = VaultScanner.text(at: path, in: vault) else { return }
            let updated = ObsidianMarkdown.settingLinks(ObsidianMarkdown.linksBlock(lines: rows), in: text)
            guard updated != text, VaultScanner.write(updated, to: path, in: vault) else { return }
            // Закладка обновляется тут же: без неё следующая сверка приняла бы
            // собственную запись за чужую правку.
            if let bookmark = bookmarks.own().first(where: { $0.noteID == id }) {
                remember(noteID: id, uid: bookmark.uid, path: path, text: updated, in: vault)
            }
        }
    }

    /// Снимает блоки связей со всех файлов, где они есть.
    ///
    /// Это кнопка отмены: человек попробовал связи, они ему не нужны,
    /// и хранилище должно вернуться к прежнему виду без следов.
    func removeAllLinkBlocks() {
        guard let vault else { return }
        queue.async {
            var cleaned = 0
            for file in VaultScanner.files(in: vault) {
                guard let text = VaultScanner.text(at: file.path, in: vault),
                      ObsidianMarkdown.linksBlock(in: text) != nil
                else { continue }
                let stripped = ObsidianMarkdown.settingLinks(nil, in: text)
                if VaultScanner.write(stripped + "\n", to: file.path, in: vault) { cleaned += 1 }
            }
            DebugLog.write("Obsidian: блоки связей сняты с \(cleaned) файлов")
        }
    }

    // MARK: - Мелочи

    /// Имя заметки — имя файла без расширения.
    static func title(ofPath path: String) -> String {
        (path as NSString).lastPathComponent.replacingOccurrences(
            of: ".md",
            with: "",
            options: [.caseInsensitive, .anchored, .backwards]
        )
    }

    private static func rtf(of text: NSAttributedString) -> Data {
        text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:]) ?? Data()
    }

    /// Двоеточие в имя файла не годится — в macOS оно разделитель пути
    /// в старом смысле, и Finder показал бы его косой чертой.
    private static func conflictStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        return formatter.string(from: date)
    }
}
