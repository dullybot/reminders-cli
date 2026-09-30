import Foundation
@testable import RemindersLibrary
import Testing

struct AlarmTests {
    private let due = Date(timeIntervalSince1970: 1_000_000)

    @Test(arguments: [("-15m", -900.0), ("15m", -900.0), ("-1h", -3_600.0), ("+30m", 1_800.0), ("-2d", -172_800.0), ("-1w", -604_800.0)])
    func parsesOffsets(argument: String, offset: TimeInterval) throws {
        let spec = try #require(AlarmSpec(argument: argument))
        #expect(spec.needsDueDate)
        #expect(spec.date(dueDate: due) == due.addingTimeInterval(offset))
    }

    @Test func parsesAbsoluteDates() throws {
        let spec = try #require(AlarmSpec(argument: "tomorrow 9am"))
        #expect(!spec.needsDueDate)
        #expect(spec.date(dueDate: nil) == DateComponents(argument: "tomorrow 9am")?.date)
    }

    @Test(arguments: ["-m", "soon", "-1x", "--15m"])
    func rejectsGarbage(argument: String) {
        #expect(AlarmSpec(argument: argument) == nil)
    }

    @Test func relativeNeedsDueDate() throws {
        #expect(try #require(AlarmSpec(argument: "-15m")).date(dueDate: nil) == nil)
        #expect(throws: (any Error).self) { try Add.parse(["Soon", "x", "--alarm", "-15m"]) }
    }

    @Test func parsesDashValues() throws {
        let add = try Add.parse(["Soon", "x", "--due-date", "tomorrow 9am", "--alarm", "-15m", "--alarm", "tomorrow 8am"])
        #expect(add.alarm.count == 2)
        #expect(try Edit.parse(["Soon", "0", "--clear-alarms"]).changes.clearAlarms)
    }
}
