import SwiftUI

/// Цвета приложения, названные по смыслу, а не по оттенку.
///
/// Раньше палитра была у окна знакомства, а панели выреза и настройки брали
/// системные `.cyan`, `.mint`, `.orange` по месту. Один и тот же смысл —
/// «полка оранжевая» — был записан в трёх файлах, и экраны выглядели
/// собранными из разных приложений.
///
/// Имена по смыслу, а не по цвету, потому что смысл переживает перекраску:
/// сменить оттенок полки — это правка одной строки здесь, а не поиск слова
/// «orange» по всему коду.
enum Palette {
    // MARK: Оттенки
    //
    // Взяты из окна знакомства: они подбирались под тёмный фон и на нём
    // не выцветают, в отличие от системных, рассчитанных на оба режима.

    static let cyan = Color(red: 0.36, green: 0.86, blue: 1.0)
    static let violet = Color(red: 0.62, green: 0.44, blue: 1.0)
    static let mint = Color(red: 0.42, green: 0.95, blue: 0.75)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.35)
    static let rose = Color(red: 1.0, green: 0.45, blue: 0.5)

    // MARK: Смыслы

    /// Быстрые команды и всё, что запускается по клавише.
    static let commands = mint
    /// Буфер обмена.
    static let clipboard = cyan
    /// Полка для файлов.
    static let shelf = amber
    /// Знакомство и ответ модели — всё, что «показывает и объясняет».
    static let welcome = violet
    static let assistant = violet
    /// Нагрузка на систему.
    static let monitor = cyan
    /// Таймер и секундомер.
    static let timer = rose
    /// Погода и календарь.
    static let weather = cyan
    static let calendar = rose
    /// Панель целиком и прочее без собственного цвета.
    static let panel = Color.white
    static let neutral = Color.white.opacity(0.55)

    // MARK: Состояния

    static let positive = mint
    static let warning = amber
    static let negative = rose
}
