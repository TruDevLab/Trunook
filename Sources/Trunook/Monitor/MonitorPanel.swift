import SwiftUI

/// Нагрузка на систему: три плитки в ряд.
///
/// По нажатию на любую открывается Мониторинг системы — панель показывает,
/// что происходит, а разбираться, кто именно ест ресурсы, идут туда.
struct MonitorPanel: View {
    @ObservedObject var monitor: MonitorService
    let metrics: NotchMetrics
    let onOpenActivityMonitor: () -> Void
    let onClose: () -> Void

    static var width: CGFloat { NotchStyle.scaled(440) }
    /// Поле от чёрного тела панели: плитки тянутся во всю ширину, и вогнутое
    /// плечо формы приходится считать явно. См. `NotchStyle.shoulderInset`.
    static let bodyPadding: CGFloat = NotchStyle.bottomPadding

    private static var tileHeight: CGFloat { NotchStyle.scaled(84) }
    private static let barHeight: CGFloat = 4

    static func height(notchHeight: CGFloat) -> CGFloat {
        NotchStyle.height(notchHeight: notchHeight, contentHeight: tileHeight)
    }

    var body: some View {
        NotchPanel(metrics: metrics, width: Self.width, bodyPadding: Self.bodyPadding) {
            NotchPanelTitle(symbol: "gauge.with.dots.needle.67percent",
                            title: t("Нагрузка"),
                            tint: Palette.monitor)
        } trailing: {
            NotchPanelButton(symbol: "xmark", hint: t("Закрыть"), action: onClose)
        } content: {
            HStack(spacing: NotchStyle.gridSpacing) {
                tile(
                    symbol: "cpu",
                    name: t("Процессор"),
                    share: monitor.sample.cpu,
                    caption: cpuCaption
                )
                tile(
                    symbol: "memorychip",
                    name: t("Память"),
                    share: monitor.sample.memoryShare,
                    caption: memoryCaption
                )
                tile(
                    symbol: "internaldrive",
                    name: t("Диск"),
                    share: monitor.sample.diskShare,
                    caption: diskCaption
                )
            }
            .frame(height: Self.tileHeight)
        }
    }

    // MARK: - Подписи

    /// Пока не набран первый промежуток, доли процессора не существует —
    /// и вместо неё стоит прочерк, а не ноль. Ноль здесь читался бы как
    /// «процессор простаивает», хотя это просто «ещё не знаем».
    private var cpuCaption: String {
        tf("%d ядер", ProcessInfo.processInfo.processorCount)
    }

    private var memoryCaption: String {
        tf("%@ из %@ ГБ",
           MonitorService.gigabytes(monitor.sample.memoryUsed),
           MonitorService.gigabytes(monitor.sample.memoryTotal))
    }

    private var diskCaption: String {
        let free = monitor.sample.diskTotal - monitor.sample.diskUsed
        return tf("%@ ГБ свободно", MonitorService.gigabytes(free))
    }

    // MARK: - Плитка

    private func tile(symbol: String, name: String, share: Double?, caption: String) -> some View {
        NotchTile(id: "monitor-" + symbol) {
            Button(action: onOpenActivityMonitor) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: symbol)
                            .font(.system(size: NotchStyle.font(10), weight: .semibold))
                            .foregroundStyle(Palette.monitor.opacity(0.9))
                        Text(name)
                            .font(.system(size: NotchStyle.captionFontSize, weight: .medium))
                            .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                        Spacer(minLength: 0)
                    }

                    Text(share.map(MonitorService.percent) ?? "—")
                        .font(.system(size: NotchStyle.font(22), weight: .semibold, design: .rounded))
                        // Моноширинные цифры: пропорциональные дёргают строку
                        // на каждом пересчёте, а он идёт дважды в секунду.
                        .monospacedDigit()
                        .foregroundStyle(.white)

                    bar(share: share ?? 0)

                    Text(caption)
                        .font(.system(size: NotchStyle.hintFontSize))
                        .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Self.tileHeight)
                // Без этого нажимаются только сами буквы: подложку рисует
                // NotchTile снаружи, и метка кнопки о ней не знает.
                .contentShape(RoundedRectangle(cornerRadius: NotchStyle.tileRadius, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
    }

    /// Полоска заполнения. Цвет меняется на высоких значениях: цифру ещё надо
    /// прочитать, а цвет виден боковым зрением.
    private func bar(share: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.10))
                Capsule()
                    .fill(tint(for: share))
                    .frame(width: max(Self.barHeight, proxy.size.width * min(1, max(0, share))))
            }
        }
        .frame(height: Self.barHeight)
    }

    private func tint(for share: Double) -> Color {
        switch share {
        case ..<0.7: return Palette.monitor
        case ..<0.9: return Palette.warning
        default: return Palette.negative
        }
    }
}
