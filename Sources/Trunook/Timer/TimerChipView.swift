import SwiftUI
import AppKit

/// Что показывает полоска идущего таймера.
///
/// Отдельным значением, а не ссылкой на службу: по нему считается ширина
/// острова, а расчёт состояния службами не пользуется — иначе его нельзя
/// было бы проверить тестом.
struct TimerChip: Equatable {
    let symbol: String
    /// Показывать ли часы. От этого зависит ширина полоски, и меняется она
    /// не чаще раза в час — остров не дёргается.
    let showsHours: Bool
}

/// Идущий таймер или секундомер — полоска, расширяющая вырез вбок.
///
/// Устроена как обратный отсчёт до встречи: значок в левом крыле, цифры
/// в правом, между ними зазор ровно по ширине аппаратного выреза. Иначе
/// нельзя — в середине острова видна сама чёлка, и рисовать там нечего.
///
/// Ширина считается по самой длинной форме записи, а не по нынешней: остров,
/// меняющий ширину на каждой смене секунды, дёргался бы шестьдесят раз
/// в минуту.
struct TimerChipView: View {
    @ObservedObject var timer: TimerService
    let metrics: NotchMetrics
    /// Нажатие по полоске открывает панель таймера. Полоска — единственное,
    /// что видно от таймера в свёрнутом вырезе, и добираться от неё
    /// до панели через меню функций было бы обходом на пустом месте.
    let onOpen: () -> Void

    static let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private static let symbolSize: CGFloat = 11

    /// Запас вокруг содержимого в боковой полосе — тот же, что у отсчёта
    /// до встречи: учитывает вогнутый уголок формы, за которым тело острова
    /// начинается не от края.
    private static let sideMargin: CGFloat = 34

    /// Самая длинная форма записи. Восьмёрки, потому что в моноширинных
    /// цифрах они не у́же прочих, а мерить надо по худшему случаю.
    private static func widest(showsHours: Bool) -> String {
        showsHours ? "8:88:88" : "88:88"
    }

    static func sideWidth(showsHours: Bool) -> CGFloat {
        TextMeasure.width(widest(showsHours: showsHours), font: font) + sideMargin
    }

    /// Ширина крыльев одинакова слева и справа: остров обязан оставаться
    /// отцентрованным по вырезу, иначе перестанет его закрывать.
    static func width(metrics: NotchMetrics, showsHours: Bool) -> CGFloat {
        metrics.notchWidth + 2 * sideWidth(showsHours: showsHours)
    }

    var body: some View {
        // Полсекунды: цифры идут по секундам, и обновление раз в секунду
        // отставало бы от смены на полсекунды — было бы видно, что счёт
        // запаздывает.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            HStack(spacing: 0) {
                side {
                    Image(systemName: timer.mode == .timer ? "timer" : "stopwatch")
                        .font(.system(size: Self.symbolSize, weight: .semibold))
                        .foregroundStyle(Palette.timer)
                }

                // Зазор ровно по ширине аппаратного выреза.
                Spacer(minLength: 0)
                    .frame(width: metrics.notchWidth)

                side {
                    Text(TimerService.clock(
                        timer.mode == .timer ? timer.remaining : timer.elapsed
                    ))
                    .font(Font(Self.font))
                    // Моноширинные цифры: пропорциональные дёргали бы строку
                    // на каждой смене секунды.
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                }
            }
            .frame(width: Self.width(metrics: metrics, showsHours: showsHours),
                   height: metrics.notchHeight)
            // Нажимается вся полоса, а не только буквы: в середине её
            // закрывает сама чёлка, и мимо значка с цифрами попасть некуда.
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        }
    }

    private var showsHours: Bool {
        (timer.mode == .timer ? timer.remaining : timer.elapsed) >= 3600
    }

    /// Содержимое центрируется в своей полосе — так запас распределяется
    /// поровну между кромкой острова и краем выреза.
    private func side<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: Self.sideWidth(showsHours: showsHours))
    }
}

extension TimerService {
    /// Описание полоски для расчёта состояния. `nil` — таймер стоит,
    /// и вырез остаётся свёрнутым.
    var chip: TimerChip? {
        guard isRunning else { return nil }
        let value = mode == .timer ? remaining : elapsed
        return TimerChip(
            symbol: mode == .timer ? "timer" : "stopwatch",
            showsHours: value >= 3600
        )
    }
}
