import TrunookXPC
import Foundation

/// Язык интерфейса.
enum Language: String, CaseIterable, Identifiable {
    /// Как в системе. Отдельным значением, а не подстановкой при первом
    /// запуске: иначе смена языка системы перестала бы влиять на приложение.
    case system
    case ru
    case en
    case zh

    var id: String { rawValue }

    /// Название на своём же языке — так его узнают, даже когда интерфейс
    /// сейчас на чужом.
    var title: String {
        switch self {
        case .system: return t("Как в системе")
        case .ru: return "Русский"
        case .en: return "English"
        case .zh: return "中文"
        }
    }

    /// Папка с переводом в бандле.
    var folder: String? {
        switch self {
        case .system: return nil
        case .ru: return "ru"
        case .en: return "en"
        case .zh: return "zh-Hans"
        }
    }
}

/// Перевод интерфейса.
///
/// Ключ перевода — сам русский текст, а не условное имя вроде
/// `settings.general.title`. Причина практическая: половина ошибок
/// в переводах — это опечатка в ключе, которая тихо показывает сам ключ
/// вместо текста. С текстом в роли ключа худшее, что случится, — строка
/// останется по-русски, и это сразу видно. Так же устроен и стандартный
/// механизм Apple, где ключом служит строка на языке разработки.
///
/// Русского файла поэтому нет вовсе: для него ключ и есть ответ.
final class Localization: ObservableObject {
    static let shared = Localization()

    @Published private(set) var current: Language = .system

    private var table: [String: String] = [:]

    private init() {}

    /// Язык поменялся — перечитываем таблицу.
    ///
    /// Части интерфейса на AppKit — меню в строке состояния — заново себя
    /// не рисуют, поэтому о смене сообщаем уведомлением.
    func apply(_ language: Language) {
        current = language
        table = Self.load(language)
        DebugLog.write("язык интерфейса: \(resolved.rawValue), строк в таблице \(table.count)")
        NotificationCenter.default.post(name: .trunookLanguageChanged, object: nil)
    }

    /// Какой язык показывается на самом деле.
    var resolved: Language {
        current == .system ? Self.systemLanguage : current
    }

    func string(_ key: String) -> String {
        table[key] ?? key
    }

    // MARK: - Загрузка

    private static func load(_ language: Language) -> [String: String] {
        let target = language == .system ? systemLanguage : language
        guard let folder = target.folder, target != .ru else { return [:] }
        guard let url = Bundle.main.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: "\(folder).lproj"
        ) else {
            DebugLog.write("перевод: \(folder).lproj не найден в бандле")
            return [:]
        }
        guard let dictionary = NSDictionary(contentsOf: url) as? [String: String] else {
            DebugLog.write("перевод: \(folder).lproj не разобрался")
            return [:]
        }
        return dictionary
    }

    /// Язык системы, приведённый к тем трём, что мы умеем.
    ///
    /// Смотрим на список предпочитаемых языков целиком, а не только
    /// на первый: у человека с китайским вторым и, скажем, немецким первым
    /// китайский ближе, чем запасной английский.
    private static var systemLanguage: Language {
        for identifier in Locale.preferredLanguages {
            let code = identifier.lowercased()
            if code.hasPrefix("ru") { return .ru }
            if code.hasPrefix("zh") { return .zh }
            if code.hasPrefix("en") { return .en }
        }
        return .en
    }
}

extension Notification.Name {
    static let trunookLanguageChanged = Notification.Name("com.trunook.languageChanged")
}

/// Перевод строки.
///
/// Отдельная функция без вариативных аргументов, а не одна общая с `tf`:
/// `CVarArg...` заставляет вывод типов Swift перебирать варианты на каждом
/// вызове, а этих вызовов в вёрстке сотни. С общей функцией сборка одного
/// только окна настроек уходила в минуты.
func t(_ key: String) -> String {
    Localization.shared.string(key)
}

/// Перевод строки с подстановкой: `tf("%d мин", minutes)`.
func tf(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: Localization.shared.string(key), arguments: arguments)
}
