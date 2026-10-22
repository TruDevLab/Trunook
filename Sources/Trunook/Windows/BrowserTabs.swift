import TrunookXPC
import AppKit
import CoreServices

/// Вкладки браузеров через их словари AppleScript.
///
/// Умеют Safari, браузеры на Chromium и Arc — у них словарь одного устройства:
/// окна с номером, вкладки с заголовком, выбранная вкладка. У Arc номер
/// окна — строка, а выбранная вкладка — сама вкладка, не её место. Firefox
/// вкладок через AppleScript не отдаёт вовсе — у его окон переключатель
/// показывает только само окно.
///
/// Разрешение «Автоматизация» спрашивается заранее и без окна
/// (`AEDeterminePermissionToAutomateTarget`): первый же запрос к браузеру
/// иначе вывел бы системный вопрос посреди ⌘Tab, пока ⌘ держат. Не спрошено —
/// переключатель предлагает ↓, и вопрос задаётся уже после закрытия.
enum BrowserTabs {
    enum Family: Equatable {
        case safari
        case chromium
        case arc
    }

    /// Окно браузера, как его отдал AppleScript.
    struct Window: Equatable {
        /// Номер окна в словаре браузера. У Arc это строка, у остальных —
        /// число, но и его держим строкой: так одна дорога на всех.
        let id: String
        let name: String
        let active: Int
        let tabs: [BrowserTab]
    }

    enum Result: Equatable {
        case windows([Window])
        case needsConsent
        case denied
        case failed

        /// Для журнала.
        var summary: String {
            switch self {
            case let .windows(windows):
                return "окон \(windows.count), вкладок \(windows.reduce(0) { $0 + $1.tabs.count })"
            case .needsConsent: return "разрешение ещё не спрошено"
            case .denied: return "доступ закрыт"
            case .failed: return "не ответил"
            }
        }
    }

    static func family(of bundleID: String) -> Family? {
        switch bundleID {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            return .safari
        case "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
             "org.chromium.Chromium", "com.microsoft.edgemac", "com.microsoft.edgemac.Beta",
             "com.brave.Browser", "com.vivaldi.Vivaldi", "ru.yandex.desktop.yandex-browser":
            return .chromium
        case "company.thebrowser.Browser":
            return .arc
        default:
            return nil
        }
    }

    /// NSAppleScript не потокобезопасен — все обращения на одной очереди.
    /// На главном их держать нельзя: браузер с сотней вкладок отвечает
    /// за десятые доли секунды.
    private static let queue = DispatchQueue(label: "com.trunook.browser-tabs", qos: .userInitiated)

    /// Вкладки всех окон браузера. Ответ — на главном потоке.
    static func load(bundleID: String, completion: @escaping (Result) -> Void) {
        guard let family = family(of: bundleID) else { return completion(.failed) }
        queue.async {
            let result = fetch(bundleID: bundleID, family: family)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func fetch(bundleID: String, family: Family) -> Result {
        switch consent(bundleID: bundleID, ask: false) {
        case noErr: break
        case OSStatus(errAEEventWouldRequireUserConsent): return .needsConsent
        case OSStatus(errAEEventNotPermitted): return .denied
        case let status:
            DebugLog.write("вкладки: \(bundleID) — разрешение не проверить, \(status)")
            return .failed
        }
        let start = CFAbsoluteTimeGetCurrent()
        var error: NSDictionary?
        guard let script = NSAppleScript(source: listSource(bundleID: bundleID, family: family)) else { return .failed }
        let output = script.executeAndReturnError(&error)
        if let error {
            DebugLog.write("вкладки: \(bundleID) — \(error[NSAppleScript.errorMessage] ?? error)")
            return .failed
        }
        let windows = parse(output.stringValue ?? "")
        DebugLog.write(String(format: "вкладки: %@ — окон %d, вкладок %d за %.0f мс", bundleID, windows.count,
                              windows.reduce(0) { $0 + $1.tabs.count }, (CFAbsoluteTimeGetCurrent() - start) * 1000))
        return .windows(windows)
    }

    /// Сделать вкладку выбранной в своём окне. Окно поднимает уже
    /// переключатель — Универсальным доступом, как и всякое окно.
    static func select(bundleID: String, windowID: String, tab: Int, then: @escaping () -> Void) {
        guard let family = family(of: bundleID), let source = selectSource(bundleID: bundleID, family: family,
                                                                           windowID: windowID, tab: tab) else {
            return then()
        }
        queue.async {
            var error: NSDictionary?
            _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                DebugLog.write("вкладки: выбрать не вышло — \(error[NSAppleScript.errorMessage] ?? error)")
            }
            DispatchQueue.main.async(execute: then)
        }
    }

    /// Задать системный вопрос о разрешении. Зовётся, когда переключатель
    /// уже закрыт: окно вопроса ждёт ответа человека.
    static func requestConsent(bundleID: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let status = consent(bundleID: bundleID, ask: true)
            DebugLog.write("вкладки: \(bundleID) — разрешение \(status == noErr ? "дано" : "не дано (\(status))")")
        }
    }

    private static func consent(bundleID: String, ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return OSStatus(procNotFound) }
        return AEDeterminePermissionToAutomateTarget(desc, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
    }

    // MARK: - Запрос и разбор

    /// Разделители — управляющие символы 31 и 30: в заголовке страницы
    /// их не бывает, а табуляция и перевод строки — бывают.
    static let field: Character = "\u{1F}"
    static let record: Character = "\u{1E}"

    /// Все окна разом: номер, заголовок, выбранная вкладка, заголовки вкладок.
    /// Окно без вкладок — настройки, загрузки — молча пропускается.
    static func listSource(bundleID: String, family: Family) -> String {
        let tabs: String
        let active: String
        switch family {
        case .safari:
            tabs = "name of every tab of w"
            active = "set k to index of current tab of w"
        case .chromium:
            tabs = "title of every tab of w"
            active = "set k to active tab index of w"
        case .arc:
            // Выбранная вкладка — объект, место её ищется по номеру.
            tabs = "title of every tab of w"
            active = """
            set k to 0
                            set activeID to id of active tab of w
                            set ids to id of every tab of w
                            repeat with i from 1 to count of ids
                                if item i of ids is activeID then set k to i
                            end repeat
            """
        }
        return """
        tell application id "\(bundleID)"
            set us to character id 31
            set rs to character id 30
            set out to ""
            set saved to AppleScript's text item delimiters
            set AppleScript's text item delimiters to us
            repeat with w in windows
                try
                    set titles to \(tabs)
                    \(active)
                    set out to out & ((id of w) as text) & us & (name of w) & us & (k as text) & us & (titles as text) & rs
                end try
            end repeat
            set AppleScript's text item delimiters to saved
            return out
        end tell
        """
    }

    /// Запрос выбора вкладки. Номер окна пришёл из ответа браузера, но в текст
    /// скрипта он вставляется — поэтому пропускаем только буквы, цифры
    /// и дефис: чужой заголовок или кавычка до скрипта не дойдут.
    static func selectSource(bundleID: String, family: Family, windowID: String, tab: Int) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard !windowID.isEmpty, windowID.unicodeScalars.allSatisfy(allowed.contains), tab > 0 else { return nil }
        switch family {
        case .safari:
            guard Int(windowID) != nil else { return nil }
            return """
            tell application id "\(bundleID)" to set current tab of window id \(windowID) \
            to tab \(tab) of window id \(windowID)
            """
        case .chromium:
            guard Int(windowID) != nil else { return nil }
            return """
            tell application id "\(bundleID)" to set active tab index of window id \(windowID) to \(tab)
            """
        case .arc:
            return """
            tell application id "\(bundleID)" to tell tab \(tab) of window id "\(windowID)" to select
            """
        }
    }

    static func parse(_ output: String) -> [Window] {
        output.split(separator: record, omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: field, omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 4, !parts[0].isEmpty, let active = Int(parts[2]) else { return nil }
            let id = parts[0]
            let tabs = parts[3...].enumerated().map { offset, title in
                BrowserTab(index: offset + 1, title: title.isEmpty ? t("Без названия") : title)
            }
            return Window(id: id, name: parts[1], active: active, tabs: tabs)
        }
    }

    /// Вкладки — к окнам переключателя.
    ///
    /// Окна сличаются по заголовку: у обоих браузеров заголовок окна —
    /// заголовок выбранной вкладки, и Универсальный доступ отдаёт тот же.
    /// Не сошлось — по порядку: AppleScript, как и CoreGraphics, перечисляет
    /// окна спереди назад. `titles` — заголовки окон этого браузера
    /// в порядке переключателя.
    static func match(_ result: Result, to titles: [String]) -> [SwitcherTabs] {
        switch result {
        case .needsConsent: return titles.map { _ in .needsConsent }
        case .denied: return titles.map { _ in .denied }
        case .failed: return titles.map { _ in .unavailable }
        case let .windows(windows):
            var free = windows
            var picked: [Window?] = titles.map { title in
                guard let index = free.firstIndex(where: { $0.name == title }) else { return nil }
                return free.remove(at: index)
            }
            for index in picked.indices where picked[index] == nil {
                let title = titles[index]
                if let near = free.firstIndex(where: {
                    !$0.name.isEmpty && (title.contains($0.name) || $0.name.contains(title))
                }) {
                    picked[index] = free.remove(at: near)
                } else if !free.isEmpty {
                    picked[index] = free.removeFirst()
                }
            }
            return picked.map { window in
                guard let window, !window.tabs.isEmpty else { return .unavailable }
                return .loaded(windowID: window.id, tabs: window.tabs, active: window.active)
            }
        }
    }
}
