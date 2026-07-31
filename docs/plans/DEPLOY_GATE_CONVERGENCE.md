---
status: open
created: 2026-07-31
owner: desk
---

# The deploy gate cannot converge — measured 2026-07-31

**Status:** OPEN · the live `~/.claude` layer has no working automatic deploy path.

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

1. **0 of 46 stamps are for a sha on trunk *at all*.** Not one, ever — every stamp is for a
   worktree/branch sha, never an `origin/main` ancestor.
2. **The only GREEN stamp is `2729a36a`, minted 2026-07-29 23:42** — off-trunk and >2 days old.
3. **`last-green` is a dangling pointer.** It reports `34e725d629ca`; **no stamp file with that
   name exists**. This is why `postland-verify status` reads healthier than reality, and it is a
   standalone bug worth fixing on its own (see §5).

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

Two code-writing tracks, no shared file:

| Track | Deliverable | Owns | Blocked by |
|---|---|---|---|
| **G1** | Gate predicate change (direction B unless costing says otherwise) + tests | `scripts/deploy-live.sh`, its bats suite | — |
| **G2** | `last-green` pointer integrity: verify-on-read or repair-on-GC + a red-proof test | `scripts/postland-verify.sh` (status + GC paths) | — |

**Rails:** dedicated worktree + own branch · gate green before commit · land ONLY via project-local
`/ship` · **C10 — never edit the launchd plists in place; stage an activation script.**

## 6. How to re-derive this in one command

```bash
for d in 1 3 7; do n=$(git rev-list --count --since="$d days ago" origin/main); \
  awk -v n="$n" -v d="$d" 'BEGIN{printf "%sd: %d commits = %.1f/hr, mean gap %.0f min\n",d,n,n/(d*24),(d*24*60)/n}'; done
grep -n 'POSTLAND_SUITE_TIMEOUT_S' scripts/postland-verify.sh
n=0; for f in ~/.claude/autonomy/postland/stamps/*.json; do s=$(basename "$f" .json); \
  git merge-base --is-ancestor "$s" origin/main 2>/dev/null && n=$((n+1)); done; echo "on-trunk stamps: $n"
```

If `on-trunk stamps` is still 0 and the rate still exceeds the bound, nothing has changed.
