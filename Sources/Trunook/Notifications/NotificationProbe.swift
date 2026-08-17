import TrunookXPC
import AppKit
import ApplicationServices

/// Разведка: что вообще видно в баннерах Центра уведомлений.
///
/// База уведомлений (`group.com.apple.usernoted`) закрыта TCC и требует
/// «Полного доступа к диску». Остаётся дерево Универсального доступа процесса
/// NotificationCenter — тот же механизм, которым пользуются приложения,
/// закрывающие баннеры за пользователя.
///
/// Это именно зонд: он ничего не показывает в вырезе, только печатает в журнал
/// то, что удалось прочитать. Пока не подтверждено, что содержимое читается
/// устойчиво, строить на этом функцию рано.
enum NotificationProbe {
    private static let bundleID = "com.apple.notificationcenterui"

    /// Запрашивает Универсальный доступ, показывая системный диалог.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        DebugLog.write("уведомления: Универсальный доступ \(trusted ? "выдан" : "не выдан")")
    }

    static func dump() {
        guard AXIsProcessTrusted() else {
            DebugLog.write("уведомления: нет Универсального доступа, читать нечем")
            requestAccessibility()
            return
        }

        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID).first
        else {
            DebugLog.write("уведомления: процесс NotificationCenter не найден")
            return
        }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        var windows: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element, kAXWindowsAttribute as CFString, &windows
        )

        guard status == .success, let list = windows as? [AXUIElement] else {
            DebugLog.write("уведомления: окна недоступны, код \(status.rawValue)")
            return
        }

        DebugLog.write("— баннеров на экране: \(list.count) —")
        for window in list {
            collect(from: window, depth: 0)
        }
    }

    /// Обходит дерево вглубь и печатает всё текстовое, что попадётся.
    private static func collect(from element: AXUIElement, depth: Int) {
        guard depth < 8 else { return }

        let role = string(of: element, attribute: kAXRoleAttribute) ?? "?"
        let texts = [
            string(of: element, attribute: kAXTitleAttribute),
            string(of: element, attribute: kAXValueAttribute),
            string(of: element, attribute: kAXDescriptionAttribute),
        ].compactMap { $0 }.filter { !$0.isEmpty }

        if !texts.isEmpty {
            let indent = String(repeating: "  ", count: depth)
            DebugLog.write("  \(indent)\(role): \(texts.joined(separator: " | "))")
        }

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &children
        ) == .success, let list = children as? [AXUIElement] else { return }

        for child in list {
            collect(from: child, depth: depth + 1)
        }
    }

    private static func string(of element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
