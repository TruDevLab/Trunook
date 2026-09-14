import CoreGraphics
import Foundation
import Testing
@testable import Trunook

@Suite("Остров на нескольких экранах")
struct NotchScreensTests {
    /// Встроенный экран с вырезом и внешний монитор справа от него.
    private let laptop = ScreenSlot(
        id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), hasNotch: true,
        trigger: CGRect(x: 660, y: 950, width: 193, height: 32)
    )
    private let monitor = ScreenSlot(
        id: 2, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440), hasNotch: false,
        trigger: CGRect(x: 2688, y: 1410, width: 208, height: 30)
    )
    private var screens: [ScreenSlot] { [monitor, laptop] }

    private func host(
        _ mode: NotchScreenMode,
        cursor: CGPoint,
        current: CGDirectDisplayID? = nil,
        busy: Bool = false
    ) -> CGDirectDisplayID? {
        NotchScreenChoice.host(mode: mode, screens: screens, cursor: cursor, current: current, isBusy: busy)
    }

    @Test("По умолчанию остров на экране с вырезом, где бы ни был курсор")
    func поУмолчаниюНаВырезе() throws {
        #expect(host(.notched, cursor: CGPoint(x: 2000, y: 700)) == 1)
        let defaults = try #require(UserDefaults(suiteName: "NotchScreensTests"))
        defaults.removePersistentDomain(forName: "NotchScreensTests")
        #expect(Settings(defaults: defaults).notchScreenMode == .notched)
    }

    @Test("Без чёлки главный — основной монитор из системных настроек")
    func безВыреза() {
        let lid = ScreenSlot(id: 3, frame: laptop.frame, hasNotch: false, trigger: laptop.trigger)
        #expect(NotchScreenChoice.home([monitor, lid]) == 2)
        #expect(NotchScreenChoice.home([lid, monitor]) == 3)
        #expect(NotchScreenChoice.home(screens) == 1)
    }

    @Test("Остров переезжает на экран курсора")
    func заКурсором() {
        #expect(host(.cursor, cursor: CGPoint(x: 2000, y: 700), current: 1) == 2)
        #expect(host(.cursor, cursor: CGPoint(x: 100, y: 500), current: 2) == 1)
    }

    /// Все экраны: события живут дома. Курсор на мониторе остров не уводит —
    /// только рука у полоски.
    @Test("На всех экранах остров дома, пока руку не подвели к полоске")
    func всеЭкраны() {
        #expect(host(.all, cursor: CGPoint(x: 2000, y: 700), current: 1) == 1)
        #expect(host(.all, cursor: CGPoint(x: 2790, y: 1430), current: 1) == 2)
        #expect(host(.all, cursor: CGPoint(x: 2000, y: 700), current: 2, busy: true) == 2)
        #expect(host(.all, cursor: CGPoint(x: 2000, y: 700), current: 2) == 1)
    }

    /// Курсор, упёртый в верхнюю кромку, стоит ровно на `maxY` — там, где
    /// `CGRect.contains` уже отвечает «нет». А у кромки и живёт чёлка.
    @Test("Курсор у самой верхней кромки принадлежит экрану")
    func уКромки() {
        #expect(host(.cursor, cursor: CGPoint(x: 2792, y: 1440), current: 1) == 2)
    }

    @Test("Пока с островом работают, он не уезжает")
    func занятыйНеУезжает() {
        #expect(host(.cursor, cursor: CGPoint(x: 2000, y: 700), current: 1, busy: true) == 1)
    }

    @Test("Экран занятого острова отключили — остров у курсора")
    func экранОтключили() {
        #expect(host(.cursor, cursor: CGPoint(x: 2000, y: 700), current: 9, busy: true) == 2)
    }

    @Test("Окна на всех экранах, кроме режима «С вырезом»")
    func окна() {
        #expect(NotchScreenChoice.windows(mode: .notched, screens: screens) == [1])
        #expect(NotchScreenChoice.windows(mode: .cursor, screens: screens) == [2, 1])
        #expect(NotchScreenChoice.windows(mode: .all, screens: screens) == [2, 1])
    }

    @Test("Отражение на главном показывает полоски, но не то, что заведено рукой")
    func отражениеНаГлавном() {
        var inputs = NotchInputs()
        inputs.overlay = .clipboard
        inputs.isHovered = true
        inputs.isPinnedOpen = true
        inputs.isQuickRingOpen = true
        #expect(inputs.passive().resolve().presentation == .collapsed)

        inputs.timerChip = TimerChip(symbol: "timer", showsHours: false)
        #expect(inputs.passive().resolve().presentation == .chip)
    }

    @Test("Без чёлки в покое пусто, у отражения — полоска, у чёлки — силуэт")
    func безВырезаПусто() {
        let hardware = NotchMetrics(notchWidth: 185, notchHeight: 32)
        let synthetic = NotchMetrics(notchWidth: 200, notchHeight: 25, hasNotch: false)
        let handle = NotchMetrics(notchWidth: 200, notchHeight: 25, hasNotch: false, showsHandle: true)
        let mirrorOnNotch = NotchMetrics(notchWidth: 185, notchHeight: 32, showsHandle: true)
        let collapsed = NotchSnapshot(presentation: .collapsed, content: NotchContent())
        #expect(collapsed.size(metrics: hardware) == hardware.closed)
        #expect(collapsed.size(metrics: synthetic).height == 0)
        #expect(collapsed.size(metrics: handle).height == NotchMetrics.handleHeight)
        #expect(collapsed.size(metrics: mirrorOnNotch) == mirrorOnNotch.closed)
    }
}
