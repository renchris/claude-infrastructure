# T8 — Existing-but-unwired land→deploy→live machinery (claude-infrastructure)

Read-only investigation. Every claim cited to file:line or real output. "Declared" vs "running"
is kept separate throughout: a plist row is a declaration, `runs = N` + a log event is an observation.

## §0 Headline (written first, revised at the end)

**REVISED at the end of the investigation.** The deploy chain is NOT missing, not unwired and not
un-run: `com.claude.deploy-live` is loaded, ticks every 600 s, has reached its migrate lane 3,820
times, and advanced the live layer at **2026-09-17T04:35:53Z — 28 minutes before this read**.
Neither un-run activation-queue entry touches it. The four real gaps, in leverage order:

1. **R1** `CC_INSTALL_RESIDENT_RELOAD` — the L4 actuator is built + tested + safety-gated and
   default `0`; the decision is filed (`4194644aea26`) and its own `/tmp` actuator script has
   been reaped, so the answerable decision is currently unexecutable.
2. **R2** `com.claude.deploy-live` is the ONE job the `ProcessType Background` → `taskpolicy -c
   utility` band repair skipped — measured PRI **4** against postland-verify's **20**.
3. **R4/R5** 11 `UNDECIDED` fleet labels and 30 staged c10 migrations, each already carrying its
   own ready command; plus a standing-converge authorization agents already hold and under-use.
4. **The actual wedge is upstream of all of them**: `86 green of 629 ever` (13.7%) and the newest
   green stamp sits **942 commits behind live HEAD**, so the green tier is unreachable and every
   advance rides the T2 absence-of-evidence budget. Band work cannot move that.

## §1 The activation queue (2 un-run, both rotting >24h)

`bash ~/.claude/hooks/activation-watch.sh --queue`:

```
ACTIVATION QUEUE (absence-is-loud, D-v): 2 pending-activation script(s) NOT run.
  ROTTING (>24h, 2): 42-postgresql14-activate.sh, 43-autonomy-sweep-band-activate.sh
```

### 42-postgresql14-activate.sh — NOT deploy-related
`~/.claude/autonomy/pending-activation/42-postgresql14-activate.sh:1-30`. A RECOVERY step
(its own words: "It is a RECOVERY, not a wiring step"), staging
`brew services restart postgresql@14` after backlog `fa2aa0f5e535` (postgres silently down
8 days, 2026-08-05→08-13, because `launchd/fleet.manifest` had no row for the label).
The manifest row already landed; this script is only reached when the board shows a
`fleet-inert` row. **No relation to the deploy chain.**

### 43-autonomy-sweep-band-activate.sh — DIRECTLY on the land chain
`~/.claude/autonomy/pending-activation/43-autonomy-sweep-band-activate.sh:1-30`. It is the
SAME repair migration 0010 / `37-postland-band-activate.sh` already made to postland-verify,
applied to `com.chrisren.autonomy-sweep`:

- The live plist declares `ProcessType Background` ⇒ Darwin's **darwinbg task role**, which
  pins every descendant at **PRI 4** (E-core confined) and *cannot be lifted from inside the
  job* — `taskpolicy -c utility` from within still reads 4 (`tests/postland-band-floor.bats`).
- The sweep **spawns the cloud land lane** (`scripts/cloud-return-lane.sh`), "which lands every
  branch a cloud VM pushes, and a child inherits the role."
- Measured cost, quoted in the script: "One cloud land from that band cost **700-3,900 s**
  against a **194 s** quiet-box median; **36 of 40** attempted lands were cut by the old
  in-tick bound." The step is claimed as a "×30-80 on every cloud land and on every other
  block the sweep runs."
- Why un-run: applying a plist is `launchctl bootout` + `bootstrap`, which is a **C10
  operator-owned** step. Until run, `scripts/launchd-parity-lint.sh` reports CONTENT DRIFT on
  this one label — "that RED is this pending step, by construction, not a defect."
- The repo SSOT (`launchd/com.chrisren.autonomy-sweep.plist`) already drops `ProcessType` and
  `Nice 5` and execs through `taskpolicy -c utility`. **The fix is landed; only the
  bootout/bootstrap is outstanding.**

## §2 `scripts/autonomy-sweep.sh` — lanes, ticking, and the inner/outer bound

### 2.1 Is it ticking? YES (observed, not declared)
`launchctl print gui/501/com.chrisren.autonomy-sweep` → `runs = 55`, `last exit code = 0`,
`state = not running` (periodic, between ticks). Cadence 300 s.

Live IDL window **2026-09-16T23:34:05Z → 2026-09-17T05:03:24Z** (~5.5 h ≈ 66 ticks),
`~/.claude/autonomy/idl.jsonl`, 24,758 rows, 607 of them `tool=="autonomy-sweep"`:

| disposition (≈ lane) | rows |
|---|---|
| phase (cost rows) | 203 |
| fired (§3 summary+notify, the LAST lane) | 66 |
| thrash-recover | 40 |
| join (§0) | 40 |
| config-parity (§0a-i) | 40 |
| cloud-retire | 40 |
| cloud-refusal-route | 40 |
| unfired-briefs (§2f) | 39 |
| custody-deathwatch (§2e) | 39 |
| backlog-health (§2b) | 39 |
| expired-unread | 17 |
| cloud-return (§0a) | 3 |
| **self-bound** | **1** |

### 2.2 The inner>outer bound defect: DOCUMENTED, PARTIALLY CURED, and my measurement
**CORRECTS the in-file comment.**

`scripts/autonomy-sweep.sh:464-484` records the classic form: §0a bounded at **900 s** inside a
tick self-bounded at **400 s** (`a7e5a609e`), so "across 49 self-bound rows, `stopped_before` is
`1-collect-pages-alarms` 35 times and `0b-author-death-join` 14 times — the two EARLIEST
checkpoints, and nothing else, ever." `scripts/autonomy-sweep.sh:523-530` restates it at
2026-09-16: "86 self-bound rows … 46 / 39 … §2b-v sits at checkpoint SEVEN of ten. It has run
**0 times/day since 2026-09-08**. The local drain chain died on 2026-09-09 and the cloud lane on
2026-09-12; the death was found by a human on 2026-09-16, because both detectors were downstream
of the bound."

**MEASURED BY ME, 2026-09-17, on the live store**: exactly **ONE** self-bound row in the window,
and its `stopped_before` is **`2b-ii-grouping-sweep`** — checkpoint FIVE, not one or two:
```
{"ts":"2026-09-17T03:37:29Z","tool":"autonomy-sweep","disposition":"self-bound",
 "stopped_before":"2b-ii-grouping-sweep","elapsed_s":403,"bound_s":400,...}
```
And §3 (`fired`, the LAST lane, whose "last `fired` row" the comment dates to 2026-09-07T21:14:23Z)
fired **66 times** in 5.5 h. So the lower half IS now reached on ~39 of ~40 ticks.

**Why the comment and my reading disagree, and which instrument loses**: `6dd72ca15`
(*"a stale idl-log.sh took the whole store to zero, silently"*) — the live layer converges by
per-file symlink, so `scripts/autonomy-sweep.sh` landed ahead of `hooks/lib/idl-log.sh`; a
`[ -f ]` guard passed against the OLDER deployed file, `idl_guarded_append` was never defined,
and **"the sweep wrote ZERO records. Not a degraded store — an empty one, with a clean exit
code."** Part of the historical "starvation" evidence was therefore an instrument artifact. Both
that fix and `d8b13504e` (*"the arms that detect this job failing were sequenced behind the
bound"*) have landed and are LIVE (the live path is a symlink straight into the checkout:
`~/.claude/scripts/autonomy-sweep.sh -> ~/Development/claude-infrastructure/scripts/autonomy-sweep.sh`;
`grep -c _DETECTORS_HOISTED` = 4).

**Residual that is still real**: the file itself says the hoist is not the general cure —
"§2, §2b, §2b-i..vi, §2e, §2f and §3 are STILL starved … Hoisting one block cures one block;
the general repair is not row 6's surface and is filed" (`scripts/autonomy-sweep.sh:481-483`).
The 900 s-inside-400 s arithmetic is untouched; today's ticks survive only because the cloud lane
has nothing to land (see §2.3).

### 2.3 Does any lane LAND / CONVERGE / DEPLOY?
- **LAND: yes** — §0a `cloud-return` detaches `scripts/cloud-return-lane.sh`, which runs the
  `ship-land` gate on every branch a cloud VM pushes. Observed rows (`tool=="cloud-return-lane"`,
  114 in the window): `cloud_return_rc:"0" elapsed_s:6 bound_s:5400`,
  `cloud-retire … examined=1 kept=1 retired=0`, `cloud-answer … CLEAR 1`. Working, rc 0, but with
  essentially **no cloud work in flight** — so the 900 s bound is not being exercised today.
  This is why §0a logs only 3 rows: the lane is detached and self-looping, not per-tick.
- **CONVERGE / DEPLOY: NO.** `grep -nE 'deploy-live|install\.sh|converge' scripts/autonomy-sweep.sh`
  returns only prose in comments (lines 126, 129, 148, 1348). **The sweep never converges the live
  layer.** That is exclusively `com.claude.deploy-live` (§3).

## §3 Dormant-vs-running inventory (declared ≠ observed)

`scripts/launchd-parity-lint.sh` → **"clean — 32 live plist(s), each findable by Label and matching
its SSOT."** Every deploy-chain job is LOADED (`launchctl list`):

| label | loaded | runs | observed evidence | touches deploy chain |
|---|---|---|---|---|
| `com.claude.deploy-live` | yes, pid 21589 | 39 | 3,820 `deploy-migrations: migrate` lines in `~/.claude/autonomy/postland/deploy.log`; `deploy-last-advance` = `1789619753 fad2bcc1f…` = **2026-09-17T04:35:53Z, 28 min before this read** | **IS the converge lane** |
| `com.claude.postland-verify` | yes, pid 98260 | 3 | 631 stamp files in `~/.claude/autonomy/postland/stamps/` | produces the GREEN cursor deploy-live advances to |
| `com.chrisren.autonomy-sweep` | yes | 55 | 607 IDL rows in 5.5 h | lands cloud branches (§0a); never converges |
| `com.chrisren.cc-reaper` | yes | 39 | reaper log | watchdog only |
| `com.claude.dispatcher` | yes, pid 85265 | 21 | — | fires sessions; not deploy |
| `com.claude.nightly-regression` | **yes** | — | `runs` never observed; board says NEVER-RAN | no |

**Two stale in-tree claims corrected by observation:**
1. `scripts/autonomy-sweep.sh:~495` — *"that job's plist is NOT loaded (`launchctl list` shows no
   com.claude.nightly-regression)"*. It **IS** loaded today (`launchctl list | awk '$3=="com.claude.nightly-regression"'`
   → `LOADED pid=- lastexit=0`). What is true is that it has produced no evidence artifact —
   `cc-blockers` reports it `fleet-inert UNDECIDED … staged: NEVER-RAN`.
2. `43-autonomy-sweep-band-activate.sh` — **its own three post-conditions ALREADY PASS.** Ran its
   exact `migration-verify` predicate from `migrations/0016-autonomy-sweep-band-plist.sh:6`:
   ```
   launchctl print gui/501/com.chrisren.autonomy-sweep | grep 'taskpolicy -c utility' \
     && ! plutil -p ~/Library/LaunchAgents/com.chrisren.autonomy-sweep.plist | grep '"ProcessType"'
   → PASS — already satisfied
   ```
   The LOADED argv is
   `…if [ -x /usr/sbin/taskpolicy ]; then exec /usr/sbin/taskpolicy -c utility ~/.claude/scripts/autonomy-sweep.sh; fi…`.
   `install.sh` converges the plist FILE on every advance, and the 2026-09-16 reboot re-bootstrapped
   from it — so the reboot silently discharged the C10 step. **The queue entry is a rotting no-op.**
   (Conviction 95% — the predicate is the script's own, run verbatim.)

### 3.1 The one job the band repair NEVER reached: `com.claude.deploy-live`
Measured, with `postland-verify` as the positive control (same box, same minute):

| plist | `ProcessType` | execs `taskpolicy -c utility` | observed PRI |
|---|---|---|---|
| `com.claude.postland-verify` | **none** | yes | **20** (pid 98260, `ps -o pid,pri`) |
| `com.chrisren.autonomy-sweep` | **none** | yes | — (loaded argv verified above) |
| **`com.claude.deploy-live`** | **Background** | **no** | **4** (pids 21589, 21890) |
| `com.chrisren.cc-reaper` | Background | no | — |

`migrations/0010-postland-band-plist.sh` fixed postland; `migrations/0016-autonomy-sweep-band-plist.sh`
fixed the sweep. **No migration and no activation script exists for `deploy-live`'s band** —
`grep -l 'deploy-live' migrations/*.sh` returns only incidental mentions. So the converger itself
runs E-core-confined (darwinbg) while both jobs on either side of it were un-confined. One
dry-run tick costs **25.8 s wall / 40% CPU** at PRI 4.

## §4 Prior plans — what was decided, what was left

`scripts/find-plan.sh --status` over all `docs/plans/*.md`:

| plan | status | relevance |
|---|---|---|
| `CONTINUOUS_DELIVERY_TO_LIVE_KITTY.md` | in-progress | **THIS wave's plan**, written 2026-09-17; L1-L4 link table |
| `LAND_PIPELINE_V2.md` | complete | §4.3 specifies the deploy lane; §4.4 specifies the two alarms |
| `DEPLOY_LANE_GROUND_UP.md` | complete | — |
| `DEPLOY_GATE_CONVERGENCE.md` | complete | — |
| `DEPLOY_DECOUPLING_V2.md` | complete | — |
| `MASTER_CONVERGENCE_DEADLOCK.md` | complete | the green-only tier deadlock; cured by the T1/T1H/T2/T3 ladder |
| `CLOUD_BACKLOG_PIPELINE.md` | complete | §A9 = the band fix |
| `DRAIN_CIRCUIT_2026-09-01.md` | in-progress | §3b C — the sweep-order measurement |

**The `unknown`-status trap the brief names is REAL and has exactly 2 instances here**, both with
NO `status:` frontmatter at all:
```
UNKNOWN | claude-infrastructure | docs/plans/STOPHOOK_MESSAGE_TIERING.md
UNKNOWN | claude-infrastructure | docs/plans/SHIP_LAND_HARDENING_PLAN.md
```
Both appear in `find-plan.sh --list-open` (470 rows fleet-wide) and can never leave it.
`SHIP_LAND_HARDENING_PLAN.md` additionally appears 3 more times from stale worktrees
(`wt-mailbox-key`, `wt-terminal-arm`, `wt-terminal-land`) — one plan, 4 permanently-open rows.
Neither is on the deploy chain; the cost is re-dispatch noise, not a broken link.

**§4.4's two alarms ARE built and firing** — `bin/cc-blockers:55-74` implements `deploy-lag`,
`never-green` and `verifier-inert` as disjoint kinds. Live read this session:
```
LAND-PIPELINE — 2 alarm(s):
trunk-red      PERSISTENT-RED   newest 5 all red, 86 green of 629 ever
deploy-wedged  NO-GREEN-AHEAD   green 24c598bac1c7 sits 942 behind live HEAD
```

## §5 The highest-leverage ALREADY-BUILT things that merely need wiring

Ranked by (leverage ÷ work), each with the evidence that it is built.

### R1 — L4 resident-daemon reload: detector ON, actuator BUILT+TESTED, default OFF. **Conviction 92%.**
This is the **only** link in L4 (live layer → running process) that is unsolved for long-lived
daemons, and both halves already exist:
- **Detector, running unconditionally**: `scripts/deploy-live.sh:1705-1899` (`residency_report`),
  emitting into the deploy log on signature change:
  `deploy-live: residency: 1 of 2 executing resident daemon(s) are running STALE bytes — com.claude.compressor-sentinel — so the live layer has NOT reached them (install.sh reloads a resident daemon only on an advance, and only with CC_INSTALL_RESIDENT_RELOAD=1) · 1 exempt`
- **Actuator, landed and tested, gated**: `install.sh:1101-1118` does `launchctl bootout` +
  `bootstrap` on a resident daemon whose running image is stale — behind
  `CC_INSTALL_RESIDENT_RELOAD`, default `0`. Suite `tests/install-resident-reload.bats` (13 cases,
  including the paired control at :126 `unset` vs :213 `=1`).
- **Every named safety precondition is already met**, per the blocked row's own words:
  a veto (`resident_bounce_vetoed`, refuses while the freeze ledger owes a SIGCONT), and
  `install.sh:1378-1415` — a failed bootstrap now **exits non-zero** so the unattended caller
  (`deploy-live.sh:2233`, which pipes install.sh to `/dev/null`) cannot read a downed daemon as
  success.
- **Status**: `cc-backlog 84394a44f133`, `event: block` at 2026-09-08T04:38:04Z, decision packet
  `4194644aea26` (class C, `~/.claude/autonomy/decisions/4194644aea26.json`). Blocker text:
  *"Every technical control is met and landed … nothing further can be measured."*
- **🚨 The packet's actuator is a DEAD POINTER.** Its `needs` field ends *"If yes: bash
  /tmp/resident-reload-flip.sh"* — and `ls /tmp/resident-reload-flip.sh` → **No such file or
  directory**. The 2026-09-16 reboot reaped `/private/tmp` (this repo's own memory:
  *"Perishable INPUT is what makes a wave urgent"*). **The decision is answerable and the answer
  can no longer be executed.** Re-minting that script is ~10 lines and needs no decision.
- **Honest counter-evidence I found in the adversarial pass**: my own `--dry-run` this session read
  `residency: 2 of 2 executing resident daemon(s) are running current bytes` — i.e. the staleness is
  INTERMITTENT, not standing, and the sentinel self-cured between the log line and my read. This is
  a real weakening: the flip buys convergence-latency on resident daemons, not a standing outage.

### R2 — `com.claude.deploy-live` is the one band-repair the migration series skipped. **Conviction 88%.**
See §3.1. Pattern, migration template, activation-script template, and the pinning test
(`tests/postland-band-floor.bats`) all exist; only the plist edit + one bootout/bootstrap is
missing. Cost basis quoted by the two sibling migrations for the SAME change: postland
*"~3× wall clock"* (`migrations/0010:3`), sweep *"one land ~1 h"* (`migrations/0016:3`).
**Residual I cannot close read-only**: nobody has measured deploy-live's own PRI-4 penalty, so the
×3 is inherited from a sibling, not measured here. It is a ~4-line plist diff and is reversible.

### R3 — the sweep's inner>outer bound: half-cured, arithmetic untouched. **Conviction 80%.**
`d8b13504e` hoisted the two detectors above §0a; my measurement (§2.2) shows the lower half is
now reached on ~39/40 ticks and §3 fired 66×. But the file itself states the general repair is
unbuilt (`scripts/autonomy-sweep.sh:481-483`) and 900 s-inside-400 s is unchanged — today's ticks
survive only because the cloud lane has **nothing to land** (`examined=1 kept=1 retired=0`). The
moment a real cloud land arrives, §0a can eat the whole 400 s tick again.

### R4 — 11 `UNDECIDED` fleet labels, each with a READY activation script. **Conviction 90%.**
`bin/cc-blockers` FLEET block: 16 labels not in declared state, 11 of them
`UNDECIDED — staged: <STATE>; decision pending`, each row carrying its own
`CONFIRM=1 bash …/pending-activation/NN-*.sh`. That includes `com.claude.nightly-regression`
(`staged: NEVER-RAN`) — the job `autonomy-sweep.sh` declined to wire work into precisely because it
believed the job was not loaded. **These are already-built wirings whose only blocker is a
one-line operator decision each.**

### R5 — the degraded-tier converge is already AGENT-AUTHORIZED and under-used. **Conviction 85%.**
`.claude/CLAUDE.md` § Standing-converge authorization grants agents
`CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` without a fresh ask, and
`.claude/settings.json` carries the paired permission rule. `deploy-live --dry-run` **prints that
exact command as its own remedy**. No build needed at all — this is a behaviour gap.

---

## §6 Adversarial pass — what I nearly got wrong

1. **"The deploy chain is unwired."** FALSE. It is loaded, ticking, and advanced 28 minutes before
   this read. The un-run activation queue contains **nothing** on the deploy chain (42 is a
   postgres recovery; 43 is a discharged no-op).
2. **"Activation 43 is the fix."** FALSE — its own predicate already passes. I only caught this by
   reading the LOADED argv rather than the plist FILE, which is the discrimination the script's own
   comment warns about (*"The EFFECT is the loaded job's argv, not the file"*).
3. **"The sweep is starved below checkpoint 2."** STALE. The in-file comment's evidence is partly an
   INSTRUMENT ARTIFACT: `6dd72ca15` — *"a stale idl-log.sh took the whole store to zero, silently …
   the sweep wrote ZERO records. Not a degraded store — an empty one, with a clean exit code."*
   Absence of rows was read as absence of execution.
4. **The real wedge is not the band or the queue — it is the GREEN SUPPLY.** `cc-blockers`:
   `trunk-red PERSISTENT-RED — newest 5 all red, 86 green of 629 ever` (**13.7%**), and
   `deploy-wedged NO-GREEN-AHEAD — green 24c598bac1c7 sits 942 behind live HEAD`. Every real advance
   therefore comes through T2 (absence-of-evidence) on the 6 h / 25-commit budget, exactly as
   `.claude/CLAUDE.md` says (*"T1 is structurally unreachable"*). **No amount of band or queue work
   moves this.**
5. **The dominant refusal cause is the SHARED CHECKOUT, not the gate.** Deploy-log refusal classes:
   `diverged-unlanded` ×4, `checkout-diverged` ×3, `dirty-tree` ×2, `peer-wip-wedge` ×2,
   `checkout-not-a-worktree` ×1, plus 4 × `REPAIRED core.bare=true … (a worktree add/remove flips
   it; every working-tree git op was failing)`. **This session's own `git status` shows 26
   uncommitted files in that shared checkout right now.** A `cc-backlog needs` row already names it
   verbatim (seen live in `ps`): *"sessions are advancing the shared checkout by hand (a raw git
   pull/merge outside deploy-live) — that skips the deploy gate AND install.sh, so brand-new tracked
   files land unlinked and silently do nothing; the fix is that sessions work in their own worktree,
   not a command to run."*
6. **`cc-kitty-reload` is already ON and working** — `deploy-live.sh:1870-1887`, live evidence
   `deploy-live: kitty-reload: verdict=reloaded key=6f1609fd5e4d instances=2 spacing=reconciled`
   (4 `verdict=reloaded` in the log). L4-for-kitty.conf needs nothing.
7. **30 migrations staged, 0 applied, every tick** — `deploy-migrations: migrate: 0 applied, 30
   staged (operator-owned), 0 pending`, repeated 3,820 times. The migration lane RUNS and the
   staged set never drains, because every one is class `c10` (operator-owned). This is the same
   shape as R4.
