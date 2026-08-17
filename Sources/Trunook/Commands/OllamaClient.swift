import TrunookXPC
import Foundation

/// Клиент Ollama.
final class OllamaClient {
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

    private var baseURL: URL? { URL(string: settings.ollamaURL) }

    // MARK: - Потоковый разговор

    /// Ведёт разговор, отдавая ответ по кускам.
    ///
    /// Возвращает задачу: пока модель думает, пользователь может закрыть
    /// панель, и тянуть ответ в никуда незачем — Ollama продолжала бы
    /// считать до конца, занимая память под контекст.
    @discardableResult
    func stream(
        messages: [ChatMessage],
        onToken: @escaping (String) -> Void,
        onFinish: @escaping (Result<String, Error>) -> Void
    ) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            do {
                let request = try self.chatRequest(messages: messages)
                let (bytes, response) = try await self.session.bytes(for: request)

                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw OllamaError.server(http.statusCode, "")
                }

                var answer = ""
                // Ollama отдаёт по одному объекту JSON на строку, а не единым
                // документом: разбирать нужно построчно, по мере поступления.
                for try await line in bytes.lines {
                    if Task.isCancelled { return }
                    guard let data = line.data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { continue }

                    if let message = object["message"] as? [String: Any],
                       let piece = message["content"] as? String,
                       !piece.isEmpty {
                        answer += piece
                        let chunk = piece
                        await MainActor.run { onToken(chunk) }
                    }
                    if object["done"] as? Bool == true { break }
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

    private func chatRequest(messages: [ChatMessage]) throws -> URLRequest {
        guard let base = baseURL, let url = URL(string: "/api/chat", relativeTo: base) else {
            throw OllamaError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": settings.ollamaModel,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": true,
            "keep_alive": settings.ollamaKeepAlive,
            "options": ["num_predict": 2048],
        ])
        return request
    }

    func generate(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let base = baseURL, let url = URL(string: "/api/generate", relativeTo: base) else {
            completion(.failure(OllamaError.badURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": settings.ollamaModel,
            "prompt": prompt,
            "stream": false,
            // По умолчанию Ollama выгружает модель через пять минут простоя,
            // и следующий вызов платит за её загрузку около минуты. Для
            // команды, которая называется быстрой, это неприемлемо: держим
            // модель в памяти между вызовами.
            "keep_alive": settings.ollamaKeepAlive,
            "options": [
                // Потолок длины ответа. Без него модель на неудачном промте
                // способна генерировать до упора, и команда просто зависает.
                "num_predict": 2048,
            ],
        ])

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data else {
                completion(.failure(OllamaError.emptyResponse))
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                completion(.failure(OllamaError.server(http.statusCode, body)))
                return
            }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = object["response"] as? String
            else {
                completion(.failure(OllamaError.emptyResponse))
                return
            }
            completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        }.resume()
    }

    /// Список установленных моделей — для выбора в настройках.
    func listModels(completion: @escaping ([Model]) -> Void) {
        guard let base = baseURL, let url = URL(string: "/api/tags", relativeTo: base) else {
            completion([])
            return
        }
        session.dataTask(with: url) { data, _, _ in
            guard let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = object["models"] as? [[String: Any]]
            else {
                completion([])
                return
            }
            let models = raw.compactMap { $0["name"] as? String }.map(Model.init)
            completion(models.sorted { $0.name < $1.name })
        }.resume()
    }

    enum OllamaError: LocalizedError {
        case badURL
        case emptyResponse
        case server(Int, String)

        var errorDescription: String? {
            switch self {
            case .badURL: return t("Неверный адрес Ollama")
            case .emptyResponse: return t("Ollama вернула пустой ответ")
            case let .server(code, body):
                return "Ollama ответила \(code): \(body.prefix(120))"
            }
        }
    }
}
