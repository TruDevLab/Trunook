import CoreGraphics

/// Размеры выреза во всех состояниях. Считаются один раз при построении
/// окна и передаются в представление — чтобы вёрстка не занималась
/// геометрией экрана.
struct NotchMetrics: Equatable {
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    /// Вогнутые уголки формы выходят за тело выреза, поэтому свёрнутый
    /// размер шире аппаратного на два радиуса.
    static let concaveOverhang: CGFloat = 8

    /// Высота строки со встречей в раскрытой панели.
    static var eventRowHeight: CGFloat { NotchStyle.scaled(38) }
    /// Строка задачи ниже: их бывает несколько подряд.
    static var taskRowHeight: CGFloat { NotchStyle.scaled(26) }
    /// Сколько задач помещаем в панель, прежде чем свернуть остаток в «+N».
    static let maxVisibleTasks = 3
    /// Сколько строк встреч показываем — на ближайшее время и следующее
    /// вместе. Больше трёх строк — это уже не «что дальше», а расписание,
    /// и за ним ходят в Календарь.
    static let maxVisibleEvents = 3

    init(notchWidth: CGFloat, notchHeight: CGFloat) {
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
    }

    var closed: CGSize {
        CGSize(width: notchWidth + 2 * Self.concaveOverhang, height: notchHeight)
    }

    /// Высота строки музыки: обложка задаёт её целиком.
    static var musicRowHeight: CGFloat { NotchStyle.scaled(44) }

    /// Раскрытая панель растёт вниз ровно на высоту того, что показывает.
    /// Складывается по общему правилу панелей: шапка живёт в крыльях,
    /// поэтому в расчёте её нет.
    func expanded(extraHeight: CGFloat) -> CGSize {
        CGSize(
            width: max(420, notchWidth + 220),
            height: NotchStyle.height(
                notchHeight: notchHeight,
                contentHeight: Self.musicRowHeight + extraHeight
            )
        )
    }

    /// Плашка события выпадает вниз, как уменьшенная панель.
    /// Ширину задаёт содержимое, высота одна для всех событий.
    func activity(width: CGFloat) -> CGSize {
        CGSize(width: width, height: notchHeight + 6 + ActivityLayout.iconSize + 12)
    }

    /// Обратный отсчёт живёт в одну строку по высоте самой чёлки: он висит
    /// подолгу, и выпадающая панель всё это время мешала бы.
    func chip(width: CGFloat) -> CGSize {
        CGSize(width: width, height: notchHeight)
    }

    /// Окно всегда максимального размера: анимируется содержимое, а не рамка.
    /// Полоска отсчёта бывает шире раскрытой панели — на технике с широким
    /// вырезом она вылезла бы за границу окна и обрезалась.
    var windowSize: CGSize {
        // Потолок панели считается тем же расчётом, что и сама панель:
        // выписанный здесь заново, он разошёлся с ней на поле подложки.
        let panel = expanded(extraHeight: NotchContent.maxExtraHeight)
        let assistant = AssistantPanel.tallest(
            notchHeight: notchHeight,
            notchWidth: notchWidth
        )
        let notes = NotesPanel.height(
            notchHeight: notchHeight,
            rows: NotesPanel.visibleRows
        )
        let clipboard = ClipboardPanel.height(
            notchHeight: notchHeight,
            rows: ClipboardPanel.visibleRows
        )
        // Потолок считается по настоящему составу меню: раньше здесь стояли
        // «две строки», и пятая плитка вылезла бы за окно, а окно обрезает.
        let hub = HubPanel.height(notchHeight: notchHeight, count: HubEntry.count)
        let teleprompter = TeleprompterPanel.height(notchHeight: notchHeight)
        let caffeine = CaffeinePanel.height(notchHeight: notchHeight)
        let shelf = ShelfPanel.height(
            notchHeight: notchHeight,
            count: ShelfPanel.columns * ShelfPanel.visibleRows
        )
        return CGSize(
            width: max(
                panel.width,
                ChipView.width(metrics: self),
                VoiceChipView.width(metrics: self),
                TimerChipView.width(metrics: self, showsHours: true),
                ClipboardPanel.width(notchWidth: notchWidth),
                AssistantPanel.width(notchWidth: notchWidth),
                NotesPanel.width(notchWidth: notchWidth),
                ShelfPanel.width,
                HubPanel.width,
                TeleprompterPanel.width(notchWidth: notchWidth),
                CaffeinePanel.width,
                MeetingControlsView.width(actionCount: MeetingAction.allCases.count)
            ),
            // Плашка с подписью значка висит под панелью, а окно обрезает:
            // без запаса она пропала бы ровно там, где нужнее всего, —
            // под самой высокой панелью, телесуфлером с его шестью значками
            // оформления.
            height: max(
                panel.height, clipboard, assistant, shelf, hub,
                teleprompter, caffeine, notes
            ) + NotchHintLayout.reserved
        )
    }
}
