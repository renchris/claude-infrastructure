#!/usr/bin/env bats
# cloud-ceiling-probe.sh — the Wave F instrument, pinned on the property that it cannot silently
# measure nothing.
#
# THE DEFECT THIS SUITE EXISTS FOR, and it is the probe's own. The first live `--control` run
# printed its header, fired its create, and stopped. Exit 0. No verdict line, no ledger record.
# Cause: `IFS=$'\t' read -r a b < <(fire_one …)` returns 1 when the producer's last line carries no
# trailing newline — the values are assigned, the rc is 1, and `set -e` kills the script between the
# API call and the record. So the probe SPENT its attempt and produced no evidence, while exiting 0
# so it read as a clean run that happened to say little. For a measurement tool that is the worst
# available failure: it is indistinguishable from "nothing to report".
#
# Everything below stubs the create. A real one spends the operator's weekly quota, and a test that
# can spend money is a test nobody runs twice.
#
# Assertions are `[ ] || false`; the negative form is `! A || false`. `A && false` is and-absorbed
# and can never fail.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  P="$REPO/scripts/cloud-ceiling-probe.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLOUD_CEILING_LEDGER="$BATS_TEST_TMPDIR/ledger.jsonl"
  export CLOUD_CEILING_ACCOUNTS="$BATS_TEST_TMPDIR/accounts.json"
  D="$BATS_TEST_TMPDIR/bin"; mkdir -p "$D"
  export PATH="$D:$PATH"
  mkdir -p "$BATS_TEST_TMPDIR/cfg-a" "$BATS_TEST_TMPDIR/cfg-b"
  cat > "$CLOUD_CEILING_ACCOUNTS" <<EOF
{"accounts":[{"name":"acct-a","config_dir":"$BATS_TEST_TMPDIR/cfg-a"},
             {"name":"acct-b","config_dir":"$BATS_TEST_TMPDIR/cfg-b"}]}
EOF
  quota acct-a 30 acct-b 100
}

# A claude-accounts stub. Its rows use `.rows[].acct` / `.weekly_pct` — the REAL shape, because
# assuming accounts.json's `.accounts[].name` here instead is a bug this script actually shipped and
# a stub in the wrong shape would let it ship again.
quota() {
  local rows="" ; while [ $# -gt 0 ]; do rows="$rows{\"acct\":\"$1\",\"weekly_pct\":$2},"; shift 2; done
  cat > "$D/claude-accounts" <<EOF
#!/bin/bash
echo '{"rows":[${rows%,}]}'
EOF
  chmod +x "$D/claude-accounts"
}

# $1 = what the fake create prints. The probe must never see a real binary here.
fake_claude() {
  printf '#!/bin/bash\ncat <<'"'"'OUT'"'"'\n%s\nOUT\nexit %s\n' "$1" "${2:-0}" > "$D/fake-claude"
  chmod +x "$D/fake-claude"
  export CLOUD_CEILING_CLAUDE_BIN="$D/fake-claude"
}

# The capability guard greps the binary for `--cloud` against an `ultrareview` positive control.
# A shell-script stub contains both strings if we put them there, which is what makes it usable as
# a stand-in for a capable binary.
capable_stub() {
  fake_claude "$1" "${2:-0}"
  printf '\n# --cloud ultrareview\n' >> "$D/fake-claude"
}

@test "THE REGRESSION: a created verdict reaches the ledger — the read does not kill the run" {
  capable_stub 'Created cloud session: session_01AAA'
  run "$P" --account acct-a --max 1 --confirm
  [ "$status" -eq 0 ] || false
  # Header alone is what the broken version produced. The VERDICT is the evidence.
  echo "$output" | grep -q 'LOWER BOUND' || false
  grep -q '"kind":"attempt"' "$CLOUD_CEILING_LEDGER" || false
  grep -q '"outcome":"created"' "$CLOUD_CEILING_LEDGER" || false
}

@test "a quota refusal is the CEILING, and the ramp stops there" {
  capable_stub 'Error: usage limit reached for this account' 1
  run "$P" --account acct-a --max 5 --confirm
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q 'CEILING = 0' || false
  grep -q '"verdict":"ceiling"' "$CLOUD_CEILING_LEDGER" || false
}

@test "a NON-quota refusal is a NON-VERDICT — no number is published" {
  capable_stub 'Error: could not resolve host api.anthropic.com' 1
  run "$P" --account acct-a --max 5 --confirm
  echo "$output" | grep -q 'NON-VERDICT' || false
  ! echo "$output" | grep -q 'CEILING =' || false
  grep -q '"verdict":"nonverdict"' "$CLOUD_CEILING_LEDGER" || false
}

@test "reaching --max without a refusal is a LOWER BOUND, never the ceiling" {
  capable_stub 'Created cloud session: session_01BBB'
  run "$P" --account acct-a --max 3 --confirm
  echo "$output" | grep -q 'AT LEAST 3' || false
  ! echo "$output" | grep -q 'CEILING =' || false
}

# ── the capability guard, all three states ───────────────────────────────────────────────────────

@test "an incapable binary REFUSES up front — it must not ramp into per-attempt non-verdicts" {
  fake_claude 'irrelevant'          # no --cloud literal, but no control literal either…
  printf '\n# ultrareview\n' >> "$D/fake-claude"   # …so give it the control ONLY: flag genuinely absent
  run "$P" --account acct-a --max 3 --confirm
  [ "$status" -eq 6 ] || false
  echo "$output" | grep -q 'no --cloud flag' || false
  # Nothing was attempted, so nothing may be recorded.
  ! grep -q '"kind":"attempt"' "$CLOUD_CEILING_LEDGER" 2>/dev/null || false
}

@test "a DEAD positive control says 'cannot tell', never 'no flag'" {
  fake_claude 'irrelevant'          # neither literal present ⇒ the grep proves nothing
  run "$P" --account acct-a --max 3 --confirm
  [ "$status" -eq 6 ] || false
  echo "$output" | grep -q 'cannot tell' || false
  ! echo "$output" | grep -q 'no --cloud flag' || false
}

# ── the free control, and the thing that makes it a control ──────────────────────────────────────

@test "--control picks the LIMITED account live, and validates the classifier on a real refusal" {
  capable_stub 'Error: weekly limit reached' 1
  run "$P" --control --confirm
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q 'acct-b' || false          # the 100% one, chosen live — never hardcoded
  echo "$output" | grep -q 'VALIDATED' || false
}

@test "--control FAILS LOUD when a known quota refusal classifies as something else" {
  capable_stub 'Error: could not resolve host' 1
  run "$P" --control --confirm
  [ "$status" -eq 5 ] || false
  echo "$output" | grep -q 'classifier WRONG' || false
}

@test "--control is VOID, not a pass, if the 'limited' account actually creates" {
  capable_stub 'Created cloud session: session_01CCC'
  run "$P" --control --confirm
  [ "$status" -eq 4 ] || false
  echo "$output" | grep -q 'VOID' || false
}

@test "--control DEFERS rather than passing when no account is at 100%" {
  quota acct-a 30 acct-b 40
  capable_stub 'Created cloud session: session_01DDD'
  run "$P" --control --confirm
  [ "$status" -eq 3 ] || false
  echo "$output" | grep -q 'DEFERRAL' || false
}

# ── the two field-shape bugs that both read empty ────────────────────────────────────────────────

@test "a ~-prefixed config_dir is expanded, not passed through literally" {
  cat > "$CLOUD_CEILING_ACCOUNTS" <<EOF
{"accounts":[{"name":"acct-a","config_dir":"~/cfg-tilde"}]}
EOF
  mkdir -p "$HOME/cfg-tilde"
  capable_stub 'Created cloud session: session_01EEE'
  run "$P" --account acct-a --max 1 --confirm
  # An unexpanded ~ would make config_dir_for yield a path that exists nowhere; the run would still
  # "work" here, so the assertion is on the RECORD being a real created reading, not on rc.
  grep -q '"outcome":"created"' "$CLOUD_CEILING_LEDGER" || false
}

@test "an unreadable quota reads '?', never 0 — 0 would say 'plenty of headroom left'" {
  rm -f "$D/claude-accounts"
  capable_stub 'Created cloud session: session_01FFF'
  run "$P" --account acct-a --max 1 --confirm
  echo "$output" | grep -q 'weekly_before=?%' || false
}

@test "no --confirm spends nothing, at either entry point" {
  capable_stub 'Created cloud session: session_01GGG'
  run "$P" --account acct-a --max 3
  [ "$status" -eq 2 ] || false
  run "$P" --control
  [ "$status" -eq 2 ] || false
  [ ! -f "$CLOUD_CEILING_LEDGER" ] || ! grep -q '"kind":"attempt"' "$CLOUD_CEILING_LEDGER" || false
}
