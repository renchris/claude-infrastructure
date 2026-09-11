# BACKLOG_ZERO — close adjudication (2026-09-07, off-box cloud fire, row `64c150ba2a8e`)

**Verdict: the plan's work is DELIVERED and LIVE; the plan's frontmatter was the stale thing.**
`docs/plans/BACKLOG_ZERO_2026-09-04.md` read `status: in-progress` with 24 of 24 sections scanning
`PENDING`, while every commit it cites is an ancestor of `origin/main` and every mechanism it
describes is present in trunk content. This document is the evidence for flipping it to `complete`,
and it records three findings a re-reader would otherwise have to re-derive.

Written from an Anthropic cloud VM, so the operator box's store
(`~/.claude/autonomy/backlog.jsonl`) was unreadable here. Everything below is computed from
`origin/main` content and git ancestry only — the one class of claim this box **cannot** make is
named in §4, rather than asserted.

## §1 What was run

```
git fetch --unshallow          # the checkout arrived at depth 50; every trunk read below
                               # would otherwise answer from inside that horizon and answer
                               # WRONG in one direction only (a landed cure reads NEVER LANDED)
git rev-list --count HEAD..origin/main        → 0        (this tree IS trunk, 902ac519f)
git rev-parse origin/main:bin/cc-dispatch     → 98ab38f5 (EQUAL to the dispatcher that fired this
                                                          brief — the composer IS trunk, so
                                                          "landed" and "live" do not diverge here)
```

## §2 Ancestry — every sha the plan cites, checked with `git merge-base --is-ancestor <sha> origin/main`

All **20** are ancestors of `origin/main`. None is a dangling citation.

| wave / section | shas | verdict |
|---|---|---|
| W1 local lane rebuild | `89a020f08` | ANCESTOR |
| W2a inflow gates | `718fa8fda` · `2f518d75b` · `d3cafafc6` | ANCESTOR ×3 |
| W2b retraction + routing | `c36876297` · `7e567755b` · `4c60e8943` · `39b409a72` | ANCESTOR ×4 |
| W3 cloud lane | `e39aa0be1` · `124c4da06` · `e467896cc` · `8ce30f3ac` · `11f50d340` | ANCESTOR ×5 |
| second-project lanes | `173a7ff34` | ANCESTOR |
| §4 status-log artifacts | `c5e2eb5a5` · `e84ba11e3` · `ffca9df45` · `24c598bac` | ANCESTOR ×4 |
| §5 filing-vs-driving | `c46af65b7` | ANCESTOR |
| §6 blocked floor | `3c2d73c4c` | ANCESTOR |

## §3 Content — the mechanisms are on trunk, not merely the commits

An ancestor commit proves a land, not a behaviour; a later commit can revert one. Each mechanism the
plan claims was grepped in `origin/main` content (`git grep <token> origin/main -- <path>`):

| plan claim | trunk evidence |
|---|---|
| §3 W1: the lane is a generated brief, not a cloned one | `scripts/drain-brief.sh` · `drain-brief.template.md` · `drain-pick.sh` · `drain-recycle-fire.sh` all present in `git ls-tree origin/main` |
| §5.3 `add` stamps the filer; `--why-not-now` is a FIELD; `done` stamps the session | `bin/cc-backlog`: `filedBy` ×5 · `why-not-now` ×8 · `closedSession` ×5 |
| §5.3 / §5.5 the certificate counts a CLOSE, not only a FILING | `scripts/wrap-ledger.sh`: `FILED_MINE` ×10 · `CLOSED_MINE` ×9 · `CLOSE_FLOOR` ×12 · `DRAIN_SCOPE` ×6 |
| §5.3 / §5.5 the hook consumes both terms | `hooks/completion-assert.sh`: `FILED_MINE` ×2 · `CLOSE_FLOOR` ×2 |
| §5.3 `cc-do <backlog-id>` runs and closes | `bin/cc-do` carries the `cc-do ran:` evidence string |
| §6.5 `add --run` exists | `bin/cc-backlog` matches `--run` ×15 |
| §6.5 the re-land row is born **OPEN**, never through `needs` | `scripts/ship-land.sh` `land_failure_inbox` (:891) builds `nargs=(add --title … --source needs --run … --why-not-now …)` at :1035, files under `CC_BACKLOG_KICK=off` at :1043, and keeps the legacy `needs` form only as the exit-2 fallback at :1048 |
| §6.5 the stored command survives a deleted branch | the same function's `cmd` is `git checkout -q ${BRANCH} \|\| git checkout -q -B ${BRANCH} ${ref}` |
| W3 cloud retire pass shipped | `scripts/cloud-retire-terminal.sh` present on trunk |

## §4 The one criterion this box cannot re-read — stated, not asserted around

The frozen scope's proof is *"`scripts/backlog-telemetry.sh` reading closed ≥ filed over its rolling
window."* That reads the operator box's store, which does not exist on a cloud VM. Two reads by
sessions that **could** see it are recorded in the plan and stand as the satisfaction:

- §5.1, 2026-09-05T03:47Z — rolling 7 d **filed 137 / closed 205 / net −68**, LIVE 518 down from the
  617 peak. Criterion met.
- §6.7, 2026-09-06T23:45Z — the local lane closing pre-existing rows: **8** closes on the 49 re-keyed
  ids (6 `lane=local-drain`), re-land rows in `blocked` **48 → 0**. Second criterion met.

**The honest caveat.** LIVE rose across 2026-09-06 (489 at 03:32Z → 506 at 23:45Z), and the plan's
own rule is that LIVE alone cannot show this change (±70/day). So the metric *was* met when last
read and is not re-read here. A metric holding is a continuing measurement, not a task: a plan kept
open until a number stays good forever is precisely the *"parking state with a cheap entrance and no
scheduled exit"* that §6.2 named as the generator. The desk's one-line re-read:

```
bash scripts/backlog-telemetry.sh          # rolling window: closed ≥ filed?
```

If it has reversed, that is a new plan under a new mandate, not an unfinished section of this one.

## §5 Three findings

### §5.1 `git cherry` is the instrument two of this plan's headline numbers rest on — and the repo's own oracle documents it as wrong in both directions

`scripts/land-content-verify.sh` exists because patch-id was measured unfit. Its header, verbatim:

> `git cherry` (patch-id) — wrong in BOTH directions: it cleared 3 refs that still held residue, and
> convicted `0a131da73` whose every path was blob-identical to trunk. Context drift moves a
> patch-id; it does not move content.

Two of this plan's numbers were measured with exactly that instrument:

- §5.5 — *"Measured over the 49 not-done rows by patch-id (`git cherry origin/main <ref>`): 2 fully
  on trunk … 45 carry genuinely unlanded commits."*
- §6.2 — *"47 with commits genuinely absent from trunk (`git cherry origin/main <ref>` prints `+`)."*

**Why the §6 re-key was nonetheless safe, and this is the load-bearing half.** The re-key moved 49
rows `blocked → open`. `open` is the *preserving* direction: a row wrongly called unlanded becomes
agent-workable and the next drain link adjudicates it by content — which is what happened
(§6.7: 6 of them closed MOOT by `lane=local-drain` links within 100 minutes, each reasoned *"main is
a strict SUPERSET of the ref"*, i.e. re-adjudicated on the **content** oracle, not on patch-id). Had
the same instrument been used to **close** those rows, its documented false-clear rate would have
stranded real work silently. The direction, not the instrument, is what made §6 correct.

**Consequence for a re-reader:** treat §5.5's `45 genuinely unlanded` and §6.2's `47` as
patch-id-derived upper bounds on real strandedness, not as content verdicts. The content verdict for
any one of them is `bash scripts/land-content-verify.sh <ref> --no-fetch`.

### §5.2 §5.5's one forward-pointing remedy is refuted by the oracle it would replace

§5.5 closes with: *"Dropped, not filed: re-keying that falsifier on the branch's patch-ids — three
rows in 167 is not worth a rail change this session; the plan now says where it lives."*

That pointer names patch-id re-keying as the remedy for the amend case (`f0c419a56091` stayed blocked
over a two-line quoting delta while all four of its commits sat on trunk). But the falsifier it would
re-key **is** `land-content-verify.sh`, and that script was built by discarding patch-id for this
exact job, on measurement (§5.1 above). Re-keying it onto `git cherry` would trade a bounded
false-*strand* for a documented false-*clear*, and a false clear on this population is the failure
mode the whole oracle exists to prevent (*"actioning four of them would have REVERTED trunk"*).

**Disposition: the pointer is retracted, not deferred.** The amend case is a known, bounded limit of
a content-superset oracle — a ref whose file holds pre-amend lines trunk never carried is, by the
oracle's own stated rule, content trunk lacks. Its measured population is **3 rows in 167 (1.8%)**,
below the ±70/day noise the plan measures elsewhere. Neither of the oracle's two rescue arms reaches
it: SUPERSEDED requires trunk to have once carried the ref's whole-file blob (it never did), and
RELOCATED requires trunk to be a multiset superset of the ref's lines (the discarded quoting is not
present anywhere). A future session should treat this as a design limit with a named cost, not as an
open task with a known fix.

### §5.3 `CLOUD_BACKLOG_PIPELINE.md` §A9.5 cites a sha that resolves nowhere

The cloud half of *"the two 24/7 drains"* is owned by `docs/plans/CLOUD_BACKLOG_PIPELINE.md`, which
reads `status: complete` and whose §A9.5 records the live convergence at 2026-09-07T05:30–06:20Z —
about an hour before this fire. Its two cited shas:

- `a7390066b` — **ANCESTOR** of `origin/main` (`feat(autonomy-sweep): the sweep leaves the darwinbg task role`).
- `ee6740491` — **does not exist in this repository at all** (`git cat-file -t` → `Not a valid object name`).

The content landed: `42b802d3` on trunk carries the identical subject
(`fix(migrations/0016): verify the LOADED job, not the copied file — install.sh had already made the
file match`, authored 2026-09-07T00:45Z), so `ee6740491` was the pre-rebase sha and the citation was
written from a tree that no longer exists. The verdict of that plan is unaffected; only its evidence
chain was unreadable. Corrected in place to `42b802d3` in this session's commit.

This is the failure the close protocol's S5 rule already names — *a sha on no branch resolves in your
checkout and nowhere else* — caught here only because an off-box reader had no local tree to resolve
it from.

## §6 Adjudication

| plan half | state | evidence |
|---|---|---|
| local 24/7 drain | **delivered, live** | W1 `89a020f08` → W5 self-perpetuating chain (§4 17:20Z) → §5 close floor `c46af65b7` → §6 blocked-floor producer `3c2d73c4c`, byte-proven live 2026-09-06T23:33Z |
| cloud 24/7 drain | **delivered; ongoing ownership delegated** | W3's five commits are ancestors of trunk; `CLOUD_BACKLOG_PIPELINE.md` reads `complete`, §A9.5 records the deployed retire pass settling 299 of 331 declarations |
| the rolling-window criterion | **met when last read; not re-readable off-box** | §4 above |

Nothing in the plan's 24 sections names remaining work. Sections 1–8 are measurement, §4 is an
INTEGRATE-only status log, and §5/§6 are landed-and-proven change records. They scan `PENDING` only
because `plan-phase-scan.sh` reads `DONE` or a commit hash **in the heading**, which narrative
headings do not carry.

**Action taken:** `status: in-progress` → `complete` in the plan's frontmatter, plus a §7 recording
this adjudication. That flip is the mechanism-level close, not a cosmetic one: `find-plan.sh`
`list_open` skips `complete|superseded` (:108), so the plan stops being minted into new `plan-open`
backlog rows, and clause (a) of the stored falsifier
(`plan-phase-scan.sh --falsify` → `find-plan.sh --status` → `complete` ⇒ `FALSIFIED`, exit 0)
retracts row `64c150ba2a8e` itself on its next premise re-run.
