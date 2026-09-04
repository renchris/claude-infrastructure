# The cloud 24/7 lane: why it closes ~0.7 rows/day and what would change it

Read-only investigation, 2026-09-04. Every row below is a command I ran or a `file:line`.
Repo `/Users/chrisren/Development/claude-infrastructure`; stores read but never written.

---

## 0. VERDICT (one line)

**PAUSE the cloud lane now.** It converts **29.9 fires/day into 0.7 backlog closes/day** while the
pending pile grows **+23.5/day**; at the observed return rate the current 543-deep pile needs
**~400 days** to drain. The local lane closes **65** rows in the same telemetry window against
cloud's **3**. Rollback is a config change the plist itself documents:
`com.claude.dispatcher.plist:48` — *"ROLLBACK is a config change, not a code change:
`CC_DISPATCH_VENUE_ONLY=local` restores the old"*.

---

## 1. Throughput now — and the arithmetic on net-negativity

| quantity | value | how measured |
|---|---|---|
| cloud sessions fired/day (Aug 29–Sep 3) | **29.9** | `declared_at` over `~/.claude/autonomy/cloud/*.decl`: 48·7·21·20·26·32 = 209/7 |
| branches returned/day (7 d) | **1.3** | `jq 'select(.outcome=="returned")'` return.jsonl: 09-02=7, 09-03=1, 09-04=1, prior 4 d = 0 |
| backlog rows closed w/ cloud evidence (7 d) | **5 total = 0.7/day** | `jq 'select(.event=="done") \| select(.evidence\|test("cloud"))'` backlog.jsonl |
| all backlog closes, same 7 d | **51** | same file — so cloud is **9.8%** of closes while holding **100%** of dispatcher admissions |
| pending pile growth | **+23.5/day** | `pass-scope.pending_total` 468 @09-01T06:17 → 543 @09-04T10:50 (+75 / 3.19 d) |
| pile depth today | **543** pending / **547** managed | return.jsonl last `pass-scope`; `cc-cloud list --json` fold |
| declarations ever | **665** over **151** distinct items | `ls *.decl`; `grep -h '^item=' *.decl \| sort -u` |
| live telemetry verdict | `drain-futile … converted=2 (8.6%) floor=25% reclaim=7.5x` | `bash scripts/backlog-telemetry.sh` |
| lane comparison | `lane=cloud closes=3` vs `lane=local-drain closes=65` | same run, LANE HEALTH block |
| cost of one cloud session | **≈0.81× a local session**, "parity, trending cloud-cheaper" | `docs/research/cloud-local-cost-ab-2026-08-11.md:8-13` |

**Is firing net-NEGATIVE? Yes, and the sweep's capacity is not the reason.**
The sweep reaches the cloud block 14–16×/day (`pass-scope` rows/day: 09-02=14, 09-03=16, 09-04=10
by 10:50) × `--limit 25` = **350–400 examined/day** against a pile of 543 — a full cursor rotation
every **~1.4 days**. Examination keeps up fine. What does not is **starting** work: the 7
`pass-deadline` rows show `started` **1–7 of 25**, `unstarted` 18–24. So:

```
in   +29.9 declarations/day
out   −1.3 returns/day        →  net +22.2/day, matching the measured +23.5
```

Each additional fire is one more row in a 25-slot rotation whose land arm completes ~1/day.
**Firing is strictly pile-additive at ~0.81× the price of a local session that would close the row.**

---

## 2. Top 3 reasons a fired session's output never closes its row

### #1 — 72% of the pile can never be landed, and 33% of it is INVISIBLE (394 of 547)

| stratum | count | share |
|---|---|---|
| managed + pending declarations | 547 | 100% |
| …whose branch is **not on origin at all** | **183** | 33% |
| …that **never pushed** (`last_sha` empty) | **211** | 39% |
| …on account **next3**, whose control-plane token is expired (see #4) | **216** | 39% |

Measured: `git ls-remote --heads origin 'refs/heads/claude/fire-*'` = **405** branches, joined
against the 547 managed rows from `cc-cloud list --json`. `scripts/cloud-reconcile.sh --list` (run
read-only) partitions those 405: **332 ELIGIBLE · 41 RETIRED · 32 LANDED**.

These rows return **with no ledger row at all** — `scripts/cloud-return.sh:442-445` (`BOOTING`,
`NOT-STARTED`, `*) state is not a return state`) each `return 0` without calling `ledger`, and
`scripts/autonomy-sweep.sh:419` sends the child's stdout to `>/dev/null 2>&1`. Arithmetic on
2026-09-04: ~250 rows examined, **65** ledger rows written → **185 examined rows left no trace**.
Root cause on the never-pushed half is already documented:
`docs/research/cloud-boot-contract-restrandings-2026-09-02.md` §1 — the "first act = push an empty
commit" boot contract is prose-only, implemented nine times, landed zero times.

### #2 — the land is never STARTED: the budget is gone, and a CUT land poisons the price

`pass-deadline` rows (`scripts/cloud-return.sh:838-844` deadline, W5):

| ts | elapsed_s | budget_s | started | unstarted | worst_unit_s |
|---|---|---|---|---|---|
| 09-03T13:51 | 907 | 720 | 1 | 15 | 4 |
| 09-03T17:58 | 640 | 720 | 1 | 24 | 238 |
| 09-03T19:47 | 791 | 720 | 4 | 21 | 0 |
| 09-04T01:25 | 626 | 720 | 7 | 18 | 57 |
| 09-04T07:20 | 615 | 720 | 1 | 24 | 57 |

**The compounding defect, not previously named.** `cloud-return.sh:596` writes a land's price
*before* the land as a lower bound `BOUND_S - elapsed`; a land that is cut early therefore records
~652 s. That figure is `MAX`-ed into the affordability test at `:551-556`, and
`COST_TTL_S` is **21600 s = 6 h** (`:202`). Consequence, from the ledger:

```
{"ts":"2026-09-04T00:21:24Z","outcome":"land-deferred","elapsed_s":94,"budget_s":720,
 "land_reserve_s":652,"land_cost_s":652,"fits_bound":true}
```

**A land was refused at elapsed 94 s of a 720 s budget** — 626 s left — because a cut had priced it
at 652 s. 4 of the 13 `*.land-cost` files hold ≥600 s (values on disk: 5·21·38·122·194·369·505·520·
522·620·652·667·823). The global `.return.land_cost` is a healthy **194**, so the poisoning is
per-session and self-inflicted.

### #3 — when a land IS started it is refused, and the refusal latches forever

`land_rc` over all of return.jsonl: **758× rc 70 · 239× rc 65 · 3× 143 · zero rc 0.**
Last 7 d: 17× 70, 2× 65.

Classifying the 64 on-disk `*.land-refused` artifacts by their **true** ship-rail exit
(`grep -o 'ship rail exited [0-9]*'` — *not* the cause words, see the instrument note below):

| cloud-reconcile rc | ship-land rc | n | meaning |
|---|---|---|---|
| 70 | **5** | **31** | **rebase conflict** — the dominant single cause |
| 65 | — | 17 | `cloud-reconcile: could not bring '<branch>' … as a local head` (branch gone / divergent residue) |
| 70 | — | 9 | never reached the ship rail |
| 70 | 6 | 6 | GATE RED — a real verdict about the diff |
| 143 | — | 1 | SIGTERM |

Once filed, the refusal cache at `cloud-return.sh:517-528` keys on `seen_sha` and *never re-asks
until the branch head moves*. A retired VM never pushes again, so **the latch is permanent** for all
64. `prior_rc` is read at `:521` but only printed — the retryable/terminal split ship-land itself
documents (`scripts/ship-land.sh:102-118`; 9 GATE-KILLED and 75 LOCK-STARVED are machine
non-verdicts) is unavailable here because **`cloud-reconcile.sh:79` collapses every lander non-zero
to 70**: *"a lander non-zero is always reported as 70"*.

### #4 — live blocker, not in the plan doc: next3's control-plane token is expired

```
{"outcome":"abstain","why":"control plane unreadable",
 "err":"cloud-create-api: HTTP 401 … OAuth access token has expired. Re-authenticate to continue.",
 "rc":"4","account":"next3"}                                    # ×22 on 2026-09-04
```

`scripts/cloud-create-api.py:175-196` reads `claudeAiOauth.accessToken` from the account keychain
item **verbatim**; `grep -c refresh scripts/cloud-create-api.py` = **0**. So a stored access token
that has aged out returns 401 forever even though `claude-accounts` reports next3 as `● live` (the
CLI refreshes on use; this reader does not). **216 of 547 pending rows (39%) are on next3.** The
same signature hit `next` on 08-21/08-22 (9+5 rows) and `next4` on 08-25 — it recurs per account.

### RULED OUT — do not spend a wave on these

- **The `cc-notify: target '5' is UNKNOWN` wake failure is NOT a blocker.** `bin/cc-notify:967`
  states the rc for `unresolvable` is deliberately **3**, and `cloud-return.sh:829` latches on
  `wrc2 == 0 || wrc2 == 3`. Of the 13 returned rows carrying that text, the non-latched ones are
  blocked by `done_unsettled`, not by the wake.
- **The cursor is not stuck.** It advances 25/pass and wraps (`cursor_from/to` 157→182→207→208→233,
  `.return.cursor` = 233 of 543). Full rotation ≈ 1.4 days. Coverage is not the defect.
- **The 900 s SIGKILL is not a land failure.** 6 of 8 `cloud_return_rc` today are 137, but §3e
  already attributed that to `timeout` killing its own process group, and `pass-deadline` shows the
  pass stopping cleanly first.

> **Instrument note (my own error, corrected in-flight).** My first classification grepped the
> artifacts for `LOCK-STARVED` and scored **37 of 46** — wrong. That string is in desk-land's
> *legend line*, printed on **every** refusal (`… 9 GATE-KILLED · 75 LOCK-STARVED …`). Anchoring on
> `ship rail exited N` inverted the answer: 0 lock-starvation, 31 rebase conflicts. Same shape as
> this repo's `greedy-anchor-matches-the-longer-token`.

---

## 3. The minimal change set — and what is ALREADY on trunk

| # | change | file:line | status on trunk |
|---|---|---|---|
| A | wire the landed-branch pruner + a retire pass into the sweep | `scripts/branch-prune-landed.sh` | **BUILT, ZERO CALLERS** |
| B | dispatcher admission gate on pending-unlanded | `bin/cc-dispatch` (after `CLOUD_CEILING`, :423) | **NOT BUILT** |
| C | stop a cut land poisoning its own price | `scripts/cloud-return.sh:596`, `:202` | **NOT BUILT** |
| D | propagate the ship-rail rc instead of constant 70 | `scripts/cloud-reconcile.sh:738,748,819` | **NOT BUILT** |
| E | refresh (or fail loudly on) the control-plane token | `scripts/cloud-create-api.py:175-196` | **NOT BUILT** |
| F | wire `thrash-block-recover.sh` | `scripts/thrash-block-recover.sh` | **BUILT, ZERO CALLERS** |

**A — retire the terminal third of the pile (largest single win, code already written).**
`scripts/branch-prune-landed.sh` deletes remote branches whose every commit is patch-equivalent on
trunk, and fills the path set before deleting. `grep -rn 'branch-prune-landed' bin scripts hooks
~/Library/LaunchAgents` returns **only comments** (`bin/cc-cloud:117,163,391`) — it is scheduled
nowhere. `cc-cloud gc` (`bin/cc-cloud:995`) archives cold *retired* declarations but never retires
any, so it cannot reach this population either. Sampling 40 origin fire branches (deterministic
shuffle; `git rev-list --count origin/main..origin/<b>` + `git log origin/main --grep='Original-branch: <b>'`):
**7 empty (17.5%) · 9 already content-on-trunk (22.5%) · 24 genuinely unlanded (60%)** — so ~40% of
the 405 origin branches are terminal, plus the 183 managed rows with no branch at all. Retiring
those shrinks the working set **547 → ~330** and removes them from the cursor permanently.

**B — the admission gate. Its stated precondition is now MET.** `git log -S 'pending_unlanded'` and
`-S 'CC_DISPATCH_CLOUD_PENDING_MAX'` both return **0** — nothing like this exists.
`bin/cc-dispatch`'s only sibling guard is the `wasDone` DONE-GUARD (`:18, :1827, :3330`), and the
dispatcher never reads the decl store's `item=` link at all. §3b item 5 is filed as
`96e532227df8` (`add` 2026-09-01T06:23, `venue` 14 s later, **never claimed**), gated on the lane
showing a non-zero drain rate — which it now does (3 closes). The redundancy it targets, measured
today: **17 backlog ids own 379 of 665 declarations (57%)**, worst-case **37 fires for one id**:

```
01ab05685857 decls=37   0c8b39b67665 decls=32   e981656df348 decls=30   f85fce7c26f5 decls=30
70ed289c10fb decls=28   b60eb29e97dd decls=24   70f0001c657b decls=24 (and it is DONE)
```

`70f0001c657b` was closed on 09-02 **and again on 09-04** while carrying 24 declarations. Gate on
"an unlanded `claude/fire-*` branch is already declared against this item" — disk-only via the decl
store, per the filed row's own shape.

**C — the price floor.** `cloud-return.sh:596` writes `BOUND_S - elapsed` before the land so a cut
records a lower bound. That is right in intent and wrong in magnitude: it can write 652 s into a
720 s budget, after which `:551-556` refuses every land for `COST_TTL_S` = 6 h (`:202`). Cap the
pre-land floor at the *global* observed price (`.return.land_cost`, currently 194) rather than the
remaining bound, or expire a floor-written value on a much shorter TTL than a completed one. Without
this, one cut costs ~6 hours of the lane.

**D — rc 70 is a lossy collapse, not a bug to hunt.** `cloud-reconcile.sh:73-88` documents that it
never propagates the lander's code. Exit with the child's rc at `:738`, `:748`, `:819` (the artifact
already parses `ship rail exited N`) so `cloud-return.sh:517` can refuse to cache a retryable 9/75.
On today's evidence this is the *smallest* of the six — 0 of 64 artifacts are lock-starved — so ship
it for correctness, not for throughput.

**E — the token.** Operator-owned in the short run (`/relogin next3` or an account touch);
structurally, `cloud-create-api.py` should refresh, or at minimum classify 401 as a **lane-wide**
abstention rather than 216 identical per-session ones.

**F — `thrash-block-recover.sh`** (180 lines, `--apply`, re-derives per item) has zero callers:
`grep -rn` finds only `bin/cc-backlog:164,320,2084,2731` comments. Live churn over 7 days:
**251 block · 176 unblock · 228 claim over 23 distinct ids** (7.5× reclaim per id).

**Ordering.** A and B first — they are the only two that change the *arithmetic*. A empties a third
of the rotation using code that already exists; B stops the refill. C, D, E, F improve the yield of
whatever remains and are worthless while the pile grows +23.5/day.

---

## 4. Verdict

**PAUSE, don't tune.** `CC_DISPATCH_VENUE_ONLY=cloud` + `CC_FIRE_CLOUD=on`
(`com.claude.dispatcher.plist:98`) currently routes **100%** of autonomous dispatch into a lane that
produced **5 of the last 51 backlog closes (9.8%)** at ~0.81× local cost per session, while the
local lane produced **65** attributed closes to cloud's **3**. Pausing does not stop autonomous
work: the plist's own line 48 names `CC_DISPATCH_VENUE_ONLY=local` as the rollback.

Numbers that decide it: **+23.5 pending/day in, 1.3 returns/day out, 543 deep, ~400-day drain
horizon, 0 land successes in 1,000 recorded land attempts** (`land_rc` = 758×70, 239×65, 3×143, no
zeros). Turn it back on when A + B are landed **and** `backlog-telemetry.sh` reports
`lane=cloud` closes rising with `pending_total` falling on consecutive days — not on a single
`cloud_return_rc: 0`, which §3h already showed is satisfiable by a quiet box.
