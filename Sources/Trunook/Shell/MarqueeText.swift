import SwiftUI
import AppKit

enum TextMeasure {
    /// Ширина строки до вёрстки. Нужна, чтобы заранее решить, поместится ли
    /// текст и какой ширины делать плашку.
    ///
    /// С памятью: расчёт выреза идёт на каждом тике мыши (10 раз в секунду),
    /// и пока горит полоска чашки или таймера, одна и та же «8:88:88»
    /// набиралась CoreText заново каждый тик — в профиле покоя это был
    /// главный расход главного потока (замер 26 сентября). Строк на деле
    /// горсть, поэтому память просто сбрасывается, если разрослась.
    static func width(_ string: String, font: NSFont) -> CGFloat {
        let key = Key(string: string, font: font.fontName, size: font.pointSize)
        lock.lock()
        defer { lock.unlock() }
        if let known = cache[key] { return known }
        let width = (string as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
        if cache.count >= 512 { cache.removeAll(keepingCapacity: true) }
        cache[key] = width
        return width
    }

    private struct Key: Hashable {
        let string: String
        let font: String
        let size: CGFloat
    }

    private static var cache: [Key: CGFloat] = [:]
    private static let lock = NSLock()
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
    /// Бежать и в энергосбережении. Для коротко живущей плашки, текст
    /// которой без прокрутки не прочитать: помощь при письме висит восемь
    /// секунд, и стоящая строка показывала бы обрывок выделенного.
    var scrollsWhenSaving = false

    /// «Уменьшить движение» останавливает прокрутку.
    ///
    /// Бесконечное движение — ровно то, от чего эта настройка защищает,
    /// и своей паузы у бегущей строки нет: остановить её нечем, кроме
    /// как убрать плашку целиком. Строка при этом не пропадает — она
    /// показывается неподвижной и обрезается многоточием.
    @ObservedObject private var motion = MotionPreference.shared
    /// В режиме энергосбережения строка стоит так же, как при «уменьшить
    /// движение» (`ENERGY.md`, Р1).
    @ObservedObject private var power = PowerPreference.shared

    private var textWidth: CGFloat { TextMeasure.width(text, font: font) }
    private var needsScroll: Bool {
        !motion.reduceMotion && (!power.saving || scrollsWhenSaving) && textWidth > availableWidth + 0.5
    }

    var body: some View {
        if needsScroll {
            // Прокрутку крутит Core Animation, а не `TimelineView`
            // (энергоаудит 18 октября). Каждый кадр `TimelineView` — это
            // проход отрисовки всего окна выреза, и в нём заново считаются
            // пружины отблеска у каждой стеклянной кнопки (`Glass.interactive`):
            // плашка помощи при письме с шестью кнопками держала 19% процессора
            // против 3,5% в покое. Анимация слоя идёт в сервере окон —
            // приложение на кадрах не делает ничего.
            MarqueeStrip(
                text: text, font: font, gap: gap, speed: speed,
                startDate: startDate, startDelay: startDelay
            )
            .frame(width: availableWidth, height: Self.lineHeight(font))
            .accessibilityLabel(text)
        } else {
            label
                // Длинную строку без прокрутки надо обрезать, иначе она вылезет
                // за панель: `fixedSize` в бегущем виде разрешал ей быть шире
                // отведённого, а сдвиг возвращал на место. Здесь сдвига нет.
                .frame(width: availableWidth, alignment: alignment)
                .clipped()
        }
    }

    /// Высота строки — та же, что у `Text` этим шрифтом.
    static func lineHeight(_ font: NSFont) -> CGFloat {
        ("Ag" as NSString).size(withAttributes: [.font: font]).height.rounded(.up)
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

}

/// Бегущая строка на слое: текст нарисован один раз двумя копиями через
/// промежуток, слой едет влево бесконечной анимацией и возвращается без шва —
/// вторая копия встаёт ровно на место первой.
///
/// Фаза считается от `startDate`, как и раньше: перерисовка родителя строку
/// не сбрасывает — слой пересобирается только при смене текста или начала.
private struct MarqueeStrip: NSViewRepresentable {
    let text: String
    let font: NSFont
    let gap: CGFloat
    let speed: CGFloat
    let startDate: Date
    let startDelay: TimeInterval

    func makeNSView(context: Context) -> MarqueeStripView { MarqueeStripView() }

    func updateNSView(_ view: MarqueeStripView, context: Context) {
        view.configure(text: text, font: font, gap: gap, speed: speed, startDate: startDate, startDelay: startDelay)
    }
}

final class MarqueeStripView: NSView {
    private let strip = CALayer()
    private var key: String?
    private var setup: (text: String, font: NSFont, gap: CGFloat, speed: CGFloat, startDate: Date, startDelay: TimeInterval)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        strip.anchorPoint = .zero
        layer?.addSublayer(strip)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func configure(text: String, font: NSFont, gap: CGFloat, speed: CGFloat, startDate: Date, startDelay: TimeInterval) {
        setup = (text, font, gap, speed, startDate, startDelay)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let key = "\(text)|\(font.fontName)|\(font.pointSize)|\(startDate.timeIntervalSinceReferenceDate)|\(scale)"
        guard key != self.key else { return }
        self.key = key

        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let width = TextMeasure.width(text, font: font)
        let height = MarqueeText.lineHeight(font)
        let size = CGSize(width: 2 * width + gap, height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            (text as NSString).draw(at: .zero, withAttributes: attributes)
            (text as NSString).draw(at: CGPoint(x: width + gap, y: 0), withAttributes: attributes)
            return true
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strip.contentsScale = scale
        strip.contents = image.layerContents(forContentsScale: scale)
        strip.frame = CGRect(origin: .zero, size: size)
        strip.removeAllAnimations()
        CATransaction.commit()

        let distance = width + gap
        guard distance > 0, speed > 0 else { return }
        let duration = Double(distance / speed)
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = -distance
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        let now = strip.convertTime(CACurrentMediaTime(), from: nil)
        let elapsed = Date().timeIntervalSince(startDate) - startDelay
        if elapsed < 0 {
            animation.beginTime = now - elapsed
        } else {
            animation.beginTime = now
            animation.timeOffset = elapsed.truncatingRemainder(dividingBy: duration)
        }
        strip.add(animation, forKey: "marquee")
    }

    /// Окно сменило плотность пикселей (экран переехал) — перерисовать текст.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let setup else { return }
        key = nil
        configure(text: setup.text, font: setup.font, gap: setup.gap, speed: setup.speed,
                  startDate: setup.startDate, startDelay: setup.startDelay)
    }

    /// Снятый с окна и вернувшийся слой теряет анимации — вернуть.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, let setup else { return }
        key = nil
        configure(text: setup.text, font: setup.font, gap: setup.gap, speed: setup.speed,
                  startDate: setup.startDate, startDelay: setup.startDelay)
    }
}
