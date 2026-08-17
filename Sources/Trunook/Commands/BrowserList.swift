import TrunookXPC
import AppKit

/// Браузеры, установленные в системе.
///
/// Отдельный объект, а не разовый вызов из вёрстки: перебор приложений
/// ходит в Launch Services, а тело представления SwiftUI пересчитывает
/// сколько угодно раз. Список обновляется при открытии настроек — как
/// команды «Команд» и модели Ollama.
final class BrowserList: ObservableObject {
    struct Browser: Identifiable, Equatable {
        let bundleID: String
        let name: String
        var id: String { bundleID }
    }

    @Published private(set) var items: [Browser] = []
    /// Что откроет ссылку, если браузер не выбран. Показываем в списке,
    /// чтобы «по умолчанию» не было угадыванием.
    @Published private(set) var defaultName: String?

    /// Ссылка-образец: спрашиваем систему, кто умеет открывать http.
    private static let probe = URL(string: "https://example.com")!

    func refresh() {
        let workspace = NSWorkspace.shared
        var seen = Set<String>()
        var found: [Browser] = []

        for url in workspace.urlsForApplications(toOpen: Self.probe) {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            // Одно и то же приложение попадается в нескольких копиях —
            // например, в /Applications и в корзине разработчика.
            guard seen.insert(bundleID).inserted else { continue }
            found.append(Browser(bundleID: bundleID, name: Self.name(of: url)))
        }

        items = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        defaultName = workspace.urlForApplication(toOpen: Self.probe).map(Self.name(of:))
        DebugLog.write("браузеров найдено — \(items.count), по умолчанию \(defaultName ?? "неизвестно")")
    }

    /// Отображаемое имя приложения: локализованное, если оно есть.
    private static func name(of url: URL) -> String {
        let display = FileManager.default.displayName(atPath: url.path)
        return display.hasSuffix(".app") ? String(display.dropLast(4)) : display
    }

    func name(forBundleID bundleID: String) -> String? {
        items.first { $0.bundleID == bundleID }?.name
    }
}
