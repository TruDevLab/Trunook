import SwiftUI

/// Сценки, где котик занят своим делом под чёлкой: ловит мышь, загорает
/// под зонтом, гоняется за птичкой и следит за курсором.
///
/// Отдельным файлом от `CritterView` по той же причине, по какой отдельно
/// живут праздники: сценок стало два десятка, и в одном файле их развилка
/// перестала читаться. Сцена, маршрут и сам котик — общие
/// (`Stage`, `Route`, `drawCat`), здесь только то, что происходит.
///
/// **Правило, общее для всех сценок:** котик выходит из-за края чёлки
/// и уходит туда же. Ни он, ни его вещи не появляются посреди экрана
/// и не тают на месте: вырез — единственная дверь этого мира, и всё, что
/// возникает мимо неё, читается сбоем отрисовки, а не сценкой. Первая
/// правка этих сценок была ровно об этом: котик выезжал вниз из-под
/// кромки, а в конце растворялся.
extension CritterView {
    // MARK: - Мышь

    /// Сбоку выбегает мышь, котик гонится за ней, ловит и уносит в зубах
    /// в чёлку.
    func drawMouse(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let s = Stage(g, side: critter.side)
        let p = s.p
        let clipped = Self.outsideNotch(ctx, g)

        let mouse = Self.mousePlace(t, g: g, side: s.side, ground: s.ground)
        // Пока бежит — мышь на земле, поймана — висит в зубах у котика.
        if t < Self.mouseCatch + 0.5 {
            let ahead = Self.mousePlace(t + 0.05, g: g, side: s.side, ground: s.ground)
            WeatherArt.draw(CritterArt.mouse(step: Int(t * 9) % 2), in: clipped,
                            anchor: mouse, flipped: ahead.x > mouse.x)
        }

        switch t {
        case ..<0.7:
            // Котик ещё за чёлкой: первой выбегает мышь.
            return
        case ..<Self.mouseCatch:
            // Бежит за мышью, отставая: догоняющий точь-в-точь выглядел бы
            // привязанным к ней верёвкой.
            let chased = Self.mousePlace(max(0, t - 0.4), g: g, side: s.side, ground: s.ground)
            let appear = CGFloat(Self.ease((t - 0.7) / 0.7))
            let x = s.hidden.x + (chased.x - s.hidden.x) * appear
            // Спускается с полосы меню на землю, а не возникает под чёлкой.
            let y = s.menu + (s.ground - s.menu) * min(1, appear * 1.6)
            let next = Self.mousePlace(max(0, t - 0.35), g: g, side: s.side, ground: s.ground)
            CritterArt.draw(CritterArt.run[Int(t * 9) % 2], in: clipped,
                            anchor: CGPoint(x: x, y: y), flipped: next.x < x)
        case ..<(Self.mouseCatch + 0.5):
            // Прыжок: накрывает мышь лапами.
            let jump = CGFloat(Self.ease((t - Self.mouseCatch) / 0.5))
            let from = Self.mousePlace(Self.mouseCatch - 0.5, g: g, side: s.side, ground: s.ground)
            let x = from.x + (mouse.x - from.x) * jump
            let lift = CGFloat(sin(Double(jump) * .pi)) * 22
            CritterArt.draw(CritterArt.run[0], in: clipped,
                            anchor: CGPoint(x: x, y: s.ground - lift), flipped: mouse.x < from.x)
        default:
            // Поймал — уносит в чёлку, мышь в зубах.
            let caught = CGPoint(x: mouse.x, y: s.ground)
            let walk = Route(start: caught, legs: [
                .init(to: caught, duration: 0.6),
                .init(to: s.ledge, duration: 0.9),
                .init(to: s.hidden, duration: 0.8),
            ])
            let place = walk.at(t - Self.mouseCatch - 0.5)
            let facingRight = abs(place.dx) > 1 ? place.dx > 0 : s.side < 0
            let sprite = place.moving ? CritterArt.run[Int(t * 8) % 2] : CritterArt.loaf[0]
            CritterArt.draw(sprite, in: clipped, anchor: place.point, flipped: !facingRight)
            // Добыча в зубах — у мордочки, чуть ниже глаз.
            let facing: CGFloat = facingRight ? 1 : -1
            WeatherArt.draw(
                CritterArt.mouse(step: 0), in: clipped,
                anchor: CGPoint(x: place.point.x + facing * 12 * p, y: place.point.y - 2 * p),
                flipped: facingRight
            )
        }
    }

    /// Когда котик настигает мышь.
    static let mouseCatch: Double = 6.2

    /// Где мышь в миг `time`: выбегает из-за края чёлки, мечется под ней
    /// зигзагом и замирает, когда её накрыли.
    static func mousePlace(_ time: Double, g: Geometry, side: CGFloat, ground: CGFloat) -> CGPoint {
        let edge = g.midX + side * g.notchWidth / 2
        let sweep = g.notchWidth / 2 + 40
        let caught = min(time, mouseCatch)
        guard caught >= 0.6 else {
            // Спускается с полосы меню на землю у края чёлки.
            let out = CGFloat(ease(max(0, caught) / 0.6))
            return CGPoint(x: edge - side * 26 + side * out * 54,
                           y: g.notchHeight - 1 + out * (ground - g.notchHeight + 1))
        }
        // Мечется: синус с добавкой второй волны — мышь не бегает ровно.
        let phase = (caught - 0.6) * 1.5
        let drift = CGFloat(sin(phase) + 0.35 * sin(phase * 2.3))
        return CGPoint(x: g.midX + side * 28 + drift * sweep * 0.7, y: ground)
    }

    // MARK: - Пляж

    /// Котик выходит сбоку, ставит зонт под чёлкой, лежит под ним со смузи
    /// и уходит вместе с зонтом. Чёлка в это время светит солнцем.
    ///
    /// Солнце рисуется лучами **под** кромкой чёлки, а не в ней: в месте
    /// выреза у экрана нет пикселей, и всё нарисованное внутри закрыто
    /// железом — это уже ловило нас на глазах кота.
    func drawBeach(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let s = Stage(g, side: critter.side)
        let p = s.p
        let clipped = Self.outsideNotch(ctx, g)
        let duration = NotchCritter.Act.beach.duration
        let shine = min(Self.ease((t - 0.6) / 1.2), Self.ease((duration - t) / 1.2))
        Self.drawSunshine(in: clipped, g, t: t, strength: shine)

        // Земля у пляжа ниже обычной: зонт выше кота на две его высоты,
        // и под самой чёлкой купол срезало вырезом. Проверено снимком.
        let spot = CGPoint(x: g.midX + s.side * 20, y: g.notchHeight + 86)
        let leaves = duration - 1.7
        let route = Route(start: s.hidden, legs: [
            .init(to: s.ledge, duration: 0.7),
            .init(to: spot, duration: 0.8),
            .init(to: spot, duration: leaves - 1.5),
            .init(to: s.ledge, duration: 0.8),
            .init(to: s.hidden, duration: 0.9),
        ])
        let place = route.at(t)
        let facingRight = abs(place.dx) > 1 ? place.dx > 0 : s.side > 0
        let facing: CGFloat = facingRight ? 1 : -1
        let resting = !place.moving

        // Зонт: пока идёт — сложенный рядом с котиком, на месте — раскрыт
        // над ним. Ножка за спиной, купол сверху; выше кромки чёлки купол
        // не поднимается — иначе его срезало бы вырезом.
        let open = min(Self.ease((t - 1.7) / 0.9), 1 - Self.ease((t - (leaves - 1.0)) / 0.7))
        let umbrella = CritterArt.umbrella(open: max(0.16, open))
        // Раскрытый стоит почти по центру котика — купол должен накрывать
        // его целиком, а не только хвост; сложенный котик несёт сбоку.
        let umbrellaX = place.point.x - facing * (open > 0.5 ? 8 : 20)
        WeatherArt.draw(umbrella, in: clipped,
                        anchor: CGPoint(x: umbrellaX, y: place.point.y + p), flipped: !facingRight)

        // Смузи — перед мордочкой: пить из-за спины котик не умеет. Сам
        // по себе он не появляется — котик приносит его с собой, и пока
        // идёт, стакан едет у его лап.
        let sips = max(0, min(5, 5 - Int((t - 3.4) / 1.1)))
        if t > 1.0, t < leaves + 0.6 {
            let glassX = place.point.x + facing * (resting ? 26 : 12)
            WeatherArt.draw(CritterArt.smoothie(level: sips), in: clipped,
                            anchor: CGPoint(x: glassX, y: place.point.y), flipped: !facingRight)
        }

        // Котик: идёт — бегущий кадр, лежит — буханка, на глотке подаётся
        // к стакану.
        let sipping = resting && Int(t * 2) % 2 == 0
        let lean: CGFloat = sipping ? facing * p : 0
        let blink = (5.0..<5.2).contains(t) || (7.6..<7.8).contains(t)
        let sprite = resting ? CritterArt.loaf[blink ? 1 : 0] : CritterArt.run[Int(t * 8) % 2]
        CritterArt.draw(sprite, in: clipped,
                        anchor: CGPoint(x: place.point.x + lean, y: place.point.y),
                        flipped: !facingRight)
    }

    /// Солнечный свет из-под чёлки: тёплое зарево и лучи, которые медленно
    /// дышат. Рисуется первым, до котика, — он должен лежать в свете,
    /// а не под ним.
    static func drawSunshine(in ctx: GraphicsContext, _ g: Geometry, t: TimeInterval, strength: Double) {
        guard strength > 0.01 else { return }
        let origin = CGPoint(x: g.midX, y: g.notchHeight)
        var glow = ctx
        glow.opacity = strength
        // Зарево — мягкое пятно под кромкой.
        let halo = CGRect(x: origin.x - 150, y: origin.y - 150, width: 300, height: 300)
        glow.fill(
            Path(ellipseIn: halo),
            with: .radialGradient(
                Gradient(colors: [CritterArt.sunGlow.opacity(0.5), CritterArt.sunGlow.opacity(0)]),
                center: origin, startRadius: 0, endRadius: 150
            )
        )
        // Лучи: от кромки вниз веером, длина дышит.
        var rays = Path()
        for index in 0..<7 {
            let angle = Double(index - 3) * 0.32
            let length = 70 + 16 * sin(t * 1.3 + Double(index))
            let spread = 5.0
            let tip = CGPoint(
                x: origin.x + CGFloat(sin(angle) * length),
                y: origin.y + CGFloat(cos(angle) * length)
            )
            rays.move(to: CGPoint(x: origin.x - CGFloat(spread), y: origin.y))
            rays.addLine(to: tip)
            rays.addLine(to: CGPoint(x: origin.x + CGFloat(spread), y: origin.y))
            rays.closeSubpath()
        }
        glow.fill(rays, with: .color(CritterArt.sunGlow.opacity(0.35)))
    }

    // MARK: - Птичка

    /// Из чёлки вылетает птичка, котик выбегает сбоку и гонится за ней,
    /// прыгает — она уходит обратно в чёлку, а он убегает за край.
    ///
    /// Котик бежит не к птичке, а туда, где она была мгновение назад:
    /// догоняющий точь-в-точь выглядел бы привязанным к ней верёвкой.
    func drawBird(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let s = Stage(g, side: critter.side)
        let clipped = Self.outsideNotch(ctx, g)
        let ground = s.ground

        let bird = Self.birdPlace(t, g: g, side: s.side, ground: ground)
        // Взмахи чаще в полёте, реже на земле.
        let flapping = t < Self.birdPerch - 1.4 || t > Self.birdPerch
        let wings = flapping ? Int(t * 9) % 2 == 0 : false
        let ahead = Self.birdPlace(t + 0.05, g: g, side: s.side, ground: ground)
        WeatherArt.draw(CritterArt.bird(wingsUp: wings), in: clipped, anchor: bird,
                        flipped: ahead.x < bird.x)

        let leap = Self.birdLeap
        switch t {
        case ..<0.6:
            // Котик ещё за чёлкой: первой вылетает птичка.
            return
        case ..<leap:
            // Выбегает из-за края, спускается на землю и гонится за птичкой.
            let chased = Self.birdPlace(max(0.5, t - 0.45), g: g, side: s.side, ground: ground)
            let appear = CGFloat(Self.ease((t - 0.6) / 0.7))
            let x = s.hidden.x + (chased.x - s.hidden.x) * appear
            let y = s.menu + (ground - s.menu) * min(1, appear * 1.6)
            let next = Self.birdPlace(max(0.5, t - 0.4), g: g, side: s.side, ground: ground)
            // Перед прыжком прижимается и не дышит.
            let sprite = t < Self.birdPerch ? CritterArt.run[Int(t * 9) % 2] : CritterArt.loaf[0]
            CritterArt.draw(sprite, in: clipped, anchor: CGPoint(x: x, y: y), flipped: next.x < x)
        case ..<(leap + 0.7):
            // Прыжок дугой туда, где птичка только что сидела.
            let jump = CGFloat(Self.ease((t - leap) / 0.7))
            let to = g.midX - s.side * 40
            let from = to + s.side * 34
            let x = from + (to - from) * jump
            let lift = CGFloat(sin(Double(jump) * .pi)) * 26
            CritterArt.draw(CritterArt.run[0], in: clipped,
                            anchor: CGPoint(x: x, y: ground - lift), flipped: to < from)
        default:
            // Не поймал — уходит за край чёлки, а не растворяется на месте.
            let landed = CGPoint(x: g.midX - s.side * 40, y: ground)
            let route = Route(start: landed, legs: [
                .init(to: landed, duration: 0.5),
                .init(to: s.ledge, duration: 0.9),
                .init(to: s.hidden, duration: 0.8),
            ])
            _ = drawCat(on: route, at: t - leap - 0.7, in: clipped, facingRight: s.side < 0)
        }
    }

    /// Когда птичка садится на землю и когда котик прыгает.
    static let birdPerch: Double = 6.4
    static let birdLeap: Double = 7.0

    /// Где птичка в миг `time`: вылетает из-под кромки, ходит волной,
    /// садится и уходит вверх в чёлку.
    static func birdPlace(_ time: Double, g: Geometry, side: CGFloat, ground: CGFloat) -> CGPoint {
        let sweep = g.notchWidth / 2 + 60
        let flightEnd = birdPerch - 1.4
        let perched = CGPoint(x: g.midX - side * 40, y: ground)
        switch time {
        case ..<0.5:
            let rise = ease(time / 0.5)
            return CGPoint(x: g.midX, y: g.notchHeight + CGFloat(rise) * 22)
        case ..<flightEnd:
            let phase = (time - 0.5) * 1.25
            return CGPoint(
                x: g.midX + CGFloat(sin(phase)) * sweep,
                y: g.notchHeight + 22 + CGFloat(sin(phase * 2.2)) * 10
            )
        case ..<birdPerch:
            let land = CGFloat(ease((time - flightEnd) / (birdPerch - flightEnd)))
            let from = CGPoint(x: g.midX + CGFloat(sin((flightEnd - 0.5) * 1.25)) * sweep,
                               y: g.notchHeight + 22)
            return CGPoint(x: from.x + (perched.x - from.x) * land,
                           y: from.y + (perched.y - from.y) * land)
        default:
            let away = CGFloat(ease((time - birdPerch) / 1.1))
            return CGPoint(x: perched.x + (g.midX - perched.x) * away,
                           y: perched.y + (g.notchHeight - 4 - perched.y) * away)
        }
    }

    // MARK: - Слежка за курсором

    /// Котик выходит сбоку, ложится под чёлкой и следит за курсором,
    /// не сходя с места: водит зрачками, разворачивается в его сторону
    /// и бьёт лапкой, если курсор подошёл близко.
    ///
    /// Именно лёжа и на одном месте: бегающий за курсором котик — это уже
    /// охота, и такая сценка есть.
    func drawWatch(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let s = Stage(g, side: critter.side)
        let p = s.p
        let clipped = Self.outsideNotch(ctx, g)
        let duration = NotchCritter.Act.watch.duration
        let spot = s.under(0)
        let route = Route(start: s.hidden, legs: [
            .init(to: s.ledge, duration: 0.7),
            .init(to: spot, duration: 0.8),
            .init(to: spot, duration: duration - 3.0),
            .init(to: s.ledge, duration: 0.7),
            .init(to: s.hidden, duration: 0.8),
        ])
        let place = route.at(t)

        guard !place.moving else {
            // Пока идёт — обычный бегущий котик; следить ещё рано.
            let facingRight = abs(place.dx) > 1 ? place.dx > 0 : s.side > 0
            CritterArt.draw(CritterArt.run[Int(t * 8) % 2], in: clipped,
                            anchor: place.point, flipped: !facingRight)
            return
        }

        // Лежит и смотрит: разворачивается в сторону курсора целиком,
        // а зрачки косятся ещё дальше. Двигаются зрачки, а не голова:
        // у буханки голова — часть силуэта.
        let gaze = critter.gaze
        let facingRight = gaze.x >= 0
        let look = Int((abs(gaze.x) * 3).rounded())
        let blink = [2.4, 4.8].contains { abs(t - $0) < 0.12 }
        // Курсор совсем рядом — котик тянет к нему лапку. Взмахи один
        // за другим: одинокий читался бы подёргиванием, а не попыткой.
        // Лапка — часть того же спрайта: отдельная отрывалась от тела.
        let swipe = (t * 1.6).truncatingRemainder(dividingBy: 1)
        let reaching = critter.squints && swipe < 0.45
        let sprite = CritterArt.loafLooking(look: blink ? 0 : look, blink: blink, reaching: reaching)
        CritterArt.draw(sprite, in: clipped, anchor: place.point, flipped: !facingRight)
        _ = p
    }
}
