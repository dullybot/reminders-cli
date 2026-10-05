import Foundation
@testable import RemindersLibrary
import Testing

struct RelativeTimeTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test(arguments: [("in 2 minutes", Calendar.Component.minute, 2), ("in 1 hour", .hour, 1), ("in 3 hrs", .hour, 3)])
    func relativeTime(argument: String, component: Calendar.Component, count: Int) throws {
        let components = try #require(DateComponents(argument: argument))
        let date = try #require(components.date)
        let expected = try #require(calendar.date(byAdding: component, value: count, to: Date()))

        #expect(components.hour != nil)
        #expect(abs(date.timeIntervalSince(expected)) < 5)
    }
}
