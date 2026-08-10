# 08 — Kernel/daemon terms the S6 capacity model does not own

**Date:** 2026-08-09 · **Box:** MacBookPro18,2 · M1 Max (8P+2E) · 64 GiB · Darwin 24.6.0 · SIP **enabled**
**Scope:** every platform term OUTSIDE S6's owned set (render, memory, ptys, load, compressor segments).
**Method:** derive first, then verify live where a non-sudo instrument exists. Bounded sampling (≤1 Hz, ≤120 s
per instrument), per-pid `lsof` only, no sudo, no config changes, no load generation.
**Ambient during measurement:** 10 `claude` sessions (command-position count), 921–927 procs, 4,271 threads,
load1 24.9–27.1, 3 kitty OS windows / 9 panes, iTerm2 **not running**, swap 0.00 M, uptime 18h57m.

**Already owned elsewhere — not re-litigated here:** compressor segments + jetsam bands
(`crash-rootcause-2026-08-09.md`); pty namespace, `head_gb` inflation, loadavg blindness, sum-RSS inversion
(`session-capacity-blind-terms-2026-08-09.md` N1–N6 + `pty-ceiling-2026-08-09.md`); render CPU/pane and the
150-resident memory budget (`CONCURRENCY_PROGRAM.md` §S6.1–S6.2).

---

## 1. Verdict table

| term | binds-before-150 | evidence (command or file:line) | remedy | confidence |
|---|---|---|---|---|
| (g) **git shared-store write contention** | **Y** | `git worktree list` = 113 on one 256 MB `.git`; `git count-objects -v` → 692 loose / 2 packs / 118 MB; `gc.auto` unset ⇒ default 6700; 2 of 10 live sessions cwd'd in the SHARED root `/Users/chrisren/Development/claude-infrastructure` (per-pid `lsof … cwd`) | `gc.auto=0` on the shared store + one scheduled `git gc`; enforce one-session-per-checkout; serialize `git worktree add` behind the existing land-lock | high (mechanism) / med (threshold) |
| (h) **keychain / oauth refresh herd** | **Y** | `scripts/relogin-probes/e1-concurrent-logins.sh:9-11` (item = `Claude Code-credentials-<sha256(CFG_DIR)[:8]>`); `forced-relogin-rootcause-2026-08-02.md` (rotation MEASURED: rt `0023ef9690b1→a9f8aadf29eb`; `lock_timeout` failure mode); `.credentials.json` absent in all 4 config dirs ⇒ keychain-backed; 27 `Claude` genp items in `login.keychain-db` | one refresh owner per account (sessions read a cached token), or per-slot `CLAUDE_CONFIG_DIR` grants (e1 Variant A — verdict unrun) | high (mechanism) / med (threshold) |
| (j) **MCP child memory** *(not in brief; not in S6's budget)* | **Y** | `ps -A -o rss=,command=` → 22 `chrome-devtools-mcp` procs / **5,073 MB** at 10 sessions = 2.2 procs & 507 MB per session; `top -l 2 -o mem` → node pid 7993 **2,179 MB**, pid 78670 **2,026 MB** | add an MCP row to the S6.2 budget; cap MCP servers per session or share one fleet-wide | high (measurement) / med (does 10/10 hold at 150) |
| (c) **vnode cache** | **UNKNOWN** (latency, not failure) | `kern.num_vnodes == kern.maxvnodes == 263168`; `kern.free_vnodes` 154,869→189,650 (in-use 73.5k–108.3k); recycle **632/s**, newvnode **624/s** over 30 s; lifetime `num_recycledvnodes` 295,748,141 in 19 h = mean 4,325/s | `sysctl -w kern.maxvnodes` (writable with SIP on — see §4) + LaunchDaemon to persist | med |
| (k) **syspolicyd exec gate** *(new)* | **UNKNOWN** | 12 s `log stream`: syspolicyd **6,861 msgs / 5 threads = 572/s**, 77% of sampled log volume; `top` CPU 2.9%; against a measured **923 exec/s** | none needed unless it serializes; measure with a fork-rate ramp (banned here) | low-med |
| (l) **`.claude.json` unlocked rewrite** *(new)* | **UNKNOWN** | 90 s @1 Hz `stat -f %m`: 6 distinct mtimes on `.claude-next`, 4 on `.claude-tertiary`; file 160–189 KB; `.claude.json.backup` written alongside at identical size (tertiary: 171,174 B, 23:36 / 23:34); **no lockfile present** in any config dir | single-writer proxy or per-session config dirs | low-med |
| (a) **Mach ports / WindowServer** | **N** | WindowServer RSS **flat/declining** 243,984→229,152 KB over 120 s @ 0.5 Hz at 9 panes; `kitty @ ls` = 3 OS windows / 9 panes; iTerm2 not running; incident-#0 port growth recomputes to **0.053 ports/s** | none under kitty; if iTerm2 returns, the ~12 windows/h leak is the term | med-high |
| (b) **fd table** | **N** | `lsof -a -p <pid>` (5 sessions): **25–33 total fds, 2–7 established** each; `kern.num_files` **7,635 / 491,520 = 1.6%**; `maxfilesperproc` 245,760; kitty 115 fds at 9 panes | none | high |
| (d) **kqueue / FSEvents** | **N** | 5 claude pids + kitty: `lsof -a -p … | grep -c fsevents` = **0** everywhere; 2–3 `KQUEUE` fds each; no kqueue sysctl limit exists (`kern.aiomax` 90 / `aioprocmax` 16 are unrelated) | none; `mds_stores` at 30.2% CPU is a separate sub-term (§3d) | high |
| (e) **logd / unified log** | **N** | `du -sk /var/db/diagnostics/Persist` +1,024 KB in 90 s = **11.37 KB/s = 953 MB/day**; store 2.3 GB + 575 MB uuidtext; logd CPU 1.0% | none; retention already self-rotates | high |
| (f) **PID churn / wrap** | **N** as capacity · **Y as a correctness hazard, already live** | 7 samples @15 s: 1024/776/846/1097/1083/715 pid/s → **mean 923/s**; wrap observed (99,917 → 32,014); `PID_MAX 99999` (XNU `bsd/sys/proc_internal.h`); proc table stable 921–927 | pair every stored pid with start-time or cwd/argv hash; 85 `kill -0` + 51 kill-by-stored-pid + 8 `ps -p $STORED` sites | high |
| (i) **disk / swap** | **N** | `vm.swapusage total = 0.00M`, `/System/Volumes/VM` **empty**; `df` 4.9 Ti avail, 53 G free inodes; transcripts 5.1 GB total, 46 MB across 39 jsonl touched in 1 h; `/private/tmp` 325 MB | none | high |

---

## 2. The YES rows

### (g) Git shared-store write contention — and a restatement of `cannot lock ref 'HEAD'`

**Measured.** 113 worktrees registered on one shared `.git` (256 MB; 249 worktree dirs box-wide, 382 in the
prior census at commit `5c73144b`). Git process concurrency sampled 60× @1 Hz at 10 sessions: 0 in 29
samples, 1 in 14, 2 in 13, 3 in 3, 4 in 1 → **mean 0.883 concurrent**. Read paths are cheap and are NOT the
term: `git rev-parse HEAD` 0.00 s, `git status --porcelain` 0.01–0.02 s, `for-each-ref` 0.01 s against a
524,723-byte `packed-refs` + 59 loose refs.

**Derived.** The shared serialization points at 150 worktrees are: `packed-refs.lock` (ref packing/deletion),
the `gc.pid` lock (`git gc --auto` runs after every commit/fetch/merge), `.git/config.lock` (every
`git worktree add`/`remove` — the documented parallel-worktree race, GH #34645 / #48927), and the shared
reflog `logs/refs/heads/<branch>`. Auto-gc is the one that flips: `gc.auto` is unset ⇒ default **6700 loose
objects**, and the store holds **692** at 10 sessions. A 15× session count crosses 6700 in hours, after which
every session's next write attempts a gc on a 118 MB pack.

🚨 **The `cannot lock ref 'HEAD'` class is mis-attributed to worktree count.** In a LINKED worktree, `HEAD`
lives at `.git/worktrees/<name>/HEAD` — **per-worktree, not shared**. That failure requires 2+ sessions in
the SAME checkout. Which is live right now: 2 of 10 sessions are cwd'd in the shared root
`/Users/chrisren/Development/claude-infrastructure`, in direct violation of `.claude/CLAUDE.md`'s
"Never commit or land in the shared checkout". So this is a **doctrine-compliance term, not a scale term** —
it does not wait for 150.

**Anomaly found in passing:** `git count-objects -v` emits
`warning: garbage found: .git/worktrees/wt-crash-rootcause-2026-08-09/refs` — a malformed entry in the shared
store contributed by this very worktree.

**Threshold caveat (why confidence is med, not high):** git concurrency tracks ACTIVE sessions. At S6.2's
design point (~10 active) it stays ~0.9 and nothing contends. It is 150-ACTIVE that produces ~13 concurrent
git processes. S6's own fork-rate cross-over (2,376/s at concurrency 4 vs 1,255/s at 16) says per-session
work SATURATES, which argues the active count — not residency — is the variable to watch.

### (h) OAuth refresh herd — and the rescue path that is disabled exactly at the design point

**Measured.** The keychain item is per-config-dir: `Claude Code-credentials-<sha256(CFG_DIR)[:8]>`
(`scripts/relogin-probes/e1-concurrent-logins.sh:9-11`), so the four accounts do **not** contend with each
other. `.credentials.json` is absent in all four config dirs ⇒ the credential is keychain-resident and
`securityd` (2.0% CPU) is in the path. `.oauth_refresh.lock` is **absent in all five config dirs** — the
Aug-2 dangling-symlink defect is fixed (`1677218f`).

**Derived, from a documented incident.** Within ONE config dir, N sessions share ONE credential ⇒ ONE expiry
instant AND ONE `.oauth_refresh.lock`. At 150 sessions over 4 accounts that is ~37 sessions per lock, all
waking to refresh in the same moment. proper-lockfile's contention failure is `lock_timeout` — precisely the
Aug-2 symptom, whose consequence was a forced `/login`. And refresh tokens **rotate** (measured, not cited:
`next` rt `0023ef9690b1 → a9f8aadf29eb` across one grant), so a losing racer that proceeds presents a stale
refresh token → `invalid_grant` → **account-wide** logout. Blast radius is ~37 sessions, not one.

🚨 **The existing rescue is structurally unavailable at 150.** `claude-accounts`' `heal()` bypasses the lock
but "refuses to run while an account has live sessions" (`forced-relogin-rootcause-2026-08-02.md`). At 150
resident, no account is ever idle — so the mechanism that has been silently keeping this fleet logged in can
never fire. This is the same shape as the crash doc's §4 finding: *the relief machinery is disabled by the
condition it relieves.*

Not a kernel table; not raisable by sysctl. Remedy is architectural: one refresh owner per account, or
per-slot config dirs with their own grants (e1 Variant A — the probe exists, is human-gated, and its verdict
is still unrun; it is the cheapest thing on this page).

### (j) MCP child memory — the term S6.2's budget has no row for

**Measured.** 10 of 10 claude sessions carry an MCP child. 22 `chrome-devtools-mcp` processes = **2.2 per
session**, **5,073 MB** ps-RSS = 507 MB/session. By `top -l 2 -o mem` (footprint, the metric S6.0 established
as the correct one): node pid 7993 at **2,179 MB**, pid 78670 at **2,026 MB**, a tail at 280–404 MB, median
MCP proc ~150 MB.

S6.2's budget counts `claude` processes only: 150 × 232 MB = 35 GB, + ~10 GB OS = 45 GB, leaving ~19 GB for
bursts. At a conservative 150 MB × 2.2 children × 150 sessions = **49.5 GB** — which exceeds the entire
remaining budget *and* the box, before a single toolchain burst. Even at the median-only reading this is the
largest unmodelled memory term found.

**Caveat that keeps this at med confidence:** MCP presence is a per-project config fact (browsermcp /
chrome-devtools-mcp), not a per-session constant. Today it is 10/10; at 150 it may not be. But S6.2 has no
term for it at any ratio, so the budget is unconditionally incomplete.

---

## 3. The UNKNOWN rows

### (c) Vnode cache — refines N6 with a rate
`num_vnodes == maxvnodes == 263,168`: the table is pinned at max, so steady-state allocation is 100% recycle
(N6, confirmed). New here is the **rate**: 632 recycles/s and 624 newvnode calls/s over 30 s at 10 sessions,
against a lifetime mean of 4,325/s (295,748,141 recycles in 19 h) — i.e. today's ambient is ~7× below this
boot's peaks. In-use swung 73.5k–108.3k of 263,168 (28–41%).

The pressure case is derivable and worth stating: this worktree is 1,611 on-disk entries; 150 simultaneously
*touched* worktrees ≈ 242k vnodes = **92% of maxvnodes** — which a fleet-wide `git status` / ripgrep sweep
approximates. Disk size is irrelevant (8.97M FS entries exist across 382 worktrees; only ~73.5k vnodes are
live). It never returns an error; it presents as "git got slow" plus elevated sys%.

### (k) syspolicyd — the un-named consequence of 923 exec/s
77% of all unified-log volume in a 12 s stream sample came from **syspolicyd** (6,861 messages across 5
threads = 572/s), with trustd at 55/s and ecosystemanalyticsd at 68/s. syspolicyd is the Gatekeeper /
code-signing evaluator: it is on the path of **every exec**, it is a single process, and it is running at
2.9% CPU against a measured 923 exec/s. Whether it serializes at higher exec rates is unmeasured — the test
is a controlled fork-rate ramp, which this brief bans. Flagged, not claimed.

### (l) `.claude.json` — unlocked whole-file rewrite
6 distinct mtimes in 90 s on `.claude-next` (2–3 sessions), 4 on `.claude-tertiary`; the file is 160–189 KB
and a `.claude.json.backup` of byte-identical size is written alongside (tertiary: both 171,174 B, 23:36 /
23:34) ⇒ ~342 KB per save. **No lockfile exists in any config dir.** At ~37 sessions per config dir the
projected rate is ~1.2 unlocked rewrites/s of a 171 KB JSON — last-writer-wins. No corruption event was
observed here, which is why this is UNKNOWN and not YES.

### (d, sub) mds_stores — 30.2% of a core, unattributed
`mdutil -s` reports indexing **enabled** on `/` and `/System/Volumes/Data`; `mdutil -s ~/Development` returns
"unknown indexing state" and there is **no `.metadata_never_index` marker** under `~/Development/.worktrees`.
The prior census found `mdfind` returns 0 under that path (effectively unindexed), yet `mds_stores` sampled
at **30.2% CPU** — the single largest daemon consumer measured. Not the FSEvents term (no fleet process holds
`/dev/fsevents`), and not attributed here.

---

## 4. Ceiling sources and raisability (SIP is ENABLED)

| ceiling | value | source | raisable with SIP on? |
|---|---|---|---|
| `kern.maxproc` | 16000 (stock 4000) | sysctl | **yes — already raised on this box** |
| `kern.maxprocperuid` | 10666 (stock 2666) | sysctl | **yes — already raised** |
| `kern.maxfiles` | 491520 (stock 245760) | sysctl | **yes — already raised** |
| `kern.maxfilesperproc` | 245760 | sysctl | yes |
| `kern.maxvnodes` | 263168 | sysctl | yes (same writable class) |
| `kern.num_threads` | 81920 | sysctl | yes |
| `kern.tty.ptmx_max` | 511 (STOCK) | sysctl; `/dev/ttys%03d` caps at ~999 | yes to ~999, then architectural |
| **`PID_MAX`** | **99999** | XNU `bsd/sys/proc_internal.h`: `#define PID_MAX 99999` / `#define NO_PID 100000` | **NO — compile-time constant, no sysctl** |
| mach port space | unknown | `lsmp` needs root | **unmeasurable non-sudo — flagged** |

The "already raised" column is the evidence that this class is writable under SIP: three sysctls sit at
non-stock values on a box reporting `System Integrity Protection status: enabled`. Persistence is currently
unwired — no `/etc/sysctl.conf`, no `boot-args` set — so any raise needs a LaunchDaemon to survive reboot.

---

## 5. 🚨 Correction to `crash-rootcause-2026-08-09.md` §2 — the PID-wrap co-factor is refuted

The ledger's closing note reads: *"both panics landed within 2 % of `PID_MAX` at a ~23.5 k-forks/day rate — a
linear clock correlated with uptime, flagged and not excluded."*

**Measured today, at 10 sessions:** the pid counter was observed at 99,917 at 23:15; minutes later a fresh
`/bin/sh -c 'echo $$'` returned **32,014** — an observed wrap. Seven samples at 15 s intervals over 105 s
gave 1024 / 776 / 846 / 1097 / 1083 / 715 pid/s, **mean 923/s**, while the process table stayed flat at
921–927 (so these are all short-lived forks, not accumulation).

- **Wrap interval = 99,999 ÷ 923 = 108 seconds.** The space wraps ~797×/day.
- True allocation rate ≈ **79.7 M pids/day vs the doc's 23.5 k — 3,392× off.** The doc's figure was derived
  from pid-value ÷ uptime **assuming zero wraps**, which is the whole error.
- Therefore "within 2 % of PID_MAX" carries a ~2 % prior at any random instant and is **coincidence, not a
  clock**. This co-factor can be excluded, which the doc explicitly left open. It also independently
  corroborates the doc's own conclusion via panic #6 (38-minute uptime): the storm is acute, not accumulative.

**What replaces it is a live correctness hazard, not a capacity ceiling.** Any pid stored and later re-checked
or signalled >108 s after capture can name a **different** process. Census of the exposure:
85 `kill -0` sites, 51 kill-by-stored-pid sites, 8 `ps -p $STORED` sites, and 15 files carrying pid files —
including `scripts/handoff-fire.sh`, `hooks/lead-crash-watchdog.sh`, `scripts/team-orphan-reaper.sh`,
`scripts/lead-supervisor.sh`, `scripts/lead-reconciler.sh`, `hooks/session-end.sh`.

This is the fleet's own indexed failure class arriving on a new axis (`kill-on-reaped-child`,
`argv-is-sampling-cwd-is-durable`, `pgrep-f-matches-agent-briefs`, `liveness-proxy-cannot-be-output-age`).
**It does not get meaningfully worse at 150** — S6's cross-over shows fork rate saturates (2,376/s at
concurrency 4 vs 1,255/s at 16), so the wrap interval stays in a 40–110 s band. It is already at its worst
today. Remedy: a pid is not an identity — pair it with process start time (`ps -o lstart=,pid=`) or the
cwd/argv hash the fleet already uses elsewhere.

---

## 6. 🚨 Correction to `iterm2-freeze-30-sessions-2026-07-30.md` — incident #0 was not a port ceiling

The incident-#0 header and the crash ledger's row 0 both name the mode **"WindowServer mach-port/window
saturation"**. Its own §2 evidence does not support the port half:

- Port growth was **4,711 → 4,743 in ~10 min = 0.053 ports/s.** Against any plausible port-space ceiling
  (10⁵–10⁶) that is **22+ days** away. Ports were a *correlate* of window creation (~16 ports/window), not a
  table approaching exhaustion.
- The measured burn was **WindowServer CPU at 92.7–99.9% sustained — one core, serialized compositing** —
  driven by a CoreAnimation `Defer Lock` storm at 142/s across only 33 contexts, with a 13.9-hour-late
  timer. iTerm2 itself sat at **0.0% CPU**. The amplifier was 98 iTerm2 window objects leaking at ~12/h that
  `close` reports success on and does not destroy.

So incident #0's binding term is **WindowServer CPU**, which **S6.1 already owns** as the render wall
(0.025 cores/pane ⇒ ~20 panes for 0.5 cores). It is not a distinct un-modelled ceiling; it is the render term
with a terminal-specific multiplier bolted on.

**And that multiplier is gone.** Measured under the current terminal: `kitty @ ls` reports **3 OS windows for
9 panes** (0.33 NSWindow/pane) against iTerm2's 8 real + 98 zombie windows at 39 sessions; WindowServer RSS
over 120 s at 0.5 Hz went **243,984 → 241,840 → 232,176 → 228,832 → 229,152 KB** — flat-to-declining, not
monotonic growth. iTerm2 is not running.

**Instrument gap, stated rather than papered over:** `lsmp -p` fails with `task_for_pid() failed` **even on
this session's own pid** — it needs root or an entitlement, so mach-port *occupancy* is unmeasurable
non-sudo on this box, exactly as `ptmx` occupancy was. The RSS trend and the window census are proxies; a
direct port count would need one `sudo lsmp -p 371`.

---

## 7. Adversarial self-pass — what would flip each NO

| NO term | flip evidence |
|---|---|
| (a) Mach ports | Returning to iTerm2 (or any terminal minting one NSWindow per pane); or WindowServer RSS/port count rising monotonically over a multi-hour window at constant pane count. One `sudo lsmp -p 371` settles it directly. |
| (b) fd table | Per-session fd count growing with session age (a leak) — not observed across 5 sessions of differing age; or any single proc approaching `maxfilesperproc` 245,760. Current headroom is 3 orders of magnitude. |
| (d) kqueue/FSEvents | Any `claude` proc opening `/dev/fsevents` (would appear if CC enabled recursive `fs.watch`); or fseventsd CPU rising super-linearly in fleet write rate. |
| (e) logd | logd CPU >20%, or Persist growth >200 KB/s (17× today's 11.37 KB/s). |
| (f) PID wrap as *capacity* | Nothing — PID_MAX is not exhaustible, only recyclable. The hazard verdict (reuse) is already YES and needs no flip. |
| (i) disk/swap | Swapfile count >30 (the death band was 66–68), or free space <100 GB against today's 4.9 TB. |

**Three gaps this pass opened and closed with real calls, not assumptions:**

1. **An instrument trap I had already fallen into.** `lsof -p <pid> -i` is an **OR**, not an AND — it
   returned 374 "per-session" inet fds that were actually the system-wide total (255 by direct count). Re-run
   with `lsof -a -p <pid> -i`: the true figure is **2–7 established sockets per session**. Had this stood, the
   fd row would have read ~56k sockets at 150 and been wrongly escalated.
2. **MCP children were absent from my own decomposition and from S6.2's budget** — and turned out to be the
   largest unmodelled number on the page (§2j). The brief asked about MCP only under the *fd* term, where it
   is irrelevant; the memory axis is where it binds.
3. **`log stats` hangs >120 s** on this box (killed at the timeout) and `log config` needs root. The log
   verdict therefore rests on a `du` delta plus a 12 s `log stream` producer sample, not on the canonical
   instrument — which is what surfaced syspolicyd (§3k) as a term nobody had named.

**Named residual uncertainties:** mach-port occupancy (needs root); the herd size at which proper-lockfile
returns `lock_timeout` (needs a controlled ramp); whether MCP presence stays 10/10 at 150; whether syspolicyd
serializes above ~1k exec/s; `mds_stores` at 30.2% CPU is measured but unattributed.
