#!/usr/bin/env bats
# kitty-pane-menu-anchor — WHICH WINDOW THE MENU BELONGS TO.
#
# THE DEFECT (operator report 2026-09-16). Right-click a kitty window on the display above, then
# right-click one below, and the second menu's directions are measured from the FIRST window —
# "not a problem if you left-click before the second right-click". That last clause is the whole
# diagnosis handed over intact: macOS makes a background window key on a LEFT mouse down and not
# on a right one, so a right click on a window the operator had not been typing in changes kitty's
# focus by exactly nothing. bin/kitty-pane-menu anchored on focused_window_id() — kitty's focused
# PANE — so the menu belonged to the window they had left.
#
# IT WAS NEVER ONLY THE CLAUSE, which is why this file exists beside the direction one. The anchor
# also decides which windows are OFFERED (itself is excluded) and which pane Paste / Close Pane /
# the move ACT ON. Measured against the operator's live tree before the fix: right-clicking
# os-window 14 rendered `claude-infrastructure — 2 panes, on the display above` — window 14
# offering ITSELF as a destination, describing itself as being on another display — and omitted the
# window actually below. All three actions aimed at a pane in a different OS window.
#
# THE CURE IS THE POINTER, which is ground truth at the moment of the click: the probe now emits a
# `C` row (pointer, top-left origin, same space as kCGWindowBounds) and one `W` row per kitty
# window (frame + z index, 0 = frontmost), and choose_anchor() hit-tests. A right click lands on
# pixels the operator can SEE, so the frontmost ON-SCREEN window under the pointer is the one they
# clicked — no other window can be in front of it there, or it would have taken the click.
#
# NOTHING HERE TOUCHES A REAL KITTY, A WINDOWSERVER OR A POINTER. Every case drives the pure
# functions over synthetic probe text and synthetic `kitty @ ls` trees.
#
# Every assertion is `[ ]`, `run`+status, or `… || false`. `[[ ]]` and `(( ))` are errexit-EXEMPT
# in bats and are silently DEAD anywhere but a body's last line — that has burned this repo twice.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MENU="$REPO/bin/kitty-pane-menu"
  SWIFT="$REPO/bin/kitty-pane-menu-native.swift"
  [ -f "$MENU" ]
  export PROBE

  # other_targets() → describe_os_window() → _true_cwd() opens ~/.claude/cc-registry/<id>.json.
  # Sandboxed so a case cannot read the operator's real registry and render a label off it.
  HOME="$BATS_TEST_TMPDIR/home"; export HOME
  mkdir -p "$HOME/.claude/cc-registry"
}

kpm() {
  MENU="$MENU" python3 - "$@" <<'PY'
import importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("kpm", os.environ["MENU"])
spec = importlib.util.spec_from_loader("kpm", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
exec(sys.argv[1])
PY
}

# The operator's live layout, as the probe emitted it 2026-09-16: built-in at the origin, the
# external arranged ABOVE (negative y, because CGDisplayBounds' origin is top-left). Three real
# kitty os-windows plus two windows this kitty instance does not own — a 500x500 unnamed helper and
# another --instance-group's probe window, both genuinely live on that box and both in front.
PROBE='D	1	UUID-BUILTIN	0	0	1728	1117	3
D	2	UUID-EXTERNAL	-63	-1050	1680	1050	2
C	1500	900
W	120887	0	0	617	500	500	0
W	120885	1	14	181	1200	728	1
W	119473	2	-63	-1050	1680	1050	0
W	116852	3	0	37	1728	1080	1
W	79048	4	-63	-1050	1680	1050	1
W	75301	5	0	38	1728	961	0
75301	1	1	0	pipeline productivity
79048	2	2	1	claude-infrastructure
116852	1	3	1	CC-backlog drain
119473	2	3	0	mac-bootstrap wave 3'

# Three OS windows, no pane anywhere reading is_focused — the state of EVERY window but the
# frontmost one, and the state the anchor has to work in.
#
# THE SHAPE IS ADVERSARIAL ON PURPOSE. In window 90 the ACTIVE pane is not the first one, and in
# window 14 the ACTIVE tab is not the first one — so `wins[0]` and `tabs[0]`, the fallbacks that
# every one of these selectors ends in, give a DIFFERENT answer from the right one. A fixture
# where the active member is also the first cannot tell the two apart, and a mutant replacing
# is_active with is_focused survived against exactly such a fixture before this was rewritten.
TREE='[{"id": 90, "platform_window_id": 116852,
        "tabs": [{"is_active": true, "is_focused": false,
                  "windows": [{"id": 442, "is_active": false, "is_focused": false,
                               "title": "second pane", "cwd": "/tmp/x"},
                              {"id": 441, "is_active": true, "is_focused": false,
                               "title": "CC-backlog drain", "cwd": "/tmp/x"}]}]},
       {"id": 14, "platform_window_id": 79048,
        "tabs": [{"is_active": false, "is_focused": false,
                  "windows": [{"id": 999, "is_active": true, "is_focused": false,
                               "title": "a tab nobody is on", "cwd": "/tmp/x"}]},
                 {"is_active": true, "is_focused": false,
                  "windows": [{"id": 440, "is_active": true, "is_focused": false,
                               "title": "claude-infrastructure", "cwd": "/tmp/x"}]}]},
       {"id": 91, "platform_window_id": 119473,
        "tabs": [{"is_active": true, "is_focused": false,
                  "windows": [{"id": 910, "is_active": true, "is_focused": false,
                               "title": "mac-bootstrap wave 3", "cwd": "/tmp/x"}]}]}]'

@test "1 parse_hit reads the pointer and the frames, front-to-back" {
  run kpm '
c, f = m.parse_hit(os.environ["PROBE"])
print(c)
print([w["num"] for w in f])
print(f[0]["rect"], f[0]["onscreen"], f[1]["onscreen"])'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "(1500, 900)" ]
  [ "${lines[1]}" = "[120887, 120885, 119473, 116852, 79048, 75301]" ]
  [ "${lines[2]}" = "(0, 617, 500, 500) False True" ]
}

@test "2 window_under takes the FRONTMOST window under the pointer, not merely a containing one" {
  # (400, 400) is inside the foreign instance's window (z 1) AND inside os-window 116852 (z 3).
  # The front one took the click, so it is the answer — this is the whole reason z is emitted.
  run kpm 'c, f = m.parse_hit(os.environ["PROBE"]); print(m.window_under((400, 400), f))'
  [ "$status" -eq 0 ]
  [ "$output" = "120885" ]
}

@test "3 an OFF-SCREEN window whose frame contains the pointer is skipped" {
  # The correctness argument, not tidiness. `.optionAll` enumerates every Space, and a window
  # parked on another desktop keeps the frame it had there: 119473 and 79048 report the IDENTICAL
  # rect and only 79048 is visible. Hit-testing the invisible one names a window nobody clicked.
  run kpm 'c, f = m.parse_hit(os.environ["PROBE"]); print(m.window_under((700, -600), f))'
  [ "$status" -eq 0 ]
  [ "$output" = "79048" ]
}

@test "4 a pointer over no kitty window, and an unreadable pointer, both answer None" {
  run kpm '
c, f = m.parse_hit(os.environ["PROBE"])
print(m.window_under((5000, 5000), f))
print(m.window_under(None, f))
c2, f2 = m.parse_hit(os.environ["PROBE"].replace("C\t1500\t900", "C\t-\t-"))
print(c2, m.window_under(c2, f2))'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "None" ]
  [ "${lines[1]}" = "None" ]
  [ "${lines[2]}" = "None None" ]
}

@test "5 THE DEFECT: the anchor is the window under the pointer, not the focused one" {
  # The red-proof. Focus is pane 441 in os-window 90; the pointer is in os-window 14, on the other
  # display. Pre-fix this returned 90 — and a mutant that restores that (choose_anchor answering
  # the focus branch unconditionally) fails exactly here.
  TREE="$TREE" run kpm '
import json
tree = json.loads(os.environ["TREE"])
probe = os.environ["PROBE"].replace("C\t1500\t900", "C\t700\t-600")
osw, pane, src, pwid = m.choose_anchor(tree, probe, 441)
print(osw, pane, src, pwid)
assert osw == 14, "anchored on the FOCUSED window, not the clicked one"
assert pane == 440, "aimed Paste/Close Pane at a pane in another OS window"'
  [ "$status" -eq 0 ]
  [ "$output" = "14 440 cursor 79048" ]
}

@test "6 the pane it picks is is_active, because is_focused is False in every non-frontmost window" {
  TREE="$TREE" run kpm '
import json
tree = json.loads(os.environ["TREE"])
osw = [o for o in tree if o["id"] == 90][0]
print(m.active_window_id(osw))
print(m.active_window_id(None))
print(m.active_window_id({"id": 7, "tabs": []}))'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "441" ]
  [ "${lines[1]}" = "None" ]
  [ "${lines[2]}" = "None" ]
}

@test "7 a pointer over a window THIS kitty does not own falls back to focus" {
  # 120885 is another --instance-group's window and is in no tree this socket can produce. Real
  # state on the box the fix was measured on, and the fallback must be the old behaviour, not None.
  TREE="$TREE" run kpm '
import json
tree = json.loads(os.environ["TREE"])
probe = os.environ["PROBE"].replace("C\t1500\t900", "C\t400\t400")
print(m.choose_anchor(tree, probe, 441))'
  [ "$status" -eq 0 ]
  [ "$output" = "(90, 441, 'focus', 120885)" ]
}

@test "8 a helper that predates the pointer rows degrades to focus, not to nothing" {
  # The compiled probe only moves on kitty-setup.sh --apply while this caller is a symlink that
  # goes live on a land, so "new caller, old binary" is a real state. No C/W rows at all.
  TREE="$TREE" run kpm '
import json
tree = json.loads(os.environ["TREE"])
old = "\n".join(l for l in os.environ["PROBE"].splitlines()
                if not l.startswith("C\t") and not l.startswith("W\t"))
print(m.choose_anchor(tree, old, 441))
print(m.choose_anchor(tree, old, None))'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "(90, 441, 'focus', None)" ]
  [ "${lines[1]}" = "(None, None, 'focus', None)" ]
}

@test "9 pointer inside the focused window: the two anchors AGREE" {
  # The common single-window case, and the one that proves the change is not a rewrite of the
  # normal path — with the pointer where the focus is, the answer is what it always was.
  TREE="$TREE" run kpm '
import json
tree = json.loads(os.environ["TREE"])
osw, pane, src, _p = m.choose_anchor(tree, os.environ["PROBE"], 441)
print(osw, pane, src)
print(m.owning_os_window_id(tree, 441))'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "90 441 cursor" ]
  [ "${lines[1]}" = "90" ]
}

@test "10 END TO END: the menu the operator saw, against the menu the click deserved" {
  # Both halves of the defect in one rendering. The stale anchor offers the clicked window ITSELF
  # (`claude-infrastructure`) and calls it "on the display above" — from the clicked window, the
  # remaining two are below and beside. Nothing here asserts on a count; the strings are the bug.
  TREE="$TREE" run kpm '
import json
tree = json.loads(os.environ["TREE"])
p, n, d = m.parse_probe(os.environ["PROBE"])
for tag, anchor in (("stale", 90), ("clicked", 14)):
    for _w, label, _s in m.other_targets(tree, anchor, p, n, True, d):
        print(tag, "|", label)'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "stale | claude-infrastructure — 2 panes in 2 tabs, on the display above" ]
  [ "${lines[1]}" = "stale | mac-bootstrap wave 3 — 1 pane, on the display above, 1 desktop right" ]
  [ "${lines[2]}" = "clicked | CC-backlog drain — 2 panes, on the display below" ]
  [ "${lines[3]}" = "clicked | mac-bootstrap wave 3 — 1 pane, 1 desktop right" ]
}

@test "11 the new row kinds are invisible to parse_probe, so an OLD caller still parses them" {
  # The other skew direction: a NEW binary under an OLD caller. `C` and `W` rows must fall out of
  # parse_probe's window scan, or the old menu grows two junk rows on every right-click.
  run kpm '
p, n, d = m.parse_probe(os.environ["PROBE"])
print(len(p), len(n), len(d))
print(sorted(n))'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "4 4 2" ]
  [ "${lines[1]}" = "[75301, 79048, 116852, 119473]" ]
}

@test "12 the caller's capability marker is the literal the probe compiles in" {
  # A marker that drifts between the two files reads every new binary as old, silently and
  # permanently — and this one gates the anchor, so the drift restores the bug with no symptom.
  [ -f "$SWIFT" ]
  run grep -c 'let CURSOR_MARKER = "KPM-CURSOR-HIT-V1"' "$SWIFT"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  run grep -c '_CURSOR_MARKER = b"KPM-CURSOR-HIT-V1"' "$MENU"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  # >15 UTF-8 bytes or swiftc's small-string optimisation keeps it out of the string table and the
  # caller's grep never finds it — the exact failure the first marker shipped with.
  run python3 -c 'print(len("KPM-CURSOR-HIT-V1".encode()))'
  [ "$output" = "17" ]
}
