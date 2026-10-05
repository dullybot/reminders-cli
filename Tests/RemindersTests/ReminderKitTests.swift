@testable import RemindersLibrary
import Testing

struct ReminderKitTests {
    /// Only inspects the Objective-C runtime; never talks to remindd.
    @Test func runtimeHasEverythingTheBridgeUses() {
        #expect(ReminderKitBridge.missingRequirements() == [])
    }

    @Test func parsesOptions() throws {
        let add = try Add.parse(["Soon", "x", "--flag", "--tag", "#work", "-t", "home", "--parent", "0", "--assign", "Sam"])
        #expect(add.flag)
        #expect(add.tag == ["#work", "home"])
        #expect(add.parent == "0")

        let edit = try Edit.parse(["Soon", "1", "--unflag", "--remove-tag", "work", "--unnest", "--unassign"])
        let changes = edit.reminderKitChanges
        #expect(changes.flagged == false)
        #expect(changes.removeTags == ["work"])
        #expect(changes.unnest && changes.unassign)
        #expect(changes.needsReminderKit)
    }

    @Test func urlAloneDoesNotNeedReminderKit() throws {
        let changes = try Edit.parse(["Soon", "1", "--url", "https://example.com"]).reminderKitChanges
        #expect(!changes.isEmpty)
        #expect(!changes.needsReminderKit)
    }

    @Test(arguments: [["--flag", "--unflag"], ["--parent", "0", "--unnest"], ["--assign", "a", "--unassign"]])
    func rejectsContradictions(arguments: [String]) {
        #expect(throws: (any Error).self) { try Edit.parse(["Soon", "1"] + arguments) }
    }
}
