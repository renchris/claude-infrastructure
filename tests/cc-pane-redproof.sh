#!/bin/bash
# cc-pane-redproof — prove tests/cc-pane.bats and tests/cc-pane-headless.bats can actually FAIL.
#
# WHY THIS EXISTS. This repo's recorded failure mode is the VACUOUS PASS — a suite that is green
# because it asserts nothing reachable, not because the subject is correct. A green run is
# therefore not evidence on its own. This harness supplies the missing half: for each load-bearing
# claim it MUTATES THE REAL ARTIFACT, re-runs the suite, and requires the NAMED test to go red.
#
# Two anti-vacuity rules it enforces on itself, because a red-proof can be vacuous too:
#   1. The mutation must APPLY — the anchor must match EXACTLY ONCE. A sed that silently matches
#      nothing produces a "mutant" byte-identical to the original, which passes, which would be
#      read as "the test cannot fail" when in truth the harness never tested anything (memory:
#      control-must-replay-the-real-artifact).
#   2. The mutant runs against a COPY OF THE REAL FILES, never a hand-written approximation —
#      an approximation passes vacuously no matter how carefully it is written.
#
# Exit: 0 = every mutant was caught by its named test · 1 = at least one survived (tests are weak)

# shellcheck disable=SC2016
# SC2016 is disabled file-wide ON PURPOSE: the mutation table below is made of single-quoted
# LITERAL SOURCE FRAGMENTS of the subject scripts. Every `$var` in them must stay unexpanded —
# expanding one would make the anchor fail to match, which this harness reports as a BROKEN
# MUTANT. The lint is right about the syntax and wrong about the intent.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BATS="${BATS_BIN:-$HOME/.claude/bin/bats}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/cc-pane-redproof.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0

# Literal (non-regex) single-occurrence replace. Refuses on any count != 1, so an anchor that
# rotted with the source cannot silently degrade this harness into a no-op.
mutate() { # $1=file $2=from $3=to
  FROM="$2" TO="$3" /usr/bin/python3 - "$1" <<'PY'
import os, sys
p = sys.argv[1]
s = open(p).read()
frm, to = os.environ["FROM"], os.environ["TO"]
n = s.count(frm)
if n != 1:
    sys.stderr.write("ANCHOR MATCHED %d TIMES (need exactly 1): %r\n" % (n, frm[:70]))
    sys.exit(9)
open(p, "w").write(s.replace(frm, to))
PY
}

# $1=label $2=relative file $3=from $4=to $5=substring of the test that MUST go red
check() {
  local label="$1" rel="$2" from="$3" to="$4" want="$5"
  local sandbox="$WORK/$RANDOM$$"
  mkdir -p "$sandbox"
  # hooks/ and scripts/ come along because the suite now asserts against REAL consumers (the
  # session-register.sh live-rename test and the bare-read ratchet). Without them those tests fail
  # for a missing-file reason under EVERY mutant, which would drown the signal this harness exists
  # to produce.
  cp -R "$REPO/bin" "$REPO/tests" "$REPO/hooks" "$REPO/scripts" "$sandbox/" \
    || { echo "SETUP FAIL $label"; fail=$((fail+1)); return; }

  if ! mutate "$sandbox/$rel" "$from" "$to"; then
    printf '  \033[31mBROKEN MUTANT\033[0m %-42s (anchor did not apply — harness is stale)\n' "$label"
    fail=$((fail+1)); return
  fi
  # The mutant must genuinely differ from the shipped file.
  if cmp -s "$sandbox/$rel" "$REPO/$rel"; then
    printf '  \033[31mBROKEN MUTANT\033[0m %-42s (byte-identical to the original)\n' "$label"
    fail=$((fail+1)); return
  fi

  local out="$sandbox/out.tap"
  # NO pipe: `bats | tail` reports the PIPE's exit code, not bats' (memory:
  # verification-harness-vacuous-pass-traps).
  "$BATS" "$sandbox/tests/cc-pane.bats" "$sandbox/tests/cc-pane-headless.bats" >"$out" 2>&1
  local rc=$?

  # A suite that produced NO verdict (`1..0`, a harness crash) is a NON-VERDICT, never a pass and
  # never a catch — it must not be counted as the mutant being caught.
  if ! grep -qE '^1\.\.[1-9]' "$out"; then
    printf '  \033[31mNON-VERDICT\033[0m  %-42s (suite produced no plan — nothing was proven)\n' "$label"
    fail=$((fail+1)); return
  fi

  if [ "$rc" -eq 0 ]; then
    printf '  \033[31mSURVIVED\033[0m     %-42s (suite stayed GREEN — the test is vacuous)\n' "$label"
    fail=$((fail+1)); return
  fi
  # Red is not enough: the RIGHT test must be the one that caught it, else the mutant was caught
  # by collateral damage and the named claim is still unproven.
  if ! grep '^not ok' "$out" | grep -F "$want" >/dev/null; then
    printf '  \033[31mWRONG TEST\033[0m   %-42s (red, but not via: %s)\n' "$label" "$want"
    grep '^not ok' "$out" | head -3 | sed 's/^/      /'
    fail=$((fail+1)); return
  fi
  printf '  \033[32mcaught\033[0m       %-42s → %s\n' "$label" "$want"
  pass=$((pass+1))
}

echo "RED-PROOF — mutating the real bin/cc-pane{,-headless} and requiring the named test to fail"
echo

# ── the seam ──────────────────────────────────────────────────────────────────────────────
check "blind-enumeration-reads-as-empty" bin/cc-pane \
  '[ "$n" -eq 0 ] && return "$RC_INDET"' \
  ':' \
  'ZERO-row enumeration is INDETERMINATE'

check "unknown-driver-falls-back-silently" bin/cc-pane \
  '[ -x "$exe" ] || { printf '"'"'cc-pane: no driver %s (looked for %s)\n'"'"' "$DRIVER" "$exe" >&2; exit "$RC_USAGE"; }' \
  '[ -x "$exe" ] || return 0' \
  'unknown driver is a NAMED rc 3'

check "ITERM_SESSION_ID-wins-over-CC_PANE_ID" bin/cc-pane \
  '  local v="${CC_PANE_ID:-}"
  [ -n "$v" ] || v="${ITERM_SESSION_ID:-}"   # cc-pane-id-lint:allow — this line IS the fallback' \
  '  local v="${ITERM_SESSION_ID:-}"
  [ -n "$v" ] || v="${CC_PANE_ID:-}"   # cc-pane-id-lint:allow — this line IS the fallback' \
  'CC_PANE_ID WINS when both are set'

check "close-drops-the-force-flag" bin/cc-pane \
  'session close -f -s "$1"' \
  'session close -s "$1"' \
  'close passes -f'

check "split-output-not-validated" bin/cc-pane \
  '"Created new pane: "*) printf '"'"'%s\n'"'"' "${out#Created new pane: }"; return "$RC_OK" ;;' \
  '"Created new pane: "*) printf '"'"'%s\n'"'"' "${out#Created new pane: }"; return "$RC_OK" ;; ""|*) printf '"'"'%s\n'"'"' "" ; return "$RC_OK" ;;' \
  'does NOT return an id is a FAILURE'

# ── the headless driver ───────────────────────────────────────────────────────────────────
check "zombie-reads-as-live (kill -0)" bin/cc-pane-headless \
  '  st="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d '"'"' '"'"')"
  [ -n "$st" ] || return 1
  case "$st" in Z*) return 1 ;; esac' \
  '  kill -0 "$pid" 2>/dev/null || return 1' \
  'ZOMBIE pid is NOT live'

check "hexdump-pads-the-minted-id" bin/cc-pane-headless \
  'id="hdl-$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d '"'"' \n'"'"')"' \
  'id="hdl-$(hexdump -n 8 -e '"'"'4/4 "%08x" 1 "\n"'"'"' /dev/urandom 2>/dev/null | head -1)"' \
  'minted id carries NO trailing whitespace'

check "unreadable-registry-reads-as-empty" bin/cc-pane-headless \
  '{ [ -r "$HOME_DIR" ] && [ -x "$HOME_DIR" ]; } || return "$RC_INDET"' \
  ':' \
  'UNREADABLE registry is INDETERMINATE'

check "close-never-escalates-to-KILL" bin/cc-pane-headless \
  '    is_live "$dir" && kill -KILL "$pid" 2>/dev/null' \
  '    :' \
  'reaps a process that ignores SIGTERM'

check "send-to-a-corpse-reports-success" bin/cc-pane-headless \
  '  is_live "$dir" || { printf '"'"'cc-pane-headless: id not live: %s\n'"'"' "$id" >&2; return "$RC_NO"; }' \
  '  :' \
  'send to a DEAD id is rc 1'

check "registry-is-world-readable" bin/cc-pane-headless \
  '  chmod 700 "$dir" 2>/dev/null' \
  '  chmod 755 "$dir" 2>/dev/null' \
  'registry is owner-only'

check "list-trusts-the-registry-not-the-OS" bin/cc-pane-headless \
    '    if is_live "$dir"; then
      printf '"'"'%s\n'"'"' "$id"' \
    '    if true; then
      printf '"'"'%s\n'"'"' "$id"' \
  'reaps dead rows on read'

# ── the child's identity (2026-08-10) ─────────────────────────────────────────────────────
# Three mutants, because the fix has two INDEPENDENT halves plus a wrong-value case, and a single
# mutant deleting the whole line would not tell us which half any test is actually holding.

# Half 1 gone: the agent is spawned with no identity of its own. CC_PANE_ID returns to being a key
# that 21 files read and nothing ever writes.
check "identity-never-exported" bin/cc-pane-headless \
  '( cd "$cwd" && export CC_PANE_ID="$id" && unset ITERM_SESSION_ID && exec "$@" ) \
      >"$dir/out.log" 2>&1 </dev/null &' \
  '( cd "$cwd" && unset ITERM_SESSION_ID && exec "$@" ) >"$dir/out.log" 2>&1 </dev/null &' \
  'EXPORTS CC_PANE_ID'

# Half 2 gone: the spawner's pane id leaks into the agent again, so every class-B scraper resolves
# a headless agent to the SPAWNER's pane — and teammate-auto-shutdown resolves a pane to CLOSE it.
check "spawner-pane-leaks-into-the-agent" bin/cc-pane-headless \
  '( cd "$cwd" && export CC_PANE_ID="$id" && unset ITERM_SESSION_ID && exec "$@" ) \
      >"$dir/out.log" 2>&1 </dev/null &' \
  '( cd "$cwd" && export CC_PANE_ID="$id" && exec "$@" ) >"$dir/out.log" 2>&1 </dev/null &' \
  'does NOT leak the SPAWNER'

# Exported, but NOT the child's own id. Pins that the test compares against the RETURNED id rather
# than merely asserting the variable is non-empty — non-emptiness is not provenance.
check "identity-exported-but-wrong-value" bin/cc-pane-headless \
  '( cd "$cwd" && export CC_PANE_ID="$id" && unset ITERM_SESSION_ID && exec "$@" ) \
      >"$dir/out.log" 2>&1 </dev/null &' \
  '( cd "$cwd" && export CC_PANE_ID="hdl-0000000000000000" && unset ITERM_SESSION_ID && exec "$@" ) >"$dir/out.log" 2>&1 </dev/null &' \
  'it is the child'"'"'s OWN id'

# NOT A MUTANT, and the reason is recorded in tests/cc-pane-headless.bats next to the test it
# retired: hoisting `export CC_PANE_ID="$id"` OUT of the subshell leaves the suite GREEN, because
# `spawn` is a SUBPROCESS of the suite and no implementation can mutate the parent's environment
# from there. The mutation is sound and the claim is real; it is simply not observable from
# outside the process, so a "caught" line here would have to come from a test that cannot fail.
# Left as a comment rather than deleted, so the next person does not re-derive it (memory:
# work-item-remedy-can-become-forbidden).

echo
printf 'RED-PROOF: %d caught · %d weak\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
