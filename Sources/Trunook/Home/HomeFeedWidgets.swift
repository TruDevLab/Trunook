import SwiftUI

/// «09:00» для сегодняшнего, «12 сент.» для прочего: в плитке нет места
/// на полную дату, а сегодняшнее важнее различать по времени.
private func shortStamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Localization.shared.resolved.locale
    if Calendar.current.isDateInToday(date) {
        formatter.dateFormat = "HH:mm"
    } else {
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
    }
    return formatter.string(from: date)
}

// MARK: - Новости

/// Заголовки последней сводки; заголовок ведёт на свою новость.
struct NewsWidget: View {
    let widget: HomeWidget
    @ObservedObject var digest: DigestService
    let actions: HomeActions

    var body: some View {
        let latest = digest.digests.first
        let entries = latest?.sections.flatMap(\.entries) ?? []
        let shown = Array(entries.prefix(HomeListRow.capacity(widget.size)))
        HomeTile(widget: widget, onTap: { actions.openFeeds(.news) }, hint: t("Открыть сводки")) {
            VStack(alignment: .leading, spacing: 4) {
                HomeCaption(
                    kind: widget.kind,
                    trailing: latest.map { (digest.hasUnseen ? "● " : "") + shortStamp($0.createdAt) }
                )
                if digest.isRunning {
                    HomeEmpty(text: digest.progress ?? t("Собираю сводку…"))
                } else if latest == nil {
                    HomeEmpty(text: t("Сводок ещё не было"))
                } else if shown.isEmpty {
                    HomeEmpty(text: t("Новостей не нашлось"))
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(shown) { entry in
                            Button { actions.join(entry.link) } label: {
                                HomeListRow(text: entry.title, detail: entry.source, dot: widget.kind.tint)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle())
                            .notchActionHint(entry.source)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Сайты

/// Слежки строками: имя и последнее значение, точка — у изменившихся.
struct SitesWidget: View {
    let widget: HomeWidget
    @ObservedObject var sites: SiteWatchService
    @ObservedObject var settings: Settings
    let actions: HomeActions

    var body: some View {
        let watches = settings.siteWatches.filter(\.isEnabled)
        let shown = Array(watches.prefix(HomeListRow.capacity(widget.size)))
        HomeTile(widget: widget, onTap: { actions.openFeeds(.sites) }, hint: t("Открыть слежку")) {
            VStack(alignment: .leading, spacing: 4) {
                HomeCaption(kind: widget.kind, trailing: watches.isEmpty ? nil : "\(watches.count)")
                if watches.isEmpty {
                    HomeEmpty(text: t("Слежек нет"))
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(shown) { watch in
                            let state = sites.state(of: watch)
                            HomeListRow(
                                text: watch.displayName,
                                detail: sites.checkingID == watch.id
                                    ? t("проверяю…")
                                    : state.reading?.text ?? "—",
                                dot: state.unseen ? widget.kind.tint : .white.opacity(0.2)
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Буфер обмена

/// Последнее скопированное.
struct ClipboardWidget: View {
    let widget: HomeWidget
    @ObservedObject var clipboard: ClipboardService
    let actions: HomeActions

    var body: some View {
        let entry = clipboard.entries.first
        HomeTile(widget: widget, onTap: actions.openClipboard, hint: t("Открыть буфер")) {
            VStack(alignment: .leading, spacing: 4) {
                HomeCaption(kind: widget.kind, trailing: entry.map { shortStamp($0.copiedAt) })
                if let entry {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: entry.kind.symbol)
                            .font(.system(size: NotchStyle.font(10)))
                            .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                        Text(entry.text.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: NotchStyle.font(11.5)))
                            .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                            .lineLimit(HomeListRow.capacity(widget.size))
                    }
                } else {
                    HomeEmpty(text: t("Буфер пуст"))
                }
            }
        }
    }
}

// MARK: - Полка

struct ShelfWidget: View {
    let widget: HomeWidget
    @ObservedObject var shelf: ShelfStore
    let actions: HomeActions

    var body: some View {
        HomeTile(widget: widget, onTap: actions.openShelf, hint: t("Открыть полку")) {
            if widget.size == .small {
                VStack(alignment: .leading, spacing: 0) {
                    HomeCaption(kind: widget.kind)
                    Spacer(minLength: 0)
                    HomeValue(text: "\(shelf.items.count)")
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HomeCaption(kind: widget.kind, trailing: shelf.isEmpty ? nil : "\(shelf.items.count)")
                    if shelf.isEmpty {
                        HomeEmpty(text: t("Полка пуста"))
                    } else {
                        HStack(spacing: 6) {
                            ForEach(shelf.items.prefix(6)) { item in
                                Image(nsImage: shelf.thumbnails[item.url] ?? shelf.icon(for: item))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 24, height: 24)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Заметки

/// Последние заметки и «плюс» — начать новую.
struct NotesWidget: View {
    let widget: HomeWidget
    @ObservedObject var notes: NotesService
    let actions: HomeActions

    var body: some View {
        let shown = Array(notes.notes.prefix(HomeListRow.capacity(widget.size)))
        HomeTile(widget: widget, onTap: actions.openNotes, hint: t("Открыть заметки")) {
            VStack(alignment: .leading, spacing: 4) {
                HomeCaption(kind: widget.kind)
                    .padding(.trailing, 22)
                if shown.isEmpty {
                    HomeEmpty(text: t("Заметок пока нет"))
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(shown) { note in
                            Button { actions.openNote(note) } label: {
                                HomeListRow(text: note.title, detail: shortStamp(note.updatedAt))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                HomeTileButton(symbol: "plus", hint: t("Новая заметка"), diameter: 20, action: actions.newNote)
                    .offset(y: -3)
            }
        }
    }
}
