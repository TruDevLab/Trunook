import AppKit
import Foundation

/// Сводка наружу: файлом Markdown и заметкой.
///
/// Два представления одного содержимого рядом, чтобы не разойтись: что есть
/// в файле, то есть и в заметке, и в том же порядке.
enum DigestExport {
    // MARK: - Markdown

    static func markdown(for digest: Digest) -> String {
        var parts = ["# " + noteTitle(for: digest)]
        parts.append("*" + tf("Новости с %@", stamp(digest.since)) + "*")
        for section in digest.sections {
            var block = ["## " + escaped(section.title)]
            if section.failed {
                block.append("_" + t("Не удалось собрать") + "_")
            } else if section.entries.isEmpty {
                block.append("_" + t("Ничего значимого за период") + "_")
            } else {
                for entry in section.entries {
                    var line = "- [\(escaped(entry.title))](\(entry.link.absoluteString))"
                    line += " — \(escaped(entry.source)), \(stamp(entry.published))"
                    block.append(line)
                    let summary = entry.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !summary.isEmpty { block.append("  " + escaped(summary)) }
                }
            }
            parts.append(block.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n") + "\n"
    }

    /// Квадратные скобки в заголовке сломали бы ссылку `[…](…)`.
    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }

    static func fileName(for digest: Digest) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "\(formatter.string(from: digest.createdAt))-\(NoteMarkdown.safe(t("Сводка"))).md"
    }

    static func noteTitle(for digest: Digest) -> String {
        tf("Сводка — %@", stamp(digest.createdAt))
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Localization.shared.resolved.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMMM HH:mm")
        return formatter.string(from: date)
    }

    // MARK: - Заметка

    /// Тело заметки: темы заголовками, новости ссылками.
    ///
    /// Оформление атрибутами, а не разметкой в тексте: заметки хранят
    /// оформленный текст, и `NoteMarkdown` при выгрузке узнаёт заголовок
    /// по кеглю, а ссылку — по атрибуту `.link`. Звёздочки в тексте так
    /// и остались бы звёздочками.
    static func attributed(for digest: Digest) -> NSAttributedString {
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: Note.bodyFontSize),
            .foregroundColor: NSColor.white,
        ]
        var heading = body
        heading[.font] = NSFont.systemFont(ofSize: Note.headingFontSize, weight: .semibold)
        var muted = body
        muted[.foregroundColor] = NSColor.white.withAlphaComponent(0.6)

        let text = NSMutableAttributedString()
        for (index, section) in digest.sections.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "\n", attributes: body)) }
            text.append(NSAttributedString(string: section.title + "\n", attributes: heading))
            if section.failed {
                text.append(NSAttributedString(string: t("Не удалось собрать") + "\n", attributes: muted))
                continue
            }
            if section.entries.isEmpty {
                text.append(NSAttributedString(string: t("Ничего значимого за период") + "\n", attributes: muted))
                continue
            }
            for entry in section.entries {
                var link = body
                link[.link] = entry.link
                text.append(NSAttributedString(string: entry.title, attributes: link))
                text.append(NSAttributedString(
                    string: " — \(entry.source), \(stamp(entry.published))\n", attributes: muted
                ))
                let summary = entry.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !summary.isEmpty {
                    text.append(NSAttributedString(string: summary + "\n", attributes: body))
                }
            }
        }
        return text
    }
}
