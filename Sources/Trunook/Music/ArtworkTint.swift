import AppKit
import SwiftUI

/// Цвет обложки — тот, которым красится полоса воспроизведения по контуру
/// острова.
///
/// Полоса раньше была белой, и это не выбор, а отсутствие выбора: белым
/// в вырезе набрано вообще всё. Обложка же — единственное цветное пятно
/// в раскрытой панели, и полоса, взявшая её цвет, читается как часть того же
/// трека, а не как ещё один служебный индикатор.
///
/// ## Как выбирается цвет
///
/// Не среднее по картинке: усреднение обложки почти всегда даёт грязно-серый
/// — красное и зелёное в сумме гасят друг друга, и чем пестрее обложка, тем
/// ровнее и безжизненнее выходит средний цвет.
///
/// Вместо этого ищется **преобладающий оттенок**. Картинка ужимается
/// до шестнадцати на шестнадцать, пиксели раскладываются по двенадцати
/// корзинам оттенка, и каждый входит в свою корзину с весом, равным
/// произведению насыщенности на яркость: серый пиксель почти ничего не весит,
/// чистый цвет — почти единицу. Побеждает самая тяжёлая корзина.
///
/// Шестнадцать на шестнадцать — не экономия, а сглаживание: на полном
/// разрешении единичный яркий блик перевешивал бы поле спокойного цвета,
/// занимающее полкартинки.
///
/// ## Почему цвет потом правится
///
/// Найденный оттенок берётся как есть, а насыщенность и яркость поднимаются
/// до порога. Причина в подложке: полоса лежит на чёрном теле выреза, и цвет,
/// на обложке выглядевший глубоким, на чёрном становится грязью. Тёмно-синяя
/// обложка дала бы полосу, неотличимую от самого выреза.
///
/// Оттенок при этом не трогается вовсе — он и есть то, что связывает полосу
/// с обложкой. Меняется только то, что мешает его увидеть.
enum ArtworkTint {
    /// Ниже этой яркости цвет на чёрном не читается.
    private static let minBrightness: Double = 0.82
    /// Ниже этой насыщенности он читается как белый с лёгким налётом цвета.
    private static let minSaturation: Double = 0.55

    /// Сторона уменьшенной картинки, по которой считается оттенок.
    private static let side = 16
    /// Корзин оттенка. Двенадцать — по тридцать градусов на корзину: соседние
    /// оттенки внутри такой корзины глаз читает как один цвет.
    private static let bins = 12

    /// Цвет для полосы. `nil` — обложки нет или она серая, полоса остаётся
    /// белой.
    static func color(from artwork: Data?) -> Color? {
        guard let artwork, let image = NSImage(data: artwork) else { return nil }
        guard let pixels = downscale(image) else { return nil }

        // Вес каждой корзины и сумма составляющих внутри неё. Оттенок
        // складывается через вектор на единичной окружности, а не как число:
        // у оттенка нет начала и конца, и среднее между 350° и 10° по числам
        // дало бы 180° — бирюзовый вместо красного.
        var weight = [Double](repeating: 0, count: bins)
        var hueX = [Double](repeating: 0, count: bins)
        var hueY = [Double](repeating: 0, count: bins)
        var saturation = [Double](repeating: 0, count: bins)
        var brightness = [Double](repeating: 0, count: bins)

        for pixel in pixels {
            let (h, s, b) = pixel
            // Почти чёрное и почти белое оттенка не несут: у первого его
            // не видно, у второго его нет.
            guard b > 0.12, b < 0.97 || s > 0.12 else { continue }
            let w = s * b
            guard w > 0.02 else { continue }

            let bin = min(bins - 1, Int(h * Double(bins)))
            let angle = h * 2 * .pi
            weight[bin] += w
            hueX[bin] += cos(angle) * w
            hueY[bin] += sin(angle) * w
            saturation[bin] += s * w
            brightness[bin] += b * w
        }

        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }),
              weight[best] > 0
        else { return nil }

        let total = weight[best]
        var angle = atan2(hueY[best] / total, hueX[best] / total)
        if angle < 0 { angle += 2 * .pi }

        return Color(
            hue: angle / (2 * .pi),
            saturation: max(minSaturation, saturation[best] / total),
            brightness: max(minBrightness, brightness[best] / total)
        )
    }

    /// Обложка, ужатая до `side × side` и разложенная в оттенок, насыщенность
    /// и яркость.
    ///
    /// Через `CGContext`, а не через `NSImage.draw`: рисование в контекст
    /// заданного размера и есть уменьшение, а результат ложится в буфер,
    /// который можно прочитать по байтам. `NSImage` отдал бы картинку,
    /// у которой пиксели ещё надо доставать.
    private static func downscale(_ image: NSImage) -> [(Double, Double, Double)]? {
        var rect = CGRect(x: 0, y: 0, width: side, height: side)
        guard let source = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let context = CGContext(
                  data: nil,
                  width: side,
                  height: side,
                  bitsPerComponent: 8,
                  bytesPerRow: side * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let buffer = context.data
        else { return nil }

        context.interpolationQuality = .medium
        context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))

        let bytes = buffer.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var result: [(Double, Double, Double)] = []
        result.reserveCapacity(side * side)
        for index in 0..<(side * side) {
            let offset = index * 4
            let alpha = Double(bytes[offset + 3]) / 255
            guard alpha > 0.5 else { continue }
            result.append(hsb(
                r: Double(bytes[offset]) / 255,
                g: Double(bytes[offset + 1]) / 255,
                b: Double(bytes[offset + 2]) / 255
            ))
        }
        return result.isEmpty ? nil : result
    }

    /// Свой перевод в HSB, а не через `NSColor`: тот на каждый пиксель заводит
    /// объект и просит преобразовать цветовое пространство — двести пятьдесят
    /// шесть объектов на обложку там, где хватает арифметики.
    private static func hsb(r: Double, g: Double, b: Double) -> (Double, Double, Double) {
        let high = max(r, g, b)
        let low = min(r, g, b)
        let delta = high - low
        guard delta > 0 else { return (0, 0, high) }

        var hue: Double
        switch high {
        case r: hue = (g - b) / delta
        case g: hue = 2 + (b - r) / delta
        default: hue = 4 + (r - g) / delta
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, delta / high, high)
    }
}
