import AVFoundation
import AppKit
import SwiftUI

/// Раздел настроек «Главный экран»: раскладка плиток и событие обратного отсчёта.
extension SettingsView {
    var homeSection: some View {
        Group {
            section(t("Главный экран"), icon: "square.grid.3x2.fill") {
                HomeLayoutPreview(settings: settings, selection: selection)
                hint(t("Перетащите плитку, чтобы переставить, или нажмите, чтобы выбрать размер."))
                HStack {
                    // Макет — заглушки; как это выглядит на деле, видно
                    // только в самом вырезе, а он раскрывается по наведению,
                    // пока курсор занят окном настроек.
                    Button(t("Показать в вырезе")) { onPreviewNotch(6) }
                    Spacer()
                    Button(t("Вернуть как было")) {
                        selection.homeSelected = nil
                        settings.resetHomeWidgets()
                    }
                }
            }
            if let id = selection.homeSelected,
               let widget = settings.homeWidgets.first(where: { $0.id == id }) {
                section(t("Выбранная плитка"), icon: "square.dashed") {
                    HomeWidgetInspector(settings: settings, selection: selection, widget: widget)
                }
            }
            // Карточка на каждую плитку команд, а не на выбранную: плиток
            // бывает несколько — у команд это разрешено, — и нажатие
            // по пустой плитке в вырезе ведёт сюда. Выбирать её здесь
            // второй раз человеку незачем.
            ForEach(settings.homeWidgets.filter { $0.kind == .commands }) { widget in
                commandsCard(widget)
            }
            if settings.homeWidgets.contains(where: { $0.kind == .countdown }) {
                countdownCard
            }
            section(t("Добавить виджет"), icon: "plus.square.on.square") {
                HomeWidgetPalette(settings: settings, selection: selection)
            }
        }
    }

    /// Команды на плитке: по строке на клетку.
    ///
    /// Выпадающими списками, а не галочками у всего набора: порядок на плитке
    /// — это порядок клеток, и галочки не сказали бы, какая команда встанет
    /// первой. Дырок в списке не бывает: выбранное в пустой строке становится
    /// следующим по порядку, а «Пусто» подтягивает остальные.
    func commandsCard(_ widget: HomeWidget) -> some View {
        let configured = settings.quickCommands.filter(\.isConfigured)
        return section(tf("Команды на плитке %@", widget.size.title), icon: "square.grid.2x2.fill") {
            if configured.isEmpty {
                hint(t("Настроенных команд нет — заведите их в разделе «Команды»."))
            }
            ForEach(0..<widget.size.commandSlots, id: \.self) { slot in
                Picker(tf("Клетка %d", slot + 1), selection: commandSlotBinding(widget, slot: slot)) {
                    Text(t("Пусто")).tag(-1)
                    ForEach(configured) { command in
                        Label {
                            Text(command.title)
                        } icon: {
                            Image(systemName: command.effectiveSymbol)
                        }
                        .tag(command.id)
                    }
                }
                .pickerStyle(.menu)
            }
            hint(t("Нажатие по команде на плитке запускает её с тем, что выделено в другом окне."))
        }
    }

    /// Что стоит в клетке. `-1` — пусто: `Picker` требует, чтобы у каждого
    /// пункта была метка того же типа, а номера команд начинаются с нуля.
    private func commandSlotBinding(_ widget: HomeWidget, slot: Int) -> Binding<Int> {
        Binding(
            get: {
                let stored = settings.homeWidgets.first { $0.id == widget.id }?.commands ?? []
                return slot < stored.count ? stored[slot] : -1
            },
            set: { chosen in
                var stored = settings.homeWidgets.first { $0.id == widget.id }?.commands ?? []
                if slot < stored.count {
                    if chosen == -1 {
                        stored.remove(at: slot)
                    } else {
                        stored[slot] = chosen
                    }
                } else if chosen != -1 {
                    stored.append(chosen)
                }
                settings.setHomeWidgetCommands(id: widget.id, stored)
            }
        )
    }

    /// Событие плитки обратного отсчёта. Карточка видна, пока плитка
    /// стоит на экране: нажатие по плитке ведёт сюда.
    var countdownCard: some View {
        section(t("Обратный отсчёт"), icon: "hourglass") {
            TextField(t("Название"), text: settings.binding(\.countdownEventTitle),
                      prompt: Text(t("Например, отпуск")))
            VStack(alignment: .leading, spacing: 4) {
            DatePicker(
                t("Когда"),
                selection: Binding(
                    get: { settings.countdownEventDate ?? Self.defaultCountdownDate() },
                    set: { settings.countdownEventDate = $0 }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            .environment(\.locale, Localization.shared.resolved.locale)
            if settings.countdownEventDate == nil {
                hint(t("Выберите дату — плитка начнёт считать."))
            }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Пока дату не выбрали, в поле — завтрашний полдень: сегодняшнее «сейчас»
    /// отсчитывать нечего.
    static func defaultCountdownDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}
