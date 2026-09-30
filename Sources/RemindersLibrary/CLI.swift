import ArgumentParser
import Foundation

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

    func run() async throws {
        try await Reminders.authorized().addReminder(
            string: self.reminder.joined(separator: " "),
            notes: self.notes,
            toListNamed: self.listName,
            dueDateComponents: self.dueDate,
            priority: priority,
            outputFormat: format)
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

    @Argument(
        parsing: .remaining,
        help: "The new reminder contents")
    var reminder: [String] = []

    func validate() throws {
        if self.dueDate != nil && self.clearDueDate {
            throw ValidationError("Cannot specify both --due-date and --clear-due-date")
        }

        if self.notes != nil && self.clearNotes {
            throw ValidationError("Cannot specify both --notes and --clear-notes")
        }

        if self.reminder.isEmpty && self.notes == nil && !self.clearNotes && self.dueDate == nil
            && !self.clearDueDate
        {
            throw ValidationError(
                "Must specify either new reminder content, new notes, or a due date change")
        }
    }

    func run() async throws {
        let newText = self.reminder.joined(separator: " ")
        try await Reminders.authorized().edit(
            itemAtIndex: self.index,
            onListNamed: self.listName,
            newText: newText.isEmpty ? nil : newText,
            newNotes: self.clearNotes ? "" : self.notes,
            newDueDateComponents: self.dueDate,
            clearDueDate: self.clearDueDate
        )
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
