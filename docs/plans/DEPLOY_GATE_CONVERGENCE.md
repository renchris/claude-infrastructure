---
status: open
created: 2026-07-31
owner: desk
---

# The deploy gate cannot converge — measured 2026-07-31

**Status:** OPEN · the live `~/.claude` layer has no working automatic deploy path.

> 🔁 **RE-DIAGNOSED later the same day — read §7 before acting on §1–§5.** The title's claim is
> wrong: the gate *can* converge and its predicate is correct. §2.1 and §2.3 are **withdrawn** —
> both came from testing a **tree** sha with a **commit** predicate (§6's command was vacuous and
> could only ever print `0`). The real cause is that the retry ladder ran in the corpus's
> **background clamp (PRI 4)**, where machine-pressure kills starve it into a permanent non-verdict.
> Fixed in `scripts/postland-verify.sh`; `deploy-live.sh` needed no change.

**Scope (frozen).** Record the measured proof that `deploy-live`'s green-stamp gate is structurally
unsatisfiable at this fleet's commit rate, so the next session fixes the *gate* instead of performing
a fourth manual sync. NOT in scope: implementing the fix (it redesigns a launchd-driven gate — C10).

---

## 1. The finding, in one line

**A verify cycle is bounded at 3 h; trunk advances a commit every ~7 min. The verifier can never
finish before its target is stale, so the gate never closes and the live layer never advances.**

| Quantity | Measured | Source |
|---|---|---|
| Trunk commit rate | **8.4/hr** (202 in 24 h · 962 in 7 d) ⇒ **mean gap 7 min** | `git rev-list --count --since` |
| Verify cycle bound | **10800 s = 3 h** (`POSTLAND_SUITE_TIMEOUT_S`, raised 2700→5400→10800) | `scripts/postland-verify.sh` |
| Trunk advance per cycle | **~25 commits** | 8.4/hr × 3 h |
| `deploy-live` tick | 600 s | `com.claude.deploy-live.plist` `StartInterval` |
| Corpus | 233 tree suites + 8 host suites | verifier's own run line |

**~25× inversion.** The design assumes verify-time ≪ commit-interval. It is 25× the other way.

## 2. Three independent confirmations it is not a blip

1. ~~**0 of 46 stamps are for a sha on trunk *at all*.**~~ **WITHDRAWN — §7.1.** The measurement
   was vacuous (tree sha tested with a commit-ancestry predicate). Corrected: **46 of 46 are on
   trunk.**
2. **The only GREEN stamp is `2729a36a`, minted 2026-07-29 23:42** — ✅ stands, with one correction:
   it is **not** off-trunk. `2729a36a` is the **tree** of on-trunk commit `34e725d629ca`.
3. ~~**`last-green` is a dangling pointer.**~~ **WITHDRAWN — §7.2.** `34e725d629ca` is a *commit*
   sha; the store is *tree*-keyed. Its stamp is `2729a36a8240.json`, which exists and is green.
   The pointer was correct; only the **rendering** was wrong (that part is real — fixed, §7.5).

**Consequence, measured:** live HEAD `ec92e68c` (08:03) vs trunk `79867781` (16:01) — **8 h and 120
commits behind**, and `deploy.log` is a wall of:

```
REFUSED — no GREEN stamp among the newest 200 commits of origin/main
REFUSED — target 34e725d629ca is not a descendant of live HEAD — this would ROLL BACK the live layer
```

Both refusals are *correct behaviour* for the predicate as written. The predicate is the defect.

## 3. Why this got worse without anyone changing it

`LAND_PIPELINE_V2` deliberately moved the full-suite claim **off** the land path onto this background
verifier, because P(green) for the monolith on the land path measured **2.3%**. That fixed landing —
lands are now 20-40 s. But it handed the verifier a 233-suite job and then ran it under
`ProcessType Background`, whose **4-84× band tax** is already documented in this repo
(`bound-must-fit-the-band-not-the-bench`). Nothing re-checked whether the *gate* could still close at
the fleet's commit rate afterwards. It cannot.

**This is the same defect behind backlog #71 / #72 / #25** ("break the deploy-live bootstrap
deadlock", "deploy-lag platter"). Those are not recurring bad luck; each manual sync buys hours
before the same structural condition reopens.

## 4. The only mechanism that currently works

A surgical single-file checkout, done by hand, per file:

```bash
cd ~/Development/claude-infrastructure
git status --porcelain -- <path>          # MUST be empty — else it is a peer's live WIP
git fetch origin main
git checkout origin/main -- <path>        # updates the working tree; HEAD unmoved
```

Used 2026-07-31 to get a **desktop-leak fix** into `skills/demo-recording/SKILL.md` while the shared
checkout was 119 behind with 4 live sessions writing in it. It self-resolves on the eventual
fast-forward (staged content already equals trunk). **It is a workaround, not a deploy path** — it
does not scale and every use is an un-audited partial deploy.

## 5. Fix directions — measure before building any of them

| # | Direction | Why it might work | Risk |
|---|---|---|---|
| **A** | **Gate on absence-of-RED for an ancestor**, not presence-of-GREEN for a recent sha | Achievable at 8.4 commits/hr; a red is a *positive* finding the verifier does produce | Weaker claim — deploys unproven trees, which is exactly what V2 moved away from |
| **B** | **Stamp the newest verified ANCESTOR and let deploy advance to it** | Decouples "what got verified" from "what is head"; converges by construction | Live layer trails by one cycle — acceptable if the trail is bounded and visible |
| **C** | **Attack the band tax** — foreground the verifier, or partition the corpus | The bound was sized from foreground timing; the tax is the whole inversion | Foregrounding a 233-suite corpus on a box that already crashed twice in 48 h |

**B is the most likely correct answer** and should be costed first: it is the only one that makes the
gate converge *without* weakening the claim (A) or raising machine risk (C).

**Independent of all three — fix the dangling `last-green` pointer.** A status surface reporting a
GC'd record as current is how this went unnoticed: I read `last-green: 34e725d6` as evidence of
health, when no such stamp exists. Either repair the pointer on GC or make `status` verify the file
before printing it. *(Same class as this repo's `claimed-outcome-vs-checked-outcome`.)*

## Phase 0 — Agent Team Orchestration (for whoever implements)

> **SUPERSEDED 2026-07-31 by §7.** Both tracks below rested on §2.1/§2.3, which are withdrawn.
> **G1 requires no change at all** (`deploy-live.sh`'s predicate is correct — §7.3), so there is no
> second independent code track and no team: the whole fix lands in `scripts/postland-verify.sh`.
> Kept here as the historical record of what was planned and why it was dropped.

Two code-writing tracks, no shared file:

| Track | Deliverable | Owns | Blocked by |
|---|---|---|---|
| **G1** | ~~Gate predicate change (direction B unless costing says otherwise) + tests~~ **NO-OP — §7.4** | `scripts/deploy-live.sh`, its bats suite | — |
| **G2** | `last-green` pointer integrity ~~verify-on-read or repair-on-GC~~ → **rendering**, + a red-proof test | `scripts/postland-verify.sh` (status + GC paths) | — |

**Rails:** dedicated worktree + own branch · gate green before commit · land ONLY via project-local
`/ship` · **C10 — never edit the launchd plists in place; stage an activation script.**

---

## 7. CORRECTION — re-measured 2026-07-31, later the same day

**The gate is not structurally unsatisfiable. It is correctly refusing a genuinely RED corpus, and
the corpus is red because the retry ladder is starved into non-verdicts by the band it runs in.**

Every number below was re-derived on the live host; §6's command was repaired first (it could not
have confirmed anything — see the warning there).

### 7.1 All 46 stamps are on trunk

Stamps are keyed by **tree** sha. The withdrawn check tested them with `merge-base --is-ancestor`,
a **commit** predicate, which exits 128 for every tree — including the tip's own tree as a positive
control. Tree-identity against `rev-list --format=%T` gives **46/46 on trunk, 1 green**.

### 7.2 `last-green` was never dangling

`last-green` = commit `34e725d629ca` → tree `2729a36a8240` → `stamps/2729a36a8240.json` exists,
`"verdict":"green"`. The doc looked for `stamps/34e725d629ca.json` — a commit name in a tree-keyed
store. **Real defect, narrower than claimed:** `status` printed the bare commit sha, which is what
made that inference available. Fixed by rendering the hop and verifying the file (§7.5).

### 7.3 The 3 h bound is not the binding constraint

`deploy-live` never required a stamp at the tip — it scans the newest `CC_DEPLOY_SCAN=200` commits
(≈24 h of headroom at 8.4/hr) and takes the first green. Measured on the live host:

| Fact | Value | Consequence |
|---|---|---|
| newest stamp `e047ff36` scan position | **87** of 200 | inside the window |
| `e047ff36` vs live HEAD `ec92e68c` | **descendant** | no rollback refusal |
| corpus wall time | **197 suites in 1994 s (33 min)** | the bound is 5.4× the corpus |

⇒ **A GREEN at `e047ff36` would have fast-forwarded the live layer immediately.** Lag is designed
for. The 3 h+ run times are the **retry ladder** (8–30 retries × up to `RETRY_TO=5400 s`), not
corpus size — so "verify-time ≫ commit-interval" was never the mechanism.

### 7.4 What actually blocks it: the red set CHURNS

| Measurement | Value |
|---|---|
| verdicts across 46 stamps | **42 red · 2 cut · 1 hung · 1 green** |
| failing-set size, last 4 red stamps | 8 · 6 · 3 · 7 |
| **intersection** of those 4 sets | **1** |
| union of those 4 sets | 16 |
| distinct suites ever named failing | **38** |

And the suites do not reproduce. Re-run individually on this host:

- `backup-prune-identity.bats` — in **all four** recent red sets — passes **green** under both the
  session PATH and the exact launchd PATH.
- `cc-close-attrib.bats` — red under the session PATH, **green** under the launchd PATH. Opposite
  direction, so "launchd PATH causes the reds" is also wrong.
- Of the 7 suites in the newest red stamp, **none** is red in both environments.

⇒ These are **machine-state-coupled tests on a box that never goes quiet** (load 12–31, 4+ live
sessions). The failures are facts about the machine, not the tree.

**Why the ladder cannot clear them — the root cause.** `retry_once` ran the re-run in
`"${QOS[@]}"`, the **corpus's background clamp (PRI 4)**. The ladder's premise is "a re-run under a
CHANGED environment discriminates a real failure from an environmental one", but de-prioritising
does not de-contend — it moves the environment the **wrong way** for the dominant failure mode.
This file's own evidence: **34 of 35 flake rows are pressure kills** (`exit 143` ×8, `exit 137` ×3)
at median loadavg 13.9. Starved at PRI 4 the ladder cannot render a verdict, and since those kills
correctly **abstain**, every run takes the cut path and **no green is ever claimable**.

This is the **third** instance of one oversight. The prelints were moved background→utility for
exactly this reason (2.9 s utility vs 41 s background @ load 14.8); the actuators before them
(`2514226e`, 84–89×). The ladder was missed both times.

### 7.5 Fix landed — `scripts/postland-verify.sh` only

| # | Change | Why it converges |
|---|---|---|
| 1 | **`RETRY_QOS` = utility band** (`nice -n 5` + `taskpolicy -c utility`), used by both `retry_once` paths | Measured PRI **20 vs 4**. The ladder can render a verdict again. Corpus stays background — this is *not* "foreground the verifier" (direction C's risk): only a seconds-long, single-named-test decision procedure moves. Nor does it weaken the claim (direction A's risk): a test that fails at utility still convicts, 2-of-3 still convicts. |
| 2 | **`suites` denominator in the stamp** | A verdict without its population size is unauditable — clearing the one green of being a collapsed-corpus run required cross-reading `runner.log`, which rotates on a different schedule than the stamps it explains. |
| 3 | **`status` renders `last-green` through to its tree-keyed stamp**, verifying the file (`MISSING` / `UNRESOLVABLE` / verdict off disk) | Removes the inference that produced §2.3 — and §7.2's defect could not be caught by any test, because nothing asserted the rendering. |

**No plist edit (C10 holds). `deploy-live.sh` unchanged.** Tests: `C24` band (with a control on the
instrument — the same reader at PRI 4 — so a pass cannot be vacuous) · `C24` empty-array fallback ·
`C4b` denominator · `C9b` rendering + GC'd-stamp `MISSING`.

### 7.6 Re-cost of §5's three directions

| # | Verdict |
|---|---|
| **A** gate on absence-of-RED | **Rejected.** There is always a red, and some reds are genuine — this deploys unproven trees for no convergence gain. |
| **B** stamp the newest verified ancestor | **Provable no-op**, and it was the doc's favourite. The newest ancestor **is** already stamped, on trunk, inside the scan window, and a descendant of live HEAD (§7.3). It is simply **red**. Stamping ancestors cannot manufacture a green. |
| **C** attack the band tax | **Right target, wrong prescription.** Contention *is* the defect, but "foreground a 233-suite corpus" is the risk §5 correctly flagged. §7.5 #1 is the surgical form: move the **ladder** (seconds), not the corpus (hours). |

### 7.7 Landing the fix does NOT deploy it — the bootstrap circle, and the one hand-step

`~/.claude/scripts/postland-verify.sh` is a **symlink into the shared checkout's WORKING TREE**:

```
~/.claude/scripts/postland-verify.sh -> ~/Development/claude-infrastructure/scripts/postland-verify.sh
```

So "the live verifier" is whatever that working tree holds — currently **122 commits behind trunk**.
The fix is therefore *not live merely by being landed*, and it cannot become live by the normal path:

```
live layer advances  ⇐ deploy-live fast-forwards ⇐ a GREEN stamp exists
a GREEN stamp exists ⇐ the ladder renders a verdict ⇐ THE FIX IS LIVE
```

A closed loop — the same shape as this repo's `deployed-layer-bootstrap-circle`, and it must be
broken **from the deploy side, once, by hand.**

**Staged:** `docs/activation/pending-activation/26-deploy-gate-unblock-activate.sh` (C10 — agent
stages, operator runs; `CONFIRM=1`). It surgically checks out **one file** to trunk's version. HEAD
is not moved, nothing is committed or stashed, **no plist is touched.** Fail-closed: it refuses if
the fix is not on trunk (verified by **content**, never a commit count) and refuses if the file is
dirty in the shared checkout (that would be a peer session's WIP). Idempotent — re-running once the
live path already carries the marker is a no-op.

> **Do not "tidy up" by unstaging that file.** `git checkout <ref> -- <path>` stages as well as
> writes, and that is load-bearing: an *unstaged* modification is a local change that
> `merge --ff-only` **refuses to advance over**, which would block the very fast-forward this
> unblocks. Staged (index == worktree == trunk) is the state that self-resolves — the eventual
> fast-forward absorbs it silently.

**Why an operator step and not an agent one:** the shared checkout has 4+ live sessions sharing one
git index, so a sibling's bare `git commit` can sweep a staged file. Only a human can pick a moment
that is safe; the script is re-runnable if one goes wrong.

### 7.8 Known-open after this fix

The fix restores the ladder's ability to *decide*. It does **not** make a machine-coupled test
hermetic — a test asserting `load >= ceiling` behaviour (e.g. `gate-home-isolation.bats` "a SHED
smoke ... makes no clone") is coupled by construction and can still convict on a loaded box. Per
this script's own settled policy (`postland-verify.sh` §PATH, 2026-07-29) that is **a bug in the
suite, not an environment to fake**. Expect a residual tail; triage with
`flakes.jsonl` (`1-of-3` = already acquitted) before touching any suite.

## 6. How to re-derive this in one command

```bash
for d in 1 3 7; do n=$(git rev-list --count --since="$d days ago" origin/main); \
  awk -v n="$n" -v d="$d" 'BEGIN{printf "%sd: %d commits = %.1f/hr, mean gap %.0f min\n",d,n,n/(d*24),(d*24*60)/n}'; done
grep -n 'POSTLAND_SUITE_TIMEOUT_S' scripts/postland-verify.sh
# stamps are keyed by TREE sha, so the on-trunk test is tree-identity, NOT commit ancestry:
git rev-list origin/main --pretty=format:'%T %H' --no-commit-header > /tmp/trunk-trees.txt
n=0; g=0; for f in ~/.claude/autonomy/postland/stamps/*.json; do t=$(basename "$f" .json); \
  grep -q "^$t " /tmp/trunk-trees.txt || continue; n=$((n+1)); \
  grep -q '"verdict":"green"' "$f" && g=$((g+1)); done
echo "on-trunk stamps: $n   of which GREEN: $g"
```

> ⚠️ **The command that stood here until 2026-07-31 was VACUOUS** — it ran
> `git merge-base --is-ancestor "$s" origin/main` where `$s` is a stamp basename. Stamp basenames are
> **tree** shas and `--is-ancestor` takes **commits**, so it exits **128 (`not a valid commit name`)
> for every input**, including a positive control (the tip's own tree). It could not return anything
> but `on-trunk stamps: 0`. That non-verdict was read as a finding and became §2.1 and §5 below.
> **See §7 — the diagnosis those claims support does not survive the corrected measurement.**
