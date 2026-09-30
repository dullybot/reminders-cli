import EventKit
import Foundation
@testable import RemindersLibrary
import Testing

struct RecurrenceTests {
    @Test func buildsRule() throws {
        let end = try #require(DateComponents(argument: "2027-01-01"))
        let rule = Recurrence(frequency: .weekly, interval: 2, end: end).rule

        #expect(rule.frequency == .weekly)
        #expect(rule.interval == 2)
        #expect(rule.recurrenceEnd?.endDate == end.date)
    }

    @Test func describesRule() {
        #expect(describe(Recurrence(frequency: .daily, interval: 1, end: nil).rule) == "every day")
        #expect(describe(Recurrence(frequency: .monthly, interval: 3, end: nil).rule) == "every 3 months")
    }

    @Test func parsesOptions() throws {
        let add = try Add.parse(["Soon", "Pay", "rent", "--due-date", "tomorrow", "--repeat", "monthly"])
        #expect(add.repeatOptions.recurrence?.frequency == .monthly)
        #expect(add.repeatOptions.recurrence?.interval == 1)
    }

    @Test(arguments: [
        ["Soon", "x", "--repeat", "daily"],
        ["Soon", "x", "--due-date", "today", "--repeat-interval", "2"],
        ["Soon", "x", "--due-date", "today", "--repeat", "daily", "--repeat-interval", "0"],
        ["Soon", "x", "--due-date", "today", "--repeat", "hourly"],
    ])
    func rejectsInvalidOptions(arguments: [String]) {
        #expect(throws: (any Error).self) { try Add.parse(arguments) }
    }

    @Test func editClearRepeat() throws {
        #expect(try Edit.parse(["Soon", "0", "--clear-repeat"]).changes.clearRecurrence)
        #expect(throws: (any Error).self) { try Edit.parse(["Soon", "0", "--clear-repeat", "--repeat", "daily"]) }
        #expect(throws: (any Error).self) { try Edit.parse(["Soon", "0"]) }
    }
}
