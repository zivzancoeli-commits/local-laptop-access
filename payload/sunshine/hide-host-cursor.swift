import AppKit
import Darwin
import Foundation

/// Hide the macOS pointer while a Moonlight session is active.
/// Usage: hide-host-cursor start|stop|run

let home = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/sunshine")
let runURL = home.appendingPathComponent("hide-host-cursor.run")
let pidURL = home.appendingPathComponent("hide-host-cursor.pid")

func runningPid() -> pid_t? {
    guard let text = try? String(contentsOf: pidURL, encoding: .utf8),
          let value = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
          value > 1
    else {
        return nil
    }
    if kill(value, 0) == 0 || errno == EPERM {
        return value
    }
    return nil
}

func stopDaemon() {
    try? FileManager.default.removeItem(at: runURL)
    if let pid = runningPid() {
        kill(pid, SIGTERM)
        for _ in 0..<20 {
            if runningPid() == nil {
                break
            }
            usleep(50_000)
        }
        if let pid = runningPid() {
            kill(pid, SIGKILL)
        }
    }
    try? FileManager.default.removeItem(at: pidURL)
    NSCursor.unhide()
}

let command = CommandLine.arguments.dropFirst().first ?? "start"

switch command {
case "stop":
    stopDaemon()
    print("cursor shown")
case "run":
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    try? "\(getpid())".write(to: pidURL, atomically: true, encoding: .utf8)
    NSCursor.hide()
    Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
        if !FileManager.default.fileExists(atPath: runURL.path) {
            timer.invalidate()
            NSCursor.unhide()
            CFRunLoopStop(CFRunLoopGetMain())
        }
    }
    RunLoop.main.run()
default:
    stopDaemon()
    FileManager.default.createFile(atPath: runURL.path, contents: nil)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = ["run"]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        try "\(process.processIdentifier)".write(to: pidURL, atomically: true, encoding: .utf8)
        print("cursor hidden pid=\(process.processIdentifier)")
    } catch {
        fputs("failed to start cursor hider: \(error)\n", stderr)
        try? FileManager.default.removeItem(at: runURL)
        exit(1)
    }
}
