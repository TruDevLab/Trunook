import Foundation
import TrunookXPC

/// Отбор заметок под вопрос — по смыслу, а не по свежести.
///
/// «Найти в заметках» раньше грузило модели всё подряд, свежее первым, пока
/// не упрётся потолок в символах. У полусотни заметок это работало; у тысячи
/// перестаёт: нужная запись годичной давности не попадала в контекст никогда,
/// сколько бы точно её ни спрашивали, — её вытесняли вчерашние списки покупок.
///
/// Теперь вопрос превращается в вектор и сравнивается с векторами заметок.
/// В контекст уходит десяток подходящих вместо сотни случайных: и ответ
/// точнее, и модели думать меньше.
///
/// **Запасной путь остаётся.** Векторов может не быть вовсе — Ollama
/// выключена, модель ещё не скачана, заметки только что записаны и посчитать
/// их не успели. Тогда работает прежний отбор по свежести: хуже, чем
/// по смыслу, но лучше, чем отказ отвечать.
final class NotesRetriever {
    private let store: NotesStore
    private let vectors: LinksStore
    private let client: ModelClient
    private let settings: Settings

    /// Ниже этой близости заметка к вопросу отношения не имеет.
    ///
    /// Порог низкий нарочно: это отбор, а не утверждение о связи. Вопрос
    /// и ответ на него написаны разными словами почти всегда, и строгий
    /// порог оставил бы человека без ответа там, где нужное в заметках есть.
    static let floor = 0.25

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

    var model: ModelRef? {
        ModelRef.parse(settings.embedModel, fallback: settings.aiProvider)
    }

    /// Готов ли векторный отбор: включён, есть чем считать и есть с чем
    /// сравнивать.
    var isAvailable: Bool {
        guard settings.notesVectorSearch, settings.ollamaEnabled, let model else { return false }
        return !vectors.vectors(model: model.stored).isEmpty
    }

    /// Заметки под вопрос, собранные в текст для модели.
    ///
    /// Ответ приходит замыканием, а не возвратом: вектор вопроса считает
    /// модель, а это сеть. Раньше сборка контекста была мгновенной, и все
    /// места, откуда её зовут, ждали ответа тут же.
    func context(
        for question: String,
        budget: Int? = nil,
        completion: @escaping (String?) -> Void
    ) {
        let limit = budget ?? settings.notesContextLimit
        guard isAvailable, let model else {
            completion(fallback(limit))
            return
        }

        client.embed(question, model: model) { [weak self] vector in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let vector, !vector.isEmpty else {
                    DebugLog.write("заметки: вектор вопроса не посчитался, беру свежие")
                    completion(fallback(limit))
                    return
                }
                completion(byMeaning(vector, limit: limit))
            }
        }
    }

    private func byMeaning(_ vector: [Float], limit: Int) -> String? {
        let picked = Self.nearest(
            to: vector,
            among: vectors.vectors(model: model?.stored ?? ""),
            count: settings.notesVectorCount,
            floor: Self.floor
        )
        let notes = picked.compactMap { store.note(id: $0) }
        guard !notes.isEmpty else {
            // Ни одна заметка к вопросу не подошла. Свежие вместо них — это
            // подмена ответа: человек спросил про одно, а модель получила
            // другое и ответит уверенно и мимо.
            DebugLog.write("заметки: по смыслу ничего не нашлось")
            return nil
        }
        DebugLog.write("заметки: по смыслу отобрано \(notes.count)")
        return NotesService.context(from: notes, budget: limit)
    }

    private func fallback(_ limit: Int) -> String? {
        NotesService.context(from: store.all(), budget: limit)
    }

    /// Ближайшие к вектору вопроса.
    ///
    /// Порядок сохраняется — от близких к далёким: модель читает контекст
    /// сверху вниз и первым строкам верит охотнее.
    static func nearest(
        to vector: [Float],
        among others: [(noteID: Int64, vector: [Float])],
        count: Int,
        floor: Double
    ) -> [Int64] {
        others
            .map { (id: $0.noteID, score: Embedding.similarity(vector, $0.vector)) }
            .filter { $0.score >= floor }
            .sorted { $0.score > $1.score }
            .prefix(count)
            .map(\.id)
    }
}
