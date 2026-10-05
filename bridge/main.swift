// RemindersBridge: launchd starts this when ~/.reminders-bridge/queue is non-empty.
// Runs each request through the bundled `reminders` binary (so TCC attributes it to this app),
// then exits after 60s with no new requests.
import Foundation

let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".reminders-bridge")
let queue = root.appendingPathComponent("queue")
let out = root.appendingPathComponent("out")
let cli = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/reminders")
let fm = FileManager.default
try? fm.createDirectory(at: queue, withIntermediateDirectories: true)
try? fm.createDirectory(at: out, withIntermediateDirectories: true)

func write(_ data: Data, _ name: String) {
    let tmp = out.appendingPathComponent(".\(name)")
    try? data.write(to: tmp)
    _ = try? fm.replaceItemAt(out.appendingPathComponent(name), withItemAt: tmp)
}

func drain() {
    let reqs = (try? fm.contentsOfDirectory(at: queue, includingPropertiesForKeys: nil)) ?? []
    for req in reqs where req.pathExtension == "req" {
        let id = req.deletingPathExtension().lastPathComponent
        let args = ((try? String(contentsOf: req, encoding: .utf8)) ?? "")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init).dropLast()
        try? fm.removeItem(at: req)
        let p = Process()
        p.executableURL = cli
        p.arguments = Array(args)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        var rc: Int32 = 127
        var data = Data()
        if (try? p.run()) != nil {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            rc = p.terminationStatus
        }
        write(data, "\(id).out")
        write(Data("\(rc)\n".utf8), "\(id).rc")
    }
}

var idle: DispatchWorkItem?
func armIdle() {
    idle?.cancel()
    idle = DispatchWorkItem { exit(0) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: idle!)
}

let fd = open(queue.path, O_EVTONLY)
let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
source.setEventHandler { drain(); armIdle() }
source.resume()
drain()
armIdle()
dispatchMain()
