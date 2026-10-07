import AVFoundation
import AppKit
import SwiftUI

/// Раздел настроек «Вырез»: поведение, вид, живой вырез. Плашки событий
/// переехали в «Уведомления».
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
                    Picker(t("Главный экран"), selection: Binding(
                        get: { settings.notchHomeScreen ?? "" },
                        set: { key in
                            settings.notchHomeScreen = key.isEmpty ? nil : key
                            settings.notchHomeScreenName = homeScreenChoices
                                .first { $0.key == key }?.name ?? ""
                        }
                    )) {
                        Text(t("С вырезом")).tag("")
                        ForEach(homeScreenChoices, id: \.key) { choice in
                            Text(choice.title).tag(choice.key)
                        }
                    }
                    .pickerStyle(.menu)
                    hint(t("На главном экране — полный остров и плашки событий."))
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
                        Text(t("Стекло выреза"))
                        Spacer()
                        // Слово рядом с ползунком: доля сама по себе
                        // ничего не значит, мнение бывает о «матовом»,
                        // а не о «шестидесяти процентах».
                        Text(Surface.LookScale.title(for: settings.notchLook))
                            .foregroundStyle(SettingsStyle.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(settings.notchLook) },
                            set: {
                                settings.notchLook = Int($0.rounded())
                                // Вырез раскрывается на время правки:
                                // иначе вид настраивают вслепую —
                                // панель показывается по наведению,
                                // а курсор держит ползунок.
                                //
                                // Срок короткий и продлевается каждым
                                // движением: отпустил — через пару секунд
                                // вырез сам вернётся к своему делу.
                                onPreviewNotch(2)
                            }
                        ),
                        in: 0...Double(Surface.LookScale.opaque),
                        // Пять положений: каждое проверено снимком
                        // на читаемость, промежуточные — нет.
                        step: 25,
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
                    .accessibilityLabel(t("Стекло выреза"))
                    .accessibilityValue(Surface.LookScale.title(for: settings.notchLook))
                    hint(t("Влево — прозрачное стекло, посередине — матовое, вправо — чёрный."))
                }
            }
            section(t("Экран блокировки"), icon: "lock") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Вырез на экране блокировки"), isOn: settings.binding(\.lockScreenEnabled))
                    hint(t("Погода, заряд и музыка поверх экрана блокировки."))
                }
                .accessibilityElement(children: .combine)
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

/// Экран в списке «Главный экран».
struct HomeScreenChoice {
    let key: String
    let name: String
    let title: String
}

extension SettingsView {
    /// Подключённые экраны и назначенный, если он сейчас отключён.
    ///
    /// Одинаковые мониторы могут называться одинаково,
    /// — поэтому к повторному имени дописывается номер по порядку.
    var homeScreenChoices: [HomeScreenChoice] {
        let slots = NSScreen.screens.map(NotchGeometry.slot(of:)).filter { !$0.key.isEmpty }
        var seen: [String: Int] = [:]
        var choices = slots.map { slot -> HomeScreenChoice in
            seen[slot.name, default: 0] += 1
            let repeated = slots.filter { $0.name == slot.name }.count > 1
            let name = repeated ? "\(slot.name) · \(seen[slot.name] ?? 1)" : slot.name
            return HomeScreenChoice(key: slot.key, name: name, title: name)
        }
        if let saved = settings.notchHomeScreen, !choices.contains(where: { $0.key == saved }) {
            let name = settings.notchHomeScreenName.isEmpty ? t("Монитор") : settings.notchHomeScreenName
            choices.append(HomeScreenChoice(key: saved, name: name, title: name + " — " + t("не подключён")))
        }
        return choices
    }
}
