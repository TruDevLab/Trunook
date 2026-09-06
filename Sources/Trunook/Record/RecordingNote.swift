import AppKit
import Foundation

/// Собирает заметку из записанного разговора.
///
/// Чистая функция под тестом: порядок частей, кегли заголовков и вид ссылки
/// на аудио — это ровно то, от чего зависит, переживёт ли заметка круг
/// «приложение → файл хранилища → приложение». Проверять это на живой записи
/// значило бы ждать час ради одной строки.
enum RecordingNote {
    /// Части заметки идут в одном порядке всегда.
    ///
    /// Пересказ первым, потому что читают заметку ради него; задачи вторыми,
    /// потому что за ними возвращаются; расшифровка последней — в неё лезут
    /// редко и нарочно.
    ///
    /// **Ссылки на запись в тексте нет.** Первая попытка ставила сюда
    /// `![[запись.m4a]]`, и в вырезе это выглядело ровно так, как написано:
    /// голой разметкой, по которой ничего не сыграешь. Путь к записи лежит
    /// отдельным полем заметки; в файл хранилища его вставляет
    /// `ObsidianMarkdown` блоком между метками, а в вырезе на его месте
    /// стоит кнопка воспроизведения.
    static func text(
        summary: RecordingSummary?,
        transcript: String
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()

        if let overview = summary?.summary, !overview.isEmpty {
            append(overview, to: result)
        }

        if let tasks = summary?.tasks, !tasks.isEmpty {
            appendHeading(t("Задачи"), to: result)
            // Чек-бокс строкой, а не оформлением: своего чек-листа
            // у заметки нет, зато `- [ ]` понимает Obsidian, и обратный
            // разбор оставляет такую строку текстом — круг её не теряет.
            for task in tasks {
                append("- [ ] " + task, to: result)
            }
        }

        let spoken = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !spoken.isEmpty {
            appendHeading(t("Расшифровка"), to: result)
            append(spoken, to: result)
        }

        return result
    }

    // MARK: - Сборка

    private static func append(_ line: String, to result: NSMutableAttributedString) {
        if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
        result.append(NSAttributedString(string: line, attributes: bodyAttributes))
    }

    /// Заголовок раздела.
    ///
    /// Кеглем, а не разметкой: по кеглю `NoteMarkdown` и опознаёт заголовок,
    /// когда выгружает заметку в файл. Пустая строка перед ним — воздух,
    /// без которого разделы слипаются в одну простыню.
    private static func appendHeading(_ title: String, to result: NSMutableAttributedString) {
        if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
        append(title, to: result)
        let length = (title as NSString).length
        result.setAttributes(
            headingAttributes,
            range: NSRange(location: result.length - length, length: length)
        )
    }

    /// Оформление своё, а не системное: чёрный текст на чёрной панели
    /// попросту не виден, а поменять его в заметке нечем.
    private static var bodyAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: Note.bodyFontSize),
            .foregroundColor: NSColor.white,
        ]
    }

    private static var headingAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: Note.headingFontSize, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
    }
}
