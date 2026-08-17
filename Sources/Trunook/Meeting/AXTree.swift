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

    static func application(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
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
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
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
        if predicate(element) { return element }
        guard maxDepth > 0 else { return nil }
        for child in children(of: element) {
            if let found = firstDescendant(of: child, maxDepth: maxDepth - 1, where: predicate) {
                return found
            }
        }
        return nil
    }

    /// Собирает все кнопки поддерева — для разведки и для поиска по подписи.
    static func buttons(of element: AXUIElement, maxDepth: Int = 24) -> [(element: AXUIElement, labels: [String])] {
        var result: [(AXUIElement, [String])] = []

        func walk(_ node: AXUIElement, depth: Int) {
            guard depth <= maxDepth else { return }
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

        func walk(_ node: AXUIElement, depth: Int) {
            guard depth <= maxDepth else { return }
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
