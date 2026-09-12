import Foundation

/// Описание инструмента на проводе.
///
/// Одна сериализация на оба диалекта: `/api/chat` у Ollama принимает ту же
/// разметку `tools`, что и OpenAI. Расходятся они не в описании инструмента,
/// а в **эхе** — в том, как вызов и его результат кладутся обратно
/// в переписку. См. `ModelClient.wire(_:dialect:)`: это единственное место
/// во всём проводе, где диалекты разошлись.
struct ToolSchema: Equatable {
    struct Parameter: Equatable {
        enum Kind: String {
            case string
            case integer
            case boolean
        }

        let name: String
        let kind: Kind
        /// Описание читает модель — значит через `t()`, как и указание
        /// «твой ответ прочитают вслух» в `AssistantSession.AnswerStyle`.
        /// Интерфейс трёхъязычный, и китайцу модель должна получать
        /// китайское описание.
        let description: String
        let isRequired: Bool
        /// Допустимые значения. Пусто — любое.
        var choices: [String] = []
    }

    let name: String
    let description: String
    let parameters: [Parameter]

    /// Готовый словарь для `body["tools"]`.
    ///
    /// Три правила здесь неочевидны, и каждое куплено чужими граблями:
    ///
    /// - `properties` стоит **всегда**, даже пустым. Голое
    ///   `{"type":"object"}` строгие серверы отвергают.
    /// - `required` при пустом списке не пишется вовсе, а не пишется `[]`.
    /// - ни `strict`, ни `additionalProperties`: их понимают не все, а без
    ///   них работают все.
    var wire: [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []

        for parameter in parameters {
            var field: [String: Any] = [
                "type": parameter.kind.rawValue,
                "description": parameter.description,
            ]
            if !parameter.choices.isEmpty { field["enum"] = parameter.choices }
            properties[parameter.name] = field
            if parameter.isRequired { required.append(parameter.name) }
        }

        var shape: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { shape["required"] = required }

        return [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": shape,
            ],
        ]
    }

    /// Годится ли имя для провода.
    ///
    /// OpenAI проверяет имена по образцу `^[a-zA-Z0-9_-]{1,64}$` и отвергает
    /// точку. Ollama точку терпит — то есть имя вида `calendar.create` жило
    /// бы на местной модели и молча падало у облачного провайдера. Поэтому
    /// правило проверяется тестом, а не доверием.
    static func isValidName(_ name: String) -> Bool {
        guard (1...64).contains(name.count) else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
            .union(CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"))
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
