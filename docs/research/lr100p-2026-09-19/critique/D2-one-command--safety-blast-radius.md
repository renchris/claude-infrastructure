# D2-one-command — critique, lens: safety-blast-radius

Critic: adversarial, read-only. Design: `scratchpad/lr/design/D2-one-command.md`. Ground truth: `scratchpad/lr/research/U01–U14`.
Repo paths relative to `/Users/chrisren/Development/claude-infrastructure`. Every claim is `file:line` or `<command> => <output>`; guesses are labelled.

## 0. Verdict in one paragraph

D2's central safety claim — *"TRANSPLANTED is the only irreversible edge … so 'transplanted but never relaunched' needs a genuinely new fault"* (D2:129-133) — rests on a mechanism that does not exist in the tree (`CC_ADMIT_BUDGET_KEY`, D2:217-219), and under the design's own `--all` fan-out the shared per-caller refusal counter reproduces today's husk arithmetic in both directions. Three further arms widen the blast radius beyond the operator's "one command" ask: the default-ON hook kick (C4) transplants before the composer gate can refuse, so an operator's held draft becomes a tombstoned husk unattended; the hook-kicked driver inherits `CLAUDE_CODE_SESSION_ID` and `lr-transplant.sh:97` then skips the source rename that every split-brain guard downstream keys on; and `cc-custody return` at DONE (C3) discharges an originator's custody over a peer that has merely resumed. The design does not land, deploy, or commit anything on behalf of a recovered session, keeps the shared checkout untouched, and its resolver, transplant lock, detach mechanism and refusal states are sound — those survive.

---

## 1. Refutations

### R1 · FATAL — `CC_ADMIT_BUDGET_KEY` does not exist; the `--all` concurrency guard is prose, and the shared counter husks and bypasses at once

**D2 claims** (D2:215-221): *"the refusal counter is keyed per run (`CC_ADMIT_BUDGET_KEY=<id>` → `_cc_admit_state_file` at `capacity-admit.sh:509-514` keys `<caller>.<key>.refusals`) so one run's release cannot reset another's"* — stated as existing behaviour, and C5 (D2:253) exports it into the launcher. No C-item lists a change to `capacity-admit.sh:509-514`.

**Evidence:**
- `grep -rn 'CC_ADMIT_BUDGET_KEY\|CC_ADMIT_NET_ZERO' scripts bin hooks tests` => *(no output)*. Neither variable exists anywhere.
- `scripts/lib/capacity-admit.sh:509-514` `_cc_admit_state_file() { … printf '%s/%s.refusals' "$dir" "$1"; }` — keyed on the CALLER string alone. U05 §1.2 ("State file keying is the first defect") and U05 P3 propose the `[.<CC_ADMIT_BUDGET_KEY>]` suffix as a FIX; D2 cites it as shipped.
- `capacity-admit.sh:360-373` `cc_hw_budget_charge`: `n=$((n+1)); if [ "$n" -gt "$budget" ]; then : > "$sf"; return 10; fi` — one integer per caller, reset on every release; `:516` `_cc_admit_reset` zeroes it on every admit.

**Why it is fatal on this lens.** With C5's `CC_ADMIT_BUDGET=1` and C7's `attempts = budget+1 = 2`, and ONE shared `lr-fire-resume.refusals` file, run `cc-lr --all` over five sids (D2:216 "fires N drivers at once"). Five launchers hit the gate within seconds of each other. Walk the counter: A refuses (n=1) · B releases (n=2>1 → admit, reset to 0) · C refuses (n=1) · D releases (admit, reset) · E refuses (n=1). Retypes ~20 s later: A releases (n=2, admit) · C refuses again (n=1 — E's refusal reset nothing, but A's admit did) · E releases. **B and D were admitted without ever being refused themselves** (a bypass of the bound they were meant to spend); **C was refused twice and is a `FAILED-RELAUNCH` husk** — the exact "counter position, not load, decides" mechanism of U01 §5.3 / U02 §0 / U05 §3.4, now reachable inside D2's own concurrency model. This refutes D2 §2 invariant 1 (D2:129-133), §4.4 row 4 ("this becomes a page-and-admit, not a failure", D2:454) and §5 acceptance row 8 ("husks 0", D2:484). The design's headline "4 of 5 husks were one off-by-one … three export lines close it" (D2:18-21) is true only for a SERIAL fleet, and D2 makes the fleet concurrent.

**Repair (for the synthesis, not for me to do):** ship the `_cc_admit_state_file` keying change (U05 P3) as a named C-item with T2's ratchet, or refuse `--all` until it lands.

### R2 · MAJOR — the design transplants BEFORE the composer gate can refuse, and C4's default-ON kick makes that unattended: a held operator draft becomes a tombstoned husk with the draft in it

**D2 claims** (D2:456): *"pane never reaches a shell (held draft, modal) → `EXITING +Ns` then `FAILED-EXIT` at 600 s → a human answers the pane; `repair --from EXITED`"* — and (D2:243-245) *"Default is on"* for the hook kick, with (D2:508-509) the composer-draft gate kept "so an operator's half-typed message is never `/exit`ed over".

**Evidence that the gate refuses AFTER the irreversible step:**
- `scripts/limit-recover/lr-handoff.sh:512-519` runs `lr-transplant.sh` (lock + tombstone + rename); `:633` then calls `handoff-fire.sh --recycle …`. Ordering is stated as deliberate at `:605-611`: the tombstone IS the admission evidence for typing `/exit`.
- `scripts/handoff-fire.sh:2419-2430` `recycle_composer_gate` returns 1 (held) at expiry with content; `:11634-11636` — *"An OPERATOR's held draft DEFERS the recycle — bounded wait, then a loud refusal that leaves the session alive and the draft intact"*.
- `lr-handoff.sh:645-652` on any non-zero handoff-fire rc: *"the recycle did NOT verify … The transplant is DONE — session … the source pane is a tombstoned husk (handed-off-session-guard blocks its prompts)"*, exit 4.
- `hooks/handed-off-session-guard.sh:1-3,60-67`: UserPromptSubmit, exit 2 blocks the prompt when `<sid>.HANDOFF.json` exists beside the transcript.

**The scenario, end to end, with nobody typing a command.** Operator is mid-draft in pane P. The turn dies on a 429. `StopFailure` fires (U10 §1c, sub-second). C4 writes the request and kicks `cc-lr`. Driver: RESOLVED → TARGETED (charges `--assign`) → ADMITTED → BUNDLED → **TRANSPLANTED** (~3 s after the limit, D2:157). handoff-fire's composer gate reads the draft, waits 180 s, refuses. Driver marks `FAILED-EXIT` and pages. The operator finishes their sentence and presses Enter: the guard blocks it. Their session is alive on the dead account, tombstoned, with a successor copy on another account that nothing has started. That is the 2026-08-16 split-brain shape the guard was written for (`handed-off-session-guard.sh:5-12`), manufactured by the recovery itself, in the pane the operator is using, 3 s after a limit they may not have read yet. D2's own state table (D2:103) draws `TRANSPLANTED → EXITED → FAILED-EXIT` and calls the pre-TRANSPLANTED region "nothing changed on failure" — the composer state is checked in the region AFTER it.

**Why default-ON is the multiplier.** The operator's brief asks for *"one command … to identify that session and pane, and self-recycle it"* — operator-initiated. D2 §1.4/C4 make it zero-command by default (D2:243-245). A human running `cc-lr 117` has looked at pane 117; a hook has not. The kill switch (`auto.off`) is reversible, but the default polarity is the blast radius.

**Repair:** either (a) probe the composer (`composer_content`, `handoff-fire.sh:2392`) in the driver's PRE-irreversible region and refuse at `REFUSED-EXIT` before the transplant, or (b) transplant with `--keep-source` (`lr-transplant.sh:23,97`) and write the tombstone/rename only after `EXITED`. (a) is ~5 lines and keeps the existing ordering rule intact for the /exit itself.

### R3 · MAJOR — the hook-kicked driver inherits `CLAUDE_CODE_SESSION_ID`, and `lr-transplant.sh:97` then skips the source rename every downstream guard keys on

**D2's C4** (D2:233-235): `"$HOME/.claude/bin/cc-lr" "$SID" --from-hook >/dev/null 2>&1 &` from inside `hooks/stop-failure-marker.sh`, no `env -u`.

**Evidence:**
- Hooks see the session id in their environment: `hooks/session-continue.sh:144` `csid="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"` and `:170`; `hooks/dod-persist.sh:144,175`. *(Inference, labelled: these are Stop/UserPromptSubmit hooks; StopFailure is the same hook harness. Not separately measured on StopFailure.)*
- `detach()` at `handoff-fire.sh:1612` (`subprocess.Popen(…, start_new_session=True)`) — a new session, not a new environment; env is inherited through `cc-lr → lr-drive → lr-handoff → lr-transplant`.
- `scripts/limit-recover/lr-transplant.sh:96-100`: `if [[ $KEEP_SOURCE -ne 1 && "${CLAUDE_CODE_SESSION_ID:-}" != "$SID" ]]; then mv "$SRC" "$SRC.handed-off"; SOURCE_RETIRED=1; fi` — with the hook's env, `CLAUDE_CODE_SESSION_ID == SID`, so the source is NOT renamed (the guard exists for the self-recovery form, where the live harness still appends by path).
- Consequence downstream: `handoff-fire.sh:6763` `if [ -n "$RCY_SRC_TX" ] && [ -f "$RCY_SRC_TX" ] && [ -f "$RCY_SRC_TX.handed-off" ]` — the fold arm requires the `.handed-off` file and is inert; the FULL transcript stays as a live-looking `<sid>.jsonl` on the dead account with a tombstone beside it. `lr-fleet.sh:217`'s DUPLICATE test and every `*.jsonl.handed-off` consumer (U04 §3 residual #2) now see a different shape than the one they were tested against.

**Blast radius:** a complete, un-renamed transcript under the source account is exactly what `cc-husk-sweep --resume` (U09 open Q2) or a cleared lock would resume into a second writer. Today's remote form renames it (all five `transplant.json` read `source_retired:1`, U02 §1); D2's default path would read `source_retired:0` on every hook-kicked recovery.

**Repair:** `env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_SESSION_ID` on the kick (one token), and pin it with SF-a asserting `source_retired:1`.

### R4 · MAJOR — `cc-custody return` at DONE discharges the ORIGINATOR's debt over a peer that has only resumed

**D2 claims** (D2:208): DONE runs *"`cc-custody return` if a custody debt names this pane"*; §2 table (D2:126) *"custody discharged if any"*.

**Evidence:**
- `bin/cc-custody:18` *"An OPEN row is discharged by a later return/abandon row matching its MARKER (unique per fire …)"*; `:107` key is `slug|targetPane`; `:182-232` `return <marker-or-slug>` appends a `return` verdict to the matched open row.
- `~/.claude/CLAUDE.md` § Session Close, CUSTODY arm: *"a fire that arms `--notify-back` records a DEBT keyed on the firing cwd; the peer's self-close discharges it. Open custody folds into the ledger as 🔧 — the ✅ certificate is mechanically unreachable over an unreturned wave"* and *"Awaiting ARMED is the legitimate non-close state; 'done' is not."*
- U10 §3b (which D2:464 cites for the fired-peer row) says the opposite of D2's DONE step: *"A recycle-in-place is exactly what preserves its pane, worktree and `--notify-back` custody; killing it would strand a `cc-custody` debt."* Preserving the debt is the point; returning it is the strand.

**Blast radius:** the originating lead's `wrap-ledger` reads the wave as returned, its `✅ SAFE TO CLOSE` becomes reachable, and the peer's actual completion later finds "no OPEN row matches — nothing discharged" (`cc-custody:232`, rc 0, stderr only). This lands a false close-certificate on a session the recovery never touched.

**Repair:** never `return`; if cc-lr fires anything with `--notify-back` of its own, discharge only its OWN marker.

### R5 · MAJOR — two drivers per request: the W3→W4 window, and C4+C10/C11 after it; no per-sid run mutex exists in the state store

**D2 claims** (D2:27-29) *"one state machine, one state store, one detached driver"*; (D2:215) *"N runs are independent except for the per-sid lock (`lr-transplant.sh:60`)"*; (D2:346-347) *"Until [C11] lands, C4's direct kick covers the latency and the poller's 600 s tick is the belt."*

**Evidence:**
- `scripts/limit-recover/lr-reset-poller.sh:646-661`: `for _rq in "$REQUESTS"/*.json; … "$FLEET" --one "$_rq_sid" … ; rm -f "$_rq"` — drains every request file with NO check of any run state. D2 §4.2 (D2:409) keeps `requests/<sid>.json` on disk until DONE.
- Landing order D2:555-561: W3 (`cc-lr`, writes requests) lands before W4 (C10, C11). Between them the OLD poller drains a request `cc-lr` is already driving → a second `lr-fleet --one` on the same sid inside a ≤600 s window. After W4, C10 runs `cc-lr <sid> --from-request` on a request the hook already kicked with `--from-hook`; with C11 `WatchPaths` the two fire within the same second. D2 nowhere says `--from-request`/`--from-hook` checks `runs/` for a non-terminal run of that sid.
- The transplant lock is check-then-write, not O_EXCL: `lr-transplant.sh:63-69` tests `-e "$LOCK"` then `printf … > "$LOCK"` six lines later.

**Blast radius, bounded and unbounded parts.** Bounded: the second driver reaches `lr-transplant` and is refused by `:55-57` (destination exists) or `:63-66` (lock) → `lr-handoff` exits under `set -euo pipefail` (`:58`) before `handoff-fire --recycle`, so **no second `/exit` is typed** — this is a genuine keep (K2). Unbounded: the second driver has already charged `--assign` (D2:204 — a phantom that walks the ranking down for 15 min, `bin/claude-accounts:1732`), written a `FAILED-*` row, and paged the desk (D2:209) — one spurious page and one wrong-direction routing charge per recovery, systematically. And in the sub-second race (two drivers between `:63` and `:69`), both proceed: two `cp -p` of the same source into possibly two targets, two tombstones, one rename — a real two-writers-on-one-uuid, low probability, non-zero under `--all` + WatchPaths.

**Repair:** a `runs/<sid>.lock` taken with `set -C` (the same idiom D2 already uses for `requests-latch`, D2:227) before RESOLVED; `--from-request` and `--from-hook` abstain on it.

### R6 · MAJOR — the explicit-ref path has no teammate guard; `cc-lr <pane>` will transplant an Agent-Teams assignee the lead owns

**D2 claims** (D2:464): teammate handling lives in *"C4 classification"* (the hook); §1.1 resolver reads registry rows.

**Evidence:**
- `grep -n 'agentName\|teammate\|TEAMMATE\|agent_assignee' scripts/limit-recover/lr-handoff.sh` => one hit, a comment at `:100`. `lr-handoff` — the callee D2's driver invokes directly (D2:206) — has no teammate refusal.
- The only teammate tests in the chain are `lr-fleet.sh:211` (the census D2 bypasses — C8 keeps it as "the compat surface", D2:305) and D2's C4 hook arm. Registry rows carry no `agentName` (`hooks/session-register.sh:282-288` schema, U07 §4).
- U10 §3b on why it matters: *"an unattached `--resume` detaches the inbox/agentName wiring and duplicates the lead's respawn."*

**Blast radius:** an operator (or a lead's `/limit-recover 133` reading a teammate pane's statusline, which D2's C12 will now label just like a lead's) transplants a teammate onto another account; the lead's team-aware recovery then respawns it → two assignees on one agent id. `cc-lr --all` is safe (requests come only from the guarded hook); the explicit ref is not.

**Repair:** C2 already opens the transcript for `lr_tier_from_transcript` (D2:192); add the `head -c 8000 | grep '"agentName"'` test there and refuse with `REFUSED-RESOLVE: teammate (lead-owned)`.

### R7 · MINOR — C12 requires a `settings.json` edit, contradicting §6's "no settings.json edit"

`jq -c '.statusLine' ~/.claude/settings.json` => `{"type":"command","command":"~/.claude/statusline.sh"}`. D2:356 *"Set `statusLine.refreshInterval: 5`"* is an edit to that object; D2:525-526 *"No new hook registration and no `settings.json` edit — both are c10"*. The override is not explicit as an operator c10 step. Move it beside C11.

### R8 · MINOR — `CC_ADMIT_NET_ZERO=1` in the LAUNCHER is permissive by one, and §6's "ceiling 8 untouched" is not true for this caller

`capacity-admit.sh:832` `elif [ $(( act + 1 )) -gt "$act_ceiling" ]` over `cc_sp_active`, which charges liveness on `(pid,lstart)` (U05 §4.1). At PROBE time (before `/exit`) the dying session's pid is alive and counted, so `+0` is the correct net-zero (U05 §4.2). At LAUNCHER time the `/exit` has already run; the old pid is dead and NOT in `act`, so `+0` under-counts the replacement by one — ceiling 8 reads as 9 for every concurrent launcher. Combined with `CC_ADMIT_BUDGET=1` (refuse once, then admit + page — `capacity-admit.sh:948-953`), the active ceiling is a page threshold, not a bound, for `lr-fire-resume`. `capacity-admit.sh:790-800` says 8 *"is a gate-threshold change and needs its own evidence and its own decision"*. Precedent softens it: `capacity_gate` already runs budget 1 (`:373-375`, U05 P3a) and the box's REAL load is net-zero (the husks it counts are dead TUIs). But D2 §6 (D2:505-507) claims the ceiling is untouched; it should instead state the policy: *for the recovery caller the active ceiling pages and admits.* Export `NET_ZERO` on the probe only.

### R9 · MINOR — `session-continue.sh clear` from the launcher clears and spends a SIBLING's continuation lever

D2 adopts U12 §6.1 clause D via C14 (D2:378-379). `hooks/session-continue.sh:156-172`: `clear` resolves `sentinel_for "$PWD"` — keyed on (config-dir|cwd), `:19` — removes it, and **unconditionally** writes `${f}.mech` spending `CC_MECH_MAX` for that cwd (*"UNCONDITIONAL on purpose: the mech budget is a property of THIS cwd"*). Run from the launcher under the TARGET cfg, that is the sentinel + mech budget of every session on the target account in that cwd — today 4 sessions share `claude-tertiary` + `claude-infrastructure` (U14 §3.2). A sibling's armed 🔧 chain is disarmed by a stranger's recovery. Run it inside the recovered session (the spec's original locus) or not at all.

### R10 · MINOR — `status --sweep` keys driver liveness on `kill -0 <pid>`; a reused pid hides a dead driver forever

D2:168-169, :461. `docs/lessons/a-stale-pid-does-not-decay-into-harmlessness-it-decays-into-a-gu.md` — key it on the KIND. The registry already uses `(pid, lstart)` (`session-register.sh:278`); the run's `state.json` should record `lstart` too, or the sweep's `FAILED-DRIVER-DIED` arm (D2:111) is unreachable on the box's 1,694-pid history (U05 §4.3).

### R11 · MINOR — `FAILED-PANE-GONE → repair --replace → lr-handoff --launch` cannot run as written, and if made to run needs `--no-transplant`

D2:457. `lr-handoff.sh:512` runs the transplant unless `--no-transplant`; on a moved sid it is refused (`lr-transplant.sh:63-66`) and `set -e` (`lr-handoff.sh:58`) exits. The repair must pass `--no-transplant --launch`; D2 does not say so. The vanish verdict itself is well-guarded — `pane_enumerated` (`handoff-fire.sh:2194-2221`) answers `absent` only from a SUCCESSFUL listing carrying other panes, `unknown` on any transport error — so a truncated `kitty @ ls` (U07 §5, rc 1) cannot mint a false VANISHED; the two-writer path through this arm is not reachable on the evidence. Underspecified, not unsafe.

### R12 · MINOR (guess, labelled) — the hook's `&` child may not survive the hook's exit

D2:233-234 backgrounds `cc-lr` with `&` from a 10 s-budget hook and relies on `cc-lr` reaching its own `setsid` (D2:237-238). `handoff-fire.sh:1600-1607` documents CC SIGKILLing a Bash TOOL call's process group; whether the hook harness does the same at hook exit is **unmeasured**. If it does, the request is written and no driver exists until the 600 s poller tick — the belt holds, the "~0 s path" does not. Cheap fix: `setsid`/`detach()` the kick itself.

---

## 2. Direct answers to the lens question

| question | answer | where |
|---|---|---|
| `/exit` a pane it cannot relaunch? | **Yes, two ways.** R1 (shared counter under `--all` refuses twice → husk) and R2 (transplanted, then the composer gate refuses the /exit → alive-but-tombstoned). | R1, R2 |
| Two writers on one uuid? | Bounded by the transplant lock in the common case (K2), **but** R3 leaves a full un-renamed transcript on the source, and R5's check-then-write lock has a sub-second race under `--all`+WatchPaths. | R3, R5, K2 |
| Bypass the capacity gate so the box can thrash? | Not thrash — the recovery is net-zero for the box — but the active ceiling becomes page-then-admit for this caller and R1 lets some launchers admit with no refusal spent. Stated policy would make it acceptable; §6 claims the opposite. | R1, R8 |
| Type into a pane the operator is using? | Never types INTO a draft (composer gate kept, K5). But R2 makes the operator's pane a husk under them, and R9 disarms a sibling's continuation. | R2, R9 |
| Touch teammates the lead owns? | **Yes** on the explicit-ref path. | R6 |
| Land/deploy a recovered session's work? | **No.** `grep -n 'git \(checkout\|switch\|worktree\|reset\|stash\|commit\|push\|pull\|merge\)' scripts/limit-recover/lr-fire-resume.sh scripts/limit-recover/lr-handoff.sh` => *(no output)*; DONE (D2:208) is `rm`/`mv`/`lf_row`/notify only. The one false "landing" is custody (R4). | K3, R4 |
| Shared checkout never committed in? | **Respected.** All state under `~/.reso/limit-recover/` and `runs/` (D2:407-425); U11 §5's commit-on-main was the LEAD's, and D2 removes the lead's polling turns. | K3 |
| Every override explicit and reversible? | Mostly (`${CC_ADMIT_LOAD_TERM:-off}`, `${CC_ADMIT_BUDGET:-1}`, `auto.off`, `CC_ROUTE_RECOVERY=off`). **Not:** `CC_ADMIT_NET_ZERO=1` is unconditional (D2:251), `CC_ADMIT_BUDGET_KEY` is inert (R1), `refreshInterval` is an undeclared settings edit (R7), and the `--assign` guard fork "one of the two, not both" (D2:302-303) is left open. | R1, R7, R8 |

---

## 3. Keeps — what survives this lens

- **K1 · setsid detach.** `handoff-fire.sh:1608-1616` `detach()` with `start_new_session=True` is the measured survivor of CC's group SIGKILL (`:1600-1607`). `hooks/validate-bash.sh:191-342` keys its live-`/goal` deny on `run_in_background` + command position; a foreground `<2 s` `cc-lr` is not in its class. D2 §4.1 is correct.
- **K2 · The irreversible step is serialised.** `lr-transplant.sh:55-57` (destination exists) + `:63-66` (lock exists) refuse a second transplant; `lr-handoff.sh:58` `set -euo pipefail` means the refusal exits before `:633`'s `handoff-fire --recycle`. A duplicate driver never types `/exit`. (Race at `:63-69` noted in R5; sub-second.)
- **K3 · No git, no land, no deploy on the recovery path.** grep above; state directory outside every repo; `--branch` on `lr-fire-resume` performs no checkout. Iron rule 7 (U09 §3) holds.
- **K4 · Refuse-on-ambiguity resolver** (D2:54-57, U07 §6c rule 4) and INDETERMINATE-on-kitty-timeout (D2:59-63, U07 §5). The wrong-pane failure is unreachable by construction.
- **K5 · The composer-draft gate is kept, only its quantum moves** (D2:508-509; `handoff-fire.sh:11634`). Nothing is ever pasted into an operator's draft. (Ordering defect is R2, not this.)
- **K6 · The watcher's vanish arm is three-state** (`handoff-fire.sh:2194-2221`): `absent` only from a successful listing with other panes. A flaky socket costs time, never a false "gone".
- **K7 · `lr-fire-resume`'s tombstone check** (`lr-fire-resume.sh:298-303`) and `handed-off-session-guard.sh` stay as enforcing stores; D2 §6 explicitly keeps the guard.
- **K8 · C10's `lr_transplanted_to` necessary-not-sufficient fix** (D2:331-335) — corrects the anti-sweep at `lr-reset-poller.sh:902-905` in the right direction; the `mv parked → resumed` mirrors `:904` and the poller's marker stays event-keyed via `:777-784`.
- **K9 · Reset-wait stays as the fallback**, not the first branch (D2:340-341, 512-513); REFUSED-TARGET on ranker rc 2 (D2:452) fails closed.
- **K10 · Recovery-lane floors are tighter, never looser** — `RECOVERY_S_CEIL 0.60 < S_CUT 0.85` (U13 §3b); `CC_ROUTE_RECOVERY=off` is byte-identical pre-U13 (U13 §5 kill-switch test).
- **K11 · C4's classification helpers exist**: `hooks/lib/agent-identity.sh:33 agent_assignee_argv`, `hooks/lib/origin-identity.sh:237 oi_origin_class`; the `requests-latch/<sid>.<death_uuid>` `set -C` latch (D2:227-228) is event-keyed per U10 §2d and LR-i.
- **K12 · No new hook registration**; C4 rides the `StopFailure` hook already registered in all five config dirs (U10 §1c); hook fail-open contract preserved (D2:239-240, `stop-failure-marker.sh:31-33`).
- **K13 · U05 P2 token deferral is stated with its reason** (D2:514-518) rather than silently dropped — the residual is named. (R1 shows the residual is larger than stated.)
- **K14 · Every FAILED-* state carries a `repair` verb and a cause joined from the IDL** (D2:449-464) — the fault-visibility half of the operator's ask is designed correctly; R1/R2 are about which states are REACHED, not whether they are named.
