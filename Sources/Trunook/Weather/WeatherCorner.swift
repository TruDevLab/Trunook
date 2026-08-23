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
                .font(.system(size: NotchStyle.font(12), weight: .medium))
                .foregroundStyle(snapshot.condition.tint)
            Text("\(snapshot.temperature)°")
                .font(.system(size: NotchStyle.font(12), weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(height: notchHeight)
        // Не кнопка, но и не украшение: значок состояния плюс число.
        // Порознь диктор читал их как «12 градусов» — без самой погоды,
        // ради которой всё и показано. Собираем в один элемент и называем.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tf("%@, %d°", snapshot.condition.title, snapshot.temperature))
        .notchActionHint(helpText)
    }

    private var helpText: String {
        guard let outlook = snapshot.outlook else { return snapshot.condition.title }
        return snapshot.condition.title + " · "
            + tf("через %d ч %@", outlook.inHours, outlook.condition.title.lowercased())
    }
}
