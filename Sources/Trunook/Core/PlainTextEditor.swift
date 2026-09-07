import AppKit
import SwiftUI

/// Многострочное поле простого текста.
///
/// Отдельно от `RichTextEditor`, хотя оба про `NSTextView`. Тот про заметку:
/// оформление, ссылки, заголовки, отмена, сохранение на диск. Здесь ничего
/// этого не нужно и всё это вредно — описание события уходит в чужое
/// хранилище простой строкой, и жирный шрифт, набранный в вырезе, до него
/// всё равно не доедет.
///
/// Своей прокрутки поле не заводит: `NSTextView` внутри `NSScrollView` в этом
/// SDK перехватывает колесо у панели целиком, и прокрутить сам список дня
/// потом становится нечем. Текст, не влезший в отведённые строки, доступен
/// стрелками — как в однострочном поле рядом.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// Забирать ли первый отклик при появлении. По умолчанию нет: в панели
    /// правки фокус принадлежит названию, а описание правят, дойдя до него.
    var focusesOnAppear = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextView {
        let view = PlaceholderTextView()
        view.delegate = context.coordinator
        view.placeholder = placeholder
        view.string = text
        view.font = .systemFont(ofSize: 12)
        view.textColor = .white
        // Фон рисует подложка SwiftUI: своя заливка здесь была бы
        // прямоугольной и торчала бы углами из скруглённой подложки.
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = true
        view.textContainerInset = NSSize(width: 0, height: 2)
        view.textContainer?.lineFragmentPadding = 0
        // Курсор и выделение — своим цветом: системный синий на чёрной
        // панели остаётся единственным местом с системной синевой.
        view.insertionPointColor = .white
        if focusesOnAppear {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.parent = self
        // Только когда разошлось: безусловная подстановка сбрасывала бы
        // курсор в начало на каждом набранном символе.
        if view.string != text { view.string = text }
        (view as? PlaceholderTextView)?.placeholder = placeholder
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor

        init(_ parent: PlainTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }

    /// `NSTextView` подсказки не имеет вовсе, а пустое поле без неё
    /// неотличимо от пустого места на панели.
    private final class PlaceholderTextView: NSTextView {
        var placeholder = "" {
            didSet { needsDisplay = true }
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard string.isEmpty else { return }
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white.withAlphaComponent(0.4),
                .font: NSFont.systemFont(ofSize: 12),
            ]
            let origin = NSPoint(x: textContainerInset.width, y: textContainerInset.height)
            placeholder.draw(at: origin, withAttributes: attributes)
        }
    }
}
