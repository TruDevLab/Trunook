import AppKit
import SwiftUI

/// Многострочное поле простого текста с прокруткой.
///
/// Отдельно от `RichTextEditor`, хотя оба про `NSTextView`. Тот про заметку:
/// оформление, ссылки, заголовки, отмена, сохранение на диск. Здесь ничего
/// этого не нужно и всё это вредно — описание события уходит в чужое
/// хранилище простой строкой, и жирный шрифт, набранный в вырезе, до него
/// всё равно не доедет.
///
/// **Прокрутка обязательна, и её отсутствие было ошибкой.** Сначала поле
/// обошлось без `NSScrollView` — из опасения, что тот перехватит колесо
/// у панели целиком. Опасение не проверили, и оно оказалось пустым: свайпы
/// по вырезу считаются только при закрытых накладках (`NotchInput.handleScroll`),
/// а поле живёт в открытой. Зато без прокрутки `NSTextView` вырос по своему
/// тексту и полез **за границы рамы** — приглашение на встречу в три абзаца
/// накрыло собой кнопки «Удалить» и «Сохранить». Рама в SwiftUI сама
/// по себе не обрезает, а `NSTextView` о ней не знает.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// Забирать ли первый отклик при появлении. По умолчанию нет: в панели
    /// правки фокус принадлежит названию, а описание правят, дойдя до него.
    var focusesOnAppear = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        // Фон рисует подложка SwiftUI: своя заливка здесь была бы
        // прямоугольной и торчала бы углами из скруглённой подложки.
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        // Наложенная полоса, а не занимающая ширину: поле и так узкое,
        // и отдавать пятнадцать точек постоянной полосе не из чего.
        scroll.scrollerStyle = .overlay
        scroll.scrollerKnobStyle = .light

        let view = PlaceholderTextView()
        view.delegate = context.coordinator
        view.placeholder = placeholder
        view.string = text
        view.font = .systemFont(ofSize: 12)
        view.textColor = .white
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = true
        view.textContainerInset = NSSize(width: 0, height: 2)
        // Курсор своим цветом: системный синий на чёрной панели остался бы
        // единственным местом с системной синевой.
        view.insertionPointColor = .white
        // Растём вниз по тексту, но не вбок: перенос по ширине, а не
        // горизонтальная полоса.
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        scroll.documentView = view
        if focusesOnAppear {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? PlaceholderTextView else { return }
        // Только когда разошлось: безусловная подстановка сбрасывала бы
        // курсор в начало на каждом набранном символе.
        if view.string != text { view.string = text }
        view.placeholder = placeholder
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
