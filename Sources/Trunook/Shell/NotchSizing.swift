import CoreGraphics
import TrunookXPC

/// Что вырез показывает прямо сейчас.
enum NotchPresentation: Equatable {
    /// Только силуэт чёлки — неотличим от аппаратного выреза.
    case collapsed
    /// Постоянный обратный отсчёт до ближайшей встречи.
    case chip
    /// Плашка события, выпадающая из-под выреза.
    case activity
    /// Мини-представление по наведению курсора.
    case preview
    /// Момент переключения трека: панель схлопнута, виден только значок
    /// направления сбоку.
    case swiping
    /// Полная панель после нажатия.
    case expanded
    /// Меню быстрых команд по горячей клавише.
    case commands
    /// История буфера обмена.
    case clipboard
    /// Ответ модели.
    case assistant
    /// Полка с отложенными файлами.
    case shelf
    /// Меню всех функций.
    case hub
}

enum SwipeDirection: Equatable {
    case previous
    case next
}

/// Всё, от чего зависит размер формы.
///
/// Собрано в один тип, потому что размер нужен в двух местах — вёрстке
/// и окну, которое принимает нажатия только внутри видимой формы, — и списки
/// параметров начали расходиться.
struct NotchContent: Equatable {
    var activity: Activity?
    var track: NowPlaying?
    var chip: CalendarItem?
    var event: CalendarItem?
    var taskCount: Int = 0
    /// Меню открыто из раскрытой панели — значит есть строка возврата.
    var commandsHasBackRow = false
    /// Сколько кнопок показывает панель встречи. Ноль — встречи нет.
    var meetingActions = 0
    /// Сколько строк истории буфера есть в наличии.
    var clipboardRows = 0
    /// Ответ модели и идёт ли он прямо сейчас — от них зависит высота панели.
    var assistantAnswer = ""
    var assistantIsStreaming = false
    /// Сколько файлов лежит на полке.
    var shelfCount = 0
    /// Сколько плиток показывает меню всех функций.
    var hubCount = 0

    /// Сколько задач реально попадёт в панель.
    var visibleTasks: Int { min(taskCount, NotchMetrics.maxVisibleTasks) }

    /// Высота всего, что показано под строкой музыки.
    ///
    /// Встреча и задачи — две отдельные подложки, у каждой свои поля.
    var extraHeight: CGFloat {
        guard event != nil || taskCount > 0 else { return 0 }
        /// Поля подложки сверху и снизу.
        let cardPadding: CGFloat = 12
        // Отступ от строки музыки.
        var height = NotchStyle.gridSpacing
        if event != nil { height += NotchMetrics.eventRowHeight + cardPadding }
        if taskCount > 0 {
            height += CGFloat(visibleTasks) * NotchMetrics.taskRowHeight + cardPadding
        }
        // Зазор между подложками — только когда их две.
        if event != nil, taskCount > 0 { height += 6 }
        return height
    }
}

enum NotchSizing {
    /// Ширина полосы под значок направления по каждому краю.
    static let swipeExtension: CGFloat = 34

    static func size(
        presentation: NotchPresentation,
        content: NotchContent,
        metrics: NotchMetrics
    ) -> CGSize {
        switch presentation {
        case .collapsed:
            return metrics.closed
        case .chip:
            guard content.chip != nil else { return metrics.closed }
            return metrics.chip(width: ChipView.width(metrics: metrics))
        case .activity:
            guard let activity = content.activity else { return metrics.closed }
            let layout = ActivityView.layout(for: activity.kind, track: content.track, metrics: metrics)
            return metrics.activity(width: layout.panelWidth)
        case .preview:
            // Во время встречи наведение показывает её кнопки: это главное,
            // что нужно от выреза, пока идёт разговор.
            if content.meetingActions > 0 {
                return CGSize(
                    width: MeetingControlsView.width(actionCount: content.meetingActions),
                    height: MeetingControlsView.height(notchHeight: metrics.notchHeight)
                )
            }
            let layout = PreviewPanel.layout(track: content.track, event: content.event, metrics: metrics)
            return metrics.activity(width: layout.panelWidth)
        case .swiping:
            // Нижняя панель убрана, остаётся высота самой чёлки: остров
            // расходится вширь, освобождая место под значок по краям.
            return CGSize(
                width: metrics.closed.width + 2 * swipeExtension,
                height: metrics.notchHeight
            )
        case .expanded:
            return metrics.expanded(extraHeight: content.extraHeight)
        case .commands:
            return CGSize(
                width: CommandsPanel.width,
                height: CommandsPanel.height(
                    notchHeight: metrics.notchHeight,
                    hasBackRow: content.commandsHasBackRow
                )
            )
        case .assistant:
            return CGSize(
                width: AssistantPanel.width,
                height: AssistantPanel.height(
                    notchHeight: metrics.notchHeight,
                    answer: content.assistantAnswer,
                    isStreaming: content.assistantIsStreaming
                )
            )
        case .clipboard:
            return CGSize(
                width: ClipboardPanel.width,
                height: ClipboardPanel.height(
                    notchHeight: metrics.notchHeight,
                    rows: content.clipboardRows
                )
            )
        case .shelf:
            return CGSize(
                width: ShelfPanel.width,
                height: ShelfPanel.height(
                    notchHeight: metrics.notchHeight,
                    count: content.shelfCount
                )
            )
        case .hub:
            return CGSize(
                width: HubPanel.width,
                height: HubPanel.height(
                    notchHeight: metrics.notchHeight,
                    count: content.hubCount
                )
            )
        }
    }
}
