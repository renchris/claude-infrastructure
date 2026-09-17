# T1 — Why commits in the SHARED checkout block the fleet-wide converge

Repo: `/Users/chrisren/Development/claude-infrastructure` (read-only; nothing changed).
Method note: every claim below is tagged **RAN** (I executed it, output quoted) or **READ**
(I read source/comment text). Comments are NOT executed — where a belief lives only in a
comment, it is labelled so.

---

## 0. THE ANSWER IN ONE PARAGRAPH

The converge is a `git merge --ff-only`. A commit made in the shared checkout puts an object on
live `HEAD` that trunk does not have, so `HEAD` stops being an ancestor of the target and the
fast-forward becomes *arithmetically impossible* — not slow, not degraded, **impossible**. The
lane's refusal is correct and deliberate: `deploy-live.sh` will never rebase or reset a shared
checkout, because an uncommitted/uncommitted-adjacent peer's work is indistinguishable from
yours. There **is** a sanctioned auto-clear arm (`diverged-superseded`) but it only fires when
every diverging commit is *already on trunk by content*, which is false for a commit that has
never been landed at all. So tonight's `145c32f53` sits in the one state with no automated exit:
genuinely unlanded, in a checkout the lane refuses to touch.

The root cause is **not** deploy-live. It is that the write is ungated: the fleet has a
PreToolUse guard against the ungated *advance* (`git merge`/`git pull`) in that directory, and
**no guard at all against `git commit`** there. I measured both arms (§2). Policy covers the
commit case in prose; prose does not execute.

---

## 1. THE EXACT DIVERGENCE CHECK IN `deploy-live.sh`

### 1.1 The gate (RAN + READ)

`scripts/deploy-live.sh:2393` — the whole thing turns on one ancestry test:

```bash
if ! g merge-base --is-ancestor "$HEAD_SHA" "$TARGET" >/dev/null 2>&1; then
```

Three outcomes below it, `scripts/deploy-live.sh:2394-2415`:

| # | Condition | Class | Line |
|---|---|---|---|
| A | `TARGET` is an ancestor of `HEAD` (live strictly AHEAD) | `ancestor-inverted` | :2395-2397 |
| B1 | diverged, **every** ahead-commit content-present on trunk | `diverged-superseded` | :2400-2401 |
| B2 | diverged, at least one ahead-commit genuinely unlanded | `diverged-unlanded` | :2403-2404 |

Tonight's refusal is **B2**, verbatim from `:2403`:

> `DIVERGED — the live checkout carries $DIV_N commit(s) that are not on ${TARGET:0:12} and are
> NOT present on it by content, so it cannot fast-forward. Dropping them would DESTROY work.
> This lane never rebases or resets a shared checkout; land them, then re-run.`

A second, independent divergence check exists at `scripts/deploy-live.sh:2543` on a different
path (`AHEAD=$(rev-list --count origin/main..HEAD)`; `[ "$AHEAD" -gt 0 ] && die "DIVERGED …"`).
Same doctrine, no auto-clear.

### 1.2 IS THERE A "DIVERGED but ALREADY LANDED" ARM? **Yes — and it cannot help here.** (READ)

`superseded_ahead()` at `scripts/deploy-live.sh:1583-1612` is a patch-id adjudicator. Per-commit
it computes `git show <c> | git patch-id --stable` and requires an exact match in the set of
patch-ids on `head..target`. rc 0 licenses the message at `:2400`, which hands the operator:

```
git -C $DEPLOY_REPO reset --keep origin/main
```

Note what that is and is not: **the script prints the command; it does not run it.** The
predicate's own header says so (`:1580-1582`, READ): *"This predicate never advances anything and
never mutates the checkout; it only decides WHICH sentence the operator is handed."* So even the
provably-safe arm is a **detector with no actuator** — the exact shape this repo's own memory
corpus names (`detector-with-no-owner-is-not-an-actuator`).

It is fail-closed in five ways (`:1584-1597`, READ): empty ahead-set, any merge commit, an empty
patch-id, either side above `CC_DEPLOY_SUPERSEDE_SCAN` (default 500), or one unmatched commit all
`return 1` → B2 wording.

### 1.3 Why B1 cannot fire for tonight's commit (RAN)

`145c32f53` adds 11 new files (4,249 insertions) that exist nowhere on trunk:

```
$ git cherry origin/main HEAD
+ 145c32f531398481f2fce2f5f1e23715f5b86b0d
$ git rev-list --count origin/main..HEAD
1
```

`+` = patch-id absent from trunk. `superseded_ahead()` returns 1 at the per-commit `hit` check
(`:1608`). Correctly so — dropping it would destroy 4,249 lines of research.

⚠️ **Caveat on `git cherry` as an instrument** (READ, repo memory `git-cherry-plus-is-not-absence-from-trunk`):
a `+` is *not* proof of absence — a rebased land changes the patch-id over comment context alone.
Here it is genuine absence because the files themselves are absent; I verified by content, not by
the `+`:

```
$ git ls-tree origin/main -- docs/research/union-alpha-drain-2026-09-17/   → (empty)
```

**Conviction that B2 is the correct classification tonight: 99%.**

### 1.4 The one mechanism that DOES auto-heal, for contrast (READ)

`scripts/deploy-live.sh:1620-1650` auto-repairs `core.bare=true` on the shared checkout without
asking — a precedent for the lane mutating shared state. Its stated justification (READ,
comment): *"core.bare has exactly one correct value on a checkout that has a working tree, so
this lane sets it rather than asking."* It has a kill switch (`CC_DEPLOY_BARE_REPAIR=off`) and
its discriminator is the *layout* (`$DEPLOY_REPO/.git` exists), never the flag. This is the
design template any divergence auto-rescue should follow (§4b).

---

## 2. POLICY vs MECHANISM — the gap, measured not asserted

### 2.1 What policy says (READ)

`.claude/CLAUDE.md` § *"Never commit or land in the shared checkout"* is unambiguous:

> `~/Development/claude-infrastructure` is the symlink source for `~/.claude` and frequently sits
> on another session's feature branch. … **Always work in a dedicated worktree, commit on your OWN
> branch, and land via the project-local `/ship`.**

It cites incident 2026-07-11 (`dfacccd`, 5 files silently dropped by a sibling land). This is
**prose in a memory file**. Prose advises; it does not execute.

### 2.2 What is MECHANICALLY enforced — I ran the hook on all three commands

There **is** a PreToolUse guard keyed on cwd == the shared checkout:
`hooks/validate-bash.sh:1203-1300`, the **FF-GATE** (`FFG_SHARED` at `:1251`).

**RAN** — fed real JSON to the real hook, `cwd` = the shared checkout:

| Command | Hook verdict | Evidence |
|---|---|---|
| `git commit -m test` | **NO OUTPUT — allowed** | hook emitted nothing |
| `git merge origin/main` | **`permissionDecision: "deny"`** | "Ungated advance of the SHARED CHECKOUT blocked" |
| `git pull --ff-only origin main` | **`permissionDecision: "deny"`** | same reason string |

🚨 **This is the whole answer to "why does this keep happening."** The fleet gated the *advance*
and left the *write* open. The gate's own scope comment says so explicitly (`:1233-1240`, READ):

> `· MECHANISM — merge/pull only. reset/checkout also appear in the reflog, but every innocent
> spelling of git reset outnumbers the guilty one and no predicate here separates them`

`commit` is **not mentioned anywhere in that scope note** — it was never considered, not
considered-and-rejected. The fast pass-through at `:1250` is `[[ "$CMD" == *merge* || "$CMD" ==
*pull* ]]`, so a `git commit` never even enters the block.

**Conviction that no PreToolUse guard denies `git commit` in the shared checkout: 97%.** (RAN the
live hook end-to-end; residual 3% is that some *other* hook in the chain, invoked by a different
matcher than the one I exercised, could deny it — I tested `validate-bash.sh` directly rather
than the whole registered chain.)

### 2.3 The git-side hooks do not cover it either (RAN + READ)

`.git/hooks/` holds `commit-msg`, `pre-commit`, `pre-merge-commit`, `pre-push`. `pre-commit` is
`cc-git-identity-gate` (`.git/hooks/pre-commit:1-30`, READ) — it gates the **author identity**,
not the **location**. Grepping it for `shared|SHARED|worktree|bare` returns exactly one hit, a
comment about worktrees sharing `.git/config`. No location predicate.

⚠️ And a git-side `pre-commit` hook is the *wrong layer* anyway: `~100` linked worktrees share
one `.git`, so `.git/hooks/pre-commit` runs for **every worktree too**. It cannot distinguish the
shared checkout from a sanctioned worktree without re-deriving cwd — and `$GIT_WORK_TREE`/`$PWD`
in a hook is derivable, so it is possible, just not what is installed today.

### 2.4 Post-hoc detectors exist; none is an actuator (READ)

`deploy-parity-assert.sh` third leg (`:755-830`, cited in the FF-GATE comment) scores an ungated
advance **after the fact**. `refusal_culprit()` (`deploy-live.sh:607, :693`) maps both divergence
classes to `checkout-diverged`. All of these *report*. The repo's own memory names this shape:
`detector-with-no-owner-is-not-an-actuator`.

---

## 3. HOW OFTEN — quantified, not asserted

### 3.1 Commits made directly in the shared checkout (RAN)

```
$ git reflog --date=iso | grep -c "commit:"
63
```

**63 commits** made in the shared checkout, reflog window **2026-08-12 → 2026-09-16** (36 days)
= **~1.75/day**. By date, the top days: 2026-09-13 (**15**), 2026-08-22 (8), 2026-09-08 (6),
2026-08-16 (6). Tonight's is the single 2026-09-16 entry.

⚠️ **This is a LOWER BOUND, and the reason matters**: the reflog's oldest entry is 2026-08-12
(`bc8327717 … merge origin/main: Fast-forward`) against a default 90-day `gc.reflogExpire`
(`git config --get gc.reflogExpire` → unset). So the window is truncated by something other than
expiry — the class may be older and larger than 36 days of data can show.

### 3.2 The manual cure, counted (RAN)

```
$ git reflog --date=iso | grep "reset:" | grep -c "moving to origin/main"
16
```

**16 `reset: moving to origin/main` entries** — that is the logging signature of the
`git reset --keep origin/main` cure the refusal prints. Someone ran the manual repair **16 times
in 36 days (~1 every 2.25 days)**. Clustered: 4 on 2026-09-13 alone, 3 within 60 seconds on
2026-08-24 (22:45:04, 22:45:46, 22:46:01 — a human retrying).

### 3.3 Refusals emitted by the unattended lane (RAN)

`~/.claude/autonomy/postland/deploy.log` is the launchd job's `StandardOutPath`
(`~/Library/LaunchAgents/com.claude.deploy-live.plist:57`). 6,170 lines; **45 DIVERGED refusals**:

| Class | Count |
|---|---|
| `DIVERGED —` (B2, unlanded) | 41 |
| `DIVERGED but ALREADY LANDED` (B1, superseded) | 4 |

🚨 **The log has NO TIMESTAMPS** — every line is `deploy-live: <msg>` with no clock. I dated the
episodes instead by extracting each refusal's **target sha** and running `git log -1 --format=%cI`
on it. 22 distinct targets:

| Date | Distinct targets | Note |
|---|---|---|
| 2026-08-23 | 1 | 6 refusals on one target |
| 2026-08-24 | 1 | superseded class |
| **2026-09-09** | **12** | 17:07:02 → 21:31:23 = **4h24m wedged** |
| 2026-09-10 | 5 | 15:06 → 20:11 = 5h05m |
| 2026-09-14 | 3 | incl. both superseded targets |

**Read the target count as DURATION, not as incidents.** A single stranded commit produces a new
target sha at every tick because trunk keeps moving underneath it. 12 distinct targets on
2026-09-09 = one wedge that survived 12 trunk advances.

### 3.4 🚨 Tonight's three refusals are in NO counted store — and that is structural (RAN + READ)

`grep -c DIVERGED` over the **last 200 lines** of `deploy.log` → **0**. Tonight's refusals are
absent. Two independent mechanisms suppress them:

1. **`refusal_bump()` returns before counting anything unless `AUTO=1` and `DRY_RUN=0`**
   (`deploy-live.sh:783-784`, READ):
   ```bash
   [ "$AUTO" -eq 1 ] || return 0
   [ "$DRY_RUN" -eq 0 ] || return 0
   ```
   A converge an **agent or operator** runs by hand moves no counter and never escalates.
2. **`$POSTLAND_DIR/deploy-refusals` does not exist** (RAN: `cat` → rc 1). The streak counter that
   feeds `REFUSE_MAX=6` / `REFUSE_COOLOFF=21600` (`:223-224`) has **never been written for this
   class**. So the escalation arm the `:2389` comment promises ("a divergence nobody clears
   becomes an EVENT instead of a silence") has, for the hand-run path, never fired.

**Implication:** the lead's "blocked at least 3 times today" is invisible to every store the
machine keeps. The true frequency is **higher than 45**; 45 is only the unattended lane's share.

### 3.5 The refusal is DELAYED, which is why it reads as sudden (RAN)

I ran the lane read-only and it did **not** reach the divergence check:

```
$ bash scripts/deploy-live.sh --dry-run --offline
deploy-live: waiting — no GREEN stamp among the newest 200 commits of origin/main …
  lag 3 commit(s) / 0h14m, inside the degrade budget (25 / 6h) — no advance, and none is due yet.
```

Forcing the advance decision reaches it exactly:

```
$ CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh --dry-run --offline
deploy-live: REFUSED — DIVERGED — the live checkout carries 1 commit(s) that are not on
  29a4918c3d4f and are NOT present on it by content …
```

So the failure mode is: **commit lands → lane silently "waits" for up to 6h / 25 commits → then
flips to a hard refusal that repeats every 10 min** (`StartInterval 600`,
`com.claude.deploy-live.plist`) **forever**. The quiet window is why nobody catches it at
commit time, and the repeat-forever tail is why it reads as "blocking all day".

### 3.6 SIDE EFFECT I CAUSED — and it is also a defect (RAN)

I must disclose a write. My `--dry-run` **created**
`~/.claude/autonomy/pages/deploy-diverged-unlanded.page` (mtime `Sep 17 00:03`, content epoch
`1789621434`, naming my run's target `29a4918c3d4f`). Its content is TRUE — the divergence is
real — but it should not have been written by a dry run.

Cause, `deploy-live.sh:2406-2413`: `refusal_bump` is `DRY_RUN`-gated, and the page write **four
lines below it is not**:
```bash
refusal_bump "$DIV_CLASS" "$DIV_MSG"      # ← returns early on DRY_RUN (:784)
mkdir -p "$PAGES_DIR" 2>/dev/null || true # ← unconditional
… } > "$PAGES_DIR/deploy-$DIV_CLASS.page"  # ← unconditional
```
This contradicts the lane's own dry-run contract, which prints `nothing mutated` (`:2419`) and
which the bare-repair block states as *"--dry-run/--offline never mutate"* (`:1643`, READ).
**Conviction this is a real (small) defect, not my misreading: 95%** — I read the gating and
observed the file appear with my run's target sha in it.

---

## 4. CANDIDATE FIXES — each with what it costs and what breaks

### Constraints any fix must satisfy (all RAN/READ this session)

| # | Constraint | Evidence |
|---|---|---|
| C1 | **The shared checkout is genuinely shared right now** — 2 of 9 live sessions are cwd'd in it | RAN: `cc-sessions --json \| jq '[.[]\|select(.cwd=="…/claude-infrastructure")]\|length'` → `2` |
| C2 | **Git authorship cannot attribute a commit to a session** — every commit on this box is `Chris Ren <ren.chris@outlook.com>`, enforced by `.git/hooks/pre-commit` | RAN: `git log -1 --format='%an <%ae>' 145c32f53` |
| C3 | **`.git/hooks/*` is shared by ~100 linked worktrees** — a git-side hook fires in worktrees too | READ: `.git/hooks/pre-commit:9` |
| C4 | **The desk session's cwd RESETS to the shared checkout** and cannot easily be in a worktree | READ: `~/.claude/autonomy/backlog.jsonl` — *"the hook-allowed bare `git push origin HEAD:main` is unreachable because the desk's cwd resets to the shared checkout, not a worktree"* |
| C5 | No rescue tooling exists today — `reset --keep` appears in exactly one tracked file, as a **printed string** | RAN: `grep -rln "reset --keep" scripts/ bin/` → `scripts/deploy-live.sh` only |
| C6 | No backlog row proposes a commit guard | RAN: targeted grep over `backlog.jsonl` → 0 hits |

---

### (a) PreToolUse hook that DENIES `git commit` when cwd == the shared checkout

**Where it goes:** `hooks/validate-bash.sh`, beside the FF-GATE at `:1203-1300`. The whole
apparatus already exists — `FFG_SHARED` (`:1251`), `_ffg_scan` (a positional argv walk that
already distinguishes a git *subcommand* from the same letters in a message), `_ffg_resolve`
(tilde/`-C`/`cd` resolution). Adding `commit` to the subcommand arm at `:1288` and the
pass-through at `:1250` is a **small, structurally-identical change**.

**Why this is the highest-value fix:** it is the only one that attacks the *cause*. Everything
else cleans up after 63 commits/36 days keep arriving.

**Conviction it would prevent the class: 92%.**

**What could go wrong — four named risks:**

1. 🚨 **It breaks the desk (C4).** This is the serious one. The desk's cwd *is* the shared
   checkout, and the backlog already records the desk unable to land. A hard deny on `git commit`
   there removes its last local write path. **Mitigation:** the deny's reason string must name the
   cure (`claude -w <name>`, or `git -C <worktree>`), and the gate needs the same `--force`-class
   escape hatch the FF-GATE advertises. Without an escape hatch this trades one wedge for another.
2. **Over-match on the word `commit`.** `git log --format=%H` is fine, but `git commit-tree`,
   `git log -S'commit'`, and a `-m` message containing the word are all near-misses. The FF-GATE
   solved exactly this by walking argv positionally rather than regexing — **reuse `_ffg_scan`,
   do not write a new matcher** (repo memory: `denylist-enumerates-spellings-not-the-class`).
3. **It cannot see the non-agent path.** The hook is `PreToolUse`; a commit typed by the operator
   in a plain terminal, or made by a script, never passes through it. So this reduces but does not
   eliminate — the FF-GATE's own comment concedes the same limit for its class (`:1216-1222`).
4. **Fail-open discipline must hold.** The FF-GATE fails open on any undecidable path (`:1243`).
   A commit gate that fails *closed* on an unresolvable cwd would block sessions in worktrees.

---

### (b) Auto-rescue lane: cherry-pick stranded commits onto a branch and land them

**Conviction this is safe to run unattended: 25% — I recommend against it as an actuator.**

**What could go wrong — and C1/C2 make these concrete, not hypothetical:**

1. 🚨 **The commit may belong to a LIVE peer still working (C1).** Two sessions are in that cwd
   *right now*. Landing a live peer's in-flight commit through your own `/ship` is, in this
   repo's own recorded words, *"not a rescue, it is a fork of their branch under a sha they will
   never see."* And C2 means **there is no field on the commit that says whose it is** — author is
   identical for all sessions.
2. 🚨 **Landing an equivalent copy does NOT clear the divergence.** This is the trap that makes
   (b) fail at its stated goal. `merge --ff-only` compares **ancestry**; a cherry-picked copy gets
   a new sha, so the original object is still on live `HEAD` and the lane still refuses. The repo
   memory records this being learned the hard way (*"I cherry-picked the stranded commit into my
   worktree and landed it; `deploy-live` still REFUSED"*). So (b) must **still** end in a
   `reset --keep`, which means it inherits every risk of (c) *plus* a land.
3. **A rebasing land rewrites the patch-id**, so after the land `git cherry` may still print `+`
   and `superseded_ahead()` may still return 1 — the auto-clear arm you were aiming for does not
   necessarily engage.
4. **It needs a gate run.** An auto-lane that lands must pass `/ship`'s full gate; under
   contention that is a 60-min unit inside a 10-min tick. Structurally it does not fit the
   launchd lane.

**Salvageable sub-variant (conviction 70%):** a **non-landing** rescue — `git branch
rescue/shared-<sha>` pointing at the stranded commit, then *surface* it. Costs nothing, destroys
nothing, makes the work recoverable, and needs no ownership judgment. But it does not unblock the
converge on its own.

---

### (c) Make the converge tolerate divergence safely

Two sub-variants with very different risk:

**(c1) Auto-run `reset --keep origin/main` in the `diverged-superseded` (B1) case only.**

This is the one I would actually build. B1 is already a *proof*: `superseded_ahead()`
(`deploy-live.sh:1583`) returns 0 only when **every** diverging commit is content-present on
trunk by patch-id, and it is fail-closed in five independent ways (`:1584-1608`). The script
already prints the exact command; it just declines to run it (`:1580-1582`, READ:
*"This predicate never advances anything and never mutates the checkout"*).

**There is direct precedent in the same file:** the `core.bare=true` auto-repair at `:1620-1650`
mutates the shared checkout without asking, justified as *"core.bare has exactly one correct
value on a checkout that has a working tree, so this lane sets it rather than asking"*, with a
kill switch (`CC_DEPLOY_BARE_REPAIR=off`) and a layout-based discriminator. **(c1) should be
built to that template**: `CC_DEPLOY_SUPERSEDE_CLEAR=off`, and the existing escalation arm
untouched so an *uncurable* divergence still pages.

**Measured payoff is real but modest: 4 of 45 refusals (8.9%)** were B1. It would have cleared
the 2026-08-24 and 2026-09-14 episodes and **would not have touched tonight's**.

**What could go wrong:**
- `reset --keep` refuses rather than clobbers when local changes would be overwritten — that is
  why it is the right verb (vs `--hard`). But it still moves `HEAD` **under two live sessions
  (C1)**, which can surprise a peer mid-`git status`.
- **The patch-id proof is about content, not about intent.** A peer may have deliberately
  committed a local-only variant that happens to match trunk's patch-id. Low probability; the
  five fail-closed arms bound it.

**(c2) Tolerate B2 (genuinely unlanded) divergence — e.g. deploy from a detached worktree of
trunk, leaving the shared checkout's HEAD alone.**

**Conviction this is the right long-term architecture: 60%. Conviction it is cheap: 15%.**
It dissolves the whole class — the live layer would stop caring what the shared checkout's HEAD
is. But `~/.claude` is a per-file **symlink farm into this checkout** (`.claude/CLAUDE.md`
§ Standing-converge), so the symlink targets *are* the shared working tree. Re-pointing them is a
fleet-wide change touching `install.sh`, `deploy-parity-assert.sh` and every consumer that
resolves a live path. This is a plan, not a patch.

---

### (d) The cheap complement nobody has built: make the wedge VISIBLE AT COMMIT TIME

Not on the lead's list, and it is the best cost/benefit after (a).

Today the sequence is: commit at 23:49 → lane says *"waiting … inside the degrade budget"* for up
to **6h / 25 commits** → then refuses every 10 min forever (§3.5). **Nothing tells the committing
session it has just frozen the fleet.** A `PostToolUse` (or Stop-hook) check — *cwd is the shared
checkout AND `rev-list --count origin/main..HEAD > 0`* — costs one `rev-list` and converts a
6-hour silent wedge into an immediate, attributable line in the session that caused it.

**What could go wrong:** it fires in worktrees too if cwd is not pinned; and it is advisory, so it
inherits `detector-with-no-owner` unless it lands in the session's own 🔧 ledger.

**Conviction it would have caught tonight's within one turn: 85%.**

---

### Recommended stack, in order

1. **(a)** commit-deny in the FF-GATE — *with* a desk escape hatch. Attacks the cause.
2. **(d)** commit-time visibility. Cheap, catches whatever (a) fails open on.
3. **(c1)** auto-clear the B1 class only, on the `core.bare` template. Small, provable, 8.9%.
4. **(b)** only as the non-landing `rescue/` branch variant. Never as an auto-lander.
5. **(c2)** file as a plan, not a patch.

---

## 5. ADVERSARIAL PASS — what I checked because I expected to be wrong

| Challenge | What I did | Result |
|---|---|---|
| *"You only tested one hook; another in the chain may deny commit."* | Enumerated the **registered** chain from `settings.json` (`jq .hooks.PreToolUse`) and ran **all 9** against `git commit` in the shared checkout | **None denies.** `smart-bash-allowlist.sh` returns `allow`; the other 8 emit nothing. Conviction 97% → **99%** |
| *"Maybe a git-side hook covers it."* | Read `.git/hooks/pre-commit`; grepped for `shared\|worktree\|bare` | Identity gate only; one worktree **comment**, no location predicate |
| *"Maybe commit-in-shared was considered and deliberately allowed."* | Read the FF-GATE scope note (`:1233-1240`); grepped `tests/validate-bash-ff-gate.bats` (18 cases) for `commit`; grepped backlog | `commit` appears in **none** of them. Not considered-and-rejected — **never considered** |
| *"`git cherry +` is not proof of absence"* (repo memory) | Verified by **content**: `git ls-tree origin/main -- docs/research/union-alpha-drain-2026-09-17/` | Empty → genuinely absent. B2 classification stands |
| *"Is the 45-refusal count the real frequency?"* | Found `deploy.log` is the launchd `StandardOutPath`; read `refusal_bump`'s `AUTO`/`DRY_RUN` guards; `cat deploy-refusals` | **45 is the unattended lane's share only.** Hand-run refusals are counted nowhere; the streak file has never been created. **45 is a floor** |
| *"Is the deploy.log dateable?"* | Checked line format — **no timestamps** | Had to date episodes by target-sha instead. Recorded as a limitation, not hidden |
| *"Does cherry-picking actually fix it?"* | Reasoned from `merge --ff-only` = ancestry + repo memory's recorded failure of exactly this | **No** — this is why (b) fails at its own goal. Load-bearing correction to the brief's option list |
| *"Is auto-rescue safe?"* | Counted live sessions in that cwd; checked whether authorship attributes | **2 of 9 live sessions share the cwd; author is identical for all.** Ownership is undecidable → (b) downgraded to 25% |

### Gaps I could NOT close — stated rather than papered over

- **Why the reflog starts 2026-08-12** with a 90-day default expiry is unexplained. If something
  truncated it, the 63/16 counts are floors by an unknown margin. **Not investigated further.**
- **I did not test the commit-deny fix.** (a)'s 92% is from reading `_ffg_scan`'s structure, not
  from building it. The desk-breakage risk (C4) is read from a backlog row, not reproduced.
- **`--offline` forces `DRY_RUN=1` at parse time** (VERIFIED: `deploy-live.sh:384`, `[ "$OFFLINE" -eq 1 ] && DRY_RUN=1`; the offline branch is `:1916`). Per repo memory it also does not fetch, so my lag
  reading of "3 commits" is a **lower bound**. It does not affect the divergence verdict, which is
  local-HEAD-vs-already-fetched-ref and cannot be cleared by a fetch of an unlanded commit.
- **I changed one file.** See §3.6 — my `--dry-run` wrote
  `~/.claude/autonomy/pages/deploy-diverged-unlanded.page`. Content is true; the write is a
  dry-run contract violation in `deploy-live.sh:2407-2413`. Disclosed, not concealed.

---

## 6. THE ONE-LINE ANSWER FOR THE LEAD

The converge is an ancestry test (`merge --ff-only`), so **any** commit in the shared checkout
makes it arithmetically impossible; `deploy-live.sh` has an auto-clear arm but it only covers the
*already-landed-by-content* case (4 of 45 refusals), and tonight's commit is genuinely unlanded so
no sanctioned path clears it. It keeps happening because **the fleet gated the advance
(`git merge`/`git pull` are DENIED by `hooks/validate-bash.sh:1251`) and left the write ungated
(`git commit` passes all 9 registered PreToolUse hooks)** — 63 such commits in 36 days, cured by
hand 16 times. The fix that attacks the cause is a `commit` arm in the existing FF-GATE, and it
must ship with a desk escape hatch (C4) or it will trade this wedge for a worse one.

---

## 7. CITATION AUDIT (ran last, on my own output)

I re-verified every `file:NNN` in this document against the tree. **Three were wrong** and are
corrected above:

| Cited | Actual | What it was |
|---|---|---|
| `validate-bash.sh:1249` | **`:1250`** | the `*merge*\|*pull*` pass-through |
| `deploy-live.sh:2421` | **`:2419`** | the `nothing mutated` dry-run line |
| `deploy-live.sh:1826` | **`:384` / `:1916`** | `--offline`; the original number came from **memory, not a read**, and pointed at unrelated residency-probe code |

The third is the instructive one: it was the single claim I sourced from the repo's memory corpus
rather than from a `sed -n` of the file. The *fact* (offline implies no fetch / dry-run) held; the
*address* did not. Everything else in this document was read or run directly.

**Overall conviction in the diagnosis (§0, §1, §2): 96%.**
**Conviction in the frequency figures (§3): 90%** — the counts are exact, but they are floors
(unattended lane only; truncated reflog window).
