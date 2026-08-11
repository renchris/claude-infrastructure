# MCP memory census — live trees, ownership, true cost

**Measured** 2026-08-10 22:23–22:52 local, Darwin 24.6.0 (macOS 15.6.1), Apple M1 Max, 10 cores,
64 GiB (`sysctl hw.memsize` = 68719476736). 1199 procs at t1, 1277 at t3. System-wide memory free 88%
(`memory_pressure`). All figures MEASURED unless tagged `[inferred]`.

---

## Verdict (answer first)

**The claim "~507 MB of MCP server children per session, uncounted" is false as a per-session figure
and roughly right for the 3 sessions it actually applies to.** MCP costs **0 bytes** in 16 of 19
resident Claude Code sessions, because only 3 sessions have a stdio MCP server configured at all.
The whole MCP population on this box is **1213 MB phys_footprint / ~945 MB true RAM** — that is
**~64 MB amortized per session**, not 507 MB.

Two corrections to the lead's earlier reading dominate everything else:

1. **The lead's 873 MB missed an entire Google Chrome tree** (4 procs, 577 MB RSS / 196 MB footprint)
   because Chrome's argv contains no `mcp` substring. It is a genuine MCP child — puppeteer-spawned
   by `chrome-devtools-mcp --isolated`.
2. **RSS is the wrong instrument here and overstates by 1.5–2.8x.** Chrome's parent reads RSS 274 MB
   but `phys_footprint` **96.5 MB** — the rest is shared clean framework pages. Conversely the 23-hour
   idle chain reads RSS 141 MB but footprint 322 MB, because 294 MB of it is in the compressor and
   RSS cannot see it.

---

## 1. The tree table

Four MCP tree roots exist on the box. `RSS1` = t1 snapshot, `RSS3` = t3 (+5m52s later). `FOOT` =
`footprint -p` phys_footprint. `CMPRS` = `top -l1 -stats pid,cmprs` (original, pre-compression size —
see section 6). Owner column: session pid, cwd basename, `CLAUDE_CONFIG_DIR` -> account.

### Tree A — session 6687 · `wt-w2-provisioning-console` · `.claude-secondary` -> chris.swe+claude@outlook.com

| pid | ppid | argv (truncated) | etime | RSS1 | RSS3 | FOOT | CMPRS |
|---|---|---|---|---|---|---|---|
| 7217 | 6687 | `npm exec chrome-devtools-mcp@latest --isolated` | 11:16:16 | 156 | 146 | 116 MB | 7.3 MB |
| 14014 | 7217 | `chrome-devtools-mcp` (retitled node) | 11:16:11 | 254 | 237 | 187 MB | 10 MB |
| 14588 | 14014 | `node …/chrome-devtools-mcp/build/src/telemetry/watchdog/main.js --parent-pid=14014 --app-version=1.7.0` | 11:16:11 | 170 | 158 | 110 MB | 2.8 MB |
| **27180** | **14014** | **`/Applications/Google Chrome.app/…/Google Chrome --remote-debugging-pipe --user-data-dir=/var/folders/…/puppeteer_dev_chrome_profile-UHs9QU`** | 10:52:49 | 274 | 230 | 98 MB | 25 MB |
| 31969 | 27180 | Google Chrome Helper (renderer) | 10:52:43 | 139 | 107 | 53 MB | 16 MB |
| 31988 | 27180 | Google Chrome Helper | 10:52:43 | 96 | 79 | 25 MB | 14 MB |
| 32036 | 27180 | Google Chrome Helper | 10:52:43 | 66 | 50 | 20 MB | 14 MB |
| | | **TREE A TOTAL (7 procs)** | | **1155** | **1007** | **609 MB** | **89 MB** |

### Tree B — session 88196 · `wt-cc-232530-26432` · `.claude-tertiary` -> ren.chris+claude@outlook.com

| pid | ppid | argv | etime | RSS1 | RSS3 | FOOT | CMPRS |
|---|---|---|---|---|---|---|---|
| 88728 | 88196 | `npm exec chrome-devtools-mcp@latest --isolated` | 23:23:42 | 45 | 45 | 117 MB | 107 MB |
| 95531 | 88728 | `chrome-devtools-mcp` | 23:23:35 | 47 | 47 | 98 MB | 91 MB |
| 95588 | 95531 | watchdog `main.js --parent-pid=95531 --app-version=1.6.0` | 23:23:34 | 49 | 49 | 107 MB | 96 MB |
| | | **TREE B TOTAL (3 procs)** | | **141** | **141** | **322 MB** | **294 MB (91%)** |

**No Chrome.** This chain is 23 h old, idle, and 91% compressed. Note `app-version=1.6.0` vs 1.7.0 in
Trees A/C — `@latest` resolved differently at spawn time, so long-lived sessions pin stale server builds.

### Tree C — session 34548 · `wt-pool-2` · `.claude-secondary` -> chris.swe+claude@outlook.com

| pid | ppid | argv | etime | RSS1 | RSS3 | FOOT | CMPRS |
|---|---|---|---|---|---|---|---|
| 36921 | 34548 | `npm exec chrome-devtools-mcp@latest --isolated` | 15:16 | 110 | 104 | 71 MB | 5.5 MB |
| 48346 | 36921 | `chrome-devtools-mcp` | 15:08 | 169 | 154 | 100 MB | 5.7 MB |
| 49988 | 48346 | watchdog `main.js --parent-pid=48346 --app-version=1.7.0` | 15:07 | 150 | 153 | 111 MB | 4.2 MB |
| | | **TREE C TOTAL (3 procs)** | | **429** | **411** | **282 MB** | **15 MB** |

**No Chrome.** Fresh chain (spawned ~1 min after its session started).

### Tree D — Cursor (not Claude Code) · app pid 13323

| pid | ppid | argv | etime | RSS1 | RSS3 | FOOT | CMPRS |
|---|---|---|---|---|---|---|---|
| 14315 | 13323 | `Cursor Helper: mcp-process` | 04:39:21 | 149 | 149 | 64 MB | 0 |

---

## 2. Totals and the true-RAM reconciliation

| | RSS t1 | RSS t3 | phys_footprint | CMPRS | **true RAM [inferred]** |
|---|---|---|---|---|---|
| Tree A (incl. Chrome) | 1155 | 1007 | 609 MB | 89 | **549 MB** |
| Tree B | 141 | 141 | 322 MB | 294 | **125 MB** |
| Tree C | 429 | 411 | 282 MB | 15 | **271 MB** |
| **CC-owned MCP total** | **1725** | **1559** | **1213 MB** | **399** | **~945 MB** |
| + Cursor mcp-process | 1874 | 1708 | 1277 MB | 399 | **~1009 MB** |

`true RAM = (footprint - CMPRS) + CMPRS / 3.02`, where 3.02 is this box's live compressor ratio
(`vm_stat`: 5393 MB stored / 1787 MB occupied). Labelled `[inferred]` because it composes two
measured quantities under an assumption argued in section 6.

**Against the box:** CC-owned MCP ~= **945 MB of 64 GiB = 1.4%**. The 19 CC session processes
themselves are 13.31 GB RSS / ~6.7 GB footprint, and 13 teammate procs a further 7.47 GB RSS.
MCP is roughly **one seventh** the footprint of the sessions it hangs off.

---

## 3. The denominator — and why the "~100 sessions" premise is wrong

Counted by **argv[0] binary path**, never `pgrep -f`:

```
awk 'NR>1 && $5 ~ /\/\.bin\/claude$/ {print $1}' snap | wc -l   ->  19
awk 'NR>1 && $5 ~ /claude\.exe$/     {print $1}' snap | wc -l   ->   8  (13 by t3)
pgrep -f claude | wc -l                                          -> 283   <- argv pollution
```

**19 resident CC sessions**, not ~100. `pgrep -f claude` reads 283 because agent briefs, hook paths
and `/Users/chrisren/.claude*/` strings appear in unrelated argv. The 8->13 `claude.exe` procs are
teammates/subagents, not sessions.

| config dir | account | sessions | with >=1 MCP child |
|---|---|---|---|
| `.claude-secondary` | chris.swe+claude@outlook.com | 7 | **2** (6687, 34548) |
| `.claude-quaternary` | chris.claudecode@outlook.com | 6 | 0 |
| `.claude-next` | ichris96+claude@hotmail.com | 4 | 0 |
| `.claude-tertiary` | ren.chris+claude@outlook.com | 1 | **1** (88196) |
| (exited mid-census: pid 50407) | — | 1 | — |
| **total** | | **19** | **3 (15.8%)** |

**Zero sessions run on `~/.claude`.** That single fact explains the browsermcp mystery (section 4).

---

## 4. Config topology — the real cost driver

| server | scope | transport | spawns a local process? |
|---|---|---|---|
| `motion`, `motion-plus` | user, in **every** `.claude*/.claude.json` | `http` (`https://mcp.motion.dev`) | **No** — 0 bytes |
| `uidotsh` | project (`.mcp.json` in reso worktrees) | `http` | **No** — 0 bytes |
| `chrome-devtools` | project (`.mcp.json` in reso worktrees) | **stdio** (`bash scripts/mcp/chrome-devtools-mcp.sh`) | **Yes** — the entire cost |
| `browsermcp` | user, in **`$HOME/.claude.json`** | stdio (`npx -y @browsermcp/mcp@latest`) | Yes — but unreachable |

**Zero browsermcp processes because no live session uses `~/.claude` as its config dir.** browsermcp
is declared user-scope in `$HOME/.claude.json` (and project-scope for `reso-upgrade-dependencies`),
but all 19 sessions run under `.claude-next/-secondary/-tertiary/-quaternary`, whose own
`.claude.json` files declare only the two http motion servers. The config is live but orphaned from
the fleet. *(The brief's premise "user-scope stdio config in primary ~/.claude.json" is correct; the
inference that sessions would therefore spawn it is not.)*

Swept `.mcp.json` across all 19 session cwds: **exactly 3 declare a stdio server**, all
`chrome-devtools`, all in reso worktrees. The other 16 (claude-infrastructure and its worktrees,
`/private/tmp/wt-multiprovider`) have no `.mcp.json` at all -> structurally 0.

**Spawn timing, measured:** the node chain starts **at session start** (Tree C: session etime 10:22,
chain 09:24 — ~1 min later), not on first tool use. Chrome starts **lazily on first browser action**
(27180 etime 10:52:49 vs its parent 14014 at 11:16:11 — 23 min later). So the node chain's ~280 MB
is unconditional for any reso session; Chrome's ~196 MB is conditional on actually browsing.

---

## 5. Orphans and hidden servers — both negative, checked by ancestry

- **No orphaned MCP processes.** `awk '$2==1'` over the snapshot returns no MCP/node process
  re-parented to pid 1. Every MCP proc has a live CC session ancestor. (One `Google Chrome` proc at
  ppid 1 — pid 31677 — is `chrome_crashpad_handler`, 5 MB, unrelated.)
- **No hidden MCP servers under any session.** Walked *every* descendant of all 19 sessions
  recursively rather than argv-matching. Non-MCP descendants are all trivial: `caffeinate -i -t 300`
  (~3.4 MB x 10), `bats` test procs, `sleep 15`, `cc-await-ping`.
- **Teammates spawn no MCP servers of their own.** Walked all 13 `claude.exe` descendants — only
  `sleep`, `ps`, `head`, `ugrep`. Subagents share the parent session's MCP clients, so MCP cost
  scales with **sessions**, not sessions x teammates. This is the load-bearing scaling finding.

---

## 6. Growth signal — the direction is DOWN, not up

Over the 5 m 52 s between t1 and t3, with real work running throughout:

| tree | RSS t1 | RSS t3 | delta |
|---|---|---|---|
| A | 1155 | 1007 | **-148 MB (-12.8%)** |
| B | 141 | 141 | 0 |
| C | 429 | 411 | -18 MB (-4.2%) |
| Cursor | 149 | 149 | 0 |

**MCP RSS decays; it does not grow.** The mechanism is visible in the cross-section: the *oldest*
chain (Tree B, 23 h) has the *smallest* RSS (141 MB) and the largest compressed share (91%), while
the *newest* (Tree C, 15 min) has 411 MB RSS and 5% compressed. Idle MCP servers get paged into the
compressor and their live-RAM cost falls by ~3x. Any model that projects MCP memory as monotonic
growth over session age is inverted.

**CMPRS semantics, resolved by measurement** (this was the one number that could have flipped the
verdict): box-wide `sum(top CMPRS) = 4047 MB`, against `vm_stat` **stored** 5393 MB (original size)
and **occupied** 1787 MB (in-RAM compressed size). 4047 tracks 5393, not 1787 -> **CMPRS reports the
original, pre-compression size**, and so does `phys_footprint`'s compressed component. Hence Tree B's
322 MB footprint overstates its live RAM by ~197 MB.

---

## 7. Adversarial pass — what would make these numbers wrong

Ran as a deliberate falsification sweep; three of five found something.

1. **Shared-memory double-count — REAL, and it cuts against RSS.** Summing RSS across the Chrome tree
   double-counts the Chrome framework. `vmmap --summary 27180`: `TOTAL VIRTUAL 99.4G / RESIDENT
   973.3M / DIRTY 96.5M`, with `ReadOnly portion of Libraries: Total=1.9G resident=685.2M`. Only
   96.5 MB is dirty. Chrome tree: **577 MB RSS vs 196 MB footprint**. Footprint is the number that
   reflects memory pressure. Residual risk: summing footprint across a tree still double-counts
   shared *dirty* pages; for these trees that is small (`__DATA_DIRTY` is 823 KB on Chrome, 232 KB on
   the node procs), so the section-2 totals are an upper bound of a few percent.
2. **Compressed pages — REAL and large.** Section 6. Without this correction Tree B would have been
   reported at 322 MB when it costs ~125 MB.
3. **Sampling moment — REAL, and it indicts a different subject entirely.** At t2 a *sibling agent's*
   `ugrep -G --ignore-files --hidden` (pid 26140, 48 s old) held **5944 MB RSS** — three times the
   entire MCP population — and had exited by the time I queried it 20 s later. Also caught: a `grep
   -rl '"name":"mcp__browsermcp'` at 29 MB, and session pid 50407 exiting mid-census. **The largest
   memory events on this box are transient greps from research fan-out, not MCP servers.** Any MCP
   figure quoted without a co-measured session/transient baseline will mis-attribute the pressure.
4. **Is the Chrome tree really attributable to MCP?** Yes, three ways: ppid chain 27180->14014
   (`chrome-devtools-mcp`); `--user-data-dir=…/puppeteer_dev_chrome_profile-UHs9QU` (a puppeteer
   throwaway profile, not the user's browser); `--remote-debugging-pipe`, so it dies with the pipe.
   It is not the user's Chrome — the user's Chrome is not running (5 Chrome procs total, 4 in this
   tree + 1 crashpad handler).
5. **Did an awk field-split hide a process?** Yes, and I caught it. `$5 ~ /\/node$/` silently missed
   the watchdog procs because their path is `/Users/chrisren/Library/Application Support/fnm/…` —
   the space in "Application Support" breaks field 5. Re-swept by reassembling the full command
   string; the corrected sweep returned the same 14 MCP procs, so the table is unaffected — but a
   space-split census on this box under-reports node procs by construction.

---

## 8. What this implies at 150 sessions [inferred]

Per-session calibration measured on 5 procs: CC sessions are **RSS 739–812 MB but footprint
267–442 MB** (mean ~353 MB) — RSS overstates sessions by ~2.2x too.

- **Sessions, not MCP, are the wall.** 150 x ~353 MB footprint ~= **53 GB on a 64 GiB box**, before
  MCP, before teammates (13 concurrent x ~250 MB ~= 3.3 GB), before transient greps that spike 6 GB.
- **MCP at the same scale:** if the reso share holds at 15.8%, ~24 chains x ~200 MB true RAM ~= 4.8 GB,
  plus Chrome on however many actually browse (+150 MB true RAM each; currently 1 of 3). Call it
  **5–7 GB, or ~10% of the session cost.** Worth fixing, not the binding constraint.
- **The cheap lever, if one is wanted:** the node chain is 3 processes per session (`npm exec`
  wrapper -> `chrome-devtools-mcp` -> telemetry watchdog) and the `npm exec` wrapper alone is
  71–156 MB RSS / 71–116 MB footprint doing nothing but holding a child. Invoking the server binary
  directly instead of through `npm exec … @latest` would drop ~1/3 of the chain and stop `@latest`
  resolving to divergent versions per session (1.6.0 vs 1.7.0 observed live).

---

## 9. Uncertainties named

- **`phys_footprint` summed across a tree** is an upper bound; shared dirty pages are charged to more
  than one task. Bounded small here (`__DATA_DIRTY` <= 823 KB/proc) but not zero.
- **The 3.02:1 compressor ratio is box-wide**, not per-process. A process whose pages compress worse
  than average would have more true RAM than section 2 credits it.
- **`ps` RSS vs `vmmap` RESIDENT disagree by ~3.5x** on Chrome (274 MB vs 973 MB). I did not resolve
  which accounting `ps` uses on Darwin 24.6; I sidestepped it by reporting footprint as the cost
  measure and RSS only for growth deltas, where the *ratio* is what matters.
- **n=1 on Chrome.** Exactly one MCP chain has ever spawned a browser, so the 196 MB Chrome figure is
  a single observation, and `phys_footprint_peak` for its renderer (31969) was **412 MB** against a
  current 52 MB — an 8x swing. Peak Chrome cost is much worse than steady-state.
- **The 15.8% MCP-bearing share is a snapshot of work-in-flight**, not a structural constant. It is
  entirely determined by how many sessions happen to be cwd'd in a reso worktree right now.
- **One session (50407) exited during the census** and its MCP status is unknown; it is counted in
  the denominator of 19 and excluded from the 3.

---

## Appendix — commands behind every number

```bash
ps -axo pid,ppid,rss,etime,command                     # snapshots t1/t2/t3
awk -v root=PID -f /tmp/mcptree.awk snap               # BFS descendant walk + RSS sum
awk 'NR>1 && $5 ~ /\/\.bin\/claude$/ {print $1}'       # denominator by binary path
ps eww -p PID -o command= | grep '^CLAUDE_CONFIG_DIR=' # config dir per session
lsof -a -p PID -d cwd -Fn                              # cwd per session
footprint -p PID | grep phys_footprint:                # true charge
top -l1 -stats pid,command,mem,cmprs,purg -o mem       # compressed split
vmmap --summary PID | grep -E 'Physical footprint|TOTAL'
vm_stat | awk '/compressor/'                           # compressor ratio 5393/1787 = 3.02
ps -p 27180 -o command= | tr ' ' '\n' | grep -E 'user-data-dir|remote-debugging'
awk 'NR>1 && $2==1' snap | grep -Ei 'mcp|node '        # orphan check
python3 -c "json.load(open('<dir>/.claude.json'))['mcpServers']"   # config topology
```

Snapshots retained at `/tmp/mcpcensus-snap{1,2,3}.txt`; tree walker at `/tmp/mcptree.awk`.
