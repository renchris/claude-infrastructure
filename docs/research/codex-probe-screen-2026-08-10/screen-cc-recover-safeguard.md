VERDICT: DEFECTIVE

EVIDENCE:

1. The close outcome is swallowed, then certified. `bin/cc-recover-safeguard:161` and `:165`
   `( cd "$CWD" && "${CLOSE_TERMINAL[@]}" ) || true`
   Both arms of the close (the `--successor` fallback at :161 and the no-successor path at :165) discard
   the exit status, and nothing downstream re-reads it. The script then asserts the close as fact:
   `:171` `"$NOTIFY_BIN" "$DEST_ORIG" "✅ SAFEGUARD-RECOVERED — blocked peer $BLOCKED closed; ..."`
   `:174` `echo "→ recovery complete: re-fired on $TARGET; blocked pane $BLOCKED closed."`
   and exits 0. "closed" is a verdict token for an event that was never measured — a refused or crashed
   self-close produces the identical ✅ to the originator, the identical "recovery complete", and the
   identical zero exit. Note the file checks the re-fire's status rigorously (`:143 if ! "${REFIRE[@]}"` →
   exit 5, pane preserved) and then declines to check the destructive half, so this is not a uniform
   best-effort convention — it is asymmetric.

   Not hypothetical: `handoff-fire.sh self-close` is by construction the INVOKER'S OWN pane. Its
   self-identity gate `verify_self_pane "$SC_SID" "$SC_SID_EXPLICIT" self-close || exit 2`
   (scripts/handoff-fire.sh:4849, gate body at :1621) refuses on verdict `not-mine`, and explicitly refuses
   rather than repairs when the id came from `--session-id` ("an ASSERTION BY THE CALLER... this refuses
   instead of repairing"). cc-recover-safeguard drives `self-close --session-id "$BLOCKED"` from a THIRD
   process that does not live in the blocked pane, so exit 2 is the EXPECTED result whenever the ownership
   oracle answers at all; it is swallowed, and the blocked pane survives while the desk and the originator
   are told it is gone. (handoff-fire's own :4742 comment states the case: "`self-close` is by construction
   the invoker's own pane, so driving it from there would have closed the DRIVER" — the remote form requires
   `--source-pane/--source-session/--transplanted-source`, none of which this file passes.)
   `tests/cc-recover-safeguard.bats` cannot see this: its handoff stub is `exit ${HANDOFF_RC:-0}` and
   HANDOFF_RC is only ever set on the re-fire test, so the close is asserted only by argv text.

2. `:128` `echo "target model:   $TARGET  (≠ blocked)"` — a success token certifying an inequality that is
   never computed. TARGET is never compared to BLOCKED_MODEL. Two live paths make the parenthetical false:
   (a) `:91 TARGET="$MODEL"` — an explicit `--model` is taken with NO check, so
   `cc-recover-safeguard <pane> --model opus` on an opus-blocked pane prints "opus  (≠ blocked)"; and
   (b) BLOCKED_MODEL is a best-effort prose parse (`:85-87`) that yields "" on any refusal wording the two
   sed patterns miss — `:127` then honestly prints `blocked model:  ?` on the line above while `:128` still
   certifies "≠ blocked" against a value it does not have.

3. `:94` `case "$(printf '%s' "$BLOCKED_MODEL" | tr '[:upper:]' '[:lower:]')" in *opus*) TARGET=sonnet ;;`
   — a guard enumerating one spelling instead of the class it names. The class, stated at `:10` ("Never
   re-fires on the model that was refused") and `:90` ("never the model that was refused"), is
   TARGET != BLOCKED_MODEL; the code tests only whether the blocked string contains "opus". With
   `CC_RECOVER_DEFAULT_MODEL` set to anything other than opus (`:45`, an env seam the file offers), a block
   on that same model leaves TARGET equal to BLOCKED_MODEL and the guard can never fire — the script
   re-fires the identical brief at the identical model that just refused it, which is the one outcome the
   tool exists to prevent.

4. (secondary) `:142` `before_json="$(... || echo '[]')"` consumed at `:150` as `--argjson seen "${before_json:-[]}"`.
   The "not present before the fire" half of the new-pane test is the only thing distinguishing the successor
   from any other session in that cwd; on a transient `cc-sessions` failure it defaults to `[]`, the guard
   becomes vacuous, and the first unrelated pane sharing $CWD is adopted as `$NEW` and written into a
   MANDATORY succession statement (`:159 --successor "$NEW" --dirty-owner successor`), which asserts to
   handoff-fire that the close loses nothing because that pane owns the tree.

OPEN_FINDINGS: none found; searched docs/research, docs/plans, docs/proposals and all of docs/ for
"cc-recover-safeguard" (8 hits). All are non-defect references: docs/SAFEGUARD_BLOCKED_VISIBILITY.md
(the C4 design/LANDED record), docs/research/nightly-regression-triage-2026-07-30.md:276 which audits this
file's reaper-horizon justification and scores it "**accurate** — the one entry that had not drifted",
docs/research/STRANDED_EXPOSURE_2026-07-26.md:730 (LANDED row), docs/research/orphan-harvest-2026-07-26/
r4-runtime-profile.md:205 (bats timing, pass), docs/plans/INFRA_PERFECTION_2026-07-25.md:440 (declaration
fixed via 7b30ed7f), docs/proposals/ARMED_SUCCESSION_LIFECYCLE.md:570,890 (descriptive). No document names
any of the four defects above.
