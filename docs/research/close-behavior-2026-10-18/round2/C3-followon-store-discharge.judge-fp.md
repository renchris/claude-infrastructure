# C3 judge, false-positive lens (D8 v2/v2b, follow-on store discharge)

Round 2, 2026-10-18. Adversarial judge on false positives and always-firing behaviour. I made no changes to the repo except
this file. Every run used the designer's sandbox copies (`/tmp/r2-C3/repo2/` = v2b) and harness. My own scripts and
outputs are under `/tmp/r2-C3/judge-fp/`. Load average was 300-367 during this work (measured: `uptime`). Every number
below is labelled measured (with the command) or estimated (with the method).

**Verdict: below-90. Conviction 25.** That is my estimate that D8 v2b, landed as a blocking arm, is net-positive *and* keeps
all six constraints. The designer put it at 40. I confirm the designer's conclusion and its headline counts. Through this
lens it is worse than the report says, for four reasons:
- It blocks deliberate stated parks **by construction**. That is constraint 2, stated outright, not just "in spirit".
- Two of the five held-out incident-class true positives are such parks.
- Precision counted per blocked stop, with the cap applied, is lower than the unique-close figure.
- The "byte-equivalent" claim for the dispatch-assert refactor is false for its drop arm.

## 1. What I re-ran (reproduced)

| Claim | My re-run | Result |
|---|---|---|
| Fire sets | `python3 -I /tmp/r2-C3/judge-fp/variants_j.py <census\|held>` (variants.py with its output redirected) | **reproduced exactly**: in-sample v2 12, v2b 5; held-out v2 39 (29 unique values), v2b 33 (27 unique) |
| New D8 suite | `/tmp/r2-C3/judge-fp/runbats.sh` (real bats-core, HOME sandboxed) | **`1..12` ok 12** |
| GENUINE abstain (not applied by the proxy) | GENUINE regex from the v2b hook, `grep -ioE` over every gated fire | it matches **none** of them, so the proxy does not overcount on this point |
| Write-gate proxy | read `extract.py:8` against `hooks/lib/session-writes.sh` `_sw_paths` | same tool set (Write/Edit/MultiEdit/NotebookEdit + subagents): the proxy is faithful |

## 2. False-positive findings

### 2.1 Stated parks are blocked by construction (constraint 2)

Hook-level probes on v2b (`bash /tmp/r2-C3/judge-fp/probes.sh`, output in `probes.out`, measured):

| Probe | Result |
|---|---|
| the real `ac0f0123` close, verbatim: "wave I3 …, dated in the plan for 2026-10-03 after seven green days, no row filed since the plan's table carries it" | **FIRE** |
| "the soak verdict, parked until 24h of data lands (2026-10-19)" | **FIRE** |
| a parked row (`whyNotNow`) filed by this sid in an earlier turn, described without its id | **FIRE** |
| the same row cited by id | pass |
| a parked row filed at 14:27:30, then another Stop hook's block starts a new turn at 14:27:40, re-close at 14:27:47 | **FIRE** (`run-jfp-park-filed-before-hookblock-T0late`) |

At `RUNG ✅ ∧ contra=0`, the only store records that can still discharge D8 are parks (`--why-not-now`/`--condition`),
fires with no notify-back custody, and closed records. Open agent rows, needs-human rows and class-C packets all move the
ledger off ✅ first (`scripts/wrap-ledger.sh:1418,1423,1499-1514`; `hooks/completion-assert.sh:1043,1054`). So **parks are
the main thing D8 adjudicates**. Any park stated in prose, or filed earlier and re-stated without its id, is blocked once
per class (cap 2). The design lists this as an open risk ("some will read that as blocking…"). Constraint 2 says "never
blocks … a deliberate stated park", so this is a violation as designed.

**Corpus evidence: two of the designer's five held-out TP-A are parks.** I read the transcript
(`ac0f0123…jsonl`, 2026-09-26 19:10-19:48Z):
- the I3 wave is gated on "seven green days";
- the session's own decision table reads "I3 on 2026-10-03 · Keep the seven-green-day gate · 90%".

It is not drivable on 09-26 or 09-27, so `b3a4924832e3` and `89f38eeeaa87` are stated parks, not undriven work.

How often a turn starts at a hook block (measured: `python3 -I /tmp/r2-C3/judge-fp/turnstart.py`, classifying the
`turn_start` record of every stop-final YES close with a non-nil verdict-line follow-on):
- in-sample: **46 of 206 (22%)** start at a `Stop hook feedback` record;
- held-out: **61 of 273 (22%)**.

In those turns, anything the session filed before the other hook's block is outside D8's window.

### 2.2 Honest nothing-drivable wordings (constraint 1)

`followon_value` has no length floor, and `_NIL_LEAD` accepts only `none|n/a|nothing|no|-` followed by end of string or
`.;,:—–-`. I fed it 38 honest nil phrasings (`/tmp/r2-C3/judge-fp/nilprobe.txt` lines 1-38). **23 of 38 read non-nil**
(measured):
- `none (all landed …)`, `none needed`, `none required`, `none for you`, `none of mine`, `none pending`;
- `nothing of mine`, `nothing drivable remains`, `nothing else`, `nothing to do`, `nothing further`;
- `no follow-on`, `no further work`, `n/a (…)`, `—`, `nil`, `zero`, `all done`, `not applicable`, `none left for anyone`.

Hook-level, `none (all landed and content-verified).`, `nothing drivable remains.`, `no follow-on.`, `—` and `none from
me.` each **FIRE** (probes).

Some closes have nothing the agent can drive and would still fire:
- `the post-land verifier runs on its own within 10 minutes.` FIREs.
- A third party's step (`…still Daniel's to make`) FIREs.
- A deadline-store id (`` `health.call-dr-shahinian-949` ``) FIREs. MSG_UNQ strips the backticked id, and `sd_ids_exist`
  knows only 12-hex ids.

In practice this pool is small, because agents mostly write the template's `none.`. Measured
(`/tmp/r2-C3/judge-fp/nilled.py`):
- **47** stop-final YES closes had a nil-led but non-nil value (14 in-sample, 33 held-out).
- 28 of them were discharged by an existing id or a store record.
- **3** reached v2b's gates: 1 TP (`99b5cd2f`) and 2 FP-nil.
- The write gate spared 4 more honest ✅ closes ("none of mine", "none from me", …) only because those sessions made no
  Edit or Write.

### 2.3 ⛔ decisions

- **This session's own class-C packets are safe by construction.** `count_blocking_decisions` counts `session_sid == $SID`
  packets, so the rung is ⛔. Unconvicted packets set `UNCONV>0`, so contra=1. Either way D8 is never reached. Verified by
  reading `wrap-ledger.sh:1483-1514` and `completion-assert.sh:1053-1054`.
- **A predecessor's packets are not.** Probe `decision-predecessor-no-id`: an open class-C packet filed by another sid
  (a handoff predecessor), described as "the two decisions the previous session filed, still open on your board" ⇒
  **FIRE**. The corpus has this shape once (in-sample #9, `6defb493` vs `d2d19fcf`). v2b's "ids anywhere" cures it only
  when an id is cited.
- Class-B packets do not move the rung either, so they are discharged only by an id or a same-turn write.

### 2.4 Fired-peer pings

The origin gate is D6's `oi_origin_class`, where ambiguity maps to origin. Measured read-only
(`bash /tmp/r2-C3/judge-fp/origin_probe.sh`, sourcing the repo lib against the live `cc-fired`, reading only), over the
**17 open stamps** fired since 10-04 with a transcript and a cwd:
- With the stamp's own pane id, **17/17 read `fired-peer`**.
- With an unknown pane id (the kitty-renumber case, by-cwd index plus inbound-marker fallback), **14/17**. The other
  **3 read `origin`** and become D8-eligible.

Probe `peer-renumbered` (stamp under pane 77, `CC_PANE_ID=78`, no index) ⇒ **FIRE** on "two items named below, both
routed to the lead"; the same case with `CC_PANE_ID=77` passes.

So the designer was right to assume the live gate exempts most peers. It does not exempt all of them. The precision
denominators exclude 6 in-sample and 10 held-out peer fires on that assumption.

### 2.5 Write-free sessions

The gate works: the designer's `write-free` control passes, and §2.2 shows it sparing real honest closes. The gate is
session-scoped, though, not turn-scoped. One Edit early in a long session makes every later close eligible, including
purely conversational re-closes (as in D6).

### 2.6 Quoted mentions

- Backticks, double quotes, fences, the template, a mention after the verdict, and a single-quoted mention on the verdict
  line all **pass** (designer controls plus my `singlequote-on-line` and `prose-mention-after` probes).
- One mechanism remains: a `>` blockquote of the incident line placed **before** the real verdict **FIREs**, because
  `close_verdict_yes_line` returns the first yes line (probe `blockquote-first`).
- **It has 0 occurrences in 3,296 verdict messages** (measured: `grep -lE '^[[:space:]]*>.*good to close'` over both
  `msgs/` dirs). Risk in theory only.

### 2.7 Precision per blocked stop, with the cap, and label disputes

The designer's precision is per unique close. A session feels blocked stops, and the `followon` cap is 2 per session.
Re-counted (measured: inline python over `variants-held.json` + `labels.json`, byte-identical copy sessions removed,
fired peers excluded):
- **Held-out: 25 unique closes ⇒ 17 blocked stops over 13 sessions** (≈1 blocked stop a day over the 16 days).
- **In-sample: 5 stops over 4 sessions.**

| Held-out, per blocked stop (17) | Designer's labels | Judge's labels |
|---|---|---|
| Incident class (agent-drivable, undriven) | 5 (29%) | **1 clear** (`404e1c00`) + 2 contested ⇒ **6-18%** |
| Contract (+ unfiled operator approvals) | 8 (47%) | **4-6 (24-35%)** |
| Stated parks blocked | 0 | **2** (`ac0f0123` ×2, §2.1) |
| Sessions whose only D8 blocks are false | — | **8 of 13** |

Label notes (each from the transcript):
- **`404e1c00` is a confirmed TP.** The Floor-tab fix was "mine, not yours". The operator then asked "Are you working or
  are you idling?", and the agent fixed it and landed Playwright 1.63. It is the incident's shape exactly.
- **`21a52acb` is an eval fixture.** cwd `/private/tmp/tokeff-bsys/runs/T18-plan-mark-done/r3/fx`, prompt "W2 landed,
  update the plan". Blocking it pushes implementation into a narrowly-scoped benchmark ask. Contested.
- **`5cbfbc98` is contested.** The turn's prompt quoted a recap whose "next action is to confirm that land and stop", and
  the close says "I've left it … since you said to confirm and stop".
- **OP-INT:** I agree with the designer that these are genuine operator picks inside an interactive loop. Blocking them
  for a packet per round fails constraint 2's purpose.

**Volume.** D8 is not an always-firing alarm: about 1 blocked stop a day held-out, 0.36 a day in-sample (estimated from
the counts above ÷ window days). Its constraint-1 failure is about **what** it fires on, not how often: by my labels,
most of its fires land where nothing agent-drivable remains.

## 3. The infrastructure claim: "dispatch-assert unscoped behaviour byte-equivalent"

It is **not byte-equivalent**. Arms 1-3 are moved verbatim. Arm 4 (the drop) used to match
`dropping|not worth|letting (this|that|it) go` (`/tmp/r2-C3/orig/hooks/dispatch-assert.sh`, `discharged_since`). It now
calls `sd_dropped`, whose `SD_DROP_RE` adds `dropped` (`diff orig repo2`). The 27/27 suite does not cover the difference.

Measured (`python3 -I /tmp/r2-C3/judge-fp/da_drop.py`, over the 51 `dispatch-assert` `fired` records in the IDL extract
`idl-ca-da.jsonl`, turn text = main-chain assistant text in `[since, ts]`): **2 of 51 fires would flip to discharged.**
Both match a drop of a *different* item:
- "I've dropped the idea of moving it back to `next`";
- "the only thing deliberately dropped was the first design run".

These would be new false negatives in dispatch-assert. The fix is to keep dispatch-assert on its own regex, or to give
`sd_dropped` a mode flag, and to measure before widening. I put the lib at 80-85% until that is fixed, not ≥90%.

## 4. Required changes before any re-submission

1. **Settle constraint 2 against parks** before more tuning. Either the operator rules that a prose park must be filed
   and cited (the constraint then changes), or D8 stops blocking and becomes a one-line surface. The designer's "surface,
   not block" next step is the only route measured here that does not break constraint 2 by construction.
2. **Re-label** `b3a4924832e3`/`89f38eeeaa87` as stated parks. Exclude eval-harness cwds (`/private/tmp/tokeff-*`) from the
   corpus, or gate D8 off in them. Report precision per blocked stop and per session, with the cap applied.
3. **Turn window versus other Stop hooks.** 22% of eligible closes start their turn at a `Stop hook feedback` record.
   Measure a window that skips hook-feedback boundaries, and check it still fires on the incident (that turn started at a
   task-notification, 1 h after the re-land row).
4. **Predecessor scope.** Count a handoff predecessor's sid as "this session" for packets and rows, or accept the
   documented FIRE.
5. **dispatch-assert drop regex**: restore byte-equivalence (§3), or justify the widening with its own measurement.
6. **Nil vocabulary.** 23 of 38 honest nil phrasings read non-nil. Each extension is a spelling list (the skeptic's
   objection). If D8 stays blocking, the block reason should at least show the exact cure (`follow-on: none.`).

## 5. Artifacts

`/tmp/r2-C3/judge-fp/`:
- `probes.sh`, `probes.out` (21 hook probes on v2b);
- `nilprobe.txt` (48 values);
- `variants_j.py`, `variants-census.json`, `variants-held.json`;
- `nilled.py`, `turnstart.py`, `origin_probe.sh`, `da_drop.py`;
- `runbats.sh`, `followon.tap`, `followon.summary`.

The probe run dirs are `/tmp/r2-C3/run-jfp-*`.
