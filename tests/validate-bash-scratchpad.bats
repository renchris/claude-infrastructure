#!/usr/bin/env bats
# validate-bash SCRATCHPAD CATEGORY — the missing rm category that wedged four dispatched sessions.
#
# Subject: hooks/validate-bash.sh, SCRATCHPAD-CATEGORY span + its two call sites in the rm warn.
#
# THE DEFECT (backlog 7da9c4451540, measured 2026-08-18): SAFE_RM_TARGETS allowlists build-artifact
# NAMES and has no entry for the harness's own per-session scratchpad, so routine self-cleanup drew
# an `ask` — and an `ask` is TERMINAL for a dispatched session, which has no operator at its pane.
# Four losses in 24 h, including pane 131, the 24/7 drain chain, dead-stopped ~4 h with no alarm.
#
# THE CLAIM IS TWO-SIDED, and the second side is the one guard changes usually skip (MEMORY.md
# guard-proxy-fails-in-both-directions). Every PERMIT below is paired with the REFUSAL that differs
# from it by exactly one lever, so a guard that simply said yes more often would fail this file:
#   (1) permit  <own scratchpad>/x        ↔ (5) refuse <own scratchpad>-evil/x    — prefix look-alike
#                                         ↔ (6) refuse <own scratchpad>/../../repo — `..` out
#                                         ↔ (7) refuse a symlink INTO a repo
#                                         ↔ (9) refuse ANOTHER session's scratchpad — same tree, wrong UUID
#                                         ↔ (10) refuse with no session_id at all  — identity absent
# and (2)/(3) are the PRE-FIX artifact replayed from git rather than hand-written (MEMORY.md
# control-must-replay-the-real-artifact): it must REFUSE case (1) — that refusal IS the bug — while
# still permitting node_modules, which proves the old artifact is functional and not merely broken.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # VB_HOOK exists so the WHOLE suite can be replayed against the pre-fix artifact, not just the two
  # cases that build it themselves — that whole-suite run is what proves the refusals were already
  # holding before the change and were not manufactured by it.
  HOOK="${VB_HOOK:-$REPO/hooks/validate-bash.sh}"
  D="$BATS_TEST_TMPDIR"
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  # The FF-gate lives in this same file and keys on the shared checkout; pin it away from the real
  # one so no case here can be decided by a guard it is not testing.
  export CC_SHARED_CHECKOUT="$D/shared"; mkdir -p "$CC_SHARED_CHECKOUT"

  # The scratchpad tree, standing in for /private/tmp/claude-<uid> through the SAME env seam
  # scripts/scratchpad-reaper.sh uses — one spelling of where the scratchpad is, not two.
  export CC_SCRATCHPAD_ROOT="$D/spads"
  SID="7bacff59-dcaa-472c-8600-cca1baaa4ae4"
  OTHER_SID="00000000-1111-2222-3333-444444444444"
  SLUG="-Users-chrisren-Development-someproject"
  SP="$CC_SCRATCHPAD_ROOT/$SLUG/$SID/scratchpad"
  OTHER_SP="$CC_SCRATCHPAD_ROOT/$SLUG/$OTHER_SID/scratchpad"
  mkdir -p "$SP/prefix-bin" "$OTHER_SP/prefix-bin" "$SP-evil"
  # A repo working tree, and the two ways a scratchpad path can reach into one.
  mkdir -p "$D/repo/src"
  ln -sfn "$D/repo" "$SP/link-to-repo"
  ln -sfn "$D/repo/src" "$SP/link-to-repo-src"
  if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
}

# probe <command> [session-id] [hook-path] — session_id defaults to THIS fixture session's UUID,
# because identity comes from the payload and nowhere else.
probe() {
  run env CC_SCRATCHPAD_ROOT="$CC_SCRATCHPAD_ROOT" bash -c \
    'jq -nc --arg c "$1" --arg s "$2" "{session_id:\$s, tool_input:{command:\$c}, cwd:\"/\"}" | "$0"' \
    "${3:-$HOOK}" "$1" "${2-$SID}"
}
decision() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo unparseable; }
permitted() { [ -z "$1" ]; }                      # silent + exit 0 is the ONLY permit shape
refused()   { [ "$(decision "$1")" = ask ] || [ "$(decision "$1")" = deny ]; }

# The pre-fix artifact, built from the REAL subject at the commit before the category landed. It is
# placed under a hooks/ dir with a lib/ link because the hook resolves hooks/lib from BASH_SOURCE —
# run it from a bare tmpdir and it silently drops to the legacy text path, which would make the
# control a comparison of two different code paths rather than of one change.
prefix_hook() {
  PRE="$D/hooks/prefix.sh"
  [ -x "$PRE" ] && { printf '%s' "$PRE"; return; }
  mkdir -p "$D/hooks"
  ln -sfn "$REPO/hooks/lib" "$D/hooks/lib"
  git -C "$REPO" show f8843d922:hooks/validate-bash.sh > "$PRE" 2>/dev/null || return 1
  [ -s "$PRE" ] || return 1
  chmod +x "$PRE"; printf '%s' "$PRE"
}

# ── PERMITS ─────────────────────────────────────────────────────────────────────────────────────

@test "(1) PERMITS rm -rf on a path under THIS session's own scratchpad — pane 339's exact shape" {
  # Pane 339 built a mutant binary in its scratchpad to prove a test RED, removed it, and stalled
  # forever on the modal. This is that command with the path expanded.
  probe "rm -rf $SP/prefix-bin"
  [ "$status" -eq 0 ]
  permitted "$output" || { echo "decision was: $(decision "$output")"; false; }
}

@test "(1b) PERMITS a nested throwaway, and the trailing-slash spelling" {
  probe "rm -r $SP/build-1/obj"
  permitted "$output" || false
  probe "rm -rf $SP/prefix-bin/"
  permitted "$output" || false
}

@test "(1c) PERMITS it on the LEGACY text path too — the second call site, not just the argv one" {
  # VALIDATE_BASH_LEGACY=1 is the parser rollback knob. The category must exist on both branches or
  # the rollback silently re-opens the stall.
  run env VALIDATE_BASH_LEGACY=1 CC_SCRATCHPAD_ROOT="$CC_SCRATCHPAD_ROOT" bash -c \
    'jq -nc --arg c "$1" --arg s "$2" "{session_id:\$s, tool_input:{command:\$c}, cwd:\"/\"}" | "$0"' \
    "$HOOK" "rm -rf $SP/prefix-bin" "$SID"
  [ "$status" -eq 0 ]
  permitted "$output" || { echo "legacy decision was: $(decision "$output")"; false; }
}

@test "(2) PRE-FIX CONTROL: the real artifact from git REFUSES case (1) — that refusal IS the bug" {
  pre="$(prefix_hook)" || skip "pre-fix artifact unavailable (shallow clone?)"
  probe "rm -rf $SP/prefix-bin" "$SID" "$pre"
  [ "$status" -eq 0 ]
  refused "$output" || { echo "pre-fix hook did NOT refuse — the control cannot fail, so it proves nothing"; false; }
}

@test "(3) PRE-FIX POSITIVE CONTROL: the same artifact still PERMITS node_modules" {
  # Without this, case (2) is satisfied by an artifact that is merely broken.
  pre="$(prefix_hook)" || skip "pre-fix artifact unavailable (shallow clone?)"
  probe "rm -rf node_modules" "$SID" "$pre"
  permitted "$output" || { echo "the pre-fix artifact refuses everything — it is broken, not pre-fix"; false; }
}

@test "(4) CONTROL: build-artifact names are untouched by the change" {
  probe "rm -rf node_modules"
  permitted "$output" || false
  probe "rm -rf dist/assets"
  permitted "$output" || false
}

# ── STILL REFUSES — one lever each, and every one must hold PRE-fix as well ──────────────────────

@test "(5) REFUSES a look-alike PREFIX: <scratchpad>-evil is not under <scratchpad>/" {
  probe "rm -rf $SP-evil/x"
  refused "$output" || { echo "a spelled prefix was admitted — the category is matching text, not paths"; false; }
}

@test "(6) REFUSES a \`..\` traversal that leaves the scratchpad and lands in a repo" {
  probe "rm -rf $SP/../../../../repo"
  refused "$output" || { echo ".. escaped the root — the comparison is not on a resolved path"; false; }
  # A `..` UNDER a component that does not exist cannot be resolved at all, so it must abstain
  # rather than be re-attached as text — that re-attachment is how a walk-up resolver leaks.
  probe "rm -rf $SP/nonexistent/../../../../../repo"
  refused "$output" || false
}

@test "(7) REFUSES a SYMLINK inside the scratchpad that points into a repo" {
  probe "rm -rf $SP/link-to-repo"
  refused "$output" || false
  # ...and the file-side of the resolver, where the leaf is a link to a directory deeper in the repo.
  probe "rm -rf $SP/link-to-repo-src"
  refused "$output" || false
}

@test "(8) REFUSES a path inside a repo working tree" {
  probe "rm -rf $D/repo/src"
  refused "$output" || false
  probe "rm -rf $REPO/hooks"
  refused "$output" || false
}

@test "(9) REFUSES ANOTHER session's scratchpad — same tree, same shape, wrong UUID" {
  probe "rm -rf $OTHER_SP/prefix-bin"
  refused "$output" || { echo "one session can delete another's scratchpad — identity is not being read"; false; }
}

@test "(10) FAILS CLOSED when the payload carries no session_id" {
  probe "rm -rf $SP/prefix-bin" "-"
  refused "$output" || false
  probe "rm -rf $SP/prefix-bin" ""
  refused "$output" || false
}

@test "(11) FAILS CLOSED on an UNEXPANDED token — the hook reads text, and a guess is a spoof" {
  probe 'rm -rf "$SP/prefix-bin"'
  refused "$output" || { echo "an unresolvable token was admitted"; false; }
}

@test "(12) FAILS CLOSED on a RELATIVE token — the cwd it would need is not this hook's to assume" {
  probe "rm -rf prefix-bin"
  refused "$output" || false
}

@test "(13) FAILS CLOSED when the scratchpad root does not exist for this session" {
  run env CC_SCRATCHPAD_ROOT="$D/no-such-root" bash -c \
    'jq -nc --arg c "$1" --arg s "$2" "{session_id:\$s, tool_input:{command:\$c}, cwd:\"/\"}" | "$0"' \
    "$HOOK" "rm -rf $SP/prefix-bin" "$SID"
  refused "$output" || false
}

@test "(14) the catastrophic-rm DENY is untouched: root and \$HOME still deny, not ask" {
  probe "rm -rf /"
  [ "$(decision "$output")" = deny ] || false
  probe 'rm -rf $HOME'
  [ "$(decision "$output")" = deny ] || false
  # A scratchpad path is a permit, but the compound-command escape hatch stays shut: the dangerous
  # clause is still decided on its own.
  probe "rm -rf $SP/prefix-bin && rm -rf $D/repo"
  refused "$output" || false
}
