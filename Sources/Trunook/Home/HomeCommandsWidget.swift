import SwiftUI

/// Что стоит на плитке команд: выбранные команды по своим клеткам.
///
/// Чистая функция, а не выборка в теле вида: по этому же правилу настройки
/// считают занятые клетки, и посчитанное порознь разошлось бы — у человека
/// выбрано четыре, а плитка рисует три, потому что одну команду он выключил.
enum HomeCommandSlots {
    /// Команды плитки в том порядке, в каком они на ней стоят.
    ///
    /// Выключенная и ненастроенная не рисуются: нажатие по ним всё равно
    /// кончилось бы отказом. Пропавшая из набора — так же: место не остаётся
    /// пустым, остальные сдвигаются.
    static func chosen(_ widget: HomeWidget, in commands: [QuickCommand]) -> [QuickCommand] {
        widget.commands
            .compactMap { id in commands.first { $0.id == id } }
            .filter(\.isConfigured)
    }

    /// Сколько команд ещё можно выбрать на эту плитку.
    static func free(_ widget: HomeWidget) -> Int {
        max(0, widget.size.commandSlots - widget.commands.count)
    }
}

/// Плитка быстрых команд: ярлыки к тому же списку, что под полем вопроса.
///
/// Нажатие запускает команду тем же путём, каким её запускает горячая
/// клавиша, — с чтением выделения из чужого окна. Главный экран фокус
/// не отбирает, поэтому выделенное в соседнем приложении к этому мигу ещё
/// живо: выделил абзац, нажал «Перевести» — и панель открылась с переводом.
struct CommandsWidget: View {
    let widget: HomeWidget
    @ObservedObject var settings: Settings
    let actions: HomeActions

    var body: some View {
        let chosen = HomeCommandSlots.chosen(widget, in: settings.quickCommands)
        // Нажатие по телу плитки — только пока выбирать нечего: иначе оно
        // перебивало бы промах мимо ячейки и уводило в настройки в тот миг,
        // когда человек просто не попал по команде.
        HomeTile(
            widget: widget,
            onTap: chosen.isEmpty ? actions.chooseCommands : nil,
            hint: chosen.isEmpty ? t("Выбрать команды") : widget.kind.title
        ) {
            if chosen.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HomeCaption(kind: widget.kind)
                    HomeEmpty(text: t("Выберите команды в настройках"))
                }
            } else {
                grid(chosen)
            }
        }
    }

    /// Клетки рядами по ширине плитки: 1×1 — одна команда, 2×2 — четыре
    /// в два ряда. Одна вёрстка на все размеры: ряд — это просто клетки,
    /// которые в него влезли.
    private func grid(_ chosen: [QuickCommand]) -> some View {
        let perRow = max(1, widget.size.columns)
        let rows = stride(from: 0, to: chosen.count, by: perRow).map { start in
            Array(chosen[start..<min(start + perRow, chosen.count)])
        }
        return VStack(spacing: HomeGrid.spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: HomeGrid.spacing) {
                    ForEach(row) { command in
                        cell(command)
                    }
                    // Недобранные клетки ряда остаются пустыми, а не растягивают
                    // команду во всю ширину: плитка 2×2 с тремя командами иначе
                    // рисовала бы третью вдвое шире соседних.
                    if row.count < perRow {
                        ForEach(0..<(perRow - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Значок и подпись в плитке высотой в один ряд мельче.
    ///
    /// Не украшательство: на 46 точках высоты значок в 18 точек оставлял
    /// названию одну строку, и «Исправить ошибки» превращалось
    /// в «Исправить оши…». Проверено снимком — в два ряда места хватало,
    /// в один нет.
    private var isTall: Bool { widget.size.rows > 1 }

    private func cell(_ command: QuickCommand) -> some View {
        Button {
            actions.runCommand(command)
        } label: {
            VStack(spacing: isTall ? 3 : 2) {
                Image(systemName: command.effectiveSymbol)
                    .font(.system(size: NotchStyle.font(isTall ? 15 : 13), weight: .medium))
                    .foregroundStyle(widget.kind.tint)
                    .frame(height: NotchStyle.scaled(isTall ? 18 : 15))
                // В две строки, а не сжатием — как у ярлыков голоса
                // и диктовки: «Объяснить простыми словами» в клетку
                // не входит, и сжатое название стояло бы мельче соседнего.
                Text(command.title)
                    .font(.system(size: NotchStyle.font(isTall ? 10 : 9.5), weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: NotchStyle.cardRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .notchActionHint(command.title)
        .accessibilityLabel(command.title)
    }
}
