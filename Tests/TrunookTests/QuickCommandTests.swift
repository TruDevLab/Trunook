import Foundation
import Testing
@testable import Trunook

/// Набор команд: их произвольное число, порядок и модель у каждой.
///
/// Проверяется в первую очередь то, что сломалось бы молча. Команд было
/// шесть, и число было зашито в чтение: набор приводился к шести слотам
/// на каждой загрузке. Уберёшь приведение неаккуратно — и седьмая команда
/// исчезает при перезапуске, ничего об этом не сказав.
@Suite("Команды")
struct QuickCommandTests {
    /// Свой домен настроек: настоящий трогать нельзя — в нём лежит набор
    /// человека, и тест переписал бы его своими выдумками.
    ///
    /// Разовые переносы по умолчанию помечены состоявшимися: иначе каждый
    /// свежий домен получал бы дописанную команду «в заметки», и проверки
    /// про порядок и число считали бы её своей.
    private func defaults(
        _ name: String = #function,
        migrated: Bool = true
    ) -> UserDefaults {
        let suite = "com.trunook.tests.commands.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        let store = UserDefaults(suiteName: suite)!
        store.set(migrated, forKey: QuickCommands.noteCommandKey)
        return store
    }

    private func command(
        id: Int,
        title: String = "Команда",
        kind: QuickCommand.Kind = .ollama,
        payload: String = "промт",
        model: String? = nil
    ) -> QuickCommand {
        QuickCommand(
            id: id,
            title: title,
            kind: kind,
            payload: payload,
            symbol: "",
            isEnabled: true,
            hotKey: nil,
            model: model
        )
    }

    // MARK: - Число и порядок

    @Test("Команд может быть сколько угодно — семь переживают запись и чтение")
    func числоНеОграничено() {
        let store = defaults()
        let many = (0..<7).map { command(id: $0, title: "Команда \($0)") }
        QuickCommands.save(many, to: store)

        let loaded = QuickCommands.load(from: store)
        #expect(loaded.count == 7)
        #expect(loaded.map(\.id) == Array(0..<7))
    }

    @Test("Порядок — это порядок в наборе, а не номера команд")
    func порядокПоНабору() {
        let store = defaults()
        // Номера нарочно вразнобой: порядок задаёт место в наборе, и после
        // перестановки номера идти по возрастанию не обязаны.
        QuickCommands.save([command(id: 5), command(id: 0), command(id: 3)], to: store)

        #expect(QuickCommands.load(from: store).map(\.id) == [5, 0, 3])
    }

    @Test("Номер новой команды не повторяет уже занятый")
    func номерНеПовторяется() {
        // Не длина набора: удалили среднюю — и новая получила бы номер
        // существующей, а по номеру команду находят настройки и клавиша.
        #expect(QuickCommands.nextID(after: [command(id: 0), command(id: 7)]) == 8)
        #expect(QuickCommands.nextID(after: []) == 0)
    }

    // MARK: - Наследство прежних версий

    @Test("Набор старого формата читается, а пустые слоты отбрасываются")
    func пустыеСлотыУходят() {
        let store = defaults()
        // Так набор выглядел до 0.11.0: шесть слотов, часть — пустые места
        // под команду. Показывать их в списке незачем, а вот потерять
        // настроенные при этом нельзя.
        let legacy = [
            command(id: 0, title: "Исправить"),
            command(id: 1, title: "Перевести"),
            QuickCommand(
                id: 2, title: "", kind: .ollama, payload: "",
                symbol: "", isEnabled: false, hotKey: nil
            ),
            QuickCommand(
                id: 3, title: "", kind: .ollama, payload: "",
                symbol: "", isEnabled: false, hotKey: nil
            ),
        ]
        QuickCommands.save(legacy, to: store)

        let loaded = QuickCommands.load(from: store)
        #expect(loaded.count == 2)
        #expect(loaded.map(\.title) == ["Исправить", "Перевести"])
    }

    @Test("«Сохранить в заметки» доезжает до тех, у кого набор уже был")
    func заметочнаяКомандаДописывается() {
        let store = defaults(migrated: false)
        QuickCommands.save([command(id: 0, title: "Исправить")], to: store)

        // Заготовки первого запуска до таких людей не доходят, а руками эту
        // команду не собрать: вида `saveToNotes` в старом списке действий
        // не было вовсе.
        let first = QuickCommands.load(from: store)
        #expect(first.count == 2)
        #expect(first.last?.kind == .saveToNotes)

        // Удалённую нарочно возвращать нельзя: выдача однократная.
        QuickCommands.save([command(id: 0, title: "Исправить")], to: store)
        #expect(QuickCommands.load(from: store).count == 1)
    }

    @Test("Команда, сохранённая без поля модели, читается целиком")
    func староеПолеЧитается() throws {
        // Поле необязательное нарочно: у синтезированного `Decodable`
        // значения по умолчанию не работают, и обязательное `model` уронило
        // бы разбор **всего** набора, сохранённого прошлой версией.
        let json = """
        [{"id":0,"title":"Перевести","kind":"ollama","payload":"переведи",
          "symbol":"","isEnabled":true,"passesSelection":false}]
        """
        let store = defaults()
        store.set(Data(json.utf8), forKey: "quickCommands")

        let loaded = QuickCommands.load(from: store)
        let first = try #require(loaded.first)
        #expect(loaded.count == 1)
        #expect(first.model == nil)
    }

    // MARK: - Что попадает в список

    @Test("В списке только настроенные, и только при включённых командах")
    func видимыеОтбираются() {
        let all = [
            command(id: 0),
            QuickCommand(
                id: 1, title: "Без промта", kind: .ollama, payload: "",
                symbol: "", isEnabled: true, hotKey: nil
            ),
            QuickCommand(
                id: 2, title: "Выключена", kind: .ollama, payload: "промт",
                symbol: "", isEnabled: false, hotKey: nil
            ),
        ]
        #expect(QuickCommands.visible(in: all, enabled: true, modelEnabled: true).map(\.id) == [0])
        #expect(QuickCommands.visible(in: all, enabled: false, modelEnabled: true).isEmpty)
    }

    @Test("С выключенной моделью в списке остаются команды без неё")
    func безМоделиОстальныеРаботают() {
        // Раньше с выключенной Ollama сочетание уводило захваченное прямиком
        // в заметки: список не показывался вовсе, хотя половина команд модели
        // не требует. Показывать запросы к модели тоже нельзя — они заведомо
        // ответят отказом.
        let all = [
            command(id: 0, title: "К модели"),
            QuickCommand(
                id: 1, title: "Открыть папку", kind: .openPath, payload: "~/Desktop",
                symbol: "", isEnabled: true, hotKey: nil
            ),
            QuickCommand(
                id: 2, title: "В заметки", kind: .saveToNotes, payload: "",
                symbol: "", isEnabled: true, hotKey: nil
            ),
        ]
        let withoutModel = QuickCommands.visible(in: all, enabled: true, modelEnabled: false)
        #expect(withoutModel.map(\.id) == [1, 2])
        #expect(QuickCommands.visible(in: all, enabled: true, modelEnabled: true).count == 3)
    }

    @Test("Заметке промт не нужен — она настроена и с пустым содержимым")
    func заметкеПромтНеНужен() {
        // Она работает с захваченным текстом, а не со своим промтом. Требуй
        // от неё непустой `payload` — и она навсегда осталась бы
        // ненастроенной, то есть невидимой в списке.
        let note = QuickCommand(
            id: 0, title: "Сохранить в заметки", kind: .saveToNotes, payload: "",
            symbol: "", isEnabled: true, hotKey: nil
        )
        #expect(note.isConfigured)
        #expect(!QuickCommand.Kind.saveToNotes.needsPayload)
        #expect(!QuickCommand.Kind.saveToNotes.usesModel)
        #expect(QuickCommand.Kind.ollama.usesModel)
    }

    // MARK: - Промт

    @Test("Без места подстановки текст дописывается снизу")
    func текстДописывается() {
        let withMarker = command(id: 0, payload: "Исправь:\n\n{{selection}}")
        #expect(withMarker.prompt(with: "фраза") == "Исправь:\n\nфраза")

        // Команда, заданная одной фразой, иначе молча теряла бы то,
        // к чему её применяют.
        let plain = command(id: 1, payload: "переведи на английский")
        #expect(plain.prompt(with: "фраза") == "переведи на английский\n\nфраза")
        #expect(plain.prompt(with: "") == "переведи на английский")
    }

    // MARK: - Размер списка

    @Test("Список не растёт выше своего потолка")
    func списокПрокручивается() {
        // Список, который может пополниться, обязан прокручиваться: иначе он
        // однажды перерастает окно, а содержимое, переросшее окно, обрезается
        // с обеих сторон — и видно это только на снимке.
        let full = CommandRows.height(rows: QuickCommands.visibleRows)
        #expect(CommandRows.height(rows: 50) == full)
        #expect(CommandRows.height(rows: 2) < full)
        // Пустой список — тоже строка: «команд пока нет».
        #expect(CommandRows.height(rows: 0) == CommandRows.rowHeight)
    }
}
