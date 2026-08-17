import CoreGraphics
import TrunookXPC

/// Единственный расчёт того, что вырез показывает прямо сейчас.
///
/// Раньше этот расчёт существовал дважды: вёрстка решала, что рисовать,
/// а контроллер — где окно принимает нажатия, и оба списка правил вели
/// вручную. Они разошлись: при добавлении полки ветку в контроллере забыли,
/// и вырез рисовал панель 440×242, принимая нажатия в прямоугольнике 201×32.
/// Плитки полки оказались вне зоны слышимости окна — ни нажатия,
/// ни перетаскивания до них не доходило, а выглядело это как «файл
/// не перетаскивается».
///
/// Поэтому правило одно: **зона нажатий обязана совпадать с нарисованным**.
/// Оба места спрашивают этот тип, и разойтись им больше негде.
struct NotchSnapshot: Equatable {
    let presentation: NotchPresentation
    let content: NotchContent

    func size(metrics: NotchMetrics) -> CGSize {
        NotchSizing.size(presentation: presentation, content: content, metrics: metrics)
    }
}

/// Всё, от чего зависит состояние выреза, — снятое с наблюдаемых объектов
/// в простые значения.
///
/// Промежуточный тип нужен, чтобы расчёт не зависел от служб: так его можно
/// проверить тестом, не поднимая ни календаря, ни музыки.
struct NotchInputs: Equatable {
    var overlay: NotchState.Overlay?
    var swipe: SwipeDirection?
    /// Свайп идёт прямо сейчас: направление и доля пройденного пути.
    var pendingSwipe: SwipeDirection?
    var swipeProgress: Double = 0
    var isHovered = false
    var isPinnedOpen = false
    var chip: CalendarItem?
    var activity: Activity?
    var track: NowPlaying?
    var event: CalendarItem?
    var taskCount = 0
    var meetingActions = 0
    var clipboardRows = 0
    var assistantAnswer = ""
    var assistantIsStreaming = false
    var shelfCount = 0
    var hubCount = 0

    /// С какой доли жеста остров начинает расходиться в бока.
    static let swipingEnterProgress: Double = 0.15

    func resolve() -> NotchSnapshot {
        NotchSnapshot(presentation: presentation, content: content)
    }

    /// Нажатие важнее наведения, наведение важнее всплывшего события,
    /// событие важнее постоянного отсчёта: чем короче живёт состояние,
    /// тем выше его право занять вырез.
    private var presentation: NotchPresentation {
        // Вызвано клавишей или правой кнопкой — это прямое указание,
        // оно важнее всего.
        switch overlay {
        case .commands: return .commands
        case .clipboard: return .clipboard
        case .assistant: return .assistant
        case .shelf: return .shelf
        case .hub: return .hub
        case nil: break
        }
        // Остров расходится в бока не после срабатывания, а по ходу жеста:
        // значок должен появляться в освободившейся полосе, а не поверх
        // названия трека. Небольшой порог — чтобы случайный горизонтальный
        // толчок не схлопывал панель.
        if isHovered, swipe != nil || swipeProgress >= Self.swipingEnterProgress {
            return .swiping
        }
        if isPinnedOpen { return .expanded }
        if isHovered { return .preview }
        if activity != nil { return .activity }
        return chip == nil ? .collapsed : .chip
    }

    private var content: NotchContent {
        NotchContent(
            activity: activity,
            track: track,
            chip: chip,
            event: event,
            taskCount: taskCount,
            commandsHasBackRow: isPinnedOpen,
            meetingActions: meetingActions,
            clipboardRows: clipboardRows,
            assistantAnswer: assistantAnswer,
            assistantIsStreaming: assistantIsStreaming,
            shelfCount: shelfCount,
            hubCount: hubCount
        )
    }
}
