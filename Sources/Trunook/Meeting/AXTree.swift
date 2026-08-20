import TrunookXPC
import AppKit
import ApplicationServices

/// Обход дерева Универсального доступа чужих приложений.
///
/// Через него читается состояние страницы встречи и нажимаются её кнопки:
/// у Телемоста нет ни словаря AppleScript, ни внешнего API, а клавиши
/// работают только в активной вкладке. Дерево доступности — единственный
/// способ управлять встречей, не перехватывая фокус.
enum AXTree {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    // MARK: - Приведение значений из чужого дерева
    //
    // Атрибут отвечает `CFTypeRef` — «что-нибудь из CoreFoundation», — и что
    // именно, решает чужое приложение. Проверять тип приходится сравнением
    // `CFTypeID` руками: `as?` для типов CoreFoundation Swift компилировать
    // отказывается — считает такое приведение всегда успешным и прямо советует
    // сверить идентификатор, — а `as!` не проверка вовсе, а переименование.
    // Раньше здесь стояло именно оно: неожиданный тип уходил бы в функцию
    // Универсального доступа как элемент, которым не является.

    /// Значение как элемент дерева — если это действительно элемент.
    static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        return (value as! AXUIElement)
    }

    /// Значение как упакованная величина — точка, размер, диапазон.
    static func packed(_ value: CFTypeRef?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        return (value as! AXValue)
    }

    /// Потолок числа узлов на один обход.
    ///
    /// Одной глубины мало: у веб-страницы на каждом уровне бывают тысячи
    /// узлов, и обход, ограниченный только глубиной, не ограничен ничем.
    /// А каждый шаг здесь — обращение к чужому процессу через Mach,
    /// миллисекунда с лишним, так что «долго» означает минуты.
    ///
    /// Ловилось живьём: с тяжёлой страницей в браузере приложение вставало
    /// на запуске насмерть — обход шёл из `MeetingService.start()`, и до
    /// значка в строке состояния дело не доходило вовсе.
    static let nodeBudget = 3000

    /// Сколько ждать ответа от чужого приложения.
    ///
    /// По умолчанию Универсальный доступ ждёт секундами, а обращений
    /// за обход тысячи. Ставится на элемент приложения — система
    /// распространяет срок на все сообщения этому приложению.
    private static let messagingTimeout: Float = 0.5

    static func application(pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func windows(of element: AXUIElement) -> [AXUIElement] {
        children(of: element, attribute: kAXWindowsAttribute)
    }

    static func children(of element: AXUIElement, attribute: String = kAXChildrenAttribute) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let list = value as? [AXUIElement]
        else { return [] }
        return list
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    static func role(of element: AXUIElement) -> String {
        string(element, kAXRoleAttribute) ?? ""
    }

    /// Все подписи элемента: разные движки кладут текст в разные атрибуты.
    static func labels(of element: AXUIElement) -> [String] {
        [
            string(element, kAXTitleAttribute),
            string(element, kAXDescriptionAttribute),
            string(element, kAXHelpAttribute),
            string(element, kAXValueAttribute),
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
    }

    /// Адрес открытой страницы. Chromium и WebKit кладут его в `AXURL`
    /// веб-области — читать адресную строку браузера не нужно, а значит
    /// и разбирать её вид в каждом браузере тоже.
    static func url(of element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &value) == .success
        else { return nil }
        return value as? URL
    }

    /// Экранный прямоугольник элемента. У скрытых и вспомогательных копий
    /// он нулевой или вынесен далеко за пределы окна.
    static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = packed(positionValue), let extent = packed(sizeValue),
              AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(extent, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func isEnabled(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &value) == .success
        else { return true }
        return (value as? Bool) ?? true
    }

    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    /// Ставит фокус на элемент и «нажимает» его с клавиатуры.
    ///
    /// Единственный способ, который на веб-встречах действительно работает.
    /// Два очевидных отвергнуты по результатам проверки на живом Телемосте —
    /// обе пробы возвращали успех, а подпись кнопки не менялась:
    ///
    /// - `AXPress` страница не слышит: веб-приложение слушает события
    ///   указателя, а не действие доступности.
    /// - Синтетический клик `CGEvent`, адресованный процессу браузера, тоже
    ///   не доходит — Chromium не маршрутизирует такие события в содержимое
    ///   неактивного окна.
    ///
    /// Кнопка же, получившая фокус, срабатывает на пробел по стандарту
    /// доступности, и обработчик страницы видит обычное клавиатурное событие.
    /// Событие адресовано процессу браузера, поэтому фокус системы остаётся
    /// у активного приложения, а курсор не двигается.
    static func focusAndKey(_ element: AXUIElement, pid: pid_t, keyCode: CGKeyCode) -> Bool {
        let focused = AXUIElementSetAttributeValue(
            element, kAXFocusedAttribute as CFString, kCFBooleanTrue
        ) == .success

        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }

        down.postToPid(pid)
        up.postToPid(pid)
        return focused
    }

    /// Ищет вглубь первый элемент, удовлетворяющий условию.
    ///
    /// Глубина ограничена: дерево веб-страницы бывает в сотни уровней,
    /// а элементы управления встречей лежат близко к корню окна.
    static func firstDescendant(
        of element: AXUIElement,
        maxDepth: Int = 24,
        where predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        var budget = nodeBudget
        return firstDescendant(of: element, maxDepth: maxDepth, budget: &budget, where: predicate)
    }

    private static func firstDescendant(
        of element: AXUIElement,
        maxDepth: Int,
        budget: inout Int,
        where predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        guard budget > 0 else { return nil }
        budget -= 1
        if predicate(element) { return element }
        guard maxDepth > 0 else { return nil }
        for child in children(of: element) {
            if let found = firstDescendant(
                of: child, maxDepth: maxDepth - 1, budget: &budget, where: predicate
            ) {
                return found
            }
        }
        return nil
    }

    /// Собирает все кнопки поддерева — для разведки и для поиска по подписи.
    static func buttons(of element: AXUIElement, maxDepth: Int = 24) -> [(element: AXUIElement, labels: [String])] {
        var result: [(AXUIElement, [String])] = []
        var budget = nodeBudget

        func walk(_ node: AXUIElement, depth: Int) {
            guard depth <= maxDepth, budget > 0 else { return }
            budget -= 1
            let role = role(of: node)
            if role == kAXButtonRole || role == kAXCheckBoxRole || role == "AXToggleButton" {
                let labels = labels(of: node)
                if !labels.isEmpty { result.append((node, labels)) }
            }
            for child in children(of: node) {
                walk(child, depth: depth + 1)
            }
        }

        walk(element, depth: 0)
        return result
    }

    /// Все веб-области окна: у браузера со вкладками их может быть несколько,
    /// если движок держит в дереве и фоновые.
    static func webAreas(in window: AXUIElement, maxDepth: Int = 14) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var budget = nodeBudget

        func walk(_ node: AXUIElement, depth: Int) {
            guard depth <= maxDepth, budget > 0 else { return }
            budget -= 1
            if role(of: node) == "AXWebArea" {
                result.append(node)
                return
            }
            for child in children(of: node) {
                walk(child, depth: depth + 1)
            }
        }

        walk(window, depth: 0)
        return result
    }

    /// Содержимое страницы в браузере. Кнопки самой страницы лежат внутри
    /// него, а не среди кнопок окна — те принадлежат интерфейсу браузера:
    /// вкладкам, панели навигации, боковой панели.
    static func webArea(in window: AXUIElement) -> AXUIElement? {
        firstDescendant(of: window, maxDepth: 12) { role(of: $0) == "AXWebArea" }
    }

    /// Печатает кнопки окна — калибровка подписей без живой встречи невозможна.
    static func dumpButtons(of window: AXUIElement, title: String) {
        guard let area = webArea(in: window) else {
            DebugLog.write("— окно «\(title)»: веб-область не найдена —")
            return
        }
        let found = buttons(of: area, maxDepth: 40)
        DebugLog.write("— страница «\(title)»: кнопок \(found.count) —")
        for (element, labels) in found.prefix(80) {
            let box = frame(of: element).map {
                String(format: "%.0f×%.0f в (%.0f, %.0f)", $0.width, $0.height, $0.minX, $0.minY)
            } ?? "нет рамки"
            DebugLog.write("    \(labels.first ?? "?") — \(box), доступна=\(isEnabled(element))")
        }
    }
}
