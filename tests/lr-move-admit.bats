#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent; stub bodies expand in the stub
# scripts/limit-recover/lr-move-batch.sh — ADMISSION: what a row must prove before it may take a claim,
# and how long a batch waits for the admit section (lr-inplace-immediacy G, 2026-10-17/18).
#
# Measured on the 17 batches of 2026-10-17/18: 10 rows whose intents had ALREADY expired when their
# batch started still took 8 claims, 8 workers and all 4 swap slots, and won every claim collision
# (8 rows with a valid intent lost to them), because only lr-handoff read the intent, at W5.
#
# Every case runs the runner under /bin/bash, as the poller's lrp_move_kick starts it (bash 3.2).
# Hermetic: sessions are `sleep`s; lr-handoff, claude-accounts and cc-notify are recorders.

setup() {
  command -v jq >/dev/null || skip "jq required"
  [ -x /bin/bash ] || skip "/bin/bash absent"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LR_MOVE_ENV_DIR="$BATS_TEST_TMPDIR/penv"; mkdir -p "$LR_MOVE_ENV_DIR"
  export CC_ADMIT_GATE=off CC_FIRE_CAPACITY_GATE=off
  # shellcheck source=/dev/null
  . "$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/helpers/lr-move-fixture.sh"
  mvf_setup
  mvf_handoff_stub
  export STUB_BOOT_S=0.3
  export CC_ACCOUNTS_BIN="$STUBS/claude-accounts" RANK_LOG="$BATS_TEST_TMPDIR/rank.log"; : > "$RANK_LOG"
  # RANK_MODE=fail-first: the first read cannot answer, the --fresh retry ranks the target.
  cat > "$CC_ACCOUNTS_BIN" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$RANK_LOG"
if [ "${RANK_MODE:-ok}" = fail-first ] && [ "$(grep -c . "$RANK_LOG")" -le 1 ]; then exit 3; fi
printf 'next3 0.9\nnext2 0.4\n'
STUB
  chmod +x "$CC_ACCOUNTS_BIN"
  export CC_NOTIFY_BIN="$STUBS/cc-notify" NOTIFY_LOG="$BATS_TEST_TMPDIR/notify.log"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$NOTIFY_LOG"\n' > "$CC_NOTIFY_BIN"; chmod +x "$CC_NOTIFY_BIN"
  : > "$NOTIFY_LOG"
  export LR_MOVE_GUARD_CHECK=off
  N=2; ROWS=(); SIDS=()
  for i in $(seq 1 "$N"); do
    sid="$(printf 'eeee%04d-0000-4000-8000-000000000001' "$i")"
    mvf_session "$((700 + i))" "$sid"
    ROWS+=("$((700 + i)):$sid"); SIDS+=("$sid")
  done
  MVF_SLOTS=2 mvf_plan m1 move "${ROWS[@]}"
  CLAIMS="$LR_STATE_DIR/runs/by-sid"
}
teardown() { mvf_teardown; }

batch() { run /bin/bash "$LRD/lr-move-batch.sh" m1; }
ALOCK_T() { printf '%s' "$LR_STATE_DIR/locks/move-admit.lock"; }
hold_admit_lock() { # a LIVE holder of the admit section: a sleep this test started, pid-only (no lstart)
  /bin/sleep 300 3>&- &
  HOLDER=$!; MVF_PIDS="$MVF_PIDS $HOLDER"
  mkdir -p "$(ALOCK_T)"; printf '%s\n' "$HOLDER" > "$(ALOCK_T)/pid"
}
fast_clock() { # every `date +%s` is 100 s after the last; `sleep` returns at once and is counted
  CLK="$BATS_TEST_TMPDIR/clk"; mkdir -p "$CLK"; : > "$CLK/n"; : > "$CLK/sleeps"
  printf '#!/bin/bash\nif [ "$1" = +%%s ]; then n=$(( $(wc -l < "%s/n") )); echo x >> "%s/n"; echo $(( %s + n * 100 )); else exec /bin/date "$@"; fi\n' \
    "$CLK" "$CLK" "$(date +%s)" > "$CLK/date"
  printf '#!/bin/bash\necho "$*" >> "%s/sleeps"\n' "$CLK" > "$CLK/sleep"
  chmod +x "$CLK/date" "$CLK/sleep"
}
intent_edit() { # $1=sid $2=jq filter — keeps the intent 0600, as cc-lr writes it
  local f="$BDIR/intent/$1.json"
  ( umask 077; jq -c "$2" "$f" > "$f.t" ) && mv "$f.t" "$f"
}

@test "[RED] an intent that expired before the batch started: NOTMOVED intent-invalid, no claim, no worker; its valid sibling still gets one" {
  intent_edit "${SIDS[1]}" ".expires_epoch = $(( $(date +%s) - 60 ))"
  batch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"syntax error"* ]] || { echo "$output"; false; }
  run jq -r '"\(.verdict) \(.reason)"' "$BDIR/${SIDS[1]}.json"
  [[ "$output" == "NOTMOVED intent-invalid: expired: "*"(checked at admission, queued "*"s); nothing touched" ]] || { echo "$output"; false; }
  # No claim was even attempted: lr_claim_take's log is created by the attempt itself.
  [ ! -e "$BDIR/${SIDS[1]}.claim.log" ]
  [ ! -e "$CLAIMS/${SIDS[1]}.active" ]
  ! grep -q "^${SIDS[1]}" "$BDIR/workers.tsv" || { cat "$BDIR/workers.tsv"; false; }
  ! grep -q "^${SIDS[1]}" "$STUB_LOG/typers.log" 2>/dev/null || { cat "$STUB_LOG/typers.log"; false; }
  grep -q "^${SIDS[0]}"$'\t' "$BDIR/workers.tsv" || { cat "$BDIR/workers.tsv"; false; }
  [ "$(jq -r .verdict "$BDIR/${SIDS[0]}.json")" = MOVED ] || { cat "$BDIR/${SIDS[0]}.json"; false; }
}

@test "[RED] A2: an admitted row gets intent/<sid>.admitted (its admission epoch, 0600); a row refused at admission gets none" {
  intent_edit "${SIDS[1]}" ".expires_epoch = $(( $(date +%s) - 60 ))"
  t0="$(date +%s)"
  batch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  a="$BDIR/intent/${SIDS[0]}.admitted"
  [ -f "$a" ] || { ls -la "$BDIR/intent"; false; }
  [ ! -L "$a" ]
  v="$(cat "$a")"
  [ "$v" -ge "$t0" ] || { echo "admitted=$v t0=$t0"; false; }
  [ "$v" -le "$(date +%s)" ] || { echo "admitted=$v"; false; }
  m="$(stat -f %Lp "$a" 2>/dev/null || stat -c %a "$a")"
  [ "$m" = 600 ] || { echo "mode $m"; false; }
  [ ! -e "$BDIR/intent/${SIDS[1]}.admitted" ]
}

# A3. The admit wait counted ITERATIONS against LR_MOVE_ADMIT_WAIT_S: under load each took ~6.6 s,
# so "90s" was 599-600 s of wall time and 2 of 5 parallel batches were refused (G §2.2). With a clock
# that moves 100 s per read and a sleep that costs nothing, a wall-clock 900 s deadline refuses within
# 10 iterations; an iteration count would sleep 89 times and say "90s".
@test "[RED] A3: the admit wait is a wall-clock deadline (default 900 s), not an iteration count" {
  hold_admit_lock
  fast_clock
  PATH="$CLK:$PATH" run /bin/bash "$LRD/lr-move-batch.sh" m1
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  n="$(grep -c . "$CLK/sleeps" || true)"
  [ "$n" -le 10 ] || { echo "slept $n times"; false; }
  run jq -r '"\(.admitted) \(.reason)"' "$BDIR/admit.json"
  [[ "$output" == "false another batch held the admit section for 900s"* ]] || { echo "$output"; false; }
  # The live holder's lock is untouched.
  [ "$(cat "$(ALOCK_T)/pid")" = "$HOLDER" ]
}

# A4. The dead-holder steal read the pid file TWICE (inside lr_pidlock_live, then `cat` for evidence)
# and deleted whatever lock was there by then: on 2026-10-18 01:51:45Z two batches were inside the
# admit section at once (G §2.3). It now reads the pid ONCE, steals by an atomic rename, and keeps the
# renamed lock only when it still names the pid it judged dead; otherwise it puts it back and waits.
dead_admit_lock() { # a lock whose holder is DEAD: the pid of a sleep that has already exited
  /bin/sleep 0 3>&- & DEADPID=$!; wait "$DEADPID" 2>/dev/null || true
  mkdir -p "$(ALOCK_T)"; printf '%s\n' "$DEADPID" > "$(ALOCK_T)/pid"
}
hold_admit_lock_quiet() { # a live holder that has NOT written the lock yet (it arrives mid-steal)
  /bin/sleep 300 3>&- &
  HOLDER=$!; MVF_PIDS="$MVF_PIDS $HOLDER"
}

@test "[RED] A4: a new holder that arrives between the two reads of a dead lock is not robbed (cat wrapper)" {
  dead_admit_lock
  hold_admit_lock_quiet
  fast_clock
  # The FIRST read of the lock's pid returns the dead pid, then a new live holder takes the section.
  printf '#!/bin/bash\nfor a in "$@"; do case "$a" in */move-admit.lock/pid)\n  if [ ! -e "%s/fired" ]; then : > "%s/fired"; /bin/cat "$@"; printf "%%s\\n" %s > "$a"; exit 0; fi ;; esac; done\nexec /bin/cat "$@"\n' \
    "$CLK" "$CLK" "$HOLDER" > "$CLK/cat"
  chmod +x "$CLK/cat"
  PATH="$CLK:$PATH" run /bin/bash "$LRD/lr-move-batch.sh" m1
  [ -e "$CLK/fired" ]
  [[ "$output" != *"taking it"* ]] || { echo "$output"; false; }
  [ "$(jq -r .admitted "$BDIR/admit.json")" = false ] || { cat "$BDIR/admit.json"; false; }
  [ "$(cat "$(ALOCK_T)/pid")" = "$HOLDER" ]
}

@test "A4: what the steal renamed is verified — a lock re-taken just before the rename is put back (mv wrapper)" {
  dead_admit_lock
  hold_admit_lock_quiet
  fast_clock
  # The rename of the lock: a new live holder's pid is in it by the time it moves.
  printf '#!/bin/bash\ncase "$1|${2:-}" in *move-admit.lock\\|*.stale.*) printf "%%s\\n" %s > "$1/pid" ;; esac\nexec /bin/mv "$@"\n' \
    "$HOLDER" > "$CLK/mv"
  chmod +x "$CLK/mv"
  PATH="$CLK:$PATH" run /bin/bash "$LRD/lr-move-batch.sh" m1
  [[ "$output" != *"taking it"* ]] || { echo "$output"; false; }
  [ "$(jq -r .admitted "$BDIR/admit.json")" = false ] || { cat "$BDIR/admit.json"; false; }
  [ "$(cat "$(ALOCK_T)/pid")" = "$HOLDER" ]
  [ -z "$(compgen -G "$(ALOCK_T).stale.*" || true)" ] || { ls -la "$(dirname "$(ALOCK_T)")"; false; }
}

@test "A4: a lock whose holder is dead is still taken, once, and the batch is admitted" {
  dead_admit_lock
  batch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"move-admit lock held by a dead process"*"taking it"* ]] || { echo "$output"; false; }
  [ "$(jq -r .admitted "$BDIR/admit.json")" = true ] || { cat "$BDIR/admit.json"; false; }
  [ -z "$(compgen -G "$(ALOCK_T).stale.*" || true)" ] || { ls -la "$(dirname "$(ALOCK_T)")"; false; }
}

@test "[RED] A4: a router read that failed and then ranked on --fresh admits with the reason of the read that answered" {
  export RANK_MODE=fail-first
  batch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(grep -c . "$RANK_LOG")" -ge 2 ] || { cat "$RANK_LOG"; false; }
  run jq -r '"\(.admitted) \(.target_auth) \(.reason)"' "$BDIR/admit.json"
  [ "$output" = "true ok router: ranked" ] || { echo "$output"; false; }
}

# R. `cc-lr move` has just ranked the target (its strict router check) and records when, as the plan's
# router_ranked_epoch. The admit read took 5-132 s, 323 s with its --fresh retry (G §2.1): inside
# LR_MOVE_ROUTE_REUSE_S (120) admission reuses the answer and asks nothing. The close-time --fresh
# re-read is unchanged; LR_MOVE_AUTH_RECHECK=off here so the log counts admission alone.
ranked_ago() { # $1=seconds since cc-lr move ranked the target
  jq -c --argjson e "$(( $(date +%s) - $1 ))" '.router_ranked_epoch = $e' "$BDIR/plan.json" > "$BDIR/plan.json.t" && mv "$BDIR/plan.json.t" "$BDIR/plan.json"
}

@test "[RED] R: a plan ranked by cc-lr move 30 s ago is admitted without a router read, and says so" {
  export LR_MOVE_AUTH_RECHECK=off
  ranked_ago 30
  batch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(grep -c . "$RANK_LOG" || true)" -eq 0 ] || { cat "$RANK_LOG"; false; }
  run jq -r '"\(.admitted) \(.target_auth) \(.reason)"' "$BDIR/admit.json"
  [[ "$output" == "true ok router: ranked by cc-lr move "*"s ago" ]] || { echo "$output"; false; }
}

@test "R: a ranking 300 s old is stale: admission reads the router" {
  export LR_MOVE_AUTH_RECHECK=off
  ranked_ago 300
  batch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(grep -c . "$RANK_LOG" || true)" -eq 1 ] || { cat "$RANK_LOG"; false; }
  [ "$(jq -r .reason "$BDIR/admit.json")" = "router: ranked" ] || { cat "$BDIR/admit.json"; false; }
}

@test "R: kill switch LR_MOVE_ROUTE_REUSE_S=0 reads the router even for a fresh ranking" {
  export LR_MOVE_AUTH_RECHECK=off LR_MOVE_ROUTE_REUSE_S=0
  ranked_ago 5
  batch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(grep -c . "$RANK_LOG" || true)" -eq 1 ] || { cat "$RANK_LOG"; false; }
}
