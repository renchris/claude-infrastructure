# Axis M — dev-tool + editor residency: census, attribution, lifecycle, reap policy

Measured 2026-08-10 06:33–07:45 UTC (23:33–00:45 PDT) on the live box. Read-only: nothing killed,
nothing changed. All process figures are `ps -Ao rss` (KB) unless marked.

---

## 0. The finding that reframes the axis

**The brief's premise — "next-server ×2 = 2.5GB is the dev-tool problem" — is measurably the wrong
target, and the box's own instrument says so.** At the compressor trip 25 minutes before this report
(`~/.claude/logs/compressor-sentinel-snap.log`, `TRIP 2026-08-10T07:09:07Z why=cbu`), the sentinel's
own RSS-by-executable roll-up read:

```
10370.9 MB  x5   ugrep          <- agent-spawned search
 7127.5 MB  x13  claude
 3660.5 MB  x8   claude.exe
 3272.5 MB  x18  node
 2441.1 MB  x11  Browser Helper (Renderer)
 2248.1 MB  x4   Google Chrome Helper (Renderer)   <- puppeteer, agent-spawned
 1925.8 MB  x2   next-server (v16.2.12)            <- the axis's nominal subject, rank 7
 1152.7 MB  x5   chrome-devtools-mcp
```

`ugrep` — the binary the agent's own `grep` resolves to — was **5.4x next-server** and the largest
class on the box. Two of those five were still *growing* at ~131 MB/s five seconds later
(4,177,872 -> 4,836,256 KB between follow-up samples 11 and 12). The resident dev-tool class
(next-server + tsc + esbuild + pnpm) totalled **5.46 GB across 13 processes** — real, but it is the
population that has an owner, a lifecycle and a reaper. The 10.4 GB has none of the three.

Two guards exist for this. **Both were measured tonight to miss it, for different structural
reasons, and one of them froze an innocent process instead.** Sections 4 and 5 are the load-bearing
parts of this report.

---

## 1. Process table (live census, 07:33–07:45Z)

Owner column derived from `lsof -a -p <pid> -d cwd` + `ps -o ppid` chain walk, not from argv.

| proc | pid | RSS | etime | owner worktree | owner session | alive? | current reap policy |
|---|---|---|---|---|---|---|---|
| `next-server (v16.2.12)` | 8747 | 1,401 MB | 1:22 | `wt-cc-225251-80524` | claude 99699 (832 MB, 1h38m) via zsh 78436 | **YES** | devserver-gc: `DEFER live-owner-session` — immortal |
| .. `.next/dev/build/*.js` x4 | 14193/12966/11364/21648 | 466+382+380+365 = 1,593 MB | ~1:15 | same | same | YES | none — children of the above |
| .. `esbuild --service` x4 | 13120/24898/14991/21907 | 264+183+180+164 = 791 MB | ~1:10 | same | same | YES | none |
| **tree total 8747** | | **3,781 MB / 9 procs** | | | | | |
| `next-server (v16.2.12)` | 72883 | 1,026 MB | 14:37 | `wt-cc-232530-26432` | claude 88196 (685 MB, 1h05m) via zsh 26432 | YES | same — *exited on its own mid-session* |
| .. build workers x2 + esbuild x2 | 74929/76514/77166/75763 | 467+359+159+157 = 1,142 MB | ~14:30 | same | same | (gone) | none |
| `node ../typescript/bin/tsc --noEmit` | 11250 | **1,755 MB** (1,528->1,755 in 3 min) | 1:19 | `wt-cc-225251-80524` | `gtimeout --kill-after=30 600 pnpm typecheck` (8861) <- ppid 41245 | YES | **bounded**: 600 s wall by the *caller*, not by any fleet mechanism |
| `node ../tsc --noEmit -p tsconfig.json` | 72813 | 1,037 MB | 0:18 | `/private/tmp/tn-harness` | `timeout 1500 ...` (72806) <- `/tmp/arm2.sh` <- **subagent `dep-types-node@session-119ce481`** | YES | bounded 1500 s by the caller |
| `node ../tsc --noEmit -p tsconfig.json` | 23125 | 1,732 MB | — | — | — | **SIGSTOPped 07:09:07Z by compressor-sentinel** | see 5b — no thaw path exists |
| `pnpm dev` / `next dev` wrappers x4 | 71675/72637/78440/78629 | 155+76+41+48 = 320 MB | 14–60 min | both worktrees | both sessions | YES | none |
| `chrome-devtools-mcp` | 7993 + 12 kin | 2,070 MB / 13 procs | 1h38m | n/a (MCP) | per-session MCP | YES | none (axis G) |
| `Google Chrome Helper (Renderer)` x4 | 73870 + kin | 2,248 MB @ trip, **0 now** | — | `puppeteer_dev_chrome_profile-Ggy05C` | spawned by chrome-devtools-mcp | exited | none |
| `ugrep` x5 | 15222/56363/44259/... | **10,371 MB @ trip** | 60–180 s each | n/a | Bash tool of sessions `7aaf2950...` and one other | exited | **none that can see it** (4, 5) |
| `ollama serve` | 806 | **25.5 MB** | 20h21m | n/a | homebrew LaunchAgent | YES | n/a — 0 models loaded (`/api/ps` -> `{"models":[]}`) |
| `postgresql@14` | — | **0 — NOT RUNNING** | — | — | `launchctl list` -> `- 1 homebrew.mxcl.postgresql@14` | **NO** | n/a |
| Adobe x10 | 640/644/846/1007/1052/1531/2520/2841/3361/3927 | ~380 MB total | 20h12m | n/a | login items | YES | operator's, out of remit |
| **Cursor / VS Code / Zed** | — | **0 — NOT RUNNING** | — | — | last quit ~23:27 PDT (`state.vscdb` mtime) | **NO** | see section 6 |

Corrections to the shared anchor census (`prespawn-decomposition.md:18-22`), each measured:

- **`postgresql@14` is not resident.** The plist is loaded; the job's last exit was **1**, no process
  exists. Zero MB, and a *failing* LaunchAgent nobody noticed.
- **`ollama` is 25.5 MB with zero models loaded** — not a memory term. It is a *latent* one (a single
  model load is GB-scale), but on this box it is noise.
- **Adobe x6 ~= 380 MB across 10 procs** — an order of magnitude below the axis's other rows.
- **"Browser/Google/Dia ~= 7.7 GB" is not all the operator's.** At the trip, 2,248 MB of it was
  `Google Chrome Helper (Renderer) --user-data-dir=.../puppeteer_dev_chrome_profile-Ggy05C` — Chrome
  spawned *by* `chrome-devtools-mcp` on an agent's behalf. That is infra-owned and belongs in this
  axis's ledger, not in "the operator's browsing".
- **`esbuild x6 = 850 MB` understated it**: esbuild is 791 MB across 4 in *one* tree; the axis's real
  unit is the *tree* (3.78 GB), not the process.

---

## 2. Attribution — question (a)

**Every dev process on the box right now has a LIVE owner. There are no orphans at this snapshot.**
The naming scheme makes attribution deterministic and I confirmed it end to end:

- Worktrees are named `wt-cc-<HHMMSS>-<pid>` where `<pid>` is the **kitty login shell** (`/bin/zsh -l`,
  ppid 600 = kitty), not the claude session. `wt-cc-225251-80524` -> shell 80524 -> `cc-close-attrib`
  99286 -> claude 99699. `wt-cc-232530-26432` -> shell 26432 -> 88074 -> claude 88196.
- Both dev servers were started **by an agent**, not by the operator: `next dev` 78629's chain is
  zsh **78436**, whose ppid is **99699 — the claude process itself** (`ps -o ppid`), and 78436's argv
  is the Claude Code shell-snapshot wrapper (`source .../shell-snapshots/snapshot-zsh-...`). So the dev
  server is a Bash-tool child, and its lifetime is bound to a session that has no teardown for it.
- The 1.04 GB `tsc` at `/private/tmp/tn-harness` traces to `/tmp/arm2.sh` under **a research
  subagent** (`claude.exe --agent-id dep-types-node@session-119ce481`). Read-only research fan-out is
  spawning 1 GB compilers. That population is invisible to every census that greps for "dev server".

---

## 3. The devserver-gc predicate — question (b)

`scripts/devserver-census.sh:197-233` (`decide_pid`), in evaluation order:

| # | test | verdict | fires? |
|---|---|---|---|
| 1 | `cwd` unreadable | `DEFER unreadable-cwd` (11) | rare |
| 2 | worktree dir gone | **`REAP orphan-worktree-gone` (0)** | only after worktree-gc removes the dir |
| 3 | `has_live_owner(wt)` | **`DEFER live-owner-session` (10)** | **this is the arm that keeps everything** |
| 4 | `age < 1800 s` | `DEFER birth-grace` (12) | |
| 5 | browser conns > 0 | `DEFER browser-attached` (11) | |
| 6 | cpu-delta >= 1 s in sample | `DEFER working` (11) | |
| 7 | else | `REAP idle-unowned` (0) | |

**It is NOT the same failure shape as the worktree GC — it is a strictly worse one.** worktree-gc's
blocking arm is `merged AND >7d`: age is a clock, so every worktree eventually becomes reapable.
devserver-gc's blocking arm is **ownership**, which is not a clock — a server owned by a live session
is *permanently* unreapable no matter how large it grows or how close the box is to a panic. The
predicate has no cost dimension, no cap, and no box-pressure input at all.

The 100% keep rate is visible in its own log: every `keep pid ...` line since 2026-08-08 reads
`live-owner-session`, and the only thing it ever proposed to reap in 40+ runs was a single ownerless
spawner (pid 29969, kept proposing for 27.5 h until it vanished).

**The owner oracle over-matches, and that over-matching is load-bearing.**
`live_session_cwds()` (`:172-174`) runs `lsof -a -d cwd -c claude`, and lsof's `-c` is a *prefix*
match — **verified live: it returns `cclaude.exe`, i.e. research subagents count as owners.** Right
now it resolves **50 distinct cwds across 11 worktrees**. The header calls this safe because
"over-matching can only cause a KEEP" — true, and precisely backwards for a memory problem: every
extra match is one more server that can never be collected. A 15-subagent research wave, which
writes nothing and owns nothing, extends the immortality of any dev server under any path it happens
to be cwd'd in.

**Two state defects around the arming, both current:**

1. `launchctl print gui/501/com.claude.devserver-gc` reads **`runs = 0`, `last exit code = (never
   exited)`**. The plist was rewritten with `DEVGC_ACT=1` at 00:26 PDT and re-bootstrapped; the last
   *logged* run is `20260810T064020Z` = 23:40 PDT, i.e. **the armed job has never executed.** Every
   run in the log is `act=0` (dry-run). "Armed" is currently an untested claim.
2. Backlog `898f8eafb809` — *"ARM the dev-server reaper..."* — is still **`blocked`** while the plist
   comment records the arming as done with decision packet `99637eaee7b9`. The store and the machine
   disagree. That item also carries the honest calibration nobody should lose: *"safe yield is ~450 MB
   of orphan tail, not 2-7 GB"*.

---

## 4. The memory-storm work item — question (d)

Three artifacts, all found; **none is a duplicate of the others and all three are open in some sense.**

| Artifact | State | What it actually covers |
|---|---|---|
| `docs/research/crash-rootcause-2026-08-09.md` sections 7, 7-bis | landed | The root-cause analysis + the parent-breaker as built |
| backlog `0e4f795b3a20` **[open]**, project **`agent-build-hackathon`** | open | `next.config: experimental.turbopackPluginRuntimeStrategy: 'workerThreads'` |
| backlog `2af4c4908422` **[done]** -> `hooks/qos-rewrite.sh` + `bin/cc-cpubound` + `config/qos-bound.patterns` | landed & live | CPU ceiling on agent Bash search commands |
| backlog `898f8eafb809` **[blocked]** | stale (section 3) | Arm devserver-gc |

**(d-i) The Next.js fix has not reached the running servers, and I can prove it by process count.**
The remedy is `experimental.turbopackPluginRuntimeStrategy: 'workerThreads'`, which *structurally
removes the child processes*. `grep -n 'turbopackPluginRuntimeStrategy' <wt>/next.config.js` returns
nothing in **either** live worktree (`wt-cc-225251-80524`, `wt-cc-232530-26432`) or in
`reso-management-app/next.config.js` — and correspondingly, next-server 8747 still has **4
`.next/dev/build/*.js` child processes (1,593 MB) each with an `esbuild` child (791 MB)**. That is
the unbounded pool the doc names as *"the ignition of 6 kernel panics"*, running right now, 2.38 GB
of it, in a config that has never had the flag. The item is also filed under project
`agent-build-hackathon`, so a claude-infrastructure dispatch wave will never pick it up.

**(d-ii) The fix's stated blast radius is next-server only.** `workerThreads` cannot touch `tsc`
(1.0–1.8 GB, spawned by `pnpm typecheck` and by subagent harnesses) or a standalone `esbuild`, and
neither is a postcss worker. Uncovered after the flag lands: tsc, esbuild-outside-next, ugrep, and
every future build tool.

**(d-iii) The parent-breaker (7-bis) is real and well-tested but scoped to the same cohort** — see 5b.

---

## 5. The two guards, measured against tonight's actual storm

### 5a. `cc-cpubound` — correct, live, and structurally 0.2%-covering

The guard is genuinely deployed (`~/.claude/hooks/qos-rewrite.sh` and `~/.claude/bin/cc-cpubound`
are both live symlinks into the checkout; `config/qos-bound.patterns` has *no* live symlink but the
hook resolves it physically through `$0`, `qos-rewrite.sh:213-230` — that is a correct pre-solution
of the `LIVE_ADDS` inertness trap). It fires: 15 `cc-cpubound 60 grep ...` rows in
`bash-execution.log`, all exit 0.

**It cannot reach the class that causes storms, by three independent gates.** The runaway commands
tonight, verbatim from `~/.claude/logs/bash-commands.log:26173` and `:26675`:

```
[07:07:20Z] S=/private/tmp/.../strings220.txt; grep -o '.\{0,700\}/goal clear to stop early.\{0,700\}' "$S" | head -2; echo ...; sed -n ...
[07:09:36Z] S=/private/tmp/.../strings220.txt; grep -o '.\{0,1500\}Goal set: .\{0,600\}' "$S" | head -c 4000
```

Each is refused by (1) `case "$CMD" in *';'*|*'|'*...) exit 0` — the compound refusal; (2) the leading
`S=...` assignment refusal; (3) even without those, `grep` is not in command position, and the table's
EREs are `^[[:space:]]*`-anchored (`qos-bound.patterns:54-56`). These two commands reached **8.5 GB
and 4.8 GB**.

**Live coverage, measured over the current log (6,138 agent Bash calls since the 2026-08-09 16:21
rotation):**

| population | n | % |
|---|---|---|
| all agent Bash calls | 6,138 | 100% |
| SIMPLE (the only shape the hook can prefix) | 1,262 | 20.6% |
| contains a search binary anywhere | 2,115 | 34.5% |
| **-> actually bounded** (simple + command-position) | **13** | **0.21%** |
| **-> unbounded** | **2,102** | **99.4% of all search calls** |

This matches the design's own 8.8-day figure (233/56,269 = 0.41%), so it is not a sampling artifact.

**The refutation of the design's safety argument.** `qos-bound.patterns:33-37` justifies excluding
compounds: *"A separate survey ... found 88 calls over 60 s and, on inspection, every one was a pipeline
that merely pipes a heavy job through grep (`ship-land.sh ... ; grep`, `eslint ... ; grep`). The hook's
refusal to touch compound commands removes that entire population by construction."* Tonight's two
calls are the counterexample that survey did not contain: **the grep IS the heavy job and `head` is
the cheap tail.** `head -c 4000` does not save it — ugrep buffers `.{0,1500}...` internally before
emitting, so SIGPIPE arrives long after 8.5 GB is allocated. The exclusion is not a filter on
cheap-greps; it is a filter on *syntax*, and the expensive greps happen to wear the excluded syntax.

There is also **no `Grep` matcher anywhere in `settings.json`** (only `Bash`, `Write|Edit|MultiEdit`,
`Agent`, one MCP set, `AskUserQuestion`), so a native Grep-tool call is out of reach by a second,
independent route.

### 5b. `compressor-sentinel` — it acted, and it froze the wrong process

The one memory actuator on this box is armed (`launchctl print` shows `CC_SENTINEL_ACT => stop` in
the inherited environment). It fired at the trip. Verbatim from the snap log:

```
=== TRIP 2026-08-10T07:09:07Z  why=cbu ===
segments 214782 of 1629615 (13.18%) - 3242.5 seg/s - compressor +191844934 B/s
  15222  7086448  63.3  ugrep -G ... -ao .{0,160}Ydr.{0,160} /Users/chrisren/.claude-220/node_modules/@anthropi...
  56363  3505936  65.1  ugrep -G ... -o .{0,700}/goal clear to stop early.{0,700} /private/tmp/claude-501/...
  23125  1725680 117.4  node ./node_modules/.bin/../typescript/bin/tsc --noEmit -p tsconfig.json
...
SIGSTOP pid=23125 rss_kb=1732176 comm=node
actuator: SIGSTOPped 1 process(es) (cap 400, floor 40960 kB)
actuator: parent-break none — no eligible parent owns >= 3 of the 1 selected burst procs
```

**It froze a legitimate 1.73 GB typecheck and left the 7.09 GB + 3.51 GB ugreps running** — which
then grew, in the sentinel's own follow-up samples, 3.86 -> 4.17 -> 4.64 -> 5.18 -> 5.47 GB.

Cause, and it is one line: `scripts/compressor-sentinel.sh:252` and `:279` —
`if (base !~ /^node/) next`. **The burst cohort is selected on `comm` basename matching `^node`.**
`ugrep` is not node, so the largest consumer at the trip is structurally invisible; `tsc` *is* node,
is over the 40,960 KB floor and is "new since 60 s ago", so it is selected. The parent-breaker cannot
rescue this either — `select_break_parents` (`:323`) ranks parents *of cohort members*, so with a
cohort of one it correctly reports `parent-break none`. The under-inclusiveness is deliberate and
documented (`:267`), and it was the right call for the storm it was written for (700 `postcss.js`
node workers of one next-server); it is the wrong shape for a single non-node process at 8.5 GB.

**And SIGSTOP has no thaw path.** `grep -n 'SIGCONT' scripts/compressor-sentinel.sh` returns exactly
one hit — a *comment* at `:314` saying the operator's session is what would send it. Nothing
automatically resumes a frozen process. A false-positive freeze is a silently hung build that the
owning session experiences as an unexplained stall.

---

## 6. Editors — question (c)

**Zero editor processes are running.** `pgrep -fl Cursor` returns one hit and it is
`/System/Library/PrivateFrameworks/TextInputUIMacHelper.framework/.../CursorUIViewService.xpc` — a
macOS text-cursor XPC service, nothing to do with Cursor.app. `Code Helper`, `Visual Studio Code`,
`Electron`, `tsserver`, `typingsInstaller`: **0 each.** Cursor.app, VS Code and Zed are all
installed; Cursor was last live at **23:27 PDT** (`state.vscdb` mtime), ~1 h before this census.

So the axis's editor sub-question has **no live memory term at all**, and the hypothesis "stale
worktree windows pin TS-servers" cannot be true while nothing is running. What is there instead is a
**cold, durable, 5.1 GB liability that every launch pays**:

- `~/Library/Application Support/Cursor` = **5.1 GB**
- `User/globalStorage/state.vscdb` = **1,463,046,144 B (1.46 GB)** — a single SQLite KV store,
  1–2 orders of magnitude above a healthy one, read on every launch.
- `User/workspaceStorage` = **98 workspaces**, whose `folder` fields include paths that no longer
  exist — `.worktrees/wt-cc-224603-79662/docs/design-targets`,
  `.worktrees/wt-cc-215629-18190/docs/wiki`, `/tmp/fable-manual-steps`,
  `/tmp/claude-agent-md-files` (twice), `/tmp/grok-wiki-artifacts`. Agent-created worktrees and
  `/tmp` scratch dirs are being opened as *editor workspaces* (the global CLAUDE.md's
  manual-command-delivery rule says `cursor /tmp/<topic>.sh`), and each one is retained forever with
  its own storage dir.

The correct reading is that the editor is the fleet's largest *cold* dev-tool footprint and its
*window restore* is the risk: if 98 workspaces are ever restored at once, each spawns an extension
host and a TS-server against a mostly-dead path. It has simply not happened during this measurement
window.

---

## 7. Findings (6-line contract)

**F1 — the memory actuator selects `comm ~ ^node` and the top consumer is `ugrep`**
Evidence: `scripts/compressor-sentinel.sh:252,279` `if (base !~ /^node/) next`; snap log
`TRIP 2026-08-10T07:09:07Z` froze `pid=23125 comm=node` (tsc, 1.73 GB) while ugrep 7.09 GB + 3.51 GB
ran on and grew to 5.47 GB in the follow-up samples.
Cost now: the one guard that can act has, at the most recent trip, 1 false positive (a stalled
typecheck with no thaw path) and 0 true positives against 10.4 GB.
Re-architecture: keep the `^node` cohort as the *storm* rule, and add a second, orthogonal selector —
**single-process, RSS over a hard ceiling (~4 GB) and rising over the sample**, comm-agnostic, with
the same claude/mcp exclusions. Pair every SIGSTOP with a bounded auto-`SIGCONT` (e.g. 60 s) so a
false positive costs latency, not a hang.
Sizing: reclaims the 7–10 GB class at the moment it matters - effort **M** - risk medium (needs the
same positive-control discipline as `tests/compressor-sentinel.bats` section 5b).
Existing mechanism: `com.claude.compressor-sentinel` — **EXTEND** (a second selector + a thaw), never
a new daemon.

**F2 — the CPU ceiling reaches 0.21% of agent Bash calls and 0.6% of search calls**
Evidence: `hooks/qos-rewrite.sh:193-199` (compound + leading-assignment refusals);
`config/qos-bound.patterns:54-56` (`^[[:space:]]*`-anchored); measured over 6,138 calls in the current
`bash-commands.log` — 13 bounded, 2,102 unbounded; the two 8.5/4.8 GB runaways at `:26173` and `:26675`
are refused by all three gates.
Cost now: the guard's calibration argument ("compound search calls are cheap greps piping a heavy job")
is refuted by its own recurrence — the heavy job *was* the grep, twice, tonight.
Re-architecture: keep the string-surgery refusal (it is correct), and move the ceiling **inside** the
shell instead of in front of it — have `qos-rewrite` emit `ulimit -t 600; <original command>` as a
prefix *statement* for any command whose text contains a search binary anywhere. `ulimit -t` is
inherited by every child, is the one Darwin limit that sets (measured in `resource-guard-2026-08-08.md`
section 2, 4-of-8 positive control), needs no parse of the command, and cannot break a pipeline.
Sizing: lifts coverage 0.21% -> ~34% of Bash calls - effort **S** (one prefix form, one table) - risk
low-medium (a 600 s CPU ceiling on a compound line must be calibrated against the 2.611% >60 s
population — use 600, not 60, precisely because the line may legitimately contain a build).
Existing mechanism: `hooks/qos-rewrite.sh` transform (c) + `bin/cc-cpubound` — **EXTEND**.

**F3 — devserver-gc's blocking arm is ownership, which is not a clock**
Evidence: `scripts/devserver-census.sh:210-212` `DEFER live-owner-session`; every `keep` line in
`~/.claude/logs/devserver-gc.out.log` since 2026-08-08 carries that reason; the live tree 8747 is
3,781 MB and permanently unreapable.
Cost now: 3.78 GB (one tree) with no ceiling; 181 worktrees carry `node_modules` and 49 carry `.next`,
so the latent surface is ~181 potential trees on 252 worktrees.
Re-architecture: add a **cap arm above the owner arm** — at most **one** owned dev server per session
and **two** fleet-wide; on breach, reap the *oldest* owned server (SIGTERM, which `next dev` handles
cleanly) and log the eviction. Ownership then decides *which* to keep, never *whether* to keep.
Sizing: bounds the class at ~4 GB instead of unbounded - effort **S** (one predicate + a rank) - risk
low (a dev server is recreated by one `pnpm dev`).
Existing mechanism: `com.claude.devserver-gc` / `devserver-census.sh` — **EXTEND**, not new.

**F4 — nothing reaps a dev server at session end; the reaper is hourly and 30-min-graced**
Evidence: all 7 `SessionEnd` hooks in `~/.claude/settings.json` (`session-end.sh`,
`session-deregister.sh`, `session-index-end.sh`, `session-save-id.sh`, `harvest-skill-end.sh`,
`live-session-registry.sh`, `cc-permission-beacon.sh clear`) — **0 of 7** contain any of
`next dev|next-server|pnpm|esbuild|devserver|:3xxx`.
Cost now: worst case a 3.78 GB orphan survives ~90 min (30-min birth grace + up to 60 min to the next
`:40` tick); the log shows one real orphan surviving **27.5 h** (pid 29969, `age=99084s`).
Re-architecture: a `SessionEnd` arm that TERMs dev servers whose `cwd` is the exiting session's
worktree *and* which no other live session owns. Event-driven, so the hourly sweep becomes the
backstop rather than the primary.
Sizing: cuts orphan-tail exposure from ~90 min to seconds - effort **S** - risk low (the same
`has_live_owner` oracle already exists and is tested).
Existing mechanism: `SessionEnd` + `devserver-census.sh decide --pid` — **EXTEND** both; reuse the
module, do not re-implement the predicate (memory: *make-the-actuator-the-arbiter*).

**F5 — the owner oracle counts research subagents as owners**
Evidence: `scripts/devserver-census.sh:172-174` `lsof -a -d cwd -c claude`; verified live — the
returned command set includes **`claude.exe`**, and the oracle currently resolves **50 distinct cwds
across 11 worktrees**.
Cost now: a 15-subagent read-only research wave (this one) extends the immortality of any dev server
under any worktree a subagent is cwd'd in — the axis measuring the problem is inflating it.
Re-architecture: restrict the oracle to **session-leader** processes — `comm` exactly `claude` (not the
`-c` prefix match), or better, read the live-session registry (`hooks/live-session-registry.sh`)
instead of `lsof`. Keep `lsof` as the fallback and keep the `exit 3` refusal.
Sizing: removes a systematic keep-bias - effort **S** - risk low (strictly narrows keeps; pair with a
positive control that a real owner still keeps).
Existing mechanism: `devserver-census.sh` D-a + `live-session-registry.sh` — **EXTEND**.

**F6 — the Next.js remedy has not reached any running server, and its item is filed on another board**
Evidence: `grep -n turbopackPluginRuntimeStrategy` finds nothing in
`wt-cc-225251-80524/next.config.js`, `wt-cc-232530-26432/next.config.js` or
`reso-management-app/next.config.js`; correspondingly next-server 8747 still runs **4
`.next/dev/build/*.js` children (1,593 MB) + 4 `esbuild` (791 MB)**. Item `0e4f795b3a20` is `[open]`
under project **`agent-build-hackathon`**.
Cost now: 2.38 GB of child-process pool per dev server, and the doc names this pool the ignition of
six kernel panics.
Re-architecture: land the one-line `experimental.turbopackPluginRuntimeStrategy: 'workerThreads'` in
reso's `next.config.js` (execution via reso's rails per cross-repo policy), and **re-file the item on
reso's board** so a claude-infrastructure wave can see it.
Sizing: -2.38 GB per live dev server, -6 processes each - effort **XS** (one config line) - risk low
and named (pre-#96592, a failing plugin leaks worker *threads* — one V8 heap, not 700 PIDs).
Existing mechanism: the filed item — **UNBLOCK/RE-FILE**, do not re-derive.

**F7 — the armed devserver-gc has never run, and its backlog row still says `blocked`**
Evidence: `launchctl print gui/501/com.claude.devserver-gc` -> `runs = 0`,
`last exit code = (never exited)`; last logged run `20260810T064020Z` (23:40 PDT) predates the
00:26 PDT plist rewrite; every logged run carries `act=0`. Backlog `898f8eafb809` is `[blocked]` while
the plist header records the arming as ratified (packet `99637eaee7b9`).
Cost now: "armed" is an unverified claim; the first armed run is the first time it will ever kill
anything, unattended.
Re-architecture: run `DEVGC_ACT=1 ~/.claude/scripts/devserver-gc-run.sh` **once, attended**, before
trusting the schedule; then close `898f8eafb809` with that run's `verdict=` line as evidence.
Sizing: 1 command - effort **XS** - risk low (this is the acceptance test the plist's own section 8 asks for).
Existing mechanism: `scripts/devserver-gc-run.sh` — **VERIFY**, nothing to build.

**F8 — three dev-tool consumers are non-issues and one census row is false**
Evidence: `ollama serve` = 25.5 MB with `/api/ps` -> `{"models":[]}`; `launchctl list` shows
`- 1 homebrew.mxcl.postgresql@14` and `pgrep postgres` is empty — **postgres is not running and its
last exit was a failure**; Adobe x10 ~= 380 MB.
Cost now: 0 MB from postgres, 25 MB from ollama. The anchor census
(`prespawn-decomposition.md:18-22`) lists both as "resident".
Re-architecture: nothing to reap. Fix the census row, and note that postgres is a *broken* LaunchAgent
worth booting out or repairing on its own merits.
Sizing: 0 MB recovered - effort XS - risk none.
Existing mechanism: n/a — this is a correction, not a lever.

---

## 8. Reap-policy design, by class — question (e)

| class | live example | owner signal | trigger | action | extends |
|---|---|---|---|---|---|
| `next dev` tree | 8747, 3.78 GB | session cwd at/under worktree | SessionEnd **(F4)** - fleet cap 2 **(F3)** - orphan+30 min (exists) | SIGTERM the `next dev` wrapper (children follow) | devserver-gc |
| `tsc` / `pnpm typecheck` | 11250, 1.76 GB | its own caller already bounds it (`gtimeout 600`) | none needed — but must be **excluded** from the sentinel's node cohort or given the F1 auto-CONT | make the caller's bound mandatory in the gate wrapper | `bin/cc-bats` pattern |
| `esbuild --service` | 13120 x4, 791 MB | child of `.next/dev/build` worker | dies with parent | none | — |
| **agent search (`ugrep`)** | 10.4 GB @ trip | none — transient, unowned | in-shell `ulimit -t` **(F2)** at spawn; sentinel RSS-ceiling selector **(F1)** at runtime | rc 152 verdict to the agent - SIGSTOP + auto-CONT | qos-rewrite (c) + compressor-sentinel |
| MCP-spawned Chrome | 2.25 GB @ trip | `chrome-devtools-mcp` ppid | MCP server exit | (axis G) | — |
| editor | 0 MB live, 5.1 GB cold | n/a | prune `workspaceStorage` entries whose `folder` no longer exists | delete stale workspace dirs; vacuum `state.vscdb` | new, tiny — or hang it off worktree-gc's removal path |
| `ollama` / `postgres` / Adobe | 25 MB / 0 / 380 MB | LaunchAgents | none | none (repair the failed postgres job separately) | — |

**Sequencing, cheapest-first:** F6 (one config line, -2.38 GB/server) -> F7 (one attended run) ->
F2 (`ulimit -t` prefix, 0.21% -> 34% coverage) -> F4 (SessionEnd arm) -> F3 (fleet cap) -> F5 (narrow
the oracle) -> F1 (second sentinel selector + auto-thaw, the only M-sized item).

---

## 9. Adversarial self-pass — what I checked because I had assumed otherwise

1. **"RSS is the wrong metric; the panics are compressor-segment exhaustion."** Checked, and it
   *strengthens* the conclusion. The trip reason is `why=cbu` (compressor bytes used). `ugrep`'s
   10.4 GB is anonymous dirty heap — all of it becomes compressor pressure. `next-server`'s 1.4 GB is
   substantially file-backed (mapped node binary + `.next` cache), which evicts rather than
   compresses. So on the metric that actually panics this box, the gap between ugrep and next-server
   is *wider* than the RSS table shows, not narrower.
2. **"Maybe the guard authors already know about the compound gap."** They do — it is documented as a
   deliberate residual (`qos-rewrite.sh:61-70`, `qos-bound.patterns:33-42`) with an honest
   rule-of-three bound. What is new here is **the refutation of the survey that justified it**: the
   88-call inspection concluded compound-search calls are cheap greps on a heavy pipeline; tonight
   produced two where the grep was the heavy job. That is a measured counterexample to a landed
   calibration, not a re-statement of a known gap.
3. **"Is `lsof -c claude` really matching subagents, or am I inferring it?"** Measured, not inferred:
   `lsof -a -d cwd -c claude -Fc` returns `cclaude.exe`.
4. **"Is the editor axis empty because I looked at the wrong names?"** Checked seven distinct names
   plus `/Applications` presence plus `tsserver`/`extensionHost` process greps. Zero. The one
   "Cursor" hit is a macOS XPC service with an unrelated meaning — a name collision that would have
   produced a false positive had I stopped at `pgrep Cursor | wc -l`.
5. **"The box survived tonight — is this a real risk or a near-miss narrative?"** The trip was real
   (`why=cbu`, 3,242 seg/s, +191 MB/s into the compressor), the actuator fired, and it fired on the
   wrong process. Two `.panic` files from 2026-08-09 (03:41, 04:18) sit in
   `/Library/Logs/DiagnosticReports/` with the same signature. It is a near-miss *of the same class*.
6. **Not covered by me, flagged for the lead:** `chrome-devtools-mcp` (2.07 GB / 13 procs) is axis G's
   but its *puppeteer Chrome child* (2.25 GB at the trip) is mis-attributed to the operator in the
   anchor census — whichever axis owns browser attribution should take that correction.

---

## 10. Blockers / uncertainties

- **`du` over 252 worktrees exceeded a 2-minute bound**, so the dev-tool *disk* term (49 `.next`,
  181 `node_modules`) is a count, not a size. Axis I owns store growth; hand it these counts.
- **The armed devserver-gc's first real run had not happened at report time** (next tick 00:40 PDT).
  Everything I say about its act-mode behaviour is derived from the module's code and its dry-run
  log, not from an observed kill.
- **I did not determine whether pid 23125 was SIGCONT'd or SIGKILLed** after the freeze — it is gone
  and no `T`-state process remains. Either way the finding stands: there is no *automatic* thaw.
- **One-window coverage measurement.** My 0.21% figure comes from the current log rotation (6,138
  calls). It agrees with the design's own 8.8-day 0.41%, so I treat it as representative, but it is
  one window.

---

## 11. Lead-steer verification (2026-08-10, second pass) — composing with the storm work

Three claims from the lead were checked against disk truth. All three hold; **two are worse than
stated**, and one carries a mechanism that will actively undo itself.

### 11a. (a) Which next projects carry `turbopackPluginRuntimeStrategy` today: **ZERO of 156**

```
next.config files under ~/Development (maxdepth 3, node_modules excluded): 156
  WITH experimental.turbopackPluginRuntimeStrategy: 0
  WITHOUT:                                        156
reso-management-app, `git log --all -S turbopackPluginRuntimeStrategy`: 0 commits
```

The remedy exists **only as prose** — in `crash-rootcause-2026-08-09.md:151` and in the title of
backlog `0e4f795b3a20` (filed on project `agent-build-hackathon`). It has never been written to a
config file, on any branch, in any repo on this box. This is the *spec-named-mechanism-may-be-
prose-only* pattern: a cited remedy whose identifiers do not exist in the tree.

Corroborating evidence from the running process table, independent of the grep: next-server 8747
still carries **4 `.next/dev/build/*.js` children (1,593 MB) + 4 `esbuild` (791 MB)**. Had the flag
been applied to that worktree, `workerThreads` would have removed the child processes entirely, so
their presence is a second, orthogonal proof the flag is absent from the config that server booted
from.

**Enforcing-store edge:** the enforcing store is `<project>/next.config.js` **read at `next dev`
boot**. Neither the doc, the backlog row, nor a landed commit in claude-infrastructure can reach it.
A dev server already running does not re-read the config, so even a correct land only takes effect
on the **next** `pnpm dev` — the edge is *config file + server restart*, not *config file*.

### 11b. (b) The arming is not "stranded on a branch" — it is on NO git ref at all

| where | `DEVGC_ACT=1` occurrences |
|---|---|
| `origin/main:launchd/com.claude.devserver-gc.plist` | **0** |
| `crash-rootcause-2026-08-09:launchd/…plist` (branch head `3a2d63ca`) | **0** |
| `HEAD:launchd/…plist` | **0** |
| **`~/Library/LaunchAgents/com.claude.devserver-gc.plist`** (real file, not a symlink) | **2** |
| **loaded launchd definition** (`launchctl print gui/501/…`) | **1** (`export DEVGC_ACT=1; exec …`) |

`c6ab83a8` ("fix(devserver-gc): arm the reaper (DEVGC_ACT=1) — operator-ratified, packet
`99637eaee7b9`") is **not an ancestor of any ref**, including the branch it was authored on —
`git merge-base --is-ancestor c6ab83a8 3a2d63ca` fails. It survives only in the reflog (3 entries),
i.e. it is an **unreachable object** that `git gc` prunes on its own schedule. The live plist is
**byte-identical to c6ab83a8's version**, so the arming is real on the machine and absent from the
repository.

This is the exact **inverse of the `🚀 landed-but-not-live` rung**: *live but not landed*. And the
usual reassurance — "the live layer will converge" — is precisely the danger here, because
convergence runs the wrong way:

```
docs/activation/pending-activation/33-devserver-gc-activate.sh:92-94
  cp "$SRC" "$DST"                              # SRC = launchd/…plist  (DEVGC_ACT=1 count 0)
  launchctl bootout   "gui/$UID_NUM/$LABEL"     # DST = the live plist   (count 2)
  launchctl bootstrap "gui/$UID_NUM" "$DST"
```

**Re-running the queued activation script DISARMS the reaper and reloads it observe-only.** That
script is item 33 in the pending-activation queue, and this session's own SessionStart banner reports
`ACTIVATION QUEUE: 7 un-run (4 rotting >24h)`. The operator therefore holds a queued, encouraged
action whose effect is to silently revoke the ratification they gave at 00:26 today. Nothing warns
about it, because from the queue's point of view the item is simply un-run.

**Enforcing-store edge:** the enforcing store is **launchd's loaded job definition**, sourced from
`~/Library/LaunchAgents/*.plist`. Git is *upstream* of it and currently disagrees with it. The fix is
not "re-arm" (it is already armed) — it is **land `DEVGC_ACT=1` into `launchd/…plist` on origin/main
so the two agree**, before anything re-runs the activation script. Until then the correct advice is:
**do not run activation item 33.**

### 11c. (c) The 03:40 reap proposal — true, and it understates the case by 26 runs

`grep -c 'REAP pid 29969' ~/.claude/logs/devserver-gc.out.log` = **27**. The same ownerless spawner
was proposed for reaping at **27 consecutive hourly runs**, `age=5479s` (1.5 h) at the first and
`age=99084s` (27.5 h) at the last. So the honest version of the arming argument is not "it would have
reaped the spawner 27 minutes before the storm" but **"it had been asking to reap that spawner for
27 hours and was never allowed to"**. That is a materially stronger case for the ratification, and it
should replace the 27-minute framing in the commit message and in `crash-rootcause-2026-08-09.md` §7.

**A new defect found while checking this: the reaper is missing from its own log at the panic.**
Every hourly run on 2026-08-09 is present except one:

```
00:40 01:40 02:40 03:40 04:40 05:40 06:40 07:40 08:40 09:40 [ 10:40 ABSENT ] 11:40 12:40 … 23:40 UTC
```

10:40 UTC = 03:40 PDT, and the storm window brackets it: compressor-sentinel trips at **10:34:27,
10:35:26, 10:36:31 UTC**, kernel panic file `panic-full-2026-08-09-034124` (03:41 PDT = **10:41 UTC**).
The reaper's scheduled run fell inside the storm and produced **no line at all** — not `verdict=none`,
not `verdict=error`, not `oracle-blind`. Its wrapper emits a line on every path
(`devserver-gc-run.sh:40-61`), so a missing line means the process did not reach `emit` — killed,
never spawned under memory pressure, or its output lost with the panic. **The reaper is unobservable
exactly when it is needed**, and its own log cannot distinguish "ran and found nothing" from "never
ran". *(Enforcing-store edge: `~/.claude/logs/devserver-gc.last` is the single-line state file —
it is overwritten by `tee`, so a skipped run leaves the PREVIOUS run's verdict in place and any
consumer reads a stale success.)*

### 11d. My assigned open ground — the storm-coverage matrix per family

Measured against the three mechanisms that could bound a dev tool
(`compressor-sentinel.sh:252,279` cohort · `config/qos-bound.patterns` CPU ceiling ·
`config/qos-batch.patterns` QoS demotion):

| family | live RSS | sentinel cohort (`comm ~ ^node`) | CPU ceiling | QoS demotion | verdict |
|---|---|---|---|---|---|
| `tsc` | 1,755 MB + 1,037 MB | **YES** — comm is `node` | NO ROW | NO ROW | **the only dev family the actuator can see, and the one that least needs it** — it is caller-bounded (`gtimeout 600`, `timeout 1500`) and is a legitimate gate. It is what got falsely SIGSTOPped at 07:09. |
| `esbuild` | 791 MB ×4 | NO — comm is `esbuild` | NO ROW | NO ROW | invisible to all three; dies with its parent, so low risk |
| `next-server` | 1,401 + 1,026 MB | NO — comm is `next-server` | NO ROW | NO ROW | invisible to all three; this is the §7-bis parent-breaker's whole reason to exist |
| `npm` | — | YES | NO ROW | **match** (`npm (install\|ci)`) | covered, but see below |
| **`pnpm`** | `pnpm dev` 40 MB, `pnpm lint` 104 MB, `pnpm typecheck` → the 1.76 GB tsc | YES | NO ROW | **NO ROW** | **the fleet runs pnpm and the table covers npm** |
| `ugrep` | 10,371 MB @ trip | NO — comm is `ugrep` | row exists, 0.21 % reachable | NO ROW | the largest class on the box, effectively unbounded |

**F9 — the sentinel's only dev-tool cohort member is its only false positive.** Of the five dev-tool
families, exactly one (`tsc`) has comm `node`, and it is the one family already bounded by its
caller. Every family that has actually stormed this box — next-server's postcss pool, and ugrep — is
outside the cohort by construction. The cohort is not merely "under-inclusive" (as
`compressor-sentinel.sh:267` says); on this axis's population it is **anti-correlated with need**.
*Enforcing-store edge: `scripts/compressor-sentinel.sh` is reached by a per-file symlink from
`~/.claude/scripts/`, so an EDIT goes live on fast-forward — but the running daemon holds the old
bytes until `launchctl kickstart -k gui/501/com.claude.compressor-sentinel`. The edge is
symlink + daemon restart, not the land.*

**F10 — `qos-batch.patterns` demotes `npm install|ci`; this fleet runs `pnpm`, which cannot match.**
Verified by running the row's own ERE against four literals:

```
npm install     -> MATCH  (demoted to utility)
pnpm install    -> no match  (full interactive priority)
pnpm typecheck  -> no match  (full interactive priority)   <- parent of the 1.76 GB tsc
pnpm dev        -> no match  (full interactive priority)   <- parent of the 3.78 GB server tree
```

The `(^|[[:space:]])` word anchor is correct and is exactly what excludes `pnpm`: the character
before `npm` in `pnpm` is `p`, not whitespace. So the fleet's real package manager — the parent of
both the largest resident tree and the largest typecheck — runs at PRI 31, head-on with the
operator's panes, while the package manager it does not use is demoted. One-line fix: change the row
to `(^|[[:space:]])p?npm (install|ci|dev|typecheck|lint|build)([[:space:]]|$)`, or add a `pnpm` row.
*Enforcing-store edge: `config/qos-batch.patterns` is read from the CHECKOUT by
`qos-rewrite.sh:262` (`$_dir/../config/…`), **not** from `~/.claude/config/` — so a landed edit is
live on the next fast-forward with no converger step and no symlink needed. This is the cheapest
enforcing edge in the whole report.*

### 11e. Revised sequencing, each with its enforcing-store edge

| # | action | enforcing store | edge |
|---|---|---|---|
| 1 | **Do NOT run activation item 33** until #2 lands | pending-activation queue | operator instruction; file it (`cc-backlog needs`) |
| 2 | Land `DEVGC_ACT=1` into `launchd/com.claude.devserver-gc.plist` on origin/main (cherry-pick `c6ab83a8` before `git gc` prunes it) | git ref + the activation script's `$SRC` | `/ship`; no re-bootstrap needed — the live job is already armed |
| 3 | Add a `pnpm` row to `config/qos-batch.patterns` (**F10**) | checkout `config/` read directly by the hook | land only — live on fast-forward |
| 4 | Write `experimental.turbopackPluginRuntimeStrategy: 'workerThreads'` into reso's `next.config.js`; re-file `0e4f795b3a20` onto reso's board (**F6**) | `next.config.js` at `next dev` boot | land **+ restart every running dev server** |
| 5 | `ulimit -t 600;` prefix statement in `qos-rewrite.sh` (**F2**, 0.21 % → ~34 %) | `~/.claude/hooks/qos-rewrite.sh` symlink | land — live on fast-forward |
| 6 | SessionEnd dev-server arm (**F4**) | `~/.claude/settings.json` | **C10 migration**, not an in-place edit |
| 7 | Cap arm above the owner arm in `devserver-census.sh` (**F3**) + narrow the owner oracle (**F5**) | `~/.claude/scripts/` symlink | land — live on fast-forward |
| 8 | Second comm-agnostic sentinel selector + auto-`SIGCONT` (**F1**, **F9**) | `scripts/compressor-sentinel.sh` symlink | land **+ `launchctl kickstart -k`** — the daemon holds old bytes |

Rows 4 and 8 are the two whose enforcing edge is **not** the land: a dev server does not re-read its
config, and a running daemon does not re-read its script. Both need a restart in the same change, or
they join the eight correct analyses that landed and changed nothing.
