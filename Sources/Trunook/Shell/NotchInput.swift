import TrunookXPC
import AppKit
import Foundation

/// Всё, что приходит от руки: наведение, нажатие, свайпы и поглаживание.
///
/// Распознаёт, но не применяет. Что делать с распознанным — вибрировать,
/// переключать трек, раскрывать панель — решает контроллер: службы и звук
/// принадлежат ему.
final class NotchInput {
    /// Порог срабатывания свайпа в точках и пауза между переключениями.
    private static let swipeThreshold: CGFloat = 45
    private static let swipeCooldown: TimeInterval = 0.6
    /// Через сколько молчания незавершённый свайп считается брошенным.
    private static let swipeIdleTimeout: TimeInterval = 0.25

    /// Порог вытягивания панели вниз. Ниже, чем у переключения трека:
    /// раскрытие обратимо — достаточно увести курсор, — а промахнуться
    /// мимо трека дороже.
    private static let pullThreshold: CGFloat = 28

    private let state: NotchState
    private let settings: Settings
    private let host: NotchWindowHost
    private let petting = PettingDetector()
    private let drag = DragDetector()

    /// Курсор вошёл в зону выреза или покинул её.
    var onHoverChanged: ((Bool) -> Void)?
    /// Панель просят раскрыть целиком: нажатием или свайпом вниз.
    var onExpand: (() -> Void)?
    /// Свайп вверх по раскрытой панели.
    var onCollapse: (() -> Void)?
    /// Свайп поперёк довели до порога.
    var onSwipe: ((SwipeDirection) -> Void)?
    /// Курсор двигается, пока открыта накладка.
    var onOverlayHover: ((CGPoint) -> Void)?
    /// Чем накладку просят закрыть.
    ///
    /// Различать обязательно: панель команд закрепляется и нажатие мимо
    /// перестаёт её закрывать — а Esc закрывает по-прежнему. Пока причина
    /// была одна на оба пути, закрепить одно, не закрепив другое, было нечем.
    enum DismissCause {
        /// Нажали мимо накладки — в чужом окне.
        case clickOutside
        /// Нажали Esc.
        case escape
    }

    /// Нажатие мимо накладки или Esc.
    var onDismissOverlay: ((DismissCause) -> Void)?
    /// Клавиша при открытой накладке. Возвращает, забрала ли накладка
    /// нажатие себе: не забранное уходит дальше своим ходом.
    var onOverlayKey: ((NSEvent) -> Bool)?
    /// Курсор сдвинулся — куда угодно, не только в вырез. По этому событию
    /// пересчитывается прозрачность окна для мыши.
    var onCursorMoved: (() -> Void)?
    /// Тик опроса: то, что нужно пересчитывать по времени, а не по событию.
    var onTick: (() -> Void)?
    /// Что-то тащат мышью. По этому признаку оживает зона приёма файлов:
    /// в покое она прозрачна для мыши и нажатий не ест.
    var onDragChanged: ((Bool) -> Void)?
    var onPettingStart: (() -> Void)?
    var onPettingStop: (() -> Void)?
    /// Кнопку держат на вырезе дольше порога — раскрывается кольцо.
    var onQuickRingOpen: (() -> Void)?
    /// Рука ведёт по кольцу. Смещение от нижней кромки чёлки, `y` вниз.
    var onQuickRingMove: ((CGPoint) -> Void)?
    /// Кнопку отпустили.
    var onQuickRingClose: (() -> Void)?

    private var monitors: [Any] = []
    private var pollTimer: Timer?

    // Накопитель горизонтального смещения для свайпа двумя пальцами.
    private var swipeOffset: CGFloat = 0
    /// Накопитель вертикального: им панель вытягивают из мини-вида.
    private var pullOffset: CGFloat = 0
    private var swipeReadyAt = Date.distantPast
    /// Когда последний раз приходило событие прокрутки: по молчанию гасим
    /// незавершённый жест.
    private var lastSwipeEventAt = Date.distantPast

    /// До какого момента отладочное раскрытие держится вопреки курсору.
    private var holdUntil = Date.distantPast

    /// Сколько держать кнопку, чтобы вышло кольцо.
    ///
    /// Треть секунды. Меньше — и обычное нажатие по чёлке начинало бы
    /// раскрывать кольцо у всякого, кто нажимает не спеша; больше — и
    /// удержание перестаёт читаться как жест и начинает читаться как
    /// задумчивость приложения.
    private static let ringDelay: TimeInterval = 0.34

    /// Когда кнопку нажали на вырезе. `nil` — не нажата или нажата не там.
    private var pressStartedAt: Date?
    /// Была ли кнопка нажата на прошлом тике: кольцо заводится **по краю**
    /// нажатия, а не по тому, что кнопка нажата и курсор над вырезом.
    private var wasPressed = false
    /// Открыто ли кольцо прямо сейчас.
    private var ringIsOpen = false


    init(state: NotchState, settings: Settings, host: NotchWindowHost) {
        self.state = state
        self.settings = settings
        self.host = host
    }

    // MARK: - Жизненный цикл

    func start() {
        installMouseTracking()
        petting.onStart = { [weak self] in self?.onPettingStart?() }
        petting.onStop = { [weak self] in self?.onPettingStop?() }
        drag.onChange = { [weak self] dragging in self?.onDragChanged?(dragging) }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    /// Отладочное раскрытие удерживается несколько секунд вопреки курсору:
    /// опрос идёт десять раз в секунду и снял бы наведение на первом же тике.
    func hold(seconds: TimeInterval) {
        holdUntil = Date().addingTimeInterval(seconds)
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
            let pressed = NSEvent.pressedMouseButtons & 1 != 0
            // До `drag.update`: кольцо и приём файлов смотрят на одну и ту же
            // кнопку, и порядок здесь важен только тем, что кольцо должно
            // узнать об отпускании тем же тиком, каким оно случилось.
            self.updateQuickRing(pressed: pressed, at: NSEvent.mouseLocation)
            self.drag.update(
                isPressed: pressed,
                at: NSEvent.mouseLocation
            )
            self.expirePendingSwipe()
            self.onTick?()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        // Мониторы оставляем ради мгновенной реакции между тиками опроса.
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handleMouse(at: NSEvent.mouseLocation)
            if event.type == .leftMouseDragged { self?.drag.note() }
            // Пока кнопка зажата, `.mouseMoved` не приходит вовсе — движение
            // едет в `.leftMouseDragged`. Без этого кольцо подсвечивало бы
            // кружок десять раз в секунду вместо каждого движения руки.
            self?.trackQuickRing(at: NSEvent.mouseLocation)
        }) {
            monitors.append(global)
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handleMouse(at: NSEvent.mouseLocation)
            if event.type == .leftMouseDragged { self?.drag.note() }
            self?.trackQuickRing(at: NSEvent.mouseLocation)
            return event
        }) {
            monitors.append(local)
        }

        // Нажатие мимо меню закрывает его — как поступает любое меню системы.
        // Монитор глобальный: он срабатывает только на события, ушедшие
        // в чужое приложение, то есть ровно на «мимо».
        if let outside = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] _ in self?.onDismissOverlay?(.clickOutside) }
        ) {
            monitors.append(outside)
        }

        // Накладка закрывается по Esc. Монитор локальный: панель к этому
        // моменту уже приняла фокус, чтобы принимать нажатия.
        //
        // Этим же монитором накладка получает и остальные клавиши — стрелки
        // и Enter в списке истории. Своего поля ввода у неё нет, а стрелки
        // в панели команд достаются полю вопроса и оттуда уходят наверх;
        // взять их иначе неоткуда. Узел только распознаёт и передаёт: что
        // делать с нажатием, решает контроллер, и он же отвечает, забрал ли
        // его себе.
        if let keys = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            guard let self, self.state.overlay != nil else { return event }
            if event.keyCode == 53 {
                self.onDismissOverlay?(.escape)
                return nil
            }
            return self.onOverlayKey?(event) == true ? nil : event
        }) {
            monitors.append(keys)
        }

        // Свайп двумя пальцами приходит обычными событиями прокрутки:
        // отдельный тип .swipe система шлёт только когда включён системный
        // жест «Смахивание между страницами», а он есть не у всех.
        if let scroll = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel], handler: { [weak self] event in
            self?.handleScroll(event)
            return event
        }) {
            monitors.append(scroll)
        }
    }

    private func handleMouse(at location: CGPoint) {
        // До всех проверок и раньше любого раннего возврата: окно оживает
        // и гаснет по положению курсора, и пропустить движение нельзя
        // ни в одной из веток ниже.
        onCursorMoved?()
        guard Date() >= holdUntil else { return }
        if state.overlay != nil {
            onOverlayHover?(location)
            petting.reset()
            return
        }
        guard settings.expandOnHover else {
            if state.isHovered { setHovered(false) }
            petting.reset()
            return
        }
        let inside = state.isHovered
            ? host.closeTriggerRect.contains(location)
            : host.openTriggerRect.contains(location)
        if inside != state.isHovered { setHovered(inside) }
        // Поглаживание проверяется на каждом движении, а не только на смене
        // состояния: пока курсор ходит внутри выреза, наведение не меняется.
        updatePetting(at: location)
    }

    // MARK: - Кольцо быстрого доступа

    /// Кнопку держат на вырезе — считаем, дошло ли до порога.
    ///
    /// Всё решается опросом положения курсора и состояния кнопки, а не
    /// событиями. Причина та же, по которой на опросе держится и наведение:
    /// монитор нажатий молчит, когда событие ушло в чужое приложение, а
    /// кнопку на вырезе как раз и держат, водя рукой далеко от него.
    /// `NSEvent.pressedMouseButtons` отвечает всегда и всем.
    private func updateQuickRing(pressed: Bool, at location: CGPoint) {
        let justPressed = pressed && !wasPressed
        wasPressed = pressed
        guard pressed else {
            pressStartedAt = nil
            guard ringIsOpen else { return }
            ringIsOpen = false
            onQuickRingClose?()
            return
        }
        if ringIsOpen {
            trackQuickRing(at: location)
            return
        }
        guard let startedAt = pressStartedAt else {
            // Кольцо заводится **по краю** нажатия, а не по тому, что кнопка
            // нажата и курсор над вырезом. Разница ровно в перетаскивании:
            // файл ведут на чёлку с зажатой кнопкой и держат там, целясь
            // в полку, — и кольцо выскакивало бы у всякого, кто это делает.
            // Нажатие, начавшееся не здесь, кольцу не принадлежит.
            guard justPressed else { return }
            // Только с самой чёлки: нажатие в открытой панели — это работа
            // с ней, а не жест.
            guard state.overlay == nil, host.openTriggerRect.contains(location) else { return }
            pressStartedAt = Date()
            return
        }
        guard Date().timeIntervalSince(startedAt) >= Self.ringDelay else { return }
        ringIsOpen = true
        onQuickRingOpen?()
        trackQuickRing(at: location)
    }

    /// Куда метит рука — в смещениях от нижней кромки чёлки, `y` вниз.
    private func trackQuickRing(at location: CGPoint) {
        guard ringIsOpen, let notch = host.geometry?.notchRect else { return }
        onQuickRingMove?(CGPoint(
            x: location.x - notch.midX,
            y: notch.minY - location.y
        ))
    }

    private func setHovered(_ hovered: Bool) {
        // Курсор ушёл — недобранный свайп уходит вместе с ним.
        if !hovered { swipeOffset = 0 }
        onHoverChanged?(hovered)
    }

    // MARK: - Поглаживание

    /// Поглаживание считается только в мини-виде. В раскрытой панели курсор
    /// ходит между кнопками перемотки, и такие движения не должны будить кота;
    /// в любой накладке — тем более.
    private func updatePetting(at location: CGPoint) {
        guard settings.purrEnabled,
              state.isHovered,
              !state.isPinnedOpen,
              state.overlay == nil,
              let geometry = host.geometry
        else {
            petting.reset()
            return
        }

        // Начать поглаживание можно только на самой чёлке, а продолжать —
        // в любом месте раскрытого мини-вида. Строгая зона высотой в саму
        // чёлку рвала мурчание почти сразу: рука на развороте выходит
        // и вбок, и вниз, а каждый выход требовал набирать четыре хода
        // заново — со стороны выглядело как «сработало один раз».
        let region = petting.isPurring ? host.closeTriggerRect : startPettingRect(geometry)
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
        state.pendingSwipe = swipeDirection
        state.swipeProgress = progress

        // Палец убрали, не доведя до порога — значок уезжает обратно.
        if event.phase == .ended || event.phase == .cancelled {
            if progress < 1 { resetPendingSwipe() }
            return
        }

        guard progress >= 1, Date() >= swipeReadyAt else { return }
        // Сторону считаем до сброса: он обнуляет накопитель, по знаку
        // которого она и определяется.
        let direction = swipeDirection
        resetPendingSwipe()
        swipeReadyAt = Date().addingTimeInterval(Self.swipeCooldown)
        onSwipe?(direction)
    }

    /// Куда ведёт нынешний свайп.
    ///
    /// Знак накопителя уже учитывает системную «естественную прокрутку» —
    /// она приходит в самих событиях. Настройка поверх этого про вкус:
    /// одним «вперёд» кажется движение влево, как листают ленту, другим
    /// вправо, как переворачивают страницу.
    private var swipeDirection: SwipeDirection {
        let natural: SwipeDirection = swipeOffset < 0 ? .next : .previous
        guard settings.swipeInverted else { return natural }
        return natural == .next ? .previous : .next
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
        wantsDown ? onExpand?() : onCollapse?()
    }
}
