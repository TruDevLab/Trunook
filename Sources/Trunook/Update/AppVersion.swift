import Foundation

/// Номер версии, который можно сравнить.
///
/// Сравнивать версии строками нельзя, и это не придирка: в ряду версий этого
/// проекта есть 0.9.0 и 0.10.0, а `"0.9.0" > "0.10.0"` — правда для строк
/// и ложь для версий. Отсюда разбор на числа и сравнение по частям.
///
/// Номер сборки (`CFBundleVersion`) сюда не входит намеренно. Он собирается
/// из даты машины сборки, со стороны релиза его взять неоткуда, и монотонным
/// относительно выпусков он не бывает: у пересобранной руками 0.11.0 он больше,
/// чем у выпущенной 0.11.1.
struct AppVersion: Comparable, CustomStringConvertible {
    /// Части номера без хвостовых нулей: и 0.11, и 0.11.0 дают `[0, 11]`.
    /// Нормализация нужна, чтобы эти двое считались равными.
    let parts: [Int]

    /// У номера был хвост вроде «-beta». Такая версия младше одноимённой
    /// без хвоста. Практического значения не имеет — `/releases/latest`
    /// предрелизы не отдаёт вовсе, — но разбор обязан не падать на том,
    /// чего не ждал.
    let isPrerelease: Bool

    /// Как номер записан у источника: его и показывают человеку.
    /// Восстанавливать запись из `parts` нельзя — нормализация съела нули.
    let text: String

    /// Разбирает «0.11.1», «v0.12.0», «0.11» и «0.12.0-beta.1».
    ///
    /// Ведущая «v» приходит из имени тега GitHub, где она есть всегда.
    init?(_ source: String) {
        var rest = Substring(source.trimmingCharacters(in: .whitespacesAndNewlines))
        if rest.first == "v" || rest.first == "V" { rest = rest.dropFirst() }

        let head = rest.prefix { $0.isNumber || $0 == "." }
        let pieces = head.split(separator: ".", omittingEmptySubsequences: true)
        let numbers = pieces.compactMap { Int($0) }
        guard !numbers.isEmpty, numbers.count == pieces.count else { return nil }

        var normalized = numbers
        while normalized.count > 1, normalized.last == 0 { normalized.removeLast() }

        parts = normalized
        // Хвостом считается только «-» или «+»: строка вида «0.11.1 (2608301645)»
        // — это формат показа из `AppInfo.version`, а не предрелиз.
        let tail = rest[head.endIndex...].first
        isPrerelease = tail == "-" || tail == "+"
        text = String(head)
    }

    var description: String { text }

    private func part(_ index: Int) -> Int {
        index < parts.count ? parts[index] : 0
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.parts == rhs.parts && lhs.isPrerelease == rhs.isPrerelease
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0 ..< max(lhs.parts.count, rhs.parts.count) where lhs.part(index) != rhs.part(index) {
            return lhs.part(index) < rhs.part(index)
        }
        // Числа равны: предрелиз младше выпуска.
        return lhs.isPrerelease && !rhs.isPrerelease
    }
}
