# Plan lifecycle: how often "complete" plans move their goalposts, and why

Unit: `plan-lifecycle` (read-only). Written 2026-09-30.
Repos: `/Users/chrisren/Development/claude-infrastructure` (trunk `f726a3a56`) and `~/Development/reso-management-app`.
Working files: `/tmp/rescomp/internal/logs/*.log` (per-plan `git log` dumps), `/tmp/rescomp/internal/bd_corrected.txt`, `/tmp/rescomp/internal/lr_goals_clean.tsv`.

## 0. Answer first

1. **Only 7 of 158 goalpost moves (4.4%) came from a new operator requirement.** The rest the process generated itself. The largest classes: claims that were **false when written** (43, 27.2%), things **only visible once built or run** (41, 25.9%), **environment drift** (24, 15.2%), **re-deriving lost or stale research** (15, 9.5%), **critic passes adding items** (14, 8.9%) and **missed axes** (14, 8.9%). Excluding the operational drain log, verification-by-building is the top class at 30.2%.
2. **"Complete" was declared early, on thin acceptance.** `LIMIT_RECOVER_100P` went COMPLETE in 2 days on **n=1** (one throwaway pane), was reopened 9 days later when the first real run of **n=5 recovered 1 of 5 in 98.7 min**, went "W1–W7 complete" again, and then needed **9 more fix or feature goals in 8 days** before a new plan replaced it. Counting sessions, that one subsystem has used **30 distinct `/goal` conditions in 22 days**. `INSOMNIAC_DENVER_PROVISIONING` read "LIVE" after about 9 hours on 2026-08-21. An authenticated read on 2026-09-13 found `floor_plan_element=0, bottle_menu_item=0`: the room was empty, and 40 days after the plan opened the customer deliverable is still on the mission board.
3. **The problem statements themselves were usually wrong.** In the 12-row ground-up campaign map, **10 of the 12 original constraint cells** were later annotated FALSIFIED, RENAMED, INSUFFICIENT or UNMEASURABLE. Research spent on the stated problem was partly spent on the wrong problem.
4. **The designated growth marker sees about 1 move in 20.** Across 104 plans, `Scope (grown)` appears **21** times, against **257** `REFUTED`, **249** `superseded`, **64** `CORRECTED` and **37** `RETRACT`. Moving goalposts mostly enter as refutations and supersessions, so the Follow-On Gate's audit trail cannot count them.
5. **The one plan that closed and stayed closed did its verification before building.** reso `DOCS_CONSOLIDATION_100P` ran all 58 acceptance commands against unmodified trunk before building. 45 turned out unsound and were replaced by one self-testing harness. The plan went from first commit to "programme complete" in **25.75 h** and was never reopened (its only later commit is whitespace). `LIMIT_RECOVER_FLEET_V2` looks similar so far: a 22-agent workflow with 5 skeptics found 7 fatal and 30 major defects in the design before any code, a measurement wave (W0) ran first, and W0–W6 landed in about 1.5 days.

## 1. Method

- **Selection** follows the task's rule: plans whose names contain 100P, GROUND_UP, GROUNDUP or V2, or that carry a `Scope (grown)` line, ranked by size, top 8 across both repos. The ranking is receipted by `wc -c` (sizes in §2). `KITTY_DRAG_ACTION` qualifies only through its `Scope (grown)` line. `GROUND_UP_DISPATCH` qualifies by name; its twin `GROUND_UP_REBUILD_MAP` (111 KB) is used for the campaign-level row data.
- **Edit counts** come from `git log --format='%h|%ad|%s' --date=iso-strict -- <plan>`, without `--follow`. `--follow` over a 430-commit file did not finish in 10+ minutes, and none of these plans shows a rename in its history.
- **"Claimed complete"** is the first commit or status line asserting COMPLETE or DONE, cited by sha or line.
- **Events.** A growth or reopen event is any one of:
  - a `Scope (grown)` line;
  - a REOPENED section;
  - a `CORRECTED`, CORRECTION, RETRACT or REFUTED section or line, where the plan corrects its own earlier claim;
  - a new-program section added after a DONE;
  - a supersession;
  - a commit whose subject states that an earlier plan claim, measurement or DoD was wrong or had moved.
  Duplicates (one event cited on two lines) are merged, and each merge is recorded.
- **Classes.** The task's six, plus one this unit added:

| code | class | meaning |
|---|---|---|
| NOR | new operator requirement | the operator asked for something outside the frozen scope |
| MA | missed axis | a dimension that was in reach of the research and not covered (including seams between sibling plans) |
| VOB | verification-only-by-building | discovered only by building, landing, or running on real load |
| EC | environment changed | the world moved: a binary, a reboot, a sibling land, backlog inflow, a count that drifted |
| RLR | re-derivation of lost research | stale inherited notes, lost continuation, a record that disagrees with disk |
| CR | critic re-generation | a critic, skeptic or adversarial pass produced new items or amendments |
| **RE** | **research error (added)** | a claim that was **false when written**: wrong unit, wrong field name, an instrument that measured something else. The six classes have no home for this, and it is the single largest class, so leaving it out would have hidden the main finding. |

- **Coder caveat.** All classification is a single pass by this unit, made from commit subjects and section text. There is no second rater. Some events could reasonably take two classes; the primary class is chosen by *how the move was discovered*.

## 2. The 8 plans: lifecycle metrics

| # | plan (repo) | size | commits | first commit | claimed complete | reopened / grown after complete | last edit | active days | status now | `Scope (grown)` | `CORRECTED` | correction-signal commit subjects* |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `BACKLOG_DRAIN_24_7` (infra) | 2,977 KB / 33,937 lines | **430** | 2026-08-16 | never (open drain) | n/a: 336 recycles (`:90`), numbered "methods" up to 272 (`:609`) | 2026-09-26 | 27 | open | 6 | 30 | 85/430 (20%) |
| 2 | `DOCS_CONSOLIDATION_100P` (reso) | 242 KB | 42 | 2026-08-20 03:57 | **2026-08-21 05:42** `249cbacd3` | **none** (only later commit is whitespace `0d203fe8a`) | 2026-08-24 | 3 | open (frontmatter), programme complete | 0 | 0 | 6/42 (14%) |
| 3 | `GROUND_UP_DISPATCH` (infra) | 167 KB | 48 | 2026-07-29 00:42 | never; 10 of 13 rows DONE by 2026-08-07 (`:416`) | row 13 added the same day (`:1743`); row 14 added 2026-08-07 (map `bb5e9f7a1`); **dormant 8 days** (`:404`); re-armed 2026-08-11 (`:318`) | 2026-08-10 | 6 | open | 0 | 0 | 10/48 (21%) |
| 4 | `MACHINE_CAPACITY_V2` (infra) | 165 KB | 28 | 2026-07-29 15:11 | row DONE 2026-07-29 17:37 `e27adea06` | §11 completion program, an operator directive **5 h later** (`:958`, `08561cca2`); §12 after a kernel panic 2026-07-31 (`:1379`) | 2026-08-09 | 6 | open | 0 | 1 | 9/28 (32%) |
| 5 | `INSOMNIAC_DENVER_PROVISIONING` (reso) | 159 KB | 35 | 2026-08-21 00:31 | "LIVE from Dallas", Waves 1–3 COMPLETE, 2026-08-21 (`:9-10`, `e7b5955a7`) | Waves 4–5 2026-08-26, Heist-parity research 2026-08-26/27; **mission board 2026-09-13: room empty** | 2026-08-27 | 5 | open | 1 | 0 (1 "CORRECTION" heading `:947`) | 10/35 (29%) |
| 6 | `LIMIT_RECOVER_100P` (infra) | 151 KB | 35 | 2026-09-08 20:46 | **2026-09-10 15:39** `9302ded90` | **REOPENED 2026-09-19** `601807233` (`:319`); "W1–W7 complete" 2026-09-21 `b73aa3819`; superseded in shape 2026-09-29 (`:933`) | 2026-09-29 | 8 | open | 4 | 0 | 10/35 (29%) |
| 7 | `KITTY_DRAG_ACTION` (infra) | 135 KB | 8 | 2026-09-16 15:33 | agent side done 2026-09-17 (`:24`) | the phase-1 research was reopened by its own critic before this plan existed (`:8-13`) | 2026-09-17 | 2 | open (2 DoD items need the operator's hand) | 1 | 5 | 3/8 (38%) |
| 8 | `USAGE_TELEMETRY_100P` (infra) | 133 KB | 13 | 2026-08-16 03:55 | wave 1 "M3 done and live" 2026-08-16 `c128cd499` | §5 wave 2 opened 2026-08-25, **9 days later**, for the strand axis wave 1 missed (`:561`, `aaba84e58`) | 2026-09-04 | 4 | open | 0 | 0 | 0/13 by regex; the subjects read "three comfortable claims killed" and similar, which the regex misses |

*Correction-signal regex (commit subject): `correct|wrong|refut|retract|stale|false|falsif|rotted|withdraw|reopen|overclaim|misread|was not|never existed|inert|phantom|contaminat|superse`. It is a lower bound: USAGE_TELEMETRY scores 0 with obviously corrective subjects.

### 2.1 Supplementary: the next qualifying plans (metrics only)

| plan | commits | span | active days | status | note (receipt) |
|---|---|---|---|---|---|
| `HOOK_SURFACE_100P` | 20 | 09-05 → 09-10 | 5 | complete | "A fifth unknown, not previously on the board: the handler-type surface is bigger than the plan knew" (`:789`); 2.1.251 shipped two events never probed (`:9-11`) (EC) |
| `LIMIT_DETECT_100P` | 18 | 09-19 → 09-25 | 4 | open | critic pass found 15 gaps, each folded in as a BINDING amendment (`:537`); a sibling of LR100P, and the seam between them dropped the request writer (LR100P `:772-777`) |
| `GROUND_UP_REBUILD_MAP` | 46 | 07-29 → 09-09 | 9 | open | 12 → 14 rows; 10 of 12 original constraint cells amended (§5.3); "the re-dispatch loop cannot terminate" (`69e6519a4`) |
| `DRAIN_CIRCUIT_2026-09-01` | 26 | 08-31 → 09-17 | 9 | — | 1 grown: a pre-existing trunk red gating the land (`:1573`) (EC) |
| `LIMIT_RECOVER_FLEET_V2` | 22 | 09-29 → 09-30 | 2 | in-progress | 22-agent workflow with 5 skeptics; revision 1 had 7 fatal and 30 major defects found *before* build (ARCH `:0 Summary`); W0–W6 landed in about 1.5 days. The plan's Provenance says "4 fatal" and the architecture says "7 fatal", an internal inconsistency |
| `ACCOUNT_ROUTING_V2` | 11 | 07-29 → 08-13 | 5 | — | 2 grown, both MA (`:379`, `:402`) |
| `LAND_PIPELINE_V2` | 32 | 07-28 → 09-17 | 12 | — | row 1 DONE 07-28 (map `:17`), yet edited across 12 active days over 7 weeks |
| reso `FLOOR_PLAN` | 169 | 08-20 → 09-05 | 6 | open | no qualifying marker, but it is the operator's exact complaint in writing: "For two days the operator asked 'are we complete?' and got 'yes' — each time true of the wave then running and false of the question asked… a per-wave DoD makes an honest close and a wrong answer the same act" (`FLOOR_PLAN.md:63-66`) |

## 3. Counts by class

| plan | NOR | MA | VOB | EC | RLR | CR | RE | total |
|---|---|---|---|---|---|---|---|---|
| BACKLOG_DRAIN_24_7 | 0 | 2 | 3 | 6 | 5 | 1 | 15 | 32 |
| DOCS_CONSOLIDATION_100P | 0 | 1 | 3 | 5 | 2 | 2 | 7 | 20 |
| GROUND_UP_DISPATCH (+map) | 0 | 3 | 3 | 5 | 3 | 0 | 6 | 20 |
| MACHINE_CAPACITY_V2 | 1 | 1 | 5 | 2 | 1 | 3 | 3 | 16 |
| INSOMNIAC_DENVER_PROVISIONING | 2 | 2 | 5 | 0 | 1 | 1 | 7 | 18 |
| LIMIT_RECOVER_100P | 4 | 3 | 14 | 1 | 2 | 3 | 3 | 30 |
| KITTY_DRAG_ACTION | 0 | 1 | 3 | 4 | 1 | 1 | 1 | 11 |
| USAGE_TELEMETRY_100P | 0 | 1 | 5 | 1 | 0 | 3 | 1 | 11 |
| **Total (158)** | **7 (4.4%)** | **14 (8.9%)** | **41 (25.9%)** | **24 (15.2%)** | **15 (9.5%)** | **14 (8.9%)** | **43 (27.2%)** | **158** |
| Total excluding the drain log (126) | 7 (5.6%) | 12 (9.5%) | **38 (30.2%)** | 18 (14.3%) | 10 (7.9%) | 13 (10.3%) | 28 (22.2%) | 126 |

**Every `Scope (grown)` line in the corpus** (21 hits across 11 infra plans plus 1 in reso; MCP `:470` is an instruction, not an event, and LR `:776`/`:848` are one event, leaving **20 events**): MA 9, VOB 6, EC 3, NOR 1, CR 1. The marker is used almost entirely for adjacent Follow-On Gate growth. It is not where research reversals get recorded.

**Corpus markers (104 infra plans):** `Scope (frozen)` 100 hits in 76 files · `Scope (grown)` 21 in 11 · `CORRECTED` 64 in 17 · `REOPENED` 12 in 5 · `superseded` 249 in 62 · `REFUTED` 257 in 41 · `RETRACT` 37 in 14. Research tree (3,365 .md files): `REFUTED` 668, `superseded` 586, `CORRECTED` 86, `Scope (grown)` 22. Command: `cat docs/plans/*.md | grep -oE '<pat>' | wc -l`. Plan statuses: complete 50 · open 31 · in-progress 16 · superseded 2 (`grep -hE '^status:' docs/plans/*.md | sort | uniq -c`).

## 4. Timelines with receipts

`L`-prefixed receipts are line numbers in that plan; shas are commits touching it.

### 4.1 LIMIT_RECOVER_100P: the loop in its purest form

| when | event | receipt | class |
|---|---|---|---|
| 09-08 20:46 | opened; frozen scope says "Research it to 100th percentile first… then implement" | `bb44e2193`, L18-22 | — |
| 09-09 02:00 | research wave: 8 of 10 spawns refused by capacity-admit; axes run serially | L186-189 | — |
| 09-08 23:20 | "3 harness pins" were **four defects, three in shipped code** | `26d72a5c2`, L190-195 | VOB |
| 09-09 | live-parser preflight added after E2E | L268 `Scope (grown)` | VOB |
| 09-10 15:39 | **CLOSED / COMPLETE**; the two items §8 listed as "Filed" had **never been filed** | `9302ded90`, L298-300 | RLR |
| 09-19 16:38 | **REOPENED**: "`status: complete` rested on n=1… first production run… 98.7 min wall for 5 sessions, 1 RECOVERED / 4 PARTIAL" | `601807233`, L319-324 | VOB |
| 09-19 18:52 | reconciled with sibling plan `LIMIT_DETECT_100P`: detection is theirs | `af83c5ce4`, L402 | MA |
| 09-19 19:23 | "correct cause 5 — a backwards route, not residue" | `874fd9197` | RE |
| 09-19 20:34 | §10 `Scope (grown)`: in-place by default, the operator's verbatim words | `3004fd282`, L443-449 | NOR |
| 09-19 20:53 | "the cross-root glob that made 80% of sessions unrecoverable" | `d4c864309` | VOB |
| 09-20 02:0x | critic pass: 17 items, 6 refuted and 10 partly refuted, folded in as BINDING | L584-606 | CR |
| 09-20 03:54 | "W2 adversarially verified after landing; it does not meet its own DoD" | `fe9a22d0f` | CR |
| 09-20 03:57 | W3 ingest half fails its adversarial pass | `0bc639660` | CR |
| 09-20 05:33 | "W3p's suite defends the argv defect that makes the wave inert" | `4c5c47d77` | VOB |
| 09-20 08:03 | "my load-fragility diagnosis was wrong, the cause was stdin EOF" | `6df22ddaf` | RE |
| 09-20 08:31 | stage 2 catches an inert predicate | `f569c6f67` | VOB |
| 09-20 11:52 | "W3i held because its gate refuses 69 of 69 real bundles" | `999af9e92` | VOB |
| 09-20 16:16 | "my own fixture produced the last false 'inert'" | `677cf8bf4` | RE |
| 09-20 16:44 | "the W3p residual I filed as open was already closed, and I never re-ran it" | `86eb2a6a6` | RLR |
| 09-20 22:43 / 22:50 | the sibling plan dropped the request writer and this plan narrowed it out, so nothing produced requests; W5 grows by one item. "the residual-7 claim… rotted in 40 minutes" | `62d222011`, L772-777, `8c336e581` | MA; EC |
| 09-21 01:07 | "182 mutants, and the predicate that is inert" | `30b69159c` | VOB |
| 09-21 04:01 | **"lr100p W1-W7 complete"** | `b73aa3819` | — |
| 09-22 → 09-29 | 9 more limit-recover goals: `cc-lr switch` and `cc-lr upgrade` ×2 (new features, NOR ×3); switch leak fix; relaunch pane address; "the four limit-recovery defects"; "the five /limit-recover gaps"; "All five fixes F1-F5"; "all three pane-UI defects" (VOB ×6) | `lr_goals_clean.tsv` rows 09-22T17:26 … 09-29T00:49; transcripts `798afadf`, `1f0976b5`, `32952438`, `1107836f` | NOR ×3, VOB ×6 |
| 09-27 07:07 | operator: *"(Why are we idling -- we still have the same panes to /limit-recover that are still not)"* | `~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/bed3478f-….jsonl` | — |
| 09-29 03:07 | superseded in shape by `LIMIT_RECOVER_FLEET_V2` (one-at-a-time → concurrent reconciler) | `0eddb2a3e`, L933-943 | MA |

Total `/goal` conditions naming limit-recover, 2026-09-09 → 09-30: **30** (`/tmp/rescomp/internal/lr_goals_clean.tsv`, extracted from 4,130 transcripts modified since 09-08).

### 4.2 MACHINE_CAPACITY_V2: DONE, then the frame falsified, then the program re-scoped

| when | event | receipt | class |
|---|---|---|---|
| 07-29 15:11 | opened: 30 sessions, ≥95% of bats CPU in the background band | `b9fc76b0d`, L7 | — |
| 07-29 15:45 | "RETRACT the deploy recommendation — adversarial pass falsified the row's frame"; §8.5.7 "load is NOT a function of session count" | `ea13e9c0d`, L480-484 | CR |
| 07-29 17:37 | map row 13 **DONE** | `e27adea06` | — |
| 07-29 18:08 | "AC1 is NOT met and a PATH shim cannot meet it — measured post-activation" | `933879369`, L694 | VOB |
| 07-29 18:20 | §9.5 self-correction: the "permanent dispatch outage" projection was falsified | `7557f6afb`, L741 | RE |
| 07-29 22:49 | **§11 COMPLETION PROGRAM**: operator directive "eliminate the possibility… at 15–30+ concurrent sessions — SYSTEMIC" | `08561cca2`, L958-962 | NOR |
| 07-30 00:07 | shadow mode rejected by 3 of 3 reviewers; a live bug found | `99e6bd994`, L827 | CR |
| 07-30 00:17 | §11.9 "two premises falsified" | `1524d61fa`, L1103 | RE |
| 07-30 00:43 | §11.10 agent-lifecycle gap found *during* the wave (16 idle claude.exe ≈ 8.5 GB) | `ce990d5b4`, L1157-1161 | MA |
| 07-30 01:06 | "AC1 is MET at 100% — the '~70% ceiling' was a contaminated denominator" | `c0f244311`, L877-883 | CR |
| 07-30 02:10 | a sibling's correction lands mid-campaign; "M7's bats-token rewrite half solved a phantom" | `5f58e4fd3`, L1308-1314 | EC |
| 07-31 10:36 | "the row carried a DONE cell over a red gate" | `224d6b166`, L1324 | VOB |
| 07-31 12:16 | §12 post-panic pass (kernel spinlock panic 11:46:47) | `dbfe9afcf`, L1379-1382 | EC |
| 07-31 13:53 | "the prescribed fork-storm fix does not pay, and its cost model was 4x too big" | `0e86e9caa`, L1656-1667 | VOB |
| 07-31 14:02 | "landed is not live; the 18 ms/call win is inert" | `cc4e28874`, L1795 | VOB |
| 07-31 17:15 | "a retraction's corroboration cited a different gate's rows" (§9.5.1: "the same defect one level up") | `019469bca`, L763-767 | RE |
| 08-06 | AC22 red on a real unbounded probe | `315772eb2` | VOB |
| 08-09 | "the plan's only ladder record said 4 rungs while the alarm ran 7" | `fb6f329d0` | RLR |

### 4.3 GROUND_UP_DISPATCH and REBUILD_MAP: campaign level

| when | event | receipt | class |
|---|---|---|---|
| 07-29 00:42 | campaign opened: 12 rows | `8154b1eab`, L7 | — |
| 07-29 11:33 | "constraint cells are claims — mandatory Phase 1 re-derive"; see the §5.3 tally, 10 of 12 cells amended | `30c900530` | RE |
| 07-29 12:21 | row 5 lead died mid-work, orphaning 5 assignees | `92a40a133`, L537 | EC |
| 07-29 14:22 | "row 12 falsifies the coordinator's daemon count" (two daemons flipped on that day) | `a853fb716`, L725-735 | EC |
| 07-29 14:29 | corrected deploy-live verdict | `8ed8615f1`, L750 | RE |
| 07-29 15:03 | "the payload template was propagating a stale count into 7 remaining fires" | `6ce912b30` | RLR |
| 07-29 15:13 | "one un-executed land strands work for five remaining rows" | `4ac06614a`, L1438 | RLR |
| 07-29 15:34 | "the orphan census was wrong at 5" | `f872db0ce` | RE |
| 07-29 16:09 | "the cadence guard duplicated a chokepoint gate, and duplicated it worse" | `743f064e9`, L1644 | RE |
| 07-29 16:56 | "the corrector got overtaken too — stop carrying numbers in payloads" | `247365cc0` | EC |
| 07-29 17:03 | **row 13 added** (machine capacity; "owns what nothing owned") | `1325d0f98`, L1743-1750 | MA |
| 07-29 17:43 | "the inherited bullet decayed within the hour" | `b0cb6d006` | EC |
| 07-29 22:50 | "retract the pane-uuid rule… I was reading a stale worktree copy" | `3455c5527`, L990 | RE |
| 07-31 13:05 | "two of its four claims were false when filed" | `bbd14a845` | RE |
| 08-07 | **row 14 added** (deskless failure detection) | map `bb5e9f7a1` | MA |
| 08-07 17:50 | **dormant 8 days**: "its continuation depended on a live session's in-memory state" | `e3fde7ffe`, L404-418 | RLR |
| 08-08 | row 9: "the build never ran, the subsystem shipped anyway, and the cap moved underneath both" | map `64696b6b1` | EC |
| 08-08 22:23 | "the re-dispatch loop cannot terminate" (third worker into a tree 822 commits behind) | map `69e6519a4` | VOB |
| 08-09 | row 3 re-fired: its "SPECIFIED, NOT BUILT" remainders were the defect the operator reported 11 days after DONE | map `f57d2fa51`, L632-640 | VOB |
| 08-10 20:55 | "the store-based cure was only as wide as its generator's input, and row 6 sat outside it" | `5a9acc8f2`, L318-330 | MA |
| 08-10 21:06 | "the fix I just landed does not reach the worker it was written for" | `5ddd55b32` | VOB |

### 4.4 INSOMNIAC_DENVER_PROVISIONING (reso)

| when | event | receipt | class |
|---|---|---|---|
| 08-21 00:38 | the invite blocker is AUTHORITY, not the credential; "two independent reasons had been merged" | `3fe69fb04` | RE |
| 08-21 01:35 | "the remote path never worked and reported success anyway" | `cf214118f` | VOB |
| 08-21 01:39 | wave 2 collected, "two corrections" | `af59c16b7` | RE |
| 08-21 01:41 | "wave 3 scoped from what Wave 2 measured, not what it guessed" | `a2bff84c1` | VOB |
| 08-21 02:05 | "a new region's parent schema was never migrated" | `4d99f9320` | VOB |
| 08-21 02:21 | "my Keychain reason was wrong" | `6b507eb02` | RE |
| 08-21 02:25 | "the health check passed on a tenant that does not exist" | `1a9fe3cca` | VOB |
| 08-21 02:45 | "the lane outage was a cache mount not the repo" | `5991e9f51` | RE |
| 08-21 05:20 | "the Ashburn alarm I raised was a false one" | `47831021a` | RE |
| 08-21 | `Scope (grown)`: `audit-venue-provisioning.ts`, "a SIXTH silent green" | L710 | VOB |
| 08-21 09:16 | **header: LIVE, "no free leg remains"** | `e7b5955a7`, L9-12 | — |
| 08-26 02:31 | Wave 4: nine Stage 0 repo repairs | `b354f24ce`, L319 | NOR |
| 08-26 03:09 | "decision 2 is two questions, and only one is the operator's" | `d1585b9a8` | RE |
| 08-26 03:37 | "four findings the brief did not ask for" | `5a7673d18` | MA |
| 08-26 15:53 | road to Heist parity, 10-agent research | `88bf799d2`, L728 | NOR |
| 08-26 16:04 | "the six false claims, corrected in place" (step 1: "six claims, not four") | `b6ff5c768`, L754 | CR |
| 08-26 22:11 | withdrew both "100% is unreachable" claims after operator pushback: *"If we reached production acceptance for Heist and Studio60 with LESS resources… we can reach 100% here."* | `eee1d2af6`, L947-953 | RE |
| 08-26 23:48 | "every gate built for Denver measures the artifact against ITSELF, and not one compares it to the SOURCE" | `3d29a025d`, L984-999 | MA |
| 08-27 18:59 | "the work list was 40% wrong in both directions" | `03342d8b7`, L1057-1077 | RLR |
| 09-13 | mission board: "the ROOM IS EMPTY… floor_plan_element=0, bottle_menu_item=0" | `cc-mission show insomniacdenver.church.live-url` | — |

### 4.5 DOCS_CONSOLIDATION_100P (reso): the closed and stayed-closed case

Key events: 45 of 58 acceptance commands unsound when run against trunk *before* build (`550409f79`, L2059-2073, CR). The audit listed its own blind spots, 9 gaps (L1941-1990, CR). "a diff-based check cannot survive its own landing" (`c9d9514db`, L897, VOB). D-1 "W4 would freeze production silently, and the plan named the wrong coupling" (`3e40c079f`, MA). "W5 died holding 120 uncommitted files" (`f7c835c0d`, RLR). "the status header said W5 was armed for an hour after W5 was dead" (`be0c06ada`, RLR). There were 7 RE events, e.g. "the 'confirmed exact' 80-line debt figure was the wrong unit" (`b6109d7bb`) and "the self-test flag never existed" (`d9f525092`). Programme complete at `249cbacd3`, 08-21 05:42; no reopen.

### 4.6 KITTY_DRAG_ACTION and USAGE_TELEMETRY_100P (short)

- **KITTY:**
  - The research critic reopened 31 citations and found 7 gaps before planning (L8-13, CR).
  - A reboot and then a second kernel panic made the safety block's pid wrong twice in one hour; the reused pid pointed at `calaccessd` (`e3937ffc0`, L168-180, EC ×4 across `c1c1008a8`/`0b8067c06`/`b73e9a42f`/`e3937ffc0`).
  - "the plan ordered the command that panicked the box, in its own goal condition" (`854eca452`, VOB).
  - The chord was armed live while the tracked record said it was not (L1425-1428, RLR).
- **USAGE_TELEMETRY:**
  - The skeptic inverted M1 and caught the lead contradicting itself (`cb838381c`, L272, CR). The critic closed wave 1 "on a doubt" (`efa6d2e96`, CR). The meter was resolved by experiment (`40d574617`, L352, VOB).
  - Wave 2 existed because wave 1 answered only "am I on pace to WALL", not "will I STRAND" (`aaba84e58` body, MA). Verification killed 3 of 4 synthesis claims (L591-593, CR).
  - Four build-time defects followed (`44671118e`, `4b2367b69`, `29009970a`, `0eb64b73c`, VOB).

### 4.7 BACKLOG_DRAIN_24_7 (operational drain; aggregate)

- **Class counts:** 32 events. The 6 `Scope (grown)` lines are at L16848, 18716, 20894, 22105, 22228 and 30470. The 30 `CORRECTED` hits reduce to 26 events: L874 duplicates L832, L14587/14589 duplicate L14573, and L23263 is a mutant label, not an event. Contexts are in `/tmp/rescomp/internal/bd_corrected.txt`.
- **RE dominates (15).** Examples: "THE DOCUMENTED REPAIR IS REFUTED, AND IT HAD THE SAME BLINDNESS AS THE DEFECT IT CORRECTED" (L832). "a row that has ALREADY CORRECTED ITSELF installs a second cause nobody audits — and this one had been false for fourteen days" (L14573).
- **RLR (5).** "CORRECTED FROM THE INHERITED TABLE… TAKE YOUR OWN COUNTS" (L2438).
- **Scale:**
  - 336 recycles (L90). "Method" lessons numbered up to 272 (L609), with 166 distinct `METHOD N —` headings.
  - The frozen scope promised "the backlog trends DOWN" (L9-14). Board readings in the log: 487 open+blocked on 08-24 (L14576), 511 on 08-25 (L11958), "net stayed 259" (L18718).
  - The 09-22 recycle closed 35 rows, 34 of them blocked rows with dead premises (L90-97).

## 5. Cross-cutting patterns (each with its receipt)

1. **Acceptance on n=1 or on self-referential gates certifies "complete" early.**
   - LR100P: "rested on n=1 (one throwaway, one-turn-old, self-spawned pane on a quiet box)" (L321).
   - Denver: "every gate built for Denver measures the artifact against ITSELF" (L984).
   - DOCS: 45 of 58 criteria "could not have proved anything" (L2059).
   - MACHINE_CAP: "a DONE cell over a red gate" (`224d6b166`).
2. **A per-wave DoD answers the wave, not the question.** "each time true of the wave then running and false of the question asked" (reso `FLOOR_PLAN.md:63-66`). Map row 3's unbuilt remainders "can BE the defect the row was fired to fix" (MAP L632-634). HOOK_SURFACE was complete "on the agent side" while three operator steps remained (L7-15).
3. **The problem statement was usually wrong.** 10 of 12 original map constraint cells were amended (§5.3 below). MACHINE_CAP §8.5.7 "falsifies the framing the whole row was commissioned under" (L480-483). FLOOR_PLAN: "11 of 14 agents in one wave audited consumer-side behaviour; every failure… lived in the half nobody briefed" (`FLOOR_PLAN.md:1076-1079`).
4. **Research claims are perishable, and inheriting them manufactures work.**
   - "a measurement is perishable. Mine was six hours old and I had already propagated it into two fire payloads" (DISPATCH L732-735).
   - "the correction itself went stale inside one hour" (KITTY L170).
   - "Magic numbers were stale before the ink dried… Four values for one quantity, inside one document, within a day" (DOCS L2080-2084).
   - "it rotted in 40 minutes" (`8c336e581`).
5. **Continuation lost with the session means research gets redone.** The campaign sat dormant 8 days because "its continuation depended on a live session's in-memory state" (DISPATCH L409-416). LR100P's "Filed" items were never filed (L298-300). Denver's work list was "written from a previous session's notes rather than from the tree… 40% wrong in both directions" (L1073-1077).
6. **Seams between sibling plans drop axes.** LIMIT_DETECT §7 DROPPED the request writer while LR100P narrowed it out, so "The recovery lane's only producer today is a human typing" (LR100P L772-777).
7. **Critics work, but late critics become goalpost moves.** Where the critic ran before build (DOCS; FLEET_V2 found 7 fatal and 30 major defects in revision 1; USAGE §5.1 refuted 3 of 4 claims), the plan converged. Where it ran after landing (LR100P `fe9a22d0f`, "W2… does not meet its own DoD"), it reopened the plan.

### 5.3 Map constraint-cell tally (`GROUND_UP_REBUILD_MAP.md` L17-32)

| row | original cell verdict after research |
|---|---|
| 1 | unannotated (the exemplar row) |
| 2 | CONFIRMED-BUT-RENAMED; metric FALSIFIED |
| 3 | CONFIRMED-BUT-RENAMED |
| 4 | unannotated |
| 5 | falsified ("real cause was no fleet concurrency ceiling") |
| 6 | renamed 2026-09-09 ("the original clause… is not the binding one") |
| 7 | CONFIRMED ("the campaign's FIRST surviving cell") but INSUFFICIENT AS STATED |
| 8 | CONFIRMED-BUT-UNMEASURABLE; METRIC FALSIFIED ON BOTH HALVES |
| 9 | RENAMED |
| 10 | CONFIRMED-BUT-INSUFFICIENT |
| 11 | FALSIFIED AS A CONSTRAINT |
| 12 | CONFIRMED but INSUFFICIENT (1 of 3 silent states) |
| 13 (added) | framing falsified (§8.5.7) |
| 14 (added) | — |

## 6. What this implies for an upfront-research method (evidence-tied, not a design)

- **The research is not too short. It mostly answers questions that turn out to be the wrong ones, and it certifies with instruments too weak for the claim.** 69% of moves are RE+VOB+EC; 5.6% are new operator asks (non-drain set).
- **Three levers correlate with plans that held:**
  1. Execute every acceptance command against current trunk *before* build and reject any command that already passes or cannot fail (DOCS §9).
  2. Run a measurement wave that produces fixtures and real-load numbers before design is frozen, with acceptance at production n rather than n=1 (FLEET_V2 W0; LR100P's failure on n=1).
  3. Put skeptics on the *design* rather than on landed waves (FLEET_V2, USAGE §5.1).
- **The frozen DoD must be the operator's deliverable, not the wave's.** Denver "LIVE" vs. an empty room is the exemplar. Growth must be recorded where it happens: today 20 `Scope (grown)` lines stand against roughly 600 refutation/supersession markers, so no one can count the drift.

## 7. Caveats

- Single-rater classification. Commit-subject regexes are lower bounds (USAGE scored 0).
- `git log` without `--follow`, so plans renamed from an earlier file would under-count. No renames were observed in the selected plans' logs.
- reso history may be squash-affected; commit counts are those visible on reso `HEAD`.
- BACKLOG_DRAIN_24_7 is an operational drain log, not a greenfield plan. Totals are given with and without it.
- The "30 limit-recover goal conditions" figure is deduplicated on the first 120 characters of the condition. Two conditions for the same work phrased differently would count twice. One unrelated match (`5141199e`, a design-reel goal) was removed.
