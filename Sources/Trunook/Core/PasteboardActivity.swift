import Foundation

/// Отметка о том, что содержимое буфера сейчас возит само приложение.
///
/// Нужна двум местам, которые ничего не знают друг о друге: чтению
/// выделенного текста через имитацию ⌘C (оно копирует выделение, а потом
/// возвращает прежнее содержимое) и выбору записи из истории. Без неё
/// история пополнялась бы собственными следами приложения.
enum PasteboardActivity {
    private static var quietUntil = Date.distantPast

    static func beQuiet(for seconds: TimeInterval) {
        quietUntil = max(quietUntil, Date().addingTimeInterval(seconds))
    }

    static var isQuiet: Bool { Date() < quietUntil }
}
