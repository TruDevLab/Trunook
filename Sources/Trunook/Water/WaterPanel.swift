import SwiftUI

/// Сколько воды выпито — ползунком.
///
/// Открывается галочкой на напоминании о воде. Раньше галочка значила только
/// «отстань, я попил», и весь ответ на вопрос «сколько за день» оставался
/// в голове человека. Теперь тем же нажатием спрашивается объём, а плашка
/// после записи говорит итог.
///
/// Ползунком, а не рядом готовых кнопок: кружки у всех свои, и набор
/// «200 / 300 / 500» отвечал бы одним попаданием из трёх, а остальное
/// заставлял бы округлять в уме. Шкала с делениями по полста отвечает
/// на любой объём и заодно показывает, много это или мало.
struct WaterPanel: View {
    @ObservedObject var log: WaterLog
    let metrics: NotchMetrics
    /// Записать то, что стоит на ползунке.
    let onRecord: () -> Void
    let onUndo: () -> Void
    let onClose: () -> Void

    static var width: CGFloat { NotchStyle.scaled(440) }
    static let bodyPadding: CGFloat = NotchStyle.bottomPadding

    private static var valueHeight: CGFloat { NotchStyle.scaled(26) }
    /// Дорожка, риски и подписи под ними.
    private static var sliderHeight: CGFloat { NotchStyle.scaled(40) }
    private static var buttonHeight: CGFloat { NotchStyle.rowHeight }

    static func height(notchHeight: CGFloat) -> CGFloat {
        NotchStyle.height(
            notchHeight: notchHeight,
            contentHeight: valueHeight + NotchStyle.gridSpacing + sliderHeight
                + NotchStyle.gridSpacing + buttonHeight
        )
    }

    /// Ширина содержимого: от неё считается, куда встают деления.
    static var contentWidth: CGFloat {
        width - 2 * (bodyPadding + NotchStyle.shoulderInset)
    }

    var body: some View {
        NotchPanel(metrics: metrics, width: Self.width, bodyPadding: Self.bodyPadding) {
            NotchPanelTitle(symbol: "drop", title: t("Вода"), tint: Palette.blue)
        } trailing: {
            HStack(spacing: 2) {
                // «Отменить» — только пока есть что отменять: кнопка, которая
                // ничего не делает, врёт о том, что записать уже успели.
                if log.day.count > 0 {
                    NotchPanelButton(
                        symbol: "arrow.uturn.backward",
                        hint: t("Отменить последний заход"),
                        action: onUndo
                    )
                }
                NotchPanelButton(symbol: "xmark", hint: t("Закрыть"), action: onClose)
            }
        } content: {
            VStack(spacing: NotchStyle.gridSpacing) {
                value
                WaterSlider(log: log, width: Self.contentWidth)
                    .frame(height: Self.sliderHeight)
                recordButton
            }
        }
    }

    /// Крупно — то, что записывают; справа — итог дня, ради которого всё
    /// и затевалось.
    private var value: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(WaterVolume.label(log.draft))
                .font(.system(size: NotchStyle.font(22), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                .lineLimit(1)
            vessel
            Spacer(minLength: 4)
            Text(Self.dayText(log.day))
                .font(.system(size: NotchStyle.captionFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(height: Self.valueHeight)
    }

    /// Посуда рядом с числом: значок и слово.
    ///
    /// Числу в миллилитрах человек не верит на глаз — «350» это много или
    /// мало, сразу не скажешь. Кружка скажет.
    ///
    /// Значок и слово вместе, а не одно из двух: значок один отвечает
    /// загадкой (кружка и стакан рисуются одинаково), слово одно теряется
    /// рядом с крупным числом.
    private var vessel: some View {
        let vessel = WaterVessel.of(log.draft)
        return HStack(spacing: 4) {
            Image(systemName: vessel.symbol)
                .font(.system(size: NotchStyle.font(12)))
                .foregroundStyle(Palette.blue.opacity(0.9))
                .symbolSwap(vessel.symbol)
            Text(vessel.title)
                .font(.system(size: NotchStyle.captionFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .lineLimit(1)
        }
        .fixedSize()
        // Диктору — одной фразой с числом: «250 мл, стакан».
        .accessibilityElement(children: .combine)
        .accessibilityLabel(vessel.title)
    }

    /// «Сегодня 1,2 л · 5 заходов» или «Сегодня ещё не пили».
    static func dayText(_ day: WaterDay) -> String {
        guard day.count > 0 else { return t("Сегодня ещё не пили") }
        return tf("Сегодня %@ · %d", WaterVolume.label(day.total), day.count)
    }

    private var recordButton: some View {
        let shape = RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
        return Button(action: onRecord) {
            Text(tf("Записать %@", WaterVolume.label(log.draft)))
                .font(.system(size: NotchStyle.rowFontSize, weight: .semibold))
                .foregroundStyle(Palette.blue)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: Self.buttonHeight)
                .background(shape.fill(Palette.blue.opacity(0.18)))
                .overlay(shape.strokeBorder(Palette.blue.opacity(0.55), lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .frame(height: Self.buttonHeight)
    }
}

/// Сам ползунок: дорожка с залитой частью, риски и подписи.
///
/// Риска на каждые полста миллилитров, подпись — на пяти из них. Без рисок
/// дорожка не говорит о шаге ничего, и человек тянет её наугад, а потом
/// сверяется с цифрой; с рисками рука сама встаёт на 250.
struct WaterSlider: View {
    @ObservedObject var log: WaterLog
    /// Ширина приходит снаружи: в панели и в настройках она разная,
    /// а деления считаются от неё.
    let width: CGFloat

    private static var trackHeight: CGFloat { NotchStyle.scaled(6) }
    private static var knobSize: CGFloat { NotchStyle.scaled(18) }
    private static var tickHeight: CGFloat { NotchStyle.scaled(5) }
    private static var majorTickHeight: CGFloat { NotchStyle.scaled(8) }
    private static var labelHeight: CGFloat { NotchStyle.scaled(12) }

    /// Дорожка короче панели на полползунка с каждой стороны: иначе кружок
    /// на краях наполовину уезжает за край и перестаёт быть кружком.
    private var trackWidth: CGFloat { max(1, width - Self.knobSize) }

    private func x(of milliliters: Int) -> CGFloat {
        Self.knobSize / 2 + CGFloat(WaterVolume.fraction(of: milliliters)) * trackWidth
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .leading) {
                track
                ticks
                knob
            }
            .frame(width: width, height: Self.knobSize)
            // Жест на всей полосе, а не на одном кружке: попасть в кружок
            // поперечником в восемнадцать точек труднее, чем в дорожку,
            // а тянут её одинаково.
            .contentShape(Rectangle())
            .gesture(drag)
            labels
        }
        .frame(width: width)
    }

    private var track: some View {
        let shape = Capsule()
        return ZStack(alignment: .leading) {
            shape
                .fill(.white.opacity(0.12))
                .frame(width: trackWidth, height: Self.trackHeight)
            // Залитая часть — то же, чем полоса заряда отличается от пустой
            // рамки: сколько набрано, видно не считая делений.
            shape
                .fill(Palette.blue)
                .frame(
                    width: max(Self.trackHeight, CGFloat(WaterVolume.fraction(of: log.draft)) * trackWidth),
                    height: Self.trackHeight
                )
        }
        .padding(.leading, Self.knobSize / 2)
    }

    private var ticks: some View {
        ForEach(WaterVolume.ticks, id: \.self) { volume in
            let major = WaterVolume.marks.contains(volume)
            Rectangle()
                .fill(.white.opacity(major ? 0.35 : 0.18))
                .frame(width: 1, height: major ? Self.majorTickHeight : Self.tickHeight)
                .offset(x: x(of: volume) - 0.5, y: Self.knobSize / 2 - 1)
        }
    }

    private var knob: some View {
        Circle()
            .fill(.white)
            .frame(width: Self.knobSize, height: Self.knobSize)
            .overlay(Circle().strokeBorder(Palette.blue, lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .offset(x: x(of: log.draft) - Self.knobSize / 2)
    }

    private var labels: some View {
        ZStack(alignment: .leading) {
            ForEach(WaterVolume.marks, id: \.self) { volume in
                // Строкой, а не числом: `Text` числу подставляет разряды
                // по языку, и «1000» превращалось в «1 000» — лишний
                // пробел на самой тесной подписи шкалы.
                Text(String(volume))
                    .font(.system(size: NotchStyle.font(9)))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                    .fixedSize()
                    // Подписи прижимаются к своим рискам, а крайние — к краям
                    // полосы: иначе первая и последняя наполовину уезжают
                    // за панель.
                    .offset(x: min(max(x(of: volume) - NotchStyle.scaled(9), 0),
                                   width - NotchStyle.scaled(20)))
            }
        }
        .frame(width: width, height: Self.labelHeight, alignment: .leading)
        .accessibilityHidden(true)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let fraction = (value.location.x - Self.knobSize / 2) / trackWidth
                log.setDraft(WaterVolume.volume(atFraction: Double(fraction)))
            }
    }
}
