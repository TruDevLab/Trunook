import Testing
import AppKit
import SwiftUI
@testable import Trunook

@Suite("Цвет обложки")
struct ArtworkTintTests {
    /// Картинка из сплошного цвета — самый простой случай и самая полезная
    /// проверка: оттенок обязан совпасть, что бы ни делали с насыщенностью
    /// и яркостью.
    private func artwork(_ color: NSColor, size: Int = 64) -> Data {
        let image = NSImage(size: CGSize(width: size, height: size))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        image.unlockFocus()
        return image.tiffRepresentation!
    }

    /// Обложка из двух половин: одна занимает большую часть, вторая — меньшую.
    private func split(major: NSColor, minor: NSColor, minorShare: CGFloat) -> Data {
        let side: CGFloat = 64
        let image = NSImage(size: CGSize(width: side, height: side))
        image.lockFocus()
        major.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        minor.setFill()
        NSRect(x: 0, y: 0, width: side, height: side * minorShare).fill()
        image.unlockFocus()
        return image.tiffRepresentation!
    }

    private func hue(_ color: Color) -> Double {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(color).usingColorSpace(.deviceRGB)!.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Double(h)
    }

    private func brightness(_ color: Color) -> Double {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(color).usingColorSpace(.deviceRGB)!.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Double(b)
    }

    /// Разница оттенков по кругу: у оттенка нет начала и конца, и 0.99 от 0.01
    /// отстоит на две сотых, а не на девяносто восемь.
    private func distance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b)
        return min(d, 1 - d)
    }

    @Test("Оттенок сплошной обложки берётся как есть")
    func сплошнойЦвет() {
        for (name, source) in [
            ("красный", NSColor(hue: 0.0, saturation: 0.8, brightness: 0.7, alpha: 1)),
            ("бирюзовый", NSColor(hue: 0.5, saturation: 0.8, brightness: 0.7, alpha: 1)),
            ("сиреневый", NSColor(hue: 0.75, saturation: 0.8, brightness: 0.7, alpha: 1)),
        ] {
            let tint = ArtworkTint.color(from: artwork(source))
            #expect(tint != nil, "\(name): цвет не найден")
            guard let tint else { continue }
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            source.usingColorSpace(.deviceRGB)!.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            #expect(distance(hue(tint), Double(h)) < 0.05, "\(name): оттенок уехал")
        }
    }

    /// Красное и зелёное поровну в среднем дают серый — ровно то, из-за чего
    /// усреднение и не годится. Побеждать должна большая половина.
    @Test("Побеждает преобладающий цвет, а не среднее")
    func преобладающийЦвет() {
        let red = NSColor(hue: 0.0, saturation: 0.9, brightness: 0.8, alpha: 1)
        let green = NSColor(hue: 0.33, saturation: 0.9, brightness: 0.8, alpha: 1)
        let tint = ArtworkTint.color(from: split(major: red, minor: green, minorShare: 0.25))
        #expect(tint != nil)
        guard let tint else { return }
        #expect(distance(hue(tint), 0.0) < 0.06, "взял не преобладающий цвет")
        #expect(distance(hue(tint), 0.33) > 0.2, "цвет уехал в сторону меньшей доли")
    }

    /// Тёмная обложка на чёрном вырезе неразличима, поэтому яркость поднимается
    /// до порога. Оттенок при этом трогать нельзя — он и связывает полосу
    /// с обложкой.
    @Test("Тёмная обложка даёт различимую полосу")
    func тёмнаяОбложкаПоднимается() {
        let deepBlue = NSColor(hue: 0.62, saturation: 0.9, brightness: 0.18, alpha: 1)
        let tint = ArtworkTint.color(from: artwork(deepBlue))
        #expect(tint != nil)
        guard let tint else { return }
        #expect(brightness(tint) >= 0.8, "полоса осталась тёмной: \(brightness(tint))")
        #expect(distance(hue(tint), 0.62) < 0.05, "оттенок изменили вместе с яркостью")
    }

    /// Серая обложка оттенка не несёт, и выдумывать его нельзя: полоса
    /// остаётся белой.
    @Test("Серая обложка оставляет полосу белой")
    func сераяОбложка() {
        #expect(ArtworkTint.color(from: artwork(NSColor(white: 0.5, alpha: 1))) == nil)
        #expect(ArtworkTint.color(from: artwork(NSColor.black)) == nil)
    }

    @Test("Без обложки цвета нет")
    func безОбложки() {
        #expect(ArtworkTint.color(from: nil) == nil)
        #expect(ArtworkTint.color(from: Data([0, 1, 2, 3])) == nil)
    }
}
