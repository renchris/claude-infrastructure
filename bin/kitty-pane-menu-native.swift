// kitty-pane-menu-native.swift — the REAL native macOS context menu (an NSMenu popped at the
// cursor), for bin/kitty-pane-menu to try before falling back to its AppleScript "choose from
// list" dialog.
//
// WHY A SEPARATE COMPILED BINARY, NOT JXA. JXA's ObjC bridge (`osascript -l JavaScript`,
// `ObjC.import('Cocoa')`) was tried first: even the most basic `$.NSObject.alloc.init()` raised
// "TypeError: Object is not a function" in this environment, reproduced identically from a full
// login shell (not a sandboxing artifact) — the bridge itself is unreliable here for anything past
// trivial property access. Swift's own Cocoa bindings have none of that ambiguity, and `swiftc` is
// already present (Xcode CLT), so a small compiled helper is the more reliable primitive.
//
// THE ACTUAL UNRESOLVED QUESTION: does an NSMenu popped from a bare, unbundled, non-LaunchServices
// binary actually SHOW when spawned as kitty's `launch --type=background` child — as opposed to
// spawned from an interactive Bash tool call, which measurably did NOT show one (screenshots taken
// mid-call showed the previously-frontmost app, unchanged). Both `activationPolicy(.accessory)`
// and an explicit `activate(ignoringOtherApps:)` are applied below on the theory that the display
// difference is a WindowServer/session-activation gap specific to how the parent process spawned
// this one — kitty.app is a full GUI app with its own bootstrapped session, a Bash-tool subprocess
// may not be. If real-world use (via kitty.conf's mouse_map, not a synthetic invocation) still
// shows nothing, that theory is refuted and this file should be abandoned in favor of the
// AppleScript dialog outright — see the caller's timing-based fallback for how it detects that.
//
//
// TWO MODES, and the guard between them is argv-shaped
//   (default)   argv = the menu item titles; pops the NSMenu, prints the picked title.
//   --windows   prints one TSV row per kitty OS window and pops NOTHING. This is the probe that
//               feeds the move-menu's row labels: the string macOS itself paints on the Mission
//               Control tile, plus the window's left-to-right desktop ordinal. It lives in THIS
//               binary rather than a second one because kitty.conf invokes
//               ${HOME}/.claude/bin/kitty-pane-menu, a symlink into the checkout that
//               os.path.abspath does NOT resolve — so HERE is ~/.claude/bin, and only this file
//               is already compiled to that path by scripts/kitty-setup.sh. A second .swift would
//               need a second build artifact there and a second staleness story.
//
// WHY THE MODE GUARD CANNOT MISFIRE. It requires argc == 2 AND argv[1] == "--windows". No menu
// item can be that string: every move-target row contains " \u2014 " and the three fixed items are
// the literals Paste / Move to New Window / Close Pane. The argc test also stops a one-target
// menu from tripping it.
//
// THE SPI, AND WHY IT IS CONTAINED. Space membership has no public API. CGSCopyManagedDisplaySpaces
// and CGSCopySpacesForWindows are resolved by dlsym at run time, so their DISAPPEARANCE is a
// checkable NULL (exit 2, DLSYM-MISS) rather than a link error. A WRONG SIGNATURE, by contrast,
// segfaults \u2014 which is exactly why the caller runs this in a bounded subprocess: a crash there is
// a non-zero exit and a dropped label, never a dead menu. The argument order below
// (connection, mask, windowIDs) is the one measured working on macOS 15.7.9, 2026-09-05.
//
// The left-to-right claim is MEASURED, not assumed: captured mid-Space-transition, when the
// windows spread instead of stacking, kCGWindowBounds x-origin against the array index was
// strictly monotone at a uniform 1792 px stride (ord1 x=-5373 \u2192 ord6 x=3587). The Spaces array
// index IS screen order.
// stdout: the title of the picked item, or nothing if dismissed without a pick.
// stderr: `shown=true|false` — NSMenu's own report of whether tracking completed with a selection
//         (diagnostic only; the caller does not trust this to distinguish "cancelled" from "never
//         rendered" — see the wall-clock heuristic in kitty-pane-menu instead).

import Cocoa
import CoreGraphics
import Foundation

final class MenuDelegate: NSObject {
    var picked: String = ""
    @objc func onPick(_ sender: NSMenuItem) {
        picked = sender.title
    }
}

// ── --windows probe mode ────────────────────────────────────────────────────────────────────────
// One TSV row per kitty OS window, and nothing else on stdout:
//     <kCGWindowNumber>\t<displayIndex>\t<ordinal|->\t<onscreen 0|1>\t<kCGWindowName>
// displayIndex/ordinal are 1-based; "-" means the window joined no managed Space (the caller then
// drops the direction clause from EVERY row rather than rendering a half-numbered menu).

private typealias MainConnFn = @convention(c) () -> Int32
private typealias DisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
private typealias SpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

// Compiled into the binary so the CALLER can test for this mode without running it. This is not
// decoration: bin/kitty-pane-menu is a symlink into the checkout and goes live the instant a land
// fast-forwards, while THIS file only reaches ~/.claude/bin when scripts/kitty-setup.sh recompiles
// it. In that window a new caller would hand `--windows` to an OLD binary, which has no such mode
// and would faithfully pop a one-item NSMenu reading "--windows" at the cursor on every
// right-click. A marker the caller greps out of the Mach-O closes that window with no subprocess
// and no timing heuristic.
let PROBE_MARKER = "KPM-WINDOWS-MODE-V1"   // >15 UTF-8 bytes on purpose — see below

private func emitWindows() -> Int32 {
    // Emitted on stderr, which the caller discards — its job is to force the literal into the
    // compiled binary, and TWO things had to be true for that to work, both found by grepping the
    // build rather than by reasoning about it. A bare unused constant does not survive
    // `swiftc -O`, so the marker sits on a live code path. And a Swift string of 15 UTF-8 bytes or
    // fewer is stored INLINE in registers by the small-string optimisation and never reaches the
    // string table at all — the first marker, `KPM-WINDOWS-V1`, was 14 bytes and was absent from
    // the optimised build while being printed correctly at run time. Keep this literal above 15
    // bytes or the caller's capability test silently reads every new binary as old.
    FileHandle.standardError.write("\(PROBE_MARKER)\n".data(using: .utf8)!)
    guard let h = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
          let pConn = dlsym(h, "_CGSDefaultConnection") ?? dlsym(h, "CGSMainConnectionID"),
          let pDisp = dlsym(h, "CGSCopyManagedDisplaySpaces"),
          let pWins = dlsym(h, "CGSCopySpacesForWindows") else {
        FileHandle.standardError.write("DLSYM-MISS\n".data(using: .utf8)!)
        return 2
    }

    // kitty's real OS windows. Layer 0 excludes menus/panels; the height floor drops the
    // 1-pixel helper windows kitty keeps around, which carry no title and no Space of interest.
    guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
        FileHandle.standardError.write("CGWINDOWLIST-NIL\n".data(using: .utf8)!)
        return 1
    }
    var kitty: [(num: Int, name: String, onscreen: Bool)] = []
    for w in list {
        guard (w[kCGWindowOwnerName as String] as? String) == "kitty",
              (w[kCGWindowLayer as String] as? Int) == 0,
              let num = w[kCGWindowNumber as String] as? Int,
              let b = w[kCGWindowBounds as String] as? [String: CGFloat],
              let hgt = b["Height"], hgt > 200 else { continue }
        kitty.append((num,
                      w[kCGWindowName as String] as? String ?? "",
                      (w[kCGWindowIsOnscreen as String] as? Bool) ?? false))
    }

    let conn = unsafeBitCast(pConn, to: MainConnFn.self)()

    // managedSpaceID -> (displayIndex, ordinal). Enumerated PER DISPLAY: a flattened index gives
    // two windows the same ordinal the moment a second display holds Spaces, and this box reports
    // 14 monitor entries.
    var placeOf: [Int: (Int, Int)] = [:]
    let displays = unsafeBitCast(pDisp, to: DisplaySpacesFn.self)(conn)?.takeRetainedValue()
        as? [[String: Any]] ?? []
    for (di, d) in displays.enumerated() {
        for (si, s) in ((d["Spaces"] as? [[String: Any]]) ?? []).enumerated() {
            if let msid = s["ManagedSpaceID"] as? Int { placeOf[msid] = (di + 1, si + 1) }
        }
    }

    // Queried one window at a time so the join is positional-free: a batch call returns a flat
    // array whose correspondence to the input is the thing we would have to assume.
    var out = ""
    for k in kitty.sorted(by: { $0.num < $1.num }) {
        let sids = unsafeBitCast(pWins, to: SpacesForWindowsFn.self)(
            conn, 0x7, [NSNumber(value: k.num)] as CFArray)?.takeRetainedValue() as? [Int] ?? []
        let place = sids.compactMap { placeOf[$0] }.first
        let di = place.map { String($0.0) } ?? "-"
        let ord = place.map { String($0.1) } ?? "-"
        // Tabs and newlines cannot survive the TSV; a window title is free-form and macOS does
        // not forbid either, so they are flattened here rather than trusted not to appear.
        let name = k.name.replacingOccurrences(of: "\t", with: " ")
                         .replacingOccurrences(of: "\n", with: " ")
        out += "\(k.num)\t\(di)\t\(ord)\t\(k.onscreen ? 1 : 0)\t\(name)\n"
    }
    FileHandle.standardOutput.write(out.data(using: .utf8)!)
    return 0
}

if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "--windows" {
    exit(emitWindows())
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.activate(ignoringOtherApps: true)

let args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else {
    FileHandle.standardError.write("kitty-pane-menu-native: no items given\n".data(using: .utf8)!)
    exit(2)
}

let menu = NSMenu()
menu.autoenablesItems = false
let delegate = MenuDelegate()

for title in args {
    let item = NSMenuItem(title: title, action: #selector(MenuDelegate.onPick(_:)), keyEquivalent: "")
    item.target = delegate
    item.isEnabled = true
    menu.addItem(item)
}

let loc = NSEvent.mouseLocation
let shown = menu.popUp(positioning: nil, at: loc, in: nil)
FileHandle.standardError.write("shown=\(shown)\n".data(using: .utf8)!)
print(delegate.picked)
