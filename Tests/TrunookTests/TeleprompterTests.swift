import AppKit
import Foundation
import Testing
@testable import Trunook

@Suite("Телесуфлер")
struct TeleprompterTests {
    private func store() -> TeleprompterStore {
        // Свои настройки, а не общие: тест не должен переписывать скорость,
        // выбранную человеком.
        let defaults = UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!
        return TeleprompterStore(settings: Settings(defaults: defaults))
    }

    /// Ползунок отдаёт дробное значение, а слишком медленная прокрутка
    /// неотличима от неподвижности — потолки нужны с обеих сторон.
    @Test("Скорость не выходит за пределы")
    func скоростьВПределах() {
        let store = store()
        store.speed = 10_000
        #expect(store.speed == TeleprompterStore.maxSpeed)
        store.speed = -5
        #expect(store.speed == TeleprompterStore.minSpeed)
    }

    @Test("Скорость переживает запись и чтение")
    func скоростьХранится() {
        let store = store()
        store.speed = 75
        #expect(store.speed == 75)
    }

    /// Пока поле не привязано, прокручивать нечего: таймер, пущенный
    /// в пустоту, крутился бы шестьдесят раз в секунду без всякого толку.
    @Test("Без поля прокрутка не пускается")
    func безПоляНеКрутим() {
        let store = store()
        store.startScrolling()
        #expect(!store.isScrolling)
    }

    /// Телесуфлер — единственная накладка, которую не убирает ни уход
    /// курсора, ни нажатие мимо: пока читают вслух, в чужом окне работают.
    @Test("Телесуфлер не закрывается сам")
    func неЗакрываетсяСам() {
        #expect(!NotchState.Overlay.teleprompter.closesOnCursorExit)
        #expect(!NotchState.Overlay.teleprompter.closesOnClickOutside)
    }

    @Test("Остальные накладки закрываются нажатием мимо")
    func остальныеЗакрываются() {
        for overlay in NotchState.Overlay.allCases where overlay != .teleprompter {
            #expect(overlay.closesOnClickOutside, "\(overlay) перестала закрываться мимо")
        }
    }

    /// Зона нажатий обязана совпадать с нарисованным — иначе панель видно,
    /// а нажать по ней нельзя.
    @Test("Панель телесуфлера имеет свой размер")
    func размерПанели() {
        let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)
        let size = NotchInputs(overlay: .teleprompter).resolve().size(metrics: metrics)
        #expect(size.width == TeleprompterPanel.width(notchWidth: metrics.notchWidth))
        #expect(size.height == TeleprompterPanel.height(notchHeight: metrics.notchHeight))
    }

    /// Панель выше и шире прочих, и окно обязано её вместить: переросшее
    /// окно обрезает содержимое молча.
    @Test("Окно вмещает панель телесуфлера")
    func окноВмещает() {
        let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)
        #expect(metrics.windowSize.width >= TeleprompterPanel.width(notchWidth: 185))
        #expect(metrics.windowSize.height >= TeleprompterPanel.height(notchHeight: 32))
    }

    /// В крыле телесуфлера семь кнопок — больше, чем у любой другой панели.
    /// При области нажатия в 24 точки прежняя ширина в 560 их уже не вмещала,
    /// и последняя уезжала под вырез, где её не видно и не нажать. Ширина
    /// теперь считается от чёлки, и проверяется это на всех ходовых её
    /// размерах, а не на одном.
    @Test("Ряд кнопок помещается в крыло при любой ширине чёлки")
    func крылоВмещаетКнопки() {
        /// Крыло по тому же расчёту, что и в `NotchPanel`.
        func wing(panelWidth: CGFloat, notchWidth: CGFloat) -> CGFloat {
            let outerInset = NotchStyle.bottomPadding + NotchStyle.shoulderInset
            return (panelWidth - notchWidth) / 2 - outerInset - NotchStyle.notchInset
        }

        for notchWidth in [CGFloat(160), 185, 200, 220] {
            let tele = wing(panelWidth: TeleprompterPanel.width(notchWidth: notchWidth),
                            notchWidth: notchWidth)
            #expect(
                tele >= NotchStyle.wingRow(buttons: 7),
                "чёлка \(notchWidth): крыло телесуфлера \(tele) не вмещает семь кнопок"
            )

            // Буфер проверяется отдельно: у него в крыле, кроме трёх кнопок,
            // стоит подсказка про номерные клавиши, и место под неё меряется
            // по самой длинной строке на ходу — а значит может разъехаться
            // от смены шрифта или набора сочетаний.
            let clip = wing(panelWidth: ClipboardPanel.width(notchWidth: notchWidth),
                            notchWidth: notchWidth)
            #expect(
                clip >= NotchStyle.wingRow(buttons: 3),
                "чёлка \(notchWidth): крыло буфера \(clip) не вмещает три кнопки"
            )
        }
    }

    /// Панели растут вместе с текстом, а вырез прибит к верхней кромке экрана
    /// и обязан на нём помещаться. Проверяется на самой узкой машине с чёлкой
    /// — MacBook Air 13" даёт 1470 точек логической ширины — и при самом
    /// крупном тексте, какой вырезу разрешён.
    @Test("При самом крупном тексте окно выреза помещается на экран")
    func окноПомещаетсяНаЭкран() {
        let defaults = UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!
        let settings = Settings(defaults: defaults)
        settings.textScale = Settings.textScales.max() ?? 200

        // Настройка размера текста до выреза не доходит вовсе: под чёлкой
        // ровно столько места, сколько оставила аппаратная вырезка.
        // Проверка держит именно это — не потолок, а его отсутствие.
        #expect(NotchStyle.textScale == 1, "вырезу вернули масштабирование текста")

        let narrowestScreen: CGFloat = 1470
        let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)
        #expect(
            metrics.windowSize.width <= narrowestScreen,
            "окно \(metrics.windowSize.width) шире самого узкого экрана с чёлкой"
        )
    }

    /// Плашка с подписью значка висит под панелью, и окно обязано оставить
    /// ей место. Проверяется на телесуфлере не случайно: он и самый высокий,
    /// и подписи нужны ему больше всех — шесть значков оформления подряд,
    /// где «Ж» от «К» на глифе размером с букву отличается не сразу.
    @Test("Под самой высокой панелью остаётся место для подписи значка")
    func окноДержитЗапасПодПодпись() {
        let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)
        let panel = TeleprompterPanel.height(notchHeight: 32)
        #expect(metrics.windowSize.height - panel >= NotchHintLayout.reserved)
    }
}
