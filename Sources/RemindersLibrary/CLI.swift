import ArgumentParser
import Foundation

private func validateURL(_ url: String?) throws {
    if let url, !url.isEmpty, URL(string: url)?.scheme == nil {
        throw ValidationError("--url must be an absolute URL such as https://example.com")
    }
}

private func normalizedTags(_ tags: [String]) -> [String] {
    tags.map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }.filter { !$0.isEmpty }
}

struct CompletionOptions: ParsableArguments {
    @Flag(help: "Show completed items only")
    var onlyCompleted = false

    @Flag(help: "Include completed items in output")
    var includeCompleted = false

    var displayOptions: DisplayOptions {
        if self.onlyCompleted {
            return .complete
        } else if self.includeCompleted {
            return .all
        }

        return .incomplete
    }

    func validate() throws {
        if self.onlyCompleted && self.includeCompleted {
            throw ValidationError(
                "Cannot specify both --include-completed and --only-completed")
        }
    }
}

struct ShowLists: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print the name of lists to pass to other commands")
    @Option(
        name: .shortAndLong,
        help: "format, either of 'plain' or 'json'")
    var format: OutputFormat = .plain

    func run() async throws {
        try await Reminders.authorized().showLists(outputFormat: format)
    }
}

struct ShowAll: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print all reminders")

    @OptionGroup
    var completion: CompletionOptions

    @Flag(help: "When using --due-date, also include items due before the due date")
    var includeOverdue = false

    @Option(
        name: .shortAndLong,
        help: "Show only reminders due on this date")
    var dueDate: DateComponents?

    @Option(
        name: .shortAndLong,
        help: "format, either of 'plain' or 'json'")
    var format: OutputFormat = .plain

    func run() async throws {
        try await Reminders.authorized().showAllReminders(
            dueOn: self.dueDate, includeOverdue: self.includeOverdue,
            displayOptions: completion.displayOptions, outputFormat: format)
    }
}

struct Show: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print the items on the given list")

    @Argument(
        help: "The list to print items from, see 'show-lists' for names",
        completion: .custom(listNameCompletion))
    var listName: String

    @OptionGroup
    var completion: CompletionOptions

    @Flag(help: "When using --due-date, also include items due before the due date")
    var includeOverdue = false

    @Option(
        name: .shortAndLong,
        help: "Show the reminders in a specific order, one of: \(Sort.commaSeparatedCases)")
    var sort: Sort = .none

    @Option(
        name: [.customShort("o"), .long],
        help: "How the sort order should be applied, one of: \(CustomSortOrder.commaSeparatedCases)")
    var sortOrder: CustomSortOrder = .ascending

    @Option(
        name: .shortAndLong,
        help: "Show only reminders due on this date")
    var dueDate: DateComponents?

    @Option(
        name: .shortAndLong,
        help: "format, either of 'plain' or 'json'")
    var format: OutputFormat = .plain

    func run() async throws {
        try await Reminders.authorized().showListItems(
            withName: self.listName, dueOn: self.dueDate, includeOverdue: self.includeOverdue,
            displayOptions: completion.displayOptions, outputFormat: format, sort: sort, sortOrder: sortOrder)
    }
}

struct Add: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add a reminder to a list")

    @Argument(
        help: "The list to add to, see 'show-lists' for names",
        completion: .custom(listNameCompletion))
    var listName: String

    @Argument(
        parsing: .remaining,
        help: "The reminder contents")
    var reminder: [String]

    @Option(
        name: .shortAndLong,
        help: "The date the reminder is due")
    var dueDate: DateComponents?

    @Option(
        name: .shortAndLong,
        help: "The priority of the reminder")
    var priority: Priority = .none

    @Option(
        name: .shortAndLong,
        help: "format, either of 'plain' or 'json'")
    var format: OutputFormat = .plain

    @Option(
        name: .shortAndLong,
        help: "The notes to add to the reminder")
    var notes: String?

    @Option(
        parsing: .unconditionalSingleValue,
        help: ArgumentHelp(
            "Add an alarm at a date, or relative to the due date like -15m, -1h, -2d (repeatable)",
            valueName: "date-or-offset"))
    var alarm: [AlarmSpec] = []

    @Option(help: "A URL to attach to the reminder")
    var url: String?

    @Flag(help: "Flag the reminder")
    var flag = false

    @Option(name: .shortAndLong, help: "Add a tag, without the leading # (repeatable)")
    var tag: [String] = []

    @Option(help: "Make this a subtask of the reminder at this index or id on the same list")
    var parent: String?

    @Option(help: "Assign to someone the list is shared with, by name or email")
    var assign: String?

    @OptionGroup
    var repeatOptions: RepeatOptions

    func validate() throws {
        try validateURL(self.url)

        if self.repeatOptions.frequency != nil && self.dueDate == nil {
            throw ValidationError("--repeat requires --due-date")
        }

        if self.alarm.contains(where: \.needsDueDate) && self.dueDate == nil {
            throw ValidationError("Relative --alarm offsets require --due-date")
        }
    }

    func run() async throws {
        let changes = ReminderChanges(
            title: self.reminder.joined(separator: " "),
            notes: self.notes,
            dueDate: self.dueDate,
            priority: self.priority,
            recurrence: self.repeatOptions.recurrence,
            url: self.url,
            alarms: self.alarm)
        let reminderKitChanges = ReminderKitChanges(
            flagged: self.flag ? true : nil,
            addTags: normalizedTags(self.tag),
            assignee: self.assign,
            url: self.url)
        try await Reminders.authorized().addReminder(
            toListNamed: self.listName, changes: changes, reminderKitChanges: reminderKitChanges,
            parentIndex: self.parent, outputFormat: format)
    }
}

struct Complete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Complete a reminder")

    @Argument(
        help: "The list to complete a reminder on, see 'show-lists' for names",
        completion: .custom(listNameCompletion))
    var listName: String

    @Argument(
        help: "The index or id of the reminder to delete, see 'show' for indexes")
    var index: String

    func run() async throws {
        try await Reminders.authorized().setComplete(true, itemAtIndex: self.index, onListNamed: self.listName)
    }
}

struct Uncomplete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Uncomplete a reminder")

    @Argument(
        help: "The list to uncomplete a reminder on, see 'show-lists' for names",
        completion: .custom(listNameCompletion))
    var listName: String

    @Argument(
        help: "The index or id of the reminder to delete, see 'show' for indexes")
    var index: String

    func run() async throws {
        try await Reminders.authorized().setComplete(false, itemAtIndex: self.index, onListNamed: self.listName)
    }
}

struct Delete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Delete a reminder")

    @Argument(
        help: "The list to delete a reminder on, see 'show-lists' for names",
        completion: .custom(listNameCompletion))
    var listName: String

    @Argument(
        help: "The index or id of the reminder to delete, see 'show' for indexes")
    var index: String

    @OptionGroup(title: "Index scope (match the flags passed to 'show')")
    var completion: CompletionOptions

    func run() async throws {
        try await Reminders.authorized().delete(
            itemAtIndex: self.index, onListNamed: self.listName, displayOptions: completion.displayOptions)
    }
}

@Sendable func listNameCompletion(_ arguments: [String], _ index: Int, _ prefix: String) -> [String] {
    // NOTE: A list name with ':' was separated in zsh completion, there might be more of these or
    // this might break other shells
    return Reminders.listNamesIfAuthorized().map { $0.replacingOccurrences(of: ":", with: "\\:") }
}

struct Edit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Edit the text of a reminder")

    @Argument(
        help: "The list to edit a reminder on, see 'show-lists' for names",
        completion: .custom(listNameCompletion))
    var listName: String

    @Argument(
        help: "The index or id of the reminder to delete, see 'show' for indexes")
    var index: String

    @Option(
        name: .shortAndLong,
        help: "The notes to set on the reminder, overwriting previous notes")
    var notes: String?

    @Option(
        name: .shortAndLong,
        help: "The new date the reminder is due")
    var dueDate: DateComponents?

    @Flag(help: "Remove the due date from the reminder")
    var clearDueDate = false

    @Flag(help: "Remove the notes from the reminder")
    var clearNotes = false

    @Option(
        name: .shortAndLong,
        help: "The new priority of the reminder")
    var priority: Priority?

    @Option(help: "The URL to set on the reminder, pass \"\" to remove it")
    var url: String?

    @OptionGroup
    var repeatOptions: RepeatOptions

    @Flag(help: "Stop the reminder repeating")
    var clearRepeat = false

    @Option(
        parsing: .unconditionalSingleValue,
        help: ArgumentHelp(
            "Add an alarm at a date, or relative to the due date like -15m, -1h, -2d (repeatable)",
            valueName: "date-or-offset"))
    var alarm: [AlarmSpec] = []

    @Flag(help: "Remove all alarms, applied before any --alarm")
    var clearAlarms = false

    @Flag(help: "Flag the reminder")
    var flag = false

    @Flag(help: "Unflag the reminder")
    var unflag = false

    @Option(name: .shortAndLong, help: "Add a tag, without the leading # (repeatable)")
    var tag: [String] = []

    @Option(help: "Remove a tag (repeatable)")
    var removeTag: [String] = []

    @Flag(help: "Remove all tags, applied before any --tag")
    var clearTags = false

    @Option(help: "Make this a subtask of the reminder at this index or id on the same list")
    var parent: String?

    @Flag(help: "Make this subtask a top level reminder")
    var unnest = false

    @Option(help: "Assign to someone the list is shared with, by name or email")
    var assign: String?

    @Flag(help: "Remove the assignee")
    var unassign = false

    @Argument(
        parsing: .remaining,
        help: "The new reminder contents")
    var reminder: [String] = []

    func validate() throws {
        try validateURL(self.url)

        if self.dueDate != nil && self.clearDueDate {
            throw ValidationError("Cannot specify both --due-date and --clear-due-date")
        }

        if self.notes != nil && self.clearNotes {
            throw ValidationError("Cannot specify both --notes and --clear-notes")
        }

        if self.repeatOptions.frequency != nil && self.clearRepeat {
            throw ValidationError("Cannot specify both --repeat and --clear-repeat")
        }

        for (first, second, names) in [
            (self.flag, self.unflag, "--flag and --unflag"),
            (self.parent != nil, self.unnest, "--parent and --unnest"),
            (self.assign != nil, self.unassign, "--assign and --unassign"),
        ] where first && second {
            throw ValidationError("Cannot specify both \(names)")
        }

        if self.changes.isEmpty && self.reminderKitChanges.isEmpty && self.parent == nil {
            throw ValidationError("Must specify either new reminder content or a field to change")
        }
    }

    var reminderKitChanges: ReminderKitChanges {
        ReminderKitChanges(
            flagged: self.flag ? true : self.unflag ? false : nil,
            addTags: normalizedTags(self.tag),
            removeTags: normalizedTags(self.removeTag),
            clearTags: self.clearTags,
            unnest: self.unnest,
            assignee: self.assign,
            unassign: self.unassign,
            url: self.url)
    }

    var changes: ReminderChanges {
        let newText = self.reminder.joined(separator: " ")
        return ReminderChanges(
            title: newText.isEmpty ? nil : newText,
            notes: self.clearNotes ? "" : self.notes,
            dueDate: self.dueDate,
            clearDueDate: self.clearDueDate,
            priority: self.priority,
            recurrence: self.repeatOptions.recurrence,
            clearRecurrence: self.clearRepeat,
            url: self.url,
            alarms: self.alarm,
            clearAlarms: self.clearAlarms)
    }

    func run() async throws {
        try await Reminders.authorized().edit(
            itemAtIndex: self.index, onListNamed: self.listName, changes: self.changes,
            reminderKitChanges: self.reminderKitChanges, parentIndex: self.parent)
    }
}


struct NewList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a new list")

    @Argument(
        help: "The name of the new list")
    var listName: String

    @Option(
        name: .shortAndLong,
        help: "The name of the source of the list, if all your lists use the same source it will default to that")
    var source: String?

    func run() async throws {
        try await Reminders.authorized().newList(with: self.listName, source: self.source)
    }
}

public struct CLI: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "reminders",
        abstract: "Interact with macOS Reminders from the command line",
        version: "2.6.0",
        subcommands: [
            Add.self,
            Complete.self,
            Uncomplete.self,
            Delete.self,
            Edit.self,
            Show.self,
            ShowLists.self,
            NewList.self,
            ShowAll.self,
        ]
    )

    public init() {}
}
