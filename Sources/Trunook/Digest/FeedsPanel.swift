import SwiftUI

/// Что выбрано в панели сводок. У контроллера, а не в панели: `@State`
/// в этом тулчейне недоступен, а пережить закрытие накладки выбор обязан —
/// открыв панель снова, человек ждёт ту же вкладку.
final class FeedsPanelState: ObservableObject {
    enum Mode: CaseIterable, Identifiable {
        case news
        case sites

        var id: Self { self }

        var title: String {
            switch self {
            case .news: return t("Новости")
            case .sites: return t("Сайты")
            }
        }
    }

    @Published var mode: Mode = .news
    /// Какая сводка открыта: 0 — самая свежая.
    @Published var digestIndex = 0
}

/// Сводки новостей и слежка за сайтами — одна накладка на обе.
///
/// Одна, а не две: меню функций заполнено до края, а обе работы про одно —
/// «что изменилось в мире, пока я не смотрел». Высота постоянная, список
/// прокручивается: сводка на пять тем по пять новостей выше любого окна.
struct FeedsPanel: View {
    @ObservedObject var digest: DigestService
    @ObservedObject var sites: SiteWatchService
    @ObservedObject var panel: FeedsPanelState
    @ObservedObject var settings: Settings
    let metrics: NotchMetrics
    let onOpenLink: (URL) -> Void
    let onSaveToNotes: (Digest) -> Void
    let onExport: (Digest) -> Void
    let onVerify: (SiteWatch) -> Void
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    static var width: CGFloat { NotchStyle.scaled(480) }
    static let bodyPadding: CGFloat = NotchStyle.bottomPadding
    private static var modeHeight: CGFloat { NotchStyle.scaled(26) }
    private static var listHeight: CGFloat { NotchStyle.scaled(290) }

    static func height(notchHeight: CGFloat) -> CGFloat {
        NotchStyle.height(
            notchHeight: notchHeight,
            contentHeight: modeHeight + NotchStyle.gridSpacing + listHeight
        )
    }

    private var current: Digest? {
        guard !digest.digests.isEmpty else { return nil }
        return digest.digests[min(panel.digestIndex, digest.digests.count - 1)]
    }

    var body: some View {
        NotchPanel(metrics: metrics, width: Self.width, bodyPadding: Self.bodyPadding) {
            NotchPanelTitle(symbol: "newspaper", title: t("Сводки"), tint: Palette.feeds)
        } trailing: {
            HStack(spacing: 2) {
                switch panel.mode {
                case .news:
                    if let current {
                        NotchPanelButton(symbol: "square.and.pencil", hint: t("В заметки")) {
                            onSaveToNotes(current)
                        }
                        NotchPanelButton(symbol: "arrow.down.doc", hint: t("Скачать .md")) {
                            onExport(current)
                        }
                    }
                    NotchPanelButton(symbol: "arrow.clockwise", hint: t("Собрать сейчас")) {
                        panel.digestIndex = 0
                        digest.run(manual: true)
                    }
                case .sites:
                    NotchPanelButton(symbol: "arrow.clockwise", hint: t("Проверить сейчас")) {
                        sites.checkAll()
                    }
                }
                // Настройки — сразу на разделе сводок: темы, расписание
                // и сайты правят именно там, а общее окно на «Основных»
                // заставляло бы искать раздел.
                NotchPanelButton(symbol: "gearshape", hint: t("Настройки сводок"), action: onOpenSettings)
                NotchPanelButton(symbol: "xmark", hint: t("Закрыть"), action: onClose)
            }
        } content: {
            VStack(spacing: NotchStyle.gridSpacing) {
                modeSwitch
                Group {
                    switch panel.mode {
                    case .news: newsList
                    case .sites: sitesList
                    }
                }
                .frame(height: Self.listHeight)
                .clipped()
            }
        }
    }

    // MARK: - Переключатель

    private func hasUnseen(_ mode: FeedsPanelState.Mode) -> Bool {
        switch mode {
        case .news: return digest.hasUnseen
        case .sites: return sites.hasUnseen
        }
    }

    private var modeSwitch: some View {
        HStack(spacing: 4) {
            ForEach(FeedsPanelState.Mode.allCases) { mode in
                let isChosen = panel.mode == mode
                Button { panel.mode = mode } label: {
                    HStack(spacing: 5) {
                        Text(mode.title)
                        // Точка — значение, а не ветка: прозрачная, пока
                        // нового нет, и место под неё не прыгает.
                        Circle()
                            .fill(Palette.feeds)
                            .frame(width: 5, height: 5)
                            .opacity(hasUnseen(mode) ? 1 : 0)
                    }
                    .font(.system(size: NotchStyle.rowFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(isChosen ? 1 : NotchStyle.secondaryOpacity))
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.modeHeight)
                    .surface(.segment, in: pillShape, lit: isChosen, glass: Surface.inNotch && isChosen)
                    .contentShape(pillShape)
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(isChosen ? [.isSelected] : [])
            }
        }
        .frame(height: Self.modeHeight)
        .surface(.card, in: pillShape, glass: Surface.inNotch)
    }

    private var pillShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
    }

    // MARK: - Новости

    @ViewBuilder
    private var newsList: some View {
        if let current {
            VStack(spacing: 6) {
                digestHeader(current)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(current.sections) { section in
                            sectionView(section)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        } else {
            message(
                symbol: "newspaper",
                text: digest.isRunning
                    ? (digest.progress ?? t("Собираю сводку…"))
                    : emptyNewsText
            )
        }
    }

    private var emptyNewsText: String {
        if !settings.ollamaEnabled { return t("Сводку собирает модель — включите её в настройках") }
        if digest.activeTopics.isEmpty { return t("Добавьте темы в настройках — сводка соберётся по расписанию") }
        return digest.lastFailed ? t("Сводка не собралась — проверьте сеть и модель") : t("Сводок пока нет")
    }

    private func digestHeader(_ shown: Digest) -> some View {
        HStack(spacing: 4) {
            NotchPanelButton(symbol: "chevron.left", hint: t("Предыдущая сводка")) {
                panel.digestIndex = min(panel.digestIndex + 1, digest.digests.count - 1)
            }
            .disabled(panel.digestIndex >= digest.digests.count - 1)

            Text(digest.isRunning ? (digest.progress ?? t("Собираю сводку…")) : stamp(shown.createdAt))
                .font(.system(size: NotchStyle.captionFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            NotchPanelButton(symbol: "chevron.right", hint: t("Следующая сводка")) {
                panel.digestIndex = max(panel.digestIndex - 1, 0)
            }
            .disabled(panel.digestIndex == 0)
        }
        .frame(height: NotchPanelButton.size)
    }

    private func sectionView(_ section: DigestSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.title)
                .font(.system(size: NotchStyle.captionFontSize, weight: .semibold))
                .foregroundStyle(Palette.feeds)
                .lineLimit(1)
                .padding(.leading, 2)
            if section.failed {
                note(t("Не удалось собрать"))
            } else if section.entries.isEmpty {
                note(t("Ничего значимого за период"))
            } else {
                ForEach(section.entries) { entry in
                    entryRow(entry)
                }
            }
        }
    }

    /// Плитка снаружи, кнопка внутри — как у строк команд. Плитка в метке
    /// кнопки не рисовала содержимого вовсе: место занимала, а строки не было.
    private func entryRow(_ entry: DigestEntry) -> some View {
        NotchTile(id: "digest-\(entry.id)", radius: NotchStyle.rowRadius) {
            Button { onOpenLink(entry.link) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.system(size: NotchStyle.rowFontSize, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(entry.source) · \(stamp(entry.published))")
                        .font(.system(size: NotchStyle.captionFontSize))
                        .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                        .lineLimit(1)
                    if !entry.summary.isEmpty {
                        Text(entry.summary)
                            .font(.system(size: NotchStyle.captionFontSize))
                            .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .notchHint(t("Открыть источник"))
        }
    }

    // MARK: - Сайты

    @ViewBuilder
    private var sitesList: some View {
        let watches = settings.siteWatches
        if watches.isEmpty {
            message(symbol: "binoculars", text: t("Добавьте страницу в настройках — сообщу, когда изменится то, за чем вы следите"))
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(watches) { watch in
                        siteRow(watch)
                    }
                }
            }
        }
    }

    private func siteRow(_ watch: SiteWatch) -> some View {
        let state = sites.state(of: watch)
        return NotchTile(id: "site-\(watch.id)", radius: NotchStyle.rowRadius,
                         isHighlighted: state.unseen) {
            HStack(spacing: 4) {
                Button { watch.pageURL.map(onOpenLink) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(watch.displayName)
                                .font(.system(size: NotchStyle.rowFontSize, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(state.reading?.text ?? "—")
                                .font(.system(size: NotchStyle.rowFontSize, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(state.unseen ? Palette.feeds : .white)
                                .lineLimit(1)
                        }
                        Text(statusText(watch, state))
                            .font(.system(size: NotchStyle.captionFontSize))
                            .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                            .lineLimit(1)
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, state.status == .blocked ? 0 : 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .notchHint(t("Открыть сайт"))

                if state.status == .blocked {
                    NotchPanelButton(symbol: "checkmark.shield", hint: t("Пройти проверку сайта")) {
                        onVerify(watch)
                    }
                    .padding(.trailing, 4)
                }
            }
        }
    }

    private func statusText(_ watch: SiteWatch, _ state: WatchState) -> String {
        if sites.checkingID == watch.id { return t("Проверяю…") }
        if !watch.isEnabled { return t("Слежка выключена") }
        let checked = state.checkedAt.map { tf("проверено %@", stamp($0)) } ?? t("ещё не проверялся")
        switch state.status {
        case .waiting: return checked
        case .ok:
            guard let previous = state.previous, state.changedAt != nil else { return checked }
            return "\(tf("было %@", previous.text)) · \(checked)"
        case .blocked: return tf("Сайт не пустил · %@", checked)
        case .notFound: return tf("Не нашлось на странице · %@", checked)
        case .failed: return tf("Не удалось проверить · %@", checked)
        }
    }

    // MARK: - Общее

    private func message(symbol: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: NotchStyle.font(18)))
                .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
            Text(text)
                .font(.system(size: NotchStyle.font(11.5)))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .multilineTextAlignment(.center)
            Button(action: onOpenSettings) {
                Text(t("Настройки"))
                    .font(.system(size: NotchStyle.captionFontSize, weight: .medium))
                    .foregroundStyle(Palette.feeds)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: NotchStyle.captionFontSize))
            .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
            .padding(.leading, 2)
    }

    private func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Localization.shared.resolved.locale
        formatter.setLocalizedDateFormatFromTemplate(
            Calendar.current.isDateInToday(date) ? "HH:mm" : "d MMM HH:mm"
        )
        return formatter.string(from: date)
    }
}

/// Что-то новое ждёт: полоска в свёрнутой чёлке.
struct FeedChip: Equatable {
    let digest: Bool
    let sites: Bool
}

/// Метка непрочитанной сводки или изменения на сайте.
///
/// Плашка живёт полминуты, а в десять утра человека может не быть рядом.
/// Метка держится, пока панель не откроют, — как полоска чашки держится,
/// пока горит чашка.
struct FeedChipView: View {
    let chip: FeedChip
    let metrics: NotchMetrics
    let onOpen: () -> Void

    private static let sideMargin: CGFloat = 34
    private static let symbolSize: CGFloat = 11

    static func sideWidth() -> CGFloat {
        symbolSize + sideMargin
    }

    static func width(metrics: NotchMetrics) -> CGFloat {
        metrics.notchWidth + 2 * sideWidth()
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: chip.digest ? "newspaper.fill" : "binoculars.fill")
                .font(.system(size: Self.symbolSize, weight: .semibold))
                .foregroundStyle(Palette.feeds)
                .frame(width: Self.sideWidth())
            Spacer(minLength: 0)
                .frame(width: metrics.notchWidth)
            Circle()
                .fill(Palette.feeds)
                .frame(width: 6, height: 6)
                .frame(width: Self.sideWidth())
        }
        .frame(width: Self.width(metrics: metrics), height: metrics.notchHeight)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .notchHint(chip.digest ? t("Новая сводка") : t("Сайт изменился"), bubble: t("Открыть"))
    }
}
