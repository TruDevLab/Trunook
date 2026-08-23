import SwiftUI

/// Цвета окна знакомства.
///
/// Окно намеренно всегда тёмное, независимо от оформления системы: оно
/// показывает вырез, а вырез — это чёрное на чёрном. На светлой подложке
/// рассказ про него разваливается.
enum WelcomePalette {
    /// Подложка окна. Общая с настройками, поэтому живёт в `Palette`.
    static let base = Palette.windowBase

    // Три оттенка — не свои, а общие. `Palette` в шапке прямо говорит, что
    // взял их отсюда; взял, но не забрал — исходники остались на месте
    // и разошлись бы с общими при первой же перекраске.
    //
    // Псевдонимы, а не удаление имён: на них пятьдесят пять обращений
    // в трёх файлах окна, и менять их все ради одного слова значило бы
    // править полсотни строк, ничего в них не меняя по существу.
    static let cyan = Palette.cyan
    static let violet = Palette.violet
    static let mint = Palette.mint

    static let accent = LinearGradient(
        colors: [cyan, violet],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Подложка карточки: почти прозрачное стекло с холодным отливом.
    static let card = Color.white.opacity(0.045)
    static let cardStroke = Color.white.opacity(0.09)
}

// MARK: - Кнопки

/// Главная кнопка шага — единственное место в окне, где остался градиент.
///
/// Было три: заголовок первого экрана, полоска текущего шага и она.
/// Плюс свечение под ней, свечение под галочкой последнего шага
/// и техническая сетка поверх фона. Всё вместе это узнаваемый набор
/// приёмов, который берут, когда не выбирают, — и за дверью человек
/// попадал в приложение с совсем другим характером: чёрное, тихое,
/// плотное. Прихожая была не от этого дома.
///
/// Градиент оставлен там, где он что-то значит: на кнопке, которая
/// ведёт дальше. Одна яркая вещь на экран — и глазу ясно, куда нажимать.
struct WelcomePrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.88))
            .padding(.horizontal, 24)
            .padding(.vertical, 9)
            .background(Capsule().fill(WelcomePalette.accent))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct WelcomeGhostButton: ButtonStyle {
    var isQuiet = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: WelcomeStyle.body, weight: .medium, design: .rounded))
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
            .font(.system(size: WelcomeStyle.micro, weight: .semibold, design: .monospaced))
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
    var size: CGFloat = WelcomeStyle.scaled(34)

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
