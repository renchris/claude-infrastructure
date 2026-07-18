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
}

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
