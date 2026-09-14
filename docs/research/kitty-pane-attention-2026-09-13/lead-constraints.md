# Lead-measured constraints (2026-09-13) — measured, not inferred

## C1 Terminal is kitty 0.48.2; ITERM_SESSION_ID is a SHIM
`ITERM_SESSION_ID=w0t0p0:317` and `KITTY_WINDOW_ID=317` — the iTerm id is synthesized
from the kitty window id. Remote control IS enabled (`kitty @ ls` works from a pane,
`KITTY_LISTEN_ON=unix:/tmp/kitty-97084`).

## C2 [CORRECTED] The repo SHIPS the theme; the LIVE SYMLINK is broken
`~/.config/kitty/kitty.conf -> /private/tmp/adn-land.v9Ngbj/config/kitty.conf` (TARGET GONE).
But the running instance is NOT on defaults (defaults: active_border_color = green #00ff00).
Live, measured via `kitty @ get-colors --match id:317`:
    background            #1e1e24
    foreground            #e6e6e6
    active_border_color   #6194f3   <- the operator's blue reference line
    inactive_border_color #3a4555   <- the gray reference line
    bell_border_color     #ff5a00   (kitty default, unstyled)
    color3 (amber)        #f3c233     color1 #e04040   color4 #6194f3   color6 #4de0e0
CORRECTION (graveyard agent + verified): the repo DOES ship the config —
`config/kitty.conf`, 755 lines, tracked, heavily reasoned (the #6194f3/#3a4555 pair is
at :729-731 with its rationale). The defect is only that the LIVE symlink was repointed
at a land-staging temp dir (`adn-land.v9Ngbj`) that has since been cleaned.
=> SEPARATE LIVE DEFECT: the operator's kitty config is currently UNDEPLOYED. kitty is
   running on the copy it loaded at start. A restart or any `load_config` loses all 755
   lines. This is worth fixing regardless of this feature.

## C3 `get-colors` exposes border colors AND accepts `--match id:N`
Strong evidence border colors are per-window addressable via `set-colors`. MUST be
empirically confirmed before the design rests on it.

## C4 Pane identity is resolvable WITHOUT the env var (transplant-proof)
Walking our own pid ancestry against `kitty @ ls` `foreground_processes[].pid` resolved
window 317 at depth 2, agreeing with KITTY_WINDOW_ID. This matters because this fleet
transplants/resumes sessions between panes (windows 161/165 are `resumed-*`), and the
memory rule [transplanted-session-loses-dispatch-identity] says env-var identity goes
stale exactly then. => resolve by ancestry, fall back to $KITTY_WINDOW_ID.

## C5 *** THE LAYOUT CONSTRAINT — this shapes the whole design ***
5 OS-windows, ONE built-in display (3456x2234 = 1728x1117 logical).
`System Events` sees ONE kitty window on the current Space, sized 1728x1080 (maximized).
=> The operator runs ONE MAXIMIZED OS-WINDOW PER macOS SPACE, each holding a `splits`
   tab of 2-10 panes.
=> CONSEQUENCE: an in-window cue (border, background tint, logo) can only ever be seen
   for the ~1 OS-window on the CURRENT Space. For the other 3-4 Spaces it is invisible.
   This is precisely the "going between windows" cost in the operator's ask.
=> THE DESIGN MUST BE TWO-TIER:
     Tier 1 (within a Space): subtle per-pane cue. Border/bg. Beauty lives here.
     Tier 2 (across Spaces): an aggregate signal readable WITHOUT switching Space.
       Candidates: macOS Dock badge (kitty has `macos_dock_badge_on_bell yes` already
       ON by default -> a bell gives a free per-app badge), window TITLE glyph (shows in
       Mission Control + Dock window menu), a menu-bar item, or a notification.

## C6 Pane census at investigation time
tab 14: 2 panes | tab 63: 5 panes | tab 64: 4 real panes (+6 subagent panes I spawned,
sizes degraded to 30x1 — SEE CLEANUP) | tab 65: 2 panes | tab 67: probe os-window (agent r1)

## C7 CLEANUP DEBT created by this session
Research subagents spawned VISIBLE panes into the operator's os-window 64, squeezing
existing panes to 30x1. Must be reclaimed at wrap-up.

## C8 Constraints the shipped config ALREADY encodes (do not relitigate)
- **"never dim data"** — `inactive_text_alpha` is deliberately left at 1.0
  (`config/kitty.conf` §7e). Operator standing rule (memory: TUI numbers first).
  => DIMMING IS REFUTED AS A CHANNEL. Do not propose it.
- **Restraint is the house style at scale** — the config's own words on kitty's stock
  defaults: *"At 30 panes that is a grid drawn in highlighter."* The design target is
  up to ~30 panes. Anything that lights up per-pane must survive being multiplied by 30.
- **The border is already SPENT on focus** (`active_border_color`). A second meaning on
  the same channel collides with the one cue the operator already reads.

## C9 Mechanisms REFUTED by prior measurement (graveyard agent, r6)
- **Title glyphs `✳ ◐ ◑` are NOT free signal.** They are Claude Code's own OSC-title
  liveness glyphs, but `✳` renders for a FULL composer AND an IDLE one
  (`pane-theft-composer-guard.md:192`) — it carries no waiting bit.
- **Never pass `--title` to a claude pane** — it is STICKY and freezes the glyph
  (`lr100p-2026-09-09/q-survivability-spawn.md:38-41`).
- **Painting text into a LIVE pane is impossible.** Claude Code enters the alternate
  screen ~1.42 s after launch; all 20 CC panes read `in_alternate_screen:True`.
  `hooks/lead-crash-watchdog.sh:1279` writes to the tty by path but REFUSES unless the
  tty has settled to a bare shell — it is precedent for a DEAD pane only.
- **Tab bar alone is insufficient** (`oversight-at-scale-2026-08-19/O4`): *"ambient count,
  no state; cannot distinguish 30 working from 30 blocked."*

## C10 The problem is QUANTIFIED already (r6, oversight-at-scale-2026-08-19 §2.7/C3)
`needs_attention` is wired in the renderer and the harness has the emitter, and NOTHING
RINGS IT — measured False on 20/20 CC panes today; `preferredNotifChannel` unset
everywhere. Operator wait on permission blocks: **p90 28 min, p95 2.55 h, 7.8% over an
hour.** That is the cost of the missing signal, in the operator's own instrumentation.
=> This work has a pre-existing, un-actuated design and a measured payoff. It discharges
   NO open backlog row (C3 was never filed — 0 hits across 20,250 records).

## C11 PERMISSION NOTE (operator-owned, never self-granted)
`kitten @ set-colors --match id:N` works on 0.48.2 but is NOT in the permission allowlist
(`send-text`/`get-text`/`launch`/`close-window`/`ls` are). Adding it is the OPERATOR's
call — never script or self-apply an allowlist edit.

## C12 [FIXED THIS SESSION] kitty.conf symlink repaired
Culprit: `scripts/kitty-setup.sh` derives its link target from `$0` (`:36`), so a run from
an ephemeral land-staging checkout (`/private/tmp/adn-land.v9Ngbj`) pointed the live layer
there. The script HAS a guard for this (`:82-101`) but it only refuses for a *linked git
worktree*; a full temp clone is invisible to it — a residual worth noting.
Blast radius measured with `scripts/kitty-setup.sh --check`: EXACTLY ONE item.
All 24 others (it2 divert, it2-kitty, split-cwd, confirm-close, pane-menu, split-launch,
cc-in-kitty, shims, teammateMode x5, control socket) were already correct.
Repair: `ln -sfn <canonical>/config/kitty.conf ~/.config/kitty/kitty.conf`
Verified: `--check` now reports **25 ok, 0 missing** (was 24 ok, 1 missing).
Deliberately did NOT run `kitty @ load-config` — repo history (`7c7717370`) records the
config watcher reverting the operator's zoom; the running instance already holds the same
bytes in memory, so a reload buys nothing and risks disturbing 24 live panes.

## C13 IMPLEMENTATION PATH (from r4) — settled, no further research needed
- **New helper script** → name it **`bin/cc-kitty-<thing>`**. `install.sh:923-935` symlinks the
  globs `bin/cc-* bin/desk-* bin/ms365-*` into `~/.claude/bin/` deliberately so a new tool
  deploys with no installer edit. Precedents: `cc-kitty-bin`, `cc-kitty-socket`, `cc-in-kitty`.
  A name OUTSIDE those globs gets no symlink and forces an 8th `ln` in kitty-setup.sh, which
  `tests/deploy-parity.bats` REFUSES (it asserts the partitions sum). Use the glob.
- **Config edits** → `config/kitty.conf` is deployed ONLY by `scripts/kitty-setup.sh:188`, as a
  symlink. Now that C12 is repaired, editing the repo file IS live-on-restart. No redeploy step.
- **From a HOOK or launchd there is no `KITTY_LISTEN_ON`** → must resolve the socket via
  `bin/cc-kitty-socket` (KITTY_LISTEN_ON fast path, stale socket falls through to a glob).
  Verified live by kitty-setup: *"daemon-PATH probe: 'session list' works with no Homebrew on
  PATH"*. THIS IS LOAD-BEARING — a naive `kitty @` in a hook fails in exactly the context we need.
- **`bin/it2-kitty` owns every kitty primitive.** `handoff-fire.sh` never calls `kitty @`; it
  calls `it2`, which diverts to `it2-kitty` inside kitty. A new kitty verb belongs there or in a
  new `cc-kitty-*` tool — not sprinkled at call sites.
- **SAFE A/B PATH (important):** `assets/demo/kitty-panes-capture.sh:21` runs
  `kitty --instance-group=ccpanes --config <repo>/config/kitty.conf` — a SEPARATE instance.
  That is how to test a conf change without reloading the operator's 24 live panes.
- Migration state: NOT in flight. iTerm2's `it2` call surface is kept permanently and translated
  to kitty at the edge, by design. Do not "finish" it.

## C14 [r4 refinements] — timing, a real guard bug, and a BORDER constraint
- Timeline pins the repair as correct and timely: symlink broke **today 17:50:31**
  (`stat -f %SB`); kitty pid 97084 started **Sep 9 18:56:14** (`ps -o lstart`). So the running
  instance loaded a GOOD config days before the break and holds it in memory. The exposure was
  purely the NEXT restart — which also loses `allow_remote_control`/`listen_on`, the two options
  kitty cannot reload, i.e. it would have silently broken the whole Agent-Teams spawn path.
- 🚨 **`draw_minimal_borders` is UNSET ⇒ kitty's default `yes`** ⇒ outer-edge borders are
  OMITTED and only inter-window dividers are drawn. => THE BORDER IS A POOR CARRIER for
  per-window state: a pane's "own" border is not a rectangle it owns, it is a shared divider.
  This independently corroborates r6's "not per-window addressable" and pushes the persistent
  channel toward BACKGROUND, which does fill a pane's whole rectangle unambiguously.
- `tests/kitty-conf-bindings.bats` asserts on the conf's TEXT with 2 mutant controls — a styling
  edit must not disturb the pinned lines.
- `~/.zshrc:695` exports `ITERM_SESSION_ID="w0t0p0:$KITTY_WINDOW_ID"` unconditionally in kitty;
  stable for the kitty PROCESS's life, NOT across restart (ids recycle low), and inherited by
  children — which is exactly why `bin/cc-in-kitty` does an ancestry check. Corroborates C4.

## C15 TWO FOLLOW-ON DEFECTS surfaced by the C12 repair (candidates, not yet driven)
(a) **The guard predicate is wrong.** `kitty-setup.sh:97-107` guards this exact failure but
    tests *"is a linked git worktree"*; the wanted invariant is *"is a DURABLE path"*. A
    standalone clone or a non-git copy (like the /tmp land-staging tree) lands on the
    permissive default, so the guard could not fire on the case that actually happened.
(b) **Nothing schedules `kitty-setup.sh --check`.** It DOES detect the break (it reported
    `24 ok, 1 missing`) but no job runs it, and `deploy-parity-assert.sh:742` exempts the path
    by design (`want=0`) — so the one auditor that would have caught it is deliberately blind.
    => The break was undetectable-in-practice for as long as it lasted.
Both are bounded, in-repo, and prevent recurrence of the defect repaired in C12.

## C16 [r5] THE REFRAME — the complaint is SPATIAL FREQUENCY, not colour
At this display's geometry (16" XDR, 32.1°x22.0° at 55 cm) the 4 px `active_border_color`
divider is **resolvable only within 3.4° of fixation**. => No palette change can make a LINE
work as a scanning cue. The cue must be **AREAL** (a pane's background), not linear.
This also explains why the blue divider is fine for the FOCUSED pane (you are looking at it)
and structurally cannot work for the pane you are trying to FIND.

## C17 [r5, positive-controlled] THE KEYSTONE ANSWER
- per-pane **`background` IS settable and isolated** via `set-colors --match id:N`. ✅
- per-pane **border colour is NOT**: `set-colors inactive_border_color` silently NO-OPS.
  (Verified with a positive control, so this is a reading, not a failed attempt.)
- The ONLY per-pane border channel is kitty's **bell state**.
=> Persistent layer = BACKGROUND. Border is reinforcement only, via the bell.

## C18 [r5] ONSET vs STATE are two different jobs — both required
Jonides & Yantis (1988): colour/luminance **singletons do NOT capture attention**; only
**abrupt onset** does. A static tint is FINDABLE but never ATTENTION-GETTING.
=> arm a one-shot onset AND a persistent state. Native eased visual bell does the onset
   (`visual_bell_duration 0.4 ease-out`, `visual_bell_color #2a2733`) — compositor-rendered,
   ZERO subprocesses. Scripting a fade costs 35.8 ms ±28 ms per step (measured) — do not.

## C19 [r5] POLARITY — RANK, do not threshold (the best idea in the wave)
Base rates invert over the day, so EITHER fixed polarity is "always on" half the time —
which is the operator's own alarm-polarity rule. Fix: exactly ONE pane (the longest-waiting)
wears the STRONG tier; every other waiting pane gets a weaker tint. The signal then carries
~4.4 bits whether 1 or 10 panes wait, and is STRUCTURALLY INCAPABLE of becoming an alarm that
always fires. Working already self-announces via spinner motion; WAITING is the unmarked state.

## C20 [r5] PALETTE — blue<->gold is the only CVD-safe axis
Red-green opponency is behaviourally absent by 25-30° eccentricity; the screen corners sit at
20.8°. `#eb6f92` collapses under protanopia to within 3% of the blue's luminance. **`#f6c177`**
keeps a 2x luminance ratio over the blue under BOTH protanopia and deuteranopia. Orange is
already taken by Claude Code's own spinner — do not reuse it.
Proposed: strong `#26242e` (+40.5% Weber luminance over `#1e1e24`; fg contrast 13.29:1 ->
12.24:1, still far above AA), secondary `#242130`, bell border `#f6c177`, border width 2pt.

## C21 🚨 [LEAD, measured now] THE DOCK BADGE CANNOT SERVE TIER 2 — REFUTED
All four bell options are INDEPENDENT (`enable_audio_bell`, `window_alert_on_bell`,
`macos_dock_badge_on_bell`, `bell_on_tab`), so audio + bounce can be silenced separately.
BUT kitty's own doc for `macos_dock_badge_on_bell`: *"Show a badge ... when a bell occurs
**and kitty is not the active application** (macOS only). The badge is **automatically cleared
when kitty regains focus**."*
The operator switches SPACES WITHIN kitty, so kitty is essentially always the active app.
=> THE BADGE WOULD NEVER ONCE APPEAR. Dock badge is dead as the cross-Space channel.
Also dead for the same occlusion reason: `bell_on_tab` (each OS-window has its own tab bar and
holds ONE tab, so an occluded window's tab bar is equally invisible).

## C22 TIER-2 CANDIDATE THAT SURVIVES — a menu-bar status item
The macOS menu bar is the ONLY surface visible from every Space without switching. A tiny
NSStatusItem showing nothing at zero and a subtle gold dot + count when panes wait
(click = focus the longest-waiting pane) is the calm-technology-correct answer.
PRECEDENT EXISTS IN-TREE: `bin/kitty-pane-menu-native.swift`, compiled by `kitty-setup.sh:245`
via `swiftc` — so a native Swift helper is an established, already-deployed pattern here.
Ship-blockers to set in conf regardless: `enable_audio_bell no` (17 panes would BEEP),
`window_alert_on_bell no` (17 dock bounces).

## C23 RESIDUAL — the tint is UNVERIFIED BY EYE
`screencapture -l` fails on background kitty windows, so no side-by-side of `#26242e` vs
`#1e1e24` was obtained. The operator must confirm the tint by eye before it ships.

## C24 [r3] THE PRODUCER CONTRACT — settled
Binary is **2.1.260** (`claude` is a shell FUNCTION — `--version` is not the instrument).
**33 events** read from the binary's own registry; 20 wired today.

| edge | event | note |
|---|---|---|
| → working | `UserPromptSubmit` | **carries `source`: `user\|sdk\|system\|loop_wakeup\|schedule_wakeup\|poll_event`.** A background-task/task-notification wake arrives as `source:"system"` — so the WAKER is nameable. There is no separate wake event. |
| → idle | `Stop` | a hook that runs a command and exits 0 does NOT alter control flow (binary's own contract). Emit NO JSON. `Stop`/`SubagentStop` share one mutually-exclusive call site, so an in-process subagent never emits a spurious `Stop`. |
| → idle (error) | 🚨 **`StopFailure`** | **`Stop` does NOT fire when a turn dies on an API error.** Without this arm a rate-limited pane stays painted "working" FOREVER — the exact failure that would make the whole system lie. Fire-and-forget by contract. |
| → blocked | 🚨 **`PermissionRequest`**, NOT `Notification` | `Notification`'s `permission_prompt` is on a **6 s debounce** (`M4e=6000`, cancelled when answered) so FAST prompts emit NOTHING; `idle_prompt` is a 60 s timer suppressed while any dialog is up. `PermissionRequest` fires the moment the dialog is displayed; exit 0 + no JSON is inert. |
| keep-alive | `PostToolBatch` | one fire per model round-trip |
| background work | `SubagentStart` (UNWIRED today), `SubagentStop`, `TaskCreated` | available for the "working at rest" state |

## C25 [r3] A HOOK CAN RING THE BELL WITH ZERO SUBPROCESS
Any hook may return **`terminalSequence`**, allowlisted to **OSC 0/1/2/9/99/777 + BEL**.
=> the ONSET (visual bell flash + `bell_border_color`) is free: no socket, no fork.
   OSC 99/777 are kitty's desktop-notification protocols — also reachable from a hook.
   ⚠️ `terminalSequence` is TITLE + NOTIFICATION only — **NOT colour**. The persistent
   background tint still requires `kitty @ set-colors --match id:N` over the socket.

## C26 HOOKS ARE NOT PERMISSION-GATED (corrects C11's scope)
C11 noted `kitten @ set-colors` is absent from the permission allowlist. That governs the
AGENT's Bash tool calls, NOT a hook: hook commands are executed by the harness from
`settings.json`, outside the tool-permission system. So the hook may call
`kitty @ set-colors` freely. The allowlist question only affects ME testing it by hand.

## C27 [r3] Pane id IS available to hooks, but is VOLATILE
Measured in a child of this session's claude process: `KITTY_WINDOW_ID=320`,
`KITTY_LISTEN_ON=unix:/tmp/kitty-97084`, `ITERM_SESSION_ID=w0t0p0:320`. Hook-side
corroboration: `session-register.sh` (SessionStart) wrote `cc-registry/324.json` at 20:36
from that env. **Pane ids are volatile and REUSED** => key durable state on cwd/session_id,
resolve the live pane at paint time (C4 ancestry).

## C28 [r3] WIRING PROCEDURE — one line
Land `migrations/0028-<slug>.sh` **in the same diff as the hook**; header
`# migration-class: c10` plus `migration-step` / `migration-run` / `migration-subject` /
`migration-verify` (a NON-tautological `jq` over `${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json`).
**c10 is STAGED, NEVER SELF-RUN** — the operator runs it.
Register into each config dir's **`settings.json`** — migration 0019 measured that the
user-level `settings.local.json` is **not** read as a hook source.

## C29 [r1] 🚨 DURABILITY CORRECTION — `set-colors` state is WIPED BY A CONFIG RELOAD
Measured on the live binary:
- **Arbitrary per-window BORDER colour is IMPOSSIBLE.** `set-colors --match id:N
  inactive_border_color=…` exits 0, **IGNORES `--match`, repaints EVERY window**, and
  `get-colors` does not report it. (Independently corroborates r5's no-op finding — two
  different routes, same verdict.) **Exactly three border states exist: focused / not / bell.**
- 🚨 **Per-window `set-colors` state does NOT survive a config reload** — measured WIPED.
  And a **`__watch_conf__` watcher is LIVE**. Repo history (`7c7717370`) records that watcher
  reverting the operator's zoom every 1-3 min. => A background tint applied by `set-colors` is
  **FRAGILE**: any reload silently erases the whole fleet's waiting marks.
- **Window logos, bell state and user-vars DO survive a reload.** Logos also survive the
  ALTERNATE SCREEN, which killed every text-painting approach (C9).
- Also impossible: per-split background *opacity*, per-split background *image*, per-window
  `set-colors --reset` (`--reset` implies `--all --configured`), macOS dock badge (= C21).

## C30 THE SYNTHESIS — keep r5's AREAL concept, move it onto r1's DURABLE channel
r5 is right that the cue must be AREAL (C16: a 4 px line resolves only within 3.4° of
fixation — and r1's 6 px logo "edge rail" inherits that same spatial-frequency defect).
r1 is right that `set-colors` is the fragile channel and `set-window-logo` is the durable one.
=> Implement the WARM WASH **as a window logo**: a soft warm gradient PNG scaled to FILL the
   pane at low alpha, not a 6 px rail. That yields an areal wash that is per-split, drawn
   under text, alt-screen-proof, config-reload-proof, and cleared with `--match id:N none`.
   Needs verifying: that `window_logo_scale` can fill the pane and that alpha reads as a wash.

## C31 [r1] OFFER, DO NOT ASSUME — per-window title bars
`window_title_bar_min_windows 1` (new in 0.46) gives a REAL per-pane header with arbitrary
runtime text, auto-rendering 🔔 and progress. It costs **one text row per pane**, and
`config/kitty.conf` already refused a one-row-per-OS-window tab bar on exactly that ground.
=> Present it as an operator CHOICE, never ship it by default.
Also available: **OSC 9;4 progress rail** (`progress_bar left`) — rounded, scrollbar-styled,
per-window presence/fill, colour+edge global. Refined-looking; same linear-cue caveat.

## C32 [LEAD, verified] THE WARM-WASH MECHANISM IS BUILDABLE AND DURABLE
`kitty @ set-window-logo` runtime flags: `--match`, `--self`, `--position`, `--alpha`,
`--no-response` (fire-and-forget — use it in hooks). **There is NO `--scale` at runtime**;
scale is the GLOBAL config option `window_logo_scale`, which accepts a TWO-number form:
*"the width and height of the logo are scaled to the respective percentage of the window's
width and height."*
=> RECIPE: set `window_logo_scale 100 100` ONCE in `config/kitty.conf` (global, harmless
   because we use logos for nothing else), then per pane at runtime:
     arm:   kitty @ set-window-logo --no-response --match id:N wash-gold.png \
                --position center --alpha 0.08
     clear: kitty @ set-window-logo --no-response --match id:N none
   A flat/softly-graded warm PNG scaled to 100%x100% at low alpha IS the areal warm wash —
   drawn UNDER text, per-split, alt-screen-proof, and config-reload-proof (unlike set-colors).

## C33 [LEAD, verified] KITTY HAS A PER-WINDOW STATE STORE + AN ATTENTION STATE
`--match` fields include:
- **`var:NAME=VALUE`** — per-window USER VARIABLES (`kitty @ set-user-vars`). r1 measured
  user-vars SURVIVE a config reload. => this is the durable per-pane state store; we can ask
  kitty itself "which panes are waiting" with `kitty @ ls --match var:cc_state=waiting`
  instead of keeping a parallel store that can desync from the panes.
- **`state:needs_attention`** — kitty's OWN per-window attention flag (the bell state), so the
  bell tier is queryable too.
- also `env:`, `cwd:`, `neighbor:`, `recent:`, `session:`.
=> The ranking rule of C19 (exactly ONE pane wears the strong tier) can be computed by reading
   kitty's own per-window vars — no external state file, nothing to desync, nothing to GC.

## C34 OPEN — awaiting r2 (state-signal)
The ONLY remaining question that can still change the design: can anything distinguish
"idle because it wants the HUMAN" from "idle-looking but legitimately waiting on a background
agent / dynamic workflow / a peer pane"? If NOTHING can, marking every idle pane recreates the
christmas tree the operator is trying to escape, and the ranking rule of C19 becomes the ONLY
thing holding the signal's information content up.
Partial answer already in hand (C24): `UserPromptSubmit.source` names the WAKER after the fact
(`user` vs `system`), which is a retrospective discriminator, not one available at idle time.

## C35 [r2] THE DISCRIMINATOR — the answer, and the gap
**Nothing distinguishes "waiting on a peer/agent/workflow" reliably.** `bin/cc-wait` +
`~/.claude/wait-contracts/*.json` was DESIGNED for exactly this and is **DEAD** (0 OPEN,
newest Aug 11, no production caller).
**BUT the usable predicate exists:** `session-busy.sh :: sb_idle_arms` (`:282-305`) separates
  **IDLE-ARMED** — a `goal` / `continue` / `mail` / `custody` arm will wake it ⇒ NOT yours
  **IDLE-DEAF** — nothing will ever wake it ⇒ **THIS is "wants the human"**
=> PAINT **IDLE-DEAF ONLY**. IDLE-ARMED panes stay calm. That is the whole false-positive fix.
**THE GAP:** there is **no arm for in-process subagents and none for Dynamic Workflows**. A lead
holding 6 subagents reads `kind=stop` + frozen glyph + IDLE-DEAF — measured on panes 316 AND 317
(317 = this very session). Cheapest closure, and it is already available: **wire `SubagentStart`**
(r3: exists in the registry, UNWIRED today) **+ `SubagentStop`, and add a `subagents` arm to
`sb_idle_arms`.** Two agents converged on this from opposite ends.

## C36 [r2] GLYPH CONTRACT — measured, and a REPO BUG it exposes
Exactly three glyphs, written by Claude Code's binary (not this repo); `◒`/`◓` never occur.
`✳` = top-level loop NOT turning · `◐⇄◑` = spinner turning (~0.75-0.8 s period).
- 🚨 **One sample is a coin flip.** Of 8 panes showing a FROZEN `◐`/`◑`, **2 were IDLE-DEAF**.
  Sample TWICE, >=0.4 s apart, and treat *change* as the signal.
- 🚨 **`✳` does NOT separate idle from BLOCKED-ON-PERMISSION** (measured twice on pane 129).
  The permission beacon `/tmp/cc-permission-pending/<sid>.json` is the only discriminator —
  and you must check `.beacon-alive` exists, else absence is BLINDNESS, not an all-clear.
- 🚨 **REPO BUG (pre-existing, ours to fix):** `--title` is STICKY and permanently freezes a
  pane's glyph. `lr-lib.sh:340` and `lr-handoff.sh:749` both warn about this — but
  **`bin/kitty-split-launch.sh:148` passes `--title` unconditionally** and `bin/cc-offload:874`
  does too. MEASURED: **7 of 23 live panes are permanently dark to this signal.** Fix = pass
  `--temporary`, or drop `--title`.
- Cost note: `cc-classify --all` is ~30 s for 17 sessions (forks jq per transcript) — NOT
  pollable. `session_busy_live` is O(1) per session and is the right primitive.

## C37 FINAL DESIGN (all six axes closed)
PRODUCER  Stop / StopFailure -> candidate-waiting · UserPromptSubmit -> clear ·
          PermissionRequest -> blocked tier · SubagentStart/Stop -> suppress (closes C35 gap)
PREDICATE paint only `IDLE-DEAF`; IDLE-ARMED (goal/continue/mail/custody) stays calm
RANK      exactly ONE pane (longest-waiting) gets the strong tier (C19) — keeps ~4.4 bits
          whether 1 or 10 panes wait, and cannot degenerate into an always-on alarm
STATE     kitty per-window user-vars (`var:cc_state=...`) — survives reload, no external store
PERSIST   `set-window-logo` warm wash, areal, alpha ~0.06-0.10 (durable; NOT set-colors)
ONSET     hook-returned BEL -> kitty native eased visual bell (zero subprocess)
BORDER    bell state only (the sole per-pane border channel); `bell_border_color #f6c177`
SILENCE   `enable_audio_bell no` + `window_alert_on_bell no` (else 17 beeps / 17 dock bounces)
TIER-2    menu-bar NSStatusItem (dock badge REFUTED, C21) — precedent: kitty-pane-menu-native.swift
RESIDUAL  the tint must be confirmed BY EYE (C23) -> deliver a live, reversible demo
