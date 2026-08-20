import TrunookXPC
import AppKit
import Foundation

/// Текст телесуфлера, его оформление и автопрокрутка.
///
/// Хранит и правит **один** документ: телесуфлер — это лист, который читают
/// вслух, а не список записей. Поэтому ни истории, ни срока хранения здесь
/// нет, и текст не пропадает сам ни при закрытии панели, ни при перезапуске
/// приложения — только по кнопке «Очистить». Человек, набравший речь
/// и потерявший её из-за того, что панель закрылась, второй раз сюда
/// не вернётся.
///
/// Правки применяются прямо к `NSTextView`, а не к копии текста в этом
/// объекте: у поля есть своя отмена (⌘Z) и свои выделения, и держать рядом
/// вторую копию значило бы однажды их рассинхронизировать.
final class TeleprompterStore: ObservableObject {
    /// Идёт ли автопрокрутка. Наблюдается вёрсткой: кнопка «Пуск» превращается
    /// в «Стоп», и обратно — сама, когда прокрутка упёрлась в конец текста.
    @Published private(set) var isScrolling = false
    /// Пусто ли поле. По нему гаснет «Очистить»: кнопка, которой нечего
    /// делать, хуже её отсутствия.
    @Published private(set) var isEmpty = true

    /// Что панель спрашивает у человека прямо сейчас.
    ///
    /// Спрашивает **своей же строкой**, а не всплывающим окном. Окно система
    /// ставит по центру экрана — то есть под чёлкой, — и панель телесуфлера
    /// его закрывала: диалог был, а увидеть его было нельзя. Строка на месте
    /// полосы управления решает это целиком и заодно не отбирает панель
    /// у остального экрана.
    @Published var prompt: Prompt?
    /// Адрес, набираемый в строке ссылки.
    @Published var linkAddress = ""

    enum Prompt: Equatable {
        case link
        case clear
    }

    private let settings: Settings

    /// Поле ввода. Слабая ссылка: окном владеет контроллер, и переживать
    /// его хранилищу незачем.
    private weak var textView: NSTextView?

    private var scrollTimer: Timer?
    /// Недобранная за тик доля точки. Без неё медленная скорость округлялась
    /// бы до нуля на каждом тике, и текст стоял бы на месте.
    private var scrollRemainder: CGFloat = 0
    /// Отложенное сохранение: писать файл на каждое нажатие клавиши
    /// расточительно, а терять набранное нельзя.
    private var saveTimer: Timer?

    /// Как часто двигаем текст. Шестьдесят раз в секунду: реже — и движение
    /// читается рывками, а телесуфлер читают глазами построчно.
    private static let tickInterval: TimeInterval = 1.0 / 60
    /// Через сколько тишины набранное уходит на диск.
    private static let saveDelay: TimeInterval = 1.0

    /// Размеры текста. Телесуфлер читают с расстояния, поэтому крупнее
    /// обычного поля ввода.
    static let bodyFontSize: CGFloat = 20
    static let headingFontSize: CGFloat = 30

    /// Пределы скорости в точках в секунду. Ниже пяти движение неотличимо
    /// от неподвижности, выше двухсот текст не успевают читать.
    static let minSpeed = 5
    static let maxSpeed = 200

    static let fileURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base
            .appendingPathComponent("Trunook", isDirectory: true)
            .appendingPathComponent("teleprompter.rtf")
    }()

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    var speed: Int {
        get { settings.teleprompterSpeed }
        set {
            objectWillChange.send()
            settings.teleprompterSpeed = min(Self.maxSpeed, max(Self.minSpeed, newValue))
        }
    }

    // MARK: - Поле ввода

    /// Поле готово — забираем его себе и кладём в него сохранённый текст.
    func attach(_ view: NSTextView) {
        textView = view
        view.textStorage?.setAttributedString(loadFromDisk())
        view.setSelectedRange(NSRange(location: 0, length: 0))
        // Отмена начинается с этого момента: восстановление текста с диска —
        // не правка человека, и откатывать её ему незачем.
        view.undoManager?.removeAllActions()
        refreshEmptiness()
    }

    func detach() {
        stopScrolling()
        saveNow()
        textView = nil
    }

    /// Текст поменялся. Зовётся делегатом поля на каждой правке.
    func textDidChange() {
        refreshEmptiness()
        scheduleSave()
    }

    private func refreshEmptiness() {
        let empty = (textView?.textStorage?.length ?? 0) == 0
        guard empty != isEmpty else { return }
        isEmpty = empty
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
            let isHeading = Self.fontSize(in: storage, at: range.location) >= Self.headingFontSize
            let font = isHeading
                ? NSFont.systemFont(ofSize: Self.bodyFontSize)
                : NSFont.boldSystemFont(ofSize: Self.headingFontSize)
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
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
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
            storage.addAttribute(.foregroundColor, value: NSColor(Palette.teleprompter), range: range)
        }
    }

    /// Адрес без схемы — всё ещё адрес: «trunook.ru» человек напишет чаще,
    /// чем «https://trunook.ru».
    private static func url(from text: String) -> URL? {
        if let url = URL(string: text), url.scheme != nil { return url }
        return URL(string: "https://" + text)
    }

    /// Спросить адрес ссылки строкой панели.
    func askForLink() {
        linkAddress = ""
        prompt = .link
    }

    /// Спросить подтверждение очистки. Переспрашиваем потому, что это
    /// единственный способ потерять текст: речь набирают один раз,
    /// а мимо кнопки попадают регулярно.
    func askToClear() {
        prompt = .clear
    }

    func cancelPrompt() {
        prompt = nil
        linkAddress = ""
        focusText()
    }

    /// Применить набранный адрес и убрать строку.
    func confirmLink() {
        let address = linkAddress
        prompt = nil
        linkAddress = ""
        applyLink(address)
    }

    func confirmClear() {
        prompt = nil
        clear()
    }

    /// Палитра эмодзи — системная. Своей у приложения нет и быть не должно:
    /// человек уже умеет пользоваться этой.
    func showEmojiPalette() {
        focusText()
        NSApp.orderFrontCharacterPalette(nil)
    }

    private func toggleTrait(_ trait: NSFontDescriptor.SymbolicTraits) {
        edit { storage, range, _ in
            let manager = NSFontManager.shared
            // Смотрим на начало выделения: если оно уже такое, снимаем —
            // так же ведут себя ⌘B и ⌘I во всех текстовых редакторах.
            let current = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            let base = current ?? NSFont.systemFont(ofSize: Self.bodyFontSize)
            let isOn = base.fontDescriptor.symbolicTraits.contains(trait)
            let change: NSFontTraitMask = trait == .bold
                ? (isOn ? .unboldFontMask : .boldFontMask)
                : (isOn ? .unitalicFontMask : .italicFontMask)

            storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = value as? NSFont ?? NSFont.systemFont(ofSize: Self.bodyFontSize)
                storage.addAttribute(.font, value: manager.convert(font, toHaveTrait: change), range: subrange)
            }
        }
    }

    /// Общая обвязка правок: взять поле, отбить правку в отмену, вернуть
    /// фокус и сохранить.
    ///
    /// Фокус возвращается непременно: кнопки оформления живут в SwiftUI,
    /// нажатие по ним уводит первого отвечающего из поля, и без возврата
    /// следующая правка пришлась бы в пустоту — а выглядело бы это как
    /// «кнопка сработала один раз».
    private func edit(_ change: (NSTextStorage, NSRange, NSTextView) -> Void) {
        guard let view = textView, let storage = view.textStorage else { return }
        var range = view.selectedRange()
        // Пустое выделение — работаем со словом под курсором: оформлять
        // нечего, а промолчать в ответ на нажатие кнопки нельзя.
        if range.length == 0 {
            range = (view.string as NSString).paragraphRange(for: range)
        }
        guard range.length > 0, NSMaxRange(range) <= storage.length else {
            focusText()
            return
        }

        view.shouldChangeText(in: range, replacementString: nil)
        storage.beginEditing()
        change(storage, range, view)
        storage.endEditing()
        view.didChangeText()

        view.setSelectedRange(range)
        focusText()
        scheduleSave()
    }

    private static func fontSize(in storage: NSTextStorage, at location: Int) -> CGFloat {
        guard location < storage.length,
              let font = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        else { return bodyFontSize }
        return font.pointSize
    }

    private func focusText() {
        guard let view = textView else { return }
        view.window?.makeFirstResponder(view)
    }

    // MARK: - Очистка

    /// Единственный способ потерять текст — и потому спрашивает подтверждения.
    /// Речь набирают один раз, а нажимают мимо регулярно.
    func clear() {
        guard let view = textView, let storage = view.textStorage else { return }
        stopScrolling()
        let all = NSRange(location: 0, length: storage.length)
        view.shouldChangeText(in: all, replacementString: "")
        storage.setAttributedString(NSAttributedString(string: ""))
        view.didChangeText()
        applyDefaultTyping(to: view)
        refreshEmptiness()
        saveNow()
        focusText()
        DebugLog.write("телесуфлер: текст очищен")
    }

    // MARK: - Автопрокрутка

    func toggleScrolling() {
        isScrolling ? stopScrolling() : startScrolling()
    }

    func startScrolling() {
        guard !isScrolling, textView != nil else { return }
        isScrolling = true
        scrollRemainder = 0
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            self?.step()
        }
        // В `.common`: на обычной очереди прокрутка вставала бы на всё время,
        // пока человек держит мышь на ползунке скорости.
        RunLoop.main.add(timer, forMode: .common)
        scrollTimer = timer
        DebugLog.write("телесуфлер: автопрокрутка пущена, \(speed) точек в секунду")
    }

    func stopScrolling() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        guard isScrolling else { return }
        isScrolling = false
    }

    /// Один шаг прокрутки. Остановка на конце текста — не ошибка, а конец
    /// речи: дальше листать нечего, и кнопка сама возвращается в «Пуск».
    private func step() {
        guard let view = textView, let clip = view.enclosingScrollView?.contentView else {
            stopScrolling()
            return
        }
        let limit = max(0, view.frame.height - clip.bounds.height)
        guard clip.bounds.origin.y < limit else {
            stopScrolling()
            return
        }

        scrollRemainder += CGFloat(speed) * CGFloat(Self.tickInterval)
        let whole = scrollRemainder.rounded(.down)
        guard whole >= 1 else { return }
        scrollRemainder -= whole

        var origin = clip.bounds.origin
        origin.y = min(limit, origin.y + whole)
        clip.scroll(to: origin)
        view.enclosingScrollView?.reflectScrolledClipView(clip)
    }

    /// Вернуть текст к началу: прочитали — и снова с первой строки.
    func scrollToStart() {
        guard let clip = textView?.enclosingScrollView?.contentView else { return }
        clip.scroll(to: CGPoint(x: clip.bounds.origin.x, y: 0))
        textView?.enclosingScrollView?.reflectScrolledClipView(clip)
        scrollRemainder = 0
    }

    // MARK: - Хранение

    /// RTF, а не обычный текст: оформление — половина смысла телесуфлера,
    /// и терять его при перезапуске нельзя. И не UserDefaults: там бы лежал
    /// весь текст речи, а файл настроек читается при каждом запуске.
    private func loadFromDisk() -> NSAttributedString {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let text = NSAttributedString(
                  rtf: data,
                  documentAttributes: nil
              )
        else { return NSAttributedString(string: "") }
        DebugLog.write("телесуфлер: прочитано символов \(text.length)")
        return text
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        let timer = Timer(timeInterval: Self.saveDelay, repeats: false) { [weak self] _ in
            self?.saveNow()
        }
        RunLoop.main.add(timer, forMode: .common)
        saveTimer = timer
    }

    func saveNow() {
        saveTimer?.invalidate()
        saveTimer = nil
        guard let storage = textView?.textStorage else { return }

        let url = Self.fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let all = NSRange(location: 0, length: storage.length)
        guard let data = storage.rtf(from: all, documentAttributes: [:]) else {
            DebugLog.write("телесуфлер: текст не собрался в RTF")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            // Промолчать нельзя: человек считает, что речь сохранена.
            DebugLog.write("телесуфлер: не сохранить — \(error.localizedDescription)")
        }
    }

    /// Оформление, с которым начинается набор в пустом поле.
    func applyDefaultTyping(to view: NSTextView) {
        view.typingAttributes = [
            .font: NSFont.systemFont(ofSize: Self.bodyFontSize),
            .foregroundColor: NSColor.white,
        ]
    }
}
