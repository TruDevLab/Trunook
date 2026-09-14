// Лист кадров погодных сценок — подбирать рисунок глазами, не пересобирая
// приложение: `make weather`, кадры в ~/Library/Logs/Trunook-weather-<сценка>.png,
// каждый миг на тёмном и светлом фоне. Рисунок — из Sources/Trunook/Shell/WeatherArt.swift.
import SwiftUI
import AppKit

let zoom: CGFloat = 2
let notchWidth: CGFloat = 185, notchHeight: CGFloat = 32
let size = CGSize(width: 300, height: 180)

struct Sheet: View {
    let scene: WeatherArt.Scene
    let times: [Double]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(times, id: \.self) { t in
                VStack(spacing: 0) {
                    ForEach([Color(red: 0.12, green: 0.14, blue: 0.2), Color(red: 0.86, green: 0.88, blue: 0.9)], id: \.self) { bg in
                        Canvas { ctx, canvas in
                            var scaled = ctx
                            scaled.scaleBy(x: zoom, y: zoom)
                            let notch = CGRect(x: size.width / 2 - notchWidth / 2, y: 0, width: notchWidth, height: notchHeight)
                            var clipped = scaled
                            var region = Path(CGRect(origin: .zero, size: size))
                            region.addRoundedRect(in: notch, cornerSize: CGSize(width: 10, height: 10))
                            clipped.clip(to: region, style: FillStyle(eoFill: true))
                            WeatherArt.draw(scene, in: clipped, notch: notch, size: size, t: t)
                            scaled.fill(Path(roundedRect: notch.insetBy(dx: 0, dy: -10).offsetBy(dx: 0, dy: -10).union(notch), cornerRadius: 10), with: .color(.black))
                        }
                        .frame(width: size.width * zoom, height: size.height * zoom)
                        .background(bg)
                        .clipped()
                    }
                    Text(String(format: "%.1f с", t)).font(.system(size: 18)).foregroundStyle(.white)
                }
            }
        }
        .padding(6)
        .background(Color(white: 0.3))
    }
}

MainActor.assumeIsolated {
    for scene in WeatherArt.Scene.allCases {
        let d = scene.duration
        let times = scene == .thunder ? [0.8, 1.45, 2.5, 3.8, d - 0.6]
            : [0.5, d * 0.3, d * 0.5, d * 0.75, d - 0.4]
        let renderer = ImageRenderer(content: Sheet(scene: scene, times: times))
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
            print("не отрисовалось"); exit(1)
        }
        try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "-\(scene.rawValue).png"))
    }
}
