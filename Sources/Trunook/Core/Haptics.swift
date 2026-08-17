import AppKit

/// Виброотклик на трекпаде.
///
/// Работает только на трекпадах с Force Touch и молча ничего не делает
/// на обычной мыши — проверять тип устройства не нужно.
enum Haptics {
    static func tap(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
        guard Settings.shared.hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
