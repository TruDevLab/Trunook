import TrunookXPC
import AppKit
import SwiftUI
import Combine

/// Держит окно над вырезом, решает когда его раскрывать и связывает
/// источники событий с представлением.
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

    private let alerts = EventAlertScheduler()
    /// Отдельное окно приёма файлов: сам вырез принимать их не может,
    /// он живёт выше уровня перетаскивания. Устройство — в `ShelfDropWindow`.
    private let shelfDrop = ShelfDropWindow()

    /// Вызывается кнопкой настроек в раскрытой панели.
    var onOpenSettings: (() -> Void)?

    private let settings: Settings
    private let state = NotchState()

    private var window: NotchWindow?
    private var hostingView: NotchHostingView<NotchView>?
    private var geometry: NotchGeometry?
    private var metrics: NotchMetrics?

    private let petting = PettingDetector()
    private let purr = PurrPlayer()

    private var monitors: [Any] = []
    private var pollTimer: Timer?
    private var swipeResetTimer: Timer?
    private var purrHapticTimer: Timer?
    private var trembleTimer: Timer?
    private var calendarObservation: AnyCancellable?
    private var thingsObservation: AnyCancellable?

    /// Гистерезис: раскрываем по узкой зоне выреза, а закрываем только когда
    /// курсор ушёл за пределы всей раскрытой панели. Иначе панель дёргается.
    private var openTriggerRect: CGRect = .zero
    private var closeTriggerRect: CGRect = .zero

    // Накопитель горизонтального смещения для свайпа двумя пальцами.
    private var swipeOffset: CGFloat = 0
    /// Накопитель вертикального: им панель вытягивают из мини-вида.
    private var pullOffset: CGFloat = 0
    private var swipeReadyAt = Date.distantPast
    /// Когда последний раз приходило событие прокрутки: по молчанию гасим
    /// незавершённый жест.
    private var lastSwipeEventAt = Date.distantPast

    /// Накладка закрывается по уходу курсора, но только после того, как он
    /// в неё хоть раз зашёл: вызванная клавишей иначе схлопнулась бы сразу,
    /// ведь курсор в этот момент где угодно.
    private var overlayCursorEntered = false

    /// До какого момента отладочное раскрытие держится вопреки курсору.
    private var debugHoldUntil = Date.distantPast

    /// Плашку полки убрали крестиком. Держится до следующего файла:
    /// человек уже знает, что на полке лежит.
    private var shelfChipDismissed = false

    /// Порог срабатывания свайпа в точках и пауза между переключениями.
    private static let swipeThreshold: CGFloat = 45
    private static let swipeCooldown: TimeInterval = 0.6
    /// Через сколько молчания незавершённый свайп считается брошенным.
    private static let swipeIdleTimeout: TimeInterval = 0.25

    /// Порог вытягивания панели вниз. Ниже, чем у переключения трека:
    /// раскрытие обратимо — достаточно увести курсор, — а промахнуться
    /// мимо трека дороже.
    private static let pullThreshold: CGFloat = 28

    /// На сколько точек зона приёма спускается ниже чёлки.
    ///
    /// Не запас на промах, а обход системного жеста: курсор, задержанный
    /// у верхней кромки во время перетаскивания, открывает Mission Control.
    /// Отменить жест нечем, поэтому файл принимается заметно ниже кромки —
    /// вести к самому краю не нужно вовсе.
    ///
    /// Платой идут нажатия, съеденные в этой полосе под чёлкой: окно,
    /// принимающее файлы, не может быть прозрачным для мыши.
    private static let dropStripReach: CGFloat = 96

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    func start() {
        installShelf()
        rebuild()
        installMouseTracking()
        installPetting()
        connectSources()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        swipeResetTimer?.invalidate()
        swipeResetTimer = nil
        stopPurrHaptics()
        stopTremble()
        purr.shutdown()
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        HotKeyCenter.shared.stop()
        battery.stop()
        music.stop()
        calendar.stop()
        things.stop()
        meeting.stop()
        clipboard.stop()
        weather.stop()
        alerts.stop()
        calendarObservation = nil
        thingsObservation = nil
        shelfDrop.hide()
        window?.orderOut(nil)
        window = nil
    }

    @objc private func screensChanged() {
        rebuild()
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
                self?.toggleCommands()
            }
        }

        if settings.clipboardEnabled, let clipboardKey = settings.clipboardHotKey {
            HotKeyCenter.shared.register(clipboardKey, name: "история буфера") { [weak self] in
                self?.toggleClipboard()
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
        guard !state.isCommandsOpen else { return }
        toggleCommands()
    }

    /// Отладочные входы: горячую клавишу из скрипта не нажать.
    func debugToggleCommands() { toggleCommands() }

    func debugRunSlot(_ index: Int) {
        guard let command = settings.quickCommands.first(where: { $0.id == index }) else { return }
        run(command)
    }

    private func toggleCommands() {
        setOverlay(state.isCommandsOpen ? nil : .commands)
    }

    /// Единая точка смены накладки: меню команд и история буфера занимают
    /// одно место, и открытие одного обязано закрывать другое.
    private func setOverlay(_ overlay: NotchState.Overlay?) {
        guard state.overlay != overlay else { return }
        state.overlay = overlay
        overlayCursorEntered = false
        DebugLog.write("накладка: \(overlay.map(Self.name(of:)) ?? "закрыта")")
        if overlay != nil {
            Haptics.tap()
            activities.dismiss()
        } else {
            // Панель ушла — напоминание о полке возвращается на её место.
            refreshShelfChip()
        }
        // Пока полка на экране, зона приёма держится раскрытой: на открытую
        // полку докладывают файлы, и целиться в полоску по чёлке при этом
        // было бы издевательством.
        shelfDrop.isPinnedOpen = overlay == .shelf
        updateWindowInteractivity()
        updateInteractiveRect()
    }

    private static func name(of overlay: NotchState.Overlay) -> String {
        switch overlay {
        case .commands: return "меню команд"
        case .clipboard: return "история буфера"
        case .assistant: return "ответ модели"
        case .shelf: return "полка"
        case .hub: return "меню функций"
        }
    }

    /// Окно ловит мышь, только когда на экране есть во что попадать.
    ///
    /// Плашка копирования тоже считается: по ней нажимают, чтобы открыть
    /// историю, а прозрачное для нажатий окно этого не позволило бы.
    private func updateWindowInteractivity() {
        window?.ignoresMouseEvents = state.overlay == nil
            && !state.isHovered
            && activities.current?.isInteractive != true
    }

    /// Курсор зашёл в накладку и вышел — закрываем.
    private func updateOverlayHover(at location: CGPoint) {
        guard let window else { return }

        // Полка живёт по другому правилу, чем остальные накладки: она
        // закрывается щелчком мимо себя, а не уходом курсора. С ней работают
        // руками — тащат файлы внутрь и наружу, — и курсор при этом заведомо
        // выходит за её границы. Закрытие по уходу отнимало бы её ровно
        // в тот момент, ради которого она открыта.
        //
        // Щелчок мимо ловит глобальный монитор нажатий: он срабатывает только
        // на события, ушедшие в чужое приложение, то есть ровно на «мимо».
        guard !state.isShelfOpen else { return }

        let inside = overlayRect(in: window).contains(location)
        if inside {
            overlayCursorEntered = true
        } else if overlayCursorEntered {
            setOverlay(nil)
        }
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
            activity: activities.current,
            track: music.nowPlaying,
            event: calendar.upcoming.first,
            taskCount: things.todayTitles.count,
            meetingActions: meeting.availableActions.count,
            clipboardRows: clipboard.entries.count,
            assistantAnswer: assistant.answer,
            assistantIsStreaming: assistant.isStreaming,
            shelfCount: shelf.items.count,
            hubCount: HubEntry.count
        ).resolve()
    }

    /// Прямоугольник накладки в координатах экрана.
    private func overlayRect(in window: NotchWindow) -> CGRect {
        guard let metrics, state.overlay != nil else { return .zero }
        let size = notchSnapshot.size(metrics: metrics)
        let frame = window.frame
        return CGRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    func closeCommands() {
        guard state.isCommandsOpen else { return }
        setOverlay(nil)
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
        setOverlay(.assistant)
    }

    /// Кнопка «спросить» на главной панели. В отличие от команды здесь нет
    /// ни промта, ни выделенного текста — только пустое поле и курсор в нём.
    func askAssistant() {
        guard settings.ollamaEnabled else { return }
        assistant.ask(target: NSWorkspace.shared.frontmostApplication)
        setOverlay(.assistant)
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
    fileprivate func composeFollowUp() {
        assistant.isComposing = true
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func closeAssistant() {
        let target = assistant.target
        let tookFocus = assistant.isComposing
        assistant.reset()
        setOverlay(nil)
        // Фокус возвращаем только если сами его забирали: без этого
        // безобидное закрытие панели дёргало бы чужие окна.
        if tookFocus, let target, !target.isActive {
            target.activate()
        }
    }

    // MARK: - Буфер обмена

    func openClipboard() {
        setOverlay(.clipboard)
    }

    private func toggleClipboard() {
        setOverlay(state.isClipboardOpen ? nil : .clipboard)
    }

    func useClipboard(_ entry: ClipboardEntry) {
        // Панель закрывается до вставки: она не забирает фокус, но остаётся
        // поверх, а вставлять человек собирается в то, что под ней.
        setOverlay(nil)
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
            self.setOverlay(.shelf)
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
            self.setOverlay(.shelf)
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

    // MARK: - Меню всех функций

    /// Правая кнопка по вырезу. Возможностей стало больше, чем человек
    /// удержит в голове, и до половины из них без сочетания было не добраться.
    func openHub() {
        setOverlay(state.isHubOpen ? nil : .hub)
    }

    /// Возврат из меню в раскрытую панель. Накладка закрывается, а панель
    /// фиксируется раскрытой — иначе она схлопнулась бы в мини-вид, ведь
    /// нажатия, которое её удерживало, не было.
    private func openExpandedFromHub() {
        setOverlay(nil)
        state.isPinnedOpen = true
        updateInteractiveRect()
    }

    func openShelf() {
        shelf.pruneMissing()
        setOverlay(.shelf)
    }

    private func toggleShelf() {
        guard settings.shelfEnabled else { return }
        state.isShelfOpen ? setOverlay(nil) : openShelf()
    }

    func removeFromShelf(_ item: ShelfItem) {
        shelf.remove(item)
        // Опустевшая полка закрывается сама: пустая панель поверх чужого окна
        // висела бы просто так.
        if shelf.isEmpty { setOverlay(nil) } else { refreshShelfChip() }
    }

    func openShelfItem(_ item: ShelfItem) {
        setOverlay(nil)
        NSWorkspace.shared.open(item.url)
    }

    func revealShelfItem(_ item: ShelfItem) {
        setOverlay(nil)
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func clearShelf() {
        shelf.clear()
        setOverlay(nil)
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

    /// Отладочный вход: набить полку и показать её. Настоящее перетаскивание
    /// из отладочной сессии не изобразить — синтетические события мыши
    /// до системы не доходят, — а вёрстку посмотреть надо.
    func debugFillShelf() {
        // Повторный вызов закрывает полку: щёлкнуть мимо неё, а только этим
        // она теперь и закрывается, из отладочной сессии нечем.
        if state.isShelfOpen {
            setOverlay(nil)
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
        debugHoldUntil = Date().addingTimeInterval(seconds)
        state.isHovered = true
        state.isPinnedOpen = true
        window?.ignoresMouseEvents = false
        updateInteractiveRect()
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
    func debugToggleClipboard() { toggleClipboard() }

    func debugUseClipboardSlot(_ index: Int) {
        guard let entry = clipboard.entry(atSlot: index) else {
            DebugLog.write("отладка: в буфере нет записи \(index + 1)")
            return
        }
        useClipboard(entry)
    }

    /// Снимок самого острова — единственный способ увидеть его вёрстку
    /// из отладочной сессии.
    func snapshot() {
        WindowSnapshot.write(window, named: "notch")
    }

    private func run(_ command: QuickCommand) {
        setOverlay(nil)
        // Меню закрывается до запуска: команда может читать выделенный текст,
        // а для этого активным должно остаться прежнее приложение.
        commands.run(command)
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

    // MARK: - Окно

    private func rebuild() {
        guard let geometry = NotchGeometry.current() else {
            window?.orderOut(nil)
            window = nil
            return
        }
        self.geometry = geometry

        let metrics = NotchMetrics(
            notchWidth: geometry.notchRect.width,
            notchHeight: geometry.notchRect.height
        )
        self.metrics = metrics

        let frame = geometry.windowFrame(contentSize: metrics.windowSize)
        openTriggerRect = geometry.notchRect.insetBy(dx: -4, dy: 0)
        closeTriggerRect = frame

        let window = self.window ?? makeWindow(frame: frame, metrics: metrics)
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        self.window = window
        updateInteractiveRect()
        rebuildShelfDrop(geometry: geometry, metrics: metrics)

        DebugLog.write("геометрия: \(geometry.description)")
        DebugLog.write("окно \(NSStringFromRect(frame)), зона раскрытия \(NSStringFromRect(openTriggerRect))")

        // Плашка события не должна оказаться уже свёрнутой формы —
        // иначе остров выглядит меньше самого выреза.
        let shortest = ActivityLayout(text: "Низкий заряд", trailing: "20%", minimumWidth: metrics.closed.width)
        DebugLog.write(
            "ширины: свёрнуто \(Int(metrics.closed.width)), "
            + "плашка минимум \(Int(shortest.panelWidth)), "
            + "раскрыто \(Int(metrics.expanded(extraHeight: 0).width)), "
            + "отсчёт \(Int(ChipView.width(metrics: metrics))) при окне \(Int(metrics.windowSize.width))"
        )
    }

    private func makeWindow(frame: CGRect, metrics: NotchMetrics) -> NotchWindow {
        let window = NotchWindow(contentRect: frame)
        let root = NotchView(
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
            settings: settings,
            metrics: metrics,
            onTap: { [weak self] in self?.handleTap() },
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
            onDismissActivity: { [weak self] in self?.dismissShelfChip() },
            onOpenHub: { [weak self] in self?.openHub() },
            onOpenExpanded: { [weak self] in self?.openExpandedFromHub() },
            onAskAssistant: { [weak self] in self?.askAssistant() }
        )
        let hosting = NotchHostingView(rootView: root)
        hosting.onRightClick = { [weak self] in self?.openHub() }
        hosting.frame = CGRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        hostingView = hosting
        return window
    }

    /// Окно всегда максимального размера, а форма занимает лишь его часть.
    /// Сообщаем подложке, где именно принимать нажатия, чтобы прозрачные
    /// углы окна не съедали клики по меню-бару.
    private func updateInteractiveRect() {
        guard let hostingView, let metrics else { return }
        let size = notchSnapshot.size(metrics: metrics)
        // Метод вызывается десять раз в секунду — выходим молча, если ничего
        // не поменялось, иначе журнал захлебнётся.
        guard size != hostingView.visibleSize else { return }
        hostingView.visibleSize = size
        DebugLog.write("зона нажатий: \(Int(size.width))×\(Int(size.height))")
    }

    // MARK: - Наведение и нажатие

    private func installMouseTracking() {
        // Опрос позиции — основной механизм. Глобальные мониторы событий молчат
        // в нескольких важных случаях: пока открыто меню другого приложения,
        // при перетаскивании файлов и при программном перемещении курсора.
        // Для оверлея, живущего под самой кромкой экрана, это заметные дыры.
        // Десять опросов в секунду сводятся к сравнению точки с двумя
        // прямоугольниками — на энергопотреблении не сказывается.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.handleMouse(at: NSEvent.mouseLocation)
            self.expirePendingSwipe()
            self.updateCountdown()
            self.updateInteractiveRect()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        // Мониторы оставляем ради мгновенной реакции между тиками опроса.
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.handleMouse(at: NSEvent.mouseLocation)
        }) {
            monitors.append(global)
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handleMouse(at: NSEvent.mouseLocation)
            return event
        }) {
            monitors.append(local)
        }

        // Свайп двумя пальцами приходит обычными событиями прокрутки:
        // отдельный тип .swipe система шлёт только когда включён системный
        // жест «Смахивание между страницами», а он есть не у всех.
        // Меню команд закрывается по Esc. Монитор локальный: панель к этому
        // моменту уже приняла фокус, чтобы принимать нажатия.
        // Нажатие мимо меню закрывает его — как поступает любое меню системы.
        if let outside = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] _ in self?.setOverlay(nil) }
        ) {
            monitors.append(outside)
        }

        if let keys = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            guard event.keyCode == 53, self?.state.overlay != nil else { return event }
            self?.setOverlay(nil)
            return nil
        }) {
            monitors.append(keys)
        }

        if let scroll = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel], handler: { [weak self] event in
            self?.handleScroll(event)
            return event
        }) {
            monitors.append(scroll)
        }
    }

    private func handleMouse(at location: CGPoint) {
        guard Date() >= debugHoldUntil else { return }
        if state.overlay != nil {
            updateOverlayHover(at: location)
            petting.reset()
            return
        }
        guard settings.expandOnHover else {
            if state.isHovered { setHovered(false) }
            petting.reset()
            return
        }
        let inside = state.isHovered
            ? closeTriggerRect.contains(location)
            : openTriggerRect.contains(location)
        if inside != state.isHovered { setHovered(inside) }
        // Поглаживание проверяется на каждом движении, а не только на смене
        // состояния: пока курсор ходит внутри выреза, наведение не меняется.
        updatePetting(at: location)
    }

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
            swipeOffset = 0
        }
        updateInteractiveRect()
    }

    /// Нажатие только раскрывает — свернуть можно уводом курсора.
    ///
    /// Переключение туда-обратно было бы опаснее: в раскрытом виде нажатие
    /// по кнопке перемотки рискует продублироваться нажатием по панели,
    /// и трек переключался бы вместе со схлопыванием.
    private func handleTap() {
        guard state.isHovered, !state.isPinnedOpen else { return }
        state.isPinnedOpen = true
        DebugLog.write("панель раскрыта полностью")
        Haptics.tap(.levelChange)
        updateInteractiveRect()
    }

    // MARK: - Поглаживание

    private func installPetting() {
        petting.onStart = { [weak self] in
            guard let self else { return }
            DebugLog.write("вырез гладят — мурчим")
            self.state.isPurring = true
            self.purr.start()
            self.startPurrHaptics()
            self.startTremble()
        }
        petting.onStop = { [weak self] in
            guard let self else { return }
            DebugLog.write("гладить перестали")
            self.state.isPurring = false
            self.purr.stop()
            self.stopPurrHaptics()
            self.stopTremble()
        }
    }

    /// Поглаживание считается только в мини-виде. В раскрытой панели курсор
    /// ходит между кнопками перемотки, и такие движения не должны будить кота;
    /// в меню команд — тем более.
    private func updatePetting(at location: CGPoint) {
        guard settings.purrEnabled,
              state.isHovered,
              !state.isPinnedOpen,
              !state.isCommandsOpen,
              let geometry
        else {
            petting.reset()
            return
        }

        // Начать поглаживание можно только на самой чёлке, а продолжать —
        // в любом месте раскрытого мини-вида. Строгая зона высотой в саму
        // чёлку рвала мурчание почти сразу: рука на развороте выходит
        // и вбок, и вниз, а каждый выход требовал набирать четыре хода
        // заново — со стороны выглядело как «сработало один раз».
        let region = petting.isPurring ? closeTriggerRect : startPettingRect(geometry)
        guard region.contains(location) else {
            petting.reset()
            return
        }
        petting.update(x: location.x)
    }

    /// Зона, в которой поглаживание начинается: чёлка с запасом по бокам
    /// и вниз на высоту мини-вида.
    private func startPettingRect(_ geometry: NotchGeometry) -> CGRect {
        let notch = geometry.notchRect
        let depth = notch.height + 28
        return CGRect(
            x: notch.minX - 34,
            y: notch.maxY - depth,
            width: notch.width + 68,
            height: depth
        )
    }

    /// Настоящее мурчание — это частые толчки, а не ровный гул. Виброотклик
    /// системы такой частоты не даёт, поэтому берём самый мягкий рисунок
    /// и повторяем его так часто, как он успевает отрабатывать.
    private func startPurrHaptics() {
        guard purrHapticTimer == nil else { return }
        Haptics.tap()
        let timer = Timer(timeInterval: 0.16, repeats: true) { _ in
            Haptics.tap()
        }
        RunLoop.main.add(timer, forMode: .common)
        purrHapticTimer = timer
    }

    private func stopPurrHaptics() {
        purrHapticTimer?.invalidate()
        purrHapticTimer = nil
    }

    /// Дрожь острова. Частоты по осям намеренно разные и не кратные:
    /// одинаковые дали бы ровное качание по диагонали, а нужно живое
    /// подрагивание.
    private func startTremble() {
        guard trembleTimer == nil else { return }
        let started = Date()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let time = Date().timeIntervalSince(started)
            // Вниз остров не уходит никогда: окно приклеено к верхней кромке
            // экрана, и смещение вниз открывает под чёлкой незакрашенную
            // полосу рабочего стола. Вверх уезжать безопасно — там экран
            // просто обрезает.
            self.state.tremble = CGSize(
                width: 0.7 * sin(time * 2 * .pi * 9),
                height: -0.45 + 0.45 * sin(time * 2 * .pi * 11.3 + 0.9)
            )
        }
        RunLoop.main.add(timer, forMode: .common)
        trembleTimer = timer
    }

    private func stopTremble() {
        trembleTimer?.invalidate()
        trembleTimer = nil
        state.tremble = .zero
    }

    /// Отладочный вход: поглаживание курсором из скрипта не изобразить,
    /// а слушать звук и щупать вибрацию нужно.
    func debugPurr(seconds: TimeInterval = 4) {
        DebugLog.write("отладка: мурчим \(Int(seconds)) с")
        state.isPurring = true
        purr.start()
        startPurrHaptics()
        startTremble()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.state.isPurring = false
            self?.purr.stop()
            self?.stopPurrHaptics()
            self?.stopTremble()
        }
    }

    // MARK: - Свайп двумя пальцами

    private func handleScroll(_ event: NSEvent) {
        guard state.isHovered, state.overlay == nil else { return }

        // Начало нового жеста обнуляет накопители, иначе остаток от прошлого
        // свайпа сработал бы раньше времени.
        if event.phase == .began || event.phase == .mayBegin {
            resetPendingSwipe()
            pullOffset = 0
        }

        // Поперёк — переключение трека, вниз — раскрытие панели. Решает
        // преобладающая ось: диагональные движения иначе делали бы и то,
        // и другое разом.
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            handleTrackSwipe(event)
        } else {
            handlePull(event)
        }
    }

    private func handleTrackSwipe(_ event: NSEvent) {
        guard settings.musicEnabled else { return }

        // Инерцию после отрыва пальцев не считаем вовсе. Трекпад досылает
        // events ещё полсекунды, и накопитель успевал перевалить порог
        // второй раз: значок появлялся, гас и появлялся снова.
        guard event.momentumPhase.isEmpty else { return }

        lastSwipeEventAt = Date()
        swipeOffset += event.scrollingDeltaX

        // Доля пройденного пути: по ней вёрстка проявляет значок.
        let progress = min(abs(swipeOffset) / Self.swipeThreshold, 1)
        state.pendingSwipe = swipeOffset < 0 ? .next : .previous
        state.swipeProgress = progress

        // Палец убрали, не доведя до порога — значок уезжает обратно.
        if event.phase == .ended || event.phase == .cancelled {
            if progress < 1 { resetPendingSwipe() }
            return
        }

        guard progress >= 1, Date() >= swipeReadyAt else { return }
        performSwipe(swipeOffset < 0 ? .next : .previous)
    }

    private func resetPendingSwipe() {
        swipeOffset = 0
        state.swipeProgress = 0
        state.pendingSwipe = nil
    }

    /// Сторож незавершённого жеста.
    ///
    /// Фазу «конец» шлёт трекпад, но не колесо мыши, а после срабатывания
    /// её может не быть вовсе: значок оставался висеть, пока не тронешь
    /// что-нибудь ещё. Поэтому доля жеста гаснет и просто по молчанию.
    private func expirePendingSwipe() {
        guard state.swipeProgress > 0 else { return }
        guard Date().timeIntervalSince(lastSwipeEventAt) >= Self.swipeIdleTimeout else { return }
        resetPendingSwipe()
    }

    /// Свайп двумя пальцами по мини-виду тянет панель: вниз — раскрывает,
    /// вверх — сворачивает обратно. То же, что нажатие и уход курсора,
    /// но не отрывая руки от трекпада.
    ///
    /// Направление считается по пальцам, а не по знаку смещения: при
    /// «естественной» прокрутке система его переворачивает, и жёстко
    /// зашитый знак работал бы правильно ровно у половины людей.
    private func handlePull(_ event: NSEvent) {
        let fingersDown = event.isDirectionInvertedFromDevice
            ? event.scrollingDeltaY > 0
            : event.scrollingDeltaY < 0

        // Какое направление сейчас имеет смысл, зависит от состояния:
        // свёрнутую панель тянут вниз, раскрытую — вверх. Обратное движение
        // обнуляет накопленное: вытягивание — это одно непрерывное движение,
        // а не сумма разнонаправленных рывков.
        let wantsDown = !state.isPinnedOpen
        guard fingersDown == wantsDown else {
            pullOffset = 0
            return
        }

        pullOffset += abs(event.scrollingDeltaY)
        guard pullOffset >= Self.pullThreshold else { return }

        pullOffset = 0
        DebugLog.write(
            "свайп \(wantsDown ? "вниз" : "вверх"): \(wantsDown ? "раскрываем" : "сворачиваем") панель"
            + " (смещение \(Int(event.scrollingDeltaY)),"
            + " направление перевёрнуто: \(event.isDirectionInvertedFromDevice))"
        )
        wantsDown ? handleTap() : collapsePanel()
    }

    /// Свернуть раскрытую панель обратно в мини-вид, не уводя курсор.
    private func collapsePanel() {
        guard state.isPinnedOpen else { return }
        state.isPinnedOpen = false
        Haptics.tap(.levelChange)
        updateInteractiveRect()
    }

    private func performSwipe(_ direction: SwipeDirection) {
        resetPendingSwipe()
        swipeReadyAt = Date().addingTimeInterval(Self.swipeCooldown)

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
}
