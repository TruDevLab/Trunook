import SwiftUI

/// Панель выреза с шапкой, разложенной по бокам от чёлки.
///
/// Полоса высотой с аппаратный вырез идёт во всю ширину панели, но середину
/// её занимает сама чёлка — там ничего показать нельзя. По бокам от неё
/// оставались два пустых крыла, и каждая панель рисовала свою шапку **ниже**,
/// отдавая под неё ещё 26 точек высоты.
///
/// Теперь название уезжает в левое крыло, действия — в правое, а содержимое
/// начинается сразу под чёлкой. Панель становится ниже на всю строку шапки,
/// а место, которое всё равно закрашено чёрным, наконец работает.
///
/// Ширина крыла — половина того, что осталось от панели за вычетом чёлки.
/// На узких панелях крыло получается тесным, поэтому содержимое крыльев
/// должно быть коротким: значок и одно слово слева, значки справа.
struct NotchPanel<Leading: View, Trailing: View, Content: View>: View {
    let metrics: NotchMetrics
    /// Ширина самой панели: из неё считается ширина крыльев.
    let width: CGFloat
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    /// Отступ крыла от внешнего края панели.
    ///
    /// Сверху форма скруглена, и содержимое, прижатое к краю, не только
    /// задевает скругление, но и читается как выпавшее из панели. Ровняется
    /// на поля содержимого ниже, чтобы левый и правый край панели шли
    /// по одной вертикали.
    private static var outerInset: CGFloat { NotchStyle.panelPadding + 4 }
    /// Отступ от самой чёлки: вплотную к ней подпись читается как часть
    /// аппаратного выреза, а не как заголовок панели.
    private static var notchInset: CGFloat { 10 }

    private var wingWidth: CGFloat {
        max(0, (width - metrics.notchWidth) / 2 - Self.outerInset - Self.notchInset)
    }

    var body: some View {
        VStack(spacing: 0) {
            wings
            content()
                .padding(.horizontal, NotchStyle.panelPadding)
                // Зазор под чёлкой рисуется здесь и только здесь. Раньше он
                // был лишь в расчёте высоты — панель получалась выше того,
                // что в ней нарисовано, и снизу оставалась чёрная полоса.
                .padding(.top, NotchStyle.topGap)
                .padding(.bottom, NotchStyle.bottomPadding)
        }
    }

    private var wings: some View {
        HStack(spacing: 0) {
            leading()
                .frame(width: wingWidth, alignment: .leading)
                .padding(.leading, Self.outerInset)

            // Место самой чёлки: здесь панель не рисует ничего, потому что
            // здесь её просто не видно.
            Spacer(minLength: metrics.notchWidth + 2 * Self.notchInset)

            trailing()
                .frame(width: wingWidth, alignment: .trailing)
                .padding(.trailing, Self.outerInset)
        }
        .frame(height: metrics.notchHeight)
    }
}

// MARK: - Части шапки

/// Название панели в левом крыле: значок и одно слово.
struct NotchPanelTitle: View {
    let symbol: String
    let title: String
    var tint: Color = .white

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint.opacity(0.85))
            Text(title)
                .font(.system(size: NotchStyle.headerFontSize, weight: .semibold))
                .foregroundStyle(.white.opacity(NotchStyle.titleOpacity))
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// Кнопка-значок в правом крыле.
struct NotchPanelButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Счётчик рядом с названием: сколько записей за панелью.
struct NotchPanelCount: View {
    let value: Int

    var body: some View {
        Text("\(value)")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
            .padding(.horizontal, 4)
            .padding(.vertical, 0.5)
            .background(Capsule().fill(.white.opacity(0.1)))
    }
}
