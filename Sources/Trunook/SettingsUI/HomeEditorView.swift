import SwiftUI

/// Макет главного экрана в настройках: те же клетки, что в вырезе.
///
/// Плитки — заглушки со значком и названием, а не живые виджеты: служб
/// у окна настроек нет, и живой вид пришлось бы тянуть через половину
/// приложения ради картинки, которую человек и так увидит, наведя курсор
/// на чёлку. Зато раскладка считается той же `HomeGrid.place`, что и в вырезе,
/// и разойтись с ним не может.
struct HomeLayoutPreview: View {
    @ObservedObject var settings: Settings
    @ObservedObject var selection: SettingsSelection

    /// Макет мельче выреза: карточка настроек у́же панели.
    static let scale: CGFloat = 0.82

    private static var cell: CGSize {
        CGSize(width: HomeGrid.cellWidth * scale, height: HomeGrid.rowHeight * scale)
    }
    private static var gap: CGFloat { HomeGrid.spacing * scale }

    private static func size(_ size: HomeWidgetSize) -> CGSize {
        CGSize(
            width: CGFloat(size.columns) * cell.width + CGFloat(size.columns - 1) * gap,
            height: CGFloat(size.rows) * cell.height + CGFloat(size.rows - 1) * gap
        )
    }

    private static func origin(column: Int, row: Int) -> CGPoint {
        CGPoint(x: CGFloat(column) * (cell.width + gap), y: CGFloat(row) * (cell.height + gap))
    }

    private static var board: CGSize {
        CGSize(
            width: CGFloat(HomeGrid.columns) * cell.width + CGFloat(HomeGrid.columns - 1) * gap,
            height: CGFloat(HomeGrid.maxRows) * cell.height + CGFloat(HomeGrid.maxRows - 1) * gap
        )
    }

    var body: some View {
        let widgets = settings.homeWidgets
        let grid = HomeGrid.place(widgets)
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                // Пустые клетки показывают, сколько места осталось: без них
                // не видно, что потолок — четыре ряда.
                ForEach(0..<(HomeGrid.columns * HomeGrid.maxRows), id: \.self) { index in
                    let origin = Self.origin(column: index % HomeGrid.columns, row: index / HomeGrid.columns)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(width: Self.cell.width, height: Self.cell.height)
                        .offset(x: origin.x, y: origin.y)
                }
                ForEach(grid.placements) { placement in
                    let origin = Self.origin(column: placement.column, row: placement.row)
                    tile(placement.widget)
                        .offset(x: origin.x, y: origin.y)
                }
            }
            .frame(width: Self.board.width, height: Self.board.height, alignment: .topLeading)
            // Бросили мимо плиток — в конец списка.
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                selection.homeDropTarget = nil
                guard let raw = items.first, let moved = Int(raw), let last = widgets.last else { return false }
                settings.moveHomeWidget(id: moved, onto: last.id)
                return true
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.88))
            )
            .frame(maxWidth: .infinity)

            if !grid.overflow.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("Не поместилось"))
                        .font(.system(size: SettingsStyle.font(11.5), weight: .semibold))
                        .foregroundStyle(Palette.warning)
                    HStack(spacing: 6) {
                        ForEach(grid.overflow) { widget in
                            Button {
                                selection.homeSelected = widget.id
                            } label: {
                                Label(widget.kind.title, systemImage: widget.kind.symbol)
                                    .font(.system(size: SettingsStyle.font(11)))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private func tile(_ widget: HomeWidget) -> some View {
        let size = Self.size(widget.size)
        let isSelected = selection.homeSelected == widget.id
        let isTarget = selection.homeDropTarget == widget.id
        let enabled = widget.kind.isEnabled(settings)
        return VStack(spacing: 3) {
            Image(systemName: widget.kind.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(enabled ? widget.kind.tint : .white.opacity(0.35))
            // Размер в одной строке с названием: тремя этажами плитка в один
            // ряд не вмещалась, и SwiftUI ужимал кегль — названия соседних
            // плиток выходили разного размера.
            HStack(spacing: 4) {
                Text(widget.kind.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.4))
                    .lineLimit(widget.size == .small ? 2 : 1)
                    .multilineTextAlignment(.center)
                if widget.size != .small {
                    Text(widget.size.title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .fixedSize()
                }
            }
        }
        .padding(4)
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                // Глухая, а не полупрозрачная: сквозь неё просвечивал
                // пунктир пустых клеток, и плитка читалась как четыре.
                .fill(Color(white: isSelected ? 0.27 : 0.17))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    isTarget || isSelected ? Color.accentColor : .clear,
                    lineWidth: isTarget ? 2 : 1.5
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture { selection.homeSelected = widget.id }
        .draggable(String(widget.id)) {
            Label(widget.kind.title, systemImage: widget.kind.symbol)
                .padding(6)
        }
        .dropDestination(for: String.self) { items, _ in
            selection.homeDropTarget = nil
            guard let raw = items.first, let moved = Int(raw) else { return false }
            settings.moveHomeWidget(id: moved, onto: widget.id)
            selection.homeSelected = moved
            return true
        } isTargeted: { targeted in
            // Своё — только своё: курсор уже мог перейти на соседнюю плитку.
            if targeted {
                selection.homeDropTarget = widget.id
            } else if selection.homeDropTarget == widget.id {
                selection.homeDropTarget = nil
            }
        }
        .contextMenu {
            if widget.kind.allowedSizes.count > 1 {
                ForEach(widget.kind.allowedSizes) { option in
                    Button(option.title) { settings.setHomeWidgetSize(id: widget.id, option) }
                }
                Divider()
            }
            Button(t("Убрать"), role: .destructive) { remove(widget) }
        }
        .animation(.easeOut(duration: 0.12), value: isTarget)
        .help(t("Перетащите, чтобы поменять порядок"))
        .accessibilityLabel(widget.kind.title + ", " + widget.size.title)
    }

    private func remove(_ widget: HomeWidget) {
        if selection.homeSelected == widget.id { selection.homeSelected = nil }
        settings.removeHomeWidget(id: widget.id)
    }
}

/// Выбранная плитка: размер и «Убрать».
struct HomeWidgetInspector: View {
    @ObservedObject var settings: Settings
    @ObservedObject var selection: SettingsSelection
    let widget: HomeWidget

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: widget.kind.symbol)
                .foregroundStyle(widget.kind.tint)
                .frame(width: 18)
            Text(widget.kind.title)
                .font(.system(size: SettingsStyle.font(13), weight: .medium))
            Spacer()
            if widget.kind.allowedSizes.count > 1 {
                Picker("", selection: Binding(
                    get: { widget.size },
                    set: { settings.setHomeWidgetSize(id: widget.id, $0) }
                )) {
                    ForEach(widget.kind.allowedSizes) { size in
                        Text(size.title).tag(size)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            } else {
                Text(widget.size.title)
                    .foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                selection.homeSelected = nil
                settings.removeHomeWidget(id: widget.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(t("Убрать"))
            .accessibilityLabel(t("Убрать"))
        }
    }
}

/// Список всего, что можно поставить на экран.
struct HomeWidgetPalette: View {
    @ObservedObject var settings: Settings
    @ObservedObject var selection: SettingsSelection

    var body: some View {
        let placed = Set(settings.homeWidgets.map(\.kind))
        ForEach(HomeWidgetKind.allCases) { kind in
            HStack(spacing: 8) {
                Image(systemName: kind.symbol)
                    .foregroundStyle(kind.tint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title)
                    if !kind.isEnabled(settings) {
                        Text(t("Функция выключена"))
                            .font(.system(size: SettingsStyle.font(11)))
                            .foregroundStyle(SettingsStyle.tertiary)
                    }
                }
                Spacer()
                if placed.contains(kind) {
                    Text(t("На экране"))
                        .font(.system(size: SettingsStyle.font(11.5)))
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        selection.homeSelected = settings.addHomeWidget(kind)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(t("Добавить"))
                    .accessibilityLabel(tf("Добавить «%@»", kind.title))
                }
            }
        }
    }
}
