import SwiftUI
import TrunookXPC
import AppKit

/// Поле записи сочетания клавиш.
///
/// Сделано на AppKit, потому что SwiftUI не даёт перехватить нажатие вместе
/// с модификаторами до того, как система разберёт его как команду меню.
///
/// Доступно с клавиатуры и для VoiceOver: фокус приходит по Tab, пробел или
/// Enter начинают запись, диктор читает название настройки и само сочетание.
/// Прежде запись включалась только щелчком, роли у вида не было — назначить
/// сочетание без мыши было нельзя ни одно из четырнадцати.
struct HotKeyRecorder: NSViewRepresentable {
    /// Название настройки — для диктора. Видимая подпись стоит рядом в строке.
    var label: String = ""
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
        view.label = label
        view.needsDisplay = true
    }

    final class RecorderView: NSView {
        var spec: HotKeySpec?
        var placeholder = ""
        var label = ""
        var onCapture: ((HotKeySpec?) -> Void)?

        private var isRecording = false {
            didSet {
                needsDisplay = true
                guard isRecording != oldValue else { return }
                if isRecording {
                    installMonitor()
                    // Свои глобальные сочетания отпускаются на время записи.
                    // Carbon забирает нажатие себе раньше приложения —
                    // и раньше этого поля в его же окне: ⌃⌥1 уходила команде,
                    // сидящей на этой цифре, а поле не получало ничего
                    // и молчало. Локального монитора тут мало: он ловит
                    // события, которые до приложения дошли, а это до него
                    // не доходит вовсе.
                    HotKeyCenter.shared.suspend()
                } else {
                    removeMonitor()
                    HotKeyCenter.shared.resume()
                }
            }
        }

        /// Ловит нажатия, пока идёт запись, — **до** того, как AppKit разберёт
        /// их сам. Сочетания с ⌘ сначала уходят «клавишами-командами» через
        /// меню и форму SwiftUI, и до поля не доходили: ⌥6 записывалось,
        /// а ⌥⌘6 — нет. Локальный монитор видит событие первым.
        private var monitor: Any?

        private func installMonitor() {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self, self.isRecording else { return event }
                self.capture(event)
                return nil
            }
        }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit {
            removeMonitor()
            // Окно настроек закрыли прямо во время записи — сочетания
            // остались бы отпущенными до следующей их перестановки,
            // то есть, возможно, до перезапуска.
            if isRecording { HotKeyCenter.shared.resume() }
        }

        override var acceptsFirstResponder: Bool { true }
        /// Tab доходит до поля, а не перепрыгивает его.
        override var canBecomeKeyView: Bool { true }

        override func becomeFirstResponder() -> Bool {
            needsDisplay = true
            return true
        }

        private func startRecording() {
            isRecording = true
            window?.makeFirstResponder(self)
            NSAccessibility.post(element: self, notification: .valueChanged)
        }

        // MARK: Кольцо фокуса

        override var focusRingMaskBounds: NSRect { bounds }

        override func drawFocusRingMask() {
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5).fill()
        }

        // MARK: Доступность

        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .button }
        override func accessibilityLabel() -> String? { label.isEmpty ? placeholder : label }
        override func accessibilityValue() -> Any? {
            isRecording ? t("Ждём нажатия…") : (spec?.display ?? t("не назначено"))
        }
        override func accessibilityHelp() -> String? {
            t("Нажмите, затем введите сочетание. Delete снимает, Escape отменяет.")
        }
        override func accessibilityPerformPress() -> Bool {
            startRecording()
            return true
        }
        override var intrinsicContentSize: NSSize { NSSize(width: 130, height: 24) }

        override func mouseDown(with event: NSEvent) {
            // Повторное нажатие в режиме записи отменяет её.
            if isRecording {
                isRecording = false
                window?.makeFirstResponder(nil)
            } else {
                startRecording()
            }
        }

        override func resignFirstResponder() -> Bool {
            isRecording = false
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                // Пробел, Enter и Enter на цифровой панели начинают запись —
                // как нажатие кнопки с клавиатуры.
                if [49, 36, 76].contains(event.keyCode), event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                    startRecording()
                    return
                }
                super.keyDown(with: event)
                return
            }
            capture(event)
        }

        private func capture(_ event: NSEvent) {
            // Escape отменяет запись, Delete снимает назначенное сочетание.
            if event.keyCode == 53 {
                isRecording = false
                return
            }
            if event.keyCode == 51 {
                spec = nil
                onCapture?(nil)
                isRecording = false
                return
            }

            guard let captured = HotKeySpec(event: event) else {
                // Без модификаторов сочетание перехватывало бы обычный набор.
                NSSound.beep()
                return
            }
            // Запись кончается **до** того, как новое сочетание уйдёт
            // в настройки: `onCapture` тут же назначает клавиши заново,
            // и порядок наоборот вернул бы поверх них прежний набор.
            isRecording = false
            spec = captured
            // В журнал — записанное: жалоба «не записывается» проверяется
            // по нему, а не по рассказу о том, что нажимали.
            DebugLog.write("запись сочетания: \(captured.display)")
            onCapture?(captured)
            // Фокус остаётся на поле: с клавиатуры человек не теряет места.
            NSAccessibility.post(element: self, notification: .valueChanged)
        }

        /// Иначе система озвучит нажатие как недопустимую команду меню.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording else { return super.performKeyEquivalent(with: event) }
            capture(event)
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
