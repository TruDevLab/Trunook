import SwiftUI
import TrunookXPC

/// Полоса воспроизведения, идущая по контуру острова.
///
/// Путь `NotchShape` начинается в левом верхнем углу и идёт вниз по левой
/// грани, вдоль нижней и вверх по правой — то есть обрезка от нуля даёт
/// естественное движение слева направо по видимой части контура.
///
/// Контур берётся разомкнутым: замкнутый включает верхнюю грань, которая
/// лежит под кромкой экрана и не видна, и полоса впустую тратила бы на неё
/// заметную часть хода.
///
/// Обводка рисуется по центру пути, поэтому внешняя половина уходит под
/// обрезку формы, а внутри остаётся ровная линия. Именно поэтому толщина
/// задаётся вдвое больше желаемой.
struct NotchProgressRing: View {
    let track: NowPlaying?
    let shape: NotchShape
    var thickness: CGFloat = 4

    var body: some View {
        if let track, let duration = track.duration, duration > 0 {
            // Позиция считается из времени, а не приходит обновлениями:
            // MediaRemote присылает отметку старта и скорость, дальше
            // положение ползунка — арифметика.
            TimelineView(.periodic(from: .now, by: 1.0 / 30)) { context in
                outline
                    .trim(from: 0, to: progress(of: track, duration: duration, at: context.date))
                    .stroke(
                        .white.opacity(0.9),
                        style: StrokeStyle(lineWidth: thickness, lineCap: .round)
                    )
            }
        }
    }

    private var outline: NotchShape {
        var outline = shape
        outline.isClosed = false
        return outline
    }

    private func progress(of track: NowPlaying, duration: Double, at date: Date) -> CGFloat {
        let position = track.position(at: date) ?? 0
        return CGFloat(min(max(position / duration, 0), 1))
    }
}
