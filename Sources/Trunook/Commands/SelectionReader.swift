import TrunookXPC
import AppKit
import ApplicationServices

/// Достаёт выделенный текст из активного приложения.
enum SelectionReader {
    /// Сначала пробуем спросить у приложения напрямую через дерево
    /// доступности. Это чисто: ничего не нажимаем и не трогаем буфер обмена.
    ///
    /// Не все приложения отдают выделение — Electron и веб-страницы часто
    /// молчат. Тогда остаётся запасной путь: сымитировать ⌘C и прочитать
    /// буфер, вернув затем прежнее содержимое на место.
    static func read(completion: @escaping (String?) -> Void) {
        if let text = readViaAccessibility(), !text.isEmpty {
            completion(text)
            return
        }
        readViaCopy(completion: completion)
    }

    // MARK: - Через дерево доступности

    private static func readViaAccessibility() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let element = AXUIElementCreateApplication(app.processIdentifier)

        var focused: CFTypeRef?
        // Проверяется не только «не пусто», но и тип: значение приходит
        // из дерева чужого приложения. Почему не `as?` — в `AXTree.element`.
        guard AXUIElementCopyAttributeValue(
            element, kAXFocusedUIElementAttribute as CFString, &focused
        ) == .success, let focusedElement = AXTree.element(focused) else { return nil }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement, kAXSelectedTextAttribute as CFString, &value
        ) == .success else { return nil }

        return value as? String
    }

    // MARK: - Через буфер обмена

    /// Сколько времени буфер считается «нашим».
    ///
    /// С запасом на всё, что здесь происходит: опрос идёт до полусекунды,
    /// а следом буфер меняется второй раз — возвратом прежнего содержимого.
    /// Монитор истории опрашивает `changeCount` четырежды в секунду, и отметка
    /// обязана пережить его тик после последней нашей записи.
    private static let quietWindow: TimeInterval = 1.0

    private static func readViaCopy(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        let changeCountBefore = pasteboard.changeCount

        // Отметка ставится до нажатия, а не после: обе записи в буфер здесь —
        // следы самого приложения, а не человека. Без неё каждый запрос
        // к модели с выделением оставлял в истории лишнюю запись, а то и две.
        PasteboardActivity.beQuiet(for: quietWindow)
        sendCopyKeystroke()

        // Приложению нужно время положить текст в буфер. Проверяем несколько
        // раз подряд, а не ждём один раз наугад.
        var attempt = 0
        func poll() {
            attempt += 1
            let changed = pasteboard.changeCount != changeCountBefore
            if changed, let text = pasteboard.string(forType: .string) {
                restore(previous, in: pasteboard)
                completion(text)
                return
            }
            guard attempt < 10 else {
                restore(previous, in: pasteboard)
                completion(nil)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
    }

    /// Возвращаем прежнее содержимое: пользователь не просил портить буфер,
    /// а команда могла быть вызвана поверх чего-то скопированного раньше.
    private static func restore(_ text: String?, in pasteboard: NSPasteboard) {
        guard let text else { return }
        // Отметка продлевается: опрос мог занять почти всю полсекунды,
        // и запас, отмеренный от нажатия, к этому моменту почти истёк.
        PasteboardActivity.beQuiet(for: quietWindow)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func sendCopyKeystroke() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyC: CGKeyCode = 8 // c

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
