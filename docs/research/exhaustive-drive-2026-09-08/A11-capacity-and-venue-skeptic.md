# A11 skeptic — capacity and venue: what survives re-measurement

**Wave:** exhaustive-drive 2026-09-08 · **Role:** skeptic for A11 · **Mode:** read-only; every command
below was re-run 22:10–22:40Z under load 238/208/164 on 10 cores (`uptime`), cc_sp_active=7, operator present.

## Verdict in one paragraph

The axis's central claim survives: the Agent-tool gate refused 20 of 38 spawns today (re-measured, identical
counts), the refused work was re-venued onto the lead with no store recording it (now 5 of 6 sessions, not 3 of
3 — the IDL rows carry `sid`, and the three sessions the axis never opened tell the same story), and
handoff-fire's active term is blind on 48/48 production admits for exactly the subshell-scope reason given.
Two of its numbers do NOT survive. (1) The "12 rc=7 `no pane anchor resolved`" fires that anchor R6 are 100%
`cc-dispatch selftest` stub output: the string exists only inside the selftest's spawn stub
(`bin/cc-dispatch:3495`, heredoc `STUB`), `scripts/handoff-fire.sh` never emits it, the selftest pins
`CC_DISPATCH_IDL`/`SPAWN_BIN`/`PAGES_DIR` but not `CC_DISPATCH_FIRE_LOG` (`:3504-3508`), and the 36 headers
carrying it are six fixture ids × six 3-hourly runs, none of which exists in `backlog.jsonl`. The real dominant
fire failure today is the INC-4 cold-worktree autosubmit race (13 of 20 IDL `failed` rows), which the axis never
names. (2) "`claude-accounts --rank general` routes to 3 accounts, so the no-capacity class is unsatisfiable"
is false at this moment: it returns `no routable account … concurrency-unmeasured` → `none`, i.e. the class's
first conjunct is satisfied by an INSTRUMENT failure under the same load that produces refusals. R4's example
formula is inverted (budget shrinks as the breach grows). R5 lacks a clear path for the disposition that actually
happens (inline completion), so as written it is an alarm that fires on every close after any refusal.

## Numbers re-checked (measured)

| # | Claim | Command | Result |
|---|---|---|---|
| 1 | 20 refuse / 38 Agent-tool evals | `jq -rc 'select(.gate)\|[.gate,.verdict,.basis,.caller]\|@tsv' ~/.claude/autonomy/idl.jsonl \| sort \| uniq -c` | capacity-admit agent-tool: refuse 20 · admit headroom-only 12 · admit budget-expired 6 = 38. **Holds.** Plus boot-resume-launch: 6 admit / 3 refuse. |
| 2 | 15 refusals in 3 hand-read sessions, 0 filed, 0 retried | IDL `sid` field on refuse rows (`jq 'select(.gate=="capacity-admit" and .verdict=="refuse")\|[.ts,.caller,.sid]'`) | 20 agent-tool refusals across **six** sids: ecdc97fa 5 · e5ab6841 6 · 98af4df2 4 · 2c9d5c43 2 · c72ea92c 2 · b0bf12dc 1. Axis read 3/6. I read the other three: 2c9d5c43 "running serially on the lead as the gate instructs" (10:50:02Z); b0bf12dc "Subagent refused … Running serially" (15:47:49Z); c72ea92c no narration — went straight to Bash/Edit at 14:46. Each Agent description appears once per transcript in all three. **Holds and extends to 5/6 narrated serial, 6/6 zero retry, 6/6 zero filed.** |
| 3 | ecdc97fa ran A/B/D/E/F inline | transcript text after 09:18Z | Axes A, B, E measured inline from 12:58Z ("All of axis A is measured", "auditing entry points (axis B)", "Checking the migration surface (axis E)"). **Holds.** But the inline work began 3h40m after the refusal because the Bash call at 09:18:39 did not return until 12:58:21 (tool_result timestamp) — the axis's "≈3 min refusal-imposed delay" measures the gate's release, not when the refused work started. |
| 4 | 48/48 production fire admits `blind: active`, 0 refusals | `jq -rc 'select(.gate=="capacity" and (.under_test\|not) and .verdict=="admit")\|(.detail\|capture("blind: (?<b>[a-z, ]+)").b//"none")' ~/.claude/logs/handoffs.jsonl \| sort \| uniq -c` | `48 active`; `{"admit":48}`. **Holds.** Last row 21:39:28Z; live `~/.claude/scripts/handoff-fire.sh` → checkout copy (readlink), 10,938 lines both, region 4990-5015 identical; last commit on the file 233cec7c9 21:11Z — still blind after it. |
| 5 | Root cause: only sourcing site inside `$( _cc_fire_presence )` | `grep -n spawn-presence scripts/handoff-fire.sh` → :4998-5001 (inside `_cc_fire_presence()`), invoked at :5152 `CC_FIRE_PRESENCE="$(_cc_fire_presence)"`; term at :5359-5362 tests `command -v cc_sp_active` | **Holds.** Note the cheaper fix: handoff-fire already sources `capacity-admit.sh` at top level (`:4889-4892`), whose `_cc_admit_load_presence()` (`:457-476`) does the sourcing at function scope — calling it before the term suffices. |
| 6 | cc_sp_active = 9 > ceiling 8 "a fire right now SHOULD refuse" | `bash -c '. scripts/lib/spawn-presence.sh; cc_sp_active'` | **7** now (trees 27, operator present). Time-dependent; today's evaluations saw active ∈ {1×12, 10×1, 11×2, 12×14, 16×9} (from refuse/admit details). The mechanism claim stands; the "right now" clause is stale. |
| 7 | Budget keyed on `<caller>`, CC_ADMIT_BUDGET=3 | `capacity-admit.sh:509-514` `_cc_admit_state_file` → `$dir/<caller>.refusals`; `:564`; `ls ~/.claude/autonomy/capacity-admit/` → `agent-tool.refusals` (one file) | **Holds.** |
| 8 | Budget released "at 16 mid-turn … six times" | `jq 'select(.basis=="budget-expired")\|.detail'` | 6 releases: **2 at 16**, **4 at 12**. Direction holds; "at 16 six times" overstates. |
| 9 | 90 real dispatch fires, 47 non-zero, 12 rc=7 'no pane anchor resolved' | `awk` over `~/.claude/logs/dispatch-fires.log` today, excluding `item=i[0-9] ` | rc census reproduces (43/34/1/12) **but** 36 of the 90 headers are stub fires: items 27f29c9ce2a8 · 2d4ff6c81200 · 723d9e9cff68 · 7d5ccfd3f67b · b1dd4c7c9f05 · e6366921d839, each ×6 at 01:53 · 05:35 · 08:27 · 11:34 · 16:26 · 19:35Z, each followed by the stub's line. `jq 'select(.id=="723d9e9cff68")' backlog.jsonl` → 0 events (4 of 6 checked). All 12 rc=7 are two of those ids (`STUB_SPAWN_RC=7`, `bin/cc-dispatch:3865,3886`). **Refuted as production evidence.** Real fires ≈ 54 headers; real launches 19 (`fired:` lines today, holds). |
| 10 | Dominant actuator failure = pane anchor | IDL: `jq 'select(.actor=="cc-dispatch" and .action=="failed")'` classified | 20 failed / 14 fired today. Causes: **13 INC-4 cold-worktree-fire-autosubmit-race** · 4 "ring pane N not found in iTerm2 (settled + retried)" · 2 anchor probe INCONCLUSIVE/congested · 1 rc=2 syntax. Anchor-shaped failures = 6/20 = 30%. **Diagnosis refuted; failure rate (59%) holds in direction.** |
| 11 | Queue 137→101, 96 unchanged, 2.9 rows/h | re-run of the axis's `comm` recipe | first pass 09:21:17Z 137 · last pass 22:12:48Z 102 · common **96**. **Holds.** |
| 12 | live_workers 1–8 vs ceiling 12 | `jq … awk '!seen[$1]++'` | distribution 1:2 2:19 3:24 4:15 5:2 6:10 7:11 8:6 — max 8. **Holds.** |
| 13 | 0 no-capacity filings | why_not_now class census | 0 (14 not-yet-true, 8 needs-human, 54 re-keyed). **Holds.** |
| 14 | "3 accounts route → class unsatisfiable" | `timeout 200 bin/claude-accounts --rank general` | First attempt rc=124 at 60 s; second: `claude-accounts: no routable account for general: next=concurrency-unmeasured; next4=…; next3=…; next2=…` then `none`, rc 0. **Refuted now.** `bin/claude-accounts:2988-2994` returns this when `ps` AND the transcript walk both failed — DATA_UNAVAILABLE (`:3355-3361`) by design, exit 3 for callers. `cc-backlog:1752` reads "routes nowhere" literally, so a legal `no-capacity:` row is constructible right now on a blind instrument. |
| 15 | cc-eligible 23/357, 152 box, 75 cross-repo | `python3 bin/cc-eligible sweep` | 354 non-done · eligible 23 · ineligible-box 151 · cross-repo 75 · offbox-lane 33 · spawn-rail 22 · visual 23. **Holds.** |
| 16 | 62 falsify events today | `jq 'select(.event=="falsify")\|.ts[0:10]' backlog.jsonl` | 64 (09-08), 16 (09-07), 34 (09-06). **Holds.** `--condition`/`--falsifier` present in `bin/cc-backlog` header. |
| 17 | Multi-day: 08-29..09-04 132 evals / 0 refusals | gzcat archives | 08-29..09-04: **159** evals, 0 refusals; 09-05 45/11 · 09-06 16/20 · 09-07 10/1 · 09-08(pre-rotation) 7/8. Denominator differs (159 vs 132); the zero and the 09-05 onset hold. |
| 18 | parked-briefs: 1 file, 0 code readers | `ls`; `grep -rln` | 1 file (2026-08-09); only `scripts/growth-coverage.conf`. **Holds.** |
| 19 | boot-resume-launch stderr-only deferral | `sed -n 275,285p` | **Holds** (exit 9, two `>&2` lines, no row). |
| 20 | 0e0c5a875dc0 still open | backlog events | add 08-25, two `venue` events, no done. **Holds.** |
| 21 | No ledger term for degraded fan-out | `grep -c SPAWN_DEFERRED scripts/wrap-ledger.sh hooks/completion-assert.sh` | 0 / 0. **Holds.** |

Presence on the 23 refusals (`[.presence,.reserve]`): 12 `self` · 6 `absent` · 5 `present`. The deny text's
premise for serializing — "while the operator is working" — did not hold for 6 of them.

## Per-recommendation verdicts

**R1 (spool the refused brief) — not refuted; conviction 92 → 80.** Mechanism real (`INPUT=$(cat)` at
`agent-teams-enforce.sh:23`; deny at `:230-243`; the brief is discarded). Fail direction as stated, plus one the
axis did not state: the replacement advice clause ("N briefs are spooled and will be re-offered") is a promise
whose truth depends on R2's lane being alive; `parked-briefs/` is what a spool looks like when the promise was
made and the lane died. Ship R1 and R2 in one diff or ship neither.

**R2 (desk lane drains on `cc_sp_active < ceiling`) — not refuted; conviction 84 → 65.** Condition is
computable and `--condition`/`--falsifier` exist. Two unstated fail directions: (a) `cc_sp_active` is a proven
LOWER BOUND and the Agent path runs with the load term OFF — at the moment of this review the drain condition is
TRUE (7 < 8) while the box carries load 238 on 10 cores (`ps` top: bash/grep/python, i.e. our own per-turn
fan-out), so the drain re-offers into a saturated box and the re-offered spawn is then ADMITTED (7+1 ≯ 8). It
errs OPEN on the box, inheriting exactly the blindness the axis's §8 caveat names. (b) When the owner is gone the
promotion target is the backlog — the store the axis measured at a 14-day median for capacity parks. The
falsifier makes it self-retract, not self-drain.

**R3 (un-blind handoff-fire's active term) — not refuted; conviction 95 → 93.** File:lines and 48/48
confirmed; live copy is the checkout. `cc_sp_active` reads 7 now, not 9 — the "would refuse immediately" claim
is stale, not wrong. Cheaper fix than proposed: call the already-sourced `_cc_admit_load_presence` before
`:5355`. Fail direction (closed) stands. Ordering claim (after R1/R2) stands.

**R4 (breach-sized budget) — REFUTED as written; conviction 71 → 35.** Keying (`<caller>.refusals`) and the
1-in-3 release are real. But the offered formula `max(1, ceiling*2 − active)` yields budget=1 at active=16
(the 2× breach the axis says should "effectively hold") and budget=7 at active=9: it releases FASTEST under the
heaviest breach — the inverse of the stated intent. Also the budget file is shared with the reserve terms (the
axis's own open question 5). Redo the arithmetic before landing; the direction (size to the breach) may still be
right.

**R5 (`SPAWN_DEFERRED_MINE` → 🔧) — partially refuted; conviction 78 → 45.** Term absent today (measured). As
specified, the spool clears only on the admit path (same description re-spawned). The disposition that actually
occurs — 5/6 sessions today — is inline completion, which has no clear verb, so the term fires on every close
after any refusal until the lead re-spawns work it already did: an alarm that always fires after the triggering
event carries no bits and trains the model to route around it (memory `alarm-polarity-and-attention-budget`).
Needs an explicit `done-inline <sha>` verb before it is a ledger term rather than a nag.

**R6 (reserved headless pane anchor) — REFUTED on its evidence; conviction 88 → 30.** The 12 rc=7 are selftest
stub fires in the production log (row 9); the real anchor-shaped failures are 6 of 20 (row 10); the dominant
cause is the INC-4 autosubmit engagement race, which a reserved anchor does not touch. Unstated fail direction:
"~4 permanently unused slots" compares the dispatcher's worker ceiling (12) against a different population than
the Agent gate's mid-turn ceiling (8); with active already at 9–16 all day, filling those 4 slots pushes the
Agent gate into MORE refusals — R6 would increase the serialization the axis is trying to cure. The fix worth
keeping from R6 is the one the axis flagged for handoffs.jsonl and missed here: split `dispatch-fires.log` on
test provenance (pin `CC_DISPATCH_FIRE_LOG` in `selftest()`).

**R7 (do-nots: no cloud, no ceiling raise, no no-capacity path) — holds on two of three; conviction 90 → 80.**
Cloud eligibility re-measured (23/354). Ceiling caveat stands. The third premise is refuted: the no-capacity
class IS constructible right now via `concurrency-unmeasured`. The conclusion (do not add a filing path) is still
right, but the missing action is to tighten `valid_why_not_now`/its definition so a DATA_UNAVAILABLE routing
result cannot satisfy the first conjunct — otherwise the class fails toward FILING under exactly the load that
produces refusals (correlated failure, `fail-safe-default-mimics-the-healthy-state` in the refuse direction).

## What the axis missed

1. Three of the six refused sessions (5 of 20 refusals) were never opened, though the IDL rows carry `sid`.
2. `dispatch-fires.log` has no test-provenance split; 36/90 of today's "real" fires are selftest stubs.
3. INC-4 cold-worktree autosubmit race is the dominant real fire failure (13/20) and is unnamed.
4. `claude-accounts --rank general` can return "routes nowhere" on instrument blindness, making the
   no-capacity class mintable under load.
5. R4's formula is inverted.
6. The Agent gate admits right now at load 238/10 cores (active=7, load term off); "the box survived every
   refusal" is not a measurement of the box.
7. The drain condition (R2) and the ceiling share the same lower-bound instrument.
8. Refusal-imposed delay measures the gate (3 min), not the refused work (ecdc97fa: 3h40m to first inline axis,
   attributable to a hung Bash call, not the gate — inferred).

Sources opened last that added nothing: `launchd/` plist listing; `bin/claude-accounts:3352-3362` after 2984-2996
(same fact). Stopped there.
