import ArgumentParser
import EventKit
import Foundation

private func formattedDueDate(from reminder: EKReminder) -> String? {
    return reminder.dueDateComponents?.date.map {
        RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date())
    }
}

private extension EKReminder {
    var mappedPriority: EKReminderPriority {
        UInt(exactly: self.priority).flatMap(EKReminderPriority.init) ?? EKReminderPriority.none
    }
}

private func format(_ reminder: EKReminder, at index: Int?, listName: String? = nil) -> String {
    let dateString = formattedDueDate(from: reminder).map { " (\($0))" } ?? ""
    let priorityString = Priority(reminder.mappedPriority).map { " (priority: \($0))" } ?? ""
    let listString = listName.map { "\($0): " } ?? ""
    let notesString = reminder.notes.map { " (\($0))" } ?? ""
    let indexString = index.map { "\($0): " } ?? ""
    return "\(listString)\(indexString)\(reminder.title ?? "<unknown>")\(notesString)\(dateString)\(priorityString)"
}

public enum OutputFormat: String, ExpressibleByArgument {
    case json, plain
}

public enum DisplayOptions: String, Decodable {
    case all
    case incomplete
    case complete
}

public enum Priority: String, ExpressibleByArgument {
    case none
    case low
    case medium
    case high

    var value: EKReminderPriority {
        switch self {
            case .none: return .none
            case .low: return .low
            case .medium: return .medium
            case .high: return .high
        }
    }

    init?(_ priority: EKReminderPriority) {
        switch priority {
            case .none: return nil
            case .low: self = .low
            case .medium: self = .medium
            case .high: self = .high
        @unknown default:
            return nil
        }
    }
}

public struct AccessError: LocalizedError {
    let underlying: Error?

    public var errorDescription: String? {
        let reason = underlying.map { "\n\($0.localizedDescription)" } ?? ""
        return "you need to grant reminders access\(reason)"
    }
}

public final class Reminders {
    private let store = EKEventStore()

    private init() {}

    /// Requests full Reminders access, only when a command actually needs it.
    static func authorized() async throws -> Reminders {
        let reminders = Reminders()
        let granted: Bool
        do {
            granted = try await reminders.store.requestFullAccessToReminders()
        } catch {
            throw AccessError(underlying: error)
        }

        guard granted else {
            throw AccessError(underlying: nil)
        }

        return reminders
    }

    /// List names for shell completion; never prompts for access.
    static func listNamesIfAuthorized() -> [String] {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            return []
        }

        return Reminders().getListNames()
    }

    func getListNames() -> [String] {
        return self.getCalendars().map { $0.title }
    }

    func showLists(outputFormat: OutputFormat) {
        switch (outputFormat) {
        case .json:
            print(encodeToJson(data: self.getListNames()))
        default:
            for name in self.getListNames() {
                print(name)
            }
        }
    }

    func showAllReminders(dueOn dueDate: DateComponents?, includeOverdue: Bool,
        displayOptions: DisplayOptions, outputFormat: OutputFormat
    ) async {
        let calendar = Calendar.current

        let reminders = await self.reminders(on: self.getCalendars(), displayOptions: displayOptions)
        var matchingReminders = [(EKReminder, Int, String)]()
        for (i, reminder) in reminders.enumerated() {
            let listName = reminder.calendar.title
            guard let dueDate = dueDate?.date else {
                matchingReminders.append((reminder, i, listName))
                continue
            }

            guard let reminderDueDate = reminder.dueDateComponents?.date else {
                continue
            }

            let sameDay = calendar.compare(
                reminderDueDate, to: dueDate, toGranularity: .day) == .orderedSame
            let earlierDay = calendar.compare(
                reminderDueDate, to: dueDate, toGranularity: .day) == .orderedAscending

            if sameDay || (includeOverdue && earlierDay) {
                matchingReminders.append((reminder, i, listName))
            }
        }

        switch outputFormat {
        case .json:
            print(encodeToJson(data: matchingReminders.map { $0.0 }))
        case .plain:
            for (reminder, i, listName) in matchingReminders {
                print(format(reminder, at: i, listName: listName))
            }
        }
    }

    func showListItems(withName name: String, dueOn dueDate: DateComponents?, includeOverdue: Bool,
        displayOptions: DisplayOptions, outputFormat: OutputFormat, sort: Sort, sortOrder: CustomSortOrder
    ) async {
        let calendar = Calendar.current

        var reminders = await self.reminders(on: [self.calendar(withName: name)], displayOptions: displayOptions)
        var matchingReminders = [(EKReminder, Int?)]()
        if sort != .none {
            reminders.sort(by: sort.sortFunction(order: sortOrder))
        }

        for (i, reminder) in reminders.enumerated() {
            let index = sort == .none ? i : nil
            guard let dueDate = dueDate?.date else {
                matchingReminders.append((reminder, index))
                continue
            }

            guard let reminderDueDate = reminder.dueDateComponents?.date else {
                continue
            }

            let sameDay = calendar.compare(
                reminderDueDate, to: dueDate, toGranularity: .day) == .orderedSame
            let earlierDay = calendar.compare(
                reminderDueDate, to: dueDate, toGranularity: .day) == .orderedAscending

            if sameDay || (includeOverdue && earlierDay) {
                matchingReminders.append((reminder, index))
            }
        }

        switch outputFormat {
        case .json:
            print(encodeToJson(data: matchingReminders.map { $0.0 }))
        case .plain:
            for (reminder, i) in matchingReminders {
                print(format(reminder, at: i))
            }
        }
    }

    func newList(with name: String, source requestedSourceName: String?) {
        let sources = self.store.sources
        guard var source = sources.first else {
            print("No existing list sources were found, please create a list in Reminders.app")
            exit(1)
        }

        if let requestedSourceName = requestedSourceName {
            guard let requestedSource = sources.first(where: { $0.title == requestedSourceName }) else
            {
                print("No source named '\(requestedSourceName)'")
                exit(1)
            }

            source = requestedSource
        } else {
            let uniqueSources = Set(sources.map { $0.title })
            if uniqueSources.count > 1 {
                print("Multiple sources were found, please specify one with --source:")
                for source in uniqueSources {
                    print("  \(source)")
                }

                exit(1)
            }
        }

        let newList = EKCalendar(for: .reminder, eventStore: self.store)
        newList.title = name
        newList.source = source

        do {
            try self.store.saveCalendar(newList, commit: true)
            print("Created new list '\(newList.title)'!")
        } catch let error {
            print("Failed create new list with error: \(error)")
            exit(1)
        }
    }

    func edit(
        itemAtIndex index: String,
        onListNamed name: String,
        newText: String?,
        newNotes: String?,
        newDueDateComponents: DateComponents? = nil,
        clearDueDate: Bool = false
    ) async {
        let calendar = self.calendar(withName: name)

        let reminders = await self.reminders(on: [calendar], displayOptions: .incomplete)
        guard let reminder = self.getReminder(from: reminders, at: index) else {
            print("No reminder at index \(index) on \(name)")
            exit(1)
        }

        do {
            reminder.title = newText ?? reminder.title
            reminder.notes = newNotes ?? reminder.notes

            if clearDueDate {
                reminder.dueDateComponents = nil
                for alarm in reminder.alarms ?? [] {
                    reminder.removeAlarm(alarm)
                }
            } else if let newDueDateComponents {
                reminder.dueDateComponents = newDueDateComponents
                for alarm in reminder.alarms ?? [] {
                    reminder.removeAlarm(alarm)
                }

                if let dueDate = newDueDateComponents.date, newDueDateComponents.hour != nil {
                    reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
                }
            }

            try self.store.save(reminder, commit: true)
            print("Updated reminder '\(reminder.title!)'")
        } catch let error {
            print("Failed to update reminder with error: \(error)")
            exit(1)
        }
    }

    func setComplete(_ complete: Bool, itemAtIndex index: String, onListNamed name: String) async {
        let calendar = self.calendar(withName: name)
        let displayOptions = complete ? DisplayOptions.incomplete : .complete
        let action = complete ? "Completed" : "Uncompleted"

        let reminders = await self.reminders(on: [calendar], displayOptions: displayOptions)
        print(reminders.map { $0.title! })
        guard let reminder = self.getReminder(from: reminders, at: index) else {
            print("No reminder at index \(index) on \(name)")
            exit(1)
        }

        do {
            reminder.isCompleted = complete
            try self.store.save(reminder, commit: true)
            print("\(action) '\(reminder.title!)'")
        } catch let error {
            print("Failed to save reminder with error: \(error)")
            exit(1)
        }
    }

    func delete(itemAtIndex index: String, onListNamed name: String) async {
        let calendar = self.calendar(withName: name)

        // Numeric indexes are only meaningful against the same display set that
        // `show` uses by default (incomplete-only), so keep that scope when the
        // caller passes a plain integer index — otherwise a numeric index would
        // resolve against a differently-ordered/sized array than the one the
        // user actually saw. External identifiers are stable regardless of
        // completion state, so widen the fetch to `.all` in that case, so a
        // reminder already marked complete can still be found and deleted by
        // its id instead of failing with "No reminder at index ...".
        let displayOptions: DisplayOptions = Int(index) == nil ? .all : .incomplete

        let reminders = await self.reminders(on: [calendar], displayOptions: displayOptions)
        guard let reminder = self.getReminder(from: reminders, at: index) else {
            print("No reminder at index \(index) on \(name)")
            exit(1)
        }

        do {
            try self.store.remove(reminder, commit: true)
            print("Deleted '\(reminder.title!)'")
        } catch let error {
            print("Failed to delete reminder with error: \(error)")
            exit(1)
        }
    }

    func addReminder(
        string: String,
        notes: String?,
        toListNamed name: String,
        dueDateComponents: DateComponents?,
        priority: Priority,
        outputFormat: OutputFormat)
    {
        let calendar = self.calendar(withName: name)
        let reminder = EKReminder(eventStore: self.store)
        reminder.calendar = calendar
        reminder.title = string
        reminder.notes = notes
        reminder.dueDateComponents = dueDateComponents
        reminder.priority = Int(priority.value.rawValue)
        if let dueDate = dueDateComponents?.date, dueDateComponents?.hour != nil {
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        }

        do {
            try self.store.save(reminder, commit: true)
            switch (outputFormat) {
            case .json:
                print(encodeToJson(data: reminder))
            default:
                print("Added '\(reminder.title!)' to '\(calendar.title)'")
            }
        } catch let error {
            print("Failed to save reminder with error: \(error)")
            exit(1)
        }
    }

    // MARK: - Private functions

    private func reminders(on calendars: [EKCalendar], displayOptions: DisplayOptions) async -> [EKReminder] {
        let predicate = self.store.predicateForReminders(in: calendars)
        let fetched = await withCheckedContinuation { continuation in
            self.store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: UncheckedReminders(value: reminders ?? []))
            }
        }

        return fetched.value.filter { self.shouldDisplay(reminder: $0, displayOptions: displayOptions) }
    }

    private func shouldDisplay(reminder: EKReminder, displayOptions: DisplayOptions) -> Bool {
        switch displayOptions {
        case .all:
            return true
        case .incomplete:
            return !reminder.isCompleted
        case .complete:
            return reminder.isCompleted
        }
    }

    private func calendar(withName name: String) -> EKCalendar {
        if let calendar = self.getCalendars().find(where: { $0.title.lowercased() == name.lowercased() }) {
            return calendar
        } else {
            print("No reminders list matching \(name)")
            exit(1)
        }
    }

    private func getCalendars() -> [EKCalendar] {
        return self.store.calendars(for: .reminder)
                    .filter { $0.allowsContentModifications }
    }

    private func getReminder(from reminders: [EKReminder], at index: String) -> EKReminder? {
        precondition(!index.isEmpty, "Index cannot be empty, argument parser must be misconfigured")
        if let index = Int(index) {
            return reminders[safe: index]
        } else {
            return reminders.first { $0.calendarItemExternalIdentifier == index }
        }
    }

}

/// EventKit hands fetched reminders back on its own queue; they are only ever used
/// by the single task awaiting them.
private struct UncheckedReminders: @unchecked Sendable {
    let value: [EKReminder]
}

private func encodeToJson(data: Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let encoded = try! encoder.encode(data)
    return String(data: encoded, encoding: .utf8) ?? ""
}
