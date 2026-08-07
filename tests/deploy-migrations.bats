#!/usr/bin/env bats
# deploy-migrations — face 3 of docs/research/inertness-generator-2026-08-07.md §3:
# ACTIVATIONS BECOME MIGRATIONS.
#
# The defect this closes is the machine's own measured state on 2026-08-07: 38 pending activations,
# 11 rotting past 24h, 8 live-vs-repo SSOT drifts, and a session-start banner re-listing all of it
# every single session. Registration state lived in an ADVISORY store — writes into it always
# succeeded, reads out of it were discretionary — so knowledge accumulated and behaviour did not.
#
# The runner's own `--selftest` proves the MECHANISM discriminates (24 cases, throwaway tree). This
# suite proves the four things a selftest structurally cannot:
#   • the mechanism is WIRED at the converger — an unwired runner is detection, not a gate
#     (memory: enforcement-must-live-at-the-chokepoint);
#   • every migration IN THIS REPO declares a class, so none can reach a converge undeclared;
#   • the runner is GREEN against the real tree — a converge step that ships standing-red would
#     wedge the very edge it exists to unwedge;
#   • the C10 boundary holds on the REAL migrations: nothing that touches settings.json / a plist /
#     credentials is declared `mechanical`, because §3's rescope of C10 is the one clause the doc
#     says a human must ratify, and this runner must not self-authorize it.
#
# Assertions use the explicit `|| { …; false; }` form throughout: a non-final `[[ ]]` is
# errexit-EXEMPT under bats and would be a DEAD assertion that can never fail
# (memory: bats-dead-assertions-errexit-exemptions).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  RUNNER="$REPO/scripts/deploy-migrations.sh"
  MIGS="$REPO/migrations"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # dogfood the sibling hermeticity rule
}

@test "1: the runner's own --selftest passes, and reports every case it ran" {
  run bash "$RUNNER" --selftest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # COMPUTED by the selftest, so this asserts the FORM and a floor rather than a literal that would
  # drift every time a case is added — and a floor is what catches a selftest gutted to one case.
  line="$(printf '%s' "$output" | sed -n 's/.*--selftest: \([0-9]*\) passed, \([0-9]*\) failed.*/\1 \2/p')"
  [ -n "$line" ] || { echo "no 'N passed, M failed' line: $output"; false; }
  passed="${line% *}"; failed="${line#* }"
  [ "$failed" -eq 0 ] || { echo "selftest reported $failed failure(s): $output"; false; }
  [ "$passed" -ge 20 ] || { echo "selftest ran only $passed case(s) — gutted?"; false; }
}

@test "2: the runner is WIRED into the converger, on BOTH paths" {
  # An unwired runner is the exact class this whole mechanism exists to leave: correct, landed,
  # inert. Both call sites are load-bearing and for different reasons — the unconditional one catches
  # retries and hand-edits of the derived queue; the post-advance one is the only call that can run a
  # migration in the SAME cycle as the land that carried it, because both early exits ("already
  # deployed", the rollback refusal) return before reaching it.
  n="$(grep -c '^migrations_converge$' "$REPO/scripts/deploy-live.sh" || true)"
  [ "$n" -eq 2 ] || { echo "expected 2 migrations_converge call sites in deploy-live.sh, found $n"; false; }
  grep -q 'migrations_converge() {' "$REPO/scripts/deploy-live.sh" \
    || { echo "deploy-live.sh does not define migrations_converge"; false; }
  # The pre-fetch call must sit with link_refresh (unconditional), not nested under the advance.
  grep -A1 '^link_refresh$' "$REPO/scripts/deploy-live.sh" | grep -q 'migrations_converge' \
    || { echo "the unconditional call is not adjacent to link_refresh — it may have been nested under the advance"; false; }
}

@test "3: every migration in the repo DECLARES a class (none can reach a converge undeclared)" {
  # The runner treats an undeclared class as a hard error rather than defaulting, because both
  # defaults are wrong (mechanical ⇒ a settings-touching migration runs unattended; c10 ⇒ it silently
  # rejoins the hand-queue). This test is what stops that error ever being reached from this repo.
  shopt -s nullglob
  local found=0
  for f in "$MIGS"/*.sh; do
    found=$(( found + 1 ))
    class="$(sed -n 's/^# *migration-class: *//p' "$f" | head -1)"
    case "$class" in
      mechanical|c10) ;;
      *) echo "$(basename "$f"): migration-class is '${class:-<absent>}' (expected mechanical|c10)"; false ;;
    esac
  done
  [ "$found" -gt 0 ] || { echo "no migrations found under $MIGS — the mechanism has zero instances"; false; }
}

@test "4: every c10 migration carries the operator step it will file" {
  # A staged step with no text is an item nobody can act on — it would render as a blank line in the
  # operator's close block, which is worse than not filing it at all.
  shopt -s nullglob
  for f in "$MIGS"/*.sh; do
    class="$(sed -n 's/^# *migration-class: *//p' "$f" | head -1)"
    [ "$class" = "c10" ] || continue
    step="$(sed -n 's/^# *migration-step: *//p' "$f" | head -1)"
    [ -n "$step" ] || { echo "$(basename "$f"): class c10 with no '# migration-step:'"; false; }
  done
}

@test "5: no mechanical migration touches a C10 surface (the un-ratified boundary holds)" {
  # §3's rescope — "operator RUNS" becomes "operator CAN REVERT" — is explicitly the one clause the
  # doc says a human must ratify, once, and it has not been ratified. So the runner must not be able
  # to reach settings.json, a launchd plist, or the keychain unattended. Keyed on the SURFACE, not on
  # a verb: a denylist of spellings (`jq -i`, `launchctl load`) enumerates its examples rather than
  # the class, and lets the twelfth spelling straight through
  # (memory: denylist-enumerates-spellings-not-the-class).
  shopt -s nullglob
  for f in "$MIGS"/*.sh; do
    class="$(sed -n 's/^# *migration-class: *//p' "$f" | head -1)"
    [ "$class" = "mechanical" ] || continue
    # Comments are stripped first: a mechanical migration may legitimately DISCUSS settings.json in
    # its rationale, and a detector that matches prose about the surface reports the explanation as
    # the breach (memory: detector-matching-its-own-skill-description).
    body="$(grep -v '^[[:space:]]*#' "$f" || true)"
    printf '%s' "$body" | grep -qE 'settings\.json|LaunchAgents|launchctl|\.plist|security +(add|find)-generic-password' \
      && { echo "$(basename "$f"): class 'mechanical' reaches a C10 surface — declare it c10 until the rescope is ratified"; false; }
  done
  true
}

@test "6: --status and --dry-run are GREEN against the real tree and mutate nothing" {
  # A converge step that ships standing-red would wedge the edge it exists to unwedge. --dry-run is
  # the safe way to assert that here: it exercises discovery, class parsing and the parity compare
  # over the REAL migrations and the REAL repo SSOT without writing to the operator's live queue.
  state="$BATS_TEST_TMPDIR/state"; queue="$BATS_TEST_TMPDIR/queue"; mkdir -p "$queue"
  run env CC_MIGRATIONS_REPO="$REPO" CC_MIGRATIONS_STATE="$state" CC_ACTIVATION_DIR="$queue" \
      bash "$RUNNER" --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -d "$state" ] || { echo "--dry-run created the state dir"; false; }
  [ -z "$(ls -A "$queue")" ] || { echo "--dry-run wrote into the live queue"; false; }
  # …and it must have SEEN the real migrations, or the green above is vacuous.
  printf '%s' "$output" | grep -q 'would RUN\|would STAGE' \
    || { echo "--dry-run named no migration — it scanned nothing: $output"; false; }

  run env CC_MIGRATIONS_REPO="$REPO" CC_MIGRATIONS_STATE="$state" bash "$RUNNER" --status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | grep -q 'MIGRATIONS' || { echo "no status header: $output"; false; }
}

@test "7: the converger never writes REPO-SIDE (a local diff the next ff must conflict on)" {
  # hooks/activation-watch.sh:249 already warns about this in the other direction. The materialise
  # phase is one-way BY CONSTRUCTION, and this asserts it against the real repo SSOT rather than a
  # fixture — the population that would actually be damaged.
  state="$BATS_TEST_TMPDIR/state2"; queue="$BATS_TEST_TMPDIR/queue2"; mkdir -p "$queue"
  printf '#!/bin/bash\n# invented live-only\n' > "$queue/zz-live-only-activate.sh"
  before="$(git -C "$REPO" status --porcelain -- docs/activation/pending-activation | wc -l | tr -d ' ')"
  run env CC_MIGRATIONS_REPO="$REPO" CC_MIGRATIONS_STATE="$state" CC_ACTIVATION_DIR="$queue" \
      bash "$RUNNER" --materialise
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  after="$(git -C "$REPO" status --porcelain -- docs/activation/pending-activation | wc -l | tr -d ' ')"
  [ "$before" = "$after" ] || { echo "materialise dirtied the repo SSOT ($before → $after)"; false; }
  [ ! -f "$REPO/docs/activation/pending-activation/zz-live-only-activate.sh" ] \
    || { echo "a LIVE-ONLY file was copied repo-side"; false; }
  # …and the real SSOT did reach the queue, so the assertion above is not green-because-nothing-ran.
  # Counted with a glob, not `ls | grep`: the invented live-only file is the ONE name that was
  # already there, so anything else present is proof the phase actually copied.
  n=0
  for _f in "$queue"/*.sh; do
    case "${_f##*/}" in zz-live-only-activate.sh) continue ;; esac
    [ -f "$_f" ] && n=$(( n + 1 ))
  done
  [ "$n" -gt 0 ] || { echo "materialise copied nothing — the repo-side assertion is vacuous"; false; }
}

@test "8: activation-watch's parity remedy points at the converger, not a hand cp" {
  # The two mechanical drift classes are now the converger's to fix. A surface still platter-ing
  # `cp live -> repo` would instruct the exact repo-side write test 7 forbids — and it used to render
  # that on EVERY SessionStart, to every agent and operator.
  W="$REPO/hooks/activation-watch.sh"
  grep -q 'deploy-live.sh' "$W" || { echo "activation-watch no longer points at the converger"; false; }
  grep -nE '▶ cp \$mirror/<name> \$DIR/<name>|▶ diff \$mirror' "$W" \
    && { echo "activation-watch still platters a hand-sync for a converger-owned class"; false; }
  true
}
