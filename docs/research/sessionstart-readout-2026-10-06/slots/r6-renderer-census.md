# R6: who renders or acts on the weekly/5h meter near the wall (replay of next3 at 2026-10-06T06:01:45Z)

Worktree `bin/claude-accounts` is byte-identical to the live `~/.claude/bin/claude-accounts` (measured with `diff -q`, which printed SAME-AS-LIVE). All line numbers below are for that file unless another file is named.

## Receipts for the replay (measured)

- **Sandbox:** `python3 /tmp/ssr-research/r6-sandbox/run.py worktree` and `python3 /tmp/ssr-research/r6-sandbox/scen.py`.
  - The module is loaded with `SourceFileLoader`. `main()` never runs.
  - HOME and the log, util, assign and route paths all point under `/tmp/ssr-research/r6-sandbox`, and `CC_ACCOUNTS_WIRE=off`.
  - Time is frozen at 06:01:46Z, which is the board file's mtime.
  - The rows are the four `account-utilization.jsonl` rows stamped `2026-10-06T06:01:45.738874`. Burn comes from `apply_burn` over a copy of the series cut off at that timestamp (12,848 rows).
- **Fidelity check 1, the board note:** the replayed board prints the incident sentence word for word: "next3 is not out of weekly quota: the meter shows 100%, but Anthropic's server says 99.0% used and still accepts work (about 1% of the week left, roughly 5% of one 5-hour window)". It also prints the pace line "next3 no strand — 1.04× burn, ⚠ WALL trajectory".
- **Fidelity check 2, the desk scores:** the replayed desk ranking is next2 2.011333 and next 2.008441. The real record in `~/.claude/route/route.jsonl` at `2026-10-06T06:03:15Z` reads `"desk -> next2 (runner-up next)","score":2.011333,...,"runner_up_score":2.008441`. The two match exactly.
- **Wire precision:** every `wire_5h_util` and `wire_7d_util` value in `account-utilization.jsonl` has at most 2 decimals. There are 44 distinct values, and the highest are 0.98, 0.99, 1.0 and 1.01 (python scan). The only 3-decimal wire value in the suites, `0.996`, is synthetic (`tests/claude-accounts-wire-truth.bats:336`).

## Answer in brief

**(a) Who has which defect**
- Five sites carry the false precision, all from one source.
  - `board_eff` (6344) turns the 2-decimal `0.99` into `99.0`.
  - `pct_text` (6365) prints it as `"99.0%"`.
  - That one value then appears in three places: the board weekly cell (`_bpct`), the `--readout` / `/accounts` markdown cell (`pctc`), and the board/readout note (6747).
  - The note adds two figures of its own: "about 1% … left" and "roughly 5% of one 5-hour window" (the second is `1/K_FROZEN`).
- Three sites carry the present-tense defect:
  - the note, which says "is not out" and "still accepts work";
  - `_wire_note` with `_plain_status`, which say "accepting work, near the limit" (they fire only on throttled rows, so they are silent on this row);
  - the board header's age, which is the age at render time, frozen into the file. The hook adds no age line until the file is 300 s old.
- **Contradictions on the same board:**
  - The drain line `soonest_reset_line` prints "0% of the week left", from the endpoint integer, two lines below "about 1% of the week left".
  - The bare human table `render_table` (step 1 of `/accounts`) ignores the wire and draws `██████████ 100%`, a full red bar. That is the exact rendering the 2026-10-03 ruling reserves for a refusal the server has confirmed.

**(b) Routing**
- **Short answer:** at 06:01:45 routing did not send new sessions to next3 in any lane. It also has no term for k or burn that could stop it once next3 is the last candidate.
  - **general lane:** next3's raw score was the highest in the fleet, 2.78e-4 against 8.26e-5 for next2, because of the T² urgency term. Only `_demote_thin` (DISPATCH_W_FLOOR 0.10) put it last.
  - **desk lane:** next3 is tier 1 and its rivals are tier 2.
  - **fable lane:** `fable-exhausted`.
  - **recovery and `--place`:** `recovery-weekly-thin`.
- **On record:** route.jsonl's last decision for next3 is `2026-10-05T01:59:16Z`. The assign ledger's last fire to next3 is `2026-10-05T17:00:53Z`. The 11 sessions were already resident.
- **Hazard 1 (measured):** the desk picks next3 as soon as every rival's projected 5h use is ≥ 60% (DESK_5H_FLOOR). The weekly key degrades first, so a tier-1 account with ≤1pp left beats a tier-0 rival with 87% of its week left.
- **Hazard 2 (measured):** with `CC_ROUTE_DISPATCH_W_FLOOR=off`, general ranks next3 first.

**(c) Status line:** no account quota reaches it. `statusline.sh:598` prints identity, mailbox, context-window % and git, and the script has no reference to claude-accounts, rate_limits or weekly.

## Census table (06:01:45Z next3 row, replayed)

"Precision" means a tenth, or a "1% left", read off a 2-decimal server figure. "Present-tense" means a snapshot stated as if it were current. "Other" is named in each row where it applies.

| # | Site (file:line, function) | Surface | What it prints or decides for next3 at 06:01:45Z (measured, sandbox) | Defect | Fix shape |
|---|---|---|---|---|---|
| 1 | `claude-accounts:6326-6345` `board_eff` | shared by board, `--readout` and the note | `(99.0, False)` from `math.floor(0.99*1000)/10` (6344). Session: `(6.0, False)` from wire 0.06 | **precision** (the source of it) | Return the percent at the resolution the server sent: `floor(wv*100)` as an integer while the wire has ≤2 decimals (all 44 observed values do), plus a "lower bound" flag. Keep `exhausted` semantics, so the three-state ruling is untouched |
| 2 | `:6360-6366` `pct_text` | all wire percent cells and the note | `'99.0%'` (6365, `f"{v:.1f}%" if v >= 99`) | **precision** | For the nearly-out state, print a bound (`99%+`, or plain `99%`) that differs from the not-confirmed `≥99%` and from the refused `100%`. Decide the text and the colour once here, as now |
| 3 | `:6369-6375` `pct_rgb`, `:6391-6420` `board_bar` | board bar | orange (NEAR_WALL_RGB), `▆▆▆▆▆▆▆▁`: 7 of 8 cells, last cell open | none (matches the 2026-10-01 and 2026-10-03 rulings) | Keep as is |
| 4 | `:6423-6444` `_bpct`, used at `:6688-6689` | board weekly cell (narrow) | `99.0%` beside the orange bar; 5h cell `6%` | **precision** (inherited from 1 and 2) | Fixed by 1 and 2. No local change |
| 5 | `:6560-6579` `pctc` in `readout_lines`, used at `:6695-6698` | `--readout` = `/accounts` markdown table | `\| next3 \| 11 \| 6% \| … \| 99.0% \| 3% \| …` | **precision** (inherited) | Fixed by 1 and 2. Edit the `"\| 99.0% \|"` pin at `tests/claude-accounts-wire-truth.bats:209` |
| 6 | `:6739-6750`, the nearly-out branch of the wall note in `readout_lines` | board note (narrow, wrapped) and `--readout` bullet; the same sentence on both | "next3 is not out of weekly quota: … says 99.0% used and still accepts work (about 1% of the week left, roughly 5% of one 5-hour window)". The figures come from `max(0,1-w7)*100` (1%) and `/K_FROZEN` (0.192, so 5.2, printed as 5%) | **precision + present-tense** | (i) State a bound: "at least 99% used, at most ~1% of the week left". Drop the "% of a 5-hour window" figure or make it "at most". (ii) Use the past tense with the read time, e.g. "was still accepting at 06:01 UTC". This needs a `wire_at` stamp on ordinary probes (see row 18). (iii) Add the load: "11 live (4 working), 1.04× burn, ⚠ WALL trajectory", plus "new work goes elsewhere while another account has room" when `thin_demoted` or desk tier < 2. Pins to edit: `wire-truth.bats:206-207` |
| 7 | `:6743-6744`, the rejected branch of the same note | board and `--readout` | not reached (status allowed_warning). For the 06:08:11 row it prints "**out of weekly quota**, confirmed … (100% used)" | none | Keep |
| 8 | `:6751-6753`, the not-confirmed branch | board and `--readout` | not reached (wire present) | none | Keep |
| 9 | `:6098-6106` `_wire_note`, `:6109-6112` `_plain_status`, called at `:6704-6706` | board and `--readout` "poll throttled" bullet | `""`: the row is not `wire_substitute`. If it were: "; Anthropic's server reads 5-hour 6% (accepting work), weekly 99% (accepting work, near the limit)" | **present-tense** (whole percent, so no precision fault) | Past tense plus the read time from `wire_at`, which a substitute read always has (1961): "weekly ≥99%, accepting at 06:01". Pin to edit: `tests/claude-accounts-freshness.bats:285` |
| 10 | `:4403-4436` `soonest_reset_line`, used at `:6855-6857` | board drain line (narrow only) | "next reset: next3 in 6.0h, 0% of the week left". `left = 100 - weekly_pct` (4420) uses the endpoint integer. It gives no routing reason because `score_general` returns `(2.78e-4, None)`, and the thin demotion is not a reason | **other**: contradicts the note above it (0% against 1%); silent on the demotion | Use `weekly_headroom(r)` as a bound ("≤1% left"). Add "demoted for new work (under the 10% dispatch floor)" when the row is `thin_demoted`, or when it is desk tier < 2 |
| 11 | `:4444-4535` `pace_line`, `:4069` `wall_projection` | board (⚠ rows only), `--readout`, human table | "next3 no strand — 1.04× burn, ⚠ WALL trajectory · 6.0h left". The ratio is 1.0368 from the endpoint `wp=100`; the wire 0.99 gives about 1.026, which is still past the wall | none (this is the evidence the note leaves out) | Keep, and feed its verdict into the note (row 6 iii) |
| 12 | `:6216-6233` `desk_why` | board and `--readout` desk clause | for next3 it would print "weekly ↻ 6.0h · 5h 7% · 5h-safe only", while the 5h cell says 6% | **other**: endpoint `session_pct` beside a wire-first cell (minor) | Use the same wire-first 5h figure as `_bpct` |
| 13 | `:6588-6596`, the header of `readout_lines` | board line 1 | "CLAUDE MAX · Tue 01:01 · cached Ns": the age is computed when the board is rendered (`write_board` at `:7818`) and frozen into the file | **present-tense** (how old the numbers are at read time is never stated) | The hook may add `age` (it already computes it at `hooks/accounts-board.sh:153`) to line 1 while the board is fresh. That stays a pure file read, so it fits the hook constraint. Today the hook adds an age line only at ≥ `STALE_S` = 300 s (`:52`, `:179-185`) |
| 14 | `:6931…7023` `render_table` (`bar()` at 6012, `pct()` at 6032) | bare `claude-accounts`, step 1 of `/accounts` (`commands/accounts.md:19`) | `next3 … ██████████ 100%` (full red bar, bold red 100%); 5h `7%` (endpoint) | **other**: ignores the wire, so an allowed account is drawn as refused. This breaks the 2026-10-03 rule "only a server-confirmed refusal prints 100%" (commit d6c4f8411 says "the board's column, its bar and the /accounts table all use them"; the human table does not) | Send the weekly and 5h cells through `board_eff` / `pct_text` / `pct_rgb`, with the eighths bar never full unless `exhausted is True` |
| 15 | `:1347-1355` `weekly_used_frac`, `:1358-1368` `weekly_headroom` | routing input (every lane), `--place` | `0.99` and `0.010000000000000009`, which is above WEEKLY_FLOOR 0.005, so next3 is eligible | **precision** (on the decision side): a 2-decimal figure is treated as exact. The docstring says "keeps its last ~1pp" | Leave the eligibility math alone (the 2026-10-01 ruling and W-1 pin `wire-truth.bats:95-108` keep the last 1pp spendable). Optionally return a (lo, hi) bound, so renderers print the hi bound as "at most" |
| 16 | `:1371-1375` `wire_rejects` | routing veto | `False` for both 7d and 5h | none | Keep |
| 17 | `:1338-1344` `wire_wanted` (WIRE_NEAR_WALL 99.0 at `:1252`) | producer gate | the wire fires (endpoint 100 ≥ 99) | none | Keep (the hard constraint) |
| 18 | `:2477-2482`, the wire step in `probe_account` | producer | `row["wire"] = w`, but **no `wire_at` stamp**. Only `apply_wire_substitute` stamps it (`:1961`) | **other**: a renderer cannot state the read's age | Stamp `row["wire_at"]` here (0 tokens, 1 line). It is needed by rows 6 and 9 |
| 19 | `:4608-4687` `_excluded` | eligibility for all lanes | `None`. Not wire-rejected, su 0.06 < S_CUT 0.85, and `k_eff` 4 (k_work, not panes 11) < `k_cap` 24 (KMAX, live `accounts.json`) | **other**: no k or burn term ties live load to weekly headroom | See the routing section |
| 20 | `:4690-4703` `score_general` + `:5297-5318` `_demote_thin` / `ranked` (DISPATCH_W_FLOOR 0.10, `:5288`) | `--route` / `--rank general` (handoff-fire `--rank general \| head -1`, cc-board "best next") | raw `2.78e-4`, highest in the fleet (next2 8.26e-5). After the demotion the order is `next2, next4, next, next3` and next3 is `thin_demoted` | none for this row. The guard is a demotion, not an exclusion, and `CC_ROUTE_DISPATCH_W_FLOOR=off` puts next3 first (measured) | Keep. Print the demotion on the board (row 10) |
| 21 | `:4795-4829` `desk_keys`, `:4831-4937` `score_interactive` | desk = bare `claude` | `w_rem 0.01 < desk_w_floor_at 0.0342`, so tier 1 (5H-SAFE), score 1.1545. Rivals are tier 2 (≈2.01) and the pick is next2 | **other (latent)**: if every rival projects 5h ≥ 0.60, next3 (tier 1) beats tier-0 rivals with 87–98% of their week left, and the desk picks next3 (measured; scen.py, rivals at 62/70/80%) | Rank a near-wall row by time to the wall rather than by tier. When `weekly_headroom / burn_wk_ph` is below a horizon (e.g. one desk life, or ~1 h), put it beneath tier 0, still routable as a last resort, so the 2026-10-01 ruling holds |
| 22 | `:4940-4977` `score_fable` | `--rank fable` | `fable-exhausted`: `f_eff = min(0.5*0.97, 0.01) = 0.01 ≤ FABLE_FLOOR 0.02` | none | Keep |
| 23 | `:4656-4665` recovery floors in `_excluded`; `:5202-5217` `--place` `floors_ok` | `--route --recovery`, `--place` | `recovery-weekly-thin` (endpoint `1-100/100 = 0 < 0.10`; the `--place` charge is `0.01 - (n+1)*0.011*5.97 < 0.10`) | none. This is the one weekly gate that is aware of burn | Keep |
| 24 | `:5542-5543` `record_utilization`, `:2481-2482` `log_event` | jsonl series, `claude-accounts.log` | raw `0.99`, `allowed_warning` | none (data, not a claim) | Keep |
| 25 | `hooks/accounts-board.sh:51-188` | SessionStart `systemMessage` | `cat` of the board. When fresh (age < 300 s) it prints the board as rendered, with no age of its own | inherits 4, 6, 10 and 13 | Pure file read. At most, put `fmt_age "$age"` into line 1 (row 13). No fork, no network |
| 26 | `bin/cc-board:140-154,191` | `watch cc-board` (operator glance) | `WK 100%`, state `LIMIT` (endpoint ≥ 90); "best next" = `--rank general \| head -3` → next2 next4 next | none of the two (endpoint integer, conservative) | Optional: read `wire.7d_status` so the label tells "refused" from "≥99" |
| 27 | `lr-fleet.sh:860-864,1179-1185`; `lr-reset-poller.sh:538`; `boot-resume.sh:921-922`; `cc-restore-rebind:294`; `cc-lr:435-436`; `handoff-fire.sh:13715-13718`; `pool-floor.sh:140-144` | limit-recover target choice, resume guards, pool sizing | they treat `weekly_pct >= 100` as capped, so next3 is excluded or held; the wire is ignored (lr-fleet also vetoes `rejected`) | none (conservative; they contradict the router's "last 1pp routable", but in the safe direction) | Out of scope for this plan |
| 28 | `statusline.sh:560,598` | Claude Code status line | prints `ID_SEG MAIL_SEG PCT_SEG OUTPUT`, where `PCT` is `context_window.used_percentage`. grep finds no `claude-accounts`, `rate_limits`, `weekly` or `7d` | none: **no account quota leaks** | Keep (2026-10-04 ruling) |

## Routing trace for next3 at 06:01:45Z (measured in the sandbox unless marked)

- **Inputs:**
  - `weekly_used_frac` 0.99, so `weekly_headroom` is 0.01 (> WEEKLY_FLOOR 0.005).
  - `k_src=work`, `k_eff` 4, `k_cap` 24, so the concurrency factor KF = 1 - 4/24 = 0.833.
  - `_soft` 0.833; `_su_projected` 0.094.
  - Burn: `burn_wk_ppd` 30.5 and `burn_5h_ewma_ph` 2.42.
- **Lane outcomes:**

  | Lane | next3 outcome | Pick |
  |---|---|---|
  | desk (`ranked interactive`) | tier 1, 1.1545 | next2 2.0113 (matches route.jsonl 06:03:15Z) |
  | general (`ranked general`) | highest raw score, demoted to last | next2 |
  | fable | excluded `fable-exhausted` | next2 |
  | recovery | excluded `recovery-weekly-thin` | — |
- **No k or burn term in any weekly gate** for new work (code: 4690-4703, 4795-4829, 4917):
  - The 11 resident sessions (panes) are charged as 4 (k_work) against a cap of 24.
  - No lane compares the ≤1pp of headroom with the burn the account is already carrying.
  - The only weekly check that charges burn is `--place` `floors_ok` (5216, `r_w_worst` 0.011/h per session), and it applies only to recovery.
- **Time to the wall, estimated** (headroom ≤ 1pp divided by the board's own burn fields):
  - ≤ ~47 min at the 48h weekly pace (30.5 %/day, i.e. 1.27 pp/h);
  - ≤ ~2.2 h at the 5h EWMA × K_FROZEN (2.42 × 0.192 = 0.465 pp/h).
  - Observed for comparison (util log): next3 sat at wire 0.99 from 03:08:26Z to 06:01:45Z, got the limit error at 06:03:04Z, and read `1.0 rejected` at 06:08:11Z.
- **How the 11 sessions got there:** the last fire-time assignment to next3 was `2026-10-05T17:00:53Z` (handoff-fire), when next3's weekly meter read 94 (util log, from 16:58:20Z). That was already under the 0.10 dispatch floor. Every routed launch from 03:00Z to 06:12Z went to next2 or next4 (route.jsonl; account-assignments.jsonl).

## What the 2026-10-01 and 2026-10-03 rulings say (from code comments and commits)

- **2026-10-01** (`:6330-6331`, commit 756a22c52): "leaving ~1% of a weekly on the table is a lot".
  - The board must not draw "99% and allowed" and "refused" as the same full red bar.
  - Routing pins this in W-1 (`wire-truth.bats:95`): "endpoint 100 + wire 0.99 allowed => routable, with the last ~1pp of headroom".
  - So keeping the last 1pp **routable** is policy. Demoting it (dispatch floor, desk tier) is consistent with the ruling; excluding it outright is not.
- **2026-10-03** (`:6348-6357`, commit d6c4f8411): the three states go inline in the percent column and the bar: "100%" solid red, "99.6%" orange with the last sliver open, "≥99%" gray half-height.
  - "Only a confirmed refusal ever prints 100%." pct_text and pct_rgb are meant to be the only deciders.
  - **The same commit introduced the tenth:** "board_eff now floors a still-accepting server reading to a tenth (99.6, capped at 99.9)". Its example value 0.996 has never been observed on the wire (0 of 44 values).
  - So the precision fix changes what is printed inside the "nearly out" state and leaves the three states themselves alone.

## Alternatives considered

- **Show a tenth only when the wire carries ≥3 decimals:** equivalent to the integer bound today (none observed) and future-proof. A reasonable implementation of row 1.
- **Print `≥99%` for nearly-out too:** rejected. It merges with the not-confirmed glyph, against the 2026-10-03 three-state rule.
- **Hard-exclude a wire-0.99 account when k is high:** rejected. It breaks the 2026-10-01 ruling and the W-1 pin, and it would strand the 1pp when next3 is the only account left. A demotion below tier 0, keyed on time to the wall, keeps it as a last resort.
- **Re-key the note on `k_shown` (panes 11) or on `k_eff` (work 4):** print both ("11 live, 4 working"), since that is what the board already shows in its `live` column, beside the router's charge.

## Blockers and things not verified

- **Rounding vs truncation (R2):** whether the server rounds or truncates `0.99` decides whether the honest phrase is "at most 1% left" (truncation) or "0.5–1.5% left" (rounding). This census assumes only that 2 decimals do not support a tenth.
- **The 06:01:45Z board header:** not recovered; the file has since been overwritten. The replayed header uses the sandbox cache age.
- **Burn fields:** come from `apply_burn` over a series copy cut at 06:01:45.74 with time frozen. They reproduce the board's 1.04× exactly, but are not proven identical to the live tick's inputs.
- **The 17:00:53Z fire:** why handoff-fire placed a fire on next3 at weekly 94 (headroom 0.06, under the dispatch floor) was not traced. It may have been an explicit `--account` or a stay-on-source.
