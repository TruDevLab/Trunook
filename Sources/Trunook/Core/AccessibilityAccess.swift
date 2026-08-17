import AppKit
import ApplicationServices

/// Универсальный доступ: нужен быстрым командам (чтение выделенного текста)
/// и управлению встречей (нажатие кнопок на странице).
///
/// В отличие от Календаря и Напоминаний система не даёт запросить его
/// программно: `AXIsProcessTrustedWithOptions` только показывает диалог
/// со ссылкой в Системные настройки, а галочку ставит человек руками.
/// Поэтому состояние приходится опрашивать, а не ждать обратного вызова.
enum AccessibilityAccess {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Системный диалог с предложением открыть нужный раздел настроек.
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func openSettings() {
        let address = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}
