import SwiftUI

/// Круглая кнопка выреза с откликом на нажатие.
///
/// `.buttonStyle(.plain)` в SwiftUI не рисует нажатие вообще, поэтому кнопки
/// выглядели мёртвыми. Виброотклик тоже живёт здесь, а не в обработчике
/// нажатия: так он срабатывает в момент касания, как в системных элементах,
/// а не после отпускания.
/// Нажимаемый элемент без собственной подложки — для обложки трека
/// и прочего, у чего уже есть своя картинка.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { Haptics.tap(.levelChange) }
            }
    }
}

struct NotchButtonStyle: ButtonStyle {
    var diameter: CGFloat = 32

    /// Заливка в покое. Вынесена, потому что ту же плотность берут подложки
    /// встреч и задач: они лежат рядом с кнопками, и разная читалась
    /// как небрежность.
    static let restingFill: Double = 0.08
    static let pressedFill: Double = 0.22

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: diameter, height: diameter)
            .background(
                Circle()
                    .fill(.white.opacity(configuration.isPressed ? Self.pressedFill : Self.restingFill))
            )
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Circle())
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { Haptics.tap(.levelChange) }
            }
    }
}
