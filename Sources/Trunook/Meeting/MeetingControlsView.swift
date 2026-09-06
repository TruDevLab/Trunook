import SwiftUI

/// Кнопки управления встречей.
///
/// Показываются по наведению, а не после нажатия: во время встречи это
/// главное, что нужно от выреза, и лишний шаг до «выключить микрофон»
/// обесценил бы всю затею.
struct MeetingControlsView: View {
    @ObservedObject var meeting: MeetingService
    /// Запись разговора. Кнопка записи стоит в том же ряду, но управляет
    /// не встречей, а приложением: службе встречи о звуке знать нечего.
    @ObservedObject var recorder: RecorderService
    let metrics: NotchMetrics
    /// Начать или закончить запись встречи — микрофон и звук системы.
    let onToggleRecording: () -> Void

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
        let isOn = state(of: action)
        return Button {
            if action == .record {
                onToggleRecording()
            } else {
                meeting.perform(action)
            }
        } label: {
            Image(systemName: action.symbol(isOn: isOn))
                .font(.system(size: NotchStyle.font(13), weight: .medium))
                .foregroundStyle(foreground(action, isOn: isOn))
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(Circle().fill(background(action, isOn: isOn)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .notchHint(hint(for: action))
    }

    /// Включено ли действие.
    ///
    /// У записи это состояние своё: она идёт или не идёт, и знает об этом
    /// не встреча, а служба записи. Остальные состояния приходят обходом
    /// страницы; неизвестное считается включённым — так было и раньше.
    private func state(of action: MeetingAction) -> Bool {
        action == .record ? recorder.phase.isRecording : (meeting.states[action] ?? true)
    }

    /// Что показывает плашка под чёлкой.
    ///
    /// У кнопок устройств подпись — имя выбранного, а не название действия:
    /// нажатие перебирает список по кругу, и без имени человек не знает,
    /// куда попал. У остальных кнопок подпись прежняя.
    private func hint(for action: MeetingAction) -> String {
        if action == .record, recorder.phase.isBusy, !recorder.phase.isRecording {
            return t("Расшифровываю…")
        }
        guard action.isDevice, let name = meeting.deviceName(for: action) else {
            return action.title
        }
        return name
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
        // Кнопки устройств — соседи «Скопировать ссылку», а не состояния
        // встречи: они ничего не включают и не выключают, поэтому и цветом
        // ничего не сообщают.
        case .copyLink, .output, .input: return .white
        case .record: return isOn ? Palette.negative : .white
        case .microphone, .camera: return isOn ? .white : Palette.negative
        case .share, .hand: return isOn ? Palette.positive : .white
        }
    }

    private func background(_ action: MeetingAction, isOn: Bool) -> Color {
        switch action {
        case .leave: return Palette.negative.opacity(0.8)
        case .copyLink, .output, .input: return .white.opacity(0.12)
        case .record:
            return isOn ? Palette.negative.opacity(0.18) : .white.opacity(0.12)
        case .microphone, .camera:
            return isOn ? .white.opacity(0.12) : Palette.negative.opacity(0.18)
        case .share, .hand:
            return isOn ? Palette.positive.opacity(0.18) : .white.opacity(0.12)
        }
    }
}
