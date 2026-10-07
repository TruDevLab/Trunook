import SwiftUI

/// Кружок кольца. Выключенной в настройках функции в кольце нет вовсе —
/// см. `HubEntry.ringCases`.
struct QuickRingItem: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let tint: Color
    /// Функция кружка — по ней рисуется миниатюра посреди веера.
    var entry: HubEntry? = nil
}

/// Кольцо быстрого доступа: кружки веером под чёлкой.
///
/// Единственное меню всех функций. Открывается двумя путями: удержанием
/// кнопки на вырезе — тогда выбирают, ведя руку, и отпускают, — и нажатием
/// правой кнопкой или кнопкой в крыле главного экрана — тогда кольцо стоит
/// открытым, пока по кружку не щёлкнут или не щёлкнут мимо (`QuickRing.isSticky`).
///
/// Рисуется **поверх обрезки** формы и попаданий не принимает вовсе:
/// в обоих режимах, куда показывает рука, приложение узнаёт опросом
/// положения курсора, а нажатие — опросом кнопки мыши.
struct QuickRingView: View {
    let items: [QuickRingItem]
    let highlighted: Int?
    /// Насколько кольцо раскрыто: 0 — свёрнуто в чёлку, 1 — на месте.
    let progress: Double
    /// Высота чёлки: от её нижней кромки и отмеряется веер.
    let notchHeight: CGFloat

    private var offsets: [CGPoint] { QuickRingLayout.offsets(count: items.count) }

    var body: some View {
        ZStack(alignment: .top) {
            // Подпись в середине веера — там, где пусто в любом случае.
            // Кружки подписать нечем: под каждым из восьми имя не помещается,
            // а одно имя посередине отвечает ровно на тот вопрос, который
            // и возникает, — «что я сейчас выберу».
            title
            miniature
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                circle(item, isLit: index == highlighted)
                    .offset(
                        x: offsets[index].x * progress,
                        y: notchHeight + offsets[index].y * progress
                    )
                    // Кружки выезжают из-под чёлки, а не проявляются на месте:
                    // проявление читается как «что-то мигнуло», а выезд —
                    // как «оно оттуда».
                    .opacity(progress)
            }
        }
        // Выравнивание по верху обязательно. `offset` не участвует
        // в раскладке, поэтому сам `ZStack` ростом с один кружок, а рама
        // вокруг него — во весь веер: без выравнивания рама **центрирует**
        // содержимое, и всё кольцо уезжает вниз ровно на половину разницы.
        // Поймано на снимке: кружки висели на семьдесят точек ниже места.
        .frame(
            width: QuickRingLayout.size(count: items.count).width,
            height: notchHeight + QuickRingLayout.size(count: items.count).height,
            alignment: .top
        )
        .allowsHitTesting(false)
    }

    private var title: some View {
        Text(highlighted.map { items[$0].title } ?? " ")
            .font(.system(size: NotchStyle.rowFontSize, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: NotchStyle.scaled(22))
            .background(Capsule().fill(.black.opacity(0.55)))
            .offset(y: notchHeight + NotchStyle.scaled(14))
            // Пока не выбрано ничего, подписи нет вовсе: пустая капсула
            // посреди веера читалась бы девятым, испорченным кружком.
            .opacity(highlighted == nil ? 0 : progress)
    }

    /// Миниатюра выбранной функции под подписью — схема её панели
    /// (`QuickRingMiniature`). На коротком веере кружки ближе к чёлке,
    /// и миниатюра уменьшается, чтобы их не задеть.
    @ViewBuilder
    private var miniature: some View {
        if let index = highlighted, items.indices.contains(index), let entry = items[index].entry {
            let scale = QuickRingLayout.miniatureScale(count: items.count)
            QuickRingMiniature(entry: entry)
                .scaleEffect(scale, anchor: .top)
                .id(entry)
                .transition(.opacity)
                .offset(y: notchHeight + QuickRingLayout.miniatureTop)
                .opacity(progress)
        }
    }

    private func circle(_ item: QuickRingItem, isLit: Bool) -> some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.55))
            Circle()
                // Цвет достаётся только выбранному. У всех разом он превратил
                // бы веер в россыпь разноцветных пятен, среди которых выбранное
                // приходится искать; у одного — сразу виден ответ.
                .fill(item.tint.opacity(isLit ? 0.9 : 0))
            Circle()
                .strokeBorder(.white.opacity(isLit ? 0.5 : 0.22), lineWidth: 1)
            Image(systemName: item.symbol)
                .font(.system(size: NotchStyle.font(16), weight: .medium))
                .foregroundStyle(
                    isLit ? .white : item.tint.opacity(0.9)
                )
        }
        .frame(width: QuickRingLayout.circle, height: QuickRingLayout.circle)
        // Выбранный крупнее: размер читается боковым зрением, а цвет — нет,
        // и рука ведёт кружок, не глядя прямо на него.
        .scaleEffect(isLit ? 1.18 : 1)
        .animation(.easeOut(duration: 0.1), value: isLit)
    }
}

extension QuickRingLayout {
    /// Верх миниатюры от нижней кромки чёлки: под подписью и с зазором.
    /// Подпись стоит на `scaled(14)` и ростом `scaled(22)`.
    static var miniatureTop: CGFloat { NotchStyle.scaled(14) + NotchStyle.scaled(22) + 6 }

    /// Во сколько уменьшить миниатюру, чтобы она не задела ни одного
    /// кружка (с запасом на увеличение выбранного). Веер с малым числом
    /// кружков узкий — там она мельче; ниже половины не сжимается.
    static func miniatureScale(count: Int) -> CGFloat {
        let base = QuickRingMiniature.size
        let reach = circle * 1.18 / 2 + 4
        let centers = offsets(count: count)
        var scale: CGFloat = 1
        while scale > 0.5 {
            let rect = CGRect(
                x: -base.width * scale / 2, y: miniatureTop,
                width: base.width * scale, height: base.height * scale
            )
            let clear = centers.allSatisfy { center in
                let dx = max(rect.minX - center.x, 0, center.x - rect.maxX)
                let dy = max(rect.minY - center.y, 0, center.y - rect.maxY)
                return hypot(dx, dy) >= reach
            }
            if clear { return scale }
            scale -= 0.05
        }
        return 0.5
    }
}
