#!/usr/bin/env bats
# bin/cc-lr — the limit-recovery front end: find · recover · status · repair
# (LIMIT_RECOVER_100P W5-D). Hermetic: a fixture state store, a stub cc-find, a stub lr-fleet.sh,
# a stub launchctl, and never the real ~/.reso store.
#
# NOT tests/cc-lr.bats. THAT file is bin/cc-find's suite (276 lines, FIND="$REPO/bin/cc-find" at
# :15) and the plan's own log calls it "cc-lr 15/15", which is how the name came to be reused. Two
# suites, two subjects; this one never touches that file's fixtures or its walltime case.
#
# WHAT THIS SUITE IS FOR. cc-lr's whole value is THREE REFUSALS that exist nowhere else in the
# tree: a TEAMMATE, an AMBIGUOUS ref, and a session that is not LIMITED. Verified on the tree
# 2026-09-20 — `lr-fleet.sh --one` checks exactly one precondition, "already TRANSPLANTED"
# (:800-803, :828), and has no teammate guard at all. So every one of those refusals is untested
# surface the moment nothing dies on its mutant, which is why each has a case here AND a mutation
# arm recorded in the wave report.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LR="$REPO/bin/cc-lr"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"; mkdir -p "$LR_STATE_DIR"
  SID="aaaaaaaa-1111-4000-8000-000000000001"
  SID2="bbbbbbbb-2222-4000-8000-000000000002"
  MUTEX="$LR_STATE_DIR/runs/by-sid/$SID.active"
  REQ="$LR_STATE_DIR/requests"
  # Stubs, always — a case that reached the real resolver would be reading the operator's live
  # fleet, and a case that reached the real lr-fleet would RECOVER A PANE from a test run.
  export CC_LR_FIND_BIN="$BATS_TEST_TMPDIR/cc-find"
  export CC_LR_FLEET_BIN="$BATS_TEST_TMPDIR/lr-fleet.sh"
  export CC_LR_POLLER_LABEL="com.reso.lr-reset-poller"
  STUBBIN="$BATS_TEST_TMPDIR/stubbin"; mkdir -p "$STUBBIN"
  PATH="$STUBBIN:$PATH"; export PATH
  fleet_stub 0
  launchctl_stub 0
}

# ── stubs ──────────────────────────────────────────────────────────────────────────────────────
find_stub() { # <rc> <TSV rows…>  — cc-find's contract: rc 0 resolved · 1 no match · 2 AMBIGUOUS
  local rc="$1"; shift
  { echo '#!/usr/bin/env bash'
    echo "printf '%s' \"\$*\" >> \"$BATS_TEST_TMPDIR/find.argv\""
    local r
    for r in "$@"; do printf 'printf %s\n' "'$r\n'"; done
    echo "exit $rc"
  } > "$CC_LR_FIND_BIN"
  chmod +x "$CC_LR_FIND_BIN"
}
fleet_stub() { # <rc> — records its argv; prints the two lines lr-fleet.sh:764-765 prints
  local rc="$1"
  { echo '#!/usr/bin/env bash'
    echo "printf '%s\\n' \"\$*\" >> \"$BATS_TEST_TMPDIR/fleet.argv\""
    echo 'echo "lr-fleet: DETACHED — driver pid 424242 is recovering aaaaaaaa; the verdict arrives as mail. END YOUR TURN; do not poll."'
    echo "echo \"run=$LR_STATE_DIR/fleet/one-20260919T175207Z log=$LR_STATE_DIR/fleet/one-20260919T175207Z/detached.log\""
    echo "exit $rc"
  } > "$CC_LR_FLEET_BIN"
  chmod +x "$CC_LR_FLEET_BIN"
}
launchctl_stub() { # <rc>
  { echo '#!/usr/bin/env bash'
    echo "printf '%s\\n' \"\$*\" >> \"$BATS_TEST_TMPDIR/launchctl.argv\""
    echo "exit $1"
  } > "$STUBBIN/launchctl"
  chmod +x "$STUBBIN/launchctl"
}
bundle() { # <sid> <stamp> <state>… — one events.jsonl, one line per state given
  local sid="$1" stamp="$2" d s; shift 2
  d="$LR_STATE_DIR/$sid/bundle-$stamp"; mkdir -p "$d"
  : > "$d/events.jsonl"
  for s in "$@"; do
    printf '{"ts":"2026-09-19T17:00:00Z","run":"%s","state":"%s","stage":"st","detail":"detail-of-%s","writer":"t:1","attempt":"1"}\n' \
      "$d" "$s" "$s" >> "$d/events.jsonl"
  done
  printf '%s' "$d"
}
row() { # <sid> <pane> <class> — one cc-find output row
  printf '%s\t%s\tclaude-next\t%s/.claude-next\t%s/wt\tLIVE\t%s' "$1" "$2" "$HOME" "$HOME" "$3"
}
nlines() { printf '%s\n' "$1" | grep -c '[^[:space:]]'; }

# ══ find — a passthrough, never a second spelling of the resolver ═══════════════════════════════
@test "find execs cc-find with verbatim argv and relays its rc" {
  find_stub 2 "x	1	a	b	c	LIVE	LIMITED"
  run bash "$LR" find --tuple '(2) 27% · claude-infrastructure · xhigh'
  [ "$status" -eq 2 ]
  [ "$(cat "$BATS_TEST_TMPDIR/find.argv")" = "--tuple (2) 27% · claude-infrastructure · xhigh" ]
}

# ══ recover — the three refusals, each of which exists NOWHERE downstream ═══════════════════════
@test "recover REFUSES a teammate with rc 2 and creates no mutex" {
  # RULE 0. cc-find classes it; lr-fleet --one would recover it. This refusal is the only one.
  find_stub 0 "$(row "$SID" 130 TEAMMATE)"
  run bash "$LR" recover 130
  [ "$status" -eq 2 ]
  # ASSERT RULE 0's OWN MESSAGE, not just "TEAMMATE appears somewhere". A teammate is also not
  # LIMITED, so deleting RULE 0 leaves RULE 2 refusing the same ref with the same rc and the same
  # word in its text — measured: that mutant SURVIVED a `*TEAMMATE*` assertion. The two refusals
  # mean different things to the operator and only one of them is the unrecoverable mistake, so
  # the message is the discriminator and RULE 0 must be the arm that speaks.
  [[ "$output" == *"lead-owned"* ]] || false
  [[ "$output" != *"not LIMITED"* ]] || false
  [ ! -d "$MUTEX" ]
  [ ! -e "$BATS_TEST_TMPDIR/fleet.argv" ]
}

@test "recover REFUSES an ambiguous ref with rc 2, prints every candidate, creates no mutex" {
  find_stub 2 "$(row "$SID" 122 LIMITED)" "$(row "$SID2" 124 LIMITED)"
  run bash "$LR" recover cb
  [ "$status" -eq 2 ]
  [[ "$output" == *AMBIGUOUS* ]] || false
  [[ "$output" == *"$SID"* ]] || false
  [[ "$output" == *"$SID2"* ]] || false
  [ ! -d "$MUTEX" ]
  [ ! -e "$BATS_TEST_TMPDIR/fleet.argv" ]
}

@test "recover REFUSES a session that is not LIMITED with rc 2 and creates no mutex" {
  find_stub 0 "$(row "$SID" 117 SESSION)"
  run bash "$LR" recover 117
  [ "$status" -eq 2 ]
  [[ "$output" == *"not LIMITED"* ]] || false
  [ ! -d "$MUTEX" ]
  [ ! -e "$BATS_TEST_TMPDIR/fleet.argv" ]
}

@test "recover REFUSES two rows at rc 0 — a recovery target is exactly one session" {
  # cc-find's bare-ref paths return rc 2 for a tie, but --kw and --limited return a LIST at rc 0.
  # A front end that read row 1 of a list would recover whichever session sorted first.
  find_stub 0 "$(row "$SID" 117 LIMITED)" "$(row "$SID2" 118 LIMITED)"
  run bash "$LR" recover 117
  [ "$status" -eq 2 ]
  [[ "$output" == *"resolved to 2 rows"* ]] || false
  [ ! -d "$MUTEX" ]
  [ ! -e "$BATS_TEST_TMPDIR/fleet.argv" ]
}

@test "recover relays cc-find's rc 1 — nothing matched is not a refusal and not a recovery" {
  # rc 1 and rc 2 mean different things to the caller (retype the ref vs. disambiguate it), and
  # collapsing them is how a typo reads as an ambiguity forever.
  find_stub 1
  run bash "$LR" recover 404
  [ "$status" -eq 1 ]
  [ ! -d "$MUTEX" ]
  [ ! -e "$BATS_TEST_TMPDIR/fleet.argv" ]
}

@test "recover on a LIMITED session takes the mutex, fires --one … --detach, prints three lines" {
  find_stub 0 "$(row "$SID" 117 LIMITED)"
  run bash "$LR" recover 117 --target next3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(nlines "$output")" -eq 3 ]
  [ -d "$MUTEX" ]
  [ "$(cat "$BATS_TEST_TMPDIR/fleet.argv")" = "--one $SID --target next3 --source-pane 117 --detach" ]
  # Line 3 names the ONE next command, and its id is the BUNDLE path — see the report: the bundle
  # is minted by lr-handoff.sh INSIDE the detached driver, so at fire time only its root exists.
  [[ "$(printf '%s\n' "$output" | sed -n 3p)" == *"$LR_STATE_DIR/$SID/bundle-"* ]] || false
  [[ "$(printf '%s\n' "$output" | sed -n 3p)" == *"cc-lr status aaaaaaaa"* ]] || false
  # The holder must name the DRIVER's pid, not this process's: this one exits immediately, and a
  # mutex naming a dead pid is stolen by the next caller — which for a live recovery is the split
  # brain the mutex exists to prevent.
  grep -q '"pid":424242' "$MUTEX/holder"
}

@test "recover REFUSES when the mutex is held by a LIVE pid, and fires nothing" {
  mkdir -p "$MUTEX"
  printf '{"sid":"%s","pane":"117","pid":%d,"ts":"t","by":"x"}\n' "$SID" "$$" > "$MUTEX/holder"
  find_stub 0 "$(row "$SID" 117 LIMITED)"
  run bash "$LR" recover 117
  [ "$status" -eq 2 ]
  [[ "$output" == *"already being recovered by pid $$"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/fleet.argv" ]
}

@test "recover STEALS a mutex whose holder pid is dead" {
  # THE FIXTURE CLOSES THE WORLD RATHER THAN ASSUMING IT. A hardcoded "impossible" pid is a claim
  # about a namespace that WRAPS (repo lesson: a-fixture-s-pid-range-is-a-claim-…). Reap a real
  # child instead, and assert the precondition before trusting it.
  local dead
  bash -c 'exit 0' & dead=$!
  wait "$dead" 2>/dev/null || true
  kill -0 "$dead" 2>/dev/null && skip "pid $dead was recycled between reap and check"
  mkdir -p "$MUTEX"
  printf '{"sid":"%s","pane":"117","pid":%d,"ts":"t","by":"x"}\n' "$SID" "$dead" > "$MUTEX/holder"
  find_stub 0 "$(row "$SID" 117 LIMITED)"
  run bash "$LR" recover 117
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"which is DEAD — stealing it"* ]] || false
  [ -e "$BATS_TEST_TMPDIR/fleet.argv" ]
}

@test "recover REFUSES an unlabelled mutex under the TTL and steals it over the TTL" {
  mkdir -p "$MUTEX"                     # no holder file: a driver that has not written one yet
  find_stub 0 "$(row "$SID" 117 LIMITED)"
  run env CC_LR_MUTEX_TTL_S=3600 bash "$LR" recover 117
  [ "$status" -eq 2 ]
  [[ "$output" == *"names no pid"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/fleet.argv" ]
  run env CC_LR_MUTEX_TTL_S=0 bash "$LR" recover 117
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"with no holder — stealing it"* ]] || false
}

@test "recover RELEASES the mutex when lr-fleet refuses, so the next attempt is not blocked" {
  fleet_stub 2
  find_stub 0 "$(row "$SID" 117 LIMITED)"
  run bash "$LR" recover 117
  [ "$status" -eq 2 ]
  [ ! -d "$MUTEX" ]
}

@test "recover omits --source-pane when no pane is known, and honours an explicit one" {
  find_stub 0 "$(row "$SID" - LIMITED)"
  run bash "$LR" recover "$SID"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$BATS_TEST_TMPDIR/fleet.argv")" = "--one $SID --target auto --detach" ]
  rm -rf "$MUTEX" "$BATS_TEST_TMPDIR/fleet.argv"
  run bash "$LR" recover "$SID" --source-pane 999
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$BATS_TEST_TMPDIR/fleet.argv")" = "--one $SID --target auto --source-pane 999 --detach" ]
}

# ══ status — the state store's second production reader ═════════════════════════════════════════
@test "status renders the LAST state per run, newest run first" {
  bundle "$SID" 20260919T170000Z probed admitted >/dev/null
  bundle "$SID" 20260919T180000Z probed submitted >/dev/null
  run bash "$LR" status --all
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(printf '%s\n' "$output" | sed -n 2p)" == *"bundle-20260919T180000Z"* ]] || false
  [[ "$(printf '%s\n' "$output" | sed -n 2p)" == *submitted* ]] || false
  [[ "$(printf '%s\n' "$output" | sed -n 3p)" == *"bundle-20260919T170000Z"* ]] || false
  [[ "$(printf '%s\n' "$output" | sed -n 3p)" == *admitted* ]] || false
  [[ "$output" == *"2 runs under the state store"* ]] || false
}

@test "status: a terminal state is STICKY against a later non-terminal line from a stale writer" {
  # lr-lib.sh's own contract at the head of lr_state_append: readers take the LAST line, and a
  # terminal line is sticky against a later NON-terminal one. Without it a crashed-then-restarted
  # writer's `probed` erases a FAILED verdict and the run renders healthy.
  bundle "$SID" 20260919T170000Z probed "FAILED:submit" probed >/dev/null
  run bash "$LR" status "$SID"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"FAILED:submit"* ]] || false
  [[ "$output" != *" probed "* ]] || false
}

@test "status: a later terminal state still replaces an earlier one" {
  bundle "$SID" 20260919T170000Z "FAILED:submit" RECOVERED >/dev/null
  run bash "$LR" status "$SID"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *RECOVERED* ]] || false
  [[ "$output" != *"FAILED:submit"* ]] || false
}

@test "status: with a stale line trailing TWO terminals, the LAST terminal is the one that shows" {
  # The case above cannot see a "first terminal sticks" defect: its last line IS terminal, so the
  # stickiness branch never runs — measured, that mutant SURVIVED it. Only a trailing NON-terminal
  # line forces the branch to choose between the two terminals, and the answer is the later one:
  # a run that failed and then recovered has recovered.
  bundle "$SID" 20260919T170000Z "FAILED:submit" RECOVERED probed >/dev/null
  run bash "$LR" status "$SID"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *RECOVERED* ]] || false
  [[ "$output" != *"FAILED:submit"* ]] || false
  [[ "$output" != *" probed "* ]] || false
}

@test "status: NEXT names cc-lr repair for a failed or parked run, and nothing for a healthy one" {
  local b
  b="$(bundle "$SID" 20260919T170000Z probed "FAILED:relaunch:gate")"
  bundle "$SID2" 20260919T171000Z probed PARKED >/dev/null
  bundle "$SID2" 20260919T172000Z probed submitted >/dev/null
  run bash "$LR" status --all
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"→ cc-lr repair $b"* ]] || false
  [[ "$output" == *"→ cc-lr repair $LR_STATE_DIR/$SID2/bundle-20260919T171000Z"* ]] || false
  [ "$(printf '%s\n' "$output" | grep -c 'cc-lr repair')" -eq 2 ]
}

@test "status is rc 1 and prints no table when the store holds no matching run" {
  run bash "$LR" status --all
  [ "$status" -eq 1 ]
  [[ "$output" != *"CAUSE / NEXT"* ]] || false
  bundle "$SID" 20260919T170000Z probed >/dev/null
  run bash "$LR" status ffffffff
  [ "$status" -eq 1 ]
}

@test "status forks jq ONCE and stat ONCE over 20 bundles — the load-invariant half of the budget" {
  # What makes a store reader slow is never the box: it is a fork per run. cc-find's own suite
  # makes exactly this argument (37 rows / 37 jq forks / 0.399 s against a 0.3 s budget), and a
  # process count is the one half of a latency claim no amount of contention can move.
  local i n
  for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20; do
    bundle "$SID" "202609190000${i}Z" probed admitted submitted >/dev/null
  done
  for n in jq stat; do
    { echo '#!/usr/bin/env bash'
      echo "echo x >> \"$BATS_TEST_TMPDIR/$n.calls\""
      echo "exec /usr/bin/env -i PATH=/usr/bin:/bin HOME=\"\$HOME\" \"\$(PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin command -v $n)\" \"\$@\""
    } > "$STUBBIN/$n"
    chmod +x "$STUBBIN/$n"
  done
  run bash "$LR" status --all
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"20 runs under the state store"* ]] || false
  [ "$(wc -l < "$BATS_TEST_TMPDIR/jq.calls" | tr -d ' ')" -eq 1 ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/stat.calls" | tr -d ' ')" -eq 1 ]
}

@test "status renders 20 bundles inside its budget — judged only on a quiet box" {
  # THE TIMING HALF, load-guarded. A wall-clock verdict on a saturated box is a fact about the BOX:
  # this project has burned two rounds on load-fragile timing cases, so above the judged band the
  # number is PRINTED and not judged, and the fork-count case above carries the load-invariant half.
  local i t0 t1
  for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20; do
    bundle "$SID" "202609190000${i}Z" probed admitted submitted >/dev/null
  done
  cat > "$BATS_TEST_TMPDIR/budget.py" <<'JUDGE'
import os, sys
d = float(sys.argv[2]) - float(sys.argv[1])
lpc = os.getloadavg()[0] / (os.cpu_count() or 1)
print("cc-lr status: %.3f s at load/core %.2f" % (d, lpc), file=sys.stderr)
if lpc >= float(os.environ.get("CC_LR_JUDGE_MAX_LPC", "1.0")):
    print("  (box not quiet — timing printed, not judged; the fork-budget case carries the"
          " load-invariant half of the claim)", file=sys.stderr)
    sys.exit(0)
sys.exit(0 if d <= float(os.environ.get("CC_LR_BUDGET_S", "0.1")) else 1)
JUDGE
  t0=$(python3 -c 'import time;print(time.time())')
  run bash "$LR" status --all
  t1=$(python3 -c 'import time;print(time.time())')
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  python3 "$BATS_TEST_TMPDIR/budget.py" "$t0" "$t1"
}

# ══ repair — writes a request, kicks the daemon, NEVER types ════════════════════════════════════
@test "repair writes the schema lr-reset-poller.sh reads, plus the mode field" {
  local b
  b="$(bundle "$SID" 20260919T170000Z probed "FAILED:submit")"
  run env CC_PANE_ID=w0t0p9 bash "$LR" repair "$b"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local f; f="$REQ/cc-lr-repair-$SID.json"
  [ -f "$f" ]
  # .sid is REQUIRED by its consumer (lr-reset-poller.sh:674-675): absent, the request is renamed
  # .malformed.json and LOST, not retried.
  [ "$(jq -r .sid "$f")" = "$SID" ]
  [ "$(jq -r .target "$f")" = auto ]
  [ "$(jq -r .requested_by "$f")" = w0t0p9 ]
  [ "$(jq -r .mode "$f")" = relaunch ]
  [ "$(jq -r 'has("source_pane")' "$f")" = true ]
  # write-then-rename: the poller globs $REQUESTS/*.json and must never read a half-written file,
  # so no temp may survive — and the temp is a DOTFILE with a .tmp suffix, which that glob cannot
  # match on either axis.
  local t leftover=""
  for t in "$REQ"/.*.tmp "$REQ"/*.tmp; do [ -e "$t" ] && leftover="$leftover $t"; done
  [ -z "$leftover" ] || { echo "left behind:$leftover"; false; }
}

@test "repair's destination is placed ONLY by a rename from a dotfile temp" {
  # A STRUCTURAL ARM, and it is here because the property is about an INTERVAL no external test can
  # sample: "no partially written file ever matches the poller's $REQUESTS/*.json glob". Measured —
  # a mutant that writes straight to the destination SURVIVES every behavioural arm, because the
  # error path's own `rm -f "$tmp"` then cleans the destination too. So assert the shape: the temp
  # is a DOTFILE with a .tmp suffix (unmatched by that glob on either axis) and `mv` is what places
  # the destination. Residual: a rename of $tmp/$dest disarms this without changing behaviour
  # (repo lesson: a-mutation-control-anchors-on-the-subjects-source-text).
  grep -qE 'tmp="\$REQ_DIR/\.cc-lr-repair-' "$LR"
  grep -qE 'mv -f "\$tmp" "\$dest"' "$LR"
  ! grep -qE '^\s*tmp="\$dest"' "$LR" || false
}

@test "repair REFUSES and RELEASES nothing when lr-fleet is unreachable — recover's mutex is freed" {
  # The sibling of the "lr-fleet refuses" case: here the binary cannot be reached at all, which is
  # a different branch and takes the mutex before it finds out.
  find_stub 0 "$(row "$SID" 117 LIMITED)"
  run env CC_LR_FLEET_BIN="$BATS_TEST_TMPDIR/does-not-exist" bash "$LR" recover 117
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot reach lr-fleet.sh"* ]] || false
  [ ! -d "$MUTEX" ]
}

@test "repair leaves NO request behind when the write itself fails" {
  # WRITE-THEN-RENAME is the property, and a leftover-tmp check cannot see its absence: a mutant
  # that writes straight to the destination also leaves no tmp. Break the write instead — the
  # destination must not exist, because the poller's drain globs it the moment it does and a
  # half-written request is one it renames .malformed.json and LOSES.
  local b; b="$(bundle "$SID" 20260919T170000Z probed)"
  { echo '#!/usr/bin/env bash'
    echo 'printf "{\"sid\":\"trunc" ; exit 1'
  } > "$STUBBIN/jq"
  chmod +x "$STUBBIN/jq"
  run bash "$LR" repair "$b"
  [ "$status" -eq 2 ]
  [ ! -e "$REQ/cc-lr-repair-$SID.json" ]
  local t leftover=""
  for t in "$REQ"/.*.tmp "$REQ"/*.tmp; do [ -e "$t" ] && leftover="$leftover $t"; done
  [ -z "$leftover" ] || { echo "left behind:$leftover"; false; }
}

@test "repair accepts a sid8 and resolves it to that session's NEWEST bundle" {
  bundle "$SID" 20260919T170000Z probed >/dev/null
  local newest; newest="$(bundle "$SID" 20260919T180000Z probed)"
  run env CC_PANE_ID=w0t0p9 bash "$LR" repair aaaaaaaa --mode prompt
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r .bundle "$REQ/cc-lr-repair-$SID.json")" = "$newest" ]
  [ "$(jq -r .mode  "$REQ/cc-lr-repair-$SID.json")" = prompt ]
}

@test "repair's requested_by is CC_PANE_ID FIRST, with ITERM_SESSION_ID only as the fallback" {
  # lr-fleet.sh:757-762's ratcheted order. A STALE ITERM_SESSION_ID can sit beside a live
  # CC_PANE_ID after a transplant, and preferring the stale one addresses the WRONG pane.
  local b; b="$(bundle "$SID" 20260919T170000Z probed)"
  run env CC_PANE_ID=w9t9p9 ITERM_SESSION_ID='w0t0p1:STALE-UUID' bash "$LR" repair "$b"
  [ "$status" -eq 0 ]
  [ "$(jq -r .requested_by "$REQ/cc-lr-repair-$SID.json")" = w9t9p9 ]
  rm -f "$REQ"/*.json
  run env -u CC_PANE_ID ITERM_SESSION_ID='w0t0p1:FALLBACK-UUID' bash "$LR" repair "$b"
  [ "$status" -eq 0 ]
  [ "$(jq -r .requested_by "$REQ/cc-lr-repair-$SID.json")" = FALLBACK-UUID ]
}

@test "repair REFUSES a bundle with no derivable sid, and writes nothing" {
  mkdir -p "$BATS_TEST_TMPDIR/loose/bundle-1"
  run bash "$LR" repair "$BATS_TEST_TMPDIR/loose/bundle-1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot be derived"* ]] || false
  [ ! -d "$REQ" ] || [ -z "$(ls -A "$REQ")" ]
}

@test "repair REFUSES an unknown mode and an unresolvable ref, and writes nothing" {
  local b; b="$(bundle "$SID" 20260919T170000Z probed)"
  run bash "$LR" repair "$b" --mode retype
  [ "$status" -eq 2 ]
  [[ "$output" == *"neither 'relaunch' nor 'prompt'"* ]] || false
  run bash "$LR" repair ffffffff
  [ "$status" -eq 2 ]
  # ASSERT THE ARM'S OWN MESSAGE. Deleting this refusal lets an unresolvable ref fall through to
  # the sid-uuid guard one line below, which refuses it too, with the same rc — measured, that
  # mutant SURVIVED a bare rc-2 assertion. The messages tell the operator different things
  # ("that ref names no run here" vs "that path is not under a session dir"), so the message is
  # the only discriminator the arm has.
  [[ "$output" == *"neither a bundle directory nor a sid"* ]] || false
  [ ! -d "$REQ" ] || [ -z "$(ls -A "$REQ")" ]
}

@test "repair kicks with kickstart and NO -k, and a failing kick is non-fatal" {
  # `-k` KILLS a running poller first, and a tick that is mid-transplant is exactly the one a
  # caller has just enqueued work for (lr-fleet.sh:893-896 makes the same argument).
  local b; b="$(bundle "$SID" 20260919T170000Z probed)"
  run bash "$LR" repair "$b"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/launchctl.argv")" = "kickstart gui/$(id -u)/com.reso.lr-reset-poller" ]
  rm -f "$REQ"/*.json "$BATS_TEST_TMPDIR/launchctl.argv"
  launchctl_stub 3
  run bash "$LR" repair "$b"
  [ "$status" -eq 0 ]                      # the request is on disk; the poller's interval drains it
  [ -f "$REQ/cc-lr-repair-$SID.json" ]
  [[ "$output" == *"the kick failed"* ]] || false
  [[ "$output" == *"launchctl kickstart gui/$(id -u)/com.reso.lr-reset-poller"* ]] || false
}

# ══ the iron rule ══════════════════════════════════════════════════════════════════════════════
# THE RATCHET IS A FUNCTION SO IT CAN BE POSITIVE-CONTROLLED. A grep that has never once gone red
# is a grep nobody has shown to be live (memory: unfixed-file-is-not-a-sound-file), and this one
# guards the property that matters most on this surface: cc-lr is reached from a screenshot.
iron_rule() { # <file> → rc 0 clean, rc 1 a banned verb is present
  local f="$1" body
  body="$(grep -vE '^[[:space:]]*#' "$f")"
  # NEVER KILLS. `kill -0` is a READ of the process table — it is the mutex's liveness oracle and
  # is the ONE spelling allowed; every other signal, and pkill/killall at all, is banned. Matched
  # with -o then filtered, because an E-regex has no lookahead and a blanket `kill` ban would
  # convict the oracle.
  printf '%s' "$body" | grep -qE '(^|[^a-zA-Z_.-])(pkill|killall)[[:space:]]' && return 1
  printf '%s' "$body" | grep -oE '(^|[^a-zA-Z_.-])kill[[:space:]]+[^[:space:]]+' \
    | grep -qvE 'kill[[:space:]]+-0$' && return 1
  # never ships, never deploys
  printf '%s' "$body" | grep -qE 'ship-land|deploy-live' && return 1
  # NEVER TYPES INTO A PANE — the property that matters most here: cc-lr is reached from a
  # screenshot, i.e. from the one moment an operator can least audit what happens next.
  printf '%s' "$body" | grep -qE 'send-text|send-key|send_text|osascript|cc-pane[[:space:]]+send|it2[[:space:]]+session[[:space:]]+(send|run)|tui-submit|(^|[^a-z-])expect[[:space:]]' && return 1
  # never mutates git
  printf '%s' "$body" | grep -qE 'git[[:space:]]+(commit|push|merge|reset|checkout|rebase|clean)' && return 1
  # LAUNCHCTL ONLY AS `kickstart`, AND NEVER WITH `-k`. Same -o-then-filter shape: every launchctl
  # VERB in the file must be kickstart — `load`/`unload`/`bootout`/`bootstrap` are not this tool's
  # to run, and `-k` KILLS a running poller, which is exactly the tick a caller just enqueued for.
  printf '%s' "$body" | grep -oE 'launchctl[[:space:]]+[a-z][a-z-]*' \
    | grep -qvE 'launchctl[[:space:]]+kickstart$' && return 1
  printf '%s' "$body" | grep -qE 'kickstart[[:space:]]+-k' && return 1
  return 0
}

@test "iron rule: cc-lr never types, never kills, never touches git, and launchctl only kickstarts" {
  iron_rule "$LR"
  # `kill -0` is a READ of the process table and is the mutex's liveness oracle; it is the one
  # `kill` spelling allowed, so assert it is still the only one present.
  [ "$(grep -cE '(^|[^a-zA-Z_.-])kill[[:space:]]' "$LR")" -eq "$(grep -cE 'kill -0' "$LR")" ]
}

@test "iron rule POSITIVE CONTROL: the ratchet trips on each banned verb, so it is not decorative" {
  local v f
  f="$BATS_TEST_TMPDIR/mutant"
  for v in 'pkill -9 "$pid"' \
           'kill -9 "$hpid"' \
           'osascript -e beep' \
           'it2 session send CR' \
           'git checkout -- .' \
           'launchctl bootout gui/501/x' \
           'launchctl kickstart -k gui/501/x' \
           'bash scripts/ship-land.sh'; do
    cp "$LR" "$f"
    printf '%s\n' "$v" >> "$f"
    run iron_rule "$f"
    [ "$status" -eq 1 ] || { echo "the ratchet did NOT trip on: $v"; false; }
  done
  # and the unmutated copy is clean, so the control is measuring the mutation and not the copy
  cp "$LR" "$f"
  run iron_rule "$f"
  [ "$status" -eq 0 ]
}

# ══ argv ═══════════════════════════════════════════════════════════════════════════════════════
@test "an unknown subcommand and a bare ref are rc 3 usage, never a silent recovery" {
  run bash "$LR" 117
  [ "$status" -eq 3 ]
  [[ "$output" == *"unknown subcommand"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/fleet.argv" ]
  run bash "$LR"
  [ "$status" -eq 3 ]
}
