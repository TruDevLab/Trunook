import Foundation

/// Разбор Markdown для окна знакомства — надстройка над `MarkdownRender`.
///
/// Отрисовщик выреза сделан под ответ модели: там нет ни таблиц, ни картинок,
/// и добавлять их туда незачем — в панели высотой в десяток строк таблица
/// всё равно не поместится. А здесь читают README и описания выпусков,
/// и в них есть и то, и другое: одних только таблиц сочетаний в README две.
///
/// Поэтому не правка общего разбора, а надстройка над ним: строки приходят
/// готовыми, а здесь они собираются в блоки. Разбор выреза при этом остаётся
/// нетронутым — вместе с расчётом высоты панели, который на него опирается.
enum WelcomeMarkdown {
    enum Block: Identifiable {
        case line(MarkdownRender.Line)
        /// Таблица целиком: шапка и строки. Порознь её ячейки — это набор
        /// абзацев с палками посередине, то есть не таблица.
        case table(id: Int, header: [String], rows: [[String]])

        var id: Int {
            switch self {
            case let .line(line): return line.id
            case let .table(id, _, _): return id
            }
        }
    }

    static func blocks(from markdown: String) -> [Block] {
        var result: [Block] = []
        var pending: [[String]] = []
        var tableStart = 0
        // Пустая строка кончает абзац — и на этом её работа заканчивается.
        // Своим блоком она была просветом вдобавок к отступам вокруг
        // заголовков, и заголовок отрывался от собственного текста дальше,
        // чем от предыдущего.
        var paragraphBroken = true

        func flushTable() {
            defer {
                if !pending.isEmpty { paragraphBroken = true }
                pending = []
            }
            guard let header = pending.first else { return }
            // Одна строка с палками — это не таблица, а строка с палками.
            // Собирать из неё шапку без содержимого значило бы соврать глазу.
            guard pending.count > 1 else {
                result.append(.line(MarkdownRender.Line(
                    id: tableStart,
                    kind: .paragraph,
                    text: AttributedString(header.joined(separator: "  ")),
                    plain: header.joined(separator: "  ")
                )))
                return
            }
            result.append(.table(id: tableStart, header: header, rows: Array(pending.dropFirst())))
        }

        for line in MarkdownRender.lines(from: stripImages(newlines(markdown))) {
            if line.kind == .paragraph, line.plain.isEmpty {
                paragraphBroken = true
                continue
            }
            if let cells = row(in: line) {
                // Строка-разделитель под шапкой — разметка, а не содержимое.
                if isSeparator(cells) { continue }
                if pending.isEmpty { tableStart = line.id }
                pending.append(cells)
                continue
            }
            flushTable()
            append(line, to: &result, continuing: !paragraphBroken)
            paragraphBroken = false
        }
        flushTable()
        return result
    }

    /// Строка исходника — не абзац.
    ///
    /// В README и в описаниях выпусков текст перенесён руками по ширине
    /// в семьдесят с небольшим знаков, и без склейки каждая такая строка
    /// вставала бы отдельным абзацем с просветом. Абзац на экране получался
    /// лесенкой из обрывков, а перенесённый пункт списка — обрывком,
    /// вывалившимся из-под своего маркера.
    ///
    /// Абзац кончается пустой строкой — так его и определяет Markdown.
    /// Поэтому продолжение приклеивается к предыдущему блоку: к абзацу,
    /// к пункту списка или к цитате. Заголовок, код и черта продолжения
    /// не имеют — они заканчиваются вместе со своей строкой.
    private static func append(
        _ line: MarkdownRender.Line,
        to result: inout [Block],
        continuing: Bool
    ) {
        guard continuing, line.kind == .paragraph,
              case let .line(previous)? = result.last,
              previous.kind == .paragraph || previous.kind == .quote || isItem(previous.kind)
        else {
            result.append(.line(line))
            return
        }
        result[result.count - 1] = .line(MarkdownRender.Line(
            id: previous.id,
            kind: previous.kind,
            text: previous.text + AttributedString(" ") + line.text,
            plain: previous.plain + " " + line.plain
        ))
    }

    private static func isItem(_ kind: MarkdownRender.Kind) -> Bool {
        if case .item = kind { return true }
        return false
    }

    /// Ячейки строки таблицы или `nil`, если это обычная строка.
    static func row(in line: MarkdownRender.Line) -> [String]? {
        guard line.kind == .paragraph else { return nil }
        let text = line.plain.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("|"), text.hasSuffix("|"), text.count > 2 else { return nil }
        return text.dropFirst().dropLast()
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func isSeparator(_ cells: [String]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { cell in
            let core = cell.drop(while: { $0 == ":" }).reversed().drop(while: { $0 == ":" })
            return !core.isEmpty && core.allSatisfy { $0 == "-" }
        }
    }

    /// Приводит переводы строк к одному виду.
    ///
    /// GitHub отдаёт описание выпуска с `\r\n` — так его сохраняет поле ввода
    /// на странице релиза. Само по себе это ничего не значит, но разбор строки
    /// снимает `CharacterSet.whitespaces`, а возврат каретки в них не входит:
    /// он перевод строки, а не пробел. Из-за одного невидимого знака в хвосте
    /// пустая строка переставала быть пустой и вставала в текст полноразмерным
    /// просветом, строка таблицы теряла закрывающую палку, а `---` переставал
    /// быть чертой. Выглядело это как разъехавшаяся вёрстка описания —
    /// и только у выпусков: README из бандла лежит с обычными переводами строк.
    /// Разбирается по `Character.isNewline`, а не поиском `"\r"` в строке,
    /// и это не украшение. В Swift `\r\n` — **один** символ: две кодовые
    /// точки в одной графеме. Поэтому `contains("\r")` на тексте с GitHub
    /// честно отвечает «нет», а `components(separatedBy: "\n")` рвёт строку
    /// по младшей половине этой пары и оставляет возврат каретки в хвосте
    /// предыдущей. Обе проверки выглядят рабочими, обе молча ничего не делают.
    static func newlines(_ markdown: String) -> String {
        markdown
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .joined(separator: "\n")
    }

    /// Убирает картинки из исходника до разбора.
    ///
    /// Именно до, а не после: строчный разбор `AttributedString` с картинкой
    /// обходится по-своему, и полагаться на то, что от неё останется, нельзя.
    /// А остаться ей всё равно нечем — снимки в README лежат в `docs/`,
    /// в бандл приложения они не едут, и показывать по такой ссылке нечего.
    static func stripImages(_ markdown: String) -> String {
        var result = ""
        var rest = Substring(markdown)
        while let bang = rest.range(of: "![") {
            guard let close = rest.range(of: "]", range: bang.upperBound ..< rest.endIndex),
                  rest[close.upperBound...].first == "(",
                  let paren = rest.range(of: ")", range: close.upperBound ..< rest.endIndex)
            else {
                result += rest[..<bang.upperBound]
                rest = rest[bang.upperBound...]
                continue
            }
            result += rest[..<bang.lowerBound]
            rest = rest[paren.upperBound...]
        }
        return result + rest
    }
}
