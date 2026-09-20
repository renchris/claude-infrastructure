# Adversarial critique — § 10 IN-PLACE BY DEFAULT (read-only, at `79e4b8d18`; scripts/ bin/ tests/ are byte-identical to `8b5db5947`)

1. **CLAIM** W9b: "`pin_still_live` proves liveness by ancestry … `scripts/handoff-fire.sh` (`:3472-3478`)" (also § 10.1 and receipt R7).
   **VERDICT** REFUTED — wrong function.
   **EVIDENCE** `pin_still_live()` is `handoff-fire.sh:3463-3470` (`:3463 pin_still_live() { # $1="<sid> <pid>" $2=pane-tty → 0 live / 1 gone`; the equality is `:3469 [ -n "$tty_now" ] && [ "$tty_now" = "$(basename "$ptty")" ]`). `:3472-3478` is the **comment header of `pid_is_cc`**, a different function defined at `:3482`.
   **FIX** Re-anchor W9b and R7 to `handoff-fire.sh:3463-3470`; `:3472-3493` is `pid_is_cc`, which W9b explicitly must NOT touch.

2. **CLAIM** W11: "`lr-transplant.sh` becomes idempotent on a same-target retry … so a retry after rc 4 / PARTIAL re-drives the recycle instead of being refused at `:97`" (files: `lr-transplant.sh` `:59-69`, `:97`).
   **VERDICT** REFUTED — `:97` refuses nothing; the two real refusals are uncited.
   **EVIDENCE** `lr-transplant.sh:97 if [[ $KEEP_SOURCE -ne 1 && "${CLAUDE_CODE_SESSION_ID:-}" != "$SID" ]]; then` — the source-retirement guard. The retry refusals are `:55-57` (`REFUSED — $DST already exists (use --force to overwrite)`) and `:63-66` (`REFUSED — lock exists ($LOCK)`). A W11 teammate editing only `:59-69`/`:97` ships a retry that is still refused at `:55`.
   **FIX** W11's idempotence edit lands at `lr-transplant.sh:55-57` **and** `:63-66` (both must return rc 0 `already transplanted` when lock `to` == target ∧ `$DST` sha ≥ source); `:97` is unrelated.

3. **CLAIM** W8: "`lr-handoff.sh`: the socket-resolution block (`:893-901`) moves ABOVE the in-place call (`:764`) so `kt()` can address kitty from launchd."
   **VERDICT** PARTIAL — the block is env-guarded and is INERT for the class § 10.1 actually measured.
   **EVIDENCE** `lr-handoff.sh:893 if [ "$IN_KITTY" = 0 ] && [ -z "${KITTY_WINDOW_ID:-}" ] && [ -z "${IT2_WRAPPER_NO_KITTY:-}" ]; then`. R5's reproduced orphan has `KWID=198 KPID=73832` **intact**, so `:893` is false and the move buys nothing for the 2026-09-19 nohup drivers (3 of the 9); it helps only the launchd poller (6 of 9).
   **FIX** State that the move serves the launchd arm only, and that the orphan arm is carried entirely by `hf_remote_pane_term`'s own `CC_TERM` export (the orphan still inherits `KITTY_LISTEN_ON`, so bare `kt()` addresses kitty without `--to`).

4. **CLAIM** W8: "a live kitty socket (`kitty_socket_answers`, discovered via `bin/cc-kitty-socket` / `kitty_socket_template` even when `KITTY_WINDOW_ID` is set — the driver's env is irrelevant to the target)".
   **VERDICT** PARTIAL — names a function that cannot enumerate, and the obvious helper is barred.
   **EVIDENCE** `kitty_socket_template()` (`:1163-1175`) returns the **unsubstituted** string `unix:/tmp/kitty-{kitty_pid}`; the enumerator is `kitty_sockets()` (`:1181-1201`), which substitutes per live kitty pid. The wrapper `kitty_headless()` is unusable here: `:1127 [ -z "${KITTY_WINDOW_ID:-}" ] || return 1` and `:1128 [ -z "${ITERM_SESSION_ID:-}" ] || return 1`, memoized at `:1120`.
   **FIX** W8 must call `kitty_sockets` + `kitty_socket_answers` **directly** (never `kitty_headless`, whose env gate is the exact opposite of "the driver's env is irrelevant"), then `export CC_TERM_KITTY_TO` itself.

5. **CLAIM** W8: "P integer ∧ a live kitty socket … enumerates window P ⇒ kitty; P a UUID ⇒ iterm2; **neither ⇒ refuse `REMOTE-PANE-UNENUMERABLE`**."
   **VERDICT** PARTIAL — "neither" collapses three states with opposite remedies, re-creating the defect the same wave is fixing one layer down.
   **EVIDENCE** An integer P that a live socket does not list = pane **GONE** (definite negative). No socket answering at all = **no kitty on the box**. A socket that times out (`kitty_socket_answers` → `hf_bounded` rc 124, `:1205-1207`) = **CANNOT TELL**. `handoff-fire.sh:1500-1511` is the in-repo ruling that ABSENT and WEDGED "do not have the same remedy", and W8's own next sentence demands `as_tty_classified` rc 3 be kept distinct.
   **FIX** `hf_remote_pane_term` returns three codes — 0 resolved · 1 `REMOTE-PANE-ABSENT` (socket answered, no such window) · 3 `REMOTE-PANE-RESOLVER-UNAVAILABLE` (no socket answered) — and only 1 is terminal.

6. **CLAIM** W10: HUSK = "a live row on account A whose sid carries a lock/tombstone with `to` ≠ A (`lr_transplanted_to`) — evaluated BEFORE the last-assistant-word filter".
   **VERDICT** PARTIAL — true of a settled husk, and **also true of every in-place recovery while it is in flight**; the plan carries no guard.
   **EVIDENCE** `lr-lib.sh:452-459` keys only on `$state/locks/$sid.lock` existing, `to != here`, and the target copy existing — and **nothing in the repo ever deletes that lock** (`grep -rn 'locks/' scripts/limit-recover/*.sh` yields no `rm`). `lr-handoff.sh:641` writes lock+copy; the source pid stays alive and its registry row live until the typed `/exit` lands (composer gate 180 s, `--await` up to 900 s, `:773-784`). During that window `lr_registry_live_rows` (`lr-lib.sh:226-241`) still returns the death-account row ⇒ HUSK.
   **FIX** Add a conjunct the plan states out loud: HUSK requires **no in-flight recycle for the sid** (an armed `__recycle` watcher / `handoffs.jsonl` row / lock ts older than `LR_HUSK_MIN_AGE_S`), and say that today the only thing stopping a close is the actuator's "successor has an assistant turn after the tombstone ts" conjunct — the CENSUS is unguarded, so W12's DoD "post-run census shows `0 HUSK`" will flake against its own arm (f).

7. **CLAIM** § 10.1 (6d): "`--mark` writes `<tx>.HANDOFF.json` beside the TARGET copy (`lr-fleet.sh:688-695`) **with no check for an existing `handed_off_to` tombstone**".
   **VERDICT** PARTIAL — a check exists; only its KEY is wrong. (Receipt R8 states this correctly; the plan body dropped the qualifier.)
   **EVIDENCE** `lr-fleet.sh:693 [ -f "$tomb" ] && { echo "lr-fleet: $tomb already exists — refusing to overwrite a tombstone" >&2; exit 2; }`, where `:692 tomb="${tx%.jsonl}.HANDOFF.json"` resolves against the TARGET store only. The write is `:694-695`; `:688` is a bare `EOF`.
   **FIX** W9a's job is to widen the existing `:693` check across all `$(lr_config_dirs)` roots (the shape `hf_transplant_evidence:2068-2078` already uses), not to add a check that is absent — and re-anchor to `lr-fleet.sh:692-695`.

8. **CLAIM** (lead's Q4) a same-account SUPERSEDED tombstone makes `lr_transplanted_to` succeed.
   **VERDICT** REFUTED — it cannot.
   **EVIDENCE** `--mark` writes **only** the JSON (`lr-fleet.sh:694-695`) and no lock; `lr_transplanted_to` reads **only** `$state/locks/$sid.lock` (`lr-lib.sh:452-453`) and additionally requires `to_real != here_real` (`:458`), which a same-account mark fails by construction.
   **FIX** Fix the plan's wording only: W10 says "a lock/**tombstone** with `to` ≠ A (`lr_transplanted_to`)" — that predicate never reads a tombstone. Say "the transplant **lock**", or the reader will build a tombstone-reading variant that DOES misfire on `--mark`.

9. **CLAIM** W11: "Automatic fallback to spawn ONLY on NO-PANE and on the launcher-rooted REPLACE class (`:794-803`); every other refusal … parks with nothing moved."
   **VERDICT** PARTIAL — anchor wrong, and the honesty gap is the rc-4 arm, not REPLACE.
   **EVIDENCE** `:794-798` is the **rc-0 success** branch; REPLACE is `:799-807` (`:799 if grep -q 'has NO shell under its session'`, `:805 LRH_REPLACE=1`, `:806 CLOSE_SOURCE=1`). Both REPLACE and the rc-4 arm (`:809-814`) sit **after** `"$HF" "${RCY_ARGS[@]}"` at `:791`, which is after the transplant at `:641` — so on both, the session HAS moved and a tombstone exists. "Nothing moved" is true only of a `lrh_precheck` refusal (`:585-630`, called at `:632`, i.e. before `:641`).
   **FIX** Re-anchor to `:799-807`, and add: "the guarantee is `lrh_precheck` at `:632`; anything refused after `:791` is already tombstoned and its disposition is `--retire-husks`, not a park."

10. **CLAIM** W11: "self (`--sid` == `$CLAUDE_CODE_SESSION_ID` and `$KITTY_WINDOW_ID`/`$ITERM_SESSION_ID` present) or driver (`--source-pane`, else `lr_registry_live_rows $SID` → its pane …)".
    **VERDICT** PARTIAL — ordering unstated, and it decides whether the "nothing moved" guarantee exists at all.
    **EVIDENCE** `lrh_precheck` probes the pane **only when `$SOURCE_PANE` is non-empty** (`lr-handoff.sh:588`) and runs at `:631-633`; argv parsing ends at `:225`. A pane resolved after `:631` is transplanted with no pre-check.
    **FIX** W11 must resolve the implied pane into `SOURCE_PANE` **between `:225` and `:631`**, and state that as the wave's ordering invariant.

11. **CLAIM** (lead's Q1) a consumer between `:9247` and the watcher spawn still reads the driver's ancestry and refuses.
    **VERDICT** REFUTED — none found.
    **EVIDENCE** `self_pane_id`/`verify_self_pane` are skipped for the remote form (`:9278 if [ "$RCY_REMOTE" = 0 ]`). The typing path branches on `in_kitty()` (`:973`), not `kitty_identity` — TRUE for the orphan via its inherited `KITTY_WINDOW_ID`, and resolved via `kitty_headless` for launchd. The only ancestry consumer is `kitty_identity` (`:991`) inside `_as_tty_query` (`:1569`), reached from `hf_remote_source_pin:2037` and `:1822`/`:1840`.
    **FIX** Add `:11838` and `:11983` (both inside `recycle_fire`) to W8's call-site list as *no-ops by inheritance* — same process, so the `:1687` early-return fires — so a teammate does not "fix" them into a second resolution.

12. **CLAIM** W8: "The watcher inherits the pinned verdict (it types into P)."
    **VERDICT** STANDS.
    **EVIDENCE** `detach()` `:1615-1620` — `subprocess.Popen(sys.argv[2:], start_new_session=True, …)` with **no `env=`** ⇒ the exported `CC_TERM`/`CC_TERM_KITTY_TO` are inherited by the `__recycle` re-exec (`:6581`), whose own `pin_term_verdict_for_watcher` calls early-return on `:1687 [ -n "${CC_TERM:-}" ] && return 0`. Caveat to record: the export is process-global, so on an iTerm2 driver recycling a kitty pane every later terminal call in that process resolves as kitty — benign today because every post-`:9247` write targets P, but it is an invariant W8 should assert rather than inherit.

13. **CLAIM** (lead's Q1, tests) a named suite goes red under W8 as designed.
    **VERDICT** REFUTED for all four, with two tripwires.
    **EVIDENCE** `handoff-selfclose-kitty-identity.bats` drives `self-close --terminal --dry-run` (`:115-116`) with no `--source-pane`, so W8's branch is unreachable. `handoff-selfclose-terminal-pin-order.bats`'s judge is a **static text scan** (`:109-126`): window = self-close entry → first `^ *SUC_TTY="\$(as_tty` (`:112`), `pin_at` = `^ *pin_term_verdict_for_watcher *$` (`:117`), `tty_at` = first `as_tty "` (`:119`) — all unchanged if `hf_remote_pane_term` sits above `:7560` and contains no literal `as_tty "`. `handoff-fire-kitty{,-daemon}.bats` pin `in_kitty`'s one-liner by `sed -n '/^in_kitty() {/p'` (`:969-970`), untouched.
    **FIX** Two hard constraints into W8's brief: (a) do **not** rename `SUC_TTY` or reshape `SUC_TTY="$(as_tty …)"` — `pin_order_verdict` returns 11 and the red-proof reads as an anchor rot; (b) `hf_remote_pane_term`'s body must not contain the literal `as_tty "` (use `as_tty_classified`), or `tty_at` moves above `pin_at` and mutant-2 flips.

14. **CLAIM** (lead's Q2) the orphan could get `cc-in-kitty` rc 2 instead of rc 1.
    **VERDICT** REFUTED for the measured population; the rc-2 path exists but is not reachable there.
    **EVIDENCE** `bin/cc-in-kitty:82` (rc 2) needs `KITTY_PID` unset/non-numeric and `:87` needs it ≤ 1 — R5 measured `KPID=73832`. The walk then hits `:101 if (c <= 1) exit 1 # reached launchd without meeting kitty: DEFINITIVE no` on the first hop for a reparented orphan. Under launchd, `:75` (`KITTY_WINDOW_ID` unset) ⇒ exit 1 before the walk. rc 2 is reachable only via `:95`/`:99`/`:103` (ps unreadable / ancestor reaped).
    **FIX** None to the mechanism; add one line that rc 2 leaves `CC_TERM` unpinned (`:1699`), so `kitty_identity` falls through to `in_kitty` and the orphan would actually SUCCEED — i.e. the failure is specific to the DEFINITIVE-no, which is what makes W8's targeting correct.

15. **CLAIM** W9b: "`tests/handoff-selfclose-transplanted-source.bats`" is the suite for the change.
    **VERDICT** PARTIAL — blast radius is three call paths and nothing pins the property in either direction.
    **EVIDENCE** `pin_still_live` callers: `successor_pin:3455` (itself called at `:2351` and `:8062`, the self-close successor gate) and the `__selfclose` close-instant re-verify `:6482`. `grep -rn 'pin_still_live\|tty_now' tests/` = **0 hits** — no suite pins equality, so no existing test can go red *or* catch a regression. Ancestry is strictly weaker than equality (equality is hop 0 of the `:2042-2046` walk), so W9b can only turn DEAD→LIVE on the gate that protects a close.
    **FIX** W9b ships both directions: the stated LIVE fixture (nested pty) **and** a still-DEAD fixture (a pid on an unrelated tty with no ancestor owning the pane tty), plus an explicit note that `successor_pin`'s two other consumers inherit the widening.

16. **CLAIM** wave-table file lists.
    **VERDICT** PARTIAL — one named file does not exist; two affected suites are unnamed.
    **EVIDENCE** `tests/lr-transplant.bats` is absent (W11 names it as an edit target). The suites that exercise the paths W10/W11 change and are not listed: `tests/lr-reset-poller-inplace.bats`, `tests/lr-handoff-close-source.bats`, `tests/lr-resume-tombstone-guard.bats`, `tests/handed-off-session-guard.bats` (the last three `grep -l lr-transplant`).
    **FIX** Mark `tests/lr-transplant.bats` "(new)" like `handoff-remote-pane-term.bats`, and add the four suites above to W10/W11's gate list.

17. **CLAIM** residual anchors, re-grepped at `79e4b8d18`.
    **VERDICT** PARTIAL — five are off by 1-3 lines; the rest verify.
    **EVIDENCE** Correct: `handoff-fire.sh` `:1686` `:2024` `:2081` `:7415` `:7478` `:9247` `:9259` `:9260` `:991` `:1561` `:1533`; `lr-fleet.sh` `:186` `:199` `:699-716`; `lr-handoff.sh` `:203-240` `:764` `:893-901`(location); `lr-lib.sh` `:226` `:450`; `lr-reset-poller.sh:902-904`; `cc-in-kitty:75` `:101`. Off: `:2036` → `as_tty` is `:2037`, the refusal `:2039`; `:2038-2046` (the ancestry walk) → `:2041-2046`; `lr-fleet.sh:684-695`/`:688-695` → the write is `:692-695`; `lr-handoff.sh:809-812` → the block is `:809-814`; DoD `terminal-pin-order.bats:140-214` truncates the final `@test` at `:214-219`.
    **FIX** Correct the five; keep `:2041-2046` distinct from `:2038` so W9b lifts the walk and not the empty-tty guard.

**17 items: 6 refuted, 10 partial, 1 stands.**
