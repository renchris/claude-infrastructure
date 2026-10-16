#!/usr/bin/env bats
# kitty-fullscreen-guard — the last gate before anything empties a kitty OS window.
#
# THE INCIDENT (docs/research/kitty-crash-2026-10-15/README.md § Chosen fix). Destroying the last
# pane of a native-fullscreen kitty window closes the NSWindow while AppKit still holds it in
# fullscreen (32 of 32 unguarded repro destroys); on 2026-10-15 that state segfaulted kitty and
# took 18 sessions with it. The guard decides "safe to empty NOW" from three facts: whether the
# removal empties the OS window (the kitten), the CGS Space type of that window (FS / WINDOWED /
# UNKNOWN), and TIME — the Space type is not a transition detector, so "windowed" counts only after
# it has held 1.0 s, longer than the longest transition measured (0.90 s).
#
# HOW: the decision runs in-process with the guard's three seams replaced — kitten_query (the
# kitty side), read_window_state (the CGS read) and _now/_sleep (a fake clock that advances only
# when the guard sleeps). The CLI cases run the real executable against a fake `kitty` and a fake
# `osascript` on PATH. NOTHING HERE TALKS TO A REAL KITTY: KITTY_LISTEN_ON/KITTY_WINDOW_ID are
# unset, and CC_TERM_KITTY names the fake.
#
# RED-proof: the guard did not exist before this change (every case fails on a missing file). Cases
# 11 and 18 were re-proven RED against the first draft (immediate undo; `action --self` --then),
# which the 2026-10-15 review (wf_bf440f65-940) showed kitty mis-targets. The stability gate's own
# control is case 16: with STABLE_S forced to 0, the enter-animation case (5)
# and the half-second-windowed case (10) return 0, which is the regression these cases catch.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export GUARD="$REPO/bin/kitty-fullscreen-guard" KITTEN="$REPO/lib/kitty-fs-kitten.py"
  [ -f "$GUARD" ]; [ -f "$KITTEN" ]
  unset KITTY_LISTEN_ON KITTY_WINDOW_ID KITTY_PID CC_KITTY_FS_GUARD
  HOME="$BATS_TEST_TMPDIR/home"; export HOME; mkdir -p "$HOME"
  export CC_KITTY_PANE_ACTIONS_LOG="$BATS_TEST_TMPDIR/actions.jsonl"
  # the policy file and the per-process fsfix cache (guard docstring § RELAX / § POLICY)
  export CC_KITTY_FS_GUARD_STATE_DIR="$BATS_TEST_TMPDIR/fs-guard-state"
  export CALLS="$BATS_TEST_TMPDIR/calls.log"; : >"$CALLS"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  # kitty: logs argv + KITTY_WINDOW_ID; `kitten` answers $KFG_KITTEN_OUT on stdout with rc
  # $KFG_KITTEN_RC (stderr $KFG_KITTEN_ERR); everything else rc 0.
  cat >"$STUBS/kitty" <<'SH'
#!/bin/sh
n=$(grep -c '"phase":"verdict"' "$CC_KITTY_PANE_ACTIONS_LOG" 2>/dev/null || true)
echo "kitty $* [KITTY_WINDOW_ID=${KITTY_WINDOW_ID:-}] [verdicts=${n:-0}]" >>"$CALLS"
case " $* " in
  *" act "*) d='{"wid":7,"acted":true}'; printf '%s\n' "${KFG_ACT_OUT:-$d}"; exit 0 ;;
  *" kitten "*) [ -n "$KFG_KITTEN_ERR" ] && echo "$KFG_KITTEN_ERR" >&2
               printf '%s\n' "$KFG_KITTEN_OUT"; exit "${KFG_KITTEN_RC:-0}" ;;
esac
exit 0
SH
  cat >"$STUBS/osascript" <<'SH'
#!/bin/sh
echo "osascript $*" >>"$CALLS"
exit 0
SH
  chmod +x "$STUBS/kitty" "$STUBS/osascript"
  export PATH="$STUBS:$PATH" CC_TERM_KITTY="$STUBS/kitty"
  # The in-process harness: load the guard, script its seams, print one result line.
  cat >"$BATS_TEST_TMPDIR/h.py" <<'PY'
import importlib.machinery as m, importlib.util as u, os, sys
l = m.SourceFileLoader("g", os.environ["GUARD"]); s = u.spec_from_loader("g", l)
g = u.module_from_spec(s); l.exec_module(g)
clock = [0.0]; reads = []; toggles = []
g._now = lambda: clock[0]
def _sleep(d): clock[0] = round(clock[0] + d, 6)
g._sleep = _sleep
def W(b=(0.0, 0.0, 800.0, 600.0)): return g.WindowState("WINDOWED", [0], True, b)
FS = g.WindowState("FS", [4], True, (0.0, 0.0, 2560.0, 1440.0))
FS_BG = g.WindowState("FS", [4], False, (0.0, 0.0, 2560.0, 1440.0))
UNK = g.WindowState("UNKNOWN", None, None, None)
def states(fn):
    def r(pwid): reads.append(clock[0]); return fn(clock[0])
    g.read_window_state = r
INFO = {"wid": 7, "os_window_id": 2, "platform_window_id": 99, "panes_in_os_window": 1,
        "tabs_in_os_window": 1, "panes_in_tab": 1,
        "last_for": {"pane": True, "tab": True, "os-window": True}}
# extra: reply keys such as fsfix=True, pid=4242 (the relax-on-fix inputs)
def kitten(entered=False, last=True, raise_=None, **extra):
    def k(addr, wid, toggle=False):
        if raise_: raise raise_
        if toggle:
            toggles.append(clock[0]); return dict(INFO, toggled_into_fullscreen=entered, **extra)
        return dict(INFO, last_for=dict(INFO["last_for"], pane=last), **extra)
    g.kitten_query = k
def since_toggle(): return clock[0] - toggles[0] if toggles else None
def run(mode="toggle", scope="pane", policy="block-stock"):
    rc, verdict, _info, last, relaxed = g.decide("unix:/nowhere", 7, mode, scope, policy)
    print(f"rc={rc} verdict={verdict} toggles={len(toggles)} reads={len(reads)} t={clock[0]:.1f}"
          f" state={last.state} relaxed={relaxed}")
# The process-start seam: hermetic by default (no ps), START[0] is "the" start time of any pid.
START = [1000]
REAL_PROC_START = g.proc_start
g.proc_start = lambda pid: START[0]
def policy(text):
    d = os.environ["CC_KITTY_FS_GUARD_STATE_DIR"]; os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "policy"), "w") as fh: fh.write(text)
def cache(pid, start, value):
    d = os.environ["CC_KITTY_FS_GUARD_STATE_DIR"]; os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, f"fsfix-{pid}-{start}"), "w") as fh: fh.write(value)
# main() in-process: the seams stay replaced, while _alert and --then still exec the PATH stubs
def cli(*a):
    rc = g.main(list(a)); print(f"rc={rc} toggles={len(toggles)}")
PY
}

# drive '<python scenario>'  — runs the harness, then the scenario (which calls run()).
drive() { /usr/bin/python3 -c "exec(open('$BATS_TEST_TMPDIR/h.py').read()); $1"; }
field() { tr ' ' '\n' <<<"$output" | sed -n "s/^$1=//p"; }
# the last verdict row the guard wrote
vrow() { grep '"phase":"verdict"' "$CC_KITTY_PANE_ACTIONS_LOG" | tail -1; }

@test "1 not the last pane: rc 0 with no CGS read and no toggle" {
  run drive 'kitten(last=False); states(lambda t: FS); run()'
  [ "$status" -eq 0 ]
  [[ "$output" == "rc=0 verdict=safe-not-last toggles=0 reads=0 "* ]] || { echo "$output"; false; }
}

@test "2 refuse mode: a fullscreen last pane refuses and never toggles" {
  run drive 'kitten(); states(lambda t: FS); run("refuse")'
  [[ "$output" == "rc=3 verdict=refused-fs toggles=0 "* ]] || { echo "$output"; false; }
}

@test "3 refuse mode: an UNKNOWN read refuses — unknown is never windowed" {
  run drive 'kitten(); states(lambda t: UNK); run("refuse")'
  [[ "$output" == "rc=3 verdict=refused-unknown toggles=0 "* ]] || { echo "$output"; false; }
}

@test "4 refuse mode: windowed on every sample for 1.0 s is safe, and not sooner" {
  run drive 'kitten(); states(lambda t: W()); run("refuse")'
  [[ "$output" == "rc=0 verdict=safe-windowed toggles=0 "* ]] || { echo "$output"; false; }
  [ "$(field t)" = "1.0" ] || { echo "$output"; false; }
}

@test "5 refuse mode: windowed that flips to fullscreen inside the second refuses (enter animation)" {
  run drive 'kitten(); states(lambda t: W() if t < 0.5 else FS); run("refuse")'
  [[ "$output" == "rc=3 verdict=refused-fs "* ]] || { echo "$output"; false; }
}

@test "6 toggle mode: a stably windowed last pane is safe with no toggle" {
  run drive 'kitten(); states(lambda t: W()); run()'
  [[ "$output" == "rc=0 verdict=safe-windowed toggles=0 "* ]] || { echo "$output"; false; }
}

@test "7 toggle mode: fullscreen → exactly one toggle → safe only after 1.0 s of stable windowed" {
  run drive 'kitten(); states(lambda t: FS if not toggles else (UNK if since_toggle() < 0.4 else W())); run()'
  [[ "$output" == "rc=0 verdict=safe-after-toggle toggles=1 "* ]] || { echo "$output"; false; }
  # windowed from 0.4 s after the toggle, held 1.0 s ⇒ no earlier than 1.4 s
  python3 -c "import sys; sys.exit(0 if float('$(field t)') >= 1.4 else 1)" || { echo "$output"; false; }
}

@test "8 toggle mode: never stably windowed → refused at the 8 s deadline, still ONE toggle" {
  run drive 'kitten(); states(lambda t: FS if not toggles else UNK); run()'
  [[ "$output" == "rc=3 verdict=refused-timeout toggles=1 "* ]] || { echo "$output"; false; }
  python3 -c "import sys; t=float('$(field t)'); sys.exit(0 if 8.0 <= t < 8.5 else 1)" || { echo "$output"; false; }
}

@test "9 toggle mode: windowed bounds still moving reset the stability clock" {
  # bounds change every 0.5 s until 3.0 s after the toggle, then hold
  run drive 'kitten(); states(lambda t: FS if not toggles else W((0.0, 0.0, 800.0 + (int(since_toggle() * 2) if since_toggle() < 3.0 else 99), 600.0))); run()'
  [[ "$output" == "rc=0 verdict=safe-after-toggle toggles=1 "* ]] || { echo "$output"; false; }
  python3 -c "import sys; sys.exit(0 if float('$(field t)') >= 4.0 else 1)" || { echo "$output"; false; }
}

@test "10 toggle mode: windowed for only 0.5 s, then unreadable, is not yet safe" {
  # W 0.0-0.5 s, UNKNOWN 0.5-0.8 s, then W for good ⇒ safe no earlier than 1.8 s after the toggle
  run drive 'kitten(); states(lambda t: FS if not toggles else (W() if since_toggle() < 0.5 or since_toggle() >= 0.8 else UNK)); run()'
  [[ "$output" == "rc=0 verdict=safe-after-toggle toggles=1 "* ]] || { echo "$output"; false; }
  python3 -c "import sys; sys.exit(0 if float('$(field t)') >= 1.8 else 1)" || { echo "$output"; false; }
}

@test "11 toggle mode: a toggle that ENTERED fullscreen is undone once, only after the enter settles" {
  # FS held 1.0 s after the bad toggle ⇒ exactly one undo, sent no earlier than 1.0 s later
  run drive 'kitten(entered=True); states(lambda t: FS); run(); print("undo_at", round(toggles[1] - toggles[0], 1))'
  [[ "${lines[0]}" == "rc=3 verdict=refused-entered toggles=2 "* ]] || { echo "$output"; false; }
  python3 -c "import sys; sys.exit(0 if float('${lines[1]#undo_at }') >= 1.0 else 1)" || { echo "$output"; false; }
  # windowed held ⇒ the toggle never took: NO undo (an undo would now ENTER fullscreen)
  run drive 'kitten(entered=True); states(lambda t: FS if not toggles else W()); run()'
  [[ "$output" == "rc=3 verdict=refused-entered toggles=1 "* ]] || { echo "$output"; false; }
  # never settles ⇒ no undo, refused at the deadline
  run drive 'kitten(entered=True); states(lambda t: FS if not toggles else UNK); run()'
  [[ "$output" == "rc=3 verdict=refused-timeout toggles=1 "* ]] || { echo "$output"; false; }
}

@test "12 toggle mode: fullscreen on a Space nobody is looking at refuses — no Space switch" {
  run drive 'kitten(); states(lambda t: FS_BG); run()'
  [[ "$output" == "rc=3 verdict=refused-not-visible toggles=0 "* ]] || { echo "$output"; false; }
}

@test "13 toggle mode: UNKNOWN until 3 s refuses; UNKNOWN that clears to windowed is safe" {
  run drive 'kitten(); states(lambda t: UNK); run()'
  [[ "$output" == "rc=3 verdict=refused-unknown toggles=0 "* ]] || { echo "$output"; false; }
  python3 -c "import sys; t=float('$(field t)'); sys.exit(0 if 3.0 <= t < 3.5 else 1)" || { echo "$output"; false; }
  run drive 'kitten(); states(lambda t: UNK if t < 1.0 else W()); run()'
  [[ "$output" == "rc=0 verdict=safe-windowed toggles=0 "* ]] || { echo "$output"; false; }
}

@test "14 a window kitty cannot match is rc 4; a kitten that fails is rc 3" {
  run drive 'kitten(raise_=g.NotFound("x")); states(lambda t: W()); run()'
  [[ "$output" == "rc=4 verdict=not-found "* ]] || { echo "$output"; false; }
  run drive 'kitten(raise_=g.KittenFailed("x")); states(lambda t: W()); run()'
  [[ "$output" == "rc=3 verdict=kitten-failed "* ]] || { echo "$output"; false; }
}

@test "15 scope: a tab that is not the OS window's only tab is safe-not-last; os-window always engages" {
  run drive 'INFO["last_for"] = {"pane": True, "tab": False, "os-window": True}; kitten(); states(lambda t: FS); run("refuse", "tab")'
  [[ "$output" == "rc=0 verdict=safe-not-last "* ]] || { echo "$output"; false; }
  run drive 'INFO["last_for"] = {"pane": False, "tab": False, "os-window": True}; g.kitten_query = lambda a, w, toggle=False: dict(INFO); states(lambda t: FS); run("refuse", "os-window")'
  [[ "$output" == "rc=3 verdict=refused-fs "* ]] || { echo "$output"; false; }
}

@test "16 MUTANT CONTROL: without the 1.0 s stability gate, cases 5 and 10 would pass a transition" {
  run drive 'g.STABLE_S = 0; kitten(); states(lambda t: W() if t < 0.5 else FS); run("refuse")'
  [[ "$output" == "rc=0 "* ]] || { echo "$output"; false; }
  run drive 'g.STABLE_S = 0; kitten(); states(lambda t: FS if not toggles else (W() if since_toggle() < 0.5 or since_toggle() >= 0.8 else UNK)); run()'
  python3 -c "import sys; sys.exit(0 if float('$(field t)') < 1.8 else 1)" || { echo "$output"; false; }
}

@test "17 CLI: the kitten reply decides — not-last exits 0; kitty's MatchError exits 4" {
  KFG_KITTEN_OUT='{"wid":7,"os_window_id":2,"platform_window_id":99,"panes_in_os_window":2,"tabs_in_os_window":1,"panes_in_tab":2,"last_for":{"pane":false,"tab":true,"os-window":true}}' \
    run "$GUARD" --window 7 --to unix:/nowhere --mode refuse --tool t
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q "kitty @ --to unix:/nowhere kitten --match id:7 $KITTEN query" "$CALLS" || { cat "$CALLS"; false; }
  KFG_KITTEN_RC=1 KFG_KITTEN_ERR='No matching windows for expression: id:7' KFG_KITTEN_OUT='' \
    run "$GUARD" --window 7 --to unix:/nowhere --mode refuse
  [ "$status" -eq 4 ] || { echo "$output"; false; }
  KFG_KITTEN_OUT='not json' run "$GUARD" --window 7 --to unix:/nowhere --mode refuse
  [ "$status" -eq 3 ] || { echo "$output"; false; }
}

@test "18 CLI --then: acts through the kitten on THAT window only after rc 0, with the verdict row already on disk" {
  KFG_KITTEN_OUT='{"wid":7,"os_window_id":2,"platform_window_id":99,"panes_in_os_window":2,"tabs_in_os_window":1,"panes_in_tab":2,"last_for":{"pane":false,"tab":true,"os-window":true}}' \
    run "$GUARD" --window 7 --to unix:/nowhere --mode toggle --scope pane --tool kitty.conf --then detach_window ask
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx "kitty @ --to unix:/nowhere kitten --match id:7 $KITTEN act detach_window ask \\[KITTY_WINDOW_ID=\\] \\[verdicts=1\\]" "$CALLS" || { cat "$CALLS"; false; }
  run grep -c 'action --self' "$CALLS"
  [ "$output" = "0" ] || { cat "$CALLS"; false; }
  grep -q '"tool":"kitty-fullscreen-guard","phase":"verdict".*"verdict":"safe-not-last".*"caller":"kitty.conf"' "$CC_KITTY_PANE_ACTIONS_LOG" || { cat "$CC_KITTY_PANE_ACTIONS_LOG"; false; }
  : >"$CALLS"
  KFG_KITTEN_RC=1 KFG_KITTEN_ERR='No matching windows for expression: id:7' KFG_KITTEN_OUT='' \
    run "$GUARD" --window 7 --to unix:/nowhere --mode toggle --then detach_window ask
  [ "$status" -eq 4 ]
  run grep -c ' act ' "$CALLS"
  [ "$output" = "0" ] || { cat "$CALLS"; false; }
  # the kitten found focus moved off the window during the wait: nothing done, rc 3
  KFG_ACT_OUT='{"error":"focus-moved","wid":7}' KFG_KITTEN_OUT='{"wid":7,"os_window_id":2,"platform_window_id":99,"panes_in_os_window":2,"tabs_in_os_window":1,"panes_in_tab":2,"last_for":{"pane":false,"tab":true,"os-window":true}}' \
    run "$GUARD" --window 7 --to unix:/nowhere --mode toggle --then detach_window
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"focus-moved — nothing done"* ]] || { echo "$output"; false; }
}

@test "19 CLI: usage errors exit 2 (no window, bad mode, bad scope, empty --then)" {
  run "$GUARD" --mode toggle;                              [ "$status" -eq 2 ]
  run "$GUARD" --window 7 --mode maybe;                    [ "$status" -eq 2 ]
  run "$GUARD" --window 7 --mode refuse --scope desk;      [ "$status" -eq 2 ]
  run "$GUARD" --window 7 --mode refuse --then;            [ "$status" -eq 2 ]
  run "$GUARD" --any-fs;                                   [ "$status" -eq 2 ]
}

@test "20 --any-fs: any fullscreen window or a failed read refuses; none fullscreen is safe" {
  run drive 'g.pid_window_states = lambda pid: [(1, W()), (2, g.WindowState("UNKNOWN", [], False, (0.0, 0.0, 500.0, 500.0)))]; print(g.any_fs(42))'
  [ "${lines[-1]}" = "0" ] || { echo "$output"; false; }
  run drive 'g.pid_window_states = lambda pid: [(1, W()), (2, FS_BG)]; print(g.any_fs(42))'
  [ "${lines[-1]}" = "3" ] || { echo "$output"; false; }
  run drive 'g.pid_window_states = lambda pid: [(1, W()), (2, UNK)]; print(g.any_fs(42))'
  [ "${lines[-1]}" = "3" ] || { echo "$output"; false; }
  run drive 'g.pid_window_states = lambda pid: None; print(g.any_fs(42))'
  [ "${lines[-1]}" = "3" ] || { echo "$output"; false; }
  # one clear sample is not enough: a window that reads FS 0.5 s later (an enter landing) refuses
  run drive 'g.pid_window_states = lambda pid: [(1, W() if clock[0] < 0.5 else FS)]; print(g.any_fs(42))'
  [ "${lines[-1]}" = "3" ] || { echo "$output"; false; }
}

@test "21 the state read is three-valued and fails to UNKNOWN, never to WINDOWED" {
  run drive 'print(g.classify([4], False), g.classify([0, 4], True), g.classify([0], True), g.classify([0], False), g.classify([], True), g.classify(None, True), g.classify([1], True)); print(g.read_window_state(None).state, g.read_window_state(0).state, g.read_window_state(-5).state, g.read_window_state(True).state)'
  [ "${lines[0]}" = "FS FS WINDOWED UNKNOWN UNKNOWN UNKNOWN UNKNOWN" ] || { echo "$output"; false; }
  [ "${lines[1]}" = "UNKNOWN UNKNOWN UNKNOWN UNKNOWN" ] || { echo "$output"; false; }
  # the REAL CGS path (dlopen, CGWindowList, CF reads): a window id nobody owns is UNKNOWN, and
  # this python process — which owns no window — lists as an empty, READABLE set, not a failure
  run drive 'print(g.read_window_state(2**31 - 1).state, g.pid_window_states(os.getpid()))'
  [ "$output" = "UNKNOWN []" ] || { echo "$output"; false; }
}

@test "23 CLI toggle-mode refusal: the guard's OWN alert names the window and its state (callers raise none)" {
  # last pane of an OS window whose platform id no window owns ⇒ the real read is UNKNOWN for 3 s
  KFG_KITTEN_OUT='{"wid":7,"os_window_id":2,"platform_window_id":2147483646,"panes_in_os_window":1,"tabs_in_os_window":1,"panes_in_tab":1,"last_for":{"pane":true,"tab":true,"os-window":true}}' \
    run "$GUARD" --window 7 --to unix:/nowhere --mode toggle --tool t
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  grep -q '^osascript .*display alert.*kitty window 7 is the last pane of a fullscreen window.*last state: UNKNOWN.*Leave fullscreen and try again' "$CALLS" || { cat "$CALLS"; false; }
  run grep -c 'application "kitty"' "$CALLS"
  [ "$output" = "0" ] || { cat "$CALLS"; false; }
  # refuse mode never alerts — its callers are autonomous and nobody is at the keyboard
  : >"$CALLS"
  KFG_KITTEN_OUT='{"wid":7,"os_window_id":2,"platform_window_id":2147483646,"panes_in_os_window":1,"tabs_in_os_window":1,"panes_in_tab":1,"last_for":{"pane":true,"tab":true,"os-window":true}}' \
    run "$GUARD" --window 7 --to unix:/nowhere --mode refuse
  [ "$status" -eq 3 ]
  run grep -c '^osascript' "$CALLS"
  [ "$output" = "0" ] || { cat "$CALLS"; false; }
}

@test "22 kitten: last_for per scope, and toggle only when asked, on the window's OS window" {
  K=/Applications/kitty.app/Contents/MacOS/kitty
  [ -x "$K" ] || skip "kitty is not installed — the kitten runs under kitty's own python"
  run env -u KITTY_LISTEN_ON -u KITTY_WINDOW_ID "$K" +runpy '
def main():
    import importlib.util, json, os
    spec = importlib.util.spec_from_file_location("k", os.environ["KITTEN"])
    k = importlib.util.module_from_spec(spec); spec.loader.exec_module(k)
    calls = []
    k.toggle_fullscreen = lambda osw: calls.append(osw) or False
    k.platform_window_id = lambda osw: 1000 + osw
    class G(list):
        @property
        def num_groups(self): return len(self)
    class T:
        def __init__(s, tid, osw, n): s.id, s.os_window_id, s.windows = tid, osw, G(range(n))
        def __len__(s): return len(s.windows)
    class W:
        def __init__(s, tab): s.tab_id, s._t = tab.id, tab
        def tabref(s): return s._t
    lone, a, b = T(1, 5, 1), T(2, 6, 2), T(3, 6, 1)
    boss = type("B", (), {})()
    boss.window_id_map = {7: W(lone), 8: W(a), 9: W(b)}
    boss.os_window_map = {5: [lone], 6: [a, b]}
    boss.tab_for_id = lambda tid: None
    for wid in (7, 8, 9):
        print(json.dumps(json.loads(k.handle_result([os.environ["KITTEN"], "query"], "", wid, boss))["last_for"], sort_keys=True))
    print("toggles-after-query", calls)
    r = json.loads(k.handle_result([os.environ["KITTEN"], "toggle"], "", 7, boss))
    print("toggle", calls, r["toggled_into_fullscreen"], r["platform_window_id"])
    print(json.loads(k.handle_result([os.environ["KITTEN"], "query"], "", 404, boss)))
    combined = []
    boss.combine = lambda a, w, raise_error=False: combined.append((a, w is boss.window_id_map[7])) or True
    boss.active_window = boss.window_id_map[8]
    print("act-unfocused", json.loads(k.handle_result([os.environ["KITTEN"], "act", "detach_window"], "", 7, boss)), combined)
    boss.active_window = boss.window_id_map[7]
    print("act-focused", json.loads(k.handle_result([os.environ["KITTEN"], "act", "detach_window", "ask"], "", 7, boss)), combined)
    print("act-gone", json.loads(k.handle_result([os.environ["KITTEN"], "act", "close_tab"], "", 404, boss)))
    # relax-on-fix inputs: pid is this process, fsfix a REAL objc_getClass read (a bool, never None
    # where ctypes works). Controls: a class every process has reads True, an absent one False —
    # the F3 trap was an absent class reading True (`None != 0`).
    q = json.loads(k.handle_result([os.environ["KITTEN"], "query"], "", 7, boss))
    print("fsfix", q["pid"] == os.getpid(), type(q["fsfix"]).__name__)
    k.FSFIX_MARKER = b"NSObject"; present = k.fsfix()
    k.FSFIX_MARKER = b"CcNoSuchClassAnywhere"; print("marker-control", present, k.fsfix())
main()
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "${lines[0]}" = '{"os-window": true, "pane": true, "tab": true}' ] || { echo "$output"; false; }
  [ "${lines[1]}" = '{"os-window": true, "pane": false, "tab": false}' ] || { echo "$output"; false; }
  [ "${lines[2]}" = '{"os-window": true, "pane": false, "tab": false}' ] || { echo "$output"; false; }
  [ "${lines[3]}" = "toggles-after-query []" ] || { echo "$output"; false; }
  [ "${lines[4]}" = "toggle [5] False 1005" ] || { echo "$output"; false; }
  [[ "${lines[5]}" == *"error"* ]] || { echo "$output"; false; }
  [ "${lines[6]}" = "act-unfocused {'error': 'focus-moved', 'wid': 7} []" ] || { echo "$output"; false; }
  [ "${lines[7]}" = "act-focused {'wid': 7, 'acted': True} [('detach_window ask', True)]" ] || { echo "$output"; false; }
  [[ "${lines[8]}" == "act-gone {'error': 'window 404 is gone'}" ]] || { echo "$output"; false; }
  [ "${lines[9]}" = "fsfix True bool" ] || { echo "$output"; false; }
  [ "${lines[10]}" = "marker-control True False" ] || { echo "$output"; false; }
}

# ── RELAX ON THE FIX (2026-10-16; guard docstring § RELAX and § POLICY) ─────────────────────────
# A refused-fs verdict becomes rc 0 only when the RUNNING kitty reports fsfix true (or the policy
# file relaxes stock kitty, D1 options B/C), the policy is not `enforce`, and the last read was FS
# AND onscreen. A relaxable call never toggles. RED-proof: every case below fails on the pre-change
# guard (no 5-tuple decide, no policy/cache, no would_rc row).

@test "24 RELAX refuse mode: fsfix + FS onscreen ⇒ rc 0, row keeps refused-fs with would_rc 3, no stderr refusal, no alert" {
  run drive 'kitten(fsfix=True, pid=4242); states(lambda t: FS); cli("--window", "7", "--to", "unix:/nowhere", "--mode", "refuse", "--tool", "t")'
  [ "$output" = "rc=0 toggles=0" ] || { echo "$output"; false; }
  vrow | grep -q '"verdict":"refused-fs","rc":0,.*"fsfix":true,"policy":"block-stock","would_rc":3,"relaxed":"fsfix","enforced":false' || { cat "$CC_KITTY_PANE_ACTIONS_LOG"; false; }
  run grep -c '^osascript' "$CALLS"
  [ "$output" = "0" ] || { cat "$CALLS"; false; }
  # the cache for that kitty process is written as a side effect (read back by --any-fs)
  [ "$(cat "$CC_KITTY_FS_GUARD_STATE_DIR/fsfix-4242-1000")" = "true" ]
}

@test "25 RELAX toggle mode: the kitten's toggle is NEVER sent, and the refusal alert never shows" {
  run drive 'kitten(fsfix=True); states(lambda t: FS); cli("--window", "7", "--to", "unix:/nowhere", "--mode", "toggle", "--tool", "kitty.conf")'
  [ "$output" = "rc=0 toggles=0" ] || { echo "$output"; false; }
  vrow | grep -q '"verdict":"refused-fs","rc":0,"mode":"toggle".*"would_rc":3,"relaxed":"fsfix"' || { cat "$CC_KITTY_PANE_ACTIONS_LOG"; false; }
  run grep -c '^osascript' "$CALLS"
  [ "$output" = "0" ] || { cat "$CALLS"; false; }
  # coerced to REFUSE mode, not to the pre-toggle wait: an UNKNOWN read refuses at once, even one
  # that would clear to FS-onscreen a second later (no relax without a stable read)
  run drive 'kitten(fsfix=True); states(lambda t: UNK if t < 1.0 else FS); run()'
  [[ "$output" == "rc=3 verdict=refused-unknown toggles=0 reads=1 t=0.0 "*" relaxed=None" ]] || { echo "$output"; false; }
}

@test "26 RELAX with --then: the native action still runs through the kitten, after the relaxed verdict" {
  run drive 'kitten(fsfix=True); states(lambda t: FS); cli("--window", "7", "--to", "unix:/nowhere", "--mode", "toggle", "--tool", "kitty.conf", "--then", "detach_window", "ask")'
  [ "$output" = "rc=0 toggles=0" ] || { echo "$output"; false; }
  grep -qx "kitty @ --to unix:/nowhere kitten --match id:7 $KITTEN act detach_window ask \\[KITTY_WINDOW_ID=\\] \\[verdicts=1\\]" "$CALLS" || { cat "$CALLS"; false; }
}

@test "27 policy enforce: fsfix true still refuses (rc 3), and toggle mode toggles exactly as before" {
  run drive 'policy("enforce\n"); kitten(fsfix=True); states(lambda t: FS); cli("--window", "7", "--to", "unix:/nowhere", "--mode", "refuse")'
  [[ "$output" == *"refused (refused-fs) kitty window 7"*"rc=3 toggles=0" ]] || { echo "$output"; false; }
  vrow | grep -q '"verdict":"refused-fs","rc":3,.*"policy":"enforce"' || { cat "$CC_KITTY_PANE_ACTIONS_LOG"; false; }
  run grep -c 'would_rc' "$CC_KITTY_PANE_ACTIONS_LOG"
  [ "$output" = "0" ]
  run drive 'kitten(fsfix=True); states(lambda t: FS if not toggles else W()); run(policy="enforce")'
  [[ "$output" == "rc=0 verdict=safe-after-toggle toggles=1 "*" relaxed=None" ]] || { echo "$output"; false; }
}

@test "28 not fixed: fsfix None or false (stock kitty) under the default policy refuses, and toggle mode still toggles" {
  run drive 'kitten(fsfix=None, pid=4242); states(lambda t: FS); run("refuse")'
  [[ "$output" == "rc=3 verdict=refused-fs toggles=0 "*" relaxed=None" ]] || { echo "$output"; false; }
  run drive 'kitten(fsfix=False); states(lambda t: FS); run("refuse")'
  [[ "$output" == "rc=3 verdict=refused-fs toggles=0 "*" relaxed=None" ]] || { echo "$output"; false; }
  run drive 'kitten(fsfix=False); states(lambda t: FS if not toggles else W()); run()'
  [[ "$output" == "rc=0 verdict=safe-after-toggle toggles=1 "* ]] || { echo "$output"; false; }
  # a None fsfix is never cached; a false one is (so --any-fs reads "not fixed", not "unknown")
  run drive 'kitten(fsfix=None, pid=4242); states(lambda t: W()); run("refuse"); kitten(fsfix=False, pid=4343); run("refuse")'
  [ ! -e "$CC_KITTY_FS_GUARD_STATE_DIR/fsfix-4242-1000" ]
  [ "$(cat "$CC_KITTY_FS_GUARD_STATE_DIR/fsfix-4343-1000")" = "false" ]
}

@test "29 RELAX needs onscreen: fsfix true but FS on a background Space keeps rc 3 (unmeasured residual, README § Residuals)" {
  run drive 'kitten(fsfix=True); states(lambda t: FS_BG); run("refuse")'
  [[ "$output" == "rc=3 verdict=refused-fs toggles=0 "*" relaxed=None" ]] || { echo "$output"; false; }
  run drive 'kitten(fsfix=True); states(lambda t: FS_BG); run()'
  [[ "$output" == "rc=3 verdict=refused-not-visible toggles=0 "*" relaxed=None" ]] || { echo "$output"; false; }
  # unknown is not fullscreen-onscreen either
  run drive 'kitten(fsfix=True); states(lambda t: UNK); run("refuse")'
  [[ "$output" == "rc=3 verdict=refused-unknown toggles=0 "*" relaxed=None" ]] || { echo "$output"; false; }
}

@test "30 D1 options B/C: relax-stock-refuse relaxes stock refuse mode only; relax-stock also stops the toggle" {
  run drive 'kitten(fsfix=False); states(lambda t: FS); run("refuse", policy="relax-stock-refuse")'
  [[ "$output" == "rc=0 verdict=refused-fs toggles=0 "*" relaxed=policy" ]] || { echo "$output"; false; }
  run drive 'kitten(fsfix=False); states(lambda t: FS if not toggles else W()); run(policy="relax-stock-refuse")'
  [[ "$output" == "rc=0 verdict=safe-after-toggle toggles=1 "*" relaxed=None" ]] || { echo "$output"; false; }
  run drive 'kitten(fsfix=False); states(lambda t: FS); run(policy="relax-stock")'
  [[ "$output" == "rc=0 verdict=refused-fs toggles=0 "*" relaxed=policy" ]] || { echo "$output"; false; }
  # the onscreen requirement holds under every policy
  run drive 'kitten(fsfix=False); states(lambda t: FS_BG); run("refuse", policy="relax-stock")'
  [[ "$output" == "rc=3 verdict=refused-fs "* ]] || { echo "$output"; false; }
  # and the policy is read from the file, one line
  run drive 'policy("relax-stock-refuse\n"); kitten(fsfix=False); states(lambda t: FS); cli("--window", "7", "--to", "unix:/nowhere", "--mode", "refuse")'
  [ "$output" = "rc=0 toggles=0" ] || { echo "$output"; false; }
  vrow | grep -q '"policy":"relax-stock-refuse","would_rc":3,"relaxed":"policy","enforced":false' || { cat "$CC_KITTY_PANE_ACTIONS_LOG"; false; }
}

@test "31 policy file: an unknown value enforces and says so ONCE; empty and comments-only read as the default" {
  run drive 'policy("relax-everything\n"); kitten(fsfix=True); states(lambda t: FS); cli("--window", "7", "--to", "unix:/nowhere", "--mode", "refuse")'
  [[ "$output" == *"rc=3 toggles=0" ]] || { echo "$output"; false; }
  [ "$(grep -c "'relax-everything' is not one of block-stock, enforce, relax-stock-refuse, relax-stock — enforcing" <<<"$output")" = "1" ] || { echo "$output"; false; }
  vrow | grep -q '"policy":"enforce","policy_refused":"relax-everything"' || { cat "$CC_KITTY_PANE_ACTIONS_LOG"; false; }
  run drive 'policy(""); print(g.read_policy()); policy("# D1 pending\n\n"); print(g.read_policy()); policy("  enforce  \n# why\n"); print(g.read_policy())'
  [ "${lines[0]}" = "('block-stock', None)" ] || { echo "$output"; false; }
  [ "${lines[1]}" = "('block-stock', None)" ] || { echo "$output"; false; }
  [ "${lines[2]}" = "('enforce', None)" ] || { echo "$output"; false; }
  # unreadable ⇒ enforce (a directory where the file should be)
  rm -f "$CC_KITTY_FS_GUARD_STATE_DIR/policy"
  mkdir "$CC_KITTY_FS_GUARD_STATE_DIR/policy"
  run drive 'print(g.read_policy()[0])'
  [ "${lines[-1]}" = "enforce" ] || { echo "$output"; false; }
}

@test "32 fsfix cache is keyed on pid AND start time: same pid, different start ⇒ not fixed" {
  run drive 'kitten(fsfix=True, pid=4242); states(lambda t: W()); run("refuse"); print(g.cached_fsfix(4242)); START[0] = 2000; print(g.cached_fsfix(4242))'
  [ "${lines[1]}" = "True" ] || { echo "$output"; false; }
  [ "${lines[2]}" = "None" ] || { echo "$output"; false; }
  # a new process with that pid overwrites, and the dead one's file goes
  run drive 'START[0] = 2000; kitten(fsfix=False, pid=4242); states(lambda t: W()); run("refuse"); print(g.cached_fsfix(4242))'
  [ "${lines[-1]}" = "False" ] || { echo "$output"; false; }
  [ ! -e "$CC_KITTY_FS_GUARD_STATE_DIR/fsfix-4242-1000" ]
  [ -e "$CC_KITTY_FS_GUARD_STATE_DIR/fsfix-4242-2000" ]
  # an unreadable start time never hits; garbage content is not a value
  run drive 'g.proc_start = lambda pid: None; print(g.cached_fsfix(4242))'
  [ "${lines[-1]}" = "None" ] || { echo "$output"; false; }
  run drive 'cache(77, 1000, "yes\n"); print(g.cached_fsfix(77))'
  [ "${lines[-1]}" = "None" ] || { echo "$output"; false; }
  # the REAL start-time read: this process has one and it is stable; a pid that cannot exist has none
  run drive 'a = REAL_PROC_START(os.getpid()); print(isinstance(a, int) and a > 0, a == REAL_PROC_START(os.getpid()), REAL_PROC_START(-1))'
  [ "${lines[-1]}" = "True True None" ] || { echo "$output"; false; }
}

@test "33 --any-fs RELAX: cached fsfix true + every FS window onscreen ⇒ 0; missing cache, offscreen FS or enforce ⇒ 3" {
  run drive 'cache(42, 1000, "true\n"); g.pid_window_states = lambda pid: [(1, FS), (2, W())]; print(g.any_fs(42))'
  [ "${lines[-1]}" = "0" ] || { echo "$output"; false; }
  vrow | grep -q '"mode":"any-fs","verdict":"refused-fs","rc":0,.*"fsfix":true,.*"would_rc":3,"relaxed":"fsfix","enforced":false' || { cat "$CC_KITTY_PANE_ACTIONS_LOG"; false; }
  # no cache for this kitty process (pid 43 was never cached) ⇒ not fixed
  run drive 'g.pid_window_states = lambda pid: [(1, FS)]; print(g.any_fs(43))'
  [ "${lines[-1]}" = "3" ] || { echo "$output"; false; }
  run drive 'cache(42, 1000, "true\n"); g.pid_window_states = lambda pid: [(1, FS), (2, FS_BG)]; print(g.any_fs(42))'
  [ "${lines[-1]}" = "3" ] || { echo "$output"; false; }
  run drive 'cache(42, 1000, "true\n"); g.pid_window_states = lambda pid: [(1, FS), (2, UNK)]; print(g.any_fs(42))'
  [ "${lines[-1]}" = "3" ] || { echo "$output"; false; }
  run drive 'cache(42, 1000, "true\n"); policy("enforce\n"); g.pid_window_states = lambda pid: [(1, FS)]; print(g.any_fs(42))'
  [ "${lines[-1]}" = "3" ] || { echo "$output"; false; }
  rm -f "$CC_KITTY_FS_GUARD_STATE_DIR/policy"   # back to the default for the cases below
  # one onscreen sample is not enough: a window that goes fullscreen OFFSCREEN 0.5 s later refuses
  run drive 'cache(42, 1000, "true\n"); g.pid_window_states = lambda pid: [(1, FS)] + ([(2, FS_BG)] if clock[0] >= 0.5 else []); print(g.any_fs(42))'
  [ "${lines[-1]}" = "3" ] || { echo "$output"; false; }
  # through the CLI, with the cache keyed on a pid's real start (this bats shell's)
  run drive "g.proc_start = REAL_PROC_START; cache($$, REAL_PROC_START($$), 'true\n'); g.pid_window_states = lambda pid: [(1, FS)]; print(g.main(['--any-fs', '--kitty-pid', '$$']))"
  [ "${lines[-1]}" = "0" ] || { echo "$output"; false; }
}
