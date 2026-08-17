# AXIS: statusline-tui — first-paint / TUI / statusline layer

**Measured 2026-08-16** on `chrisren@macOS 15.6.1`, 10 cores, **load average 17.88 / 19.08 / 20.27**
(≈1.8× cores) with ~19 live `claude` processes. Memory NOT under pressure (79% free, pageouts
26,255 lifetime) — swap is ruled out as a cause.

Every number below carries the command that produced it. n≥3 everywhere, min + median reported.

---

## 0. TWO GROUND-TRUTH CORRECTIONS BEFORE ANYTHING ELSE

### 0.1 The real launcher does NOT go through `~/bin/claude-latest`

The lead's brief states *"`_claude_pinned` ultimately runs `~/bin/claude-latest`"* and prices ~1.3 s
of `rotate_log` / `update_if_needed` / `validate_or_recover` onto every launch.

```
$ grep -n '_claude_pinned' ~/.zshrc      # → NO MATCH; the function does not exist
$ sed -n '451,505p' ~/.zshrc
```

`claude()` at `~/.zshrc:451` ends at line 496 with:

```
local _bin="$HOME/.claude-220/node_modules/.bin/claude"
... DISABLE_AUTOUPDATER=1 CLAUDE_CONFIG_DIR="$_cfg" CLAUDE_CODE_TASK_LIST_ID="$(_cc_tlid)" \
    "$HOME/.claude/bin/cc-close-attrib" "$_bin" --permission-mode auto --model claude-opus-5 --effort high
```

`claude-latest` appears in `~/.zshrc` only at lines **173 / 175**, inside the *legacy* body that now
serves `claude-prev*` (the stable 2.1.114 track). So the 1.3 s wrapper + `npm view` network call is
**off the primary launch path**. (It is still on `claude-prev`.) The shell-layer axis owns the
re-pricing; flagged here because it changes what the TTFB baseline should be compared against.

### 0.2 The binary in `~/.claude-versions/current` is NOT the one anyone runs

```
$ readlink -f ~/.claude-versions/current                      → /Users/chrisren/.claude-versions/2.1.114
$ ps -axo args | grep -F 'node_modules/.bin/claude' | ...     → 19/19 live sessions on ~/.claude-220
$ ~/.claude-220/node_modules/.bin/claude --version            → 2.1.220 (Claude Code)
```

The brief's suggested probe target (`~/.claude-versions/current/...`) is **2.1.114**. Every live
session runs **2.1.220** from `~/.claude-220`. All probes below therefore use `~/.claude-220`.

---

## 1. STATUSLINE — `~/.claude/statusline.sh`

410 lines of bash. **No network, no API, no `cc-context` shell-out.** What it forks per render:

| fork | purpose | measured cost (min/median, n=9, in the reso worktree) |
|---|---|---|
| `bash` itself | the interpreter | 2.6 / 2.8 ms |
| `jq` #1 | one `@tsv`-style read of 6 payload scalars | ~4 ms |
| `jq` #2 | memoized pid read from prior telemetry file | ~4 ms |
| `jq` #3 | telemetry EMIT (writes `/tmp/cc-telemetry/<sid>.json`) | ~4 ms |
| `git rev-parse --short HEAD` | commit id | **7.6 / 8.1 ms** |
| `git status --porcelain=v2 --branch --no-ahead-behind -uno` | branch + dirty | **13.2 / 13.9 ms** |
| `basename`/`pwd`/`mv` | line assembly | ~5 ms |
| `ps` ancestry walk (COLD ONLY, ≤10 iterations) | resolve owning claude pid | 3.4 / 3.7 ms per `ps` |

Component measurement command:

```
$ python3 /tmp/slt/parts.py     # subprocess.run x9 per case, cwd = reso worktree
fork floor: /bin/bash -c true                                min=   2.6 med=   2.8
git rev-parse --short HEAD                                   min=   7.6 med=   8.1
git status --porcelain=v2 --branch --no-ahead-behind -uno    min=  13.2 med=  13.9
jq --version                                                 min=   3.6 med=   3.9
ps -o comm= -p 1                                             min=   3.4 med=   3.7
basename (fork)                                              min=   2.3 med=   2.6
```

### End-to-end statusline timing (synthetic payload, throwaway `CC_TELEMETRY_DIR`)

```
$ python3 /tmp/slt/bench.py <cwd> cold 8     # fresh session_id each run → no memoized pid → ps-walk
$ python3 /tmp/slt/bench.py <cwd> warm 8     # fixed session_id → pid memoized
```

Payload: `/tmp/slt/payload.json` — a real-shaped `{session_id, transcript_path, cwd, model, effort,
context_window{size 1e6, used 37, remaining 63}}`. Telemetry redirected to `/tmp/slt/tel`
(`CC_TELEMETRY_DIR`) and a `SLT-*` session id, so **no live session's telemetry row was touched**.

| mode | samples (ms) | min | **median** | max |
|---|---|---|---|---|
| cold (first render of a session) | 87.3 66.0 68.2 51.2 54.6 57.7 54.0 54.6 | 51.2 | **56.2** | 87.3 |
| warm run 1 | 71.2 51.2 50.3 49.2 50.3 47.7 52.2 50.4 | 47.7 | **50.3** | 71.2 |
| warm run 2 | 48.1 47.1 48.0 49.1 57.6 47.5 52.9 55.9 | 47.1 | **48.6** | 57.6 |

An earlier, cruder harness (two `python3` timestamp forks around the call) reported 82–93 ms — that
was **instrument overhead** (~30 ms of second-`python3` exec). Discarded; the `subprocess`-timed
numbers above are the ones to cite.

**Prior-art check:** R4 table row 13 says *"statusline command (per render) 45 ms, not blocking"*.
**STILL HOLDS** — 48.6 ms median today vs 45 ms then, and today's box is at load 18.

**The script's own header comment is STALE**: it says *"spent 109 ms of CPU each time"* pre-slim.
Post-slim reality is 48–56 ms wall. The de-forking refactor it describes did land and did work.

### How often is it invoked?

The statusline writes `/tmp/cc-telemetry/<sid>.json` **on every render**, so an mtime transition is
exactly one render. Poller (read-only, 0.15 s sampling, 90 s window):

```
$ python3 /tmp/slt/renderrate.py 90
window=90s polls=585 files_seen=29
sessions that rendered at least once: 6
      3 renders    0.03 Hz  440c548a-…
      2 renders    0.02 Hz  bf3b6435-…
      2 renders    0.02 Hz  8120a4c7-…
      1 renders    0.01 Hz  f9d4b4ee-…   (×3 more at 0.01 Hz)
TOTAL renders across fleet in window: 10  (0.11 renders/sec fleet-wide)
```

29 live telemetry rows, **10 renders in 90 s across the whole fleet**. Peak observed per pane:
**0.03 Hz**. The statusline's own comment claims *"0.15–0.37 Hz per pane"* — **that claim is now
STALE / high by 5–12×** on this workload.

Corroborating: my own session's telemetry row (`62005ce6…`, cwd = this worktree) was **621 s stale
while the session was actively working** — a long agent turn renders ZERO times, exactly as the
script's own "not always fresh" note warns.

**Verdict on statusline as the post-startup-responsiveness suspect: REFUTED.**
0.03 Hz × 50 ms = **1.5 ms of work per pane per minute**; fleet-wide 0.11 renders/s × 50 ms =
**0.55 % of one core**. Even if the render were fully blocking on the UI thread, it cannot produce a
perceptible hitch at this rate. It is not the regression.

---

## 2. TIME TO FIRST PAINT — zero-token pty probe

Harness `/tmp/slt/probe2.py` (kept out of the repo). `pty.fork()` → `execve` the 2.1.220 binary,
timestamp every output chunk, **never type**, `SIGKILL` at the dwell deadline. Pane-identity env
stripped (`CC_PANE_ID`, `ITERM_SESSION_ID`, `CLAUDE_CODE_TASK_LIST_ID`, `CLAUDECODE`,
`CLAUDE_CODE_ENTRYPOINT`) — a pty probe genuinely is not an iTerm2 pane, and this is the same
treatment R4's harness used. `LEAD_CRASH_WATCHDOG_DISABLED=1` (its own documented kill switch) so no
detached watchdog daemon leaks per probe. 150×44 winsize.

Markers: `box_top` = first `╭` (composer box drawn), `hint_shortcuts` = the `? for shortcuts` hint
line under the composer. Full traces in `/tmp/slt/trace-*.txt`.

### 2a. FLOOR — scratch config dir, scratch cwd (no hooks, no MCP, no user settings)

```
$ python3 -u /tmp/slt/probe2.py A2-floor /tmp/slt/cfg-scratch /tmp/slt/proj 12     # ×5
```

Scratch config = `{"tui":"default"}` + a `.claude.json` with `hasCompletedOnboarding` and a trusted
project entry.

| run | first byte (ms) | composer/hint (ms) |
|---|---|---|
| 1 | 366.4 | 498.0 |
| 2 | 411.5 | 555.6 |
| 3 | 328.8 | 430.1 |
| 4 | 339.0 | 454.7 |
| 5 | 451.2 | 587.2 |

**min 328.8 / median 366.4 TTFB · min 430.1 / median 498.0 time-to-interactive.**
After that: silence until a single re-render at ~10.4 s (idle repaint), no further work.

### 2b. real config dir (`~/.claude-tertiary`), scratch cwd

```
$ python3 -u /tmp/slt/probe2.py B-realcfg-tmpcwd ~/.claude-tertiary /tmp/slt/proj 25     # ×3
```

| run | first byte (ms) | `box_top` (ms) | last output before quiet (ms) |
|---|---|---|---|
| 1 | 412.9 | 1288.2 | 2268.5 |
| 2 | 412.5 | 1226.7 | 1868.3 |
| 3 | 422.0 | 1501.1 | 2839.4 |

**TTFB min 412.5 / median 412.9 — statistically identical to the floor.**
Composer at min 1226.7 / median 1288.2 ms.

### 2c. real config dir + real reso worktree — THE OPERATOR'S ACTUAL LAUNCH

```
$ python3 -u /tmp/slt/probe3.py C3-real-real ~/.claude-tertiary \
      /Users/chrisren/Development/.worktrees/wt-cc-143835-83020 20 keepchild      # ×5
```

| run | first byte (ms) | composer (ms) | statusline first painted (ms) |
|---|---|---|---|
| 1 | 542.7 | 1520.2 | 2237.9 |
| 2 | 638.3 | 1713.4 | 2583.7 |
| 3 | 547.3 | 1827.1 | 2156.3 |
| 4 | 459.0 | 1325.6 | 1987.6 |
| 5 | 445.1 | 1276.9 | 1654.0 |
| | **min 445.1 · med 542.7** | **min 1276.9 · med 1520.2** | min 1654.0 · med 2156.3 |

### 2d. THE HEADLINE DELTA

| | first byte | **time-to-interactive (composer)** |
|---|---|---|
| floor (scratch config, scratch cwd) | min 335.8 / med 489.6 | min 472.5 / **med 632.4** |
| real config dir + real reso worktree | min 445.1 / med 542.7 | min 1276.9 / **med 1520.2** |
| **DELTA — what all the hooks / MCP / config cost** | +53 ms (noise) | **+888 ms median (+804 ms min-to-min)** |

**Time-to-first-byte is essentially config-independent (~0.4–0.5 s = node/bundle boot).
Everything the operator's configuration costs lands in the 0.4 s → 1.5 s window, and it is
about 0.9 s.**

### 2e. Full decoded timeline of one real launch (`t3-C3-real-real-1786920472.txt`)

```
[    542.7]  first bytes (terminal mode setup)
[   1520.2]  ▐▛███▜▌ Claude Code v2.1.220 / Opus 5 (1M context) / ~/…/wt-cc-143835-83020
             ❯ Try "create a util logging.py that…"          ← COMPOSER, interactive
[   1532.4]  ⚠ Transcript saving is off … · /rc connecting… · ⏵⏵ auto mode on
[   2237.9]  (3) wt-cc-143835-83020 (8fe22bdbc) · medium      ← STATUSLINE first render
[   2452.0]  /rc                                              ← remote control CONNECTED
[  11365.6]  (idle repaint)
```

**No 5.8 s or 9.3 s settle event.** R4 (2026-08-11) reported settles at 5.85 s and 9.26 s on reso
and 5.75 s / 9.05 s on an empty project, attributed to `hooks/setup-task-symlinks.sh` running 21 s
and being killed by its own `timeout: 5`. **That does not reproduce today** in 5/5 runs: the trace
goes quiet at ~2.5 s and stays quiet until an idle repaint at ~11.3 s. Either the hook was fixed or
it no longer blocks. → **R4's headline finding is STALE.**

### 2f. Ablation — where the 0.9 s actually lives

All at cwd `/tmp/slt/proj`, `keepchild`, n=3, composer marker:

| config | composer min / **median** | note |
|---|---|---|
| scratch (`{"tui":"default"}`) | 472.5 / **632.4** | floor (n=5) |
| **`settings.json` copied verbatim from tertiary** (hooks + statusline + all 492 permission rules), minimal `.claude.json` | 520.3 / **643.6** | `/tmp/slt/cfg-rcon` |
| same, `hooks` key deleted | 483.9 / **540.5** | `/tmp/slt/cfg-nohooks` |
| same, `remoteControlAtStartup:false` | 548.3 / **794.4** | `/tmp/slt/cfg-rcoff` |
| **the real `~/.claude-tertiary` dir**, MCP disabled (`--strict-mcp-config --mcp-config=<empty>`) | 1355.6 / **1365.1** | `D-nomcp` |
| **the real `~/.claude-tertiary` dir**, everything on | 1253.9 / **1812.0** | `B3` |

Read this table top-to-bottom:

- **`settings.json` — including all 15 SessionStart hooks and the statusline — costs ~11 ms of
  median TTI** (632.4 → 643.6). Deleting the `hooks` key moves it by ~100 ms median / ~36 ms min,
  i.e. **inside the noise of this box at load 18**.
  ⚠️ Caveat: cwd was `/tmp/slt/proj`, where many hooks legitimately early-exit. This bounds hooks
  *in that cwd*, not in the reso worktree. But §2e's gap-free real-cwd timeline independently says
  no hook is blocking there either.
- **`remoteControlAtStartup:false` did not make anything faster** (794.4 vs 643.6 median — the
  *off* variant was nominally slower, i.e. pure noise). Inconclusive as an A/B, because the
  `/rc connecting` marker never appeared in the scratch dirs — remote control apparently does not
  activate without the real `.claude.json`. See §4 for the real-config measurement.
- **The jump is the config DIRECTORY, not `settings.json`**: 643.6 → 1365.1 ms with MCP already
  off. That +722 ms is `~/.claude-tertiary`'s **184 KB `.claude.json` (369–395 project entries)**
  plus its 35 skills / 20 commands / 5 agents / 7 plugins. **This belongs to the config/skills axis,
  not to statusline-tui** — flagging it because it is the single largest term I measured.
- **MCP: 1365.1 → 1812.0 median (+447 ms), but 1355.6 → 1253.9 on the mins (−102 ms).** The two
  statistics disagree, so at n=3 under load 18 MCP is **not reliably on the critical path**.
  Magnitude UNKNOWN; hand to the MCP axis.

---

## 3. INPUT RESPONSIVENESS — the operator's actual complaint, measured

Zero-token: `/tmp/slt/probe4.py` sends **one printable character** (`zqx`, never Enter) at a
scheduled time T after launch and measures how long until it is echoed. Nothing is ever submitted.

```
$ python3 -u /tmp/slt/probe4.py real2 ~/.claude-tertiary <reso worktree> <T> 12
```

Real config dir + real reso worktree:

| T (keystroke sent at) | composer painted at | echo latency |
|---|---|---|
| 1.00 s | 1.49 s | **NEVER — dropped** |
| 1.00 s | 1.66 s | **NEVER — dropped** |
| 1.01 s | 1.77 s | **NEVER — dropped** |
| 2.01 s | 1.84 s | 234.0 ms |
| 2.01 s | 1.66 s | 7.5 ms |
| 2.00 s | 1.54 s | 156.1 ms |
| 3.01 s | 2.28 s | 88.0 ms |
| 3.00 s | 2.55 s | 156.3 ms |
| 3.01 s | 1.57 s | 21.2 ms |
| 4.01 s | 1.54 s | 5.8 ms |
| 5.00 s | 1.57 s | 6.1 ms |
| 5.00 s | 2.12 s | 6.7 ms |
| 7.01 s | 1.21 s | 7.3 ms |

Floor config for comparison: T=1.0 s → 81.6 ms (composer was already up at 0.73 s); T=2/3/5 s →
8.3 / 7.9 / 6.5 ms.

**Three things this establishes:**

1. **A keystroke typed before the composer paints is silently DISCARDED — 3/3.** Not buffered, not
   late-echoed; it never appears within the following 11 s. On the real config that window is
   **~1.3–1.8 s** wide (and the shell layer sits in front of it).
2. **For ~1–1.5 s after the composer appears, echo is 88–234 ms** — visibly sluggish typing, not
   "frozen". It reaches steady state (~6–8 ms) by ~4 s.
3. **Steady-state echo is 6–8 ms, i.e. the 48 ms statusline is NOT invoked per keystroke.** If it
   were, no echo could be faster than ~50 ms.

---

## 4. `remoteControlAtStartup` — measured, and it is CONCURRENT

Set `true` in **all five** config dirs. In the real-config trace it is unambiguous:

```
[   1532.4]  /rc connecting…          ← starts AFTER the composer is already painted (1520.2)
[   2452.0]  /rc                      ← connected
```

**It opens a network connection at boot and takes ~920 ms to establish, entirely after the prompt is
usable.** It is therefore **CONCURRENT — 0 ms on the blocking path**, in 5/5 real-config runs (the
`rc_connecting` marker never precedes the composer marker in any run). Whether disabling it frees
anything downstream is **UNKNOWN** — my settings-only A/B (§2f) could not activate the feature.

## 4b. The other three startup keys

| key | value (all 5 dirs) | effect on startup |
|---|---|---|
| `tui` | `"default"` (`.claude-next`: `"fullscreen"`) | **The real suppressor.** Prior art's decompiled gate `X_m()` short-circuits on `eo().tui!==void 0` before the GrowthBook flag and the seen-counter, so any defined value kills the fullscreen upsell unconditionally. **Re-verified behaviourally today:** 0 upsell modals in 26 launches across 5 config variants. `"default"` also keeps panes out of the alternate screen. |
| `skipAutoPermissionPrompt` | `true` | Suppresses the auto-default permission nudge. Schema-validated (prior art type-probe). **No blocking round-trip observed**: no permission dialog in any of the 26 launches. Its cost when unset would be a *blocking modal*, not latency — so `true` is worth ~∞ on a spawned pane and 0 ms on a launch that would not have shown it. |
| `skipWorkflowUsageWarning` | `true` | Same class. Never fired in any probe. **0 ms.** |
| `remoteControlAtStartup` | `true` | §4 — network connect, ~920 ms, **concurrent**. |

**None of the four is a blocking round-trip on the current settings.** They are modal *suppressors*,
and their value is that a spawned pane cannot wedge — not startup milliseconds.

---

## 5. WHAT THIS LAYER COSTS — verdict

| component | blocking on the prompt? | measured cost |
|---|---|---|
| node/bundle boot → first byte | BLOCKING | **~0.45 s** (config-independent) |
| first byte → composer painted, floor | BLOCKING | ~0.15 s |
| first byte → composer painted, real config | BLOCKING | **~1.0 s** (of which settings+hooks+statusline ≈ 0.01–0.10 s; config-dir contents ≈ 0.7 s; MCP 0–0.45 s) |
| **total time-to-interactive, real launch** | — | **min 1.28 s · median 1.52 s** |
| statusline first render | CONCURRENT (130–860 ms *after* composer) | 48.6 ms per render |
| statusline steady state | CONCURRENT | 0.03 Hz/pane ⇒ **1.5 ms per pane per minute** |
| `remoteControlAtStartup` connect | CONCURRENT | ~920 ms, starts after composer |
| SessionStart hooks | CONCURRENT/negligible in the composer path | ≤~0.1 s; **R4's 5 s blocking hook does not reproduce** |

**Statusline is exonerated on both halves of the question.** It is not on the startup critical path
(it paints 0.1–0.9 s after the prompt is usable) and it is not the post-startup responsiveness
regression (0.03 Hz × 48.6 ms; keystroke echo is 6–8 ms, which is arithmetically impossible if a
48 ms fork ran per keystroke).

**The real TUI-layer finding is the DROPPED KEYSTROKE**: for the first ~1.3–1.8 s the process is
running, has a pty, and is silently eating input. Combined with whatever the shell layer costs in
front of it, that is exactly "I launched Claude, started typing, and nothing happened."

---

## 3b. STARTUP MODALS (encountered)

Two gates were hit *by accident* during baseline construction and both are worth recording, because
each is a **hard block on interactivity** — the pane paints in ~330 ms and then waits forever:

1. **Trust dialog on an untrusted cwd.** `/tmp/slt/proj` seeded as trusted under the key
   `/tmp/slt/proj` still showed the dialog — Claude Code keys the project on the **realpath**
   (`/private/tmp/slt/proj`). Seeding both keys cleared it. Confirms prior art's "never a wildcard,
   only the specific realpath".
2. **The 82-permission pre-approval variant.** With a scratch config dir on the reso worktree, the
   trust dialog carries an extra clause:
   `⚠ This folder pre-approves 82 tool permissions in .claude/settings.json … Only proceed if you
   trust this configuration.` `hasTrustDialogAccepted:true` alone did NOT clear it in the scratch
   dir. On the operator's real config dirs the worktree is already accepted, so this does not fire
   in practice — but any fresh config dir landing on reso will wedge here.

Neither is on the operator's normal path (all real config dirs have `tui:"default"` except
`.claude-next` which has `tui:"fullscreen"`, and all have the projects trusted).

### Settings keys, all five config dirs

```
$ python3 -c "...json.load(settings.json) for the 5 dirs..."
.claude          tui=default     skipAutoPermissionPrompt=True  skipWorkflowUsageWarning=True  remoteControlAtStartup=True
.claude-secondary  same
.claude-tertiary   same
.claude-next     tui=fullscreen  + enableAllProjectMcpServers=True
.claude-quaternary same
```

(see §4 for what each does to startup)

---

## Appendix — dead ends / instrument notes

- First statusline harness used two `python3` forks around the call → +30 ms bias. Rewritten with
  `subprocess.run` inside one interpreter.
- First pty harness (`ptyprobe.py`) hung past a 90 s timeout with no trace written; not diagnosed,
  rewritten from scratch as `probe2.py`, which works. `ptyprobe.py` is abandoned, not fixed.
- Attempted `head`/`grep` on `~/.claude/hooks/dod-persist.sh` via Bash was permission-denied; read
  with the Read tool instead. **dod-persist's SessionStart mode is read-only** (it only writes on
  PreCompact or explicit `set`), so the real-config probes could not clobber a live session's frozen
  DoD.
- `~/.claude/hooks/session-register.sh` needs `$ITERM_SESSION_ID`; stripped in the probe env, so no
  phantom registry rows were created (`find ~/.claude/cc-registry -mmin -40` = 2 rows, both from
  real sessions, unchanged by the probes).
- **Probes with the real config dir DID arm `mailbox-wake-arm.sh` watchers** (`cc-await-ping <sid>
  --timeout 14340`), which survive the child's SIGKILL. **14 orphans were identified and reaped**
  (`/tmp/slt/reap.py`), on a criterion that can only match this investigation's own processes: the
  watcher's telemetry row must have `cwd == /private/tmp/slt/proj` (a directory this probe created)
  **and** its owning claude pid must be dead. Watchers with a live owner, or with no telemetry row
  at all, were left untouched. Post-reap re-run reports `total: 0`. No real session's watcher was
  touched, and nothing was `pkill`'d.
- `LEAD_CRASH_WATCHDOG_DISABLED=1` was set in every probe (the hook's own documented kill switch),
  so no detached watchdog daemon leaked.
- All probes ran with `CLAUDE_CODE_CHILD_SESSION` inherited (`keepchild`), which turns transcript
  saving OFF — so **no phantom transcripts were written** into the operator's `projects/` tree. It
  also means hook behaviour that keys on a transcript path may differ slightly from a real launch;
  this is a known, deliberate bias toward *under*-counting hook cost. The composer/TTFB numbers are
  unaffected (the round-2 probe without `keepchild` gave the same TTFB band: 465–1111 ms on first,
  cache-cold runs).
- Grepping the 245 MB `claude.exe` for `remoteControlAtStartup` took **179 s** and returned only key
  tables, no logic. Not worth repeating — behavioural measurement (§4) settled the question in
  20 s.

## Artifacts (all outside the repo, in `/tmp/slt/`)

`payload.json` · `bench.py` (statusline timing) · `parts.py` (fork decomposition) ·
`renderrate.py` (render-frequency poller) · `probe3.py` (first-paint pty probe) ·
`probe4.py` (keystroke-echo pty probe) · `orphans.py` / `reap.py` (cleanup) ·
`t3-*.txt` / `t4-*.txt` (raw timestamped traces) · `ablate.txt` · `probe4.txt` · `round3.txt`.
