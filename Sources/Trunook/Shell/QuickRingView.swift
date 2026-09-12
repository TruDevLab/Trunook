import SwiftUI

/// Кольцо быстрого доступа: кружки веером под чёлкой.
///
/// Появляется, пока держат кнопку на вырезе, и уходит, когда её отпускают.
/// Ради этого оно и заведено: до него до всякой функции надо было либо
/// помнить сочетание, либо открыть меню, найти плитку и нажать — три
/// движения там, где хватает одного.
///
/// Рисуется **поверх обрезки** формы и попаданий не принимает вовсе. Ни то,
/// ни другое ему не нужно: кружки лежат снаружи чёлки, а рука в это время
/// держит кнопку — и куда она показывает, приложение узнаёт опросом
/// положения курсора, а не нажатием по кружку.
struct QuickRingView: View {
    let items: [HubPanel.Item]
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

    private func circle(_ item: HubPanel.Item, isLit: Bool) -> some View {
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
                    isLit ? .white : item.tint.opacity(item.isEnabled ? 0.9 : 0.3)
                )
        }
        .frame(width: QuickRingLayout.circle, height: QuickRingLayout.circle)
        // Выбранный крупнее: размер читается боковым зрением, а цвет — нет,
        // и рука ведёт кружок, не глядя прямо на него.
        .scaleEffect(isLit ? 1.18 : 1)
        // Выключенная в настройках функция видна, но бледна — то же правило,
        // что и в меню всех функций: пропавшая плитка читается как «функцию
        // убрали совсем».
        .opacity(item.isEnabled ? 1 : 0.45)
        .animation(.easeOut(duration: 0.1), value: isLit)
    }
}
