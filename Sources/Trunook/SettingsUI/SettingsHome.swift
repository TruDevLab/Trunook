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
            if settings.homeWidgets.contains(where: { $0.kind == .countdown }) {
                countdownCard
            }
            section(t("Добавить виджет"), icon: "plus.square.on.square") {
                HomeWidgetPalette(settings: settings, selection: selection)
            }
        }
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
