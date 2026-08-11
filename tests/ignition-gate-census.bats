#!/usr/bin/env bats
# cc-ignition-gate — TERM 2, the burst census, and the reason it had never once fired.
#
# WHAT THIS SUITE HAS TO PROVE:
#   · TERM 2 COULD NOT COUNT. The gate read `ps -Awwo pid=,etime=,comm=,args=` and tested
#     `basename(comm) == "node"`. `ps` widens only its LAST column, so a `comm=` requested BEFORE
#     `args=` comes back truncated to a FIXED 16 characters — measured on this box 2026-08-11:
#     `/Users/chrisren/`, `/Library/Applica`, `endpointsecurity`, all exactly 16. No real node
#     install has a path that short, so the test could match nothing but a process whose comm was
#     literally the 4-character string `node`. Live control in this suite: the pre-fix gate reads
#     node_n=0 over a fixture of four unmistakable node processes.
#     The old comment beside that line rationalised the miss as deliberate under-inclusiveness for
#     "a comm containing a space". The space was never the mechanism; the column width was. On this
#     box node lives at `…/Library/Application Support/fnm/…/bin/node` and loses BOTH ways.
#   · WHICH TERM THIS KILLS. TERM 2 is the ONLY term that can see the storm shape W11 identified:
#     an old `next-server` re-storming on mass invalidation, whose etime is hours, so TERM 1's
#     settle window can never match it — "only the process count tells". That count was 0.
#   · TERM 1 STILL WORKS. Dropping `comm=` reindexed the args extraction from three leading fields
#     to two. A silently wrong strip would break the incumbent term and the claude argv[0]
#     exclusion, and both fail OPEN, so neither would announce itself.
#   · FAIL-OPEN SURVIVES A SECOND READ. The name table is a second `ps`; unreadable must still ADMIT.
#
# PROOF DISCIPLINE (this repo's bar):
#   · $HOME is FIXTURED into $BATS_TEST_TMPDIR — the gate appends telemetry to
#     ~/.claude/logs/ignition-gate.jsonl and an unfixtured run would pollute live telemetry.
#   · NO real ps: both reads are pinned through CC_IGNITION_PS_FILE and CC_IGNITION_EXE_FILE.
#   · Non-final `[ ]` is errexit-EXEMPT under bats and therefore DEAD as an assertion — every one
#     below carries `|| false`.
#   · Every ABSENCE assertion has a POSITIVE CONTROL beside it.
#   · The pre-fix control is the REAL artifact replayed from `git show origin/main:…`, never a
#     mutant of this file (memory: control-must-replay-the-real-artifact).
#
# RED-PROOF: against a tree without bin/cc-ignition-gate, setup's `[ -x "$G" ]` fails and every case
# fails at setup rather than passing vacuously.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  G="$REPO/bin/cc-ignition-gate"
  D="$BATS_TEST_TMPDIR"
  [ -x "$G" ] || false

  export HOME="$D/home"; mkdir -p "$HOME/.claude/logs"
  export CC_IGNITION_LOG="$D/ign.jsonl"
  # This gate is not terminal-aware, but the suite runs it as a real process: pin the terminal so a
  # kitty-hosted run cannot diverge from an iTerm2 one (this repo's recurring latent-unhermetic
  # class — tests/capacity-alarm-segments.bats records it springing for real).
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  # WAIT_S=0 ⇒ check-and-admit, never sleep. A suite that could sleep 90 s per case is a suite
  # nobody runs.
  export CC_IGNITION_WAIT_S=0

  # The pre-fix artifact, for the controls.
  PRE="$D/pre-gate"
  git -C "$REPO" show origin/main:bin/cc-ignition-gate > "$PRE" 2>/dev/null || true
  chmod +x "$PRE" 2>/dev/null || true

  FNM='/Users/x/Library/Application Support/fnm/node-versions/v22.21.1/installation/bin/node'
}

# ── fixtures ──────────────────────────────────────────────────────────────────────────────────────
# `ps` output is written out literally rather than generated, because the whole defect lives in the
# exact column geometry — a fixture that "looks like ps" but pads differently would prove nothing.

# POST-FIX shape: `pid etime args…` (args LAST and therefore complete) + a separate name table.
psrows() { printf '%s\n' "$1" > "$D/ps"; export CC_IGNITION_PS_FILE="$D/ps"; }
exerows() { printf '%s\n' "$1" > "$D/exe"; export CC_IGNITION_EXE_FILE="$D/exe"; }

# PRE-FIX shape: `pid etime comm args…`, comm TRUNCATED TO 16 AND PADDED, exactly as ps emits it.
prerows() { printf '%s\n' "$1" > "$D/preps"; }

gate() { run env CC_IGNITION_PS_FILE="$D/ps" CC_IGNITION_EXE_FILE="$D/exe" \
             CC_IGNITION_LOG="$CC_IGNITION_LOG" CC_IGNITION_WAIT_S=0 \
             CC_IGNITION_BURST_N="${BURST_N:-100}" CC_IGNITION_SETTLE_S="${SETTLE_S:-90}" \
             HOME="$HOME" bash "$G" --check --class t; }

pregate() { run env CC_IGNITION_PS_FILE="$D/preps" \
                CC_IGNITION_LOG="$D/pre.jsonl" CC_IGNITION_WAIT_S=0 \
                CC_IGNITION_BURST_N="${BURST_N:-100}" CC_IGNITION_SETTLE_S="${SETTLE_S:-90}" \
                HOME="$HOME" bash "$PRE" --check --class t; }

reason() { # last logged reason, from the telemetry row rather than stdout — stdout is silent on
           # the common path by contract, so the row is the only place a verdict always lands.
  sed -n '$s/.*"reason":"\([^"]*\)".*/\1/p' "${1:-$CC_IGNITION_LOG}"
}

# ══ 1. TERM 2 — the census that could not count ═══════════════════════════════════════════════════

@test "THE DEFECT: the pre-fix gate reads node_n=0 over four unmistakable node processes" {
  # Real geometry: comm truncated to 16 and padded, then the full argv. The four basenames the
  # pre-fix code computes are `/Users/x/Library`→`Library`, `/opt/homebrew/bi`→`bi`, twice each.
  prerows "$(printf '%s\n%s\n%s\n%s' \
    "  801    05:00 /Users/x/Library $FNM /w/a/w1.js" \
    "  802    05:00 /Users/x/Library $FNM /w/a/w2.js" \
    "  803    05:00 /opt/homebrew/bi /opt/homebrew/bin/node /w/a/w3.js" \
    "  804    05:00 /opt/homebrew/bi /opt/homebrew/bin/node /w/a/w4.js")"
  BURST_N=1 pregate
  [ "$status" = "0" ] || false                       # fail-open: every path admits
  [ "$(reason "$D/pre.jsonl")" = "clear node_n=0" ] || false
}

@test "THE FIX: the same four processes are COUNTED, and the burst term becomes reachable" {
  psrows "$(printf '%s\n%s\n%s\n%s' \
    "  801    05:00 $FNM /w/a/w1.js" \
    "  802    05:00 $FNM /w/a/w2.js" \
    "  803    05:00 /opt/homebrew/bin/node /w/a/w3.js" \
    "  804    05:00 /opt/homebrew/bin/node /w/a/w4.js")"
  exerows "$(printf '801 node\n802 node\n803 node\n804 node')"
  BURST_N=1 gate
  [ "$status" = "0" ] || false
  [ "$(reason)" = "burst node_n=4 limit=1" ] || false
  # POSITIVE CONTROL ON THE THRESHOLD — the same count under a limit it does not exceed is CLEAR,
  # so the line above is the threshold firing and not the gate reporting busy unconditionally.
  BURST_N=9 gate
  [ "$(reason)" = "clear node_n=4" ] || false
}

@test "a process the name table does not name is not counted — unidentifiable is not evidence" {
  psrows "$(printf '%s\n%s' "  801    05:00 $FNM /w/a/w1.js" "  802    05:00 $FNM /w/a/w2.js")"
  exerows '801 node'
  BURST_N=1 gate
  [ "$(reason)" = "clear node_n=1" ] || false
}

@test "a basename that merely STARTS with node is not counted — the test is exact, as it always was" {
  psrows "  801    05:00 /w/a/node_modules/.bin/nodemon /w/a/w.js"
  exerows '801 nodemon'
  BURST_N=0 gate
  [ "$(reason)" = "clear node_n=0" ] || false
  exerows '801 node'                                  # POSITIVE CONTROL
  BURST_N=0 gate
  [ "$(reason)" = "burst node_n=1 limit=0" ] || false
}

# ══ 2. TERM 1 — the field reindex must not have broken the incumbent ══════════════════════════════

@test "TERM 1 still matches an ignition-shaped argv after comm left the read" {
  # args is now fields 3..NF rather than 4..NF. A wrong strip leaves a leading `05:00` on the string
  # the ^-anchored ERE matches, which fails OPEN and would therefore never announce itself.
  psrows "  901    00:10 /opt/homebrew/bin/node /w/a/node_modules/.bin/next dev"
  exerows '901 node'
  gate
  [ "$status" = "0" ] || false
  [ "$(reason)" = "incumbent pid=901 age_s=10" ] || false
}

@test "TERM 1 respects the settle window: a next dev up for an hour is not an incumbent" {
  psrows "  902 01:00:00 /opt/homebrew/bin/node /w/a/node_modules/.bin/next dev"
  exerows '902 node'
  gate
  # node_n is 1 — it IS a node process; the point is that no INCUMBENT is named, so TERM 1 is what
  # went quiet. A `clear node_n=0` here would mean the name table had silently stopped arriving.
  [ "$(reason)" = "clear node_n=1" ] || false
  # POSITIVE CONTROL — the identical row inside the window IS an incumbent.
  psrows "  902    00:10 /opt/homebrew/bin/node /w/a/node_modules/.bin/next dev"
  gate
  [ "$(reason)" = "incumbent pid=902 age_s=10" ] || false
}

@test "the claude argv[0] exclusion still holds — this fleet is not a cold compile" {
  # Every worktree of this repo has `claude` in its PATH, and a session's argv carries its whole
  # brief; an unanchored match would deadlock the fleet against its own vocabulary.
  psrows "  903    00:05 /Users/x/.claude/local/node_modules/.bin/claude --resume next dev"
  exerows '903 claude'
  gate
  [ "$(reason)" = "clear node_n=0" ] || false
}

# ══ 3. FAIL-OPEN — the second read must not be able to strand a command ═══════════════════════════

@test "an unreadable name table ADMITS: node_n=0, verdict clear, exit 0" {
  psrows "$(printf '%s\n%s' "  801    05:00 $FNM /w/a/w1.js" "  802    05:00 $FNM /w/a/w2.js")"
  export CC_IGNITION_EXE_FILE="$D/does-not-exist"
  run env CC_IGNITION_PS_FILE="$D/ps" CC_IGNITION_EXE_FILE="$D/does-not-exist" \
      CC_IGNITION_LOG="$CC_IGNITION_LOG" CC_IGNITION_WAIT_S=0 CC_IGNITION_BURST_N=1 \
      HOME="$HOME" bash "$G" --check --class t
  [ "$status" = "0" ] || false
  [ "$(reason)" = "clear node_n=0" ] || false
  # POSITIVE CONTROL — with the table readable the SAME rows do trip the limit, so the admit above
  # is the fail-open path and not a gate that never trips.
  exerows "$(printf '801 node\n802 node')"
  BURST_N=1 gate
  [ "$(reason)" = "burst node_n=2 limit=1" ] || false
}

@test "the kill switch still precedes both reads" {
  psrows "$(printf '%s' "  801    05:00 $FNM /w/a/w1.js")"
  exerows '801 node'
  run env CC_IGNITION_GATE=off CC_IGNITION_PS_FILE="$D/ps" CC_IGNITION_EXE_FILE="$D/exe" \
      CC_IGNITION_LOG="$D/killed.jsonl" HOME="$HOME" bash "$G" --check --class t
  [ "$status" = "0" ] || false
  [ ! -s "$D/killed.jsonl" ] || false
}
