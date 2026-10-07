# D2 - Cloud credit: what claiming authorizes and exposes (primary sources)

Read 2026-10-07T03:55-04:10Z (2026-10-06 ~23:00 CDT). Nothing claimed, toggled, logged in, or called with a token.
Labels: **M** measured (command named) - **D** documented (URL) - **I** inferred - **E** estimated (method named).
Saved copies of every fetched page: `/tmp/decisions-eval/d2-*.{html,txt,md}`.

## Headline

- The offer has its own help-center page the prior investigation did not read: `https://support.claude.com/en/articles/17152539-cloud-sessions-bonus-credit-promotion`. It answers the Usage Credit question directly: **"Do I need to turn on usage credits? No. You can claim and use your bonus credit without turning on usage credits."** (D, `d2-promo-article.txt:25-26`).
- The generic legal terms still carry a blanket permission: **"you authorize Anthropic to enable Usage Credit on your account if it is not already enabled"** (D, `https://www.anthropic.com/legal/promotion-credit-terms`, `d2-terms.txt:13`). That clause is shared by every promo; the cloud offer's own page says the toggle is not needed.
- Draw order is **credit first, plan quota second, no bill third** for cloud sessions (D, `d2-promo-article.txt:29`).
- Usage Credit on Pro/Max is a **prepaid** wallet: a toggle that is on with no purchased funds and no auto-reload cannot charge the card (D, `d2-extra-usage.txt:45-46`; `d2-fable-credit.txt:45`).
- All four accounts read `eligible: true, claimed: false` in the CLI's local promo cache; next3's server-pushed banner already says **"You've been granted a $250 bonus credit"** while its toggle stayed off (M, below).
- Deadline: **Oct 7 23:59 PT = 2026-10-08T06:59Z = Oct 8 01:59 CDT**, 26.9 h after 2026-10-07T04:07Z (D `d2-promo-article.txt:9`; M `python3 datetime`).

## 1 - Verbatim: what claiming authorizes

| # | Text | Source | Label |
|---|---|---|---|
| 1 | "provides you with promotional usage credit ... redeemable toward Usage Credit on your Claude subscription ... Offer may be further limited to specific products, features, or seats as stated in the offer." | promotion-credit-terms, effective May 19, 2026, `d2-terms.txt:12` | D |
| 2 | "By participating in this Offer, you also agree to the Usage Credit Terms and/or the Supplemental Credit Terms where applicable, and you authorize Anthropic to enable Usage Credit on your account if it is not already enabled." | same, `d2-terms.txt:13` | D |
| 3 | "Credit applies only toward Usage Credit charges on your Claude subscription - not subscription fees, seat charges, or taxes. Credit has no cash value, is not transferable, and will be applied automatically before your payment method is charged." | same, `d2-terms.txt:18` | D |
| 4 | "Limit one Offer per account unless otherwise stated" | same, `d2-terms.txt:15` | D |
| 5 | "Credit expires on the date stated in the offer ... Unless otherwise stated, Credit is forfeited if you cancel your subscription or seat, downgrade to a free plan, or if your account or user is suspended or terminated." | same, `d2-terms.txt:20` | D |
| 6 | "Anthropic may modify, suspend, or terminate this Offer at any time without notice, and may revoke Credit or disqualify participants where it determines there has been fraud, abuse, or violation of these terms." | same, `d2-terms.txt:21` | D |
| 7 | "Do I need to turn on usage credits? No. You can claim and use your bonus credit without turning on usage credits. After the credit runs out, cloud sessions count toward your plan's usage limits. You're only charged for usage credits if you've turned them on and you go past your plan's usage limits." | support article 17152539, `d2-promo-article.txt:25-26` | D |
| 8 | "Exception: On Pro plans, selecting Fable requires usage credits to be turned on with a balance." (Pro only; Max includes Fable, `d2-fable-article.txt:30`) | `d2-promo-article.txt:27,30` | D |
| 9 | Contrast, same legal terms, different promo: "Claiming turns on usage credits for your account so they're ready to use." / "Claiming them turns on usage credits for your account, but you're only charged if you buy additional usage credits later." | Fable 5 one-time credits, `https://support.claude.com/en/articles/15862783`, `d2-fable-credit.txt:24,45` | D |

- Reading of rows 2, 7, 9: the legal clause is a permission, not an action; where a promo does flip the toggle the help page says so (row 9), and the cloud page says the opposite (row 7). **I**: claiming does not turn Usage Credit on. Not observed directly: the claim page returned 403 to curl (M: `curl -w %{http_code} https://claude.ai/code/claim-credit`).
- What the claim does **not** authorize under any reading: a purchase, auto-reload, or a payment-method charge. Auto-reload is a separate opt-in ("If Customer activates the Balance Maintenance Service, Customer authorizes Anthropic to charge the payment method", `https://www.anthropic.com/legal/credit-terms`, `d2-credit-terms.txt:18`) (D).

## 2 - Draw order, scope, zero balance, expiry

| Question | Answer | Source | Label |
|---|---|---|---|
| Before or after plan limits? | **Before.** "While you have credit remaining, cloud session usage is paid for by the credit and doesn't count toward your plan's usage limits." | `d2-promo-article.txt:29` | D |
| Works while the account is at its plan limit? | Yes: the server-pushed limit-wall line reads "While you wait, start a new cloud session by claiming a $250 credit" | M: `tengu_swift_lynx.limitWall` in `~/.claude-next/.claude.json` `cachedGrowthBookFeatures` | M |
| Which usage draws it? | Cloud sessions only, "from web, desktop, CLI, or mobile". Not covered: "Projects and Routines", "Remote control sessions", "Chat and Cowork sessions", "Any Claude usage outside of cloud sessions" | `d2-promo-article.txt:24,31-35` | D |
| Balance hits zero | "After the credit runs out, cloud sessions count toward your plan's usage limits the same way local sessions do. There's no separate charge for the cloud container." Usage continues on plan quota; no bill. | `d2-promo-article.txt:29` | D |
| Expiry | "Credits expire November 4 at 11:59 PM PT" = 2026-11-05T07:59Z (PST; DST ends Sun Nov 1). Blog: "After it's used or expires, your plan's regular usage applies." | `d2-promo-article.txt:10`; `https://claude.dev/blog/claude-code-in-the-cloud/` `d2-blog.txt:27` | D |
| Where the balance shows | "You can see your remaining balance in the usage menu." | `d2-promo-article.txt:24` | D |
| Rate the credit is debited at | Not stated for this offer. Usage credits bill "at standard API pricing rates" (`d2-extra-usage.txt:34`) | - | I |

## 3 - Usage Credit mechanics (the thing `usage_credits_authorized=false` guards)

| Item | Fact | Source | Label |
|---|---|---|---|
| Funding model | Prepaid: "You'll then need to prepay to cover usage beyond your plan limits. Click 'Add funds'". Continue past a limit only "If usage credits are enabled and you have funds available". | `https://support.claude.com/en/articles/12429409` `d2-extra-usage.txt:33,45` | D |
| Auto-reload | Opt-in: "You can also enable auto-reload to automatically make a purchase when your balance falls below a threshold you set". Daily redemption limit $2,000. | `d2-extra-usage.txt:46,48` | D |
| Spend cap | Monthly spend limit via "Adjust limit"; "Set to unlimited" is selectable. With no limit set, `/usage` "shows `Unlimited`". Default not stated in words; the no-limit state exists. | `d2-extra-usage.txt:44`; `https://code.claude.com/docs/en/costs` `d2-doc-costs.md:72` | D (state) / I (default = none) |
| Switch off again | "Yes, you can disable usage credits at any time through Settings > Usage." Toggling is not among the forfeiture triggers (row 5); "If you downgrade your plan, you keep your credit." | `d2-extra-usage.txt:79`; `d2-promo-article.txt:38` | D / I (no forfeiture on toggle-off) |
| Promo spent first | "Your free promotional credits are spent first, then your other credits, including auto-reload if you have it turned on." (Fable promo precedent) | `d2-fable-credit.txt:40` | D |
| What a toggle that is ON unlocks beyond plan limits | Fable past the Max 50% weekly cap ("keep using Fable models with usage credits"); in `-p`/Agent SDK "Claude Code never asks for consent ... bills it without asking"; fast mode "draws directly from usage credits, even if you have remaining usage on your plan"; ultrareview after 3 free runs; Sonnet 4.6 `[1m]`; routines and Project threads past the limit | `d2-fable-article.txt:30`; `d2-llms-full.txt:92851, 84263, 50889, 93451, 44762, 13809` | D |
| Cache TTL | Drops from 1 h to 5 min "once you're drawing on usage credits" | `d2-doc-costs.md:359` | D |

- Dollar exposure needs **toggle on AND (purchased balance OR auto-reload on)**. The cloud credit is restricted to cloud sessions, so it is not a balance the unlocked features above can spend (I from `d2-promo-article.txt:35`).

## 4 - Eligibility and deadline

| Item | Fact | Source | Label |
|---|---|---|---|
| Unit | "One credit per account. It can't be combined with other offers." / "Limit one Offer per account" | `d2-promo-article.txt:37`; `d2-terms.txt:15` | D |
| Who | "Individual Pro and Max subscribers who had an active subscription when the promotion started, September 23, 2026 at 2:00pm PDT." Sign-in with claude.ai account required. | `d2-promo-article.txt:12-13` | D |
| Excluded | "Team and Enterprise plans, free trials, and accounts with a past-due payment." | `d2-promo-article.txt:14` | D |
| Amount | Max $250 (one tier for Max 5x and 20x; no 20x uplift stated) | `d2-promo-article.txt:7` | D |
| Claim cutoff | "Claim by October 7 at 11:59 PM PT" | `d2-promo-article.txt:9` | D |
| Auto-grant | "Some accounts may be automatically granted credits. Otherwise, you can claim" via desktop/IDE banner, `/claim-credit`, or the claim URL | `d2-promo-article.txt:16-19` | D |
| Use prerequisite | GitHub connected (GitHub App or `/web-setup`) | `d2-promo-article.txt:21` | D |
| One person, four accounts | No text addresses it. The four are distinct accounts, orgs and emails (M: hashed `oauthAccount.{accountUuid,organizationUuid,emailAddress}` across the four `.claude.json`, 4 distinct each). Consumer Terms (effective Oct 8, 2025) contain no "multiple accounts"/"one account" language (M: grep of `d2-consumer-terms.txt`). CLI carries the refusal string "This offer was already claimed in another organization." (M: binary strings, 2.1.284). Residual: the discretionary revoke clause (row 6). | - | M / I |

## 5 - Measured local state (read-only file reads)

| acct | tier / billing | `hasExtraUsageEnabled` | `credits_on` true rows since 09-23 | promo cache `eligible / claimed` (checkedAt) | server banner (feature cache fetched) | auth now |
|---|---|---|---|---|---|---|
| next | max_20x / stripe | false | 0 of 3,024 | true / false (2026-09-29T00:48Z) | v1 "Claim a $250 bonus credit for cloud sessions, on top of your plan limits" (10-07T04:02Z) | ok |
| next2 | max_20x / stripe | false | 0 of 3,024 | true / false (2026-09-29T06:17Z) | v1 "Claim ..." (10-07T02:52Z) | ok |
| next3 | max_20x / stripe | false | 0 of 3,024 | true / false (2026-09-28T23:25Z) | **v2 "You've been granted a $250 bonus credit for cloud sessions, on top of your plan limits"**, button "Get started" (10-06T16:42Z) | login-required; last ok 10-06T23:12Z |
| next4 | max_20x / stripe | false | 0 of 3,024 | true / false (2026-10-04T09:07Z) | v1 "Claim ..." (10-07T03:59Z) | ok |

- Commands (M): `python3 json.load` over `~/.claude-{next,secondary,tertiary,quaternary}/.claude.json` keys `promoStartupStatusCache`, `cachedGrowthBookFeatures.tengu_swift_lynx`, `cachedGrowthBookFeaturesAt`, `oauthAccount`; row counts from `~/.claude/logs/account-utilization.jsonl` filtered `ts >= 2026-09-23`; `credits_used > 0` rows: 0 on all four.
- Promo endpoint is `/v1/code/promo/cloud_credit`, separate from `extra_usage` (M: same cache).
- next3: banner said "granted" at 10-06T16:42Z; its `credits_on` stayed false through its last good read at 23:12Z, 6.5 h later (M). **I**: a grant does not flip the toggle. Weakness: the grant itself was not confirmed against a balance, and an auto-grant is not the claim flow.
- `/claim-credit` in CLI 2.1.284 does one status GET and opens `claude.ai/code/claim-credit/<org-uuid>` in the browser or desktop app; no POST/PUT/PATCH in the promo module (M: `mmap`+regex over `~/.claude-284/.../claude`, 25 KB window around offset 196,565,074; `Nt.get` 1, `Nt.post` 0). The claim completes on the web page, as the logged-in browser profile.
- Fleet guard: `accounts.json:19` `usage_credits_authorized: false`, `:37` `credits_authorized: false` (M). `bin/claude-accounts:6797-6808` raises a breach line on `extra_usage.used_credits > 0`; `:6817-6821` a warning on toggle ON; `:1372` cuts weekly headroom target to 0.98 and `:2658` halves the soft score above 90% weekly when the toggle is on (M: `sed -n`).

## 6 - Exposure by scenario

| Scenario | Toggle | Purchased funds / auto-reload | Dollar exposure | Fleet side effect |
|---|---|---|---|---|
| A. Claim; toggle untouched (what the offer page describes) | off | none | **$0** (D rows 7) | none, unless bonus spend is reported in `extra_usage.used_credits`, which would print a false breach line (unknown) |
| B. Claim; Anthropic enables the toggle (terms row 2 permit it) | on | none | **$0** billed: prepaid model, "only charged if you buy additional usage credits later" (D row 9) | warning line per account; routing loses 2 pp weekly headroom per account per week while on (`:1372`), i.e. up to 8 pp per account over 4 weeks vs 4.4-5.7 pp gained (E) -> switch it off the same day (allowed, section 3) |
| C. As B, plus a residual purchased balance or auto-reload on any account | on | present | Real: Fable past the 50% cap in `-p` "bills it without asking"; plan-limit overflow at API rates; cap "Unlimited" unless set; up to $2,000/day redemption | breach line |
| D. Skip | off | none | $0 | next3 appears to hold the credit already; skip does not keep it out of the promo (I) |

- Scenario C precondition was not re-read today. Prior note: `balance=null`, toggle off on all four on 2026-09-23 (D, memory `cloud-session-cost-exposure.md`); one account showed $176.91 historical spend on 2026-07-26 (D, `accounts.json:17`).

## 7 - Numbers that move the choice

| Quantity | Value | Label |
|---|---|---|
| Nominal credit | 4 x $250 = $1,000; 3 need a claim, next3 reads as already granted | D / M |
| Time left to claim | 26.9 h from 2026-10-07T04:07Z | M (`python3 datetime`) |
| Credit lifetime | 29.2 days from now | M |
| Quota displaced if one account's $250 is fully used | 4.4-5.7 weekly-pp ($250 / $6.29-8.15 per fire x 0.143 pp per fire; inputs from `a4-economics-and-live-state.md:65`, `candidates.md:25`, arithmetic re-run) | E |
| Fleet, fully used | 17.6-22.8 pp = 1.1-1.4% of 1,600 account-week-pp (4 accounts x 4 weeks) | E |
| Fleet, at the lane's 1.86 fires/day | ~52 fires x 0.143 = 7.4 pp = 0.46% | E (prior rate, `a4:65`) |
| Operator cost | 3 claim-page visits in the right browser profile, 1 login (next3), then one `claude-accounts` read | I |

## 8 - Prior claims re-checked

| Prior claim | Result |
|---|---|
| Terms say claiming authorizes Anthropic to enable Usage Credit (`a4:44`, `candidates.md:25`) | Confirmed verbatim (M: re-fetched, `d2-terms.txt:13`) |
| "Draw order ... Cannot tell which" (`a4:62-64`) | Resolved: credit-first (D, `d2-promo-article.txt:29`) |
| "After the credit is used or expires, a plan limit on an account with the toggle still on bills the payment method unless the monthly spend limit is set" (`a4:61`) | Overstated: needs purchased funds or auto-reload as well (D, `d2-extra-usage.txt:33,45-46`); and the toggle need not be on at all (D, row 7) |
| "terms were not read ... support.claude.com articles were not fetched" (`b2:147,194`) | Now read: article 17152539 |
| `usage_credits_authorized=false`, `credits_on=false` on all four (`a4:52-55`) | Confirmed (M) |
| `/claim-credit` exists in 2.1.284 (`a4:46`) | Confirmed; it only opens the claim page (M) |

## 9 - Alternatives considered

- **Claim on all claimable accounts, leave the toggle off, read `claude-accounts` after each.** Supported by rows 7, 9 and section 5.
- **Probe one account first** (within the 26.9 h), read the toggle and `extra_usage.used_credits`, then the other two. Removes the two unknowns in section 10 before committing all accounts.
- **Skip.** Costs nothing; forgoes 0.46-1.4% of four weeks of fleet quota (E) and the limit-wall option; does not undo next3's apparent grant.
- **Claim and flip `usage_credits_authorized` to true.** Not required by anything read; rejected.

## 10 - Blockers and uncertainties

- Claim page text unread (403). Whether it shows its own consent line about Usage Credit is unknown.
- Whether a claim changes `extra_usage.is_enabled`: inferred no; never observed on a claimed account.
- Whether bonus-credit spend is reported in `extra_usage.used_credits` (would trip the breach line on free spend) or in a separate field.
- next3: grant not confirmed against a balance; account is `login-required`; its status cache is 8 days old. Status caches for the others are 2-8 days old.
- Residual purchased balance and auto-reload state per account not re-read today.
- Debit rate and cache-TTL treatment for credit-paid cloud sessions not stated; the $6.29-8.15 per fire figure is the prior agent's.
- Whether the lane's `claude --cloud` fires (`scripts/handoff-fire.sh:12490`) count as "cloud sessions from ... CLI": the page lists CLI (D); not tested.
- One person holding four accounts: permitted by the letter ("per account"); the revoke clause is discretionary.

## Sources

- `https://claude.dev/blog/claude-code-in-the-cloud/` (published 2026-10-06)
- `https://www.anthropic.com/legal/promotion-credit-terms` (effective May 19, 2026)
- `https://www.anthropic.com/legal/credit-terms` (effective March 4, 2024)
- `https://support.claude.com/en/articles/17152539-cloud-sessions-bonus-credit-promotion`
- `https://support.claude.com/en/articles/12429409-manage-usage-credits-for-paid-claude-plans`
- `https://support.claude.com/en/articles/15862783-claude-fable-5-one-time-free-credits-promotion`
- `https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan`
- `https://support.claude.com/en/articles/14246112-buy-usage-bundles`
- `https://code.claude.com/docs/en/costs`, `/model-config`, `/fast-mode`, `/ultrareview`, `/routines`, `/claude-code-on-the-web` (via `llms-full.txt`)
- `https://www.anthropic.com/legal/consumer-terms` (effective October 8, 2025)
