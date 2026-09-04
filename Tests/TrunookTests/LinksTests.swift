import AppKit
import Foundation
import Testing
@testable import Trunook

/// Векторы смысла: упаковка, близость, текст для модели.
@Suite("Векторы смысла")
struct EmbeddingTests {
    @Test("Вектор переживает упаковку в хранилище")
    func упаковкаИРаспаковка() {
        let vector: [Float] = [0.5, -0.25, 1_000.125, 0]
        #expect(Embedding.vector(from: Embedding.data(from: vector)) == vector)
    }

    @Test("Пустой вектор упаковывается в ничто и обратно")
    func пустойВектор() {
        #expect(Embedding.data(from: []).isEmpty)
        #expect(Embedding.vector(from: Data()).isEmpty)
    }

    @Test("Одинаковые векторы близки, противоположные — нет")
    func близость() {
        let one: [Float] = [1, 0, 0]
        #expect(abs(Embedding.similarity(one, one) - 1) < 0.0001)
        #expect(abs(Embedding.similarity(one, [0, 1, 0])) < 0.0001)
        #expect(Embedding.similarity(one, [-1, 0, 0]) < 0)
    }

    /// Длина вектора зависит от длины текста. Считай мы расстояние, короткая
    /// заметка оказывалась бы далека от длинной, даже когда обе про одно.
    @Test("Длина текста близости не мешает")
    func длинаНеМешает() {
        let short: [Float] = [1, 2, 3]
        let long: [Float] = [10, 20, 30]
        #expect(abs(Embedding.similarity(short, long) - 1) < 0.0001)
    }

    /// Векторы разной длины — это ответы разных моделей. Сравнивать их
    /// бессмысленно, и честный ноль лучше подгонки.
    @Test("Векторы разных моделей не сравниваются")
    func разныеМодели() {
        #expect(Embedding.similarity([1, 0], [1, 0, 0]) == 0)
    }

    @Test("Нулевой вектор ни с чем не близок")
    func нулевойВектор() {
        #expect(Embedding.similarity([0, 0, 0], [1, 2, 3]) == 0)
    }

    /// Хвост длинной заметки размывает вектор, притягивая её ко всему подряд.
    @Test("Имя идёт целиком, тело обрезается")
    func текстДляВектора() {
        let note = Note(
            id: 1, title: "Идея про вырез",
            rtf: Data(), plain: String(repeating: "а", count: 5_000),
            createdAt: Date(), updatedAt: Date(), origin: .typed, titleByModel: false
        )
        let text = Embedding.text(for: note)
        #expect(text.hasPrefix("Идея про вырез\n"))
        #expect(text.count <= Embedding.textLimit + 20)
    }
}

/// Ответ модели эмбеддингов у обоих диалектов.
@Suite("Ответ с вектором")
struct EmbedResponseTests {
    @Test("Ollama кладёт вектор в embeddings")
    func диалектOllama() throws {
        let data = Data(#"{"embeddings":[[0.5,-0.25,0.75]]}"#.utf8)
        let vector = try #require(ModelClient.vector(in: data, dialect: .ollama))
        #expect(vector == [0.5, -0.25, 0.75])
    }

    @Test("OpenAI кладёт вектор в data[0].embedding")
    func диалектOpenAI() throws {
        let data = Data(#"{"data":[{"embedding":[1,2,3]}]}"#.utf8)
        let vector = try #require(ModelClient.vector(in: data, dialect: .openAI))
        #expect(vector == [1, 2, 3])
    }

    @Test("Чужой ответ вектором не притворяется")
    func чужойОтвет() {
        #expect(ModelClient.vector(in: Data("{\"error\":\"нет модели\"}".utf8), dialect: .ollama) == nil)
        #expect(ModelClient.vector(in: Data("не json".utf8), dialect: .openAI) == nil)
        #expect(ModelClient.vector(in: Data(#"{"embeddings":[[]]}"#.utf8), dialect: .ollama) == nil)
    }
}

/// Отбор кандидатов и разбор ответа модели.
@Suite("Связи между заметками")
struct NoteLinkerTests {
    private let vectors: [(noteID: Int64, vector: [Float])] = [
        (1, [1, 0, 0]),
        (2, [0.9, 0.1, 0]),
        (3, [0, 1, 0]),
        (4, [0.7, 0.7, 0])
    ]

    @Test("Кандидаты идут от близких к далёким и не включают саму заметку")
    func отборКандидатов() {
        let picked = NoteLinker.candidates(
            for: [1, 0, 0], among: vectors, excluding: 1, threshold: 0.5, limit: 10
        )
        #expect(picked.map(\.id) == [2, 4])
        #expect(picked.first!.score > picked.last!.score)
    }

    @Test("Порог отсекает далёкое")
    func порогОтсекает() {
        let picked = NoteLinker.candidates(
            for: [1, 0, 0], among: vectors, excluding: 1, threshold: 0.95, limit: 10
        )
        #expect(picked.map(\.id) == [2])
    }

    @Test("Потолок кандидатов соблюдается")
    func потолокКандидатов() {
        let picked = NoteLinker.candidates(
            for: [1, 0, 0], among: vectors, excluding: 1, threshold: 0, limit: 2
        )
        #expect(picked.count == 2)
    }

    // MARK: - Разбор ответа

    @Test("Номер и причина вынимаются из строки")
    func разборОтвета() {
        let answer = "1 — обе про раскрытие панели\n3. там первая проба жеста"
        let parsed = NoteLinker.parse(answer, count: 3)
        #expect(parsed.map(\.index) == [0, 2])
        #expect(parsed.first?.reason == "обе про раскрытие панели")
        #expect(parsed.last?.reason == "там первая проба жеста")
    }

    /// Модель охотно предваряет список вводной фразой. Это разговоры,
    /// а не ответ.
    @Test("Вводные слова в связи не превращаются")
    func вводныеСловаОтбрасываются() {
        let answer = "Вот что связано:\n\n2) про то же самое\nБольше ничего не нашёл."
        let parsed = NoteLinker.parse(answer, count: 3)
        #expect(parsed.map(\.index) == [1])
    }

    @Test("Номер вне списка не принимается")
    func номерВнеСписка() {
        #expect(NoteLinker.parse("7 — придумано", count: 3).isEmpty)
        #expect(NoteLinker.parse("0 — тоже придумано", count: 3).isEmpty)
    }

    @Test("Повтор номера не удваивает связь")
    func повторНомера() {
        let parsed = NoteLinker.parse("1 — раз\n1 — два", count: 2)
        #expect(parsed.count == 1)
    }

    @Test("Отказ модели связей не даёт")
    func отказМодели() {
        #expect(NoteLinker.parse("нет", count: 3).isEmpty)
        #expect(NoteLinker.parse("", count: 3).isEmpty)
    }

    @Test("Связь без причины остаётся связью")
    func связьБезПричины() throws {
        let parsed = NoteLinker.parse("2", count: 3)
        #expect(parsed.count == 1)
        #expect(parsed.first?.reason == "")
    }

    // MARK: - Блок для файла

    @Test("Строки блока — настоящие ссылки Obsidian")
    func строкиБлока() {
        let rows = NoteLinker.vaultLines([
            (title: "Проекты/Роадмап", reason: "обе про раскрытие панели"),
            (title: "Стекло", reason: "")
        ])
        #expect(rows == ["- [[Проекты/Роадмап]] — обе про раскрытие панели", "- [[Стекло]]"])
    }
}

/// Хранилище векторов и связей.
@Suite("Хранилище связей")
struct LinksStoreTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("trunook-links-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    @Test("Вектор ложится и читается тем же")
    func векторВХранилище() throws {
        let store = LinksStore(url: temporaryURL())
        store.put(noteID: 1, model: "ollama|nomic", hash: "отпечаток", vector: [0.5, 0.25])

        let back = try #require(store.vectors(model: "ollama|nomic").first)
        #expect(back.noteID == 1)
        #expect(back.vector == [0.5, 0.25])
        #expect(store.hash(noteID: 1, model: "ollama|nomic") == "отпечаток")
    }

    /// У разных моделей векторы разной длины и разного смысла. Смена модели
    /// обязана оставлять прежние векторы за бортом, а не путать их с новыми.
    @Test("Векторы чужой модели не подмешиваются")
    func чужаяМодель() {
        let store = LinksStore(url: temporaryURL())
        store.put(noteID: 1, model: "ollama|nomic", hash: "х", vector: [1, 0])
        #expect(store.vectors(model: "openAI|text-embedding-3").isEmpty)
        #expect(store.hash(noteID: 1, model: "openAI|text-embedding-3") == nil)
    }

    /// Заметку правят, смысл её меняется — прежние связи становятся неверными.
    @Test("Новые связи заменяют прежние, а не копятся")
    func связиЗаменяются() {
        let store = LinksStore(url: temporaryURL())
        store.replace(from: 1, with: [NoteLink(toID: 2, score: 0.9, reason: "раз")])
        store.replace(from: 1, with: [NoteLink(toID: 3, score: 0.8, reason: "два")])

        #expect(store.links(from: 1).map(\.toID) == [3])
    }

    @Test("Связи выдаются от близких к далёким")
    func порядокСвязей() {
        let store = LinksStore(url: temporaryURL())
        store.replace(from: 1, with: [
            NoteLink(toID: 2, score: 0.7, reason: "дальше"),
            NoteLink(toID: 3, score: 0.95, reason: "ближе")
        ])
        #expect(store.links(from: 1).map(\.toID) == [3, 2])
    }

    @Test("Забытая заметка уходит и из связей в обратную сторону")
    func забытаяЗаметка() {
        let store = LinksStore(url: temporaryURL())
        store.put(noteID: 2, model: "м", hash: "х", vector: [1])
        store.replace(from: 1, with: [NoteLink(toID: 2, score: 0.9, reason: "")])
        store.replace(from: 2, with: [NoteLink(toID: 1, score: 0.9, reason: "")])

        store.forget(noteID: 2)
        #expect(store.links(from: 1).isEmpty, "связь на удалённую заметку висеть не должна")
        #expect(store.links(from: 2).isEmpty)
        #expect(store.vectors(model: "м").isEmpty)
    }

    /// Так выглядит выключенный поиск связей: ни векторов, ни связей.
    @Test("Очистка не оставляет следов")
    func очистка() {
        let store = LinksStore(url: temporaryURL())
        store.put(noteID: 1, model: "м", hash: "х", vector: [1])
        store.replace(from: 1, with: [NoteLink(toID: 2, score: 0.9, reason: "")])

        store.clearAll()
        #expect(store.vectors(model: "м").isEmpty)
        #expect(store.links(from: 1).isEmpty)
    }
}

/// Скачивание модели и рекомендованные имена.
@Suite("Установка модели")
struct ModelInstallTests {
    @Test("Доля скачанного вынимается из строки ответа")
    func доляСкачанного() {
        let line = #"{"status":"pulling","completed":512,"total":1024}"#
        #expect(ModelClient.pullProgress(in: line) == 0.5)
    }

    /// У Ollama больше половины строк без чисел вовсе: «pulling manifest»,
    /// «verifying sha256», «success».
    @Test("Строка без чисел долей не притворяется")
    func строкаБезЧисел() {
        #expect(ModelClient.pullProgress(in: #"{"status":"verifying sha256"}"# ) == nil)
        #expect(ModelClient.pullProgress(in: "не json") == nil)
        #expect(ModelClient.pullProgress(in: #"{"completed":10,"total":0}"#) == nil)
    }

    /// Ollama отвечает об отказе полем в теле, а код ответа при этом
    /// остаётся успешным: поток уже начался, когда выяснилось, что модели
    /// с таким именем нет.
    @Test("Отказ виден в теле ответа, а не в коде")
    func отказВТеле() {
        #expect(ModelClient.pullError(in: #"{"error":"model not found"}"#) == "model not found")
        #expect(ModelClient.pullError(in: #"{"status":"success"}"#) == nil)
    }

    /// Ollama зовёт скачанное `nomic-embed-text:latest`, а просят её обычно
    /// без метки. Точное сравнение отвечало бы «нет» на установленную модель.
    @Test("Метка версии установленную модель не прячет")
    func меткаВерсииНеМешает() {
        let installed = [
            ModelRef(provider: .ollama, name: "nomic-embed-text:latest"),
            ModelRef(provider: .ollama, name: "gemma4:12b")
        ]
        #expect(RecommendedModel.isInstalled("nomic-embed-text", among: installed))
        #expect(RecommendedModel.isInstalled("gemma4:12b", among: installed))
        #expect(!RecommendedModel.isInstalled("llama3", among: installed))
    }

    @Test("Имя модели очищается от провайдера и метки")
    func основаИмени() {
        #expect(RecommendedModel.base(of: "ollama|nomic-embed-text:latest") == "nomic-embed-text")
        #expect(RecommendedModel.base(of: "gemma4:12b") == "gemma4")
    }
}

/// Отбор заметок под вопрос.
@Suite("Заметки под вопрос")
struct NotesRetrieverTests {
    private let vectors: [(noteID: Int64, vector: [Float])] = [
        (1, [1, 0, 0]),
        (2, [0.9, 0.1, 0]),
        (3, [0, 1, 0]),
        (4, [-1, 0, 0])
    ]

    @Test("Ближайшие идут первыми")
    func ближайшиеПервыми() {
        let picked = NotesRetriever.nearest(
            to: [1, 0, 0], among: vectors, count: 10, floor: NotesRetriever.floor
        )
        #expect(picked == [1, 2])
    }

    /// Порог низкий нарочно: это отбор, а не утверждение о связи. Но заметку,
    /// не имеющую к вопросу отношения, он обязан отсечь.
    @Test("Противоположное по смыслу в контекст не попадает")
    func противоположноеОтсекается() {
        let picked = NotesRetriever.nearest(
            to: [1, 0, 0], among: vectors, count: 10, floor: NotesRetriever.floor
        )
        #expect(!picked.contains(4))
        #expect(!picked.contains(3), "перпендикулярное — тоже мимо")
    }

    @Test("Больше запрошенного не отдаётся")
    func потолокШтук() {
        let picked = NotesRetriever.nearest(to: [1, 0, 0], among: vectors, count: 1, floor: 0)
        #expect(picked == [1])
    }

    @Test("Пустое хранилище векторов даёт пустой отбор")
    func пустыеВекторы() {
        #expect(NotesRetriever.nearest(to: [1, 0, 0], among: [], count: 5, floor: 0).isEmpty)
    }
}

/// Чем векторная модель отличается от обычной.
@Suite("Умения модели")
struct ModelCapabilityTests {
    /// Спрашиваем у самой Ollama, а не угадываем по имени: векторную модель
    /// зовут и `nomic-embed-text`, и `bge-m3`, и
    /// `hf.co/Qwen/Qwen3-Embedding-4B-GGUF:Q4_K_M`.
    @Test("Умения вынимаются из ответа")
    func умения() {
        let data = Data(#"{"capabilities":["embedding","tools","insert"]}"#.utf8)
        #expect(ModelClient.capabilities(in: data) == ["embedding", "tools", "insert"])
    }

    @Test("Обычная модель векторной не притворяется")
    func обычнаяМодель() {
        let data = Data(#"{"capabilities":["completion","vision","tools"]}"#.utf8)
        #expect(!ModelClient.capabilities(in: data).contains("embedding"))
    }

    /// У Ollama постарше этого поля нет вовсе. Пустой ответ значит
    /// «не знаю», а не «ничего не умеет».
    @Test("Ответ без поля умений даёт пустой набор")
    func ответаНет() {
        #expect(ModelClient.capabilities(in: Data(#"{"details":{}}"#.utf8)).isEmpty)
        #expect(ModelClient.capabilities(in: Data("не json".utf8)).isEmpty)
    }
}

/// Кому искать связи, а кого не трогать.
@Suite("Связи только у новых")
struct LinksScopeTests {
    private let border = Date(timeIntervalSince1970: 1_757_000_000)

    /// У архива на пять тысяч заметок первый проход — это пять тысяч
    /// запросов к чат-модели. Человек, включивший связи, такого не заказывал.
    @Test("Заметка старше границы связями не трогается")
    func стараяНеТрогается() {
        let old = border.addingTimeInterval(-60)
        #expect(!NoteLinker.shouldLink(old, onlyNew: true, since: border))
    }

    @Test("Записанное после включения — новое")
    func новаяСвязывается() {
        let fresh = border.addingTimeInterval(60)
        #expect(NoteLinker.shouldLink(fresh, onlyNew: true, since: border))
        #expect(NoteLinker.shouldLink(border, onlyNew: true, since: border), "ровно на границе — новая")
    }

    @Test("Выключенное «только новые» связывает всех")
    func всехПодряд() {
        let old = border.addingTimeInterval(-100_000)
        #expect(NoteLinker.shouldLink(old, onlyNew: false, since: border))
    }

    /// Так работает кнопка «Связать и старые»: граница снимается.
    @Test("Снятая граница связывает всех")
    func границыНет() {
        let old = border.addingTimeInterval(-100_000)
        #expect(NoteLinker.shouldLink(old, onlyNew: true, since: nil))
    }
}
