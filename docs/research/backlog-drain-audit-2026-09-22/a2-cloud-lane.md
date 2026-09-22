# A2 — Cloud lane productivity probe
Measured 2026-09-22T06:00–06:40Z on `~/Development/claude-infrastructure`. Read-only: no session
fired, no file in the repo edited, no `poll`/`create`/`fire` verb run.

---

## 1. Headline verdict

**The cloud lane IS productive, and it is productive TODAY — but its session yield is ~16%.**

Over its whole life (first declaration `2026-08-08T08:01:34Z`, most recent `2026-09-22T02:11:40Z`
— 45 days) the cloud lane drove **116 distinct backlog rows to a LANDED result on origin/main**.
113 of those are `done` in the backlog fold right now; 3 are `blocked`.

That number is bracketed by three independent instruments, and I report all three rather than one:

| instrument | sessions landed | distinct backlog rows landed |
|---|---|---|
| **floor** — all three instruments agree | 90 | **85** |
| `cc-cloud list --state` (the repo's own classifier) | 127 | **105** |
| **union** of the three (the headline) | 149 of 727 | **116** |

A fourth, wholly independent store agrees on the closure side: **110 backlog rows carry a `done`
record whose own evidence text names a cloud session** (`cloud session_01… → origin/main: <paths>`
or `cloud-worker-LANDED:<sha>`), and all 110 are still `done` today.

Rates: **2.6 landed rows/day** across the 45-day life; **1.4/day** over the last 14 days.
The last successful end-to-end closure was **3h57m before this probe** (§5).

**The leak is not lost work — it is wasted fires.** 727 declarations covered only **182 distinct
items** (3.90 fires per item; worst single item fired **38** times). 328 sessions sit STALLED on
pushed-but-unlanded refs, yet those 328 cover only **73 distinct items, 69 of which are now
`done`**. So the cloud lane's dominant failure mode is *re-firing an item that is already out
there or already finished*, not losing the result of work it completed.

**Two things are broken right now and neither is the pile cap:**
1. The lane's own liveness sensor (`scripts/cloud-lane-liveness.sh`) has been **permanently VOID
   since 2026-09-16** — a sibling job deleted the refs its baseline is pinned to (§3).
2. **The dispatchable cloud queue is zero.** All 28 rows `cc-eligible` calls eligible today are
   `blocked`; none of the 10 `open` rows is cloud-eligible (§4).

---

## 2. The funnel

### 2a. Session level

| # | stage | count | store |
|---|---|---|---|
| 1 | backlog rows routed `venuePlan=cloud` | **230 distinct ids** (239 routing records) | `~/.claude/autonomy/backlog.jsonl`, `event=="venue"` |
| 2 | cloud sessions declared (= fired) | **727** declarations, 710 carrying `item=`, over **182 distinct items** | `~/.claude/autonomy/cloud/*.decl` |
| 3 | sessions that produced a result (pushed a ref to origin) | **518** (71.3%) | `cc-cloud list --state --json` → `last_sha != ""`; independently corroborated by 518 `*.seen` sidecars |
| 4 | results RETURNED and LANDED on origin/main | **149** (20.5% of fires, 28.8% of pushers) | union of: `cc-cloud` `state=="LANDED"` (127) · `Cloud-session:` trailers in `git log origin/main` (127 distinct sids) · `return.jsonl` `outcome=="returned" and content_verified==true` (100) |
| 5 | distinct backlog rows landed | **116** (113 done, 3 blocked) | the 149 sessions' `item=` fields, intersected with the `cc-backlog list --all --json` fold |
| 6 | backlog rows closed as a consequence | **110** (all still `done`) | `backlog.jsonl` `event=="done"` records whose evidence names a cloud session |

Stage-4 latching marker `*.returned` exists for only 99 sessions because `cloud-return.sh` writes
it only on the full-success path (`cloud-return.sh:1019-1020`, gated on
`landed_ok==0 && done_unsettled==0`); the ledger row is written unconditionally, which is why 106
sessions have a `returned` ledger row and 149 have landed evidence somewhere.

### 2b. Item level

```
230 routed cloud ──▶ 182 fired ──▶ 116 landed ──▶ 110 closed by the lane itself
     (−65 never fired)   (−66 fired, never landed)
```
Of the 65 items routed cloud but never fired, 60 are `done` today and 5 are `blocked` — closed by
some other route. Of the 167 fired items that are real backlog rows, 164 are `done`, 3 `blocked`.

### 2c. Where the leak is, with sizes

| leak | size | evidence |
|---|---|---|
| **Re-fire loop (the dominant leak)** | 545 of 727 declarations (74.9%) are re-fires of an item already fired. Top offenders: `01ab05685857` ×38, `0c8b39b67665` ×33, `f85fce7c26f5` / `e981656df348` / `70ed289c10fb` ×30. | `grep -h '^item=' *.decl \| sort \| uniq -c` |
| **Fires that produced nothing** | **209** declarations (28.7%) never pushed a ref — `ABANDONED: no ref, no push evidence` (203) plus 6 others. | `cc-cloud list --state`, `last_sha` empty |
| **Pushed but never landed** | **369** of 518 pushers (71.2%). | stages 3→4 above |
| **Stranded bytes on origin today** | **346** live `origin/claude/*` refs; **345** are content-divergent from trunk on the very files they touch; **508** commits are not patch-equivalent on trunk; **88** refs add **155 files that exist nowhere on origin/main**. | three separate measurements, §3 |
| **Backlog close arm failed on ids that exist** | 105 close-failure rows over **44 distinct items**, all reporting `cc-backlog done: unknown id <id>` — yet **all 44 are present in the fold today** (43 done, 1 blocked). 34 of the 105 also carry `shell-init: error retrieving current directory: getcwd`, i.e. the lander ran from a deleted worktree. **Confined to 2026-08-11…2026-08-17; zero since.** | `return.jsonl` `.backlog` field vs `cc-backlog list --all --json` |
| **Land refusals** | 89 sessions filed a `*.land-refused` artifact; rc histogram `70`×51, `65`×18, `5`×9, `6`×8, `7`/`69`/`143`×1. The refusal-route arm recovers **37 of 89 (41.6%)** — those sessions later landed. | `*.land-refused`, `*.refusal-route`, cross-referenced with the landed set |

**Caveat on the stranded-bytes numbers, stated rather than buried.** `branch-prune-landed.sh` uses
`git cherry` (patch-id), so 508 is an *upper* bound — a commit rebased across a moved trunk gets a
new patch-id and reads `+` even if its content landed. My own independent instrument (per ref:
does `git diff origin/main <ref> -- <files the ref touched>` come back empty?) returns
**DIVERGENT for 345 of 346**, which *over*-counts in the opposite direction, because trunk moving
ahead on a shared file also reads DIVERGENT. The one number with no confound is the third:
**155 files added by 88 cloud refs have no blob on origin/main at all.**

**Why this is waste rather than loss.** Those 346 refs map to 73 STALLED + 59 ABANDONED distinct
items; 69 and 49 of those respectively are `done` today, and 37 / 29 of them were landed by a
*sibling cloud session*. The pile is overwhelmingly duplicate attempts at work that finished.

### 2d. The state classifier's blind spot — the reason STALLED is so large

`cc-cloud`'s `landed()` (`bin/cc-cloud:512-525`) returns "not landed" on an **empty `paths=`**
by design. Cross-tabulating state against `paths`:

```
 215 ABANDONED   NO-PATHS        328 STALLED   NO-PATHS         55 UNKNOWN   NO-PATHS
 127 LANDED      has-paths         2 UNKNOWN   has-paths
```

**Every** declaration that reads LANDED has `paths`; **every** STALLED and ABANDONED one has none.
For 598 of 727 declarations (82.3%) the LANDED verdict is structurally unreachable — C3 can never
fire. So `cc-cloud`'s `STALLED` is not a measurement that the work did not land; it is what a
paths-less declaration decays into. This is why I refused to headline `cc-cloud`'s 127 alone and
went to trunk trailers + a content diff for corroboration. `cc-cloud fill-paths` exists to close
exactly this and was evidently not run over the STALLED population.

---

## 3. The four named sub-questions

### 3.1 — Is the 332-unlanded-declaration refusal still in force? **NO.**

The cap is `bin/cc-dispatch:2158`, threshold `CLOUD_PENDING_MAX="${CC_DISPATCH_CLOUD_PENDING_MAX:-50}"`
(`:455`). Its population is `cloud_pending_scan()` (`:778-793`): a `*.decl` counts as pending
unless a `.returned` **or** a `.retired` sidecar exists.

Re-running that exact predicate by hand against the live store:

```
LIVE cloud_pending_scan count = 0  (cap = 50)
total decls = 727 · with .retired = 727 · with .returned = 99
```

Three further arms agree, so this is not one instrument's word:
* `grep -c 'refusing ALL cloud fires' /tmp/claude-dispatcher.stderr.log` → **0** (log covers
  2026-09-21T05:36Z → 2026-09-22T06:05Z).
* `cloud-pending-cap` rows in the live IDL → **0**; in all 8 archived IDL gz files (back to
  2026-09-12) → **0**.
* Fires resumed after the outage: last declaration before the refusal `2026-09-04T19:38:03Z`
  (`session_01AcrJ4ScWxmkBQJb6fkJdUA`) — the exact timestamp in the brief — then a **58.8-hour
  silence**, then `2026-09-07T06:23:48Z`. Fires have continued every day since 2026-09-16, with
  one today.

`cloud-retire-terminal.sh` drained the pile by retiring the strata that can never return; the plist
comment is history, and the comment block itself says so.

### 3.2 — `scripts/cloud-lane-liveness.sh`, run verbatim

`--help` is the header block; the flags are `--json`, `--assert`, `--selftest`. Human readout:

```
cloud-lane-liveness — the cloud FIRE lane, read from origin
  sensor        answered
  VERDICT       UNKNOWN — refs dated <=20260907 read 334 against a pinned floor of 426 — a branch was DELETED, so an absent date is a collection artifact and the census is void
```
exit **3**. `--assert` prints the same and exits **3**. `--json`:

```json
{
  "verdict": "UNKNOWN",
  "why": "refs dated <=20260907 read 334 against a pinned floor of 426 — a branch was DELETED, so an absent date is a collection artifact and the census is void",
  "open_gap_h": null,
  "ceiling_h": 24,
  "last_fire": null,
  "self_excluded": null,
  "window_days": 7,
  "fires_in_window": null,
  "rate_per_day": null,
  "stalls_in_window": null,
  "max_closed_gap_h": null,
  "refs_seen": null,
  "baseline_obs": null,
  "baseline_want": 426
}
```

**This sensor is permanently void, and a sibling job is why.** Its baseline
(`CC_LANE_BASELINE_N=426`, `CC_LANE_BASELINE_DATE=20260907`, `:97-98`) is a pinned *floor* on the
old-ref population, so it can only ever be breached downward. `scripts/branch-prune-landed.sh`
— run every tick by the same sweep — **deleted 76 branches between 2026-09-05 and 2026-09-15**
(per-day PRUNE counts from the manifests: 15, 1, 1, 1, 1, 31, 9, 1, 15, 1). Since 2026-09-16 every
manifest reads `343–347 HOLD-stranded, 0 PRUNE`. The observed population now reads 334 against a
floor of 426, and it cannot recover, because the deleted refs are gone and no new ref can be dated
`<=20260907`. The lane's only continuous liveness instrument has been dead for 6 days and the
`cloud-return-lane` tick journals `fire_read_rc:"3"` every ~10 minutes into
`~/.claude/logs/cloud-return-lane.log` where nothing reads it.

### 3.3 — `cc-eligible` re-derived TODAY vs the plist's 2026-08-11 measurement

`./bin/cc-eligible sweep --json` over the live store (10.7 s wall):
**non_done = 350 · eligible = 28 (8.0%) · ineligible = 322 (92.0%).**

| refusal class | 2026-08-11 (plist) | 2026-09-22 (re-derived) | delta |
|---|---|---|---|
| `ineligible-box` | 155 | **146** | −9 |
| `ineligible-cross-repo` | *(class absent from the plist list)* | **84** | **+84 — the single biggest change** |
| `ineligible-offbox-lane` | 10 | **30** | +20 |
| `ineligible-visual` | 16 | **26** | +10 |
| `ineligible-spawn-rail` | 24 | **17** | −7 |
| `ineligible-branch-banking` | 25 | **11** | −14 |
| `ineligible-deep-history` | 15 | **3** | −12 |
| `ineligible-external-deploy` | — | 3 | new |
| `ineligible-github` | — | 1 | new |
| `ineligible-foreign-tree` | — | 1 | new |
| `ineligible-parked` | — | 0 | — |
| **eligible** | **45 of 312 (14.4%)** | **28 of 350 (8.0%)** | **−17 rows, −6.4 pp** |

Two caveats the delta needs. (a) The populations differ: the plist counted 312 *dispatchable* rows
(45 cloud / 236 local / 31 unlabelled); `sweep` counts 350 *non-done* rows. (b) The classifier
itself gained at least four classes since August, so `−9` on `ineligible-box` partly reflects rows
reclassified into `cross-repo`, not rows that became eligible.

**The finding that matters more than the histogram: the cloud lane's dispatchable queue is zero.**

```
eligible rows: 28  →  fold status:  28 blocked,  0 open
the 10 open rows  →  cc-eligible ELIGIBLE: 0
```

Every row `cc-eligible` would admit off-box is `blocked`. The lane is alive with nothing it is
allowed to pick up. This is not the pile cap and not an eligibility tightening — it is that the
backlog has drained to 10 open rows, none of them off-box-safe.

A durable cross-check from a different store — `venueWhy` on the 1,389 `event=="venue"` records:
all-time `ineligible-box` 631 · `eligible` 239 · `offbox-lane` 108 · `cross-repo` 93 ·
`deep-history` 76 · `visual` 74 · `spawn-rail` 65 · `branch-banking` 58 · rest ≤13. Since
2026-09-15 (150 records): `ineligible-box` 111 · `eligible` 18 · `deep-history` 14 · rest ≤2.

### 3.4 — Last successful end-to-end closure: **2026-09-22T02:43:35Z** (3h57m before this probe)

Not "never". The full trail for item `187ee2cb4252`, one row, four stores:

```
2026-09-22T01:57:02Z  backlog.jsonl  add
2026-09-22T01:57:12Z  backlog.jsonl  venue  venuePlan=cloud  ("eligible: no local-only spelling fired…")
2026-09-22T02:10:58Z  backlog.jsonl  claim
2026-09-22T02:11:40Z  cloud/session_01DvfDYpj559WrLYAFctQ8Y3.decl   branch=claude/fire-20260922T021133Z-61538-1
2026-09-22T02:43:35Z  backlog.jsonl  done   "cloud session_01DvfDYpj559WrLYAFctQ8Y3 → origin/main: tests/jev-predict-land.bats"
              …       cloud/session_01DvfDYpj559WrLYAFctQ8Y3.returned  outcome=returned goal=MET
              …       origin/main 93f58587a70f  trailer: Cloud-session: session_01DvfDYpj559WrLYAFctQ8Y3
```
**46 minutes, add → landed → closed.** Four prior closures: 2026-09-21T05:15:31Z, 2026-09-21T03:34:45Z,
2026-09-20T23:35:47Z, 2026-09-20T13:31:34Z.

Per-day cloud-attributed closures (110 items, first `done` record): 08-11 ×3, 08-12 ×3, 08-14 ×4,
08-15 ×2, **08-16 ×29**, 08-17 ×12, 08-18 ×6, 08-21 ×1, 08-23 ×2, 08-24 ×2, 08-25 ×6, 09-02 ×1,
09-03 ×1, **09-04 ×10**, 09-05 ×3, 09-06 ×1, 09-07 ×5, 09-09 ×1, 09-10 ×1, 09-12 ×2, 09-16 ×2,
09-17 ×5, 09-18 ×1, 09-19 ×2, 09-20 ×2, 09-21 ×2, 09-22 ×1.

### 3.5 — Is the lane 24/7? **YES. Two 300-second launchd clocks, both loaded and both ticking.**

`launchctl list | grep claude` shows no cloud-named job because **the return half of the lane is not
named `claude`** — it is `com.chrisren.autonomy-sweep`. Both halves:

| half | job | interval | state | evidence it is alive |
|---|---|---|---|---|
| **fire** | `com.claude.dispatcher` → `$HOME/.claude/bin/cc-dispatch --once` (`CC_FIRE_CLOUD=on`) | `StartInterval 300` | loaded, `runs = 517`, `last exit code = 0` | `/tmp/claude-dispatcher.stderr.log` written 06:05Z, one minute before this probe |
| **return** | `com.chrisren.autonomy-sweep` → `~/.claude/scripts/autonomy-sweep.sh` under `taskpolicy -c utility` | `StartInterval 300` | loaded, `runs = 265`, `last exit code = 0` | `~/.claude/logs/autonomy-sweep.err.log` written 05:52Z |

`autonomy-sweep.sh:713` detaches **`scripts/cloud-return-lane.sh`**, which is the cloud lane's own
tick: `fire-lane read` → `return pass` → `retire pass` → `answer pass`, each journalling its own
IDL row under `tool:"cloud-return-lane"`. It also runs `cloud-refusal-route.sh` (`:755`),
`branch-prune-landed.sh` (`:799`) and `cloud-retire-terminal.sh` (`:800`). Last three ticks, verbatim
from `~/.claude/logs/cloud-return-lane.log`:

```
2026-09-22T05:57:58Z fire-lane read rc=3 took=1s — UNKNOWN — refs dated <=20260907 read 334 against a pinned floor of 426 …
2026-09-22T05:58:09Z return pass rc=0 took=11s — pass completed — per-session outcomes in …/cloud/return.jsonl
2026-09-22T05:58:18Z retire pass rc=0 took=9s — cloud-retire-terminal: examined=0 gone=0 landed=0 superseded=0 conflict=0 young-held=0 kept=0 retired=0 failed=0 dry_run=0
2026-09-22T05:58:19Z answer pass rc=0 took=1s — cloud-answer: read 0 active session(s) — nothing read
```

The lane is running, on time, and has nothing to do: `examined=0`, `0 active session(s)`, and
`(no MANAGED cloud declarations)` on every pass. Declarations/day collapsed from 30–55 (2026-08-24 →
2026-09-04) to 1–6 since 2026-09-07.

---

## 4. Every command that produced a number

```bash
# --- stores and shapes
ls ~/.claude/autonomy/cloud/ | sed 's/.*\.//' | sort | uniq -c | sort -rn
#   727 .decl · 727 .retired · 697 .sends · 518 .seen · 99 .returned · 92 .woken
#   89 .land-refused · 85 .land-cost · 84 .refusal-route · 42 .close-attempts

# --- stage 1: rows routed venue=cloud
jq -r 'select(.event=="venue") | .venuePlan' ~/.claude/autonomy/backlog.jsonl | sort | uniq -c
#   1150 local · 239 cloud
jq -r 'select(.event=="venue" and .venuePlan=="cloud") | .id' ~/.claude/autonomy/backlog.jsonl | sort -u | wc -l   # 230

# --- stage 2: sessions declared
ls ~/.claude/autonomy/cloud/*.decl | wc -l                                            # 727
grep -h '^item=' ~/.claude/autonomy/cloud/*.decl | sed 's/^item=//' | sort -u | wc -l  # 182
grep -h '^item=' ~/.claude/autonomy/cloud/*.decl | sed 's/^item=//' | sort | uniq -c | sort -rn | head
#   38 01ab05685857 · 33 0c8b39b67665 · 30 f85fce7c26f5 · 30 e981656df348 · 30 70ed289c10fb

# --- stage 3/4: the repo's own state classifier (read-only; `poll` is the only mutator)
./bin/cc-cloud list --state --json > /tmp/backlog-probe/.cloud_list.json   # JSONL, 727 rows, rc 0
jq -r '.state' .cloud_list.json | sort | uniq -c
#   328 STALLED · 215 ABANDONED · 127 LANDED · 57 UNKNOWN
jq -r '[.state, (if (.last_sha//"")=="" then "no-sha" else "has-sha" end)] | @tsv' .cloud_list.json | sort | uniq -c
#   518 has-sha in total (126 LANDED + 328 STALLED + 57 UNKNOWN + 7 ABANDONED)
jq -r '[.state, (if (.paths//"")=="" then "NO-PATHS" else "has-paths" end)] | @tsv' .cloud_list.json | sort | uniq -c
#   215 ABANDONED NO-PATHS · 328 STALLED NO-PATHS · 127 LANDED has-paths · 55/2 UNKNOWN

# --- stage 4, instrument 2: provenance trailers on trunk
git fetch origin --quiet
git log origin/main --format='%B' > /tmp/backlog-probe/.trunk_bodies.txt
/usr/bin/grep -oE 'Cloud-session: *session_[A-Za-z0-9]+' .trunk_bodies.txt | sed 's/.*session_/session_/' | sort -u | wc -l   # 127

# --- stage 4, instrument 3: the return ledger
jq -r '.outcome' ~/.claude/autonomy/cloud/return.jsonl | sort | uniq -c
#   1816 abstain · 1030 land-refused · 932 pass-scope · 769 land-refused-cached · 419 land-deferred
#   242 waiting · 210 land-cut · 197 returned · 31 land-conflict · 21 pass-deadline · 20 dry-run
#   13 nothing-to-land · 4 superseded          (5704 rows, 2026-08-11T18:58:51Z → 2026-09-22T02:43:36Z)
jq -r 'select(.outcome=="returned" and .content_verified==true) | .id' return.jsonl | sort -u | wc -l   # 100

# --- union / floor, and the map to backlog rows
cat .cclist_landed.txt .trunk_cloud_sids.txt .landed_sids.txt | sort -u | wc -l   # 149 sessions
comm -12 .cclist_landed.txt <(comm -12 .trunk_cloud_sids.txt .landed_sids.txt) | wc -l   # 90 (floor)
# then per session: sed -n 's/^item=//p' <sid>.decl  → sort -u → comm -12 against the fold
#   union 116 real rows (113 done, 3 blocked) · cc-cloud-only 105 · floor 85

# --- stage 5/6: the backlog fold
./bin/cc-backlog list --all --json > /tmp/backlog-probe/.bl_all.json      # 3740 items, rc 0
jq -r '.[] | .status' .bl_all.json | sort | uniq -c      # 3390 done · 340 blocked · 10 open
jq -r '.[] | (.venue // "null") + "\t" + .status' .bl_all.json | sort | uniq -c
#   3260 local done · 337 local blocked · 130 cloud done · 10 local open · 3 cloud blocked
jq -rc 'select(.event=="done")' backlog.jsonl > .done_rows.jsonl          # 3633
jq -r 'select((tostring|test("session_01|cloud-worker|cloud session"))) | .id' .done_rows.jsonl | sort -u | wc -l   # 110

# --- the close-arm defect
jq -r 'select(.outcome=="returned") | .backlog' return.jsonl | grep -o 'could NOT mark [0-9a-f]* done' | awk '{print $4}' | sort -u | wc -l   # 44
jq -r 'select(.outcome=="returned") | .backlog' return.jsonl | grep -c 'getcwd'   # 34 of 105 rows
jq -r 'select(.outcome=="returned" and (.backlog|test("could NOT mark"))) | .ts' return.jsonl | cut -c1-10 | sort | uniq -c
#   08-11 ×1 · 08-12 ×2 · 08-14 ×21 · 08-15 ×11 · 08-16 ×58 · 08-17 ×12 · none after

# --- the pile cap (§3.1)
D=~/.claude/autonomy/cloud; n=0
for f in "$D"/*.decl; do id="${f##*/}"; id="${id%.decl}"
  [ -f "$D/$id.returned" ] && continue; [ -f "$D/$id.retired" ] && continue; n=$((n+1)); done
echo "$n"                                                                 # 0   (cap 50)
grep -c 'refusing ALL cloud fires' /tmp/claude-dispatcher.stderr.log       # 0  (rc 1)
for f in ~/.claude/autonomy/idl.jsonl.2026*.gz; do gzcat "$f" | grep -c 'cloud-pending-cap'; done   # 0 × 8

# --- liveness (§3.2)
bash scripts/cloud-lane-liveness.sh            # exit 3, UNKNOWN
bash scripts/cloud-lane-liveness.sh --json     # exit 3
bash scripts/cloud-lane-liveness.sh --assert   # exit 3
for f in ~/.claude/autonomy/cloud/branch-prune-manifest-*.tsv; do
  tail -n +2 "$f" | awk -F'\t' '{print $6}' | sort | uniq -c; done
#   PRUNE totals 76 across 09-05…09-15; 0 since 09-16 (343–347 HOLD-stranded per day)
git ls-remote --heads origin 'refs/heads/claude/*' | wc -l                 # 346  (rc 0)

# --- eligibility (§3.3)
time ./bin/cc-eligible sweep --json > /tmp/backlog-probe/.elig_sweep.json  # 10.7 s, rc 0
jq -c '.counts' .elig_sweep.json
#   {"ineligible-offbox-lane":30,"ineligible-spawn-rail":17,"ineligible-box":146,"ineligible-visual":26,
#    "ineligible-branch-banking":11,"ineligible-external-deploy":3,"ineligible-github":1,
#    "ineligible-parked":0,"ineligible-cross-repo":84,"ineligible-foreign-tree":1,
#    "ineligible-deep-history":3,"eligible":28,"unknown-item":0,"unknown-store":0}   non_done=350
jq -r '.eligible[]?.id' .elig_sweep.json | sort -u | join -t$'\t' - .fold_ids.tsv | cut -f2 | sort | uniq -c   # 28 blocked
jq -r '.[] | select(.status=="open") | .id' .bl_all.json | sort | comm -12 - <(jq -r '.eligible[]?.id' .elig_sweep.json | sort -u) | wc -l   # 0
jq -r 'select(.event=="venue") | (.venueWhy//"?") | split(":")[0]' backlog.jsonl | sort | uniq -c | sort -rn

# --- stranded bytes (§2c)
git for-each-ref --format='%(refname:short)' 'refs/remotes/origin/claude/*' | wc -l    # 346
# per ref: git rev-list --count origin/main..$r              → 553 commits over 346 refs
# per ref: git merge-base + git diff --name-only $b $r, then git diff --name-only origin/main $r -- <those files>
#                                                            → CONTENT-ON-TRUNK 1 · DIVERGENT 345
# per ref: git diff --diff-filter=A --name-only $b $r, then git ls-tree origin/main -- <path>
#                                                            → 88 refs add 155 files absent from trunk
tail -n +2 ~/.claude/autonomy/cloud/branch-prune-manifest-2026-09-22.tsv | awk -F'\t' '{s+=$3} END{print s}'   # 508

# --- refusal recovery and land cost (§2c)
ls ~/.claude/autonomy/cloud/*.land-refused | wc -l                         # 89
grep -h '^rc=' ~/.claude/autonomy/cloud/*.land-refused | sort | uniq -c     # 70×51 65×18 5×9 6×8 7/69/143×1
# intersect the 89 with the union-landed session set                        # 37 (41.6%)
cat ~/.claude/autonomy/cloud/*.land-cost | awk '{print $2}' | sort -n       # n=85 min=2 median=249 p90=2457 max=5250

# --- the clock (§3.5)
launchctl print gui/$UID/com.chrisren.autonomy-sweep   # loaded · run interval 300 · runs 265 · last exit 0
launchctl print gui/$UID/com.claude.dispatcher         # loaded · run interval 300 · runs 517 · last exit 0
grep -n 'cloud-return-lane\|branch-prune\|cloud-refusal-route\|cloud-retire' scripts/autonomy-sweep.sh
```

---

## 5. What I could NOT measure, and why

1. **Cloud sessions created but never declared.** The declaration store is written by
   `cc-cloud declare` *before* a fire; a session created out of band (`scripts/cloud-create-api.py`
   called directly, or a hand-started claude.ai session) leaves no local record, and I am forbidden
   from calling the cloud API. There is no `cloud-create` log anywhere under `~/.claude/logs/`.
   **727 is therefore a lower bound on sessions created**, and an absence in our own store bounds
   the store, not the world. It is an exact count of *declared* sessions, which is what every
   downstream gate actually reads.
2. **Whether a stalled ref's work is genuinely unlanded.** All three of my instruments have a known
   bias direction and I have stated each (§2c). No instrument on this box separates "the cloud
   commit's content is on trunk in a different shape" from "trunk moved past it". The only
   confound-free figure is the 155 added-and-absent files.
3. **When exactly the pile cap cleared.** IDL archives start 2026-09-12 and the live dispatcher
   stderr log starts 2026-09-21T05:36Z, so I can only bracket it: the cap was in force from
   2026-09-04T19:38Z (last pre-refusal declaration, exactly the brief's timestamp) and had cleared
   by 2026-09-07T06:23:48Z (first post-refusal declaration) — a 58.8-hour outage.
4. **Quota actually spent by the lane.** `*.land-cost` records the price of the *land* on this box
   (n=85, median 249 s), not the VM's token spend. Cloud sessions bill the same weekly Max meter
   per the dispatcher plist, but no per-session token record reaches this machine, so I cannot put
   a cost against the 545 duplicate fires.
5. **Whether the 2026-08-11 plist figures used the same classifier.** `ineligible-cross-repo`,
   `-external-deploy`, `-github` and `-foreign-tree` do not appear in the plist's list. I cannot
   re-run August's `cc-eligible` against August's queue, so part of the delta in §3.3 is
   reclassification rather than movement. Both populations are stated; neither is imputed.
6. **The `cc-cloud` UNKNOWN stratum (57 sessions).** `detail` reads `ref vanished after push of
   <sha>` — the branch was pruned before the classifier could adjudicate. `cc-cloud fill-paths`
   would resolve them but is a mutator of the declaration store, so I did not run it. They are
   counted in neither the landed nor the not-landed column.
