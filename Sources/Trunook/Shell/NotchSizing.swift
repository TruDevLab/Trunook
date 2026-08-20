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
    /// Таймер и секундомер.
    case timer
    /// Нагрузка на систему.
    case monitor
    /// Телесуфлер под самой чёлкой — там, где камера.
    case teleprompter
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
    /// Полоска идущего таймера.
    var timerChip: TimerChip?
    /// Ближайшие встречи: то, что начинается сейчас, и то, что идёт следом.
    /// На один слот в календаре нередко стоят две — они попадают сюда обе.
    var events: [CalendarItem] = []
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

    /// Встречи, разложенные по подложкам: одна подложка на одно время начала.
    ///
    /// Все одновременные встречи лежат в общей подложке — они про один и тот
    /// же слот, и по отдельным карточкам читались бы как несвязанные. А вот
    /// следующее время — уже другой слот, и общая подложка слепила бы
    /// «сейчас» и «потом» в один блок расписания.
    var eventGroups: [[CalendarItem]] {
        Array(events.prefix(NotchMetrics.maxVisibleEvents)).groupedByStart()
    }

    /// Высота всего, что показано под строкой музыки.
    var extraHeight: CGFloat {
        let groups = eventGroups
        return Self.extraHeight(
            eventRows: groups.reduce(0) { $0 + $1.count },
            eventCards: groups.count,
            taskRows: visibleTasks
        )
    }

    /// Высота подложек по их составу: строки, поля подложек и зазоры.
    ///
    /// Считается по числам, а не по самим записям, потому что тот же расчёт
    /// нужен потолку размера окна — а у потолка записей нет и быть не может.
    /// Раньше потолок был выписан отдельной формулой и разошёлся с этой
    /// на поле подложки и отступ от строки музыки.
    static func extraHeight(eventRows: Int, eventCards: Int, taskRows: Int) -> CGFloat {
        let cards = eventCards + (taskRows > 0 ? 1 : 0)
        guard cards > 0 else { return 0 }
        /// Поля подложки сверху и снизу.
        let cardPadding: CGFloat = 12
        // Отступ от строки музыки.
        var height = NotchStyle.gridSpacing
        height += CGFloat(eventRows) * NotchMetrics.eventRowHeight
        // Зазоров между строками на каждой подложке на один меньше, чем строк.
        height += CGFloat(max(0, eventRows - eventCards)) * NotchStyle.rowSpacing
        // Задачи идут вплотную друг к другу: они читаются одним списком.
        height += CGFloat(taskRows) * NotchMetrics.taskRowHeight
        height += CGFloat(cards) * cardPadding
        // Зазор между подложками — он же единственный разделитель.
        height += CGFloat(cards - 1) * NotchStyle.cardGap
        return height
    }

    /// Потолок высоты содержимого: полный запас строк встреч, разложенный
    /// по двум подложкам — так выше, чем одной, — и полный список задач.
    static var maxExtraHeight: CGFloat {
        extraHeight(
            eventRows: NotchMetrics.maxVisibleEvents,
            eventCards: min(2, NotchMetrics.maxVisibleEvents),
            taskRows: NotchMetrics.maxVisibleTasks
        )
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
            // Таймер важнее отсчёта до встречи: его завели руками.
            if let timer = content.timerChip {
                return metrics.chip(
                    width: TimerChipView.width(metrics: metrics, showsHours: timer.showsHours)
                )
            }
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
            let layout = PreviewPanel.layout(track: content.track, event: content.events.first, metrics: metrics)
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
        case .monitor:
            return CGSize(
                width: MonitorPanel.width,
                height: MonitorPanel.height(notchHeight: metrics.notchHeight)
            )
        case .timer:
            return CGSize(
                width: TimerPanel.width,
                height: TimerPanel.height(notchHeight: metrics.notchHeight)
            )
        case .teleprompter:
            return CGSize(
                width: TeleprompterPanel.width,
                height: TeleprompterPanel.height(notchHeight: metrics.notchHeight)
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
