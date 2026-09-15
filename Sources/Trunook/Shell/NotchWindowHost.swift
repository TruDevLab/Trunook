import TrunookXPC
import AppKit
import SwiftUI

/// Окна над вырезом: построение, геометрия и зона нажатий.
///
/// Вёрстку строит не он. Службы и действия принадлежат контроллеру, хосту —
/// только окна, их размеры и прямоугольники, по которым считается наведение.
///
/// Окон столько, сколько экранов показывают остров, и у каждого своя вёрстка,
/// построенная один раз под свою чёлку. Одно из них **главное**: оно ловит
/// мышь и показывает то, что заведено рукой. Остальные рисуют полоску или
/// отсчёт. Смена главного не двигает окон и не пересобирает вёрстку — только
/// меняет, чей снимок полный. Первый вариант возил одно окно с экрана на экран
/// и подменял ему вёрстку, а на покинутом экране заводил окно-отражение
/// с нуля: на миг остров на мониторе вспыхивал чёрным по метрикам MacBook,
/// а отсчёт на MacBook пропадал, пока новое окно не нарисовало первый кадр.
final class NotchWindowHost {
    /// Собирает корневой вид окна на экране с этим номером. Метрики приходят
    /// снаружи, потому что зависят от размеров выреза, а те известны только
    /// после разбора геометрии.
    var makeRoot: ((NotchMetrics, CGDirectDisplayID) -> NotchView?)?

    /// Размер видимой формы окна — тот же расчёт, что и в вёрстке. Зона
    /// нажатий обязана совпадать с нарисованным: иначе панель видно, а нажать
    /// по ней нельзя — на этом уже спотыкались.
    var contentSize: ((NotchMetrics, CGDirectDisplayID) -> CGSize)?

    /// Нажатие правой кнопкой по вырезу.
    var onRightClick: (() -> Void)?

    /// Главным стало окно на экране с этим номером. Зовётся до перерисовки:
    /// вёрстка узнаёт о смене из состояния, которое здесь и меняют.
    var onActivate: ((CGDirectDisplayID) -> Void)?

    /// Геометрия главного окна сменилась: зона приёма файлов считается от неё.
    var onRebuild: ((NotchGeometry, NotchMetrics) -> Void)?

    private final class Entry {
        let window: NotchWindow
        let hosting: NotchHostingView<NotchView>
        var geometry: NotchGeometry
        var metrics: NotchMetrics

        init(window: NotchWindow, hosting: NotchHostingView<NotchView>, geometry: NotchGeometry, metrics: NotchMetrics) {
            self.window = window
            self.hosting = hosting
            self.geometry = geometry
            self.metrics = metrics
        }
    }

    private var entries: [CGDirectDisplayID: Entry] = [:]
    private(set) var activeID: CGDirectDisplayID?
    private var active: Entry? { activeID.flatMap { entries[$0] } }

    var geometry: NotchGeometry? { active?.geometry }
    var metrics: NotchMetrics? { active?.metrics }

    /// Гистерезис: раскрываем по узкой зоне выреза, а закрываем только когда
    /// курсор ушёл за пределы всей раскрытой панели. Иначе панель дёргается.
    var openTriggerRect: CGRect { active?.geometry.openTrigger ?? .zero }
    /// Где курсор ещё держит раскрытое: нарисованная форма с запасом.
    ///
    /// Раньше это была рамка всего окна, а окно всегда размером с самую
    /// большую панель — 620 точек в ширину и сотни в высоту. Мини-вид
    /// в 233 точки держался, пока курсор бродил где угодно в этом
    /// прямоугольнике под чёлкой, — по заголовкам окон, вкладкам, полям,
    /// — и выглядело это как залипание. Окно росло с каждой новой панелью,
    /// а с ним и зона залипания.
    var closeTriggerRect: CGRect {
        guard let size = currentContentSize, size != .zero else { return active?.window.frame ?? .zero }
        return Self.closeRect(visible: topAlignedRect(size: size), open: openTriggerRect)
    }

    /// Запас вокруг формы: без него панель дёргалась бы, стоит курсору
    /// задеть край.
    static let hoverSlack: CGFloat = 16

    static func closeRect(visible: CGRect, open: CGRect) -> CGRect {
        visible.insetBy(dx: -hoverSlack, dy: -hoverSlack).union(open)
    }

    /// Главное окно ловит мышь, только когда на экране есть во что попадать.
    /// Остальные не ловят никогда: работа с островом идёт в главном.
    var ignoresMouseEvents: Bool {
        get { active?.window.ignoresMouseEvents ?? true }
        // Свойство спрашивают десять раз в секунду. Присваивать окну то же
        // самое каждый раз незачем: сравнение дешевле обращения к AppKit.
        set {
            guard let window = active?.window, window.ignoresMouseEvents != newValue else { return }
            window.ignoresMouseEvents = newValue
            DebugLog.write("окно \(newValue ? "прозрачно для мыши" : "ловит мышь")")
        }
    }

    /// Курсор внутри нарисованного главным окном прямо сейчас.
    ///
    /// По нему решается, ловит ли окно мышь: непрозрачное окно съедает
    /// нажатия во всей рамке, и держать его таким, пока курсор далеко,
    /// значит выключить кусок экрана.
    var visibleRectContainsCursor: Bool {
        guard let size = currentContentSize, size != .zero else { return false }
        return topAlignedRect(size: size).contains(NSEvent.mouseLocation)
    }

    /// Нынешний размер видимой формы главного окна. Нужен не только зоне
    /// нажатий: по нему же считается прямоугольник накладки на экране.
    var currentContentSize: CGSize? {
        guard let active, let activeID else { return nil }
        return contentSize?(active.metrics, activeID)
    }

    // MARK: - Построение

    /// Построить окна на экранах. `handles` — экраны, где в покое видна
    /// полоска; `active` — экран главного окна. Окна, которых нет в списке,
    /// убираются; уже стоящие не пересоздаются.
    func rebuild(screens: [NSScreen], handles: Set<CGDirectDisplayID>, active: CGDirectDisplayID) {
        let wanted = Set(screens.map(NotchGeometry.displayID(of:)))
        for (id, entry) in entries where !wanted.contains(id) {
            entry.window.orderOut(nil)
            entries[id] = nil
        }
        guard wanted.contains(active) else {
            hide()
            return
        }
        if activeID != active {
            activeID = active
            onActivate?(active)
        }

        for screen in screens {
            let geometry = NotchGeometry(screen: screen)
            let id = geometry.displayID
            let metrics = NotchMetrics(
                notchWidth: geometry.notchRect.width,
                notchHeight: geometry.notchRect.height,
                hasNotch: geometry.isHardware,
                showsHandle: handles.contains(id)
            )
            let frame = geometry.windowFrame(contentSize: metrics.windowSize)
            if let entry = entries[id] {
                // Экран поменял чёлку или полоску: вёрстка получает размеры
                // один раз, при постройке. Службы и состояние при этом
                // не пересоздаются — меняется только значение, из которого
                // вид строится.
                if metrics != entry.metrics, let root = makeRoot?(metrics, id) {
                    entry.hosting.rootView = root
                }
                entry.geometry = geometry
                entry.metrics = metrics
                entry.window.setFrame(frame, display: true)
            } else {
                guard let entry = makeEntry(id: id, frame: frame, geometry: geometry, metrics: metrics) else {
                    continue
                }
                entries[id] = entry
            }
            if id != active { entries[id]?.window.ignoresMouseEvents = true }
            entries[id]?.window.orderFrontRegardless()

            DebugLog.write("геометрия: \(geometry.description)\(id == active ? ", главное" : "")")
            DebugLog.write("окно \(NSStringFromRect(frame)), зона раскрытия \(NSStringFromRect(geometry.openTrigger))")
        }

        updateInteractiveRect()
        if let entry = self.active { onRebuild?(entry.geometry, entry.metrics) }

        guard let metrics else { return }
        // Плашка события не должна оказаться уже свёрнутой формы —
        // иначе остров выглядит меньше самого выреза.
        let shortest = ActivityLayout(text: "Низкий заряд", trailing: "20%", minimumWidth: metrics.closed.width)
        DebugLog.write(
            "ширины: свёрнуто \(Int(metrics.closed.width)), "
            + "плашка минимум \(Int(shortest.panelWidth)), "
            + "раскрыто \(Int(metrics.expanded(rows: 0).width)), "
            + "отсчёт \(Int(ChipView.width(metrics: metrics))) при окне \(Int(metrics.windowSize.width))"
        )
    }

    /// Сделать главным окно на другом экране. Окна не двигаются.
    func activate(_ id: CGDirectDisplayID) {
        guard id != activeID, let entry = entries[id] else { return }
        active?.window.ignoresMouseEvents = true
        activeID = id
        onActivate?(id)
        updateInteractiveRect()
        onRebuild?(entry.geometry, entry.metrics)
        DebugLog.write("главное окно: \(entry.geometry.description)")
    }

    private func makeEntry(id: CGDirectDisplayID, frame: CGRect, geometry: NotchGeometry, metrics: NotchMetrics) -> Entry? {
        guard let root = makeRoot?(metrics, id) else { return nil }
        let window = NotchWindow(contentRect: frame)
        let hosting = NotchHostingView(rootView: root)
        hosting.onRightClick = { [weak self] in self?.onRightClick?() }
        hosting.frame = CGRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        return Entry(window: window, hosting: hosting, geometry: geometry, metrics: metrics)
    }

    func hide() {
        entries.values.forEach { $0.window.orderOut(nil) }
        entries.removeAll()
        activeID = nil
    }

    // MARK: - Размеры и координаты

    /// Окно всегда максимального размера, а форма занимает лишь его часть.
    /// Сообщаем подложке, где именно принимать нажатия, чтобы прозрачные
    /// углы окна не съедали клики по меню-бару.
    func updateInteractiveRect() {
        for (id, entry) in entries {
            guard let size = contentSize?(entry.metrics, id) else { continue }
            // Метод вызывается десять раз в секунду — выходим молча, если
            // ничего не поменялось, иначе журнал захлебнётся.
            guard size != entry.hosting.visibleSize else { continue }
            entry.hosting.visibleSize = size
            if id == activeID {
                DebugLog.write("зона нажатий: \(Int(size.width))×\(Int(size.height))")
            }
        }
    }

    /// Прямоугольник заданного размера, прижатый к верхней кромке главного
    /// окна и отцентрованный по вырезу, — в координатах экрана.
    func topAlignedRect(size: CGSize) -> CGRect {
        guard let frame = active?.window.frame else { return .zero }
        return CGRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Прочее

    /// Панель фокус не забирает по устройству, поэтому на ввод текста
    /// его приходится требовать явно.
    func makeKey() {
        active?.window.makeKeyAndOrderFront(nil)
    }

    /// Снимок главного окна — единственный способ увидеть вёрстку острова
    /// из отладочной сессии.
    func snapshot(named name: String = "notch") {
        WindowSnapshot.write(active?.window, named: name)
    }

    /// Снимки остальных окон: главный экран — `notch-mirror-home`, чужие —
    /// с номером экрана.
    func snapshotInactive(home: CGDirectDisplayID?) {
        for (id, entry) in entries where id != activeID {
            WindowSnapshot.write(entry.window, named: id == home ? "notch-mirror-home" : "notch-mirror-\(id)")
        }
    }
}
