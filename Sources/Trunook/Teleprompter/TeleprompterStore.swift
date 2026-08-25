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

    /// Правка оформления. Общая с панелью модели: два набора правил
    /// оформления разошлись бы при первой же правке.
    let editor = RichTextEditor(style: .teleprompter)

    /// Само поле — у редактора. Здесь оно нужно прокрутке и записи на диск.
    private var textView: NSTextView? { editor.view }

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
        editor.onEdit = { [weak self] in
            self?.refreshEmptiness()
            self?.scheduleSave()
        }
    }

    var speed: Int {
        get { settings.teleprompterSpeed }
        set {
            objectWillChange.send()
            settings.teleprompterSpeed = min(Self.maxSpeed, max(Self.minSpeed, newValue))
        }
    }

    // MARK: - Поле ввода

    /// Поле готово — отдаём его редактору и кладём сохранённый текст.
    func attach(_ view: NSTextView) {
        editor.attach(view)
        editor.setAttributed(loadFromDisk())
        refreshEmptiness()
    }

    func detach() {
        stopScrolling()
        saveNow()
        editor.detach()
    }

    /// В суфлер вставили чужой текст.
    ///
    /// Речь в него как раз и вставляют — из документа, из письма, из чата, —
    /// и приходит она со своим цветом. Чёрный на чёрной панели не виден,
    /// а поменять его нечем: кнопки цвета здесь нет.
    func didPaste() {
        editor.normalizeColors()
        refreshEmptiness()
        scheduleSave()
    }

    /// Текст поменялся. Зовётся делегатом поля на каждой правке.
    func textDidChange() {
        refreshEmptiness()
        scheduleSave()
    }

    private func refreshEmptiness() {
        let empty = editor.isEmpty
        guard empty != isEmpty else { return }
        isEmpty = empty
    }

    // MARK: - Оформление

    /// Оформление целиком лежит в `RichTextEditor` — здесь только
    /// переадресация.
    ///
    /// Кнопки панели зовут телесуфлер, а не редактор напрямую, и это
    /// нарочно: панель знает про свой телесуфлер, а про то, что правки
    /// общие с панелью модели, ей знать незачем.
    func toggleHeading() { editor.toggleHeading() }
    func toggleBold() { editor.toggleBold() }
    func toggleItalic() { editor.toggleItalic() }
    func toggleUnderline() { editor.toggleUnderline() }
    func applyLink(_ address: String) { editor.applyLink(address) }

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

    func showEmojiPalette() { editor.showEmojiPalette() }

    private func focusText() { editor.focus() }

    // MARK: - Очистка

    /// Единственный способ потерять текст — и потому спрашивает подтверждения.
    /// Речь набирают один раз, а нажимают мимо регулярно.
    func clear() {
        stopScrolling()
        editor.clear()
        refreshEmptiness()
        saveNow()
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
}
