#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
#   Structurally false under bats (every @test body is its own subshell; `run` sets $output there).
#
# cc-resume-layout.sh --desktops --restore against the REAL shape of the 2026-10-15 00:01:27 kitty
# crash: six OS windows, 20 Claude panes, nested splits with biases of 1/6, 1/5, 1/4 and 1/3. The
# recovery of that crash brought every session back in a different pane position, because the rows
# it was handed carried no k<pid>w<n> group, so no recorded tree was found and replayed.
#
# Contracts under test:
#   · replay: the DRY plan (stderr `DRY [CC-DESK-n grp] head|tab|vsplit|hsplit … pane=#K
#     [next-to=#J] [bias=B]`) rebuilds every recorded tab exactly (structure, axis, bias, pane order)
#     when kitty's own split semantics are applied to it — checked by a simulation in THIS file
#     ($TT), against an expectation read straight from the fixture, never by the subject's planner
#     or scripts/lib/kitty_tree.py;
#   · discovery by session id: 4-column rows with no group find the heartbeat tree whose roster
#     holds their sessions, except one recorded by a kitty that is still running;
#   · read-back: after a replayed splits tab is built, `kitty @ ls` is compared with the plan; a
#     match is verdict=ok with no kitten, a difference sends the apply-layout kitten a spec whose
#     pairs are the plan in the launched window ids, and the verdict is the SECOND read-back.
#
# Fixture: tests/fixtures/kitty-crash-2026-10-15/ is the crash heartbeat (…/heartbeat/<boot>/64211/)
# minimized once by a throwaway script: OS window ids, platform ids, tab layout_state (pairs, window
# groups, class, opts) and window ids kept; every cwd rewritten to /work/proj-N, every session id to
# 00000000-0000-4000-8000-0000000000NN, accounts to next..next4, display uuids to FAKE-DISPLAY-A/B;
# cmdline, env, titles, foreground processes and user vars dropped.
#
# RED-proof: run in a scratch copy of this tree against `git show 5a5773b7a:bin/cc-resume-layout.sh`
# (the parent of aff7c1def, the pre-change script), cases 3-7 fail. Case 3: no `tree oswin=` line at
# all (rows without a group found no tree: 0 != 6). Case 4: its liveness half passes vacuously and
# its positive-control half fails (the dead kitty's tree is not found either). Case 5: no `kitty @
# ls` call (0 != 1). Cases 6-7: no `tree-verify` line and no kitten call — the pre-change script never
# reads a tree back. Cases 1 and 2 pass there: they pin the planner on the crash shape, which this
# change left alone, and their simulation is proven live by a mutant that swaps `one`/`two` in the
# planner's build() (passes the planner's own shape-only self-check; both cases fail at `check`,
# pane order reversed). Mutants of the CHANGED script: deleting `or live_kitty(...)` fails case 4 at
# `[ "$(tree_lines)" -eq 0 ]` (6 lines from the running kitty's tree); writing the read-back tree
# (`tab["tree"]`) into the kitten spec instead of the plan fails case 6 at the spec check.
#
# Axis: the crash fixture has only side-by-side pairs, so cases 1-3 do not exercise hsplit. Axis is
# pinned by tests/cc-resume-layout-desktops.bats ("tree: pairs are rebuilt with orientation and bias")
# and live by scripts/checks/restore-tree-live-verify.py (mixed vsplit/hsplit, three biases).
#
# Hermetic: HOME, CC_HEARTBEAT_DIR and CC_BOOT_RESUME_STATE_DIR are per-test; the script is COPIED
# into a fixture tree with stub capacity/spawn-log/lr-lib libraries; kitty and osascript are stubs;
# no case touches a real kitty. The layout script runs under /bin/bash 3.2, as launchd runs it.

bats_require_minimum_version 1.5.0

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FIXD="$BATS_TEST_DIRNAME/fixtures/kitty-crash-2026-10-15"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_HEARTBEAT_DIR="$BATS_TEST_TMPDIR/heartbeat"
  export CC_BOOT_RESUME_STATE_DIR="$BATS_TEST_TMPDIR/boot-resume"
  mkdir -p "$CC_HEARTBEAT_DIR" "$CC_BOOT_RESUME_STATE_DIR"
  export CC_ADMIT_GATE=off
  FIX="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$FIX/bin" "$FIX/scripts/lib" "$FIX/scripts/limit-recover"
  cp "$REPO/bin/cc-resume-layout.sh" "$FIX/bin/"
  for f in scripts/lib/kitty_tree.py scripts/kitty-apply-layout.py; do
    [ ! -f "$REPO/$f" ] || cp "$REPO/$f" "$FIX/$f"
  done
  LAYOUT="$FIX/bin/cc-resume-layout.sh"
  # The fixture tree holds no runner and HOME is hermetic: pin it (FIX-DESIGN §4 W2.4; kitty is a stub).
  export CC_PANE_RUNNER_BIN="$REPO/bin/cc-pane-runner"
  unset CC_PANE_CMD CC_PANE_CMD_INTERACTIVE CC_PANE_CMD_DIR   # injected into every pane; never inherited
  printf 'cc_capacity_admit() { return 0; }\ncc_capacity_probe() { return 0; }\ncc_capacity_admit_reason() { printf stub; }\n' \
    > "$FIX/scripts/lib/capacity-admit.sh"
  printf 'cc_log_pane_spawn() { :; }\n' > "$FIX/scripts/lib/pane-spawn-log.sh"
  printf 'lr_holder_count() { echo 0; }\n' > "$FIX/scripts/limit-recover/lr-lib.sh"

  # kitty stub: logs argv; a launch hands out 101, 102, … and records "<sid> <id>" in $KLOG.map; `ls`
  # answers $KLOG.lstpl with every "@<sid>@" replaced by the id that sid was handed; the apply kitten
  # keeps a copy of its spec and, when $KLOG.lstpl.after exists, makes it the new `ls` answer.
  export KLOG="$BATS_TEST_TMPDIR/kitty.log"
  export CC_TERM_KITTY="$BATS_TEST_TMPDIR/kitty-stub"
  cat > "$CC_TERM_KITTY" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$KLOG"
case " $* " in
  *" launch "*)
    n=$(cat "$KLOG.n" 2>/dev/null || echo 100); n=$((n + 1)); echo "$n" > "$KLOG.n"
    s="$(printf '%s' "$*" | grep -o "'sid-[a-z]*'" | head -1 | tr -d "'")"
    printf '%s %s\n' "$s" "$n" >> "$KLOG.map"
    echo "$n" ;;
  *" kitten --match "*)
    for a in "$@"; do last="$a"; done
    cp "$last" "$KLOG.spec"
    if [ -f "$KLOG.lstpl.after" ]; then mv "$KLOG.lstpl.after" "$KLOG.lstpl"; fi ;;
  *" ls "*)
    t="$(cat "$KLOG.lstpl")"
    while read -r s i; do t="$(printf '%s' "$t" | sed "s/\"@$s@\"/$i/g")"; done < "$KLOG.map"
    printf '%s\n' "$t" ;;
esac
exit 0
SH
  chmod +x "$CC_TERM_KITTY"
  export CC_OSASCRIPT_BIN="$BATS_TEST_TMPDIR/osascript"
  printf '#!/bin/bash\ncat > /dev/null\necho ok\n' > "$CC_OSASCRIPT_BIN"; chmod +x "$CC_OSASCRIPT_BIN"
  export CC_RESUME_ONE_BIN="$BATS_TEST_TMPDIR/resume-one"
  printf '#!/bin/bash\nexit 0\n' > "$CC_RESUME_ONE_BIN"; chmod +x "$CC_RESUME_ONE_BIN"
  export CC_SWIFT_BIN="$BATS_TEST_TMPDIR/no-swift" CC_LSOF_BIN="$BATS_TEST_TMPDIR/no-lsof"
  export CC_RESUME_STAGGER=0 CC_DESKTOP_SETTLE=0 CC_DESKTOP_FS_DELAY=0
  export CC_RESTORE_WAIT=0 CC_RESTORE_K_BACKOFF=0 CC_RESTORE_FS_GAP=0 CC_RESTORE_MAYBE_S=0
  export CC_RESTORE_MAYBE_POLL=0 CC_RESTORE_FS_VERIFY=0 CC_RESTORE_APPLY_SETTLE=0
  unset KITTY_WINDOW_ID KITTY_PID CC_TERM_KITTY_TO CC_RESTORE_KITTY_PID CC_RESTORE_TREE \
        CC_KITTY_APPLY_LAYOUT_KITTEN CC_KITTY_EQUALIZE_KITTEN CC_ADMIT_RESTORE_R CC_RESTORE_DEADLINE
  ROWS="$BATS_TEST_TMPDIR/rows.tsv"

  # $TT — the test's own model of kitty Splits (kitty 0.48.2 kitty/layout/splits.py): a pair is
  # (one, two, horizontal, bias = share of `one`); `launch --location=vsplit|hsplit --next-to X
  # --bias P` turns leaf X into pair(X, new, horizontal = vsplit, bias = 1 - P/100), 0.5 without P.
  TT="$BATS_TEST_TMPDIR/tt.py"
  cat > "$TT" <<'PY'
import json, re, sys

TOL = 0.005

def pairs(x, leaf):
    if x is None or isinstance(x, bool):
        return None
    if isinstance(x, int):
        return leaf(x)
    a, b = pairs(x.get("one"), leaf), pairs(x.get("two"), leaf)
    if a is None or b is None:
        return a if b is None else b
    return {"h": x.get("horizontal", True) is not False, "b": float(x.get("bias", 0.5)), "one": a, "two": b}

def leaves(n):
    return leaves(n["one"]) + leaves(n["two"]) if isinstance(n, dict) else [n]

def eq(a, b):
    if isinstance(a, dict) and isinstance(b, dict):
        return a["h"] == b["h"] and abs(a["b"] - b["b"]) <= TOL and eq(a["one"], b["one"]) and eq(a["two"], b["two"])
    return not isinstance(a, dict) and not isinstance(b, dict) and a == b

def roster(path):
    return {str(e["paneUUID"]): e["session_id"] for e in json.load(open(path))}

def expected(ls_path, roster_path, drop_pane=None):
    """Per OS window holding a roster pane: its tabs as trees, leaves = session id (shell:<cwd> else)."""
    ro = roster(roster_path)
    drop = ro.get(drop_pane) if drop_pane else None
    wins = []
    for o in json.load(open(ls_path)):
        tabs = []
        for t in o["tabs"]:
            st = t["layout_state"]
            assert st["class"] == "Splits", "fixture tab is not Splits"
            cwd = {w["id"]: w.get("cwd") for w in t["windows"]}
            gw = {g["id"]: g["window_ids"] for g in st["all_windows"]["window_groups"]}
            def leaf(g):
                ws = gw.get(g) or []
                sids = [ro[str(w)] for w in ws if str(w) in ro]
                if sids:
                    return None if sids[0] == drop else sids[0]
                return ("shell:%s" % cwd.get(ws[-1])) if ws else None
            n = pairs(st["pairs"], leaf)
            if n is not None:
                tabs.append(n)
        if any(not l.startswith("shell:") for t in tabs for l in leaves(t)):
            wins.append(tabs)
    return wins

DRY = re.compile(r"^DRY \[CC-DESK-(\d+) [^\]]*\] (head|tab|vsplit|hsplit) (.*)$")

def simulate(stderr_path):
    """Replay the DRY launch lines the way kitty would build them; leaves = session id."""
    wins, label = {}, {}
    def split(n, anchor, new, h, b):
        if isinstance(n, dict):
            return dict(n, one=split(n["one"], anchor, new, h, b), two=split(n["two"], anchor, new, h, b))
        return {"h": h, "b": b, "one": n, "two": new} if n == anchor else n
    for line in open(stderr_path):
        m = DRY.match(line.rstrip("\n"))
        if not m:
            continue
        win, how, rest = m.groups()
        tok = rest.split()
        kv = dict(t.split("=", 1) for t in tok if "=" in t)
        key = kv["pane"].lstrip("#")
        label[key] = "shell:%s" % tok[1] if tok[0] == "shell" else tok[1]
        tabs = wins.setdefault(win, [])
        if how in ("head", "tab"):
            tabs.append(key)
        else:
            b = 1 - float(kv["bias"]) / 100 if kv.get("bias") else 0.5
            tabs[-1] = split(tabs[-1], kv["next-to"].lstrip("#"), key, how == "vsplit", b)
    def rel(n):
        return dict(n, one=rel(n["one"]), two=rel(n["two"])) if isinstance(n, dict) else label[n]
    return [[rel(t) for t in tabs] for _, tabs in sorted(wins.items(), key=lambda kv: int(kv[0]))]

def check(ls_path, roster_path, stderr_path, drop_pane=None):
    exp, sim = expected(ls_path, roster_path, drop_pane), simulate(stderr_path)
    key = lambda w: tuple(sorted(l for t in w for l in leaves(t)))
    simk = {key(w): w for w in sim}
    bad = []
    for w in exp:
        got = simk.get(key(w))
        if got is None or len(got) != len(w) or not all(eq(a, b) for a, b in zip(w, got)):
            bad.append("want %s\n  got %s" % (json.dumps(w), json.dumps(got)))
    if len(sim) != len(exp):
        bad.append("planned %d windows, recorded %d" % (len(sim), len(exp)))
    if bad:
        print("\n".join(bad)); return 1
    print("ok windows=%d panes=%d" % (len(exp), sum(len(leaves(t)) for w in exp for t in w)))
    return 0

def spec(spec_path, ls_path, roster_path, map_path):
    """The kitten's spec must be the recorded tree with each session's launched window id as leaf."""
    wid = dict(l.split() for l in open(map_path) if l.strip())
    (want,) = expected(ls_path, roster_path)[0]
    def rel(n):
        return dict(n, one=rel(n["one"]), two=rel(n["two"])) if isinstance(n, dict) else int(wid[n])
    want = rel(want)
    got = pairs(json.load(open(spec_path))["pairs"], lambda w: w)
    if eq(want, got):
        print("spec-ok"); return 0
    print("want %s\ngot %s" % (json.dumps(want), json.dumps(got))); return 1

cmd, args = sys.argv[1], sys.argv[2:]
if cmd == "check":
    sys.exit(check(*args))
if cmd == "spec":
    sys.exit(spec(*args))
if cmd == "rows":       # rows <roster> [skip-pane] — 4-column rows: acct sid cwd branch
    for e in json.load(open(args[0])):
        if len(args) < 2 or str(e["paneUUID"]) != args[1]:
            print("\t".join([e["account"], e["session_id"], e["cwd"], "br"]))
    sys.exit(0)
if cmd == "sid":        # sid <roster> <pane>
    print(roster(args[0]).get(args[1], "")); sys.exit(0)
sys.exit(2)
PY
}

teardown() {
  if [ -f "$BATS_TEST_TMPDIR/live.pid" ]; then kill "$(cat "$BATS_TEST_TMPDIR/live.pid")" 2>/dev/null || true; fi
}

tree_lines() { printf '%s\n' "$output" | grep -c "^cc-resume-layout: tree oswin=${1:-}" || true; }
hb_copy() { # <dir> — the crash heartbeat recorded under a kitty pid dir
  mkdir -p "$1"; cp "$FIXD/hb.kitty-ls.json" "$FIXD/hb.roster.json" "$FIXD/hb.displays.tsv" "$1/"
  echo 1784800000 > "$1/hb.start"
}

@test "replay: the 2026-10-15 crash snapshot plans every tab back to its recorded tree" {
  run --separate-stderr /bin/bash "$LAYOUT" --desktops --restore --dry-run --tree "$FIXD/hb.kitty-ls.json" </dev/null
  [ "$status" -eq 0 ]
  [ ! -f "$KLOG" ]
  [ "$(tree_lines)" -eq 6 ]
  printf '%s\n' "$stderr" > "$BATS_TEST_TMPDIR/stderr"
  run python3 "$TT" check "$FIXD/hb.kitty-ls.json" "$FIXD/hb.roster.json" "$BATS_TEST_TMPDIR/stderr"
  [ "$status" -eq 0 ]
  [ "$output" = "ok windows=6 panes=20" ]
}

@test "replay: a session left out of the rows is dropped and its sibling takes its place, the rest keep their positions" {
  # pane 3 sits in OS window 2 as `one` of a 1/5-biased pair; without it that pair collapses into
  # its other half and the 1/6 root keeps its shape.
  python3 "$TT" rows "$FIXD/hb.roster.json" 3 > "$ROWS"
  [ "$(wc -l < "$ROWS" | tr -d ' ')" -eq 19 ]
  dropped="$(python3 "$TT" sid "$FIXD/hb.roster.json" 3)"; [ -n "$dropped" ]
  run --separate-stderr /bin/bash "$LAYOUT" --desktops --restore --dry-run --tree "$FIXD/hb.kitty-ls.json" --file "$ROWS"
  [ "$status" -eq 0 ]
  ! printf '%s\n' "$stderr" | grep -qF -- "$dropped" || false
  printf '%s\n' "$stderr" > "$BATS_TEST_TMPDIR/stderr"
  run python3 "$TT" check "$FIXD/hb.kitty-ls.json" "$FIXD/hb.roster.json" "$BATS_TEST_TMPDIR/stderr" 3
  [ "$status" -eq 0 ]
  [ "$output" = "ok windows=6 panes=19" ]
}

@test "discovery: 4-column rows with no group find their recorded tree by session id" {
  dead=99999; while /bin/ps -p "$dead" >/dev/null 2>&1; do dead=$((dead - 1)); done
  hb_copy "$CC_HEARTBEAT_DIR/BOOT/$dead"
  python3 "$TT" rows "$FIXD/hb.roster.json" > "$ROWS"
  [ "$(awk -F'\t' 'NF != 4' "$ROWS" | wc -l | tr -d ' ')" -eq 0 ]
  run --separate-stderr /bin/bash "$LAYOUT" --desktops --restore --dry-run --file "$ROWS"
  [ "$status" -eq 0 ]
  [ ! -f "$KLOG" ]
  [ "$(tree_lines "[0-9]* src=k${dead}w")" -eq 6 ]
  printf '%s\n' "$stderr" > "$BATS_TEST_TMPDIR/stderr"
  run python3 "$TT" check "$FIXD/hb.kitty-ls.json" "$FIXD/hb.roster.json" "$BATS_TEST_TMPDIR/stderr"
  [ "$status" -eq 0 ]
  [ "$output" = "ok windows=6 panes=20" ]
}

@test "discovery: a tree recorded by a kitty that is still running is never replayed" {
  mkdir -p "$BATS_TEST_TMPDIR/live"; ln -s /bin/sleep "$BATS_TEST_TMPDIR/live/kitty"
  "$BATS_TEST_TMPDIR/live/kitty" 300 >/dev/null 2>&1 3>&- &
  live=$!; echo "$live" > "$BATS_TEST_TMPDIR/live.pid"
  i=0; comm=""
  while [ "$i" -lt 50 ]; do comm="$(/bin/ps -p "$live" -o comm= 2>/dev/null)"; [ "${comm%kitty}" = "$comm" ] || break; sleep 0.1; i=$((i + 1)); done
  [ "${comm%kitty}" != "$comm" ]                                   # the precondition the guard keys on
  hb_copy "$CC_HEARTBEAT_DIR/BOOT/$live"
  python3 "$TT" rows "$FIXD/hb.roster.json" > "$ROWS"
  run --separate-stderr /bin/bash "$LAYOUT" --desktops --restore --dry-run --file "$ROWS"
  [ "$status" -eq 0 ]
  [ "$(tree_lines)" -eq 0 ]
  [ "$(printf '%s\n' "$stderr" | grep -cE '^DRY \[CC-DESK-[0-9]+ [^]]*\] (head|vsplit) ')" -eq 20 ]   # still planned, as plain rows
  [ "$(printf '%s\n' "$stderr" | grep -cE '^DRY \[CC-DESK-[0-9]+ k[0-9]+w[0-9]+\]')" -eq 0 ]   # a replayed window is grouped k<pid>w<n>; plain rows by project
  # the same record, once its kitty is gone, is replayed — so the refusal above was the liveness
  kill "$live" 2>/dev/null || true; wait "$live" 2>/dev/null || true
  run --separate-stderr /bin/bash "$LAYOUT" --desktops --restore --dry-run --file "$ROWS"
  [ "$status" -eq 0 ]
  [ "$(tree_lines "[0-9]* src=k${live}w")" -eq 6 ]
}

@test "discovery: a crash event's copy of the heartbeat is found by session id once the heartbeat root has none" {
  dead=99999; while /bin/ps -p "$dead" >/dev/null 2>&1; do dead=$((dead - 1)); done
  hb_copy "$CC_BOOT_RESUME_STATE_DIR/events/E1/hb/$dead"            # the crash page's copy; the root is empty
  python3 "$TT" rows "$FIXD/hb.roster.json" > "$ROWS"
  run --separate-stderr /bin/bash "$LAYOUT" --desktops --restore --dry-run --file "$ROWS"
  [ "$status" -eq 0 ]
  [ "$(tree_lines "[0-9]* src=k${dead}w")" -eq 6 ]
}

@test "discovery: of two dead kitties that recorded the same sessions, the newer arrangement is replayed" {
  old=99999; while /bin/ps -p "$old" >/dev/null 2>&1; do old=$((old - 1)); done
  new=$((old - 1)); while /bin/ps -p "$new" >/dev/null 2>&1; do new=$((new - 1)); done
  hb_copy "$CC_HEARTBEAT_DIR/BOOT/$new"
  hb_copy "$CC_HEARTBEAT_DIR/BOOT/$old"; echo 1784700000 > "$CC_HEARTBEAT_DIR/BOOT/$old/hb.start"
  # the older record has every root pair mirrored: a different arrangement of the same sessions
  python3 -c '
import json, sys
p = sys.argv[1]; d = json.load(open(p))
for o in d:
    for t in o["tabs"]:
        q = t["layout_state"].get("pairs") or {}
        if "one" in q and "two" in q:
            q["one"], q["two"] = q["two"], q["one"]
json.dump(d, open(p, "w"))' "$CC_HEARTBEAT_DIR/BOOT/$old/hb.kitty-ls.json"
  python3 "$TT" rows "$FIXD/hb.roster.json" > "$ROWS"
  run --separate-stderr /bin/bash "$LAYOUT" --desktops --restore --dry-run --file "$ROWS"
  [ "$status" -eq 0 ]
  [ "$(tree_lines "[0-9]* src=k${new}w")" -eq 6 ]
  [ "$(tree_lines "[0-9]* src=k${old}w")" -eq 0 ]
  printf '%s\n' "$stderr" > "$BATS_TEST_TMPDIR/stderr"
  run python3 "$TT" check "$FIXD/hb.kitty-ls.json" "$FIXD/hb.roster.json" "$BATS_TEST_TMPDIR/stderr"
  [ "$status" -eq 0 ]
  [ "$output" = "ok windows=6 panes=20" ]
}

# ── read-back after a replayed splits tab is built (non-dry). Recorded: (a over b) at 60 % on the left
#    as an hsplit, c on the right. $KLOG.lstpl is what `kitty @ ls` shows, written in session ids. ──
small_tree() {
  SM="$BATS_TEST_TMPDIR/small"; mkdir -p "$SM"
  printf '[{"id":6,"platform_window_id":700,"tabs":[{"id":1,"layout":"splits","layout_state":{"class":"Splits","all_windows":{"window_groups":[{"id":1,"window_ids":[11]},{"id":2,"window_ids":[12]},{"id":3,"window_ids":[13]}]},"pairs":{"bias":0.6,"one":{"horizontal":false,"one":1,"two":2},"two":3}},"windows":[{"id":11,"cwd":"/w"},{"id":12,"cwd":"/w"},{"id":13,"cwd":"/w"}]}]}]\n' > "$SM/hb.kitty-ls.json"
  : > "$ROWS"; local s sep="" out=""
  for s in a b c; do
    mkdir -p "$BATS_TEST_TMPDIR/wt-$s"
    printf 'next\tsid-%s\t%s\tbr\n' "$s" "$BATS_TEST_TMPDIR/wt-$s" >> "$ROWS"
  done
  for s in a:11 b:12 c:13; do out="$out$sep{\"session_id\":\"sid-${s%%:*}\",\"paneUUID\":\"${s#*:}\",\"account\":\"next\",\"cwd\":\"/w\",\"name\":\"n\"}"; sep=","; done
  printf '[%s]\n' "$out" > "$SM/hb.roster.json"
}
ls_shows() { # <file> <sid in group 1> <group 2> <group 3> — kitty's answer, same pairs as recorded
  printf '[{"id":1,"platform_window_id":900,"tabs":[{"id":1,"layout":"splits","layout_state":{"class":"Splits","all_windows":{"window_groups":[{"id":1,"window_ids":["@%s@"]},{"id":2,"window_ids":["@%s@"]},{"id":3,"window_ids":["@%s@"]}]},"pairs":{"bias":0.6,"one":{"horizontal":false,"one":1,"two":2},"two":3}},"windows":[{"id":"@%s@"},{"id":"@%s@"},{"id":"@%s@"}]}]}]\n' \
    "$2" "$3" "$4" "$2" "$3" "$4" > "$1"
}
rb_restore() { run --separate-stderr /bin/bash "$LAYOUT" --desktops --restore --to unix:/tmp/cc-fake-sock --tree "$SM/hb.kitty-ls.json" --file "$ROWS"; }
layout_tail() { printf '%s\n' "$output" | sed -n 's/^cc-resume-layout: layout tree_windows=1 .* \(tree_ok=.*\)$/\1/p'; }
# The read-back's own `ls` calls: those after the last launch and before the first fullscreen toggle.
# Other bare `ls` calls now exist outside that span (R21, 2026-10-21): the snapshot before any
# launch, the fullscreen pass's window lookup, and the stray-window pass after it.
readback_ls() { awk '/ launch / { n = 0; next } /toggle_fullscreen/ { exit } / ls$/ { n++ } END { print n + 0 }' "$KLOG"; }

@test "read-back: a tab that reads back as planned is verdict=ok and no kitten is sent" {
  small_tree; ls_shows "$KLOG.lstpl" sid-a sid-b sid-c
  rb_restore
  [ "$status" -eq 0 ]
  [ "$(grep -c ' launch ' "$KLOG")" -eq 3 ]
  [ "$(readback_ls)" -eq 1 ]                                      # the read-back; the fullscreen step's `ls --match id:<head>` is not one
  [ "$(printf '%s\n' "$output" | grep '^cc-resume-layout: tree-verify ')" = 'cc-resume-layout: tree-verify oswin=1 tab=0 verdict=ok' ]
  ! grep -q ' kitten ' "$KLOG" || false
  [ "$(layout_tail)" = 'tree_ok=1 tree_fixed=0 tree_mismatch=0 tree_unknown=0' ]
}

@test "read-back: swapped panes send the apply kitten the planned tree in launched window ids; a read-back still wrong is mismatch" {
  small_tree; ls_shows "$KLOG.lstpl" sid-a sid-c sid-b           # b and c came back in each other's place
  rb_restore
  [ "$status" -eq 0 ]
  # the stub's ls never changes, so the read-back after the kitten still differs
  [ "$(printf '%s\n' "$output" | grep '^cc-resume-layout: tree-verify ')" = 'cc-resume-layout: tree-verify oswin=1 tab=0 verdict=mismatch' ]
  [ "$(layout_tail)" = 'tree_ok=0 tree_fixed=0 tree_mismatch=1 tree_unknown=0' ]
  [ "$(readback_ls)" -eq 2 ]                                    # read back again after the kitten
  head_id="$(head -1 "$KLOG.map" | awk '{ print $2 }')"
  grep ' launch ' "$KLOG" | head -1 | grep -q -- '--type=os-window'
  [ "$(grep -c ' kitten ' "$KLOG")" -eq 1 ]
  kl="$(grep ' kitten ' "$KLOG")"
  case "$kl" in *" kitten --match id:$head_id /"*"/kitty-apply-layout.py "*.json) ;; *) false ;; esac
  run python3 "$TT" spec "$KLOG.spec" "$SM/hb.kitty-ls.json" "$SM/hb.roster.json" "$KLOG.map"
  [ "$status" -eq 0 ]; [ "$output" = spec-ok ]
}

@test "read-back: when the second read-back matches the plan the verdict is fixed, not the kitten's word" {
  small_tree; ls_shows "$KLOG.lstpl" sid-a sid-c sid-b
  ls_shows "$KLOG.lstpl.after" sid-a sid-b sid-c                 # after the kitten, ls shows the plan
  rb_restore
  [ "$status" -eq 0 ]
  [ "$(grep -c ' kitten ' "$KLOG")" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep '^cc-resume-layout: tree-verify ')" = 'cc-resume-layout: tree-verify oswin=1 tab=0 verdict=fixed' ]
  [ "$(layout_tail)" = 'tree_ok=0 tree_fixed=1 tree_mismatch=0 tree_unknown=0' ]
}

@test "read-back: an unreadable kitty @ ls is verdict=unknown, counted apart from mismatch, and no kitten is sent" {
  small_tree; printf 'not json\n' > "$KLOG.lstpl"
  rb_restore
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep '^cc-resume-layout: tree-verify ')" = 'cc-resume-layout: tree-verify oswin=1 tab=0 verdict=unknown' ]
  [ "$(layout_tail)" = 'tree_ok=0 tree_fixed=0 tree_mismatch=0 tree_unknown=1' ]
  ! grep -q ' kitten ' "$KLOG" || false
}
