import SwiftUI

/// Движение выреза: пружины формы, проявление содержимого, каскады.
///
/// Одним местом по той же причине, что и `SymbolSwap`: «уменьшить движение»
/// и отладочное замедление должны действовать на всё разом, а пружины,
/// разбросанные по видам, однажды разошлись бы характером.
///
/// Характер — **Dynamic Island** (просьба пользователя: «как на iPhone»):
/// остров — одно упругое тело, раскрывается с небольшим отскоком,
/// содержимое мягко проявляется из размытия вместе с ним и уходит раньше,
/// чем сжимается форма.
///
/// История: сначала пружина была одна на всё (0.28 / 0.82) — раскрытие
/// за 120–160 мс без перелёта читалось скачком; затем «капля» с раздельными
/// пружинами ширины и высоты и «плюхом» — дёргано. Отказ от неё —
/// у `shape(to:)`.
enum NotchMotion {
    /// Во сколько раз замедлить всё движение выреза — для записи и разбора:
    /// `defaults write com.trunook.Trunook debugSlowMotion 5`. Без него
    /// переход в 150 мс на записи 25 к/с — четыре кадра, судить не по чему.
    static var slowdown: Double {
        max(1, UserDefaults.standard.double(forKey: "debugSlowMotion"))
    }

    static var reduced: Bool { MotionPreference.shared.reduceMotion }

    /// Анимация с поправкой на замедление.
    static func timed(_ animation: Animation) -> Animation {
        let factor = slowdown
        return factor > 1 ? animation.speed(1 / factor) : animation
    }

    // MARK: - Форма

    /// Пружины формы — как у Dynamic Island: **одна** на всю форму, по
    /// длительности и доле отскока, как их задаёт iOS. Остров движется
    /// единым телом: раздельные пружины ширины и высоты («капля», 11 октября)
    /// и «плюх» в конце пользователь назвал дёрганьем — их нет.
    ///
    /// По тому, **куда** идёт остров: раскрываясь — с отскоком около
    /// пятой доли, сворачиваясь — быстрее и почти ровно.
    static func shape(to presentation: NotchPresentation) -> Animation {
        guard !reduced else { return timed(.easeInOut(duration: 0.2)) }
        switch presentation {
        case .collapsed, .swiping, .quickRing: return timed(close)
        case .chip, .voice: return timed(chip)
        case .preview, .activity: return timed(openSmall)
        default: return timed(openPanel)
        }
    }

    // Быстро, но плавно (просьба пользователя: 0.42–0.46 «слишком медленно»):
    // короче, а отскок мягче — при короткой пружине тот же отскок
    // читался бы рывком.
    /// Сворачивание чуть длиннее раскрытия: при 0.28 с форма первые
    /// сорок миллисекунд стояла, а потом разом схлопывалась — на записи
    /// ухода курсора с главного экрана это читалось рывком.
    static let close = Animation.spring(duration: 0.34, bounce: 0.06)
    static let chip = Animation.spring(duration: 0.30, bounce: 0.18)
    static let openSmall = Animation.spring(duration: 0.30, bounce: 0.18)
    static let openPanel = Animation.spring(duration: 0.32, bounce: 0.15)

    /// Кольцо функций: веер выезжает из-под чёлки с отскоком, а убирается
    /// ровно — с отскоком кружки на обратном пути перелетали за чёлку
    /// и выныривали снова.
    static func ring(opening: Bool) -> Animation {
        guard !reduced else { return timed(.easeOut(duration: 0.15)) }
        return timed(opening ? .spring(duration: 0.30, bounce: 0.22) : .spring(duration: 0.22, bounce: 0))
    }

    // MARK: - Содержимое

    /// Насколько содержимое «вышло из чёлки»: 0 — спрятано в ней, 1 — на месте.
    ///
    /// Прозрачность, размытие, масштаб от верхнего края и сдвиг вверх
    /// вместе: одна прозрачность читается как «включилось», а с масштабом
    /// и размытием — как «проявилось из чёлки».
    struct Reveal: ViewModifier {
        let progress: Double
        var anchor: UnitPoint = .top
        var scale: Double = 0.92
        var blur: Double = 10
        var lift: Double = 8

        func body(content: Content) -> some View {
            content
                .opacity(progress)
                .blur(radius: (1 - progress) * blur)
                .scaleEffect(scale + (1 - scale) * progress, anchor: anchor)
                .offset(y: -lift * (1 - progress))
        }
    }

    /// Переход панели внутри острова — на раскрытие, сворачивание и смену
    /// одной панели на другую разом.
    ///
    /// Уход **быстрее формы**: содержимое втягивается, пока остров ещё
    /// большой. Иначе в конце сворачивания два кадра схлопывался пустой
    /// тёмный прямоугольник шире чёлки — на записи это читалось тормозом.
    ///
    /// Полоски в свёрнутой чёлке — свой переход: в высоте чёлки «выход
    /// сверху» не виден, их значки выпрыгивают из середины с перелётом.
    static func panelTransition(for presentation: NotchPresentation) -> AnyTransition {
        guard !reduced else { return .opacity.animation(timed(.easeOut(duration: 0.15))) }
        switch presentation {
        case .chip, .voice:
            return .asymmetric(
                insertion: .modifier(
                    active: Reveal(progress: 0, anchor: .center, scale: 0.6, blur: 4, lift: 0),
                    identity: Reveal(progress: 1, anchor: .center, scale: 0.6, blur: 4, lift: 0)
                ).animation(timed(.spring(duration: 0.28, bounce: 0.24).delay(0.03))),
                removal: .modifier(
                    active: Reveal(progress: 0, anchor: .center, scale: 0.8, blur: 4, lift: 0),
                    identity: Reveal(progress: 1, anchor: .center, scale: 0.8, blur: 4, lift: 0)
                ).animation(timed(.easeIn(duration: 0.08)))
            )
        default:
            return .asymmetric(
                insertion: .modifier(
                    active: Reveal(progress: 0, scale: 0.9, blur: 6, lift: 6),
                    identity: Reveal(progress: 1, scale: 0.9, blur: 6, lift: 6)
                ).animation(timed(.spring(duration: 0.26, bounce: 0).delay(0.03))),
                // Уход — как у Dynamic Island: содержимое сжимается к чёлке
                // вместе с формой и гаснет, почти без размытия. Прежде оно
                // размывалось на месте, пока форма ещё стояла, — кадр
                // большого мутного пятна, потом щелчок.
                removal: .modifier(
                    active: Reveal(progress: 0, scale: 0.82, blur: 2, lift: 14),
                    identity: Reveal(progress: 1, scale: 0.82, blur: 2, lift: 14)
                ).animation(timed(.easeOut(duration: 0.18)))
            )
        }
    }

    // MARK: - Каскады

    /// Шаг каскада: плитки главного экрана, миниатюры в крыльях.
    static let cascadeStep: Double = 0.014
    /// Пружина плитки: встаёт на место почти ровно.
    static let settle = Animation.spring(duration: 0.30, bounce: 0.10)
    /// Пружина значка: выпрыгивает с умеренным перелётом.
    static let pop = Animation.spring(duration: 0.30, bounce: 0.28)

    /// Элемент каскада: проявляется в свою очередь, когда панель показана.
    ///
    /// По признаку `shown`, а не переходом: переход срабатывает только у вида,
    /// который вставили сам, — у плиток внутри вставленной панели он молчит.
    struct Cascade: ViewModifier {
        let index: Int
        let shown: Bool
        var scale: Double = 0.96
        var lift: Double = -6
        /// «Выпрыгнуть» с заметным перелётом — значки и миниатюры, а не плитки.
        var pop = false

        func body(content: Content) -> some View {
            if NotchMotion.reduced {
                content
            } else {
                content
                    .opacity(shown ? 1 : 0)
                    .scaleEffect(shown ? 1 : scale)
                    .offset(y: shown ? 0 : lift)
                    .animation(
                        shown
                            ? NotchMotion.timed((pop ? NotchMotion.pop : NotchMotion.settle)
                                .delay(0.02 + Double(index) * NotchMotion.cascadeStep))
                            : nil,
                        value: shown
                    )
            }
        }
    }
}

extension NotchMotion {
    /// Цифры прокручиваются, а не мигают: температура, письма, дни, вода.
    struct Number<Value: Equatable>: ViewModifier {
        let value: Value

        func body(content: Content) -> some View {
            content
                .contentTransition(NotchMotion.reduced ? .opacity : .numericText())
                .animation(NotchMotion.timed(.snappy(duration: 0.32)), value: value)
        }
    }

    /// Смена содержимого перетеканием: старое растворяется, новое
    /// проявляется — новый трек, другая встреча в строке мини-вида.
    struct Swap<Key: Hashable>: ViewModifier {
        let key: Key
        var alignment: Alignment = .leading

        func body(content: Content) -> some View {
            ZStack(alignment: alignment) {
                content
                    .id(key)
                    .transition(NotchMotion.reduced
                        ? .opacity
                        : .modifier(
                            active: Reveal(progress: 0, anchor: .center, scale: 0.9, blur: 6, lift: 0),
                            identity: Reveal(progress: 1, anchor: .center, scale: 0.9, blur: 6, lift: 0)
                        ))
            }
            .animation(NotchMotion.timed(.spring(response: 0.36, dampingFraction: 0.86)), value: key)
        }
    }
}

extension NotchMotion {
    /// Поворот карточки вокруг вертикальной оси: 0 — лицом, ±90 — ребром.
    struct Turn: ViewModifier {
        let angle: Double

        func body(content: Content) -> some View {
            content
                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .opacity(abs(angle) >= 89 ? 0 : 1)
        }
    }

    /// Смена трека — переворот обложки, как карточки: старая уходит ребром,
    /// новая выходит лицом. Сторона — по перелистыванию: «вперёд» —
    /// карточка уходит влево и приходит справа, «назад» — наоборот.
    /// Новая песня от самого плеера (трек доиграл) — как «вперёд».
    struct Flip<Key: Hashable>: ViewModifier {
        let key: Key
        let forward: Bool

        func body(content: Content) -> some View {
            let sign: Double = forward ? 1 : -1
            ZStack {
                content
                    .id(key)
                    .transition(NotchMotion.reduced
                        ? .opacity
                        : .asymmetric(
                            insertion: .modifier(active: Turn(angle: 90 * sign), identity: Turn(angle: 0))
                                .animation(NotchMotion.timed(.spring(duration: 0.40, bounce: 0.18)
                                    .delay(0.1))),
                            removal: .modifier(active: Turn(angle: -90 * sign), identity: Turn(angle: 0))
                                .animation(NotchMotion.timed(.easeIn(duration: 0.14)))
                        ))
            }
            .animation(NotchMotion.timed(.spring(duration: 0.40, bounce: 0.18)), value: key)
        }
    }

    /// Последнее перелистывание: в какую сторону и когда. Переворот обложки
    /// берёт сторону отсюда, если трек сменился сразу после жеста.
    static var lastSkip: (forward: Bool, at: Date) = (true, .distantPast)

    /// Сторона переворота для только что сменившегося трека.
    static var flipsForward: Bool {
        Date().timeIntervalSince(lastSkip.at) < 3 ? lastSkip.forward : true
    }
}

extension View {
    /// Переворот обложки при смене трека — см. `NotchMotion.Flip`.
    func notchFlip<Key: Hashable>(_ key: Key, forward: Bool = NotchMotion.flipsForward) -> some View {
        modifier(NotchMotion.Flip(key: key, forward: forward))
    }

    func notchNumber<Value: Equatable>(_ value: Value) -> some View {
        modifier(NotchMotion.Number(value: value))
    }

    func notchSwap<Key: Hashable>(_ key: Key, alignment: Alignment = .leading) -> some View {
        modifier(NotchMotion.Swap(key: key, alignment: alignment))
    }

    /// Каскадное проявление — см. `NotchMotion.Cascade`.
    func notchCascade(_ index: Int, shown: Bool, scale: Double = 0.96, lift: Double = -6,
                      pop: Bool = false) -> some View {
        modifier(NotchMotion.Cascade(index: index, shown: shown, scale: scale, lift: lift, pop: pop))
    }
}
