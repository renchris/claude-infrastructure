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

  # pane_proof now records the TRANSPORT it selected, which reads kitty_identity → in_kitty. Both
  # are one-liners; extracting them here keeps every `xf pane_proof` test self-contained. With
  # KITTY_WINDOW_ID unset and CC_TERM unset (pinned above), identity is deterministically iterm2.
  xf1 kitty_identity; xf1 in_kitty
}

# The listing shape the REAL it2 emits: `rich` box-drawing with the Session ID column
# ELLIPSIS-TRUNCATED to 80 columns when stdout is a pipe. Reproduced from a live capture on this
# box, 2026-08-05. The old fixture used bare integer ids — the KITTY transport's shape — which is
# why a suite that was green all along could not see that the iTerm2 path never worked.
rendered_table() { # $1… = full ids to render (truncated, exactly as rich does it)
  { printf '                                iTerm2 Sessions                                 \n'
    printf '┏━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━┓\n'
    printf '┃ Session ID            ┃ Name                  ┃ TTY   ┃\n'
    printf '┡━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━┩\n'
    local id; for id in "$@"; do printf '│ %s… │ Default (-zsh)        │ ttys0 │\n' "${id:0:20}"; done
    printf '└───────────────────────┴───────────────────────┴───────┘\n'
  } > "$PANE_LIST"
}

# The `--json` shape both transports implement (bin/it2-kitty:503 and the real it2's `--json`).
json_listing() { # $1… = full ids
  { printf '[\n'; local id first=1
    for id in "$@"; do
      [ "$first" = 1 ] || printf ',\n'; first=0
      printf '  {\n    "id": "%s",\n    "name": "Default (-zsh)",\n    "tty": "/dev/ttys016"\n  }' "$id"
    done
    printf '\n]\n'
  } > "$PANE_LIST"
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

# ONE-LINER extraction. in_kitty and kitty_identity have no `^}` of their own, so the range form
# above would swallow the next function whole. Guarded: an empty eval is a vacuous pass, which is
# the failure mode this suite exists to prevent.
xf1() { local l; l="$(sed -n '/^'"$1"'() {/p' "$HF")"; [ -n "$l" ] || return 1; eval "$l"; }

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

# ── THE PRODUCTION SHAPE (item 191d1fc4143c, 2026-08-05) ─────────────────────────────────────────
# Everything above this line runs against BARE ids — the kitty transport's shape, and the only one
# the old oracle could match. The iTerm2 transport renders a rich table with ellipsis-truncated
# UUIDs, so `grep -qxF` against a 36-char id could not match at ANY width: self-close and --recycle
# refused permanently on every iTerm2 pane while this suite stayed green. One probe, two transports,
# a fixture that only ever exercised the one that worked.

@test "pane_proof: the REAL --json listing → reachable (the shape the shipped path actually gets)" {
  # RED before the fix: the old probe whole-line-matched the raw bytes, and no line of a JSON
  # document equals a bare UUID. This is the assertion the incumbent fixture could not make.
  xf pane_proof
  json_listing D2AD56B8-7C0A-46E5-AA22-4C46ECF7ABCC 208ADD40-B603-4690-803A-B9BC61F2B785
  run pane_proof "$HOMEDIR/.claude/bin/it2" D2AD56B8-7C0A-46E5-AA22-4C46ECF7ABCC __selfclose
  [ "$status" -eq 0 ]
  [[ "$output" == *"→ pane-reachable: D2AD56B8-7C0A-46E5-AA22-4C46ECF7ABCC"* ]] || false
  [[ "$output" == *"shape=json"* ]]
}

@test "pane_proof: --json still refuses a pane that is genuinely absent (fail-closed intact)" {
  # The fix must not buy reachability by loosening the refusal — that refusal is CORRECT, and
  # typing /exit into an unverified pane could hit a sibling.
  xf pane_proof
  json_listing 208ADD40-B603-4690-803A-B9BC61F2B785
  run pane_proof "$HOMEDIR/.claude/bin/it2" D2AD56B8-7C0A-46E5-AA22-4C46ECF7ABCC __selfclose
  [ "$status" -eq 1 ]
  [[ "$output" == *"!! pane-UNREACHABLE:"* ]] || false
  [[ "$output" == *"is NOT among the 1 id(s)"* ]]
}

@test "pane_proof: a RENDERED table is named as a format artefact, not reported as an absent pane" {
  # The exact production failure, pinned. The pane IS in the listing; the format makes it unmatchable.
  # Still rc 1 (fail-closed is correct — an unparsed listing is not evidence of a reachable pane),
  # but the log must say WHY, because "no id matched" and "the output was never id-shaped" send an
  # investigator to different places. This one cost two misdiagnoses for lack of that sentence.
  xf pane_proof
  rendered_table D2AD56B8-7C0A-46E5-AA22-4C46ECF7ABCC 208ADD40-B603-4690-803A-B9BC61F2B785
  run pane_proof "$HOMEDIR/.claude/bin/it2" D2AD56B8-7C0A-46E5-AA22-4C46ECF7ABCC __selfclose
  [ "$status" -eq 1 ]
  [[ "$output" == *"shape=RENDERED-TABLE"* ]] || false
  [[ "$output" == *"ellipsis-truncated"* ]] || false
  [[ "$output" == *"artefact of the FORMAT"* ]]
}

@test "pane_proof: a COMPACT single-line array enumerates EVERY id, not just the last" {
  # Caught by a sibling suite's stub, which emits the array on one line. A greedy `.*"id"` matches
  # to the LAST occurrence ON THE LINE, so every pane but the final one read as absent — a parser
  # that agreed with the pretty-printed fixture it was written against and with nothing else.
  printf '[{"id": "PREDSID", "tty": "/dev/ttys999"}, {"id": "SUCC-B", "tty": "/dev/ttys998"}]\n' > "$PANE_LIST"
  xf pane_proof
  run pane_proof "$HOMEDIR/.claude/bin/it2" PREDSID __selfclose
  [ "$status" -eq 0 ]
  [[ "$output" == *"ids=2"* ]] || false
  [[ "$output" == *"→ pane-reachable: PREDSID"* ]]
}

@test "pane_proof: the probe ASKS for --json — the machine format is the contract, not a fallback" {
  xf pane_proof
  json_listing 218
  run pane_proof "$HOMEDIR/.claude/bin/it2" 218 __selfclose
  [ "$status" -eq 0 ]
  run grep -qxF 'session list --json' "$IT2_CALLS"
  [ "$status" -eq 0 ]
}

@test "pane_proof: logs the TRANSPORT it selected, including the verdict handed down to it" {
  # The watcher is an orphan by construction and cannot re-derive its own terminal. Which backend
  # it selected — and whether the foreground's pinned verdict actually ARRIVED — was unobservable,
  # so a failed route and a slow one produced identical evidence: none.
  xf pane_proof
  json_listing 218
  CC_TERM=iterm2 run pane_proof "$HOMEDIR/.claude/bin/it2" 218 __selfclose
  [ "$status" -eq 0 ]
  [[ "$output" == *"→ pane-probe: __selfclose pane=218"* ]] || false
  [[ "$output" == *"CC_TERM=iterm2"* ]] || false
  [[ "$output" == *"identity=iterm2"* ]] || false
  [[ "$output" == *"listing rc=0"* ]]
}

@test "pane_proof: the probe's own stderr is RENDERED, never discarded" {
  # `2>/dev/null` on the listing is what made a failed transport indistinguishable from a slow one.
  # A diagnostic that throws away the diagnosis leaves an operator staring at a healthy-looking
  # terminal and a pane that will not close (bin/it2-kitty's own lesson, :517).
  xf pane_proof
  cat > "$HOMEDIR/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$IT2_CALLS"
echo "it2: There was a problem connecting to iTerm2" >&2
exit 3
SH
  chmod +x "$HOMEDIR/.claude/bin/it2"
  run pane_proof "$HOMEDIR/.claude/bin/it2" 218 __selfclose
  [ "$status" -eq 1 ]
  [[ "$output" == *"problem connecting to iTerm2"* ]] || false
  [[ "$output" == *"listing rc=3"* ]]
}

# ── kitty_identity — stage 1: identity is not the divert predicate ───────────────────────────────

@test "kitty_identity: an ancestry-resolved verdict governs in BOTH directions; unpinned is in_kitty" {
  # A stale inherited KITTY_WINDOW_ID made a genuine iTerm2 pane resolve its tty through kitty's
  # NUMERIC id space, which cannot hold a UUID — so the pane read as absent (`tty=none` on
  # self-close, an outright abort on --recycle) while it sat right there in the it2 listing.
  xf1 kitty_identity; xf1 in_kitty

  export KITTY_WINDOW_ID=2; unset IT2_WRAPPER_NO_KITTY   # the polluted-env case, measured on this box
  CC_TERM=iterm2 run kitty_identity; [ "$status" -ne 0 ] # ancestry says iTerm2 → iTerm2 wins
  CC_TERM=kitty  run kitty_identity; [ "$status" -eq 0 ] # and the converse, so it is a verdict not a veto

  unset CC_TERM                                          # unpinned ⇒ byte-identical to in_kitty
  run kitty_identity; [ "$status" -eq 0 ]
  unset KITTY_WINDOW_ID
  run kitty_identity; [ "$status" -ne 0 ]
}

@test "pane_proof: no executable it2 shim → rc 1, and says so rather than guessing" {
  xf pane_proof
  run pane_proof "$BATS_TEST_TMPDIR/nope/it2" 218 __recycle
  [ "$status" -eq 1 ]
  [[ "$output" == *"no executable it2 shim"* ]]
}

# ── await_pane_proof ─────────────────────────────────────────────────────────────────────────────

@test "await_pane_proof: affirmative → 0; negative → 1; SILENCE → 2, a distinct outcome" {
  xf await_pane_proof
  local log="$BATS_TEST_TMPDIR/w.log"

  printf '→ armed: x\n→ pane-reachable: 218 enumerated\n' > "$log"
  run await_pane_proof "$log"; [ "$status" -eq 0 ]

  printf '→ armed: x\n!! pane-UNREACHABLE: 218 nope\n' > "$log"
  run await_pane_proof "$log"; [ "$status" -eq 1 ]

  # Silence is NOT consent — it still refuses. But it is no longer the SAME refusal: "the probe
  # answered no" and "the probe has not answered" have the same disposition and different fixes,
  # and folding them into one rc is what made item 191d1fc4143c unreadable through two
  # investigations. rc 2 is the stall; every non-zero still means DO NOT KILL.
  printf '→ armed: x\n' > "$log"
  run env HANDOFF_PANE_PROOF_TICKS=3 bash -c 'set -euo pipefail
    '"$(sed -n '/^await_pane_proof() {/,/^}/p' "$HF")"'
    await_pane_proof "$1"' _ "$log"
  [ "$status" -eq 2 ]
}

@test "await_pane_proof: the window is DERIVED from the watcher's own bound, never guessed" {
  # THE BOUND MUST FIT WHAT IT BOUNDS. The old window was a fixed 60 ticks = 12.0s while the
  # watcher's probe is bounded at HF_TIMEOUT_S plus timeout(1)'s -k 3 kill grace = 13s worst case:
  # an honest-but-slow probe was GUARANTEED to be read as failure, its verdict landing in the log
  # about a second after the foreground gave up. A bound shorter than its subject can only convict.
  xf await_pane_proof
  local log="$BATS_TEST_TMPDIR/slow.log"; printf '→ armed: x\n' > "$log"

  # Drive the derivation with a large bound and assert the window covers bound + kill-grace, by
  # measuring how long the silent case actually waits. 0.2s per tick.
  local t0 t1
  t0="$(date +%s)"
  HF_TIMEOUT_S=10 run await_pane_proof "$log"
  t1="$(date +%s)"
  [ "$status" -eq 2 ]
  # 10 + 3 (kill grace) = 13s is the floor the watcher can legitimately take.
  [ "$(( t1 - t0 ))" -ge 13 ]
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

  # /dev/ttys999 has no processes. Since the fail-safe pane probe landed (2026-08-06) that reads
  # `unknown`, NOT "shell-only" — the watcher waits rather than type onto a pane whose state it
  # cannot positively confirm — so this run no longer races past the exit-wait and the `timeout`
  # is what ends it. That does not weaken the assertion: `pane-reachable` is emitted by the probe
  # under test BEFORE the wait loop is entered, and this file's subject is the probe, not the wait.
  # Bounded: we assert on the LOG, not on the watcher running to completion.
  run env HOME="$HOMEDIR" timeout 8 bash "$HF" __recycle 218 /dev/ttys999 "$cmdfile"
  # ORDER IS LOAD-BEARING, and it was wrong first time round. Written with the affirmative FIRST and
  # the negative last, this test passed against the PRE-FIX subject — which emits neither line — so
  # the "positive control" could not fail and proved nothing. The decisive assertion goes LAST.
  [[ "$output" != *"pane-UNREACHABLE"* ]] || false
  [[ "$output" == *"→ pane-reachable: 218"* ]]
}

@test "__selfclose watcher: logs the transport, and says UNPINNED when no verdict was handed down" {
  # The item's literal spec. pin_term_verdict_for_watcher resolves the terminal in the foreground —
  # where the ancestry walk is valid — and hands it down through the environment; whether it
  # ARRIVED was invisible right up to the moment the watcher's pane writes went to the wrong
  # backend. cc-in-kitty's exit 2 is deliberately left unpinned (fail-closed), which is correct and
  # must therefore be LEGIBLE rather than inferred from a silence.
  json_listing 218
  unset CC_TERM
  run env HOME="$HOMEDIR" timeout 8 bash "$HF" __selfclose 218 /dev/ttys999
  [[ "$output" == *"→ transport: __selfclose CC_TERM=UNPINNED"* ]] || false
  [[ "$output" == *"identity="* ]] || false

  run env HOME="$HOMEDIR" CC_TERM=iterm2 timeout 8 bash "$HF" __selfclose 218 /dev/ttys999
  [[ "$output" == *"→ transport: __selfclose CC_TERM=iterm2"* ]]
}

@test "__selfclose watcher: a reachable pane is CLOSED — the positive control for the whole path" {
  # "A pane that is closable must emit pane-reachable and actually close" (item 191d1fc4143c).
  # Without this, every refusal assertion above is satisfied by a probe that always refuses — which
  # is exactly the shipped defect: a permanent, self-consistent, wrong NO.
  json_listing 218 219
  run env HOME="$HOMEDIR" timeout 8 bash "$HF" __selfclose 218 /dev/ttys999
  [ "$status" -eq 0 ]
  [[ "$output" == *"→ pane-reachable: 218"* ]] || false
  run grep -qxF 'session close -f -s 218' "$IT2_CALLS"
  [ "$status" -eq 0 ]
}
