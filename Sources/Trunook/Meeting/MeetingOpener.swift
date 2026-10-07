import TrunookXPC
import AppKit
import Security

/// Та же встреча — ссылкой для приложения сервиса, без браузера.
///
/// Перенесено из Trudaybook (`MeetingLink.nativeApp`) без изменений логики:
/// подключение в обоих приложениях должно вести себя одинаково.
extension MeetingLink {
    struct NativeApp: Equatable {
        /// Ссылка в схеме приложения (`zoommtg:`, `msteams:`, `telemost:`).
        let url: URL
        /// Кому её можно отдать: требование к подписи программы. Схему
        /// может перехватить любая программа — ссылку с паролем встречи
        /// получит только подписанная самим сервисом.
        let requirement: String
    }

    /// Ссылка для приложения — Zoom, Teams и Телемост: их схемы известны и
    /// принимают ту же встречу. У остальных `nil` — откроется браузер.
    /// Хост сверяется строго (`zoom.us` или `*.zoom.us`), а не «содержит»:
    /// `zoom.us.example.com` сюда не пройдёт.
    var nativeApp: NativeApp? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased() else { return nil }
        func under(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        guard host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }) else { return nil }

        if under("zoom.us") || under("zoom.com") {
            // /j/<номер> — встреча, /w/<номер> — вебинар.
            let parts = components.path.split(separator: "/")
            guard parts.count == 2, parts[0] == "j" || parts[0] == "w",
                  let number = parts.last, (9...13).contains(number.count),
                  number.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            var target = URLComponents()
            target.scheme = "zoommtg"
            target.host = host
            target.path = "/join"
            var query = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: String(number))]
            if let password = components.queryItems?.first(where: { $0.name == "pwd" })?.value {
                // Пароль — как его пишет Zoom; всё прочее из ссылки не передаём.
                guard password.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-") }) else { return nil }
                query.append(URLQueryItem(name: "pwd", value: password))
            }
            target.queryItems = query
            return target.url.map {
                NativeApp(url: $0, requirement: #"identifier "us.zoom.xos" and anchor apple generic and certificate leaf[subject.OU] = "BJ4HAAB9B3""#)
            }
        }
        if host == "teams.microsoft.com" {
            // Приглашение Teams: путь и параметры те же, меняется только схема.
            let path = components.percentEncodedPath
            guard path.hasPrefix("/l/meetup-join/") else { return nil }
            var text = "msteams:" + path
            if let query = components.percentEncodedQuery { text += "?" + query }
            return URL(string: text).map {
                NativeApp(url: $0, requirement: #"(identifier "com.microsoft.teams2" or identifier "com.microsoft.teams") and anchor apple generic and certificate leaf[subject.OU] = "UBF8T346G9""#)
            }
        }
        if Self.telemostHosts.contains(host) {
            // Как передаёт сайт Телемоста его приложению (видно в журнале
            // приложения): `telemost://https//хост/j/номер` — без двоеточия.
            let parts = components.path.split(separator: "/")
            guard parts.count == 2, parts[0] == "j", let number = parts.last,
                  (6...20).contains(number.count), number.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return URL(string: "telemost://https//\(host)/j/\(number)").map {
                NativeApp(url: $0, requirement: #"identifier "ru.yandex.desktop.telemost" and anchor apple generic and certificate leaf[subject.OU] = "477EAT77S3""#)
            }
        }
        return nil
    }

    /// Адреса Телемоста — списком: по «содержит» прошёл бы чужой хост.
    private static let telemostHosts: Set<String> = [
        "telemost.yandex.ru", "telemost.360.yandex.ru", "telemost.yandex.com", "telemost.360.yandex.com",
    ]
}

/// «Подключиться»: встреча Zoom, Teams или Телемоста — сразу в их приложении,
/// мимо браузера с его «Открыть zoom.us?».
///
/// Ссылка в схеме приложения несёт номер и пароль встречи, а схему
/// (`zoommtg:`, `msteams:`) может объявить своей любая программа. Поэтому
/// ссылка уходит только той, что подписана самим сервисом (требование из
/// `MeetingLink.NativeApp`); нет такой — как раньше, в браузер.
enum MeetingOpener {
    static func open(_ url: URL) {
        guard let link = MeetingLink.extract(url: url, location: nil, notes: nil),
              let native = link.nativeApp,
              let app = trustedHandler(for: native)
        else {
            NSWorkspace.shared.open(url)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // Именно проверенной программе, а не «кому система отдаст схему».
        NSWorkspace.shared.open([native.url], withApplicationAt: app, configuration: configuration) { _, error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                DebugLog.write("встреча: приложение \(link.provider.rawValue) не открылось — в браузер")
                NSWorkspace.shared.open(url)
            }
        }
        DebugLog.write("встреча: в приложении \(link.provider.rawValue)")
    }

    /// Программа для схемы — если она подписана тем, кем должна.
    /// Ресурсы пакета не перепроверяем (это секунды на каждое нажатие):
    /// важно, чей исполняемый файл, а целостность пакета стережёт macOS.
    private static func trustedHandler(for native: MeetingLink.NativeApp) -> URL? {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: native.url) else { return nil }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(native.requirement as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return nil }
        let flags = SecCSFlags(rawValue: kSecCSDoNotValidateResources)
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            DebugLog.write("встреча: схему держит программа без подписи сервиса — в браузер")
            return nil
        }
        return app
    }
}
