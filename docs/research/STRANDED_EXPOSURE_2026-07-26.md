# Stranded-commit exposure of the gate runaway loop — re-derived (2026-07-26)

Impact measurement for backlog `915a3fa56361`, closing out the raw estimate filed against
the gate runaway loop (`f8e40b4c577d` mechanism, `a0718a5d78b3` root cause).

**Verdict — the loop's cost is real and structural, but every raw count of it has been
wrong, in both directions at once.** True exposure is **209 distinct patches** repo-wide —
**164 on live worktree branches** (the actionable slice, §1-§4) plus **45 orphaned on
branches whose worktree is gone** (§6). Not ~290, and emphatically not the
~1,500-commit figure the raw metric produces: 1,525 raw rows across 241 branches collapse
to 209 distinct patches, a 7.3× overcount. The sweep the item proposes must NOT run yet —
both of its stated preconditions are verified UNLANDED on trunk, and the loop was
measurably ACTIVE while this measurement was taken.

**§8 (added 2026-07-26, backlog `85de64e3ce08`) rules the orphaned set** and revises this
verdict once more, in the same direction: of 60 orphan-exclusive patches (45 at the time of
§6 — the set GROWS as worktrees are reaped), **4 are RECOVER and 56 are ABANDON with no work
lost.** 73 of the 81 carrying branches are machine-generated `ship/backup-*` refs that
`ship-land.sh:690` never deletes — so most "orphaned" exposure is a ref leak manufactured by
successful landings, and patch-id alone overcounts it monotonically.

## 1. The corrected number — four overlapping detectors

| # | Detector | Value | What it tells us |
|---|---|---|---|
| — | **As filed** (`915a3fa56361`) | **~290** / 25 worktrees | raw `origin/main..HEAD` summed per worktree |
| D1 | raw `origin/main..HEAD` summed, re-run | **342** / 36 branches | same metric, wider + later scan |
| D2 | patch-id **not upstream** (`--cherry-pick --right-only`) summed | **342** | **zero** commits already landed by content |
| D3 | **union** of distinct commit SHAs (`rev-list <all refs> --not origin/main`) | **219** | 123 rows (36%) were double-counted across branches |
| D4 | **union deduped by `git patch-id --stable`** | **164** | a further 55 are the *same patch* re-committed under new SHAs |

**D4 = 164 is the landable exposure** — the count of distinct pieces of work that exist
nowhere on trunk. D1→D4 is a 52% reduction from the raw metric.

Scan basis: `origin/main` = `1f19ac0`, fetched fresh; 53 worktrees enumerated
(1 main checkout + 52 linked), 36 branches carrying commits, 9 dirty trees, 10 worktrees
fully clean-and-landed (pure GC candidates).

### Why the raw metric misleads in both directions

- **Over, by content (−178 rows).** `git rev-list` counts SHAs, and this repo's parallel
  worker pattern produces the same patch on many branches. Two compounding effects:
  - *Nested stacks* — `tm/gates`(38) ⊂ `tm/growth`(46); `tm/hygiene`(29), `tm/hooks`(23),
    `tm/closure-a`(13) ⊂ `tm/gates`; `tm/wtgc`(9), `tm/launchd`(7) ⊂ `fix/infra-perfection`.
  - *Independently duplicated work* — `fix/infra-perfection`(55) and `tm/growth`(46) share
    **42 patch-ids under different SHAs**. Neither is upstream, so D2 cannot see it; only
    patch-id can. `tm/growth` is **100% covered** by `fix/infra-perfection ∪ tm/hygiene` —
    it contributes zero unique patches. 53 duplicate-patch groups exist inside the unlanded
    set, three of them triplicated (e.g. `feat(worktree-gc): the janitor…` ×3).
    This is the parallel-stream convergence pathology (same incident, parallel fixers,
    no pre-build sibling sweep), now quantified.
- **Under, by scope (+11 branches).** The filed scan covered 25 worktrees; 36 carry
  unlanded commits. Unlisted holders include `feat/board-runnable-commands`(19),
  `wt-02ba4e52389a`(8), `wt-1a941c28a079`(8), `wt-a3d505ff2cef`(8), `wt-6cab0ab3cb2f`(8),
  `wt-63929c8d6072`(7), `wt-94edb2fa9f14`(5).
- **Stale, in one place that matters.** The filed `relogin 20` is now **0** — that branch
  landed between filing and this scan. `wt-cc-relogin` likewise sits exactly at
  `origin/main`. The exposure is not a frozen quantity; it moved during a one-hour window.

The item's own caveat ("some branches may be superseded or abandoned") is **refuted for the
cherry-pick case specifically**: D2 finds zero commits already upstream by content. The
redundancy is entirely *among the unlanded branches themselves*, not against trunk.

## 2. Precondition verdict — NOT met (verified on trunk, not from the ledger)

The item gates its action on "once admission control + scoped-pkill land". Checked against
`origin/main` file-by-file — all four required fixes are absent:

| Required fix | Source | State on `origin/main` |
|---|---|---|
| (B) admission control — defer on load | `f8e40b4c577d` | **ABSENT.** `postland-verify.sh:68,139` and `ship-land.sh:277` only *record* `vm.loadavg` into forensic JSON. No `defer`/`shed` anywhere in the land path. |
| (A) signal-kill as a THIRD state | `f8e40b4c577d`, `a0718a5d78b3`(2) | **ABSENT.** `postland-verify.sh:138` computes `sig:N` for `rc>128` — but only as a *field in the stamp it still writes*. A killed run is still recorded. |
| (1) worktree-scoped pkill | `a0718a5d78b3` | **ABSENT.** `scripts/reaper-e2e.sh:24` still runs `pkill -f "$LABEL"`, machine-wide. |
| (3) lint forbidding unscoped pkill | `a0718a5d78b3` | **ABSENT.** No such test in `tests/`; `reaper-e2e.sh` is the sole remaining `pkill` site in tracked scripts. |

Ledger state agrees and adds nothing: `a0718a5d78b3` has only an `add` record (never
claimed); `f8e40b4c577d` was claimed 04:38Z then reopened 05:05Z. Neither is `done`.

**The unblock is 2 commits away.** Both fixes already exist, unlanded, on
`fix/gate-runaway-loop` — `7dda0f8 fix(gate): signal-kill is a third state, and shed load
before a full suite` + `6fbec78 fix(ship-land): resolve SCRIPT_DIR through symlinks`
(256 lines / 4 files). That branch is owned by `f8e40b4c577d`; landing another session's
branch is exactly the drop incident this repo's CLAUDE.md forbids, so it is named here for
its owner, not taken.

## 3. The loop was active during this measurement

Sampled while scanning, without running any gate:

```
vm.loadavg     { 18.26 22.85 21.93 }
bats procs     78
ship-land runs 13   ← concurrent, unserialized
claude procs   24
```

This is mechanism (5) of `f8e40b4c577d` observed live: N worktrees each running a full
suite outside the land-lock. It independently corroborates the filed forensics
(load 20-31, 180 bats procs, 42 ship-land runs) and it is why §4 is a plan, not an action.

**This measurement was therefore deliberately kept gate-inert.** `gate-select.sh:121-125`
classifies `docs/research/**.md` as prose ⇒ empty selection ⇒ lint-only land. A new
`scripts/*.sh` matches `INSTALL_RE` (`gate-select.sh:90-93`) and would pull bats suites
into a 13-way-contended, unscoped-`pkill`-exposed gate — i.e. shipping the measurement's
own tooling would have fed the pathology being measured. The reproducible harness is
specified in §5 and deferred to the sweep, by design.

## 4. Sweep plan — for after the preconditions land

Corrects the filed ordering: **precondition-first, then smallest-diff-first.**
`fix/gate-runaway-loop` is both the unblocker and the 6th-smallest diff, so it is not a
trade-off.

**Step 1 — delete, do not land: 11 fully-redundant branches.** Every patch is already
carried by another branch. Landing them means 130 redundant commits through the gate and
guaranteed rebase conflicts against their own superset.

| Branch | Commits | Wholly contained in |
|---|---|---|
| `tm/gates` | 38 | `tm/growth` |
| `tm/hygiene` | 29 | `tm/gates` — *but see note* |
| `tm/hooks` | 23 | `tm/gates` |
| `tm/closure-a` | 13 | `tm/gates` |
| `tm/wtgc` | 9 | `fix/infra-perfection` |
| `tm/launchd` | 7 | `fix/infra-perfection` |
| `feat/relogin-executor` | 4 | `feat/relogin-build` |
| `feat/relogin-browser` | 2 | `feat/relogin-build` |
| `feat/relogin-probes` | 2 | `feat/relogin-build` |
| `feat/relogin-schedule` | 2 | `feat/relogin-build` |
| `wt-f8e40b4c577d` | 1 | `fix/gate-runaway-loop` |

*Note:* `tm/growth` is itself redundant (0 unique patches) but `tm/hygiene` carries **4
patches** that `fix/infra-perfection` does not. Land `fix/infra-perfection` + `tm/hygiene`
and the entire `tm/*` family is covered; `tm/growth` and `tm/gates` can then be dropped.
Verify before deleting anything — see §5.

**Step 2 — land 25 branches covering all 164 patches, smallest-diff-first.** Zero patches
uncovered by this set. `LINES` = insertions+deletions vs `origin/main`.

| Order | Branch | Commits | Files | Lines |
|---|---|---|---|---|
| **0** | **`fix/gate-runaway-loop`** ← precondition, land first | 2 | 4 | 256 |
| 1 | `wt-fdf4161aeb28` | 2 | 2 | 57 |
| 2 | `fix/reaper-desk-registration` | 1 | 2 | 184 |
| 3 | `fix/iterm-sticky-custom-command` | 1 | 4 | 204 |
| 4 | `wt-a186c7d48637` | 1 | 3 | 207 |
| 5 | `feat/activation-ssot-parity` | 1 | 2 | 255 |
| 6 | `wt-2d36e63d16a2` | 2 | 2 | 298 |
| 7 | `docs/relogin-research` | 1 | 1 | 393 |
| 8 | `wt-0c93f779ecfa` | 1 | 3 | 415 |
| 9 | `tm/closure-b` | 3 | 8 | 451 |
| 10 | `relogin-design2` | 1 | 1 | 464 |
| 11 | `wt-a3d505ff2cef` | 8 | 22 | 670 |
| 12 | `wt-761a546f939c` | 1 | 5 | 692 |
| 13 | `feat/relogin-observability` | 3 | 5 | 881 |
| 14 | `wt-1a941c28a079` | 8 | 15 | 1046 |
| 15 | `feat/board-runnable-commands` | 19 | 23 | 1152 |
| 16 | `wt-63929c8d6072` | 7 | 53 | 1415 |
| 17 | `wt-94edb2fa9f14` | 5 | 58 | 1611 |
| 18 | `fix/session-close-hardening` | 5 | 13 | 1652 |
| 19 | `wt-6cab0ab3cb2f` | 8 | 13 | 1935 |
| 20 | `wt-02ba4e52389a` | 8 | 29 | 2467 |
| 21 | `docs/frontier-problems-2026-07-23` | 2 | 32 | 4021 |
| 22 | `feat/relogin-build` | 21 | 23 | 5441 |
| 23 | `tm/hygiene` | 29 | 85 | 6913 |
| 24 | `fix/infra-perfection` | 55 | 125 | 10694 |

**Step 3 — 9 dirty trees need a commit (or a discard) before their branch can land.**
The filed list of 4 was incomplete.

| Worktree | Dirty files | Branch is ahead by |
|---|---|---|
| `wt-tm-closure-b` | 4 | 3 |
| `wt-cc-relogin` | 2 | 0 |
| `wt-cc-upgrade-gate` | 2 | 0 |
| `wt-relogin-build` | 2 | 21 |
| `permission-beacon` | 2 | 0 |
| `wt-664c62164ccf` | 2 | 0 |
| `wt-relogin-design` | 1 | 0 |
| `wt-d1ba434f6239` | 1 | 0 |
| `wt-f8e40b4c577d` | 1 | 1 (redundant — see Step 1) |

**Rails, unchanged from the item.** Serialized, one at a time, via the project-local
`/ship` only (never a bare push). Re-fetch before each. **Verify every landing by CONTENT,
never by commit count** — `git rev-list origin/main..HEAD` reading 0 is exactly the false
signal that hid the 2026-07-11 drop:

```bash
git fetch origin --quiet
git ls-tree -r origin/main --name-only -- <the branch's declared paths>
```

## 5. Reproducing this measurement

Every figure above is re-derivable. Detectors D3/D4 are the ones that matter — a raw
`origin/main..HEAD` sum is not a measurement of work, only of rows.

```bash
# D1/D2 per branch
git rev-list --count origin/main..$B
git rev-list --count --cherry-pick --right-only origin/main...$B

# D3 — union of distinct SHAs across every branch carrying work
git rev-list --no-merges $ALL_REFS --not origin/main | sort -u | wc -l

# D4 — the landable number: dedupe that union by patch-id
while read -r sha; do
  git diff-tree -p --no-commit-id "$sha" | git patch-id --stable | awk '{print $1}'
done < union.txt | sort -u | wc -l

# §6 repo-wide — branches with no worktree. `git cherry` splits the two classes:
#   '+' = content NOT on trunk · '-' = rebase-landed (SHA unreachable, content IS on trunk)
git for-each-ref --format='%(refname:short)' refs/heads/ > all.txt
git worktree list --porcelain | awk '/^branch /{sub(/^refs\/heads\//,"",$2); print $2}' | sort -u > wt.txt
comm -23 <(sort -u all.txt) wt.txt | while read -r b; do git cherry origin/main "$b"; done \
  | awk '/^\+/{print $2}' > nowt-plus.txt      # then patch-id-dedupe as in D4
```

**Relationship to the existing tooling — complementary, not a duplicate.** Trunk already
carries the landing-safety family `land-lock.sh` / `land-verify.sh` / `postland-verify.sh` /
`stranded-sweep.sh`. `stranded-sweep.sh` answers a **narrower and different** question: it
flags the *drop* class — a commit not patch-equivalent on trunk, not reachable by SHA, **and
all of whose paths are absent from the trunk tree** — and it is deliberately per-branch and
review-not-fail (`git cherry`, i.e. detector D2 only). It has no cross-branch union (D3), no
patch-id dedupe (D4), and no subset/cover analysis, so it cannot see the 178 redundant rows
or produce §4's ordering. The two should stay separate: one detects *lost* work, the other
quantifies and sequences *pending* work.

**Deferred, and why:** packaging D3/D4 plus the subset/greedy-cover analysis that produced
§4 as `scripts/stranded-exposure.sh` is the durable form — a doc figure rots, and this one
demonstrably did (290 → 342 in roughly an hour). It is held back only because a new
`scripts/*.sh` is gate-coupled (§3) and the gate is currently the broken component.
**Ship it as the first commit of the sweep, once `fix/gate-runaway-loop` has landed and the
gate can be trusted.**

## 6. Scope correction — branches with no worktree

§1-§4 scope to *worktree-attached* branches, matching how the item was filed ("across 25
worktrees"). That is the right scope for the sweep — a live worktree is the signal that the
work is live — but it is **not** the repo's full exposure. The `stranded-sweep.sh` run at the
end of this doc's own landing reported "311 commits across 374 branches", which forced the
wider scan:

| | Branches | Raw rows | Not upstream by content | Distinct patch-ids |
|---|---|---|---|---|
| Worktree-attached | 36 | 342 | 342 | **164** |
| No worktree | 205 | 1,183 | 887 (`git cherry` `+`) | 195 |
| **Repo-wide** | **241** | **1,525** | 1,229 | **209** |

Three things fall out, and they matter more than the totals:

1. **296 rows on no-worktree branches are already on trunk by content** (`git cherry` `-`)
   — rebase-landed, so their original SHAs are unreachable and `origin/main..$b` still
   counts them. Any exposure metric built on `rev-list` alone inflates by exactly this
   amount, permanently. This is the mechanism behind the "~223 branches / 1,491 commits
   unlanded" figure carried in prior notes: it is a *row* count, not a work count.
2. **150 of the 195 no-worktree patches are stale duplicates of the live 164** — the same
   work, left behind on branches whose worktrees were GC'd. Only **45 patches exist
   exclusively** on a branch with no worktree.
3. Those **45 are the genuinely at-risk set**: no worktree means no session, so nothing is
   driving them, and `stranded-sweep.sh`'s review verdict is the only thing surfacing them.
   They need **triage (abandon vs. recover), not a land sweep** — a different task from §4,
   and deliberately not folded into it. 107 no-worktree branches carry at least one.

The 324 branches with no worktree are also the standing worktree/branch-GC backlog: 98 of
the 205 carrying raw commits carry **zero** unlanded content and are pure delete candidates.

## 7. What this measurement does NOT claim

- **Not a claim that all 164 patches are finished or green.** It bounds *exposure* —
  work that exists only outside trunk. Per-branch readiness is unaudited; some branches
  may be abandoned by intent.
- **`⊆` is patch-id containment, not a merge-safety proof.** Verify a subset relation
  immediately before deleting any branch; the set can change under you.
- **Ordering is by diff size, a proxy for gate cost**, not by risk or dependency. A small
  diff to a shared surface (`install.sh`, `settings-templates/`) triggers a FULL gate —
  see `gate-select.sh` Rule 2 — and costs far more than its line count suggests.
- **The 45 no-worktree-only patches (§6) are unaudited for intent.** "Content not on trunk"
  is not "work someone still wants". Abandoned-by-decision and dropped-by-accident are
  indistinguishable from git alone — that set needs a human ruling per branch, which is why
  §4 excludes it. **→ NOW RULED: see §8** (backlog `85de64e3ce08`, 2026-07-26). The premise
  above holds but was incomplete: git alone cannot separate the two *by patch-id*, yet two
  further detectors (§8.3) do separate them, and they reclassify 56 of 60 as
  already-covered — the set needing genuine human judgement is 4 patches, not 45.
- **The scan is a point-in-time snapshot** (`origin/main` = `1f19ac0`). Re-run §5 before
  acting; do not hand these numbers forward as fact. The exposure moved twice *during* this
  measurement (290 → 342 raw in an hour; contention 78 → 105 bats procs in ~15 min).

## 8. Triage of the orphaned set — ABANDON vs RECOVER (backlog `85de64e3ce08`, 2026-07-26)

Discharges the §7 caveat and backlog `85de64e3ce08`. **Verdict — 4 of 60 orphan-exclusive
patches are RECOVER; 56 are ABANDON, and none of the 56 loses any work.** The orphaned class
is not a graveyard of forgotten features: **73 of the 81 carrying branches are
machine-generated `ship/backup-*` refs** that `ship-land.sh:690` creates before every land and
never deletes (§8.2). The genuinely-at-risk residue is 4 small patches / 8 files, and only
one of them is a feature — the other three are a repo-SSOT backup, a latent lint blocker, and
a research doc.

The count moved 45 → 60 since §6, in the direction §6 predicted: worktree GC *migrates*
patches into the orphan class (a patch shared with a live worktree branch stops being
"covered" the moment that worktree is reaped). The orphan set is therefore a **growing**
liability while the ref leak stands — which makes §8.2, not the four recoveries, the finding
with the long tail.

### 8.1 Re-derivation — pinned, and drifting under us

`origin/main` moved twice during this triage (`1f19ac0` → `f4c1725` → `995dd96`), so the
§5 recipe was re-run **pinned to a fixed base** rather than to the moving ref. Anyone
re-running this must pin too: the first unpinned pass produced 61/82 against a base that
advanced mid-scan, and the pinned pass produced 60/81. That 1-patch delta is not noise in the
method, it is the repo landing work while the scan reads it.

| | Branches | Raw `+` rows | Distinct patch-ids |
|---|---|---|---|
| Worktree-attached | 40 | 356 | 180 |
| No worktree | 159 | 1,135 | 230 |
| Repo-wide | 199 | 1,491 | **240** |
| **Orphan-exclusive** (no-wt minus wt) | **81 carry ≥1** | — | **60** |

Base `995dd96`; 464 local branches, 57 worktree-attached, 407 without. `git cherry` also
classified **344 rows on 132 no-worktree branches as `-`** — already on trunk by content,
the rebase-landed class §6 note 1 warns about. Trap (1) from the item is therefore confirmed
at the new base, at a similar magnitude (296 → 344 rows).

### 8.2 The structural finding — the orphan class is mostly a ref leak, not abandoned work

`scripts/ship-land.sh:690` runs, before the gate rounds:

```bash
git branch -f "ship/backup-$(git rev-parse --short HEAD)" HEAD   # rollback point
```

Nothing deletes it on success. Every `/ship` invocation therefore leaves a permanent branch
pinning the **pre-rebase** commits, whose SHAs *and often patch-ids* differ from what landed
(the rebase reflows context; a landing frequently also revises the commit). `git cherry`
scores those refs `+`, and patch-id dedupe cannot collapse them onto their landed twins —
so each successful land manufactures fresh "stranded" rows, permanently.

Of the 81 branches carrying orphan-exclusive patches: **73 are machine-generated**
(`ship/backup-*` ×70, `backup/daemon-window`, `backup/pre-c605a2e-3218b24`,
`agent-a324-prerebase-backup`) and **8 are human/session branches** (`infra-green`,
`infra-green-v2`, `wt-d46bb5fbdb8f`, `wt-d1ba434f6239`, `park/gc-session-index`,
`fix/cc-discover-c3-reason-aware`, `feat/session-scoped-close`,
`cc/reobserve-waiting-recycle`).

**This is the same error-class as the rev-list inflation §6 diagnosed, one level up.** §6
fixed "rows ≠ patches"; this fixes "patches ≠ work". An exposure metric built on patch-id
alone counts every landing twice — once as trunk, once as its own backup ref — and the
overcount grows monotonically with landing volume. The durable fix is a ship-flow reaper
(delete `ship/backup-<sha>` once `<sha>`'s content is content-verified on trunk), which is
**named here and not built** — new `scripts/*.sh` is gate-coupled (§3) and the gate is still
the broken component (§8.6).

### 8.3 Two detectors patch-id cannot substitute for

Patch-id equality answers "is this exact diff on trunk". It cannot answer the question triage
actually needs — "is this *work* covered somewhere" — so two detectors were added.

- **D5 — substance-on-trunk (status-aware).** For each added line of real content, is that
  exact line in the trunk version of the same file? Per-file by diff status: `A`/`M` need the
  lines present; **`D` needs the file ABSENT**. The `D` arm is load-bearing — a v1 without it
  scored `7c62d033` ("remove obsolete watcher") at 0% and would have ruled it RECOVER, when
  in fact both files are already gone from trunk and the patch is fully applied.
- **D6 — subject-level coverage.** Does the commit's exact subject exist on trunk, or on a
  live worktree branch? This catches what D5 cannot: a commit that landed in *revised* form.
  31 of the 60 match a trunk subject (their D5 scores span 40–100% — the shortfall measures
  how much the commit was edited between backup ref and landing, not how much is missing).

**Both were RED-proofed before use.** Positive control: the four tip commits of trunk scored
100/100/100/100 through D5. Negative control: the *same* commits re-scored against their own
parent — where the content genuinely does not exist yet — scored 0/6/12/4. A detector that
cannot return "absent" would have rubber-stamped the whole set ABANDON.

**Two limits, both found by breaking the detector rather than trusting it:**

1. **D5's line filter hides short guards.** It scores lines ≥22 chars, so
   `[[ -e "$p" ]] || continue` (21 chars) — the *entire* mechanism of `e8261775` — was
   excluded. That patch scored 24% ("absent") while the decisive line sits on trunk at
   `ship-land.sh:348`. Re-running at ≥10 chars moved it to 25%: **line-fraction is a screen,
   never a verdict.** Every ruling below rests on locating the specific mechanism on trunk.
2. **D6 silently matched nothing on the first run** (wrong column — it was fed the trace
   field, not the subject). A zero-match result from a matcher is indistinguishable from
   "no matches exist", so it was positive-controlled by matching known-live subjects against
   themselves before being believed.

### 8.4 The ruling

| Class | N | Ruling | Basis |
|---|---|---|---|
| **LANDED** — landed on trunk under a rewritten patch-id | 31 | ABANDON | D6 exact subject on trunk; D5 40–100% |
| **SUPERSEDED** — the mechanism is on trunk, implemented differently | 15 | ABANDON | mechanism located on trunk, per patch (§8.5) |
| **IN-FLIGHT** — a live worktree branch carries the same work, further developed | 10 | ABANDON *here* | belongs to sweep item `35de32d78364`; all 7 covering worktrees verified present on disk |
| **RECOVER** — absent from trunk and from every live branch | **4** | **RECOVER** | §8.5 |

No patch was ruled from its score alone. The three that most look like drops but are not:

- `e8261775` "skip deleted paths in run_gate" (24%) — guard present, `ship-land.sh:348`.
- `bc5f7b84` "read the not-ok COUNT, not the exit code" (21%) — present,
  `ship-land.sh:265` (`notok="$(grep -c '^not ok' …)"`, then `if [[ "$notok" -gt 0 ]]`).
- `c1f17de0` "`--daemon-window` lane — no anchor" (0%, feature genuinely absent) — but trunk's
  `--window` **is** the anchor-free lane (`handoff-fire.sh:2161`: *"`--window` is SUPPOSED to
  open a fresh window — no firing-pane anchoring, by design"*). Two parallel fixes for one
  defect; `--window` won. Its dependents `693a2ccf` and `442995ba` (the `--daemon-window`
  caller and its test file) die with it.

The four postland-verify patches (`f17382df`, `6ba557e9`, `8e5480c4`, and the verdict half of
`7bdbbcda`) are one defect fixed four times in parallel. Trunk's landed form
(`postland-verify.sh:154-165`) is **deliberately stricter** than the orphans': it splits zero
`not ok` (⇒ truncated ⇒ CUT, non-verdict) from `not ok` without a diagnostic (⇒ a genuine red
that merely cannot be attributed). The orphans' "unattributed = signal-death" reading would
launder a real named failure into a non-verdict. Superseded *and* rejected on the merits.

### 8.5 RECOVER — the four, and how to recover them

| Patch | Files | Source commit | Why it is not covered anywhere |
|---|---|---|---|
| `f696dbbb` feat(install): install the python deps `bin/` imports | 4 | `6a5caea41` on `infra-green-v2` | Adds `requirements.txt` (deps enumerated with parsed `# import:` probe markers), `scripts/python-deps.sh` (probe/install, structured verdict token), `install.sh` wiring (global-only, warns never aborts), `tests/python-deps.bats`. Trunk has **no** `requirements.txt` and no pip path in `install.sh`. Trunk's `b6961d5` fixed only the *diagnosis* (cc-relogin now blames the dep instead of the browser); declare-and-install never landed. |
| `4a8b2b51` fix(activation): 12-mailbox-posttool → repo SSOT | 1 | `b52c3ac77` on `wt-d46bb5fbdb8f` | `~/.claude/autonomy/pending-activation/12-mailbox-posttool-activate.sh` exists live and is **byte-identical** to the patch; trunk's `docs/activation/pending-activation/` holds 01–11 but not 12. An operator artifact with no SSOT copy — lost if the live layer is. |
| `8030d997` fix(session-index): shellcheck directives | 2 | `ab66db8c7` on `park/gc-session-index` | The gate runs bare `shellcheck` (`ship-land.sh:355`) — no `-S`, so default severity `style`, everything blocks. Trunk's `hooks/lib/session-index-helpers.sh` yields **17** findings (SC2001, SC2034) and `hooks/session-index-sweep.sh` **6** (SC1090, SC2001). Any future land touching either file gates RED. Same latent-blocker class as `e8261775`, which the repo judged worth landing. |
| `aa7bcfed` docs(research): re-observe waiting-recycle | 1 | `3f348e3d1` on `cc/reobserve-waiting-recycle` | Records the disposition of backlog `f75a196e00dc` (verdict: healthy-DORMANT, a C3 reason-blind false positive) with its evidence. 22 sibling docs already on trunk in that directory; this rationale exists nowhere else. Prose-only ⇒ lint-only land. |

**Recover by cherry-pick, never by landing the branch.** `infra-green` also carries
`2caa48aa7` and `20ee3d0de` — both ruled SUPERSEDED — so landing it wholesale would re-land
two superseded patches into files trunk has already changed. `infra-green-v2` carries the same
`f696dbbb` content as its only orphan-exclusive patch and is the correct source.
`park/gc-session-index` carries 8 further patches that are covered elsewhere; take only
`ab66db8c7`.

```bash
# after the §8.6 preconditions land, from a dedicated worktree, ONE at a time:
git fetch origin --quiet
git cherry-pick 6a5caea41   # f696dbbb — python deps        (infra-green-v2)
git cherry-pick b52c3ac77   # 4a8b2b51 — activation SSOT     (wt-d46bb5fbdb8f)
git cherry-pick ab66db8c7   # 8030d997 — shellcheck directives (park/gc-session-index)
git cherry-pick 3f348e3d1   # aa7bcfed — research doc         (cc/reobserve-waiting-recycle)
# verify by CONTENT, never by commit count:
git ls-tree -r origin/main --name-only -- requirements.txt scripts/python-deps.sh \
  tests/python-deps.bats docs/activation/pending-activation/12-mailbox-posttool-activate.sh \
  hooks/lib/session-index-helpers.sh hooks/session-index-sweep.sh \
  docs/research/desk-audit-2026-07-18/reobserve-waiting-recycle.md
```

`f696dbbb` touches `install.sh`, a shared surface ⇒ FULL gate (`gate-select.sh` Rule 2). Land
it last and alone. Caveat on `8030d997`: it *suppresses* findings via directives rather than
fixing them — SC1090 (dynamic `source`) is legitimately a directive, but confirm the SC2034
unused-variable suppressions are not masking a real bug before landing.

### 8.6 The recoveries are PARKED — both preconditions are still absent from trunk

Re-verified file-by-file at `995dd96`, unchanged from §2 five commits later:

| Required fix | State on trunk |
|---|---|
| (B) admission control — defer on load | **ABSENT.** No `gate_admit` / `CC_GATE_MAX_LOAD` in `ship-land.sh`; `loadavg` is still only *recorded* into forensic JSON (`postland-verify.sh:71,142`; `ship-land.sh:289,320`). |
| (1) worktree-scoped `pkill` | **ABSENT.** `scripts/reaper-e2e.sh:24` is still `pkill -f "$LABEL"`, machine-wide. |

Both were **re-confirmed absent at `56ea34b`** immediately before this section landed — trunk
advanced 5 commits during the triage, so the parked state is asserted against the tree that
actually received it, not against the tree it was measured on. (The re-check needed a positive
control: `git show "$B:path"` silently fails under zsh, which parses `$B:` as a history
modifier and returns *"bad substitution"* — a grep count of 0 from that is a broken read, not
an absent feature. Braces (`"${B}:path"`) fix it.)

Both now exist on `fix/gate-runaway-loop`, which has grown 2 → **10 commits** and is
**worktree-attached** (`gate-runaway-loop`) — a live branch owned by `f8e40b4c577d`, carrying
`7b505de5` (admission control), `0c2d5b90` (worktree-scoped cleanup + a guard against the
unscoped form), `b868c6e0` (twice-cut ⇒ exit 9) and `6cee552b` (exit 75 LOCK-STARVED). Landing
another session's branch is the drop incident this repo's CLAUDE.md forbids — named for its
owner, not taken.

**And the loop is still running, harder than when §3 measured it:**

```
vm.loadavg     { 14.72 13.58 15.47 }
bats procs     97      ← §3 measured 78
ship-land runs 24      ← §3 measured 13, "concurrent, unserialized"
claude procs   39
```

(Counted by argv via `ps -Ao args=`. A first attempt with `pgrep -xc claude` returned **0**
while this session was itself running — `-x` matches the process *name*, not the argv. A
`pgrep` negative is not evidence of absence.)

So the ruling is recorded and the four landings wait. This section is prose-only and lands
lint-only (`gate-select.sh:121-125`), which is why the triage could complete while the sweep
it feeds cannot start.

### 8.7 Branch-level disposition

- **12 branches carry ≥1 RECOVER patch** — keep until recovered: `infra-green-v2`,
  `infra-green`, `wt-d46bb5fbdb8f`, `park/gc-session-index`, `cc/reobserve-waiting-recycle`,
  and the backup refs `ship/backup-{20ee3d0,3f348e3,6b554ca,7dd3af7,b52c3ac,preconverge,v2}`.
- **69 branches carry only ABANDON-class patches** — GC-eligible, **and not deleted here.**
  Per the item's own rail and §7's `⊆` caveat, a delete needs a re-verify immediately before
  it, because the set moves (it moved twice during this triage). The safe predicate for a
  `ship/backup-<sha>` ref is content-verify, not row count: every path it touches present on
  trunk *and* patch-equivalent-or-superseded. Nothing was bulk-landed and nothing was
  bulk-deleted, as the item requires.

**Adjacent gap found, not in scope, not fixed:** two more live activation scripts have no repo
SSOT copy — `05-ship-rail-push-allow-activate.sh` and `13-mailbox-gc-activate.sh` (both
present in `~/.claude/autonomy/pending-activation/`, absent from
`docs/activation/pending-activation/`, and carried by **no** branch in the orphan set, so
`4a8b2b51` does not cover them). `05-ship-rail-push-allow` is one of the three staged >24h and
un-run flagged at session start. Same loss-exposure class as `4a8b2b51`; needs its own item.

### 8.8 Appendix — the full 60-patch ruling

`%` = D5 substance-on-trunk. Read it as a screen, not a verdict (§8.3).

| Patch-id | Ruling | D5 | Subject |
|---|---|---|---|
| `4a8b2b51` | RECOVER | 0% | fix(activation): commit the orphaned 12-mailbox-posttool activation to the repo SSOT |
| `8030d997` | RECOVER | 0% | fix(session-index): shellcheck directives — the gate only lints files a land touch |
| `aa7bcfed` | RECOVER | 0% | docs(research): re-observe waiting-recycle — NOT inert (dormant not-armed; C3 reas |
| `f696dbbb` | RECOVER | 0% | feat(install): install the python deps bin/ imports — a missing websocket-client m |
| `8776b559` | SUPERSEDED | 0% | fix(reaper-horizon-lint): declare bin/cc-reconcile (jq-temp rm, not a reaper) |
| `c1f17de0` | SUPERSEDED | 0% | feat(handoff-fire): --daemon-window lane — fresh window via it2 python API, no anc |
| `7c62d033` | SUPERSEDED | 100% | chore(launchd): remove obsolete watch-getAppState-fix watcher + plist (T-P10-7) |
| `fc603db5` | SUPERSEDED | 11% | test(account-sweep): the lock-held fixture observes acquisition instead of guessing  |
| `2f9dc402` | SUPERSEDED | 20% | fix(tests): fixture $HOME in cc-relogin.bats — trunk was red on its own hermeticit |
| `442995ba` | SUPERSEDED | 20% | test(daemon-window): handoff-fire lane + desk-invariant heal/sweep/fail-reason |
| `bc5f7b84` | SUPERSEDED | 21% | fix(ship-land): the full gate must read the not-ok COUNT, not the exit code (K2) |
| `e8261775` | SUPERSEDED | 24% | fix(ship-land): skip deleted paths in run_gate so file-removal commits land green |
| `fe223af2` | SUPERSEDED | 26% | fix(cc-discover,cc-digest): reason-aware D9 inert-check — exclude healthy DORMANT  |
| `f17382df` | SUPERSEDED | 5% | fix(postland-verify): a killed run is not a verdict — stop stamping it red, perman |
| `693a2ccf` | SUPERSEDED | 62% | fix(desk-invariant): daemon-lane replacement fire — heal role, surface stderr, swe |
| `886352b5` | SUPERSEDED | 7% | fix(close): session-scoped rungs + vocabulary lint — 📦 never means live-on-orig |
| `2d41b6be` | SUPERSEDED | 8% | fix(orphan-reaper): never archive a live team on a stale leadSessionId |
| `6ba557e9` | SUPERSEDED | 9% | fix(postland-verify): unattributed RED is signal-death, not a test failure |
| `8e5480c4` | SUPERSEDED | 9% | fix(postland-verify): unattributed RED is signal-death, not a test failure |
| `39b0906e` | IN-FLIGHT | 16% | fix(tests): fixture $HOME in the two suites leaking into the live layer |
| `4cc9de1d` | IN-FLIGHT | 2% | fix(cc-notify): registry-direct resolution, honest rc, round-tripping listing |
| `51be8bba` | IN-FLIGHT | 2% | fix(ship-land): cut-twice is exit 9, and the gate takes an admission slot |
| `bf5b72c7` | IN-FLIGHT | 2% | fix(comms): bring NAME-keyed mailboxes under the fail-loud guard |
| `32605436` | IN-FLIGHT | 3% | fix(gate): signal-kill is a third state, and shed load before a full suite |
| `11e864eb` | IN-FLIGHT | 4% | fix(ship-land): signal-kill is a THIRD state, exit 9, never a gate red |
| `7bdbbcda` | IN-FLIGHT | 4% | fix(postland-verify): a non-verdict is never stamped, plus load admission |
| `7d387000` | IN-FLIGHT | 5% | feat(relogin): --relogin-status, class-C blocker row, log rotation |
| `b8d90d2e` | IN-FLIGHT | 5% | fix(cc-notify): accept the uuid prefix the lister actually prints |
| `f10128d1` | IN-FLIGHT | 7% | fix(gate): a named failure with no file is a RED — guard the boundary, keep the na |
| `2ce9edbc` | LANDED | 100% | feat(cc-idl): rotation-epoch chain — wire the sealer, end the permanent false TAMP |
| `59af5f63` | LANDED | 100% | docs(land-gate): live dogfood trace — zero-hold stale release + 14s fast-path land |
| `ba600fbe` | LANDED | 100% | docs(desk-24x7): cc-run Test B selftest de-flake — status entry + sibling flake fi |
| `c051dec8` | LANDED | 100% | feat(lint): fail-closed settings.json hook-wiring lint |
| `c4314ab0` | LANDED | 100% | fix(cc-dispatch): bound wave to MAX_SPAWN so an oversized backlog stops false-cliffi |
| `dc38c9c6` | LANDED | 100% | feat(desk): T-P11-6 desk-assert live wiring — resident rule runs the grounding gua |
| `916725cc` | LANDED | 40% | feat(handoff-fire): pre-fire account sweep — auto-heal + stranded-account bridge ( |
| `a90d06e2` | LANDED | 44% | fix(handoff-fire): back-channel trailer teaches the v2 inbox transport, not v1 keyst |
| `dfcc7e0e` | LANDED | 47% | feat(supervisor): page-target role-file fallback — empty CC_PAGE_TO reads cc-roles |
| `7a02c985` | LANDED | 62% | fix(handoff-fire): bracketed-paste + echo-verify launch injection (ttys018) |
| `5adaf8ef` | LANDED | 64% | fix(handoff-fire): bracketed-paste + echo-verify launch injection (ttys018) |
| `14dd1954` | LANDED | 77% | fix(handoff-fire): autonomous fires no longer steal OS focus (C1) |
| `8c21f942` | LANDED | 85% | fix(supervisor): idle-live STALL? oscillation — warm-transcript exemption + void k |
| `4d22f854` | LANDED | 90% | feat(ship-rail): T-P9-7 ship-land auto-rollback + bounded retry on verify-fail |
| `18af79e9` | LANDED | 91% | feat(activation): stage pending-activation queue (plan law #6) |
| `f03c4b7c` | LANDED | 94% | fix(supervisor): GC stale telemetry + pid-identity check — recycled/hung pids no l |
| `a2e57d1d` | LANDED | 95% | docs(research): 2026-07-25 shutdown-hardening — why Jul-23 missed it, the closer d |
| `6513dbd2` | LANDED | 96% | feat(close): operator-readout — silver-platter manual-steps block at Stop |
| `cf27a155` | LANDED | 97% | feat(escalation): limit-recover CC_UNATTENDED mode → class-B packet, not a block |
| `3bb5b24f` | LANDED | 98% | feat(comms): forward-chain + succession-migration primitives (D1) |
| `79bd2719` | LANDED | 98% | feat(cc-idl,cc-audit): T-P7-3 auditability floor — hash-chained IDL + four-zeros/D |
| `ad7c3cc5` | LANDED | 98% | feat(activation): 07-comms-drain — one runnable script wires the mailbox-drain hoo |
| `c93661a4` | LANDED | 98% | feat(desk): value ledger — cc-board VALUE column + fleet/account churn footer (T-P |
| `cd7f398a` | LANDED | 98% | fix(reaper): serialize sweeps with a single-instance lock |
| `d7d6dd21` | LANDED | 98% | feat(escalation): |
| `102ddcc1` | LANDED | 99% | docs(research): infra reliability audit — 15-agent wave, 4 systemic root causes |
| `29c76aed` | LANDED | 99% | fix(cc-classify): tenancy-bind fired stamps, hold-before-handoff, positive successor |
| `67f298ce` | LANDED | 99% | fix(lr-poller): require the isApiErrorMessage envelope before opening a spend packet |
| `80417f88` | LANDED | 99% | feat(recover): cc-recover-safeguard — re-fire a safeguard-blocked peer on a differ |
| `8f79bfaf` | LANDED | 99% | fix(tests): flake root-fixes — unguarded kill, e2e hoist, IDL pin, /tmp seam, stam |
| `df32e338` | LANDED | 99% | feat(gate-batching): T-P7-7 C1..C10 manifest + auto-stamp trailer + /ship backstop |

