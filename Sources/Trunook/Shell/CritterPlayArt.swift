import SwiftUI

/// Реквизит новых сценок: мышь, зонт со смузи, птичка.
///
/// Сам котик — всё та же буханка из `CritterArt`; здесь только то, что рядом
/// с ним. Цветное — спрайтами `WeatherArt.Sprite` на той же сетке в два
/// пикселя, что у праздников и напоминаний.
///
/// Без зависимостей от приложения: рисунок подбирается глазами по листу
/// кадров, `make critter`.
extension CritterArt {
    // MARK: - Мышь

    /// Мышь: тёмно-серая капля — острая мордочка, полное тельце к хвосту, —
    /// круглое ухо, тёмный глаз и длинный тонкий хвост. Смотрит влево.
    /// Два кадра: лапки в беге меняются местами.
    ///
    /// Каплей, а не овалом: овал читался камешком. Хвост длиной в половину
    /// тела — по нему мышь и узнаётся с одного взгляда.
    static func mouse(step: Int) -> Colored {
        var rows = [
            "..mm..mmm......",
            ".mmmmmmmmmm....",
            "mKmmmmmmmmmk...",
            "mmmmmmmmmm.kk..",
            ".mm...mm.....kk",
        ]
        if step == 1 {
            rows[4] = "..mm.mm......kk"
            rows[3] = "mmmmmmmmmm..kk."
        }
        return Colored(rows)
    }

    // MARK: - Зонт и смузи

    /// Пляжный зонт: купол полосами и тонкая ножка. `open` от 0 до 1 —
    /// котик его раскрывает, купол растёт вширь от ножки.
    ///
    /// Полосы красные через белые: одноцветный купол читался шляпой гриба.
    static func umbrella(open: Double) -> Colored {
        let full = 21
        let width = max(3, Int((Double(full) * min(1, max(0, open))).rounded()) | 1)
        let dome = 4
        // Ножка длинная: с короткой купол оказывался на уровне спины
        // лежащего котика и читался колпаком у него на плече. Проверено
        // листом кадров.
        let height = dome + 17
        var grid = Array(repeating: Array(repeating: Character("."), count: full), count: height)
        let center = full / 2
        let half = width / 2

        for y in 0..<dome {
            // Купол — дуга: чем ниже ряд, тем шире.
            // Дуга крутая у макушки и пологая к краям: линейная выходила
            // конусом, а не зонтом.
            let arc = (Double(y + 1) / Double(dome)).squareRoot()
            let reach = Int((Double(half) * arc).rounded())
            for x in (center - reach)...(center + reach) {
                guard x >= 0, x < full else { continue }
                // Полосы считаются от середины, чтобы купол был симметричным.
                grid[y][x] = ((x - center + 60) / 3) % 2 == 0 ? "r" : "W"
            }
        }
        // Тёмная кромка под куполом: белые полосы на светлых обоях
        // пропадали вовсе, и зонт читался половиной — одними красными.
        // Та же беда, что у сугроба в новогодней сценке.
        let rim = Int((Double(half) * 1.0).rounded())
        for x in max(0, center - rim)...min(full - 1, center + rim) {
            grid[dome][x] = "k"
        }

        // Ножка — от кромки до земли.
        for y in (dome + 1)..<height {
            grid[y][center] = "t"
        }
        grid[height - 1][center - 1] = "t"
        grid[height - 1][center + 1] = "t"
        return Colored(grid.map { String($0) })
    }

    /// Смузи в стакане с трубочкой. `level` — сколько рядов осталось, 0…5.
    /// Розовый: ягодный смузи узнаётся цветом, а не формой.
    static func smoothie(level: Int) -> Colored {
        let inner = 5
        var rows = ["..k...W..", "..k...W..", "kkkkkkWkk"]
        for row in 0..<inner {
            let filled = row >= inner - max(0, min(inner, level))
            rows.append(filled ? "kppppWppk" : "k.....W.k")
        }
        rows.append(".kkkkkkk.")
        return Colored(rows)
    }

    /// Цвет солнца из чёлки — тёплый жёлтый. Отдельной величиной: им же
    /// красится и зарево, и лучи, а расходиться им незачем.
    static let sunGlow = Color(red: 1.0, green: 0.85, blue: 0.35)

    // MARK: - Птичка

    /// Птичка: жёлтое тельце, оранжевый клювик, тёмный глаз. Два кадра —
    /// крыло вверх и вниз, ими она и машет. Смотрит вправо.
    static func bird(wingsUp: Bool) -> Colored {
        wingsUp
            ? Colored([
                "...dd......",
                "..dddd.....",
                "..yyyy.....",
                ".yyyyyy....",
                "yyKyyyyoo..",
                ".yyyyyy....",
                "..yyyy.....",
                "...o.o.....",
            ])
            : Colored([
                "...........",
                "...yyy.....",
                ".yyyyyy....",
                "yyKyyyyoo..",
                ".yyyyyy....",
                "..dddd.....",
                "...dd......",
                "...o.o.....",
            ])
    }
}
