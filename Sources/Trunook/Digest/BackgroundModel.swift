import TrunookXPC
import Foundation

/// Разовый вопрос модели из фоновой работы — сводки или слежки.
///
/// Отличие от вопроса из панели одно, но важное: никто не смотрит. Движок
/// в десять утра может ещё подниматься (`OllamaEngine.ensureUp` запускает
/// его и не ждёт), и первый запрос дня тогда падает. Человек в панели
/// нажал бы ещё раз, а здесь нажать некому — поэтому один повтор
/// с паузой встроен сюда.
enum BackgroundModel {
    static let retryDelay: UInt64 = 20_000_000_000

    @MainActor
    static func ask(_ prompt: String, model: String, client: ModelClient, label: String) async -> String? {
        if let answer = await once(prompt, model: model, client: client, label: label) { return answer }
        try? await Task.sleep(nanoseconds: retryDelay)
        return await once(prompt, model: model, client: client, label: label)
    }

    @MainActor
    private static func once(_ prompt: String, model: String, client: ModelClient, label: String) async -> String? {
        await withCheckedContinuation { continuation in
            client.stream(
                messages: [.user(prompt)],
                contextWindow: ModelClient.contextWindow(forCharacters: prompt.count),
                model: model.isEmpty ? nil : model,
                onToken: { _ in },
                onFinish: { result in
                    switch result {
                    case let .success(text):
                        continuation.resume(returning: text)
                    case let .failure(error):
                        DebugLog.write("\(label): модель не ответила — \(error.localizedDescription)")
                        continuation.resume(returning: nil)
                    }
                }
            )
        }
    }
}
