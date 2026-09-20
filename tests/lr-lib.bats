#!/usr/bin/env bats
# scripts/limit-recover/lr-lib.sh — the shared limit-recover predicates (LIMIT_RECOVER_100P).
# Each function here replaced a per-caller re-derivation that had already produced an incident; the
# suite pins the rule each one enforces and the parity between the two copies of the engagement core.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/limit-recover/lr-lib.sh"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"; mkdir -p "$LR_STATE_DIR/locks"
  export LR_LIB_DIR="$REPO/scripts/limit-recover"
  # Ambient-state pins (test-hermeticity ratchet). This suite exercises handoff-fire, whose
  # capacity_gate() refuses a net-new fire above 2.0/core — on this box that is red-by-load, not by
  # subject — and three seams whose defaults do not resolve under $HOME: two absolute /tmp paths and
  # one BARE NAME the subject would execute off the operator's PATH. An ABSENT path is the right
  # value for all three: these sensors fail open on one.
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/handoff-account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  CFG="$BATS_TEST_TMPDIR/cfg-a"; OTHER="$BATS_TEST_TMPDIR/cfg-b"
  SLUG="-Users-x-thing"; mkdir -p "$CFG/projects/$SLUG" "$OTHER/projects/$SLUG"
  SID="aaaa1111-0000-4000-8000-000000000001"
  TX="$CFG/projects/$SLUG/$SID.jsonl"
  # shellcheck disable=SC1090  # the subject under test, resolved from $REPO at run time
  . "$LIB"
}
turn() { # $1=file $2=ts $3=model $4=effort [$5=text]
  printf '{"type":"assistant","timestamp":"%s","effort":"%s","message":{"role":"assistant","model":"%s","content":[{"type":"text","text":"%s"}]}}\n' "$2" "$4" "$3" "${5:-work}" >> "$1"
}
limit() { printf '{"type":"assistant","timestamp":"%s","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 7:50pm"}]}}\n' "$2" >> "$1"; }

# ── tier ──────────────────────────────────────────────────────────────────────────────────────────
@test "tier: the last NON-ERROR turn BEFORE the limit error wins — not argv, not the file tail" {
  turn "$TX" 2026-09-08T22:00:00.000Z claude-opus-5 high
  turn "$TX" 2026-09-08T22:30:00.000Z claude-fable-5-1 xhigh
  limit "$TX" 2026-09-08T23:11:09.000Z
  turn "$TX" 2026-09-09T00:52:00.000Z claude-opus-5 max "a same-account rescuer appending by path"
  run lr_tier_from_transcript "$CFG" "$SID"
  [ "$status" -eq 0 ]; [ "$output" = "claude-fable-5-1 xhigh" ]
}
@test "tier: with no limit error the last turn overall is the tier" {
  turn "$TX" 2026-09-08T22:00:00.000Z claude-opus-5 high
  turn "$TX" 2026-09-08T22:30:00.000Z claude-fable-5-1 max
  run lr_tier_from_transcript "$CFG" "$SID"
  [ "$output" = "claude-fable-5-1 max" ]
}
@test "tier: a transcript already renamed .handed-off is still read" {
  turn "$TX" 2026-09-08T22:00:00.000Z claude-opus-5 high; mv "$TX" "$TX.handed-off"
  run lr_tier_from_transcript "$CFG" "$SID"
  [ "$output" = "claude-opus-5 high" ]
}
@test "tier: nothing on disk is rc 1, never a guess" {
  run lr_tier_from_transcript "$CFG" "$SID"; [ "$status" -eq 1 ]
}

# ── engagement after a baseline, and parity with handoff-fire.sh's resume_engaged ────────────────
@test "engaged: a non-error turn newer than the baseline = 0; older-only = 1; API error = 1" {
  turn "$TX" 2026-09-09T01:00:00.000Z claude-opus-5 high
  run lr_engaged_after "$CFG" "$SID" 2026-09-09T01:04:00; [ "$status" -eq 1 ]
  limit "$TX" 2026-09-09T01:05:00.000Z
  run lr_engaged_after "$CFG" "$SID" 2026-09-09T01:04:00; [ "$status" -eq 1 ]
  turn "$TX" 2026-09-09T01:06:00.000Z claude-opus-5 high
  run lr_engaged_after "$CFG" "$SID" 2026-09-09T01:04:00; [ "$status" -eq 0 ]
}
@test "PARITY: lr_engaged_after and handoff-fire's resume_engaged carry a byte-identical python core" {
  a="$(sed -n '/^lr_engaged_after() {/,/^}/p' "$LIB" | sed -n "/<<'PY'/,/^PY$/p")"
  b="$(sed -n '/^resume_engaged() {/,/^}/p' "$HF" | sed -n "/<<'PY'/,/^PY$/p")"
  [ -n "$a" ] && [ -n "$b" ]
  [ "$a" = "$b" ] || { diff <(printf '%s\n' "$a") <(printf '%s\n' "$b"); false; }
}

# ── liveness from the registry ───────────────────────────────────────────────────────────────────
@test "registry: a row naming the sid with a LIVE pid is a live process; a dead pid is not" {
  printf '{"paneUUID":"616","session_id":"%s","pid":%d,"account":"claude-secondary","cwd":"/x"}\n' "$SID" "$$" > "$CC_REGISTRY_DIR/616.json"
  printf '{"paneUUID":"617","session_id":"%s","pid":4194102,"account":"claude-secondary","cwd":"/x"}\n' "$SID" > "$CC_REGISTRY_DIR/617.json"
  printf '{"paneUUID":"618","session_id":"other","pid":%d}\n' "$$" > "$CC_REGISTRY_DIR/618.json"
  run lr_registry_live_rows "$SID"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = 1 ]
  [[ "$output" == 616$'\t'$$$'\t'claude-secondary$'\t'/x ]] || { echo "$output"; false; }
}
@test "registry: no live row is rc 1" {
  run lr_registry_live_rows "$SID"; [ "$status" -eq 1 ]
}

# ── transplant read ──────────────────────────────────────────────────────────────────────────────
@test "transplanted_to: a lock naming ANOTHER store whose copy exists prints that store" {
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SID" "$CFG" "$OTHER" > "$LR_STATE_DIR/locks/$SID.lock"
  : > "$OTHER/projects/$SLUG/$SID.jsonl"
  run lr_transplanted_to "$SID" "$CFG"
  [ "$status" -eq 0 ]; [ "$output" = "$OTHER" ]
}
@test "transplanted_to: the successor is GONE ⇒ rc 1 (this store's copy is the one to act on)" {
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SID" "$CFG" "$OTHER" > "$LR_STATE_DIR/locks/$SID.lock"
  run lr_transplanted_to "$SID" "$CFG"; [ "$status" -eq 1 ]
}
@test "transplanted_to: asked FROM the target itself ⇒ rc 1 (the target is the successor)" {
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SID" "$CFG" "$OTHER" > "$LR_STATE_DIR/locks/$SID.lock"
  : > "$OTHER/projects/$SLUG/$SID.jsonl"
  run lr_transplanted_to "$SID" "$OTHER"; [ "$status" -eq 1 ]
}

# ── the pane argv shape ──────────────────────────────────────────────────────────────────────────
@test "launch tail: with bin/cc-pane-runner present the window is RUNNER-rooted and the launcher rides in CC_PANE_CMD, non-exec" {
  lr_launch_tail /tmp/lr-launch-x.sh
  [ "$LR_SPAWN_SHAPE" = runner ]
  local joined; joined="$(printf '%s\n' "${LR_LAUNCH_TAIL[@]}")"
  printf '%s\n' "$joined" | grep -qx 'CC_PANE_CMD=bash /tmp/lr-launch-x.sh'
  printf '%s\n' "$joined" | grep -qx 'CC_PANE_CMD_INTERACTIVE=1'
  printf '%s\n' "$joined" | grep -qx 'exec "$CC_PANE_RUNNER"'
  ! printf '%s\n' "$joined" | grep -q 'exec bash'
}
@test "launch tail CONTROL: with no runner anywhere the argv fallback is \`-- /bin/bash <launcher>\`" {
  export LR_LIB_DIR="$BATS_TEST_TMPDIR/nowhere" CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/nowhere" CC_PANE_RUNNER_BIN="$BATS_TEST_TMPDIR/absent"
  lr_launch_tail /tmp/lr-launch-x.sh
  [ "$LR_SPAWN_SHAPE" = argv ]
  [ "${LR_LAUNCH_TAIL[1]}" = /bin/bash ] && [ "${LR_LAUNCH_TAIL[2]}" = /tmp/lr-launch-x.sh ]
}

# ── the kitty spawn: anchored beside the SOURCE, socket-addressed, provenance in --var ──────────
@test "kitty spawn with an anchor: vsplit beside it, --source-window pinned, no focus steal, no --title, provenance in --var" {
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/kitty.log"; echo 777\n' "$BATS_TEST_TMPDIR" > "$STUB/kitty"; chmod +x "$STUB/kitty"
  export CC_TERM_KITTY="$STUB/kitty" CC_TERM_KITTY_TO="unix:/tmp/fake-kitty"
  run lr_kitty_spawn /tmp/lr-launch-x.sh /tmp/wt "$SID" next3 616
  [ "$status" -eq 0 ]; [ "$output" = 777 ]
  log="$(cat "$BATS_TEST_TMPDIR/kitty.log")"
  [[ "$log" == *"@ --to unix:/tmp/fake-kitty launch --type=window --location=vsplit --match window_id:616 --next-to id:616 --source-window id:616 --cwd=current --dont-take-focus"* ]] || { echo "$log"; false; }
  [[ "$log" == *"--var lr_continuation_of=$SID --var lr_source_pane=616 --var lr_target_account=next3"* ]] || { echo "$log"; false; }
  [[ "$log" != *"--title"* ]]
}
@test "kitty spawn with no anchor: an os-window at the explicit cwd (never --cwd=current: that reads the ACTIVE window)" {
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/kitty.log"; echo 778\n' "$BATS_TEST_TMPDIR" > "$STUB/kitty"; chmod +x "$STUB/kitty"
  export CC_TERM_KITTY="$STUB/kitty" CC_TERM_KITTY_TO="unix:/tmp/fake-kitty"
  run lr_kitty_spawn /tmp/lr-launch-x.sh /tmp/wt "$SID" next3
  [ "$status" -eq 0 ]; [ "$output" = 778 ]
  grep -q -- '--type=os-window --cwd=/tmp/wt' "$BATS_TEST_TMPDIR/kitty.log"
}
@test "kitty spawn: a non-integer id from kitty is not a pane — rc 1, nothing claimed" {
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  printf '#!/bin/bash\necho "Error: no such tab"\n' > "$STUB/kitty"; chmod +x "$STUB/kitty"
  export CC_TERM_KITTY="$STUB/kitty" CC_TERM_KITTY_TO="unix:/tmp/fake-kitty"
  run lr_kitty_spawn /tmp/lr-launch-x.sh /tmp/wt "$SID" next3
  [ "$status" -eq 1 ]
}

# ── the argv census (lr_resume_procs) ────────────────────────────────────────────────────────────
# Both cases below were LIVE defects on 2026-09-09, and both made the same false claim — that a
# session had more than one process — which is the claim `--duplicates` acts on by telling the
# operator to retire a pane.
ps_stub() { # $@ = literal `pid ppid command` lines the fake ps prints
  STUB="$BATS_TEST_TMPDIR/psstub"; mkdir -p "$STUB"
  { echo '#!/bin/bash'; echo 'cat <<"EOF"'; printf '%s\n' "$@"; echo 'EOF'; } > "$STUB/ps"
  chmod +x "$STUB/ps"; export PATH="$STUB:$PATH"
}
@test "argv census: the cc-close-attrib WRAPPER and its child are ONE session, not two" {
  ps_stub \
    "16125 15577 bash /Users/x/.claude/bin/cc-close-attrib /Users/x/claude --resume $SID" \
    "16212 16125 /Users/x/claude --resume $SID"
  run lr_resume_procs "$SID"
  [ "$status" -eq 0 ]
  [ "$output" = "16212" ]                      # the LEAF is the session; the parent is the launcher
}
@test "argv census: two genuinely unrelated processes on one sid are still BOTH reported" {
  ps_stub "500 1 /Users/x/claude --resume $SID" "900 1 /Users/x/claude --resume $SID"
  run lr_resume_procs "$SID"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" = 2 ]
}
@test "argv census: the QUERENT is not in its own population — a sid no process holds returns rc 1" {
  # NO ps stub here deliberately: this case is about what the REAL process table shows. The pattern
  # used to ride in argv (`awk -v s="--resume $sid"`), so the concurrently-started `ps` printed the
  # awk process itself and index($0,s) matched it — this census answered YES for every sid ever
  # asked about, and `--locate` duly called a one-pane session DUPLICATE and a no-pane session
  # RESUMING. The sid travels in the environment now, so a sid nothing holds must come back empty.
  run lr_resume_procs "ffffffff-0000-4000-8000-ffffffffffff"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

# ── CONFIG DIRS: a symlinked store is ONE account, and it must be scanned ONCE ─────────────────
# `~/.claude-next/projects` is a SYMLINK to `~/.claude/projects` on this box, so the census walked
# 421 of 2,579 transcript files TWICE — 16.3% of the scan, paid on the hot path and deduped
# afterwards at lr-fleet.sh:257-262 by row (U14 §1.1). A dedupe at the ROW is the wrong layer: it
# corrects the output and cannot recover the work, and every OTHER consumer of lr_config_dirs pays
# the full double walk with no dedupe at all. The identity that matters is the one the scan reads —
# the resolved `projects/` dir — not the config dir's own name, so the key is `pwd -P` of it.
@test "config dirs: two stores whose projects/ resolve to ONE directory are enumerated ONCE" {
  mkdir -p "$HOME/.claude/projects" "$HOME/.claude-secondary/projects"
  ln -s "$HOME/.claude/projects" "$HOME/.claude-next/projects" 2>/dev/null || {
    mkdir -p "$HOME/.claude-next"; ln -s "$HOME/.claude/projects" "$HOME/.claude-next/projects"; }
  run env -u LR_CONFIG_DIRS bash -c ". '$LIB'; lr_config_dirs"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" = 2 ] || { printf '%s\n' "$output" >&2; false; }
  # the MIRROR is the one dropped, never the store it mirrors: lf_dedup_mirror keeps the row whose
  # account is not the bare `.claude`, and every downstream account name is derived from this path.
  [[ "$output" == *"/.claude"* ]] || { printf '%s\n' "$output" >&2; false; }
  [[ "$output" != *".claude-next"* ]] || { printf '%s\n' "$output" >&2; false; }
  [[ "$output" == *".claude-secondary"* ]] || { printf '%s\n' "$output" >&2; false; }
}

@test "config dirs CONTROL: two stores with genuinely SEPARATE projects/ dirs are both kept" {
  mkdir -p "$HOME/.claude/projects" "$HOME/.claude-next/projects" "$HOME/.claude-tertiary/projects"
  run env -u LR_CONFIG_DIRS bash -c ". '$LIB'; lr_config_dirs"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" = 3 ] || { printf '%s\n' "$output" >&2; false; }
}

# ── the run's state log (W2, LIMIT_RECOVER_100P) ──────────────────────────────────────────────────
# Append-only, one ≤1 KB jq-encoded line per transition, in the run's OWN bundle dir. The properties
# that matter are the ones a silent store cannot have: a failed append is LOUD (D3-FT R10 refused the
# `|| true` form), the record is bounded at the WRITER so O_APPEND stays atomic (repo lesson
# append-atomicity-ends-at-the-stdio-buffer), and the last line IS the state.

@test "state: an append is one jq-encoded line, and the last one is the current state" {
  run="$BATS_TEST_TMPDIR/bundle-1"
  lr_state_append "$run" targeted rank "picked next3"
  lr_state_append "$run" admitted gate "token minted"
  [ "$(wc -l < "$run/events.jsonl" | tr -d ' ')" = 2 ]
  run jq -rs 'length' "$run/events.jsonl"           # slurpable: no malformed line
  [ "$output" = "2" ]
  [ "$(lr_state_current "$run")" = "admitted" ]
  [ "$(jq -r '.stage' < <(tail -1 "$run/events.jsonl"))" = "gate" ]
  [ -n "$(jq -r '.writer' < <(tail -1 "$run/events.jsonl"))" ]
}

@test "state: a record is BOUNDED at the writer, so a concurrent append cannot splice into it" {
  run="$BATS_TEST_TMPDIR/bundle-2"
  big="$(head -c 4000 /dev/zero | tr '\0' 'x')"
  lr_state_append "$run" FAILED gate "$big"
  [ "$(wc -l < "$run/events.jsonl" | tr -d ' ')" = 1 ]
  [ "$(wc -c < "$run/events.jsonl" | tr -d ' ')" -le 1024 ] \
    || { wc -c < "$run/events.jsonl"; echo "a record over the stdio buffer is no longer an atomic append"; false; }
}

@test "state: a failed append is LOUD and non-zero — never a silent drop" {
  # The store is unwritable: the run dir cannot be created. A `|| true` here would report success
  # over a run whose whole state log is missing.
  blocked="$BATS_TEST_TMPDIR/blocked"; : > "$blocked"      # a FILE where the dir must be
  run lr_state_append "$blocked/bundle" FAILED gate "x"
  [ "$status" -eq 1 ]
  [[ "$output" == *"NOT recorded"* ]] || { echo "$output"; false; }
  run lr_state_current "$blocked/bundle"
  [ "$status" -eq 1 ]                                # a run with no log has no state, and says so
}

# ── HUSK: a LIVE pane on a store whose session has already MOVED (W10, LIMIT_RECOVER_100P § 10) ──
# The conjunction is three parts and each leg is red-proved on its own below. The state exists
# because a transplant leaves the SOURCE pane standing: alive, empty composer, the limit error
# still on screen, while the session is worked on somewhere else. Measured 2026-09-19 on panes
# 110/126/150 — all three live, none of them in `--locate`.
#
# EVERY IDENTIFIER HERE IS UNFORGEABLE FROM OUTSIDE THE FIXTURE. Leg (c1) reads the REAL process
# table, so a pane id that can also exist on this box would let an unrelated `__recycle` watcher
# decide these cases (memory: hermetic-in-stubs-not-in-interpreter). `HUSKPANE-a1b2c3` cannot.
HKPANE=HUSKPANE-a1b2c3

hk_live() { # → a live pid THIS SUITE owns, reaped in teardown
  # EVERY fd is closed on the way out. A background job that inherits bats' own stdout holds
  # the test's output pipe open, so bats waits on a `sleep` instead of on its subject and the
  # run hangs with no failing assertion to point at.
  # shellcheck disable=SC2217  # the </dev/null is NOT for sleep's benefit — sleep reads no stdin.
  # It is here to detach this background job from bats' OWN stdin/stdout, which is the hang the
  # comment above describes. Dropping it to satisfy the check re-creates the hang.
  sleep 45 >/dev/null 2>&1 </dev/null & printf '%s\n' "$!" >> "$BATS_TEST_TMPDIR/hk-pids"; printf '%s' "$!"
}
hk_row() { # $1=pane $2=sid $3=account $4=pid
  printf '{"paneUUID":"%s","session_id":"%s","pid":%s,"account":"%s","cwd":"/x"}\n' \
    "$1" "$2" "$4" "$3" > "$CC_REGISTRY_DIR/$1.json"
}
hk_lock() { # $1=from $2=to — and the successor copy the lock claims
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SID" "$1" "$2" > "$LR_STATE_DIR/locks/$SID.lock"
  mkdir -p "$2/projects/$SLUG"; : > "$2/projects/$SLUG/$SID.jsonl"
}
hk_husk() { # the whole true-husk fixture: live row on CFG's account + lock to OTHER + quiet log
  export CC_HANDOFF_LOG="$BATS_TEST_TMPDIR/handoffs.jsonl"; : > "$CC_HANDOFF_LOG"
  hk_row "$HKPANE" "$SID" cfg-a "$(hk_live)"
  hk_lock "$CFG" "$OTHER"
}
hk_hrow() { # $1=age seconds → one handoffs.jsonl row naming the sid, that old
  local ts; ts="$(/usr/bin/python3 -c '
import sys
from datetime import datetime,timedelta,timezone
print((datetime.now(timezone.utc)-timedelta(seconds=float(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1")"
  printf '{"ts":"%s","class":"recycle-intent","prev_sid":"%s"}\n' "$ts" "$SID" >> "$CC_HANDOFF_LOG"
}
teardown() {
  [ -f "$BATS_TEST_TMPDIR/hk-pids" ] || return 0
  # `|| true` on the kill, not just `2>/dev/null`: under bats' errexit a kill whose target was
  # already reaped returns 1 and aborts the teardown body — a test that passed on its own merits
  # then goes red, and only under load. The `&& kill … || true` form would also work but hides the
  # precedence; the explicit guard says what it does.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    kill "$p" 2>/dev/null || true
  done < "$BATS_TEST_TMPDIR/hk-pids"
  return 0
}

@test "husk: live row on THIS store's account + a lock to another store + nothing in flight = HUSK" {
  hk_husk
  run lr_husk_state "$SID" "$CFG"
  [ "$status" -eq 0 ] || { ls "$CC_REGISTRY_DIR"; cat "$LR_STATE_DIR/locks/$SID.lock"; false; }
}

# §10.3 item 4, and the one that keeps the W12 drill from flaking: the lock is NEVER deleted and the
# source row stays live until the typed `/exit` lands, so (a) ∧ (b) is true of every recovery during
# its own relaunch window. Without leg (c) the census would call each one a husk and the actuator
# would close the pane a recovery is mid-way through using.
@test "husk: a handoffs.jsonl row 60 s old is a recovery IN FLIGHT, never a husk" {
  hk_husk; hk_hrow 60
  run lr_husk_state "$SID" "$CFG"
  [ "$status" -eq 1 ] || { cat "$CC_HANDOFF_LOG"; false; }
}

# The same leg, the other way round — otherwise the case above passes for a predicate that simply
# refuses on ANY row naming the sid, and the log is append-only and never pruned, so that predicate
# would disqualify every sid that has ever been recycled, permanently.
@test "husk: a handoffs.jsonl row OLDER than LR_HUSK_MIN_AGE_S does not disqualify it" {
  hk_husk; hk_hrow 5400
  run lr_husk_state "$SID" "$CFG"
  [ "$status" -eq 0 ] || { cat "$CC_HANDOFF_LOG"; false; }
  LR_HUSK_MIN_AGE_S=7200 run lr_husk_state "$SID" "$CFG"   # widen the bound: the same row now bites
  [ "$status" -eq 1 ]
}

@test "husk: a live __recycle watcher for the pane is a recovery IN FLIGHT, never a husk" {
  hk_husk
  # A REAL process whose argv carries `__recycle <pane>`, standing in for the detached watcher
  # handoff-fire.sh leaves behind (`… __recycle <pane> <tty> <cmdfile> <launch-dir> <prev-sid>`).
  cat > "$BATS_TEST_TMPDIR/hf.sh" <<'SH'
#!/bin/bash
sleep 45
SH
  chmod +x "$BATS_TEST_TMPDIR/hf.sh"
  bash "$BATS_TEST_TMPDIR/hf.sh" __recycle "$HKPANE" /dev/ttys999 /tmp/cmd /tmp >/dev/null 2>&1 </dev/null &
  printf '%s\n' "$!" >> "$BATS_TEST_TMPDIR/hk-pids"
  # the watcher must be IN the process table before the census reads it, or this case passes for
  # a race rather than for its subject
  # shellcheck disable=SC2009  # DELIBERATELY `ps | grep`, not pgrep, in all three reads below.
  # The subject (lr_husk_state leg c1) censuses with `ps -axo command=`, and this probe has to see
  # the process table the way the SUBJECT sees it. pgrep excludes itself, which would hide exactly
  # the self-match hazard the subject is written to avoid (docs/lessons/census-matches-itself.md) —
  # so a pgrep-based readiness probe could pass over a table the subject reads differently.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    ps -axo command= | grep -q "__recycle $HKPANE" && break
    sleep 0.2
  done
  # shellcheck disable=SC2009
  ps -axo command= | grep -q "__recycle $HKPANE" || { echo "the stand-in watcher never started"; false; }
  run lr_husk_state "$SID" "$CFG"
  # shellcheck disable=SC2009
  [ "$status" -eq 1 ] || { ps -axo command= | grep __recycle; false; }
}

@test "husk: a lock whose \"to\" IS this store is not a husk — the successor is the one asking" {
  hk_husk
  run lr_husk_state "$SID" "$OTHER"
  [ "$status" -eq 1 ]
}

@test "husk: no live registry row at all is not a husk" {
  export CC_HANDOFF_LOG="$BATS_TEST_TMPDIR/handoffs.jsonl"; : > "$CC_HANDOFF_LOG"
  hk_lock "$CFG" "$OTHER"
  run lr_husk_state "$SID" "$CFG"
  [ "$status" -eq 1 ]
}

# THE COMPLETED TRANSPLANT. Leg (a) is an ACCOUNT test, not a liveness test: once the source pane
# is gone the only live row for the sid is the SUCCESSOR's, on the target account. Without the
# account leg that row satisfies "a live row exists" and the source store reads as a husk on the
# strength of the survivor's own liveness — and the actuator would be aimed at the survivor.
@test "husk: the only live row is on ANOTHER account ⇒ not a husk (the successor is not the husk)" {
  export CC_HANDOFF_LOG="$BATS_TEST_TMPDIR/handoffs.jsonl"; : > "$CC_HANDOFF_LOG"
  hk_row "$HKPANE" "$SID" cfg-b "$(hk_live)"
  hk_lock "$CFG" "$OTHER"
  run lr_husk_state "$SID" "$CFG"
  [ "$status" -eq 1 ]
}

# THE MIRROR FOLD, and it is load-bearing rather than defensive. `~/.claude` and `~/.claude-next`
# are ONE account; lr_config_dirs keeps the `.claude` spelling and drops `.claude-next`, while a
# session started under CLAUDE_CONFIG_DIR=~/.claude-next registers as account `claude-next`
# (hooks/session-register.sh:158). Measured 2026-09-19: 2 of the 3 live husks (panes 110 and 126)
# were exactly this shape, so without the fold two thirds of the population stay invisible.
@test "husk: a row registered as claude-next matches a store enumerated as ~/.claude" {
  export CC_HANDOFF_LOG="$BATS_TEST_TMPDIR/handoffs.jsonl"; : > "$CC_HANDOFF_LOG"
  MIRROR="$HOME/.claude"; mkdir -p "$MIRROR/projects/$SLUG"
  hk_row "$HKPANE" "$SID" claude-next "$(hk_live)"
  hk_lock "$MIRROR" "$OTHER"
  run lr_husk_state "$SID" "$MIRROR"
  [ "$status" -eq 0 ] || { cat "$LR_STATE_DIR/locks/$SID.lock"; false; }
}

@test "husk: LR_HUSK_RETIRE=off makes a TRUE husk read rc 1 — the census is pre-W10, byte for byte" {
  hk_husk
  run lr_husk_state "$SID" "$CFG"            # the positive control: it IS a husk with the switch on
  [ "$status" -eq 0 ]
  LR_HUSK_RETIRE=off run lr_husk_state "$SID" "$CFG"
  [ "$status" -eq 1 ]
}

# ── W4 step 3 (LIMIT_DETECT_100P): lr_last_api_error's kind comes from the SSOT ─────────────────
# The verbatim 2.1.260 Fable record — quotaLimits ABSENT, errorDetails present. Receipt:
# ~/.claude-quaternary/projects/-Users-chrisren-Development-hammerspoon-config/2d71c6d8-….jsonl:1252
# (the same record tests/lr-predicate.bats pins as fable_record).
f1_tail() { # -> a transcript whose LAST assistant record is a Fable cap
  local f="$BATS_TEST_TMPDIR/f1.jsonl"
  printf '%s\n' '{"type":"user","timestamp":"2026-09-12T15:20:00.000Z","message":{"role":"user","content":"go"}}' > "$f"
  printf '%s\n' '{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit","apiErrorStatus":429,"uuid":"2d71c6d8-0000-4000-8000-000000000001","timestamp":"2026-09-12T15:26:49.089Z","entrypoint":"cli","message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"You'"'"'ve reached your Fable limit. Run /usage-credits to continue or switch models with /model."}]}}' >> "$f"
  printf '%s' "$f"
}

# THE SHAPE IS THE CONTRACT, not a tidiness rule. hooks/net-recover-arm.sh:195 strips everything up
# to the LAST tab and feeds what is left to a string compare against a turn timestamp
# (`_turn_ended_after`, :164/:175). A fifth column was measured turning that read into the literal
# entrypoint value, after which the asyncRewake never fires (judge Da-latency FATAL 2). So this row
# asserts the field COUNT and, separately, that the same suffix-strip that hook performs still
# yields the timestamp — the assertion the hook actually depends on.
@test "lr_last_api_error prints EXACTLY 4 tab fields, with the timestamp LAST" {
  local f out
  f="$(f1_tail)"
  out="$(lr_last_api_error "$f")"
  [ "$(printf '%s' "$out" | awk -F'\t' '{print NF}')" = 4 ]
  [ "${out##*$'\t'}" = "2026-09-12T15:26:49.089Z" ]
  [ "$(printf '%s' "$out" | cut -f1)" = "2d71c6d8-0000-4000-8000-000000000001" ]
  [ "$(printf '%s' "$out" | cut -f2)" = "rate_limit" ]
}

# RED before W4: the kind was `"limit" if "You've hit your" in txt else "other"`, which is blind to
# every `reached your` cap. hooks/recover-inject.sh:98 branches on this exact field, so a Fable
# death was announced to the operator as "NOT a quota message".
@test "F1: a Fable cap reads \`limit\` in field 3 — the model-scoped caps are no longer invisible" {
  local f
  f="$(f1_tail)"
  [ "$(lr_last_api_error "$f" | cut -f3)" = limit ]
}

# THE DEGRADED ARM. An import error must degrade to the PRE-W4 text answer and never to rc 1: rc 1
# from this function means "the last assistant record is not an api error", so an unreachable
# module would report a CAPPED fleet as a healthy one — a fail-dangerous inversion, not a quiet
# one. Forced here through the same LR_LIB_DIR lever tests/lr-lib.bats:117 already uses.
#
# NOT because the module is unconverged — it is not. Checked 2026-09-20: ~/.claude/scripts/
# limit-recover/lr_predicate.py and lr-predicate.sh have been symlinked into the shared checkout
# since 02:48 and the live shim answers. The reachable causes are a worktree binary whose sibling
# is missing, a caller that exports LR_LIB_DIR somewhere else (three do export it), a future file
# added beside these, and a half-installed layer.
@test "module unreachable: the kind degrades to the pre-W4 answer, and NEVER to rc 1" {
  local f out
  f="$(f1_tail)"
  LR_LIB_DIR="$BATS_TEST_TMPDIR/nowhere" run lr_last_api_error "$f"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | awk -F'\t' '{print NF}')" = 4 ]
  [ "$(printf '%s' "$output" | cut -f3)" = other ]
}

# ── RED-PROOF (W4 step 3 rows) ──────────────────────────────────────────────────────────────────
# Against pristine trunk e03e36eec with the UNMIGRATED lr-lib.sh, `bats -f "EXACTLY 4 tab
# fields|F1: a Fable cap reads|module unreachable"`:
#
#   1..3
#   ok 1 lr_last_api_error prints EXACTLY 4 tab fields, with the timestamp LAST
#   not ok 2 F1: a Fable cap reads `limit` in field 3 — the model-scoped caps are no longer invisible
#   # (in test file tests/lr-lib.bats, line 440)
#   #   `[ "$(lr_last_api_error "$f" | cut -f3)" = limit ]' failed
#   ok 3 module unreachable: the kind degrades to the pre-W4 answer, and NEVER to rc 1
#
# ROWS 1 AND 3 ARE GREEN IN BOTH ARMS BY DESIGN, and that is the point of them, not a weakness.
# Row 1 pins the SHAPE the migration must not change — a fifth column here makes
# net-recover-arm.sh:195 read the entrypoint instead of the timestamp and the asyncRewake never
# fires — so it can only ever be green before and must stay green after. Row 3 pins the degraded
# path, which on pristine trunk has no module to lose. BOTH WERE MUTATION-CHECKED, and these are
# the runs, not a prediction of them:
#   mutant: append a 5th column (entrypoint) ->
#     not ok 1 lr_last_api_error prints EXACTLY 4 tab fields, with the timestamp LAST
#     #   `[ "$(printf '%s' "$out" | awk -F'\t' '{print NF}')" = 4 ]' failed
#   mutant: the unreachable-module branch `sys.exit(1)` instead of degrading ->
#     not ok 1 module unreachable: the kind degrades to the pre-W4 answer, and NEVER to rc 1
#     #   `[ "$status" -eq 0 ]' failed
# Row 2 is the only behavioural red, and it is the one the DoD names.
