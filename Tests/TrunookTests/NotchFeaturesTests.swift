import Foundation
import SwiftUI
import Testing
@testable import Trunook

@Suite("Разделы полки")
struct ShelfDropZoneTests {
    @Test("Раздел узнаётся по горизонтали, поля достаются крайним")
    func разделПоГоризонтали() {
        let width: CGFloat = 440
        let inset: CGFloat = 20
        #expect(ShelfDropZone.at(x: 0, width: width, inset: inset) == .shelf)
        #expect(ShelfDropZone.at(x: 30, width: width, inset: inset) == .shelf)
        #expect(ShelfDropZone.at(x: 150, width: width, inset: inset) == .archive)
        #expect(ShelfDropZone.at(x: 250, width: width, inset: inset) == .share)
        #expect(ShelfDropZone.at(x: 430, width: width, inset: inset) == .trash)
        #expect(ShelfDropZone.at(x: 999, width: width, inset: inset) == .trash)
    }

    @Test("Архивы узнаются по хвосту имени")
    func архивы() {
        #expect(ShelfFileActions.isArchive(URL(fileURLWithPath: "/tmp/отчёт.zip")))
        #expect(ShelfFileActions.isArchive(URL(fileURLWithPath: "/tmp/src.tar.gz")))
        #expect(ShelfFileActions.isArchive(URL(fileURLWithPath: "/tmp/SRC.TGZ")))
        #expect(!ShelfFileActions.isArchive(URL(fileURLWithPath: "/tmp/фото.jpg")))
        #expect(!ShelfFileActions.isArchive(URL(fileURLWithPath: "/tmp/.zip")))
        #expect(ShelfFileActions.unpacks([URL(fileURLWithPath: "/a.zip"), URL(fileURLWithPath: "/b.tar")]))
        #expect(!ShelfFileActions.unpacks([URL(fileURLWithPath: "/a.zip"), URL(fileURLWithPath: "/b.txt")]))
        #expect(!ShelfFileActions.unpacks([]))
    }

    @Test("Свободное имя не перезаписывает чужой файл")
    func свободноеИмя() {
        let folder = URL(fileURLWithPath: "/tmp/probe")
        let taken: Set<String> = ["Архив.zip", "Архив 2.zip", "src.tar.gz"]
        let exists: (URL) -> Bool = { taken.contains($0.lastPathComponent) }
        #expect(ShelfFileActions.freeURL(named: "Архив.zip", in: folder, exists: exists).lastPathComponent == "Архив 3.zip")
        #expect(ShelfFileActions.freeURL(named: "src.tar.gz", in: folder, exists: exists).lastPathComponent == "src 2.tar.gz")
        #expect(ShelfFileActions.freeURL(named: "папка", in: folder, exists: exists).lastPathComponent == "папка")
        #expect(ShelfFileActions.baseName(ofArchive: URL(fileURLWithPath: "/x/отчёт.tar.bz2")) == "отчёт")
    }

    @Test("Сжатие и распаковка возвращают те же файлы")
    func сжатиеИРаспаковка() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("shelf-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let one = folder.appendingPathComponent("один.txt")
        let two = folder.appendingPathComponent("два.txt")
        try "1".write(to: one, atomically: true, encoding: .utf8)
        try "2".write(to: two, atomically: true, encoding: .utf8)

        let zip = try ShelfFileActions.archive([one, two])
        #expect(FileManager.default.fileExists(atPath: zip.path))
        let unpacked = try ShelfFileActions.unarchive(zip)
        let names = try FileManager.default.contentsOfDirectory(atPath: unpacked.path).sorted()
        #expect(names == ["два.txt", "один.txt"].sorted())
    }
}

@Suite("Обратный отсчёт")
struct CountdownClockTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("Дальше суток — дни и часы, ближе — часы, минуты, секунды")
    func части() throws {
        let far = try #require(CountdownClock.parts(from: now, to: now.addingTimeInterval(3 * 86_400 + 5 * 3600 + 20)))
        #expect(far == .init(days: 3, hours: 5, minutes: 0, seconds: 20))
        #expect(CountdownClock.text(far, compact: false) == tf("%d дн %d ч", 3, 5))
        #expect(CountdownClock.text(far, compact: true) == tf("%d дн", 3))

        let near = try #require(CountdownClock.parts(from: now, to: now.addingTimeInterval(2 * 3600 + 5 * 60 + 9)))
        #expect(CountdownClock.text(near, compact: true) == "2:05:09")
    }

    @Test("Наступившее событие отсчёта не даёт")
    func наступило() {
        #expect(CountdownClock.parts(from: now, to: now) == nil)
        #expect(CountdownClock.parts(from: now, to: now.addingTimeInterval(-60)) == nil)
    }
}

@Suite("Напоминания о перерыве")
struct BreakTrackerTests {
    private func minutes(_ kind: BreakKind) -> Int {
        switch kind {
        case .rest: return 50
        case .water: return 30
        case .stretch: return 0
        }
    }

    @Test("Считается только время за машиной")
    func времяЗаМашиной() {
        var tracker = BreakTracker()
        // 29,5 минуты работы — ещё рано.
        for _ in 0..<59 { #expect(tracker.advance(by: 30, idle: 5, minutes: minutes).isEmpty) }
        // Читал минуту, не трогая мышь, — счёт стоит.
        #expect(tracker.advance(by: 60, idle: 150, minutes: minutes).isEmpty)
        #expect(tracker.advance(by: 30, idle: 5, minutes: minutes) == [.water])
    }

    @Test("Долгая отлучка — это перерыв, но не вода")
    func отлучка() {
        var tracker = BreakTracker()
        for _ in 0..<40 { _ = tracker.advance(by: 30, idle: 5, minutes: minutes) }
        _ = tracker.advance(by: 30, idle: 400, minutes: minutes)
        #expect(tracker.worked[.rest] == 0)
        #expect(tracker.worked[.water] == 1200)
    }

    @Test("Выключенное не копится, показанное — сначала")
    func выключенноеИСброс() {
        var tracker = BreakTracker()
        var due: [BreakKind] = []
        for _ in 0..<100 { due = tracker.advance(by: 30, idle: 1, minutes: minutes) }
        #expect(due == [.rest, .water])
        #expect(tracker.worked[.stretch] == 0)
        tracker.reset(.rest)
        #expect(tracker.advance(by: 30, idle: 1, minutes: minutes) == [.water])
    }

    @Test("Показанное ждёт ответа, ответ снимает ожидание")
    func ответ() {
        let reminders = BreakReminders(settings: Settings(defaults: UserDefaults(suiteName: "break-test-\(UUID())")!))
        reminders.debugAwait(.water)
        #expect(reminders.awaiting == .water)
        reminders.answer(.rest, done: true)
        #expect(reminders.awaiting == .water)
        reminders.answer(.water, done: false)
        #expect(reminders.awaiting == nil)
    }

    @Test("Напоминание висит без срока и держится при наведении")
    func безСрока() {
        let activity = Activity(kind: .breakReminder(.stretch))
        #expect(activity.duration == .infinity)
        #expect(activity.isInteractive)
        #expect(ActivityView.answer(for: .breakReminder(.rest))?.count == 2)
        #expect(ActivityView.isDismissable(.countdownReached(title: "Отпуск")))
    }

    @Test("Обычные сценки кота — без напоминаний")
    func сценкиНапоминанийНеВыходятСами() {
        #expect(CritterSchedule.everyday.allSatisfy { !$0.isReminder })
        #expect(BreakKind.allCases.allSatisfy { $0.act.isReminder })
    }
}

@Suite("Раскладка окон")
struct WindowSnapTests {
    @Test("Рамки делят рабочую область зеркально")
    func рамки() {
        let visible = CGRect(x: 0, y: 25, width: 1500, height: 900)
        #expect(WindowSlot.fill.frame(in: visible) == visible)
        #expect(WindowSlot.center.frame(in: visible) == CGRect(x: 113, y: 93, width: 1275, height: 765))
        #expect(WindowSlot.leftHalf.frame(in: visible) == CGRect(x: 0, y: 25, width: 750, height: 900))
        #expect(WindowSlot.rightThird.frame(in: visible) == CGRect(x: 1000, y: 25, width: 500, height: 900))
        #expect(WindowSlot.leftTopQuarter.frame(in: visible) == CGRect(x: 0, y: 475, width: 750, height: 450))
        #expect(WindowSlot.rightBottomQuarter.frame(in: visible) == CGRect(x: 750, y: 25, width: 750, height: 450))
        // Правая сторона — зеркало левой.
        #expect(WindowSlot.rightTwoThirds.frame(in: visible) == CGRect(x: 500, y: 25, width: 1000, height: 900))
        for (left, right) in [(WindowSlot.leftHalf, WindowSlot.rightHalf), (.leftThird, .rightThird), (.leftTwoThirds, .rightTwoThirds),
                              (.leftTopQuarter, .rightTopQuarter), (.leftBottomQuarter, .rightBottomQuarter)] {
            #expect(left.unit.width == right.unit.width)
            #expect(abs(left.unit.minX - (1 - right.unit.maxX)) < 0.0001)
            #expect(left.unit.minY == right.unit.minY)
        }
    }

    @Test("Окну, которому раскладка мала, есть к какому краю прижаться")
    func края() {
        #expect(WindowSlot.leftThird.edges == [])
        #expect(WindowSlot.rightThird.edges == [.right])
        #expect(WindowSlot.rightTwoThirds.edges == [.right])
        #expect(WindowSlot.leftTwoThirds.edges == [])
        #expect(WindowSlot.rightBottomQuarter.edges == [.right, .bottom])
        #expect(WindowSlot.leftBottomQuarter.edges == [.bottom])
        #expect(WindowSlot.fill.edges == [])
        #expect(WindowSlot.center.edges == [.center])
    }

    @Test("Четверти от краёв и половины по высоте")
    func новыеРамки() {
        let visible = CGRect(x: 0, y: 25, width: 1600, height: 900)
        #expect(WindowSlot.firstQuarter.frame(in: visible) == CGRect(x: 0, y: 25, width: 400, height: 900))
        #expect(WindowSlot.fourthQuarter.frame(in: visible) == CGRect(x: 1200, y: 25, width: 400, height: 900))
        #expect(WindowSlot.rightThreeQuarters.frame(in: visible) == CGRect(x: 400, y: 25, width: 1200, height: 900))
        // Трети и четверти — всегда от края экрана.
        for slot in WindowSlot.allCases where slot.unit.height == 1 && slot.unit.width < 1 {
            #expect(slot.unit.minX < 0.0001 || slot.unit.maxX > 0.9999, "\(slot) не у края")
        }
        #expect(WindowSlot.topHalf.frame(in: visible) == CGRect(x: 0, y: 475, width: 1600, height: 450))
        #expect(WindowSlot.fourthQuarter.edges == [.right])
        #expect(WindowSlot.bottomHalf.edges == [.bottom])
    }

    @Test("Следующие места дополняют раскладку до всего экрана")
    func следующиеМеста() {
        for slot in WindowSlot.allCases where !slot.followUps.isEmpty {
            let area = ([slot] + slot.followUps).reduce(0.0) { $0 + $1.unit.width * $1.unit.height }
            #expect(abs(area - 1) < 0.0001, "\(slot) с продолжением не покрывает экран")
            for (index, a) in ([slot] + slot.followUps).enumerated() {
                for b in ([slot] + slot.followUps)[(index + 1)...] {
                    let overlap = a.unit.intersection(b.unit)
                    #expect(overlap.isNull || overlap.width * overlap.height < 0.000001, "\(a) и \(b) налезают")
                }
            }
        }
        #expect(WindowSlot.topHalf.followUps == [.bottomHalf])
        #expect(WindowSlot.rightBottomQuarter.followUps == [.leftTopQuarter, .rightTopQuarter, .leftBottomQuarter])
        #expect(WindowSlot.fill.followUps.isEmpty)
        #expect(WindowSlot.center.followUps.isEmpty)
    }

    @Test("Место отступает от настоящего края соседнего окна")
    func местоПоОкну() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)
        // Табличный редактор не уже 713 точек при трети в 504 — правые две трети сужаются.
        let wide = CGRect(x: 0, y: 0, width: 713, height: 949)
        #expect(WindowSlot.fit(WindowSlot.rightTwoThirds.frame(in: visible), avoiding: [wide])
                == CGRect(x: 713, y: 0, width: 799, height: 949))
        // Зеркально справа.
        let right = CGRect(x: 799, y: 0, width: 713, height: 949)
        #expect(WindowSlot.fit(WindowSlot.leftTwoThirds.frame(in: visible), avoiding: [right])
                == CGRect(x: 0, y: 0, width: 799, height: 949))
        // Верхняя половина вышла выше — нижняя ниже её края (y снизу, как в AppKit).
        let top = CGRect(x: 0, y: 400, width: 1512, height: 549)
        #expect(WindowSlot.fit(WindowSlot.bottomHalf.frame(in: visible), avoiding: [top])
                == CGRect(x: 0, y: 0, width: 1512, height: 400))
        // Угол, не давший себя сузить: сосед по ряду отступает по ширине,
        // угол под ним — по высоте.
        let corner = CGRect(x: 0, y: 475, width: 900, height: 474)
        #expect(WindowSlot.fit(WindowSlot.rightTopQuarter.frame(in: visible), avoiding: [corner]).minX == 900)
        #expect(WindowSlot.fit(WindowSlot.leftBottomQuarter.frame(in: visible), avoiding: [corner])
                == WindowSlot.leftBottomQuarter.frame(in: visible))
        // Встало как надо или уже — место по плану, не шире.
        let narrow = CGRect(x: 0, y: 0, width: 600, height: 949)
        #expect(WindowSlot.fit(WindowSlot.rightHalf.frame(in: visible), avoiding: [narrow]) == WindowSlot.rightHalf.frame(in: visible))
    }

    @Test("Разметка: каждая раскладка ровно раз, плитки не налезают")
    func разметкаПолная() {
        let slots = WindowSnapBoard.cells.map(\.slot)
        #expect(slots.count == WindowSlot.allCases.count)
        #expect(Set(slots) == Set(WindowSlot.allCases))
        for cell in WindowSnapBoard.cells {
            #expect(CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -0.0001, dy: -0.0001).contains(cell.unit))
        }
        for (index, a) in WindowSnapBoard.cells.enumerated() {
            for b in WindowSnapBoard.cells[(index + 1)...] {
                let overlap = a.unit.intersection(b.unit)
                #expect(overlap.isNull || overlap.width * overlap.height < 0.000001, "\(a.slot) и \(b.slot) налезают")
            }
        }
    }

    @Test("Разметка: плитка стоит там, где окажется окно")
    func разметкаПоМестам() {
        func unit(_ slot: WindowSlot) -> CGRect { WindowSnapBoard.cells.first { $0.slot == slot }!.unit }
        // Углы — в углах (y плитки сверху вниз).
        #expect(unit(.leftTopQuarter).minX == 0 && unit(.leftTopQuarter).minY == 0)
        #expect(abs(unit(.rightTopQuarter).maxX - 1) < 0.0001 && unit(.rightTopQuarter).minY == 0)
        #expect(unit(.leftBottomQuarter).minX == 0 && abs(unit(.leftBottomQuarter).maxY - 1) < 0.0001)
        #expect(abs(unit(.rightBottomQuarter).maxX - 1) < 0.0001 && abs(unit(.rightBottomQuarter).maxY - 1) < 0.0001)
        // Верх и низ — посередине сверху и снизу, середина — в середине.
        #expect(abs(unit(.topHalf).midX - 0.5) < 0.0001 && unit(.topHalf).minY == 0)
        #expect(abs(unit(.bottomHalf).midX - 0.5) < 0.0001 && abs(unit(.bottomHalf).maxY - 1) < 0.0001)
        for slot in [WindowSlot.fill, .center] {
            #expect(abs(unit(slot).midX - 0.5) < 0.0001)
            #expect(unit(slot).minY > unit(.topHalf).maxY && unit(slot).maxY < unit(.bottomHalf).minY)
        }
        // Полосы во всю высоту — по порядку середины окна, каждая на своей стороне.
        let strips = WindowSlot.allCases.filter { $0.unit.height == 1 && $0.unit.width < 1 }
        let byTile = strips.sorted { unit($0).midX < unit($1).midX }
        let byWindow = strips.sorted { $0.unit.midX < $1.unit.midX }
        #expect(byTile == byWindow)
        for slot in strips { #expect((unit(slot).midX < 0.5) == (slot.unit.midX < 0.5)) }
    }

    private var screenLayout: WindowSnapBoard.Layout {
        WindowSnapBoard.layout(
            screen: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visible: CGRect(x: 0, y: 0, width: 1512, height: 944),
            notch: CGRect(x: 663, y: 950, width: 185, height: 32)
        )
    }

    @Test("Разметка: отмена под чёлкой, плитки ниже, внутри рабочей области")
    func разметкаМеста() {
        let layout = screenLayout
        #expect(abs(layout.cancel.midX - 755.5) <= 1)
        #expect(layout.cancel.minY >= 32)
        #expect(layout.area.minY > layout.cancel.maxY)
        #expect(layout.area.maxY <= 982)
        #expect(layout.area.minX >= 0 && layout.area.maxX <= 1512)
        for rect in layout.tiles.values { #expect(layout.area.insetBy(dx: -1, dy: -1).contains(rect)) }
    }

    @Test("Разметка: что под курсором")
    func попадание() {
        let layout = screenLayout
        func at(_ point: CGPoint) -> WindowSnapBoard.Target? { WindowSnapBoard.target(at: point, in: layout) }
        func center(_ slot: WindowSlot) -> CGPoint { CGPoint(x: layout.tiles[slot]!.midX, y: layout.tiles[slot]!.midY) }
        for slot in WindowSlot.allCases { #expect(at(center(slot)) == .slot(slot)) }
        #expect(at(CGPoint(x: layout.cancel.midX, y: layout.cancel.midY)) == .cancel)
        // Стык двух плиток — одной из них, а не мимо.
        let half = layout.tiles[.leftHalf]!
        #expect(at(CGPoint(x: half.maxX, y: half.midY)) != nil)
        // Сбоку от отмены, выше плиток — мимо.
        #expect(at(CGPoint(x: 40, y: layout.cancel.midY)) == nil)
    }
}

@Suite("Наведение на вырез")
struct HoverZoneTests {
    @Test("Мини-вид держится формой с запасом, а не всем окном")
    func зонаЗакрытия() {
        let preview = CGRect(x: 640, y: 908, width: 233, height: 74)
        let notch = CGRect(x: 663, y: 950, width: 185, height: 32)
        let zone = NotchWindowHost.closeRect(visible: preview, open: notch)
        #expect(zone.contains(CGPoint(x: 650, y: 900)))
        // Под мини-видом в сотне точек — уже не наведение, хотя окно выреза
        // простирается и туда.
        #expect(!zone.contains(CGPoint(x: 756, y: 800)))
        #expect(!zone.contains(CGPoint(x: 560, y: 950)))
        #expect(zone.contains(notch.origin))
    }
}
