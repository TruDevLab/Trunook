import Foundation

/// Значки, из которых выбирают для команды.
///
/// Готовый набор, а не поле для имени символа. Имя пришлось бы знать наизусть
/// («text.badge.checkmark»), опечатка в нём давала бы пустое место в строке
/// под чёлкой, а свериться было бы негде: приложение SF Symbols ставится
/// вместе с Xcode, которого на этой машине нет.
///
/// Набор подобран по делу, а не по красоте: здесь то, чем помечают работу
/// с текстом, переводом, кодом и файлами. Порядок смысловой, не алфавитный:
/// в палитре ищут глазами по группам.
enum CommandSymbols {
    static let all: [String] = [
        // Текст и правка
        "text.badge.checkmark",
        "text.alignleft",
        "text.quote",
        "textformat",
        "pencil",
        "wand.and.stars",
        "sparkles",

        // Язык и смысл
        "character.book.closed",
        "globe",
        "quote.bubble",
        "bubble.left.and.bubble.right",

        // Списки и разбор
        "list.bullet.rectangle",
        "list.number",
        "checklist",
        "tablecells",

        // Код и данные
        "chevron.left.forwardslash.chevron.right",
        "terminal",
        "function",
        "number",

        // Работа с записями
        "tray.and.arrow.down",
        "square.and.pencil",
        "bookmark",
        "tag",
        "paperclip",

        // Файлы и места
        "folder",
        "doc.text",
        "link",
        "app.badge",
        "square.stack.3d.up.fill",
        "applescript",

        // Оценка и итог
        "magnifyingglass",
        "questionmark.circle",
        "exclamationmark.bubble",
        "lightbulb",
        "brain",
        "graduationcap",
    ]
}
