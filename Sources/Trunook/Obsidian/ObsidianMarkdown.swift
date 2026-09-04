import AppKit
import Foundation

/// Файл хранилища: шапка свойств, тело, блок связей — и обратный перевод
/// разметки в оформленный текст.
///
/// Здесь заканчивается работа `NoteMarkdown`: тот умеет только прямое
/// направление, из оформленного текста в разметку, потому что выгрузке
/// в папку обратный путь не нужен вовсе. Синхронизации нужен круг.
///
/// `MarkdownRender` для обратной стороны не годится: он отдаёт список строк
/// для показа в вырезе — со своими видами блоков и своей вёрсткой, — а полю
/// правки нужен `NSAttributedString` с теми же кеглями и начертаниями,
/// какие ставит `RichTextEditor`. Разойдись эти два набора, и заметка,
/// проехавшая через файл, вернулась бы с чужим оформлением.
enum ObsidianMarkdown {
    // MARK: - Имена свойств

    enum Key {
        /// Постоянный номер заметки. Он и делает переименование в Obsidian
        /// переименованием, а не «удалили одну, завели другую».
        static let uid = "trunook"
        static let created = "created"
    }

    // MARK: - Метки блока связей

    /// Комментарии Markdown: в Obsidian их не видно, а найти их в файле
    /// можно точным совпадением строки.
    ///
    /// Между метками приложение переписывает всё, **вне их — ни байта**.
    /// Это единственная защита чужого текста от нашей записи, поэтому метки
    /// и сравниваются целой строкой, а не «содержит».
    static let linksStart = "<!-- trunook:связи:начало -->"
    static let linksEnd = "<!-- trunook:связи:конец -->"

    // MARK: - Шапка свойств

    /// Разрезает файл на шапку свойств и тело.
    ///
    /// Шапкой считается только та, что стоит с самого начала файла: `---`
    /// посреди текста — это горизонтальная черта, и принять её за начало
    /// свойств значило бы съесть половину заметки.
    static func split(_ text: String) -> (front: [String], body: String) {
        let lines = self.lines(of: text)
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return ([], text)
        }
        guard let end = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        }) else {
            // Открытая и незакрытая шапка — это не шапка, а текст,
            // начинающийся с черты.
            return ([], text)
        }
        let front = Array(lines[1..<end])
        let body = lines[(end + 1)...].joined(separator: "\n")
        return (front, trimmingLeadingBlankLines(body))
    }

    /// Собирает файл обратно.
    static func join(front: [String], body: String) -> String {
        guard !front.isEmpty else { return body }
        return (["---"] + front + ["---", "", ""]).joined(separator: "\n") + body
    }

    /// Значение свойства. Кавычки вокруг значения снимаются: Obsidian
    /// заключает в них всё, что похоже на ссылку.
    static func value(of key: String, in front: [String]) -> String? {
        for line in front {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            guard name == key else { continue }
            var value = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Ставит или заменяет одно свойство, **не трогая остальных**.
    ///
    /// Свойства в чужой заметке ставил человек: теги, дата, статус задачи.
    /// Собрать шапку заново «как надо» значило бы стереть их молча.
    static func setting(_ key: String, to value: String, in front: [String]) -> [String] {
        let line = "\(key): \(value)"
        var result = front
        for (index, existing) in front.enumerated() {
            guard let colon = existing.firstIndex(of: ":") else { continue }
            let name = String(existing[existing.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            if name == key {
                result[index] = line
                return result
            }
        }
        result.append(line)
        return result
    }

    // MARK: - Блок связей

    /// Блок связей целиком, вместе с метками. `nil`, если его нет.
    static func linksBlock(in text: String) -> String? {
        let lines = self.lines(of: text)
        guard let start = lines.firstIndex(of: linksStart),
              let end = lines[start...].firstIndex(of: linksEnd)
        else { return nil }
        return lines[start...end].joined(separator: "\n")
    }

    /// Текст без блока связей.
    static func stripLinks(from text: String) -> String {
        let lines = self.lines(of: text)
        guard let start = lines.firstIndex(of: linksStart),
              let end = lines[start...].firstIndex(of: linksEnd)
        else { return text }
        var kept = Array(lines[..<start])
        kept.append(contentsOf: lines[(end + 1)...])
        return trimmingTrailingBlankLines(kept.joined(separator: "\n"))
    }

    /// Ставит блок связей в конец текста, заменяя прежний. `nil` снимает его
    /// совсем — так работает кнопка «Убрать блоки связей из файлов».
    static func settingLinks(_ block: String?, in text: String) -> String {
        let clean = stripLinks(from: text)
        guard let block, !block.isEmpty else { return clean }
        return clean.isEmpty ? block : clean + "\n\n" + block
    }

    /// Собирает блок связей из готовых строк.
    static func linksBlock(lines rows: [String]) -> String? {
        guard !rows.isEmpty else { return nil }
        return ([linksStart, "## " + t("Связанное")] + rows + [linksEnd]).joined(separator: "\n")
    }

    // MARK: - Файл своей заметки

    /// Имя файла своей заметки в хранилище.
    ///
    /// Имя файла — это и есть имя заметки: в Obsidian на неё ссылаются
    /// именно так, а `# Заголовок` внутри был бы вторым названием рядом
    /// с первым. Дата в имени, в отличие от выгрузки в папку, не нужна —
    /// хранилище сортирует своими средствами, а дата лежит в свойствах.
    static func fileName(for note: Note) -> String {
        let name = NoteMarkdown.safe(note.title)
        guard !name.isEmpty else { return fileStamp(note.createdAt) + ".md" }
        return name + ".md"
    }

    /// Файл своей заметки: обновлённая шапка, тело из оформленного текста
    /// и прежний блок связей на месте.
    ///
    /// `existing` — то, что лежит в файле сейчас. Оно нужно целиком, а не
    /// ради проверки: в шапке могли появиться чужие свойства, а в конце —
    /// блок связей, и собрать файл заново с нуля значило бы стереть и то,
    /// и другое.
    static func file(for note: Note, uid: String, existing: String?) -> String {
        let (front, oldBody) = split(existing ?? "")
        var updated = setting(Key.uid, to: uid, in: front)
        updated = setting(Key.created, to: stamp(note.createdAt), in: updated)

        let body = settingLinks(linksBlock(in: oldBody), in: NoteMarkdown.body(note.attributed))
        return join(front: updated, body: body.isEmpty ? "" : body + "\n")
    }

    /// Тело файла, готовое к показу: без шапки свойств и без блока связей.
    ///
    /// Связи показывают отдельным разделом панели, а не строчками в тексте:
    /// в теле они выглядели бы припиской, которую человек не писал.
    static func readableBody(of text: String) -> String {
        stripLinks(from: split(text).body)
    }

    // MARK: - Разметка в оформленный текст

    /// Обратный перевод: разметка файла — в текст с оформлением.
    ///
    /// Переводится ровно то, что умеет поле правки: заголовок, полужирный,
    /// курсив, ссылка. Всё прочее — списки, цитаты, код, таблицы — остаётся
    /// **как есть, строкой текста**. Это не лень: так круг «файл → заметка →
    /// файл» ничего не теряет. Преврати мы `- пункт` в красивую точку,
    /// обратная запись вернула бы в файл эту точку вместо разметки списка,
    /// и заметка в Obsidian испортилась бы молча.
    static func attributed(from markdown: String, style: RichTextEditor.Style = .note) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var insideFence = false

        for (index, raw) in lines(of: markdown).enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n", attributes: plainAttributes(size: style.bodyFontSize)))
            }
            let line = String(raw)

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                insideFence.toggle()
                result.append(NSAttributedString(string: line, attributes: plainAttributes(size: style.bodyFontSize)))
                continue
            }
            if insideFence {
                result.append(NSAttributedString(string: line, attributes: plainAttributes(size: style.bodyFontSize)))
                continue
            }

            if let heading = heading(in: line) {
                result.append(
                    inline(heading, size: style.headingFontSize, bold: true, italic: false, tint: style.tint)
                )
                continue
            }
            result.append(inline(line, size: style.bodyFontSize, bold: false, italic: false, tint: style.tint))
        }
        return result
    }

    /// Содержимое строки-заголовка. `nil`, если строка обычная.
    ///
    /// Уровень не сохраняется: поле правки знает один заголовок, и делать
    /// вид, что их шесть, незачем. Обратно уходит `##` — первый уровень
    /// в файле хранилища занят именем заметки.
    private static func heading(in line: String) -> String? {
        var marks = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == "#", marks < 6 {
            marks += 1
            index = line.index(after: index)
        }
        guard marks > 0, index < line.endIndex, line[index] == " " else { return nil }
        return String(line[line.index(after: index)...])
    }

    // MARK: - Разметка внутри строки

    private static func inline(
        _ text: String,
        size: CGFloat,
        bold: Bool,
        italic: Bool,
        tint: NSColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let chars = Array(text)
        var plain = ""
        var index = 0

        func flush() {
            guard !plain.isEmpty else { return }
            result.append(
                NSAttributedString(
                    string: plain,
                    attributes: attributes(size: size, bold: bold, italic: italic)
                )
            )
            plain = ""
        }

        while index < chars.count {
            if chars[index] == "[", let link = link(chars, from: index) {
                flush()
                let inner = inline(link.text, size: size, bold: bold, italic: italic, tint: tint)
                let marked = NSMutableAttributedString(attributedString: inner)
                let all = NSRange(location: 0, length: marked.length)
                marked.addAttribute(.link, value: link.url, range: all)
                marked.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: all)
                marked.addAttribute(.foregroundColor, value: tint, range: all)
                result.append(marked)
                index = link.next
                continue
            }

            if chars[index] == "*", let mark = emphasis(chars, from: index) {
                flush()
                result.append(
                    inline(
                        mark.text,
                        size: size,
                        bold: bold || mark.bold,
                        italic: italic || mark.italic,
                        tint: tint
                    )
                )
                index = mark.next
                continue
            }

            plain.append(chars[index])
            index += 1
        }
        flush()
        return result
    }

    /// `[текст](адрес)` целиком. `nil`, если это просто квадратная скобка —
    /// в том числе у ссылки Obsidian `[[Заметка]]`, которую трогать нельзя.
    private static func link(_ chars: [Character], from start: Int) -> (text: String, url: URL, next: Int)? {
        guard start + 1 < chars.count, chars[start + 1] != "[" else { return nil }
        guard let close = chars[(start + 1)...].firstIndex(of: "]") else { return nil }
        guard close + 1 < chars.count, chars[close + 1] == "(" else { return nil }
        guard let end = chars[(close + 2)...].firstIndex(of: ")") else { return nil }

        let text = String(chars[(start + 1)..<close])
        let address = String(chars[(close + 2)..<end]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !address.isEmpty, let url = RichTextEditor.url(from: address) else { return nil }
        return (text, url, end + 1)
    }

    /// `*курсив*`, `**жирный**`, `***и то и другое***`.
    ///
    /// Закрывающие звёздочки ищутся тем же числом, что и открывающие,
    /// а пробел сразу после открытия отменяет разметку: `5 * 3 * 2` — это
    /// умножение, а не курсив.
    private static func emphasis(
        _ chars: [Character],
        from start: Int
    ) -> (text: String, bold: Bool, italic: Bool, next: Int)? {
        var marks = 0
        while start + marks < chars.count, chars[start + marks] == "*", marks < 3 { marks += 1 }
        let open = start + marks
        guard marks > 0, open < chars.count, chars[open] != " " else { return nil }

        var index = open
        while index < chars.count {
            if chars[index] == "*" {
                var run = 0
                while index + run < chars.count, chars[index + run] == "*" { run += 1 }
                if run == marks, index > open, chars[index - 1] != " " {
                    return (
                        String(chars[open..<index]),
                        marks >= 2,
                        marks == 1 || marks == 3,
                        index + marks
                    )
                }
                index += max(run, 1)
                continue
            }
            index += 1
        }
        return nil
    }

    // MARK: - Оформление

    private static func plainAttributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        attributes(size: size, bold: false, italic: false)
    }

    private static func attributes(size: CGFloat, bold: Bool, italic: Bool) -> [NSAttributedString.Key: Any] {
        [.font: font(size: size, bold: bold, italic: italic), .foregroundColor: NSColor.white]
    }

    private static func font(size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let base = NSFont.systemFont(ofSize: size)
        guard !traits.isEmpty else { return base }
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    // MARK: - Строки и даты

    /// Разбор на строки **только** по `Character.isNewline`.
    ///
    /// Это не придирка к стилю. Файлы хранилища приходят с чужими переносами,
    /// и `\r\n` в Swift — **один** символ: `components(separatedBy: "\n")`
    /// рвёт пару пополам и оставляет `\r` в хвосте каждой строки, а
    /// `contains("\r")` отвечает «нет», потому что одинокого возврата каретки
    /// в тексте и правда нет. Правка, сделанная привычным способом, выглядит
    /// рабочей и не делает ничего — этот час уже потрачен на описаниях
    /// выпусков.
    static func lines(of text: String) -> [String] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
    }

    /// Дата в свойствах — в том виде, в каком её пишет сам Obsidian:
    /// `04.09.2026 19:46`.
    ///
    /// Не ISO. `2026-09-04T19:46:46Z` — машинная запись: она точна, но
    /// человек читает свойства заметки глазами, а Obsidian показывает их
    /// панелью прямо над текстом. Секунды и часовой пояс там лишние.
    ///
    /// Локаль постоянная, `en_US_POSIX`: формат числовой, и локаль системы
    /// перевела бы его то в `04/09/2026`, то в `2026/09/04` — у одного
    /// человека одно, у другого другое, и разобрать чужой файл стало бы
    /// нечем.
    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter
    }()

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func stamp(_ date: Date) -> String { stampFormatter.string(from: date) }

    /// Разбирает дату из свойств.
    ///
    /// Оба вида: свой и оставшийся от прежних записей ISO. Файлы, записанные
    /// до смены формата, лежат у людей на дисках, и отказ их прочитать
    /// означал бы потерянную дату создания у каждой такой заметки.
    static func date(from text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return stampFormatter.date(from: trimmed) ?? iso.date(from: trimmed)
    }

    /// Запасное имя файла, когда у заметки нет названия.
    private static func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: date)
    }

    // MARK: - Мелочи

    private static func trimmingLeadingBlankLines(_ text: String) -> String {
        var lines = self.lines(of: text)
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n")
    }

    private static func trimmingTrailingBlankLines(_ text: String) -> String {
        var lines = self.lines(of: text)
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
