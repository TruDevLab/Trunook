import TrunookXPC
import AppKit

/// Исполняет быстрые команды и сообщает о ходе дела наружу.
final class CommandRunner {
    /// Состояние показывается плашкой в вырезе.
    enum Outcome: Equatable {
        case running(String)
        case done(String)
        case failed(String)
    }


    var onOutcome: ((Outcome) -> Void)?
    /// Запрос к модели уходит в панель выреза: ответ пишется там по мере
    /// поступления, и с ним можно что-то сделать, а не только найти
    /// в буфере обмена.
    var onAssistantPrompt: ((_ title: String, _ prompt: String) -> Void)?

    private let settings: Settings
    private let ollama: OllamaClient
    /// NSAppleScript не потокобезопасен — держим его на своей очереди.
    private let scriptQueue = DispatchQueue(label: "com.trunook.applescript")

    init(settings: Settings = .shared, ollama: OllamaClient = OllamaClient()) {
        self.settings = settings
        self.ollama = ollama
    }

    func run(_ command: QuickCommand) {
        guard command.isConfigured else { return }
        DebugLog.write("команда «\(command.title)» (\(command.kind.rawValue))")

        switch command.kind {
        case .shortcut:
            runShortcut(command)
        case .ollama:
            runOllama(command)
        case .appleScript:
            runAppleScript(command)
        case .openApp:
            openApp(command)
        case .openPath:
            openPath(command)
        case .openURL:
            openURL(command)
        }
    }

    // MARK: - Модель

    private func runOllama(_ command: QuickCommand) {
        guard settings.ollamaEnabled else {
            DebugLog.write("команда «\(command.title)»: Ollama выключена в настройках")
            report(.failed(t("Ollama выключена в настройках")))
            return
        }

        SelectionReader.read { [weak self] selection in
            guard let self else { return }
            let text = (selection ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            // Без выделения запрос бессмысленен, и это не безобидно: промт
            // вроде «исправь ошибки» без текста уводит модель в бесконечную
            // генерацию. Проверено — тот же запрос через curl не вернулся
            // и за три минуты.
            guard !text.isEmpty || !command.payload.contains("{{selection}}") else {
                DebugLog.write("команда «\(command.title)»: нет выделенного текста")
                self.report(.failed(t("Нет выделенного текста")))
                return
            }

            self.onAssistantPrompt?(command.title, command.prompt(with: text))
        }
    }

    // MARK: - Команды

    private func runShortcut(_ command: QuickCommand) {
        report(.running(command.title))

        func execute(with input: String?) {
            ShortcutsService.run(name: command.payload, input: input) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case let .success(output):
                        // Результат кладём в буфер только если он есть:
                        // многие команды ничего не возвращают, и затирать
                        // буфер пустотой было бы вредительством.
                        if let output, !output.isEmpty {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(output, forType: .string)
                            DebugLog.write("команда «\(command.title)»: результат \(output.count) симв. в буфере")
                            self?.report(.done(tf("В буфере: %@", String(output.prefix(40)))))
                        } else {
                            self?.report(.done(command.title))
                        }
                    case let .failure(error):
                        DebugLog.write("команда «\(command.title)»: \(error.localizedDescription)")
                        self?.report(.failed(error.localizedDescription))
                    }
                }
            }
        }

        guard command.passesSelection else {
            execute(with: nil)
            return
        }
        SelectionReader.read { selection in
            execute(with: selection)
        }
    }

    // MARK: - AppleScript

    private func runAppleScript(_ command: QuickCommand) {
        report(.running(command.title))
        scriptQueue.async { [weak self] in
            var error: NSDictionary?
            let script = NSAppleScript(source: command.payload)
            let result = script?.executeAndReturnError(&error)

            DispatchQueue.main.async {
                if let error {
                    let message = (error[NSAppleScript.errorMessage] as? String) ?? t("ошибка")
                    DebugLog.write("команда «\(command.title)»: \(message)")
                    self?.report(.failed(message))
                } else {
                    self?.report(.done(result?.stringValue ?? command.title))
                }
            }
        }
    }

    // MARK: - Приложения и пути

    private func openApp(_ command: QuickCommand) {
        let url: URL? = command.payload.hasPrefix("/")
            ? URL(fileURLWithPath: command.payload)
            : NSWorkspace.shared.urlForApplication(withBundleIdentifier: command.payload)

        guard let url else {
            report(.failed(t("Приложение не найдено")))
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        report(.done(command.title))
    }

    private func openPath(_ command: QuickCommand) {
        let expanded = (command.payload as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        guard FileManager.default.fileExists(atPath: expanded) else {
            report(.failed(t("Путь не найден")))
            return
        }
        NSWorkspace.shared.open(url)
        report(.done(command.title))
    }

    // MARK: - Ссылки

    private func openURL(_ command: QuickCommand) {
        guard let url = QuickCommand.webURL(from: command.payload) else {
            DebugLog.write("команда «\(command.title)»: ссылка не разобрана")
            report(.failed(t("Ссылка не разобрана")))
            return
        }

        guard let bundleID = command.browserBundleID, !bundleID.isEmpty else {
            NSWorkspace.shared.open(url)
            report(.done(command.title))
            return
        }

        // Браузер могли удалить или переместить уже после того, как слот
        // настроили. Открыть ссылку в стандартном лучше, чем не открыть
        // вовсе, — но человек должен увидеть, что вышло не по его выбору.
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            DebugLog.write("команда «\(command.title)»: браузер \(bundleID) не найден")
            NSWorkspace.shared.open(url)
            report(.done(t("Открыто в браузере по умолчанию")))
            return
        }

        NSWorkspace.shared.open(
            [url],
            withApplicationAt: application,
            configuration: NSWorkspace.OpenConfiguration()
        ) { [weak self] _, error in
            guard let error else {
                self?.report(.done(command.title))
                return
            }
            DebugLog.write("команда «\(command.title)»: \(error.localizedDescription)")
            self?.report(.failed(error.localizedDescription))
        }
    }

    private func report(_ outcome: Outcome) {
        DispatchQueue.main.async { [weak self] in
            self?.onOutcome?(outcome)
        }
    }
}
