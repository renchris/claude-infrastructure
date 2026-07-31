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

### P4 — the queue (T4)
`cc-permission-beacon.sh` already fires on `PermissionRequest` → `/tmp/cc-permission-pending/<sid>.json`.
It has no face. 100 rows fits one screen; 1000 needs grouping (a list problem, not a rendering one).

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
tail -1 docs/research/data/kitty-drift-run2.log          # verdict=OK | ABORTED-* | PARTIAL
# fit first-vs-last on ports (col 6) / threads (col 5) / mem (col 4); ≥0.9 of 6h must have elapsed
```
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

### 6.6 Liveness is PID+start-time, never registry presence

The headless registry records *claims*; the OS holds *truth*. A row is live only if its pid exists
**and** that pid's start time still matches the recorded one — the standard PID-reuse guard, and the
direct defence of memory `liveness-proxy-cannot-be-output-age`. `list` verifies every row and reaps
what it disproves, so a reboot (which kills every session) cannot leave rows that read as alive.

### 6.7 Two defects the smoke test caught before any test was written

Both were in the first cut of `bin/cc-pane-headless` and both are now pinned by tests:

1. **BSD `hexdump -e` PADS to the field width.** `hexdump -n 8 -e '4/4 "%08x"'` minted
   `hdl-<16hex><16 spaces>` — an id with trailing whitespace, which becomes a *directory name*
   with trailing whitespace and compares unequal to its own echoed form. `od -An -N8 -tx1` is
   used instead, plus a shape-gate that fails loud on a malformed mint.
2. **`kill -0` SUCCEEDS on a ZOMBIE.** `spawn -- /usr/bin/false` returned **rc 0 and a fresh id**
   for a process that had already exited. Liveness now reads `ps -o stat=` and treats `Z*` (and
   empty) as dead. Same class as memory `kill-on-reaped-child-fails-fast-path-hides-it`.

### 6.8 The red-proof harness caught a WEAK TEST — the zombie guard was unproven

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

### 6.9 The class-2 rename is TWO classes, not one — and only class A is mechanical

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
every one of these scrapers silently finds nothing and *skips the session* — a false negative, not
an error. Making them accept either key is correct and small, but it is fleet-wide
headless-awareness (T3 territory), not the mechanical rename T1 was scoped to, and
`teammate-auto-shutdown.sh` is high-traffic machinery with its own extensive suite. Filed rather
than smuggled in.

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
