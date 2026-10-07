# Decision 2: claim the Claude Code cloud credit on the four Max accounts?

Judged 2026-10-07 04:26 UTC (Oct 6, 11:26 PM Central). Nothing was claimed, toggled, logged in or fired; no authenticated endpoint was called.
Labels: **measured** = I ran the named command; **documented** = a source says it; **inferred**; **estimated** = method named.

## Verdict

- **Recommendation: claim, one account first.** Claim on account next4, run the account readout (`claude-accounts`) five minutes later, and claim on next, next2 and next3 only if next4's usage-credits toggle still reads off. Leave the "usage credits authorized" setting in `accounts.json` at false.
- **Conviction: 68%** in that course (skip: 32%).
- **Deadline:** October 7, 11:59 PM Pacific = October 8, 1:59 AM Central, 26.6 hours after this read (documented: help page; measured: `python3 datetime`).
- **Would flip it:** the readout showing the usage-credits toggle ON for next4 after its claim, or the claim page itself saying that claiming turns usage credits on. Then switch the toggle off and skip the other three.
- **Prior conviction moved:** from "skip, 65%" to "claim in stages, 68%". The mover is the offer's own help page, which the prior investigation never read: "Do I need to turn on usage credits? No. You can claim and use your bonus credit without turning on usage credits." The prior skip rested on the opposite reading (`docs/research/cloud-post-eval-2026-10-06/candidates.md:89`, `README.md:29-30`).

## Why

| # | Reason | Source | Label |
|---|---|---|---|
| 1 | The offer's help page says no toggle is needed, the credit is spent before plan quota, and "You're only charged for usage credits if you've turned them on and you go past your plan's usage limits." Anthropic staff point to this page as the credit's documentation. | https://support.claude.com/en/articles/17152539-cloud-sessions-bonus-credit-promotion (my copy `/tmp/decisions-eval/judge-d2-scratch/promo.txt:38-45`); staff reply on GitHub issue anthropics/claude-code 98183 | measured (`curl`, HTTP 200; `gh api` GET) |
| 2 | A claimed Max 20x account's settings panel shows the toggle still off: a separate "Cloud session credits, $247 of $250 left" block, "Turn on usage credits ...", "£0.00 this month, No spend limit, Auto-reload off". A Max 5x user reports the same ("Usage credits toggle is OFF"). I found no public report of a claim turning the toggle on or charging a card (5 issue searches since 2026-09-20). | GitHub issues 99597 (body) and 97021 (comment 2026-10-02) | measured read of two unverified user reports |
| 3 | Even if Anthropic used its permission to enable usage credits, Max usage credits are prepaid: "You'll then need to prepay", auto-reload is opt-in, and it can be switched off "at any time". Our own alarm would show a flip within one 5-minute sweep: the toggle read on in 0 of 45,414 logged rows across the four accounts, and all four cached configs read usage credits disabled. | https://support.claude.com/en/articles/12429409-manage-usage-credits-for-paid-claude-plans (`judge-d2-scratch/extra.txt:53,70-71,118-119`); `bin/claude-accounts:6817-6821` | documented; measured (`python3` over `~/.claude/logs/account-utilization.jsonl`; `python3 json.load` of each account's `.claude.json`, key `cachedExtraUsageDisabledReason`) |
| 4 | Skipping is the only choice that cannot be undone after the deadline; an unused credit expires at no cost. The operator's own note already files this as an open item with the check to run after a claim. | help page ("After it's used or expires, your plan's regular usage applies"); `~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/cloud-session-cost-exposure.md` | documented |
| 5 | What caps the conviction: the value is small. At the cloud lane's measured rate (10, 25, 69 sessions in the last 7, 14, 28 days) the credit would relieve 2.4-10.3 weekly quota points fleet-wide by November 4, which is 0.15-0.65% of four weeks of fleet quota, about $1-$5 of subscription; $262-$585 of the $1,000 would be used. Fully spent it is 17.7-22.9 points, about $8-$11. No cloud-eligible work is dispatchable now (0 open backlog rows, 120 blocked, 1 claimed). | fire count measured (`python3` over 757 `~/.claude/autonomy/cloud/*.decl`); backlog count measured from the researcher's saved list (`/tmp/decisions-eval/d2-web/bl_all.json`) | value estimated: fires x 29.15 days x $6.29-$8.15 per session x 0.0585-0.144 points per session (prior figures, not re-measured); $0.46 per point = $200 a month / 434.5 points |

## Options

| Option | Outcome | Cost |
|---|---|---|
| **Claim, one account first (recommended)** | Up to $250 of cloud-session credit per account through November 4, drawn before plan quota. Toggle and config stay as they are. The one open question (does a claim flip the toggle on our accounts) is answered on the lowest-risk account before the other three are touched. | About 10 operator minutes (estimated: 4 claim pages in 4 browser profiles plus 2 readouts). Per-session quota measurements read zero for credit-funded sessions until November 4 (`candidates.md:71`). Unquantified tail of account action (one unverified closure report, issue 99852). |
| Skip | Nothing changes; zero new state. | Forgoes 0.15-0.65% of four weeks of fleet quota (estimated), permanently after October 8, 1:59 AM Central. Does not undo account next3, whose banner already reads "You've been granted a $250 bonus credit". |
| Claim all four at once | Same upside, 5 minutes sooner. | Tests the unknown on next and next2 first, the two accounts that once had usage credits enabled (`docs/research/breaking-the-ceiling-2026-08-19/B2-cloud-economics.md:147-152`) and sit at the limit most often. |
| Claim and set "usage credits authorized" to true | Silences any false alarm from credit spend. | Rejected: the setting is one fleet-wide switch, so it also silences the real-dollar breach line and the toggle warning for four weeks (`bin/claude-accounts:6797-6821`). Nothing in the offer requires it. |

## The recommended course, step by step (described only, none run)

1. On next4, open `https://claude.ai/code/claim-credit` in that account's browser profile, or run `/claim-credit` in its command-line session (it only opens that page). Read the page before clicking; stop if it says usage credits get turned on.
2. Wait one 5-minute sweep and run `claude-accounts`. A warning line on next4 means the toggle flipped: switch it off in Settings > Usage and skip the rest.
3. Clean readout: on next and next2, look at Settings > Usage first (balance, auto-reload), then claim. next3 needs its login anyway (reads login-required at 04:21 UTC, measured); after login, check whether its credit is already there.
4. After the next cloud session on a claimed account, read "Cloud session credits" in Settings > Usage. A balance that did not fall means our session path does not draw the credit: no gain, no harm.

## Key questions

| Question | Answer |
|---|---|
| Best option under the operator's values? | Staged claim. Completeness: it is the only path that keeps the one item with a hard deadline. Zero dollar exposure: preserved on the documented path, and checked on one account before the rest. No landing outage: landing is untouched unless the toggle flips, which lowers one account's routable weekly ceiling from 1.00 to 0.98 (`bin/claude-accounts:1372`) until it is switched off. Minimal operator time: about 10 minutes against zero for skip; this is the value that argues for skip. |
| Did the research move the prior? | Yes, from skip 65% to claim 68%, by the help page in reason 1 plus the claimed-account panel in reason 2. |
| What can only an action settle, and is it cheap and reversible? | Whether a claim flips the toggle on our accounts: one claim plus one readout, 5 minutes. A flipped toggle can be switched off (documented). The claim itself cannot be withdrawn, but an unused credit simply expires. |

## Where the researchers disagreed, and what I believed

| Point | Positions | Resolution |
|---|---|---|
| Is next3 already granted? | One researcher measured a "granted" banner; two listed it as unknown. | The banner is real: next3's cached server message is version 2, "You've been granted a $250 bonus credit", fetched 2026-10-06 16:42 UTC; the other three read version 1, "Claim ..." (measured: `python3 json.load`, key `cachedGrowthBookFeatures.tengu_swift_lynx`). The grant is not confirmed: its claim-status cache still reads claimed=false (dated 2026-09-28) and no balance was read. Treat as inferred. |
| Value per account | 4.4-5.7 points versus 1.8-5.7 versus 1.2-3.1. | Different questions. 1.8-5.7 is one account's $250 fully spent, across three exchange rates; at the measured fire rate no account spends its $250. I use the fleet-wide realized range in reason 5. |
| The $176.91 found on one account in July | The adversarial researcher calls it unexplained spend with the toggle off. | The commit that recorded it says the toggle field is only "the toggle's current position" and that the meter is zeroed after switch-off (commit `7edc3b5b2`). It shows the toggle was once on, not that money moved with it off. Who turned it on is not recorded. |
| Can a flipped toggle be reversed? | "At any time" (help page) versus "may be blocked" (an August reading of can-toggle = false). | Help page for the rule; the August reading is two months old and was not re-read. Left as an unknown. |
| Open backlog rows | Brief says 1; one researcher measured 0. | 0 open, 120 blocked, 1 claimed of 4,241 (measured from the saved list). No effect on the verdict. |

## Remaining unknowns

- Whether a claim turns the usage-credits toggle on for our accounts. The help page and two user reports say no; the legal terms still say "you authorize Anthropic to enable Usage Credit on your account if it is not already enabled" (https://www.anthropic.com/legal/promotion-credit-terms, `/tmp/decisions-eval/d2-terms.txt:13`). Not measured on our accounts.
- Whether our cloud sessions, created through the sessions endpoint under the account's sign-in, draw the credit. The help page names web, desktop, command line and mobile. Two public reports say cloud usage hit plan quota despite a credit (issues 99166, 97021). Worst case is no gain.
- Whether credit spend is reported in the usage-credit spend field, which would print a false "NOT authorized" line (`bin/claude-accounts:6797-6808`). The claimed-account panel shows a separate ledger and "£0.00 this month" after $3 of credit, which argues against.
- Purchased balance and auto-reload on next and next2, last read 2026-09-23 (balance empty on all four, per the operator's note). Not re-read today.
- How often accounts are actioned after claiming, and how Anthropic treats four claims by one holder. The offer says "One credit per account"; the terms allow revoking credit for "fraud, abuse". One unverified closure report exists (issue 99852, 0 comments). No source gives a rate.
- The claim page's own wording: it returns 403 without a signed-in browser.
- The per-session cost and quota figures behind every value number are August-September measurements, not re-measured.

## Receipts

- Researcher files: `/tmp/decisions-eval/d2-terms-primary.md`, `/tmp/decisions-eval/d2-our-policy-and-value.md`, `/tmp/decisions-eval/d2-red-team.md`.
- Pages I re-fetched (HTTP 200 each): `/tmp/decisions-eval/judge-d2-scratch/{promo,terms,extra,blog}.txt`.
- Prior claims re-checked: the terms sentence (confirmed); both config settings false (`jq` on `~/.claude/accounts.json`, `accounts.json:19,37`, confirmed); toggle never on in the log (confirmed, 0 of 45,414 rows).
