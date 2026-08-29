import TrunookXPC
import Foundation

/// Клиент модели: Ollama или свой сервер, совместимый с OpenAI.
///
/// Один клиент на оба, а не два клиента: снаружи разговор с моделью
/// одинаков — послали переписку, получили ответ по кускам, — и различаются
/// только адрес, обёртка запроса и разметка потока. Два клиента означали бы
/// два места, где заводится окно контекста, потолок ответа и разбор ошибок,
/// и разошлись бы они на первой же правке.
final class ModelClient {
    struct Model: Decodable, Identifiable, Equatable {
        let name: String
        var id: String { name }
    }

    /// Реплика разговора. Нужна именно переписка, а не одиночный запрос:
    /// на ответ модели можно возразить, и она должна помнить, о чём речь.
    struct ChatMessage: Equatable {
        let role: String
        let content: String

        static func user(_ text: String) -> ChatMessage { ChatMessage(role: "user", content: text) }
        static func assistant(_ text: String) -> ChatMessage { ChatMessage(role: "assistant", content: text) }
        /// Указание модели, как отвечать. Отдельной ролью, а не приставкой
        /// к вопросу: приставка попадает в переписку и повторяется в каждой
        /// реплике, а модель начинает отвечать на неё саму.
        static func system(_ text: String) -> ChatMessage { ChatMessage(role: "system", content: text) }
    }

    private let settings: Settings
    private let session: URLSession

    init(settings: Settings = .shared) {
        self.settings = settings
        let configuration = URLSessionConfiguration.ephemeral
        // Первый запрос после простоя ждёт загрузки модели в память:
        // для 12 миллиардов параметров это около минуты, и измеренные 120 с
        // оказались впритык. Пять минут — с запасом.
        configuration.timeoutIntervalForRequest = 300
        session = URLSession(configuration: configuration)
    }

    /// Адрес запроса.
    ///
    /// Склеиваем строками, а не через `URL(string:relativeTo:)`: тот
    /// отбрасывает путь основы, стоит пути начаться с косой черты, — и адрес
    /// `…:8888/v1` терял бы `/v1` молча.
    private func endpoint(_ path: String, of provider: AIProvider) -> URL? {
        var base = settings.apiURL(for: provider).trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty else { return nil }
        return URL(string: base + path)
    }

    /// Путь к API OpenAI-совместимого сервера.
    ///
    /// Адрес такого сервера пишут и с `/v1` на конце, и без него — и оба
    /// написания человек считает верными, потому что оба он где-то видел.
    /// Дописываем недостающее сами, вместо того чтобы требовать одного
    /// из двух и молча отвечать «404» на второе.
    private func openAIPath(_ path: String, of provider: AIProvider) -> String {
        let base = settings.apiURL(for: provider).trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return base.hasSuffix("/v1") ? path : "/v1" + path
    }

    /// Полный адрес запроса — с учётом диалекта провайдера.
    private func url(_ openAI: String, ollama: String, of provider: AIProvider) -> URL? {
        provider.dialect == .ollama
            ? endpoint(ollama, of: provider)
            : endpoint(openAIPath(openAI, of: provider), of: provider)
    }

    /// Ключ доступа заголовком. У Ollama ключа нет — заголовка тоже.
    ///
    /// Ключ берётся **у того провайдера, к которому идём**, а не у основного:
    /// провайдеров держат несколько, и команда может уходить не туда, куда
    /// уходит свободный вопрос.
    private func authorize(_ request: inout URLRequest, as provider: AIProvider) {
        guard provider.usesKey else { return }
        let key = settings.apiKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    }

    // MARK: - Потоковый разговор

    /// Ведёт разговор, отдавая ответ по кускам.
    ///
    /// Возвращает задачу: пока модель думает, пользователь может закрыть
    /// панель, и тянуть ответ в никуда незачем — Ollama продолжала бы
    /// считать до конца, занимая память под контекст.
    /// `model` — чем отвечать. `nil` — моделью из настроек: у большинства
    /// разговоров своей модели нет, а у команды бывает.
    @discardableResult
    func stream(
        messages: [ChatMessage],
        contextWindow: Int? = nil,
        model: String? = nil,
        onToken: @escaping (String) -> Void,
        onFinish: @escaping (Result<String, Error>) -> Void
    ) -> Task<Void, Never> {
        // Клиент держится **сильно**, пока идёт запрос.
        //
        // Слабая ссылка тут выглядела осторожностью, а была ловушкой:
        // клиент, созданный на одну строку (`ModelClient().generate(…)`),
        // умирал раньше, чем задача успевала начаться, и запрос молча
        // не уходил никуда. Поймано на отладочном эхе: сервер отвечал
        // на тот же запрос из curl, а приложение не показывало ничего —
        // ни ответа, ни ошибки.
        //
        // Цикла ссылок это не заводит: задачу держит тот, кто её заказал,
        // а клиент задачу не держит. Живёт она ровно столько, сколько идёт
        // запрос, — то есть ровно столько, сколько клиент и нужен.
        Task { [self] in
            do {
                let request = try self.chatRequest(
                    messages: messages,
                    contextWindow: contextWindow,
                    model: model
                )
                let (bytes, response) = try await self.session.bytes(for: request)

                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    // Тело ошибки читаем: сервер объясняет в нём отказ —
                    // не та модель, кончился ключ, не хватило памяти, — а без
                    // объяснения остаётся голый код, по которому человеку
                    // не понять ничего.
                    var body = ""
                    for try await line in bytes.lines {
                        body += line
                        if body.count > 300 { break }
                    }
                    throw ModelError.server(http.statusCode, body)
                }

                let dialect = self.target(model).provider.dialect
                var answer = ""
                // Оба отдают ответ построчно, а не единым документом,
                // но по-разному: Ollama кладёт в строку голый объект JSON,
                // OpenAI-совместимый — строку вида `data: {…}` и `data: [DONE]`
                // на конце. Разбор поэтому разный, а всё вокруг — общее.
                for try await line in bytes.lines {
                    if Task.isCancelled { return }
                    guard let piece = Self.token(in: line, dialect: dialect) else {
                        if Self.isEnd(line, dialect: dialect) { break }
                        continue
                    }
                    guard !piece.isEmpty else { continue }
                    answer += piece
                    await MainActor.run { onToken(piece) }
                }

                if Task.isCancelled { return }
                let final = answer
                await MainActor.run { onFinish(.success(final)) }
            } catch {
                if Task.isCancelled || error is CancellationError { return }
                await MainActor.run { onFinish(.failure(error)) }
            }
        }
    }

    /// Кусок ответа из строки потока. `nil` — в строке ответа нет.
    static func token(in line: String, dialect: AIProvider.Dialect) -> String? {
        switch dialect {
        case .ollama:
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = object["message"] as? [String: Any]
            else { return nil }
            return message["content"] as? String
        case .openAI:
            guard let payload = Self.sseData(line), payload != "[DONE]",
                  let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = object["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any]
            else { return nil }
            return delta["content"] as? String
        }
    }

    /// Конец потока.
    static func isEnd(_ line: String, dialect: AIProvider.Dialect) -> Bool {
        switch dialect {
        case .ollama:
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }
            return object["done"] as? Bool == true
        case .openAI:
            return Self.sseData(line) == "[DONE]"
        }
    }

    /// Содержимое строки `data: …`. Прочие строки потока — пустые разделители
    /// и служебные `event:` — ответа не несут.
    private static func sseData(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
    }

    /// Куда и чем отвечать на этот запрос.
    ///
    /// Пустое имя равносильно отсутствию: команда, у которой модель однажды
    /// выбрали, а потом эту модель удалили, не должна уходить с пустой
    /// строкой вместо имени.
    private func target(_ model: String?) -> ModelRef {
        settings.modelRef(model) ?? settings.defaultModel
    }

    private func chatRequest(
        messages: [ChatMessage],
        contextWindow: Int?,
        model: String?
    ) throws -> URLRequest {
        let target = target(model)
        let provider = target.provider
        guard let url = url("/chat/completions", ollama: "/api/chat", of: provider) else {
            throw ModelError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request, as: provider)

        let wire = messages.map { ["role": $0.role, "content": $0.content] }
        var body: [String: Any] = ["model": target.name, "messages": wire, "stream": true]

        switch provider.dialect {
        case .ollama:
            var options: [String: Any] = ["num_predict": Self.answerTokens]
            // Просим окно контекста явно — иначе длинный промт молча
            // обрежется. Подробности у `contextWindow(forCharacters:)`.
            if let contextWindow { options["num_ctx"] = contextWindow }
            body["keep_alive"] = settings.ollamaKeepAlive
            body["options"] = options
        case .openAI:
            // Ни окна контекста, ни удержания модели в памяти здесь нет:
            // и то и другое — дело сервера, а не запроса. Просить их полями,
            // которых в этом интерфейсе не существует, значит нарваться
            // на отказ у строгих серверов.
            body["max_tokens"] = Self.answerTokens
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Окно контекста

    /// Потолок длины ответа. Без него модель на неудачном промте способна
    /// генерировать до упора, и запрос просто зависает.
    static let answerTokens = 2048

    /// Сколько контекста просить у модели под промт такой длины.
    ///
    /// Просить приходится **явно**, и это главная ловушка всей затеи
    /// с заметками. У модели в её файле параметра `num_ctx` обычно нет —
    /// проверено на `gemma3:4b`, там заданы только `temperature`, `top_k`,
    /// `top_p` и `stop`, — и Ollama берёт своё умолчание около четырёх тысяч
    /// токенов. Всё, что длиннее, она **молча отрезает**: ни ошибки,
    /// ни предупреждения. Модель отвечает по огрызку промта, и выглядит это
    /// как выдумка модели, а не как потеря данных.
    ///
    /// Два символа на токен — заведомо щедрая оценка: для кириллицы выходит
    /// около двух с половиной, для латиницы вчетверо больше. Ошибка здесь
    /// стоит памяти, а недооценка — тихо испорченного ответа.
    ///
    /// Ступенями, а не точным числом: Ollama выделяет память под контекст
    /// целиком, и дёргать её произвольными размерами на каждый вопрос значит
    /// заставлять перезагружать модель.
    static func contextWindow(forCharacters count: Int) -> Int {
        let needed = count / 2 + answerTokens + 1024
        let ladder = [4096, 8192, 16_384, 32_768, 65_536, 131_072]
        return ladder.first { $0 >= needed } ?? 131_072
    }

    /// Разовый вопрос без переписки — им называется заметка.
    ///
    /// Через тот же поток, что и разговор. Отдельный путь здесь был
    /// (`/api/generate` у Ollama), и он завёл второе место, где задаются
    /// адрес, модель и потолок ответа. Со вторым провайдером таких мест
    /// стало бы четыре.
    func generate(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        stream(
            messages: [.user(prompt)],
            onToken: { _ in },
            onFinish: { result in
                completion(result.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            }
        )
    }

    /// Список моделей — для выбора в настройках и в строке команды.
    func listModels(from provider: AIProvider, completion: @escaping ([ModelRef]) -> Void) {
        guard let url = url("/models", ollama: "/api/tags", of: provider) else {
            completion([])
            return
        }
        var request = URLRequest(url: url)
        authorize(&request, as: provider)

        session.dataTask(with: request) { data, _, _ in
            guard let data else {
                completion([])
                return
            }
            let names = Self.models(in: data, dialect: provider.dialect)
            completion(
                names.sorted { $0.name < $1.name }
                    .map { ModelRef(provider: provider, name: $0.name) }
            )
        }.resume()
    }

    /// Имена моделей из ответа. У Ollama они лежат в `models[].name`,
    /// у OpenAI-совместимого — в `data[].id`.
    static func models(in data: Data, dialect: AIProvider.Dialect) -> [Model] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        switch dialect {
        case .ollama:
            let raw = object["models"] as? [[String: Any]] ?? []
            return raw.compactMap { $0["name"] as? String }.map(Model.init)
        case .openAI:
            let raw = object["data"] as? [[String: Any]] ?? []
            return raw.compactMap { $0["id"] as? String }.map(Model.init)
        }
    }

    enum ModelError: LocalizedError {
        case badURL
        case emptyResponse
        case server(Int, String)

        var errorDescription: String? {
            switch self {
            case .badURL: return t("Неверный адрес сервера модели")
            case .emptyResponse: return t("Сервер модели вернул пустой ответ")
            case let .server(code, body):
                // 401 стоит отдельно: у Ollama ключа нет вовсе, и человек,
                // подключивший свой сервер, увидит именно этот код — а по
                // голому числу не догадаться, что дело в незаполненном ключе.
                if code == 401 || code == 403 { return t("Сервер модели не принял ключ") }
                return tf("Сервер модели ответил %d", code) + (body.isEmpty ? "" : ": \(body.prefix(120))")
            }
        }
    }
}
