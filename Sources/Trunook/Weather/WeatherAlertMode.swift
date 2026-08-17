import Foundation

/// Когда вырез сообщает о погоде.
enum WeatherAlertMode: String, CaseIterable, Identifiable {
    /// Только когда что-то поменялось: пошёл дождь, распогодилось,
    /// в ближайшие часы ожидаются осадки.
    case onChange
    /// Просто раз в столько-то часов, что бы за окном ни было.
    case periodic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onChange: return t("Когда меняется погода")
        case .periodic: return t("По расписанию")
        }
    }
}
