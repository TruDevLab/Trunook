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
    ///
    /// Модель идёт третьим: она у каждой команды своя, а разговор ведёт
    /// не бегунок, а сессия — сказать ей, чем отвечать, можно только здесь.
    var onAssistantPrompt: ((_ title: String, _ prompt: String, _ model: String?) -> Void)?
    /// Записать захваченный текст заметкой. Замыканием, а не своим вызовом
    /// службы заметок: подтверждение показывается по-разному в зависимости
    /// от того, открыта ли накладка, — а об этом знает только контроллер.
    var onSaveToNotes: ((String) -> Void)?

    private let settings: Settings
    private let ollama: OllamaClient
    /// NSAppleScript не потокобезопасен — держим его на своей очереди.
    private let scriptQueue = DispatchQueue(label: "com.trunook.applescript")

    init(settings: Settings = .shared, ollama: OllamaClient = OllamaClient()) {
        self.settings = settings
        self.ollama = ollama
    }

    /// `selection` — захваченный текст. Приходит готовым, а не читается здесь:
    /// его прочли один раз при вызове панели, показали человеку плашкой,
    /// и он мог его убрать. Читать выделение заново в момент запуска значило
    /// бы взять не то, что видно на экране: панель забрала фокус, и выделения
    /// в чужом окне к этому мигу уже нет.
    func run(_ command: QuickCommand, selection: String = "") {
        guard command.isConfigured else { return }
        DebugLog.write("команда «\(command.title)» (\(command.kind.rawValue))")

        switch command.kind {
        case .shortcut:
            runShortcut(command, selection: selection)
        case .ollama:
            runOllama(command, selection: selection)
        case .saveToNotes:
            saveToNotes(command, selection: selection)
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

    private func runOllama(_ command: QuickCommand, selection: String) {
        guard settings.ollamaEnabled else {
            DebugLog.write("команда «\(command.title)»: Ollama выключена в настройках")
            report(.failed(t("Ollama выключена в настройках")))
            return
        }

        let text = selection.trimmingCharacters(in: .whitespacesAndNewlines)

        // Без текста запрос бессмысленен, и это не безобидно: промт
        // вроде «исправь ошибки» без текста уводит модель в бесконечную
        // генерацию. Проверено — тот же запрос через curl не вернулся
        // и за три минуты.
        guard !text.isEmpty || !command.payload.contains("{{selection}}") else {
            DebugLog.write("команда «\(command.title)»: нет захваченного текста")
            report(.failed(t("Нечего обрабатывать — ничего не выделено")))
            return
        }

        onAssistantPrompt?(command.title, command.prompt(with: text), command.model)
    }

    // MARK: - Заметки

    /// Захваченное — сразу в заметки, без модели.
    ///
    /// Единственная команда, которая ничего не спрашивает и ничего
    /// не открывает: записал и читаешь дальше. Тем же путём, что и ⌃⌥⇧Z, —
    /// иначе одна и та же запись легла бы двумя разными способами.
    private func saveToNotes(_ command: QuickCommand, selection: String) {
        let text = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            DebugLog.write("команда «\(command.title)»: нечего сохранять")
            report(.failed(t("Нечего сохранить")))
            return
        }
        onSaveToNotes?(text)
    }

    // MARK: - Команды

    private func runShortcut(_ command: QuickCommand, selection: String) {
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

        // Захваченный текст на входе — только если команда его просит:
        // многие команды из «Команд» работают сами по себе, и кормить их
        // случайным выделением значило бы менять то, что они делают.
        //
        // Читать выделение заново здесь нельзя по той же причине, что
        // и у модели: панель уже забрала фокус. Пустой захват передаётся
        // как `nil` — «входа нет», а не «вход пустой».
        guard command.passesSelection else {
            execute(with: nil)
            return
        }
        execute(with: selection.isEmpty ? nil : selection)
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
