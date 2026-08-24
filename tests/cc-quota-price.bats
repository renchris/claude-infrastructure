#!/usr/bin/env bats
# bin/cc-quota-price — the tokens→weekly-percentage-point price list (USAGE_TELEMETRY_100P M4).
#
# THE PINNED INVARIANT: this tool converts a token census into quota, and the conversion is worth
# nothing unless the census is DEDUPED ON `message.id`. Claude Code writes a streamed assistant
# message once per content block — same id, same requestId, identical complete `usage` — so a
# census that sums records counts one billing event 2-3x. That bug survived three independent
# derivations in the research wave that produced this plan and shipped a price list 2.1-2.8x too
# high (§2.1). Case "RED-PROOF" below runs the PRODUCTION extractor with its dedup disabled and
# asserts the inflation, so the invariant cannot be deleted without a red.
#
# The second invariant is ABSTAIN-NEVER-IMPUTE (§3.3.4): every path with no recoverable
# denominator must name its reason and report no numbers. An instrument that quietly interpolates
# over an empty join is the `cc-value` failure (§2.7) in a new file.
#
# The tool's own `--selftest` carries 13 hermetic cases including a fit against a KNOWN price
# vector; this suite is the gate's entry point to it plus the contract checks a caller depends on.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  QP="$REPO_ROOT/bin/cc-quota-price"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  T=1787000000                     # frozen "now" — every fixture stamp is relative to it
  BW=21600                         # the 6h bucket width the producer aligns to
  ROOT="$BATS_TEST_TMPDIR/.claude-secondary/projects"
  mkdir -p "$ROOT/proj"
  UTIL="$BATS_TEST_TMPDIR/util.jsonl"
  export CC_NOW="$T" CC_UTIL_LOG="$UTIL" CC_QP_ROOTS="$ROOT=next2"
}

# One transcript line, in the exact shape Claude Code writes.
_tx() { # $1=iso $2=msgid $3=out $4=cc $5=cr
  printf '{"type":"assistant","timestamp":"%s","requestId":"req_%s","message":{"id":"%s","model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s}}}\n' \
    "$1" "$2" "$2" "$3" "$4" "$5"
}
_util() { # $1=iso $2=weekly_pct [$3=stale]
  printf '{"ts":"%s","acct":"next2","weekly_pct":%s,"weekly_reset_at":"2026-08-23T00:00:00Z","stale":%s}\n' \
    "$1" "$2" "${3:-false}"
}
_iso() { python3 -c 'import sys,datetime;print(datetime.datetime.fromtimestamp(int(sys.argv[1]),datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }

# Substring assertions as SIMPLE COMMANDS, never `[[ ]]`. bats bodies run under `set -eET`, and
# bash exempts the `[[` keyword from errexit — so a non-final `[[ ... ]]` evaluates, discards its
# false result, and the test passes anyway (scripts/bats-assert-liveness.py flags exactly this,
# and flagged five of these before they were converted). `grep` and `[` are ordinary commands, so
# their failure aborts the body wherever it sits.
_has()   { printf '%s\n' "$2" | grep -qF -- "$1"; }
_hasnt() { [ "$(printf '%s\n' "$2" | grep -cF -- "$1")" -eq 0 ]; }

# A priceable fixture: 24 aligned 6h buckets whose Δweekly_pct is synthesized from a KNOWN
# coefficient vector (output 4.0 pp/Mtok, cache_creation 0.3 pp/Mtok), so the fit has a truth.
_priceable() {
  python3 - "$UTIL" "$ROOT/proj/b.jsonl" "$T" <<'PY'
import sys, json, datetime
util, tx, T = sys.argv[1], sys.argv[2], int(sys.argv[3])
BW = 21600
iso = lambda e: datetime.datetime.fromtimestamp(e, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
wp = 0.0
with open(util, "w") as uh, open(tx, "w") as th:
    for i in range(24):
        t0 = (T // BW - (30 - i)) * BW
        out, cc = 40000 + 7000 * (i % 5), 900000 + 130000 * (i % 3)
        dpp = out * 4.0e-6 + cc * 0.3e-6
        for s in range(12):
            uh.write(json.dumps({"ts": iso(t0 + s * 1800), "acct": "next2", "weekly_pct": wp,
                                 "weekly_reset_at": "2026-08-23T00:00:00Z", "stale": False}) + "\n")
        uh.write(json.dumps({"ts": iso(t0 + 5 * 3600 + 3000), "acct": "next2", "weekly_pct": wp + dpp,
                             "weekly_reset_at": "2026-08-23T00:00:00Z", "stale": False}) + "\n")
        wp += dpp
        th.write(json.dumps({"type": "assistant", "timestamp": iso(t0 + 600),
                             "requestId": f"r{i}", "message": {"id": f"m{i}", "model": "claude-opus-5",
                             "usage": {"input_tokens": 100, "output_tokens": out,
                                       "cache_creation_input_tokens": cc,
                                       "cache_read_input_tokens": out * 300}}}) + "\n")
PY
}

@test "the tool's own hermetic selftest is green (13 cases, incl. the dedup RED-proof)" {
  run "$QP" --selftest
  [ "$status" -eq 0 ]
  _has "0 failed" "$output"
}

@test "DEDUP: three streamed lines of ONE message.id count as ONE billed response" {
  # The real shape: same id, same requestId, identical complete usage on every content block.
  for _ in 1 2 3; do _tx "$(_iso $((T-3600)))" msgA 1000 5000 900000; done > "$ROOT/proj/a.jsonl"
  run "$QP" --census --json --since 1d
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.tokens.output')" -eq 1000 ]
  [ "$(echo "$output" | jq -r '.census.deduped')" -eq 1 ]
  [ "$(echo "$output" | jq -r '.census.repeats')" -eq 2 ]
}

@test "RED-PROOF: the production extractor with dedup DISABLED inflates output >=2x" {
  # This is what makes the case above a live assertion rather than a passing tautology. If anyone
  # deletes the dedup, the case above goes red; if anyone weakens this bound, this case goes red.
  for _ in 1 2 3; do _tx "$(_iso $((T-3600)))" msgA 1000 5000 900000; done > "$ROOT/proj/a.jsonl"
  # NOT `run`: bats merges stderr into $output, and the seam's own loud warning (asserted by the
  # next case) would then be parsed as part of the JSON.
  naive="$(CC_QP_DEDUP=0 "$QP" --census --json --since 1d 2>/dev/null | jq -r '.tokens.output')"
  [ "$naive" -ge 2000 ]
}

@test "RED-PROOF: the dedup kill seam announces itself loudly on stderr" {
  # A seam that can silently corrupt every number this tool publishes must never be quiet.
  _tx "$(_iso $((T-3600)))" msgA 1000 5000 900000 > "$ROOT/proj/a.jsonl"
  run env CC_QP_DEDUP=0 bash -c "'$QP' --census --json --since 1d 2>&1 >/dev/null"
  _has "CC_QP_DEDUP=0" "$output"
  _has "TEST SEAM" "$output"
}

@test "ABSTAIN: an absent utilization store names the path AND the rung, exit 3, no price" {
  _tx "$(_iso $((T-3600)))" msgA 1000 5000 900000 > "$ROOT/proj/a.jsonl"
  CC_UTIL_LOG="$BATS_TEST_TMPDIR/nope.jsonl" run "$QP" --json --since 1d
  [ "$status" -eq 3 ]
  [ "$(echo "$output" | jq -r '.verdict')" = ABSTAIN ]
  reason="$(echo "$output" | jq -r '.reason')"
  _has "nope.jsonl" "$reason"
  _has "does not exist" "$reason"
  [ "$(echo "$output" | jq -r '.price // "absent"')" = absent ]
}

@test "ABSTAIN: too few MOVING buckets names the count and the floor, and reports no price" {
  _priceable
  run "$QP" --json --since 10d --min-buckets 500
  [ "$status" -eq 3 ]
  [ "$(echo "$output" | jq -r '.verdict')" = ABSTAIN ]
  _has "500" "$(echo "$output" | jq -r '.reason')"
  [ "$(echo "$output" | jq -r '.price // "absent"')" = absent ]
}

@test "FIT: a KNOWN price vector is recovered within 5% from a synthesized corpus" {
  _priceable
  run "$QP" --json --since 10d --bucket-h 6
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.verdict')" = OK ]
  # 4.0 pp/Mtok output, 0.3 pp/Mtok cache_creation — the vector the fixture was built from
  [ "$(echo "$output" | jq -r '(.price.output.pp_per_mtok - 4.0 | fabs) < 0.2')" = true ]
  [ "$(echo "$output" | jq -r '(.price.cache_creation.pp_per_mtok - 0.3 | fabs) < 0.015')" = true ]
  # NON-DEGENERACY: the same tolerance must REJECT a price the fixture was not built from
  [ "$(echo "$output" | jq -r '(.price.output.pp_per_mtok - 8.0 | fabs) < 0.4')" = false ]
}

@test "cache_read is reported as BOUNDED by experiment and never enters the design matrix" {
  # §2.8 bounded it by experiment; observationally it is collinear with output (r~+0.91) and NNLS
  # is bounded below at zero, so a fitted 0.0000 would be a boundary artifact, not a measurement.
  _priceable
  run "$QP" --json --since 10d
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.price.cache_read.kind')" = bounded ]
  [ "$(echo "$output" | jq -r '.price.cache_read.pp_per_mtok')" = null ]
  [ "$(echo "$output" | jq -r '.price.cache_read.bound_pp_per_mtok')" = 0.049 ]
  [ "$(echo "$output" | jq -r '.fit.coef_pp_per_token | has("cache_read")')" = false ]
}

@test "--with-cache-read admits the column as a labelled DIAGNOSTIC, never as the price list" {
  _priceable
  run "$QP" --json --since 10d --with-cache-read
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.price.cache_read.kind')" = diagnostic ]
  [ "$(echo "$output" | jq -r '[.caveats[] | select(contains("DIAGNOSTIC"))] | length')" -ge 1 ]
}

@test "a bucket spanning a weekly RESET is dropped, not read as negative spend" {
  # The §1 error class in miniature: a periodically-resetting counter read as if it were
  # cumulative. It inverted this plan's own opening premise, in the fleet's headline renderer.
  _priceable
  before="$("$QP" --json --since 10d | jq -r '.buckets.moving')"
  t0=$(( (T / BW - 3) * BW ))
  for s in 0 1 2 3 4 5 6 7 8 9 10 11; do
    _util "$(_iso $((t0 + s*1800)))" "$((90 - s))" >> "$UTIL"
  done
  _util "$(_iso $((t0 + 21000)))" 95 >> "$UTIL"
  after="$("$QP" --json --since 10d | jq -r '.buckets.moving')"
  [ "$after" -eq "$before" ]
}

@test "stale utilization rows never enter a bucket — 'could not measure' is not 'nothing happened'" {
  _priceable
  before="$("$QP" --json --since 10d | jq -r '.buckets.moving')"
  t0=$(( (T / BW - 2) * BW ))
  for s in 0 1 2 3 4 5 6 7 8 9 10 11; do
    _util "$(_iso $((t0 + s*1800)))" 95 true >> "$UTIL"
  done
  _util "$(_iso $((t0 + 21000)))" 99 true >> "$UTIL"
  after="$("$QP" --json --since 10d | jq -r '.buckets.moving')"
  [ "$after" -eq "$before" ]
}

@test "the table renderer prints a reason and NO price table on ABSTAIN" {
  CC_UTIL_LOG="$BATS_TEST_TMPDIR/nope.jsonl" run "$QP" --since 1d
  [ "$status" -eq 3 ]
  _has ABSTAIN "$output"
  _hasnt "pp / Mtok" "$output"
}

@test "a symlinked transcript root cannot double-count a file" {
  # ~/.claude-next{,2,3,4}/projects are SYMLINKS into the four real config dirs (§1). A naive glob
  # over both counts every response twice — the same 2x error the message.id dedup prevents, one
  # level up, and it would inflate the numerator exactly as silently.
  _tx "$(_iso $((T-3600)))" msgA 1000 5000 900000 > "$ROOT/proj/a.jsonl"
  ln -s "$ROOT" "$BATS_TEST_TMPDIR/mirror"
  CC_QP_ROOTS="$ROOT=next2:$BATS_TEST_TMPDIR/mirror=next2" run "$QP" --census --json --since 1d
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.tokens.output')" -eq 1000 ]
}

@test "an unknown argument is a usage error, never a silently ignored flag" {
  run "$QP" --no-such-flag
  [ "$status" -eq 2 ]
}
