# claude-infrastructure — operating reference

The [README](../README.md) argues the design in three layers; this file holds the operating detail
and the measurement record that used to live inside it, moved here on 2026-09-24 when the README
was rebuilt (worklog: [`research/README-rewrite-2026-09-24.pyramid-worklog.md`](research/README-rewrite-2026-09-24.pyramid-worklog.md)).
Everything below was carried over **verbatim** except where a later measurement corrected it; each
correction is marked *(corrected 2026-09-24)* with its source.

- [1. The terminal: why kitty, and the measurements behind it](#1-the-terminal-why-kitty-and-the-measurements-behind-it)
- [2. Operating reference — daemons, launchers, status line, kitty chords](#2-operating-reference)
- [3. Re-recording the demos and rebuilding the generated art](#3-re-recording-the-demos-and-rebuilding-the-generated-art)

---

## 1. The terminal: why kitty, and the measurements behind it

> **Status, 2026-09-24.** kitty has been the only working terminal since 2026-08-03 — the migration
> happened regardless of the HOLD recommended below ([`plans/TERMINAL_AGNOSTIC_L3_L4.md`](plans/TERMINAL_AGNOSTIC_L3_L4.md) §9).
> iTerm2 support survives behind the `it2` seam, dormant and not re-verified since August. The
> figures below are the dated record of the bakeoff (2026-07-31 → 2026-08-01), kept because the
> method and the refutations still hold; read the iTerm2 rows as history.

### Why 30+ panes froze iTerm2 — and why the GPU can't fix it

**It isn't a memory leak — it's windows that don't die.** iTerm2 has an unfixed upstream bug (#12097, #12645, #12905): closing a tab to zero panes should destroy its `NSWindow`; on iTerm2 it doesn't. One session left 98 "closed" windows alive, and each still costs the compositor real objects: a **window** costs ~28–34 MB of backing store + ~4.9 Mach ports to WindowServer; a **pane** inside an existing window costs almost nothing (~3 IOSurfaces, ~0 net bytes). Spreading 30 sessions across 30 windows costs WindowServer **2.35× more CPU than the same 30 panes gathered into one window** — while iTerm2 itself measured **0.0% CPU** and WindowServer sat at 92–99.9%. The window is the expensive unit.

**Pushing that rendering onto the idle GPU makes it worse, and Ghostty is the proof.** The bottleneck is compositor *objects*, and GPU rendering adds them: iTerm2's Metal path allocates a `CAMetalLayer` plus dispatch queues *per pane* and caps GPU rendering at 5 panes per tab, so lighting up 30 sessions on Metal forces **six separate windows** — the exact axis that already froze the machine. Ghostty has **no CPU renderer at all**, so if "more GPU" were the fix it should be the cheapest terminal under load; byte-matched at 18 panes / 10 fps it burns **27.3% app CPU against kitty's 9.5%**, because submitting frames to a GPU is itself CPU work, paid on every pane. kitty wins by putting all panes in **one** window, not by avoiding the GPU — and the axis is not the graphics API at all, which [§6](#the-interface-is) fits to cadence, then windows, then surfaces.

Full evidence and the migration plan: [`docs/research/terminal-for-30-panes-2026-07-31.md`](research/terminal-for-30-panes-2026-07-31.md).

### The interface is

| Measurement | Reading |
|---|---|
| **Renderer vs fleet** | iTerm2 **122.1%** + WindowServer **49.0%** ≈ **1.7 cores** — **2.3× the entire agent fleet it displays**, and that is the *conservative* end: five re-samples put the ratio at **2.74–4.08×** (median 2.89×) |
| **Leak, at frozen layout** | **+76 mach ports/hour** while RSS *falls* (−28 MB/hr) — the axis whose unbounded growth characterised the freeze |
| **Tuning headroom** | [`iterm2-perf-parity.sh`](../scripts/iterm2-perf-parity.sh) → `match=9 drift=0`, and it still burns 1.2 cores at *half* load ⇒ **configuration is exhausted** |
| **The unit that costs** | the same 30 panes cost **+22.6 pp** of a core across 30 windows vs **+11.2 pp** in one — **windows are 2.35×; panes are nearly free** |

This inverts the obvious remedy **on iTerm2**. It disables Metal for any tab holding ≥6 sessions *and* for every background tab, so its only all-GPU layout for 30 sessions is **6 windows** — which forces you into the expensive unit. On *that* architecture, "more GPU" and "more compositor objects" are the same request, because iTerm2 allocates one `CAMetalLayer` **per pane** — so the cap is protecting you.

But the axis is not the graphics API — it is **cadence, then windows, then surfaces**, fitted from four compositor arms at identical geometry and pixels/second:

| Axis | Coefficient | Lever at 30 panes |
|---|---|---|
| **Presentation cadence** | **0.480 pp/Hz** | **9.6pp — dominant, 6× the surface lever** |
| OS-window count | 0.4483 pp/window | 13.0pp across 1→30 |
| Surface count *within* a window | 0.0552 pp/surface | 1.60pp ceiling — 8.1× cheaper per unit than a window |
| **Metal vs OpenGL vs CPU** | **—** | **not a term** |

**Ghostty is the falsifier.** It is **Metal-native *and* per-pane**, and measures **24 panes in one window at 0.0% idle CPU / 351 MB**. If the API were the cost axis, that reading is impossible. What survives is **surfaces per window**, not *GPU or not* — so the cheapest lever is the one nobody files under "renderer": **drop the 120 Hz display to 60 Hz.** One reversible click, and a text UI gains nothing from 120 Hz.

### Therefore: stop rendering what you do not read

Measured on this box with one ruler — [`scripts/terminal-bench.sh`](../scripts/terminal-bench.sh), per-pid threads/RSS/ports from the **second** sample of `top -l 2` (never `ps %cpu`, a lifetime average that misread this box 2.3×). The decisive column is **loaded app CPU**: 18 panes repainting a byte-identical stream, every pane confirmed at 10.00 achieved fps.

| Terminal | **loaded app CPU** (18 panes @ 10 fps) | threads / pane | windows for 30 panes | per-pane scripting | console layer |
|---|---|---|---|---|---|
| **kitty** | **9.5%** — while carrying **22 % more bytes** | flat — 10 at 48 panes | **1** | `kitten @` · `$KITTY_WINDOW_ID` | — |
| iTerm2 | **10.5%** *in the cheap layout* (1 window × 20 panes, CPU renderer) | ~0.87–1.1 | 6 (forced by the Metal gate) | `ITERM_SESSION_ID` | — |
| WezTerm | 24.4% | **4.00, linear** | 1 | `wezterm cli` | — |
| Ghostty | 27.3% — highest, and 3 processes per loaded pane | **4.00, linear** | **1** | **none on macOS** (`performIpc` false; AppleScript only) | — |
| cmux | *not run under load* | **5.18, linear** (`5.18×panes + 10.6`) | 1 | **`CMUX_SURFACE_ID` + full socket API** | **built in** — sidebar row per pane, blue ring on attention, notifications panel, `notify` CLI |

**kitty wins among the challengers by 2.6–2.9× on loaded CPU — not on threads.** The thread-count rationale is **retired**: WezTerm measured **4.00** threads/pane, not the ~7.0 previously published, and the falsification test written to kill the thread finding **fired** — 87 WezTerm threads produced *fewer* context switches than kitty's 10.

**And the migration is on HOLD, because the incumbent has not been beaten.** The one iTerm2 datapoint taken in the *cheap* layout — one window, 20 panes, CPU renderer — read **10.5% against kitty's 9.5%**: within ~10% on CPU and within one thread. Every other iTerm2 figure above comes from the *expensive* layout it is normally run in, which is a statement about how it is configured, not about what it can do. Two cheaper rungs are live and unmeasured: the eight render knobs have never been benchmarked since passing their own gate, and the dismissal of plain `tmux` rested on a premise since verified **false**. See [`terminal-for-30-panes-2026-07-31.md`](research/terminal-for-30-panes-2026-07-31.md) §9.

**cmux does not dominate kitty either**: it wins the console axis — it ships, natively, the *shape* of the exception surface described below — and has not been run under load at all.

#### And the RAM-efficient harness is not a terminal at all

[jcode](https://github.com/1jehuang/jcode) (Rust, MIT, ~17k stars) advertises **+10.4 MB per added session against Claude Code's +212.7 MB**, which reads like the answer to a memory ceiling. It was evaluated 2026-08-11 and **ruled out** — the full 22-agent due diligence is in [`docs/research/jcode-due-diligence-2026-08-11.md`](research/jcode-due-diligence-2026-08-11.md). Four reasons, any one sufficient:

- **It replaces Claude Code, not kitty.** jcode is a harness that runs *inside* a terminal — its own `docs/TERMINAL_CAPABILITIES.md` is a matrix of kitty and iTerm2 quirks to survive, a document only a guest process writes. §6's HOLD on terminal migration is not engaged by it.
- **Its Claude path impersonates Claude Code to Anthropic.** Same OAuth `client_id`, `User-Agent: claude-cli/…`, the `claude-code-20250219` beta header, and an injected *"You are Claude Code, Anthropic's official CLI for Claude"* system block; jcode's own `OAUTH.md` states the API rejects OAuth requests without it. Anthropic prohibits consumer-plan OAuth tokens in other products. **The exposure is not a bill — it is the four Max subscriptions the fleet runs on**, and jcode's default `Auto` credential mode falls back to a metered API key on OAuth failure with only a log line.
- **It optimises the axis with headroom.** Resident memory ranks **fifth** of five binding constraints on this box ([`bottleneck-refute.md`](research/memory-econ-rearchitecture-2026-08-10/bottleneck-refute.md)); what refuses a session today is router `KMAX=8×4=32` and a dispatcher ceiling of 6. Its marginal figure is Linux `/proc/smaps_rollup` PSS on cold, ~4.5 s-old sessions — **no macOS/arm64 number exists** from the vendor, this fleet, or any third party.
- **It cannot touch the Model Context Protocol term.** The shared pool is daemon-only, jcode's own guidance requires stateful browser servers to be `shared:false` — so the saving on the one server that costs anything is 0 MB — and it is stdio-only, silently skipping the HTTP servers that already cost zero processes.

What would reopen it: a measured macOS footprint under real context load, and a lane that draws on **no** Max plan. The one slot worth trialling is the opposite of a migration — jcode's headless swarm worker as an Agent-Team *assignee* runtime on a non-Claude provider, which needs none of the 81 hook commands across 12 event types that the interactive lane would have to rebuild.

#### So the question stopped being "which one" — it runs on both

**iTerm2 and kitty are both first-class**, and the same session machinery — Agent Teams, handoff, recycling, two-way comms, teardown — runs on either. One command wires the second one:

```bash
scripts/kitty-setup.sh          # idempotent · --check reports · --undo reverts
```

Every pane chord it gives you — split, focus, swap, and the detach that is the only route to another monitor — is in [§2 below](#2-operating-reference).

**The lock was never the renderer — it was a process boundary this repo already owned.** Claude Code's Agent-Teams pane backend is not linked against iTerm2 and never handshakes with it. Decompiled from the live 2.1.219 binary, its gate is an **env check plus a PATH lookup** — `TERM_PROGRAM==="iTerm.app" || !!ITERM_SESSION_ID`, then `$SHELL -lc "command -v it2"` — after which it drives panes through exactly five subcommands of whatever `it2` it resolved. So a program answering those five commands against `kitty @` gets **native kitty split panes** for assignee sessions. That is [`bin/it2-kitty`](../bin/it2-kitty), and [`bin/it2-wrapper`](../bin/it2-wrapper) execs it when `KITTY_WINDOW_ID` is set. No fork of either terminal — which would be legally impossible anyway: iTerm2 is GPL-2.0-only, kitty GPL-3.0.

Four seams carry the rest, and each was a measured defect before it was a design:

| Seam | What it does | The defect that proved it necessary |
|---|---|---|
| `ITERM_SESSION_ID = w0t0p0:$KITTY_WINDOW_ID` | gives a kitty pane an id the whole fleet already knows how to read | the **colon is required** — Claude Code derives the leader id as everything after the first colon, and returns `null` without one, silently splitting from whatever pane is active |
| `~/.claude/shims` first on the **login** PATH | wins the lookup Claude Code actually performs | `-lc` is login-but-not-interactive: it reads `.zprofile` and **never `.zshrc`**, and the resolved path is **cached for the process lifetime** — losing that race bypasses the wrapper on iTerm2 too |
| the divert predicate, written once | decides "am I in kitty" identically everywhere | `handoff-fire.sh` and `cc-pane` deliberately resolve the *raw* it2 to inherit a pane's profile. Inside kitty there is no profile to inherit, so that bypass is pure loss — it resolves an iTerm2 client with no iTerm2 to talk to |
| [`bin/cc-kitty-bin`](../bin/cc-kitty-bin) — the kitty binary by **absolute path** | one resolver, so the seventh caller cannot reintroduce the bare name | `${CC_TERM_KITTY:-kitty}` appeared in six files, and hooks/launchd run with a PATH that excludes Homebrew — so `kitty` did not exist for exactly the callers that close panes. Measured: a teammate pane close from a hook exited `kitty: command not found`, rc 1, and the pane survived **3h09m** with its 653 MB `claude.exe` resident; the same command from the operator's shell closed it, rc 0. The worst polarity — **green where a human tests it, dead where it runs** |

Which is why the divert predicate is pinned by a test rather than trusted: a handoff that **splits the pane with one binary and addresses it with another** fails in a way no single-file test can see.

**What is verified, and on which terminal.** Every ✅ names the evidence that earned it:

| Surface | iTerm2 | kitty | Evidence |
|---|---|---|---|
| Agent-Teams assignee panes | ✅ | ✅ | **this change was written by two of them** — see below |
| Pane seam (`cc-pane` address/list/send/close) | ✅ | ✅ | live on this box; `address <gone>` correctly returns an authoritative **NO**, not indeterminate |
| Two-way comms | ✅ | ✅ | delivery is **a file, not a keystroke** ([README §1](../README.md#2-the-sessions-run-each-other)) — terminal-agnostic by construction; only the pane-liveness oracle touched a terminal |
| Session register · teardown · crash watchdog | ✅ | ✅ | live registry holds kitty-hosted sessions keyed by bare kitty pane ids across all four accounts; teardown resolves the shim, and the operator page is a macOS notification, not an iTerm2 call |
| Handoff / recycle — **split + type + focus** | ✅ | ✅ | argv verified verb by verb against the contract: `focus-window --match id:`, `close-window`, `send-text` preserving the raw `Ctrl-U` byte, and `run` appending `\r`. `focus` with no target **refuses** rather than hijacking the active pane |
| Handoff — tty / tab / background-tab helpers | ✅ | ✅ | pane→`pid`→`ps -o tty=` for the tty kitty does not expose; `--keep-focus` on the background tab. The **two exit states** are the contract — a failed query and an absent pane must not be confused, or a live successor reads dead — and inverting them is one of the 10 mutations the suite convicts |
| Limit-recovery · boot-resume · pane census | ✅ | ✅ | AppleScript pane-open → `kitty @ launch`. The census was *worse than inert* on kitty: it truthfully reported **0 iTerm2 panes** on a box with a dozen live ones, zeroing the operator's only load-shed lever. Every kitty failure mode now lands on **null**, never `0` |

**The Agent-Teams row is self-demonstrating.** Part of this section's own work was done by two assignee sessions spawned from a kitty pane: 19 panes before, **21 after**, the two new ones being kitty windows `30` and `31` running `claude.exe --agent-id k2-handoff@…` and `--agent-id k3-recovery@…` — the whole chain exercised with no stub in it.

**Two-way comms was already portable and nobody had noticed.** Because a message is a file that hooks read, none of it was ever terminal-coupled; the *only* terminal call in the path was asking "is that pane still alive". When that oracle broke on kitty it returned **unknown** rather than **dead**, so nothing was mis-delivered and nothing went red — invisible precisely because it failed correctly.

#### The instrument, running

<div align="center">

<img src="../assets/demo/terminal-bench.webp" width="900" alt="Terminal recording of scripts/terminal-bench.sh measuring the live terminals on this machine in five scenes. Scene 1 greps the READ-ONLY contract out of the script's own source. Scene 2 censuses which terminals are actually running, matching on the ps comm basename. Scene 3 runs a full drift row against kitty and prints verdict=OK. Scene 4 runs against the live iTerm2 and prints a GPU to CPU frame ratio below one, showing it renders mostly on the CPU, ending in verdict=PARTIAL. Scene 5 runs against WezTerm, which is not installed, and prints verdict=NO-DATA with exit 3.">

<sub><b>Every number in this terminal record came out of this instrument, on this machine.</b> Recorded with <a href="https://github.com/charmbracelet/vhs">VHS</a> from <a href="../assets/demo/terminal-bench.tape"><code>assets/demo/terminal-bench.tape</code></a> — re-runnable, so it cannot drift from the script it documents. <a href="../scripts/terminal-bench.sh"><code>terminal-bench.sh</code></a> is <b>read-only by construction</b> (creates no panes, closes none, writes no preference), which is the only reason it is safe to aim at a live fleet mid-session. <a href="../assets/demo/terminal-bench.mp4">Full-resolution video</a> — <b>1920×1080, 60 fps</b>, an unedited <code>screencapture</code> of the same sequence at display refresh.</sub>

</div>

**Why three different verdicts are on camera.** `verdict=` has three terminal states, so a reader can always tell a measured zero from a run that never happened: `OK` (both readings + GPU profile resolved), `PARTIAL` (**every number real, but one reading cannot support a leak verdict** — the OK token is refused rather than overclaimed), and `NO-DATA` at exit 3 (the app is not running).

**The readings behind the table**, verbatim from that run, 2026-07-31, against this machine's own live fleet of 13 Claude Code sessions:

| live app | CPU | threads | mach ports | RSS | **GPU:CPU frame ratio** | verdict |
|---|---|---|---|---|---|---|
| **iTerm2** (incumbent) | **106.9%** | 12 | 700 | 800 MB | **0.53 : 1 — draws mostly on the CPU** | `PARTIAL` |
| **kitty** | **0.0%** | **8** | 362 | 321 MB | **50.0 : 1** | `OK` |
| Ghostty | 0.0% | 8 | 338 | 84 MB | 16.0 : 1 | `OK` |
| WezTerm | — | — | — | — | — | `NO-DATA` (not installed **at the time of that run**) |
| cmux | — | — | — | — | — | **not driveable by this instrument** — see below |

**WezTerm was measured under the films** (2026-08-01), and the two instruments agree:
**27.2% app CPU, 82 threads (4.56/pane), 177 MB, GPU:CPU 107.5 : 1** at 18 panes of the same load,
against the candidate table's independently-derived 24.4% and 4.00 threads/pane. The same run puts
kitty at **10.4% / 10 threads** and Ghostty at **31.7% / 139 threads**, each with the row committed
beside its film. These are 18 panes under load, not the idle fleet in the table above — two regimes,
kept in two tables.

**cmux is absent because this instrument cannot drive it** — a property of cmux, measured
2026-08-01. Its control socket refuses processes that did not start inside cmux (`Access denied -
only processes started inside cmux can connect`, with `socketPassword` empty in
`~/.config/cmux/cmux.json`), and `cmux new-split` accepts no `--command`, so even an authorised
caller cannot put the load into the panes it creates — only `workspace create` takes one, which
yields a single loaded pane and seventeen idle shells. Its only measured column is therefore the
structural one above (5.18 threads/pane, linear).

That `0.53 : 1` is **measured by profile, not read off a flag** — `sample` symbol counts, because a loaded GPU driver and a warm shader cache can only ever refute *"absent"*, never establish *"used"*. iTerm2 ships a Metal renderer and was still resolving 235 CPU frames to 125 GPU frames while burning a full core.

**The leak axis — where the evidence genuinely runs out.** iTerm2 measured **+76 mach ports/hour** at frozen layout; kitty read **+0 ports, +0 windows, +0 offscreen** over the same instrument — but a 45-second window cannot resolve a rate finer than ~80 ports/hr, so that reading **cannot exclude iTerm2's +76/hr**. A 30-minute run taken to sharpen it (at 1800 s, one port is 2/hr) did not deliver a clean bound either: the window census fell 36 → 19 while it held, so the layout was not constant and its `+5 ports` cannot be separated into leaked-versus-released — recorded as still-open in [`terminal-for-30-panes-2026-07-31.md`](research/terminal-for-30-panes-2026-07-31.md) §6.1 rather than quoted as a bound it is not. What it *does* show is churn: **the window population fell by 17 and offscreen by 18** for +5 ports and +20 MB — kitty gave the windows back, where iTerm2 had **98 windows survive `close()`** ([upstream #12097](https://gitlab.com/gnachman/iterm2/-/issues/12097), open since 2025-01-01).

**The sustained-runtime question is open, and it is the largest gap in the terminal case** — the challenger is ahead of its rivals on loaded CPU, level with the incumbent in the incumbent's cheap layout, and unproven over hours. **Which is why the move below is a seam and not a migration:** a `CC_PANE_ID` abstraction costs the same whichever terminal eventually wins, so the question need not be answered before anything else can proceed.

**Reproduce any row yourself** — one read-only command per terminal:

```bash
scripts/terminal-bench.sh --app kitty  --interval 1800   # full row + drift  → verdict=OK
scripts/terminal-bench.sh --app iTerm2 --interval 0      # single reading    → verdict=PARTIAL
scripts/terminal-bench.sh --app wezterm --interval 0     # not running       → verdict=NO-DATA, exit 3
```

The first command is the one that failed above, and **it can no longer fail that way quietly**. `verdict=OK` never certified the constant-layout precondition, so the instrument now measures that precondition itself, re-checks it every `--watch` seconds, and **aborts with `verdict=LAYOUT-DRIFT` (exit 4) instead of printing a confounded row**. The gate keys on the *onscreen* count, and on offscreen only when offscreen **falls**: a *rising* offscreen count is the leak being measured, so a gate keyed on the `windows` total would make a leaking terminal abort its own measurement and become structurally unable to report the leak.

**The raw transcripts are committed**, so every number above is auditable against the run that produced it rather than against this table: [`bench-live-3way-2026-07-31.txt`](research/data/bench-live-3way-2026-07-31.txt) (the kitty/Ghostty/cmux readings) and [`kitty-drift-30min-2026-07-31.txt`](research/data/kitty-drift-30min-2026-07-31.txt) (the 30-minute run, including the window census that invalidates it as a drift bound).

Full method, per-candidate rows and the falsification plan: [`terminal-for-30-panes-2026-07-31.md`](research/terminal-for-30-panes-2026-07-31.md) · adjudication of the two outside reports: [`l3-l4-terminal-and-workflow-2026-07-31.md`](research/l3-l4-terminal-and-workflow-2026-07-31.md) · the plan this feeds: [`TERMINAL_AGNOSTIC_L3_L4.md`](plans/TERMINAL_AGNOSTIC_L3_L4.md).

#### And the renderers themselves, under the load — one film per terminal

This films the *subject*: 18 panes of the identical
Ink-shaped load ([`tui-load.sh`](../scripts/tui-load.sh) — alternate screen, 24-bit colour, full-frame
repaint at 10 fps) repainting in each candidate, recorded at **1920×1080, 60 fps**, with that
terminal's [`terminal-bench.sh`](../scripts/terminal-bench.sh) row taken **during the same take** so the
film and the numbers describe one event rather than two.

<div align="center">

<img src="../assets/demo/renderer-grid.webp" width="900" alt="An animated clip, four terminals in a 2x2 grid, each showing an 18-pane window repainting under the same synthetic load. Colour ramps shift row by row in every pane. kitty's panes form an even grid; WezTerm's, Ghostty's and iTerm2's form uneven binary split trees. Each pane header shows its own measured column-by-row geometry.">

<sub><b>The films themselves, playing — 18 panes, one window, the same load, this machine.</b> 3 s of each take at 10 fps, 900 px per tile. <b>Full 1080p60 masters</b> (1920×1080, 60/1, ~15 s): <a href="../assets/demo/renderer-kitty.mp4">kitty</a> · <a href="../assets/demo/renderer-wezterm.mp4">WezTerm</a> · <a href="../assets/demo/renderer-ghostty.mp4">Ghostty</a> · <a href="../assets/demo/renderer-itermbench.mp4">iTerm2</a> Measurement row taken during each take: <a href="../assets/demo/renderer-kitty.txt">kitty</a> · <a href="../assets/demo/renderer-wezterm.txt">WezTerm</a> · <a href="../assets/demo/renderer-ghostty.txt">Ghostty</a> · <a href="../assets/demo/renderer-itermbench.txt">iTerm2</a>. Reproduce: <a href="../assets/demo/renderer-film.sh"><code>renderer-film.sh --app kitty</code></a>, then <a href="../assets/demo/renderer-grid.sh"><code>renderer-grid.sh</code></a>.</sub>

<sub><b>Ghostty's tile is lighter than kitty's</b> because its default background is <code>#282c34</code> against kitty's true black — not because that window was unfocused (checked: the background sits at 42–44 across all 48 spatial blocks). <b>iTerm2 is the isolated clone</b> built by <a href="../scripts/iterm-metal-bench-app.sh"><code>iterm-metal-bench-app.sh</code></a>, never the real one.</sub>

</div>

**The films show that the load really ran, in that terminal, on this box** — not that one terminal
beat another on looks. Three caveats:

- **The pane geometry differs because the terminals differ.** kitty is run with its `grid` layout,
  which is what an 18-pane kitty user would actually use; WezTerm and Ghostty have no grid layout, so
  they get their own binary split trees and their cells come out uneven.
- **Each pane's header shows its own measured geometry** (`62x19`, `94x22`, `79x40`…), because it
  was once wrong: `tui-load.sh` sized itself with `tput cols`, which inside a command substitution
  reports the terminfo default **80×24** instead of the pane, so WezTerm panes painted a small fixed
  frame while kitty painted full-size ones — an *identical*-load generator silently not delivering
  one. Fixed to read `stty size`; geometry and the answering probe are now recorded per pane.
- **Ghostty's row is app-wide, not per-pane.** Ghostty is a single shared process that was already
  running the operator's own surfaces, so its totals include panes these films did not create. The
  row says so; the per-pane division there is an upper bound.

**The incumbent is not filmed, because launching it is already destructive.** A "film it only when
iTerm2 is not running" guard passes and is still not enough: window restoration fires **at launch**,
before any check can run, and it reopened three of the operator's windows and landed 18 splits in
*their* live sessions. So [`renderer-film.sh`](../assets/demo/renderer-film.sh) refuses `--app iterm2`
outright and implements the isolated route itself as `--app itermbench`, driving
[`iterm-metal-bench-app.sh`](../scripts/iterm-metal-bench-app.sh), which clones iTerm2 under its own
bundle id and defaults domain — the only route that restores nothing.

**Stalls are measured at the source, and every candidate has none.** ScreenCaptureKit emits a frame
only when the window's content changes, so the gap between delivered frames *is* how long that window
sat unchanged: kitty, WezTerm and Ghostty each recorded **0 gaps over 1.5 s**, with longest gaps of
**0.07 s, 0.06 s and 0.04 s**. A pixel-based `freezedetect` reading is not usable here — it averages
over the whole frame, so on sparse coloured text it called a 20-second film containing 808 distinct
frames "frozen from t=0".

But the renderer is the *second*-order fix: a 30-pane grid is a **polling** interface, so its cost scales with agent count, and exception routing does not. The beacon already writes every blocked session to `/tmp/cc-permission-pending/` and nothing reads it — caught live while this section was written, two sessions blocked at once under full three-monitor visibility, one unattended for **6.6 minutes**.

Nor can the allow-list close the gap: **88.3% of prompting Bash calls are compound**, so a `Bash(prefix:*)` list caps at ~2.4% coverage regardless of rule count — already at `defaultMode: auto` with **339 allow / 6 ask / 41 deny** *(corrected 2026-09-24: 344 allow / 3 ask / 41 deny, `jq '.permissions' ~/.claude/settings.json`; the residue is now mostly hook-emitted asks — [`research/permission-prompt-census-2026-09-10.md`](research/permission-prompt-census-2026-09-10.md))*. The residue is the guardrail working. The defect is not that it blocks; it is that *discovering* the block costs a full-screen poll.

### Roadmap

| When | Move | Why it is sized this way |
|---|---|---|
| **Now** | Do **not** cap V8 heaps; stop the automation minting **windows**; add a window-count rung to `capacity-alarm.sh` (warn 25 / page 60, measured as *drift*) | free, reversible, and windows are the 2.35× unit |
| **Done** | Support **both** terminals, behind one seam ([above](#so-the-question-stopped-being-which-one--it-runs-on-both)) | a seam costs the same as a migration and does not require winning the argument first; `scripts/kitty-setup.sh` wires it in one command |
| **Then** | Give the beacon a face — **a console, not a terminal**: one row per session, a queue fed by the beacon, zoom-to-full-screen on demand, a dispatch composer | implements no VT at all; rendering then scales with sessions *blocked* (0–3), not sessions *running* (30+) |

**Writing a terminal from scratch was considered and rejected.** WindowServer is the ceiling and it is Apple's — 30 panes in one window cost ~+11.2 pp of a core inside the compositor, the floor for *any* application, and kitty already sits on it. A from-scratch emulator's best case is matching something already installed, while owning VT correctness under Ink's alternate-screen/resize/wide-char usage forever.

---

## 2. Operating reference

### Why a recycle types `/exit` rather than `/clear` plus a queued prompt

`handoff-fire.sh --recycle` arms a detached watcher, types `/exit`, and relaunches `claude` in the
same pane once the old process is gone. It does not use `/clear` followed by a queued brief, because
Claude Code's input queue treats the two kinds differently: a built-in slash command waits for the
current turn to end, while plain text is injected into the still-running turn at the next
tool-result boundary, and the firing script's own Bash call guarantees one. A queued brief would
therefore run inside the **old** context, with `/clear` still waiting behind it.

**28 launchd daemons** *(corrected 2026-09-24: 28 top-level plists, all installed, 26 loaded; 5 more in `launchd/staged/`)* (`launchd/`, all low-priority; `install.sh` copies and loads them). The rows below are the original 20; `launchd/fleet.manifest` is the complete, current list:

| Plist | Schedule | Purpose |
|---|---|---|
| `com.claude.dispatcher` | 5 min + kicked by every backlog write *(corrected 2026-09-24)* | open backlog → quota-aware wave plan → fire worker sessions |
| `com.claude.discovery` | 60 min | scan ledgers, plans and gates for new work → feed the backlog |
| `com.chrisren.autonomy-sweep` | 5 min | alarms, pages and decision-packet sweep → operator escalation |
| `com.claude.desk-invariant` | 5 min | desk liveness + recycle-armedness fail-loud monitor |
| `com.claude.boot-resume` | 5 min | post-reboot ghost-session detection + consolidated resume |
| `com.claude.team-orphan-reaper` | 10 min | archive dead teammate panes and worktrees (identity-pinned) |
| `com.claude.postland-verify` | 5 min | assert a landing actually reached trunk, by content |
| `com.claude.log-rotation` | 60 min | size-gated rotation of `idl.jsonl` + bash command logs |
| `com.claude.caffeinate-floor` | KeepAlive | sleep-prevention floor while sessions run |
| `com.claude.power-policy-verify` | 60 min | assert pmset/caffeinate continuity posture |
| `com.claude.nightly-regression` | 4 am | full bats suite against the live deployment — `fleet.manifest` says **staged**, but it is loaded on this machine *(corrected 2026-09-24: the repo and the machine disagree)* |
| `com.claude.session-search-sweep` | 60 s | catch missed session transcripts |
| `com.claude.session-search-backfill` | Sun 3 am | full backfill of all sessions |
| `com.claude.deploy-live` | 10 min | advance the live `~/.claude` layer once the green stamp allows it |
| `com.claude.lead-supervisor` | KeepAlive | watch the leads; reap stranded panes and beacons |
| `com.claude.capacity-alarm` | 60 s | fail-loud when the box runs out of headroom — or out of scheduler |
| `com.claude.qos-census` | 10 min | census the fleet's QoS bands (the PRI-4 ratchet is one-way) |
| `com.claude.worktree-gc-infra` | 4:15 am | reap merged and stale worktrees of this repo |
| `com.chrisren.cc-reaper` | 5 min | reap dead sessions the registry still lists |
| `com.chrisren.watch-claude-code-2118-hold` | 9:12 am | poll the three upstream issues (GH #52251, #52522, #51798) that block moving the stable track from 2.1.114 to 2.1.118 *(corrected 2026-09-24)* |

**Status line.** [`statusline.sh`](../statusline.sh) shows `(n) dir (commit) branch* · effort · N%`. The leading `(n)` is the **parallel-instance marker** — which `claude-next<n>` launcher this session is, derived from its `CLAUDE_CONFIG_DIR` (`~/.claude-next` → 1, `-secondary` → 2, `-tertiary` → 3, `-quaternary` → 4; stable `claude`/`cc` shows nothing). It is left-anchored so a narrow terminal's ellipsis cannot eat it. The marker is **per-terminal**: iTerm2 gets the circled glyph `①..⑳`, everything else gets the ASCII ring, because a circle drawn inside one cell is bounded by the cell's *width* — iTerm2 draws fallback glyphs at natural size and lets them overflow (~27 px, larger than the text), while kitty squeezes them into one cell (18 px, unreadable). The context percentage subtracts a **reserved-token** allowance — 97k absolute (64k output buffer, 13k auto-compact, 20k warning) scaled against the window size the payload reports, so it costs 48 points on a 200k window but only ~9 on a 1M one. It was a fixed 48 until 2026-07-13, which overstated usage ~2.3× on 1M-window models. Under 60% gray, 60–90% default, over 90% red. [`notify.sh`](../hooks/notify.sh) pairs a system sound with a desktop alert that **names the session it came from** — `Permission · <dir>` over `<session> · <tool>` over the actual blocked command — debounced 2 s **per session**, so two sessions blocking at once are two alerts rather than one. Funk for a permission request, Blow for a question, Glass for a plan ready to review, Purr for task completion (sound only).

**Browser automation** goes through the **`agent-browser` CLI** (and `chrome-devtools-mcp --browserUrl` when a session genuinely needs the MCP tool surface against an already-running Chrome). **BrowserMCP was retired on 2026-08-11** — wrapper `git rm`'d, and every config site cleared: `mcpServers.browsermcp` in `~/.claude.json` (user + `reso-upgrade-dependencies`), `enabledMcpjsonServers` across five config dirs and five project `settings.local.json`, and the `~/.claude/.mcp.json` entry four config dirs symlink into. The evidence was that it was **not being used and could not be**: 0 invocations across 3,504 transcripts / 30 days, upstream frozen 2025-04-11, and a port-9009 `kill -9` singleton that makes per-session spawning invalid by construction. A wrapper that fixes NVM-path connection failures for a server nothing connects to is pure carrying cost. Provenance: [`docs/research/mcp-memory-groundup-2026-08-10.md`](research/mcp-memory-groundup-2026-08-10.md) §3.

**Shell launchers** (`~/.zshrc`) — two tracks, one name each. `claude` is THE entrypoint: pinned eval binary (2.1.280 since 2026-09-22), Opus 5.5 (`claude-opus-5-5`) *(corrected 2026-09-24)*, `--permission-mode auto`, `--effort high`, config `~/.claude-next` — and bare `claude` routes each launch to an account while `claude1` pins account 1 *(corrected 2026-09-24; `lib/claude-launcher.zsh`)* — auto-updater off, nested-subagent depth capped at 1. `claude-prev` is the pinned **stable 2.1.114** track on `~/.claude`. Each fans out per account as `claude2`/`3`/`4` and `claude-prev2`/`3`/`4` — the same body with `CLAUDE_CONFIG_DIR` set, never a second entrypoint. Around them: `claude-plan` (plan mode + "ultrathink") · `claude-x`/`-h` (effort tiers) · `cc`/`cc-prev`/`ccr` (resume: per-track and cross-worktree) · `claude-desk*` (orchestrator desk) · `claude-which` (active config dir). No-auto-mode is `CLAUDE_PERM_MODE=default claude`. The frontier tier is a **model, not a name**, and it has two live routes: pick `Fable` in the in-session `/model` picker (row 3 — the normal way in), or start pinned with `claude --model claude-fable-5-1` when a session must *be* Fable from turn one, as fired peers and headless runs must (the id is whatever `model-config.yaml` `frontier_access.model` says — `claude-fable-5-1` since the 2026-09-03 flip; the bare alias `--model fable` resolves to the same model on 2.1.260, measured). The ~2×-cost warning is printed by `claude` itself when it sees that model selected. Six other name families (`claude-next*`, `claude-opus5*`, `cc-next*`, `claude-fable*`, `claude-previous*`, `claude-stable`) were deleted in the 2026-08-01 consolidation: they were one launcher body wearing six spellings, so each was a thing to keep in sync and none was a thing anyone ran. Gate check 5 now asserts their **absence** beside its effect-read of `claude`, because a deleted launcher name comes back silently otherwise.

**`claude --resume <id>` works from anywhere** (2026-08-02). Claude Code resolves a session id in exactly one place — `$CLAUDE_CONFIG_DIR/projects/<cwd-hashed>/<id>.jsonl` — and on this machine *both* halves of that path are ambient: four account config dirs, and a project dir per worktree. So the line Claude prints at the end of every session, `Resume this session with: claude --resume <id>`, failed from anywhere but the pane that printed it, on either axis, with the same undiagnostic `No conversation found`. `bin/cc-resume-resolve` searches every account store (from the `accounts.json` SSOT), finds the transcript, and reads the cwd the session actually recorded; `lib/cc-resume-shell.sh`'s `_cc_resume_pin` — called by `claude` and `claude-prev` — redirects the config dir and launches in that cwd via a subshell, so your own pane never moves. It accepts an 8-char id prefix, refuses an ambiguous one by name, recreates a reaped worktree path so a stranded transcript still loads, and **fails open**: an id it cannot resolve is passed through untouched for Claude to report itself. A bare `--resume` (the interactive picker) is deliberately left alone, because that one is cwd-scoped by design. Escape hatch for a deliberate cross-account transplant: `CC_RESUME_NO_RESOLVE=1`. **It redirects, it does not transplant** — the launcher name you type is irrelevant (`claude4 --resume <id>` on an account-3 session was verified to run on account 3), so a resumed session always spends the *owning* account's auth and quota. That makes an account's sessions unresumable while it sits past its login cliff or its weekly limit, and no redirect can route around that — you are picking a session, not an account.

Which binary any of that actually runs is resolved by **one** reader, [`bin/cc-claude-bin`](../bin/cc-claude-bin), which parses the launcher's own `_bin=` pin rather than restating it — so repointing the launcher moves every consumer in the same edit. Before advancing a version, [`scripts/cc-upgrade-gate.sh`](../scripts/cc-upgrade-gate.sh) runs 15 empirical checks *(corrected 2026-09-24; check 14 = credential-write safety, check 15 = nested-spawn depth effect)* against the *candidate* binary (model registration, auto-mode non-blocking, effort ladder, spawn-depth containment, teammate/workflow/subagent spawn, lifecycle hooks, resume routing, MCP) and returns one GREEN/RED verdict — which is what carries the decision when a release ships a one-line changelog.

**19 commands** (`commands/`) — `/handoff`, `/ship`, `/wrap`, `/desk`, `/accounts`, `/limit-recover`, `/research`, `/review`, `/commit`, `/harvest-skill` and more. **15 skills** (`skills/`) — agent-teams, research-subagents, frontier-routing, coding-standards, plan-conventions, cc-upgrade-gate and others. **4 agents** (`agents/`) — `deep-research` (frontier/adversarial research), `deep-research-sonnet` (bulk-fan-out worker, currently benched), `frontier-derivation` (baseline-blind derivation panelist for `/frontier-run`), `research-decomposition-critic` (pre-spawn decomposition critic). Symlinked into `~/.claude/agents/` like the skills beside them, so editing the repo file edits the live agent.

**Driving kitty's panes — every gesture, and the two the keyboard cannot reach.**

<div align="center">

<img src="../assets/demo/kitty-panes.webp" width="900" alt="Screen recording of a single kitty window running the pane-management sequence. A narration pane on the left prints each chord as it fires; the window splits right, then below, into three coloured panes. A pane then swaps places with its neighbour, another is thrown to the top edge, per-pane title bars appear across the tops of the panes, and finally one pane leaves the split entirely and a tab bar appears at the bottom of the window holding it.">

<sub><b>One kitty window, one sequence, every chord below.</b> The narration pane prints each chord as it fires, so the frame that shows a change already names the action that caused it. Each beat is the mappable action the chord is bound to, driven over that window's own remote-control socket — <b>keystrokes are deliberately not synthesised</b>, because macOS sends them to the frontmost process and on this box that is usually one of ~30 live agent panes. <a href="../assets/demo/kitty-panes.mp4">Full-resolution video</a> — <b>1920×1080, 60 fps</b> (the window-scoped capture delivered <b>41.7 fps</b> of distinct frames; the container is 60). Reproduce with <a href="../assets/demo/kitty-panes-capture.sh"><code>assets/demo/kitty-panes-capture.sh</code></a>.</sub>

</div>

**The chords.** All of them live in [`config/kitty.conf`](../config/kitty.conf) and are pinned by
[`tests/kitty-conf-bindings.bats`](../tests/kitty-conf-bindings.bats) against kitty's *own* config
loader — so a rename in a future kitty fails there rather than under your fingers. After editing,
`kitten @ load-config` applies everything except `allow_remote_control` and `listen_on`.

| | Chord | Action | Note |
|---|---|---|---|
| **Split** | ⌘D · ⌘⇧D | `launch --location=vsplit\|hsplit` | right · below, inheriting the cwd |
| | ⌘W | `close_window` | last pane closes the tab, then the window |
| | ⌘⇧↩ | `toggle_layout stack` | zoom one pane to fill the tab |
| **Focus** | ⌘⌥←→↑↓ | `neighboring_window` | split-aware; ⌘] ⌘[ cycle |
| **Move the pane** | ⌘⇧←→↑↓ | `move_window` | a **swap** with the neighbouring slot |
| | ⌘⌃←→↑↓ | `layout_action move_to_screen_edge` | the placement a swap cannot express |
| | ⌘⌃R · ⌘⌃E | `layout_action rotate` · `equalize` | flip a split's axis · even them out |
| | ⌘R | `start_resizing_window` | arrows, then Esc |
| **Leave the tab** | ⌘⇧O | `detach_window ask` | chooser — **this is the cross-monitor move** |
| | ⌘⌥O · ⌘⌃O | `detach_window` · `detach_tab ask` | into a new OS window · move the whole tab |
| **Mouse** | drag a divider | resize | needs `window_drag_tolerance` above kitty's 2 pt |
| | ⌘⇧B, then drag a title bar | re-order | ⌘⇧B is what *draws* the handle |

**Three that are not guessable.**

- **`move_window` is a swap, and a silent no-op with no neighbour.** In a two-pane side-by-side
  tab, ⌘⇧↑ and ⌘⇧↓ are correctly dead — no beep, no message, nothing — which is indistinguishable
  from a binding that failed to load. `move_to_screen_edge` is the action for "put it *there*".
- **kitty has no action that sends a window to a display.** A pane's monitor is simply wherever its
  OS window sits, so the route to the other screen is to *detach into a window that is already
  there* — ⌘⇧O, pick the tab. Measured on kitty 0.48.2: window id and child pid are **unchanged**
  across a detach into a new OS window and then into an existing tab, so a running Claude Code
  session moves with its pty, scrollback and process intact.
- **The mouse can drag a pane only by a title bar kitty does not draw** — hence ⌘⇧B — and only
  **tabs**, never panes, can be dragged *between* OS windows. That gesture also needs
  `tab_bar_min_tabs 1`, which is deliberately off here: a permanently visible tab bar costs one
  text row in every OS window, and at 30 panes that row is screen space this repo will not spend.

**Clicking a claude.ai link opens it as the account that owns the pane.** Every pane used to share
one `open_url_with open -b company.thebrowser.dia`, and LaunchServices has no profile argument — so
an artifact published by the account-3 session opened in the account-1 Dia Space and rendered *Page
not found*. The link was never broken; it was handed to a browser identity that could not see it.
[`bin/cc-url-open`](../bin/cc-url-open) closes that: it reads the **focused kitty window**, looks that
pane's account up in `cc-registry` (the same row `cc-notify` reads), maps it through `accounts.json`
→ Dia's `Local State` to that account's Space, and opens the link *there*. Nothing else changes —
non-`claude.ai` URLs, a pane with no registry row, an unknown account and every error take the
`open -b` path this used to be, so the worst case is exactly the old behaviour.

The transport is the interesting part, and two obvious routes are dead ends worth naming: Dia's
binary **will not forward a URL to a running Dia at all** (with *or* without `--profile-directory` —
both launches sit alive and open nothing), and `Target.createTarget({browserContextId})` is
**refused across profiles** even though `Target.getTargets` reports the id. What works is attaching
to a page that already lives in the target Space and having *it* `window.open` the link — the new
tab inherits its opener's profile by construction. That needs Dia's remote-debugging port, which is
unauthenticated and exposes every Space, so this **never enables it** and never asks you to: port
down (or a consent dialog pending) is just another fallback. Pinned by
[`tests/cc-url-open.bats`](../tests/cc-url-open.bats), where every unhappy path asserts the same thing
— the URL still reaches `open`. A handler that can swallow a click is worse than one that routes it
wrong.


---

## 3. Re-recording the demos and rebuilding the generated art

**Editing the diagrams.** Sources live in `assets/diagrams/*.mmd` and render through [beautiful-mermaid](https://www.npmjs.com/package/beautiful-mermaid) — the ELK-based engine behind Cursor's agent panel — into per-mode SVGs, because GitHub cannot swap its own dagre renderer. Edit the `.mmd`, run `npm run diagrams`, commit the regenerated SVGs.

**Re-recording the demos.** `assets/demo/handoff-real.webp` regenerates from its committed tape — `vhs assets/demo/handoff-real.tape`, then `gif2webp -m 6 -min_size` — so the command output in the README can never drift from the scripts. `assets/demo/handoff-live.webp` is a screen recording of an actual `/handoff`; it is captured by hand (`screencapture -v`, cropped to the iTerm2 window with `ffmpeg`) because it depends on a live fleet, so there is no script for it, and it is encoded `img2webp -near_lossless 40`. The two routes differ because the content does: flat terminal output converts losslessly (`gif2webp`, 10.6 % smaller), while a live screen recording must be **near-lossless** — ordinary lossy WebP encodes each frame as a partial update rectangle, and the flat grey of an unfocused pane re-quantizes differently inside that rectangle than outside, leaving a visible vertical seam. Measurements in the `demo-recording` skill.

`assets/demo/terminal-bench.*` is the third, and it is the only one needing **two** routes. The inline WebP takes the VHS path like the first — `vhs assets/demo/terminal-bench.tape`, then `gif2webp -m 6 -min_size -mt`. The linked MP4 **cannot**: VHS 0.11 ignores `Set Framerate` for its mp4 muxer and emits 25 fps whatever the tape asks — probed directly, since a tool's documented option silently not applying is exactly the kind of thing that ships as a false caption. So the 1080p60 master is a real `screencapture` of [`terminal-bench-capture.sh`](../assets/demo/terminal-bench-capture.sh) at display refresh, and the tape deliberately emits no mp4 that could overwrite it. GitHub's sanitizer strips `<video>`, so the MP4 is only ever a link beside the image.

**That capture route can film the operator's screen: three separate leaks were caught by the mandatory contact sheet.** `screencapture -l<window-id>` does *not* scope **video** to that window (it recorded the whole display, Dock and other windows — use `-R x,y,w,h` with your own window covering the rect); a macOS notification banner carrying live session ids landed in the top-right (banners are right-aligned — keep the rect's right edge clear of them); and the window closed before the `-V` budget expired, so the tail filmed the desktop. Scan **every** second for that last one rather than sampling — mean luma separates the states unambiguously (terminal ≈ 6.4k, wallpaper ≈ 22.8k of 65535). Rect geometry and the full recipe are in the tape header.

Unlike the other two, this clip has a **live dependency it does not control**: it measures whatever terminals are running when it is recorded, so a re-record on another day legitimately produces different numbers, and the `verdict=NO-DATA` scene stays honest only while WezTerm is genuinely absent. Re-check the scene comments against reality first. And note `pgrep -x iTerm2` **cannot see iTerm2 on macOS** — its accounting name is the first 16 chars of its full path — which is why the script and the tape both match on the `ps` comm basename.

`assets/demo/kitty-panes.*` is the fourth, and it settles the capture problem the one above only worked around. It is filmed **window-scoped** — `tools/terminal-bench/window-film.swift` (ScreenCaptureKit, compiled with `swiftc`; interpreted, the same call aborts inside swift-frontend), resolved by title through `window-rect.swift`, exactly as [`renderer-film.sh`](../assets/demo/renderer-film.sh) does. That is a **safety property, not a convenience**: a `-R` rect films whatever is on top of it — the first attempt at this demo recorded the operator's browser, because the demo window was behind it. Positioning the window to fix the rect is not available either: it needs Accessibility, and `osascript` here answers *"not allowed assistive access"* (-1719). The window-scoped filter composites the window's own content, so occlusion, the Dock and notification banners become **impossible** to film rather than something a contact sheet has to catch — and it works while the window is on no visible Space at all, which is where a freshly launched window on this four-display box actually lands.

It also takes **two routes for one sequence**, for a measured reason. The linked 1080p60 master is filmed with the panes running [`tui-load.sh`](../scripts/tui-load.sh) at 60 Hz, because ScreenCaptureKit is **change-driven**: with still panes the same take delivered **26 frames in 38 s (0.68 fps)** while the container could still be muxed at 60, which would have made "1080p60" true of the file and false of the pixels. With the panes repainting it delivers **41.7 fps**, and the caption states that number beside the container's. The inline WebP is built from a **still-pane** take (`CC_PANES_STATIC=1`) because that same 60 Hz churn is close to incompressible — the animated WebP of the moving take came out **38 MB**, against **167 KB** for the still one, whose 144 sampled frames the encoder merges into **11** stored frames with no loss of anything the image exists to show: the pane moves are discrete state changes, not motion.

**Rebuilding the banner.** It is generated, never hand-drawn: `python3 tools/banner/gen.py --out assets/banner`. The generator refuses to emit rather than ship a subtly wrong asset — periods that do not divide the master loop, a loop whose first and last frame differ, a stride that drifts out of lock with the ground it walks on. Verify one with `scripts/banner-verify.sh <asset> --period <P>` (six checks, all able to fail; the hero loop is `--period 240`), and prove every beat is actually VISIBLE with `scripts/banner-beat-ink.py assets/banner/v6*.svg` — it renders each beat whole and again with that beat suppressed, and requires a real pixel difference at the README's own 838 px width. That gate exists because every other one is structural: a meteor trail once shipped painting **zero pixels** — a horizontal path's bounding box has no height, so the gradient filling it was never drawn — and the markup parsed, the animation was singular and the loop still sealed shut. Sabotage every gate at once with `scripts/banner-gate-redproof.py` (41 cases *(corrected 2026-09-24)*, each required to fire on its own message). **The animated SVG is the deliverable, not a fallback** — GitHub serves it through camo as an image, and CSS animations inside an SVG loaded as an image do run, which is why the inline asset is vector.

