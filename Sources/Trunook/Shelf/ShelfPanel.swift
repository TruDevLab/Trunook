import AppKit
import SwiftUI

/// Полка: файлы, отложенные в вырез, чтобы вытащить их в другом окне.
///
/// Плитками, а не строками — в отличие от истории буфера. У файла опознаётся
/// не текст, а вид: миниатюра плюс имя. Ради этого же имя показывается
/// в две строки: у файлов совпадают начала, а различаются хвосты.
struct ShelfPanel: View {
    let items: [ShelfItem]
    let thumbnail: (ShelfItem) -> NSImage
    let metrics: NotchMetrics
    /// Перетаскивание уже над полкой — подсвечиваем, куда ронять.
    let isDropTarget: Bool
    let onRemove: (ShelfItem) -> Void
    let onOpen: (ShelfItem) -> Void
    let onRevealInFinder: (ShelfItem) -> Void
    let onClear: () -> Void
    /// Файл потащили с полки наружу. Нужно контроллеру, чтобы он не закрыл
    /// панель по уходу курсора: уводить курсор — и есть способ вытащить файл.
    let onBeginDragOut: () -> Void
    let onEndDragOut: () -> Void
    let onClose: () -> Void

    /// Ширина считается от сетки, а не задана числом: поле содержимого
    /// отмеряется от чёрного тела, и подобранная под прежнее поле ширина
    /// обрезала бы четвёртую колонку.
    static var width: CGFloat {
        CGFloat(columns) * tileWidth
            + CGFloat(columns - 1) * tileSpacing
            + 2 * NotchStyle.bodyInset
    }
    static var tileWidth: CGFloat { NotchStyle.scaled(96) }
    static var tileHeight: CGFloat { NotchStyle.scaled(78) }
    static var tileSpacing: CGFloat { NotchStyle.gridSpacing }
    static let columns = 4
    /// Сколько рядов видно без прокрутки. Три уже закрывают треть экрана.
    static let visibleRows = 2

    static func height(notchHeight: CGFloat, count: Int) -> CGFloat {
        NotchStyle.height(notchHeight: notchHeight, contentHeight: gridHeight(count: count))
    }

    static func gridHeight(count: Int) -> CGFloat {
        let rows = max(1, min(rowCount(for: count), visibleRows))
        return CGFloat(rows) * tileHeight + CGFloat(rows - 1) * tileSpacing
    }

    static func rowCount(for count: Int) -> Int {
        max(1, Int(ceil(Double(count) / Double(columns))))
    }

    private var columnLayout: [GridItem] {
        Array(
            repeating: GridItem(.fixed(Self.tileWidth), spacing: Self.tileSpacing),
            count: Self.columns
        )
    }

    var body: some View {
        NotchPanel(metrics: metrics, width: Self.width, bodyPadding: NotchStyle.bottomPadding) {
            NotchPanelTitle(symbol: "tray.full", title: t("Полка"), tint: Palette.shelf)
        } trailing: {
            HStack(spacing: 2) {
                if !items.isEmpty {
                    NotchPanelCount(value: items.count)
                    NotchPanelButton(symbol: "trash", hint: t("Очистить полку"), action: onClear)
                }
                // Крестик — общий для всех накладок и всегда последний
                // в крыле: где бы человек ни находился, закрывается панель
                // одинаково и в одном и том же месте.
                NotchPanelButton(symbol: "xmark", hint: t("Закрыть"), action: onClose)
            }
        } content: {
            if items.isEmpty { empty } else { grid }
        }
    }

    private var empty: some View {
        VStack(spacing: 3) {
            Text(t("Полка пуста"))
                .font(.system(size: NotchStyle.headerFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
            Text(t("Перетащите файлы на чёлку — они лягут сюда"))
                .font(.system(size: NotchStyle.font(10)))
                .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.gridHeight(count: 0))
        .background(dropHint)
    }

    private var grid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columnLayout, spacing: Self.tileSpacing) {
                ForEach(items) { tile($0) }
            }
        }
        .frame(height: Self.gridHeight(count: items.count))
        .background(dropHint)
    }

    /// Пунктир под сеткой, пока файл ведут над полкой.
    @ViewBuilder
    private var dropHint: some View {
        RoundedRectangle(cornerRadius: NotchStyle.tileRadius, style: .continuous)
            .strokeBorder(
                Palette.shelf.opacity(isDropTarget ? 0.5 : 0),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
            .padding(-4)
            .animation(.easeOut(duration: 0.15), value: isDropTarget)
    }

    private func tile(_ item: ShelfItem) -> some View {
        NotchTile(id: "shelf-" + item.id.uuidString) {
            tileBody(item)
        }
    }

    private func tileBody(_ item: ShelfItem) -> some View {
        VStack(spacing: 4) {
            Image(nsImage: thumbnail(item))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)

            Text(item.name)
                .font(.system(size: NotchStyle.font(9.5)))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)

            Text(item.subtitle)
                .font(.system(size: NotchStyle.font(8.5)))
                // Ступенью, а не числом по месту: 0.32 давала 2.67:1 —
                // вдвое ниже нормы, притом что это самый мелкий текст
                // в приложении и читать его труднее всего.
                .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                .lineLimit(1)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .frame(width: Self.tileWidth, height: Self.tileHeight)
        // Нажатие, перетаскивание и правая кнопка — на AppKit: `.onDrag`
        // в вырезе не работает, потому что вырез не становится ключевым
        // окном. Подробности — в `ShelfDragOut`.
        .overlay(
            ShelfDragOut(
                item: item,
                icon: thumbnail(item),
                onBegin: onBeginDragOut,
                // Ушедший файл снимается с полки: она отдаёт его насовсем.
                // Оставшийся — остаётся, иначе запись пропала бы, а файл нет.
                onEnd: { moved in
                    onEndDragOut()
                    if moved { onRemove(item) }
                },
                onClick: { onOpen(item) },
                onReveal: { onRevealInFinder(item) },
                onRemove: { onRemove(item) }
            )
        )
    }
}
