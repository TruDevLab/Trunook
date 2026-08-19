import Foundation

/// Быстрая команда — один из шести слотов меню.
struct QuickCommand: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case shortcut
        case ollama
        case openApp
        case openPath
        case openURL
        case appleScript

        var title: String {
            switch self {
            case .shortcut: return t("Команда из «Команд»")
            case .ollama: return t("Запрос к модели")
            case .openApp: return t("Открыть приложение")
            case .openPath: return t("Открыть файл или папку")
            case .openURL: return t("Открыть ссылку")
            case .appleScript: return t("Скрипт AppleScript")
            }
        }

        var defaultSymbol: String {
            switch self {
            case .shortcut: return "square.stack.3d.up.fill"
            case .ollama: return "sparkles"
            case .openApp: return "app.badge"
            case .openPath: return "folder"
            case .openURL: return "link"
            case .appleScript: return "applescript"
            }
        }
    }

    let id: Int
    var title: String
    var kind: Kind
    /// Промт, текст скрипта, путь к приложению или путь к папке.
    var payload: String
    var symbol: String
    var isEnabled: Bool
    /// Своё сочетание. nil — слот запускается только из меню.
    var hotKey: HotKeySpec?
    /// Передавать ли выделенный текст на вход. Для команд из «Команд»:
    /// многие из них работают с текстом, а многие — сами по себе.
    var passesSelection: Bool = false
    /// В каком браузере открывать ссылку. `nil` — в браузере по умолчанию.
    ///
    /// Необязательное поле намеренно: у синтезированного `Decodable`
    /// значения по умолчанию не работают, а вот отсутствующий ключ
    /// необязательного свойства читается как `nil`. Иначе слоты, сохранённые
    /// прошлой версией, перестали бы разбираться целиком.
    var browserBundleID: String?

    /// Пустой слот: показывается в меню как место под команду.
    static func empty(id: Int) -> QuickCommand {
        QuickCommand(
            id: id,
            title: "",
            kind: .ollama,
            payload: "",
            symbol: "",
            isEnabled: false,
            hotKey: HotKeySpec.slot(id)
        )
    }

    var isConfigured: Bool {
        isEnabled && !title.isEmpty && !payload.isEmpty
    }

    var effectiveSymbol: String {
        symbol.isEmpty ? kind.defaultSymbol : symbol
    }

    /// Подстановка выделенного текста в промт.
    ///
    /// Если места подстановки нет, текст дописывается снизу: иначе команда,
    /// заданная одной фразой вроде «переведи на английский», молча теряла бы
    /// то, к чему её применяют.
    /// Разбирает ссылку из того, что вписал человек.
    ///
    /// Схему дописываем сами: адрес обычно копируют или набирают без неё,
    /// а `NSWorkspace` без схемы такую строку не откроет.
    static func webURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        return URL(string: "https://" + trimmed)
    }

    func prompt(with selection: String) -> String {
        let marker = "{{selection}}"
        guard payload.contains(marker) else {
            return selection.isEmpty ? payload : "\(payload)\n\n\(selection)"
        }
        return payload.replacingOccurrences(of: marker, with: selection)
    }
}

/// Шесть слотов быстрых команд.
///
/// Число фиксировано намеренно: меню вызывается вслепую, по памяти, и растущий
/// список сводил бы на нет саму идею — попасть в нужное действие не глядя.
enum QuickCommands {
    static let slotCount = 6

    static func load(from defaults: UserDefaults) -> [QuickCommand] {
        guard let data = defaults.data(forKey: "quickCommands"),
              let stored = try? JSONDecoder().decode([QuickCommand].self, from: data)
        else { return defaults0 }

        // Число слотов могло измениться между версиями — приводим к текущему.
        var commands = (0..<slotCount).map { index in
            stored.first { $0.id == index } ?? .empty(id: index)
        }
        if migrateLegacyHotKeys(&commands, in: defaults) {
            save(commands, to: defaults)
        }
        return commands
    }

    /// Ключ, которым помечен состоявшийся перенос сочетаний.
    private static let migrationKey = "quickCommandHotKeysMigrated"

    /// Переносит нетронутые сочетания слотов с ⌥⌘ на ⌃⌥.
    ///
    /// До 0.6.0 слоты сидели на ⌥⌘ с цифрами, остальное приложение — на ⌃⌥.
    /// Сменить умолчание оказалось мало: у всех, кто уже запускал приложение,
    /// набор лежит в настройках со старыми сочетаниями, и меню функций честно
    /// показывало ⌥⌘1, пока рядом стояли ⌃⌥C и ⌃⌥V. Выглядело это как
    /// недоделка, а не как чужой выбор.
    ///
    /// Переносится только то, чего человек не касался: сочетание, совпадающее
    /// со старым умолчанием **своего** слота. Заданное вручную остаётся как
    /// есть. Отметка в настройках нужна, чтобы перенос случился однажды —
    /// иначе он молча переписывал бы выбор того, кто нарочно вернул ⌥⌘1.
    private static func migrateLegacyHotKeys(
        _ commands: inout [QuickCommand],
        in defaults: UserDefaults
    ) -> Bool {
        guard !defaults.bool(forKey: migrationKey) else { return false }
        defaults.set(true, forKey: migrationKey)

        var changed = false
        for index in commands.indices {
            let command = commands[index]
            guard let hotKey = command.hotKey,
                  hotKey == HotKeySpec.legacySlot(command.id),
                  let fresh = HotKeySpec.slot(command.id)
            else { continue }
            commands[index].hotKey = fresh
            changed = true
        }
        return changed
    }

    static func save(_ commands: [QuickCommand], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(commands) else { return }
        defaults.set(data, forKey: "quickCommands")
    }

    /// Заготовки при первом запуске: показывают, что вообще умеет меню.
    private static var defaults0: [QuickCommand] {
        [
            QuickCommand(
                id: 0,
                title: t("Исправить ошибки"),
                kind: .ollama,
                payload: t("Исправь орфографию и пунктуацию. Верни только исправленный текст, без пояснений.\n\n{{selection}}"),
                symbol: "text.badge.checkmark",
                isEnabled: true,
                hotKey: HotKeySpec.slot(0)
            ),
            QuickCommand(
                id: 1,
                title: t("Перевести на русский"),
                kind: .ollama,
                payload: t("Переведи на русский. Верни только перевод.\n\n{{selection}}"),
                symbol: "character.book.closed",
                isEnabled: true,
                hotKey: HotKeySpec.slot(1)
            ),
            QuickCommand(
                id: 2,
                title: t("Кратко пересказать"),
                kind: .ollama,
                payload: t("Перескажи кратко, тремя пунктами.\n\n{{selection}}"),
                symbol: "list.bullet.rectangle",
                isEnabled: true,
                hotKey: HotKeySpec.slot(2)
            ),
            .empty(id: 3),
            .empty(id: 4),
            .empty(id: 5),
        ]
    }
}
