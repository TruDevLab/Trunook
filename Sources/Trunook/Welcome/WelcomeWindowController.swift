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
    /// Поиск города для погоды: `@State` недоступен, набранному и найденному
    /// надо где-то жить, и живут они столько же, сколько окно.
    private let placeSearch = WeatherPlaceSearch()
    /// Состояние шага «Модель»: живёт с контроллером, а не с видом —
    /// проверка связи и скачивание переживают закрытие окна.
    private let ai = WelcomeAI()
    /// Описания выпусков: живут дольше окна, чтобы повторное открытие
    /// не качало их заново.
    private let releaseNotes = ReleaseNotesService()

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    /// `mode` открывает окно сразу описанием выпуска — так оно приходит
    /// после обновления и по нажатию «Что нового» в настройках.
    func show(
        calendar: CalendarService,
        launchAtLogin: LaunchAtLogin,
        weather: WeatherService,
        mode: WelcomeModel.Mode = .tour,
        onHotKeysChanged: @escaping () -> Void
    ) {
        launchAtLogin.refresh()
        if mode == .notes { releaseNotes.load() }

        if let window, let model {
            model.start(mode: mode)
            present(window)
            return
        }

        let model = WelcomeModel(calendar: calendar)
        let view = WelcomeView(
            model: model,
            calendar: calendar,
            launchAtLogin: launchAtLogin,
            settings: settings,
            weather: weather,
            placeSearch: placeSearch,
            releaseNotes: releaseNotes,
            ai: ai,
            onHotKeysChanged: onHotKeysChanged,
            onFinish: { [weak self] in self?.finish() }
        )

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: WelcomeView.size),
            // `.resizable` — с тех пор, как окно растёт вместе с текстом.
            // На двухстах процентах оно упирается в кромку экрана, и
            // прижатое к ней содержимое нужно чем-то доставать: тянуть
            // окно мышью человек умеет и без подсказки.
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
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
        // Размер считается от масштаба текста, поэтому упереться в экран он
        // может ещё до открытия. Обрезать окно кромкой всё равно придётся —
        // но обрезанное по видимой области оно останется целым окном
        // с полосой заголовка, а не уедет под неё половиной.
        window.setContentSize(Self.fitted(WelcomeView.size))
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.window = window
        self.model = model
        model.start(mode: mode)

        centerOnActiveScreen(window)
        present(window)
        DebugLog.write("окно знакомства открыто")
    }

    func snapshot() {
        WindowSnapshot.write(window, named: "welcome")
    }

    /// Кадры демонстрации выреза для `docs/demo.gif`. Число и шаг подобраны
    /// под петлю в двадцать две секунды: семьдесят кадров — тот же счёт,
    /// что и у прежней картинки.
    func snapshotDemo() {
        WindowSnapshot.writeSequence(window, named: "demo", frames: 70, interval: 0.315)
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
    /// Размер, ужатый до видимой области того экрана, где сейчас курсор.
    private static func fitted(_ size: CGSize) -> CGSize {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return size }
        return CGSize(
            width: min(size.width, visible.width),
            height: min(size.height, visible.height)
        )
    }

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
