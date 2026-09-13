import SwiftUI

/// Список предложений моделей — строками формы, для окна настроек.
///
/// Все решения — какая пометка, какая кнопка, что написать о нехватке —
/// приняты в `ModelCatalogue.rows`; здесь только рисование. Экран
/// знакомства рисует те же строки по-своему, белым по стеклу, и общим
/// у двух экранов должен быть **состав строк**, а не их вид: один вид
/// на стекло и на форму был бы выдумкой.
struct ModelOfferRows: View {
    let rows: [ModelOfferRow]
    let onInstall: (String) -> Void
    let onSelect: (String) -> Void

    var body: some View {
        ForEach(rows) { row in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.offer.title)
                        .font(.system(size: SettingsStyle.font(13), weight: .medium))
                    badge(row.badge)
                    Spacer(minLength: 8)
                    Text(row.offer.sizeText)
                        .font(.system(size: SettingsStyle.font(11.5)))
                        .foregroundStyle(SettingsStyle.tertiary)
                    control(row)
                }
                Text(row.offer.detail)
                    .font(.system(size: SettingsStyle.font(11.5)))
                    .foregroundStyle(SettingsStyle.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if let warning = row.warning {
                    Text(warning)
                        .font(.system(size: SettingsStyle.font(11.5)))
                        .foregroundStyle(Palette.warning)
                }
            }
            // Непосильная строка приглушается целиком, но остаётся читаемой:
            // человек должен понять, что это не поломка, а «не для этой
            // машины».
            .opacity(row.badge == .heavy ? 0.55 : 1)
        }
    }

    @ViewBuilder
    private func badge(_ badge: ModelOfferRow.Badge) -> some View {
        switch badge {
        case .none, .heavy:
            EmptyView()
        case .recommended:
            label(t("рекомендуем"), tint: Palette.assistant)
        case .selected:
            label(t("отвечает"), tint: Palette.assistant)
        case .installed:
            label(t("скачана"), tint: SettingsStyle.tertiary)
        }
    }

    private func label(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: SettingsStyle.font(10.5), weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint.opacity(0.14))
            )
    }

    @ViewBuilder
    private func control(_ row: ModelOfferRow) -> some View {
        switch row.action {
        case .none:
            EmptyView()
        case .install:
            Button(t("Скачать")) { onInstall(row.offer.tag) }
        case .select:
            Button(t("Отвечать ею")) { onSelect(row.offer.tag) }
        case let .installing(share):
            HStack(spacing: 6) {
                ProgressView(value: share).controlSize(.small).frame(width: 70)
                Text(tf("%d%%", Int(share * 100)))
                    .font(.system(size: SettingsStyle.font(11)))
                    .foregroundStyle(SettingsStyle.tertiary)
                    .monospacedDigit()
            }
        case .queued:
            Text(t("в очереди"))
                .font(.system(size: SettingsStyle.font(11)))
                .foregroundStyle(SettingsStyle.tertiary)
        case .blocked:
            // Кнопки нет нарочно: нажать и ждать пять гигабайт ради модели,
            // которой не хватит памяти, — хуже, чем не дать нажать.
            EmptyView()
        }
    }
}
