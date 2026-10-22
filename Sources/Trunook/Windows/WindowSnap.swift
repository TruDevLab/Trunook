import AppKit
import ApplicationServices
import TrunookXPC

/// Куда разложить окно, донесённое до чёлки.
///
/// Половины, трети и четверти — всегда от края экрана, углы и целиком.
/// Плитки на экране собраны по этим же группам — см. `WindowSnapBoard`.
enum WindowSlot: String, CaseIterable, Identifiable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case leftThird, rightThird, leftTwoThirds, rightTwoThirds
    case firstQuarter, fourthQuarter, leftThreeQuarters, rightThreeQuarters
    case leftTopQuarter, rightTopQuarter, leftBottomQuarter, rightBottomQuarter
    case fill, center

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: return t("Весь экран")
        case .center: return t("По центру, 85%")
        case .leftHalf: return t("Левая половина")
        case .rightHalf: return t("Правая половина")
        case .topHalf: return t("Верхняя половина")
        case .bottomHalf: return t("Нижняя половина")
        case .leftThird: return t("Левая треть")
        case .rightThird: return t("Правая треть")
        case .leftTwoThirds: return t("Левые две трети")
        case .rightTwoThirds: return t("Правые две трети")
        case .firstQuarter: return t("Левая четверть")
        case .fourthQuarter: return t("Правая четверть")
        case .leftThreeQuarters: return t("Левые три четверти")
        case .rightThreeQuarters: return t("Правые три четверти")
        case .leftTopQuarter: return t("Левый верхний угол")
        case .rightTopQuarter: return t("Правый верхний угол")
        case .leftBottomQuarter: return t("Левый нижний угол")
        case .rightBottomQuarter: return t("Правый нижний угол")
        }
    }

    /// Доля экрана, которую занимает окно: `x` и `y` от левого нижнего угла,
    /// как у координат AppKit. Из неё рисуется и значок плитки.
    var unit: CGRect {
        switch self {
        case .fill: return CGRect(x: 0, y: 0, width: 1, height: 1)
        case .center: return CGRect(x: 0.075, y: 0.075, width: 0.85, height: 0.85)
        case .leftHalf: return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .bottomHalf: return CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .leftThird: return CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1)
        case .rightThird: return CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .leftTwoThirds: return CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1)
        case .rightTwoThirds: return CGRect(x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 1)
        case .firstQuarter: return CGRect(x: 0, y: 0, width: 0.25, height: 1)
        case .fourthQuarter: return CGRect(x: 0.75, y: 0, width: 0.25, height: 1)
        case .leftThreeQuarters: return CGRect(x: 0, y: 0, width: 0.75, height: 1)
        case .rightThreeQuarters: return CGRect(x: 0.25, y: 0, width: 0.75, height: 1)
        case .leftTopQuarter: return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .rightTopQuarter: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .leftBottomQuarter: return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .rightBottomQuarter: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        }
    }

    /// Места, которые предлагается заполнить следующими окнами, по порядку.
    ///
    /// У половин, третей и четвертей от края остаток — одна полоса: половина
    /// дополняется второй половиной (и верхняя нижней), треть — двумя третями,
    /// четверть — тремя четвертями и наоборот. У угла — три оставшихся угла
    /// в порядке чтения: сначала сосед по ряду, потом нижний или верхний ряд.
    var followUps: [WindowSlot] {
        switch self {
        case .leftHalf: return [.rightHalf]
        case .rightHalf: return [.leftHalf]
        case .topHalf: return [.bottomHalf]
        case .bottomHalf: return [.topHalf]
        case .leftThird: return [.rightTwoThirds]
        case .rightThird: return [.leftTwoThirds]
        case .leftTwoThirds: return [.rightThird]
        case .rightTwoThirds: return [.leftThird]
        case .firstQuarter: return [.rightThreeQuarters]
        case .fourthQuarter: return [.leftThreeQuarters]
        case .leftThreeQuarters: return [.fourthQuarter]
        case .rightThreeQuarters: return [.firstQuarter]
        case .leftTopQuarter, .rightTopQuarter, .leftBottomQuarter, .rightBottomQuarter:
            return [.leftTopQuarter, .rightTopQuarter, .leftBottomQuarter, .rightBottomQuarter].filter { $0 != self }
        case .fill, .center: return []
        }
    }

    /// Место раскладки, ужатое так, чтобы не налезать на уже поставленные окна.
    ///
    /// Приложение может не дать окну ужаться до раскладки: табличный редактор не уже
    /// 713 точек при трети экрана в 504. Место по плану тогда наехало бы
    /// на него — поэтому оно отступает от настоящего края окна. Сторона
    /// отступа — по тому, с какой стороны окно и по какой оси нахлёст меньше:
    /// соседа слева двигаем по ширине, соседа сверху — по высоте.
    /// Окно, вставшее меньше раскладки, место не расширяет.
    static func fit(_ frame: CGRect, avoiding placed: [CGRect]) -> CGRect {
        var frame = frame
        for window in placed {
            let overlap = frame.intersection(window)
            guard !overlap.isNull, overlap.width > 1, overlap.height > 1 else { continue }
            if overlap.width <= overlap.height {
                if window.midX < frame.midX {
                    frame = CGRect(x: window.maxX, y: frame.minY, width: frame.maxX - window.maxX, height: frame.height)
                } else {
                    frame = CGRect(x: frame.minX, y: frame.minY, width: window.minX - frame.minX, height: frame.height)
                }
            } else if window.midY < frame.midY {
                frame = CGRect(x: frame.minX, y: window.maxY, width: frame.width, height: frame.maxY - window.maxY)
            } else {
                frame = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: window.minY - frame.minY)
            }
        }
        return frame
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

/// Разметка экрана плитками раскладок: где что стоит и что под курсором.
/// Чистые функции, под тестом.
///
/// Плитка стоит там, где окажется окно: углы — в углах экрана, верхняя
/// и нижняя половины — сверху и снизу посередине, весь экран и по центру —
/// в середине. Полосы во всю высоту — высокими плитками в среднем ряду,
/// по порядку середины окна: у края четверть, дальше треть, половина, две
/// трети, три четверти — и зеркально справа. Между плитками остаются
/// пустые места: точное положение важнее плотной сетки. Сверху под чёлкой —
/// плитка «Отмена», под ней — ряд экранов, если мониторов несколько.
///
/// Координаты — от левого верхнего угла экрана, как у окна разметки.
enum WindowSnapBoard {
    /// Что под курсором: раскладка или отмена.
    enum Target: Equatable {
        case slot(WindowSlot)
        case cancel
        /// Плашка экрана: номер в ряду экранов слева направо.
        case screen(Int)
    }

    /// Ячейка в долях области плиток: `x` слева, `y` сверху.
    struct Cell {
        let slot: WindowSlot
        let unit: CGRect
    }

    static let cells: [Cell] = {
        func cell(_ slot: WindowSlot, _ x: Double, _ y: Double, _ width: Double, _ height: Double) -> Cell {
            Cell(slot: slot, unit: CGRect(x: x, y: y, width: width, height: height))
        }
        // Три ряда: верхний и нижний — углы и половины по высоте, средний —
        // полосы во всю высоту и середина.
        let rowHeight = 0.2, middleTop = 0.25, middleHeight = 0.5, bottom = 1 - rowHeight
        let corner = 0.22, halfWidth = 0.28
        // Пять полос с каждой стороны в 0,41 ширины, середина — 0,14.
        let gap = 0.008, side = 0.41
        let strip = (side - 4 * gap) / 5
        let leftStrips: [WindowSlot] = [.firstQuarter, .leftThird, .leftHalf, .leftTwoThirds, .leftThreeQuarters]
        let rightStrips: [WindowSlot] = [.rightThreeQuarters, .rightTwoThirds, .rightHalf, .rightThird, .fourthQuarter]
        let centerX = side + 0.02, centerWidth = 1 - 2 * centerX
        let centerHeight = (middleHeight - 0.02) / 2

        var cells = [
            cell(.leftTopQuarter, 0, 0, corner, rowHeight),
            cell(.topHalf, 0.5 - halfWidth / 2, 0, halfWidth, rowHeight),
            cell(.rightTopQuarter, 1 - corner, 0, corner, rowHeight),
            cell(.fill, centerX, middleTop, centerWidth, centerHeight),
            cell(.center, centerX, middleTop + centerHeight + 0.02, centerWidth, centerHeight),
            cell(.leftBottomQuarter, 0, bottom, corner, rowHeight),
            cell(.bottomHalf, 0.5 - halfWidth / 2, bottom, halfWidth, rowHeight),
            cell(.rightBottomQuarter, 1 - corner, bottom, corner, rowHeight),
        ]
        for (index, slot) in leftStrips.enumerated() {
            cells.append(cell(slot, Double(index) * (strip + gap), middleTop, strip, middleHeight))
        }
        for (index, slot) in rightStrips.enumerated() {
            cells.append(cell(slot, 1 - side + Double(index) * (strip + gap), middleTop, strip, middleHeight))
        }
        return cells
    }()

    static let cancelSize = CGSize(width: 240, height: 40)
    /// Между чёлкой, отменой и плитками.
    static let gap: CGFloat = 12
    /// Поле плиток от краёв рабочей области.
    static let margin: CGFloat = 12
    /// Плитка рисуется меньше своей ячейки — между соседями виден зазор.
    static let spacing: CGFloat = 8

    struct Layout: Equatable {
        let cancel: CGRect
        let area: CGRect
        let tiles: [WindowSlot: CGRect]
        /// Плашки экранов под отменой — по одной на монитор, в порядке
        /// слева направо. Пусто, если монитор один.
        var screens: [CGRect] = []
    }

    static let screenChipSize = CGSize(width: 190, height: 36)
    static let screenChipGap: CGFloat = 8

    /// Ряд плашек экранов по центру под отменой. Плашки уже, если все
    /// в обычную ширину не влезают.
    static func screenChips(count: Int, centerX: CGFloat, top: CGFloat, width: CGFloat) -> [CGRect] {
        guard count > 1 else { return [] }
        let fit = (width - CGFloat(count - 1) * screenChipGap) / CGFloat(count)
        let chip = min(screenChipSize.width, max(fit, 60))
        let total = CGFloat(count) * chip + CGFloat(count - 1) * screenChipGap
        let left = (centerX - total / 2).rounded()
        return (0..<count).map { index in
            CGRect(x: left + CGFloat(index) * (chip + screenChipGap), y: top,
                   width: chip, height: screenChipSize.height)
        }
    }

    /// Разметка экрана. Всё — в координатах AppKit: экран, рабочая область
    /// без полосы меню и Dock, чёлка. Результат — от левого верхнего угла экрана.
    /// `screenCount` — сколько мониторов: больше одного — под отменой ряд экранов.
    static func layout(screen: CGRect, visible: CGRect, notch: CGRect, screenCount: Int = 1) -> Layout {
        let local = { (rect: CGRect) in
            CGRect(x: rect.minX - screen.minX, y: screen.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        let notchLocal = local(notch)
        let visibleLocal = local(visible)
        let cancel = CGRect(
            x: (notchLocal.midX - cancelSize.width / 2).rounded(),
            y: max(notchLocal.maxY, visibleLocal.minY) + gap,
            width: cancelSize.width,
            height: cancelSize.height
        )
        let screens = screenChips(count: screenCount, centerX: cancel.midX, top: cancel.maxY + gap,
                                  width: visibleLocal.width - 2 * margin)
        let top = (screens.first?.maxY ?? cancel.maxY) + gap
        let area = CGRect(
            x: visibleLocal.minX + margin,
            y: top,
            width: visibleLocal.width - 2 * margin,
            height: max(visibleLocal.maxY - margin - top, 0)
        )
        var tiles: [WindowSlot: CGRect] = [:]
        for cell in cells {
            tiles[cell.slot] = CGRect(
                x: (area.minX + area.width * cell.unit.minX).rounded(),
                y: (area.minY + area.height * cell.unit.minY).rounded(),
                width: (area.width * cell.unit.width).rounded(),
                height: (area.height * cell.unit.height).rounded()
            )
        }
        return Layout(cancel: cancel, area: area, tiles: tiles, screens: screens)
    }

    /// Что под точкой. Точка — от левого верхнего угла экрана.
    ///
    /// Узкий зазор между плитками достаётся ближайшей: плитка не должна гаснуть
    /// на стыке. Широкие пустые места — ничьи: отпустили там — выбор щелчком.
    static func target(at point: CGPoint, in layout: Layout) -> Target? {
        if layout.cancel.insetBy(dx: -spacing, dy: -spacing).contains(point) { return .cancel }
        if let index = layout.screens.firstIndex(where: {
            $0.insetBy(dx: -screenChipGap / 2, dy: -screenChipGap / 2).contains(point)
        }) {
            return .screen(index)
        }
        var best: (slot: WindowSlot, distance: CGFloat)?
        for cell in cells {
            guard let rect = layout.tiles[cell.slot] else { continue }
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
            let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            let distance = hypot(dx, dy)
            if distance <= reach, distance < (best?.distance ?? .infinity) { best = (cell.slot, distance) }
        }
        return best.map { .slot($0.slot) }
    }

    /// Насколько далеко от плитки курсор ещё считается на ней.
    static let reach: CGFloat = 12
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

    static func position(of element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func size(of element: AXUIElement) -> CGSize? {
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

    /// Окна приложения в порядке, какой отдаёт Универсальный доступ.
    static func windows(ofApp pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows
    }

    static func title(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Поднять окно поверх и сделать его приложение передним.
    ///
    /// Через Универсальный доступ, а не `NSRunningApplication.activate`:
    /// фоновому приложению система с macOS 14 передавать активность
    /// не обязана и молча отказывает.
    static func raise(_ element: AXUIElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
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
