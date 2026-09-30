import ArgumentParser
import EventKit
import Foundation

private extension EKReminder {
    var mappedPriority: EKReminderPriority {
        UInt(exactly: self.priority).flatMap(EKReminderPriority.init) ?? EKReminderPriority.none
    }
}

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

private func format(_ reminder: EKReminder, at index: Int?, listName: String? = nil,
    details: ReminderDetails? = nil, parentTitle: String? = nil) -> String
{
    let dateString = formattedDueDate(from: reminder).map { " (\($0))" } ?? ""
    let priorityString = Priority(reminder.mappedPriority).map { " (priority: \($0))" } ?? ""
    let alarmDates = (reminder.alarms ?? []).compactMap { $0.fireDate(for: reminder) }
    let alarmString = alarmDates.isEmpty ? "" : " (alarms: \(alarmDates.map { relativeDueDate($0) }.joined(separator: ", ")))"
    let repeatString = reminder.recurrenceRules?.first.map { " (repeats \(describe($0)))" } ?? ""
    let listString = listName.map { "\($0): " } ?? ""
    let notesString = reminder.notes.flatMap { $0.isEmpty ? nil : " (\($0))" } ?? ""
    let urlString = (reminder.url ?? details?.url).map { " <\($0.absoluteString)>" } ?? ""
    let indexString = index.map { "\($0): " } ?? ""
    let flaggedString = details?.flagged == true ? " (flagged)" : ""
    let tagsString = details?.tags.map { " #\($0)" }.joined() ?? ""
    let assigneeString = details?.assignee.map { " (assigned to \($0))" } ?? ""
    let parentString = parentTitle.map { " (subtask of '\($0)')" } ?? ""
    return "\(listString)\(indexString)\(reminder.title ?? "<unknown>")\(tagsString)\(notesString)\(urlString)\(dateString)\(repeatString)\(alarmString)\(priorityString)\(flaggedString)\(assigneeString)\(parentString)"
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
    private lazy var calendars = store.calendars(for: .reminder).filter { $0.allowsContentModifications }
    /// Optional: output simply omits Reminders.app-only fields without ReminderKit.
    private lazy var reminderKit = Result<ReminderExtras, Error> { try ReminderKitBridge() }
    private var extras: ReminderExtras? { try? self.reminderKit.get() }

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
        // Indexes printed here aren't usable with other commands, so the fetch
        // can be narrowed to the requested day in EventKit itself.
        let reminders = await self.reminders(
            on: self.calendars, displayOptions: displayOptions,
            dueOn: dueDate, includeOverdue: includeOverdue)
        let matchingReminders = reminders.enumerated().filter {
            isDue($0.element, on: dueDate, includeOverdue: includeOverdue)
        }

        let printer = ReminderPrinter(reminders: matchingReminders.map { $0.element }, extras: self.extras)
        switch outputFormat {
        case .json:
            print(encodeToJson(data: printer.json(matchingReminders.map { $0.element })))
        case .plain:
            for (i, reminder) in matchingReminders {
                print(printer.plain(reminder, at: i, listName: reminder.calendar.title))
            }
        }
    }

    func showListItems(withName name: String, dueOn dueDate: DateComponents?, includeOverdue: Bool,
        displayOptions: DisplayOptions, outputFormat: OutputFormat, sort: Sort, sortOrder: CustomSortOrder
    ) async {
        var reminders = await self.reminders(on: [self.calendar(withName: name)], displayOptions: displayOptions)
        if sort != .none {
            reminders.sort(by: sort.sortFunction(order: sortOrder))
        }

        let matchingReminders = reminders.enumerated()
            .filter { isDue($0.element, on: dueDate, includeOverdue: includeOverdue) }
            .map { (reminder: $0.element, index: sort == .none ? $0.offset : nil) }

        let printer = ReminderPrinter(reminders: reminders, extras: self.extras)
        switch outputFormat {
        case .json:
            print(encodeToJson(data: printer.json(matchingReminders.map { $0.reminder })))
        case .plain:
            for (reminder, i) in matchingReminders {
                print(printer.plain(reminder, at: i))
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
        itemAtIndex index: String, onListNamed name: String, changes: ReminderChanges,
        reminderKitChanges: ReminderKitChanges, parentIndex: String?
    ) async {
        let reminders = await self.reminders(on: [self.calendar(withName: name)], displayOptions: .incomplete)
        let reminder = self.reminder(from: reminders, at: index, onListNamed: name)
        var reminderKitChanges = reminderKitChanges
        reminderKitChanges.parent = parentIndex.map { self.reminder(from: reminders, at: $0, onListNamed: name) }

        do {
            let reminderKitChanges = try self.prepare(reminderKitChanges, on: reminder.calendar)
            try changes.apply(to: reminder)
            try self.store.save(reminder, commit: true)
            try self.apply(reminderKitChanges, to: reminder)
            print("Updated reminder '\(reminder.title ?? "")'")
        } catch let error {
            print("Failed to update reminder with error: \(error.localizedDescription)")
            exit(1)
        }
    }

    func setComplete(_ complete: Bool, itemAtIndex index: String, onListNamed name: String) async {
        let displayOptions = complete ? DisplayOptions.incomplete : .complete
        let action = complete ? "Completed" : "Uncompleted"
        let reminder = await self.reminder(at: index, onListNamed: name, displayOptions: displayOptions)

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
        // Numeric indexes resolve against the same display set `show` printed
        // them from, so callers pass the same completion flags. External
        // identifiers are stable regardless of completion state.
        let displayOptions = Int(index) == nil ? .all : displayOptions
        let reminder = await self.reminder(at: index, onListNamed: name, displayOptions: displayOptions)

        do {
            try self.store.remove(reminder, commit: true)
            print("Deleted '\(reminder.title ?? "")'")
        } catch let error {
            print("Failed to delete reminder with error: \(error)")
            exit(1)
        }
    }

    func addReminder(
        toListNamed name: String, changes: ReminderChanges, reminderKitChanges: ReminderKitChanges,
        parentIndex: String?, outputFormat: OutputFormat
    ) async {
        let calendar = self.calendar(withName: name)
        var reminderKitChanges = reminderKitChanges
        if let parentIndex {
            let reminders = await self.reminders(on: [calendar], displayOptions: .incomplete)
            reminderKitChanges.parent = self.reminder(from: reminders, at: parentIndex, onListNamed: name)
        }

        let reminder = EKReminder(eventStore: self.store)
        reminder.calendar = calendar

        do {
            let reminderKitChanges = try self.prepare(reminderKitChanges, on: calendar)
            try changes.apply(to: reminder)
            try self.store.save(reminder, commit: true)
            try self.apply(reminderKitChanges, to: reminder)
            switch (outputFormat) {
            case .json:
                print(encodeToJson(data: ReminderPrinter(reminders: [reminder], extras: self.extras).json([reminder])[0]))
            default:
                print("Added '\(reminder.title ?? "")' to '\(calendar.title)'")
            }
        } catch let error {
            print("Failed to save reminder with error: \(error.localizedDescription)")
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

    /// Checks Reminders.app-only changes before anything is saved, so an unsupported
    /// change fails without leaving a half-applied edit. A URL alone is also stored
    /// through EventKit, so its attachment is skipped when ReminderKit can't add it.
    private func prepare(_ changes: ReminderKitChanges, on calendar: EKCalendar) throws -> ReminderKitChanges {
        if !changes.needsReminderKit {
            return changes.isEmpty ? changes : (try? self.extras?.supported(changes, on: calendar)) ?? ReminderKitChanges()
        }

        return try self.reminderKit.get().supported(changes, on: calendar)
    }

    private func apply(_ changes: ReminderKitChanges, to reminder: EKReminder) throws {
        if !changes.isEmpty {
            try self.extras?.apply(changes, to: reminder)
        }
    }

    private func reminder(at index: String, onListNamed name: String, displayOptions: DisplayOptions) async
        -> EKReminder
    {
        let reminders = await self.reminders(on: [self.calendar(withName: name)], displayOptions: displayOptions)
        return self.reminder(from: reminders, at: index, onListNamed: name)
    }

    private func reminder(from reminders: [EKReminder], at index: String, onListNamed name: String) -> EKReminder {
        guard let reminder = self.getReminder(from: reminders, at: index) else {
            print("No reminder at index \(index) on \(name)")
            exit(1)
        }

        return reminder
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

/// EventKit hands fetched reminders back on its own queue; they are only ever used
/// by the single task awaiting them.
private struct UncheckedReminders: @unchecked Sendable {
    let value: [EKReminder]
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

private func isDue(_ reminder: EKReminder, on dueDate: DateComponents?, includeOverdue: Bool) -> Bool {
    guard let dueDate = dueDate?.date else {
        return true
    }

    guard let reminderDueDate = reminder.dueDateComponents?.date else {
        return false
    }

    let order = Calendar.current.compare(reminderDueDate, to: dueDate, toGranularity: .day)
    return order == .orderedSame || (includeOverdue && order == .orderedAscending)
}

/// Formats reminders together with their Reminders.app-only fields.
private struct ReminderPrinter {
    let details: [String: ReminderDetails]
    let reminders: [String: EKReminder]

    init(reminders: [EKReminder], extras: ReminderExtras?) {
        self.details = extras?.details(for: reminders) ?? [:]
        self.reminders = Dictionary(reminders.map { (reminderKitKey($0), $0) }, uniquingKeysWith: { first, _ in first })
    }

    func plain(_ reminder: EKReminder, at index: Int?, listName: String? = nil) -> String {
        let details = self.details[reminderKitKey(reminder)]
        let parentTitle = details?.parentIdentifier.map { self.reminders[$0]?.title ?? $0 }
        return format(reminder, at: index, listName: listName, details: details, parentTitle: parentTitle)
    }

    /// Parents are identified by `externalId`, like everywhere else in the output.
    func json(_ reminders: [EKReminder]) -> [ReminderJSON] {
        reminders.map { reminder in
            var details = self.details[reminderKitKey(reminder)]
            if let parent = details?.parentIdentifier {
                details?.parentIdentifier = self.reminders[parent]?.calendarItemExternalIdentifier ?? parent
            }
            return ReminderJSON(reminder: reminder, details: details)
        }
    }
}

private struct ReminderJSON: Encodable {
    private enum CodingKeys: String, CodingKey {
        case flagged, tags, parentId, assignee, url
    }

    let reminder: EKReminder
    let details: ReminderDetails?

    func encode(to encoder: Encoder) throws {
        try self.reminder.encode(to: encoder)
        guard let details else {
            return
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(details.flagged, forKey: .flagged)
        try container.encode(details.tags, forKey: .tags)
        try container.encodeIfPresent(details.parentIdentifier, forKey: .parentId)
        try container.encodeIfPresent(details.assignee, forKey: .assignee)
        if self.reminder.url == nil {
            try container.encodeIfPresent(details.url, forKey: .url)
        }
    }
}

private func encodeToJson(data: Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let encoded = try! encoder.encode(data)
    return String(data: encoded, encoding: .utf8) ?? ""
}
