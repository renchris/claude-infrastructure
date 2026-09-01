#!/usr/bin/env bats
# drain-conversion-churn.bats — the claims→dones conversion metric and the churn alarm that reads it.
#
# SUBJECTS: scripts/backlog-telemetry.sh (`verdict=drain-futile`), bin/cc-value (`churn_reasons`),
# and scripts/rotate-autonomy-logs.sh (the hourly host that actually invokes the assert).
#
# WHAT THIS SUITE EXISTS TO PREVENT, and it is not "the alarm is broken". For a week the pipeline
# burned cloud sessions at zero drain and `cc-value` rendered `churn=false` the whole time, because
# its predicate required fleet value to be exactly 0 while the local lane landed 42-86 commits a
# day. The alarm was not wrong, it was UNREACHABLE. So the load-bearing test here is not the one
# where the alarm fires — it is C1, where a HEALTHY window must leave it SILENT. A suite that only
# tests the firing case cannot tell a working alarm from one that is stuck on, which is the same
# defect mirrored (memory alarm-polarity-and-attention-budget).
#
# C1 IS THE CONTROL THAT CAN FAIL, and it is proved to be able to fail rather than asserted: C1-M
# runs the identical fixture through the identical subject with ONE input changed — the dones
# removed — and requires the verdict to flip. A control whose two arms are green either way asserts
# nothing at all.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  D="$BATS_TEST_TMPDIR"
  # Hermetic HOME: both subjects fall back to $HOME for the live store, and a test that let that
  # resolve to the operator's real one would read — or, through the rotation host, WRITE — prod.
  export HOME="$D/home"
  mkdir -p "$HOME/.claude/autonomy"
  TELEM="$REPO/scripts/backlog-telemetry.sh"
  VALUE="$REPO/bin/cc-value"
  ROTATE="$REPO/scripts/rotate-autonomy-logs.sh"
  export CC_BACKLOG_FILE="$D/backlog.jsonl"
  # Seams that do NOT resolve under $HOME and so survive a fixtured HOME untouched: cc-value's
  # telemetry dir defaults to an absolute /tmp/cc-telemetry, and its ledger cache to $TMPDIR. Left
  # unpinned, this suite would read the operator's live sessions — and value_env() below overrides
  # the first only inside the tests that call it, which is precisely the partial fixturing the
  # hermeticity ratchet exists to refuse. The default here points at a path that does not exist:
  # these sensors fail OPEN on an absent dir, which is the correct baseline for a test that has
  # not declared its own.
  export CC_TELEMETRY_DIR="$D/telemetry-absent"
  export CC_VALUE_CACHE="$D/cc-value-cache.json"
}

# Timestamps are generated relative to NOW, never hardcoded: every lane verdict in the subject is an
# age against `date -u`, so a fixture with literal dates goes red by CALENDAR the day after it is
# written (memory fixture-literal-date-expires-against-a-ttl). BSD `date -v` first, GNU `-d` second.
ago() { # <hours> → ISO-8601Z
  date -u -v-"$1"H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "$1 hours ago" +%Y-%m-%dT%H:%M:%SZ
}

# Every roster lane closes something recent, so the PRE-EXISTING lane-silence/stall arms are quiet
# and this suite's assertions are about conversion alone. Without this the healthy control reds for
# a reason that has nothing to do with what it controls.
lanes_all_fresh() {
  printf '{"id":"lane-c","ts":"%s","event":"add"}\n'                       "$(ago 5)"
  printf '{"id":"lane-c","ts":"%s","event":"done","lane":"cloud"}\n'       "$(ago 4)"
  printf '{"id":"lane-l","ts":"%s","event":"add"}\n'                       "$(ago 5)"
  printf '{"id":"lane-l","ts":"%s","event":"done","lane":"local-drain"}\n' "$(ago 4)"
  printf '{"id":"lane-s","ts":"%s","event":"add"}\n'                       "$(ago 5)"
  printf '{"id":"lane-s","ts":"%s","event":"done","lane":"session"}\n'     "$(ago 4)"
}

# THE FUTILE SHAPE — this week's, measured: 12 distinct ids re-claimed 5x each, ZERO conversions.
seed_futile() {
  { lanes_all_fresh
    local i j
    for i in $(seq -f '%02g' 1 12); do
      printf '{"id":"futile-%s","ts":"%s","event":"add"}\n' "$i" "$(ago 6)"
      # Re-claims spread over distinct hours — the live shape, where one item is picked up again
      # and again rather than five times in one instant.
      for j in 1 2 3 4 5; do
        printf '{"id":"futile-%s","ts":"%s","event":"claim"}\n' "$i" "$(ago "$j")"
      done
    done
  } > "$CC_BACKLOG_FILE"
}

# THE HEALTHY SHAPE — the same 12 ids, claimed ONCE each, 9 of them reaching done.
seed_healthy() {
  { lanes_all_fresh
    local i
    for i in $(seq -f '%02g' 1 12); do
      printf '{"id":"conv-%s","ts":"%s","event":"add"}\n'   "$i" "$(ago 6)"
      printf '{"id":"conv-%s","ts":"%s","event":"claim"}\n' "$i" "$(ago 3)"
    done
    for i in $(seq -f '%02g' 1 9); do
      printf '{"id":"conv-%s","ts":"%s","event":"done","lane":"local-drain"}\n' "$i" "$(ago 2)"
    done
  } > "$CC_BACKLOG_FILE"
}

# SUBSTRING assertions as SIMPLE COMMANDS, never `[[ ]]`. bash exempts `[[ ]]` from errexit in
# every position but last, so a `[[ ]]` mid-test is evaluated and then silently discarded — this
# suite had 19 such dead assertions before scripts/bats-assert-liveness.py named them, including
# one asserting a value that was factually wrong (`converted=1` against a fixture with 0). A
# function call is an ordinary command and errexit honours it wherever it sits.
has()   { case "$2" in *"$1"*) return 0 ;; esac; return 1; }
hasnt() { case "$2" in *"$1"*) return 1 ;; esac; return 0; }

# ── A. the mode fix ──────────────────────────────────────────────────────────────────────────────

@test "A1 scripts/backlog-telemetry.sh is EXECUTABLE" {
  # It shipped 644, so `"$script"` failed for every caller and only `bash script` worked — which is
  # why the one scheduled invocation added in this change resolves it as a FILE and runs it under
  # bash. The bit is still the contract: install.sh symlinks scripts/*.sh, so the live layer's mode
  # is this file's mode, and nothing else re-asserts it.
  [ -x "$TELEM" ]
}

# ── B. the conversion metric ─────────────────────────────────────────────────────────────────────

@test "B1 the daily series and the rolling line BOTH carry raw claims AND distinct ids" {
  seed_futile
  run bash "$TELEM" --days 3
  [ "$status" -eq 0 ]
  # Header columns exist on the series...
  printf '%s\n' "$output" | grep -q 'claims' || false
  printf '%s\n' "$output" | grep -q 'cids' || false
  # ...and the rolling line carries both counts, DIFFERENT from each other. 60 claim events over 12
  # ids is the whole signal: either number alone reads as ordinary work.
  run bash -c "bash '$TELEM' --days 3 | grep '^CONVERSION 7D'"
  [ "$status" -eq 0 ]
  has "claims=60" "$output"
  has "over 12 distinct id(s)" "$output"
  has "reclaim=5x" "$output"
}

@test "B2 the FUTILE shape fires drain-futile and --assert exits 1" {
  seed_futile
  run bash -c "bash '$TELEM' --days 1 | grep 'scope=fleet'"
  [ "$status" -eq 0 ]
  has "verdict=drain-futile" "$output"
  has "ids=12 converted=0" "$output"

  run bash "$TELEM" --days 1 --assert
  [ "$status" -eq 1 ]
}

@test "C1 CONTROL — the HEALTHY shape leaves the alarm SILENT and --assert exits 0" {
  seed_healthy
  run bash -c "bash '$TELEM' --days 1 | grep 'scope=fleet'"
  [ "$status" -eq 0 ]
  has "verdict=drain-converting" "$output"
  hasnt "drain-futile" "$output"

  run bash "$TELEM" --days 1 --assert
  [ "$status" -eq 0 ]
}

@test "C1-M the control CAN fail: strip the dones from the healthy fixture and it flips to futile" {
  # The mutation is ONE input — the conversions — on the byte-identical fixture C1 just passed.
  # Without this, C1's green is compatible with an alarm that is simply never on.
  seed_healthy
  grep -v '"id":"conv-' "$CC_BACKLOG_FILE" > "$D/mutant.pre" || true
  grep '"id":"conv-' "$CC_BACKLOG_FILE" | grep -v '"event":"done"' >> "$D/mutant.pre"
  mv "$D/mutant.pre" "$CC_BACKLOG_FILE"

  run bash -c "bash '$TELEM' --days 1 | grep 'scope=fleet'"
  [ "$status" -eq 0 ]
  has "verdict=drain-futile" "$output"
  run bash "$TELEM" --days 1 --assert
  [ "$status" -eq 1 ]
}

@test "C2 below the sample floor the verdict ABSTAINS (drain-unmeasured), it does not fire" {
  # Two claimed ids is noise. An alarm that convicts on it would fire from the day it shipped and
  # be read past by the time it meant something — the polarity rule this file's subject documents.
  { lanes_all_fresh
    printf '{"id":"tiny-1","ts":"%s","event":"claim"}\n' "$(ago 3)"
    printf '{"id":"tiny-2","ts":"%s","event":"claim"}\n' "$(ago 3)"
  } > "$CC_BACKLOG_FILE"

  run bash -c "bash '$TELEM' --days 1 | grep 'scope=fleet'"
  [ "$status" -eq 0 ]
  has "verdict=drain-unmeasured" "$output"
  hasnt "drain-futile" "$output"
  run bash "$TELEM" --days 1 --assert
  [ "$status" -eq 0 ]
}

# ── D. cc-value's churn arms ─────────────────────────────────────────────────────────────────────

# cc-value needs a repo to count commits in, an active telemetry row, and an account spending at or
# above the churn floor — otherwise every arm is correctly gated off and the test proves nothing.
value_env() {
  R="$D/repo"
  if [ ! -d "$R" ]; then
    git init -q "$R"
    git -C "$R" config user.email t@t; git -C "$R" config user.name t
    git -C "$R" commit -q --allow-empty -m "landed value"
    git -C "$R" update-ref refs/remotes/origin/main "$(git -C "$R" rev-parse HEAD)"
    mkdir -p "$D/tel"
    printf '{"session_id":"uuid-A","config_dir":"/x/.claude-next","cwd":"%s","used_pct":30,"pid":%d,"ts":%d}\n' \
      "$R" "$$" "$(date -u +%s)" > "$D/tel/uuid-A.json"
  fi
  export CC_VALUE_REPOS="$R" CC_TELEMETRY_DIR="$D/tel" \
         CC_ACCTS_JSON='{"rows":[{"acct":"next","session_pct":20,"weekly_pct":30}]}'
}

@test "D1 the FUTILE store makes cc-value report churn TRUE, naming the arm" {
  seed_futile; value_env
  run bash -c "'$VALUE' --json | jq -c '.fleet | {churn, churn_reasons, value}'"
  [ "$status" -eq 0 ]
  has '"churn":true' "$output"
  has 'no-conversion' "$output"
  # The commit count is UNTOUCHED — the whole point of an additive fix. `value` still reads >0 and
  # the alarm fires anyway, which the replaced predicate could not do.
  run bash -c "'$VALUE' --json | jq '.fleet.value > 0'"
  [ "$output" = "true" ]
}

@test "D2 CONTROL — the HEALTHY store leaves cc-value's churn FALSE with no arm fired" {
  seed_healthy; value_env
  run bash -c "'$VALUE' --json | jq -c '[.fleet.churn, (.fleet.churn_reasons|length)]'"
  [ "$status" -eq 0 ]
  [ "$output" = '[false,0]' ]
}

@test "D3 the per-lane split reads the done record's lane, not the fleet sum" {
  # Summing is exactly what let the local lane's commit volume mask the cloud lane's zero. Here the
  # cloud lane closes nothing while local-drain does, and the ledger must say so per lane.
  { lanes_all_fresh
    printf '{"id":"x1","ts":"%s","event":"done","lane":"local-drain"}\n' "$(ago 1)"
  } > "$CC_BACKLOG_FILE"
  # Drop the cloud close so exactly one roster lane is silent. Two statements, not an `&&` list:
  # a non-last `&&` operand is exempt from errexit, so a failed grep here would be discarded and
  # the fixture would silently keep its cloud close.
  grep -v '"lane":"cloud"' "$CC_BACKLOG_FILE" > "$D/nc"
  mv "$D/nc" "$CC_BACKLOG_FILE"
  value_env
  run bash -c "'$VALUE' --json | jq -c '.fleet.lanes'"
  [ "$status" -eq 0 ]
  has '{"lane":"cloud","closes":0}' "$output"
  has '"lane":"local-drain","closes":2' "$output"
  run bash -c "'$VALUE' --json | jq -c '.fleet.churn_reasons'"
  has 'lane-silent:cloud' "$output"
  hasnt 'lane-silent:local-drain' "$output"
}

@test "D4 UNKNOWN ≠ 0 — an unreachable store abstains, it is never read as an empty window" {
  # A fail-safe default that mimics the healthy state is unfalsifiable, and the mirror defect is a
  # fail-safe default that mimics the BROKEN one: a missing store must not manufacture "0 claims,
  # 0 conversions, all lanes silent" and convict on it. Both halves are asserted.
  seed_healthy; value_env
  export CC_BACKLOG_FILE="$D/does-not-exist.jsonl"
  run bash -c "'$VALUE' --json | jq -c '[.fleet.backlog_readable, .fleet.conversion, ([.fleet.lanes[].closes]|unique)]'"
  [ "$status" -eq 0 ]
  [ "$output" = '[false,null,[null]]' ]
  run bash -c "'$VALUE' --json | jq -c '[.fleet.churn_reasons[]|select(.==\"no-conversion\" or startswith(\"lane-silent:\"))]'"
  [ "$output" = '[]' ]
}

@test "D5 cc-value's own selftest still passes end to end" {
  run bash "$VALUE" selftest
  [ "$status" -eq 0 ]
  has "0 failed" "$output"
}

# ── E. the wiring — the host that actually invokes the assert ────────────────────────────────────

@test "E1 the hourly rotation host RUNS the assert and journals its verdict" {
  # DoD: prove the scheduled host invokes it, by the row appearing after a run — not by reading the
  # code that would call it. This drives the real host script against a hermetic HOME/IDL.
  seed_futile
  export CC_IDL="$HOME/.claude/autonomy/idl.jsonl"
  export ROTATE_TARGETS="$CC_IDL"
  export DRAIN_TELEMETRY_BIN="$TELEM"
  : > "$CC_IDL"

  run bash "$ROTATE"
  [ "$status" -eq 0 ]
  has "drain=emitted" "$output"

  run grep -c '"tool":"drain-health"' "$CC_IDL"
  [ "$output" = "1" ]
  run bash -c "grep '\"tool\":\"drain-health\"' '$CC_IDL' | jq -c '[.assert, .verdict, .claim_ids, .converted]'"
  [ "$output" = '["red","drain-futile",12,0]' ]
}

@test "E2 the arm is DEBOUNCED — an unchanged verdict does not re-journal, and says so" {
  seed_futile
  export CC_IDL="$HOME/.claude/autonomy/idl.jsonl"
  export ROTATE_TARGETS="$CC_IDL"
  export DRAIN_TELEMETRY_BIN="$TELEM"
  : > "$CC_IDL"

  bash "$ROTATE" >/dev/null
  run bash "$ROTATE"
  [ "$status" -eq 0 ]
  has "drain=debounced" "$output"
  # Exactly one drain-health row for two ticks — but BOTH ticks recorded what the arm did, so "ran
  # and had nothing new to say" stays distinguishable from "never ran".
  run grep -c '"tool":"drain-health"' "$CC_IDL"
  [ "$output" = "1" ]
  run grep -c '"drain":"debounced"' "$CC_IDL"
  [ "$output" = "1" ]
}

@test "E3 a verdict CHANGE re-journals inside the same day" {
  seed_futile
  export CC_IDL="$HOME/.claude/autonomy/idl.jsonl"
  export ROTATE_TARGETS="$CC_IDL"
  export DRAIN_TELEMETRY_BIN="$TELEM"
  : > "$CC_IDL"

  bash "$ROTATE" >/dev/null          # red / drain-futile
  seed_healthy
  run bash "$ROTATE"
  has "drain=emitted" "$output"
  run grep -c '"tool":"drain-health"' "$CC_IDL"
  [ "$output" = "2" ]
  run bash -c "grep '\"tool\":\"drain-health\"' '$CC_IDL' | tail -1 | jq -r .verdict"
  [ "$output" = "drain-converting" ]
}

@test "E4 an ABSENT telemetry producer is a NAMED skip, never a silent pass" {
  seed_futile
  export CC_IDL="$HOME/.claude/autonomy/idl.jsonl"
  export ROTATE_TARGETS="$CC_IDL"
  export DRAIN_TELEMETRY_BIN="$D/no-such-telemetry.sh"
  : > "$CC_IDL"

  run bash "$ROTATE"
  [ "$status" -eq 0 ]
  has "drain=telemetry-absent" "$output"
  run grep -c '"tool":"drain-health"' "$CC_IDL"
  [ "$output" = "0" ]
}

@test "E4b a STALE producer is reported as such, not as a clean read" {
  # Measured on the first real run: the live layer was 17 commits behind trunk, so the arm resolved
  # a PRE-LAND backlog-telemetry.sh that emits no fleet-scope line. The rc is still the assert's own
  # verdict and is journaled, but `drain:"emitted"` beside `verdict:"unparsed"` would read as a
  # working arm in the one field every tick writes. A stub standing in for the stale producer.
  seed_futile
  export CC_IDL="$HOME/.claude/autonomy/idl.jsonl"
  export ROTATE_TARGETS="$CC_IDL"
  printf '#!/bin/bash\necho "old renderer with no fleet line"\nexit 1\n' > "$D/stale-telemetry.sh"
  export DRAIN_TELEMETRY_BIN="$D/stale-telemetry.sh"
  : > "$CC_IDL"

  run bash "$ROTATE"
  [ "$status" -eq 0 ]
  has "drain=emitted-unparsed" "$output"
  run bash -c "grep '\"tool\":\"drain-health\"' '$CC_IDL' | jq -c '[.verdict, .claims, .rc]'"
  [ "$output" = '["unparsed",null,1]' ]
}

@test "E5 NO new launchd activation was added by this change" {
  # The binding design constraint: the activation queue is 11 deep with all 11 rotting past 24h, so
  # a fix shipped as a 12th activation rots exactly like them. The assert rides com.claude.log-
  # rotation, which is already loaded and already hourly.
  run bash -c "git -C '$REPO' status --porcelain launchd/ | grep -c '^??' || true"
  [ "$output" = "0" ]
  # and the host it rides really is the one that runs rotate-autonomy-logs.sh
  run grep -c 'rotate-autonomy-logs.sh' "$REPO/launchd/com.claude.log-rotation.plist"
  [ "$output" = "1" ]
}
