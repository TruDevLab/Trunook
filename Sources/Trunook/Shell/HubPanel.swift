import SwiftUI

/// Меню всех функций: плитками то, до чего иначе надо помнить сочетание.
///
/// Появилось потому, что возможностей стало больше, чем человек способен
/// удержать в голове: у полки, буфера и команд свои клавиши, и не зная их,
/// добраться до половины приложения было нельзя вовсе. Открывается правой
/// кнопкой по вырезу и кнопкой из раскрытой панели.
struct HubPanel: View {
    let metrics: NotchMetrics
    let items: [Item]
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    /// Плитка меню. Выключенная в настройках функция остаётся видимой,
    /// но недоступной: иначе меню меняло бы состав, и человек решил бы,
    /// что функция пропала совсем.
    struct Item: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let tint: Color
        let isEnabled: Bool
        let hint: String?
        let action: () -> Void
    }

    /// Ширина считается от сетки, а не задана числом: поле содержимого
    /// отмеряется от чёрного тела, и подобранная под прежнее поле ширина
    /// обрезала бы третью колонку. Так панель подстроится и под правку
    /// размера плитки.
    static var width: CGFloat {
        CGFloat(columns) * tileWidth
            + CGFloat(columns - 1) * tileSpacing
            + 2 * NotchStyle.bodyInset
    }
    /// Три колонки.
    ///
    /// Были две: при четырёх плитках в три они ложились как 3 + 1, и второй
    /// ряд выглядел недоделанным. С пятой плиткой две колонки дали третий ряд,
    /// и меню выросло на семьдесят четыре точки — панель, вызываемая правой
    /// кнопкой, полезла закрывать чужие окна. Три колонки возвращают прежнюю
    /// высоту: пять плиток ложатся как 3 + 2, и ряд читается рядом.
    static let columns = 3
    /// Уже прежней ровно настолько, чтобы три плитки с зазорами уложились
    /// в ту же ширину панели.
    static let tileWidth: CGFloat = 130
    static let tileHeight: CGFloat = 66
    /// Общая высота значка — см. плитку.
    private static let symbolHeight: CGFloat = 20
    static let tileSpacing = NotchStyle.gridSpacing

    static func height(notchHeight: CGFloat, count: Int) -> CGFloat {
        NotchStyle.height(notchHeight: notchHeight, contentHeight: gridHeight(count: count))
    }

    static func gridHeight(count: Int) -> CGFloat {
        let rows = max(1, Int(ceil(Double(count) / Double(columns))))
        return CGFloat(rows) * tileHeight + CGFloat(rows - 1) * tileSpacing
    }

    private var columnLayout: [GridItem] {
        Array(
            repeating: GridItem(.fixed(Self.tileWidth), spacing: Self.tileSpacing),
            count: Self.columns
        )
    }

    var body: some View {
        NotchPanel(metrics: metrics, width: Self.width, bodyPadding: NotchStyle.bottomPadding) {
            NotchPanelTitle(symbol: "square.grid.2x2", title: t("Всё сразу"))
        } trailing: {
            HStack(spacing: 2) {
                NotchPanelButton(symbol: "gearshape", action: onOpenSettings)
                // Крестик — общий для всех накладок и всегда последний
                // в крыле: где бы человек ни находился, закрывается панель
                // одинаково и в одном и том же месте.
                NotchPanelButton(symbol: "xmark", action: onClose)
            }
        } content: {
            LazyVGrid(columns: columnLayout, spacing: Self.tileSpacing) {
                ForEach(items) { tile($0) }
            }
        }
    }

    private func tile(_ item: Item) -> some View {
        NotchTile(id: "hub-" + item.id, isEnabled: item.isEnabled) {
            Button(action: item.action) {
            VStack(spacing: 5) {
                Image(systemName: item.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(item.isEnabled ? item.tint : .white.opacity(0.25))
                    // Высота задана жёстко: значки системного набора разного
                    // роста — «доска с листом» и циферблат выше подноса, —
                    // и без общей высоты они толкали подпись вниз, а ряд
                    // читался кривым.
                    .frame(height: Self.symbolHeight)
                Text(item.title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(item.isEnabled ? 0.9 : 0.35))
                    .lineLimit(1)
                // Строка подсказки есть у всех, даже когда сочетания нет:
                // без неё плитки с клавишей и без неё вставали на разной
                // высоте, и ряд читался рваным.
                Text(item.hint ?? " ")
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(item.isEnabled ? 0.3 : 0.18))
                    .opacity(item.hint == nil ? 0 : 1)
                    .lineLimit(1)
            }
            .frame(width: Self.tileWidth, height: Self.tileHeight)
            // Без этого зона нажатия у кнопки — только сами буквы и значок:
            // подложку рисует NotchTile снаружи, а метка кнопки о ней
            // не знает и остаётся прозрачной для попаданий.
            .contentShape(RoundedRectangle(cornerRadius: NotchStyle.tileRadius, style: .continuous))
        }
            .buttonStyle(PressableStyle())
            .disabled(!item.isEnabled)
        }
    }
}
