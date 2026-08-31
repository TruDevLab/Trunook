import SwiftUI

/// Таймер и секундомер в вырезе.
struct TimerPanel: View {
    @ObservedObject var timer: TimerService
    let metrics: NotchMetrics
    let onClose: () -> Void

    static var width: CGFloat { NotchStyle.scaled(440) }
    /// Поле от чёрного тела панели, а не от рамки. Ряды кнопок здесь тянутся
    /// во всю ширину, поэтому вогнутое плечо формы приходится считать явно —
    /// иначе слева и справа остаётся вчетверо меньше, чем снизу.
    /// См. `NotchStyle.shoulderInset`.
    static let bodyPadding: CGFloat = NotchStyle.bottomPadding

    /// Высота одна на оба режима. Секундомеру ряд готовых длительностей
    /// не нужен, но его место остаётся занятым подсказкой: панель, меняющая
    /// рост при переключении режима, дёргала бы вырез на ровном месте.
    private static var modeHeight: CGFloat { NotchStyle.scaled(24) }
    private static let clockHeight: CGFloat = 46
    private static var rowHeight: CGFloat { NotchStyle.rowHeight }

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
            NotchPanelButton(symbol: "xmark", hint: t("Закрыть"), action: onClose)
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

    /// Один выбор из двух — одним элементом управления.
    ///
    /// Было две отдельные подложки с зазором: 0.08 у выбранного против 0.02
    /// у соседа — это 1.12:1, то есть ничем. Разницу держал один цвет текста,
    /// а читалось всё вместе как два действия, а не как переключатель.
    ///
    /// Стало: общая дорожка на оба режима и бегунок, лежащий на ней.
    /// Невыбранный не рисует ничего — он показан тем, что дорожка под ним
    /// пуста. Цвет текста остался вторым признаком, а не единственным.
    private var modeSwitch: some View {
        // Группа: бегунок и дорожка сливаются в одну поверхность, а не
        // лежат стопкой. Состав ограничен по построению — два режима, —
        // поэтому высоту содержимое здесь не задаёт.
        GlassGroup(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(TimerService.Mode.allCases) { mode in
                    let isChosen = timer.mode == mode
                    Button { timer.select(mode: mode) } label: {
                        Text(mode.title)
                            .font(.system(size: NotchStyle.rowFontSize, weight: .medium))
                            .foregroundStyle(isChosen
                                ? Palette.timer
                                : .white.opacity(NotchStyle.secondaryOpacity))
                            .frame(maxWidth: .infinity)
                            .frame(height: Self.modeHeight)
                            // Стекло достаётся только бегунку. Это значение,
                            // а не ветка: невыбранный идёт тем же путём
                            // и получает пустую поверхность.
                            .surface(.segment, in: pillShape,
                                     tint: Palette.timer,
                                     lit: isChosen,
                                     glass: Surface.inNotch && isChosen)
                            .contentShape(pillShape)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(isChosen ? [.isSelected] : [])
                }
            }
            .frame(height: Self.modeHeight)
            // Дорожка под обоими режимами — то, что делает их одним
            // элементом управления.
            .surface(.card, in: pillShape, glass: Surface.inNotch)
        }
        .frame(height: Self.modeHeight)
    }

    private var pillShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
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
                    .font(.system(size: NotchStyle.font(34), weight: .semibold, design: .rounded))
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
                            .foregroundStyle(isChosen(minutes)
                                ? Palette.timer
                                : .white.opacity(NotchStyle.secondaryOpacity))
                            .frame(maxWidth: .infinity)
                            .frame(height: Self.rowHeight)
                            .background(
                                RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                                    .fill(.white.opacity(isChosen(minutes) ? NotchStyle.tileFill : 0.02))
                            )
                            .contentShape(RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(isChosen(minutes) ? [.isSelected] : [])
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
                .font(.system(size: NotchStyle.font(11), weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(isPrimary ? 0.22 : 0.12)))
        }
        .buttonStyle(PressableStyle())
        .fixedSize()
    }
}
