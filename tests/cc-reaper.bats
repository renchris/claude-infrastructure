#!/usr/bin/env bats
# cc-reaper — RED-proof the disposition: a reap needs cause∈{handed-off-lead,finished-teammate} AND
# work-landed AND idle>=settle AND --reap; checkpoint runs BEFORE teardown; a post-classify dirty tree
# aborts the reap (WIP checkpointed); every never-reap cause is left untouched. Mocks classify/teardown/
# checkpoint; uses REAL temp git repos so the work-landed re-check is exercised for real.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  R="$REPO/bin/cc-reaper"
  D="$BATS_TEST_TMPDIR"; mkdir -p "$D/bin"
  # real git repos: clean+shipped (landed) and dirty (not landed)
  mkrepo() { local r="$1"; mkdir -p "$r"; git -C "$r" init -q; git -C "$r" config user.email t@t; git -C "$r" config user.name t
             echo a > "$r/f"; git -C "$r" add f; git -C "$r" commit -qm c1
             git -C "$r" update-ref refs/remotes/origin/main HEAD; }
  # squash-landed: clean tree, HEAD 1 ahead by COUNT, but content already on origin/main (different sha)
  mksquashland() { local r="$1"; mkdir -p "$r"; git -C "$r" init -q
             git -C "$r" config user.email t@t; git -C "$r" config user.name t
             echo base > "$r/f"; git -C "$r" add f; git -C "$r" commit -qm base
             echo feature >> "$r/f"; git -C "$r" add f; git -C "$r" commit -qm landed
             git -C "$r" update-ref refs/remotes/origin/main HEAD
             git -C "$r" reset -q --hard HEAD~1; echo feature >> "$r/f"; git -C "$r" add f
             GIT_AUTHOR_DATE="@1000000500" GIT_COMMITTER_DATE="@1000000500" git -C "$r" commit -qm featureX; }
  mkrepo "$D/clean"
  mkrepo "$D/dirty"; echo change >> "$D/dirty/f"      # dirty tree
  mksquashland "$D/squash"                             # clean + content-landed but count>0 ahead
  # mock teardown: record argv + ordering; rc from TEARDOWN_RC
  cat > "$D/bin/teardown" <<EOF
#!/bin/bash
echo "TD \$*" >> "$D/order"
printf '%s\n' "\$*" >> "$D/td-calls"
exit \${TEARDOWN_RC:-0}
EOF
  # mock checkpoint: record it ran (+ ordering)
  cat > "$D/bin/checkpoint" <<EOF
#!/bin/bash
cat >> "$D/ckpt-payloads"; echo "CKPT" >> "$D/order"
EOF
  chmod +x "$D/bin/teardown" "$D/bin/checkpoint"
  export CC_REAPER_TEARDOWN_BIN="$D/bin/teardown"
  export CC_REAPER_CHECKPOINT_BIN="$D/bin/checkpoint"
  export CC_REAPER_SETTLE_S=100
  export CC_REAPER_TRUNK=origin/main
  export CC_REAPER_LOG="$D/reaper.log"
  # ── hermetic paging (T-P3-3) + self-check (P0-12b): mock cc-notify + ps so no test can hit the LIVE
  #    desk or count REAL panes. Desk target is absent by default (→ no notify); surface/self-check tests
  #    opt in with set_desk. Live-pane count comes from $D/nlive (default 1 → matches the common 1-session
  #    case, so unrelated tests see Δ0 and never self-check-page). ──
  cat > "$D/bin/notify" <<EOF
#!/bin/bash
printf 'NOTIFY %s\n' "\$2" >> "$D/notify-calls"
EOF
  cat > "$D/bin/ps" <<EOF
#!/bin/bash
n=\$(cat "$D/nlive" 2>/dev/null || echo 1)
for ((k=0; k<n; k++)); do echo "claude --permission-mode auto --model claude-opus-4-8 --effort max"; done
EOF
  # mock cc-reconcile: records that (and how) it was invoked so no test hits the LIVE cc-registry, and
  # the reconcile wiring (runs on --reap, before classify) is assertable.
  cat > "$D/bin/reconcile" <<EOF
#!/bin/bash
printf 'RECON %s\n' "\$*" >> "$D/reconcile-calls"
echo "cc-reconcile: mock 0 backfilled"
EOF
  # mock cc-backlog: records that `reap` was invoked (the claim-ledger sweep wiring, --reap only) so no
  # test hits the LIVE backlog. Echoes a summary line like the real one so the reaper surfaces it.
  cat > "$D/bin/backlog" <<EOF
#!/bin/bash
printf 'BACKLOG %s\n' "\$*" >> "$D/backlog-calls"
echo "cc-backlog reap: 0 reopened, 0 blocked (0 non-terminal scanned)"
EOF
  chmod +x "$D/bin/notify" "$D/bin/ps" "$D/bin/reconcile" "$D/bin/backlog"
  export CC_REAPER_NOTIFY_BIN="$D/bin/notify"
  export CC_REAPER_PS_BIN="$D/bin/ps"
  export CC_REAPER_RECONCILE_BIN="$D/bin/reconcile"
  export CC_REAPER_BACKLOG_BIN="$D/bin/backlog"
  export CC_REAPER_PAGEDIR="$D/pages"
  export CC_REAPER_IDL="$D/idl.jsonl"
  export CC_PAGE_TO=""                        # neutralize any inherited real desk target
  export CC_PAGE_TO_FILE="$D/desk"            # absent by default → no notify; opt in via set_desk
  export CC_REAPER_SELFCHECK_MIN_PERSIST=1    # one sweep pages a real blind spot (hysteresis tests override)
}
notified()  { [ -s "$D/notify-calls" ]; }
reconciled() { [ -f "$D/reconcile-calls" ]; }
backlog_reaped() { grep -q '^BACKLOG reap' "$D/backlog-calls" 2>/dev/null; }
set_desk()  { echo "DESK-UUID" > "$D/desk"; }
set_live()  { echo "$1" > "$D/nlive"; }

# emit a mock cc-classify --all --json with ONE session; args: cause cwd idle landed [pane]
mock_classify() {
  local cause="$1" cwd="$2" idle="$3" landed="$4" pane="${5:-PANE-X}"
  cat > "$D/bin/classify" <<EOF
#!/bin/bash
jq -nc '[{name:"t",paneUUID:"$pane",account:"next",cwd:"$cwd",cause:"$cause",idle_s:$idle,work_landed:"$landed",successor:"PANE-SUCC",detail:"x"}]'
EOF
  chmod +x "$D/bin/classify"; export CC_REAPER_CLASSIFY_BIN="$D/bin/classify"
}
td_called() { [ -f "$D/td-calls" ]; }

@test "handed-off-lead + landed + idle>settle + --reap → teardown IS called with the pane" {
  mock_classify handed-off-lead "$D/clean" 999 yes PANE-A
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  td_called
  grep -q 'PANE-A' "$D/td-calls"
  grep -q -- '--done-evidence' "$D/td-calls"
}

@test "checkpoint runs BEFORE teardown (checkpoint-first)" {
  mock_classify handed-off-lead "$D/clean" 999 yes PANE-A
  run "$R" sweep --reap
  [ "$(head -1 "$D/order")" = CKPT ]
  grep -q '^TD ' "$D/order"
}

@test "DRY-RUN (no --reap) never calls teardown even for a valid candidate" {
  mock_classify handed-off-lead "$D/clean" 999 yes
  run "$R" sweep
  [ "$status" -eq 0 ]
  ! td_called
  echo "$output" | grep -q WOULD-REAP
}

@test "active is NEVER reaped" {
  mock_classify active "$D/clean" 999 yes
  run "$R" sweep --reap
  ! td_called
}

@test "owned-wait is NEVER reaped" {
  mock_classify owned-wait "$D/clean" 999 yes
  run "$R" sweep --reap
  ! td_called
}

@test "coordination-hang is NEVER reaped" {
  mock_classify coordination-hang "$D/clean" 999 yes
  run "$R" sweep --reap
  ! td_called
}

@test "rate-limited is NEVER reaped" {
  mock_classify rate-limited "$D/clean" 999 yes
  run "$R" sweep --reap
  ! td_called
}

@test "crashed is NEVER reaped (surfaced only)" {
  mock_classify crashed "$D/clean" 999 yes
  run "$R" sweep --reap
  ! td_called
}

@test "reapable cause but work NOT landed → DEFER, no teardown" {
  mock_classify handed-off-lead "$D/clean" 999 no
  run "$R" sweep --reap
  ! td_called
  echo "$output" | grep -q 'NOT landed'
}

@test "reapable + landed but idle < settle → not yet (self-close window), no teardown" {
  mock_classify handed-off-lead "$D/clean" 50 yes
  run "$R" sweep --reap
  ! td_called
  echo "$output" | grep -q 'settle'
}

@test "finished-teammate + landed + idle>settle → teardown called" {
  mock_classify finished-teammate "$D/clean" 999 yes PANE-T
  run "$R" sweep --reap
  td_called; grep -q PANE-T "$D/td-calls"
}

@test "finished + landed + idle>settle + --reap → teardown called (new reapable cause)" {
  mock_classify finished "$D/clean" 999 yes PANE-F
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  td_called; grep -q PANE-F "$D/td-calls"
}

@test "finished + work NOT landed → DEFER, no teardown (idle alone never reaps)" {
  mock_classify finished "$D/clean" 999 no
  run "$R" sweep --reap
  ! td_called
  echo "$output" | grep -q 'NOT landed'
}

@test "finished DRY-RUN surfaces WOULD-REAP, never tears down" {
  mock_classify finished "$D/clean" 999 yes PANE-F
  run "$R" sweep
  [ "$status" -eq 0 ]
  ! td_called
  echo "$output" | grep -q WOULD-REAP
}

@test "post-classify RACE: classify says landed but cwd is dirty at act-time → ABORT, WIP checkpointed, no teardown" {
  mock_classify handed-off-lead "$D/dirty" 999 yes
  run "$R" sweep --reap
  ! td_called                       # teardown NOT called
  [ -f "$D/ckpt-payloads" ]          # but checkpoint DID run first (WIP snapshotted)
  echo "$output" | grep -q ABORT
}

@test "cc-teardown DEFER (rc10) → reaper reports not-reaped, no crash" {
  mock_classify handed-off-lead "$D/clean" 999 yes PANE-A
  TEARDOWN_RC=10 run "$R" sweep --reap
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'NOT reaped'
}

@test "identity pin (a17 S-4): classify-time pid+lstart are forwarded to cc-teardown as --expect-*" {
  # cc-classify emits pid+lstart; cc-reaper must thread them to cc-teardown so a classify→act recycle
  # is caught. A mock classify supplies both; the teardown call must carry --expect-pid/--expect-lstart.
  cat > "$D/bin/classify" <<EOF
#!/bin/bash
jq -nc '[{name:"t",paneUUID:"PANE-A",account:"next",cwd:"$D/clean",cause:"finished",idle_s:999,work_landed:"yes",pid:4242,lstart:"Fri Jul 18 10:00:00 2026",successor:"PANE-SUCC",detail:"x"}]'
EOF
  chmod +x "$D/bin/classify"; export CC_REAPER_CLASSIFY_BIN="$D/bin/classify"
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  td_called
  grep -q -- '--expect-pid' "$D/td-calls"
  grep -q -- '4242' "$D/td-calls"
  grep -q -- '--expect-lstart' "$D/td-calls"
}

@test "identity pin: no pid/lstart from classify → no --expect-* args (back-compat, no crash)" {
  mock_classify finished "$D/clean" 999 yes PANE-A   # legacy classify JSON: no pid/lstart fields
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  td_called
  ! grep -q -- '--expect-pid' "$D/td-calls"
}

@test "landed-by-content (P0-17): cc-reaper's re-check reaps a squash-landed repo (content on trunk, count>0)" {
  # classify says finished+landed; the cwd is squash-landed (count>0). The COUNT-based re-check ABORTed
  # (permanent DEFER); the CONTENT-based re-check sees the work on trunk and reaps.
  mock_classify finished "$D/squash" 999 yes PANE-A
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  td_called
  grep -q PANE-A "$D/td-calls"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# T-P3-3 — surfaced-not-reaped causes get a DESK PAGE consumer (FM2 "surfaced ≠ acted" gap G-P3-3)
# ─────────────────────────────────────────────────────────────────────────────────────────────────

@test "T-P3-3: coordination-hang → desk PAGE (cc-notify) within one sweep, never reaped" {
  set_desk; set_live 1
  mock_classify coordination-hang "$D/clean" 9000 no PANE-H
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  notified                                         # a cc-notify reached the desk
  grep -q 'REAPER SURFACE' "$D/notify-calls"
  grep -q 'coordination-hang' "$D/notify-calls"
  ! td_called                                      # surfaced only — NEVER torn down
}

@test "T-P3-3: crashed and finished-shared-review each page the desk" {
  set_desk; set_live 1
  mock_classify crashed "$D/clean" 9000 no PANE-C
  run "$R" sweep --reap
  notified; grep -q 'crashed' "$D/notify-calls"
  : > "$D/notify-calls"; rm -rf "$D/pages"
  mock_classify finished-shared-review "$D/clean" 9000 no PANE-R
  run "$R" sweep --reap
  notified; grep -q 'finished-shared-review' "$D/notify-calls"
}

@test "T-P3-3 damping: the SAME surface cause pages ONCE across sweeps (no per-sweep composer storm)" {
  set_desk; set_live 1
  mock_classify coordination-hang "$D/clean" 9000 no PANE-H
  run "$R" sweep --reap; notified                  # first sweep pages
  : > "$D/notify-calls"
  run "$R" sweep --reap                             # identical second sweep
  [ "$status" -eq 0 ]
  ! notified                                        # damped — no second notify
  echo "$output" | grep -q 'damped'
}

@test "T-P3-3: a cause CHANGE on the same pane re-pages (coordination-hang → crashed)" {
  set_desk; set_live 1
  mock_classify coordination-hang "$D/clean" 9000 no PANE-H
  run "$R" sweep --reap
  : > "$D/notify-calls"
  mock_classify crashed "$D/clean" 9000 no PANE-H   # same pane, worsened cause
  run "$R" sweep --reap
  notified; grep -q 'crashed' "$D/notify-calls"
}

@test "T-P3-3: a non-surface never-reap cause (active/owned-wait/rate-limited) NEVER pages" {
  set_desk; set_live 1
  for c in active owned-wait rate-limited; do
    : > "$D/notify-calls"
    mock_classify "$c" "$D/clean" 9000 no PANE-X
    run "$R" sweep --reap
    [ "$status" -eq 0 ]
    ! notified
  done
}

@test "T-P3-3 dry-run: a surface cause prints WOULD-PAGE and NEVER notifies" {
  set_desk; set_live 1
  mock_classify coordination-hang "$D/clean" 9000 no PANE-H
  run "$R" sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'WOULD-PAGE'
  ! notified
}

@test "T-P3-3 re-arm: a pane leaving the surface set drops its damping marker (recovery re-pages later)" {
  set_desk; set_live 1
  mock_classify coordination-hang "$D/clean" 9000 no PANE-H
  run "$R" sweep --reap
  [ -f "$D/pages/PANE-H.cause" ]                    # marker written on first page
  mock_classify active "$D/clean" 10 no PANE-H      # recovered → no longer surfaced
  run "$R" sweep --reap
  [ ! -f "$D/pages/PANE-H.cause" ]                  # marker pruned → re-armed
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# P0-12b — enumerated≈live-panes self-check: surface the delta when the reaper is blind to live panes
# ─────────────────────────────────────────────────────────────────────────────────────────────────

@test "P0-12b: live panes > enumerated → desk PAGE (blind-spot surface), never a reap" {
  set_desk; set_live 4                              # 4 live interactive panes
  mock_classify active "$D/clean" 10 no PANE-1      # but only 1 enumerated
  run "$R" sweep --reap                             # MIN_PERSIST=1 → pages on the first sweep
  [ "$status" -eq 0 ]
  notified
  grep -q 'SELF-CHECK' "$D/notify-calls"
  grep -q 'BLIND to 3' "$D/notify-calls"
  ! td_called
}

@test "P0-12b: live == enumerated → no page (the reaper sees every live pane)" {
  set_desk; set_live 1
  mock_classify active "$D/clean" 10 no PANE-1
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  ! notified
  echo "$output" | grep -q 'reaper sees all live panes'
}

@test "P0-12b hysteresis: a blind-spot delta must PERSIST before it pages (kills a start/exit race)" {
  set_desk; set_live 3
  export CC_REAPER_SELFCHECK_MIN_PERSIST=2
  mock_classify active "$D/clean" 10 no PANE-1
  run "$R" sweep --reap                             # sweep 1 → persist 1/2, observe only
  ! notified
  echo "$output" | grep -q 'persist 1/2'
  run "$R" sweep --reap                             # sweep 2 → persist 2/2, page
  notified; grep -q 'SELF-CHECK' "$D/notify-calls"
}

@test "P0-12b dry-run: a blind spot prints WOULD-PAGE and NEVER notifies" {
  set_desk; set_live 4
  mock_classify active "$D/clean" 10 no PANE-1
  run "$R" sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'self-check: WOULD-PAGE'
  ! notified
}

@test "reconcile runs on --reap (heals the registry before the self-check surfaces a delta)" {
  mock_classify active "$D/clean" 10 no PANE-1
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  reconciled                                        # cc-reconcile was invoked
  echo "$output" | grep -q 'cc-reconcile: mock'     # its summary is surfaced on stdout
}

@test "cc-backlog reap runs on --reap (heals the CLAIM ledger, its summary surfaced)" {
  mock_classify active "$D/clean" 10 no PANE-1
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  backlog_reaped                                    # cc-backlog reap was invoked
  echo "$output" | grep -q 'cc-backlog reap:'       # its summary is surfaced on stdout
}

@test "cc-backlog reap does NOT run on a DRY-RUN sweep (dry-run writes nothing)" {
  mock_classify active "$D/clean" 10 no PANE-1
  run "$R" sweep
  [ "$status" -eq 0 ]
  ! backlog_reaped                                  # no claim-ledger mutation on a dry-run
}

@test "reconcile does NOT run on a DRY-RUN sweep (dry-run writes nothing)" {
  mock_classify active "$D/clean" 10 no PANE-1
  run "$R" sweep
  [ "$status" -eq 0 ]
  ! reconciled
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# log() timestamps — TRUE UTC, never local-time mislabeled with a Z (cc-backlog 6d898339d690)
# ─────────────────────────────────────────────────────────────────────────────────────────────────

@test "log() stamps true UTC, not local time mislabeled Z (cc-backlog 6d898339d690)" {
  # Regression: log() used a bare \`date\` (LOCAL time) under a literal Z (UTC marker), so
  # cc-reaper.log read TZ-offset hours stale to any freshness check → a false 'reaper DORMANT /
  # no sweep since HH:MMZ' page while the reaper was in fact sweeping every ~5 min. Force a fixed
  # non-UTC zone; the emitted [..Z] stamp, parsed AS UTC, must land inside the sweep's real UTC
  # window — a local-as-Z value is a full 5h out and fails.
  export TZ='Etc/GMT-5'                              # UTC+5, DST-free (POSIX offset sign is inverted)
  mock_classify active "$D/clean" 999 yes
  local before after ts epoch
  before=$(date -u +%s)
  run "$R" sweep --reap
  after=$(date -u +%s)
  [ "$status" -eq 0 ]
  ts=$(grep 'sweep start' "$D/reaper.log" | tail -1 | sed -E 's/^\[([0-9T:-]+)Z\].*/\1/')
  [ -n "$ts" ]
  epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$ts" +%s)   # -u: interpret the stamp AS UTC (TZ-independent)
  [ -n "$epoch" ]
  [ "$epoch" -ge "$((before - 120))" ]               # the 5h (18000s) mislabel dwarfs the ±120s slack
  [ "$epoch" -le "$((after + 120))" ]
}
