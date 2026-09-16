// draghold — a synthetic CGEvent mouse-drag driver for testing kitty window drags.
//
// PROVENANCE. This is the driver referenced at
//   docs/research/kitty-pane-title-overlay-2026-09-14.md § I9
//   docs/research/kitty-drag-action-implementation-2026-09-16.md § 6.4 item 3
// Phase-1 § 6.4 recorded it as "no longer exists in the repo". It was never IN the repo —
// `git log --all --diff-filter=A -- '*draghold*'` returns NOTHING and
// `git log --all -S'CGEventCreateMouseEvent'` returns zero commits on any branch — but the
// ORIGINAL SOURCE survived in a per-session scratchpad and is preserved byte-identical beside
// this file as draghold-original.c (sha256 4a43327b652af4a7f9ab315c8b3b8361547fe5108e7beb82
// aa71658b174f8402, verified against the hash recorded independently in the Q18 probe).
// This file is that original with the EVENT LOOP UNCHANGED — identical event order, identical
// timings, identical argv contract, so every recovered harness drives it without edit — plus
// a --help / --dry-run / --check surface so it can be verified without moving a real cursor.
//
// THE TIMINGS ARE KNOWN-GOOD. KEEP THEM. WHY THEY WORK IS UNMEASURED.
//   250 ms hover before press   120 ms press dwell   12 ms between every posted event
//   40 motion steps by default (the harnesses pass 120)   explicit hold before mouse-up
// A run under these timings started a real drag: a mid-drag capture showed kitty's drag
// thumbnail and its green drop-target line, and three drags reordered panes under a
// `move_window` control passing in the same run (§ I9's four-row table; see README.md).
// 🚨 Do NOT re-derive these from § I9's sentence that the predecessor "warps, presses, moves
// and releases in milliseconds". That sentence is REFUTED by a side-by-side read of the
// predecessor `drag.m`: it does NO warp, hovers 120 ms, and its press dwell is 160 ms —
// LONGER than this driver's 120 ms — over ~1.02 s total. The real deltas are the WARP and the
// HOLD, not slowness, and WHICH delta makes the drag start has never been isolated (that
// needs a warp-vs-no-warp A/B at fixed aim, firing real events at a sandbox kitty). Keep the
// timings because they are known-good; do not spend a session tuning dwell on a false story.
// § I11 of the same file withdraws that whole line of investigation: the drag was never
// broken. The documented lever that demonstrably WAS wrong is the AIM (§ I9 item 2).
//
// COORDINATE SPACE. CGEvent global display coordinates: POINTS (not device pixels), origin
// TOP-LEFT of the main display. The recovered harnesses take x/y from System Events
// ("get {position, size} of window 1"), which is the same space — do not mix in a
// screencapture pixel row without dividing by the backing-scale factor first.
//
// MOUSE BUTTON. kCGMouseButtonLeft + kCGEventLeftMouse{Down,Dragged,Up} is the CoreGraphics
// numbering and is self-consistent. It is NOT the GLFW numbering (LEFT=0 RIGHT=1 MIDDLE=2)
// and NOT kitty's mouse_button_map b1/b2/b3 strings; those two traps live on the kitty side
// of the boundary, not here.
//
// PERMISSION. Posting to kCGHIDEventTap requires Accessibility permission, and macOS grants
// it to the PARENT application (the terminal/app that launched this), not to this binary. If
// the parent is untrusted the posts are silently dropped and the run looks exactly like "the
// drag did not start" — the same false negative that cost §§ I7-I8, at a third level.
// `--check` reports the grant so that becomes a stated verdict before the run rather than an
// ambiguity after it. 🚨 Its CANNOT-POST branch is written but UNEXERCISED (no untrusted
// parent was available); a session that sees CANNOT-POST should confirm the branch.
//
// BUILD:  ./build.sh      (or: clang -O2 -Wall -Wextra -o draghold draghold.c \
//                                 -framework ApplicationServices)
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

static int DRY = 0;

static void post(CGEventType t, CGPoint p) {
    const char *n = t == kCGEventMouseMoved      ? "MouseMoved"
                  : t == kCGEventLeftMouseDown   ? "LeftMouseDown"
                  : t == kCGEventLeftMouseDragged? "LeftMouseDragged"
                  : t == kCGEventLeftMouseUp     ? "LeftMouseUp" : "?";
    if (DRY) { fprintf(stderr, "  [dry] %-17s (%.1f, %.1f)  +12ms\n", n, p.x, p.y); return; }
    CGEventRef e = CGEventCreateMouseEvent(NULL, t, p, kCGMouseButtonLeft);
    CGEventPost(kCGHIDEventTap, e); CFRelease(e); usleep(12000);
}

static void nap(unsigned us, const char *why) {
    if (DRY) { fprintf(stderr, "  [dry] sleep %-11u us  (%s)\n", us, why); return; }
    usleep(us);
}

static int usage(int rc) {
    fprintf(stderr,
"usage: draghold x1 y1 x2 y2 hold_ms [steps]\n"
"       draghold --dry-run x1 y1 x2 y2 hold_ms [steps]   print the event plan, post NOTHING\n"
"       draghold --check                                  report Accessibility grant, post NOTHING\n"
"       draghold --help\n"
"\n"
"Drags the left mouse button from (x1,y1) to (x2,y2) slowly enough for kitty to begin a\n"
"window drag, HOLDS at the target for hold_ms so the screen can be photographed mid-drag,\n"
"then releases. Coordinates are CGEvent global display POINTS, origin top-left.\n"
"\n"
"Fixed timings (known-good, do not tune): 250ms hover, 120ms press dwell, 12ms per event.\n"
"Recovered working invocation: ... 400 120   (reorder)   ... 3000 120   (mid-drag capture)\n"
"Note steps=120, three times the built-in default of 40.\n"
"\n"
"WARNING: this MOVES THE REAL CURSOR and posts to the system-wide HID event tap. It is not\n"
"scoped to one application. Never run it while someone is using the machine.\n");
    return rc;
}

int main(int argc, char **argv) {
    if (argc > 1 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h"))) return usage(0);

    if (argc > 1 && !strcmp(argv[1], "--check")) {
        // Negative control for the whole instrument: if this is false, every posted event is
        // silently dropped and the run is indistinguishable from "kitty ignored the drag".
        int trusted = AXIsProcessTrusted();
        CGDirectDisplayID d = CGMainDisplayID();
        fprintf(stderr, "accessibility_trusted=%s\n", trusted ? "YES" : "NO");
        fprintf(stderr, "main_display_points=%zux%zu\n",
                CGDisplayPixelsWide(d), CGDisplayPixelsHigh(d));
        CGEventRef probe = CGEventCreate(NULL);            // read cursor without moving it
        CGPoint c = CGEventGetLocation(probe); CFRelease(probe);
        fprintf(stderr, "cursor_now=(%.1f, %.1f)\n", c.x, c.y);
        fprintf(stderr, "verdict=%s\n", trusted ? "CAN-POST" : "CANNOT-POST-events-will-be-dropped");
        return trusted ? 0 : 1;
    }

    int a = 1;
    if (argc > 1 && !strcmp(argv[1], "--dry-run")) { DRY = 1; a = 2; }
    if (argc - a < 5) return usage(2);

    double x1 = atof(argv[a]), y1 = atof(argv[a+1]),
           x2 = atof(argv[a+2]), y2 = atof(argv[a+3]);
    int hold  = atoi(argv[a+4]);
    int steps = (argc - a > 5) ? atoi(argv[a+5]) : 40;
    if (steps < 1) steps = 1;

    fprintf(stderr, "draghold%s (%.1f,%.1f) -> (%.1f,%.1f) hold=%dms steps=%d\n",
            DRY ? " --dry-run" : "", x1, y1, x2, y2, hold, steps);
    if (DRY) fprintf(stderr, "  [dry] warp cursor  (%.1f, %.1f)\n", x1, y1);
    else CGWarpMouseCursorPosition(CGPointMake(x1, y1));

    post(kCGEventMouseMoved, CGPointMake(x1, y1));
    nap(250000, "hover: let kitty hit-test the region under the cursor");
    post(kCGEventLeftMouseDown, CGPointMake(x1, y1));
    nap(120000, "press dwell");

    for (int i = 1; i <= steps; i++) {
        double f = (double)i / steps;
        post(kCGEventLeftMouseDragged,
             CGPointMake(x1 + (x2 - x1) * f, y1 + (y2 - y1) * f));
    }

    fprintf(stderr, "held at target, %d ms\n", hold);
    nap((unsigned)hold * 1000, "hold at target: capture the drag thumbnail here");
    post(kCGEventLeftMouseUp, CGPointMake(x2, y2));
    if (DRY) fprintf(stderr, "  [dry] posted 0 events\n");
    return 0;
}
