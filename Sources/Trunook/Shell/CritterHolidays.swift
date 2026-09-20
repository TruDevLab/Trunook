import SwiftUI

/// Праздники, в которые у кота есть своя сценка.
///
/// Только в свой день: в праздник котик через раз играет праздничную
/// сценку (`CritterSchedule.pick`), в остальные дни их нет вовсе.
enum CritterHoliday: String, CaseIterable {
    /// Новый год и Рождество — с 25 декабря по 8 января: и католическое,
    /// и православное Рождество.
    case newYear
    case childrenDay
    case womenDay
    case defenderDay
    /// Пасха — и западная, и православная.
    case easter
    case halloween
    case valentine
    case victoryDay
    case lunarNewYear
    case cosmonautics

    var act: NotchCritter.Act {
        switch self {
        case .newYear: return .winter
        case .childrenDay: return .kittens
        case .womenDay: return .flowers
        case .defenderDay: return .tank
        case .easter: return .easter
        case .halloween: return .pumpkin
        case .valentine: return .valentine
        case .victoryDay: return .ribbon
        case .lunarNewYear: return .dragon
        case .cosmonautics: return .rocket
        }
    }

    /// Праздник, которому принадлежит сценка; `nil` — сценка обычная.
    static func act(for act: NotchCritter.Act) -> CritterHoliday? {
        allCases.first { $0.act == act }
    }

    /// Праздники в этот день. Бывает и два сразу: православная Пасха 2026
    /// выпадает на День космонавтики.
    static func on(_ date: Date, calendar: Calendar = .current) -> [CritterHoliday] {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return [] }
        var found: [CritterHoliday] = []
        if (month == 12 && day >= 25) || (month == 1 && day <= 8) { found.append(.newYear) }
        if month == 2 && day == 14 { found.append(.valentine) }
        if month == 2 && day == 23 { found.append(.defenderDay) }
        if month == 3 && day == 8 { found.append(.womenDay) }
        if month == 4 && day == 12 { found.append(.cosmonautics) }
        if month == 5 && day == 9 { found.append(.victoryDay) }
        if month == 6 && day == 1 { found.append(.childrenDay) }
        if month == 10 && day == 31 { found.append(.halloween) }
        let easters = [westernEaster(year), orthodoxEaster(year)]
        if easters.contains(where: { $0.month == month && $0.day == day }) { found.append(.easter) }
        if isLunarNewYear(date) { found.append(.lunarNewYear) }
        return found
    }

    /// Западная Пасха по григорианскому календарю — анонимный алгоритм.
    static func westernEaster(_ year: Int) -> (month: Int, day: Int) {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let n = h + l - 7 * m + 114
        return (n / 31, n % 31 + 1)
    }

    /// Православная Пасха: по юлианскому календарю (алгоритм Меёса),
    /// переведённая в григорианский — плюс тринадцать дней в 1900–2099.
    static func orthodoxEaster(_ year: Int) -> (month: Int, day: Int) {
        let a = year % 4, b = year % 7, c = year % 19
        let d = (19 * c + 15) % 30
        let e = (2 * a + 4 * b - d + 34) % 7
        let n = d + e + 114
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let julian = utc.date(from: DateComponents(year: year, month: n / 31, day: n % 31 + 1)),
              let shifted = utc.date(byAdding: .day, value: 13, to: julian) else { return (0, 0) }
        let parts = utc.dateComponents([.month, .day], from: shifted)
        return (parts.month ?? 0, parts.day ?? 0)
    }

    /// Первый день первого месяца по китайскому календарю — он в Foundation
    /// есть, таблица дат не нужна.
    static func isLunarNewYear(_ date: Date) -> Bool {
        let parts = Calendar(identifier: .chinese).dateComponents([.month, .day], from: date)
        return parts.month == 1 && parts.day == 1 && parts.isLeapMonth != true
    }
}

// MARK: - Сценки

extension CritterView {
    /// Путь котика отрезками: откуда, куда и за сколько. Пауза — отрезок
    /// в ту же точку.
    struct Route {
        struct Leg {
            var to: CGPoint
            var duration: Double
        }
        let start: CGPoint
        let legs: [Leg]

        var duration: Double { legs.reduce(0) { $0 + $1.duration } }

        /// Где в миг `t`, куда движется по горизонтали и движется ли вообще.
        ///
        /// Отрезки движения подряд — одна плавная кривая с разгоном в начале
        /// и торможением в конце. Раньше каждый отрезок разгонялся и тормозил
        /// сам, и на стыке — например, спрыгнув с полосы меню под чёлку —
        /// котик замирал и дёргался дальше рывком. Пауза (отрезок в ту же
        /// точку) кривую разрывает: там котик и должен стоять.
        func at(_ t: Double) -> (point: CGPoint, dx: CGFloat, moving: Bool) {
            let points = [start] + legs.map(\.to)
            var starts: [Double] = []
            var clock = 0.0
            for leg in legs {
                starts.append(clock)
                clock += leg.duration
            }
            guard let index = starts.lastIndex(where: { t >= $0 }), t < clock else {
                return (points.last ?? start, 0, false)
            }
            func isPause(_ i: Int) -> Bool { points[i] == points[i + 1] }
            if isPause(index) { return (points[index], 0, false) }
            // Границы непрерывного движения вокруг текущего отрезка.
            var first = index, last = index
            while first > 0, !isPause(first - 1) { first -= 1 }
            while last < legs.count - 1, !isPause(last + 1) { last += 1 }
            let begin = starts[first]
            let end = starts[last] + legs[last].duration
            // Разгон и торможение — на всё движение, а не на каждый отрезок.
            let eased = begin + CritterView.ease((t - begin) / (end - begin)) * (end - begin)
            let leg = starts.lastIndex(where: { eased >= $0 }).map { min(max($0, first), last) } ?? first
            let k = CGFloat(min(1, max(0, (eased - starts[leg]) / legs[leg].duration)))
            // Катмулл — Ром по точкам этого движения: кривая проходит через все.
            let p0 = points[max(first, leg - 1)], p1 = points[leg], p2 = points[leg + 1]
            let p3 = points[min(last + 1, leg + 2)]
            func axis(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                let k2 = k * k, k3 = k2 * k
                return 0.5 * (2 * b + (-a + c) * k + (2 * a - 5 * b + 4 * c - d) * k2 + (-a + 3 * b - 3 * c + d) * k3)
            }
            let point = CGPoint(x: axis(p0.x, p1.x, p2.x, p3.x), y: axis(p0.y, p1.y, p2.y, p3.y))
            return (point, p2.x - p1.x, true)
        }
    }

    /// Цветная деталь поверх котика — клетками на его сетке, с учётом того,
    /// куда он смотрит.
    static func drawOn(_ piece: CritterArt.Colored, column: Int, row: Int, cat: CritterArt.Sprite,
                       anchor: CGPoint, flipped: Bool, in ctx: GraphicsContext) {
        var paths: [Character: Path] = [:]
        for y in 0..<piece.height {
            for x in 0..<piece.width {
                guard let key = piece.cells[y][x] else { continue }
                let rect = CritterArt.cell(column + x, row + y, of: cat, anchor: anchor, flipped: flipped)
                paths[key, default: Path()].addRect(rect)
            }
        }
        if let rim = paths.removeValue(forKey: "k") { ctx.fill(rim, with: .color(WeatherArt.color("k"))) }
        for (key, path) in paths { ctx.fill(path, with: .color(WeatherArt.color(key))) }
    }

    /// Бегущий или лежащий котик на маршруте.
    func drawCat(on route: Route, at t: Double, in ctx: GraphicsContext, facingRight fallback: Bool,
                 lying: CritterArt.Sprite? = nil) -> (sprite: CritterArt.Sprite, anchor: CGPoint, flipped: Bool) {
        let place = route.at(t)
        let facingRight = abs(place.dx) > 1 ? place.dx > 0 : fallback
        let sprite = place.moving ? CritterArt.run[Int(t * 8) % 2] : (lying ?? CritterArt.loaf[0])
        CritterArt.draw(sprite, in: ctx, anchor: place.point, flipped: !facingRight)
        return (sprite, place.point, !facingRight)
    }

    /// Сцена: где у этой сценки край чёлки, полоса меню и земля.
    ///
    /// Не `private`: по ней же живут и обычные сценки из `CritterPlay`.
    /// Свой такой же расчёт у них разошёлся бы с этим на первой же правке
    /// высоты земли — а земля у всех одна.
    struct Stage {
        let p = CritterArt.pixel
        let side: CGFloat
        let edge: CGFloat
        let far: CGFloat
        let menu: CGFloat
        let ground: CGFloat
        let midX: CGFloat

        init(_ g: Geometry, side: CGFloat) {
            self.side = side
            midX = g.midX
            edge = g.midX + side * g.notchWidth / 2
            far = g.midX - side * g.notchWidth / 2
            menu = g.notchHeight - 1
            ground = g.notchHeight + 40
        }

        var hidden: CGPoint { CGPoint(x: edge - side * 26, y: menu) }
        var ledge: CGPoint { CGPoint(x: edge + side * 22, y: menu) }
        var farLedge: CGPoint { CGPoint(x: far - side * 22, y: menu) }
        var farHidden: CGPoint { CGPoint(x: far + side * 26, y: menu) }
        func under(_ offset: CGFloat) -> CGPoint { CGPoint(x: midX + side * offset, y: ground) }
    }

    // MARK: Новый год

    func drawWinter(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let s = Stage(g, side: critter.side)
        let clipped = Self.outsideNotch(ctx, g)
        let notch = g.notchRect
        // Снег из чёлки — двумя волнами, чтобы шёл всю сценку.
        WeatherArt.draw(.snow, in: clipped, notch: notch, size: g.size, t: t)
        if t > 3.5 { WeatherArt.draw(.snow, in: clipped, notch: notch, size: g.size, t: t - 3.5) }

        // Земля ниже, чем в других сценках: котик прыгает в сугробы дугой,
        // и с обычной высоты он в верхней точке заскакивал за чёлку.
        let ground = s.ground + 24
        let drifts = [s.midX + s.side * 55, s.midX - s.side * 5, s.midX - s.side * 65]
        // В сугробе наполовину: низ в снегу, над ним голова и шапка.
        // Глубже — торчала одна шапка, выше — котик сидел на сугробе.
        let sink: CGFloat = 0
        let landings = [2.4, 3.7, 5.0]
        // Котик: выбегает, спрыгивает под чёлку, ныряет в сугробы по очереди.
        let jumps: [(from: CGPoint, to: CGPoint, start: Double)] = [
            (CGPoint(x: drifts[0] + s.side * 24, y: ground), CGPoint(x: drifts[0], y: ground + sink), 1.9),
            (CGPoint(x: drifts[0], y: ground + sink), CGPoint(x: drifts[1], y: ground + sink), 3.2),
            (CGPoint(x: drifts[1], y: ground + sink), CGPoint(x: drifts[2], y: ground + sink), 4.5),
            (CGPoint(x: drifts[2], y: ground + sink), CGPoint(x: drifts[2] - s.side * 30, y: ground), 5.8),
        ]
        var cat: (sprite: CritterArt.Sprite, anchor: CGPoint, flipped: Bool)?
        var catClip: CGFloat?
        let towardFar = s.side < 0
        switch t {
        case ..<1.9:
            let route = Route(start: s.hidden, legs: [
                .init(to: s.ledge, duration: 0.8),
                .init(to: CGPoint(x: drifts[0] + s.side * 44, y: ground), duration: 0.5),
                .init(to: jumps[0].from, duration: 0.6),
            ])
            let place = route.at(t)
            let right = abs(place.dx) > 1 ? place.dx > 0 : towardFar
            cat = (CritterArt.run[Int(t * 8) % 2], place.point, !right)
        case ..<6.3:
            if let jump = jumps.last(where: { t >= $0.start }), t < jump.start + 0.5 {
                let k = (t - jump.start) / 0.5
                let arc = CGFloat(sin(k * .pi)) * 18
                let x = jump.from.x + (jump.to.x - jump.from.x) * CGFloat(k)
                let y = jump.from.y + (jump.to.y - jump.from.y) * CGFloat(k) - arc
                cat = (CritterArt.run[0], CGPoint(x: x, y: y), !towardFar)
                catClip = ground
            } else if let jump = jumps.last(where: { t >= $0.start }) {
                // Сидит в сугробе: видны голова и шапка.
                cat = (CritterArt.loaf[0], jump.to, !towardFar)
                catClip = ground
            }
        default:
            let route = Route(start: jumps[3].to, legs: [
                .init(to: s.farLedge, duration: 0.5),
                .init(to: s.farHidden, duration: 0.8),
            ])
            let place = route.at(t - 6.3)
            let right = abs(place.dx) > 1 ? place.dx > 0 : towardFar
            cat = (CritterArt.run[Int(t * 8) % 2], place.point, !right)
        }

        if let cat {
            var catCtx = clipped
            if let floor = catClip {
                catCtx.clip(to: Path(CGRect(x: 0, y: 0, width: g.size.width, height: floor)))
            }
            CritterArt.draw(cat.sprite, in: catCtx, anchor: cat.anchor, flipped: cat.flipped)
            Self.drawOn(CritterArt.santaHat, column: CritterArt.santaHatColumn, row: CritterArt.santaHatRow,
                        cat: cat.sprite, anchor: cat.anchor, flipped: cat.flipped, in: catCtx)
            Self.drawOn(CritterArt.beard, column: CritterArt.beardColumn, row: CritterArt.beardRow,
                        cat: cat.sprite, anchor: cat.anchor, flipped: cat.flipped, in: catCtx)
        }
        // Сугробы — поверх котика: он в них проваливается.
        for (i, x) in drifts.enumerated() {
            let growth = Self.ease((t - Double(i) * 0.4) / 2.2)
            guard growth > 0.05 else { continue }
            WeatherArt.draw(CritterArt.drift(growth: growth), in: clipped, anchor: CGPoint(x: x, y: ground))
        }
        // Снежные брызги на каждом прыжке в сугроб.
        for (i, landing) in landings.enumerated() {
            let local = t - landing
            guard local > 0, local < 0.35 else { continue }
            var puff = Path()
            for ray in 0..<6 {
                let angle = Double.pi + Double(ray) * .pi / 5
                let r = CGFloat(local / 0.35) * 16
                let x = drifts[i] + CGFloat(cos(angle)) * r
                let y = ground - 12 + CGFloat(sin(angle)) * r
                puff.addRect(CGRect(x: WeatherArt.snap(x), y: WeatherArt.snap(y), width: s.p, height: s.p))
            }
            clipped.fill(puff, with: .color(.white))
        }
    }

    // MARK: День защиты детей

    func drawKittens(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let s = Stage(g, side: critter.side)
        let clipped = Self.outsideNotch(ctx, g)
        let spot = s.under(0)
        let drop = s.under(70)
        let arrive = Route(start: s.hidden, legs: [
            .init(to: s.ledge, duration: 0.8),
            .init(to: drop, duration: 0.5),
            .init(to: spot, duration: 0.6),
        ])
        // Уходят за противоположный край чёлки, а не туда, откуда пришли.
        let leave = Route(start: spot, legs: [
            .init(to: s.under(-70), duration: 0.5),
            .init(to: s.farLedge, duration: 0.5),
            .init(to: s.farHidden, duration: 0.8),
        ])
        let circleStart = 3.0, circleEnd = 6.0
        let radius = CGSize(width: 48, height: 12)
        let spin = 2 * Double.pi * 1.5 / (circleEnd - circleStart) * Double(-s.side)
        func ring(_ angle: Double) -> CGPoint {
            CGPoint(x: spot.x + radius.width * CGFloat(cos(angle)), y: spot.y + radius.height * CGFloat(sin(angle)))
        }

        // Котята: где каждый и куда смотрит.
        var kittens: [(point: CGPoint, right: Bool, moving: Bool, behind: Bool)] = []
        for i in 0..<3 {
            let delay = 0.35 * Double(i + 1)
            let baseAngle = s.side > 0 ? 0.0 : Double.pi
            let startAngle = baseAngle + Double(i) * 2 * .pi / 3
            if t < circleStart {
                let local = t - delay
                guard local > 0 else { continue }
                if local < arrive.duration {
                    let place = arrive.at(local)
                    kittens.append((place.point, place.dx > 0, true, false))
                } else {
                    // Добежал — занимает место на кругу.
                    let k = CGFloat(Self.ease((t - delay - arrive.duration) / 0.4))
                    let target = ring(startAngle)
                    let point = CGPoint(x: spot.x + (target.x - spot.x) * k, y: spot.y + (target.y - spot.y) * k)
                    kittens.append((point, target.x > spot.x, k < 1, target.y < spot.y))
                }
            } else if t < circleEnd {
                let angle = startAngle + spin * (t - circleStart)
                let right = -sin(angle) * spin > 0
                kittens.append((ring(angle), right, true, sin(angle) < 0))
            } else {
                let endAngle = startAngle + spin * (circleEnd - circleStart)
                let local = t - circleEnd - 0.25 * Double(i + 1)
                if local < 0 {
                    kittens.append((ring(endAngle), s.side < 0, false, sin(endAngle) < 0))
                } else if local < 0.3 {
                    let k = CGFloat(Self.ease(local / 0.3))
                    let from = ring(endAngle)
                    let point = CGPoint(x: from.x + (spot.x - from.x) * k, y: from.y + (spot.y - from.y) * k)
                    kittens.append((point, s.side < 0, true, false))
                } else if local - 0.3 < leave.duration {
                    let place = leave.at(local - 0.3)
                    kittens.append((place.point, place.dx > 0, true, false))
                }
            }
        }
        func drawKitten(_ kitten: (point: CGPoint, right: Bool, moving: Bool, behind: Bool)) {
            let frame = kitten.moving ? Int(t * 10) % 2 : 2
            CritterArt.draw(CritterArt.kitten[frame], in: clipped, anchor: kitten.point, flipped: !kitten.right)
        }
        for kitten in kittens where kitten.behind { drawKitten(kitten) }

        // Мама-кошка.
        if t < circleEnd + 0.2 {
            let place = arrive.at(t)
            let lying = CritterArt.loaf[(3.5..<3.7).contains(t) || (5.0..<5.2).contains(t) ? 1 : 0]
            let right = abs(place.dx) > 1 ? place.dx > 0 : s.side < 0
            let sprite = place.moving ? CritterArt.run[Int(t * 8) % 2] : lying
            CritterArt.draw(sprite, in: clipped, anchor: place.point, flipped: !right)
        } else {
            let place = leave.at(t - circleEnd - 0.2)
            if place.moving || t - circleEnd - 0.2 < leave.duration {
                CritterArt.draw(CritterArt.run[Int(t * 8) % 2], in: clipped, anchor: place.point, flipped: !(place.dx > 0))
            }
        }
        for kitten in kittens where !kitten.behind { drawKitten(kitten) }
    }

    // MARK: 8 Марта

    func drawFlowers(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let s = Stage(g, side: critter.side)
        let p = s.p
        let clipped = Self.outsideNotch(ctx, g)
        let spot = s.under(40)
        let route = Route(start: s.hidden, legs: [
            .init(to: s.ledge, duration: 0.8),
            .init(to: spot, duration: 0.6),
            .init(to: spot, duration: 3.8),
            .init(to: s.ledge, duration: 0.5),
            .init(to: s.hidden, duration: 0.8),
        ])
        let place = route.at(t)
        let facingRight = abs(place.dx) > 1 ? place.dx > 0 : s.side > 0
        let blink = (1.8..<2.0).contains(t) || (4.2..<4.4).contains(t)
        let sprite = place.moving ? CritterArt.run[Int(t * 8) % 2] : CritterArt.loaf[blink ? 1 : 0]
        let facing: CGFloat = facingRight ? 1 : -1
        // Букет — перед мордочкой, кульком к подбородку. Выносит его с собой,
        // на месте протягивает вперёд и чуть вверх, потом прижимает обратно.
        let reach = min(Self.ease((t - 1.9) / 0.5), Self.ease((5.2 - t) / 0.4))
        let bob: CGFloat = reach > 0.99 && Int(t * 2.5) % 2 == 0 ? p : 0
        // Низ кулька — у лап: букет высокий, и выше он заходил под чёлку.
        let bouquet = CGPoint(
            x: place.point.x + facing * (11 * p + 8 + CGFloat(reach) * 12),
            y: place.point.y + 3 * p - CGFloat(reach) * 4 - bob
        )
        CritterArt.draw(sprite, in: clipped, anchor: place.point, flipped: !facingRight)
        WeatherArt.draw(CritterArt.bouquet, in: clipped, anchor: bouquet, flipped: !facingRight)
    }

    // MARK: 23 Февраля

    func drawTank(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let s = Stage(g, side: critter.side)
        let p = s.p
        let clipped = Self.outsideNotch(ctx, g)
        let hidden = s.edge - s.side * 40
        let rest = s.edge + s.side * 92
        let shots = [2.2, 3.4]
        let turnAt = 4.6, turnTime = 0.5
        // Путь от 0 — спрятан за краем чёлки, до 1 — стоит на месте.
        let way: Double
        var driving = false
        switch t {
        case ..<1.5:
            way = Self.ease(t / 1.5)
            driving = true
        case ..<(turnAt + turnTime):
            way = 1
            driving = t >= turnAt
        default:
            way = 1 - Self.ease((t - turnAt - turnTime) / 1.6)
            driving = true
        }
        // Разворот: танк сжимается по ширине — встаёт к нам боком —
        // и распрямляется уже пушкой к чёлке. Назад он заезжает передом,
        // а не задом.
        let turn = min(1, max(0, (t - turnAt) / turnTime))
        let facingOut = turn < 0.5
        let squeeze = max(0.06, CGFloat(abs(cos(turn * .pi))))
        let out: CGFloat = facingOut ? s.side : -s.side
        var x = hidden + (rest - hidden) * CGFloat(way)
        // Из-за края выезжает по полосе меню — под чёлкой ниже её он был бы
        // виден и спрятанным, — а отъехав, съезжает ниже, где котику
        // хватает места высунуться.
        let lower = CGFloat(Self.ease((way - 0.4) / 0.6))
        // Отдача: после выстрела танк откатывается на два пикселя.
        for shot in shots where (0..<0.25).contains(t - shot) { x -= s.side * 2 * p }
        let flipped = out < 0
        // Танк ниже полосы меню: над полосой нет места, и котик в люке
        // упирался в край экрана — глаз было не видно.
        let bottom = s.menu + 1 + 15 * lower
        let tank = CritterArt.tank(frame: driving ? Int(t * 10) % 2 : 0)
        let tankTop = bottom - CGFloat(tank.height) * p
        // Котик в люке: голова над башней, остальное — внутри танка.
        // Голова — над люком башни (столбцы 8–15 танка), тело уходит внутрь.
        let catAnchor = CGPoint(x: x - out * 8 * p, y: tankTop + 4 * p)
        var body = clipped
        if squeeze < 1 {
            body.translateBy(x: x, y: 0)
            body.scaleBy(x: squeeze, y: 1)
            body.translateBy(x: -x, y: 0)
        }
        var catCtx = body
        catCtx.clip(to: Path(CGRect(x: -10_000, y: 0, width: 20_000, height: tankTop + 2 * p)))
        CritterArt.draw(CritterArt.loaf[0], in: catCtx, anchor: catAnchor, flipped: flipped)
        WeatherArt.draw(tank, in: body, anchor: CGPoint(x: x, y: bottom), flipped: flipped)

        // Дуло — второй ряд, последний столбец танка.
        let muzzle = CGPoint(x: x + s.side * CGFloat(tank.width / 2) * p, y: tankTop + 2 * p)
        for shot in shots {
            let local = t - shot
            if (0..<0.15).contains(local) {
                WeatherArt.draw(CritterArt.muzzleFlash, in: clipped,
                                anchor: CGPoint(x: muzzle.x + s.side * 4 * p, y: muzzle.y + 3 * p), flipped: flipped)
            }
            if local > 0, local < 0.9 {
                // Снаряд улетает, дым от выстрела расходится и тает.
                var shell = Path()
                shell.addRect(CGRect(x: WeatherArt.snap(muzzle.x + s.side * CGFloat(local) * 420), y: muzzle.y - p,
                                     width: 2 * p, height: p))
                clipped.fill(shell, with: .color(WeatherArt.color("K")))
                var smoke = Path()
                for k in 0..<4 {
                    let r = CGFloat(local) * 22 + CGFloat(k) * 3
                    let sx = muzzle.x + s.side * (8 + r)
                    let sy = muzzle.y - CGFloat(k % 2) * 6 - CGFloat(local) * 10
                    smoke.addRect(CGRect(x: WeatherArt.snap(sx), y: WeatherArt.snap(sy), width: 2 * p, height: 2 * p))
                }
                clipped.fill(smoke, with: .color(Color(white: 0.72).opacity(1 - local / 0.9)))
            }
        }
    }

    // MARK: Пасха

    func drawEaster(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let s = Stage(g, side: critter.side)
        let p = s.p
        let clipped = Self.outsideNotch(ctx, g)
        let feet = s.menu
        let eggRest = s.edge + s.side * 112
        let eggStart = s.edge - s.side * 10
        // Не спеша: первый вариант, вдвое быстрее, выглядел суетливым.
        let rollTime = 2.6, leaveAt = 3.2, crackAt = 7.0, hatchAt = 7.8

        // Яйцо: катится, крутясь, и встаёт. Потом трескается и раскрывается.
        let egg = CritterArt.egg()
        let eggHalf = CGFloat(egg.height) * p / 2
        let eggX = eggStart + (eggRest - eggStart) * CGFloat(Self.easeOut(min(1, t / rollTime)))
        if t < crackAt {
            // Поворот по пройденному пути, рывками по 45°: круглое катится.
            let travelled = Double(abs(eggX - eggStart))
            let spin = t < rollTime ? (travelled / 9 / (.pi / 4)).rounded() * (.pi / 4) : 0
            WeatherArt.drawRotated(egg, in: clipped, center: CGPoint(x: eggX, y: feet - eggHalf),
                                   angle: Double(s.side) * spin)
        } else if t < hatchAt {
            let shake: CGFloat = t > crackAt + 0.4 && Int(t * 14) % 2 == 0 ? p : 0
            WeatherArt.draw(CritterArt.egg(cracked: true), in: clipped, anchor: CGPoint(x: eggRest + shake, y: feet))
        } else {
            var shell = clipped
            shell.opacity = max(0, 1 - (t - (hatchAt + 2.6)) / 0.6)
            WeatherArt.draw(CritterArt.eggBottom, in: shell, anchor: CGPoint(x: eggRest, y: feet))
            // Верх скорлупы подпрыгивает и падает рядом.
            let fly = t - hatchAt
            if fly < 0.8 {
                let k = fly / 0.8
                let x = eggRest - s.side * CGFloat(k) * 18
                let y = feet - 7 * p - CGFloat(sin(k * .pi)) * 14 + CGFloat(k) * 6
                WeatherArt.draw(CritterArt.eggTop, in: clipped, anchor: CGPoint(x: x, y: y))
            }
            // Цыплёнок: сидит в скорлупе, выпрыгивает и бежит в чёлку.
            let chickX: CGFloat
            let chickY: CGFloat
            let running: Bool
            switch fly {
            case ..<1.1:
                chickX = eggRest
                chickY = feet - 5 * p
                running = false
            case ..<1.5:
                let k = (fly - 1.1) / 0.4
                chickX = eggRest - s.side * CGFloat(k) * 16
                chickY = feet - 5 * p * CGFloat(1 - k) - CGFloat(sin(k * .pi)) * 10
                running = false
            default:
                let k = min(1, (fly - 1.5) / 1.3)
                let from = eggRest - s.side * 16
                chickX = from + (s.edge - s.side * 20 - from) * CGFloat(k)
                chickY = feet - CGFloat(abs(sin(fly * 18))) * 2
                running = true
            }
            var chickCtx = clipped
            if fly < 1.1 {
                // В скорлупе видна только верхняя половина.
                chickCtx.clip(to: Path(CGRect(x: 0, y: 0, width: g.size.width, height: feet - 5 * p)))
            }
            WeatherArt.draw(CritterArt.chick(frame: running ? Int(t * 10) % 2 : 0), in: chickCtx,
                            anchor: CGPoint(x: chickX, y: chickY), flipped: s.side > 0)
        }

        // Котик катит яйцо перед собой, кролик скачет за котиком, не обгоняя.
        let catRest = CGPoint(x: eggRest - s.side * 33, y: feet)
        let rabbitRest = CGPoint(x: catRest.x - s.side * 42, y: feet)
        // Уходя, котик сперва спрыгивает вниз с полосы меню и только внизу
        // бежит к чёлке: кролик лежит между ним и чёлкой, и по полосе котик
        // пробегал сквозь него. Кролик тем временем допрыгивает по полосе
        // до места котика — над ним.
        let away: [Route.Leg] = [
            .init(to: CGPoint(x: catRest.x, y: s.ground), duration: 0.9),
            .init(to: s.under(60), duration: 1.0),
            .init(to: s.under(-60), duration: 2.3),
            .init(to: s.farLedge, duration: 0.8),
            .init(to: s.farHidden, duration: 1.2),
        ]
        let catRoute = Route(start: catRest, legs: away)
        if t < leaveAt {
            let x = min(1, t / rollTime) < 1 ? eggX - s.side * 33 : catRest.x
            let moving = t < rollTime
            let sprite = moving ? CritterArt.run[Int(t * 6) % 2] : CritterArt.loaf[0]
            CritterArt.draw(sprite, in: clipped, anchor: CGPoint(x: x, y: feet), flipped: s.side < 0)
        } else {
            _ = drawCat(on: catRoute, at: t - leaveAt, in: clipped, facingRight: s.side < 0)
        }

        let rabbitStart = 0.4
        guard t > rabbitStart else { return }
        var rabbitAt: CGPoint
        var rabbitRight: Bool
        var hopping: Bool
        // Кролик идёт по следу котика с отставанием: сперва допрыгивает
        // до места, где тот лежал, дальше — ровно по его пути, на столько же
        // позже. Свой маршрут со своим разгоном местами обгонял котика,
        // и кролик набегал на него.
        let lag = 1.8, wait = 0.6
        if t < leaveAt {
            // Держится за котиком на том же расстоянии, пока яйцо катится.
            rabbitAt = CGPoint(x: eggX - s.side * 75, y: feet)
            rabbitRight = s.side > 0
            hopping = t < rollTime
        } else if t < leaveAt + lag {
            // Пережидает, пока котик спрыгнет, и допрыгивает до его места.
            let k = CGFloat(Self.ease((t - leaveAt - wait) / (lag - wait)))
            rabbitAt = CGPoint(x: rabbitRest.x + (catRest.x - rabbitRest.x) * k, y: feet)
            rabbitRight = s.side < 0
            hopping = t > leaveAt + wait
        } else {
            // Убежал — не рисовать: спрятанный под чёлкой, он торчал лапками
            // из-под кромки.
            guard t - leaveAt - lag < catRoute.duration else { return }
            let place = catRoute.at(t - leaveAt - lag)
            rabbitAt = place.point
            rabbitRight = abs(place.dx) > 1 ? place.dx > 0 : s.side < 0
            hopping = place.moving
        }
        let hop: CGFloat = hopping ? CGFloat(abs(sin(t * 1.8 * .pi))) * 6 : 0
        WeatherArt.draw(CritterArt.rabbit, in: clipped, anchor: CGPoint(x: rabbitAt.x, y: rabbitAt.y - hop + p),
                        flipped: !rabbitRight)
    }

    // MARK: Хэллоуин

    func drawPumpkin(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let s = Stage(g, side: critter.side)
        let p = s.p
        let clipped = Self.outsideNotch(ctx, g)
        let spot = s.under(40)
        let route = Route(start: s.hidden, legs: [
            .init(to: s.ledge, duration: 0.8),
            .init(to: spot, duration: 0.6),
            .init(to: spot, duration: 3.8),
            .init(to: s.ledge, duration: 0.5),
            .init(to: s.hidden, duration: 0.8),
        ])
        let letters: [(CritterArt.Colored, Double)] = [
            (CritterArt.letterB, 2.0), (CritterArt.letterO, 2.3), (CritterArt.letterO, 2.6),
            (CritterArt.letterO, 2.9), (CritterArt.letterBang, 3.2),
        ]
        let talking = letters.contains { (0..<0.22).contains(t - $0.1) }
        let place = route.at(t)
        let facingRight = abs(place.dx) > 1 ? place.dx > 0 : s.side > 0
        let sprite = place.moving ? CritterArt.run[Int(t * 8) % 2] : CritterArt.loaf[0]
        let anchor = CGPoint(x: place.point.x, y: place.point.y - (talking ? p : 0))
        CritterArt.draw(sprite, in: clipped, anchor: anchor, flipped: !facingRight)
        Self.drawOn(CritterArt.pumpkin(open: talking), column: CritterArt.pumpkinColumn, row: CritterArt.pumpkinRow,
                    cat: sprite, anchor: anchor, flipped: !facingRight, in: clipped)

        // «BOOO!» — слева направо, с какой бы стороны ни сидел котик.
        if t > 2.0, t < 5.0 {
            let step: CGFloat = 13
            let nearest = spot.x + s.side * 48
            let startX = s.side > 0 ? nearest : nearest - step * CGFloat(letters.count - 1)
            for (i, letter) in letters.enumerated() where t >= letter.1 {
                let pop: CGFloat = t - letter.1 < 0.15 ? p : 0
                WeatherArt.draw(letter.0, in: clipped, anchor: CGPoint(x: startX + step * CGFloat(i), y: spot.y - 14 - pop),
                                shadow: true)
            }
        }

        // На «BOOO» из чёлки вылетают три призрака: мечутся и улетают
        // под чёлку с разных сторон.
        let notch = g.notchRect
        let exits = [CGPoint(x: notch.minX + 18, y: 12), CGPoint(x: notch.maxX - 18, y: 12), CGPoint(x: notch.midX, y: 8)]
        let swings: [CGFloat] = [-110, 120, 20]
        for i in 0..<3 {
            let start = 2.1 + Double(i) * 0.15
            let k = (t - start) / 2.4
            guard k > 0, k < 1 else { continue }
            let from = CGPoint(x: notch.midX + CGFloat(i - 1) * 20, y: 12)
            let control = CGPoint(x: notch.midX + swings[i], y: notch.maxY + 130)
            let u = CGFloat(k), v = 1 - CGFloat(k)
            var x = v * v * from.x + 2 * u * v * control.x + u * u * exits[i].x
            var y = v * v * from.y + 2 * u * v * control.y + u * u * exits[i].y
            // Мечутся: поверх дуги — быстрые сбивчивые колебания, стихающие к краям пути.
            let wild = CGFloat(sin(k * .pi))
            x += (CGFloat(sin(t * 9 + Double(i) * 2)) * 18 + CGFloat(sin(t * 5.3 + Double(i))) * 10) * wild
            y += (CGFloat(cos(t * 7.7 + Double(i) * 3)) * 12) * wild
            var ghost = clipped
            ghost.opacity = 0.72
            WeatherArt.draw(CritterArt.ghost(frame: Int(t * 8) % 2), in: ghost, anchor: CGPoint(x: x, y: y),
                            flipped: sin(t * 9 + Double(i) * 2) < 0)
        }
    }

    // MARK: 14 Февраля

    func drawValentine(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let s = Stage(g, side: critter.side)
        let p = s.p
        let clipped = Self.outsideNotch(ctx, g)
        let kissAt = 2.7, partAt = 5.6
        let meet = 11 * p
        func route(from side: CGFloat, delay: Double) -> Route {
            let edge = s.midX + side * g.notchWidth / 2
            let hidden = CGPoint(x: edge - side * 26, y: s.menu)
            let ledge = CGPoint(x: edge + side * 22, y: s.menu)
            let drop = CGPoint(x: s.midX + side * 80, y: s.ground)
            let seat = CGPoint(x: s.midX + side * meet, y: s.ground)
            return Route(start: hidden, legs: [
                .init(to: hidden, duration: delay),
                .init(to: ledge, duration: 0.8),
                .init(to: drop, duration: 0.5),
                .init(to: seat, duration: 0.9),
                .init(to: seat, duration: partAt - 2.2 - delay),
                .init(to: drop, duration: 0.5),
                .init(to: ledge, duration: 0.5),
                .init(to: hidden, duration: 0.8),
            ])
        }
        let kissing = (kissAt..<partAt).contains(t)
        for (side, white) in [(s.side, false), (-s.side, true)] {
            let place = route(from: side, delay: white ? 0.3 : 0).at(t)
            let towardCenter = side < 0
            let right = abs(place.dx) > 1 ? place.dx > 0 : towardCenter
            let lying = CritterArt.loaf[kissing ? 1 : 0]
            let sprite = place.moving ? CritterArt.run[Int(t * 8) % 2] : lying
            // В поцелуе тянутся друг к другу на пиксель.
            let lean: CGFloat = kissing && !place.moving ? -side * p : 0
            let anchor = CGPoint(x: place.point.x + lean, y: place.point.y)
            if white {
                CritterArt.draw(CritterArt.whiteCat(sprite), in: clipped, anchor: anchor, flipped: !right)
            } else {
                CritterArt.draw(sprite, in: clipped, anchor: anchor, flipped: !right)
            }
        }
        guard t > kissAt else { return }
        // Большое сердечко над ними.
        let local = t - kissAt
        if local < 1.4 {
            let heart = CritterArt.hearts[local < 0.2 ? 0 : 1]
            CritterArt.draw(heart, in: clipped, anchor: CGPoint(x: s.midX, y: s.ground - 26 - CGFloat(local) * 12),
                            ink: CritterArt.heartColor)
        }
        // Из чёлки сыплются маленькие сердечки.
        let notch = g.notchRect
        for i in 0..<26 {
            let born = kissAt + WeatherArt.noise(i, 41) * 2.6
            let age = t - born
            guard age > 0 else { continue }
            let fall = CGFloat(age) * (34 + CGFloat(WeatherArt.noise(i, 42)) * 18)
            guard fall < 150 else { continue }
            let x = notch.minX + 12 + CGFloat(WeatherArt.noise(i, 43)) * (notch.width - 24)
                + CGFloat(sin(age * 3 + Double(i))) * 5
            CritterArt.draw(CritterArt.hearts[0], in: clipped, anchor: CGPoint(x: x, y: notch.maxY + fall),
                            ink: CritterArt.heartColor)
        }
    }

    // MARK: 9 Мая

    func drawRibbon(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let s = Stage(g, side: critter.side)
        let p = s.p
        let clipped = Self.outsideNotch(ctx, g)
        let entry = CGPoint(x: s.edge - s.side * 10, y: s.ground)
        let exit = CGPoint(x: s.far + s.side * 10, y: s.ground)
        let cross = 2.6
        let before = 0.7 + 0.5
        let route = Route(start: s.hidden, legs: [
            .init(to: s.ledge, duration: 0.7),
            .init(to: entry, duration: 0.5),
            .init(to: exit, duration: cross),
            .init(to: s.farLedge, duration: 0.5),
            .init(to: s.farHidden, duration: 0.8),
        ])
        /// Путь с волной на пробежке под чёлкой.
        func position(_ time: Double) -> CGPoint {
            var point = route.at(time).point
            if time > before, time < before + cross {
                point.y += CGFloat(sin((time - before) / cross * 3 * .pi)) * 10
            }
            return point
        }
        // Ленточка тянется за котиком по его же следу: три чёрные полосы
        // и две оранжевые.
        let stripes: [Color] = [WeatherArt.color("K"), WeatherArt.color("o"), WeatherArt.color("K"),
                                WeatherArt.color("o"), WeatherArt.color("K")]
        var bands = Array(repeating: Path(), count: stripes.count)
        var lag = 0.05
        while lag < 0.9 {
            let time = t - lag
            if time > 0 {
                let point = position(time)
                let flutter = CGFloat(sin(time * 12 + lag * 20)) * CGFloat(lag) * 6
                let x = WeatherArt.snap(point.x)
                let top = WeatherArt.snap(point.y - 9 * p + flutter)
                for (k, _) in stripes.enumerated() {
                    bands[k].addRect(CGRect(x: x, y: top + CGFloat(k) * p, width: p, height: p))
                }
            }
            lag += 0.012
        }
        for (k, color) in stripes.enumerated() { clipped.fill(bands[k], with: .color(color)) }

        let place = route.at(t)
        guard place.moving || t < route.duration else { return }
        let point = position(t)
        CritterArt.draw(CritterArt.run[Int(t * 8) % 2], in: clipped, anchor: point, flipped: !(place.dx > 0))
    }

    // MARK: Китайский Новый год

    func drawDragon(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let side = critter.side
        let p = CritterArt.pixel
        let clipped = Self.outsideNotch(ctx, g)
        let half = g.notchWidth / 2
        // Путь для правой стороны; для левой отражается.
        let waypoints: [CGPoint] = [
            CGPoint(x: half - 40, y: 16), CGPoint(x: half + 90, y: 18), CGPoint(x: half + 160, y: 70),
            CGPoint(x: half + 110, y: 125), CGPoint(x: 0, y: 108), CGPoint(x: -(half + 110), y: 125),
            CGPoint(x: -(half + 160), y: 70), CGPoint(x: -(half + 90), y: 18), CGPoint(x: -(half - 40), y: 16),
        ]
        let duration = NotchCritter.Act.dragon.duration - 0.6
        func point(_ time: Double) -> CGPoint {
            let u = min(Double(waypoints.count - 1), max(0, time / duration * Double(waypoints.count - 1)))
            let i = min(waypoints.count - 2, Int(u))
            let f = CGFloat(u - Double(i))
            let p0 = waypoints[max(0, i - 1)], p1 = waypoints[i], p2 = waypoints[i + 1]
            let p3 = waypoints[min(waypoints.count - 1, i + 2)]
            // Катмулл — Ром: кривая проходит через все точки.
            func axis(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                let f2 = f * f, f3 = f2 * f
                return 0.5 * (2 * b + (-a + c) * f + (2 * a - 5 * b + 4 * c - d) * f2 + (-a + 3 * b - 3 * c + d) * f3)
            }
            let local = CGPoint(x: axis(p0.x, p1.x, p2.x, p3.x), y: axis(p0.y, p1.y, p2.y, p3.y))
            return CGPoint(x: g.midX + side * local.x, y: local.y)
        }
        // Звенья чаще собственной ширины — тело сплошное, а не бусы.
        let spacing = 0.045
        let count = 24
        // Хвост к голове: голова рисуется последней, поверх тела.
        for k in stride(from: count, through: 1, by: -1) {
            let time = t - Double(k) * spacing
            guard time > 0 else { continue }
            let piece = k > count - 3 ? CritterArt.dragonTail : CritterArt.dragonSegment
            let at = point(time)
            let wave = CGFloat(sin(time * 8 + Double(k))) * p
            WeatherArt.draw(piece, in: clipped, anchor: CGPoint(x: at.x, y: at.y + wave + 3 * p))
        }
        let head = point(t)
        let ahead = point(t + 0.05)
        let right = ahead.x >= head.x
        // Котик верхом — на шестом звене за головой.
        let seatTime = t - 6 * spacing
        if seatTime > 0 {
            let seat = point(seatTime)
            let seatAhead = point(seatTime + 0.05)
            CritterArt.draw(CritterArt.loaf[0], in: clipped, anchor: CGPoint(x: seat.x, y: seat.y - 2 * p),
                            flipped: seatAhead.x < seat.x)
        }
        WeatherArt.draw(CritterArt.dragonHead, in: clipped, anchor: CGPoint(x: head.x, y: head.y + 5 * p), flipped: !right)
        // Усы: два длинных, от морды назад, колышутся на лету волной.
        let facing: CGFloat = right ? 1 : -1
        let snout = CGPoint(x: head.x + facing * 8 * p, y: head.y - p)
        var whiskers = Path()
        for (lift, phase) in [(CGFloat(-1), 0.0), (CGFloat(1), 1.7)] {
            for step in 1...22 {
                let d = CGFloat(step)
                let wave = CGFloat(sin(t * 7 + Double(step) * 0.45 + phase)) * d * 0.28
                let x = snout.x - facing * d * p * 0.9
                let y = snout.y + lift * d * 0.9 + wave + d * 0.35
                whiskers.addRect(CGRect(x: WeatherArt.snap(x), y: WeatherArt.snap(y), width: p, height: p))
            }
        }
        clipped.fill(whiskers, with: .color(WeatherArt.color("D")))
    }

    // MARK: День космонавтики

    func drawRocket(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let side = critter.side
        let p = CritterArt.pixel
        let clipped = Self.outsideNotch(ctx, g)
        let center = CGPoint(x: 120, y: 140)
        let radius: CGFloat = 60
        let start = CGPoint(x: 0, y: 6)
        let bottom = CGPoint(x: center.x, y: center.y + radius)
        let outTime = 0.9, loopTime = 2.4, backTime = 0.9
        /// Путь для правой стороны, от середины выреза.
        func local(_ time: Double) -> CGPoint {
            func bezier(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ k: CGFloat) -> CGPoint {
                let u = 1 - k
                return CGPoint(x: u * u * a.x + 2 * u * k * c.x + k * k * b.x,
                               y: u * u * a.y + 2 * u * k * c.y + k * k * b.y)
            }
            if time < outTime {
                return bezier(start, CGPoint(x: 0, y: bottom.y), bottom, CGFloat(Self.ease(time / outTime)))
            }
            if time < outTime + loopTime {
                let angle = (time - outTime) / loopTime * 2 * .pi
                return CGPoint(x: center.x + radius * CGFloat(sin(angle)), y: center.y + radius * CGFloat(cos(angle)))
            }
            let k = CGFloat(min(1, (time - outTime - loopTime) / backTime))
            return bezier(bottom, CGPoint(x: 10, y: bottom.y), start, CGFloat(Self.ease(Double(k))))
        }
        func screen(_ point: CGPoint) -> CGPoint { CGPoint(x: g.midX + side * point.x, y: point.y) }
        guard t < outTime + loopTime + backTime + 0.1 else { return }

        // Дымный след — клочки по пройденному пути, тают.
        var smoke = Path()
        for k in 1..<10 {
            let time = t - Double(k) * 0.07
            guard time > 0 else { continue }
            let at = screen(local(time))
            let size = CGFloat(1 + k / 4) * p
            smoke.addRect(CGRect(x: WeatherArt.snap(at.x), y: WeatherArt.snap(at.y), width: size, height: size))
        }
        clipped.fill(smoke, with: .color(Color(white: 0.75).opacity(0.7)))

        let here = local(t), ahead = local(t + 0.02)
        // Поворот рывками по 45°: плавно повёрнутый пиксельный рисунок
        // рассыпается в муть, а по восьми направлениям остаётся рисунком.
        let raw = atan2(Double(ahead.y - here.y), Double(ahead.x - here.x))
        let angle = (raw / (.pi / 4)).rounded() * (.pi / 4)
        WeatherArt.drawRotated(CritterArt.rocket(frame: Int(t * 12) % 2), in: clipped, center: screen(here),
                               angle: side > 0 ? angle : -angle, flipped: side < 0)
    }
}
