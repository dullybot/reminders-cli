import Foundation
@testable import RemindersLibrary
import Testing

struct NaturalLanguageTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test func yesterday() throws {
        let components = try #require(DateComponents(argument: "yesterday"))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: Date()))
        let expectedComponents = calendar.dateComponents(
            calendarComponents(except: timeComponents), from: yesterday)

        #expect(components == expectedComponents)
    }

    @Test func todayString() throws {
        let components = try #require(DateComponents(argument: "today"))
        let expectedComponents = calendar.dateComponents(
            calendarComponents(except: timeComponents), from: Date())

        #expect(components == expectedComponents)
    }

    @Test func todayNoon() throws {
        let components = try #require(DateComponents(argument: "12:00"))
        let today = try #require(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()))
        let expectedComponents = calendar.dateComponents(in: .current, from: today)

        #expect(components == expectedComponents)
    }

    @Test func tonight() throws {
        let components = try #require(DateComponents(argument: "tonight"))
        let today = try #require(calendar.date(bySettingHour: 19, minute: 0, second: 0, of: Date()))
        let expectedComponents = calendar.dateComponents(in: .current, from: today)

        #expect(components == expectedComponents)
    }

    @Test func tomorrow() throws {
        let components = try #require(DateComponents(argument: "tomorrow"))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: Date()))
        let expectedComponents = calendar.dateComponents(
            calendarComponents(except: timeComponents), from: tomorrow)

        #expect(components == expectedComponents)
    }

    @Test func usesGregorianCalendar() throws {
        let components = try #require(DateComponents(argument: "tomorrow"))

        #expect(components.calendar?.identifier == .gregorian)
    }

    @Test func tomorrowAtTime() throws {
        let components = try #require(DateComponents(argument: "tomorrow 9pm"))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: Date()))
        let tomorrowAt9 = try #require(
            calendar.date(bySettingHour: 21, minute: 0, second: 0, of: tomorrow))
        let expectedComponents = calendar.dateComponents(in: .current, from: tomorrowAt9)

        #expect(components == expectedComponents)
    }

    @Test func relativeDayCount() throws {
        let components = try #require(DateComponents(argument: "in 2 days"))
        let inTwoDays = try #require(calendar.date(byAdding: .day, value: 2, to: Date()))
        let expectedComponents = calendar.dateComponents(
            calendarComponents(except: timeComponents), from: inTwoDays)

        #expect(components == expectedComponents)
    }

    @Test func nextSaturday() throws {
        let components = try #require(DateComponents(argument: "next saturday"))
        let date = try #require(calendar.date(from: components))

        #expect(calendar.isDateInWeekend(date))
    }

    // FB8921206
    @Test func nextWeekend() {
        // TODO: This should be inverted but DataDetector doesn't support it right now
        #expect(DateComponents(argument: "next weekend") == nil)
    }

    @Test func specificDays() {
        #expect(DateComponents(argument: "next monday") != nil)
        #expect(DateComponents(argument: "on monday at 9pm") != nil)
    }

    @Test func ignoreRandomString() {
        #expect(DateComponents(argument: "blah tomorrow 9pm") == nil)
    }
}
