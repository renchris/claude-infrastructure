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
// stdout: the title of the picked item, or nothing if dismissed without a pick.
// stderr: `shown=true|false` — NSMenu's own report of whether tracking completed with a selection
//         (diagnostic only; the caller does not trust this to distinguish "cancelled" from "never
//         rendered" — see the wall-clock heuristic in kitty-pane-menu instead).

import Cocoa

final class MenuDelegate: NSObject {
    var picked: String = ""
    @objc func onPick(_ sender: NSMenuItem) {
        picked = sender.title
    }
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
