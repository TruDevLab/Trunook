import SwiftUI

/// Сценки кота из `NotchCritter`.
///
/// Всё рисуется фигурами на `Canvas`, без картинок: так кот одинаково
/// чёткий на любой плотности экрана и не тянет в бандл ресурсов. Сам рисунок —
/// в `CritterArt`, пиксельный, чёрно-белый; здесь — где на экране и в какой
/// миг сценки. Кадры сменяются ступенями, пятнадцати в секунду хватает.
/// Кадры считаются из времени от начала сценки — `@State` в этом тулчейне
/// недоступен, и тем же приёмом живёт бегущая строка.
///
/// Холст шире и выше чёлки: хвост свешивается ниже её кромки, котик ходит
/// по полосе меню сбоку. Попаданий слой не принимает — нажатия уходят тому,
/// что под ним.
struct CritterView: View {
    @ObservedObject var critter: NotchCritter
    let metrics: NotchMetrics
    /// Неглавное окно: кот живёт в одном вырезе, а не во всех сразу.
    let isHidden: Bool

    /// Шире и выше, чем нужно прочим сценкам: на охоте котик бегает
    /// за курсором под чёлкой. Окно выреза и так больше, лишнее обрежет оно.
    static let canvasSize = CGSize(width: 600, height: 240)


    var body: some View {
        let act = isHidden ? nil : critter.act
        TimelineView(.animation(minimumInterval: 1 / 15, paused: act == nil)) { context in
            Canvas { ctx, size in
                guard let act else { return }
                let t = context.date.timeIntervalSince(critter.startedAt)
                let geometry = Geometry(size: size, metrics: metrics)
                switch act {
                case .eyes: drawEyes(in: &ctx, geometry, t: t)
                case .tail: drawTail(in: &ctx, geometry, t: t)
                case .run: drawRun(in: &ctx, geometry, t: t)
                case .ears: drawEars(in: &ctx, geometry, t: t)
                case .paw: drawPaw(in: &ctx, geometry, t: t)
                case .sleep: drawSleep(in: &ctx, geometry, t: t)
                case .upside: drawUpside(in: &ctx, geometry, t: t)
                case .yarn: drawYarn(in: &ctx, geometry, t: t)
                case .angry: drawAngry(in: &ctx, geometry, t: t)
                case .fist: drawFist(in: &ctx, geometry, t: t)
                case .kiss: drawKiss(in: &ctx, geometry, t: t)
                case .chase: drawChase(in: &ctx, geometry, t: t)
                case .hunt: drawHunt(in: &ctx, geometry, t: t)
                case .cool: drawCool(in: &ctx, geometry, t: t)
                case .smoke: drawSmoke(in: &ctx, geometry, t: t)
                case .mouse: drawMouse(in: &ctx, geometry, t: t)
                case .beach: drawBeach(in: &ctx, geometry, t: t)
                case .bird: drawBird(in: &ctx, geometry, t: t)
                case .watch: drawWatch(in: &ctx, geometry, t: t)
                case .winter: drawWinter(in: &ctx, geometry, t: t)
                case .kittens: drawKittens(in: &ctx, geometry, t: t)
                case .flowers: drawFlowers(in: &ctx, geometry, t: t)
                case .tank: drawTank(in: &ctx, geometry, t: t)
                case .easter: drawEaster(in: &ctx, geometry, t: t)
                case .pumpkin: drawPumpkin(in: &ctx, geometry, t: t)
                case .valentine: drawValentine(in: &ctx, geometry, t: t)
                case .ribbon: drawRibbon(in: &ctx, geometry, t: t)
                case .dragon: drawDragon(in: &ctx, geometry, t: t)
                case .rocket: drawRocket(in: &ctx, geometry, t: t)
                case .rest: drawRest(in: &ctx, geometry, t: t)
                case .drink: drawDrink(in: &ctx, geometry, t: t)
                case .stretch: drawStretch(in: &ctx, geometry, t: t)
                }
            }
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .opacity(act == nil ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Где чёлка на холсте.
    /// Не `private`: праздничные сценки живут в своём файле, `CritterHolidays`.
    struct Geometry {
        let midX: CGFloat
        let notchWidth: CGFloat
        let notchHeight: CGFloat
        let size: CGSize

        init(size: CGSize, metrics: NotchMetrics) {
            self.size = size
            midX = size.width / 2
            notchWidth = metrics.notchWidth
            notchHeight = metrics.notchHeight
        }

        var notchRect: CGRect {
            CGRect(x: midX - notchWidth / 2, y: 0, width: notchWidth, height: notchHeight)
        }
    }

    // MARK: - Мордочка из-под чёлки

    private func drawEyes(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let duration = NotchCritter.Act.eyes.duration
        let p = CritterArt.pixel
        // Выезжает из-под кромки ступенями по пикселю и уезжает обратно.
        let reach = min(Self.ease(t / 0.5), Self.ease((duration - t) / 0.5))
        guard reach > 0.01 else { return }
        var level = 2
        // Два моргания — по ним котик и читается живым.
        for blink in [1.8, 3.4] where abs(t - blink) < 0.14 { level = 0 }
        if critter.squints { level = min(level, 1) }
        let gaze = critter.gaze
        let sprite = CritterArt.peek(
            open: level,
            look: Int((gaze.x * 3).rounded()),
            down: gaze.y > 0.35
        )
        let height = CGFloat(sprite.height) * p
        // Верх спрайта прячется в чёлке, пока котик не выглянул.
        let top = g.notchHeight - p - (1 - CGFloat(reach)) * height
        // Вся мордочка ползёт вдоль кромки к курсору, а не только глаза:
        // сдвиг глаз на пиксель-другой издалека не виден. Не дальше края
        // чёлки — лапки держатся за её кромку.
        let room = g.notchWidth / 2 - CGFloat(sprite.width) * p / 2 - 6
        let x = g.midX + max(-room, min(room, gaze.x * g.notchWidth))
        CritterArt.draw(sprite, in: Self.outsideNotch(ctx, g), anchor: CGPoint(x: x, y: top + height))
    }

    // MARK: - Хвост

    private func drawTail(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let duration = NotchCritter.Act.tail.duration
        let reach = min(Self.ease(t / 0.7), Self.ease((duration - t) / 0.7))
        guard reach > 0.01 else { return }
        let (sprite, rootColumn) = CritterArt.hangingTail(time: t)
        let p = CritterArt.pixel
        let height = CGFloat(sprite.height) * p
        // Хвост не растёт, а выезжает из-под чёлки: основание уходит внутрь
        // выреза и обрезается им.
        let rootX = g.midX + g.notchWidth * 0.28
        let rootY = g.notchHeight - 2 - (1 - CGFloat(reach)) * height
        let anchor = CGPoint(
            x: rootX + CGFloat(sprite.width / 2 - rootColumn) * p,
            y: rootY + height
        )
        CritterArt.draw(sprite, in: Self.outsideNotch(ctx, g), anchor: anchor)
    }

    // MARK: - Пробежка

    private func drawRun(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let edge = g.midX + g.notchWidth / 2
        let hidden = edge - 26
        let restX = edge + 60
        // Лапы у самой кромки полосы меню.
        let feet = g.notchHeight - 1
        let clipped = Self.outsideNotch(ctx, g)
        // Бег — два кадра по восемь раз в секунду: пиксельный котик скачет
        // рывками, как в игре, а не плывёт.
        let stride = CritterArt.run[Int(t * 8) % 2]

        switch t {
        case ..<1.2:
            let x = hidden + (restX - hidden) * Self.ease(t / 1.2)
            CritterArt.draw(stride, in: clipped, anchor: CGPoint(x: x, y: feet))
        case ..<5.4:
            // Лёг буханкой и дважды медленно моргнул.
            let blinking = (2.4..<2.9).contains(t) || (4.0..<4.5).contains(t)
            CritterArt.draw(CritterArt.loaf[blinking ? 1 : 0], in: clipped, anchor: CGPoint(x: restX, y: feet))
        default:
            let back = min(1, (t - 5.4) / 1.2)
            let x = restX + (hidden - restX) * Self.ease(back)
            CritterArt.draw(stride, in: clipped, anchor: CGPoint(x: x, y: feet), flipped: true)
        }
    }

    // MARK: - Уши из-за края

    private func drawEars(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let duration = NotchCritter.Act.ears.duration
        let side = critter.side
        let sprite0 = CritterArt.ears(twitch: false, blink: false)
        let half = CGFloat(sprite0.width) * CritterArt.pixel / 2
        let edge = g.midX + side * g.notchWidth / 2
        // Голова выезжает из-за края на три четверти: видны оба уха и оба
        // глаза, а край чёлки прячет только затылок. Наполовину было мало —
        // одно ухо без второго котом не читалось.
        let out = min(Self.ease(t / 0.6), Self.ease((duration - t) / 0.6))
        let x = edge + side * (-half + half * 1.5 * CGFloat(out))
        let twitch = [1.2, 2.6, 3.1].contains { (t - $0) >= 0 && (t - $0) < 0.22 }
        let blink = abs(t - 2.0) < 0.14
        CritterArt.draw(
            CritterArt.ears(twitch: twitch, blink: blink),
            in: Self.outsideNotch(ctx, g),
            anchor: CGPoint(x: x, y: g.notchHeight),
            flipped: side < 0
        )
    }

    // MARK: - Лапа

    private func drawPaw(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let duration = NotchCritter.Act.paw.duration
        let p = CritterArt.pixel
        let reach = min(Self.ease(t / 0.5), Self.ease((duration - t) / 0.5))
        guard reach > 0.01 else { return }
        // Отмахивается, пока лапа снаружи: туда-сюда, как за игрушкой.
        let swiping = (1.0..<3.6).contains(t)
        let lean = swiping ? Int((sin(t * 7) * 2).rounded()) : 0
        let sprite = CritterArt.paw(lean: lean)
        let height = CGFloat(sprite.height) * p
        let top = g.notchHeight - p - (1 - CGFloat(reach)) * height
        // Ловит курсор: тянется к нему вдоль кромки.
        let room = g.notchWidth / 2 - CGFloat(sprite.width) * p / 2 - 10
        let x = g.midX + max(-room, min(room, critter.gaze.x * g.notchWidth))
        CritterArt.draw(sprite, in: Self.outsideNotch(ctx, g), anchor: CGPoint(x: x, y: top + height))
    }

    // MARK: - Сон

    private func drawSleep(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let side = critter.side
        let edge = g.midX + side * g.notchWidth / 2
        let hidden = edge - side * 26
        let restX = edge + side * 58
        let feet = g.notchHeight - 1
        let clipped = Self.outsideNotch(ctx, g)
        let flip = side < 0
        let stride = CritterArt.run[Int(t * 8) % 2]

        switch t {
        case ..<1.2:
            let x = hidden + (restX - hidden) * Self.ease(t / 1.2)
            CritterArt.draw(stride, in: clipped, anchor: CGPoint(x: x, y: feet), flipped: flip)
        case ..<1.8, 7.4..<8.0:
            CritterArt.draw(CritterArt.loaf[0], in: clipped, anchor: CGPoint(x: restX, y: feet), flipped: flip)
        case ..<7.4:
            // Дышит медленно, раз в полторы секунды.
            let breath = CritterArt.sleeping[Int((t - 1.8) / 0.75) % 2]
            CritterArt.draw(breath, in: clipped, anchor: CGPoint(x: restX, y: feet), flipped: flip)
            // Буквы поднимаются от головы одна за другой и тают наверху.
            for k in 0..<2 {
                let local = t - 2.2 - Double(k) * 0.8
                guard local > 0 else { continue }
                let phase = CGFloat(local.truncatingRemainder(dividingBy: 1.6) / 1.6)
                guard phase < 0.9 else { continue }
                let letter = CritterArt.z[phase < 0.45 ? 0 : 1]
                let x = restX + side * (24 + phase * 12)
                let y = feet - 10 - phase * 16
                CritterArt.draw(letter, in: clipped, anchor: CGPoint(x: x, y: y))
            }
        default:
            let back = min(1, (t - 8.0) / 1.2)
            let x = restX + (hidden - restX) * Self.ease(back)
            CritterArt.draw(stride, in: clipped, anchor: CGPoint(x: x, y: feet), flipped: !flip)
        }
    }

    // MARK: - Вверх ногами

    private func drawUpside(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let p = CritterArt.pixel
        let side = critter.side
        let edge = g.midX + side * g.notchWidth / 2
        let far = g.midX - side * g.notchWidth / 2
        let menu = g.notchHeight - 1
        let clipped = Self.outsideNotch(ctx, g)
        let stride = CritterArt.run[Int(t * 8) % 2]
        let height = CGFloat(stride.height) * p
        // Вверх ногами лапы у нижней кромки выреза, спина вниз.
        let ceiling = g.notchHeight + height
        let hidden = CGPoint(x: edge - side * 26, y: menu)
        let corner = CGPoint(x: edge + side * 12, y: menu)
        // Под кромкой — не у самых углов: там она скруглена.
        let near = CGPoint(x: edge - side * 18, y: ceiling)
        let farEnd = CGPoint(x: far + side * 18, y: ceiling)

        func run(from a: CGPoint, to b: CGPoint, _ k: Double, upsideDown: Bool) {
            let k = CGFloat(Self.ease(k))
            let body = CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
            CritterArt.draw(stride, in: clipped, anchor: body, flipped: b.x < a.x, upsideDown: upsideDown)
        }

        switch t {
        case ..<0.8:
            run(from: hidden, to: corner, t / 0.8, upsideDown: false)
        case ..<1.1:
            // Перебирается через угол: половину пути ещё на лапах,
            // вторую — уже вверх ногами.
            let k = (t - 0.8) / 0.3
            run(from: corner, to: near, k, upsideDown: k > 0.5)
        case ..<3.1:
            run(from: near, to: farEnd, (t - 1.1) / 2, upsideDown: true)
        case ..<3.6:
            // Добежал до другого угла — висит буханкой и моргает.
            let blink = (3.25..<3.45).contains(t)
            CritterArt.draw(CritterArt.loaf[blink ? 1 : 0], in: clipped,
                            anchor: CGPoint(x: farEnd.x, y: g.notchHeight + CGFloat(CritterArt.loaf[0].height) * p),
                            flipped: side > 0, upsideDown: true)
        case ..<5.5:
            run(from: farEnd, to: near, (t - 3.6) / 1.9, upsideDown: true)
        case ..<5.8:
            let k = (t - 5.5) / 0.3
            run(from: near, to: corner, k, upsideDown: k < 0.5)
        default:
            run(from: corner, to: hidden, min(1, (t - 5.8) / 0.8), upsideDown: false)
        }
    }

    // MARK: - Клубок

    private func drawYarn(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let p = CritterArt.pixel
        let side = critter.side
        let edge = g.midX + side * g.notchWidth / 2
        let feet = g.notchHeight - 1
        let clipped = Self.outsideNotch(ctx, g)
        let flip = side < 0

        // Клубок: выкатывается, лежит (котик его толкает), укатывается назад.
        let ballOut = edge + side * 104
        let ballIn = edge - side * 10
        var ballX: CGFloat
        var rolling = false
        switch t {
        case ..<1.4:
            ballX = ballIn + (ballOut - ballIn) * Self.easeOut(t / 1.4)
            rolling = true
        case ..<3.4:
            ballX = ballOut
        case ..<4.8:
            // Котик толкнул — клубок откатился на полшага.
            ballX = ballOut + side * 8 * Self.ease((t - 3.4) / 0.4)
            rolling = t < 3.8
        case ..<6.2:
            let from = ballOut + side * 8
            ballX = from + (ballIn - from) * Self.ease((t - 4.8) / 1.4)
            rolling = true
        default:
            ballX = ballIn
        }
        // Нитка тянется от чёлки к клубку по земле.
        let threadY = feet - p
        var thread = Path()
        thread.addRect(CGRect(
            x: min(edge, ballX), y: (threadY / p).rounded() * p,
            width: abs(ballX - edge), height: p
        ))
        clipped.fill(thread, with: .color(.black))
        let ballFrame = rolling ? Int(t * 10) % 2 : 0
        CritterArt.draw(CritterArt.yarn(frame: ballFrame), in: clipped, anchor: CGPoint(x: ballX, y: feet))

        // Котик: бежит следом, сидит, прыгает на клубок, убегает.
        let hidden = edge - side * 26
        let restX = edge + side * 70
        let stride = CritterArt.run[Int(t * 8) % 2]
        switch t {
        case ..<0.8:
            break
        case ..<2.2:
            let x = hidden + (restX - hidden) * Self.ease((t - 0.8) / 1.4)
            CritterArt.draw(stride, in: clipped, anchor: CGPoint(x: x, y: feet), flipped: flip)
        case ..<3.2:
            CritterArt.draw(CritterArt.loaf[0], in: clipped, anchor: CGPoint(x: restX, y: feet), flipped: flip)
        case ..<3.6:
            // Прыжок: котик в разбеге, на полшага ближе к клубку.
            CritterArt.draw(CritterArt.run[0], in: clipped,
                            anchor: CGPoint(x: restX + side * 6, y: feet - 2 * p), flipped: flip)
        case ..<4.8:
            CritterArt.draw(CritterArt.loaf[0], in: clipped, anchor: CGPoint(x: restX, y: feet), flipped: flip)
        case ..<6.3:
            let x = restX + (hidden - restX) * Self.ease((t - 4.8) / 1.5)
            CritterArt.draw(stride, in: clipped, anchor: CGPoint(x: x, y: feet), flipped: !flip)
        default:
            break
        }
    }

    // MARK: - Злой котик

    private func drawAngry(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let p = CritterArt.pixel
        let side = critter.side
        let edge = g.midX + side * g.notchWidth / 2
        let hidden = edge - side * 26
        let restX = edge + side * 60
        let feet = g.notchHeight - 1
        let clipped = Self.outsideNotch(ctx, g)
        let flip = side < 0
        let stride = CritterArt.run[Int(t * 8) % 2]

        switch t {
        case ..<1.2:
            let x = hidden + (restX - hidden) * Self.ease(t / 1.2)
            CritterArt.draw(stride, in: clipped, anchor: CGPoint(x: x, y: feet), flipped: flip)
        case ..<5.2:
            // Лежит буханкой и трясётся от злости — на пиксель туда-сюда.
            let shake: CGFloat = Int(t * 14) % 2 == 0 ? p : -p
            CritterArt.draw(CritterArt.loaf[0], in: clipped, anchor: CGPoint(x: restX + shake, y: feet), flipped: flip)
            let body = CGPoint(x: restX, y: feet - 12)

            // Искры — вспышками, каждая по восьми лучам, повёрнутым
            // от вспышки к вспышке, чтобы не бить в одни и те же места.
            for burst in 0..<8 {
                let local = t - 1.4 - Double(burst) * 0.45
                guard local > 0, local < 0.4 else { continue }
                let reach = CGFloat(local / 0.4)
                for ray in 0..<8 {
                    let angle = (Double(ray) + (burst % 2 == 0 ? 0 : 0.5)) * .pi / 4
                    let distance = 16 + reach * 20
                    let x = body.x + CGFloat(cos(angle)) * distance
                    let y = body.y + CGFloat(sin(angle)) * distance * 0.8
                    var spark = Path()
                    // Два пикселя на два: одиночный пиксель на экране терялся.
                    spark.addRect(CGRect(x: (x / p).rounded() * p, y: (y / p).rounded() * p, width: 2 * p, height: 2 * p))
                    let color = CritterArt.sparkColors[(ray + burst) % 2]
                    clipped.fill(spark, with: .color(reach > 0.75 ? color.opacity(0.5) : color))
                }
            }

            // Ругательства: по одному от головы, дугой — вверх, в сторону
            // от чёлки и вниз, под полосу меню: над котиком там край экрана.
            for k in 0..<10 {
                let local = t - 1.5 - Double(k) * 0.36
                guard local > 0, local < 1.1 else { continue }
                let glyph = CritterArt.grawlix[k % CritterArt.grawlix.count]
                let spread = CGFloat(k % 3) * 14
                let x = body.x + side * (18 + CGFloat(local) * (46 + spread))
                let y = body.y - CGFloat(local) * 34 + CGFloat(local * local) * 70
                CritterArt.draw(glyph, in: clipped, anchor: CGPoint(x: x, y: y), ink: CritterArt.heartColor)
            }
        default:
            let back = min(1, (t - 5.2) / 1.2)
            let x = restX + (hidden - restX) * Self.ease(back)
            CritterArt.draw(stride, in: clipped, anchor: CGPoint(x: x, y: feet), flipped: !flip)
        }
    }

    // MARK: - Кулак

    private func drawFist(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let p = CritterArt.pixel
        let side = critter.side
        let edge = g.midX + side * g.notchWidth / 2
        let hidden = edge - side * 26
        let restX = edge + side * 60
        let feet = g.notchHeight - 1
        let clipped = Self.outsideNotch(ctx, g)
        let flip = side < 0
        let stride = CritterArt.run[Int(t * 8) % 2]
        func loaf(frown: Bool, fist: Bool?, hop: CGFloat = 0) {
            CritterArt.draw(CritterArt.fistLoaf(frown: frown, fist: fist), in: clipped,
                            anchor: CGPoint(x: restX + side * CritterArt.fistShift, y: feet - hop), flipped: flip)
        }

        switch t {
        case ..<1.2:
            let x = hidden + (restX - hidden) * Self.ease(t / 1.2)
            CritterArt.draw(stride, in: clipped, anchor: CGPoint(x: x, y: feet), flipped: flip)
        case ..<1.7:
            // Лёг и смотрит спокойно — чтобы было видно, как нахмурится.
            loaf(frown: false, fist: nil)
        case ..<2.1:
            // Нахмурился — и сердито подскочил на пиксель.
            loaf(frown: true, fist: nil, hop: t < 1.8 ? p : 0)
        case ..<5.4:
            // Трясёт кулаком шесть раз в секунду и подпрыгивает на пиксель
            // вместе с каждым взмахом.
            let high = Int(t * 6) % 2 == 0
            loaf(frown: true, fist: high, hop: high ? p : 0)
        default:
            let back = min(1, (t - 5.4) / 1.2)
            let x = restX + (hidden - restX) * Self.ease(back)
            CritterArt.draw(stride, in: clipped, anchor: CGPoint(x: x, y: feet), flipped: !flip)
        }
    }

    // MARK: - Поцелуйчик

    private func drawKiss(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let p = CritterArt.pixel
        let side = critter.side
        let edge = g.midX + side * g.notchWidth / 2
        let hidden = edge - side * 26
        let restX = edge + side * 60
        let feet = g.notchHeight - 1
        let clipped = Self.outsideNotch(ctx, g)
        let flip = side < 0
        let stride = CritterArt.run[Int(t * 8) % 2]

        switch t {
        case ..<1.2:
            let x = hidden + (restX - hidden) * Self.ease(t / 1.2)
            CritterArt.draw(stride, in: clipped, anchor: CGPoint(x: x, y: feet), flipped: flip)
        case ..<5.6:
            // Лежит буханкой и не меняется — поцелуйчик читается сердечком
            // у мордочки, а не позой.
            CritterArt.draw(CritterArt.loaf[0], in: clipped, anchor: CGPoint(x: restX, y: feet), flipped: flip)
            // Рот буханки — четыре пикселя вперёд от середины и три ряда
            // над лапами; мордочка смотрит от чёлки.
            let mouth = CGPoint(x: restX + side * 4 * p, y: feet - 3 * p)
            for start in [1.8, 3.4] {
                let local = t - start
                guard local > 0, local < 1.9 else { continue }
                let flight = CGFloat(local / 1.9)
                let heart = CritterArt.hearts[flight < 0.18 ? 0 : 1]
                let sway = CGFloat(sin(local * 9)) * 2
                let x = mouth.x + side * (4 + flight * 46) + sway
                let y = mouth.y - flight * 22 + CGFloat(heart.height) * p / 2
                CritterArt.draw(heart, in: clipped, anchor: CGPoint(x: x, y: y), ink: CritterArt.heartColor)
            }
        default:
            let back = min(1, (t - 5.6) / 1.2)
            let x = restX + (hidden - restX) * Self.ease(back)
            CritterArt.draw(stride, in: clipped, anchor: CGPoint(x: x, y: feet), flipped: !flip)
        }
    }

    // MARK: - Очки

    private func drawCool(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let p = CritterArt.pixel
        let side = critter.side
        let edge = g.midX + side * g.notchWidth / 2
        let menu = g.notchHeight - 1
        let hidden = CGPoint(x: edge - side * 26, y: menu)
        let ledge = CGPoint(x: edge + side * 24, y: menu)
        // Лежит под самой чёлкой, чуть в сторону от середины, мордочкой
        // наружу: целиком ниже кромки выреза.
        let spot = CGPoint(x: g.midX + side * 22, y: g.notchHeight + 34)
        let clipped = Self.outsideNotch(ctx, g)
        let stride = CritterArt.run[Int(t * 8) % 2]

        /// Очки на котике, смотрящем вправо или влево. Встают на ряды 6–8:
        /// у буханки это четыре ряда над лапами, у бегущего — шесть (под ним
        /// ещё два ряда ног). По ширине — на четыре пикселя вперёд, к мордочке.
        func glasses(at body: CGPoint, facingRight: Bool, running: Bool, drop: CGFloat = 0) {
            let anchor = CGPoint(x: body.x + (facingRight ? 4 : -4) * p,
                                 y: body.y - (running ? 6 : 4) * p - drop)
            CritterArt.draw(CritterArt.glasses, in: clipped, anchor: anchor, flipped: !facingRight)
        }
        func run(from a: CGPoint, to b: CGPoint, _ k: Double, withGlasses: Bool) {
            let k = CGFloat(Self.ease(k))
            let body = CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
            // По горизонтали почти не сдвигается только прыжок вниз-вверх:
            // тогда смотрит, куда смотрел, — наружу.
            let facingRight = abs(b.x - a.x) < 1 ? side > 0 : b.x > a.x
            CritterArt.draw(stride, in: clipped, anchor: body, flipped: !facingRight)
            if withGlasses { glasses(at: body, facingRight: facingRight, running: true) }
        }

        switch t {
        case ..<0.9:
            run(from: hidden, to: ledge, t / 0.9, withGlasses: false)
        case ..<1.5:
            // Спрыгивает под чёлку.
            run(from: ledge, to: spot, (t - 0.9) / 0.6, withGlasses: false)
        case ..<5.8:
            let facingRight = side > 0
            let blink = (1.8..<2.0).contains(t)
            CritterArt.draw(CritterArt.loaf[blink ? 1 : 0], in: clipped, anchor: spot, flipped: !facingRight)
            guard t >= 2.1 else { return }
            // Очки съезжают сверху на мордочку и садятся.
            let drop = CGFloat(1 - Self.ease((t - 2.1) / 0.7)) * 22
            glasses(at: spot, facingRight: facingRight, running: false, drop: drop)
            // Блик: вспыхивает в углу линзы, раскрывается звёздочкой, мерцает
            // и улетает вбок, прочь от чёлки, — не под вырез, где его не видно.
            let local = t - 2.95
            guard local > 0, local < 1.6 else { return }
            let corner = CGPoint(x: spot.x + side * 12 * p, y: spot.y - 7 * p)
            let star: CritterArt.Sprite
            let position: CGPoint
            if local < 0.35 {
                star = CritterArt.sparkle[local < 0.12 ? 0 : 1]
                position = corner
            } else {
                let flight = CGFloat((local - 0.35) / 1.25)
                star = CritterArt.sparkle[Int(local * 8) % 2 == 0 ? 1 : 2]
                position = CGPoint(x: corner.x + side * flight * 56, y: corner.y - flight * 8)
            }
            CritterArt.draw(star, in: clipped,
                            anchor: CGPoint(x: position.x, y: position.y + CGFloat(star.height) * p / 2),
                            ink: CritterArt.sparkleColor)
        case ..<6.3:
            // Запрыгивает обратно на полосу меню — в очках.
            run(from: spot, to: ledge, (t - 5.8) / 0.5, withGlasses: true)
        default:
            run(from: ledge, to: hidden, min(1, (t - 6.3) / 0.7), withGlasses: true)
        }
    }

    // MARK: - Сигарета

    private func drawSmoke(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let p = CritterArt.pixel
        let side = critter.side
        let edge = g.midX + side * g.notchWidth / 2
        let hidden = edge - side * 26
        let restX = edge + side * 60
        let feet = g.notchHeight - 1
        let clipped = Self.outsideNotch(ctx, g)
        let lightAt = 1.6
        let drags: [Double] = [2.6, 4.2, 5.8]
        let leaveAt = 6.8

        // Где котик и какой он сейчас.
        let facingRight: Bool
        let body: CGPoint
        let sprite: CritterArt.Sprite
        switch t {
        case ..<1.2:
            facingRight = side > 0
            body = CGPoint(x: hidden + (restX - hidden) * Self.ease(t / 1.2), y: feet)
            sprite = CritterArt.run[Int(t * 8) % 2]
        case ..<leaveAt:
            facingRight = side > 0
            body = CGPoint(x: restX, y: feet)
            // На затяжке прикрывает глаза.
            let dragging = drags.contains { (0..<0.6).contains(t - $0) }
            sprite = CritterArt.loaf[dragging ? 1 : 0]
        default:
            facingRight = side < 0
            let back = min(1, (t - leaveAt) / 1.2)
            body = CGPoint(x: restX + (hidden - restX) * Self.ease(back), y: feet)
            sprite = CritterArt.run[Int(t * 8) % 2]
        }
        CritterArt.draw(sprite, in: clipped, anchor: body, flipped: !facingRight)
        guard t >= 1.3 else { return }

        func cell(_ column: Int, _ row: Int) -> CGRect {
            CritterArt.cell(column, row, of: sprite, anchor: body, flipped: !facingRight)
        }
        let row = CritterArt.cigaretteRow
        var filter = Path(), paper = Path()
        for column in CritterArt.filterColumns { filter.addRect(cell(column, row)) }
        for column in CritterArt.paperColumns { paper.addRect(cell(column, row)) }
        clipped.fill(filter, with: .color(CritterArt.filterColor))
        clipped.fill(paper, with: .color(CritterArt.paperColor))

        let tip = cell(CritterArt.emberColumn, row)
        let outward: CGFloat = facingRight ? 1 : -1

        // Закуривает: язычок огня пляшет у кончика.
        if (lightAt..<lightAt + 0.8).contains(t) {
            let tall = Int(t * 16) % 2 == 0 ? 3 : 2
            var flame = Path()
            for k in 0..<tall {
                flame.addRect(CGRect(x: tip.minX, y: tip.minY - CGFloat(k) * p, width: p, height: p))
            }
            flame.addRect(CGRect(x: tip.minX + outward * p, y: tip.minY, width: p, height: p))
            clipped.fill(flame, with: .color(CritterArt.flameColor))
        }
        guard t >= lightAt + 0.4 else { return }

        // Уголёк: тлеет, чуть мерцая, и ярко вспыхивает на затяжке.
        let dragging = drags.contains { (0..<0.6).contains(t - $0) }
        let flicker = Int(t * 5) % 3 == 0
        let ember = dragging || (t < lightAt + 0.8 && flicker) ? CritterArt.emberBright
            : (flicker ? CritterArt.emberBright.opacity(0.7) : CritterArt.emberDim)
        clipped.fill(Path(tip), with: .color(ember))

        // Струйка дыма от уголька: клочки рождаются каждую пятую долю
        // секунды, поднимаются, покачиваясь, и тают. Относятся ветром
        // прочь от чёлки — над котиком край экрана.
        var trail = Path()
        let born = lightAt + 0.5
        for k in 0..<40 {
            let start = born + Double(k) * 0.2
            let age = t - start
            guard age > 0, age < 1.6 else { continue }
            let rise = CGFloat(age) * 12
            let sway = CGFloat(sin(age * 5 + Double(k))) * 2
            let x = tip.minX + outward * (CGFloat(age) * 14) + sway
            let y = tip.minY - p - rise
            let size = age > 0.9 ? 2 * p : p
            trail.addRect(CGRect(x: (x / p).rounded() * p, y: (y / p).rounded() * p, width: size, height: size))
        }
        clipped.fill(trail, with: .color(CritterArt.smokeColor.opacity(0.8)))

        // Выдох: после затяжки изо рта выходит клуб — три клочка расходятся
        // и тают.
        let mouth = cell(18, row)
        for drag in drags {
            let age = t - drag - 0.8
            guard age > 0, age < 1.2 else { continue }
            let spread = CGFloat(age) * 10
            let fade = 1 - age / 1.2
            var puff = Path()
            for (dx, dy) in [(0.0, 0.0), (1.0, -0.6), (0.4, 0.5)] {
                let x = mouth.minX + outward * (8 + CGFloat(dx) * spread + CGFloat(age) * 16)
                let y = mouth.minY + CGFloat(dy) * spread - CGFloat(age) * 6
                puff.addRect(CGRect(x: (x / p).rounded() * p, y: (y / p).rounded() * p, width: 2 * p, height: 2 * p))
            }
            clipped.fill(puff, with: .color(CritterArt.smokeColor.opacity(0.85 * fade)))
        }
    }

    // MARK: - Охота на курсор

    private func drawHunt(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let clipped = Self.outsideNotch(ctx, g)
        let menu = g.notchHeight - 1
        let area = CGRect(x: 16, y: menu, width: g.size.width - 32, height: g.size.height - menu - 4)
        // Кончик курсора — лапы котика после прыжка встают чуть ниже него.
        let pointer = critter.pointer
        let target = CGPoint(x: g.midX + pointer.x, y: pointer.y + 10)
        let side = critter.side
        let start = CGPoint(x: g.midX + side * (g.notchWidth / 2 - 26), y: menu)
        let edges = (left: g.midX - g.notchWidth / 2 + 26, right: g.midX + g.notchWidth / 2 - 26)
        let hunt = critter.advanceHunt(to: t, start: start, target: target, area: area,
                                       homes: [CGPoint(x: edges.left, y: menu), CGPoint(x: edges.right, y: menu)])
        guard hunt.visible else { return }
        let sprite: CritterArt.Sprite
        switch hunt.pose {
        case .running: sprite = CritterArt.run[Int(t * 10) % 2]
        case .leaping: sprite = CritterArt.run[0]
        case .sitting: sprite = CritterArt.loaf[(t.truncatingRemainder(dividingBy: 2.4)) < 0.2 ? 1 : 0]
        }
        CritterArt.draw(sprite, in: clipped, anchor: hunt.drawn, flipped: !hunt.facingRight)
    }

    // MARK: - За хвостом

    private func drawChase(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let p = CritterArt.pixel
        let side = critter.side
        let edge = g.midX + side * g.notchWidth / 2
        let far = g.midX - side * g.notchWidth / 2
        let menu = g.notchHeight - 1
        let clipped = Self.outsideNotch(ctx, g)
        let stride = CritterArt.run[Int(t * 10) % 2]
        // Круг под чёлкой: сплюснут, как дорожка, на которую смотрят сверху
        // и чуть сбоку. Дальняя половина уходит под кромку выреза.
        let center = CGPoint(x: g.midX, y: g.notchHeight + 30)
        let radius = CGSize(width: 30, height: 9)
        func onCircle(_ angle: Double) -> CGPoint {
            CGPoint(x: center.x + radius.width * CGFloat(cos(angle)),
                    y: center.y + radius.height * CGFloat(sin(angle)))
        }
        let startAngle = side > 0 ? 0.0 : Double.pi
        // Три с половиной круга — и котик на противоположной стороне.
        let turns = 7 * Double.pi

        func run(from a: CGPoint, to b: CGPoint, _ k: Double) {
            let k = CGFloat(Self.ease(k))
            let x = a.x + (b.x - a.x) * k
            CritterArt.draw(stride, in: clipped, anchor: CGPoint(x: x, y: a.y + (b.y - a.y) * k), flipped: b.x < a.x)
        }

        switch t {
        case ..<0.9:
            // Выбегает из-за края по полосе меню.
            run(from: CGPoint(x: edge - side * 26, y: menu), to: CGPoint(x: edge + side * 24, y: menu), t / 0.9)
        case ..<1.5:
            // Спрыгивает под чёлку, к краю круга.
            run(from: CGPoint(x: edge + side * 24, y: menu), to: onCircle(startAngle), (t - 0.9) / 0.6)
        case ..<5.1:
            // Разгоняется и тормозит: так кружатся за хвостом, а не катаются
            // на карусели.
            let k = Self.ease((t - 1.5) / 3.6)
            let angle = startAngle + side * turns * k
            let point = onCircle(angle)
            // Лицом по ходу: слева направо — как нарисован, обратно — отражён.
            let movingRight = -sin(angle) * side > 0
            CritterArt.draw(stride, in: clipped, anchor: point, flipped: !movingRight)
        case ..<5.9:
            // Догнал — голова кружится: сидит, покачиваясь, над головой спиралька.
            let spot = onCircle(startAngle + side * turns)
            let wobble = CGFloat(sin(t * 14)) * p
            let facingOut = spot.x < g.midX
            CritterArt.draw(CritterArt.loaf[Int(t * 4) % 2], in: clipped,
                            anchor: CGPoint(x: spot.x + wobble, y: spot.y), flipped: facingOut)
            CritterArt.draw(CritterArt.dizzy, in: clipped,
                            anchor: CGPoint(x: spot.x + (facingOut ? -10 : 10), y: spot.y - 30))
        default:
            // Убегает за другой край: вверх на полосу меню и под чёлку.
            let spot = onCircle(startAngle + side * turns)
            let out = CGPoint(x: far - side * 24, y: menu)
            if t < 6.4 {
                run(from: spot, to: out, (t - 5.9) / 0.5)
            } else {
                run(from: out, to: CGPoint(x: far + side * 26, y: menu), (t - 6.4) / 0.8)
            }
        }
    }

    /// Катится и тормозит.
    static func easeOut(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return 1 - (1 - c) * (1 - c)
    }

    // MARK: - Общее

    /// Всё, кроме самой чёлки: кот выходит из-за её края, а не проступает
    /// сквозь неё.
    static func outsideNotch(_ ctx: GraphicsContext, _ g: Geometry) -> GraphicsContext {
        var clipped = ctx
        var region = Path(CGRect(origin: .zero, size: g.size))
        region.addRoundedRect(in: g.notchRect, cornerSize: CGSize(width: 10, height: 10))
        clipped.clip(to: region, style: FillStyle(eoFill: true))
        return clipped
    }

    /// Плавный вход и выход, от нуля до единицы.
    static func ease(_ x: Double) -> Double {
        let clamped = min(1, max(0, x))
        return clamped * clamped * (3 - 2 * clamped)
    }
}
