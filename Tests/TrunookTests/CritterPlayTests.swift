import Foundation
import Testing
@testable import Trunook

@Suite("Новые сценки кота: мышь, пляж, птичка, слежка")
struct CritterPlayTests {
    private let added: [NotchCritter.Act] = [.mouse, .beach, .bird, .watch]

    // MARK: - Расписание

    @Test("Новые сценки выходят наравне с прочими и не привязаны к празднику")
    func вОбщемНаборе() {
        let everyday = CritterSchedule.everyday
        for act in added {
            #expect(everyday.contains(act))
            #expect(CritterHoliday.act(for: act) == nil)
            #expect(!act.isReminder)
        }
    }

    /// Сценка живёт ровно столько, сколько идёт её действие: обрежь её —
    /// котик исчезнет посреди дела.
    @Test("Длительности хватает на всё, что происходит")
    func длительности() {
        // Мышь: после поимки остаётся время унести её в чёлку.
        #expect(NotchCritter.Act.mouse.duration > CritterView.mouseCatch + 2.5)
        // Птичка: прыжок и уход в чёлку после него.
        #expect(NotchCritter.Act.bird.duration > CritterView.birdLeap + 1.4)
        #expect(CritterView.birdPerch < CritterView.birdLeap)
        for act in added {
            #expect(act.duration >= 9)
            #expect(act.duration <= 13)
        }
    }

    @Test("За курсором следит слежка, но не остальные новые сценки")
    func взглядЗаКурсором() {
        #expect(NotchCritter.Act.watch.followsCursor)
        #expect(!NotchCritter.Act.mouse.followsCursor)
        #expect(!NotchCritter.Act.beach.followsCursor)
        #expect(!NotchCritter.Act.bird.followsCursor)
    }

    // MARK: - Рисунок

    @Test("Лапка в слежке — часть спрайта, и котик от неё не съезжает вбок")
    func лапка() {
        let calm = CritterArt.loafLooking(look: 0, blink: false)
        let reach = CritterArt.loafLooking(look: 0, blink: false, reaching: true)
        // Лапка нарисована в самом спрайте, а не отдельным куском рядом:
        // отдельная отрывалась от тела.
        #expect(reach.cells != calm.cells)
        // Поля с обеих сторон: без них середина уезжала бы вместе с лапкой,
        // и котик дёргался бы вбок на каждом взмахе.
        #expect(reach.width == calm.width + 6)
        // Зрачки не разъезжаются от того, что спрайт стал шире.
        func eyes(_ sprite: CritterArt.Sprite) -> Int {
            sprite.cells.reduce(0) { count, row in count + row.filter { $0 == false }.count }
        }
        #expect(eyes(reach) == eyes(calm))
        #expect(eyes(CritterArt.loafLooking(look: 2, blink: false, reaching: true)) == eyes(calm))
    }

    @Test("Мышь бежит двумя кадрами и не меняет размера")
    func мышь() {
        let step0 = CritterArt.mouse(step: 0)
        let step1 = CritterArt.mouse(step: 1)
        #expect(step0.width == step1.width)
        #expect(step0.height == step1.height)
        #expect(step0.cells != step1.cells)
        // Тёмный глаз и хвост: без них серое пятно мышью не читается.
        #expect(step0.cells.contains { $0.contains("K") })
        #expect(step0.cells.contains { $0.contains("k") })
        // Мышь мельче котика — иначе это уже не добыча, а сосед по чёлке.
        #expect(step0.width < CritterArt.loaf[0].width)
        #expect(step0.height < CritterArt.loaf[0].height)
    }

    @Test("Зонт раскрывается вширь, а ножка остаётся на месте")
    func зонт() {
        func canopy(_ open: Double) -> Int {
            let sprite = CritterArt.umbrella(open: open)
            return sprite.cells[0].filter { $0 != nil }.count
        }
        #expect(canopy(0.2) < canopy(1))
        let full = CritterArt.umbrella(open: 1)
        // Тёмная кромка под куполом — иначе белые полосы пропадают
        // на светлых обоях.
        #expect(full.cells.contains { $0.contains("k") })
        // Ножка одна и до самой земли.
        #expect(full.cells.last?.contains("t") == true)
    }

    @Test("Смузи убывает глотками и не уходит в минус")
    func смузи() {
        func drink(_ level: Int) -> Int {
            CritterArt.smoothie(level: level).cells.reduce(0) { count, row in
                count + row.filter { $0 == "p" }.count
            }
        }
        #expect(drink(5) > drink(2))
        #expect(drink(0) == 0)
        #expect(drink(-3) == 0)
        // Трубочка на месте и в пустом стакане.
        #expect(CritterArt.smoothie(level: 0).cells.contains { $0.contains("W") })
    }

    @Test("У птички два кадра крыльев, и они разные")
    func птичка() {
        let up = CritterArt.bird(wingsUp: true)
        let down = CritterArt.bird(wingsUp: false)
        #expect(up.width == down.width)
        #expect(up.height == down.height)
        #expect(up.cells != down.cells)
        // Клюв и глаз есть у обоих: без них жёлтое пятно птицей не читается.
        #expect(up.cells.contains { $0.contains("o") })
        #expect(down.cells.contains { $0.contains("K") })
    }

    @Test("Буханка водит зрачками, не меняя силуэта")
    func взгляд() {
        let ahead = CritterArt.loafLooking(look: 0, blink: false)
        let right = CritterArt.loafLooking(look: 2, blink: false)
        let blink = CritterArt.loafLooking(look: 2, blink: true)
        #expect(ahead.width == right.width)
        #expect(ahead.height == right.height)
        #expect(ahead.cells != right.cells)

        func eyes(_ sprite: CritterArt.Sprite) -> Int {
            sprite.cells.reduce(0) { count, row in count + row.filter { $0 == false }.count }
        }
        // Зрачков по-прежнему столько же: они двигаются, а не плодятся.
        #expect(eyes(ahead) == eyes(right))
        // Прикрытые глаза — один ряд вместо двух.
        #expect(eyes(blink) < eyes(ahead))
    }
}
