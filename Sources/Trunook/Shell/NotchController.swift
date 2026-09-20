import TrunookXPC
import AppKit
import SwiftUI
import Combine

/// Связывает источники событий с представлением.
///
/// Сам он ни за окном, ни за жестами, ни за накладками уже не следит:
/// окно держит `NotchWindowHost`, руку слушает `NotchInput`, порядок накладок
/// хранит `OverlayRouter`. Здесь остаётся то, ради чего эти трое существуют, —
/// службы и решения о том, что показать.
final class NotchController {
    let music = MusicClient()
    let activities = ActivityCenter(settings: .shared)
    let battery = BatteryMonitor()
    let calendar = CalendarService()
    /// Состояние мини-календаря: листаемый месяц, выбранный день и событие
    /// на правке. Заводится здесь же, потому что читает ту же службу.
    private(set) lazy var planner = CalendarPlanner(service: calendar)
    /// Кольцо быстрого доступа: открыто ли и куда метит рука.
    let ring = QuickRing()
    let things = ThingsService()
    let commands = CommandRunner()
    let meeting = MeetingService()
    let clipboard = ClipboardService()
    let assistant = AssistantSession()
    let weather = WeatherService()
    let shelf = ShelfStore()
    let timer = TimerService()
    let monitor = MonitorService()
    let updates = UpdateService()
    /// Надиктовать текст в поле — своим слушателем, не тем, которым
    /// слушает голосовой заход: диктовать в заметку и спрашивать голосом
    /// одновременно нельзя, но гасить друг друга они не должны.
    let dictation = Dictation()

    /// Исполнитель того, о чём просит модель.
    ///
    /// Лениво: службы выше по списку к этому мигу уже созданы, а сам
    /// помощник у большинства выключен — заводить его всем подряд незачем.
    /// Чем ответить кругу, когда человек нажмёт на карточке.
    ///
    /// Держится здесь, а не в карточке: карточка — значение, она ничего
    /// не исполняет, и замыкание в ней сделало бы её несравнимой,
    /// а по сравнению вырез решает, менялось ли что-нибудь.
    private var pendingAnswer: ((AgentToolResult) -> Void)?

    private(set) lazy var agent = AgentRunner(
        calendar: calendar,
        timer: timer,
        notes: notes,
        weather: weather,
        settings: settings
    )
    /// Текст телесуфлера. У контроллера, а не у окна: телесуфлер живёт
    /// накладкой в вырезе — у самой камеры, — и своего окна у него нет.
    let teleprompter = TeleprompterStore()
    let notes = NotesService()
    /// Сводка новостей по расписанию. Без включённой настройки тикает
    /// вхолостую: расписание спрашивается, но ничего не собирается.
    let digest = DigestService()
    /// Слежка за сайтами. Так же молчит, пока её не включили.
    let siteWatch = SiteWatchService()
    /// Вкладка и номер сводки в панели — переживают закрытие накладки.
    let feedsPanel = FeedsPanelState()

    /// Представление дня, стоявшее до отладочного показа шкалы.
    private var viewBeforeTimeline: CalendarDayView?
    /// Синхронизация заметок с хранилищем Obsidian. По умолчанию выключена
    /// и в этом состоянии не заводит ни таймера, ни слежения за папкой.
    let obsidian = ObsidianService()
    /// Смысловые связи между заметками. Работают только при включённой
    /// настройке и доступной модели.
    let linker = NoteLinker()
    /// Отбор заметок под вопрос по смыслу. Живёт рядом со связями: обе
    /// работы стоят на одних и тех же векторах.
    let retriever = NotesRetriever()
    /// Набранное в панели модели. Живёт у контроллера, а не в панели:
    /// панель исчезает вместе с накладкой, а черновик переживать её обязан.
    let draft = NoteDraft()
    /// Подтверждение внутри панели. Обычные плашки событий из-под накладки
    /// не видны: накладка важнее плашки по расчёту состояния.
    let flash = PanelFlash()
    /// Голосовой заход. Разговор берёт существующий: спросить голосом
    /// и дописать текстом — это одна переписка, а не две.
    lazy var voice = VoiceSession(assistant: assistant, notes: notes)
    /// Жест вызова: модификатор, нажатый дважды. Мимо Carbon — тот умеет
    /// только сочетания с обычной клавишей.
    private let voiceHotKey = VoiceHotKey()
    /// Запись разговора с расшифровкой в заметку. Берёт готовые заметки
    /// и хранилище: результат её работы — обычная заметка, и заводить
    /// ей свой путь в базу незачем.
    lazy var recorder = RecorderService(notes: notes, obsidian: obsidian)
    /// Проигрыватель записей. Отдельно от записи: слушают потом и независимо
    /// от того, идёт ли новая запись.
    let player = RecordingPlayer()
    /// Удержание экрана от гашения — чашка кофе в раскрытой панели.
    let wake: WakeGuard
    /// Блокировка клавиатуры для чистки.
    let keyboardLock = KeyboardLock()
    /// Журнал воды: общий с плиткой главного экрана.
    let water = WaterLog.shared

    private let alerts = EventAlertScheduler()
    /// Отдельное окно приёма файлов: сам вырез принимать их не может,
    /// он живёт выше уровня перетаскивания. Устройство — в `ShelfDropWindow`.
    private let shelfDrop = ShelfDropWindow()

    /// Вызывается кнопкой настроек в раскрытой панели.
    var onOpenSettings: (() -> Void)?
    /// Открыть настройки сразу на нужном разделе.
    var onOpenSettingsTab: ((SettingsSelection.Tab) -> Void)?
    /// Залп конфетти из чёлки. Окном залпа владеет `AppDelegate`.
    var onCelebrate: (() -> Void)?
    /// Показать описание выпуска. Окном знакомства владеет `AppDelegate` —
    /// контроллер выреза о нём не знает и знать не должен.
    var onOpenReleaseNotes: (() -> Void)?

    private let settings: Settings
    private let state = NotchState()

    private let host = NotchWindowHost()
    /// Кот в чёлке: изредка разыгрывает сценку, пока вырезу нечего показывать.
    let critter = NotchCritter()
    /// Погодные сценки под чёлкой при смене погоды.
    let weatherScenes = WeatherScenePlayer()
    /// Напоминания о перерыве, воде и разминке.
    private lazy var breaks = BreakReminders(settings: settings)
    /// Какой экран у острова и где стоят отражения.
    private let screens = NotchScreens()
    private let router: OverlayRouter
    private let input: NotchInput
    private let purr: PurrEffects
    private let chime = ChimePlayer()

    private var swipeResetTimer: Timer?
    /// Раз в несколько часов записи сверяются со сроком хранения.
    private var retentionTimer: Timer?
    private var retentionObservation: AnyCancellable?
    /// Срок, по которому чистили последний раз: настройки меняются часто,
    /// а чистить по каждой смене незачем.
    private var lastRetentionDays: Int?
    private var calendarObservation: AnyCancellable?
    private var thingsObservation: AnyCancellable?
    /// Открыт ли главный экран с плиткой нагрузки — от этого зависит опрос.
    private var monitorObservation: AnyCancellable?
    /// Следит за набором вопроса: подсветка действий гаснет с первой буквой.
    private var questionObservation: AnyCancellable?
    /// Метка сводок меняет размер свёрнутой чёлки — окно обязано узнать.
    private var feedsObservation: AnyCancellable?
    /// Ход обновления — для проверки, запущенной из меню.
    private var updateObservation: AnyCancellable?
    /// Проверку запустил человек из меню: каждый её шаг показывается в чёлке.
    /// Фоновые проверки остаются тихими — сообщает только готовое обновление.
    private var isReportingUpdate = false

    /// Плашку полки убрали крестиком. Держится до следующего файла:
    /// человек уже знает, что на полке лежит.
    private var shelfChipDismissed = false

    /// На сколько точек зона приёма спускается ниже чёлки.
    ///
    /// Не запас на промах, а обход системного жеста: курсор, задержанный
    /// у верхней кромки во время перетаскивания, открывает Mission Control.
    /// Отменить жест нечем, поэтому файл принимается заметно ниже кромки —
    /// вести к самому краю не нужно вовсе.
    ///
    /// Раньше за эту полосу платили нажатиями: окно, принимающее файлы,
    /// не может быть прозрачным для мыши, и 185×128 точек под чёлкой
    /// не нажимались никогда. Теперь окно оживает только на время
    /// перетаскивания, и платы больше нет.
    private static let dropStripReach: CGFloat = 96

    init(settings: Settings = .shared) {
        self.settings = settings
        wake = WakeGuard(settings: settings)
        router = OverlayRouter(state: state, host: host)
        input = NotchInput(state: state, settings: settings, host: host)
        purr = PurrEffects(state: state)
    }

    func start() {
        notes.start()
        installShelf()
        installHost()
        installInput()
        // Окно строится после того, как хост узнал, из чего собирать вёрстку.
        placeScreens(force: true)
        connectSources()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func stop() {
        input.stop()
        swipeResetTimer?.invalidate()
        swipeResetTimer = nil
        retentionTimer?.invalidate()
        retentionTimer = nil
        critter.stop()
        breaks.stop()
        weatherScenes.stop()
        purr.shutdown()
        chime.shutdown()
        TimerDialGrip.shared.shutdown()
        voiceHotKey.stop()
        voice.shutdown()
        // Экран отпускаем явно: система сделала бы это и сама вместе
        // с процессом, но полагаться на это, когда выключение штатное,
        // незачем.
        wake.disable()
        keyboardLock.unlock()
        HotKeyCenter.shared.stop()
        battery.stop()
        music.stop()
        calendar.stop()
        things.stop()
        meeting.stop()
        clipboard.stop()
        weather.stop()
        timer.stop()
        monitor.stop()
        updates.stop()
        digest.stop()
        siteWatch.stop()
        alerts.stop()
        calendarObservation = nil
        thingsObservation = nil
        shelfDrop.hide()
        host.hide()
    }

    @objc private func screensChanged() {
        placeScreens(force: true)
    }

    /// Поставить остров на нужный экран — по режиму из настроек.
    ///
    /// Режим читается на каждом тике: смену в настройках `NotchScreens`
    /// замечает сам и пересобирает окна, отдельной подписки не нужно.
    private func placeScreens(force: Bool = false) {
        screens.place(
            mode: settings.notchScreenMode,
            host: host,
            isBusy: state.overlay != nil || state.isPinnedOpen || state.isHovered
                || ring.isOpen || voice.phase != nil || state.isDraggingOut,
            force: force
        )
    }

    /// Экран, на котором сейчас стоит остров.
    var notchScreen: NSScreen? { host.geometry?.screen }

    // MARK: - Сборка узлов

    private func installHost() {
        host.makeRoot = { [weak self] metrics, id in self?.makeRootView(metrics: metrics, displayID: id) }
        host.contentSize = { [weak self] metrics, id in self?.snapshot(for: id).size(metrics: metrics) ?? .zero }
        host.onActivate = { [weak self] id in self?.state.activeDisplay = id }
        host.onRightClick = { [weak self] in self?.openRingMenu() }
        host.onRebuild = { [weak self] geometry, metrics in
            self?.rebuildShelfDrop(geometry: geometry, metrics: metrics)
        }
        router.onChange = { [weak self] overlay in self?.applyOverlay(overlay) }
        router.onCursorExit = { [weak self] in self?.collapseAfterOverlay() }
    }

    private func installInput() {
        input.onHoverChanged = { [weak self] hovered in self?.setHovered(hovered) }
        input.onExpand = { [weak self] in self?.expandPanel() }
        input.onCollapse = { [weak self] in self?.collapsePanel() }
        input.onSwipe = { [weak self] direction in self?.performSwipe(direction) }
        input.onOverlayHover = { [weak self] location in self?.router.updateHover(at: location) }
        input.onDismissOverlay = { [weak self] cause in self?.dismissOverlay(cause) }
        input.onOverlayKey = { [weak self] event in self?.handleOverlayKey(event) ?? false }
        // Прозрачность окна пересчитывается на каждом движении курсора,
        // а не только в тике опроса: между тиками десятая доля секунды,
        // и быстрый бросок к полоске с нажатием в неё не уложился бы.
        input.onCursorMoved = { [weak self] in
            // Сеанс перетаскивания заводится чуть позже, чем курсор тронулся:
            // зона приёма ждёт его на каждом движении.
            if let self, self.input.isDragging { self.shelfDrop.isArmed = self.input.isDraggingData }
            self?.updateWindowInteractivity()
            self?.updateCritterGaze()
            self?.updateWindowSlot()
        }
        // Зона приёма файлов оживает только пока что-то тащат: в покое она
        // прозрачна для мыши и не ест нажатия по тому, что под чёлкой.
        // Оживает только когда тащат данные, а не окно и не выделение: см.
        // `NotchInput.isDraggingData`. Гаснет — вместе с перетаскиванием.
        input.onDragChanged = { [weak self] dragging in
            guard let self else { return }
            self.shelfDrop.isArmed = dragging && self.input.isDraggingData
        }
        // То, что пересчитывается по времени, а не по событию.
        input.onTick = { [weak self] in
            self?.updateWindowSnap()
            self?.keepBreakReminder()
            self?.checkCountdownReached()
            self?.placeScreens()
            self?.interruptCritterIfBusy()
            self?.updateWeatherScene()
            self?.updateCountdown()
            self?.host.updateInteractiveRect()
            // Проверка нажатий тоже пересчитывается по времени: таймер
            // запускают из панели, а гаснет он сам, и ловить оба края
            // отдельными вызовами — верный способ однажды забыть.
            self?.updateWindowInteractivity()
        }
        input.onPettingStart = { [weak self] in
            DebugLog.write("вырез гладят — мурчим")
            self?.purr.start()
        }
        input.onPettingStop = { [weak self] in
            DebugLog.write("гладить перестали")
            self?.purr.stop()
        }
        input.onQuickRingOpen = { [weak self] in self?.openQuickRing() }
        input.onQuickRingMove = { [weak self] point in
            guard let self else { return }
            let count = HubEntry.ringCases.count
            // Удержание выбирает направлением руки, щелчок — попаданием:
            // см. `QuickRingLayout.circleIndex`.
            let picked = self.ring.isSticky
                ? QuickRingLayout.circleIndex(at: point, count: count)
                : QuickRingLayout.index(at: point, count: count)
            // Толчок трекпада на каждом новом кружке: рука ведёт кольцо,
            // не глядя прямо на него, и подтверждение нужно ей, а не глазу.
            if picked != nil, picked != self.ring.highlighted { Haptics.tap(.alignment) }
            self.ring.move(to: picked)
            // Над кружком окно ловит мышь, мимо — пропускает насквозь.
            // Пересчёт здесь, а не по движению курсора: то приходит раньше,
            // чем подсветка успела смениться.
            if self.ring.isSticky { self.updateWindowInteractivity() }
        }
        input.onQuickRingClose = { [weak self] in self?.closeQuickRing() }
        input.start()
    }

    // MARK: - Источники событий

    private func connectSources() {
        battery.onEvent = { [weak self] kind in
            self?.activities.present(kind)
        }
        battery.start()

        music.onTrackChanged = { [weak self] _ in
            guard let self, self.settings.showTrackChanges else { return }
            self.activities.present(.trackChanged)
        }
        if settings.musicEnabled {
            music.start()
        }

        commands.onOutcome = { [weak self] outcome in
            switch outcome {
            case let .running(title):
                self?.activities.present(.command(text: title + "…", state: .running))
            case let .done(text):
                self?.activities.present(.command(text: text, state: .done))
            case let .failed(text):
                self?.activities.present(.command(text: text, state: .failed))
            }
        }
        commands.onAssistantPrompt = { [weak self] title, prompt, model in
            self?.openAssistant(title: title, prompt: prompt, model: model)
        }
        commands.onSaveToNotes = { [weak self] text in
            self?.saveTextToNotes(text, origin: .selection, done: t("Записано в заметки"))
        }
        installHotKeys()
        installVoice()

        alerts.onAlert = { [weak self] item, minutes in
            self?.activities.present(.meeting(item: item, minutesBefore: minutes))
        }
        alerts.start()

        // Планировщик и обратный отсчёт питаются одним и тем же списком.
        calendarObservation = calendar.$upcoming.sink { [weak self] items in
            self?.refreshSchedule(calendarItems: items)
            self?.updateCountdown(from: items)
        }
        // Задачи Things с назначенным временем тоже должны предупреждать.
        thingsObservation = things.$tasks.sink { [weak self] _ in
            self?.refreshSchedule()
        }
        // Нагрузку опрашивают и панель, и плитка главного экрана. Решение
        // одно на обоих — иначе закрытие одной гасило бы опрос у другой.
        // Значения берутся из самих публикаций: `@Published` сообщает до того,
        // как свойство поменялось, и чтение из `state` дало бы прежнее.
        monitorObservation = state.$overlay
            .combineLatest(state.$isPinnedOpen, settings.objectWillChange.map { _ in () }.prepend(()))
            .receive(on: RunLoop.main)
            .sink { [weak self] overlay, isPinnedOpen, _ in
                self?.updateMonitorPolling(overlay: overlay, isPinnedOpen: isPinnedOpen)
            }
        // Начали печатать — подсветка с действий снимается. Её ставит само
        // приложение, когда ответ дописан, и оставлять её поверх набранного
        // значит обещать Enter не тому: обведённой стоит «Скопировать»,
        // а уйдёт вопрос. Enter и так отдаётся вопросу, но обещание на экране
        // должно совпадать с делом.
        questionObservation = draft.$question.sink { [weak self] text in
            guard let self else { return }
            // Список «@» — про то, что набирают прямо сейчас, поэтому он
            // пересобирается на каждое изменение, включая опустевшее поле.
            self.refreshMentions(for: text)
            // Список инструментов — там же и по тому же поводу. Одновременно
            // им не бывать: «/» ловится только в начале вопроса, а «@» —
            // в его хвосте.
            self.refreshSlash(for: text)
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            guard self.assistant.highlightedAnswerAction != nil else { return }
            self.assistant.highlightedAnswerAction = nil
            NotchHintTracker.shared.focus(nil)
        }
        meeting.onCopiedLink = { [weak self] _ in
            self?.activities.present(.command(text: t("Ссылка встречи в буфере"), state: .done))
        }

        clipboard.onCopy = { [weak self] entry in
            guard let self, self.settings.clipboardShowsChip else { return }
            // Пока история открыта, плашка не нужна: список и так обновился
            // на глазах, а всплыла бы она уже после закрытия панели.
            guard self.state.overlay == nil else { return }
            self.activities.present(.clipboard(entry: entry))
            self.updateWindowInteractivity()
        }

        timer.onFinished = { [weak self] phase in
            guard let self else { return }
            // Виброотклик тут не украшение: вырез мог быть свёрнут, а звука
            // у приложения нет — толчок единственное, что заметно, если
            // человек смотрит в другое окно.
            Haptics.tap(.levelChange)
            if self.settings.timerSoundEnabled { self.chime.play() }
            self.activities.present(.timer(
                text: phase == .rest ? t("Перерыв окончен") : t("Время вышло")
            ))
            self.updateWindowInteractivity()
        }

        // Плашка смены трека данных не несёт — читает их живьём. Диктору
        // текст нужен ровно тогда же, поэтому и он берётся отсюда.
        activities.nowPlaying = { [weak self] in self?.music.nowPlaying }

        // Срок удержания экрана вышел — говорим об этом плашкой. Молча
        // отпустить экран значило бы оставить человека гадать, почему тот
        // вдруг снова гаснет.
        wake.onExpired = { [weak self] in
            self?.activities.present(.caffeine(change: .expired))
        }

        // Срок блокировки вышел — панель с отсчётом больше не нужна.
        keyboardLock.onExpired = { [weak self] in
            guard let self else { return }
            if self.state.overlay == .keyboardLock { self.router.close() }
            Haptics.tap(.levelChange)
        }

        weather.onAlert = { [weak self] text, symbol in
            self?.activities.present(.weather(text: text, symbol: symbol))
        }
        // Сценка встаёт в очередь и на ближайшем тике играет вместе
        // с плашкой о погоде, капая из-под её края.
        weather.onSceneChange = { [weak self] scene in
            guard let self, self.settings.weatherScenesEnabled else { return }
            self.weatherScenes.queue(scene)
            // Спросить на ближайшем тике, а не через две секунды: плашка
            // уже раскрывается, и сценке надо начаться вместе с ней.
            self.weatherSceneCheckedAt = .distantPast
        }
        weather.start()

        // Плашка показывается один раз за запуск и только на готовом
        // к установке: загрузка тихая по замыслу, а отказы человек увидит
        // в настройках, когда сам туда придёт.
        updates.onReady = { [weak self] release in
            self?.activities.present(.update(version: release.version.text))
        }
        updates.start()
        updateObservation = updates.$state
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.reportManualUpdate(state) }

        digest.onReady = { [weak self] ready in
            self?.activities.present(.digestReady(entries: ready.entryCount))
        }
        siteWatch.onChange = { [weak self] watch, change in
            guard let self, let url = watch.pageURL else { return }
            Haptics.tap(.levelChange)
            self.activities.present(.siteChanged(name: watch.displayName, text: change.text, url: url))
        }
        feedsObservation = digest.$hasUnseen.map { _ in () }
            .merge(with: siteWatch.$states.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.updateWindowInteractivity()
                self?.host.updateInteractiveRect()
            }
        digest.start()
        siteWatch.start()

        calendar.start()
        things.start()
        meeting.start()
        clipboard.start()

        obsidian.onNotesChanged = { [weak self] in
            self?.notes.refresh()
            // Сверка могла привезти правки из хранилища — у изменившихся
            // заметок вектор смысла устарел.
            self?.linker.refreshAll()
        }
        obsidian.start()

        notes.onSaved = { [weak self] id in self?.linker.enqueue(id: id) }
        installAudioRetention()
        critter.onDue = { [weak self] in self?.critterDue() }
        critter.frequency = { [weak self] in self?.settings.critterFrequency ?? .normal }
        critter.start()
        breaks.onDue = { [weak self] kind in self?.remindBreak(kind) ?? false }
        breaks.start()

        // Заметка из записи готова — показать её так же, как показывают
        // сохранённое выделение: плашкой, если панель закрыта, и вспышкой
        // внутри панели, если открыта.
        recorder.onNote = { [weak self] note, warning in
            self?.announceRecording(note, warning: warning)
        }
        recorder.onFailure = { [weak self] reason in
            self?.announce(reason)
        }
        linker.writeToVault = { [weak self] id, rows in
            self?.obsidian.writeLinks(NoteLinker.vaultLines(rows), forNote: id)
        }
    }

    /// Планировщик получает и встречи, и задачи Things: для него это
    /// однородный список записей со временем.
    private func refreshSchedule(calendarItems: [CalendarItem]? = nil) {
        let items = (calendarItems ?? calendar.upcoming) + things.reminders
        alerts.update(items: items)
    }

    /// Обратный отсчёт показываем, пока встреча близко, но ещё не началась.
    private func updateCountdown(from items: [CalendarItem]? = nil) {
        let source = items ?? calendar.upcoming
        guard settings.showCountdown, settings.calendarEnabled else {
            if state.chipItem != nil { state.chipItem = nil }
            return
        }

        let window = settings.countdownWindowMinutes
        let now = Date()
        let candidate = source.first { item in
            guard !item.isAllDay else { return false }
            let minutes = item.minutesUntilStart(from: now)
            return minutes <= window && minutes >= 0
        }
        guard candidate != state.chipItem else { return }
        state.chipItem = candidate
    }

    // MARK: - Быстрые команды

    /// Сочетания задаются пользователем, поэтому набор пересобирается после
    /// каждой правки настроек. Включённость всё равно проверяется в момент
    /// нажатия — так галка действует сразу, без перерегистрации.
    func installHotKeys() {
        HotKeyCenter.shared.unregisterAll()
        // Жест голоса — тоже вызов, и настраивают его в том же окне.
        // Пересобирать его отдельно значило бы однажды забыть.
        installVoiceHotKey()

        // Единственный вход в разговор с моделью: захватить выделенное
        // и открыть панель. Не переключателем, как накладки: нажатие при
        // открытой панели означает «я выделил другое», и захват обязан
        // обновиться, а не свернуть панель вместе с уже набранным вопросом.
        if let capture = settings.assistantHotKey {
            HotKeyCenter.shared.register(capture, name: "захват выделенного") { [weak self] in
                self?.captureAndAsk()
            }
        }

        if settings.clipboardEnabled, let clipboardKey = settings.clipboardHotKey {
            HotKeyCenter.shared.register(clipboardKey, name: "история буфера") { [weak self] in
                self?.toggleClipboard()
            }
        }

        if settings.monitorEnabled, let monitorKey = settings.monitorHotKey {
            HotKeyCenter.shared.register(monitorKey, name: "нагрузка") { [weak self] in
                self?.toggleMonitor()
            }
        }

        if settings.digestEnabled || settings.siteWatchEnabled, let feedsKey = settings.feedsHotKey {
            HotKeyCenter.shared.register(feedsKey, name: "сводки") { [weak self] in
                self?.toggleFeeds()
            }
        }

        if settings.calendarEnabled, let calendarKey = settings.calendarHotKey {
            HotKeyCenter.shared.register(calendarKey, name: "календарь") { [weak self] in
                self?.toggleCalendar()
            }
        }

        if settings.timerEnabled, let timerKey = settings.timerHotKey {
            HotKeyCenter.shared.register(timerKey, name: "таймер") { [weak self] in
                self?.toggleTimer()
            }
        }

        if settings.shelfEnabled, let shelfKey = settings.shelfHotKey {
            HotKeyCenter.shared.register(shelfKey, name: "полка") { [weak self] in
                self?.toggleShelf()
            }
        }

        // Основная панель. Переключателем, как и накладки: нажали при
        // раскрытой — свернулась.
        if let expandedKey = settings.expandedHotKey {
            HotKeyCenter.shared.register(expandedKey, name: "основная панель") { [weak self] in
                self?.toggleExpanded()
            }
        }

        // Создание заметки. Плитки в меню функций у заметок нет: они часть
        // разговора с моделью, и второй способ записать — клавиша.
        if settings.notesEnabled, let notesKey = settings.notesHotKey {
            HotKeyCenter.shared.register(notesKey, name: "новая заметка") { [weak self] in
                self?.toggleNoteComposer()
            }
        }

        // Выделенное — сразу в заметки, ничего не открывая. Отдельно
        // от предыдущего: там открывают пустое поле, чтобы набрать, здесь
        // записывают уже написанное и остаются в своём окне.
        if settings.notesEnabled, let selectionKey = settings.noteSelectionHotKey {
            HotKeyCenter.shared.register(selectionKey, name: "выделенное в заметки") { [weak self] in
                self?.saveSelectionToNotes()
            }
        }

        // Голос сочетанием — только если человек выбрал в списке «Своё
        // сочетание». Иначе вызов идёт жестом, и занимать ещё и букву
        // за человека нельзя.
        if settings.voiceEnabled, settings.voiceTrigger == .hotKey,
           let voiceKey = settings.voiceHotKey {
            HotKeyCenter.shared.register(voiceKey, name: "голос") { [weak self] in
                self?.toggleVoice()
            }
        }

        // Аудиозаметка. Одна клавиша на начать и закончить: пока идёт
        // запись, других дел у неё нет, а искать вторую клавишу ради
        // остановки — лишняя работа памяти.
        if settings.notesEnabled, settings.recordEnabled, let recordKey = settings.recordHotKey {
            HotKeyCenter.shared.register(recordKey, name: "аудиозаметка") { [weak self] in
                self?.recorder.toggleNote()
            }
        }

        // У телесуфлера выключателя нет: он ничего не делает, пока окно
        // закрыто, и выключать в нём нечего.
        if let teleprompterKey = settings.teleprompterHotKey {
            HotKeyCenter.shared.register(teleprompterKey, name: "телесуфлер") { [weak self] in
                self?.toggleTeleprompter()
            }
        }

        // Номерные строки истории. Клавиша работает и когда панель закрыта:
        // смысл в том и есть — вставить позавчерашнее, не открывая ничего.
        if settings.clipboardEnabled, let mask = settings.clipboardSlotModifiers.carbonMask {
            for index in 0..<ClipboardService.hotSlotCount {
                guard let spec = HotKeySpec.clipboardSlot(index, modifiers: mask) else { continue }
                HotKeyCenter.shared.register(spec, name: "буфер \(index + 1)") { [weak self] in
                    guard let self, let entry = self.clipboard.entry(atSlot: index) else { return }
                    self.useClipboard(entry)
                }
            }
        }

        for command in settings.quickCommands {
            guard let shortcut = command.hotKey else { continue }
            let id = command.id
            HotKeyCenter.shared.register(shortcut, name: "слот \(id + 1)") { [weak self] in
                guard let self else { return }
                // Открытая история буфера забирает цифры себе.
                if self.pasteFromOpenClipboard(key: shortcut.keyCode) { return }
                guard self.settings.quickCommandsEnabled else { return }
                guard let current = self.settings.quickCommands.first(where: { $0.id == id })
                else { return }
                // При открытой панели команда берёт захваченное, а не читает
                // выделение заново: фокус уже у выреза, и в чужом окне
                // выделения больше нет. Клавиша и строка списка обязаны
                // делать одно и то же — иначе одна и та же команда работала
                // бы по-разному в зависимости от того, чем её позвали.
                if self.state.overlay == .assistant {
                    self.runCommandFromPanel(current)
                } else {
                    self.run(current)
                }
            }
        }

        // Цифры своего семейства, никем не занятые. Пока история открыта,
        // они тоже её строки: иначе ⌃⌥7 молчал бы там, где ⌃⌥1 вставляет,
        // и правило «цифра — это строка списка» перестало бы быть правилом.
        if settings.clipboardEnabled {
            let taken = Set(settings.quickCommands.compactMap(\.hotKey))
            for index in 0..<ClipboardService.hotSlotCount {
                guard let spec = HotKeySpec.ownDigit(index),
                      !taken.contains(spec),
                      spec.modifiers != settings.clipboardSlotModifiers.carbonMask
                else { continue }
                HotKeyCenter.shared.register(spec, name: "буфер \(index + 1) в панели") { [weak self] in
                    self?.pasteFromOpenClipboard(key: spec.keyCode)
                }
            }
        }
    }

    /// Вставка строки истории цифрой, пока список истории на экране.
    /// Возвращает, забрала ли история это нажатие себе.
    ///
    /// Ряд ⌃⌥1 … ⌃⌥9 поделен между слотами быстрых команд и строками буфера,
    /// и развести их по разным сочетаниям некуда: ⌃⌥ — единственная пара,
    /// которую не занимает ни система, ни привычные приложения. Разводит их
    /// состояние экрана: пока список открыт, человек считает строки глазами,
    /// и цифра означает строку списка, а не слот команды. Раньше здесь молча
    /// срабатывала команда — история закрывалась, и вместо вставки уходил
    /// запрос к модели.
    @discardableResult
    private func pasteFromOpenClipboard(key keyCode: UInt32) -> Bool {
        guard state.overlay == .clipboard,
              settings.clipboardEnabled,
              let index = HotKeySpec.digitIndex(keyCode),
              let entry = clipboard.entry(atSlot: index)
        else { return false }
        useClipboard(entry)
        return true
    }

    /// Проверка кодировки на коротком запросе: логируем и то, что отправили,
    /// и то, что вернулось, побайтово.
    func debugOllamaEcho() {
        let prompt = "Повтори дословно: Привет, мир"
        DebugLog.write("ollama: шлём «\(prompt)», байт \(prompt.utf8.count)")
        ModelClient().generate(prompt: prompt) { result in
            switch result {
            case let .success(answer):
                DebugLog.write("ollama: ответ «\(answer)»")
                DebugLog.write("ollama: байт \(answer.utf8.count), символов \(answer.count)")
            case let .failure(error):
                DebugLog.write("ollama: ошибка \(error.localizedDescription)")
            }
        }
    }

    func debugRunSlot(_ index: Int) {
        guard let command = settings.quickCommands.first(where: { $0.id == index }) else { return }
        // Через ту же развилку, что и настоящее нажатие: открытая история
        // буфера забирает цифры себе. Иначе этот вход проверял бы не то,
        // что происходит на клавише, — синтетические нажатия до Carbon
        // не доходят, и другого способа увидеть развилку из сессии нет.
        if let key = command.hotKey?.keyCode, pasteFromOpenClipboard(key: key) { return }
        run(command)
    }

    /// Команда по своей горячей клавише — из чужого окна, минуя панель.
    ///
    /// Выделение читается здесь же: панель ещё не открыта, фокус чужой,
    /// и это последний момент, когда выделенное вообще можно взять.
    private func run(_ command: QuickCommand) {
        SelectionReader.read { [weak self] selection in
            self?.commands.run(command, selection: selection ?? "")
        }
    }

    /// Команда из списка в открытой панели.
    ///
    /// Выделение не читается: оно уже захвачено, показано плашкой, и человек
    /// мог его убрать. Спрашивать систему заново значило бы взять не то, что
    /// он видит на экране, — фокус давно у панели, и выделения в чужом окне
    /// больше нет.
    private func runCommandFromPanel(_ command: QuickCommand) {
        assistant.choosingModelFor = nil
        commands.run(command, selection: assistant.captured)
    }

    /// Команда с плитки главного экрана.
    ///
    /// Тем же путём, что и по горячей клавише, а не как из панели: главный
    /// экран фокус не отбирает, передним стоит чужое приложение, и выделение
    /// в нём ещё живо — это последний момент, когда его можно взять.
    /// Захваченного текста у панели здесь нет вовсе: её не открывали.
    ///
    /// Панель с ответом откроется сама: запрос к модели уходит через
    /// `onAssistantPrompt`, и адресатом вставки запомнится то приложение,
    /// из которого текст и взят.
    private func runCommandFromHome(_ command: QuickCommand) {
        DebugLog.write("плитка команд: «\(command.title)»")
        run(command)
    }

    // MARK: - Накладки

    /// Мониторинг опрашивает систему только пока он на экране: иначе
    /// он сам стал бы той нагрузкой, которую показывает. На экране он
    /// двояко — панелью или плиткой открытого главного экрана.
    private func updateMonitorPolling(overlay: NotchState.Overlay?, isPinnedOpen: Bool) {
        let tileVisible = overlay == nil && isPinnedOpen
            && HomeGrid.place(settings.homeWidgets).placements.contains { $0.widget.kind == .monitor }
        overlay == .monitor || tileVisible ? monitor.start() : monitor.stop()
    }

    /// Побочные действия смены накладки. Само решение приняли в `OverlayRouter`,
    /// здесь — только то, что требует служб.
    private func applyOverlay(_ overlay: NotchState.Overlay?) {
        if overlay != nil {
            Haptics.tap()
            activities.dismiss()
        } else {
            // Панель ушла — напоминание о полке возвращается на её место.
            refreshShelfChip()
        }
        // Список моделей нужен панели разговора: по нему Tab перебирает
        // модель команды. Спрашивался он только из настроек и по нажатию
        // на имя модели — то есть у того, кто ни туда, ни туда не заходил,
        // Tab не делал ничего.
        if overlay == .assistant, settings.ollamaEnabled {
            ModelList.shared.refreshIfNeeded()
        }
        // Открытая панель сводок — и есть «прочитано»: метка в чёлке гаснет.
        if overlay == .feeds {
            digest.markSeen()
            siteWatch.markSeen()
        }
        // Пока полка на экране, зона приёма держится раскрытой: на открытую
        // полку докладывают файлы, и целиться в полоску по чёлке при этом
        // было бы издевательством.
        shelfDrop.isPinnedOpen = overlay == .shelf
        updateWindowInteractivity()
        host.updateInteractiveRect()
    }

    /// Окно ловит мышь, только когда на экране есть во что попадать —
    /// **и только пока курсор над этим находится**.
    ///
    /// Вторая половина правила куплена дорого. Окно, не прозрачное для мыши,
    /// съедает нажатия **во всей своей рамке**, а не только там, где что-то
    /// нарисовано: проверка попаданий в `NotchHostingView` решает лишь, какой
    /// вид внутри получит событие, но наружу, в чужое приложение, его уже
    /// не пустит. Рамка же размером с самую большую панель — 560×388.
    ///
    /// Пока условие было «есть отсчёт до встречи», окно становилось
    /// непрозрачным за полчаса до каждой встречи и оставалось таким всё это
    /// время: прямоугольник 560×388 под чёлкой переставал реагировать
    /// на нажатия целиком. Ровно та же беда, что была у полосы приёма файлов,
    /// и лечится она тем же — не геометрией, а временем.
    ///
    /// Накладка — исключение: она живёт минуты, а не полчаса, и нажатие мимо
    /// её закрывает, то есть съеденный клик там не пропадает зря.
    private func updateWindowInteractivity() {
        // Нарисованное берётся из того же снимка, что и зона нажатий:
        // разойтись им нельзя. Само правило — в `NotchMouseCatch`, оттуда же
        // его проверяет тест.
        host.ignoresMouseEvents = !NotchMouseCatch.catchesMouse(
            hasSomethingDrawn: notchSnapshot.presentation != .collapsed,
            cursorOverVisibleRect: host.visibleRectContainsCursor,
            isDraggingOut: state.isDraggingOut,
            cursorOverRingCircle: ring.isSticky && ring.highlighted != nil
        )
    }

    /// Полоска идущего таймера — или её отсутствие. Спрашивают и расчёт
    /// состояния, и проверка нажатий, и разойтись им нельзя.
    private var timerChip: TimerChip? {
        settings.timerEnabled ? timer.chip : nil
    }

    /// Метка сводок — по той же причине одним местом на оба спроса.
    private var feedChip: FeedChip? {
        let news = settings.digestEnabled && digest.hasUnseen
        let sites = settings.siteWatchEnabled && siteWatch.hasUnseen
        return news || sites ? FeedChip(digest: news, sites: sites) : nil
    }

    /// Единственное место, где состояние выреза собирается из служб.
    ///
    /// Спрашивают отсюда оба: и зона нажатий окна, и вёрстка, которой снимок
    /// отдаётся готовым. Раньше вёрстка собирала свой — и списки полей
    /// разошлись: она передавала долю свайпа, здесь её не было, а доля решает,
    /// расходится ли остров вширь. Полоску таймера они брали по-разному тоже:
    /// вёрстка у самой службы, контроллер — с оглядкой на настройку. Значит
    /// при выключенном таймере рисовалось одно, а мерилось другое.
    ///
    /// Урок записан в `NotchResolver`: свести расчёт в один **тип** мало,
    /// тип не мешает построить его дважды. Сводить надо в одно место вызова.
    private var notchSnapshot: NotchSnapshot { notchInputs.resolve() }

    private var notchInputs: NotchInputs {
        NotchInputs(
            overlay: state.overlay,
            swipe: state.swipe,
            pendingSwipe: state.pendingSwipe,
            swipeProgress: state.swipeProgress,
            isHovered: state.isHovered,
            isPinnedOpen: state.isPinnedOpen,
            chip: state.chipItem,
            recordingChip: recorder.chip,
            timerChip: timerChip,
            caffeineChip: wake.chip,
            feedChip: feedChip,
            activity: activities.current,
            track: music.nowPlaying,
            // Ближайшие встречи подряд, а не «ближайшее время и следующее»:
            // так было у прежней панели, и плитка высотой в два ряда показывала
            // две встречи при месте под три — третье время отбрасывалось.
            events: Array(calendar.upcoming.prefix(NotchMetrics.maxVisibleEvents)),
            taskCount: things.todayTitles.count,
            meetingActions: meeting.availableActions.count,
            clipboardRows: clipboard.entries.count,
            assistantTranscript: assistant.transcript,
            assistantIsStreaming: assistant.isStreaming,
            assistantQuestion: draft.question,
            assistantMode: draft.mode,
            assistantHasCapture: !assistant.captured.isEmpty,
            assistantCaptureExpanded: assistant.isCaptureExpanded,
            assistantCommandRows: visibleCommands.count,
            // Один слот на два списка — «@» и «/», — и высота у него одна.
            // Порядок тот же, что в вёрстке: открыт список инструментов —
            // считаем по нему.
            assistantMentionRows: assistant.isPickingSlash
                ? max(1, min(assistant.slashMatches.count, PickerRows<SlashTool>.visibleRows))
                : (assistant.isPickingMention
                    ? max(1, min(assistant.mentionMatches.count, PickerRows<Mention>.visibleRows))
                    : nil),
            assistantModelEnabled: settings.ollamaEnabled,
            assistantPending: assistant.pending != nil,
            assistantHasAnswer: !assistant.answer.isEmpty,
            // Пока держат файлы, полка во весь рост — ровно под окно приёма,
            // которое раздаётся под полную сетку: разделы узнаются по месту
            // курсора, и мишень не должна быть меньше панели.
            shelfCount: state.isShelfDropTarget
                ? ShelfPanel.columns * ShelfPanel.visibleRows
                : shelf.items.count,
            notesRows: notes.notes.count,
            notesEnabled: settings.notesEnabled,
            voicePhase: voice.phase,
            isQuickRingOpen: ring.isOpen,
            homeRows: HomeGrid.place(settings.homeWidgets).rows
        )
    }

    /// Что показывает окно на экране с этим номером.
    ///
    /// Главное окно — всё. Неглавное на главном экране в режиме «Все экраны» —
    /// полоски и плашки, без того, что заведено рукой: с островом работают
    /// на другом экране, а отсчёт до встречи пропадать не должен. Остальные —
    /// пустая полоска: события живут на главном экране, и повторять их
    /// на каждом значило бы показывать одно уведомление трижды.
    private func snapshot(for id: CGDirectDisplayID) -> NotchSnapshot {
        if id == state.activeDisplay { return notchSnapshot }
        if settings.notchScreenMode == .all, screens.isHome(id) {
            return notchInputs.passive().resolve()
        }
        return Self.handleSnapshot
    }

    private static let handleSnapshot = NotchSnapshot(presentation: .collapsed, content: NotchContent())

    // MARK: - Кольцо быстрого доступа

    private func openQuickRing() {
        ring.open()
        DebugLog.write("кольцо: раскрыто")
        Haptics.tap(.levelChange)
        // Форма сменилась на кольцо: окно обязано узнать об этом, иначе
        // зона нажатий останется от прежнего состояния.
        host.updateInteractiveRect()
    }

    /// Руку отпустили. Выбранное открывается, невыбранное — ничего.
    ///
    /// Отпустить, ничего не выбрав, — обычный способ передумать: рука
    /// возвращается к чёлке, и кольцо гаснет. Ради этого у него и есть
    /// мёртвая зона.
    private func closeQuickRing() {
        guard let picked = ring.close() else {
            DebugLog.write("кольцо: закрыто без выбора")
            host.updateInteractiveRect()
            return
        }
        let entries = HubEntry.ringCases
        guard picked < entries.count else { return }
        let entry = entries[picked]
        guard entry.isEnabled(settings) else {
            DebugLog.write("кольцо: «\(entry.title)» выключена в настройках")
            host.updateInteractiveRect()
            return
        }
        DebugLog.write("кольцо: выбрано «\(entry.title)»")
        Haptics.tap(.generic)
        openHubEntry(entry)
    }

    /// Что открывает плитка меню функций. Одна и та же дорога и для меню,
    /// и для кольца: разойдись они, кольцо однажды открывало бы не то.
    func openHubEntry(_ entry: HubEntry) {
        switch entry {
        case .assistant: askAssistant()
        case .notes: openNotes()
        case .calendar: openCalendar()
        case .clipboard: openClipboard()
        case .shelf: openShelf()
        case .timer: openTimer()
        case .monitor: openMonitor()
        case .teleprompter: openTeleprompter()
        case .caffeine: openAwake()
        case .keyboardLock: openKeyboardLock()
        case .news: openFeeds(tab: .news)
        case .sites: openFeeds(tab: .sites)
        case .voice: toggleVoice()
        case .dictation: dictateNote()
        }
    }

    // MARK: - Наведение и раскрытие

    private func setHovered(_ hovered: Bool) {
        DebugLog.write("вырез \(hovered ? "показан мини-вид" : "свёрнут")")
        state.isHovered = hovered
        // Панель ловит мышь только когда видна пользователю. В остальных
        // состояниях окно прозрачно для нажатий.
        updateWindowInteractivity()

        if hovered {
            state.hoverStartedAt = Date()
            Haptics.tap()
            music.refresh()
            // Задачу заводят и тут же открывают вырез посмотреть, появилась ли
            // она: опроса раз в минуту для такого сценария мало.
            things.refresh()
            // Мини-вид важнее досматривания всплывшего события — но плашку,
            // по которой нажимают, наведение убирать не смеет: до неё тогда
            // было бы физически не дотянуться курсором.
            if activities.current?.isInteractive != true {
                activities.dismiss()
            }
        } else {
            // Курсор ушёл — фиксация раскрытия снимается.
            state.isPinnedOpen = false
            state.swipe = nil
        }
        host.updateInteractiveRect()
    }

    /// Нажатие только раскрывает — свернуть можно уводом курсора.
    ///
    /// Переключение туда-обратно было бы опаснее: в раскрытом виде нажатие
    /// по кнопке перемотки рискует продублироваться нажатием по панели,
    /// и трек переключался бы вместе со схлопыванием.
    private func expandPanel() {
        // Пока идёт голосовой заход, нажатие по острову ведёт в разговор,
        // а не раскрывает главную панель: на острове в этот момент шкала
        // и кнопка «замолчать», и человек, нажимающий на него, хочет
        // увидеть разговор глазами, а не музыку с расписанием.
        if voice.isActive {
            openVoiceConversation()
            return
        }
        guard state.isHovered, !state.isPinnedOpen else { return }
        state.isPinnedOpen = true
        DebugLog.write("панель раскрыта полностью")
        Haptics.tap(.levelChange)
        host.updateInteractiveRect()
    }

    /// Накладку убрал ушедший курсор — сворачиваем вырез целиком.
    ///
    /// Без этого из-под закрывшейся накладки выныривало то, что было под ней:
    /// человек открывал «Всё сразу», из него нагрузку или команды, уводил
    /// курсор — и вместо того чтобы свернуться, вырез показывал главную
    /// панель. Держалась она потом до тех пор, пока курсор не покинет **всю
    /// рамку окна** 560×388, то есть несколько секунд.
    ///
    /// Причина в том, что фиксация раскрытия и накладка живут по разным
    /// правилам: накладка закрывается по уходу из своего прямоугольника,
    /// а фиксация снимается по уходу из рамки окна. Правило же должно быть
    /// одно: ушёл от накладки — ушёл от выреза. Прямоугольник накладки всегда
    /// накрывает саму чёлку, так что выйти из него, оставшись на вырезе,
    /// нельзя.
    private func collapseAfterOverlay() {
        state.isPinnedOpen = false
        if state.isHovered { setHovered(false) }
    }

    /// Свернуть раскрытую панель обратно в мини-вид, не уводя курсор.
    private func collapsePanel() {
        guard state.isPinnedOpen else { return }
        state.isPinnedOpen = false
        Haptics.tap(.levelChange)
        host.updateInteractiveRect()
    }

    /// Свайп довели до порога: переключаем трек и показываем это в вырезе.
    private func performSwipe(_ direction: SwipeDirection) {
        DebugLog.write("свайп: \(direction == .next ? "следующий" : "предыдущий") трек")
        Haptics.tap(.levelChange)
        music.send(direction == .next ? .nextTrack : .previousTrack)

        state.swipe = direction
        swipeResetTimer?.invalidate()
        // Пауза подобрана под задержку MediaRemote: клиент перечитывает трек
        // через 0.3 с после команды, так что к моменту возврата в мини-вид
        // название уже новое, а не то, с которого свайпнули.
        let timer = Timer(timeInterval: 0.55, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.state.swipe = nil
            // Заново отсчитываем бегущую строку — у нового трека своё название.
            self.state.hoverStartedAt = Date()
        }
        RunLoop.main.add(timer, forMode: .common)
        swipeResetTimer = timer
    }

    // MARK: - Ответ модели

    /// Показывает панель с ответом. Приложение, из которого позвали команду,
    /// запоминается заранее: именно туда потом уйдёт «вставить».
    func openAssistant(title: String, prompt: String, model: String? = nil) {
        // Приложение запоминается только если панель ещё закрыта: при запуске
        // команды из открытой панели передним стоит сам вырез, и запомнить
        // его значило бы потерять адрес, куда потом вставлять ответ.
        let target = state.overlay == .assistant
            ? assistant.target
            : NSWorkspace.shared.frontmostApplication
        armAgent()
        assistant.start(title: title, prompt: prompt, model: model, target: target)
        router.set(.assistant)
    }

    /// Отладочный вход: панель с образцом захваченного текста.
    ///
    /// Настоящее выделение из сессии не создать — чужому окну его негде
    /// взять, — а вёрстку плашки и списка команд надо на чём-то снимать.
    /// Образец нарочно длинный: короткий уместился бы в строку и не показал
    /// бы ни второй строки, ни обрезки.
    func debugCapture(expanded: Bool = false) {
        let sample = t("Захваченный текст показывается здесь целиком, насколько помещается в две строки, а дальше обрезается — по нему надо узнать кусок, а не перечитать его. Раскрытая плашка показывает его весь, до своего потолка, а дальше прокручивается: захват срабатывает на всё выделенное, и понять по обрезанной фразе, то ли взялось, нельзя.")
        draft.setMode(.model)
        assistant.ask(captured: sample, target: NSWorkspace.shared.frontmostApplication)
        assistant.isCaptureExpanded = expanded
        router.set(.assistant)
        takeKeyboard()
    }

    /// Панель с захваченным текстом и сразу запущенной командой из списка.
    ///
    /// Тем же путём, каким её запускает нажатие по строке
    /// (`runCommandFromPanel`), а не горячей клавишей: у клавиши свой путь,
    /// с чтением выделения из чужого окна, и беда с задвоенным абзацем
    /// в ленте живёт не там.
    func debugCaptureRun() {
        debugCapture()
        guard let command = settings.quickCommands.first(where: { $0.kind == .ollama }) else {
            DebugLog.write("команды: запроса к модели в списке нет")
            return
        }
        // С задержкой: подряд панель к этому мигу ещё не построена — та же
        // ловушка, что у подсветки.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.runCommandFromPanel(command)
        }
    }

    /// То же, но с подсветкой, уведённой вниз на несколько шагов.
    ///
    /// Стрелки из сессии не послать — синтетические нажатия до Carbon
    /// не доходят, — а проверять надо именно то, что список едет
    /// за подсветкой. Ходим тем же путём, что и ↓: иначе проверялся бы не он.
    ///
    /// Шаги идут по одному и с задержкой, а не подряд в том же такте.
    /// Подряд они бессмысленны: панель к этому мигу ещё не построена,
    /// SwiftUI собирает её уже с готовой подсветкой — и `onChange`,
    /// на котором держится прокрутка, не срабатывает ни разу. Нажатия
    /// живьём приходят по одному в уже открытую панель, и проверять
    /// надо именно это.
    func debugCaptureHighlight(steps: Int) {
        debugCapture()
        debugStepHighlight(left: max(1, steps))
    }

    private func debugStepHighlight(left: Int) {
        guard left > 0 else {
            DebugLog.write(
                "отладка: подсветка на \(assistant.highlightedCommandID.map(String.init) ?? "нет")"
                    + ", команд \(visibleCommands.count)"
            )
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            _ = self.moveHighlight(1)
            self.debugStepHighlight(left: left - 1)
        }
    }

    /// ⌃⌥C: захватить выделенное и открыть разговор.
    ///
    /// Единственный вход в общение с моделью. Выделение читается тем же
    /// путём, что и для заметки: сперва напрямую через дерево доступности,
    /// а кто не отдаёт — имитацией ⌘C с возвратом прежнего буфера. Ответ
    /// приходит замыканием, потому что второй путь занимает до полусекунды.
    ///
    /// Приложение запоминается **до** чтения: имитация ⌘C сама по себе фокус
    /// не отбирает, но панель следом отберёт, а «вставить ответ» должно уйти
    /// туда, откуда текст взят.
    func captureAndAsk() {
        // Команды без модели — тоже повод открыть панель. Раньше проверялись
        // только модель и заметки, и с выключенной Ollama сочетание уводило
        // захваченное прямиком в заметки: список команд, половина которых
        // модели не требует, до человека не доходил вовсе.
        let hasCommands = !visibleCommands.isEmpty
        guard settings.ollamaEnabled || settings.notesEnabled || hasCommands else { return }
        let target = NSWorkspace.shared.frontmostApplication

        SelectionReader.read { [weak self] text in
            guard let self else { return }
            let captured = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            DebugLog.write("захват: \(captured.isEmpty ? "выделения нет" : "\(captured.count) симв.")")

            // Без модели разговаривать не с кем. Но уводить в заметку можно
            // только когда и делать больше нечего: с непустым списком команд
            // панель остаётся тем, чем её и звали, — местом, где выбирают,
            // что сделать с захваченным.
            if !self.settings.ollamaEnabled, self.visibleCommands.isEmpty {
                self.draft.setMode(.note)
            }
            self.armAgent()
            self.assistant.ask(captured: captured, target: target)
            self.router.set(.assistant)
            self.takeKeyboard()
        }
    }

    // MARK: - Диктовка

    /// Надиктовать заметку: панель открывается заметкой, речь ложится в поле.
    ///
    /// Не аудиозаметка: та пишет звук и потом расшифровывает его целиком,
    /// а здесь текст появляется по мере речи и правится руками тут же.
    /// Разные дела, и путать их нельзя — у записи разговора остаётся своё
    /// сочетание и своя кнопка.
    func dictateNote() {
        guard settings.voiceEnabled, settings.notesEnabled else { return }
        guard VoiceAccess.isReady else {
            requestVoiceAccess()
            return
        }
        if state.overlay != .assistant {
            draft.setMode(.note)
            router.set(.assistant)
            takeKeyboard()
        } else {
            draft.setMode(.note)
        }
        startDictation(into: .note)
    }

    /// Куда кладётся надиктованное.
    enum DictationTarget {
        /// В поле вопроса: надиктовать команду вместо набора.
        case question
        /// В заметку.
        case note
    }

    private func startDictation(into target: DictationTarget) {
        guard settings.voiceEnabled else { return }
        guard VoiceAccess.isReady else {
            requestVoiceAccess()
            return
        }
        // Договорить уже начатое — то же нажатие, что и начать.
        guard !dictation.isListening else {
            dictation.toggle()
            return
        }
        // Голос и диктовка слушают один микрофон: начатый заход обрывается,
        // иначе распознавание получало бы одну речь на двоих.
        voice.stop()

        // Набранное до диктовки не теряется: речь дописывается к нему.
        // Подменять набранное было бы молчаливой потерей — человек мог
        // начать печатать и перейти на голос на полуслове.
        let prefix: String
        switch target {
        case .question:
            prefix = draft.question.isEmpty ? "" : draft.question + " "
        case .note:
            prefix = ""
        }

        dictation.onText = { [weak self] text in
            guard let self else { return }
            switch target {
            case .question:
                self.draft.question = prefix + text
            case .note:
                self.draft.setDictated(text)
            }
            self.host.updateInteractiveRect()
        }
        dictation.onFinish = { [weak self] _ in
            guard let self else { return }
            if target == .note { self.draft.endDictation() }
            Haptics.tap(.generic)
        }
        dictation.onFailure = { [weak self] reason in
            self?.activities.present(.command(text: reason, state: .failed))
        }
        dictation.start()
        Haptics.tap(.levelChange)
    }

    /// Кнопка микрофона в поле вопроса.
    func toggleQuestionDictation() { startDictation(into: .question) }

    // MARK: - Помощник, который делает

    /// Подвесить помощника к разговору.
    ///
    /// Зовётся на каждое открытие панели, а не один раз при запуске:
    /// набор инструментов считается из настроек, а их правят на ходу —
    /// выключенный календарь обязан унести свой инструмент сразу, а не
    /// после перезапуска.
    ///
    /// Голос инструментов не получает вовсе. Спрошенное голосом панель
    /// не открывает, и карточка подтверждения всплыла бы там, где её
    /// некому увидеть и нечем нажать.
    ///
    /// Здесь же снимается ручной поиск по заметкам. Пока инструмент жив,
    /// переключателя в панели нет, и оставленное с прошлого раза «да»
    /// работало бы вслепую: заметки уходили бы модели простынёй, а нажать
    /// на это нечем.
    private func armAgent(spoken: Bool = false) {
        assistant.availableTools = { [weak self] in
            guard let self, !spoken else { return [] }
            // Модель, про которую известно, что инструменты она не умеет,
            // их и не получает: Ollama отвечает на такой запрос отказом,
            // и команда падает целиком — «Перевести» не переводит ничего
            // из-за помощника, которого о переводе не просили.
            //
            // Ответа три, и два были бы враньём: `/api/show` есть только
            // у Ollama, у облачного провайдера спросить нечего вовсе.
            // Умалчиваем только про заведомо неумеющую.
            guard self.modelHandlesTools else { return [] }
            // Выбранная через «/» группа сужает список до себя: человек
            // уже сказал, куда идти, и думать за него модели незачем.
            return self.agent.tools(only: self.assistant.toolFilter)
        }
        if AgentTool.searchNotes.isEnabled(settings) { assistant.usesNotes = false }
        assistant.runTool = { [weak self] call, done in
            self?.handleToolCall(call, done: done)
        }
    }

    /// Достанутся ли инструменты той модели, которая будет отвечать.
    ///
    /// Спрашивается в момент запроса, а не при снаряжении помощника: модель
    /// разговора назначается первым вопросом, и на снаряжении её ещё нет.
    ///
    /// Модель по умолчанию берётся из `defaultModel`, а не из `ollamaModel`:
    /// второй — ключ тех времён, когда провайдер был один, и с разъездом
    /// провайдеров он остался лежать со старым значением. Проверка читала
    /// именно его и отвечала про модель, к которой запрос давно не уходит:
    /// у пользователя там висела `gemma3:4b`, а разговор шёл с `qwen3:8b` —
    /// инструменты не уходили вовсе, и список «/» не показывался.
    private var modelHandlesTools: Bool {
        let stored = assistant.model ?? settings.defaultModel.stored
        guard let ref = ModelRef.parse(stored, fallback: settings.aiProvider) else { return true }
        return ModelList.shared.toolSupport(of: ref) != .no
    }

    /// Модель просит что-то сделать.
    private func handleToolCall(_ call: ToolCall, done: @escaping (AgentToolResult) -> Void) {
        switch agent.prepare(call) {
        case let .refuse(result):
            DebugLog.write("помощник: отказ — \(result.label)")
            done(result)

        case let .run(tool, call):
            agent.run(tool, call, completion: done)

        case let .confirm(action):
            // Ответ модели откладывается до нажатия: круг ждёт человека
            // ровно столько, сколько тот думает. Оборвать это можно только
            // закрытием панели.
            pendingAnswer = done
            // Спрошенное голосом панели не раскрывает — а карточку надо
            // где-то показать и чем-то нажать. Раскрываем её сами: это
            // единственный случай, когда голос выходит на экран, и он же
            // единственный, где он что-то меняет в чужих данных.
            if state.overlay != .assistant {
                draft.setMode(.model)
                router.set(.assistant)
                takeKeyboard()
                DebugLog.write("помощник: панель раскрыта под карточку")
            }
            assistant.propose(action)
            // Панель подросла на карточку — окно обязано узнать, иначе
            // нажатия будут приниматься по прежней высоте.
            host.updateInteractiveRect()
        }
    }

    /// Человек нажал «Создать».
    func confirmPendingAction() {
        guard let action = assistant.pending, let done = pendingAnswer else { return }
        pendingAnswer = nil
        assistant.clearPending()
        let result = agent.commit(action)
        DebugLog.write("помощник: \(result.label)")
        host.updateInteractiveRect()
        done(result)
    }

    /// Человек нажал «Отмена».
    ///
    /// Разговор при этом **продолжается**: модель узнаёт об отказе ответом
    /// инструмента и договаривает словами. Оборвать всё можно закрытием
    /// панели — и тогда не выполняется ничего.
    func declinePendingAction() {
        guard let action = assistant.pending, let done = pendingAnswer else { return }
        pendingAnswer = nil
        assistant.clearPending()
        DebugLog.write("помощник: отменено человеком — \(action.tool.name)")
        host.updateInteractiveRect()
        done(agent.declined(action))
    }

    /// Отладочный вопрос голосом, минуя микрофон.
    ///
    /// Через контроллер, а не прямо в сессию: инструменты подвешивает он,
    /// и заход без них проверял бы не то, что идёт живьём.
    func debugAskByVoice(_ text: String) {
        armAgent()
        voice.debugAsk(text)
    }

    // MARK: - Модели: отладка

    /// Каталог предложений с числами этой машины — в журнал.
    ///
    /// Совет по ресурсам проверяется тестом на выдуманных числах, и это
    /// правильно. Но настоящая память и настоящее свободное место есть
    /// только здесь, а промах в единицах — гигабайты против байтов —
    /// на выдуманных числах не виден вовсе: тест сойдётся сам с собой.
    func debugModelOffers() {
        // Список установленного надо спросить, и он приходит по сети:
        // в свежем процессе он пуст, и без ожидания все строки выглядят
        // как «не скачано» — первая же проверка так и соврала.
        guard ModelList.shared.models.isEmpty else {
            printModelOffers()
            return
        }
        ModelList.shared.refreshIfNeeded()
        DebugLog.write("модели: список пуст, спрашиваю сервер")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.printModelOffers()
        }
    }

    private func printModelOffers() {
        let machine = MachineResources.current()
        let памяти = ByteCountFormatter.string(fromByteCount: machine.ram, countStyle: .file)
        let диска = ByteCountFormatter.string(fromByteCount: machine.freeDisk, countStyle: .file)
        DebugLog.write("модели: у машины памяти \(памяти), свободно \(диска)")
        DebugLog.write("модели: советуем \(ModelCatalogue.recommended(on: machine).tag)")

        let rows = ModelCatalogue.rows(
            on: machine,
            installed: ModelList.shared.models(of: .ollama),
            selected: settings.apiModel(for: .ollama),
            installing: ModelInstaller.shared.installing,
            share: 0,
            queued: []
        )
        for row in rows {
            let verdict: String
            switch ModelCatalogue.fit(row.offer, on: machine) {
            case .fits: verdict = "по силам"
            case .needsRAM: verdict = "не хватает памяти"
            case .needsDisk: verdict = "не хватает места"
            }
            DebugLog.write(
                "модели: \(row.offer.tag) — \(row.offer.title), \(row.offer.sizeText), "
                    + "\(verdict), пометка \(row.badge), кнопка \(row.action)"
            )
        }
    }

    /// Что движок думает о себе — в журнал.
    ///
    /// Главное, что здесь проверяется: уже работающая Ollama должна
    /// подхватываться, а не переставляться. На машине, где она стоит
    /// и работает, в журнале обязано быть «порт ответил», и ни слова
    /// про установку.
    func debugEngine() {
        let engine = OllamaEngine.shared
        let address = settings.apiURL(for: .ollama)
        DebugLog.write("движок: адрес \(address), местный — \(OllamaApp.isLocalAddress(address))")
        switch OllamaApp.installed() {
        case let .app(bundle): DebugLog.write("движок: найден бандл \(bundle.path)")
        case let .brew(cli): DebugLog.write("движок: найдена утилита \(cli.path), это Homebrew")
        case .foreign: DebugLog.write("движок: что-то есть, но не опознано")
        case nil: DebugLog.write("движок: на диске не найдено ничего")
        }

        engine.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let line = engine.line
            DebugLog.write("движок: состояние \(engine.state)")
            DebugLog.write("движок: строка «\(line.text)», кнопка \(line.action)")
        }
    }

    /// Поднять движок и дождаться порта.
    func debugEngineStart() {
        let engine = OllamaEngine.shared
        engine.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            DebugLog.write("движок: запускаю из состояния \(engine.state)")
            engine.start()
            self?.reportEngineState(times: 20)
        }
    }

    /// Попросить приложение Ollama выйти.
    ///
    /// Просим, а не убиваем: `pkill` по чужому приложению — то же
    /// самоуправство, от которого держится в стороне установщик обновлений.
    ///
    /// **Случай «стоит, но молчит» этим не получить, и это находка.**
    /// Сервер `ollama serve` — отдельный процесс, поднятый её агентом
    /// `com.ollama.ollama`, и выход приложения из строки меню его не гасит:
    /// порт продолжает отвечать. Значит состояние `running` после такого
    /// выхода — верное, а не промах опознания: порт старше бандла.
    /// Настоящее «молчит» бывает после перезагрузки без автозапуска
    /// и после «Quit» в её собственном меню, где она гасит и сервер.
    func debugEngineQuit() {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: OllamaApp.bundleID)
        guard !running.isEmpty else {
            DebugLog.write("движок: приложение Ollama не запущено — просить выйти некого")
            return
        }
        for app in running { app.terminate() }
        DebugLog.write("движок: попросил приложение Ollama выйти — \(running.count) шт.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            OllamaEngine.shared.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let state = OllamaEngine.shared.state
                DebugLog.write("движок: после выхода приложения состояние \(state)")
                if state.isRunning {
                    DebugLog.write("движок: порт жив — сервер работает отдельно от приложения")
                }
            }
        }
    }

    /// Сверяет подпись у уже лежащего образа, ничего не устанавливая.
    ///
    /// Обязано идти **в процессе приложения**: скрипт под `swift` подписан
    /// Apple, и Security отвечает ему иначе — на этом уже обжигались
    /// с голосами. Сам по себе отказ здесь — самая вероятная поломка
    /// всей работы: у Ollama сменится владелец подписи, и установка встанет.
    func debugEngineVerify() {
        let image = OllamaDownload.imageFile
        guard FileManager.default.fileExists(atPath: image.path) else {
            DebugLog.write("движок: образа нет — \(image.path)")
            return
        }
        DebugLog.write("движок: требование — \(OllamaApp.requirement)")
        guard let volume = DiskImage.attach(image) else {
            DebugLog.write("движок: образ не смонтировался")
            return
        }
        defer { DiskImage.detach(volume) }

        guard let app = DiskImage.application(in: volume.mountPoint) else {
            DebugLog.write("движок: на образе не одно приложение")
            return
        }
        switch CodeSignatureCheck.matches(app, requirement: OllamaApp.requirement) {
        case .valid:
            DebugLog.write("движок: подпись сошлась — \(app.lastPathComponent)")
        case let .rejected(reason):
            DebugLog.write("движок: подпись отклонена — \(OllamaDownload.failure(for: reason))")
        }
    }

    /// Весь путь установки живьём: скачать, сверить, положить, запустить.
    ///
    /// Трогает «Программы», поэтому зовётся только руками и только
    /// осознанно — как `updateInstall`.
    func debugEngineInstall() {
        DebugLog.write("движок: ставлю Ollama с нуля")
        OllamaEngine.shared.install()
        reportEngineState(times: 90)
    }

    private func reportEngineState(times: Int) {
        guard times > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            let engine = OllamaEngine.shared
            DebugLog.write("движок: состояние \(engine.state)")
            guard engine.state.isBusy else { return }
            self.reportEngineState(times: times - 1)
        }
    }

    /// Качает одну векторную модель — самую дешёвую в каталоге.
    ///
    /// Полосу иначе не проверить: нажать «Скачать» из сессии нечем,
    /// а счёт доли по слоям виден только на живом ответе Ollama.
    func debugPullEmbed() {
        let offer = ModelCatalogue.embed
        DebugLog.write("модели: пробная загрузка \(offer.tag), \(offer.sizeText)")
        ModelInstaller.shared.enqueue([offer.tag])
        reportInstallerState(every: 2, times: 30)
    }

    /// Ставит рекомендованную пару — проверка очереди.
    ///
    /// На машине, где разговорная модель уже есть, очередь обязана её
    /// пропустить: повторная загрузка пяти гигабайт ни за чем — ровно то,
    /// от чего очередь и сделана.
    func debugPullPair() {
        let machine = MachineResources.current()
        let pair = ModelCatalogue.recommendedPair(on: machine)
        DebugLog.write("модели: пара к установке — \(pair.joined(separator: ", "))")
        ModelInstaller.shared.enqueue(pair)
        DebugLog.write("модели: в очереди — \(ModelInstaller.shared.waiting.joined(separator: ", "))")
        reportInstallerState(every: 2, times: 30)
    }

    /// Пишет состояние загрузки в журнал, пока она идёт.
    ///
    /// Загрузка живёт минутами и отчитывается замыканиями в вёрстку;
    /// из сессии вёрстки нет, и единственный способ увидеть ход — журнал.
    private func reportInstallerState(every seconds: Int, times: Int) {
        guard times > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) { [weak self] in
            guard let self else { return }
            let installer = ModelInstaller.shared
            DebugLog.write(
                "модели: состояние \(installer.state), качается \(installer.installing ?? "—"),"
                    + " в очереди \(installer.waiting.count)"
            )
            guard installer.isBusy || !installer.waiting.isEmpty else { return }
            self.reportInstallerState(every: seconds, times: times - 1)
        }
    }

    // MARK: - Помощник: отладка

    /// Что уходит модели прямо сейчас — в журнал.
    ///
    /// Единственный способ увидеть провод, не поднимая сервера и не гадая
    /// по ответу: описания собираются из настроек, а настройки правят
    /// на ходу.
    func debugAgentTools() {
        let tools = AgentTool.allCases
        for tool in tools {
            let state = tool.blockedReason(settings) ?? "доступен"
            DebugLog.write("помощник: \(tool.name) — \(state)")
        }
        let wire = agent.tools()
        let json = (try? JSONSerialization.data(withJSONObject: wire, options: [.prettyPrinted, .sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "—"
        DebugLog.write("помощник: инструментов \(wire.count)\n\(json)")

        let model = settings.defaultModel
        let support: String
        switch ModelList.shared.toolSupport(of: model) {
        case .yes: support = "умеет"
        case .no: support = "НЕ умеет"
        case .unknown: support = "неизвестно (сервер не сообщает)"
        }
        DebugLog.write("помощник: модель \(model.stored) — инструменты \(support)")
        DebugLog.write("помощник: указание — \(AgentTool.instruction())")
    }

    /// Разбор образцов времени — на живой машине, с её поясом.
    ///
    /// Тесты идут с закреплённым поясом нарочно, и правильно; но промах
    /// на три часа случается именно от настоящего пояса, и увидеть это
    /// можно только здесь.
    func debugAgentTime() {
        let now = Date()
        DebugLog.write("помощник: сейчас — \(AgentTime.stamp(now: now))")
        for sample in [
            "2026-09-12 15:00", "2026-09-12T15:00", "2026-09-12T15:00Z",
            "2026-09-12", "15:00", "2024-09-12 15:00", "завтра в три",
        ] {
            guard let parsed = AgentTime.parse(sample, now: now) else {
                DebugLog.write("помощник: «\(sample)» — не разобрано")
                continue
            }
            let rolled = AgentTime.rollingForward(parsed, now: now)
            DebugLog.write(
                "помощник: «\(sample)» — "
                    + AgentTime.humanize(rolled.date, isDateOnly: rolled.isDateOnly)
                    + (rolled.yearRepaired ? " (год поправлен)" : "")
            )
        }
    }

    /// Лента со строками шагов, мимо модели.
    ///
    /// Снимок вёрстки не должен зависеть от того, что сегодня ответит
    /// модель: шаги приходят от неё, а рисовать их надо одинаково.
    /// Ответ на месте, подсветка уведена вниз по действиям.
    ///
    /// Проверяет ровно то, что сменилось: под полем теперь не список команд,
    /// а действия, и вести по ним должна та же пара клавиш. Нажатия
    /// из сессии не доходят, а шаги идут по одному и с задержкой — подряд
    /// они бессмысленны, панель к этому мигу ещё не построена.
    func debugAnswerHighlight(steps: Int) {
        debugAgentSteps()
        debugStepHighlight(left: max(1, steps))
    }

    /// Уточняющий вопрос поверх готового ответа.
    ///
    /// Воспроизводит беду целиком: ответ дописан, подсветка сама стоит
    /// на «Скопировать», человек печатает продолжение и отправляет. Панель
    /// при этом обязана **остаться открытой**, а вопрос — уйти модели;
    /// прежде Enter копировал прежний ответ, а `copyAnswer` закрывает панель.
    func debugFollowUp() {
        debugAgentSteps()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.draft.question = "а во сколько вторая?"
            self.sendDraft()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                DebugLog.write(
                    "отладка: после отправки панель "
                        + (self.state.overlay == .assistant ? "открыта" : "ЗАКРЫЛАСЬ")
                )
            }
        }
    }

    func debugAgentSteps() {
        armAgent()
        draft.setMode(.model)
        assistant.debugSteps([
            ("Посмотрел календарь на 12 сентября", AgentTool.dayAgenda.symbol),
            ("Таймер на 10 мин", AgentTool.startTimer.symbol),
        ], answer: "Таймер пошёл. Завтра у вас две встречи: планёрка в 10:00 и созвон в 15:00.")
        router.set(.assistant)
        takeKeyboard()
    }

    /// Карточка подтверждения на выдуманном предложении.
    ///
    /// Ждать живого ответа модели ради снимка нельзя, а форм у карточки
    /// три — у встречи, напоминания и заметки разные вторые строки
    /// и разные подписи кнопок.
    func debugAgentCard(kind: AgentTool) {
        armAgent()
        draft.setMode(.model)
        let call: ToolCall
        switch kind {
        case .createNote:
            call = ToolCall(
                id: "debug",
                name: kind.name,
                arguments: #"{"text":"Позвонить в сервис и спросить про сроки","title":"Сервис"}"#
            )
        default:
            let day = AgentTime.stamp(now: Date())
            DebugLog.write("помощник: карточка на образце, сегодня \(day)")
            call = ToolCall(
                id: "debug",
                name: AgentTool.createEvent.name,
                arguments: #"{"title":"Созвон с командой","start":"\#(Self.debugStart())","duration_minutes":60}"#
            )
        }
        guard case let .confirm(action) = agent.prepare(call) else {
            DebugLog.write("помощник: образец не собрался в карточку")
            return
        }
        pendingAnswer = { result in DebugLog.write("помощник: образец — \(result.label)") }
        assistant.debugSteps([], answer: "Готов завести — подтвердите.")
        assistant.propose(action)
        router.set(.assistant)
        takeKeyboard()
    }

    /// Завтрашние три часа дня — строкой того вида, который просят у модели.
    private static func debugStart() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return formatter.string(from: tomorrow) + " 15:00"
    }

    /// Весь круг на живой модели: запрос с инструментами, вызов, ответ.
    ///
    /// Вопрос кладётся **с задержкой** после открытия панели, а не в том же
    /// такте. Подряд он бессмыслен: панель к этому мигу ещё не построена,
    /// и проверялся бы не тот путь, которым вопрос приходит от человека.
    /// Отладочный вход: список инструментов под полем.
    ///
    /// Нажать «/» из сессии нечем — синтетические клавиши до приложения
    /// не доходят, — а снять вёрстку списка надо.
    func debugSlashList() {
        askAssistant()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.draft.question = "/"
        }
    }

    /// Весь круг живьём: выбранная группа и вопрос из задачи.
    func debugSlashAsk(_ question: String) {
        askAssistant()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.draft.question = question
            DebugLog.write("инструмент: отладочный вопрос — \(question)")
            self.sendDraft()
        }
    }

    /// Ответ, оборванный на полуслове: кнопку «Остановить» из сессии
    /// не нажать.
    func debugStopAfter(_ seconds: TimeInterval, question: String) {
        debugAgentAsk(question)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.stopAnswer()
        }
    }

    func debugAgentAsk(_ question: String) {
        askAssistant()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.draft.question = question
            DebugLog.write("помощник: отладочный вопрос — \(question)")
            self.sendDraft()
        }
    }

    /// Кнопка на главной панели. Открывает панель модели и заметок:
    /// пустое поле и курсор в нём.
    ///
    /// Работает и с выключенной Ollama — тогда это просто поле для заметки.
    /// Панель прячет у себя всё, что без модели не имеет смысла.
    func askAssistant() {
        guard settings.ollamaEnabled || settings.notesEnabled else { return }
        // Без модели разговаривать не с кем — панель открывается сразу
        // заметкой, иначе человек упёрся бы в пустую область ответа.
        if !settings.ollamaEnabled { draft.setMode(.note) }
        armAgent()
        assistant.ask(target: NSWorkspace.shared.frontmostApplication)
        router.set(.assistant)
        takeKeyboard()
    }

    // MARK: - Указания через «@»

    /// На сколько дней вперёд «@» показывает встречи.
    ///
    /// Две недели: дальше человек переносит и отменяет редко, а список,
    /// в котором сотня строк, ищет хуже, чем календарь.
    private static let mentionHorizon = 14

    /// Сколько заметок попадает в список. Свежие сверху — по ним и ищут.
    private static let mentionNotes = 60

    /// Сколько знаков заметки уходит модели. Дальше это уже не «покажи
    /// на заметку», а выгрузка архива в один вопрос.
    private static let mentionNoteLimit = 1200

    /// Всё, на что можно показать. Собирается один раз на открытие списка:
    /// чтение календаря — поход в EventKit, и делать его на каждую букву
    /// значило бы платить за него всё время, пока набирают имя.
    private var mentionPool: [Mention] = []

    /// Запрос, который человек закрыл клавишей Esc. Пока набранное
    /// не изменилось, список не всплывает снова.
    private var dismissedMention: String?

    /// Группы инструментов, доступные прямо сейчас. Собираются на открытие
    /// списка, а не на каждую букву: настройки между двумя нажатиями
    /// не меняются, а обход всех инструментов стоит заметно дороже разбора
    /// строки.
    private var slashPool: [SlashTool] = []

    /// Запрос, закрытый клавишей Esc, — как и у «@».
    private var dismissedSlash: String?

    /// Набранное изменилось: открыть, обновить или закрыть список
    /// инструментов.
    ///
    /// Отдельно от «@», хотя правила и похожи: «/» ловится только в начале
    /// вопроса, а список собирается из настроек, а не из календаря и заметок.
    private func refreshSlash(for text: String) {
        guard state.overlay == .assistant, draft.mode == .model,
              settings.ollamaEnabled, settings.agentEnabled
        else {
            assistant.hideSlash()
            return
        }
        guard let query = SlashQuery.query(in: text) else {
            dismissedSlash = nil
            slashPool = []
            assistant.hideSlash()
            return
        }
        guard dismissedSlash != query else { return }
        dismissedSlash = nil
        if slashPool.isEmpty { slashPool = SlashCatalogue.all(for: settings) }
        // Инструментов у модели нет вовсе — предлагать выбор нечего:
        // выбранная группа ничего не изменила бы. Причина пишется
        // в журнал: молча пропавший список — это «/ не работает»,
        // и разбираться в нём иначе не с чем.
        guard !slashPool.isEmpty, modelHandlesTools else {
            DebugLog.write("инструменты: список «/» не показан — "
                + (slashPool.isEmpty ? "нет доступных групп" : "модель не умеет инструменты"))
            assistant.hideSlash()
            return
        }
        assistant.showSlash(SlashQuery.matches(
            slashPool,
            query: query,
            limit: PickerRows<SlashTool>.visibleRows * 4
        ))
    }

    /// Выбрали группу — она встаёт в начало вопроса словом.
    ///
    /// Словом, а не невидимой пометкой: человек должен видеть, куда уйдёт
    /// вопрос, и уметь это стереть. Стёр — и выбора не было, разбор идёт
    /// по самому тексту.
    func pickSlash(_ tool: SlashTool) {
        draft.question = SlashQuery.insert(tool, into: draft.question)
        assistant.hideSlash()
        dismissedSlash = nil
        takeKeyboard()
        DebugLog.write("инструмент: выбран «\(tool.title)» — \(tool.tools.map(\.name).joined(separator: ", "))")
    }

    /// Набранное изменилось: открыть, обновить или закрыть список.
    private func refreshMentions(for text: String) {
        guard state.overlay == .assistant, draft.mode == .model, settings.ollamaEnabled else {
            assistant.hideMentions()
            return
        }
        guard let query = MentionQuery.query(in: text) else {
            dismissedMention = nil
            mentionPool = []
            assistant.hideMentions()
            return
        }
        guard dismissedMention != query else { return }
        dismissedMention = nil
        if mentionPool.isEmpty { mentionPool = buildMentionPool() }
        assistant.showMentions(MentionQuery.matches(
            mentionPool,
            query: query,
            limit: PickerRows<Mention>.visibleRows * 4
        ))
    }

    /// Встречи ближайших дней и свежие заметки — одним списком.
    ///
    /// Встречи первыми: «@» завели ради них, а заметку чаще открывают
    /// списком, чем зовут в вопрос. Выключенная в настройках функция своих
    /// записей не даёт — иначе человек показал бы на встречу, которой
    /// приложению нечем распорядиться.
    private func buildMentionPool() -> [Mention] {
        var pool: [Mention] = []
        let day = Calendar.current

        if settings.calendarEnabled {
            let now = Date()
            let until = day.date(byAdding: .day, value: Self.mentionHorizon, to: now) ?? now
            // Час назад, а не «сейчас»: идущую встречу тоже переносят
            // и отменяют, и чаще всего именно её.
            let events = calendar.events(from: now.addingTimeInterval(-3600), to: until)
            for (index, item) in events.enumerated() where !item.title.isEmpty {
                pool.append(Mention(
                    kind: .event,
                    handle: "e\(index + 1)",
                    target: item.id,
                    start: item.start,
                    title: item.title,
                    detail: AgentTime.humanize(item.start, isDateOnly: item.isAllDay, calendar: day)
                ))
            }
        }

        if settings.notesEnabled {
            for (index, note) in notes.notes.prefix(Self.mentionNotes).enumerated()
            where !note.title.isEmpty {
                pool.append(Mention(
                    kind: .note,
                    handle: "n\(index + 1)",
                    target: String(note.id),
                    start: nil,
                    title: note.title,
                    detail: AgentTime.humanize(note.updatedAt, isDateOnly: true, calendar: day)
                ))
            }
        }

        DebugLog.write("упоминания: собрано \(pool.count)")
        return pool
    }

    /// Выбрали запись — она встаёт в текст вопроса словом.
    ///
    /// Именно словом, а не невидимой пометкой: человек должен видеть
    /// в своём вопросе то, что уйдёт модели, и уметь это стереть.
    func pickMention(_ mention: Mention) {
        draft.question = MentionQuery.insert(mention, into: draft.question)
        assistant.remember(mention)
        assistant.hideMentions()
        dismissedMention = nil
        takeKeyboard()
        DebugLog.write("упоминание: выбрано \(mention.handle) «\(mention.title)»")
    }

    /// Что модель узнает о позванных записях.
    ///
    /// Ярлыком вперёд: им же она потом назовёт встречу инструменту переноса
    /// или отмены. Настоящий идентификатор EventKit сюда не попадает вовсе —
    /// маленькая модель, переписывая тридцать знаков в аргумент, ошибается
    /// чаще, чем попадает.
    private func mentionContext(for mentions: [Mention]) -> String? {
        guard !mentions.isEmpty else { return nil }
        var lines = [t("Человек показал в вопросе на эти записи. Работай с ними, заново их не ищи:")]
        for mention in mentions {
            switch mention.kind {
            case .event: lines.append(eventLine(mention))
            case .note: lines.append(noteLine(mention))
            }
        }
        if mentions.contains(where: { $0.kind == .event }) {
            lines.append(t("Перенести или отменить встречу можно инструментом, назвав её ярлыком — например «e1»."))
        }
        return lines.joined(separator: "\n")
    }

    private func eventLine(_ mention: Mention) -> String {
        var line = tf("Встреча %@ «%@» — %@", mention.handle, mention.title, mention.detail)
        if let start = mention.start,
           let draft = calendar.draft(eventID: mention.target, start: start) {
            if !draft.isAllDay { line += ", " + draft.durationLabel }
            if !draft.location.isEmpty { line += ", " + tf("место: %@", draft.location) }
        }
        return line + "."
    }

    private func noteLine(_ mention: Mention) -> String {
        let head = tf("Заметка %@ «%@» от %@", mention.handle, mention.title, mention.detail)
        guard let id = Int64(mention.target), let note = notes.note(id: id) else {
            return head + "."
        }
        let body = note.plain.prefix(Self.mentionNoteLimit)
        guard !body.isEmpty else { return head + "." }
        return head + ":\n" + body
    }

    // MARK: - Список команд в панели

    /// Команды, которые видно в панели прямо сейчас.
    ///
    /// Тем же расчётом, каким их отбирает вёрстка: стрелка обязана вести
    /// подсветку ровно по видимым строкам, а два списка порознь разошлись бы
    /// на первой же выключенной команде.
    private var visibleCommands: [QuickCommand] {
        QuickCommands.visible(
            in: settings.quickCommands,
            enabled: settings.quickCommandsEnabled,
            modelEnabled: settings.ollamaEnabled
        )
    }

    /// ↑ и ↓ ведут подсветку. Возвращает, забрала ли панель нажатие себе.
    /// Само правило шага — в `HighlightMove`: оно общее с историей буфера.
    /// ↑ и ↓ ведут подсветку по тому, что стоит под полем прямо сейчас.
    ///
    /// Слот там один на двоих: пока ответа нет — список команд, появился
    /// ответ — действия с ним. Клавиша обязана вести по тому, что человек
    /// видит, а не по тому, что лежало там до ответа: два списка под одной
    /// парой клавиш — это один список, который сменился.
    private func moveHighlight(_ offset: Int) -> Bool {
        // Пока выбирают модель, стрелки принадлежат этому выбору, а не списку
        // команд: увести подсветку из-под открытого выбора значило бы менять
        // модель не у той команды.
        guard assistant.choosingModelFor == nil else { return false }

        // Список «@» стоит в том же слоте и открыт ровно тогда, когда его
        // набрали: стрелки принадлежат ему, пока он на экране.
        if assistant.isPickingSlash {
            guard !assistant.slashMatches.isEmpty else { return false }
            let last = assistant.slashMatches.count - 1
            let current = assistant.highlightedSlash ?? 0
            assistant.highlightedSlash = min(max(0, current + offset), last)
            return true
        }
        if assistant.isPickingMention {
            guard !assistant.mentionMatches.isEmpty else { return false }
            let last = assistant.mentionMatches.count - 1
            let current = assistant.highlightedMention ?? 0
            assistant.highlightedMention = min(max(0, current + offset), last)
            return true
        }

        if !assistant.answer.isEmpty {
            return moveAnswerAction(offset)
        }

        let list = visibleCommands
        guard !list.isEmpty else { return false }
        // Двух подсветок разом быть не должно, иначе непонятно, чей Enter.
        assistant.highlightedAnswerAction = nil

        assistant.highlightedCommandID = HighlightMove.next(
            from: assistant.highlightedCommandID, in: list.map(\.id), offset: offset
        )
        showHintForHighlight()
        return true
    }

    /// Какие действия с ответом доступны прямо сейчас.
    ///
    /// Состав зависит от настроек — «в заметки» есть только при включённых
    /// заметках, — и считать его надо здесь: панель рисует ту же тройку,
    /// но о настройках знает лишь то, что ей передали.
    private var answerActions: [AssistantSession.AnswerAction] {
        settings.notesEnabled ? [.copy, .paste, .note] : [.copy, .paste]
    }

    /// ← и → ведут подсветку по действиям с ответом.
    ///
    /// Только пока подсветка есть: в остальное время стрелки принадлежат
    /// тексту в поле, и забирать их значило бы сломать обычную правку
    /// набранного вопроса.
    private func moveAnswerAction(_ offset: Int) -> Bool {
        let list = answerActions
        guard !list.isEmpty else { return false }
        // Подсветки ещё нет — первое нажатие ставит её на край, с которого
        // пришли: сверху вниз на первое действие, снизу вверх на последнее.
        guard let current = assistant.highlightedAnswerAction,
              let index = list.firstIndex(of: current)
        else {
            assistant.highlightedAnswerAction = offset >= 0 ? list.first : list.last
            assistant.highlightedCommandID = nil
            showHintForHighlight()
            return true
        }
        // По краям упирается, а не заворачивается: список короткий, и уехать
        // с последнего действия на первое человек не просил.
        let next = min(max(0, index + offset), list.count - 1)
        assistant.highlightedAnswerAction = list[next]
        showHintForHighlight()
        return true
    }

    /// Подпись подсвеченного — той же плашкой под чёлкой, что и при наведении.
    ///
    /// Кнопки в панели — одни значки без слов, и подпись у них всегда была
    /// одна: плашка под чёлкой. Но показывало её только наведение, и человек,
    /// ведущий подсветку стрелками, водил её по трём одинаковым кружкам,
    /// не зная, какой из них что делает.
    private func showHintForHighlight() {
        if let action = assistant.highlightedAnswerAction {
            NotchHintTracker.shared.focus(
                action.title(pasteTo: PasteApps.shortName(of: assistant.pasteDestination))
            )
            return
        }
        if let id = assistant.highlightedCommandID,
           let command = visibleCommands.first(where: { $0.id == id }) {
            // Сочетание в подписи — список заодно ему и учит: подсмотреть
            // его больше негде, кроме настроек.
            let shortcut = command.hotKey.map { " · " + $0.display } ?? ""
            NotchHintTracker.shared.focus(command.title + shortcut)
            return
        }
        NotchHintTracker.shared.focus(nil)
    }

    /// Следующее приложение для вставки.
    ///
    /// Перебор идёт по кругу и по именам: список чужой и длинный, упереться
    /// в его конец значило бы заставить человека считать нажатия, а случайный
    /// порядок `runningApplications` менял бы направление перебора между
    /// нажатиями.
    private func cyclePasteTarget() -> Bool {
        let list = PasteApps.candidates()
        guard !list.isEmpty else { return true }
        let next = PasteApps.next(after: assistant.pasteDestination, in: list)
        assistant.pasteTarget = next
        DebugLog.write("вставка: цель — \(next?.localizedName ?? "?")")
        showHintForHighlight()
        return true
    }

    /// Выполнить подсвеченное действие с ответом.
    private func runAnswerAction(_ action: AssistantSession.AnswerAction) {
        switch action {
        case .copy: copyAnswer()
        case .paste: pasteAnswer()
        case .note: saveAnswer()
        }
    }

    /// Tab меняет модель подсвеченной команды на следующую установленную.
    ///
    /// По кругу и через «как в настройках»: у команды это отдельное
    /// состояние, а не одна из моделей, и пропустить его перебором значило бы
    /// лишить человека возможности вернуть команду к общей модели, не заходя
    /// в настройки.
    private func cycleModel() -> Bool {
        // Подсветка стоит на вставке — Tab меняет не модель, а приложение,
        // в которое эта вставка уйдёт. Клавиша в панели всюду значит одно:
        // «поменять то, на чём стоит подсветка».
        if assistant.highlightedAnswerAction == .paste { return cyclePasteTarget() }
        guard let id = assistant.highlightedCommandID,
              var command = settings.quickCommands.first(where: { $0.id == id })
        else {
            // Подсветки нет — Tab принадлежит самому вопросу. Свободный
            // вопрос до сих пор уходил только моделью из настроек, хотя
            // у любой команды модель можно сменить одной клавишей:
            // менять её ради одного вопроса значило идти в настройки
            // и возвращать обратно.
            return cycleQuestionModel()
        }

        // Дальше Tab не уходит ни при каком исходе. Он уходил — и попадал
        // в поле вопроса отступом: список моделей ни разу не спрашивали,
        // он был пуст, обработчик отвечал «не моё», и `NSTextView` честно
        // вставлял табуляцию. Выглядело это как «Tab не работает», а на деле
        // работало всё, кроме одного: списка ещё не существовало.
        //
        // Пока подсветка стоит на команде, Tab принадлежит ей. Команде
        // без модели менять нечего — но и отступ в вопросе ей не нужен тем
        // более.
        guard command.kind.usesModel else { return true }

        let models = ModelList.shared.models
        guard !models.isEmpty else {
            // Спрашиваем сейчас же: к следующему нажатию список будет.
            ModelList.shared.refresh()
            return true
        }

        // Лестница начинается с «как в настройках»: к общей модели надо иметь
        // возможность вернуться, а руками её из списка не выбрать — там
        // только имена.
        let ladder: [String?] = [nil] + models.map { Optional($0.stored) }
        let index = ladder.firstIndex(of: command.model) ?? 0
        command.model = ladder[(index + 1) % ladder.count]
        settings.updateCommand(command)
        DebugLog.write("команда «\(command.title)»: модель — \(command.model ?? "как в настройках")")
        return true
    }

    /// Tab в поле вопроса меняет модель этого разговора.
    ///
    /// Разговора, а не настроек: выбранное держится до конца переписки
    /// и сбрасывается вместе с ней. Настройку правит настройка — здесь
    /// же спрашивают «а что скажет вот эта».
    ///
    /// По тому же кругу и через «как в настройках», что и у команды:
    /// два перебора одного и того же разошлись бы на первой правке.
    private func cycleQuestionModel() -> Bool {
        guard settings.ollamaEnabled else { return false }
        let models = ModelList.shared.models
        guard !models.isEmpty else {
            // Спрашиваем сейчас же: к следующему нажатию список будет.
            // Tab при этом не уходит дальше — иначе он вставил бы отступ
            // в вопрос, и выглядело бы это как «Tab не работает».
            ModelList.shared.refresh()
            return true
        }

        let ladder: [String?] = [nil] + models.map { Optional($0.stored) }
        let index = ladder.firstIndex(of: assistant.questionModel) ?? 0
        assistant.setQuestionModel(ladder[(index + 1) % ladder.count])
        DebugLog.write("вопрос: модель — \(assistant.questionModel ?? "как в настройках")")
        return true
    }

    /// Esc снимает подсветку и закрывает выбор модели.
    ///
    /// Возвращает `false`, когда снимать было нечего: тогда нажатие идёт
    /// дальше и панель закрывает `NotchInput`. Иначе Esc закрывал бы панель
    /// вместе с набранным вопросом за одно нажатие — а человек всего лишь
    /// передумал выбирать команду.
    private func escapeHighlight() -> Bool {
        // Esc на карточке — отказ от предложенного, а не закрытие панели:
        // разговор при этом продолжается, и модель об отказе узнаёт.
        if assistant.pending != nil {
            declinePendingAction()
            return true
        }
        if assistant.choosingModelFor != nil {
            assistant.choosingModelFor = nil
            return true
        }
        // Esc над списком инструментов — то же самое: закрывается список,
        // а не панель.
        if assistant.isPickingSlash {
            dismissedSlash = SlashQuery.query(in: draft.question)
            assistant.hideSlash()
            return true
        }
        // Esc над списком «@» закрывает список, а не панель. Набранное
        // остаётся как есть: человек передумал выбирать, а не передумал
        // писать. Снова список поднимется, когда он изменит запрос.
        if assistant.isPickingMention {
            dismissedMention = MentionQuery.query(in: draft.question)
            assistant.hideMentions()
            return true
        }
        if assistant.highlightedAnswerAction != nil {
            assistant.highlightedAnswerAction = nil
            NotchHintTracker.shared.focus(nil)
            return true
        }
        guard assistant.highlightedCommandID != nil else { return false }
        assistant.highlightedCommandID = nil
        NotchHintTracker.shared.focus(nil)
        return true
    }

    /// Выбор модели открывается на месте списка команд.
    private func beginChoosingModel(_ command: QuickCommand) {
        assistant.highlightedCommandID = command.id
        assistant.choosingModelFor = command.id
        // Список могли не запрашивать ни разу: настройки открывают не все,
        // а до этого момента моделей взять неоткуда.
        ModelList.shared.refresh()
    }

    private func chooseModel(_ model: String?) {
        defer { assistant.choosingModelFor = nil }
        guard let id = assistant.choosingModelFor,
              var command = settings.quickCommands.first(where: { $0.id == id })
        else { return }
        command.model = model
        settings.updateCommand(command)
        DebugLog.write("команда «\(command.title)»: модель — \(model ?? "как в настройках")")
    }

    /// Поле ввода требует клавиатуры, а вырез по умолчанию фокус не забирает:
    /// на этом держится «выделил текст, спросил у модели, вставил обратно».
    /// Забираем явно — и возвращаем при закрытии.
    /// Куда вставлять из истории: приложение, из которого её открыли.
    private var clipboardTarget: NSRunningApplication?

    private func takeKeyboard() {
        NSApp.activate(ignoringOtherApps: true)
        host.makeKey()
        // После того как окно стало ключевым: до этого первого отклика
        // назначать некому. Строка вопроса забирает фокус сама при появлении,
        // а полю заметки его надо отдать руками.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.draft.mode == .note else { return }
            self.draft.focusNote()
        }
    }

    /// Сменить режим панели.
    ///
    /// Фокус переезжает вместе с режимом: поле, в которое нельзя печатать
    /// сразу, — это лишний щелчок на каждое переключение.
    private func selectMode(_ mode: NotePanelMode) {
        draft.setMode(mode)
        flash.clear()
        takeKeyboard()
    }

    /// Набранное уходит модели.
    ///
    /// Заметки в контекст кладутся только при включённом переключателе
    /// и только в первую реплику разговора: дальше они уже в переписке.
    /// Оборвать ответ на полуслове — кнопкой «Остановить».
    ///
    /// Написанное до обрыва остаётся на экране: человек жмёт «стоп», когда
    /// нужное уже прочитал, и стирать это значило бы отнимать у него ответ
    /// вместо того чтобы прекратить его дописывать. Разговор при этом живой:
    /// следующий вопрос уходит той же перепиской.
    func stopAnswer() {
        guard assistant.isStreaming else { return }
        DebugLog.write("модель: ответ оборван человеком, \(assistant.answer.count) симв.")
        assistant.cancel()
        takeKeyboard()
    }

    func sendDraft() {
        // Подсвеченное забирает Enter себе — что бы это ни было. Человек
        // довёл до него стрелками и ждёт именно его: иначе клавиша делала бы
        // не то, на что показывает подсветка.
        //
        // Карточка помощника — раньше всего: она стоит поперёк разговора
        // и держит его. Пока на неё не ответили, любое другое толкование
        // Enter означало бы, что человек продолжает говорить в сторону,
        // а круг молча ждёт.
        if assistant.pending != nil {
            confirmPendingAction()
            return
        }
        // Список «/» забирает Enter себе по той же причине, что и «@»:
        // он открыт ровно тогда, когда человек набирает имя группы,
        // и отправлять недописанное «/наст» модели незачем.
        if assistant.isPickingSlash,
           let index = assistant.highlightedSlash,
           assistant.slashMatches.indices.contains(index) {
            pickSlash(assistant.slashMatches[index])
            return
        }
        // Список «@» забирает Enter себе: он открыт ровно тогда, когда
        // человек набирает имя записи, и отправлять недописанное «@пла»
        // модели незачем.
        if assistant.isPickingMention,
           let index = assistant.highlightedMention,
           assistant.mentionMatches.indices.contains(index) {
            pickMention(assistant.mentionMatches[index])
            return
        }
        // Набранный вопрос старше любой подсветки. Подсветку на «Скопировать»
        // ставит **само приложение**, как только ответ дописан, — человек её
        // не наводил. Пока она стояла первой, уточняющий вопрос уходил
        // не модели: Enter копировал прежний ответ, а `copyAnswer` закрывает
        // панель — вырез схлопывался прямо на полуслове.
        let typed = draft.question.trimmingCharacters(in: .whitespacesAndNewlines)

        // Действие с ответом идёт первым, только когда спрашивать нечего:
        // подсветка переезжает туда сама, и в этот момент она единственная
        // на весь экран.
        if typed.isEmpty, let action = assistant.highlightedAnswerAction {
            runAnswerAction(action)
            return
        }
        if typed.isEmpty, let id = assistant.highlightedCommandID,
           let command = visibleCommands.first(where: { $0.id == id }) {
            runCommandFromPanel(command)
            return
        }
        // Выбранная через «/» группа разбирается из самого набранного,
        // а не из памяти о нажатии: человек стирает ярлык, и уходить модели
        // должно ровно то, что написано. Ярлык из вопроса при этом убирается —
        // это указание приложению, а не часть вопроса.
        let chosen = SlashQuery.chosen(in: typed, from: SlashCatalogue.all(for: settings))
        assistant.toolFilter = chosen?.tool.tools
        let text = chosen?.question ?? typed
        // Вопрос из одного ярлыка — это не вопрос: человек выбрал группу
        // и не дописал. Отправлять пустоту незачем, а ярлык пусть стоит
        // в поле и ждёт.
        guard !text.isEmpty, settings.ollamaEnabled else { return }
        if let chosen {
            DebugLog.write("инструмент: вопрос уходит с «\(chosen.tool.title)» — "
                + chosen.tool.tools.map(\.name).joined(separator: ", "))
        }

        // Позванное через «@» сужается до того, что уцелело в наборе:
        // стёртое упоминание не должно оставаться в поле зрения помощника,
        // иначе он отменит встречу, о которой в вопросе уже ни слова.
        //
        // Уточняющий вопрос при этом ничего не теряет: «перенеси её на час
        // позже» упоминаний не содержит вовсе, и прежнее поле зрения
        // остаётся при нём.
        let alive = MentionQuery.surviving(assistant.mentions, in: text)
        if !alive.isEmpty || assistant.isFirstQuestion { assistant.keepMentions(alive) }
        agent.setMentions(assistant.mentions)
        // Указание про выбранную группу идёт тем же путём, что и указанные
        // через «@» записи: инструментов модель и так получит ровно столько,
        // сколько в группе, но с одним инструментом в списке маленькая
        // модель нет-нет да и отвечает из головы, не позвав его.
        let mentioned = [chosen.map { SlashQuery.instruction(for: $0.tool) },
                         mentionContext(for: assistant.mentions)]
            .compactMap { $0 }
            .joined(separator: "\n\n")
        let hints: String? = mentioned.isEmpty ? nil : mentioned

        guard assistant.usesNotes, settings.notesEnabled else {
            assistant.send(text, mentionContext: hints)
            draft.clearQuestion()
            return
        }

        // Поле очищаем сразу, не дожидаясь отбора: вопрос уже принят,
        // и оставленный в поле текст читается как несработавшая отправка.
        draft.clearQuestion()
        retriever.context(for: text) { [weak self] context in
            guard let self else { return }
            guard let context else {
                // Заметок нет вовсе или ни одна к вопросу не подошла —
                // сказать об этом честнее, чем задать вопрос по пустому
                // архиву и выдать общий ответ за найденный.
                activities.present(.command(text: t("В заметках такого нет"), state: .failed))
                return
            }
            assistant.send(text, mentionContext: hints, notesContext: context)
        }
    }

    /// Набранное уходит в заметки. Открытая на правку — переписывается,
    /// новая — заводится.
    private func saveNote() {
        guard settings.notesEnabled else { return }
        let wasEditing = draft.editingID != nil

        // Заметку открыли и не тронули — закрываем, а не переписываем.
        // Перезапись тем же текстом сдвинула бы время правки, а по нему
        // список и сортируется: заметка выпрыгнула бы наверх ни за что.
        if wasEditing, !draft.isNoteEdited {
            draft.clearNote()
            DebugLog.write("заметки: правка закрыта без изменений")
            return
        }

        guard let saved = notes.save(draft.attributed, origin: .typed, editing: draft.editingID)
        else { return }
        // Подтверждение внутри панели, а не плашкой в вырезе: плашку из-под
        // открытой накладки не видно, и сохранение выглядело как несработавшее.
        flash.show(wasEditing ? t("Заметка обновлена") : t("Записано в заметки"))
        DebugLog.write("заметки: сохранено из панели — \(saved.id)")
        draft.clearNote()
    }

    /// Ответ модели уходит в заметки — без разметки, тем же текстом,
    /// что виден на экране. Звёздочек человек не видел, и в заметке
    /// им взяться неоткуда.
    private func saveAnswer() {
        guard settings.notesEnabled else { return }
        let text = MarkdownRender.plain(assistant.answer)
        guard !text.isEmpty else { return }
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: Note.bodyFontSize),
            .foregroundColor: NSColor.white,
        ])
        guard notes.save(attributed, origin: .assistant) != nil else { return }
        flash.show(t("Ответ в заметках"))
    }

    private func toggleNotesSearch() {
        assistant.usesNotes.toggle()
        DebugLog.write("модель: поиск по заметкам — \(assistant.usesNotes)")
    }

    private func copyAnswer() {
        assistant.copyAnswer()
        activities.present(.command(text: t("Ответ в буфере"), state: .done))
        closeAssistant()
    }

    private func pasteAnswer() {
        assistant.pasteAnswer { [weak self] in
            self?.closeAssistant()
        }
    }

    func closeAssistant() {
        let target = assistant.target
        assistant.reset()
        // Набранное остаётся на диске и вернётся при следующем открытии,
        // а вот правка заметки — нет: сохранять вслепую в запись, про которую
        // уже забыли, что её открывали, нельзя.
        draft.saveNow()
        draft.endEditing()
        flash.clear()
        router.close()
        // Клавиатуру панель забирает всегда — значит и возвращать её надо
        // всегда, иначе человек остаётся без фокуса в чужом окне.
        if let target, !target.isActive {
            target.activate()
        }
    }

    // MARK: - Заметки

    func openNotes() {
        guard settings.notesEnabled else { return }
        router.set(.notes)
        takeKeyboard()
    }

    /// Клавиша ведёт к **созданию** заметки, а не к списку.
    ///
    /// Записывают чаще, чем перечитывают: мысль приходит сама, а за списком
    /// идут нарочно. Список открывается из этой же панели одной кнопкой,
    /// а вот запись на бегу должна быть в одно нажатие.
    private func toggleNoteComposer() {
        guard settings.notesEnabled else { return }
        if router.current == .assistant, draft.mode == .note {
            closeAssistant()
            return
        }
        openNoteComposer()
    }

    /// Новая заметка: панель в режиме заметки, привязка к правившейся записи
    /// сброшена.
    private func openNoteComposer(seededWith text: String = "") {
        guard settings.notesEnabled else { return }
        draft.startNewNote(seededWith: text)
        // Строку поиска снимаем: она своё дело сделала и уехала в заметку,
        // а оставшись, показала бы при следующем заходе пустой список
        // с непонятно откуда взявшимся запросом.
        if !text.isEmpty { notes.query = "" }
        assistant.ask(target: NSWorkspace.shared.frontmostApplication)
        router.set(.assistant)
        takeKeyboard()
    }

    /// Календарь и правка события — из сессии до них не добраться: и то
    /// и другое открывается нажатием, а нажатия сюда не доходят.
    /// Кольцо в раскрытом виде, с подсвеченным кружком.
    ///
    /// Иначе его не снять вовсе: оно живёт, только пока держат кнопку,
    /// а нажатия из сессии не доходят. Держится несколько секунд и гаснет
    /// само, ничего не открывая.
    func debugQuickRing(highlight: Int = 4, seconds: TimeInterval = 6) {
        ring.open()
        ring.move(to: highlight)
        host.updateInteractiveRect()
        // Наведение не трогаем: кольцо выше него в расчёте состояния,
        // и опрос курсора его не перебьёт.
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            _ = self.ring.close()
            self.host.updateInteractiveRect()
        }
        DebugLog.write("кольцо: показано на \(Int(seconds)) с")
    }

    func debugCalendar() {
        openCalendar()
    }

    /// Календарь со шкалой времени. Выбор представления — настройка
    /// человека, поэтому повторный вызов возвращает прежний: отладка
    /// не должна оставлять после себя чужой выбор.
    func debugCalendarTimeline() {
        if let saved = viewBeforeTimeline {
            settings.calendarDayView = saved
            viewBeforeTimeline = nil
            DebugLog.write("календарь: представление возвращено — \(saved.rawValue)")
            return
        }
        viewBeforeTimeline = settings.calendarDayView
        settings.calendarDayView = .timeline
        openCalendar()
        DebugLog.write("календарь: шкала времени, дел на день — \(planner.events.count)")
    }

    /// Правка первого события выбранного дня, а если день пуст — новое
    /// событие: снять надо оба вида, а какой достанется, зависит от того,
    /// что стоит у человека в календаре сегодня.
    func debugEditEvent() {
        openCalendar()
        guard let first = planner.events.first else {
            DebugLog.write("календарь: на сегодня пусто — открываю новое событие")
            composeEvent()
            return
        }
        openItem(first)
    }

    /// Правка первого повторяющегося события, какое найдётся впереди.
    ///
    /// Отдельным событием, потому что вид у панели тогда другой: заголовок
    /// предупреждает о повторе, а в ряду кнопок появляется выбор «только
    /// это / весь ряд». Наткнуться на такое событие среди сегодняшних —
    /// как повезёт, а проверять надо наверняка.
    func debugEditSeries() {
        openCalendar()
        let calendarForDays = Calendar.current
        for offset in 0..<60 {
            guard let day = calendarForDays.date(byAdding: .day, value: offset, to: Date()) else {
                continue
            }
            for item in calendar.events(on: day) {
                planner.edit(item, fromCalendar: true)
                guard planner.draft?.isRecurring == true else { continue }
                planner.select(day)
                planner.edit(item, fromCalendar: true)
                router.set(.eventEditor)
                takeKeyboard()
                DebugLog.write("календарь: повторяющееся «\(item.title)» найдено")
                return
            }
        }
        planner.cancelEditing()
        DebugLog.write("календарь: повторяющихся событий впереди на два месяца нет")
    }

    /// Правка первого события с длинным описанием.
    ///
    /// Отдельным событием, потому что именно на длинном тексте вылезла беда:
    /// поле росло по своему содержимому и накрывало кнопки панели. С пустым
    /// описанием этого не увидеть вовсе.
    func debugEditEventWithNotes() {
        openCalendar()
        let days = Calendar.current
        for offset in 0..<60 {
            guard let day = days.date(byAdding: .day, value: offset, to: Date()) else { continue }
            for item in calendar.events(on: day) {
                guard let found = calendar.draft(for: item), found.notes.count > 200 else { continue }
                planner.select(day)
                planner.edit(item, fromCalendar: true)
                router.set(.eventEditor)
                takeKeyboard()
                DebugLog.write("календарь: «\(item.title)» с описанием в \(found.notes.count) знаков")
                return
            }
        }
        DebugLog.write("календарь: событий с длинным описанием впереди нет")
    }

    func debugComposeEvent() {
        openCalendar()
        composeEvent()
    }

    func debugToggleNotes() {
        guard settings.notesEnabled else { return }
        router.toggle(.notes)
    }

    func debugNoteComposer() { toggleNoteComposer() }

    /// Черновик со списком с галочками — посмотреть их вёрстку.
    func debugChecklist() {
        draft.debugCompose(ObsidianMarkdown.attributed(
            from: "Покупки\n- [ ] Хлеб\n- [x] Молоко\n- [ ] Кофе в зёрнах\n  - [x] Вложенный пункт"
        ))
        router.set(.assistant)
        takeKeyboard()
    }

    func debugSaveNote() { saveNote() }

    /// Свежая заметка — на правку. Проверяет, что режим переключается сам:
    /// заметка, открытая в разговоре, показывалась бы поверх чужого ответа
    /// и с однострочным полем.
    func debugTogglePinNewestNote() {
        guard let note = notes.notes.first(where: { !$0.isReadOnly }) else { return }
        togglePin(note)
        DebugLog.write("заметки: булавка у \(note.id), закреплено \(notes.pinned.count)")
    }

    func debugEditNewestNote() {
        guard let note = notes.notes.first else {
            DebugLog.write("заметки: пусто, сперва notesFill")
            return
        }
        openNote(note)
        DebugLog.write("заметки: на правку \(note.id), режим \(draft.mode.rawValue)")
    }

    /// Заметка открывается на правку там же, где её набирали, — в панели
    /// модели. Отдельного окна правки нет: поле ввода уже есть.
    private func openNote(_ note: Note) {
        // Заметку хранилища в поле правки не открываем вовсе. Поле знает
        // заголовок, жирный, курсив и ссылку, а в чужой заметке бывают
        // таблицы, списки задач и вложения: сохранение потеряло бы их молча.
        guard !note.isReadOnly else {
            openInObsidian(note)
            return
        }
        draft.load(note)
        router.set(.assistant)
        takeKeyboard()
    }

    /// Уводит заметку хранилища в сам Obsidian.
    private func openInObsidian(_ note: Note) {
        guard let vault = obsidian.vault,
              let path = obsidianPath(of: note),
              let url = vault.openURL(for: path),
              ObsidianApp.isInstalled
        else {
            activities.present(.command(text: t("Эту заметку правят в Obsidian"), state: .failed))
            return
        }
        router.close()
        NSWorkspace.shared.open(url)
    }

    private func obsidianPath(of note: Note) -> String? {
        obsidian.path(ofNote: note.id)
    }

    private func exportNotes() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = t("Выгрузить")
        panel.message = t("Куда сложить заметки")

        // Панель выбора отбирает фокус у выреза, и накладка закрылась бы
        // щелчком мимо ещё до того, как человек увидит окно.
        router.close()
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let result = notes.exportAll(to: folder)
        activities.present(.command(
            text: result.failed == 0
                ? tf("Выгружено заметок: %d", result.written)
                : tf("Выгружено %d, не вышло %d", result.written, result.failed),
            state: result.failed == 0 ? .done : .failed
        ))
    }


    // MARK: - Голос

    /// Связывает голосовой заход с вырезом.
    ///
    /// Ставится один раз: сам заход переживает перестройку геометрии,
    /// меняются только настройки — их перечитывает `installVoiceHotKey`.
    private func installVoice() {
        voice.onStart = { [weak self] in
            guard let self else { return }
            // Вздрагивание — единственный отклик, который заметен, когда
            // на вырез не смотрят. Свечение появляется плавно и краем глаза
            // читается не сразу, а толчок виден движением.
            self.purr.jolt()
            Haptics.tap()
            // Плашка события уступила бы месту самому свечению: голос
            // важнее её по расчёту состояния, и она всё равно не показалась
            // бы. Убираем явно, чтобы не висела под островом.
            self.activities.dismiss()
        }
        voice.onFailure = { [weak self] reason in
            // Молчаливый отказ неотличим от сломанного микрофона: человек
            // позвал голосом и ждёт хоть чего-нибудь.
            self?.activities.present(.command(text: reason, state: .failed))
        }
        installVoiceHotKey()
    }

    private func installVoiceHotKey() {
        voiceHotKey.onTrigger = { [weak self] in
            self?.toggleVoice()
        }
        voiceHotKey.install(settings.voiceTrigger, isEnabled: settings.voiceEnabled)
    }

    /// Позвать голос — или оборвать начатое тем же жестом.
    func toggleVoice() {
        guard settings.voiceEnabled else {
            DebugLog.write("голос: выключен в настройках")
            return
        }
        guard VoiceAccess.isReady else {
            requestVoiceAccess()
            return
        }
        // Инструменты подвешиваются и голосу: заметки перестали быть
        // отдельным входом, и добраться до них модель может только так.
        armAgent()
        // Список скачанных нужен, чтобы выбрать модель голоса. Спрашивается
        // здесь, пока человек ещё говорит: к концу фразы он уже придёт.
        if settings.ollamaEnabled { ModelList.shared.refreshIfNeeded() }
        voice.toggle()
    }

    /// Просит недостающие доступы и, получив их, продолжает заход.
    ///
    /// Спрашиваем в тот момент, когда доступ понадобился, а не при запуске:
    /// два системных диалога на старте приложения, которым человек ещё
    /// не пользовался, — верный способ получить отказ.
    private func requestVoiceAccess() {
        // Уже отказали — диалога больше не будет, и повторный запрос молча
        // вернёт «нет». Ведём в настройки: иначе нажатие жеста выглядело бы
        // как сломанное.
        guard VoiceAccess.microphone != .denied, VoiceAccess.recognition != .denied else {
            DebugLog.write("голос: доступ закрыт, открываю настройки")
            activities.present(.command(
                text: t("Нужен доступ к микрофону и распознаванию речи"),
                state: .failed
            ))
            if VoiceAccess.microphone == .denied {
                VoiceAccess.openMicrophoneSettings()
            } else {
                VoiceAccess.openRecognitionSettings()
            }
            return
        }

        DebugLog.write("голос: спрашиваю доступ к микрофону и распознаванию")
        // Приложение — агент: без этого системный диалог всплывает позади
        // чужого окна, и человек его попросту не увидит.
        NSApp.activate(ignoringOtherApps: true)
        VoiceAccess.request { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.activities.present(.command(
                    text: t("Нужен доступ к микрофону и распознаванию речи"),
                    state: .failed
                ))
                return
            }
            self.voice.toggle()
        }
    }

    /// Раскрыть разговор глазами — нажатием по голосовой полосе.
    ///
    /// Заход при этом продолжается: панель показывает ту же переписку,
    /// в которую сейчас говорят, а не отдельный её снимок.
    func openVoiceConversation() {
        guard settings.ollamaEnabled || settings.notesEnabled else { return }
        draft.setMode(.model)
        router.set(.assistant)
        takeKeyboard()
    }

    func debugToggleVoice() { toggleVoice() }

    /// Прогоняет фазы свечения по очереди — по восемь секунд на каждую.
    ///
    /// Живой заход для съёмки не годится: он идёт своим ходом, микрофон
    /// в отладочной сессии не поговорит, а фазы сменяются быстрее, чем
    /// успеваешь снять. Здесь фаза держится ровно столько, чтобы `shotNotch`
    /// поймал каждую.
    func debugVoiceGlow() {
        let phases: [VoiceSession.Phase] = [.listening, .thinking, .speaking]
        purr.jolt()
        for (index, phase) in phases.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 8) { [weak self] in
                guard let self else { return }
                self.voice.debugShow(phase: phase)
                DebugLog.write("голос: показана фаза \(phase)")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(phases.count) * 8) {
            [weak self] in
            self?.voice.stop()
        }
    }

    /// Полный путь ответа: фаза «отвечаю», чтение вслух и — главное —
    /// возврат в тишину. Полоса после ответа однажды осталась висеть,
    /// и поймать это можно только пройдя путь целиком.
    func debugVoiceAnswer() {
        // Без `t()`: строка отладочная, её слышит только разработчик —
        // как и записи журнала. Держать её в словарях незачем.
        voice.debugAnswer("Билеты до Владивостока уже куплены. Смета обсуждается завтра.")
    }

    /// Прочитать образец вслух — кнопкой «Прослушать» в настройках.
    ///
    /// Не отладочный вход, хотя начинался им: выбрать голос иначе нечем.
    /// Имена у них случайные — системный премиальный русский зовётся
    /// «Голос 2», — и разница между компактным и нейронным слышна только
    /// на слух.
    func speakVoiceSample() {
        let language = settings.voiceLanguage ?? Localization.shared.resolved
        voice.speaker.begin(
            language: language,
            rate: SpeechSpeaker.rate(forStep: settings.voiceRateStep),
            voiceIdentifier: settings.voiceIdentifier
        )
        voice.speaker.finishStream(answer: t("Проверка голоса. Так звучит ответ модели."))
        DebugLog.write("голос: читаю образец на \(language.rawValue)")
    }

    // MARK: - Буфер обмена

    func openClipboard() {
        guard settings.clipboardEnabled else { return }
        // Приложение запоминается **до** того, как панель заберёт фокус:
        // вставка обязана уйти туда, откуда пришли, а после `makeKey`
        // активным будем уже мы.
        //
        // Себя целью не берём. Историю открывают и из меню функций, а оно
        // к этому времени уже могло забрать фокус — цель вышла бы «Trunook»,
        // и вставка ушла бы в нас же. Без цели вставка идёт туда, где фокус
        // окажется сам, — как было до клавиатурной навигации.
        let front = NSWorkspace.shared.frontmostApplication
        clipboardTarget = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            ? nil
            : front
        clipboard.highlighted = nil
        router.set(.clipboard)
        // Клавиатура нужна ради стрелок и Enter. Панель обходилась без неё,
        // пока в ней было нечего нажимать, кроме мыши и цифр: цифры приходят
        // горячей клавишей и фокуса не требуют. Стрелки — требуют, и другого
        // способа получить их у панели без поля ввода нет.
        NSApp.activate(ignoringOtherApps: true)
        host.makeKey()
    }

    /// Клавишей историю и открывают, и убирают.
    func toggleClipboard() {
        if state.overlay == .clipboard {
            closeOverlay()
            return
        }
        openClipboard()
    }

    /// Нажатие мимо накладки или Esc. Не всякая накладка этому поддаётся —
    /// правило живёт в самой накладке, — но клавиатуру, если её забирали,
    /// возвращать надо и на этом пути тоже.
    private func dismissOverlay(_ cause: NotchInput.DismissCause) {
        // Панель команд закреплена, как телесуфлер: нажатие мимо её
        // не закрывает. С ней работают в чужом окне — читают ответ,
        // переключаются к письму, копируют оттуда кусок и возвращаются
        // дописать вопрос, — и каждое такое переключение унесло бы разговор.
        // Esc и крестик закрывают по-прежнему: это «я закончил», сказанное
        // прямо, а не побочный след работы.
        if cause == .clickOutside,
           state.overlay == .assistant,
           !settings.assistantClosesOnClickOutside {
            return
        }
        let wasClipboard = state.overlay == .clipboard
        router.dismiss()
        guard wasClipboard, state.overlay == nil else { return }
        clipboard.highlighted = nil
        returnKeyboardToClipboardTarget()
    }

    /// Закрыть накладку и вернуть клавиатуру тому, у кого её взяли.
    ///
    /// Одно место на все способы закрыть — крестик, Esc, нажатие мимо, та же
    /// клавиша второй раз. Возврат фокуса, разложенный по этим четырём путям,
    /// разошёлся бы при первой правке, и человек оставался бы без фокуса
    /// в чужом окне — по одному из путей из четырёх.
    func closeOverlay() {
        let wasClipboard = state.overlay == .clipboard
        router.close()
        guard wasClipboard else { return }
        clipboard.highlighted = nil
        returnKeyboardToClipboardTarget()
    }

    private func returnKeyboardToClipboardTarget() {
        defer { clipboardTarget = nil }
        guard let target = clipboardTarget, !target.isActive else { return }
        target.activate()
    }

    /// Клавиши, пока открыт список истории.
    ///
    /// Стрелки водят подсветку, Enter вставляет подсвеченное. Всё остальное
    /// уходит дальше нетронутым: панель забрала клавиатуру, и глотать чужие
    /// нажатия ей не за чем.
    private func handleOverlayKey(_ event: NSEvent) -> Bool {
        guard state.overlay == .clipboard, settings.clipboardEnabled else { return false }
        switch event.keyCode {
        case 126: return clipboard.moveHighlight(-1)
        case 125: return clipboard.moveHighlight(1)
        // 36 — Enter основной, 76 — на цифровой части.
        case 36, 76:
            guard let entry = clipboard.highlightedEntry else { return false }
            useClipboard(entry)
            return true
        default: return false
        }
    }

    /// Отложить скопированное в заметки — из списка истории или прямо
    /// с плашки о копировании.
    ///
    /// Ничего не открывает и не закрывает: это действие «попутно», его делают,
    /// не отрываясь от своего занятия. Список истории поэтому остаётся
    /// на экране — из него откладывают подряд несколько записей.
    private func saveClipboardToNotes(_ entry: ClipboardEntry) {
        guard let text = entry.notesText else { return }
        saveTextToNotes(text, origin: .clipboard, done: t("Записано в заметки"))
    }

    /// Выделенный в чужом окне текст — сразу заметкой, по клавише.
    ///
    /// Ничего не открывает: смысл в том и есть — выделил, нажал, продолжил
    /// читать. Панель, всплывшая поверх страницы, отняла бы у этого ровно то,
    /// ради чего сочетание и заводилось.
    ///
    /// Выделение читается тем же путём, что и для вопроса модели: сперва
    /// напрямую через дерево доступности, а кто не отдаёт — через имитацию
    /// ⌘C с возвратом прежнего буфера. Ответ приходит замыканием, потому что
    /// второй путь занимает до полусекунды.
    func saveSelectionToNotes() {
        guard settings.notesEnabled else { return }
        SelectionReader.read { [weak self] text in
            guard let self else { return }
            let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                // Молчать нельзя: человек нажал клавиши и ждёт ответа.
                // Без слов это выглядит как несработавшее сочетание, и его
                // жмут снова — а причина в том, что выделять было нечего
                // или приложение выделение не отдало.
                self.activities.present(.command(text: t("Нечего сохранить"), state: .failed))
                DebugLog.write("заметки: выделения нет")
                return
            }
            self.saveTextToNotes(trimmed, origin: .selection, done: t("Выделенное в заметках"))
        }
    }

    /// Кладёт простой текст заметкой и говорит об этом там, где человек
    /// сейчас смотрит.
    ///
    /// Подтверждение двоякое не от лени, а потому что мест два: при открытой
    /// накладке плашка события не видна вовсе — накладка важнее плашки
    /// по расчёту состояния и просто занимает её место; при закрытой,
    /// наоборот, не видно панели.
    private func saveTextToNotes(_ text: String, origin: Note.Origin, done: String) {
        guard settings.notesEnabled else { return }
        // Оформление своё, а не чужое: скопированный чёрный текст на чёрной
        // панели попросту не виден, а поменять его в заметке нечем.
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: Note.bodyFontSize),
            .foregroundColor: NSColor.white,
        ])
        guard notes.save(attributed, origin: origin) != nil else { return }

        if state.overlay == nil {
            activities.present(.command(text: done, state: .done))
        } else {
            flash.show(done)
        }
    }

    // MARK: - Запись разговора

    /// Пускает запись заметки прямо в вырезе.
    ///
    /// Путь у заметки бывает двух видов, и превратить относительный
    /// в настоящий может только тот, кто знает, где хранилище, — поэтому
    /// разбор здесь, а не в проигрывателе.
    private func playRecording(_ note: Note) {
        guard let url = audioURL(of: note) else {
            flash.show(t("Записи нет на месте"))
            return
        }
        player.toggle(note: note, url: url)
    }

    /// Где лежит запись этой заметки. `nil` — файла не найти.
    private func audioURL(of note: Note) -> URL? {
        guard note.hasAudio else { return nil }
        let url = note.audio.hasPrefix("/")
            ? URL(fileURLWithPath: note.audio)
            : obsidian.vault?.fileURL(for: note.audio)
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Удаляет заметку вместе с её записью.
    ///
    /// Запись уносится в Корзину, а не стирается: удаление в этой части кода
    /// всегда обратимо — то же правило, что у сверки с хранилищем, и по той
    /// же причине. Час разговора не восстановить ничем, а нажатие «удалить»
    /// бывает и промахом.
    ///
    /// Не в `NotesService`: путь внутри хранилища относительный, и превратить
    /// его в настоящий может только тот, кто знает, где хранилище. Служба
    /// заметок этого не знает и знать не должна.
    private func deleteNote(_ note: Note) {
        if note.hasAudio { trashAudio(of: note) }
        notes.delete(note)
    }

    // MARK: - Действия с заметкой

    private var noteActions: NoteActions {
        NoteActions(
            open: { [weak self] note in self?.openNote(note) },
            togglePin: { [weak self] note in self?.togglePin(note) },
            toggleKeepAudio: { [weak self] note in self?.notes.setKeepAudio(note, keep: !note.keepAudio) },
            deleteAudio: { [weak self] note in self?.deleteAudio(of: note) },
            play: { [weak self] note in self?.playRecording(note) },
            openInObsidian: { [weak self] note in self?.openInObsidian(note) },
            isInVault: { [weak self] note in self?.obsidian.path(ofNote: note.id) != nil }
        )
    }

    private func togglePin(_ note: Note) {
        guard notes.togglePin(note) else {
            announce(t("Закрепить можно не больше трёх заметок"))
            return
        }
    }

    /// Запись — в Корзину, заметка остаётся. Руками удаляют обратимо:
    /// нажатие бывает промахом, а час разговора ничем не восстановить.
    private func deleteAudio(of note: Note) {
        trashAudio(of: note)
        notes.clearAudio(note)
        obsidian.sync(manual: false)
        flash.show(t("Запись удалена"))
    }

    // MARK: - Кот в чёлке

    private var critterGate: CritterGate {
        CritterGate(
            enabled: settings.critterEnabled,
            isIdle: notchSnapshot.presentation == .collapsed,
            hasNotch: host.metrics?.hasNotch == true,
            reduceMotion: MotionPreference.shared.reduceMotion,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            idleSeconds: CritterGate.secondsSinceInput,
            fullScreen: CritterGate.isFullScreen(on: host.geometry?.screen)
        )
    }

    private func critterDue() {
        // Погодная сценка идёт или ждёт своего мига — кот подождёт её.
        // Сценка напоминания уже идёт — тоже: котик в чёлке один.
        if weatherScenes.scene != nil || weatherScenes.pending != nil || critter.act != nil {
            critter.retrySoon()
            return
        }
        let gate = critterGate
        guard gate.canPlay else {
            DebugLog.write("кот: не вышел — \(gate.reason)")
            gate.enabled ? critter.retrySoon() : critter.start()
            return
        }
        critter.play()
        updateCritterGaze()
    }

    /// Сценку перебивает всё, что вырезу есть показать, и выключенная
    /// настройка. Проверка — две булевых, на каждом тике это даром.
    private func interruptCritterIfBusy() {
        guard critter.act != nil else {
            critterForced = false
            return
        }
        // Сценка напоминания идёт вместе со своей плашкой: перебивает её
        // только то, что заведено рукой.
        if critter.act?.isReminder == true {
            if state.overlay != nil || state.isHovered || state.isPinnedOpen || ring.isOpen {
                critter.cancel()
            }
            return
        }
        // Отладочную сценку полоски не перебивают: снимать её приходится
        // тогда, когда в чёлке висит отсчёт до встречи.
        let busy = critterForced
            ? state.overlay != nil || state.isHovered || state.isPinnedOpen
            : !settings.critterEnabled || notchSnapshot.presentation != .collapsed
        if busy { critter.cancel() }
    }

    /// Сценка вызвана отладочным событием.
    private var critterForced = false

    /// Глаза следят за курсором; подведёшь руку совсем близко — щурятся.
    private func updateCritterGaze() {
        guard critter.act?.followsCursor == true, let notch = host.geometry?.notchRect else { return }
        let cursor = NSEvent.mouseLocation
        let dx = cursor.x - notch.midX
        // Вверх по экрану — `y` растёт, а в рисунке вниз: знак меняется.
        let dy = notch.midY - cursor.y
        // Чувствительность — полэкрана MacBook: мордочка ползёт вслед за курсором
        // заметно, но у края чёлки упирается, а не прыгает.
        let reach: CGFloat = 400
        critter.gaze = CGPoint(x: max(-1, min(1, dx / reach)), y: max(-1, min(1, dy / reach)))
        // Для охоты — сам курсор в точках от верха выреза: `notch.maxY` —
        // верхняя кромка экрана.
        if critter.act == .hunt {
            critter.pointer = CGPoint(x: dx, y: notch.maxY - cursor.y)
        }
        // «Курсор совсем рядом» нужен двоим: мордочка от этого щурится,
        // а лежащий котик в слежке пробует достать его лапкой.
        critter.squints = (critter.act == .eyes || critter.act == .watch) && hypot(dx, dy) < 120
    }

    // MARK: - Проверка обновлений из меню

    /// «Проверить обновления» в меню. Раньше нажатие проходило молча: проверка
    /// шла, но итог «новее нет» не показывался нигде, а готовое обновление
    /// сообщает о себе один раз за запуск. Теперь чёлка ведёт от «проверяю»
    /// до итога.
    func checkForUpdatesManually() {
        switch updates.state {
        case let .ready(release, _):
            // Уже скачано — показываем плашку с кнопкой ещё раз.
            activities.present(.update(version: release.version.text))
            return
        case let .downloading(release, progress):
            isReportingUpdate = true
            activities.present(.command(
                text: tf("Скачиваю версию %@ — %d%%", release.version.text, Int(progress * 100)),
                state: .running
            ))
            return
        case .checking, .installing:
            isReportingUpdate = true
            activities.present(.command(text: t("Проверяю обновления…"), state: .running))
            return
        default:
            break
        }
        isReportingUpdate = true
        activities.present(.command(text: t("Проверяю обновления…"), state: .running))
        updates.check(manual: true)
    }

    private func reportManualUpdate(_ state: UpdateState) {
        guard isReportingUpdate else { return }
        switch state {
        case .idle, .checking, .installing:
            break
        case let .found(release):
            activities.present(.command(text: tf("Найдена версия %@", release.version.text), state: .running))
        case let .downloading(release, progress):
            // Плашка обновляется по каждому проценту незачем — хватит начала.
            guard progress == 0 else { return }
            activities.present(.command(text: tf("Найдена версия %@ — скачиваю…", release.version.text), state: .running))
        case let .ready(release, _):
            isReportingUpdate = false
            activities.present(.update(version: release.version.text))
        case .upToDate:
            isReportingUpdate = false
            activities.present(.command(text: tf("У вас последняя версия %@", AppInfo.shortVersion), state: .done))
        case let .failed(failure):
            isReportingUpdate = false
            activities.present(.command(text: failure.message, state: .failed))
        }
    }

    // MARK: - Раскладка окон

    /// Окно, которое потащили, пока кнопка зажата. `nil` — ничего не тащат
    /// или тащат не окно.
    private var draggedWindow: DraggedWindow?
    /// Для этого нажатия окно уже искали: искать на каждом тике — дёргать
    /// чужое приложение десять раз в секунду.
    private var draggedWindowLooked = false

    /// На каждом тике: несут ли окно, не пора ли показать раскладки
    /// и не отпустили ли его над ними.
    private func updateWindowSnap() {
        let pressed = NSEvent.pressedMouseButtons & 1 != 0
        guard pressed else {
            finishWindowSnap()
            return
        }
        guard settings.windowSnapEnabled, input.isDragging else { return }
        if !draggedWindowLooked {
            draggedWindowLooked = true
            // Под курсором, а не в точке нажатия: окно едет вместе с курсором,
            // а от точки нажатия быстрый рывок уносит его за один тик.
            draggedWindow = DraggedWindow(pressedAt: NSEvent.mouseLocation)
        }
        guard let window = draggedWindow else { return }
        window.refresh()
        guard window.isMoving else { return }

        if state.overlay != .windowSnap, isNearNotch(NSEvent.mouseLocation) {
            // Поверх того, с чем работают руками, раскладки не открываем.
            guard state.overlay == nil else { return }
            router.set(.windowSnap)
        }
        updateWindowSlot()
    }

    /// Курсор у чёлки: над ней или чуть ниже, на её ширину с запасом.
    ///
    /// Не у самой кромки: окно, задержанное у верхнего края, система понимает
    /// как жест и открывает Mission Control — раскладки должны открыться
    /// раньше, чем курсор туда дойдёт.
    private func isNearNotch(_ point: CGPoint) -> Bool {
        guard let notch = host.geometry?.notchRect else { return false }
        let zone = CGRect(x: notch.minX - 60, y: notch.minY - 60, width: notch.width + 120, height: notch.height + 60)
        return zone.contains(point)
    }

    /// Раскладка под курсором — по движению, а не только по тику: плитки
    /// мелкие, и подсветка, отстающая на десятую долю секунды, промахивается.
    private func updateWindowSlot() {
        guard state.overlay == .windowSnap, let geometry = host.geometry, let metrics = host.metrics else { return }
        let size = CGSize(width: WindowSnapLayout.width, height: WindowSnapLayout.height(notchHeight: metrics.notchHeight))
        let frame = geometry.windowFrame(contentSize: size)
        let cursor = NSEvent.mouseLocation
        let point = CGPoint(x: cursor.x - frame.minX, y: frame.maxY - cursor.y)
        let slot = WindowSnapLayout.slot(at: point, notchHeight: metrics.notchHeight)
        guard slot != state.windowSlot else { return }
        state.windowSlot = slot
        Haptics.tap(.alignment)
    }

    /// Кнопку отпустили. Над раскладками — окно ложится по выбранной.
    private func finishWindowSnap() {
        // Нажатия не было — и заканчивать нечего. Иначе отпущенная кнопка
        // закрывала бы раскладки на каждом тике, кто бы их ни открыл.
        guard draggedWindowLooked else { return }
        defer {
            draggedWindow = nil
            draggedWindowLooked = false
        }
        guard state.overlay == .windowSnap else { return }
        let slot = state.windowSlot
        let window = draggedWindow
        state.windowSlot = nil
        router.close()
        guard let slot, let window, let screen = host.geometry?.screen else { return }
        let frame = slot.frame(in: screen.visibleFrame)
        DebugLog.write("окна: раскладка \(slot.rawValue) → \(NSStringFromRect(frame))")
        // С задержкой: система заканчивает перенос окна по отпусканию сама
        // и поставила бы его на место отпускания поверх нашей раскладки.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            DraggedWindow.place(window.element, in: frame, edges: slot.edges)
        }
    }

    /// Раскладки без перетаскивания: первый вызов открывает, каждый следующий
    /// подсвечивает следующую, после последней — закрывает.
    func debugStepWindowSlots() {
        guard state.overlay == .windowSnap else {
            router.set(.windowSnap)
            state.windowSlot = WindowSlot.allCases.first
            return
        }
        let all = WindowSlot.allCases
        guard let current = state.windowSlot, let index = all.firstIndex(of: current), index + 1 < all.count else {
            state.windowSlot = nil
            router.close()
            return
        }
        state.windowSlot = all[index + 1]
    }

    /// Все раскладки по очереди на переднем окне — сверка в журнале,
    /// какие получились. В конце окно возвращается как было.
    func debugCycleWindowSlots() {
        guard let window = DraggedWindow.frontmost(), let screen = host.geometry?.screen,
              let original = DraggedWindow.frame(of: window) else {
            DebugLog.write("окна: переднего окна нет")
            return
        }
        for (index, slot) in WindowSlot.allCases.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 1.6) {
                let frame = slot.frame(in: screen.visibleFrame)
                DebugLog.write("окна: цикл \(slot.rawValue)")
                DraggedWindow.place(window, in: frame, edges: slot.edges)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(WindowSlot.allCases.count) * 1.6) {
            DraggedWindow.place(window, in: original)
        }
    }

    /// Разложить окно переднего приложения — проверка установки места
    /// и размера без рук.
    func debugApplyWindowSlot(_ slot: WindowSlot) {
        guard let window = DraggedWindow.frontmost(), let screen = host.geometry?.screen else {
            DebugLog.write("окна: переднего окна нет")
            return
        }
        let frame = slot.frame(in: screen.visibleFrame)
        DebugLog.write("окна: проба \(slot.rawValue) → \(NSStringFromRect(frame))")
        DraggedWindow.place(window, in: frame, edges: slot.edges)
    }

    // MARK: - Перерывы

    /// Пора напомнить о перерыве. Возврат — показано ли: вырез занят —
    /// напоминание подождёт следующего тика.
    ///
    /// Не поверх того, с чем работают руками, и не поверх другой плашки:
    /// напоминание — не срочность, оно подождёт полминуты. Окно на весь экран
    /// тоже ждёт: фильм и презентацию не прерываем.
    private func remindBreak(_ kind: BreakKind) -> Bool {
        let busy = state.overlay != nil || state.isHovered || state.isPinnedOpen || ring.isOpen
            || voice.phase != nil || activities.current != nil || weatherScenes.scene != nil
        if busy {
            DebugLog.write("перерывы: \(kind.rawValue) ждёт — вырез занят")
            return false
        }
        if CritterGate.isFullScreen(on: host.geometry?.screen) {
            DebugLog.write("перерывы: \(kind.rawValue) ждёт — окно на весь экран")
            return false
        }
        showBreak(kind)
        return true
    }

    /// Плашка и сценка кота разом.
    private func showBreak(_ kind: BreakKind) {
        critter.cancel()
        activities.present(.breakReminder(kind))
        Haptics.tap(.levelChange)
        // Котик — если у экрана есть чёлка, из-за которой выходить,
        // и человек не просил меньше движения.
        guard host.metrics?.hasNotch == true, !MotionPreference.shared.reduceMotion else { return }
        if let metrics = host.metrics {
            critter.islandWidth = notchSnapshot.size(metrics: metrics).width
        }
        // Как отладочная: штатный выход кота по расписанию она не переносит.
        critter.play(kind.act, debug: true)
    }

    /// Напоминание сразу, в обход счёта и занятости.
    func debugBreak(_ kind: BreakKind) {
        router.close()
        activities.dismiss()
        breaks.debugAwait(kind)
        showBreak(kind)
    }

    /// Подсветка на строке вставки, а следующий вызов — то же, что Tab.
    ///
    /// Нажать Tab из сессии нечем: синтетические нажатия до Carbon
    /// не доходят. Ходим тем же путём, что и клавиша, — иначе проверялся бы
    /// не он.
    func debugPasteRow() {
        guard state.overlay == .assistant else {
            DebugLog.write("вставка: панель разговора закрыта")
            return
        }
        if assistant.highlightedAnswerAction != .paste {
            assistant.highlightedCommandID = nil
            assistant.highlightedAnswerAction = .paste
            showHintForHighlight()
            DebugLog.write("вставка: подсветка на строке вставки")
            return
        }
        _ = cycleModel()
    }

    /// Куда попадёт вставка в переднем приложении — словами в журнал.
    func debugPasteProbe() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            DebugLog.write("вставка: переднего приложения нет")
            return
        }
        let name = app.localizedName ?? "?"
        let pid = app.processIdentifier
        DispatchQueue.global(qos: .userInitiated).async {
            DebugLog.write("вставка в \(name): \(PasteTarget.probe(pid: pid))")
        }
    }

    /// Ответ на напоминание кнопкой в плашке.
    ///
    /// У воды галочка значит не «отстань», а «попил» — и следом спрашивает
    /// сколько. Счёт до следующего напоминания при этом начинается сразу,
    /// не дожидаясь записи: человек воду выпил, даже если закроет ползунок
    /// не записав.
    private func answerBreak(_ kind: BreakKind, done: Bool) {
        breaks.answer(kind, done: done)
        if case .breakReminder? = activities.current?.kind { activities.dismiss() }
        Haptics.tap(.levelChange)
        guard kind == .water, done else { return }
        openWater()
    }

    /// Когда последний раз проверяли, на месте ли плашка напоминания.
    private var breakCheckedAt = Date.distantPast

    /// Напоминание, которому не ответили, возвращается, как только вырез
    /// освободится: его убирает любая открытая панель и перебивает важная
    /// плашка, а пропасть без ответа оно не должно.
    private func keepBreakReminder() {
        guard let kind = breaks.awaiting, Date().timeIntervalSince(breakCheckedAt) >= 1 else { return }
        breakCheckedAt = Date()
        guard activities.current == nil, state.overlay == nil, !state.isHovered, !state.isPinnedOpen,
              !ring.isOpen, voice.phase == nil else { return }
        activities.present(.breakReminder(kind))
    }

    /// Крестик на плашке: у полки он прячет напоминание до следующего файла,
    /// у остальных просто убирает плашку.
    private func dismissActivity() {
        if case .shelf? = activities.current?.kind {
            dismissShelfChip()
        } else {
            activities.dismiss()
        }
    }

    // MARK: - Событие обратного отсчёта

    private var countdownCheckedAt = Date.distantPast

    /// Наступило событие отсчёта — плашка с его названием и залп конфетти,
    /// один раз на дату.
    ///
    /// Только пока плитка отсчёта стоит на главном экране: убранная плитка —
    /// значит, событие человеку больше не нужно. Наступившее больше суток
    /// назад не празднуется: приложение было выключено, и залп через три дня
    /// после отпуска — не праздник, а недоразумение.
    private func checkCountdownReached() {
        guard Date().timeIntervalSince(countdownCheckedAt) >= 1 else { return }
        countdownCheckedAt = Date()
        guard let date = settings.countdownEventDate, date <= Date(),
              settings.countdownCelebratedDate != date,
              settings.homeWidgets.contains(where: { $0.kind == .countdown })
        else { return }
        guard Date().timeIntervalSince(date) < 24 * 3600 else {
            settings.countdownCelebratedDate = date
            return
        }
        // Под открытой панелью плашку не видно — подождём, пока закроют.
        guard state.overlay == nil else { return }
        settings.countdownCelebratedDate = date
        celebrateCountdown()
    }

    private func celebrateCountdown() {
        router.close()
        activities.present(.countdownReached(title: settings.countdownEventTitle))
        Haptics.tap(.levelChange)
        onCelebrate?()
        DebugLog.write("отсчёт: событие наступило")
    }

    func debugCountdownReached() { celebrateCountdown() }

    // MARK: - Погодные сценки

    /// Можно ли сыграть погодную сценку. Те же условия, что у кота, плюс
    /// сам кот: двум сценкам в одной чёлке тесно.
    private var weatherSceneGate: CritterGate {
        CritterGate(
            enabled: settings.weatherScenesEnabled && settings.weatherEnabled,
            isIdle: Self.allowsWeatherScene(notchSnapshot) && critter.act == nil,
            hasNotch: host.metrics?.hasNotch == true,
            reduceMotion: MotionPreference.shared.reduceMotion,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            idleSeconds: weatherScenes.pendingIsDebug ? 0 : CritterGate.secondsSinceInput,
            fullScreen: CritterGate.isFullScreen(on: host.geometry?.screen)
        )
    }

    /// Когда последний раз спрашивали, можно ли сыграть отложенную сценку:
    /// проверка окна на весь экран обходит список окон, и на каждом тике
    /// её делать незачем.
    private var weatherSceneCheckedAt = Date.distantPast

    /// На каждом тике: перебить идущую сценку, если вырезу есть что
    /// показать, или сыграть отложенную, если стало можно.
    private func updateWeatherScene() {
        if weatherScenes.scene != nil {
            let snapshot = notchSnapshot
            let busy = !settings.weatherScenesEnabled || !Self.allowsWeatherScene(snapshot)
            if busy {
                weatherScenes.cancel()
            } else if let metrics = host.metrics {
                weatherScenes.noteIsland(snapshot.size(metrics: metrics))
            }
            return
        }
        guard weatherScenes.pending != nil,
              Date().timeIntervalSince(weatherSceneCheckedAt) >= 2,
              let scene = weatherScenes.due() else { return }
        weatherSceneCheckedAt = Date()
        // Дёшево отсеять занятый вырез до обхода окон.
        guard Self.allowsWeatherScene(notchSnapshot), critter.act == nil else { return }
        let gate = weatherSceneGate
        guard gate.canPlay else {
            DebugLog.write("погода: сценка ждёт — \(gate.reason)")
            return
        }
        weatherScenes.play(scene)
    }

    /// Сценке место — в свободной чёлке или под плашкой о самой погоде:
    /// при смене погоды вырез раскрывается ею, и сценка идёт вместе с ней,
    /// капая из-под её края, а не дожидается, пока она уйдёт.
    static func allowsWeatherScene(_ snapshot: NotchSnapshot) -> Bool {
        switch snapshot.presentation {
        case .collapsed: return true
        case .activity:
            if case .weather = snapshot.content.activity?.kind { return true }
            return false
        default: return false
        }
    }

    /// Смена погоды тем же путём, что и настоящая: плашка о погоде и сценка
    /// из очереди, со всеми условиями показа. В обход шла бы сценка без
    /// плашки — а у человека их всегда две вместе.
    func debugWeatherScene(_ scene: WeatherArt.Scene?) {
        let scene = scene ?? WeatherArt.Scene.allCases.randomElement() ?? .rain
        DebugLog.write("погода: проверка сценки — \(weatherSceneGate.reason)")
        critter.cancel()
        weatherScenes.queue(scene, force: true)
        weatherSceneCheckedAt = .distantPast
        let alert = weather.alert(for: scene)
        activities.present(.weather(text: alert.text, symbol: alert.symbol))
    }

    func debugCritter(_ act: NotchCritter.Act?) {
        DebugLog.write("кот: проверка — \(critterGate.reason)")
        critterForced = true
        critter.play(act, debug: true)
        updateCritterGaze()
    }

    // MARK: - Срок хранения записей

    private func installAudioRetention() {
        purgeExpiredAudio()
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.purgeExpiredAudio()
        }
        // `objectWillChange` приходит до записи значения — поэтому через
        // очередь главного потока: к этому мигу настройка уже новая.
        retentionObservation = settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, settings.audioRetentionDays != lastRetentionDays else { return }
                purgeExpiredAudio()
            }
    }

    /// Удаляет записи старше срока хранения. Текст заметок остаётся.
    ///
    /// По сроку удаляется **насовсем**, а не в Корзину: срок заводят, чтобы
    /// освободить место, а Корзина его не освобождает. Руками — в Корзину,
    /// см. `deleteAudio`.
    private func purgeExpiredAudio() {
        let days = settings.audioRetentionDays
        lastRetentionDays = days
        guard days > 0 else { return }
        var removed = 0
        for note in notes.expiredAudio(days: days) {
            // Хранилище не подключено — файл может лежать там, куда сейчас
            // не дотянуться. Путь не трогаем: следующая чистка его найдёт.
            if !note.audio.hasPrefix("/"), obsidian.vault?.isReachable != true { continue }
            if player.isPlaying(note.id) { player.stop() }
            if let url = audioURL(of: note) {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    DebugLog.write("запись: файл заметки \(note.id) не удалился — \(error.localizedDescription)")
                    continue
                }
            }
            notes.clearAudio(note)
            removed += 1
        }
        guard removed > 0 else { return }
        DebugLog.write("запись: по сроку \(days) дн. удалено записей \(removed)")
        obsidian.sync(manual: false)
    }

    private func trashAudio(of note: Note) {
        guard let url = audioURL(of: note) else {
            // Файла на месте нет: хранилище отключено или запись убрали
            // руками. Молча — человек удаляет заметку, а не разбирается
            // с хранилищем.
            DebugLog.write("запись: файла \(note.audio) нет, удалять нечего")
            return
        }
        // Играющую запись сперва глушим: удалять то, что звучит, — верный
        // способ получить тишину без объяснений.
        if player.isPlaying(note.id) { player.stop() }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            DebugLog.write("запись: файл заметки \(note.id) унесён в Корзину")
        } catch {
            DebugLog.write("запись: файл не унёсся — \(error.localizedDescription)")
        }
    }

    /// Заметка из записи готова.
    ///
    /// Показывается ровно так же, как сохранённое выделение, и по той же
    /// причине: мест два. При открытой накладке плашка события не видна
    /// вовсе — накладка важнее плашки по расчёту состояния; при закрытой,
    /// наоборот, не видно панели.
    private func announceRecording(_ note: Note, warning: String?) {
        // Предупреждение вместо имени заметки, а не вместе с ним: место
        // в плашке одно, и «почему нет текста» человеку нужнее, чем название,
        // которое он и так увидит в списке.
        announce(warning ?? tf("Заметка готова: %@", note.title))
    }

    private func announce(_ text: String) {
        if state.overlay == nil {
            activities.present(.command(text: text, state: .done))
        } else {
            flash.show(text)
        }
    }

    /// Свежую запись истории — в заметки. То же, что кнопка в строке списка
    /// и на плашке о копировании; нажать их из сессии нечем.
    func debugSaveNewestClipboardToNotes() {
        guard let entry = clipboard.entries.first else {
            DebugLog.write("буфер: пусто, сперва что-нибудь скопируйте")
            return
        }
        saveClipboardToNotes(entry)
    }

    func useClipboard(_ entry: ClipboardEntry) {
        // Панель закрывается до вставки: вставлять человек собирается в то,
        // что под ней. Цель берётся до закрытия — оно её и обнуляет.
        let destination = clipboardTarget
        closeOverlay()
        clipboard.use(entry, into: destination)
    }

    // MARK: - Полка

    /// Связывает зону приёма с вырезом. Ставится один раз: само окно приёма
    /// переживает перестройку геометрии, меняются только его размеры.
    private func installShelf() {
        shelfDrop.onEnter = { [weak self] urls in
            guard let self else { return }
            // Файлы ведут над чёлкой — раскрываем полку разделами, чтобы
            // человек видел, куда роняет и что с файлами станет.
            self.shelf.pruneMissing()
            self.state.shelfDropUnpacks = ShelfFileActions.unpacks(urls)
            self.state.shelfDropZone = .shelf
            self.state.isShelfDropTarget = true
            self.router.set(.shelf)
        }
        shelfDrop.onMove = { [weak self] point in
            guard let self, let zone = self.shelfZone(at: point), zone != self.state.shelfDropZone else { return }
            self.state.shelfDropZone = zone
            Haptics.tap(.alignment)
        }
        shelfDrop.onExit = { [weak self] in
            // Полку не закрываем: человек мог обвести файл мимо панели
            // и вести обратно. Закроется она как все накладки — по уходу
            // курсора за её границы.
            self?.state.isShelfDropTarget = false
        }
        shelfDrop.onDrop = { [weak self] urls, point in
            guard let self else { return false }
            self.state.isShelfDropTarget = false
            let zone = self.shelfZone(at: point) ?? .shelf
            DebugLog.write("полка: уронили в раздел \(zone)")
            guard zone == .shelf else {
                self.perform(zone, on: urls)
                return true
            }
            let added = self.shelf.add(urls)
            if added > 0 {
                Haptics.tap()
                // Новый файл — снова есть о чём напомнить, даже если прошлое
                // напоминание человек убрал крестиком.
                self.shelfChipDismissed = false
            }
            self.router.set(.shelf)
            return added > 0
        }
    }

    /// Раздел полки под точкой экрана. Пока окно приёма не раздалось
    /// до панели — никакого: полоска по чёлке уже панели, и горизонталь
    /// в ней значила бы не то.
    private func shelfZone(at point: CGPoint) -> ShelfDropZone? {
        guard let geometry = host.geometry, let metrics = host.metrics else { return nil }
        let size = NotchSizing.size(
            presentation: .shelf,
            content: NotchContent(shelfCount: ShelfPanel.columns * ShelfPanel.visibleRows),
            metrics: metrics
        )
        let frame = geometry.windowFrame(contentSize: size)
        guard point.y >= frame.minY - 1 else { return nil }
        return ShelfDropZone.at(x: point.x - frame.minX, width: frame.width)
    }

    /// Файлы уронили не на полку, а в раздел действия.
    ///
    /// Полка закрывается сразу: итог сообщает плашка, а плашку накладка
    /// закрывает собой.
    private func perform(_ zone: ShelfDropZone, on urls: [URL]) {
        router.close()
        switch zone {
        case .shelf:
            break
        case .archive:
            let unpacks = ShelfFileActions.unpacks(urls)
            activities.present(.command(text: unpacks ? t("Распаковываю…") : t("Сжимаю…"), state: .running))
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var made: [URL] = []
                var failed = false
                do {
                    if unpacks {
                        for archive in urls { made.append(try ShelfFileActions.unarchive(archive)) }
                    } else {
                        made.append(try ShelfFileActions.archive(urls))
                    }
                } catch {
                    failed = true
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    if failed {
                        self.activities.present(.command(
                            text: unpacks ? t("Не удалось распаковать") : t("Не удалось сжать"), state: .failed
                        ))
                        return
                    }
                    DebugLog.write("полка: готово — \(made.map(\.lastPathComponent))")
                    let text = made.count == 1
                        ? made[0].lastPathComponent
                        : tf("Распаковано архивов: %d", made.count)
                    self.activities.present(.command(text: text, state: .done))
                }
            }
        case .share:
            shareToCloud(urls)
        case .trash:
            ShelfFileActions.trash(urls) { [weak self] moved in
                guard let self else { return }
                self.shelf.pruneMissing()
                self.refreshShelfChip()
                guard moved > 0 else {
                    self.activities.present(.command(text: t("Не удалось переместить в Корзину"), state: .failed))
                    return
                }
                Haptics.tap()
                self.activities.present(.command(
                    text: urls.count == 1 ? tf("В Корзине: %@", urls[0].lastPathComponent) : tf("В Корзине: %d", moved),
                    state: .done
                ))
            }
        }
    }

    /// Ссылки iCloud на файлы — в буфер обмена, по строке на файл.
    ///
    /// Плашка «Загружаю в iCloud…» висит, пока файл едет на сервер: без неё
    /// минута ожидания выглядела бы как отказ.
    private func shareToCloud(_ urls: [URL]) {
        guard CloudShare.isAvailable else {
            activities.present(.command(text: t("iCloud Drive выключен"), state: .failed))
            return
        }
        activities.present(.command(text: t("Копирую в iCloud…"), state: .running))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var links: [URL] = []
            var failure: CloudShare.Failure?
            for url in urls {
                do {
                    links.append(try CloudShare.publish(url, onUploading: {
                        DispatchQueue.main.async {
                            self?.activities.present(.command(text: t("Загружаю в iCloud…"), state: .running))
                        }
                    }, onQueued: {
                        // Плашка ожидания уходит через пять минут, а ждать
                        // бывает дольше: говорим прямо, что ссылка придёт сама.
                        DispatchQueue.main.async {
                            self?.activities.present(.command(
                                text: t("iCloud загружает файл — ссылка скопируется, когда будет готова"),
                                state: .running
                            ))
                        }
                    }))
                } catch {
                    failure = error as? CloudShare.Failure ?? .other(error.localizedDescription)
                    break
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if let failure {
                    let text: String
                    switch failure {
                    case .noDrive: text = t("iCloud Drive выключен")
                    case .timedOut: text = t("iCloud за час так и не загрузил файл")
                    case .other: text = t("Не удалось получить ссылку")
                    }
                    // Ссылки, что успели, всё равно в буфере: терять их незачем.
                    if !links.isEmpty { self.copyLinks(links) }
                    self.activities.present(.command(text: text, state: .failed))
                    return
                }
                self.copyLinks(links)
                Haptics.tap()
                self.activities.present(.command(
                    text: links.count == 1 ? t("Ссылка скопирована") : tf("Ссылок скопировано: %d", links.count),
                    state: .done
                ))
            }
        }
    }

    private func copyLinks(_ links: [URL]) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(links.map(\.absoluteString).joined(separator: "\n"), forType: .string)
    }

    /// Разделы полки, как при перетаскивании: первый вызов открывает, каждый
    /// следующий подсвечивает следующий раздел, после последнего — закрывает.
    func debugStepShelfZones() {
        guard state.isShelfDropTarget else {
            state.shelfDropUnpacks = false
            state.shelfDropZone = .shelf
            state.isShelfDropTarget = true
            router.set(.shelf)
            return
        }
        guard let next = ShelfDropZone(rawValue: state.shelfDropZone.rawValue + 1) else {
            state.isShelfDropTarget = false
            router.close()
            return
        }
        state.shelfDropZone = next
    }

    /// Папка пробных файлов. В кэше, а не на рабочем столе: там iCloud
    /// и чужие файлы, а пробы должны трогать только своё.
    private static var debugShelfFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrunookShelfProbe", isDirectory: true)
    }

    /// Действие раздела на пробных файлах — тем же путём, что и падение файла.
    func debugShelfAction(_ zone: ShelfDropZone, unpack: Bool) {
        let folder = Self.debugShelfFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if unpack {
            let archives = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter(ShelfFileActions.isArchive)
            guard !archives.isEmpty else {
                DebugLog.write("полка: проба — архивов нет, сначала shelfZip")
                return
            }
            perform(zone, on: archives)
            return
        }
        let stamp = Int(Date().timeIntervalSince1970)
        let files = ["заметка", "список"].map { name -> URL in
            let url = folder.appendingPathComponent("\(name)-\(stamp).txt")
            try? "проба полки \(stamp)\n".write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        perform(zone, on: zone == .archive ? files : [files[0]])
    }

    /// Зона приёма: в покое — полоска ровно по чёлке, при перетаскивании
    /// раздаётся до размера панели полки.
    ///
    /// Полоска узкая не для красоты: окно, принимающее файлы, ест нажатия
    /// в своих границах, и позволить себе это можно только под самой чёлкой,
    /// где меню-бар пуст по устройству железа.
    private func rebuildShelfDrop(geometry: NotchGeometry, metrics: NotchMetrics) {
        guard settings.shelfEnabled else {
            shelfDrop.hide()
            return
        }
        // Растём сразу под полную полку, а не под нынешнее число файлов:
        // размер меняется посреди перетаскивания, и мишень не должна
        // съезжать под курсором.
        let grown = NotchSizing.size(
            presentation: .shelf,
            content: NotchContent(shelfCount: ShelfPanel.columns * ShelfPanel.visibleRows),
            metrics: metrics
        )
        // Полоска спускается ниже чёлки, и это не запас на промах.
        // Курсор, задержанный у самой верхней кромки во время перетаскивания,
        // система понимает как жест переключения пространств и открывает
        // Mission Control. Отменить жест нечем, поэтому файл надо перехватить
        // раньше, чем он дойдёт до кромки: заход в полоску немедленно
        // раскрывает зону приёма вниз, и вести к кромке уже незачем.
        let strip = geometry.notchRect.insetBy(dx: 0, dy: -Self.dropStripReach / 2)
            .offsetBy(dx: 0, dy: -Self.dropStripReach / 2)

        shelfDrop.update(
            collapsed: strip,
            grown: geometry.windowFrame(contentSize: grown)
        )
    }

    // MARK: - Таймер

    func openTimer() {
        guard settings.timerEnabled else { return }
        router.set(.timer)
    }

    private func toggleTimer() {
        guard settings.timerEnabled else { return }
        router.toggle(.timer)
    }

    /// Отладочные входы: сочетание из скрипта не нажать, а кнопку «Пуск»
    /// в панели — тем более.
    func debugToggleTimer() { toggleTimer() }

    /// Завести таймер на минуту и запустить: полоску в чёлке иначе не увидеть.
    func debugRunTimer() {
        router.close()
        timer.select(minutes: 1)
        timer.start()
    }

    /// Секундомер с уже набежавшим временем.
    ///
    /// Из сессии режим не переключить — он меняется нажатием, — а шкала
    /// у секундомера выглядит по-разному в начале и на ходу: пока прошло
    /// меньше четверти часа, левая половина полосы пуста, потому что времени
    /// до нуля не бывает. Проверять это надо на снимке, и добраться до него
    /// иначе нечем.
    func debugRunStopwatch() {
        timer.select(mode: .stopwatch)
        timer.start()
        router.set(.timer)
    }

    // MARK: - Сводки и сайты

    /// Открывает панель на том, что новое: пришло только изменение сайта —
    /// сразу на сайтах, пришла сводка — на свежей сводке.
    func openFeeds() {
        if digest.hasUnseen {
            feedsPanel.mode = .news
            feedsPanel.digestIndex = 0
        } else if siteWatch.hasUnseen {
            feedsPanel.mode = .sites
        }
        router.set(.feeds)
    }

    /// Плитка «Новости» или «Сайты»: вкладку выбрал человек, и то, что
    /// новое лежит на другой, его выбора не отменяет.
    func openFeeds(tab: FeedsPanelState.Mode) {
        feedsPanel.mode = tab
        if tab == .news { feedsPanel.digestIndex = 0 }
        router.set(.feeds)
    }

    private func toggleFeeds() {
        if state.overlay == .feeds {
            router.close()
        } else {
            openFeeds()
        }
    }

    private func saveDigestToNotes(_ shown: Digest) {
        guard settings.notesEnabled else {
            flash.show(t("Заметки выключены в настройках"))
            return
        }
        flash.show(digest.saveToNotes(shown, notes: notes) ? t("Сводка в заметках") : t("Не удалось сохранить"))
    }

    private func exportDigest(_ shown: Digest) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = DigestExport.fileName(for: shown)
        panel.canCreateDirectories = true
        panel.message = t("Куда сохранить сводку")
        // Окно сохранения отбирает фокус у выреза — как у выгрузки заметок.
        router.close()
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DigestExport.markdown(for: shown).write(to: url, atomically: true, encoding: .utf8)
            activities.present(.command(text: t("Сводка сохранена"), state: .done))
        } catch {
            DebugLog.write("сводка: файл не записался — \(error.localizedDescription)")
            activities.present(.command(text: t("Не удалось сохранить"), state: .failed))
        }
    }

    private func verifySite(_ watch: SiteWatch) {
        router.close()
        siteWatch.openForVerification(watch)
    }

    func debugRunDigest() { digest.run(manual: true) }
    func debugDigestPill() { activities.present(.digestReady(entries: 7)) }
    func debugWatchPill() {
        activities.present(.siteChanged(
            name: "Наушники", text: "12 990 ₽ → 11 490 ₽", url: URL(string: "https://example.com")!
        ))
    }
    func debugWatchCheck() { siteWatch.checkAll() }
    func debugWatchProbe() { siteWatch.probe() }

    // MARK: - Нагрузка на систему

    func openMonitor() {
        guard settings.monitorEnabled else { return }
        router.set(.monitor)
    }

    private func toggleMonitor() {
        guard settings.monitorEnabled else { return }
        router.toggle(.monitor)
    }

    /// Отладочный вход: сочетание из скрипта не нажать.
    func debugToggleMonitor() { toggleMonitor() }

    /// Разбираться, кто именно ест ресурсы, идут в Мониторинг системы:
    /// панель показывает только сколько, а не кто.
    private func openActivityMonitor() {
        router.close()
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            DebugLog.write("мониторинг: не открыть Мониторинг системы — \(error.localizedDescription)")
        }
    }

    // MARK: - Полка

    func openShelf() {
        shelf.pruneMissing()
        router.set(.shelf)
    }

    private func toggleShelf() {
        guard settings.shelfEnabled else { return }
        state.isShelfOpen ? router.close() : openShelf()
    }

    func removeFromShelf(_ item: ShelfItem) {
        shelf.remove(item)
        // Опустевшая полка закрывается сама: пустая панель поверх чужого окна
        // висела бы просто так.
        if shelf.isEmpty { router.close() } else { refreshShelfChip() }
    }

    func openShelfItem(_ item: ShelfItem) {
        router.close()
        NSWorkspace.shared.open(item.url)
    }

    func revealShelfItem(_ item: ShelfItem) {
        router.close()
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func clearShelf() {
        shelf.clear()
        router.close()
    }

    /// Напоминание о непустой полке.
    ///
    /// Не событие, а состояние: висит, пока файлы лежат. Поэтому показывается
    /// заново каждый раз, когда панель освобождает место, — и снимается,
    /// когда полка опустела.
    private func refreshShelfChip() {
        guard settings.shelfEnabled, !shelf.isEmpty else {
            if case .shelf = activities.current?.kind { activities.dismiss() }
            return
        }
        guard !shelfChipDismissed, state.overlay == nil else { return }
        activities.present(.shelf(count: shelf.items.count))
    }

    /// Крестик на плашке. Убирает её до следующего файла: человек уже знает,
    /// что на полке лежит, и напоминать ему больше не о чем.
    private func dismissShelfChip() {
        shelfChipDismissed = true
        activities.dismiss()
    }

    /// Файл потащили с полки наружу. Зону приёма на это время убираем:
    /// она раскрыта во всю панель и стоит ровно на пути.
    private func beginShelfDragOut() {
        state.isDraggingOut = true
        shelfDrop.isPinnedOpen = false
    }

    /// Файл донесли или бросили. Полка остаётся открытой: закроет её щелчок
    /// мимо, как и всё остальное в ней.
    private func endShelfDragOut() {
        state.isDraggingOut = false
        shelfDrop.isPinnedOpen = state.isShelfOpen
    }

    // MARK: - Меню всех функций

    /// Кольцо, открытое нажатием: правой кнопкой по вырезу и кнопкой в крыле
    /// главного экрана.
    ///
    /// Прежде оба пути открывали панель «Всё сразу» — сетку плиток. От неё
    /// отказались в пользу кольца: одно меню всех функций вместо двух
    /// с разным составом. Повторное нажатие закрывает кольцо — как и любое
    /// нажатие мимо кружков.
    func openRingMenu() {
        guard !ring.isOpen else {
            _ = ring.close()
            updateWindowInteractivity()
            host.updateInteractiveRect()
            return
        }
        router.close()
        ring.open(sticky: true)
        input.openStickyRing()
        Haptics.tap(.levelChange)
        DebugLog.write("кольцо: раскрыто нажатием")
        host.updateInteractiveRect()
    }

    // MARK: - Бодрость

    /// Нажатие по чашке открывает выбор срока.
    ///
    /// Раньше оно переключало удержание вслепую: срок брался из настроек,
    /// и какой он, из выреза было не узнать. Чашку же включают под конкретное
    /// дело, и срок у каждого дела свой — ходить за ним в отдельное окно
    /// дороже самого дела.
    func openAwake() {
        router.set(.caffeine)
    }

    /// Выбран срок. Ноль — без ограничения.
    ///
    /// Панель после выбора закрывается: выбор срока — это и есть всё, зачем
    /// её открывали, и оставлять её висеть значило бы требовать ещё одного
    /// нажатия по крестику.
    private func chooseAwakeLimit(minutes: Int) {
        let wasOn = wake.isOn
        wake.setLimit(minutes: minutes)
        router.close()
        Haptics.tap(.levelChange)
        // Плашку показываем только на включении. При перестановке срока
        // у горящей чашки её не нужно: панель была открыта, человек видел,
        // что нажал, — а плашка поверх только что закрытой панели читалась бы
        // как второе, отдельное событие.
        if !wasOn {
            activities.present(.caffeine(change: .on(minutes: minutes)))
        }
    }

    /// Выключить удержание.
    ///
    /// Плашка нужна: подложка под чашкой пропадает, но панель к этому моменту
    /// уже закрыта, и без плашки выключение выглядело бы не сработавшим.
    private func disableAwake() {
        wake.disable()
        router.close()
        Haptics.tap(.levelChange)
        activities.present(.caffeine(change: .off))
    }

    /// Панель блокировки клавиатуры.
    func openKeyboardLock() {
        router.set(.keyboardLock)
    }

    /// Выбран срок блокировки. Панель остаётся открытой: на ней отсчёт
    /// и кнопка досрочного снятия — клавиатурой их уже не позвать.
    func lockKeyboard(seconds: Int) {
        keyboardLock.lock(seconds: seconds)
        Haptics.tap(.levelChange)
    }

    private func unlockKeyboard() {
        keyboardLock.unlock()
        router.close()
        Haptics.tap(.levelChange)
    }

    /// Отладочный вход: ждать конца срока в сессии незачем.
    func debugExpireKeyboardLock() { keyboardLock.debugExpireNow() }

    // MARK: - Вода

    /// Ползунок воды. Открывается галочкой на напоминании и нажатием
    /// по плитке «Вода».
    func openWater() {
        water.refresh()
        router.set(.water)
    }

    /// Записать выставленное и сказать итог дня плашкой.
    ///
    /// Плашка, а не подтверждение внутри панели: панель закрывается тем же
    /// движением, и подтверждение в ней человек увидел бы долей секунды.
    /// Итог дня — то единственное, ради чего объём и спрашивали.
    private func recordWater() {
        let portion = water.record()
        router.close()
        Haptics.tap(.levelChange)
        activities.present(.waterLogged(portion: portion))
    }

    /// Ползунок сразу: нажать галочку на плашке из сессии нечем.
    func debugWater() {
        router.close()
        activities.dismiss()
        openWater()
    }

    /// Следующая посуда на ползунке — под снимок: протянуть его из сессии
    /// нечем. Журнал не трогает, двигается только черновик.
    func debugWaterVessel() {
        if state.overlay != .water { openWater() }
        // Следующая за той, что стоит сейчас, а не за самим объёмом:
        // середина полосы посуды меньше её границы, и счёт по объёму
        // топтался бы на месте.
        let current = WaterVessel.of(water.draft)
        let next = WaterVessel.allCases.first { $0.upperBound > current.upperBound }
            ?? WaterVessel.allCases[0]
        // Середина между границами, а не сама граница: на границе значок
        // ещё прежний, и снимок показал бы не ту посуду.
        let lower = WaterVessel.allCases.last { $0.upperBound < next.upperBound }?.upperBound
            ?? WaterVolume.minimum - WaterVolume.step
        water.setDraft((lower + next.upperBound) / 2)
        DebugLog.write("вода: \(water.draft) мл — \(next.title)")
    }

    /// Плашка с итогом дня на выдуманном заходе — под снимок. Журнал
    /// не трогает: записанное человеком не наше.
    func debugWaterPill() {
        activities.present(.waterLogged(portion: WaterVolume.standard))
    }

    private func undoWater() {
        water.undoLast()
        Haptics.tap(.levelChange)
    }

    /// Телесуфлер. Клавишей — переключателем, как и остальные накладки.
    ///
    /// Фокус забирается сразу и явно: в телесуфлер печатают, а вырез по
    /// устройству фокуса не отбирает — без этого поле не приняло бы ни одной
    /// буквы. Тем же приёмом пользуется поле встречного вопроса к модели.
    func toggleTeleprompter() {
        let wasOpen = state.isTeleprompterOpen
        router.toggle(.teleprompter)
        guard !wasOpen else { return }
        NSApp.activate(ignoringOtherApps: true)
        host.makeKey()
    }

    /// Плиткой меню — открытием, а не переключателем: в меню за «закрыть»
    /// не ходят, туда идут открывать.
    private func openTeleprompter() {
        guard !state.isTeleprompterOpen else { return }
        toggleTeleprompter()
    }

    /// Раскрыть главную панель без наведения на чёлку: из меню всех функций
    /// и по нажатию на полоску обратного отсчёта.
    ///
    /// Наведение выставляется вместе с фиксацией, хотя курсор в зону чёлки
    /// и не заходил. Без него панель осталась бы раскрытой навсегда: снимает
    /// фиксацию уход курсора, а уход считается только после захода — и то,
    /// и другое меряется по узкой полосе самой чёлки, мимо которой курсор
    /// в обоих случаях прошёл стороной. С наведением уход считается уже
    /// по всей раскрытой панели, и она схлопывается там, где человек
    /// её оставил.
    private func openExpanded() {
        router.close()
        if !state.isHovered { setHovered(true) }
        state.isPinnedOpen = true
        host.updateInteractiveRect()
    }

    /// Пересобрать окно: размеры панелей изменились.
    ///
    /// Тот же путь, что при смене экрана, — окно там пересчитывается целиком.
    /// Отдельного, более дешёвого пути заводить незачем: размер текста меняют
    /// раз в жизни, а два способа пересчитать одно и то же со временем
    /// разошлись бы.
    func relayout() {
        placeScreens(force: true)
    }

    /// Клавиша раскрывает панель и ею же сворачивает.
    ///
    /// Мышью свернуть можно уводом курсора, а с клавиатуры уводить нечего:
    /// без переключателя раскрытая панель осталась бы висеть до тех пор,
    /// пока к вырезу не подведут указатель, — то есть ровно то, чего у того,
    /// кто пользуется клавиатурой, и нет.
    private func toggleExpanded() {
        if state.isPinnedOpen {
            state.isPinnedOpen = false
            setHovered(false)
            host.updateInteractiveRect()
        } else {
            openExpanded()
        }
    }

    // MARK: - Записи и ссылки

    /// Открывает запись.
    ///
    /// Встречу — **своим окном правки**, а не Календарём Apple. Раньше вело
    /// туда: чтобы передвинуть встречу на полчаса или прочитать, где она,
    /// человек уходил из выреза в чужое окно поверх работы — и возвращался
    /// оттуда руками. Всё, что нужно от встречи в рабочий день, панель
    /// теперь умеет сама.
    ///
    /// Напоминание и задача по-прежнему уходят в своё приложение: править
    /// их вырез не умеет, и подменять переход пустым окном было бы обманом.
    func openItem(_ item: CalendarItem) {
        if item.source == .event, settings.calendarEnabled {
            // Из календаря — с возвратом в него; с главного экрана — без:
            // человек туда не заходил, и открывшийся по закрытии месяц был
            // бы подменой.
            planner.edit(item, fromCalendar: state.overlay == .calendar)
            guard planner.draft != nil else { return }
            router.set(.eventEditor)
            takeKeyboard()
            return
        }
        guard let url = item.appURL else {
            ThingsService.openToday()
            return
        }
        DebugLog.write("открываю запись «\(item.title)» в \(url.scheme ?? "?")")
        NSWorkspace.shared.open(url)
    }

    // MARK: - Мини-календарь

    func openCalendar() {
        guard settings.calendarEnabled else { return }
        planner.open()
        router.set(.calendar)
    }

    private func toggleCalendar() {
        guard settings.calendarEnabled else { return }
        if state.overlay == .calendar {
            router.close()
        } else {
            openCalendar()
        }
    }

    private func composeEvent() {
        planner.compose()
        router.set(.eventEditor)
        takeKeyboard()
    }

    /// Уйти из правки обратно в месяц, ничего не сохраняя.
    ///
    /// Отдельно от крестика: тот закрывает вырез целиком, и человек,
    /// пришедший в правку из календаря, терял вместе с ней и календарь.
    private func backToCalendar() {
        planner.cancelEditing()
        planner.reload()
        router.set(.calendar)
    }

    private func saveEvent() {
        guard planner.save() else { return }
        closeEditor()
    }

    private func deleteEvent() {
        guard planner.deleteEditing() else { return }
        closeEditor()
    }

    /// Куда уходит правка, когда она закончена.
    ///
    /// Возврат в календарь — только если оттуда и пришли. Нажав по встрече
    /// на главном экране, человек в календарь не заходил, и открывшийся
    /// по закрытии месяц был бы подменой.
    private func closeEditor() {
        guard planner.returnsToCalendar else {
            router.close()
            return
        }
        // Перечитываем до показа: правку сохранили только что, а хранилище
        // сообщает об изменениях своим уведомлением и не сразу — список
        // успел бы показать старое.
        planner.reload()
        router.set(.calendar)
    }

    /// Кладёт ссылку встречи в буфер — иногда её нужно переслать, а не открыть.
    func copyLink(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        DebugLog.write("ссылка встречи скопирована")
        activities.present(.command(text: t("Ссылка в буфере"), state: .done))
    }

    /// Открывает ссылку встречи. Ссылки берутся из полей события, а не
    /// из содержимого страниц, поэтому открываем как есть.
    func join(_ url: URL) {
        DebugLog.write("открываю ссылку встречи: \(url.host ?? url.absoluteString)")
        NSWorkspace.shared.open(url)
    }

    // MARK: - Вёрстка

    private func makeRootView(metrics: NotchMetrics, displayID: CGDirectDisplayID) -> NotchView {
        NotchView(
            state: state,
            activities: activities,
            music: music,
            calendar: calendar,
            planner: planner,
            ring: ring,
            things: things,
            meeting: meeting,
            clipboard: clipboard,
            assistant: assistant,
            dictation: dictation,
            weather: weather,
            battery: battery,
            shelf: shelf,
            timer: timer,
            monitor: monitor,
            teleprompter: teleprompter,
            notes: notes,
            draft: draft,
            voice: voice,
            recorder: recorder,
            player: player,
            flash: flash,
            wake: wake,
            keyboardLock: keyboardLock,
            water: water,
            critter: critter,
            weatherScenes: weatherScenes,
            digest: digest,
            sites: siteWatch,
            feedsPanel: feedsPanel,
            settings: settings,
            metrics: metrics,
            displayID: displayID,
            // Замыканием, а не значением: вид строится один раз, а состояние
            // меняется по десять раз в секунду. Вёрстка перерисовывается
            // от наблюдаемых служб и на каждой перерисовке спрашивает снимок
            // заново — тот же, по которому считается зона нажатий.
            snapshot: { [weak self] in
                self?.snapshot(for: displayID) ?? NotchController.handleSnapshot
            },
            onTap: { [weak self] in
                // Кольцо и раскрытие панели делят одно и то же нажатие:
                // панель раскрывается по отпусканию, и без этой проверки
                // за выбранной в кольце функцией раскрывалась бы ещё и она.
                guard self?.ring.swallowsTap() != true else { return }
                self?.expandPanel()
            },
            onOpenSettings: { [weak self] in self?.onOpenSettings?() },
            onJoin: { [weak self] url in self?.join(url) },
            onInstallUpdate: { [weak self] in self?.updates.install() },
            onOpenReleaseNotes: { [weak self] in self?.onOpenReleaseNotes?() },
            onRunCommand: { [weak self] command in self?.runCommandFromPanel(command) },
            onClearCapture: { [weak self] in self?.assistant.clearCapture() },
            onToggleCapture: { [weak self] in self?.assistant.isCaptureExpanded.toggle() },
            onBeginChoosingModel: { [weak self] command in self?.beginChoosingModel(command) },
            onChooseModel: { [weak self] model in self?.chooseModel(model) },
            onCancelChoosingModel: { [weak self] in self?.assistant.choosingModelFor = nil },
            onMoveHighlight: { [weak self] offset in self?.moveHighlight(offset) ?? false },
            onCycleModel: { [weak self] in self?.cycleModel() ?? false },
            onEscapeHighlight: { [weak self] in self?.escapeHighlight() ?? false },
            onConfirmAction: { [weak self] in self?.confirmPendingAction() },
            onCancelAction: { [weak self] in self?.declinePendingAction() },
            onCopyLink: { [weak self] url in self?.copyLink(url) },
            onOpenItem: { [weak self] item in self?.openItem(item) },
            onCloseOverlay: { [weak self] in self?.closeOverlay() },
            onOpenClipboard: { [weak self] in self?.openClipboard() },
            onUseClipboard: { [weak self] entry in self?.useClipboard(entry) },
            onSaveClipboardToNotes: { [weak self] entry in self?.saveClipboardToNotes(entry) },
            onStopVoice: { [weak self] in self?.voice.stop() },
            onStartVoice: { [weak self] in self?.toggleVoice() },
            onDictateNote: { [weak self] in self?.dictateNote() },
            onDictateQuestion: { [weak self] in self?.toggleQuestionDictation() },
            onStopRecording: { [weak self] in self?.recorder.stop() },
            onToggleRecording: { [weak self] in self?.recorder.toggleNote() },
            onToggleMeetingRecording: { [weak self] in self?.recorder.toggleMeeting() },
            onPlayRecording: { [weak self] note in self?.playRecording(note) },
            onDeleteClipboard: { [weak self] entry in self?.clipboard.delete(entry) },
            onClearClipboard: { [weak self] in self?.clipboard.clear() },
            onCopyAnswer: { [weak self] in self?.copyAnswer() },
            onPasteAnswer: { [weak self] in self?.pasteAnswer() },
            onSendDraft: { [weak self] in self?.sendDraft() },
            onStopAnswer: { [weak self] in self?.stopAnswer() },
            onSaveDraft: { [weak self] in self?.saveNote() },
            onSelectMode: { [weak self] mode in self?.selectMode(mode) },
            onNewNote: { [weak self] seed in self?.openNoteComposer(seededWith: seed) },
            onSaveAnswer: { [weak self] in self?.saveAnswer() },
            onToggleNotesSearch: { [weak self] in self?.toggleNotesSearch() },
            onPickMention: { [weak self] mention in self?.pickMention(mention) },
            onPickSlash: { [weak self] tool in self?.pickSlash(tool) },
            onCloseAssistant: { [weak self] in self?.closeAssistant() },
            onOpenNotes: { [weak self] in self?.openNotes() },
            onOpenCalendar: { [weak self] in self?.openCalendar() },
            onComposeEvent: { [weak self] in self?.composeEvent() },
            onEditEventTitle: { [weak self] text in self?.planner.changeTitle(text) },
            onEditEventLocation: { [weak self] text in self?.planner.changeLocation(text) },
            onEditEventNotes: { [weak self] text in self?.planner.changeNotes(text) },
            onChooseEventCalendar: { [weak self] id in self?.planner.chooseCalendar(id) },
            onCycleEventCalendar: { [weak self] in self?.planner.cycleCalendar() },
            onChooseEventSeries: { [weak self] whole in self?.planner.setEditsSeries(whole) },
            onBackToCalendar: { [weak self] in self?.backToCalendar() },
            onMoveEventDay: { [weak self] steps in
                self?.planner.change { $0.movingDay(by: steps) }
            },
            onMoveEventStart: { [weak self] steps in
                self?.planner.change { $0.movingStart(bySteps: steps) }
            },
            onStretchEvent: { [weak self] steps in
                self?.planner.change { $0.stretched(bySteps: steps) }
            },
            onToggleEventAllDay: { [weak self] in self?.planner.toggleAllDay() },
            onSaveEvent: { [weak self] in self?.saveEvent() },
            onDeleteEvent: { [weak self] in self?.deleteEvent() },
            onOpenNote: { [weak self] note in self?.openNote(note) },
            noteActions: noteActions,
            onDeleteNote: { [weak self] note in self?.deleteNote(note) },
            isNoteInVault: { [weak self] note in self?.obsidian.path(ofNote: note.id) != nil },
            onOpenNoteInObsidian: { [weak self] note in self?.openInObsidian(note) },
            onExportNotes: { [weak self] in self?.exportNotes() },
            onRemoveFromShelf: { [weak self] item in self?.removeFromShelf(item) },
            onOpenShelfItem: { [weak self] item in self?.openShelfItem(item) },
            onRevealShelfItem: { [weak self] item in self?.revealShelfItem(item) },
            onClearShelf: { [weak self] in self?.clearShelf() },
            onBeginShelfDragOut: { [weak self] in self?.beginShelfDragOut() },
            onEndShelfDragOut: { [weak self] in self?.endShelfDragOut() },
            onOpenShelf: { [weak self] in self?.openShelf() },
            onOpenTimer: { [weak self] in self?.openTimer() },
            onOpenMonitor: { [weak self] in self?.openMonitor() },
            onOpenActivityMonitor: { [weak self] in self?.openActivityMonitor() },
            onDismissActivity: { [weak self] in self?.dismissActivity() },
            onBreakAnswer: { [weak self] kind, done in self?.answerBreak(kind, done: done) },
            onOpenHub: { [weak self] in self?.openRingMenu() },
            onOpenTeleprompter: { [weak self] in self?.openTeleprompter() },
            onEditCountdown: { [weak self] in
                self?.router.close()
                self?.collapsePanel()
                self?.onOpenSettingsTab?(.home)
            },
            onRunCommandFromHome: { [weak self] command in self?.runCommandFromHome(command) },
            onChooseCommands: { [weak self] in
                self?.router.close()
                self?.collapsePanel()
                self?.onOpenSettingsTab?(.home)
            },
            onOpenExpanded: { [weak self] in self?.openExpanded() },
            onAskAssistant: { [weak self] in self?.askAssistant() },
            onOpenAwake: { [weak self] in self?.openAwake() },
            onChooseAwakeLimit: { [weak self] minutes in self?.chooseAwakeLimit(minutes: minutes) },
            onDisableAwake: { [weak self] in self?.disableAwake() },
            onOpenKeyboardLock: { [weak self] in self?.openKeyboardLock() },
            onLockKeyboard: { [weak self] seconds in self?.lockKeyboard(seconds: seconds) },
            onUnlockKeyboard: { [weak self] in self?.unlockKeyboard() },
            onOpenWater: { [weak self] in self?.openWater() },
            onRecordWater: { [weak self] in self?.recordWater() },
            onUndoWater: { [weak self] in self?.undoWater() },
            onOpenFeeds: { [weak self] in self?.openFeeds() },
            onOpenFeedsTab: { [weak self] tab in self?.openFeeds(tab: tab) },
            onOpenFeedsSettings: { [weak self] in
                self?.router.close()
                self?.onOpenSettingsTab?(.feeds)
            },
            onSaveDigest: { [weak self] digest in self?.saveDigestToNotes(digest) },
            onExportDigest: { [weak self] digest in self?.exportDigest(digest) },
            onVerifySite: { [weak self] watch in self?.verifySite(watch) }
        )
    }

    // MARK: - Отладочные входы

    /// Отладочный вход: набить полку и показать её. Настоящее перетаскивание
    /// из отладочной сессии не изобразить — синтетические события мыши
    /// до системы не доходят, — а вёрстку посмотреть надо.
    func debugFillShelf() {
        // Повторный вызов закрывает полку: щёлкнуть мимо неё, а только этим
        // она теперь и закрывается, из отладочной сессии нечем.
        if state.isShelfOpen {
            router.close()
            return
        }
        if shelf.isEmpty {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let candidates = (try? FileManager.default.contentsOfDirectory(
                at: home.appendingPathComponent("Desktop"),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            shelf.add(Array(candidates.prefix(7)))
        }
        openShelf()
    }

    /// Отладочный вход: раскрыть панель целиком. Нажать по вырезу
    /// из отладочной сессии нечем.
    ///
    /// Раскрытие удерживается несколько секунд: опрос положения курсора идёт
    /// десять раз в секунду и снял бы наведение на первом же тике — человек
    /// в это время работает мышью, и вернуть курсор на место программно
    /// не выходит.
    /// Закрыть открытую накладку — чтобы снять то, что под ней.
    func debugCloseOverlay() {
        router.close()
    }

    func debugExpand(seconds: TimeInterval = 6) {
        holdOpen(seconds: seconds)
    }

    /// Подержать вырез раскрытым — не для отладки, а чтобы человек видел то,
    /// что настраивает.
    ///
    /// Понадобилось ползунку прозрачности: он живёт в окне настроек, а меняет
    /// вид выреза, и до этого настройку крутили вслепую — панель раскрывается
    /// по наведению, а курсор в это время держит ползунок.
    ///
    /// Тело то же, что у отладочного раскрытия, и по той же причине: опрос
    /// положения курсора идёт десять раз в секунду и снял бы наведение
    /// на первом же тике.
    func holdOpen(seconds: TimeInterval) {
        input.hold(seconds: seconds)
        state.isHovered = true
        state.isPinnedOpen = true
        host.ignoresMouseEvents = false
        host.updateInteractiveRect()
    }

    /// Отладочный вход: открыть ближайшую запись в её приложении.
    func debugOpenFirstItem() {
        guard let item = calendar.upcoming.first else {
            DebugLog.write("отладка: впереди нет записей")
            return
        }
        openItem(item)
    }

    /// Отладочный вход: нажать по чашке в панели из сессии нечем.
    ///
    /// Идёт теми же путями, что и панель выбора, а не мимо них: отладка,
    /// которая ходит в обход настоящего кода, проверяет не то, что работает
    /// у человека.
    func debugToggleAwake() {
        if wake.isOn {
            disableAwake()
        } else {
            chooseAwakeLimit(minutes: wake.limitMinutes)
        }
    }

    /// Отладочный вход: дождаться конца получасового срока в сессии нельзя.
    func debugExpireAwake() { wake.debugExpireNow() }

    /// Отладочные входы: сочетание из скрипта не нажать, а кнопку «Пуск»
    /// в панели — тем более.
    func debugToggleTeleprompter() { toggleTeleprompter() }

    func debugToggleTeleprompterScroll() { teleprompter.toggleScrolling() }

    /// Перебирает строки вопросов телесуфлера: нажать «Ссылку» или «Очистить»
    /// в панели из сессии нечем, а увидеть их надо — они занимают место
    /// полосы управления, и разъехаться им с ней нельзя.
    func debugCycleTeleprompterPrompt() {
        switch teleprompter.prompt {
        case nil: teleprompter.askForLink()
        case .link: teleprompter.askToClear()
        case .clear: teleprompter.cancelPrompt()
        }
    }

    /// Отладочный вход: панель ответа модели без выделенного текста.
    func debugAssistant() {
        openAssistant(
            title: "Проверка потока",
            prompt: "Что такое HTTP? Ответь кратко, тремя пунктами списка, "
                + "выделяя главное."
        )
    }

    /// Отладочные входы: синтетические нажатия из отладочной сессии
    /// до Carbon не доходят — Универсальный доступ выдан только самому
    /// приложению, а не процессу, который их шлёт.
    func debugToggleClipboard() { toggleClipboard() }

    /// Панель с открытым выбором модели у первой команды.
    ///
    /// Выбор открывается нажатием по имени модели в строке, а нажать
    /// из сессии нечем. Проверять же надо именно его: с несколькими
    /// провайдерами в списке появляются одноимённые модели разных серверов,
    /// и по снимку видно, различимы ли они.
    func debugCaptureModels() {
        debugCapture()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, let command = self.visibleCommands.first(where: { $0.kind.usesModel })
            else { return }
            self.beginChoosingModel(command)
        }
    }

    /// История с подсветкой, уведённой вниз: список должен ехать за ней.
    ///
    /// Шаги по одному и с задержкой — по той же причине, что и у команд:
    /// подряд в одном такте панель ещё не построена, и прокрутка,
    /// живущая на `onChange`, не срабатывает ни разу.
    func debugClipboardHighlight(steps: Int) {
        openClipboard()
        debugStepClipboard(left: max(1, steps))
    }

    private func debugStepClipboard(left: Int) {
        guard left > 0 else {
            DebugLog.write("отладка: подсветка истории на \(clipboard.highlighted.map(String.init) ?? "нет")")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.clipboard.moveHighlight(1)
            self.debugStepClipboard(left: left - 1)
        }
    }

    /// Набивает заметками для проверки списка и поиска.
    ///
    /// Тексты нарочно разные и по-русски: поиск складывает регистр своей
    /// колонкой, и проверять его на латинице значит не проверять вовсе.
    /// Список с запросом, под который ничего не нашлось.
    ///
    /// Из сессии в поле поиска не напечатать, а состояние это отдельное:
    /// в нём стоит своя строка объяснения и своя подсказка про Enter.
    /// Проверить её иначе нечем.
    func debugMissingNote() {
        guard settings.notesEnabled else { return }
        notes.query = "зурбаган"
        router.set(.notes)
    }

    func debugFillNotes() {
        let samples = [
            "Купить билеты до Владивостока\nОбратно с пересадкой в Хабаровске",
            "Созвон в четверг, обсудить смету",
            "ПРИВЕТ, Мир — проба регистра",
            "Скидка 50% до пятницы",
            "Отпуск: что взять с собой",
        ]
        for (index, text) in samples.enumerated() {
            let attributed = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: Note.bodyFontSize),
                .foregroundColor: NSColor.white,
            ])
            notes.save(
                attributed,
                origin: index == 1 ? .assistant : .typed,
                now: Date().addingTimeInterval(-Double(index) * 3_600)
            )
        }
        DebugLog.write("заметки: набито образцов \(samples.count), всего \(notes.total)")
        openNotes()
    }

    /// Вопрос по заметкам целиком из сессии: переключатель и отправка —
    /// это нажатия, а их отсюда нет.
    /// Панель с длинным вопросом в поле — чтобы увидеть выросшее поле.
    ///
    /// Набрать его из сессии нечем: синтетические нажатия до Carbon
    /// не доходят, а поле растёт именно от набранного. Здесь текст кладётся
    /// прямо в черновик — и дальше всё идёт своим ходом: поле подрастает,
    /// панель за ним, окно вмещает.
    func debugLongQuestion() {
        draft.setMode(.model)
        // Заведомо больше потолка в пять строк: проверяется не только рост,
        // но и то, что выросшее поле упирается в потолок и прокручивается,
        // а панель при этом вписывается в окно.
        // Без `t()`: строка отладочная, её видит только разработчик —
        // как и записи журнала. Переводить её значило бы держать
        // в словарях фразу, которой в интерфейсе нет.
        draft.question = String(
            repeating: "Длинный вопрос, который заведомо не помещается в одну строку и должен растянуть поле ввода на несколько строк подряд.",
            count: 3
        )
        assistant.ask(target: NSWorkspace.shared.frontmostApplication)
        router.set(.assistant)
        takeKeyboard()
        DebugLog.write("панель: длинный вопрос в поле, знаков \(draft.question.count)")
    }

    /// Панель с набранной «@» в поле: список записей открыт.
    ///
    /// Собаку из сессии не нажать — синтетические нажатия до Carbon
    /// не доходят, — а без неё списка не увидеть ни глазами, ни снимком.
    func debugMention() {
        assistant.ask(target: NSWorkspace.shared.frontmostApplication)
        draft.setMode(.model)
        router.set(.assistant)
        takeKeyboard()
        // С задержкой, как и всё, что кладётся в свежеоткрытую панель:
        // подряд, в одном такте, панель к этому мигу ещё не построена.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.draft.question = "@"
            self.host.updateInteractiveRect()
            DebugLog.write("упоминания: список открыт, строк \(self.assistant.mentionMatches.count)")
        }
    }

    /// Весь круг с указанием живьём: выбрать первую встречу из списка «@»
    /// и попросить перенести её.
    ///
    /// Ничего не меняет: пишущее останавливается карточкой, а нажать её
    /// из сессии нечем. Так и задумано — это проверка провода, а не правка
    /// чужого календаря.
    func debugMentionRun() {
        askAssistant()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.draft.question = "@"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let first = self.assistant.mentionMatches.first(where: { $0.kind == .event }) else {
                    DebugLog.write("упоминания: встреч под рукой нет, переносить нечего")
                    return
                }
                self.pickMention(first)
                self.draft.question += t("перенеси на завтра в 15:00")
                DebugLog.write("упоминания: отладочный вопрос — \(self.draft.question)")
                self.sendDraft()
            }
        }
    }

    func debugAskNotes() {
        guard settings.ollamaEnabled else {
            DebugLog.write("заметки: Ollama выключена, спрашивать нечем")
            return
        }
        assistant.usesNotes = true
        assistant.ask(target: NSWorkspace.shared.frontmostApplication)
        router.set(.assistant)
        let question = t("О чём мои заметки? Перечисли коротко.")
        retriever.context(for: question) { [weak self] context in
            guard let context else {
                DebugLog.write("заметки: пусто, сперва notesFill")
                return
            }
            DebugLog.write("заметки: вопрос по контексту в \(context.count) симв.")
            self?.assistant.send(question, notesContext: context)
        }
    }

    func debugUseClipboardSlot(_ index: Int) {
        guard let entry = clipboard.entry(atSlot: index) else {
            DebugLog.write("отладка: в буфере нет записи \(index + 1)")
            return
        }
        useClipboard(entry)
    }

    func debugPurr(seconds: TimeInterval = 4) {
        purr.run(seconds: seconds)
    }

    /// Снимок самого острова — единственный способ увидеть его вёрстку
    /// из отладочной сессии.
    func snapshot() {
        host.snapshot()
    }

    func snapshotMirror() {
        host.snapshotInactive(home: screens.home)
    }

    /// Отладочный путь: добавляет к списку напоминание со сроком через
    /// указанное число секунд и скармливает его планировщику.
    func scheduleTestReminder(in seconds: TimeInterval) {
        let item = CalendarItem(
            id: "debug-reminder",
            title: "Проверка напоминания",
            start: Date().addingTimeInterval(seconds),
            end: nil,
            isAllDay: false,
            source: .reminder,
            link: nil,
            colorComponents: [1.0, 0.6, 0.2]
        )
        DebugLog.write("отладка: напоминание через \(Int(seconds)) с")
        alerts.update(items: calendar.upcoming + [item])
    }
}
