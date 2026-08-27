import TrunookXPC
import AppKit
import Foundation

/// Чем панель занята прямо сейчас.
///
/// Режимы, а не одно поле на две работы. Одно поле пробовали: набранное можно
/// было отправить модели или сохранить заметкой, и выбор делался кнопкой уже
/// после набора. Оказалось хуже — потому что от выбора зависит **само поле**.
/// Вопросу нужна одна строка и отправка по Enter, заметке — несколько строк
/// и Enter как перевод строки. Совместить это в одном поле нельзя: либо
/// вопрос отправляется через кнопку, либо заметку нельзя набрать в два абзаца.
enum NotePanelMode: String, CaseIterable, Identifiable {
    /// Разговор с моделью: строка вопроса, ответ, поиск по заметкам.
    case model
    /// Заметка: многострочное поле с оформлением, ответа модели нет вовсе.
    case note

    var id: String { rawValue }

    var title: String {
        switch self {
        // «Команды», а не «ИИ»: с выключенной моделью в этом режиме остаются
        // ровно они — захваченное и список того, что с ним сделать. Название,
        // обещающее модель, оказывалось бы прямой неправдой ровно тогда,
        // когда человек и так недоумевает, куда она делась.
        case .model: return t("Команды")
        case .note: return t("Заметка")
        }
    }

    var symbol: String {
        switch self {
        case .model: return "square.grid.2x2"
        case .note: return "square.and.pencil"
        }
    }
}

/// Набранное в панели: вопрос модели и текст заметки.
///
/// Два содержимого, а не одно, и переключение между ними ничего не теряет:
/// начал писать заметку, вспомнил вопрос, спросил, вернулся — заметка на месте.
///
/// Текст заметки живёт на диске. Накладка закрывается щелчком мимо, и с одной
/// строкой это было безобидно, а с набранной заметкой означало бы потерю
/// работы. Правило закрытия менять не пришлось: текст просто возвращается.
final class NoteDraft: ObservableObject {
    /// Чем панель занята. Переживает закрытие панели: человек, писавший
    /// заметку, вернётся к заметке, а не к пустому вопросу.
    @Published private(set) var mode: NotePanelMode = .model

    /// Строка вопроса — режим ИИ.
    @Published var question = ""

    /// Пуст ли текст заметки. По нему гаснет «Сохранить»: кнопка, которой
    /// нечего делать, хуже её отсутствия.
    @Published private(set) var isNoteEmpty = true

    /// Правится существующая заметка, а не пишется новая.
    ///
    /// От этого меняются и название панели, и то, что делает сохранение:
    /// переписать эту заметку, а не завести рядом вторую такую же.
    @Published private(set) var editingID: Int64?

    /// Что панель спрашивает у человека прямо сейчас.
    ///
    /// Спрашивает своей же строкой, а не всплывающим окном: окно система
    /// ставит по центру экрана — то есть под чёлкой, — и панель его
    /// закрывает. Диалог есть, а увидеть его нельзя.
    @Published var prompt: Prompt?
    @Published var linkAddress = ""

    enum Prompt: Equatable {
        case link
    }

    let editor = RichTextEditor(style: .note)

    /// Текст, который ждёт своего поля.
    ///
    /// Заметку открывают на правку, когда панель ещё показывает разговор:
    /// поля заметки в этот миг не существует, и класть текст некуда. Он ждёт
    /// здесь и попадает в поле, как только SwiftUI его построит.
    ///
    /// Без этого правка открывалась **пустой**: текст уходил в никуда,
    /// а приложение поля тут же затирало его черновиком с диска.
    private var pendingText: NSAttributedString?

    /// Через сколько тишины набранное уходит на диск.
    private static let saveDelay: TimeInterval = 1.0
    private var saveTimer: Timer?

    static let fileURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base
            .appendingPathComponent("Trunook", isDirectory: true)
            .appendingPathComponent("assistant-draft.rtf")
    }()

    init() {
        editor.onEdit = { [weak self] in
            self?.refreshEmptiness()
            self?.scheduleSave()
        }
    }

    // MARK: - Режим

    func setMode(_ mode: NotePanelMode) {
        guard mode != self.mode else { return }
        // Уходя из заметки, сохраняем набранное сразу: панель могут закрыть
        // из другого режима, и отложенная запись до диска не дойдёт.
        if self.mode == .note { saveNow() }
        self.mode = mode
        prompt = nil
        DebugLog.write("панель: режим \(mode.rawValue)")
    }

    /// Пусто ли то, что сейчас набирают.
    var isEmpty: Bool {
        switch mode {
        case .model: return question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .note: return isNoteEmpty
        }
    }

    // MARK: - Поле заметки

    /// Поле построено — кладём в него то, на чём остановились.
    ///
    /// Ждущий текст важнее черновика: он появился позже и по прямому
    /// указанию — открыли заметку на правку.
    func attach(_ view: NSTextView) {
        editor.setAttributed(pendingText ?? loadFromDisk())
        pendingText = nil
        refreshEmptiness()
    }

    func textDidChange() {
        refreshEmptiness()
        scheduleSave()
    }

    /// Вставили чужой текст.
    ///
    /// Цвет и подложку с него снимаем: скопированное из браузера или документа
    /// приносит свой цвет, и чёрный текст на чёрной панели попросту не виден.
    /// Поменять его руками нечем — кнопки цвета у нас нет и не будет, — так
    /// что заметка выглядела бы пустой, оставаясь непустой.
    ///
    /// Начертания при этом остаются: полужирный и курсив в чужом тексте —
    /// это его смысл, а не оформление под чужую тему.
    func didPaste() {
        editor.normalizeColors()
        refreshEmptiness()
        scheduleSave()
    }

    private func refreshEmptiness() {
        // Пока поле не построено, о пустоте говорит ждущий текст: у пустого
        // редактора без поля ответ был бы «пусто» на любую заметку.
        let text = pendingText?.string ?? editor.attributed.string
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard empty != isNoteEmpty else { return }
        isNoteEmpty = empty
    }

    var attributed: NSAttributedString { editor.attributed }
    var plain: String { editor.attributed.string }

    func focusNote() { editor.focus() }

    // MARK: - Оформление

    func toggleHeading() { editor.toggleHeading() }
    func toggleBold() { editor.toggleBold() }
    func toggleItalic() { editor.toggleItalic() }

    func askForLink() {
        linkAddress = ""
        prompt = .link
    }

    func confirmLink() {
        let address = linkAddress
        prompt = nil
        linkAddress = ""
        editor.applyLink(address)
    }

    func cancelPrompt() {
        prompt = nil
        linkAddress = ""
        editor.focus()
    }

    // MARK: - Содержимое

    /// Открыть заметку на правку.
    ///
    /// Режим переключается сам: заметка, открытая в режиме ИИ, показывалась бы
    /// поверх чужого ответа модели и с однострочным полем — то есть как что
    /// угодно, только не как заметка на правке.
    func load(_ note: Note) {
        setMode(.note)
        editingID = note.id
        let text = RichTextEditor.normalized(note.attributed, tint: editor.style.tint)
        if editor.view == nil {
            // Поля ещё нет — панель показывала разговор. Текст подождёт.
            pendingText = text
        } else {
            editor.setAttributed(text)
        }
        refreshEmptiness()
        saveNow()
        DebugLog.write("заметки: правка \(note.id) открыта в панели")
    }

    /// Новая заметка с чистого листа — кнопкой в списке или клавишей.
    ///
    /// Набранное не трогаем: человек мог отвлечься на список посреди заметки
    /// и вернуться. Сбрасывается только привязка к правившейся записи, иначе
    /// новая заметка молча переписала бы старую.
    func startNewNote() {
        setMode(.note)
        editingID = nil
    }

    /// Набранное ушло — вопросом модели или заметкой.
    func clearNote() {
        editingID = nil
        pendingText = nil
        editor.clear()
        refreshEmptiness()
        saveNow()
    }

    func clearQuestion() {
        question = ""
    }

    /// Панель закрылась. Текст остаётся на диске, а вот правка заметки —
    /// нет: сохранять вслепую в запись, про которую уже забыли, что её
    /// открывали, нельзя.
    func endEditing() {
        editingID = nil
    }

    // MARK: - Хранение

    private func loadFromDisk() -> NSAttributedString {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let text = NSAttributedString(rtf: data, documentAttributes: nil)
        else { return NSAttributedString(string: "") }
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

        // Без поля сохранять нечего — и, что важнее, нечего **стирать**.
        // Пока этой проверки не было, закрытие панели из режима ИИ сносило
        // черновик заметки: поля в этот миг нет, редактор пуст, и пустота
        // честно записывалась поверх набранного.
        guard editor.view != nil else { return }

        let text = editor.attributed
        let url = Self.fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard text.length > 0 else {
            // Пустой черновик — это не «нечего сохранять», а «файла быть
            // не должно»: иначе он вернул бы прошлый текст при следующем
            // открытии панели.
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = text.rtf(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [:]
        ) else {
            DebugLog.write("черновик: текст не собрался в RTF")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            // Промолчать нельзя: человек считает, что набранное не пропадёт.
            DebugLog.write("черновик: не сохранить — \(error.localizedDescription)")
        }
    }
}
