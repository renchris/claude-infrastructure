# D2 — Our usage-credit policy, what depends on it, and what the $250 is worth

Read 2026-10-07T04:10Z (Oct 6 23:10 CDT). Repo `/Users/chrisren/Development/.worktrees/wt-cc-205652-27362` (paths relative to it), tip `03b7e413c`. Nothing claimed, toggled, fired or logged in. Scratch: `/tmp/decisions-eval/d2-web/`.

Labels: **[M]** measured here (command named) · **[D]** documented (file:line / URL) · **[E]** estimated (method named) · **[I]** inferred.

## 0 · Headline

- **The prior verdict's main premise does not hold as stated.** The offer's own Help Center page says: "Do I need to turn on usage credits? No. You can claim and use your bonus credit without turning on usage credits ... You're only charged for usage credits if you've turned them on and you go past your plan's usage limits." **[M: `curl` HTTP 200, https://support.claude.com/en/articles/17152539-cloud-sessions-bonus-credit-promotion, saved `d2-web/promo-help.txt` L31-34]**. The generic promo terms (dated May 19, 2026) still carry "you authorize Anthropic to enable Usage Credit on your account if it is not already enabled" **[M: `curl` HTTP 200, https://www.anthropic.com/legal/promotion-credit-terms]**. Two vendor documents disagree; the outcome on our accounts is unverified but our own instrument detects a flip within one sweep (section 3).
- **Draw order is credit-first, per the same page:** "While you have credit remaining, cloud session usage is paid for by the credit and doesn't count toward your plan's usage limits." (L37) **[M]**. One user report says the opposite (#99166, unverified).
- **Deadline is later than assumed:** "Claim by October 7 at 11:59 PM PT" = 2026-10-08T06:59Z, about 27 h from this read; "Credits expire November 4 at 11:59 PM PT" (L10-11) **[M]**.
- **Value is small:** $250 = 1.8-5.7 weekly points of one account, once **[E]**; at the lane's measured rate only 26-58% of the fleet's $1,000 would be used before expiry **[E]**.
- **Our guard is an alarm, not a gate:** `spend.usage_credits_authorized` has three readers, all renderers; nothing refuses a fire or changes routing on it **[M: grep]**.

## 1 · Why the fleet forbids usage credits

| date | event | evidence |
|---|---|---|
| 2026-07-19 | Live sessions killed by "You've hit your monthly spend limit" (a billing-plane cap with no reset); poller taught to open a class-B decision instead of dropping it | `scripts/limit-recover/lr-reset-poller.sh:33-37`, `:1706-1709` **[D]** |
| 2026-07-26 | An account read `credits_on: false` with `credits_used: 17691` = "$176.91 spent" in the web Usage panel; the alert was keyed on the toggle so the money was invisible, and the raw field is cents | commit `7edc3b5b2` body; `bin/claude-accounts:1576-1591` **[D]** |
| 2026-08-07 | Primary source settles that cloud is subscription-billed and shares the pool; same day backlog row `e9245cc24dff` filed: "STANDING COST GUARD: keep the 'usage credits' toggle OFF on all four accounts — with it off, hitting a plan limit STOPS the session instead of billing pay-as-you-go overage; cloud sessions share the same pool, so firing more of them raises the chance of hitting it" | `docs/plans/CONCURRENCY_PROGRAM.md:725-736`; **[M: `jq` over `~/.claude/autonomy/backlog.jsonl`, add event 2026-08-07T09:47:27Z, source session `ec05d411`]** |
| 2026-08-09 | Consolidation finds the guard has "zero enforcement surface"; SSOT field `accounts.json:spend.usage_credits_authorized=false` lands | `docs/plans/backlog-consolidation-2026-08-09/OUT-accounts.md:26,104`; commit `a9b5b325a`; `accounts.json:17-20` **[D]** |
| 2026-08-10 | Same flag cited as the policy that keeps per-token backends unwired | `docs/plans/MULTI_PROVIDER_PLANS.md:93,107-110,215-216`; `bin/claude-accounts:7700-7701` **[D]** |
| 2026-08-15 | Readout gains a toggle-ON warning that fires before money moves; row closed 2026-08-16 | commit `313d83050`; `bin/claude-accounts:6809-6821`; `docs/plans/BACKLOG_SELF_DRAINING_2026-08-12.md:2265-2274` **[D]** |
| 2026-09-23 | Memory note: "The ONLY way it can cost dollars is usage credits"; credit listed as the operator's open item; "Unknown: whether claiming it flips the usage-credits toggle" | `~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/cloud-session-cost-exposure.md`; `.claude/rules/agent-operating-lessons-situational.md:230` **[D]** |

- **Hard ruling or default?** Both layers exist. The value is recorded as "the operator's standing answer to 'may this fleet spend beyond the four Max subscriptions'" with the protocol "flip to true only on an explicit operator decision, and say why in the commit" (`accounts.json:17,20`) **[M: `jq` key/boolean read; prose notes are not credentials]**. The code default when the block is absent is also unauthorized (commit `313d83050`: "a missing standing answer reads as unauthorized") **[D]**. No verbatim operator sentence was found: the row was filed by an agent session whose transcript is no longer on disk **[M: `ls ~/.claude*/projects/*/ec05d411*.jsonl` no match]**.
- **What the ruling forbids, read literally:** spend beyond the subscriptions and the toggle being on. A free credit that leaves the toggle off is outside both **[I]**.
- `frontier.credits_authorized=false` is a different gate: it stops scoring Fable past a window deadline (`bin/claude-accounts:4961,7190`; `accounts.json:32,37`) **[D]**. Not touched by this decision.

## 2 · What reads the flag or the account's credit state

| reader | site | effect | kind |
|---|---|---|---|
| `spend.usage_credits_authorized` | `bin/claude-accounts:6797-6808` | nonzero `credits_used` renders as "NOT authorized" breach, or as "authorized" | render |
| same | `:6817-6821` | toggle ON at zero spend renders "a plan limit will now BILL instead of stopping the session" | render |
| same | `:7700-7701` | provider section text | render |
| `credits_on` | `:1372` `weekly_headroom` | routable weekly ceiling drops from 1.00 to 0.98 for that account | routing |
| `credits_on` | `:2658` `_soft` CF | score halved once weekly >= 90% | routing |
| `credits_on` / spend | `:7133-7142` | table alert | render |
| recovery floors | `:4665-4668` | the 0.98 target is deliberately not applied | routing |
| `wire.overage_status` | `:1331` | captured, **zero consumers** | none |
| utilization log | `:5550` | `credits_on`, `credits_used` appended each sweep | record |
| cache TTL hook | `hooks/cache-expiry-warning.sh:8-11` | assumes the 1 h TTL because credits have never been drawn | assumption |
| `cc-value` | `bin/cc-value:41-43` | spend proxied by quota | assumption |
| limit-recover | `scripts/limit-recover/lr_predicate.py:88-91`; `lr-fire-resume.sh:719,1246-1249`; `lr-preseed-env.sh:121` | detection needs the limit-stop api-error record; an overage notice is dismissed with Enter; the upsell is suppressed at source | assumption |
| cloud fire gate | `scripts/handoff-fire.sh:8619-8636` | prices a cloud fire in account headroom; refuses when no account is routable | gate, does not read credits |

**[M: `grep -rn` over `bin scripts hooks docs/plans CLAUDE.global.md`; files with any credit read: `bin/claude-accounts`, `bin/cc-value`, `scripts/desk-strand-replay.py`, `scripts/limit-recover/lr-fire-resume.sh`, `hooks/cache-expiry-warning.sh`]**

- **No guard excludes or rotates away from an account whose toggle is on.** Commit `313d83050` measured it: the readout "still routes the desk to that account"; the fix added a warning line only **[D]**.
- **If the toggle were on and funds available, a limit hit would not stop the session, and our recovery would not see it.** Vendor: usage credits let you "continue ... after reaching their included usage limits" (https://support.claude.com/en/articles/12429409-extra-usage-for-paid-claude-plans) **[M: curl]**; binary 2.1.284 carries `isInOverageMode` and "Now using usage credits" **[M: `strings`, 5 hits]**; limit-recover parks only on the stop record **[D]**. So: no park, no rotation, session keeps running on paid usage **[I]**.
- Other documented behaviour changes while drawing usage credits: cache lifetime falls from one hour to five minutes (`costs.md:359`); headless `-p` Fable requests "bill ... without asking" (`model-config.md:114`); unattended interactive panes get a consent prompt that ends the turn unanswered (`errors.md:737-745`) **[M: curl of code.claude.com/docs/en/{costs,model-config,errors}.md]**.
- **Live state:** `credits_on=false`, `credits_used=0` on every logged row: next 11,365 · next2 11,365 · next3 11,313 · next4 11,363; latest sweep 2026-10-07T04:00:46Z **[M: `jq` over `~/.claude/logs/account-utilization.jsonl`]**.

## 3 · What claiming would do to that tooling

| outcome after claim | tooling effect | how we would know |
|---|---|---|
| Toggle stays off (Help Center reading) | none; limit hits still stop; guard untouched | `credits_on` stays false in the next 5-minute sweep row |
| Toggle flips on (terms clause exercised) | readout prints the toggle warning on each claimed account; router gives up 2 weekly points of routable ceiling per account-week and halves score above 90%; a limit hit no longer stops if funds exist | `claude-accounts` warning line (`:6817-6821`); `credits_on=true` in the log |
| Credit consumption counted as `extra_usage.used_credits` | breach line "NOT authorized" on each account while the flag is false (`:6797-6808`); flipping the flag to silence it also silences real-dollar breaches, because the flag is one fleet-wide boolean | unknown until a credit-funded fire runs **[I]** |

- Dollar exposure with the toggle on is bounded by funds: Pro/Max credits are prepaid ("You'll then need to prepay"; auto-reload optional) **[M: curl, support article 12429409]**. Whether any of the four accounts holds a balance or auto-reload is not readable from our logs; on 2026-09-23 `balance=null` on all four (memory note) **[D]**.
- Earlier reads disagree on whether the toggle can be turned on at all: `can_toggle: false`, `org_level_disabled` (2026-08-19, `docs/research/breaking-the-ceiling-2026-08-19/B2-cloud-economics.md:28-29,131-132,155`); `user_disabled: true` (2026-09-10, `docs/research/cloud-lane-redesign-2026-09-10/C1-quota-pool.md:81`) **[D]**. Not re-read.

## 4 · Value, re-derived

Per-fire inputs **[D]**: $5.63 mean per cloud fire, list-price equivalence (`C2-cost-per-landed-row.md:11-16,86`); control-plane `cost_usd` runs 1.118x that (`C2:110-114`); post-gate strata mix $7.29 (`a4-economics-and-live-state.md:115`); 0.144 weekly points per fire (`C1-quota-pool.md:52`).

| method | weekly points per $250 | basis |
|---|---|---|
| (a) fire-based, prior method | **4.4-5.7** | $250 / ($6.30-$8.15 per fire) = 30.7-39.7 fires x 0.144 **[E]**; reproduces K10 |
| (b) list-price exchange rate | **3.0-3.4** | $73.50 list-equivalent per weekly point (`docs/research/usage-telemetry-100p-2026-08-16/exchange-rate.md:134`), with and without the 1.118 factor **[E]** |
| (c) token coefficients on C2's per-fire tokens | **1.8-2.3** | 33,938 output x 1.2823 pp/Mtok + 142,066 cache-write x 0.1054 = 0.0585 pp per fire (`exchange-rate.md:125-126`, `C2:86`) x 30.7-39.7 fires **[E]** |

- **Range: 1.8-5.7 weekly points of one account, once.** The prior 4.4-5.7 is the top of it. Fleet: 7-23 points against 1,600 account-week points over four weeks = 0.45-1.4% **[E]**.
- In subscription dollars: one account-week costs about $46 ($200/mo; fleet "$800/mo", `exchange-rate.md:134`), so $250 of credit replaces about $0.83-$2.62 of subscription per account **[E]**.
- All three exchange rates were fitted on Opus 5 in August-September; the current model's price was not checked.

### Would it be consumed? (credit-first, as the Help Center states)

| quantity | value | source |
|---|---|---|
| Fire rate | 1.43/day (7 d, 10 fires) · 1.79/day (14 d, 25) · 2.46/day (28 d, 69) | **[M: parse of `~/.claude/autonomy/cloud/*.decl` `declared_at`]** |
| Days to expiry | 29.2 | **[E: Nov 4 23:59 PT = 2026-11-05T07:59Z]** |
| Fires before expiry at those rates | 41-71 | **[E]** |
| Dollars drawn | $258-$579 of $1,000 = **26-58%** | **[E: x $6.30-$8.15]** |
| Per account (14 d split next 7, next2 6, next3 4, next4 8) | $91-$118 · $78-$101 · $52-$68 · $104-$135 of $250 each | **[E]** |
| Quota actually relieved | 2.4-10.2 weekly points fleet-wide = 0.15-0.64% of four weeks | **[E: 41-71 fires x 0.0585-0.144]** |
| Rate needed to use it all | 4.2-5.5 fires/day = 1.7-3.8x measured | **[E: 123-159 fires / 29 d]** |
| Eligible supply now | 0 open rows (120 blocked · 1 claimed, venue local · 4,120 done); 10 cloud-eligible rows, all blocked | **[M: `bin/cc-backlog list --all --json` rc 0; `bin/cc-eligible sweep --json` joined on id]** |

- Accounts do reach the wall, so a point has real marginal value: share of 5-minute rows since 09-22 with a wire-rejected window: next 17.9% · next2 31.1% · next3 5.2% · next4 3.8% **[M: `python3` over `account-utilization.jsonl`, 3,214 rows each]**.
- **The gate blocks the credit when it is worth most.** The cloud gate refuses when no account is routable (`handoff-fire.sh:8630-8636`); a credit-funded fire on an exhausted account would need the per-fire override `CC_FIRE_CLOUD_GATE=off` named at `:8634` **[D]**. Session create is not gated by weekly quota (commit `a9b5b325a`: "an account at 100% weekly created cloud sessions normally") **[D]**.
- Unverified: whether sessions created by our private path (`POST /v1/sessions` with the account's OAuth identity, `C1-quota-pool.md:19-20`) count as "cloud sessions from web, desktop, CLI, or mobile" (Help Center L30). The page excludes API-key authentication, which we do not use **[I]**.

## 5 · Non-backlog uses in other repos (from our docs only)

- A cloud session's source set is one repository and the lane defaults to `renchris/claude-infrastructure` (`docs/plans/CLOUD_BACKLOG_PIPELINE.md:1399-1401`) **[D]**.
- Cross-repo rows are refused: `ineligible-cross-repo` = 38 of 121 non-done rows **[M: sweep `counts`]**. `doc_classifier` and `reso-management-app` are dispatchable locally only (`scripts/dispatch-projects.conf`) **[D]**.
- `claude --cloud "task"` from another repo was measured and rejected on 2026-08-10: the bundle gives `sources: []` and the push is 403 (`scripts/cloud-create-api.py:11-26`) **[D]**.
- Projects, Routines, Remote Control, chat and Cowork are excluded by the offer (Help Center L40-43) **[M]**.
- Our docs name no other cloud use. Nothing documented absorbs the unused 42-74%.

## 6 · Blockers and public reports

- `next3` reads `login-required` at 04:00:46Z; it cannot claim without a login **[M: latest utilization row]**.
- Claiming is per account, signed in as that account, via `/claim-credit`, the app banner, or the claim page; "Some accounts may be automatically granted credits" (Help Center L18-22) **[M]**. `"claim-credit":"action"` exists in 2.1.284 **[M: `strings`, 2 hits]**.
- Open issues on `anthropics/claude-code`, single-user and unverified **[M: `gh api` GET]**: #99852 (10-06) Max account closed right after claiming and starting a cloud session; #99166 (10-03) cloud session "using my regular local usage tokens"; #99597 (10-05) credit unusable at the weekly limit in a routine-triggered session, normal cloud sessions fine; #98630 (10-01) balance still zero after completing the steps.

## 7 · Alternatives

| option | what the evidence says |
|---|---|
| Skip | Forgoes at most 0.15-0.64% of four weeks' fleet quota at current rates; zero operator action; zero new state |
| Claim, leave `usage_credits_authorized=false`, read `credits_on` in the next sweep, switch the toggle off if it flipped | Permitted by the ruling's literal scope if the toggle stays off; the existing 5-minute sweep is the check; 3 accounts claimable now, `next3` after login |
| Claim and flip the flag to true | Not supported: the flag is fleet-wide and binary, so it would mute the real-dollar breach line for four weeks |
| Claim and raise cloud volume to use it all | Needs 1.7-3.8x the fire rate with 0 dispatchable rows; reach is capped at 12.9-14.4% of rows (`a4:127-128`) |

## 8 · Adversarial pass

- "The Help Center page could be wrong for our accounts." The generic terms grant the authorization, so a flip is possible. It is detectable and reversible, not preventable.
- "Credit-first could be wrong." #99166 says so. If the credit is overflow-only, pipeline consumption falls to about zero without the gate override, and the decision is moot rather than harmful.
- "0.144 points per fire overstates the draw." Method (c) gives 0.0585; the range above carries both.
- "The lane rate may rise." The 28-day rate (2.46/day) is the highest window and is already the upper bound used.
- "Promo consumption may trip the breach line." Unknown; listed in section 3.
- Ruled out as evidence: B2's single-fire meter step (refuted by B2-VERIFY, `a4:28`); the `can_toggle` reads as current state (August/September, conflicting).

## 9 · Gaps

1. Whether claiming flips `extra_usage.is_enabled` on a Max account. Only a claim shows it.
2. Whether credit consumption increments `extra_usage.used_credits`.
3. Whether sessions created through `POST /v1/sessions` draw the credit.
4. Balance, payment method and auto-reload state per account (not in our logs).
5. Whether any account was auto-granted the credit since 2026-09-23.
6. Current model pricing against the August exchange rates.
7. No verbatim operator statement of the standing guard survives on disk.
