#!/usr/bin/env bats
# ctx-audit.bats — row 8 (CONTEXT_ECONOMY_V2.md §7). Proves the context-economy OUTCOME READER
# measures what it claims: wall hits by exact match (never substring), compactions by the LITERAL
# trigger (never inferred), and a fill p95 that EXCLUDES rather than imputes a missing denominator.
#
# PROOF DISCIPLINE (non-negotiable, from the campaign's catches):
#   · Every absence assertion has a POSITIVE CONTROL beside it.
#   · Non-final `[[ ]]` / `(( ))` are errexit-EXEMPT and therefore DEAD as assertions — every one
#     carries `|| false` (memory bats-dead-assertions-errexit-exemptions).
#   · Fully hermetic: every store the reader touches is behind an env seam and fixtured here, so a
#     run can neither read the operator's live telemetry nor be decided by ambient state.
#
# RED-PROOF — TWO KINDS, and the second is the one that matters:
#   (a) FILE-ABSENCE RED (weak, named as such): the pristine pre-change tree recovered via
#       `git archive` has no bin/cc-ctx-audit, so every test fails at file-not-found. That proves
#       the tests exercise a new artifact; it proves NOTHING about their logic.
#   (b) MUTATION RED (strong): the discriminating tests are re-run against a COPY of the reader
#       with one specific behaviour inverted — exact-match downgraded to a substring match, and
#       the null-denominator guard replaced by a 1,000,000 default (the exact error this row
#       committed and withdrew in Phase 1). Each mutation must flip its test to RED. A test that
#       stays green under its own mutation is pinning nothing. See the `mutation:` tests below.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  AUDIT="$REPO/bin/cc-ctx-audit"
  TMP="$BATS_TEST_TMPDIR"

  # ── HERMETICITY ──────────────────────────────────────────────────────────────────────────────
  # The reader defaults its denominator sources to /tmp/cc-telemetry and
  # $HOME/.claude/autonomy/recycle-events.jsonl. Unfixtured, this suite's verdict would be decided
  # by whatever live sessions happen to be running on the box — the borrowed-hermeticity defect
  # (memory bats-runtime-cap-placement-and-borrowed-hermeticity). Fixture HOME *and* both seams.
  export HOME="$TMP/home"
  mkdir -p "$HOME/.claude/autonomy"
  export CC_CTX_ROOTS="$TMP/projects"
  export CC_CTX_TELEMETRY_DIR="$TMP/telemetry"
  export CC_CTX_EVENTS="$HOME/.claude/autonomy/recycle-events.jsonl"
  mkdir -p "$TMP/projects/proj" "$TMP/telemetry"

  # ── FIXTURES: shaped from the REAL producers' literal emission (memory
  #    fixture-shape-parity-with-real-producer — a fixture is a contract CLAIM, so it must match
  #    what the harness actually writes, verified against live transcripts this session).
  #
  # S1: hits the wall. Bare assistant text exactly equal to the API refusal.
  cat > "$TMP/projects/proj/s1.jsonl" <<'EOF'
{"type":"assistant","sessionId":"s1","timestamp":"2026-07-20T10:00:00.000Z","cwd":"/w/a","message":{"model":"claude-opus-4-8","usage":{"input_tokens":100,"cache_read_input_tokens":149900,"cache_creation_input_tokens":0}}}
{"type":"assistant","sessionId":"s1","timestamp":"2026-07-20T10:01:00.000Z","cwd":"/w/a","message":{"content":"Prompt is too long"}}
EOF
  # S2: TALKS ABOUT the refusal but never hit it — the substring trap. A loose grep counts this.
  cat > "$TMP/projects/proj/s2.jsonl" <<'EOF'
{"type":"assistant","sessionId":"s2","timestamp":"2026-07-20T11:00:00.000Z","cwd":"/w/b","message":{"content":"The failure mode is that the API returns Prompt is too long and the session dies."}}
{"type":"assistant","sessionId":"s2","timestamp":"2026-07-20T11:01:00.000Z","cwd":"/w/b","message":{"model":"claude-opus-4-8","usage":{"input_tokens":50,"cache_read_input_tokens":50,"cache_creation_input_tokens":0}}}
EOF
  # S3: one MANUAL compaction, and a peak that needs the cache terms summed to be seen at all.
  cat > "$TMP/projects/proj/s3.jsonl" <<'EOF'
{"type":"system","subtype":"compact_boundary","sessionId":"s3","timestamp":"2026-07-20T12:00:00.000Z","compactMetadata":{"trigger":"manual","preTokens":430436,"postTokens":14148}}
{"type":"assistant","sessionId":"s3","timestamp":"2026-07-20T12:01:00.000Z","cwd":"/w/c","message":{"model":"claude-opus-4-8","usage":{"input_tokens":1000,"cache_read_input_tokens":179000,"cache_creation_input_tokens":0}}}
EOF
  # S4: an AUTO compaction — the value with ZERO instances in the real fleet. Present here so the
  # reader is proven able to SEE it the day it first happens (R1: existence evidence, positive
  # control for the "0 auto" claim rather than a claim that rests on never having looked).
  cat > "$TMP/projects/proj/s4.jsonl" <<'EOF'
{"type":"system","subtype":"compact_boundary","sessionId":"s4","timestamp":"2026-07-20T13:00:00.000Z","compactMetadata":{"trigger":"auto","preTokens":900000,"postTokens":20000}}
EOF
  # Denominators: s1 has a 200K window; s3 has 1M. s2/s4 have NONE — they must be EXCLUDED.
  # Note s1 and s3 deliberately share the same numerator scale so that imputing 1M for s1 would
  # visibly change the p95 — that is what the mutation test detects.
  cat > "$TMP/telemetry/s1.json" <<'EOF'
{"ts":1785000000,"session_id":"s1","window":200000,"used_pct":75,"input_tokens":150000}
EOF
  cat > "$TMP/telemetry/s3.json" <<'EOF'
{"ts":1785000001,"session_id":"s3","window":1000000,"used_pct":18,"input_tokens":180000}
EOF
}

# ── the reader exists and is executable under the REAL interpreter ────────────────────────────
@test "reader is executable and parses under /bin/bash (not the zsh the Bash tool runs)" {
  [ -x "$AUDIT" ] || false
  run /bin/bash -n "$AUDIT"
  [ "$status" -eq 0 ] || false
}

@test "kill switch CC_CTX_AUDIT=off exits 0 and emits nothing" {
  CC_CTX_AUDIT=off run /bin/bash "$AUDIT" --summary
  [ "$status" -eq 0 ] || false
  [ -z "$output" ] || false
}

@test "usage error exits 2, not 0 and not 3" {
  run /bin/bash "$AUDIT" --no-such-flag
  [ "$status" -eq 2 ] || false
}

@test "no mode given exits 2" {
  run /bin/bash "$AUDIT"
  [ "$status" -eq 2 ] || false
}

# ── wall hits: exact match, and the substring trap ────────────────────────────────────────────
@test "wall-hits counts the session that HIT the wall (positive control)" {
  run /bin/bash "$AUDIT" --wall-hits --since all
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"1 event(s) in 1 session(s)"* ]] || false
  [[ "$output" == *"s1"* ]] || false
}

@test "wall-hits EXCLUDES a session that only TALKS about the refusal (the substring trap)" {
  run /bin/bash "$AUDIT" --wall-hits --since all
  [ "$status" -eq 0 ] || false
  # s2 contains the phrase but never hit it. A substring detector would report 2 sessions.
  [[ "$output" != *"s2"* ]] || false
  [[ "$output" != *"2 session(s)"* ]] || false
}

@test "mutation: downgrading exact-match to a substring match turns the trap test RED" {
  # THE STRONG RED-PROOF. Invert exactly one behaviour and require the suite to notice.
  cp "$AUDIT" "$TMP/mutant"
  # exact equality  →  substring containment
  sed -i.bak 's/== "prompt is too long"/| test("prompt is too long")/' "$TMP/mutant"
  # assert the patch APPLIED — an unapplied sed silently leaves the ORIGINAL program under test,
  # and the test then passes while proving nothing (memory source-patching-test-makes-the-line-an-api)
  run grep -c 'test("prompt is too long")' "$TMP/mutant"
  [ "$status" -eq 0 ] || false
  [ "$output" -ge 1 ] || false
  chmod +x "$TMP/mutant"
  run /bin/bash "$TMP/mutant" --wall-hits --since all
  [ "$status" -eq 0 ] || false
  # the mutant MUST now miscount s2 as a wall hit — that is the RED this test pins
  [[ "$output" == *"2 session(s)"* ]] || false
}

# ── compactions: literal trigger, never inferred ──────────────────────────────────────────────
@test "compactions are classified by the LITERAL trigger, auto and manual kept distinct" {
  run /bin/bash "$AUDIT" --compactions --since all
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"2 event(s)"* ]] || false
  [[ "$output" == *"manual"* ]] || false
  # POSITIVE CONTROL for the real fleet's "0 auto" finding: the reader CAN see an auto trigger,
  # so the fleet-wide zero is a measurement and not a blind spot.
  [[ "$output" == *"auto"* ]] || false
}

@test "a compaction with no recorded trigger is reported as unrecorded, never folded into manual" {
  cat > "$TMP/projects/proj/s5.jsonl" <<'EOF'
{"type":"system","subtype":"compact_boundary","sessionId":"s5","timestamp":"2026-07-20T14:00:00.000Z","compactMetadata":{"preTokens":1,"postTokens":1}}
EOF
  run /bin/bash "$AUDIT" --compactions --since all
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"unrecorded"* ]] || false
}

# ── the denominator: excluded, NEVER imputed ──────────────────────────────────────────────────
@test "p95 counts only sessions WITH a recoverable denominator and reports the exclusions" {
  run /bin/bash "$AUDIT" --p95-recycle-fill --since all
  [ "$status" -eq 0 ] || false
  # s1 (150000/200000 = 75%) and s3 (180000/1000000 = 18%) have windows; s2/s4 do not.
  [[ "$output" == *"n=2"* ]] || false
  [[ "$output" == *"EXCLUDED"* ]] || false
}

@test "p95 arithmetic is right: s1=75% of a 200K window, not 15% of an imputed 1M" {
  run /bin/bash "$AUDIT" --sessions --since all
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"200000"* ]] || false
  [[ "$output" == *"75.0"* ]] || false
  # 150000/1000000 = 15.0 — the withdrawn Phase-1 error. It must NOT appear.
  [[ "$output" != *" 15.0"* ]] || false
}

@test "peak sums the cache terms — input_tokens alone understates a warm context" {
  # s1's peak is 100 + 149900 = 150000. Reading .input_tokens alone would give 100 (0.05%).
  run /bin/bash "$AUDIT" --sessions --since all
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"150000"* ]] || false
}

@test "NO denominator anywhere ⇒ exit 3 (a NON-VERDICT), never exit 0 with a number" {
  rm -f "$TMP/telemetry"/*.json
  : > "$CC_CTX_EVENTS"
  run /bin/bash "$AUDIT" --p95-recycle-fill --since all
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"NO DENOMINATOR"* ]] || false
  [[ "$output" == *"non-verdict"* || "$output" == *"NON-VERDICT"* ]] || false
}

@test "mutation: defaulting a missing denominator to 1,000,000 turns the exclusion test RED" {
  # The withdrawn Phase-1 error, reproduced deliberately: impute 1M when the window is unknown.
  cp "$AUDIT" "$TMP/mutant2"
  sed -i.bak 's|grep -q "\^\$sid " "\$TMP/denom" 2>/dev/null \|\| continue|win_default=1000000|' "$TMP/mutant2"
  sed -i.bak2 's|\[ -n "\$win" \] \|\| continue|win="${win:-1000000}"|' "$TMP/mutant2"
  # assert at least one patch applied, else the test is vacuous
  run grep -c '1000000' "$TMP/mutant2"
  [ "$status" -eq 0 ] || false
  [ "$output" -ge 1 ] || false
  chmod +x "$TMP/mutant2"
  run /bin/bash "$TMP/mutant2" --p95-recycle-fill --since all
  # the mutant folds s2/s4 in at an imputed denominator, so n must exceed the honest 2
  [[ "$output" != *"n=2"* ]] || false
}

# ── the recycle-events store is a valid second denominator source (M-3's contract) ─────────────
@test "a recycle-events record supplies a denominator when telemetry is gone" {
  rm -f "$TMP/telemetry"/*.json
  cat > "$CC_CTX_EVENTS" <<'EOF'
{"ts":"2026-07-20T10:02:00Z","sid":"s1","hook":"waiting-recycle","verdict":"executed","used_pct":75,"input_tokens":150000,"window":200000,"trigger":"threshold","mode":"idle"}
EOF
  run /bin/bash "$AUDIT" --p95-recycle-fill --since all
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"n=1"* ]] || false
}

# ── population hygiene ────────────────────────────────────────────────────────────────────────
@test "transcripts are deduped by realpath so a symlinked root cannot double-count" {
  ln -s "$TMP/projects/proj" "$TMP/projects/proj-link" 2>/dev/null || skip "no symlink support"
  run /bin/bash "$AUDIT" --wall-hits --since all
  [ "$status" -eq 0 ] || false
  # s1 must still be ONE session, not two
  [[ "$output" == *"1 session(s)"* ]] || false
}

@test "--since excludes events outside the window (positive control: 'all' includes them)" {
  run /bin/bash "$AUDIT" --wall-hits --since all
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"1 event(s)"* ]] || false
  # the fixture wall hit is 2026-07-20; a 1-day window from today must not contain it
  run /bin/bash "$AUDIT" --wall-hits --since 1d
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"0 event(s)"* ]] || false
}

@test "an unparseable --since exits 2 rather than silently widening to 'all'" {
  run /bin/bash "$AUDIT" --wall-hits --since "not-a-window"
  [ "$status" -eq 2 ] || false
}

@test "--json emits parseable JSON carrying the exclusion count" {
  run /bin/bash "$AUDIT" --p95-recycle-fill --since all --json
  [ "$status" -eq 0 ] || false
  run bash -c "printf '%s' '$output' | jq -e '.excluded_no_denominator' >/dev/null"
  [ "$status" -eq 0 ] || false
}
