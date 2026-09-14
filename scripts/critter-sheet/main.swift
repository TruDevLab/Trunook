// Лист кадров кота в чёлке — подбирать рисунок глазами, не пересобирая
// приложение: `make critter`, кадры в ~/Library/Logs/Trunook-critter-N.png
// (0 — хвост, 1 — котик, 2 — мордочка, 3 — уши и лапа, 4 — сон, зевок, клубок, 5 — зевок и злой котик), каждый на тёмном и светлом фоне.
// Рисунок берётся из Sources/Trunook/Shell/CritterArt.swift как есть.
import SwiftUI
import AppKit

let zoom: CGFloat = 5
let notchWidth: CGFloat = 185, notchHeight: CGFloat = 32

typealias Frame = (GraphicsContext, CGSize) -> Void

func notch(_ ctx: GraphicsContext, _ size: CGSize) {
    ctx.fill(Path(roundedRect: CGRect(x: size.width / 2 - notchWidth / 2, y: -10, width: notchWidth, height: notchHeight + 10),
                  cornerRadius: 10), with: .color(.black))
}

struct Sheet: View {
    let frames: [Frame]
    let size: CGSize
    var body: some View {
        HStack(spacing: 6) {
            ForEach(frames.indices, id: \.self) { i in
                VStack(spacing: 0) {
                    ForEach([Color(red: 0.12, green: 0.14, blue: 0.2), Color(red: 0.86, green: 0.88, blue: 0.9)], id: \.self) { bg in
                        Canvas { ctx, canvas in
                            var scaled = ctx
                            scaled.scaleBy(x: zoom, y: zoom)
                            frames[i](scaled, CGSize(width: canvas.width / zoom, height: canvas.height / zoom))
                        }
                        .frame(width: size.width * zoom, height: size.height * zoom)
                        .background(bg)
                        .clipped()
                    }
                }
            }
        }
        .padding(6)
        .background(Color(white: 0.5))
    }
}

let tail: [Frame] = [0.0, 0.6, 1.2, 1.8, 2.4].map { t in
    { ctx, size in
        notch(ctx, size)
        let (sprite, root) = CritterArt.hangingTail(time: t)
        let anchorX = size.width / 2 + 40 + CGFloat(sprite.width / 2 - root) * CritterArt.pixel
        CritterArt.draw(sprite, in: ctx, anchor: CGPoint(x: anchorX, y: notchHeight - 2 + CGFloat(sprite.height) * CritterArt.pixel))
        notch(ctx, size)
    }
}
let cat: [Frame] = [
    { ctx, s in CritterArt.draw(CritterArt.run[0], in: ctx, anchor: CGPoint(x: s.width / 2, y: 36)) },
    { ctx, s in CritterArt.draw(CritterArt.run[1], in: ctx, anchor: CGPoint(x: s.width / 2, y: 36)) },
    { ctx, s in CritterArt.draw(CritterArt.run[0], in: ctx, anchor: CGPoint(x: s.width / 2, y: 36), flipped: true) },
    { ctx, s in CritterArt.draw(CritterArt.loaf[0], in: ctx, anchor: CGPoint(x: s.width / 2, y: 36)) },
    { ctx, s in CritterArt.draw(CritterArt.loaf[1], in: ctx, anchor: CGPoint(x: s.width / 2, y: 36)) },
]
let eyes: [Frame] = [(2, 0), (2, -2), (2, 2), (1, 0), (0, 0)].map { open, look in
    { ctx, size in
        let sprite = CritterArt.peek(open: open, look: look)
        CritterArt.draw(sprite, in: ctx, anchor: CGPoint(x: size.width / 2, y: notchHeight - 2 + CGFloat(sprite.height) * CritterArt.pixel))
        notch(ctx, size)
    }
}

let more: [Frame] = [
    { ctx, s in CritterArt.draw(CritterArt.ears(twitch: false, blink: false), in: ctx, anchor: CGPoint(x: s.width / 2, y: 36)) },
    { ctx, s in CritterArt.draw(CritterArt.ears(twitch: true, blink: false), in: ctx, anchor: CGPoint(x: s.width / 2, y: 36)) },
    { ctx, s in CritterArt.draw(CritterArt.ears(twitch: false, blink: true), in: ctx, anchor: CGPoint(x: s.width / 2, y: 36)) },
    { ctx, s in CritterArt.draw(CritterArt.paw(lean: 0), in: ctx, anchor: CGPoint(x: s.width / 2, y: 36)) },
    { ctx, s in CritterArt.draw(CritterArt.paw(lean: -2), in: ctx, anchor: CGPoint(x: s.width / 2, y: 36)) },
    { ctx, s in CritterArt.draw(CritterArt.paw(lean: 2), in: ctx, anchor: CGPoint(x: s.width / 2, y: 36)) },
]
let rest: [Frame] = [
    { ctx, s in
        CritterArt.draw(CritterArt.sleeping[0], in: ctx, anchor: CGPoint(x: s.width / 2 - 6, y: 38))
        CritterArt.draw(CritterArt.z[0], in: ctx, anchor: CGPoint(x: s.width / 2 + 22, y: 22))
        CritterArt.draw(CritterArt.z[1], in: ctx, anchor: CGPoint(x: s.width / 2 + 30, y: 10))
    },
    { ctx, s in CritterArt.draw(CritterArt.sleeping[1], in: ctx, anchor: CGPoint(x: s.width / 2 - 6, y: 38)) },
    { ctx, s in CritterArt.draw(CritterArt.yawn(stage: 1, look: 0), in: ctx, anchor: CGPoint(x: s.width / 2, y: 36)) },
    { ctx, s in CritterArt.draw(CritterArt.yawn(stage: 2, look: 0), in: ctx, anchor: CGPoint(x: s.width / 2, y: 36)) },
    { ctx, s in
        CritterArt.draw(CritterArt.yarn(frame: 0), in: ctx, anchor: CGPoint(x: s.width / 2 - 10, y: 36))
        CritterArt.draw(CritterArt.yarn(frame: 1), in: ctx, anchor: CGPoint(x: s.width / 2 + 10, y: 36))
    },
]

let mood: [Frame] = [
    { ctx, s in CritterArt.draw(CritterArt.yawn(stage: 0, look: 0), in: ctx, anchor: CGPoint(x: s.width / 2, y: 36)) },
    { ctx, s in CritterArt.draw(CritterArt.yawn(stage: 1, look: 0), in: ctx, anchor: CGPoint(x: s.width / 2, y: 36)) },
    { ctx, s in CritterArt.draw(CritterArt.yawn(stage: 2, look: 0), in: ctx, anchor: CGPoint(x: s.width / 2, y: 40)) },
    { ctx, s in
        CritterArt.draw(CritterArt.angry[0], in: ctx, anchor: CGPoint(x: s.width / 2 + 4, y: 40))
        CritterArt.draw(CritterArt.anger, in: ctx, anchor: CGPoint(x: s.width / 2 - 16, y: 14))
    },
    { ctx, s in CritterArt.draw(CritterArt.angry[1], in: ctx, anchor: CGPoint(x: s.width / 2 + 4, y: 40)) },
]

MainActor.assumeIsolated {
    let sheets: [([Frame], CGSize)] = [(tail, CGSize(width: 120, height: 110)), (cat, CGSize(width: 60, height: 44)), (eyes, CGSize(width: 110, height: 56)), (more, CGSize(width: 50, height: 44)), (rest, CGSize(width: 70, height: 44)), (mood, CGSize(width: 60, height: 48))]
    for (i, sheet) in sheets.enumerated() {
        let renderer = ImageRenderer(content: Sheet(frames: sheet.0, size: sheet.1))
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
            print("не отрисовалось"); exit(1)
        }
        try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "-\(i).png"))
    }
}
