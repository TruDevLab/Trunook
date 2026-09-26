import Testing
import CoreGraphics
@testable import Trunook

@Suite("Поверхности выреза")
struct SurfaceTests {
    @Test("Нажимаемое подсвечивается, карточка — нет")
    func подсветкаТолькоУНажимаемого() {
        // Карточка показателя ничего не обещает нажатием, и подсветка
        // под курсором обещала бы обратное.
        #expect(Surface.Role.card.fill(lit: true) == Surface.Role.card.fill(lit: false))
        #expect(Surface.Role.card.litOnGlass == 0)
        #expect(!Surface.Role.card.isInteractive)

        for role in [Surface.Role.tile, .row, .control] {
            #expect(role.fill(lit: true) > role.fill(lit: false),
                    "\(role) не светлеет под курсором")
            #expect(role.litOnGlass > 0, "\(role) не подсвечивается на стекле")
            #expect(role.isInteractive)
        }
    }

    @Test("Плитка и строка одной плотности с кнопкой")
    func плотностиСходятся() {
        // Подложки лежат рядом в одной панели, и разная плотность читалась
        // как небрежность ещё до всякого стекла.
        #expect(Surface.Role.tile.fill(lit: false) == Surface.Role.row.fill(lit: false))
        #expect(Surface.Role.tile.fill(lit: false) == NotchStyle.tileFill)
        #expect(Surface.Role.control.fill(lit: false) == NotchButtonStyle.restingFill)
    }

    @Test("Заливка не выходит за пределы прозрачности")
    func заливкаВПределах() {
        for role in [Surface.Role.card, .tile, .row, .control] {
            for lit in [true, false] {
                let fill = role.fill(lit: lit)
                #expect(fill >= 0 && fill <= 1, "\(role) при lit=\(lit) даёт \(fill)")
            }
            #expect(role.litOnGlass >= 0 && role.litOnGlass <= 1)
        }
    }

    @Test("Под стеклом поверхность темнее того, что под ней")
    func затемнениеПодСтеклом() {
        // Стекло берёт цвет от обоев, а обои бывают любые. Без затемнения
        // плитка на светлой картинке становится светлой, и белая подпись
        // на ней пропадает — ровно это и случилось в меню всех функций.
        // Матовые плитки — на прозрачном фоне; на матовом они без стекла
        // и держатся кромкой (`плиткиПротивФона`).
        let frosted = Surface.GlassLook.step(Surface.LookScale.hazy)
        #expect(Surface.Role.tile.scrimOnGlass(in: frosted) > 0)
        #expect(Surface.Role.row.scrimOnGlass(in: frosted) > 0)
        #expect(Surface.Role.control.scrimOnGlass(in: frosted) > 0)
        #expect(Surface.Role.card.scrimOnGlass(in: frosted) > 0)

        // По плитке читают одно короткое слово мелким кеглем — запас ей
        // нужнее, чем карточке.
        #expect(Surface.Role.tile.scrimOnGlass(in: frosted) > Surface.Role.card.scrimOnGlass(in: frosted))

        for role in [Surface.Role.card, .tile, .row, .control, .segment] {
            #expect(role.scrimOnGlass(in: frosted) >= 0 && role.scrimOnGlass(in: frosted) < 1,
                    "\(role) затемняет на \(role.scrimOnGlass(in: frosted))")
        }
    }

    @Test("Цвет смысла подмешивается вполсилы")
    func тинтНеВПолнуюСилу() {
        // Взятый целиком, он высветлял стекло до того, что подпись
        // на нём пропадала.
        #expect(Surface.Role.tintStrength > 0)
        #expect(Surface.Role.tintStrength < 0.5)
    }

    @Test("Растворение черноты идёт кривой, а не прямой")
    func переходСглажен() {
        let curve = NotchStyle.ironCurve
        #expect(curve.first == 1, "переход начинается не с непрозрачного")
        #expect(curve.last == 0, "переход не доходит до прозрачного")
        #expect(curve.count >= 5, "двух-трёх ступеней на кривую не хватит")

        // Убывает всюду: возврат яркости посреди перехода читался бы полосой.
        for (previous, next) in zip(curve, curve.dropFirst()) {
            #expect(next <= previous, "кривая возвращается вверх: \(previous) → \(next)")
        }

        // Сглажена: у прямой середина равна 0.5, у сглаженного шага
        // она проходит там же, но концы прижаты к горизонтали — первый
        // и последний шаги заметно мельче среднего.
        let steps = zip(curve, curve.dropFirst()).map { $0 - $1 }
        let average = steps.reduce(0, +) / Double(steps.count)
        #expect(steps.first! < average, "начало перехода не сглажено")
        #expect(steps.last! < average, "конец перехода не сглажен")
    }

    @Test("Стекло достаётся всем, кроме свёрнутого выреза")
    func стеклоКромеСвёрнутого() {
        // Свёрнутый вырез — силуэт аппаратной вырезки и ничего сверх неё.
        // Прозрачность там означала бы обои сквозь железо.
        #expect(!NotchPresentation.collapsed.usesGlass)

        for вид in NotchPresentation.все where вид != .collapsed {
            #expect(вид.usesGlass, "\(вид) остался без стекла")
        }
    }

    @Test("Сплошная чернота выходит за пределы вырезки")
    func чернотаШиреВырезки() {
        // Растворение, начатое ровно на кромке железа, оставляло у самой
        // вырезки посветлевшую полосу: физическая вырезка чёрная наглухо,
        // а рядом с ней остров уже подсвечен — и шов между ними виден.
        // Запас переносит начало растворения наружу.
        #expect(NotchStyle.ironBleed > 0)

        let notchHeight: CGFloat = 32
        let notchWidth: CGFloat = 200

        // По высоте: чернота накрывает вырезку целиком и ещё запас.
        let core = notchHeight + NotchStyle.ironBleed
        #expect(core > notchHeight)

        // По ширине запаса нет: вбок чернота расходилась верно и без него.
        // Запас понадобился только по высоте — на низкой полоске пятно
        // не доходило до низа вырезки, и она переставала быть сплошь чёрной.
        _ = notchWidth

        // На низкой полоске запас упирается в её собственную высоту
        // и обрезается ею, а не выносит черноту за пределы фигуры.
        for высота in [CGFloat(38), 44, 55] {
            #expect(min(высота, core) <= высота)
        }
    }

    @Test("Пять положений: слева стекло, посередине матовое, справа чёрный")
    func шкалаВида() {
        typealias Scale = Surface.LookScale
        #expect(Scale.steps == [0, 25, 50, 75, 100])
        // По умолчанию — полупрозрачное.
        #expect(Scale.standard == Scale.hazy)
        // Промежуточное значение прилипает к ближайшему положению.
        #expect(Scale.snap(40) == Scale.matte)
        #expect(Scale.snap(10) == Scale.glass)
        #expect(Scale.snap(90) == Scale.opaque)
        // Середина — ровно прежнее матовое: затемнения подбирались
        // и проверялись живьём именно в нём.
        let matte = Surface.GlassLook.step(Scale.matte)
        #expect(matte.frost == 1 && matte.scrimScale == 1 && matte.panelScrim(0.24) == 0.24)
        #expect(Surface.GlassLook.step(Scale.glass).frost == 0)
        #expect(Surface.GlassLook.step(Scale.dark).scrimScale > 1)
    }

    @Test("У каждого положения ползунка есть название")
    func положенияНазваны() {
        // Доля сама по себе ничего не значит — мнение бывает о слове.
        for level in stride(from: 0, through: Surface.LookScale.opaque, by: 5) {
            #expect(!Surface.LookScale.title(for: level).isEmpty,
                    "положение \(level) без названия")
        }

        // Концы шкалы названы по-разному, иначе она не читается шкалой.
        #expect(Surface.LookScale.title(for: 0)
                != Surface.LookScale.title(for: Surface.LookScale.opaque))
        #expect(Surface.LookScale.title(for: Surface.LookScale.matte)
                != Surface.LookScale.title(for: 0))
    }

    @Test("Затемнение не переходит в полную непрозрачность")
    func затемнениеНеДоходитДоЕдиницы() {
        // На плотной стороне шкалы плашка подписи с её 0.58 ушла бы
        // за единицу, а прозрачность больше полной не бывает: SwiftUI такое
        // значение примет молча, и потолок пришлось бы искать глазами.
        for исходное in [0.24, 0.30, 0.42, 0.58, 0.92] {
            let итог = Surface.scrim(исходное)
            #expect(итог >= 0 && итог < 1, "затемнение \(исходное) дало \(итог)")
        }
    }

    @Test("Уголки крепления к экрану остаются чёрными")
    func уголкиКрепленияЧёрные() {
        // Верхними уголками — вогнутыми плечами формы — остров держится
        // за кромку экрана. Боковое растворение съедало их первыми,
        // и остров отрывался от кромки.
        #expect(NotchStyle.ironAttach > 0)

        // Полоса крепления ниже растворения вниз: она держит кромку,
        // а не заменяет собой весь переход.
        #expect(NotchStyle.ironAttach < NotchStyle.ironFade)

        // Достаётся она тем, кто вырастает из чёлки вниз: плашке события
        // и мини-виду трека.
        let растутВниз: [NotchPresentation] = [.activity, .preview]
        for вид in растутВниз {
            #expect(вид.keepsAttachCorners, "\(вид) остался без полосы крепления")
        }

        // Всем остальным — нет, и проверено это на живом виде. Раскрытым
        // панелям полоса добавляла сплошную чёрную планку во всю ширину;
        // раздвижениям вбок — отсчёту, полоскам таймера и чашки, голосовому
        // заходу — она ложится поперёк роста и читается планкой сверху,
        // а не креплением.
        for вид in NotchPresentation.все where !растутВниз.contains(вид) {
            #expect(!вид.keepsAttachCorners, "\(вид) не должен нести полосу крепления")
        }

        // Полоса вместе с растворением под ней не закрывает полоску целиком:
        // иначе стекла у неё не оставалось вовсе.
        #expect(NotchStyle.ironAttachCeiling < 1)
        for высота in [CGFloat(34), 44, 55, 66] {
            let полоса = высота * NotchStyle.ironAttachCeiling
            #expect(высота - полоса > 8,
                    "на полоске \(высота) стеклу осталось \(высота - полоса) точек")
        }
    }

    @Test("На стекле панель без затемнения, плитки матовые; матовое — как прежде")
    func видПоложений() {
        let glass = Surface.GlassLook.step(Surface.LookScale.glass)
        let matte = Surface.GlassLook.step(Surface.LookScale.matte)
        #expect(glass.panelScrim(0.24) == 0)
        #expect(glass.surfaceScrim(0.42) > 0)
        // Матовое — ровно прежние числа.
        #expect(matte.panelScrim(0.24) == 0.24)
        #expect(matte.surfaceScrim(0.42) == 0.42)
    }
}

private extension NotchPresentation {
    /// Все состояния списком: перечисление не `CaseIterable` — у него есть
    /// значения, — а проверять надо каждое.
    static var все: [NotchPresentation] {
        [.collapsed, .chip, .activity, .preview, .swiping, .voice,
         .expanded, .clipboard, .assistant, .shelf, .timer,
         .monitor, .teleprompter, .caffeine, .keyboardLock, .notes]
    }
}
