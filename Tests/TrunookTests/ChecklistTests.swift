import AppKit
import Testing
@testable import Trunook

@Suite("Списки с галочками")
struct ChecklistTests {
    @Test("Разметка пункта разбирается во всех написаниях")
    func разборРазметки() {
        #expect(Checklist.item(inMarkdown: "- [ ] Купить хлеб") == .init(indent: "", isChecked: false, rest: "Купить хлеб"))
        #expect(Checklist.item(inMarkdown: "  * [x] Готово")?.isChecked == true)
        #expect(Checklist.item(inMarkdown: "+ [X] Готово")?.isChecked == true)
        #expect(Checklist.item(inMarkdown: "- [ ]") == .init(indent: "", isChecked: false, rest: ""))
        #expect(Checklist.item(inMarkdown: "- пункт") == nil)
        #expect(Checklist.item(inMarkdown: "- [ссылка](https://x)") == nil)
        #expect(Checklist.item(inMarkdown: "-[ ] слитно") == nil)
    }

    @Test("Строка текста заметки и строка разметки переводятся друг в друга")
    func переводСтрок() {
        #expect(Checklist.display(fromMarkdown: "- [ ] Позвонить") == "☐ Позвонить")
        #expect(Checklist.display(fromMarkdown: "\t- [x] Позвонить") == "\t☑ Позвонить")
        #expect(Checklist.markdown(fromDisplay: "☑ Позвонить") == "- [x] Позвонить")
        #expect(Checklist.markdown(fromDisplay: "  ☐ Позвонить") == "  - [ ] Позвонить")
        #expect(Checklist.markdown(fromDisplay: "☐слитно — не пункт") == "☐слитно — не пункт")
    }

    @Test("Превью заметки, записанной разметкой, показывает галочки")
    func превью() {
        let note = Note(id: 1, title: "Дела", rtf: Data(), plain: "- [ ] Хлеб\n- [x] Молоко",
                        createdAt: Date(), updatedAt: Date(), origin: .typed, titleByModel: true)
        #expect(note.oneLine == "☐ Хлеб ☑ Молоко")
    }

    /// Круг «файл → заметка → файл» не должен ничего терять: пункт обязан
    /// вернуться в Obsidian той же разметкой, а отмеченный — остаться
    /// отмеченным.
    @Test("Круг через Obsidian сохраняет пункты и отметки")
    func кругЧерезObsidian() {
        let markdown = "Список\n- [ ] Хлеб\n- [x] **Молоко**\n  - [ ] Вложенный"
        let attributed = ObsidianMarkdown.attributed(from: markdown)
        #expect(attributed.string == "Список\n☐ Хлеб\n☑ Молоко\n  ☐ Вложенный")
        #expect(NoteMarkdown.body(attributed) == markdown)
    }

    @Test("Отмеченный пункт зачёркнут, неотмеченный — нет")
    func оформление() {
        let attributed = ObsidianMarkdown.attributed(from: "- [x] Готово\n- [ ] Нет")
        let string = attributed.string as NSString
        let done = string.range(of: "Готово")
        let open = string.range(of: "Нет")
        #expect(attributed.attribute(.strikethroughStyle, at: done.location, effectiveRange: nil) != nil)
        #expect(attributed.attribute(.strikethroughStyle, at: open.location, effectiveRange: nil) == nil)
    }

    @Test("Заметка, записанная разметкой, при открытии получает галочки")
    func открытиеСтаройЗаметки() {
        let old = NSAttributedString(string: "- [ ] Хлеб\n- [x] Молоко", attributes: [
            .font: NSFont.systemFont(ofSize: Note.bodyFontSize), .foregroundColor: NSColor.white,
        ])
        let opened = RichTextEditor.normalized(old, tint: .systemPurple)
        #expect(opened.string == "☐ Хлеб\n☑ Молоко")
        let milk = (opened.string as NSString).range(of: "Молоко")
        #expect(opened.attribute(.strikethroughStyle, at: milk.location, effectiveRange: nil) != nil)
    }

    /// RTF — то, в чём заметка лежит в базе. Галочка, не пережившая его,
    /// пропала бы при первом же сохранении.
    @Test("Галочки переживают RTF")
    func переживаютRTF() throws {
        let text = ObsidianMarkdown.attributed(from: "- [x] Готово\n- [ ] Нет")
        let rtf = try #require(text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:]))
        let back = try #require(NSAttributedString(rtf: rtf, documentAttributes: nil))
        #expect(back.string == "☑ Готово\n☐ Нет")
        #expect(NoteMarkdown.body(back) == "- [x] Готово\n- [ ] Нет")
    }
}

@Suite("Галочки в поле правки")
@MainActor
struct ChecklistEditingTests {
    private func field(_ text: String) -> (RichTextView.PastingTextView, RichTextEditor) {
        let view = RichTextView.PastingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.isRichText = true
        let editor = RichTextEditor(style: .note)
        editor.attach(view)
        editor.setAttributed(RichTextEditor.normalized(
            NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: Note.bodyFontSize), .foregroundColor: NSColor.white,
            ]),
            tint: .systemPurple
        ))
        return (view, editor)
    }

    @Test("Щелчок по галочке ставит и снимает отметку")
    func отметка() {
        let (view, _) = field("☐ Хлеб")
        view.toggleCheckbox(at: 0)
        #expect(view.string == "☑ Хлеб")
        #expect(view.textStorage?.attribute(.strikethroughStyle, at: 2, effectiveRange: nil) != nil)
        view.toggleCheckbox(at: 0)
        #expect(view.string == "☐ Хлеб")
        #expect(view.textStorage?.attribute(.strikethroughStyle, at: 2, effectiveRange: nil) == nil)
    }

    @Test("Enter продолжает список, Enter в пустом пункте его заканчивает")
    func enter() {
        let (view, _) = field("☐ Хлеб")
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        view.insertNewline(nil)
        #expect(view.string == "☐ Хлеб\n☐ ")
        view.insertNewline(nil)
        #expect(view.string == "☐ Хлеб\n")
    }

    @Test("Набранное «[] » в начале строки становится галочкой")
    func набор() {
        let (view, _) = field("")
        view.insertText("[] ", replacementRange: NSRange(location: 0, length: 0))
        view.convertTypedCheckbox()
        #expect(view.string == "☐ ")
    }

    @Test("Кнопка списка делает пункты и снимает их")
    func кнопка() {
        let (view, editor) = field("Хлеб\nМолоко")
        view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
        editor.toggleChecklist()
        #expect(view.string == "☐ Хлеб\n☐ Молоко")
        view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
        editor.toggleChecklist()
        #expect(view.string == "Хлеб\nМолоко")
    }
}
