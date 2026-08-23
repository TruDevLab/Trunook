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
    /// Преобладающий цвет обложки. `nil` — обложки нет или она серая,
    /// и полоса остаётся белой.
    var tint: Color?
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
                        stroke,
                        style: StrokeStyle(lineWidth: thickness, lineCap: .round)
                    )
                    // Смена трека меняет цвет полосы, и переход стоит показать:
                    // мгновенная подмена цвета читается как сбой отрисовки,
                    // а не как «заиграло другое». Полсекунды — дольше всего
                    // прочего в вырезе: остальное отзывается на действие
                    // человека, а это происходит само.
                    .animation(.easeInOut(duration: 0.5), value: tint)
            }
        }
    }

    /// Цвет полосы.
    ///
    /// Прозрачность одна и та же для цветной и белой: цвет обложки уже поднят
    /// по яркости до порога, и приглушать его отдельно значило бы отменять
    /// эту работу.
    private var stroke: Color {
        (tint ?? .white).opacity(NotchStyle.dense(0.9))
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
