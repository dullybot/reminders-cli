import ArgumentParser
import EventKit
import Foundation

public enum Sort: String, Decodable, ExpressibleByArgument, CaseIterable {
    case none
    case creationDate = "creation-date"
    case dueDate = "due-date"

    public static let commaSeparatedCases = Self.allCases.map { $0.rawValue }.joined(separator: ", ")

    func sortFunction(order: CustomSortOrder) -> (EKReminder, EKReminder) -> Bool {
        switch self {
            case .none: return { _, _ in fatalError() }
            case .creationDate: return { order.isOrdered($0.creationDate, $1.creationDate) }
            case .dueDate: return { order.isOrdered($0.dueDateComponents?.date, $1.dueDateComponents?.date) }
        }
    }
}

// TODO: Replace with SortOrder when we drop < macOS 12.0
public enum CustomSortOrder: String, Decodable, ExpressibleByArgument, CaseIterable {
    case ascending
    case descending

    public static let commaSeparatedCases = Self.allCases.map { $0.rawValue }.joined(separator: ", ")

    /// Orders two optional dates, always placing missing dates last.
    func isOrdered(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
            case (.none, _): return false
            case (.some, .none): return true
            case let (.some(lhs), .some(rhs)): return self == .ascending ? lhs < rhs : lhs > rhs
        }
    }
}
