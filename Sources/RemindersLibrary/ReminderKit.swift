import EventKit
import Foundation
import ObjectiveC

// Everything that goes through Apple's private ReminderKit framework lives in
// this file. EventKit has no API for flags, tags, subtasks, assignees or the
// URL shown in Reminders.app, so these are reached through the Objective-C
// runtime and fail with a clear error when a class or selector is missing.

/// Reminders.app-only fields for a reminder.
struct ReminderDetails: Encodable, Equatable {
    var flagged = false
    var tags: [String] = []
    /// `calendarItemIdentifier` of the parent reminder, if this is a subtask.
    var parentIdentifier: String?
    var assignee: String?
    var url: URL?
}

/// Reminders.app-only changes; nil or empty leaves a field untouched.
struct ReminderKitChanges {
    var flagged: Bool?
    var addTags: [String] = []
    var removeTags: [String] = []
    var clearTags = false
    var parent: EKReminder?
    var unnest = false
    var assignee: String?
    var unassign = false
    /// An empty string removes the URL attachment.
    var url: String?

    var isEmpty: Bool {
        self.flagged == nil && self.addTags.isEmpty && self.removeTags.isEmpty && !self.clearTags
            && self.parent == nil && !self.unnest && self.assignee == nil && !self.unassign
            && self.url == nil
    }

    /// Whether ReminderKit is needed; the URL alone is also stored through EventKit.
    var needsReminderKit: Bool {
        var withoutURL = self
        withoutURL.url = nil
        return !withoutURL.isEmpty
    }
}

protocol ReminderExtras {
    func details(for reminders: [EKReminder]) -> [String: ReminderDetails]
    func apply(_ changes: ReminderKitChanges, to reminder: EKReminder) throws
}

enum ReminderKitError: LocalizedError {
    case unavailable(String)
    case notFound(String)
    case noSuchAssignee(String, [String])
    case failed(String)

    var errorDescription: String? {
        switch self {
            case .unavailable(let symbol):
                return "this feature needs Apple's private ReminderKit framework, which is missing '\(symbol)' on this macOS version"
            case .notFound(let title):
                return "ReminderKit couldn't find the reminder '\(title)'"
            case .noSuchAssignee(let name, let sharees):
                let options = sharees.isEmpty ? "the list isn't shared" : "choose one of: \(sharees.joined(separator: ", "))"
                return "no one named '\(name)' shares this list, \(options)"
            case .failed(let reason):
                return "ReminderKit save failed: \(reason)"
        }
    }
}

final class ReminderKitBridge: ReminderExtras {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/ReminderKit.framework/ReminderKit"
    /// Hashtag type used by Reminders.app for user-entered tags.
    private static let hashtagType = 0
    /// Assignment status used for new assignments.
    private static let assignmentStatus = 0

    /// Every class, `+`class and `-`instance method used below, checked up front so a
    /// macOS update that renames one fails with a clear error instead of crashing.
    private static let requirements: [String: [String]] = [
        "REMStore": ["-init", "-fetchRemindersWithObjectIDs:error:"],
        "REMReminder": ["+objectIDWithUUID:", "-storage", "-list", "-attachmentContext"],
        "REMReminderStorage": ["-objectID", "-flagged", "-hashtags", "-parentReminderID", "-currentAssignment"],
        "REMSaveRequest": ["-initWithStore:", "-updateReminder:", "-saveSynchronouslyWithError:"],
        "REMReminderChangeItem": [
            "-flaggedContext", "-hashtagContext", "-subtaskContext", "-assignmentContext",
            "-attachmentContext", "-removeFromParentReminder",
        ],
        "REMReminderFlaggedContextChangeItem": ["-setFlagged:"],
        "REMReminderHashtagContextChangeItem": ["-hashtags", "-addHashtagWithType:name:", "-removeHashtag:"],
        "REMReminderSubtaskContextChangeItem": ["-addReminderChangeItem:"],
        "REMReminderAssignmentContextChangeItem": [
            "-removeAllAssignments", "-addAssignmentWithAssigneeID:originatorID:status:",
        ],
        "REMReminderAttachmentContextChangeItem": ["-setURLAttachmentWithURL:", "-removeURLAttachments"],
        "REMReminderAttachmentContext": ["-urlAttachments"],
        "REMURLAttachment": ["-url"],
        "REMList": ["-shareeContext"],
        "REMListShareeContext": ["-sharees"],
        "REMSharee": ["+nullifiedAssignmentOriginatorID", "-objectID", "-displayName", "-firstName", "-address"],
        "REMAssignment": ["-assigneeID"],
        "REMHashtag": ["-name"],
        "REMObjectID": ["-uuid"],
    ]

    private let store: NSObject

    init() throws {
        if let missing = Self.missingRequirements().first {
            throw ReminderKitError.unavailable(missing)
        }

        let storeClass: NSObject.Type = try objcClass("REMStore")
        self.store = storeClass.init()
    }

    /// Loads ReminderKit and lists anything the bridge needs that it lacks.
    static func missingRequirements() -> [String] {
        guard dlopen(Self.frameworkPath, RTLD_NOW) != nil else {
            return [Self.frameworkPath]
        }

        return Self.requirements.sorted { $0.key < $1.key }.flatMap { className, methods -> [String] in
            guard let objcClass = NSClassFromString(className) else {
                return [className]
            }

            return methods.filter { method in
                let selector = NSSelectorFromString(String(method.dropFirst()))
                let found = method.hasPrefix("+")
                    ? class_getClassMethod(objcClass, selector) : class_getInstanceMethod(objcClass, selector)
                return found == nil
            }
            .map { "\(className) \($0)" }
        }
    }

    func details(for reminders: [EKReminder]) -> [String: ReminderDetails] {
        guard let remReminders = try? self.fetch(reminders) else {
            return [:]
        }

        var details = [String: ReminderDetails]()
        for (identifier, remReminder) in remReminders {
            // REMReminder forwards these to its storage at runtime, which KVC can't see.
            let storage = remReminder.value(forKey: "storage") as? NSObject
            details[identifier] = ReminderDetails(
                flagged: (storage?.value(forKey: "flagged") as? Int ?? 0) != 0,
                tags: ((storage?.value(forKey: "hashtags") as? NSSet)?.allObjects ?? [])
                    .compactMap { ($0 as? NSObject)?.value(forKey: "name") as? String }
                    .sorted(),
                parentIdentifier: uuidString(storage?.value(forKey: "parentReminderID")),
                assignee: self.assigneeName(of: remReminder),
                url: self.urlAttachment(of: remReminder))
        }

        return details
    }

    func apply(_ changes: ReminderKitChanges, to reminder: EKReminder) throws {
        let targets = [reminder] + (changes.parent.map { [$0] } ?? [])
        let remReminders = try self.fetch(targets)
        guard let remReminder = remReminders[reminderKitKey(reminder)] else {
            throw ReminderKitError.notFound(reminder.title ?? "")
        }

        let saveRequest = try allocInit("REMSaveRequest", "initWithStore:", self.store)
        let changeItem = try call(saveRequest, "updateReminder:", remReminder)

        if let flagged = changes.flagged {
            let flaggedContext = try property(changeItem, "flaggedContext")
            try send(flaggedContext, "setFlagged:", flagged ? 1 : 0)
        }

        if changes.clearTags || !changes.addTags.isEmpty || !changes.removeTags.isEmpty {
            try self.updateTags(of: try property(changeItem, "hashtagContext"), changes)
        }

        if changes.unnest {
            try send(changeItem, "removeFromParentReminder")
        } else if let parent = changes.parent {
            guard let remParent = remReminders[reminderKitKey(parent)] else {
                throw ReminderKitError.notFound(parent.title ?? "")
            }

            let parentChangeItem = try call(saveRequest, "updateReminder:", remParent)
            let subtasks = try property(parentChangeItem, "subtaskContext")
            _ = try call(subtasks, "addReminderChangeItem:", changeItem)
        }

        if changes.unassign || changes.assignee != nil {
            let assignments = try property(changeItem, "assignmentContext")
            try send(assignments, "removeAllAssignments")
            if let assignee = changes.assignee {
                try self.assign(assignee, of: remReminder, in: assignments)
            }
        }

        if let url = changes.url {
            let attachments = try property(changeItem, "attachmentContext")
            if let url = URL(string: url), !url.absoluteString.isEmpty {
                _ = try call(attachments, "setURLAttachmentWithURL:", url as NSURL)
            } else {
                try send(attachments, "removeURLAttachments")
            }
        }

        typealias Save = @convention(c) (NSObject, Selector, UnsafeMutablePointer<NSError?>?) -> Bool
        var error: NSError?
        guard try implementation(saveRequest, "saveSynchronouslyWithError:", Save.self)(
            saveRequest, NSSelectorFromString("saveSynchronouslyWithError:"), &error)
        else {
            throw ReminderKitError.failed(error?.localizedDescription ?? "unknown error")
        }
    }

    // MARK: - Private

    /// ReminderKit objects for EventKit reminders, keyed by `calendarItemIdentifier`,
    /// which is the ReminderKit object UUID for reminders stored by remindd.
    private func fetch(_ reminders: [EKReminder]) throws -> [String: NSObject] {
        let reminderClass: NSObject.Type = try objcClass("REMReminder")
        let objectIDs = reminders.compactMap { reminder in
            UUID(uuidString: reminder.calendarItemIdentifier).flatMap {
                try? call(reminderClass, "objectIDWithUUID:", $0 as NSUUID)
            }
        }

        typealias Fetch = @convention(c) (NSObject, Selector, NSArray, UnsafeMutablePointer<NSError?>?)
            -> Unmanaged<AnyObject>?
        let selector = "fetchRemindersWithObjectIDs:error:"
        var error: NSError?
        let result = try implementation(self.store, selector, Fetch.self)(
            self.store, NSSelectorFromString(selector), objectIDs as NSArray, &error)?.takeUnretainedValue()
        if let error {
            throw ReminderKitError.failed(error.localizedDescription)
        }

        let fetched: [Any]
        if let dictionary = result as? NSDictionary {
            fetched = dictionary.allValues
        } else {
            fetched = (result as? NSArray) as? [Any] ?? []
        }

        var byIdentifier = [String: NSObject]()
        for case let reminder as NSObject in fetched {
            let storage = reminder.value(forKey: "storage") as? NSObject
            if let identifier = uuidString(storage?.value(forKey: "objectID")) {
                byIdentifier[identifier] = reminder
            }
        }

        return byIdentifier
    }

    private func updateTags(of hashtagContext: NSObject, _ changes: ReminderKitChanges) throws {
        let existing = (hashtagContext.value(forKey: "hashtags") as? NSSet)?.allObjects as? [NSObject] ?? []
        let removed = Set(changes.removeTags.map { $0.lowercased() })
        var kept = Set<String>()
        for hashtag in existing {
            let name = (hashtag.value(forKey: "name") as? String)?.lowercased() ?? ""
            if changes.clearTags || removed.contains(name) {
                try call(hashtagContext, "removeHashtag:", hashtag)
            } else {
                kept.insert(name)
            }
        }

        typealias AddHashtag = @convention(c) (NSObject, Selector, Int, NSString) -> Unmanaged<AnyObject>?
        let selector = "addHashtagWithType:name:"
        let add = try implementation(hashtagContext, selector, AddHashtag.self)
        for tag in changes.addTags where kept.insert(tag.lowercased()).inserted {
            _ = add(hashtagContext, NSSelectorFromString(selector), Self.hashtagType, tag as NSString)
        }
    }

    private func sharees(of remReminder: NSObject) -> [NSObject] {
        let list = remReminder.value(forKey: "list") as? NSObject
        let shareeContext = list?.value(forKey: "shareeContext") as? NSObject
        return shareeContext?.value(forKey: "sharees") as? [NSObject] ?? []
    }

    private func assign(_ name: String, of remReminder: NSObject, in assignments: NSObject) throws {
        let sharees = self.sharees(of: remReminder)
        let wanted = name.lowercased()
        guard let sharee = sharees.first(where: { sharee in
            ["displayName", "firstName", "address"].contains {
                (sharee.value(forKey: $0) as? String)?.lowercased() == wanted
            }
        }) else {
            throw ReminderKitError.noSuchAssignee(name, sharees.compactMap(displayName))
        }

        let shareeClass: NSObject.Type = try objcClass("REMSharee")
        let originator = try call(shareeClass, "nullifiedAssignmentOriginatorID")
        typealias Assign = @convention(c) (NSObject, Selector, NSObject, NSObject, Int) -> Unmanaged<AnyObject>?
        let selector = "addAssignmentWithAssigneeID:originatorID:status:"
        guard let assigneeID = sharee.value(forKey: "objectID") as? NSObject else {
            throw ReminderKitError.unavailable("REMSharee.objectID")
        }

        _ = try implementation(assignments, selector, Assign.self)(
            assignments, NSSelectorFromString(selector), assigneeID, originator, Self.assignmentStatus)
    }

    private func assigneeName(of remReminder: NSObject) -> String? {
        let storage = remReminder.value(forKey: "storage") as? NSObject
        guard let assignment = storage?.value(forKey: "currentAssignment") as? NSObject,
            let assigneeID = uuidString(assignment.value(forKey: "assigneeID"))
        else {
            return nil
        }

        let sharee = self.sharees(of: remReminder).first { uuidString($0.value(forKey: "objectID")) == assigneeID }
        return sharee.flatMap(displayName) ?? assigneeID
    }

    private func urlAttachment(of remReminder: NSObject) -> URL? {
        let context = remReminder.value(forKey: "attachmentContext") as? NSObject
        let attachments = context?.value(forKey: "urlAttachments") as? [NSObject]
        return attachments?.first?.value(forKey: "url") as? URL
    }
}

// MARK: - Objective-C runtime helpers

private func objcClass(_ name: String) throws -> NSObject.Type {
    guard let objcClass = NSClassFromString(name) as? NSObject.Type else {
        throw ReminderKitError.unavailable(name)
    }

    return objcClass
}

private func implementation<Function>(_ target: AnyObject, _ selector: String, _: Function.Type) throws
    -> Function
{
    let selector = NSSelectorFromString(selector)
    guard let targetClass = object_getClass(target), class_respondsToSelector(targetClass, selector),
        let method = class_getMethodImplementation(targetClass, selector)
    else {
        throw ReminderKitError.unavailable("\(type(of: target)).\(NSStringFromSelector(selector))")
    }

    return unsafeBitCast(method, to: Function.self)
}

private func property(_ target: NSObject, _ key: String) throws -> NSObject {
    guard target.responds(to: NSSelectorFromString(key)), let value = target.value(forKey: key) as? NSObject else {
        throw ReminderKitError.unavailable("\(type(of: target)).\(key)")
    }

    return value
}

/// Sends a message returning an object, with up to one object argument.
@discardableResult
private func call(_ target: AnyObject, _ selector: String, _ argument: AnyObject? = nil) throws -> NSObject {
    let result: Unmanaged<AnyObject>?
    if let argument {
        typealias Function = @convention(c) (AnyObject, Selector, AnyObject) -> Unmanaged<AnyObject>?
        result = try implementation(target, selector, Function.self)(target, NSSelectorFromString(selector), argument)
    } else {
        typealias Function = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        result = try implementation(target, selector, Function.self)(target, NSSelectorFromString(selector))
    }

    guard let object = result?.takeUnretainedValue() as? NSObject else {
        throw ReminderKitError.failed("\(selector) returned nil")
    }

    return object
}

/// Sends a message with no return value and no argument or one integer argument.
private func send(_ target: AnyObject, _ selector: String, _ argument: Int? = nil) throws {
    if let argument {
        typealias Function = @convention(c) (AnyObject, Selector, Int) -> Void
        try implementation(target, selector, Function.self)(target, NSSelectorFromString(selector), argument)
    } else {
        typealias Function = @convention(c) (AnyObject, Selector) -> Void
        try implementation(target, selector, Function.self)(target, NSSelectorFromString(selector))
    }
}

/// `[[ClassName alloc] initializer argument]`, balancing the +1 references ARC can't see.
private func allocInit(_ className: String, _ initializer: String, _ argument: AnyObject) throws -> NSObject {
    let objcClass = try objcClass(className)
    typealias Alloc = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>
    typealias Initializer = @convention(c) (Unmanaged<AnyObject>, Selector, AnyObject) -> Unmanaged<AnyObject>?
    let alloc = unsafeBitCast(
        method_getImplementation(class_getClassMethod(objcClass, NSSelectorFromString("alloc"))!), to: Alloc.self)
    let selector = NSSelectorFromString(initializer)
    guard class_respondsToSelector(objcClass, selector),
        let method = class_getMethodImplementation(objcClass, selector)
    else {
        throw ReminderKitError.unavailable("\(className).\(initializer)")
    }

    let allocated = alloc(objcClass, NSSelectorFromString("alloc"))
    guard let object = unsafeBitCast(method, to: Initializer.self)(allocated, selector, argument)?
        .takeRetainedValue() as? NSObject
    else {
        throw ReminderKitError.failed("\(className) \(initializer) returned nil")
    }

    return object
}

/// Key matching `uuidString` for an EventKit reminder backed by ReminderKit.
func reminderKitKey(_ reminder: EKReminder) -> String {
    UUID(uuidString: reminder.calendarItemIdentifier)?.uuidString ?? reminder.calendarItemIdentifier
}

private func uuidString(_ objectID: Any?) -> String? {
    ((objectID as? NSObject)?.value(forKey: "uuid") as? UUID)?.uuidString
}

private func displayName(_ sharee: NSObject) -> String? {
    sharee.value(forKey: "displayName") as? String ?? sharee.value(forKey: "address") as? String
}
