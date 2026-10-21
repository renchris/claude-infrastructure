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

# ── liveness SCOPED TO ONE STORE (W5-A, 2026-09-20) ──────────────────────────────────────────────
# The poller's transplant arm asks "did the SUCCESSOR, on the TARGET store, come up?" — and the
# unscoped predicate above cannot answer it: a live row on the SOURCE account returns the same yes
# while meaning the opposite (that row is the HUSK). Each leg below is red-proved on its own.
rc_row() { # $1=pane $2=account [$3=pid] — one registry row naming $SID
  printf '{"paneUUID":"%s","session_id":"%s","pid":%d,"account":"%s","cwd":"/x"}\n' \
    "$1" "$SID" "${3:-$$}" "$2" > "$CC_REGISTRY_DIR/$1.json"
}

@test "registry-in-cfg: a live row on the NAMED store is a hit; one on another store is not" {
  rc_row 701 cfg-b
  run lr_registry_live_rows_in_cfg "$SID" "$OTHER"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c .)" = 1 ]
  [[ "$output" == 701$'\t'$$$'\t'cfg-b$'\t'/x ]] || { echo "$output"; false; }
  run lr_registry_live_rows_in_cfg "$SID" "$CFG"        # the SAME row, asked about the other store
  [ "$status" -eq 1 ] || { echo "a source-account row answered for the target: $output"; false; }
}

@test "registry-in-cfg: it FILTERS, it does not merely pass lr_registry_live_rows through" {
  # Without the account compare this case is indistinguishable from the unscoped predicate: two
  # live rows on two stores, and the answer for each store must name exactly ONE of them.
  rc_row 701 cfg-b
  rc_row 616 cfg-a
  run lr_registry_live_rows_in_cfg "$SID" "$OTHER"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" = 1 ] || { echo "$output"; false; }
  [[ "$output" == 701* ]] || { echo "$output"; false; }
}

@test "registry-in-cfg: a DEAD pid on the named store is not a successor" {
  rc_row 701 cfg-b 4194102
  run lr_registry_live_rows_in_cfg "$SID" "$OTHER"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "registry-in-cfg: the .claude / .claude-next MIRROR is ONE account, in both directions" {
  # NOT a nicety. hooks/session-register.sh writes `.account` as basename $CLAUDE_CONFIG_DIR with
  # the dot stripped, and a session started under CLAUDE_CONFIG_DIR=~/.claude-next registers as
  # `claude-next` while its transcripts enumerate under `~/.claude`. Two of the three husks W10
  # measured carried exactly that mismatch, so a literal compare answers "no successor" for a
  # common transplant target on this box.
  mkdir -p "$HOME/.claude" "$HOME/.claude-next"
  rc_row 701 claude-next
  run lr_registry_live_rows_in_cfg "$SID" "$HOME/.claude"
  [ "$status" -eq 0 ] || { echo "row account=claude-next vs cfg ~/.claude: $output"; false; }
  rm -f "$CC_REGISTRY_DIR/701.json"
  rc_row 702 claude
  run lr_registry_live_rows_in_cfg "$SID" "$HOME/.claude-next"
  [ "$status" -eq 0 ] || { echo "row account=claude vs cfg ~/.claude-next: $output"; false; }
}

@test "registry-in-cfg: a missing argument is rc 1, never a wildcard match" {
  rc_row 701 cfg-b
  run lr_registry_live_rows_in_cfg "$SID" ""; [ "$status" -eq 1 ]
  run lr_registry_live_rows_in_cfg "" "$OTHER"; [ "$status" -eq 1 ]
}

@test "registry-in-cfg: a trailing slash on the cfg path does not change the account it names" {
  rc_row 701 cfg-b
  run lr_registry_live_rows_in_cfg "$SID" "$OTHER/"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
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
  # `ls` answers a census (anchor 616 alone in its OS window), because placement now reads one
  # before it splits (scripts/lib/pane-placement.sh): an unreadable census opens a fullscreen OS
  # window instead, which tests/pane-placement.bats pins.
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/kitty.log"\ncase " $* " in *" ls "*) echo %s; exit 0 ;; esac\necho 777\n' \
    "$BATS_TEST_TMPDIR" "'[{\"id\":1,\"tabs\":[{\"id\":2,\"layout\":\"splits\",\"windows\":[{\"id\":616}]}]}]'" > "$STUB/kitty"; chmod +x "$STUB/kitty"
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


# ══ W10b — the husk predicate reads the LOCK *or* the TOMBSTONE (2026-09-20) ═════════════════════
# THE DEFECT THIS PINS. lr_husk_state's leg (b) went in reading only the split-brain lock, on the
# stated ground that a same-account `--mark` writes a tombstone and no lock. That is true about the
# FILES and false about the FLEET: measured on the three panes W10 was written for,
# ~/.reso/limit-recover/locks held ONE lock for the whole box and it belonged to an unrelated
# session. Each husk had a tombstone, a retired <sid>.jsonl.handed-off source and a live successor
# copy — and NO lock; the tombstone even named a lock path that no longer existed. So the predicate
# returned "not a husk" for all three panes it exists to find, with every unit test green, because
# the fixtures had been built to the predicate's own assumption (memory:
# an-imported-threshold-can-sit-above-the-model-s-output-range).
#
# The discriminator was never the file KIND — it is "does it name a DIFFERENT store". The third
# case is the one that keeps that honest.
hk_tomb() { # $1=target cfg → a TRANSPLANT tombstone in CFG pointing at it, and NO lock
  printf '{"handed_off_to":"%s","target_transcript":"%s/projects/%s/%s.jsonl","ts":"2026-09-19T22:23:39Z"}\n' \
    "$1" "$1" "$SLUG" "$SID" > "$CFG/projects/$SLUG/$SID.HANDOFF.json"
}

@test "husk: a TOMBSTONE with no lock still resolves the transplant target" {
  mkdir -p "$OTHER/projects/$SLUG"; : > "$OTHER/projects/$SLUG/$SID.jsonl"
  hk_tomb "$OTHER"
  [ ! -e "$LR_STATE_DIR/locks/$SID.lock" ] || { echo "fixture leaked a lock — the point is that there is none"; false; }
  run lr_transplant_target "$SID" "$CFG"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"$OTHER"* ]] || { echo "$output"; false; }
}

@test "husk: a live row + a tombstone-only transplant IS a husk" {
  export CC_HANDOFF_LOG="$BATS_TEST_TMPDIR/handoffs.jsonl"; : > "$CC_HANDOFF_LOG"
  mkdir -p "$OTHER/projects/$SLUG"; : > "$OTHER/projects/$SLUG/$SID.jsonl"
  hk_tomb "$OTHER"
  hk_row "$HKPANE" "$SID" cfg-a "$(hk_live)"
  run lr_husk_state "$SID" "$CFG"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "husk: a SAME-STORE tombstone is NOT a transplant — the --mark case stays excluded" {
  # THE SAFETY PROPERTY the lock-only read was protecting, now carried by the different-store test
  # instead of by the file kind. A `--mark` SUPERSEDED tombstone names THIS store.
  export CC_HANDOFF_LOG="$BATS_TEST_TMPDIR/handoffs.jsonl"; : > "$CC_HANDOFF_LOG"
  hk_tomb "$CFG"
  hk_row "$HKPANE" "$SID" cfg-a "$(hk_live)"
  run lr_transplant_target "$SID" "$CFG"
  [ "$status" -ne 0 ] || { echo "a same-store tombstone was read as a transplant: $output"; false; }
  run lr_husk_state "$SID" "$CFG"
  [ "$status" -ne 0 ] || { echo "a same-account duplicate was called a HUSK"; false; }
}

@test "husk: a tombstone whose successor copy is ABSENT is not a transplant" {
  hk_tomb "$OTHER"          # deliberately no $OTHER copy
  run lr_transplant_target "$SID" "$CFG"
  [ "$status" -ne 0 ] || { echo "$output"; false; }
}

# ── lr_heal_bare_checkout (D1, 2026-09-28): the driver heals a flipped checkout, or degrades ─────
# A checkout with core.bare=true answers every work-tree op rc 128; on 2026-09-28 that killed a
# recovery and the lead's repair was classifier-denied, so a human typed it. RED PROOFS: before this
# function existed the heal case has no subject at all. The refusal cases are the discriminators
# from memory worktree-ops-can-bare-the-shared-checkout — each must leave core.bare=true untouched.
bare_fixture() { # $1=dir → a normal checkout with a commit (reflog), then flipped
  git init -q "$1" && printf 'a\n' > "$1/a" && git -C "$1" add a \
    && git -C "$1" -c user.email=t@t -c user.name=t commit -qm init \
    && git -C "$1" config core.bare true
}

@test "bare-heal: a flipped checkout with files and a work-tree reflog is HEALED, with a backup" {
  local d="$BATS_TEST_TMPDIR/co"; bare_fixture "$d"
  [ "$(git -C "$d" rev-parse --is-inside-work-tree)" = false ]
  run lr_heal_bare_checkout "$d"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=healed"* ]] || false
  [ "$(git -C "$d" rev-parse --is-inside-work-tree)" = true ]
  ls "$d/.git/"config.lr-bare-backup-* >/dev/null
  grep -q 'bare = true' "$d/.git/"config.lr-bare-backup-*
}

@test "bare-heal: no working files ⇒ refused, core.bare stays true" {
  local d="$BATS_TEST_TMPDIR/co"; bare_fixture "$d"; rm -f "$d/a"
  run lr_heal_bare_checkout "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=refused-no-working-files"* ]] || false
  [ "$(git -C "$d" config --bool core.bare)" = true ]
}

@test "bare-heal: no work-tree operation in the HEAD reflog ⇒ refused, core.bare stays true" {
  local d="$BATS_TEST_TMPDIR/co"; bare_fixture "$d"; : > "$d/.git/logs/HEAD"
  run lr_heal_bare_checkout "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=refused-no-worktree-reflog"* ]] || false
  [ "$(git -C "$d" config --bool core.bare)" = true ]
}

@test "bare-heal: a genuinely bare repository is never touched" {
  local d="$BATS_TEST_TMPDIR/real.git"; git init -q --bare "$d"; printf 'x\n' > "$d/stray"
  run lr_heal_bare_checkout "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=refused-no-dotgit"* ]] || false
  [ "$(git -C "$d" config --bool core.bare)" = true ]
  ! ls "$d/"config.lr-bare-backup-* >/dev/null 2>&1
}

@test "bare-heal: LR_BARE_REPAIR=off detects and writes nothing" {
  local d="$BATS_TEST_TMPDIR/co"; bare_fixture "$d"
  LR_BARE_REPAIR=off run lr_heal_bare_checkout "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=detected-repair-off"* ]] || false
  [ "$(git -C "$d" config --bool core.bare)" = true ]
}

@test "bare-heal: a healthy checkout and a non-repo are silent no-ops" {
  local d="$BATS_TEST_TMPDIR/co"; bare_fixture "$d"; git -C "$d" config --unset core.bare
  run lr_heal_bare_checkout "$d"; [ "$status" -eq 0 ]; [ -z "$output" ]
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  run lr_heal_bare_checkout "$BATS_TEST_TMPDIR/plain"; [ "$status" -eq 2 ]
}

# ── lr_phantom_actives counts EVERY corpse ────────────────────────────────────────────────────────
# `break 3` left the per-beat loop on the first match, so the count could never exceed 1 however many
# limit-blocked sessions inflated the census — the recovery stayed refused by the ones it missed.
@test "phantom count > 1 with 3 corpses" {
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats"; mkdir -p "$CC_BEAT_DIR"
  export LR_CONFIG_DIRS="$CFG"
  local i sid
  for i in 1 2 3; do
    sid="bbbb000$i-0000-4000-8000-00000000000$i"
    printf '{"sid":"%s","kind":"prompt","pid":%s,"t":1}\n' "$sid" "$(hk_live)" > "$CC_BEAT_DIR/$sid.json"
    turn "$CFG/projects/$SLUG/$sid.jsonl" 2026-09-08T22:00:00.000Z claude-opus-5 high
    limit "$CFG/projects/$SLUG/$sid.jsonl" 2026-09-08T23:11:09.000Z
  done
  run lr_phantom_actives
  [ "$status" -eq 0 ]
  [ "$output" = 3 ]
}

# ONE jq over every beat (2026-10-08: a fork per beat over 7105 files took 70-87 s). jq reads the
# files as one stream, so a beat it cannot parse must fall back to the per-file loop, never cost the
# beats after it. RED: drop the fallback arm and the count reads 0 or 1, not 3.
@test "phantom: a beat jq cannot parse costs only itself, one-pass or per-file" {
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats"; mkdir -p "$CC_BEAT_DIR"
  export LR_CONFIG_DIRS="$CFG"
  local i sid
  printf '{"sid": "broken", "kind": ' > "$CC_BEAT_DIR/0000-broken.json"
  for i in 1 2 3; do
    sid="cccc000$i-0000-4000-8000-00000000000$i"
    printf '{\n  "sid": "%s",\n  "kind": "prompt",\n  "pid": %s\n}\n' "$sid" "$(hk_live)" > "$CC_BEAT_DIR/$sid.json"
    turn "$CFG/projects/$SLUG/$sid.jsonl" 2026-09-08T22:00:00.000Z claude-opus-5 high
    limit "$CFG/projects/$SLUG/$sid.jsonl" 2026-09-08T23:11:09.000Z
  done
  printf '{"sid":"dddd0001-0000-4000-8000-000000000001","kind":"stop","pid":%s}\n' "$(hk_live)" > "$CC_BEAT_DIR/stop.json"
  run lr_phantom_actives
  [ "$output" = 3 ] || { echo "one-pass: $output"; false; }
  LR_PHANTOM_ONEPASS=off run lr_phantom_actives
  [ "$output" = 3 ] || { echo "per-file: $output"; false; }
}

# BOTH CORRECTIONS ONLY SUBTRACT, so an uncorrected ADMIT is final and the beat scan is skipped; a
# refusal still gets the corrected second probe. RED: drop the lazy arm and PH_LOG gains a line on
# the admit case.
@test "probe: an uncorrected admit skips the phantom scan; a refusal still runs it" {
  PH_LOG="$BATS_TEST_TMPDIR/ph.log"; : > "$PH_LOG"
  cc_sp_active() { echo 5; }
  lr_phantom_actives() { echo scan >> "$PH_LOG"; printf 1; }
  cc_capacity_probe() { [ -z "${CC_SP_ACTIVE_OVERRIDE:-}" ] && return "${RAW_RC:-0}"; return 0; }
  RAW_RC=0 run lr_capacity_probe_corrected t probe
  [ "$status" -eq 0 ]; [ ! -s "$PH_LOG" ] || { cat "$PH_LOG"; false; }
  RAW_RC=9 run lr_capacity_probe_corrected t probe
  [ "$status" -eq 0 ]; [ "$(grep -c scan "$PH_LOG")" = 1 ]
  LR_PROBE_LAZY_CORRECTION=off RAW_RC=0 run lr_capacity_probe_corrected t probe
  [ "$(grep -c scan "$PH_LOG")" = 2 ]
}

# ── the focus gate (FLEET_V2 W6, resolution 1): one rule for every typing path ──────────────────
# Readers are stubbed by NAME, the way callers pass theirs. Mutants: drop the LR_MOVE_FOCUSED test
# (off stops holding) · drop the second read (a draft that appears in the gap passes) · treat
# `unknown` as focused (the iTerm2 case holds) · read the window flag alone (a background tab holds).
fg_focus() { printf '%s' "${FG_FOCUS:-yes}"; }
fg_comp() { # serves the next queued read from FG_READS: "" empty · "!" unreadable · else content
  local c; c="$(head -n 1 "$FG_READS")"; tail -n +2 "$FG_READS" > "$FG_READS.t"; mv "$FG_READS.t" "$FG_READS"
  echo "read" >> "$FG_LOG"
  [ "$c" = "!" ] && return 2
  [ -z "$c" ] && return 0
  printf '%s' "$c"; return 1
}
fg_world() {
  FG_READS="$BATS_TEST_TMPDIR/fg-reads"; FG_LOG="$BATS_TEST_TMPDIR/fg-log"; : > "$FG_LOG"
  printf '%s\n' "$@" > "$FG_READS"
  export LR_SLEEP="$BATS_TEST_TMPDIR/fg-sleep"
  printf '#!/usr/bin/env bash\necho "sleep $1" >> "%s"\n' "$FG_LOG" > "$LR_SLEEP"; chmod +x "$LR_SLEEP"
}

@test "focus gate: not focused or unknown proceeds without a read; focused under off is HELD:focused, nothing read" {
  fg_world "" ""
  export LR_MOVE_FOCUSED=off
  FG_FOCUS=no lr_focus_gate 901 fg_focus fg_comp
  [ "$LR_FOCUS_STATE" = no ]
  [ -z "$LR_FOCUS_HOLD" ]
  FG_FOCUS=garbage lr_focus_gate 901 fg_focus fg_comp
  [ "$LR_FOCUS_STATE" = unknown ]
  [ -z "$LR_FOCUS_HOLD" ]
  [ ! -s "$FG_LOG" ] || { cat "$FG_LOG"; false; }
  local rc=0; lr_focus_gate 901 fg_focus fg_comp || rc=$?
  [ "$rc" = 3 ] || { echo "rc=$rc"; false; }
  [ "$LR_FOCUS_HOLD" = HELD:focused ] || { echo "hold=$LR_FOCUS_HOLD"; false; }
  [ ! -s "$FG_LOG" ] || { cat "$FG_LOG"; false; }
}

@test "focus gate under on: two empty reads a gap apart proceed; a draft or an unreadable box on either read is HELD:draft" {
  export LR_MOVE_FOCUSED=on LR_FOCUS_READ_GAP_S=10
  fg_world "" ""
  lr_focus_gate 901 fg_focus fg_comp
  [ "$(tr '\n' ',' < "$FG_LOG")" = "read,sleep 10,read," ] || { cat "$FG_LOG"; false; }
  [ "$LR_FOCUS_STATE" = yes ]
  [ -z "$LR_FOCUS_HOLD" ]
  local first want rc
  for first in "" "hi"; do
    fg_world "$first" "operator typing"
    want="${first:-operator typing}"
    rc=0; lr_focus_gate 901 fg_focus fg_comp || rc=$?
    [ "$rc" = 3 ] || { echo "rc=$rc"; false; }
    [ "$LR_FOCUS_HOLD" = HELD:draft ] || { echo "hold=$LR_FOCUS_HOLD"; false; }
    [ "$LR_FOCUS_READ" = "$want" ] || { echo "read=[$LR_FOCUS_READ] want=[$want]"; false; }
  done
  fg_world "" "!"
  rc=0; lr_focus_gate 901 fg_focus fg_comp || rc=$?
  [ "$rc" = 3 ] || { echo "rc=$rc"; false; }
  [ "$LR_FOCUS_READ" = "<unreadable>" ] || { echo "read=[$LR_FOCUS_READ]"; false; }
}

# D7.6 the flip (decision 7, ruled 2026-09-30): unset is ON, and so is any value but `off`.
# Mutant: `${LR_MOVE_FOCUSED:-off}` back in lr_focus_gate — the unset case holds unread.
@test "focus gate by default (LR_MOVE_FOCUSED unset, or not 'off') reads twice and proceeds; only =off holds" {
  export LR_FOCUS_READ_GAP_S=10
  local v rc
  for v in "" on yes; do
    fg_world "" ""
    if [ -z "$v" ]; then unset LR_MOVE_FOCUSED; else export LR_MOVE_FOCUSED="$v"; fi
    rc=0; lr_focus_gate 901 fg_focus fg_comp || rc=$?
    [ "$rc" = 0 ] || { echo "v=[$v] rc=$rc hold=$LR_FOCUS_HOLD"; false; }
    [ "$(tr '\n' ',' < "$FG_LOG")" = "read,sleep 10,read," ] || { echo "v=[$v]"; cat "$FG_LOG"; false; }
  done
  fg_world "" ""
  export LR_MOVE_FOCUSED=off
  rc=0; lr_focus_gate 901 fg_focus fg_comp || rc=$?
  [ "$rc" = 3 ] || { echo "rc=$rc"; false; }
  [ "$LR_FOCUS_HOLD" = HELD:focused ] || { echo "hold=$LR_FOCUS_HOLD"; false; }
}

@test "focus gate default reader: UI focus is OS window AND tab AND window; an unparseable listing is unknown" {
  export LR_FOCUS_LS_FILE="$BATS_TEST_TMPDIR/ls.json"
  printf '[{"is_focused":true,"tabs":[{"is_focused":true,"windows":[{"id":901,"is_focused":true}]},{"is_focused":false,"windows":[{"id":903,"is_focused":true}]}]},{"is_focused":false,"tabs":[{"is_focused":true,"windows":[{"id":904,"is_focused":true}]}]}]\n' > "$LR_FOCUS_LS_FILE"
  [ "$(lr_pane_focused 901)" = yes ]
  [ "$(lr_pane_focused 903)" = no ]
  [ "$(lr_pane_focused 904)" = no ]
  [ "$(lr_pane_focused w1t0p0:901)" = yes ]
  [ "$(lr_pane_focused 999)" = unknown ]
  [ "$(lr_pane_focused abc)" = unknown ]
  echo 'not json' > "$LR_FOCUS_LS_FILE"
  [ "$(lr_pane_focused 901)" = unknown ]
}

@test "operator idle time: an integer passes, anything else reads unreadable, never a guessed 0" {
  [ "$(LR_HID_IDLE_S=2044 lr_hid_idle_s)" = 2044 ]
  [ "$(LR_HID_IDLE_S='' lr_hid_idle_s)" = unreadable ]
  [ "$(LR_HID_IDLE_S=x lr_hid_idle_s)" = unreadable ]
}

# ══ WHO CARRIES A MOVED SESSION — lr_pid_cfg + lr_successor_state (lr-stranded-husk, 2026-10-10) ══
# The poller retired pane 168's request (186452ed) because the SOURCE transcript was tombstoned,
# while no successor had started and the source pane still held the session — the "stranded husk"
# (docs/research/lr-stranded-husk-2026-10-10/ROOT-CAUSE.md). The predicate keys on the ACCOUNT each
# live holder runs under. Live facts at base, pinned as shapes below: 186452ed from ~/.claude-secondary
# answers `husk 168 28699`; panes 2/3/14 (7f5deb68, 1c0f7f90, 4d059264) answer `unmoved`.
# RED PROOF: run against lr-lib.sh at 982b9f184 (before c2eaac99a) every case here is rc 127.
# Hermetic: env files under LR_MOVE_ENV_DIR stand in for `ps -E`, except the lr_pid_cfg cases, which
# read the REAL ps branch over processes this suite spawns and kills itself.
SS_SID="c2c2a1b2-0000-4000-8000-0000000c2c2c"
# Pane ids UNFORGEABLE from outside the fixture (the HKPANE rule above): lr_husk_state's leg (c1)
# reads the REAL process table for `__recycle <pane>`, and 168 is the incident's own live pane, so a
# real recycle of it would turn these fixtures' husk into in-flight.
P168=HUSKPANE-c2-168; P200=HUSKPANE-c2-200; P2=HUSKPANE-c2-2
ss_setup() {
  SRC="$HOME/.claude-secondary"; TGT="$HOME/.claude-quaternary"; TER="$HOME/.claude-tertiary"
  mkdir -p "$HOME/.claude/projects" "$HOME/.claude-next" "$SRC/projects/-p" "$TGT/projects/-p" "$TER/projects/-p"
  ln -s "$HOME/.claude/projects" "$HOME/.claude-next/projects"
  # shellcheck disable=SC2031  # each @test is its own subshell; this helper sets it for the one calling it
  export CC_HANDOFF_LOG="$BATS_TEST_TMPDIR/handoffs.jsonl"; : > "$CC_HANDOFF_LOG"
  export LR_MOVE_ENV_DIR="$BATS_TEST_TMPDIR/env"; mkdir -p "$LR_MOVE_ENV_DIR"
  unset LR_CONFIG_DIRS LR_SUCCESSOR_GATE LR_HUSK_RETIRE
}
ss_retired() { # the 186452ed shape: confirm tombstone (no phase), .handed-off, /exit stub, target copy, lock
  printf '{"handed_off_to":"%s","target_transcript":"%s/projects/-p/%s.jsonl","ts":"2026-10-10T04:18:07Z","confirm_len":10}\n' "$TGT" "$TGT" "$SS_SID" > "$SRC/projects/-p/$SS_SID.HANDOFF.json"
  printf 'x\n' > "$SRC/projects/-p/$SS_SID.jsonl.handed-off"; printf 'stub\n' > "$SRC/projects/-p/$SS_SID.jsonl"
  printf 'x\n' > "$TGT/projects/-p/$SS_SID.jsonl"
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SS_SID" "$SRC" "$TGT" > "$LR_STATE_DIR/locks/$SS_SID.lock"
}
ss_admit() { # the 7f5deb68 shape: admit-phase tombstone, NO .handed-off, the source .jsonl still live
  printf '{"handed_off_to":"%s","ts":"2026-10-10T05:19:27Z","cause":"voluntary","phase":"admit"}\n' "$TGT" > "$SRC/projects/-p/$SS_SID.HANDOFF.json"
  printf 'live\n' > "$SRC/projects/-p/$SS_SID.jsonl"; printf 'old\n' > "$TGT/projects/-p/$SS_SID.jsonl"
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SS_SID" "$SRC" "$TGT" > "$LR_STATE_DIR/locks/$SS_SID.lock"
}
ss_row() { # $1=pane $2=pid $3=account $4=cfg → a live registry row plus that pid's environment
  hk_row "$1" "$SS_SID" "$3" "$2"; [ -z "$4" ] || printf '%s' "$4" > "$LR_MOVE_ENV_DIR/$2"
}
ss_leaf() { # → a live pid THIS SUITE owns whose argv is `claude --resume SS_SID` (reaped in teardown)
  # shellcheck disable=SC2217  # the </dev/null detaches the job from bats' own stdio (hk_live's hang)
  ( exec -a "claude --resume $SS_SID" sleep 45 ) >/dev/null 2>&1 </dev/null &
  printf '%s\n' "$!" >> "$BATS_TEST_TMPDIR/hk-pids"; printf '%s' "$!"
}
ss_state() { run lr_successor_state "$SS_SID" "$1"; }

@test "lr_pid_cfg, the REAL ps -E branch: an env-less /bin/sleep is rc 1, python3 under X is X, without it \$HOME/.claude, a dead pid rc 1" {
  unset LR_MOVE_ENV_DIR
  # Measured 2026-10-10: Apple platform binaries show NO environment block to a same-uid `ps -E`
  # (0 tokens for /bin/sleep), so the account is unknown — never the $HOME/.claude default, which
  # would call a source husk a "successor" and retire it (C2 skeptic). An Apple /usr/bin/python3 shim
  # hides its env the same way, so the env-visible leg needs a non-platform python3.
  local py; py="$(command -v python3)"
  if [ -z "$py" ] || [ "$py" = /usr/bin/python3 ]; then skip "no non-Apple python3 on PATH (its env would be hidden like /bin/sleep's)"; fi
  # shellcheck disable=SC2217  # the </dev/null detaches each job from bats' own stdio (hk_live's hang)
  /bin/sleep 45 >/dev/null 2>&1 </dev/null & local s=$!; echo "$s" >> "$BATS_TEST_TMPDIR/hk-pids"
  CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg-x" "$py" -c 'import time; time.sleep(45)' >/dev/null 2>&1 </dev/null & local x=$!; echo "$x" >> "$BATS_TEST_TMPDIR/hk-pids"
  env -u CLAUDE_CONFIG_DIR "$py" -c 'import time; time.sleep(45)' >/dev/null 2>&1 </dev/null & local d=$!; echo "$d" >> "$BATS_TEST_TMPDIR/hk-pids"
  # shellcheck disable=SC2217  # as above
  /bin/sleep 45 >/dev/null 2>&1 </dev/null & local gone=$!; kill "$gone"; wait "$gone" 2>/dev/null || true
  sleep 0.5
  run lr_pid_cfg "$s";    [ "$status" -eq 1 ] || { echo "env-less sleep: rc=$status out=$output"; false; }
  run lr_pid_cfg "$x";    [ "$status" -eq 0 ] && [ "$output" = "$BATS_TEST_TMPDIR/cfg-x" ] || { echo "python3 under X: rc=$status out=$output"; false; }
  run lr_pid_cfg "$d";    [ "$status" -eq 0 ] && [ "$output" = "$HOME/.claude" ] || { echo "python3 without X: rc=$status out=$output"; false; }
  run lr_pid_cfg "$gone"; [ "$status" -eq 1 ] || { echo "dead pid: rc=$status out=$output"; false; }
  run lr_pid_cfg "";      [ "$status" -eq 1 ]
  run lr_pid_cfg "12x";   [ "$status" -eq 1 ]
}

# ══ THE ENV BLOCK ALONE — lr_env_block + lr_pid_env (W12, B5a §5.2; reviews S4, S17) ════════════════
# `ps -E` prints argv THEN the env, so an owed prompt on claude's argv can spell KITTY_WINDOW_ID ahead
# of the env's own; only the block after the argv prefix may answer. lr_pid_env has its OWN seam,
# LR_PID_ENV_DIR (env-shaped files), and lr_pid_cfg's LR_MOVE_ENV_DIR (a bare config dir) is untouched.
@test "lr_env_block: the argv prefix is stripped, an env-less or mismatched line is rc 1; lr_pid_env reads the LAST token of the block alone" {
  run lr_env_block "claude KITTY_WINDOW_ID=41" "claude KITTY_WINDOW_ID=41 HOME=/h PATH=/bin KITTY_WINDOW_ID=99"
  [ "$status" -eq 0 ] || false
  [ "$(printf '%s\n' "$output" | sed -n 's/^KITTY_WINDOW_ID=//p')" = 99 ] || { echo "$output"; false; }
  run lr_env_block "claude x" "claude x KITTY_WINDOW_ID=41";      [ "$status" -eq 1 ] || { echo "no HOME/PATH: $output"; false; }
  run lr_env_block "claude y" "claude x HOME=/h PATH=/bin";        [ "$status" -eq 1 ] || { echo "prefix mismatch: $output"; false; }
  run lr_env_block "" "HOME=/h";                                   [ "$status" -eq 1 ] || false
  export LR_PID_ENV_DIR="$BATS_TEST_TMPDIR/penv"; mkdir -p "$LR_PID_ENV_DIR"
  printf 'HOME=/h PATH=/bin KITTY_WINDOW_ID=7 KITTY_WINDOW_ID=8\n' > "$LR_PID_ENV_DIR/4242"
  run lr_pid_env 4242 KITTY_WINDOW_ID; [ "$status" -eq 0 ] && [ "$output" = 8 ] || { echo "rc=$status $output"; false; }
  run lr_pid_env 4242 KITTY_PID;       [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "absent var: rc=$status $output"; false; }
  printf 'KITTY_WINDOW_ID=7\n' > "$LR_PID_ENV_DIR/4243"
  run lr_pid_env 4243 KITTY_WINDOW_ID; [ "$status" -eq 1 ] || { echo "no env block: rc=$status"; false; }
  run lr_pid_env 4244 KITTY_WINDOW_ID; [ "$status" -eq 1 ] || false
  run lr_pid_env 12x KITTY_WINDOW_ID;  [ "$status" -eq 1 ] || false
  run lr_pid_env 4242 'BAD;VAR';       [ "$status" -eq 1 ] || false
}

@test "lr_pid_cfg is byte-identical: it never reads LR_PID_ENV_DIR, and its LR_MOVE_ENV_DIR fixture (a bare dir) still answers" {
  export LR_PID_ENV_DIR="$BATS_TEST_TMPDIR/penv" LR_MOVE_ENV_DIR="$BATS_TEST_TMPDIR/menv"; mkdir -p "$LR_PID_ENV_DIR" "$LR_MOVE_ENV_DIR"
  printf 'HOME=/h PATH=/bin CLAUDE_CONFIG_DIR=/wrong\n' > "$LR_PID_ENV_DIR/4242"
  printf '%s' "$HOME/.claude-tertiary" > "$LR_MOVE_ENV_DIR/4242"
  run lr_pid_cfg 4242; [ "$status" -eq 0 ] && [ "$output" = "$HOME/.claude-tertiary" ] || { echo "rc=$status $output"; false; }
}

@test "lr_pid_env, the REAL ps branch: a non-platform child's env block answers, its argv token never does" {
  unset LR_PID_ENV_DIR
  # Apple platform binaries show no env block to ps -E (the lr_pid_cfg case above measured it), so
  # the child must be a non-/bin bash.
  local b="" c
  for c in /opt/homebrew/bin/bash /usr/local/bin/bash "$(command -v bash)"; do
    case "$c" in ''|/bin/*) continue ;; esac
    if [ -x "$c" ]; then b="$c"; break; fi
  done
  [ -n "$b" ] || skip "no non-platform bash (its env would be hidden like /bin/sleep's)"
  env -i HOME=/h PATH=/bin KITTY_WINDOW_ID=5 "$b" -c 'sleep 45; :' KITTY_WINDOW_ID=9 >/dev/null 2>&1 </dev/null &
  local c=$!; echo "$c" >> "$BATS_TEST_TMPDIR/hk-pids"
  sleep 0.5
  run lr_pid_env "$c" KITTY_WINDOW_ID
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output"; false; }
  [ "$output" = 5 ] || { echo "out=$output argv=$(ps -ww -o command= -p "$c")"; false; }
}

@test "successor_state: the 186452ed shape (source row only, nothing in flight) is husk <pane> <pid>; a fresh handoffs row is in-flight" {
  ss_setup; ss_retired
  local p; p="$(hk_live)"; ss_row "$P168" "$p" claude-secondary "$SRC"
  ss_state "$SRC"; [ "$status" -eq 0 ] && [ "$output" = "husk $P168 $p" ] || { echo "rc=$status $output"; false; }
  printf '{"ts":"%s","class":"recycle-engaged","prev_sid":"%s"}\n' "$(date -u +%FT%TZ)" "$SS_SID" >> "$CC_HANDOFF_LOG"
  ss_state "$SRC"; [ "$status" -eq 0 ] && [ "$output" = "in-flight $P168 $p" ] || { echo "rc=$status $output"; false; }
}

@test "successor_state kill switches: LR_HUSK_RETIRE=off answers none; LR_SUCCESSOR_GATE=off is rc 2" {
  ss_setup; ss_retired
  local p; p="$(hk_live)"; ss_row "$P168" "$p" claude-secondary "$SRC"
  LR_HUSK_RETIRE=off ss_state "$SRC"; [ "$status" -eq 0 ] && [ "$output" = none ] || { echo "rc=$status $output"; false; }
  LR_SUCCESSOR_GATE=off ss_state "$SRC"; [ "$status" -eq 2 ] && [ -z "$output" ] || { echo "rc=$status $output"; false; }
}

@test "successor_state: a live holder under another account is the successor — a target row, a bare --resume leaf, a third store, the next mirror" {
  ss_setup; ss_retired
  local h p l; h="$(hk_live)"; ss_row "$P168" "$h" claude-secondary "$SRC"
  p="$(hk_live)"; ss_row "$P200" "$p" claude-quaternary "$TGT"
  ss_state "$SRC"; [ "$status" -eq 0 ] && [ "$output" = "successor $P200 $p $TGT" ] || { echo "row: rc=$status $output"; false; }
  rm -f "$CC_REGISTRY_DIR/$P200.json"
  l="$(ss_leaf)"; sleep 0.3
  printf '%s' "$TGT" > "$LR_MOVE_ENV_DIR/$l"
  ss_state "$SRC"; [ "$status" -eq 0 ] && [ "$output" = "successor - $l $TGT" ] || { echo "leaf: rc=$status $output"; false; }
  printf '%s' "$TER" > "$LR_MOVE_ENV_DIR/$l"
  ss_state "$SRC"; [[ "$output" == "successor - $l $TER" ]] || { echo "third store: rc=$status $output"; false; }
  printf '%s' "$HOME/.claude-next" > "$LR_MOVE_ENV_DIR/$l"
  ss_state "$SRC"; [[ "$output" == "successor - $l "* ]] || { echo "next mirror: rc=$status $output"; false; }
}

@test "successor_state: an unreadable holder env is unknown; no holder is none; a source holder with no pane is unknown" {
  ss_setup; ss_retired
  local h l; h="$(hk_live)"; ss_row "$P168" "$h" claude-secondary ""     # live, no env file
  ss_state "$SRC"; [ "$status" -eq 0 ] && [ "$output" = unknown ] || { echo "unreadable: rc=$status $output"; false; }
  rm -f "$CC_REGISTRY_DIR/$P168.json"
  ss_state "$SRC"; [ "$status" -eq 0 ] && [ "$output" = none ] || { echo "no holder: rc=$status $output"; false; }
  l="$(ss_leaf)"; sleep 0.3; printf '%s' "$SRC" > "$LR_MOVE_ENV_DIR/$l"
  ss_state "$SRC"; [ "$status" -eq 0 ] && [ "$output" = unknown ] || { echo "source leaf, no row: rc=$status $output"; false; }
}

@test "successor_state: the panes 2/3/14 shape (admit tombstone, source live) is unmoved; a lock alone is rc 1" {
  ss_setup; ss_admit
  local p; p="$(hk_live)"; ss_row "$P2" "$p" claude-secondary "$SRC"
  ss_state "$SRC"; [ "$status" -eq 0 ] && [ "$output" = unmoved ] || { echo "admit: rc=$status $output"; false; }
  rm -f "$SRC/projects/-p/$SS_SID.HANDOFF.json"
  ss_state "$SRC"; [ "$status" -eq 1 ] || { echo "lock only must stay today's read: rc=$status $output"; false; }
}

@test "successor_state: not a durable move off this store is rc 1 — the .claude/.claude-next mirror, never moved, a round trip home" {
  ss_setup
  mkdir -p "$HOME/.claude/projects/-p"; printf 'x\n' > "$HOME/.claude/projects/-p/$SS_SID.jsonl"
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SS_SID" "$HOME/.claude" "$HOME/.claude-next" > "$LR_STATE_DIR/locks/$SS_SID.lock"
  ss_state "$HOME/.claude"; [ "$status" -eq 1 ] || { echo "mirror: rc=$status $output"; false; }
  rm -f "$LR_STATE_DIR/locks/$SS_SID.lock"
  printf 'x\n' > "$SRC/projects/-p/$SS_SID.jsonl"
  ss_state "$SRC"; [ "$status" -eq 1 ] || { echo "never moved: rc=$status $output"; false; }
  printf '{"handed_off_to":"%s","ts":"2026-10-01T00:00:00Z"}\n' "$TGT" > "$SRC/projects/-p/$SS_SID.HANDOFF.json"
  printf 'old\n' > "$SRC/projects/-p/$SS_SID.jsonl.handed-off"
  printf 'x\n' > "$TGT/projects/-p/$SS_SID.jsonl.handed-off"
  ss_state "$SRC"; [ "$status" -eq 1 ] || { echo "round trip: rc=$status $output"; false; }
}

# ── ONE TABLE, TWO IMPLEMENTATIONS: the shell predicate vs lr_recon's census.successor_state ─────
# tests/fixtures/lr-stale-parity/cases.json is read here and by lr_recon/tests/test_census.py
# (StaleParity); both must give each case's `expect` (the first token, or null for rc 1/rc 2). The
# census mirrors this predicate in Python over its own evidence, so a rule changed on one side only
# turns one of the two red. Each case gets its OWN sid, store tree, registry and processes.
par_leaf() { # $1=sid → a live pid THIS SUITE owns whose argv is `claude --resume <sid>` (reaped in teardown)
  # shellcheck disable=SC2217  # the </dev/null detaches the job from bats' own stdio (hk_live's hang)
  ( exec -a "claude --resume $1" sleep 45 ) >/dev/null 2>&1 </dev/null &
  printf '%s\n' "$!" >> "$BATS_TEST_TMPDIR/hk-pids"; printf '%s' "$!"
}
@test "parity: lr_successor_state answers every row of the shared lr-stale-parity table" {
  local table="$REPO/tests/fixtures/lr-stale-parity/cases.json" n i sid H tp c to ph pane cfg pid acct kv got want fails=""
  n="$(jq '.cases | length' "$table")"; [ "$n" -gt 10 ]
  for (( i = 0; i < n; i++ )); do
    c="$(jq -c ".cases[$i]" "$table")"
    sid="$(printf 'c2ba%04d-0000-4000-8000-000000000001' "$i")"
    H="$BATS_TEST_TMPDIR/par$i"; mkdir -p "$H/reg" "$H/state/locks" "$H/env"
    declare -A st=([src]="$H/.claude-secondary" [tgt]="$H/.claude-quaternary" [ter]="$H/.claude-tertiary")
    mkdir -p "${st[src]}/projects/-p" "${st[tgt]}/projects/-p" "${st[ter]}/projects/-p"
    tp="${st[src]}/projects/-p/$sid.jsonl"
    if [ "$(jq -r .handed_off <<< "$c")" = true ]; then printf 'x\n' > "$tp.handed-off"; fi
    if [ "$(jq -r .src_jsonl <<< "$c")" = true ]; then printf 'x\n' > "$tp"; fi
    to="$(jq -r '.tomb.to // ""' <<< "$c")"; ph="$(jq -r '.tomb.phase // ""' <<< "$c")"
    [ -z "$to" ] || printf '{"handed_off_to":"%s"%s}\n' "${st[$to]}" "${ph:+,\"phase\":\"$ph\"}" > "${tp%.jsonl}.HANDOFF.json"
    if [ "$(jq -r .tgt_copy <<< "$c")" = true ]; then printf 'x\n' > "${st[tgt]}/projects/-p/$sid.jsonl"; fi
    while IFS=$'\t' read -r cfg pane; do
      [ -n "$cfg" ] || continue
      if [ "$pane" != null ]; then
        pid="$(hk_live)"
        # the row's account is its store's basename sans dot (session-register.sh), which
        # lr_husk_state's leg (a) matches against the source store; an unreadable holder sits on src
        acct="$(basename "${st[${cfg/none/src}]}")"
        printf '{"paneUUID":"%s","session_id":"%s","pid":%s,"account":"%s","cwd":"/x"}\n' "$pane" "$sid" "$pid" "${acct#.}" > "$H/reg/$pane.json"
      else
        pid="$(par_leaf "$sid")"; sleep 0.3
      fi
      [ "$cfg" = none ] || printf '%s' "${st[$cfg]}" > "$H/env/$pid"
    done < <(jq -r '.holders[] | [.cfg, (.pane // "null")] | @tsv' <<< "$c")
    kv="$(jq -r '(.env // {}) | to_entries[] | "\(.key)=\(.value)"' <<< "$c")"
    got="$( export HOME="$H" CC_REGISTRY_DIR="$H/reg" LR_STATE_DIR="$H/state" LR_MOVE_ENV_DIR="$H/env" \
              CC_HANDOFF_LOG="$H/handoffs.jsonl"; : > "$CC_HANDOFF_LOG"
            unset LR_CONFIG_DIRS LR_SUCCESSOR_GATE LR_HUSK_RETIRE
            while IFS= read -r e; do [ -z "$e" ] || export "${e?}"; done <<< "$kv"
            out="$(lr_successor_state "$sid" "${st[src]}")" && printf '%s' "${out%% *}" || printf null )"
    want="$(jq -r '.expect // "null"' <<< "$c")"
    [ "$got" = "$want" ] || fails="$fails"$'\n'"  [$i] $(jq -r .name <<< "$c"): got $got, want $want"
  done
  [ -z "$fails" ] || { echo "parity broken:$fails"; false; }
}

# ── team membership (teammate resurrection 2026-10-16, REPORT.md § 4.2 step 1) ───────────────────
member_fixture() { # → $MSID, $MCWD, $MTX (exact-slug member transcript under $CFG)
  # shellcheck disable=SC1091  # resolved from $REPO at run time
  . "$REPO/tests/helpers/member-transcript.sh"
  MSID="5423f92a-9089-4690-8c85-28ffc4018768"; MCWD="/Users/x/wt-pool-5"
  MTX="$CFG/projects/-Users-x-wt-pool-5/$MSID.jsonl"
  mk_member_transcript "$MTX" "$MSID" session-3cbb68e5 web-next16
}

@test "lr_team_member: the 2.1.293 head is a member, found through the EXACT slug before any glob" {
  member_fixture
  # A decoy under an earlier-sorting project dir: a glob would hit it first and read "not a member".
  mk_plain_transcript "$CFG/projects/-A-decoy/$MSID.jsonl" "$MSID"
  run lr_team_member "$MSID" "$CFG" "$MCWD"
  [ "$status" -eq 0 ]; [ "$output" = "$MTX" ]
  # the first user record is past 8 KB, so the 32 KB head is what reaches the member records
  [ "$(head -c 8192 "$MTX" | grep -c '"type":"user"')" = 0 ]
}

@test "lr_team_member: a lead head and a plain head are not members; no transcript is 1" {
  member_fixture
  mk_lead_transcript "$CFG/projects/$SLUG/lead1.jsonl" lead1
  mk_plain_transcript "$CFG/projects/$SLUG/plain1.jsonl" plain1
  run lr_team_member lead1 "$CFG" /Users/x/thing;  [ "$status" -eq 1 ]
  run lr_team_member plain1 "$CFG" /Users/x/thing; [ "$status" -eq 1 ]
  run lr_team_member nosuch "$CFG" /Users/x/thing; [ "$status" -eq 1 ]
}

@test "lr_team_member: a named store is globbed alone; an empty cfg walks every store" {
  member_fixture
  run lr_team_member "$MSID" "$OTHER" "/Users/x/elsewhere"; [ "$status" -eq 1 ]
  LR_CONFIG_DIRS="$OTHER:$CFG" run lr_team_member "$MSID" "" "/Users/x/elsewhere"
  [ "$status" -eq 0 ]; [ "$output" = "$MTX" ]
}

@test "lr_team_member: the key present but the predicate unrunnable is UNDECIDED (2), never 'not a member'" {
  member_fixture
  mkdir -p "$BATS_TEST_TMPDIR/nolib"
  LR_LIB_DIR="$BATS_TEST_TMPDIR/nolib" run lr_team_member "$MSID" "$CFG" "$MCWD"
  [ "$status" -eq 2 ]
}

@test "lr_team_member: runs under /bin/bash 3.2" {
  [ -x /bin/bash ] || skip "no /bin/bash"
  member_fixture
  run /bin/bash -c '. "$1"; lr_team_member "$2" "$3" "$4"' _ "$LIB" "$MSID" "$CFG" "$MCWD"
  [ "$status" -eq 0 ]; [ "$output" = "$MTX" ]
}

@test "lr_member_row: present, absent row, absent file" {
  mkdir -p "$CFG/teams/t1"
  printf '{"members":[{"name":"team-lead"},{"name":"web-next16"}]}\n' > "$CFG/teams/t1/config.json"
  run lr_member_row "$CFG" t1 web-next16; [ "$status" -eq 0 ]
  run lr_member_row "$CFG" t1 web-small;  [ "$status" -eq 1 ]
  run lr_member_row "$CFG" t2 web-next16; [ "$status" -eq 1 ]
}

@test "lr_death_after: the since filter, the sid filter and the pid column" {
  export CC_CRASH_LOG="$BATS_TEST_TMPDIR/crashes.jsonl"
  {
    printf '{"ts":"2026-10-16T23:24:48Z","sid":"S1","pid":15617,"class":"RECYCLE","cause":"deliberate-teardown"}\n'
    printf 'torn{\n'
    printf '{"ts":"2026-10-16T23:26:00Z","sid":"S1","pid":80169,"class":"RECYCLE","cause":"retired-teammate"}\n'
    printf '{"ts":"2026-10-16T23:26:05Z","sid":"S2","pid":9,"class":"CRASH","cause":"x"}\n'
  } > "$CC_CRASH_LOG"
  run lr_death_after S1 2026-10-16T23:25:00Z
  [ "$status" -eq 0 ]; [ "$output" = "2026-10-16T23:26:00Z 80169 RECYCLE retired-teammate" ]
  run lr_death_after S1 2026-10-16T23:00:00Z
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == *" 15617 "* ]] || false
  run lr_death_after S1 2026-10-17T00:00:00Z; [ "$status" -eq 1 ]
  CC_CRASH_LOG="$BATS_TEST_TMPDIR/absent" run lr_death_after S1 x; [ "$status" -eq 2 ]
}

@test "lr_death_wait: returns at once when our launcher spawned nothing in this move" {
  export CC_CRASH_LOG="$BATS_TEST_TMPDIR/crashes.jsonl"; : > "$CC_CRASH_LOG"
  run_dir="$BATS_TEST_TMPDIR/run"; mkdir -p "$run_dir"
  printf '{"ts":"2026-10-16T23:24:05Z","state":"lru-step","stage":"claim"}\n' > "$run_dir/events.jsonl"
  s=$SECONDS
  LR_DEATH_VERDICT_WAIT_S=30 run lr_death_wait S1 2026-10-16T23:24:00Z 15617 "$run_dir"
  [ "$status" -eq 0 ]; [ $((SECONDS - s)) -lt 5 ]
}

@test "lr_death_wait: waits for a verdict on a pid other than the old one, and is bounded" {
  export CC_CRASH_LOG="$BATS_TEST_TMPDIR/crashes.jsonl"
  printf '{"ts":"2026-10-16T23:24:48Z","sid":"S1","pid":15617,"class":"RECYCLE","cause":"deliberate-teardown"}\n' > "$CC_CRASH_LOG"
  run_dir="$BATS_TEST_TMPDIR/run"; mkdir -p "$run_dir"
  printf '{"ts":"2026-10-16T23:24:52Z","state":"relaunch-typed","stage":"expect"}\n' > "$run_dir/events.jsonl"
  # only the old pid's row exists ⇒ the full (1 s) bound is spent
  s=$SECONDS
  LR_DEATH_VERDICT_WAIT_S=1 LR_DEATH_POLL_S=1 run lr_death_wait S1 2026-10-16T23:24:00Z 15617 "$run_dir"
  [ "$status" -eq 0 ]; [ $((SECONDS - s)) -ge 1 ]
  # a row for the relaunched pid ⇒ no wait at all
  printf '{"ts":"2026-10-16T23:26:00Z","sid":"S1","pid":80169,"class":"RECYCLE","cause":"retired-teammate"}\n' >> "$CC_CRASH_LOG"
  s=$SECONDS
  LR_DEATH_VERDICT_WAIT_S=30 run lr_death_wait S1 2026-10-16T23:24:00Z 15617 "$run_dir"
  [ "$status" -eq 0 ]; [ $((SECONDS - s)) -lt 5 ]
}
