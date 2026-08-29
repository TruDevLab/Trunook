import TrunookXPC
import AppKit

/// Модели всех включённых провайдеров, сведённые в один список.
///
/// Отдельный объект, а не разовый запрос: список нужен в настройках,
/// обновляется по кнопке и переживает переключение разделов.
final class ModelList: ObservableObject {
    /// Один на всё приложение: тот же список читает строка команды в вырезе,
    /// и два объекта означали бы два опроса сервера и два разных ответа
    /// на один и тот же вопрос.
    static let shared = ModelList()

    @Published private(set) var models: [ModelRef] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private let client = ModelClient()
    private let settings: Settings

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    /// Модели одного провайдера — для выбора в его же настройках.
    func models(of provider: AIProvider) -> [ModelRef] {
        models.filter { $0.provider == provider }
    }

    /// Спросить всех включённых разом.
    ///
    /// Всех, а не только основного: команда может уходить не туда, куда
    /// уходит свободный вопрос, и список, показывающий модели одного
    /// провайдера, не дал бы выбрать модель второго — то есть второй
    /// провайдер был бы включён и недоступен.
    /// Спросить, если ещё не спрашивали.
    ///
    /// Для тех мест, где список нужен, но повторный опрос ни к чему: панель
    /// разговора открывают десятки раз за день, а моделей на сервере
    /// от этого не прибавляется.
    func refreshIfNeeded() {
        guard models.isEmpty, !isLoading else { return }
        refresh()
    }

    func refresh() {
        guard !isLoading else { return }
        let providers = settings.enabledProviders
        guard !providers.isEmpty else {
            models = []
            error = nil
            return
        }
        isLoading = true
        error = nil

        var collected: [AIProvider: [ModelRef]] = [:]
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            client.listModels(from: provider) { found in
                // Складываем на главной очереди: ответы приходят вразнобой
                // и с разных потоков, а словарь один на всех.
                DispatchQueue.main.async {
                    collected[provider] = found
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isLoading = false
            // Порядок — как у провайдеров в настройках: список, меняющий
            // порядок от ответа к ответу, читается как другой список.
            self.models = providers.flatMap { collected[$0] ?? [] }
            self.error = Self.error(silent: providers.filter { collected[$0]?.isEmpty != false })
            DebugLog.write(
                "модели: найдено — \(self.models.count)"
                    + " у \(providers.count) провайдеров"
            )
        }
    }

    /// Что сказать про тех, кто ничего не отдал.
    ///
    /// Молчащего провайдера надо называть по имени. Раньше провайдер был один,
    /// и «сервер не отвечает» относилось к нему без вопросов; теперь их
    /// несколько, и общая жалоба отправила бы человека проверять все.
    private static func error(silent: [AIProvider]) -> String? {
        guard !silent.isEmpty else { return nil }
        let names = silent.map(\.title).joined(separator: ", ")
        return tf("Не отвечают или моделей нет: %@", names)
    }
}

/// Диалоги выбора вместо ручного ввода путей.
enum CommandPickers {
    /// Выбор приложения. Возвращает путь к бандлу.
    static func chooseApplication() -> (path: String, name: String)? {
        let panel = NSOpenPanel()
        panel.title = t("Выберите приложение")
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return (url.path, url.deletingPathExtension().lastPathComponent)
    }

    /// Выбор файла или папки.
    static func choosePath() -> (path: String, name: String)? {
        let panel = NSOpenPanel()
        panel.title = t("Выберите файл или папку")
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return (url.path, url.lastPathComponent)
    }

    /// Значок приложения или папки — чтобы выбранное было видно, а не только
    /// написано путём.
    static func icon(forPath path: String) -> NSImage? {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }
}

/// Готовые действия для команд AppleScript.
///
/// Писать скрипт руками нужно редко, а типовые действия одни и те же —
/// поэтому они собраны списком, а свой скрипт остаётся отдельным пунктом.
struct ScriptPreset: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let source: String

    static let all: [ScriptPreset] = [
        ScriptPreset(
            id: "lock",
            title: t("Заблокировать экран"),
            symbol: "lock.fill",
            source: """
            tell application "System Events" to keystroke "q" using {control down, command down}
            """
        ),
        ScriptPreset(
            id: "sleep",
            title: t("Спящий режим"),
            symbol: "moon.fill",
            source: "tell application \"System Events\" to sleep"
        ),
        ScriptPreset(
            id: "appearance",
            title: t("Переключить тёмную тему"),
            symbol: "circle.lefthalf.filled",
            source: """
            tell application "System Events" to tell appearance preferences
                set dark mode to not dark mode
            end tell
            """
        ),
        ScriptPreset(
            id: "emptyTrash",
            title: t("Очистить корзину"),
            symbol: "trash.fill",
            source: "tell application \"Finder\" to empty trash"
        ),
        ScriptPreset(
            id: "hideOthers",
            title: t("Скрыть остальные окна"),
            symbol: "rectangle.stack.fill",
            source: """
            tell application "System Events" to keystroke "h" using {option down, command down}
            """
        ),
        ScriptPreset(
            id: "newNote",
            title: t("Новая заметка"),
            symbol: "note.text",
            source: """
            tell application "Notes"
                activate
                make new note at folder 1 of account 1
            end tell
            """
        ),
        ScriptPreset(
            id: "screenshot",
            title: t("Снимок области экрана"),
            symbol: "camera.viewfinder",
            source: "do shell script \"screencapture -i -c\""
        ),
    ]

    /// Совпадает ли текст команды с одной из заготовок.
    static func matching(_ source: String) -> ScriptPreset? {
        let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.first { $0.source.trimmingCharacters(in: .whitespacesAndNewlines) == normalized }
    }
}
