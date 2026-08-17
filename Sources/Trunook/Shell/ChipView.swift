import SwiftUI
import AppKit

/// Обратный отсчёт до ближайшей встречи — узкая полоска, расширяющая
/// вырез вбок, пока встреча близко.
///
/// В отличие от плашки события живёт долго, поэтому не выпадает вниз:
/// панель, висящая под чёлкой четверть часа, закрывала бы содержимое окон.
/// Раскладка по бокам от чёлки здесь безопасна — в отличие от названия
/// трека, отсчёт имеет предсказуемую длину, и ширина считается по самой
/// длинной его форме.
struct ChipView: View {
    let item: CalendarItem
    let metrics: NotchMetrics

    static let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private static let dotSize: CGFloat = 7

    /// Запас вокруг содержимого в боковой полосе.
    ///
    /// Учитывает вогнутый уголок формы: тело острова начинается не от края,
    /// а отступив на радиус скругления, и без этого запаса текст упирался
    /// прямо в дугу.
    private static let sideMargin: CGFloat = 34

    /// Самая длинная форма отсчёта — по ней и меряем, чтобы остров
    /// не дёргался на каждой минуте. Окно отсчёта не превышает 30 минут,
    /// так что часы сюда не попадают.
    private static let widestText = t("30 мин")

    /// Ширина боковой полосы. Одна и та же слева и справа: остров обязан
    /// оставаться отцентрованным по аппаратному вырезу, иначе он перестанет
    /// его закрывать.
    private static var sideWidth: CGFloat {
        max(dotSize, TextMeasure.width(widestText, font: font)) + sideMargin
    }

    static func width(metrics: NotchMetrics) -> CGFloat {
        metrics.notchWidth + 2 * sideWidth
    }

    var body: some View {
        // Обновляется дважды в минуту: чаще незачем, отсчёт идёт в минутах.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 0) {
                side {
                    Circle()
                        .fill(item.color)
                        .frame(width: Self.dotSize, height: Self.dotSize)
                }

                // Зазор ровно по ширине аппаратного выреза.
                Spacer(minLength: 0)
                    .frame(width: metrics.notchWidth)

                side {
                    Text(item.countdown(from: context.date))
                        .font(Font(Self.font))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(width: Self.width(metrics: metrics), height: metrics.notchHeight)
        }
    }

    /// Содержимое центрируется в своей полосе — так запас распределяется
    /// поровну между кромкой острова и краем выреза.
    private func side<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: Self.sideWidth)
    }
}
