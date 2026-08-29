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
            DebugLog.write("выделение: взято через дерево доступности, \(text.count) симв.")
            completion(text)
            return
        }
        readViaCopy(completion: completion)
    }

    // MARK: - Через дерево доступности

    /// Спрашиваем двумя путями и двумя способами каждым.
    ///
    /// Одного пути не хватало. Приложение спрашивалось только через свой
    /// собственный элемент, а фокус бывает и не там: у приложений с окнами
    /// в отдельном процессе — браузеры, всё на Electron — общесистемный
    /// элемент отвечает, где фокус на самом деле, а собственный молчит.
    ///
    /// Способов тоже два. `AXSelectedText` отдают не все: у части полей
    /// его нет вовсе, зато есть отрезок выделения и умение выдать текст
    /// по отрезку. Это не одно и то же свойство, и приложение, молчащее
    /// на первое, часто отвечает на второе.
    private static func readViaAccessibility() -> String? {
        guard AXIsProcessTrusted() else { return nil }

        var roots: [AXUIElement] = [AXUIElementCreateSystemWide()]
        if let app = NSWorkspace.shared.frontmostApplication {
            roots.append(AXUIElementCreateApplication(app.processIdentifier))
        }

        for root in roots {
            var focused: CFTypeRef?
            // Проверяется не только «не пусто», но и тип: значение приходит
            // из дерева чужого приложения. Почему не `as?` — в `AXTree.element`.
            guard AXUIElementCopyAttributeValue(
                root, kAXFocusedUIElementAttribute as CFString, &focused
            ) == .success, let element = AXTree.element(focused) else { continue }

            if let text = selectedText(of: element), !text.isEmpty { return text }
            if let text = selectedByRange(of: element), !text.isEmpty { return text }
        }
        return nil
    }

    private static func selectedText(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &value
        ) == .success else { return nil }
        return value as? String
    }

    /// Выделение отрезком: спрашиваем, что выделено, и просим текст этого
    /// куска отдельным запросом.
    private static func selectedByRange(of element: AXUIElement) -> String? {
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeValue
        ) == .success, let raw = rangeValue else { return nil }
        // Отрезок приходит завёрнутым в `AXValue`; пустой брать незачем —
        // это курсор без выделения, и запрос по нему вернёт пустоту.
        guard CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let box = unsafeBitCast(raw, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetValue(box, .cfRange, &range), range.length > 0 else { return nil }

        var text: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, raw, &text
        ) == .success else { return nil }
        return text as? String
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
        //
        // Продлевается она и потом: `SyntheticKey` ждёт, пока человек отпустит
        // ⌃⌥, и от постановки отметки до самого копирования проходит время.
        PasteboardActivity.beQuiet(for: quietWindow)

        // Опрос заводится только после того, как нажатие ушло: раньше он
        // начинался сразу, а само нажатие уходило с задержкой на отпускание
        // клавиш — и половина попыток опроса тратилась впустую, до того как
        // копировать вообще начали.
        SyntheticKey.send(SyntheticKey.c, flags: .maskCommand) {
            PasteboardActivity.beQuiet(for: quietWindow)

            // Приложению нужно время положить текст в буфер. Проверяем
            // несколько раз подряд, а не ждём один раз наугад.
            var attempt = 0
            func poll() {
                attempt += 1
                let changed = pasteboard.changeCount != changeCountBefore
                if changed, let text = pasteboard.string(forType: .string) {
                    restore(previous, in: pasteboard)
                    DebugLog.write("выделение: взято через ⌘C с попытки \(attempt), \(text.count) симв.")
                    completion(text)
                    return
                }
                guard attempt < pollAttempts else {
                    restore(previous, in: pasteboard)
                    DebugLog.write("выделение: ⌘C ничего не дал — выделения нет или приложение его не отдаёт")
                    completion(nil)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + pollStep, execute: poll)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + pollStep, execute: poll)
        }
    }

    /// Сколько раз спрашиваем буфер и с каким шагом.
    ///
    /// Было десять по 0,05 — полсекунды. Тяжёлым приложениям этого не хватало:
    /// у страницы с длинным выделением копирование занимает дольше, и захват
    /// возвращался пустым при живом выделении. Секунда с четвертью ждёт того,
    /// кто задумался, и по-прежнему не заметна тому, кто ответил сразу:
    /// опрос кончается на первом же изменении буфера.
    private static let pollAttempts = 25
    private static let pollStep: TimeInterval = 0.05

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

}
