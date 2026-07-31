// window-census.swift — count what WindowServer actually tracks, per application.
//
// WHY THIS EXISTS. The 2026-07-30 freeze was WindowServer-side: it saturated a full core with a
// monotonically growing mach-port table while iTerm2 itself measured 0.0% CPU. The proximate defect
// was a population of 98 iTerm2 window OBJECTS that were invisible, held zero tabs, and survived
// close(). Window-object count was invisible to every existing headroom / swap / pressure rung.
// (docs/research/iterm2-freeze-30-sessions-2026-07-30.md §2-§3.)
//
// WHY NOT APPLESCRIPT. The prior investigation counted those windows with `tell application "iTerm2"`.
// That instrument has two disqualifying properties for comparing TERMINALS:
//   1. It is iTerm2-specific. Ghostty, WezTerm, kitty and Alacritty expose no equivalent dictionary,
//      so an AppleScript census cannot compare the thing we are trying to choose between.
//   2. It perturbs its subject. Enumerating ~100 windows over Apple events was measured contributing
//      up to 18% of the CoreAnimation defer-lock storm it was trying to observe.
// CGWindowListCopyWindowInfo reads the window server's own list. It is app-agnostic, needs no
// Accessibility or Screen Recording grant (we never request kCGWindowName, which is the only
// permission-gated field), sends no Apple events, and costs one call.
//
// WHAT IT MEASURES, and why each column is the one that matters here:
//   windows        every window the server tracks for that owner, ON- AND OFF-SCREEN. The 98 zombies
//                  were all offscreen, so an onscreen-only count would have reported zero and
//                  exonerated the actual defect.
//   offscreen      the zombie axis directly. A terminal whose pane churn leaks window objects shows
//                  a rising offscreen count while its visible layout is unchanged.
//   zeroArea       degenerate windows (w*h == 0). Free-standing evidence of leaked shells rather
//                  than legitimate hidden panels.
//   megapixels     summed w*h over ONSCREEN windows. WindowServer's compositing cost tracks surface
//                  AREA as well as surface COUNT, so a count without an area denominator would rank
//                  a tiled 30-pane window equal to a 30-window cascade.
//   layers         count of distinct CGWindowLayer values — separates real document windows (layer 0)
//                  from panels, tooltips and shadows that are cheap.
//
// 🚨 CALIBRATION — A SINGLE READING CANNOT CONVICT, AND `offscreen` IS NOT A LEAK SIGNAL.
// Measured on this box 2026-07-31, 7.5 h after the iTerm2 restart that cleared 98 zombies:
//     iTerm2 21 win / 17 offscreen        Finder 21 / 20        Terminal 20 / 18
//     Cursor 22 / 22                      Console 17 / 17       Script Editor 16 / 16
// EVERY app carries a large offscreen population. Offscreen is the ordinary resting state of a
// macOS window, not evidence of a leak, and iTerm2's share of it is unremarkable against Finder's.
// Reading "17 offscreen" as "17 zombies" would have manufactured a defect out of the baseline —
// the denominator error recorded in memory positive-control-the-denominator.
// Note also that this tool CANNOT see the specific property that defined the 98 zombies (an iTerm2
// window holding zero TABS); tabs are an application concept invisible to the window server, and
// those windows had ordinary non-zero bounds so `zeroArea` does not catch them either.
// ⇒ THE LEAK INSTRUMENT IS DRIFT, NOT LEVEL: take two readings separated by a known interval with
//   the visible layout held CONSTANT, and attribute only the growth. That is what
//   scripts/terminal-bench.sh does, and it is the only reading of this tool that supports a verdict
//   about leaking. Cross-app comparison at an EQUAL pane count is the other valid use.
//
// EXIT CODES / VERDICT. Prints a machine-parsable `verdict=` token on the last line, because a
// consumer must be able to distinguish "measured, zero found" from "the instrument did not run".
// A bare 0 returned by a broken instrument reading as a clean bill of health is the failure mode
// recorded in memory positive-control-the-denominator, so:
//   verdict=OK       the window list was returned and parsed  (exit 0)
//   verdict=NO-DATA  the window list was nil or empty         (exit 3)
// An empty list is NO-DATA rather than "0 windows" on purpose: a logged-in Mac always has windows,
// so an empty result means the call failed, not that the desktop is bare.
//
// USAGE
//   swift window-census.swift                 # all owners, human table
//   swift window-census.swift --tsv           # all owners, tab-separated (owner pid windows …)
//   swift window-census.swift --owner iTerm2  # one owner, still prints the desktop total
// Compile once for repeated use (interpreted start-up is ~0.4 s, which matters in a sample loop):
//   swiftc -O window-census.swift -o window-census

import Foundation
import CoreGraphics

struct OwnerStats {
    var pid: Int = 0
    var windows: Int = 0
    var onscreen: Int = 0
    var offscreen: Int = 0
    var zeroArea: Int = 0
    var pixels: Double = 0          // onscreen only
    var layers: Set<Int> = []
}

let args = CommandLine.arguments
let wantTSV = args.contains("--tsv")
var ownerFilter: String? = nil
if let i = args.firstIndex(of: "--owner"), i + 1 < args.count { ownerFilter = args[i + 1] }

// .optionAll = every window the server knows about, including windows that are not on screen.
// Restricting to .optionOnScreenOnly here would structurally hide the exact defect this tool exists
// to catch, so the option is deliberately not configurable.
guard let raw = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]],
      !raw.isEmpty else {
    FileHandle.standardError.write("window-census: CGWindowListCopyWindowInfo returned no data\n".data(using: .utf8)!)
    print("verdict=NO-DATA")
    exit(3)
}

var byOwner: [String: OwnerStats] = [:]

for w in raw {
    let owner = (w[kCGWindowOwnerName as String] as? String) ?? "(unknown)"
    var s = byOwner[owner] ?? OwnerStats()

    s.pid = (w[kCGWindowOwnerPID as String] as? Int) ?? s.pid
    s.windows += 1
    if let layer = w[kCGWindowLayer as String] as? Int { s.layers.insert(layer) }

    // kCGWindowIsOnscreen is ABSENT (not false) for offscreen windows — treat missing as offscreen.
    let onscreen = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
    var area = 0.0
    if let b = w[kCGWindowBounds as String] as? [String: Any],
       let width = b["Width"] as? Double, let height = b["Height"] as? Double {
        area = width * height
    }
    if area == 0 { s.zeroArea += 1 }
    if onscreen { s.onscreen += 1; s.pixels += area } else { s.offscreen += 1 }

    byOwner[owner] = s
}

let totalWindows = byOwner.values.reduce(0) { $0 + $1.windows }
let totalOffscreen = byOwner.values.reduce(0) { $0 + $1.offscreen }
let totalMpx = byOwner.values.reduce(0.0) { $0 + $1.pixels } / 1_000_000

func row(_ name: String, _ s: OwnerStats) -> String {
    let mpx = s.pixels / 1_000_000
    if wantTSV {
        return "\(name)\t\(s.pid)\t\(s.windows)\t\(s.onscreen)\t\(s.offscreen)\t\(s.zeroArea)\t\(String(format: "%.2f", mpx))\t\(s.layers.count)"
    }
    return String(format: "  %-24s pid=%-7d win=%-5d on=%-5d off=%-5d zeroArea=%-5d %6.2f Mpx  layers=%d",
                  (name as NSString).utf8String!, s.pid, s.windows, s.onscreen, s.offscreen,
                  s.zeroArea, mpx, s.layers.count)
}

if wantTSV { print("owner\tpid\twindows\tonscreen\toffscreen\tzeroArea\tonscreenMpx\tlayers") }
else { print("window-census — \(totalWindows) windows tracked, \(totalOffscreen) offscreen, \(String(format: "%.1f", totalMpx)) Mpx onscreen") }

// Sorted by window count: the leaker sorts itself to the top, which is the whole point.
for (name, s) in byOwner.sorted(by: { $0.value.windows > $1.value.windows }) {
    if let f = ownerFilter, name != f { continue }
    if !wantTSV && ownerFilter == nil && s.windows < 2 { continue }   // trim single-window noise
    print(row(name, s))
}

if ownerFilter != nil && byOwner[ownerFilter!] == nil {
    // An absent owner is a real answer (the app is not running) and must not read as a clean zero.
    FileHandle.standardError.write("window-census: owner '\(ownerFilter!)' has no windows tracked\n".data(using: .utf8)!)
    print("verdict=NO-DATA")
    exit(3)
}

print("verdict=OK")
