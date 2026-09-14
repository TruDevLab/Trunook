import AppKit

/// Списки с галочками в заметках.
///
/// В тексте заметки пункт — символ в начале строки: ☐ или ☑ и пробел.
/// Символом, а не картинкой-вложением: заметка хранится в RTF, а RTF теряет
/// вложения и свои атрибуты, и галочки пропали бы при первом сохранении.
/// Символ переживает и RTF, и поиск, и строку превью в списке.
///
/// Наружу — в Obsidian и выгрузку — уходит обычная разметка `- [ ]`
/// и `- [x]`, и обратно она же превращается в символ. Круг «файл → заметка →
/// файл» ничего не теряет: пункт возвращается в файл тем же `- [ ]`.
enum Checklist {
    static let unchecked: Character = "☐"
    static let checked: Character = "☑"

    static func prefix(checked: Bool) -> String { String(checked ? self.checked : unchecked) + " " }

    /// Пункт списка в строке текста заметки: отступ, отметка и остаток.
    struct Item: Equatable {
        let indent: String
        let isChecked: Bool
        let rest: String
    }

    /// Строка текста заметки — пункт? Отступ перед символом допускается.
    static func item(inDisplay line: String) -> Item? {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let body = line.dropFirst(indent.count)
        guard let mark = body.first, mark == unchecked || mark == checked else { return nil }
        let after = body.dropFirst()
        guard after.isEmpty || after.first == " " else { return nil }
        return Item(indent: indent, isChecked: mark == checked, rest: String(after.dropFirst()))
    }

    /// Строка разметки — пункт? `- [ ]`, `* [ ]`, `+ [ ]`, `- [x]`, `- [X]`.
    static func item(inMarkdown line: String) -> Item? {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let chars = Array(line.dropFirst(indent.count))
        guard chars.count >= 5,
              "-*+".contains(chars[0]), chars[1] == " ", chars[2] == "[", chars[4] == "]",
              chars[3] == " " || chars[3] == "x" || chars[3] == "X"
        else { return nil }
        guard chars.count == 5 || chars[5] == " " else { return nil }
        let rest = chars.count > 6 ? String(chars[6...]) : ""
        return Item(indent: indent, isChecked: chars[3] != " ", rest: rest)
    }

    /// Строка разметки для строки текста заметки.
    static func markdown(fromDisplay line: String) -> String {
        guard let item = item(inDisplay: line) else { return line }
        return item.indent + (item.isChecked ? "- [x] " : "- [ ] ") + item.rest
    }

    /// Строка текста заметки для строки разметки.
    static func display(fromMarkdown line: String) -> String {
        guard let item = item(inMarkdown: line) else { return line }
        return item.indent + prefix(checked: item.isChecked) + item.rest
    }

    /// Весь текст: разметку пунктов — в символы. Для превью и заметок,
    /// записанных до появления галочек.
    static func displayText(fromMarkdown text: String) -> String {
        guard text.contains("[") else { return text }
        return ObsidianMarkdown.lines(of: text).map { display(fromMarkdown: String($0)) }.joined(separator: "\n")
    }

    // MARK: - Оформление

    /// Шрифт самой галочки.
    ///
    /// Свой, а не системный: в системном шрифте есть ☑, а ☐ нет, и система
    /// добирает его из Apple Symbols — пустой квадрат выходил заметно мельче
    /// отмеченного. В Apple Symbols есть оба и одного размера. Кегль крупнее
    /// текста, но ниже заголовка: по кеглю первой буквы строка опознаётся
    /// заголовком при выгрузке.
    static func markFont(bodySize: CGFloat) -> NSFont {
        let size = min(bodySize * 1.3, Note.headingFontSize - 1)
        return NSFont(name: "AppleSymbols", size: size) ?? NSFont.systemFont(ofSize: size)
    }

    /// Дать галочке её шрифт. `location` — сам символ.
    static func styleMark(_ storage: NSMutableAttributedString, at location: Int, bodySize: CGFloat = Note.bodyFontSize) {
        guard location < storage.length else { return }
        let range = NSRange(location: location, length: 1)
        let font = markFont(bodySize: bodySize)
        if (storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont) != font {
            storage.addAttribute(.font, value: font, range: range)
        }
        storage.removeAttribute(.strikethroughStyle, range: range)
        storage.addAttribute(.foregroundColor, value: NSColor.white, range: range)
    }

    /// Отмеченный пункт — приглушённый и зачёркнутый, как в любом списке дел.
    /// `range` начинается с самой галочки.
    static func style(_ storage: NSMutableAttributedString, paragraph range: NSRange, checked: Bool) {
        styleMark(storage, at: range.location)
        guard range.length > 2 else { return }
        let text = NSRange(location: range.location + 2, length: range.length - 2)
        if checked {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: text)
            storage.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.45), range: text)
        } else {
            storage.removeAttribute(.strikethroughStyle, range: text)
            storage.addAttribute(.foregroundColor, value: NSColor.white, range: text)
        }
    }

    /// Разметку пунктов в оформленном тексте — в символы, с оформлением.
    ///
    /// Нужна заметкам, записанным до галочек, и тексту, вставленному
    /// или набранному разметкой. Возвращает, поменялось ли что-нибудь.
    @discardableResult
    static func convertMarkdown(in storage: NSMutableAttributedString) -> Bool {
        let string = storage.string as NSString
        var changed = false
        var location = string.length
        // С конца: замена укорачивает строку, и диапазоны впереди не съезжают.
        while location > 0 {
            let paragraph = (storage.string as NSString).paragraphRange(for: NSRange(location: location - 1, length: 0))
            location = paragraph.location
            let line = (storage.string as NSString).substring(with: paragraph)
                .trimmingCharacters(in: .newlines)
            guard let item = item(inMarkdown: line) else { continue }
            let markerLength = (line as NSString).length - (item.rest as NSString).length
                - (item.indent as NSString).length
            let marker = NSRange(location: paragraph.location + (item.indent as NSString).length, length: markerLength)
            let attributes = storage.attributes(at: marker.location, effectiveRange: nil)
            storage.replaceCharacters(in: marker, with: NSAttributedString(
                string: prefix(checked: item.isChecked), attributes: attributes
            ))
            let updated = (storage.string as NSString).paragraphRange(for: NSRange(location: marker.location, length: 0))
            let body = NSRange(location: marker.location, length: NSMaxRange(updated) - marker.location)
            style(storage, paragraph: body, checked: item.isChecked)
            changed = true
        }
        return changed
    }
}
