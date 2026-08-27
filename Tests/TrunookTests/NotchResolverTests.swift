import Testing
@testable import Trunook

/// Расчёт состояния выреза.
///
/// Главное здесь — не отдельные правила приоритета, а то, что расчёт
/// **один**. Раньше их было два: вёрстка решала, что рисовать, контроллер —
/// где принимать нажатия. Они разошлись на полке, и панель было видно,
/// но нажать по ней нельзя.
@Suite("Расчёт состояния выреза")
struct NotchResolverTests {
    private let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)

    @Test("Накладка важнее всего остального")
    func накладкаПобеждает() {
        let inputs = NotchInputs(
            overlay: .clipboard,
            isHovered: true,
            isPinnedOpen: true,
            activity: nil,
            clipboardRows: 3
        )
        #expect(inputs.resolve().presentation == .clipboard)
    }

    @Test("У каждой накладки своё состояние и ненулевой размер")
    func каждаяНакладкаИмеетРазмер() {
        for overlay in NotchState.Overlay.allCases {
            var inputs = NotchInputs(overlay: overlay)
            inputs.clipboardRows = 3
            inputs.shelfCount = 4
            inputs.hubCount = HubEntry.count
            let snapshot = inputs.resolve()

            #expect(snapshot.presentation != .collapsed, "накладка \(overlay) осталась свёрнутой")

            // Тот самый случай: панель нарисована, а зона нажатий — с чёлку.
            let size = snapshot.size(metrics: metrics)
            #expect(size.width > metrics.closed.width, "у накладки \(overlay) ширина как у свёрнутой")
            #expect(size.height > metrics.notchHeight, "у накладки \(overlay) высота как у чёлки")
        }
    }

    @Test("Нажатие важнее наведения, наведение важнее плашки")
    func приоритетСостояний() {
        let pinned = NotchInputs(isHovered: true, isPinnedOpen: true)
        #expect(pinned.resolve().presentation == .expanded)

        let hovered = NotchInputs(isHovered: true, activity: Activity(kind: .trackChanged))
        #expect(hovered.resolve().presentation == .preview)

        let activity = NotchInputs(activity: Activity(kind: .trackChanged))
        #expect(activity.resolve().presentation == .activity)
    }

    @Test("Пустой вырез свёрнут, с отсчётом — полоска")
    func пустоеСостояние() {
        #expect(NotchInputs().resolve().presentation == .collapsed)
    }

    @Test("Свайп виден только при наведении")
    func свайпТребуетНаведения() {
        #expect(NotchInputs(swipe: .next).resolve().presentation == .collapsed)
        #expect(NotchInputs(swipe: .next, isHovered: true).resolve().presentation == .swiping)
    }

    @Test("Остров расходится в бока по ходу жеста, а не после срабатывания")
    func свайпРасширяетПоХоду() {
        // Ниже порога — обычный мини-вид: случайный толчок вбок не должен
        // схлопывать панель.
        let nudge = NotchInputs(pendingSwipe: .next, swipeProgress: 0.05, isHovered: true)
        #expect(nudge.resolve().presentation == .preview)

        // За порогом — уже расширение, хотя трек ещё не переключён.
        let pulling = NotchInputs(pendingSwipe: .next, swipeProgress: 0.5, isHovered: true)
        #expect(pulling.resolve().presentation == .swiping)
    }

    @Test("Расширенный остров шире свёрнутого и высотой с чёлку")
    func размерРасширения() {
        let size = NotchInputs(pendingSwipe: .next, swipeProgress: 0.5, isHovered: true)
            .resolve().size(metrics: metrics)
        #expect(size.width > metrics.closed.width)
        #expect(size.height == metrics.notchHeight)
    }

    @Test("Панель растёт вместе с числом файлов на полке")
    func полкаРастёт() {
        let one = NotchInputs(overlay: .shelf, shelfCount: 1).resolve().size(metrics: metrics)
        let many = NotchInputs(overlay: .shelf, shelfCount: 8).resolve().size(metrics: metrics)
        #expect(many.height > one.height)
    }

    // MARK: - Разговор с моделью

    /// Плашка захваченного текста и список команд занимают высоту, и оба
    /// обязаны быть учтены расчётом. Не учтёшь — панель выйдет короче своего
    /// содержимого, и нижнее обрежется краем: ловится это только снимком.
    @Test("Захваченный текст и список команд поднимают панель")
    func панельРастётПодСодержимое() {
        let bare = NotchInputs(overlay: .assistant).resolve().size(metrics: metrics)

        var withCapture = NotchInputs(overlay: .assistant)
        withCapture.assistantHasCapture = true
        #expect(withCapture.resolve().size(metrics: metrics).height > bare.height)

        var withCommands = NotchInputs(overlay: .assistant)
        withCommands.assistantCommandRows = 3
        #expect(withCommands.resolve().size(metrics: metrics).height > bare.height)

        // Ноль строк — это «списка нет вовсе», а не «список из нуля строк»:
        // с выключенными командами место под него отводиться не должно.
        var noCommands = NotchInputs(overlay: .assistant)
        noCommands.assistantCommandRows = 0
        #expect(noCommands.resolve().size(metrics: metrics).height == bare.height)
    }

    /// Окно всегда одного размера, а панель растёт: всё, что панель умеет
    /// показать, обязано в него влезать. Прежде потолок считался по пустому
    /// полю — и выросшая панель обрезалась бы краем окна.
    @Test("Самая полная панель разговора влезает в окно")
    func полнаяПанельВлезает() {
        var inputs = NotchInputs(overlay: .assistant)
        inputs.assistantHasCapture = true
        inputs.assistantCommandRows = QuickCommands.visibleRows
        inputs.assistantIsStreaming = true
        inputs.assistantQuestion = String(repeating: "\n", count: GrowingTextField.maxLines)

        let size = inputs.resolve().size(metrics: metrics)
        #expect(size.height <= metrics.windowSize.height)
        #expect(size.width <= metrics.windowSize.width)
    }
}
