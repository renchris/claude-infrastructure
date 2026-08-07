# Concurrency census — what actually saturates the M1 Max, measured 2026-08-07

**Why this file exists.** A reso session hit the `handoff-fire.sh` capacity gate, investigated the
box, and produced numbers that live nowhere else. The machine's state changes hourly, so
re-measuring later gives *different* numbers, not the same ones. This is the baseline any
concurrency work should start from rather than re-derive.

**Hardware:** MacBook Pro 16" M1 Max, **10 cores, 64 GB**. Terminals: kitty **and** iTerm2, both
live simultaneously. Measured across ~90 minutes, 00:48–02:30 local.

**The headline, and it is arithmetic rather than opinion:**

> The operator's goal is ~100 concurrent Claude Code sessions. **At the measured 511 MB/session,
> 100 sessions is 51.1 GB of a 64 GB box** — before dev servers, before a single 2.4 GB `eslint`
> run, before macOS and a browser. **100 local sessions is not reachable on this hardware**, and no
> display-layer change (tmux, session switcher, detached panes) alters that. Reaching 100 requires
> sessions that do not live on this machine.

---

## 1 · What is running (the correction that matters most)

**There is nothing meaningful to reclaim. The box is honestly oversubscribed, not leaking.**

| class | measured |
| --- | --- |
| Claude Code panes (tty-attached) | **14** |
| `claude` processes total | **47–48** — 13 top-level + 35 children |
| …of which orphaned | **0** — zero dead-parent (`ppid==1`), zero detached (no tty) |
| RSS distribution | **23 procs at ~1 MB** (shell wrappers/shims — effectively free) · **~10 at 367–588 MB** (the real node runtimes) |
| **total claude RSS** | **7,148 MB** |
| **per-session aggregate** | **511 MB** (7,148 ÷ 14) |
| `next dev` servers | **5 worktrees × 2 procs = 10**, totalling **9,580 MB** |
| gates in flight (one sample) | 713 MB; at another, **two concurrent `eslint` at 2,381 MB and 2,434 MB**, 38–39% CPU each |
| memory free | **69–73%**, **swap 0.00 MB** (not swapping at 14 sessions) |

🚨 **The process COUNT is not the cost.** 47 processes sounds alarming and is not: half are ~1 MB
wrappers. The cost is ~one heavy runtime per session. Any "reduce process count" work aimed at the
47 would optimise the free half.

### Dev servers — every one of them is legitimate

| worktree | RSS | age |
| --- | --- | --- |
| `wt-cc-001759-77337` | **5,024 MB** | 1h59 |
| `wt-cc-152400-19682` | **2,930 MB** | 12m |
| `wt-cc-225106-82355` | 595 MB | 2h57 |
| `bs-deck-retarget` | 430 MB | 1h19 |
| `bs-spacing-header` | 393 MB | 3h16 |

Every one resolved `DIR-OK/wt-ok` — live directory, live git worktree. **None orphaned.**

⚠️ **This corrects a wrong reading made during the same session.** The first pass saw twelve
`next dev` processes at **0.0% CPU** and called them orphaned dead weight (~8 GB to reclaim). They
are not: an idle Next dev server sits at 0% CPU and is perfectly alive. **0% CPU is not evidence of
abandonment** — resolve the process's `cwd` and test the directory (`lsof -a -p <pid> -d cwd` +
`git -C <cwd> rev-parse --is-inside-work-tree`). A whole remediation track was scoped on the wrong
reading before this check ran.

---

## 2 · Where the CPU goes

Load samples (10 cores; `handoff-fire.sh` gate ceiling is `CC_FIRE_MAX_LOAD_PER_CORE=2.0`, i.e. 20.0):

```text
23.51            → gate refused at 2.35/core
24.62 28.03 41.96
22.93 34.23 40.12   ← after a 9-min wait; 1-min fell, 5-min ROSE
26.84 29.56 32.33
35.92 31.49 32.71
61.86 36.82 33.77   → 6.2/core
```

The gate refused four times. **Given 14 sessions on 10 cores, refusing a 15th is arguably correct
behaviour, not a bad metric** — an early hypothesis that load average was "measuring the wrong
thing" was built on the orphan misreading above and should be dropped.

### Top consumers, by class

| class | cost | note |
| --- | --- | --- |
| **gates** | 2 × `eslint` at ~2.4 GB, 38–39% CPU | `eslint src/ lib/ replicache/ --cache --cache-location .eslintcache` — see §3 |
| **hooks** | `grep -hoE 'HANDOFF-RECYCLE-DEAD…'` at **49.4%**, a `find` over a worktree at **13.9%** | the monitoring is a top-5 CPU consumer, and it scales with session count |
| **display** | WindowServer **35.4%** + kitty **17.3%** + iTerm2 **9.6%** = **0.62 cores**, 810 MB | ~2% of total load |

🔑 **Free win: kitty and iTerm2 are both running.** 27% of a core across two emulators for one
operator. Consolidating to one is the cheapest available saving and costs nothing architecturally.

---

## 3 · The eslint finding — N worktrees pay N cold full-tree lints

`package.json` (reso, `origin/main`):

```json
"lint": "eslint src/ lib/ replicache/ --cache --cache-location .eslintcache"
```

`.eslintcache` is **worktree-local**. Two concurrent runs were observed in *different* worktrees
(`wt-pool-2`, `wt-f8f182674419`), each ~2.4 GB. So every worktree pays a **cold** full-tree lint;
the cache never amortises across the fleet. With a fleet target of dozens of worktrees this scales
linearly and is likely the single largest controllable CPU+RAM cost.

Note the pre-commit hook already lints **staged files only** — the 2.4 GB runs are the full-tree
`pnpm lint` (pre-push / manual gate), not the commit path.

**Cheapest fixes, in order:** share the cache across worktrees · scope the gate to changed files ·
only then consider a faster engine.

---

## 4 · oxlint/oxc as a replacement — analysed and rejected as a "byte-identical port"

The operator asked whether a Fable-tier session should build a byte-identical `oxlint`/`oxfmt`/`oxc`
equivalent of reso's `eslint.config.mjs`. **No** — and the blockers are categorical, not
"unimplemented yet". Composition of that config (read from `origin/main`, 29 explicit rule entries):

| bucket | count | oxc story |
| --- | --- | --- |
| airbnb **linting** (`eslint-config-flat-airbnb`) | 140 | Mostly portable; coverage + default *options* still need a mechanical audit |
| airbnb **stylistic** | 78 | 🚫 **Category mismatch.** oxc puts formatting in `oxfmt`, a Prettier-style formatter — one opinionated output, not 78 independently configurable rules. `@stylistic/semi: 'never'` + `object-curly-newline` + 76 others are not expressible as formatter settings |
| airbnb imports | 14 | likely portable |
| `@pandacss/*` | 9 uses | 🚫 no eslint-plugin ABI in oxlint; encodes Panda token/config semantics |
| `reso-design/*` | 4 uses | 🚫 local plugin (`./eslint-rules/index.mjs`) — `use-focus-ring-token`, `no-imported-call-in-css`, `no-ungated-db-export`, `no-raw-bottle-picture` |
| `tailwindcss/*` | plugin | 🚫 same |
| `@typescript-eslint/no-unnecessary-condition` | 1 | ⚠️ **type-aware** — needs full type info; oxlint's `tsgolint` path is early. **Verify live before relying on it** |
| react / jsx-a11y / `@next` | 7 / 5 / 1 | likely portable |

🔑 **The 13 plugin/custom rule-uses are the ones that actually bite.** `@pandacss/no-hardcoded-color`,
`@stylistic/object-curly-newline` and `reso-design/*` all fired on real code during the session that
wrote this. A port that drops precisely those keeps the speed and loses the value.

**Achievable shape instead:** two tiers — oxlint as a fast pre-filter for the ~140 portable linting
rules (milliseconds, no 2 GB node heap), eslint retained as authoritative for stylistic + the 13
plugin/custom + the type-aware rule. Opus work, not frontier.

---

## 5 · The path to ~100 sessions

| lever | saving | verdict |
| --- | --- | --- |
| **Move sessions off the box** (cloud/remote) | unbounded | **The only lever that scales past the hardware.** Entitlement is per-account and gated — check `/accounts`, do not assume |
| Consolidate to one terminal emulator | ~0.3 cores, free | do it |
| Shared eslint cache / changed-files scoping | kills N × 2.4 GB cold lints | highest local win |
| Fewer dev servers (stop when idle) | 1.9 GB per worktree | real; 5 running = 9.6 GB |
| tmux / detached panes | **0.6 cores, 0.6 GB (~2%)** | ⚠️ **not worth it for load** — and it costs a rewrite of the whole session lifecycle, which is built on the iTerm2 python API (`it2` shim, `handoff-fire.sh`, `--recycle`, `self-close --successor`, teammate spawning). Do it because you *cannot draw 100 panes*, not for CPU |
| Session switcher ("left arrow") | unknown | Settle by measurement: `ps -Ao command \| grep -c 'node_modules/.bin/claude'` before/after. Unchanged ⇒ a view over existing processes ⇒ **zero** load benefit. Baseline at 14 panes: **47** |

**Remote-viability by work type** — cloud helps less than it first appears:

- ✅ **repo-only work** (lint config, rule audits, refactors) — no browser, no local state
- ❌ **visual design** — every measurement in the originating session ran through the local browser
  (chrome-devtools MCP against `localhost:3554`); a sandboxed clone has neither server nor browser
- ❌ **anything about this box** — inherently local
- ⚠️ **branch banking** — the 2,304 commits across 199 unpushed branches exist *only* on this
  machine, which is the entire problem; a remote clone cannot see them

---

## 6 · Traps — do not rediscover these

- 🚨 **Never `nice` / `taskpolicy` / QoS-throttle a gate to shed load.** Deprioritising implicitly
  re-specifies every wall-clock timeout inside it: it does not slow gracefully, it **fails**. This
  fleet has already stamped a trunk RED with 11 hook-timeouts and zero assertion failures for
  exactly this reason. The tell is the failure *text* — `timed out in Nms` with no assertion
  failures means the gate could not RUN.
- **`pgrep -fc claude` returned 0** while 47 claude processes were live — pattern miss. Use
  `ps -Ao command | grep -c 'node_modules/.bin/claude'`.
- **0% CPU ≠ orphaned** (§1). Resolve `cwd` and test it.
- **A process count is not a cost** (§1) — half of them are ~1 MB wrappers.
- **The capacity gate is asymmetric:** it blocks *agent-initiated* fires only. An operator pasting
  the same payload into a fresh pane creates a byte-identical session at identical cost. That is a
  tooling asymmetry, not a real difference in load — worth deciding deliberately rather than by
  accident.

---

## 7 · Reproducing this

```bash
uptime; sysctl -n hw.ncpu hw.memsize
ps -Ao command | grep -c 'node_modules/.bin/claude'                     # session count proxy
ps -Ao rss,command | grep 'node_modules/.bin/claude' | grep -v grep \
  | awk '{s+=$1} END {printf "%.0f MB over %d procs\n", s/1024, NR}'    # total + per-session
for pid in $(pgrep -f "next-server|next/dist/bin/next"); do             # dev servers + liveness
  cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)
  echo "$pid $(ps -o rss= -p $pid) $cwd"
done
ps -Ao pcpu,rss,comm -r | head -13                                      # top consumers
```
