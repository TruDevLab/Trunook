import AppKit
import SwiftUI

/// Поле ввода, которое само забирает фокус при появлении.
///
/// На AppKit, а не `TextField` со `@FocusState`: панель — окно-агент,
/// первый отклик ей нужно назначать вручную, и делать это надёжнее там,
/// где видно само `NSView`.
struct FocusedTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    /// Поле получило или отдало первый отклик. Обводку по этому признаку
    /// рисует подложка — своей формы и своего цвета.
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Подсказка своим цветом: системный на тёмном фоне почти чёрный
    /// и не читается — поле выглядело пустым и без объяснений.
    private static func hint(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .foregroundColor: NSColor.white.withAlphaComponent(0.4),
            .font: NSFont.systemFont(ofSize: 12),
        ])
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusReportingField()
        field.onFocusChange = onFocusChange
        field.delegate = context.coordinator
        field.placeholderAttributedString = Self.hint(placeholder)
        field.font = .systemFont(ofSize: 12)
        field.textColor = .white
        // Фон и рамку рисует подложка SwiftUI. Своя заливка здесь была
        // прямоугольной и торчала бы углами из скруглённой подложки.
        field.drawsBackground = false
        field.isBordered = false
        // Системное кольцо снято, но признак фокуса остался — его рисует
        // сама подложка в `AssistantPanel`.
        //
        // Кольцо тут побывало дважды. Сначала его сняли, и при полном доступе
        // с клавиатуры поле не показывало, что оно в фокусе. Потом вернули
        // как `.exterior` — и получили синий системный прямоугольник поверх
        // капсулы: чужой формы, чужого цвета и в единственном месте
        // приложения, где вообще есть системная синева.
        //
        // Верно и то и другое: признак нужен, но рисовать его должно то же,
        // что рисует само поле. Поле сообщает о фокусе наружу, подложка
        // меняет обводку — форма своя, цвет свой.
        field.focusRingType = .none
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.placeholderAttributedString = Self.hint(placeholder)
    }

    /// `NSTextField`, сообщающий о своём фокусе.
    ///
    /// Через подкласс, а не через делегат: `controlTextDidBeginEditing`
    /// приходит на первом набранном символе, а обводка нужна с того
    /// мгновения, как поле стало первым откликом, — то есть до набора.
    ///
    /// Редактирование в `NSTextField` ведёт общий на окно `NSTextView`,
    /// поэтому первым откликом становится он, а поле остаётся его
    /// «делегатом поля». Отсюда проверка на `currentEditor`, а не просто
    /// возврат `true`.
    final class FocusReportingField: NSTextField {
        var onFocusChange: (Bool) -> Void = { _ in }

        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            guard became else { return false }
            // Курсор цветом панели, а не системным синим. Синева ушла
            // с обводки, но осталась бы в мигающей чёрточке — в единственном
            // месте выреза, где вообще есть системный акцент.
            //
            // Здесь, а не в `makeNSView`: у `NSTextField` своего курсора нет,
            // рисует его общий на окно редактор полей, и достаётся он только
            // тогда, когда поле уже стало первым откликом.
            (currentEditor() as? NSTextView)?.insertionPointColor =
                NSColor(Palette.assistant)
            onFocusChange(true)
            return true
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { onFocusChange(false) }
            return resigned
        }

        override func textDidEndEditing(_ notification: Notification) {
            super.textDidEndEditing(notification)
            onFocusChange(false)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusedTextField

        init(_ parent: FocusedTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            return true
        }
    }
}
