**Verdict: moving, then stalled.** 624 of the program's 627 verified findings came in by 2026-10-12, at a modest ~220 quota points (19% of the fleet's quota since 09-27). Since 10-13 it has mostly bled calendar time: 3 new finds in 3.4 days, nothing shipped upstream, and a build that cannot start before mid-November because the certificate is waiting on the research kit's router data, not on anything about TrueMemory.

# TrueMemory 2.0 research program: cost against outcome (measured 2026-10-16)

The operator asked (2026-10-16): *"I feel we have been close to a month of researching; can we measure our time cost and our token cost relative to the outcome and improvement? Or are we bleeding out time/tokens for no true movement or improvement?"*

**How to read the numbers.** Every number carries the command that reproduces it, run from the repo root. Most come from one derived file, so paste this helper once:

```
hl() { python3 -I docs/research/tm2-cost-vs-outcome-2026-10-16/scripts/z_headlines.py | grep "^$1 "; }
```

`hl pp_M1_core` then prints `pp_M1_core = 220.2`. In tables, the **key** column is the `hl` argument. `data/` means `docs/research/tm2-cost-vs-outcome-2026-10-16/data/`: run the `jq …` lines from `docs/research/tm2-cost-vs-outcome-2026-10-16/`, and everything else from the repo root. §7 gives the full pipeline.

**Terms.** *pp* means percentage points of one account's weekly plan quota: the fleet has 4 accounts, so 400 pp per week. *Core* means the program's own sessions, plus the research-kit implementation, plus the research-method design the kit implements. *Material hole* means a confirmed defect in the plan that 2 of 3 raters rated MATERIAL. It excludes planted test defects ("seeds"), artifacts and re-finds. *Week 1* (Wk1) is 09-28 to 10-04, Wk2 is 10-05 to 10-11, and Wk3 is 10-12 to 10-16. Wk3 is partial (4.4 days), so compare weeks per day.

| Headline | Value | key |
|---|---|---|
| Calendar time since the TrueMemory study / first TM2 plan commit / program intake | 18.5 / 17.2 / 14.5 days | `span_days_since_truememory_study`, `…first_tm2_plan_commit`, `…program_intake` |
| Hours with program work going on, of the 423 since first activity | 336 (79%) | `hours_working`, `pct_hours_working` |
| Quota spent: core, with two independent methods (fitted price / share of the measured meter) | 220.2 / 217.5 pp | `pp_M1_core`, `pp_M2_core` |
| Share of the fleet's measured quota since 09-27 | 18.6% of 1,171 pp | `pp_core_share_of_fleet_moved_pct`, `pp_fleet_moved` |
| Verified findings: plan critique rounds 1-23, plus material holes | 437 + 190 = 627 | `plan_critique_rounds_1_23_verified_findings`, `material_real_new_total` |
| Findings per day: Wk1 / Wk2 / Wk3 | 76.7 / 5.1 / 12.3 | `findings_per_day_Wk1` … `_Wk3` |
| New material in Stage 8 (10-13 onward, 3.4 days) | 3 | `days_per_decision_naming_hole_S8` (3.41 days / 3) |
| Upstream TrueMemory pull requests opened / merged by us | 0 / 0 | `upstream_prs_opened_by_us`, `upstream_prs_merged` |
| Research-kit commits since 09-28 that fix the kit's own defects | 67 of 134 (50%) | `kit_commits_D`, `kit_commits` |
| Calendar time from intake to the earliest build start (2026-11-15) | 43.9 days, against the contract's 28-day ceiling | `days_intake_to_2026_11_15` |

## Situation, complication, question, answer

- **Situation.** The TrueMemory study began 2026-09-27, and the first TM2 plan commit landed 09-29. The plan went through 29 critique rounds, and the formal program started at intake on 10-02. It then ran eight stages: frame, censuses, contact, decisions, executable acceptance, trace and freeze, 6 certification rounds (Stage 7, 10-10 to 10-13), and gate-row closure (Stage 8, 10-13 to now).
- **Complication.** It feels like a month (it is 18.5 days), and nothing is in users' hands. The certifying gate passes or files 18 of 19 rows, but row 15 (the kit's re-ask router) fails with "router not built". The build-only premises were re-dated to December–March. The method's own estimator now expects more material holes than it did after round 1.
- **Question.** Is the spend buying real movement, or bleeding time and tokens?
- **Answer.** Both, in sequence. Through 10-12 the spend bought fast, cheap movement: 624 findings, 22 decisions ruled or carried, and 87 of 111 premises proven. After Wk1, the quota cost was about 30 pp a week. Since 10-13 the marginal day buys certification bookkeeping, and the calendar is now gated by kit infrastructure. **Tokens are not the constraint; calendar time and kit churn are.**

## 1. Time

**Calendar span.** 18.5 days since the study (`hl span_days_since_truememory_study`), 17.2 since the first TM2 plan commit (`hl span_days_since_first_tm2_plan_commit`), 14.5 since intake (`hl span_days_since_program_intake`). So it is about 2.6 weeks, not a month. Projected to the earliest build start (mid-November), it becomes about 7 weeks from the study (`hl days_intake_to_2026_11_15` = 43.9 days from intake).

**Stages.** The kit counts an agent-day as a stage's wall-clock days (`scripts/research-kit/lib/cli_core.py` `budget_report`). Stage budgets are the standard profile's (`kit._STD_STAGE_DAYS`), and the cap is 1.5 × budget. `budget.json` records only stages 1–5. Stages 6–8 are dated from their tm2-plan commits (a3a78e97d, aa4d4e6c2, b503de538).

| Stage | Wall days (key `wall_days_<stage>`) | Kit budget / cap (days) | Core quota pp (key `pp_M1_core_<stage>`) | Material holes recorded | What it produced |
|---|---|---|---|---|---|
| Pre-program: study, plan, 29 critique rounds | 5.13 | — | 103.8 (program 74.2) | 437 critique findings fixed | the plan |
| S1 frame | 0.06 | 2.0 / 3.0 | 2.2 | 40 (frame critique) | signed frame |
| S2 censuses | 0.06 | 1.5 / 2.25 | 1.8 | 0 | 12 censuses |
| S3 contact | 0.89 | 1.5 / 2.25 | 12.2 | 0 | upstream slice, contacts K1–K15 |
| S4 decisions and premises | 4.61 (over its 4.5 cap; overrun packet e1c36dfb1570) | 3.0 / 4.5 | 43.4 (program 13.2; kit and method 30.2) | 60 (plan critique rounds 24–29, recorded here) | 16 decisions ruled (tm2-plan 110244ad5) |
| S5 executable acceptance | 0.15 | 2.5 / 3.75 | 3.5 | 0 | acceptance rows |
| S6 trace and freeze | 0.78 | 1.0 / 1.5 | 1.9 | 4 (fresh read) | freeze |
| S7 certification, 6 rounds | 2.52 | not in budget.json | 31.7 | 83 | the certification findings |
| S8 gate rows | 3.41 so far | not in budget.json | 11.2 | 3 (rehearsal) | gate 14 PASS, 4 FILED, 1 FAIL |

Stages 1–6 used 6.55 of their 11.5 budgeted agent-days, with S6 counted from its commits (`hl kit_agent_days_stages_1_6`, `hl kit_budget_days_stages_1_6`). On the kit's own measure the program is under budget. Only Stage 4 crossed its cap. The kit has no budget record for stages 7–8, which have taken 5.93 days (`hl wall_days_stages_7_8`). Gaps between stages took 1.98 days (`jq '[.stages[]|select(.stage|startswith("gap"))|.wall_days]|add' data/t_time.json`).

**Working against waiting** (`python3 -I docs/research/tm2-cost-vs-outcome-2026-10-16/scripts/t_time.py`). An hour counts as *working* when any program, kit or method session wrote a billed response in it. That measures presence, not productivity.

| Hours since first activity (09-28 23:00 UTC), 423 in all | Hours | Share | key |
|---|---|---|---|
| Working | 336 | 79.4% | `hours_working` |
| Waiting on the operator (a class-C decision packet or a recorded sign-off checkpoint open, nothing running) | 72 | 17.0% | `hours_waiting_operator` |
| Waiting on a vendor usage wall (OpenAI, 10-10 and 10-11) | 1 | 0.2% | `hours_waiting_vendor_wall` |
| Idle at night (23:00–08:00 local) / idle daytime, unexplained | 8 / 6 | 3.3% | `hours_idle_night`, `hours_idle_daytime_unexplained` |

- Concurrency: 1,296 session-hours, a mean of 3.9 sessions per working hour (`hl session_hours`, `hl mean_concurrent_sessions_per_working_hour`).
- The program almost never sat idle. **Its calendar is long because the work kept going while the stop line kept moving, not because sessions were waiting.**
- Operator decisions: 56 packets name the program, 39 of them class C (`hl operator_packets`, `hl operator_packets_class_C`). A class-C packet stayed open a median of 31.2 hours (`hl operator_class_C_median_open_hours`). The Stage 8 batch of 11 class-C packets, opened 10-13, was answered 10-16, after 66.7–71.1 hours (`jq '.operator_packets.class_C_open_hours' data/t_time.json`). Work mostly continued beside open packets: 237 of the 336 working hours (71%) had at least one open (`jq .working_hours_with_operator_open data/t_time.json`).
- Load waits: the measured re-proofs in Stage 8 gate every run on 1-minute load ≤ 40 on a machine running at about 400. Those waits are deliberately untimed, so they hide inside "working". It took 5 fix commits to make them survive load (`hl rework_s8_load_fix_commits`).
- Waiting on data to accumulate: the build start waits for a fresh sealed held-out set of 400 unused prompts for the router's gate row. The operator chose that option on 10-08 (packet 915d7fb98b7f, option "fresh-v5-subtle", conviction 72: "ready around Nov 1-22, likely before the gate anyway"). That is about 30 more calendar days of waiting, and none of it is research.
- Dispatched sessions: 58 fires (21 of them kit fires) took 155 session-hours (`hl fires`, `hl fires_kit`, `hl fires_hours`). By week: 3 / 16 / 39 (`hl fires_Wk1` … `_Wk3`). Two were abandoned: fire-tm2-s6-w1 and fire-kit-row4-filed (`jq .fires.abandoned data/t_time.json`).

## 2. Tokens and quota

**Method** (`docs/research/tm2-cost-vs-outcome-2026-10-16/scripts/k_census.py`, then `k_attrib.py`). The census reads all four accounts' transcripts (`~/.claude-next/projects` is a symlink to `~/.claude/projects` and is read once). It uses the same billing semantics as `bin/cc-quota-price`: dedupe on message.id, take the first record's timestamp and input, take the maximum output. It found 402,873 billed responses since 2026-09-27. `bin/cc-quota-price --census --since 2026-09-27`, run independently, found 402,629. The 0.06% gap is responses written between the two scans (`bash docs/research/tm2-cost-vs-outcome-2026-10-16/scripts/y_crosscheck.sh | grep fleet_responses`).

Quota is computed two ways:
- **M1** prices tokens with the fitted rate from `bin/cc-quota-price --json --since 21d`: R² 0.85 over 199 six-hour buckets. The rates are 1.95 pp per million output tokens, 0.25 pp per million cache-creation tokens, and cache reads are excluded as about zero cost (`jq .fit,.price data/k_ccqp_fit21d.json`).
- **M2** takes the weekly_pct movement measured on each account's meter (`~/.claude/logs/account-utilization.jsonl`) and splits it by the program's share of priced tokens in each six-hour bucket.

They agree within 1.3%.

| Bucket (rule: §6) | Responses | Output tokens | Cache-creation tokens | Cache-read tokens | pp, M1 | pp, M2 |
|---|---|---|---|---|---|---|
| Program: lead, records, plan, contact, reviewers | 69,718 | 17.9M | 221.2M | 10.6B | 151.0 | 152.3 |
| Kit implementation | 11,770 | 6.5M | 46.4M | 1.9B | 34.1 | 31.2 |
| Method design (the spec the kit implements) | 10,575 | 2.7M | 78.3M | 1.2B | 35.1 | 34.0 |
| **Core total** | **92,063** | **27.1M** | **345.9M** | **13.7B** | **220.2** | **217.5** |
| Upper band: mixed sessions (adoption lead; AgentMemory study) | 9,095 | 1.7M | 99.8M | 1.9B | 35.9 | 45.5 |
| Not counted: other fleet work that names the program path | 24,141 | 7.1M | 94.4M | 2.7B | 57.7 | 48.1 |
| Fleet, all sessions | 402,873 | 131.7M | 1,792.1M | 64.3B | — | 1,171 moved |

Commands: `python3 -I docs/research/tm2-cost-vs-outcome-2026-10-16/scripts/k_attrib.py` prints this table. Key `core_*` and `fleet_*` give the core and fleet columns, and `pp_M1_<bucket>` / `pp_M2_<bucket>` the quota columns.

The core is 20.6% of the fleet's output tokens, 19.3% of its cache-creation tokens, and 18.6% of its measured quota (`hl core_share_output_pct`, `hl core_share_cache_creation_pct`, `hl pp_core_share_of_fleet_moved_pct`). With the upper band added, the core is at most 311 pp (`hl pp_core_upper_with_mixed_and_suspect`). In capacity terms, 220 pp is 2.2 account-weeks out of the roughly 11 the fleet had over the span.

| Week | Core pp, M1 / M2 | Fleet pp moved | Core share of fleet | key |
|---|---|---|---|---|
| Wk1 (09-28 – 10-04) | 160.0 / 147.8 | 573 | 26–28% | `pp_M1_core_Wk1`, `pp_M2_core_Wk1`, `pp_fleet_moved_Wk1` |
| Wk2 (10-05 – 10-11) | 29.2 / 32.8 | 364 | 8–9% | `…_Wk2` |
| Wk3 (10-12 – 10-16, 4.4 days) | 31.0 / 36.9 | 190 | 16–19% | `…_Wk3` |

**Where the program's 151 pp went, by activity** (key `pp_M1_program_sub_<activity>`):
- Plan critique rounds in the replan worktree: 76.5
- Lead sessions: 33.9
- Records and waves in tm2-plan: 15.5
- Certification reviewers on the Anthropic lane: 14.4
- Upstream contact (slice, clones, upstream plan): 9.2
- Other tm2 waves: 1.4

So half of the program's quota went to the plan critique rounds, which were also its cheapest findings per pp. Their 497 findings (437 in rounds 1–23 plus 60 in rounds 24–29) cost 76.5 pp, about 6.5 per pp. Stage 7's 83 cost 31.7 pp, about 2.6 per pp.

By account (M2): next3 131.2, next4 38.2, next 32.8, next2 15.4 pp (`jq '[.pp[]|select(.key[0]=="acct" and (.key[1]=="program" or .key[1]=="kit" or .key[1]=="kit-method"))]' data/k_attrib.json`).

By model: Opus 5.5 carried nearly all of it. Fable 5.1 wrote 0.97M output tokens for the program, which is 5.4% of the program's output (`hl output_fable_program`).

## 3. Outcome: what exists now that did not before

### 3a. In the program records (`python3 -I docs/research/tm2-cost-vs-outcome-2026-10-16/scripts/o_records.py`)

Records are append-only event logs, folded by id with the kit's own `fold`, `premise_level` and `not_new_material`.

| Item | Now | key |
|---|---|---|
| Plan critique findings verified and fixed (rounds 1–23, before intake) | 437 | `plan_critique_rounds_1_23_verified_findings` |
| Holes recorded (distinct ids) | 429 | `holes_distinct` |
| Real new material holes: frame critique / plan critique rounds 24–29 / certification rounds 1–6 / fresh read / rehearsal | 40 / 60 / 83 / 4 / 3 = 190 | `material_real_new_frame_critique`, `…replan_rounds_24_29`, `…certification_rounds_1_6`, `material_real_new_total` |
| …of which name a decision (a proxy for decision-changing) | 102 | `material_naming_a_decision_total` |
| Planted test defects caught (seeds; not findings) | 66 | `seed_catches_total` |
| Decisions: 22 in all; 17 ruled and 5 carried as sets | 22 | `decisions`, `decisions_ruled`, `decisions_carried` |
| …ruled by the operator / by packet default / by the agent | 13 / 6 / 3 | `decisions_ruled_by_operator`, `…packet-default`, `…agent` |
| Premises at their required evidence level / below it / refuted | 87 / 24 / 17 of 111 | `premises_at_required_level_now`, `premises_below_required_now`, `premises_refuted` |
| Premise evidence levels now (E1 recall … E6 operator view) | E1 8, E2 5, E3 41, E4 7, E5 42, E6 8 | `hl premises_level_E3` etc. |
| Probes run (701 of them live reads, the kind the daily freshness re-checks renew) | 1,011 | `probes`, `probes_live_read` |
| Known rows (open) / apply-at-build rows (open) / residual rows | 30 (25) / 59 (50) / 48 | `known_rows`, `apply_at_build_rows`, `residual_rows` |
| Plan size: first commit to now (61 commits; 6 freezes from 3,554 to 3,921 lines) | 2,975 to 3,921 lines | `plan_lines_first_commit`, `plan_lines_now`, `jq .freezes data/o_records.json` |
| Certifying gate (10-16 07:55 local): PASS / FILED / FAIL of 19 rows | 14 / 4 / 1 (row 15 Router) | `gate_pass_now`, `gate_filed_now`, `gate_failing_now` |

### 3b. Research-kit capability (`python3 -I docs/research/tm2-cost-vs-outcome-2026-10-16/scripts/p_kit.py`)

There were 134 commits on main since 09-28 touching `scripts/research-kit` (8.9% of all trunk commits). Each one is classified by hand, from its subject and diff; the class and reason for every commit are in `data/p_kit_commits.csv`. TM2 is the only program ever registered with the kit (`jq . ~/.claude/autonomy/research/programs.json`), so this program paid for every class.

| Class | Commits | Lines added | key |
|---|---|---|---|
| G-plan: generic capability built from the method spec | 50 | 26,130 | `kit_commits_G-plan` |
| G-trig: generic capability, built because TM2 hit the situation | 12 | 4,560 | `kit_commits_G-trig` |
| T: TM2-only | 3 | 1,016 | `kit_commits_T` |
| D: fixing the kit's own defects | 67 (50%) | 7,770 (19.5%) | `kit_commits_D`, `kit_defect_share_commits_pct` |
| O: repo-wide commits that only touched a kit file | 2 | 379 | `kit_commits_O` |

- The defect fixes did not taper off: 28 in Wk1, 22 in Wk2, and 17 in Wk3's 4.4 days (`jq .by_week data/p_kit.json`).
- 39 commits (13,075 lines) went to the re-ask router and its held-out sets. That is the one gate row still failing (`hl rework_kit_router_commits`).
- 11 commits (4,847 lines) built method v1.2 and the Stage 9 built-artifact certificate in the middle of the program. This program cannot use them: its frame was signed under method 1.1, and gate rows 18–19 print "not applicable" (`hl rework_kit_v12_stage9_commits`).

### 3c. The product: nothing has shipped

- **Upstream TrueMemory pull requests opened by us: 0. Merged: 0. Issues: 0** (`hl upstream_prs_opened_by_us`, cross-checked over the REST API in `y_crosscheck.sh`).
- The 10-02 contact slice left 40 fix commits in the local upstream clone, never pushed. Its remote is named `DISABLED-never-push-upstream` by design (`git -C ~/Development/.worktrees/tm-upstream-clone log --branches --not --remotes --oneline | wc -l`).
- Build wave W1 cannot start before mid-November (tm2-plan commit 0c3a5504e). Its build-only premise filings were re-dated to 2026-12-31, 2027-01-31 and 2027-03-31.

## 4. Movement: is the marginal week still buying anything?

**Yield by week** (`python3 -I docs/research/tm2-cost-vs-outcome-2026-10-16/scripts/m_movement.py`; key `<column>_<week>`). Findings = plan critique findings plus real new material holes.

| | Wk1 | Wk2 | Wk3 (4.4 days) |
|---|---|---|---|
| Findings (`plan_critique_verified_findings` + `real_new_material_holes`) | 437 + 100 | 0 + 36 | 0 + 54 |
| …per day (`findings_per_day`) | 76.7 | 5.1 | 12.3 |
| …per 10 pp of core quota (`findings_per_10pp`) | 33.6 | 12.3 | 17.4 |
| …per 100 session-hours (`findings_per_100_session_hours`) | 153.0 | 9.5 | 9.5 |
| Material holes naming a decision (`of_which_name_a_decision`) | 46 | 21 | 35 |
| Decisions reaching their first ruling or carry (`decisions_first_ruled`) | 4 | 18 | 0 (re-rulings and affirmations only) |
| Premises first reaching their required level (`premises_reaching_required_level`) | 73 | 20 | 9 |
| Session-hours (`session_hours`) | 351 | 380 | 567 |

Wk3's 54 finds are not spread over the week. 51 came on Monday 10-12, from certification rounds 2–6, and 3 came on 10-16 from the rehearsal (`jq .holes.real_new_material_by_day data/o_records.json`). **Stage 8 (10-13 to now) found 3 material holes in 3.41 days and ruled no new decision.** Wk3 as a whole raised 9 premises to their required level. Its 51 tm2-plan commits split into:
- 12 freshness re-checks
- 9 gate and trace bookkeeping
- 6 rehearsal
- 5 re-dating, re-ruling and affirming
- 4 findings
- 1 round mechanics
- 14 other: mostly measuring premises at level E4, plus 5 load-handling fixes

(`jq '.s8_commits, .s8_commit_categories' data/m_movement.json`)

**Certification rounds** (`jq '.rounds' data/m_movement.json`; key `round_<n>_new_material`, `round_<n>_kappa`):

| Round | 1 | 2 | 3 | 4 | 5 | 6 (cap) |
|---|---|---|---|---|---|---|
| New material holes | 32 | 13 | 11 | 10 | 9 | 8 |
| Rater agreement on materiality (kappa; the method wants ≥ 0.7) | 0.065 | 0.135 | 0.049 | 0.097 | 0.235 | 0.016 |
| Re-closes | 2 | 1 | 2 | 1 | 2 | 1 |

The yield curve flattened at 8–11 a round and never reached a quiet round. Review stopped because it hit the 6-round cap, not because the curve ran dry (`hl forecast_now_stop`, `hl forecast_now_quiet_streak`). Rounds 2–6 each took 1–3 hours of a dispatched session (`jq '.fires.list[]|select(.slug|test("w2[2-6]$"))' data/t_time.json`). Raters agreed on materiality at roughly chance level every round, so the material counts are noisy in both directions.

**Against the method's own forecast** (`python3 -I scripts/research-kit/estimate.py forecast --program truememory-2-0`, read-only, saved to `data/m_estimate_forecast.txt`):

| | After round 1 (contract page) | After round 6 (now) | key |
|---|---|---|---|
| Material holes found | 32 | 83 | `forecast_round1_found`, `forecast_now_found` |
| Estimated material holes in all (n_hat) | 98 (≤ 145 at 95%) | 205 | `forecast_round1_n_hat`, `forecast_now_n_hat` |
| Desk-detectable material changes expected after signoff | 68.6 (≤ 113) | 127.5 (≤ 199) | `forecast_now_desk_mean`, `forecast_now_desk_n95` |
| Changes no reviewer can see | 13.5 (≤ 39) | 28.2 (≤ 76) | `forecast_now_invisible_mean` |
| Chance of at least one material change after signoff | 1 | 1.0 | `forecast_now_p_any` |

More review raised the estimate of what remains. The reviewers caught 24 of the 60 planted seeds (59 effective) (`jq '.rounds[7].seeds_planted.original' data/m_movement.json`). By the method's own numbers, "no take-backs" is not reachable on this plan.

**Against the reference class.**
- The contract page gives a typical total of about 14 days and a ceiling of about 28 days, "every loop at its cap".
- Intake to now is 14.45 days: at the typical total, with no certificate issued.
- Intake to the earliest build start is 43.9 days, about 1.6 times the ceiling. The extra time is calendar spent waiting for router data, not research.

**Against the operator's escape cost** (3 research days per decision-changing hole found after build; key `days_per_decision_naming_hole_<stage>`):

| Stage | Wall days | Material holes naming a decision | Days per hole | Against the 3-day escape price |
|---|---|---|---|---|
| S7 certification | 2.52 | 53 | 0.05 | about 60 times cheaper than an escape: review paid off by a wide margin |
| S4 (plan critique rounds 24–29, recorded in S4) | 4.61 | 30 | 0.15 | paid off |
| S8 gate rows | 3.41 | 3 (all from the rehearsal) | 1.14 | still under the price, but 20 times worse than S7, and not produced by research rounds |

The operator's own price says the certification rounds were the best-value activity in the program. The cap stopped them while each 1–3-hour round still found 8–13 material holes. The days after the cap went to gate rows, and now the calendar waits on router data.

## 5. Verdict

**Bleeding or moving?** Moving through 10-12, and cheaply. Since 10-13, mostly bleeding calendar time, not tokens.
- At the token level the program is affordable: about 30 pp a week after Wk1 is about 8% of fleet capacity, and the whole program is 18.6% of the fleet's measured quota.
- At the calendar level it is not. 44% of the days since intake went to stages that found almost nothing: 6.38 of 14.45 days (`hl other_stages_days_since_intake`). The next roughly 30 days are pure waiting.
- Nothing has reached TrueMemory users.

**Durable value against rework, measured three ways:**
- **Program quota.** 130.2 of 151.0 pp (86%) went to stages that found or decided things: pre-program, S1, S3, S4 and S7. 20.8 pp (14%) went to the rest (`hl pp_M1_program_finding_stages`, `hl pp_M1_program_other_stages`).
- **Kit.** 50% of commits and 19.5% of lines fixed the kit's own defects, which puts 6.6–17.1 pp of the kit's 34.1 pp into rework (`hl kit_defect_share_commits_pct`, `hl kit_defect_share_lines_pct`).
- **Core total.** About 27–38 pp of 220 (12–17%) was rework or ceremony, and about 83–88% went to finding, deciding or reusable capability. In calendar time the split inverts. If the build starts 11-15, finding stages are 8.08 of 43.9 days from intake, or 18% (`hl finding_stages_days_since_intake`).

**Rework and goal-post moving, named** (`python3 -I docs/research/tm2-cost-vs-outcome-2026-10-16/scripts/r_rework.py`):

| # | Instance | Class | Evidence |
|---|---|---|---|
| 1 | The definition of "complete" replaced the operator's words of 09-14 and 09-27 at intake | goal-post | CONTRACT.md § Definition of complete |
| 2 | Frame signed 10-01 (45ff686fe), revised from the operator's second sitting 10-02, re-signed at the Stage 5 checkpoint 10-09 (99c41d2cb), after new frame keys 10-10 (566c07705), and for the "lite" profile 10-12 (390b73707); contract page rendered 4 times | goal-post | `jq .frame_sign_or_resign_commits data/r_rework.json`; `hl rework_contract_page_renders` |
| 3 | Profile switched from standard to lite after round 1: reviewers per round 16 → 8, round cap 10 → 6 | goal-post | CONTRACT.md § Profile |
| 4 | Six build-only premises filed not-yet-true at 07:43 local on 10-16 (due 10-31), re-dated at 08:09 (to Dec–Mar), and a kit verb built for the re-file | goal-post | tm2-plan a9e1c97a9 → 0c3a5504e; kit 40158a730 |
| 5 | The build start moved behind router data. Chosen 10-08, when the fresh set was expected "likely before the gate anyway"; it is now the binding constraint | goal-post | packet 915d7fb98b7f; gate row 15 |
| 6 | 9 certification-round re-closes across 6 rounds (seed-match fix, settling, rating re-passes that never brought kappa above 0.24) | rework | `hl rework_round_recloses` |
| 7 | 6 freezes in under 3 days (10-10 to 10-13) | rework | `hl rework_freezes` |
| 8 | 6 decisions ruled more than once (28 rule events for 22 decisions) | rework | `hl rework_decisions_ruled_more_than_once` |
| 9 | 2 abandoned fires, and a duplicate kit-row4-filed-2 | rework | `jq .fires.abandoned data/t_time.json` |
| 10 | 67 kit defect fixes, 17 of them in Wk3. They include the research block refusing the program's own round (0ed9589d0), gate row 13 reading an overwritten preflight (9000cec6f), and freshness reading a crash as a refutation (0816f9cb4) | plumbing | `hl kit_commits_D` |
| 11 | 39 router commits (13,075 lines) for a gate row that still fails "router not built" | plumbing | `hl rework_kit_router_commits` |
| 12 | 11 method v1.2 / Stage 9 commits built mid-program, which this program cannot use | plumbing | `hl rework_kit_v12_stage9_commits` |
| 13 | 5 load-handling fixes for Stage 8 measurement scripts (machine load ~400) | plumbing | `hl rework_s8_load_fix_commits` |
| 14 | 107 bundle backups of tm2-plan, 35.3 GB | plumbing | `hl rework_bundle_backups`, `hl rework_bundle_gb` |
| — | 17 premises refuted by later reads; 65 of 74 challenges voided | legitimate iteration | `hl premises_refuted`, `hl rework_challenges_void` |

**The three changes that would cut cost per unit of progress most:**

1. **Let the build start on the 18 rows that pass or are filed, and carry the router row (row 15) as a filed residual.**
   - The router decides whether a prompt re-asks certified research. It says nothing about the TrueMemory plan, yet it now sets the build date.
   - Saves about 30 calendar days (10-16 to about 11-15), plus the daily freshness churn needed to keep evidence fresh while waiting: 7 Stage 8 freshness commits and most of the 701 live-read probes (`hl rework_s8_freshness_commits`, `hl probes_live_read`).
   - This is the operator's call, because it changes the contract.
2. **Freeze the kit while a program certifies, and land kit changes between programs after a pilot on a fixture program.**
   - Half the kit's commits were defect fixes, and 21 of the 58 fires were kit fires. Many landed mid-certification and forced re-closes and re-runs. 11 commits built a method version this program cannot use.
   - Saves roughly half the kit spend (about 17 pp) and most of the 9 re-closes.
3. **Stop review on yield, priced at the escape cost, instead of on a fixed round cap followed by a gate-row campaign.**
   - Rounds still paid about 60 times their cost when the cap stopped them.
   - Stage 8 then spent 3.41 days on 3 finds.
   - Also drop the rating re-pass: with kappa between 0.016 and 0.235, it did not stabilize the ratings and it caused re-closes.
   - Spends the remaining days where findings come in at 8–13 per 1–3-hour round rather than 3 per 3.4 days.

Smaller levers:
- Batch operator decisions into one sitting per stage. There were 39 class-C packets with a median 31 hours open, and 72 hours of nothing running while one was open.
- Prune the 35 GB of bundles.

## 6. Coverage and method: what this cannot see

- **Attribution** (`jq .sessions_by_bucket_how data/k_attrib.json`). Each session is assigned by one rule:
  - 612 core sessions by working directory: 548 program (including the reviewer sessions inside the program's round bundles) and 64 kit. Another 34 adoption sessions and 1 measurement session were also placed by directory, outside the core.
  - 24 by first prompt (the brief), after stripping the hook line that injects "RESEARCH PROGRAM truememory-2-0" into unrelated prompts. A brief that only names the program also needs at least 5 transcript lines in the program worktree, unless it is a lead brief.
  - 3 by the same session id on a second account (an account switch keeps the id).
  - 8 by hand-read override: 4 method design, 3 mixed, 1 excluded. The reasons are in `data/k_sessions.csv`.
- **Not attributed: 17 sessions (48–58 pp)** whose transcripts name the program path at least 5 times. All 17 were read: they are other fleet work (backlog, terminal crashes, permission prompts, limit recovery) and are excluded. They are reported only as an upper band (`hl pp_core_upper_with_mixed_and_suspect` = 311 pp).
- **Lower bounds.** Agent and subagent output is often missing its final record, so output tokens under-read wherever agents did the work (cc-quota-price docstring).
- **Outside the census.**
  - Certification used other vendors: 50 OpenAI and 52 Google panel or rater calls (`jq '[.rounds[].panels_by_vendor.openai//0]|add' data/m_movement.json`). They run on ChatGPT Plus and Antigravity (plan tier unknown), and their tokens are not in Claude transcripts.
  - Fable 5.1 calls are in the census.
  - Operator time is not measured at all.
- **Quota.** The fitted price's token classes are strongly collinear (r 0.75–0.94), so the per-class split is unreliable. Totals are not: M1 and M2 agree within 1.3%, and the fitted price explains 90% of the fleet's measured meter movement (`jq '.agg[]|select(.key==["fleet","all"])' data/k_attrib.json` priced at M1, against 1,171 pp moved).
- **"Working" hours** measure presence, not progress. Load waits inside measured re-proofs count as working.
- **"Material"** rests on ratings with kappa 0.02–0.24. "Names a decision" (a hole citing a DR-* id) is a proxy for decision-changing.
- **Kit classes** are hand-assigned. A cruder subject-only rule (fix/revert) gives 61 defect fixes instead of 67 (`y_crosscheck.sh`, NOTE line).
- **No separate auditor agent.** The research block refused Workflow and Agent in this session, because the program is certifying. In its place, `y_crosscheck.sh` re-derives 21 headline numbers by a different method each (raw git, jq, the REST API, cc-custody, cc-quota-price). All 21 pass (`data/y_crosscheck.txt`).
- **Privacy.** This repo is public. The program's records stay on the private tm2-plan branch, and `config/public-hygiene.conf` lists the program dir as local-only. So this report's data holds counts and commit hashes, never private commit subjects or session prompts. `data/k_raw.json` (every session's first prompt) is gitignored and regenerated locally.

## 7. Reproduce

From the repo root, in order. Steps 1–3 read about 30 GB of transcripts and take about 15 minutes at load ~400.

```
S=docs/research/tm2-cost-vs-outcome-2026-10-16/scripts; D=docs/research/tm2-cost-vs-outcome-2026-10-16/data
python3 -I $S/k_census.py                                   # deduped census per session and hour -> $D/k_raw.json (local only)
bin/cc-quota-price --census --since 2026-09-27 > $D/k_ccqp_census.txt
bin/cc-quota-price --json --since 21d > $D/k_ccqp_fit21d.json
python3 -I $S/k_attrib.py                                   # attribution, M1 and M2 quota -> k_attrib.json, k_sessions.csv
python3 -I $S/o_records.py                                  # program records -> o_records.json
python3 -I $S/p_kit.py                                      # kit commits, classified -> p_kit.json, p_kit_commits.csv
gh pr list -R buildingjoshbetter/TrueMemory --state all --author @me --json number,title,state,createdAt,mergedAt > $D/p_upstream_prs.json
gh issue list -R buildingjoshbetter/TrueMemory --state all --author @me --json number,title,state,createdAt > $D/p_upstream_issues.json
python3 -I $S/t_time.py                                     # stages, hours, packets, fires -> t_time.json
python3 -I scripts/research-kit/estimate.py forecast --program truememory-2-0 > $D/m_estimate_forecast.txt
python3 -I $S/m_movement.py                                 # yield, rounds, forecast, escape cost -> m_movement.json
python3 -I $S/r_rework.py                                   # named rework counts -> r_rework.json
python3 -I $S/z_headlines.py > $D/z_headlines.txt           # every headline number, key = value
bash $S/y_crosscheck.sh                                     # independent re-derivation of 21 headlines
```

All inputs are read-only. The scripts write only under this directory. No program record was written, and no research verb was run.
