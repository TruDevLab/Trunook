import Testing
import CoreGraphics
@testable import Trunook

@Suite("Раскладка окон на другом экране")
struct WindowSnapScreensTests {
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let left = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
    private let right = CGRect(x: 1512, y: 0, width: 2560, height: 1440)

    @Test("Плашки: этот экран и остальные со стрелкой, где они стоят")
    func подписи() {
        let names = SnapScreenNames.names(frames: [left, laptop, right], titles: ["DELL", "Встроенный", "LG"], home: 1)
        #expect(names == ["← DELL", "Этот экран", "→ LG"])
        let above = CGRect(x: 0, y: 982, width: 1920, height: 1080)
        #expect(SnapScreenNames.names(frames: [laptop, above], titles: ["A", "B"], home: 0) == ["Этот экран", "↑ B"])
    }

    @Test("Монитор сверху справа — диагональ, а не «вправо»")
    func диагональ() {
        // Как у пользователя: два монитора над ноутбуком, левее и правее.
        let upLeft = CGRect(x: -732, y: 982, width: 2560, height: 1440)
        let upRight = CGRect(x: 1828, y: 982, width: 2560, height: 1440)
        let names = SnapScreenNames.names(frames: [upLeft, laptop, upRight], titles: ["A", "Mac", "B"], home: 1)
        #expect(names == ["↑ A", "Этот экран", "↗ B"])
        #expect(SnapScreenNames.arrow(dx: -100, dy: -100) == "↙")
        #expect(SnapScreenNames.arrow(dx: 0, dy: -50) == "↓")
    }

    @Test("Два одинаковых монитора с одной стороны различает номер")
    func одинаковые() {
        let far = CGRect(x: 4072, y: 0, width: 2560, height: 1440)
        let names = SnapScreenNames.names(frames: [laptop, right, far], titles: ["Mac", "DELL", "DELL"], home: 0)
        #expect(names == ["Этот экран", "→ DELL 1", "→ DELL 2"])
    }

    private let notch = CGRect(x: 1512 / 2 - 100, y: 982 - 32, width: 200, height: 32)

    @Test("Один монитор — ряда экранов нет, плитки как раньше")
    func одинЭкран() {
        let one = WindowSnapBoard.layout(screen: laptop, visible: laptop, notch: notch)
        #expect(one.screens.isEmpty)
        let three = WindowSnapBoard.layout(screen: laptop, visible: laptop, notch: notch, screenCount: 3)
        #expect(three.screens.count == 3)
        // Ряд экранов под отменой, плитки ниже ряда.
        #expect(three.screens.allSatisfy { $0.minY >= one.cancel.maxY })
        #expect(three.area.minY > three.screens[0].maxY)
        #expect(three.area.minY > one.area.minY)
    }

    @Test("Ряд экранов по центру и не шире рабочей области")
    func ряд() {
        let chips = WindowSnapBoard.screenChips(count: 3, centerX: 756, top: 100, width: 1488)
        #expect(chips.count == 3)
        #expect(abs((chips.first!.minX + chips.last!.maxX) / 2 - 756) <= 1)
        let tight = WindowSnapBoard.screenChips(count: 8, centerX: 300, top: 0, width: 600)
        #expect(tight.last!.maxX - tight.first!.minX <= 600 + 1)
    }

    @Test("Курсор над плашкой — экран, а не плитка и не отмена")
    func попадание() {
        let layout = WindowSnapBoard.layout(screen: laptop, visible: laptop, notch: notch, screenCount: 3)
        let chip = layout.screens[2]
        #expect(WindowSnapBoard.target(at: CGPoint(x: chip.midX, y: chip.midY), in: layout) == .screen(2))
        let cancel = layout.cancel
        #expect(WindowSnapBoard.target(at: CGPoint(x: cancel.midX, y: cancel.midY), in: layout) == .cancel)
    }
}
