import SwiftUI

/// Сколько осталось до события — чистые правила, под тестом.
///
/// Дальше суток — днями и часами: секунды у события через три недели
/// только мельтешат. Ближе — часами, минутами и секундами, и тогда плитка
/// тикает.
enum CountdownClock {
    struct Parts: Equatable {
        var days: Int
        var hours: Int
        var minutes: Int
        var seconds: Int
    }

    /// `nil` — событие уже наступило.
    static func parts(from now: Date, to target: Date) -> Parts? {
        let total = Int(target.timeIntervalSince(now).rounded(.up))
        guard total > 0 else { return nil }
        return Parts(
            days: total / 86_400,
            hours: total % 86_400 / 3600,
            minutes: total % 3600 / 60,
            seconds: total % 60
        )
    }

    /// Текст отсчёта. `compact` — для малой плитки: одни дни, без часов.
    static func text(_ parts: Parts, compact: Bool) -> String {
        if parts.days > 0 {
            return compact || parts.hours == 0
                ? tf("%d дн", parts.days)
                : tf("%d дн %d ч", parts.days, parts.hours)
        }
        return String(format: "%d:%02d:%02d", parts.hours, parts.minutes, parts.seconds)
    }
}

/// Плитка обратного отсчёта: название события и сколько до него осталось.
/// Нажатие ведёт в настройки главного экрана — там событие и задают.
struct CountdownWidget: View {
    let widget: HomeWidget
    @ObservedObject var settings: Settings
    let actions: HomeActions

    var body: some View {
        HomeTile(widget: widget, onTap: actions.editCountdown, hint: t("Изменить событие")) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(now: context.date)
            }
        }
    }

    private var title: String {
        let name = settings.countdownEventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? t("Событие") : name
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let target = settings.countdownEventDate {
            let parts = CountdownClock.parts(from: now, to: target)
            let value = parts.map { CountdownClock.text($0, compact: widget.size == .small) } ?? t("Наступило")
            if widget.size == .small {
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: widget.kind.symbol)
                        .font(.system(size: NotchStyle.font(11), weight: .semibold))
                        .foregroundStyle(widget.kind.tint)
                        .frame(height: NotchStyle.scaled(16))
                    Spacer(minLength: 0)
                    HomeValue(text: value, size: 18)
                    Text(title)
                        .font(.system(size: NotchStyle.font(9.5), weight: .medium))
                        .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                        .lineLimit(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HomeCaption(kind: widget.kind, title: title, trailing: Self.dateText(target, now: now))
                    Spacer(minLength: 0)
                    HomeValue(text: value, size: 22)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HomeCaption(kind: widget.kind)
                HomeEmpty(text: t("Задайте событие в настройках"))
            }
        }
    }

    /// Дата события: в этом году — без года, время — если оно не полночь.
    static func dateText(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        var style = Date.FormatStyle().day().month(.abbreviated)
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) {
            style = style.year()
        }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        if parts.hour != 0 || parts.minute != 0 {
            style = style.hour().minute()
        }
        return date.formatted(style.locale(Localization.shared.resolved.locale))
    }
}
