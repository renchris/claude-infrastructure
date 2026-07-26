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
  §4 excludes it.
- **The scan is a point-in-time snapshot** (`origin/main` = `1f19ac0`). Re-run §5 before
  acting; do not hand these numbers forward as fact. The exposure moved twice *during* this
  measurement (290 → 342 raw in an hour; contention 78 → 105 bats procs in ~15 min).
