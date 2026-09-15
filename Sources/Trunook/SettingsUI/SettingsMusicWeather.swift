import AVFoundation
import AppKit
import SwiftUI

/// Раздел настроек «Музыка и погода».
extension SettingsView {
    var weatherSection: some View {
        Group {
            section(t("Погода"), icon: "cloud.sun") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Погода"), isOn: Binding(
                        get: { settings.weatherEnabled },
                        set: { enabled in
                            settings.weatherEnabled = enabled
                            weather.restart()
                        }
                    ))
                    hint(t("Плитка на главном экране, а без плитки — значок в углу панели."))
                }
                .accessibilityElement(children: .combine)


                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Анимация смены погоды"), isOn: settings.binding(\.weatherScenesEnabled))
                        .disabled(!settings.weatherEnabled)
                    hint(t("Дождь капает из чёлки, солнышко всплывает."))
                }
                .accessibilityElement(children: .combine)


}

            section(t("Место"), icon: "mappin.and.ellipse") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Где смотреть погоду"), selection: Binding(
                        get: { settings.weatherSource },
                        set: { settings.weatherSource = $0; weather.placeChanged() }
                    )) {
                        ForEach(WeatherSource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .disabled(!settings.weatherEnabled)
                    if settings.weatherSource != .place {
                        hint(t("Приложение запросит доступ к геопозиции."))
                    }
                }

                if settings.weatherSource == .place {
                    placePicker
                }
            }

            section(t("Состояние"), icon: "location") {
                weatherStatus
            }

            section(t("Откуда берётся"), icon: "network") {
                // Справочная карточка: сплошной текст абзацами, а не список
                // настроек. Одной строкой — чтобы `Form` не расчерчивал абзацы
                // разделителями, будто каждый из них что-то отдельное включает.
                VStack(alignment: .leading, spacing: SettingsStyle.gap) {
                    hint(t("Прогноз берётся у open-meteo.com."))
                    hint(t("Наружу уходят координаты, округлённые до километра."))
                }
            }
        }
    }

    /// Выбор города: поле поиска и список найденного.
    ///
    /// Название сохраняется вместе с координатами, а не ищется заново перед
    /// каждым запросом: Ростовов два, Владимиров тоже, и повторный поиск
    /// однажды выбрал бы другой.
    @ViewBuilder
    var placePicker: some View {
        if let place = settings.weatherPlace {
            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill").foregroundStyle(Palette.weather)
                Text(place.title)
                Spacer()
                // Поле поиска при выбранном городе не показывается вовсе:
                // город уже назван, и второе поле рядом с ним читается
                // как «а этот тогда что».
                Button(t("Сменить")) {
                    settings.weatherPlace = nil
                    placeSearch.reset()
                }
            }
        } else {
            placeField
        }

        hint(t("Наружу уходит только название города."))
    }

    @ViewBuilder
    var placeField: some View {
        HStack(spacing: SettingsStyle.gap) {
            TextField(t("Название города"), text: $placeSearch.query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: SettingsStyle.searchFieldWidth)
                // Ввод с клавиатуры: искать по каждой букве значило бы слать
                // запрос на каждое нажатие.
                .onSubmit { placeSearch.search() }
            Button(t("Найти")) { placeSearch.search() }
                .disabled(placeSearch.query.trimmingCharacters(in: .whitespaces).count < 2)
            if placeSearch.isSearching { ProgressView().controlSize(.small) }
        }
        .disabled(!settings.weatherEnabled)

        if let message = placeSearch.message {
            hint(message)
        }

        ForEach(placeSearch.results) { found in
            Button {
                settings.weatherPlace = found
                settings.weatherSource = .place
                placeSearch.reset()
                weather.placeChanged()
            } label: {
                HStack(spacing: SettingsStyle.gap) {
                    Image(systemName: "mappin").foregroundStyle(.secondary)
                    Text(found.title)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    var weatherStatus: some View {
        // При выбранном городе разрешение ни при чём: показывать «доступ
        // не запрошен» там, где он и не нужен, — значит пугать без причины.
        if settings.weatherSource == .place {
            weatherReading
        } else {
            locationStatus
        }
    }

    @ViewBuilder
    var locationStatus: some View {
        switch weather.authorization {
        case .denied, .restricted:
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
                Text(t("Доступ к геопозиции запрещён. Без него погоду не узнать."))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(t("Открыть настройки конфиденциальности")) {
                WeatherService.openPrivacySettings()
            }
        case .notDetermined:
            Button(t("Разрешить доступ к геопозиции")) {
                weather.requestAccessIfNeeded()
            }
            .disabled(!settings.weatherEnabled)
        default:
            weatherReading
        }
    }

    /// Сам прогноз — он одинаков, откуда бы ни взялись координаты.
    @ViewBuilder
    var weatherReading: some View {
        if let snapshot = weather.current {
            HStack(spacing: 10) {
                Image(systemName: snapshot.condition.symbol)
                    .foregroundStyle(snapshot.condition.tint)
                Text("\(snapshot.condition.title), \(snapshot.temperature)°")
                Spacer()
                Button(t("Обновить")) { weather.refresh() }
            }
            if let outlook = snapshot.outlook {
                hint(tf("Через %d ч %@, вероятность %d%%",
                        outlook.inHours, outlook.condition.title.lowercased(), outlook.probability))
            }
        } else if settings.weatherSource == .place, settings.weatherPlace == nil {
            hint(t("Город не выбран — прогноз запрашивать не для чего."))
        } else {
            HStack(spacing: 10) {
                Text(weather.error ?? t("Прогноз ещё не загружен"))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(t("Обновить")) { weather.refresh() }
            }
        }
    }

    /// Музыка. Живёт в «В вырезе»: вырез показывает трек сам, без спроса.
    var musicCard: some View {
        Group {
                section(t("Музыка"), icon: "music.note") {
                    Toggle(t("Музыка"), isOn: settings.binding(\.musicEnabled))
                    VStack(alignment: .leading, spacing: 4) {

                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(t("Поменять стороны свайпа"), isOn: settings.binding(\.swipeInverted))
                                .disabled(!settings.musicEnabled)
                        }
                

                        hint(t("Свайп двумя пальцами по острову переключает трек."))
                    }
                    .accessibilityElement(children: .combine)
}
        }
    }

    var inNotchSection: some View {
        Group {
            musicCard
            weatherSection
        }
    }
}
