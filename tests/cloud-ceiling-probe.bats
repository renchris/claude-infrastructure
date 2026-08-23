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

# A capable stub whose output CROSSES the 64 KiB pipe buffer, decisive line FIRST.
#
# The SIZE is the whole point. Every classifier in the probe is `producer | grep -q …` under
# `set -o pipefail`, and `grep -q` exits at its first match — so once the producer's write exceeds
# the pipe buffer it takes SIGPIPE, and the PIPELINE reports failure on the very input it just
# matched. The verdict then inverts on a property of the payload's LENGTH, which no pattern of the
# classifier's own can control (memory: grep-q-under-pipefail-inverts-the-verdict).
#
# Every stub above fits in the buffer, so none of them can reach that regime — which is precisely
# how a control named after a bug stays green (memory: control-fixture-must-reach-the-bugs-regime).
# And the large regime is the ORDINARY one here, not a corner case: a real create is a 180s PTY
# capture of a CLI that paints progress, colour and cursor moves the whole time.
#
# The filler is inert BY CONSTRUCTION — it matches no pattern in classify_outcome,
# is_harness_refusal or is_bundle_refusal — so any verdict change is attributable to length alone.
big_stub() { # $1 = the decisive first line (must contain no single quote); ~240 KB of filler follows
  cat > "$D/fake-claude" <<STUB
#!/bin/bash
# --cloud ultrareview
printf '%s\n' '$1'
awk 'BEGIN{ s=""; for(i=0;i<80;i++) s = s "inert-padding-bytes-"; for(j=0;j<150;j++) print s }'
exit 0
STUB
  chmod +x "$D/fake-claude"
  export CLOUD_CEILING_CLAUDE_BIN="$D/fake-claude"
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

# ── ADDED 2026-08-08 (gate G7, taking the measurement) ───────────────────────────────────────────
# Three properties the suite above does not yet hold, each found by running the probe for real
# against live accounts rather than by reading it.

@test "a rig refusal indicts THE RIG (exit 7) and explicitly exonerates the classifier" {
  # The live control's actual message, verbatim. The create path is interactive-only (§6.2) and the
  # call is inside $( ), so this fires on EVERY account before quota is ever consulted.
  capable_stub "Error: --cloud requires an interactive terminal. Non-interactive invocations (piped stdout, --init-only, --sdk-url) run locally and would silently ignore --cloud. Drop --cloud, or run from a TTY."
  run bash "$P" --control --confirm
  [ "$status" -eq 7 ]
  [[ "$output" == *"refused BEFORE the account was ever consulted"* ]] || false
  [[ "$output" == *"Do NOT touch classify_outcome"* ]] || false
  # The defect being pinned: it must NOT reach the arm that blames the classifier.
  [[ "$output" != *"classifier WRONG"* ]]
}

@test "a rig refusal carrying a QUOTA WORD still classifies as rig, never as the ceiling" {
  # The load-bearing ordering test. `is_harness_refusal` runs BEFORE the quota patterns, so a
  # refusal that mentions both cannot be published as a wall. Without the ordering this classifies
  # `refused-quota`, the control prints "VALIDATED", and a broken rig certifies itself — after which
  # a ramp would report a ceiling of N for a wall that was our own call.
  capable_stub "Error: --cloud requires an interactive terminal; your weekly limit reached is irrelevant here."
  run bash "$P" --control --confirm
  [ "$status" -eq 7 ]
  [[ "$output" != *"VALIDATED"* ]] || false
  [[ "$output" != *"CEILING"* ]]
}

@test "a rig refusal mid-ramp is its own verdict, distinct from a plain non-verdict" {
  # MIGRATED 2026-08-09, not deleted. This case used to feed the BUNDLE-UPLOAD string and assert
  # `verdict":"harness"` — because `Bundle upload failed` was folded into is_harness_refusal. That
  # classification is now known to be wrong: CONCURRENCY_PROGRAM.md §S5.3 measured the cause as this
  # repo's ~95 MiB seed bundle against a 100 MiB cap, which is a property of the REPO and the VENDOR,
  # not of how we invoked the binary. Left as-is, the assertion would have guarded the defect
  # (memory: stale-assertion-becomes-an-inverted-guard — the side with the incident wins).
  # The INTENT is preserved exactly: a rig refusal still gets its own verdict, distinct from a bare
  # non-verdict. Only the stimulus changed, to one that is genuinely about our own call.
  capable_stub "Error: --cloud requires an interactive terminal. Drop --cloud, or run from a TTY."
  run bash "$P" --account acct-a --max 4 --confirm
  [ "$status" -eq 0 ]
  [[ "$output" == *"about HOW IT CALLED"* ]] || false
  [[ "$output" != *"CEILING ="* ]] || false
  run /usr/bin/grep -c '"verdict":"harness"' "$CLOUD_CEILING_LEDGER"
  [ "$output" -eq 1 ]
}

@test "a BUNDLE refusal is its own verdict — not the rig's, not the ceiling's" {
  # The specificity control §S5.4 calls for, over a REAL artifact: the exact refusal this box
  # produces on demand, which must never reach the quota patterns and must never be blamed on the
  # rig. Ordered ahead of quota for the same reason `harness` is.
  capable_stub "Error: Bundle upload failed: Socket is closed after 3 attempts. Please setup GitHub on https://claude.ai/code"
  run bash "$P" --account acct-a --max 4 --confirm
  [ "$status" -eq 0 ]
  [[ "$output" != *"CEILING ="* ]] || false
  [[ "$output" != *"about HOW IT CALLED"* ]] || false
  [[ "$output" == *"seeding the sandbox"* ]] || false
  run /usr/bin/grep -c '"verdict":"bundle"' "$CLOUD_CEILING_LEDGER"
  [ "$output" -eq 1 ]
}

@test "a CREATED session is still created when the capture crosses the pipe buffer" {
  # Same stimulus as "THE REGRESSION" above, same token, same position on line 1 — only the
  # capture's LENGTH differs. That test is this one's positive control: if both are red the fixture
  # is broken, and only this one going red is the defect.
  #
  # Measured pre-fix: 200/200 created below 64 KiB, 1/100 AT 64 KiB, 0/200 at 200 KB. The probe
  # spends REAL weekly quota to reach this point, so the inversion converts a paid, successful
  # create into a published non-verdict — the one outcome a measurement rig must never buy.
  big_stub 'Created cloud session: session_01AAA'
  run bash "$P" --account acct-a --max 1 --confirm
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"LOWER BOUND"* ]] || false
  run /usr/bin/grep -c '"outcome":"created"' "$CLOUD_CEILING_LEDGER"
  [ "$output" -eq 1 ]
}

@test "a rig refusal is still the RIG's when the capture crosses the pipe buffer" {
  # is_harness_refusal is checked FIRST so that a fault in our own instrument can never be
  # published as a property of the accounts. Inverting it silently is therefore worse than
  # inverting the created arm: the run falls through to the quota patterns, and a rig fault
  # becomes a CEILING. This pairs with the small-payload rig test above.
  big_stub 'Error: --cloud requires an interactive terminal. Drop --cloud, or run from a TTY.'
  run bash "$P" --control --confirm
  [ "$status" -eq 7 ]
  [[ "$output" == *"refused BEFORE the account was ever consulted"* ]] || false
  [[ "$output" != *"classifier WRONG"* ]]
}

@test "a BUNDLE refusal is still the bundle's when the capture crosses the pipe buffer" {
  # The third ordered arm, and the one whose real-world capture is LARGEST: this refusal arrives
  # after three upload retries of a ~95 MiB bundle, with the CLI painting progress throughout.
  big_stub 'Error: Bundle upload failed: Socket is closed after 3 attempts. Please setup GitHub on https://claude.ai/code'
  run bash "$P" --account acct-a --max 4 --confirm
  [ "$status" -eq 0 ]
  [[ "$output" == *"seeding the sandbox"* ]] || false
  [[ "$output" != *"CEILING ="* ]] || false
  run /usr/bin/grep -c '"verdict":"bundle"' "$CLOUD_CEILING_LEDGER"
  [ "$output" -eq 1 ]
}

@test "every ledger row is attributable to its run and cwd" {
  # A ceiling is a COUNT OF ROWS in a SHARED file (~/.claude/autonomy/cloud/ceiling-probe.jsonl),
  # and this box runs many sessions at once — observed live, a concurrent probe interleaving with
  # this one mid-ramp. Unattributable rows do not merely lose provenance: two interleaved 2-create
  # runs read exactly like one 4-create run, so the ledger can publish a doubled ceiling.
  capable_stub "Created cloud session: session_01ABCdefGHIjklMNOpqrs"
  CLOUD_CEILING_RUN_ID=RUN-A run bash "$P" --account acct-a --max 2 --confirm
  [ "$status" -eq 0 ]
  CLOUD_CEILING_RUN_ID=RUN-B run bash "$P" --account acct-a --max 1 --confirm
  [ "$status" -eq 0 ]
  run /usr/bin/grep -c '"kind":"attempt"' "$CLOUD_CEILING_LEDGER"
  [ "$output" -eq 3 ]                       # positive control: all three really are in one file
  run bash -c "jq -r 'select(.kind==\"attempt\" and .run==\"RUN-A\")|.n' '$CLOUD_CEILING_LEDGER' | wc -l | tr -d ' '"
  [ "$output" -eq 2 ]                       # …and each run's own count is still recoverable
  run bash -c "jq -r 'select(.kind==\"attempt\" and .run==\"RUN-B\")|.n' '$CLOUD_CEILING_LEDGER' | wc -l | tr -d ' '"
  [ "$output" -eq 1 ]
  run bash -c "jq -r 'select(.kind==\"attempt\")|.cwd' '$CLOUD_CEILING_LEDGER' | sort -u | wc -l | tr -d ' '"
  [ "$output" -eq 1 ]                       # cwd is a live variable, not context — see §S5.2
}

@test "the create runs under a pty that needs no tty of its own" {
  # scripts/lib/pty-run.py, not script(1): script calls tcgetattr on ITS OWN stdin and dies
  # "Operation not supported on socket" from an agent call, cron, launchd or CI — i.e. everywhere a
  # measurement rig actually runs. The stub reports what it sees, so this fails if the allocator
  # ever silently stops being applied.
  capable_stub ""
  cat > "$D/fake-claude" <<'STUB'
#!/bin/bash
# --cloud ultrareview
if [ -t 1 ]; then echo "Error: weekly limit reached (saw a TTY)"; else echo "Error: NO-TTY"; fi
STUB
  chmod +x "$D/fake-claude"
  export CLOUD_CEILING_CLAUDE_BIN="$D/fake-claude"
  run bash "$P" --control --confirm
  [ "$status" -eq 0 ]
  [[ "$output" == *"saw a TTY"* ]] || false
  [[ "$output" != *"NO-TTY"* ]]
}
