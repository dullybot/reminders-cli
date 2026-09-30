import ArgumentParser
import EventKit
import Foundation

public enum RepeatFrequency: String, ExpressibleByArgument, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly

    public static let commaSeparatedCases = Self.allCases.map { $0.rawValue }.joined(separator: ", ")

    var ekFrequency: EKRecurrenceFrequency {
        switch self {
            case .daily: return .daily
            case .weekly: return .weekly
            case .monthly: return .monthly
            case .yearly: return .yearly
        }
    }
}

struct Recurrence {
    let frequency: RepeatFrequency
    let interval: Int
    let end: DateComponents?

    var rule: EKRecurrenceRule {
        EKRecurrenceRule(
            recurrenceWith: self.frequency.ekFrequency,
            interval: self.interval,
            end: self.end?.date.map { EKRecurrenceEnd(end: $0) })
    }
}

/// e.g. "every day", "every 2 weeks"
func describe(_ rule: EKRecurrenceRule) -> String {
    let unit: String
    switch rule.frequency {
        case .daily: unit = "day"
        case .weekly: unit = "week"
        case .monthly: unit = "month"
        case .yearly: unit = "year"
        @unknown default: unit = "period"
    }

    return rule.interval == 1 ? "every \(unit)" : "every \(rule.interval) \(unit)s"
}

struct RepeatOptions: ParsableArguments {
    @Option(
        name: .customLong("repeat"),
        help: "Repeat the reminder, one of: \(RepeatFrequency.commaSeparatedCases)")
    var frequency: RepeatFrequency?

    @Option(help: "Repeat every N periods, e.g. 2 with '--repeat weekly' for every other week")
    var repeatInterval: Int?

    @Option(help: "The date the repetition ends")
    var repeatEnd: DateComponents?

    var recurrence: Recurrence? {
        self.frequency.map { Recurrence(frequency: $0, interval: self.repeatInterval ?? 1, end: self.repeatEnd) }
    }

    func validate() throws {
        if let repeatInterval, repeatInterval < 1 {
            throw ValidationError("--repeat-interval must be at least 1")
        }

        if self.frequency == nil && (self.repeatInterval != nil || self.repeatEnd != nil) {
            throw ValidationError("--repeat-interval and --repeat-end require --repeat")
        }
    }
}
