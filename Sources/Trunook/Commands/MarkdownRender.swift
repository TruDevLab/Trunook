import Foundation

/// Разбор Markdown до того немногого, что имеет смысл показывать в вырезе.
///
/// Модели отвечают разметкой, о которой их никто не просил: заголовки,
/// списки, `**жирный**`. Показывать её сырой нельзя — звёздочки посреди
/// текста читаются как опечатки. Полноценный отрисовщик здесь тоже ни к чему:
/// в панели высотой в десяток строк не нужны ни таблицы, ни картинки.
///
/// Поэтому разбираем построчно: у строки определяем вид, а внутри строки
/// отдаём выделение системному разбору `AttributedString`.
enum MarkdownRender {
    enum Kind: Equatable {
        case paragraph
        /// Уровень заголовка, 1…3. Больше в такой панели неразличимо.
        case heading(Int)
        /// Пункт списка. Маркер готовый: у нумерованного это его номер.
        case item(String)
        case quote
        case code
        /// Разделительная черта.
        case rule
    }

    struct Line: Identifiable {
        let id: Int
        let kind: Kind
        let text: AttributedString
        /// Тот же текст без всякой разметки — для замера ширины и для
        /// того, что уходит в буфер обмена.
        let plain: String
    }

    static func lines(from markdown: String) -> [Line] {
        merge(parse(markdown))
    }

    /// Подряд идущие строки кода — это один блок, а не стопка полосок.
    /// Порознь у каждой своя подложка, и ответ выглядит как таблица.
    private static func merge(_ lines: [Line]) -> [Line] {
        var result: [Line] = []
        for line in lines {
            if line.kind == .code, let last = result.last, last.kind == .code {
                result[result.count - 1] = Line(
                    id: last.id,
                    kind: .code,
                    text: last.text + AttributedString("\n") + line.text,
                    plain: last.plain + "\n" + line.plain
                )
            } else {
                result.append(line)
            }
        }
        return result
    }

    private static func parse(_ markdown: String) -> [Line] {
        var result: [Line] = []
        var insideFence = false

        for (index, raw) in markdown.components(separatedBy: "\n").enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                insideFence.toggle()
                continue
            }
            if insideFence {
                result.append(Line(id: index, kind: .code, text: AttributedString(raw), plain: raw))
                continue
            }
            if isRule(trimmed) {
                result.append(Line(id: index, kind: .rule, text: AttributedString(""), plain: ""))
                continue
            }

            let (kind, body) = classify(trimmed)
            let attributed = inline(body)
            result.append(Line(
                id: index,
                kind: kind,
                text: attributed,
                plain: String(attributed.characters)
            ))
        }
        return result
    }

    /// Текст без разметки: он уходит в буфер обмена и во вставку.
    ///
    /// Копировать сырой Markdown было бы неожиданно: человек видит в панели
    /// набранный текст без звёздочек и его же ожидает получить.
    static func plain(_ markdown: String) -> String {
        lines(from: markdown)
            .map { line in
                switch line.kind {
                case let .item(marker): return "\(marker) \(line.plain)"
                case .rule: return ""
                default: return line.plain
                }
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Разбор строки

    private static func classify(_ line: String) -> (Kind, String) {
        if line.hasPrefix("#") {
            let hashes = line.prefix { $0 == "#" }.count
            let body = line.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
            return (.heading(min(hashes, 3)), body)
        }
        if line.hasPrefix("> ") {
            return (.quote, String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        }
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            // Пробелы после маркера обрезаем: модели ставят их по два-три,
            // и первая строка пункта выезжала правее собственных переносов.
            return (.item("•"), String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        }
        if let match = orderedMarker(line) {
            return (.item(match.marker), match.body)
        }
        return (.paragraph, line)
    }

    /// «1. текст» — маркером остаётся сам номер: у модели он часто значащий,
    /// и заменять его точкой нельзя.
    private static func orderedMarker(_ line: String) -> (marker: String, body: String)? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return (String(digits) + ".", String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        return line.allSatisfy { $0 == "-" } || line.allSatisfy { $0 == "*" }
            || line.allSatisfy { $0 == "_" }
    }

    /// Выделение внутри строки разбирает система.
    ///
    /// Только строчный разбор: полный превратил бы каждую строку в отдельный
    /// документ со своими отступами, а они здесь уже расставлены нами.
    /// На незакрытой разметке — а поток обрывает её на каждом слове —
    /// разбор просто возвращает текст как есть, и это то, что нужно.
    private static func inline(_ text: String) -> AttributedString {
        guard !text.isEmpty else { return AttributedString("") }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
