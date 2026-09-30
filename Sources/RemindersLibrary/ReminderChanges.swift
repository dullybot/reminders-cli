import ArgumentParser
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
    /// An empty string clears the URL.
    var url: String?
    var alarms: [AlarmSpec] = []
    var clearAlarms = false

    var isEmpty: Bool {
        self.title == nil && self.notes == nil && self.dueDate == nil && !self.clearDueDate
            && self.priority == nil && self.recurrence == nil && !self.clearRecurrence
            && self.url == nil && self.alarms.isEmpty && !self.clearAlarms
    }

    func apply(to reminder: EKReminder) throws {
        if let title {
            reminder.title = title
        }

        if let notes {
            reminder.notes = notes.isEmpty ? nil : notes
        }

        if let url {
            reminder.url = URL(string: url)
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

        if self.clearAlarms {
            removeAlarms(from: reminder)
        }

        for alarm in self.alarms {
            guard let date = alarm.date(dueDate: reminder.dueDateComponents?.date) else {
                throw ValidationError("Alarms relative to the due date need a reminder with a due date")
            }

            reminder.addAlarm(EKAlarm(absoluteDate: date))
        }
    }
}

private func removeAlarms(from reminder: EKReminder) {
    for alarm in reminder.alarms ?? [] {
        reminder.removeAlarm(alarm)
    }
}
