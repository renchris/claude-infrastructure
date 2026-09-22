# A7 — the cc-backlog drain WORKER PATH: pick → brief → fire → work → land → close

Measured 2026-09-22T06:00–06:20Z against the live stores in
`~/.claude/autonomy/` (one shared store; `.claude-next|-tertiary|-quaternary/autonomy`
are all symlinks to `~/.claude/autonomy`, verified by `ls -ld`).
Repo: `/Users/chrisren/Development/claude-infrastructure` @ `215c69e0b` (main, clean).
READ-ONLY throughout: no fire, no dry-run that spawns, no edit, no commit.

---

## 1. Headline

**Pick-to-landed completion rate: 5.9%** — 57 of 972 claims taken in the last 7 days
produced a close whose evidence names a commit that is an ancestor of `origin/main`.

**The single biggest break is not in the worker. It is one stage earlier: the worker is
never born.** 805 of 972 claims (82.8%) ended in `reopen / releaseReason:"spawn-fail"` —
the dispatcher claimed the row, `handoff-fire.sh` REFUSED the fire, and the dispatcher
rolled the claim back seconds later. No session, no worktree, no commit, no close.
62 distinct rows are in that loop; the top one has been claimed and released **385 times
in 30 days** (374 of them in the last 7), on a ~15-minute cycle, right now.

Two verbatim causes, read out of `cc-dispatch`'s own `action:"failed"` journal rows:

| rc | cause | count in the 69.3 h fire log |
|---|---|---|
| 3 | `handoff-fire ABORTED: the payload carries TRUNCATED pane id(s)` — the **pane-id-lint payload gate** | 196 |
| 1 | `anchor probe INCONCLUSIVE (rc=2) — iTerm2 may be busy or congested` | 101 |
| 1 | `anchor probe REFUSED: live windows exist but none is agent-owned (rc=4)` | 99 |
| 1 | `handoff-fire: no pane anchor resolved` | 114 |

The rc=3 case is self-referential and is the whole 374-failure row. Backlog row
`d6d7edef60a3`'s TITLE is *"handoff-fire runs its payload gates on 1 of 3 fire paths:
`--recycle` runs NEITHER payload_pane_id_gate NOR payload_lint_gate…"* — the dispatcher
embeds that title in the brief, and `handoff-fire`'s pane-id lint then convicts the
payload for containing a truncated pane id. **The gate refuses to dispatch the row that
describes the gate**, forever, ~96 times a day.

**Second headline — the close is prose, not a mechanism.** `scripts/ship-land.sh` never
closes a backlog row: `grep -c 'cc-backlog done' scripts/ship-land.sh` → **0**. Landing a
fix does not close its row. On the local drain lane the ONLY closer is the worker itself
following a sentence in a generated markdown brief
(`scripts/drain-brief.template.md:64`). If the worker dies, the row stays open with its
fix already on trunk.

**Third — the local drain chain has been dead for 12.3 days** and its own detector says
so, unheeded. `local-drain`-lane closes: 397 in the last 30 days, **0 in the last 7**.

---

## 2. The chain, with per-stage measured survival

```
                                                        7-day counts
┌─────────────────────────────────────────────────────────────────────────┐
│ 0. STORE            350 live rows · 3,740 distinct ids ever             │
│                     inflow 224 filed / 221 closed → NET +3 (losing)     │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────────────┐
│ 1. PICK             two independent arbiters, two different answers      │
│   drain-pick.sh     eligible = 1   thrash_held = 1                      │
│   cc-dispatch       admit    = 226 decisions in one 3.4 h IDL epoch     │
│   READINESS probe   ready:false on 164 of 226 (reason cites-nothing)    │
│                     gate = "advisory" ⇒ DISPATCHED ANYWAY               │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │ 972 claims
┌────────────────────────────────▼────────────────────────────────────────┐
│ 2. BRIEF            drain: pure function of (template,N,lane,project)   │
│                     dispatch: embeds the ROW TITLE verbatim ──┐         │
└────────────────────────────────┬──────────────────────────────┼─────────┘
                                 │                              │
┌────────────────────────────────▼──────────────────────────────▼─────────┐
│ 3. FIRE             handoff-fire.sh                                      │
│   ✗ 805 (82.8%)  spawn-fail  ── pane-id lint (rc3) · no pane anchor (rc1)│
│   ✗   1 (0.1%)   worktree-fail                                           │
│   ✓ 166 (17.1%)  a session actually started                    ── 17.1% ─┤
└────────────────────────────────┬────────────────────────────────────────┘
                                 │ 166
┌────────────────────────────────▼────────────────────────────────────────┐
│ 4. WORK + LAND      no automatic close on land (ship-land: 0 calls)      │
│   → done   68   (41.0% of fires that started; 7.0% of claims)           │
│   → block  15                                                            │
│   → re-claimed without disposition 70                                    │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │ 68
┌────────────────────────────────▼────────────────────────────────────────┐
│ 5. CLOSE ON TRUNK   57 of 68 cite a sha that IS an ancestor of main      │
│                     (store-wide: 159 of 221 closes = 71.9%)             │
│                                                        ── 5.9% of 972 ──┘
└─────────────────────────────────────────────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────────────┐
│ 6. RETURN / CUSTODY 123 OPEN debts · 123 STALE · 0 fresh                 │
│                     ages 294 h – 715 h (12.2 d – 29.8 d), median 564 h  │
│                     119 cloud-session · 4 local fires · 0 discharged     │
└─────────────────────────────────────────────────────────────────────────┘
```

Per-stage survival, claim→trunk: **17.1% × 41.0% × 83.8% = 5.9%.**

---

## 3. Selection predicate and the readiness question

### 3a. `drain-pick.sh` — the ranking function, quoted (`scripts/drain-pick.sh:86-92`)

```jq
| . + { tier: (if (.title | test("^(advance MASTER|W[0-9]+ WAVE|MASTER:)")) then 3
               elif .falsifier then 0
               elif ((.dodRef // "") != "") then 1
               else 2 end) }
] as $all
| ($all | map(select(.claims >= $maxc))) as $thrash
| ($all | map(select(.claims < $maxc)) | sort_by(.tier, .firstTs)) as $pick
```

Tier 0 = carries a falsifier (cheapest adjudication) · 1 = carries a `dodRef` · 2 = plain ·
3 = umbrella. Within a tier, **oldest `firstTs` first**. Not priority, not random.
Exclusions: `status != "open"`, project mismatch, and `claims >= --max-claims` (default 5).

Live output right now — `eligible=1` against a store of 350 live rows:

```
DRAIN PICK  ·  2026-09-22T06:07:16Z  ·  projects=claude-infrastructure
rank id            project                age_d claims tier  title
1    52e837e8f22d  claude-infrastructure      0      0    0  re-land docs/ship-owns-the-tree-removal: ship-land could not complete …
eligible=1 shown=1 thrash_held=1
  held: d6d7edef60a3 claims=385 handoff-fire runs its payload gates on 1 of 3 fire paths: --
```

The only eligible row is a **re-land row that `ship-land.sh` itself minted after a failed
land.** The drain's worklist is currently the land rail's own exhaust.

### 3b. What is in the brief

`scripts/drain-brief.sh` substitutes 11 placeholders into the tracked
`drain-brief.template.md` (96 lines; ratchet refuses a template > 200 lines,
`drain-brief.sh:105-106`). No row content is baked in — the worker is told to run
`drain-pick.sh` itself. Per-project rails (`GATE_CMD` / `LAND_CMD` / `ENTRY_STEP`) are
selected by a `case` on `--project` (lines 88-101). The brief is written to
`$CLAUDE_CONFIG_DIR/autonomy/fire-drain-<lane>-recycle<N>.txt` plus a <400-byte pointer.

The cc-dispatch path is different and is where the rc=3 failure lives: it composes a
payload containing the **row's title verbatim**, and that payload is what the pane-id lint
scans.

### 3c. Readiness/staleness gate at FIRE time — the plist's claim is now HALF wrong

`com.claude.dispatcher.plist` says, verbatim:

> 2. STALENESS. Nothing yet gates an item on being current at the moment it FIRES.
> … The readiness conjunction that closes this is filed, not built:
> docs/plans/BACKLOG_CONSOLIDATION_2026-08-09.md section READINESS, waves d73a772a8468 /
> 0e8a10c501af / df003b95630b.
> REVERT: … Do that only once the readiness gate is enforcing, or the two reasons above
> are both still true.

**Verified, and corrected:** all three waves now fold to `done`, and a readiness gate DOES
exist and DOES run — `bin/cc-dispatch:1354`, `READY_GATE="${CC_DISPATCH_READY_GATE:-advisory}"`,
accepting `advisory|enforce|off`. **It defaults to `advisory`, which journals the verdict
and admits anyway** (`cc-dispatch:250-251`). Live IDL rows:

```json
{"ts":"2026-09-22T02:45:13Z","actor":"cc-dispatch","action":"readiness","id":"d6d7edef60a3",
 "ready":false,"state":"void","reason":"cites-nothing","gate":"advisory", …}
```

**164 of 226 readiness evaluations in the current IDL epoch read `ready:false`, and every
one of them was dispatched.** The plist's prose ("nothing gates") is stale; the operative
fact is that the gate is built, is measuring, is red on 73% of what it sees, and is not
wired to refuse. The plist's own un-park precondition ("only once the readiness gate is
enforcing") was therefore not met when the dispatcher was un-parked on 2026-09-07.

---

## 4. Who closes a backlog row — the exact code

| Closer | file:line | Trigger | Kind of close |
|---|---|---|---|
| **the worker, by hand** | `scripts/drain-brief.template.md:64` — *"Only then `cc-backlog done <id> --evidence "landed <sha> — …"`"* | prose in a generated markdown brief | the ONLY closer on the local drain lane |
| `cc-premise` | `bin/cc-premise:2914` `subprocess.run([_backlog_bin(),"done",cid,"--evidence",ev])` | `autonomy-sweep.sh:1489 --close-falsified 25` | MOOT — the row's falsifier passed. Not work-landed. |
| `cloud-return.sh` | step 8, `scripts/cloud-park.sh:18` — *"cloud-return.sh step 8 turns the landed path into `cc-backlog done`"* | `scripts/cloud-return-lane.sh`, detached from `autonomy-sweep.sh:713` | the cloud lane's only automatic close |
| `backlog-handback.sh` | `scripts/backlog-handback.sh:4` `record <id> --verb done` | called ONLY from `scripts/cloud-reconcile.sh:788` | records a VM's verdict |
| **`ship-land.sh`** | — | — | **NEVER. `grep -c 'cc-backlog done' scripts/ship-land.sh` → 0.** It only *files* rows (re-land rows, `ship-land.sh:804,1341`). |

**THE HEADLINE OF THIS SECTION:** on the local drain path, a fix that is committed, gated
and landed on `origin/main` closes NOTHING. The close is a separate voluntary act by a
session that must still be alive to perform it. `wrap-ledger.sh:2041` and
`completion-assert.sh:748` nag about it at Stop; neither performs it.

The two hooks that *mention* closing are pure nags:
`hooks/completion-assert.sh:728,748`, `scripts/wrap-ledger.sh:2033,2041`.

---

## 5. Assert-script verdicts, verbatim

### `bash scripts/drain-chain-assert.sh` (bare = report, no filing)

```
drain-chain-assert: the 24/7 backlog drain chain is DEAD — 350 live row(s) and nothing is working them: no fire-drain-recycle brief inside 86400s (newest: 1063252s old) and 0 live leases inside 5400s. Restart it with the Lane B recycle-fire template in docs/plans/BACKLOG_DRAIN_24_7.md §4.1
rc=0
```

### `bash scripts/drain-chain-assert.sh --json`

```json
{"verdict":"dead","why":"no-brief-no-lease","live_rows":350,
 "brief":"/Users/chrisren/.claude-tertiary/autonomy/fire-drain-infra-recycle333.txt",
 "brief_age_s":1063257,"live_leases":0,"cloud_leases":0,
 "progress_age_s":null,"progress_why":null,"pane":null,"sid":null,"transcript":null,
 "progress_max_age_s":3600,"handover_grace_s":900, …}
```

1,063,257 s = **12.31 days**. The chain stopped at recycle #333.

### `bash scripts/backlog-flow-assert.sh` (always prints)

```
backlog-flow: NET-POSITIVE over 7d — 224 filed / 221 closed (net +3) · 815 reopened. §6: the INFLOW list (C1-C4) gets the next fix, not more drain horsepower.
rc=0
```

### `bash scripts/backlog-flow-assert.sh --project claude-infrastructure`

```
backlog-flow: NET-POSITIVE over 7d — 209 filed / 205 closed (net +4) · 803 reopened · project claude-infrastructure. §6: the INFLOW list (C1-C4) gets the next fix, not more drain horsepower.
rc=0
```

`--json` adds: `"added":224,"closed":221,"reopened":815,"net":3,"unparsed":0,"dropped":0,
"excluded":0,"records":23348,"history_s":5639915`. Excluded = 0, so guard 4 does not abstain:
this verdict is clean.

**Read the 815 reopens against the 221 closes.** `backlog-flow-assert` deliberately does
not fold reopens into `added`, and its reasoning (INFLOW list C1-C4 are all *filing*
generators) means it is structurally blind to this population — **811 of the 815 are
`releaseReason:"spawn-fail"`**, which is neither inflow nor drain. The flow auditor sees a
+3 week; the actual event that dominates the store is a fire loop it has no category for.

### `bash scripts/dispatch-acceptance.sh`

```
AUTONOMY_DISPATCH_V2 §7 — disk-truth acceptance reads
  ✓ A1   PASS    10 decisions == 10 open items (pass 20260922T055600Z-17380)
  ✗ A2   FAIL    1 add(s) in the v2 window received NO decision at all (n=1 decided)
  ✓ A3   PASS    0 deferral(s), 0 abstentions since v2 began
  ✓ A4   PASS    2 wall verdict(s), 0 un-evidenced / 0 with a healthy account / 0 on a failed oracle
  ✓ A5   PASS    2 unknown verdict(s), no quota-cliff page written
  ✓ A7   PASS    no admit recorded at or above ceiling 12
  ✓ A8   PASS    bounded helper run_oracle() invokes $TIMEOUT_BIN; timeout→unknown proven behaviourally
  · A11  NOT-RUN label loaded + enabled, last exit 0, no output yet — awaiting its first interval
  verdict=red fails=1
```

**The acceptance reader has NO criterion for the spawn-fail class.** It reports 7 PASS / 1
FAIL while 805 fires failed in the window it claims to audit. A11 reads
`/tmp/claude-dispatcher.stdout.log` and calls a dispatcher that has failed 21 spawns in the
last 3.4 h *"awaiting its first interval."*

---

## 6. Branch archaeology

Naming conventions found: `handoff-fire.sh` cuts `claude/fire-<UTCts>-<pid>-<n>` (155 on
this checkout); `cc-dispatch` cuts **`wt-<backlog-id>`** per row
(`bin/cc-dispatch:70,1726,3292`); the drain lane uses `drain/lane-<lane>` in
`~/Development/.worktrees/drain/lane-<lane>` (`drain-brief.sh:76`).

### 6a. `wt-<12-hex>` dispatch branches — 49, judged per PATH by CONTENT

`git rev-parse <branch>:<path>` vs `git rev-parse origin/main:<path>` for every path in
`merge-base..branch`. Never `git cherry`, never a commit count alone.

| verdict | n | reading |
|---|---:|---|
| **EMPTY** (0 paths differ from merge-base) | **27** | branch tip IS a trunk commit — the worktree was cut and **nothing was ever committed**, or a verbatim land collapsed it. Reflog disambiguates where it survives (see 6b). |
| **DIVERGED** (paths exist on main, content differs) | 21 | branch base is 42–58 days old; trunk has moved. Superseded, not owed. |
| **LANDED** (all paths byte-identical on main) | 1 | `wt-87a515ed087e` |
| **STRANDED-ADD** (a path the branch created, absent from main) | **0** | no *added* file is stranded on any `wt-` branch |

Row states for those 49 ids: **47 `done`**, 1 `reopen`, 1 `block`.

Provenance cross-check, convention-independent: `origin/main` carries **162 commits with a
`Backlog:` trailer, naming 120 distinct ids** across all history. Of the 49 `wt-` branch ids,
**only 2** (`963c7af699c9`, `c50158434c7a`) have such a commit on trunk. So either the
`Backlog:` trailer convention (mandated at `drain-brief.template.md:51`) is not followed by
dispatch workers, or 47 of these branches never produced an attributable commit.

Reflog survives on only 10 of 49 (the rest expired). All 10 are from 2026-09-17 → 09-22 and
all show real activity (`rebase (finish)`, `commit:`). The 39 with no reflog are all
`merge-base` ages 42–58 d — i.e. **the EMPTY-with-no-reflog class cannot be distinguished
between never-worked and landed-verbatim by any instrument still on this disk.** Stated as a
residual, not folded into either bucket.

### 6b. `drain/lane-infra` — the drain chain's own last branch. THE ONE MEASURABLE STRAND.

3 commits ahead of `origin/main`, tip `a0c743c74`, dated **2026-09-09 18:53** — the day the
chain died. 5 paths, none absent from trunk. Per commit, by content:

| commit subject | verdict | evidence |
|---|---|---|
| `fix(unattended-path-lint): a plist that resolves NOTHING is declared or LOUD, never silent` | **SUPERSEDED** | trunk's `unattended-path-lint.sh` carries the "resolves NOTHING" arm **twice**; trunk is +770/−382 lines ahead of the branch on it |
| `feat(capacity-alarm): rung 8 — chronic-pressure ratchets (swapfiles + data.kalloc.1024)` | **SUPERSEDED** | landed on trunk as `70c164267 feat(capacity-alarm): rung 8 — chronic ratchets (swapfile count + data.kalloc.1024) with a reboot advisory` — reworded subject, so an exact-subject test falsely reads NOT-ON-TRUNK |
| `docs(drain): recycle #332 — closed 4 rows` | **🚨 STRANDED** | `git show origin/main:docs/plans/BACKLOG_DRAIN_24_7.md \| grep -c 'recycle #332'` → **0**. Trunk's §2.1 log stops at **#331**. |

**The chain's final record of its own last working link — the entry saying it closed 4 rows
— is the one artifact that never reached trunk.** The §2.1 log now reads as if the drain
stopped at #331, and the fire that produced brief #333 left no trace in it at all.

Landed / stranded / superseded across all 50 examined branches:
**landed 1 · stranded 1 (one commit) · superseded 23 · indeterminate-empty 27 (0 of which
strand an added file).**

---

## 7. Custody — the waves that never returned

`bash bin/cc-custody count --open` reads store-wide (`_files_for` with no `--cwd` cats
every `*.jsonl`). Store totals: **1,062 `open` · 476 `return` · 463 `abandon`.**

```
open total: 123      open stale: 123      open fresh: 0
ages (h):  min 294 · p25 482 · median 564 · p75 638 · max 715
classes:   cloud-session_*  119      local fires  4
```

**Every open custody debt is stale** (TTL 24 h; `CC_CUSTODY_TTL_HOURS`). The *youngest*
unreturned wave is **12.25 days** old — which coincides with the drain chain's 12.31-day
brief age. Both stores date the stop to ~2026-09-09/10.

The 4 non-cloud debts, all from 2026-09-09:

```
2026-09-09T01:40:26Z  fire-ed-recycle    pane 643  316 h  proven
2026-09-09T18:11:37Z  fire-ed-w2-w3b1    pane 725  299 h  proven
2026-09-09T23:18:26Z  fire-ed-w2-w3b4    pane 761  294 h  unproven-rc1
2026-09-09T23:27:53Z  fire-ed-w2-w3eng   pane 762  294 h  unproven-rc1
```

`unproven-rc1` = the opener could not prove the fire engaged. Nothing discharged them, and
nothing will: `cc-custody` deliberately never expires a row (its header: *"NOT expiry. A
TTL that DROPS a row is the silent-loss direction this file's POLARITY note already
rejects"*). Discharge requires a human/agent `abandon --stale --why …`. Correct design;
the consequence is that every session sharing those 4 cwds inherits a permanent 🔧 and can
never render `✅ SAFE TO CLOSE`.

---

## 8. Every place the chain can silently drop work

Ordered by measured volume.

1. **Fire reports a failure the store records and no alarm reads.**
   805 spawn-fails / 7 d. `grep -rln 'spawn-fail' scripts/ bin/ hooks/` returns only the
   *producers* (`cc-dispatch`, `cc-backlog`, `cc-reaper`, `lr-reset-poller.sh`) — **there is
   no detector, no sweep arm and no plist keyed on the dispatch spawn-failure rate.**
   `drain-chain-assert.sh` is scoped to the LOCAL drain only; `backlog-flow-assert.sh`
   counts reopens on a separate line and explicitly refuses to act on them.

2. **The brake that would stop the loop was deliberately disarmed, for a good reason.**
   `bin/cc-backlog:6449` — *"A SELF-RELEASE IS NOT A THRASH CYCLE. selfRelease marks a
   reopen the CLAIMER issued…"* — and `bin/cc-dispatch:1136-1139` explains why: without it,
   `reap` rule B blocked 228 items on dispatcher rollbacks. Correct fix; the side effect is
   that a row failing to spawn is **never blocked, never reaped, never sunk out.**
   Meanwhile `drain-pick.sh` *does* hold it (`claims >= 5` → `thrash_held`). **Two arbiters
   over one store give opposite answers on the same row**: drain-pick holds
   `d6d7edef60a3`; cc-dispatch fired it 374 times.

3. **`cc-dispatch`'s own thrash sink is measured over a store that rotates.**
   `thrash_map()` folds `action=="failed"` rows out of `$IDL`.
   `rotate-autonomy-logs.sh:75` rotates `idl.jsonl` at **25 MiB** — the live epoch began
   `2026-09-22T02:43:17Z` and is 3.4 h old; archives are dated Sept 12/13/14/15/16/17/20/22.
   A row's lifetime failure count is truncated to the current epoch at every rotation, so
   374 failures read as ~13. And the sink only ORDERS; it never EXCLUDES — and with
   `free_slots=12` there is nothing for ordering to exclude.

4. **A `fired` journal row is not a fire.** `action:"fired"` rows carry
   `actor:"cc-wave-plan"` and `id:null` — they are quota-PLACEMENT messages
   (`"placed 2 items across 2 accounts; urgency: next3 is BEHIND…"`). In the live 3.4 h
   epoch: **15 `fired` rows, 21 `failed` rows, 0 actual worker spawns.** Any reader counting
   `fired` reports 15 successful dispatches where there were none. *(I made this error
   myself first — reading `21 failed` as a 7-day figure before checking the IDL window.)*

5. **A worker commits to a worktree nobody merges.** 104 live worktrees;
   `drain/lane-infra` holds an unlanded §2.1 entry from 2026-09-09; 49 `wt-<id>` branches
   sit at 42–58-day-old bases. `worktree-gc.sh:814` records that *"0 had a `done` backlog
   item"* among eligible worktrees, and refuses to close rows itself
   (`worktree-gc.sh:775`, `:1167`).

6. **A close that never fires.** `ship-land.sh` lands and does not close. If the session
   dies between the push and `cc-backlog done`, the fix is on trunk and the row is open —
   and `drain-pick.sh` will rank it again, oldest-first, for another worker to redo.
   `worker-claim-gate.sh:488` is the only thing that catches the redo, and only if it
   recognises the finished item.

7. **A readiness verdict computed and discarded.** 164 `ready:false` in one epoch,
   `gate:"advisory"`, dispatched anyway (`cc-dispatch:1354`).

8. **A notify-back into a dead inbox.** 123 open custody rows, target panes 643/725/761/762
   long gone; `cc-custody return|abandon` is *best-effort by design* — on no match it prints
   to stderr and **exits 0** (`bin/cc-custody`, the `else` arm of the return branch).

9. **A self-perpetuating inflow.** `scripts/drain-peer-findings.py` files rows into the same
   store from dead sessions' closes; `ship-land.sh` files a re-land row on every failed
   land. The one currently-eligible row for the whole `claude-infrastructure` project
   (`52e837e8f22d`) is a ship-land re-land row. **The pipeline's remaining work is its own
   exhaust.**

---

## 9. Every command that produced a number

```bash
cd /Users/chrisren/Development/claude-infrastructure
L=~/.claude/autonomy/backlog.jsonl
S7=$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ); S30=$(date -u -v-30d +%Y-%m-%dT%H:%M:%SZ)

# --- store identity (one store, four config dirs) ---
for d in ~/.claude ~/.claude-next ~/.claude-tertiary ~/.claude-quaternary; do ls -ld "$d/autonomy"; done

# --- the two chain auditors (read-only modes; --file NOT used) ---
bash scripts/drain-chain-assert.sh
bash scripts/drain-chain-assert.sh --json
bash scripts/backlog-flow-assert.sh
bash scripts/backlog-flow-assert.sh --json
bash scripts/backlog-flow-assert.sh --project claude-infrastructure
bash scripts/dispatch-acceptance.sh
bash scripts/drain-pick.sh --project claude-infrastructure --top 8

# --- the funnel: per-claim outcome over 7 days  (972 claims; 805 spawn-fail; 68 done) ---
jq -rs --arg s "$S7" '
  (group_by(.id) | map({id:.[0].id, ev:(sort_by(.ts))})) as $b
  | [ $b[] | .id as $i | .ev as $e
      | ($e|to_entries[]|select(.value.event=="claim" and (.value.ts//"")>=$s)
         | . as $c
         | ($e[($c.key+1):] | map(select(.event!="link" and .event!="venue" and .event!="update")) | .[0]) as $n
         | { id:$i, next:($n.event // "NOTHING"),
             reason: (if $n.event=="reopen" then ($n.releaseReason // (if $n.selfRelease then "self" else "manual" end)) else "-" end) } ) ]
  | group_by(.next+"/"+.reason) | map({k:(.[0].next+" / "+.[0].reason), n:length})
  | sort_by(-.n) | .[] | "\(.n)\t\(.k)"' "$L"
jq -r --arg s "$S7" 'select(.event=="claim" and (.ts//"")>=$s)|.id' "$L" | wc -l

# --- release reasons (811 spawn-fail / 815 reopens; 62 distinct ids) ---
jq -r --arg s "$S7" 'select(.event=="reopen" and (.ts//"")>=$s and .selfRelease==true)|.releaseReason//"NONE"' "$L" | sort | uniq -c | sort -rn
jq -r --arg s "$S7" 'select(.event=="reopen" and (.ts//"")>=$s and .releaseReason=="spawn-fail")|.id' "$L" | sort -u | wc -l
jq -r --arg s "$S7" 'select(.event=="reopen" and (.ts//"")>=$s and .releaseReason=="spawn-fail")|.id' "$L" | sort | uniq -c | sort -rn | head

# --- the trunk-backing test (57 of 68; 159 of 221) — per record, ANY hex token that is an ancestor ---
bash /tmp/backlog-probe/evid2.sh     # source inlined below
#   for each `done` in window: for sha in $(grep -oE '\b[0-9a-f]{7,40}\b' <<<"$evidence" | sort -u | head -12);
#     git cat-file -e "${sha}^{commit}" && git merge-base --is-ancestor "$sha" origin/main
bash /tmp/backlog-probe/funnel.sh    # same test, restricted to the 68 claim→done pairs

# --- close attribution ---
jq -r --arg s "$S30" 'select(.event=="done" and (.ts//"")>=$s)|.lane//"NO-LANE"' "$L" | sort | uniq -c | sort -rn
jq -r --arg s "$S7"  'select(.event=="done" and (.ts//"")>=$s)|.lane//"NO-LANE"' "$L" | sort | uniq -c | sort -rn
grep -c 'cc-backlog done' scripts/ship-land.sh                      # → 0
grep -rn 'cc-backlog done' scripts/ hooks/ bin/ | grep -v '^bin/cc-backlog:'

# --- fire failures, verbatim causes ---
grep -oE '^(!!|handoff-fire:).{0,90}' ~/.claude/logs/dispatch-fires.log | sed 's/[0-9a-f]\{8,\}/HEX/g' | sort | uniq -c | sort -rn
grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z' ~/.claude/logs/dispatch-fires.log | sort | sed -n '1p;$p'   # 2026-09-19T08:30:56Z → 2026-09-22T05:50:53Z
jq -c 'select(.action=="failed")' ~/.claude/autonomy/idl.jsonl | head -2
jq -c 'select(.action=="fired")'  ~/.claude/autonomy/idl.jsonl | head -2   # actor=cc-wave-plan, id=null

# --- readiness gate ---
jq -r 'select(.action=="readiness")|(.reason//"-")' ~/.claude/autonomy/idl.jsonl | sort | uniq -c | sort -rn
grep -n 'READY_GATE=\|CC_DISPATCH_READY_GATE' bin/cc-dispatch          # :250-251, :1354-1356
jq -r '.ts//empty' ~/.claude/autonomy/idl.jsonl | sort | sed -n '1p;$p' # epoch = 3.4 h
grep -n 'MAX_BYTES' scripts/rotate-autonomy-logs.sh                     # 25 MiB
ls -la ~/.claude/autonomy/ | grep idl

# --- branch archaeology ---
git for-each-ref --format='%(refname:short)' refs/heads/ | grep -E '^wt-[0-9a-f]{12}$'   # 49
bash /tmp/backlog-probe/arch.sh      # per-branch, per-PATH: git rev-parse <b>:<p> vs origin/main:<p>
bash /tmp/backlog-probe/reflog.sh    # .git/logs/refs/heads/wt-* — 10 of 49 survive
git log origin/main --format='%H|%cI|%(trailers:key=Backlog,valueonly,separator=%x2C)' \
  | awk -F'|' '$3!=""' | wc -l                                          # 162 commits
comm -12 <(sort /tmp/backlog-probe/landed-ids.txt) <(sed 's/^wt-//' /tmp/backlog-probe/wt-branches.txt | sort)  # 2

# --- drain/lane-infra, per path + per commit subject ---
mb=$(git merge-base origin/main drain/lane-infra)
for p in $(git diff --name-only "$mb"..drain/lane-infra); do
  [ "$(git rev-parse "drain/lane-infra:$p")" = "$(git rev-parse "origin/main:$p")" ] && echo "IDENTICAL $p" || echo "DIFFERS $p"; done
git show origin/main:docs/plans/BACKLOG_DRAIN_24_7.md | grep -c 'recycle #332'    # → 0
git show origin/main:docs/plans/BACKLOG_DRAIN_24_7.md | grep -oE 'recycle #3[0-9]{2}' | sort -u | tail -5
git show origin/main:scripts/unattended-path-lint.sh | grep -c 'resolves NOTHING' # → 2
git diff --stat origin/main drain/lane-infra -- scripts/unattended-path-lint.sh scripts/capacity-alarm.sh

# --- custody ---
bash bin/cc-custody count --open; bash bin/cc-custody count --open --stale; bash bin/cc-custody count --open --fresh
bash bin/cc-custody list  --open --json > /tmp/backlog-probe/custody-open.json
jq -r '[.[].ageHours]|sort|{min:.[0],median:.[(length/2|floor)],max:.[-1],n:length}' /tmp/backlog-probe/custody-open.json
cat ~/.claude/autonomy/custody/*.jsonl | jq -r '.kind' | sort | uniq -c

# --- plist + load state ---
cat ~/Library/LaunchAgents/com.claude.dispatcher.plist
launchctl list | grep -Ei 'dispatch|autonomy'     # both loaded, last exit 0
```

---

## 10. Adversarial pass — what I checked because it would have refuted me

- **"The 82.8% is an artifact of two pathological rows."** Partly true and it does not
  change the verdict. 374 + 52 = 426 of 805 spawn-fails sit on two rows; the remaining 379
  spread over 60 rows at ~13 each. Removing both rows still leaves 379/546 = **69.4%** of
  claims dying at the fire. Daily spread confirms it is not one spike: 14 / 50 / 278 / 132 /
  89 / 50 / 157 / 41 across Sept 15→22.
- **"The IDL only shows 21 failures — the ledger's 805 must be a different producer."**
  Wrong, and I caught it by checking the store's window: `idl.jsonl` spans **3.4 hours**
  (25 MiB rotation), not 7 days. 21 failures / 3.4 h ≈ 148/day ≈ 1,037/week, which brackets
  the ledger's 805. Same producer. (Recorded because the wrong reading would have
  manufactured a fake "journal gap" finding.)
- **"`EMPTY` branches mean workers never worked."** Cannot be asserted. A verbatim land
  collapses `merge-base` onto the branch tip, producing the identical signature. Reflog
  disambiguates but survives on only 10 of 49. Reported as an explicit indeterminate class
  rather than folded into "never worked."
- **"`NOT-ON-TRUNK` by commit subject means stranded."** Refuted on my own data: the
  `rung 8` commit landed as `70c164267` with a **reworded subject**, so exact-subject
  matching called landed work stranded. Every `drain/lane-infra` verdict above was re-taken
  by content (`git show origin/main:<path> | grep`), and only then did one true strand
  survive.
- **"Closes might be fabricated."** Tested: 159 of 221 closes (71.9%) name a commit that is
  a verified ancestor of `origin/main`. Of the 62 that do not, the sample is dominated by
  legitimate MOOT/operator/superseded closes (`cc-do ran: … (exit 0)`, `auto-retracted at
  filing: land-content-verify.sh reports …`, `premise wrong: …`). **Close quality is not
  the defect; fire survival is.**
- **"The plist says there is no readiness gate — take it at its word."** Did not. All three
  cited waves fold to `done`, the gate exists at `cc-dispatch:1354`, and it is running and
  red. The plist is a resident doc restating a perishable fact, exactly the failure mode
  `resident-policy-must-not-restate-perishable-facts` names — and I nearly reproduced the
  plist's own stale claim as a finding.
