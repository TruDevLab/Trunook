import SwiftUI

/// Залп конфетти из-под чёлки — один `Canvas` на все бумажки.
///
/// Не шестьдесят видов с анимацией: столько отдельных видов SwiftUI пересобирал
/// бы каждый кадр, а рисование в `Canvas` идёт одним проходом. Заодно снимается
/// вопрос про `@State` — рисовать нечего, кроме того, что посчитано из времени.
struct ConfettiView: View {
    /// Откуда вылетают: середина нижней кромки чёлки в координатах окна.
    let origin: CGPoint
    let started: Date

    private let pieces = Confetti.pieces()

    /// Цвета палитры. Пять — столько же, сколько цветных плиток в меню
    /// функций: набор узнаётся как свой, а не как чужая праздничная россыпь.
    private static let colors: [Color] = [
        Palette.cyan, Palette.violet, Palette.mint, Palette.amber, Palette.rose,
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(started)
            Canvas { context, _ in
                for piece in pieces {
                    guard let state = Confetti.state(of: piece, elapsed: elapsed) else { continue }
                    var layer = context
                    layer.opacity = state.opacity
                    layer.translateBy(
                        x: origin.x + state.offset.x,
                        y: origin.y + state.offset.y
                    )
                    layer.rotate(by: .radians(state.rotation))
                    // Сплющивание поперёк изображает, что бумажка повёрнута
                    // к нам ребром. Без него вращение читается как кувырок
                    // плоской наклейки, а не как летящий клочок бумаги.
                    layer.scaleBy(x: 1, y: cos(state.rotation * 1.7))
                    layer.fill(
                        Path(
                            roundedRect: CGRect(
                                x: -piece.size.width / 2,
                                y: -piece.size.height / 2,
                                width: piece.size.width,
                                height: piece.size.height
                            ),
                            cornerRadius: 1.5
                        ),
                        with: .color(Self.colors[piece.colorIndex % Self.colors.count])
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }
}
