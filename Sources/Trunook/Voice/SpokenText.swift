import Foundation

/// Готовит ответ модели к чтению вслух.
///
/// Снятой разметки мало. `MarkdownRender.plain` убирает звёздочки и решётки,
/// но оставляет то, что на экране читается глазом и **не читается голосом**:
///
/// - **маркер списка.** «•» уходил в синтезатор как есть, и тот честно
///   выговаривал его название. Это первое, что слышно в кривом ответе;
/// - **адреса.** Ссылку вслух не воспроизвести: получается минута
///   по буквам и косым чертам;
/// - **эмодзи.** Синтезатор произносит их описание — «улыбающееся лицо
///   с улыбающимися глазами» посреди фразы.
///
/// Отдельно от `SpeechSpeaker`, чтобы проверить тестом: на слух такое
/// ловится только вживую, а вживую из отладочной сессии не послушать.
enum SpokenText {
    /// Убирает всё, что нельзя произнести.
    static func clean(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map(stripMarker)
        return dropUnspeakable(lines.joined(separator: "\n"))
            .replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " \n", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Снимает маркер в начале строки.
    ///
    /// Точку у нумерованного пункта оставляем: она и без того звучит паузой,
    /// а сам номер у модели часто значащий — «во-первых» из него и слышно.
    private static func stripMarker(_ line: String) -> String {
        var body = line.trimmingCharacters(in: .whitespaces)
        while let first = body.first, bullets.contains(first) {
            body = String(body.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return body
    }

    private static let bullets: Set<Character> = ["•", "‣", "◦", "–", "—", "-", "*", "+"]

    /// Выбрасывает адреса и всё, что не произносится словами.
    private static func dropUnspeakable(_ text: String) -> String {
        text
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { word -> String in
                // Не молча: пропавшая ссылка оставила бы фразу без члена
                // предложения — «подробности в», и всё.
                if isAddress(word) { return t("ссылка") }
                return String(String.UnicodeScalarView(word.unicodeScalars.filter {
                    !isUnspeakable($0)
                }))
            }
            .joined(separator: " ")
    }

    private static func isAddress(_ word: Substring) -> Bool {
        word.hasPrefix("http://") || word.hasPrefix("https://") || word.hasPrefix("www.")
    }

    /// Эмодзи и прочие знаки, у которых нет звучания, — только описание.
    private static func isUnspeakable(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isEmoji && scalar.properties.isEmojiPresentation
    }
}
