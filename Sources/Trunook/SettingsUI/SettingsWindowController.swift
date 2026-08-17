import TrunookXPC
import AppKit
import SwiftUI

/// Окно настроек.
///
/// Приложение — агент (`LSUIElement`), у него нет ни Dock, ни главного меню,
/// поэтому окно приходится создавать и показывать вручную.
final class SettingsWindowController {
    private var window: NSWindow?

    private let selection = SettingsSelection()
    private let models = OllamaModelList()
    private let shortcuts = ShortcutsService()
    private let browsers = BrowserList()

    func show(
        settings: Settings,
        launchAtLogin: LaunchAtLogin,
        calendar: CalendarService,
        clipboard: ClipboardService,
        weather: WeatherService,
        onHotKeysChanged: @escaping () -> Void
    ) {
        // Всё, что приходит извне, перечитывается при каждом открытии, а не
        // только при первом: пользователь мог поменять автозапуск в Системных
        // настройках, завести календарь, добавить команду в «Команды» или
        // модель в Ollama — и ожидает увидеть их сразу.
        launchAtLogin.refresh()
        calendar.refreshSources()
        if settings.ollamaEnabled { models.refresh() }
        shortcuts.refresh()
        browsers.refresh()

        // Отладочный вход: переключать разделы из сессии нечем, а снимать
        // нужно любой.
        //   defaults write com.trunook.Trunook debugSettingsTab commands
        if DebugLog.isEnabled,
           let name = UserDefaults.standard.string(forKey: "debugSettingsTab"),
           let tab = SettingsSelection.Tab(rawValue: name) {
            selection.tab = tab
        }

        if let window {
            present(window)
            return
        }

        let view = SettingsView(
            settings: settings,
            launchAtLogin: launchAtLogin,
            calendar: calendar,
            selection: selection,
            models: models,
            shortcuts: shortcuts,
            browsers: browsers,
            clipboard: clipboard,
            weather: weather,
            onHotKeysChanged: onHotKeysChanged
        )
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: SettingsView.size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = t("Настройки Trunook")
        // Тёмное окно целиком, вместе с полосой заголовка: содержимое тёмное
        // всегда, и светлый заголовок над ним выглядел бы приклеенным
        // от другого приложения.
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(SettingsStyle.background)
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        self.window = window
        centerOnActiveScreen(window)
        present(window)
    }

    func snapshot() {
        WindowSnapshot.write(window, named: "settings")
    }

    /// `NSWindow.center()` ориентируется на экран, где окно уже находится,
    /// а новое окно создаётся в начале координат — на конфигурации с внешними
    /// мониторами оно из-за этого открывается не там, куда смотрит пользователь.
    private func centerOnActiveScreen(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            window.center()
            return
        }
        let size = window.frame.size
        window.setFrameOrigin(
            CGPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            )
        )
    }

    private func present(_ window: NSWindow) {
        // Агент не выходит на передний план сам — просим об этом явно,
        // иначе окно откроется под чужими окнами и без фокуса.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
