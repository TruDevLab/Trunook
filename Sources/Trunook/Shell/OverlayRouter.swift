import TrunookXPC
import AppKit

/// Кто сейчас поверх выреза и по какому правилу он закроется.
///
/// Накладки занимают одно место: меню команд, история буфера, ответ модели,
/// полка и меню функций рисуются в одном и том же прямоугольнике. Значит
/// открытие любой из них обязано закрывать предыдущую, и держать это правило
/// нужно в одном месте, а не в каждой кнопке.
final class OverlayRouter {
    private let state: NotchState
    private let host: NotchWindowHost

    /// Накладка сменилась. Побочные действия — вибрация, плашки, зона приёма
    /// файлов — остаются за контроллером: службы принадлежат ему.
    var onChange: ((NotchState.Overlay?) -> Void)?

    /// Накладка закрывается по уходу курсора, но только после того, как он
    /// в неё хоть раз зашёл: вызванная клавишей иначе схлопнулась бы сразу,
    /// ведь курсор в этот момент где угодно.
    private var cursorEntered = false

    init(state: NotchState, host: NotchWindowHost) {
        self.state = state
        self.host = host
    }

    var current: NotchState.Overlay? { state.overlay }

    /// Единая точка смены накладки.
    func set(_ overlay: NotchState.Overlay?) {
        guard state.overlay != overlay else { return }
        state.overlay = overlay
        cursorEntered = false
        DebugLog.write("накладка: \(overlay.map(Self.name(of:)) ?? "закрыта")")
        onChange?(overlay)
    }

    /// Клавишей накладку и открывают, и убирают тем же сочетанием.
    func toggle(_ overlay: NotchState.Overlay) {
        set(state.overlay == overlay ? nil : overlay)
    }

    func close() {
        set(nil)
    }

    /// Нажатие мимо накладки или Esc.
    ///
    /// Не всякая накладка этому поддаётся: телесуфлер держат открытым, пока
    /// работают в чужом окне, и нажатие мимо для него — обычная работа,
    /// а не «я закончил». Правило живёт в самой накладке.
    func dismiss() {
        guard state.overlay?.closesOnClickOutside == true else { return }
        set(nil)
    }

    /// Курсор зашёл в накладку и вышел — закрываем.
    func updateHover(at location: CGPoint) {
        // Не всякая накладка закрывается уходом курсора: с полкой и ответом
        // модели работают руками, и курсор заведомо уходит за их границы.
        // Правило живёт в самой накладке — см. `closesOnCursorExit`.
        //
        // Щелчок мимо ловит глобальный монитор нажатий: он срабатывает только
        // на события, ушедшие в чужое приложение, то есть ровно на «мимо».
        guard state.overlay?.closesOnCursorExit == true else { return }

        if rect.contains(location) {
            cursorEntered = true
        } else if cursorEntered {
            set(nil)
        }
    }

    /// Прямоугольник накладки в координатах экрана. Размер берётся тем же
    /// расчётом, что и зона нажатий, — иначе они разойдутся.
    private var rect: CGRect {
        guard state.overlay != nil, let size = host.currentContentSize else { return .zero }
        return host.topAlignedRect(size: size)
    }

    static func name(of overlay: NotchState.Overlay) -> String {
        switch overlay {
        case .commands: return "меню команд"
        case .clipboard: return "история буфера"
        case .assistant: return "ответ модели"
        case .shelf: return "полка"
        case .hub: return "меню функций"
        case .timer: return "таймер"
        case .monitor: return "нагрузка"
        case .teleprompter: return "телесуфлер"
        }
    }
}
