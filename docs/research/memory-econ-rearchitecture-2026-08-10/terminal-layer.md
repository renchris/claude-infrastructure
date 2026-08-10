# Axis H — Terminal layer: kitty / iTerm2 / Hammerspoon memory economics

Measured 2026-08-10 07:30–08:05Z on the live fleet. kitty pid 600, uptime 20h11m at first read.
All numbers are live reads; prior-art numbers are cited to file:line. **Read-only** — no pane,
config, or terminal was modified. Builds on (does not re-run) `terminal-for-30-panes-2026-07-31.md`
and `machine-lag-and-kitty-2026-08-06.md`.

---

## 0. Headline

**The terminal layer's own footprint is ~3.6 GB (5.6% of 64 GB) — but its largest memory cost is the
~6.2 GB it PREVENTS from being freed.** A fail-closed pane-close guard has refused 73 closes since
2026-08-07, 100% of them on the `UNKNOWN` arm and 0% on the `NON-EMPTY` arm it exists to protect.
Each refusal strands a pane holding a ~600–900 MB Claude Code process, and nothing retries.

Second: **the wave's own census figure for kitty is wrong by 8.6×.** `ps` RSS reads 220 MB;
`phys_footprint` reads 1895 MB. This repo already recorded that correction
(`machine-lag-and-kitty-2026-08-06.md:263-280`) and the decomposition repeated the error anyway.

---

## 1. Live census (brief question a)

`kitten @ ls --to unix:/tmp/kitty-600` (remote control is enabled: `allow_remote_control socket-only`,
`listen_on unix:/tmp/kitty-{kitty_pid}` — `config/kitty.conf:58,76`).

| Unit | Count |
|---|---|
| kitty processes | 1 (pid 600) + 2 `kitten` helpers (`__atexit__` 21 MB, `__watch_conf__` 22 MB) |
| OS windows | **4** (ids 2, 3, 5, 6) |
| tabs | **4** (exactly 1 per OS window — no tab consolidation in use) |
| panes (kitty "windows") | **31** (7 · 3 · 6 · 15) |
| displays driven | 4 — 1× XDR 3456×2234 + **3× DELL S2725QC 5120×2880** |

Foreground-process histogram across the 31 panes: 15 `claude`, 15 `claude.exe` (subagents),
15 `bash`/`tee`/`zsh` wrappers, 5 `chrome-devtools-mcp`, 28 `caffeinate`, 1 `expect`.

**Memory, three instruments, same process, same second:**

| Instrument | Reading | Verdict |
|---|---|---|
| `ps -o rss= -p 600` | **220 MB** | **wrong — misses GPU backing store** |
| `top -l 2 -stats mem` | 1895 MB | correct (this is what `terminal-bench.sh:195` reads) |
| `footprint -p 600` → `phys_footprint` | **1895 MB** (peak 1997 MB) | authoritative |

`footprint` decomposition:

```
1350 MB    24 regions   IOSurface            ← 71% of the total
 158 MB   179 regions   IOAccelerator (graphics)
 134 MB                 Owned physical footprint (unmapped)
 123 MB                 untagged (VM_ALLOCATE)
 112 MB                 MALLOC_{MEDIUM,SMALL,TINY,NANO}
```

**1508 MB of 1895 MB (80%) is GPU backing store.** Of the IOSurface, 225 MB is compressed/swapped
(`vmmap -summary`: VIRT 1.3G / RSDNT 1.3G / DIRTY 1.1G / SWAPPED 225.0M), so effective RAM is
~1.67 GB, not 1.9.

**Implied RSS-per-pane is a meaningless quantity here** — see §2. The honest per-unit figure is
**~338 MB per OS WINDOW**.

---

## 2. The IOSurface model — validated, predictive (brief question b, part 1)

Every large IOSurface region is **exactly 56.2 MiB**, and `5120 × 2880 × 4 B = 56.25 MiB` — one full
5K framebuffer. `vmmap 600 | grep '^IOSurface'` size histogram: **24 × 56.2M** + 2 × 4800K
(`1280x960 (BGRA) IOGPUSurfaceMTL`) + 3 × 16K. `24 × 56.25 = 1350 MB` — an exact match to
`footprint`'s IOSurface line.

Cross-validated against the only other footprint read on record
(`machine-lag-and-kitty-2026-08-06.md:269-274`, pid 567):

| Date | pid | OS windows | panes | IOSurface | **MB per OS window** |
|---|---|---|---|---|---|
| 2026-08-06 | 567 | 3 | 15 | 1069 MB | **356** |
| 2026-08-10 | 600 | 4 | 31 | 1350 MB | **338** |

**The two agree within 5%, across 4 days, different pids, different window counts, and a 2× change
in pane count.** This is instrument-independent (it needs no assumption about region decomposition)
and it is the axis's most reusable result:

> **kitty costs ≈ 340 MB of IOSurface per OS WINDOW on a 5K display. Panes are ~free. Tabs are
> ~free** (only the active tab of an OS window renders — `config/kitty.conf:427`).

---

## 3. `scrollback_lines` is NOT a lever, and the config's stated reason for keeping it is FALSE

**Finding:** `config/kitty.conf:401-404` calls `scrollback_lines` "the one memory knob that scales
with pane count" and justifies 2000 with "overflow spills to a disk-backed pager instead of RAM."
Both halves are wrong.

**Evidence:**
- **Magnitude.** Σ(2000 lines × pane width) over all 31 panes = 2,528,000 cells. At a *generous*
  20 B/cell that is **48 MB — 2.5% of kitty's 1895 MB**. At 8 B/cell, 19 MB. (Panes are narrow —
  28–76 columns — because the splits layout subdivides; narrow panes make scrollback cheaper still.)
- **Direction.** Non-GPU residual (`footprint − IOSurface − IOAccelerator`) **FELL** 416 MB → 387 MB
  while pane count **rose** 15 → 31. Pane count is not driving the non-GPU term.
- **The pager claim.** `scrollback_pager_history_size` is **0**, and kitty's own man page states
  *"A value of zero or less disables this feature."* Nothing spills anywhere — overflow past 2000
  lines is **discarded**. The kitty docs do not state a backing store for that buffer at all, so the
  word "disk-backed" is unsourced as well as inapplicable.

**Consequence for the operator:** you have exactly 2000 lines/pane of history and no more. For a
chatty agent pane that is minutes. This is a *capability* gap, not a memory problem.

**Worst case per chatty agent pane (asked for in the brief):** at the widest pane on this box
(76 cols) and 20 B/cell, 2000 lines = **3.0 MB**. Raising to 10000 lines costs **≈15 MB/pane**, or
~100–250 MB across 31 panes. That is real but an order of magnitude below one OS window.

---

## 4. §6.1 — the multi-hour drift item (brief question c)

**What the doc says.** `terminal-for-30-panes-2026-07-31.md:479-491`: item 1 is 🔴 OPEN and *"moved
backwards"* — no multi-hour run of any challenger exists; the 12 h `kadv` evidence died in the 11:46
reboot; the longest reads since are 6 min (Ghostty) and a 3-point read on kitty, both explicitly
*"too short for a leak verdict"*. `:488-491` retires the "~23.7 MB/pane at 48 panes" figure as
**permanently unfalsifiable — must not be cited.** `:493-522` documents a 30-min attempt that failed
its *precondition*: the layout moved (census 36→19) and `verdict=OK` **does not certify layout
stability**. `:524-536` records that the gate is now BUILT (`--watch`, `verdict=LAYOUT-DRIFT`, exit 4,
no drift row emitted).

**What I measured.** The precondition the doc says was never met was available today: kitty pid 600
had **20h11m uptime**. Three independent lines of evidence, none leak-shaped:

1. **Within-instance, retrospective.** `phys_footprint 1895 MB` vs `phys_footprint_peak 1997 MB` at
   20 h uptime. Current sits at **95% of peak — kitty gave back 102 MB.** A monotonic leak sits *at*
   its peak; this one does not.
2. **Cross-instance, 4 days apart.** Per-OS-window IOSurface constant within 5% (§2). The
   1069 → 1350 MB growth is **fully explained by 3 → 4 OS windows**, not by time or pane churn.
3. **Live 1800 s constant-layout run.** `scripts/terminal-bench.sh --app kitty --interval 1800
   --watch 30`, fired 07:32:30Z. T0: `mem=1901MB th=13 ports=523 win=33 off=27`,
   `gpu_frames=285 cpu_frames=14 ratio=20.36:1`, precondition baseline `onscreen=6 offscreen=27`.
   **→ see §11 for the verdict** (run completes 08:02:30Z).

**Verdict on the memory axis: NOT leak-shaped.** The item's remaining open half is *ports/threads*,
where kitty already measured `+5 ports` against iTerm2's `+76/hr` (`:514`, `:519`).

**Restart cadence recommendation: none warranted on memory grounds.** A restart kills every pane and
every Claude Code session in it (`config/kitty.conf:13-15`), which is a far larger cost than the
102 MB below peak that a restart would reclaim. If a cadence is ever wanted, tie it to *display
reconfiguration* (which is what changes IOSurface), not to elapsed time.

---

## 5. The real terminal-layer memory sink: panes that cannot be closed

**Finding:** `bin/it2-kitty:852` exits **rc 67** rather than close a pane whose composer state is
not provably empty. Since 2026-08-07 it has fired 73 times, and **every single one was the
`UNKNOWN` arm — never once the `NON-EMPTY` arm the guard exists to protect.**

**Evidence** (`~/.claude/logs/teammate-lifecycle.log`, 24,002 lines):

```
grep -o "composer state is [A-Z-]*" | sort | uniq -c
     73 composer state is UNKNOWN
      0 composer state is NON-EMPTY
```
| Outcome | Count |
|---|---|
| `✓ closed pane` | **885** |
| `✗ pane close FAILED` | **94** (9.6%) |
| …of which `rc=67` | **73** (7.5%) |

First 2026-08-07 06:48:58 (`416 cut-compa…`), latest **2026-08-10 00:42:06 — `110 (r-adversary)`,
a sibling worker of THIS research wave, refused while this report was being written.**

### 5.1 ROOT CAUSE — traced to the line, with the live refusal's own snapshot

`bin/it2-kitty:601` is the whole decision:

```python
print("AGENT-PANE" if (alt and agent_pane) else ("UNKNOWN" if alt else "NO-TUI"))
```

`agent_pane` (`:599`) requires **`len(rules) == 1`**, where `rules` are lines containing ≥20 `─`
box-drawing glyphs — i.e. the Claude Code composer's own frame. The pass-list at `:832` is
`EMPTY|NO-TUI|AGENT-PANE`, so an agent pane is closable **only while it is drawing exactly one
footer rule.**

**A FINISHED agent pane draws no rules at all.** The guard preserved the proof itself. Window 110
(`r-adversary`), snapshot `~/.claude/logs/composer-snapshots/20260810T074206Z-win110.txt`, all
**86 bytes** of it:

```
(blank)
✻ Worked for 10m 40s
  ✘ Auto-update failed · Try claude doctor or npm i -g …
(blank)
```

Zero `─` rules ⇒ `len(rules)==1` is False ⇒ `agent_pane` False ⇒ `alt` True ⇒ **`UNKNOWN` ⇒ refuse.**
There was no composer on that screen to protect.

**This generalises across the entire refusal population** (276 snapshots in
`~/.claude/logs/composer-snapshots/`):

| Rules (`─` ≥20) in snapshot | Snapshots | Can reach `AGENT-PANE`? |
|---|---|---|
| **0** | **212 (77%)** | **No — structurally impossible** |
| 1 | 63 (23%) | yes, if the footer label matches |
| 2 | 1 | no |

- **Median snapshot size is 0 bytes** — over half the refusals are on an *empty* `get-text`, which
  hits a second forced-`UNKNOWN` arm at `composer_state()`'s `[ -n "$txt" ] || printf 'UNKNOWN'`
  ("a blank read proves nothing").
- **Only 19 of 276 (6.9%) contain a `❯` composer prompt at all.** 55 carry the finished-summary
  signature (`Worked for` / `Auto-update`).

**So the guard is refusing to close panes that demonstrably hold no composer, 93% of the time.**
This is the repo's own recorded failure shape — MEMORY.md *"Abstain rule retires the common case"*
(3 states: green · red · **INAPPLICABLE**) and *"Abstain goes on the branch the case reaches"* — the
mild branch is the live one.

**Hypothesis I raised and REFUTED:** I first suspected the 1-row (28×1) panes of §12 were starving
`get-text`. Window 110's snapshot carries a 56-character line, so it is not width-truncated. Pane
geometry is not the cause; the **finished-agent render** is.

### 5.2 The fix, stated so it cannot weaken the guard

The composer is *always* drawn inside a box — `composer_state()` itself assumes this
(`body = lines[rules[-2]+1 : rules[-1]]`). Therefore:

> **Zero `─` rules ⇒ there is no composer box on screen ⇒ there is no unsent text to destroy.**

Add `ZERO-RULES` (or fold into `NO-TUI`) as a **fourth passing state**. This touches neither the
`NON-EMPTY` arm nor the ≥2-rule modal-occlusion arm (`:599` comment: *"A modal-occluded pane draws
its own box borders (≥2 rules) and so can never reach here"*), so the 2026-08-07 incident that
motivated the guard stays covered. It converts **212 of 276** refusals into closes.

Second, smaller: an empty `get-text` on a pane whose agent process has **exited** is not "unknown",
it is "gone" — pair the blank read with a liveness check on the pane's foreground process before
abstaining.

**Nothing retries.** No reaper in `scripts/` or `bin/` greps for 67 (`cc-reaper`, `cc-teardown`,
`team-orphan-reaper.sh`, `reap-guard.sh` all checked). The refusal is terminal.

**Cost, measured not modelled:** backlog `4caa5e0beab6` (still `blocked`) —
*"Close the 10 finished agent panes from session-e5d3628d … refused by it2-kitty rc=67; they hold
~6.2GB RSS and 10 kitty windows. Agents are classifier-blocked from closing panes."*

**6.2 GB of stranded panes exceeds the entire terminal layer's own 3.6 GB footprint**, and at 10
extra OS windows it also adds ~3.4 GB of IOSurface by §2's model.

---

## 6. iTerm2 duplication (brief question d)

**iTerm2 is NOT resident. The RAM cost of keeping both is zero.**
- `pgrep -lx iTerm2` → nothing. Not in login items (`Hammerspoon, Dia, BetterDisplay, VoiceInk,
  Wispr Flow, FigmaAgent, …` — no iTerm).
- Disk: **134 MB** (`/Applications/iTerm.app`, last modified 2026-07-11).
- The resurrection path is closed: `scripts/boot-resume-launch.sh:282` — *"NEVER `open -a iTerm`
  (removed 2026-08-07)"* — after `bin/cc-kitty-socket:8` recorded the incident (*"observed
  2026-08-07 03:51:18, iTerm2 RESURRECTED behind a kitty-fleet operator (153 kitty panes) and 6
  sessions fired into it"*). Guarded by `tests/{cc-kitty-socket,kitty-divert-real-it2,
  boot-resume-launch}.bats`.

**What remains iTerm2-shaped — and it is not memory.** 11 files still reference `iTerm.app` /
`it2py` / `ITERM_SRC_APP`: `bin/{it2-kitty,cc-in-kitty}`, `scripts/{iterm-metal-bench-app,
boot-resume-launch,kitty-setup,handoff-fire,render-census,pane-spawn-coverage-lint}.sh`,
`scripts/lib/cc-type-verified.sh`, `scripts/limit-recover/{lr-handoff,lr-reset-poller}.sh`. Most are
compatibility shims (`bin/it2-kitty` deliberately *speaks* it2 so Claude Code's `ITermBackend` builds
kitty panes — `bin/it2-kitty:4-8`). Two costs are live:

1. **`it2py` is ABSENT on this box** (confirmed; matches `pane-theft-composer-guard.md:194`). So the
   composer guard of §5 is **kitty-only and unverified for iTerm2** — there is no fallback reader.
2. **A pending activation gates autonomous dispatch.**
   `docs/activation/pending-activation/32-cc-roles-kitty-normalise-activate.sh:18-24` —
   *"while these files hold UUIDs, EVERY HEADLESS FIRE IS HELD. Autonomous dispatch is fail-closed
   until this script runs."* Backlog `b0a237b76793` is `blocked` on running it. **Current state is a
   THIRD one the script does not name:** `~/.claude/cc-roles/` now holds only `archive` and
   `orchestrator`, and `orchestrator` is **empty** — neither the iTerm2-UUID case the script fixes
   nor the clean integer-id case. Whether an empty file reads as "absent" or as "broken invariant"
   at `it2py anchor` is **unverified and is the one thing I could not settle read-only.**

**Recommendation: keep iTerm2 installed** (134 MB disk, 0 RAM; `scripts/iterm-metal-bench-app.sh` is
the only counterfactual instrument for the bake-off, and re-acquiring it is expensive). **Do not**
spend effort removing it. Spend it on the empty-`orchestrator` question instead.

---

## 7. Hammerspoon (brief question e) — the brief's premise is wrong

**Finding: Hammerspoon has ZERO role in the pane machinery, and zero dependencies in this repo — but
it IS the image-paste path into Claude Code, so it is not removable either.**

**Evidence:**
- `grep -rlE 'hammerspoon|hs\.ipc|hs -c' bin/ scripts/ hooks/ config/` → **no matches.** Nothing in
  claude-infrastructure calls it.
- Coupling is via macOS event taps, not code: `~/.hammerspoon/init.lua:211-231` —
  *"Smart paste: Cmd+V → Ctrl+V for images in terminal apps (for Claude Code)"* — plus a
  `~/Screenshots` pathwatcher → auto-copy-to-clipboard → thumbnail pipeline (`:242-518`).
- `init.lua:31-44` records that this table was name-keyed and **silently missed kitty** until
  2026-07-31 (bundle-id keyed now). So the coupling is real, load-bearing, and already bitten once.
- Cost: **115 MB RSS**, a login item, plus one **global `keyDown` eventtap** (`:214`), two
  pathwatchers, an application watcher and a caffeinate watcher.

**Recommendation: keep.** 115 MB buys the screenshot→Claude paste path, which has no substitute here.
Flag only that it is an *undeclared* dependency — nothing in the repo would tell a successor that
removing Hammerspoon breaks image paste into Claude Code.

---

## 8. Per-pane shell overhead + orphaned `gitstatusd`

| Term | Measured |
|---|---|
| Direct children of kitty(600) | **36 procs, 228 MB RSS** |
| `/bin/zsh -l` login shells | 14, 50 MB |
| `gitstatusd-darwin-arm64` | 12 procs, **60 MB** |
| …**orphaned (`ppid=1`)** | **10 procs, 41 MB**, ages 35 min → **7 h 55 m** |
| `caffeinate` | 33 procs (~3.5 KB each — negligible RAM, real process-table pressure) |

Prior art exonerated `gitstatusd` on **CPU and count** (`docs/plans/MACHINE_CAPACITY_V2.md:157`
*"39 procs, 0.09 GB, ~0% CPU"*; `:252` "would remove crash recovery to fix a non-problem"). **Neither
prior reading measured ORPHANING.** 10 of 12 have `ppid=1` — their pane is gone and the daemon
outlived it. Small in absolute terms (41 MB) but monotone in pane churn, and structurally the same
defect as §5: no component owns its own teardown.

---

## 9. Findings in the wave's 6-line row format

```
Finding: ps RSS understates kitty 8.6x, and this wave's census inherited the error
Evidence: ps 220MB vs footprint phys_footprint 1895MB (peak 1997MB), same pid 600, same second;
          80% is IOSurface+IOAccelerator, invisible to ps. Correction already on record at
          docs/research/machine-lag-and-kitty-2026-08-06.md:263-280 ("ps RSS undercounts kitty ~6x")
Cost now: the decomposition's "kitty x1 = 157MB" understates by 1.7GB; every GPU-backed app in the
          fleet census is understated the same way (WindowServer top MEM 1523MB vs ps 169MB)
Re-architecture: census with `footprint`/`top -stats mem` for GPU-backed apps; ps only for CLI procs
Sizing: corrects ~3.2GB of fleet accounting - effort S (instrument swap) - risk none
Existing mechanism: scripts/terminal-bench.sh:195 ALREADY reads top -stats mem correctly - reuse it
```
```
Finding: kitty's memory is per-OS-WINDOW, not per-pane; ~340MB each on a 5K display
Evidence: 24 IOSurface regions x exactly 56.2MiB (= 5120x2880x4B) = 1350MB, matching footprint
          exactly. Cross-validated: 1069MB/3 windows = 356MB (2026-08-06 pid 567) vs 1350MB/4 =
          338MB (today) - agree within 5% across a 2x change in pane count
Cost now: 4 OS windows = 1350MB IOSurface + a WindowServer composite client each (WS 1523MB)
Re-architecture: prefer TABS over new OS windows (only the active tab renders,
          config/kitty.conf:427); retire any OS window not owning its own display
Sizing: -338MB kitty +WindowServer share per window retired - effort S (layout, no config edit)
          - risk low, but NOT free: the operator drives 4 displays, so 4->1 costs 3 displays
Existing mechanism: already filed as machine-lag-and-kitty-2026-08-06.md:551 recommendation #11
```
```
Finding: the fail-closed pane-close guard strands ~7.5% of agent panes, and its protective arm has
         NEVER fired
Evidence: ~/.claude/logs/teammate-lifecycle.log - 73 rc=67 refusals since 2026-08-07, 100%
          "composer state is UNKNOWN", 0% "NON-EMPTY"; 885 successful closes vs 94 failures.
          bin/it2-kitty:852. Nothing retries (no reaper greps 67). Live case 2026-08-10 00:42:06,
          window 110 (r-adversary) - a worker of THIS wave
Cost now: backlog 4caa5e0beab6 measured 10 concurrent stranded panes = 6.2GB RSS + 10 OS windows
          (=+3.4GB IOSurface by the model above). Larger than the whole terminal layer's footprint
Re-architecture: ROOT CAUSE at bin/it2-kitty:599-601 - AGENT-PANE requires len(rules)==1, but a
          FINISHED agent pane draws ZERO composer rules, so it can never match. Add ZERO-RULES as a
          4th passing state: no box => no composer => nothing to protect. Touches neither the
          NON-EMPTY arm nor the >=2-rule modal-occlusion arm, so the 2026-08-07 incident stays covered
Sizing: converts 212 of 276 refusals into closes, recovers ~6.2GB - effort S (one branch)
          - risk LOW once scoped to zero-rules (do NOT weaken the NON-EMPTY arm)
Existing mechanism: bin/it2-kitty + docs/research/pane-theft-composer-guard.md - EXTEND the state
          machine, do not add a second closer
```
```
Finding: scrollback_lines is not a memory lever here, and the config's stated reason is false
Evidence: all 31 panes' scrollback = 2,528,000 cells = 48MB at a generous 20B/cell (2.5% of
          footprint). Non-GPU residual FELL 416MB->387MB as panes rose 15->31. And
          scrollback_pager_history_size is 0, which kitty's man page defines as "disables this
          feature" - so config/kitty.conf:402-403's "overflow spills to a disk-backed pager instead
          of RAM" is false in both halves; overflow is DISCARDED
Cost now: 0 MB of waste; the real cost is a false rationale that will misdirect the next reader
Re-architecture: correct the comment; KEEP scrollback_lines 2000 (lowering it saves ~nothing and
          costs history). Optionally raise to 5000 (~+45MB) now that the cost is known
Sizing: 0MB recovered - effort XS (comment) - risk none. Value is preventing a wrong future edit
Existing mechanism: config/kitty.conf:398-404 - edit in place
```
```
Finding: 10 orphaned gitstatusd daemons outlive their panes, up to 7h55m
Evidence: 12 gitstatusd procs / 60MB, 10 with ppid=1 / 41MB. Prior art exonerated gitstatusd on CPU
          and count (docs/plans/MACHINE_CAPACITY_V2.md:157,252) but never measured orphaning
Cost now: 41MB, monotone in pane churn
Re-architecture: reap ppid==1 gitstatusd with no live pane at pane-death, alongside the pane reaper
Sizing: recovers ~41MB and stops the growth - effort S - risk low (p10k respawns it on demand)
Existing mechanism: bin/cc-teardown:524 already ENUMERATES gitstatusd* in its skip list - it knows
          about these processes and deliberately ignores them; extend that arm
```
```
Finding: the half-finished iTerm2->kitty migration costs 0 RAM but gates autonomous dispatch
Evidence: iTerm2 not resident, not a login item, 134MB disk. But
          docs/activation/pending-activation/32-cc-roles-kitty-normalise-activate.sh:18-24 -
          "EVERY HEADLESS FIRE IS HELD. Autonomous dispatch is fail-closed until this script runs"
          (backlog b0a237b76793, blocked). ~/.claude/cc-roles/ now holds only an EMPTY
          `orchestrator` - a third state the script does not handle
Cost now: 0 MB; unknown dispatch availability
Re-architecture: run the activation, or verify that an empty role file reads as absent (not as a
          broken invariant) at `it2py anchor`
Sizing: 0MB - effort XS - risk low. NOT a memory item; surfaced because it was found on this axis
Existing mechanism: the activation script exists and is written; it needs running, not building
```

---

## 10. Config recommendations — exact `kitty.conf` lines

Applied to `config/kitty.conf` (SSOT; symlinked to `~/.config/kitty/kitty.conf`).

| # | Line | Change | MB |
|---|---|---|---|
| 1 | `scrollback_lines 2000` | **KEEP.** Do not lower. | 0 (lowering saves <20 MB) |
| 2 | `config/kitty.conf:401-404` comment | **REWRITE** — see below; both claims are false | 0 (prevents a wrong edit) |
| 3 | `scrollback_pager_history_size` | **OPTIONALLY ADD** `scrollback_pager_history_size 64` if real history is wanted (~640k lines by kitty's own 10k-lines/MB figure). Currently disabled. | +64 MB max, per new window |
| 4 | `background_opacity 1.0` | **ALREADY OPTIMAL, do not change** — any value <1.0 adds a compositing pass and more surfaces | would cost, not save |
| 5 | `background_blur 0` | **ALREADY OPTIMAL, do not change** — same reason | would cost, not save |
| 6 | `repaint_delay 16` / `input_delay 5` | **KEEP** — CPU/compositor levers, correctly set (`:406-421`); not memory | 0 |
| 7 | `confirm_os_window_close -1` | **KEEP** — `:439-449` records why `2` was wrong | 0 |

**There is no kitty.conf line that reduces IOSurface.** The 1350 MB is a function of
`OS windows × display area`, and kitty exposes no knob for it. **The only lever is layout**, and it
is worth more than every config line above combined:

```
retire 1 OS window  →  −338 MB kitty IOSurface  +  1 fewer WindowServer composite client
4 OS windows → 2    →  −676 MB
4 OS windows → 1    →  −1014 MB   (but costs 3 of 4 displays for terminal work)
```

Prefer **new tabs over new OS windows** in every spawn path (`⌘T` semantics, not `⌘N`) — only the
active tab of an OS window renders (`config/kitty.conf:427`), so tabs are ~free where windows are
340 MB each.

---

## 11. Live leak-run result (§6.1 closure attempt)

`scripts/terminal-bench.sh --app kitty --interval 1800 --watch 30`, T0 2026-08-10T07:32:30Z,
kitty pid 600 at 20h11m uptime — the multi-hour constant-layout precondition
`terminal-for-30-panes-2026-07-31.md:479-522` says has never been met.

```
T0  app   cpu=15.0 mem=1901MB th=13 ports=523 win=33 off=27 mpx=11.40
T0  WS    cpu=20.5 mem=1523MB th=25 ports=3955 win=17 off=12 mpx=13.05
GPU path taken: gpu_frames=285 cpu_frames=14  ratio=20.36:1
precondition baseline: onscreen=6 offscreen=27  (polling every 30s)
```

**RESULT — `verdict=LAYOUT-DRIFT`, exit 4, aborted at t+1410s (23.5 min):**

```
⛔ CONSTANT-LAYOUT PRECONDITION BROKE — t+1410s: onscreen 6→8, offscreen 27→25
   Ports move WITH windows, so this window's mem/ports delta cannot be split into
   leaked-versus-released. No drift row is emitted. Re-run when nothing opens or closes.
verdict=LAYOUT-DRIFT
```

**Three things this establishes.**

1. **The gate works.** Built 2026-07-31 (`terminal-for-30-panes-2026-07-31.md:524-536`), this is its
   first firing on a real attempt. It detected the breach, **emitted no drift row**, and exited 4 —
   exactly the behaviour designed to prevent a second confounded row being filed as a clean bound.
   The instrument is sound; do not "fix" it.
2. **23.5 minutes is the longest UNCONFOUNDED constant-layout hold on record for kitty.** Prior best
   was 6 min (Ghostty) and a 3-point kitty read; the 30-min 22:17Z run was confounded from the start
   (census fell 36→19 under it).
3. **§6.1's own predicted obstacle is now confirmed empirically, and it is structural.** `:520`
   said *"the obstacle is not instrument time, it is finding a half-hour on a shared box when no
   session opens a pane."* Two windows opened at t+1410s. **On a fleet with autonomous dispatch, a
   30-minute pane-quiet window does not reliably exist** — so §6.1 as specified may be unclosable
   here by repetition. It needs re-specification, not another attempt.

**Recommendation — retire the precondition, don't keep waiting for it.** Replace *constant layout*
with a **layout-NORMALISED** metric, which §2 supplies: `IOSurface_MB / OS_window_count` was 356
(2026-08-06) and 338 (2026-08-10) — stable within 5% across a window-count change, so it divides the
confounder out instead of aborting on it. A drift instrument reading normalised MB/window (plus
ports/window) can run continuously on a live fleet and never needs a quiet half-hour. That converts
§6.1 from "wait for a condition the fleet destroys" into a measurement that is always available.

The three independent lines of evidence in §4 stand regardless — none of them depend on this run.

---

## 12. Adversarial self-pass

**"What did I assume was irrelevant?"** — three gaps found and investigated:

1. **I hypothesised the §6.1 instrument was blind to 71% of kitty's memory** (reasoning that
   `terminal-bench.sh:195` reads `top`, and `ps` misses IOSurface). **REFUTED by measurement:**
   `top -l 2 -stats mem` returns 1895M, matching `footprint` exactly. `top`'s MEM is
   phys_footprint, not RSS. The instrument is sound; only `ps` is wrong. Recorded because the
   plausible-and-false version would have discredited a working instrument.
2. **Is the terminal layer even material?** Honest ranking: kitty 1.9 GB + WindowServer 1.5 GB +
   Hammerspoon 0.12 + kittens 0.04 + per-pane shells 0.11 ≈ **3.6 GB = 5.6% of 64 GB**, against
   `claude ×14 = 8.7 GB`. **The terminal layer is NOT the ceiling**, and the 2026-07-30 freeze
   root-caused to WindowServer *CPU* saturation, not RAM (`iterm2-freeze-30-sessions-2026-07-30.md`).
   The one terminal-layer item that IS ceiling-relevant is §5's stranded panes (6.2 GB), because
   that is Claude Code memory the terminal is holding hostage — not terminal memory.
3. **Is `ps` under- or over-counting?** Both, in opposite directions, and I nearly reported only one.
   Backlog `2029c52b8a32` establishes `ps rss` is *"the banned 2.34x shared-page overcount"* when
   **summed across the fleet**; §1 shows it **under**-counts a single GPU app by 8.6×. Any fleet
   census must not use `ps` for either purpose.

**Not established / blockers:**
- The `6 framebuffers per OS window` decomposition is inferred; the robust claim is the
  instrument-independent **340 MB/window**, which does not depend on it.
- Whether an **empty** `~/.claude/cc-roles/orchestrator` reads as absent or as a broken invariant at
  `it2py anchor` — unresolvable read-only, and it gates autonomous dispatch (§6).
- `footprint -p 371` (WindowServer) needs root; WindowServer's 1523 MB is `top -stats mem`, so its
  IOSurface share is unmeasured. The per-window saving in §10 counts only kitty's side and is
  therefore a **lower bound**.
- The 08-06 comparison is 2 points, not a series. §4's conclusion is "not leak-shaped", not
  "leak-free".
- **Ops, outside this axis but observed:** 8 of the 31 panes are **28×1 — a single text row**
  (kitty ids 101–108, this wave's own workers). kitty's splits have no minimum-size floor. Not a
  memory cost (narrow panes are cheaper), but a rendering surface that small will degrade any TUI
  running in it.

---

## 13. CROSS-AXIS FLAG — not my axis, but it is the largest process on the box

Found while ranking the terminal layer against the fleet. **Surfacing because at 8.5 GB it dwarfs
every number above, and no axis in the decomposition names it.**

```
ugrep pid=68889 rss=8.28 GB etime=03:23
ugrep pid=68889 rss=8.43 GB etime=03:25     ← +35 MB/s, monotonic
ugrep pid=68889 rss=8.56 GB etime=03:27
```

Full argv:
`ugrep -G --ignore-files --hidden -I --exclude-dir=.git … -oE .{0,150}(C…`

- **This is a Bash-tool `grep`.** MEMORY.md already records *"Bash tool shell is zsh … `grep` is
  ugrep"* — the interactive `grep` on this box resolves to `ugrep`, not `/usr/bin/grep`.
- `-oE` with a `.{0,150}` context window **materialises every match plus 150 chars of context in
  memory**. Over a tree this large that is unbounded by construction.
- **Ranking, `ps` RSS:** ugrep **6.4–8.6 GB** > `next-server` 1.7 GB > `node` 1.6 GB >
  `chrome-devtools-mcp` 1.5 GB > the largest `claude` session 0.99 GB. It is #1 on the box.
- **Probable multiplier — ties to axis D:** `--hidden` with only VCS dirs excluded, over a tree
  holding **553 worktree directories**, greps each worktree's full checkout separately.
- **Caveat, stated because I could not close it:** `footprint -p 68889` returned a *different*
  process (`claude.exe`), so the 8.5 GB is a `ps` RSS reading only and I could not corroborate it
  with `phys_footprint`. Given §1 shows `ps` **under**-counts GPU-backed apps and backlog
  `2029c52b8a32` shows it **over**-counts shared pages when summed, a single-process RSS this large
  is very likely real but is **one instrument, not two**. It is monotonically growing across three
  reads 2 s apart, which no shared-page artifact would do.

**Recommended owner:** `blindspots` or `bottleneck-refute`. Cheap mitigations if it confirms: bound
agent greps with `--max-count`/`--max-files`, drop `-o` for counting passes, or scope the search root
away from `~/Development/.worktrees`.
