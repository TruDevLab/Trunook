import AppKit
import Foundation

/// Одна заметка.
///
/// Оформленный текст лежит в `rtf`, он же и есть содержимое. Рядом — тот же
/// текст без оформления, и это не дублирование по недосмотру: `plain` нужен
/// на каждый сбор контекста для модели и на каждую строку списка, а разбирать
/// RTF ради двух строк предпросмотра — работа на пустом месте, да ещё и
/// в главном потоке.
struct Note: Identifiable, Equatable {
    /// Откуда заметка взялась. Влияет на значок в списке и на промт
    /// именования: ответ модели уже связный текст, а набранное руками —
    /// чаще обрывок.
    enum Origin: String {
        case typed
        case assistant

        var symbol: String {
            switch self {
            case .typed: return "square.and.pencil"
            case .assistant: return "sparkles"
            }
        }
    }

    var id: Int64
    var title: String
    var rtf: Data
    var plain: String
    var createdAt: Date
    var updatedAt: Date
    var origin: Origin
    /// Имя придумала модель, а не запасной расчёт. По этому признаку видно,
    /// какие заметки ещё ждут своего имени, — и их можно переименовать
    /// позже, когда Ollama включат.
    var titleByModel: Bool

    /// Ещё не записанная заметка. Идентификатор назначит база.
    static let unsaved: Int64 = 0

    var isSaved: Bool { id != Self.unsaved }

    // MARK: - Кегли

    /// Размеры текста заметки.
    ///
    /// Живут здесь, а не в вёрстке, потому что это свойство **формата**,
    /// а не панели: по кеглю заголовок и опознаётся — и когда его набирают
    /// в поле, и когда заметку выгружают в Markdown. Разъедься эти два
    /// числа, и выгрузка перестала бы видеть заголовки, оставаясь при этом
    /// внешне исправной.
    ///
    /// Мельче, чем в телесуфлере: тот читают с расстояния, а заметку —
    /// с обычного.
    static let bodyFontSize: CGFloat = 13
    static let headingFontSize: CGFloat = 18

    // MARK: - Текст

    var attributed: NSAttributedString {
        NSAttributedString(rtf: rtf, documentAttributes: nil) ?? NSAttributedString(string: plain)
    }

    /// Однострочное представление для списка: переносы в узкой строке всё
    /// равно не видны, а из-за них строка выглядит обрезанной на полуслове.
    var oneLine: String {
        Self.oneLine(from: plain)
    }

    static func oneLine(from text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    // MARK: - Сложенный текст для поиска

    /// Имя и текст вместе, приведённые к нижнему регистру.
    ///
    /// Хранится отдельной колонкой, и это единственный способ искать
    /// по-русски: встроенный в SQLite `LIKE` складывает регистр **только
    /// для латиницы** — «Привет» по запросу «привет» он не находит. Своей
    /// функции складывания в SQLite не зарегистрировать без сторонней сборки,
    /// поэтому складываем в Swift на записи, а запрос — тем же вызовом.
    ///
    /// Ищем и по имени тоже: имя придумывает модель по содержанию, и нередко
    /// нужное слово есть именно в нём, а в тексте стоит синоним.
    static func folded(title: String, plain: String) -> String {
        (title + "\n" + plain).folded
    }

    var folded: String { Self.folded(title: title, plain: plain) }
}

extension String {
    /// Строка для сравнения без оглядки на регистр и диакритику.
    ///
    /// `folding` с локалью, а не `lowercased()`: у турецкой «i» правила свои,
    /// и складывание без учёта языка ломает поиск ровно у тех, кто пишет
    /// на нём.
    var folded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
