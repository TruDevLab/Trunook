import SwiftUI

/// Раздел полки, над которым держат файлы.
///
/// Пока файлы ведут над чёлкой, полка показывает не сетку, а четыре раздела
/// колонками: положить на полку, сжать или распаковать, поделиться ссылкой
/// из iCloud, в Корзину. Что сделают с файлами, решает раздел, над которым
/// их отпустили.
///
/// Разделы — колонки во всю высоту панели, и раздел узнаётся **по одной
/// горизонтали**. Это не упрощение, а правило совпадения: зону приёма держит
/// отдельное окно (`ShelfDropWindow`), и считать вёрстку SwiftUI заново
/// в его координатах значило бы завести второй расчёт, который однажды
/// разойдётся с первым. Горизонталь у обоих одна — ширина панели и её поля.
enum ShelfDropZone: Int, CaseIterable, Identifiable {
    case shelf
    case archive
    case share
    case trash

    var id: Int { rawValue }

    /// Подпись раздела. Сжать или распаковать — по тому, что держат: одни
    /// архивы распаковываются, всё прочее сжимается.
    func title(unpacks: Bool) -> String {
        switch self {
        case .shelf: return t("На полку")
        case .archive: return unpacks ? t("Распаковать") : t("Сжать в ZIP")
        case .share: return t("Ссылка iCloud")
        case .trash: return t("В Корзину")
        }
    }

    func symbol(unpacks: Bool) -> String {
        switch self {
        case .shelf: return "tray.and.arrow.down.fill"
        case .archive: return unpacks ? "shippingbox.and.arrow.backward.fill" : "archivebox.fill"
        case .share: return "link.icloud.fill"
        case .trash: return "trash.fill"
        }
    }

    var tint: Color {
        switch self {
        case .shelf: return Palette.shelf
        case .archive: return Palette.cyan
        case .share: return Palette.blue
        case .trash: return Palette.negative
        }
    }

    /// Раздел под горизонталью `x`, отсчитанной от левого края панели
    /// шириной `width`.
    ///
    /// Поля панели и промежутки между колонками достаются ближайшему разделу:
    /// промахнуться мимо всех четырёх, держа файл над панелью, нельзя.
    static func at(x: CGFloat, width: CGFloat, inset: CGFloat = NotchStyle.bodyInset) -> ShelfDropZone {
        let usable = max(1, width - 2 * inset)
        let share = (x - inset) / usable
        let index = Int((share * CGFloat(allCases.count)).rounded(.down))
        return ShelfDropZone(rawValue: min(max(index, 0), allCases.count - 1)) ?? .shelf
    }
}
