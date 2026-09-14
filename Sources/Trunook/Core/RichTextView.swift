import AppKit
import SwiftUI

/// Поле оформленного текста — `NSTextView` внутри прокрутки.
///
/// Не `TextEditor` из SwiftUI: тот работает с простой строкой и оформления
/// не знает вовсе, а здесь оформление — половина смысла. Через `NSTextView`
/// заодно достаются штатная отмена, распознавание ссылок и системная палитра
/// эмодзи — писать своё для каждого из них не пришлось.
///
/// Вынесено из телесуфлера, когда такое же поле понадобилось панели модели.
/// Отличаются они кеглем, цветом и полями — это параметры; всё остальное
/// у них общее.
struct RichTextView: NSViewRepresentable {
    let editor: RichTextEditor
    /// Поле вокруг текста. Наружу — потому что по нему выравнивается
    /// подсказка пустого поля: два числа порознь разъехались бы.
    var inset: CGSize
    /// Текст изменился рукой человека.
    var onChange: () -> Void
    /// Что делать по нажатию на ссылку в самом поле.
    ///
    /// По умолчанию ничего: и телесуфлер, и заметку **правят**, а не листают,
    /// и уход в браузер посреди правки — последнее, чего от поля ждут.
    var opensLinks = false
    /// В поле что-то вставили — из буфера или перетаскиванием.
    ///
    /// Наружу, а не внутрь редактора: чистка чужого оформления — решение
    /// того, чьё это поле, и телесуфлеру с заметкой оно может понадобиться
    /// разное.
    var onPaste: (() -> Void)?
    /// Поле построено и отдано редактору.
    ///
    /// Нужно тому, кто кладёт в поле готовый текст — сохранённую речь или
    /// заметку, открытую на правку. Зовётся здесь, а не из `onAppear`:
    /// к появлению вида поле уже должно быть заполнено, иначе первый кадр
    /// показывает пустоту, а следом текст возникает рывком.
    var onAttach: ((NSTextView) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, opensLinks: opensLinks)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let view = PastingTextView()
        view.onPaste = onPaste
        view.delegate = context.coordinator
        view.isRichText = true
        view.allowsUndo = true
        view.isEditable = true
        view.isSelectable = true
        // Распознавание ссылок на лету: адрес, набранный или вставленный
        // в текст, сам становится ссылкой — отдельно размечать его не нужно.
        view.isAutomaticLinkDetectionEnabled = true
        // Умные кавычки и тире выключены намеренно: сюда вставляют готовый
        // чужой текст, и подмена символов в нём — не помощь.
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false

        view.drawsBackground = false
        view.textColor = .white
        view.insertionPointColor = editor.style.tint
        // Свой цвет ссылок: системный синий на чёрном читается как чужой,
        // а `.link` в тексте поле перекрашивает по-своему, что бы ни было
        // записано в самом атрибуте.
        view.linkTextAttributes = [
            .foregroundColor: editor.style.tint,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.iBeam,
        ]
        // Поля вокруг текста: строка, упирающаяся в кромку окна, читается
        // с трудом.
        view.textContainerInset = inset
        // Собственное поле контейнера — в ноль. По умолчанию оно пять точек
        // и прибавляется к отступу слева, то есть текст начинается не там,
        // где сказано. Подсказка пустого поля рисуется поверх средствами
        // SwiftUI и об эти пять точек и споткнулась: курсор вставал
        // на первой букве подсказки, а не перед ней.
        //
        // Ноль, а не прибавка к подсказке: отступ должен значить ровно то,
        // что в нём написано, иначе следующий, кто станет что-нибудь
        // выравнивать по краю текста, споткнётся так же.
        view.textContainer?.lineFragmentPadding = 0

        // Ширина по окну, высота по тексту: так работает прокрутка.
        view.minSize = CGSize(width: 0, height: 0)
        view.maxSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = CGSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        editor.applyDefaultTyping(to: view)
        scroll.documentView = view
        editor.attach(view)
        onAttach?(view)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Текст снаружи не переписываем: он живёт в самом поле, и подмена
        // его на каждой перерисовке сбивала бы курсор и отмену. Вёрстка сюда
        // только смотрит. Обновляем лишь замыкание — оно у нового значения
        // структуры своё.
        context.coordinator.onChange = onChange
        (nsView.documentView as? PastingTextView)?.onPaste = onPaste
    }

    /// `NSTextView`, сообщающий о вставке.
    ///
    /// Через подкласс, а не через делегата: у `NSTextViewDelegate` нет метода
    /// «вставили», а `textDidChange` не отличает вставку от набора руками —
    /// перебирать же всё содержимое на каждой нажатой клавише ради чужих
    /// цветов расточительно.
    ///
    /// Перекрыты три пути: обычная вставка, вставка без оформления
    /// и `readSelection` — им приходит перетаскивание. Первый из них зовёт
    /// третий внутри себя, так что сообщение иногда приходит дважды; чистка
    /// от этого не портится — она идемпотентна.
    final class PastingTextView: NSTextView {
        var onPaste: (() -> Void)?

        // MARK: Галочки

        /// Щелчок по ☐ или ☑ в начале строки ставит или снимает отметку,
        /// а курсор остаётся где был: человек отмечает пункт, а не правит его.
        override func mouseDown(with event: NSEvent) {
            if let index = checkboxIndex(at: convert(event.locationInWindow, from: nil)) {
                toggleCheckbox(at: index)
                return
            }
            super.mouseDown(with: event)
        }

        private func checkboxIndex(at point: NSPoint) -> Int? {
            guard let layout = layoutManager, let container = textContainer, textStorage?.length ?? 0 > 0 else {
                return nil
            }
            let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
            let glyph = layout.glyphIndex(for: local, in: container)
            let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            guard rect.insetBy(dx: -3, dy: -2).contains(local) else { return nil }
            let index = layout.characterIndexForGlyph(at: glyph)
            let string = self.string as NSString
            let paragraph = string.paragraphRange(for: NSRange(location: index, length: 0))
            let head = string.substring(with: NSRange(location: paragraph.location, length: index - paragraph.location))
            guard head.allSatisfy({ $0 == " " || $0 == "\t" }),
                  let item = Checklist.item(inDisplay: string.substring(from: paragraph.location)
                      .components(separatedBy: .newlines).first ?? ""),
                  (item.indent as NSString).length == head.utf16.count
            else { return nil }
            return index
        }

        func toggleCheckbox(at index: Int) {
            guard let storage = textStorage else { return }
            let string = self.string as NSString
            let paragraph = string.paragraphRange(for: NSRange(location: index, length: 0))
            let isChecked = string.substring(with: NSRange(location: index, length: 1)) == String(Checklist.checked)
            var body = NSRange(location: index, length: NSMaxRange(paragraph) - index)
            if body.length > 0, string.substring(with: NSRange(location: NSMaxRange(body) - 1, length: 1))
                .first?.isNewline == true {
                body.length -= 1
            }
            guard shouldChangeText(in: body, replacementString: nil) else { return }
            storage.beginEditing()
            storage.replaceCharacters(
                in: NSRange(location: index, length: 1),
                with: String(isChecked ? Checklist.unchecked : Checklist.checked)
            )
            Checklist.style(storage, paragraph: body, checked: !isChecked)
            storage.endEditing()
            didChangeText()
        }

        /// Enter в пункте продолжает список новым пунктом. Enter в пустом
        /// пункте список заканчивает — так ведут себя все редакторы списков,
        /// и иначе из списка было бы не выйти.
        override func insertNewline(_ sender: Any?) {
            let string = self.string as NSString
            let selection = selectedRange()
            let paragraph = string.paragraphRange(for: NSRange(location: selection.location, length: 0))
            let line = string.substring(with: paragraph).trimmingCharacters(in: .newlines)
            guard selection.length == 0, let item = Checklist.item(inDisplay: line) else {
                super.insertNewline(sender)
                return
            }
            if item.rest.trimmingCharacters(in: .whitespaces).isEmpty {
                let marker = NSRange(
                    location: paragraph.location + (item.indent as NSString).length,
                    length: min(2, (line as NSString).length - (item.indent as NSString).length)
                )
                insertText("", replacementRange: marker)
                return
            }
            super.insertNewline(sender)
            var typing = typingAttributes
            typing.removeValue(forKey: .strikethroughStyle)
            typing[.foregroundColor] = NSColor.white
            typingAttributes = typing
            insertText(item.indent + Checklist.prefix(checked: false), replacementRange: selectedRange())
        }

        /// `- [ ] ` или `[] ` в начале строки превращается в пункт сразу,
        /// как только допечатан пробел.
        func convertTypedCheckbox() {
            styleMarkUnderCursor()
            let selection = selectedRange()
            guard selection.length == 0, selection.location > 0 else { return }
            let string = self.string as NSString
            let paragraph = string.paragraphRange(for: NSRange(location: selection.location - 1, length: 0))
            let head = string.substring(with: NSRange(
                location: paragraph.location, length: selection.location - paragraph.location
            ))
            let indent = String(head.prefix { $0 == " " || $0 == "\t" })
            let typed = String(head.dropFirst(indent.count))
            let checked: Bool
            switch typed {
            case "- [ ] ", "* [ ] ", "[] ", "[ ] ": checked = false
            case "- [x] ", "- [X] ": checked = true
            default: return
            }
            let marker = NSRange(
                location: paragraph.location + (indent as NSString).length,
                length: (typed as NSString).length
            )
            insertText(Checklist.prefix(checked: checked), replacementRange: marker)
            styleMarkUnderCursor()
        }

        /// Галочка в строке под курсором — своим шрифтом. Набранная, вставленная
        /// Enter'ом или переведённая из разметки, она приходит шрифтом набора.
        /// Меняется только оформление, без отмены: текст не трогается.
        private func styleMarkUnderCursor() {
            guard let storage = textStorage, storage.length > 0 else { return }
            let string = self.string as NSString
            let location = min(selectedRange().location, string.length)
            let paragraph = string.paragraphRange(for: NSRange(location: max(0, location == string.length ? location - 1 : location), length: 0))
            let line = string.substring(with: paragraph).trimmingCharacters(in: .newlines)
            guard let item = Checklist.item(inDisplay: line) else { return }
            Checklist.styleMark(storage, at: paragraph.location + (item.indent as NSString).length)
        }

        override func paste(_ sender: Any?) {
            super.paste(sender)
            onPaste?()
        }

        override func pasteAsPlainText(_ sender: Any?) {
            super.pasteAsPlainText(sender)
            onPaste?()
        }

        override func readSelection(
            from pboard: NSPasteboard,
            type: NSPasteboard.PasteboardType
        ) -> Bool {
            let accepted = super.readSelection(from: pboard, type: type)
            if accepted { onPaste?() }
            return accepted
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: () -> Void
        private let opensLinks: Bool

        init(onChange: @escaping () -> Void, opensLinks: Bool) {
            self.onChange = onChange
            self.opensLinks = opensLinks
        }

        func textDidChange(_ notification: Notification) {
            (notification.object as? PastingTextView)?.convertTypedCheckbox()
            onChange()
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            // `true` значит «нажатие обработано нами», то есть система
            // ссылку не откроет.
            !opensLinks
        }
    }
}
