#!/usr/bin/env bats
# Regression guard for the PANE-REACHABILITY handshake and the watcher's terminal-verdict pin
# (2026-08-02).
#
# THE INCIDENT. Session 625efe2a (desk, account next3, kitty pane 218) fired
# `handoff-fire.sh --recycle`. handoff-fire composed the correct relaunch on the correct account
# with the correct payload, armed its detached watcher, wrote the teardown marker, typed /exit —
# and the watcher then failed EVERY write into pane 218 ("it2 relaunch write failed twice"). The
# predecessor was already dead. The operator watched a pane vanish with the work stranded and no
# successor. It was not a one-off: 4 of 4 recycles since the kitty migration (panes 176, 2, 173,
# 218) end with the identical two lines in their watcher logs, and `~/.claude/watchdog/teardown/`
# holds 63 `recycle` records against 14 `successor` records — the last successor dated
# 2026-07-30T01:28Z, i.e. the day before the machine moved to kitty.
#
# THE CAUSE. detach() spawns the watcher with start_new_session=True, so it reparents to launchd BY
# CONSTRUCTION. bin/cc-in-kitty discriminates on ANCESTRY, not on the KITTY_* env vars — correctly,
# because those inherit transitively into iTerm2 — but an orphan has no kitty ancestor, so for the
# watcher the walk can only ever answer "not kitty". Every pane write was routed to the real iTerm2
# CLI and died against a kitty pane id. The watcher was not misconfigured; it was structurally
# unable to re-derive a fact the foreground could still see.
#
# THE TWO GUARDS PINNED HERE.
#   1. pin_term_verdict_for_watcher — resolve the verdict in the FOREGROUND, where the ancestry walk
#      is valid, and hand it down through cc-in-kitty's own CC_TERM seam. Definitive verdicts only.
#   2. pane_proof / await_pane_proof — the arm handshake used to prove only that the watcher could
#      write its own LOG. It now must also prove it can reach the PANE, over the real transport,
#      BEFORE anything is killed. Kill-first-discover-second is the class; this inverts the order.
#
# Technique mirrors tests/handoff-selfclose.bats: PATH shims, a fake HOME with a recording it2 stub,
# sed-extracted functions for the units, and `bash "$HF" __recycle …` to run the watcher body in the
# foreground (no detach, no real panes).

setup() {
  # PIN THE TERMINAL. handoff-fire.sh's primitives branch on KITTY_WINDOW_ID, so run from inside a
  # kitty pane an unpinned suite silently becomes a function of the developer's terminal. Same pin,
  # same reason, as tests/handoff-selfclose.bats and tests/it2-wrapper.bats. This file drives the
  # terminal decision EXPLICITLY through stubs, so an inherited one would be pure noise.
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  # CC_TERM is the seam under test — a value inherited from the developer's shell would make
  # pin_term_verdict_for_watcher's "never overwrite" branch fire in every test.
  unset CC_TERM
  # PIN THE LOAD GATES (M11). handoff-fire's capacity_gate() refuses a net-new fire above 2.0/core
  # and headroom_gate() refuses on its own ceiling; this box lives above both, so an unpinned
  # fire-executing suite goes red as a function of what ELSE the operator is running rather than of
  # its subject. tests/handoff-fire-capacity-gate.bats test 25 is the ratchet that derives this
  # requirement over every fire-executing suite — it has been RED on trunk since this file landed
  # (acbaba85), which blocks every lander, not just the one who notices.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off

  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"

  # hf_bounded is the script's timeout(1) wrapper; extracted functions do not get it in scope. A
  # passthrough keeps the extracted behaviour byte-identical. Its own semantics are covered by
  # tests/handoff-fire-it2-bound.bats against the real definition.
  hf_bounded() { "$@"; }

  # HERMETIC $HOME. The subject resolves both the it2 shim and cc-in-kitty as "$HOME/.claude/bin/…",
  # so an unfixtured HOME would run these tests against the operator's LIVE ~/ — reading their real
  # terminal and their real panes, which is exactly the ambient dependency this file exists to
  # remove from the subject. Exported (not just passed per-invocation) so the extracted-function
  # tests get it too. scripts/test-hermeticity-lint.sh blocks the land without this.
  export HOME="$BATS_TEST_TMPDIR/home"
  HOMEDIR="$HOME"; mkdir -p "$HOMEDIR/.claude/bin"
  # handoff-fire's capacity_gate() refuses a net-new fire above 2.0 load/core and this box lives
  # well above that, so an unpinned suite goes red by MACHINE LOAD rather than by its subject.
  export CC_FIRE_CAPACITY_GATE=off
  export IT2_CALLS="$BATS_TEST_TMPDIR/it2-calls"; : > "$IT2_CALLS"
  export PANE_LIST="$BATS_TEST_TMPDIR/pane-list";  : > "$PANE_LIST"

  # Recording it2 stub. `session list` prints whatever $PANE_LIST holds — that file IS the
  # reachability fixture. Every invocation is appended to $IT2_CALLS so a test can assert that a
  # WRITE never happened, which is the property that actually matters: the guard's job is to stop
  # the kill, not merely to log a complaint.
  cat > "$HOMEDIR/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$IT2_CALLS"
if [ "${1:-}" = session ] && [ "${2:-}" = list ]; then cat "$PANE_LIST"; exit 0; fi
exit 0
SH
  chmod +x "$HOMEDIR/.claude/bin/it2"
}

# cc-in-kitty stub with a caller-chosen exit code. Absent by default so tests opt in.
mk_cik() { # $1=exit-code
  cat > "$HOMEDIR/.claude/bin/cc-in-kitty" <<SH
#!/usr/bin/env bash
exit $1
SH
  chmod +x "$HOMEDIR/.claude/bin/cc-in-kitty"
}

# Extract ONE function from the subject. The address pair is assembled in SINGLE quotes: the `{`
# and `}` are sed syntax, and interpolating them inside a double-quoted `$(sed …)` nested in this
# function's own braces truncates the script to `/^name() //p` — sed then rejects it and the test
# fails with a bare 127 that reads like a missing function rather than a mangled pattern.
xf() {
  local pat; pat='/^'"$1"'() {/,/^}/p'
  eval "$(sed -n "$pat" "$HF")"
}

# ── pane_proof ───────────────────────────────────────────────────────────────────────────────────

@test "pane_proof: pane enumerated by the real transport → rc 0 and an affirmative log line" {
  xf pane_proof
  printf '%s\n' 218 219 > "$PANE_LIST"
  run pane_proof "$HOMEDIR/.claude/bin/it2" 218 __recycle
  [ "$status" -eq 0 ]
  [[ "$output" == *"→ pane-reachable: 218"* ]]
}

@test "pane_proof: pane ABSENT from session list → rc 1 and names pane, shim and CC_TERM" {
  xf pane_proof
  printf '%s\n' 219 220 > "$PANE_LIST"          # the 2026-08-02 shape: kitty pane, iTerm2 enumeration
  run pane_proof "$HOMEDIR/.claude/bin/it2" 218 __recycle
  [ "$status" -eq 1 ]
  [[ "$output" == *"!! pane-UNREACHABLE:"* ]] || false
  [[ "$output" == *"218"* ]] || false
  [[ "$output" == *"CC_TERM=unset"* ]]
}

@test "pane_proof: substring match must not count as reachable" {
  # `grep -qxF`, not `grep -qF`. Pane 18 and pane 218 are different panes, and kitty ids are bare
  # integers — a substring match would declare an unreachable pane healthy and re-open the incident.
  xf pane_proof
  printf '%s\n' 218 > "$PANE_LIST"
  run pane_proof "$HOMEDIR/.claude/bin/it2" 18 __recycle
  [ "$status" -eq 1 ]
  [[ "$output" == *"!! pane-UNREACHABLE:"* ]]
}

@test "pane_proof: no executable it2 shim → rc 1, and says so rather than guessing" {
  xf pane_proof
  run pane_proof "$BATS_TEST_TMPDIR/nope/it2" 218 __recycle
  [ "$status" -eq 1 ]
  [[ "$output" == *"no executable it2 shim"* ]]
}

# ── await_pane_proof ─────────────────────────────────────────────────────────────────────────────

@test "await_pane_proof: affirmative line → 0; negative line → 1; neither → 1" {
  xf await_pane_proof
  local log="$BATS_TEST_TMPDIR/w.log"

  printf '→ armed: x\n→ pane-reachable: 218 enumerated\n' > "$log"
  run await_pane_proof "$log"; [ "$status" -eq 0 ]

  printf '→ armed: x\n!! pane-UNREACHABLE: 218 nope\n' > "$log"
  run await_pane_proof "$log"; [ "$status" -eq 1 ]

  # Silence is NOT consent. A watcher that armed and then said nothing about the pane must read as
  # unreachable — the whole defect was an affirmative inferred from an absent signal.
  printf '→ armed: x\n' > "$log"
  run await_pane_proof "$log"; [ "$status" -eq 1 ]
}

# ── pin_term_verdict_for_watcher ─────────────────────────────────────────────────────────────────

@test "pin_term_verdict_for_watcher: definitive verdicts are pinned in BOTH directions" {
  xf pin_term_verdict_for_watcher
  HOME="$HOMEDIR"

  mk_cik 0; unset CC_TERM; pin_term_verdict_for_watcher; [ "$CC_TERM" = kitty ]
  mk_cik 1; unset CC_TERM; pin_term_verdict_for_watcher; [ "$CC_TERM" = iterm2 ]
}

@test "pin_term_verdict_for_watcher: UNVERIFIABLE (exit 2) pins nothing" {
  # cc-in-kitty's exit 2 means KITTY_* is present but the lineage could not be checked. Pinning a
  # guess there would hand the watcher a fabricated verdict it cannot audit; leaving it unset keeps
  # today's fail-closed behaviour, which is the honest weaker answer.
  xf pin_term_verdict_for_watcher
  HOME="$HOMEDIR"
  mk_cik 2; unset CC_TERM; pin_term_verdict_for_watcher
  [ -z "${CC_TERM:-}" ]
}

@test "pin_term_verdict_for_watcher: an explicit override is never overwritten, and a missing binary is not fatal" {
  xf pin_term_verdict_for_watcher
  HOME="$HOMEDIR"

  mk_cik 0; CC_TERM=iterm2; pin_term_verdict_for_watcher
  [ "$CC_TERM" = iterm2 ]                       # operator/test intent outranks the probe

  rm -f "$HOMEDIR/.claude/bin/cc-in-kitty"; unset CC_TERM
  run pin_term_verdict_for_watcher
  [ "$status" -eq 0 ]                           # a side-car must never fail wider than itself
}

# ── the guard end-to-end: the watcher refuses to proceed, and writes nothing ──────────────────────

@test "__recycle watcher: unreachable pane → exits 1 BEFORE any write, and logs why" {
  # THE CONTROL FOR THE WHOLE FILE. Pre-fix, this watcher armed, waited for claude to exit, and
  # only then discovered it could not type — by which point the foreground had already killed the
  # session. Post-fix it must fail at the probe, and `it2 session send` must never appear.
  printf '%s\n' 219 > "$PANE_LIST"              # pane 218 is NOT enumerated
  local cmdfile="$BATS_TEST_TMPDIR/cmd.sh"; printf 'echo relaunch\n' > "$cmdfile"

  run env HOME="$HOMEDIR" bash "$HF" __recycle 218 /dev/ttys999 "$cmdfile"
  [ "$status" -eq 1 ]
  [[ "$output" == *"→ armed: __recycle"* ]] || false # it DID arm — the log write was never the problem
  [[ "$output" == *"!! pane-UNREACHABLE:"* ]] || false

  run grep -c 'session send' "$IT2_CALLS"
  [ "$output" = "0" ]
}

@test "__recycle watcher: reachable pane → the probe passes and does not block the happy path" {
  # Positive control. Without it, every assertion above is satisfied by a probe that simply always
  # refuses — which would convert a stranded pane into a recycle that never fires at all.
  printf '%s\n' 218 219 > "$PANE_LIST"
  local cmdfile="$BATS_TEST_TMPDIR/cmd.sh"; printf 'echo relaunch\n' > "$cmdfile"
  local log="$BATS_TEST_TMPDIR/happy.log"

  # /dev/ttys999 has no processes, so cc_alive is false and the watcher moves straight past the
  # exit-wait. Bounded: we assert on the LOG, not on the watcher running to completion.
  run env HOME="$HOMEDIR" timeout 8 bash "$HF" __recycle 218 /dev/ttys999 "$cmdfile"
  # ORDER IS LOAD-BEARING, and it was wrong first time round. Written with the affirmative FIRST and
  # the negative last, this test passed against the PRE-FIX subject — which emits neither line — so
  # the "positive control" could not fail and proved nothing. The decisive assertion goes LAST.
  [[ "$output" != *"pane-UNREACHABLE"* ]] || false
  [[ "$output" == *"→ pane-reachable: 218"* ]]
}
