import ArgumentParser
import EventKit
import Foundation

/// An `--alarm` value: a natural language date, or an offset from the due date
/// such as `-15m`, `-1h` or `-2d` (before) and `+30m` (after).
enum AlarmSpec: ExpressibleByArgument {
    case absolute(DateComponents)
    case relative(TimeInterval)

    private static let units: [Character: TimeInterval] = ["m": 60, "h": 3_600, "d": 86_400, "w": 604_800]

    init?(argument: String) {
        let value = argument.trimmingCharacters(in: .whitespaces).lowercased()
        if let unit = value.last.flatMap({ Self.units[$0] }) {
            var amount = value.dropLast()
            let sign: TimeInterval = amount.first == "+" ? 1 : -1
            if amount.first == "+" || amount.first == "-" {
                amount = amount.dropFirst()
            }

            if let count = Int(amount), count >= 0 {
                self = .relative(sign * TimeInterval(count) * unit)
                return
            }
        }

        guard let components = DateComponents(argument: argument) else {
            return nil
        }

        self = .absolute(components)
    }

    var needsDueDate: Bool {
        if case .relative = self {
            return true
        }

        return false
    }

    func date(dueDate: Date?) -> Date? {
        switch self {
            case .absolute(let components): return components.date
            case .relative(let offset): return dueDate.map { $0.addingTimeInterval(offset) }
        }
    }
}

extension EKAlarm {
    /// When the alarm fires, resolving offsets against the reminder's due date.
    func fireDate(for reminder: EKReminder) -> Date? {
        if self.structuredLocation != nil {
            return nil
        }

        return self.absoluteDate ?? reminder.dueDateComponents?.date.map { $0.addingTimeInterval(self.relativeOffset) }
    }
}
