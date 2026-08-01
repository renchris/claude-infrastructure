// window-rect.swift — print the on-screen RECT of one window, so a screen capture can be scoped to
// it without ever moving it.
//
// WHY THIS EXISTS. Filming a terminal under test needs `screencapture -R x,y,w,h` (`-l<window-id>`
// does NOT scope a VIDEO capture — it silently films the whole display, which is how a take once
// recorded the operator's desktop). Producing that rect the obvious way — System Events `set
// position of window 1` — needs the Accessibility grant, and on this box `osascript is not allowed
// assistive access` (-1728). It also targets `window 1`, i.e. whatever is frontmost, which on a
// machine already running the subject app can be the OPERATOR'S OWN live window.
//
// So instead of MOVING a window to a known rect, read the rect of the window we already know is
// ours. `CGWindowListCopyWindowInfo` needs no Accessibility grant, and it can be scoped by owner
// AND by title, which is what makes "never film the operator's session" enforceable rather than
// hoped-for.
//
// 🚨 TITLE MATCHING IS THE SAFETY PROPERTY, not a convenience. kCGWindowName is the one field that
// requires the Screen Recording grant; without it the field is ABSENT, and an absent title must
// never silently match. A `--title` that matches nothing exits 4 with verdict=NO-MATCH rather than
// falling back to "the first window of that app" — the fallback would film a live session.
//
// 🚨 AND THE RECT IS NOT ENOUGH — `--assert-unoccluded` is the second half of the same safety
// property. `screencapture -R` films whatever is ON SCREEN at that rect, not the window that owns
// it. Measured while building this: the film window's rect was correct to the pixel and a BROWSER
// sat on top of it, so the still came back showing the operator's home address, their mail client
// and their open tabs. Nothing errored; the rect was right; the film would have been of somebody
// else's window. So Z-order is checked directly — CGWindowList returns onscreen windows FRONT TO
// BACK, so anything listed before ours that intersects our rect is on top of it, and that is a
// refusal, not a warning.
//
// USAGE
//   swift window-rect.swift --owner kitty --title CCFILM
//   swift window-rect.swift --owner Ghostty --window-id 12345
//   swift window-rect.swift --owner WezTerm --largest
//   swift window-rect.swift --owner kitty --title CCFILM --assert-unoccluded
// PRINTS (one line, then verdict):
//   rect=x,y,w,h  owner=<name> pid=<n> wid=<n> title=<...>
//   verdict=OK | NO-MATCH | AMBIGUOUS | OCCLUDED | NO-DATA
// EXIT: 0 OK · 3 NO-DATA (list unavailable) · 4 NO-MATCH · 5 AMBIGUOUS (>1 match, no --largest)
//       6 OCCLUDED (another window covers part of the rect — do NOT film)

import Foundation
import CoreGraphics

var owner: String?
var titleNeedle: String?
var wantWindowID: Int?
var pickLargest = false
var assertUnoccluded = false
// A window may not cover more than this fraction of the rect before the take is refused. It is not
// zero: macOS reports a few 1-2 px system layers (and some apps' own drop-shadow helpers) that
// clip the very edge of a rect while painting nothing into it. 0.2% of a 1280x748 rect is ~1,900
// px² — about a 44x44 corner — which no real window can hide behind.
let occlusionTolerance = 0.002

var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--owner":     owner = args.isEmpty ? nil : args.removeFirst()
    case "--title":     titleNeedle = args.isEmpty ? nil : args.removeFirst()
    case "--window-id": wantWindowID = args.isEmpty ? nil : Int(args.removeFirst())
    case "--largest":   pickLargest = true
    case "--assert-unoccluded": assertUnoccluded = true
    case "-h", "--help":
        print("usage: window-rect.swift --owner <app> [--title <substr>] [--window-id <n>] [--largest]")
        exit(0)
    default:
        FileHandle.standardError.write("window-rect: unknown arg \(a)\n".data(using: .utf8)!)
        exit(2)
    }
}
guard let ownerName = owner else {
    FileHandle.standardError.write("window-rect: --owner is required\n".data(using: .utf8)!)
    exit(2)
}

// .optionOnScreenOnly: an offscreen window has stale bounds and cannot be filmed anyway.
// .excludeDesktopElements: drops the wallpaper/Dock layer so a match is a real application window.
let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
    print("verdict=NO-DATA")
    exit(3)
}

struct Hit {
    let x: Int, y: Int, w: Int, h: Int
    let pid: Int, wid: Int, title: String
    var area: Int { w * h }
}

var hits: [Hit] = []
for win in raw {
    let thisOwner = (win[kCGWindowOwnerName as String] as? String) ?? ""
    guard thisOwner.caseInsensitiveCompare(ownerName) == .orderedSame else { continue }

    // Layer 0 is the normal window layer. Anything else is a panel, HUD, menu or shadow helper —
    // filming one of those would produce a rect that is not the terminal.
    let layer = (win[kCGWindowLayer as String] as? Int) ?? -1
    guard layer == 0 else { continue }

    guard let b = win[kCGWindowBounds as String] as? [String: Any],
          let x = b["X"] as? Double, let y = b["Y"] as? Double,
          let w = b["Width"] as? Double, let h = b["Height"] as? Double,
          w > 1, h > 1 else { continue }

    let wid = (win[kCGWindowNumber as String] as? Int) ?? -1
    let pid = (win[kCGWindowOwnerPID as String] as? Int) ?? -1
    // ABSENT, not empty, when the Screen Recording grant is missing — see the header. An absent
    // title can never satisfy --title, which is deliberate.
    let title = (win[kCGWindowName as String] as? String) ?? ""

    if let wantID = wantWindowID, wid != wantID { continue }
    if let needle = titleNeedle {
        guard title.range(of: needle, options: .caseInsensitive) != nil else { continue }
    }
    hits.append(Hit(x: Int(x), y: Int(y), w: Int(w), h: Int(h), pid: pid, wid: wid, title: title))
}

if hits.isEmpty {
    // Say WHY there is no match, because the two causes need opposite fixes: the app not running vs
    // the title filter (or a missing Screen Recording grant hiding every title).
    let ownerWindows = raw.filter {
        (($0[kCGWindowOwnerName as String] as? String) ?? "")
            .caseInsensitiveCompare(ownerName) == .orderedSame
    }.count
    let titled = raw.filter { $0[kCGWindowName as String] != nil }.count
    print("verdict=NO-MATCH owner_windows=\(ownerWindows) titled_windows_on_screen=\(titled)")
    exit(4)
}

if hits.count > 1 && !pickLargest {
    for h in hits { print("candidate rect=\(h.x),\(h.y),\(h.w),\(h.h) wid=\(h.wid) title=\(h.title)") }
    print("verdict=AMBIGUOUS matches=\(hits.count)")
    exit(5)
}

let pick = pickLargest ? hits.max(by: { $0.area < $1.area })! : hits[0]
print("rect=\(pick.x),\(pick.y),\(pick.w),\(pick.h)  owner=\(ownerName) pid=\(pick.pid) wid=\(pick.wid) title=\(pick.title)")

if assertUnoccluded {
    // `raw` is front-to-back, so every entry BEFORE ours is drawn on top of it. Windows of our own
    // pid are excluded: a terminal's own tab bar / shadow / titlebar helper legitimately overlaps
    // its frame and is part of what we are filming.
    let ourRect = CGRect(x: pick.x, y: pick.y, width: pick.w, height: pick.h)
    let ourArea = Double(pick.w * pick.h)
    var offenders: [(String, Double)] = []
    // Size of the display our window sits on — the yardstick for "full-display system surface".
    let screen = CGDisplayBounds(CGMainDisplayID())
    let displayW = Int(screen.width), displayH = Int(screen.height)

    for win in raw {
        let wid = (win[kCGWindowNumber as String] as? Int) ?? -1
        if wid == pick.wid { break }                       // reached ours — everything after is behind
        let pid = (win[kCGWindowOwnerPID as String] as? Int) ?? -1
        if pid == pick.pid { continue }
        guard let b = win[kCGWindowBounds as String] as? [String: Any],
              let x = b["X"] as? Double, let y = b["Y"] as? Double,
              let w = b["Width"] as? Double, let h = b["Height"] as? Double else { continue }
        let name = (win[kCGWindowOwnerName as String] as? String) ?? "(unknown)"

        // SYSTEM COMPOSITING SURFACES ARE NOT OCCLUDERS. `Dock` publishes one window the size of the
        // WHOLE display (measured: 0,0,1728,1117 at layer 20) and `Window Server` publishes the
        // menubar backdrop the same way. Neither paints into the middle of the screen, but a purely
        // geometric test scores both at 100% coverage of every rect — which would make this gate
        // refuse every take on every machine, i.e. an alarm that always fires and therefore carries
        // no information. They are skipped ONLY at full-display size: a Dock window of ordinary size
        // is a real window and still counts.
        // "Notification Center" belongs here for the same reason as the Dock: it publishes a
        // full-display backdrop that paints nothing. Its actual banners are SMALL windows and are
        // still caught — which matters, because a banner carrying live session ids once landed in
        // frame on this machine.
        let isSystemChrome = (name == "Dock" || name == "Window Server" || name == "Notification Center")
        if isSystemChrome, w >= Double(displayW) * 0.98, h >= Double(displayH) * 0.98 { continue }

        let inter = CGRect(x: x, y: y, width: w, height: h).intersection(ourRect)
        if inter.isNull || inter.isEmpty { continue }
        let frac = Double(inter.width * inter.height) / ourArea
        if frac > occlusionTolerance {
            let name = (win[kCGWindowOwnerName as String] as? String) ?? "(unknown)"
            offenders.append((name, frac))
        }
    }

    if !offenders.isEmpty {
        // Name the app and how much of the frame it holds. "Something is on top" is not actionable;
        // "Dia covers 78% of the rect" tells the operator exactly which window to move.
        for (name, frac) in offenders {
            print(String(format: "occluder=%@ covers=%.1f%% of rect", name, frac * 100))
        }
        print("verdict=OCCLUDED occluders=\(offenders.count)")
        exit(6)
    }
}

print("verdict=OK")
exit(0)
