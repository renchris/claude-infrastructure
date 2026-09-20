#!/usr/bin/env bats
# lr-fire-resume.sh — the DIRECT invocation must not abort on a variable only the driver sets.
#
# THE DEFECT. The capacity-admit prefix read `CC_ADMIT_BUDGET_KEY="${LR_RUN##*/}"` — bare, with no
# default — under `set -u`. LR_RUN is exported only by the FLEET driver (lr-fleet.sh /
# lr-handoff.sh). This script's OTHER documented entry point is a direct invocation: § Usage says
# "Run it in the terminal/pane that should own the resumed session", and that is how /limit-recover
# resumes a single session by hand. There LR_RUN is unset, so the script died at that line —
# `lr-fire-resume.sh: line 381: LR_RUN: unbound variable` — BEFORE the capacity gate, before the
# spawn, after it had already printed its tombstone check and run the preseed. Measured 2026-09-20
# on a live recovery: the Studio60 bottle-image session (07e30aeb) could not be resumed at all.
#
# WHY IT SURVIVED REVIEW. The three siblings in the same `VAR=… VAR=… cmd` prefix are ALL guarded
# (`${LR_ADMIT_TOKEN:-}`, `${LR_LOAD_TERM:-off}`), and so is every LR_RUN_DIR read in the file
# (`${LR_RUN_DIR:-}`, three sites). One unguarded read among four guarded ones on one continued line
# is invisible; shellcheck does not model `set -u` reachability for environment variables, so the
# file lints clean both before and after.
#
# THE FALLBACK IS NOT EMPTY, and that is the load-bearing half. CC_ADMIT_BUDGET_KEY carries a stated
# invariant — "per-RUN refusal counter: one recovery's refusals cannot release another's". An empty
# key pools every direct invocation into ONE counter, so three unrelated hand resumes would spend a
# shared 3-refusal budget and the fourth would be ADMITTED over a loaded box. The direct path
# therefore keys on its own sid.
#
# The expression is extracted with sed and executed, the house idiom for a unit inside a script that
# would otherwise `exec expect` and spawn a TUI (see lr-fire-resume-model-ssot.bats). Extracting the
# file's OWN bytes is what makes this red pre-fix: the old expression aborts under `set -u`.

setup() {
  # HERMETIC. This suite only greps the script and evaluates one extracted expression, but the
  # subject sources scripts/lib/capacity-admit.sh, whose gate reads LIVE load, free memory and a
  # `ps` session census — so a suite that can reach it goes red by desk rather than by subject
  # (backlog 5ef0dcb22aec). Both closures are asserted by the test-hermeticity ratchet.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ADMIT_GATE=off
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/limit-recover/lr-fire-resume.sh"
  [ -f "$SCRIPT" ] || skip "lr-fire-resume.sh not found"
  # The script's OWN bytes: the guarded derivation (absent pre-fix) and the prefix's key expression.
  DERIV="$(grep -E '^[[:space:]]*_lr_bkey=' "$SCRIPT" || true)"
  # `:` so an ABSENT derivation (the pre-fix shape) is a no-op rather than a `; ;` syntax error:
  # the fleet arm below must stay green pre-fix, because the fleet path was never broken.
  [ -n "$DERIV" ] || DERIV=":"
  KEYEXPR="$(grep -oE 'CC_ADMIT_BUDGET_KEY="[^"]*"' "$SCRIPT" | head -1 | sed 's/^CC_ADMIT_BUDGET_KEY=//')"
  [ -n "$KEYEXPR" ] || skip "no CC_ADMIT_BUDGET_KEY assignment found"
}

@test "direct invocation: LR_RUN unset does not abort, and keys on its own sid" {
  run env -u LR_RUN bash -c "set -u; SID=\"\$1\"; $DERIV; printf '%s' $KEYEXPR" _ 07e30aeb-bb48
  [ "$status" -eq 0 ]
  [[ "$output" != *"unbound variable"* ]] || false
  [ "$output" = "direct-07e30aeb-bb48" ]
}

@test "fleet invocation: LR_RUN set still keys on the run's basename" {
  run env LR_RUN="$BATS_TEST_TMPDIR/fleet/one-20260919T234931Z" \
      bash -c "set -u; SID=\"\$1\"; $DERIV; printf '%s' $KEYEXPR" _ 07e30aeb-bb48
  [ "$status" -eq 0 ]
  [ "$output" = "one-20260919T234931Z" ]
}

@test "two direct invocations do not share one refusal budget" {
  a="$(env -u LR_RUN bash -c "set -u; SID=\"\$1\"; $DERIV; printf '%s' $KEYEXPR" _ sid-aaa)"
  b="$(env -u LR_RUN bash -c "set -u; SID=\"\$1\"; $DERIV; printf '%s' $KEYEXPR" _ sid-bbb)"
  [ -n "$a" ]
  [ "$a" != "$b" ]
}

@test "no bare LR_RUN read survives anywhere in the file" {
  # PER-MATCH, never per-line. The original of this assertion filtered whole LINES on ':-', and the
  # defective line also carried ${LR_LOAD_TERM:-off} — so it discarded the very line it was hunting
  # and passed against the pre-fix file. A guard whose span is wider than its subject is no guard.
  run bash -c "grep -oE '[\$]\{LR_RUN(_DIR)?[^}]*\}' '$SCRIPT' | sort -u | grep -vE ':-|:=' || true"
  [ -z "$output" ]
}
