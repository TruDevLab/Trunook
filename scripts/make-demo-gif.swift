#!/usr/bin/env swift
// Собирает docs/demo.gif из кадров, снятых приложением.
//
// Кадры делает само приложение — снимок собственного слоя, разрешения
// на запись экрана для этого не нужно:
//
//   defaults write com.trunook.Trunook debugWelcomeStep 0
//   defaults write com.trunook.Trunook language en
//   make run
//   swift scripts/debug-event.swift welcome
//   swift scripts/debug-event.swift shotDemo     # 70 кадров, ~22 секунды
//   swift scripts/make-demo-gif.swift            # (или make demo)
//
// Картинка порождается кодом по той же причине, что иконка, звуки и фон
// образа: иначе она устаревает молча. Прежний demo.gif полгода показывал
// сочетание ⌥⌘Space, которого в приложении уже не было, — и заметить это
// было неоткуда.

import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Где приложение оставляет кадры.
let framesDirectory = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent("Library/Logs")
let framePrefix = "Trunook-demo-"

/// Что вырезаем из окна знакомства, в точках снимка (он ретиновый, 1560×1400).
///
/// Берём только демонстрацию выреза с подписью под ней: заголовок и плитки
/// возможностей в анимации не участвуют, а места занимают втрое больше.
let crop = CGRect(x: 280, y: 425, width: 1000, height: 437)

/// Размер готовой картинки. Тот же, что у прежней: README свёрстан под него.
let output = CGSize(width: 595, height: 260)

/// Задержка кадра — шаг съёмки. Семьдесят кадров по 0,315 с складываются
/// в петлю ровно той длины, что и сама демонстрация.
let frameDelay = 0.315

// MARK: - Кадры

let names = ((try? FileManager.default.contentsOfDirectory(atPath: framesDirectory.path)) ?? [])
    .filter { $0.hasPrefix(framePrefix) && $0.hasSuffix(".png") }
    // Имена с ведущими нулями, поэтому обычная сортировка даёт верный порядок.
    .sorted()

guard !names.isEmpty else {
    print("кадров нет: снимите их через `swift scripts/debug-event.swift shotDemo`")
    exit(1)
}

func prepared(_ path: String) -> CGImage? {
    guard let image = NSImage(contentsOfFile: path),
          let full = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let piece = full.cropping(to: crop)
    else { return nil }

    // Уменьшаем сами, а не силами GIF: ImageIO сжимает палитру, но размер
    // кадра берёт как есть, и картинка вышла бы вчетверо тяжелее.
    guard let context = CGContext(
        data: nil,
        width: Int(output.width),
        height: Int(output.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }
    context.interpolationQuality = .high
    context.draw(piece, in: CGRect(origin: .zero, size: output))
    return context.makeImage()
}

// MARK: - Сборка

let destinationURL = URL(fileURLWithPath: "docs/demo.gif")
guard let destination = CGImageDestinationCreateWithURL(
    destinationURL as CFURL,
    UTType.gif.identifier as CFString,
    names.count,
    nil
) else {
    print("не удалось создать \(destinationURL.path)")
    exit(1)
}

// Ноль повторов означает «бесконечно»: петля не должна останавливаться.
CGImageDestinationSetProperties(destination, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
] as CFDictionary)

// Незажатая задержка нужна рядом с обычной: часть просмотрщиков читает
// только её и иначе гонит петлю на предельной скорости.
let frameProperties = [
    kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFDelayTime: frameDelay,
        kCGImagePropertyGIFUnclampedDelayTime: frameDelay,
    ],
] as CFDictionary

var written = 0
for name in names {
    guard let image = prepared(framesDirectory.appendingPathComponent(name).path) else {
        print("кадр не разобрался: \(name)")
        continue
    }
    CGImageDestinationAddImage(destination, image, frameProperties)
    written += 1
}

guard CGImageDestinationFinalize(destination) else {
    print("не удалось записать \(destinationURL.path)")
    exit(1)
}

let bytes = ((try? FileManager.default.attributesOfItem(atPath: destinationURL.path))?[.size] as? Int) ?? 0
let seconds = Double(written) * frameDelay
print(String(
    format: "собрано: %@ — %d кадров, %.0f×%.0f, %.1f с, %.0f КБ",
    destinationURL.path, written, output.width, output.height, seconds, Double(bytes) / 1024
))
