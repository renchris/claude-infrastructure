# E — LANDED ⇒ LIVE: mechanism, lag, atomicity, verify-at-HEAD

All measurements taken **2026-08-10 01:19–01:29 PDT** on the live host. Every number below is
followed by the command that produced it. Repo/`~/.claude` treated read-only; the only executions
were `deploy-parity-assert.sh` (pure-`printf`, verified at scripts/deploy-parity-assert.sh:346,366-371),
`wrap-ledger.sh --machine` (declared pure-read, scripts/wrap-ledger.sh:117-120), and
`deploy-live.sh --dry-run --offline` (`--offline` forces `DRY_RUN=1` at scripts/deploy-live.sh:110).

---

## 1 · Mechanism map — how a landed commit becomes LIVE

### 1.1 The live layer's shape

| Live path | Kind | Evidence |
|---|---|---|
| `~/.claude/{hooks,commands,scripts,bin}` | **real dirs of per-file symlinks** into `~/Development/claude-infrastructure` | `find ~/.claude/<d> -maxdepth 1 -type l \| wc -l` → hooks 72 · commands 19 · scripts 148 · bin 90; `-type f` → 0/0/0/2 |
| `~/.claude/skills/<name>/` | real dir; **SKILL.md is the symlink** | `ls -ld ~/.claude/skills/agent-teams{,/SKILL.md}` — dir is `drwx`, `SKILL.md` is `lrwx→ …/skills/agent-teams/SKILL.md` |
| `~/.claude/{agents,lib}` | real dirs of per-file symlinks | `ls -l ~/.claude/lib` → 4 symlinks + 1 `.prelink-bak` real file |
| `~/.claude/CLAUDE.md` | **real file, NOT a symlink** | `ls -l ~/.claude/CLAUDE.md` → `-rw-------  59116  Aug 10 00:35` |
| `~/Library/LaunchAgents/*.plist` | **copies**, not links | install.sh:670 `for plist in "$REPO_DIR"/launchd/*.plist` under `copy_file`; deploy-live.sh:740 names launchd a COPY class |

Consequence, and it is the whole mechanism: **content goes live when the live CHECKOUT's working
tree advances**, because the symlinks point at working-tree paths. Nothing needs to copy bytes.

### 1.2 The three advance paths (only one is gated)

| # | Trigger | Actuator | Gate in front of the fast-forward |
|---|---|---|---|
| **A** | launchd `com.claude.deploy-live`, `StartInterval 600`, `RunAtLoad true` (launchd/com.claude.deploy-live.plist:41-45) | `deploy-live.sh --auto` → `g merge --ff-only "$TARGET"` (scripts/deploy-live.sh:707) | **Full T1/T2/T3 ladder** (deploy-live.sh:19-32, 507-609) |
| **B** | an **agent session typing `git pull --ff-only -q origin main`** in the shared root checkout | git itself | **NONE** |
| **C** | `scripts/deploy-now.sh:77` `git merge --ff-only origin/main` (operator entrypoint `~/.claude/DEPLOY-NOW.sh`) | git itself | **NONE** (it *reports* newly-added unlinked files, deploy-now.sh:16-21, and never links them) |

Path B is **not hypothetical and not a script** — it is agents. Verbatim tool call, session
`d3b1290e`, 2026-08-10T06:54:43Z (that session produced live HEAD `d52c3a94`, "fix(cc-offload)"):

```
cd /Users/chrisren/Development/claude-infrastructure
git pull --ff-only -q origin main 2>&1 | tail -2
ln -sfn …/bin/cc-offload ~/.claude/bin/cc-offload
```
(`grep -rn 'ff-only -q' ~/.claude/projects/…` — no tracked script in `scripts/ hooks/ bin/ commands/`
contains that string; `git grep -n -- '--ff-only'` returns only comments plus deploy-live.sh:707 and
deploy-now.sh:77.)

**Measured mix, last 200 HEAD reflog entries** (`git reflog show HEAD -n 200 | sed 's/.*}: //' | cut -d: -f1 | sort | uniq -c | sort -rn`):

```
42 commit · 32 merge origin/main · 14 reset · 11 rebase (pick) · 7 rebase (start) ·
 6 rebase (finish) · 4 pull --ff-only -q origin main · 4 checkout · 3 pull -q --rebase ·
 2 pull --ff-only · 16 × "merge <sha>: Fast-forward"  ← the ONLY sanctioned shape
```

`merge <resolved-sha>` is the discriminator deploy-parity-assert.sh:436-451 uses, and it is sound:
deploy-live resolves TARGET with `rev-parse` before merging, so a sanctioned advance always reflogs
a hex object name; every ungated path names a ref or is not a merge.

### 1.3 The `--auto` tick, in execution order

| Step | file:line | Runs when the advance is REFUSED? |
|---|---|---|
| `link_refresh` — repairs missing per-file symlinks | deploy-live.sh:324-358, called **unconditionally** at :418 | **YES** (this is the ADD remedy) |
| `migrations_converge` (pre-fetch) | :402-413, called at :419 | **YES** |
| `g fetch origin main` | :452 | yes (skipped only under `--offline`) |
| lag measured on BOTH axes (`LAG_COMMITS`, `LAG_HOURS`) | :464-480 | yes |
| **target selection T1 → T2 → T3** | :507-609 | — |
| at-tip early exit (`LAG_COMMITS == 0`) | :558-562 | — |
| already-deployed early exit (`TARGET == HEAD`) | :634-639 | — |
| anti-rollback: TARGET must be a descendant of live HEAD | :648-649 | — |
| dirty-tree pre-flight, names the blocking path | :670-684 (`merge_blockers` :367-380) | — |
| **`git merge --ff-only "$TARGET"`** | :707 | no |
| `install.sh` (the ONLY full relink) | :733-751 | **no** |
| `migrations_converge` (post-advance) | :756 | **no** |
| `host_checks "$TARGET"` (manifest suites vs the live layer) | :207-289, called :759 | **no** |

Damping in front of the page, not the merge: `damp_ok` keyed on the refusal REASON, window
`CC_DEPLOY_DAMP_S` default 86400s (deploy-live.sh:129-143, 614); cleared on every healthy outcome
(:559, :637, :762).

### 1.4 postland-verify's role

- launchd `com.claude.postland-verify`, `StartInterval 300`, `RunAtLoad false`
  (launchd/com.claude.postland-verify.plist). State now: `not running`, `runs = 105`, `last exit code = 0`
  (`launchctl print gui/$(id -u)/com.claude.postland-verify`).
- It verifies in a **throwaway worktree**, never the live checkout:
  `WORKTREE="${CC_POSTLAND_WORKTREE:-$WT_ROOT/wt-run-$$}"` (postland-verify.sh:108),
  `git -C "$REPO" worktree add --detach "$WORKTREE" "$sha"` (:770). Two such worktrees are live now
  (`git worktree list` → `~/.claude/autonomy/postland/wt-run-7357`, `wt-run-86570`).
- It writes `<stamps>/<TREE-sha>.json` with `verdict` ∈ green|red|cut|hung — **tree-keyed**, so a
  rebase preserving the tree keeps the verdict (deploy-live.sh:11-12).
- **It does not lock, block or delay deploy-live.** deploy-live never reads `gate-green`, holds no
  lock, and waits on nothing; the only coupling is stamp *presence*. `grep -nEi 'flock|lock' scripts/deploy-live.sh` → **no hits**.

---

## 2 · LIVE-LAG, MEASURED NOW

**LIVE_SRC (which checkout is the live source):** `~/Development/claude-infrastructure` — the default
in three independent places: `DEPLOY_REPO` (deploy-live.sh:71), `LIVE_REPO` (wrap-ledger.sh:323),
`CC_DEPLOY_REPO` (deploy-now.sh:31). Confirmed by symlink target:
`readlink ~/.claude/scripts/wrap-ledger.sh` → `/Users/chrisren/Development/claude-infrastructure/scripts/wrap-ledger.sh`.

```bash
cd ~/Development/claude-infrastructure
git rev-parse HEAD                                  # d52c3a947016…  "fix(cc-offload): a bare cloud URL is a trap"
git log -1 --format='%cr' HEAD                      # 18 minutes ago
git ls-remote origin refs/heads/main                # 37a87cd4f645…  (real remote; local ref is FRESH, not stale)
git rev-list --count HEAD..origin/main              # 4
git rev-list --count origin/main..HEAD              # 0
git merge-base --is-ancestor HEAD origin/main       # rc 0 — behind only, no divergence
```

**Three different lag facts, and they disagree — quote all three or none:**

| Axis | Value | Budget | Verdict |
|---|---|---|---|
| **commits behind trunk** | **4** | 25 (`CC_DEPLOY_MAX_LAG_COMMITS`, deploy-live.sh:81) | inside |
| **age of the live commit** | **18 min** (`%cr` on HEAD) | 6 h (`CC_DEPLOY_MAX_LAG_HOURS`, :82) | inside |
| **pending ADDs** (paths HEAD lacks vs live tree) | **0** — live IS the checkout, so the diff is empty by construction | none (an ADD gets no budget) | see §4.1 |

⇒ `LAG_TRIP` is empty ⇒ **T2 is not authorised** (deploy-live.sh:580) ⇒ the current refusal is the
ladder behaving as designed at this lag, not a new fault.

**The gate's own verdict, asked read-only** (`bash scripts/deploy-live.sh --dry-run --offline`):

```
deploy-migrations: migrate: 0 applied, 7 staged (operator-owned), 0 pending (DRY RUN — nothing written)
deploy-live: REFUSED — no GREEN stamp among the newest 200 commits of origin/main — nothing is safe to deploy
```

**Why T1 cannot fire — the green cursor has fallen out of the scan window:**

```bash
ls -1 ~/.claude/autonomy/postland/stamps | wc -l          # 129
# verdict histogram (python3 json read per stamp):
#   107 red · 18 cut · 3 green · 1 hung
git rev-list --count 71e96bcbc825..origin/main            # 320   ← the only green whose commit is on trunk
git merge-base --is-ancestor 71e96bcbc825 HEAD            # rc 0 — and it is BEHIND live HEAD anyway
git rev-list --count --since='24 hours ago' origin/main   # 142
git rev-list --count --since='7 days ago'  origin/main    # 582
```

`SCAN_N=200` (deploy-live.sh:76). The newest on-trunk green sits **320 commits down**, so T1's walk
never reaches it — hence `RKEY=no-green` rather than `green-behind` (deploy-live.sh:567-573). At
**142 commits/day** the window (200) is consumed in **~34 h**, so a green must appear roughly daily
or the lane is structurally blind. Two of the three greens are not on trunk at all
(`NOT-in-top-400`), i.e. they are side-branch trees.

**Refusal / advance census in the current log** (`~/.claude/autonomy/postland/deploy.log`, 141 096 B, rotated):

```bash
grep -c 'REFUSED'                  ~/.claude/autonomy/postland/deploy.log   # 601
grep -n  'deployed '               … | tail -1   # deploy-live: deployed 4462994233a9 → c2ccbeb8ef53
grep -c  'link-refresh:.*created'  …             # 12
```
Last **sanctioned** advance: `c2ccbeb8` at **2026-08-09 16:14** (`git reflog show HEAD` →
`merge c2ccbeb8ef53…: Fast-forward`) — **~9 h ago**. Everything since is path B/C.
`launchctl print … com.claude.deploy-live` → `runs = 117`, `last exit code = 1`.

**MIG_FAILED state:** `0`.
```bash
for d in applied failed staged superseded; do ls -1 ~/.claude/autonomy/migrations/$d | wc -l; done
# applied 1 · failed 0 · staged 7 · superseded 11
```
The 7 staged are **c10 operator-owned by design** (`migrations/README.md`), not a failure:
`0002-curl-gate-scope`, `0003-cloud-fleet-link-drive`, `0004-lead-deathwatch-l1`,
`0005-goal-inert-watch`, `0006-coldcompile-admit`, `0007-mailbox-wake-arm`, `0008-auth-timeseries`.

**`wrap-ledger.sh --machine`, run here, verbatim:**
```
RUNG=🔧   READOUT=🔧 Loose ends — 3 uncommitted change(s) in the tree; continuing.
DIRTY=1  DIRTY_N=3  AHEAD=0  UNLANDED=0
LIVE=0  LIVE_SRC=skip  LIVE_SHA=  LIVE_LAG=0  LIVE_ADDS=0  MIG_FAILED=0
GATE=stale  TRUNK=origin/main
```
`LIVE_SRC=skip` because `compute_live_layer` is called **only on the ✅-eligible path**
(wrap-ledger.sh:352-353) and the rung is 🔧. See §5.2 — this is the sensor's second blind spot.

**`gate-green` (a different marker, and it does NOT gate deploy-live):**
```bash
cat "$(git rev-parse --git-common-dir)/gate-green"    # 71e96bcbc825efcbabc36fd7a9ebee5f739a7983
ls -l  "$(git rev-parse --git-common-dir)/gate-green" # Aug  7 17:47   → ~32 h stale
```
Single live writer = postland-verify.sh:1707. ship-land.sh:1273 also writes it but is **pinned off**
in v2 (`GATE_EFFECTIVE_FULL=0`, ship-land.sh:1264-1272 — "a land makes no full-suite claim"). Its
only consumers are `hooks/boundary-handoff.sh:316` and `wrap-ledger.sh` (GATE=, :204-208).

---

## 3 · Atomicity — a running consumer CAN observe torn state

**Verdict: YES, torn state is observable, and nothing guards it.** No lock, no quiesce, no staging
directory anywhere on the advance path: `grep -nEi 'flock|lockfile|\.lock|mkdir.*lock' scripts/deploy-live.sh` → **zero hits**.

The exact sequence and its four windows:

1. **`g merge --ff-only "$TARGET"`** (deploy-live.sh:707) rewrites the working tree file-by-file.
   Since every live path is a symlink *into* that tree, a consumer resolving `~/.claude/hooks/X.sh`
   mid-merge reads whatever bytes are on disk at that instant. Across a 4-commit advance that is
   **28 paths** (`git diff --name-only HEAD origin/main | grep -c .` → 28) updated one at a time.
   ⇒ **Window 1 — mixed generation:** hook A already new while hook B is still old, for the
   duration of the checkout.
   ⇒ **Window 2 — transient ENOENT / short read:** git replaces a tracked file rather than
   rename-swapping it, so a `[ -f x ] && . x` guard can miss and a `source`/`exec` can catch a
   partially-written file.

2. **The advancer rewrites itself while running.** deploy-live.sh:686-706 states it outright:
   *"THE FILE UNDER THIS PROCESS CHANGES ON THE NEXT LINE… from here on the code executing is the
   copy bash parsed BEFORE the merge."* Measured consequence recorded there: 8035ea63 (2026-08-05)
   fixed post-merge code, the fix rode along in the very advance that could not run it, and the run
   emitted the pre-fix behaviour — reading as "the fix never landed". Deliberately not closed
   (no re-exec); generator item `07e6e3888e9c`.
   ⇒ **Window 3 — one-deploy-late semantics** for any change to post-merge code.

3. **`install.sh` relink** (deploy-live.sh:733) uses `run ln -sf "$src" "$dest"` (install.sh:200)
   with a skip-if-identical fast path (install.sh:196-199). `ln -sf` over an existing symlink is
   unlink-then-symlink, not an atomic `rename`.
   ⇒ **Window 4 — dangling/absent link:** a consumer resolving that exact path in the microsecond
   between unlink and create gets ENOENT. Narrow, but real, and it is a *silent* skip under this
   tree's guard forms.

4. `link_refresh` (deploy-live.sh:339-353) is **monotone by construction** — it only acts on paths
   the assert reported as failing `-e` (deploy-parity-assert.sh:310 emits `MISSING:` only after
   by-design-PENDING files `continue` at :308), so it *creates* links and never overwrites a live
   one. This step introduces no torn window.

**Mitigating facts, so the verdict is not overstated:** the merge is a single git invocation over a
small path set (28 files today); the ADD path is monotone; and paths A/B/C all use `--ff-only`, so a
consumer can never observe a *rolled-back* tree — only a mixed-forward one. The exposure scales with
lag: an advance across 104 commits touches thousands of paths and holds Window 1 open far longer
than one across 4.

---

## 4 · Verify-at-HEAD — the two known diagnoses

### 4.1 Diagnosis 1 (ADD gap, backlog `99b715f31a98`, 2026-08-09) — **REMEDIED at both ends, with a NAMED residual hole**

**Sensor half — REMEDIED (`83fe0b84`, 2026-08-09).**
`git log --since=2026-08-08 -- scripts/wrap-ledger.sh` → `83fe0b84 fix(wrap-ledger): the converge
budget is an EDIT's budget, and a landed ADD is inert at lag 1`.
`git merge-base --is-ancestor 83fe0b84 HEAD` → **rc 0 (in the live checkout, therefore live)**.
The code is present and correct at HEAD: `LIVE_ADDS` is a tree diff
`git diff --diff-filter=A --name-only "$LIVE_SHA" "$HEAD_SHA"` (wrap-ledger.sh:416), and
`LIVE_ADDS > 0` breaches with **no budget** (:445-446), rendering
`🚀 Landed but NOT live — N NEW file(s) are absent from the live layer` (:524-525). `?` is a
distinct third state that never breaches (:415-421, :443-444).

**Cause half — REMEDIED EARLIER (`c2f24edc` 2026-07-30 hoisted `link_refresh` out of the advance;
`70d86739` 2026-07-31; `a7cba56d` 2026-08-07 added the unconditional migration converge).**
`link_refresh` now runs on **every 600 s tick regardless of refusal** (deploy-live.sh:416-419), so an
ADD is live within **≤600 s of landing** even while the gate refuses. Positive control — the
diagnosis's own subject:
```bash
ls -l ~/.claude/scripts/lib/pane-spawn-log.sh
# lrwxr-xr-x  Aug  7 12:46 → …/scripts/lib/pane-spawn-log.sh
ls -l    scripts/lib/pane-spawn-log.sh          # -rwxr-xr-x  Aug  7 12:44
```
Link created **2 minutes** after the file appeared — consistent with the tick, and the file that
proved the bug is now live. Log evidence of the repair firing 12 times in the current window:
`deploy-live:   linked …/scripts/{headless-precondition-probe,hook-dispatch-bench,pty-census,test-afunix-path-lint,capacity-ramp,pool-floor}.sh`.

🚨 **RESIDUAL HOLE — `link_refresh` covers 5 of install.sh's ~19 link classes.** It consumes only
`deploy-parity-assert.sh`'s `MISSING:` lines, and that leg enumerates a **fixed pathspec**:

```
scripts/deploy-parity-assert.sh:310
  _tracked="$(git -C "$REPO" ls-files -- hooks commands scripts bin skills 2>/dev/null)"
```

install.sh links or copies these classes (`grep -nE 'for [a-z_]+ in "\$REPO_DIR"' install.sh`):

| class | install.sh | in link_refresh's universe? |
|---|---|---|
| `hooks/*.sh`, `hooks/*.py`, `hooks/lib/*.sh` | :264, :272, :276 | ✅ |
| `commands/*.md` | :372 | ✅ |
| `scripts/*.sh`, `scripts/lib/*.sh`, `scripts/limit-recover/*` | :448, :466, :489 | ✅ |
| `bin/cc-*`, `bin/desk-*` | :612 | ✅ |
| `skills/*/` | :525 | ✅ |
| **`agents/*.md`** | :389 | ❌ |
| **`lib/*.zsh`, `lib/*.sh`** | :360, :366 | ❌ |
| **`vendor/*/`** | :548 | ❌ |
| **`githooks/*`** | :309 | ❌ |
| **`accounts.json`, `model-config.yaml`, `~/bin/claude-accounts`** | :428, :436, :422 | ❌ |
| **`launchd/*.plist`** (COPY class) | :670 | ❌ |

For those classes an ADD reaches the live layer **only when `install.sh` runs**, and `install.sh`
runs **only after a successful advance** (deploy-live.sh:733) — last one **2026-08-09 16:14**, with
the lane refusing 601 times since. install.sh:271 says so in its own words for one of them:
*"agents/ leg: a brand-new tracked file is not linked at all, however current the checkout."*
**They are in parity right now** (agents tracked 4 / live-linked 4; `lib` top-level tracked 4 /
live-linked 4 — `lib/cc-upgrade-gate/*.sh` is a subdir the `lib/*.sh` glob never matched either), so
this is a **latent** hole, not an active outage. The next `agents/*.md` or `lib/*.zsh` that lands is
inert until a green stamp releases the lane.

**Verdict: REMEDIED(83fe0b84 sensor + c2f24edc/a7cba56d cause) — with a named residual: the
add-repair path is scoped to `hooks commands scripts bin skills` (deploy-parity-assert.sh:310) and
is blind to 6+ other install.sh link classes.**

### 4.2 Diagnosis 2 (104-commit deploy lag; c10 migrations) — **CHANGED**

**Lag: CHANGED — the 104/91-commit figures are historical and are not reproducible today.**
Measured now: **4 commits / 18 min**, inside both budgets. The worst-case figures in the source are
dated and each cites its own incident: 91 commits + 534 refusals + 276 runs all exit 1
(deploy-live.sh:19-30, 2026-08-07); 174 commits + 96 refusals (deploy-live.sh:299-302, 2026-07-30);
196 commits above the newest green + 29-of-30 ungated advances (deploy-parity-assert.sh:387-392,
2026-07-31).

**But the lag is small for the WRONG reason, and that is the finding.** The sanctioned lane is
*still* deadlocked (601 refusals; last advance 9 h ago; the only on-trunk green 320 commits down).
What keeps the live layer at 4 commits is **path B — agents fast-forwarding the shared checkout by
hand**. `deploy-parity-assert.sh` says exactly this at :394-399: the unconditional `link_refresh`
"erases the only residue a raw ff used to leave behind… the symptom is now cleaned up on a 600s
timer while the ungated advance that caused it goes on undetected", which is why "five prior
sessions each measured 'drift at its historical minimum' and closed."

**Live verdict from the provenance leg, run now** (`bash scripts/deploy-parity-assert.sh`):
```
UNGATED    (provenance)   HEAD advanced OUTSIDE deploy-live — pull --ff-only -q origin main: Fast-forward
UNVERIFIED (verification) HEAD tree 7dfb2754114814a5a6bf0dfc4fb396fbc3117e20 has NO green stamp
deploy-parity-assert: DRIFT — the code running IS this checkout, but it never came through the deploy gate.
```

**Migrations: CHANGED (healthy).** 0 failed, 1 applied, 11 superseded, 7 staged-operator-owned.
`MIG_FAILED=0`, so the migration arm of 🚀 (wrap-ledger.sh:440-441, :522-523) is not firing. The
converger materialises the queue from repo SSOT on every tick even while refusing — visible in
deploy.log: `materialise: + 35-auth-timeseries-activate.sh (was REPO-ONLY — committed but never in
the operator's queue)` and `staged (c10, operator-owned): 0008-auth-timeseries-activation →
cc-backlog e848943a81f4`.

---

## 5 · Adversarial pass — what I nearly missed

### 5.1 The lag number has three denominators and they answer different questions
"4 commits behind" is nearly meaningless alone. **Count** (4) says how much trunk moved;
**age** (18 min) is the only clock that keeps ticking on a quiet trunk (deploy-live.sh:459-463);
**ADDs** (0) is the one with no budget. A close quoting only the count would have read
`✅ … converging` over a state where the *gated* lane has been dead for 9 h. Quote all three, or say
which one you measured.

### 5.2 The 🚀 rung is structurally unreachable for a session in the ROOT checkout
`LIVE_REPO` defaults to `$HOME/Development/claude-infrastructure` (wrap-ledger.sh:323). A session
whose cwd **is** that repo compares the repo to itself:
`git merge-base --is-ancestor HEAD HEAD` → **rc 0** ⇒ `LIVE=1, LIVE_SRC=ok` (wrap-ledger.sh:395-396),
and `LIVE_ADDS` is never even computed (it lives in the `else` branch, :399-421). So the sessions
that perform the **ungated pulls** (path B, all in the root checkout — every transcript above has
`"cwd":"/Users/chrisren/Development/claude-infrastructure"`) are precisely the ones the live-layer
sensor cannot convict. Worktree sessions get the real check; root sessions get a tautology.
**Second gate on top of it:** `compute_live_layer` is called only on the ✅-eligible path
(wrap-ledger.sh:352-353), so any 🔧/📦/⛔ turn skips the live read entirely — observed live as
`LIVE_SRC=skip` in §2.

### 5.3 `~/.claude/CLAUDE.md` is the one live file no converger touches — and it is clean *today*
```bash
md5 -q CLAUDE.md ~/.claude/CLAUDE.md
# fc0b61feb66b2220eb24d97ae86762e9
# fc0b61feb66b2220eb24d97ae86762e9   ← identical
diff CLAUDE.md ~/.claude/CLAUDE.md | grep -c '^[<>]'   # 0
git log -1 --format='%h %cr %s' -- CLAUDE.md
# 37aa0014  34 minutes ago  docs(claude-md): match the live global copy
```
It is in parity only because a session **hand-synced it 34 minutes ago**. No launchd job, no
migration and no link covers it: `install.sh` has no CLAUDE.md leg, and it is `-rw-------`, a real
file. The always-resident policy is therefore the single highest-consequence path where *landed ≠
live* with **zero automated detection** — `deploy-parity-assert.sh:310`'s pathspec excludes it too.

### 5.4 The dirty tree is NOT currently blocking the advance (I assumed it might be)
```bash
git status --porcelain            # 3 entries: M docs/plans/CLOUD_OBSERVABILITY.md + 2 untracked
git diff --name-only HEAD origin/main -- docs/plans/CLOUD_OBSERVABILITY.md   # (empty)
```
`merge_blockers` (deploy-live.sh:367-380) intersects the dirty set with the advance's own path set;
the intersection is empty, and the two untracked files cannot block a `--ff-only` (:371). So the
refusal is `no-green`, not `dirty-tree`. Had I inferred the cause from `git status` I would have
named the wrong one.

### 5.5 The green-stamp famine is a rate problem, not a one-off
3 greens in 129 stamps (2.3%); the newest green stamp of any colour is 08-09 23:05, but the newest
**green** on trunk is from **08-07 17:47** and is now 320 commits down. Trunk runs 142 commits/day
against `SCAN_N=200` ⇒ a **~34 h window**. Unless the verifier greens something roughly daily, T1 is
permanently blind and the lane's only exits are T2 (needs lag > 25 commits or > 6 h — i.e. the
system must get *worse* before the gate will act) or an operator `--force`/`--bootstrap`. Path B's
existence is what keeps lag under the T2 threshold, so **the ungated path is actively suppressing
the degradation path that would otherwise self-heal the gated one.**

---

## 6 · Uncertainties, stated

- **`deploy-parity-assert.sh` exit code not captured** — I piped it through `tail`, so `rc=$?` read
  tail's status. Its stdout verdict (UNGATED + UNVERIFIED + DRIFT) is unambiguous; the numeric rc is
  unverified.
- **Window 2/4 (short read, ENOENT during relink) are derived from the write mechanics** (`git`
  checkout replaces rather than rename-swaps; `ln -sf` is unlink+create), **not** observed on this
  host. Window 1 (mixed generation) and Window 3 (one-deploy-late) are documented in-source with
  measured incidents. A racing-reader experiment would settle 2/4 and was not run (it needs writes).
- **`skills/` link shape may diverge between the two repairers**: install.sh:525 links the skill
  DIRECTORY; `link_refresh` would emit a per-FILE `ln -sf …/skills/x/SKILL.md ~/.claude/skills/x/SKILL.md`.
  Both resolve, but a new skill repaired by `link_refresh` gets a different topology than one
  installed by `install.sh`. Not observed failing; flagged.
- **Reflog horizon**: the 200-entry census covers 2026-07-29 → 08-10 in this checkout. `gc.reflogExpire`
  is 90 d by default, so nothing older was reachable; deploy-parity-assert.sh:429-434 treats an empty
  reflog as a NON-VERDICT for the same reason.
- **Log rotation**: `deploy.log` (141 096 B) is the current window only; the 601 refusals and 6
  advances are counts *within it*, not lifetime totals.

---

## 7 · The three findings that change what someone does

1. **The gated lane has been dead for 9 h and 601 refusals; the live layer is fresh only because
   agents hand-pull the shared checkout.** Both facts are true simultaneously, and every parity leg
   except the provenance one reads clean. (§2, §4.2)
2. **`LIVE_ADDS` is landed and live, but the *repair* it monitors covers 5 of ~19 link classes.**
   `agents/`, `lib/`, `vendor/`, `githooks/`, the two root JSON/YAML configs and `launchd/` have no
   tick-driven repair at all — they wait on an `install.sh` that only a successful advance runs. (§4.1)
3. **A root-checkout session can never see 🚀**, because `LIVE_REPO == cwd` makes the ancestry test a
   tautology — and root-checkout sessions are exactly the population doing the ungated advances. (§5.2)
