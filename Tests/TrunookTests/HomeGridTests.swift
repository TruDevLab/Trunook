import Foundation
import SwiftUI
import Testing
@testable import Trunook

@Suite("Главный экран из плиток")
struct HomeGridTests {
    private func widget(_ id: Int, _ kind: HomeWidgetKind, _ size: HomeWidgetSize) -> HomeWidget {
        HomeWidget(id: id, kind: kind, size: size)
    }

    private func spot(_ grid: HomeGrid, _ id: Int) -> [Int]? {
        grid.placements.first { $0.widget.id == id }.map { [$0.column, $0.row] }
    }

    // MARK: - Укладка

    @Test("Плитка на всю ширину занимает свой ряд")
    func полнаяШирина() {
        let grid = HomeGrid.place([
            widget(0, .music, .full),
            widget(1, .timer, .small),
        ])
        #expect(spot(grid, 0) == [0, 0])
        #expect(spot(grid, 1) == [0, 1])
        #expect(grid.rows == 2)
    }

    /// Четыре маленькие рядом с 2×2 закрывают два ряда без единой дыры.
    @Test("2×2 и четыре 1×1 — два ряда без дыр")
    func большаяИМаленькие() {
        let grid = HomeGrid.place([
            widget(0, .month, .large),
            widget(1, .timer, .small),
            widget(2, .weather, .small),
            widget(3, .battery, .small),
            widget(4, .voice, .small),
        ])
        #expect(grid.rows == 2)
        #expect(grid.overflow.isEmpty)
        #expect(spot(grid, 1) == [2, 0])
        #expect(spot(grid, 2) == [3, 0])
        #expect(spot(grid, 3) == [2, 1])
        #expect(spot(grid, 4) == [3, 1])
    }

    /// Плотная укладка: плитка, стоящая в списке после широкой строки,
    /// всё равно заходит в дыру справа от 2×2.
    @Test("Дыра рядом с 2×2 заполняется следующей плиткой, которая в неё входит")
    func плотнаяУкладка() {
        let grid = HomeGrid.place([
            widget(0, .month, .large),
            widget(1, .music, .full),
            widget(2, .timer, .wide),
        ])
        #expect(spot(grid, 0) == [0, 0])
        #expect(spot(grid, 1) == [0, 2])
        #expect(spot(grid, 2) == [2, 0])
        #expect(grid.rows == 3)
    }

    @Test("Что не влезло в четыре ряда — в переполнение, порядок сохранён")
    func переполнение() {
        let widgets = (0..<6).map { widget($0, .music, .full) }
        let grid = HomeGrid.place(widgets)
        #expect(grid.placements.map(\.widget.id) == [0, 1, 2, 3])
        #expect(grid.overflow.map(\.id) == [4, 5])
        #expect(grid.rows == HomeGrid.maxRows)
    }

    @Test("Пустая раскладка — ноль рядов и нулевая высота")
    func пусто() {
        let grid = HomeGrid.place([])
        #expect(grid.rows == 0)
        #expect(HomeGrid.contentHeight(rows: 0) == 0)
    }

    // MARK: - Размеры

    @Test("Размер по умолчанию есть среди допустимых у каждого вида")
    func размерПоУмолчанию() {
        for kind in HomeWidgetKind.allCases {
            #expect(kind.allowedSizes.contains(kind.defaultSize), "\(kind.rawValue)")
            #expect(!kind.title.isEmpty && !kind.symbol.isEmpty, "\(kind.rawValue)")
        }
    }

    @Test("Недопустимый размер при создании заменяется размером по умолчанию")
    func недопустимыйРазмер() {
        #expect(HomeWidget(id: 0, kind: .battery, size: .fullTall).size == .small)
    }

    @Test("Вопрос к ИИ встаёт и в клетку, но добавляется полосой")
    func вопросВКлетку() {
        #expect(HomeWidgetKind.ask.allowedSizes.contains(.small))
        // Ярлык 1×1 — выбор человека, а не то, что достаётся по умолчанию:
        // ради строки набора плитку и берут.
        #expect(HomeWidgetKind.ask.defaultSize == .full)
        #expect(HomeWidget(id: 0, kind: .ask, size: .small).size == .small)
    }

    @Test("Сетка ровно заполняет ширину содержимого")
    func ширина() {
        let full = HomeGrid.size(of: .full)
        #expect(abs(full.width - HomeGrid.contentWidth) < 0.5)
        let two = HomeGrid.size(of: .large)
        #expect(two.height == HomeGrid.contentHeight(rows: 2))
    }

    /// Окно режет молча: самый высокий главный экран обязан в него влезать.
    @Test("Окно вмещает главный экран в четыре ряда")
    func потолокОкна() {
        let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)
        let tallest = metrics.expanded(rows: HomeGrid.maxRows)
        #expect(tallest.height <= metrics.windowSize.height)
        #expect(tallest.width <= metrics.windowSize.width)
        #expect(metrics.expanded(rows: 2).height
                == metrics.expanded(rows: 1).height + HomeGrid.rowHeight + HomeGrid.spacing)
    }

    /// Высота главного экрана задаётся раскладкой, а не встречами: вторая
    /// встреча ложится в ту же плитку, и панель от неё не растёт.
    @Test("Встречи не меняют высоту главного экрана")
    func встречиНеРастятПанель() {
        let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)
        let noon = Date(timeIntervalSince1970: 1_700_000_000)
        func item(_ title: String, _ offset: TimeInterval) -> CalendarItem {
            CalendarItem(id: title, title: title, start: noon.addingTimeInterval(offset), end: nil,
                         isAllDay: false, source: .event, link: nil, colorComponents: [1, 1, 1])
        }
        let one = NotchContent(events: [item("созвон", 0)], homeRows: 3)
        let three = NotchContent(events: [item("созвон", 0), item("ретро", 0), item("обед", 3600)], homeRows: 3)
        #expect(NotchSizing.size(presentation: .expanded, content: one, metrics: metrics)
                == NotchSizing.size(presentation: .expanded, content: three, metrics: metrics))
    }

    /// Три колонки и одна рядом закрывают ряд целиком.
    @Test("3×1 и 1×1 делят один ряд")
    func триИОдна() {
        let grid = HomeGrid.place([
            widget(0, .news, .threeWide),
            widget(1, .battery, .small),
            widget(2, .timer, .threeWide),
        ])
        #expect(spot(grid, 0) == [0, 0])
        #expect(spot(grid, 1) == [3, 0])
        #expect(spot(grid, 2) == [0, 1])
        #expect(HomeGrid.size(of: .threeWide).width
                == 3 * HomeGrid.cellWidth + 2 * HomeGrid.spacing)
    }

    /// Плитка встреч в два ряда обязана вмещать весь запас встреч,
    /// который ей передаёт вырез.
    @Test("В плитку встреч высотой в два ряда входят все три встречи")
    func триВстречиВВысокойПлитке() {
        let inner = HomeTile<EmptyView>.inner(.fullTall).height
        let needed = CGFloat(NotchMetrics.maxVisibleEvents) * ScheduleWidget.rowHeight
            + CGFloat(NotchMetrics.maxVisibleEvents - 1) * NotchStyle.rowSpacing
        #expect(needed <= inner)
    }

    @Test("Проверочные страницы показывают каждый вид в каждом размере и не переполняются")
    func проверочныеСтраницы() {
        let pages = HomeWidgets.showcasePages()
        let all = pages.flatMap { $0 }
        let expected = HomeWidgetKind.allCases.reduce(0) { $0 + $1.allowedSizes.count }
        #expect(all.count == expected)
        for page in pages {
            #expect(HomeGrid.place(page).overflow.isEmpty)
        }
    }

    // MARK: - Хранение

    private func freshSettings() -> Trunook.Settings {
        Trunook.Settings(defaults: UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!)
    }

    @Test("Без сохранённой раскладки — стандартная")
    func стандартная() {
        let settings = freshSettings()
        #expect(settings.homeWidgets == HomeWidgets.standard)
        #expect(settings.homeWidgets.map(\.kind) == [.music, .schedule, .month, .weather])
    }

    /// Музыка 3×1 с погодой в первом ряду, встречи и месяц по 2×2 под ними —
    /// три ряда без единой дыры.
    @Test("Стандартная раскладка ложится в три ряда без дыр")
    func стандартнаяУкладка() {
        let grid = HomeGrid.place(HomeWidgets.standard)
        #expect(grid.rows == 3)
        #expect(grid.overflow.isEmpty)
        #expect(spot(grid, 0) == [0, 0])
        #expect(spot(grid, 3) == [3, 0])
        #expect(spot(grid, 1) == [0, 1])
        #expect(spot(grid, 2) == [2, 1])
    }

    @Test("Раскладка переживает запись и чтение")
    func записьИЧтение() {
        let settings = freshSettings()
        settings.homeWidgets = [widget(3, .timer, .wide), widget(7, .month, .large)]
        #expect(settings.homeWidgets == [widget(3, .timer, .wide), widget(7, .month, .large)])
    }

    /// Разобранная раскладка запоминается, но не переживает свои байты:
    /// запись мимо `Settings` — `defaults write` при отладке — видна сразу.
    @Test("Запомненная раскладка сменяется записью и через настройки, и мимо них")
    func кэшРаскладки() {
        let defaults = UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!
        let settings = Trunook.Settings(defaults: defaults)
        settings.homeWidgets = [widget(1, .timer, .small)]
        #expect(settings.homeWidgets == [widget(1, .timer, .small)])
        #expect(settings.homeWidgets == [widget(1, .timer, .small)])

        settings.homeWidgets = [widget(2, .month, .large)]
        #expect(settings.homeWidgets == [widget(2, .month, .large)])

        HomeWidgets.save([widget(3, .music, .full)], to: defaults)
        #expect(settings.homeWidgets == [widget(3, .music, .full)])

        defaults.removeObject(forKey: HomeWidgets.key)
        #expect(settings.homeWidgets == HomeWidgets.standard)
    }

    /// Раскладку, сохранённую более новой версией, старая не теряет целиком.
    @Test("Незнакомый вид пропускается, незнакомый размер заменяется")
    func незнакомыйВид() {
        let defaults = UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!
        let json = """
        [{"id":0,"kind":"music","size":"full"},
         {"id":1,"kind":"hologram","size":"small"},
         {"id":2,"kind":"timer","size":"huge"}]
        """
        defaults.set(Data(json.utf8), forKey: HomeWidgets.key)
        let loaded = HomeWidgets.load(from: defaults)
        #expect(loaded == [widget(0, .music, .full), widget(2, .timer, .small)])
    }

    @Test("Добавить, переставить, сменить размер, убрать, вернуть как было")
    func правка() {
        let settings = freshSettings()
        let timer = settings.addHomeWidget(.timer)
        #expect(settings.homeWidgets.last == widget(timer, .timer, .small))

        settings.moveHomeWidget(id: timer, onto: settings.homeWidgets[0].id)
        #expect(settings.homeWidgets.first?.kind == .timer)

        settings.setHomeWidgetSize(id: timer, .wide)
        #expect(settings.homeWidgets.first?.size == .wide)
        // Размера, под который нет вёрстки, не ставится.
        settings.setHomeWidgetSize(id: timer, .fullTall)
        #expect(settings.homeWidgets.first?.size == .wide)

        settings.removeHomeWidget(id: timer)
        #expect(!settings.homeWidgets.contains { $0.kind == .timer })

        settings.resetHomeWidgets()
        #expect(settings.homeWidgets == HomeWidgets.standard)
    }
}
