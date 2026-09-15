import SwiftUI

/// Раскладки окна: окно донесли до чёлки, и она показывает, куда его можно
/// положить. Плитка под курсором подсвечена, её название — строкой снизу.
///
/// Нажимать здесь нечего: окно держат на весу, и раскладка применяется
/// отпусканием. Поэтому и кнопок в крыльях нет, кроме названия.
struct WindowSnapPanel: View {
    let metrics: NotchMetrics
    let selected: WindowSlot?

    var body: some View {
        NotchPanel(metrics: metrics, width: WindowSnapLayout.width, bodyPadding: NotchStyle.bottomPadding) {
            NotchPanelTitle(symbol: "rectangle.split.2x1", title: t("Окно"), tint: Palette.cyan)
        } trailing: {
            EmptyView()
        } content: {
            VStack(spacing: WindowSnapLayout.spacing) {
                HStack(alignment: .top, spacing: WindowSnapLayout.spacing) {
                    ForEach(WindowSnapLayout.columns.indices, id: \.self) { index in
                        VStack(spacing: WindowSnapLayout.spacing) {
                            ForEach(WindowSnapLayout.columns[index]) { slot in
                                tile(slot, width: WindowSnapLayout.columnWidth(index))
                            }
                        }
                    }
                }
                .frame(height: WindowSnapLayout.gridHeight, alignment: .top)

                Text(selected?.title ?? t("Отпустите окно на раскладке"))
                    .font(.system(size: NotchStyle.captionFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(selected == nil ? NotchStyle.tertiaryOpacity : NotchStyle.primaryOpacity))
                    .lineLimit(1)
                    .frame(height: WindowSnapLayout.captionHeight)
            }
            .frame(width: WindowSnapLayout.contentWidth, height: WindowSnapLayout.contentHeight)
        }
    }

    /// Плитка — маленький экран, на котором закрашена доля окна.
    private func tile(_ slot: WindowSlot, width: CGFloat) -> some View {
        let active = slot == selected
        let height = WindowSnapLayout.tileHeight(of: slot)
        return Canvas { ctx, size in
            let inset: CGFloat = 5
            let screen = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            let unit = slot.unit
            // Доля считается от левого нижнего угла, а холст рисует сверху.
            let window = CGRect(
                x: screen.minX + screen.width * unit.minX,
                y: screen.minY + screen.height * (1 - unit.maxY),
                width: screen.width * unit.width,
                height: screen.height * unit.height
            ).insetBy(dx: 1.5, dy: 1.5)
            // Контур экрана: без него половина читалась квадратом, а треть —
            // полоской неизвестно чего.
            ctx.stroke(Path(roundedRect: screen, cornerRadius: 4),
                       with: .color(.white.opacity(active ? 0.5 : 0.22)), lineWidth: 1)
            ctx.fill(Path(roundedRect: window, cornerRadius: 3),
                     with: .color(active ? Palette.cyan : .white.opacity(NotchStyle.tertiaryOpacity)))
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: NotchStyle.tileRadius, style: .continuous)
                .fill(active ? Palette.cyan.opacity(0.18) : .white.opacity(NotchStyle.tileFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotchStyle.tileRadius, style: .continuous)
                .strokeBorder(Palette.cyan.opacity(active ? 0.8 : 0), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.1), value: active)
        .accessibilityLabel(slot.title)
    }
}
