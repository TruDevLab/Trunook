import AppKit

/// Правка оформленного текста поверх `NSTextView`.
///
/// Вынесено из телесуфлера, когда оформленный ввод понадобился второй раз —
/// в панели модели. Скопировать эти двести строк значило бы завести два
/// набора правил оформления, которые разойдутся при первой же правке: ровно
/// так уже расходились два расчёта состояния выреза, и стоило это полдня
/// поисков.
///
/// Правки применяются **прямо к полю**, а не к копии текста внутри
/// объекта: у `NSTextView` есть своя отмена (⌘Z) и свои выделения, и вторая
/// копия рядом однажды с ними рассинхронизируется.
final class RichTextEditor {
    /// Чем отличается один оформленный текст от другого: кеглями и цветом.
    ///
    /// Телесуфлер читают с расстояния, заметку — с обычного, и кегли у них
    /// разные. Всё остальное — правила оформления — общее.
    struct Style {
        let bodyFontSize: CGFloat
        let headingFontSize: CGFloat
        /// Цвет ссылок и курсора. Системная синева в вырезе смотрится чужой:
        /// это единственное место приложения, где она вообще появилась бы.
        let tint: NSColor

        static var teleprompter: Style {
            Style(
                bodyFontSize: TeleprompterStore.bodyFontSize,
                headingFontSize: TeleprompterStore.headingFontSize,
                tint: NSColor(Palette.teleprompter)
            )
        }

        static var note: Style {
            Style(
                bodyFontSize: Note.bodyFontSize,
                headingFontSize: Note.headingFontSize,
                tint: NSColor(Palette.assistant)
            )
        }
    }

    let style: Style

    /// Текст изменился нашей правкой. Хозяин решает, что с этим делать:
    /// телесуфлер откладывает запись на диск, черновик заметки — тоже.
    var onEdit: (() -> Void)?

    /// Поле ввода. Слабая ссылка: окном владеет контроллер, и переживать
    /// его редактору незачем.
    private weak var textView: NSTextView?

    init(style: Style) {
        self.style = style
    }

    // MARK: - Поле

    var view: NSTextView? { textView }

    func attach(_ view: NSTextView) {
        textView = view
    }

    func detach() {
        textView = nil
    }

    var isEmpty: Bool { (textView?.textStorage?.length ?? 0) == 0 }

    var attributed: NSAttributedString {
        textView?.textStorage.map { NSAttributedString(attributedString: $0) }
            ?? NSAttributedString(string: "")
    }

    /// Кладёт в поле готовый текст.
    ///
    /// Отмена после этого начинается с чистого листа: восстановление текста
    /// с диска или открытие заметки на правку — не правка человека,
    /// и откатывать её ему незачем.
    func setAttributed(_ text: NSAttributedString) {
        guard let view = textView, let storage = view.textStorage else { return }
        storage.setAttributedString(text)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.undoManager?.removeAllActions()
        applyDefaultTyping(to: view)
    }

    /// Оформление, с которым начинается набор в пустом поле.
    func applyDefaultTyping(to view: NSTextView) {
        view.typingAttributes = [
            .font: NSFont.systemFont(ofSize: style.bodyFontSize),
            .foregroundColor: NSColor.white,
        ]
    }

    func focus() {
        guard let view = textView else { return }
        view.window?.makeFirstResponder(view)
    }

    /// Палитра эмодзи — системная. Своей у приложения нет и быть не должно:
    /// человек уже умеет пользоваться этой.
    func showEmojiPalette() {
        focus()
        NSApp.orderFrontCharacterPalette(nil)
    }

    // MARK: - Оформление

    /// Заголовок — крупнее и жирнее, обычный текст — обратно.
    ///
    /// Абзацем целиком, а не выделением: заголовок — это свойство строки,
    /// и половина строки заголовком не бывает. Достаточно поставить курсор
    /// в строку, выделять её не нужно.
    func toggleHeading() {
        edit { storage, _, view in
            let range = (view.string as NSString).paragraphRange(for: view.selectedRange())
            guard range.length > 0 else { return }
            let isHeading = self.fontSize(in: storage, at: range.location) >= self.style.headingFontSize
            let font = isHeading
                ? NSFont.systemFont(ofSize: self.style.bodyFontSize)
                : NSFont.boldSystemFont(ofSize: self.style.headingFontSize)
            storage.addAttribute(.font, value: font, range: range)
        }
    }

    func toggleBold() { toggleTrait(.bold) }
    func toggleItalic() { toggleTrait(.italic) }

    /// Подчёркивание — своим свойством, а не начертанием шрифта: у системного
    /// шрифта подчёркнутого начертания нет вовсе.
    func toggleUnderline() {
        edit { storage, range, _ in
            let existing = storage.attribute(.underlineStyle, at: range.location, effectiveRange: nil)
            let isUnderlined = (existing as? Int ?? 0) != 0
            if isUnderlined {
                storage.removeAttribute(.underlineStyle, range: range)
            } else {
                storage.addAttribute(
                    .underlineStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: range
                )
            }
        }
    }

    /// Ссылка на выделенном тексте. Пустое выделение снимает ссылку —
    /// иначе снять её было бы нечем.
    func applyLink(_ address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        edit { storage, range, _ in
            guard !trimmed.isEmpty, let url = Self.url(from: trimmed) else {
                storage.removeAttribute(.link, range: range)
                storage.removeAttribute(.underlineStyle, range: range)
                return
            }
            storage.addAttribute(.link, value: url, range: range)
            // Подчёркивание ставим сами: без него ссылка в чёрной панели
            // отличается от текста только оттенком, а его на репетиции
            // не разглядеть.
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            storage.addAttribute(.foregroundColor, value: self.style.tint, range: range)
        }
    }

    /// Адрес без схемы — всё ещё адрес: «trunook.ru» человек напишет чаще,
    /// чем «https://trunook.ru».
    static func url(from text: String) -> URL? {
        if let url = URL(string: text), url.scheme != nil { return url }
        return URL(string: "https://" + text)
    }

    // MARK: - Чужие цвета

    /// Снимает с текста цвет и подложку, пришедшие извне.
    ///
    /// Вставленное из браузера или документа приносит свой цвет. Чёрный текст
    /// на чёрной панели попросту не виден, и поменять его руками нечем —
    /// кнопки цвета здесь нет и не будет. Поле выглядело бы пустым, оставаясь
    /// непустым: беда тихая и оттого злая.
    ///
    /// Начертания не трогаем: полужирный и курсив в чужом тексте — это его
    /// смысл, а не подгонка под чужую тему. Ссылкам возвращается наш оттенок,
    /// а не белый: иначе ссылка перестала бы отличаться от текста.
    func normalizeColors() {
        guard let view = textView, let storage = view.textStorage else { return }
        let all = NSRange(location: 0, length: storage.length)
        guard all.length > 0 else { return }

        view.shouldChangeText(in: all, replacementString: nil)
        storage.beginEditing()
        Self.normalize(storage, tint: style.tint)
        storage.endEditing()
        view.didChangeText()

        // Набор после вставки продолжается своим цветом, а не подхваченным
        // из вставленного куска.
        applyDefaultTyping(to: view)
    }

    /// То же самое, но над готовым текстом — когда поля ещё нет.
    ///
    /// Нужно потому, что заметку открывают на правку **до** того, как SwiftUI
    /// построит поле: панель в этот миг ещё показывает разговор.
    static func normalized(_ text: NSAttributedString, tint: NSColor) -> NSAttributedString {
        let storage = NSMutableAttributedString(attributedString: text)
        guard storage.length > 0 else { return storage }
        storage.beginEditing()
        normalize(storage, tint: tint)
        storage.endEditing()
        return storage
    }

    private static func normalize(_ storage: NSMutableAttributedString, tint: NSColor) {
        let all = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.backgroundColor, range: all)
        storage.enumerateAttribute(.link, in: all) { link, range, _ in
            storage.addAttribute(.foregroundColor, value: link == nil ? NSColor.white : tint, range: range)
        }
    }

    // MARK: - Очистка

    func clear() {
        guard let view = textView, let storage = view.textStorage else { return }
        let all = NSRange(location: 0, length: storage.length)
        view.shouldChangeText(in: all, replacementString: "")
        storage.setAttributedString(NSAttributedString(string: ""))
        view.didChangeText()
        applyDefaultTyping(to: view)
        focus()
    }

    // MARK: - Общая обвязка

    private func toggleTrait(_ trait: NSFontDescriptor.SymbolicTraits) {
        edit { storage, range, _ in
            let manager = NSFontManager.shared
            // Смотрим на начало выделения: если оно уже такое, снимаем —
            // так же ведут себя ⌘B и ⌘I во всех текстовых редакторах.
            let current = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            let base = current ?? NSFont.systemFont(ofSize: self.style.bodyFontSize)
            let isOn = base.fontDescriptor.symbolicTraits.contains(trait)
            let change: NSFontTraitMask = trait == .bold
                ? (isOn ? .unboldFontMask : .boldFontMask)
                : (isOn ? .unitalicFontMask : .italicFontMask)

            storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = value as? NSFont ?? NSFont.systemFont(ofSize: self.style.bodyFontSize)
                storage.addAttribute(
                    .font,
                    value: manager.convert(font, toHaveTrait: change),
                    range: subrange
                )
            }
        }
    }

    /// Взять поле, отбить правку в отмену, вернуть фокус и сообщить наружу.
    ///
    /// Фокус возвращается непременно: кнопки оформления живут в SwiftUI,
    /// нажатие по ним уводит первого отвечающего из поля, и без возврата
    /// следующая правка пришлась бы в пустоту — а выглядело бы это как
    /// «кнопка сработала один раз».
    private func edit(_ change: (NSTextStorage, NSRange, NSTextView) -> Void) {
        guard let view = textView, let storage = view.textStorage else { return }
        var range = view.selectedRange()
        // Пустое выделение — работаем с абзацем под курсором: оформлять
        // нечего, а промолчать в ответ на нажатие кнопки нельзя.
        if range.length == 0 {
            range = (view.string as NSString).paragraphRange(for: range)
        }
        guard range.length > 0, NSMaxRange(range) <= storage.length else {
            focus()
            return
        }

        view.shouldChangeText(in: range, replacementString: nil)
        storage.beginEditing()
        change(storage, range, view)
        storage.endEditing()
        view.didChangeText()

        view.setSelectedRange(range)
        focus()
        onEdit?()
    }

    private func fontSize(in storage: NSTextStorage, at location: Int) -> CGFloat {
        guard location < storage.length,
              let font = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        else { return style.bodyFontSize }
        return font.pointSize
    }
}
