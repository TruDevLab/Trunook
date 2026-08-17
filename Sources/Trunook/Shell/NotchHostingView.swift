import AppKit
import SwiftUI

/// Подложка SwiftUI, которая ловит мышь только внутри видимой формы.
///
/// Окно всегда максимального размера, а форма занимает его лишь частично.
/// Без этого ограничения панель, ставшая интерактивной, съедала бы нажатия
/// по меню-бару и рабочему столу вокруг выреза — в прозрачных углах окна.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// Размер видимой формы. Прямоугольник попаданий считается из него здесь,
    /// а не снаружи: `NSHostingView` перевёрнут, и вычислять координаты
    /// в вызывающем коде — верный способ ошибиться знаком.
    var visibleSize: CGSize = .zero {
        didSet { needsDisplay = oldValue != visibleSize }
    }

    /// Нажатие правой кнопкой по вырезу. Ловится здесь, а не жестом SwiftUI:
    /// своего жеста для правой кнопки у него нет, а `contextMenu` показал бы
    /// системное меню — нам же нужна собственная накладка.
    var onRightClick: (() -> Void)?

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) не используется")
    }

    /// Форма прижата к верхней кромке окна и отцентрована по горизонтали.
    private var interactiveRect: CGRect {
        guard visibleSize != .zero else { return .zero }
        return CGRect(
            x: (bounds.width - visibleSize.width) / 2,
            // В перевёрнутой системе координат верх — это ноль.
            y: isFlipped ? 0 : bounds.height - visibleSize.height,
            width: visibleSize.width,
            height: visibleSize.height
        )
    }

    override func rightMouseDown(with event: NSEvent) {
        // Внутрь формы или мимо — решает та же проверка, что и для левой:
        // прозрачные углы окна не должны отзываться.
        let local = convert(event.locationInWindow, from: nil)
        guard interactiveRect.contains(local) else {
            super.rightMouseDown(with: event)
            return
        }
        onRightClick?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Точка приходит в координатах надпредставления.
        let local = superview.map { convert(point, from: $0) } ?? point
        guard interactiveRect.contains(local) else { return nil }
        return super.hitTest(point)
    }
}
