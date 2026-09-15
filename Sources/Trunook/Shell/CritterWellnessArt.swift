import SwiftUI

/// Рисунки сценок-напоминаний: перерыв, вода, разминка. Сам котик — всё та же
/// буханка из `CritterArt`; здесь то, что рядом с ним: кружка с молоком,
/// стакан с трубочкой, повязка на лбу, капли пота и счёт, — и одна поза
/// самого котика, потягушка.
///
/// Цветное — спрайтами `WeatherArt.Sprite`, сеткой в два пикселя, как
/// у праздничных сценок.
extension CritterArt {
    // MARK: - Перерыв

    /// Кружка с молоком в трёх положениях: стоит, падает, лежит. Голубая,
    /// а не белая: молоко белое, и в белой кружке его было бы не видно.
    /// Ручка — с дальней от котика стороны, горлышко падает к нему:
    /// котик цепляет кружку лапой и роняет на себя, как и положено коту.
    /// Нарисованы для котика слева; справа отражаются.
    static let milkMug: [Colored] = [
        Colored([
            "kkkkkkk..",
            "kWWWWWk..",
            "kbbbbbkkk",
            "kbbbbbk.k",
            "kbbbbbkkk",
            "kbbbbbk..",
            ".kkkkk...",
        ]),
        Colored([
            "..kkk....",
            ".kWWbk...",
            "kWWbbbk..",
            "kWbbbbbk.",
            ".kbbbbbkk",
            "..kbbbk.k",
            "...kkk.k.",
        ]),
        Colored([
            "...kkk...",
            "...k.k...",
            "kkkkkkkk.",
            "WWbbbbbk.",
            "WWbbbbbk.",
            "WWbbbbbk.",
            "kkkkkkkk.",
        ]),
    ]

    static let milkColor = Color.white
    static let tongueColor = Color(red: 1.0, green: 0.5, blue: 0.62)

    // MARK: - Вода

    /// Стакан воды. `level` — сколько рядов воды осталось, от 0 до 5:
    /// котик пьёт, и вода убывает ступенями.
    static func waterGlass(level: Int) -> Colored {
        let inner = 5
        var rows = ["k....k"]
        for row in 0..<inner {
            let filled = row >= inner - max(0, min(inner, level))
            rows.append(filled ? (row == inner - 1 ? "kBBBBk" : "kbbbbk") : "k....k")
        }
        rows.append(".kkkk.")
        return Colored(rows)
    }

    /// Трубочка от рта к стакану — клетками на сетке буханки: из уголка рта
    /// вверх-вперёд, через край стакана и вниз, в воду.
    static let strawCells: [(Int, Int)] = [
        (21, 9), (22, 8), (23, 7), (24, 6), (25, 6), (26, 7), (26, 8), (26, 9), (26, 10), (26, 11),
    ]
    static let strawColor = Color(red: 0.95, green: 0.3, blue: 0.4)

    // MARK: - Разминка

    /// Повязка на лбу: красная полоса поперёк всей головы и узелок
    /// с хвостиками сзади, которые треплет на прыжках. Клетки — на сетке
    /// буханки: первый столбец восьмой, первый ряд — третий
    /// (`headbandColumn`, `headbandRow`).
    /// `length` — ширина полосы: у буханки голова шире, чем у котика
    /// в потягушке.
    static func headband(flutter: Bool, length: Int = 14) -> Colored {
        let band = String(repeating: "r", count: length - 1)
        return flutter
            ? Colored(["r" + String(repeating: ".", count: length - 1), "." + band, "r." + band.dropFirst()])
            : Colored([String(repeating: ".", count: length), "r" + band, "." + band])
    }
    static let headbandColumn = 8
    static let headbandRow = 3

    /// Потягушка: котик упёрся в пол вытянутыми передними лапами, грудь
    /// и голова внизу, зад с хвостом задран, спина прогнута. Голова та же,
    /// что у буханки, — котик узнаётся по ней. `tail` — кончик хвоста
    /// качается.
    static func stretchBow(tail: Int) -> Sprite {
        var rows = [
            ".#...........................",
            ".#...###.....................",
            ".#.#######...................",
            "..#########..................",
            "..#########......#.....#.....",
            "..##########....##....##.....",
            "..############.#W#...#W#.....",
            "..#######################....",
            "...#######################...",
            "...##.###########W#####W##...",
            "...##...##..##############...",
            "...##...##.....##############",
            "...##...##..........#########",
        ]
        if tail == 1 {
            rows[0] = "#............................"
            rows[1] = ".#...###....................."
        }
        return Sprite(rows)
    }
    /// Где у потягушки повязка: голова ниже и правее, чем у буханки.
    static let bowHeadbandColumn = 14
    static let bowHeadbandRow = 6
    static let bowHeadbandLength = 12

    /// Счёт зарядки над котиком: «1», «2», «3» — цифры три на пять.
    static let digits: [Sprite] = [
        Sprite([".#.", "##.", ".#.", ".#.", "###"]),
        Sprite(["##.", "..#", ".#.", "#..", "###"]),
        Sprite(["##.", "..#", ".#.", "..#", "##."]),
    ]

    static let sweatColor = Color(red: 0.55, green: 0.82, blue: 1.0)
}
