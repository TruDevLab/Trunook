import SwiftUI

/// Страница «Описание» в окне знакомства: что изменилось в выпусках и README.
///
/// Живёт в окне, а не в вырезе, и это не вкусовщина: описание выпуска — это
/// страница текста с заголовками, списками и таблицами. В панели под чёлкой
/// от неё осталось бы полторы строки.
///
/// Слева список: свежий выпуск первым, под ним прошлые, отдельной строкой
/// README. Справа — сам текст. Обе половины в прокрутке: список выпусков
/// растёт с каждым релизом, а описание бывает и на два экрана.
struct WelcomeNotesPage: View {
    @ObservedObject var notes: ReleaseNotesService

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                sidebar
                readmeRow
            }
            Divider().overlay(Color.white.opacity(0.08))
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Список слева

    private var sidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                if case .loading = notes.state {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text(t("Загружаем…"))
                            .font(.system(size: WelcomeStyle.caption, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                }

                // Отказ показывается здесь, а не вместо текста: справа
                // в это время открыт README, и подменять его сообщением
                // об ошибке значило бы убрать у человека единственное,
                // что всё-таки прочиталось.
                if case .failed = notes.state {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(t("Описания не загрузились"))
                            .font(.system(size: WelcomeStyle.micro, design: .rounded))
                            .foregroundStyle(WelcomePalette.amber.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                        Button(t("Попробовать снова")) { notes.load() }
                            .buttonStyle(WelcomeGhostButton(isQuiet: true))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }

                ForEach(notes.notes) { note in
                    row(
                        title: note.version.text,
                        detail: dateLabel(note.publishedAt),
                        isSelected: notes.selection == .release(tag: note.tag)
                    ) {
                        notes.select(.release(tag: note.tag))
                    }
                }

            }
            .padding(.trailing, 2)
        }
        .frame(width: WelcomeStyle.notesSidebar)
    }

    /// README стоит под списком и **вне** прокрутки.
    ///
    /// Внутри он уезжал за нижнюю кромку: выпусков уже дюжина, и до строки,
    /// ради которой в это окно приходит половина читателей, приходилось
    /// прокручивать весь список версий.
    private var readmeRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.bottom, 6)
            row(
                title: t("О приложении"),
                detail: t("README"),
                isSelected: notes.selection == .readme
            ) {
                notes.select(.readme)
            }
        }
        .frame(width: WelcomeStyle.notesSidebar)
    }

    private func row(
        title: String,
        detail: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: WelcomeStyle.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : Color.white.opacity(0.72))
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: WelcomeStyle.micro, design: .rounded))
                        .foregroundStyle(Color.white.opacity(isSelected ? 0.55 : 0.35))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? WelcomePalette.cyan.opacity(0.16) : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isSelected ? WelcomePalette.cyan.opacity(0.35) : .clear,
                                lineWidth: 0.5
                            )
                    )
            )
            // Без этого нажимается только по самим буквам: подложка
            // нарисована фоном, а фон в проверке попаданий не участвует.
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Текст справа

    @ViewBuilder
    private var content: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 10) {
                switch notes.selection {
                case .readme:
                    WelcomeMarkdownView(markdown: ReleaseNotesService.readme(
                        language: Localization.shared.resolved
                    ))
                case let .release(tag):
                    if let note = notes.note(tagged: tag) {
                        releaseHeader(note)
                        WelcomeMarkdownView(markdown: note.body.isEmpty
                                            ? t("У этого выпуска нет описания.")
                                            : note.body)
                    } else {
                        placeholder
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 6)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func releaseHeader(_ note: ReleaseNote) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(size: WelcomeStyle.chapter, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                let date = dateLabel(note.publishedAt)
                if !date.isEmpty {
                    Text(date)
                        .font(.system(size: WelcomeStyle.caption, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            Spacer(minLength: 0)
            if let page = note.pageURL {
                Link(t("На GitHub"), destination: page)
                    .font(.system(size: WelcomeStyle.caption, design: .rounded))
                    .foregroundStyle(WelcomePalette.cyan)
            }
        }
        .padding(.bottom, 2)
    }

    /// Ни сети, ни кэша. README при этом на месте — он в бандле, — и предложить
    /// его лучше, чем оставить человека перед пустым листом.
    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("Описания выпусков не загрузились"))
                .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(t("Нужен интернет: описания лежат на странице выпусков GitHub."))
                .font(.system(size: WelcomeStyle.body, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
            Button(t("Попробовать снова")) { notes.load() }
                .buttonStyle(WelcomeGhostButton())
                .padding(.top, 4)
        }
    }

    private func dateLabel(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Localization.shared.resolved.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
