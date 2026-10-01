import ArgumentParser
import EventKit
import Foundation

private func formattedDueDate(from reminder: EKReminder) -> String? {
    guard let components = reminder.dueDateComponents, let date = components.date else {
        return nil
    }

    return relativeDueDate(date, allDay: components.hour == nil)
}

/// Describes a due date relative to now, counting calendar days rather than
/// elapsed 24 hour periods once it isn't today.
func relativeDueDate(_ date: Date, allDay: Bool = false, relativeTo now: Date = Date(),
    calendar: Calendar = .current, locale: Locale = .current) -> String
{
    let formatter = RelativeDateTimeFormatter()
    formatter.calendar = calendar
    formatter.locale = locale
    let days = calendar.dateComponents(
        [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    if days == 0 {
        if allDay {
            formatter.dateTimeStyle = .named
            return formatter.localizedString(from: DateComponents(day: 0))
        }

        return formatter.localizedString(for: date, relativeTo: now)
    }

    return formatter.localizedString(from: DateComponents(day: days))
}

private extension EKReminder {
    var mappedPriority: EKReminderPriority {
        UInt(exactly: self.priority).flatMap(EKReminderPriority.init) ?? EKReminderPriority.none
    }
}

private func format(_ reminder: EKReminder, at index: Int?, listName: String? = nil) -> String {
    let dateString = formattedDueDate(from: reminder).map { " (\($0))" } ?? ""
    let priorityString = Priority(reminder.mappedPriority).map { " (priority: \($0))" } ?? ""
    let repeatString = reminder.recurrenceRules?.first.map { " (repeats \(describe($0)))" } ?? ""
    let alarmDates = (reminder.alarms ?? []).compactMap { $0.fireDate(for: reminder) }
    let alarmString = alarmDates.isEmpty ? "" : " (alarms: \(alarmDates.map { relativeDueDate($0) }.joined(separator: ", ")))"
    let listString = listName.map { "\($0): " } ?? ""
    let notesString = reminder.notes.flatMap { $0.isEmpty ? nil : " (\($0))" } ?? ""
    let urlString = reminder.url.map { " <\($0.absoluteString)>" } ?? ""
    let indexString = index.map { "\($0): " } ?? ""
    return "\(listString)\(indexString)\(reminder.title ?? "<unknown>")\(notesString)\(urlString)\(dateString)\(repeatString)\(alarmString)\(priorityString)"
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
    private lazy var calendars = self.store.calendars(for: .reminder).filter { $0.allowsContentModifications }

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
        return self.calendars.map { $0.title }
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

        // Indexes printed here aren't usable with other commands, so the fetch
        // can be narrowed to the requested day in EventKit itself.
        let reminders = await self.reminders(
            on: self.calendars, displayOptions: displayOptions, dueOn: dueDate, includeOverdue: includeOverdue)
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
        // Accounts such as iCloud can expose several sources with the same title,
        // only one of which holds reminders, so prefer sources that already do.
        let sources = self.store.sources
        let reminderSources = sources.filter { !$0.calendars(for: .reminder).isEmpty }
        let candidates = reminderSources.isEmpty ? sources : reminderSources
        let source: EKSource
        if let requestedSourceName {
            let matches = { (source: EKSource) in
                source.title == requestedSourceName || source.sourceIdentifier == requestedSourceName
            }
            guard let requestedSource = candidates.first(where: matches) ?? sources.first(where: matches) else {
                print("No source named '\(requestedSourceName)'")
                exit(1)
            }

            source = requestedSource
        } else if candidates.count == 1, let onlySource = candidates.first {
            source = onlySource
        } else if candidates.isEmpty {
            print("No existing list sources were found, please create a list in Reminders.app")
            exit(1)
        } else {
            print("Multiple sources were found, please specify one with --source:")
            for source in candidates {
                print("  \(source.title) (\(source.sourceIdentifier))")
            }

            exit(1)
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
        clearDueDate: Bool = false,
        newPriority: Priority? = nil,
        newURL: String? = nil,
        newRecurrence: Recurrence? = nil,
        clearRecurrence: Bool = false,
        newAlarms: [AlarmSpec] = [],
        clearAlarms: Bool = false
    ) async {
        let calendar = self.calendar(withName: name)

        let reminders = await self.reminders(on: [calendar], displayOptions: .incomplete)
        guard let reminder = self.getReminder(from: reminders, at: index) else {
            print("No reminder at index \(index) on \(name)")
            exit(1)
        }

        do {
            reminder.title = newText ?? reminder.title
            if let newNotes {
                reminder.notes = newNotes.isEmpty ? nil : newNotes
            }
            if let newPriority {
                reminder.priority = Int(newPriority.value.rawValue)
            }
            if let newURL {
                reminder.url = URL(string: newURL)
            }

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

            if clearRecurrence || newRecurrence != nil {
                for rule in reminder.recurrenceRules ?? [] {
                    reminder.removeRecurrenceRule(rule)
                }
            }

            if let newRecurrence {
                reminder.addRecurrenceRule(newRecurrence.rule)
            }

            if clearAlarms {
                for alarm in reminder.alarms ?? [] {
                    reminder.removeAlarm(alarm)
                }
            }

            if newAlarms.contains(where: \.needsDueDate) && reminder.dueDateComponents?.date == nil {
                print("Alarms relative to the due date need a reminder with a due date")
                exit(1)
            }

            addAlarms(newAlarms, to: reminder)

            try self.store.save(reminder, commit: true)
            print("Updated reminder '\(reminder.title ?? "")'")
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
        guard let reminder = self.getReminder(from: reminders, at: index) else {
            print("No reminder at index \(index) on \(name)")
            exit(1)
        }

        do {
            reminder.isCompleted = complete
            try self.store.save(reminder, commit: true)
            print("\(action) '\(reminder.title ?? "")'")
        } catch let error {
            print("Failed to save reminder with error: \(error)")
            exit(1)
        }
    }

    func delete(itemAtIndex index: String, onListNamed name: String, displayOptions: DisplayOptions) async {
        let calendar = self.calendar(withName: name)

        // Numeric indexes resolve against the same display set `show` printed
        // them from, so callers pass the same completion flags. External
        // identifiers are stable regardless of completion state.
        let displayOptions = Int(index) == nil ? .all : displayOptions

        let reminders = await self.reminders(on: [calendar], displayOptions: displayOptions)
        guard let reminder = self.getReminder(from: reminders, at: index) else {
            print("No reminder at index \(index) on \(name)")
            exit(1)
        }

        do {
            try self.store.remove(reminder, commit: true)
            print("Deleted '\(reminder.title ?? "")'")
        } catch let error {
            print("Failed to delete reminder with error: \(error)")
            exit(1)
        }
    }

    func addReminder(
        string: String,
        notes: String?,
        url: String?,
        toListNamed name: String,
        dueDateComponents: DateComponents?,
        priority: Priority,
        recurrence: Recurrence?,
        alarms: [AlarmSpec],
        outputFormat: OutputFormat)
    {
        let calendar = self.calendar(withName: name)
        let reminder = EKReminder(eventStore: self.store)
        reminder.calendar = calendar
        reminder.title = string
        reminder.notes = notes?.isEmpty == true ? nil : notes
        reminder.url = url.flatMap(URL.init(string:))
        reminder.dueDateComponents = dueDateComponents
        reminder.priority = Int(priority.value.rawValue)
        if let dueDate = dueDateComponents?.date, dueDateComponents?.hour != nil {
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        }

        if let recurrence {
            reminder.addRecurrenceRule(recurrence.rule)
        }

        do {
            addAlarms(alarms, to: reminder)
            try self.store.save(reminder, commit: true)
            switch (outputFormat) {
            case .json:
                print(encodeToJson(data: reminder))
            default:
                print("Added '\(reminder.title ?? "")' to '\(calendar.title)'")
            }
        } catch let error {
            print("Failed to save reminder with error: \(error)")
            exit(1)
        }
    }

    // MARK: - Private functions

    /// Fetches with EventKit's completion-state (and optionally due-date) predicates
    /// instead of loading every reminder and filtering in memory.
    private func reminders(
        on calendars: [EKCalendar],
        displayOptions: DisplayOptions,
        dueOn dueDate: DateComponents? = nil,
        includeOverdue: Bool = false
    ) async -> [EKReminder] {
        let predicate: NSPredicate
        switch displayOptions {
        case .all:
            predicate = self.store.predicateForReminders(in: calendars)
        case .complete:
            predicate = self.store.predicateForCompletedReminders(
                withCompletionDateStarting: nil, ending: nil, calendars: calendars)
        case .incomplete:
            let range = dueDate?.date.map { dueDayRange(for: $0, includeOverdue: includeOverdue) }
            predicate = self.store.predicateForIncompleteReminders(
                withDueDateStarting: range?.start, ending: range?.end, calendars: calendars)
        }

        let fetched = await withCheckedContinuation { continuation in
            self.store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: UncheckedReminders(value: reminders ?? []))
            }
        }

        return fetched.value
    }

    private func calendar(withName name: String) -> EKCalendar {
        if let calendar = self.calendars.find(where: { $0.title.lowercased() == name.lowercased() }) {
            return calendar
        } else {
            print("No reminders list matching \(name)")
            exit(1)
        }
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

/// The day containing `date`, or everything up to the end of that day when overdue
/// items are included.
func dueDayRange(for date: Date, includeOverdue: Bool, calendar: Calendar = .current)
    -> (start: Date?, end: Date?)
{
    // EventKit's start bound is exclusive, which would drop all-day reminders due at midnight.
    let start = calendar.startOfDay(for: date)
    return (includeOverdue ? nil : start.addingTimeInterval(-1), calendar.date(byAdding: .day, value: 1, to: start))
}

/// EventKit hands fetched reminders back on its own queue; they are only ever used
/// by the single task awaiting them.
private struct UncheckedReminders: @unchecked Sendable {
    let value: [EKReminder]
}

private func addAlarms(_ alarms: [AlarmSpec], to reminder: EKReminder) {
    for date in alarms.compactMap({ $0.date(dueDate: reminder.dueDateComponents?.date) }) {
        reminder.addAlarm(EKAlarm(absoluteDate: date))
    }
}

private func encodeToJson(data: Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let encoded = try! encoder.encode(data)
    return String(data: encoded, encoding: .utf8) ?? ""
}
