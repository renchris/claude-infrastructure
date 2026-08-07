# Machine lag triage + claude-infrastructure-on-kitty audit — 2026-08-06

**Answer: the box is oversubscribed by its own fleet, and the fleet is running 82-commit-old code
because `deploy-live` has been dead-locked for two days.** A 10-core M1 Max is carrying 17 Claude
Code sessions, ~9.5 GB of idle browser-automation infrastructure, and a 297-suite test corpus at a
50% duty cycle. **kitty is the cheapest large thing running** (294 MB, ~6% CPU, 15 panes) and is
exonerated — no kitty-side change is warranted. The one claude-infrastructure defect that matters is
§5: a green-stamp/anti-rollback deadlock that has frozen the live `~/.claude` layer at 42 stale
symlinked files and refused 346 times.

Machine: MacBookPro18,2 · M1 Max (8P+2E = **10 cores**) · 64 GiB · Darwin 24.6.0 · uptime 1d 22h.
Measured 2026-08-06 23:06–23:40 PDT.

---

## 1. The load, measured

| Metric | Value | Read |
|---|---|---|
| Load average | **66.19 / 52.71 / 39.38** at 23:06, **11.44 / 27.11 / 31.87** at 23:13 | spiky, 1–6.6× core count |
| Processes / threads | 1,123–1,349 / **6,342–6,420** | load is thread-level, not process-level |
| CPU split | ~35% user / **~32% sys** / ~32% idle | **one third of the machine is in the kernel** |
| PhysMem | 45–47 G used of 64 G, compressor **6.6 GB** | pressured but not swapping |
| Swap | `swapins 0, swapouts 0`, `vm.swapusage used = 0.00M` | **not swapping** |
| Compressor segments | 106,060 in-core vs `vm.compressor_segment_limit` 1,629,615 = **6.5%** | below the sentinel's 15% trip |

**The 32% sys time is the anomaly.** A healthy box sits at 5–10%. It is the signature of fork/exec
churn and IPC across ~20 agent sessions, their hooks, the daemon layer, and the compressor.

**The panic axis is currently cold.** `panic-compressor-2026-08-05.md` documents three kernel panics
in six days from VM-compressor segment exhaustion. At 6.5% of the segment limit with zero swap
activity, that mechanism is **not** what is happening tonight. `compressor-sentinel.sh` is running
(PID 52180, HEALTHY) but its actuator is default-off — it arms only on `CC_SENTINEL_ACT=stop`, and no
such variable is in its environment.

## 2. Where the memory goes

RSS by application family (`ps -Ao rss,command`, full-cmdline match; sums overcount shared pages):

| Family | RSS | Procs |
|---|---:|---:|
| **Claude Code (sessions + infra)** | **9,721 MB** | 90 |
| **Chrome browser** | **6,356 MB** | 48 |
| **Dia browser** | **5,677 MB** | 27 |
| **chrome-devtools-mcp** | **3,123 MB** | 30 |
| node / next dev servers | 2,033 MB | 6 |
| Cursor IDE | 962 MB | 11 |
| **kitty terminal** | **294 MB** | 10 |
| iTerm2 | 278 MB | 2 |
| bats corpus | 43 MB | 22 |

Session census: **14 Claude leads + 3 assignees**, of which **10 of 14 leads are idle** (<1% lifetime
average CPU). Combined lead RSS ≈ 7.2 GB.

## 3. Finding A — browser fan-out via MCP is the largest reclaimable block (~9.5 GB)

Every `~/Development/.worktrees/*/.mcp.json` for **reso-management-app** contains:

```json
"args": ["chrome-devtools-mcp@latest", "--isolated"]
```

**70 of 272 worktrees carry it** (all 70 owned by reso-management-app — confirmed via
`git rev-parse --git-common-dir`, not by directory name). Any Claude session started in one
auto-spawns the chain:

```
npm exec chrome-devtools-mcp@latest --isolated   (~46 MB)
  └─ chrome-devtools-mcp node process             (48–950 MB)
      └─ a full isolated Google Chrome            (105 MB – 1.45 GB) + N renderer helpers
```

13 such chains were live. Renderer-helper count was **229 at 23:06 and 38 at 23:14** — it spikes hard
and is largely idle in between. Two secondary costs: `@latest` forces an npm registry resolve on
every session start, and each `--isolated` profile is a throwaway.

**This is a reso-management-app config, not a claude-infrastructure one** — but it is the single
biggest memory consumer on the machine and it is mostly idle.

## 4. Finding B — the postland corpus runs at a 50% duty cycle against a 57-hour-red trunk

From `~/.claude/autonomy/postland/runner.log`:

- **RED: 83 · GREEN: 2.** Last green `29313ae4c35a` at 2026-08-04T14:15Z ≈ **57 hours ago**.
- Over the last 10 runs: **54.5 h wall span, 27.2 h spent running the corpus → 50% duty cycle.**
  Individual runs are 0.9–3.25 h over 294–297 suites.
- The autorevert does not converge: `AUTOREVERT verdict=skipped reason=already-attempted
  culprit=b3f728858a6f` repeats from 2026-08-04 onward; once `verdict=FAILED(step=revert rc=90)`.
- `cc-blockers` reports it independently:
  `trunk-red  PERSISTENT-RED  newest 5 all red, 2 green of 85 ever`.

CPU-wise the corpus is small (3.8% summed, 22 processes at PRI 4 background band), so **it is not the
main lag source**. Its costs are that it is a continuous fork/exec generator feeding the 32% sys
time, and — per §5 — that its redness is what holds the deploy lane shut.

Aggregate failures across all 85 runs (`jq` over `postland/stamps/*.json`):

```
  28 tests/gate-home-isolation.bats      18 tests/waiting-recycle.bats
  27 tests/cc-authbrowser.bats           18 tests/session-continue.bats
  23 tests/kitty-conf-bindings.bats      18 tests/lr-team-audit.bats
  23 tests/cc-queue.bats                 18 tests/desk-recycle-durable.bats
  23 tests/capacity-alarm-segments.bats  18 tests/desk-arm-live.bats
  22 tests/git-worktree-guard.bats       18 tests/deploy-parity.bats
```

The per-run failing *set* changes every round, supporting task #117's read that most are contention
flakes rather than one regression. Note `kitty-conf-bindings.bats` at 23 — see §6b, where it turns
out to be already fixed on trunk and stale only in the frozen live layer.

## 5. Finding C — THE HEADLINE: deploy-live is dead-locked, and the fleet runs 82-commit-old code

`~/.claude` is not a copy of this repo; it is **symlinked directly into the shared checkout's working
tree**:

```
~/.claude/hooks/backup-before-write.sh -> /Users/chrisren/Development/claude-infrastructure/hooks/backup-before-write.sh
~/.claude/scripts/postland-verify.sh   -> /Users/chrisren/Development/claude-infrastructure/scripts/postland-verify.sh
```

That shared checkout is at `a9060c18`. `origin/main` is at `94474128`.

```
$ git rev-list --left-right --count origin/main...HEAD
82      0
```

**82 commits behind, 0 ahead** — a clean fast-forward is available and is not happening. Across
`hooks/ scripts/ bin/ commands/ skills/` that is **51 files changed, 6,953 insertions**; of the 50
changed files under `hooks/ scripts/ bin/`, **42 are symlinked into `~/.claude`**. Every session in
the fleet is executing the stale copy of those 42 files.

### Why it cannot advance

`launchctl print gui/$(id -u)/com.claude.deploy-live` → `runs = 269`, `last exit code = 1`.
`~/.claude/autonomy/postland/deploy.log` carries **346 identical refusals**:

```
deploy-live: REFUSED — target 3725e5432bfc is not a descendant of live HEAD a9060c18b314 — this would ROLL BACK the live layer
```

`deploy-live.sh:325` picks its target by walking back from `origin/main` for the newest commit whose
**tree** carries a green stamp:

```bash
tree="$(g rev-parse "$sha^{tree}" 2>/dev/null || true)"
if [ -n "$tree" ] && is_green "$STAMPS_DIR/$tree.json"; then TARGET="$sha"; UNSTAMPED="$scanned"; break; fi
```

The newest green-stamped commit is `3725e543` (2026-08-04, *"Revert 'docs(research): the subagent
idle/working signal is wrong in BOTH directions'"*). Ancestry, measured:

| Question | Answer |
|---|---|
| is live HEAD `a9060c18` an ancestor of `origin/main`? | **YES** — a clean fast-forward is available |
| is the target `3725e543` an ancestor of `origin/main`? | YES |
| is live HEAD `a9060c18` an ancestor of the target `3725e543`? | **NO** — hence the permanent refusal |

**The bind.** The live layer got *ahead* of the last green stamp. Deploying the green-stamped target
would move `~/.claude` backwards, so the anti-rollback guard — correctly — refuses. Advancing
requires a green stamp on a commit at or above `a9060c18`, and §4 shows the corpus has not produced
one in 57 hours. **The guard is right; the state it is guarding is unreachable.**

This is the deployed-layer bootstrap circle: *a check asserting against the deployed layer cannot
pass while the tree is ahead, and deploy only advances via that check.* Tasks #50 and #71 ("Break the
deploy-live bootstrap deadlock via a green stamp") name this exact failure; #50 is marked completed
and #71 is still pending, so it has recurred.

### Why this is also a lag finding

It closes the loop. The corpus is red partly from contention flakes; the contention comes from the
fleet; the fleet runs 82-commit-old hooks and scripts because the corpus is red. Each arm sustains
the others, and the machine pays 27 of every 54 hours re-running a 297-suite corpus to re-learn it.

## 6. Finding D — the kitty verdict, in two parts

### 6a. kitty the terminal is exonerated

| | |
|---|---|
| RSS | **294 MB across 10 processes** (kitty itself 214 MB) — cheaper than iTerm2's 278 MB for 2 |
| CPU | ~5–6% |
| Layout | **3 OS windows · 5 tabs · 15 panes** — far below the 30-pane stress case of `terminal-for-30-panes-2026-07-31.md` |
| Config | `scrollback_lines 2000` (default), `repaint_delay 16`, `input_delay 5`, `allow_remote_control socket-only`, `confirm_os_window_close -1` — all sane; `dec053fb perf(kitty): throttle redraws at high pane count` already landed |

WindowServer was 20.9–45.6% of one core, but with 15 kitty panes plus Chrome, Dia, Cursor and iTerm2
all compositing, that is not attributable to kitty. **No kitty-side configuration change is
warranted.** Task #90 ("multi-hour kitty drift at constant layout") finds no support in tonight's
numbers.

### 6b. `tests/kitty-conf-bindings.bats` — a false alarm that diagnosed §5

Recorded because the *error* is the useful part.

Run from the shared checkout, the suite fails 6-ok/5-not-ok, pinning binding strings that
`config/kitty.conf` has since outgrown (`kitty-split-cwd.sh`, `kitty-confirm-close`, and the
`cmd+ctrl` → `cmd+opt+shift` chord retirement in `1d507193`). It has failed in 23 of 85 corpus runs.
The obvious conclusion — "the test is stale, fix the five assertions" — is **wrong**.

Run the identical suite from a worktree cut at `origin/main`:

```
rc=0  ok=12  not_ok=0
```

**Green.** `cca7cc98 fix(kitty-tests): the ⌘W guard asserted the silent kill the conf exists to
prevent` (2026-08-06) already fixed it. The failure I measured was an artifact of testing the tree
82 commits behind — the same staleness §5 describes. A scan reports *its* revision, not trunk.

One hypothesis was refuted along the way and is worth keeping. Task #124 describes a class where a
suite executing a `KITTY_WINDOW_ID`-branching script, run from an operator's kitty pane, goes red;
the corpus runner (PID 1317) does inherit a live `KITTY_WINDOW_ID=225`,
`KITTY_LISTEN_ON=unix:/tmp/kitty-567`, and `ITERM_SESSION_ID=w0t0p0:240` (kitty sets the iTerm2
variable too, so a guard discriminating on its presence sees both terminals). Running both arms:

| Arm | Environment | Result |
|---|---|---|
| A | inherited live kitty env (what the corpus does) | 6 ok, 5 not-ok |
| B | `env -u KITTY_WINDOW_ID -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_PUBLIC_KEY -u ITERM_SESSION_ID IT2_WRAPPER_NO_KITTY=1` | 6 ok, 5 not-ok — **identical** |

Removing the environment changed nothing, which by task #124's own stated diagnostic indicts the
subject rather than the harness. The class is nonetheless real and larger than filed: **13
terminal-aware subjects under `bin/ hooks/ scripts/`, and 57 suites execute one without pinning the
terminal in `setup()`** — including `it2-kitty.bats`, `it2-kitty-terminal-guard.bats`,
`kitty-setup-*.bats`, `terminal-bench.bats`. That is 5.7× task #124's "all ten suites are pinned"
estimate. It stays a hygiene ratchet, not a fix for anything currently red.

## 7. Finding E — accumulation

| Item | Count | Note |
|---|---:|---|
| git worktrees, total | **272** | 133 claude-infrastructure · 70 reso-management-app · 59 doc_classifier · 3 reso-web-app · 2 sevenrooms-bridge |
| claude-infrastructure worktrees | **133** | task #23 swept 65; it has doubled since. `com.claude.worktree-gc-infra` reports HEALTHY |
| `caffeinate -i -t 300` holders | 11 | one per session — the machine never idles |
| `gitstatusd-darwin-arm64` | 20 | 101 MB, one per powerlevel10k shell |
| `lead-crash-watchdog.sh` | ~17 | one per session |
| Zombies | 3 | minor |
| Blocked permission prompts | 3 | bs-spacing-header, bs-deck-retarget (18m), wt-cc-225106-82355 — sessions parked on the operator |

`cc-fleet --table` reports **5 declared-run services not healthy**:

```
STALLED            com.chrisren.autonomy-sweep         evidence 463h old; bound 15m
STALLED            com.chrisren.verify-2114-archive    evidence 110h old; bound 72h
FAILING            com.chrisren.watch-claude-code-2118-hold  last exit code 1 after 2 runs
NEVER-RAN          com.claude.session-search-backfill  loaded, runs=0, no evidence artifact
NEVER-RAN          com.chrisren.restic-claude-archive  loaded, runs=0, no evidence artifact
```

`com.chrisren.autonomy-sweep` is the notable one: **463 hours stale against a 15-minute bound** — dead
for 19 days while reporting as loaded.

## 8. Recommendations, ordered by leverage

1. **Break the deploy-live deadlock (§5).** Nothing else in this document compounds the way this
   does. The live layer is 82 commits and 42 symlinked files stale, and it cannot self-heal: the
   green stamp it needs sits behind a corpus that has been red for 57 hours. Either force one
   deploy (`deploy-live.sh --force` exists and banners itself as `green-stamp gate BYPASSED`), or
   get one green corpus run above `a9060c18`. Also worth fixing structurally: the target selector
   should refuse to pick a target that is *behind* live HEAD and say so, rather than emitting the
   same refusal 346 times.
2. **Reclaim the idle browser fleet (~9.5 GB, §3).** The 10 idle Claude leads each hold a
   chrome-devtools-mcp + Chrome they are not using. Closing idle sessions reclaims both. Longer
   term, reso's `.mcp.json` should scope chrome-devtools to worktrees doing browser work and pin a
   version instead of `@latest`. *(reso-management-app's call, not this repo's.)*
3. **Triage the top-6 corpus failures (§4)** — `gate-home-isolation`, `cc-authbrowser`, `cc-queue`,
   `capacity-alarm-segments`, `git-worktree-guard`, plus whatever survives once the live layer is
   current. The autorevert is stuck on `culprit=b3f728858a6f` (`reason=already-attempted`) and
   cannot converge on its own.
4. **Sweep the 133 claude-infrastructure worktrees (§7).** `com.claude.worktree-gc-infra` reports
   HEALTHY while the count has doubled since the last manual sweep — worth checking what it collects.
5. **Repair `com.chrisren.autonomy-sweep`** (463 h stale on a 15 m bound) and
   `com.chrisren.watch-claude-code-2118-hold` (exit 1).
6. **Land the task-#124 ratchet eventually** — 57 unpinned suites, not the 0 currently assumed. Not
   urgent; it is not what is red.
7. **Not recommended: any kitty configuration change.** kitty is 294 MB and ~6% CPU for 15 panes.
   Nothing measured supports touching it.

## 9. Method note

Four read-only axis subagents (kitty / daemons / hooks / leaks) were spawned and **all four
terminated without writing their deliverable files**. Nothing here derives from them — every number
is a direct measurement from this session, with the command that produced it named inline.

The §6b correction is the methodological point worth keeping: the first conclusion ("the kitty test
is stale, fix five assertions") was well-evidenced, internally consistent, and **wrong**, because
every command had been run against a checkout 82 commits behind trunk. Re-running the same suite at
`origin/main` refuted it in one step and simultaneously surfaced §5, which is the larger finding. A
scan reports its own revision, not trunk — date every finding against the tree it was measured on.

Not measured this session, and therefore not claimed: per-tool-call hook chain cost, and the per-tick
fork rate of the standing daemon layer. Both are plausible contributors to the 32% sys time and
remain open.
