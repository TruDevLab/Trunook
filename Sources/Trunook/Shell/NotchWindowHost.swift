import TrunookXPC
import AppKit
import SwiftUI

/// Окно над вырезом: построение, геометрия и зона нажатий.
///
/// Вёрстку строит не он. Службы и действия принадлежат контроллеру, хосту —
/// только окно, его размеры и прямоугольники, по которым считается наведение.
final class NotchWindowHost {
    /// Собирает корневой вид. Метрики приходят снаружи, потому что зависят
    /// от размеров выреза, а те известны только после разбора геометрии.
    var makeRoot: ((NotchMetrics) -> NotchView?)?

    /// Размер видимой формы — тот же расчёт, что и в вёрстке. Зона нажатий
    /// обязана совпадать с нарисованным: иначе панель видно, а нажать по ней
    /// нельзя — на этом уже спотыкались.
    var contentSize: ((NotchMetrics) -> CGSize)?

    /// Нажатие правой кнопкой по вырезу.
    var onRightClick: (() -> Void)?

    /// Геометрия пересобрана: зона приёма файлов считается от неё.
    var onRebuild: ((NotchGeometry, NotchMetrics) -> Void)?

    private(set) var geometry: NotchGeometry?
    private(set) var metrics: NotchMetrics?

    /// Гистерезис: раскрываем по узкой зоне выреза, а закрываем только когда
    /// курсор ушёл за пределы всей раскрытой панели. Иначе панель дёргается.
    private(set) var openTriggerRect: CGRect = .zero
    private(set) var closeTriggerRect: CGRect = .zero

    private var window: NotchWindow?
    private var hostingView: NotchHostingView<NotchView>?

    /// Окно ловит мышь, только когда на экране есть во что попадать.
    var ignoresMouseEvents: Bool {
        get { window?.ignoresMouseEvents ?? true }
        // Свойство спрашивают десять раз в секунду. Присваивать окну то же
        // самое каждый раз незачем: сравнение дешевле обращения к AppKit.
        set {
            guard let window, window.ignoresMouseEvents != newValue else { return }
            window.ignoresMouseEvents = newValue
            DebugLog.write("окно \(newValue ? "прозрачно для мыши" : "ловит мышь")")
        }
    }

    /// Нынешний размер видимой формы. Нужен не только зоне нажатий:
    /// по нему же считается прямоугольник накладки на экране.
    var currentContentSize: CGSize? {
        guard let metrics else { return nil }
        return contentSize?(metrics)
    }

    // MARK: - Построение

    func rebuild() {
        guard let geometry = NotchGeometry.current() else {
            hide()
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

        guard let window = self.window ?? makeWindow(frame: frame, metrics: metrics) else { return }
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        self.window = window
        updateInteractiveRect()
        onRebuild?(geometry, metrics)

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

    private func makeWindow(frame: CGRect, metrics: NotchMetrics) -> NotchWindow? {
        guard let root = makeRoot.flatMap({ $0(metrics) }) else { return nil }
        let window = NotchWindow(contentRect: frame)
        let hosting = NotchHostingView(rootView: root)
        hosting.onRightClick = { [weak self] in self?.onRightClick?() }
        hosting.frame = CGRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        hostingView = hosting
        return window
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        hostingView = nil
    }

    // MARK: - Размеры и координаты

    /// Окно всегда максимального размера, а форма занимает лишь его часть.
    /// Сообщаем подложке, где именно принимать нажатия, чтобы прозрачные
    /// углы окна не съедали клики по меню-бару.
    func updateInteractiveRect() {
        guard let hostingView, let size = currentContentSize else { return }
        // Метод вызывается десять раз в секунду — выходим молча, если ничего
        // не поменялось, иначе журнал захлебнётся.
        guard size != hostingView.visibleSize else { return }
        hostingView.visibleSize = size
        DebugLog.write("зона нажатий: \(Int(size.width))×\(Int(size.height))")
    }

    /// Прямоугольник заданного размера, прижатый к верхней кромке окна
    /// и отцентрованный по вырезу, — в координатах экрана.
    func topAlignedRect(size: CGSize) -> CGRect {
        guard let frame = window?.frame else { return .zero }
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
        window?.makeKeyAndOrderFront(nil)
    }

    /// Снимок самого острова — единственный способ увидеть его вёрстку
    /// из отладочной сессии.
    func snapshot() {
        WindowSnapshot.write(window, named: "notch")
    }
}
