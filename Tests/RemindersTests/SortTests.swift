import Foundation
@testable import RemindersLibrary
import Testing

struct SortTests {
    private let earlier = Date(timeIntervalSince1970: 0)
    private let later = Date(timeIntervalSince1970: 100)

    @Test func ascending() {
        #expect(CustomSortOrder.ascending.isOrdered(earlier, later))
        #expect(!CustomSortOrder.ascending.isOrdered(later, earlier))
    }

    @Test func descending() {
        #expect(CustomSortOrder.descending.isOrdered(later, earlier))
        #expect(!CustomSortOrder.descending.isOrdered(earlier, later))
    }

    @Test(arguments: CustomSortOrder.allCases)
    func missingDatesSortLast(order: CustomSortOrder) {
        #expect(order.isOrdered(earlier, nil))
        #expect(!order.isOrdered(nil, earlier))
        #expect(!order.isOrdered(nil, nil))
    }
}

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
