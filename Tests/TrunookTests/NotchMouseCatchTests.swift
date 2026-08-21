import Testing
@testable import Trunook

@Suite("Прозрачность окна для мыши")
struct NotchMouseCatchTests {
    private func catches(
        drawn: Bool = false,
        cursorOver: Bool = false,
        draggingOut: Bool = false
    ) -> Bool {
        NotchMouseCatch.catchesMouse(
            hasSomethingDrawn: drawn,
            cursorOverVisibleRect: cursorOver,
            isDraggingOut: draggingOut
        )
    }

    /// Главное правило. Непрозрачное окно съедает нажатия во всей рамке —
    /// 560×388 под чёлкой, — а нарисована в ней бывает плашка 233×74.
    /// Полоса вокруг неё обязана оставаться живой: под ней чужие окна,
    /// и человек в них работает.
    @Test("Мимо нарисованного окно нажатий не ест")
    func мимоНарисованногоНеЕст() {
        #expect(!catches(drawn: true, cursorOver: false))
    }

    @Test("По нарисованному попасть можно")
    func поНарисованномуМожно() {
        #expect(catches(drawn: true, cursorOver: true))
    }

    /// Раньше здесь были исключения — «пока открыта накладка» и «пока
    /// наведено», — и каждое выключало полосу вокруг панели. Исключений
    /// больше нет: нажатие мимо панели уходит в чужое приложение, а значит
    /// его видит глобальный монитор и накладка закрывается сама.
    @Test("Исключений из правила нет")
    func безИсключений() {
        #expect(!catches(drawn: false, cursorOver: true))
        #expect(!catches(drawn: false, cursorOver: false))
    }

    /// Свёрнутый вырез нажатий не ждёт: под ним аппаратная чёлка.
    @Test("Свёрнутый вырез прозрачен всегда")
    func свёрнутыйПрозрачен() {
        #expect(!catches(drawn: false, cursorOver: true))
    }

    /// Перетаскивание с полки начинается внутри панели и уводит курсор
    /// за её край. Погасшее на полпути окно оборвало бы его.
    @Test("Пока тащат файл, окно не гаснет")
    func приПеретаскиванииНеГаснет() {
        #expect(catches(drawn: true, cursorOver: false, draggingOut: true))
        #expect(catches(drawn: false, cursorOver: false, draggingOut: true))
    }

    /// Условие, на котором держится сворачивание выреза по уходу из накладки.
    ///
    /// Уход курсора из накладки считается уходом от выреза совсем — вырез
    /// сворачивается, а не показывает то, что было под накладкой. Верно это
    /// ровно потому, что прямоугольник любой накладки накрывает саму чёлку:
    /// выйти из накладки, оставшись на вырезе, нельзя. Узкая панель, добавленная
    /// когда-нибудь позже, это рассуждение молча сломала бы — и вырез начал бы
    /// схлопываться под курсором.
    @Test("Любая накладка шире свёрнутого выреза")
    func накладкиНакрываютЧёлку() {
        let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)
        for overlay in NotchState.Overlay.allCases {
            // Состав задаётся так, чтобы панель была в самом узком своём виде:
            // пустые списки дают наименьшую ширину, какая у неё бывает.
            let size = NotchInputs(overlay: overlay).resolve().size(metrics: metrics)
            #expect(
                size.width >= metrics.closed.width,
                "накладка \(overlay) у́же свёрнутого выреза: \(size.width)"
            )
            #expect(size.height >= metrics.notchHeight, "накладка \(overlay) ниже чёлки")
        }
    }
}
