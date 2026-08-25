import AppKit
import Foundation

/// Заметка в Markdown — для выгрузки в файлы.
///
/// Обратная задача к `MarkdownRender`: тот разбирает разметку из ответа
/// модели, чтобы показать её на экране, а здесь оформление, набранное
/// руками, превращается обратно в разметку.
///
/// Без этого выгрузка была бы нечестной: человек ставил заголовки, жирный
/// и ссылки, а в файле получил бы ровный текст — и заметил бы потерю
/// не сразу, а когда исходной заметки уже нет.
enum NoteMarkdown {
    // MARK: - Файл целиком

    static func document(for note: Note) -> String {
        var parts = ["# " + note.title.trimmingCharacters(in: .whitespacesAndNewlines)]
        parts.append("*" + stamp(note.createdAt) + "*")
        let text = body(note.attributed)
        if !text.isEmpty { parts.append(text) }
        return parts.joined(separator: "\n\n") + "\n"
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Localization.shared.resolved.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMMM yyyy HH:mm")
        return formatter.string(from: date)
    }

    /// Имя файла: дата впереди, чтобы папка сама собой сортировалась
    /// по времени, а не по первой букве названия.
    static func fileName(for note: Note) -> String {
        let formatter = DateFormatter()
        // Здесь локаль нарочно постоянная: имя файла — не текст для чтения,
        // а ключ сортировки, и «25 августа» в нём сортировалось бы по букве
        // «а», а не по месяцу.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let stamp = formatter.string(from: note.createdAt)
        let name = safe(note.title)
        return name.isEmpty ? "\(stamp).md" : "\(stamp)-\(name).md"
    }

    /// Убирает из имени всё, чем файловая система подавится.
    ///
    /// Двоеточие — не придирка: в macOS оно разделитель пути в старом смысле,
    /// и Finder показывает такое имя с косой чертой вместо него. А имя
    /// заметки начинается как раз со времени, где двоеточие есть всегда.
    static func safe(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\n\t")
        let cleaned = title
            .components(separatedBy: forbidden)
            .joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return String(cleaned.prefix(60))
    }

    // MARK: - Тело

    static func body(_ text: NSAttributedString) -> String {
        let string = text.string as NSString
        guard string.length > 0 else { return "" }

        var lines: [String] = []
        var index = 0
        while index < string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: index, length: 0))
            // Из абзаца выкидывается его перевод строки: он разделитель,
            // а не содержимое, и в разметке ему места нет.
            var content = paragraph
            while content.length > 0,
                  let last = string
                      .substring(with: NSRange(location: NSMaxRange(content) - 1, length: 1))
                      .first,
                  last.isNewline {
                content.length -= 1
            }
            lines.append(line(in: text, range: content))
            index = NSMaxRange(paragraph)
            // Защита от топтания на месте: `paragraphRange` на пустом хвосте
            // возвращает нулевую длину, и цикл иначе не кончился бы.
            if paragraph.length == 0 { break }
        }

        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
    }

    private static func line(in text: NSAttributedString, range: NSRange) -> String {
        guard range.length > 0 else { return "" }

        let isHeading = fontSize(in: text, at: range.location) >= Note.headingFontSize
        var result = ""
        text.enumerateAttributes(in: range) { attributes, subrange, _ in
            result += run(text.attributedSubstring(from: subrange).string, attributes: attributes)
        }
        // Заголовок вторым уровнем, а не первым: первый занят названием
        // самой заметки, и два `#` подряд читались бы как два названия.
        return isHeading ? "## " + result : result
    }

    /// Один кусок текста с одинаковым оформлением.
    ///
    /// Маркеры навешиваются только на непробельную часть: `** **` разметкой
    /// не считается ни одним разборщиком, и такой кусок вылез бы в файл
    /// звёздочками.
    private static func run(_ text: String, attributes: [NSAttributedString.Key: Any]) -> String {
        guard !text.isEmpty else { return "" }

        let core = text.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty else { return text }
        let leading = String(text.prefix(while: { $0 == " " }))
        let trailing = String(String(text.reversed()).prefix(while: { $0 == " " }))

        var marked = core
        if let font = attributes[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            // Заголовок жирный по определению — звёздочки внутри `##`
            // были бы шумом.
            let isHeading = font.pointSize >= Note.headingFontSize
            let bold = traits.contains(.bold) && !isHeading
            let italic = traits.contains(.italic)
            if bold, italic {
                marked = "***" + marked + "***"
            } else if bold {
                marked = "**" + marked + "**"
            } else if italic {
                marked = "*" + marked + "*"
            }
        }
        if let url = link(from: attributes[.link]) {
            marked = "[" + marked + "](" + url.absoluteString + ")"
        }
        return leading + marked + trailing
    }

    /// Ссылка приходит то `URL`, то строкой — `NSTextView` кладёт то,
    /// что нашёл сам, а мы кладём `URL`.
    private static func link(from value: Any?) -> URL? {
        if let url = value as? URL { return url }
        if let string = value as? String { return URL(string: string) }
        return nil
    }

    private static func fontSize(in text: NSAttributedString, at location: Int) -> CGFloat {
        guard location < text.length,
              let font = text.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        else { return Note.bodyFontSize }
        return font.pointSize
    }
}
