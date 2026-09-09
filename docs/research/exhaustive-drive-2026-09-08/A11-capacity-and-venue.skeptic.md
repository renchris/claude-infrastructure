# A11 — Skeptic pass: capacity and venue

**Wave:** exhaustive-drive 2026-09-08 · **Role:** skeptic over `A11-capacity-and-venue.md` · **Mode:** read-only
**Re-measured at:** 2026-09-09 01:40–02:00Z (the axis measured at ~21:00Z on 09-08; the IDL had grown 45,824 → 54,868 lines, agent-tool rows unchanged)

## Verdict in one paragraph

The axis's core finding survives and gets stronger: I extended its hand-read from 15/20 refusals to
20/20 (the 5 it did not read belong to three more sessions, and all three serialized too), so today's
disposition is **6 of 6 sessions, 20 of 20 refusals → serialized on the lead, 0 filed, 0 retried**.
Three of those six sessions were refused on *every* attempt and never got a budget release — the
release went to a different session hours later — which refutes the axis's "~3 minutes of delay"
figure (for half the affected sessions the delay was infinite) and sharpens R4. Two recommendations
are refuted as specified: **R6** rests on a fixture artifact (all 12 `rc=7 "no pane anchor resolved"`
fires are selftest stubs — the string exists only in `bin/cc-dispatch:3495`'s test stub, and
`handoff-fire.sh` cannot emit it) and proposes a "designated anchor" that already exists
(`resolve_headless_anchor`, desk role `~/.claude/cc-roles/desk`); **R4**'s formula
`max(1, ceiling*2 − active)` inverts its own intent at a 2× breach (yields budget 1 → release after
one refusal). **R5** as designed would have blocked 6 legitimate closes today, because every spool
entry would have been work the lead already did inline. **R1** and **R3** hold; R3's ordering clause
("land after R1/R2") is overstated because dispatcher-driven fires already have a retry queue.

## Numbers re-checked

| Claim | Axis | Mine | Command (population) | Holds |
|---|---|---|---|---|
| Agent-tool capacity evals / refusals today | 38 / 20 | 38 / 20 (12 headroom-only + 6 budget-expired admits) | `jq -rc 'select(.gate) \| [.gate,.verdict,.basis,.caller]' idl.jsonl \| sort \| uniq -c` (IDL since 08:22Z) | yes |
| handoff-fire production admits carrying `blind: active` | 48/48 | 48/48; 0 refusals | `jq 'select(.gate=="capacity" and (.under_test\|not) and .verdict=="admit") \| .detail \| capture("blind: (?<b>…)")'` handoffs.jsonl | yes |
| Sourcing site is inside a command substitution | `:5152` | `CC_FIRE_PRESENCE="$(_cc_fire_presence)"` at :5152; `_cc_fire_presence` :4995 is the only `spawn-presence.sh` source; `cc_sp_active` tested at :5360; no `cc_capacity_admit` call in the fire path | `grep -n spawn-presence\|cc_sp_active\|cc_capacity_admit scripts/handoff-fire.sh` | yes |
| Fire bats never exercises the live active path | (not claimed) | `tests/handoff-fire-capacity-gate.bats:84` exports `CC_FIRE_ACTIVE_OVERRIDE=0` in setup; every active-term test passes an override | `grep -n CC_FIRE_ACTIVE_OVERRIDE tests/handoff-fire-capacity-gate.bats` | new |
| Budget keyed on `<caller>`, default 3, reset on admit | :82-83, :564 | confirmed; reset at :573/:589/:595; **no TTL** — counter carried 10:49:57 → 13:24:34 (2.6 h) and 14:45:22 → 15:47:26 across different sessions | IDL agent-tool sequence + `sed -n 360,380p;516p capacity-admit.sh` | yes, stronger |
| Budget-expired releases | 6 | 6 — to ecdc97fa ×2, e5ab6841 ×2, 98af4df2 ×2; **2c9d5c43, c72ea92c, b0bf12dc received 0 releases** | `jq 'select(.basis=="budget-expired") \| .sid'` | yes; the 3 starved sessions are new |
| Refusal-imposed delay ≈ 3 min | 24+54+5+25+15+60 s | the "5 s" burst began 10:49:46 in another session (2 h 35 m earlier); three sessions never released at all | same sequence | **no** — mis-scoped |
| Hand-read: refused → serialized | 15/20, 3/3 sessions | 20/20, 6/6: 2c9d5c43 "running serially on the lead as the gate instructs"; b0bf12dc "Subagent refused … Running serially."; c72ea92c (2 teammate spawns refused 14:44/14:45) → "Edits to cc-backlog are in" at 14:4x — did the implementation itself | `jq` over each sid's transcript (found by sid across 4 roots; sizes 1.3–3.4 MB) | yes, extended |
| dispatch-fires rc census (non-`i[0-9]`) | 43/34/1/12 | 43/35/1/12 = 91 | `grep '^===== 2026-09-08' \| grep -v 'item=i[0-9] ' \| grep -o 'rc=…'` | yes |
| …of which real backlog items | 53 items | **48 of 54 fire-item ids are in backlog.jsonl; 6 are not** (27f29c9ce2a8 2d4ff6c81200 723d9e9cff68 7d5ccfd3f67b b1dd4c7c9f05 e6366921d839), each fired exactly 6×; the two rc=7 ids are in that set; their only output is the literal stub line | `comm` of fire ids vs `jq 'select(.event=="add")\|.id' backlog.jsonl` | **no** — 36 of 91 fires are fixtures |
| Real production fire failure | 47/90 = 52%, 12 on rc=7 | 36 of 55 real fires failed (65%); 19 launched (= the 19 `fired:` lines); causes today: `anchor probe INCONCLUSIVE (rc=2) — iTerm2 may be busy` ×12, `anchor probe REFUSED: live windows exist but none is agent-owned (rc=4)` ×10, `anchor gone` ×7, `never engaged` ×1; **rc=7 count for real items = 0** | `awk '/^===== 2026-09-08/{d=1} d && /^!!/' dispatch-fires.log \| sort \| uniq -c` | **no** on cause, worse on rate |
| dispatcher live_workers never bound | 1–8 vs 12 | 1–8 (620 rows at 8); 10,482 `defer capacity` rows | `jq 'select(.actor=="cc-dispatch" and .reason=="capacity") \| .live_workers'` | yes |
| cc-eligible sweep | 23/357 (6.4%) | 23/346 (6.6%); 146 ineligible-box; the tool's own label: "eligible — **no spelling fired — NOT a proof** of repo-only" | `python3 bin/cc-eligible sweep` | yes on count; it is a spelling denylist's output |
| `no-capacity` rows / class unsatisfiable | 0 rows; 3 accounts route | 0 rows; **`claude-accounts --rank general` → "no routable account" (next2 5h-cutoff; next/next3/next4 concurrency-unmeasured)** at 01:46Z | `bin/claude-accounts --rank general` | count yes; "unsatisfiable" **perished within 5 h** |
| cc_sp_active now vs ceiling | 9 > 8 | **4** < 8, trees 23, operator absent, load 35/70/84 | `. scripts/lib/spawn-presence.sh; cc_sp_active` | time-bound; the "should refuse right now" is no longer true |
| Multi-day archive refusals before 09-05 | 132 evals / 0 | 159 evals / 0 (one archive line failed to parse) ; 09-05 11, 09-06 20, 09-07 1, 09-08-pre-rotation 8 | `gzcat idl.jsonl.2026*.gz \| jq …` | yes (0 refusals) |
| Prose park latencies | 14.4 d / 14.8 d / ≥14.6 d | 253aaa52412e add 08-21 → done 09-04; f79353f8c096 08-21 → 09-05; 0e0c5a875dc0 add 08-25, **reopen 2026-09-08T22:33Z** | `jq 'select(.id==$i)\|[.ts,.event]'` | yes |
| parked-briefs: 1 file, 0 readers | | 1 file (mailbox-groundup.txt, 08-09); only hit `scripts/growth-coverage.conf` | `ls; grep -rl parked-briefs scripts bin hooks commands` | yes |
| R2/R5 primitives exist | | `bin/cc-mail`, `hooks/mailbox-wake-arm.sh`, `--condition` (31 refs) `--falsifier` (16 refs), 67 `falsify` events today; wrap-ledger has CLOSED/CUSTODY/FILED/UNCONVICTED_MINE, all rendering "session id unresolvable (not counted)" when sid=none (:1988-2004) | greps | yes |

## Per-recommendation verdicts

### R1 — spool the refused brief before denying · **not refuted** · conviction 85 (from 92)
Mechanism confirmed: the deny block at `hooks/agent-teams-enforce.sh:226-243` has `$INPUT` with
`.tool_input.description` and `.tool_input.prompt`, writes an IDL row whose `what` is only
`"<subagent_type> spawn"` (11 `deep-research spawn`, 8 `general-purpose spawn`, 1 `Explore spawn`),
and nothing else — `grep -ci 'parked\|spool'` = 0. Today's 20 refusals produced no artifact.
Deductions: (a) the message rewrite ("do not re-run inline") is the dangerous half — it converts a
lead that today does the work into a lead that waits on a drain, and the drain does not yet exist;
land the write first and the wording only with R2. (b) `.tool_input.prompt` can be a full brief
(tens of KB); without a per-sid cap the spool is a second transcript. **Fail direction as stated by
the axis is right: alone it is parked-briefs/ again.**

### R2 — a desk lane drains the spool and re-offers to the owner · **partially refuted** · conviction 55 (from 84)
Primitives exist. Three problems the axis did not weigh:
1. **Steady-state output is 100% duplicates on today's evidence** — 20/20 refused briefs were run
   inline by their leads, and no store records that, so every re-offer today would be a re-offer of
   finished work. "Accept the duplicate" is an alarm that always fires (memory
   `alarm-polarity-and-attention-budget`); the lead learns to ignore the mail.
2. **The drain condition re-implements the gate's predicate** (`cc_sp_active < ceiling`) instead of
   letting the actuator decide (memory `make-the-actuator-the-arbiter`); the spawn it re-offers then
   passes through the same gate anyway.
3. **Promotion to backlog enqueues into a lane whose real failure rate is 65%** (fixture-corrected),
   not 52%.
The owner-side actuator already exists and is goal-safe: `session-continue.sh` blocks the owner's
own Stop. A spool entry that the OWNER discharges (`done`/`skip`) at its next Stop — or that is
re-spawned by the owner when `cc_sp_active` is under the ceiling — is the one design where the
party who knows whether the work was done inline is the one asked. **Fail direction of the axis's
design: nags on legitimate closes.** Fail direction of the owner-side design: an owner that dies
leaves the entry stranded — which is where R2's promote-with-falsifier path belongs, and only there.

### R3 — un-blind handoff-fire's active term · **not refuted** · conviction 90 (from 95)
48/48 re-measured; root cause reproduced from the source (only `spawn-presence.sh` source is inside
`_cc_fire_presence`, invoked as `$(…)` at :5152; :5360 tests `command -v cc_sp_active` in the parent
shell). New corroboration the axis missed: the bats suite sets `CC_FIRE_ACTIVE_OVERRIDE=0` in setup
(line 84) and every active-term test passes an override, so the live `command -v` branch has never
been under test — memory `harness-default-collapses-the-states-under-test`. The red-proof the axis
asks for must run WITHOUT the override against a stubbed beat dir.
Deduction: the ordering clause "land after R1/R2 or it moves the defect to a second surface" is
overstated. Dispatcher-driven fires (`bin/cc-dispatch`) already re-pass every tick — a refused fire
is deferred and retried, which IS a queue with a destination; only interactive `/handoff` fires lack
one, and those are the operator's own. Also "a fire right now SHOULD refuse (9 > 8)" was true at
21:00Z and false at 01:46Z (`cc_sp_active` = 4). **Fail direction: closed, correctly, and only when
the box is genuinely over — the same polarity the Agent gate has shown for six days.**

### R4 — size the budget to the breach · **refuted as specified** · conviction 35 (from 71)
The diagnosis is right and stronger than stated: the counter is global per caller, has no TTL
(carried 2.6 h across sessions), and resets only on admit — so which session gets the release is a
lottery, and today three of six refused sessions got none. But the proposed formula
`max(1, ceiling*2 − active)` gives budget **1** at active = 16 (2×8 − 16 = 0 → max 1), i.e. the
release fires after ONE refusal at the heaviest breach — the exact opposite of "effectively holds".
The defect is the KEY (global) and the missing decay, not the constant: key the budget on
`(caller, sid)` so a lead's own third attempt releases its own wave, and age the counter. **Fail
direction of the formula as written: opens at heavy breach; fail direction of a per-sid key: N
concurrent leads each get a release, N admits into a saturated box — bound it with the existing
global counter as a second, outer term.**

### R5 — ledger term SPAWN_DEFERRED_MINE → 🔧 · **refuted as designed** · conviction 40 (from 78)
The shape exists (`FILED_MINE`, `UNCONVICTED_MINE`, `CUSTODY_MINE`; completion-assert consumes
UNCONVICTED_MINE). But on today's data the term would have held 🔧 over six closes whose spooled
briefs were all executed inline — the spool has no way to learn that. A close blocked on finished
work is the failure the brief names first: it trains the model to route around the gate (or to stop
attempting spawns). Also every `*_MINE` term degrades to "session id unresolvable (not counted)"
when the sid is absent (`wrap-ledger.sh:1988-2004`), so `/wrap` would be blind while the Stop hook
is not — two verdicts for one state (memory
`discriminator-scoped-to-a-window-yields-two-verdicts`). Viable only with an owner-side discharge
verb; at that point it is FILED_MINE with a different store.

### R6 — a designated headless pane anchor · **refuted as specified** · conviction 20 in the mechanism, 85 in the goal (from 88)
1. The headline cause is a fixture artifact: all 12 `rc=7 handoff-fire: no pane anchor resolved`
   fires are items `723d9e9cff68` / `7d5ccfd3f67b`, absent from backlog.jsonl, fired exactly 6× each
   in lockstep with four other non-backlog ids (24 rc=0) — a selftest running ~6×/day. The string
   exists only in the stub at `bin/cc-dispatch:3495`; `scripts/handoff-fire.sh` has no such line
   (its own `exit 7` at :6933 is a self-close resolver abort). Memory `positive-control-the-denominator`
   — the axis applied it to its transcript instrument and not to this log.
2. A designated anchor already exists: `resolve_headless_anchor()` (`handoff-fire.sh:9813`) reads
   the desk role file (`~/.claude/cc-roles/desk` = `330`), falls back to a fresh window when iTerm2
   is DETERMINED empty (rc 1), and refuses on INCONCLUSIVE (rc 2) or "no agent-owned window" (rc 4).
   Today's real failures are rc=2 ×12 (probe congested — the box was at load 155) and rc=4 ×10 (the
   desk pane / no agent-owned window provable) plus `anchor gone` ×7. A reserved window changes
   neither: it must still be probed through the same congested API and still be provably agent-owned.
3. The 36 fixture fires/day themselves hit that API; nobody has measured whether the selftest is part
   of the congestion it reports on.
The right target is probe robustness under load and desk-role liveness (why `330` is not accepted as
agent-owned), plus fixture fires labelled so a census cannot count them. **Fail direction of the
axis's mechanism: as it says, spawning into an operator window — but it would not even reach that,
because the probe refusal precedes the anchor choice.**

### DO-NOT (cloud / ceiling / no-capacity path) · **not refuted, one leg perished** · conviction 75 (from 90)
- Cloud: agree, but the evidence is the wrong kind — `cc-eligible` is by its own header a denylist
  of spellings and labels its own "eligible" as "no spelling fired — NOT a proof". 6.4% is the
  classifier's output, not a measurement of what a VM could do (memory
  `denylist-enumerates-spellings-not-the-class`). The independent argument (15/15 refused axes are
  about this box) stands.
- Ceiling: agree — `cc_sp_active` is "latest beat is `prompt`", so a lead blocked on subagents is
  charged; raising 8 moves a number a wrong input is compared against.
- No-capacity path: the "class is unsatisfiable today because 3 accounts route" evidence perished
  within five hours — at 01:46Z `claude-accounts --rank general` routes NOWHERE. Zero rows is still
  true and still the point; but do not carry "unsatisfiable" forward (memory
  `resident-policy-must-not-restate-perishable-facts`).

## What the axis missed that its question required

1. **Five of twenty refusals were never read**, and they carry the sharpest fact of the day: three
   sessions were refused on every attempt and never released — the budget lottery paid other leads.
2. **The "3 minutes of delay" is mis-scoped** to bursts that ended in a release; the counter has no TTL.
3. **The rc=7 cause is a selftest stub**, and 36 of 91 "fires" today are fixtures; the real production
   failure rate is 65%, on probe congestion and ownership proof, not on a missing anchor.
4. **The headless anchor and desk-role mechanism already exist** (`resolve_headless_anchor`,
   `~/.claude/cc-roles/desk`); R6 re-proposes them.
5. **The fire bats collapse the state under test** (`CC_FIRE_ACTIVE_OVERRIDE=0` in setup), which is
   why a 100%-blind production term has a green suite.
6. **Dispatcher-driven fires already retry** — R3's "no queue behind a fire refusal" is true only of
   interactive fires, so the mandated landing order is weaker than stated.
7. **R4's formula inverts at the breach it targets.**
8. **R2/R5 cannot tell "spooled" from "done inline"**, and on today's evidence that is 100% of entries.
9. **The owner-side actuator (`session-continue.sh`) was not considered** as the drain — it is the
   only party that knows whether the brief was executed, and it is already goal-safe.
10. **Perishable evidence stated as standing fact** ("3 accounts route"; "9 > 8 right now").

## Instrument caveats
Same windows as the axis (IDL since 08:22Z 09-08; handoffs.jsonl since 04:48Z). Transcript reads are
n = 6 sessions / 20 refusals — 100% of today's Agent-tool refusals. `pgrep -x iTerm2` read
not-running from inside this session and is discounted (memory `pgrep-excludes-the-callers-ancestors`).
