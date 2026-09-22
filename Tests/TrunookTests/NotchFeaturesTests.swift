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

    @Test("Плитка под курсором: колонки слева направо, ряды сверху вниз")
    func попадание() {
        let notch: CGFloat = 32
        let top = notch + NotchStyle.topGap
        let left = NotchStyle.bodyInset
        let w = WindowSnapLayout.tileWidth, s = WindowSnapLayout.spacing
        func at(_ x: CGFloat, _ y: CGFloat) -> WindowSlot {
            WindowSnapLayout.slot(at: CGPoint(x: left + x, y: top + y), notchHeight: notch)
        }
        #expect(at(10, 5) == .leftHalf)
        #expect(at(10, WindowSnapLayout.gridHeight - 5) == .leftHalf)
        #expect(at(w + s + 10, 5) == .leftTwoThirds)
        #expect(at(w + s + 10, WindowSnapLayout.gridHeight - 5) == .leftThird)
        #expect(at(2 * (w + s) + 10, 5) == .leftTopQuarter)
        #expect(at(3 * (w + s) + 10, 5) == .fill)
        #expect(at(3 * (w + s) + 10, WindowSnapLayout.gridHeight - 5) == .center)
        #expect(at(WindowSnapLayout.contentWidth - 10, 5) == .rightHalf)
        #expect(at(WindowSnapLayout.contentWidth - w - s - 10, 5) == .rightTwoThirds)
        #expect(at(WindowSnapLayout.contentWidth - 2 * (w + s) - 10, 70) == .rightBottomQuarter)
        // Выше сетки и за полями — ближайшая плитка.
        #expect(WindowSnapLayout.slot(at: CGPoint(x: -50, y: 0), notchHeight: notch) == .leftHalf)
        #expect(WindowSnapLayout.slot(at: CGPoint(x: 9_999, y: 9_999), notchHeight: notch) == .rightHalf)
        #expect(WindowSnapLayout.tileHeight(of: .leftHalf) == WindowSnapLayout.gridHeight)
        #expect(WindowSnapLayout.tileHeight(of: .leftTwoThirds) == WindowSnapLayout.tileHeight)
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
