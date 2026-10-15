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
# RED-proof: the guard did not exist before this change (every case fails on a missing file). The
# stability gate's own control is case 16: with STABLE_S forced to 0, the enter-animation case (5)
# and the half-second-windowed case (10) return 0, which is the regression these cases catch.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export GUARD="$REPO/bin/kitty-fullscreen-guard" KITTEN="$REPO/lib/kitty-fs-kitten.py"
  [ -f "$GUARD" ]; [ -f "$KITTEN" ]
  unset KITTY_LISTEN_ON KITTY_WINDOW_ID KITTY_PID CC_KITTY_FS_GUARD
  HOME="$BATS_TEST_TMPDIR/home"; export HOME; mkdir -p "$HOME"
  export CC_KITTY_PANE_ACTIONS_LOG="$BATS_TEST_TMPDIR/actions.jsonl"
  export CALLS="$BATS_TEST_TMPDIR/calls.log"; : >"$CALLS"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  # kitty: logs argv + KITTY_WINDOW_ID; `kitten` answers $KFG_KITTEN_OUT on stdout with rc
  # $KFG_KITTEN_RC (stderr $KFG_KITTEN_ERR); everything else rc 0.
  cat >"$STUBS/kitty" <<'SH'
#!/bin/sh
echo "kitty $* [KITTY_WINDOW_ID=${KITTY_WINDOW_ID:-}]" >>"$CALLS"
case " $* " in
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
def kitten(entered=False, last=True, raise_=None):
    def k(addr, wid, toggle=False):
        if raise_: raise raise_
        if toggle:
            toggles.append(clock[0]); return dict(INFO, toggled_into_fullscreen=entered)
        return dict(INFO, last_for=dict(INFO["last_for"], pane=last))
    g.kitten_query = k
def since_toggle(): return clock[0] - toggles[0] if toggles else None
def run(mode="toggle", scope="pane"):
    rc, verdict, _info, last = g.decide("unix:/nowhere", 7, mode, scope)
    print(f"rc={rc} verdict={verdict} toggles={len(toggles)} reads={len(reads)} t={clock[0]:.1f}"
          f" state={last.state}")
PY
}

# drive '<python scenario>'  — runs the harness, then the scenario (which calls run()).
drive() { /usr/bin/python3 -c "exec(open('$BATS_TEST_TMPDIR/h.py').read()); $1"; }
field() { tr ' ' '\n' <<<"$output" | sed -n "s/^$1=//p"; }

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

@test "11 toggle mode: a toggle that ENTERED fullscreen is toggled back and refuses" {
  run drive 'kitten(entered=True); states(lambda t: FS); run()'
  [[ "$output" == "rc=3 verdict=refused-entered toggles=2 "* ]] || { echo "$output"; false; }
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

@test "18 CLI --then: runs the action with --self on THAT window only after rc 0, and logs the verdict" {
  KFG_KITTEN_OUT='{"wid":7,"os_window_id":2,"platform_window_id":99,"panes_in_os_window":2,"tabs_in_os_window":1,"panes_in_tab":2,"last_for":{"pane":false,"tab":true,"os-window":true}}' \
    run "$GUARD" --window 7 --to unix:/nowhere --mode toggle --scope pane --tool kitty.conf --then detach_window ask
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx 'kitty @ --to unix:/nowhere action --self detach_window ask \[KITTY_WINDOW_ID=7\]' "$CALLS" || { cat "$CALLS"; false; }
  grep -q '"tool":"kitty-fullscreen-guard","phase":"verdict".*"verdict":"safe-not-last".*"caller":"kitty.conf"' "$CC_KITTY_PANE_ACTIONS_LOG" || { cat "$CC_KITTY_PANE_ACTIONS_LOG"; false; }
  : >"$CALLS"
  KFG_KITTEN_RC=1 KFG_KITTEN_ERR='No matching windows for expression: id:7' KFG_KITTEN_OUT='' \
    run "$GUARD" --window 7 --to unix:/nowhere --mode toggle --then detach_window ask
  [ "$status" -eq 4 ]
  run grep -c ' action ' "$CALLS"
  [ "$output" = "0" ] || { cat "$CALLS"; false; }
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
}

@test "21 the state read is three-valued and fails to UNKNOWN, never to WINDOWED" {
  run drive 'print(g.classify([4], False), g.classify([0, 4], True), g.classify([0], True), g.classify([0], False), g.classify([], True), g.classify(None, True), g.classify([1], True)); print(g.read_window_state(None).state, g.read_window_state(0).state, g.read_window_state(-5).state, g.read_window_state(True).state)'
  [ "${lines[0]}" = "FS FS WINDOWED UNKNOWN UNKNOWN UNKNOWN UNKNOWN" ] || { echo "$output"; false; }
  [ "${lines[1]}" = "UNKNOWN UNKNOWN UNKNOWN UNKNOWN" ] || { echo "$output"; false; }
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
main()
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "${lines[0]}" = '{"os-window": true, "pane": true, "tab": true}' ] || { echo "$output"; false; }
  [ "${lines[1]}" = '{"os-window": true, "pane": false, "tab": false}' ] || { echo "$output"; false; }
  [ "${lines[2]}" = '{"os-window": true, "pane": false, "tab": false}' ] || { echo "$output"; false; }
  [ "${lines[3]}" = "toggles-after-query []" ] || { echo "$output"; false; }
  [ "${lines[4]}" = "toggle [5] False 1005" ] || { echo "$output"; false; }
  [[ "${lines[5]}" == *"error"* ]] || { echo "$output"; false; }
}
