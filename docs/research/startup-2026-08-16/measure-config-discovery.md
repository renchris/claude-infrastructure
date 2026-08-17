# Config-discovery layer — measured 2026-08-16

Session cwd: `/Users/chrisren/Development/.worktrees/wt-cc-143835-83020`
`CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-tertiary`
Binary in use by the live fleet: **`~/.claude-220/node_modules/.bin/claude` = 2.1.220**
(NOT `~/.claude-versions/current`, which resolves to 2.1.114 — see §7 binary-identity note).
node on PATH: v22.21.1 (fnm multishell)
Box under normal load (~24 live sessions).

RAW NOTES — appended as measured. Commands verbatim.

---

## 0. Prior art read

- `R3-shell-latency.md` (+ its R6 addendum) — pre-exec zsh chain. R6 claims the chain fell
  2,713→940 ms end-to-end after removing fetch/pnpm from `cmd_claim`.
- `R4-cc-latency.md` (+ R6 addendum) — post-exec. Claims relevant to MY axis, to re-check:
  - stage 3 "settings + MDM + permission-rule load ≈ **300 ms**, blocking"
  - stage 4 "skills/commands/agents/plugins loaded in **159 ms**" (93 skills)
  - stage 5 "MCP configs resolved in **207 ms**"
  - stage 10 "first-request assembly ~200 ms"
  - R6: SessionStart hook group max **900 ms → 240 ms**
  - incidental: `~/.claude-tertiary/CLAUDE.md is over the 40.0k-char limit (62.0k chars)`
  - incidental: `Skill listing over budget: 93 skills, 46716 chars > 8000 budget`
- `R5-startup-print.md` — hook output channels, not latency. No numbers to re-check.

---

## 1. `.claude.json` — size, content, parse time

### 1a. Sizes (`stat -f%z`)

```
for d in ~/.claude.json ~/.claude/.claude.json ~/.claude-tertiary/.claude.json \
         ~/.claude-next/.claude.json ~/.claude-quaternary/.claude.json \
         ~/.claude-secondary/.claude.json; do
  [ -f "$d" ] && printf "%10d  %s\n" "$(stat -f%z "$d")" "$d"; done
```

| path | bytes | brief said |
|---|---|---|
| `~/.claude.json` | 129,406 | 129 KB ✓ |
| `~/.claude/.claude.json` | 68,848 | 69 KB ✓ |
| `~/.claude-tertiary/.claude.json` | **184,248** | 184 KB ✓ **(this session's)** |
| `~/.claude-next/.claude.json` | 174,916 | 175 KB ✓ |
| `~/.claude-quaternary/.claude.json` | 185,208 | not in brief |
| `~/.claude-secondary/.claude.json` | **205,434** | not in brief — **the biggest** |
| `~/.cc-firewall/.claude.json` | 32,521 | not in brief |

Stale backups also on disk (never read by CC, listed for completeness):
`~/.claude.json.backup` 481,958 B, `~/.claude.json.bak-mcpw2-20260811-003055` 130,466 B,
`~/.claude.json.bak-ms365-restore` 129,237 B.

### 1b. What is IN them (`/tmp/cfgsize.py`)

`~/.claude-tertiary/.claude.json`, 72 top-level keys:

| key | bytes | % | shape |
|---|---|---|---|
| `projects` | 87,777 | 47.6 % | dict, **368 entries** |
| `cachedGrowthBookFeatures` | 27,409 | 14.9 % | dict, 504 entries |
| `githubRepoPaths` | 21,094 | 11.4 % | dict, 10 entries |
| `skillUsage` | 2,663 | 1.4 % | dict, 44 |
| `tipsHistory` | 1,078 | 0.6 % | 45 |
| everything else (67 keys) | < 1 KB each | | |

🚨 **The brief's hypothesis about `history` arrays is REFUTED.** Every config dir reports
`history arrays total 0B across 0 entries`. Something already prunes per-project `history`
(all six files). The unbounded-history cold-start tax does **not** exist here.

What `projects` actually holds per entry (reso, 2,475 B): `allowedTools`, `mcpServers`,
`exampleFiles` (5 filenames), and ~20 `last*` telemetry counters incl. a `lastModelUsage`
sub-dict per model. Bounded per project; the growth axis is the **number of projects**
(368 here, 487 in `.claude-quaternary`, 409 in `.claude-secondary`) — one entry per cwd
ever visited, and every ephemeral `/tmp` worktree gets one.

`githubRepoPaths` is 21 KB for **10 keys** because one value is a 9,577-byte array of every
worktree path ever seen for `renchris/reso-management-app`.

### 1c. Parse timing — node, n=5 (`/tmp/tparse.js`)

```
node /tmp/tparse.js ~/.claude-tertiary/.claude.json   # x5
```

```
read=0.304 parse=0.997 total=1.301 ms
read=0.262 parse=0.968 total=1.231 ms
read=0.244 parse=0.911 total=1.155 ms   <- min
read=0.383 parse=1.188 total=1.571 ms
read=0.326 parse=1.408 total=1.733 ms
```

**median total 1.30 ms, min 1.16 ms.** LOWER BOUND on the binary's own cost (same V8, same
file; the binary additionally validates/normalises and may write back).

**VERDICT: `.claude.json` is NOT a startup cost.** 184 KB of JSON is ~1 ms for V8. Even the
largest (205 KB) is ~1.4 ms. This axis is a token/hygiene problem, not a latency one.

---

## 2. The settings cascade

`stat -f%z` on every layer that applies to this cwd:

| layer | path | bytes |
|---|---|---|
| enterprise (macOS) | `/Library/Application Support/ClaudeCode/managed-settings.json` | **MISSING** |
| enterprise (unix) | `/etc/claude-code/managed-settings.json` | **MISSING** |
| user (default dir) | `~/.claude/settings.json` | 36,371 |
| user local | `~/.claude/settings.local.json` | MISSING |
| **user (active dir)** | `~/.claude-tertiary/settings.json` | **36,388** |
| user local (active) | `~/.claude-tertiary/settings.local.json` | MISSING |
| project | `./.claude/settings.json` | 5,229 |
| project local | `./.claude/settings.local.json` | MISSING |

Note the two 36 KB user files are near-identical (mirrored across config dirs by
`config-mirror.zsh`); only the active dir's is read.

Total settings JSON actually parsed for this session: **41,617 B** across 2 files.

---

## 3. CLAUDE.md + rules + memory — the context-injection payload

### 3a. CLAUDE.md

| file | bytes | note |
|---|---|---|
| `~/.claude/CLAUDE.md` | **63,983** | the real file |
| `~/.claude-tertiary/CLAUDE.md` | 33 (symlink) | → `~/.claude/CLAUDE.md`, so same 63,983 B |
| `./CLAUDE.md` (project) | **34,628** | |

No `@`-imports in either (`grep -n '^@' …` → no hits), so no transitive expansion.

R4's incidental warning (`over the 40.0k-char limit (62.0k chars)`) **still holds and has
grown**: 63,983 B today vs 62.0 k then.

### 3b. 🚨 The `paths:`-scoping defect — CONFIRMED LIVE, and observable in my own context

Per-file check (`head -1` vs first `^---$`):

| file | bytes | line 1 | first `---` | loaded into THIS session? |
|---|---|---|---|---|
| `agent-operating-lessons.md` | 6,540 | HTML comment | none | ✅ yes — **correctly** (no frontmatter by design) |
| `agent-teams.md` | 7,891 | HTML comment | none | ✅ yes — **correctly** (no frontmatter by design) |
| `api-security.md` | 4,445 | HTML comment | **line 3** | ✅ yes — **BY ACCIDENT** |
| `bottle-service.md` | 6,043 | HTML comment | **line 3** | ✅ yes — **BY ACCIDENT** |
| `migrations.md` | 4,553 | HTML comment | **line 3** | ✅ yes — **BY ACCIDENT** |
| `monitoring.md` | 9,763 | HTML comment | **line 3** | ✅ yes — **BY ACCIDENT** |
| `replicache.md` | 32,062 | HTML comment | **line 3** | ✅ yes — **BY ACCIDENT** |
| `view-transitions.md` | 25,045 | HTML comment | **line 3** | ✅ yes — **BY ACCIDENT** |
| `bottle-menu-data.md` | 14,870 | `---` | line 1 | ❌ **no** — correctly scoped out |
| `design-surfaces.md` | 4,916 | `---` | line 1 | ❌ **no** — correctly scoped out |

The "loaded?" column is not inferred — it is read off **this session's own
`<system-reminder>` block**, which enumerates exactly those 8 files and omits the 2 with
line-1 frontmatter. That is a positive **and** a negative control in one observation: the
two files whose frontmatter the loader can see are the two that are absent.

Byte accounting for `.claude/rules/` (116,128 B on disk):

- unconditional **by design** (genuinely no frontmatter): 14,431 B
- unconditional **by accident** (line-1 comment hides `paths:`): **81,911 B**
- correctly scoped out: 19,786 B
- **loaded this session: 96,342 B of 116,128 B (83 %)**

81,911 B ≈ the "~82 KB" in the memory index. **The claim is exact and still live today.**
None of these six paths match this cwd's work (no `src/app/api/**`, `drizzle/**`,
`scripts/**`, bottle-service or vt-reference files touched).

### 3c. 🚨 PRIOR-ART CORRECTION — `~/.claude/rules/` DOES load on this binary

The brief and the always-resident memory both state, measured twice (2.1.114 and 2.1.220),
that `~/.claude/rules/*.md` is never read. **On the binary this session is running, it is.**

`~/.claude/rules/agent-operating-lessons.md` is 1,760 B and its full text appears in this
session's system-reminder, labelled *"user's private global instructions for all projects"*.
It cannot have arrived by `@`-import: `grep -n '^@' ~/.claude/CLAUDE.md` returns nothing and
`grep -n 'rules/' ~/.claude/CLAUDE.md` returns nothing.

Cost is trivial (1,760 B) — the finding matters because the file's own body says the surface
is dead, so the fleet is declining to use a mechanism that now works.

`~/.claude-tertiary/rules/agent-operating-lessons.md` is the same 1,760 B file.

### 3d. Memory store

`~/.claude-tertiary/projects/-Users-…-reso-management-app/memory` → symlink into `~/.claude/…`.

| file | bytes | loaded? |
|---|---|---|
| `MEMORY.md` | 12,779 | ✅ yes (in system-reminder) |
| `MEMORY-ARCHIVE.md` | 360,689 | ❌ no — referenced only |
| whole memory dir | 670 files | only the index is read |

### 3e. Total instruction payload injected at boot for this cwd

| source | bytes |
|---|---|
| `~/.claude/CLAUDE.md` (via tertiary symlink) | 63,983 |
| `./CLAUDE.md` | 34,628 |
| `.claude/rules/` (8 of 10 files) | 96,342 |
| `~/.claude/rules/agent-operating-lessons.md` | 1,760 |
| `MEMORY.md` | 12,779 |
| **TOTAL** | **209,492 B ≈ 52 K tokens** |

Of which **81,911 B (39 %) is unconditional-by-accident** and would not load if the
markdownlint directive were moved below the frontmatter.

---

## 4. Skills / commands / agents / plugins discovery

`find -L … -type f` + `stat -L -f%z`:

| surface | files | bytes (deref) |
|---|---|---|
| `~/.claude/skills` | 485 | 15,669,554 |
| ├ top-level skill dirs | **35** | |
| └ `SKILL.md` files | **35** | 135,169 |
| `~/.claude/commands` | 20 (all symlinks → claude-infrastructure) | 210,121 |
| `~/.claude/agents` | 5 | 30,046 |
| `~/.claude/hooks` | 101 | 1,633,906 |
| `~/.claude/plugins` | 456 | 6,411,758 (74 `SKILL.md`/`plugin.json`) |
| project `.claude/skills` | 29 | 188,092 |
| project `.claude/commands` | 18 | 95,515 |
| project `.claude/agents` | 11 | 68,617 |
| project `.claude/hooks` | 2 | 7,407 |
| project `.claude/rules` | 10 | 116,128 |
| project `.mcp.json` | 1 | 429 |

`~/.claude-tertiary/{skills,commands,agents,plugins}` are all **symlinks to the `~/.claude`
copies** — so the active config dir adds no distinct bytes, but the loader still walks them.

---

## 5. Session/transcript store

```
for d in ~/.claude ~/.claude-tertiary ~/.claude-next ~/.claude-secondary ~/.claude-quaternary; do
  find "$d/projects" -name '*.jsonl' -type f | wc -l ; du -sh "$d/projects" ; done
```

| store | slug dirs | `*.jsonl` | du |
|---|---|---|---|
| `~/.claude/projects` | 381 | 1,817 | 2.0 G |
| `~/.claude-tertiary/projects` | 395 | 1,958 | 2.0 G |
| `~/.claude-next/projects` | 381 | **0** | 0 B |
| `~/.claude-secondary/projects` | 522 | 1,707 | 2.0 G |
| `~/.claude-quaternary/projects` | 376 | 1,570 | 1.5 G |
| **`find ~/.claude*/projects -name '*.jsonl' \| wc -l`** | | **7,052** | ~7.5 G |

(continued below with timings)

### 5b. Is the store scanned at boot? **NO — measured, not assumed**

```
grep -ihcE 'projects/|\.jsonl|transcript|resume|history\.jsonl' dbgF1.log   ->  0
```

Zero hits across a full-cascade debug log. The binary does **not** enumerate
`~/.claude*/projects/**`, does not read `history.jsonl` (2.3 MB / 3,386 lines,
read+parse lower bound **10.5 ms** — never paid at boot), and does not touch
`~/.claude/session-index.db` (**41,127,936 B**, plus a stale 51,728,384 B backup at
`state/session-index.db.bak-2026-07-26`).

🚨 **The brief's "3,966 sessions / directory scan is a real cost" hypothesis is REFUTED
for the binary.** The session index is read by the fleet's own `session-index-start.sh`
SessionStart hook — that is the hooks axis, not config discovery. For reference the raw
scan cost is small anyway: `find ~/.claude-tertiary/projects -name '*.jsonl' | wc -l`
= **57 / 44 / 42 ms** (n=3).

Transcript distribution (`~/.claude-tertiary/projects`): n=1,962, total 1.90 GB,
median 338,261 B, p90 1,716,580 B, max 68,761,081 B.

This session's own slug dir
`…/projects/-Users-chrisren-Development--worktrees-wt-cc-143835-83020` holds 2 entries,
4.2 MB. Nothing is resumed at a fresh start.

---

## 6. Lower-bound file IO for the WHOLE config-discovery layer (`/tmp/tdisc.js`, node)

Same V8 the binary embeds. n=3 (first run cold-ish):

| step | run1 | run2 | run3 |
|---|---|---|---|
| read+parse `.claude.json` (184 KB) | 1.188 | 1.277 | 1.227 |
| read+parse `settings.json` (36 KB) | 0.145 | 0.236 | 0.190 |
| read+parse project `settings.json` | 0.425 | 0.058 | 0.060 |
| stat 6 settings layers (4 missing) | 0.204 | 0.126 | 0.125 |
| read 2 × CLAUDE.md + MEMORY.md (110 KB) | 0.699 | 0.321 | 0.372 |
| readdir+read project `.claude/rules/*.md` (115 KB) | 2.943 | 0.537 | 0.557 |
| readdir+read `~/.claude/rules/*.md` | 0.155 | 0.054 | 0.057 |
| walk 35 user skills, read `SKILL.md` (388 KB) | 1.761 | 1.305 | 1.329 |
| walk 13 project skills (94 KB) | 0.450 | 0.344 | 0.348 |
| read 38 commands (302 KB) | 1.284 | 0.896 | 0.937 |
| read 16 agents (98 KB) | 0.546 | 0.445 | 0.412 |
| read 4 plugin catalog JSONs (408 KB) | 2.149 | 0.584 | 0.592 |
| read project `.mcp.json` | 0.224 | 0.042 | 0.043 |
| **TOTAL** | **12.17** | **6.23** | **6.25** |

🚨 **The entire disk side of config discovery is ~6 ms warm.** Everything the binary
spends beyond that is its own processing, not IO. This is a LOWER BOUND on the binary's
cost, and it is stated as one.

---

## 7. The binary's OWN stage timings — zero-token pty probe

Harness: `scratchpad/ptyprobe.py` (python `pty.fork`, byte-level output trace, SIGINT at
timeout). Binary **`~/.claude-220/node_modules/.bin/claude` = 2.1.220**.

⚠️ **Binary-identity correction.** The brief says the real binary is
`~/.claude-versions/current/node_modules/.bin/claude`. That symlink resolves to
**2.1.114**, but every live session on this box is running
`~/.claude-220/node_modules/.bin/claude` = **2.1.220** (`ps -eo pid,command | grep …`,
e.g. `cc-close-attrib /Users/chrisren/.claude-220/…/claude --permission-mode auto`).
All timings below are 2.1.220 — the binary the operator actually runs.

Three configurations, each n=3, all in the reso worktree unless noted:

- **A** `--bare` (skip hooks/LSP/plugins; also skips skill dirs and CLAUDE.md) — isolates
  the settings + permission-rule layer.
- **B** `--setting-sources project` (user hooks off; CLAUDE.md/rules + project skills on).
- **F** full cascade, neutral cwd `/tmp/ccprobe-cwd` (so `dod-persist` / `session-register`
  key on a throwaway path, not this worktree) — isolates the **user** skills/commands load.

```
cd <reso worktree>; python3 ptyprobe.py 14 $B --bare --debug-file dbgA$i.log
cd <reso worktree>; python3 ptyprobe.py 16 $B --setting-sources project --debug-file dbgB$i.log
cd /tmp/ccprobe-cwd; python3 ptyprobe.py 16 $B --debug-file dbgF$i.log
```

### 7a. pty output trace

| config | TTFB (s) | QUIESCE (s) |
|---|---|---|
| A `--bare` | 0.444 / 0.395 / **0.357** | 0.915 / 0.852 / **0.779** |
| B project-only | 0.393 / 0.429 / **0.373** | 1.160 / 1.421 / **1.303** |
| F full, neutral cwd | 0.425 / 0.417 / 1.201 | 0.470 / 0.458 / 1.704 |

### 7b. `[STARTUP]` stage times, from the binary's own debug lines

| stage | A `--bare` | B project-only | F full | R4 (2026-08-11) | verdict |
|---|---|---|---|---|---|
| MDM settings load | 0 / 1 / 0 ms | 0 / 1 / 1 | — | (part of "~300 ms") | **0 ms — no enterprise policy file exists** |
| permission-rule apply (all 981 rules) | **8 ms** (02.788→02.796) | 0 ms | — | "~300 ms" | **STALE — it is ~8 ms** |
| `setup()` (skill dir discovery) | 10 / 13 / **11** | 33 / 37 / **30** | 45 / **56** / 126 | — | new line, not in R4 |
| `Commands and agents loaded in` | 50 / 63 / **50** | 51 / 58 / **50** | 30 / **32** / 49 | **159 ms** | **STALE — 32–50 ms today** |
| `showSetupScreens()` | 102 / 107 / **102** | 475 / 640 / **557** | 401 / **800** / 1019 | not measured | **THE HOTSPOT** |
| `MCP configs resolved in` | 0 / 1 / **0** | 76 / 93 / **76** | 59 / **75** / 156 | **207 ms** | **STALE — 0–156 ms** |
| `Loaded N CLAUDE.md/rules files` | none (bare skips) | 12 files, ~9 ms | 2 files | — | ~9 ms, post-paint |
| FileIndex `git ls-files` 4,511 files | 25 ms / refresh 148 | 87 ms / refresh 119 | ripgrep 199 / refresh 484 (non-git cwd) | — | concurrent, post-paint |

### 7c. 🚨 THE FINDING — `showSetupScreens()` blocks 400–1,000 ms, and it is the
`.claude.json` write path

Every run shows a **silent, un-logged gap immediately before an atomic `.claude.json`
write**, inside the blocking `showSetupScreens()` stage:

| run | gap before write | showSetupScreens total | writes/start |
|---|---|---|---|
| B1 | **354 ms** | 475 ms | 3 |
| B2 | **278 ms** | 640 ms | — |
| B3 | **411 ms** | 557 ms | — |
| F1 | **265 ms** | 401 ms | **4** |
| F2 | **576 ms** | 800 ms | 3 |
| F3 | **285 ms** | 1,019 ms | 3 |

The write itself is logged as: `Preserving file permissions: 100644` →
`Writing to temp file: …/.claude.json.tmp.<pid>.<hash>` → `Temp file written
successfully, size: 185615 bytes` → `written atomically`.

**Two hypotheses tested and both REFUTED:**

1. *"It scales with the 184 KB file."* — A throwaway `CLAUDE_CONFIG_DIR=/tmp/ccprobe-small`
   holding a **16 KB** `.claude.json` showed the same **279 ms** gap on the run where it
   wrote. Size-independent.
2. *"It is lock contention across the ~24 live sessions sharing this config dir."* — the
   16 KB probe above was a **fresh /tmp dir with zero contention** and still paid 279 ms.
   Contention refuted.

A control with **no write at all** (throwaway big dir, runs 2–3, nothing changed) gives
`showSetupScreens() completed in 59 / 87 / 65 ms` — i.e. **the write path is the whole
difference**, ~340–940 ms of it.

**Pure IO cost of the write is only ~14 ms** (`/tmp/twrite.js`, n=5:
serialize 0.56–0.92 ms, write+fsync+rename 11.58 / 13.00 / 13.90 / 18.70 / 52.37 ms).
So ≥95 % of the gap is something the binary awaits before writing, and **it emits no
debug line for it**. Cause = **UNKNOWN**. A fixed ~250–300 ms debounce/flush timer fits
the lower cluster but is unproven; I did not `dtruss`/`fs_usage` it (needs sudo).

### 7d. `.claude.json` is rewritten 3–4× per start, and it GROWS unboundedly

`grep -c 'written atomically'` → **4 / 3 / 3** per start (F1/F2/F3). Sizes within one
start: 185,615 → 185,615 → 186,089 → 186,234 B.

Live file measured at the start of this session: **184,248 B**. After my 9 probe
launches: **187,162 B** — **+2,914 B, ≈324 B per launch.** Growth axes: a new `projects`
entry per never-before-seen cwd (my `/tmp/ccprobe-cwd` earned one), and
`githubRepoPaths` accumulating every worktree path ever seen (already a single
9,577-byte array for `renchris/reso-management-app`).

At 368 project entries / 487 in `.claude-quaternary` this is monotone and nothing prunes
it. It does not cost parse time (1.3 ms) — it costs the 3–4 serialize+fsync cycles and,
eventually, whatever the silent 300 ms is.

---

## 8. BLOCKING classification

| item | class | median ms | why |
|---|---|---|---|
| `.claude.json` read+parse | BLOCKING | **1.3** | before anything |
| MDM/enterprise settings | BLOCKING | **0** | both paths absent |
| settings cascade read+parse (2 files, 42 KB) | BLOCKING | **~0.3** (node LB) | |
| permission-rule apply, 981 rules total | BLOCKING | **8** | 338+41+6 user, 82+19+2 project, 493 local, minus 15 removals |
| `setup()` — skill dir discovery | BLOCKING | **56** (full) | |
| commands + agents + plugins load | BLOCKING | **32** (full, 90 skills) | |
| **`showSetupScreens()` (`.claude.json` write path)** | **BLOCKING** | **~600** | §7c |
| MCP **config** resolve | BLOCKING | **75** | distinct from the connects |
| MCP server **connects** (5 servers) | CONCURRENT | 217–651 each | `awaited at +492ms`, all parallel |
| `Loaded 12 CLAUDE.md/rules files` (206,311 chars) | CONCURRENT (post-paint) | **~9** | at +1.0 s, after TTFB 0.4 s |
| FileIndex `git ls-files` (4,511 files) | CONCURRENT | 119–148 refresh | post-paint |
| `~/.claude*/projects/**` scan | **NOT DONE** | 0 | §5b |
| `history.jsonl` (2.3 MB) | **NOT DONE at boot** | 0 (10.5 ms if it were) | §5b |
| `session-index.db` (41 MB) | **NOT DONE by binary** | 0 | fleet hook reads it |
| transcript resume | **N/A on fresh start** | 0 | |

**Layer total on the BLOCKING critical path: ~0.67 s median** (0.0013 + 0.3 + 8 + 56 + 32
+ 600 + 75 ms), of which **~600 ms (89 %) is the single `showSetupScreens()` write path.**

---

## 9. Prior-art verdict

| R4 claim | today | verdict |
|---|---|---|
| settings + MDM + permission-rule load ≈ 300 ms | 0 + 0.3 + 8 ms | **STALE / misattributed.** R4's 300 ms window (dbg 16.903→17.121) contained the whole pre-`setup()` phase incl. CA certs (73 ms measured today), git remote parse, plugin catalog — not rule compilation. |
| skills/commands/agents/plugins = 159 ms, 93 skills | **32 ms**, 90 skills (55 user + 35 bundled + 1 plugin) | **STALE — 5× faster** |
| MCP configs resolved = 207 ms | **75 ms** | **STALE — 2.8× faster** |
| MCP connects 191–386 ms, parallel, non-blocking | 217–651 ms, parallel, non-blocking | **HOLDS** (slower tail, same class) |
| `~/.claude-tertiary/CLAUDE.md` over the 40 k limit (62.0 k) | 62,748 chars | **HOLDS, and grew** |
| `Skill listing over budget: 93 skills, 46,716 chars > 8,000` | **NOT reproduced** in any of my 9 probes | UNKNOWN — plausibly emitted only on first-request assembly, which a pty probe with no prompt never reaches. Do not cite as refuted. |
| R6: SessionStart group max 240 ms | not my axis, not re-measured | — |
| memory: `~/.claude/rules/*.md` does not load | **it loads** (§3c) | **STALE — REFUTED** |
| brief: unbounded per-project `history` arrays | **0 B in all 6 files** | **REFUTED** |
| brief: 3,966-session directory scan is a real cost | binary never scans it | **REFUTED for the binary** |
| brief: `.claude.json` 129/184/175/69 KB | confirmed, plus 205 KB `.claude-secondary` and 185 KB `.claude-quaternary` the brief missed | **HOLDS, incomplete** |

---

## 10. Dead ends / things that cost me time

- Naming the pty harness `pty.py` shadowed the stdlib `pty` module → `AttributeError:
  partially initialized module 'pty' has no attribute 'fork'`. Could not `rm`/`mv` it
  (permission gate), so the harness moved to the session scratchpad.
- `claude --debug mcp list` emits **no** `[STARTUP]` lines — subcommands skip the whole
  startup path. Not usable as a cheap probe.
- `--bare` looked like the ideal isolate but it prints
  `[reduced mode] Skipping skill dir discovery` and `No CLAUDE.md/rules files found` —
  it cannot measure the two surfaces most of this axis is about. Hence three
  configurations instead of one.
- `find -L <dir> -type f -exec stat -f%z` under-reports by ~150× on symlink farms
  (`~/.claude/commands` read 1,413 B; with `stat -L` it is 210,121 B). Every size in §4
  is the `stat -L` figure.

## 11. UNKNOWN

- **Cause of the 265–576 ms silent segment before the `.claude.json` write.** Measured,
  reproducible, size-independent, contention-independent — but the binary logs nothing in
  it and I did not run `fs_usage`/`dtruss` (sudo).
- Whether the `Skill listing over budget` warning still fires — a pty probe that never
  submits a prompt does not reach first-request assembly.
- The full-cascade stage times **in the reso worktree specifically** (F ran in a neutral
  cwd to avoid `dod-persist`/`session-register` writing against this worktree). B covers
  the reso project surfaces; the user-skill load is measured in F. No single run has both.
- Whether a second/third `.claude.json` write in the same start also pays its own ~300 ms
  or only the first does.
