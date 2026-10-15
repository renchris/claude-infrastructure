// probe — read-only window/Space facts plus a stand-in for kitty-pane-menu-native, for the
// 2026-10-15 kitty crash repro (docs/research/kitty-crash-2026-10-15/README.md § Repro).
//
//   probe fs <pid>                    one row per layer-0 window (>200 px tall) owned by <pid>:
//                                     num  x  y  w  h  onscreen  spaceTypes(comma)
//                                     space type 4 = a native-fullscreen Space, 0 = a desktop.
//   probe front                       pid of the frontmost application
//   probe helper <cancel_ms> <hold_ms> the stand-in: an .accessory app that activates itself and
//                                     pops an NSMenu at the pointer exactly as the real helper does
//                                     (kitty-pane-menu-native.swift:272-296), cancels it after
//                                     <cancel_ms>, waits <hold_ms> (the real helper's exit took
//                                     ~300 ms on the analytics barrier, unilog :305), and exits.
//
// Build: swiftc -O -o probe probe.swift
import AppKit
import CoreGraphics

typealias MainConnFn = @convention(c) () -> Int32
typealias SpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
typealias SpaceGetTypeFn = @convention(c) (Int32, UInt64) -> Int32

func fsRows(pid: Int) -> Int32 {
    guard let h = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
          let pConn = dlsym(h, "_CGSDefaultConnection") ?? dlsym(h, "CGSMainConnectionID"),
          let pWins = dlsym(h, "CGSCopySpacesForWindows"),
          let pType = dlsym(h, "CGSSpaceGetType") else {
        FileHandle.standardError.write("DLSYM-MISS\n".data(using: .utf8)!)
        return 2
    }
    let conn = unsafeBitCast(pConn, to: MainConnFn.self)()
    let spacesFor = unsafeBitCast(pWins, to: SpacesForWindowsFn.self)
    let typeOf = unsafeBitCast(pType, to: SpaceGetTypeFn.self)
    guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
        return 1
    }
    var out = ""
    for w in list {
        guard (w[kCGWindowOwnerPID as String] as? Int) == pid,
              (w[kCGWindowLayer as String] as? Int) == 0,
              let num = w[kCGWindowNumber as String] as? Int,
              let b = w[kCGWindowBounds as String] as? [String: CGFloat],
              let hgt = b["Height"], hgt > 200 else { continue }
        let sids = spacesFor(conn, 0x7, [NSNumber(value: num)] as CFArray)?.takeRetainedValue() as? [UInt64] ?? []
        let types = sids.map { String(typeOf(conn, $0)) }.joined(separator: ",")
        let on = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
        out += "\(num)\t\(Int(b["X"] ?? 0))\t\(Int(b["Y"] ?? 0))\t\(Int(b["Width"] ?? 0))\t\(Int(hgt))"
             + "\t\(on ? 1 : 0)\t\(types.isEmpty ? "-" : types)\n"
    }
    FileHandle.standardOutput.write(out.data(using: .utf8)!)
    return 0
}

let argv = CommandLine.arguments
if argv.count == 3 && argv[1] == "fs", let pid = Int(argv[2]) {
    exit(fsRows(pid: pid))
}
if argv.count == 2 && argv[1] == "front" {
    print(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1)
    exit(0)
}
// The Apple Event `tell application "kitty" to activate` sends (misc/actv), addressed by PID so it
// can only reach the throwaway kitty, never the live one that shares its name and bundle id.
if argv.count == 3 && argv[1] == "activate", let pid = Int32(argv[2]) {
    let ev = NSAppleEventDescriptor(eventClass: AEEventClass(kAEMiscStandards), eventID: AEEventID(kAEActivate),
                                    targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
                                    returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    do { _ = try ev.sendEvent(options: [.noReply], timeout: 5) } catch {
        FileHandle.standardError.write("activate: AE failed (\(error)); NSRunningApplication fallback\n".data(using: .utf8)!)
        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps])
    }
    exit(0)
}
if argv.count == 4 && argv[1] == "helper", let cancelMs = Int(argv[2]), let holdMs = Int(argv[3]) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    let menu = NSMenu()
    menu.autoenablesItems = false
    for t in ["Paste", "Move to New Window", "kcrash-repro stand-in", "Close Pane"] {
        menu.addItem(NSMenuItem(title: t, action: nil, keyEquivalent: ""))
    }
    let timer = Timer(timeInterval: Double(cancelMs) / 1000, repeats: false) { _ in menu.cancelTracking() }
    RunLoop.main.add(timer, forMode: .common)
    let shown = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    FileHandle.standardError.write("shown=\(shown)\n".data(using: .utf8)!)
    if holdMs > 0 { usleep(UInt32(holdMs) * 1000) }
    exit(0)
}
FileHandle.standardError.write("usage: probe fs <pid> | front | helper <cancel_ms> <hold_ms>\n".data(using: .utf8)!)
exit(2)
