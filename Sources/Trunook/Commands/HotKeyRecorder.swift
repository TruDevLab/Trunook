import SwiftUI
import AppKit

/// Поле записи сочетания клавиш.
///
/// Сделано на AppKit, потому что SwiftUI не даёт перехватить нажатие вместе
/// с модификаторами до того, как система разберёт его как команду меню.
struct HotKeyRecorder: NSViewRepresentable {
    @Binding var spec: HotKeySpec?
    var placeholder: String = t("Нажмите сочетание")

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onCapture = { spec = $0 }
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.spec = spec
        view.placeholder = placeholder
        view.needsDisplay = true
    }

    final class RecorderView: NSView {
        var spec: HotKeySpec?
        var placeholder = ""
        var onCapture: ((HotKeySpec?) -> Void)?

        private var isRecording = false {
            didSet { needsDisplay = true }
        }

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 130, height: 24) }

        override func mouseDown(with event: NSEvent) {
            // Повторное нажатие в режиме записи отменяет её.
            if isRecording {
                isRecording = false
                window?.makeFirstResponder(nil)
            } else {
                isRecording = true
                window?.makeFirstResponder(self)
            }
        }

        override func resignFirstResponder() -> Bool {
            isRecording = false
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }

            // Escape отменяет запись, Delete снимает назначенное сочетание.
            if event.keyCode == 53 {
                isRecording = false
                window?.makeFirstResponder(nil)
                return
            }
            if event.keyCode == 51 {
                spec = nil
                onCapture?(nil)
                isRecording = false
                window?.makeFirstResponder(nil)
                return
            }

            guard let captured = HotKeySpec(event: event) else {
                // Без модификаторов сочетание перехватывало бы обычный набор.
                NSSound.beep()
                return
            }
            spec = captured
            onCapture?(captured)
            isRecording = false
            window?.makeFirstResponder(nil)
        }

        /// Иначе система озвучит нажатие как недопустимую команду меню.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)

            (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15)
                         : NSColor.controlBackgroundColor).setFill()
            path.fill()
            (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.stroke()

            let text = isRecording ? t("Ждём нажатия…") : (spec?.display ?? placeholder)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: spec == nil ? .regular : .medium),
                .foregroundColor: spec == nil || isRecording
                    ? NSColor.secondaryLabelColor
                    : NSColor.labelColor,
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(
                at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                withAttributes: attributes
            )
        }
    }
}
