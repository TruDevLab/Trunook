import SwiftUI

/// Таймер и секундомер в вырезе.
struct TimerPanel: View {
    @ObservedObject var timer: TimerService
    let metrics: NotchMetrics
    let onClose: () -> Void

    static let width: CGFloat = 440
    /// Поле от чёрного тела панели, а не от рамки. Ряды кнопок здесь тянутся
    /// во всю ширину, поэтому вогнутое плечо формы приходится считать явно —
    /// иначе слева и справа остаётся вчетверо меньше, чем снизу.
    /// См. `NotchStyle.shoulderInset`.
    static let bodyPadding: CGFloat = NotchStyle.bottomPadding

    /// Высота одна на оба режима. Секундомеру ряд готовых длительностей
    /// не нужен, но его место остаётся занятым подсказкой: панель, меняющая
    /// рост при переключении режима, дёргала бы вырез на ровном месте.
    private static let modeHeight: CGFloat = 24
    private static let clockHeight: CGFloat = 46
    private static let rowHeight: CGFloat = 28

    static func height(notchHeight: CGFloat) -> CGFloat {
        NotchStyle.height(
            notchHeight: notchHeight,
            contentHeight: modeHeight + clockHeight + rowHeight * 2
                + NotchStyle.gridSpacing * 3
        )
    }

    var body: some View {
        NotchPanel(metrics: metrics, width: Self.width, bodyPadding: Self.bodyPadding) {
            NotchPanelTitle(
                symbol: timer.mode == .timer ? "timer" : "stopwatch",
                title: title,
                tint: Palette.timer
            )
        } trailing: {
            NotchPanelButton(symbol: "xmark", action: onClose)
        } content: {
            VStack(spacing: NotchStyle.gridSpacing) {
                modeSwitch
                clock
                middleRow
                controls
            }
        }
    }

    /// В заголовке — фаза помидора, а не просто «Таймер»: по ней и понятно,
    /// работа сейчас или перерыв.
    private var title: String {
        guard timer.mode == .timer else { return t("Секундомер") }
        return timer.phase == .rest ? t("Перерыв") : t("Таймер")
    }

    // MARK: - Режим

    private var modeSwitch: some View {
        HStack(spacing: 4) {
            ForEach(TimerService.Mode.allCases) { mode in
                Button { timer.select(mode: mode) } label: {
                    Text(mode.title)
                        .font(.system(size: NotchStyle.rowFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(
                            timer.mode == mode ? NotchStyle.primaryOpacity : NotchStyle.secondaryOpacity
                        ))
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.modeHeight)
                        .background(
                            RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                                .fill(.white.opacity(timer.mode == mode ? NotchStyle.tileFill : 0.02))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .frame(height: Self.modeHeight)
    }

    // MARK: - Цифры

    /// Цифры перерисовывает `TimelineView`, а не тик службы: пока панель
    /// закрыта, обновлять нечего, и приложение не будит процессор впустую.
    ///
    /// Ход времени берётся у `TimerService`, который считает его от момента
    /// запуска, — поэтому пропущенный кадр ничего не сдвигает.
    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(TimerService.clock(timer.mode == .timer ? timer.remaining : timer.elapsed))
                    // Моноширинные цифры: пропорциональные дёргают строку
                    // на каждой смене секунды.
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.identity)

                if timer.mode == .timer, timer.harvest > 0 {
                    Label("\(timer.harvest)", systemImage: "checkmark.circle.fill")
                        .font(.system(size: NotchStyle.captionFontSize, weight: .semibold))
                        .foregroundStyle(Palette.timer.opacity(0.8))
                }
                Spacer(minLength: 0)
            }
            .frame(height: Self.clockHeight)
        }
    }

    // MARK: - Средний ряд

    @ViewBuilder
    private var middleRow: some View {
        if timer.mode == .timer {
            HStack(spacing: 6) {
                ForEach(TimerService.presets, id: \.self) { minutes in
                    Button { timer.select(minutes: minutes) } label: {
                        Text(tf("%d мин", minutes))
                            .font(.system(size: NotchStyle.captionFontSize, weight: .medium))
                            .foregroundStyle(.white.opacity(
                                isChosen(minutes) ? NotchStyle.primaryOpacity : NotchStyle.secondaryOpacity
                            ))
                            .frame(maxWidth: .infinity)
                            .frame(height: Self.rowHeight)
                            .background(
                                RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                                    .fill(.white.opacity(isChosen(minutes) ? NotchStyle.tileFill : 0.02))
                            )
                            .contentShape(RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .frame(height: Self.rowHeight)
        } else {
            Text(t("Секундомер считает вверх, пока его не остановят"))
                .font(.system(size: NotchStyle.captionFontSize))
                .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Self.rowHeight)
        }
    }

    private func isChosen(_ minutes: Int) -> Bool {
        Int(timer.duration / 60) == minutes
    }

    // MARK: - Кнопки

    private var controls: some View {
        HStack(spacing: 6) {
            action(
                timer.isRunning ? t("Пауза") : t("Пуск"),
                symbol: timer.isRunning ? "pause.fill" : "play.fill",
                isPrimary: true
            ) { timer.toggle() }

            if timer.mode == .timer {
                action(t("+1 мин"), symbol: "plus") { timer.extend() }
            }

            Spacer(minLength: 0)

            action(t("Сброс"), symbol: "arrow.counterclockwise") { timer.reset() }
                .disabled(timer.isClean)
                .opacity(timer.isClean ? 0.4 : 1)
        }
        .frame(height: Self.rowHeight)
    }

    private func action(
        _ title: String,
        symbol: String,
        isPrimary: Bool = false,
        run: @escaping () -> Void
    ) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(isPrimary ? 0.22 : 0.12)))
        }
        .buttonStyle(PressableStyle())
        .fixedSize()
    }
}
