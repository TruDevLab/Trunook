import SwiftUI

/// Медленно дышащее свечение за содержимым окна.
///
/// Общий вид, а не часть знакомства: его берут оба окна приложения — и
/// знакомство, и настройки. Пока он назывался `AuroraBackground` и лежал
/// в папке `Welcome`, это было честно; со вторым владельцем имя стало враньём,
/// а место — случайностью.
///
/// Смысл у фона тот же в обоих окнах: связать обычное окно с вырезом. Вырез
/// чёрный и живёт на обоях; окно, выкрашенное ровным серым, читается как
/// чужое приложение, открытое рядом. Три плывущих пятна дают той же черноте
/// глубину, не отвлекая: движение медленное настолько, что заметить его можно,
/// только специально следя.

struct AuroraBackground: View {
    /// Во сколько раз тише обычного светить.
    ///
    /// Единица — окно знакомства: там крупная вёрстка с большими пустотами,
    /// и пятнам есть где играть, не мешая читать. В настройках текста вчетверо
    /// больше и он мельче, а строка поверх бирюзового пятна читается заметно
    /// хуже, чем поверх чёрного, — поэтому там фон приглушён.
    ///
    /// Множителем, а не отдельным набором цветов: пятна должны остаться теми же
    /// самыми. Смысл фона в том, что оба окна выглядят частями одного
    /// приложения, — а разные пятна в разных окнах ровно это и сломали бы.
    var intensity: Double = 1

    /// Кадр, на котором замирает фон при «уменьшить движение».
    ///
    /// Не нулевой: в нуле все три пятна стоят в своих исходных точках —
    /// два наверху и одно внизу по центру, — и композиция выходит
    /// симметричной до скуки. Число подобрано так, чтобы пятна разошлись.
    private static let stillFrame: TimeInterval = 7

    @ObservedObject private var motion = MotionPreference.shared

    var body: some View {
        // Самая большая анимация в приложении — три пятна во весь экран,
        // тридцать кадров в секунду, всё время, пока открыто окно. Крутить
        // её при «уменьшить движение» нельзя вдвойне: настройка ровно про это,
        // а расплачивается за неё ещё и батарея.
        //
        // Приём тот же, что в `WelcomeNotchDemo`: показ замирает на одном
        // кадре, а не замедляется. Правило одно на окно, и жить оно обязано
        // в обоих его движущихся частях одинаково.
        TimelineView(motion.reduceMotion ? .periodic(from: .now, by: .infinity)
                                         : .periodic(from: .now, by: 1.0 / 30.0)) { context in
            let time = motion.reduceMotion
                ? Self.stillFrame
                : context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                ZStack {
                    Palette.windowBase
                    blob(Palette.violet, size: proxy.size, at: drift(time, speed: 0.05, phase: 0.0, spread: 0.28, center: CGPoint(x: 0.24, y: 0.28)), scale: 1.15)
                    blob(Palette.cyan, size: proxy.size, at: drift(time, speed: 0.037, phase: 2.1, spread: 0.24, center: CGPoint(x: 0.78, y: 0.22)), scale: 0.95)
                    blob(Palette.mint, size: proxy.size, at: drift(time, speed: 0.029, phase: 4.3, spread: 0.2, center: CGPoint(x: 0.6, y: 0.92)), scale: 0.8)
                    vignette(size: proxy.size)
                }
            }
        }
        .ignoresSafeArea()
    }

    /// Точка движется по фигуре Лиссажу: путь не повторяется на глаз, а вся
    /// анимация остаётся чистой функцией времени — без хранимого состояния.
    private func drift(_ time: TimeInterval, speed: Double, phase: Double, spread: Double, center: CGPoint) -> CGPoint {
        CGPoint(
            x: center.x + spread * sin(time * speed * 2 * .pi + phase),
            y: center.y + spread * 0.6 * cos(time * speed * 3 * .pi + phase * 1.7)
        )
    }

    private func blob(_ color: Color, size: CGSize, at unit: CGPoint, scale: CGFloat) -> some View {
        let side = max(size.width, size.height) * 1.05 * scale
        return RadialGradient(
            colors: [color.opacity(0.5 * intensity),
                     color.opacity(0.14 * intensity),
                     color.opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: side / 2
        )
        .frame(width: side, height: side)
        .position(x: unit.x * size.width, y: unit.y * size.height)
        .blendMode(.plusLighter)
    }

    private func vignette(size: CGSize) -> some View {
        RadialGradient(
            colors: [Color.clear, Color.black.opacity(0.6)],
            center: .center,
            startRadius: min(size.width, size.height) * 0.35,
            endRadius: max(size.width, size.height) * 0.75
        )
    }
}
