import CoreGraphics
import Foundation

/// Раскладка плиток главного экрана по клеткам.
///
/// Без единого обращения к SwiftUI и к службам: где стоит плитка — вопрос
/// арифметики, и его одинаково задают вёрстка выреза, расчёт размера окна
/// и макет в настройках. Посчитанное трижды разошлось бы, как однажды
/// разошлись вёрстка и зона нажатий.
struct HomeGrid: Equatable {
    struct Placement: Equatable, Identifiable {
        let widget: HomeWidget
        let column: Int
        let row: Int

        var id: Int { widget.id }
    }

    static let columns = 4
    /// Потолок в четыре ряда: панель растёт вниз, поверх чужой работы,
    /// и пятый ряд уже закрывал бы треть экрана ноутбука.
    static let maxRows = 4

    let placements: [Placement]
    /// Сколько рядов занято. Ноль — плиток нет вовсе.
    let rows: Int
    /// Не поместившиеся. В вырезе не рисуются, в настройках помечены.
    let overflow: [HomeWidget]

    /// Плотная укладка: каждая плитка встаёт в первое свободное место,
    /// считая слева направо и сверху вниз.
    ///
    /// Не «строго по порядку», а первым подходящим местом: иначе рядом
    /// с плиткой 2×2 оставалась бы дыра в две клетки, куда следующая
    /// маленькая плитка не зашла бы только потому, что стоит в списке позже.
    static func place(
        _ widgets: [HomeWidget],
        columns: Int = HomeGrid.columns,
        maxRows: Int = HomeGrid.maxRows
    ) -> HomeGrid {
        // Последняя укладка запоминается: высоту главного экрана спрашивает
        // расчёт выреза на каждом тике опроса мыши, а раскладка меняется
        // только руками в настройках. Укладка заново была самой дорогой
        // частью тика (`ENERGY.md`, О3). Функция чистая — запомненное
        // по тем же входам и есть ответ.
        let key = PlaceKey(widgets: widgets, columns: columns, maxRows: maxRows)
        lastPlacedLock.lock()
        defer { lastPlacedLock.unlock() }
        if let last = lastPlaced, last.key == key { return last.grid }
        let grid = pack(widgets, columns: columns, maxRows: maxRows)
        lastPlaced = (key, grid)
        return grid
    }

    private struct PlaceKey: Equatable {
        let widgets: [HomeWidget]
        let columns: Int
        let maxRows: Int
    }

    /// Под замком: в приложении раскладку спрашивают с главного потока,
    /// но тесты идут параллельно.
    private static var lastPlaced: (key: PlaceKey, grid: HomeGrid)?
    private static let lastPlacedLock = NSLock()

    private static func pack(_ widgets: [HomeWidget], columns: Int, maxRows: Int) -> HomeGrid {
        var taken = Array(repeating: Array(repeating: false, count: columns), count: maxRows)
        var placements: [Placement] = []
        var overflow: [HomeWidget] = []
        var rows = 0

        for widget in widgets {
            let width = min(widget.size.columns, columns)
            let height = widget.size.rows
            guard let spot = firstFree(width: width, height: height, in: taken) else {
                overflow.append(widget)
                continue
            }
            for row in spot.row..<spot.row + height {
                for column in spot.column..<spot.column + width {
                    taken[row][column] = true
                }
            }
            placements.append(Placement(widget: widget, column: spot.column, row: spot.row))
            rows = max(rows, spot.row + height)
        }
        return HomeGrid(placements: placements, rows: rows, overflow: overflow)
    }

    private static func firstFree(
        width: Int, height: Int, in taken: [[Bool]]
    ) -> (column: Int, row: Int)? {
        let rowCount = taken.count
        guard let columnCount = taken.first?.count, height <= rowCount, width <= columnCount else {
            return nil
        }
        for row in 0...(rowCount - height) {
            for column in 0...(columnCount - width) {
                let free = (row..<row + height).allSatisfy { r in
                    (column..<column + width).allSatisfy { c in !taken[r][c] }
                }
                if free { return (column, row) }
            }
        }
        return nil
    }

    // MARK: - Геометрия

    /// Ширина панели. Та же, что у панели сводок: у двух соседних панелей
    /// разная ширина читалась бы как прыжок выреза при переходе.
    static var panelWidth: CGFloat { NotchStyle.scaled(480) }

    /// Поле панели от чёрного тела — как у прежней раскрытой панели.
    static var bodyPadding: CGFloat { NotchStyle.bottomPadding }

    static var spacing: CGFloat { NotchStyle.gridSpacing }

    /// Высота ряда. Под неё подогнана строка музыки с обложкой 44 точки
    /// и три строки встреч в плитке высотой в два ряда.
    static var rowHeight: CGFloat { NotchStyle.scaled(62) }

    static var contentWidth: CGFloat {
        panelWidth - 2 * (bodyPadding + NotchStyle.shoulderInset)
    }

    static var cellWidth: CGFloat {
        (contentWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns)
    }

    /// Высота сетки по числу рядов. Одна формула на панель и на потолок
    /// окна: выписанный отдельно, потолок однажды уже разошёлся с панелью.
    static func contentHeight(rows: Int) -> CGFloat {
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * rowHeight + CGFloat(rows - 1) * spacing
    }

    static func size(of size: HomeWidgetSize) -> CGSize {
        CGSize(
            width: CGFloat(size.columns) * cellWidth + CGFloat(size.columns - 1) * spacing,
            height: CGFloat(size.rows) * rowHeight + CGFloat(size.rows - 1) * spacing
        )
    }

    static func origin(of placement: Placement) -> CGPoint {
        CGPoint(
            x: CGFloat(placement.column) * (cellWidth + spacing),
            y: CGFloat(placement.row) * (rowHeight + spacing)
        )
    }
}
