import Testing
import Foundation
@testable import Trunook

@Suite("Помощь при письме")
struct WritingHelpTests {
    private func command(_ id: Int, _ kind: QuickCommand.Kind, payload: String = "x", passes: Bool = false,
                         enabled: Bool = true) -> QuickCommand {
        var command = QuickCommand(id: id, title: "К\(id)", kind: kind, payload: payload, symbol: "",
                                   isEnabled: enabled, hotKey: nil)
        command.passesSelection = passes
        return command
    }

    @Test("На плашку — первые шесть команд, работающих с текстом")
    func команды() {
        let list = [
            command(0, .ollama), command(1, .openApp), command(2, .saveToNotes, payload: ""),
            command(3, .shortcut, passes: false), command(4, .shortcut, passes: true),
            command(5, .ollama, enabled: false), command(6, .ollama), command(7, .ollama),
            command(8, .ollama), command(9, .ollama),
        ]
        let picked = WritingHelpRules.commands(from: list, modelEnabled: true)
        #expect(picked.map(\.id) == [0, 2, 4, 6, 7, 8])
        // Модель выключена — запросы к ней не предлагаем.
        #expect(WritingHelpRules.commands(from: list, modelEnabled: false).map(\.id) == [2, 4])
    }

    @Test("Предлагаем к тексту, а не к щелчку и не ко всему документу")
    func какоеВыделение() {
        #expect(!WritingHelpRules.offers(""))
        #expect(!WritingHelpRules.offers("  a  "))
        #expect(!WritingHelpRules.offers("42"))
        #expect(WritingHelpRules.offers("ок"))
        #expect(WritingHelpRules.offers("Привет, как дела?"))
        #expect(!WritingHelpRules.offers(String(repeating: "слово ", count: 5_000)))
    }

    @Test("Кнопки плашки — снимок названий и значков команд")
    func кнопки() {
        let offer = WritingHelpRules.offer(text: "текст", commands: [command(3, .saveToNotes, payload: "")])
        #expect(offer.buttons == [.init(id: 3, title: "К3", symbol: QuickCommand.Kind.saveToNotes.defaultSymbol)])
    }

    @Test("Заготовки — те же шесть команд, что выходят на плашку")
    func заготовки() {
        let defaults = QuickCommands.defaults0
        #expect(defaults.count == 6)
        #expect(defaults.map(\.kind) == [.ollama, .ollama, .ollama, .ollama, .ollama, .saveToNotes])
        #expect(WritingHelpRules.commands(from: defaults, modelEnabled: true).map(\.id) == defaults.map(\.id))
        #expect(Set(defaults.map(\.id)).count == 6)
        #expect(defaults[1].payload.contains("{{language}}"))
    }

    @Test("{{language}} — язык системы, {{selection}} — текст")
    func подстановкаЯзыка() {
        let command = command(1, .ollama, payload: "Переведи на «{{language}}»:\n{{selection}}")
        #expect(command.prompt(with: "hello", language: "русский") == "Переведи на «русский»:\nhello")
        #expect(!QuickCommand.systemLanguage.isEmpty)
    }

    @Test("Плашка в два ряда: кнопки помещаются, длинный текст бежит строкой")
    func размерыПлашки() {
        let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)
        let six = (0..<6).map { command($0, .ollama) }
        let short = WritingHelpRules.offer(text: "ок", commands: six)
        let shortLayout = WritingHelpButtons.layout(for: short, text: "ок", metrics: metrics)
        #expect(shortLayout.panelWidth >= WritingHelpButtons.rowWidth(for: short) + 2 * ActivityLayout.leadingPadding)
        let long = String(repeating: "очень длинный выделенный текст ", count: 20)
        let longLayout = WritingHelpButtons.layout(for: short, text: long, metrics: metrics)
        #expect(longLayout.panelWidth == ActivityLayout.maxWidth)
        #expect(longLayout.textWidth > 200)
        // Через общий расчёт выреза — та же ширина и высота на ряд больше.
        var inputs = NotchInputs()
        inputs.activity = Activity(kind: .writingHelp(short))
        let size = inputs.resolve().size(metrics: metrics)
        #expect(size.height == metrics.activity(width: 0).height + WritingHelpButtons.extraHeight)
    }

    @Test("Выделение спрашиваем после протяжки, двойного щелчка, ⇧ со стрелкой и ⌘A — не после простого щелчка и заглавной буквы")
    func когдаСпрашивать() {
        #expect(!SelectionWatcher.mouseSelects(clickCount: 1, shift: false, dragged: 1))
        #expect(SelectionWatcher.mouseSelects(clickCount: 1, shift: false, dragged: 30))
        #expect(SelectionWatcher.mouseSelects(clickCount: 2, shift: false, dragged: 0))
        #expect(SelectionWatcher.mouseSelects(clickCount: 1, shift: true, dragged: 0))
        // ⇧ + буква «A» (код 0) — заглавная, не выделение; ⌘A — выделить всё.
        #expect(!SelectionWatcher.keySelects(keyCode: 0, shift: true, command: false))
        #expect(SelectionWatcher.keySelects(keyCode: 0, shift: false, command: true))
        #expect(SelectionWatcher.keySelects(keyCode: 124, shift: true, command: false))
        #expect(!SelectionWatcher.keySelects(keyCode: 124, shift: false, command: false))
    }
}
