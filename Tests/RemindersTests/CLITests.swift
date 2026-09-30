import ArgumentParser
@testable import RemindersLibrary
import Testing

struct CLITests {
    // keith/reminders-cli#85: ArgumentParser rejects `--notes=""`, so offer a flag.
    @Test func clearNotes() throws {
        #expect(try Edit.parse(["Soon", "0", "--notes", ""]).notes == "")
        #expect(try Edit.parse(["Soon", "0", "--clear-notes"]).clearNotes)
        #expect(try Add.parse(["Soon", "Title", "--notes", ""]).notes == "")
        #expect(throws: (any Error).self) {
            try Edit.parse(["Soon", "0", "--clear-notes", "--notes", "x"])
        }
    }

    @Test func deleteAcceptsCompletionScope() throws {
        #expect(try Delete.parse(["Soon", "0"]).completion.displayOptions == .incomplete)
        #expect(try Delete.parse(["Soon", "0", "--only-completed"]).completion.displayOptions == .complete)
        #expect(try Delete.parse(["Soon", "0", "--include-completed"]).completion.displayOptions == .all)
        #expect(throws: (any Error).self) {
            try Delete.parse(["Soon", "0", "--only-completed", "--include-completed"])
        }
    }

    @Test func version() {
        #expect(CLI.configuration.version.isEmpty == false)
    }
}

struct URLOptionTests {
    @Test func acceptsURLs() throws {
        #expect(try Add.parse(["Soon", "x", "--url", "https://example.com/a?b=c"]).url == "https://example.com/a?b=c")
        #expect(try Edit.parse(["Soon", "0", "--url", ""]).changes.url == "")
    }

    @Test func rejectsRelativeURLs() {
        #expect(throws: (any Error).self) { try Add.parse(["Soon", "x", "--url", "not a url"]) }
    }
}
