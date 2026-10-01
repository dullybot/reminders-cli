import Foundation
@testable import RemindersLibrary
import Testing

struct DueDayRangeTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test func coversWholeDay() throws {
        let noon = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 8, hour: 12)))
        let range = dueDayRange(for: noon, includeOverdue: false, calendar: calendar)

        // Just before midnight, since EventKit's start bound is exclusive.
        #expect(range.start == calendar.startOfDay(for: noon).addingTimeInterval(-1))
        #expect(range.end == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: noon)))
    }

    @Test func overdueHasNoStart() throws {
        let noon = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 8, hour: 12)))

        #expect(dueDayRange(for: noon, includeOverdue: true, calendar: calendar).start == nil)
    }
}
