import SwiftUI

/// Кнопки управления встречей.
///
/// Показываются по наведению, а не после нажатия: во время встречи это
/// главное, что нужно от выреза, и лишний шаг до «выключить микрофон»
/// обесценил бы всю затею.
struct MeetingControlsView: View {
    @ObservedObject var meeting: MeetingService
    let metrics: NotchMetrics

    static let buttonSize: CGFloat = 34
    static let spacing: CGFloat = 10
    static let horizontalPadding: CGFloat = 18

    static func width(actionCount: Int) -> CGFloat {
        let count = max(actionCount, 1)
        return CGFloat(count) * buttonSize
            + CGFloat(count - 1) * spacing
            + 2 * horizontalPadding
    }

    static func height(notchHeight: CGFloat) -> CGFloat {
        notchHeight + 8 + buttonSize + 12
    }

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(meeting.availableActions) { action in
                button(action)
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.top, metrics.notchHeight + 8)
        .padding(.bottom, 12)
    }

    private func button(_ action: MeetingAction) -> some View {
        let isOn = meeting.states[action] ?? true
        return Button {
            meeting.perform(action)
        } label: {
            Image(systemName: action.symbol(isOn: isOn))
                .font(.system(size: NotchStyle.font(13), weight: .medium))
                .foregroundStyle(foreground(action, isOn: isOn))
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(Circle().fill(background(action, isOn: isOn)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .notchHint(action.title)
    }

    /// Выключенные микрофон и камера подсвечены тревожным — это состояние,
    /// о котором важно узнать не читая, а боковым зрением.
    ///
    /// Цвета из `Palette`, а не системные `.red` и `.green`. Заголовок
    /// `Palette` описывает ровно эту ошибку и то, чем она кончилась:
    /// системные рассчитаны на оба режима и на чёрном теле заметно тусклее
    /// собственных, а один смысл, покрашенный в двух местах по-разному,
    /// перестаёт быть цветом смысла. Плашки событий от этого вылечили,
    /// а управление встречей осталось на прежнем — просто потому,
    /// что до него не дошли.
    private func foreground(_ action: MeetingAction, isOn: Bool) -> Color {
        switch action {
        case .leave: return .white
        case .copyLink: return .white
        case .microphone, .camera: return isOn ? .white : Palette.negative
        case .share, .hand: return isOn ? Palette.positive : .white
        }
    }

    private func background(_ action: MeetingAction, isOn: Bool) -> Color {
        switch action {
        case .leave: return Palette.negative.opacity(0.8)
        case .copyLink: return .white.opacity(0.12)
        case .microphone, .camera:
            return isOn ? .white.opacity(0.12) : Palette.negative.opacity(0.18)
        case .share, .hand:
            return isOn ? Palette.positive.opacity(0.18) : .white.opacity(0.12)
        }
    }
}
