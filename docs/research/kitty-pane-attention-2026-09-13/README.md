# Making a kitty pane say "I am waiting for YOU" — design record

**Ask (2026-09-13):** *"the most beautiful and subtle way to style the panes to have a better
visual indication of it waiting on user input rather than working even at rest… draw the user's
eyes without having to scour the last message, the recap note, and such."*
Reference bar: *"the active split pane has its dividing line in blue instead of gray."*

Six parallel research agents + a lead pass. Every claim here is measured on the live box; the
six agent artifacts sit beside this file and `lead-constraints.md` carries the lead's own
measurements (C1–C37). **Nothing below is inferred from a name or a comment.**

---

## The reframe that decides everything

**The complaint is SPATIAL FREQUENCY, not colour.** At this display's geometry (16" XDR,
32.1°×22.0° at 55 cm) the 4 px `active_border_color` divider is resolvable **only within 3.4° of
fixation**. No palette makes a *line* work as a scanning cue. The cue must be **areal**.

That also explains the reference case precisely: the blue divider works beautifully for the pane
you are *looking at*, and structurally cannot work for the pane you are trying to *find*.

**Second reframe — onset and state are different jobs.** Jonides & Yantis (1988): colour and
luminance *singletons do not capture attention*; only **abrupt onset** does. A static tint is
findable but never attention-getting. Both halves are required.

---

## What is IMPOSSIBLE (measured — do not design around these)

| | Verdict |
|---|---|
| arbitrary per-window **border colour** | `set-colors --match id:N inactive_border_color` exits 0, **ignores `--match`, repaints EVERY window**. Exactly three border states exist: focused / not / bell. Found twice, by two agents, by different routes. |
| per-window `set-colors` **surviving a config reload** | **wiped** — and a `__watch_conf__` watcher is live on this box. Logos, bell state and user-vars survive. |
| **macOS Dock badge** as the cross-Space signal | kitty's own doc: shows only *"when kitty is **not** the active application"* and *"cleared when kitty regains focus"*. The operator switches Spaces **within** kitty ⇒ it would never once appear. |
| painting **text** into a live pane | Claude Code enters the alternate screen ~1.42 s after launch; all panes read `in_alternate_screen:True`. `lead-crash-watchdog.sh` paints by tty path but **refuses** unless the pane has settled to a bare shell — precedent for a *dead* pane only. |
| **dimming** inactive panes | `config/kitty.conf` §7e declines `inactive_text_alpha` under the standing *"never dim data"* rule. |
| the **title glyphs** as a waiting signal | `✳` renders for idle **and** for blocked-on-permission (measured twice). It separates *turning* from *not turning*, never *why*. |
| per-split background **opacity** or **image**, per-window `set-colors --reset` | per-OS-window by design / `--reset` implies `--all`. |

---

## The design

```
PRODUCER   Stop, StopFailure          -> candidate waiting
           UserPromptSubmit           -> clear   (NOT on focus — glancing ≠ answering)
           PermissionRequest          -> blocked tier
           SubagentStart/SubagentStop -> suppress (closes the false-positive gap, below)
PREDICATE  paint IDLE-DEAF only; IDLE-ARMED (goal|continue|mail|custody) stays calm
RANK       exactly ONE pane — the longest-waiting — wears the strong tier
STATE      kitty per-window user-vars (`var:cc_wash=…`) — survives reload, nothing to desync
PERSIST    `set-window-logo` areal warm wash, alpha 0.06–0.15   (durable; NOT set-colors)
ONSET      hook-returned BEL -> kitty's native eased visual bell (zero subprocess)
BORDER     bell state only — the sole per-pane border channel; `bell_border_color #f6c177`
SILENCE    `enable_audio_bell no` + `window_alert_on_bell no`   (else 17 beeps / 17 bounces)
TIER 2     menu-bar NSStatusItem  (dock badge refuted; precedent kitty-pane-menu-native.swift)
```

### Why rank instead of threshold — the best idea in the wave
Base rates invert over the day, so **either** fixed polarity is "always on" half the time, which
is this repo's own alarm-polarity rule. Ranking — exactly one strong pane, the rest weak — keeps
the signal at ~4.4 bits whether 1 or 10 panes wait, and makes it **structurally incapable** of
degenerating into an alarm that always fires. Working already self-announces via spinner motion;
**waiting is the genuinely unmarked state.**

### Why gold
Blue↔gold is the only colour-blind-safe axis available. Red-green opponency is behaviourally
absent by 25–30° eccentricity and the screen corners sit at 20.8°; a rose tone collapses under
protanopia to within 3% of the existing blue's luminance. **`#f6c177`** holds a 2× luminance
ratio over `#6194f3` under **both** protanopia and deuteranopia. Orange is already spoken for by
Claude Code's own spinner.

---

## The false-positive gap, and its cheap closure

**Nothing on the box reliably distinguishes "waiting on the human" from "waiting on a background
agent / Dynamic Workflow / a peer pane."** `bin/cc-wait` + `~/.claude/wait-contracts/` was built
for exactly this and is **dead** — 0 OPEN, newest Aug 11, no production caller.

The usable predicate is `session-busy.sh :: sb_idle_arms` (`:282-305`):
**IDLE-ARMED** (a goal / continue / mail / custody arm will wake it) ⇒ not yours.
**IDLE-DEAF** (nothing will ever wake it) ⇒ **this is "wants the human."** Paint only these.

**The residual hole:** there is no arm for **in-process subagents** and none for **Dynamic
Workflows**. A lead holding 6 subagents reads `kind=stop` + frozen glyph + IDLE-DEAF — measured
on panes 316 and 317, where 317 was the session running this very investigation.
**Closure:** wire `SubagentStart` (present in the binary's registry, unwired today) +
`SubagentStop`, and add a `subagents` arm to `sb_idle_arms`. Two agents converged on this from
opposite ends.

---

## Producer-side traps that would have shipped broken

1. 🚨 **`Stop` does NOT fire when a turn dies on an API error — `StopFailure` does.** Without
   that arm a rate-limited pane stays painted "working" forever.
2. 🚨 **Do not use `Notification` for the permission edge.** Its `permission_prompt` is on a
   **6 s debounce**, so fast prompts emit nothing; `idle_prompt` is a 60 s timer suppressed while
   any dialog is up. **`PermissionRequest`** fires the moment the dialog is displayed.
3. A hook that runs a command and exits 0 does **not** alter control flow (the binary's own
   contract). Emit no JSON. Only exit 2 / `decision:"block"` / `continue:false` /
   `additionalContext` force a turn.
4. Hooks may return **`terminalSequence`**, allowlisted to OSC 0/1/2/9/99/777 + **BEL** — so the
   onset flash costs no fork and no socket. It is title + notification only, **never colour**.
5. A hook has **no `KITTY_LISTEN_ON`** under launchd — resolve via `bin/cc-kitty-socket`.
6. Pane ids are **volatile and reused** — key durable state on cwd/session_id and resolve the
   live pane at paint time (pid-ancestry against `kitty @ ls`, which is also transplant-proof).
7. Wiring goes in `migrations/00NN-<slug>.sh`, `# migration-class: c10`, **staged never self-run**,
   registered into each config dir's **`settings.json`** (migration 0019 measured that the
   user-level `settings.local.json` is *not* read as a hook source).

---

## Two defects found on the way (both pre-existing, neither caused by this work)

**A. The live kitty config was undeployed.** `~/.config/kitty/kitty.conf` pointed at
`/private/tmp/adn-land.v9Ngbj/…`, a land-staging tree since cleaned. **Repaired this session**
(`kitty-setup.sh --check`: 24 ok/1 missing → **25 ok, 0 missing**). It was also a prerequisite —
`kitty @ load-config` was failing, so any A/B measured an unreproducible baseline. The running
instance (up since Sep 9) held a good config in memory, so the exposure was the *next restart*,
which would also have dropped `allow_remote_control` and `listen_on` — silently breaking the whole
Agent-Teams spawn path, not just the colours.
- Root cause: `kitty-setup.sh:36` derives `$REPO` from `$0`. A guard for this exact failure exists
  at `:97-107` but its predicate is *"is a linked git worktree"*; the wanted invariant is
  *"is a durable path"*, so a standalone `/tmp` clone lands on the permissive default.
- `--check` detects it, but **nothing schedules `--check`**, and `deploy-parity-assert.sh:742`
  exempts the path by design — so the break was undetectable in practice.

**B. `--title` is sticky and permanently freezes a pane's liveness glyph.** `lr-lib.sh:340` and
`lr-handoff.sh:749` both warn about this, but **`bin/kitty-split-launch.sh:148` passes `--title`
unconditionally** and `bin/cc-offload:874` does too. Measured: **7 of 23 live panes are
permanently dark to the glyph signal.** Fix: pass `--temporary`, or drop `--title`.

---

## Prior art

No implementation ever existed. One prior design did and was never actuated:
`oversight-at-scale-2026-08-19/O2` §C3 — *"the renderer is wired, the harness has the emitter, and
nothing rings it… oversight is 100% pull."* `needs_attention` measured **False on 20/20** panes
today; `preferredNotifChannel` still unset everywhere. Operator wait on permission blocks:
**p90 28 min, p95 2.55 h, 7.8% over an hour.** That is the cost of the missing signal, in the
operator's own instrumentation. It was never filed — 0 backlog hits across 20,250 records.

---

## Residual — named, not hidden

- **The tint is UNVERIFIED BY EYE.** `screencapture -l` fails on background kitty windows, so no
  side-by-side was obtained. `bin/cc-kitty-wash demo` paints a live, fully reversible demo for
  exactly this reason. **The aesthetic call is the operator's and has not been made.**
- **Tier 2 (cross-Space) is designed but NOT built.** 20 of 21 panes are fully occluded — OS
  windows are full-screen and stacked one per Space — so Tier 1 solves only the Space in view.
- A single glyph sample is a coin flip: of 8 panes showing a frozen `◐`/`◑`, **2 were IDLE-DEAF**.
  Sample twice, ≥0.4 s apart, and treat *change* as the signal.
- Whether the glyph contract holds under real iTerm2 is unmeasured (every pane here is kitty).
