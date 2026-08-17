import SwiftUI

/// Погодное явление, приведённое к тому немногому, что различимо
/// значком размером с букву.
///
/// Коды приходят по стандарту WMO — их около тридцати, и половина
/// отличается словами вроде «умеренный» и «сильный». В вырезе эта разница
/// не читается, поэтому коды сводятся к семи случаям.
enum WeatherCondition: String, Equatable {
    case clear
    case cloudy
    case fog
    case drizzle
    case rain
    case snow
    case thunder

    /// Разбор кода WMO.
    init(wmo code: Int) {
        switch code {
        case 0, 1: self = .clear
        case 2, 3: self = .cloudy
        case 45, 48: self = .fog
        case 51, 53, 55, 56, 57: self = .drizzle
        case 61, 63, 65, 66, 67, 80, 81, 82: self = .rain
        case 71, 73, 75, 77, 85, 86: self = .snow
        case 95, 96, 99: self = .thunder
        default: self = .cloudy
        }
    }

    var symbol: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .thunder: return "cloud.bolt.rain.fill"
        }
    }

    var tint: Color {
        switch self {
        case .clear: return .yellow
        case .cloudy, .fog: return .white.opacity(0.7)
        case .drizzle, .rain: return .cyan
        case .snow: return .white
        case .thunder: return .orange
        }
    }

    var title: String {
        switch self {
        case .clear: return t("Ясно")
        case .cloudy: return t("Облачно")
        case .fog: return t("Туман")
        case .drizzle: return t("Морось")
        case .rain: return t("Дождь")
        case .snow: return t("Снег")
        case .thunder: return t("Гроза")
        }
    }

    /// С осадками — то, о чём стоит предупредить заранее.
    var isPrecipitation: Bool {
        switch self {
        case .drizzle, .rain, .snow, .thunder: return true
        case .clear, .cloudy, .fog: return false
        }
    }
}
