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
    /// Полоска идущей записи. Выше всех прочих полосок: запись легко
    /// забыть выключенной, и цена этому — час звука мимо заметки, тогда как
    /// пропущенный таймер стоит одного взгляда на часы.
    var recordingChip: RecordingChip?
    /// Полоска идущего таймера. Важнее отсчёта до встречи: таймер заводят
    /// руками и смотрят на него нарочно, а отсчёт всплывает сам.
    var timerChip: TimerChip?
    /// Полоска горящей чашки. Ниже таймера и отсчёта до встречи: чашка живёт
    /// часами, а те двое — минутами, и правило здесь общее — чем короче живёт
    /// состояние, тем выше его право занять вырез.
    var caffeineChip: CaffeineChip?
    /// Метка непрочитанной сводки или изменения на сайте. Ниже всех полосок:
    /// она живёт часами, пока панель не откроют.
    var feedChip: FeedChip?
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
    /// Есть ли захваченный текст. Признак, а не сам текст: плашка постоянной
    /// высоты, и на размер влияет только её наличие.
    var assistantHasCapture = false
    /// Плашка захваченного текста раскрыта: она выше свёрнутой.
    var assistantCaptureExpanded = false
    /// Сколько команд показывает список под полем. Ноль — списка нет вовсе.
    var assistantCommandRows = 0
    /// Сколько строк показывает список «@». `nil` — список закрыт, и слот
    /// под полем занят обычным: командами или действиями с ответом.
    var assistantMentionRows: Int?
    /// Модель включена. Без неё в панели нет ни ленты, ни поля вопроса.
    var assistantModelEnabled = true
    /// Помощник предлагает что-то сделать — в панели стоит карточка.
    /// Признаком, а не значением: высота карточки постоянна.
    var assistantPending = false
    /// Ответ готов — под полем стоят действия с ним, а не список команд.
    var assistantHasAnswer = false
    var shelfCount = 0
    var notesRows = 0
    var notesEnabled = true
    /// Чем занят голосовой заход. `nil` — заход не идёт.
    var voicePhase: VoiceSession.Phase?
    /// Кольцо быстрого доступа раскрыто — кнопку держат на вырезе.
    var isQuickRingOpen = false
    /// Сколько рядов занимают плитки главного экрана.
    var homeRows = 0

    /// С какой доли жеста остров начинает расходиться в бока.
    static let swipingEnterProgress: Double = 0.15

    func resolve() -> NotchSnapshot {
        NotchSnapshot(presentation: presentation, content: content)
    }

    /// То же состояние без того, что заведено рукой: наведения, панелей,
    /// кольца, голоса.
    ///
    /// Для отражения на главном экране, пока основное окно уехало на другой:
    /// с островом работают там, а отсчёт до встречи и плашки на главном
    /// пропадать не должны.
    func passive() -> NotchInputs {
        var copy = self
        copy.overlay = nil
        copy.swipe = nil
        copy.pendingSwipe = nil
        copy.swipeProgress = 0
        copy.isHovered = false
        copy.isPinnedOpen = false
        copy.voicePhase = nil
        copy.isQuickRingOpen = false
        return copy
    }

    /// То, что можно показать поверх экрана блокировки: плашки погоды
    /// и заряда, мини-вид с музыкой по наведению и свайпы треков.
    ///
    /// Всё остальное снято: экран блокировки видит любой, кто подошёл
    /// к ноутбуку, — встречи, буфер и заметки там не место, а панели
    /// с полем ввода там и не заработают: клавиатура у экрана пароля.
    func lockScreen() -> NotchInputs {
        var copy = passive()
        copy.swipe = swipe
        copy.pendingSwipe = pendingSwipe
        copy.swipeProgress = swipeProgress
        // Наведение — только ради музыки: без трека мини-вид показал бы
        // ближайшую встречу, а её тут прятать.
        copy.isHovered = isHovered && track != nil
        copy.chip = nil
        copy.recordingChip = nil
        copy.timerChip = nil
        copy.caffeineChip = nil
        copy.feedChip = nil
        copy.activity = activity.flatMap { Self.showsOnLockScreen($0.kind) ? $0 : nil }
        copy.events = []
        copy.taskCount = 0
        copy.meetingActions = 0
        return copy
    }

    static func showsOnLockScreen(_ kind: Activity.Kind) -> Bool {
        switch kind {
        case .weather, .powerConnected, .powerDisconnected, .lowBattery, .trackChanged:
            return true
        default:
            return false
        }
    }

    /// Нажатие важнее наведения, наведение важнее всплывшего события,
    /// событие важнее постоянного отсчёта: чем короче живёт состояние,
    /// тем выше его право занять вырез.
    private var presentation: NotchPresentation {
        // Вызвано клавишей или правой кнопкой — это прямое указание,
        // оно важнее всего.
        switch overlay {
        case .clipboard: return .clipboard
        case .assistant: return .assistant
        case .shelf: return .shelf
        case .timer: return .timer
        case .monitor: return .monitor
        case .teleprompter: return .teleprompter
        case .caffeine: return .caffeine
        case .keyboardLock: return .keyboardLock
        case .water: return .water
        case .notes: return .notes
        case .calendar: return .calendar
        case .eventEditor: return .eventEditor
        case .feeds: return .feeds
        case .windowSnap: return .windowSnap
        case nil: break
        }
        // Кольцо выше всего, кроме накладок: его держат рукой прямо сейчас,
        // и всё, что могло бы его перебить — наведение, мини-вид, плашка, —
        // случилось раньше и подождёт.
        if isQuickRingOpen { return .quickRing }
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
        let hasChip = chip != nil || timerChip != nil || caffeineChip != nil
            || recordingChip != nil || feedChip != nil
        return hasChip ? .chip : .collapsed
    }

    private var content: NotchContent {
        NotchContent(
            activity: activity,
            track: track,
            chip: chip,
            recordingChip: recordingChip,
            timerChip: timerChip,
            caffeineChip: caffeineChip,
            feedChip: feedChip,
            events: events,
            taskCount: taskCount,
            meetingActions: meetingActions,
            clipboardRows: clipboardRows,
            assistantTranscript: assistantTranscript,
            assistantIsStreaming: assistantIsStreaming,
            assistantQuestion: assistantQuestion,
            assistantMode: assistantMode,
            assistantHasCapture: assistantHasCapture,
            assistantCaptureExpanded: assistantCaptureExpanded,
            assistantCommandRows: assistantCommandRows,
            assistantMentionRows: assistantMentionRows,
            assistantModelEnabled: assistantModelEnabled,
            assistantPending: assistantPending,
            assistantHasAnswer: assistantHasAnswer,
            shelfCount: shelfCount,
            notesRows: notesRows,
            notesEnabled: notesEnabled,
            voicePhase: voicePhase,
            homeRows: homeRows
        )
    }
}
