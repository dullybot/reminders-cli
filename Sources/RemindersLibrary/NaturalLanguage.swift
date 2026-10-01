import ArgumentParser
import Foundation

private let calendar = Calendar(identifier: .gregorian)
private let allComponents: Set<Calendar.Component> = [
    .era, .year, .yearForWeekOfYear, .quarter, .month,
    .weekOfYear, .weekOfMonth, .weekday, .weekdayOrdinal, .day,
    .hour, .minute, .second, .nanosecond,
    .calendar, .timeZone
]
let timeComponents: Set<Calendar.Component> = [
    .hour, .minute, .second, .nanosecond,
]

func calendarComponents(except removedComponents: Set<Calendar.Component> = []) -> Set<Calendar.Component> {
    return allComponents.subtracting(removedComponents)
}

/// "in 5 minutes", "in 2 hours": NSDataDetector doesn't recognize these.
private func componentsFromRelativeTime(_ string: String, now: Date = Date()) -> DateComponents? {
    let words = string.lowercased().split(separator: " ")
    guard words.count == 3, words[0] == "in", let count = Int(words[1]), count >= 0 else {
        return nil
    }

    let component: Calendar.Component
    switch words[2] {
        case "minute", "minutes", "min", "mins": component = .minute
        case "hour", "hours", "hr", "hrs": component = .hour
        default: return nil
    }

    return calendar.date(byAdding: component, value: count, to: now).map {
        calendar.dateComponents(in: .current, from: $0)
    }
}

private func components(from string: String) -> DateComponents? {
    if let components = componentsFromRelativeTime(string) {
        return components
    }

    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
        fatalError("error: failed to create NSDataDetector")
    }

    let range = NSRange(string.startIndex..<string.endIndex, in: string)

    let matches = detector.matches(in: string, options: .anchored, range: range)
    guard matches.count == 1, let match = matches.first, let date = match.date else {
        return nil
    }

    var includeTime = true
    if match.responds(to: NSSelectorFromString("timeIsSignificant")) {
        includeTime = match.value(forKey: "timeIsSignificant") as? Bool ?? true
    } else {
        print("warning: timeIsSignificant is not available, please report this to keith/reminders-cli")
    }

    let timeZone = match.timeZone ?? .current
    let parsedComponents = calendar.dateComponents(in: timeZone, from: date)
    if includeTime {
        return parsedComponents
    } else {
        return calendar.dateComponents(calendarComponents(except: timeComponents), from: date)
    }
}

extension DateComponents: @retroactive ExpressibleByArgument {
      public init?(argument: String) {
          if let components = components(from: argument) {
              self = components
          } else {
              return nil
          }
      }
}
