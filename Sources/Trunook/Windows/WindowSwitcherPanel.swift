import SwiftUI

/// Переключатель окон в вырезе: ряд окон, заголовок выбранного, ряд его
/// вкладок, если это браузер.
///
/// Высота постоянна — ряд вкладок есть всегда, у небраузера в нём
/// подсказка. Иначе панель прыгала бы на каждом Tab, проходя мимо
/// браузеров, а листают её быстро.
///
/// Поле миниатюры у карточки тоже есть всегда: без снимка — без «Записи
/// экрана», у свёрнутого окна, у приложения без окон — в нём крупный значок.
/// Высота панели от разрешения не зависит.
struct WindowSwitcherPanel: View {
    @ObservedObject var switcher: WindowSwitcher
    let metrics: NotchMetrics
    let onClose: () -> Void

    static var width: CGFloat { NotchStyle.scaled(560) }

    private static var cardWidth: CGFloat { NotchStyle.scaled(104) }
    private static var previewSize: CGSize { CGSize(width: NotchStyle.scaled(96), height: NotchStyle.scaled(60)) }
    private static var cardHeight: CGFloat { previewSize.height + NotchStyle.scaled(30) }
    private static var iconSide: CGFloat { NotchStyle.scaled(38) }
    /// Значок приложения в углу миниатюры.
    private static var badgeSide: CGFloat { NotchStyle.scaled(20) }
    private static var titleHeight: CGFloat { NotchStyle.scaled(16) }
    private static var tabsHeight: CGFloat { NotchStyle.rowHeight }
    private static var tabWidth: CGFloat { NotchStyle.scaled(190) }

    static func height(notchHeight: CGFloat) -> CGFloat {
        NotchStyle.height(
            notchHeight: notchHeight,
            contentHeight: cardHeight + titleHeight + tabsHeight + 2 * NotchStyle.gridSpacing
        )
    }

    var body: some View {
        NotchPanel(metrics: metrics, width: Self.width) {
            NotchPanelTitle(symbol: "macwindow.on.rectangle", title: t("Окна"), tint: Palette.switcher)
        } trailing: {
            NotchPanelButton(symbol: "xmark", hint: t("Закрыть"), action: onClose)
        } content: {
            VStack(spacing: NotchStyle.gridSpacing) {
                if switcher.items.isEmpty {
                    Text(t("Собираю окна…"))
                        .font(.system(size: NotchStyle.rowFontSize))
                        .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.cardHeight)
                } else {
                    cards
                }
                title
                tabs
            }
        }
    }

    // MARK: - Окна

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: NotchStyle.cardGap) {
                    ForEach(Array(switcher.items.enumerated()), id: \.element.id) { index, item in
                        card(item, index: index)
                            .id(item.id)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: Self.cardHeight)
            .onChange(of: switcher.selected) { _, selected in
                guard switcher.items.indices.contains(selected) else { return }
                withAnimation(NotchMotion.reduced ? nil : .easeOut(duration: 0.15)) {
                    proxy.scrollTo(switcher.items[selected].id, anchor: .center)
                }
            }
            .onAppear {
                guard switcher.items.indices.contains(switcher.selected) else { return }
                proxy.scrollTo(switcher.items[switcher.selected].id, anchor: .center)
            }
        }
    }

    private func card(_ item: SwitcherItem, index: Int) -> some View {
        let isSelected = index == switcher.selected
        let isFocused = isSelected && !switcher.inTabs
        let shape = RoundedRectangle(cornerRadius: NotchStyle.cardRadius, style: .continuous)
        return VStack(spacing: 5) {
            preview(item)
            Text(item.appName)
                .font(.system(size: NotchStyle.captionFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(isSelected ? NotchStyle.primaryOpacity : NotchStyle.secondaryOpacity))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 4)
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .background(shape.fill(isSelected ? Palette.switcher.opacity(isFocused ? 0.2 : 0.1) : .clear))
        .overlay(shape.strokeBorder(Palette.switcher.opacity(isFocused ? 0.85 : 0), lineWidth: 1))
        // Приложение без окон на этом столе — тусклее: перейти к нему
        // можно, но окна, которое встанет перед глазами, нет.
        .opacity(item.kind == .app ? 0.7 : 1)
        .contentShape(shape)
        .onHover { inside in
            if inside { switcher.highlight(index) }
        }
        .onTapGesture { switcher.commit(at: index) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title == item.appName ? item.appName : "\(item.appName), \(item.title)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Поле миниатюры: снимок окна со значком приложения в углу,
    /// без снимка — крупный значок посередине.
    private func preview(_ item: SwitcherItem) -> some View {
        let size = Self.previewSize
        let thumbnail = item.windowNumber.flatMap { switcher.thumbnails[$0] }
        let shape = RoundedRectangle(cornerRadius: NotchStyle.tileRadius, style: .continuous)
        return ZStack(alignment: .bottomLeading) {
            shape.fill(.white.opacity(thumbnail == nil ? 0.04 : 0))
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                icon(item, side: Self.badgeSide)
                    .offset(x: -2, y: 4)
            } else {
                icon(item, side: Self.iconSide)
                    .frame(width: size.width, height: size.height)
            }
            if item.kind == .minimized {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: NotchStyle.font(11), weight: .bold))
                    .foregroundStyle(.white, .black.opacity(0.7))
                    .frame(width: size.width, height: size.height, alignment: .bottomTrailing)
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(NotchMotion.reduced ? nil : .easeOut(duration: 0.18), value: thumbnail != nil)
    }

    @ViewBuilder
    private func icon(_ item: SwitcherItem, side: CGFloat) -> some View {
        if let icon = switcher.icons[item.pid] {
            Image(nsImage: icon)
                .resizable()
                .frame(width: side, height: side)
        } else {
            RoundedRectangle(cornerRadius: NotchStyle.tileRadius)
                .fill(.white.opacity(0.08))
                .frame(width: side, height: side)
        }
    }

    private var title: some View {
        Text(Self.caption(switcher.current, tab: switcher.inTabs ? switcher.current?.tabs.tabs[safe: switcher.selectedTab] : nil))
            .font(.system(size: NotchStyle.rowFontSize))
            .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity)
            .frame(height: Self.titleHeight)
    }

    /// Заголовок окна и признак — свёрнуто, без окон. В ряду вкладок —
    /// полный заголовок выбранной вкладки: на самой вкладке он обрезан.
    static func caption(_ item: SwitcherItem?, tab: BrowserTab? = nil) -> String {
        if let tab { return tab.title }
        guard let item else { return " " }
        switch item.kind {
        case .window: return item.title
        case .minimized: return tf("%@ · свёрнуто", item.title)
        case .app: return tf("%@ · нет окон на этом столе", item.appName)
        }
    }

    // MARK: - Вкладки

    private var tabs: some View {
        Group {
            switch switcher.current?.tabs ?? .none {
            case let .loaded(_, tabs, active) where !tabs.isEmpty:
                tabRow(tabs, active: active)
            case .loading:
                hint(t("Вкладки…"))
            case .needsConsent:
                hint(t("↓ — разрешить доступ к вкладкам браузера"))
            case .denied:
                hint(t("Вкладки закрыты в «Автоматизации» системных настроек"))
            case .unavailable, .loaded:
                hint(t("У этого окна вкладок нет"))
            case .none:
                hint(t("Tab — дальше, отпустите — перейти, Esc — отмена"))
            }
        }
        .frame(height: Self.tabsHeight)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: NotchStyle.hintFontSize))
            .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
    }

    private func tabRow(_ tabs: [BrowserTab], active: Int) -> some View {
        HStack(spacing: 6) {
            // Стрелка подсказывает, как попасть в ряд: ↓ с клавиатуры.
            Image(systemName: switcher.inTabs ? "square.stack" : "arrow.down")
                .font(.system(size: NotchStyle.font(11), weight: .semibold))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .accessibilityHidden(true)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Array(tabs.enumerated()), id: \.element.id) { offset, tab in
                            tabChip(tab, offset: offset, isActive: tab.index == active)
                                .id(tab.id)
                        }
                    }
                }
                .scrollIndicators(.never)
                .onChange(of: switcher.selectedTab) { _, selected in
                    guard tabs.indices.contains(selected) else { return }
                    withAnimation(NotchMotion.reduced ? nil : .easeOut(duration: 0.15)) {
                        proxy.scrollTo(tabs[selected].id, anchor: .center)
                    }
                }
                .onAppear {
                    let index = switcher.inTabs ? switcher.selectedTab : (tabs.firstIndex { $0.index == active } ?? 0)
                    guard tabs.indices.contains(index) else { return }
                    proxy.scrollTo(tabs[index].id, anchor: .center)
                }
            }
        }
    }

    /// Вкладка — плотной тёмной подложкой, а не полупрозрачной белой:
    /// панель стеклянная, и над светлым окном белая подложка с серым
    /// текстом сливалась с тем, что под вырезом. Тёмная держит контраст
    /// на любом фоне.
    private func tabChip(_ tab: BrowserTab, offset: Int, isActive: Bool) -> some View {
        let isFocused = switcher.inTabs && switcher.selectedTab == offset
        let shape = RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
        return HStack(spacing: 5) {
            if isActive {
                Circle()
                    .fill(Palette.switcher)
                    .frame(width: 5, height: 5)
            }
            Text(tab.title)
                .font(.system(size: NotchStyle.rowFontSize, weight: isActive || isFocused ? .semibold : .medium))
                .foregroundStyle(.white.opacity(isFocused || isActive ? 1 : 0.85))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: Self.tabWidth)
        .frame(height: Self.tabsHeight)
        .background(shape.fill(isFocused ? Palette.switcher.opacity(0.35) : .black.opacity(0.55)))
        .overlay(shape.strokeBorder(isFocused ? Palette.switcher : .white.opacity(0.12), lineWidth: 1))
        .contentShape(shape)
        .onHover { inside in
            if inside { switcher.highlightTab(offset) }
        }
        .onTapGesture { switcher.commitTab(at: offset) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isFocused ? [.isButton, .isSelected] : .isButton)
    }
}
