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

    /// Ближайшее время и то, что идёт следом, — двумя слотами подряд.
    ///
    /// Одного слота мало: отсчёт до ближайшей встречи отвечает на вопрос
    /// «когда бежать», а планировать день по нему нельзя — что будет после,
    /// панель не показывала вовсе, и за этим приходилось идти в Календарь.
    ///
    /// Потолок общий на оба слота: панель растёт вниз, и высоту ей задаёт
    /// число строк, а не число слотов. Если ближайшее время занято тремя
    /// встречами разом, следующее не показывается — накладка сегодня важнее
    /// планов на вечер.
    func upcomingSlots(limit: Int) -> [Element] {
        let first = startingTogether(limit: limit)
        let rest = limit - first.count
        guard rest > 0 else { return first }
        return first + Array(dropFirst(first.count)).startingTogether(limit: rest)
    }

    /// Разбивает список на группы записей с общим временем начала.
    ///
    /// Группа — это одна подложка в панели. Отдельные подложки нужны именно
    /// здесь: записи одного времени связаны между собой (человек занят
    /// дважды и выбирает), а записи разного времени — нет, и общая подложка
    /// показала бы их как один блок расписания.
    func groupedByStart() -> [[Element]] {
        reduce(into: [[Element]]()) { groups, item in
            guard let last = groups.last?.last,
                  let minute = Calendar.current.dateInterval(of: .minute, for: last.start),
                  minute.contains(item.start)
            else {
                groups.append([item])
                return
            }
            groups[groups.count - 1].append(item)
        }
    }
}
