import Foundation

extension Array where Element == CalendarItem {
    /// Ближайшие записи, начинающиеся в одну и ту же минуту.
    ///
    /// В календаре нередко стоят две встречи на один слот: приглашение
    /// и дубль от организатора, накладка двух команд, «созвон» поверх
    /// «фокус-времени». Показывать из них только первую — значит молча
    /// скрыть ровно тот факт, ради которого человек и смотрит в вырез:
    /// что в это время он занят дважды и надо выбирать.
    ///
    /// Список должен быть отсортирован по началу — таким его и отдаёт
    /// `CalendarService`.
    ///
    /// Сравниваем по минуте, а не по секунде: встречи, заведённые разными
    /// людьми, расходятся на доли секунды, и посекундное сравнение развело бы
    /// их по разным экранам.
    func startingTogether(limit: Int) -> [Element] {
        guard let first = self.first, limit > 0 else { return [] }
        let minute = Calendar.current.dateInterval(of: .minute, for: first.start)
        return prefix(limit).filter { item in
            guard let minute else { return item.start == first.start }
            return minute.contains(item.start)
        }
    }
}
