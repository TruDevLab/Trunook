import SwiftUI
import TrunookXPC

final class NotchState: ObservableObject {
    @Published var isHovered = false
    /// Нажатие фиксирует панель раскрытой, пока курсор не ушёл.
    @Published var isPinnedOpen = false
    @Published var swipe: SwipeDirection?
    /// Свайп идёт прямо сейчас: куда ведут пальцы и насколько далеко увели,
    /// от нуля до единицы. Значок перелистывания проявляется по этой доле,
    /// а сам трек переключается только когда она дошла до единицы.
    @Published var pendingSwipe: SwipeDirection?
    @Published var swipeProgress: Double = 0
    /// Момент наведения — точка отсчёта для бегущей строки в мини-виде.
    @Published var hoverStartedAt = Date()
    /// Встреча, до которой показывается обратный отсчёт. Решение о том,
    /// показывать ли его, принимает контроллер — вёрстка только рисует.
    @Published var chipItem: CalendarItem?
    /// Что вызвано поверх выреза клавишей. Одновременно — только одно:
    /// разговор с моделью и история буфера занимают одно и то же место.
    @Published var overlay: Overlay?

    enum Overlay: Equatable, CaseIterable {
        case clipboard
        case assistant
        case shelf
        case hub
        case timer
        case monitor
        case teleprompter
        case caffeine
        case notes

        /// Закрывается ли накладка тем, что курсор ушёл за её границы.
        ///
        /// Полка, панель модели, телесуфлер и список заметок — нет, и по одной
        /// причине: с ними работают руками. С полки тащат файлы наружу,
        /// у модели читают длинный ответ и набирают вопрос, в телесуфлер
        /// набирают речь, в списке заметок печатают в поиск, — курсор при этом
        /// заведомо уходит, и закрытие по уходу отнимало бы панель ровно
        /// в тот момент, ради которого она открыта.
        var closesOnCursorExit: Bool {
            switch self {
            case .clipboard, .hub, .timer, .monitor, .caffeine: return true
            case .shelf, .assistant, .teleprompter, .notes: return false
            }
        }

        /// Закрывается ли накладка нажатием мимо неё.
        ///
        /// Все закрываются — кроме телесуфлера. По нему читают вслух, глядя
        /// в камеру и работая в чужом окне: нажатие мимо там не «я закончил»,
        /// а обычная работа. Убрать телесуфлер можно только кнопкой «Закрыть»
        /// или той же клавишей, что его открыла, — набранную речь нельзя
        /// терять от случайного щелчка.
        var closesOnClickOutside: Bool {
            self != .teleprompter
        }
    }

    var isClipboardOpen: Bool { overlay == .clipboard }
    var isAssistantOpen: Bool { overlay == .assistant }
    var isShelfOpen: Bool { overlay == .shelf }
    var isHubOpen: Bool { overlay == .hub }
    var isTimerOpen: Bool { overlay == .timer }
    var isMonitorOpen: Bool { overlay == .monitor }
    var isTeleprompterOpen: Bool { overlay == .teleprompter }
    var isNotesOpen: Bool { overlay == .notes }
    var isCaffeineOpen: Bool { overlay == .caffeine }

    /// Файлы ведут над зоной приёма прямо сейчас. Держится отдельно
    /// от `overlay`: полка бывает открыта и без перетаскивания, а подсветка
    /// нужна только пока над ней что-то держат.
    @Published var isShelfDropTarget = false

    /// С полки тащат файл наружу. Пока это так, накладку закрывать нельзя:
    /// вытащить файл — это и значит увести курсор за её границы.
    @Published var isDraggingOut = false

    /// Чёлку гладят — она мурчит и подрагивает.
    @Published var isPurring = false

    /// Смещение острова при мурчании.
    ///
    /// Считается таймером в контроллере, а не `TimelineView` в самой вёрстке.
    /// Ветвление «мурчит — не мурчит» внутри тела вида меняло его тождество,
    /// и в момент, когда курсор уходил, SwiftUI пересобирал поддерево вместо
    /// того чтобы доиграть схлопывание: остров будто отрывался от кромки.
    /// Смещение, которое всегда на месте и просто равно нулю, тождества
    /// не трогает.
    @Published var tremble: CGSize = .zero
}

struct NotchView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var activities: ActivityCenter
    @ObservedObject var music: MusicClient
    /// Календарь наблюдается, хотя вёрстка к нему и не обращается: встречи
    /// приходят готовыми в снимке состояния, но перерисоваться от их смены
    /// вёрстка обязана сама — снимок берётся лениво и сам о себе не сообщает.
    @ObservedObject var calendar: CalendarService
    @ObservedObject var things: ThingsService
    @ObservedObject var meeting: MeetingService
    /// Подпись значка под курсором. Общий на всё приложение объект, как
    /// и `HoverTracker`: значок под курсором в вырезе всегда один.
    @ObservedObject private var hint = NotchHintTracker.shared
    /// Настройки доступности наблюдаются здесь, в корне.
    ///
    /// Ступени прозрачности и плотности заливок в `NotchStyle` вычисляются
    /// из «Уменьшить прозрачность», а стили кнопок — из «Уменьшить движение».
    /// Ни то ни другое подписаться само не может: `NotchStyle` — набор чисел,
    /// `ButtonStyle` — не `View`. Подписка в корне перерисовывает всё
    /// поддерево разом, и они читают новые значения.
    @ObservedObject private var motion = MotionPreference.shared
    @ObservedObject var clipboard: ClipboardService
    @ObservedObject var assistant: AssistantSession
    /// Установленные модели Ollama — для правой части строки команды.
    /// Общий объект с настройками: список один на приложение, и опрашивать
    /// Ollama дважды незачем.
    @ObservedObject private var models = ModelList.shared
    @ObservedObject var weather: WeatherService
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var timer: TimerService
    @ObservedObject var monitor: MonitorService
    /// Телесуфлер: текст, оформление и автопрокрутка.
    @ObservedObject var teleprompter: TeleprompterStore
    /// Заметки: список, поиск и их число.
    @ObservedObject var notes: NotesService
    /// Набранное в панели модели — вопрос ей или будущая заметка.
    @ObservedObject var draft: NoteDraft
    /// Голосовой заход: фаза, громкость и чем его оборвать.
    @ObservedObject var voice: VoiceSession
    /// Короткое подтверждение внутри панели: обычные плашки из-под накладки
    /// не видны вовсе.
    @ObservedObject var flash: PanelFlash
    /// Держим ли экран от гашения. Наблюдается: подложка под чашкой —
    /// единственное, чем это состояние показано.
    @ObservedObject var wake: WakeGuard
    /// Настройки наблюдаются, а не передаются снимком: слоты команд правятся
    /// в окне настроек, и без наблюдения вырез показывал бы набор, каким тот
    /// был на момент запуска.
    @ObservedObject var settings: Settings

    let metrics: NotchMetrics
    /// Что вырез показывает прямо сейчас — готовым, из одних рук.
    ///
    /// Вёрстка не собирает состояние сама и про `NotchInputs` не знает вовсе.
    /// Собирала — и список полей разошёлся со списком контроллера: вёрстка
    /// передавала долю свайпа, контроллер нет, а доля участвует в решении.
    /// Выходило, что во время жеста рисуется одно, а зона нажатий считается
    /// по другому, — ровно тот дефект, ради которого расчёт и сводили в один
    /// тип. Свести в тип оказалось мало: тип не мешает построить его дважды.
    /// Сведено в одно **место вызова** — `NotchController.notchSnapshot`.
    let snapshot: () -> NotchSnapshot
    let onTap: () -> Void
    let onOpenSettings: () -> Void
    let onJoin: (URL) -> Void
    /// Поставить скачанное обновление. Приложение при этом выйдет: дальше
    /// работает подменщик.
    let onInstallUpdate: () -> Void
    /// Открыть описание выпуска — страницу окна знакомства.
    let onOpenReleaseNotes: () -> Void
    /// Запустить команду из списка под полем вопроса.
    let onRunCommand: (QuickCommand) -> Void
    /// Убрать захваченный текст с плашки.
    let onClearCapture: () -> Void
    /// Раскрыть или свернуть плашку захваченного текста.
    let onToggleCapture: () -> Void
    /// Выбор модели для команды: открыть список, выбрать, вернуться.
    let onBeginChoosingModel: (QuickCommand) -> Void
    let onChooseModel: (String?) -> Void
    let onCancelChoosingModel: () -> Void
    /// Клавиатура в поле вопроса. Каждое отвечает, забрало ли оно нажатие:
    /// без списка команд стрелки и Tab принадлежат тексту.
    let onMoveHighlight: (Int) -> Bool
    /// ← и → ведут подсветку по действиям с готовым ответом.
    let onMoveAnswerAction: (Int) -> Bool
    let onCycleModel: () -> Bool
    let onEscapeHighlight: () -> Bool
    let onCopyLink: (URL) -> Void
    let onOpenItem: (CalendarItem) -> Void
    /// Закрыть любую накладку — крестиком в её шапке.
    let onCloseOverlay: () -> Void
    let onOpenClipboard: () -> Void
    let onUseClipboard: (ClipboardEntry) -> Void
    /// Отложить скопированное в заметки — из списка истории или прямо
    /// с плашки о копировании.
    let onSaveClipboardToNotes: (ClipboardEntry) -> Void
    /// Оборвать голосовой заход — кнопкой в мини-виде или в панели.
    let onStopVoice: () -> Void
    let onDeleteClipboard: (ClipboardEntry) -> Void
    let onClearClipboard: () -> Void
    let onCopyAnswer: () -> Void
    let onPasteAnswer: () -> Void
    /// Отправить набранное модели.
    let onSendDraft: () -> Void
    /// Сохранить набранное заметкой — или переписать ту, что открыта на правку.
    let onSaveDraft: () -> Void
    /// Переключить режим панели: разговор или заметка.
    let onSelectMode: (NotePanelMode) -> Void
    /// Начать новую заметку — из списка.
    let onNewNote: () -> Void
    /// Сохранить заметкой ответ модели.
    let onSaveAnswer: () -> Void
    /// Переключить поиск по заметкам.
    let onToggleNotesSearch: () -> Void
    let onCloseAssistant: () -> Void
    let onOpenNotes: () -> Void
    let onOpenNote: (Note) -> Void
    let onDeleteNote: (Note) -> Void
    let isNoteInVault: (Note) -> Bool
    let onOpenNoteInObsidian: (Note) -> Void
    let onExportNotes: () -> Void
    let onRemoveFromShelf: (ShelfItem) -> Void
    let onOpenShelfItem: (ShelfItem) -> Void
    let onRevealShelfItem: (ShelfItem) -> Void
    let onClearShelf: () -> Void
    let onBeginShelfDragOut: () -> Void
    let onEndShelfDragOut: () -> Void
    let onOpenShelf: () -> Void
    let onOpenTimer: () -> Void
    let onOpenMonitor: () -> Void
    let onOpenActivityMonitor: () -> Void
    let onDismissActivity: () -> Void
    let onOpenHub: () -> Void
    /// Телесуфлер живёт в своём окне, а не накладкой в вырезе: в него печатают
    /// и смотрят подолгу, а вырез фокуса не отбирает и прибит к кромке.
    let onOpenTeleprompter: () -> Void
    /// Раскрыть главную панель. Плитки в меню у этого больше нет — возврат
    /// туда и так делается крестиком, — но нажатие по полоске отсчёта ведёт
    /// именно сюда.
    let onOpenExpanded: () -> Void
    let onAskAssistant: () -> Void
    /// Чашка кофе в левом крыле открывает выбор срока.
    ///
    /// Раньше нажатие переключало удержание вслепую: включалось оно на срок
    /// из настроек, и узнать, на какой именно, из выреза было нельзя.
    let onOpenAwake: () -> Void
    /// Выбран срок в панели бодрости. Ноль — без ограничения.
    let onChooseAwakeLimit: (Int) -> Void
    let onDisableAwake: () -> Void

    /// Команды для списка под полем вопроса: только настроенные и только
    /// при включённых командах.
    ///
    /// Ненастроенные не показываются вовсе — в отличие от прежнего меню, где
    /// пустой слот рисовался пунктиром как место под команду. Там это было
    /// нужно: меню держало шесть мест, и пропавшее место означало бы съехавшую
    /// раскладку. Здесь мест нет, список ровно из того, что есть, и пустая
    /// строка в нём была бы просто мусором.
    private var commands: [QuickCommand] {
        QuickCommands.visible(
            in: settings.quickCommands,
            enabled: settings.quickCommandsEnabled,
            modelEnabled: settings.ollamaEnabled
        )
    }

    /// Плитки меню всех функций: состав задаёт `HubEntry`, здесь к нему
    /// добавляются только действия. Раньше состав жил здесь, а его длина —
    /// отдельной константой в контроллере, и они разошлись бы при первой
    /// же правке.
    private var hubItems: [HubPanel.Item] {
        HubEntry.allCases.map { entry in
            HubPanel.Item(
                id: entry.id,
                title: entry.title,
                symbol: entry.symbol,
                tint: entry.tint,
                isEnabled: entry.isEnabled(settings),
                hint: entry.hint(settings),
                action: { run(entry) }
            )
        }
    }

    private func run(_ entry: HubEntry) {
        switch entry {
        case .assistant: onAskAssistant()
        case .clipboard: onOpenClipboard()
        case .shelf: onOpenShelf()
        case .timer: onOpenTimer()
        case .monitor: onOpenMonitor()
        case .teleprompter: onOpenTeleprompter()
        }
    }

    /// Что обещает кнопка в правом крыле раскрытой панели.
    ///
    /// Одно слово на все случаи, хотя открывает кнопка разное: с моделью —
    /// разговор, команды и заметки, без неё — команды и заметки. Подпись
    /// перечисляла состав («Модель и заметки»), и выходило, что одно место
    /// зовётся в трёх местах тремя именами. Имя у места должно быть одно,
    /// а из чего оно состоит — видно, когда откроешь.
    private var askHint: String { t("Команды") }

    private var content: NotchContent { snapshot().content }
    private var presentation: NotchPresentation { snapshot().presentation }

    private var size: CGSize { snapshot().size(metrics: metrics) }

    /// Встречи берутся из снимка, а не из календаря напрямую: панель обязана
    /// показывать ровно тот список, по которому посчитана её высота.
    private var events: [CalendarItem] { content.events }

    private var isOpen: Bool { presentation != .collapsed }

    /// Полоса воспроизведения нужна там, где виден сам трек.
    private var showsProgress: Bool {
        presentation == .preview || presentation == .expanded
    }

    private var shape: NotchShape {
        NotchShape(
            topRadius: isOpen ? NotchStyle.shoulderInset : 8,
            bottomRadius: {
                switch presentation {
                case .expanded, .clipboard, .assistant, .shelf, .hub, .timer,
                     .monitor, .teleprompter, .caffeine, .notes:
                    return NotchStyle.panelRadius
                case .preview, .activity: return 20
                case .swiping: return 14
                // Голосовая полоса высотой с чёлку — той же формы, что
                // и обратный отсчёт: это одна и та же полоса, разного
                // содержания.
                case .voice, .chip, .collapsed: return 12
                }
            }()
        )
    }

    /// Форма ведёт, содержимое догоняет. При закрытии наоборот: сначала
    /// гаснет содержимое, потом схлопывается форма.
    private var shapeAnimation: Animation { .spring(response: 0.28, dampingFraction: 0.82) }
    private var contentAnimation: Animation {
        .easeOut(duration: 0.14).delay(isOpen ? 0.10 : 0)
    }

    /// Рисовать ли стекло в вырезе.
    ///
    /// Спрашивается у `Surface`, а не у настроек напрямую: условий три —
    /// система умеет, человек не отказался, съёмка не идёт, — и держать их
    /// врозь значит однажды забыть одно.
    ///
    /// Пятое условие своё: стекла не получает только свёрнутый вырез —
    /// он и есть силуэт аппаратной вырезки. Почему остальные получают,
    /// включая полоски, — у `NotchPresentation.usesGlass`.
    private var glassInNotch: Bool { Surface.inNotch && presentation.usesGlass }

    /// Растворять ли черноту железа в панели.
    ///
    /// Отдельно от `glassInNotch`: растворение — обычный градиент, и режим
    /// плоской съёмки его не касается. Иначе на снимке вырез сплошь чёрный,
    /// и длину перехода приходится подбирать вслепую.
    private var translucentNotch: Bool {
        Surface.notchIsTranslucent && presentation.usesGlass
    }

    /// Подложка острова: стекло на всю форму, поверх него — чернота железа.
    ///
    /// Полоса высотой с аппаратную вырезку остаётся непрозрачно чёрной
    /// всегда. Там остров неотличим от самой вырезки — в этом весь его вид, —
    /// и стекло на этом месте показывало бы обои сквозь железо. Ниже
    /// начинается панель, и она стеклянная: остров не всплывает поверх
    /// экрана, он вытекает из железа.
    ///
    /// Свёрнутый вырез остаётся чёрным сам собой, без отдельной ветки: его
    /// высота равна высоте чёлки, и чёрная полоса покрывает его целиком.
    private var background: some View {
        ZStack(alignment: .top) {
            Color.clear.panelGlass(in: shape, glass: glassInNotch)
            // Общее затемнение под стеклом. Панель несёт текст и без всякой
            // плитки под ним — заголовок в крыле, подпись под чёлкой, —
            // а лестница прозрачностей считалась под чёрное. Затемнение
            // возвращает ей это основание, не отнимая прозрачности.
            shape.fill(.black.opacity(glassInNotch ? Surface.panelScrim : 0))
            // Подмена стекла на время съёмки: стекло попадает в снимок
            // мусором, а без него панель осталась бы дырой в рабочий стол.
            // В обычной работе — ноль, то есть ничего.
            shape.fill(.black.opacity(standInFill))
            // Чернота растворяется в обе стороны сразу: вниз — от чёлки
            // к низу панели, вбок — от чёлки к крыльям. Маска перемножает
            // прозрачности, и вместе они дают спад от самой вырезки во все
            // стороны: остров вытекает из железа, а не выпадает из-под
            // чёрной планки во всю ширину.
            LinearGradient(stops: ironStops, startPoint: .top, endPoint: .bottom)
                .mask(ironMaskAcross)
        }
    }

    /// Растворение вбок: непрозрачно над самой чёлкой, к краям панели сходит
    /// на нет.
    ///
    /// Той же кривой, что и вниз: два разных закона спада в одном пятне
    /// читались бы углом.
    private var ironMaskAcross: some View {
        let width = max(1, size.width)
        // Половина ширины сплошной черноты — ровно половина вырезки, без
        // запаса. Запас нужен был по высоте, и туда он и ушёл: вбок чернота
        // и так расходилась верно.
        //
        // При непрозрачном вырезе половина — это вся панель: склоны уезжают
        // за края, и маска остаётся сплошной. Значение вместо ветки.
        let half = translucentNotch
            ? min(0.5, (metrics.notchWidth / 2) / width)
            : 0.5
        let span = translucentNotch ? min(0.5 - half, NotchStyle.ironFadeX / width) : 0

        let curve = NotchStyle.ironCurve
        let last = max(1, curve.count - 1)
        var stops: [Gradient.Stop] = []
        // Левый склон: снаружи прозрачно, у кромки чёлки непрозрачно.
        for (index, opacity) in curve.reversed().enumerated() {
            stops.append(Gradient.Stop(
                color: .white.opacity(opacity),
                location: 0.5 - half - span + span * CGFloat(index) / CGFloat(last)
            ))
        }
        // Правый — зеркально. Между склонами обе кромки непрозрачны,
        // и полоса над чёлкой остаётся сплошной.
        for (index, opacity) in curve.enumerated() {
            stops.append(Gradient.Stop(
                color: .white.opacity(opacity),
                location: 0.5 + half + span * CGFloat(index) / CGFloat(last)
            ))
        }
        return ZStack(alignment: .top) {
            LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
            // Полоса по верхней кромке боковому растворению не подчиняется:
            // ею остров держится за край экрана вогнутыми плечами формы.
            // Наложение поверх маски — значит объединение: где полоса
            // непрозрачна, там непрозрачна и маска, что бы ни говорил
            // боковой градиент.
            LinearGradient(stops: attachStops(height: max(1, size.height)),
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        }
    }

    /// Ступени полосы крепления: непрозрачно у самой кромки, дальше сходит
    /// на нет той же кривой, что и всё остальное растворение.
    private func attachStops(height: CGFloat) -> [Gradient.Stop] {
        guard translucentNotch else {
            return [Gradient.Stop(color: .white, location: 0),
                    Gradient.Stop(color: .white, location: 1)]
        }
        // Полоса достаётся одной плашке события — почему, у
        // `NotchPresentation.keepsAttachCorners`. Остальным ноль, и это
        // значение, а не ветка: нулевая полоса просто ничего не рисует.
        //
        // Привязана и к росту фигуры: четырнадцать точек сплошного плюс
        // растворение съели бы низкую плашку целиком. Растворение вдвое
        // длиннее сплошной части — полоса обязана удержать кромку,
        // а не заменить собой весь переход.
        //
        // Сплошная часть не короче вогнутого плеча формы: плечо и есть тот
        // уголок, которым остров держится за кромку. Полоса, оказавшаяся
        // короче него, оставила бы верх уголка на стекле — а именно он
        // и виден как место крепления.
        let attach = presentation.keepsAttachCorners
            ? max(NotchStyle.shoulderInset,
                  min(NotchStyle.ironAttach, height * NotchStyle.ironAttachShare))
            : 0
        // Потолок на полосу вместе с растворением под ней: на полоске
        // отсчёта, немногим более высокой, чем сама чёлка, они вдвоём
        // закрывали всё, и стекла у неё не оставалось вовсе.
        let ceiling = height * NotchStyle.ironAttachCeiling
        let solid = min(1, min(attach, ceiling) / height)
        let span = max(0, min(1 - solid, (ceiling - attach) / height))
        // Сила полосы — множитель, а не выключатель. Выключенная нулевой
        // высотой, она всё равно красила самую верхнюю строку: ступени
        // сходились в точку, а первая из них непрозрачна по построению.
        // Замер по снимку полоски таймера поймал там альфу 0,94 вместо нуля.
        let strength: Double = presentation.keepsAttachCorners ? 1 : 0

        let curve = NotchStyle.ironCurve
        let last = max(1, curve.count - 1)
        return curve.enumerated().map { index, opacity in
            Gradient.Stop(
                color: .white.opacity(opacity * strength),
                location: solid + span * CGFloat(index) / CGFloat(last)
            )
        }
    }

    /// Чем закрыт низ панели, пока идёт плоская съёмка.
    ///
    /// Значение, а не ветка: в обычной работе просто ноль.
    private var standInFill: Double {
        translucentNotch && !glassInNotch ? Surface.snapshotStandIn : 0
    }

    /// Переход от черноты к стеклу.
    ///
    /// Отказ от стекла проведён **значением**, а не веткой: при выключенном
    /// стекле обе точки уезжают в единицу, и градиент становится сплошной
    /// чернотой — той самой заливкой, что была здесь раньше. Ветка `if`
    /// поменяла бы тождество вида, и SwiftUI пересобрал бы поддерево вместо
    /// перехода; на этом уже ловили отрыв острова от кромки при мурчании.
    private var ironStops: [Gradient.Stop] {
        let height = max(1, size.height)
        // По `translucentNotch`, а не по `glassInNotch`: градиент рисуется
        // и на снимке — иначе его форму нечем проверить.
        //
        // Чернота держится на всю высоту вырезки и ещё на запас сверх неё:
        // растворение, начатое ровно на кромке железа, оставляло у самой
        // вырезки посветлевшую полосу, и тёмное выглядело у́же чёлки.
        // Подробности — у `NotchStyle.ironBleed`.
        let iron = translucentNotch
            ? min(height, metrics.notchHeight + NotchStyle.ironBleed)
            : height
        let solid = min(1, iron / height)
        let span = translucentNotch ? min(1 - solid, NotchStyle.ironFade / height) : 0

        // Кривая, а не две точки: линейный переход от чёрного к прозрачному
        // глаз видит полосой — яркость растёт равномерно, а воспринимается
        // нелинейно, и середина такого перехода читается краем.
        let curve = NotchStyle.ironCurve
        let last = max(1, curve.count - 1)
        return curve.enumerated().map { index, opacity in
            Gradient.Stop(
                color: .black.opacity(opacity),
                location: solid + span * CGFloat(index) / CGFloat(last)
            )
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            background

            // Внутри ZStack, а не поверх: обрезка формой съедает внешнюю
            // половину обводки и оставляет ровную линию по краю острова.
            if showsProgress {
                NotchProgressRing(track: music.nowPlaying, shape: shape, tint: music.artworkTint)
            }

            // Группы стеклянных поверхностей живут внутри самих панелей,
            // а не здесь. Обёртка `GlassEffectContainer` вокруг всей панели
            // ломает ей высоту: список команд, ограниченный четырьмя
            // строками, отрисовал все шесть, полоса действий наехала
            // на две последние, а лишнее ушло под обрезку. Причина —
            // ровно та, о которой предупреждает `DEVELOPMENT.md`:
            // содержимое не должно задавать размер панели, а контейнер
            // перестаёт передавать вниз предложенную высоту.
            //
            // Поэтому группы ставятся точечно — там, где состав ограничен
            // по построению: сетка меню функций, ряд показателей нагрузки.
            // Прокручиваемым спискам слияние и не нужно: строки в них
            // разделены нарочно.
            panel
                .opacity(isOpen ? 1 : 0)
                .animation(contentAnimation, value: presentation)
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: swipeAlignment) {
            // Значок проявляется вместе с движением пальцев, а не вспыхивает
            // по факту переключения: так видно, что жест засчитывается,
            // и насколько ещё вести.
            if presentation == .swiping, let direction = effectiveSwipe {
                SwipeIndicator(direction: direction)
                    // Вогнутый уголок формы съедает крайние точки, поэтому
                    // отступаем на его радиус — иначе значок обрезается.
                    .padding(direction == .previous ? .leading : .trailing, 12)
                    .opacity(swipeVisibility)
                    // Подъезжает из-за края: одна лишь прозрачность читается
                    // как мигание, а смещение — как движение.
                    .offset(x: swipeSlide(direction))
            }
        }
        .animation(.easeOut(duration: 0.12), value: state.swipeProgress)
        // Обрезаем по той же форме: пока чёлка не раскрылась, содержимое
        // физически не может вылезти за её края.
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture(perform: onTap)
        // Подпись значка — под всей чёлкой, а не под самим значком: в крыле
        // на неё нет места, а здесь пусто в любом состоянии выреза.
        //
        // Оверлей навешивается **после** `clipShape` и `onTapGesture`:
        // до обрезки плашку срезало бы формой панели, а до жеста она отняла
        // бы у панели нажатия. Попаданий она не принимает и сама.
        .overlay(alignment: .bottom) {
            NotchHintBubble(text: hint.text)
                .offset(y: NotchHintLayout.reserved)
                .allowsHitTesting(false)
        }
        // Свечение голосового захода — **поверх** обрезки: внутри неё оно
        // просто не вышло бы за края острова, а светить оно должно наружу.
        //
        // Слой стоит всегда и гаснет прозрачностью, а не появляется по `if`.
        // Ветвление в теле вида меняет его тождество, и SwiftUI пересобирает
        // поддерево вместо того чтобы доиграть переход: на этом уже ловили
        // отрыв острова от кромки при мурчании.
        .background(voiceGlow)
        // Панель сменилась или закрылась — подпись уходит с ней. Кнопка
        // исчезает вместе с панелью и об уходе курсора уже не сообщает,
        // так что сама плашка о своём устаревании не узнает.
        .onChange(of: presentation) { _, _ in hint.clear() }
        // Дрожь поверх обрезки: трясётся весь остров целиком, а не его
        // содержимое внутри неподвижной формы.
        .offset(x: state.tremble.width, y: state.tremble.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(shapeAnimation, value: presentation)
        // Размер меняется не только при смене состояния: панель модели
        // и панель заметки — одна и та же накладка `.assistant` разной
        // высоты, и переключение режима меняло её рывком, без всякого
        // перехода. Той же пружиной, что и смена состояния: два разных
        // движения в одном месте читались бы как сбой.
        //
        // Заодно перестал дёргаться и конец потока: панель, садящаяся
        // по содержимому после ответа, тоже меняла высоту скачком.
        .animation(shapeAnimation, value: size)
        .animation(.easeOut(duration: 0.12), value: state.swipe)
    }

    /// Куда указывает значок: по свершившемуся переключению, а пока его нет —
    /// по направлению текущего жеста.
    private var effectiveSwipe: SwipeDirection? {
        state.swipe ?? (state.swipeProgress > 0.02 ? state.pendingSwipe : nil)
    }

    /// Свершившийся свайп показывается целиком, идущий — по своей доле,
    /// пересчитанной от порога раскрытия: к моменту, когда полоса открылась,
    /// значок уже должен начать проявляться, а не ждать своей очереди.
    private var swipeVisibility: Double {
        guard state.swipe == nil else { return 1 }
        let start = NotchInputs.swipingEnterProgress
        return min(1, max(0, (state.swipeProgress - start) / (1 - start)))
    }

    private func swipeSlide(_ direction: SwipeDirection) -> CGFloat {
        guard state.swipe == nil else { return 0 }
        let remaining = CGFloat(1 - min(1, state.swipeProgress))
        return (direction == .previous ? -1 : 1) * remaining * 10
    }

    private var swipeAlignment: Alignment {
        effectiveSwipe == .previous ? .leading : .trailing
    }


    /// Свечение вокруг острова, пока идёт голосовой заход.
    ///
    /// Две обводки одной и той же формы, размытые по-разному: узкая держит
    /// кромку, широкая уходит в стороны ореолом. Одной не хватает — одна
    /// либо режет край, либо расплывается в пятно без формы.
    ///
    /// Пульс считается из времени, а не хранится состоянием: `@State`
    /// в этом тулчейне недоступен, и это тот же приём, которым живёт
    /// бегущая строка.
    private var voiceGlow: some View {
        // Останавливается, когда захода нет, и это не мелочь: вырез открыт
        // всё время работы машины, и тридцать кадров в секунду ради
        // невидимого слоя человек оплачивал бы батареей круглые сутки.
        //
        // Останов — параметр, а не ветка `if`: ветвление меняет тождество
        // вида, и SwiftUI пересобирал бы поддерево вместо перехода.
        TimelineView(.animation(
            minimumInterval: 1 / 30,
            paused: motion.reduceMotion || voice.phase == nil
        )) { context in
            let strength = voiceGlowStrength(at: context.date)
            // Тени, наложенные одна на другую: каждая угасает наружу сама,
            // а вместе они складываются в плавный ореол. Размытые обводки
            // тут не годятся — они дают либо ничего, либо кольца; подробности
            // у `VoiceGlow.layers`.
            //
            // Тени выписаны подряд, а не собраны циклом: `ForEach` строит
            // соседние слои, а тень оборачивает предыдущий — свет от этого
            // и накапливается.
            shape
                .stroke(voiceGlowTint, lineWidth: VoiceGlow.edgeWidth)
                // Размытие до теней, а не после: резкая обводка видна сама
                // по себе, и вместо ореола выходит чёткий контур с бледным
                // свечением снаружи.
                .blur(radius: VoiceGlow.edgeBlur)
                .shadow(color: glowShade(0), radius: VoiceGlow.layers[0].radius)
                .shadow(color: glowShade(1), radius: VoiceGlow.layers[1].radius)
                .shadow(color: glowShade(2), radius: VoiceGlow.layers[2].radius)
                .shadow(color: glowShade(3), radius: VoiceGlow.layers[3].radius)
                .frame(width: size.width, height: size.height)
                .opacity(strength)
            // Свечение — украшение состояния, а не кнопка: попадания
            // по нему уходят тому, что под ним.
            .allowsHitTesting(false)
        }
    }

    /// Цвет слоя свечения по его номеру.
    private func glowShade(_ index: Int) -> Color {
        voiceGlowTint.opacity(VoiceGlow.layers[index].opacity)
    }

    private var voiceGlowTint: Color {
        voice.phase.map(VoiceGlow.tint(for:)) ?? .clear
    }

    /// Сила свечения прямо сейчас: своя для каждой фазы, с медленным
    /// дыханием поверх.
    ///
    /// Когда захода нет — ноль, и слой становится невидимым, не исчезая
    /// из дерева видов.
    private func voiceGlowStrength(at date: Date) -> Double {
        guard let phase = voice.phase else { return 0 }
        let base = VoiceGlow.strength(for: phase, level: voice.listener.level)
        guard !motion.reduceMotion else { return base }
        // Дыхание неглубокое: свечение должно жить, а не мигать. Мигающее
        // у самой кромки экрана поле зрения читает как неисправность.
        let breath = (sin(date.timeIntervalSinceReferenceDate * 2.2) + 1) / 2
        return base * (0.82 + 0.18 * breath)
    }

    /// Куда ведёт нажатие по плашке, по которой можно нажать.
    private func openInteractive(_ activity: Activity) {
        switch activity.kind {
        case .shelf: onOpenShelf()
        // Тело плашки — «расскажи подробнее», капсула — «ставь». Без этой
        // ветки `default` открывал бы по обновлению историю буфера.
        //
        // Подробнее — это описание выпуска, а не настройки: в настройках
        // человек видел ту же строку состояния, что и в плашке, и на этом
        // «подробнее» заканчивалось.
        case .update: onOpenReleaseNotes()
        default: onOpenClipboard()
        }
    }

    @ViewBuilder
    private var panel: some View {
        switch presentation {
        case .collapsed, .swiping:
            EmptyView()
        case .assistant:
            AssistantPanel(
                session: assistant,
                draft: draft,
                flash: flash,
                metrics: metrics,
                modelEnabled: settings.ollamaEnabled,
                notesEnabled: settings.notesEnabled,
                commands: commands,
                models: models.models,
                defaultModel: settings.defaultModel,
                onSend: onSendDraft,
                onRunCommand: onRunCommand,
                onClearCapture: onClearCapture,
                onToggleCapture: onToggleCapture,
                onBeginChoosingModel: onBeginChoosingModel,
                onChooseModel: onChooseModel,
                onCancelChoosingModel: onCancelChoosingModel,
                onMoveHighlight: onMoveHighlight,
                onMoveAnswerAction: onMoveAnswerAction,
                onCycleModel: onCycleModel,
                onEscapeHighlight: onEscapeHighlight,
                onSaveNote: onSaveDraft,
                onCopy: onCopyAnswer,
                onPaste: onPasteAnswer,
                onSaveAnswer: onSaveAnswer,
                onOpenNotes: onOpenNotes,
                onToggleNotesSearch: onToggleNotesSearch,
                onSelectMode: onSelectMode,
                onClose: onCloseAssistant,
                onStopVoice: onStopVoice,
                voicePhase: voice.phase
            )
        case .notes:
            NotesPanel(
                notes: notes,
                metrics: metrics,
                onOpen: onOpenNote,
                onDelete: onDeleteNote,
                isInVault: isNoteInVault,
                onOpenInObsidian: onOpenNoteInObsidian,
                onExportAll: onExportNotes,
                onNewNote: onNewNote,
                onClose: onCloseOverlay
            )
        case .clipboard:
            ClipboardPanel(
                entries: clipboard.entries,
                flash: flash,
                metrics: metrics,
                slotHint: settings.clipboardSlotModifiers.hint,
                notesEnabled: settings.notesEnabled,
                highlighted: clipboard.highlighted,
                onUse: onUseClipboard,
                onSaveToNotes: onSaveClipboardToNotes,
                onDelete: onDeleteClipboard,
                onClear: onClearClipboard,
                onOpenSettings: onOpenSettings,
                onClose: onCloseOverlay
            )
        case .hub:
            HubPanel(
                metrics: metrics,
                items: hubItems,
                onOpenSettings: onOpenSettings,
                onClose: onCloseOverlay
            )
        case .timer:
            TimerPanel(timer: timer, metrics: metrics, onClose: onCloseOverlay)
        case .caffeine:
            CaffeinePanel(
                wake: wake,
                metrics: metrics,
                onChoose: onChooseAwakeLimit,
                onDisable: onDisableAwake,
                onClose: onCloseOverlay
            )
        case .teleprompter:
            TeleprompterPanel(
                store: teleprompter,
                metrics: metrics,
                onClose: onCloseOverlay
            )
        case .monitor:
            MonitorPanel(
                monitor: monitor,
                metrics: metrics,
                onOpenActivityMonitor: onOpenActivityMonitor,
                onClose: onCloseOverlay
            )
        case .shelf:
            ShelfPanel(
                items: shelf.items,
                thumbnail: { shelf.thumbnails[$0.url] ?? shelf.icon(for: $0) },
                metrics: metrics,
                isDropTarget: state.isShelfDropTarget,
                onRemove: onRemoveFromShelf,
                onOpen: onOpenShelfItem,
                onRevealInFinder: onRevealShelfItem,
                onClear: onClearShelf,
                onBeginDragOut: onBeginShelfDragOut,
                onEndDragOut: onEndShelfDragOut,
                onClose: onCloseOverlay
            )
        case .voice:
            if let phase = voice.phase {
                VoiceChipView(
                    phase: phase,
                    level: voice.listener.level,
                    metrics: metrics,
                    onStop: onStopVoice
                )
            }
        case .chip:
            // Порядок тот же, что в расчёте размера, и это не совпадение:
            // разойдись они — вырез рисовал бы одно, а размер считал
            // по другому.
            if timer.isRunning {
                TimerChipView(timer: timer, metrics: metrics, onOpen: onOpenTimer)
            } else if let chip = state.chipItem {
                ChipView(item: chip, metrics: metrics, onOpen: onOpenExpanded)
            } else if wake.isOn {
                CaffeineChipView(wake: wake, metrics: metrics, onOpen: onOpenAwake)
            }
        case .activity:
            if let activity = activities.current {
                let view = ActivityView(
                    activity: activity,
                    track: music.nowPlaying,
                    metrics: metrics,
                    onJoin: onJoin,
                    onInstallUpdate: onInstallUpdate,
                    onDismiss: onDismissActivity,
                    onOpen: { openInteractive(activity) },
                    onSaveToNotes: onSaveClipboardToNotes,
                    notesEnabled: settings.notesEnabled
                )
                .frame(
                    width: ActivityView
                        .layout(
                            for: activity.kind,
                            track: music.nowPlaying,
                            metrics: metrics,
                            notesEnabled: settings.notesEnabled
                        )
                        .panelWidth
                )
                // Нажатие обрабатывает сама плашка: у неё есть ещё крестик,
                // а кнопка, вложенная в кнопку, нажатий не получает.
                view
            }
        case .preview where !meeting.availableActions.isEmpty:
            MeetingControlsView(meeting: meeting, metrics: metrics)

        case .preview:
            PreviewPanel(
                track: music.nowPlaying,
                event: events.first,
                metrics: metrics,
                startDate: state.hoverStartedAt,
                onTogglePlayback: { music.send(.togglePlayPause) }
            )
            .frame(width: PreviewPanel.layout(track: music.nowPlaying, event: events.first, metrics: metrics).panelWidth)
        case .expanded:
            ExpandedPanel(
                music: music,
                events: events,
                tasks: things.todayTitles,
                metrics: metrics,
                onOpenSettings: onOpenSettings,
                onJoin: onJoin,
                onOpenTasks: { ThingsService.openToday() },
                onCopyLink: onCopyLink,
                onOpenItem: onOpenItem,
                onOpenHub: onOpenHub,
                // Панель модели открывается и без модели: заметки в ней
                // работают сами по себе. Пропадает кнопка только если
                // выключено и то и другое.
                onAsk: (settings.ollamaEnabled || settings.notesEnabled) ? onAskAssistant : nil,
                askHint: askHint,
                weather: settings.weatherEnabled ? weather.current : nil,
                isAwake: wake.isOn,
                onOpenAwake: settings.caffeineEnabled ? onOpenAwake : nil
            )
            .frame(width: metrics.expanded(extraHeight: content.extraHeight).width, alignment: .leading)
        }
    }
}

/// Содержимое раскрытой панели: музыка и ближайшая встреча.
private struct ExpandedPanel: View {
    @ObservedObject var music: MusicClient
    let events: [CalendarItem]
    let tasks: [String]
    let metrics: NotchMetrics
    let onOpenSettings: () -> Void
    let onJoin: (URL) -> Void
    let onOpenTasks: () -> Void
    let onCopyLink: (URL) -> Void
    let onOpenItem: (CalendarItem) -> Void
    let onOpenHub: () -> Void
    /// Открыть панель модели и заметок. nil — выключены обе, и кнопки нет:
    /// кнопка, которая ничего не делает, хуже её отсутствия.
    let onAsk: (() -> Void)?
    /// Что кнопка обещает: она открывает разное в зависимости от того,
    /// что включено.
    let askHint: String
    /// Погода живёт в полосе аппаратного выреза справа: там пусто, и панель
    /// от неё не растёт.
    let weather: WeatherService.Snapshot?
    /// Экран удерживается от гашения.
    let isAwake: Bool
    /// Нажатие по чашке. `nil` — чашка выключена в настройках и не рисуется.
    /// Тем же способом сюда приходят выключенные погода и ответ модели:
    /// решение принимает тот, у кого настройки под рукой, а панель только
    /// показывает то, что ей дали.
    let onOpenAwake: (() -> Void)?

    var body: some View {
        NotchPanel(
            metrics: metrics,
            width: metrics.expanded(extraHeight: 0).width,
            // Поле отмеряется от чёрного тела, а не от рамки: подложки
            // тянутся во всю ширину, и вогнутое плечо формы съедало у них
            // три четверти бокового поля — сбоку оставалось четыре точки
            // против двенадцати снизу, и подложка нижним углом почти
            // упиралась в скругление панели.
            bodyPadding: NotchStyle.bottomPadding
        ) {
            // Погода уехала из правого угла в левое крыло, освободив правое
            // под настройки: в строке музыки шестерёнка отнимала ширину
            // у названия трека.
            HStack(spacing: 6) {
                if let weather {
                    WeatherCorner(snapshot: weather, notchHeight: metrics.notchHeight)
                }
                if let onOpenAwake {
                    CaffeineButton(isOn: isAwake, action: onOpenAwake)
                }
            }
            .frame(height: metrics.notchHeight)
        } trailing: {
            HStack(spacing: 2) {
                if let onAsk {
                    NotchPanelButton(symbol: "sparkles", hint: askHint, action: onAsk)
                }
                NotchPanelButton(symbol: "gearshape", hint: t("Настройки"), action: onOpenSettings)
            }
        } content: {
            VStack(spacing: NotchStyle.gridSpacing) {
                musicRow
                schedule
            }
            .foregroundStyle(.white)
        }
    }

    /// Встречи и задачи — отдельными подложками, а не одной с линией внутри.
    ///
    /// Сначала их разделяли `Divider()`, потом волосяная линия внутри общей
    /// карточки — и то и другое читалось как полоса поперёк панели. Две
    /// отдельные подложки на чёрном разделяются сами: границу показывает
    /// зазор между ними, а не проведённая черта.
    @ViewBuilder
    private var schedule: some View {
        VStack(spacing: NotchStyle.cardGap) {
            // Подложка на каждое время начала. Одновременные встречи лежат
            // в общей: они про один и тот же слот, и по отдельным карточкам
            // читались бы как несвязанные события в разные часы. А следующее
            // время — уже другой слот, и общая подложка слепила бы «сейчас»
            // и «потом» в один блок расписания.
            ForEach(eventGroups, id: \.first?.id) { group in
                card {
                    VStack(spacing: NotchStyle.rowSpacing) {
                        ForEach(group) { event in
                            eventRow(event)
                        }
                    }
                }
            }
            if !tasks.isEmpty {
                card { tasksList }
            }
        }
    }

    /// Те же группы, по которым считается высота панели: расчёт один,
    /// иначе нарисованное разойдётся с размером окна.
    private var eventGroups: [[CalendarItem]] {
        NotchContent(events: events).eventGroups
    }

    /// Отступ содержимого от края подложки. Он же задаёт вертикаль, по которой
    /// выравнивается обложка трека.
    static let cardInset: CGFloat = 12

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, Self.cardInset)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Та же заливка, что у круглых кнопок панели: подложки и кнопки
            // лежат рядом, и разная плотность читалась как небрежность.
            .background(
                RoundedRectangle(cornerRadius: NotchStyle.cardRadius, style: .continuous)
                    .fill(.white.opacity(NotchButtonStyle.restingFill))
            )
    }

    private var musicRow: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(trackTitle)
                    .font(.system(size: NotchStyle.font(13), weight: .semibold))
                    .lineLimit(1)
                // Пустая вторая строка не рисуется вовсе: без неё название
                // встаёт по центру обложки, а не липнет к её верху.
                if hasTrack, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: NotchStyle.font(11)))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            transport
            hubButton
        }
        // Тот же отступ, что у содержимого подложек ниже: без него обложка
        // стояла левее строки встречи, и левый край панели выглядел рваным.
        .padding(.horizontal, Self.cardInset)
    }

    /// Переход в меню всех функций — кнопкой, а не жестом.
    ///
    /// Горизонтальный свайп двумя пальцами в этом же состоянии уже занят
    /// переключением трека, а вертикальный — раскрытием панели; вешать на них
    /// третий смысл значило бы сделать все жесты ненадёжными: система
    /// не отличит намерение по одному движению.
    ///
    /// Раньше кнопка вела прямо в команды. Теперь функций больше, чем одна,
    /// и вести из панели в одну из них, минуя остальные, — произвол.
    private var hubButton: some View {
        button("square.grid.2x2.fill", hint: t("Всё сразу"), action: onOpenHub)
            .padding(.leading, 6)
    }

    /// Играет ли что-нибудь на самом деле. MediaRemote в паузах между
    /// треками присылает запись с пустым названием — по одному только `nil`
    /// это не отличить.
    private var hasTrack: Bool {
        !(music.nowPlaying?.title ?? "").isEmpty
    }

    /// Название трека либо честное «ничего не играет».
    ///
    /// Проверяется не только `nil`: MediaRemote в паузах между треками
    /// присылает запись с пустым названием, и строка молча оставалась
    /// пустой — панель выглядела не «музыки нет», а «что-то не загрузилось».
    private var trackTitle: String {
        let title = music.nowPlaying?.title ?? ""
        return title.isEmpty ? t("Ничего не играет") : title
    }

    /// Исполнитель — и только он. Состояние связи с хелпером («подключён»)
    /// подписью под названием быть не должно: это слово для журнала, а не
    /// для человека, и под «ничего не играет» оно читается как ошибка.
    private var subtitle: String {
        music.nowPlaying?.artist ?? ""
    }

    /// Задачи получили собственные строки, а не подпись под треком: пока
    /// играла музыка, подпись была занята исполнителем, и включённая
    /// интеграция с Things не показывала ничего вовсе.
    private var tasksList: some View {
        Button(action: onOpenTasks) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleTasks.enumerated()), id: \.offset) { index, task in
                    taskRow(task, isLast: index == visibleTasks.count - 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private var visibleTasks: [String] {
        Array(tasks.prefix(NotchMetrics.maxVisibleTasks))
    }

    private func taskRow(_ task: String, isLast: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .font(.system(size: NotchStyle.font(9), weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            Text(task)
                .font(.system(size: NotchStyle.font(12)))
                .lineLimit(1)

            Spacer(minLength: 8)

            // Остаток списка показываем последней строкой, чтобы не отнимать
            // место у самих задач.
            if isLast, tasks.count > visibleTasks.count {
                Text("+\(tasks.count - visibleTasks.count)")
                    .font(.system(size: NotchStyle.font(11), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize()
            }
        }
        .frame(height: NotchMetrics.taskRowHeight)
    }

    private func eventRow(_ event: CalendarItem) -> some View {
        HStack(spacing: 10) {
            // Нажатие на саму строку открывает запись в её приложении.
            // Кнопки ссылки справа живут отдельно: у них своё действие,
            // и попасть в них мимо строки должно быть можно.
            Button { onOpenItem(event) } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(event.color)
                        .frame(width: 7, height: 7)

                    // Название на своей строке, время под ним подписью.
                    // В одну строку они делили ширину с кнопкой встречи,
                    // и название обрезалось на третьем слове — притом что
                    // именно оно и отвечает на вопрос «что за встреча».
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title)
                            .font(.system(size: NotchStyle.font(12)))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(event.isAllDay ? event.timeLabel : "\(event.timeLabel) · \(event.countdown())")
                            .font(.system(size: NotchStyle.font(10), weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)
                }
                // Высота задана, а не выведена из содержимого: расчёт размера
                // панели опирается на неё, и «примерно столько» разъезжается
                // с нарисованным на пустую полосу внизу. Она же задаёт высоту
                // всей строки — кнопки ссылки справа ниже и тянутся за ней.
                .frame(height: NotchMetrics.eventRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            // Подсказкой, а не именем: имя строки — название самой встречи,
            // и подменять его на «Открыть в Календаре» значило бы сделать
            // все строки расписания неразличимыми на слух.
            .notchActionHint(t("Открыть в Календаре"))

            if let link = event.link {
                Button { onCopyLink(link.url) } label: {
                    Image(systemName: "link")
                        .font(.system(size: NotchStyle.font(11), weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(Circle().fill(.white.opacity(0.18)))
                }
                .buttonStyle(PressableStyle())
                .notchHint(t("Скопировать ссылку"))

                Button { onJoin(link.url) } label: {
                    Label(link.provider.title, systemImage: link.provider.symbol)
                        .font(.system(size: NotchStyle.font(11), weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.22)))
                }
                .buttonStyle(PressableStyle())
                .fixedSize()
            }
        }
    }

    private var artwork: some View {
        Group {
            if let data = music.nowPlaying?.artwork, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                    )
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous))
    }

    /// Только «играть»: перематывают свайпом двумя пальцами.
    ///
    /// Кнопки «назад» и «вперёд» убраны намеренно. Они занимали треть панели,
    /// повторяя жест, который и так работает, — а место нужнее названию трека:
    /// оно обрезалось на третьем слове.
    private var transport: some View {
        let isPlaying = music.nowPlaying?.isPlaying == true
        // Подпись меняется вместе со значком, а не остаётся одной на оба
        // состояния: значок «пауза» и значок «играть» — это разные кнопки
        // для того, кто их не видит.
        return button(
            isPlaying ? "pause.fill" : "play.fill",
            hint: isPlaying ? t("Пауза") : t("Играть")
        ) {
            music.send(.togglePlayPause)
        }
    }

    private func button(
        _ symbol: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: NotchStyle.font(13), weight: .medium))
                .foregroundStyle(.white)
        }
        // Отклик на нажатие и вибрация живут в стиле, а не здесь.
        .buttonStyle(NotchButtonStyle())
        .notchHint(hint)
    }
}
