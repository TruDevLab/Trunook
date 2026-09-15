import SwiftUI

/// Сценки-напоминания: котик выходит вместе с плашкой о перерыве, воде
/// или разминке и показывает, что делать.
///
/// Играют **вместе с плашкой**, а не в свободной чёлке: плашка раскрывает
/// остров вбок и вниз, поэтому котик выходит из-за края острова, а не
/// из-за края чёлки, — иначе выбегал бы прямо поверх текста плашки.
/// Ширину острова сообщает контроллер (`NotchCritter.islandWidth`).
extension CritterView {
    /// Где играет сценка: край острова, место котика, полоса меню.
    private struct Bench {
        let p = CritterArt.pixel
        let side: CGFloat
        let edge: CGFloat
        let feet: CGFloat
        let island: CGRect

        init(_ g: Geometry, side: CGFloat, islandWidth: CGFloat) {
            self.side = side
            let width = max(g.notchWidth, islandWidth)
            island = CGRect(x: g.midX - width / 2, y: 0, width: width, height: g.notchHeight)
            edge = g.midX + side * width / 2
            feet = g.notchHeight - 1
        }

        var hidden: CGFloat { edge - side * 26 }
        var rest: CGFloat { edge + side * 40 }
        var facingOut: Bool { side > 0 }

        /// Всё, кроме полосы острова: котик выходит из-за её края.
        func clip(_ ctx: GraphicsContext, size: CGSize) -> GraphicsContext {
            var clipped = ctx
            var region = Path(CGRect(origin: .zero, size: size))
            region.addRoundedRect(in: island, cornerSize: CGSize(width: 10, height: 10))
            clipped.clip(to: region, style: FillStyle(eoFill: true))
            return clipped
        }

        /// Выбег, сценка на месте, убег: где котик в миг `t`.
        func place(_ t: Double, leaveAt: Double) -> (x: CGFloat, moving: Bool, facingRight: Bool) {
            switch t {
            case ..<1.2:
                return (hidden + (rest - hidden) * CritterView.ease(t / 1.2), true, facingOut)
            case ..<leaveAt:
                return (rest, false, facingOut)
            default:
                let back = min(1, (t - leaveAt) / 1.2)
                return (rest + (hidden - rest) * CritterView.ease(back), true, !facingOut)
            }
        }
    }

    // MARK: - Перерыв

    /// Котик выбегает к кружке с молоком, цепляет её лапой и роняет — молоко
    /// разливается лужицей, котик ложится и лакает, пока не вылижет.
    func drawRest(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let b = Bench(g, side: critter.side, islandWidth: critter.islandWidth)
        let p = b.p
        let clipped = b.clip(ctx, size: g.size)
        let leaveAt = 7.2
        let place = b.place(t, leaveAt: leaveAt)
        let body = CGPoint(x: place.x, y: b.feet)
        let flipped = !b.facingOut
        let facing: CGFloat = b.facingOut ? 1 : -1
        let restSprite = CritterArt.loaf[0]
        let rest = CGPoint(x: b.rest, y: b.feet)
        func snap(_ v: CGFloat) -> CGFloat { (v / p).rounded() * p }

        let pawAt = 1.5, tipAt = 1.9, fallAt = 2.15
        let lickFrom = 2.9, lickTo = 6.6

        // Кружка: стоит, пока котик бежит; от лапы кренится и падает горлышком
        // к нему; тает, когда он убегает.
        let mugShown = min(CritterView.ease(t / 0.3), CritterView.ease((leaveAt + 0.7 - t) / 0.4))
        let mugFrame = t < tipAt ? 0 : (t < fallAt ? 1 : 2)
        // Поодаль, а не впритык: между мордочкой и кружкой разливается молоко,
        // и впритык лужица целиком уходила под котика.
        let mugX = b.rest + facing * 50
        if mugShown > 0.01 {
            var layer = clipped
            layer.opacity = mugShown
            WeatherArt.draw(CritterArt.milkMug[mugFrame], in: layer, anchor: CGPoint(x: mugX, y: b.feet), flipped: flipped)
        }

        // Лужица: от горлышка лежащей кружки к подбородку котика. Растёт,
        // пока молоко выливается, и убывает, пока котик лакает.
        let spill = CritterView.ease((t - fallAt) / 0.6)
        let licked = CritterView.ease((t - lickFrom) / (lickTo - lickFrom))
        let puddle = CGFloat(spill) * (1 - CGFloat(licked))
        let mouthOfMug = mugX - facing * 4 * p
        func drawPuddle() {
            guard puddle > 0.02 else { return }
            // От-под кружки до подбородка: край у мордочки — там, где лакают.
            let length = snap(34 * puddle)
            let far = mouthOfMug + facing * 3 * p
            let near = far - facing * length
            let x0 = min(far, near), x1 = max(far, near)
            var milk = Path()
            milk.addRect(CGRect(x: snap(x0), y: b.feet - p, width: max(p, snap(x1 - x0)), height: p))
            if x1 - x0 > 4 * p {
                milk.addRect(CGRect(x: snap(x0 + 2 * p), y: b.feet - 2 * p, width: snap(x1 - x0 - 4 * p), height: p))
            }
            // Посередине лужица горкой: в два ряда она читалась полоской.
            if x1 - x0 > 12 * p {
                milk.addRect(CGRect(x: snap(x0 + 5 * p), y: b.feet - 3 * p, width: snap(x1 - x0 - 10 * p), height: p))
            }
            // Тёмная кромка снизу: на светлых обоях белая лужица иначе пропадает.
            clipped.fill(Path(CGRect(x: snap(x0), y: b.feet, width: max(p, snap(x1 - x0)), height: p / 2)),
                         with: .color(WeatherArt.color("k")))
            clipped.fill(milk, with: .color(CritterArt.milkColor))
        }
        // Струйка из горлышка, пока кружка падает и выливается.
        if (fallAt - 0.1..<fallAt + 0.5).contains(t) {
            var stream = Path()
            for k in 0..<3 {
                let phase = (t * 6 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                let x = mouthOfMug - facing * CGFloat(phase) * 6
                let y = b.feet - 4 * p + CGFloat(phase * phase) * 3 * p
                stream.addRect(CGRect(x: snap(x), y: snap(y), width: p, height: p))
            }
            clipped.fill(stream, with: .color(CritterArt.milkColor))
        }

        // Котик: бежит, лежит у кружки; лакает с закрытыми глазами.
        let lapping = !place.moving && (lickFrom..<lickTo).contains(t)
        let sprite = place.moving ? CritterArt.run[Int(t * 8) % 2] : CritterArt.loaf[lapping ? 1 : 0]
        CritterArt.draw(sprite, in: clipped, anchor: body, flipped: !place.facingRight)
        // Лужица — поверх котика: у мордочки она лежит перед ним, а не под ним.
        drawPuddle()

        guard !place.moving else { return }
        // Лапа тянется к кружке и цепляет её.
        if (pawAt..<fallAt).contains(t) {
            let reach = Int(min(9, (t - pawAt) / 0.04))
            var paw = Path()
            for column in 21...(22 + reach) {
                paw.addRect(CritterArt.cell(column, 9, of: restSprite, anchor: rest, flipped: flipped))
            }
            paw.addRect(CritterArt.cell(22 + reach, 8, of: restSprite, anchor: rest, flipped: flipped))
            clipped.fill(paw, with: .color(.black))
        }
        // Язычок: высовывается к лужице и прячется, быстро, как лакают кошки.
        if lapping, (t * 3).truncatingRemainder(dividingBy: 1) < 0.45 {
            var tongue = Path()
            for (column, row) in [(21, 11), (22, 11), (22, 12)] {
                tongue.addRect(CritterArt.cell(column, row, of: restSprite, anchor: rest, flipped: flipped))
            }
            clipped.fill(tongue, with: .color(CritterArt.tongueColor))
        }
        // Вылизал — сердечко от довольства.
        let age = t - lickTo
        if age > 0, age < 0.9 {
            var layer = clipped
            layer.opacity = 1 - max(0, age - 0.5) / 0.4
            let head = CritterArt.cell(17, 4, of: restSprite, anchor: rest, flipped: flipped)
            CritterArt.draw(CritterArt.hearts[0], in: layer,
                            anchor: CGPoint(x: head.midX + facing * 20, y: head.minY + 6 - CGFloat(age) * 6),
                            ink: CritterArt.heartColor)
        }
    }

    // MARK: - Вода

    /// Котик выбегает к стакану воды и пьёт через трубочку: три глотка,
    /// вода убывает, в стакане поднимаются пузырьки.
    func drawDrink(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let b = Bench(g, side: critter.side, islandWidth: critter.islandWidth)
        let p = b.p
        let clipped = b.clip(ctx, size: g.size)
        let leaveAt = 7.4
        let sips: [Double] = [2.0, 3.6, 5.2]
        let sipTime = 1.0
        let place = b.place(t, leaveAt: leaveAt)
        let body = CGPoint(x: place.x, y: b.feet)
        let sipping = sips.contains { (0..<sipTime).contains(t - $0) }
        let sprite = place.moving ? CritterArt.run[Int(t * 8) % 2] : CritterArt.loaf[sipping ? 1 : 0]
        // Стакан стоит на сетке лежащей буханки, даже пока котик бежит:
        // стоит он там, куда котик ляжет.
        let rest = CGPoint(x: b.rest, y: b.feet)
        let restSprite = CritterArt.loaf[0]
        let flipped = !b.facingOut

        // Сколько уже выпито — по времени глотков.
        let drunk = sips.reduce(0.0) { $0 + min(sipTime, max(0, t - $1)) }
        let level = max(0, 5 - Int(drunk / 0.6))

        let glassShown = min(CritterView.ease((t - 0.6) / 0.4), CritterView.ease((leaveAt + 0.7 - t) / 0.4))
        if glassShown > 0.01 {
            var layer = clipped
            layer.opacity = glassShown
            let glass = CritterArt.waterGlass(level: level)
            Self.drawOn(glass, column: 24, row: restSprite.height - glass.height, cat: restSprite,
                        anchor: rest, flipped: flipped, in: layer)
            // Пузырьки на глотке: белые точки поднимаются по воде.
            if sipping, level > 0 {
                var bubbles = Path()
                for k in 0..<3 {
                    let phase = (t * 3 + Double(k) * 0.33).truncatingRemainder(dividingBy: 1)
                    let row = restSprite.height - 2 - Int(phase * Double(level))
                    bubbles.addRect(CritterArt.cell(25 + k % 2 * 2, row, of: restSprite, anchor: rest, flipped: flipped))
                }
                layer.fill(bubbles, with: .color(.white.opacity(0.85)))
            }
        }

        CritterArt.draw(sprite, in: clipped, anchor: body, flipped: !place.facingRight)

        // Трубочка — пока котик лежит у стакана.
        if !place.moving, t > 1.3 {
            var straw = Path()
            for (column, row) in CritterArt.strawCells {
                straw.addRect(CritterArt.cell(column, row, of: restSprite, anchor: rest, flipped: flipped))
            }
            clipped.fill(straw, with: .color(CritterArt.strawColor))
        }

        // Напился: капля срывается с губ.
        let age = t - 6.4
        if !place.moving, age > 0, age < 0.7 {
            let mouth = CritterArt.cell(20, 11, of: restSprite, anchor: rest, flipped: flipped)
            let y = mouth.minY + CGFloat(age * age) * 30
            clipped.fill(Path(CGRect(x: mouth.minX, y: (y / p).rounded() * p, width: p, height: p)),
                         with: .color(CritterArt.sweatColor))
        }
    }

    // MARK: - Разминка

    /// Котик в повязке выбегает и делает зарядку: три прыжка со счётом,
    /// потягушка с прогнутой спиной, ещё два прыжка — с котика летят капли пота.
    func drawStretch(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let b = Bench(g, side: critter.side, islandWidth: critter.islandWidth)
        let p = b.p
        let clipped = b.clip(ctx, size: g.size)
        let leaveAt = 7.2
        let place = b.place(t, leaveAt: leaveAt)
        let facing: CGFloat = place.facingRight ? 1 : -1

        // Прыжки: три со счётом, потом потягушка, потом два быстрых.
        let counted: [(start: Double, length: Double)] = [(1.4, 0.8), (2.2, 0.8), (3.0, 0.8)]
        let quick: [(start: Double, length: Double)] = [(5.8, 0.65), (6.45, 0.65)]
        var lift: CGFloat = 0
        for hop in counted + quick where (0..<hop.length).contains(t - hop.start) {
            // Невысоко: над буханкой в полосе меню пять точек до края экрана.
            lift = CGFloat(sin((t - hop.start) / hop.length * .pi)) * 5
        }

        // Потягушка: упор на вытянутые передние лапы, зад задран, спина
        // прогнута, хвост покачивается.
        let bowing = !place.moving && (3.9..<5.5).contains(t)
        let sprite: CritterArt.Sprite
        if place.moving {
            sprite = CritterArt.run[Int(t * 8) % 2]
        } else if bowing {
            sprite = CritterArt.stretchBow(tail: Int(t * 3) % 2)
        } else {
            sprite = CritterArt.loaf[0]
        }
        // Голова потягушки на полтора столбца правее середины, чем у буханки:
        // сдвиг держит мордочку на месте, а назад уезжает зад.
        let body = CGPoint(
            x: place.x - (bowing ? facing * p : 0),
            y: b.feet - (lift / p).rounded() * p
        )
        CritterArt.draw(sprite, in: clipped, anchor: body, flipped: !place.facingRight)

        // Повязка — на лбу, в какой бы позе котик ни был.
        let flutter = (place.moving || lift > 0) && Int(t * 8) % 2 == 0
        Self.drawOn(
            CritterArt.headband(flutter: flutter, length: bowing ? CritterArt.bowHeadbandLength : 14),
            column: bowing ? CritterArt.bowHeadbandColumn : CritterArt.headbandColumn,
            row: bowing ? CritterArt.bowHeadbandRow : CritterArt.headbandRow,
            cat: sprite, anchor: body, flipped: !place.facingRight, in: clipped
        )

        // Счёт перед мордочкой: цифра всплывает на своём прыжке. Не над
        // головой — над буханкой в полосе меню край экрана.
        for (index, hop) in counted.enumerated() {
            let age = t - hop.start
            guard age > 0, age < 0.9 else { continue }
            var layer = clipped
            layer.opacity = 1 - max(0, age - 0.5) / 0.4
            CritterArt.draw(CritterArt.digits[index], in: layer,
                            anchor: CGPoint(x: place.x + facing * 32, y: b.feet - 8 - CGFloat(age) * 6),
                            outlined: true, ink: .white, outline: .black)
        }

        // Капли пота: с приземления разлетаются от головы и падают.
        var drops = Path()
        for hop in counted + quick {
            let age = t - (hop.start + hop.length * 0.85)
            guard age > 0, age < 0.6 else { continue }
            let head = CritterArt.cell(14, 2, of: CritterArt.loaf[0], anchor: CGPoint(x: place.x, y: b.feet),
                                       flipped: !place.facingRight)
            for direction in [-1.0, 1.0] {
                let x = head.midX + CGFloat(direction) * CGFloat(age) * 22
                let y = head.minY - CGFloat(age) * 14 + CGFloat(age * age) * 40
                drops.addRect(CGRect(x: (x / p).rounded() * p, y: (y / p).rounded() * p, width: p, height: p))
            }
        }
        clipped.fill(drops, with: .color(CritterArt.sweatColor))
    }
}
