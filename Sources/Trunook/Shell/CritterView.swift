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

    static let canvasSize = CGSize(width: 480, height: 120)


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
                case .yawn: drawYawn(in: &ctx, geometry, t: t)
                case .yarn: drawYarn(in: &ctx, geometry, t: t)
                case .angry: drawAngry(in: &ctx, geometry, t: t)
                }
            }
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .opacity(act == nil ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Где чёлка на холсте.
    private struct Geometry {
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

    // MARK: - Зевок

    private func drawYawn(in ctx: inout GraphicsContext, _ g: Geometry, t: TimeInterval) {
        let duration = NotchCritter.Act.yawn.duration
        let p = CritterArt.pixel
        let reach = min(Self.ease(t / 0.5), Self.ease((duration - t) / 0.5))
        guard reach > 0.01 else { return }
        let stage: Int
        switch t {
        case 1.2..<1.5, 2.8..<3.1: stage = 1
        case 1.5..<2.8: stage = 2
        default: stage = 0
        }
        let sprite = CritterArt.yawn(stage: stage, look: stage == 0 ? Int((critter.gaze.x * 3).rounded()) : 0)
        // Высота — по закрытому рту: челюсть опускается вниз, а голова
        // не подпрыгивает вверх вместе с ней.
        let height = CGFloat(CritterArt.yawn(stage: 0, look: 0).height) * p
        let top = g.notchHeight - p - (1 - CGFloat(reach)) * height
        let room = g.notchWidth / 2 - CGFloat(sprite.width) * p / 2 - 6
        let x = g.midX + max(-room, min(room, critter.gaze.x * g.notchWidth))
        CritterArt.draw(sprite, in: Self.outsideNotch(ctx, g),
                        anchor: CGPoint(x: x, y: top + CGFloat(sprite.height) * p))
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
            // Трясёт кулаком шесть раз в секунду и сердито подпрыгивает
            // на пиксель вместе с каждым взмахом.
            let shake = Int(t * 6) % 2
            let hop = shake == 0 ? p : 0
            CritterArt.draw(CritterArt.angry[shake], in: clipped,
                            anchor: CGPoint(x: restX, y: feet - hop), flipped: flip)
            // Знак злости мигает над головой со стороны, свободной от кулака.
            if Int(t * 3) % 2 == 0 {
                let mark = CGPoint(x: restX - side * 18, y: 14)
                CritterArt.draw(CritterArt.anger, in: clipped, anchor: mark)
            }
        default:
            let back = min(1, (t - 5.2) / 1.2)
            let x = restX + (hidden - restX) * Self.ease(back)
            CritterArt.draw(stride, in: clipped, anchor: CGPoint(x: x, y: feet), flipped: !flip)
        }
    }

    /// Катится и тормозит.
    private static func easeOut(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return 1 - (1 - c) * (1 - c)
    }

    // MARK: - Общее

    /// Всё, кроме самой чёлки: кот выходит из-за её края, а не проступает
    /// сквозь неё.
    private static func outsideNotch(_ ctx: GraphicsContext, _ g: Geometry) -> GraphicsContext {
        var clipped = ctx
        var region = Path(CGRect(origin: .zero, size: g.size))
        region.addRoundedRect(in: g.notchRect, cornerSize: CGSize(width: 10, height: 10))
        clipped.clip(to: region, style: FillStyle(eoFill: true))
        return clipped
    }

    /// Плавный вход и выход, от нуля до единицы.
    private static func ease(_ x: Double) -> Double {
        let clamped = min(1, max(0, x))
        return clamped * clamped * (3 - 2 * clamped)
    }
}
