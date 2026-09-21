# W6b — rank → assign → probe, serialized; and a pool instead of a queue

**Worktree** `/Users/chrisren/Development/.worktrees/wt-lr-w6b` · **base** `5cf74150c` (the W5
merged tip) · **commits** `930bcacf4` (code + tests) · `e5dd25727` (handoff-fire, comment only) ·
`0d2a64e54` (a test that could not see its own mutant) · `3946d8103` (SC2030 tidy-up) · this
report last.

**One line.** `lr-fleet.sh` now asks the router's RECOVERY lane, charges the account it picks,
parks with the router's own reasons instead of its own prose, runs rank → assign → probe under one
mutex, and drives `--recover` as a pool of `LR_RECOVER_MAX_CONCURRENT` (default 2) workers that
claim the next session the moment one exits.

**And it fixes a defect nobody had seen.** `lf_one` read the picker through `$( )`, so every
global `lf_pick_target` set died in that subshell. The `targets already hold this sid: …` park
note — landed 2026-09-20 with its own passing case — could never once fire from `lf_one`. § 6.

---

## 1. What changed, by file:function

### `scripts/limit-recover/lr-fleet.sh`

| anchor (post-change) | change |
|---|---|
| `:76-82` | `LF_ADMIT_LOCK="$STATE/admit.lock"` and `RUN_CLAIMS="$STATE/runs/by-sid"` — the same store, by the same name, that `lr-reset-poller.sh:167` and `bin/cc-lr:48` use |
| `lf_admit_lock_take` / `lf_admit_lock_release` (new) | the admit section's mutex: `mkdir`, holder names its pid, dead holder stolen at once, live holder waited out to `LR_ADMIT_LOCK_WAIT_S` (300 s) then stolen LOUDLY; release only what is still ours |
| `lf_run_claim_take` / `lf_run_claim_release` (new) | W5's per-sid run claim as a third writer sees it — cc-lr's semantics (pid-alive ⇒ refuse, pid-dead ⇒ steal) with the poller's TTL fallback for its holder-less shape |
| `lf_rank_why` (new) | lifts the ROUTER's own reason text out of the rank's stderr; `route-meta:` is excluded — it is the decision's inputs, not its reason |
| `lf_charge_assign` (new) | `--assign <acct> --src lr-fleet`, skipped under `--dry-run`, advisory but never silent when it fails |
| `lf_pick_target` | asks `--rank <lane> --recovery --max-wait 3`, keeps stderr at `$rdir/rank.<lane>.stderr`, validates each candidate against `lib/account-map.generated.sh`, charges the winner, and **sets `LF_PICK_TARGET` instead of printing** |
| `lf_admit_section` (new, split out of `lf_one`) | the whole section, returning 0 admitted / 1 parked / 3 dry-run, so the caller can hold the lock across it with exactly ONE release |
| `lf_one` | take lock → `lf_admit_section` → release lock → actuator. The actuator is deliberately OUTSIDE |
| `lf_row` | the note is stripped of TAB/newline and cut to 600 chars — `results.tsv` became a concurrent file |
| `lf_pool_max` / `lf_pool_count` / `lf_pool_reap` / `lf_pool_wait_slot` / `lf_pool_drain` (new) | the pool |
| `case recover)` | takes the run claim, waits for a slot, backgrounds `lf_one`, tracks `pid:sid`, drains before the report |

### `scripts/handoff-fire.sh`

One comment block above the `recycle_repick` charge (`:9553-9568`). **No conditional.** § 5.

### `tests/lr-fleet.bats`

`setup()` pins `LR_RECOVER_MAX_CONCURRENT=1`, `LR_POOL_POLL_S`, `LR_ADMIT_LOCK_WAIT_S`,
`HANDOFF_ACCOUNT_SWEEP_STAMP`, `CC_HEAL_LOCK_PREFIX`, and unsets `CC_PANE_CMD_DIR` /
`CC_PANE_CMD_INTERACTIVE` / `CC_PANE_CMD`. +23 cases (66 → 89). One case renamed: *"sessions are
sequenced one at a time"* is no longer true of the driver, and what it actually pinned was that
`--max` bounds how many are STARTED.

---

## 2. The anchors I verified, and what they said

Every anchor below was read on this base before it was cited; the plan draft's own are stale (§ 5).

| claim | verified at |
|---|---|
| there is no `flock(1)` on this box | `command -v flock` → rc 1; `bin/cc-dispatch:1604` "`mkdir` is the atomic primitive (no flock on this box)" |
| `--assign` is a write-and-exit dispatched before any sweep | `bin/claude-accounts:5830-5847` |
| the recovery lane exists and is a MODIFIER | `bin/claude-accounts:2062` `recovery_floors`, `:5994` `recovery = "--recovery" in args`, `:6055` `route-meta … recovery=` |
| `--rank` prints `<acct> <score>` lines and `none` + exit 2/3 when nothing is routable | `bin/claude-accounts:6100-6102`, `:6007-6015` |
| the router's two reason shapes | `:6008-6009` ("no routable account for …") and `:6021-6023` ("<kind> excluded — …") |
| the account map returns 1 on an undeclared name and sets globals rather than echoing | `lib/account-map.generated.sh:11-26` and its header |
| the per-sid run claim's store, semantics and TTL | `lr-reset-poller.sh:167`, `:716-731`, `:835`; `bin/cc-lr:48`, `:128-158`, `:220` |
| `-maxdepth 0` on the claim directory | `lr-reset-poller.sh:719-722` |
| `bin/cc-lr` shells out to `lr-fleet --one … --detach` and `tests/cc-lr-front.bats` stubs it | `bin/cc-lr:227`, `tests/cc-lr-front.bats:48-57` |
| lr-fleet reaches handoff-fire only as a resume-launcher recycle | `lr-handoff.sh:1003` |
| a non-empty `RESUME_LAUNCHER` takes the explicit arm before `recycle_repick` | `handoff-fire.sh:9701` vs `:9706`, `:9714` |
| the fire path's `--assign` is gated on `RECYCLE = 0` | `handoff-fire.sh:9975` |
| `recycle_repick` returns before its charge when the winner is the incumbent | `handoff-fire.sh:9474` |
| the admission token is minted in `lr-handoff.sh`, not in `lr-fleet.sh` | `lr-handoff.sh:799-800` (the only caller of `cc_capacity_token_mint` outside the library) |
| `kill -0` goes false once bash has reaped a background child, while `wait` still returns its status | measured on `/bin/bash` 3.2.57 and `bash` 5.3.15 — see § 7 |

---

## 3. The four things built, and why each is shaped the way it is

**(1) The recovery lane, bounded, with its stderr kept.** `--rank <lane> --recovery --max-wait 3`,
stderr to `$rdir/rank.<lane>.stderr`. A recovery is not a dispatch: `--recovery` turns on W6a's
survival floors, so an account with room for a FIRE but not for a TRANSPLANT is excluded here
rather than discovered two hours later as a re-limit. `--max-wait 3` is the router's own
wall-clock bound and nothing wraps an outer timeout around it.

**(2) The charge, and who owns it.** `--assign <acct> --src lr-fleet` on every pick, including an
explicit `--target` (that account hosts a real session too, and a fleet whose explicit targets are
invisible to the router's spread is the same defect one step removed). Skipped under `--dry-run`:
a dry run launches nothing, so a charge would tell the router about a session that will never
exist — a phantom with no body that decays only on `ASSIGN_TTL_MIN`.

**(3) The park carries the router's own reasons.** `no routable target` named the outcome and
never the cause. The note now joins, in order: destinations that already hold this session,
names the account map does not declare, and the router's own exclusion text. `route-meta:` is
skipped by name — it is a dump of the decision's INPUTS (`k_eff`, `cliff_band`, `repick_ratio`) and
putting it in front of an operator who asked *why nothing was routable* is worse than saying
nothing.

**(4) The section is serialized; the actuator is not.** rank → assign → probe under
`$STATE/admit.lock`. Concurrency makes every term that section reads stale in the SAME direction:
N workers rank the same ≤90 s-cached rows, pick the same winner, and N probes at one census all
admit (D3-safety R2). Warm the section is ~1–2 s; a cold `cc_sp_active` is 7.2 s; a capacity park
holds it for up to `LR_FLEET_CAP_WAIT_S` (120 s) — deliberately, because admitting a second
recovery while the box refuses the first is the over-admission the lock exists to prevent. The
actuator (115–658 s) stays outside, which is what leaves room for the pool.

**(5) A pool, not a queue.** `LR_RECOVER_MAX_CONCURRENT` (default 2) workers; the next is claimed
the moment ONE exits. Not a group `wait` — that idles the pool behind its slowest member — and not
`wait -n`, which `/bin/bash` 3.2 does not have and which is the interpreter `launchd` gives
`lr-reset-poller.sh`. Each worker takes W5's per-sid run claim first, so a sid the poller or
`cc-lr` is already driving is skipped with a row that says so, and releases it on exit.

---

## 4. Mutation score — 23 built, 23 killed, 0 survived

Driver: `mutate.py` (scratchpad), one mutant at a time applied IN PLACE to the real subject, the
named cases run, the subject restored and its sha256 re-verified after each. A patch that does not
apply is recorded FAILED, never skipped. Subject sha256 `855e21d…` for M1–M22 and `b31299ac…` after the M23 fix landed, unchanged at
the end of every batch.

| # | mutant | the case that died |
|---|---|---|
| M1 | drop `--recovery` from the rank argv | RECOVERY lane + FABLE lane (2) |
| M2 | drop `--max-wait 3` | RECOVERY lane |
| M3 | remove `lf_charge_assign "$cand"` | charged exactly ONCE |
| M4 | remove the `DRY` guard in `lf_charge_assign` | `--dry-run` charges NOTHING |
| M5 | drop `LF_RANK_WHY="$(lf_rank_why …)"` | ROUTER's own reasons |
| M6 | remove the account-map validation | the router naming an undeclared account |
| M7 | `lf_admit_lock_take`/`_release` → no-ops | two workers SERIALIZE the admit section |
| M8 | release predicate can never match (never releases) | a completed pool worker RELEASES its claim |
| M9 | pool → serial `lf_one … \|\| worst=1` | the ACTUATOR half is a POOL |
| M10 | remove the `lf_run_claim_take` guard | a sid a LIVE run already claims |
| M11 | dead-pid claim branch returns 1 (never steals) | a claim held by a DEAD pid is stolen |
| M12 | remove `[ "$DRY" = 0 ] &&` from the claim guard | `--dry-run` neither TAKES a claim nor OBEYS one |
| M13 | remove `lf_run_claim_release` from the reaper | a completed pool worker RELEASES its claim |
| M14 | remove `cut -c1-600` from `lf_row` | lf_row BOUNDS its note |
| M15 | remove `tr '\t\n'` from `lf_row` | lf_row keeps a tab or newline from re-columning |
| M16 | remove the dead-pid steal from `lf_admit_lock_take` | an admit lock left by a DEAD holder |
| M17 | restore the pre-wave shape: pick PRINTS and is read through `$( )` | died in a subshell + ROUTER's own reasons (2) |
| M18 | slot test `-lt 99` (pool unbounded) | `LR_RECOVER_MAX_CONCURRENT=1` is a queue again |
| M19 | remove `lf_pool_max`'s junk/zero fallback | junk + zero `LR_RECOVER_MAX_CONCURRENT` (2) |
| M20 | remove `/^route-meta:/ { next }` from `lf_rank_why` | route-meta is not a REASON |
| M21 | remove `lf_pool_drain` | drives lr-handoff --in-place (the report renders before the rows) |
| M22 | never append `$!:$sid` to `LF_PIDS` | `LR_RECOVER_MAX_CONCURRENT=1` is a queue again |
| M23 | `lf_run_claim_release` removes any claim, not only ours | `--dry-run` neither TAKES a run claim nor OBEYS one |

**Three entries need their honesty stated.**

**M12 SURVIVED on the first pass, and that is a finding about the TEST, not about the code.** The
case asserted `[ ! -d …/<sid>.active ]` *after* the run, and the pool's reaper releases the claim
when the worker exits — so the directory is gone at the end in both arms. An assertion that cannot
separate the arms is decorative. Re-aimed at the observable harm (with the guard gone, `--dry-run`
over a sid the poller is driving prints `skipped` instead of the preview) it dies. Fixed in
`0d2a64e54`, which exists so the survivor is on the record rather than quietly absorbed.

**M23 is a defect the test found in MY code, not in a mutant.** `lf_pool_reap` ran
`lf_run_claim_release` once per worker, unconditionally — and a worker can reach the reaper without
ever having taken a claim, because `--dry-run` takes none by design. So a dry run deleted whatever
claim sat at that path, which is exactly the claim `cc-lr` or the poller holds over a LIVE
recovery. It was invisible when the case was run alone and fell out on the full-file pass, after
the case had been re-aimed for M12. Fixed in `33dffb694`; the release is now ownership-checked
against its own holder file, and M23 dies on it.

**M19 killed by WEDGE, not by assertion, and I had to intervene by hand.** Without the fallback,
`LR_RECOVER_MAX_CONCURRENT=nonsense` makes `[ "$(lf_pool_count)" -lt nonsense ]` an arithmetic
error, the slot test is never satisfied, and `--recover` spins forever — measured at 16 minutes
before I killed the leaf `lr-fleet.sh --recover` (pid 54980) so bats could report the failure.
That is exactly the hazard the case names, and it is why the fallback exists: a typo in a launchd
environment would wedge the poller's whole request drain rather than degrade it. Recorded as
KILLED because the case cannot pass under the mutant, with the mechanism stated because "killed by
timeout" and "killed by assertion" are different facts.

**The one guard whose direction is argued rather than killed.** `lf_admit_lock_release`'s
ownership test (`only release a lock whose pid file still names us`) protects against releasing a
lock a PEER stole from us — which needs three parties, and the suite can construct two. Its paired
mutation is M8 (make the predicate never match), which proves the release runs at all and that the
predicate is not vacuously false. The remaining direction — that it must not release someone
else's — is argued, not measured, and is named as residual R4.

---

## 5. What the spec got wrong

| plan draft (§ W6b, `PLAN_DRAFT.md:644-658`) | the tree |
|---|---|
| `flock "$STATE/admit.lock"` | **there is no `flock(1)` on this box.** `command -v flock` → rc 1. The path is honoured; the primitive is `mkdir`, which is what `bin/cc-dispatch:1604`, `lr-reset-poller.sh`'s tick lock, `lr_state_append`'s event lock and `cc-lr`'s per-session mutex all use |
| "`--recover`/`--all` become a POOL" | **there is no `--all` mode in lr-fleet.sh.** The modes are `--locate --recover --one --enqueue --duplicates --retire-husks --report`; `--all` is `bin/cc-limited`'s flag, which lr-fleet passes through to the census. The pool is on `--recover` |
| "`handoff-fire.sh:9296` `--assign` guard" | **`:9296` is `tmp="$HF_INFLIGHT_DIR/.$key.$$"`.** The two `--assign` sites are `recycle_repick`'s (`:9569` post-change) and the fire path's (`:9977`) |
| "Today a recycle can charge an assignment that lr-fleet also charges" | **false, and the reason is control flow.** lr-fleet reaches handoff-fire only as `--recycle --transplanted-source --resume-launcher …` (`lr-handoff.sh:1003`), and a non-empty `RESUME_LAUNCHER` takes the explicit arm at `:9701`, which never enters the `auto` arm at `:9706` where `recycle_repick` is called. The fire path's charge is gated on `RECYCLE = 0` (`:9975`). So handoff-fire charges ZERO times on the recovery path |
| "skip in handoff-fire when the recycle stays on the same account" | **already implemented** — `:9474` returns before the charge when the ranked winner is the incumbent |
| "rank → assign → probe → **mint**, all under the lock" | **lr-fleet cannot hold the mint.** `cc_capacity_token_mint` is called in `lr-handoff.sh:800` — one process down, after lr-fleet has started the actuator. Holding the lock that far would serialize the 115–658 s half and delete the pool. What is serialized is rank → assign → probe; the mint is named as residual R1 |
| `--detach-inner` | still absent, as the brief said — the only occurrence in the tree is `lr-reset-poller.sh:696` saying so |

**Which owner I chose for `--assign`, and why.** lr-fleet. Not because handoff-fire was disabled
but because it was never reachable from here — the choice is recorded at BOTH sites (a comment
block above `recycle_repick`'s charge, `e5dd25727`) so the next reader finds it wherever they
start. **No conditional was added to handoff-fire.** An arm keyed on "lr-fleet already charged"
would be unreachable on every measured path: untested surface by construction, which is the thing
this project's single most important rule exists to prevent.

---

## 6. The defect found on the way: three of the picker's four outputs were unreachable

`lf_one` read the picker as `target="$(lf_pick_target "$acct" "$tier" "$sid")"` — a command
substitution, i.e. a subshell — so `LF_PICK_SKIPPED_HOLDER` (and, new in this wave,
`LF_PICK_REJECTED` and `LF_RANK_WHY`) never escaped. Consequence: the

```
lr-fleet: <sid> — no routable target: every candidate past <acct> already holds this session (…)
```

park note, landed 2026-09-20 against the real incident it was written for, **could never fire from
`lf_one`**. Every real park printed the generic `no routable target` instead. It had a passing test
because that test (`_pick`) calls the function DIRECTLY — the harness was not wrong, it was simply
blind to the caller.

Fixed by making `lf_pick_target` set `LF_PICK_TARGET` and print nothing, which is the house pattern:
`lib/account-map.generated.sh`'s `cc_acct_dir_for_name` header already says *"Sets globals rather
than echoing: callers that need the fable flag cannot invoke this via `$(...)` command substitution
— that runs in a subshell, so a side-channel var set there never reaches the caller."* Pinned
end-to-end by *"the holder-skip park note reaches the ROW"*, which goes through `--recover` rather
than the harness; M17 restores the old shape and kills it.

**The generalisable half** (repo memory already has the mechanism —
`assignment-inside-command-substitution-never-escapes` — this adds the detection rule): a function
with ONE return channel can be read through `$( )`; a function with a return channel AND
side-channel globals cannot, and a test harness that calls it directly can never see the
difference. When a function grows its second output, its callers are the thing to re-read.

---

## 7. Measurements taken for this wave

**`kill -0` vs `wait` on a reaped background child**, because the pool's reaper depends on it and
`wait -n` is unavailable:

```
/bin/bash 3.2.57   kill -0 FAILS after exit (reaped) · wait rc=7 · second wait rc=7
bash     5.3.15    kill -0 FAILS after exit (reaped) · wait rc=7 · second wait rc=7
```

So bash's own SIGCHLD reaper clears the pid before the poll sees it, and `wait` still returns the
remembered status — which is what lets `lf_pool_reap` free the slot AND fold the worker's rc into
the run's verdict without `wait -n`.

**The poll is a ceiling on claim latency, not a floor on the run.** `lf_pool_wait_slot`'s guard is
*"the pool is FULL"*, which is false whenever a slot is free, so a caller with room never enters
the body. The shape the `poll-period-charged-as-a-cost-floor` lesson warns about is the one whose
guard is *"the child is alive"*; this is not it.

---

## 8. Suites, with their plan lines

Run on the final tree. `bats` exits 75 under admission pressure and that is a DEFERRAL, not a
result — every run below was retried until it returned a real rc, and the `1..N` line is asserted
because a refused suite emits no `not ok` and exits 0.

| suite | plan line | result |
|---|---|---|
| `tests/lr-fleet.bats` | `1..89` (66 before this wave) | all ok |
| `tests/cc-lr-front.bats` | `1..32` | all ok — `bin/cc-lr recover`'s stub of `lr-fleet --one` is unaffected: `--one`'s CLI is unchanged |
| `tests/lr-reset-poller-requests.bats` | `1..24` | all ok — the poller's own run claim is untouched |
| `tests/lr-handoff-inplace-default.bats` | `1..6` | all ok |
| `tests/lr-lib.bats` | `1..46` | all ok |
| all five in one invocation | **`1..197`, 197 ok, 0 not ok, rc 0** | the number reported |

Static gates on the final tree:

```
shellcheck -x scripts/limit-recover/lr-fleet.sh      rc 0   (DEFAULT severity — no -S warning)
shellcheck -x scripts/handoff-fire.sh                rc 0
shellcheck -x tests/lr-fleet.bats                    2 findings, both pre-existing on the base
bash -n / /bin/bash -n on both .sh                   clean (5.3.15 and 3.2.57)
scripts/test-hermeticity-lint.sh tests               rc 0 — 721 suites, 0 new leaks
scripts/pipefail-sigpipe-lint.sh                     rc 0
scripts/bats-assert-liveness.py                      rc 0
```

`tests/lr-fleet.bats` carried 2 shellcheck findings on the base (SC2030/SC2031 over `CC_ADMIT_IDL`)
and carries the same 2 now: the wave briefly added two more of that class and `3946d8103` removed
them by exporting `LRH_SEQ` from `setup()` instead of from the two cases that use it.

---

## 9. Residuals, each with the command that re-measures it

**R1 — the MINT is still outside the serialized section, and it is the half that spends budget.**
`lr-fleet`'s lock covers rank → assign → probe. `cc_capacity_token_mint` is called in
`lr-handoff.sh:800`, after lr-fleet has started the actuator, and `lr-handoff` runs its OWN
`lr_capacity_probe_corrected` at `:792` immediately before it. So with a pool of N, up to N
lr-handoff probes still read one census concurrently — D3-safety R2 is narrowed from N to the pool
width, not closed. The fix is one named lock around `lr-handoff.sh:790-810`, using the same
`$STATE/admit.lock` path, and `lr-handoff.sh` is outside this wave's file set.

```
grep -n 'lr_capacity_probe_corrected\|cc_capacity_token_mint' scripts/limit-recover/lr-handoff.sh
```

**R2 — the admit lock's park bound is the pool's worst case.** A worker that parks on capacity
holds the section for up to `LR_FLEET_CAP_WAIT_S` (120 s), so a pool of 2 against a full box costs
~240 s of serialized parking rather than ~120 s of parallel parking. Deliberate — admitting a
second recovery while the box refuses the first is the over-admission the lock exists to prevent —
but it is a real cost and the knob is one variable.

```
grep -n 'LR_FLEET_CAP_WAIT_S\|LR_ADMIT_LOCK_WAIT_S' scripts/limit-recover/lr-fleet.sh
```

**R3 — `lf_pool_wait_slot` has no bound of its own.** What stops it spinning is that BOTH operands
are normalised integers: the configured side by `lf_pool_max` (M19), the counted side by
`lf_pool_count`'s own arithmetic. A third source of junk would reopen it. No such source exists
today; the claim is a survey, not a proof.

```
grep -n 'lf_pool_max()\|lf_pool_count()\|lf_pool_wait_slot()' -A6 scripts/limit-recover/lr-fleet.sh
```

**R4 — `lf_admit_lock_release`'s ownership test is argued, not measured.** Its paired mutation (M8,
predicate can never match) dies, which proves the release runs and the predicate is not vacuously
false. The direction it actually guards — never release a lock a PEER stole from us — needs three
parties and the suite can build two. Its sibling in `lf_run_claim_release` IS measured (M23), which
is the closest evidence available that the shape is right.

```
bats -f 'RELEASES its claim|neither TAKES a run claim' tests/lr-fleet.bats
```

**R5 — the drill's row 4 (targets spread across ≥2 accounts inside one 90 s TTL) is not asserted
here.** It needs `tests/lr-drill.sh`, which is W7's and is operator-launched because it spends
quota and types into panes. What IS asserted here is the mechanism the row depends on: the charge
lands exactly once per pick, and two workers cannot rank concurrently.

```
bats -f 'charged exactly ONCE|SERIALIZE the admit section' tests/lr-fleet.bats
```

**R6 — `--recover`'s stderr interleaves at concurrency ≥2.** Each worker narrates its own progress
and the lines cross. The rows in `results.tsv` do not (bounded record, `lf_row`), and the report is
rendered after the drain, so the ARTIFACT is ordered even when the stream is not. Naming it because
someone reading a live `--recover` at concurrency 2 will notice, and will otherwise suspect the
pool of something worse.

```
LR_RECOVER_MAX_CONCURRENT=2 bash scripts/limit-recover/lr-fleet.sh --recover --dry-run
```

---

## 10. Knobs this wave introduced

| variable | default | what it does |
|---|---|---|
| `LR_RECOVER_MAX_CONCURRENT` | `2` | pool width for `--recover`; junk or `0` falls back to 2 rather than wedging |
| `LR_POOL_POLL_S` | `0.2` | how often the reaper looks for a freed slot — a ceiling on claim latency |
| `LR_ADMIT_LOCK_WAIT_S` | `300` | how long a live holder of the admit section is waited out before a LOUD steal |
| `LR_RUN_CLAIM_TTL_MIN` | `30` | already the poller's; read here too, so the two agree on when a holder-less claim is stale |
