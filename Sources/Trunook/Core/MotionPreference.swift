import AppKit
import TrunookXPC

/// Системные настройки доступности, которые касаются движения и прозрачности.
///
/// Одно место на всё приложение, а не проверка по месту, и причин две.
///
/// Первая — настройку меняют, пока приложение работает, и без подписки
/// на уведомление половина экрана жила бы по старому правилу до перезапуска.
/// Уведомление приходит из своего центра — `NSWorkspace.notificationCenter`, —
/// а не из общего: подписка на общий молчит.
///
/// Вторая — таких мест много: бегущая строка, пружина под нажатием, мурчание,
/// демонстрация в окне знакомства. Разложенная по ним проверка неизбежно
/// разъехалась бы, а «уменьшить движение» работает только целиком: экран,
/// где половина замерла, а половина дёргается, хуже обоих чистых случаев.
///
/// Общим объектом, а не значением в теле вида: `@State` в этом тулчейне
/// недоступен — по той же причине так устроены `HoverTracker`
/// и `NotchHintTracker`.
final class MotionPreference: ObservableObject {
    static let shared = MotionPreference()

    /// «Универсальный доступ» → «Монитор» → «Уменьшить движение».
    @Published private(set) var reduceMotion: Bool

    /// Там же: «Уменьшить прозрачность».
    ///
    /// Читается вместе с движением, хотя нужна будет позже: обе настройки
    /// приходят одним уведомлением, и разносить их по разным местам значило бы
    /// подписываться на него дважды.
    @Published private(set) var reduceTransparency: Bool

    /// Там же: «Увеличить контраст». Окна с цветным фоном переходят
    /// на сплошной: текст поверх пятен читается хуже.
    @Published private(set) var increaseContrast: Bool

    private init() {
        let workspace = NSWorkspace.shared
        reduceMotion = workspace.accessibilityDisplayShouldReduceMotion
        reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        increaseContrast = workspace.accessibilityDisplayShouldIncreaseContrast

        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(optionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @objc private func optionsChanged() {
        let workspace = NSWorkspace.shared
        let motion = workspace.accessibilityDisplayShouldReduceMotion
        let transparency = workspace.accessibilityDisplayShouldReduceTransparency
        let contrast = workspace.accessibilityDisplayShouldIncreaseContrast
        guard motion != reduceMotion || transparency != reduceTransparency || contrast != increaseContrast else { return }
        reduceMotion = motion
        reduceTransparency = transparency
        increaseContrast = contrast
        DebugLog.write("доступность: движение \(motion ? "уменьшено" : "обычное"), "
                       + "прозрачность \(transparency ? "уменьшена" : "обычная")")
    }
}
