import AppKit

/// Окно-оверлей над вырезом.
///
/// Ключевое свойство — `.nonactivatingPanel`: нажатие в вырезе не отбирает
/// фокус у активного приложения. Без этого сценарий «выделил текст, спросил
/// у модели, вставил ответ обратно» развалится, потому что выделение слетит.
final class NotchWindow: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Полосы заголовка у окна без рамки нет, и на экране имя не появится.
        // Нужно оно диктору: без него VoiceOver добирался до безымянного окна
        // и сказать о нём мог только «окно».
        title = AppInfo.name
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        // Порядок важен: сеттер isFloatingPanel сам выставляет уровень .floating,
        // поэтому свой уровень назначаем строго после него.
        isFloatingPanel = true
        // Выше меню-бара и выше полноэкранных окон.
        level = .screenSaver
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        animationBehavior = .none
    }

    // Нужно для будущего поля ввода запроса к модели.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
