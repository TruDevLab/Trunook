import AppKit
import TrunookXPC

/// Окно, которое ловит перетаскиваемые файлы для полки.
///
/// Отдельное окно, а не сам вырез, и это не выбор оформления, а требование
/// системы. Подробности с числами — в `DEVELOPMENT.md`, раздел «Правила
/// приёма, из-за которых всё устроено именно так»; здесь коротко, почему
/// устроено именно так:
///
/// - **Уровень 500 и ни точкой выше.** `kCGDraggingWindowLevel` — это уровень,
///   на котором система везёт картинку перетаскиваемого файла. Окно выше неё
///   целью перетаскивания не считается вовсе. Вырез живёт на 1000, поэтому
///   принимать файлы сам он не может в принципе.
/// - **Окно выреза сверху не мешает.** Перетаскивание проходит к окну под ним
///   насквозь, в любом его состоянии.
/// - **Прозрачно для мыши, пока никто ничего не тащит.** Приём файлов
///   и прозрачность для нажатий — один выключатель: окно, пропускающее
///   нажатия сквозь себя, не принимает и перетаскивание. Раньше выключатель
///   стоял в «принимаю» всегда, и полоса 185×128 под чёлкой съедала нажатия
///   по чужим окнам круглые сутки. Теперь окно оживает по `isArmed` — только
///   на время перетаскивания.
/// - **Растёт посреди перетаскивания.** По первому `draggingEntered` окно
///   раздаётся до размера панели, и ронять можно куда угодно в неё. Система
///   такой рост признаёт: обновления продолжают идти в новой геометрии.
/// - **Схлопывается с задержкой.** Мгновенный возврат к полоске вытаскивает
///   окно из-под курсора, тот попадает в него снова, и получается мигание.
final class ShelfDropWindow {
    /// Курсор с файлами зашёл в зону приёма.
    var onEnter: (() -> Void)?
    /// Курсор с файлами ушёл, ничего не уронив.
    var onExit: (() -> Void)?
    /// Файлы уронили. Возврат — принято ли хоть что-то.
    var onDrop: (([URL]) -> Bool)?

    private var panel: DropPanel?
    private var view: DropView?

    private var collapsedFrame: CGRect = .zero
    private var grownFrame: CGRect = .zero
    private var collapseWork: DispatchWorkItem?

    /// Окно ловит мышь. В покое — нет: иначе полоса под чёлкой съедает
    /// нажатия по тому, что под ней.
    ///
    /// Разделить приём файлов и прозрачность для мыши система не даёт, это
    /// одно свойство. Поэтому «прозрачно, пока не тащат»: признак ставит
    /// `NotchInput`, который и так опрашивает мышь десять раз в секунду.
    /// Успевает с запасом — от начала перетаскивания до чёлки курсору идти
    /// много дольше.
    var isArmed = false {
        didSet {
            guard isArmed != oldValue else { return }
            panel?.ignoresMouseEvents = !isArmed
            DebugLog.write("полка: зона приёма \(isArmed ? "ожила" : "прозрачна для мыши")")
        }
    }

    /// Полка открыта как накладка — окно держим раскрытым, чтобы на открытую
    /// полку можно было докладывать файлы.
    var isPinnedOpen = false {
        didSet {
            guard isPinnedOpen != oldValue else { return }
            isPinnedOpen ? grow() : scheduleCollapse()
        }
    }

    /// Насколько задерживаем схлопывание. Меньше трети секунды — мигание
    /// возвращается, больше секунды — окно заметно висит поверх чужого.
    private static let collapseDelay: TimeInterval = 0.35

    /// Типы, на которые подписаны и вид, и окно. Прототип принимал файлы
    /// именно с таким набором.
    static let draggedTypes: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string]

    func update(collapsed: CGRect, grown: CGRect) {
        collapsedFrame = collapsed
        grownFrame = grown

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(isPinnedOpen ? grownFrame : collapsedFrame, display: true)
        panel.orderFrontRegardless()
        DebugLog.write("полка: зона приёма \(NSStringFromRect(collapsed)) → \(NSStringFromRect(grown))")
    }

    func hide() {
        collapseWork?.cancel()
        collapseWork = nil
        panel?.orderOut(nil)
        panel = nil
        view = nil
    }

    // MARK: - Размер

    private func grow() {
        collapseWork?.cancel()
        collapseWork = nil
        guard let panel, panel.frame != grownFrame else { return }
        panel.setFrame(grownFrame, display: true)
    }

    private func scheduleCollapse() {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isPinnedOpen else { return }
            self.panel?.setFrame(self.collapsedFrame, display: true)
            self.view?.isHighlighted = false
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.collapseDelay, execute: work)
    }

    // MARK: - Построение

    private func makePanel() -> DropPanel {
        let panel = DropPanel(
            contentRect: collapsedFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // В покое окна для мыши как бы нет. Оживает на время перетаскивания.
        panel.ignoresMouseEvents = !isArmed
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        // Ровно уровень картинки перетаскивания. Выше — приёма не будет.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)))
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.animationBehavior = .none

        let view = DropView(frame: CGRect(origin: .zero, size: collapsedFrame.size))
        view.onEnter = { [weak self] in
            guard let self else { return }
            self.grow()
            self.onEnter?()
        }
        view.onExit = { [weak self] in
            guard let self else { return }
            self.scheduleCollapse()
            self.onExit?()
        }
        view.onDrop = { [weak self] urls in
            guard let self else { return false }
            let accepted = self.onDrop?(urls) ?? false
            self.scheduleCollapse()
            return accepted
        }
        panel.contentView = view
        // Регистрация нужна и на самом окне, не только на виде. У NSWindow
        // свой список принимаемых типов, и без него окно может не попасть
        // в перебор целей перетаскивания. В прототипе было зарегистрировано
        // и то и другое — повторяем проверенную связку целиком.
        panel.registerForDraggedTypes(Self.draggedTypes)
        self.view = view
        return panel
    }
}

/// Панель приёма. Ключ не отбирает — вырез намеренно не трогает фокус,
/// и полка не повод это менять.
private final class DropPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Вид, принимающий файлы.
///
/// Рисует почти прозрачную заливку, и это не украшение, а условие работы:
/// **окно, не нарисовавшее ни одной непрозрачной точки, не участвует
/// в проверке попаданий** — события проходят сквозь него, как сквозь дыру,
/// и перетаскивание вместе с ними. В прототипе заливка была яркой, чтобы
/// человек видел мишень, и этим случайно скрыла требование: при переносе
/// в приложение заливку убрали, и приём молча перестал работать.
///
/// Заливка берётся на одну ступень прозрачности из 255 — минимально
/// возможную ненулевую. Видимое здесь рисовать нечего: подсветку показывает
/// сам вырез, который висит выше.
private final class DropView: NSView {
    /// Одна ступень прозрачности из 255 — меньше уже ноль, а ноль означает
    /// дыру: события пройдут насквозь и перетаскивание не придёт.
    ///
    /// Начиналось с одного процента, но после того как зона опустилась
    /// на 96 точек ниже чёлки, полупрозрачный прямоугольник 185×128 стало
    /// видно на светлом фоне. Это физический минимум: ниже — только ноль.
    private static let hitTestableAlpha: CGFloat = 1.0 / 255.0

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(Self.hitTestableAlpha).setFill()
        bounds.fill()
    }

    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onDrop: (([URL]) -> Bool)?

    var isHighlighted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(ShelfDropWindow.draggedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) не используется")
    }

    /// Растёт вместе с окном: окно меняет размер посреди перетаскивания,
    /// и вид обязан занять его целиком, иначе приём останется в старых границах.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        autoresizingMask = [.width, .height]
    }

    private func urls(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let files = urls(from: sender)
        guard !files.isEmpty else {
            // Не молча: перетаскивание без файловых ссылок — это либо чужой
            // тип, либо неверная подписка, и различать их надо по журналу.
            let types = (sender.draggingPasteboard.types ?? []).map(\.rawValue)
            DebugLog.write("полка: заход без файлов, типы \(types)")
            return []
        }
        isHighlighted = true
        DebugLog.write("полка: перетаскивание вошло, файлов \(files.count)")
        onEnter?()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        urls(from: sender).isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isHighlighted = false
        DebugLog.write("полка: перетаскивание ушло")
        onExit?()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !urls(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isHighlighted = false
        let files = urls(from: sender)
        DebugLog.write("полка: уронили \(files.count)")
        guard !files.isEmpty else { return false }
        return onDrop?(files) ?? false
    }
}
