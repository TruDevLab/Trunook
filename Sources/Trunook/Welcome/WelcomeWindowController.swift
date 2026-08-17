import TrunookXPC
import AppKit
import SwiftUI

/// Окно знакомства.
///
/// Как и настройки, создаётся вручную: приложение — агент (`LSUIElement`),
/// ни Dock, ни главного меню у него нет.
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: WelcomeModel?

    private let settings: Settings

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    func show(
        calendar: CalendarService,
        launchAtLogin: LaunchAtLogin,
        onHotKeysChanged: @escaping () -> Void
    ) {
        launchAtLogin.refresh()

        if let window, let model {
            model.start()
            present(window)
            return
        }

        let model = WelcomeModel(calendar: calendar)
        let view = WelcomeView(
            model: model,
            calendar: calendar,
            launchAtLogin: launchAtLogin,
            settings: settings,
            onHotKeysChanged: onHotKeysChanged,
            onFinish: { [weak self] in self?.finish() }
        )

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: WelcomeView.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = t("Знакомство с Trunook")
        // Заголовок скрыт, а полоса прозрачна: окно рисует фон само, до самой
        // верхней кромки. Кнопка закрытия при этом остаётся на месте.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.black
        // Оформление всегда тёмное: окно показывает вырез, а он чёрный.
        window.appearance = NSAppearance(named: .darkAqua)

        // `NSHostingView` по умолчанию сам диктует окну размер и требует его
        // от области под полосой заголовка. С `fullSizeContentView` окно
        // из-за этого вырастало на высоту полосы, и сверху оставалась
        // чёрная кромка мимо фона. Размер задаёт окно.
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setContentSize(WelcomeView.size)
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.window = window
        self.model = model
        model.start()

        centerOnActiveScreen(window)
        present(window)
        DebugLog.write("окно знакомства открыто")
    }

    func snapshot() {
        WindowSnapshot.write(window, named: "welcome")
    }

    /// Закрытие любым путём — кнопкой, «Пропустить» или «Начать» — считается
    /// знакомством: второй раз само окно уже не появится.
    private func finish() {
        window?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model?.stop()
        guard !settings.hasSeenWelcome else { return }
        settings.hasSeenWelcome = true
        DebugLog.write("знакомство пройдено")
    }

    /// То же, что у окна настроек: новое окно создаётся в начале координат,
    /// и `center()` увёл бы его не на тот экран.
    private func centerOnActiveScreen(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
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
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
