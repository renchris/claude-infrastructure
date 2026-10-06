# q7 — how targets are chosen when N sessions leave one account, and whether the choice spreads them

Date 2026-10-06. Read-only slot. Tags: MEASURED = I ran the command; READ = source or record; INFERRED = derived.
Paths are relative to the checkout `/Users/chrisren/Development/.worktrees/lr-zero-memory` unless absolute.

## Verdict

- There are three target choosers, and they disagree. Only one of them counts the batch, and that one drives nothing.
- **Move lane** (`cc-lr move`, and the idle half of `cc-lr recover --limited --account A`): ONE target for the whole batch, resolved once, with no term for N and no ledger charge. All N land on one account by construction.
- **Recover lane** (`lr-fleet.sh --one/--recover`): one router ask per session under a lock, each pick charged as a 15-minute phantom. The phantom moves only the concurrency term; the 5-hour and weekly survival floors never see sessions assigned but not yet burning.
- **`claude-accounts --place`**: per-batch placement that charges each placed mover's projected burn against both floors. Its only caller is the reconciler, which runs in `observe` mode, so it actuates nothing.
- Today's record: next3's pane count went 11 to 0 between 05:55Z and 06:34Z; next2's went 1 to 13 while next4 (weekly 2%) went 0 to 2 and next went 1 to 2. No wall was hit, because idle moved sessions burn nothing until prompted.

## Q1 — rank logic in bin/claude-accounts

| Fact | Receipt | Tag |
|---|---|---|
| `--rank KIND` prints every routable account as `name score`, best first; `--route` prints only rank[0] | bin/claude-accounts:8207-8211, sort at :4992 | READ |
| General score = `weekly_headroom / T^2 * SF * KF * CF * cliff`; T = hours to weekly reset minus 0.5 | :4690-4703, :2625-2655; URGENCY_EXP 2.0 in ~/.claude/accounts.json | READ |
| The objective is deliberate concentration on the soonest-expiring quota, not balance | :2790-2814 ("exhaust by deadline") | READ |
| `--recovery` adds eligibility floors: projected 5h < 0.60, weekly headroom >= 0.10, fable f_eff > 0.05 | :4647-4664, defaults :2943-2945 | READ |
| The 5h projection is `session_pct + the account's own measured burn * min(1 h, time to reset)`; no term for incoming sessions | :3492-3516 | READ |
| Repeated asks see earlier picks only through `k_phantom`: ledger rows younger than 15 min, stamped on every invocation, cached rows included | :3209-3257, :7973, ASSIGN_TTL_MIN :2825 | READ |
| `k_phantom` feeds two places only: the hard gate `k_eff >= k_cap` and the soft factor `KF = clamp(1 - k_eff/k_cap, 0.1, 1)` | :3027-3035, :4679, :2653 | READ |
| `k_cap` is KMAX when the working census was measured, KMAX_RESIDENT otherwise; live values 24 and 40 | :3123-3162; `jq .router ~/.claude/accounts.json` | MEASURED |
| KMAX was raised 8 to 24 on 2026-10-04 "so 12 sessions could move onto the account with the soonest weekly reset" | accounts.json `_kmax` note | READ |
| The file states the single-ask defect itself: "a wave of limited panes asked it N times and every answer was the same rank[0]" | :4996-5001 | READ |

Consequence (INFERRED from the rows above): one more phantom costs the leader 1/24 of its score (4.2%). A cohort stacks on rank[0] until KF closes the score gap to rank[1], or the gate trips at 24 working plus phantoms. The quota floors are evaluated on the pre-landing reading for every pick inside one <=90 s cache.

## Q2 — how each lane picks

| Lane | Entry | Target unit | Rule | Sees the N being moved? | Writes the ledger? |
|---|---|---|---|---|---|
| Move, explicit `--to B` | bin/cc-lr:1237-1317 | whole batch (`plan.json` has one `to`) | operator names B; gate is membership of B in `--rank general` (no `--recovery`) at cc-lr:771-808 and lr-move-batch.sh:128-150 | no | no |
| Move, `--to auto` | bin/cc-lr:1270-1274 calls cl_switch_auto_target once (:701-724) | whole batch | `--rank interactive`, hysteresis off, tier 2 only, highest score = soonest weekly reset (claude-accounts:4923) | no | no |
| Idle half of `recover --limited --account A` | bin/cc-lr:488-502 | whole idle set | same single auto target, then cmd_switch_driver to cmd_move | no | no |
| Recover per session | lr-fleet.sh:760-837, asked at :741 | per session | `--rank KIND --recovery --src SRC`; walk past the source and stores that hold the sid; take the first | k only | yes, `--assign A --src lr-fleet`, no sid, no id (:713-719) |
| Recover, explicit `--target` | lr-fleet.sh:767 | per session | caller's account, charged as a phantom | k only | yes |
| Recover soft fallback | lr-fleet.sh:824-835, :841-867 | per session | router ranked nothing: take a soft-excluded account, lowest weekly_pct first; survival floors bypassed | no (sort key is weekly_pct, session_pct) | yes |
| Reconciler | lr_recon/plan.py:229-242 | per batch | `--place --lane L --recovery` | yes, both floors and k | `--assign-many`, act mode only |

- The recover lane's rank, assign and capacity probe run under one mutex so that worker 2 sees worker 1's phantom (lr-fleet.sh:580-592). READ.
- `grep -n -i assign` over lr-move-batch.sh, lr-move-lib.sh and lr-move-worker.sh returns one hit, `LR_ASSIGN_ID="$BATCH"` (lr-move-worker.sh:146), which is a record field and not a ledger write. MEASURED.
- The move gate for N sessions is weaker than the recover gate for one: plain `--rank general` lists an account at weekly 95% or projected 5h 80%, which `--recovery` excludes. INFERRED from claude-accounts:4645-4664 and :5297-5310.
- tests/lr-move-plan.bats has 15 cases (lines 90-232). None passes `--to auto` and none asserts a count or a spread. tests/claude-accounts-place.bats:156 pins "12 equal movers over 3 equal accounts give 4/4/4" and :145 pins the 7th-mover 5h refusal. READ.

`--place` arithmetic (claude-accounts:5202-5218, constants :5002-5003), for the n-th mover onto account a:

- 5h: `u5 + (own_burn + n * 0.07/h) * min(1 h, 5h_reset_h) < 0.60`
- weekly: `headroom - (n + 1) * 0.011/h * min(9 h, weekly_reset_h) >= 0.10`
- seats: `KMAX - k_work - phantoms - already placed`; a null k_work gives 0 seats
- pick: highest recovery-lane score with phantoms plus placed movers in KF; ties go to the account with fewer placed (:5268-5269)

Reconciler state: `recon/shadow/last-pass.json` reads `"mode":"observe"`, `recon/owned` and `recon/plans` are empty, `~/.reso/limit-recover/recon.on` does not exist, and the assignment ledger holds no charge row with an `id` or `sid` (382 rows; one void row dated 2026-10-04). MEASURED.

## Q3 — what the records show

Move lane (`ls ~/.reso/limit-recover/move`: one batch directory, n=1 batch):

| Batch | Rows | Target | Verdicts | Router at admit |
|---|---|---|---|---|
| 20261006T060534Z-next3-next2-64630 | 9 (7 move, 2 hold) | next2 for all | 7 of 7 MOVED to next2, 176-386 s each, batch wall 434 s | `router.err` route-meta names next4 as rank[0] of the general lane; admission asked only whether next2 was listed |

Recover lane (`fleet/*/results.tsv`: 703 rows in 475 runs; 226 router-picked rows and 75 explicit-target rows among `one-*` rows that carry a target). Cohort = same source, gaps <= 20 min, at least 3 distinct sessions with a target. MEASURED: 11 cohorts, 6 landed on one account, 5 split.

| Start (UTC) | Source | Sessions | Targets | Why |
|---|---|---|---|---|
| 09-19 20:23 | next3 | 7 | next2 x7 | explicit `--target` (no rank file) |
| 09-29 04:17 | next2 | 4 | next4 x4 | only eligible: next=kmax, next3=weekly-exhausted |
| 10-01 19:59 | next4 | 13 | next3 x13 | only eligible; excluded as `recovery-weekly-thin` by 20:18Z; 10 more rows sent by explicit target, 6 of those FAILED |
| 10-04 07:45 | next4 | 13 | next3 x7, next2 x5, next x1 | spill mostly while next3 read `kmax-concurrency` (KMAX was 8 then) |
| 10-06 06:04 | next3 | 4 | next2 x2, next4 x2 | KF flip at k_eff 6 of 24; base scores were within 1.32x (inferred from the replica below) |

Destination trajectories (`~/.claude/logs/account-utilization.jsonl`), MEASURED:

| Event | Destination before | After | Per landed session (upper bound, residents included) |
|---|---|---|---|
| 10-01, 13 routed to next3 | 19:41Z weekly 88% | 20:31Z 91%, 23:09Z 93%; k 16 to 24 | started 2 points above its own floor and crossed it in under 50 min |
| 10-04, 7 onto next3 | 07:45Z 5h 3%, weekly 39%, k 2 | 09:22Z 5h 42%, weekly 49%, k 8 | 5h 3.4 pp/h, weekly 0.88 pp/h |
| 09-29, 4 onto next4 | 04:10Z 5h 7%, weekly 26% | 05:44Z 5h 23%, weekly 30% | 5h 2.6 pp/h, weekly 0.64 pp/h |
| 10-06, next3 emptied (k 11 to 0) | 05:55Z next2 k 1, next4 k 0, next k 1 | 06:34Z next2 k 13 (5h 5%, weekly 15%), next4 k 2, next k 2 | no wall |

- 9 of the 11 leavers I can name on 10-06 went to next2: 7 moved, plus 2 of 4 recoveries. MEASURED.
- Ledger rows 05:57-06:27Z on 10-06: 6 `lr-fleet` rows and 0 for the 7-session batch admitted at 06:07:04Z. Recoveries ranking at 06:08Z and 06:20Z could not see those 7. MEASURED (`jq` over `~/.claude/logs/account-assignments.jsonl`; 382 rows in total: 194 handoff-fire, 167 lr-fleet, 19 claude-launcher, 1 recycle-repick, 1 with no src).

Replay of 14 movers on the 05:55Z snapshot. Estimated: my own replica of score_general and floors_ok, k_work 0, phantoms 0.

| Rule | next2 | next4 | next | Waiting |
|---|---|---|---|---|
| Move lane, single target | 14 | 0 | 0 | 0 |
| Recover lane, rank plus phantom, all inside one TTL | 8 | 3 | 3 | 0 |
| `--place` | 6 | 4 | 4 | 0 |
| `--place`, 20 movers | 6 | 7 | 6 | 1 |
| `--place`, 30 movers | 6 | 7 | 6 | 11 |

By the router's own batch floor, next2's budget was 6 movers; its pane count rose by 12, and 9 of those are named leavers of next3.

## Q4 — a spread rule with today's numbers

The objective stays "fill in deadline order", which is the router's design and the operator's 10-04 ruling. The missing piece is a per-destination seat budget that counts the batch. It already exists as `--place`.

Seats for destination a (not the source, not hard-excluded):

- `seats_5h = floor((0.60 - u5 - own_burn * ahead) / (0.07 * ahead))`, with `ahead = min(1 h, 5h_reset_h)`
- `seats_wk = floor((weekly_headroom - 0.10) / (0.011 * min(9 h, weekly_reset_h))) - 1`
- `seats_k = 24 - k_work - phantoms`
- `seats = max(0, min(seats_5h, seats_wk, seats_k) - pending)`, where `pending` is sessions moved onto a that have not yet shown burn

Fill by recovery-lane score, recomputed after each pick. Limited sessions take seats before idle ones (the order at claude-accounts:5194-5200). Overflow: idle sessions stay on the source and are listed with the source's reset time; they are not blocked until someone types. Limited sessions with no seat go to the account with the lowest projected utilisation rather than all to one, which keeps the 10-01 ruling against parking.

Seats now, from the 06:37Z cache (`jq` over /tmp/claude-accounts-cache.json; hand arithmetic, estimated):

| Account | 5h | Weekly | Weekly reset | Panes k | seats_5h | seats_wk | Seats before `pending` |
|---|---|---|---|---|---|---|---|
| next | 6% | 15% | 117.4 h | 2 | 7 | 6 | 6 |
| next4 | 4% | 3% | 122.4 h | 2 | 7 | 7 | 7 |
| next2 | 8% | 16% | 100.4 h | 13 | 7 | 6 | 6, and 0 once the roughly 12 sessions moved in since 06:04Z are charged |
| next3 | 7% | 100% (wire rejected) | 5.4 h | 0 | source | source | 0 |

About 19 seats per pass across three destinations. The 5h test is a strict inequality, so an exact quotient loses one seat (next4: 0.56 / 0.07 = 8 gives 7). Calibration against the two measured cohorts: the 0.07/h 5h default is 2.1-2.7x above measured 2.6-3.4 pp/h (conservative); the 0.011/h weekly default is 1.25-1.7x above measured 0.64-0.88 pp/h. n=2 cohorts.

Missing data for a better rule:

1. Per-session burn before the move. `burn_ph` is accepted by `--place` and "no caller supplies burn_ph today" (claude-accounts:5229-5231), so every mover is charged the same default.
2. Whether a moved session will burn at all. `kind` (limited or idle) only orders movers; there is no post-move activity signal, so 7 idle sessions cost the same seats as 7 working ones.
3. A `pending` count. Phantoms live 15 min; a moved idle session is then invisible to k_work, to the 5h projection and to the weekly floor until it is prompted. No ledger says "moved here, not yet burning".
4. A reliable k_work. It was null on 2,292 of 6,400 sweep rows from 09-29 to 10-06 (35.8%); `--place` gives a null account 0 seats, and `--rank` silently switches cap 24 to 40.
5. Native 5h burn. `burn_5h_ewma_ph` and `burn_5h_ph` were null on all 4 rows of the 06:37Z cache.
6. The server's per-account concurrency limit above 6 working sessions, which the `_kmax` note calls unmeasured.
7. Provenance. `plan.json` does not record whether `to` was auto or explicit, and nothing joins "moved to X at t" with "X refused at t+d", so wall-push rates had to be rebuilt by hand above.

## Alternatives considered

- Equal split across eligible accounts: rejected. It strands the soonest-reset quota, which the router was built to prevent (claude-accounts:2790-2814) and which the KMAX lift re-affirmed.
- Lower KMAX back to 8 so the gate spreads: rejected. It caps working sessions, and the refusals of 10-01 and 10-04 are what the operator ruled against.
- A longer phantom TTL alone: insufficient. Phantoms move k only; the floors would still read pre-landing quota.
- Count logic inside cc-lr: rejected. It would be a routing threshold outside the router, which the file warns against (claude-accounts:2843-2846).

## Uncertainties

- The 10-06 destination counts come from pane-census deltas, which include unrelated launches (one launcher row for next2 at 06:03Z, handoff-fire rows for next at 06:12Z and next2 at 06:26Z).
- Whether the 10-06 batch's `to` came from `auto` or was typed is not recorded. Both routes give next2: it had the soonest weekly reset among safe accounts.
- Per-session burn figures are two cohorts, contaminated by resident sessions and staggered arrival.
- The replay is my replica, not a run of `--place`. I did not run it because I had not proven every callee writes nothing.
- A faster, parallel rotation raises the stakes: today's two-at-a-time pace lets real burn reach the quota reading between picks; 14 picks in 60 s would all read one snapshot. INFERRED.

## Side observation, outside this slot

`batch.log` of the 10-06 batch records `syntax error near unexpected token 'newline'` at the installed lr-move-batch.sh line 84, and `summary.json` says `"verdicts":"none"` for a batch with 7 MOVED. `/bin/bash` is 3.2.57, and it fails to parse `case "$f" in a|b) ... ;; esac` inside `$( )` (reproduced with a one-line `/bin/bash -c`). The same construct is at scripts/limit-recover/lr-move-batch.sh:80-83 in this checkout.
