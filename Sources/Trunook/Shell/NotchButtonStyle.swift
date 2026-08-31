import SwiftUI

/// Насколько сжимать и как долго анимировать при «уменьшить движение».
///
/// Ноль и там и там, а не «поменьше»: настройка называется «уменьшить
/// движение», но означает «убрать». Половинчатая пружина — это по-прежнему
/// пружина, и того, кому она мешает, она мешать не перестанет.
private enum PressMotion {
    static var scale: CGFloat { MotionPreference.shared.reduceMotion ? 1 : 0.9 }
    static var buttonScale: CGFloat { MotionPreference.shared.reduceMotion ? 1 : 0.88 }
    static var duration: Double { MotionPreference.shared.reduceMotion ? 0 : 0.12 }
}

/// Круглая кнопка выреза с откликом на нажатие.
///
/// `.buttonStyle(.plain)` в SwiftUI не рисует нажатие вообще, поэтому кнопки
/// выглядели мёртвыми. Виброотклик тоже живёт здесь, а не в обработчике
/// нажатия: так он срабатывает в момент касания, как в системных элементах,
/// а не после отпускания.
/// Нажимаемый элемент без собственной подложки — для обложки трека
/// и прочего, у чего уже есть своя картинка.
/// `ButtonStyle` — не `View`, и подписаться на настройку изнутри он не может:
/// SwiftUI не следит за его полями. Перерисовку обеспечивают корневые виды —
/// `NotchView` и `SettingsView`, — которые наблюдают `MotionPreference` сами;
/// от них она расходится по всему поддереву, и стиль пересоздаётся с новыми
/// значениями.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? PressMotion.scale : 1)
            .animation(.easeOut(duration: PressMotion.duration), value: configuration.isPressed)
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
    static var restingFill: Double { NotchStyle.dense(0.08) }
    static var pressedFill: Double { NotchStyle.dense(0.22) }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: diameter, height: diameter)
            // Подложка идёт через общий слой, а не своей заливкой: кнопка
            // лежит рядом с плитками, и разная плотность читалась
            // как небрежность ещё до всякого стекла.
            .surface(.control, in: Circle(), lit: configuration.isPressed, glass: Surface.inNotch)
            .scaleEffect(configuration.isPressed ? PressMotion.buttonScale : 1)
            .animation(.easeOut(duration: PressMotion.duration), value: configuration.isPressed)
            .contentShape(Circle())
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { Haptics.tap(.levelChange) }
            }
    }
}
