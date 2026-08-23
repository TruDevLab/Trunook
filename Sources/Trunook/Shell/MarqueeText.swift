import SwiftUI
import AppKit

enum TextMeasure {
    /// Ширина строки до вёрстки. Нужна, чтобы заранее решить, поместится ли
    /// текст и какой ширины делать плашку.
    static func width(_ string: String, font: NSFont) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }
}

/// Однострочный текст, который едет справа налево, если не помещается.
///
/// Когда текст умещается — он просто центрируется, без движения: бегущая
/// строка там, где она не нужна, только раздражает.
///
/// Смещение вычисляется из времени, а не хранится в состоянии представления.
/// Причина практическая: `@State` в этом SDK реализован макросом, а плагин
/// `SwiftUIMacros` поставляется только с Xcode, которого на машине нет.
/// Побочная выгода — прокрутка не сбивается, когда родитель перерисовывается:
/// точка отсчёта привязана к моменту появления события, а не к жизни вьюхи.
struct MarqueeText: View {
    let text: String
    let font: NSFont
    let availableWidth: CGFloat
    /// Момент, от которого отсчитывается прокрутка.
    let startDate: Date

    /// Промежуток между концом строки и началом её копии.
    var gap: CGFloat = 36
    /// Точек в секунду.
    var speed: CGFloat = 42
    /// Пауза перед началом движения, чтобы успеть прочитать начало.
    var startDelay: TimeInterval = 0.5

    /// «Уменьшить движение» останавливает прокрутку.
    ///
    /// Бесконечное движение — ровно то, от чего эта настройка защищает,
    /// и своей паузы у бегущей строки нет: остановить её нечем, кроме
    /// как убрать плашку целиком. Строка при этом не пропадает — она
    /// показывается неподвижной и обрезается многоточием.
    @ObservedObject private var motion = MotionPreference.shared

    private var textWidth: CGFloat { TextMeasure.width(text, font: font) }
    private var needsScroll: Bool {
        !motion.reduceMotion && textWidth > availableWidth + 0.5
    }

    var body: some View {
        if needsScroll {
            TimelineView(.animation) { context in
                // Вторая копия строки идёт следом, чтобы прокрутка была бесшовной.
                HStack(spacing: gap) {
                    label
                    label
                }
                .offset(x: offset(at: context.date))
            }
            .frame(width: availableWidth, alignment: .leading)
            .clipped()
        } else {
            label
                // Длинную строку без прокрутки надо обрезать, иначе она вылезет
                // за панель: `fixedSize` в бегущем виде разрешал ей быть шире
                // отведённого, а сдвиг возвращал на место. Здесь сдвига нет.
                .frame(width: availableWidth, alignment: alignment)
                .clipped()
        }
    }

    /// Помещающаяся строка центруется, обрезанная равняется по левому краю:
    /// у обрезанной начало важнее середины.
    private var alignment: Alignment {
        textWidth > availableWidth + 0.5 ? .leading : .center
    }

    private var label: some View {
        Text(text)
            .font(Font(font))
            .lineLimit(1)
            .fixedSize()
    }

    private func offset(at date: Date) -> CGFloat {
        let elapsed = max(0, date.timeIntervalSince(startDate) - startDelay)
        let distance = textWidth + gap
        guard distance > 0 else { return 0 }
        return -CGFloat((elapsed * Double(speed)).truncatingRemainder(dividingBy: Double(distance)))
    }
}
