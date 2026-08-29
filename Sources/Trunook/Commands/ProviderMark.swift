import TrunookXPC
import SwiftUI
import AppKit

/// Значки провайдеров — нарисованные, а не подобранные из системного набора.
///
/// Подобранные не годятся: в наборе нет ни лам, ни ленивцев, ни китов, а имя
/// провайдера из строки команды убрано — весь ответ на «чьё это» несёт значок.
/// Символ, выбранный по смыслу («молния, потому что быстрый»), отвечает
/// на этот вопрос загадкой: он про свойство, а не про того, кто отвечает.
///
/// Марки упрощены до силуэта нарочно. Значок живёт при кегле 10–11 точек,
/// то есть двадцати с небольшим пикселях: всё, что тоньше штриха, там
/// схлопывается в пятно. Поэтому у ламы нет глаз, а у кита — плавника.
///
/// Рисуются в квадрате 100×100 с началом в левом верхнем углу и отдаются
/// готовым `NSImage` с меткой шаблона. Не `Shape`: тот же значок нужен
/// в выпадающем списке настроек, а `NSMenu` принимает картинку, а не вид —
/// произвольная вёрстка в пункт меню просто не доезжает.
enum ProviderMark {
    /// Готовые картинки: значок рисуется на каждый кадр строки, а строк
    /// в списке столько же, сколько команд.
    private static var cache: [String: NSImage] = [:]

    static func image(for provider: AIProvider, size: CGFloat) -> NSImage {
        let key = provider.rawValue + "@" + String(format: "%.1f", size)
        if let ready = cache[key] { return ready }

        let box = NSSize(width: size, height: size)
        let image = NSImage(size: box, flipped: true) { rect in
            let path = shape(of: provider)
            let scale = min(rect.width, rect.height) / 100
            let move = AffineTransform(scaleByX: scale, byY: scale)
            path.transform(using: move)
            NSColor.black.setFill()
            // Чётно-нечётное заполнение: глаза ленивца и дырка в «q» —
            // это отверстия, а не отдельные фигуры поверх.
            path.windingRule = .evenOdd
            path.fill()
            return true
        }
        // Шаблон: цвет задаёт тот, кто показывает, — в строке приглушённый,
        // в меню системный. Своего цвета у значка нет.
        image.isTemplate = true
        cache[key] = image
        return image
    }

    // MARK: - Сами марки

    private static func shape(of provider: AIProvider) -> NSBezierPath {
        switch provider {
        case .ollama: return llama()
        case .llamaCpp: return llamaHead()
        case .unsloth: return sloth()
        case .deepSeek: return whale()
        case .openAI: return rosette()
        case .anthropic: return burst()
        case .gemini: return star()
        case .groq: return letterQ()
        case .openRouter: return branch()
        case .vllm: return letterV()
        case .lmStudio: return squircleL()
        case .custom: return sliders()
        }
    }

    /// Лама целиком: уши, голова, шея, корпус. Так её и рисует Ollama —
    /// зверь стоит анфас и узнаётся по длинной шее, а не по морде.
    private static func llama() -> NSBezierPath {
        // Уши узкие и близко: разведённые в стороны превращают ламу в зайца —
        // проверено листом марок. Голова у́же корпуса, шея длинная: по этим
        // трём пропорциям зверь и опознаётся, а не по морде, которой
        // при таком размере всё равно не будет.
        let path = NSBezierPath()
        path.append(ear(tipX: 39, tipY: 4, baseX: 43, baseY: 30, width: 9))
        path.append(ear(tipX: 61, tipY: 4, baseX: 57, baseY: 30, width: 9))
        path.append(NSBezierPath(roundedRect: NSRect(x: 38, y: 20, width: 24, height: 30),
                                 xRadius: 11, yRadius: 11))
        path.append(NSBezierPath(roundedRect: NSRect(x: 44, y: 44, width: 12, height: 30),
                                 xRadius: 6, yRadius: 6))
        path.append(NSBezierPath(roundedRect: NSRect(x: 26, y: 66, width: 48, height: 32),
                                 xRadius: 15, yRadius: 15))
        return path
    }

    /// Она же вблизи: у llama.cpp на месте марки та же лама, но головой
    /// в кадре — уши крупнее, шеи нет.
    private static func llamaHead() -> NSBezierPath {
        // Та же лама, но головой в кадре. Уши сведены так же — разведённые
        // читались летучей мышью.
        let path = NSBezierPath()
        path.append(ear(tipX: 33, tipY: 4, baseX: 39, baseY: 34, width: 12))
        path.append(ear(tipX: 67, tipY: 4, baseX: 61, baseY: 34, width: 12))
        path.append(NSBezierPath(roundedRect: NSRect(x: 30, y: 26, width: 40, height: 46),
                                 xRadius: 18, yRadius: 18))
        path.append(NSBezierPath(roundedRect: NSRect(x: 39, y: 60, width: 22, height: 34),
                                 xRadius: 10, yRadius: 10))
        return path
    }

    /// Ухо — каплей: острый кончик и широкое основание.
    private static func ear(
        tipX: CGFloat, tipY: CGFloat, baseX: CGFloat, baseY: CGFloat, width: CGFloat
    ) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: tipX, y: tipY))
        path.curve(to: NSPoint(x: baseX + width / 2, y: baseY),
                   controlPoint1: NSPoint(x: tipX + width, y: tipY + 10),
                   controlPoint2: NSPoint(x: baseX + width / 2, y: baseY - 16))
        path.line(to: NSPoint(x: baseX - width / 2, y: baseY))
        path.curve(to: NSPoint(x: tipX, y: tipY),
                   controlPoint1: NSPoint(x: baseX - width / 2, y: baseY - 18),
                   controlPoint2: NSPoint(x: tipX - width / 3, y: tipY + 12))
        path.close()
        return path
    }

    /// Ленивец: круглая морда и два светлых пятна вокруг глаз — по ним его
    /// и узнают. Пятна сделаны отверстиями: на тёмной панели значок светлый,
    /// и дырка читается как светлое пятно на морде.
    private static func sloth() -> NSBezierPath {
        // Морда шире, чем выше, пятна крупные и вытянутые вбок, рта нет.
        // С круглой мордой и тремя дырками выходил череп — проверено листом.
        let path = NSBezierPath(ovalIn: NSRect(x: 8, y: 18, width: 84, height: 70))
        path.append(NSBezierPath(ovalIn: NSRect(x: 20, y: 36, width: 26, height: 20)))
        path.append(NSBezierPath(ovalIn: NSRect(x: 54, y: 36, width: 26, height: 20)))
        // Носа нет: третья дырка на морде превращала её в череп.
        return path
    }

    /// Кит: тело каплей и раздвоенный хвост. Глаз — отверстием, иначе
    /// силуэт читается как рыба.
    private static func whale() -> NSBezierPath {
        // Тупой лоб, толстое тело и хвост с вырезом посередине. С острым
        // носом и треугольным хвостом выходила рыба — проверено листом:
        // кита от рыбы отличают именно лоб и раздвоенный хвост.
        let path = NSBezierPath()
        // Лоб тупой и высокий, тело толстое, хвост с глубоким вырезом.
        // Вытянутое тело с треугольным хвостом читалось рыбой дважды подряд:
        // кита от неё отличают именно лоб и раздвоенный хвост, а не размер.
        path.move(to: NSPoint(x: 6, y: 48))
        path.curve(to: NSPoint(x: 50, y: 28),
                   controlPoint1: NSPoint(x: 8, y: 26),
                   controlPoint2: NSPoint(x: 28, y: 22))
        path.curve(to: NSPoint(x: 66, y: 46),
                   controlPoint1: NSPoint(x: 60, y: 32),
                   controlPoint2: NSPoint(x: 65, y: 38))
        // Хвост занимает треть длины и разрезан почти до тела: у рыбы
        // он маленький и цельный, и без этого силуэт читался рыбой трижды.
        path.line(to: NSPoint(x: 98, y: 16))
        path.curve(to: NSPoint(x: 76, y: 50),
                   controlPoint1: NSPoint(x: 92, y: 32),
                   controlPoint2: NSPoint(x: 82, y: 42))
        path.line(to: NSPoint(x: 98, y: 88))
        path.curve(to: NSPoint(x: 64, y: 58),
                   controlPoint1: NSPoint(x: 86, y: 80),
                   controlPoint2: NSPoint(x: 72, y: 68))
        path.curve(to: NSPoint(x: 6, y: 48),
                   controlPoint1: NSPoint(x: 42, y: 86),
                   controlPoint2: NSPoint(x: 4, y: 74))
        path.close()
        path.append(NSBezierPath(ovalIn: NSRect(x: 18, y: 44, width: 8, height: 8)))
        return path
    }

    /// Шестиугольное кольцо OpenAI.
    ///
    /// Розетка из лепестков была первой попыткой — и оказалась неотличима
    /// от звезды Anthropic: оба читались как звёздочка. Кольцо ни на что
    /// в наборе не похоже и держит связь с шестиугольным узлом марки.
    private static func rosette() -> NSBezierPath {
        let path = hexagon(radius: 46)
        path.append(hexagon(radius: 26))
        return path
    }

    private static func hexagon(radius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        for corner in 0..<6 {
            let angle = (CGFloat(corner) * 60 - 90) * .pi / 180
            let point = NSPoint(x: 50 + radius * cos(angle), y: 50 + radius * sin(angle))
            corner == 0 ? path.move(to: point) : path.line(to: point)
        }
        path.close()
        return path
    }

    /// Звезда Anthropic: три полосы через центр.
    private static func burst() -> NSBezierPath {
        let path = NSBezierPath()
        for index in 0..<3 {
            let bar = NSBezierPath(roundedRect: NSRect(x: 43.5, y: 8, width: 13, height: 84),
                                   xRadius: 6.5, yRadius: 6.5)
            var turn = AffineTransform(translationByX: 50, byY: 50)
            turn.rotate(byDegrees: CGFloat(index) * 60)
            turn.translate(x: -50, y: -50)
            bar.transform(using: turn)
            path.append(bar)
        }
        return path
    }

    /// Четырёхлучевая звезда Gemini — с вогнутыми боками.
    private static func star() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 50, y: 4))
        path.curve(to: NSPoint(x: 96, y: 50),
                   controlPoint1: NSPoint(x: 56, y: 34),
                   controlPoint2: NSPoint(x: 66, y: 44))
        path.curve(to: NSPoint(x: 50, y: 96),
                   controlPoint1: NSPoint(x: 66, y: 56),
                   controlPoint2: NSPoint(x: 56, y: 66))
        path.curve(to: NSPoint(x: 4, y: 50),
                   controlPoint1: NSPoint(x: 44, y: 66),
                   controlPoint2: NSPoint(x: 34, y: 56))
        path.curve(to: NSPoint(x: 50, y: 4),
                   controlPoint1: NSPoint(x: 34, y: 44),
                   controlPoint2: NSPoint(x: 44, y: 34))
        path.close()
        return path
    }

    /// Буква «q» — по ней и узнаётся Groq: у него марка не картинка,
    /// а собственное начертание имени.
    private static func letterQ() -> NSBezierPath {
        let path = NSBezierPath(ovalIn: NSRect(x: 10, y: 14, width: 60, height: 60))
        path.append(NSBezierPath(ovalIn: NSRect(x: 26, y: 30, width: 28, height: 28)))
        path.append(NSBezierPath(roundedRect: NSRect(x: 58, y: 40, width: 14, height: 54),
                                 xRadius: 7, yRadius: 7))
        return path
    }

    /// Развилка OpenRouter: один запрос уходит нескольким.
    private static func branch() -> NSBezierPath {
        let path = NSBezierPath(roundedRect: NSRect(x: 6, y: 43, width: 44, height: 14),
                                xRadius: 7, yRadius: 7)
        path.append(arm(toX: 92, toY: 20))
        path.append(arm(toX: 92, toY: 80))
        return path
    }

    private static func arm(toX: CGFloat, toY: CGFloat) -> NSBezierPath {
        let length = hypot(toX - 44, toY - 50)
        let bar = NSBezierPath(roundedRect: NSRect(x: 0, y: -7, width: length, height: 14),
                               xRadius: 7, yRadius: 7)
        var turn = AffineTransform(translationByX: 44, byY: 50)
        turn.rotate(byDegrees: atan2(toY - 50, toX - 44) * 180 / .pi)
        bar.transform(using: turn)
        return bar
    }

    /// Буква «V» — марка vLLM.
    private static func letterV() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 8, y: 10))
        path.line(to: NSPoint(x: 30, y: 10))
        path.line(to: NSPoint(x: 50, y: 66))
        path.line(to: NSPoint(x: 70, y: 10))
        path.line(to: NSPoint(x: 92, y: 10))
        path.line(to: NSPoint(x: 60, y: 92))
        path.line(to: NSPoint(x: 40, y: 92))
        path.close()
        return path
    }

    /// Скруглённый квадрат с буквой «L» — так выглядит значок LM Studio
    /// в Dock: приложение, а не сервис.
    private static func squircleL() -> NSBezierPath {
        let path = NSBezierPath(roundedRect: NSRect(x: 6, y: 6, width: 88, height: 88),
                                xRadius: 24, yRadius: 24)
        let letter = NSBezierPath()
        letter.move(to: NSPoint(x: 32, y: 26))
        letter.line(to: NSPoint(x: 46, y: 26))
        letter.line(to: NSPoint(x: 46, y: 60))
        letter.line(to: NSPoint(x: 70, y: 60))
        letter.line(to: NSPoint(x: 70, y: 74))
        letter.line(to: NSPoint(x: 32, y: 74))
        letter.close()
        path.append(letter)
        return path
    }

    /// Ползунки — у кастомного провайдера марки нет и быть не может:
    /// это не сервис, а «настроенное руками».
    private static func sliders() -> NSBezierPath {
        let path = NSBezierPath()
        for (index, knob) in [CGFloat(66), 32, 58].enumerated() {
            let y = 22 + CGFloat(index) * 28
            path.append(NSBezierPath(roundedRect: NSRect(x: 8, y: y - 5, width: 84, height: 10),
                                     xRadius: 5, yRadius: 5))
            path.append(NSBezierPath(ovalIn: NSRect(x: knob - 11, y: y - 11, width: 22, height: 22)))
            path.append(NSBezierPath(ovalIn: NSRect(x: knob - 5, y: y - 5, width: 10, height: 10)))
        }
        return path
    }
}

/// Значок провайдера в вёрстке.
///
/// Обёртка вокруг `ProviderMark`: картинку с меткой шаблона SwiftUI красит
/// текущим цветом, как системный символ, — снаружи значок ничем от него
/// не отличается.
struct ProviderIcon: View {
    let provider: AIProvider
    let size: CGFloat

    var body: some View {
        Image(nsImage: ProviderMark.image(for: provider, size: size))
            .renderingMode(.template)
            .accessibilityHidden(true)
    }
}

extension ProviderMark {
    /// Лист со всеми марками — в двух размерах: в рабочем, где значок живёт,
    /// и крупно, чтобы разглядеть саму форму.
    ///
    /// Иначе марки не проверить: на снимке панели значок занимает двадцать
    /// пикселей, и по нему не понять, лама там или пятно. А понять надо
    /// до того, как это увидит человек.
    static func writeSheet(to url: URL) {
        let providers = AIProvider.allCases
        let rowHeight: CGFloat = 56
        let size = NSSize(width: 420, height: rowHeight * CGFloat(providers.count) + 20)
        let sheet = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            NSRect(origin: .zero, size: size).fill()

            for (index, provider) in providers.enumerated() {
                let y = 10 + CGFloat(index) * rowHeight

                for (offset, side) in [(CGFloat(16), CGFloat(11)), (44, 22), (86, 40)] {
                    let mark = image(for: provider, size: side)
                    let box = NSRect(x: offset, y: y + (rowHeight - side) / 2,
                                     width: side, height: side)
                    tinted(mark, .white).draw(in: box)
                }

                let label = provider.title as NSString
                label.draw(
                    at: NSPoint(x: 150, y: y + rowHeight / 2 - 8),
                    withAttributes: [
                        .font: NSFont.systemFont(ofSize: 13),
                        .foregroundColor: NSColor.white,
                    ]
                )
            }
            return true
        }

        guard let data = sheet.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url)
        DebugLog.write("снимок марок провайдеров: \(url.path)")
    }

    /// Шаблон рисуется чёрным; на чёрном листе его не видно.
    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        let copy = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return copy
    }
}
