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

### P1 — the seam (T1)
`CC_PANE_ID` replaces `ITERM_SESSION_ID` at the 18 class-2 sites (mechanical; keep `ITERM_SESSION_ID`
as a read fallback for one release). Interface verbs, driver-selected by `CC_PANE_DRIVER`
(`iterm2` default). The 12 class-1 files are **not touched** — they keep calling `it2`.

### P2 — headless driver (T2) — *the one that scales*
`spawn` mints an id, starts the session with no surface, registers it. `address`/`send` work by id.
`close` reaps. Design rule: **headless is the DEFAULT and a pane is the exception** — build it that
way or it gets rebuilt.

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
2. **cmux socket auth from outside** — `socketControlMode: "passwordOrCmux"` is NOT a valid enum; the
   correct value is unknown, and without it external automation cannot drive cmux.
3. **The exact `it2` contract surface** Claude Code calls — reversed only partially.
4. **Agent View coverage** — `claude agents --json` is scoped to `CLAUDE_CONFIG_DIR`; it saw 3 of 25
   sessions. A 4-account fleet fragments into 4 views.

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
   directly with a minimal tape at `Set Framerate 60` → `avg_frame_rate=25/1`. The operator asked for
   1080p60; the resolution is honoured, the rate is not, and the caption says **25** rather than
   claiming a 60 the file does not have. A true 60 needs the `screencapture` path, which films a real
   window and carries a content-leak risk the scripted tape does not.
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
