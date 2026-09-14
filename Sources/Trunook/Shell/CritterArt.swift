import SwiftUI

/// Рисунок кота в пиксельном стиле: только чёрный и белый.
///
/// Кот — чёрный силуэт из квадратных пикселей, без обводки: белая обводка
/// делала его наклейкой. Глаза — белые
/// чёрточки, у ушей белое нутро.
///
/// Позы котика нарисованы спрайтами — строками, где `#` чёрный пиксель,
/// `W` белый, `.` пусто. Обводку, если понадобится, спрайт умеет посчитать
/// сам (`outline`), но по умолчанию её нет. Хвост не спрайт —
/// его кривая растрируется в сетку, и он качается без ручных кадров.
///
/// Отдельно от `CritterView` и без зависимостей от приложения: рисунок
/// подбирается глазами по листу кадров, `make critter`.
enum CritterArt {
    /// Сторона пикселя в точках. Два — на Retina это четыре настоящих
    /// пикселя: крупно, но котик ещё помещается в полосу меню.
    static let pixel: CGFloat = 2

    // MARK: - Спрайт

    struct Sprite {
        let width: Int
        let height: Int
        /// `true` — чёрный, `false` — белый, `nil` — пусто.
        let cells: [[Bool?]]

        init(_ rows: [String]) {
            let width = rows.map(\.count).max() ?? 0
            self.width = width
            height = rows.count
            cells = rows.map { row in
                let chars = Array(row)
                return (0..<width).map { x -> Bool? in
                    guard x < chars.count else { return nil }
                    switch chars[x] {
                    case "#": return true
                    case "W": return false
                    default: return nil
                    }
                }
            }
        }

        init(width: Int, height: Int, cells: [[Bool?]]) {
            self.width = width
            self.height = height
            self.cells = cells
        }

        /// Обводка: пустые клетки, соседние с чёрными по восьми направлениям.
        var outline: [(Int, Int)] {
            var result: [(Int, Int)] = []
            for y in -1...height {
                for x in -1...width {
                    if cell(x, y) != nil { continue }
                    var touches = false
                    for dy in -1...1 {
                        for dx in -1...1 where cell(x + dx, y + dy) == true { touches = true }
                    }
                    if touches { result.append((x, y)) }
                }
            }
            return result
        }

        func cell(_ x: Int, _ y: Int) -> Bool? {
            guard y >= 0, y < height, x >= 0, x < width else { return nil }
            return cells[y][x]
        }
    }

    /// Нарисовать спрайт. `anchor` — точка на экране под серединой нижнего
    /// ряда; `flipped` — смотрит влево. Координаты прилипают к сетке пикселей:
    /// дробный сдвиг размазал бы пиксели в муть.
    static func draw(_ sprite: Sprite, in ctx: GraphicsContext, anchor: CGPoint, flipped: Bool = false, outlined: Bool = false) {
        let p = pixel
        let originX = (anchor.x / p).rounded() * p - CGFloat(sprite.width / 2) * p
        let originY = (anchor.y / p).rounded() * p - CGFloat(sprite.height) * p
        func rect(_ x: Int, _ y: Int) -> CGRect {
            let column = flipped ? sprite.width - 1 - x : x
            return CGRect(x: originX + CGFloat(column) * p, y: originY + CGFloat(y) * p, width: p, height: p)
        }
        var white = Path(), black = Path()
        if outlined {
            for (x, y) in sprite.outline { white.addRect(rect(x, y)) }
        }
        for y in 0..<sprite.height {
            for x in 0..<sprite.width {
                switch sprite.cells[y][x] {
                case true?: black.addRect(rect(x, y))
                case false?: white.addRect(rect(x, y))
                case nil: break
                }
            }
        }
        ctx.fill(black, with: .color(.black))
        ctx.fill(white, with: .color(.white))
    }

    // MARK: - Мордочка из-под чёлки

    /// Котик свисает из-под нижней кромки выреза: две лапы держатся за край,
    /// голова с ушами целиком ниже кромки — без ушей мордочка не читалась
    /// котом. Лапы короткие и прямые: расставленные в стороны, они читались
    /// крыльями летучей мыши. Верх спрайта прижат к кромке.
    ///
    /// Не глаза внутри чёлки: в месте выреза у экрана нет пикселей, и всё,
    /// что рисуется там, закрыто железом. На снимке окна глаза были, на экране
    /// их не видел никто.
    ///
    /// `open` — 2 открыты, 1 прищур, 0 закрыты; `look` — сдвиг глаз в пикселях,
    /// от −2 до 2, `down` — курсор далеко внизу: котик смотрит туда, где он.
    static func peek(open: Int, look: Int, down: Bool = false) -> Sprite {
        // Левая половина; правая — её зеркало, мордочка симметрична.
        let left = [
            "....##.......",
            "....##.......",
            "....##..#....",
            "....##..##...",
            "....##..###..",
            "....#########",
            "....#########",
            ".....########",
            ".....########",
            ".....########",
            "......#######",
            "........#####",
        ]
        let rows = left.map { $0 + String($0.reversed()) }
        var cells = Sprite(rows).cells
        // Глаза косятся в сторону курсора на два пикселя, а если курсор
        // далеко внизу — опускаются на ряд.
        let shift = max(-2, min(2, look))
        let top = down ? 8 : 7
        let eyeRows = open >= 2 ? [top, top + 1] : open == 1 ? [top + 1] : []
        for column in [9, 16] {
            for row in eyeRows { cells[row][column + shift] = false }
        }
        return Sprite(width: 26, height: rows.count, cells: cells)
    }

    // MARK: - Хвост

    /// Хвост, свисающий из-под кромки: кривая растрируется в сетку пикселей.
    /// `length` — в пикселях. `rootColumn` — столбец спрайта, где основание.
    static func hangingTail(time t: Double, length: Int = 30) -> (sprite: Sprite, rootColumn: Int) {
        // Кадры ступенями, по восемь в секунду: плавная кривая на крупной
        // сетке дрожала бы пикселями на каждом кадре экрана.
        let t = (t * 8).rounded(.down) / 8
        var points: [(CGFloat, CGFloat)] = []
        var x: CGFloat = 0, y: CGFloat = 0
        let sway = CGFloat(sin(t * 2.2))
        let steps = length * 3
        for i in 0..<steps {
            let s = CGFloat(i) / CGFloat(steps)
            let angle = CGFloat.pi / 2 + sway * 0.35 * s
                + CGFloat(sin(t * 2.2 - Double(s) * 3)) * 0.8 * s
                - (sway >= 0 ? 1 : -1) * smooth(s, from: 0.72, to: 1) * 0.8
            x += cos(angle) / 3
            y += sin(angle) / 3
            points.append((x, y))
        }
        let minX = Int(floor(points.map(\.0).min() ?? 0)) - 2
        let maxX = Int(ceil(points.map(\.0).max() ?? 0)) + 2
        let height = Int(ceil(points.map(\.1).max() ?? 0)) + 2
        let width = maxX - minX + 1
        var cells = Array(repeating: Array(repeating: Bool?.none, count: width), count: height)
        for (i, point) in points.enumerated() {
            let s = CGFloat(i) / CGFloat(points.count)
            // Три пикселя толщиной, к кончику — два.
            let radius: CGFloat = s < 0.8 ? 1.6 : 1.1
            let cx = point.0 - CGFloat(minX), cy = point.1
            for gy in Int(cy - radius - 1)...Int(cy + radius + 1) {
                for gx in Int(cx - radius - 1)...Int(cx + radius + 1) {
                    guard gy >= 0, gy < height, gx >= 0, gx < width else { continue }
                    let dx = CGFloat(gx) + 0.5 - cx, dy = CGFloat(gy) + 0.5 - cy
                    if dx * dx + dy * dy <= radius * radius { cells[gy][gx] = true }
                }
            }
        }
        return (Sprite(width: width, height: height, cells: cells), -minX)
    }

    // MARK: - Котик

    /// Бежит вправо — та же буханка на коротких лапках, два кадра. Худой
    /// бегущий котик рядом с круглой лежащей буханкой читался другим зверем.
    static let run: [Sprite] = [
        Sprite(loafRows(eyes: [7, 8], tail: 0) + [
            "....##..##....##..##..",
            "...##....##..##....##.",
        ]),
        Sprite(loafRows(eyes: [7, 8], tail: 1) + [
            ".....##.##.....##.##..",
            ".....##.##.....##.##..",
        ]),
    ]

    /// Лежит буханкой, смотрит вправо, хвост крючком. Второй кадр —
    /// глаза прикрыты: буханка медленно моргает.
    static let loaf: [Sprite] = [
        Sprite(loafRows(eyes: [7, 8])),
        Sprite(loafRows(eyes: [8])),
    ]

    /// Буханка. `tail` — 0 хвост крючком вверх, 1 — опущен: на бегу хвост
    /// подпрыгивает вместе с шагом.
    private static func loafRows(eyes: [Int], tail: Int = 0) -> [String] {
        var rows = [
            ".............#.....#..",
            "............##....##..",
            "...........#W#...#W#..",
            "..........###########.",
            "..........############",
            "#.......##############",
            "##.....###############",
            ".##...################",
            "..##.#################",
            "...###################",
            "...##################.",
            "....################..",
            ".....##############...",
        ]
        if tail == 1 {
            rows[5] = "........##############"
            rows[6] = ".......###############"
            rows[7] = "......################"
            rows[8] = "#....#################"
            rows[9] = "######################"
        }
        for row in eyes {
            var chars = Array(rows[row])
            chars[12] = "W"
            chars[18] = "W"
            rows[row] = String(chars)
        }
        return rows
    }

    // MARK: - Уши из-за края чёлки

    /// Голова котика, спрятавшегося за боковым краем выреза: снаружи видны
    /// ухо, глаз и половина морды. `twitch` — ухо дёрнулось, `blink` — глаза
    /// прикрыты. Дёргается правое ухо; у левого края спрайт отражается.
    static func ears(twitch: Bool, blink: Bool) -> Sprite {
        let left = [
            "..#....",
            "..##...",
            "..#W#..",
            ".######",
            "#######",
            "#######",
            "#######",
            "#######",
            "#######",
            "#######",
            ".######",
            "..#####",
        ]
        var cells = Sprite(left.map { $0 + String($0.reversed()) }).cells
        if twitch {
            // Кончик уха отгибается наружу.
            cells[0][11] = nil
            cells[1][11] = nil
            cells[1][12] = true
            cells[0][13] = true
        }
        for column in [3, 10] {
            if !blink { cells[6][column] = false }
            cells[7][column] = false
        }
        return Sprite(width: 14, height: left.count, cells: cells)
    }

    // MARK: - Лапа из-под чёлки

    /// Лапа, свисающая из-под кромки: сверху — рука, снизу — ступня
    /// с пальцами. `lean` — от −2 до 2, куда отмахнулась.
    static func paw(lean: Int) -> Sprite {
        let width = 11, height = 12
        var cells = Array(repeating: Array(repeating: Bool?.none, count: width), count: height)
        func fill(_ row: Int, _ from: Int, _ to: Int) {
            for x in from...to where x >= 0 && x < width { cells[row][x] = true }
        }
        let lean = max(-2, min(2, lean))
        for row in 0..<height {
            // Рука отгибается от плеча: чем ниже, тем дальше в сторону взмаха.
            let c = 5 + Int((Double(lean) * Double(row) / Double(height - 1)).rounded())
            switch row {
            case 0...5: fill(row, c - 1, c + 1)
            case 6...7: fill(row, c - 2, c + 2)
            case 8: fill(row, c - 2, c + 2)
            case 9...10: fill(row, c - 3, c + 3)
            default:
                // Пальцы — три бугорка.
                for x in [c - 2, c, c + 2] { fill(row, x, x) }
            }
        }
        return Sprite(width: width, height: height, cells: cells)
    }

    // MARK: - Сон

    /// Спящая буханка: глаза — две белые чёрточки, два кадра дыхания.
    static let sleeping: [Sprite] = [
        Sprite(sleepRows(inhale: false)),
        Sprite(sleepRows(inhale: true)),
    ]

    private static func sleepRows(inhale: Bool) -> [String] {
        var rows = loafRows(eyes: [])
        for column in [11, 12, 17, 18] {
            var chars = Array(rows[8])
            chars[column] = "W"
            rows[8] = String(chars)
        }
        if inhale {
            // На вдохе спина поднимается на пиксель.
            rows[4] = ".........#############"
            rows[5] = "#......###############"
        }
        return rows
    }

    /// Буквы сна: маленькая и большая.
    static let z: [Sprite] = [
        Sprite(["###", "..#", ".#.", "###"]),
        Sprite(["#####", "...#.", "..#..", ".#...", "#####"]),
    ]

    // MARK: - Зевок

    /// Мордочка из-под чёлки, зевающая. `stage` — 0 рот закрыт, 1 приоткрыт,
    /// 2 зевает во весь рот.
    ///
    /// Во весь рот — не белый кружок: одинокий кружок на чёрной морде
    /// не читался ртом. Глаза зажмурены галочками, рот широкий, с чёрным
    /// язычком внизу, челюсть опущена на три ряда.
    static func yawn(stage: Int, look: Int) -> Sprite {
        let base = peek(open: stage == 0 ? 2 : stage == 1 ? 1 : 0, look: look)
        var cells = base.cells
        let width = base.width
        switch stage {
        case 2:
            // Челюсть опускается: подбородок на три ряда ниже.
            for range in [8...17, 9...16, 11...14] {
                var chin = Array(repeating: Bool?.none, count: width)
                for x in range { chin[x] = true }
                cells.append(chin)
            }
            // Зажмуренные глаза — галочки вершиной вверх.
            for (row, column) in [(8, 8), (7, 9), (8, 10), (8, 15), (7, 16), (8, 17)] {
                cells[row][column] = false
            }
            // Рот: широкий, скруглённый, с язычком.
            let mouth: [(Int, ClosedRange<Int>)] = [
                (10, 12...13), (11, 11...14), (12, 11...14), (13, 12...13),
            ]
            for (row, range) in mouth {
                for x in range { cells[row][x] = false }
            }
            for x in 12...13 { cells[13][x] = true }
        case 1:
            // Приоткрытый рот — маленький овал.
            for (row, range) in [(9, 12...13), (10, 11...14), (11, 12...13)] {
                for x in range { cells[row][x] = false }
            }
        default:
            break
        }
        return Sprite(width: width, height: cells.count, cells: cells)
    }

    // MARK: - Клубок

    /// Клубок с нитками. Два кадра — клубок катится.
    static func yarn(frame: Int) -> Sprite {
        var cells = Sprite([
            "..###..",
            ".#####.",
            "#######",
            "#######",
            "#######",
            ".#####.",
            "..###..",
        ]).cells
        let strands: [(Int, Int)] = frame % 2 == 0
            ? [(1, 4), (2, 3), (3, 2), (4, 1), (3, 5), (4, 4), (5, 3)]
            : [(1, 2), (2, 3), (3, 4), (4, 5), (3, 1), (4, 2), (5, 3)]
        for (row, column) in strands { cells[row][column] = false }
        return Sprite(width: 7, height: 7, cells: cells)
    }

    // MARK: - Злой котик

    /// Сидит лицом к зрителю, брови домиком, грозит поднятым кулаком.
    /// Два кадра: кулак вверху и кулак ниже — трясёт.
    static let angry: [Sprite] = [
        Sprite(angryRows(fistHigh: true)),
        Sprite(angryRows(fistHigh: false)),
    ]

    private static func angryRows(fistHigh: Bool) -> [String] {
        let head = [
            "..#.....#.......",
            "..##...##.......",
            "..#######.......",
            ".#########......",
            ".#W#####W#......",
            ".##W###W##......",
            ".#########......",
            "..#######.......",
        ]
        let body = [
            ".###########....",
            "############....",
            "###########.....",
            "###########.....",
            ".#########......",
            "..##....##......",
        ]
        // Рука с кулаком — справа от головы, поверх пустых столбцов.
        // Рука с кулаком — справа от головы: толстая, кулак круглый.
        let arm: [(Int, String)] = fistHigh
            ? [(0, ".##."), (1, "####"), (2, "####"), (3, ".##."), (4, "..#."), (5, ".##."), (6, "##.."), (7, "#...")]
            : [(2, ".##."), (3, "####"), (4, "####"), (5, ".##."), (6, "##.."), (7, "#...")]
        var rows = [String](repeating: "................", count: 1) + head + body
        for (row, piece) in arm {
            var chars = Array(rows[row + 1])
            for (i, c) in piece.enumerated() where c == "#" {
                chars[10 + i] = "#"
            }
            rows[row + 1] = String(chars)
        }
        // Плечо: рука сходится с телом.
        var shoulder = Array(rows[8])
        shoulder[10] = "#"
        rows[8] = String(shoulder)
        return rows
    }

    /// Знак злости — вздувшаяся жилка, как в комиксах.
    static let anger = Sprite([
        ".#.#.",
        "##.##",
        ".....",
        "##.##",
        ".#.#.",
    ])

    static func smooth(_ x: CGFloat, from a: CGFloat, to b: CGFloat) -> CGFloat {
        let v = min(1, max(0, (x - a) / (b - a)))
        return v * v * (3 - 2 * v)
    }
}
