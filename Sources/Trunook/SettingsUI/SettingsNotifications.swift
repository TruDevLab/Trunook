import AppKit
import SwiftUI

/// Раздел настроек «Уведомления»: всё, что всплывает под чёлкой.
///
/// Собрано из трёх разделов: плашки событий жили в «Вырезе», предупреждения
/// о встречах — в «Календаре», перерывы — в «Инструментах». Пока новых
/// уведомлений не было, это терпелось; когда появились звонки и вопросы
/// от программ, звонок попал в «Календарь» просто по соседству со встречами —
/// и пользователь справедливо спросил, при чём тут календарь.
extension SettingsView {
    /// Сначала то, что вырез сообщает сам, потом то, что спрашивает.
    ///
    /// Двумя маленькими группами: в `Group` помещается не больше десяти
    /// видов, и запас на следующие карточки лучше оставить сразу.
    var notificationsSection: some View {
        Group {
            Group {
                plashkiCard
                meetingsCard
                breaksCard
            }
            Group {
                callsCard
                questionsCard
                questionsTryCard
            }
        }
    }

    /// Что вырез сообщает сам: трек, копирование, заряд, погода.
    var plashkiCard: some View {
        section(t("Плашки событий"), icon: "bell.badge") {

            VStack(alignment: .leading, spacing: 4) {
                Picker(t("Держать плашки событий"), selection: settings.binding(\.activityHold)) {
                    ForEach(Settings.activityHolds, id: \.self) { scale in
                        Text(Self.activityHoldTitle(scale)).tag(scale)
                    }
                }
                .pickerStyle(.menu)
                hint(t("Как долго держатся плашки событий."))
                hint(t("Наведение на вырез убирает плашку в любом случае."))
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Показывать смену трека"), isOn: settings.binding(\.showTrackChanges))
                    .disabled(!settings.musicEnabled)
                hint(t("Работает с любым плеером: сведения читаются из системы."))
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Показывать плашку при копировании"),
                       isOn: settings.binding(\.clipboardShowsChip))
                    .disabled(!settings.clipboardEnabled)
                hint(t("По плашке можно нажать — откроется история."))
            }
            .accessibilityElement(children: .combine)

            Toggle(t("Состояние питания"), isOn: settings.binding(\.batteryEnabled))
            Toggle(t("Предупреждать о низком заряде"), isOn: settings.binding(\.warnOnLowBattery))
                .disabled(!settings.batteryEnabled)
            Picker(t("Порог предупреждения"), selection: settings.binding(\.lowBatteryThreshold)) {
                ForEach([10, 15, 20, 25, 30], id: \.self) { value in
                    Text("\(value)%").tag(value)
                }
            }
            .pickerStyle(.menu)
            .disabled(!settings.batteryEnabled || !settings.warnOnLowBattery)

            // Пояснение — в одной строке со списком: отдельной строкой
            // под линией оно читалось как ещё одна настройка.
            VStack(alignment: .leading, spacing: 4) {
                Picker(t("Сообщать"), selection: Binding(
                    get: { settings.weatherAlertMode },
                    set: { settings.weatherAlertMode = $0 }
                )) {
                    ForEach(WeatherAlertMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!settings.weatherEnabled)
                if settings.weatherAlertMode != .periodic {
                    hint(t("Один раз на явление, а не каждую проверку."))
                }
            }

            if settings.weatherAlertMode == .periodic {
                Picker(t("Как часто сообщать"), selection: settings.binding(\.weatherPeriodHours)) {
                    ForEach([1, 3, 6, 12], id: \.self) { value in
                        Text(tf("%d ч", value)).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!settings.weatherEnabled)
            }
        }
    }

    /// Предупреждения о встречах и отсчёт до них.
    var meetingsCard: some View {
        section(t("Встречи"), icon: "calendar.badge.clock") {

            Picker(t("Предупреждать за"), selection: settings.binding(\.eventLeadMinutes)) {
                Text(t("в момент начала")).tag(0)
                Text(t("5 минут")).tag(5)
                Text(t("10 минут")).tag(10)
                Text(t("15 минут")).tag(15)
            }
            .pickerStyle(.menu)

            Toggle(t("Ещё раз в момент начала"), isOn: settings.binding(\.alertAtEventStart))
                .disabled(settings.eventLeadMinutes == 0)

            Toggle(t("Обратный отсчёт рядом с вырезом"), isOn: settings.binding(\.showCountdown))

            Picker(t("Отсчёт появляется за"), selection: settings.binding(\.countdownWindowMinutes)) {
                ForEach([5, 10, 15, 30], id: \.self) { value in
                    Text(tf("%d минут", value)).tag(value)
                }
            }
            .pickerStyle(.menu)
            .disabled(!settings.showCountdown)
        }
    }

    /// Входящий звонок чужого телефона — плашкой с ответом и отбоем.
    var callsCard: some View {
        section(t("Входящие звонки"), icon: "phone.arrow.down.left") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Показывать звонок в вырезе"), isOn: settings.binding(\.callsEnabled))
                hint(t("Telephone, Zoiper, Linphone, Bria, 3CX, Telegram. Ответить и отклонить прямо из выреза."))
                hint(t("Нужен Универсальный доступ: кнопки нажимаются в самом приложении."))
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Вопросы от других программ.
    ///
    /// Слова подобраны так, чтобы понять настройку, не зная, как она
    /// устроена: первый заход назывался «Принимать уведомления от скриптов»
    /// с пояснением про папку — и пользователь спросил, какую папку ему
    /// указывать. Никакую: папка одна, и программы знают её сами.
    ///
    var questionsCard: some View {
        section(t("Вопросы от программ"), icon: "questionmark.bubble") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Разрешить программам спрашивать через вырез"), isOn: settings.binding(\.inboxEnabled))
                hint(t("Сборка, помощник в терминале или свой скрипт показывают вопрос с двумя кнопками и узнают, какую вы нажали."))
                hint(t("Указывать ничего не нужно: программы кладут вопрос в папку приложения сами."))
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Пример и папка — чтобы увидеть, что это, до того как включать.
    var questionsTryCard: some View {
        section(t("Как это выглядит"), icon: "eye") {
            HStack {
                Button(t("Показать пример")) { onPreviewNotice() }
                Spacer()
                Button(t("Открыть папку")) {
                    try? FileManager.default.createDirectory(
                        at: NotifyInbox.defaultFolder, withIntermediateDirectories: true
                    )
                    NSWorkspace.shared.open(NotifyInbox.defaultFolder)
                }
            }
        }
    }
}
