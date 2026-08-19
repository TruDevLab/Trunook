import SwiftUI

/// Меню быстрых команд: шесть слотов в два ряда.
///
/// Раскладка жёсткая, а не по числу заполненных слотов: меню вызывается
/// вслепую, и место команды не должно съезжать оттого, что соседний слот
/// пустой. Пустые показываются как места под команду.
struct CommandsPanel: View {
    let commands: [QuickCommand]
    let metrics: NotchMetrics
    let onRun: (QuickCommand) -> Void
    let onOpenSettings: () -> Void
    /// nil — возвращаться некуда, меню вызвано клавишей.
    let onClose: () -> Void

    static let columns = 3
    static let slotWidth: CGFloat = 118
    static let slotHeight: CGFloat = 58
    static let spacing = NotchStyle.gridSpacing
    static let horizontalPadding = NotchStyle.panelPadding

    static var width: CGFloat {
        CGFloat(columns) * slotWidth
            + CGFloat(columns - 1) * spacing
            + 2 * horizontalPadding
    }

    /// Высота с учётом строки возврата, если она есть.
    /// Строка возврата больше не занимает высоты: стрелка уехала в крыло.
    /// Признак оставлен, чтобы не менять вызовы, но на размер не влияет.
    static func height(notchHeight: CGFloat, hasBackRow: Bool = false) -> CGFloat {
        let rows = ceil(Double(QuickCommands.slotCount) / Double(columns))
        let grid = CGFloat(rows) * slotHeight + CGFloat(rows - 1) * spacing
        return NotchStyle.height(notchHeight: notchHeight, contentHeight: grid)
    }

    var body: some View {
        NotchPanel(metrics: metrics, width: Self.width) {
            NotchPanelTitle(
                symbol: "square.grid.2x2",
                title: t("Команды"),
                tint: Palette.commands
            )
        } trailing: {
            HStack(spacing: 2) {
                NotchPanelButton(symbol: "gearshape", action: onOpenSettings)
                // Крестик — общий для всех накладок и всегда последний
                // в крыле: где бы человек ни находился, закрывается панель
                // одинаково и в одном и том же месте.
                NotchPanelButton(symbol: "xmark", action: onClose)
            }
        } content: {
            VStack(spacing: Self.spacing) {
                ForEach(0..<rowCount, id: \.self) { row in
                    HStack(spacing: Self.spacing) {
                        ForEach(slots(in: row)) { command in
                            slot(command)
                        }
                    }
                }
            }
        }
    }

    private var rowCount: Int {
        Int(ceil(Double(QuickCommands.slotCount) / Double(Self.columns)))
    }

    private func slots(in row: Int) -> [QuickCommand] {
        let start = row * Self.columns
        let end = min(start + Self.columns, commands.count)
        guard start < end else { return [] }
        return Array(commands[start..<end])
    }

    @ViewBuilder
    private func slot(_ command: QuickCommand) -> some View {
        if command.isConfigured {
            NotchTile(id: "command-\(command.id)") {
                Button { onRun(command) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: command.effectiveSymbol)
                            .font(.system(size: 16, weight: .medium))
                        Text(command.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            // Поля по бокам: без них длинная подпись упиралась
                            // в самый край плитки и обрезалась по букве.
                            .padding(.horizontal, 8)
                    }
                    .foregroundStyle(.white)
                    .frame(width: Self.slotWidth, height: Self.slotHeight)
                    .overlay(alignment: .topTrailing) {
                        // Номер слота: он же цифра в сочетании ⌃⌥N.
                        Text("\(command.id + 1)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(5)
                    }
                    // Зона нажатия — вся плитка, а не только надпись:
                    // подложка рисуется снаружи, в NotchTile.
                    .contentShape(RoundedRectangle(cornerRadius: NotchStyle.tileRadius, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
        } else {
            // Пустой слот — пунктиром: место под команду, а не плитка.
            // Подложки у него нет, поэтому и отклика на курсор тоже.
            Button(action: onOpenSettings) {
                VStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                    Text(tf("Слот %d", command.id + 1))
                        .font(.system(size: 10))
                }
                .foregroundStyle(.white.opacity(0.3))
                .frame(width: Self.slotWidth, height: Self.slotHeight)
                .background(
                    RoundedRectangle(cornerRadius: NotchStyle.tileRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
                .contentShape(RoundedRectangle(cornerRadius: NotchStyle.tileRadius, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
    }
}
