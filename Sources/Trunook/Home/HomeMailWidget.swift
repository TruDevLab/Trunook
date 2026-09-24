import SwiftUI

/// Плитка «Почта»: сколько писем ждут разбора в Trudaybook и какое из них
/// главное. Нажатие открывает Trudaybook.
///
/// Числа приходят сводкой-файлом (`TrudaybookFeed`), а не из почтового
/// ящика: ящик — дело Trudaybook, он и решает, что считать разобранным.
struct MailWidget: View {
    let widget: HomeWidget
    @ObservedObject var feed: TrudaybookFeed
    let actions: HomeActions

    var body: some View {
        HomeTile(widget: widget, onTap: actions.openTrudaybook, hint: t("Открыть Trudaybook")) {
            // Такт в минуту: им сводка «стареет», если Trudaybook закрыли.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if let summary = feed.current(at: context.date) {
                    if widget.size == .small { small(summary) } else { wide(summary) }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        HomeCaption(kind: widget.kind)
                        Spacer(minLength: 0)
                        HomeEmpty(text: emptyText)
                    }
                }
            }
        }
    }

    private var emptyText: String {
        guard TrudaybookFeed.isInstalled else { return t("Нужен Trudaybook") }
        return feed.summary == nil ? t("Включите сводку в Trudaybook") : t("Trudaybook закрыт")
    }

    /// В клетку — значок, число и одна строка под ним.
    private func small(_ summary: TrudaybookSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: widget.kind.symbol)
                .font(.system(size: NotchStyle.font(11), weight: .semibold))
                .foregroundStyle(widget.kind.tint)
                .frame(height: NotchStyle.scaled(16))
            Spacer(minLength: 0)
            HomeValue(text: "\(summary.unresolved)", size: 18)
            Text(Self.detail(summary))
                .font(.system(size: NotchStyle.font(9.5), weight: .medium))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .lineLimit(1)
        }
    }

    private func wide(_ summary: TrudaybookSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HomeCaption(kind: widget.kind, trailing: Self.detail(summary))
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 8) {
                HomeValue(text: "\(summary.unresolved)", size: 22)
                if let top = summary.top, summary.unresolved > 0 {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(top.from)
                            .font(.system(size: NotchStyle.font(9.5), weight: .semibold))
                            .foregroundStyle(summary.important > 0 ? Palette.amber : .white.opacity(NotchStyle.secondaryOpacity))
                        Text(top.title)
                            .font(.system(size: NotchStyle.font(10.5)))
                            .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                    }
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// «важных: 2», «не разобрано» или «всё разобрано».
    static func detail(_ summary: TrudaybookSummary) -> String {
        if summary.unresolved == 0 { return t("всё разобрано") }
        if summary.important > 0 { return tf("важных: %d", summary.important) }
        return t("не разобрано")
    }
}
