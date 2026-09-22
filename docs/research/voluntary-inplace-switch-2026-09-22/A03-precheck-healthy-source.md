# A03 — the pre-flight check when the source is HEALTHY

Read-only investigation, 2026-09-22. Nothing in the repo was modified; no pane was driven.

---

## Verdict

**Today's `lrh_precheck()` is not a safety gate over a healthy session — it is an ELIGIBILITY gate
that happens to refuse healthy sessions as a side effect, and on the commonest path it already does
not refuse them at all.** The safety it appears to provide is supplied almost entirely by a physical
fact about the subject — *a quota-blocked session cannot execute another turn* — and not by any
conjunct in the check. Remove that fact and three separate mechanisms lose their correctness
argument at once:

| # | Mechanism | Why it is correct today | What breaks on a healthy source |
|---|---|---|---|
| **M1** | `lr-transplant.sh:246-263` — `cp -p` the transcript, then `shasum` both sides | a limited session appends nothing after the copy, so the snapshot IS the session | the source keeps appending for the whole window between the copy and the `/exit` (which includes `recycle_composer_gate`'s **up-to-180 s** wait, `handoff-fire.sh:12348`). Every turn written in that window exists only in `$SRC`; the successor resumes `$DST`. **Silent truncation of the tail, with no consumer anywhere that would notice** |
| **M2** | `handoff-fire.sh:9714-9721` — `--transplanted-source ⇒ ALLOW_LIVE_SA=1`, the subagent gate is waived by class | *"a limit-blocked lead's subagents died with it — their transcripts have no terminus, so the gate would read them as IN FLIGHT"* | the premise is **false**. A healthy lead's subagents are genuinely in flight, and the one gate that would refuse is disabled by the very flag the in-place path always passes |
| **M3** | `handoff-fire.sh:6956-6968` — the exit-time dialog is auto-answered with the index parsed for `CC_MODAL_BGWORK_KEEP` (`hooks/lib/pane-modal.sh:251`, `"Move to background and exit"`) | a limited lead has no live teammates to appear in that dialog | `docs/lessons/a-lead-with-live-teammates-cannot-exit-unattended.md` measures the **same** dialog rendering `subagent · <brief>` rows for live named teammates. The recycle rail would auto-answer the teammate-orphaning modal, unattended, and the recycle path runs **no** `live_teammates_of` check at all (only `self-close` does — `handoff-fire.sh:8405`) |

M1 is the largest and is not in the brief's enumeration. It is a correctness defect, not a policy
one: no flag, no refusal and no log records it.

**And the hole is already open.** `lr-handoff.sh:797-822` (the SELF branch, landed 2026-09-22)
runs the probe and **deliberately discards its rc**, with the reason stated in-comment at :806-810:
*"a healthy session probes `REFUSED:not-limited` and exits 5: letting that rc reach the branch above
would refuse every self-recovery of a session that is merely low on context or being moved to a
fresher account."* So the voluntary path exists today, it is the commonest in-place shape on the box
(a session recycling itself), and on it **every pane- and session-level refusal is inert** — the
branch can only ADD a `killed_inflight` record. The correct fix is not to re-arm those refusals on
that branch; it is to give the voluntary verb its own conjunct set, because the ones it would
re-arm are the wrong ones.

---

## (a) Conjunct-by-conjunct

`lrh_precheck()` is `scripts/limit-recover/lr-handoff.sh:754-849`, called at `:851-853` under
`IN_PLACE=1 && LRH_PRECHECK != off`. Its pane/session conjuncts are all delegated to
`handoff-fire.sh --probe-recycle-preconditions` (`scripts/handoff-fire.sh:7763-7895`), which is
the **same implementation the actuator uses** (deliberate — probe and gate must answer one question).

Legend: **KEEP** unchanged · **CHANGE** semantics or polarity · **DROP** for the voluntary verb ·
**ADD** new. "Limited-only" = the conjunct exists *because* the source was assumed quota-blocked.

| # | Conjunct | file:line | rc/verdict today | Limited-only? | Voluntary verdict | Reason |
|---|---|---|---|---|---|---|
| C1 | `handoff-fire.sh` reachable / executable | `lr-handoff.sh:758-762` | 6, `REFUSED` | no | **KEEP** | unreadable evidence is not evidence; and the voluntary path needs *more* reads, not fewer |
| C2 | pane↔session registry binding (`hf_remote_source_bind`) | `handoff-fire.sh:7775-7779`, fn at `:2027-2073` | 5 `REFUSED:registry` | no | **KEEP + STRENGTHEN** | the bind proves the pane *names* the session; it never checks the row's **pid is alive on that tty**. `hf_remote_source_pin` (`:2219`) does exactly that and is called on the remote recycle path (`:9686`) but **not** in the probe — a known queued defect (`docs/plans/LIMIT_RECOVER_100P.md:695`). On a healthy source the pin is load-bearing: a stale row plus a living stranger in that pane is the wrong-pane recycle class |
| C3 | in-flight subagent **count** (`live_subagents: <n>`) | `handoff-fire.sh:7819-7822`; recorded `lr-handoff.sh:788-795` (driver) / `:813-821` (self) | never a refusal | no | **CHANGE → REFUSE** | see (d). Counted-never-refusing is correct when the units are already dead; it is the wrong polarity when they are alive |
| C4 | a transcript for the sid exists under `$CC_PROJECTS_DIRS` | `handoff-fire.sh:7823-7826` | 5 `REFUSED:no-transcript` | no | **KEEP** | there is nothing to transplant. (This conjunct carried the `${LIST}/*/x` single-word glob bug that made 4 of 5 config roots invisible and refused ~80% of recoverable sessions — `LIMIT_RECOVER_100P.md:435`; fixed, but it is the conjunct most likely to fail-closed for the wrong reason) |
| C5 | `lr_last_api_error` is reachable | `handoff-fire.sh:7827-7830` | 5 `REFUSED:limit-unreadable` | **yes** | **DROP as a refusal / KEEP as a read** | "I could not read the limit predicate" must not block a switch that does not depend on a limit. But the *reading* is still needed — it selects the safety profile (below) |
| C6 | the last assistant record is `kind=limit` | `handoff-fire.sh:7831-7836` (`lr_last_api_error`, `lr-lib.sh:174-230`) | 5 `REFUSED:not-limited` | **yes — this IS the assumption** | **DROP as a refusal; INVERT into a MODE SELECTOR** | its stated rationale (`:7783-7785`) is *eligibility*: "a network death has a retry ladder that may still be running… and a clean session is not owed a recovery at all". Neither sentence is about safety. For the voluntary verb: `kind=limit` ⇒ **FORCED profile** (source provably cannot act; today's conjunct set is sufficient). Anything else ⇒ **VOLUNTARY profile** (the source can act; the whole new set below binds). Note that `lr_last_api_error` returns rc 1 / empty `kind` for a healthy session, so "healthy" and "died on a network error" land in the same bucket here and must be split by the busy oracle, not by this one |
| C7 | the source is not itself a teammate (`"agentName"` in the first 8 KB) | `handoff-fire.sh:7841-7846` | 5 `REFUSED:teammate` | no | **KEEP** | teammate rule 0: its close is its lead's harvest; transplanting it orphans it. Unchanged by health |
| C8 | which terminal owns the pane (`hf_remote_pane_term`) | `handoff-fire.sh:7855-7869` | 3 `HELD:pane:resolver-unavailable` / 5 `REFUSED:pane:absent` | no | **KEEP** | transport resolution; health-independent |
| C9 | `pane_cc_state == cc` | `handoff-fire.sh:7871-7877`, fn at `:3764-3808` | 5 `REFUSED:pane:<state>` | no | **KEEP, but it answers less than it looks like** | it returns `cc` for a session that is *mid-turn*, *idle*, *at a permission modal* and *wedged*, identically. It is a "is a claude here" oracle, never an "is it safe to interrupt" one. See (c) |
| C10 | composer is EMPTY (`composer_content`) | `handoff-fire.sh:7881-7892`, fn at `:2608-2624` | 3 `HELD:draft` / 3 `HELD:composer-unreadable` | no | **KEEP + RE-READ** | the polarity is already right (an operator draft defers). The problem is the *sample*, not the predicate — see (c) |
| C11 | machine capacity (`lr_capacity_probe_corrected`) | `lr-handoff.sh:826-833`, `lr-lib.sh:399` | 6 `PARKED` | no | **KEEP** | unchanged |
| C12 | admission token mint | `lr-handoff.sh:835-843` | warning only, never a refusal | no | **KEEP** | unchanged |
| C13 | **the whole block is gated on `SOURCE_PANE` being set** | `lr-handoff.sh:757` vs the SELF branch at `:797` | — | — | **CHANGE — this is the headline structural defect** | `lrh_resolve_implied_pane` branch (b) (`:288-297`) deliberately leaves `SOURCE_PANE` empty for SELF and exports `LRH_SELF_PANE` instead; the SELF branch then runs the probe with `|| true` and drops the rc (`:814`). So on the commonest in-place recovery there are **zero** refusable reads. The same conditional was found and reproduced once before as a husk generator (`LIMIT_RECOVER_100P.md:688` — A/B with one variable: with `--source-pane`, rc 6 nothing moved; without, the transplant ran and 180 s later the pane was a tombstoned husk). It was fixed for the DRIVER verb only |

### The conjuncts that are **not there** and are load-bearing

| Missing | Where the oracle already exists | Consequence today |
|---|---|---|
| live named **teammates** of the source (it is a LEAD) | `live_teammates_of` (`handoff-fire.sh:4986`), used only by `self-close` (`:8405-8419`, exit 4). Also already computed per-run in the bundle: `audit.json` `.teams.led[].members[].verdict=="RUNNING"`, pid-keyed (`lr-audit.py:1474,1480,2229-2237`), written at `lr-handoff.sh:492` — i.e. **before** the precheck at `:851` | the recycle path orphans a live team, and M3 auto-answers the modal that would otherwise stop it |
| the source is **mid-turn** | `tool_in_flight()` (`bin/cc-classify:410-470`), mirrored as `_tool_in_flight()` (`hooks/teammate-auto-shutdown.sh:603`) | `/exit` "INTERRUPTS the in-flight turn and exits within seconds… the busy turn died with no output persisted" (`handoff-fire.sh:12360-12362`, E2E-measured). Plus M1's truncation |
| the source is **BUSY vs IDLE-ARMED vs IDLE-DEAF** | `session_busy_live()` (`hooks/lib/session-busy.sh:328-389`) — beat-based, with `GONE` and `UNKNOWN` as distinct states, consumed today only by `scripts/wrap-ledger.sh:2140-2158` | no producer on this path answers "working or idling" at all |
| a **backgrounded job** of the source is running | `sb_busy_jobs()` (`hooks/lib/session-busy.sh:195`) | this is the *exact* trigger of the exit-time dialog (`handoff-fire.sh:3086-3092`, incident `004d154032e8`). Reading it before the transplant converts a 600 s watcher death into a refusal |
| a **land** is in flight in the source's worktree | `land_inflight_live()` (`hooks/lib/land-inflight.sh:95`) | a `/exit` mid-land is the worst single loss on this box; the dialog's KEEP option exists *because* "on this box [background work] is usually a land in flight" (`pane-modal.sh:249-250`) |
| a **permission prompt** is pending | `sb_permpend()` (`hooks/lib/session-busy.sh:306`); `cc-classify`'s `blocked-on-permission` beacon | partially covered by accident: a modal renders no composer box, so `composer_content` fails and C10 yields `HELD:composer-unreadable` (`handoff-fire.sh:7889-7891`). That is the right answer reached from the wrong direction, and it cannot say *which* modal |
| **open custody debt** | `cc-custody count --open --cwd <dir>` (`bin/cc-custody:252`) | a lead mid-wave that switches accounts keeps its debt (custody is cwd-keyed, `bin/cc-custody:36-39`), so the debt survives the switch. This is a **WARN**, not a refusal |
| **duplicate holders** of the sid | `lr_holder_count()` (`lr-lib.sh:506`), used by `lr-fleet.sh:254` to compute `DUPLICATE` — **not** by `lr-handoff` | a healthy sid with a second live holder (a `--resume` leaf elsewhere) is a split brain the transplant would deepen |
| the pane's row **pid is alive** | `hf_remote_source_pin()` (`handoff-fire.sh:2219`) | see C2 |

---

## (b) The new refusals a healthy source requires

Disposition column: **REFUSE** = exit non-zero before anything moves · **DRIVE** = bring the source
to a safe state first, then re-read · **WARN** = record and proceed.

| State | Oracle | Disposition | Why, and why not the other two |
|---|---|---|---|
| **source is mid-turn** (unreturned `tool_use`, or a launched-and-unnotified background Bash) | `tool_in_flight` (`cc-classify:410`) | **DRIVE, then REFUSE on timeout** | `/exit` kills the turn with nothing persisted (`handoff-fire.sh:12360`) AND M1 truncates the snapshot. Driving = poll until the tool returns, bounded; a bound it cannot meet is a refusal, never a proceed. A bare WARN is inadmissible: the loss is silent. Pair it with the M1 fix (below) — the two are the same hazard seen from two files |
| **source is BUSY** by the beat (`kind=prompt`, pid+lstart verified) | `session_busy_live` (`session-busy.sh:328`) | **DRIVE, then REFUSE** | strictly wider than mid-turn (it catches a thinking turn with no tool out). `BUSY-SUSPECT` (transcript static > `CC_BUSY_SUSPECT_S`, default 900 s) is the one sub-case that may degrade to WARN — it is the wedge signature, and the switch is the cure |
| **`session_busy_live` returns `UNKNOWN` / `error`** | same | **REFUSE (HELD)** | house rule, stated in that file's own header at `:33-36`: "an instrument that could not read anything reports UNKNOWN, never a manufactured state". Typing needs the affirmative (`handoff-fire.sh:3729`) |
| **live named teammates** (source is a LEAD) | `live_teammates_of`, or `audit.json .teams.led[].members[].verdict=="RUNNING"` already in the bundle | **REFUSE**, override `--allow-live-teammates` | `self-close` already refuses this at exit 4 over the identical loss (`:8408-8418`); a recycle is strictly worse than a close because it also relaunches. The vendor's `cleanupSessionTeams` is unreachable unattended anyway (lesson, measured 2.1.260), so "proceed and let the harness tidy up" is not available. **Do not DRIVE this one automatically** — sending `shutdown_request` to N members is an outward act with its own harvest semantics; that is the lead's judgment, not the rail's |
| **in-flight Agent-tool subagents** | `live_subagents_of` — the number the probe already prints | **REFUSE**, override `--allow-live-subagents` | this is simply `subagent_gate`'s existing contract (`handoff-fire.sh:5156-5202`, exit 4) reaching the path that currently bypasses it. The bypass is `:9714-9721`'s class waiver, whose premise is false here. A killed subagent "stops mid-token" and "nothing observes it" — the gate's own failure-direction argument (`:5055-5058`) applies with full force |
| **a backgrounded job of the source is running** | `sb_busy_jobs` (`session-busy.sh:195`) | **REFUSE** if it is a land; **WARN + proceed** otherwise, having *pre-decided* the modal answer | this is the dialog's trigger. Reading it before the transplant is what makes the 600 s watcher death (`handoff-fire.sh:7009-7054`) unreachable instead of recoverable. The filed remedy's "drain it first" arm is already refuted (`pane-modal.sh` block at `handoff-fire.sh:3100-3105`) — the harness tracks shells whose processes are gone — so *awaiting* is not the cure; *knowing* is |
| **a land is in flight** in the source's worktree | `land_inflight_live` (`land-inflight.sh:95`) | **DRIVE (await the land), then REFUSE on timeout** | a land is minutes long (episode p90 991 s, `land-inflight.sh:6-8`) and its marker is pid+lstart-verified, so the wait is bounded by a real signal rather than a guess |
| **composer holds an operator draft** | `composer_content` (`:2608`) | **REFUSE (HELD)** — unchanged | already correct: "the draft is the operator mid-thought, and a recycle rail can always re-fire; a swallowed message cannot be unsent" (`:12341-12343`). **But it must be re-read immediately before the `/exit`** — see (c) |
| **composer unreadable** | same | **REFUSE (HELD)** — unchanged | dominated by a blocking modal, where a keystroke is consumed as the ANSWER (`:2700-2710`) |
| **a permission prompt is pending for this sid** | `sb_permpend` (`session-busy.sh:306`) | **REFUSE (HELD)**, and NAME the tool | today this only reaches us as `HELD:composer-unreadable`. Naming it turns an unexplained hold into an instruction — the same argument `session-busy.sh:44-45` makes |
| **an armed `/goal`** | `goal_live_condition` (`hooks/lib/goal-state.sh:60`) | **WARN** | `--recycle` INHERITS the predecessor's live condition (`inherit_recycle_goal`, `handoff-fire.sh:5805`, called `:11070`; `CC_RECYCLE_GOAL_INHERIT` defaults to 1), so this is **not** a loss — but the resume path passes `--resume-launcher`, so the successor's launch line is not the ordinary recycle line. **Uncertainty, named:** I did not establish that `inherit_recycle_goal` is reached on the `RESUME_LAUNCHER` arm. If it is not, this becomes a REFUSE-or-DRIVE, because a dropped goal on a voluntary switch is exactly the "armed and never evaluated" class |
| **an armed continue-sentinel** | `continue_sentinel_for` (`hooks/lib/continue-sentinel.sh`) | **no refusal; nothing to do** | the sentinel is sid-bound and the actuator clears a sentinel whose sid ≠ the actuating session's (`hooks/session-continue.sh:29-31`). A transplant keeps the SAME uuid, so it survives correctly rather than being inherited wrongly. This one is already safe; record it so a future reader does not "fix" it |
| **open custody debt** | `cc-custody count --open --cwd` | **WARN** | cwd-keyed, so it follows the worktree across the switch. It is a close-time obligation, not a transplant hazard |
| **uncommitted tracked work** | `git status --porcelain --untracked-files=no` in the source's own cwd (`sc_git`, `handoff-fire.sh:8510-8531`) | **WARN, not REFUSE** | an in-place switch does not touch the worktree — the successor lands in the SAME cwd with the SAME uuid, so the dirt survives by construction. `self-close`'s refusal exists because a close makes the session evaporate; this does not. Copying that refusal here would be the `remedy-gate-must-cover-the-occasion` defect |
| **committed-not-landed** | `rev-list --count trunk..HEAD` (`:8544-8556`) | **WARN** | same argument; the branch survives the switch |
| **duplicate holders of the sid** | `lr_holder_count` (`lr-lib.sh:506`) | **REFUSE** | `lr-fleet` already classifies `>1` as `DUPLICATE` rather than `RECOVERABLE` (`lr-fleet.sh:254`). Transplanting under a second live holder writes a target copy that two processes believe they own |
| **source's registry pid is not alive on that tty** | `hf_remote_source_pin` (`:2219`) | **REFUSE** | already the standard on the remote recycle path (`:9686`); the probe is the one caller missing it |

### Mechanism fixes that are not refusals

These are the parts that cannot be closed by a gate, and they matter more than any of the rows above.

| | Fix | Why a refusal cannot substitute |
|---|---|---|
| **M1** | the transplant must be **re-verified or re-taken** immediately before the `/exit`, not minutes before. Options, in preference order: (i) move the `cp` to *after* the composer gate and *immediately* before the `/exit`; (ii) re-`shasum` `$SRC` at the `/exit` and refuse on change; (iii) re-copy the delta | the window is created by the rail's own ordering (`lr-handoff.sh:855-862` transplant → `:880+` launcher mint → `handoff-fire --recycle` → `recycle_composer_gate` up to 180 s → `/exit`). No gate placed at the *start* of that window can see what happens inside it. The existing `SHA_SRC != SHA_DST` check (`lr-transplant.sh:259-262`) only catches growth *during* the `cp`, which is the smallest slice of the exposure |
| **M2** | `handoff-fire.sh:9714-9721` must condition its `ALLOW_LIVE_SA=1` waiver on the source having actually died on a limit, not on the `--transplanted-source` flag | the flag says "a transplant happened", which is true of both profiles. The comment's premise — subagent transcripts with no terminus because the lead died — is a property of the *limit*, not of the *transplant* |
| **M3** | the bgwork auto-answer must refuse to answer a dialog whose rows include a `subagent ·` entry it did not expect, or must be preceded by the teammate/subagent gates so such a dialog cannot arise | `pane_bgwork_choice` (`pane-modal.sh:268-286`) reads the index off the screen — correctly, and with no guess — but it does not read *what is being backgrounded*. Its authorisation argument (`handoff-fire.sh:3095-3099`) is explicitly "the only judgement left is what happens to work already running, where 'do not stop it' is the answer with no downside". For a live TEAM that is false: option 2 leaves members running with no lead to harvest them, which is precisely the `self-close` gate's loss class |

---

## (c) How "idle and safe to retire" is measured today — and whether to trust it

**It is not measured at all.** The three reads the probe makes each answer a different question, and
none is idleness:

| Read | Question it answers | Question it is being used for |
|---|---|---|
| `pane_cc_state` (`:3764`) | "is a claude process in this pane's descendant closure" | — |
| `lr_last_api_error kind==limit` (`:7833`) | "did the last assistant record say quota" | this is the de-facto idleness proof, and it is only that for the FORCED profile |
| `composer_content` (`:7883`) | "is there unsubmitted text in the box" | operator-draft protection |

`pane_cc_state` returns `cc` identically for mid-turn, idle-at-prompt, at-a-modal and wedged (its
three states are `cc|shell|unknown`, `:3764`). So for a voluntary switch the answer is: **no, today's
measurement is not trustworthy, because there is no idleness measurement to trust.** Substitutes
already exist and are cited in (b): `session_busy_live` (beat-derived, three idle-side states,
`GONE` separated from `IDLE`), `tool_in_flight`, `sb_busy_jobs`, `sb_permpend`.

### The sample-vs-state problem, and the one place the rail already gets it right

`MEMORY.md` → `tui-capture-is-a-sample-not-a-state` ("a prompt I read had already resolved — re-read
right before acting"). Applied here:

- **The composer read is already re-taken at the actuator.** `recycle_composer_gate`
  (`handoff-fire.sh:2631-2645`) re-reads every `CC_RECYCLE_DRAFT_IVL` (15 s) for up to
  `CC_RECYCLE_DRAFT_WAIT` (180 s), and `recycle_fire` refuses on a still-held draft at `:12348-12369`.
  So the precheck's C10 is an *early warning*, not the load-bearing check — and that is the correct
  architecture. **Do not build the new healthy-source conjuncts as precheck-only reads.**
- **Nothing else is re-taken.** The teammate set, the subagent count, the busy state, the land marker
  and the pid pin would all be single samples taken before a multi-minute transplant. For a source
  that *cannot act*, a single sample is a state. For a source that *can*, it is a sample.
- **Therefore the contract must be two-phase**: an **admit** phase before the first irreversible step
  (the transplant), and a **confirm** phase inside `recycle_fire`, after the composer gate and
  immediately before `as_write "$SID" "/exit"`. Any conjunct whose subject can change while the
  source keeps running must appear in **both**. The sibling-auditors rule (`MEMORY.md` →
  `sibling-auditors-must-share-the-state-model`) says these must be one implementation invoked
  twice, never two predicates.
- **A refinement the probe already needs anyway:** `hf_remote_source_pin` at both phases pins the
  *process*, not just the row — which is the cheapest way to detect "the thing I measured is no
  longer the thing I am about to type into".

---

## (d) Is `killed_inflight` accounting correct when the recycle is voluntary?

**No — and it is wrong in three independent ways at once.** The field is written at
`lr-handoff.sh:788-795` (driver) and `:813-821` (self), from the probe's `live_subagents: <n>` line
(`handoff-fire.sh:7819-7822`), and read by `lr-ingest-verify.sh` clause **A6** (`:213-228`).

| # | Defect | Detail |
|---|---|---|
| **D1** | **The name is false in the FORCED case and true in the VOLUNTARY one — and A6 was calibrated on the false one** | for a limited source, the counted units are agents that **already died with the lead**; their transcripts merely have no terminus, so `live_subagents_of` reads them as in flight (this is exactly `handoff-fire.sh:9718-9720`'s stated reasoning for waiving the gate). The recycle kills nothing. For a healthy source the same number is a **real, prospective kill**. One field, two meanings, no discriminator on the row |
| **D2** | **A6's consequence is a fast-path decision, not a safety decision** | `killed_inflight>0` ⇒ `clause FAIL A6 "the recycle interrupted in-flight work"` (`lr-ingest-verify.sh:226`), which merely degrades the recovery to the full ingest. That is the right response to D1's forced case (re-audit those units) and completely the wrong response to the voluntary case, where the correct response is **do not recycle**. A6 runs *after* the recycle; by then there is nothing to decide |
| **D3** | **The count is stale by the whole transplant window, and on the voluntary path it can move in BOTH directions** | for a limited source the number is frozen (no turn can spawn an agent). For a healthy one, agents can finish (count falls) **and** be spawned (count rises) between the probe and the `/exit`. A6 then adjudicates a number that describes a moment that has passed. Compare `handoff-fire.sh:9707-9713`, which places the recycle-path subagent gate deliberately in the foreground process "and not one line later" because "the point of no return is the `as_write "$SID" "/exit"`" — the same argument applies to the measurement, and the precheck is many minutes earlier than "one line" |

Two further honesty notes on the same field:

- On the **SELF** branch the probe's rc is discarded (`:814`), so a probe that refused for an
  unrelated reason still contributes its `live_subagents` line if it printed one. That line is
  emitted before every refusal path by design (`handoff-fire.sh:7810-7818` — the block was hoisted
  on 2026-09-22 precisely so it is reachable on refusals), so the record is *produced*; it is the
  **rc** that is thrown away, not the count.
- When `SOURCE_PANE` is empty **and** `LRH_SELF_PANE` is empty (the spawn fallback), no record is
  written at all and A6 fails closed — correctly, per its own contract (`lr-ingest-verify.sh:194-197`:
  "a log that never recorded the value does not say the value was zero").

**Required change for the voluntary verb:** stamp the *profile* on the row (e.g.
`killed_inflight=<n> profile=voluntary|forced`), make the voluntary profile refuse at
`n>0` at the **gate** rather than report at the ingest, and re-measure `n` in the confirm
phase. A6 should then read the profile and stop asserting "the recycle interrupted in-flight work"
about units that were already dead.

---

## Adversarial self-pass

Three things I assumed were fine and then checked.

1. **"The transplant is a read; only the `/exit` is irreversible."** False. `lr-transplant.sh`
   writes a split-brain lock (`:242-243`), copies (`:246-251`), and writes a tombstone (`:267-270`).
   It skips the source rename only when `CLAUDE_CODE_SESSION_ID == SID` (`:271`), i.e. only for SELF —
   so the **driver** form of a voluntary switch renames a *live, healthy* session's transcript to
   `.handed-off` while the harness is still appending to it by path. The header's own guard comment
   (`:265-266`, "never rename the LIVE session's transcript — the running harness still appends to it
   by path") is keyed on the driver's own env var, which is the wrong subject for a remote pane. That
   is the `discharge-predicate-must-measure-its-own-subject` shape, and it is a second, distinct M1.
   **Not verified:** what the harness does on an appending-to-a-renamed-inode transcript. Worth a
   dedicated probe before any voluntary driver form ships.
2. **"An armed continue-sentinel would be inherited by the successor."** False, and worth recording
   so nobody adds a refusal for it: the sentinel is sid-bound and a mismatch clears it
   (`hooks/session-continue.sh:29-31`). A transplant preserves the uuid, so the sentinel legitimately
   survives — which is the desired behaviour on a voluntary switch, not a hazard.
3. **"The composer read covers everything the operator has in hand."** Not quite. The harness also
   holds a **queue** — `queue-operation` records appear in the transcript
   (`bin/cc-classify:410-421` counts them as bookkeeping; `lr-audit.py:129-134` quotes their shape).
   A message the operator typed and *submitted* during a running turn sits in the queue, not the
   composer, and `composer_content` reads EMPTY for it. `/exit` would discard it. I found **no**
   oracle in the tree for pending queued input. This is a genuine gap and the only one of the three
   that has no existing reader — named here rather than designed, because it needs a measurement
   (does the queue survive `/exit`? does it survive a resume of the same uuid?) that I did not run.

A fourth, checked and cleared: **capacity**. `lr_capacity_probe_corrected` (`lr-lib.sh:399`) and the
admission token are profile-independent; a voluntary switch needs exactly the same capacity decision
and the same one-shot token, so C11/C12 carry over verbatim.

---

## Proposed pre-check contract for the voluntary path

Exit codes extend today's vocabulary rather than replacing it, so `lrh_precheck`'s
`${state%%:*}` read (`lr-handoff.sh:770`) and the `REFUSED:pane:` prefix pinned by
`tests/lr-handoff-launcher-quoting.bats` keep working.

```
EXIT CODES (probe verb; lr-handoff still collapses every non-zero to its own 6)
  0  OK:<profile>          admitted — caller may take the irreversible step
  3  HELD:<check>          transient, operator-owned or driveable; nothing is wrong, not yet
  5  REFUSED:<check>       this session must not be switched at all
  7  DRIVE:<check>:<hint>  a safe state is reachable by WAITING on a named signal; the caller
                           may poll and re-run. Distinct from 3 because 3 means "somebody else
                           must act" and 7 means "time will act". Never treated as 0.
  9  UNKNOWN:<check>       an oracle could not answer. NEVER admitted, never rendered as a
                           finding about the session (session-busy.sh:33-36 house rule).
```

```
probe_switch_preconditions(pane, session, phase)      # phase ∈ {admit, confirm}
    # ── PHASE-INDEPENDENT IDENTITY ────────────────────────────────────────────
    hf_remote_source_bind(pane, session)              || exit 5 REFUSED:registry
    hf_remote_source_pin(pane, row.pid)               || exit 5 REFUSED:pane:pid      # NEW (C2)
    hf_remote_pane_term(pane) -> rc
        rc == 3                                       -> exit 3 HELD:pane:resolver-unavailable
        rc != 0                                       -> exit 5 REFUSED:pane:absent
    tx = transcript_for(session, CC_PROJECTS_DIRS)
    tx == ""                                          -> exit 5 REFUSED:no-transcript
    head -c 8000 tx contains '"agentName"'            -> exit 5 REFUSED:teammate
    lr_holder_count(session) > 1                      -> exit 5 REFUSED:duplicate-holders   # NEW

    # ── PROFILE SELECTION — the inverted C6 ───────────────────────────────────
    # This no longer REFUSES. It chooses which conjunct set binds.
    kind = lr_last_api_error(tx).kind        # "" when the module is unreachable
    busy = session_busy_live(session, row.cwd, tx)     # BUSY|IDLE-ARMED|IDLE-DEAF|GONE|UNKNOWN
    profile = (kind == "limit" || busy.state == "GONE") ? FORCED : VOLUNTARY

    # ── ALWAYS COUNTED, AND NOW ALSO REFUSING UNDER VOLUNTARY ────────────────
    n_sub = live_subagents_of(subagent_dir_for_sid(session)) | count
    emit "live_subagents: n_sub"                       # unconditional; every path, both phases
    emit "profile: profile"

    if profile == FORCED:
        # today's set, verbatim — the source provably cannot act, so one sample is a state
        pane_cc_state(tty) != cc                      -> exit 5 REFUSED:pane:<state>
        composer_content(pane) -> (c, ok)
            !ok                                       -> exit 3 HELD:composer-unreadable
            c != ""                                   -> exit 3 HELD:draft
        exit 0 OK:forced                               # n_sub is RECORDED, never refuses (D1)

    # ── VOLUNTARY ─────────────────────────────────────────────────────────────
    busy.state == UNKNOWN || busy.src == error        -> exit 9 UNKNOWN:busy
    pane_cc_state(tty) != cc                          -> exit 5 REFUSED:pane:<state>

    # teammates — the loss self-close already refuses over (handoff-fire.sh:8408)
    tm = live_teammates_of(cc_sid_for_pane(pane))
         # or, at admit phase only, audit.json .teams.led[].members[]|select(.verdict=="RUNNING")
    tm != "" && !allow_live_teammates                 -> exit 5 REFUSED:live-teammates:<n>
        # NOT auto-driven: shutting a team down is the lead's harvest decision, not the rail's.

    # subagents — subagent_gate's contract, reaching the path that bypasses it (M2)
    n_sub > 0 && !allow_live_subagents                -> exit 5 REFUSED:live-subagents:<n>

    # a land is the single worst thing to interrupt on this box
    land_inflight_live(row.cwd)                       -> exit 7 DRIVE:land-inflight:<pid>

    # mid-turn, two independent readers; either one holds
    tool_in_flight(tx)                                -> exit 7 DRIVE:mid-turn:tool
    busy.state == BUSY && !busy.suspect               -> exit 7 DRIVE:busy:<age>s
    busy.state == BUSY &&  busy.suspect               -> WARN busy-suspect:<age>s   # wedged; proceed

    # backgrounded job → the exit-time dialog will be raised; decide now, not at 600s (M3)
    jobs = sb_busy_jobs(row.cwd)
    jobs != ""                                        -> WARN bgwork:<sample>
                                                         # and set EXPECT_BGWORK_DIALOG=1 so the
                                                         # watcher may answer it; absent this flag
                                                         # an unexpected dialog is a refusal.

    # the operator's hand — unchanged polarity, and re-read in the confirm phase
    pp = sb_permpend(session)
    pp != ""                                          -> exit 3 HELD:permission:<tool>/<age>s
    composer_content(pane) -> (c, ok)
        !ok                                           -> exit 3 HELD:composer-unreadable
        c != ""                                       -> exit 3 HELD:draft

    # advisories — recorded, never blocking (the switch preserves cwd, branch and uuid)
    goal_live_condition(tx)                           -> WARN goal-armed:<cond>
                                                         # REFUSE instead if inherit_recycle_goal is
                                                         # NOT reached on the --resume-launcher arm
    cc-custody count --open --cwd row.cwd  > 0        -> WARN custody-open:<n>
    git -C row.cwd status --porcelain -uno | head -1  -> WARN dirty:<n>
    git -C row.cwd rev-list --count trunk..HEAD > 0   -> WARN unlanded:<n>@<branch>
    continue_sentinel_for(row.cwd) exists             -> note sentinel-sid-bound (no action)

    exit 0 OK:voluntary
```

```
CALLER CONTRACT — two phases, one implementation

lr-handoff (voluntary verb):
    probe(admit)   rc 0        -> mint admission token; proceed
                   rc 7        -> poll the named signal, bounded by LR_SWITCH_DRIVE_MAX_S
                                  (default 900 = land p90 991s is the binding case; re-probe every
                                  15s, same cadence as recycle_composer_gate). On expiry -> 6.
                   rc 3|5|9    -> exit 6, nothing moved.
    transplant     ... IRREVERSIBLE BOUNDARY ...
    handoff-fire --recycle
        recycle_composer_gate (existing, up to 180s)
        probe(confirm)  rc != 0 -> REFUSE before as_write "/exit"
                                    (pane alive, transplant already taken — disposition is a retry
                                     via lr-fleet --one, per LIMIT_RECOVER_100P W11; never a park)
        re-verify or re-take the transcript snapshot   # M1 — the exit is not safe over a stale copy
        detach watcher; as_write "$SID" "/exit"

KILL SWITCHES
    LRH_PRECHECK=off             existing — skips the whole check (unchanged)
    LR_SWITCH_PROFILE=forced     force today's conjunct set on a healthy source (loud, recorded)
    LR_SWITCH_CONFIRM=off        skip the confirm phase (restores today's single-sample behaviour)
    --allow-live-teammates / --allow-live-subagents   deliberate abandonment, mirroring self-close
```

---

## Blockers and named uncertainties

1. **Not measured: does `inherit_recycle_goal` (`handoff-fire.sh:5805`, called `:11070`) run on the
   `RESUME_LAUNCHER` arm?** That arm sets `LAUNCHER="bash"; EXPLICIT_LAUNCHER=1` at
   `handoff-fire.sh:9730-9732` and takes a different resolution path. If the goal is dropped there,
   the goal row in (b) moves from WARN to REFUSE-or-DRIVE.
2. **Not measured: the queued-input question** (adversarial item 3). No oracle exists; the shape of
   the loss is inferred from the presence of `queue-operation` records, not from a probe.
3. **Not measured: harness behaviour when its transcript inode is renamed underneath it** — the
   driver-form M1 (adversarial item 1). `lr-transplant.sh:271`'s guard is keyed on the *driver's*
   `CLAUDE_CODE_SESSION_ID`, so a third-pane voluntary switch renames a live file.
4. **Cannot be tested on the current box in the obvious way.** The FORCED profile's own live check is
   still owed a real limited session with a routable target (`LIMIT_RECOVER_100P.md:736` item 7,
   `:807`). The VOLUNTARY profile is the *easier* one to exercise — any healthy pane is a subject —
   but every red-proof must use a fixture pane, never a live one
   (`docs/lessons/a-research-probe-that-drives-real-ui-writes-into-the-operator-s.md`).
5. **Fixture shape warning, inherited.** `tests/handoff-probe-preconditions.bats` was written
   specifically because a one-config-root fixture cannot distinguish the broken and correct forms of
   the cross-root glob (`LIMIT_RECOVER_100P.md:435`,
   `docs/lessons/fixture-shape-hides-address-bugs.md`). Any new conjunct that resolves an address —
   the teammate set, the subagent dir, the worktree — needs the same two-root treatment, or it is
   decorative on the axis its bug lives on.
