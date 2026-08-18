// Рисует фон окна установки для образа.
//
//   swift scripts/make-dmg-background.swift 0.5.1
//
// Пишет build/dmg-background.png и build/dmg-background@2x.png. Дальше
// `make dmg` сшивает их в один tiff: Finder берёт из него подходящее
// разрешение сам, и на ретине фон не мылится.
//
// Изображение генерируется кодом по той же причине, что и иконка: силуэт
// выреза и цвета живут в приложении, и держать их картинкой значило бы
// однажды разойтись с ним.

import AppKit
import Foundation

/// Версия приходит из Makefile: держать её здесь строкой значило бы однажды
/// разойтись с той, что стоит в бандле.
let version = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "?"

/// Размер окна в точках. Ровно он же задаётся Finder'у как bounds —
/// фон рисуется один к одному, без растяжения.
let W: CGFloat = 660
let H: CGFloat = 480

// Под значками фон не рисует ничего, и это не лень.
//
// Finder отсчитывает места значков от одного края окна, а фон подкладывает
// от другого: с полосой вкладок значки уезжают вниз ровно на её высоту.
// Высота эта у каждого своя — у кого-то полосы нет вовсе, — и образ её
// не знает. Поэтому всё, что должно совпасть со значками — подложки,
// стрелка, — из фона убрано: совпасть у них не выйдет ни при какой раскладке.
// Смысл вынесен в шапку, где значков нет и разъезжаться нечему.
//
// По той же причине снизу оставлен запас: у кого полосы есть, тот видит
// окно короче, и внизу не должно оказаться ничего важного.

// MARK: - Координаты

/// Макет считается сверху вниз, как в вёрстке, а рисует AppKit снизу вверх.
func flip(_ topDown: CGFloat) -> CGFloat { H - topDown }

func rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
    CGRect(x: x, y: flip(y + height), width: width, height: height)
}

func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: flip(y)) }

// MARK: - Цвета

func white(_ alpha: CGFloat) -> NSColor { NSColor(white: 1, alpha: alpha) }
let violet = NSColor(calibratedRed: 0.62, green: 0.44, blue: 1.0, alpha: 1)

// MARK: - Части

/// Силуэт выреза: сверху вогнутые уголки — переход к кромке окна,
/// снизу выпуклые, как у аппаратной чёлки.
func notchPath(width: CGFloat, height: CGFloat, top: CGFloat, bottom: CGFloat) -> NSBezierPath {
    let left = (W - width) / 2
    let right = left + width
    let path = NSBezierPath()
    path.move(to: point(left, 0))
    path.curve(
        to: point(left + top, top),
        controlPoint1: point(left + top, 0),
        controlPoint2: point(left + top, 0)
    )
    path.line(to: point(left + top, height - bottom))
    path.curve(
        to: point(left + top + bottom, height),
        controlPoint1: point(left + top, height),
        controlPoint2: point(left + top, height)
    )
    path.line(to: point(right - top - bottom, height))
    path.curve(
        to: point(right - top, height - bottom),
        controlPoint1: point(right - top, height),
        controlPoint2: point(right - top, height)
    )
    path.line(to: point(right - top, top))
    path.curve(
        to: point(right, 0),
        controlPoint1: point(right - top, 0),
        controlPoint2: point(right - top, 0)
    )
    path.close()
    return path
}

func centered(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, baseline: CGFloat) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: style,
    ]
    let height = size * 1.4
    (text as NSString).draw(
        in: rect(x: 0, y: baseline - height, width: W, height: height),
        withAttributes: attributes
    )
}

private let stepBadge: CGFloat = 20
private let stepGap: CGFloat = 9
private let stepFont = NSFont.systemFont(ofSize: 12.5, weight: .medium)

private func stepWidth(_ text: String) -> CGFloat {
    stepBadge + stepGap + (text as NSString).size(withAttributes: [.font: stepFont]).width
}

/// Шаг установки: кружок с номером и подпись справа от него.
///
/// Левый край задаётся снаружи и один на все шаги: если центрировать каждый
/// по отдельности, номера встают лесенкой и список перестаёт читаться списком.
func step(_ number: String, _ text: String, left: CGFloat, top: CGFloat) {
    let badge = stepBadge
    let gap = stepGap
    let attributes: [NSAttributedString.Key: Any] = [
        .font: stepFont,
        .foregroundColor: white(0.62),
    ]
    let textWidth = (text as NSString).size(withAttributes: attributes).width

    let circle = rect(x: left, y: top, width: badge, height: badge)
    violet.withAlphaComponent(0.22).setFill()
    NSBezierPath(ovalIn: circle).fill()
    violet.withAlphaComponent(0.55).setStroke()
    let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 0.5, dy: 0.5))
    ring.lineWidth = 1
    ring.stroke()

    let numberStyle = NSMutableParagraphStyle()
    numberStyle.alignment = .center
    (number as NSString).draw(
        in: rect(x: left, y: top + 3.5, width: badge, height: 14),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: white(0.9),
            .paragraphStyle: numberStyle,
        ]
    )

    (text as NSString).draw(
        in: rect(x: left + badge + gap, y: top + 2.5, width: textWidth + 2, height: 16),
        withAttributes: attributes
    )
}

// MARK: - Отрисовка

func draw() {
    // Подложка: почти чёрный градиент, как у плитки иконки.
    NSGradient(
        colors: [
            NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1),
            NSColor(calibratedRed: 0.03, green: 0.03, blue: 0.04, alpha: 1),
        ]
    )?.draw(in: CGRect(x: 0, y: 0, width: W, height: H), angle: -90)

    // Свечение под чёлкой: она иначе висит на ровном фоне пятном.
    NSGradient(colors: [violet.withAlphaComponent(0.16), violet.withAlphaComponent(0)])?
        .draw(
            fromCenter: point(W / 2, 20), radius: 0,
            toCenter: point(W / 2, 20), radius: 300,
            options: []
        )

    NSColor.black.setFill()
    notchPath(width: 180, height: 30, top: 9, bottom: 14).fill()

    centered("Trunook", size: 25, weight: .semibold, color: white(0.95), baseline: 76)
    centered(
        "Динамический вырез для MacBook",
        size: 11.5, weight: .regular, color: white(0.32), baseline: 98
    )

    // Оба шага в шапке, одной колонкой: ниже начинается полоса значков,
    // и туда фону соваться нельзя.
    let first = "Перетащите Trunook в папку «Программы» →"
    let second = "Откройте «Как установить» — иначе macOS не запустит"
    let column = (W - max(stepWidth(first), stepWidth(second))) / 2
    step("1", first, left: column, top: 128)
    step("2", second, left: column, top: 160)

    // Видна не у всех: у кого включена полоса вкладок, низ окна обрезан.
    // Поэтому здесь только подпись, без которой можно обойтись.
    centered("Trunook \(version) · лицензия MIT", size: 10.5, weight: .regular,
             color: white(0.16), baseline: 452)
}

// MARK: - Файлы

func render(scale: CGFloat, to path: String) {
    let pixelsWide = Int(W * scale)
    let pixelsHigh = Int(H * scale)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        FileHandle.standardError.write(Data("не удалось создать растр\n".utf8))
        exit(1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.setShouldAntialias(true)
    // Рисуем в точках, а множитель отдаём контексту: макет один на оба файла.
    context.cgContext.scaleBy(x: scale, y: scale)
    draw()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
    try? data.write(to: URL(fileURLWithPath: path))
    print("нарисовано: \(path) — \(pixelsWide)×\(pixelsHigh)")
}

try? FileManager.default.createDirectory(atPath: "build", withIntermediateDirectories: true)
render(scale: 1, to: "build/dmg-background.png")
render(scale: 2, to: "build/dmg-background@2x.png")
