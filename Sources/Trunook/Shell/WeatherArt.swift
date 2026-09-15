import SwiftUI

/// Погодные сценки под чёлкой: дождь капает из выреза, снег сыплется,
/// солнышко всплывает, облака выплывают или несутся по ветру.
///
/// Пиксельные, той же сеткой, что и кот (`CritterArt.pixel`), но цветные:
/// погоду узнают по цвету раньше, чем по форме. Светлое — облака, снег,
/// порывы ветра — идёт с тёмной обводкой или тенью, иначе на светлых обоях
/// оно пропадает.
///
/// Без зависимостей от приложения, как и `CritterArt`: сценки подбираются
/// глазами по листу кадров, `make weather`. Всё считается из времени
/// от начала сценки, случайность — из номера частицы, поэтому кадр
/// в один и тот же миг всегда одинаков.
enum WeatherArt {
    enum Scene: String, CaseIterable {
        case sun
        case clouds
        case fog
        case drizzle
        case rain
        case snow
        /// Снегопад — снег втрое гуще обычного и быстрее.
        case heavySnow
        /// Вьюга — снег и ветер: снег сдувает вбок с завихрениями.
        case blizzard
        case thunder
        case wind

        var duration: TimeInterval {
            switch self {
            case .sun: return 5.5
            case .clouds: return 6
            case .fog: return 6
            case .drizzle: return 6
            case .rain: return 6.5
            case .snow: return 7.5
            case .heavySnow: return 7.5
            case .blizzard: return 6.5
            case .thunder: return 6.5
            case .wind: return 4.5
            }
        }
    }

    /// Сторона пикселя в точках — как у кота.
    static let pixel: CGFloat = 2

    /// Холст сценки. Выше кошачьего: дождю нужно, куда падать, — и падать
    /// ему бывает из-под плашки о погоде, а она ниже чёлки.
    static let canvasSize = CGSize(width: 480, height: 260)

    /// Нарисовать сценку в миг `t`. `notch` — прямоугольник острова на холсте
    /// в начале сценки; `ctx` уже обрезан так, что внутри острова ничего
    /// не видно. `island` — каким остров был в миг от начала сценки: при смене
    /// погоды вырез раскрыт плашкой, и капли, сорвавшиеся с её нижнего края,
    /// не должны подпрыгнуть, когда плашка свернётся. `mirrored` — ветер дует
    /// справа налево.
    /// `variant` — случайное число показа: сколько облаков, например.
    static func draw(_ scene: Scene, in ctx: GraphicsContext, notch: CGRect, size: CGSize, t: TimeInterval,
                     mirrored: Bool = false, variant: Int = 0, island: ((TimeInterval) -> CGRect)? = nil) {
        let island = island ?? { _ in notch }
        switch scene {
        case .sun: drawSun(ctx, notch: notch, t: t)
        case .clouds: drawClouds(ctx, notch: notch, size: size, t: t, count: 3 + abs(variant) % 3)
        case .fog: drawFog(ctx, notch: notch, size: size, t: t)
        case .drizzle: drawDrops(ctx, island: island, t: t, style: .drizzle)
        case .rain: drawDrops(ctx, island: island, t: t, style: .rain)
        case .snow: drawSnow(ctx, island: island, t: t, density: 1)
        case .heavySnow: drawSnow(ctx, island: island, t: t, density: 3)
        case .blizzard: drawBlizzard(ctx, notch: notch, size: size, t: t, mirrored: mirrored)
        case .thunder:
            drawDrops(ctx, island: island, t: t, style: .storm)
            drawLightning(ctx, notch: notch, t: t)
        case .wind: drawWind(ctx, notch: notch, size: size, t: t, mirrored: mirrored)
        }
    }

    // MARK: - Солнышко

    private static func drawSun(_ ctx: GraphicsContext, notch: CGRect, t: TimeInterval) {
        let duration = Scene.sun.duration
        let reach = min(ease(t / 0.9), ease((duration - t) / 0.7))
        guard reach > 0.01 else { return }
        let sprite = sun(twinkle: Int(t / 0.3) % 2 == 1, blink: abs(t - 2.8) < 0.14)
        let height = CGFloat(sprite.height) * pixel
        // Всплывает из-под кромки и чуть покачивается, пока светит.
        let bob: CGFloat = reach > 0.99 && sin(t * 3) > 0 ? pixel : 0
        let bottom = notch.maxY - 4 + CGFloat(reach) * (height + 6) + bob
        draw(sprite, in: ctx, anchor: CGPoint(x: notch.midX, y: bottom))
    }

    /// Солнце 25×25: круглое, с глазками, улыбкой и лучами. Лучи мерцают —
    /// прямые и косые по очереди становятся длинными.
    static func sun(twinkle: Bool, blink: Bool = false) -> Sprite {
        let side = 25, center = 12.0
        var rows = Array(repeating: Array(repeating: Character("."), count: side), count: side)
        for y in 0..<side {
            for x in 0..<side {
                let distance = hypot(Double(x) - center, Double(y) - center)
                if distance <= 6.3 { rows[y][x] = distance > 5.3 ? "o" : "y" }
            }
        }
        rows[8][9] = "W"; rows[9][8] = "W"; rows[8][10] = "W"
        // Глазки — чёрточки в два ряда, моргание оставляет один.
        for x in [10, 14] {
            rows[12][x] = "k"
            rows[11][x] = blink ? "y" : "k"
        }
        for (x, y) in [(10, 14), (11, 15), (12, 15), (13, 15), (14, 14)] { rows[y][x] = "o" }
        let straight: [(Int, Int)] = [(0, -1), (0, 1), (-1, 0), (1, 0)]
        let slanted: [(Int, Int)] = [(-1, -1), (1, -1), (-1, 1), (1, 1)]
        func ray(_ direction: (Int, Int), from: Int, to: Int) {
            for step in from...to {
                rows[12 + direction.1 * step][12 + direction.0 * step] = "y"
            }
        }
        for direction in straight { twinkle ? ray(direction, from: 9, to: 10) : ray(direction, from: 8, to: 11) }
        for direction in slanted { twinkle ? ray(direction, from: 6, to: 8) : ray(direction, from: 7, to: 7) }
        return Sprite(rows.map { String($0) })
    }

    // MARK: - Облака

    /// Облачно: из-под середины выреза выплывают облака — от трёх до пяти —
    /// и расходятся в стороны, но не дальше, чем помещается в окно: иначе
    /// край окна их срезал. В конце уплывают обратно под чёлку.
    private static func drawClouds(_ ctx: GraphicsContext, notch: CGRect, size: CGSize, t: TimeInterval, count: Int) {
        let duration = Scene.clouds.duration
        // Куда уплывает каждое: сторона, доля свободного места, высота.
        let layout: [(side: CGFloat, share: CGFloat, drop: CGFloat, big: Bool, delay: Double)] = [
            (-1, 0.55, 20, true, 0.0),
            (1, 0.45, 14, false, 0.25),
            (1, 0.95, 38, true, 0.5),
            (-1, 0.95, 46, false, 0.75),
            (1, 0.15, 58, false, 1.0),
        ]
        for plan in layout.prefix(count) {
            let out = min(ease((t - plan.delay) / 1.8), ease((duration - 0.2 - plan.delay * 0.4 - t) / 1.6))
            guard out > 0.01 else { continue }
            let sprite = plan.big ? cloud : smallCloud
            let half = CGFloat(sprite.width) * pixel / 2
            // Свободное место до края холста — с запасом на полоблака.
            let room = max(0, size.width / 2 - half - 12)
            let drift = CGFloat(sin(t * 1.1 + plan.delay * 3)) * 2
            let x = notch.midX + plan.side * CGFloat(out) * room * plan.share + drift * CGFloat(out)
            // Выплывает из-под кромки: начинает внутри выреза.
            let y = notch.maxY - 6 + CGFloat(out) * (plan.drop + 6 + CGFloat(sprite.height) * pixel)
            draw(sprite, in: ctx, anchor: CGPoint(x: x, y: y))
        }
    }

    static let cloud = Sprite([
        ".........kkkkk..........",
        ".......kkWWWWWkk........",
        "......kWWWWWWWWWk.kkkk..",
        "....kkWWWWWWWWWWWkWWWWk.",
        "...kWWWWWWWWWWWWWWWWWWWk",
        "..kWWWWWWWWWWWWWWWWWWWWk",
        ".kWWWWWWWWWWWWWWWWWWWWWk",
        "kWWWWWWWWWWWWWWWWWWWWWWk",
        "kgWWWWWWWWWWWWWWWWWWWWgk",
        "kggWWWWWWWWWWWWWWWWWggk.",
        ".kgggggggggggggggggggk..",
        "..kkkkkkkkkkkkkkkkkkk...",
    ])

    static let smallCloud = Sprite([
        "....kkkk.....",
        "...kWWWWkkk..",
        "..kWWWWWWWWk.",
        ".kWWWWWWWWWWk",
        "kWWWWWWWWWWWk",
        "kgWWWWWWWWWgk",
        ".kgggggggggk.",
        "..kkkkkkkkk..",
    ])

    // MARK: - Ветер

    /// Ветрено: облака и порывы проносятся поперёк всей полосы, за вырезом
    /// пропадают и выныривают с другой стороны.
    private static func drawWind(_ ctx: GraphicsContext, notch: CGRect, size: CGSize, t: TimeInterval, mirrored: Bool) {
        let span = size.width + 80
        func x(start: Double, speed: Double) -> CGFloat? {
            let travelled = (t - start) * speed
            guard travelled >= 0, travelled <= Double(span) else { return nil }
            let forward = CGFloat(travelled) - 40
            return mirrored ? size.width - forward : forward
        }
        let clouds: [(Sprite, Double, Double, CGFloat)] = [
            (cloud, 0.0, 150, notch.maxY + 14),
            (smallCloud, 0.6, 190, notch.maxY - 6),
            (smallCloud, 1.5, 170, notch.maxY + 46),
            (cloud, 2.2, 140, notch.maxY + 30),
        ]
        for (sprite, start, speed, y) in clouds {
            guard let cx = x(start: start, speed: speed) else { continue }
            draw(sprite, in: ctx, anchor: CGPoint(x: cx, y: y), flipped: mirrored)
        }
        // Порывы — белые чёрточки с тенью, быстрее облаков.
        var streaks = Path(), shade = Path()
        for i in 0..<14 {
            let start = noise(i, 1) * (Scene.wind.duration - 1.6)
            guard let head = x(start: start, speed: 320 + noise(i, 2) * 120) else { continue }
            let y = snap(notch.maxY - 10 + CGFloat(noise(i, 3)) * 90)
            let length = CGFloat(Int(4 + noise(i, 4) * 6)) * pixel
            let left = snap(mirrored ? head : head - length)
            streaks.addRect(CGRect(x: left, y: y, width: length, height: pixel))
            shade.addRect(CGRect(x: left + pixel, y: y + pixel, width: length, height: pixel))
        }
        ctx.fill(shade, with: .color(color("k")))
        ctx.fill(streaks, with: .color(.white.opacity(0.9)))
    }

    // MARK: - Туман

    /// Туман — белая дымка, как нарисованная аэрографом: размытые
    /// полупрозрачные пятна медленно наплывают из-под выреза и расходятся.
    /// Не пикселями: пиксельные полосы туманом не читались.
    private static func drawFog(_ ctx: GraphicsContext, notch: CGRect, size: CGSize, t: TimeInterval) {
        let duration = Scene.fog.duration
        let fade = min(ease(t / 1.4), ease((duration - t) / 1.4))
        guard fade > 0.01 else { return }
        ctx.drawLayer { layer in
            var haze = layer
            // Одно большое мягкое пятно под чёлкой — не облачка по отдельности.
            // Дышит: чуть растёт и опадает, медленно смещается.
            haze.addFilter(.blur(radius: 26))
            let breath = CGFloat(sin(t * 0.9)) * 0.06
            let width = notch.width * (2.0 + breath)
            let height: CGFloat = 70 * (1 + breath)
            // Ниже кромки на полторы высоты пятна: выше дымка липла к чёлке.
            let center = CGPoint(x: notch.midX + CGFloat(sin(t * 0.5)) * 10, y: notch.maxY + 58)
            let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
            haze.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.55 * fade)))
            // Ядро плотнее — чтобы пятно читалось и на светлых обоях.
            let core = rect.insetBy(dx: width * 0.25, dy: height * 0.2)
            haze.fill(Path(ellipseIn: core), with: .color(.white.opacity(0.35 * fade)))
            // К бокам холста дымка растворяется: иначе край окна срезал её
            // прямой линией.
            layer.blendMode = .destinationIn
            layer.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: 0.3),
                    .init(color: .white, location: 0.7),
                    .init(color: .clear, location: 1),
                ]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: 0)
            ))
        }
    }

    // MARK: - Дождь и морось

    enum DropStyle {
        case drizzle, rain, storm

        var count: Int { self == .drizzle ? 90 : self == .rain ? 300 : 360 }
        var length: Int { self == .drizzle ? 2 : 4 }
        var start: CGFloat { self == .drizzle ? 30 : 90 }
        var gravity: CGFloat { self == .drizzle ? 120 : 300 }
        var depth: ClosedRange<CGFloat> { self == .drizzle ? 60...110 : 120...180 }
    }

    private static func drawDrops(_ ctx: GraphicsContext, island: (TimeInterval) -> CGRect, t: TimeInterval, style: DropStyle) {
        let duration = style == .drizzle ? Scene.drizzle.duration : Scene.rain.duration
        // Капли срываются из-под всей кромки выреза, кроме скруглённых углов.
        let inset: CGFloat = 12
        var body = Path(), tip = Path()
        for i in 0..<style.count {
            let born = noise(i, 7) * (duration - 1.6)
            let age = t - born
            guard age >= 0 else { continue }
            let notch = island(born)
            let fall = style.start * CGFloat(age) + style.gravity * CGFloat(age * age) / 2
            let depth = style.depth.lowerBound + CGFloat(noise(i, 8)) * (style.depth.upperBound - style.depth.lowerBound)
            guard fall < depth else { continue }
            // Последняя треть пути — капля тает, иначе обрывается на лету.
            let melt = (fall - depth * 0.66) / (depth * 0.34)
            guard melt <= 0 || noise(i, 10) > Double(melt) else { continue }
            let x = snap(notch.minX + inset + CGFloat(noise(i, 9)) * (notch.width - 2 * inset))
            let y = snap(notch.maxY - pixel + fall)
            body.addRect(CGRect(x: x, y: y, width: pixel, height: CGFloat(style.length - 1) * pixel))
            tip.addRect(CGRect(x: x, y: y + CGFloat(style.length - 1) * pixel, width: pixel, height: pixel))
        }
        ctx.fill(body, with: .color(color("b")))
        ctx.fill(tip, with: .color(color("B")))
    }

    // MARK: - Молния

    private static func drawLightning(_ ctx: GraphicsContext, notch: CGRect, t: TimeInterval) {
        // Две вспышки, каждая мигает дважды — ровная молния читается
        // картинкой, а мигающая — грозой.
        let strikes: [(at: Double, x: CGFloat, flipped: Bool)] = [
            (1.4, notch.minX + 36, false),
            (3.7, notch.maxX - 30, true),
        ]
        for strike in strikes {
            let local = t - strike.at
            let lit = (0..<0.08).contains(local) || (0.13..<0.3).contains(local)
            guard lit else { continue }
            // Вспышка — мягкое свечение под вырезом, иначе молния
            // в два десятка точек читается значком, а не грозой.
            let glow = CGRect(x: strike.x - 90, y: notch.maxY - 40, width: 180, height: 140)
            ctx.fill(Path(ellipseIn: glow), with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.28), .clear]),
                center: CGPoint(x: glow.midX, y: glow.midY), startRadius: 0, endRadius: 90
            ))
            draw(bolt, in: ctx, anchor: CGPoint(x: strike.x, y: notch.maxY + 2 + CGFloat(bolt.height) * pixel),
                 flipped: strike.flipped)
        }
    }

    static let bolt = Sprite([
        "......kkkkk",
        ".....klllk.",
        "....klllk..",
        "...klllk...",
        "..klllkkkkk",
        ".klllllllk.",
        ".kkkklllk..",
        "....klllk..",
        "...klllk...",
        "...kllk....",
        "..kllk.....",
        "..klk......",
        ".klk.......",
        ".kk........",
    ])

    // MARK: - Снег

    /// Снег. `density` — во сколько раз гуще: у снегопада втрое.
    private static func drawSnow(_ ctx: GraphicsContext, island: (TimeInterval) -> CGRect, t: TimeInterval,
                                 density: Int) {
        let duration = Scene.snow.duration
        let inset: CGFloat = 10
        for i in 0..<(46 * density) {
            let born = noise(i, 11) * (duration - 3)
            let age = t - born
            guard age >= 0 else { continue }
            let notch = island(born)
            // Снегопад идёт заметно быстрее: хлопья валят, а не кружат.
            let speed = 22 + CGFloat(noise(i, 12)) * 14 + CGFloat(density - 1) * 22
            let fall = CGFloat(age) * speed
            let depth: CGFloat = 90 + CGFloat(noise(i, 13)) * 60
            guard fall < depth else { continue }
            let sway = CGFloat(sin(age * 2 + noise(i, 14) * 6)) * 6
            let x = notch.minX + inset + CGFloat(noise(i, 15)) * (notch.width - 2 * inset) + sway
            let y = notch.maxY + fall
            let sprite = noise(i, 16) > 0.45 ? flake : speck
            draw(sprite, in: ctx, anchor: CGPoint(x: x, y: y + CGFloat(sprite.height) * pixel), shadow: true)
        }
    }

    /// Вьюга: снег срывается из-под выреза и тут же уносится ветром вбок,
    /// закручиваясь вихрями; поверх — порывы.
    private static func drawBlizzard(_ ctx: GraphicsContext, notch: CGRect, size: CGSize, t: TimeInterval, mirrored: Bool) {
        let duration = Scene.blizzard.duration
        let wind: CGFloat = mirrored ? -1 : 1
        for i in 0..<110 {
            let born = noise(i, 61) * (duration - 2)
            let age = t - born
            guard age >= 0, age < 2.6 else { continue }
            let origin = CGPoint(x: notch.minX + 8 + CGFloat(noise(i, 62)) * (notch.width - 16), y: notch.maxY)
            // Разгоняется ветром, падает медленно.
            let gust = 90 + CGFloat(noise(i, 63)) * 110
            let run = CGFloat(age) * gust + CGFloat(age * age) * 30
            let fall = CGFloat(age) * (16 + CGFloat(noise(i, 64)) * 20)
            // Вихрь: круги поверх полёта, у каждой снежинки свой.
            let radius = 6 + CGFloat(noise(i, 65)) * 12
            let spin = age * (5 + noise(i, 66) * 4) + noise(i, 67) * 6
            let x = origin.x + wind * run + radius * CGFloat(cos(spin))
            let y = origin.y + fall + radius * 0.6 * CGFloat(sin(spin))
            guard x > -10, x < size.width + 10 else { continue }
            let sprite = noise(i, 68) > 0.5 ? flake : speck
            draw(sprite, in: ctx, anchor: CGPoint(x: x, y: y + CGFloat(sprite.height) * pixel), shadow: true)
        }
        var streaks = Path(), shade = Path()
        for i in 0..<12 {
            let start = noise(i, 71) * (duration - 1)
            let travelled = CGFloat(t - start) * (340 + CGFloat(noise(i, 72)) * 140)
            guard travelled > 0, travelled < size.width + 80 else { continue }
            let head = mirrored ? size.width + 40 - travelled : travelled - 40
            let y = snap(notch.maxY - 6 + CGFloat(noise(i, 73)) * 80)
            let length = CGFloat(Int(5 + noise(i, 74) * 7)) * pixel
            let left = snap(mirrored ? head : head - length)
            streaks.addRect(CGRect(x: left, y: y, width: length, height: pixel))
            shade.addRect(CGRect(x: left + pixel, y: y + pixel, width: length, height: pixel))
        }
        ctx.fill(shade, with: .color(color("k")))
        ctx.fill(streaks, with: .color(.white.opacity(0.9)))
    }

    static let flake = Sprite([
        ".W.",
        "WWW",
        ".W.",
    ])

    static let speck = Sprite(["W"])

    // MARK: - Спрайт

    /// Цветной спрайт: `W` белый, `g` светло-серый, `k` тёмная обводка,
    /// `y` жёлтый, `o` оранжевый, `b` и `B` синие, `l` молния, `.` пусто.
    struct Sprite {
        let width: Int
        let height: Int
        let cells: [[Character?]]

        init(_ rows: [String]) {
            let width = rows.map(\.count).max() ?? 0
            self.width = width
            height = rows.count
            cells = rows.map { row in
                let chars = Array(row)
                return (0..<width).map { x in
                    guard x < chars.count, chars[x] != "." else { return nil }
                    return chars[x]
                }
            }
        }
    }

    static func color(_ key: Character) -> Color {
        switch key {
        case "W": return .white
        case "g": return Color(white: 0.8)
        case "k": return .black.opacity(0.45)
        case "y": return Color(red: 1.0, green: 0.83, blue: 0.25)
        case "o": return Color(red: 1.0, green: 0.55, blue: 0.15)
        case "b": return Color(red: 0.45, green: 0.78, blue: 1.0)
        case "B": return Color(red: 0.2, green: 0.5, blue: 0.95)
        case "l": return Color(red: 1.0, green: 0.93, blue: 0.4)
        // Праздничные сценки кота.
        case "K": return Color(white: 0.04)
        case "r": return Color(red: 0.9, green: 0.14, blue: 0.2)
        case "R": return Color(red: 0.58, green: 0.07, blue: 0.1)
        case "G": return Color(red: 0.22, green: 0.66, blue: 0.26)
        case "e": return Color(red: 0.42, green: 0.5, blue: 0.22)
        case "n": return Color(red: 0.24, green: 0.31, blue: 0.13)
        case "d": return Color(red: 1.0, green: 0.8, blue: 0.24)
        case "D": return Color(red: 0.78, green: 0.5, blue: 0.08)
        case "p": return Color(red: 1.0, green: 0.52, blue: 0.76)
        case "v": return Color(red: 0.62, green: 0.36, blue: 0.92)
        // Сценки-напоминания кота: чай в кружке.
        case "t": return Color(red: 0.62, green: 0.36, blue: 0.14)
        default: return .clear
        }
    }

    /// `anchor` — точка под серединой нижнего ряда, как у `CritterArt.draw`.
    /// `shadow` — тень на полпикселя вправо-вниз, чтобы белое читалось
    /// на светлых обоях.
    static func draw(_ sprite: Sprite, in ctx: GraphicsContext, anchor: CGPoint, flipped: Bool = false, shadow: Bool = false) {
        let originX = snap(anchor.x) - CGFloat(sprite.width / 2) * pixel
        let originY = snap(anchor.y) - CGFloat(sprite.height) * pixel
        var paths: [Character: Path] = [:]
        var shade = Path()
        for y in 0..<sprite.height {
            for x in 0..<sprite.width {
                guard let key = sprite.cells[y][x] else { continue }
                let column = flipped ? sprite.width - 1 - x : x
                let rect = CGRect(x: originX + CGFloat(column) * pixel, y: originY + CGFloat(y) * pixel,
                                  width: pixel, height: pixel)
                paths[key, default: Path()].addRect(rect)
                if shadow { shade.addRect(rect.offsetBy(dx: pixel / 2, dy: pixel / 2)) }
            }
        }
        if shadow { ctx.fill(shade, with: .color(.black.opacity(0.35))) }
        // Обводка первой: цветное ложится поверх.
        if let outline = paths.removeValue(forKey: "k") {
            ctx.fill(outline, with: .color(color("k")))
        }
        for (key, path) in paths {
            ctx.fill(path, with: .color(color(key)))
        }
    }

    /// Спрайт, повёрнутый на угол `angle` (радианы, по часовой на экране)
    /// вокруг своей середины `center`. Пиксели остаются на сетке: для каждой
    /// клетки экрана берётся клетка спрайта, из которой она пришла, —
    /// так в повёрнутом рисунке не появляется дыр.
    static func drawRotated(_ sprite: Sprite, in ctx: GraphicsContext, center: CGPoint, angle: Double, flipped: Bool = false) {
        let cosA = cos(angle), sinA = sin(angle)
        let halfW = Double(sprite.width) / 2, halfH = Double(sprite.height) / 2
        let reach = Int((hypot(halfW, halfH)).rounded(.up)) + 1
        let originX = snap(center.x), originY = snap(center.y)
        var paths: [Character: Path] = [:]
        for dy in -reach...reach {
            for dx in -reach...reach {
                let x = Double(dx) + 0.5, y = Double(dy) + 0.5
                // Обратный поворот: откуда в спрайте пришла эта клетка.
                let sx = x * cosA + y * sinA + halfW
                let sy = -x * sinA + y * cosA + halfH
                guard sx >= 0, sy >= 0 else { continue }
                var column = Int(sx)
                let row = Int(sy)
                guard column < sprite.width, row < sprite.height else { continue }
                if flipped { column = sprite.width - 1 - column }
                guard let key = sprite.cells[row][column] else { continue }
                let rect = CGRect(x: originX + CGFloat(dx) * pixel, y: originY + CGFloat(dy) * pixel,
                                  width: pixel, height: pixel)
                paths[key, default: Path()].addRect(rect)
            }
        }
        if let outline = paths.removeValue(forKey: "k") {
            ctx.fill(outline, with: .color(color("k")))
        }
        for (key, path) in paths {
            ctx.fill(path, with: .color(color(key)))
        }
    }

    // MARK: - Общее

    /// Случайное, но постоянное число от 0 до 1 для частицы `index`.
    static func noise(_ index: Int, _ salt: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: (index &* 73_856_093) ^ (salt &* 19_349_663)) &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x % 10_000) / 10_000
    }

    /// Прилипнуть к сетке пикселей: дробный сдвиг размазал бы пиксель в муть.
    static func snap(_ value: CGFloat) -> CGFloat {
        (value / pixel).rounded() * pixel
    }

    static func ease(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return c * c * (3 - 2 * c)
    }
}
