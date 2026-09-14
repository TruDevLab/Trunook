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

    /// Настоящий вырез или условный — на экране без чёлки.
    let hasNotch: Bool
    /// Отражение на чужом экране: в покое без чёлки видна полоска-ручка.
    let showsHandle: Bool

    /// Высота полоски на экранах без чёлки: заметна как край, текста
    /// в неё не положить.
    static let handleHeight: CGFloat = 5

    init(notchWidth: CGFloat, notchHeight: CGFloat, hasNotch: Bool = true, showsHandle: Bool = false) {
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.hasNotch = hasNotch
        self.showsHandle = showsHandle
    }

    var closed: CGSize {
        CGSize(width: notchWidth + 2 * Self.concaveOverhang, height: notchHeight)
    }

    /// Свёрнутый вырез в покое.
    ///
    /// Над настоящим вырезом это его силуэт. На экране без чёлки основное
    /// окно не рисует ничего: чёрное пятно посреди полосы меню не прячет
    /// никакого железа, а зона нажатий под ним ела бы щелчки по полосе.
    /// Отражение рисует тонкую полоску — знак, что остров можно раскрыть.
    /// Ширина остаётся, чтобы раскрытие росло из середины кромки.
    var resting: CGSize {
        guard !hasNotch else { return closed }
        return CGSize(width: closed.width, height: showsHandle ? Self.handleHeight : 0)
    }

    /// Главный экран растёт вниз на столько рядов плиток, сколько занято.
    /// Складывается по общему правилу панелей: шапка живёт в крыльях,
    /// поэтому в расчёте её нет.
    func expanded(rows: Int) -> CGSize {
        CGSize(
            width: max(HomeGrid.panelWidth, notchWidth + 220),
            height: NotchStyle.height(
                notchHeight: notchHeight,
                contentHeight: HomeGrid.contentHeight(rows: rows)
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
        let panel = expanded(rows: HomeGrid.maxRows)
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
        let teleprompter = TeleprompterPanel.height(notchHeight: notchHeight)
        let calendar = CalendarPanel.height(notchHeight: notchHeight)
        let editor = EventEditorPanel.height(notchHeight: notchHeight)
        let caffeine = CaffeinePanel.height(notchHeight: notchHeight)
        let keyboardLock = KeyboardLockPanel.height(notchHeight: notchHeight)
        let feeds = FeedsPanel.height(notchHeight: notchHeight)
        // Кольцо в окне не панель, но обрезает его так же. Веер расходится
        // с ростом списка, и рано или поздно он перерос бы самую высокую
        // панель молча — а окно режет без предупреждения.
        let ringSize = QuickRingLayout.size(count: HubEntry.ringCases.count)
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
                TeleprompterPanel.width(notchWidth: notchWidth),
                CaffeinePanel.width,
                KeyboardLockPanel.width,
                FeedsPanel.width,
                FeedChipView.width(metrics: self),
                CalendarPanel.width,
                EventEditorPanel.width,
                ringSize.width,
                MeetingControlsView.width(actionCount: MeetingAction.allCases.count)
            ),
            // Плашка с подписью значка висит под панелью, а окно обрезает:
            // без запаса она пропала бы ровно там, где нужнее всего, —
            // под самой высокой панелью, телесуфлером с его шестью значками
            // оформления.
            height: max(
                panel.height, clipboard, assistant, shelf,
                teleprompter, caffeine, keyboardLock, notes, calendar, editor, feeds,
                notchHeight + ringSize.height
            ) + NotchHintLayout.reserved
        )
    }
}
