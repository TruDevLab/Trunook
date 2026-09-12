import Foundation

/// Вызов инструмента, о котором попросила модель.
struct ToolCall: Equatable, Identifiable {
    /// У OpenAI приходит от сервера, у Ollama его нет вовсе — тогда
    /// назначаем свой, `call_1`. Без него нечем сослаться на результат:
    /// OpenAI требует `tool_call_id` в ответной реплике.
    let id: String
    let name: String
    /// Аргументы **строкой JSON**, а не словарём.
    ///
    /// Словарём было бы удобнее, но `[String: Any]` не `Equatable`,
    /// а `ModelClient.ChatMessage` обязан им остаться — по нему считается
    /// высота панели. К тому же OpenAI именно строкой их и присылает,
    /// по кускам: разбирать её всё равно приходится один раз, и лучше
    /// в одном месте.
    let arguments: String

    /// Разобранные аргументы. Пустой словарь — и когда аргументов нет,
    /// и когда модель прислала мусор: инструмент в обоих случаях ответит,
    /// что не понял, и у модели будет заход поправиться.
    var values: [String: Any] {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    /// Аргументы объектом для провода Ollama — ей нужен именно объект.
    /// Пустая строка означает «аргументов нет», а не «пустой объект»,
    /// но на проводе это одно и то же.
    var wireArguments: [String: Any] { values }

    /// Строковое значение аргумента.
    ///
    /// Модель шлёт `10` и `"10"` вперемешку, и разбирать это в каждом
    /// инструменте по-своему значило бы разойтись на первом же. Число,
    /// строка и булево сводятся к строке здесь, один раз.
    func string(_ key: String) -> String? {
        switch values[key] {
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    func integer(_ key: String) -> Int? {
        switch values[key] {
        case let number as NSNumber: return number.intValue
        case let text as String: return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }

    /// Булево. Модель пишет и `true`, и `"true"`, и `"да"`.
    func flag(_ key: String) -> Bool {
        switch values[key] {
        case let number as NSNumber: return number.boolValue
        case let text as String:
            return ["true", "yes", "1", "да"].contains(text.lowercased())
        default: return false
        }
    }
}
