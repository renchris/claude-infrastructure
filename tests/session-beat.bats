#!/usr/bin/env bats
# session-beat.bats — the presence BEAT: producer (hooks/session-beat.sh) + reader (hooks/lib/cc-beat.sh).
#
# The beat exists so "who drove the last turn" is ATTESTED once, at the instant it is known, instead
# of re-derived from multi-MB transcripts by every closer on every sweep. Its correctness is what the
# act-time re-take and the 60s freshness lease both rest on.
#
# `[ ]` throughout — a non-final `[[ ]]` is errexit-EXEMPT under bats and therefore a DEAD assertion.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # Fixture $HOME FIRST: the producer and reader both default CC_BEAT_DIR to $HOME/.claude/cc-beats,
  # so an unfixtured suite would write beats into the operator's LIVE registry — and a live beat is
  # exactly what the reaper reads to decide a close. Hermetic by construction, not by convention.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  BEAT="$REPO/hooks/session-beat.sh"
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats"
  # shellcheck source=/dev/null
  . "$REPO/hooks/lib/cc-beat.sh"
}

# The producer DETACHES its write and returns at once (load-hook-timeouts-2026-10-11 item 7), so a
# caller that reads the beat must wait for it. wait_beat polls, bounded, until <sid>'s beat exists
# with seq > <after>; the 45 s bound is inside the 60 s freshness contract the reader relies on
# (sized for a machine at load ~600, where one `ps` start can take most of a second).
beat_seq() { jq -r '.seq // 0' "$CC_BEAT_DIR/$1.json" 2>/dev/null || echo 0; }
wait_beat() { # <sid> [after-seq]
  local n=0
  while [ "$n" -lt 450 ]; do
    [ "$(beat_seq "$1")" -gt "${2:-0}" ] 2>/dev/null && return 0
    sleep 0.1; n=$((n + 1))
  done
  echo "no beat for $1 past seq ${2:-0} within 45 s" >&2; return 1
}

emit() { # <json-stdin> <kind> — one beat, returned once it is ON DISK
  local sid before
  sid="$(printf '%s' "$1" | jq -r '.session_id // empty' 2>/dev/null)"
  before="$(beat_seq "$sid")"
  printf '%s' "$1" | /bin/bash "$BEAT" "${2:-prompt}"
  wait_beat "$sid" "$before"
}

# For a payload the producer refuses BEFORE it detaches (kill switch, no sid, hostile sid): nothing
# is forked, so there is nothing to wait for and the absence is final when this returns.
emit_nowait() { # <json-stdin> <kind>
  printf '%s' "$1" | /bin/bash "$BEAT" "${2:-prompt}"
}

@test "an operator prompt is attested who=operator and sets operatorT" {
  emit '{"session_id":"s1","cwd":"/tmp","prompt":"please fix the reaper"}' prompt
  [ "$(jq -r '.who' "$CC_BEAT_DIR/s1.json")" = "operator" ]
  [ "$(jq -r '.operatorT != null' "$CC_BEAT_DIR/s1.json")" = "true" ]
}

@test "AUTO-TRAFFIC is not presence: a Stop-hook re-prompt reads who=auto with NO operatorT" {
  # Load-bearing, not cosmetic: our own auto-drive arrives through UserPromptSubmit. A presence
  # signal that counted its own auto-drive would hold every self-driving session open forever and
  # deadlock every recycle — the exact reason the shared auto-traffic regex exists.
  emit '{"session_id":"s2","cwd":"/tmp","prompt":"Stop hook feedback: keep going"}' prompt
  [ "$(jq -r '.who' "$CC_BEAT_DIR/s2.json")" = "auto" ]
  [ "$(jq -r '.operatorT' "$CC_BEAT_DIR/s2.json")" = "null" ]
  run cb_operator_age s2
  [ "$status" -ne 0 ]        # UNKNOWN, never "0 seconds ago"
  [ -z "$output" ]
}

@test "task-notification traffic is also not presence (second auto-traffic form)" {
  emit '{"session_id":"s2b","cwd":"/tmp","prompt":"<task-notification>done</task-notification>"}' prompt
  [ "$(jq -r '.who' "$CC_BEAT_DIR/s2b.json")" = "auto" ]
}

@test "operatorT is STICKY: a later auto beat must never lower it" {
  # Presence, once shown, decays only by the clock. A Stop beat landing after an operator prompt
  # must not erase the very evidence that protects the pane from being reaped.
  emit '{"session_id":"s3","cwd":"/tmp","prompt":"do the thing"}' prompt
  before="$(jq -r '.operatorT' "$CC_BEAT_DIR/s3.json")"
  emit '{"session_id":"s3","cwd":"/tmp"}' stop
  [ "$(jq -r '.kind' "$CC_BEAT_DIR/s3.json")" = "stop" ]
  [ "$(jq -r '.who'  "$CC_BEAT_DIR/s3.json")" = "auto" ]
  [ "$(jq -r '.operatorT' "$CC_BEAT_DIR/s3.json")" = "$before" ]
  [ "$(jq -r '.seq' "$CC_BEAT_DIR/s3.json")" -eq 2 ]
}

@test "cb_operator_age reports the age against a pinned clock" {
  emit '{"session_id":"s4","cwd":"/tmp","prompt":"hello"}' prompt
  t="$(jq -r '.operatorT' "$CC_BEAT_DIR/s4.json")"
  CC_BEAT_NOW="$(( t + 300 ))" run cb_operator_age s4
  [ "$status" -eq 0 ]
  [ "$output" -eq 300 ]
}

@test "a backwards clock cannot forge a huge age (which would read as 'operator long gone')" {
  emit '{"session_id":"s5","cwd":"/tmp","prompt":"hello"}' prompt
  t="$(jq -r '.operatorT' "$CC_BEAT_DIR/s5.json")"
  CC_BEAT_NOW="$(( t - 5000 ))" run cb_operator_age s5
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]        # clamped to the SAFE direction (present), never a large stale age
}

@test "a torn/partial beat reads as ABSENT, never as a malformed 'no operator' answer" {
  mkdir -p "$CC_BEAT_DIR"
  printf '{"sid":"s6","who":"oper' > "$CC_BEAT_DIR/s6.json"     # truncated write
  run cb_last_beat s6
  [ "$status" -ne 0 ]
  run cb_operator_age s6
  [ "$status" -ne 0 ]        # UNKNOWN ⇒ the caller fails CLOSED
}

@test "EXISTENCE GATE: cb_system_live is false with no beat dir, true with a fresh beat" {
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/absent-beats"
  run cb_system_live
  [ "$status" -ne 0 ]
  # positive control beside the absence assertion — proves the gate can say LIVE, so the negative
  # above is attributable to absence and not to a predicate that never returns 0.
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats2"
  emit '{"session_id":"s7","cwd":"/tmp","prompt":"hi"}' prompt
  run cb_system_live
  [ "$status" -eq 0 ]
}

@test "EXISTENCE GATE: only STALE beats ⇒ not live (the producer stopped)" {
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats3"; mkdir -p "$CC_BEAT_DIR"
  printf '{"sid":"s8","t":1000000000,"who":"auto","operatorT":null,"seq":1}\n' > "$CC_BEAT_DIR/s8.json"
  run cb_system_live
  [ "$status" -ne 0 ]
  CC_BEAT_LIVE_MAX_S=999999999 run cb_system_live
  [ "$status" -eq 0 ]        # differential: the same beat IS live under a wide window
}

@test "kill switch CC_BEAT=off writes nothing — and with it ON the same call writes (differential)" {
  CC_BEAT=off emit_nowait '{"session_id":"s9","cwd":"/tmp","prompt":"hi"}' prompt
  [ ! -f "$CC_BEAT_DIR/s9.json" ]
  emit '{"session_id":"s9","cwd":"/tmp","prompt":"hi"}' prompt
  [ -f "$CC_BEAT_DIR/s9.json" ]
}

@test "FAIL-OPEN producer: garbage stdin and a missing sid still exit 0 (a beat must never cost a session)" {
  run emit_nowait 'not json at all' prompt
  [ "$status" -eq 0 ]
  run emit_nowait '{"cwd":"/tmp","prompt":"no sid here"}' prompt
  [ "$status" -eq 0 ]
}

@test "a path-hostile sid is refused, never written outside the beat dir" {
  emit_nowait '{"session_id":"../../escape","cwd":"/tmp","prompt":"hi"}' prompt
  [ ! -e "$BATS_TEST_TMPDIR/escape.json" ]
  [ ! -e "$CC_BEAT_DIR/../../escape.json" ]
}

# ══ TZ PIN — the (pid,lstart) identity must not carry the writer's zone ══════════════════════════
#
# `ps -o lstart=` renders in the AMBIENT zone. Until 2026-09-08 both the writer here and the reader in
# scripts/lib/spawn-presence.sh sampled it unpinned, so the identity only ever matched when the two
# zones happened to agree — measured over 51 live beats, 0 matched a `TZ=UTC` reader and 22 matched an
# ambient one — and at the next DST change EVERY row would have re-rendered and read as a different
# process while the sessions were still alive (memory
# process-start-time-renders-in-ambient-timezone). `bin/cc-await-ping`'s `_pid_ident` already pins
# both of its own samples; this is that idiom applied to the stored field.

@test "TZ PIN: lstart is UTC-rendered, so two ambient zones write ONE identity" {
  # RED pre-fix: Chicago and Tokyo are 14h apart, so the two beats disagree on the same process.
  printf '%s' '{"session_id":"tzA","cwd":"/tmp","prompt":"hi"}' \
    | env TZ=America/Chicago /bin/bash "$BEAT" prompt
  printf '%s' '{"session_id":"tzB","cwd":"/tmp","prompt":"hi"}' \
    | env TZ=Asia/Tokyo /bin/bash "$BEAT" prompt
  wait_beat tzA; wait_beat tzB
  a="$(jq -r '.lstart' "$CC_BEAT_DIR/tzA.json")"
  b="$(jq -r '.lstart' "$CC_BEAT_DIR/tzB.json")"
  [ -n "$a" ]
  [ "$a" = "$b" ]
}

@test "TZ PIN: the stored lstart IS the UTC rendering of the recorded pid, not a matching ambient pair" {
  # The case above is satisfiable by any zone-independent string; this one names the zone. Skipped
  # only where the ambient zone IS UTC, because there the two renderings are identical by
  # construction and the assertion could not discriminate (it would pass on the broken writer too).
  printf '%s' '{"session_id":"tzC","cwd":"/tmp","prompt":"hi"}' \
    | env TZ=America/Chicago /bin/bash "$BEAT" prompt
  wait_beat tzC
  pid="$(jq -r '.pid' "$CC_BEAT_DIR/tzC.json")"
  got="$(jq -r '.lstart' "$CC_BEAT_DIR/tzC.json")"
  utc="$(TZ=UTC ps -o lstart= -p "$pid" | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  amb="$(TZ=America/Chicago ps -o lstart= -p "$pid" | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  [ -n "$utc" ]
  [ "$got" = "$utc" ]
  if [ "$utc" != "$amb" ]; then [ "$got" != "$amb" ]; fi
}

@test "PANE: KITTY_WINDOW_ID is the last address fallback, so a kitty session beats with a pane" {
  # Without this the beat's pane provenance DISAGREES with the stop-failure marker's for exactly
  # the population that has no registry row: the marker (LIMIT_DETECT_100P W1) reads
  # CC_PANE_ID -> KITTY_WINDOW_ID -> ITERM, and this writer read only the first and last. A reader
  # comparing the two would see a conflict that is purely this gap, on the sessions least able to
  # afford one.
  printf '%s' '{"session_id":"kt","cwd":"/tmp","prompt":"hi"}' \
    | env -u CC_PANE_ID -u ITERM_SESSION_ID KITTY_WINDOW_ID=186 /bin/bash "$BEAT" prompt
  wait_beat kt
  [ "$(jq -r '.pane' "$CC_BEAT_DIR/kt.json")" = 186 ]

  # LAST, not first: a session that resolves today keeps the SAME pane when a kitty id is also in
  # the environment. Appending a fallback must never re-address an existing population.
  printf '%s' '{"session_id":"kb","cwd":"/tmp","prompt":"hi"}' \
    | env -u CC_PANE_ID ITERM_SESSION_ID='w0t0p0:112' KITTY_WINDOW_ID=999 /bin/bash "$BEAT" prompt
  wait_beat kb
  [ "$(jq -r '.pane' "$CC_BEAT_DIR/kb.json")" = 112 ]

  # and with no address at all the beat is still written — a missing pane must never cost a beat,
  # because the beat is what keeps the session counted as alive.
  printf '%s' '{"session_id":"kn","cwd":"/tmp","prompt":"hi"}' \
    | env -u CC_PANE_ID -u ITERM_SESSION_ID -u KITTY_WINDOW_ID /bin/bash "$BEAT" prompt
  wait_beat kn
  [ -s "$CC_BEAT_DIR/kn.json" ]
  [ "$(jq -r '.pane' "$CC_BEAT_DIR/kn.json")" = "" ]
}

# ══ OFF THE PROMPT PATH — the producer detaches its work (load-hook-timeouts-2026-10-11 item 7) ══
#
# Every prompt of every session runs this hook, and it used to hold the turn for six jq starts and up
# to 24 `ps` (the ancestry walk) under a 3 s cap. It now pays one jq parse in the foreground and
# detaches the rest. The `ps` stub below stalls the walk's FIRST call for 10 s: a foreground walk
# cannot return before that, a detached one returns at once and the beat lands after it.

slow_ps_stub() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\nif [ -n "${BEAT_SLOW_PS:-}" ] && mkdir "$BEAT_SLOW_PS" 2>/dev/null; then sleep 10; fi\nexec /bin/ps "$@"\n' \
    > "$BATS_TEST_TMPDIR/bin/ps"
  chmod +x "$BATS_TEST_TMPDIR/bin/ps"
}

@test "OFF PATH: the hook returns while a stalled walk is still running, and the beat lands fresh" {
  slow_ps_stub
  start=$SECONDS
  # $( ) waits for EOF on the hook's stdout, so this also proves the worker does not hold the pipe.
  out="$(printf '%s' '{"session_id":"op1","cwd":"/tmp","prompt":"hello"}' \
    | env PATH="$BATS_TEST_TMPDIR/bin:$PATH" BEAT_SLOW_PS="$BATS_TEST_TMPDIR/stalled" CC_BEAT_TIMEOUT=40 \
      /bin/bash "$BEAT" prompt)"
  elapsed=$(( SECONDS - start ))
  [ -z "$out" ]
  # The DESIGN target is <1 s (one jq start); measured at 0 s on an idle box. The bound asserted is
  # looser because $SECONDS is whole seconds and, at load ~600, bash + one jq start alone has taken
  # 2 s here; the 10 s stall is what a foreground hook could not get under.
  [ "$elapsed" -le 4 ] || { echo "hook held the prompt ${elapsed}s" >&2; false; }
  # Non-vacuity, and the load-proof half: the stub DID stall the walk (the worker reached it) and the
  # beat is not yet written, so the return above is the detach, not a walk that never ran. (The
  # worker may reach its first `ps` just after the hook returns; once it has, the beat is ≥10 s away.)
  n=0; while [ ! -d "$BATS_TEST_TMPDIR/stalled" ] && [ "$n" -lt 80 ]; do sleep 0.1; n=$((n + 1)); done
  [ -d "$BATS_TEST_TMPDIR/stalled" ]
  [ ! -e "$CC_BEAT_DIR/op1.json" ]
  wait_beat op1
  [ "$(jq -r '.who' "$CC_BEAT_DIR/op1.json")" = operator ]
  t="$(jq -r '.t' "$CC_BEAT_DIR/op1.json")"
  [ $(( $(date +%s) - t )) -le 60 ]      # the reader's freshness contract
}

@test "OFF PATH: a lock left by a killed worker costs no wait, never the beat, and is cleared" {
  # The per-sid lock serializes a session's detached read-modify-writes (a slow prompt worker must
  # not let a later Stop worker write back a stale operatorT). A worker killed by its HARD timeout
  # while holding it must not cost every later beat. The lock names its holder's pid; a dead one is
  # taken over at once.
  mkdir -p "$CC_BEAT_DIR"
  /bin/sh -c 'exit 0' & dead=$!; wait "$dead"
  ln -s "$dead" "$CC_BEAT_DIR/.lk1.lk"
  emit '{"session_id":"lk1","cwd":"/tmp","prompt":"hi"}' prompt
  n=0; while [ -L "$CC_BEAT_DIR/.lk1.lk" ] && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
  [ ! -L "$CC_BEAT_DIR/.lk1.lk" ]
  [ "$(jq -r '.who' "$CC_BEAT_DIR/lk1.json")" = operator ]
}

@test "OFF PATH: a LIVE holder's lock is never taken over or removed; the waiter still writes its beat" {
  # At load ~600 a read-modify-write can outlast any guessed bound, so a clock-only takeover would
  # let two writers run at once and the first one's unlock delete the second's lock. A live holder
  # (this test's own shell) is waited for — half the HARD timeout, 2 s here — and then the waiter
  # writes without the lock and leaves the holder's in place.
  mkdir -p "$CC_BEAT_DIR"
  ln -s "$$" "$CC_BEAT_DIR/.lv1.lk"
  printf '%s' '{"session_id":"lv1","cwd":"/tmp","prompt":"hi"}' | CC_BEAT_TIMEOUT=4 /bin/bash "$BEAT" prompt
  wait_beat lv1
  [ "$(jq -r '.who' "$CC_BEAT_DIR/lv1.json")" = operator ]
  [ "$(readlink "$CC_BEAT_DIR/.lv1.lk")" = "$$" ]
}

@test "OFF PATH: the HARD-timeout timer leaves no orphaned sleep behind" {
  # The timer subshell is stopped once the beat lands; its own `sleep` is this hook's child too and
  # must go with it, or every beat leaves a CC_BEAT_TIMEOUT-long sleep running (two per turn).
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\necho $$ >> "$BEAT_SLEEP_PIDS"\nexec /bin/sleep "$@"\n' > "$BATS_TEST_TMPDIR/bin/sleep"
  chmod +x "$BATS_TEST_TMPDIR/bin/sleep"
  export BEAT_SLEEP_PIDS="$BATS_TEST_TMPDIR/sleep.pids"
  printf '%s' '{"session_id":"sl1","cwd":"/tmp","prompt":"hi"}' \
    | env PATH="$BATS_TEST_TMPDIR/bin:$PATH" CC_BEAT_TIMEOUT=37 /bin/bash "$BEAT" prompt
  wait_beat sl1
  n=0; while [ ! -s "$BEAT_SLEEP_PIDS" ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
  [ -s "$BEAT_SLEEP_PIDS" ]      # non-vacuity: the timer's sleep went through the stub
  n=0; live=1
  while [ "$n" -lt 100 ]; do
    live=0
    while read -r p; do kill -0 "$p" 2>/dev/null && live=1; done < "$BEAT_SLEEP_PIDS"
    [ "$live" = 0 ] && break
    sleep 0.1; n=$((n + 1))
  done
  [ "$live" = 0 ] || { echo "orphaned sleep: $(cat "$BEAT_SLEEP_PIDS")" >&2; false; }
}

@test "OFF PATH: a beat that logs nothing creates no log file and no log directory under HOME" {
  # stop-failure-marker's footprint pin (SA9) diffs $HOME: the log is created only by the one line a
  # worker logs (a superseded beat), never by every run.
  emit "$(jq -nc '{session_id:"lg1",cwd:"/tmp",prompt:"hi"}')" prompt
  CC_BEAT_SYNC=1 emit_nowait '{"session_id":"lg2","cwd":"/tmp","prompt":"hi"}' prompt
  [ -s "$CC_BEAT_DIR/lg2.json" ]
  [ ! -e "$HOME/.claude/logs" ]
}

# ══ SYNC MODE — the `limited` kind (stop-failure-marker's death path) and CC_BEAT_SYNC=1 ═════════
#
# stop-failure-marker pipes into this hook, so its parent is not claude and its readers need the flip
# on disk when it returns. The `ps` stub stalls the walk's first call for 1 s: a detached beat cannot
# be on disk when the hook returns, a synchronous one must be.

stall1_ps_stub() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\nif [ -n "${BEAT_SLOW_PS:-}" ] && mkdir "$BEAT_SLOW_PS" 2>/dev/null; then sleep 1; fi\nexec /bin/ps "$@"\n' \
    > "$BATS_TEST_TMPDIR/bin/ps"
  chmod +x "$BATS_TEST_TMPDIR/bin/ps"
}

@test "SYNC: a limited beat is ON DISK when the hook returns, with no poll" {
  stall1_ps_stub
  printf '%s' '{"session_id":"sy1","cwd":"/tmp"}' \
    | env PATH="$BATS_TEST_TMPDIR/bin:$PATH" BEAT_SLOW_PS="$BATS_TEST_TMPDIR/stalled1" CC_BEAT_TIMEOUT=30 \
      /bin/bash "$BEAT" limited
  [ -d "$BATS_TEST_TMPDIR/stalled1" ]           # non-vacuity: the walk did stall
  [ "$(jq -r '.kind' "$CC_BEAT_DIR/sy1.json")" = limited ]
}

@test "SYNC: CC_BEAT_SYNC=1 makes any kind synchronous; without it a prompt beat is detached" {
  stall1_ps_stub
  printf '%s' '{"session_id":"sy2","cwd":"/tmp","prompt":"hi"}' \
    | env PATH="$BATS_TEST_TMPDIR/bin:$PATH" BEAT_SLOW_PS="$BATS_TEST_TMPDIR/stalled2" CC_BEAT_TIMEOUT=30 \
      CC_BEAT_SYNC=1 /bin/bash "$BEAT" prompt
  [ "$(jq -r '.who' "$CC_BEAT_DIR/sy2.json")" = operator ]
  # differential: the same call without the switch returns before its stalled walk can write
  printf '%s' '{"session_id":"sy3","cwd":"/tmp","prompt":"hi"}' \
    | env PATH="$BATS_TEST_TMPDIR/bin:$PATH" BEAT_SLOW_PS="$BATS_TEST_TMPDIR/stalled3" CC_BEAT_TIMEOUT=30 \
      /bin/bash "$BEAT" prompt
  [ ! -e "$CC_BEAT_DIR/sy3.json" ]
  wait_beat sy3
}

@test "the who regex runs in bash and agrees with the reader's jq test on multi-line and unicode prompts" {
  # Every alternative is ^-anchored; neither engine may read ^ as a line anchor, or a pasted log
  # whose SECOND line starts with ⟳ would flip an operator prompt to auto.
  emit "$(jq -nc '{session_id:"rx1",cwd:"/tmp",prompt:"look at this\n⟳ recycled"}')" prompt
  [ "$(jq -r '.who' "$CC_BEAT_DIR/rx1.json")" = operator ]
  emit "$(jq -nc '{session_id:"rx2",cwd:"/tmp",prompt:"⚑ boundary advisory"}')" prompt
  [ "$(jq -r '.who' "$CC_BEAT_DIR/rx2.json")" = auto ]
  emit "$(jq -nc '{session_id:"rx3",cwd:"/tmp",prompt:"[Request interrupted by user]"}')" prompt
  [ "$(jq -r '.who' "$CC_BEAT_DIR/rx3.json")" = auto ]
}

# ══ ORDER BY EVENT — two detached workers of one session must leave the LATER boundary on disk ══
#
# Detached, a turn's prompt beat and its Stop beat are separate workers; the per-sid lock stops them
# writing at once but not from landing out of order. A stalled worker used to win by arriving last,
# leaving the previous boundary's kind on disk (cc-wake, session-busy and cc-await-ping all read it).
# The `ps` stub below HOLDS the first worker's walk until the test releases it, so the earlier event
# deterministically reaches the lock second.

held_ps_stub() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\nif [ -n "${BEAT_HOLD_PS:-}" ] && mkdir "$BEAT_HOLD_PS" 2>/dev/null; then n=0; while [ ! -e "$BEAT_HOLD_PS/release" ] && [ "$n" -lt 400 ]; do sleep 0.1; n=$((n + 1)); done; fi\nexec /bin/ps "$@"\n' \
    > "$BATS_TEST_TMPDIR/bin/ps"
  chmod +x "$BATS_TEST_TMPDIR/bin/ps"
}

held_emit() { # <json-stdin> <kind> — fire a beat whose worker is held at its first `ps`
  printf '%s' "$1" | env PATH="$BATS_TEST_TMPDIR/bin:$PATH" BEAT_HOLD_PS="$BATS_TEST_TMPDIR/held" \
    CC_BEAT_TIMEOUT=60 /bin/bash "$BEAT" "$2"
  local n=0
  while [ ! -d "$BATS_TEST_TMPDIR/held" ] && [ "$n" -lt 200 ]; do sleep 0.1; n=$((n + 1)); done
  [ -d "$BATS_TEST_TMPDIR/held" ]
}

# The released worker has settled once it logs its supersession — or, on a hook that does not order
# by event, once it writes over the beat (seq past <ceiling>), which the kind assertion then catches.
release_and_settle() { # <sid> <seq-ceiling>
  local n=0
  touch "$BATS_TEST_TMPDIR/held/release"
  while [ "$n" -lt 450 ]; do
    grep -q "sid=$1 .*superseded" "$CC_BEAT_LOG" 2>/dev/null && return 0
    [ "$(beat_seq "$1")" -gt "$2" ] 2>/dev/null && return 0
    sleep 0.1; n=$((n + 1))
  done
  echo "held worker for $1 never settled within 45 s" >&2; return 1
}

@test "ORDER: a stalled prompt worker cannot overwrite the later Stop beat, but still raises operatorT" {
  export CC_BEAT_LOG="$BATS_TEST_TMPDIR/beat.log"
  held_ps_stub
  held_emit '{"session_id":"or1","cwd":"/tmp","prompt":"quick question"}' prompt
  emit '{"session_id":"or1","cwd":"/tmp"}' stop
  [ "$(jq -r '.kind' "$CC_BEAT_DIR/or1.json")" = stop ]
  release_and_settle or1 1
  [ "$(jq -r '.kind' "$CC_BEAT_DIR/or1.json")" = stop ]
  [ "$(jq -r '.who'  "$CC_BEAT_DIR/or1.json")" = auto ]
  [ "$(jq -r '.seq'  "$CC_BEAT_DIR/or1.json")" -eq 1 ]
  # presence is still kept: the late operator prompt raised the sticky mark on the Stop beat
  [ "$(jq -r '.operatorT != null' "$CC_BEAT_DIR/or1.json")" = true ]
}

@test "ORDER: a stalled prompt worker cannot overwrite the next turn's prompt beat" {
  # The Stop beat is synchronous (it is not on the prompt path), so the out-of-order pair that is
  # still possible is two detached prompt workers: an operator prompt stalled behind a later
  # machine-fed one. The later boundary's `who` must survive, and the stalled one only raises operatorT.
  export CC_BEAT_LOG="$BATS_TEST_TMPDIR/beat.log"
  held_ps_stub
  held_emit '{"session_id":"or2","cwd":"/tmp","prompt":"quick question"}' prompt
  emit '{"session_id":"or2","cwd":"/tmp","prompt":"Stop hook feedback: keep going"}' prompt
  [ "$(jq -r '.who' "$CC_BEAT_DIR/or2.json")" = auto ]
  release_and_settle or2 1
  [ "$(jq -r '.kind' "$CC_BEAT_DIR/or2.json")" = prompt ]
  [ "$(jq -r '.who'  "$CC_BEAT_DIR/or2.json")" = auto ]
  [ "$(jq -r '.seq'  "$CC_BEAT_DIR/or2.json")" -eq 1 ]
  [ "$(jq -r '.operatorT != null' "$CC_BEAT_DIR/or2.json")" = true ]
}

@test "SYNC: a stop beat is ON DISK when the hook returns, with no poll (cc-await-ping's arm baseline)" {
  stall1_ps_stub
  printf '%s' '{"session_id":"sy4","cwd":"/tmp"}' \
    | env PATH="$BATS_TEST_TMPDIR/bin:$PATH" BEAT_SLOW_PS="$BATS_TEST_TMPDIR/stalled4" CC_BEAT_TIMEOUT=30 \
      /bin/bash "$BEAT" stop
  [ -d "$BATS_TEST_TMPDIR/stalled4" ]           # non-vacuity: the walk did stall
  [ "$(jq -r '.kind' "$CC_BEAT_DIR/sy4.json")" = stop ]
}

@test "the one-jq parse keeps an empty cwd from shifting fields, and restores an escaped cwd byte-for-byte" {
  emit "$(jq -nc '{session_id:"cw1",cwd:"",prompt:"hi"}')" prompt
  [ "$(jq -r '.cwd' "$CC_BEAT_DIR/cw1.json")" = "$PWD" ]
  [ "$(jq -r '.who' "$CC_BEAT_DIR/cw1.json")" = operator ]
  emit "$(jq -nc '{session_id:"cw2",cwd:"/tmp/a\\b\tc",prompt:"hi"}')" prompt
  [ "$(jq -r '.cwd == "/tmp/a\\b\tc"' "$CC_BEAT_DIR/cw2.json")" = true ]
}
