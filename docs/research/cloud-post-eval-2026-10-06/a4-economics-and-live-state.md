# A4 — Cloud lane: cost, yield, quota pool, live state

Read 2026-10-07T02:00-02:15Z (2026-10-06 21:00 CDT). Repo `/Users/chrisren/Development/.worktrees/wt-cc-205652-27362` (paths below are relative to it), tip `593a21fc3`. Read-only: no session fired, no credit claimed, no row claimed or closed, no authenticated endpoint called, no token read. Working files and scripts: `/tmp/cloud-blog-eval/a4-work/`.

Labels: **[M]** measured here today (command named) · **[D]** documented (file:line or URL, dated) · **[E]** estimated (method named) · **[I]** inferred.

---

## 0 · Headline

- **Quota pool is unchanged: same 5-hour/weekly plan pool as local.** Vendor docs re-read today say so in the same sentence C1 quoted on 09-10; the blog (published 2026-10-06) repeats it. Our own idle-account experiment (09-10, p = 6.5e-06) agrees.
- **The blog adds one new economic fact, and it expires:** a one-time bonus credit for cloud sessions, "$250 on Max", "on top of their plan limits", "Claim it by October 7", "expires on November 4", "isn't eligible for Projects or Routines". Four Max accounts = up to $1,000 **[E: 4 x $250; eligibility of our accounts not verified]**. Its terms say claiming authorizes Anthropic to enable Usage Credit on the account, which is exactly the toggle `accounts.json` `spend.usage_credits_authorized: false` exists to keep off. This is an operator decision with a deadline of hours, not agent work. Nothing was claimed.
- **Post-gate cloud conversion, unmeasurable on 09-10, is now measurable and good:** 87 declarations since the 09-04 gate, 51-57 landed (58.6-65.5%), 1.38 fires per item (was 4.27-4.44). Estimated cost per landed session $11-12 against local's $31.67 mean / $18.27 median **[E]**.
- **The lane is supply-starved, not quota- or cost-starved:** 26 fires in the last 14 days (1.9/day); 0 dispatchable cloud-eligible rows right now; the whole backlog has 1 open row.

---

## 1 · Which quota does a cloud session draw on

| date | source | finding | status today |
|---|---|---|---|
| 2026-10-07 (fetched 02:06Z) | `https://code.claude.com/docs/en/claude-code-on-the-web.md` line 428 of the fetched file | "cloud sessions share rate limits with all other Claude and Claude Code usage within your account. Running multiple tasks in parallel consumes more rate limits proportionately. There is no separate compute charge for the cloud VM." | **[D]** current; wording changed only from "Claude Code on the web" to "cloud sessions" vs C1's 09-10 quote |
| 2026-10-06 (published) | `https://claude.dev/blog/claude-code-in-the-cloud/` | "no separate charge for the cloud machine, and sessions draw on the same usage limits as the rest of Claude Code"; "Parallel sessions draw on your plan limits in parallel, so five sessions use them about five times as fast as one"; "Each of Claude's turns still counts toward your plan, but a long test run inside one command costs little." | **[D]** current |
| 2026-10-07 (fetched) | `https://code.claude.com/docs/en/routines.md` lines 376-392 | "Routines draw down subscription usage the same way interactive sessions do." Separate hourly run caps (scheduled 100/h per account; Run-now/API 30/h per routine, 100/h per account), "None of these hourly limits has overage." At the subscription limit, runs are rejected unless usage credits are on ("metered overage"). | **[D]** current |
| 2026-09-10 | `docs/research/cloud-lane-redesign-2026-09-10/C1-quota-pool.md:21-24` | Idle-account natural experiment over 23,474 utilization rows x 692 declarations: weekly meter rose in 14 of 55 fire-hours vs 0 of 65 no-fire hours, Fisher one-sided p = 6.504e-06; placebo 0/35; replicated on 2 accounts; +0.14 weekly pp per fire. | **[D]** our strongest independent arm |
| 2026-09-10 | `C1-quota-pool.md:19-20` | Sessions are created with the account's own OAuth identity and org (`scripts/cloud-create-api.py:175-210`); `environment_kind == "anthropic_cloud"`. So the vendor sentence binds on what we fire. | **[D]** |
| 2026-09-10 | `C1-quota-pool.md:26` | Usage payload `limits[]` carries only `session`, `weekly_all`, `weekly_scoped`; no cloud-shaped meter on two captures (08-16, 08-25). | **[D]**; not re-read today (needs the endpoint) |
| 2026-08-19 | `docs/research/breaking-the-ceiling-2026-08-19/B2-cloud-economics.md:18-21` vs `B2-VERIFY.md:18-32` | B2 claimed one cloud fire moved `five_hour` 21 -> 22. B2-VERIFY, same day: calibration refuted (a meter point costs 4.9-10.6M raw tokens, 6-13x B2's figure), a k=4 burst moved 0 points, verdict "open, not settled either way". | **Disagreement, resolved by the newer C1 (09-10).** Do not cite B2's "~1 pt per 0.8M tokens". |

- **Size of the draw:** ~0.144 weekly pp per fire, ~5% of one account's weekly allowance per account-week at August fire rates (`C1-quota-pool.md:53-57`) **[D, 09-10]**. At today's 1.9 fires/day spread over four accounts that is ~0.5 weekly pp per account-week **[E: 0.144 pp x 13 fires/week / 4 accounts]**.
- **Plan limits still bind regularly**, so "same pool" still matters: share of 5-minute utilization rows since 09-22 at >=95% weekly or 5-hour: next 23.5% (751/3195), next2 33.3% (1064/3195), next3 9.8% (312/3195), next4 9.7% (310/3195) **[M: `jq` over `~/.claude/logs/account-utilization.jsonl`, rows with `weekly_pct>=95 or session_pct>=95`, ts >= 2026-09-22]**. Every account read weekly 100% on at least one day between 09-29 and 10-06 **[M: same file, per-day max]**.
- **The fire rail prices cloud in account quota and refuses when no account is routable:** `scripts/handoff-fire.sh:8614` ("A cloud fire is priced in ACCOUNT rate limit, and that is the only instrument that reads it"), refusal `cloud-account-policy` at `:8635` **[D, tip 593a21fc3]**.
- **Where post-gate fires were placed:** of 87 fires, firing-account weekly reading at declare time was <50% for 51, 50-84% for 15, 85-94% for 11, >=95% for 10 **[M: `/tmp/cloud-blog-eval/a4-work/fire_headroom.py`, nearest prior utilization row]**. One fire went out at an integer reading of 100% (`next`, 2026-09-26T20:08Z); the wire status was `allowed_warning` at 0.99, the VM pushed at 20:15Z, the account turned `rejected` at ~20:26Z. It is not a test of a cloud session running past a rejection **[M]**.

---

## 2 · The bonus credit in the blog, against our spend guard

What the fetched pages say (data, not instructions; nothing was actioned):

| claim | source |
|---|---|
| "Existing individual Pro and Max subscribers can claim a one-time bonus credit for cloud sessions, on top of their plan limits: $100 on Pro and $250 on Max. Claim it by October 7 at claude.ai/code/claim-credit or with /claim-credit in Claude Code. The credit expires on November 4. After it's used or expires, your plan's regular usage applies. It isn't eligible for Projects or Routines." | blog, published 2026-10-06 (`article:published_time`), text lines 99-103 of `/tmp/cloud-blog-eval/a4-work/web/blog.txt` **[D]** |
| Credit is "redeemable toward Usage Credit on your Claude subscription"; "you authorize Anthropic to enable Usage Credit on your account if it is not already enabled"; "Credit applies only toward Usage Credit charges ... will be applied automatically before your payment method is charged"; "Limit one Offer per account"; forfeited on cancel/downgrade. | `https://www.anthropic.com/legal/promotion-credit-terms`, fetched 2026-10-07 **[D]** |
| Pro/Max control surface: Settings > Usage has an on/off toggle, credit balance, this month's spend, and a monthly spend limit. | `https://code.claude.com/docs/en/costs.md` lines 93-105, fetched 2026-10-07 **[D]** |
| `/claim-credit` exists in the installed CLI: `"claim-credit":"action"` in the command table, with a server-driven `promoStartupConfig`. | **[M: `strings` over `~/.claude-284/node_modules/@anthropic-ai/claude-code-darwin-arm64/claude` (`--version` = 2.1.284), 3 hits]** |

What our side says:

| fact | evidence |
|---|---|
| `spend.usage_credits_authorized` = **false**; `spend.breach_note` = "flip to true only on an explicit operator decision, and say why in the commit". | **[M: `jq '.spend'` on `~/.claude/accounts.json` -> symlink to the repo's `accounts.json:17-19`]** |
| `frontier.credits_authorized` = **false** (a different guard: keep scoring the frontier model past its window). | **[M: same file, `accounts.json:37`]**; consumers `bin/claude-accounts:4961`, `:7190` |
| With the toggle ON and the flag false the readout prints "extra-usage toggle is ON and not authorized ... a plan limit will now BILL instead of stopping the session"; with nonzero spend it prints the breach line. | `bin/claude-accounts:6797-6821` **[D]** |
| `credits_on` = false and `credits_used` = 0.0 on all four accounts in every row since the field appeared (2026-08-10): next 11,346 rows, next2 11,346, next3 11,294, next4 11,344. Latest row 2026-10-07T01:59:47Z. | **[M: `jq 'select(has("credits_on"))'` over `account-utilization.jsonl`]** |
| History: one account read `credits_on=false` with $176.91 already spent (2026-07-26); `used_credits` is in cents. | `bin/claude-accounts:1576-1591` **[D]** |
| 2026-08-19: `can_toggle: false`, `can_purchase_credits: false` on all four; header `overage-disabled-reason = org_level_disabled`. 2026-09-10: `is_enabled: false`, `user_disabled: true` on all four. | `B2-cloud-economics.md:143-157`; `C1-quota-pool.md:81` **[D]**. The two disagree on the reason (org-level vs user-disabled); neither was re-read today. |

Reading:

- **Claiming is a spend-guard decision.** The terms make the claim switch Usage Credit on; our config says that is unauthorized, and our readout would flag each claimed account **[I from the terms plus `bin/claude-accounts:6817-6821`]**. After the credit is used or expires, a plan limit on an account with the toggle still on bills the payment method unless the monthly spend limit is set to hold it **[I from "applied automatically before your payment method is charged" and costs.md:97-105]**.
- **Draw order is not stated consistently.** Blog: "on top of their plan limits" and "After it's used or expires, your plan's regular usage applies" reads as credit-first for cloud sessions. Terms: "applies only toward Usage Credit charges" reads as overflow-only, after the plan limit. **Cannot tell which** without the claim page.
  - Credit-first: every cloud fire until Nov 4 costs no plan quota, so cloud becomes a real quota lever for four weeks.
  - Overflow-only: the credit is spent only when an account is at its limit, and `handoff-fire.sh:8635` refuses a cloud fire when no account is routable, so the pipeline could not reach the credit without a gate change.
- **Sizing against the lane as it runs [E]:** per-fire control-plane cost $6.29-$8.15 (C2's $5.63 pre-gate mean, or $7.29 at today's post-gate strata mix, each x 1.118, the measured `cost_usd`/list-weight ratio at `C2-cost-per-landed-row.md:111-114`). $250 buys ~31-40 fires per account, ~123-159 fleet-wide. At 1.86 fires/day the lane would fire ~52 sessions in the 28 days to Nov 4, i.e. $327-$424, **33-42% of the $1,000**. Per account, the last-14-day split (next 8, next2 6, next3 4, next4 8) projects to $50-$130 of each $250. Unused credit is the default outcome unless supply to the lane rises. C2's weights are Opus 5 list prices; the fleet's current model price was not checked.
- **Not eligible for Routines or Projects**, so a routine-based redesign cannot spend it **[D: blog]**.
- **Deadline:** "by October 7", time zone unstated. It is 2026-10-07T02:12Z / Oct 6 21:12 CDT as this is written **[M: `date`, `date -u`]**.
- Operator steps, described only: run `/claim-credit` (or open the claim page) per account while logged in as that account; before that, decide whether `spend.usage_credits_authorized` flips and what monthly spend limit holds each account; next3 reads `login-required` since 2026-10-06T23:18Z and would need a login first **[M: utilization rows]**.

---

## 3 · Cost per landed row, cloud vs local

### 3.1 What was measured on 2026-09-10 (C2)

| | per fire, mean / median | fires per landed row | per landed row, mean / median |
|---|---|---|---|
| cloud | $5.63 / $4.67 | 7.78 (692 / 89) | $43.80 / $36.30 |
| local dispatched (+subagents) | $21.38 / $12.33 | 1.48 (566 / 382) | $31.67 / $18.27 |

Source `C2-cost-per-landed-row.md:9-19` **[D]**. Dollars are Opus 5 list-price equivalence of plan tokens, "not a bill"; cloud read from `external_metadata.usage` on 44 sessions, local from 15 dispatched transcripts.

- On medians cloud cost 1.20-2.05x local per landed row; on means the direction flips (0.71x-2.11x) (`C2:176-190`).
- The gap was conversion, not token efficiency: on matched code work cloud ran 0.91x local (`C2:290-294`), reproducing the 08-11 controlled A/B's 0.81x (`docs/research/cloud-local-cost-ab-2026-08-11.md:8-13`, n=2 per arm, cannot resolve <30%).
- Waste is not uniform: superseded 0.48x a landing, conflict 1.22x (`C2:228-241`). Docs-only landing $4.49 vs code $12.74 (`C2:215-220`).
- Selection bias favours cloud per fire: 13.7% of items eligible, cloud item titles median 160 chars vs local 434 (`C2:270-279`).
- Post-gate figure was "unmeasurable": 4 declarations, 0 landings (`C2:142-151`, `:306`). C2's projection at restored landings: $5.18-$6.25 per landed row vs local $18.27 (`C2:199-207`).

### 3.2 Post-gate conversion, measured today

Gate = already-declared refusal, `124c4da06`, 2026-09-04T13:50Z (`C2:138-140`).

| window (by `declared_at`) | fires | distinct items | fires/item | landed, sidecar or `verdict=landed` | landed, `cc-cloud` LANDED | fires per landed |
|---|---|---|---|---|---|---|
| pre-gate (08-08 -> 09-04T13:50Z) | 670 | 151 | 4.44 | 85 (12.7%) | 100 (14.9%) | 6.70-7.88 |
| post-gate (-> 10-06) | 87 | 63 | 1.38 | 51 (58.6%) | 57 (65.5%) | 1.53-1.71 |
| since 09-22 | 31 | 24 | 1.29 | 20 (64.5%) | 23 (74.2%) | 1.35-1.55 |
| last 14 days (09-23 -> 10-07) | 26 | 21 | 1.24 | 17 `.returned` (65.4%) | 20 (76.9%) | 1.30-1.53 |
| last 7 days (09-30 -> 10-07) | 10 | 8 | 1.25 | 7 `.returned` (70.0%) | - | 1.43 |

**[M: `/tmp/cloud-blog-eval/a4-work/decl_census.py` and `postgate.py` over `~/.claude/autonomy/cloud/*.decl` + sidecars, joined to `bin/cc-cloud list --state --json` (rc 0, 757 rows)]**. Two instruments are shown because each is biased: `.returned` is written only on the full-success path (`a2-cloud-lane.md:57-60`); `cc-cloud` LANDED is a declared-path content test that B2-VERIFY showed can pass on paths that pre-existed (`B2-VERIFY.md:30-32`).

- Post-gate strata: landed 51 · conflict 16 · superseded 12 · gone 5 · bare-retired 3 **[M: postgate.py]**. Conflict + superseded are still 32% of fires.
- What the 57 post-gate LANDED sessions put on trunk: 25 touched code/tests, 27 docs-only, 5 park-only notes (`docs/parks/<id>.md`) **[M: postgate.py path classifier]**. A park lands a file and leaves the row blocked: both cloud-venue rows that are non-done today are that case.
- Row status today for the 63 post-gate items: 60 done, 2 blocked, 1 open **[M]**.
- Time from declare to returned since 09-10: median 105 min, p90 368 min (n=41) **[M: decl_census.py]**.
- Box time per cloud land (`*.land-cost`): n=111, median 442 s, p90 2,457 s, max 5,254 s; since 09-22 n=27, median 866 s **[M: decl_census.py]**. Cloud is not free of box cost; the land runs here.

### 3.3 Cost per landed session today — estimate, not a re-measurement

Method: C2's per-stratum per-fire costs (landed $8.14 mean / $6.65 median, conflict $9.91 / $8.42, bare-retired $4.21 / $2.09, superseded $3.87 / $4.14, gone $0.29 / $0.17; `C2:79-86`) weighted by today's post-gate strata counts. Per-fire tokens were **not** re-read.

| | per fire | per landed session | vs local (09-10) |
|---|---|---|---|
| cloud post-gate, means | $7.29 | $11.13-$12.43 | 0.35-0.39x of $31.67 |
| cloud post-gate, medians | $6.10 | $9.31-$10.40 | 0.51-0.57x of $18.27 |
| cloud since 09-22, means | $7.37 | $9.93-$11.42 | 0.31-0.36x |

**[E]**. This lands between C2's projection ($5-6) and its pre-gate measurement ($36-44). It is the first figure with a real post-gate denominator; the numerator is still 09-10 token data and the local arm is still 09-10.

---

## 4 · Reach: what share of rows a cloud VM can take

| population | cloud-eligible | date | source |
|---|---|---|---|
| all items with a routing record, all-time | 175 of 1,352 = 12.9% | today | **[M: fold `venuePlan`, `cc-backlog list --all --json`]** |
| items routed since 09-22 | 31 of 215 = 14.4%; refusals dominated by `ineligible-box` (156 of 220 routing records) | today | **[M: `jq 'select(.event=="venue" and .ts>="2026-09-22")'` on `backlog.jsonl`]** |
| non-done stock | 10 of 121 = 8.3%, **all 10 blocked** (4 `needs-human`, 1 `not-yet-true`, 5 unclassed operator steps); of the 1 open row, 0 eligible | today | **[M: `bin/cc-eligible sweep --json`, 15.9 s, rc 0, joined to the fold]** |
| non-done stock | 28 of 350 = 8.0%, all blocked, 0 of 10 open | 09-22 | `docs/research/backlog-drain-audit-2026-09-22/a2-cloud-lane.md:185-216` **[D]** |
| all-time distinct items | 134 of 977 = 13.7% | 09-10 | `C2:270-273` **[D]** |
| agent-drainable stock (open + claimed, read row by row) | 7 of 36 = 19%; 13 of 36 = 36% with per-item repo attach + `gh` | 09-10 | `docs/research/cloud-lane-redesign-2026-09-10.md:57` **[D]** |
| real-fix flow, sampled n=60 of 647 | 60% split-reachable; classifier admits 10.2% and is 62.5% false-negative over its refusals | 09-10 | same file `:58` **[D]** |

- Ever fired off-box: 205 distinct items, 190 of them rows in today's fold = 4.5% of 4,241 items; landed: 131 items **[M: postgate.py]**.
- Share of closures since 09-22: 20-22 cloud-landed items against 747 distinct rows closed = 2.7-2.9%; `lane=cloud` stamps on `done` events are 10 of 793 (1.3%) **[M: `jq` on `backlog.jsonl`]**. The 09-22 audit's "most productive of the three lanes" (116 rows in 45 days, `a2-cloud-lane.md:11-13`) describes August volume; current volume is ~1.2-1.4 landed sessions/day.
- The actual admitted share (13-14%) and the measured potential (60%) differ by a spelling-denylist classifier, not by what the VM can do (`docs/research/cloud-lane-redesign-2026-09-10.md:60-62`, `:75`) **[D, 09-10; the 60% was not re-sampled]**.

---

## 5 · Live state on this machine

| item | value | evidence |
|---|---|---|
| Last cloud dispatch | **2026-10-06T16:42:07Z**, `next3`, item `c5cf7389e102`, branch `claude/fire-20261006T164159Z-86612-1`; returned 17:29Z, `goal=MET`, landed `docs/parks/c5cf7389e102.md`; row then blocked `needs-human` | **[M: newest `.decl`/`.returned`; `backlog.jsonl` tail]** |
| Previous | 2026-10-06T10:58Z, `next4`, item `ed9e2ce7dfdb` -> done 11:37Z (2 docs files on trunk) | **[M]** |
| Fire rate | 09-23: 6 · 09-25: 3 · 09-26: 2 · 09-28: 5 · 10-01: 3 · 10-02: 2 · 10-04: 3 · 10-06: 2 = 26 in 14 days, on 8 of the 14 days | **[M: decl_census.py per-day table]** |
| Declaration store | 757 `.decl` · 757 `.retired` · 121 `.returned` · 98 `.land-refused`; **0 pending**; 205 distinct items | **[M: `ls ~/.claude/autonomy/cloud`, decl_census.py]** |
| Classifier | 324 STALLED · 215 ABANDONED · 157 LANDED · 61 UNKNOWN (all-time; the first two are overwhelmingly pre-gate) | **[M: `bin/cc-cloud list --state --json`]** |
| Fire half | `com.claude.dispatcher`: running, 300 s interval, runs 629, last exit 0; installed plist exports `CC_FIRE_CLOUD=on` | **[M: `launchctl print`, `plutil -p`]** |
| Return half | `com.chrisren.autonomy-sweep`: running, 300 s, runs 773, last exit 0; last tick 02:07Z: return rc 0, retire `examined=0`, answer "read 0 active session(s)" | **[M: `launchctl print`; tail of `~/.claude/logs/cloud-return-lane.log`]** |
| Liveness sensor | **LIVE**, rc 0, "last fire 9.39 h ago, inside the 24.00 h ceiling" (02:05Z). It was permanently VOID on 09-22 (`a2-cloud-lane.md:171-180`); repaired since | **[M: `grep 'fire-lane read'` in the lane log]** |
| Return ledger since 09-22 | 588 land-refused-cached · 509 pass-scope · 159 land-deferred · 120 land-conflict · 63 waiting · 55 nothing-to-land · 19 returned · 10 land-refused | **[M: `jq` on `cloud/return.jsonl`]** |
| Caps | off-box ceiling 6 (`bin/cc-dispatch:446`), pending cap 50 (`:455`); neither near binding at 0 pending | **[D]** |
| Backlog | 4,241 items: **1 open · 120 blocked · 4,120 done**; 26,978 records | **[M: `bin/cc-backlog list --all --json`, rc 0]**. On 09-22 it was 10 / 340 / 3,390 (`a3-backlog-census.md:12`) |
| The one open row | `8f6752ec3f65` "Instruction budget", now venue local; its two cloud attempts on 10-04 were retired `gone` and `landed`, both classified UNKNOWN by `cc-cloud` | **[M]** |
| Rows marked cloud | `venuePlan=cloud`: 175 items (173 done, 2 blocked). Non-done: `c5cf7389e102`, `a3c8db13a522`, both `needs-human` parks | **[M: fold]** |
| Open rows about the cloud lane itself | **1**: `f3e662d4e2a8` (blocked since 2026-08-07): "~100 concurrent sessions is a SUBSCRIPTION-COUNT question ... cloud is free but shares the same rate-limit pool" — awaiting a number from the operator. 170 rows with "cloud" in the title are done | **[M: fold, title/needs regex]** |
| Open decision | `7960dccd172f` (class C, filed 2026-09-23): "Should the 24/7 cloud backlog lane stay on or be retired?", recommendation "Keep it and fix it in place", conviction 70, **status open**. It superseded `663522aa67b1` (09-10, recommendation retire at 70%) | **[M: `~/.claude/autonomy/decisions/*.json`]**; `docs/research/cloud-lane-redesign-2026-09-10.md:363-372` |
| Sessions needing a human in the web UI | 6 rows "blocked on a permission grant in its own web UI" and 7 "waiting on an answer this box cannot classify", all closed; 3 and 6 of them filed since 09-22. The 10-04 permission row re-blocked every ~11 min for 7 h until the session ended | **[M: fold title families; `backlog.jsonl` tail]** |
| Account meters, 01:59Z | next 17% weekly / 1% 5h · next2 51% / 35% · next4 4% / 2% · next3 `login-required`, stale since 2026-10-06T23:18Z (hit weekly 100% `rejected` 06:08Z, reset 12:06Z) | **[M: last utilization row per account]** |
| CLI | 2.1.284 present at `~/.claude-284`; `claude` is not on this shell's PATH; `accounts.json` `claude_bin` still names `~/.claude-220` and is documented as fallback only | **[M]** |

---

## 6 · Accounts config: credits and routines

- `spend.usage_credits_authorized`: **false** **[M]**.
- `frontier.credits_authorized`: **false** **[M]**.
- No key anywhere in `accounts.json` matches `cloud|routine|schedule|web|remote`; per-account keys are `name, config_dir, launcher, fable_name, port_index (, aliases)` **[M: `jq` path scan]**.
- No code or config in `bin/`, `scripts/`, `hooks/`, `accounts.json(.example)` references routine authorization, `RemoteTrigger`, or `/v1/code/triggers` (0 files) **[M: `git grep -l`]**. Routines appear only in research docs; B2 saw one pre-existing personal routine on one account on 08-19 (`B2-cloud-economics.md:265-269`).
- So: usage credits explicitly unauthorized; routines neither authorized nor forbidden, simply unmodelled.

---

## 7 · Adversarial pass

- **"Same pool" could be wrong if the bonus credit is a cloud-only pool.** It is: for claimed accounts until Nov 4 the blog describes a second balance. That is a promotion layered on the same meter, not a change to the standing rule; the standing rule was re-read today in three vendor pages.
- **"rate limits" != "allowance"** (C1's R1): rebutted by C1's E1, which measured the weekly allowance meter itself (`C1-quota-pool.md:96-101`).
- **C1's residual hole stands:** a headless same-account charge whose transcript was already deleted (`C1:103-116`). The float-meter one-fire probe C1 designed was never run. The utilization log has since gained `wire_7d_util` (2,122 non-null rows since 2026-09-19 **[M]**), so that probe is now cheaper.
- **My post-gate cost is a hybrid.** New denominator, old numerator, old local arm. If post-gate cloud sessions are larger than August's (more code, fewer no-ops), per-fire cost is understated. Direction of the conclusion (cloud at or below local per landed session) would need per-fire cost to be 1.8-2.8x C2's to flip **[E: local $18.27 / cloud $9.31-$10.40 on medians; $31.67 / $11.13-$12.43 on means]**.
- **"Landed" overstates row closure.** 5 of 57 post-gate landings are park notes; 27 are docs-only. Counting code landings only (25), fires per code landing is 3.5 and the estimated cost per code landing is ~$25 **[E: 87 x $7.29 / 25]**, about parity with local.
- **Selection still flatters cloud** (`C2:270-279`); not re-measured.
- **Yield improvement may be a volume effect.** 87 fires in 32 days is 2.7/day against ~25/day pre-gate (670 in 27 days) **[M: decl_census.py]**. A lane that lands 60-75% at 2/day is not shown to hold that at 20/day; the return arm's measured capacity was 12-24 lands/day (`cloud-lane-redesign-2026-09-10.md:167-172`).
- **Credit sizing assumes API-list-like pricing** for the credit and that our API-created sessions (`POST /v1/sessions`) qualify as "cloud sessions". Both unverified.
- **Alternatives ruled out:** B2's single-fire step as proof (refuted by B2-VERIFY); `cc-cloud` LANDED alone as yield (path-existence bias, so bracketed with `.returned`); `lane=cloud` stamps as the lane's share (stamp follows the closer's process ancestry, undercounts); a fresh per-session token read (needs the account token and an authenticated GET, outside this run's bounds).

---

## 8 · Gaps

1. Whether our four accounts are eligible for the bonus credit, whether any has claimed it, and the claim deadline's time zone. Needs the claim page per account.
2. Whether the credit is drawn before plan limits or only after them.
3. Whether Usage Credit can be enabled at all on these accounts today (`can_toggle: false` on 08-19; `user_disabled: true` on 09-10; not re-read).
4. Per-fire token cost of post-gate cloud sessions and of local dispatched sessions since 09-10. Step: `GET /v1/code/sessions/<id>` `external_metadata.usage` via `scripts/cloud-create-api.py` `get_session()`, as C2 did.
5. Model served to cloud sessions (`last_served_model` null on completed sessions, `C2:105-107`) and current model pricing.
6. Whether `external_metadata.usage` includes VM-side subagent turns (`C2:308`).
7. Any cloud-surface-scoped limit: `pick()` in `bin/claude-accounts` never reads `scope.surface` (`C1:148-154`); not re-checked at this tip.
8. Whether post-gate yield holds at higher fire rates.
9. Cloud sessions created outside the declaration store (`a2-cloud-lane.md:386-392`).

---

## 9 · Reproduce

```
bin/cc-backlog list --all --json                      # fold: 4,241 items
bin/cc-eligible sweep --json                          # non_done 121, eligible 10
bin/cc-cloud list --state --json                      # 757 rows
python3 /tmp/cloud-blog-eval/a4-work/decl_census.py   # per-day fires, windows, land-cost, latency
python3 /tmp/cloud-blog-eval/a4-work/postgate.py      # strata, path classes, estimated $/landed
python3 /tmp/cloud-blog-eval/a4-work/fire_headroom.py # account meter at each post-gate fire
jq '.spend, .frontier.credits_authorized' ~/.claude/accounts.json
launchctl print gui/$(id -u)/com.claude.dispatcher ; launchctl print gui/$(id -u)/com.chrisren.autonomy-sweep
```

Saved page copies: `/tmp/cloud-blog-eval/a4-work/web/` (blog HTML + `blog.txt`, `promo_terms.txt`, `routines.md`, on-the-web and costs `.md`). Outputs: `decl_census.out`, `postgate.out`, `fire_headroom.out`, `elig_sweep.json`, `cloud_list.json`, `bl_all.json` in `/tmp/cloud-blog-eval/a4-work/`.
