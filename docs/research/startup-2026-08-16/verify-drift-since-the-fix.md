# Verify — "DRIFT SINCE THE FIX: the deferred MCP work grew 45%, and the router keep-warm cadence tripled"

**Slot:** adversarial refutation (recovery re-run, 4th attempt — three prior deaths: session limit, ECONNRESET ×2)
**Date:** 2026-08-16 22:15–23:05, load 11.8–13.4, 26 live `claude` processes (all `.claude-220`)
**Target claim:** 3 974 ms, path class **BACKGROUNDED**
**Anchors:** `hooks/session-start.sh:87` (recorded band) · `~/Library/LaunchAgents/com.claude.accounts-keepwarm.plist`

---

## Verdict

**REFUTED = TRUE — but the error runs the opposite way from the wave's own refutation.**

| | claim | measured |
| --- | --- | --- |
| "grew 45%" | +45% since 2026-08-11 | **0% — flat.** Fleet log n=313 probes: median **3.0 s every day** 08-11 → 08-15. Same-composition split: mean 3.23 → 3.07 (*down*). |
| keep-warm 60→180 s | a startup regression | **not a regression** — launcher reads `--max-age 600`, so 180 s is always a cache HIT. (Proposer already conceded; verified at `lib/claude-launcher.zsh:74`.) |
| **BACKGROUNDED** | costs ~0 | **WRONG — it is BLOCKING.** The detached refresher inherits the hook's **stdout pipe**; the harness reads to EOF, so the input pipeline is frozen for the refresher's whole life. Proven 3/3 vs 3/3 on the real hook in a pty. |
| 3 974 ms | the drift | inside **day-one's own distribution** (2026-08-11: n=112, med 3.0, p90 4.0, max 6.0 s). It is a loaded-box single sample compared against a quiet-box hand-run trio. |

So the claim's three load-bearing assertions — *drift*, *45%*, *backgrounded* — are each false, and
refutation angle **#2 (instrument artifact)** holds for the drift half. But angle **#1 does not hold**:
this is not "runs but does not gate". It gates. **`COLD_START_100P.md:658` ("Hook returns in 69 ms…
a process nothing blocks on. Keep the SWR.") is wrong on path class** — it measured the process-exit
clock, and the harness does not use that clock.

**corrected_ms:** **+2 200 ms median** to time-to-usable-prompt (p90 ≈ +4 200 ms; tail unbounded — see §4),
on the **54.4 %** of session starts that run a probe.
**corrected_path_class:** **BLOCKING** (input pipeline, same class as `mailbox-drain`), not BACKGROUNDED.

---

## 1. The drift premise is false — the fleet's own log says flat

`session-start.sh` writes `MCP probe binary: …` when a probe starts and `MCP Status (attempt N):`
when it answers, both to `~/.claude/logs/sessions.log`. Pairing them gives a **real distribution of
every probe the fleet has run since the fix**, at 1 s resolution — better evidence than any synthetic
re-run, and it needs no live-system perturbation.

```bash
# pairs 'MCP probe binary' → next 'MCP Status (attempt', excludes agent fixtures (fakeclaude)
python3 <pairing script>  < ~/.claude/logs/sessions.log
```

| day | n | min | **med** | p90 | max |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2026-08-11 *(the day of the fix)* | 112 | 0 | **3.0** | 4.0 | 6.0 |
| 2026-08-12 | 44 | 2 | **3.0** | 5.0 | 6.0 |
| 2026-08-13 | 23 | 1 | **3.0** | 4.0 | 7.0 |
| 2026-08-14 | 21 | 2 | **3.0** | 4.0 | 6.0 |
| 2026-08-15 | 25 | 2 | **3.0** | 5.0 | 8.0 |
| 2026-08-16 *(measurement day)* | 88 | 0 | **4.0** | 5.0 | 9.0 |
| **ALL** | **313** | 0 | **3.0** | 5.0 | 9.0 (mean 3.30) |

Holding composition constant (the modal 2-server probe, n=113):

```
first half  2026-08-11        n=56  med=3.0  mean=3.23
last  half  2026-08-11→08-15  n=57  med=3.0  mean=3.07
```

**Duration tracks server count, not date:**

| servers in that probe | n | min | med | p90 | max |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 35 | 0 | 1.0 | 2.0 | 3.0 |
| 2 | 113 | 1 | 3.0 | 4.0 | 6.0 |
| 3 | 96 | 1 | 3.0 | 4.0 | 7.0 |
| 4 | 46 | 2 | 4.0 | 6.0 | 9.0 |
| 5 | 27 | 3 | 4.0 | 5.0 | 8.0 |

And the 08-16 elevation is **not** a load ramp: pre-wave hours (00–14 h) med **5.0** (n=22), wave hours
(15–22 h) med **3.0** (n=70), 21 h med **1.0** (n=12). The distribution is dominated by *which config
dir / cwd* is being probed, not by time.

**Server inventory did not grow either.** 4 user-scope servers in `.claude`, `.claude-secondary`,
`.claude-tertiary`, `.claude-quaternary`; 3 in `.claude-next`
(`jq -r '.mcpServers|keys|length'`). Max rows ever emitted by a probe in the whole post-fix log = **5**;
the hook's own header records **6** at the time of the fix. Nothing was added.

⇒ **"grew 45%" is a comparison between a quiet-box hand-run trio (2.51 / 2.58 / 2.89 s, written into
`session-start.sh:87` on 2026-08-11) and one sample taken during a 12-agent research wave.** The hook's
own header already warns against exactly this: *"The clean-bench number is not the band."*

---

## 2. Keep-warm: confirmed a non-issue (ruling upheld, independently)

```bash
plutil -p ~/Library/LaunchAgents/com.claude.accounts-keepwarm.plist   # StartInterval => 180, --max-age 90
sed -n '74p' lib/claude-launcher.zsh
#   acct="$("$bin" --route interactive --max-wait 0 --max-age 600 2>/dev/null)"
```

180 s cadence ≪ 600 s launcher tolerance ⇒ always a HIT; a miss abstains (`rc=3` → PINNED) without
blocking. Nothing about the cadence change touches the startup path. Matches the wave's cleared-item
note. **Not a regression; do not re-litigate.**

---

## 3. 🚨 The real finding: the SWR refresher is BLOCKING, not BACKGROUNDED

### 3.1 Mechanism

`hooks/session-start.sh` `_mcp_spawn_refresh`:

```bash
( bash "${BASH_SOURCE[0]}" --refresh-mcp-cache >/dev/null 2>&1
  rmdir "$MCP_CACHE_LOCK" 2>/dev/null || true ) &
```

The **inner `bash`** has its stdout redirected. The **subshell** does not — it inherits the hook's fd 1,
which is the pipe the harness reads. The hook process exits in ~80 ms; the *pipe* stays open until the
refresher dies.

### 3.2 Two clocks, one hook, 40× apart

Real hook, real code, fixture `claude` binary that sleeps 3 s, scratch `CC_MCP_CACHE_FILE` aged 400 s
(> TTL 300) so a refresh spawns; n=5 per arm:

```bash
export CC_CLAUDE_BIN=$SP/fakeclaude CC_MCP_CACHE_FILE=$SP/cache CLAUDE_CONFIG_DIR=$SP/cfg
bash hooks/session-start.sh </dev/null > out.json     # ARM A: process-exit clock
out=$(bash hooks/session-start.sh </dev/null)         # ARM B: pipe-EOF clock
```

| arm | runs (ms) | median |
| --- | --- | ---: |
| A — process exit (what the wave measured) | 122 · 85 · 83 · 66 · 65 | **83** |
| B — pipe EOF (what a read-to-EOF harness sees) | 3098 · 3091 · 3096 · 3093 · 3102 | **3 096** |

### 3.3 Which clock does Claude Code use? — pty A/B, n=3 per arm

Throwaway `CLAUDE_CONFIG_DIR=/tmp/ssprobe/cfg`, one synthetic SessionStart hook that prints its JSON
and exits immediately after forking a 6 s child. `/help` typed at t=1.2 s (a purely local slash
command — zero tokens). Metric = last byte emitted.

```bash
PROBE_DUR=16 PROBE_TYPE="/help" PROBE_TYPE_AT=1.2 PROBE_OUT=… \
  CLAUDE_CONFIG_DIR=/tmp/ssprobe/cfg python3 /tmp/ssprobe/ptyprobe2.py \
  /Users/chrisren/.claude-220/node_modules/.bin/claude
```

| hook body | run 1 | run 2 | run 3 |
| --- | ---: | ---: | ---: |
| no background child | 1.376 | 1.414 | 11.484\* |
| `( sleep 6 ) &` — **fd inherited** | **6.549** | **6.421** | **6.439** |
| `( sleep 6 ) >/dev/null 2>&1 &` — fd closed | 1.402 | 1.390 | 1.401 |

\* one late-render outlier; the other two arms are 3/3 clean and mutually separated by ~5 s.

**The harness waits for stdout EOF.** A backgrounded child that inherits the hook's stdout blocks the
input pipeline for its full duration; closing the fd makes it genuinely free.

### 3.4 End-to-end on the real hook

Same pty harness, hook = the **actual** `hooks/session-start.sh` (fixture binary 3 s, `HOME` pointed at
a scratch dir so the live `sessions.log` is untouched):

| cache state | /help renders at (n=3) | median | delta |
| --- | --- | ---: | ---: |
| **fresh** (age 0 s, no refresh spawned) | 1.373 · 1.389 · 1.403 | 1.389 | baseline |
| **stale** (age 400 s ⇒ refresh spawned) | 3.514 · 3.594 · 3.701 | 3.594 | **+2.205 s** |

The block is `hook_start + probe_duration − typed_at`. With the fleet's real p50 probe (3.0 s) that is
**+2.2 s**; at p90 (5.0 s) **+4.2 s**; at the observed max (9.0 s) **+8.2 s**.

### 3.5 The hook's `timeout:` does NOT bound it

`~/.claude-secondary/settings.json` gives `session-start.sh` `timeout: 10`. With a 12 s fixture probe:

| configured hook timeout | /help renders at (n=2) |
| ---: | --- |
| 30 | 12.801 · 12.476 |
| **10** | **12.499 · 12.479** |

The harness timeout kills the *hook process* — which already exited at ~80 ms — so it has nothing to
reap and keeps reading the orphan's pipe. **Unlike `mailbox-drain` (reaped at 5 s), this one has no
harness-side ceiling at all.**

---

## 4. Exposure — how often, and the unbounded tail

- **54.4 % of session starts run a probe.** Post-fix window (2026-08-11 03:19 → now), agent fixtures
  excluded: **338 probes / 621 real session starts**.
- **All four live caches are stale right now**: `.claude-next` 19 917 s, `.claude-quaternary` 19 900 s,
  `.claude-secondary` 19 978 s, `.claude-tertiary` 224 s — against `TTL=300`. Three of four will spawn a
  blocking refresh on their next start.
- 🚨 **`timeout`/`gtimeout` are unresolvable on a subset of live sessions**, which makes the hook's own
  `PROBE_TIMEOUT=10` / `PROBE_BUDGET=15` **inert** there:

  ```bash
  pid=$(pgrep -f "claude-220/node_modules/.bin/claude" | head -1)
  ps eww -p "$pid" | tr ' ' '\n' | grep -m1 '^PATH='
  #   PATH=/Applications/kitty.app/Contents/MacOS:/usr/bin:/bin:/usr/sbin:/sbin   ← no /opt/homebrew/bin
  ```

  Sampled 14 readable live claude processes: **10 have `/opt/homebrew/bin` on PATH, 4 do not.** On those
  4, `_TIMEOUT_BIN=""` and `claude mcp list` runs with **no timeout**, blocking the input pipeline for
  however long it hangs. This is the honest explanation of the wave's **31.6 s cold tail** — that was
  31.6 s of *blocked input*, not detached work.

  *(Instrument note against myself: my first check reported both binaries ABSENT — because the **Bash
  tool's own** PATH is the same stripped one. The finding survived only because I then read a live
  process's environment instead of trusting my shell.)*

### What this does to the ranking

Group cost is MAX not SUM, so:

- **Fresh panes (52 % of starts)** — `mailbox-drain` early-exits (38 ms) and the group max is
  `setup-task-symlinks` at 633 ms. A stale MCP cache makes **`session-start.sh` the group max at
  ~3.5 s** ⇒ marginal cost **≈ +2.9 s, today, additive.**
- **Reused panes** — currently masked by `mailbox-drain`'s 5 s reap. **But the moment S1 lands, this
  becomes the new group max**, and the wave's promised ~4 s win is roughly **halved on 54 % of starts**.
- **Who actually feels it:** the freeze window is the session's first ~3.5 s. A human who takes >4 s to
  type pays 0. A **dispatched/fired session whose prompt is auto-submitted at t≈0** pays the whole
  thing — and that is the fleet's dominant start shape.

---

## 5. Fix — one line, validated, recovers 100 %

```diff
-  ( bash "${BASH_SOURCE[0]}" --refresh-mcp-cache >/dev/null 2>&1
-    rmdir "$MCP_CACHE_LOCK" 2>/dev/null || true ) &
+  ( bash "${BASH_SOURCE[0]}" --refresh-mcp-cache >/dev/null 2>&1
+    rmdir "$MCP_CACHE_LOCK" 2>/dev/null || true ) >/dev/null 2>&1 &
```

Patched copy, same pty harness, stale cache, n=3:

| | /help renders at | vs fresh-cache baseline |
| --- | --- | --- |
| **fixed, stale cache** | 1.374 · 1.381 · 1.393 | **identical** (1.373 · 1.389 · 1.403) |

And the refresher **still completes and still writes the cache** (`v1 1786945402 ok 1 0`, written ~3 s
after the hook returned). No function lost.

**Refutation angle #3 does not hold**: the fix recovers the time and breaks nothing. The honest caveat
is that it converts the refresh from *blocking* into *genuinely detached* — i.e. into **M2** (a 325 MB
CLI contending with turn 1). That is strictly better than blocking on it, and it is the state the whole
fleet already believed it was in.

**Two adjacent items this exposes (file, don't bundle):**
1. `_TIMEOUT_BIN` empty ⇒ no probe timeout. Either hard-path `/opt/homebrew/bin/timeout`, or implement a
   shell-level watchdog. A documented bound that silently does not apply is worse than no bound.
2. **Audit every other hook for the same fd-inheritance shape** — this defect is invisible to every
   process-exit-clock benchmark the fleet owns, including `scripts/hook-latency-probe.sh` and the
   wave's own `tw.sh` wrapper. Grep for `) &` and `&$` in `hooks/*.sh`.

---

## 6. Corrections this file makes to `COLD_START_100P.md`

| line | says | should say |
| --- | --- | --- |
| **658** (Ruled out) | *"SWR detaching a second CLI is a hotspot — Hook returns in 69 ms … a process nothing blocks on. Keep the SWR."* | **Un-rule-out.** 69 ms is the process-exit clock; the harness uses the **pipe-EOF** clock. Real cost **+2.2 s p50 / +4.2 s p90 BLOCKING** on 54.4 % of starts, unbounded where `timeout` is unresolvable. Keep the SWR — **and close the fd.** |
| **226** (T-class table) | `session-start.sh` MCP line — *"SWR is correct and holds (2.52 s → 0.036 s). Only its MAX_AGE fallback violates the T4 rule."* | The **TTL path** violates it too. The `MAX_AGE` cliff (~10 ms/start amortised) is the *smaller* of the two. |
| **281** (M2) | *"costs the hook 69 ms and detaches a 325–329 MB second CLI … competes with turn 1"* | It does not merely *compete* with turn 1 — **it precedes it**. Today the deferral is not deferral. |
| **350** (PART C) | `session-start.sh | 159 (2 655 cold) | CONCURRENT` | **BLOCKING** whenever the cache is older than 300 s. The 159 ms in-situ figure was measured through a wrapper that also uses the exit clock, so it could not have seen this. |
| §7 Prior-art "Still holds" | *"`session-start` SWR 2.52 s → 0.036 s warm"* | Holds **only** for the fd-closed case, which is not the shipped code. |

**A note on why two independent passes missed it, because it is the same shape as C2.** C2 records that
both prior waves benchmarked `mailbox-drain` under `env -u ITERM_SESSION_ID`, i.e. its early-exit guard.
This is the identical failure one layer down: **every hook harness in this fleet times the hook's
`wait()`, and the harness under test times its `read()`.** A benchmark that does not use the same
completion predicate as the system it models cannot see this class of defect at all. Invariant **I7**
should be widened from *"never strip the hook's real input"* to *"the probe's completion predicate must
be the harness's completion predicate."*

---

## 7. Method, safety, and self-disclosed contamination

- **Zero** `claude -p` calls; zero tokens. Every pty run typed only `/help` (local command) and was
  SIGINT+SIGKILLed by `ptyprobe2.py`.
- No live config, hook, `.zshrc` or settings file was edited. The patched hook is a **copy** at
  `/tmp/ssprobe/session-start-FIXED.sh`. `/tmp/ssprobe/cfg/settings.json` (a throwaway dir created by
  the earlier wave) was used and **restored to `{"hooks":{}}`**.
- No process I did not start was signalled.
- ⚠️ **Contamination I caused, disclosed:** my first fd test (§3.2 ARM A/B, 10 runs) ran before I added
  the `HOME` override, so it appended **20 lines** to `~/.claude/logs/sessions.log`
  (`Session started in …` + `MCP probe binary: …/scratchpad/fdtest/fakeclaude`). A prior agent left 14
  more at 16:53 (`/tmp/fakeclaude`). **Every number in §1 and §4 excludes them** (`grep -v fakeclaude`
  plus a look-ahead filter on the paired start line); the unfiltered vs filtered medians are identical
  (3.0 s), and n moves 317 → 313 and 637 → 621. Future miners of that log must apply the same filter.
- **Un-measured (UNKNOWN):** the real `claude mcp list` wall time at ms resolution — I used the fleet
  log's 1 s quantisation rather than spawning real probes, because a real `mcp list` fires a phantom
  `SessionEnd` into 7 live consumers. The 1 s resolution is sufficient for the drift question and is
  the *conservative* direction for §3.4's arithmetic.
