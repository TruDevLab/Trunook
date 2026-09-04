import Foundation
import TrunookXPC

/// Смысловые связи между заметками.
///
/// Два шага, и оба нужны.
///
/// **Векторы** отвечают на «о том же ли». Совпадение слов на это не отвечает:
/// «раскрытие панели по наведению» и «жест на чёлке» — об одном, а общих слов
/// нет ни одного. Вектор считается один раз на заметку и только при её правке;
/// дальше близкое находится умножением, без единого обращения к модели.
///
/// **Модель** отвечает на «связаны ли и чем». Близость — ещё не связь: две
/// заметки про кофе близки, даже когда одна про зерно, а другая про то, что
/// экран не гаснет. Поэтому кандидатов, отобранных векторами, показывают
/// модели, и в файл уходит только то, что она подтвердила, — с фразой,
/// объясняющей связь.
///
/// Устройство очереди — как у `NoteTitler`: строго по одному запросу.
/// Локальная модель на параллельных пересчитывает контекст заново
/// и отвечает медленнее, чем на тех же запросах по очереди.
final class NoteLinker {
    /// Связи заметки обновились — панели пора перерисоваться.
    var onLinks: ((Int64) -> Void)?

    /// Куда писать блок связей в хранилище. Ставится службой Obsidian;
    /// без неё связи живут только внутри приложения.
    var writeToVault: ((Int64, [(title: String, reason: String)]) -> Void)?

    private let store: NotesStore
    private let vectors: LinksStore
    private let client: ModelClient
    private let settings: Settings

    private var pending: [Int64] = []
    private var isBusy = false

    /// Сколько связей держать у одной заметки.
    ///
    /// Десяток «связанных» — это не связи, а шум: человек перестаёт их
    /// читать целиком, и список теряет смысл.
    static let maxLinks = 4

    /// Сколько кандидатов показывать модели. Больше — длиннее промт
    /// и дольше ответ, а хвост списка всё равно почти никогда не проходит.
    static let maxCandidates = 8

    init(
        store: NotesStore = NotesStore(),
        vectors: LinksStore = LinksStore(),
        client: ModelClient = ModelClient(),
        settings: Settings = .shared
    ) {
        self.store = store
        self.vectors = vectors
        self.client = client
        self.settings = settings
    }

    /// Считать ли векторы вообще.
    ///
    /// Шире, чем связи: на тех же векторах теперь работает и поиск
    /// по заметкам. Включено любое из двух — считаем.
    var computesVectors: Bool {
        settings.ollamaEnabled && (settings.notesVectorSearch || settings.obsidianLinksEnabled)
    }

    /// Искать ли связи — второй шаг, отдельный от векторов.
    ///
    /// Он дороже: на каждую заметку уходит запрос к чат-модели, а не только
    /// к маленькой векторной. Человек может хотеть векторный поиск и не хотеть
    /// связей, и наоборот.
    var isAvailable: Bool {
        settings.obsidianLinksEnabled && settings.ollamaEnabled
    }

    var model: ModelRef? {
        ModelRef.parse(settings.embedModel, fallback: settings.aiProvider)
    }

    private var threshold: Double { Double(settings.obsidianLinkThreshold) / 100 }

    // MARK: - Очередь

    /// Ставит заметку в очередь на пересчёт.
    func enqueue(id: Int64) {
        guard computesVectors, !pending.contains(id) else { return }
        pending.append(id)
        runNext()
    }

    /// Пересчитывает всё, у чего разошёлся отпечаток.
    ///
    /// Заметок бывают тысячи, но вектор считается только у изменившихся:
    /// у остальных отпечаток текста тот же, что и был.
    func refreshAll() {
        guard computesVectors, let model else { return }
        let stale = store.all().filter { note in
            vectors.hash(noteID: note.id, model: model.stored) != Self.hash(of: note)
        }
        for note in stale { enqueue(id: note.id) }
        DebugLog.write("связи: в очереди \(stale.count) заметок")
    }

    func links(of noteID: Int64) -> [NoteLink] { vectors.links(from: noteID) }

    func forget(noteID: Int64) { vectors.forget(noteID: noteID) }

    /// Выключенное всё не оставляет за собой ничего.
    func clearAll() {
        pending.removeAll()
        vectors.clearAll()
    }

    /// Связи выключили, а векторы остались нужны поиску: убираем только связи.
    func clearLinks() {
        for note in store.all() { vectors.replace(from: note.id, with: []) }
    }

    private func runNext() {
        guard !isBusy, computesVectors, let model, let id = pending.first else { return }
        pending.removeFirst()
        guard let note = store.note(id: id) else {
            runNext()
            return
        }
        isBusy = true

        client.embed(Embedding.text(for: note), model: model) { [weak self] vector in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let vector, !vector.isEmpty {
                    vectors.put(
                        noteID: id,
                        model: model.stored,
                        hash: Self.hash(of: note),
                        vector: vector
                    )
                    // Связи — отдельный шаг и отдельное согласие: вектор
                    // нужен и поиску по заметкам, а запрос к чат-модели
                    // ради связей — уже нет. Старые заметки к тому же можно
                    // не трогать вовсе: у большого архива первый проход
                    // это часы работы модели.
                    if isAvailable, Self.shouldLink(
                        note.createdAt,
                        onlyNew: settings.linksOnlyNew,
                        since: settings.linksSince
                    ) {
                        decide(for: note, vector: vector, model: model)
                    }
                }
                isBusy = false
                runNext()
            }
        }
    }

    // MARK: - Отбор и подтверждение

    private func decide(for note: Note, vector: [Float], model: ModelRef) {
        let picked = Self.candidates(
            for: vector,
            among: vectors.vectors(model: model.stored),
            excluding: note.id,
            threshold: threshold,
            limit: Self.maxCandidates
        )
        guard !picked.isEmpty else {
            vectors.replace(from: note.id, with: [])
            onLinks?(note.id)
            return
        }

        let others = picked.compactMap { pick in store.note(id: pick.id).map { ($0, pick.score) } }
        guard !others.isEmpty else { return }

        client.generate(prompt: Self.prompt(for: note, candidates: others.map(\.0))) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let answer = (try? result.get()) ?? ""

                var found: [NoteLink] = []
                for (index, reason) in Self.parse(answer, count: others.count) where index < others.count {
                    let (other, score) = others[index]
                    found.append(NoteLink(toID: other.id, score: score, reason: reason))
                }
                let kept = Array(found.prefix(Self.maxLinks))
                vectors.replace(from: note.id, with: kept)
                onLinks?(note.id)

                guard settings.obsidianLinksToFiles else { return }
                writeToVault?(
                    note.id,
                    kept.compactMap { [store] link in
                        store.note(id: link.toID).map { (title: $0.title, reason: link.reason) }
                    }
                )
            }
        }
    }

    // MARK: - Чистое

    /// Стоит ли искать связи у этой заметки.
    ///
    /// Граница ставится в тот миг, когда связи включили: всё, что человек
    /// записал после, — новое. Пустая граница значит «связывать все»: так
    /// работает кнопка «Связать и старые».
    static func shouldLink(_ createdAt: Date, onlyNew: Bool, since: Date?) -> Bool {
        guard onlyNew, let since else { return true }
        return createdAt >= since
    }

    /// Отпечаток текста, по которому считали вектор.
    static func hash(of note: Note) -> String {
        VaultFile.hash(of: Embedding.text(for: note))
    }

    /// Ближайшие по смыслу, кроме самой заметки.
    ///
    /// Порог человек ставит сам: у одного хранилище про одно и то же, и всё
    /// связано со всем; у другого заметки разрозненные, и связи находятся
    /// с трудом. Одного правильного числа тут нет.
    static func candidates(
        for vector: [Float],
        among others: [(noteID: Int64, vector: [Float])],
        excluding id: Int64,
        threshold: Double,
        limit: Int
    ) -> [(id: Int64, score: Double)] {
        others
            .filter { $0.noteID != id }
            .map { (id: $0.noteID, score: Embedding.similarity(vector, $0.vector)) }
            .filter { $0.score >= threshold }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    /// Промт подтверждения.
    ///
    /// Ответа в JSON у модели не просим — в этом проекте так не делают нигде,
    /// и локальные модели на строгом формате срываются чаще, чем попадают.
    /// Просим строки «номер — фраза» и чистим ответ разбором.
    static func prompt(for note: Note, candidates: [Note]) -> String {
        let list = candidates.enumerated().map { index, other in
            "\(index + 1). \(other.title)\n\(String(other.plain.prefix(400)))"
        }.joined(separator: "\n\n")

        return """
            \(t("Заметка:"))
            \(note.title)
            \(String(note.plain.prefix(800)))

            \(t("Возможно связанные заметки:"))
            \(list)

            \(t("Какие из них связаны с первой по смыслу? Ответь строками «номер — чем связаны», одной короткой фразой на строку. Несвязанные не упоминай."))
            """
    }

    /// Разбор ответа модели.
    ///
    /// Модель отвечает как умеет: то с точкой после номера, то со скобкой,
    /// то с вводной строкой перед списком. Берём только строки, начинающиеся
    /// с числа в пределах списка, — всё прочее это разговоры, а не ответ.
    static func parse(_ answer: String, count: Int) -> [(index: Int, reason: String)] {
        var result: [(index: Int, reason: String)] = []
        var seen = Set<Int>()

        for line in ObsidianMarkdown.lines(of: answer) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-*• "))
            let digits = trimmed.prefix { $0.isNumber }
            guard !digits.isEmpty, let number = Int(digits), number >= 1, number <= count else { continue }
            guard !seen.contains(number) else { continue }
            seen.insert(number)

            let reason = trimmed
                .dropFirst(digits.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".):—- \t"))
            result.append((number - 1, reason))
        }
        return result
    }

    /// Строки блока связей для файла хранилища.
    static func vaultLines(_ links: [(title: String, reason: String)]) -> [String] {
        links.map { link in
            link.reason.isEmpty ? "- [[\(link.title)]]" : "- [[\(link.title)]] — \(link.reason)"
        }
    }
}
