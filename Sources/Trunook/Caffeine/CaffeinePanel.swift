import SwiftUI

/// Выбор срока для чашки кофе.
///
/// Раньше срок жил только в настройках, и неудобно это было ровно там, где
/// чашкой и пользуются: включают её под конкретное дело — досмотреть,
/// дочитать, дождаться сборки, — и срок у каждого дела свой. Ходить за ним
/// в отдельное окно, чтобы поменять число и вернуться, дороже самого дела.
///
/// Поэтому нажатие по чашке больше не переключает удержание вслепую,
/// а открывает этот выбор. Настройка при этом не лишняя: она задаёт,
/// что предложено по умолчанию.
///
/// Отдельной накладкой, а не строкой внутри раскрытой панели: у той внизу
/// расписание и музыка, и вставленный между ними ряд кнопок читался бы
/// как часть расписания.
struct CaffeinePanel: View {
    @ObservedObject var wake: WakeGuard
    let metrics: NotchMetrics
    let onChoose: (Int) -> Void
    let onDisable: () -> Void
    let onClose: () -> Void

    static var width: CGFloat { NotchStyle.scaled(440) }
    static let bodyPadding: CGFloat = NotchStyle.bottomPadding

    private static var statusHeight: CGFloat { NotchStyle.scaled(22) }
    private static var rowHeight: CGFloat { NotchStyle.scaled(28) }

    static func height(notchHeight: CGFloat) -> CGFloat {
        NotchStyle.height(
            notchHeight: notchHeight,
            contentHeight: statusHeight + NotchStyle.gridSpacing + rowHeight
        )
    }

    var body: some View {
        NotchPanel(metrics: metrics, width: Self.width, bodyPadding: Self.bodyPadding) {
            NotchPanelTitle(
                symbol: "cup.and.saucer.fill",
                title: t("Бодрость"),
                tint: Palette.caffeine
            )
        } trailing: {
            NotchPanelButton(symbol: "xmark", hint: t("Закрыть"), action: onClose)
        } content: {
            VStack(spacing: NotchStyle.gridSpacing) {
                status
                choices
            }
        }
    }

    // MARK: - Что происходит сейчас

    /// Строка состояния с отсчётом.
    ///
    /// Отсчёт перерисовывает `TimelineView`, а не таймер службы: пока панель
    /// закрыта, обновлять нечего, и приложение не будит процессор впустую.
    /// Так же сделаны цифры таймера.
    private var status: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(statusText(at: context.date))
                .font(.system(size: NotchStyle.rowFontSize))
                .foregroundStyle(.white.opacity(
                    wake.isOn ? NotchStyle.primaryOpacity : NotchStyle.secondaryOpacity
                ))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Self.statusHeight)
        }
    }

    private func statusText(at date: Date) -> String {
        guard wake.isOn else { return t("Экран гаснет как обычно") }
        guard let endsAt = wake.endsAt else { return t("Экран не гаснет — без ограничения") }
        let left = max(0, endsAt.timeIntervalSince(date))
        return tf("Экран не гаснет — осталось %@", TimerService.clock(left))
    }

    // MARK: - Сроки

    private var choices: some View {
        HStack(spacing: 6) {
            // «Выключить» первым и только когда есть что выключать: это самое
            // частое, зачем к горящей чашке возвращаются, и искать его среди
            // сроков было бы издевательством.
            if wake.isOn {
                choice(
                    title: t("Выключить"),
                    tint: Palette.negative,
                    isChosen: false,
                    action: onDisable
                )
            }
            ForEach(Settings.caffeineLimits, id: \.self) { minutes in
                choice(
                    title: Self.title(minutes: minutes),
                    tint: Palette.caffeine,
                    isChosen: wake.isOn && wake.activeLimitMinutes == minutes,
                    action: { onChoose(minutes) }
                )
            }
        }
        .frame(height: Self.rowHeight)
    }

    /// Ноль — «без срока», и стоит он последним: срок выбирают, чтобы
    /// ограничить, а «без срока» — это отказ от ограничения.
    ///
    /// Круглые часы часами и подписаны: «120 мин» человек про себя всё равно
    /// переводит в два часа, а места в ряду из шести кнопок мало.
    static func title(minutes: Int) -> String {
        guard minutes > 0 else { return t("Без срока") }
        guard minutes % 60 == 0 else { return tf("%d мин", minutes) }
        return tf("%d ч", minutes / 60)
    }

    private func choice(
        title: String,
        tint: Color,
        isChosen: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: NotchStyle.captionFontSize, weight: .medium))
                // Выбранный — цветом и обводкой, как у режимов таймера:
                // подложки отличаются слишком слабо, чтобы нести состояние
                // в одиночку.
                .foregroundStyle(isChosen ? tint : .white.opacity(NotchStyle.secondaryOpacity))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: Self.rowHeight)
                .background(
                    RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                        .fill(.white.opacity(isChosen ? NotchStyle.tileFill : 0.02))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                        .strokeBorder(isChosen ? tint : .clear, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
    }
}
