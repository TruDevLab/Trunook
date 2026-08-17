import TrunookXPC
import AppKit

/// Список моделей Ollama для выпадающего меню.
///
/// Отдельный объект, а не разовый запрос: список нужен в настройках,
/// обновляется по кнопке и переживает переключение разделов.
final class OllamaModelList: ObservableObject {
    @Published private(set) var models: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private let client = OllamaClient()

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        client.listModels { [weak self] models in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                self.models = models.map(\.name)
                // Пустой список при доступном сервере — это тоже ответ:
                // моделей просто нет, и об этом надо сказать.
                self.error = models.isEmpty ? t("Ollama не отвечает или моделей нет") : nil
                DebugLog.write("Ollama: моделей найдено — \(models.count)")
            }
        }
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
