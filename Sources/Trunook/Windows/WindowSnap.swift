import AppKit
import ApplicationServices
import TrunookXPC

/// Куда разложить окно, донесённое до чёлки.
///
/// Посередине — на весь экран и по центру на 85%, по бокам
/// зеркально: половина, две трети, треть, верхняя и нижняя четверть.
enum WindowSlot: String, CaseIterable, Identifiable {
    case leftTwoThirds, leftHalf, leftThird, leftTopQuarter, leftBottomQuarter
    case fill, center
    case rightTwoThirds, rightHalf, rightThird, rightTopQuarter, rightBottomQuarter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: return t("Весь экран")
        case .center: return t("По центру, 85%")
        case .leftTwoThirds: return t("Левые две трети")
        case .rightTwoThirds: return t("Правые две трети")
        case .leftHalf: return t("Левая половина")
        case .leftThird: return t("Левая треть")
        case .leftTopQuarter: return t("Левая верхняя четверть")
        case .leftBottomQuarter: return t("Левая нижняя четверть")
        case .rightHalf: return t("Правая половина")
        case .rightThird: return t("Правая треть")
        case .rightTopQuarter: return t("Правая верхняя четверть")
        case .rightBottomQuarter: return t("Правая нижняя четверть")
        }
    }

    /// Доля экрана, которую занимает окно: `x` и `y` от левого нижнего угла,
    /// как у координат AppKit. Из неё рисуется и значок плитки.
    var unit: CGRect {
        switch self {
        case .fill: return CGRect(x: 0, y: 0, width: 1, height: 1)
        case .center: return CGRect(x: 0.075, y: 0.075, width: 0.85, height: 0.85)
        case .leftTwoThirds: return CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1)
        case .rightTwoThirds: return CGRect(x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 1)
        case .leftHalf: return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .leftThird: return CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1)
        case .leftTopQuarter: return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .leftBottomQuarter: return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .rightHalf: return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .rightThird: return CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .rightTopQuarter: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .rightBottomQuarter: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        }
    }

    struct Edges: OptionSet {
        let rawValue: Int
        static let right = Edges(rawValue: 1)
        static let bottom = Edges(rawValue: 2)
        /// По центру: окно больше раскладки встаёт серединой на её середину.
        static let center = Edges(rawValue: 4)
    }

    /// К каким краям экрана прижата раскладка справа и снизу: к ним
    /// прижимается окно, которому раскладка мала.
    var edges: Edges {
        if self == .center { return .center }
        var edges: Edges = []
        if unit.minX > 0.001, unit.maxX > 0.999 { edges.insert(.right) }
        if unit.minY < 0.001, unit.maxY < 0.999 { edges.insert(.bottom) }
        return edges
    }

    /// Рамка окна в рабочей области экрана — без полосы меню и Dock.
    /// Целые точки: окно на полуточке у многих приложений размывает текст.
    func frame(in visible: CGRect) -> CGRect {
        let u = unit
        return CGRect(
            x: visible.minX + (visible.width * u.minX).rounded(),
            y: visible.minY + (visible.height * u.minY).rounded(),
            width: (visible.width * u.width).rounded(),
            height: (visible.height * u.height).rounded()
        )
    }
}

/// Раскладка плиток в панели и попадание курсора — чистые функции, под тестом.
///
/// Семь колонок: три колонки левой стороны, широкая колонка посередине —
/// «весь экран» над «по центру, 85%», — три колонки правой. Колонка с одной
/// плиткой — высокая, в ней раскладка во всю высоту: у внешнего края половина.
/// Дальше к середине — две трети над третью и четверти. Правая сторона —
/// зеркало левой.
enum WindowSnapLayout {
    /// Уже, чем было при пяти колонках: семь колонок по-прежнему должны
    /// помещаться в панель разумной ширины.
    static var tileWidth: CGFloat { NotchStyle.scaled(56) }
    static var tileHeight: CGFloat { NotchStyle.scaled(40) }
    static var centerWidth: CGFloat { NotchStyle.scaled(96) }
    static var spacing: CGFloat { NotchStyle.gridSpacing }
    /// Под плитками — строка с названием выбранной раскладки.
    static var captionHeight: CGFloat { NotchStyle.scaled(18) }

    /// Колонки слева направо; у боковых — верхняя и нижняя плитка.
    static let columns: [[WindowSlot]] = [
        [.leftHalf],
        [.leftTwoThirds, .leftThird],
        [.leftTopQuarter, .leftBottomQuarter],
        [.fill, .center],
        [.rightTopQuarter, .rightBottomQuarter],
        [.rightTwoThirds, .rightThird],
        [.rightHalf],
    ]

    static var gridHeight: CGFloat { 2 * tileHeight + spacing }
    static var contentWidth: CGFloat {
        columns.indices.reduce(0) { $0 + columnWidth($1) } + CGFloat(columns.count - 1) * spacing
    }
    static var contentHeight: CGFloat { gridHeight + spacing + captionHeight }

    static var width: CGFloat { contentWidth + 2 * NotchStyle.bodyInset }

    static func height(notchHeight: CGFloat) -> CGFloat {
        NotchStyle.height(notchHeight: notchHeight, contentHeight: contentHeight)
    }

    static func columnWidth(_ index: Int) -> CGFloat {
        columns[index].contains(.fill) ? centerWidth : tileWidth
    }

    /// Плитка одна в колонке — высокая, во всю сетку.
    static func tileHeight(of slot: WindowSlot) -> CGFloat {
        columns.first { $0.contains(slot) }?.count == 1 ? gridHeight : tileHeight
    }

    /// Плитка под точкой. Точка — от левого верхнего угла панели.
    ///
    /// Промежутки и поля достаются ближайшей плитке, а ниже сетки и выше неё
    /// точка прижимается к сетке: окно держат на весу, и промахнуться мимо
    /// всех плиток, стоя над панелью, не должно получаться.
    static func slot(at point: CGPoint, notchHeight: CGFloat) -> WindowSlot {
        let left = NotchStyle.bodyInset
        let top = notchHeight + NotchStyle.topGap
        let x = point.x - left
        let y = min(max(point.y - top, 0), gridHeight)

        var edge: CGFloat = 0
        var column = columns.count - 1
        for index in columns.indices {
            let right = edge + columnWidth(index) + spacing / 2
            if x < right {
                column = index
                break
            }
            edge += columnWidth(index) + spacing
        }
        let slots = columns[column]
        guard slots.count == 2 else { return slots[0] }
        return y < gridHeight / 2 ? slots[0] : slots[1]
    }
}

/// Окно, которое тащат прямо сейчас: какое оно и сдвинулось ли.
///
/// Перетаскивание окна система приложению не сообщает никак — ни событием,
/// ни уведомлением. Узнаётся оно по делу: в миг нажатия берётся окно под
/// курсором через Универсальный доступ и запоминается его место; сдвинулось
/// окно, а размер остался прежним — значит, его тащат за заголовок.
/// Потянули за край — меняется и размер, и это не перенос.
final class DraggedWindow {
    let element: AXUIElement
    private let origin: CGPoint
    private let size: CGSize
    /// Окно сдвинулось с места — его несут.
    private(set) var isMoving = false

    /// Окно под точкой, где его держат. Точка — в координатах AppKit.
    init?(pressedAt point: CGPoint) {
        guard AccessibilityAccess.isTrusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        // Спрашиваем чужое приложение — оно может висеть. Долго ждать его
        // на главном потоке нельзя.
        AXUIElementSetMessagingTimeout(system, 0.2)
        var hit: AXUIElement?
        let ax = Self.axPoint(point)
        guard AXUIElementCopyElementAtPosition(system, Float(ax.x), Float(ax.y), &hit) == .success,
              let hit else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)
        guard pid != ProcessInfo.processInfo.processIdentifier,
              let window = Self.window(of: hit),
              let position = Self.position(of: window),
              let size = Self.size(of: window)
        else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.2)
        element = window
        origin = position
        self.size = size
    }

    /// Сверить место окна. Однажды сдвинутое остаётся «несомым» до конца
    /// нажатия: опрашивать дальше незачем.
    func refresh() {
        guard !isMoving, let position = Self.position(of: element), let now = Self.size(of: element) else { return }
        let moved = hypot(position.x - origin.x, position.y - origin.y) >= 2
        let resized = abs(now.width - size.width) >= 1 || abs(now.height - size.height) >= 1
        if moved, !resized {
            isMoving = true
            DebugLog.write("окна: тащат окно")
        }
    }

    /// Разложить окно по месту на экране.
    ///
    /// Три приёма, и каждый лечит своё:
    ///
    /// - **Размер, место, снова размер.** Приложение, которому окно на новом
    ///   месте не влезает, урезает размер под старое место; и наоборот —
    ///   большое окно не пускают на место у края экрана.
    /// - **Расширенный режим доступности выключается на время.** Chromium
    ///   и Electron, заметив клиента доступности, включают у себя
    ///   `AXEnhancedUserInterface` — и тогда анимируют смену рамки, а вторая
    ///   команда посреди анимации теряется: окно переезжает, но не меняет
    ///   размер. Так же поступают сторонние менеджеры окон.
    /// - **Сверка после.** Через долю секунды рамка читается обратно; не та —
    ///   ставится ещё раз. Система, доигрывая свой перенос окна, иногда
    ///   возвращает его на место отпускания поверх нашей раскладки.
    ///
    /// `edges` — к каким краям экрана раскладка прижата. Окно, которое
    /// приложение не пускает меньше своего минимума (у одного Electron-приложения это 600 точек
    /// при трети экрана в 504), прижимается к ним, а не вылезает за край.
    static func place(_ element: AXUIElement, in frame: CGRect, edges: WindowSlot.Edges = [], attempt: Int = 1) {
        let topLeft = axPoint(CGPoint(x: frame.minX, y: frame.maxY))
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        let enhanced = flag("AXEnhancedUserInterface", of: app)
        if enhanced { setFlag("AXEnhancedUserInterface", false, of: app) }

        setSize(frame.size, of: element)
        setPosition(topLeft, of: element)
        setSize(frame.size, of: element)

        if enhanced { setFlag("AXEnhancedUserInterface", true, of: app) }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let position = Self.position(of: element), let size = Self.size(of: element) else { return }
            let off = max(abs(position.x - topLeft.x), abs(position.y - topLeft.y),
                          abs(size.width - frame.width), abs(size.height - frame.height))
            DebugLog.write("окна: попытка \(attempt), вышло \(Int(position.x)),\(Int(position.y)) "
                + "\(Int(size.width))×\(Int(size.height)), ждали \(Int(topLeft.x)),\(Int(topLeft.y)) "
                + "\(Int(frame.width))×\(Int(frame.height))\(enhanced ? ", режим доступности был включён" : "")")
            guard off > 2 else { return }
            let sizeRefused = abs(size.width - frame.width) > 2 || abs(size.height - frame.height) > 2
            if sizeRefused, attempt >= 2 {
                // Размер не дали и со второго раза — это минимум приложения.
                // Повторять бесполезно: прижимаем окно к краям раскладки.
                var anchored = topLeft
                if edges.contains(.right) { anchored.x = topLeft.x + frame.width - size.width }
                if edges.contains(.bottom) { anchored.y = topLeft.y + frame.height - size.height }
                if edges.contains(.center) {
                    anchored.x = topLeft.x + (frame.width - size.width) / 2
                    anchored.y = topLeft.y + (frame.height - size.height) / 2
                }
                if anchored != position { setPosition(anchored, of: element) }
                DebugLog.write("окна: приложение не даёт размер меньше \(Int(size.width))×\(Int(size.height)) — прижали к краю")
                return
            }
            if attempt < 3 { place(element, in: frame, edges: edges, attempt: attempt + 1) }
        }
    }

    private static func flag(_ name: String, of element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return false }
        return (value as? Bool) == true
    }

    private static func setFlag(_ name: String, _ on: Bool, of element: AXUIElement) {
        AXUIElementSetAttributeValue(element, name as CFString, (on ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef)
    }

    // MARK: - Универсальный доступ

    /// AppKit считает `y` снизу основного экрана, Универсальный доступ —
    /// сверху. Основной экран — первый в списке, у него начало в нуле.
    static func axPoint(_ point: CGPoint) -> CGPoint {
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: point.x, y: height - point.y)
    }

    private static func window(of element: AXUIElement) -> AXUIElement? {
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        if (role as? String) == kAXWindowRole as String { return element }
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        return (window as! AXUIElement)
    }

    private static func position(of element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func size(of element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    private static func setPosition(_ point: CGPoint, of element: AXUIElement) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        let result = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        if result != .success { DebugLog.write("окна: место не поставилось — \(result.rawValue)") }
    }

    private static func setSize(_ size: CGSize, of element: AXUIElement) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        let result = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        if result != .success { DebugLog.write("окна: размер не поставился — \(result.rawValue)") }
    }

    /// Рамка окна в координатах AppKit — чтобы вернуть его, как было.
    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = position(of: element), let size = size(of: element) else { return nil }
        let bottomLeft = axPoint(CGPoint(x: position.x, y: position.y + size.height))
        return CGRect(origin: bottomLeft, size: size)
    }

    /// Окно переднего приложения — для отладочной раскладки без перетаскивания.
    static func frontmost() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.2)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        return (window as! AXUIElement)
    }
}
