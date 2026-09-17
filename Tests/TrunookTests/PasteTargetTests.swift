import Foundation
import Testing
@testable import Trunook

/// Выбор поля, куда ляжет вставка.
///
/// Проверка нужна потому, что промах здесь молчаливый и обидный: текст уйдёт
/// в строку поиска вместо строки сообщения, и человек увидит это, только
/// перечитав чужое окно.
@Suite("Куда вставлять")
struct PasteTargetTests {
    private func rect(_ y: CGFloat, _ width: CGFloat = 400, _ height: CGFloat = 40) -> CGRect {
        CGRect(x: 0, y: y, width: width, height: height)
    }

    @Test("Берётся самое нижнее поле")
    func самоеНижнее() {
        // В чате, письме и заметке поле ввода стоит внизу, а всё, что выше,
        // — поиск, заголовок и боковые списки.
        let fields = [rect(40), rect(600), rect(320)]
        #expect(PasteTarget.best(of: fields) { $0 } == rect(600))
    }

    @Test("Равные по низу разводит площадь")
    func равныеПоНизу() {
        // Рядом со строкой сообщения бывает однострочное поле: у поля ввода
        // площадь больше.
        let small = CGRect(x: 0, y: 600, width: 80, height: 20)
        let big = CGRect(x: 0, y: 600, width: 400, height: 60)
        #expect(PasteTarget.best(of: [small, big]) { $0 } == big)
        #expect(PasteTarget.best(of: [big, small]) { $0 } == big)
    }

    @Test("Настоящая роль важнее положения")
    func рольВажнееПоложения() {
        // `AXGroup` с записываемым значением — догадка: в вебе так выглядит
        // и поле ввода, и невидимая заготовка. Объявленное полем важнее,
        // даже если стоит выше.
        struct Candidate { let frame: CGRect; let named: Bool }
        let group = Candidate(frame: rect(900), named: false)
        let field = Candidate(frame: rect(200), named: true)
        let best = PasteTarget.best(of: [group, field], frame: { $0.frame }, isNamedField: { $0.named })
        #expect(best?.frame == rect(200))
    }

    @Test("Поле за краем окна не считается полем")
    func заКраемОкна() {
        // Поймано на браузере: среди восьмидесяти девяти «полей» страницы
        // выбралось 10×8 над верхней кромкой окна.
        let window = CGRect(x: 0, y: 0, width: 1200, height: 800)
        #expect(PasteTarget.fits(rect(400), in: window))
        #expect(!PasteTarget.fits(CGRect(x: 0, y: -8, width: 10, height: 8), in: window))
        #expect(!PasteTarget.fits(CGRect(x: 0, y: 2000, width: 400, height: 40), in: window))
    }

    @Test("Слишком мелкое полем не считается")
    func слишкомМелкое() {
        #expect(!PasteTarget.fits(CGRect(x: 0, y: 100, width: 10, height: 8), in: nil))
        #expect(!PasteTarget.fits(CGRect(x: 0, y: 100, width: 400, height: 6), in: nil))
        #expect(PasteTarget.fits(CGRect(x: 0, y: 100, width: 80, height: 20), in: nil))
    }

    @Test("Рамки окна нет — судим по одному размеру")
    func безРамкиОкна() {
        // У окна без рамки (а такое бывает у чужих) остаётся хотя бы
        // проверка размера: без неё вернулись бы невидимые заготовки.
        #expect(PasteTarget.fits(rect(400), in: nil))
        #expect(!PasteTarget.fits(CGRect(x: 0, y: 400, width: 4, height: 4), in: nil))
    }

    @Test("Пустой список не даёт поля")
    func пустойСписок() {
        #expect(PasteTarget.best(of: [CGRect]()) { $0 } == nil)
    }

    @Test("Одно поле берётся как есть")
    func одноПоле() {
        #expect(PasteTarget.best(of: [rect(10)]) { $0 } == rect(10))
    }
}
