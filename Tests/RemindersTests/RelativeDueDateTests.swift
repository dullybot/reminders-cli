import Foundation
@testable import RemindersLibrary
import Testing

struct RelativeDueDateTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let locale = Locale(identifier: "en_US_POSIX")

    private func date(_ day: Int, _ hour: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour)))
    }

    // keith/reminders-cli#101
    @Test func countsCalendarDays() throws {
        let now = try date(8, 9)
        #expect(relativeDueDate(try date(10, 8), relativeTo: now, calendar: calendar, locale: locale) == "in 2 days")
        #expect(relativeDueDate(try date(9, 8), relativeTo: now, calendar: calendar, locale: locale) == "in 1 day")
        #expect(relativeDueDate(try date(6, 23), relativeTo: now, calendar: calendar, locale: locale) == "2 days ago")
    }

    @Test func allDayToday() throws {
        #expect(relativeDueDate(try date(8, 0), allDay: true, relativeTo: try date(8, 15), calendar: calendar, locale: locale) == "today")
    }

    @Test func sameDayUsesTime() throws {
        let now = try date(8, 9)
        #expect(relativeDueDate(try date(8, 12), relativeTo: now, calendar: calendar, locale: locale) == "in 3 hours")
    }
}
