import SwiftUI

/// Отрисовка Markdown в окне знакомства.
///
/// Своя, а не общая с панелью выреза, и это не оплошность. Панель рисует
/// ответ модели: белым по чёрному стеклу, кеглями `NotchStyle`, шириной
/// в чёлку. Здесь — страница описания: кегли `WelcomeStyle`, которые растут
/// вместе с системным размером текста, ширина в пол-окна и таблицы, которых
/// в вырезе не бывает. Общим у двух этих отрисовок остался разбор
/// (`MarkdownRender`), а он и есть то, чему нельзя разойтись.
struct WelcomeMarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(WelcomeMarkdown.blocks(from: markdown)) { block in
                switch block {
                case let .line(line): markdownLine(line)
                case let .table(_, header, rows): table(header: header, rows: rows)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func markdownLine(_ line: MarkdownRender.Line) -> some View {
        switch line.kind {
        case .rule:
            Divider().overlay(Color.white.opacity(0.12)).padding(.vertical, 4)

        case let .heading(level):
            Text(line.text)
                .font(.system(
                    size: level == 1 ? WelcomeStyle.chapter : (level == 2 ? WelcomeStyle.deck : WelcomeStyle.title),
                    weight: .semibold,
                    design: .rounded
                ))
                .foregroundStyle(.white)
                // Заголовок отбивается сверху, а не снизу: он открывает
                // свой кусок текста и должен стоять к нему ближе, чем
                // к предыдущему.
                .padding(.top, level == 1 ? 2 : 12)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .item(marker):
            // Маркер в колонке постоянной ширины: иначе перенос длинного
            // пункта уезжает под сам маркер и список перестаёт быть списком.
            HStack(alignment: .top, spacing: 7) {
                Text(marker)
                    .font(.system(size: WelcomeStyle.body, design: .rounded))
                    .foregroundStyle(WelcomePalette.cyan.opacity(0.7))
                    .frame(width: WelcomeStyle.scaled(16), alignment: .trailing)
                Text(line.text)
                    .font(.system(size: WelcomeStyle.body, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .quote:
            HStack(alignment: .top, spacing: 9) {
                Rectangle()
                    .fill(WelcomePalette.cyan.opacity(0.4))
                    .frame(width: 2)
                Text(line.text)
                    .font(.system(size: WelcomeStyle.body, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .code:
            Text(line.text)
                .font(.system(size: WelcomeStyle.caption, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.8))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )

        case .paragraph:
            Text(line.text)
                .font(.system(size: WelcomeStyle.body, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func table(header: [String], rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            row(header, isHeader: true)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, cells in
                Divider().overlay(Color.white.opacity(0.07))
                row(cells, isHeader: false)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(WelcomePalette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(WelcomePalette.cardStroke, lineWidth: 0.5)
                )
        )
        .padding(.vertical, 3)
    }

    /// Первая колонка уже прочих и не растягивается: в таблицах README слева
    /// стоит сочетание клавиш или короткое имя, а справа — объяснение, и
    /// поделённая пополам ширина оставляла бы объяснению половину строки.
    private func row(_ cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                Text(cell)
                    .font(.system(
                        size: isHeader ? WelcomeStyle.caption : WelcomeStyle.body,
                        weight: isHeader ? .semibold : .regular,
                        design: .rounded
                    ))
                    .foregroundStyle(isHeader
                                     ? Color.white.opacity(0.5)
                                     : Color.white.opacity(index == 0 ? 0.92 : 0.72))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(
                        maxWidth: index == 0 ? WelcomeStyle.scaled(150) : .infinity,
                        alignment: .leading
                    )
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
    }
}
