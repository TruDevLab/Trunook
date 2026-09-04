import TrunookXPC
import AppKit
import Foundation

/// Заметки: список, правка, поиск и сбор их в контекст модели.
///
/// Связывает три части, у каждой из которых своя забота: `NotesStore` знает
/// только SQL, `NoteTitler` — только имена, `NoteMarkdown` — только выгрузку.
/// Здесь они сходятся, и здесь же живёт наблюдаемый список для вёрстки.
final class NotesService: ObservableObject {
    /// То, что показывает список: с учётом строки поиска.
    @Published private(set) var notes: [Note] = []

    /// Строка поиска. Живёт здесь, а не в панели: `@State` в этом тулчейне
    /// недоступен, а список обязан пережить закрытие панели — человек ищет,
    /// отвлекается и возвращается.
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }

    /// Сколько заметок всего, без оглядки на поиск. Нужно, чтобы отличить
    /// «заметок нет вовсе» от «поиск ничего не нашёл»: это разные слова.
    @Published private(set) var total = 0

    private let store: NotesStore
    private let titler: NoteTitler
    private let settings: Settings

    private var pendingSearch: DispatchWorkItem?
    private let searchQueue = DispatchQueue(label: "com.trunook.notes.search")
    private static let searchDelay: TimeInterval = 0.15

    init(
        store: NotesStore = NotesStore(),
        titler: NoteTitler = NoteTitler(),
        settings: Settings = .shared
    ) {
        self.store = store
        self.titler = titler
        self.settings = settings

        titler.onTitle = { [weak self] id, title in
            self?.apply(title: title, to: id, byModel: true)
        }
    }

    func start() {
        reload()
        DebugLog.write("заметки: загружено \(total)")
    }

    private func reload() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Пустая строка поиска — только свои заметки. Хранилище Obsidian
        // бывает на тысячи файлов, и своя дюжина утонула бы в нём бесследно;
        // чужие всплывают, когда человек что-то ищет.
        notes = trimmed.isEmpty ? store.all(source: .own) : store.search(trimmed)
        total = store.count(source: .own)
    }

    /// Поиск с задержкой и не на главном потоке.
    ///
    /// Раньше `LIKE` по всей базе выполнялся прямо в главном потоке
    /// на каждое нажатие клавиши. Со своей сотней заметок это незаметно,
    /// а с хранилищем Obsidian в базе оказываются тысячи строк, и ввод
    /// начинает заикаться. Задержка гасит промежуточные наборы: пока человек
    /// печатает «вырез», незачем искать «в», «вы», «выр».
    private func scheduleSearch() {
        pendingSearch?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.searchInBackground() }
        pendingSearch = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.searchDelay, execute: work)
    }

    private func searchInBackground() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchQueue.async { [weak self] in
            guard let self else { return }
            let list = trimmed.isEmpty ? store.all(source: .own) : store.search(trimmed)
            let count = store.count(source: .own)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // За время запроса строку могли дописать — тогда ответ уже
                // не о том, и своё придёт следующим заходом.
                guard trimmed == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                notes = list
                total = count
            }
        }
    }

    /// Заметку записали или изменили. По этому поводу пересчитывают
    /// её вектор смысла и связи — но только если их вообще ищут.
    var onSaved: ((Int64) -> Void)?

    /// Перечитать список. Зовут снаружи — например, когда синхронизация
    /// с Obsidian привезла правки из хранилища.
    func refresh() { reload() }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func note(id: Int64) -> Note? { store.note(id: id) }

    // MARK: - Запись

    /// Кладёт заметку или переписывает существующую.
    ///
    /// Возвращает записанное — с назначенным идентификатором и поставленным
    /// именем, — чтобы вызвавший мог показать человеку, что именно вышло.
    /// `nil` значит, что записывать было нечего.
    @discardableResult
    func save(
        _ text: NSAttributedString,
        origin: Note.Origin,
        editing id: Int64? = nil,
        now: Date = Date()
    ) -> Note? {
        let plain = text.string
        guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let all = NSRange(location: 0, length: text.length)
        guard let rtf = text.rtf(from: all, documentAttributes: [:]) else {
            DebugLog.write("заметки: текст не собрался в RTF")
            return nil
        }

        if let id, let existing = store.note(id: id) {
            // Имя у правки не переставляем на новое время: заметку узнают
            // по имени, и меняющееся при каждой правке имя — это чужая
            // заметка в списке.
            var updated = existing
            updated.rtf = rtf
            updated.plain = plain
            updated.updatedAt = now
            store.update(updated)
            reload()
            DebugLog.write("заметки: правка \(id), символов \(plain.count)")
            // Имя, поставленное запасным расчётом, ещё имеет смысл заменить
            // на настоящее: текст изменился, а имя было временным.
            if !updated.titleByModel { titler.enqueue(id: id, plain: plain) }
            onSaved?(id)
            return updated
        }

        let note = Note(
            id: Note.unsaved,
            title: NoteTitler.fallback(for: plain, at: now),
            rtf: rtf,
            plain: plain,
            createdAt: now,
            updatedAt: now,
            origin: origin,
            titleByModel: false
        )
        guard let id = store.insert(note) else { return nil }
        reload()
        DebugLog.write("заметки: записана \(id), символов \(plain.count), откуда \(origin.rawValue)")

        titler.enqueue(id: id, plain: plain)
        onSaved?(id)

        var saved = note
        saved.id = id
        return saved
    }

    /// Просит модель придумать имя заново — кнопкой в списке.
    func rename(_ note: Note) {
        titler.enqueue(id: note.id, plain: note.plain)
    }

    private func apply(title: String, to id: Int64, byModel: Bool) {
        guard let note = store.note(id: id) else { return }
        store.rename(id: id, title: title, plain: note.plain, byModel: byModel)
        reload()
    }

    // MARK: - Удаление

    func delete(_ note: Note) {
        store.delete(id: note.id)
        reload()
        DebugLog.write("заметки: удалена \(note.id)")
    }

    func clearAll() {
        titler.cancelAll()
        store.deleteAll()
        query = ""
        reload()
    }

    // MARK: - Контекст для модели

    /// Заметки, собранные в текст для модели.
    ///
    /// Свежие идут первыми и целиком, пока не упрётся потолок. Что не влезло,
    /// названо вслух отдельной строкой: неполный ответ, о неполноте которого
    /// не сказано, читается как неверный, и человек винит модель вместо того,
    /// чтобы сузить вопрос.
    ///
    /// Потолок в символах, а не в токенах: токены не сосчитать без самой
    /// модели, и у каждой они свои.
    func contextText(budget: Int? = nil) -> String? {
        let limit = budget ?? settings.notesContextLimit
        return Self.context(from: store.all(), budget: limit)
    }

    /// Сборка контекста из готового набора заметок.
    ///
    /// Отдельно от выборки, потому что выбирать их можно двумя способами:
    /// по свежести (как было) и по смыслу вопроса (векторами). Формат
    /// при этом обязан остаться одним: разойдись он, и ответы модели
    /// на один и тот же вопрос отличались бы от того, каким путём собрали
    /// заметки, — а это уже не поиск, а лотерея.
    static func context(from all: [Note], budget: Int) -> String? {
        let limit = budget
        guard !all.isEmpty else { return nil }

        var blocks: [String] = []
        var used = 0
        var included = 0

        for note in all {
            let block = block(for: note, number: included + 1)
            // Первая заметка кладётся всегда, даже если одна не влезает
            // в потолок целиком: пустой контекст хуже урезанного.
            if used + block.count > limit, included > 0 { break }
            if used + block.count > limit {
                let room = max(200, limit - used)
                blocks.append(String(block.prefix(room)) + "\n…")
                included += 1
                used = limit
                break
            }
            blocks.append(block)
            used += block.count
            included += 1
        }

        var text = preamble + "\n\n" + blocks.joined(separator: "\n\n")
        if included < all.count {
            let oldest = all[included - 1].updatedAt
            let note = tf("(показаны %d из %d заметок — самые свежие; остальные старше %@)", included, all.count, shortStamp(oldest))
            text += "\n\n" + note
        }
        return text
    }

    static var preamble: String {
        t("Ниже заметки пользователя, свежие первыми. Отвечай на вопрос только по ним. Если ответа в заметках нет, так и скажи — не придумывай.")
    }

    static func block(for note: Note, number: Int) -> String {
        """
        --- \(number). \(note.title) (\(shortStamp(note.updatedAt))) ---
        \(note.plain)
        """
    }

    static func shortStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Localization.shared.resolved.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return formatter.string(from: date)
    }

    // MARK: - Выгрузка

    /// Выгружает все заметки в папку. Возвращает, сколько легло и сколько нет.
    @discardableResult
    func exportAll(to folder: URL) -> (written: Int, failed: Int) {
        var written = 0
        var failed = 0
        var used = Set<String>()

        for note in store.all() {
            let base = NoteMarkdown.fileName(for: note)
            var name = base
            // Две заметки одной минуты с одинаковым именем затёрли бы друг
            // друга — и человек увидел бы, что выгрузилось меньше, чем было.
            var attempt = 2
            while used.contains(name) {
                name = base.replacingOccurrences(of: ".md", with: "-\(attempt).md")
                attempt += 1
            }
            used.insert(name)

            if write(note, to: folder.appendingPathComponent(name)) {
                written += 1
            } else {
                failed += 1
            }
        }
        DebugLog.write("заметки: выгружено \(written), не вышло \(failed)")
        return (written, failed)
    }

    @discardableResult
    func export(_ note: Note, to url: URL) -> Bool {
        let ok = write(note, to: url)
        DebugLog.write("заметки: заметка \(note.id) выгружена — \(ok)")
        return ok
    }

    private func write(_ note: Note, to url: URL) -> Bool {
        do {
            try NoteMarkdown.document(for: note).write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            // Промолчать нельзя: человек считает, что заметка выгружена.
            DebugLog.write("заметки: не записать \(url.lastPathComponent) — \(error.localizedDescription)")
            return false
        }
    }
}
