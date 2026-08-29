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
    let things = ThingsService()
    let commands = CommandRunner()
    let meeting = MeetingService()
    let clipboard = ClipboardService()
    let assistant = AssistantSession()
    let weather = WeatherService()
    let shelf = ShelfStore()
    let timer = TimerService()
    let monitor = MonitorService()
    /// Текст телесуфлера. У контроллера, а не у окна: телесуфлер живёт
    /// накладкой в вырезе — у самой камеры, — и своего окна у него нет.
    let teleprompter = TeleprompterStore()
    let notes = NotesService()
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
    /// Удержание экрана от гашения — чашка кофе в раскрытой панели.
    let wake: WakeGuard

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
        voiceHotKey.stop()
        voice.shutdown()
        // Экран отпускаем явно: система сделала бы это и сама вместе
        // с процессом, но полагаться на это, когда выключение штатное,
        // незачем.
        wake.disable()
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
        router.onCursorExit = { [weak self] in self?.collapseAfterOverlay() }
    }

    private func installInput() {
        input.onHoverChanged = { [weak self] hovered in self?.setHovered(hovered) }
        input.onExpand = { [weak self] in self?.expandPanel() }
        input.onCollapse = { [weak self] in self?.collapsePanel() }
        input.onSwipe = { [weak self] direction in self?.performSwipe(direction) }
        input.onOverlayHover = { [weak self] location in self?.router.updateHover(at: location) }
        input.onDismissOverlay = { [weak self] in self?.dismissOverlay() }
        input.onOverlayKey = { [weak self] event in self?.handleOverlayKey(event) ?? false }
        // Прозрачность окна пересчитывается на каждом движении курсора,
        // а не только в тике опроса: между тиками десятая доля секунды,
        // и быстрый бросок к полоске с нажатием в неё не уложился бы.
        input.onCursorMoved = { [weak self] in self?.updateWindowInteractivity() }
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
        // Список моделей нужен панели разговора: по нему Tab перебирает
        // модель команды. Спрашивался он только из настроек и по нажатию
        // на имя модели — то есть у того, кто ни туда, ни туда не заходил,
        // Tab не делал ничего.
        if overlay == .assistant, settings.ollamaEnabled {
            ModelList.shared.refreshIfNeeded()
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
            isDraggingOut: state.isDraggingOut
        )
    }

    /// Полоска идущего таймера — или её отсутствие. Спрашивают и расчёт
    /// состояния, и проверка нажатий, и разойтись им нельзя.
    private var timerChip: TimerChip? {
        settings.timerEnabled ? timer.chip : nil
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
    private var notchSnapshot: NotchSnapshot {
        NotchInputs(
            overlay: state.overlay,
            swipe: state.swipe,
            pendingSwipe: state.pendingSwipe,
            swipeProgress: state.swipeProgress,
            isHovered: state.isHovered,
            isPinnedOpen: state.isPinnedOpen,
            chip: state.chipItem,
            timerChip: timerChip,
            caffeineChip: wake.chip,
            activity: activities.current,
            track: music.nowPlaying,
            events: calendar.upcoming.upcomingSlots(limit: NotchMetrics.maxVisibleEvents),
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
            assistantModelEnabled: settings.ollamaEnabled,
            shelfCount: shelf.items.count,
            hubCount: HubEntry.count,
            notesRows: notes.notes.count,
            notesEnabled: settings.notesEnabled,
            voicePhase: voice.phase
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
            self.assistant.ask(captured: captured, target: target)
            self.router.set(.assistant)
            self.takeKeyboard()
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
        assistant.ask(target: NSWorkspace.shared.frontmostApplication)
        router.set(.assistant)
        takeKeyboard()
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
    private func moveHighlight(_ offset: Int) -> Bool {
        let list = visibleCommands
        guard !list.isEmpty else { return false }
        // Пока выбирают модель, стрелки принадлежат этому выбору, а не списку
        // команд: увести подсветку из-под открытого выбора значило бы менять
        // модель не у той команды.
        guard assistant.choosingModelFor == nil else { return false }
        // Вверх-вниз возвращают человека к командам: ответ прочитан, и он
        // решил спросить иначе. Подсветка действий при этом гаснет — двух
        // подсветок разом быть не должно, иначе непонятно, чей Enter.
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
        guard let current = assistant.highlightedAnswerAction else { return false }
        let list = answerActions
        guard let index = list.firstIndex(of: current) else { return false }
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
            NotchHintTracker.shared.focus(action.title)
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
        guard let id = assistant.highlightedCommandID,
              var command = settings.quickCommands.first(where: { $0.id == id })
        else { return false }

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

    /// Esc снимает подсветку и закрывает выбор модели.
    ///
    /// Возвращает `false`, когда снимать было нечего: тогда нажатие идёт
    /// дальше и панель закрывает `NotchInput`. Иначе Esc закрывал бы панель
    /// вместе с набранным вопросом за одно нажатие — а человек всего лишь
    /// передумал выбирать команду.
    private func escapeHighlight() -> Bool {
        if assistant.choosingModelFor != nil {
            assistant.choosingModelFor = nil
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
    private func sendDraft() {
        // Подсвеченное забирает Enter себе — что бы это ни было. Человек
        // довёл до него стрелками и ждёт именно его: иначе клавиша делала бы
        // не то, на что показывает подсветка.
        //
        // Действие с ответом идёт первым: подсветка переезжает туда сама,
        // как только ответ дописан, и в этот момент она единственная на весь
        // экран.
        if let action = assistant.highlightedAnswerAction {
            runAnswerAction(action)
            return
        }
        if let id = assistant.highlightedCommandID,
           let command = visibleCommands.first(where: { $0.id == id }) {
            runCommandFromPanel(command)
            return
        }

        let text = draft.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, settings.ollamaEnabled else { return }

        var context: String?
        if assistant.usesNotes, settings.notesEnabled {
            context = notes.contextText()
            if context == nil {
                // Заметок нет вовсе — сказать об этом честнее, чем задать
                // вопрос по пустому архиву и выдать общий ответ за найденный.
                activities.present(.command(text: t("Заметок пока нет"), state: .failed))
                return
            }
        }
        assistant.send(text, notesContext: context)
        draft.clearQuestion()
    }

    /// Набранное уходит в заметки. Открытая на правку — переписывается,
    /// новая — заводится.
    private func saveNote() {
        guard settings.notesEnabled else { return }
        let wasEditing = draft.editingID != nil
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
    private func openNoteComposer() {
        guard settings.notesEnabled else { return }
        draft.startNewNote()
        assistant.ask(target: NSWorkspace.shared.frontmostApplication)
        router.set(.assistant)
        takeKeyboard()
    }

    func debugToggleNotes() {
        guard settings.notesEnabled else { return }
        router.toggle(.notes)
    }

    func debugNoteComposer() { toggleNoteComposer() }

    func debugSaveNote() { saveNote() }

    /// Свежая заметка — на правку. Проверяет, что режим переключается сам:
    /// заметка, открытая в разговоре, показывалась бы поверх чужого ответа
    /// и с однострочным полем.
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
        draft.load(note)
        router.set(.assistant)
        takeKeyboard()
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
        voiceHotKey.onTrigger = { [weak self] usesNotes in
            self?.toggleVoice(usesNotes: usesNotes)
        }
        voiceHotKey.install(
            plain: settings.voiceTrigger,
            withNotes: settings.voiceNotesTrigger,
            isEnabled: settings.voiceEnabled
        )
    }

    /// Позвать голос — или оборвать начатое тем же жестом.
    func toggleVoice(usesNotes: Bool) {
        guard settings.voiceEnabled else {
            DebugLog.write("голос: выключен в настройках")
            return
        }
        guard VoiceAccess.isReady else {
            requestVoiceAccess(usesNotes: usesNotes)
            return
        }
        voice.toggle(usesNotes: usesNotes)
    }

    /// Просит недостающие доступы и, получив их, продолжает заход.
    ///
    /// Спрашиваем в тот момент, когда доступ понадобился, а не при запуске:
    /// два системных диалога на старте приложения, которым человек ещё
    /// не пользовался, — верный способ получить отказ.
    private func requestVoiceAccess(usesNotes: Bool) {
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
            self.voice.toggle(usesNotes: usesNotes)
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

    func debugToggleVoice() { toggleVoice(usesNotes: false) }
    func debugToggleVoiceNotes() { toggleVoice(usesNotes: true) }

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
    private func dismissOverlay() {
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
        host.rebuild()
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
            teleprompter: teleprompter,
            notes: notes,
            draft: draft,
            voice: voice,
            flash: flash,
            wake: wake,
            settings: settings,
            metrics: metrics,
            // Замыканием, а не значением: вид строится один раз, а состояние
            // меняется по десять раз в секунду. Вёрстка перерисовывается
            // от наблюдаемых служб и на каждой перерисовке спрашивает снимок
            // заново — тот же, по которому считается зона нажатий.
            snapshot: { [weak self] in
                self?.notchSnapshot ?? NotchSnapshot(presentation: .collapsed, content: NotchContent())
            },
            onTap: { [weak self] in self?.expandPanel() },
            onOpenSettings: { [weak self] in self?.onOpenSettings?() },
            onJoin: { [weak self] url in self?.join(url) },
            onRunCommand: { [weak self] command in self?.runCommandFromPanel(command) },
            onClearCapture: { [weak self] in self?.assistant.clearCapture() },
            onToggleCapture: { [weak self] in self?.assistant.isCaptureExpanded.toggle() },
            onBeginChoosingModel: { [weak self] command in self?.beginChoosingModel(command) },
            onChooseModel: { [weak self] model in self?.chooseModel(model) },
            onCancelChoosingModel: { [weak self] in self?.assistant.choosingModelFor = nil },
            onMoveHighlight: { [weak self] offset in self?.moveHighlight(offset) ?? false },
            onMoveAnswerAction: { [weak self] offset in self?.moveAnswerAction(offset) ?? false },
            onCycleModel: { [weak self] in self?.cycleModel() ?? false },
            onEscapeHighlight: { [weak self] in self?.escapeHighlight() ?? false },
            onCopyLink: { [weak self] url in self?.copyLink(url) },
            onOpenItem: { [weak self] item in self?.openItem(item) },
            onCloseOverlay: { [weak self] in self?.closeOverlay() },
            onOpenClipboard: { [weak self] in self?.openClipboard() },
            onUseClipboard: { [weak self] entry in self?.useClipboard(entry) },
            onSaveClipboardToNotes: { [weak self] entry in self?.saveClipboardToNotes(entry) },
            onStopVoice: { [weak self] in self?.voice.stop() },
            onDeleteClipboard: { [weak self] entry in self?.clipboard.delete(entry) },
            onClearClipboard: { [weak self] in self?.clipboard.clear() },
            onCopyAnswer: { [weak self] in self?.copyAnswer() },
            onPasteAnswer: { [weak self] in self?.pasteAnswer() },
            onSendDraft: { [weak self] in self?.sendDraft() },
            onSaveDraft: { [weak self] in self?.saveNote() },
            onSelectMode: { [weak self] mode in self?.selectMode(mode) },
            onNewNote: { [weak self] in self?.openNoteComposer() },
            onSaveAnswer: { [weak self] in self?.saveAnswer() },
            onToggleNotesSearch: { [weak self] in self?.toggleNotesSearch() },
            onCloseAssistant: { [weak self] in self?.closeAssistant() },
            onOpenNotes: { [weak self] in self?.openNotes() },
            onOpenNote: { [weak self] note in self?.openNote(note) },
            onDeleteNote: { [weak self] note in self?.notes.delete(note) },
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
            onDismissActivity: { [weak self] in self?.dismissShelfChip() },
            onOpenHub: { [weak self] in self?.openHub() },
            onOpenTeleprompter: { [weak self] in self?.openTeleprompter() },
            onOpenExpanded: { [weak self] in self?.openExpanded() },
            onAskAssistant: { [weak self] in self?.askAssistant() },
            onOpenAwake: { [weak self] in self?.openAwake() },
            onChooseAwakeLimit: { [weak self] minutes in self?.chooseAwakeLimit(minutes: minutes) },
            onDisableAwake: { [weak self] in self?.disableAwake() }
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

    func debugAskNotes() {
        guard settings.ollamaEnabled else {
            DebugLog.write("заметки: Ollama выключена, спрашивать нечем")
            return
        }
        guard let context = notes.contextText() else {
            DebugLog.write("заметки: пусто, сперва notesFill")
            return
        }
        assistant.usesNotes = true
        assistant.ask(target: NSWorkspace.shared.frontmostApplication)
        router.set(.assistant)
        assistant.send(t("О чём мои заметки? Перечисли коротко."), notesContext: context)
        DebugLog.write("заметки: вопрос по контексту в \(context.count) симв.")
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
