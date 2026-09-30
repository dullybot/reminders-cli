import EventKit
import Foundation

/// Field changes shared by `add` and `edit`; nil leaves a field untouched.
struct ReminderChanges {
    var title: String?
    /// An empty string clears the notes.
    var notes: String?
    var dueDate: DateComponents?
    var clearDueDate = false
    var priority: Priority?
    var recurrence: Recurrence?
    var clearRecurrence = false

    var isEmpty: Bool {
        self.title == nil && self.notes == nil && self.dueDate == nil && !self.clearDueDate
            && self.priority == nil && self.recurrence == nil && !self.clearRecurrence
    }

    func apply(to reminder: EKReminder) {
        if let title {
            reminder.title = title
        }

        if let notes {
            reminder.notes = notes.isEmpty ? nil : notes
        }

        if let priority {
            reminder.priority = Int(priority.value.rawValue)
        }

        if self.clearDueDate {
            reminder.dueDateComponents = nil
            removeAlarms(from: reminder)
        } else if let dueDate {
            reminder.dueDateComponents = dueDate
            removeAlarms(from: reminder)
            if let date = dueDate.date, dueDate.hour != nil {
                reminder.addAlarm(EKAlarm(absoluteDate: date))
            }
        }

        if self.clearRecurrence || self.recurrence != nil {
            for rule in reminder.recurrenceRules ?? [] {
                reminder.removeRecurrenceRule(rule)
            }
        }

        if let recurrence {
            reminder.addRecurrenceRule(recurrence.rule)
        }
    }
}

private func removeAlarms(from reminder: EKReminder) {
    for alarm in reminder.alarms ?? [] {
        reminder.removeAlarm(alarm)
    }
}
