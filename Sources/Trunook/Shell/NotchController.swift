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
    let activities = ActivityCenter()
    let battery = BatteryMonitor()
    let calendar = CalendarService()
    let things = ThingsService()
    let commands = CommandRunner()
    let meeting = MeetingService()
    let clipboard = ClipboardService()
    let assistant = AssistantSession()
    let weather = WeatherService()
    let shelf = ShelfStore()
    let timer = TimerService()
    let monitor = MonitorService()

    private let alerts = EventAlertScheduler()
    /// Отдельное окно приёма файлов: сам вырез принимать их не может,
    /// он живёт выше уровня перетаскивания. Устройство — в `ShelfDropWindow`.
    private let shelfDrop = ShelfDropWindow()

    /// Вызывается кнопкой настроек в раскрытой панели.
    var onOpenSettings: (() -> Void)?

    private let settings: Settings
    private let state = NotchState()

    private let host = NotchWindowHost()
    private let router: OverlayRouter
    private let input: NotchInput
    private let purr: PurrEffects
    private let chime = ChimePlayer()

    private var swipeResetTimer: Timer?
    private var calendarObservation: AnyCancellable?
    private var thingsObservation: AnyCancellable?

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
        router = OverlayRouter(state: state, host: host)
        input = NotchInput(state: state, settings: settings, host: host)
        purr = PurrEffects(state: state)
    }

    func start() {
        installShelf()
        installHost()
        installInput()
        // Окно строится после того, как хост узнал, из чего собирать вёрстку.
        host.rebuild()
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
        purr.shutdown()
        chime.shutdown()
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
        alerts.stop()
        calendarObservation = nil
        thingsObservation = nil
        shelfDrop.hide()
        host.hide()
    }

    @objc private func screensChanged() {
        host.rebuild()
    }

    // MARK: - Сборка узлов

    private func installHost() {
        host.makeRoot = { [weak self] metrics in self?.makeRootView(metrics: metrics) }
        host.contentSize = { [weak self] metrics in self?.notchSnapshot.size(metrics: metrics) ?? .zero }
        host.onRightClick = { [weak self] in self?.openHub() }
        host.onRebuild = { [weak self] geometry, metrics in
            self?.rebuildShelfDrop(geometry: geometry, metrics: metrics)
        }
        router.onChange = { [weak self] overlay in self?.applyOverlay(overlay) }
    }

    private func installInput() {
        input.onHoverChanged = { [weak self] hovered in self?.setHovered(hovered) }
        input.onExpand = { [weak self] in self?.expandPanel() }
        input.onCollapse = { [weak self] in self?.collapsePanel() }
        input.onSwipe = { [weak self] direction in self?.performSwipe(direction) }
        input.onOverlayHover = { [weak self] location in self?.router.updateHover(at: location) }
        input.onDismissOverlay = { [weak self] in self?.router.close() }
        // Зона приёма файлов оживает только пока что-то тащат: в покое она
        // прозрачна для мыши и не ест нажатия по тому, что под чёлкой.
        input.onDragChanged = { [weak self] dragging in self?.shelfDrop.isArmed = dragging }
        // То, что пересчитывается по времени, а не по событию.
        input.onTick = { [weak self] in
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
        commands.onAssistantPrompt = { [weak self] title, prompt in
            self?.openAssistant(title: title, prompt: prompt)
        }
        installHotKeys()

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
        meeting.onCopiedLink = { [weak self] _ in
            self?.activities.present(.command(text: t("Ссылка встречи в буфере"), state: .done))
        }

        clipboard.onCopy = { [weak self] entry in
            guard let self, self.settings.clipboardShowsChip else { return }
            // Пока история открыта, плашка не нужна: список и так обновился
            // на глазах, а всплыла бы она уже после закрытия панели.
            guard self.state.overlay == nil else { return }
            self.activities.present(.clipboard(text: entry.oneLine, kind: entry.kind))
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

        weather.onAlert = { [weak self] text, symbol in
            self?.activities.present(.weather(text: text, symbol: symbol))
        }
        weather.start()

        calendar.start()
        things.start()
        meeting.start()
        clipboard.start()
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

        if let menu = settings.menuHotKey {
            HotKeyCenter.shared.register(menu, name: "меню команд") { [weak self] in
                guard self?.settings.quickCommandsEnabled == true else { return }
                self?.router.toggle(.commands)
            }
        }

        if settings.clipboardEnabled, let clipboardKey = settings.clipboardHotKey {
            HotKeyCenter.shared.register(clipboardKey, name: "история буфера") { [weak self] in
                self?.router.toggle(.clipboard)
            }
        }

        if settings.monitorEnabled, let monitorKey = settings.monitorHotKey {
            HotKeyCenter.shared.register(monitorKey, name: "нагрузка") { [weak self] in
                self?.toggleMonitor()
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
                guard let self, self.settings.quickCommandsEnabled else { return }
                guard let current = self.settings.quickCommands.first(where: { $0.id == id })
                else { return }
                self.closeCommands()
                self.run(current)
            }
        }
    }

    /// Проверка кодировки на коротком запросе: логируем и то, что отправили,
    /// и то, что вернулось, побайтово.
    func debugOllamaEcho() {
        let prompt = "Повтори дословно: Привет, мир"
        DebugLog.write("ollama: шлём «\(prompt)», байт \(prompt.utf8.count)")
        OllamaClient().generate(prompt: prompt) { result in
            switch result {
            case let .success(answer):
                DebugLog.write("ollama: ответ «\(answer)»")
                DebugLog.write("ollama: байт \(answer.utf8.count), символов \(answer.count)")
            case let .failure(error):
                DebugLog.write("ollama: ошибка \(error.localizedDescription)")
            }
        }
    }

    /// Переход к командам из раскрытой панели. В отличие от клавиши —
    /// не переключатель: панель уже открыта, и «спрятать» здесь означает
    /// вернуться назад, для чего есть своя кнопка.
    func openCommands() {
        router.set(.commands)
    }

    func closeCommands() {
        guard state.isCommandsOpen else { return }
        router.close()
    }

    /// Отладочные входы: горячую клавишу из скрипта не нажать.
    func debugToggleCommands() { router.toggle(.commands) }

    func debugRunSlot(_ index: Int) {
        guard let command = settings.quickCommands.first(where: { $0.id == index }) else { return }
        run(command)
    }

    private func run(_ command: QuickCommand) {
        router.close()
        // Меню закрывается до запуска: команда может читать выделенный текст,
        // а для этого активным должно остаться прежнее приложение.
        commands.run(command)
    }

    // MARK: - Накладки

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
        // Мониторинг опрашивает систему только пока он на экране: иначе
        // он сам стал бы той нагрузкой, которую показывает.
        overlay == .monitor ? monitor.start() : monitor.stop()
        // Пока полка на экране, зона приёма держится раскрытой: на открытую
        // полку докладывают файлы, и целиться в полоску по чёлке при этом
        // было бы издевательством.
        shelfDrop.isPinnedOpen = overlay == .shelf
        updateWindowInteractivity()
        host.updateInteractiveRect()
    }

    /// Окно ловит мышь, только когда на экране есть во что попадать.
    ///
    /// Плашка копирования тоже считается: по ней нажимают, чтобы открыть
    /// историю, а прозрачное для нажатий окно этого не позволило бы.
    private func updateWindowInteractivity() {
        host.ignoresMouseEvents = state.overlay == nil
            && !state.isHovered
            && activities.current?.isInteractive != true
            // По полоске идущего таймера нажимают, чтобы открыть его панель.
            // Прозрачное для нажатий окно этого не позволило бы.
            && timerChip == nil
    }

    /// Полоска идущего таймера — или её отсутствие. Спрашивают и расчёт
    /// состояния, и проверка нажатий, и разойтись им нельзя.
    private var timerChip: TimerChip? {
        settings.timerEnabled ? timer.chip : nil
    }

    /// Состояние выреза глазами контроллера. Тот же расчёт, что и в вёрстке:
    /// зона нажатий обязана совпадать с нарисованным, иначе панель видно,
    /// а нажать по ней нельзя — на этом уже спотыкались.
    private var notchSnapshot: NotchSnapshot {
        NotchInputs(
            overlay: state.overlay,
            swipe: state.swipe,
            isHovered: state.isHovered,
            isPinnedOpen: state.isPinnedOpen,
            chip: state.chipItem,
            timerChip: timerChip,
            activity: activities.current,
            track: music.nowPlaying,
            events: calendar.upcoming.startingTogether(limit: NotchMetrics.maxVisibleEvents),
            taskCount: things.todayTitles.count,
            meetingActions: meeting.availableActions.count,
            clipboardRows: clipboard.entries.count,
            assistantAnswer: assistant.answer,
            assistantIsStreaming: assistant.isStreaming,
            shelfCount: shelf.items.count,
            hubCount: HubEntry.count
        ).resolve()
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
        guard state.isHovered, !state.isPinnedOpen else { return }
        state.isPinnedOpen = true
        DebugLog.write("панель раскрыта полностью")
        Haptics.tap(.levelChange)
        host.updateInteractiveRect()
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
    func openAssistant(title: String, prompt: String) {
        assistant.start(
            title: title,
            prompt: prompt,
            target: NSWorkspace.shared.frontmostApplication
        )
        router.set(.assistant)
    }

    /// Кнопка «спросить» на главной панели. В отличие от команды здесь нет
    /// ни промта, ни выделенного текста — только пустое поле и курсор в нём.
    func askAssistant() {
        guard settings.ollamaEnabled else { return }
        assistant.ask(target: NSWorkspace.shared.frontmostApplication)
        router.set(.assistant)
        // Поле ввода требует клавиатуры, а панель по умолчанию фокус
        // не забирает: забираем явно, как и для встречного вопроса.
        composeFollowUp()
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

    /// Встречный вопрос требует клавиатуры, а панель по умолчанию фокус
    /// не забирает. Забираем явно — и возвращаем его обратно при закрытии.
    private func composeFollowUp() {
        assistant.isComposing = true
        NSApp.activate(ignoringOtherApps: true)
        host.makeKey()
    }

    func closeAssistant() {
        let target = assistant.target
        let tookFocus = assistant.isComposing
        assistant.reset()
        router.close()
        // Фокус возвращаем только если сами его забирали: без этого
        // безобидное закрытие панели дёргало бы чужие окна.
        if tookFocus, let target, !target.isActive {
            target.activate()
        }
    }

    // MARK: - Буфер обмена

    func openClipboard() {
        router.set(.clipboard)
    }

    func useClipboard(_ entry: ClipboardEntry) {
        // Панель закрывается до вставки: она не забирает фокус, но остаётся
        // поверх, а вставлять человек собирается в то, что под ней.
        router.close()
        clipboard.use(entry)
    }

    // MARK: - Полка

    /// Связывает зону приёма с вырезом. Ставится один раз: само окно приёма
    /// переживает перестройку геометрии, меняются только его размеры.
    private func installShelf() {
        shelfDrop.onEnter = { [weak self] in
            guard let self else { return }
            // Файлы ведут над чёлкой — раскрываем полку, чтобы человек видел,
            // куда роняет, и мог доложить к уже лежащему.
            self.shelf.pruneMissing()
            self.state.isShelfDropTarget = true
            self.router.set(.shelf)
        }
        shelfDrop.onExit = { [weak self] in
            // Полку не закрываем: человек мог обвести файл мимо панели
            // и вести обратно. Закроется она как все накладки — по уходу
            // курсора за её границы.
            self?.state.isShelfDropTarget = false
        }
        shelfDrop.onDrop = { [weak self] urls in
            guard let self else { return false }
            self.state.isShelfDropTarget = false
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

    /// Правая кнопка по вырезу. Возможностей стало больше, чем человек
    /// удержит в голове, и до половины из них без сочетания было не добраться.
    func openHub() {
        router.toggle(.hub)
    }

    /// Возврат из меню в раскрытую панель. Накладка закрывается, а панель
    /// фиксируется раскрытой — иначе она схлопнулась бы в мини-вид, ведь
    /// нажатия, которое её удерживало, не было.
    private func openExpandedFromHub() {
        router.close()
        state.isPinnedOpen = true
        host.updateInteractiveRect()
    }

    // MARK: - Записи и ссылки

    /// Открывает запись в её приложении: встречу — в Календаре, напоминание —
    /// в Напоминаниях, задачу — списком на сегодня в Things.
    func openItem(_ item: CalendarItem) {
        guard let url = item.appURL else {
            ThingsService.openToday()
            return
        }
        DebugLog.write("открываю запись «\(item.title)» в \(url.scheme ?? "?")")
        NSWorkspace.shared.open(url)
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

    private func makeRootView(metrics: NotchMetrics) -> NotchView {
        NotchView(
            state: state,
            activities: activities,
            music: music,
            calendar: calendar,
            things: things,
            meeting: meeting,
            clipboard: clipboard,
            assistant: assistant,
            weather: weather,
            shelf: shelf,
            timer: timer,
            monitor: monitor,
            settings: settings,
            metrics: metrics,
            onTap: { [weak self] in self?.expandPanel() },
            onOpenSettings: { [weak self] in
                self?.closeCommands()
                self?.onOpenSettings?()
            },
            onJoin: { [weak self] url in self?.join(url) },
            onRunCommand: { [weak self] command in self?.run(command) },
            onCopyLink: { [weak self] url in self?.copyLink(url) },
            onOpenItem: { [weak self] item in self?.openItem(item) },
            onOpenCommands: { [weak self] in self?.openCommands() },
            onCloseCommands: { [weak self] in self?.closeCommands() },
            onCloseOverlay: { [weak self] in self?.router.close() },
            onOpenClipboard: { [weak self] in self?.openClipboard() },
            onUseClipboard: { [weak self] entry in self?.useClipboard(entry) },
            onDeleteClipboard: { [weak self] entry in self?.clipboard.delete(entry) },
            onClearClipboard: { [weak self] in self?.clipboard.clear() },
            onCopyAnswer: { [weak self] in self?.copyAnswer() },
            onPasteAnswer: { [weak self] in self?.pasteAnswer() },
            onComposeFollowUp: { [weak self] in self?.composeFollowUp() },
            onSendFollowUp: { [weak self] text in self?.assistant.follow(up: text) },
            onCloseAssistant: { [weak self] in self?.closeAssistant() },
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
            onDismissActivity: { [weak self] in self?.dismissShelfChip() },
            onOpenHub: { [weak self] in self?.openHub() },
            onOpenExpanded: { [weak self] in self?.openExpandedFromHub() },
            onAskAssistant: { [weak self] in self?.askAssistant() }
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
    func debugExpand(seconds: TimeInterval = 6) {
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
    func debugToggleClipboard() { router.toggle(.clipboard) }

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
