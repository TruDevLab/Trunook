import SwiftUI

/// Силуэт выреза: сверху скруглён вогнуто — переход к кромке экрана,
/// снизу выпукло — как у аппаратной чёлки.
///
/// Вогнутые уголки выходят за пределы «тела» выреза, поэтому ширина фигуры
/// на `2 × topRadius` больше, чем сам вырез.
struct NotchShape: Shape {
    var topRadius: CGFloat = 8
    var bottomRadius: CGFloat = 14
    /// Замыкать ли контур верхней гранью.
    ///
    /// Для заливки и обрезки — да. Для полосы воспроизведения — нет: верхняя
    /// грань лежит вплотную к кромке экрана и не видна, а в замкнутом контуре
    /// она съедала бы часть хода полосы впустую.
    var isClosed: Bool = true

    /// Позволяет SwiftUI плавно интерполировать радиусы при раскрытии.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let width = rect.width
        let height = rect.height
        let top = min(topRadius, width / 2)
        let bottom = min(bottomRadius, max(0, (width - 2 * top) / 2), height)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Вогнутый переход слева.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))

        // Выпуклый нижний левый угол.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))

        // Выпуклый нижний правый угол.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))

        // Вогнутый переход справа.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )

        if isClosed { path.closeSubpath() }
        return path
    }
}
