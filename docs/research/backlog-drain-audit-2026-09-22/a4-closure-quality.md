# A4 — cc-backlog closure QUALITY audit (read-only)

Store: `~/.claude/autonomy/backlog.jsonl` — 23,348 records, **0 parse failures**, 3,740 distinct ids.
Oracle: `origin/main` = `e3f7a2e7c9a3ccf2c52f1457137cf0bca44c759b`. Measured 2026-09-22. Nothing mutated.

Population under test = **3,389 TERMINAL closures** (ids whose LAST event is `done`; 3,633 `done`
EVENTS exist, 3,394 distinct ids carry one, 5 were later re-opened).

---

## 1. HEADLINE

**Trunk-verified delivery: 38.4% (1,303 / 3,389) all-time; 32.9% (407 / 1,237) in the last 30 days.
No-op closures: 47.3% all-time, 48.8% in 30 days.** The balance (14.3% / 18.3%) claims an artifact
this repo's git cannot adjudicate — overwhelmingly another repo's work, not a fake closure.

Restricted to the population where the oracle actually works (`project == claude-infrastructure`,
n = 2,408): **50.4% delivered · 10.3% claimed-elsewhere · 39.2% no-op.** In the last 30 days that
repo's delivered fraction falls to **41.9%** and its no-op fraction rises to **47.6%** — driven
entirely by auto-retraction (13.9% → 21.1%).

**The recorded lesson "40-55% of closures were no-ops" is CONFIRMED by an independent fold today:
47.3% all-time, 48.8% over 30 days.** Its second half is confirmed too — the delivered fraction has
**no measurable trend**: weekly values 13.3 · 56.9 · 41.4 · 63.2 · 48.4 · 39.7 · 19.6 · 14.1 · 46.8 ·
31.0 · 37.5 %, whose week-over-week delta **changes sign 6 times in 11 weeks**. A slope fitted to that
is a fact about the window chosen, not about the drain.

Corroboration from a sibling instrument with a different state model (`cc-value`, 24 h window):
`DRAIN 185 claim(s) over 13 distinct id(s) → 12 reached done (92.3%) · reclaim 14.2x per id`.
92% of claims close, but it took 185 claims to finish 13 items.

---

## 2. CLASSIFICATION TABLES

Method: every terminal record's `evidence` (the disposition text) folded by a **position-adjudicated**
ladder — auto-retraction markers first; then whichever of {no-op verdict, delivery verb/sha} appears
FIRST in the leading 260 chars wins; then the git verdict; then a body scan. Position adjudication is
load-bearing: `landed 588d49be6 — the handoff-fire.sh half is already on trunk …` (row `4a0e50459ad5`)
is a DELIVERY whose head also contains "already on trunk"; a marker-presence classifier scored it
`superseded`. v1 (presence-only) read 35.3% delivered; v2 (position) reads 38.4%.

### ALL TIME (n = 3,389)

| class | n | % |
|---|---:|---:|
| delivered-artifact (sha ancestor of / content on trunk) | 1,303 | 38.4% |
| delivered-claimed-unverifiable (no resolvable sha here) | 483 | 14.3% |
| superseded / already-true / moot | 309 | 9.1% |
| premise-refuted / retracted / withdrawn / "not a defect" | 594 | 17.5% |
| duplicate / consolidation-prune | 229 | 6.8% |
| auto-retracted (machine, no work) | 335 | 9.9% |
| no-disposition-recorded (empty evidence) | 57 | 1.7% |
| other | 79 | 2.3% |
| **REAL DELIVERY** | **1,303** | **38.4%** |
| **NO-OP CLOSURES** | **1,603** | **47.3%** |

### LAST 30 DAYS (n = 1,237)

| class | n | % |
|---|---:|---:|
| delivered-artifact | 407 | 32.9% |
| delivered-claimed-unverifiable | 226 | 18.3% |
| superseded | 213 | 17.2% |
| premise-refuted | 107 | 8.6% |
| duplicate | 20 | 1.6% |
| auto-retracted | 203 | 16.4% |
| no-disposition-recorded | 16 | 1.3% |
| other | 45 | 3.6% |
| **REAL DELIVERY** | **407** | **32.9%** |
| **NO-OP CLOSURES** | **604** | **48.8%** |

### THE TWO DRAIN PIPELINES

By `venuePlan` label (the dispatcher's local-vs-cloud routing decision; only 1,065 terminal rows
carry one — the label post-dates most of the store):

| venue | n | delivered | +claimed | no-op |
|---|---:|---:|---:|---:|
| local | 919 | 442 (48.1%) | 61.2% | 357 (38.8%) |
| cloud | 146 | 43 (29.5%) | 72.6% | 40 (27.4%) |
| unlabelled | 2,324 | 818 (35.2%) | 48.1% | 1,206 (51.9%) |

By `lane` on the `done` record:

| lane | n | delivered | no-op | note |
|---|---:|---:|---:|---|
| session | 493 | 259 (52.5%) | 29.0% | the honest drain — best delivery rate in the store |
| local-drain | 386 | 91 (23.6%) | 56.5% | 42.0% of its closures are `superseded` |
| cloud | 33 | 2 (6.1%) | 0.0% | see below — this row is an artifact of the sha regex |
| sweep | 71 | 0 | 68 (95.8%) | pure auto-retraction |
| land | 73 | 0 | 73 (100%) | pure auto-retraction |
| (no lane) | 2,333 | 951 (40.8%) | 47.2% | pre-lane era |

**The cloud lane's 6.1% is an instrument artifact, corrected here.** Cloud evidence is shaped
`cloud session_<id> → origin/main: <paths>` and cites no sha, so the sha-keyed audit scores it
`no-sha`. Checked the other way — do the cited paths exist on trunk — **56 of 56 cloud rows pass
(100%)**. Read cloud as ~100% delivered, not 6%.

### By project (delivery is only adjudicable in this repo)

| project | n | delivered | claimed | no-op |
|---|---:|---:|---:|---:|
| claude-infrastructure | 2,408 | 1,214 (50.4%) | 249 | 945 (39.2%) |
| reso-management-app | 575 | 9 (1.6%) | 147 | 419 |
| reso-qa-runner | 135 | 0 | 0 | 135 |
| doc_classifier | 46 | 0 | 39 | 7 |
| others | 225 | 0 | 34 | 191 |

The 1.6% for reso is **not** a finding about reso — it is this oracle answering a question about a
repo it cannot see (`absent-from-trunk-has-two-opposite-causes`).

---

## 3. THE 15-SAMPLE VERIFICATION

Random sample (seed 2026) of 15 rows classified `delivered-artifact`, each re-adjudicated from
scratch: resolve every cited sha, `merge-base --is-ancestor <sha> origin/main`; on rc 1 fall through
to a blob-by-blob content check over the paths the commit touched; plus `cat-file -e origin/main:<path>`
for every file path cited in the prose.

**PASS RATE: 15 / 15 = 100%.** Ids: `a31d1fe3de3d 09f087a7f3d8 88b6e65e4acf 004d154032e8 0c5d47c863bf
3208342f2f4c ba54591adaec b885c06e78fe d72ae1b6a74a 3517d2df3dcd 5a629c6465d1 56e82c56fb07
19995fa8df43 0754ce1bf2aa 02ad49233919`. Every one had ≥1 cited sha that is a live ancestor of
`origin/main`; 5 also cited paths, all present on trunk (21/21 path checks).

Note the honest limit: this sample is drawn from rows the audit already scored `on-trunk`, so it
verifies the audit's arithmetic independently, not the whole population. **The adversarial sample is
the informative one:** 15 random `delivered-claimed-unverifiable` rows. 3 PASS (all cited paths on
trunk), 9 cite no path at all (state/live-layer claims: "sentinel daemon now pid 42344 running
post-fix bytes", "pane 276 absent, pid dead" — real but unfalsifiable from git), 3 "FAIL" — and all
3 fail because their paths are in OTHER repos (`tests/integration/test_fixture_intake_mirror.py`,
`rules/agent-teams.md`, `scripts/setup/clone-heist-floorplan-to-the-key.ts`). **Zero fabricated
closures found in 30 verified rows.**

`SUSPECT` from the shipped audit is 102 rows = **4.6% of scored**, and sampling 6 of them shows they
are not fake closures either: they are honest no-op dispositions that cite a sha for CONTEXT
(`"cited sha e7e2ea9445b3 is NOT an ancestor of origin/main (never landed)"` — the row says so
itself), or a branch verified by patch-id rather than by object. The false-closure rate this store
supports is **~0%**; the defect is not lying, it is **closing rows that never needed work**.

---

## 4. THE AUTO-RETRACTION ARM

Terminal closures produced by machinery rather than by work:

| arm | all-time | % of all closures | last 30 d | % of 30 d |
|---|---:|---:|---:|---:|
| `auto-retracted at filing` (land-content-verify: the land died AFTER its content landed) | 195 | 5.8% | 111 | 9.0% |
| `cc-premise sweep --close-falsified` (stored falsifier passed) | 115 | 3.4% | 73 | 5.9% |
| other auto | 15 | 0.4% | 15 | 1.2% |
| dispatcher step 1d `premise-retracted:` (stale `plan-open`) | 10 | 0.3% | 4 | 0.3% |
| **TOTAL** | **335** | **9.9%** | **203** | **16.4%** |

Over all 3,633 `done` EVENTS (not just terminal): 393 = **10.8%**.

Two findings. (a) **Step 1d is nearly inert** — 10 retractions all-time, 4 in 30 days. It is not what
inflates the count. (b) **The inflation is the land re-file loop**: `auto-retracted at filing` mints a
re-land row and retracts it in the same breath, 195 times, and it is *accelerating* (5.8% → 9.0%).
Lanes `land` (73/73) and `sweep` (68/71) are **100% and 96% machine closures with zero delivery** —
any closure count that includes them is reading its own plumbing.

---

## 5. RE-MINT RATE

A closed row is "re-minted" if a NEW id was `add`ed after the close carrying a near-identical title.

**96 / 3,389 = 2.83%** (identifier-preserving match: jaccard ≥ 0.85 or sequence ≥ 0.92 on titles with
shas, branch names and timestamps LEFT IN). All 96 were re-filed within 30 days of their close.

By source class:

| class of the closure that re-minted | rate |
|---|---:|
| **auto-retracted** | **64 / 335 = 19.1%** |
| duplicate | 10 / 229 = 4.4% |
| superseded | 4 / 309 = 1.3% |
| delivered-artifact | 15 / 1,303 = 1.2% |
| delivered-claimed-unverifiable | 2 / 483 = 0.4% |
| premise-refuted | 1 / 594 = 0.2% |

**The re-mint is an auto-retraction disease, 16× the rate of a delivered closure.** Sample:
`5dcc620e96b9 → 2a3e208e491d`, both `re-land local-drain (/Users/chrisren/Development/.worktrees/local-drain):
ship-land exited 6`, **+0 days**. The auto-filer files, the auto-retractor closes, the auto-filer
files again.

A looser normalizer that strips shas/dates (i.e. treats one TEMPLATE as one subject) reads 148 = 4.4%
— the extra 52 are distinct incidents from the same producer template, not re-mints. The 2.83% figure
is the defensible one.

**Temporal: every re-mint hit closed in 2026-07 (1) or 2026-08 (95). Newest: 2026-08-18. Zero in the
last 30 days** — against 1,042 September closures, so this is not censoring at that magnitude. The
re-mint loop appears to have been fixed or its producer retired between 2026-08-18 and now.

---

## 6. cc-premise COVERAGE — the 51.5% figure does NOT re-derive, and the denominator is why

Three denominators, all measured today:

| denominator | covered | pct |
|---|---:|---:|
| `cc-premise coverage` probeable (open ∨ claimed, its own definition) = **9** | 2 | **22.2%** |
| all non-done rows in the fold = **350** | 34 | **9.7%** |
| `open` rows only = **10** | 3 | 30.0% |

`launchd/com.claude.dispatcher.plist:76` and `scripts/backlog-ratchet.sh:40` cite **51.5%**. That
number was taken over a live population of **307** rows (`304 open + 3 claimed, of which 157 carry a
probe`, per the ratchet's own header). **Today that population is 10.** The fold is 350 rows: 340
blocked, 10 open. So 51.5% has not fallen to 22.2% — the two are computed over populations differing
by 30×, and the comparison is void. The comment is stale, not wrong-at-the-time.

Currently evaluating to "no longer needed": `cc-premise sweep --json` (read-only — `--record`,
`--limit` and `--close-falsified` all withheld, and each write path in the source is gated on exactly
those flags: `bin/cc-premise:3137` `if record:`, `:3154` `if limit > 0:`, `:3158` `if close_cap > 0:`):

```
non_done 350 · assessed 34 · probe_capable 34 · unprobed 316 · deferred 0
falsified 1 · superseded 0 · self_duplicate 1 · corrected 1 · suspect 20
closed_falsified 0 · validated_recorded 0 (not-requested)
```

**1 of 34 probed rows (2.9%) currently says "no longer needed".** 316 of 350 rows (90.3%) can be
asked by no arm at all.

---

## 7. EVERY COMMAND THAT PRODUCED A NUMBER

```bash
# §1 the shipped audit, verbatim (full output at /tmp/backlog-probe/audit-verbatim.txt)
cd ~/Development/claude-infrastructure
python3 scripts/backlog-closure-audit.py --json /tmp/backlog-probe/closure-audit.json
python3 scripts/backlog-closure-audit.py --show 4 > /tmp/backlog-probe/audit-verbatim.txt 2>&1

# §2 the independent disposition fold (script: /tmp/backlog-probe/classify2.py)
python3 /tmp/backlog-probe/classify2.py        # → /tmp/backlog-probe/classified2.json
python3 /tmp/backlog-probe/classify.py         # v1, presence-only ladder, kept as the control

# §3 verification samples
python3 /tmp/backlog-probe/verify15.py             # 15 delivered-artifact  → 15/15
python3 /tmp/backlog-probe/verify_unverifiable.py  # 15 claimed + all 56 cloud rows
git -C ~/Development/claude-infrastructure merge-base --is-ancestor <sha> origin/main
git -C ~/Development/claude-infrastructure rev-parse <sha>:<path>      # content check
git -C ~/Development/claude-infrastructure cat-file -e origin/main:<path>

# §5 re-mint
python3 /tmp/backlog-probe/remint.py    # loose normalizer  → 148 = 4.4%
python3 /tmp/backlog-probe/remint2.py   # identifier-preserving → 96 = 2.83%

# §6 premise coverage (all read-only)
python3 bin/cc-premise coverage --json
python3 bin/cc-premise sweep --json > /tmp/backlog-probe/premise-sweep.json
bash bin/cc-backlog list --json > /tmp/backlog-probe/fold.json
grep -n "51.5" launchd/com.claude.dispatcher.plist scripts/backlog-ratchet.sh

# cross-check
bash bin/cc-value
```

### The audit's own output, verbatim

```
done rows with evidence: 3537
sha candidates: 3765  resolve here: 2203
  of those, ancestors of origin/main: 1775

=== VERDICTS ===
  on-trunk          2059
  content-landed      11
  partial             59
  SUSPECT            102
  foreign            686   (not scored)
  no-sha             620   (not scored)

  scored rows: 2231   SUSPECT: 102 (4.6% of scored)

=== SUSPECT rows (first 4 of 102) ===

  0bddf5fb4afe  2026-07-26T14:12:17Z
    3d05270 5 path(s) absent or different on trunk
    evidence: DISPOSED — no code landed (correct for this item). VERIFIED BY CONTENT BEFORE ACTING: git cherry origin/main wt-f8e40b4c577d ⇒ 61124fb already upstrea

  2844cb4b50ee  2026-07-30T06:27:46Z
    0b1e466e 3 path(s) absent or different on trunk
    evidence: 0b1e466e

  4401c48e4e82  2026-07-30T07:58:02Z
    5375088b 3 path(s) absent or different on trunk
    evidence: corrupt project label '/' — producer fixed in 5375088b (cc-backlog refuses a degenerate default; autonomy-sweep passes --project). NOT work: this is a

  1f66e5325918  2026-07-30T07:58:02Z
    5375088b 3 path(s) absent or different on trunk
    evidence: corrupt project label '/' — producer fixed in 5375088b (cc-backlog refuses a degenerate default; autonomy-sweep passes --project). NOT work: this is a
```

The script has **no dry-run flag and needs none** — it reads the store and runs `git cat-file` /
`merge-base` / `diff-tree` / `rev-parse` only; `--json` is its only write, and it was pointed at
`/tmp`.

---

## 8. WHAT I COULD NOT MEASURE

1. **Delivery outside this repo — 981 terminal closures (29%).** 686 rows cite shas that resolve in
   no object of `claude-infrastructure`, and 575 belong to `reso-management-app` alone. Absence here
   is not evidence of absence (`absent-from-trunk-has-two-opposite-causes`). Scoring them would
   require cloning each project and re-running the same oracle per repo.
2. **Non-git artifacts.** 483 rows claim a live-layer or state deliverable — a launchd job loaded, a
   daemon running post-fix bytes, `~/.claude/...` memory files outside the repo, a dead pane. Nine of
   my 15 adversarial samples cite no path at all. These are neither confirmable nor refutable by git,
   and I refuse to score them either way.
3. **Which pipeline closed 69% of the store.** 2,333 of 3,389 terminal rows carry no `lane` and 2,324
   no `venuePlan` — both fields post-date most of the history. Every per-pipeline number above rests
   on the 1,056/1,065 labelled rows.
4. **Whether a no-op closure was WRONG.** A `superseded` or `premise-refuted` closure with no artifact
   is often exactly correct — the work genuinely was already done, or the premise genuinely was false.
   This audit measures *what fraction produced an artifact*, never *what fraction should have*. The
   second question needs the item's TITLE adjudicated against the world, which is not mechanical.
5. **The 51.5% baseline.** Its source population (307 live rows) no longer exists, and neither the
   plist nor the ratchet recorded which denominator was used at the time; I reconstructed it from the
   ratchet's own prose (`304 open + 3 claimed … 157 carry a probe`), not from a stored measurement.
6. **`cc-close-attrib`** was named in the brief but not exercised — `cc-value`'s attribution leg
   already ABSTAINS on this store (`0 of 150 landed commits carry a Session-Id or Land-Session
   trailer — the join key is EXTINCT`), so no closure in this window can be attributed to a session
   or account by any shipped instrument. Per-agent closure quality is unmeasurable today.
7. **Re-mint censoring at the tail.** A row closed in the last few days has had little chance to be
   re-filed. The 30-day re-mint reading of 0 is therefore a floor, though a weak one: the whole
   96-hit population re-filed within 30 days and none since 2026-08-18.
