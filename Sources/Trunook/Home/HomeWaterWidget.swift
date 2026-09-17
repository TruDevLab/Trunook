import SwiftUI

/// Плитка «Вода»: сколько выпито за сегодня.
///
/// Цели нет намеренно — так решил пользователь: человек не весь день
/// за компьютером, и полоса «выполнено 40%» врала бы о дне, половину
/// которого приложение не видело. Плитка отвечает на то, что знает точно:
/// сколько записано и сколькими заходами.
///
/// Нажатие открывает тот же ползунок, что и галочка на напоминании: пьют
/// чаще, чем напоминают, и записывать выпитое надо уметь не дожидаясь
/// плашки.
struct WaterWidget: View {
    let widget: HomeWidget
    @ObservedObject var log: WaterLog
    let actions: HomeActions

    private var inner: CGSize { HomeTile<EmptyView>.inner(widget.size) }

    var body: some View {
        HomeTile(widget: widget, onTap: actions.openWater, hint: t("Записать воду")) {
            if widget.size == .small {
                small
            } else {
                wide
            }
        }
    }

    /// В одну клетку — только значок и число: подпись «Вода» под ними
    /// не помещается, а значок капли отвечает на «чего именно» сам.
    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: widget.kind.symbol)
                .font(.system(size: NotchStyle.font(11), weight: .semibold))
                .foregroundStyle(widget.kind.tint)
                .frame(height: NotchStyle.scaled(16))
            Spacer(minLength: 0)
            HomeValue(text: WaterVolume.label(log.day.total), size: 18)
            Text(Self.countText(log.day))
                .font(.system(size: NotchStyle.font(9.5), weight: .medium))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .lineLimit(1)
        }
    }

    private var wide: some View {
        VStack(alignment: .leading, spacing: 2) {
            HomeCaption(kind: widget.kind, trailing: Self.countText(log.day))
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 8) {
                HomeValue(text: WaterVolume.label(log.day.total), size: 22)
                Spacer(minLength: 4)
                if log.day.count > 0 {
                    portions
                }
            }
        }
    }

    /// Заходы столбиками — высота по объёму.
    ///
    /// Это и есть то, чего не скажет одно число: литр за пять раз и литр
    /// залпом выглядят по-разному. Столбики без подписей: подписать каждый
    /// значило бы уместить пять чисел в полплитки, а вопрос здесь не «сколько
    /// именно в третьем», а «ровно ли пил».
    private var portions: some View {
        let height = NotchStyle.scaled(22)
        let visible = log.day.portions.suffix(Self.maximumBars)
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, portion in
                Capsule()
                    .fill(widget.kind.tint.opacity(0.8))
                    .frame(
                        width: 4,
                        height: max(4, CGFloat(WaterVolume.fraction(of: portion)) * height + 6)
                    )
            }
        }
        .frame(height: height, alignment: .bottom)
    }

    /// Столько столбиков помещается в самую узкую из широких плиток.
    /// Дальше показываются последние: свежие заходы важнее утренних.
    private static let maximumBars = 12

    /// «5 заходов» — или приглашение, пока не пили вовсе.
    static func countText(_ day: WaterDay) -> String {
        day.count > 0 ? tf("заходов: %d", day.count) : t("нажмите, чтобы записать")
    }
}
