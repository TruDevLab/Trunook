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
    /// История буфера обмена.
    case clipboard
    /// Ответ модели.
    case assistant
    /// Полка с отложенными файлами.
    case shelf
    /// Таймер и секундомер.
    case timer
    /// Нагрузка на систему.
    case monitor
    /// Телесуфлер под самой чёлкой — там, где камера.
    case teleprompter
    /// Выбор срока для чашки кофе.
    case caffeine
    /// Блокировка клавиатуры для чистки.
    case keyboardLock
    /// Список заметок.
    case notes
    /// Мини-календарь: месяц и дела выбранного дня.
    case calendar
    /// Правка одного события.
    case eventEditor
    /// Сводки новостей и слежка за сайтами.
    case feeds
    /// Раскладки окна, донесённого до чёлки.
    case windowSnap
    /// Голосовой заход: панель не раскрывается, светится сам остров.
    case voice
    /// Кольцо быстрого доступа: кружки веером под чёлкой, пока держат кнопку.
    case quickRing

    /// Достаётся ли стекло.
    ///
    /// Всем, кроме свёрнутого. Свёрнутый вырез — это и есть силуэт аппаратной
    /// вырезки, ничего сверх неё он не занимает, и прозрачность там означала
    /// бы обои сквозь железо.
    ///
    /// Полоски — отсчёт до встречи, плашка события, мини-вид трека, голосовой
    /// заход — стекло получают. Сначала не получали, и довод был такой:
    /// чёрная полоса железа отмерена по высоте чёлки, а полоска ростом
    /// с чёлку закрашивалась ею целиком. Довод перестал быть верным, когда
    /// растворение пошло вбок: полоски раздвигаются именно вбок, и там им
    /// есть куда растворяться — середина остаётся чёрной, крылья становятся
    /// стеклом.
    var usesGlass: Bool { self != .collapsed }

    /// Держатся ли верхние уголки чёрными, что бы ни говорило боковое
    /// растворение.
    ///
    /// У тех, кто вырастает из чёлки **вниз**: плашка события и мини-вид
    /// трека. Вогнутыми плечами формы остров держится за кромку экрана,
    /// и боковое растворение съедало плечи первыми — верх повисал сам
    /// по себе.
    ///
    /// Всем остальным полоса не нужна, и это проверено на живом виде:
    ///
    /// - **Раскрытым панелям** она добавляла поверх сплошную чёрную планку
    ///   во всю ширину. Чернота у них и так доходит до кромки собственной
    ///   высотой.
    /// - **Раздвижениям вбок** — отсчёту до встречи, полоскам таймера
    ///   и чашки, голосовому заходу — тоже нет. Они растут в стороны,
    ///   а не вниз; полоса поперёк такого роста читается планкой, наложенной
    ///   сверху, а не креплением.
    var keepsAttachCorners: Bool {
        switch self {
        case .activity, .preview: return true
        case .collapsed, .chip, .swiping, .voice, .quickRing, .expanded,
             .clipboard, .assistant, .shelf, .timer, .monitor,
             .teleprompter, .caffeine, .keyboardLock, .notes, .calendar, .eventEditor, .feeds, .windowSnap:
            return false
        }
    }
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
    var recordingChip: RecordingChip?
    var timerChip: TimerChip?
    /// Полоска горящей чашки.
    var caffeineChip: CaffeineChip?
    /// Метка непрочитанной сводки или изменения на сайте.
    var feedChip: FeedChip?
    /// Ближайшие встречи подряд — столько, сколько вмещает плитка встреч
    /// в два ряда.
    var events: [CalendarItem] = []
    var taskCount: Int = 0
    /// Сколько кнопок показывает панель встречи. Ноль — встречи нет.
    var meetingActions = 0
    /// Сколько строк истории буфера есть в наличии.
    var clipboardRows = 0
    /// Переписка и идёт ли поток — от них зависит высота панели.
    var assistantTranscript: [AssistantSession.Reply] = []
    var assistantIsStreaming = false
    /// Набранный вопрос. Поле растёт вместе с ним, а вслед за полем —
    /// и панель: высоту окна надо знать до того, как поле будет построено.
    var assistantQuestion = ""
    /// Чем занята панель: разговором или заметкой. От режима зависит вся
    /// её вёрстка, а значит и высота.
    var assistantMode: NotePanelMode = .model
    /// Есть ли захваченный текст: над полем вопроса появляется плашка.
    ///
    /// Признак, а не сам текст. Плашка постоянной высоты нарочно — иначе
    /// размер окна пришлось бы пересчитывать на каждую смену захвата,
    /// а панель дёргалась бы вслед за длиной чужого абзаца.
    var assistantHasCapture = false
    /// Плашка захваченного текста раскрыта.
    ///
    /// Раскрытая выше свёрнутой на постоянную величину: текст в ней
    /// прокручивается, а не тянет плашку за собой. Иначе панель прыгала бы
    /// на каждое раскрытие по-разному — в зависимости от того, что попало
    /// в захват.
    var assistantCaptureExpanded = false
    /// Сколько команд показывает список под полем. Ноль — списка нет вовсе:
    /// команды выключены в настройках.
    var assistantCommandRows = 0
    /// Сколько строк показывает список «@». `nil` — список закрыт.
    ///
    /// Слот под полем один на троих, и высота обязана считаться тем же
    /// правилом, каким вёрстка выбирает, кого в нём рисовать.
    var assistantMentionRows: Int?
    /// Модель включена.
    ///
    /// Без неё панель короче ровно на ленту и поле вопроса: спросить некого,
    /// и держать под это место значило бы отдать полпанели пустоте.
    var assistantModelEnabled = true
    /// Помощник предлагает что-то сделать.
    var assistantPending = false
    /// Ответ готов — слот под полем занят действиями с ним.
    var assistantHasAnswer = false
    /// Сколько файлов лежит на полке.
    var shelfCount = 0
    /// Сколько строк показывает список заметок — с учётом поиска.
    var notesRows = 0
    /// Заметки включены.
    ///
    /// Расчёту размера это нужно затем же, зачем и вёрстке: на плашке
    /// о копировании появляется кнопка «в заметки», и от неё зависит ширина
    /// плашки. Разойдись эти двое — кнопку обрезало бы краем.
    var notesEnabled = true
    /// Чем занят голосовой заход. `nil` — заход не идёт.
    ///
    /// Фазой, а не признаком «идёт»: от неё зависит цвет свечения и рисунок
    /// шкалы, то есть само нарисованное. Признака хватило бы только на размер.
    var voicePhase: VoiceSession.Phase?
    /// Сколько рядов занимают плитки главного экрана.
    ///
    /// Высота раскрытой панели задаётся раскладкой, а не тем, сколько
    /// сегодня встреч: экран, скачущий по высоте вслед за календарём,
    /// нельзя было бы честно показать макетом в настройках.
    var homeRows = 0
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
            return metrics.resting
        case .chip:
            // Порядок тот же, что в расчёте состояния и в вёрстке. Запись
            // первой: её потеря дороже всех остальных полосок.
            if let recording = content.recordingChip {
                return metrics.chip(
                    width: RecorderChipView.width(
                        metrics: metrics, showsHours: recording.showsHours
                    )
                )
            }
            // Таймер важнее отсчёта до встречи: его завели руками. Чашка ниже
            // обоих: она горит часами, а те двое живут минутами.
            if let timer = content.timerChip {
                return metrics.chip(
                    width: TimerChipView.width(metrics: metrics, showsHours: timer.showsHours)
                )
            }
            if content.chip != nil {
                return metrics.chip(width: ChipView.width(metrics: metrics))
            }
            if let caffeine = content.caffeineChip {
                return metrics.chip(width: CaffeineChipView.width(metrics: metrics, chip: caffeine))
            }
            // Метка ниже всех: она ждёт часами и никуда не спешит.
            guard content.feedChip != nil else { return metrics.closed }
            return metrics.chip(width: FeedChipView.width(metrics: metrics))
        case .activity:
            guard let activity = content.activity else { return metrics.closed }
            let layout = ActivityView.layout(
                for: activity.kind,
                track: content.track,
                metrics: metrics,
                notesEnabled: content.notesEnabled
            )
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
            return metrics.expanded(rows: content.homeRows)
        case .assistant:
            return CGSize(
                width: AssistantPanel.width(notchWidth: metrics.notchWidth),
                height: AssistantPanel.height(
                    notchHeight: metrics.notchHeight,
                    notchWidth: metrics.notchWidth,
                    mode: content.assistantMode,
                    transcript: content.assistantTranscript,
                    isStreaming: content.assistantIsStreaming,
                    question: content.assistantQuestion,
                    hasCapture: content.assistantHasCapture,
                    captureExpanded: content.assistantCaptureExpanded,
                    commandRows: content.assistantCommandRows,
                    mentionRows: content.assistantMentionRows,
                    modelEnabled: content.assistantModelEnabled,
                    notesEnabled: content.notesEnabled,
                    hasPending: content.assistantPending,
                    hasAnswer: content.assistantHasAnswer
                )
            )
        case .notes:
            return CGSize(
                width: NotesPanel.width(notchWidth: metrics.notchWidth),
                height: NotesPanel.height(
                    notchHeight: metrics.notchHeight,
                    rows: content.notesRows
                )
            )
        case .calendar:
            return CGSize(
                width: CalendarPanel.width,
                height: CalendarPanel.height(notchHeight: metrics.notchHeight)
            )
        case .eventEditor:
            return CGSize(
                width: EventEditorPanel.width,
                height: EventEditorPanel.height(notchHeight: metrics.notchHeight)
            )
        case .quickRing:
            // Сама чёлка и есть форма: кружки рисуются **снаружи** неё,
            // поверх обрезки, и в размер не входят. Раскрывать при этом
            // нечего — кольцо и заведено, чтобы обойтись без панели.
            return metrics.closed
        case .voice:
            // Полоса высотой с чёлку: голосовой заход намеренно не раскрывает
            // панель — она закрыла бы то, с чем человек работает, а смотреть
            // в неё незачем, ответ звучит.
            return metrics.chip(width: VoiceChipView.width(metrics: metrics))
        case .clipboard:
            return CGSize(
                width: ClipboardPanel.width(notchWidth: metrics.notchWidth),
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
        case .windowSnap:
            return CGSize(
                width: WindowSnapLayout.width,
                height: WindowSnapLayout.height(notchHeight: metrics.notchHeight)
            )
        case .feeds:
            return CGSize(
                width: FeedsPanel.width,
                height: FeedsPanel.height(notchHeight: metrics.notchHeight)
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
                width: TeleprompterPanel.width(notchWidth: metrics.notchWidth),
                height: TeleprompterPanel.height(notchHeight: metrics.notchHeight)
            )
        case .caffeine:
            return CGSize(
                width: CaffeinePanel.width,
                height: CaffeinePanel.height(notchHeight: metrics.notchHeight)
            )
        case .keyboardLock:
            return CGSize(
                width: KeyboardLockPanel.width,
                height: KeyboardLockPanel.height(notchHeight: metrics.notchHeight)
            )
        }
    }
}
