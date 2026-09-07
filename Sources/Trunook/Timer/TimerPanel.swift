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

    /// Ширина содержимого — то, по чему шкала считает своё растворение
    /// у краёв. Тело панели у́же рамки на вогнутое плечо с каждой стороны,
    /// см. `NotchStyle.bodyInset`.
    static var contentWidth: CGFloat { width - 2 * NotchStyle.bodyInset }

    /// Высота одна на оба режима: шкала стоит в обоих, только у секундомера
    /// её не тянут — она едет сама. Панель, меняющая рост при переключении
    /// режима, дёргала бы вырез на ровном месте.
    private static var modeHeight: CGFloat { NotchStyle.scaled(24) }
    private static let clockHeight: CGFloat = 46
    private static var rowHeight: CGFloat { NotchStyle.rowHeight }

    static func height(notchHeight: CGFloat) -> CGFloat {
        NotchStyle.height(
            notchHeight: notchHeight,
            contentHeight: modeHeight + clockHeight + TimerDial.height + rowHeight
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
    /// пуста.
    ///
    /// Цвета в переключателе нет намеренно. Розовый оттенок таймера стоит
    /// в шапке панели и на шкале — там он значит «это таймер». На бегунке
    /// он значил бы совсем другое — «выбрано», — и один цвет отвечал бы
    /// в одной панели на два разных вопроса. Выбранный режим показан тем,
    /// что под ним есть подложка, а невыбранный — тем, что её нет; текст
    /// различает их яркостью.
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
                            .foregroundStyle(.white.opacity(isChosen
                                ? 1
                                : NotchStyle.secondaryOpacity))
                            .frame(maxWidth: .infinity)
                            .frame(height: Self.modeHeight)
                            // Стекло достаётся только бегунку. Это значение,
                            // а не ветка: невыбранный идёт тем же путём
                            // и получает пустую поверхность.
                            .surface(.segment, in: pillShape,
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

    // MARK: - Цифры и шкала

    /// Цифры перерисовывает `TimelineView`, а не тик службы: пока панель
    /// закрыта, обновлять нечего, и приложение не будит процессор впустую.
    ///
    /// Ход времени берётся у `TimerService`, который считает его от момента
    /// запуска, — поэтому пропущенный кадр ничего не сдвигает.
    ///
    /// Один `TimelineView` на цифры и на шкалу: это два вида одного и того же
    /// значения, и обновляться врозь им незачем. Четверти секунды хватает
    /// обоим — шкала за секунду проезжает пятую часть точки.
    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            VStack(spacing: NotchStyle.gridSpacing) {
                digits
                TimerDial(
                    centerMinutes: centerMinutes,
                    range: range,
                    onScrub: canScrub ? { timer.select(minutes: $0, quietly: true) } : nil
                )
            }
        }
    }

    /// Цифры по центру, а урожай помидоров — поверх, у правого края.
    ///
    /// Раньше они стояли рядом в одной строке, и цифры от этого оказывались
    /// не по середине панели, а левее на ширину значка — причём только тогда,
    /// когда помидоры уже собраны. Середина, которая ездит, перестаёт быть
    /// серединой: под ней стоит метка шкалы, и расходились они на глазах.
    private var digits: some View {
        Text(TimerService.clock(timer.mode == .timer ? timer.remaining : timer.elapsed))
            // Моноширинные цифры: пропорциональные дёргают строку
            // на каждой смене секунды.
            .font(.system(size: NotchStyle.font(34), weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .contentTransition(.identity)
            .frame(maxWidth: .infinity)
            .frame(height: Self.clockHeight)
            .overlay(alignment: .trailing) { harvest }
    }

    @ViewBuilder
    private var harvest: some View {
        if timer.mode == .timer, timer.harvest > 0 {
            Label("\(timer.harvest)", systemImage: "checkmark.circle.fill")
                .font(.system(size: NotchStyle.captionFontSize, weight: .semibold))
                .foregroundStyle(Palette.timer.opacity(0.8))
        }
    }

    // MARK: - Шкала

    /// Где стоит середина шкалы.
    ///
    /// У таймера это остаток, а не заданная длительность: пока время идёт,
    /// шкала должна показывать, сколько его ещё есть, — иначе она повторяет
    /// то, что человек и так однажды выбрал. У секундомера — прошедшее.
    private var centerMinutes: Double {
        let seconds = timer.mode == .timer ? timer.remaining : timer.elapsed
        return seconds / 60
    }

    /// Границы шкалы.
    ///
    /// У таймера снизу минута, а не ноль: нулевой таймер завести нельзя,
    /// и деление, до которого можно дотянуть, но нельзя воспользоваться,
    /// врёт руке. Сверху три часа — дальше вырез перестаёт быть подходящим
    /// местом для отсчёта.
    ///
    /// У секундомера верхней границы нет по существу: он считает, пока его
    /// не остановят, и упереться шкале не во что.
    private var range: ClosedRange<Int> {
        timer.mode == .timer ? 1...180 : 0...Int.max - 1
    }

    /// Тянуть шкалу можно, только пока таймер стоит.
    ///
    /// Идущий таймер шкалу везёт сам, и рука, потянувшая её навстречу,
    /// спорила бы с ходом времени: непонятно, что должно означать
    /// «отмотать назад работающий отсчёт». Прибавить на ходу есть чем —
    /// кнопка «+1 мин» рядом. Секундомеру тянуть нечего вовсе:
    /// у прошедшего времени нет другого значения, кроме прошедшего.
    private var canScrub: Bool {
        timer.mode == .timer && !timer.isRunning
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
