---
status: open
created: 2026-07-31
owner: desk
---

# Terminal-agnostic pane layer → Level 3/4 — PLAN

**Status:** ACTIVE · created 2026-07-31 · survives crashes by design (this file IS the recovery point)

**Scope (frozen).** Make claude-infrastructure's pane layer terminal-agnostic behind ONE seam with a
HEADLESS-FIRST driver model, so that (a) no future terminal choice forces a migration, (b) Agent-Team
panes work on any terminal via an `it2` facade, and (c) the fleet can scale past the ~38-pane physical
ceiling toward Level 3 (~100 agents). Explicitly NOT in scope: migrating terminals, supporting three
terminals, or building kitty/cmux drivers speculatively.

> **Why this file exists.** This machine hard-crashed twice in 48 h (2026-07-30 compressor-segment
> panic; 2026-07-31 11:46 spinlock panic from a research probe's 8,368-thread ladder, which killed 19
> live sessions and a 12-hour measurement). Work has been repeatedly rediscovered. **Everything needed
> to resume is in this file — do not re-derive any of it.**

---

## 0. The decisions ALREADY MADE (do not re-litigate)

| # | Decision | Basis |
|---|---|---|
| D1 | **Do not build a terminal from scratch** | prize measured at **0.105 core = 1.05%** of the box; iTerm2→kitty already captures **92.4%** of the total available prize (12.2:1 split) |
| D2 | **Do not migrate terminals now** | the readable-pane ceiling is **38 panes** across all 3 displays — *physical*, identical for every terminal. A migration buys ≤38 when the target is 100 → 1000 |
| D3 | **Build ONE seam, TWO drivers: `iterm2` + `headless`** | at Level 3 ~95 of 100 agents need no pane; at Level 4 ~999 of 1000. Headless is the driver that scales |
| D4 | **kitty/cmux drivers only when/if we actually switch** | ~150 lines each behind a proven interface; building them now is guessing |
| D5 | **The `it2` facade is how Agent Teams work anywhere** | Claude Code shells out to an EXTERNAL `it2` CLI (`ERROR: iTerm2 detected but no it2 CLI`); it has **0 KittyBackend / 0 GhosttyBackend** (40 ITermBackend, 32 TmuxBackend). We already intercept `it2` in `bin/it2-wrapper` |
| D6 | **The real ceiling is QUOTA, not hardware** | live read 2026-07-31: next2 **95%** weekly, next 69%, next4 62%, next3 35%. 100 concurrent = 21.5 GB / 3.6 cores — *fits*. Level 4 volume is quota-bound on 4 Max plans |

---

## 1. Measured evidence base (all on this box — never re-derive)

**Physical ceiling.** Readable 80×20 TUI pane ≈ 600×340 logical px ⇒ built-in 6 + DELL 16 + DELL 16 =
**38 panes total**, already unreadably dense. Level 3 (100) is 2.6× over; Level 4 (1000) is 26× over.

**Resource ceiling.** 215 MB and 0.036 cores per session ⇒ 100 sessions = **21.5 GB / 3.6 cores (fits)**;
1000 *simultaneous* = 215 GB (impossible) but Level 4 is **throughput, not concurrency**.

**Cost model — the true axis is NOT the graphics API.** Three orthogonal terms, fitted from the four
compositor arms {1w×1s 9.6pp · 1w×30s 11.2pp · 6w×5s 17.5pp · 30w×1s 22.6pp}:

| Axis | Coefficient | Lever at 30 panes |
|---|---|---|
| **Presentation cadence** | 0.480 pp/Hz | **9.6pp — dominant (6× the surface lever)** |
| OS-window count | 0.4483 pp/window | 13.0pp across 1→30 |
| Surface count *within* a window | 0.0552 pp/surface | 1.60pp ceiling — 8.1× cheaper per unit than a window |
| Metal vs OpenGL vs CPU | — | **not a term in the model** |

**Threads per pane (measured, one ruler):** kitty **flat ~10 @ 48 panes** (one GL context per window,
panes as `glViewport` sub-rects, one `CVDisplayLink` **per monitor**) · **cmux 5.18/pane linear**
(fit `5.18×panes + 10.6`; 2→21, 8→53, 13→78; ⇒ ~166 @ 30) · Ghostty **4.00/pane linear**
(`6 + 4.00×panes`; 24 panes in ONE window = 101 threads, 0.0% idle CPU, 351 MB) · iTerm2 ~0.9/pane.

> ⚠ **The thread axis above is RETIRED as the decisive criterion (2026-07-31 PM, `4faa1cb6`)** — still
> true, no longer load-bearing. WezTerm measured **4.00**/pane, not the ~7.0 published, and §8's own
> kill condition for the thread finding **fired**: 87 WezTerm threads produced *fewer* context
> switches than kitty's 10. The axis that survived a matched-load test is **loaded app CPU** — 18
> panes, byte-identical stream, all at 10.00 achieved fps ⇒ **kitty 9.5% · WezTerm 24.4% · Ghostty
> 27.3%**, kitty carrying 22% *more* bytes. **D2 is reinforced, not weakened:** the one iTerm2
> datapoint in the *cheap* layout (1 window × 20 panes, CPU renderer) read **10.5% against kitty's
> 9.5%** — the incumbent has not been beaten, and the migration is explicitly on **HOLD**. This is
> also why D3 (the seam) is the right shape: `CC_PANE_ID` costs the same whichever terminal wins.

**iTerm2 today:** renderer+compositor = **2.74–4.08× the whole agent fleet** (median 2.89×, five
samples); **+76 mach ports/hr drift at frozen layout** while RSS falls; perf-parity `match=9 drift=0`
⇒ **tuning is exhausted**. *(That +76/hr remains the only clean drift number in the corpus — a
30-minute kitty counterpart was attempted 22:17Z and failed its constant-layout precondition; see
`terminal-for-30-panes` §6.1.)*

**Memory is exonerated (4×):** both panics non-memory; 31 live sessions at 93% free / `Pageouts: 0`;
compressor 0 B at load 15.

**Coupling census (production files, tests excluded):**

| Class | Files | Work |
|---|---|---|
| 1 — shells out to `it2` | **12** | **zero** — already behind the wrapper seam |
| 2 — reads `$ITERM_SESSION_ID` | **18** | mechanical rename → `CC_PANE_ID` |
| 3 — AppleScript at iTerm2 directly | **6** | real porting |
| total touching iTerm2 | 44 | — |

Class-3 files: `scripts/handoff-fire.sh` (4,024 lines — highest risk in the repo), `boot-resume-launch.sh`,
`handoff-selfclose-e2e.sh`, `render-census.sh`, `limit-recover/lr-handoff.sh`, `limit-recover/lr-reset-poller.sh`.

---

## Phase 0 — Agent Team Orchestration

Four independent tracks; no shared file between them. T1 and T2 may run concurrently from the start.
T3 depends on T1's interface landing. T4 is independent throughout.

| Track | Deliverable | Owns (no overlap) | Blocked by |
|---|---|---|---|
| **T1** | `CC_PANE_ID` + 4-verb driver interface (`spawn`·`address`·`send`·`close` + `list`), `iterm2` driver = today's behaviour | `bin/cc-pane` (new), `bin/it2-wrapper` | — |
| **T2** | **`headless` driver** — spawn returns an addressable id with NO surface; the agent surfaces only via the queue | `bin/cc-pane-headless` (new), registry glue | — |
| **T3** | Port the 6 class-3 files behind the interface, `iterm2` path staying default until headless is proven | the 6 named files | T1 |
| **T4** | Queue front-end over `cc-permission-beacon.sh` — one row per agent, blocked-first | `bin/cc-queue` (new) | — |

**Rails for every track:** dedicated worktree + own branch · gate green before commit · land ONLY via
project-local `/ship` · C10 (never edit settings.json / live hooks / launchd in place) · brief ≤150 lines.

---

## 2. Phases

### P1 — the seam (T1) — ✅ **DONE**, landed on `origin/main` 2026-07-31
`bin/cc-pane`: 4 verbs + `list`, driver-selected by `CC_PANE_DRIVER` (`iterm2` default), the
`iterm2` driver built in and reproducing today's behaviour — verified against the **live** iTerm2,
not only fakes: 16 panes enumerated, self-address stripping `w3t0p5:` correctly, id round-tripped
through the real `it2`. `CC_PANE_ID` landed at **17 class-2 own-env sites across 15 files**, with
`ITERM_SESSION_ID` kept as a read fallback for one release. The 12 class-1 files were **not
touched**.

| sha | what |
|---|---|
| `1f7be212` | the seam + both drivers |
| `457c19db` | 38 tests across seam + headless |
| `b2601ced` | red-proof mutation harness (and the weak test it exposed) |
| `6c94a26d` | `CC_PANE_ID` at the 17 class-2 sites |
| `3ff736cb` · `82ebb42d` · `93f2f605` | three test defects the land gate caught (§6.10) |

### P2 — headless driver (T2) — ✅ **DONE**, landed on `origin/main` 2026-07-31
`bin/cc-pane-headless` (`1f7be212`): `spawn` mints an id and starts the agent with **no surface**,
`address`/`send` work by id, `close` reaps TERM→KILL and is **ps-verified**. The registry holds
*claims*, the OS holds *truth* — liveness is pid + start-time + process state, and `list` reaps what
it disproves, so a reboot is self-healing rather than leaving confident corpses. Design rule held:
nothing in the contract assumes a surface (§6.4), and the suite proves it by putting poisoned
`it2`/`osascript`/`tmux` stubs on `PATH`.

**Not yet true, and neither is T1/T2 scope** — both named precisely rather than implied:
the **class-B** env-scrapers of §6.9 still cannot see a headless agent, and nothing yet *drains* a
headless inbox. `send` guarantees durable delivery, never consumption; P4's queue is what closes
that. Until both land, headless is addressable but not yet load-bearing.

### P3 — port the 6 (T3)
Incremental, never a cutover: each file gains the interface call with the iTerm2 path as default.
`handoff-fire.sh` last and in slices — it fires sessions and is the most dangerous file in the repo.

### P4 — the queue (T4) — ✅ **DONE**, landed on `origin/main` 2026-07-31
`cc-permission-beacon.sh` already fires on `PermissionRequest` → `/tmp/cc-permission-pending/<sid>.json`.
It has no face. 100 rows fits one screen; 1000 needs grouping (a list problem, not a rendering one).

**Shipped:** `bin/cc-queue` — blocked-first list across ALL 4 config dirs, exact blocked command + wait
duration, `--attach` to jump, `--group-by`/filters for scale, `--check` as a gate. 1000 rows in 0.39 s.
Full design, measurements, and learnings in **§7**.

### P5 — `it2` facade (after P1)
Widen `bin/it2-wrapper` to serve the same 4 verbs so Agent-Team panes work under any driver without
Claude Code knowing. Contract to reverse: `session split` · `session send` · `session close` · `session list`.

---

## 3. Free wins, independent of all of the above

1. **Drop the 120 Hz DELL to 60 Hz** — cadence is the dominant compositor term (0.480 pp/Hz) and a text
   UI gains nothing from 120 Hz. One click, reversible.
2. **Do NOT set `NODE_OPTIONS=--max-old-space-size`** — `claude.exe` is a compiled Mach-O already
   carrying `--max-old-space-size=8192`; the flag is either inert or an 8× cut, and can only bind
   during a spike, i.e. only ever kills a session mid-task.
3. **Stop the automation minting windows** — windows are the 2.35× unit.

---

## 4. NOT established (open, and honest)

1. **kitty multi-hour drift at constant layout** — the 12 h/48-pane run was destroyed by the 11:46 panic
   before its second reading. §6.1 of `terminal-for-30-panes-2026-07-31.md` remains OPEN.
   → **STILL OPEN, but no longer from zero** — §4.1 below has the partial evidence, the harness, and
   the exact resume command. Nothing here needs re-deriving.

### 4.1 PARTIAL — kitty drift: nothing leaking yet, but the 6 h reading is not in hand

**Status: the falsification test has not yet been passed or failed.** What exists:

| Reading | Window | Result |
|---|---|---|
| `terminal-bench.sh --app kitty --panes 30 --interval 1800` | 30 min | **`verdict=OK`** — mach ports **−16.0/hr**, mem −8.0/hr, **0.27 threads/pane**, GPU path 62:1 |
| `kitty-drift-run.sh` run 1 | 90 min, 7 samples | ports **+4.0/hr**, threads 6→9, mem +53/hr |

**Do not publish either as the verdict.** The two windows disagree in *sign*, so the series is
oscillating in a ±16 band around ~360 ports with no monotone trend — which is exactly the state a
short window cannot distinguish from a slow leak. The iTerm2 figure this must be compared against is
**+76 mach ports/hr at frozen layout while RSS falls**; nothing measured so far resembles that, but
"resembles" is not a leak verdict. Window count is noisier still (36→19 in 30 min) and is not a usable
instrument at this timescale.

**Run 1 died at t+90m and the harness called it OK.** The kitty instance vanished — almost certainly a
human closing an unexplained 30-pane grid, which is a reasonable thing to do to a window that does not
say why it exists. The script kept looping, wrote no further rows, and would have printed `verdict=OK`
on seven stale samples after 4.5 h of measuring nothing, because the verdict was earned by a *sample
count* and an empty `top` row was a silent skip. **Silence was the success path.** Fixed and
positive-controlled (`589d541c`): subject death is separated from a transient miss by `kill -0`, the
layout is re-checked against what was built, the verdict now requires 90 % of the window to have
*elapsed*, and `--pid` pins the subject because `pgrep -x kitty | head -1` chooses arbitrarily whenever
more than one kitty runs. The window is now titled `DO-NOT-CLOSE`.

**Run 2 is live** — pid-pinned, socket `unix:/tmp/kitty-drift2`, 30/30 panes, started 2026-07-31
23:20 UTC, due ~05:21 UTC. Data lands at
`docs/research/data/kitty-drift-run2-2026-07-31.tsv` (durable, not `/tmp`).

**To finish this gap — read the TSV, no re-derivation:**
```bash
git log --oneline --grep='data(kitty-drift): run 2 result'   # the verdict + the fitted rates
tail -3 docs/research/data/kitty-drift-run2-2026-07-31.tsv   # the series itself (TRACKED)
# fit first-vs-last on ports (col 6) / threads (col 5) / mem (col 4); ≥0.9 of 6h must have elapsed
```
⚠ **The `.log` is NOT on trunk** — `.gitignore:11` is `*.log`, so `kitty-drift-run2.log` exists only
in the worktree that ran it. The verdict token therefore reaches trunk **through the collector's
commit message**, and the data through the `.tsv`. Do not write a resume instruction that points at
the log: on a fresh clone it reads as an empty file, which is indistinguishable from a run that never
happened.

`scripts/kitty-drift-collect.sh` was left running detached to commit the result when the run exits,
so the series lands whether or not a session is still watching. It **commits and stops** — landing
stays a decision with a person behind it.
`verdict=ABORTED-*` ⇒ the run is void, re-run it; it does **not** mean kitty leaked. Re-run:
`scripts/kitty-drift-run.sh --hours 6 --panes 30 --pid <kitty-pid> --socket unix:/tmp/kitty-drift2`

**Two confounds to state with whatever number comes out**, not to discover later: the box was at
**load ~27** with a sibling session actively benching kitty on the same host, and this is **30 panes,
not the 48** of the destroyed run — 48 shells plus the sampler's children lands at ~86-90 % of the
64-process safety ceiling held for six hours, and drift is a rate, so 30 measures the same leak with
headroom. Scale accordingly rather than comparing pane-counts directly.
2. ~~**cmux socket auth from outside** — `socketControlMode: "passwordOrCmux"` is NOT a valid enum; the
   correct value is unknown, and without it external automation cannot drive cmux.~~
   → **CLOSED 2026-07-31**, §4.2 below · `docs/research/cmux-external-control-2026-07-31.md`.

### 4.2 CLOSED — cmux socket auth: `automation` (no secret) or `password` (shared secret)

**External automation CAN drive cmux.** The plan had the field name right and the *value* invented:
`grep -a -c passwordOrCmux` over the 208 MB app binary returns **0** (calibration: `socketControlMode`
returns 24). Published schema `/properties/automation/properties/socketControlMode`:

| Value | Meaning (verbatim from shipped UI strings) | External automation? |
|---|---|---|
| `off` | "Disable the local control socket." | no socket |
| **`cmuxOnly`** (default) | "Only processes started inside cmux terminals can send commands." | **BLOCKED** |
| **`automation`** | "Allow external local automation clients from this macOS user (no ancestry check)." | **YES — no secret** |
| `password` | "Require socket authentication with a password stored in a local file." | YES — shared secret |
| `allowAll` | "Allow any local process and user to connect with no auth. Unsafe." | **do not use** |

Nine schema values but only five canonical; the other four are a lowercased legacy-alias
normalization table. **`automation` is the right one for us** — it drops only the process-ancestry
check, staying scoped to this macOS user, and needs no secret on disk.

**Proven end-to-end from an iTerm2-parented shell** (a genuine external caller, not a cmux child):
`cmux list-panes` · `cmux new-split right --workspace workspace:1` · `cmux send … "echo … >
/tmp/cmux-proof.txt"` — and the send **executed**, confirmed by an independent on-disk oracle, not
just by a zero exit. Negative control: under the untouched `cmuxOnly` default the same caller is
refused with `Access denied - only processes started inside cmux can connect`.

**⚠ Operational blocker, separately verified and NOT an auth problem:** cmux 0.64.20 **deterministically
wedges at 100 % CPU with unbounded RSS when launched with no workspace to open** — 6/6 launches, in
every socket mode including the untouched default. Launch as `cmux <path>` instead; that path is
healthy. Anything automating cmux must always pass a path.

**Consequence for D4 (kitty/cmux drivers only if we switch):** the cmux driver is now *unblocked* —
external drive is a settings change, not a patch. D4 stands on its own merits; it is no longer
blocked on an unknown.

**Config safety:** `~/.config/cmux/cmux.json` was edited twice and restored from a pristine pre-edit
copy; final sha256 **matches** the recorded pre-edit hash (independently re-verified here). The revert
was also confirmed *behaviourally* — the app refused the external caller again — because a
byte-identical file is not sufficient on its own: cmux imports file-managed values into UserDefaults.
Probe password file, probe sockets and cmux's own probe-triggered backup were removed; cmux left not
running, as found.

> **Pre-existing hygiene item, surfaced not fixed:** `~/.config/cmux/cmux.20260731T204525.bak` (13:45
> today, *before* this session) is the artifact of the earlier experiment that produced the bogus
> value — it still contains `"socketControlMode": "passwordOrCmux"` **and a plaintext
> `"socketPassword": "bakeoff-temp-…"`**. A throwaway local-socket password, but a plaintext secret at
> rest in the config dir. Deleting files in the operator's config dir is the operator's call.
3. ~~**The exact `it2` contract surface** Claude Code calls — reversed only partially.~~
   → **CLOSED 2026-07-31**, §4.3 below · `docs/research/it2-contract-surface-2026-07-31.md`.
4. ~~**Agent View coverage** — `claude agents --json` is scoped to `CLAUDE_CONFIG_DIR`; it saw 3 of 25
   sessions. A 4-account fleet fragments into 4 views.~~
   → **CLOSED 2026-07-31**, §4.4 below · `docs/research/agent-view-coverage-2026-07-31.md`.

### 4.4 CLOSED — Agent View coverage: one view for SEEING, N for DISPATCH

**Verdict: one view CAN aggregate the 4-account fleet for observation, and CANNOT for dispatch.**
The only scoping input is the single path `join(CLAUDE_CONFIG_DIR, "sessions")` — a *directory*, with
no account identity anywhere in the read path and **no auth required**. But a session launched *from*
the view inherits the view process's own `CLAUDE_CONFIG_DIR`, so a unified view can only ever start
work on one account. **N views is structural for starting work, not for seeing it** — so the
operator's account-sharding survives Agent View for monitoring, and only the launch path stays
per-account.

**`CLAUDE_CONFIG_DIR` does not accept a list, and fails SILENTLY.** Measured: single path → rows;
`"$A:$B"` → **0 rows, no error** (`readdir` throws on the bogus path, `catch { return [] }`). An
operator who tries the obvious thing gets an empty view and no diagnostic.

**The cheapest real fix already exists in production.** Symlink each account's `sessions/` **directory**
to one shared real directory — `~/.claude-next/sessions -> ~/.claude/sessions` has been doing exactly
this since 2026-06-03 (verified live). No code, no patch, no upstream change.

**⚠ The obvious variant is a trap: per-FILE symlinks read as ZERO, silently.** `qI()` uses `lstat`, so
`isFile()` is false for a symlink and every row maps to `null` — no warning, no telemetry. Verified
back-to-back on the same directory: **symlinked files → 0 · copied files → 3** (positive control). A
symlinked *directory* is fine because `readdir` follows it and the entries inside are real files.

**Loop-and-merge works today with zero config change:**
`for d in $DIRS; do CLAUDE_CONFIG_DIR=$d claude agents --json; done | dedupe-by-pid` — a **complete**
aggregation of the registry, ~1.4 s wall for four accounts. Dedupe by `pid` is **mandatory** (the
`.claude-next` symlink means two roots enumerate one registry). `--json` only; no TUI equivalent.

**Coverage, with denominators that are stated rather than blurred** (ground truth taken independently
of `claude agents`, by argv0-**position** census — `pgrep -f`-style substring matching reads ~122 where
the truth is ~15, the 6-8× trap this repo has recorded before):

| View | of live REPL sessions (D_sess≈13) |
|---|---|
| default (`~/.claude`) | **7.7 %** |
| best single account | 38.5 % |
| loop-and-merge / shared registry | **92.3 %** |

**The plan's recalled "3 of 25" is retired, not corroborated** — no denominator on this box
reproduces 25 (disk truth is ~13 live REPLs / ~15 processes / ~122 naive). Do not treat it as a
second data point.

**Second, orthogonal defect — the residue is NOT a scoping failure.** `NDc()` returns before writing
when `CLAUDE_CODE_CHILD_SESSION` is set, interactive, and **not** in tmux. Claude Code sets that var on
every process it spawns ⇒ **any interactive `claude` REPL launched from inside another session's Bash
tool, outside tmux, is invisible to Agent View — including in its own account's view.** That is
precisely this fleet's handoff / dedicated-split-pane pattern, and no amount of view-merging fixes it.
Escape hatch exists: `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE`.

### 4.3 CLOSED — the `it2` contract surface (T1/T5 unblocked)

Recovered as **readable JavaScript** from `claude.exe` 2.1.219 (the Bun bundle stores its JS as plain
text), then confirmed against the real `it2` 0.2.3 CLI and its Python source. `strings(1)` alone was
not sufficient and would have been actively misleading: its 4-char default drops every 2-char flag,
so an argv rebuilt from it is missing exactly `-v`, `-s`, `-f`.

**The headline is resolution, not argv — and it falsifies a claim this repo relies on.** Claude Code
runs `$SHELL -lc "command -v it2"` **once**, caches the resulting **absolute path**, and execs that
path forever (`Uor` → `ocs` → `Drn`). Measured here: it resolves to `~/.local/bin/it2` (the raw uv
CLI) because the **login** PATH puts `~/.local/bin` at position **1** and `~/.claude/bin` at **15**,
and the lookup finishes in 0.02 s against CC's 2000 ms bound — so the bare-name fallback, the only
branch a PATH search could reach, is never taken.

⇒ **`bin/it2-wrapper` is bypassed for Claude Code's own teammate panes.** Its header claim that it
intercepts "Claude Code's native ITermBackend killPane — both spawn PATH-resolved `it2`" is false on
this box. All three interceptions are lost for CC's panes: the `-p Claude-Teammate` never-prompt
profile (those panes do **not** close cleanly from ⌘W), the `force=True` modal suppression (CC's
`killPane` **does** pop the running-job modal), and the 30 s bound on the fleet's hot liveness probe.
**This decides where the facade lives: it must win a LOGIN-shell lookup.** A shim on the current
process PATH cannot even *observe* CC's it2 traffic — verified with an instrumented shim and a real
teammate spawn that recorded **zero** calls.

**The contract — complete; there is nothing else in the class:**

| Verb | exact argv | stdout contract |
|---|---|---|
| split (1st, leader known) | `session split -v -s <leaderId>` | `Created new pane: <id>` |
| split (1st, no leader) | `session split -v` | ” |
| split (subsequent) | `session split -s <lastTeammateId>` · else `session split` | ” |
| send | `session send -s <id> $'\x15'` **then** `session run -s <id> <cmd>` | — (only `run`'s code is checked) |
| close | `session close -f -s <id>` | code 0 ⇒ true |
| list | `session list` — **no `--json`** | must exit 0; ids must be FULL (below) |

- `-v` is **`--vertical`, not verbose**, and appears **only on the first split** — subsequent splits
  are horizontal. Reading it as verbosity gives wrong geometry on every pane after the first.
- Leader id = `ITERM_SESSION_ID` with everything up to and including the **first colon** stripped;
  **no colon ⇒ null**, silently downgrading to the untargeted shape. A facade minting ids for another
  terminal must emit `<prefix>:<id>`.
- Split output is parsed `/Created new pane:\s*(.+)/` then `.trim()` — greedy to end of line, so any
  trailing text on that line **becomes part of the id**.
- `sendCommandToPane` makes **two** calls: `send` (Ctrl-U, clears the input line) then `run` (appends
  `\r`). Implementing one verb either leaves stale input or never submits.

**Both deployed tracks are live and they disagree on exactly this verb.** `claude-latest` pins
**2.1.114**, while **15 running processes are 2.1.219**. 2.1.114 issues `session run` alone — the
string `"session","send"` is **absent from that binary entirely**; the Ctrl-U prelude landed between
2.1.114 and 2.1.183. Split shapes, `killPane` and the `session list` liveness path (truncation
included) are **identical across all three**. ⇒ a facade validated only against the pinned stable
would never observe `send`, then silently drop the line-clear for every 2.1.219 session.

**`session list` is structurally broken as a liveness test.** CC's dead-session check is
`!stdout.includes(fullSessionId)`, but `rich` truncates the Session ID column to the 80 columns it
assumes when stdout is a pipe: `A5B61882-E2AD-438D-…`. Measured — full id absent, 18-char prefix
present (positive control), `COLUMNS=250` restores it. So the check always reads "dead": CC prunes
teammates unconditionally, on no evidence. A facade printing **full ids** makes that check work —
strictly better than real iTerm2 behaves today.

**`claude -p` is unconditionally in-process — no pane, no backend, no `it2` call at all**
(`isInProcessEnabled`: "true (non-interactive session)"). That is not a caveat, it is **D3/P2 already
true in the product**: headless is the norm and the pane is the exception. P2 is building what the
product already does — the strongest available evidence the seam is drawn in the right place.

**Minimum viable facade**, ordered by what breaks first: win the login-shell lookup · `session list`
exit 0 with full ids · `session split` printing that exact line · colon-bearing ids · `send`
tolerating `\x15` · `run` appending `\r` · `close -f -s` · non-zero + stderr on real failure.
`capture`, `focus`, `set-var`, `restart` and `monitor` are **never** called by ITermBackend.

---

## 4b. QUEUED FOR A SUCCESSOR — not done, not dropped (2026-07-31 recycle boundary)

Three tracks were fired at 14:18-14:27 (T1+T2 seam+headless · T4 queue · R1 the four gaps), all on
`next4`, all engagement-confirmed, all carrying the crash-durability clause. They own the
implementation. What the LEAD still owed and did not finish:

**Q1 — the landed docs carry a premise the workflow later FALSIFIED.** Both `README.md` §6 and
`docs/research/l3-l4-terminal-and-workflow-2026-07-31.md` still say, in effect, *"maximising the GPU is
backwards"*. That was derived from iTerm2's per-pane `CAMetalLayer` and over-generalised into a claim
about GPU rendering as such. It is **wrong as stated** — Ghostty is Metal-native AND per-pane and
measures 24 panes in one NSWindow at 0.0% idle CPU. Replace with the three-term model in §1 above
(cadence 0.480 pp/Hz dominant · window 0.4483 pp · surface 0.0552 pp · **graphics API is not a term**).
Exact sites: `README.md:480`, and `l3-l4-terminal-and-workflow-2026-07-31.md:163,183,355,357`.

**Q2 — an internal contradiction is live on trunk.** `terminal-for-30-panes-2026-07-31.md` §5b claims
kitty makes the `tmux-panes-inherit-server-iterm-session-id` hazard class *disappear*; §5a establishes
that on kitty, teammate spawning falls to the **tmux** path. Both cannot hold — and `strings` on both
live binaries confirms **0 KittyBackend / 0 GhosttyBackend** (40 ITermBackend, 32 TmuxBackend), so on
kitty every tmux pane shares one `KITTY_WINDOW_ID` exactly as they shared one `ITERM_SESSION_ID`. Same
hazard, new spelling. Fix §5b; do not delete §5a.

**Q3 — the operator asked for hands-on evidence IN the README, plus a recording.** Requested verbatim:
link or contain the hands-on evidence, and a 1080p60 recording of the terminal test's
visualisation/animation/colouring, *"to ensure the README demonstrates we validated against real
testing not just comparing summaries/source code at a reading glance."* The repo's existing convention
is the model: `assets/demo/handoff-real.webp` (VHS, re-runnable, `gif2webp` lossless for flat terminal
output) and `assets/demo/handoff-live.webp` (real screen capture, **`img2webp -near_lossless 40`** —
ordinary lossy WebP seams flat greys). The natural subject is `scripts/terminal-bench.sh` emitting real
`verdict=` lines plus the drift readings. See the `demo-recording` skill for the measured encode
recipes and the mandatory contact-sheet review.

**Q4 — Ghostty's thread count is wrong in the older doc.** `terminal-for-30-panes-2026-07-31.md:377`
says "3 threads/pane"; measured **4.00/pane** (`renderer`, `io`, `io-reader`, `cf_release`), fit
`6 + 4.00×panes`, confirmed to 24 panes.

**Q5 — cmux is absent from the README §6 candidate table** and now has measured numbers:
**5.18 threads/pane linear** (`5.18×panes + 10.6`; 2→21, 8→53, 13→78 ⇒ ~166 at 30 panes),
~10.5 MB/pane, libghostty renderer, full socket control API with `CMUX_SURFACE_ID`, and a built-in
console layer (sidebar row per pane, blue ring on attention, notifications panel, `Cmd+Shift+U`,
`notify` CLI). It does NOT dominate kitty — it wins on the console axis and loses on threads.

### 4b-STATUS — Q1·Q2·Q4·Q5 CLOSED 2026-07-31 (successor lead, branch `docs/l3l4-readout-evidence`)

| Q | State | Commit | What landed |
|---|---|---|---|
| Q1 | **CLOSED** | `4455f175`, `ffddbaa9` | Falsified premise retracted **in place** at all 5 sites (4 in the research doc, 1 in README). Superseded reasoning kept visible, not deleted, so the retraction is auditable. |
| Q2 | **CLOSED** | `a1793357` | §5b gains a correction subsection quoting its own withdrawn sentence; §5a untouched as instructed. |
| Q4 | **CLOSED** | `a1793357`, `4455f175`, `ffddbaa9` | 4.00 threads/pane in all four places it was wrong — §6.7, §8 falsification row, the §5 verdict table, the README table. |
| Q5 | **CLOSED** | `ffddbaa9` | cmux in the README table; table reordered by thread cost and given a **console** column, the axis cmux actually wins. |
| Q3 | **CLOSED** | `49304944`, `24978960` | `assets/demo/terminal-bench.{tape,webp,mp4}` + a README evidence block: the instrument running against the live fleet, the readings behind the table, and a reproduce-it-yourself command per row. |

**Q3 detail — five things a successor should not rediscover:**

1. **The subject chose itself: `terminal-bench.sh` is READ-ONLY by construction** (creates no panes,
   closes none, writes no preference). That is the only reason a recording could point at the
   operator's live fleet mid-session while the box was recovering from two panics in 48 h.
   `terminal-bakeoff.sh` **does** create panes — it was ruled out on the safety ceiling, and measuring
   the *live* fleet turned out to be better evidence than a synthetic bake-off anyway.
2. **`pgrep -x iTerm2` cannot see iTerm2 on macOS.** Its accounting name is the first 16 chars of its
   FULL PATH (`/Applications/iT`), so `-x` can never match. An ad-hoc census run while preparing the
   recording concluded *"iTerm2 is not running"* and a whole scene was scripted around it — while
   iTerm2 was **pid 591 burning 107% CPU**. `terminal-bench.sh` was never fooled (it falls back to the
   `ps` comm basename) and its source documents the trap. **Census by comm basename, never `pgrep -x`.**
3. **VHS 0.11.0 ignores `Set Framerate` for its mp4 muxer** — emits 25 fps regardless. Probed
   directly with a minimal tape at `Set Framerate 60` → `avg_frame_rate=25/1`. **Resolved by splitting
   the artifact** (`4d31f7ae`): the tape keeps the inline WebP and emits **no mp4**, and the linked
   master is a real `screencapture` at display refresh — **1920×1080, `avg_frame_rate=60/1`, 4260
   frames, 71 s**, from `assets/demo/terminal-bench-capture.sh`. Two artifacts, two routes; forced,
   not stylistic.

   **The capture route can film the operator's screen — three leaks, all caught by the contact
   sheet, none by any encoder error:** (a) `screencapture -l<window-id>` does **not** scope *video*
   to that window — the first take recorded the whole display, Dock and the operator's other windows,
   and was deleted unused; use `-R` with your own window covering the rect. (b) A macOS notification
   banner carrying **live session ids** landed in frame — banners are right-aligned, so the rect's
   right edge must clear them (1280×720 at x=0 does, and captures at 2× for a clean 2560×1440 →
   1080p downscale). (c) The window closed before the `-V` budget expired and the tail filmed the
   desktop — **scan every second, not a sample**; mean luma separates the states cleanly here
   (terminal ≈6.4k vs wallpaper ≈22.8k of 65535). Final scan: **0 bright frames**.
4. **A 45-second drift window cannot resolve a rate finer than ~80 ports/hr**, so kitty's `+0` over
   45 s is a real reading but **cannot exclude iTerm2's measured +76/hr**. Publish drift readings WITH
   their resolution or they read as far stronger than they are — this is the `bound-must-fit-the-band`
   class. The discriminating run is 1800 s (~2 ports/hr).
5. **Two verification traps hit live.** `vhs … | tail` returned **rc=0 while the render failed**
   (the pipe's exit, not vhs's) — run it unpiped and read the text. And the VHS parser rejects
   escaped quotes inside `Type "…"`, which is why the tape uses none. Verify a WebP by **summed
   duration** (76,720 ms, matching the mp4 exactly), never by frame count — `gif2webp` merges runs of
   identical frames, so the count legitimately drops.

**Three traps found while closing these — each would have cost a successor a re-derivation:**

1. **Q4's own line reference had drifted.** §4b cites `terminal-for-30-panes-2026-07-31.md:377`; line
   377 is the stranded-branch paragraph. The real sites were **:427, :429, :505**. Line numbers in a
   queue rot as soon as anyone edits above them — **cite the section + a quoted phrase**, never a bare
   line number.
2. **The backend symbol counts are method-sensitive, and three sources already disagree.** §1/D5 of
   this plan says `40 ITermBackend / 32 TmuxBackend`; `terminal-for-30-panes` §5a says `43/39`; a
   re-count on 2.1.183 measures **47/41 occurrences** or **21/24 matching lines**. Only the **zero**
   (`0 KittyBackend`, `0 GhosttyBackend` — confirmed on *both* 2.1.114 and 2.1.183) is
   method-independent. **Cite the zero; the zero is the load-bearing fact.** The positives are noise
   that reads as contradiction.
3. **Closing Q4 opened a coherence gap in the same file.** §6.7 said "Ghostty was not measured";
   closing it left §2 — the doc's primary *"one ruler for every candidate"* table — as the only place
   still written as though Ghostty and cmux did not exist. Added as a marked **addendum** rather than
   folded in, so which figures came from which run stays visible.

### 4b-STATUS addendum — §6.1's PRECONDITION GATE built 2026-07-31 23:20Z (same branch)

§6.1's own prescription — *"gate the run on a layout-stability check that ABORTS rather than emitting
a confounded row"* — is **built, RED-proven and green (18/18 in `tests/terminal-bench.bats`)**. The
§6.1 **evidence** item stays 🔴 **OPEN**: a gate supplies no multi-hour run. What it buys is that the
next attempt is either clean or *loudly void*, and that a wasted window now costs seconds instead of
the full interval — which is what makes retrying on a shared box practical.

`scripts/terminal-bench.sh` gains `--watch <secs>` (default 30) and a fourth verdict token
`LAYOUT-DRIFT` (exit 4). **Four things a successor should not re-derive:**

1. **The obvious column is the wrong one, and picking it would have been worse than no gate.** The
   `windows` column the script already reads is the **on- AND off-screen TOTAL**, and a *rising*
   offscreen count **is** the leak the instrument exists to convict — gating on it makes a leaking
   terminal abort its own measurement and become structurally unable to report the leak. The gate is
   asymmetric: **onscreen UNCHANGED · offscreen must not FALL · offscreen RISING allowed**. Onscreen
   is census field 4, which the script did not read at all before this change.
2. **The 22:17Z numbers were mislabelled, and the correction validates the gate.** "−17 onscreen" was
   the TOTAL; with offscreen −18, onscreen actually rose **+1**. The real event was *18 offscreen
   releases plus 1 new onscreen window* — each of which independently trips the rule derived in (1),
   so it is confirmed against the real failure and not only against synthetic tests. Corrected in
   place at both sites (research §6.1 and README §6).
3. **Two further verdict defects sat in the same six lines.** The header's long-documented "missing
   window census ⇒ PARTIAL" was never implemented (`OK` was set unconditionally once two readings
   existed), and the `--out` JSONL row was appended **before** the final GPU downgrade — so the
   machine-readable sink could record `"verdict":"OK"` for a run whose stdout read `PARTIAL`. The
   overclaim was living on the surface consumers parse rather than the one a human reads.
4. **Three of the six new tests first passed for the wrong reason, and that is now designed out.**
   The script's baseline probe lands ~5 s in (two `top -l 2` samples plus the GPU sample), so a
   stubbed layout change scheduled at t+2 had already been folded into the baseline before there was
   anything to detect. Every test now **asserts the printed baseline**, so a mistimed run fails
   loudly instead of certifying a layout that never moved.

**RED proof:** the pre-fix script at `f8633b2c`, against a stubbed census whose onscreen count moves
1 → 4 mid-interval, prints `DRIFT (app, constant layout …): windows +3 over 20s = +540.0/hr` — a
confounded row under a header that literally reads *constant layout*.

---

## 5. Corrections this plan supersedes

- **"`bin/it2-wrapper` intercepts Claude Code's native `it2` calls"** (the wrapper's own header, and
  the premise behind D5's "we already intercept `it2`") — **FALSE on this box.** CC resolves it2
  through a *login* shell and execs the absolute path, which is `~/.local/bin/it2`, not the wrapper.
  The 12 class-1 files still route through the wrapper because *they* are PATH-resolved; Claude Code
  itself is not. See §4.3.

- **"Maximising the GPU is the wrong goal"** — WRONG AS STATED. Derived from iTerm2's per-pane
  `CAMetalLayer` and over-generalised. Ghostty is Metal-native *and* per-pane and measures 24 panes at
  0.0% idle CPU. The true axis is cadence + window count; the API is not a term.
- **"kitty makes the tmux-ISID hazard disappear"** (`terminal-for-30-panes` §5b) contradicts §5a: with
  **0 KittyBackend**, teammates on kitty fall back to tmux — where every pane shares one
  `KITTY_WINDOW_ID` exactly as they shared one `ITERM_SESSION_ID`. Same hazard, new spelling.
- **"Ghostty 3 threads/pane"** — measured **4.00** (`renderer`, `io`, `io-reader`, `cf_release`).
- **Level 4 = 215 GB locally** — wrong frame; Level 4 is throughput, not concurrency.

---

## 6. T1/T2 build log (branch `feat/cc-pane-seam`, worktree `.worktrees/terminal-agnostic-pane`)

Append-only. Each entry is a fact established on disk, written the moment it was established so a
crash costs nothing. Started 2026-07-31 from `origin/main` @ `856ee347`.

### 6.1 Census correction — the class-2 set is 25 files, not 18, and it OVERLAPS class-3

`grep -rl ITERM_SESSION_ID bin scripts hooks` (tests excluded) = **25** files, not the 18 in §1.
More importantly the two sets are **not disjoint** — 3 of the 6 class-3 files also read the env var:

| class-3 file | `ITERM_SESSION_ID` refs | consequence |
|---|---|---|
| `scripts/handoff-fire.sh` | 18 | rename here is T3's, NOT T1's — do not touch |
| `scripts/handoff-selfclose-e2e.sh` | 2 | same |
| `scripts/limit-recover/lr-handoff.sh` | 2 | same |

⇒ **The T1 mechanical-rename set is the 25 minus the 3 class-3 files = 22 candidates**, of which the
harness/e2e scripts are further excluded. §1's "18" was a count of a differently-drawn population;
it is not wrong so much as *not the set T1 may edit*. Whoever runs T3 owns the 3 overlap files.

### 6.2 The rename is genuinely mechanical — because of the `##*:` idiom

Every consumer reads the var and immediately strips an `it2` prefix:
`ITERM_SESSION_ID="wNtNpN:<UUID>"` → `${x##*:}` → bare UUID. Verified at `bin/cc-notify:343`,
`hooks/session-register.sh:73`, `bin/cc-teardown:86-87`, `hooks/waiting-recycle.sh:212`.

⇒ the rename is exactly `${ITERM_SESSION_ID:-}` → `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}`, leaving the
`##*:` untouched. `CC_PANE_ID` is therefore defined to accept **either** the bare id or the prefixed
form — a superset — so the substitution provably cannot change behaviour for any existing caller.
That is the property that makes "keep `ITERM_SESSION_ID` as a read fallback for one release" free.

### 6.3 Naming hazard — `CC_PANE_ID_GATE` already exists and is UNRELATED

`scripts/handoff-fire.sh:1595-1620` and `tests/handoff-payload-gates.bats:152` already use
`CC_PANE_ID_GATE` — a payload-validation kill switch, nothing to do with this seam. Shell env lookup
is exact-match so there is no runtime collision, but any future *prefix* grep (`grep CC_PANE_ID`)
will conflate them. Recorded so nobody "fixes" one while reading the other.

### 6.4 Reconciling "default `iterm2`" with "headless is the DEFAULT"

The two instructions look contradictory and are not; re-deriving this is a trap, so it is settled here:

- **Architecture is headless-first.** Nothing in the contract may assume a surface exists. `address` /
  `send` / `close` are keyed on an **opaque id** and never on a window/tab/pane coordinate. Anything
  that needs a surface (focus, split direction, profile) is an **optional capability** a driver may
  not have, and a driver lacking it must be *usable*, not broken.
- **Runtime default is `iterm2`,** for one release, so today's behaviour is reproduced exactly —
  the same compat logic as the `ITERM_SESSION_ID` read fallback, and what §2/P3 already says
  ("the `iterm2` path staying default until headless is proven").

Headless-first is a statement about the *contract*; `iterm2` is a statement about the *default value*.

### 6.5 Driver resolution — why the `iterm2` driver lives INSIDE `bin/cc-pane`

`bin/cc-pane` is front-end + dispatcher and carries the `iterm2` driver as the built-in incumbent;
any other driver `X` resolves to a sibling executable `bin/cc-pane-X` (so `headless` → the new
`bin/cc-pane-headless`, and D4's future kitty/cmux drivers drop in with **zero** edits to `cc-pane`).
This keeps T1+T2 to exactly the two files the track owns instead of minting a third.

Self-resolution must follow the **final symlink**, not just the directory — `~/.claude/bin` is a tree
of per-file symlinks into this checkout, and `pwd -P` resolves the dir only (memory:
`self-identity-guard-must-fully-resolve`). A `cc-pane` that resolved its own dir naively would look
for its sibling driver in `~/.claude/bin` instead of the checkout.

### 7.6 Liveness is PID+start-time, never registry presence

The headless registry records *claims*; the OS holds *truth*. A row is live only if its pid exists
**and** that pid's start time still matches the recorded one — the standard PID-reuse guard, and the
direct defence of memory `liveness-proxy-cannot-be-output-age`. `list` verifies every row and reaps
what it disproves, so a reboot (which kills every session) cannot leave rows that read as alive.

### 7.7 Two defects the smoke test caught before any test was written

Both were in the first cut of `bin/cc-pane-headless` and both are now pinned by tests:

1. **BSD `hexdump -e` PADS to the field width.** `hexdump -n 8 -e '4/4 "%08x"'` minted
   `hdl-<16hex><16 spaces>` — an id with trailing whitespace, which becomes a *directory name*
   with trailing whitespace and compares unequal to its own echoed form. `od -An -N8 -tx1` is
   used instead, plus a shape-gate that fails loud on a malformed mint.
2. **`kill -0` SUCCEEDS on a ZOMBIE.** `spawn -- /usr/bin/false` returned **rc 0 and a fresh id**
   for a process that had already exited. Liveness now reads `ps -o stat=` and treats `Z*` (and
   empty) as dead. Same class as memory `kill-on-reaped-child-fails-fast-path-hides-it`.

### 7.8 The red-proof harness caught a WEAK TEST — the zombie guard was unproven

`tests/cc-pane-redproof.sh` mutates the **real** artifacts and requires the **named** test to go
red. First run: **11 caught · 1 SURVIVED**. The survivor was the zombie mutant — reverting the
state check to `kill -0` left the suite GREEN.

**Why**, and it is the load-bearing lesson: whether an exited child is still a zombie or has
*already been reaped* is a **RACE**. Under /Users/chrisren/.claude/bin/cc-bats the child lost that race, so the naive `kill -0`
failed "correctly" and the test passed — the guard looked proven while the actual claim was
untested. A green suite was not evidence.

Fix: stop racing for a zombie and **construct one deterministically** — a `perl` parent that forks
a child which exits and is never waited on pins it in state `Z` for as long as the parent lives.
The test carries a **positive control** (assert the fixture really is `Z*` *and* that `kill -0` is
really fooled by it) so it cannot pass merely because the pid was gone — a different, easier case
that would leave the claim unproven. Note the control asserts the `Z` **prefix**: a niced zombie
reads `ZN`, and pinning the exact flag string made the test fail on its first run for a reason
that had nothing to do with the property under test.

### 7.9 The class-2 rename is TWO classes, not one — and only class A is mechanical

Applying the rename revealed the population splits by *what is being read*:

| Class | Shape | Sites | Verdict |
|---|---|---|---|
| **A — own-env read** | the literal `${ITERM_SESSION_ID:-}` | **17 sites / 15 files** | genuinely mechanical: ONE literal substitution → `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}` |
| **B — scrapes ANOTHER process's env** | `ps eww … grep '^ITERM_SESSION_ID='`, `env_val <blob> ITERM_SESSION_ID` | **4 sites** | **NOT a rename** — see below |

Class A is done (commit below). The one substitution also handles the nested precedence chains
correctly without special-casing, because the inner literal is identical:
`${CC_TEARDOWN_SELF_UUID:-${ITERM_SESSION_ID:-}}` → `${CC_TEARDOWN_SELF_UUID:-${CC_PANE_ID:-${ITERM_SESSION_ID:-}}}`,
and the same for `CC_WR_UUID` in `waiting-recycle.sh`. Explicit test seams keep winning; `CC_PANE_ID`
slots in ahead of `ITERM_SESSION_ID` and behind everything else.

**Class B is left UNCHANGED and is named here as a distinct follow-on**, because it is a different
problem wearing the same variable name. These sites answer *"which pane is process X in?"* by
reading **X's** environment:

- `scripts/desk-arm-live.sh:103` · `scripts/desk-recycle-invariant.sh:146` — match a uuid to a pid
- `hooks/teammate-auto-shutdown.sh:247` — resolve a teammate's pane in order to close it
- `bin/cc-reconcile:169` — `env_val "$env_blob" ITERM_SESSION_ID`

Today they work because **iTerm2 itself** sets `ITERM_SESSION_ID` in the target's environment. They
keep working untouched. But a **headless** agent has `CC_PANE_ID` and no `ITERM_SESSION_ID`, so
~~every one of these scrapers silently finds nothing and *skips the session* — a false negative, not
an error.~~ Making them accept either key is correct and small, but it is fleet-wide
headless-awareness (T3 territory), not the mechanical rename T1 was scoped to, and
`teammate-auto-shutdown.sh` is high-traffic machinery with its own extensive suite. Filed rather
than smuggled in.

> ⚠ **The struck sentence is FALSIFIED, and it was wrong in the dangerous direction — see §10.**
> The premise "a headless agent has `CC_PANE_ID` and no `ITERM_SESSION_ID`" describes the intended
> contract, not what the code did. `cc-pane-headless spawn` ran `exec "$@"`, which **inherits the
> spawner's environment**, so a headless agent fired from a pane-hosted session carried the
> **spawner's** `ITERM_SESSION_ID` and no `CC_PANE_ID` at all. These scrapers therefore did not
> find nothing — they found the **spawner's pane** and returned it confidently. `teammate-auto-
> shutdown.sh` resolves a pane *in order to close it*. Fixed at the producer in §10; the consumer
> half (teach the four sites to prefer `CC_PANE_ID`) stays filed here, and is only now non-inert,
> because until §10 landed nothing in the fleet ever exported the key they would be reading.

### 6.10 Three test defects the LAND GATE caught that 658 green tests did not

T1/T2 landed only after three consecutive `exit 6` gate reds. All three were in the **tests**, none
in the subject, and none was visible from a green suite — worth recording because the pattern is
"my tests passed" concealing "my tests were not being checked":

1. **`tests/cc-pane.bats` ran against the operator's live `~/`** (`3ff736cb`). `cc-pane`'s
   `it2_bin()` defaults to `$HOME/.claude/bin/it2`, so any test that forgot `$CC_PANE_IT2` would
   have driven the **real** it2 shim — the live fleet — from a test run. The headless suite had the
   same exposure via `$HOME/.claude/autonomy/panes`, where the verbs under test *spawn and reap
   processes*, so both were fixtured, not just the one the ratchet named.
2. **A prose comment opened with the tool's name** (`82ebb42d`). shellcheck parses a comment-initial
   `shellcheck` as a **directive** and aborts the whole file ⇒ `bats-shellcheck-lint` was *silently
   blind* to that suite and its clean verdict meant nothing. The word had merely wrapped onto an
   unlucky column. `--selftest` passes on `origin/main`, so the regression was unambiguously mine.
3. **A trailing `return 0` made 15 later tests unreachable** (`93f2f605`). A `.bats` file is linted
   as plain bash, where `@test "…" { … }` is not valid function syntax — so shellcheck read the
   zombie test's closing `return` as a **top-level** return ending control flow, and flagged every
   subsequent test body SC2317.

**The two defects composed, and the order matters:** #3 was *invisible until #2 was fixed*, because
the abort meant the lint saw nothing in that file at all. A gate that only reported "clean" would
have shipped both. This is the same shape as the §6.8 red-proof result — a green signal that was
green because nothing was actually looking.

## 7. T4 — `bin/cc-queue`: measured findings + design (2026-07-31)

**Status:** ✅ **DONE — LANDED on `origin/main`** 2026-07-31, content-verified (4 paths present +
diff-empty). Deliverables: `bin/cc-queue` · `tests/cc-queue.bats` (35 assertions) ·
`tests/cc-queue-redproof.py` (15 mutations, all caught).

| landed sha | what |
|---|---|
| `c95ca590` | §7 findings — telemetry spine, three-state world, `agents --json` unavailable |
| `57e16249` | the tool |
| `cfb59850` | RED-proof harness — and the vacuous-pass surface it exposed |
| `f9f023ec` | truncation marker, attach proof, 1000-row measurement |
| `4fb28f34` · `a151a0d7` | P4 done; §6→§7 renumber after T1/T2 landed their own §6 |
| `8bbbca2a` · `9e15b9e3` · `2d4b201f` | three defects the LAND GATE caught (§7.10) |

> ⚠ **Landed ≠ on the operator's PATH.** `bin/cc-queue` is a **brand-new file**, so it needs a symlink
> minted in `~/.claude/bin/` — existing files stay fresh because their symlinks already track the
> checkout, which is exactly why only new files rot here (memory: `repair-gated-behind-advance`). That
> link is minted by `deploy-live.sh`'s link-only partition, which is **fail-closed on a GREEN postland
> stamp — and the newest stamp is RED and 41 h old**. So the tool is on trunk and correct, but not yet
> runnable as `cc-queue`. Pre-existing deploy-lag (backlog #71/#72), NOT caused by this track.
> Unblock = advance the shared checkout, then let deploy link it:
> `git -C ~/Development/claude-infrastructure pull --ff-only && ~/.claude/scripts/deploy-live.sh --auto`
> (the shared checkout also holds another session's staged work — check `git status` there first).

### 7.1 The four disk sources (NO terminal polling — all reads are files)

| Source | Path | Gives | Cross-account? |
|---|---|---|---|
| **beacon** (spine) | `/tmp/cc-permission-pending/<sid>.json` | `{ts, tool_name, tool_input, cwd}` ⇒ BLOCKED + exact cmd + since | **YES** — shared `/tmp`, config-dir agnostic |
| **telemetry** (census) | `/tmp/cc-telemetry/<sid>.json` | `{ts, session_id, cwd, config_dir, model, effort, pid, used_pct, …}` | **YES** — shared `/tmp`, and it *records* `config_dir` per row |
| **registry** (attach) | `~/.claude/cc-registry/<paneUUID>.json` | `{paneUUID, name, cwd, account, pid, session_id}` ⇒ sid→pane | **YES** — ONE dir for all 4 accounts, carries `account` |
| **transcript** (activity) | `<config_dir>/projects/<mangled-cwd>/<sid>.jsonl` | mtime = last message/tool event | resolved per-row from telemetry's `config_dir` |

### 7.2 `claude agents --json` is NOT available on this box (supersedes the T4 brief's premise)

The brief specifies it as the per-config-dir enrichment source. **Verified false here today:** the pinned
stable is **2.1.114** (`claude-latest` refuses 2.1.220 — "available but not in MANIFEST allow-list"), and
`agents --json` returns `error: unknown option '--json'`. Installed versions are **2.1.113 / 2.1.114 /
2.1.183** — none ≥ 2.1.219. So the enrichment source is **prose-only on this box** until the binary
advances (memory: `spec-named-mechanism-may-be-prose-only`).

**This is not a loss — telemetry is strictly better for the stated purpose.** The brief wanted
`claude agents --json` *per config dir* precisely to defeat the 4-account sharding that made it report 3
of 25. The telemetry row already **carries `config_dir` as a field**, and the registry already carries
`account`, so the census has **no sharding blindness to defeat**. `cc-queue` therefore takes telemetry as
the census and treats `claude agents --json` as strictly-optional enrichment that is never depended on.

### 7.3 Classification — reuse the supervisor's measured lessons, do NOT re-derive

Both classifiers are lifted from `scripts/lead-supervisor.sh` (mirrored, not imported — cc-queue is
standalone and lead-supervisor is not T4's file):

- **Activity = TRANSCRIPT mtime, never telemetry `ts`** (`lead-supervisor.sh:426-442`). The telemetry
  writer is `statusline.sh`, which stops emitting when a pane is not actively rendering — a healthy
  backgrounded/long-turn session goes telemetry-stale for hours while its transcript stays warm
  (**measured 2026-07-19: a live session 3.5 DAYS telemetry-stale with a 5-min-warm transcript**).
  Unresolvable transcript ⇒ sentinel ⇒ treated COLD (fail-safe: never exempt a stall we cannot disprove).
- **Liveness = `kill -0` AND the process command matches `claude`** (`lead-supervisor.sh:468-479`). Bare
  `kill -0` reads a **recycled pid** as the original session (the STALL? zombie: 266841ba 14h-stale,
  5277b63a 3d-stale).

### 7.4 The load-bearing correctness property — the THREE-state world

The beacon hook (`hooks/cc-permission-beacon.sh:60-98`) maintains a `.beacon-alive` heartbeat on EVERY
invocation specifically so consumers can tell these apart:

| Observation | Meaning |
|---|---|
| dir **ABSENT** | the hook has **never run** — INERT/mis-wired. "Nothing blocked" is **NOT trustworthy** |
| dir present, **no** `<sid>.json` | genuinely nothing pending — the all-clear that **can** be trusted |
| dir present, `<sid>.json` present | a real pending prompt |

A queue that renders "0 blocked" for an absent dir reproduces the exact 2026-07-29 failure (a teammate sat
blocked while the board read all-clear). `cc-queue` renders this split explicitly and **loudly**; the same
existence-evidence discipline applies to the telemetry census.

**Corollary (fail-safe):** a beacon whose sid has **no** telemetry row is still rendered as a BLOCKED row.
The exception queue must never drop an exception for lack of enrichment.

### 7.5 Deploy-lag observed in passing (NOT T4 scope, C10 — surfaced only)

The **live** `~/.claude/hooks/cc-permission-beacon.sh` **differs from `origin/main`**: the repo version has
the durable archive (`CC_PERMARCHIVE_DIR`, default `~/.claude/autonomy/permission-archive`); the live copy
still does a bare `rm -f` on clear. So the archive that task #89 landed is **committed but not deployed**.
`cc-queue` therefore does **not** depend on the archive existing.

### 7.6 The surface, as shipped

```
⛔ BLOCKED (1) — waiting on a permission answer; nothing in-session can self-approve
   1    3m12s  tertiary   claude-infrastructure  Bash: cd …/wt-terminal-arm && python3 - <<'PY' p='…
  → answer one:  cc-queue --attach <#>   (jumps to that pane)
● WORKING (13) … ○ IDLE (5) … · DONE (12)
36 agents across all config dirs · ⛔1 ●13 ○5 ·12
```

`cc-queue` · `--json` · `--check` (gate) · `--attach ROW|SID` · `--state` · `--group-by cwd|account|model|state`
· `--account` / `--cwd` filters · `--limit N` · `--watch [S]` · `--selftest`.

**It found a real blocked agent on its first live run** — a `tertiary` session in `wt-terminal-arm`,
blocked 3m12s on a Bash heredoc, that nothing else was surfacing. That is the 6.6-minute case the plan
was written around, caught by a list instead of by eyeballing panes.

### 7.7 Scale — MEASURED, not asserted

Synthetic fleet of **1000** telemetry rows (4 config dirs, 7 cwds) + 12 blocked beacons: **0.39 s wall**,
all 1000 rows rendered (2026-07-31, this box). Every syscall class is batched — ONE `ps`, ONE `stat`,
one `jq` slurp per source dir — so cost does not scale with row count. Re-measure rather than quoting
this: it is one box on one day, and the per-file fallback (malformed source only) is O(files).

Readability at 1000 is a **grouping** problem, not a rendering one: `--group-by account` collapses the
fleet to one line per group with per-state counts, blocked-bearing groups first. Blocked rows are
**never** capped; other states cap at `--limit` and always print what they withheld.

### 7.8 Learnings (the durable ones)

1. **A non-final `[[ ]]` never fails a bats test.** MEASURED on bats 1.13.0 + this bash: a non-final
   failing `[[ ]]` does **not** fail the test, while a non-final `[ ]` does. Every multi-assertion test
   written with `[[ ]]` was therefore checking **only its last line**. Found because a mutation deleting
   the cap notice left the suite fully green. Fix: assertion **helper functions** (`has`/`hasnt`) — a
   simple command, so errexit fails at the failing line. **This likely affects other suites in this
   repo** — a `grep -n '\[\[' tests/*.bats` sweep is a genuine follow-up (NOT done here: out of T4 scope).
2. **`|| fallback` attached to a pipeline double-prints under `pipefail`.** `cmd | grep | jq || printf '[]'`
   emits `[][]` when grep matches nothing (jq already printed `[]`, then the pipeline's failure fires the
   fallback) — invalid JSON that killed the whole render whenever **no claude process was running**.
   Caught by a test, not by review. Fix: capture, then decide.
3. **A one-row fixture cannot test "row N".** The attach test passed a mutation replacing `.[$n-1]` with
   `.[-1]`, because with one row those are the same row.
4. **Mutate the verdict, not a redundant guard.** Deleting the `[ -d ]` check was unobservable (the
   heartbeat check subsumes it), which reads as "the test is vacuous" when the truth is "the mutation
   is unsound".

### 7.9 Not done (named, not silently dropped)

- **`cc-queue` is not wired into any hook, statusline, or launchd job** — it is a command the operator
  runs. Wiring it (e.g. a blocked-count segment in the statusline, or `--check` in a sweep) touches
  files T4 does not own (C10) and is a separate decision.
- **The `[[ ]]` sweep across the other ~90 bats suites** (learning 1) is filed above, not performed.
- **`claude agents --json` enrichment** is designed for but not implemented — the binary that has it is
  not installed here (§7.2), so implementing it would be untestable on this box.

### 7.10 Three defects the LAND GATE caught that a green suite did not

All three were invisible to 35 passing tests + 15 caught mutations. The gate is not ceremony.

1. **The suite ran against the operator's LIVE `~/`** (`8bbbca2a`). `CC_REGISTRY_DIR` defaults to
   `$HOME/.claude/cc-registry` and `setup()` never fixtured `$HOME`, so real fleet rows could mix into
   assertions. Every seam *was* overridden explicitly; the leak was the backstop nobody set. Fix:
   `export HOME="$TD/home"` in `setup()`. Caught by `test-hermeticity-lint` in seconds, by name.
2. **`shellcheck -S warning` hid an *info*-level finding the gate blocks on** (`2d4b201f`). I verified
   locally at `warning`; the gate runs default severity, where SC2016 fires. **Match the gate's own
   invocation or a local green means nothing** — a weaker local check manufactures a false all-clear.
3. **A bare `done` inside `[ ]` parses as the loop keyword** (`9e15b9e3`, SC1010) — `[ "$x" = done ]`
   needs `'done'`. It appeared in both the tool and the suite.

**The meta-lesson matches T1/T2's independently** (§6): a green signal can be green because nothing was
looking. Here the suite was green while `[[ ]]` silently swallowed non-final assertions, the hermeticity
leak was invisible to every test, and a weaker local shellcheck invented an all-clear. Three different
instruments, one failure mode.

---

## 8. P3/P5 — dual-terminal parity (branch `feat/kitty-parity`, 2026-07-31)

**Frame correction, and it is the load-bearing one.** §2/P3 is written as *"port the 6 class-3
files"* and §4b/D2 as a migration held on HOLD. Both framings are now wrong in the same way: the
goal is **not** to move to kitty and **not** to port everything, it is that **iTerm2 and kitty both
work**. Most of the fleet was already portable and nobody had checked — the useful work turned out
to be four small seams, not six file ports.

### 8.1 The census, re-run — most of the "coupling" was already behind a seam

| Surface | Verdict | Why |
|---|---|---|
| `bin/cc-notify` · `bin/cc-teardown` · `hooks/teammate-auto-shutdown.sh` | **already portable** | all resolve `$HOME/.claude/bin/it2`, i.e. the shim, so the kitty divert carries them unchanged |
| `hooks/waiting-recycle.sh` · `hooks/lead-crash-watchdog.sh` | **already portable** | their `osascript` is `display notification` — a macOS call, not an iTerm2 one. A raw osascript count is NOT a coupling count |
| two-way comms | **already portable** | delivery is a FILE that hooks read (README §1). The only terminal call in the path is the pane-liveness oracle |
| `scripts/handoff-fire.sh` | real work | 5 functions + 4 it2py verbs, below |
| `lr-handoff.sh` · `lr-reset-poller.sh` · `boot-resume-launch.sh` · `render-census.sh` | real work | AppleScript pane-open / pane-count |

⇒ **§1's "class 3 = 6 files needing real porting" overstates it.** `handoff-selfclose-e2e.sh` is a
harness, and the genuine production surface is 5 functions in one file plus 4 launcher/census
scripts. Count *functions reached*, not files touched.

### 8.2 The four defects found, all by measurement on a live kitty (19 panes)

1. **`it2-kitty` ignored `--json`** (`8ba40a02`). It fell through the arg loop's `*)` arm into ARGS,
   which `list` ignores. `cc-pane:153` and `cc-notify` both call `session list --json` and jq
   `.[].id` ⇒ `cc-pane list` exited **2 INDETERMINATE** with a `[: -1\n-1…: integer expression
   expected` bash error, and cc-notify's liveness oracle returned **unknown**. Both degraded SAFELY
   and both were non-functional — the shape a green suite cannot see.
2. **The `REAL_IT2` bypass inverts under kitty** (`65e46727`). `handoff-fire.sh` and `cc-pane`
   resolve the raw it2 to escape the shim's `-p Claude-Teammate` injection. That injection sits
   BELOW the shim's terminal dispatch, so inside kitty the shim never adds it — the bypass buys
   nothing and resolves an iTerm2 client with no iTerm2 to talk to. **`it2_split` is the DEFAULT
   fire path** (`:3922`; it2py only saves/restores focus around it), so this one line decided
   whether handoff fired at all on kitty.
3. **The CC_PANE_ID ratchet convicted the PRODUCER** (`9d5e2a50`). `tests/cc-pane.bats`' ratchet was
   RED on trunk since kitty-setup landed, firing on the file that *creates* `ITERM_SESSION_ID` from
   `KITTY_WINDOW_ID` and on the `--check` line that asserts it took effect. A red ratchet ratchets
   nothing. Fixed with the ratchet's own per-LINE marker, never a path exemption.
4. **`tests/cc-pane.bats` depended on which terminal it ran from.** Same defect
   `tests/it2-wrapper.bats` already carries; it predates both diverts (`KITTY_WINDOW_ID` was simply
   never read) and only became observable when the branch was added. **Any suite asserting the
   iTerm2 path must PIN the terminal in `setup()`.**

### 8.3 The divert predicate is now in THREE files — and that is the standing risk

`[ -n "${KITTY_WINDOW_ID:-}" ] && [ -z "${IT2_WRAPPER_NO_KITTY:-}" ]` — origin `bin/it2-wrapper:75`,
copied into `handoff-fire.sh` and `bin/cc-pane`. The failure mode if they drift is specific and
nasty: **a handoff that splits the pane with one binary and addresses it with another.** No
single-file test can see it, so `tests/kitty-divert-real-it2.bats` pins that all three agree
textually — and that test fired on its own mutant, so it is not decorative.

### 8.4 What a successor must NOT re-derive

- **`kitty @ ls` already carries each pane's `env`.** That is strictly better than the class-B
  `ps eww` scrapers of §7.9 — the "which pane is process X in?" question has a first-class answer on
  kitty and does not need the env-scrape at all.
- **There is no `tty` field**; derive it as pane → `pid` → `ps -o tty= -p <pid>`.
- **`ITERM_SESSION_ID` is synthesized inside kitty** as `w0t0p0:$KITTY_WINDOW_ID` by a `.zshrc`
  block, so a "session uuid" in a kitty fleet IS the integer kitty window id, and every `${x##*:}`
  consumer keeps working untouched. **`CC_PANE_ID` itself is still never exported by anything** —
  consumers only work because of the `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}` fallback. Worth closing,
  but it is not what breaks anything today.
- **`session list` has two consumers with two shapes.** Claude Code calls it BARE (and prunes with
  `stdout.includes`); this repo calls it `--json`. Both must keep working — that was defect 1.
- **The login-PATH race is CLOSED** via `~/.claude/shims` prepended in `.zprofile`
  (`scripts/kitty-setup.sh --check` reports 15/15 live, including that `it2 session list` exits 0).
  Do not re-open it; `-lc` reads `.zprofile` and never `.zshrc`.

### 8.5 Status

**P3 and P5 are DONE — every surface in the frozen scope works on both terminals.** `cc-pane` seam ·
Agent-Teams panes · two-way comms · session register/teardown/crash-watchdog · handoff (split, type,
focus, tty, tab, background-tab) · limit-recovery · boot-resume · pane census. Both teammate branches
merged and independently re-verified by the lead, not accepted on report.

### 8.6 Two defects the teammates found that were NOT in their briefs

1. **`render-census.sh` was worse than inert on kitty — it was CONFIDENTLY WRONG.** The
   `is running` short-circuit landed 2026-07-31 makes it report **0 iTerm2 panes**, which is a
   truthful measurement and a useless one: the fleet is elsewhere. `capacity-alarm.sh:278` reads
   that column as the operator's only load-shed lever, so it read `0` on a box with a dozen live
   panes. A correct answer to the wrong question outranks a missing one in how long it survives.
2. **`boot-resume-launch.sh` RESURRECTS iTerm2 on a kitty box.** It runs `open -a iTerm` one line
   before its AppleScript, deliberately — there the launch IS the intent. On a kitty fleet that
   starts the app whose window objects saturated WindowServer on 2026-07-30, at boot, unattended.

### 8.7 The terminal-dependent-suite class is now at FIVE instances

`it2-wrapper.bats` · `cc-pane.bats` · `handoff-orphaned-assignee.bats` ·
`handoff-selfclose-session-pin.bats` · `handoff-selfclose.bats` — plus five more k3 pinned
pre-emptively. Every one asserts an iTerm2 path while stubbing only `osascript`, so once the subject
branches on `KITTY_WINDOW_ID` the verdict becomes a function of **which terminal the developer is
sitting in**. In each case the dependency PREDATED the branch and was simply unobservable.

**The diagnostic that settles it in one step:** re-run the suite with the terminal pinned at the ENV
level (`env -u KITTY_WINDOW_ID IT2_WRAPPER_NO_KITTY=1 …`) and change nothing else. Returning to the
exact baseline count proves the harness, not the subject — and it is proof, not inference, because
no test and no production line was touched to obtain it. **Any suite asserting a terminal-specific
path must pin the terminal in `setup()`.**

### 8.8 Four MORE defects the LAND GATE caught that ~340 passing assertions did not

This matches §6.10 and §7.10 exactly, on a third independent track. Every one was invisible to a
fully green suite, and each was named by the gate in seconds, by file and line:

1. **Two new suites read AMBIENT machine load.** Neither pinned `CC_FIRE_CAPACITY_GATE=off`, and
   both exercise handoff-fire, whose `capacity_gate()` refuses a net-new fire above 2.0/core — a box
   this one lives well above. Their verdict was a function of what else the operator was running.
2. **A DEAD assertion in `tests/it2-kitty.bats`.** `grep -q -- '--json' … && false` could not fail:
   as a non-final `A && B` the failure is absorbed and errexit never sees it. Repaired to
   `! A || false` **by hand**, because the prescribed fixer's uniform `|| false` is wrong for this
   class — on `A && false` it fails on BOTH branches (backlog #100). Proven in both directions
   after: green when the flag is consumed, `not ok 5` against a mutant that lets it leak.
3. **A ShellCheck directive covered only half its line.** A directive applies to the **next
   command**, so on `A=1; B=2` it suppresses A and leaves B flagged. Split onto separate lines.
4. **And fixing (3) walked straight into this repo's own documented trap.** The explanatory comment
   began with the lowercase tool name, which parses as a MALFORMED DIRECTIVE and **aborts analysis
   of the entire file** — the §6.10 defect #2 class, re-committed by someone who had read §6.10.
   The parser is case-sensitive; `ShellCheck` is safe.

**The compounding lesson, now three-for-three:** a green suite is evidence about the axes something
is looking at, and nothing else. Across T1/T2, T4 and this track the gate has caught 10 defects that
zero passing tests could see — hermeticity leaks, ambient-load dependence, dead assertions, and
lints that were structurally blind. **Run the gate's own invocation, never a weaker local one.**

---

## 9. P6 — background-agent spawn is BROKEN on live kitty (opened 2026-08-03)

**Scope (frozen).** Two independent defects, both observed on a live kitty session, both of which
silently DESTROY background agents at spawn time. Resolve each so a fan-out of N agents starts N
agents with zero operator keystrokes and zero collision with operator typing.

> **Status change this opens against §0-D2.** D2 said "do not migrate terminals now" and §8.2's
> HOLD still reads that way — but **the operator is now running kitty as the daily driver**
> (`TERM=xterm-kitty`, kitty pid 613 owning every pane, `/Applications/kitty.app`). The migration
> happened regardless of the recommendation. The iTerm2-shaped assumptions in the spawn path are
> therefore live production defects, not speculative driver work. **This does not reopen D2** — it
> reclassifies the kitty driver from "speculative" (D4) to "load-bearing".

### 9.1 Defect A — the spawner TYPES into a live interactive shell, and collides with the operator

Seven `deep-research` agents were fanned out at 10:46–10:49. **Two never started.** Both failures are
character-level corruption of the injected command line, captured verbatim from the panes:

| tty | What landed on the prompt | Result | Agent lost |
|---|---|---|---|
| `ttys020` | `ccd /Users/chrisren/Development/personal && env CLAUDECODE=1 … --agent-name austin-inventory …` | `zsh: command not found: ccd` | `austin-inventory` |
| `ttys024` | `^U tcd /Users/chrisren/Development/personal && env … --agent-name complaints …` | `zsh: correct 'tcd' to 'cd' [nyae]?` — hung on the spellcheck modal | `complaints` |

**Read the corruption precisely — it is diagnostic, not random.** In both cases exactly ONE character
precedes the intended `cd`: `c`+`cd` → `ccd`, `t`+`cd` → `tcd`. That is the signature of injected text
**concatenating with a character already sitting on the prompt line** — i.e. the operator's own
in-flight keystroke. The operator was typing when the fan-out fired.

Two further facts constrain the fix:

1. **`^U` is visible as literal text in `ttys024`.** The injector evidently does try to clear the line
   first, but the kill-line either rendered literally or arrived out of order relative to the payload —
   the surviving `t` proves it did not take effect. **A line-clear prefix is already attempted and is
   not sufficient.** Do not "fix" this by adding another `^U`.
2. **The failure mode is SILENT to the parent.** The `Agent` tool returned `Spawned successfully` for
   all seven. Liveness had to be recovered by hand:
   `ps aux | grep '[c]laude.exe' | grep 'parent-session-id <sid>' | grep -oE '\-\-agent-name [a-z0-9-]+'`
   returned **5**, not 7. **There is no post-spawn liveness assertion anywhere in the path** — the
   operator discovers a lost agent only by noticing a missing result, or never.

**The structural objection to the whole mechanism.** Typing a command into an interactive shell shares
one mutable resource — the prompt line — with the human. It cannot be made race-free by better
escaping or better timing; correctness requires that the operator not be typing, which is unknowable
and unenforceable. §8's `it2` facade already establishes the seam. **The fix direction is to stop
typing at a prompt at all** (exec the command in a new pane / pass it as the pane's argv), not to
harden the keystroke path. Treat any proposed fix that still types at a live prompt as not-a-fix.

⚠ **Detection trap, measured — do not key terminal detection on `ITERM_SESSION_ID`.** On this kitty:

```
TERM=xterm-kitty   KITTY_WINDOW_ID=312   KITTY_LISTEN_ON=unix:/tmp/kitty-613
TERM_PROGRAM=(empty)   ITERM_SESSION_ID=w0t0p0:312     ← kitty sets an iTerm2-COMPAT value
```

`ITERM_SESSION_ID` is **present and well-formed under kitty**, and its final field is literally
`KITTY_WINDOW_ID`. Any `[[ -n "$ITERM_SESSION_ID" ]]` test misidentifies kitty as iTerm2 and will
route to the iTerm2 driver. §8.3 already flags that the divert predicate lives in THREE files —
**audit all three against this specific value**, and note that `TERM_PROGRAM` is EMPTY here, so a
predicate falling back to it fails open rather than closed.

### 9.2 Defect B — every fresh agent session blocks on the `.mcp.json` trust modal

Each spawned session in `/Users/chrisren/Development/personal` renders **"New MCP server found in
this project: ms365 · 1. Use this MCP server / 2. …all future… / 3. Continue without"** and BLOCKS
there. An agent sitting on this modal is an alive `claude.exe` doing no work, so **process liveness
is not progress** — `ps` alone cannot distinguish a working agent from a stalled one, which is why
9.1's liveness check must not be the only assertion.

Disk state, read live (the cause):

```
/Users/chrisren/Development/personal/.mcp.json   → declares server "ms365" (npx @softeria/ms-365-mcp-server)
~/.claude-tertiary/.claude.json  projects["/Users/chrisren/Development/personal"]:
    enabledMcpjsonServers  = []          ← never persisted
    disabledMcpjsonServers = []
    hasTrustDialogAccepted = false
    mcpServers             = {}
```

The parent session's own approval was answered as option **1 (this server, this session)**, which is
session-scoped and writes nothing — so the approval never persists and **every** child re-prompts.
`--permission-mode auto` does not cover it: this is a project-trust dialog, not a tool permission.

**Attempted fix, BLOCKED — needs the operator.** Writing
`/Users/chrisren/Development/personal/.claude/settings.json` (file does not exist) with
`{"enabledMcpjsonServers": ["ms365"]}` was refused by the auto-mode permission classifier, correctly:
it is a permission-surface change. Deliberately NOT routed around via Bash. The successor should
land the durable fix and let the operator apply the one-time unblock.

**Prefer `settings.json` over editing `.claude.json`.** `~/.claude-tertiary/.claude.json` is rewritten
live by every running session; with 7+ sessions up, a hand-edit is a clobber race. `enabledMcpjsonServers`
is valid in `settings.json`, which nothing else writes.

### 9.3 What a successor must NOT re-derive

- Which two agents died and why — §9.1's table is verbatim from the panes; the cause is prompt-line
  collision, confirmed by the single-character prefix on both.
- That a line-clear (`^U`) is already attempted and already insufficient (§9.1 fact 1).
- That `ITERM_SESSION_ID` is set under kitty and is NOT a valid iTerm2 discriminator (§9.1 trap).
- That `hasTrustDialogAccepted=false` + `enabledMcpjsonServers=[]` is the Defect-B cause, and that
  option-1 approval is session-scoped and persists nothing.
- That the classifier blocks the settings write — that is an operator step, not a puzzle to solve.

### 9.4 Open — for the successor to determine

1. **Where the spawn path actually is.** Is the keystroke injection Claude Code's own internal
   background-agent spawner, or this repo's `bin/it2-wrapper` / `handoff-fire.sh` intercepting it?
   The corrupted line is a `cd … && env CLAUDECODE=1 CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
   CLAUDE_CONFIG_DIR=… claude.exe --agent-id … --agent-type deep-research --permission-mode auto`,
   which is CC's own agent argv — **establish ownership before proposing a fix**, because the
   remedy differs completely (upstream-report vs local interception).
2. Whether the `it2` facade can present a pane whose argv IS the command (no prompt, no typing).
3. A post-spawn liveness+progress assertion: spawned N ⇒ N alive AND none parked on a modal.
4. Whether `CC_FIRE_*` capacity gating interacts with a 7-way fan-out.

### 9.5 RESOLVED 2026-08-03 (branch `docs/p6-kitty-agent-spawn`) — §9.4 items 1-3 closed

**Ownership (§9.4 item 1) — settled by reading the 2.1.220 binary, not by inference. The typing is
Claude Code's, and CC's OWN tmux backend already does it correctly.** The two backends, side by side:

```js
ITermBackend.sendCommandToPane(id, cmd)          TmuxBackend.sendCommandToPane(id, cmd)
  await it2 ["session","send","-s",id,"\x15"]      await tmux ["set-option","-p","-t",id,
  const o = await it2 ["session","run","-s",id,           "remain-on-exit","failed"]
                       cmd]                        await tmux ["respawn-pane","-k","-t",id,
  if (o.code !== 0) throw …                                "--", cmd]      ← argv IS the command
```

⇒ **This repo intercepts nothing.** `bin/it2-kitty` faithfully implements the contract its own header
already documented at lines 46-47; the *decision* to type belongs to `ITermBackend`. So the remedy is
neither "fix our interception" nor "wait for upstream" — the defect is confined to one of two
upstream backends, and the other one already contains the fix, which is exactly the shape kitty was
given. **`sendCommandToPane` is also where the silence comes from**: it checks `o.code`, i.e. that the
KEYSTROKES were accepted. Nothing in the path ever asks whether a process exists.

**§9.4 item 2 — yes, with a one-hop deferral, because CC splits BEFORE it has the command.**
`da3e7173`. A split pane now launches `bin/cc-pane-runner` instead of an interactive shell and is
marked ARMED; `run` writes the command to a file the runner is already blocked on; `send`'s `^U` is a
no-op because an armed pane has no line to clear. No prompt line is involved at any point, so the
operator's keystrokes cannot become argv. The runner consumes its own marker, so the pane returns to
the legacy typing transport for every LATER send/run — which is what keeps the change safe.

- **`-l -i` on the launch argv is load-bearing, not decoration.** `.zprofile` puts `~/.claude/shims`
  on PATH (§8.4's login-PATH race) and `.zshrc` synthesizes
  `ITERM_SESSION_ID="w0t0p0:$KITTY_WINDOW_ID"` — the pane identity every hook, cc-notify address and
  comms registration is keyed on. Measured on pane 331: the NEW pane's own id, shims present. A
  runner exec'd from a non-login non-interactive shell would have produced agents that are alive and
  **unaddressable**, which is worse than dead.
- **A FIFO would have been the wrong primitive** and the reason generalises: it makes the ORDER of
  `open()` load-bearing between two processes with no synchronisation, and a FIFO opened for write
  with no reader blocks — i.e. it would hang CC's spawn call whenever `run` won the race. An
  atomically-written regular file has no ordering requirement at all.

**A THIRD defect, found while fixing the first — and a CONCURRENT SESSION found and landed it first.**
`kitty @ launch` focuses the new window by default and `it2-kitty split` never said otherwise, so
every split moved the operator's keyboard into a pane they did not ask for — *that is the mechanism*
by which an in-flight keystroke reached an agent's prompt line at all. Session `7868b45e` reached the
identical conclusion independently and landed `0999c8bb` (`--keep-focus`, with an A/B measurement:
focus HELD while the pane count moved 9→10) while this work was in flight. **This branch adopted the
landed flag and deleted its own duplicate** — the arming path carries `--keep-focus` too, because a
transport-specific fix would have left the legacy (opted-out) path unprotected.

⚠ **The two fixes are complements, and reading either as sufficient is the trap.** `0999c8bb`'s own
comment states the residue exactly: *"`launch` starts a bare interactive zsh with no program, so
between the line-clear and the command there is a ~50-150ms window"*. Un-focusing removes the
operator's keystrokes as a **source**; it does not remove the **window**, which is a property of
typing a command at a prompt at all. Anything else reaching that pty — a stray `session send`, a
paste, a `focus_follows_mouse` flip, a caller that legitimately focuses the pane — still lands in the
same line buffer. Arming removes the buffer. §9.1's standing instruction ("treat any proposed fix
that still types at a live prompt as not-a-fix") is what says which of the two closes the defect.

**§9.4 item 3 — the LIVENESS half landed here; the PROGRESS half is deliberately NOT a second tool.**

The inline assertion is in `it2-kitty run` and is what §9.1 fact 2 was missing: the runner deleting
the command file is the ack, so a non-zero exit means the command provably never started, and Claude
Code turns that into a real `Failed to send command to iTerm2 pane <id>` throw instead of a silent
"Spawned successfully". It sits on CC's blocking spawn path, so it is liveness-only by design —
measured 0.18s end-to-end in the healthy case, and both negative controls (never consumed / pane
vanished) fail loud with named diagnostics.

**The aggregate half was BUILT, TESTED, and then NOT LANDED — because session `7868b45e` landed
`bin/cc-spawn-verify` (`17842e77`) for the same question while it was in flight.** Shipping a rival
would recreate `sibling-auditors-must-share-the-state-model` on purpose: two checks over one
population, with different oracles and different exit vocabularies. Theirs is the better instrument
for the half they cover, and their reasoning indicts mine specifically — they key on the **process
table** (the harness stamps `--agent-name` into the child's argv, so a match is proof) and explicitly
reject `foreground_processes`, which is what mine enumerated, as *"the foreground process GROUP,
sampled"* — measured showing `caffeinate`, `tee`, and MCP servers alongside the binary. It
over-reports rather than under-reports (29/29 live panes did contain `claude`), so mine was not
wrong; it was keyed on a weaker oracle for no gain.

**What their tool does NOT cover, and what therefore remains open.** `cc-spawn-verify` resolves
0 RUNNING / 1 ABSENT / 2 PARKED, where PARKED means *no process AND a pane showing a dead launch* —
i.e. **never started**. §9.2's failure is the opposite shape: the process EXISTS and is inert on a
modal. That is a FOURTH state in a three-state vocabulary their header says is shared verbatim with
`handoff-fire.sh:verify_engagement` — so adding it is a change to someone else's just-landed contract
with a second consumer, not a local edit (`new-enum-member-falls-into-fail-closed-default` is exactly
what a careless fourth member does). **Filed as a follow-on for that file's owner rather than forced
through here.** With §9.2 closed, it has no live trigger today.

### 9.6 The fourth state — CLOSED 2026-08-09 (backlog `75c2e3e2bde7`)

Shipped as **exit 4 `WEDGED`** in `cc-spawn-verify` and **return 4** in
`handoff-fire.sh:verify_engagement`, with the dialog enumeration in ONE shared file,
`hooks/lib/pane-modal.sh`, so the rotting half has a single edit site. §9.5's framing held up on
every point; four things it could not have known:

- **It is a FIFTH member, not a fourth, and the fold had to be rewritten because of it.** `3 OFFBOX`
  landed between the filing and the fix (CLOUD_OBSERVABILITY.md §5.2). `--all` folded with
  `max(rc)`, which silently encoded "highest exit code = worst outcome" — true by luck up to 3,
  false at 4, because `OFFBOX` is the set's only NON-VERDICT and must outrank every verdict no
  matter what integer it wears. The rank is now an explicit table and a test asserts the property
  the integer used to imply. This is the *real* shape of
  `new-enum-member-falls-into-fail-closed-default`: the default arm was `max()`.
- **The §9.5 prescription — "header AND an option" — is necessary and was NOT sufficient.** Measured
  while writing the tests: two ordinary lines of THIS PLAN's prose, one naming the header and one
  quoting an option mid-sentence, satisfy the conjunction *between them*, and a fleet whose agents
  read this document produces that screen routinely. The fix is the other half of §9.5's own
  sentence, translated instead of copied: the shell states anchor to column 0, so the TUI states
  anchor to **column 0 modulo box chrome and menu index** (`^[^[:alnum:]]*([0-9]+\.)?[[:space:]]*`).
  Prose begins with a letter; a rendered dialog line does not. The index is optional deliberately —
  `hideIndexes` exists in the binary's own dialog vocabulary, and a rule that could go inert on a
  rendering flag fails in the expensive direction.
- **cfdd9fc3's folder-trust matcher was ALREADY INERT and nothing could have said so.** It keyed on
  `Do you trust the files in this folder`, which does not exist in claude.exe 2.1.220 (both
  spellings checked). The live wording is `Accessing workspace:` / `Quick safety check:` with
  options `Yes, I trust this folder` / `No, continue without these permissions`. So the enumeration
  is now pinned by a test that greps every fragment **out of the lib** and into the shipping binary
  — with the stale string as its positive control, proving the anchor can fail. Measured across the
  six co-installed tracks: the fragments are 8/8 in 183/219/220 and 7/8 in 156/161/170, so the test
  resolves the NEWEST track (a plain `$HOME/.claude-*` glob is lexical and picked 156 — a binary
  nothing launches — and convicted a healthy enumeration on its first run).
- **The verdict buys a SAFETY property, not just a label.** Before it, a wedged fire fell through
  the whole engagement window into the INC-4 recovery, which pastes the brief and sends CR at a
  pane that is a single-key prompt — so the paste's own bytes become ANSWERS to whichever dialog is
  up, and the two reachable here are workspace-trust and MCP-approval, i.e. exactly the two
  `docs/research/cc-startup-modals-2026-08-04.md` §1 classifies as boundaries that must reach a
  human. `verify_engagement` now abstains on 4, on both the in-loop and pre-resend paths.

**Deliberately NOT built: the composer anchor as a general predicate.** The `? for shortcuts`
positive anchor (`cc-startup-modals-2026-08-04.md` §3, measured 9/9) is class-level and is the right
oracle for a one-shot startup watchdog in `bin/cc-pane-runner`, where "should have reached a composer
by now" is sound. It is wrong for an any-time verdict in both directions: as a positive test a busy
agent is not at a composer either, so it would report WEDGED for every working agent; as a negative
veto over the enumeration, a modal opening mid-session leaves the earlier composer line in scrollback,
so it would suppress a genuine wedge — trading a glance for an agent.

**Verification.** 17 tests in `tests/pane-modal.bats` (new), 9 added to `tests/cc-spawn-verify.bats`,
11 added to `tests/handoff-fire-pane-parked.bats`; 68 assertions green. Eleven mutants, each
convicting the tests that exist for it and no others: conjunction weakened to header-only and to
option-only, anchor removed, a fragment gone stale, the wedge check removed, the fold reverted to
`max(rc)`, 4 folded into 2, the pane join degraded to a substring, the fail-closed screen read
inverted, and the abstain deleted on each of its two paths. **One mutant initially SURVIVED** — the
pre-resend abstain, because at any non-zero timeout the in-loop check returns first and that line is
never evaluated; it is now pinned by a `FIRE_ENGAGE_TIMEOUT=0` arm. An invariant no test can reach is
an invariant nobody is holding.

**Two defects the LIVE FLEET caught in the unlanded tool that its fixtures could not.** Both are
recorded because the LESSONS outlive the code, and both were found by running it against 27 real
panes rather than a fixture:

1. **It reported the LEAD's own pane as an agent.** It joined each process's argv into a string and
   tested `"--agent-id" in cl`. The lead's argv carries its whole prompt, and that prompt quoted
   `--agent-id` *while describing this very defect*. A flag NAMED in prose is indistinguishable from
   a flag PASSED once you have flattened the list that told them apart (memory:
   `pgrep-f-matches-agent-briefs`, re-committed by someone who had read it).
2. **It reported a healthy agent as BLOCKED.** Pane 329 was grepping this repo and had `[nyae]` —
   quoted inside `handoff-fire.sh`'s own comment — on screen. **A pane can DISPLAY a modal's text
   without BEING at one**, and in a fleet whose agents read the plan documenting these modals that is
   not a rare case. Any future progress-oracle must anchor shell states to column 0, require the TUI
   modal's header AND an option, and stay a REPORTER — a false BLOCKED costs a glance, a false OK
   costs an agent.

Both are why the fourth state is worth doing carefully rather than quickly.

**§9.1's `ITERM_SESSION_ID` trap — audited, and there was nothing to fix.** All FOUR divert spellings
(`it2-wrapper:90`, `cc-pane:111`, `handoff-fire.sh:464` **and** `:3652` — §8.3 says three FILES, but
handoff-fire carries two) key on `KITTY_WINDOW_ID` + `IT2_WRAPPER_NO_KITTY`. **`TERM_PROGRAM` is
never read in code anywhere in the repo**, so the "fails open" concern has no site. Every
`ITERM_SESSION_ID` read in the fleet is PANE IDENTITY, which is correct under kitty precisely because
`.zshrc` synthesizes it. A clean audit is still worth a test, so the measured values are now a
regression anchor in `tests/kitty-divert-real-it2.bats` — with its own iTerm2-shaped control, because
a predicate keyed on the session id would return the SAME answer to both and one of them would be
wrong.

**§9.2 (Defect B) — CLOSED, and it closed itself mid-session.** At 11:05 on 2026-08-03
`/Users/chrisren/Development/personal/.claude/settings.json` appeared containing exactly
`{"enabledMcpjsonServers": ["ms365"]}` — the durable fix §9.2 specified, applied while this work was
in flight. **Verified rather than assumed** (memory: `parked-blocker-obsoleted-by-later-fix`): a fresh
`claude` launched into that project under `CLAUDE_CONFIG_DIR=~/.claude-tertiary` — the exact config
whose `enabledMcpjsonServers` was `[]` — now starts straight to its prompt with no MCP modal. That run
went through the new argv path, so it doubles as the end-to-end proof of the §9.1 fix with a real
agent binary in the real project. **No operator step remains for §9.2.**

**§9.4 item 4 — NOT investigated, and named rather than silently dropped.** `CC_FIRE_*` capacity
gating lives in `handoff-fire.sh`, which is not on Claude Code's Agent-Teams spawn path at all
(CC calls `it2` directly), so it cannot have gated the 7-way fan-out. That is an argument, not a
measurement, and the item stays open on that basis.

**Verification.** 13 tests in `tests/it2-kitty-argv-spawn.bats`, 2 added to
`tests/kitty-divert-real-it2.bats`; the sibling's `tests/it2-kitty.bats` additions pass unchanged
against the merged file, and 105 neighbouring kitty assertions are unaffected. Every
central claim red-proofed against a mutant that makes it false (drop `--dont-take-focus`; always-pass
liveness; never arm; substring matching; header-only modal) — each convicted the intended test and
only it. Live on real panes: armed spawn 0.18s with focus unmoved, and both negative controls (never
consumed / pane vanished) failing loud with named diagnostics.

**One defect the red-proof caught in the HARNESS.** The "liveness assertion passes" test used an
unbounded background consumer, so the mutant that broke arming *hung* the suite instead of failing it
— two minutes of a red-proof run spent proving nothing. A harness whose failure mode is a hang cannot
report the thing it exists to report. Bounded, then the mutant convicted three tests cleanly.

---

## 10. P2 residue — the headless agent had NO identity, and inherited the SPAWNER's (2026-08-10)

**Scope (frozen).** Close §8.4's *"`CC_PANE_ID` itself is still never exported by anything"* and the
half of §2/P2's "not yet true" list that reads *"the class-B env-scrapers of §6.9 still cannot see a
headless agent"*. Producer side only; the consumer half stays filed (below).

### 10.1 The finding — the plan's own risk statement was wrong in the DANGEROUS direction

§7.9 predicted that class-B scrapers would meet a headless agent and *"silently find nothing and skip
the session — a false negative, not an error."* **Measured, and it is not what happens.**
`bin/cc-pane-headless:119` spawned the agent as `( cd "$cwd" && exec "$@" )`, and `exec` **inherits
the spawner's environment**. So:

| What the plan assumed the agent's env holds | What it actually held |
|---|---|
| `CC_PANE_ID` = its own id · no `ITERM_SESSION_ID` | **no `CC_PANE_ID` at all** · `ITERM_SESSION_ID` = **the spawner's pane** |

Measured directly, by having the child report its own environment:

```
$ ITERM_SESSION_ID=w0t0p0:SPAWNER-PANE-77 cc-pane-headless spawn -- node …
  headless agent's own minted id : hdl-b078a2ee174a6ff8
  ITERM_SESSION_ID in its env    : w0t0p0:SPAWNER-PANE-77      ← the SPAWNER's pane
  CC_PANE_ID in its env          : <absent>
```

⇒ the four class-B scrapers (`desk-arm-live.sh:103`, `desk-recycle-invariant.sh:146`,
`teammate-auto-shutdown.sh:356`, `cc-reconcile:169`) did not fail to answer *"which pane is this
agent in?"* — **they answered the spawner's pane, confidently.** `teammate-auto-shutdown.sh` resolves
a pane *in order to close it*, so the failure mode is closing the wrong pane, not skipping a session.
A false negative costs a missed reap; this cost the spawner's pane. **Fixing the scrapers first —
the order §7.9 implies — would also have shipped INERT**, because nothing in the fleet exported the
key they would have been taught to read.

### 10.2 The fix — both halves are load-bearing, and they fail differently

`bin/cc-pane-headless:119` now spawns as
`( cd "$cwd" && export CC_PANE_ID="$id" && unset ITERM_SESSION_ID && exec "$@" )` — both assignments
inside the existing subshell, so they scope to the spawned agent and not to the rest of `v_spawn`.
*(The **calling** process is protected by the process boundary, not by these parentheses — `spawn`
is a subprocess of whoever invoked it. That distinction is why §10.4 retired a test which claimed
the subshell was what kept the caller clean.)*

- **`export CC_PANE_ID="$id"`** — the seam's own key had **21 readers and zero writers** across
  `bin/ scripts/ hooks/`. It now exists in a real process's environment for the first time.
- **`unset ITERM_SESSION_ID`** — converts a confidently wrong pane into an honest absence. This is
  the safety half: it restores exactly the false-negative §7.9 *described*, which is the fail-closed
  behaviour, while `CC_PANE_ID` supplies the correct answer under the correct key.

**Functional payoff, and the reason this is P2's blocker and not cosmetics:** an agent can now reach
its own registry row from inside itself (`"$CC_PANE_HOME/$CC_PANE_ID/inbox"`, asserted live). Before
this, `send`'s durable delivery had **no reachable consumer on the agent's side** — the agent could
not name its own inbox. Anything that *drains* a headless inbox (§2/P2's other "not yet true" item)
was unbuildable until this landed.

### 10.3 The instrument lesson — `ps` env visibility is a function of CODE SIGNATURE

This nearly convicted four healthy production files. A positive control was built on `/bin/sleep`,
`ps eww -p <pid>` returned **zero** env tokens for it, and the reading generalised to *"`ps eww -p`
is universally blind on macOS 15, so every class-B scraper is already broken."* **That conclusion was
false**, and the real production line recovers `ITERM_SESSION_ID=w0t0p0:70` from live Claude panes
with 55 env tokens visible.

Measured on macOS 15.6.1, same launcher, same env, one variable changed:

| Subject | `codesign -dv` | env tokens via `ps eww -p` |
|---|---|---|
| `/bin/sleep` | `Identifier=com.apple.sleep` | **0 — hidden** |
| `cp` of `/bin/sleep` | signature is embedded, so still Apple | **0 — hidden** |
| `node` (user-installed) | `Identifier=node`, `flags=0x10000(runtime)` | **77 — visible** |

⇒ **macOS hides a process's environment from `ps` for Apple platform binaries and exposes it for
user-installed ones.** A control built from `/bin/sleep`, `/bin/echo` or `/usr/bin/true` is
*structurally incapable* of showing an env var, so it reports "blind" whatever the truth is — the
`control-must-replay-the-real-artifact` class, where the control cannot fail the same way the subject
does. Real agents are `node`, so production was never in the hidden population.

**Consequence for the tests in §10.4, and it is not a stylistic choice:** they assert via the child's
**own self-report** into `out.log`, never via `ps`. The suite spawns `/bin/sh` — an Apple binary — so
a `ps`-based oracle would read "ITERM_SESSION_ID absent" for a child that *has* it, and would go
**green against a reverted fix**. Two further contamination traps hit while measuring, both the
`pgrep-f-matches-agent-briefs` shape: `env VAR=val cmd` puts the marker in **argv**, and the Bash
tool's own `zsh -c '<script>'` carries the whole script text in *its* argv, so an unfiltered
`grep -c` counted the probe's own source as evidence.

### 10.4 Verification

`tests/cc-pane-headless.bats` **23/23 green**, 4 new: the export · the non-leak · a positive control
proving the oracle can see an inherited variable at all · inbox reachability. `tests/cc-pane-redproof.sh`
**15/15 caught · 0 weak**, with 3 added — export deleted · `unset` deleted · exported-but-wrong-value.
The third pins that the test compares against the **returned id** rather than merely asserting
non-emptiness, because non-emptiness is not provenance.

**A fifth test was written, passed, and was REMOVED for passing for the wrong reason** — worth
recording because the suite would have shipped one more green line than it earned. The claim was
*"the identity is set inside the subshell, so the SPAWNER's own environment is never mutated."* A
mutant hoisting `export CC_PANE_ID="$id"` **out** of the subshell left the suite **fully green**:
`spawn` runs as a SUBPROCESS of the suite, and no child can mutate its parent's environment under
any implementation, so the assertion was guaranteed by the process boundary rather than by the
subshell it named. The mutation is sound; the property is simply not observable from outside the
process. Both the test and its mutant are now comments explaining that, so it is not re-derived.

**One latent flake was fixed before it could fire, and it is this repo's recurring class.** The
retired test's first cut asserted `CC_PANE_ID = <unset>` against **whatever the developer's shell
happened to carry** — a verdict that is a function of *where* the suite runs (§8.8 defect 1). It
would have gone red for a real reason that had nothing to do with the subject: run the suite from
inside a headless agent, and `CC_PANE_ID` is now exported *by this very change*.

### 10.5 Still open — named, not dropped

1. **The consumer half — FILED as backlog `0f796daa0c76`.** The four class-B sites should prefer
   `CC_PANE_ID` and fall back to `ITERM_SESSION_ID`. It is small and now **non-inert** (the key
   exists), but it lands in T3 territory and `teammate-auto-shutdown.sh` closes panes, so it is not
   smuggled in here: Follow-On Gate **F2 fails** (the consumer side was not verified this session)
   and **F3 is questionable** (pane-closing is an escalation surface). Post-fix the sites are
   fail-closed — they see absence, not a wrong pane — which is why this is an improvement to make
   deliberately rather than an outage to patch.
2. **Kitty re-synthesis residue.** `unset` removes the variable from the agent's own environment, but
   `KITTY_WINDOW_ID` is still inherited, and §8.4 records that a login `zsh` re-synthesizes
   `ITERM_SESSION_ID="w0t0p0:$KITTY_WINDOW_ID"` from it. A headless agent that starts a **login
   shell** can therefore re-acquire the spawner's kitty window id. `KITTY_WINDOW_ID` was left alone
   deliberately: it is the **terminal-dispatch** variable that all four divert predicates key on
   (§8.3), so clearing it would change which backend the agent's own `cc-pane` calls resolve to — a
   much wider blast radius than the identity fix. Class-A consumers are already immune (`CC_PANE_ID`
   wins the `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}` precedence); only class-B scrapers would see the
   re-synthesized value, and item 1 is their durable defence.
