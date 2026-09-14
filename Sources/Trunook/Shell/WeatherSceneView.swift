import SwiftUI

/// Холст погодной сценки поверх выреза. Рисунок — в `WeatherArt`, здесь —
/// где чёлка и который миг. Попаданий не принимает.
struct WeatherSceneView: View {
    @ObservedObject var player: WeatherScenePlayer
    let metrics: NotchMetrics
    /// Неглавное окно или экран без чёлки: сценка живёт в одном вырезе.
    let isHidden: Bool

    var body: some View {
        let scene = isHidden ? nil : player.scene
        // Тридцать кадров, а не пятнадцать, как у кота: капли падают быстро,
        // и на пятнадцати дождь дёргается.
        TimelineView(.animation(minimumInterval: 1 / 30, paused: scene == nil)) { context in
            Canvas { ctx, size in
                guard let scene else { return }
                let t = context.date.timeIntervalSince(player.startedAt)
                let closed = CGSize(width: metrics.notchWidth, height: metrics.notchHeight)
                func island(_ moment: TimeInterval) -> CGRect {
                    let island = player.island(at: moment) ?? closed
                    return CGRect(x: size.width / 2 - island.width / 2, y: 0, width: island.width, height: island.height)
                }
                // Обрезка — по острову сейчас: плашка о погоде шире и ниже
                // чёлки, и под ней капли не видны так же, как под железом.
                let now = island(t)
                var clipped = ctx
                var region = Path(CGRect(origin: .zero, size: size))
                let radius: CGFloat = now.height > metrics.notchHeight + 1 ? 20 : 10
                region.addRoundedRect(in: now, cornerSize: CGSize(width: radius, height: radius))
                clipped.clip(to: region, style: FillStyle(eoFill: true))
                WeatherArt.draw(
                    scene, in: clipped, notch: island(0), size: size, t: t,
                    mirrored: player.mirrored, variant: player.variant, island: island
                )
            }
        }
        .frame(width: WeatherArt.canvasSize.width, height: WeatherArt.canvasSize.height)
        .opacity(scene == nil ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
