#!/usr/bin/env bats
# headless-precondition-probe.sh — the instrument Phase E's precondition is decided by.
#
# WHAT THIS SUITE IS FOR. The probe itself must launch a real `claude` to be worth anything, which
# is not hermetic and cannot run in a verifier. What CAN be pinned — and what actually went wrong
# during the wave — is the VERDICT LOGIC. On its first run the probe returned `P3 mail PASS` on the
# strength of an advanced inbox cursor, while the message had reached nothing: `additionalContext`
# is injected into the model's context and is invisible in the output stream, so "drained and
# delivered" and "drained and silently discarded" have the identical signature there.
#
# Test 2 is that vacuous pass, pinned so it cannot return: enqueued + cursor-advanced + token NOT
# echoed must be PARTIAL. Test 5 is its mutation check — it restores the original cursor-based rule
# and asserts test 2 flips to PASS, so test 2 cannot itself be passing for free.
#
# The `claude` binary is stubbed. The stub reproduces only the surface the probe reads: it holds
# stdin open, writes stream-json, and appends hook names to the probe's own log.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  P="$REPO/scripts/headless-precondition-probe.sh"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME/.claude/bin" "$D/mail"
  export CC_MAILBOX_DIR="$D/mail"

  # ── stub `claude` ───────────────────────────────────────────────────────────────────────────
  # CC_STUB_HOOKS  : which hook names to report as fired
  # CC_STUB_REPLY  : what the "model" says about its inbox — the token, or NOMAIL, or nothing
  cat > "$D/claude" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
log="${CC_STUB_LOG:?}"
for ev in ${CC_STUB_HOOKS:-}; do echo "$ev" >> "$log"; done
printf '{"type":"system","subtype":"init"}\n'
while IFS= read -r _line; do
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"PROBEOK %s"}]}}\n' "${CC_STUB_REPLY:-}"
  printf '{"type":"result","result":"done"}\n'
done
STUB
  chmod +x "$D/claude"
  export CC_HEADLESS_PROBE_BIN="$D/claude"
  export CC_STUB_LOG=""   # set per-test, after the probe creates its work dir

  # ── stub `cc-notify` ────────────────────────────────────────────────────────────────────────
  # Reproduces the v2 transport exactly: append one line to <uuid>.md, print a verdict token.
  # It also advances the .seen cursor, which is what made the original vacuous pass possible.
  cat > "$HOME/.claude/bin/cc-notify" <<'NOTIFY'
#!/usr/bin/env bash
set -uo pipefail
while [ "${1:-}" = "--mailbox-only" ]; do shift; done
uuid="$1"; shift
dir="${CC_MAILBOX_DIR:?}"; mkdir -p "$dir"
echo "$(date +%FT%T) [test] $*" >> "$dir/$uuid.md"
wc -l < "$dir/$uuid.md" | tr -d ' ' > "$dir/$uuid.seen"
echo "cc-notify: verdict=mailbox-only enqueued=1 uuid=$uuid" >&2
NOTIFY
  chmod +x "$HOME/.claude/bin/cc-notify"
}

# The probe generates its own work dir and its own MAIL_TOKEN; the stub needs to echo that token
# back to simulate delivery. We pre-seed the reply with the token pattern the probe will use.
run_probe() { # <hooks> <reply-mode>
  W="$D/work.$RANDOM"
  export CC_STUB_LOG="$W/hookfire.log"
  mkdir -p "$W"; : > "$CC_STUB_LOG"
  export CC_STUB_HOOKS="$1"
  case "$2" in
    token)  export CC_STUB_REPLY="HEADLESSPROBE-ECHOED" ;;
    nomail) export CC_STUB_REPLY="NOMAIL" ;;
    silent) export CC_STUB_REPLY="" ;;
  esac
  # The probe's token is HEADLESSPROBE-<its pid>; we cannot know it in advance, so for the "token"
  # case we make the stub echo whatever is already in the mailbox — the honest emulation of a drain.
  if [ "$2" = token ]; then
    cat > "$D/claude" <<'STUB2'
#!/usr/bin/env bash
set -uo pipefail
log="${CC_STUB_LOG:?}"
for ev in ${CC_STUB_HOOKS:-}; do echo "$ev" >> "$log"; done
printf '{"type":"system","subtype":"init"}\n'
while IFS= read -r _line; do
  tok="$(cat "${CC_MAILBOX_DIR:?}"/*.md 2>/dev/null | grep -o 'HEADLESSPROBE-[0-9]*' | head -1)"
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"PROBEOK %s"}]}}\n' "$tok"
  printf '{"type":"result","result":"done"}\n'
done
STUB2
    chmod +x "$D/claude"
  fi
  run bash "$P" --dir "$W" --timeout 12
}

ALL_HOOKS="SessionStart UserPromptSubmit PreToolUse PostToolUse Stop SessionEnd"

@test "1 full hook set + token echoed back ⇒ P1/P2/P3 all PASS" {
  run_probe "$ALL_HOOKS" token
  [ "$status" -eq 0 ]
  [[ "$output" == *"P1 no-pty     PASS"* ]] || false
  [[ "$output" == *"P2 hooks      PASS"* ]] || false
  [[ "$output" == *"P3 mail       PASS"* ]] || false
  [[ "$output" == *"reached-model=yes"* ]]
}

@test "2 cursor advanced but token NOT echoed ⇒ PARTIAL, never PASS (the vacuous pass, pinned)" {
  run_probe "$ALL_HOOKS" silent
  # Enqueued: yes. Cursor advanced: yes. Reached the model: unproven. That is PARTIAL.
  [[ "$output" == *"enqueued=yes"* ]] || false
  [[ "$output" == *"cursor-advanced=yes"* ]] || false
  [[ "$output" == *"reached-model=no"* ]] || false
  [[ "$output" == *"P3 mail       PARTIAL"* ]] || false
  [[ "$output" != *"P3 mail       PASS"* ]]
}

@test "3 model positively denies receiving mail ⇒ P3 FAIL" {
  run_probe "$ALL_HOOKS" nomail
  [[ "$output" == *"P3 mail       FAIL"* ]] || false
  [ "$status" -eq 1 ]          # a FAIL predicate is the only thing that makes the probe exit non-zero
}

@test "4 a missing hook is reported by NAME, not rounded into PASS" {
  run_probe "SessionStart UserPromptSubmit Stop SessionEnd" token
  [[ "$output" == *"P2 hooks      PARTIAL"* ]] || false
  [[ "$output" == *"PreToolUse"* ]] || false
  [[ "$output" == *"PostToolUse"* ]]
}

@test "5 no hooks at all ⇒ P2 FAIL — the precondition that would kill the wave" {
  run_probe "" token
  [[ "$output" == *"P2 hooks      FAIL"* ]] || false
  [ "$status" -eq 1 ]
}

# ── MUTATION CHECK ────────────────────────────────────────────────────────────────────────────────

@test "6 MUTANT: restoring the cursor-based P3 rule turns test 2 back into a false PASS" {
  cp "$P" "$D/mutant.sh"
  n=$(grep -c 'if   \[ "\$P3_REACHED_MODEL" = yes \]; then P3=PASS' "$D/mutant.sh")
  [ "$n" -eq 1 ]                       # anchored to exactly one site
  # This is verbatim the rule the probe shipped with on its first run.
  sed -i '' 's|if   \[ "\$P3_REACHED_MODEL" = yes \]; then P3=PASS|if   [ "$P3_ENQUEUED" = yes ] \&\& [ "$P3_CONSUMED" = yes ]; then P3=PASS|' "$D/mutant.sh"
  bash -n "$D/mutant.sh"               # a mutant that does not parse would red everything vacuously

  W="$D/work.mut"
  export CC_STUB_LOG="$W/hookfire.log"
  mkdir -p "$W"; : > "$CC_STUB_LOG"
  export CC_STUB_HOOKS="$ALL_HOOKS"
  export CC_STUB_REPLY=""              # token NOT echoed — exactly test 2's scenario
  run bash "$D/mutant.sh" --dir "$W" --timeout 12
  [[ "$output" == *"reached-model=no"* ]] || false
  [[ "$output" == *"P3 mail       PASS"* ]]   # the false PASS, reproduced on demand
}
