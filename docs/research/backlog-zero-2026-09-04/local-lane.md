# Local drain lane — why each link audits its predecessor instead of closing rows

**Answer in one line: the SSOT is not the source.** `§4.1` says "the drain session regenerates its
per-recycle brief from THIS". It does not. `~/.claude/autonomy/splice299.py:15-16` reads
`SRC = fire-drain-recycle299.txt` → `DST = fire-drain-recycle300.txt` — each brief is a **targeted
section replacement over its own predecessor's 300 KB brief**, and nothing ever pulls §4.1's text in.
So every §4.1 edit since 2026-08-31 — the closure floor, the `drain-recycle-fire.sh` chokepoint, the
goal — is invisible to the running chain. Grep of the live brief: `closure-report` **0**, `invariant
4` **0**, `closure floor` **0**; `drain-recycle-fire` **2**, both of them test-suite line counts
(`:756`, `:1555`). The chain's own memory says *"an ad-hoc message dies at the next brief, so land it
in §4.1"*. One layer deeper is true too: **a §4.1 edit dies at the brief as well.**

Live link is **#299** (not #297): pane 27, pid 99880, account `claude-next`, sid `706e2f80`, worktree
`.worktrees/drain/recycle-11`, launched 2026-09-04 11:12:01, registry name `recycle-11-27`.

---

## 1. §4.1 — every invariant, one line each (`docs/plans/BACKLOG_DRAIN_24_7.md`)

| # | line | verbatim gist |
|---|---|---|
| 1 | 31805 | *"Pick the smallest live `master-*` effort from the CURRENT fold …; claim its CONDITION (one lease covers the group)."* |
| 2 | 31807 | *"Per row: run the stored falsifier against a pristine origin/main worktree FIRST (exit 0 = retracting → close on that evidence); re-measure dated titles; landedness by CONTENT."* |
| 3 | 31809 | *"Close line format: `<effort>: N open / M blocked (K operator-gated)` — a zero without its blocked tail is the exact defect that produced this plan."* |
| 4 | 31811 | 🚨 *"THE CLOSURE FLOOR … **MET requires `C >= 1` AND `C >= F`** … it OUTRANKS invariant 6."* |
| 5 | 31832 | *"Operator-gated rows: platter via the cc-do/operator-readout rail, never burn turns on them."* |
| 6 | 31833 | *"THE CHAIN IS THE DELIVERABLE: firing recycle #N+1 … outranks finishing one more row."* — **DEMOTED below 4** (31836): *"It still outranks finishing ONE MORE row; it no longer outranks finishing ANY row."* |
| 7 | 31847 | *"THE BACK-CHANNEL MUST NAME SOMETHING THAT RESOLVES"* — ping `cc-notify 102 "HANDOFF-PING recycle #<N> …"`, second-to-last action (31904-31906). |
| 8 | 31963 | *"SET `SHIP_LAND_SMOKE_BUDGET_S=420` ON THE FIRST LAND whenever the diff touches a file with a big suite."* |
| 9 | 31988 | *"RESOLVE A STORE'S PATH FROM ITS PRODUCER — 'THE DIRECTORY EXISTS' CANNOT TELL YOU IT IS THE RIGHT DIRECTORY."* (added by #296) |

**Yes, there IS a row-selection instruction — invariant 1** (claim the smallest live `master-*`
condition group), plus invariant 2's per-row falsifier pass. **No project filter, no oldest-first
order.** Invariant 6's own text is what the chain optimizes: *firing outranks finishing.* Its
demotion (2026-08-31) is real in §4.1 and has never reached a brief.

⚠️ **Invariant 9 is the tell.** It is a 42-line essay about a `find` path in the chain's own census
script — §4.1 has itself become a place to file methods.

---

## 2. What the live brief actually orders (`~/.claude/autonomy/fire-drain-recycle299.txt`, 3,366 ln / 299 KB)

| brief section | line | what it directs |
|---|---|---|
| opening | 1-45 | #298's grep-symlink finding — *"READ § #298 FOUND… BEFORE YOU GREP ANY TREE"* |
| FIRST FOUR THINGS | 335 | export PATH · instrument-fault warnings. Not a row. |
| THE BOARD — RE-DERIVE EVERYTHING | 1389 | census arrivals/departures. **1417: *"`ca97c678b18b` has now moved AGAIN. Report it; do not take it."*** |
| SCREEN ORDER | 1381-1383 | **a 35-item queue of METHOD numbers** (`213 → 211 → 210 → …`), not row ids |
| YOUR RECOMMENDED START | 1453-1461 | count `*.page` files in the chain's own store, three times per link |
| THE ONE THING TO TAKE | 887 | *"WHAT POPULATION DOES YOUR INSTRUMENT WALK?"* |
| THE STRONGEST LEADS | 2627-2658 | 0 = re-ask every "nothing/nowhere" sentence · 1 = build a grep lint · 2 = `wrap-ledger.sh` candidate C |
| CHAIN DUTY | 3270-3282 | `bash scripts/handoff-fire.sh --recycle --prompt-file ~/.claude/autonomy/fire-pointer-300.txt` |

🚨 **No instruction anywhere tells the link to claim a row.** `grep -in 'cc-backlog claim|claim the|
claim a row|--open --project'` over the whole brief → 2 hits, both unrelated prose. All 42
`cc-backlog` mentions are test-suite sizes, stderr-site counts, or fold syntax.

🚨 **And every `master-*` group invariant 1 names is excluded BY NAME in the brief** — 6 hits, all
bans or observations:
- `:1385` *"DO NOT RE-WORK BUCKET (A) … `master-operator-gated` … genuine operator gates"*
- `:2873` *"NOT drain pickups: `6464f9d641ff` (all ten `master-fire-gate` rows)"*
- `:2949` *"`master-convergence-deadlock`'s open rows are STILL not a general drain population — #184–#241 all found this"*

The exclusions accreted over ~115 links and are inherited by splice. Invariant 1's population has
been argued to zero inside the brief, while §4.1 still says to claim from it.

---

## 3. The last 12 §2.1 entries — what each link spent itself on

Every one opens with the same clause. Sizes are the entry's own line count.

| recycle | §2.1 line | lines | subject — every one names its predecessor |
|---|---|---|---|
| #297 | 89 | 110 | "#296 asked what population an instrument's count is taken over" |
| #296 | 199 | 128 | "#295 asked what each ARM of one ladder…" |
| #295 / #294 / #293 | 327 / 392 / 516 | 65 / 124 / 89 | ladder arms · a field's comment vs its code · "#292 counted the consumers of a deli…" |
| #292 / #291 / #290 | 605 / 696 / 842 | 91 / 146 / 104 | "#291 attributed a conjunction's ZERO to a conjunct" · "#289 left clause 4b's zero as its cheapest lead" |
| #289 / #287 / #286 | 946 / 1153 / 1274 | 92 / 121 / 115 | tokeniser boundaries · scopes · "a conjunction of correct clauses can describe a thing that does not exist" |
| **#288** | 1038 | 115 | **`:1040` *"The route was the cheapest one in the brief for the thirteenth time: go where your predecessor pointed"*** |

All twelve open with the literal clause **"ZERO rows closed, ZERO filed, ZERO reopened"** (#294 adds
"ONE row UPDATED"); each reports one or two commits and one push.

Median entry ≈ 112 lines against §4.1's *implied* close line of one. All twelve are about
`scripts/pipefail-sigpipe-lint.sh`, `postland-verify.sh`, census instruments — the drain's own tools.

---

## 4. MEASURE (a) — per-recycle closures, filings, commits

Windows bounded by `handoffs.jsonl` `recycle-intent` rows whose `prompt_file` is `fire-pointer-<N>.txt`.
`CLOSED` = distinct ids with `event=done, lane=local-drain` in-window. `DRAIN` / `OTHER` = trunk
commit subjects starting `docs(drain)` vs everything else (**`OTHER` includes sibling sessions** — the
whole fleet lands to this trunk, so it is an upper bound, not the drain's own).

| N | CLOSED | FILED | DRAIN | OTHER | note |
|---|---|---|---|---|---|
| 250–260 (11 links) | **0** | 15 | 14 | 62 | #259 spans 41 h (the 40.5 h chain death window) |
| **261** | **2** | 3 | 1 | 1 | closure floor written into §4.1 that day |
| **262** | **3** | 0 | 1 | 1 | |
| 263 | 0 | 1 | 1 | 1 | |
| **264** | **1** | 0 | 2 | 2 | |
| 265–277 (13 links) | **0** | 0 | 19 | 24 | thirteen consecutive zero-close links |
| **278** | **1** | 5 | 1 | 10 | |
| 279–298 (20 links) | **0** | 81 | 32 | 118 | twenty consecutive zero-close links |
| **299** (live) | **1** | 1 | — | — | closed `115ee778401a` 15 min in |

**#250–#298 = 49 links, 7 rows closed, 105 filed.** 45 of 49 links closed **zero**. Filed:closed ≈ **15:1**.
Exactly **one** `docs(drain)` §2.1 commit per link, 49 of 49. Peak filing: #281 (13), #291 (12),
#289 and #290 (10 each) — all zero-close.

**The rows the drain actually closed** (all `project=claude-infrastructure`, all
`closedBy=chriss-macbook-pro-3-recycle-11`):

| ts | id | filed by | title (truncated) |
|---|---|---|---|
| 2026-08-31T00:27:14Z | `ff4e6cbead11` | `lead-102` | 35-auth-timeseries keychain-ACL gate FAILS OPEN… |
| 2026-08-31T00:27:19Z | `85fc4f3216a7` | `needs` | UNLOAD or properly activate com.claude.auth-timeseries… |
| 2026-08-31T01:08:49Z | `c446beb6ad28` | `needs` | Restart the 24/7 drain chain: open a FRESH terminal tab… |
| 2026-08-31T01:09:13Z | `92b48ac81692` | `needs` | deploy-live cannot converge: no GREEN tree descends… |
| 2026-08-31T01:09:36Z | `cb10454ead99` | `needs` | email guardrails LANDED but NOT YET ENFORCING… |
| 2026-08-31T02:33:59Z | `48f01c02cf09` | `needs` | converge the live layer onto the mail-hook change… |
| 2026-09-01T04:49:26Z | `32d12fde0469` | `needs` | drain recycle: --recycle's /exit blocked by the modal… |
| 2026-09-04T11:27:19Z | `115ee778401a` | measured 2026-08-23 | wake path unarmable in .claude-next… |

⚠️ **Six of the seven historical closes were `needs` rows — the operator-gated class invariant 5 says
never to burn turns on** — and all cluster on 2026-08-31, the day the closure floor was written into
§4.1. A one-day compliance spike, then decay to zero. The chain read the SSOT once, by hand.

## MEASURE (b) — 64 lifetime local-drain closes, by who filed the row

| filer | n |
|---|---|
| drain-authored (`source` matches `drain`/`recycle`) | **12** |
| filed by someone else | **52** |

Age at close: median **143 h**, max **594 h**; 7 closed <2 h after filing, 12 within 24 h. So
self-filed-then-self-closed is a real but minority pattern (~19%).

## MEASURE (c) — the plan file's growth

| | |
|---|---|
| `BACKLOG_DRAIN_24_7.md` total | **32,959 lines** |
| §2.1 span (lines 88–31,493) | **31,405 = 95.3%** of the file |
| added in last 14 days | **25,490** (77.3% of the file); deleted 130 |
| commits touching it in 14 d | **270** |
| 7-day trunk: `docs(drain)` / all | **63 / 273** |

The file is monotone-growing at ~1,800 lines/day and the SSOT (§4.1, 335 lines) is 1% of it.

---

## 5. Is the closure-floor goal armed? **No — and it never has been on this chain.**

`~/.claude/logs/handoffs.jsonl`, class `recycle-intent`, whole log: **125 `goal_requested:false` vs
19 `true`.** Every one of the 19 `true` rows is a *different* pointer (`fire-reso-marketing-kit.txt`,
`fire-lakehouse-continue.txt`, `recycle-drain.txt`…) — **not one is `fire-pointer-<N>.txt`.**

| ts | pointer | pane | account | goal_requested |
|---|---|---|---|---|
| 2026-09-04T00:33:23Z | fire-pointer-293.txt | 27 | next2 | **false** |
| 2026-09-04T02:27:17Z | fire-pointer-294.txt | 27 | next | **false** |
| 2026-09-04T03:25:01Z | fire-pointer-295.txt | 27 | next | **false** |
| 2026-09-04T04:59:37Z | fire-pointer-296.txt | 27 | next | **false** |
| 2026-09-04T05:44:35Z | fire-pointer-297.txt | 27 | next | **false** |
| 2026-09-04T06:38:06Z | fire-pointer-298.txt | 27 | next | **false** |
| 2026-09-04T11:11:51Z | fire-pointer-299.txt | 27 | next | **false** |

**Where it fires from:** brief `:3282` — `bash scripts/handoff-fire.sh --recycle --prompt-file
~/.claude/autonomy/fire-pointer-300.txt`. **It does not go through `drain-recycle-fire.sh`.** That
script is on trunk, has 20 green bats (`tests/drain-recycle-fire.bats`), and is invoked by nobody.
The condition it would arm (`--num 298 --print-goal`, 1,004 chars) has never appeared in a `goal-arm`
row — the last 8 `goal-arm` conditions are 307–847 chars, all other panes.

⚠️ **§4.1 also warns that `--recycle` INHERITS a live goal** (31747). It cannot rescue this: the
inherited goal would have to originate somewhere, and there is no `goal-arm` row for pane 27 at all.

---

## 6. Why `closed>=1 and closed>=filed` is too weak — measured, not argued

`scripts/drain-recycle-fire.sh:82-89` is the whole predicate. Four defects, each verified by
executing the tool:

1. **It is LANE-BLIND.** `lane` appears **0 times** in the jq filter. The goal's own constraint —
   *"do not satisfy the floor … by counting another lane's closures"* (`:115`) — is unenforceable by
   the instrument the goal names.
2. **It is PROJECT-BLIND.** `--arg proj "$PROJECT"` is bound at `:82` and **never referenced** in the
   filter body. **`CC_DRAIN_PROJECT` therefore governs nothing** — its only two occurrences in the
   whole repo are `drain-recycle-fire.sh:55` (a comment) and `:63` (the assignment).
3. **The window has no upper bound.** `--closure-report <since>` counts to *now*. Live run over the
   #298 window returned `closed=2 filed=9 blocked=3 floor=UNMET` — and **both** closes were outside
   #298: one `lane=land` (a sibling) and one `lane=local-drain` at 11:27Z, which is **#299's**.
4. **One row clears it.** Over the last 7 days other lanes closed `session` 17 · `land` 15 · `NONE` 9
   · `sweep` 5 · `cloud` 3 = **49 closes the drain did not make**, every one of them admissible to
   this floor.

**A stronger, still-evaluable condition** (the evaluator is tool-less, so every clause must be a
token a command PRINTS):

```
closed_by_me >= 3 AND filed_by_me == 0 AND drain_docs_lines <= 15
```

surfaced by one new `--closure-report --until <ISO> --mine` mode that filters
`lane=="local-drain" and closedBy==$HOST_WORKTREE`, bounds the window at both ends, prints the row
**ids and titles** it counted, and adds `entry_lines=<N>` read from `git diff --numstat` of this
link's own `docs/plans/BACKLOG_DRAIN_24_7.md` hunk. Evaluable because all four numbers are in one
printed block; falsifiable because the ids are named.

---

## 7. Proposed §4.1 rewrite — ranked invariants

**R0 (new, above everything). THE BRIEF IS REGENERATED FROM §4.1, NOT FROM THE PREDECESSOR.**
`splice<N>.py` must copy §4.1 lines 31804-32037 verbatim into the successor brief as its **first**
section, and the fire must refuse if the successor brief does not contain the literal string
`--closure-report`. Without R0 every invariant below is unreachable — that is the finding.

**R1. FIRST ACT, BEFORE ANY CENSUS.** Print
`cc-backlog list --open --project "$CC_DRAIN_PROJECT" | awk -F'|' '$1 ~ /open/'` sorted oldest-first
and `cc-backlog claim <top workable id> --by <sid>`. ⚠️ **`--open` does not filter** — measured, it
returns blocked and claimed too (claude-infrastructure: 206 open + 130 blocked + 6 claimed = 342
lines; reso: 124 + 70 = 194). Either fix `cc-backlog list` or keep the `awk` guard in the invariant.

**R2. THE §2.1 ENTRY IS CAPPED AT 15 LINES** and must contain, on line 1, the ids closed. A method
that wants an essay goes to `docs/research/<topic>.md`, one file per method, linked by one line.

**R3. MACHINERY WORK IS ALLOWED ONLY WHEN A CLAIMED ROW REQUIRES IT** — and the row id must appear in
the commit trailer. A `docs(drain)` commit with no claimed row in its trailer is the defect.

**R4. FIRING IS UNCONDITIONAL AND LAST** (invariant 6 unchanged in mechanism, permanently below R1).

**R5–R9** = current invariants 2, 3, 5, 7, 8. **Invariant 9 moves out** to `docs/research/` under R2.

**Should the chain run on all projects?** Yes for `reso-management-app`, and it is nearly free:
`CC_DRAIN_PROJECT` is a dead variable today, so pointing the lane at reso costs one jq edit
(`select(.project==$proj)`) plus one line in R1. **124 open reso rows** sit in
`master-product-repos` (open=32 / blocked=18 in the fold) — the largest agent-reachable group on the
board and the one invariant 1's *"smallest live `master-*` effort"* heuristic reaches **last**.
⚠️ That heuristic is itself anti-throughput: today the smallest live groups are
`master-fleet-footprint` (open=1) and `master-session-lifecycle` (open=1). Replace "smallest" with
"largest agent-reachable", or drop grouping and go oldest-first.

**Board today** (`cc-backlog fold`, LIVE 2026-09-04T11:38:11Z): open **371** · blocked **242** ·
claimed 6 · done 2,391 over 3,010 rows.

---

## 8. Cost per link

Recycle #298 (sid `33839051`, 4 h 34 m): **117 assistant turns · 41.64 M cache-read input tokens ·
0.47 M cache-write · 0.148 M output · 117 tool calls · 2.28 MB transcript** → **zero rows closed, one
110-line §2.1 entry.** At Opus-5 list rates that is ≈ **$27 of quota per link**; the chain has run 49
such links in the measured span. Context fill at recycle across the last 14 links: **35–75%** of a
1,000,000-token window (`~/.claude/autonomy/recycle-events.jsonl`, `hook:"context-econ"`).

---

## 9. Adversarial pass — what I checked that argues the other way

- **The findings are real, and killing them has a cost.** #297 and #298's essays landed genuine
  repairs on trunk (`0eb34ecea` stamps-store consumer census keyed on the path, missed 5 of 7;
  `218d2a636` `grep -R` is not symlink-following, and two landed claims rest on it). A rewrite that
  forbids machinery work outright would have suppressed both. R3 (allowed *when a claimed row
  requires it*) is deliberately narrower than a ban.
- **"Close more rows" is not automatically higher value.**
  `docs/research/backlog-drain-netpositivity-2026-08-25.md:18-31`: *"40–55% of the 2,294 closures
  match a verbatim no-op disposition"*; the agent-facing board *"sat at 287 ± 38 for 19 days while
  1,635 items were closed inside it"*; and the 2026-08-09 full-corpus triage pruned 35.2% of a
  460-row pool and *"bought nothing"*. The floor should therefore demand **closes with same-moment
  content evidence**, which the goal condition already says and no instrument checks.
- **The one mechanical sensor on this chain measures the wrong thing.**
  `scripts/drain-chain-assert.sh` asserts *liveness only* (`alive ⟺ drained ∨ handover-grace ∨
  live-lease ∨ progressing`, §6:32077-32080). A chain that fires forever and closes nothing is
  **maximally healthy** by it. Nothing on this box asserts drain *productivity*. The stamp that does
  is a one-line file nobody routes: `~/.claude/autonomy/.drain-health.stamp` reads
  `2026-09-04 rc1 drain-futile effort-productive` (mtime Sep 3 18:08).
- **#299 is closing rows — is the premise stale?** It closed `115ee778401a` 15 min in. I checked for
  an intervention: `~/.claude/mailbox/27.md` is dated **Aug 25** — the lead has not paged this chain
  in ten days — and the id appears nowhere in brief 299. So the close is organic, and n=1 against 45
  consecutive zero-close links.
- **Is the ping target alive?** No. §4.1:31904 prescribes `cc-notify 102 …`; there is no
  `102.json` in `~/.claude/cc-registry` and `cc-sessions --names` lists no pane 102. Invariant 7's
  address is now as dead as the `<N-1>` spelling it replaced. Brief `:3316` already records this
  (*"§4.1's OWN PING EXAMPLE IS STALE, WHICH COST #294 TWO REFUSED SENDS"*) — the brief knows and
  §4.1 does not, which is the SSOT inversion in miniature.

## 10. Blockers / uncertainties named

- `OTHER` commits in §4's table are **fleet-wide**, not drain-attributed. Attributing them needs
  per-commit branch/author resolution I did not run.
- `docs/research/drain-telemetry-2026-08-25/` is about **quota-window planning**, not this lane —
  its `SYNTHESIS-design.md` verdict (`K = 0.192` weekly-pp per session-pp, 43 pp stranded across 8
  account-weeks) is unrelated to backlog drain. Do not cite it here.
- The 65-vs-64 local-drain discrepancy is one id closed twice (65 events, 64 distinct ids).
- I did not read `bin/cc-backlog`'s `done` implementation in full. What I verified: `:93` documents
  `done <id> --evidence <ref> → ALSO stamps lane`; `:1791 _bl_derive_lane` derives the lane from
  **process ancestry anchored on argv position** (`ship-land.sh` ⇒ `land`; `claude` ⇒ `session`),
  `CC_BACKLOG_LANE` overrides it against a closed-set validator `_bl_lane_valid` (`:1749`), an
  unknown value **falls through to derivation and warns** rather than minting a bogus lane, and a
  lane-less `done` keeps no lane (`:1731`) because *"inferring one would manufacture precisely the
  certainty the readout exists to measure the absence of."* `lane` is a property of the **record**,
  not the item (`:1741`). Closing with evidence is therefore `cc-backlog done <id> --evidence "<text>"`
  run from inside the drain session, which is what stamps `lane=local-drain`.
