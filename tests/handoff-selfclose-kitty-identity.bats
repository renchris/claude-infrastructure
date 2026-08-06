#!/usr/bin/env bats
# handoff-fire.sh self-close — SELF-IDENTITY on a kitty pane (2026-08-05, item 4e074b938da7).
#
# THE DEFECT. self-close's identity default read $ITERM_SESSION_ID and nothing else, so a fired peer
# hosted in kitty exited 1 at the very first gate — "!! self-close needs $ITERM_SESSION_ID or
# --session-id" — having done nothing. Measured from kitty window 28 (KITTY_PID=567, cc-in-kitty:
# "kitty[567] is an ancestor", ITERM_SESSION_ID unset). Such a session cannot obey its own standing
# ON COMPLETION — SELF-RETIRE instruction, and its pane plus worktree leak until an operator reaps
# them.
#
# WHY IT IS A DIFFERENT QUESTION FROM b0b4ec40d63a, whose fix does not reach it. That item fixed the
# FIRE path, which asks "which terminal do I DRIVE" — answerable from outside the process, by
# probing the box for a control socket that answers. self-close asks "WHICH WINDOW AM I", and no
# socket probe can answer that: `kitty @ ls`'s is_focused is UI focus, not identity (memory
# kitty-split-anchors-active-tab-not-caller), so a peer in a background window would resolve to
# whichever window the operator was looking at. Only $KITTY_WINDOW_ID knows — behind the ANCESTRY
# verdict, because the bare var inherits transitively and made the divert fire inside genuine iTerm2
# panes on 2026-07-31.
#
# WHAT IS PINNED HERE, and why each would otherwise be "simplified" away:
#   1. THE FIX ITSELF — an ancestry-confirmed kitty pane resolves its own id, and the refusal that
#      used to be terminal now moves to the NEXT gate NAMING that id.
#   2. PRECEDENCE, NOT "WHICHEVER IS SET". In a genuine kitty pane an $ITERM_SESSION_ID is either
#      SYNTHETIC (kitty-setup.sh:255 exports w0t0p0:$KITTY_WINDOW_ID unconditionally — same value,
#      which is why the defect is intermittent rather than total) or STALE from an iTerm2 ancestor
#      (kitty-setup.sh:437). KITTY_WINDOW_ID must win, or the stale case feeds an iTerm2 UUID into
#      kitty's numeric id space and every downstream lookup misses.
#   3. THE DIRECTION THAT MUST NOT FLIP. A genuine iTerm2 pane carrying a POLLUTED KITTY_WINDOW_ID
#      keeps its iTerm2 UUID. Getting this backwards is the 2026-07-31 outage.
#   4. THE GATE STILL REFUSES. Two negative controls — ancestry says not-kitty, and no terminal env
#      at all — must still exit 1. Without them every assertion here is satisfiable by a gate that
#      simply stopped refusing, which is a strictly worse bug than the one being fixed.
#   5. UNVERIFIABLE STAYS FAIL-CLOSED. cc-in-kitty exit 2 pins nothing, so the resolution degrades
#      to exactly its pre-fix behaviour rather than inheriting a guess.
#   6. ORDERING. pin_term_verdict_for_watcher must run BEFORE the identity default, because
#      self_pane_id CONSUMES its verdict. Test 1 covers this behaviourally (CC_TERM is UNSET in the
#      integration cases and the verdict comes from the stubbed cc-in-kitty), so a re-order that put
#      the pin back below the default goes red here rather than silently reverting the fix.
#
# THE REAL SCRIPT IS EXECUTED, but only ever as `self-close --dry-run`, which prints and exits before
# any side effect: no watcher is detached, no /exit is typed, no pane is closed. $HOME, the fired-dir
# and cc-in-kitty are all fixtured, so the operator's real kitty and real panes are never reachable.
#
# Every assertion is `[ ]`, `run`+status, or `… || false`. `[[ ]]` and `(( ))` are errexit-EXEMPT in
# bats and are silently DEAD anywhere but a body's last line — that has burned this repo twice.

setup() {
  # Rule 2 of test-hermeticity-lint: this suite names handoff-fire, so the capacity gate is pinned
  # OFF or the verdict reads ambient machine load instead of the subject.
  export CC_FIRE_CAPACITY_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"          # hermeticity ratchet rule 1: never the live ~/
  mkdir -p "$HOME/.claude/bin" "$HOME/.claude/cc-registry" "$HOME/.claude/cc-roles"
  FIRED="$HOME/.claude/cc-fired"; mkdir -p "$FIRED"
  export CC_FIRED_DIR="$FIRED"

  # The it2 shim must EXIST or handoff-fire's `sed … | head -1` REAL_IT2 probe aborts the script
  # under pipefail before any gate runs (same fixture as tests/handoff-selfclose-session-pin.bats).
  printf '#!/bin/bash\nREAL_IT2="%s"\nexit 0\n' "$HOME/.claude/bin/it2" > "$HOME/.claude/bin/it2"
  chmod +x "$HOME/.claude/bin/it2"

  # THE ANCESTRY SEAM. pin_term_verdict_for_watcher shells out to $HOME/.claude/bin/cc-in-kitty and
  # pins CC_TERM from its EXIT CODE — 0 kitty · 1 iterm2 · 2 unverifiable (pins nothing). Stubbing
  # the walk rather than the verdict is what lets these tests drive the REAL precedence logic: the
  # integration cases below leave CC_TERM unset, so the value under test is the one this stub
  # produces through the real pin. cc-in-kitty's own walk has its coverage in tests/cc-in-kitty.bats.
  cat > "$HOME/.claude/bin/cc-in-kitty" <<'SH'
#!/bin/bash
exit "${FAKE_CIK_RC:-1}"
SH
  chmod +x "$HOME/.claude/bin/cc-in-kitty"

  # The pane's cwd, and the tenancy oracle the origin gate binds on.
  WORK="$BATS_TEST_TMPDIR/work"; mkdir -p "$WORK"
  # $WORK must NOT sit inside a git repo: the dirty-tree gate runs BEFORE the dry-run branch, so a
  # git-visible $WORK would preempt the subject and every integration case would assert on the wrong
  # refusal. Asserted, never assumed — a fixture that quietly stops isolating is a vacuous pass.
  if ( cd "$WORK" && git rev-parse --is-inside-work-tree >/dev/null 2>&1 ); then
    echo "FIXTURE BROKEN: \$WORK is inside a git repo — the dirty-tree gate would preempt the subject" >&2
    return 1
  fi

  # The unit under test, extracted on its own — the established pattern here
  # (tests/handoff-fire-kitty.bats:124). It depends on no top-level variable, only on env.
  eval "$(sed -n '/^self_pane_id() {/,/^}/p' "$HF")"
}

# Drive the real script's self-close arm in $WORK with a controlled terminal environment.
# CC_TERM and ITERM_SESSION_ID are scrubbed unless a case sets them, so the identity comes from the
# stubbed ancestry verdict via the real pin — never from whatever terminal the developer is sitting
# in, the dependency that has broken suites in this repo twice.
sc() { # $1=cc-in-kitty rc  $2=KITTY_WINDOW_ID ("" to unset)  $3=ITERM_SESSION_ID ("" to unset)
  local rc="$1" kw="$2" it="$3"
  run env -u ITERM_SESSION_ID -u CC_TERM -u KITTY_WINDOW_ID \
      FAKE_CIK_RC="$rc" \
      ${kw:+KITTY_WINDOW_ID="$kw"} ${it:+ITERM_SESSION_ID="$it"} \
      /bin/bash -c 'cd "$1" || exit 99; exec /bin/bash "$2" self-close --terminal --dry-run' \
      _ "$WORK" "$HF"
}

# ── 1. THE FIX: an ancestry-confirmed kitty pane resolves ITSELF ─────────────────────────────────

@test "kitty pane, no \$ITERM_SESSION_ID: the identity gate PASSES and names the kitty window id" {
  # The exact shape measured on the item: KITTY_WINDOW_ID set, ITERM_SESSION_ID unset, ancestry
  # confirmed. Pre-fix this exited 1 on the identity gate; now it reaches the ORIGIN gate — a
  # different refusal, at a later gate, and one that can only be printed once an id resolved. The
  # id itself is asserted, so "it got further" cannot be mistaken for "it got further as the RIGHT
  # pane". CC_TERM is unset here, so the pin ordering is under test too (see 6 in the header).
  sc 0 4242 ""
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF 'pane 4242 has no fired-peer stamp' || false
  ! printf '%s\n' "$output" | grep -qF 'self-close needs' || false
}

@test "kitty pane with a STALE inherited \$ITERM_SESSION_ID: the KITTY id wins, not the UUID" {
  # The dangerous half of precedence. kitty-setup.sh:437 names this state — a kitty pane whose
  # ITERM_SESSION_ID came from an iTerm2 ancestor and does NOT map to its window. Taking it sends an
  # iTerm2 UUID into kitty's numeric id space, where every later lookup misses (the tty=none abort
  # of 191d1fc4143c stage 1, reached from the identity side). A "whichever is set" fix passes test 1
  # and fails this one.
  sc 0 4242 "w0t0p0:DEADBEEF-0000-1111-2222-333344445555"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF 'pane 4242 has no fired-peer stamp' || false
  ! printf '%s\n' "$output" | grep -qF 'DEADBEEF' || false
}

@test "FULL POSITIVE CONTROL: a stamped kitty peer reaches the close chain, rc 0" {
  # Tests 1 and 2 prove the identity gate stopped refusing; only this proves the resolved id is
  # USABLE all the way through. Without it the suite would be satisfied by an id that clears gate 1
  # and is wrong for everything after it.
  command -v jq >/dev/null 2>&1 || false      # a skip here would be a NON-VERDICT, not a pass
  jq -n --arg p 4242 --arg c "$(cd "$WORK" && pwd -P)" \
     '{paneUUID:$p, cwd:$c, firedBy:"positive-control", firedAt:"2026-08-05T00:00:00Z",
       selfRetire:true, schema:2, originClass:"fired-peer", closedAt:null, succession:null}' \
     > "$FIRED/4242.json"
  [ -s "$FIRED/4242.json" ]
  sc 0 4242 ""
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE '^pane: +4242$' || false
}

# ── 2. THE DIRECTIONS THAT MUST NOT FLIP ─────────────────────────────────────────────────────────

@test "genuine iTerm2 pane with a POLLUTED KITTY_WINDOW_ID keeps its iTerm2 UUID" {
  # The 2026-07-31 outage in miniature: an iTerm2.app launched from a kitty pane carries
  # KITTY_WINDOW_ID into EVERY one of its panes. cc-in-kitty answers 1 (kitty is not an ancestor),
  # so the kitty branch must never be reached and the UUID must survive.
  sc 1 4242 "w0t0p0:C0FFEE00-1111-2222-3333-444455556666"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF 'pane C0FFEE00-1111-2222-3333-444455556666 has no fired-peer stamp' || false
  ! printf '%s\n' "$output" | grep -qF 'pane 4242' || false
}

@test "NEGATIVE CONTROL: ancestry says not-kitty and there is no UUID — still REFUSES, exit 1" {
  # Without this, every assertion above is equally satisfied by a gate that simply stopped refusing.
  sc 1 4242 ""
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'self-close needs' || false
}

@test "NEGATIVE CONTROL: no terminal env at all (a launchd/daemon caller) — still REFUSES, exit 1" {
  # ANCHOR_INTENT=0: a caller with no pane of its own has no self to close, and inventing one would
  # be strictly worse than refusing.
  sc 1 "" ""
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'self-close needs' || false
}

@test "UNVERIFIABLE ancestry (cc-in-kitty exit 2) pins nothing and stays fail-closed" {
  # KITTY_* present but the walk could not be completed. The pin's own contract leaves CC_TERM
  # unset for this, so the resolution must degrade to its pre-fix behaviour — NOT to a guess that
  # the KITTY_WINDOW_ID sitting right there is ours.
  sc 2 4242 ""
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'self-close needs' || false
}

@test "UNVERIFIABLE ancestry still honours a real \$ITERM_SESSION_ID" {
  # The other half of "degrades to pre-fix": unpinned is not a refusal, it is simply the old read.
  sc 2 4242 "w0t0p0:BADC0FEE-1111-2222-3333-444455556666"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF 'pane BADC0FEE-1111-2222-3333-444455556666 has no fired-peer stamp' || false
}

@test "--session-id still overrides both, in a kitty pane" {
  # The explicit anchor is the caller's statement and outranks any derivation — unchanged contract.
  run env -u ITERM_SESSION_ID -u CC_TERM FAKE_CIK_RC=0 KITTY_WINDOW_ID=4242 \
      /bin/bash -c 'cd "$1" || exit 99; exec /bin/bash "$2" self-close --terminal --session-id 7 --dry-run' \
      _ "$WORK" "$HF"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF 'pane 7 has no fired-peer stamp' || false
}

# ── 3. THE UNIT, extracted — the precedence table on its own ─────────────────────────────────────

@test "self_pane_id: CC_TERM=kitty + KITTY_WINDOW_ID → the kitty window id" {
  CC_TERM=kitty KITTY_WINDOW_ID=28 ITERM_SESSION_ID=w0t0p0:STALE-UUID run self_pane_id
  [ "$status" -eq 0 ]
  [ "$output" = "28" ]
}

@test "self_pane_id: CC_TERM=iterm2 strips the prefix and ignores a polluted KITTY_WINDOW_ID" {
  CC_TERM=iterm2 KITTY_WINDOW_ID=28 ITERM_SESSION_ID=w0t0p0:REAL-UUID run self_pane_id
  [ "$status" -eq 0 ]
  [ "$output" = "REAL-UUID" ]
}

@test "self_pane_id: UNPINNED is byte-for-byte the pre-fix read" {
  # No CC_TERM ⇒ no admitted ancestry verdict ⇒ KITTY_WINDOW_ID is not evidence of anything.
  run env -u CC_TERM KITTY_WINDOW_ID=28 ITERM_SESSION_ID=w0t0p0:PLAIN-UUID /bin/bash -c \
      "$(sed -n '/^self_pane_id() {/,/^}/p' "$HF"); self_pane_id"
  [ "$status" -eq 0 ]
  [ "$output" = "PLAIN-UUID" ]
}

@test "self_pane_id: CC_TERM=kitty with NO KITTY_WINDOW_ID yields empty, so the caller still refuses" {
  # The headless pin: kitty_headless only fires when KITTY_WINDOW_ID is EMPTY, so CC_TERM=kitty does
  # NOT imply the caller owns a window. Returning anything here would invent a pane for a launchd job.
  run env -u KITTY_WINDOW_ID -u ITERM_SESSION_ID CC_TERM=kitty /bin/bash -c \
      "$(sed -n '/^self_pane_id() {/,/^}/p' "$HF"); self_pane_id"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "self_pane_id: a SYNTHETIC \$ITERM_SESSION_ID and the kitty id agree — the intermittency" {
  # kitty-setup.sh:255 exports w0t0p0:$KITTY_WINDOW_ID unconditionally inside kitty, so a pane whose
  # rc block has run resolves the SAME value on either branch. That is precisely why this defect is
  # invisible from most kitty panes and why it was measured, not reasoned about.
  CC_TERM=kitty KITTY_WINDOW_ID=28 ITERM_SESSION_ID=w0t0p0:28 run self_pane_id
  [ "$output" = "28" ]
  CC_TERM=iterm2 KITTY_WINDOW_ID=28 ITERM_SESSION_ID=w0t0p0:28 run self_pane_id
  [ "$output" = "28" ]
}
