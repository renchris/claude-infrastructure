# R6 — graveyard scan: prior art on "make a terminal pane visually say it is idle / waiting"

Read-only. Nothing modified, nothing closed. Every claim below names a file:line, a command, or a
live measurement taken this session (2026-09-13).

---

## 0. HEADLINE

**There is no prior implementation and no prior refutation of "tint/colour a pane to show idle".
There IS a measured prior DESIGN of the same problem, one level up, plus three independent
measurements that kill the three most obvious mechanisms.** The design is
`docs/research/oversight-at-scale-2026-08-19/O2-operator-attention.md` §2.7 + §4/C3. It was never
filed as a backlog row, so this work would be its first actuation.

The three killed mechanisms (each measured by someone else, for another reason):

| Mechanism | Verdict | Where it was killed |
|---|---|---|
| Set the pane TITLE to say "idle" | 🚨 **REFUTED — destroys an existing signal** | `docs/research/lr100p-2026-09-09/q-survivability-spawn.md:38-41, 277-280` |
| Dim / alpha the idle (or non-idle) panes | ❌ **REJECTED on a standing operator rule** | `config/kitty.conf:751-753` + memory `feedback-tui-visibility-numbers-first` |
| Print a banner into the pane while CC runs | ❌ **structurally impossible** | `docs/research/R6-observability.md` §1 (alt-screen), and the one shipped painter refuses exactly this |

---

## 1. THE PAINT PRECEDENT — how `lead-crash-watchdog.sh` touches another pane

**Mechanism: an ordinary `write(2)` to the pane's tty by PATH — no kitty socket, no terminal API,
no iTerm2 cookie.** `hooks/lead-crash-watchdog.sh:1263-1287`, header at `:1119-1156`.

```sh
# hooks/lead-crash-watchdog.sh:1279
if { printf '\n%s\n' "$block"; printf '\033]2;%s\007' "$title"; } > "$PANE_VERDICT_DEV/$tty" 2>/dev/null
```

- `$tty` is captured **at registration**, not at death: `LEAD_TTY="${CC_PANE_VERDICT_TTY:-$(ps -o tty= -p "$LEAD_PID")}"`, shape-gated to `ttys[0-9]*` (`:1382-1383`). Nothing can re-derive it after the death.
- Two payloads in one write: a **text block** and an **OSC-2 window-title** escape (`\033]2;…\007`).
- Rationale, verbatim from `:1129-1133`: *"The pane's tty is a character device this daemon can write by path (`crw--w---- chrisren tty`) … so the launchd-context blindness that let cc-reaper kill a session but never close its pane cannot reach a `write(2)` to `/dev/ttysNNN`. Writing to the OUTPUT side of a tty types nothing into the shell."*
- Second BEL emitter in the same file: `:1695` `printf '\a' >/dev/tty` — **the only `\a` in `hooks/ bin/ scripts/`** (verified this session).

### 🚨 The precedent does NOT extend to a live session — and it says so itself

`paint_pane_verdict` **refuses to write** unless the tty has settled to a **bare shell prompt**
(`pane_verdict_settle`, `:1185-1201`; `pane_procs_are_shells`, `:1181-1184`). Four outcomes:

| state | action |
|---|---|
| `closed` | not painted |
| `relaunched` (a claude took the tty) | **not painted** — `:1271` |
| `unknown` (something running) | **not painted** — `:1272` *"refusing to write over it"* |
| `shell` | painted |

So the shipped rail paints **only over a dead session's leftover prompt**. Writing into a *live*
CC pane's tty lands in the alternate screen buffer and is erased on the next TUI frame (see §4).
**Any idle-indicator design must either (a) use the OSC-2 title arm alone — which §2 refutes — or
(b) use kitty remote control, which is a different transport with different failure modes.**

Other in-repo writers of a pane's appearance: `scripts/kitty-drift-run.sh:169`
(`kitty @ set-window-title --match title:…`, test-only). That is the complete list.

---

## 2. 🚨 THE REFUTED DESIGN — setting the title freezes CC's own liveness glyph

`docs/research/lr100p-2026-09-09/q-survivability-spawn.md:38-41` (measured, probe 7, 2026-09-09):

> **MEASURED — `--title` is STICKY.** Probe 7: with `--title`, the child's OSC-0 is ignored;
> without it, the child renames the window. So **never pass `--title` to a recovered claude pane** —
> it would freeze the title and destroy the `✳/◐/◑` liveness glyph the operator reads. Provenance
> goes in `--var` (machine-readable, `kitty @ ls`-visible, invisible to the eye).

Repeated as a design rule at `:277-280`. **Claude Code already encodes per-pane liveness in the OSC
title**, and the operator already reads it. Confirmed live this session — of 26 kitty windows, every
CC pane's title begins `✳` / `◐` / `◑`:

```
 265 ✳ Vista Real Apartment move-out bill        317 ◑ Kitty pane visual indicator for input …
 285 ◑ 100th percentile agent-entrypoint scre…   318 ◐ deep-research
```

⚠️ **But the glyph is NOT a clean idle bit.** `docs/research/pane-theft-composer-guard.md:192` (S7):
*"Title is `✳ Claude Code` for a fresh pane with a full composer **and** for an idle empty one.
Carries no composer bit."* So `✳` is an animation/base frame, not "waiting for you".

**Consequence for this work:** the title is *already occupied*, it is *sticky once overridden*, and
overriding it is a measured regression. Both `lead-crash-watchdog.sh`'s OSC-2 arm and any
`kitty @ set-window-title` approach collide with this.

---

## 3. THE MEASURED PRIOR DESIGN — O2, 2026-08-19 (the most valuable hit)

`docs/research/oversight-at-scale-2026-08-19/O2-operator-attention.md`, §2.7 *"THE INTERRUPT CHANNEL
IS OFF (this is the binding one)"*:

| Fact | Value then (2026-08-19) | Re-measured now (2026-09-13) |
|---|---|---|
| kitty `needs_attention` | **False on 12/12 panes** | **False on 20/20 CC panes** (3 True are sibling probe/shell panes, not CC) |
| kitty `has_activity_since_last_focus` | False 12/12 | **False 26/26** |
| kitty wired to RENDER it | `tab_title_template "…{bell_symbol}{activity_symbol}…"` | unchanged, `config/kitty.conf:428` |
| CC binary has the emitter | `preferredNotifChannel` ×15, `terminal_bell` ×10, `notifyBell` ×9, `inputNeededNotifEnabled`; enum neighbours `ghostty`/`iterm2`/`disabled` | — |
| It is configured | **nowhere** | **still nowhere** (`grep -o '"preferredNotifChannel"…' ~/.claude*/settings*.json ~/.claude.json` → empty) |
| any BEL in `hooks/ bin/` | **none** | **one** — `lead-crash-watchdog.sh:1695` (landed 2026-09-08, after O2) |

> *"The renderer is wired, the harness has the emitter, and nothing rings it. **Oversight on this box
> is 100% pull: the human must go and look.**"*

§4 **C3**, the design constraint, verbatim:

> **C3 — The pull-only interface is the defect, and it is one setting plus one convention away from
> being fixed.** … The consequence is measured: a permission block waits **28 minutes at p90 and
> 2.55 hours at p95**, and **7.8% of all blocks wait over an hour** — a session frozen mid-turn, with
> the operator two feet away, because nothing told him. **INTERRUPT is the cheapest term in C1.**

Supporting numbers from the same wave (all MEASURED):
- Operator attention budget: **3.75 distinct sessions/active hour** (median 3, p90 7); `units = rate × tolerance` ⇒ **~15**.
- **C2 — SEE cannot be bought with more screen.** 99.3% of a 9.3 Mpt² three-display desktop is already kitty; 635 rows across 12 panes; the smallest live pane is 19×95 and one of them rendered **no status line at all**. *"Any design past ~15 must derive per-unit state from a store, not from a rendered TUI, and must reserve the glass for the units that are asking for something."*
- `O4-exception-routing.md:52`, channel #11 — **the kitty tab bar was already assessed as a channel**: *"tab labels carry pane counts (task #147 done) … ambient count, no state; **cannot distinguish 30 working from 30 blocked**."*
- `O4:42-44` — the three live channels: the harness permission modal (invisible unless that pane is on screen, blocks indefinitely; 1,543 events/20 d, p50 37 s, p90 1,696 s, **max 81,411 s**); `hooks/notify.sh` chime (**18.7 alerts/h, peak 235/h, 71% is `complete`** i.e. noise); `hooks/push-critical.sh` (Pushover) — **INERT**, `PUSHOVER_TOKEN`/`USER` unset, `exit 0`, positive-controlled by running it.

**Status of C3: NEVER FILED.** Backlog rows whose `source`/`dodRef` is the oversight wave:
`ad37b0296a56` (unit-gate — **done**), `0d0e8b05bdfc` (**done**), `e75d0916cc2b` (mis-projected reso
row, done). No row anywhere in `backlog.jsonl` (20,250 lines) mentions `preferredNotifChannel`,
`needs_attention`, `notifyBell`, or `terminal_bell`. **This work discharges nothing on the ledger —
it actuates a research finding that has sat un-filed for 25 days.**

---

## 4. THE ALT-SCREEN REFUTATION — why "print it into the pane" cannot work on a live session

`docs/research/R6-observability.md` §1 (measured under a real pty, 2.1.220):

| probe | result |
|---|---|
| `ESC[?1049h` (enter alt screen) emitted by claude | **1×, at byte 104** |
| `ESC[2J` immediately after | 1× |
| wall-clock gap: pre-exec stderr → alt-screen switch | **1.42 s** |
| `ESC[?1049l` (restore) | only on a clean `/exit` |

> *"the announcement is visible for ~1.4 s … and cannot be scrolled back to during the session
> (kitty's scrollback in alt-screen shows the alt buffer). This is a **structural** loss."*

Confirmed live: **every CC pane reads `in_alternate_screen: True`** and **`at_prompt: False`**
(20/20 this session). Two consequences:
1. A text write into a live CC pane's tty is erased.
2. kitty's shell-integration `at_prompt` bit — the obvious native "this pane is idle" signal —
   **is structurally False for every CC pane** and cannot discriminate anything.

§1a of the same doc is itself a correction worth carrying: `cc-startup-modals-2026-08-04.md:79-82`
concluded from reading `ds()`/`IZi()` in the binary that `tui:"default"` keeps panes **out** of the
alternate screen, and all four config homes were set that way on that basis. **Refuted by
measurement.** A source-read about rendering lost to a pty capture.

R6's own Rank 3a proposed `kitty @ set-tab-title "next3 · <cwd>"` and flagged it **UNTESTED**
(§6 blocker: *"kitty tab-title persistence against CC's OSC-0 write is UNTESTED … a subagent cannot
claim it from documentation"*). §2 above is the answer that arrived four weeks later, from another
wave, and it is **negative**. Rank 3c (`CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1`) was measured to
kill `?1049h` but explicitly **"Do not reach for this"** — it changes the renderer for every session.

---

## 5. `config/kitty.conf` — the appearance decisions already taken, with their reasons

This file is the real design record. Every knob this brief would touch is already argued in it.

**Already SPENT on focus, not on state** (`:721-731`):
```
window_border_width   1pt
active_border_color   #6194f3     # blue = FOCUS is findable without hunting for the cursor
inactive_border_color #3a4555
```
kitty's stock values are called out as *"a grid drawn in highlighter"* (`#00ff00` / `#cccccc`).
⚠️ **The border channel is therefore already carrying "which pane has focus".** An idle tint on the
border either overloads it or fights it.

**Explicitly REJECTED — dimming** (`:751-753`, § "7e. Deliberately NOT set"):
> `inactive_text_alpha` — dimming unfocused panes is the obvious 30-pane move and iTerm2 offers it,
> **but the operator's standing rule is "never dim data"** (memory: TUI numbers first). Left at 1.0
> on purpose; set to ~0.85 only if that rule is revisited.

The standing rule, memory `feedback-tui-visibility-numbers-first.md` (screenshot-verified 2026-07-10):
never `░`/`▒` textures; **never SGR-2 dim** (profile-dependent, collapses to invisible on dark
themes) — use explicit truecolor grays; **the number IS the signal**, severity colour
green <50 / amber <80 / red ≥80. Also rejected on an adjacent axis: `text_fg_override_threshold`
(*"would systematically UNDO 7a"*), `macos_thicken_font`.

**Also explicitly NOT enabled** (`:390-395`): `tab_bar_min_tabs 1` — *"Showing it costs one text row
in EVERY OS window, permanently, and §6 is explicit that screen space is what we cannot spend at 30
panes."*

**The tab-title template already carries the attention glyphs** (`:406-428`, added 2026-08-07 after a
session became unfindable):
```
tab_title_template "{fmt.fg.red}{bell_symbol}{activity_symbol}{fmt.fg.tab}{f'[{num_windows}] ' if num_windows > 1 else ''}{f'⧉ ' if layout_name == 'stack' else ''}{title}"
tab_title_max_length 22
```
🚨 with a verification law attached: *"**VERIFY BY SCREENSHOT, NEVER BY `kitty @ load-config` EXITING
0.** kitty accepts unknown placeholder text silently and renders it literally, so a typo ships as
decoration. `kitty @ ls` reports the WINDOW title, not the rendered bar, and cannot catch it."*
And the honest limit: *"This does NOT make the bar authoritative — `cc-where` is what actually
answers 'where is my session', because no bar can name panes that are inside a tab rather than
being the tab."*

**A tab's title is its ACTIVE pane's title** — so at N panes per tab, N−1 sessions have *no*
representation on screen. That is the documented 2026-08-07 incident.

---

## 6. CAPABILITY — what kitty 0.48.2 on this box actually offers (measured now)

| Lever | Reachable? | Note |
|---|---|---|
| `kitten @ set-colors --match id:N …` | ✅ **YES** — `--match, -m` / `--match-tab, -t` / `--all` / `--configured` all present in `--help` | per-**window** colour change by remote control; this is the live lever for a per-pane tint |
| `kitten @ set-window-title --match …` | ✅ exists; used at `scripts/kitty-drift-run.sh:169` | ⚠️ **sticky** — see §2 |
| per-window **border** colour | ❌ **not exposed** — `active_border_color`/`inactive_border_color` are global config, no per-window `--match` form | the border cannot be driven per pane |
| `needs_attention` per window | read-only in `kitten @ ls`; kitty raises it on BEL-while-unfocused | rendered by `{bell_symbol}` at **tab** granularity only |
| `--var` / `user_vars` | ✅ per-window, `kitty @ ls`-visible, **no child process can forge it** (`q-survivability-spawn.md:277-280`) | the sanctioned provenance channel; invisible to the eye |
| `at_prompt` | ✅ field exists | **False on 20/20 CC panes** (alt screen) — useless as an idle bit |

Permission state: `Bash(kitten @ send-text:*)` plus `get-text`/`launch`/`close-window`/`ls` are
allowlisted in `~/.claude/settings.json:184` and the project file
(`docs/plans/backlog-consolidation-2026-08-09/OUT-panes.md:27`). **`set-colors` is NOT in that list.**

---

## 7. RELATED PRIOR ART, briefly

- **`hooks/waiting-recycle.sh`** — the desk idle detector. It already has an operator-facing arm, and
  it is `osascript display notification` (`wr_os_notify`, `:666-669`), plus `⟳`/`⚑` advisories
  injected as model-facing text. **It has no pane-appearance arm.** If an idle indicator needs a
  producer, this is the one that already computes the state.
- **`bin/cc-classify`**, **`bin/cc-where`**, **`bin/cc-sessions`** — existing state/locator stores.
  O2/C2's ruling is that state must come from a store, not a rendered TUI.
- **`statusline.sh`** (486 lines) — the always-visible per-pane row. Renders **context % only** plus
  an instance ring; no rung, no idle bit. It is a documented hot path (`0.15–0.37 Hz per pane`,
  109 ms CPU each, reduced to one `jq`), and `tests/statusline-identity.bats` pins it differentially
  with no glyph literal — so it can take extra content without reddening layer 1.
  ⚠️ Blind spot: a **resumed** pane often lacks `jq` on PATH (`statusline.sh:43-54`) — measured, five
  live `--resume` panes had no telemetry row. A statusline-borne indicator inherits that hole silently.
- **`hooks/notify.sh`** — the chime. macOS sound + NotificationCenter, 4 sounds by event TYPE.
  71% `complete` noise; 2 s debounce is per-session so N units = N chimes.
- **iTerm2 era**: no implementation ever existed. `grep -rn "1337\|SetBadge\|setColors"` over
  `bin/ hooks/ scripts/ lib/` → zero real hits (only `31337`/`13370` as digits). iTerm2 is retired
  (backlog `07cc93e6be57`); `docs/research/l3-l4-terminal-and-workflow-2026-07-31.md:242` records that
  iTerm2's pane surface was `ITERM_SESSION_ID` + the Python API, and `it2py` **is not on disk on this
  box** (`pane-theft-composer-guard.md:194`). Nothing died in the migration — nothing existed.

---

## 8. BOUNDED NULL — what I searched and did not find

**NOT FOUND, anywhere, on any surface below: a prior attempt, decision, refutation, or filed work
item whose SUBJECT is "make a pane visually indicate idle / waiting for the operator".**

Surfaces searched (the null is bounded to exactly these):

1. **`git log --all`** over 15,702 commits since 2026-01-01, all branches incl. `claude/fire-*`,
   `backup/*`, `agent-*`, `banner/*`, `cf-wave-*`; **`refs/wip/*`** (967 refs); **7 stashes**
   (diff-grepped for `needs_attention|set-colors|tab_title|inactive_text_alpha` → 0 hits).
   `git log --all --diff-filter=A` for any file ever added under `bin|hooks|scripts|config|lib`
   matching `attention|idle|visual|tint|glow|border|badge|paint|indicat|colou?r` → **one file,
   `scripts/idle-slope-sweep.sh`, which is a load-regression harness, not this.**
   Pickaxes: `-S inactive_text_alpha` (only the 2026-07-30 appearance commit `e9862360b` + noise),
   `-S set-tab-title` (only the R6 + desk-router docs), `-S set-colors` (only kitty.conf + README),
   `-S bell_symbol` (only the oversight doc + kitty.conf).
2. **`docs/plans/*.md` (86 files) + `docs/research/*` (200+ files and dirs)** grepped for
   `kitty · pane · idle · waiting · attention · border · visual · indicator · glyph · statusline ·
   tint · colour/color · blink · pulse · notify · badge · "draw the eye" · "at rest" ·
   set_tab_color · tab_bar · active_border_color · background_opacity · kitten @`.
3. **Memory corpora, all four config roots** — `~/.claude`, `~/.claude-next`, `~/.claude-tertiary`,
   `~/.claude-quaternary`, project dir `-Users-chrisren-Development-claude-infrastructure/memory`
   (**466 files each, identical sets**), plus `MEMORY.md` and the resident
   `.claude/rules/agent-operating-lessons.md`. Nearest hits are §5's `feedback-tui-visibility-numbers-first`
   and `screen-oracle-is-only-true-at-its-measured-geometry`; **no entry about pane-level state colour**.
4. **`~/.claude/autonomy/backlog.jsonl`** — 20,250 records, full JSON scan. Term counts across the
   whole store: `set-tab-title` 0 · `set_tab_title` 0 · `tab_bar` 0 · `active_border_color` 0 ·
   `background_opacity` 0 · `idle indicator` 0 · `visual indicator` 0. Every kitty row found is
   **mechanics** (socket path, self-close, pane identity, chord bindings) — all `done`.
   **`~/.claude/autonomy/decisions/`** — 4 files matched the term set, none on this subject
   (`a412859337a9` gesture/render refactor, `f6e4c09d07e3` permission-prompt autonomy,
   `a15f0fd2205e` venue re-seed, `6932c201bdc9` a 32→44px touch target in reso).
   **`~/.claude/autonomy/pending-activation/`** — no pane/appearance activator.
5. **Session index** (`~/.claude/bin/claude-search`, 7,252 sessions) — five queries
   (`kitty pane border colour idle`, `pane visually indicate waiting for operator`,
   `tab title idle indicator kitty`, `needs_attention kitty bell`, `which pane needs me visual`).
   **Zero on-topic sessions.** The only "visual indicator" hits are reso's 2026-01 *Table Status
   Visual Indicators* (app UI: border + badge encoding for table statuses) — a different subject that
   will keep surfacing in searches; ignore it.
6. **`~/.claude/hooks/` and `~/.claude/bin/`** — enumerated; §1 is the complete answer for "does
   anything paint into a pane". `grep -rn '\a'` over `hooks/ bin/ scripts/` → exactly one emitter.
7. **iTerm2-era code** — §7. Nothing existed to become dead.

**Strata explicitly EXCLUDED (I did not search these):** other repos on this box
(`reso-management-app`, `claude-session-search`, `lakehouse-lecture`, `personal`); the cloud
declaration store (`bin/cc-cloud`); GitHub issues/PRs; `~/.claude/logs/*`; the operator's iMessage
history (`msg`). A prior decision recorded ONLY in one of those would not appear here.

---

## 9. WHAT A BUILDER SHOULD CARRY FORWARD

1. **Do not set the pane title.** Sticky, and it kills `✳/◐/◑`. (§2, MEASURED)
2. **Do not dim.** Standing operator rule, already invoked once to reject `inactive_text_alpha`. (§5)
3. **The border is taken** — it means focus. (§5) And it is not per-window addressable anyway. (§6)
4. **Do not print into a live pane's tty.** Alt screen eats it; the one shipped painter refuses this case by design. (§1, §4)
5. **`kitten @ set-colors --match id:N` is the live, un-refuted lever** — and it is **not** in the permission allowlist. (§6)
6. **Verify by SCREENSHOT, at the production geometry.** kitty accepts bad template text silently
   (`kitty.conf:422-426`), and a rendering verdict is only true at the width/height you measured
   (memory `screen-oracle-is-only-true-at-its-measured-geometry`: a table measured at 120 cols
   inverted at 40; the failure looked like a 4% flake and was 100% of the narrow stratum).
7. **`tests/kitty-conf-bindings.bats` pins BINDINGS, not appearance** — an appearance change should
   not redden it; the two backlog rows that once called it red (`d4fcb1f5eb53`, `043c2e5fcc7e`) are
   both **done**, premise refuted, suite 12/12 green.
8. **`config/kitty.conf` lives in the SHARED checkout's live layer.** Land via the project-local
   `/ship` from a worktree; never commit in `~/Development/claude-infrastructure`.

---

## 10. 🚨 BLOCKER FOUND WHILE TIGHTENING THE NULL — the live kitty.conf is a DANGLING symlink

Found 2026-09-13 on a second pass, not part of the original brief. **Read-only; not fixed.**

```
$ ls -la ~/.config/kitty/
lrwxr-xr-x  kitty.conf -> /private/tmp/adn-land.v9Ngbj/config/kitty.conf   # created today 17:50
$ [ -d /private/tmp/adn-land.v9Ngbj ] && echo yes || echo NO
NO
```

`~/.config/kitty/` holds **exactly one entry**, and it points into an `adn-land.*` **land-staging
directory in `/private/tmp` that no longer exists**. `scripts/kitty-setup.sh:179` derives
`SRC_CONF="$REPO/config/kitty.conf"` — so the symlink was minted by a `kitty-setup` run whose
`$REPO` was an **ephemeral staging checkout**, not the durable one.

**Consequences, in order of when they bite:**

| | State |
|---|---|
| The **running** kitty (pid 97084) | Fine — it parsed the file before the target vanished. The 26 panes still show `#6194f3` borders, so the config did load. |
| `kitty @ load-config` / ⌘⌃, reload | **Fails now.** Any `config/kitty.conf` edit is unreachable by the live kitty. |
| The **next** kitty launch | Reads a dangling path ⇒ **compiled-in defaults**: `active_border_color #00ff00` (the "grid drawn in highlighter" `kitty.conf:727` names), **no `tab_title_template`** so `{bell_symbol}{activity_symbol}` and the `[N]`/`⧉` indicators vanish, no `tab_title_max_length`, none of the ⌘ chords, `repaint_delay` back to 10 ms, font size back to 12. |

**Every appearance and binding decision recorded in `config/kitty.conf` is one kitty restart from
gone, silently.** Nothing on this box asserts the symlink resolves — `tests/kitty-setup-canonical-tree.bats`
and `tests/kitty-conf-bindings.bats` read the **repo** copy, not the deployed one.

**Why this blocks the R6 work specifically:** a proposal that edits `config/kitty.conf` (a tab
template, a border colour, anything) **cannot take effect today** and would be measured against a
config the running kitty is holding only in memory. Re-point the symlink at
`/Users/chrisren/Development/claude-infrastructure/config/kitty.conf` and re-run
`kitty @ load-config` **before** measuring anything, or every A/B in this programme is against an
unreproducible baseline.

Same class as the resident rule *[Launcher runs the live layer]* — *"a generated launcher must name a
DURABLE path (it outlives the worktree that minted it)"*. Here it is a **setup script** run from a
`/tmp` checkout, minting a symlink to itself. Worth filing on its own merits; not filed by me
(read-only brief).

### Null tightened on two previously-excluded strata

`grep -rlE 'set-colors|inactive_text_alpha|active_border_color|needs_attention|set-tab-title'` over
`~/Development/claude-session-search`, `~/Development/personal`, `~/.claude/skills` → **zero hits in
all three.** Still excluded: `reso-management-app`, `lakehouse-lecture`, the cloud declaration store,
GitHub issues/PRs, `~/.claude/logs/*`, iMessage.
