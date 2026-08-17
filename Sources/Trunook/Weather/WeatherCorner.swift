import SwiftUI

/// Погода в правом верхнем углу раскрытой панели.
///
/// Живёт в полосе высотой с аппаратный вырез — по бокам от самой чёлки там
/// пусто, потому что содержимое панели начинается ниже. Значит, вырез
/// от погоды не растёт ни на точку.
struct WeatherCorner: View {
    let snapshot: WeatherService.Snapshot
    let notchHeight: CGFloat

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: snapshot.condition.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(snapshot.condition.tint)
            Text("\(snapshot.temperature)°")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(height: notchHeight)
        .help(helpText)
    }

    private var helpText: String {
        guard let outlook = snapshot.outlook else { return snapshot.condition.title }
        return snapshot.condition.title + " · "
            + tf("через %d ч %@", outlook.inHours, outlook.condition.title.lowercased())
    }
}
