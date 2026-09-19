# D3-identity-observability — critique, lens: fault-tolerance

Critic: adversarial, read-only · 2026-09-19 · inputs: `scratchpad/lr/design/D3-identity-observability.md` (463 lines) and U01–U14 under `scratchpad/lr/research/`, plus re-reads of the live tree at `/Users/chrisren/Development/claude-infrastructure`. Every claim below is `file:line` or `<command> => <output>`; a claim I could not measure is marked **GUESS**.

## 0. Verdict in three sentences

D3 makes today's husks **visible** — the state record, the `failed:*` disposition and the `hf_alarm` on the no-process branch are real improvements and survive this critique. It does **not** make them **re-drivable**: on the four paths a fault actually takes (a hot box while the operator is present, a held draft, a re-limit on the target, a watcher that outlives its watchdog) the design either parks with the WRONG name, refuses its own re-drive, or produces the duplicate writer it was built to prevent. And its central concurrency claim — `recover --all` ≈ max(single) — fails by construction on the exact shape of every fleet limit event, because the five limited sessions count themselves against the `reserve-active` term the design leaves untouched.

## 1. Every step, what happens when it fails or hangs

| # | step (D3 state) | writer | if it fails / hangs | VISIBLE? | RE-DRIVABLE from here? | verdict |
|---|---|---|---|---|---|---|
| 1 | `cc-lr find` → `located` | driver (fg) | kitty RPC 10 s timeout with corrupt payload (U07 §5) → INDETERMINATE by design; registry pid reused after reboot reads ALIVE (`kill -0` only, D3 §C2 rule 4 — the row carries `lstart` for exactly this, U07 §4) | yes (refuse) / **no** (a reused pid is a false ALIVE) | yes | minor — R12 |
| 2 | detach `lr-fleet --one` + `lr-watchdog` | driver | driver dies between `located` write and detach → doc at `located`, no `watchdog_pid` field; poller `§0b` adopts "watchdog_pid dead" — a MISSING field is not specified as dead | partial | after ≤600 s poller tick, if missing≡dead | minor |
| 3 | `targeted` → probe `lf_capacity_wait` (60 s) | lr-fleet | probe refuses on `reserve-active` — the term D3 does not touch (`capacity-admit.sh:834-840`), which counts the limited sessions themselves (`kind:"prompt"` beats over live pids, U05 §4.1; Stop never fires on a limit, U10 §1a 5/5). Probe is non-charging AND non-releasing (U01 §2.2). 60 s → `PARKED` → **no state exists for a capacity park** (D3 §3.1 has none; §3.4 lr-fleet writes only `targeted, transplanted, parked:no-target, failed:transplant:*`) | **misnamed**: watchdog fires `stalled:targeted` at 10 s with the RANK repair → `parked:no-target` + page for a capacity fault | `cc-lr recover` REFUSED while the run is non-terminal (D3:180); nothing else re-probes | **fatal — R1** |
| 4 | `transplanted` | lr-fleet via lr-handoff | irreversible; runs at `lr-handoff.sh:517`, BEFORE `handoff-fire` at `:628` | yes | n/a | keep |
| 5 | composer gate (fg `recycle_fire`, 180 s) | — (D3 says the WATCHER writes `exit-deferred`; the gate runs in the FOREGROUND before `detach`, U04 §1 F2 < F4) | rc 1 after 180 s → `handoff-fire.sh:11655-11667`: pages, **`exit 1`** — a REFUSAL, not a wait. Transplant already done (step 4). Pane = live CC on the limited account with its transcript renamed `.handed-off`, prompts blocked by `handed-off-session-guard.sh` (U02 §2c) | yes (`recycle-held-draft` event + 2 notifies) | **no**: re-run → `lr-transplant.sh:63-66` REFUSED lock exists; `:55-57` REFUSED destination exists | **fatal — R2** |
| 6 | `exited` (watcher, `HF_RECYCLE_SHELL_WAIT_S` 600) | watcher | slow teardown / bgwork dialog (`handoff-fire.sh:6613-6615`, nudges at 60/150/300 s) → D3 budget 30 s → `stalled:exited` → watchdog repair "re-send /exit once" **while the watcher's own `recycle_nudge_decision` is deciding the same thing** (`:6682-6689`, `:2435+`) | yes | two actuators on one composer | major — R3 |
| 7 | `relaunched` → `refused:capacity` | watcher / launcher | budget=1 + token: attempt 2 releases (`cc_hw_budget_charge`, `capacity-admit.sh:366-375`) **and pages** on every non-token refusal (`_cc_admit_page`, `:535-542`). `pane_cc_state` = `unknown` (7 branches, `handoff-fire.sh:3532-3576`) → retype skipped → watcher writes `failed:relaunch:*` (D3 §C5.5) — a TERMINAL state → watchdog "if terminal → exit" (D3 §C8) → the "every 30 s retype" repair NEVER RUNS on the path that needs it | yes (state + alarm + notify) | only by hand (`cc-lr repair`); C13's notify text "watchdog retrying every 30 s" describes a loop the watchdog has already left | major — R3 |
| 8 | `alive` → `submitted` | launcher (expect) | READY never matches → C6 quiet-pty injects Ctrl-U+prompt+CR after 8 s of silence **into whatever is on the pty** — a parked menu included (`lr-fire-resume.sh:501-503` returns 0 "sent NOTHING", caller `exp_continue`s at `:546`) | yes | — | major — R6 |
| 9 | `submitted` → `engaged` (C7 token oracle) | watcher | target account ALSO limited → assistant record is `isApiErrorMessage` → excluded → `stalled:submitted` → 90 s → `failed:submitted:watchdog-gave-up`. The hook (C3) SKIPS a request when `locks/<sid>.lock` exists (D3:196); `lr-transplant` refuses on the same lock. **No second hop exists** | yes, misnamed (says "engaged-timeout", cause is a re-limit) | **no** | major — R5 |
| 10 | `engaged` → `resumed` (+ `cc-notify` receipt) | watcher | requester pane dead/recycled → `reason=target-not-live` (`bin/cc-notify:277`) → does `resumed` still write? unspecified → `stalled:engaged` alarm on a working session | yes (wrong) | n/a | minor — R13 |
| 11 | any state, watchdog ceiling 300 s | watchdog | watcher's own caps are 600 (shell) + 180 (draft) + 180 (engage) = 960 s > 300+60. Watchdog writes `failed:<state>:watchdog-gave-up`, notifies FAILED **with the manual launcher command**, exits; the watcher continues and later writes `alive/engaged/resumed` OVER the terminal state. Operator runs the manual command → **two `claude --resume <sid>`** on one transcript (U01 §1.3 shows two resume processes are possible; the lock is per-transplant, not per-process) | yes — contradictory | **produces the duplicate writer** | major — R3 |
| 12 | run doc concurrent writes | 4–5 processes | `lr_state_set` = read → jq append → tmp+mv (D3:111). No lock. Watcher and watchdog read-modify-write the same doc at the moment a budget boundary coincides with a legit transition → lost `states[]` entry; the watchdog then acts on the stale state it re-reads | no | — | minor — R10 |
| 13 | state write itself | any | `|| true` at every call site (D3:113). Unwritable `~/.reso/limit-recover/recoveries/` → the whole spine goes dark **silently**; the watchdog reads a doc that never advances and fires `stalled:*` repairs against a run that is actually progressing | **no** | — | minor — R10 |
| 14 | hook C3 → `located` | stop-failure-marker | writes a `located` run + `by-pane/<pane>` with no watchdog. Operator's `cc-lr recover <pane>` → D3:180 **REFUSED** ("run not terminal"). Poller drain (`lr-reset-poller.sh:657`) calls `--one` WITHOUT `--run` → the real recovery has no run doc, `cc-lr find` shows `recovering(<run> located)` over an engaged session | yes, wrong | refused | major — R4 |
| 15 | hook-originated alarms/pages | watchdog | `requested_by.pane` for a hook run = the LIMITED pane's own `$KITTY_WINDOW_ID` (D3:198) → every `cc-notify` for that run is addressed to the victim (memory `dead-session-verdict-belongs-in-the-pane`) | no owner | — | major — R4 |
| 16 | `recover --all` target pick | 5 × lr-fleet | 5 detached `--rank --recovery` all read the 90 s cache before any `--assign` lands (`bin/claude-accounts:170`: the flock is process-level single-flight on the cache, "nothing here is a cross-process guard") → 5 picks stack on rank[0] | recorded (C10) | — | major — R9 |
| 17 | poller adopt after reboot | poller `§0b` | `~/.reso` survives, processes and `$TMPDIR` launchers do not (U04 §3 #8-9); kitty renumbers windows → adopted watchdog's repair types `cd … && nocorrect bash <gone launcher>` into whatever fresh shell now holds pane N. C8 repairs carry no pane→sid re-binding (`lr-handoff.sh:266-284` does it at FIRE time only) | no | wrong pane | major — R8 |
| 18 | C11 fast-path ingest | launcher | trusts `audit.json` `spawned==settled` — on pane 114 that read 16/16 while handoff-fire's `live_subagents_of` counted 1 in flight and KILLED it (`handoff-fire.sh:4900`; both artifacts below). The one-line prompt says "nothing is owed and nothing re-runs" | **no** | no (certified clean) | major — R7 |

## 2. Refutations

### R1 — FATAL — the fleet parks by construction, and the park has no state, wrong name, wrong repair

**Claim refuted.** D3 §C4: "with the load term off, what remains (headroom 4 GB, segments 50 %, active ≤ 8, reserve) is a genuinely hot box, and a 60 s park is the point at which the watchdog's repair loop (C8) takes over on a 30 s cadence"; §C2: "`recover --all`: N concurrent runs … turns 5 × 150 s into ≈ max(single)"; §8 "fleet wall (5 concurrent) ≤ 60 s".

**Why it fails.**
1. `CC_ADMIT_NET_ZERO=1` is specified against `:832` only (D3:230; U05 §5.5(i) diff is `:832` only). The `reserve-active` term at `capacity-admit.sh:834-840` still evaluates `act + 1 > ceiling − reserve` whenever the operator is `present`.
2. `act` counts every session whose latest beat is `kind:"prompt"` with a live `(pid,lstart)` (`spawn-presence.sh:298-390`, U05 §4.1). A limited session's beat stays `prompt` because Stop does not fire on a limit (U10 §1a, 5/5) and its `claude` stays alive — measured now: `cd ~/.claude/cc-beats && jq … e442434c* 28f07827*` => `prompt pid=99916 pane=121`, `prompt pid=63305 pane=114`. **So N limited sessions contribute N to `act`.** Five limited + the lead mid-turn + one working session = 7 → `7 + 1 > 7` → refuse. Measured today, verbatim from `~/.claude/autonomy/idl.jsonl`:
   ```
   17:17:43Z refuse reserve-active 7 sessions mid-turn + 1 > active ceiling 8 − operator reserve 1 = 7 (operator present) (probe — budget untouched)
   17:18:04Z / 17:18:25Z / 17:18:47Z  (same)
   17:19:45Z admit  … 4 sessions mid-turn
   ```
   and the 17:19:45 admit read "4" only because the operator's third attempt ran `CC_SP_ACTIVE_OVERRIDE=4` (U11 §3, pane 112, 12:19:07). Nothing had `/exit`ed yet; the real count was still ≥7. **D3 has no override and does not touch the term, so the 17:19:45 admit does not replay.**
3. The probe is non-charging AND non-releasing (`capacity-admit.sh:925-931`, U01 §2.2). A refusing probe can only be rescued by an unrelated Stop lowering `act` — and in `recover --all` all five probes run BEFORE any `/exit`, so no recovery can lower the count for another. Sequential recovery today self-healed only because each `/exit` killed one `prompt` beat's pid; concurrent recovery removes that accident.
4. On PARKED there is **no state**: D3 §3.1 enumerates none for a capacity park and §3.4 gives lr-fleet only `targeted, transplanted, parked:no-target, failed:transplant:*`. The doc sits at `targeted` (budget 10 s) while `lf_capacity_wait` legitimately runs 60 s (`LR_FLEET_CAP_IVL_S` 5 × cold `cc_sp_active` 7.2 s, U05 §4.3, is closer to 96 s). The watchdog fires `stalled:targeted` at 10 s and applies the C8 repair for `targeted` — "re-rank once → `parked:no-target` + page". The operator is paged that there is NO TARGET when the fault is `reserve-active`. The "watchdog takes over on a 30 s cadence" has no mechanism: the only capacity repair in the C8 table is "retype the launcher", and no launcher exists before the transplant.
5. `cc-lr recover <pane>` is REFUSED while the run is non-terminal (D3:180). The operator can neither re-probe nor override for up to 300 s.

**Severity: fatal.** It breaks the design's headline concurrency claim on the ONE shape a fleet limit event always has (the limited sessions are alive, `prompt`-beated, and count themselves), it misnames the fault, and it blocks the manual re-drive.

**Evidence:** `capacity-admit.sh:834-840`; `spawn-presence.sh:298-390`; U05 §3.2, §4.1-4.2, §5.5; U10 §1a; U11 §3 (pane 112 attempt 3, `CC_SP_ACTIVE_OVERRIDE=4`); IDL rows above; D3:101 (budgets), :230, :233, :271-278.

### R2 — FATAL — a held draft after the transplant is a dead end, not a "named wait"

**Claim refuted.** D3 §3.1 `exit-deferred` = "composer held a draft; /exit NOT typed — a named wait, not a failure"; §3.4 says the WATCHER writes it; §8 (c) "a held draft in one composer → exit-deferred with the snapshot; nothing typed; clear the draft → proceeds"; I4 "nothing irreversible precedes an admission the launcher will honour".

**Why it fails.**
- The composer gate runs in the FOREGROUND `recycle_fire`, before `detach` (U04 §1: F2 precedes F4). After `CC_RECYCLE_DRAFT_WAIT` 180 s with rc 1 it does not wait — it REFUSES: `handoff-fire.sh:11655-11667` emits `recycle-held-draft`, pages the desk and the pane, prints "recycle REFUSED … Clear/send the draft, then re-run", and **`exit 1`**. There is no watcher to write `exit-deferred`; the process that could is gone.
- The transplant already ran: `lr-handoff.sh:517` (`lr-transplant.sh`) precedes `:628` (`handoff-fire`). D3 §9 keeps `lr-transplant.sh` unchanged and §C5 keeps the composer gate "unchanged" — it does not reorder. So after the refusal: lock held, tombstone written, source renamed `.handed-off`, and a LIVE claude on the limited account whose prompts are blocked by `hooks/handed-off-session-guard.sh` (U02 §2c). The operator's draft — the thing the gate protected — can no longer be sent from that pane.
- "clear the draft → proceeds" has no mechanism. The re-run is `cc-lr recover` → `lr-fleet --one` → `lr-handoff` → `lr-transplant.sh:63-66` **REFUSED — lock exists**, and `:55-57` **REFUSED — destination exists**. `failed:transplant:*`. The only exit is `--force`, which D3 never surfaces.
- I4 is therefore false on this path: the composer gate is a second admission (the pane's) that the irreversible step precedes.

**Severity: fatal** for the path; it is the one fault-injection arm (§8 c) the design lists as passing, and it cannot pass as specified.

**Evidence:** `handoff-fire.sh:11634-11667`; `recycle_composer_gate` `:2414-2427` (rc 1 = held, rc 2 = unknown, both refuse); `lr-handoff.sh:517, :628`; `lr-transplant.sh:55-66`; U02 §2a-2c; U04 §1 F2/F4; D3:67, :122, :249, :410.

### R3 — MAJOR — two actuators and two verdict-writers on one run; the FAILED notify manufactures the duplicate writer

**Claim refuted.** I2 "one record per run, one writer"; I7 "`DUPLICATE` means two live processes"; C13 "FAILED at relaunched … watchdog retrying every 30 s until 12:31 · manual: cd … && nocorrect bash <launcher>".

**Why it fails.**
1. **Ceilings disagree.** Watchdog lifetime = 300 + 60 s (D3 §C8, §5). The watcher it supervises keeps `HF_RECYCLE_SHELL_WAIT_S` 600 (D3:331 "stays as the watcher's own cap"), `CC_RECYCLE_DRAFT_WAIT` 180 (D3:332) and `RCY_ENGAGE_TIMEOUT` 180 (D3:246). A watcher legitimately inside its own bounds at 300 s (a bgwork dialog, `handoff-fire.sh:6613-6615`; teardown under load) gets `failed:<state>:watchdog-gave-up` written under it, the requester gets a FAILED notify with the manual launcher line, and the watchdog exits. The watcher then proceeds, relaunches, and writes `alive` → `engaged` → `resumed` OVER the terminal state, sending a second notify. If the operator acted on the first notify, there are now two `claude … --resume <sid>` on one transcript — the split brain the lock cannot see (it is per-transplant, `lr-transplant.sh:59-69`; U01 §1.3 shows the wrapper+leaf pair per resume, and two independent resumes would each present one).
2. **Repairs race the watcher.** C8's `relaunched/refused:capacity` repair retypes the launcher every 30 s; C5.4 keeps the watcher's own retype (`HF_RECYCLE_RELAUNCH_TRIES` 2). C8's `exited` repair re-sends `/exit`; the watcher's `recycle_nudge_decision` (`handoff-fire.sh:2435+`, checkpoints `:6682-6689`) decides the same thing at 60/150/300 s. Neither knows the other typed. The `at_shell` gate is NOT sufficient against this: `pane_cc_state` classifies the launcher's own `bash` prologue as `shell` for ~2 s (`handoff-fire.sh:3568`; U04 §5C says the ≥9 s floor and 2-consecutive-sample rule are "required, not cosmetic") and D3's C8 table carries neither rule.
3. **The retry loop is unreachable on the path that needs it.** C5.5 has the WATCHER write `failed:relaunch:<cause>` when `pane_cc_state` is `unknown` and the retype is skipped; `failed:*` is terminal (D3 §3.1); C8 "if state is terminal → exit". So the C8 row "relaunched / refused:capacity — every 30 s: at_shell → retype" only runs if the watcher has NOT yet given up — i.e. never in the case C13's notify text describes.
4. **No lock on the run doc.** `lr_state_set` is read → append → tmp+mv (D3:111). Two writers at a budget boundary lose an update. `ledger.jsonl` survives; the doc the watchdog reads does not.

**Severity: major** — (1) is deterministic, not a race, and it is the design producing the exact artefact ("duplicate writer") the question names.

**Evidence:** D3:113, :122, :246, :269-278, :317, :331-332, :344-345; `handoff-fire.sh:2435+, :3568, :6613-6615, :6682-6689`; `lr-transplant.sh:59-69`; U01 §1.3; U04 §1 (await bound vs composer gate), §5C.

### R4 — MAJOR — the hook's `located` run collides with the one command, bypasses the spine on the poller path, and pages the victim

**Claim refuted.** C3 "Also write the `located` state … so `cc-lr find` shows `limited · request written`"; C2 step 2 "Refuse if `by-pane/<pane>` exists and its run is not terminal"; C3 policy tier "the poller drains the request within seconds and the operator's screenshot finds a session already engaged".

**Why it fails.**
- The hook writes a run doc at `located` with `by-pane/<pane>` → it. `located` is non-terminal. The operator's `cc-lr recover <pane>` — the design's one command — is REFUSED by its own step 2 for every session the hook has already seen, i.e. every session once W4 lands. No adoption rule is stated.
- The hook detaches no watchdog (C3 does not say it does; a `StopFailure` hook has a 10 s budget). The `located` doc has no `watchdog_pid`; `§0b` adopts on "watchdog_pid is dead" — a MISSING field is unspecified. If adopted at the next 600 s tick: `stalled:located` (no repair) → 300 s → `failed:located:watchdog-gave-up`. Best case the one command is refused for ~15 min after a limit.
- The poller's request arm calls `"$FLEET" --one "$_rq_sid" … --from-daemon` (`lr-reset-poller.sh:657`) with no `--run`. D3 gives `--run` only to `cc-lr recover` (C2 step 4). So a poller-driven recovery writes into NO run doc, while the hook's `located` doc stays the `by-pane` target: `cc-lr find` reports `recovering(<run> located)` over a session that is engaged, and `cc-lr recover` stays refused. The policy tier's "screenshot finds a session already engaged" is exactly what `find` will NOT say.
- `requested_by.pane` for a hook-originated run can only be the limited pane's own `$KITTY_WINDOW_ID` (D3:198 `source_pane:$KITTY_WINDOW_ID`; the hook runs inside the dying session). C8/C13 route every alarm page and the terminal notify to `requested_by.pane` — the pane being `/exit`ed, or the husk. That is the addressed-to-the-victim shape `docs/lessons`/memory `dead-session-verdict-belongs-in-the-pane` records for the desk death. `hf_alarm` records still land in `~/.claude/handoff-alarms/` for the desk sweep, so the alarm CLASS has an owner; the PAGE does not.

**Severity: major.**

**Evidence:** D3:180-181, :192-203, :198, :269, :317; `lr-reset-poller.sh:639-661`; `hooks/stop-failure-marker.sh` 10 s timeout (U10 §1c); memory `dead-session-verdict-belongs-in-the-pane`.

### R5 — MAJOR — a re-limit on the target is un-drivable by the machine and invisible to the hook

**Claim refuted.** I7/C13 "never a husk"; C3 "Skip if `locks/<sid>.lock` or `<sid>.HANDOFF.json` exists (already moved)"; §8 "target spread: no two Fable sessions on an account whose weekly ≥ 90".

**Why it fails.** A transplanted xhigh Fable session resumes burning at once (U13 §3a); the 5-hour cap is per account and the survival floors project it (`RECOVERY_S_CEIL` on PROJECTED 5 h) from a burn rate measured over ONE 2.43 h window (U13 §6). When the target limits:
- `resume_engaged` excludes `isApiErrorMessage` (U04 §4) → no `engaged` → `stalled:submitted` → `failed:submitted:watchdog-gave-up`, named as an engagement timeout. The C8 repair for `submitted` is "never retype — the session may be working". Correct polarity, wrong diagnosis, no cure.
- C3's hook on the TARGET's `StopFailure` skips because `locks/<sid>.lock` exists (D3:196) — the guard against re-requesting a moved session also suppresses the request for its second limit.
- `cc-lr find --limited` DOES see it (marker + live registry row + `lr_last_api_error` on the target tail), so the operator runs `cc-lr recover` → `lr-transplant.sh:63-66` REFUSED lock exists. D3 has no second-hop state, no `--force` path, and no `from=<target>` re-lock.

**Severity: major** — the cure for a re-limit is a second transplant, and the design's own guards forbid it; the disposition the operator reads names the wrong cause.

**Evidence:** `lr-transplant.sh:55-66`; D3:196, :277; U04 §4; U10 §3d(3); U13 §3a, §6.

### R6 — MAJOR — READY-BY-QUIET injects into an unknown screen, against the file's own rule and I8

**Claim refuted.** C6 "replace `timeout {}` at `:560` with an 8 s quiet-pty settle that injects anyway and says so"; I8 "each with the emptiness pre-gate (U08 §5)".

**Why it fails.** `answer_menu` on an unconfirmed selector "sent NOTHING" and returns 0 (`lr-fire-resume.sh:501-503`); its caller `exp_continue`s (`:546`) with the menu still on screen. Nothing else is emitted, so the pty goes quiet. C6's 8 s quiet arm then sends `\025` + prompt + `\r` into the parked menu; a CR selects whatever is highlighted. The file's own comment at `:502` — "Refusing to guess: the next option down is destructive" — is the rule C6 overrides. U03 §2(c) documents the same hazard for the 5 blind CRs C6 deletes; C6 re-creates it once, on the path where the menu is most likely (an unpreseeded dialog class). The preseeds (resume threshold `:336-352`, `fullscreenUpsellSeenCount` in C6) shrink the population but do not close it, and no emptiness/modal read precedes the inject.

**Severity: major** (bounded by the preseeds; unbounded on any new dialog class).

**Evidence:** `lr-fire-resume.sh:495-503, :540-560`; D3:257; U03 §2(a)-(c); U08 §5 item 2.

### R7 — MAJOR — C11 certifies "nothing is owed" over a killed subagent (pane 114's exact shape)

**Claim refuted.** C11 "every ingest step-1 assertion is a shell predicate … plus the `gaps_at_handoff == 0 ∧ counts.gaps == 0 ∧ waiting == 0 ∧ open delegations == 0` clauses"; the prompt text "nothing is owed and nothing re-runs".

**Why it fails.** Two oracles judged pane 114 (`28f07827`) two seconds apart and disagreed:
- `~/.reso/limit-recover/28f07827-…/bundle-20260919T174936Z/audit.json` => `{"spawned":16,"settled":16,"open":0,"gaps":0,"waiting":0}`
- `~/.reso/limit-recover/fleet/one-20260919T174851Z/*.stderr` => `⚠ recycle proceeding with 1 IN-FLIGHT subagent(s) — --allow-live-subagents asserted; they are being KILLED deliberately, their partial transcripts are named in the successor's brief` (`handoff-fire.sh:4900`, from `live_subagents_of`).
In resume mode there is no successor brief (RECYCLE_VERIFY is forced 0, U04 §4), so the "named in the brief" half never happens either. C11's precondition A reads the audit, precondition B (`--ledger-only`) reads the same transcript-derived ledger, and both pass. The recovered session is told, by a script, that nothing re-runs — the narrated-verdict failure U12 §6.2 warns about, now with a false input. The loss is silent by construction.

**Severity: major** (correctness of the recovery, not just latency).

**Evidence:** the two artifacts above; `handoff-fire.sh:4870-4903`; U09 §3 (in-flight subagents "never stated as a plan item"); U12 §5-6; D3:306-309.

### R8 — MAJOR — the adopt arm and the C8 repairs act on a pane id that is not re-bound to the session

**Claim refuted.** §8 (b) "kill the watchdog too → the poller backstop adopts within one tick"; C8 "`repaired:<state>:adopt`"; the husk repair "type exactly that once through `it2_type_verified` when `at_shell`".

**Why it fails.** `lr-handoff.sh:266-284` proves pane→sid through the registry row at FIRE time and refuses on mismatch; `handoff-fire` re-checks it before `/exit` (`:261-265`). None of C8's repairs (retype launcher, re-send `/exit`, `cc_tui_submit_verified`, the husk retype) re-runs that check. The registry row is the ONLY thing tying a pane id to a session, and pane ids are re-issued: kitty renumbers from 1 on every launch, `~/.reso` survives a reboot while processes and `$TMPDIR` launchers do not (U04 §3 #8-9; `lr-handoff.sh:534-539`), and the `§0b` adopt arm is explicitly for "a watchdog that died". After a reboot the adopted watchdog finds pane N holding a fresh shell (`at_shell` true, `it2-kitty:520-527` SHELL) and types `cd <cwd> && nocorrect bash /var/folders/…/lr-launch-…sh` into a stranger's window. The launcher is gone so the line fails loudly — but the design's `alive` repair (`cc_tui_submit_verified` with the run's prompt) would paste the ingest prompt into whatever TUI now sits there. Memory `a-stale-pid-does-not-decay-into-harmlessness` is the shape.

**Severity: major.**

**Evidence:** `lr-handoff.sh:266-284`; `bin/it2-kitty:520-527`; D3:269-280, :284, :409; U04 §3 #8-9.

### R9 — MAJOR — `recover --all` stacks its five picks

**Claim refuted.** C10 "`--assign "$t" --src lr-fleet` … so N concurrent recoveries walk DOWN the ranking inside the 90 s cache TTL"; §8 "target spread".

**Why it fails.** The five `lr-fleet --one` processes are detached within milliseconds (C2 step 4). Each runs `--rank --recovery` then `--assign`. `bin/claude-accounts:141,170`: the cache is "flock single-flight" and "process-level single-flight flock in get_data(), so nothing here is a cross-process guard". There is no lock spanning rank→assign, so five ranks read zero phantoms and five assigns land afterwards. The phantom mechanism (`:1711`, `record_assignment` `:2053`, `apply_assignments` `:2147`) is correct for SEQUENTIAL fires — which is the only shape that has ever exercised it (handoff-fire fires one at a time). **GUESS on the exact window** (ms-scale; not measured), **not a guess on the mechanism.** Five Fable/xhigh sessions on one account whose weekly was 0 % is survivable today by the floors; it is not what the design claims to deliver, and on a day where only one account clears `RECOVERY_W_FLOOR` it is five sessions racing one 5-hour bucket.

**Severity: major** (for `--all`; sequential is unaffected).

**Evidence:** `bin/claude-accounts:141, :170, :1711, :2053, :2147`; D3:182, :186, :301, :404; U01 §3.3(b); U13 §2 D3.

### R10 — MINOR — the spine fails silent, and the watchdog acts on its silence

**Claim refuted.** I2 "nothing infers a verdict from another component's silence"; I3 "There is no state whose breach is silent".

**Why.** D3:113 makes `lr_state_set` "never exit non-zero into its caller (`|| true` at every call site)". An unwritable `recoveries/` (permissions, disk full, a `~/.reso` mount hiccup) produces zero writes and zero errors; the watchdog then reads a frozen doc and fires `stalled:*` plus repairs against a run that is advancing normally — the silence is inferred as a verdict, which is what I2 forbids. Memory `claimed-outcome-vs-checked-outcome` (`|| true` deletes the message) and `null-result-must-not-use-the-error-channel`. Also unbounded: `ledger.jsonl` lines carry "the exact command", "composer snapshot (first 200 chars)" and `rank_err` verbatim; a record over the stdio buffer is not an atomic append under N concurrent writers (`docs/lessons/append-atomicity-ends-at-the-stdio-buffer.md`).

**Severity: minor** (needs an environmental fault first; the polarity is the defect).

**Evidence:** D3:39-40, :111-113; the two memory/lesson files named.

### R11 — MINOR — three budgets are sized against the wrong wait

- `targeted→transplanted` 10 s (D3:101, :330) vs `lf_capacity_wait` 60 s by design and cold `cc_sp_active` 7.2 s per probe (U05 §4.3). The stall fires on every hot-box recovery before the fleet has done anything wrong (R1 is the consequence).
- Token TTL 180 s "leaves 4× slack" over "the whole `/exit`→shell→type path is bounded at 30+10 s" (D3:231, :337). The token is minted BEFORE `lr-handoff` (C4, `lr-fleet.sh:286`) and the composer gate (180 s) sits between mint and redemption (U04 §1 F2). Slack is ≤ 0 on a held draft; the fallback is a charging refusal + page (`_cc_admit_page`), so every draft-delayed recovery pages. Not fatal because budget=1 releases on attempt 2 — which means the gate on this path is now "refuse once, page, admit"; D3 does not say so.
- `exited` 30 s from "3–15 s in all 8 logs" (D3:331) — eight logs on one day, none through the bgwork dialog whose nudge checkpoints are 60/150/300 s (`handoff-fire.sh:6682-6689`).

**Evidence:** as cited; `capacity-admit.sh:535-542`.

### R12 — MINOR — `find` liveness by `kill -0` reads a reused pid as ALIVE

D3 §C2 rule 4: "`kill -0 <pid>` per candidate (authoritative)". The registry row carries `lstart` precisely as the pid-reuse guard (`hooks/session-register.sh:278`, U07 §4) and `cc_sp_active` charges liveness on `(pid,lstart)` for the same reason (`spawn-presence.sh:386-390`). After a reboot the 26 stale rows (U14 §3.2) meet a densely re-issued pid space; a STALE row that reads ALIVE is eligible for `recover`, and I4's irreversible transplant then runs against a session no process holds. Memory `a-stale-pid-does-not-decay-into-harmlessness`.

**Evidence:** D3:173; `hooks/session-register.sh:278`; `spawn-presence.sh:386-390`; U14 §3.2.

### R13 — MINOR — `resumed` is gated on a notify the requester may be unable to receive

D3 §3.1 `resumed` evidence = "registry row copy, notify receipt"; §6 "`cc-notify --receipt` for the delivery". `bin/cc-notify:277` resolves a dead peer as `reason=target-not-live`. A requester that recycled itself (same pane, new sid) or closed → the run engages, never reaches `resumed`, and at 90 s the watchdog raises `lr-stalled-engaged` on a working session. Whether `resumed` is written on an undelivered notify is unspecified.

**Evidence:** D3:73, :365; `bin/cc-notify:277`.

### R14 — MINOR — the poller's re-drive of `failed:*` sits behind the source account's reset

C8: "`:902-905` … A run in `failed:*`/`stalled:*` is re-driven through the request arm instead of retired." That arm is inside `§2 RESUME`, and `lr-reset-poller.sh:896` `(( now < reset_epoch )) && continue` gates every line below it (U06 §1). D3 adds the `§0b` adopt arm above the gate for a DEAD WATCHDOG only; a run whose watchdog gave up honestly (terminal `failed:*`) is re-driven no sooner than the source's reset — 2 h 40 m today. U06 §5 A (branch above `:896`) is not adopted.

**Evidence:** `lr-reset-poller.sh:896, :902-905`; D3:283-284; U06 §1, §5 A.

### R15 — MINOR — `results.tsv`'s cause has no writer at verdict time

C9: "`lf_one` writes the watcher's cause into `results.tsv` … read from the run doc". With `--no-await` (C5.7) `lf_one` maps `handoff-fire`'s FOREGROUND rc (`lr-fleet.sh:326-337`), which is 0 once the watcher is armed and `/exit` typed — so every run reads `RECOVERED` in `results.tsv` at the instant the watcher starts. The verdict `lf_one` was to copy from the run doc does not exist yet when `lf_one` exits. Harmless if `results.tsv` is retired; contradictory if it stays a store.

**Evidence:** `lr-fleet.sh:310-343`; D3:247, :295.

## 3. Replay of today's five against D3

| pane / sid | today | under D3, as specified | disposition |
|---|---|---|---|
| **112 / d02d8feb** (attempt 1, 17:04:50) | 600 s park on the load term, then PARKED | load term off; probe hits `reserve-active` (7 mid-turn incl. the 5 limited, operator present — IDL 17:17:43-17:18:47) for 60 s → PARKED. Run doc at `targeted`; watchdog `stalled:targeted` at 10 s, re-rank repair, `parked:no-target` page. `cc-lr recover 112` REFUSED (non-terminal) until 300 s | **regresses**: today's 17:19:45 admit was the operator's `CC_SP_ACTIVE_OVERRIDE=4`; D3 has no override, no net-zero on reserve-active, no state for the park (R1) |
| 112 (attempt 3, 17:19:07, override) | RECOVERED; engagement satisfied by a queued task-notification turn; ingest never delivered | if it got past the probe: token → admit; C6 submits and proves the user record; C7 refuses the task-notification turn as engagement | fixed (C6/C7 keep) — conditional on R1 |
| **111 / 09e64dcb** (17:21:26) | 2 refusals, husk, 17 min manual repair | probe 17:22:03 admitted (6 mid-turn = exactly the threshold) → token → admit on redemption → submit → engaged | **RECOVERED** |
| **121 / e442434c** (17:44:03) | husk; ingest never delivered | probe admitted (5) → RECOVERED, ingest proven | **RECOVERED** |
| **114 / 28f07827** (17:48:51) | husk; 1 in-flight subagent KILLED; manual ingest | probe admitted (4) → RECOVERED → C11 fast path passes on `audit.json` 16/16 → prompt says "nothing is owed and nothing re-runs" | **RECOVERED with a certified silent loss** (R7) |
| **117 / cb227486** (17:52:07) | husk; only auto-ingest of the day (+2 m 27 s) | probe admitted (2) → RECOVERED | **RECOVERED** |
| zero-byte run `one-20260919T171706Z` | operator `TaskStop` at 1.8 min | census gone (C9), so the 40–86 s vanishes; but the probe is still `reserve-active`-blocked → 60 s → PARKED-misnamed | regresses to R1's shape |

Net: 3 of 5 clean, 1 clean-but-lying, 1 parked with the wrong name — **and the parked one is the first session of any fleet event**, because it is the one that runs while all five limited sessions are still alive and counted. Two new dead ends (R2 held draft, R5 re-limit) are reachable that today's chain did not have, because today's chain never got far enough.

## 4. Keeps — what survives this lens and should go into the synthesis

- **C1 identity in the pixels** (`⌗pane sid8`, left-anchored, +1.2 ms) and **C2 `find`'s REFUSE-on-ambiguity** (rule 3) — the refusal polarity is the fault-tolerant one (U07 §6c item 4).
- **C4's launcher env block as the only channel that reaches the pane** (U04 §2), **`CC_ADMIT_BUDGET_KEY=$SID`** (kills the shared-counter poison, U05 §3.4), and **the one-shot / TTL / probe-inert token with tests 15/15b/15c** — correct as a mechanism; only the TTL sizing (R11) and the untouched reserve term (R1) are wrong.
- **C5.5 — the no-process branch emits** `recycle-dead` + `hf_alarm` + a state. This alone closes U04 §3's H8, the branch that fired 4/4 today with no record.
- **C5.3 — the positive discriminator** (read `refused:capacity` / the IDL row) instead of polling a corpse for 45 s.
- **C7 — token-anchored engagement.** Kills the pane-112 false positive (U03 §0, U11 §0(B)) by construction.
- **C6's transcript-first submit probe and rc 12** (U03 §4) — keep the oracle, drop the quiet-pty INJECT (R6); a quiet pty may justify a loud "READY NEVER SEEN", never a keystroke.
- **C8's husk predicate as a named, executable disposition** (`lr_is_husk`, the 4-read join from U04 §3) — the visibility half is right.
- **C8's poller retirement fix at `:902-905`** — a lock+transcript is no longer "the successor carries it" (U02 §2c, the single highest-leverage finding).
- **C9 — DUPLICATE with overlap subtraction; `RECOVERED→acct` / `RECOVERING` / `HUSK` dispositions** (U01 §1.3).
- **C10 — survival floors + recorded rationale** (stderr kept, `parked:no-target` carries the router's reasons; U13 §3b, D2).
- **I5 — the driver never blocks; end the turn** (U11 §2's 24.4 min). One caveat for the synthesis: U11 measured the Bash `task-notification` wake; a `start_new_session` detach does not produce one, so the wake is the mailbox — `hooks/mailbox-wake-arm.sh` IS registered on SessionStart (`jq` over `~/.claude/settings.json` => `~/.claude/hooks/mailbox-wake-arm.sh`), so the mechanism exists; it has not been measured on this path.
- **`ledger.jsonl` append-only, one line per transition** — it is the only store that survives R10's lost update; make it, not the doc, what `cc-lr status --last` renders.
- **§9's non-changes**: the `at_shell` affirmative-only gate, the composer gate's refuse-on-held polarity (the REFUSAL is right — the ORDER around it is what R2 indicts), lock/tombstone/guard, `cc_capacity_probe`'s never-spend contract, iron rule 7.
- **§8 fault-injection arms (a), (b), (d), (e)** as red-proofed tests; (c) as written cannot pass (R2).

## 5. What the lens says the synthesis must add (one line each, no design)

1. A `parked:capacity(<term>, <detail>)` state with its own budget and a probe-side repair; `CC_ADMIT_NET_ZERO` applied to `reserve-active` (`:834-840`) as well as `:832`; and either `kind:"limited"` beats (U05 §5.5 ii) or an `active` census that subtracts the run's own sid.
2. The composer gate BEFORE the transplant (probe → gate → transplant), or a `--force`/re-lock second hop that `cc-lr repair` can run; today the irreversible step precedes two admissions, not one.
3. One actuator per pane: the watchdog owns repairs ONLY after the watcher is proven dead (`kill -0 watcher_pid` false), never beside it; watchdog ceiling ≥ the watcher's own caps or the watcher's caps lowered to fit.
4. Hook-written `located` is adoptable by `cc-lr recover` (not refused), a hook run detaches a watchdog or is adopted on the next tick by rule, and the poller's drain passes `--run`.
5. Pane→sid re-binding (registry `session_id == sid` ∧ `(pid,lstart)` live) before EVERY repair keystroke, not only at fire time.
6. A second-hop path for a re-limited target and a hook that does not skip on a lock whose `to` equals the current config dir.
7. `lr_state_set` fails LOUD into the ledger and the alarm dir (not `|| true`), with a record-size bound.
