import TrunookXPC
import Foundation
import EventKit

/// Запись напоминаний.
///
/// Отдельным расширением, как и `CalendarWriter`, и по той же причине:
/// в теле службы разговор один — «что впереди», — а здесь другой. До сих
/// пор приложение напоминания только читало: `EKReminder` во всём проекте
/// не встречался ни разу.
extension CalendarService {
    /// Списки, куда можно писать.
    ///
    /// Спрашиваем хранилище напрямую, а **не** `availableReminderLists`:
    /// тот заполняется побочно, внутри чтения напоминаний, и до первого
    /// такого чтения пуст. Помощника зовут раньше — и список оказался бы
    /// пустым ровно в тот миг, когда он нужен.
    func writableReminderLists() -> [CalendarSource] {
        guard remindersAccess == .fullAccess else { return [] }
        return store.calendars(for: .reminder)
            .filter { $0.allowsContentModifications }
            .map(CalendarSource.init)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Завести напоминание.
    ///
    /// `hasTime` отделяет «во вторник» от «во вторник в десять»: у первого
    /// в составляющих даты часа нет вовсе, и чтение различает их именно так
    /// (`components.hour == nil`). Две половины обязаны говорить об одном.
    ///
    /// **Одного срока мало, чтобы напоминание сработало.** Со сроком, но без
    /// будильника оно молча лежит в списке и не звонит никогда — и человек
    /// скажет «напоминание не сработало», и будет прав. Поэтому ко времени
    /// добавляется `EKAlarm`.
    @discardableResult
    func addReminder(
        title: String,
        due: Date?,
        hasTime: Bool,
        listNamed name: String? = nil,
        calendar: Calendar = .current
    ) -> Bool {
        // Полный доступ, а не «только запись»: у напоминаний такой ступени
        // нет вовсе, и половинчатый доступ означал бы отказ хранилища уже
        // на сохранении.
        guard remindersAccess == .fullAccess else {
            DebugLog.write("напоминание: нет полного доступа")
            return false
        }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            DebugLog.write("напоминание: пустое название")
            return false
        }
        guard let list = reminderList(named: name) else {
            DebugLog.write("напоминание: некуда писать — нет списка с правом записи")
            return false
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = clean
        reminder.calendar = list

        if let due {
            reminder.dueDateComponents = calendar.dateComponents(
                hasTime
                    ? [.year, .month, .day, .hour, .minute]
                    : [.year, .month, .day],
                from: due
            )
            // Звонок ставится только ко времени: у напоминания на целый день
            // звонить не в чем — часа нет, и система выбрала бы полночь.
            if hasTime { reminder.addAlarm(EKAlarm(absoluteDate: due)) }
        }

        do {
            try store.save(reminder, commit: true)
            DebugLog.write("напоминание: «\(clean)» в «\(list.title)»"
                           + (due == nil ? ", без срока" : ", со сроком"))
            refresh()
            return true
        } catch {
            DebugLog.write("напоминание: не сохранилось — \(error.localizedDescription)")
            return false
        }
    }

    /// Куда писать. Названный список ищется по имени без оглядки на регистр,
    /// а не находится — берём тот, что система считает основным.
    private func reminderList(named name: String?) -> EKCalendar? {
        let writable = store.calendars(for: .reminder).filter { $0.allowsContentModifications }
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty,
           let found = writable.first(where: { $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return found
        }
        if let system = store.defaultCalendarForNewReminders(),
           system.allowsContentModifications {
            return system
        }
        return writable.first
    }
}
