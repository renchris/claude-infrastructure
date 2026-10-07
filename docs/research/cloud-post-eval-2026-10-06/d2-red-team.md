# D2 red team — claim the cloud bonus credit on the four Max accounts?

Read 2026-10-07T04:05Z (Oct 6 23:05 CDT, `date; date -u`). Lens: strongest case against the prior verdict (skip, 65%), then an attack on that case.
Read-only run: nothing claimed, toggled, fired or logged in; no authenticated endpoint called; no token read.
`ROOT` = `/Users/chrisren/Development/.worktrees/wt-cc-205652-27362`.
Labels: **[M]** measured here (command named) · **[D]** documented (source says it) · **[I]** inferred · **[E]** estimated (method named).

## 0 · Verdict

- **Lean: CLAIM, staged — canary on `next4`, then `next`, `next2`, `next3` — about 60%.** Skip drops from 65% to about 40%.
- **Why it moved:** the prior skip rested on "claiming switches Usage Credit on, which `accounts.json` forbids". Anthropic's offer-specific FAQ says the opposite, and two user reports agree. No policy exception is needed on the documented path.
- **Why it did not move further:** the value is small in the fleet's own currency — about 6-10 weekly quota points fleet-wide at current cloud supply, ceiling 18-23 **[E]**. Being wrong in either direction costs little.
- **Deadline is a day, not hours:** Oct 7 23:59 PT = 2026-10-08T06:59Z = Oct 8 01:59 CDT; 26 h 54 min from this read **[D + M]**.

## 1 · What changed against the prior verdict

| prior premise (source) | today's evidence | label |
|---|---|---|
| "Its terms say claiming authorizes Anthropic to enable Usage Credit ... exactly the toggle `spend.usage_credits_authorized: false` exists to keep off" (`ROOT/docs/research/cloud-post-eval-2026-10-06/a4-economics-and-live-state.md:12`, `:61`) | Generic terms do say it: "you authorize Anthropic to enable Usage Credit on your account if it is not already enabled" (<https://www.anthropic.com/legal/promotion-credit-terms>, re-fetched, http 200) | **[M]** fetch, **[D]** content |
| same | Offer FAQ: "Do I need to turn on usage credits? No. You can claim and use your bonus credit without turning on usage credits ... You're only charged for usage credits if you've turned them on and you go past your plan's usage limits." (<https://support.claude.com/en/articles/17152539-cloud-sessions-bonus-credit-promotion>, http 200). Prior investigation did not fetch support.claude.com (`ROOT/docs/research/cloud-post-eval-2026-10-06/b2-official-docs-limits.md:194`) | **[M]** fetch, **[D]** content |
| same | Max 20x user's pasted Settings > Usage panel after claiming: separate "Cloud session credits · $247 of $250 left" block; "Usage credits · £0 · Turn on usage credits to keep using Claude if you hit a plan limit"; "No spend limit · Auto-reload off" (<https://github.com/anthropics/claude-code/issues/99597>) | **[D]** one user report |
| same | Max 5x user after claiming and spending over $100 of credit: "Usage credits toggle is OFF" (<https://github.com/anthropics/claude-code/issues/97021>, comment 2026-10-02) | **[D]** one user report |
| "Draw order is not stated consistently ... Cannot tell which" (`a4-...md:62`) | FAQ: "While you have credit remaining, cloud session usage is paid for by the credit and doesn't count toward your plan's usage limits." Credit-first | **[D]** |
| "Deadline: 'by October 7', time zone unstated" (`a4-...md:67`) | FAQ: "Claim by October 7 at 11:59 PM PT"; "Credits expire November 4 at 11:59 PM PT". Panel in #99597: "Expires 7:59 AM GMT+0, November 5" | **[D]** |
| "eligibility of our accounts not verified" (`a4-...md:12`) | FAQ: individual Pro/Max with an active subscription at 2026-09-23 14:00 PDT; excluded: Team, Enterprise, free trials, past-due payment. All four accounts have utilization rows since 2026-08-10 | **[D]** rule, **[I]** that ours qualify |
| credit could leak to local work | FAQ exclusions: Projects, Routines, Remote Control, Chat, Cowork, "Any Claude usage outside of cloud sessions" | **[D]** |

## 2 · Value left on the table by skipping

Fire counts recounted from `~/.claude/autonomy/cloud/*.decl` `declared_at` epochs: **10 in 7 d, 25 in 14 d, 69 in 28 d**; 28-day split next 16 · next2 19 · next3 13 · next4 21 **[M: shell loop over 757 `.decl` files]**. Days to expiry: 29.16 **[M: 2026-10-07T04:05Z to 2026-11-05T07:59Z]**.

| scenario | fires to Nov 4 | credit consumed | plan quota displaced | share of fleet quota (4 x 29.16 d = 1,666 pp) | at replacement cost |
|---|---|---|---|---|---|
| 7-day rate (1.43/d) | 41.7 | $262-$340 | 6.0 weekly-pp | 0.36% | $2.8 |
| 14-day rate (1.79/d) | 52.1 | $328-$425 | 7.5 pp | 0.45% | $3.5 |
| 28-day rate (2.46/d) | 71.9 | $452-$586 | 10.4 pp | 0.62% | $4.8 |
| all $1,000 spent | 123-159 | $1,000 | 17.7-22.9 pp | 1.06-1.37% | $8.1-$10.5 |

- Method **[E]**: fires x $6.29-$8.15 per fire (`a4-...md:65`, from C2 `ROOT/docs/research/cloud-lane-redesign-2026-09-10/C2-cost-per-landed-row.md:9-19`, `:108-114`) and x 0.144 weekly-pp per fire (`ROOT/docs/research/cloud-lane-redesign-2026-09-10/C1-quota-pool.md:53-57`). Neither per-fire figure was re-measured; C1 states its estimator was fitted on idle-account hours.
- Replacement cost **[E]**: $200/month per Max account (`ROOT/docs/research/breaking-the-ceiling-2026-08-19.md:277`, `ROOT/docs/research/concurrency-scale-2026-10-04/README.md:230`) / (100 pp x 4.345 weeks) = $0.46 per weekly-pp.
- Per account at current supply: 1.2-3.1 pp, $52-$178 of each $250 **[E: per-account 7 d and 28 d fire splits]**. No account reaches its $250 cap.
- The prior "4.4-5.7 pp per account" (`ROOT/docs/research/cloud-post-eval-2026-10-06/candidates.md:25`) is the full-spend ceiling. At today's supply the realised figure is 26-59% of it.
- Supply, not credit, is the limit: 1 open backlog row, 0 dispatchable cloud-eligible rows (`a4-...md:14`, `:129`, `:155`) **[D, not re-run]**.
- Quota does bind, so displaced points are not idle: share of 5-minute rows since 09-22 at 95% or more on weekly or 5-hour — next 23.4% (751/3214), next2 33.1% (1064/3214), next3 9.7% (312/3214), next4 9.6% (310/3214) **[M: `jq` + `awk` over `~/.claude/logs/account-utilization.jsonl`]**. Matches `a4-...md:31`.
- Credit-funded sessions run while the plan is at 100% weekly: "Normal sessions on Claude code web fine" with "This week 100% used" (#99597 body and 2026-10-05 comment) **[D, one report]**. Worth little here: all four accounts at the wall together in 0 of 3,214 timestamps since 09-22; at least one at the wall in 53.5% **[M: python over the same log]**. The router moves work instead.
- Option value: skipping is irreversible after 2026-10-08T06:59Z; an unused credit expires at no cost **[D: FAQ]**.

## 3 · Failure scenarios on our fleet if all four claim

| # | scenario | what it does here | detection | reversal | label |
|---|---|---|---|---|---|
| S1 | Claim flips the usage-credits toggle on (terms permit it) | Readout prints "extra-usage toggle is ON and not authorized ... a plan limit will now BILL" (`ROOT/bin/claude-accounts:6817-6821`). Router drops weekly target to 0.98 and halves the soft score above 90% weekly (`:1372`, `:2658`): up to 2 pp of routable headroom per account-week, up to 8 pp per account over 4 weeks, more than the 1.2-3.1 pp the credit yields | `credits_on` in the next 5-minute utilization row | Settings > Usage toggle off: "you can disable usage credits at any time" (<https://support.claude.com/en/articles/12429409-manage-usage-credits-for-paid-claude-plans>). Blocked if `can_toggle` is still false (S2) | **[I]**; router cost **[E]** upper bound |
| S2 | Toggle on and cannot be turned off | `can_toggle: false`, `can_purchase_credits: false`, header `overage-disabled-reason = org_level_disabled` on all four on 2026-08-19 (`ROOT/docs/research/breaking-the-ceiling-2026-08-19/B2-cloud-economics.md:143-156`); "cannot buy overage" restated 2026-10-04 (`ROOT/docs/research/concurrency-scale-2026-10-04/README.md:230`). The same flags that would block reversal also block purchase | same | support ticket | **[D]** state as of 08-19; **[I]** consequence |
| S3 | Toggle on plus a funded balance or dormant auto-reload | Only path to real dollars. Pro/Max usage credits are prepaid: "You'll then need to prepay"; auto-reload is opt-in (support article above). `next` and `next2` read `credits_ever_enabled: true` on 08-19 (`B2-cloud-economics.md:147-156`); one account carried $176.91 of spend on 2026-07-26 (`ROOT/accounts.json:17`, `ROOT/bin/claude-accounts:1576-1591`). `balance=null` on all four on 09-23 (memory note, section 9). These two are also the accounts most often at the wall (23.4%, 33.1%) | `credits_used > 0` prints the breach line (`ROOT/bin/claude-accounts:6797-6808`) | toggle off; remove auto-reload | **[D]** history; **[I]** exposure; live `spend.auto_reload` not read |
| S4 | Credit draw is reported as `extra_usage.used_credits` | False "NOT authorized" breach line on every claimed account for four weeks (`:6797-6808`, alert `:7133-7141`). Pressure to set `usage_credits_authorized=true`, which blinds the guard to real spend | readout | none short of expiry | **[I]**; the panel in #99597 shows a separate "Cloud session credits" ledger, which argues against |
| S5 | Credit not applied; cloud sessions keep drawing plan quota | Zero gain, same as today. Reports: #99166, #98888, #97021 (credit row vanished with over $100 left). Lane sessions are created by `POST /v1/sessions` (`ROOT/scripts/cloud-create-api.py:57`, `:411`); the FAQ names "web, desktop, CLI, or mobile" | credit balance does not fall after a lane fire | none needed | **[D]** reports; **[I]** eligibility of API-created sessions |
| S6 | Account action after claiming | One report: Max account closed "immediately after claiming and initiating a session" (#99852, 0 comments, unverified). Terms allow revocation for "fraud, abuse" and "Limit one Offer per account". Four claims by one operator are within the letter. Losing one account is 100 pp/week against 1.2-3.1 pp gained once at current supply (5.7 at the ceiling): break-even closure probability per account is 1.2-3.1% for a one-week loss (5.7% at the ceiling), 0.3-0.8% for a four-week loss (1.4% at the ceiling) | `auth` column | appeal | **[D]** report; **[E]** break-even; base rate unknown |
| S7 | Measurement contamination | Credit-funded fires add 0 to the weekly meter, so the 0.144 pp/fire estimator and the planned float-meter probe (`a4-...md:180`) read wrong until the credit is spent or expires | none | wait | **[I]** |
| S8 | New `limits[]` kind in the usage payload | Logged, left routable by design (`ROOT/bin/claude-accounts:1534-1556`) | log line | none needed | **[M]** code read |

- S1-S4 all require the toggle to turn on. With the toggle off, the fleet's dollar exposure after claiming equals today's **[I from FAQ]**.
- `-p` sessions bill Fable to usage credits "without asking" once credits are on (<https://code.claude.com/docs/en/model-config.md>, line 114 of the fetched file). Reachable only through S1 **[D]**.

## 4 · Claiming at zero dollar exposure — what the sources say

| control | source | status |
|---|---|---|
| Leave usage credits off; claim and use anyway | FAQ "No. You can claim and use your bonus credit without turning on usage credits" | **[D]**; consistent with #99597 panel and #97021 comment; not verified on our accounts |
| Toggle off after claim | "Yes, you can disable usage credits at any time through Settings > Usage" (usage-credits article); control surface listed at <https://code.claude.com/docs/en/costs.md> lines 93-105 | **[D]**; unverified here because `can_toggle` read false on 08-19 |
| No funds, auto-reload off | Prepay model and opt-in auto-reload (usage-credits article); "Auto-reload off" default shown in #99597 | **[D]**; live `spend.balance` and `spend.auto_reload` on our four not read today |
| Spend cap at zero | Article offers "Adjust limit" and "Set to unlimited"; no source states that $0 is accepted. #99597: with usage on, "Monthly spend limit reached ... Credits can't be used until you do" while the panel read "No spend limit" | **Unverified**; the billing UI around this promo misreports |
| No payment method on file | Not available: a paid individual subscription bills a card. Only app-store subscribers have none on file with Anthropic (usage-credits article, mobile note) | **[I]**; how our four are billed was not read |
| Fleet-side tripwire | `credits_on` and `credits_used` logged every 5 minutes: false and 0.0 in all 45,406 rows (next 11,365 · next2 11,365 · next3 11,313 · next4 11,363) | **[M: `jq 'select(has("credits_on"))'` + `sort | uniq -c`]** |
| Standing procedure | "after any claim, run `claude-accounts`. A warning on that account means the toggle turned on and must go back off" (memory note, section 9; index at `ROOT/.claude/rules/agent-operating-lessons-situational.md:230`) | **[D]**; the operator already files this as an open item, not a forbidden act |

## 5 · Operator time and policy exception against the value

| item | size | label |
|---|---|---|
| Operator time | about 10 minutes: 4 claim-page opens, 1 readout; `next3` needs a login it needs anyway (`auth: login-required`, last row 2026-10-07T04:00Z) | **[E: step count]**, **[M]** auth state |
| Policy exception | none on the documented path; `spend.usage_credits_authorized` stays false (`ROOT/accounts.json:19-20`) | **[D]** |
| Policy exception if S1 fires | one toggle-off per affected account, or four weeks of warning lines | **[I]** |
| Value, current supply | 6.0-10.4 pp, $2.8-$4.8 at replacement cost | **[E]** |
| Value, ceiling | 17.7-22.9 pp, $8.1-$10.5 | **[E]** |
| Break-even operator rate | $17-$29/hour at current supply; $49-$63/hour at the ceiling | **[E: value / (10/60 h)]** |

- In replacement-cost dollars the claim does not repay ten minutes at a professional rate.
- In quota it does: these accounts cannot buy overage (`can_purchase_credits=false`), and the next unit of quota is a fifth account at $200/month.

## 6 · The single fact that flips the answer

- **"Claiming leaves `extra_usage.is_enabled` false on our accounts."**
- True (FAQ, two user reports): exposure is unchanged, the claim is a free option, claim.
- False: S1 costs more routable headroom than the credit yields, S3 opens on `next` and `next2`, and reversal may be blocked by S2. Skip.
- Cost to measure: one canary claim on `next4` (4% weekly, `credits_ever_enabled: false` on 08-19) and one utilization row, 5 minutes.
- Second-order fact, bounded at "no gain": whether `POST /v1/sessions` fires draw the credit (S5). Read after the next lane fire on the canary: credit balance down, weekly meter flat.

## 7 · Attack on my own case

- **The value is immaterial.** 0.36-0.62% of four-week fleet quota at current supply; the $1,000 face value is $3-$11 of quota at what the operator pays.
- **Nothing to spend it on.** 1 open row, 0 eligible; 7-day fire rate (1.43/d) is below the 28-day rate (2.46/d) **[M]**. Realised value is trending to the low row of the table.
- **The legal text outranks the FAQ.** The terms still carry the authorization; the FAQ is "Updated over a week ago" and can change without notice ("Anthropic may modify, suspend, or terminate this Offer at any time without notice").
- **The billing surface around this promo is unreliable.** Five open reports of credit not applied or vanished (#97021, #98888, #99166, #99337, #99597); one closure report (#99852). The zero-exposure rule exists so the fleet does not depend on that surface being right.
- **The fleet's one dollar incident is unexplained.** $176.91 on 2026-07-26 with the toggle reading off (`ROOT/accounts.json:17`). The mechanism was never recorded, so "prepaid, no overage path" is documented for the product and unproven for these accounts.
- **Toggle evidence is n=2 anecdotes plus a FAQ.** Neither user had `can_toggle: false` or `org_level_disabled`; our accounts are in a different state.
- **Reply:** every attack except S6 is bounded at "no gain" while the toggle stays off, and the canary measures that in 5 minutes. S6 has one unverified report and no base rate; the lane has run 757 declared cloud sessions on these accounts since August with no closure **[M: `.decl` count]**.

## 8 · Alternatives considered

| option | verdict | reason |
|---|---|---|
| Claim all four at once | rejected | spends the flip fact on `next`/`next2`, the two accounts with billing history and the most wall time |
| Claim `next4` and `next3` only (`credits_ever_enabled: false`) | fallback if the operator wants no contact with S3 | keeps 34 of the 69 trailing-28-day fires (49%) on credited accounts **[M]** |
| Skip | defensible | zero variance; costs $3-$11 of quota |
| Flip `usage_credits_authorized` to true and claim | rejected | not needed on the documented path; disarms the breach line for real spend |
| Read `spend.*` live before deciding | not run | needs the account token and an authenticated GET, outside this run's bounds |
| Raise cloud supply to use the full $1,000 | out of scope | classifier work (`ROOT/docs/research/cloud-lane-redesign-2026-09-10.md:55-62`); cannot land and pay back inside 29 days on evidence here |

## 9 · Operator steps, described only (none run)

1. `next4`: open `https://claude.ai/code/claim-credit` in that account's browser profile, or run `/claim-credit` in its CLI (`"claim-credit":"action"` present in the 2.1.284 binary, 3 hits **[M: byte search of `~/.claude-284/.../claude`]**; absent in 2.1.282 per #96861). The page returns 403 to `curl` **[M]**.
2. Wait one utilization row (5 minutes). Run `claude-accounts`. A toggle warning on `next4` means stop, turn it off at Settings > Usage, skip the other three.
3. Clean: on `next` and `next2` read Settings > Usage first (balance, auto-reload), then claim. `next3` after its login.
4. After the next lane fire on a claimed account, read "Cloud session credits" in Settings > Usage. Unchanged balance means S5.
- Memory note with the raw-field recipe: `/Users/chrisren/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/cloud-session-cost-exposure.md` (state 09-23: credits off, $0.00, `balance=null`, `omelette_promotional` null on all four).

## 10 · Unverified, and blockers

- Live `extra_usage.is_enabled`, `spend.balance`, `spend.auto_reload`, `spend.can_toggle`, `can_purchase_credits` and promo status per account. Last readings 08-19, 09-10, 09-23; they disagree on the disabled reason (`org_level_disabled` against `user_disabled: true`, `a4-...md:57`).
- Whether the claim flow flips the toggle on accounts in the `org_level_disabled` state.
- Whether sessions created by `POST /v1/sessions` draw the credit.
- Whether credit draw surfaces in `extra_usage.used_credits` (S4).
- Whether credit-funded sessions run on the 5-minute cache lifetime that applies "once you're drawing on usage credits" (<https://code.claude.com/docs/en/costs.md> line 359), which would raise per-fire cost against the credit.
- Whether any account was auto-granted the credit ("Some accounts may be automatically granted credits", FAQ).
- How the four subscriptions are billed; what produced the $176.91.
- Base rate of account action after claiming (S6).
- C1's 0.144 pp/fire and C2's per-fire cost were not re-measured; every value figure above inherits them.
- Blocker: `next3` is `login-required`.

## 11 · Receipts

- Scratch copies in `/tmp/decisions-eval/`: `_post.html`/`_post.txt` (blog), `_terms.txt` (promotional terms), `_promo_support.txt` (offer FAQ), `_extra.txt` (usage-credits article), `_credterms.txt` (supplemental credit terms), `_costs.md`, `_errors.md`, `_model.md`, `_web.md`, `_commands.md`, `_consumer.html`.
- Prior claims re-checked today: blog credit paragraph (matches `a4-...md:43`); terms authorization sentence (matches `a4-...md:44`); `spend.usage_credits_authorized=false` and `frontier.credits_authorized=false` (`jq` on `~/.claude/accounts.json`, a symlink to `/Users/chrisren/Development/claude-infrastructure/accounts.json`); `credits_on=false`, `credits_used=0.0` on every row; wall-time shares; fire counts (25 in 14 d against a4's 26).
- Issues read with `gh api` GET: anthropics/claude-code #96861, #97021, #97160, #97567, #97626, #98014, #98060, #98183, #98888, #99166, #99337, #99568, #99597, #99852. Staff reply (COLLABORATOR `dicksontsai`, 2026-09-29) on #97160, #98014, #98183 points to the offer FAQ and confirms Projects are excluded.
