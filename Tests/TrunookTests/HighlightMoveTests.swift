import Testing
@testable import Trunook

@Suite("Шаг подсветки по списку")
struct HighlightMoveTests {
    private let list = [10, 20, 30]

    @Test("Первое ↓ ставит подсветку сверху, первое ↑ — снизу")
    func firstStepLandsOnEdge() {
        #expect(HighlightMove.next(from: nil, in: list, offset: 1) == 10)
        #expect(HighlightMove.next(from: nil, in: list, offset: -1) == 30)
    }

    @Test("Шаг ведёт на соседнюю строку")
    func stepsToNeighbour() {
        #expect(HighlightMove.next(from: 20, in: list, offset: 1) == 30)
        #expect(HighlightMove.next(from: 20, in: list, offset: -1) == 10)
    }

    @Test("У края подсветка стоит, а не уходит по кругу")
    func stopsAtEdges() {
        #expect(HighlightMove.next(from: 30, in: list, offset: 1) == 30)
        #expect(HighlightMove.next(from: 10, in: list, offset: -1) == 10)
    }

    @Test("В пустом списке подсветке стоять негде")
    func emptyListHasNoHighlight() {
        #expect(HighlightMove.next(from: nil, in: [Int](), offset: 1) == nil)
    }

    @Test("Подсветка на выбывшей строке начинает с края")
    func goneEntryStartsOver() {
        // Строка истории уходит по сроку хранения, команду удаляют
        // в настройках — а подсветка на ней остаётся.
        #expect(HighlightMove.next(from: 99, in: list, offset: 1) == 10)
        #expect(HighlightMove.next(from: 99, in: list, offset: -1) == 30)
    }
}
