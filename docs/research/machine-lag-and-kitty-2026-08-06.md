# Machine lag triage + claude-infrastructure-on-kitty audit — 2026-08-06

**Answer: the box is oversubscribed by its own fleet, and the fleet is running 82-commit-old code
because `deploy-live` has been dead-locked for two days.** A 10-core M1 Max is carrying 17 Claude
Code sessions, ~9.5 GB of idle browser-automation infrastructure, and a 297-suite test corpus at a
50% duty cycle. **kitty is exonerated as a lag driver** (~6% CPU; its 1,637 MB footprint is 75% GPU
backing store scaled to *display area × OS-window count*, not to pane count — §6a-bis corrects the
"294 MB" this line first claimed, and names the one real kitty-side lever: 3 OS windows → 1). The
claude-infrastructure defect that matters is §5: a green-stamp/anti-rollback deadlock that has frozen
the live `~/.claude` layer at 42 stale symlinked files and refused 346 times.

Machine: MacBookPro18,2 · M1 Max (8P+2E = **10 cores**) · 64 GiB · Darwin 24.6.0 · uptime 1d 22h.
Measured 2026-08-06 23:06–23:40 PDT.

> ## ⚠ UPDATE 2026-08-06 23:34 — the lag was an EVENT, not a state; two claims above are corrected
>
> Four read-only axis agents (kitty · daemons · hooks · leaks) reported after the first pass. Each
> claim below was re-verified independently here before being adopted. Net effect:
>
> - **The spike self-resolved while it was being investigated.** 1-min load went **66.19 → 6.43**
>   between 23:06 and 23:34 with no intervention (`23:34 up 1 day, 23:15, load averages: 6.43 8.28
>   13.56`). All three non-kitty axes observed the same decay independently. §1 is therefore the
>   peak of a transient, not a steady state — **the durable finding is §5, which does not decay.**
> - **The answer line's "kitty … 294 MB" is wrong by ~6×, and there IS a kitty-side lever.** `ps`
>   RSS undercounts GPU backing store badly. See **§6a-bis**.
> - **§4's corpus finding gains its mechanism**: three concurrent corpus runs at once, because the
>   mutex guards only one entrypoint. See **§4-bis**.
>
> New material the first pass did not measure at all: **§10, the per-event hook layer** — 392 ms per
> Bash call, and a free −30 ms sitting built-but-unwired.

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

### §4-bis — the mechanism: the corpus mutex guards a script, not the corpus

The load spike was **three bats corpus runs at once** (daemon-audit, verified against my own process
census, which had recorded the same PIDs without chasing them):

1. pid 1317/1321 — `postland-verify.sh --run-if-needed` from worktree `wt-9de59b36023d`, PPID 1,
   under `timeout -k 10 10800` (a 3 h budget), full ~300-file corpus, 41 min in.
2. pid 31887 — agent session 38700, `bats -f 'C23:|C13:'`, 8 min in.
3. pid 97812 — **the same agent session 38700**, `tests/postland-verify.bats`, 1 h 27 m in.

`com.claude.postland-verify` fires `--run-if-needed` every 300 s, and the mutex
(`postland-verify.sh:290,342-359`, `LOCK=run.lock.d`, TTL 3600) is taken **inside that script**. An
agent that invokes `bats` directly never sees it. So one agent session ran two suites concurrently
while the scheduled corpus ran a third — ~1,900 tests × 3–6 bash forks each, ×3. That is the
fork-storm signature in §1's `sys 32% > user 35%` split, and it is why the load decayed to 6.43 on
its own: the suites drained.

**Fix shape:** make the lock reachable from outside the script — a `cc-bats` wrapper that takes
`LOCK` before any corpus-scale invocation, or make `--run-if-needed` the only sanctioned entrypoint.

> **AMENDED 2026-08-07 (item `22b9f2b5a660`, implementing this).** The diagnosis above is confirmed
> and the chokepoint is right; **the prescribed remedy is refuted by measurement and was not built.**
> Taking `run.lock.d` itself in the wrapper would be a fleet-wide outage, not a serialization. From
> the verifier's own `runner.log`, consecutive scheduled corpus runs held that mutex for **6257 s,
> 11412 s and 11560 s, started back-to-back** (19:18→21:02, 21:11→00:20, 00:27→03:37 UTC
> 2026-08-06/07) — a duty cycle near **90%**. A wrapper sharing that lock whose loser refused would
> refuse virtually every agent `bats tests/…` on this machine, permanently; whose loser *waited*
> would violate R1 and block for up to three hours. This is the shape `MACHINE_CAPACITY_V2` §9.3
> already records as the cautionary case — the landed `capacity_gate()` REFUSED 10/10 against real
> samples and became a permanent dispatch outage.
>
> **Built instead:** the predicate `MACHINE_CAPACITY_V2` §8.5.1 had already specified for exactly
> this population — *admit if load/core < ceiling AND live bats roots < K, else DEFER with the exact
> re-run command* — enforced in `bin/cc-bats` over a pid-keyed live-roots registry, defaults K=2 and
> 2.0 load/core, exit **75** (`EX_TEMPFAIL`), never a silent 0 and never a 1. The conjunction is what
> keeps it from becoming the outage above: with the corpus holding a slot ~90% of the time, a
> roots-only bound would fire almost always. Under the incident's own numbers (3 roots, load 66.19 on
> 10 cores = 6.6/core) the third run is refused. Every unknown — unreadable load, unwritable
> registry, unresolvable ancestry, malformed seam — **admits**, because a wrong refusal inside the
> corpus surfaces as a failing test and red here reaches `auto_revert`. Tests:
> `tests/cc-bats-admission.bats` (24 green; 11 RED against the pre-change tree).
>
> Recorded rather than rewritten, per `lock-scope-gates-not-protects`: a filed remedy is a
> hypothesis, and verifying its *reasons* rather than only its diagnosis is what caught this.

**One unconfirmed observation, recorded because it inverts the intended priority.** Suite 1's process
tree (1321, 1393, …) read **PRI 20 / NI 20** — ordinary timeshare — *despite its own argv containing
`nice -n 19 /usr/sbin/taskpolicy -c background`*. daemon-audit A/B'd that exact chain in isolation and
it reached PRI 4 in every variant, so the deployed invocation is not getting the band it names. Suites
2 and 3 (the interactive ones) *were* at PRI 4. If real, the **unattended** corpus competes with
foreground work while the **interactive** ones politely do not — exactly backwards. Not reproduced
here; needs a post-spawn `ps -o pri= -p <child>` assertion to become a verdict rather than an
observation.

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

### §6a-bis — correction: `ps` RSS undercounts kitty ~6×, and the lever is OS-WINDOW count

The "294 MB" above is `ps` RSS, and for a GPU-compositing app it is the wrong instrument. Measured
directly:

```
$ ps -o rss= -p 567          →  269 MB
$ footprint -p 567
kitty [567]: 64-bit    Footprint: 1637 MB (16384 bytes per page)
1069 MB   24 regions   IOSurface
 152 MB  198 regions   IOAccelerator (graphics)
    phys_footprint: 1637 MB   phys_footprint_peak: 2251 MB
```

**1,221 MB of the 1,637 MB (75%) is GPU backing store**, and it scales with **display area per OS
window**, not with pane count. This box drives four displays — `3456×2234` XDR plus **3× `5120×2880`
5K @ 60 Hz** (`system_profiler SPDisplaysDataType`) — and kitty holds **3 OS windows**. `top`'s MEM
column had reported 1621M and was right; I discarded it in favour of `ps` and was wrong to.

So the corrected comparison is: kitty **1,637 MB** vs iTerm2 **128 MB** — kitty is *not* the cheapest
large thing running, though ~75% of its cost is a display-area tax any GPU terminal would pay for the
same window count.

**The lever this creates, which §6a said did not exist: consolidate 3 OS windows → 1** (tabs, not
windows). IOSurface is allocated per OS window at that window's 5K backing store, so merging drops
roughly two-thirds of the 1,069 MB and removes two clients from WindowServer's composite tree. It is
a layout change, needs no config edit, and `config/kitty.conf:324-330` already records the underlying
measurement from the prior investigation ("21 panes across 4 OS windows on 3×5K + 1 XDR: WindowServer
71% CPU, kitty 10%") — the finding was in the repo and this document initially missed it.

Pane count is confirmed *not* to be the driver: kitty renders only the active tab of each OS window,
and only 5 of the tabs' panes are in active tabs. **Pane counts in this document are unstable and
should not be quoted** — 15 at 23:14, 12 at 23:34, and kitty-audit reported 21 with a per-tab
breakdown that sums to 16. The stable facts are **3 OS windows and 5 tabs**.

The §6a conclusion survives with one word changed: no kitty **config** change is warranted; a kitty
**layout** change is the single biggest kitty-side win available.

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

## 7-bis. Finding F — the commit-gate mutex is the WRONG REMEDY for an UNPROVEN cause (2026-08-07)

Backlog item `d961db369ef9` was filed against this document, extrapolating §4-bis "one layer up":

> Nothing serialises per-worktree COMMIT GATES: 4 concurrent ~2GB tsc/eslint runs (wt-n16-prefetch,
> wt-n16-conn-module, wt-n16-instr, wt-n16-errors) + a 3.3GB next-server drove load 100 and the
> compressor to 19.9% of segment limit with 56MB free on 2026-08-07.

**Both halves fail.** The remedy is forbidden by this repo's own measured doctrine, and the cause is
not something the cited instrument can establish. Neither claim is in *this* document — the item is
an extrapolation from §4-bis, not a finding it recorded.

### (a) The remedy is a REJECTED ALTERNATIVE, lint-enforced

`docs/plans/MACHINE_CAPACITY_V2.md` §6 rejects this exact mechanism by name, under a heading that
reads *"do not relitigate"*:

> | Serialize all gate runs behind one global lock | Turns wall-time into unbounded deploy latency,
> and the landing lock already serializes the *land* path — the burst is from *pre-commit* gates,
> **which must stay parallel**. Demotion gives contention relief without a queue. |

The adjacent constraint **R1** forbids the load-gated form on *measured* grounds — `gate_admit` was
built, measured at "~2 h sleeping/run; 5 gates self-starving at load 16–18 vs their own ceiling of
8", and deleted (§4 M2). Its absence is a standing acceptance criterion (**AC5**) enforced by a lint
at `scripts/postland-verify.sh:1245-1247`. `hooks/qos-rewrite.sh:25` and `bin/cc-bats:39` both carry
the constraint verbatim: *"NOT admission control. Nothing here waits, sleeps, queues, or polls load
— demotion only (R1)."* Building this item's mutex would trip a lint that exists to stop it.

### (b) The cited instrument CANNOT attribute the memory — in either direction

`compressor-sentinel.sh` fired **18 trips** across 2026-08-06T11:20:40Z → 2026-08-07T07:31:00Z,
segments climbing 3.90% → 31.16%. Its snapshot has two independent blindnesses, so *no* count of
`tsc` — zero or four — can be read off it:

| Section | Defect | Consequence |
|---|---|---|
| `--- argv (…head -80) ---` | truncated at exactly 80 lines in **16 of 18** trips | a miss is a lookup miss, never an absence |
| `--- top by memory (head -30) ---` | prints **COMM only**, so every Node workload reads as `node` | `tsc`, `next-server` and an MCP chain are indistinguishable |

Joining the two by PID leaves **1–8 of the largest `node` rows UNIDENTIFIED at every trip**. Two
successive analyses of this log produced a confident "tsc = 0" that was an artifact — first of the
truncation, then of the COMM column. The honest verdict is *unknown*, and an instrument that fires
18 times during an incident while being unable to name what consumed the memory is the reason a
cause could be filed that nothing verified.

**What the argv sections do establish** (sound as a FLOOR, since truncation only undercounts):
`tsc --noEmit` ran in the n16 worktrees at **1.48 GB** (pid 43687, `wt-n16-gates`) and **1.24 GB**
(pid 1149, `wt-n16-errors`) — real, concurrent, and roughly *half* the claimed ~2 GB. The item's
"3.3GB next-server" is corroborated exactly (pid 24847 at 3,432,416 kB), and that same process was
also observed at **4.63 GB**.

### (c) The larger unserialised per-worktree term is the DEV SERVER, not the gate

Measured live while writing this, 2026-08-07T07:5x: **6 concurrent `next-server` processes totalling
~7.1 GB**, one of them (pid 24847) at **5.82 GB after 38 minutes and still growing** — a single
resident allocation about 4× the entire concurrent-`tsc` term the item blames. `grep -rl
'next-server|pnpm dev|next dev' scripts/ bin/ hooks/` returns **nothing**: no reaper, no cap, no
census. A commit gate is transient and self-terminating; a dev server is a permanent per-worktree
allocation that nobody collects. R1 does not bind here at all — reaping an idle server is not
admission control, and a dev server is not a gate.

### (d) The standing memory backstop is DISARMED

Two `compressor-sentinel.sh` instances are live (command-position–anchored, *not* `pgrep -f` — the
argv of the bats corpus contains the string and inflates the count):

```
52180  ppid 1  up 1-12:14:52  /bin/bash …/compressor-sentinel.sh   ← launchd, com.claude.compressor-sentinel
86050  ppid 1  up      38:50  bash      …/compressor-sentinel.sh   ← orphan
```

`com.claude.compressor-sentinel.plist` sets **only `PATH`** — no `CC_SENTINEL_ACT` — and the script
defaults `ACT="${CC_SENTINEL_ACT:-off}"` (`:70`). So the durable, launchd-managed sentinel runs
**detection-only**, and the armed `SIGSTOP` actuator seen in the log belongs to the 38-minute-old
orphan that will die with whatever session started it. This is why the snap log interleaves
`actuator: SIGSTOPped 1 process(es)` and `actuator: DISARMED (CC_SENTINEL_ACT=off)` seconds apart:
two instances, two policies, one log. Against four kernel panics from compressor-segment exhaustion
(`panic-compressor-2026-08-05.md` §1), the standing protection being detection-only is the finding
that outranks the mutex this item asked for.

**Disposition:** `d961db369ef9` closed as **refuted** — not built. This section is written here, in
the document the item cites, so the same extrapolation cannot be re-filed from §4-bis. §4-bis itself
(the corpus mutex, `22b9f2b5a660`) is untouched by this and remains valid: `bin/cc-bats` still takes
no lock, and `run.lock.d` still lives only at `scripts/postland-verify.sh:379`.

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
7. **Not recommended: any kitty *configuration* change.** `repaint_delay 16`, `input_delay 5`,
   `scrollback_lines 2000`, `background_opacity` unset, `cursor_blink_interval 0` are already the
   right values — `dec053fb perf(kitty): throttle redraws at high pane count` landed exactly this
   tuning. Lowering `repaint_delay` further would *raise* cost.

**Added after the axis reports (§4-bis, §6a-bis, §10), in leverage order:**

8. ~~**Serialize the corpus (§4-bis).** Three concurrent runs caused the spike. Put the `run.lock.d`
   mutex behind a wrapper any caller must use, so an agent typing `bats tests/…` cannot bypass it.~~
   **DONE 2026-08-07, with the remedy re-derived** — sharing `run.lock.d` was measured to be a ~90%
   duty-cycle outage, so `bin/cc-bats` enforces a two-term admission bound instead (live roots ≥ K
   **and** load/core ≥ ceiling ⇒ defer with the exact re-run command, exit 75). See the amendment
   box in §4-bis for the measurement and the reasoning. This is the fix for the lag *event*, as §5
   is the fix for the durable state.
9. **Run `26-curl-gate-scope-activate.sh` (§10).** Free −30.4 ms on every Bash call, already built,
   tested and symlinked; only `settings.json:435` still points at the unscoped hook.
10. **Scope `teammate-checkpoint.sh` to worktrees (§10)** — drop the `*)` arm at `:67-75` so the
    human-owned repo root stops being checkpointed, and tighten the machine-wide GC damper at
    `:91-115`. Standing cost today: 6,097 refs, 599 KB `packed-refs`, paid by every `git` call in
    every hook.
11. **Consolidate kitty's 3 OS windows into 1 (§6a-bis)** — the only kitty-side win, ~700 MB of
    IOSurface plus two fewer WindowServer composite clients. Layout change, no config edit.
12. **Add `"timeout": 10` to `waiting-recycle.sh`** — the only unbounded hook on the hottest event
    (PostToolUse/Bash), 1,214 lines, reads transcripts, runs `osascript`, and can `exec
    handoff-fire.sh --recycle`.
13. **Reconcile `~/.claude/settings.json` vs `~/.claude-next/settings.json`** — they register
    different chains (PreToolUse 14 vs 13, Stop 11 vs 10, SessionStart 14 vs 13). Live panes run
    `~/.claude-220` with `~/.claude-next` snapshots, so per-event accounting from `~/.claude` alone
    is wrong for some of them.

**Added after the 2026-08-07 follow-up (§7-bis), in leverage order:**

14. **Arm the launchd compressor sentinel.** `com.claude.compressor-sentinel.plist` sets no
    `CC_SENTINEL_ACT`, so the durable instance is detection-only while four panics stand on this
    exact mechanism; the armed actuator belongs to an orphan that dies with its session. Operator
    step (plist edit — C10).
15. **Reap idle `next-server` dev servers.** 6 concurrent / ~7.1 GB measured live, one at 5.82 GB
    and still growing after 38 minutes; no reaper, cap, or census exists anywhere in `scripts/`,
    `bin/` or `hooks/`. Larger and far more durable than the commit-gate term §7-bis was filed about.
16. ~~**Make the sentinel snapshot attributable.**~~ **DONE 2026-08-07** — `head -80` on argv plus a
    COMM-only top-30 meant the forensic record could not say what consumed the memory, which is the
    defect that let §7-bis's item name an unverified cause. `scripts/compressor-sentinel.sh` now
    inverts the composition: `top_by_rss` ranks by RSS and prints the **full argv** of the rows that
    ranked, so the section's bound is a *rank* in the quantity the incident is about rather than a
    line cut over an unranked, name-filtered list. `rss_by_exe` keeps the one thing the old list
    caught by accident — a swarm of small identical workers — as an explicitly coarse total. The
    twelve follow-up samples render the same thing (they were the blindest part of the record: a
    process born after the trip appeared in no section at all). Seams `CC_SENTINEL_SNAP_TOPN` (30) ·
    `_TOPN_FUP` (10) · `_ARGV_MAX` (400, and the cut stamps how much it dropped) · `_AGG_N` (15),
    each refused at startup if non-numeric, because awk turns `-v n=abc` into 0 and an n of 0 renders
    a header with nothing under it — a typo would silently restore this exact blindness.
    Live verification on the same box: the 2.6 GB `node` row that this document could only call
    `node` now reads `…/wt-n16-conn-consumers/…/eslint.js src/ lib/ replicache/ --cache`.
    11 tests in `tests/compressor-sentinel.bats` §7, all red against the pre-fix script.
17. **Not recommended: serializing per-worktree commit gates.** Rejected on measured grounds
    (`MACHINE_CAPACITY_V2.md` §6 + R1/AC5); see §7-bis.

## 10. The per-event hook layer — measured (was "open" in §9)

§9 listed per-tool-call hook cost as not measured. It now is (hook-audit; the PreToolUse subtotal
independently corroborates this repo's own `docs/plans/HOOK_CHAIN_COST.md` §2.3 within 3.5%, and I
re-verified the two actionable findings directly).

**~392 ms of CPU and ~55 process creations per Bash tool call**, across a 12-hook hot chain (7
PreToolUse + 5 PostToolUse — two of the PostToolUse entries match `""`, i.e. *every* tool). At the
measured live rate of 780–844 Bash calls/hour across 17 sessions, that is **0.086 cores = 0.9% of
this 10-core box**. The statusline adds 0.025 cores (measured 0.66 renders/s fleet-wide × 37.6 ms —
it renders on activity, not a timer). **The hook layer is not a lag driver**, and per `HOOK_CHAIN_COST.md`
§3 the obvious remedy is already refuted: `hooks/hook-chain.sh` was built in `5c88633f` and measured
*negative* (174 ms serial vs ~180 ms dispatched). Do not rebuild it.

Worst offenders: `validate-bash.sh` 78.4 ms / 18 externals · `qos-rewrite.sh` 49.7 ms ·
`curl-gate.py` 37.7 ms · `git-worktree-guard.sh` 18.6 ms.

Two findings here are worth acting on regardless of the lag, and both were verified here:

1. **`curl-gate-scope.sh` landed inert — a free −30.4 ms/Bash call (7.7% of the chain).** It is
   built, has 14 bats cases, is symlinked live
   (`~/.claude/hooks/curl-gate-scope.sh -> …/hooks/curl-gate-scope.sh`), and ships an activation
   script (`docs/activation/pending-activation/26-curl-gate-scope-activate.sh`) — but
   `~/.claude/settings.json:435` still registers `~/.claude/hooks/curl-gate.py` directly, so every
   Bash call pays 37.7 ms of Python startup for a hook that no-ops outside reso. Verified by reading
   line 435 and resolving the symlink.
2. **`teammate-checkpoint.sh` is checkpointing the shared repo root**, not just teammate worktrees:
   its `*)` arm (`:67-75`) accepts any dir passing `git rev-parse --git-common-dir`, which the root
   does. The root tree is dirty, so `:140`'s `git status --porcelain | grep -q .` is always true and
   every 5th tool call runs `read-tree` + `add -A` + `write-tree` + `commit-tree` over 1,214 tracked
   files. Its GC damper is one **machine-wide** stamp (`:91-115`), so ~20 sessions share one sweep
   per day against a 24 refs/hour production rate. Verified standing state: **6,097 refs under
   `refs/checkpoints/`, `.git/packed-refs` at 599 KB** — a cost every `git` call in every hook pays.

## 9. Method note

Four read-only axis subagents (kitty / daemons / hooks / leaks) were spawned. **All four delivered,
but none could write its deliverable file — the briefing was at fault**: they were `Explore` agents,
which have no Write/Edit tool, and I gave them a delivery contract requiring one. Each returned its
report inline instead. *A delivery contract must be satisfiable by the agent type you spawn* — check
the tool list before writing the contract.

Every axis claim adopted above was re-verified here before adoption, and two were **not** adopted:
kitty-audit's "21 panes" (its own per-tab breakdown sums to 16, and I measure 12–15 at different
moments), and the various session counts, which disagree across axes (14 leads by my count of the
node binary, 19 by daemon-audit, 39 by leak-audit, 97 procs by hook-audit) because each counted a
different population. Where the axes and I disagreed, the disagreement is stated rather than
averaged.

The §6b correction is the methodological point worth keeping: the first conclusion ("the kitty test
is stale, fix five assertions") was well-evidenced, internally consistent, and **wrong**, because
every command had been run against a checkout 82 commits behind trunk. Re-running the same suite at
`origin/main` refuted it in one step and simultaneously surfaced §5, which is the larger finding. A
scan reports its own revision, not trunk — date every finding against the tree it was measured on.

Not measured this session, and therefore not claimed: per-tool-call hook chain cost, and the per-tick
fork rate of the standing daemon layer. Both are plausible contributors to the 32% sys time and
remain open.
