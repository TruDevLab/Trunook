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
    /// Поле содержимого, отмеренное от чёрного тела, а не от рамки панели.
    ///
    /// Обычной панели хватает общего поля: её содержимое до краёв не доходит,
    /// и вогнутое плечо формы съедает пустое место. Панель, у которой строка
    /// или поле ввода тянется во всю ширину, задаёт поле этим параметром
    /// и получает ровно его — слева, справа и снизу поровну.
    ///
    /// Включено не для всех сразу: сетки полки и меню функций подогнаны
    /// под нынешнюю ширину содержимого впритык, и сужение их сломает.
    var bodyPadding: CGFloat?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    /// Поле содержимого от краёв рамки.
    private var contentInset: CGFloat {
        guard let bodyPadding else { return NotchStyle.panelPadding }
        // То же, что `NotchStyle.bodyInset`, но от заданного поля: панель
        // вправе попросить своё. Считающие свою ширину берут число оттуда.
        return bodyPadding + NotchStyle.shoulderInset
    }

    /// Отступ крыла от внешнего края панели.
    ///
    /// Сверху форма скруглена, и содержимое, прижатое к краю, не только
    /// задевает скругление, но и читается как выпавшее из панели. Ровняется
    /// на поля содержимого ниже, чтобы левый и правый край панели шли
    /// по одной вертикали.
    private var outerInset: CGFloat {
        bodyPadding == nil ? NotchStyle.panelPadding + 4 : contentInset
    }

    /// Поле под последней строкой.
    private var bottomInset: CGFloat { bodyPadding ?? NotchStyle.bottomPadding }

    private var wingWidth: CGFloat {
        max(0, (width - metrics.notchWidth) / 2 - outerInset - NotchStyle.notchInset)
    }

    var body: some View {
        VStack(spacing: 0) {
            wings
            content()
                .padding(.horizontal, contentInset)
                // Зазор под чёлкой рисуется здесь и только здесь. Раньше он
                // был лишь в расчёте высоты — панель получалась выше того,
                // что в ней нарисовано, и снизу оставалась чёрная полоса.
                .padding(.top, NotchStyle.topGap)
                .padding(.bottom, bottomInset)
        }
    }

    private var wings: some View {
        HStack(spacing: 0) {
            leading()
                .frame(width: wingWidth, alignment: .leading)
                .padding(.leading, outerInset)

            // Место самой чёлки: здесь панель не рисует ничего, потому что
            // здесь её просто не видно.
            Spacer(minLength: metrics.notchWidth + 2 * NotchStyle.notchInset)

            trailing()
                .frame(width: wingWidth, alignment: .trailing)
                .padding(.trailing, outerInset)
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
                .font(.system(size: NotchStyle.font(10), weight: .semibold))
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
    /// Подпись значка — обязательная.
    ///
    /// Была необязательной, и тринадцать кнопок из двадцати одной обходились
    /// без неё: считалось, что крестик и шестерёнку узнают по самому значку.
    /// Глазом — да. Но `hint` уходил ещё и в `.accessibilityLabel`, а там
    /// `hint ?? ""` подставлял пустую строку — и она не просто ничего
    /// не добавляет, она **перекрывает** имя, которое SwiftUI вывел бы
    /// из названия символа. VoiceOver говорил «кнопка» и умолкал.
    ///
    /// Обязательным поле сделано, чтобы четырнадцатую кнопку без подписи
    /// поймал компилятор, а не следующий аудит.
    let hint: String
    let action: () -> Void

    /// Сторона области нажатия.
    ///
    /// Было 18. Норма для указательного ввода — 24, и послабление
    /// «маленькие цели можно, если они разрежены» здесь не работает: кнопки
    /// стоят с шагом в две точки, а послабление требует двадцати четырёх
    /// между центрами.
    ///
    /// Растёт только область нажатия — кегль значка прежний, десять пунктов.
    /// Рисунок шапки не меняется, меняется то, куда можно попасть курсором.
    static var size: CGFloat { max(24, NotchStyle.scaled(24)) }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: NotchStyle.font(10), weight: .medium))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .frame(width: Self.size, height: Self.size)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        // Имя для диктора и плашка под чёлкой для глаза — из одной строки.
        .notchHint(hint)
    }
}

/// Счётчик рядом с названием: сколько записей за панелью.
struct NotchPanelCount: View {
    let value: Int

    var body: some View {
        Text("\(value)")
            .font(.system(size: NotchStyle.font(9), weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
            .padding(.horizontal, 4)
            .padding(.vertical, 0.5)
            .background(Capsule().fill(.white.opacity(0.1)))
    }
}
