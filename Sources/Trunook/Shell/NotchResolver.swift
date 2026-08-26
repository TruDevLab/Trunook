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
    /// Полоска идущего таймера. Важнее отсчёта до встречи: таймер заводят
    /// руками и смотрят на него нарочно, а отсчёт всплывает сам.
    var timerChip: TimerChip?
    var activity: Activity?
    var track: NowPlaying?
    var events: [CalendarItem] = []
    var taskCount = 0
    var meetingActions = 0
    var clipboardRows = 0
    var assistantTranscript: [AssistantSession.Reply] = []
    var assistantIsStreaming = false
    var assistantQuestion = ""
    var assistantMode: NotePanelMode = .model
    var shelfCount = 0
    var hubCount = 0
    var notesRows = 0
    var notesEnabled = true
    /// Чем занят голосовой заход. `nil` — заход не идёт.
    var voicePhase: VoiceSession.Phase?

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
        case .timer: return .timer
        case .monitor: return .monitor
        case .teleprompter: return .teleprompter
        case .caffeine: return .caffeine
        case .notes: return .notes
        case nil: break
        }
        // Голос выше всего, кроме накладок: заход начат прямой командой
        // человека и идёт прямо сейчас — плашка о смене трека посреди него
        // была бы не к месту. Ниже накладок потому, что открытая панель
        // и есть тот самый разговор, только видимый глазами.
        if voicePhase != nil { return .voice }
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
        return chip == nil && timerChip == nil ? .collapsed : .chip
    }

    private var content: NotchContent {
        NotchContent(
            activity: activity,
            track: track,
            chip: chip,
            timerChip: timerChip,
            events: events,
            taskCount: taskCount,
            commandsHasBackRow: isPinnedOpen,
            meetingActions: meetingActions,
            clipboardRows: clipboardRows,
            assistantTranscript: assistantTranscript,
            assistantIsStreaming: assistantIsStreaming,
            assistantQuestion: assistantQuestion,
            assistantMode: assistantMode,
            shelfCount: shelfCount,
            hubCount: hubCount,
            notesRows: notesRows,
            notesEnabled: notesEnabled,
            voicePhase: voicePhase
        )
    }
}
