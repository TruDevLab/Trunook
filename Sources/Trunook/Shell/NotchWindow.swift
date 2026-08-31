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

        // Облик окна всегда тёмный — как у окна настроек и окна знакомства.
        //
        // Раньше окно обходилось без облика вовсе, и это сходило с рук:
        // всё в нём было выкрашено чёрным вручную, а системным цветам
        // взяться было неоткуда. Со стеклом перестало: `Glass.regular`
        // рисует светлый вариант под светлым обликом, и в светлой теме
        // системы остров высветлялся вместе с ней — вплоть до того, что
        // белая подпись на нём переставала читаться.
        //
        // Остров обязан быть тёмным при любой теме, и не ради вкуса:
        // он вырастает из аппаратной вырезки, а она чёрная всегда. Светлый
        // остров рядом с чёрной вырезкой — это не светлая тема, это шов.
        appearance = NSAppearance(named: .darkAqua)

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
