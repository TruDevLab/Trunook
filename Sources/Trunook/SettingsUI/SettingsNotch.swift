import AVFoundation
import AppKit
import SwiftUI

/// Раздел настроек «Вырез»: поведение, вид, плашки событий, живой вырез.
extension SettingsView {
    /// Поведение и вид самого выреза, плашки событий и то, что оживляет его
    /// само: кот, мурчание, погода. Собрано из «Основных», «В вырезе»
    /// и «Инструментов» — плашки раньше настраивались в пяти местах.
    var notchSection: some View {
        Group {
            section(t("Поведение"), icon: "cursorarrow.rays") {
                Toggle(t("Раскрывать вырез при наведении"), isOn: settings.binding(\.expandOnHover))

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Экраны"), selection: Binding(
                        get: { settings.notchScreenMode },
                        set: { settings.notchScreenMode = $0 }
                    )) {
                        ForEach(NotchScreenMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    hint(settings.notchScreenMode.hint)
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(t("Раскрыть панель"))
                        Spacer()
                        HotKeyRecorder(label: t("Раскрыть панель"), spec: Binding(
                            get: { settings.expandedHotKey },
                            set: { settings.expandedHotKey = $0; onHotKeysChanged() }
                        ))
                        .frame(width: SettingsStyle.hotKeyField.width,
                               height: SettingsStyle.hotKeyField.height)
                    }
                    hint(t("Открывает главную панель. Повторное нажатие сворачивает."))
                }

                Toggle(t("Виброотклик на трекпаде"), isOn: settings.binding(\.hapticsEnabled))
            }
            section(t("Вид"), icon: "circle.lefthalf.filled") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(t("Прозрачность выреза"))
                        Spacer()
                        // Слово рядом с ползунком: доля сама по себе
                        // ничего не значит, мнение бывает о «матовее»,
                        // а не о «шестидесяти процентах».
                        Text(Surface.DensityScale.title(for: settings.notchDensity))
                            .foregroundStyle(SettingsStyle.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(settings.notchDensity) },
                            set: {
                                settings.notchDensity = Int($0.rounded())
                                // Вырез раскрывается на время правки:
                                // иначе прозрачность настраивают вслепую —
                                // панель показывается по наведению,
                                // а курсор держит ползунок.
                                //
                                // Срок короткий и продлевается каждым
                                // движением: отпустил — через пару секунд
                                // вырез сам вернётся к своему делу.
                                onPreviewNotch(2)
                            }
                        ),
                        in: 0...Double(Surface.DensityScale.opaque),
                        // Шаг, а не плавный ход: соседние доли на глаз
                        // не различаются, и плавный ползунок обещал бы
                        // разницу, которой нет.
                        step: 5,
                        // Раскрыть и в тот миг, когда ползунок только
                        // взяли: человек мог взяться и держать, ничего
                        // ещё не сдвинув, — а смотреть уже начал.
                        onEditingChanged: { editing in
                            if editing { onPreviewNotch(4) }
                        }
                    )
                    // Подпись — для диктора: видимое название стоит строкой
                    // выше, и без неё VoiceOver говорил «ползунок, 60 %»,
                    // не называя, чего.
                    .accessibilityLabel(t("Прозрачность выреза"))
                    .accessibilityValue(Surface.DensityScale.title(for: settings.notchDensity))
                    hint(t("До упора вправо — сплошной чёрный вырез, как было."))
                }
            }
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
            section(t("Живой вырез"), icon: "cat") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Кот в вырезе"), isOn: settings.binding(\.critterEnabled))
                    hint(t("Изредка в чёлке появляется кот, пока ей нечего показывать."))
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Как часто выходит кот"), selection: Binding(
                        get: { settings.critterFrequency },
                        set: { settings.critterFrequency = $0 }
                    )) {
                        ForEach(CritterFrequency.allCases) { frequency in
                            Text(frequency.title).tag(frequency)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!settings.critterEnabled)
                    hint(settings.critterFrequency.hint)
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Мурчание"), isOn: settings.binding(\.purrEnabled))
                    hint(t("Поводите курсором по чёлке из стороны в сторону — вырез замурчит."))
                }
                .accessibilityElement(children: .combine)
}
        }
    }
}
