import SwiftUI

/// Карточка подтверждения: модель предлагает — человек решает.
///
/// Живёт **внутри панели разговора**, а не отдельной накладкой, и это
/// не мелочь раскладки. Место накладки одно (`NotchState.Overlay`), и
/// открытие карточки закрыло бы разговор — то есть спрятало бы ровно тот
/// вопрос, к которому карточка относится; нажав «Создать», человек смотрел
/// бы в свёрнутую чёлку, не зная, вышло ли. Вдобавок у накладки нет верного
/// ответа на «закрываться ли по уходу курсора»: да — молча теряем запись,
/// нет — выходит модальное окно, которое всё равно закрывается щелчком мимо.
///
/// Высота **постоянна**: подпись обрезается, а не переносится. Панель,
/// растущая от длины названия встречи, прыгала бы на каждом предложении —
/// той же причиной живёт и постоянная высота плашки захвата.
struct AgentCard: View {
    let action: PendingAction
    let onConfirm: () -> Void
    let onCancel: () -> Void

    static let height: CGFloat = 58

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: action.tool.symbol)
                .font(.system(size: NotchStyle.font(13)))
                .foregroundStyle(Palette.assistant)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                    .font(.system(size: NotchStyle.font(11.5), weight: .medium))
                    .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(action.detail)
                    .font(.system(size: NotchStyle.font(10.5)))
                    .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // «Отмена» слева от «Создать»: правая кнопка ближе к большому
            // пальцу и к Enter, и главной должна быть та, которую просили.
            Button(action: onCancel) {
                Text(t("Отмена"))
                    .font(.system(size: NotchStyle.font(11)))
                    .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
            }
            .buttonStyle(PressableStyle())

            Button(action: onConfirm) {
                Text(action.confirm)
                    .font(.system(size: NotchStyle.font(11), weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Palette.assistant.opacity(NotchStyle.dense(0.55)))
                    )
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: NotchStyle.cardRadius, style: .continuous)
                .fill(Palette.assistant.opacity(NotchStyle.dense(0.16)))
                .overlay(
                    RoundedRectangle(cornerRadius: NotchStyle.cardRadius, style: .continuous)
                        .stroke(Palette.assistant.opacity(0.35), lineWidth: 1)
                )
        )
    }
}
