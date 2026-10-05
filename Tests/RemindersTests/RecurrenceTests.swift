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
}
