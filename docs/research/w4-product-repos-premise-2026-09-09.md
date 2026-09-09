# W4 "the operator's actual products" — three of four premises refuted, one driven

**Date:** 2026-09-09 · **Item:** cc-backlog `79e7c3cb7357` (condition `master-product-repos`)
**Roadmap:** `docs/plans/MASTER_PRODUCT_REPOS.md` · **Filed:** 2026-08-12T11:59:19Z, 27 days before this read.

This is the disproof the item's own PREMISE CHECK asks for. It is written back into the store as a
sibling row naming `79e7c3cb7357`, and the item is closed citing it.

## The headline was never true, and the technical premise was cured before the item was written

The item's motivating sentence — inherited from the parent plan — is:

> reso took **0 commits in 7 days** while claude-infrastructure took 884. *The infrastructure had
> become the work.*

Measured on `origin/main` of `reso-management-app`:

| Window | Claim | Measured |
|---|---|---|
| The 7 days **before the item was filed** (2026-08-05 → 2026-08-12T11:59:19Z) | 0 commits | **328 commits** |
| The 7 days **before this read** (2026-09-02 → 2026-09-09) | — | **140 commits** |
| Longest gap between consecutive trunk commits since 2026-06-01 | ≥7 days | **6.24 days** (149.8 h) |

There is no 7-day window on reso's trunk since June with zero commits — the quietest calendar week
(2026-W29) carried 7, and the busiest (W34) carried 743. The premise is not stale; **it was never
true of trunk.** Commits-per-week since 2026-06: 1, 463, 620, 656, 384, 468, 84, 7, 40, 145, 343,
165, 743, 288, 108, 33.

The second premise — *"pnpm lint RED on origin/main (122 import-x errors) blocks every land"* — is
**dead, and was already dead when the item was filed.**

```
$ cd <clean worktree at origin/main dec92dd1b> && pnpm lint
✖ 5 problems (0 errors, 5 warnings)          exit 0
$ grep -oE "import-x/[a-z-]+" <lint output> | sort | uniq -c
(no matches)
```

The cure is **`7f1259b31` "fix(lint): 122 errors across 96 files were one unresolved Panda alias"** —
an ancestor of `origin/main`, and note that its subject carries the item's own number, 122. Its
commit timestamps against the filing time:

| Event | Timestamp (UTC) |
|---|---|
| cure authored | 2026-08-12T03:18:36Z |
| cure committed | 2026-08-12T03:20:18Z |
| **item filed** | **2026-08-12T11:59:19Z** |

The item was filed **8 h 39 min after its central blocker was fixed**, with **18 further commits**
already on trunk in between. It was stale at birth and has been re-dispatched on that premise for 27
days. The cure's own body explains why the number was so large and so cheap to fix: `styled-system/*`
is a tsconfig paths alias, import-x had no TypeScript resolver, fell back to node resolution and
reported "Missing file extension" 122 times across 96 files — **one cause, not 122 defects.**

The third premise — *"Amplify/Fly prod split-brain"* (roadmap wave **R3**) — is also discharged, and
the repo's own tool asserts it from the live APIs rather than from prose. Run this turn from a clean
trunk worktree:

```
$ bash scripts/land-status.sh
✓ decoupling: Amplify auto-build on main is OFF — landing bills nothing.
✓ decoupling: Path F watches refs/heads/release — landing ships no Fly release.
✓ deploy: production is at the trunk tip.
```

Two deploy paths exist but they are **decoupled, not split**: `main` triggers nothing, `refs/heads/release`
ships Fly, and production is at the trunk tip. This also settles the ship-policy question the brief
raises — **landing in reso bills nothing today**, so reso is *not* a repo whose own CLAUDE.md puts it
on the "landing spends money" side of the global table.

## What is actually left: 41 of 59 members are already done

| Project | done | blocked | open |
|---|---|---|---|
| reso-management-app (+ `reso`, `reso-qa-runner`) | 36 | 9 | 0 |
| doc_classifier | 5 | 9 | 1 |
| other | 1 | 0 | 0 |

The item's "58 rows" is now 18 non-done rows, and **18 of the 19 are `blocked`** — i.e. parked on an
operator step, not on agent work. The reso rows in particular are **not stale**: their `needs` fields
were re-measured on 2026-09-07 and already carry corrected reasons (the "landing bills a deploy"
premise was retracted there two days ago; the live blockers are a `docs/research/` `BANNED_PATH_PREFIXES`
governance rule, a superseded choreography, and a genuine landing-range escalation).

**Where the item's fourth premise survives, in a weaker form.** "4 branches hold 87+ unlanded commits"
is directionally live but understates the drift: `cc-135842-3950` is 11 ahead / **1792 behind** trunk
and `cc-225947-27025` is 39 ahead / **1671 behind**. These are design/preview branches whose landing
is a substantial rebase over ~27 days of divergence, not a tail — and one of them carries a commit
titled `wip(preview): … halted mid-flight`. They are correctly parked.

## The one live defect — and its remedy had rotted

`doc_classifier` was the half the item told a worker to do **first** ("work the authorization holes
FIRST"), and that premise is **LIVE**. On trunk today:

```
$ git show origin/main:reviewapp/api/routers/run.py | grep -c require_loopback_client
0
```

An unauthenticated remote caller can still `POST /api/run/start` and get a 200 that spawns the whole
run-all spine via `subprocess.Popen`, plus 6 read routes and `/api/capabilities`. The fix has been
written and gate-green **since 2026-08-08** and has never landed.

**The reason it never landed is the finding.** Four rows (`35cae65a8d2d`, `e3d8a8cf90a4`,
`8c7f7ae4ee4d`, and the already-`done` `39d8431abae5`) publish an operator command marked *"Do not
vary it"*:

```
git checkout main && git merge --ff-only wt-35cae65a8d2d && git merge wt-769c22b99fec && make ci && git push origin main
```

That command is **dead**. Trunk moved `cc6a30a6 → ae9f2075 → 31dc8809` after the rows were written, so
every one of the five fix branches is now 2 commits behind and `--ff-only` refuses:

```
$ git merge --ff-only wt-35cae65a8d2d
hint: Diverging branches can't be fast-forwarded, you need to either: ...
```

An operator who pasted the published command got a failure at step one and landed nothing. This is
`symptom-vs-remedy-rot` with the polarity that costs the most: **the symptom is alive and the remedy
is dead**, so the row keeps demanding action while the action it names cannot work.

Worse, the rows' own history shows this is the **fourth** occurrence — the target was re-pointed on
2026-08-08 ("merge target changed AGAIN, same stranding reason"), and twice before that. Each
re-point froze a new sha, and the next trunk move killed it again.

### What was driven

- Rebased all 9 commits (3 run-plane loopback + 6 untrusted-input contract fixes) onto current trunk
  as **`w4-runplane-security-rebased`** — cherry-picked, zero conflicts (verified: no file overlap
  between either branch set and the 2 new trunk commits). Peer branches were **not** rewritten.
- Gate re-run on that exact tree: **`make ci` exit 0 — 4655 passed / 5 skipped, 95.20% coverage.**
  (First run was red with 65 `Cannot find … "fastapi"` errors — an incomplete install in a fresh
  worktree, not a defect in the diff. The repo ships `make sync` with the canonical four-group list;
  `uv sync --frozen` alone is not it. Instrument controlled before the diff was indicted.)
- **Pushed the branch to origin** so the work is no longer visible only to this machine. `ahead=9,
  behind=0`, `git merge-base --is-ancestor origin/main w4-runplane-security-rebased` passes.
- Re-armed the three blocked rows with a **runnable** `--run`, replacing the frozen-sha command with
  a script that **recomputes** the fast-forward: `~/Development/doc_classifier/.local/land-runplane.sh`
  (durable + gitignored). It fetches, rebases the branch onto trunk if trunk has moved again, runs
  the full gate on the exact tree that will land, asserts the guard is present, gates the single
  irreversible push behind a typed `yes`, and verifies by reading `origin/main` back afterwards.

**The generalizable rule** — and the reason this doc exists rather than a fifth re-point: *a handover
that names a frozen sha rots every time trunk moves; one that names the invariant plus the command
that recomputes it does not.* This is the same shape as the ship-policy table's refusal to name a
repo, and as the `docs/rules` entry on replacing a number with the criterion that re-measures it.

## Residual, stated honestly

- **`doc_classifier` landing stays operator-owned.** That repo has **no `CLAUDE.md` and no `/ship`
  rail** (no `.claude/commands/`), and its `.githooks/pre-push` gates a `main` push on `make ci`.
  With no sanctioned rail, an agent landing there would be a bare push, which global Git Safety
  forbids. The prohibition is structural, not a stale premise — but it now sits behind a command
  that works.
- **`39d8431abae5` reads `done` while the hole is open.** It is latched `done` in the ledger, yet the
  DoD it names (`grep -c require_loopback_client` ≥ 1 on `origin/main`) prints 0. That is a false-done
  of exactly the class the row was originally filed to flag. Not reopened here (reopening an
  operator-gated row re-cycles it); recorded so the next reader is not misled by it.
- **`wt-90eed49dd55c`** (S4 CH-S DI body-identity fix) was deliberately **not** folded in: it conflicts
  with the 2 new trunk commits on generated golden fixtures and `uv.lock`, and it depends on an
  unlanded peer commit `211c94a5`. Resolving that means regenerating golden data, where a silent
  wrong resolution is worse than a delay.
- **`scripts/land-status.sh` looked absent and was not.** A first read of the reso *working checkout*
  reported no such file; that checkout is **1816 commits behind trunk**. Reading `origin/main` found
  it. A stale checkout answers "absent" for a file that exists, and it answers in only one direction.
