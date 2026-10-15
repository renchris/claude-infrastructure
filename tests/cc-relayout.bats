#!/usr/bin/env bats
# bin/cc-relayout: move RUNNING Claude panes back into the OS window, tab and split position a
# recorded heartbeat tree had them in, without restarting them.
#
# Contracts under test, each read from what the tool sends kitty or prints, never from its internals:
#   · plan: a live pane is joined to its recorded session through the session registry (rows of THIS
#     kitty only) or, failing that, through the one session id in its command line; the recorded tab
#     is mapped to the live tab already holding most of its panes, and every other pane is a move;
#   · apply: each move is ONE `detach-window --match id:<pane> --target-tab id:<tab>`, then the
#     apply-layout kitten gets a spec whose pairs are the recorded tree in LIVE window ids; the verdict
#     is the read-back of `kitty @ ls`, not the kitten's word;
#   · refusal: an OS window a pane leaves or joins that reads fullscreen, or whose state cannot be
#     read, stops the run before anything is sent (exit 3) — the 2026-10-15 kitty crash shape;
#   · usage: --to must be a unix: socket (exit 2), and nothing is sent;
#   · a recorded session that is not live is left out and its sibling takes its place.
#
# Fixture (tests/fixtures/cc-relayout/): a recorded tree of ONE OS window, ONE splits tab, three
# sessions A B C as H:0.7(A, V(B, C)) in recorded window ids 4 5 6; a live `kitty @ ls` where A (11)
# and B (12) sit in tab 10 of OS window 1 (platform 601) and C (21) in tab 20 of OS window 2 (602),
# beside a shell (22). A and C join through registry rows; B only through its command line, and a
# decoy registry row from ANOTHER kitty points B at the shell 22.
#
# RED-proof: at HEAD~3 (before bc9d782ea) bin/cc-relayout does not exist: run in a scratch copy of
# this tree at that state every case fails at its first `[ "$status" -eq … ]` (status 127, command
# not found). On a scratch COPY of the current tree with cc-relayout's `if blocked:` turned into
# `if False:` (the fullscreen/unreadable refusal removed), cases 3, 4, 5 and 5b fail at
# `[ "$status" -eq 3 ]`: the run goes on, sends detach-window and the kitten, and exits 1 on the
# read-back. The other cases stay green, so those fail for the intended reason. Case 5b
# fails on 13993a836's cc-relayout (the window with no platform id was skipped): exit 1, moves sent.
# Cases 8, 8b and 11 fail on cebafa946's cc-relayout (review 2026-10-15): a stale registry row put
# session A on the shell pane 22 (plan tree H:0.700(22,…)); a session on two panes was resolved by
# dict order instead of refused; two recorded shells in one directory both became live pane 13.
#
# Hermetic: HOME, TMPDIR, the registry, the pane-spawn log and the swift probe are per-test; kitty
# and swift are recording stubs; no case talks to a real kitty or reads the real screen.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  FIXD="$BATS_TEST_DIRNAME/fixtures/cc-relayout"
  SUBJ="$REPO/bin/cc-relayout"
  TREE="$FIXD/hb.kitty-ls.json"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  export CC_SPAWN_LOG_FILE="$BATS_TEST_TMPDIR/pane-spawns.jsonl"
  unset KITTY_LISTEN_ON KITTY_PID KITTY_WINDOW_ID
  SA=11111111-1111-4111-8111-111111111111
  SB=22222222-2222-4222-8222-222222222222
  SC=33333333-3333-4333-8333-333333333333
  TO=unix:/tmp/kitty-4242

  # registry: A and C in THIS kitty (4242); a decoy for B from another kitty (9999) naming pane 22
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry"; mkdir -p "$CC_REGISTRY_DIR"
  printf '{"kitty_pid": 4242, "paneUUID": "11", "session_id": "%s"}\n' "$SA" > "$CC_REGISTRY_DIR/a.json"
  printf '{"kitty_pid": 4242, "paneUUID": "21", "session_id": "%s"}\n' "$SC" > "$CC_REGISTRY_DIR/c.json"
  printf '{"kitty_pid": 9999, "paneUUID": "22", "session_id": "%s"}\n' "$SB" > "$CC_REGISTRY_DIR/decoy.json"

  # kitty stub: argv is `@ --to <sock> <cmd> …`; logs every call, answers `ls` from $KLS, keeps a
  # copy of the kitten's spec, and swaps $KLS for $KLS.after (when present) once the kitten ran.
  export KLOG="$BATS_TEST_TMPDIR/kitty.log" KLS="$BATS_TEST_TMPDIR/ls.json"
  cp "$FIXD/live-ls.json" "$KLS"
  export CC_TERM_KITTY="$BATS_TEST_TMPDIR/kitty-stub"
  cat > "$CC_TERM_KITTY" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$KLOG"
case "$4" in
  ls) cat "$KLS" ;;
  launch) echo 901 ;;
  kitten)
    for a in "$@"; do last="$a"; done
    cp "$last" "$KLOG.spec"
    if [ -f "$KLS.after" ]; then mv "$KLS.after" "$KLS"; fi ;;
esac
exit 0
SH
  chmod +x "$CC_TERM_KITTY"

  # swift stub: argv is `<probe.swift> <pwid>…`; logs the pwids and prints an 11-field row for each
  # pwid listed in $SWFS ("<pwid> <fullscreen 0|1>"); a pwid not listed gets no row.
  export SWLOG="$BATS_TEST_TMPDIR/swift.log" SWFS="$BATS_TEST_TMPDIR/swift.fs"
  printf '601 0\n602 0\n' > "$SWFS"
  export CC_HB_SWIFT_BIN="$BATS_TEST_TMPDIR/swift-stub"
  cat > "$CC_HB_SWIFT_BIN" <<'SH'
#!/bin/bash
shift
printf '%s\n' "$*" >> "$SWLOG"
for p in "$@"; do
  fs="$(awk -v p="$p" '$1 == p { print $2 }' "$SWFS")"
  if [ -n "$fs" ]; then
    printf '%s\tFAKE-DISPLAY\t0\t0\t1728\t1117\t%s\t0\t0\t1000\t800\n' "$p" "$fs"
  fi
done
exit 0
SH
  chmod +x "$CC_HB_SWIFT_BIN"
}

# every call the stub logged other than `ls` — the calls that would change something
changes() { grep -v -E "^@ --to $TO ls\$" "$KLOG" || true; }

@test "1. dry run prints the plan (registry + cmdline join, decoy ignored) and sends no change" {
  run "$SUBJ" --to "$TO" --tree "$TREE"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qxF "cc-relayout: record $TREE: 1 tab(s), 3 session(s); 3 of them live in this kitty"
  # the recorded H:0.7(A, V(B, C)) in live ids: A=11, B=12 (cmdline, not the decoy's 22), C=21
  echo "$output" | grep -qxF "cc-relayout: plan rec_os=7 rec_tab=0 -> tab 10 tree=H:0.700(11,V(12,21))"
  [ "$(echo "$output" | grep -c 'plan move ')" -eq 1 ]
  echo "$output" | grep -qxF "cc-relayout: plan move pane=21 sid=$SC from tab=20"
  echo "$output" | grep -qxF "cc-relayout: dry run: 1 move(s), 1 tab(s); nothing changed (add --apply)"
  # the stub log is live (ls was asked), and nothing else was sent
  grep -qxF "@ --to $TO ls" "$KLOG"
  [ -z "$(changes)" ]
  # the probe was asked about exactly the window C leaves (602) and the one it joins (601)
  [ "$(cat "$SWLOG")" = "601 602" ]
}

@test "2. --apply: one detach-window, then the kitten with the recorded tree in live ids; static ls reads back mismatch" {
  run "$SUBJ" --to "$TO" --tree "$TREE" --apply
  [ "$status" -eq 1 ]
  echo "$output" | grep -qxF "cc-relayout: verdict=mismatch moved=1 restarted=0 tabs=1 mismatched=1"
  echo "$output" | grep -qE '^cc-relayout: tab rec_os=7 rec_tab=0 live_tab=10 verdict=mismatch \('
  [ "$(changes | wc -l | tr -d ' ')" -eq 2 ]
  [ "$(changes | sed -n 1p)" = "@ --to $TO detach-window --match id:21 --target-tab id:10" ]
  kl="$(changes | sed -n 2p)"
  spec="${kl##* }"
  [ "$kl" = "@ --to $TO kitten --match id:11 $REPO/scripts/kitty-apply-layout.py $spec" ]
  # expected pairs: the fixture's recorded pairs, group -> window -> session -> live id, by the
  # test's own mapping (A=11, B=12, C=21), not by scripts/lib/kitty_tree.py
  run python3 -c '
import json, sys
fixd, got = sys.argv[1], json.load(open(sys.argv[2]))
tab = json.load(open(fixd + "/hb.kitty-ls.json"))[0]["tabs"][0]
win = {g["id"]: g["window_ids"][0] for g in tab["layout_state"]["all_windows"]["window_groups"]}
sid = {int(r["paneUUID"]): r["session_id"] for r in json.load(open(fixd + "/hb.roster.json"))}
live = dict(zip(sys.argv[3:6], (11, 12, 21)))
def m(x):
    if isinstance(x, dict):
        return {k: (m(v) if k in ("one", "two") else v) for k, v in x.items()}
    return live[sid[win[x]]]
want = m(tab["layout_state"]["pairs"])
print(json.dumps(want, sort_keys=True)); print(json.dumps(got["pairs"], sort_keys=True))
sys.exit(0 if got["pairs"] == want and got["result"] == sys.argv[6] + ".result" else 1)
' "$FIXD" "$KLOG.spec" "$SA" "$SB" "$SC" "$spec"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = '{"bias": 0.7, "one": 11, "two": {"horizontal": false, "one": 12, "two": 21}}' ]
}

@test "2b. --apply: a read-back that matches the record is verdict=ok, exit 0" {
  cp "$FIXD/live-ls-after.json" "$KLS.after"
  run "$SUBJ" --to "$TO" --tree "$TREE" --apply
  [ "$status" -eq 0 ]
  echo "$output" | grep -qxF "cc-relayout: tab rec_os=7 rec_tab=0 live_tab=10 verdict=ok"
  echo "$output" | grep -qxF "cc-relayout: verdict=ok moved=1 restarted=0 tabs=1 mismatched=0"
  [ "$(changes | grep -c -E ' (detach-window|kitten) ')" -eq 2 ]
}

@test "3. the window a pane LEAVES reads fullscreen: refused, exit 3, nothing sent even with --apply" {
  printf '601 0\n602 1\n' > "$SWFS"
  run "$SUBJ" --to "$TO" --tree "$TREE" --apply
  [ "$status" -eq 3 ]
  echo "$output" | grep -qxF "cc-relayout: refuse: OS window 602 reads fullscreen"
  [ "$(echo "$output" | grep -c 'refuse: ')" -eq 1 ]
  echo "$output" | grep -qxF "cc-relayout: verdict=refused moved=0 restarted=0 tabs=1 mismatched=0"
  [ -z "$(changes)" ]
}

@test "4. the window a pane JOINS reads fullscreen: refused, exit 3, nothing sent even with --apply" {
  printf '601 1\n602 0\n' > "$SWFS"
  run "$SUBJ" --to "$TO" --tree "$TREE" --apply
  [ "$status" -eq 3 ]
  echo "$output" | grep -qxF "cc-relayout: refuse: OS window 601 reads fullscreen"
  [ "$(echo "$output" | grep -c 'refuse: ')" -eq 1 ]
  echo "$output" | grep -qxF "cc-relayout: verdict=refused moved=0 restarted=0 tabs=1 mismatched=0"
  [ -z "$(changes)" ]
}

@test "5. fullscreen state unreadable (probe prints nothing): refused, exit 3, nothing sent" {
  : > "$SWFS"
  run "$SUBJ" --to "$TO" --tree "$TREE" --apply
  [ "$status" -eq 3 ]
  echo "$output" | grep -qxF "cc-relayout: refuse: OS window 601 reads unreadable"
  echo "$output" | grep -qxF "cc-relayout: refuse: OS window 602 reads unreadable"
  echo "$output" | grep -qxF "cc-relayout: verdict=refused moved=0 restarted=0 tabs=1 mismatched=0"
  [ "$(cat "$SWLOG")" = "601 602" ]
  [ -z "$(changes)" ]
}

@test "5b. a window with no platform id cannot be probed: refused, exit 3, nothing sent" {
  # Regression (2026-10-15 review): the window C leaves had no platform_window_id, was never probed,
  # and so was never refused — the move went out over a fullscreen state nobody read.
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d[1].pop("platform_window_id", None); json.dump(d, open(sys.argv[1], "w"))' "$KLS"
  run "$SUBJ" --to "$TO" --tree "$TREE" --apply
  [ "$status" -eq 3 ]
  echo "$output" | grep -qxF "cc-relayout: refuse: OS window (no platform id) reads unreadable"
  echo "$output" | grep -qxF "cc-relayout: verdict=refused moved=0 restarted=0 tabs=1 mismatched=0"
  [ -z "$(changes)" ]
}

@test "6. --to that is not a unix: socket is a usage error (exit 2) and kitty is never called" {
  run "$SUBJ" --to /tmp/kitty-4242 --tree "$TREE" --apply
  [ "$status" -eq 2 ]
  echo "$output" | grep -qxF "cc-relayout: --to must be a unix: socket address"
  [ ! -e "$KLOG" ]
}

@test "7. a recorded session that is not live is left out; its sibling takes its place" {
  rm "$CC_REGISTRY_DIR/c.json"
  run "$SUBJ" --to "$TO" --tree "$TREE"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qxF "cc-relayout: record $TREE: 1 tab(s), 3 session(s); 2 of them live in this kitty"
  # V(B, C) collapses to B: the plan's tree has two leaves, A and B, at the recorded 0.7
  echo "$output" | grep -qxF "cc-relayout: plan rec_os=7 rec_tab=0 -> tab 10 tree=H:0.700(11,12)"
  [ "$(echo "$output" | grep -c 'plan move ')" -eq 0 ]
  echo "$output" | grep -qxF "cc-relayout: dry run: 0 move(s), 1 tab(s); nothing changed (add --apply)"
  [ "$(cat "$SWLOG")" = "601" ]
  [ -z "$(changes)" ]
}

# live ls with one window changed: <pane> <key> <json value>
live_with() { python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for o in d:
    for t in o["tabs"]:
        for w in t["windows"]:
            if w["id"] == int(sys.argv[2]):
                w[sys.argv[3]] = json.loads(sys.argv[4])
json.dump(d, open(sys.argv[5], "w"))' "$@"; }

@test "8. a registry row whose process is not alive under its pane is ignored (a stale row)" {
  # A's session, said to be in the shell pane 22 by a row whose pid (1) does not run under that pane
  printf '{"kitty_pid": 4242, "paneUUID": "22", "pid": 1, "session_id": "%s"}\n' "$SA" > "$CC_REGISTRY_DIR/stale.json"
  run "$SUBJ" --to "$TO" --tree "$TREE"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qxF "cc-relayout: plan rec_os=7 rec_tab=0 -> tab 10 tree=H:0.700(11,V(12,21))"
  [ -z "$(changes)" ]
}

@test "8b. a session that two panes claim is refused: exit 3, nothing sent" {
  printf '{"kitty_pid": 4242, "paneUUID": "22", "session_id": "%s"}\n' "$SA" > "$CC_REGISTRY_DIR/twice.json"
  run "$SUBJ" --to "$TO" --tree "$TREE" --apply
  [ "$status" -eq 3 ]
  echo "$output" | grep -qxF "cc-relayout: refuse: session $SA is in more than one pane — which one to move cannot be told"
  echo "$output" | grep -qxF "cc-relayout: verdict=refused moved=0 restarted=0 tabs=0 mismatched=0"
  [ -z "$(changes)" ]
}

@test "9. a moved pane whose process changed is reported as restarted, exit 1" {
  live_with "$FIXD/live-ls-after.json" 21 pid 4999 "$KLS.after"
  run "$SUBJ" --to "$TO" --tree "$TREE" --apply
  [ "$status" -eq 1 ]
  echo "$output" | grep -qxF "cc-relayout: pane 21 sid=$SC: process changed or gone"
  echo "$output" | grep -qxF "cc-relayout: verdict=mismatch moved=1 restarted=1 tabs=1 mismatched=0"
}

@test "10. a pane the record does not know stays in the target tab, to the right of the recorded tree" {
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
t = d[0]["tabs"][0]
t["windows"].append({"id": 13, "pid": 1013, "cwd": "/work/other", "cmdline": ["/bin/zsh"]})
t["layout_state"]["all_windows"]["window_groups"].append({"id": 130, "window_ids": [13]})
t["layout_state"]["pairs"] = {"one": t["layout_state"]["pairs"], "two": 130}
json.dump(d, open(sys.argv[1], "w"))' "$KLS"
  run "$SUBJ" --to "$TO" --tree "$TREE" --apply
  [ "$status" -eq 1 ]                                   # the static ls never reads back as planned
  python3 -c '
import json, sys
got = json.load(open(sys.argv[1]))["pairs"]
want = {"one": {"bias": 0.7, "one": 11, "two": {"horizontal": False, "one": 12, "two": 21}}, "two": 13}
sys.exit(0 if got == want else 1)' "$KLOG.spec"
}

@test "11. two recorded shells in one directory take two distinct live shells, never one pane twice" {
  R="$BATS_TEST_TMPDIR/rec2"; mkdir -p "$R"
  # recorded: H(A, V(shell /work/w, shell /work/w)); live tab 10: A=11 and shells 13, 14 in /work/w
  printf '%s\n' '[{"id": 3, "platform_window_id": 700, "tabs": [{"id": 1, "layout": "splits", "layout_state": {"class": "Splits", "pairs": {"one": 1, "two": {"horizontal": false, "one": 2, "two": 3}}, "all_windows": {"window_groups": [{"id": 1, "window_ids": [4]}, {"id": 2, "window_ids": [5]}, {"id": 3, "window_ids": [6]}]}}, "windows": [{"id": 4, "cwd": "/work/a"}, {"id": 5, "cwd": "/work/w"}, {"id": 6, "cwd": "/work/w"}]}]}]' > "$R/hb.kitty-ls.json"
  printf '[{"session_id": "%s", "paneUUID": "4", "cwd": "/work/a"}]\n' "$SA" > "$R/hb.roster.json"
  printf '%s\n' '[{"id": 1, "platform_window_id": 601, "tabs": [{"id": 10, "layout": "splits", "layout_state": {"class": "Splits", "pairs": {"one": 110, "two": {"one": 130, "two": 140}}, "all_windows": {"window_groups": [{"id": 110, "window_ids": [11]}, {"id": 130, "window_ids": [13]}, {"id": 140, "window_ids": [14]}]}}, "windows": [{"id": 11, "pid": 1011, "cwd": "/work/a", "cmdline": ["claude"]}, {"id": 13, "pid": 1013, "cwd": "/work/w", "cmdline": ["/bin/zsh"]}, {"id": 14, "pid": 1014, "cwd": "/work/w", "cmdline": ["/bin/zsh"]}]}]}]' > "$KLS"
  run "$SUBJ" --to "$TO" --tree "$R/hb.kitty-ls.json"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qxF "cc-relayout: plan rec_os=3 rec_tab=0 -> tab 10 tree=H(11,V(13,14))"
}
