import Foundation

/// Собирает вызовы инструментов из потока ответа.
///
/// Два потока устроены по-разному, и это не мелочь разметки.
///
/// Ollama отдаёт вызов **целиком** в одной строке, в `message.tool_calls`,
/// и аргументы у неё **объектом**.
///
/// OpenAI шлёт его **обрывками**: в `choices[0].delta.tool_calls[]` приходит
/// сперва `index` с `id`, потом имя, потом аргументы — по нескольку символов
/// за посылку, строкой. Склеивать их надо **по `index`**, а не по порядку
/// прихода: вызовов бывает несколько сразу, и их куски идут вперемешку.
/// Склейка по порядку выглядит работающей ровно до второго инструмента
/// в одном ответе.
struct ToolCallStream {
    private struct Draft {
        var id: String?
        var name = ""
        var arguments = ""
    }

    private var drafts: [Int: Draft] = [:]
    private var order: [Int] = []

    var isEmpty: Bool { drafts.isEmpty }

    /// Скармливается **каждая** строка потока, и до разбора текста.
    ///
    /// Одна посылка законно несёт и кусок ответа, и кусок вызова, — а `guard`,
    /// которым разбирается текст, такую строку пропустил бы дальше по `continue`
    /// и вызов потерялся бы.
    mutating func eat(_ line: String, dialect: AIProvider.Dialect) {
        switch dialect {
        case .ollama: eatOllama(line)
        case .openAI: eatOpenAI(line)
        }
    }

    /// Собранное, в порядке появления.
    func calls() -> [ToolCall] {
        order.compactMap { index in
            guard let draft = drafts[index], !draft.name.isEmpty else { return nil }
            return ToolCall(
                id: draft.id ?? "call_\(index + 1)",
                name: draft.name,
                arguments: draft.arguments
            )
        }
    }

    // MARK: - Ollama: вызов приходит целиком

    private mutating func eatOllama(_ line: String) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? [String: Any],
              let list = message["tool_calls"] as? [[String: Any]]
        else { return }

        for item in list {
            guard let function = item["function"] as? [String: Any],
                  let name = function["name"] as? String
            else { continue }
            let index = order.count
            drafts[index] = Draft(
                id: item["id"] as? String,
                name: name,
                arguments: Self.text(ofArguments: function["arguments"])
            )
            order.append(index)
        }
    }

    /// Аргументы Ollama — объект. Приводим к строке JSON, чтобы дальше обе
    /// разметки разбирались одинаково. Ключи по порядку: иначе строка
    /// менялась бы от запуска к запуску и тест ловил бы не то.
    private static func text(ofArguments raw: Any?) -> String {
        if let text = raw as? String { return text }
        guard let object = raw as? [String: Any],
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.sortedKeys]
              )
        else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - OpenAI: вызов приходит обрывками

    private mutating func eatOpenAI(_ line: String) {
        guard let payload = ModelClient.sseData(line), payload != "[DONE]",
              let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let list = delta["tool_calls"] as? [[String: Any]]
        else { return }

        for item in list {
            // Без `index` склеивать нечем. Он есть у всех, кто вообще шлёт
            // вызовы обрывками; на всякий случай считаем отсутствие нулём —
            // один вызов так соберётся верно, а не потеряется.
            let index = (item["index"] as? NSNumber)?.intValue ?? 0
            if drafts[index] == nil {
                drafts[index] = Draft()
                order.append(index)
            }
            if let id = item["id"] as? String, !id.isEmpty { drafts[index]?.id = id }
            guard let function = item["function"] as? [String: Any] else { continue }
            if let name = function["name"] as? String, !name.isEmpty {
                drafts[index]?.name = name
            }
            if let piece = function["arguments"] as? String {
                drafts[index]?.arguments += piece
            }
        }
    }
}
