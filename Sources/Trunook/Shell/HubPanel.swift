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

    static let width: CGFloat = 440
    /// Две колонки, а не три: плиток четыре, и в три они ложатся как 3 + 1 —
    /// последний ряд выглядит недоделанным.
    static let columns = 2
    static let tileWidth: CGFloat = 196
    static let tileHeight: CGFloat = 66
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
        NotchPanel(metrics: metrics, width: Self.width) {
            NotchPanelTitle(symbol: "square.grid.2x2", title: t("Всё сразу"))
        } trailing: {
            NotchPanelButton(symbol: "gearshape", action: onOpenSettings)
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
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(item.isEnabled ? item.tint : .white.opacity(0.25))
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
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
