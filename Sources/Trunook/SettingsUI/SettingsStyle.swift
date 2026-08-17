import SwiftUI

/// Оформление окна настроек.
///
/// Раньше окно жило системными цветами и в светлой теме, а вырез и окно
/// знакомства — тёмные. Открыть настройки из чёрной панели и получить белое
/// окно значило каждый раз спотыкаться о смену темы.
///
/// Значения здесь — те же, что у панелей выреза (`NotchStyle`), но названы
/// по-своему: у окна свои размеры, и подгонять его под панель шириной
/// в четыреста точек было бы натяжкой.
enum SettingsStyle {
    /// Фон окна: чуть светлее выреза, иначе окно сливается с ним, когда
    /// открыто поверх.
    static let background = Color(red: 0.07, green: 0.075, blue: 0.09)
    /// Полоса разделов слева — темнее содержимого, как в системных окнах.
    static let sidebar = Color(red: 0.05, green: 0.055, blue: 0.07)

    /// Подложка карточки раздела.
    static let card = Color.white.opacity(0.05)
    /// Она же у полей ввода: они лежат внутри карточки и должны читаться
    /// как углубление в ней.
    static let fieldFill = Color.black.opacity(0.25)
    static let stroke = Color.white.opacity(0.09)

    /// Выбранный раздел в полосе слева.
    static let selection = Color.white.opacity(0.12)
    static let selectionHover = Color.white.opacity(0.06)

    static let title = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.38)

    static let cardRadius: CGFloat = 10
    static let rowRadius: CGFloat = 7
}
