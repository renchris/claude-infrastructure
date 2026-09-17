# T2 — What makes an agent's commit reach trunk without a human, and where the chain breaks

Repo: `/Users/chrisren/Development/claude-infrastructure` @ `145c32f53` (main). READ-ONLY session; no
`/ship`, no push, no `deploy-live` was run. Every number below is RAN unless marked READ.

---

## §0 ANSWER (the chain, and its one real break)

The unattended-land chain is **fully authorized and fully mechanized in this repo**. Nothing in it
requires a human. It breaks in exactly one place, and that place is not a permission gate — it is a
**throughput failure in `ship-land.sh`'s optimistic re-round loop**, which is conditional on the
round being slow, and slow rounds co-occur with a busy trunk.

```
agent finishes work          →  Follow-On Gate F1-F4 (global CLAUDE.md)         [no human]
commit on own branch         →  Standing-land authorization (.claude/CLAUDE.md) [no human]
📦 rung computed             →  wrap-ledger.sh                                  [no human]
Stop hook refuses to idle    →  session-continue.sh SHIP FLOOR                  [no human]
/ship → ship-land.sh         →  optimistic round → land-lock → CAS → push       [🚨 BREAKS HERE]
landed                       →  Standing-converge authorization → deploy-live   [no human]
```

---

## §1 What an agent may already land unattended, and what still needs a human

READ `.claude/CLAUDE.md` § Standing-land authorization (lines 15-27) and § Standing-converge
authorization (28-63); global `CLAUDE.md` § Session Close Protocol ship-policy table.

| Step | Authorized unattended? | Citation |
|---|---|---|
| Commit on own branch | YES, proactively, one per logical task | global CLAUDE.md § Git Commit Workflow |
| Land via **project-local `/ship`** | **YES — the 📦-offer/wait cycle is explicitly WAIVED in this repo** | `.claude/CLAUDE.md:17-19` "lands via the project-local `/ship` flow **without a fresh ask**" |
| Bare `git push` | **NO — never** | `.claude/CLAUDE.md:22-24` "exclusively for the fail-closed project-local `/ship` — never a bare `git push`" |
| Converge to the live layer | **YES, degraded tier** `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` | `.claude/CLAUDE.md:35-37` |
| `deploy-live --force` | **NO — operator's escape hatch** | `.claude/CLAUDE.md:39-49` |
| `git merge --ff-only` in the shared checkout | **NO — hook-denied** | `.claude/CLAUDE.md:51-55`, `hooks/validate-bash.sh:1352` |
| Committing IN the shared checkout | **NO** | `.claude/CLAUDE.md:5-13` |
| A land whose escalation-scan trips (destructive SQL / credentials) | **NO — parks a decision packet, exit 3** | `scripts/ship-land.sh:41-43` |

**So: nothing in the authorization layer requires a human for an ordinary green land in this repo.**
The ship-policy table's "ASK only where landing spends money" arm does not fire here — landing is
free in claude-infrastructure. The human-required set is narrow and correct: force-converge,
bare push, shared-checkout writes, and escalation-scan trips.

The rule is also **scoped deliberately**: `.claude/CLAUDE.md:20-22` gives the reason — this repo IS
the `~/.claude` symlink source, so a parked commit leaves the live layer stale. That is a
repo-specific fact, and the global file's ship-policy table names no repo on purpose.

---

## §2 The livelock — measured, and sharper than the folklore

### The shape (READ, `scripts/ship-land.sh:40-78`)

```
optimistic rounds, up to SHIP_LAND_GATE_ROUNDS (default 3), each:
  UNLOCKED: fetch → rebase → GATE on the rebased tree → record GATE_BASE/GATE_HEAD
  → land-lock'd child: last-moment fetch → CAS: origin/main == GATE_BASE AND HEAD == GATE_HEAD?
      NO ⇒ release lock, exit 42 (INTERNAL stale-gate) and the OUTER loop re-rebases + re-gates
      YES ⇒ push → land-verify (in the lock) → release
rounds exhausted ⇒ in-lock re-gate of STATICS ONLY (SHIP_LAND_GATE_ROUNDS=0 goes straight there)
```
Round loop: `scripts/ship-land.sh:4986` (`ROUNDS="${SHIP_LAND_GATE_ROUNDS:-3}"`), fallback at 5020,
fallback-mode branch at 4512.

The file already carries the corrected cost model at lines 74-89 (READ): the re-round's cost is
`gate_arms_s` (p50 137s / p90 783s / p99 2842s), not the two cheap terms an earlier reading named —
"every clause audited true and the total was wrong by three orders of magnitude".

### Trunk's real gap distribution (RAN)

`git log --format=%cI origin/main --since="24 hours ago"` → 60 commits, 106 gaps computed from `%ct`:

| Window | n gaps | p50 | p90 | p95 | max | gaps ≥60min |
|---|---|---|---|---|---|---|
| Last 24h | 106 | **5.0 min** | 23.6 min | 35.9 min | 451.6 min | 2 |
| Busy 8h (16:00-23:59) | 45 | **5.0 min** | 15.0 min | — | **30.1 min** | **0** |

Hourly rate (RAN): 16 commits at 16:00, 12 at 17:00, 11 at 23:00; a 7h overnight hole (03:00-09:00)
is the single 451-min gap and is the ONLY reason the 24h figures look survivable.

### Round duration, from the lander's own ledger (RAN, `~/.claude/land.log`, 130 ship-land rows since 2026-09-16)

`gate_s` (the unlocked round): **p50 178s · p75 683s · p90 1251s · p99 4136s · max 5133s**.
`gate_arms_s` p50 142s / p90 300s / max 3121s. `gate_statics_s` p50 0s / p90 1s — the in-lock
fallback really is free. `smoke_s` p90 900s.

### The livelock probability (RAN — length-biased renewal, `P = E[max(0,G−D)]/E[G]`)

Convolving the REAL `gate_s` distribution against the REAL gap distribution:

| Round duration | P(clean round), busy regime | P(all 3 rounds stale) |
|---|---|---|
| p50, 178s | 0.691 | **0.030** |
| p90, 1251s (21 min) | 0.056 | **0.841** |
| max, 5133s (85 min) | 0.000 | **1.000** |
| marginal over the whole `gate_s` distribution | 0.555 | 0.088 |

**This refines, and partly corrects, the resident memory rule** (`[Optimistic round cannot outrun
its contention]`), which reads "probability ~0 of ever completing". That is true of a **60-min
round** — in the busy 8h window the maximum gap is 30.1 min, so `P(clean) = 0.0000` exactly, which
is what tonight's 3h/3-round land was. It is NOT true of the median land: at `gate_s` p50 the loop
completes 97% of the time. **The livelock is a TAIL property, not a mode property.**

🚨 **And the independence assumption UNDERSTATES it.** A slow round and a busy trunk are not
independent draws — both are driven by the same variable (concurrent writers: 127 worktrees, see
§4). The 0.088 marginal figure is a floor; the conditional figure that matters is the 0.841 at p90,
because a land is slow precisely when trunk is fast.

### Observed re-round rate (RAN, same ledger)

24 of 130 rows are `exit:42` stale-gate re-rounds = **18.5%**, matching the header's stated 17.7%.
`gate_rounds` on the 106 land-stage rows: 0→11, 1→79, 2→15, 3→1. Eleven lands already ran with
**zero** optimistic rounds — the escape hatch is in routine use, not exotic.

Other exits today: `0`→60, `6`→22 (gate RED — a verdict about the diff, not contention), `143`→9
(killed), `11`→7 (a second land from one worktree while the first is in flight).

---

## §3 Are the escape-hatch env vars safe? YES here, NO in 4 sibling worktrees

**The scrub exists** — `scripts/ship-land.sh:2048-2056` (RAN, `grep -n`):

```
  ${pre[@]+"${pre[@]}"} \
  env -u SHIP_LAND_GATE_ROUNDS -u SHIP_LAND_VERIFY_RETRIES -u SHIP_LAND_GATE_SCOPE \
      -u LAND_LOCK_WAIT -u LAND_LOCK_TTL \
      -u SHIP_LAND_LANE -u SHIP_LAND_SMOKE_BUDGET_S -u SHIP_LAND_TIMEOUT_BIN \
      ... CC_GATE_MAX_LOAD=0 CC_BATS_MAX_ROOTS=0 ... bats "$@" </dev/null
```

so `SHIP_LAND_GATE_ROUNDS=0` and a raised `LAND_LOCK_WAIT` cannot reach the bats subprocesses that
assert on them. The hazard is real and documented at `scripts/ship-land.sh:1914` (READ): a
46/46 `tests/ship-land.bats` degrades to 45/1 then 7 failures under an un-scrubbed inherit.

Note the adjacent trap at 2041-2047 (READ): a comment between the `\` continuation and `env` ENDS
the continuation and silently un-wraps the timeout/nice prefix. Do not edit that block.

**The per-worktree claim is STILL TRUE, and I measured it rather than assumed it** (RAN, loop over
`git worktree list`):

- 124 of 127 worktrees carry a `scripts/ship-land.sh`.
- **4 of 124 (3.2%) lack the scrub.**

| Worktree | HEAD date |
|---|---|
| `.worktrees/permission-beacon` | 2026-07-19 |
| `.worktrees/wt-02ba4e52389a` | 2026-07-25 |
| `.worktrees/wt-63929c8d6072` | 2026-07-25 |
| `.worktrees/wt-6cab0ab3cb2f` | 2026-07-25 |

The scrub landed **`cd08189b6`, 2026-07-26T06:10:42-07:00** (RAN, `git log -S`), so all four were
cut **before** it — exactly the mechanism the memory rule names, confirmed by date rather than by
inference. All four are ≥7 weeks stale on branches nothing is driving; the residual is small but
nonzero, and the honest form is "a worktree cut before 2026-07-26 carries the trap", which is a
criterion, not a list.

---

## §4 How much is stranded right now

Raw counts are useless here and I say so rather than quoting them: `2,799` local branches, `2,657`
ahead of trunk by **ancestry**, `8,130` commits ahead. That figure is ~99% artifact — `2,352` of the
branches are `ship/backup-*`, which are **ship-land's own preflight safety refs** (`ship-land.sh:44`
"safety backup ref"), and a rebasing land changes patch-id so ancient branches read ahead forever
(resident rule `[cherry + ≠ absence]`).

**The honest denominator** (RAN): branches whose tip moved in the **last 7 days**, excluding
`ship/*` — 83 candidates, of which **19 are ahead by ancestry (37 commits)**. Content-narrowed with
`git cherry origin/main <branch>`:

| Branch | `+` unlanded | `-` already on trunk |
|---|---|---|
| `claude/fire-20260912T010855Z-86683-1` | **6** | 0 |
| `fix/rm-gate-ephemeral-temp` | 2 | 2 |
| `kpanic-defense` | 2 | 0 |
| `fix/effort-parity-reads-legacy-knob` | 1 | 4 |
| `research/kernel-panic-2026-09-16`, `research/codex-vs-claude-200`, `fix/untracked-dodref`, `fix/kitty-one-draggable-title`, `fix/kitty-menu-close-anchor`, `docs/panic-clang-format-swarm` | 1 each | 0 |
| 6 × `claude/fire-*` | 0 | 1-4 each (already landed) |

**37 ancestry → 17 by patch-id.** Content-verified the top three with `git diff --stat origin/main...`:

- `claude/fire-…-86683-1` — **6 files, 1,071 insertions, 0 deletions** (drain-circuit W11 + 17 test cases). Nothing of it is on trunk.
- `kpanic-defense` — **8 files, 1,789 insertions** (panic-quarantine feature + a 420-line bats suite).
- `fix/rm-gate-ephemeral-temp` — **4 files, 299 insertions** (validate-bash mktemp category + site-inventory re-pin).

≈ **3,159 lines of genuinely absent, gate-relevant work** on three branches alone. Two of them are
already named in the resident corpus as re-land items, still stranded.

🚨 **And NONE of it can be nudged.** RAN `bin/cc-sessions --json`: **9 live sessions**, cwd's are
`claude-infrastructure` (×2) and `fde-endpoint-business-case` (×7). **Zero live sessions in
`wt-kpanic-defense`, `rmgate-widen`, `wt-effort-parity-fix`**, and `claude/fire-…-86683-1` has **no
worktree at all**. See §5 for why that is terminal.

*(A full-corpus `git cherry` over all 2,799 branches was started and had not finished at write time;
the 7-day scoped figure above is the one I stand behind, and is the better denominator regardless.)*

---

## §5 What "land automatically when gates are green" would look like — and which arm already pushes

### The four Stop-hook arms, and their actual disposition (RAN)

`hooks/session-continue.sh:1109` gives the order: **mechanical 🔧 → ship floor → wake floor**, at
most one emitting per Stop. Plus `completion-assert.sh` (blocks a false done) and `cc-custody`
(folds into 🔧 via `wrap-ledger.sh:994-1014`).

| Arm | Pushes toward auto-land? | Measured (all-time, `~/.claude/logs/session-continue.log`, 14,261 rows since 2026-07-25) |
|---|---|---|
| **Ship floor** (`session-continue.sh:1005-1101`) | **YES — it IS the actuator.** Blocks the stop with "📦 SHIP FLOOR … /ship it (auto-fire by default)" | **189 FIRED.** Abstentions: `not-mine` 415 · `assignee` 169 · `latched` 64 · `budget` 49 · `teardown` 36 · `kill-switch` 26 |
| **Mechanical 🔧** | Indirectly — forces commit, which is the floor's precondition | 159 `fired continue` in the last 48h |
| **completion-assert** | Blocks a false ✅ over a 📦 ledger; `commands/ship.md:42` "stop here" once *disarmed* it (`:193-196`) | Negative only — refutes, never actuates |
| **custody** | Makes ✅ unreachable over an unreturned wave | Orthogonal to landing |
| **`wrap-ledger.sh`** | Computes the 📦 rung: `UNLANDED=0; { [ "$AHEAD" -gt 0 ] || [ "$CHERRY" -eq 1 ]; } && UNLANDED=1` (`:537`), `RUNG="📦"` (`:1798-1803`) | The sensor, not an actuator |

### 🚨 The terminal break: there is NO scheduled lander, and the only actuator is session-scoped

RAN: no launchd plist in `~/Library/LaunchAgents/` or the repo's `launchd/` names `ship-land`;
`scripts/autonomy-sweep.sh` has no land lane (its 4 `ship-land` hits are all prose about cost).
`stranded-sweep` is explicitly **"REVIEW-only advisory (exit 1 is a prompt, not a verdict)"** —
`ship-land.sh:61`, `:1374` — and "never auto-recovered".

So **every land on this box requires a live session at a Stop**. And the ship floor is gated on
`session_unlanded_mine` (`:1053-1056`) — it fires only over commits **THIS session wrote**, and
abstains on ignorance rather than nudging over a sibling's work. That gate is **correct** (it is
the #105 sibling-dirt lesson applied to commits) and it is exactly why:

> **Ship-floor fires on 2026-09-16: 0. On 2026-09-17: 0.** Last fire: 2026-09-15 (1 event).
> Meanwhile 17 commits / ~3,159 lines sit unlanded with no live session owning any of them.

**The moment a session ends, its unlanded commits become permanently un-nudgeable.** No arm
attributes them to anyone, no sweep lands them, and the worktree is the only thing that remembers.
That is the chain's real break — not the authorization layer, and not even the livelock.

### What auto-land would have to be

1. **A repo-scoped lander lane**, not a session-scoped floor — keyed on the BRANCH + its gate
   verdict, so an author's death does not orphan the commit. `stranded-sweep` already **detects**
   this set (it reports only commits whose paths are ALL absent from trunk) and is deliberately
   advisory; making it an actuator is the smallest real change.
2. It must **default to `SHIP_LAND_GATE_ROUNDS=0`** on the unattended path. Measured (§2): the
   in-lock statics re-gate costs `gate_statics_s` p50 **0s** / p90 **1s**, so the optimistic rounds
   buy nothing unattended and cost the 84%-at-p90 livelock. Rounds are a foreground-latency
   optimization; an unattended lander has no latency to optimize.
3. It must **not** relax attribution for exit 6. Of 130 attempts since 2026-09-16, **22 were exit 6**
   (gate RED) — nearly as many as the 24 stale-gate re-rounds. `ship-land.sh`'s rc-6 contract is
   "a named `not ok` in a direct suite is a VERDICT about your diff: fix it, do not retry unchanged."
   An auto-lander that retried those would loop forever on real defects.
4. `exit 11` ×7 today (a second land from one worktree while the first is in flight) means the lane
   needs per-worktree serialization it does not have today.

---

## §6 Adversarial pass — what a hostile reviewer would say I missed

1. **"Your livelock math assumes independence."** Conceded and investigated: it does, and that makes
   0.088 a FLOOR. A slow round and a busy trunk share one driver (concurrent writers). The
   conditional figure — 0.841 at `gate_s` p90 — is the operative one.
2. **"You measured 24h; the memory rule measured 4h."** Checked. Segmenting recovers the rule's
   regime: in the busy 8h the max gap is **30.1 min** and `P(clean | D=60min) = 0.0000` exactly.
   The 24h view's survivability is entirely the 451-min overnight hole. Both readings are right
   about their window; neither generalizes without naming it.
3. **"Is the livelock even the dominant failure?"** Checked, and it is NOT the largest single bucket:
   exit 0 → 60, exit **6** (gate red) → 22, exit **42** (stale gate) → 24, exit 143 (killed) → 9,
   exit 11 → 7. Contention and genuine reds are the same order of magnitude. I lead with the
   livelock because the brief asked, but the honest ranking puts real gate reds beside it.
4. **"The scrub might be present but not REACHED."** Checked the adjacent trap the file itself
   documents (`:2041-2047`): a comment between the `\` and `env` ends the continuation. The
   continuation is intact at HEAD.
5. **"Are the four unscrubbed worktrees actually a risk?"** Measured their HEAD dates (2026-07-19 to
   2026-07-25) against the scrub's landing (`cd08189b6`, 2026-07-26). All predate it, confirming the
   mechanism by date rather than inference. All are ≥7 weeks stale with no live session — the
   residual is real but dormant.
6. **"You said the authorization layer needs no human — did you check the escalation scan?"** Yes:
   `ship-land.sh:41-43`, a destructive-SQL/credentials hit PARKS a decision packet and exits 3,
   never auto-lands. That is the one authorization-layer human gate, and it is correct.

## §7 Conviction

- **The chain is fully authorized unattended in this repo** — 97%. Direct quotes from both files.
- **The livelock is real and tail-conditional (not mode-conditional)** — 90%. Renewal math on
  measured gaps + the lander's own 130-row ledger; the correction to "probability ~0" is well
  supported, the independence caveat is stated.
- **The scrub exists at HEAD and 4/124 sibling worktrees still carry the trap** — 98%. Direct grep
  over every worktree, dated against the scrub's landing commit.
- **No scheduled lander exists; the ship floor is the only actuator and is session-scoped** — 93%.
  Negative evidence (no plist, no sweep lane) is bounded by where I looked: launchd agents, the
  repo's `launchd/`, and `autonomy-sweep.sh`. A lander hiding in a cron I did not enumerate would
  refute it.
- **Dead-session commits are permanently un-nudgeable** — 88%. Follows from `session_unlanded_mine`
  + 0 live sessions in those worktrees + 0 ship-floor fires in 48h. Inferred from the gate's code
  path rather than from a fired/abstained record naming those specific shas.

---

## §8 ADDENDUM — full-corpus `git cherry` completed (closes the §4 gap)

The background job flagged as unfinished in §4 has now completed (exit 0). **All 2,799 local
branches, `git cherry origin/main <branch>`:**

- **1,760 branches carry ≥1 `+` commit · 2,408 commits total.**
- Ancestry said 8,130. Patch-id narrows it to 2,408 — a **70% reduction**, which is the measure of
  how much "ahead" is rebase artifact.

### 🚨 Three quarters of the corpus-wide "stranding" is the LANDER'S OWN undo buffer

Decomposed by branch class (RAN):

| Commits | Branches | Class |
|---|---|---|
| **1,801 (74.8%)** | 1,489 | `ship/backup-*` — ship-land's preflight safety refs |
| **206** | 138 | `claude/fire-*` — dispatched peers |
| 70 | 17 | `wt-*` — dispatch worktrees |
| 68 / 53 / 42 | 8 / 20 / 9 | `tm/*` · `fix/*` · `feat/*` |
| ~168 | ~79 | everything else (`gate/`, `w4/`, `superseded/`, `park/`, …) |

`ship/backup-*` is created at `scripts/ship-land.sh:4966-4968` (`git branch -f
"ship/backup-$(git rev-parse --short HEAD)" HEAD`) **before the optimistic rounds**, and is
discharged only by `post_release_finish` → `ship-backup-reap.sh reap "$SHIP_LAND_BACKUP_REF"
"$LANDED_HEAD"` (`:1493-1494`) — i.e. **on the SUCCESS path only**. A land that exits 42 / 6 / 143 /
11 leaves its ref behind permanently. Age of the 2,350 such refs (RAN): `≤1d: 32 · 1-7d: 105 ·
7-30d: 755 · >30d: 1,458`.

So **the backup-ref population is a standing proxy for the lander's failure history**, and it is the
single largest term in any naive stranding count. Anyone quoting "2,408 unlanded commits" is
quoting the lander's crash-safety buffer back at itself. *(I stop short of asserting every one of
the 2,350 is a failure — the reap declines on a non-ancestor ref for legitimate reasons too; what
is directly readable is that the reap sits on the success path.)*

### The genuine agent stranding, and why it corroborates §5

Excluding lander-owned refs (`ship/backup-*` + `backup/*`): **≈586 commits across ≈260 branches**,
and the **largest single genuine class is `claude/fire-*` — 206 commits across 138 branches.**

That is precisely the population §5 identified as structurally un-nudgeable: a dispatched peer's
session **always** ends, by construction, so `session_unlanded_mine` can never attribute its commits
to any live session again. The corpus-wide decomposition independently lands on the same class the
ship-floor analysis predicted would accumulate. I did not look for this; it fell out of the split.

### What I will NOT quote, and why

Content-absence on OLD branches is confounded and I tried it rather than assuming: sampling the
10 largest non-backup branches, `tm/growth` shows 120 differing files / 7,414 insertions but only
20 files absent from trunk, while `wt-8532922cce46` shows 427 files / 71,471 insertions and just
**2** absent. Those branches are hundreds of commits behind trunk; a file-absence proxy over them
measures branch age, not stranding. The correct instrument already exists and is cited in the
lander's own header (`ship-land.sh:1489`): **stranded-sweep reports only a commit whose paths are
ALL absent from trunk.** It is advisory-only (`:61`, `:1374`), which is §5's point exactly.

**So the defensible ladder is:** 8,130 (ancestry) → 2,408 (patch-id) → ~586 (non-lander) →
**17 verified genuinely-absent commits / ~3,159 lines in the last 7 days** (§4, content-verified).
Each step down is a real instrument correction, and only the last one is content-proven.

**Conviction on §8:** 92% for the decomposition (direct `git cherry` + `git for-each-ref`, arithmetic
only); 80% for "the `claude/fire-*` class is the dominant genuine stranding" — the class split is
measured, but its content-absence is not verified branch-by-branch, and a `stranded-sweep --all`
run (not performed: read-only session, and it re-fetches) is what would settle it.
