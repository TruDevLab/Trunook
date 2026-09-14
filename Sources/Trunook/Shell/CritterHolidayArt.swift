import SwiftUI

/// Рисунки праздничных сценок кота. Сам котик — всё та же буханка
/// из `CritterArt`; здесь то, что появляется рядом с ним: шапка и шарф,
/// сугробы, котята, букет, танк, яйцо и кролик, тыква, дракон, ракета.
///
/// Цветное — спрайтами `WeatherArt.Sprite`, той же сеткой в два пикселя:
/// у них уже есть палитра по буквам и обводка `k`.
extension CritterArt {
    typealias Colored = WeatherArt.Sprite

    // MARK: - Новый год

    /// Красная шапка с белой опушкой и помпоном, свисающим назад, к хвосту.
    /// Клетки — на сетке буханки, первый столбец девятый, первый ряд — третий
    /// над макушкой (`santaHatColumn`, `santaHatRow`).
    static let santaHat = Colored([
        "W...........",
        "Wrr.........",
        "..rrrr......",
        "...rrrrrr...",
        "...rrrrrrrr.",
        "..rrrrrrrrrr",
        "..WWWWWWWWWW",
    ])
    static let santaHatColumn = 9
    static let santaHatRow = -3

    /// Белая борода Деда Мороза: от рта клином вниз, ниже лап. Тёмная кромка
    /// по краям — на светлых обоях белое иначе пропадает.
    static let beard = Colored([
        "kWWWWWWWWWk",
        "kWWWWWWWWWk",
        ".kWWWWWWWk.",
        "..kWWWWWk..",
        "...kWWWk...",
        "....kWk....",
    ])
    static let beardColumn = 11
    static let beardRow = 9

    /// Белый котик того же размера, что чёрный: весь белый, без обводки,
    /// чёрные только глаза и нутро ушей — без них белое пятно котом
    /// не читается. Обводка сначала шла снаружи и делала его толще,
    /// потом по кромке — вышло лучше вовсе без неё.
    static func whiteCat(_ sprite: Sprite) -> Sprite {
        let cells = sprite.cells.map { row in row.map { cell in cell.map { !$0 } } }
        return Sprite(width: sprite.width, height: sprite.height, cells: cells)
    }

    /// Сугроб: белый холмик с тёмной кромкой сверху, чтобы читался и на
    /// светлых обоях. `growth` от 0 до 1 — насколько намело.
    static func drift(growth: Double) -> Colored {
        let width = 24, height = 7
        var rows = Array(repeating: Array(repeating: Character("."), count: width), count: height)
        let peak = Double(height - 1) * min(1, max(0, growth))
        for x in 0..<width {
            let u = (Double(x) + 0.5 - Double(width) / 2) / (Double(width) / 2)
            let tall = Int((peak * (1 - u * u).squareRoot()).rounded())
            guard tall > 0 else { continue }
            let top = height - tall
            rows[top][x] = "k"
            // Низ холмика в тени — светло-серый: целиком белый сугроб
            // на светлых обоях читался одной кромкой.
            for y in (top + 1)..<height { rows[y][x] = y >= height - 2 ? "g" : "W" }
        }
        return Colored(rows.map { String($0) })
    }

    // MARK: - День защиты детей

    /// Котёнок — маленькая буханка, смотрит вправо. Два кадра бега и сидя.
    static let kitten: [Sprite] = [
        Sprite(kittenRows + ["...#.#.#.#."]),
        Sprite(kittenRows + ["....#.#..#."]),
        Sprite(kittenRows),
    ]

    private static var kittenRows: [String] {
        [
            "......#..#.",
            ".....######",
            "#....#W##W#",
            ".#..#######",
            "..#########",
            "..#########",
        ]
    }

    // MARK: - 8 Марта

    /// Букет в обёртке, перевязанной лентой: бумага веером за цветами,
    /// в середине перехвачена розовой лентой с бантом, ниже чуть расходится,
    /// из-под неё — стебли. Три крупных цветка с жёлтыми серединками и листья.
    /// Кулёк конусом читался рожком мороженого.
    static let bouquet: Colored = {
        let width = 15, height = 19
        var rows = Array(repeating: Array(repeating: Character("."), count: width), count: height)
        func paper(_ y: Int, inset: Int) {
            let left = inset, right = width - 1 - inset
            for x in left...right { rows[y][x] = (x == left || x == right) ? "k" : "W" }
        }
        // Бумага выше ленты — сужается к перехвату.
        for y in 6...11 { paper(y, inset: y - 6) }
        // Ниже ленты — снова расходится.
        for (y, inset) in [(13, 5), (14, 5), (15, 4), (16, 4), (17, 3)] { paper(y, inset: inset) }
        for x in 3...11 { rows[17][x] = x == 3 || x == 11 ? "k" : rows[17][x] }
        for x in 6...8 { rows[18][x] = "G" }
        // Лента и бант.
        for x in 2...12 { rows[12][x] = "p" }
        rows[12][7] = "R"
        for (x, y) in [(2, 11), (3, 11), (11, 11), (12, 11), (2, 13), (3, 13), (11, 13), (12, 13),
                       (6, 14), (5, 15), (8, 14), (9, 15)] {
            rows[y][x] = "p"
        }
        // Цветы — поверх бумаги.
        func blob(_ cx: Int, _ cy: Int, _ color: Character) {
            for y in (cy - 2)...(cy + 2) {
                for x in (cx - 2)...(cx + 2) where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= 5 {
                    rows[y][x] = color
                }
            }
            rows[cy][cx] = "y"
        }
        blob(7, 2, "v")
        blob(3, 5, "r")
        blob(11, 5, "p")
        blob(7, 6, "r")
        for (x, y) in [(0, 6), (1, 7), (14, 6), (13, 7)] { rows[y][x] = "G" }
        return Colored(rows.map { String($0) })
    }()

    // MARK: - 23 Февраля

    /// Танк, ствол вправо. `frame` двигает катки — едет.
    static func tank(frame: Int) -> Colored {
        let wheels = frame % 2 == 0 ? "KWKKWKKWKKWKKWKKWKKWKKWKKK" : "KKWKKWKKWKKWKKWKKWKKWKKWKK"
        return Colored([
            ".........nnnnnnn..............",
            "........neeeeeeennnnnnnnnnnnnn",
            "........eeeeeeee..............",
            "..eeeeeeeeeereeeeeeeeeee......",
            ".eeeeeeeeeeeeeeeeeeeeeeee.....",
            "KKKKKKKKKKKKKKKKKKKKKKKKKK....",
            wheels + "....",
            ".KKKKKKKKKKKKKKKKKKKKKKKK.....",
        ])
    }

    /// Вспышка выстрела у дула.
    static let muzzleFlash = Colored([
        ".y.o",
        "yyyy",
        "oyy.",
        ".o.y",
    ])

    // MARK: - Пасха

    /// Пасхальное яйцо в полоску. `cracked` — по поясу бежит трещина.
    static func egg(cracked: Bool = false) -> Colored {
        var rows = [
            "...kkk...",
            "..kpppk..",
            ".kpppppk.",
            ".kyWyWyk.",
            "kbbbbbbbk",
            "kbbbbbbbk",
            "kyWyWyWyk",
            "kvvvvvvvk",
            ".kvvvvvk.",
            "..kpppk..",
            "...kkk...",
        ].map { Array($0) }
        if cracked {
            for (x, y) in [(1, 5), (2, 4), (3, 5), (4, 4), (5, 5), (6, 4), (7, 5)] { rows[y][x] = "K" }
        }
        return Colored(rows.map { String($0) })
    }

    /// Верх скорлупы — отлетает, низ — остаётся, в нём цыплёнок.
    static let eggTop = Colored([
        "...kkk...",
        "..kpppk..",
        ".kpppppk.",
        ".kyWyWyk.",
        "kbKbKbKbk",
    ])
    static let eggBottom = Colored([
        "kKbKbKbKk",
        "kbbbbbbbk",
        "kyWyWyWyk",
        "kvvvvvvvk",
        ".kvvvvvk.",
        "..kpppk..",
        "...kkk...",
    ])

    /// Цыплёнок, клювом вправо. `frame` — лапки на бегу.
    static func chick(frame: Int) -> Colored {
        Colored([
            "..yyy...",
            ".yyyKy..",
            ".yyyyyoo",
            "yyyyyy..",
            "yyyyyy..",
            ".yyyy...",
            frame % 2 == 0 ? "..o.o..." : ".o...o..",
        ])
    }

    /// Белый кролик, мордочкой вправо: розовые уши и нос, чёрный глаз,
    /// тёмная обводка — на светлых обоях белый иначе пропал бы.
    static let rabbit = Colored([
        "...kk.kk....",
        "..kWpkWpk...",
        "..kWpkWpk...",
        "..kWWkWWk...",
        ".kWWWWWWWk..",
        "kWWWWWWKWWk.",
        "kWWWWWWWWWpk",
        ".kWWWWWWWWk.",
        "kWWWWWWWWWk.",
        "kWWWWWWWWWk.",
        ".kWWkkkWWk..",
        "..kk...kk...",
    ])

    // MARK: - Хэллоуин

    /// Призрак: белый, с чёрными глазами и волнистым подолом; рисуется
    /// полупрозрачным. `frame` — подол колышется.
    static func ghost(frame: Int) -> Colored {
        Colored([
            "..kkkkk..",
            ".kWWWWWk.",
            "kWWWWWWWk",
            "kWKWWWKWk",
            "kWKWWWKWk",
            "kWWWWWWWk",
            "kWWWKWWWk",
            "kWWWWWWWk",
            frame % 2 == 0 ? "kWWkWWkWk" : "kWkWWkWWk",
            frame % 2 == 0 ? ".k..k..k." : "..k..k..k",
        ])
    }

    /// Восклицательный знак к «BOOO».
    static let letterBang = Colored([".oo.", ".oo.", ".oo.", "....", ".oo."])

    /// Тыква на голове буханки, резной рожицей. `open` — рот раскрыт: говорит.
    static func pumpkin(open: Bool) -> Colored {
        var rows = [
            "......nn.....",
            ".....nn......",
            "..ooooooooo..",
            ".ooDooooDooo.",
            "ooooooooooooo",
            "ooooyooooyooo",
            "oooyyoooyyooo",
            "ooDooooooDooo",
            "ooyoyoyoyoyoo",
            "oooyyyyyyyooo",
            ".ooooooooooo.",
        ]
        if open {
            rows[8] = "ooyyyyyyyyyoo"
            rows[9] = "ooyyyyyyyyyoo"
            rows[10] = ".ooyyyyyyyoo."
        }
        return Colored(rows)
    }
    static let pumpkinColumn = 9
    static let pumpkinRow = -2

    /// Буквы «BOOO».
    static let letterB = Colored(["oooo.", "o...o", "oooo.", "o...o", "oooo."])
    static let letterO = Colored([".ooo.", "o...o", "o...o", "o...o", ".ooo."])

    // MARK: - Китайский Новый год

    /// Голова дракона, мордой вправо: золотая, с красной гривой и рогами.
    static let dragonHead = Colored([
        "...rr......rr.....",
        "..rddr....rddr....",
        "..rdddrrrrdddr....",
        ".rdddddddddddddd..",
        "rrddKKdddddddddddW",
        ".rdddddddddddddddW",
        "..dddDDDDDDDDddd..",
        "...ddddddrrrrrr...",
        "....dDDd....rr....",
        ".....dd.......r...",
        "......d...........",
    ])

    /// Звено тела: золотое, с красным гребнем сверху и тёмным брюхом.
    static let dragonSegment = Colored([
        "..rrr..",
        ".ddddd.",
        "ddddddd",
        "ddddddd",
        "dDDDDDd",
        ".DDDDD.",
        "..DDD..",
    ])

    static let dragonTail = Colored([
        ".r.",
        "ddd",
        "dDd",
        ".D.",
    ])

    // MARK: - День космонавтики

    /// Ракета носом вправо, а на ней верхом буханка. Одним спрайтом —
    /// он целиком поворачивается на петле. `frame` — пламя из сопла.
    static func rocket(frame: Int) -> Colored {
        let width = 30
        var rows = Array(repeating: Array(repeating: Character("."), count: width), count: 19)
        // Котик: чёрное — чёрным, глаза и нутро ушей — белым.
        let cat = loaf[0]
        for y in 0..<cat.height {
            for x in 0..<cat.width {
                guard let black = cat.cells[y][x] else { continue }
                rows[y][x + 5] = black ? "K" : "W"
            }
        }
        let body = [
            "....rr........................",
            "...rrrWWWWWWWWWWWWWWWWWWr.....",
            "..rrWWWWWWWWWWbbbWWWWWWWWrr...",
            "..WWWWWWWWWWWWbBbWWWWWWWWrrr..",
            "..rrWWWWWWWWWWbbbWWWWWWWWrr...",
            "...rrrWWWWWWWWWWWWWWWWWWr.....",
            "....rr........................",
        ]
        for (i, line) in body.enumerated() {
            for (x, c) in line.enumerated() where c != "." { rows[11 + i][x] = c }
        }
        let flame = frame % 2 == 0
            ? [(13, 1, "o"), (14, 0, "y"), (14, 1, "y"), (15, 1, "o"), (14, 2, "o")]
            : [(13, 0, "y"), (14, 0, "o"), (14, 1, "y"), (15, 0, "y"), (13, 1, "o")]
        for (y, x, c) in flame { rows[y][x] = Character(c) }
        // Обводка вокруг белого, чтобы ракета читалась на светлых обоях.
        var outlined = rows
        for y in 0..<rows.count {
            for x in 0..<width where rows[y][x] == "." {
                var touches = false
                for (dx, dy) in [(0, 1), (1, 0), (0, -1), (-1, 0)] {
                    let nx = x + dx, ny = y + dy
                    guard ny >= 0, ny < rows.count, nx >= 0, nx < width else { continue }
                    if rows[ny][nx] == "W" { touches = true }
                }
                if touches { outlined[y][x] = "k" }
            }
        }
        return Colored(outlined.map { String($0) })
    }
}
