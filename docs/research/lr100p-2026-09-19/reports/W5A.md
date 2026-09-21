# W5-A — the poller's request lane

**Branch worktree** `/Users/chrisren/Development/.worktrees/wt-lr-w5a`, off `ea5012b30`.
**Commits** `2892ffecd` (implementation + suites) and this report.

---

## 1. What changed, and why

Five changes across `scripts/limit-recover/lr-reset-poller.sh` § 0 and § 2 and one new predicate in
`scripts/limit-recover/lr-lib.sh`. Four of them close defects that were live on trunk.

### 1.1 The worker ran in the FOREGROUND, inside the tick lock

`:680` ran `"$FLEET" --one …` in the foreground of `LOCKD`. `lr-fleet.sh:725` prices `--one` at
115–658 s, so **one request held the self-overlap lock for minutes** and every concurrent tick
TICK-SKIPped — the overlap guard doing its job over a lock that should never have been held that
long. The fix is `--detach` (`lr-fleet.sh:90` flag, `:739-768` implementation): it re-execs the
driver under `setsid` via `scripts/lib/detach.sh`, returns in ≤ 3 s, and mails the verdict. It
**refuses** rather than silently blocking when it cannot reach `detach.sh` (`:748`), so passing the
flag can never quietly degrade back to the foreground.

Consequence recorded honestly in the result file: `rc` now means *the dispatch* rc, not *the
recovery* rc, so the result JSON gained `mode` and `verdict` fields and the log line reads
`REQUEST <sid> — dispatched rc=0` rather than `done rc=0`.

### 1.2 A real per-sid claim

There was nothing between reading a record and driving it that reserved the sid. `mkdir
$STATE/runs/by-sid/<sid>.active` is the atomic reservation that `: >` never was — `claim_sid`
(`:225-226`) is `: > "$CLAIMS/$1" || true`, where two writers both "win"; that one guards the SPAWN
path and is **untouched**. A second tick over a held sid logs `SUPERSEDED-BY-LIVE-RUN` and drops the
request (the brief's own snippet: `rm -f`).

The drained request is **moved** to `$STATE/claimed/`, not deleted: a consumed request that reached
nobody was previously indistinguishable from one that was never written.

### 1.3 The hook-origin policy gate (new, safety-critical, fails closed)

`requested_by == stop-failure-marker` drains **only** when `$STATE/autorecover.on` exists. Absent ⇒
`continue`, leaving the record in place, unclaimed and undeleted, as the breadcrumb `cc-find
--limited` reads. The daemon never creates that file. Held requests are reported as **one** summary
line per tick (`HOOK-HELD <n> …`), never one line per request per tick — a thirty-strong cohort at a
10-minute cadence is 4,320 identical lines a day, and this daemon has already produced that shape
once (1,800 lines, § the fire-failure latch).

### 1.4 Dispatch on the record's shape, never on the glob

`:1105-1107` writes `retire-husk-<sid>.json` **into `$REQUESTS`**, and the loop globbed `*.json`, so
a request to CLOSE a pane was driven through `lr-fleet --one` as if it were a recovery. Now `.kind`
is read: `retire-husk` is filed to `$STATE/husk-requests/` (a new lane — see § 6, there are **zero**
readers of it in `$REQUESTS` today), unknown kinds park as `<name>.unknown-kind.json`.

`.mode` added: `relaunch` (default when absent) and `prompt` (the C14 repair — re-type into a live
composer via `cc_tui_submit <pane> <file>`). The `cc-tui.sh` source is guarded and **skips loudly**
when the file is not on this layer, because an ADD is absent-not-stale until a converge and a
`[ -f x ] && . x` guard over one is a silent skip. It is sourced in a **subshell**: `cc-tui.sh` is
another wave's file and this daemon already defines `log`, `lrp_bounded` and a dozen more at global
scope.

### 1.5 Retire only on RECOVERED

`:1110`'s `mv "$pf" "$RESUMED/…"` was unconditional on the transplant **read**, and the HUSK branch
(`:1096-1103`) logged `HUSK … retire request written` and then **fell through to the same `mv`** —
the poller retired the very records its own log said it was not retiring. A tombstone says the
session MOVED; it says nothing about whether the successor took a turn, and a move that produced
nothing is exactly the case where the parked record is the only thing that would re-fire.

Retire now requires one of:
1. `lr_state_current "$bundle"` == `RECOVERED` — newest `$STATE/<sid>/bundle-*` (ISO names sort
   lexically == chronologically). **This is that function's first production caller in the tree.**
2. a live registry row under the **TARGET** cfg — `lr_registry_live_rows_in_cfg`, new in `lr-lib.sh`.

Otherwise: `HUSK <sid> (run <bundle> state <S>) — … record LEFT PARKED`, damped to once per record
via `$PARKED/<sid>.husk-noted` (cleared with `.notified` on a later genuine retire).

**One ordering change the brief did not call out, and it is a safety property:** the gate is
evaluated **before** the husk-retire-request block, not after. Writing "close the source pane" for a
session whose successor never came up would ask to close the only live thing left.

**Why a new lr-lib predicate was required.** `lr_registry_live_rows` (`lr-lib.sh:280`) takes only a
sid, so on this question it is not merely imprecise — it is *inverted*: a live row on the SOURCE
account returns the same yes while meaning the opposite (that row **is** the husk). The new function
carries the `.claude`/`.claude-next` mirror fold lifted from `lr_husk_state`, because
`hooks/session-register.sh` writes `.account` as `basename $CLAUDE_CONFIG_DIR` and 2 of the 3 husks
W10 measured carried exactly that mismatch.

---

## 2. Verified anchors actually used

Every line below was re-read at `ea5012b30` before it was cited.

| anchor | verdict |
|---|---|
| `lr-reset-poller.sh:127-128` STATE/PARKED/RESUMED/LOG | ✅ exact |
| `:160` `REQUESTS`/`RESULTS` + `mkdir -p` | ✅ exact — `CLAIMED`/`RUN_CLAIMS` added here |
| `:187-205` LOCKD, steal-on-stale by (pid,lstart), trap | ✅ |
| `:216-233` `sid_claimed()` / `claim_sid()` | ✅ |
| `:225-226` `claim_sid` is `: >` with `|| true` — not atomic | ✅ exact, and **untouched** |
| `:258-294` the fire-failure latch | ✅ (the damping precedent both new log-damps cite) |
| `:304` `MAX_PER_WT`, sole consumer `:1043` | ✅ — **not touched** |
| `:664-685` THE REQUEST LOOP | ✅ exact |
| `:680` the foreground worker | ✅ exact |
| `:816-824` the CLAIM reaper (`cc-limited --reaper`) | ✅ — not mine, untouched |
| `:1083-1110` the TRANSPLANT retire, `:1110` the `mv` | ✅ exact |
| `:1105-1107` writes `retire-husk-<sid>.json` into `$REQUESTS` | ✅ exact |
| `:1150-1170` the WINNER retire (`WINNER_SIDS` at `:1150`, `LISTED` at `:1165`) | ✅ — untouched |
| `lr-lib.sh:280` `lr_registry_live_rows` — sid only | ✅ exact |
| `lr-lib.sh:439` `lr_state_current` — EXISTS and is INERT | ✅ exact; callers were `tests/lr-lib.bats:226,:247` only |
| `lr-fleet.sh:90` `--detach` flag · `:723-763` impl · `:748` refusal | ✅ (impl block runs `:739-768`) |
| `lr-fleet.sh:725` prices `--one` at 115–658 s | ✅ exact |

Two anchors in the brief point **inside a function's header comment** rather than at its definition:

| brief said | tree says |
|---|---|
| `lr-lib.sh:537 lr_transplant_target` | the function is at **`:543`**; `:537` is a comment line in its header |
| `lr-lib.sh:590 lr_husk_state` | the function is at **`:596`**; `:590` is a comment line in its header |

---

## 3. The request-record schema — for W5-F and W5-D

Fixed **here, by the consumer**, and documented in the file at `lr-reset-poller.sh` § 0.

| field | required | default | read by |
|---|---|---|---|
| `.sid` | **YES** | — | every mode. Absent or unreadable ⇒ parked `<name>.malformed.json` and **never retried** |
| `.kind` | no | `recovery` | `recovery` ⇒ drive; `retire-husk` ⇒ filed to `$STATE/husk-requests/`, never executed; anything else ⇒ parked `.unknown-kind.json` |
| `.mode` | no | `relaunch` | `relaunch` \| `prompt`; anything else ⇒ parked `.unknown-mode.json` |
| `.target` | no | `auto` | relaunch → `lr-fleet --target` |
| `.source_pane` | relaunch: no · **prompt: YES** | — | relaunch → `--source-pane`; prompt → the pane to type into (absent ⇒ parked `.malformed.json`) |
| `.requested_by` | no | `?` | recorded in the result; **`stop-failure-marker` is POLICY-GATED on `$STATE/autorecover.on`** |
| `.prompt_file` | no | — | prompt: an existing path to type |
| `.prompt` | no | `/limit-recover` | prompt: inline text, used when `.prompt_file` is absent or missing. Read by its **own** `jq -r`, so a multi-line prompt survives verbatim |

**Result** at `$RESULTS/<sid>.json`: `{sid, rc, ts, log, requested_by, mode, verdict}`.
`verdict` ∈ `dispatched` · `dispatch-failed` · `submitted` · `no-such-pane` · `unreadable-or-modal`
· `composer-occupied` · `paste-not-echoed` · `sent-but-no-record` · `rc-<n>`.
🚨 **W5-F / W5-D, read this:** for `mode:relaunch` an `rc` of 0 means the driver was **dispatched**,
not that the recovery succeeded — `--detach` returns before the work. The recovery's own verdict
arrives as mail; `$RESULTS/<sid>.log` holds the dispatch banner with lr-fleet's `run=`/`log=` paths.

New stores, all created at `:160`/on demand: `$STATE/claimed/` (drained requests),
`$STATE/runs/by-sid/<sid>.active` (the run claim), `$STATE/husk-requests/` (filed breadcrumbs).
New env knobs: `LR_RUN_CLAIM_TTL_MIN` (default 30), `LR_CC_TUI_LIB` (test seam; when **set** it is
the whole ladder, so a suite can name an absent path).

---

## 4. Mutation table

**25 primary mutants built · 22 killed · 3 survived, all three equivalence guards whose killing
mutation was then built and run (4 further probe mutants, all 4 killed).**

Method: one mutant at a time, applied by exact single-occurrence string replace, subject restored
and **sha256-verified** after every one; the tree was confirmed byte-identical to `HEAD` at the end.
A `cc-bats` DEFERRAL (rc 75) emits no TAP and no `not ok`, so it would score as a false SURVIVED —
every run therefore asserts the expected `1..N` plan line and a shed is retried, never counted.

| # | arm mutated | mutation | verdict | killed by |
|---|---|---|---|---|
| M1 | `--detach` on the fleet argv | drop it | **KILLED** (3) | *detach: the dispatched argv carries --detach* · *detach RED-PROOF: a worker that blocks for 20 s does not hold the tick* · *dispatch that FAILS releases the claim* |
| M2 | the run claim gate | `if false` (never superseded) | **KILLED** (4) | *claim: a drained request leaves an .active claim* · *two ticks over one request* · *TTL retake* |
| M3 | claim TTL window | `-mmin +999999` (never stale) | **KILLED** (1) | *a claim older than the TTL is retaken* |
| M4 | release on dispatch failure | drop the release | **KILLED** (1) | *a dispatch that FAILS releases the claim* |
| M5 | release after `mode:prompt` | drop the release | **KILLED** (1) | *maps cc_tui_submit's rc onto a NAMED verdict, and frees the sid* |
| M6 | `mv` → `claimed/` | back to `rm -f` | **KILLED** (3) | *lands in claimed/* · *WITH the flag the same request drains* · inplace *REQUESTS … MOVED to claimed/* |
| M7 | hook gate, requester conjunct | match a name nothing uses | **KILLED** (2) | *NOT drained without the flag* · *cohort held and reported as ONE line* |
| M8 | hook gate, `autorecover.on` conjunct | drop it (gate always holds) | **KILLED** (1) | *WITH the flag the same request drains* |
| M9 | `HOOK-HELD` summary line | `log` → `:` | **KILLED** (2) | *NOT drained without the flag* · *ONE line, not one per request* |
| M10 | kind dispatch, `retire-husk` arm | route it into the recovery arm (the pre-wave defect) | **KILLED** (1) | *a retire-husk breadcrumb is FILED, never executed* |
| M11 | kind dispatch, unknown arm | fall through | **KILLED** (1) | *an unknown kind is PARKED, not driven* |
| M12 | mode dispatch, unknown arm | fall through | **KILLED** (1) | *an unknown mode is PARKED, not driven* |
| M13 | cc-tui presence guard | `if false` | **KILLED** (1) | *mode:prompt with no cc-tui.sh SKIPS LOUDLY* |
| M14 | `mode:prompt` source_pane guard | `if false` | **KILLED** (1) | *without .source_pane is malformed, not a guess* |
| M15 | reader guard, empty-sid arm | drop it | **KILLED** (1) | *a record with no .sid is parked as malformed* |
| M15b | reader guard, **field-count arm** | drop it | **SURVIVED** | see below |
| M16 | retire gate leg 1 (`== RECOVERED`) | compare to a value nothing emits | **KILLED** (1) | *a run whose own state log reads RECOVERED retires* |
| M17 | retire gate leg 2 (target registry row) | `if false` | **KILLED** (1) | *a lock to ANOTHER store + a LIVE row there retires* |
| M18 | the retire gate itself | `if false` (restores the unconditional `mv`) | **KILLED** (4) | all three TRANSPLANTED CONTROLs + the once-per-record case |
| M19 | `.husk-noted` damping | `if true` (log every tick) | **KILLED** (1) | *the LEFT-PARKED line is said ONCE per record* |
| M20 | `lr_registry_live_rows_in_cfg`: row-side mirror fold | delete | **KILLED** (1) | *the .claude / .claude-next MIRROR is ONE account* |
| M21 | same: cfg-side mirror fold | delete | **KILLED** (1) | *the .claude / .claude-next MIRROR is ONE account* |
| M22 | same: the account filter | delete | **KILLED** (2) | *a live row on the NAMED store is a hit* · *it FILTERS, it does not merely pass through* |
| M23 | same: the two-argument guard | delete | **SURVIVED** | see below |
| M24 | same: `${cfg%/}` | drop the strip | **SURVIVED** | see below |

### The three survivors, and the mutation each one DOES die on

**M15b — the `${#_rqf[@]} != 7` arm is an EQUIVALENCE GUARD.** The python reader writes all seven
fields in one `sys.stdout.write` or, on any exception (bad JSON, non-dict top level), writes nothing
— so no reachable input yields 1–6 fields, and the empty-sid arm already covers the zero case. It is
a fail-closed guard against a **reader/consumer desync**, and that is exactly what it dies on:

- **M15c** — reader emits 3 keys, count arm **present** → **KILLED, 18 of 24**: every record parks
  as malformed, which is the safe outcome the arm exists to produce.
- **M15d** — the same 3-key reader with the count arm **removed** → **KILLED, 20 of 24**: `${_rqf[4]}`
  is unbound, `set -u` kills the whole tick. The arm is what makes a desync a parked record instead
  of a dead daemon.

**M23 — the `[ -n "$sid" ] && [ -n "$cfg" ] || return 1` arm is an EQUIVALENCE GUARD.** With it gone,
an empty `cfg` yields `want=""` which matches no account (rc 1), and an empty `sid` is refused by
`lr_registry_live_rows`'s own guard (rc 1). It buys an explicit, one-stat refusal, not a different
answer. Its polarity is pinned:
- **M23b** — `|| return 0` → **KILLED**: *a missing argument is rc 1, never a wildcard match*.

**M24 — `${cfg%/}` is an EQUIVALENCE GUARD**, because `basename(1)` already strips trailing slashes.
The case pins the *derivation*, and a derivation that does not strip dies:
- **M24b** — `want="${cfg##*/}"` → **KILLED**: *a trailing slash on the cfg path does not change the
  account it names*.

### Re-run the pass
```
bash /tmp/w5a-mutation-harness/w5a-catalogue-frozen.sh M1 M2 M3 …   # the 25
bash /tmp/w5a-mutation-harness/w5a-probes.sh M15c|M15d|M23b|M24b    # the 4
```

---

## 5. Suites run, with plan lines

| suite | plan | result |
|---|---|---|
| `tests/lr-reset-poller-requests.bats` (**new**) | `1..24` | 24 ok |
| `tests/lr-reset-poller-inplace.bats` (extended 14 → 19) | `1..19` | 19 ok |
| `tests/lr-lib.bats` (extended 40 → 46) | `1..46` | 46 ok |
| `tests/lr-reset-poller.bats` | `1..38` | 38 ok, unchanged |
| `tests/lr-reset-poller-consolidate.bats` | `1..10` | 10 ok, unchanged |
| `tests/lr-reset-poller-engagement.bats` | `1..14` | 14 ok, unchanged |
| `tests/lr-reset-poller-overlap.bats` | `1..9` | 9 ok, unchanged |

Post-mutation confirmation: the three touched suites re-run together as `1..89`, 0 `not ok`, with
`git diff HEAD` empty.

Gates, all clean: `shellcheck -S warning -x` on both `.sh` and all three `.bats`; `bash -n` and
`/bin/bash -n` (3.2) on both `.sh`; `scripts/pipefail-sigpipe-lint.sh`; `scripts/bats-assert-liveness.py`.

---

## 6. What the spec got wrong

1. **`--detach-inner` does not exist.** Confirmed: the only occurrence in the tree is
   `PLAN_DRAFT.md:571`. `--detach` is what shipped. *(The brief already flagged this; recorded as
   verified.)*

2. 🚨 **`lr_state_current "$bundle" == RECOVERED` is INERT against the tree as built** — the plan's
   headline predicate cannot fire today. **No writer in this tree ever appends the state
   `RECOVERED`.** The live vocabulary, read off every `events.jsonl` on this box, is
   `admitted` · `gate-admitted` · `submit-token-armed` · `relaunch-typed` · `FAILED` ·
   `FAILED:submit`. Worse, **only 4 of ~140 sid dirs carry an `events.jsonl` at all**, so for ~97% of
   parked records the leg cannot even be evaluated. The gate is therefore carried entirely by the
   second disjunct (a live registry row on the target). Leg 1 is implemented and tested anyway,
   because it is the specified predicate and it goes live the day a writer emits the value — but a
   report that said "retire only on RECOVERED" without this paragraph would be describing a program
   nobody shipped. Re-derive:
   ```
   jq -r .state $(find ~/.reso/limit-recover -name events.jsonl) | sort -u
   ```

3. **`$REQUESTS/retire-husk-*.json` has ZERO readers.** `git grep retire-husk- ea5012b30` returns
   exactly one hit — the writer at `:1107`. So the record was written into a directory whose only
   consumer executed it as a recovery, and nothing else ever looked. Filing it into
   `$STATE/husk-requests/` is a decision I made as the consumer; the **writer is unchanged**, so the
   documented location is preserved and the routing happens on the next tick. If a future
   `--retire-husks` consumer is written, `$STATE/husk-requests/` is where these now live.

4. **`autorecover.on` is read nowhere at base.** Confirmed — every `autorecover` hit in the tree is
   docs/plans prose or `cc-reaper`'s unrelated `SAFEGUARD_AUTORECOVER`. This gate is 100% new, and
   the file is not created by anything I wrote.

5. **Two lr-lib anchors point at header comments, not definitions** — see § 2.

6. **`tests/lr-reset-poller-inplace.bats:138` also pinned the defect, and the brief only anticipated
   `:198`.** The `TRANSPLANTED` case asserted that a lock naming another store retires the record,
   full stop — which *is* the behaviour § 1.5 removes. It was **extended, not deleted**: the original
   assertions survive verbatim in the positive case, now with the successor evidence its premise
   always implied, and three CONTROLs were added beside it. The `:198` request-lane case keeps its
   original `[ ! -f requests/… ]` assertion and gains `[ -f claimed/… ]` and `--detach`.

---

## 7. Residuals

Each with the command that re-measures it.

1. **The run claim has no reaper; it is TTL-only (30 min).** The run reaper is the sibling plan's and
   is out of scope here. A driver that dies mid-run holds its sid out of recovery for up to
   `LR_RUN_CLAIM_TTL_MIN`. 30 min ≈ 2.7× lr-fleet's own worst case (658 s) and ≈ 3 ticks. When the
   reaper lands, it should `rm -rf "$STATE/runs/by-sid/<sid>.active"` on any terminal state and the
   TTL becomes a backstop.
   ```
   ls -ld ~/.reso/limit-recover/runs/by-sid/*.active 2>/dev/null; date
   ```

2. **`mode:prompt` is untested against the real `cc-tui.sh`** — W5-E is writing it this wave and it
   was absent from this worktree throughout. My suite pins the contract (`cc_tui_submit <pane>
   <file>`, rc 0–5 → named verdicts) against a stub. First real exercise is a post-converge drill.
   ```
   test -f ~/.claude/scripts/lib/cc-tui.sh && echo LIVE || echo 'ADD not converged'
   ```

3. **A superseded request is `rm -f`'d, per the brief's snippet, not filed.** The `SUPERSEDED-BY-LIVE-RUN`
   log line is its only trace. If a *different* ask (e.g. a `mode:prompt`) arrives for a sid with a
   live `relaunch` run, it is dropped rather than queued. Deliberate and small; say so if it bites.
   ```
   grep -c SUPERSEDED-BY-LIVE-RUN ~/.reso/limit-recover/poller.log
   ```

4. **`$STATE/claimed/` and `$STATE/husk-requests/` have no pruner.** They grow one small JSON per
   drained request forever. `results/` already has this property (22 files today), so it is not a new
   class, but it is a new pair of directories.
   ```
   find ~/.reso/limit-recover/claimed ~/.reso/limit-recover/husk-requests -type f 2>/dev/null | wc -l
   ```

5. **Everything here is INERT until the lead converges.** The live plist runs
   `/Users/chrisren/.claude/scripts/limit-recover/lr-reset-poller.sh` — the symlink layer — and
   `tests/lr-reset-poller-requests.bats` is an **ADD**, so it has no live counterpart until
   `install.sh` runs.
   ```
   bash scripts/wrap-ledger.sh --machine | grep -E 'LIVE_(SHA|LAG|ADDS)'
   ```

6. **The `HUSK` log prefix is now shared by two different facts** — the source-pane husk
   (`HUSK <sid> (<acct>) — … source pane … still live`) and the not-recovered park
   (`HUSK <sid> (run … state …) — … LEFT PARKED`). The brief prescribed the second string literally.
   They are distinguishable by their parenthetical and by the suffix, but a bare `grep HUSK` now
   returns both.
   ```
   grep -c 'record LEFT PARKED' ~/.reso/limit-recover/poller.log
   ```

---

## 8. One environment hazard the lead should know about

**The session scratchpad is SHARED by all six sibling agents in this wave.** At 23:07 a sibling's own
`mutate.sh` was written over mine at
`/private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/d90959db-.../scratchpad/mutate.sh`
**while mine was running**. bash reads a script incrementally, so the running shell re-read the new
bytes at its old offset, aborted mid-function, and **left my subject file mutated with no restore** —
caught only because I ran `git status` immediately after. That directory also holds `w5c/`,
`mutants.py`, `muts.json`, `run-all.sh` and `plan.tsv` from other siblings, so the collision surface
is the whole shared namespace, not one filename.

Mitigation used here: a private `/tmp/w5a-mutation-harness/` with W5A-unique filenames, and the
harness given an `EXIT INT TERM` trap that restores and sha256-verifies. Worth telling the other five.

**Second, smaller note:** `cc-bats` refused most of this pass (load/core hit 3.0 with six siblings
running suites). After three sheds each mutant run took **cc-bats' own documented waiver** —
`CC_BATS_WAIVER_REASON='…' CC_BATS_MAX_ROOTS=0` — one root at a time, never in parallel. Marked in
the harness output as `(cc-bats waiver)`. The alternative was scoring a shed as SURVIVED, which is
exactly the failure the plan-line assertion exists to prevent.
