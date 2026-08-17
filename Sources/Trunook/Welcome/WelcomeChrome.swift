import SwiftUI

/// Цвета окна знакомства.
///
/// Окно намеренно всегда тёмное, независимо от оформления системы: оно
/// показывает вырез, а вырез — это чёрное на чёрном. На светлой подложке
/// рассказ про него разваливается.
enum WelcomePalette {
    static let base = Color(red: 0.035, green: 0.043, blue: 0.075)
    static let cyan = Color(red: 0.36, green: 0.86, blue: 1.0)
    static let violet = Color(red: 0.62, green: 0.44, blue: 1.0)
    static let mint = Color(red: 0.42, green: 0.95, blue: 0.75)

    static let accent = LinearGradient(
        colors: [cyan, violet],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Подложка карточки: почти прозрачное стекло с холодным отливом.
    static let card = Color.white.opacity(0.045)
    static let cardStroke = Color.white.opacity(0.09)
}

// MARK: - Фон

/// Медленно дышащее свечение за содержимым.
///
/// Пятна нарисованы радиальными градиентами, а не размытием: `blur` пришлось
/// бы пересчитывать каждый кадр на всю площадь окна, а градиент и так мягкий.
/// Тиков тридцать в секунду — движение медленное, разницы с шестьюдесятью
/// не видно, а работы вдвое меньше.
struct WelcomeBackground: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                ZStack {
                    WelcomePalette.base
                    grid(size: proxy.size)
                    blob(WelcomePalette.violet, size: proxy.size, at: drift(time, speed: 0.05, phase: 0.0, spread: 0.28, center: CGPoint(x: 0.24, y: 0.28)), scale: 1.15)
                    blob(WelcomePalette.cyan, size: proxy.size, at: drift(time, speed: 0.037, phase: 2.1, spread: 0.24, center: CGPoint(x: 0.78, y: 0.22)), scale: 0.95)
                    blob(WelcomePalette.mint, size: proxy.size, at: drift(time, speed: 0.029, phase: 4.3, spread: 0.2, center: CGPoint(x: 0.6, y: 0.92)), scale: 0.8)
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
            colors: [color.opacity(0.5), color.opacity(0.14), color.opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: side / 2
        )
        .frame(width: side, height: side)
        .position(x: unit.x * size.width, y: unit.y * size.height)
        .blendMode(.plusLighter)
    }

    private func grid(size: CGSize) -> some View {
        Path { path in
            let step: CGFloat = 32
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
        }
        .stroke(Color.white.opacity(0.028), lineWidth: 0.5)
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

// MARK: - Кнопки

struct WelcomePrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.88))
            .padding(.horizontal, 24)
            .padding(.vertical, 9)
            .background(Capsule().fill(WelcomePalette.accent))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5))
            .shadow(color: WelcomePalette.cyan.opacity(0.35), radius: 16, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct WelcomeGhostButton: ButtonStyle {
    var isQuiet = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(isQuiet ? 0.45 : 0.82))
            .padding(.horizontal, isQuiet ? 8 : 16)
            .padding(.vertical, isQuiet ? 4 : 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(isQuiet ? 0 : 0.06))
                    .overlay(
                        Capsule().strokeBorder(
                            Color.white.opacity(isQuiet ? 0 : 0.14),
                            lineWidth: 0.5
                        )
                    )
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Мелкие элементы

/// Надпись над заголовком: разрядка и моноширинный шрифт отделяют её
/// от обычного текста, не занимая места.
struct WelcomeEyebrow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(2.4)
            .foregroundStyle(WelcomePalette.cyan.opacity(0.85))
    }
}

/// Карточка-стекло: общая подложка для строк и плиток.
struct WelcomeCard<Content: View>: View {
    var highlighted = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(WelcomePalette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                highlighted ? WelcomePalette.cyan.opacity(0.4) : WelcomePalette.cardStroke,
                                lineWidth: highlighted ? 1 : 0.5
                            )
                    )
            )
    }
}

/// Значок в цветной плитке — тот же приём, что в боковой панели настроек.
struct WelcomeGlyph: View {
    let symbol: String
    var tint: Color = WelcomePalette.cyan
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(tint.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                    .strokeBorder(tint.opacity(0.32), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(tint)
            )
            .frame(width: size, height: size)
    }
}
