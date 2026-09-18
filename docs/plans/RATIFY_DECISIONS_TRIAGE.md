---
status: open
---

# RATIFY DECISIONS — triage, evidence, and the open remainder

**Status:** open · **Opened:** 2026-08-23 · **Owner:** rolling (recycled session)

---

## Phase 0 — Agent Team Orchestration

**EXECUTION LOCUS PER WAVE**

| Wave | Locus | Why |
|---|---|---|
| W1 · verify the named fact behind each of the 6 open decisions | **S** — one dispatched session per repo cluster | default for implementation/verification waves; keeps the lead's window for judgment |
| W2 · mergeability triage of the 5 escalation-parked branches | **S** — dispatched, one worktree per branch | each branch needs a real rebase attempt; conflicts must not land in the lead's context |
| W3 · synthesise verdicts → action/leave each packet | **L** — lead-inline | *(justification)* the output is one `cc-decide action` per packet with an evidence string; it is small, and it must be judged against all waves at once |

**Read-only research fan-out** (subagents, no `team_name`) is unrestricted — findings only, never
code. ⚠️ The capacity gate (`capacity-admit`) refused three fan-outs on 2026-08-23 at the
active-turn ceiling of 8; its own instruction is *"run this work SERIALLY on the lead"* while the
operator is at the keyboard. **Do not override with `CC_ADMIT_GATE=off`.**

**Team roster / worktrees**

| Track | Worktree | Owns |
|---|---|---|
| `ratify-reso` | `wt-ratify-reso` | `ef79469fbb12`, `9d97a3c272a2`, `7d4a230457c5` (reso-management-app) |
| `ratify-ext` | `wt-ratify-ext` | `739906feadbe` (doc_classifier), `2820133fc77c` sequencing |
| `ratify-branches` | one per branch | W2 mergeability |

**Dependency graph:** W1 ∥ W2 (independent) → W3 (blockedBy: W1, W2).
`739906feadbe` is blockedBy `2820133fc77c` (same Azure account surface).

**Lead context budget + succession point:** lead holds ≥50% of its window for judgment; recycle at
the natural seam after W3's synthesis, or at ~75% fill, whichever comes first.

🚨 **Two packets are NOT delegable:** `ef79469fbb12` (auth surface — operator's ruling) and any
`--force`/destructive land. Surface, never self-action.

The durable record of the operator-ratification decision set (`cc-decide`), the evidence that
closed six of them, and the analysis behind the six still open. **The decision packets themselves
are the SSOT; this doc holds the RESEARCH that is not in any packet** and would otherwise die with
the session that did it.

---

## Scope (frozen)

> Drive every open operator-ratification decision to a resolved state — each either ACTIONED with
> disk-verified evidence, or left open with a written recommendation, a conviction level, and the
> one named fact that would move it. Use Dynamic Workflows / subagents / Agent Teams for the
> research fan-out wherever the capacity gate admits them.

---

## The counting correction (read this before quoting any number)

`cc-decide list --open | grep -c .` is a **line count**, and packets wrap — it read 22 when the
true figure was 17. Count by the `status` field instead:

```bash
python3 -c "
import json,glob,os;from collections import Counter
r=[json.load(open(f)) for f in glob.glob(os.path.expanduser('~/.claude/autonomy/decisions/*.json'))]
print(Counter(x.get('status') for x in r)); print(Counter(x.get('class') for x in r if x.get('status')=='open'))"
```

**2026-08-23 truth: 17 open — 16 class-C + 1 class-B.** Five class-B `ship-land` packets had
already auto-fired their defaults and were never awaiting the operator.

---

## CLOSED this session (6) — actioned with evidence

| id | why it was dead |
|---|---|
| `e05e343e1821` | staged scripts 01–04 all carry `.done`; `com.claude.dispatcher` + `com.claude.discovery` both LOADED |
| `feb9a28b5dec` | `git merge-base --is-ancestor 2ebab2b HEAD` = true — the fix was already in the checkout |
| `2dfbab6ee5c5` | class A — already ruled and acted (audit trail only) |
| `a412859337a9` | class A — already ruled and acted |
| `33e4a598de8c` | **REFUTED.** Packet claimed desk was ARMED-but-SHADOW. `arm-<key>` **and** `live-<key>` both present and matched in `~/.claude`, `~/.claude-tertiary`, `~/.claude-quaternary` since 2026-07-26. Keys recomputed via `sha(cfg\|cwd)[:16]`; LIVE is a *separate* sentinel (`waiting-recycle.sh:441`), not a flag in the arm marker |
| `55a0079d1769` | **PREMISE DEAD.** `src/app/(app)/bottle-menu/page.tsx` is on `origin/main`; its docstring reads *"the venue's catalog, readable without a reservation."* Rebuilt 2026-08-16 as a read-only MODE on the shared catalog UI — a fourth path, none of options a/b/c, clear of the clean-room charter |

Also resolved without action: **`c9dd784a29eb`** left the open set (class-B default fired = "Loud").
The evidence supports it — `lib/floor-plan/venueSvgData.ts:217` already reports a corrupt geometry
blob at `severity: 'error'`, reasoning *"missing walls on a floor door staff work through"* is not a
warning. "Loud" matches the file's own precedent.

---

## OPEN — the six below 90% conviction

Each carries the ONE fact that would move it. **Do not re-derive; verify the named fact.**

### 1. `ef79469fbb12` — platform-privileged admin row per tenant · rec: move it off the platform domain · ~93%
Verified `lib/auth/platform-email.ts:11`: the predicate is `normalized.endsWith(domainPattern)`.
*(Line corrected 2026-08-23 second pass, re-read from `git show origin/main:lib/auth/platform-email.ts`:
**`:11` is the `export const isPlatformEmail` declaration; the predicate itself is `:17`** —
`if (domainPattern && normalized.endsWith(domainPattern.toLowerCase())) return true`. Cite `:17` when
this is actioned. The substantive claim is unchanged and now double-read: with
`PLATFORM_EMAIL_DOMAIN=@reso.gl`, `endsWith` accepts **any** local part, so the plus-stripping in
`normalizeEmail:6-9` is irrelevant to the gate — it is not the mechanism, and narrowing it would not
close the hole. A third sharp edge falls out of the same line: `endsWith` is a **substring** test with
no `@` anchor, so were `PLATFORM_EMAIL_DOMAIN` ever set without its leading `@`, a lookalike domain
ending in the same characters would also pass. Option 3 ("narrow isPlatformEmail") is therefore both
wider-blast-radius **and** aimed at the wrong clause.)*
**This is broader than the packet states** — plus-stripping is not even required; *any*
`<anything>@reso.gl` passes the platform gate. Latent (no WebAuthn credential; `invite:admin`
refuses an existing address) but a predictable full-CRUD platform identity in every new tenant.
Moving the row = one file; narrowing `isPlatformEmail` changes a shared auth predicate.
**Auth surface ⇒ operator's call. Do not self-action.**

### 2. `922699aacda0` (class B) — 49 commits written off · rec: revive the 8 that still merge · ~85%
41 cloud-session declarations marked terminal in a **21-second burst** on 2026-08-18; 36 carry no
success marker and the store records only a timestamp. **Default "leave them written off" fires
2026-08-30** — silence loses the work.

### 3. `739906feadbe` — Tier-A $0 Azure validation · rec: sequence behind `2820133fc77c` · ~85%
Located at `doc_classifier/runbooks/live-validation-zero-dollar.md`. Its "ONE irreducible step" is
creating a $0 Azure account — the same Azure surface the fraud gate blocked. Aside: `dc-wiring`
holds a byte-identical copy of that runbook (two repos, one SSOT).

### 4. `9d97a3c272a2` — focus-ring authority · rec: `docs/design-system/CONSTRAINTS.md` is authority · ~85%
Verified 2 of 3 sites (`CONSTRAINTS.md` = `outline: 2px solid #56b4e9`; `focus-ring.ts` =
`insetRing: '1px'`). **The packet's stated reason is stale** — `use-focus-ring-token.mjs` now runs
three checks (raw hex, hand-rolled token-spelled, suppressed), not hex-only.

### 5. `7d4a230457c5` — console mints its own invite · rec: leave it · ~85%
`"invite:admin"` confirmed at package.json:100, so the two-step gap is real. Unverified: the
"writes no bearer credential to its run directory" claim.

### 6. `shipland-esc-c661813` — `feat/autonomy-100` · classifier >95%, land ~60%
See § Escalation classifier below. The false positive is proven; **mergeability is the open axis.**

---

## Infra findings (not decisions — defects, with evidence)

### The escalation classifier is wrong, and a parked branch documents it
`ESC_RE_EFFECT_DEFAULT` (`scripts/ship-land.sh:478`) applied to each branch diff:

| branch | commits | what matched | verdict |
|---|---|---|---|
| `feat/autonomy-100` | 14 | **its own regex definition** + **bats fixtures** | FALSE POSITIVE |
| `docs/frontier-problems-2026-07-23` | 2 | prose *describing* this bug | FALSE POSITIVE |
| `wt-6cab0ab3cb2f` | 8 | **zero hits**, effect *and* secret class | FALSE POSITIVE |
| `fix/infra-perfection` | 55 | `DELETE FROM session_chunks` — a **local SQLite index** | benign |
| `tm/growth` | 49 | same local-cache deletes | benign |

`ESC_RE_SECRET_DEFAULT` is only the PEM private-key banner — the literal is deliberately NOT quoted
here, because writing it out makes this very document trip the scanner it is documenting, which is
precisely the false-positive class this table catalogues. `SHIP_LAND_ESC_RE` is an overridable env
var (line 169), and **the narrowing fix is already written inside `fix/infra-perfection`** — the
remedy is parked behind the bug it fixes.

🚨 **But "land them" is NOT mechanical.** `wt-6cab0ab3cb2f` conflicts against a moved trunk
(`scripts/reaper-horizon-lint.sh`, `tests/scratchpad-reaper.bats`). Aborted and restored clean.
**Classifier verdict ≠ landability. Test mergeability before promising a land.**

### `ship-land` exits 0 on refusals (extends task #179)
Observed twice this session: refusing the shared checkout, and leaving a conflicted rebase
mid-flight. Both exit 0. **Never trust its exit code — verify by content.**

### Live layer converged (was frozen 15 commits)
Root cause: the shared checkout sat 2 commits AHEAD of `last-green`, and `deploy-live.sh` rule T1
advances only to a green **descendant** of live HEAD. Green was an *ancestor* ⇒ refuse ⇒ silent
`exit 0` (line 47). Resolved 2026-08-23: checkout at `d8fc911b5` == `origin/main`;
`deploy-live.sh`, `ship-land.sh`, `waiting-recycle.sh` byte-identical to trunk.
Backup ref `backup/shared-main-pre-rebase-20260823` retained.

### Machine lag (separate investigation, same session)
Not a memory problem — 21.4 GB reclaimable headroom, compressor segments 12.8% of a 45% warn floor,
`compressor-sentinel` 0 breaches in 2000 ticks. It is **kernel churn**: ~5 processes created and
destroyed per second against 1217 resident, from our own pollers (31 `cc-await-ping` holding 22
Python children, `lead-supervisor`, `assignee-pane-residency`, `lead-crash-watchdog`). Load bursts
trace to concurrent `ship-land` gates each spawning `tsc --noEmit` at ~1.9 cores.

---

## Instrument traps hit this session (all cost a wrong answer first)

1. **`git diff A..B` (two dots)** folds in commits you are MISSING as fake deletions — read 2,348
   deletions that were really 175 insertions. Use `A...B` or `git show` per commit.
2. **Scanning a worktree instead of `origin/main`** — `wt-pool-3` is on branch `cc-154540-9309`;
   its `layout_data` hits reversed the true verdict.
3. **`launchctl list | grep rotate`** — the job is labelled `com.claude.log-rotation`; a name-based
   grep read "not scheduled" for a live job.
4. **`cc-decide list | grep -c .`** — line count, not packet count (see § counting correction).
5. **`ITERM_SESSION_ID`** — pane 589 is the LEAD, not a subagent; `cc-sessions` rows in the same
   repo/age band are not automatically your own children.
6. **A branch census over local refs alone cannot say "gone."** `git rev-parse origin/<b>` failing
   proves only that *this checkout's* remote-tracking cache lacks it — and this session's `git fetch`
   never completed (tool timeout), so the cache was of unknown age. The claim needs `git ls-remote`,
   which asks the remote. It happened to confirm all 12; the point is that it *could* have refuted
   them, and nothing in the local read would have said so.
8. 🚨 **The reso checkout is on branch `main` but its HEAD is ~1328 commits BEHIND `origin/main`.**
   Being "on main" says nothing about being *at* main. The working-tree copies of
   `eslint-rules/use-focus-ring-token.mjs` and `eslint.config.mjs` are **older blobs** than trunk's,
   while `recipes/settings-ghost.recipe.ts` and `src/lib/focus-ring.ts` happen to be identical — so
   a spot-check of the *subject* files agrees with trunk and lulls you, while an in-tree
   `npx eslint` silently measures the **stale hex-only rule** and reproduces exactly the packet's
   out-of-date claim. Every read in this pass used `git show origin/main:<path>`, and the lint was
   measured by extracting the trunk blobs to a temp dir first. **`git rev-parse` both sides per file
   before trusting any working-tree read**, and run linters from an extracted blob, not the tree.
9. **A shell `for` loop over 88 files timed out twice at 120 s on this box.** Not a git problem —
   the machine-lag finding below (~5 process creations/sec against 1217 resident) makes per-item
   `stat`/`git` **forks** the dominant cost. Rewriting the same sweep as ONE `python3` process ran it
   in seconds. On a fork-starved box, prefer one interpreter over a loop of subshells.

---

## W1/W2 verdicts — named facts VERIFIED (2026-08-23, second pass)

**Locus deviation from Phase 0, recorded rather than hidden:** W1 was planned as **S** (dispatched
sessions per repo cluster). It ran as **read-only research subagents** instead. Reason: once the
named facts were written down, W1 reduced to three cross-repo *greps* — the plan's own § Phase 0
declares read-only subagent fan-out "unrestricted", and a dispatched session per grep buys custody
debt and pane latency for no isolation gain. W2 was planned as **S, one worktree per branch**; it
ran **lead-inline** on `git merge-tree --write-tree`, which answers mergeability **without a
worktree, without an index, and without touching a ref** — strictly safer than the planned rebase
attempts, and it moots HARD CONSTRAINT 3 entirely. W3 unchanged (**L**).

### W2 — mergeability of the 5 escalation-parked branches

Method: `git merge-tree --write-tree --name-only origin/main <branch>`, non-destructive, run at
`origin/main = d8fc911b5`. Conflicted-file count = lines before the first blank in its output.

| branch | commits ahead | behind | conflicted files | landable as-is |
|---|---|---|---|---|
| `feat/autonomy-100` | 14 | 3103 | **13** | **no** |
| `docs/frontier-problems-2026-07-23` | 2 | 3006 | **1** (`docs/research/FRONTIER_HOLES.md`) | **no — but trivially resolvable** |
| `wt-6cab0ab3cb2f` | 8 | 2900 | **8** | **no** |
| `fix/infra-perfection` | 55 | 2921 | **55** | **no** |
| `tm/growth` | 49 | 2750 | **53** | **no** |

🚨 **Zero of the five merge cleanly.** The § Escalation classifier finding stands unchanged — the
false positives are real — but it is now measured, not assumed, that **no classifier fix makes any
of these branches landable**. `feat/autonomy-100`'s conflicts land squarely on the files trunk has
rewritten most (`scripts/ship-land.sh`, `bin/cc-decide`, `scripts/autonomy-sweep.sh`,
`scripts/wrap-ledger.sh` + their bats suites) — i.e. the branch's own subject matter is what moved.

The one cheap exception is `docs/frontier-problems-2026-07-23`: 2 commits, one conflicted file, and
that file is an **append-only ledger** (`FRONTIER_HOLES.md`). That is a union-merge, not a
resolution.

### 6. `shipland-esc-c661813` — RESOLVED to a recommendation · conviction ~95%

Named fact (mergeability) **verified: 13 conflicted files.** The packet asks a human to "review and
land"; the honest answer is that **there is nothing mechanically landable to review.** Recommended
disposition: **do not land `feat/autonomy-100`.** Harvest by cherry-pick per commit against today's
trunk, or re-implement — and fix the classifier from trunk rather than from inside
`fix/infra-perfection` (§ Escalation classifier notes the remedy is parked behind the bug; W2 now
shows that parking is 55-conflicted-files deep, so **write the narrowing fix fresh on trunk**).
Still class C / operator-surfaced: the *decision* is the operator's, but the option "just land it"
is now known-false.

### 2. `922699aacda0` — recommendation REFUTED by its own named fact · conviction ~95%

Named fact: *how many of the branches under the 2026-08-18 terminal markers still merge cleanly.*
Measured across all 41 burst markers (`~/.claude/autonomy/cloud/*.retired`, mtime bucket
`2026-08-18T03`, one `merge-tree` per branch against `origin/main`):

| class | branches | commits (ancestry) | commits **patch-stranded** |
|---|---|---|---|
| **merges cleanly** | **2** | 3 | **3** |
| conflicts against trunk | 27 | 38 | **27** (on 24 branches; 3 branches are fully patch-landed) |
| **branch no longer exists** (absent from `origin/*` and from the remote) | **12** | 0 | **0 — unrecoverable** |
| total | 41 | 41 | **30** |

🚨 **Count commits by PATCH, not by ancestry — the two disagree by 21%.** The first pass used
`git rev-list origin/main..<branch>` and got 41. `git cherry origin/main <branch>` — which compares
patch-ids — shows **8 of those commits are already on trunk under a different sha** (rebased or
cherry-picked in), leaving **30 genuinely stranded**. Three conflicting branches turn out to hold
*nothing* new at all. An ancestry count of a long-lived branch measures how far trunk has moved, not
how much work is unlanded. Task **#174** already had this right — it counts by `git cherry` — so its
"46 stranded across 41 branches" is a **different, larger population** (all remote cloud branches,
not just the burst-marked ones) and is **not** contradicted by anything here.

Three corrections to the packet, each disk-verified:

1. **"revive only the 8 that still merge cleanly" names a set of 8 that does not exist — there are
   2.** And those 2 are **throwaway**: `claude/fire-20260811T180903Z-57078-1` (2 commits) and
   `…-57078-2` (1 commit) are the two arms of a **cost A/B probe** (`item=cc-offload ab-brief.txt`),
   each adding the same three files — `tools/cost-ab-probe/{wordfreq.py,test_wordfreq.py,__init__.py}`,
   a toy top-N word-frequency CLI written twice. Landing them would land the probe's litter, not
   finished work. **The cleanly-mergeable half of this decision is worth nothing.**
2. **"49 commits" is really 30.** 12 of the 41 declarations point at branches that no longer exist
   on the remote, so nothing they held is recoverable by clearing a marker; and of the commits that
   *do* remain, 8 are already on trunk by patch-id. 30 commits across 27 live branches is the true
   exposure of this decision.
3. **The packet's open question — "a deliberate mass write-off would look exactly like this" — is
   answered NO.** 26 of the 41 carry a `.land-refused` **and** a `.refusal-route` record written
   *hours to days before* the burst (measured deltas 8,788 s – 68,697 s). The lane attempted these
   lands, was refused (`rc=70` gate-red, `rc=65` reconcile-failure), logged the route, and only then
   swept them terminal. Two refusal bodies name the cause verbatim: `"why":"the rebase onto the
   trunk conflicted — resolving it needs the trunk the VM…"`. A further 8 refusals are environmental
   (`shell-init: error retrieving current directory` — a deleted worktree cwd), not content verdicts.
   The 21-second burst is a **sweep of already-stuck declarations**, not a blind write-off of healthy
   work.

**Revised recommendation: let the default fire — "leave them written off" — and do NOT action the
packet early.** It is class B with `default_effect=no-change` and `veto_deadline=2026-08-30`; the
default is now the *measured* right answer, and leaving it open preserves the operator's veto window
for free. The **27 patch-stranded commits on 24 conflicting branches** are **not** written off by
this: they are already owned by task **#174** ("Recover the 46 stranded cloud commits"), which is a
separate per-branch cherry-pick lane, not a marker-clearing decision. Clearing a terminal marker
would only re-enter them into a lane that already refused them 26 times for gate-red and conflict —
which is why "revive all 34" is the worst of the three options, not the most generous.

**The "12 branches gone" claim was re-checked against the remote, not the local cache.** The
mergeability sweep ran without a successful `git fetch` (it exceeded the tool timeout), so a stale
remote-tracking ref would have turned a live branch into a false "unrecoverable". `git ls-remote
--heads origin 'claude/fire-*'` returns **70 heads**, and **none of the 12 is among them** — the
absence is real. *(Instrument trap 6, below.)*

Raw data: `/tmp/ratify-cloud-merge.json`, `/tmp/ratify-burst-ids.txt`, `/tmp/ratify-lsremote.txt`
(regenerable; all ephemeral).

### 4. `9d97a3c272a2` — all three sites re-read; the packet's *reason* is wrong twice over · ~95%

Every citation in the packet is **exact** on `origin/main` — re-read via `git show origin/main:<path>`,
not from a worktree:

| site | path:line | literal |
|---|---|---|
| (a) | `docs/design-system/CONSTRAINTS.md:38` | `` `outline: 2px solid #56b4e9; outline-offset: 2px` `` |
| (b) | `src/lib/focus-ring.ts:29` | `_focusVisible: { insetRing: '1px' }` |
| (c) | `recipes/settings-ghost.recipe.ts:44-48` | `_focusVisible: { outline: '2px solid', outlineColor: 'uish.brand.gold', outlineOffset: '-1px' }` |

Site (c) is **live and admin-facing**, not dead code — imported by
`src/app/(app)/admin/(settings)/components/{InvitationsList,MembersList,PlatformContent}.tsx`.

**Named fact — does the current lint flag site (c)? Measured: NO, for two reasons, and the packet
names neither.** The packet says "un-flagged because the lint only inspects hex outlines." That
wording is stale — `eslint-rules/use-focus-ring-token.mjs:11-18` now documents three arms (A raw hex,
always on; B hand-rolled focus outline, strict; C suppressed ring, strict). But the conclusion
survives, via two *different* mechanisms:

1. **Scope.** `eslint.config.mjs:442` labels the widened arms *"WARN-FIRST, **FLOOR-PLAN PATH
   ONLY**"* and `:466` enables them as `['warn', { strict: true }]`. `recipes/` is not the floor-plan
   path, so arms B and C **never execute** on site (c) — and `:187` gates the whole focus-object
   visitor behind `if (strict && …)`.
2. **Predicate — and this one is a real defect in the lint.** Even with strict on, arm B bails at
   `:172` on `if (!COLOR_REF.test(value)) continue`, where
   `COLOR_REF = /token\(|var\(--|#[0-9a-f]{3,8}\b/i` (`:74`). Site (c)'s colour is the **bare Panda
   token path** `'uish.brand.gold'`, which matches none of the three alternatives — and
   `outline: '2px solid'` carries no colour at all. Yet the lint's own docstring at `:14-15` claims
   arm B covers *"a bare Panda token path."* **The docstring over-claims what the regex
   implements.** A reader auditing coverage from the header would conclude site (c) is covered.

🚨 **RECOMMENDATION REVERSED (2026-08-23 cross-check) — `CONSTRAINTS.md` is NOT the authority, and
the plan's earlier "~95% CONSTRAINTS.md is authority" was wrong.** Five citations, each re-verified
by hand against `origin/main`:

1. **It is a generated mirror, not a source.** `docs/design-system/CONSTRAINTS.md:1-2` —
   `<!-- GENERATED from docs/design-system/constraints.json by scripts/design/gen-constraints.ts.
   DO NOT EDIT BY HAND. -->`. Naming a generated artifact as the authority puts the SSOT downstream
   of itself.
2. **Its own source sanctions THREE rings, so it cannot resolve a three-way conflict.**
   `docs/design-system/constraints.json:99-101` carries `sky: #56b4e9`, **`gold: #d4af37`**, and
   `amber: #ffb000`. The gold ring the packet treats as the violation is *listed in the file the
   proposed authority is generated from.*
3. **It prescribes the ring the lint exists to prevent.** `CONSTRAINTS.md:38` is the 2px **outset**
   `outline`, which `use-focus-ring-token.mjs:5-7` calls *"the old outset ring."*
4. **A doc DOES claim authority — and it points at site (b), not (a).** `docs/design/README.md:114`
   is a heading reading *"One focus treatment. There is no second one"*, whose body is
   `focusRingSkyStyles` (`outline:'none'` + `_focusVisible:{insetRing:'1px'}`). Corroborated by
   `docs/OWNERS.tsv:71` — `src/lib/focus-ring.ts   design   the one focus treatment`.
5. **The recipe gap is already a KNOWN, documented hole.** `docs/design/chapter-enforcement.md:44-48`
   — *"The lint cannot see recipe-level focus … Recipe migrations therefore carry a
   `/* focus: sky ✓ */` provenance comment — a convention, not a check."* And
   `git grep "focus: sky" origin/main -- recipes` returns **zero** hits across all 13 recipes, so
   even the convention is unobserved.

**Revised recommendation (~93%): the authority is `src/lib/focus-ring.ts` + `recipes/_focus.ts`
(site b).** Site (c) is then not an unresolved third opinion but **tolerated residue** — one of four
known gold rings, per `src/reso-panda-preset.ts:286-288` (*"the 4 live gold rings reach gold via
`uish.brand.gold` / `mcGold` / inline, never via this token"*). The packet's premise *"no doc
resolves them"* is therefore also slightly wrong: a doc does resolve it, it is simply **unenforced
for recipes**. And `CONSTRAINTS.md:38` should be corrected at its **source** (`constraints.json`),
not cited as the ruling.

*(Superseded text kept per INTEGRATE-never-overwrite:)* ~~Recommendation (unchanged, now at ~95%):
**`CONSTRAINTS.md` is the authority.**~~ Two follow-ons fall
out, and both are the operator's, not mine: repo-wide promotion of the strict arms is *already* a
filed operator call (`use-focus-ring-token.mjs:28` cites "plan §17.5 call ②"), and the `COLOR_REF`
gap means that promotion **would still not catch site (c)** — the regex has to gain a bare-token-path
alternative first, or the promotion lands as a false green.

### 5. `7d4a230457c5` — the unverified claim is CONFIRMED, and by construction · ~93%

Named fact: *"the console deliberately writes no bearer credential to its run directory."*
**Confirmed, and more strongly than the packet claims it.** `lib/provisioning/provision-venue.events.pure.ts:165-167`
states it as a type-level invariant: *"No member has a `value`, `token`, `secret`, `url` or `command`
field … so the stream is given no field able to carry it."* The event stream cannot carry a
credential — this is not a convention that a future edit forgets, it is an absent field.

Corroborating: the only disk write on the provisioning path is
`scripts/setup/provision-venue.ts:552` — `fs.appendFileSync(filePath, serializeJournalLine(event))`,
i.e. the run journal, fed by exactly that credential-incapable event type. And
`PlatformContent.tsx` (the console surface) matches **zero** occurrences of
`inviteUrl|invite_url|inviteLink|magicLink|bearer|token` — nothing credential-shaped is returned to
the page either.

⇒ Recommendation **"Leave it" stands**, and its stated rationale is now load-bearing rather than
aspirational: the two-step gap is not an oversight to close, it is the mechanism that keeps a bearer
credential off both the response and the disk. Still class C / auth surface — **surface, do not
self-action.**

#### …but the packet's PREMISE is false in two places (2026-08-23, cross-check pass)

A second independent read went deeper than the named fact and found the decision is **framed
wrongly**. All four load-bearing citations below were then re-verified by hand against `origin/main`:

1. **"the console … writes no bearer credential" is enforced by an UNCONDITIONAL flag, not by
   restraint.** `lib/provisioning/provision-run-store.ts:272` puts `'--no-admin-invite'` in the
   literal `args` array of `buildProvisionArgs` — outside every `if`, unlike `--execute`/`--force`/
   `--skip-*` below it. The saga then short-circuits (`scripts/setup/provision-venue.ts:1524-1528`,
   `kind === 'suppressed'` ⇒ `return { invite: null }`), so the one print site at `:2687`
   (`if (invite !== null && !opts.dryRun)`) is unreachable. Three layers, not one.
2. 🚨 **"every tenant provisioned from the UI arrives with no way to log into it until someone runs
   `pnpm invite:admin`" is FALSE.** The console already mints and emails the invite:
   `src/app/actions/auth/provisionActions.ts:311` `sendFirstAdminInvite`, wired to a live button at
   `ProvisioningConsole.tsx:437` — *"Email the first-admin invite."* The raw token is minted at
   `:330` and returned in **no** field (`{ delivered, email }`), and the recipient is not a
   parameter — `:328` pins it to `process.env.PERSONAL_PLATFORM_EMAIL`. **So the real decision is
   much narrower than the packet asks:** not *may the console mint an invite* (it does), but *may it
   mint one for an **arbitrary** recipient* — which is the actual cross-tenant escalation surface.
3. **"all four Turso group tokens sit on every Fly app" is wrong twice.** `lib/config/tenants.ts:234`
   enumerates **five** groups (`oregon | los-angeles | singapore | ashburn | dallas`), and the repo's
   own text says the invariant does not hold live: `bootstrap-region.pure.ts:2131-2132` calls the
   absence on `reso-sin` *"a defect rather than noise"*, and
   `docs/runbooks/S11_NOTIF_SWEEP_OREGON_COVERAGE.md:19` states **"`reso-sin` can't reach non-SIN
   tenants."** The "technically reachable" premise that makes this an escalation is therefore
   **weaker than the packet claims** — which argues *for* "Leave it", not against it.
4. **The console's own UI prose contradicts its own button, in the same file.**
   `ProvisioningConsole.tsx:337-338` still reads *"The first admin's invite is not issued here — that
   stays a deliberate CLI step, because the link it mints is a one-time credential"* — 100 lines
   above the button that issues it. Whoever ratifies this packet is reading that sentence.

**Net:** the recommendation does not change, but the packet should be **re-stated before it is
ruled on** — it currently asks the operator to authorise something already shipped, and justifies
the risk with a token-distribution claim the repo contradicts. Item 4 is an ordinary docs fix and is
filed below, not an operator decision.

### 3. `739906feadbe` — sequencing JUSTIFIED, but for a different reason than stated · ~90%

Named fact: *is the runbook's irreducible step the same Azure surface as the gpt-5-mini fraud gate?*

- `doc_classifier/runbooks/live-validation-zero-dollar.md:17` — **"## 1 · Create the $0 account (your
  ONE irreducible step)"**, with `:3` framing the whole runbook as *"the moment you have a
  guaranteed-$0 commercial Azure account."* So the blocker is **creating a NEW commercial Azure
  account/subscription** — not the existing `dcl20s-aoai` account that `2820133fc77c` targets.
- But they are **not** independent: `:91` requires `az cognitiveservices account show` to confirm a
  live `Cognitive Services User` role, so the runbook's success path runs through the *same*
  Cognitive-Services surface Azure's fraud gate (case 715-123420) refused.
- `scripts/aoai-retry-standing.sh` exists on `main`, and `c7b7f16b` is real —
  *"fix(provision): bash-3.2-safe register reader; location on account create"* — consistent with the
  packet's "shell parsing bug before reaching Azure."
- The dc-wiring duplication is **confirmed byte-identical**: both copies of
  `runbooks/live-validation-zero-dollar.md` hash `3c6e4491f8ad0816443cbcf093a497038bbe64ed`.

**Refinement to the recommendation.** "Sequence 739906feadbe behind 2820133fc77c" is right, but the
reason is *cost asymmetry, not blocking*: `2820133fc77c` is a **one-command probe against an account
that already exists** and its result is informative either way, whereas `739906feadbe` asks the
operator to stand up a **new commercial account** — a heavier, less reversible step that a fresh
fraud-gate refusal would waste. Run the cheap probe first. Note also that a new account is
arguably a *route around* the gate rather than a dependent of it; if the probe re-trips 715-123420,
that is evidence about tenancy standing which makes the new-account path **more** attractive, not
less. Both remain operator-hand-reserved (money path + policy relax) ⇒ **surface, do not
self-action.**

---

## ✅ ACTIONED — `2820133fc77c` · the Azure fraud gate has LIFTED (2026-08-23)

The operator ran `scripts/aoai-retry-standing.sh`. **Case (715-123420) no longer fires** — the
deployment that had been refused since 2026-07-20 now succeeds:

- `gpt-5-mini` **v2025-08-07**, GlobalStandard, capacity 10, on `dcl20s-aoai`
  (`…/accounts/dcl20s-aoai/deployments/gpt-5-mini`, `createdAt 2026-08-23T10:39:52Z`)
- `provisioningState = Succeeded`, `deploymentState = Running`
- **`PF-06 PASS — deployments match the register`**

**Guardrails re-locked, verified independently of the script's own claim** (the script prints
`== guardrails RE-LOCKED` from a trap, which is an assertion, not a check): `az policy assignment
show` returns `zerodollar-deny-nonfree-skus` with `enforcementMode = Default`, and
`apply-zero-dollar-guardrails.sh --verify` reports **both** `zerodollar-deny-nonfree-skus` and
`zerodollar-deny-cost-vectors` assigned — *"hard-$0 deny policies are in place."* The policy window
opened and closed; nothing was left relaxed.

`cc-decide action 2820133fc77c` recorded with that evidence. **Open set: 21 → 20.**

**Consequence for `739906feadbe`:** its sequencing dependency is **discharged**. The recommendation
was "run the cheap probe first, because a fresh fraud refusal would waste a new-account effort" —
the probe ran and came back clean, so tenancy standing is no longer the open risk. What remains of
that packet is only its own merit (it is labelled OPTIONAL, and its surfaces — Burstable Postgres +
an Entra app — are unrelated to Azure OpenAI). It is no longer blocked by anything.

Also unblocked per the packet's own text: *"everything downstream of this deployment (live full-spine
S0-S9 with CH-P extraction) is unblocked the moment it succeeds."*

---

## SECOND SWEEP — the other 15 open packets (2026-08-23)

The operator asked for **all** ratify decisions, not just the six. `cc-decide list --open --json`
reports **21 open**, and six more were researched this pass.

🚨 **COUNTING TRAP #2 — a glob on `status=='open'` undercounts by 5.** My census read 16 while the
tool read 21. Cause: **five packets carry no `status` field at all** (the `shipland-esc-*` ones —
the earlier `Counter` showed `None: 5` and it was misread as noise). `cc-decide` treats a missing
status as open; an equality test does not. **Always read `cc-decide list --open --json`, never a
hand-rolled glob** — this is a second, independent instance of the § counting correction at the top
of this file, in a new spelling.

### `a3b5aadfb217` — GO LIVE · **DEAD, no action** · ~95%
All four cited shas are ancestors of `origin/main` (`1ddba46`, `9c0d42a`, `6b39463`, `f53348a`), and
the deciding fact is that **step (2) is already applied**: `mailbox-drain` appears **3×** in each of
`~/.claude/settings.json`, `~/.claude-tertiary/settings.json`, `~/.claude-quaternary/settings.json`.
Step (1) is satisfied by today's live-layer convergence. The packet asks the operator to run two
commands that would both be no-ops.

### `adec28939635` — ship-rail permission posture · **ALREADY APPLIED** · ~93%
`allow → Bash(scripts/ship-land.sh:*)` is present in all three settings.json, alongside
`ask → Bash(git push:*)` and `deny → Bash(git push --force|-f:*)`. That IS the "narrow allow for the
transparent ship-land push only" the packet proposes. Its activation script
(`05-ship-rail-push-allow-activate.sh`) is **no longer in the un-run queue** (12 rotting, and it is
not among them) ⇒ it ran. The push happens *inside* the allowed script, so it is not a separate
tool call and cannot re-enter per-attempt classifier judgment.

### `1e325f3f5711` — Turso client 1.9.2 → 2.0.5 · **rec: YES, upgrade** · ~93% · *audit refuted*
🚨 **The packet's audit ("major in name only: no files removed, no exports removed") is WRONG — it
audited PACKAGING, not the API.** Diffing the two `dist/index.d.ts` shows genuine breaking changes:
`OrganizationInvite` renamed wholesale (`ID/CreatedAt/Role/Email/…` → `id/email/role/token/created_at`,
dropping `UpdatedAt`, `DeletedAt`, `OrganizationID`, `Organization`, `Accepted`); `inviteUser` now
returns a different type (`OrganizationInviteCreated`); **`deleteInvite` returns `void`** instead of
a record; `OrganizationMemberRole` widened with `"viewer"`.

**It is nevertheless safe here, for a better reason than the audit gave:** reso touches **none** of
that surface — `git grep inviteUser|deleteInvite|OrganizationInvite|OrganizationMemberRole` over
`origin/main` returns **zero** hits. `Group` is **byte-identical**; `Database` only **gains**
`database_type`; `createClient(config: TursoConfig): TursoClient` is **unchanged**; `TursoConfig`
only loosens (`org` required→optional, `token` widened to accept a factory). And the blast radius is
smaller than stated: of the four call sites, **two are `import type` only** — `PlatformContent.tsx:7`
and `platformActions.ts:4` erase at compile — leaving **two runtime sites**,
`sessionWrite.ts:33` and `tenantContext.ts:3`, both importing just `createClient`. `2.0.5` is `latest`.

### `5bccddb2bb52` — pin the first admin's username · **rec: LEAVE IT, no migration** · ~92%
`lib/auth/first-admin-invite.ts:36-37` states the mechanism outright: *"No username is pinned — the
`invitation` table has no username column; the invitee chooses one during the [registration]."* The
premise is confirmed — **and it supplies the route-around the packet missed.** The operator IS the
invitee, so they simply type `chrisren` at registration. `user.username` already exists `NOT NULL`
with `CREATE UNIQUE INDEX user_username_unique` (`drizzle/migrations/0000_magical_ulik.sql:73,83`),
and a freshly-provisioned tenant has no rows to collide with, so the desired name is always
available. **A migration on the auth path buys nothing here.**

### `2b9d23a05157` — run the SevenRooms read-only mapper · **rec: YES, safe to run** · ~90%
**The read-only claim is enforced by construction, not asserted.** `scripts/map_app_readonly.mjs:83`
installs `ctx.route('**/*', …)`; `:86` matches `['POST','PUT','PATCH','DELETE']` and `:88`
`route.abort('blockedbyclient')`; only `:94` `route.continue()` passes anything through. A second,
independent defence at `:50` refuses to click any control whose label matches
`/save|submit|send|delete|remove|cancel|confirm|charge|book|reserve|create|…/i`.

**It has also already been run — partially.** Artifacts dated 2026-07-20 (the packet's own open
date) exist at `~/Development/sevenrooms-introspection/mapping/`: `endpoints.json` (**52 endpoints,
all GET**) and `session2.har`, plus a dozen daemon logs. **`coverage.json` is absent**, and the
recorded statuses are `302` on `/login` and `/manager/home` — i.e. **that run was unauthenticated
and redirected**. So the packet's actual ask (hand-login, then crawl) is the missing half, and the
value of running it is real rather than duplicative.

*Instrument note:* my first search concluded "the mapper does not exist" — because I searched
`sevenrooms-bridge` and `reso-web-app`, and `sevenrooms-bridge/src/map/mapper.ts` is an unrelated
**sign-up→booking field mapper**. The real tool lives in a **third** repo named only inside the
plan's prose (`SEVENROOMS_NAVIGATION_INTROSPECTION_AGENT_TEAMS_PLAN.md:262`). A name collision plus
an unsearched repo produced a confident false negative.

### `7b406352c6f3` — SevenRooms channel A/B/C · **rec: start B now, and take the free proof** · ~75%
New fact that changes the shape: **option B has not been started.** `msg search "SevenRooms"` over
the operator's full history returns only operational venue chatter (2022–2026) — **no commercial or
Partner-API correspondence of any kind**. B's "unknown lead time" is therefore not merely unknown,
it has not begun, and its clock starts only when someone sends the first email. That argues for
**opening B immediately** (it costs one message and nothing else) rather than choosing B *instead
of* acting. Option A remains a pilot that halts on ~6 h session expiry. The packet's one-off live
add-then-remove PROOF is independent of the channel choice — but it is a **write to a live external
system**, so it stays the operator's authorisation, not a Follow-On-Gate item.

### `264154f10d1a` — Opus 5 spawn counts vs "never cap" · **rec: KEEP never-cap for research** · ~85%
Citations, checked: reso `CLAUDE.md:513` is **exact** — *"NEVER cap research-subagent parallelism …
Default 10-30 parallel research subagents."* The infra citation has **drifted**: `PARALLELIZE BY
DEFAULT` is at **`:138`**, not `:131` (`:131` is the Agent-Teams-are-the-default line). Its own
source doc repeats the stale number (`opus5-adaptation-2026-08-01.md:94` cites `:130/:131`).

The conflict is **real and sourced**, but one hop removed: the Opus 5 quotes
(*"delegates to subagents more readily than prior models"*, *"keep spawn counts low"*, *"prefer one
subagent to several"*) appear in `docs/research/opus5-adaptation-2026-08-01.md:25,94-96`, which
quotes an external guide — **grepping the bundled `claude-api` skill and all of `~/.claude/skills/`
for that guidance returns nothing**, so it is not independently checkable on this machine. That doc
already books this as *"Blocked on you (value-fork): D2b"* (`:224`).

🚨 **This session is itself a two-sided natural experiment, and it argues for keeping the rule:**

1. **Over-spawning is already bounded by a MECHANISM, not by policy.** Of 5 subagents spawned in one
   message, `capacity-admit` **refused 4** (10 sessions mid-turn vs ceiling 8) and told the lead to
   run serially. So the never-cap *policy* is not what governs spawn volume — the admission gate is.
   Removing the policy would change little except to make the lead under-fan when capacity is free.
2. **Under-spawning would have cost accuracy, measurably.** The focus-ring subagent's independent
   read is what established that `CONSTRAINTS.md` is a **generated mirror whose source lists three
   rings** — reversing a recommendation this lead had recorded at ~95% conviction. A single-agent
   run would have shipped the wrong answer with high confidence.

And the Opus 5 concern most often cited here — *"do not use subagents to verify or double-check your
own work"* — is about **self-verification**, which the global CLAUDE.md already distinguishes by name
from *"a fresh-context reviewer of a teammate's output, which is a real second pair of eyes."* Point
2 above is the latter, not the former. **Recommendation: keep never-cap for read-only research
fan-out.** Still the operator's ratified rule and explicitly not the agent's to flip.

*(Counter-evidence, recorded honestly: 3 of 3 subagents in the first wave went idle without
delivering and had to be pinged before they reported — twice now across two sessions. That is a
delivery-path defect, not an argument about counts, but it does mean a wide fan-out currently costs
the lead an extra collection round-trip.)*

### `409693600c90` — reboot posture · **rec: LaunchDaemon conversion** · ~80%
Premise **confirmed**: **25** `com.claude.*` LaunchAgents, **0** LaunchDaemons, `fdesetup status` =
*"FileVault is On."*

**The measurement that reshapes the choice: only 1 of the 25 is GUI-bound.** Classifying each job by
whether its `ProgramArguments` script references `osascript|iTerm|kitty|it2-|AppleScript|cc-pane|
handoff-fire`, exactly one hits — **`com.claude.lead-supervisor`** — and **24 are daemon-safe
candidates** (`compressor-sentinel`, `capacity-alarm`, `deploy-live`, `cc-gc`, `discovery`,
`auth-timeseries`, …). The intuitive objection to option 1 — *"these all drive panes, so they can't
run pre-login"* — is **false for 24 of 25**. That makes the LaunchDaemon conversion mostly mechanical
and removes most of the motivation for the auto-login option, which is the one carrying a real
security cost.

Recommended shape: **convert the 24, leave `lead-supervisor` a LaunchAgent** (it legitimately needs
the Aqua session), and let the existing `com.claude.boot-resume` agent cover the post-login half.
Option 3 is then not an alternative but the *remainder* of option 1.

⚠️ **Two limits on this measurement, stated so it is not over-read.** (a) The classifier reads each
job's **direct** script only — a job that reaches a GUI helper transitively through a sourced lib
would be missed, so the 24 needs a per-job check before conversion, not a bulk `launchctl` move.
(b) The packet's phrase *"FileVault … halts the whole desk until console login"* conflates two
different gates: FileVault's **pre-boot unlock** (unavoidable, and a daemon cannot precede it) with
**console login** (which only LaunchAgents wait for). A daemon runs after pre-boot unlock without a
console login; that is exactly why the conversion helps. Worth confirming before conversion.

🚨 **CORRECTION (same session, cross-check) — the LaunchDaemon recommendation above is WRONG on both
halves. Superseded; kept per INTEGRATE-never-overwrite.**

1. **FileVault voids the conversion entirely, and I had the direction backwards.** I wrote *"a daemon
   runs after pre-boot unlock without a console login; that is exactly why the conversion helps."*
   The opposite is true: with FileVault On the volume is **not mounted at boot**, so
   `/Library/LaunchDaemons` **cannot be read** until a human authenticates at the pre-boot screen —
   and that authentication proceeds into a normal login session anyway. **A daemon therefore starts
   no earlier than the agents already do.** Option 1 buys nothing for the stated problem.
   Corroborating: `defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser` → *does
   not exist* (auto-login OFF), and `fdesetup supportsauthrestart` → `true`, which is the one real
   lever — `fdesetup authrestart` for **planned** reboots.
2. **My "1 of 25 GUI-bound" count was wrong because my classifier could not see a whole category.**
   I grepped for `osascript|iTerm|kitty|it2-|AppleScript|cc-pane|handoff-fire` — which misses
   **keychain-bound** jobs. `relogin`, `accounts-keepwarm` and `auth-timeseries` read the **login
   keychain** (`security find-generic-password`, `bin/claude-accounts:31-34`): locked pre-login, and
   a *root* daemon has no access to a user keychain at all. With Aqua-bound jobs added
   (`lead-supervisor` 13 hits, `autonomy-sweep` 10, `capacity-alarm` 10, `cc-reaper` 5,
   `teammate-reap-alarm`, `compressor-sentinel`, `browser-spin-guard`, `screenshot-clipboard`) the
   real figure is **~10 blocked, not 1**. *This is the exact limitation I flagged one paragraph
   earlier and then over-read anyway — the caveat was written and not applied.*
3. **Option 3 is not an alternative — it is already built, loaded, and running.**
   `com.claude.boot-resume` is live (`launchctl list` → `7766  0  com.claude.boot-resume`),
   `RunAtLoad = true`, `StartInterval = 300`. `~/.claude/autonomy/boot-resume/` contains **only**
   `last-boot-epoch` — **no `mode` file**, so it runs in default `page` mode and has never fired
   (`disposition:"fired"` count = 0). **Arming it is writing `resume` to
   `~/.claude/autonomy/boot-resume/mode`** — one file, no conversion, no security tradeoff.

**Revised recommendation (~90%): close the three-way choice as posed.** Option 1 is void (FileVault),
option 2 (auto-login) buys a security cost for a problem option 3 already solves, and option 3 is
built and one file from armed. The only genuinely open lever is `fdesetup authrestart` for planned
reboots. *(Not verified by an actual reboot — the FileVault ordering is established from
`fdesetup status` plus the absent auto-login setting, not from an observed boot.)*

### `f91a9701ed21` — Pushover credentials · **premise TRUE, but fix the FILTER first** · ~90%
Re-scoped by measurement. The creds really are unset in **all eight** locations checked (process env,
4 shell rcs, 4 settings.json, `*.env`, launchd plists), and the consumer branch is a **silent** no-op:
`hooks/push-critical.sh:21-22` — `[ -z "${PUSHOVER_TOKEN:-}" ] && exit 0`, wired into 3 Notification
slots across 5 config dirs.

**The volume is the finding: `~/.claude/autonomy/push-records/` holds 363 records, 354 of them in the
last 7 days, and the verdict histogram is `{'inert': 363}` — 100%, with not one non-inert record in
the store's entire history.** Corroborating backlogs in 7 days: `autonomy/pages` 226,
`completion-push` 108, `cc-announce-alarms` 108.

**So the premise is true for an AWAY human but false as written.** A live local channel exists —
macOS Notification Center (`osascript display notification`) in 14 scripts — and it reaches the
operator *at the desk*; it simply cannot reach a phone. Independently confirmed: no other remote
sender exists anywhere (`grep -rlnE "osascript.*Messages|mail -s|sendmail|smtplib|ntfy\.sh|hooks\.slack|twilio"`
over `bin scripts hooks` returns only `hooks/curl-gate.py`, a lint).

🚨 **Therefore the fix is a FILTER first and a secret second.** `push-critical.sh` is wired to
`permission_prompt`, and `docs/research/oversight-at-scale-2026-08-19.md:193` measures that exporting
the creds as-is would light **~5.3 pushes/hour**. Handing over the token today converts a silent
channel into a spamming one. **Recommend: land the filter, then add the secret** — do not action the
packet as written.

Also stale in the packet: *"CC_PAGE_TO empty ⇒ pages go nowhere"*. `scripts/lead-supervisor.sh:321`
falls back to the role file when `CC_PAGE_TO` is empty (landed `dfcc7e0e`), and the plist sets it
SET-BUT-EMPTY, which that fallback handles.

*(Superseded, kept for history:)* ~~### `f91a9701ed21` — Pushover credentials · **still open** · ~60%~~
Premise partly checked (`PUSHOVER_TOKEN` / `CC_PAGE_TO` not exported in this session's environment),
but the load-bearing question is **Q4: does another away-channel already reach the operator?** This
repo demonstrably ships `cc-notify`, a mailbox/inbox path, and a page channel with its own
activation script (`04-page-channel-activate.sh`). If any of those reaches a phone, the packet's
*"every page and alarm is currently silent to an away human"* is false and the decision shrinks to a
redundancy question. **NOT VERIFIED — do not action either way until Q4 is answered.**

---

## VERDICT TABLE — the six, after W1+W2 (2026-08-23)

| # | id | named fact | verified? | evidence (file:line / measurement) | conviction | disposition |
|---|---|---|---|---|---|---|
| 1 | `ef79469fbb12` | predicate is unanchored `endsWith` | **yes** | `lib/auth/platform-email.ts:17` (**not `:11`** — corrected) | 95% | **⛔ operator — AUTH. Never self-actioned.** |
| 2 | `922699aacda0` | how many burst branches still merge | **yes** | 2 clean / 27 conflict / 12 gone; **30** patch-stranded, not 49; 26 carry a prior `.land-refused` | 95% | **rec REFUTED → let the 2026-08-30 default fire** |
| 3 | `739906feadbe` | same Azure surface as `2820133fc77c`? | **yes** | runbook `:17`, `:3`, `:91`; `c7b7f16b`; dc-wiring sha `3c6e449…` | 90% | **⛔ operator — money path. Sequence behind the probe.** |
| 4 | `9d97a3c272a2` | does the current lint flag site (c)? | **yes — no, measured with a control** | `eslint.config.mjs:311,464,466` + `use-focus-ring-token.mjs:74,172` | 95% (fact) / 93% (rec) | **rec REVERSED → authority is `focus-ring.ts`, NOT `CONSTRAINTS.md` (a generated mirror whose source lists 3 rings)** |
| 5 | `7d4a230457c5` | "no bearer credential to its run directory" | **yes** | `provision-run-store.ts:272`; `provision-venue.ts:1524-1528,2687`; `events.pure.ts:165-167` | 93% | **⛔ operator — AUTH. "Leave it" confirmed, but RE-STATE the packet first (premise false, see §5)** |
| 6 | `shipland-esc-c661813` | is `feat/autonomy-100` landable? | **yes** | 13 conflicted files vs `origin/main` | 95% | **not landable — harvest by cherry-pick, don't land** |

**Every named fact is now verified.** Nothing was self-actioned: `ef79469fbb12` and `7d4a230457c5`
are auth surfaces, `739906feadbe`/`2820133fc77c` are money-path, `922699aacda0`'s default fires on
its own, and no branch in the escalation set is mergeable in the first place. Three of the six had
their **stated reason** falsified while their **recommendation** survived (#4, #5 strengthened, #3
re-grounded); one had its recommendation outright refuted (#2); one turned out to be asking the
operator to choose between options that do not exist (#6).

### Filed out of this pass (agent work, not operator work)

- **`use-focus-ring-token.mjs` `COLOR_REF` cannot see a bare Panda token path**, while the rule's own
  docstring says arm B covers one. Promoting the strict arms repo-wide (already a filed operator
  call) would ship a false green over `settings-ghost.recipe.ts:44-48`. Fix the regex *before* the
  promotion, not after.
- **`ProvisioningConsole.tsx:337-338` tells the operator the opposite of what `:437` does** — the
  paragraph says the first-admin invite "is not issued here … a deliberate CLI step" while the button
  100 lines below issues it. Docs-only fix in reso, no decision attached, but it is misleading
  exactly the person about to rule on `7d4a230457c5`.
- **The five `shipland-esc-*` packets are one bug, not five decisions.** `cc-decide list --open`
  carries `-c661813` (`feat/autonomy-100`), `-86b7c96` (`docs/frontier-problems…`), `-ab66db8`
  (`wt-6cab0ab3cb2f`), `-1ca84e4` **and** `-a877ec8` (both `fix/infra-perfection`, two landing
  ranges), `-3511d99b` (`tm/growth`). All six are the same false positive, and W2 shows **none of
  the five branches is mergeable**, so no classifier fix resolves any of them. They should be closed
  as a group against the narrowing fix, not adjudicated one at a time.

---

## Status log

- **2026-08-23** — Triaged all 17 open ratification decisions. Closed 6 with disk-verified evidence.
  Researched the sub-90% set to the named-fact level. Recorded the escalation-classifier false
  positives, the `ship-land` exit-0 defect, and the live-layer convergence. Three research subagents
  were spawned; all three went idle and **never returned reports** — nothing here depends on them.
  Capacity gate refused three further fan-outs at the active-turn ceiling; research ran serially.
- **2026-08-23 (second pass)** — W1 + W2 complete. **All six named facts verified**; see § VERDICT
  TABLE. Nothing self-actioned and nothing committed (this file stays untracked in the shared
  checkout, per the standing constraint). Substantive outcomes: `922699aacda0`'s recommendation
  refuted by measurement (2 clean branches holding a throwaway A/B probe, not 8 holding real work);
  all 5 escalation-parked branches proven **un-mergeable**, so the classifier fix cannot make them
  landable; `ef79469fbb12`'s line citation corrected `:11` → `:17`; `7d4a230457c5`'s open claim
  confirmed as a **type-level** invariant; `9d97a3c272a2`'s lint gap traced to a `COLOR_REF` regex
  that cannot match the very spelling its own docstring claims to cover.
  **Three research subagents were spawned again and again returned nothing before the work
  completed** — second consecutive session with that outcome, so the three cross-repo verifications
  were driven on the lead instead. That is now a pattern worth its own investigation rather than a
  per-session workaround; it does not affect any verdict above, all of which were measured directly.
