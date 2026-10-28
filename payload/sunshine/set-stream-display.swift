import CoreGraphics
import Foundation

/// Switch the built-in display to a 1x mode at the same logical size so
/// Sunshine is not encoding a 2880x1800 Retina framebuffer.
/// Usage: set-stream-display [list|apply|restore]

let stateURL = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent(".config/sunshine/display-restore.json")

struct SavedMode: Codable {
    var ioDisplayModeID: Int32
    var width: Int
    var height: Int
    var pixelWidth: Int
    var pixelHeight: Int
}

func allModes(_ displayID: CGDirectDisplayID) -> [CGDisplayMode] {
    let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
    guard let raw = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else {
        return []
    }
    return raw
}

func describe(_ mode: CGDisplayMode) -> String {
    let scale = mode.width == 0 ? 0 : Double(mode.pixelWidth) / Double(mode.width)
    return "\(mode.width)x\(mode.height) pixel=\(mode.pixelWidth)x\(mode.pixelHeight) scale=\(String(format: "%.2f", scale)) hz=\(Int(mode.refreshRate)) id=\(mode.ioDisplayModeID)"
}

func is1x(_ mode: CGDisplayMode) -> Bool {
    mode.pixelWidth == mode.width && mode.pixelHeight == mode.height
}

func pixelCount(_ mode: CGDisplayMode) -> Int {
    mode.pixelWidth * mode.pixelHeight
}

/// Prefer a 1x mode with the same logical size as the current desktop
/// (1440x900 on this laptop). That does not zoom the UI; it only drops the
/// Retina 2880x1800 capture that was overloading VideoToolbox.
func pickStreamMode(_ modes: [CGDisplayMode], current: CGDisplayMode) -> CGDisplayMode? {
    let targetW = current.width
    let targetH = current.height
    let exact = modes.first { is1x($0) && $0.width == targetW && $0.height == targetH }
    if let exact {
        return exact
    }
    let oneX = modes.filter { is1x($0) && $0.width <= targetW && $0.height <= targetH && $0.width >= 1280 }
    return oneX.max { pixelCount($0) < pixelCount($1) }
}

func apply(_ displayID: CGDirectDisplayID, _ mode: CGDisplayMode) -> Bool {
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success else { return false }
    let status = CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)
    if status != .success {
        CGCancelDisplayConfiguration(config)
        return false
    }
    return CGCompleteDisplayConfiguration(config, .permanently) == .success
}

func saveCurrent(_ displayID: CGDirectDisplayID) throws {
    guard let current = CGDisplayCopyDisplayMode(displayID) else { return }
    let saved = SavedMode(
        ioDisplayModeID: current.ioDisplayModeID,
        width: current.width,
        height: current.height,
        pixelWidth: current.pixelWidth,
        pixelHeight: current.pixelHeight
    )
    let data = try JSONEncoder().encode(saved)
    try data.write(to: stateURL, options: .atomic)
}

func restore(_ displayID: CGDirectDisplayID) -> Bool {
    guard let data = try? Data(contentsOf: stateURL),
          let saved = try? JSONDecoder().decode(SavedMode.self, from: data)
    else {
        fputs("no saved display mode\n", stderr)
        return false
    }
    let match = allModes(displayID).first { mode in
        mode.ioDisplayModeID == saved.ioDisplayModeID
            || (mode.pixelWidth == saved.pixelWidth && mode.pixelHeight == saved.pixelHeight
                && mode.width == saved.width && mode.height == saved.height)
    }
    guard let mode = match else {
        fputs("saved mode not found\n", stderr)
        return false
    }
    return apply(displayID, mode)
}

func builtinDisplayID() -> CGDirectDisplayID {
    var displays = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    CGGetOnlineDisplayList(16, &displays, &count)
    for id in displays.prefix(Int(count)) where CGDisplayIsBuiltin(id) != 0 {
        return id
    }
    CGGetActiveDisplayList(16, &displays, &count)
    for id in displays.prefix(Int(count)) where CGDisplayIsBuiltin(id) != 0 {
        return id
    }
    return CGMainDisplayID()
}

let displayID = builtinDisplayID()
let command = CommandLine.arguments.dropFirst().first ?? "apply"

switch command {
case "list":
    guard let current = CGDisplayCopyDisplayMode(displayID) else {
        fputs("no current display mode\n", stderr)
        exit(1)
    }
    print("current: \(describe(current))")
    if let target = pickStreamMode(allModes(displayID), current: current) {
        print("stream: \(describe(target))")
    }
    for mode in allModes(displayID) {
        let mark = is1x(mode) ? "1x" : "scaled"
        print("\(mark) \(describe(mode))")
    }
case "restore":
    if restore(displayID) {
        if let current = CGDisplayCopyDisplayMode(displayID) {
            print("restored \(describe(current))")
        }
        try? FileManager.default.removeItem(at: stateURL)
        exit(0)
    }
    exit(1)
default:
    guard let current = CGDisplayCopyDisplayMode(displayID) else {
        fputs("no current display mode\n", stderr)
        exit(1)
    }
    let modes = allModes(displayID)
    guard let target = pickStreamMode(modes, current: current) else {
        fputs("no suitable 1x display mode\n", stderr)
        exit(1)
    }
    if current.pixelWidth == target.pixelWidth && current.pixelHeight == target.pixelHeight && is1x(current) {
        print("already \(describe(current))")
        exit(0)
    }
    do { try saveCurrent(displayID) } catch {
        fputs("failed to save current mode: \(error)\n", stderr)
        exit(1)
    }
    if apply(displayID, target) {
        print("switched \(describe(current)) -> \(describe(target))")
        exit(0)
    }
    fputs("failed to switch display mode\n", stderr)
    exit(1)
}
