// Рисует иконку приложения и собирает .icns.
//
//   swift scripts/make-icon.swift
//
// Изображение генерируется кодом, а не лежит файлом: иконка — это тот же
// силуэт острова, что рисует само приложение, и держать его в двух местах
// значило бы однажды их разойтись.

import AppKit
import Foundation

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconset = URL(fileURLWithPath: "build/Trunook.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// Силуэт выреза: сверху вогнутые уголки, снизу выпуклые.
func notchPath(in rect: CGRect, topRadius: CGFloat, bottomRadius: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let top = min(topRadius, rect.width / 2)
    let bottom = min(bottomRadius, max(0, (rect.width - 2 * top) / 2), rect.height)

    // Координаты AppKit растут вверх, поэтому «низ» выреза — это minY.
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.curve(
        to: CGPoint(x: rect.minX + top, y: rect.maxY - top),
        controlPoint1: CGPoint(x: rect.minX + top, y: rect.maxY),
        controlPoint2: CGPoint(x: rect.minX + top, y: rect.maxY)
    )
    path.line(to: CGPoint(x: rect.minX + top, y: rect.minY + bottom))
    path.curve(
        to: CGPoint(x: rect.minX + top + bottom, y: rect.minY),
        controlPoint1: CGPoint(x: rect.minX + top, y: rect.minY),
        controlPoint2: CGPoint(x: rect.minX + top, y: rect.minY)
    )
    path.line(to: CGPoint(x: rect.maxX - top - bottom, y: rect.minY))
    path.curve(
        to: CGPoint(x: rect.maxX - top, y: rect.minY + bottom),
        controlPoint1: CGPoint(x: rect.maxX - top, y: rect.minY),
        controlPoint2: CGPoint(x: rect.maxX - top, y: rect.minY)
    )
    path.line(to: CGPoint(x: rect.maxX - top, y: rect.maxY - top))
    path.curve(
        to: CGPoint(x: rect.maxX, y: rect.maxY),
        controlPoint1: CGPoint(x: rect.maxX - top, y: rect.maxY),
        controlPoint2: CGPoint(x: rect.maxX - top, y: rect.maxY)
    )
    path.close()
    return path
}

func render(size: Int) -> Data? {
    let side = CGFloat(size)

    // Растр с точными пикселями, а не `NSImage.lockFocus`: тот рисует
    // в масштабе экрана, и на ретине каждый файл выходил вдвое крупнее
    // своего имени — набор иконок с такими размерами недействителен.
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.cgContext.setShouldAntialias(true)

    // Подложка-скруглённый квадрат по пропорциям системных иконок.
    let inset = side * 0.06
    let plate = CGRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let plateRadius = plate.width * 0.225
    let platePath = NSBezierPath(roundedRect: plate, xRadius: plateRadius, yRadius: plateRadius)

    NSGradient(
        colors: [
            NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.20, alpha: 1),
            NSColor(calibratedRed: 0.04, green: 0.04, blue: 0.05, alpha: 1),
        ]
    )?.draw(in: platePath, angle: -90)

    // Сам остров: белая чёлка, свисающая с верхней кромки подложки.
    let islandWidth = plate.width * 0.62
    let islandHeight = plate.height * 0.30
    let island = CGRect(
        x: plate.midX - islandWidth / 2,
        y: plate.maxY - islandHeight - plate.height * 0.16,
        width: islandWidth,
        height: islandHeight
    )
    NSColor.white.setFill()
    notchPath(
        in: island,
        topRadius: islandHeight * 0.28,
        bottomRadius: islandHeight * 0.42
    ).fill()

    // Точка активности — намёк на то, что остров живой.
    let dot = side * 0.055
    NSColor(calibratedRed: 0.30, green: 0.80, blue: 0.45, alpha: 1).setFill()
    NSBezierPath(ovalIn: CGRect(
        x: plate.midX - dot / 2,
        y: island.minY - dot * 2.0,
        width: dot,
        height: dot
    )).fill()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

for size in sizes {
    guard let data = render(size: size) else {
        print("не удалось нарисовать \(size)")
        exit(1)
    }
    try data.write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))

    // Ретиновые варианты — та же картинка вдвое большего размера.
    if size <= 512, let retina = render(size: size * 2) {
        try retina.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
    }
}

print("иконки нарисованы в \(iconset.path)")
