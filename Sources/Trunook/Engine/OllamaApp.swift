import AppKit
import Foundation
import TrunookXPC

/// Где на машине искать Ollama, чем её опознать и как запустить.
///
/// **Главное правило: порт старше бандла.** Отвечающий порт означает, что
/// движок уже работает, и дальше спрашивать не о чем — откуда он взялся,
/// нас не касается. Из этого само собой выходит самое важное требование:
/// уже работающая Ollama подхватывается и никогда не переставляется, будь
/// она из Homebrew, из docker или запущена руками.
enum OllamaApp {
    /// След от Electron в имени — так и есть, менять его не нам.
    static let bundleID = "com.electron.ollama"

    /// Владелец подписи: `Infra Technologies, Inc`.
    ///
    /// Зашито нарочно: иначе мы копировали бы в «Программы» всё, что
    /// пришло по этой ссылке. Но имя владельца у Ollama уже менялось
    /// однажды, и в день, когда оно сменится снова, установка начнёт
    /// отказывать. Отказ не тупик — образ показывается в Finder, — но
    /// причину искать надо здесь, и `engineVerify` говорит её одной строкой.
    static let teamID = "3MU9H2V9Y9"

    /// Требование к подписи скачанного.
    ///
    /// Нотаризация плюс имя владельца: первое проверяет, что Apple видела
    /// этот код, второе — что код именно Ollama. По отдельности ни того,
    /// ни другого не хватает.
    static let requirement = "anchor apple generic and identifier \"\(bundleID)\""
        + " and certificate leaf[subject.OU] = \"\(teamID)\" and notarized"

    /// Постоянная ссылка на образ. Ведёт переходами на релиз в GitHub.
    ///
    /// Минуя GitHub API нарочно: у него потолок в шестьдесят запросов
    /// в час на адрес, а эта ссылка отдаёт и размер в заголовке, и сам образ.
    static let imageURL = URL(string: "https://ollama.com/download/Ollama.dmg")!

    /// Страница для тех случаев, когда дальше человек ставит сам.
    static let page = URL(string: "https://ollama.com")!

    /// Команда для тех, у кого Homebrew.
    static let serveCommand = "ollama serve"

    /// Потолок ожидания порта.
    static let ceiling: TimeInterval = 60

    /// Где искать утилиту, если бандла нет.
    static let cliPaths = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]

    // MARK: - Поиск

    /// Что нашлось на диске. Порт здесь не спрашивается: это дело движка.
    static func installed() -> OllamaInstall? {
        if let bundle = bundle() { return .app(bundle) }
        for path in cliPaths {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            if let install = classify(cli: url, resolved: url.resolvingSymlinksInPath()) {
                return install
            }
        }
        return nil
    }

    /// Бандл приложения, где бы он ни лежал.
    ///
    /// Сначала спрашиваем Launch Services: приложение может лежать
    /// в `~/Applications` или вообще где угодно. И только потом — прямые
    /// пути: Launch Services отвечает с запозданием в те самые секунды
    /// после того, как мы сами положили бандл, и сказать «не установлена»
    /// про только что записанное нельзя.
    static func bundle() -> URL? {
        if let known = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return known
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: "/Applications/Ollama.app"),
            home.appendingPathComponent("Applications/Ollama.app"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Чем окажется найденная утилита.
    ///
    /// Чистая, и в этом вся польза: на машине разработчика
    /// `/usr/local/bin/ollama` — это **симлинк внутрь бандла**, который
    /// Ollama делает сама своим шагом «установить утилиту». Считать такую
    /// находку установкой через Homebrew значило бы показать совет
    /// запустить `ollama serve` там, где надо просто открыть приложение.
    static func classify(cli: URL, resolved: URL) -> OllamaInstall? {
        let path = resolved.path
        guard let range = path.range(of: ".app/Contents") else {
            return .brew(cli)
        }
        let bundle = String(path[path.startIndex..<range.lowerBound]) + ".app"
        return .app(URL(fileURLWithPath: bundle))
    }

    // MARK: - Адрес

    /// Местный ли адрес движка.
    ///
    /// Тому, кто указал Ollama на другую машину, предлагать местную
    /// установку нельзя: он получит второй движок, которого не просил,
    /// а тот, с которым он работает, никуда не денется.
    ///
    /// Пустой адрес — местный: `Settings.apiURL(for:)` подставляет вместо
    /// него `defaultOllamaURL`.
    static func isLocalAddress(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        guard let host = URL(string: text)?.host?.lowercased() else {
            // Не разобралось — пусть считается местным: отказать человеку
            // в установке из-за опечатки в адресе хуже, чем предложить её
            // лишний раз.
            return true
        }
        return ["localhost", "127.0.0.1", "::1", "0.0.0.0"].contains(host)
    }

    /// Что показать в строке про чужой адрес.
    static func host(of raw: String) -> String {
        URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? raw
    }

    // MARK: - Запуск

    /// Сколько ждать перед следующим опросом порта. `nil` — время вышло.
    ///
    /// Полсекунды на первые десять попыток и по секунде дальше: поднимается
    /// Ollama обычно за пару секунд, но при первом запуске открывает своё
    /// окно и просит права на свою утилиту — и тогда ждать приходится,
    /// пока человек в нём закончит.
    ///
    /// Расписание чистое, потому что иначе его проверяет только терпение:
    /// тест на живом ожидании шёл бы минуту.
    static func waitStep(attempt: Int) -> TimeInterval? {
        let step: TimeInterval = attempt < 10 ? 0.5 : 1
        guard waited(before: attempt) + step <= ceiling else { return nil }
        return step
    }

    /// Сколько прошло к началу попытки.
    static func waited(before attempt: Int) -> TimeInterval {
        let fast = min(attempt, 10)
        let slow = max(0, attempt - 10)
        return Double(fast) * 0.5 + Double(slow)
    }

    /// Открывает приложение.
    ///
    /// - Parameter activates: выводить ли его вперёд. После нашей установки —
    ///   да: у Ollama свой первый запуск со своим окном, и спрятанное окно,
    ///   в котором надо нажать, — тупик.
    static func launch(_ bundle: URL, activates: Bool, then done: @escaping (Bool) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) { _, error in
            if let error {
                DebugLog.write("движок: Ollama не открылась — \(error.localizedDescription)")
            }
            DispatchQueue.main.async { done(error == nil) }
        }
    }
}
