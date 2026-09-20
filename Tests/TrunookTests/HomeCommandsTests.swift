import Foundation
import Testing
@testable import Trunook

@Suite("Плитка быстрых команд")
struct HomeCommandsTests {
    private func freshSettings() -> Trunook.Settings {
        Trunook.Settings(defaults: UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!)
    }

    private func command(
        id: Int,
        title: String = "Команда",
        payload: String = "промт",
        isEnabled: Bool = true
    ) -> QuickCommand {
        QuickCommand(
            id: id,
            title: title,
            kind: .ollama,
            payload: payload,
            symbol: "",
            isEnabled: isEnabled,
            hotKey: nil
        )
    }

    // MARK: - Сколько команд встаёт

    /// Ровно то, о чём просили: 1×1 — одна команда, 2×2 — четыре.
    @Test("Клеток столько же, сколько клеток сетки, но не больше четырёх")
    func клетки() {
        #expect(HomeWidgetSize.small.commandSlots == 1)
        #expect(HomeWidgetSize.wide.commandSlots == 2)
        #expect(HomeWidgetSize.threeWide.commandSlots == 3)
        #expect(HomeWidgetSize.full.commandSlots == 4)
        #expect(HomeWidgetSize.large.commandSlots == 4)
        // Восемь клеток, а потолок всё равно четыре: плитка — горсть ярлыков,
        // а не второй список команд.
        #expect(HomeWidgetSize.fullTall.commandSlots == 4)
    }

    @Test("Лишние команды отрезаются по размеру плитки")
    func лишние() {
        let small = HomeWidget(id: 0, kind: .commands, size: .small, commands: [3, 4, 5])
        #expect(small.commands == [3])
        let large = HomeWidget(id: 1, kind: .commands, size: .large, commands: [3, 4, 5, 6, 7])
        #expect(large.commands == [3, 4, 5, 6])
    }

    @Test("Плитка уменьшилась — лишние команды ушли с ней")
    func уменьшение() {
        let settings = freshSettings()
        let id = settings.addHomeWidget(.commands)
        settings.setHomeWidgetCommands(id: id, [0, 1, 2, 3])
        #expect(settings.homeWidgets.last?.commands == [0, 1, 2, 3])

        settings.setHomeWidgetSize(id: id, .small)
        #expect(settings.homeWidgets.last?.commands == [0])
    }

    @Test("Размер по умолчанию — 2×2, четыре команды")
    func размерПоУмолчанию() {
        #expect(HomeWidgetKind.commands.defaultSize == .large)
        let settings = freshSettings()
        let id = settings.addHomeWidget(.commands)
        #expect(settings.homeWidgets.last?.size == .large)
        #expect(settings.homeWidgets.last?.id == id)
    }

    // MARK: - Хранение

    @Test("Выбор команд переживает запись и чтение")
    func записьИЧтение() {
        let settings = freshSettings()
        let id = settings.addHomeWidget(.commands)
        settings.setHomeWidgetCommands(id: id, [2, 0])
        #expect(settings.homeWidgets.last?.commands == [2, 0])
    }

    /// Раскладка, сохранённая до того, как плитка команд появилась, читается
    /// целиком — иначе обновление приложения обнулило бы главный экран.
    @Test("Плитка без ключа команд читается с пустым списком")
    func прежнийФормат() {
        let defaults = UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!
        let json = """
        [{"id":0,"kind":"music","size":"full"},
         {"id":1,"kind":"commands","size":"large"}]
        """
        defaults.set(Data(json.utf8), forKey: HomeWidgets.key)
        let loaded = HomeWidgets.load(from: defaults)
        #expect(loaded?.count == 2)
        #expect(loaded?.last?.commands == [])
    }

    @Test("Вторая плитка команд разрешена, вторая плитка музыки — нет")
    func дубли() {
        #expect(HomeWidgetKind.commands.allowsDuplicates)
        #expect(!HomeWidgetKind.music.allowsDuplicates)
        #expect(!HomeWidgetKind.timeline.allowsDuplicates)
    }

    // MARK: - Что рисуется

    @Test("На плитке стоят выбранные команды в своём порядке")
    func порядок() {
        let widget = HomeWidget(id: 0, kind: .commands, size: .large, commands: [2, 0])
        let chosen = HomeCommandSlots.chosen(widget, in: [
            command(id: 0, title: "Перевести"),
            command(id: 1, title: "Пересказать"),
            command(id: 2, title: "Исправить"),
        ])
        #expect(chosen.map(\.title) == ["Исправить", "Перевести"])
    }

    /// Выключенная, ненастроенная и удалённая не рисуются: нажатие по ним
    /// кончилось бы отказом, а место они занимали бы наравне с рабочими.
    @Test("Выключенная, пустая и пропавшая команда на плитку не попадают")
    func негодные() {
        let widget = HomeWidget(id: 0, kind: .commands, size: .large, commands: [0, 1, 2, 9])
        let chosen = HomeCommandSlots.chosen(widget, in: [
            command(id: 0, title: "Рабочая"),
            command(id: 1, title: "Выключенная", isEnabled: false),
            command(id: 2, title: "Без промта", payload: ""),
        ])
        #expect(chosen.map(\.title) == ["Рабочая"])
    }

    @Test("Свободные клетки считаются от размера")
    func свободные() {
        #expect(HomeCommandSlots.free(HomeWidget(id: 0, kind: .commands, size: .large)) == 4)
        #expect(HomeCommandSlots.free(
            HomeWidget(id: 0, kind: .commands, size: .large, commands: [1, 2])
        ) == 2)
        #expect(HomeCommandSlots.free(
            HomeWidget(id: 0, kind: .commands, size: .small, commands: [1])
        ) == 0)
    }

    @Test("Плитка живёт тем же выключателем, что и список команд")
    func выключатель() {
        let settings = freshSettings()
        #expect(HomeWidgetKind.commands.isEnabled(settings))
        settings.quickCommandsEnabled = false
        #expect(!HomeWidgetKind.commands.isEnabled(settings))
    }
}
