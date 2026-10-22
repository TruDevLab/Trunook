import Testing
import CoreGraphics
@testable import Trunook

@Suite("Переключатель окон")
struct WindowSwitcherTests {
    private func key(_ code: Int64, _ flags: CGEventFlags, open: Bool = false,
                     trigger: SwitcherTrigger = .command) -> SwitcherKey {
        SwitcherKey.keyDown(code, flags: flags, isOpen: open, trigger: trigger)
    }

    @Test("⌘Tab открывает, ⇧⌘Tab открывает шагом назад")
    func открытие() {
        #expect(key(SwitcherKey.tab, .maskCommand) == .open(step: 1))
        #expect(key(SwitcherKey.tab, [.maskCommand, .maskShift]) == .open(step: -1))
        // Без модификатора Tab — обычная клавиша.
        #expect(key(SwitcherKey.tab, []) == .pass)
        // Чужие сочетания: ⌃Tab листает вкладки браузера, ⌘⌥Tab — чьё-то своё.
        #expect(key(SwitcherKey.tab, .maskControl) == .pass)
        #expect(key(SwitcherKey.tab, [.maskCommand, .maskAlternate]) == .pass)
        #expect(key(SwitcherKey.tab, [.maskCommand, .maskControl]) == .pass)
        // Закрытый переключатель остальные клавиши не трогает.
        #expect(key(SwitcherKey.escape, .maskCommand) == .pass)
        #expect(key(SwitcherKey.left, .maskCommand) == .pass)
    }

    @Test("Сочетание ⌥Tab: системный ⌘Tab остаётся системе")
    func сочетаниеОпции() {
        #expect(key(SwitcherKey.tab, .maskAlternate, trigger: .option) == .open(step: 1))
        #expect(key(SwitcherKey.tab, .maskCommand, trigger: .option) == .pass)
        #expect(SwitcherKey.flagsChanged(.maskCommand, isOpen: true, trigger: .option) == .commit)
        #expect(SwitcherKey.flagsChanged(.maskAlternate, isOpen: true, trigger: .option) == .pass)
    }

    @Test("Открытый: Tab, стрелки, Esc, Enter; остальное проглатывается")
    func открытый() {
        let held: CGEventFlags = .maskCommand
        #expect(key(SwitcherKey.tab, held, open: true) == .step(1))
        #expect(key(SwitcherKey.tab, [.maskCommand, .maskShift], open: true) == .step(-1))
        #expect(key(SwitcherKey.right, held, open: true) == .step(1))
        #expect(key(SwitcherKey.left, held, open: true) == .step(-1))
        #expect(key(SwitcherKey.down, held, open: true) == .tabs(true))
        #expect(key(SwitcherKey.up, held, open: true) == .tabs(false))
        #expect(key(SwitcherKey.escape, held, open: true) == .cancel)
        #expect(key(SwitcherKey.enter, held, open: true) == .commit)
        #expect(key(SwitcherKey.keypadEnter, held, open: true) == .commit)
        // ⌘Q посреди переключения не должен закрыть переднее приложение.
        #expect(key(12, held, open: true) == .swallow)
        // ⌘⌥Tab, пока открыт, — тоже не наружу.
        #expect(key(SwitcherKey.tab, [.maskCommand, .maskAlternate], open: true) == .swallow)
    }

    @Test("Отпустили ⌘ — выбор; отпускание прошло мимо — клавиатура не глохнет")
    func отпускание() {
        #expect(SwitcherKey.flagsChanged([], isOpen: true, trigger: .command) == .commit)
        #expect(SwitcherKey.flagsChanged(.maskShift, isOpen: true, trigger: .command) == .commit)
        #expect(SwitcherKey.flagsChanged([.maskCommand, .maskShift], isOpen: true, trigger: .command) == .pass)
        #expect(SwitcherKey.flagsChanged([], isOpen: false, trigger: .command) == .pass)
        // Считаем открытым, а ⌘ уже не держат: нажатие уходит, куда шло.
        #expect(key(0, [], open: true) == .lost)
        #expect(key(SwitcherKey.tab, [], open: true) == .lost)
    }

    @Test("Начинаем со второй строки, если первая — текущее окно")
    func начало() {
        #expect(SwitcherOrder.start(count: 5, firstIsFrontmost: true) == 1)
        #expect(SwitcherOrder.start(count: 5, firstIsFrontmost: false) == 0)
        #expect(SwitcherOrder.start(count: 1, firstIsFrontmost: true) == 0)
        #expect(SwitcherOrder.start(count: 0, firstIsFrontmost: true) == 0)
    }

    @Test("Шаг по кругу")
    func шаг() {
        #expect(SwitcherOrder.move(4, by: 1, count: 5) == 0)
        #expect(SwitcherOrder.move(0, by: -1, count: 5) == 4)
        #expect(SwitcherOrder.move(2, by: 7, count: 5) == 4)
        #expect(SwitcherOrder.move(0, by: 1, count: 0) == 0)
    }

    @Test("Нажатия до готовности списка не теряются")
    func нажатияДоСписка() {
        // Одно ⌘Tab — предыдущее окно.
        #expect(SwitcherOrder.selection(firstStep: 1, steps: 1, count: 5, firstIsFrontmost: true) == 1)
        // Три Tab подряд, пока список собирался.
        #expect(SwitcherOrder.selection(firstStep: 1, steps: 3, count: 5, firstIsFrontmost: true) == 3)
        // Вперёд и назад — вернулись к текущему.
        #expect(SwitcherOrder.selection(firstStep: 1, steps: 0, count: 5, firstIsFrontmost: true) == 0)
        // ⇧⌘Tab — с конца.
        #expect(SwitcherOrder.selection(firstStep: -1, steps: -1, count: 5, firstIsFrontmost: true) == 4)
        // Переднее приложение без окон: первая строка — уже чужое окно.
        #expect(SwitcherOrder.selection(firstStep: 1, steps: 1, count: 5, firstIsFrontmost: false) == 0)
    }

    // MARK: - Вкладки

    private let us = String(BrowserTabs.field)
    private let rs = String(BrowserTabs.record)

    @Test("Ответ браузера: окна, выбранная вкладка, заголовки")
    func разбор() {
        let output = ["101", "Почта", "2", "Новости", "Почта"].joined(separator: us) + rs
            + ["202", "Карта", "1", "Карта"].joined(separator: us) + rs
            + "мусор" + rs
            + ["303", "", "1", ""].joined(separator: us) + rs
        let windows = BrowserTabs.parse(output)
        #expect(windows.count == 3)
        #expect(windows[0] == .init(id: "101", name: "Почта", active: 2, tabs: [
            BrowserTab(index: 1, title: "Новости"), BrowserTab(index: 2, title: "Почта"),
        ]))
        #expect(windows[1].tabs.map(\.title) == ["Карта"])
        // Вкладка без заголовка не пустеет на экране.
        #expect(windows[2].tabs.first?.title == "Без названия")
        #expect(BrowserTabs.parse("").isEmpty)
    }

    private func window(_ id: String, _ name: String, tabs: Int = 2) -> BrowserTabs.Window {
        .init(id: id, name: name, active: 1, tabs: (0..<tabs).map { BrowserTab(index: $0 + 1, title: "в\($0)") })
    }

    @Test("Окна сличаются по заголовку, потом по сходству, потом по порядку")
    func сличение() {
        let result = BrowserTabs.Result.windows([
            window("1", "Почта"), window("2", "Документ — черновик"), window("3", "Карта"),
        ])
        let ids = BrowserTabs.match(result, to: ["Карта", "Документ", "Что-то другое"]).map { tabs -> String? in
            if case let .loaded(id, _, _) = tabs { return id }
            return nil
        }
        // Третье не нашлось ни по имени, ни по сходству — оставшееся по порядку.
        #expect(ids == ["3", "2", "1"])
    }

    @Test("Окон в браузере меньше — лишним вкладок нет; окно без вкладок — тоже")
    func лишниеОкна() {
        let matched = BrowserTabs.match(.windows([window("7", "А", tabs: 0)]), to: ["А", "Б"])
        #expect(matched == [.unavailable, .unavailable])
    }

    @Test("Разрешение и отказ доходят до каждого окна")
    func разрешение() {
        #expect(BrowserTabs.match(.needsConsent, to: ["а", "б"]) == [.needsConsent, .needsConsent])
        #expect(BrowserTabs.match(.denied, to: ["а"]) == [.denied])
        #expect(BrowserTabs.match(.failed, to: ["а"]) == [.unavailable])
    }

    @Test("Вкладки умеют Safari и браузеры на Chromium")
    func браузеры() {
        #expect(BrowserTabs.family(of: "com.apple.Safari") == .safari)
        #expect(BrowserTabs.family(of: "com.google.Chrome") == .chromium)
        #expect(BrowserTabs.family(of: "ru.yandex.desktop.yandex-browser") == .chromium)
        #expect(BrowserTabs.family(of: "company.thebrowser.Browser") == .arc)
        #expect(BrowserTabs.family(of: "org.mozilla.firefox") == nil)
        #expect(BrowserTabs.family(of: "com.apple.finder") == nil)
    }

    @Test("Номер окна в текст скрипта попадает только чистым")
    func выборВкладки() {
        let chrome = BrowserTabs.selectSource(bundleID: "com.google.Chrome", family: .chromium, windowID: "42", tab: 3)
        #expect(chrome?.contains("set active tab index of window id 42 to 3") == true)
        let arc = BrowserTabs.selectSource(bundleID: "company.thebrowser.Browser", family: .arc,
                                           windowID: "A1B2-C3", tab: 2)
        #expect(arc?.contains("tell tab 2 of window id \"A1B2-C3\" to select") == true)
        // Кавычка, пробел, пустота, нечисловой номер у Safari — не пропускаем.
        #expect(BrowserTabs.selectSource(bundleID: "company.thebrowser.Browser", family: .arc,
                                         windowID: "x\" & quit", tab: 1) == nil)
        #expect(BrowserTabs.selectSource(bundleID: "com.apple.Safari", family: .safari, windowID: "", tab: 1) == nil)
        #expect(BrowserTabs.selectSource(bundleID: "com.apple.Safari", family: .safari, windowID: "AB", tab: 1) == nil)
        #expect(BrowserTabs.selectSource(bundleID: "com.apple.Safari", family: .safari, windowID: "5", tab: 0) == nil)
    }

    @Test("Миниатюра вписана в карточку с сохранением пропорций и не крупнее окна")
    func миниатюра() {
        let box = CGSize(width: 288, height: 180)
        #expect(WindowThumbnails.fit(CGSize(width: 1440, height: 900), in: box) == CGSize(width: 288, height: 180))
        #expect(WindowThumbnails.fit(CGSize(width: 1000, height: 1000), in: box) == CGSize(width: 180, height: 180))
        #expect(WindowThumbnails.fit(CGSize(width: 2000, height: 400), in: box) == CGSize(width: 288, height: 58))
        // Маленькое окно не растягиваем.
        #expect(WindowThumbnails.fit(CGSize(width: 120, height: 80), in: box) == CGSize(width: 120, height: 80))
        #expect(WindowThumbnails.fit(.zero, in: box) == .zero)
    }

    @Test("Накладка переключателя раскрывает вырез панелью")
    func накладка() {
        #expect(NotchInputs(overlay: .windowSwitcher).resolve().presentation == .windowSwitcher)
        #expect(!NotchState.Overlay.windowSwitcher.closesOnCursorExit)
    }
}
