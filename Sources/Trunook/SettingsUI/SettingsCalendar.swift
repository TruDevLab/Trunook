import AVFoundation
import AppKit
import SwiftUI

/// Раздел настроек «Календарь»: встречи, задачи, какие календари показывать.
extension SettingsView {
    var calendarSection: some View {
        Group {
        section(t("Календарь и задачи"), icon: "calendar") {
            Toggle(t("Встречи из Календаря"), isOn: Binding(
                get: { settings.calendarEnabled },
                set: { enabled in
                    settings.calendarEnabled = enabled
                    if enabled { calendar.requestAccessIfNeeded() }
                    onHotKeysChanged()
                }
            ))

            HStack {
                Text(t("Открыть календарь"))
                Spacer()
                HotKeyRecorder(label: t("Открыть календарь"), spec: Binding(
                    get: { settings.calendarHotKey },
                    set: { settings.calendarHotKey = $0; onHotKeysChanged() }
                ))
                .frame(width: SettingsStyle.hotKeyField.width,
                       height: SettingsStyle.hotKeyField.height)
            }
            .disabled(!settings.calendarEnabled)

            VStack(alignment: .leading, spacing: 4) {
                Picker(t("Дела дня"), selection: settings.binding(\.calendarDayView)) {
                    ForEach(CalendarDayView.allCases) { view in
                        Text(view.title).tag(view)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!settings.calendarEnabled)
                hint(t("То же переключает кнопка в открытом календаре."))
            }
            .accessibilityElement(children: .combine)

            Toggle(t("Напоминания Apple"), isOn: Binding(
                get: { settings.remindersEnabled },
                set: { enabled in
                    settings.remindersEnabled = enabled
                    if enabled { calendar.requestAccessIfNeeded() }
                }
            ))
            Toggle(t("Задачи Things 3"), isOn: settings.binding(\.thingsEnabled))

            accessStatus
        
}

        section(t("Управление встречей"), icon: "video") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Кнопки встречи в вырезе"), isOn: settings.binding(\.meetingControlsEnabled))
                hint(t("Микрофон, камера, демонстрация, рука и выход. Телемост, Meet, Zoom, Teams."))
                hint(t("Вкладка встречи должна быть открыта."))
            }
            .accessibilityElement(children: .combine)
        }

        if !calendar.availableCalendars.isEmpty {
            section(t("Какие календари показывать"), icon: "calendar.badge.checkmark") {
                sourcePicker(calendar.availableCalendars, keyPath: \.enabledCalendarIDs)
            }
        }

        if !calendar.availableReminderLists.isEmpty {
            section(t("Какие списки напоминаний показывать"), icon: "checklist") {
                sourcePicker(calendar.availableReminderLists, keyPath: \.enabledReminderListIDs)
            }
        }
        }
    }

    @ViewBuilder
    var accessStatus: some View {
        if settings.calendarEnabled, calendar.eventsAccess != .fullAccess {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.warning)
                Text(calendar.eventsAccess == .denied
                     ? t("Доступ к Календарю запрещён. Выдайте его в Системных настройках.")
                     : t("Доступ к Календарю ещё не выдан."))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(t("Открыть настройки конфиденциальности")) {
                CalendarService.openPrivacySettings()
            }
        }
    }

    /// Список календарей или списков напоминаний с галочками.
    func sourcePicker(
        _ sources: [CalendarSource],
        keyPath: ReferenceWritableKeyPath<Settings, Set<String>>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(sources) { source in
                Toggle(isOn: Binding(
                    get: {
                        settings.isSourceEnabled(source.id, in: keyPath, all: sources.map(\.id))
                    },
                    set: { enabled in
                        settings.setSource(source.id, enabled: enabled, in: keyPath, all: sources.map(\.id))
                    }
                )) {
                    HStack(spacing: SettingsStyle.gap) {
                        Circle().fill(source.color).frame(width: SettingsStyle.scaled(8), height: SettingsStyle.scaled(8))
                        Text(source.title)
                    }
                }
            }
        }
    }
}
