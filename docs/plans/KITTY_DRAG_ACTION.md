---
status: open
subsystem: kitty — begin a window drag from a front-end-drawn region
---

# KITTY DRAG ACTION — make the pane header we draw ourselves draggable

**Phase 2 of 3** (research → **plan** → implement). Phase 1 is landed and is the input to this
file: `docs/research/kitty-drag-action-implementation-2026-09-16.md` (1,904 lines, `dad60f772`).
**Read that file's § 10 before its §§ 1-9** — § 10 is a critic pass that re-opened 31 `file:line`
citations and found seven gaps in the body above it, and the body was deliberately *not* corrected,
so § 10 is the correction record rather than an appendix. Every ruling below that departs from the
body cites the § 10 subsection that moved it.

**Scope (frozen).** Implement, for real, the ability to BEGIN A KITTY WINDOW DRAG from a chord on a
region a front-end draws itself. Three self-recycled phases: research (DONE, landed `dad60f772`),
plan (THIS FILE), then implement to 100% — working, built, hand-verified, plus our own config
integration so the operator's styled pane header becomes draggable. **Posting anything to kitty's
upstream tracker is the OPERATOR'S call and is explicitly OUT of scope** — phase 3 produces the
patch, the build, the tests and the PR body; it does not open the PR.

---

## § 0. PHASE 0 — AGENT TEAM ORCHESTRATION

**Execution locus per wave — the FIRST field, because it decides whose context pays.**

| Wave | What | Locus | Size band | Why this locus |
|---|---|---|---|---|
| **W0** | Re-pin `tests/kitty-title-zero-shift.bats` — **DONE `ee0652933`**, discharged by a sibling while this plan was being written | — | — | — |
| **W1** | Fix the record (Q19): nine citation/claim corrections + the `cc-kitty-reload` header refutation | **S** · dispatched session | 20–40K · 1 unit | default |
| **W2** | Deliverable A — the config-only prototype kitten, both arming spellings, sandbox-only | **S** · dispatched session | 40–80K · 1 unit | default |
| **W3** | Deploy the kitten file (route A′: `scripts/` + absolute path) + the mandatory `kitty-conf-bindings` case | **S** · dispatched session | 20–40K · 1 unit | default |
| **W4** | **OPERATOR GATE — Q9/Q10/Q8/Q12 hand-drag session.** Not an agent wave. | **L** · lead-inline, and only to *hand over* | — | It needs a human hand on a real mouse. The lead's only job is to deliver ONE script that drives everything drivable and reads the verdict back; see § 5.W4. |
| **W5** | Deliverable B — the upstream patch against master (action + parser + accessor + changelog + tests) | **S** · dispatched session | 80–150K · 1 unit | default |
| **W6** | Deliverable B on v0.48.2 — backport build, incl. **adding** the master-only `mouse_left_press_x/y` field | **S** · dispatched session | 40–80K · 1 unit | default |
| **W7** | Our config integration — the armed-off `globinclude` drop-in, the § 7.1 retirements, the Q7 coupling test | **S** · dispatched session | 40–80K · 1 unit | default |
| **W8** | Recover + commit the `draghold` CGEvent driver **with its invocation** (Q18) | **S** · dispatched session | 20–40K · 1 unit | default; off the critical path but **time-boxed** — the only surviving copy is in a reapable scratchpad |

**T (teammates) is used nowhere in this plan and that is deliberate.** Every wave here is one
subsystem's files, verifiable on its own, with no member that must be synthesised against another
member *immediately*. The one wave that would tempt T — W5, the patch — is a single coherent diff
across four files in one clone; splitting it across teammates would put the merge loop in the lead's
window for no parallelism gain, which is the exact failure the S-default exists to prevent.

**Task dependency graph.**

```
W0 (unblock the land gate) ──► W1 (record) ──────────────┐
                          └──► W7 ...                    │
                                                         ├──► W4 (OPERATOR GATE: hand drag)
W2 (prototype kitten) ──────► W3 (deploy, route A') ─────┘          │
                                                                    ├──► W7 (config integration)  [GATED ON W4]
                                                                    └──► W5 (patch/master) ──► W6 (patch/0.48.2)
W8 (draghold recovery) — independent; run it EARLY, not last (see W8)
```

- **W0 blocked W1 and W7** — both edit `config/kitty.conf`, which selects a suite that was red on
  trunk. This edge is the one the first draft of this plan missed entirely; the wave is now **DONE**
  (`ee0652933`), so the edge is discharged rather than removed.
- **W2 blocks W4**: the hand drag needs something to drag from.
- **W4 blocks W7 ABSOLUTELY.** See § 2. W7 is the only wave that can reach the operator's live
  panes, and it may not start until a human has driven the gesture in a sandbox.
- W5/W6 do **not** block on W4 for *correctness* — the patch's design is settled here — but W4's
  answers to Q9 and Q10 are the last input that could change B's *shape*, so W5 SHOULD follow W4
  where scheduling allows. If it does not, W5 ships the design ruled in § 4 and W4's findings are
  folded as a follow-up commit.

**Worktree assignments.** One worktree per wave, branched off `origin/main`, named
`feat/kitty-drag-w<N>-<slug>`. **Never work in `~/Development/claude-infrastructure`** — it is the
symlink source for `~/.claude` and a commit there is a fleet-wide converge block
(`.claude/CLAUDE.md` § Never commit or land in the shared checkout). W2/W5/W6 additionally use the
kitty build trees, which are NOT worktrees of this repo and are shared read-write across waves:
`/private/tmp/kitty-dev` (master `1d67ecd`, built) and `/private/tmp/kitty-482` (v0.48.2, built).
**Serialize W5 and W6** — they edit the same two trees.

**Lead context budget + succession point.**

- **Reserved for leading: ≥50%.** The lead of phase 3 holds half its window for deciding, per
  CLAUDE.md § Context Stewardship. Every wave above is dispatched precisely so the lead pays for
  the brief and a one-line completion ping, not for the implementation detail.
- **Succession point: after W4.** W4 is a human gate whose answer may re-shape W5-W7, and it is the
  natural seam: everything before it is disk-reconstructible (landed commits + this plan), and
  everything after it is re-briefed from W4's verdict. The phase-3 lead recycles there
  (`handoff-fire.sh --recycle`), not at a context threshold. A second succession point sits after
  W6 if the window is tight.

**Every dispatched brief in this plan MUST carry, verbatim:**

1. The § 2 safety block (below). It is not optional context; it is the constraint that makes the
   wave safe to run at all.
2. **"Never put `rm -r`, `rm -rf`, `git clean`, `kill`, or `pkill` in a command."** This box's
   PreToolUse hook escalates those to a permission prompt, **and a subagent cannot answer a
   permission prompt** — it wedges forever. Phase 1 lost three research agents and one whole
   synthesis stage to exactly this.
3. A `--goal` naming one measurable end state, the command that PRINTS the proof, and the
   constraint that must hold. Per-wave goals are in § 5.

---

---

## § 1. PHASE 1 — DONE (`dad60f772`, corrected in place by `76b2795d2`)

Compacted per the plan conventions; the full record is the research doc itself. **Do not re-derive
any of this.**

**The verdict.** The capability is reachable **today**, on stock kitty 0.48.2, **with config only**,
and was driven end to end on the shipped binary. So **the patch buys correctness and cost, not
capability** — see § 3 for the four things it buys that route A provably cannot have.

**The one mechanism everything rests on**, re-verified by this session in both trees with a positive
control:

```
master mouse.c:1427  ==  v0.48.2 mouse.c:1362      (byte-identical)
} else if ((r.in_title_bar && r.window) || global_state.window_being_dragged.id) {
                                           ^^^ no title-bar term in the second disjunct
no C-side clear of window_being_dragged anywhere in either tree
POS CTRL: the tab equivalent DOES have one — zero_at_ptr(&global_state.tab_being_dragged) v mouse.c:951
```

**Read § 10 before §§ 1-9.** § 10 is a critic pass that re-opened 31 citations and found seven gaps
in the body above it. Three of those were since corrected **in the body** (`76b2795d2`, each marked
`CORRECTED 2026-09-16`): `set_mouse_position` is in **both** refs, not v0.48.2-only; the `no_ui`
handler takes the window id **third**, not second; and `dnd_test_set_mouse_pos` does **not** drive
`w->drag_source`. **§ 10's other four gaps remain uncorrected in the body BY DESIGN** — § 10 is the
record for those, and this plan folds them in: the live-converge safety finding (§ 2 here),
`OSWindow.mouse_left_press_x/y` existing on master (Q2), the § 6.5 `dnd_test_*` inversion (W5), and
the missing deployment path (W3).

**Key learnings that shaped this plan, not repeated below:** a line number without its ref lands a
reader in a different function (the trees differ in six places, not five); a chord probe needs two
known-TAKEN positive controls or a mis-numbered GLFW button reads as a free chord; and phase 1's
skeptics defaulted `refuted=true`, so most "REFUTED" rows are confirmations carrying a correction —
**judge on `correctedClaim`, never on the boolean.** Full list: § 8.

## § 2. 🚨 THE SAFETY CONSTRAINT — a landed config line arms the operator's live terminal by itself

**This is the finding that shapes the whole staging, and no phase-1 research axis covered it.**
It is § 10.2 of the research doc, and it was **reproduced independently by this session**:

```
$ readlink ~/.config/kitty/kitty.conf
/Users/chrisren/Development/claude-infrastructure/config/kitty.conf      ← the SHARED CHECKOUT

$ ps -axo pid=,command= | grep __watch_conf__
97219 /Applications/kitty.app/Contents/MacOS/kitten __watch_conf__ 97084 100 \
      /etc/xdg/kitty/kitty.conf /Users/chrisren/.config/kitty/kitty.conf
```

🚨 **THE PID IN THIS SECTION IS STALE, AND THE WAY IT WENT STALE IS THE REUSABLE PART.**
**CORRECTED 2026-09-16 (phase 3), AND THE CORRECTION ITSELF WENT STALE INSIDE ONE HOUR — which is
the real lesson.** The box rebooted at 15:50 and `97084` no longer existed, so this was first
corrected to *"the live kitty is pid 633, socket `/tmp/kitty-633`"*. A second kernel panic at 16:28
made that false too, and **far worse than merely false: `ps -p 633` now returns
`calaccessd`, the system calendar daemon.** The pid was not just freed, it was REUSED by an
unrelated live process — so a rule reading "never signal pid 633" had, within the hour, become a
rule pointing at Calendar. An identity-keyed refusal does not decay into harmlessness; it decays
into a loaded gun aimed somewhere new. The live kitty is **pid 597** as of 17:05, and that number
will be wrong too. The original number is left above rather than overwritten, because the number was
never the point — **an identity-keyed refusal reads as SATISFIED once its subject is gone.** Every
brief in this phase carried "never signal pid 97084"; after the reboot each one named a process that
did not exist, so the constraint was trivially true while the real terminal was unnamed and
unprotected. A wave could have signalled pid 633 in full compliance with its own safety block.

⇒ **Key the refusal on something IDENTITY-FREE.** `scripts/kitty-drag-w4.sh` refuses any socket
matching the `/tmp/kitty-*` glob, which is how kitty names every live control socket, so it cannot
go stale across a reboot, a restart, or a second instance. Prefer that shape to any pid, and read a
pid in a safety rule as a *perishable fact* of exactly the kind § 8 item 9 and the ship-policy table
warn about — correct when written, silently false later, and failing in the direction that looks
fine.

⚠️ *Collateral, recorded because it was self-inflicted:* phase 3 created `/private/tmp/kitty-dev` and
`/private/tmp/kitty-482` as symlinks to the durable trees so this plan's literal paths keep
resolving — and those names now match that same `/tmp/kitty-*` glob. They are **directories, not
sockets**, so a correct consumer that tests for a socket is unaffected, and a glob-only consumer
becomes *more* conservative, never less. Noted so the next reader is not surprised by two extra
glob hits.


`97084` is the operator's live kitty; `100` is the debounce in ms. The watcher resolves symlinks
whole (`tools/watch/api.go:86-91`) so it watches **`~/Development/claude-infrastructure/config/`** —
the directory `deploy-live.sh` fast-forwards on every converge — and `unix.Kill(kitty_pid, SIGUSR1)`
at `api.go:223-225` reloads the config. `auto_reload_config` defaults to `0.1` s
(`kitty/options/definition.py:2927-2930`, v0.48.2) and our config never overrides it.

**Therefore a landed `mouse_map … kitten kitty-drag-window.py` line becomes live in the operator's
11-13-pane terminal ~100 ms after the shared checkout advances — at CONVERGE time, not at test
time.** And route A's two worst failure modes are not cosmetic:

- **THE WEDGE** (research § 3.5 #1). There is **no C-side clear of `window_being_dragged` anywhere
  in either tree** — positive-controlled grep; the tab equivalent `zero_at_ptr(&…tab_being_dragged)`
  exists at master `mouse.c:981` / v `:951`, so the instrument works and the null is informative.
  The only mouse-driven clear is a **LEFT** release through arm 7. A flag left set routes every
  mouse event in every OS window to the title-bar handler permanently — killing selection, URL
  detection, border resize and click dispatch across the whole fleet.
- **BUTTONLESS SYSTEM DRAG** (§ 3.5 #2). Once wedged, the next bare pointer move past
  `drag_threshold` starts a **real system drag with no button held**. Verified in the shipped
  0.48.2 bytecode: the motion block contains no `mouse_button_pressed` reference at all.

### § 2.1 The rules this imposes on every wave

| # | Rule | Binding on |
|---|---|---|
| **S1** | **No wave before W7 may write `config/kitty.conf` in a way that changes BEHAVIOUR.** Comment-only edits (the Q19 corrections) are permitted and are argued safe in § 4 Q19 — a reload with identical semantics is a no-op. | all waves |
| **S2** | **All route-A prototyping happens in a sandbox config dir**, `KITTY_CONFIG_DIRECTORY=<own /private/tmp dir>`, never in `~/.config/kitty` and never in the shared checkout. Research § 6.3 has the verified recipe. | W2, W4 |
| **S3** | **The kitten FILE lands before the line that names it.** A `mouse_map … kitten X.py` whose file is absent raises `FileNotFoundError` inside `import_kitten_main_module` (`kittens/runner.py:59`), which `Boss.combine` catches into `show_error('Key action failed', …)` **and consumes the press** — i.e. an error overlay in his live panes on every chord press until fixed. This is why W3 precedes W7. | W3 → W7 |
| **S4** | **Never assume a land is inert until someone reloads.** It is not (above), and even with the watcher absent, `deploy-live` calls `cc-kitty-reload` every 600 s. | all waves |
| **S5** | **This agent shell already points at the operator's kitty** — `KITTY_LISTEN_ON=unix:/tmp/kitty-97084`, `KITTY_PID=97084`. A bare `kitten @ <cmd>` **drives his terminal**. Every sandbox command must be prefixed `env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID`, and the sandbox socket must live **outside** the `/tmp/kitty-*` glob (`bin/cc-kitty-socket` scans it and `scripts/kitty-pane-title-overlay.py:683` returns `None` when it finds more than one). | all waves |
| **S6** | **Never signal pid 97084.** No `kill -USR1`, no anything. | all waves |

### § 2.2 🚨 MEASURED THIS SESSION — the reload is COMPLETE, so the recovery path is an edit, not a restart

§ 10.2 left one thing unmeasured that decides how hard the staging rule must be: **is the SIGUSR1
reload partial?** If it only re-read some options and left the already-built mousemap in place, then
a bad `mouse_map` reaching his live kitty could be withdrawn **only by restarting his terminal** —
killing 11-13 live Claude sessions. Measured end to end in a sandbox reproducing his exact symlink
topology, triggered by the sandbox's own `__watch_conf__` child (**no signal was sent by anyone**):

```
kitty/config.py:134    mousemap: MouseMap = {}      ← a FRESH dict on every reload
kitty/config.py:141    opts.mousemap = mousemap
kitty/window.py:1399   action = get_options().mousemap.get(ev)   ← read LIVE at every click, no cache

sandbox 0.48.2, own config dir, socket outside /tmp/kitty-*:
  T0 baseline                        mousemap_len 33   [POS CTRL cursor_blink_interval 1.5 ]
  T1 change the action + the control  33               [POS CTRL              -> 0.25]  action CHANGED
  T2 delete the line                  32               [POS CTRL               0.25]   binding GONE
  T3 override a shipped kitty default …                                                default RESTORED on revert
  NEG CTRL: an unedited mouse_map line read back byte-identical at every step
```

**Verdict: the reload rebuilds `opts.mousemap` completely, from a fresh empty dict, and
`merge_result_dicts` builds new lists so reloads cannot accumulate. A bad line is fully withdrawable
in place, through the symlink, in ~3 seconds, including restoring an overridden kitty default. A
restart of his terminal is NOT the recovery path.**

**So the rule softens from "never land the arming line" to "stage it and keep the withdrawal path
open" — and the probe also found the mechanism that makes landing safe by construction.**

| # | Finding | What the plan does with it |
|---|---|---|
| **M1** | **`globinclude drag-arm.d/*.conf`** (or `envinclude`) is silent when empty and arms by a file write, which **does** fire the watcher | **W7 lands the arming line in a `globinclude`d drop-in, empty by default.** Arming is a one-line write the operator makes; disarming is emptying it. Landing the plan's diff arms **nothing**. |
| **M2** | 🚨 **Deletions never fire the watcher, at any level** | **Disarm by EDITING THE FILE EMPTY, never by deleting it** — or by also touching the top-level `kitty.conf`. Both measured. A plan that says "delete the file to disarm" is wrong. |
| **M3** | 🚨 **An in-kitten guard is NOT a safety mechanism.** A `mouse_map … kitten …` **always consumes the event** regardless of what the kitten returns (`boss.py:2405` discards it) — proven live, with the not-consumed channel controlled: `kitten @ action "definitely_not_an_action"` → rc **1**, the declining kitten → rc **0** | **Never gate safety on the kitten's own return.** A guard makes the ACTION inert and leaves the BINDING live, so any chord with a useful default has that default **silently dead**. This kills the obvious "ship it behind a sentinel-file check" design. |
| **M4** | 🚨 **"Just don't deploy the kitten file" is the WORST state**, not the safe one — `show_error('Key action failed')` on every click **and** the default still lost | **Confirms and strengthens S3.** The file lands first, always. |
| **M5** | **He already lands `mouse_map` lines through converge — three of them, live** | The novel risk is the **kitten dispatch**, not the config-line class. § 2 is calibrated accordingly: this is not a reason to treat every kitty.conf edit as radioactive. |
| **M6** | Narrow residual: a converge racing an explicit `kitty @ load-config` — which `scripts/kitty-pane-title-toggle.sh:92` fires — during a file-absent window would load **pure defaults**. The watcher alone cannot cause this | One line in W7's checklist: do not land a config change while that toggle script can fire. W7 retires that script anyway (§ 7.1). |

⚠️ **What this does NOT soften: the WEDGE is C state, and no config reload clears it.**
Withdrawing the line stops new arming; it does **not** clear a `window_being_dragged` that has
already leaked, because there is no C-side clear (verified this session, with the tab
`zero_at_ptr(&global_state.tab_being_dragged)` at v `mouse.c:951` as the positive control proving the
null is informative). The leaked flag self-cures on the next LEFT press/release, so it is disruptive
rather than permanent — but between the leak and that click, a bare pointer move past
`drag_threshold` starts a real system drag with nothing held. **The config is withdrawable in
3 seconds; the wedge is cured by a click. Neither is cured by the other.**

### § 2.3 What this does NOT forbid

The correct reading of § 2 is *stage the arming line*, not *never touch kitty config*. Specifically
permitted, and needed: comment corrections to `config/kitty.conf` (Q19), any edit inside a
**worktree** that is not landed until its wave's gate passes, the whole of W2 in a sandbox, and the
`draw_minimal_borders` / padding experiments of W4 — in a sandbox.

---

## § 3. THE TWO DELIVERABLES, AND WHY BOTH SHIP

Phase 1's headline result reframes the project: **the capability is reachable TODAY on stock kitty
0.48.2 with config only**, and was driven end to end on the shipped binary. `mouse.c` arm 7
(`(r.in_title_bar && r.window) || global_state.window_being_dragged.id`, master `mouse.c:1427` /
v `:1362`, byte-identical) routes on that flag alone with **no title-bar term in the second
disjunct**; a `no_ui` kitten runs synchronously inside the kitty process holding the `Boss`; and on
macOS `_glfwPlatformStartDrag` fabricates an `NSEvent` when none is live.

**So the patch buys CORRECTNESS AND COST, not capability.** Precisely, it buys four things route A
provably cannot have:

1. **The press-instant origin.** Route A's best spelling captures the pointer at the *first motion
   event after* the press, not at the press (research § 3.3 route (i)).
2. **No per-press `open()` + `read()` + `compile()` + `exec()`** — `kittens/runner.py:53-66` does all
   four on **every** invocation, measured 0.1945 ms, on the gesture path.
3. **A supported binding** instead of a monkeypatch of two private methods whose spelling already
   drifted between the refs (`Boss.request_thumbnail` is master-only; `request_callback_with_thumbnail`
   takes 6 args at 0.48.2 and 7 on master).
4. 🚨 **PASSTHROUGH.** `Boss.kitten` (v `boss.py:2405-2406` / master `:2669-2671`) is a bare call with
   **no `return`**, so `dispatch_action`'s `passthrough` is always `None` and **the press is always
   consumed**. A config-only handler that decides "this press was not in our header band" *cannot*
   pass it through to the program. This is the single strongest argument for B and it is what makes
   Q13's answer matter.

**Ruling: both ship, A first.** A is a ~30-line kitten plus one config line; it answers Q9 and Q10 —
the only two open questions that can still change B's design — and it positive-controls the patch: if
A's drag behaves correctly, B is provably just a faster, threshold-correct spelling of the same
thing. See § 4 Q1.

**The staging, which § 2 forces:**

```
  W2  prototype in a SANDBOX config dir          ── nothing of the operator's is touched
  W3  land the kitten FILE + its deploy wiring   ── INERT: no config line references it (S3, M4)
  W4  OPERATOR hand-drag in the sandbox          ── the gate; answers Q9, Q10, Q8, Q12
  W7  land the arming line in an EMPTY globinclude drop-in   ── lands ARMED-OFF (§ 2.2 M1)
      the operator writes one line into that drop-in         ── arms in ~100ms, withdrawable in ~3s
```

**W7 is operator-gated, and § 2.2 changes what that gate is for.** Every other decision in this plan
is ruled here and driven without re-asking, per the Follow-On Gate. W7's gate survives for one reason
only, and it is not the blast radius: **its precondition — Q9, a real hand on a real mouse — is
physically unavailable to an agent.** The impossibility class is *physical*, not judgemental.

The blast-radius half of the argument is **measured away** by § 2.2: W7's diff lands **armed-off**
into an empty `globinclude` drop-in, so landing it reaches nothing; arming is one line the operator
writes; and a bad line is withdrawable in ~3 seconds with no restart and no session loss. So W7 is
not a `⛔` waiting on courage — it is a wave whose last step is a human gesture, which is a different
and much smaller thing. **Phase 3 should land W7 armed-off without asking, and ask only for the
arming line.**

---

## § 4. RULINGS ON THE 24 OPEN QUESTIONS

Research § 8 lists 24. Every one is ruled below, or explicitly deferred **with the reason and with
the instrument that will settle it**. Format: **RULED** (decided here, phase 3 executes) ·
**DEFERRED** (phase 3 decides, with the criterion) · **OPERATOR** (genuinely theirs) ·
**OUT OF SCOPE**.

### Q1 — Do both deliverables ship, and in what order? — **RULED**

**Both ship. A first, then B, with A's *landing* split across W3 and W7 by § 2.** The corpus is
unanimous on A-first and § 10.2 does not change the order — it changes the **staging**, which is why
"A first" here means *prototype and validate A first*, not *land A's arming line first*. A answers
Q9 and Q10, costs ~30 lines plus one config line, and positive-controls the patch.

**A is not retired when B lands.** B must be built, and on this box that means a patched kitty the
operator would have to run instead of `/Applications/kitty.app`. Until an upstream release carries
the action, **A is the shipping implementation and B is the durable one.** Phase 3 must not write
A as throwaway.

### Q2 — Arm with `drag_started=True` or `drag_started=False`? — **RULED (and § 10.3 moved it)**

**B arms with `drag_started=False` — threshold-preserving.** The research body (§ 4.4) framed this
as 1 file vs 3 and priced the `False` branch as needing *"a new accessor … which no Python getter
returns"*. **§ 10.3 refutes the expensive half:** the press-instant origin **already exists on
master**:

```
master kitty/state.h:552      double mouse_left_press_x, mouse_left_press_y;   ← in OSWindow
master kitty/glfw.c:681-686   window->mouse_left_press_x = window->mouse_x;    ← written HERE
                              if (is_window_ready_for_callbacks()) mouse_event(...);  ← 3 lines later
v0.48.2:  grep -rn mouse_left_press kitty/ glfw/  →  rc 1, ZERO hits           ← MASTER-ONLY
```

Three properties decide it, all read off those lines: it is written **from `window->mouse_x`**, the
*same* framebuffer-pixel space `set_window_being_dragged` wants (the existing producer at master
`mouse.c:965` passes `osw->mouse_x`) — so no conversion and none of the origin mismatch V1 warns
about for `global_x/global_y`; it is written **three lines before** `mouse_event(...)`, so an action
dispatched from that press reads *this* press's origin; and it is currently read by exactly one
consumer (a shader uniform, master `shaders.c:2583-2584`). The work is **exposing a field, not
inventing a capture mechanism** — two keys in the `Py_BuildValue` § 4.4 already names, or a
three-line getter.

**Why threshold-preserving rather than the free `True` shortcut:** `drag_threshold` documents itself
as *"A value of zero disables all dragging"* (master `definition.py:1170`). An action that silently
ignores a documented option is a review objection waiting to happen and a surprise in use. And with
the accessor landed, **pixels become the free and better region unit**, which is what lets Q3 and Q7
be answered cheaply.

⚠️ **Carry § 10.3's caveat, because it compounds with Q24.** The field is written on **every** LEFT
press anywhere in the OS window and is **never cleared** — it is a *last left press* value, not a
*current gesture* value. Dispatched synchronously from the press, that cannot bite. On
`drain_actions`' timer it can, and **stale is worse than NULL**: NULL crashes loudly under the
customary guard, stale silently arms at the **wrong origin**. See Q24.

**For deliverable A, the prototype, the ruling is different and deliberate: implement BOTH
spellings behind one switch.** Route (i) threshold-preserving (wrap `boss.handle_window_title_bar_mouse`,
capture the first delivered pixel pair) and route (ii) threshold-free
(`set_window_being_dragged(wid, True, 0, 0)` then `request_callback_with_thumbnail`). The delta is
~10 lines, and § 8 Q9 names *"whether threshold-less behaviour is objectionable in use"* as a
sub-question only a hand can answer. Shipping one spelling forfeits that answer for free.

### Q3 — `rows` argument, no argument, or a global OPTION? — **RULED**

**An optional positional `rows: int = 0` argument on the action** (`0` = the whole window), exactly
as research § 4.6's ready-to-paste doc text already writes it. Against V29's real point that kitty
scopes the adjacent mouse region with a *global option* (`window_drag_tolerance`), and against A6's
"take none in v1":

- The region is a property of **this binding in this pane style**, not of kitty. A user with two
  differently-drawn panes needs two values; an option cannot give them.
- A new option **drags `kitty/options/definition.py` and the regenerated `kitty/options/types.py`
  into the diff** (§ 4.2 row 6, measured by executing kitty's real generator). § 4.2's own ruling is
  to ship **no** default `mouse_map` for exactly this reason. An argument costs one
  `@func_with_args` parser in `kitty/options/utils.py` and nothing generated.
- "Take none in v1" forfeits the only thing the feature exists for on this box — a header band that
  is draggable while the rest of the pane still belongs to the program.

🚨 **Unit note — CORRECTED by this session's measurement wave; the first draft of this ruling had it
backwards.** I drafted "the argument is rows, the predicate is evaluated in pixels", on § 4.4's
"pixels are strictly the better unit". **Measured, the region predicate is CELLS, and the choice is
forced, not preferred:** `global_x`/`global_y` **have no Python read path in either tree** —
`get_mouse_data_for_window` returns exactly three keys, verified by direct read:

```
v0.48.2 kitty/state.c:1742-1743
    return Py_BuildValue("{sI sI sO}", "cell_x", ..., "cell_y", ..., "in_left_half_of_cell", ...);
```

So a pixel *region* predicate is unreadable from Python, and choosing it would silently convert
deliverable A into an upstream patch. And § 4.M/Q7 measures that pixels buy **nothing** for the
region anyway. **The ORIGIN needs pixels (Q2's accessor, for `drag_threshold`); the REGION is cells.
They are two different jobs and § 4.4's single "pixels are better" sentence conflates them.** Full
reasoning and the sweep: § 4.M/Q7.

### Q4 — Name, class and group — **RULED, with the last word deferred to review**

**`mouse_drag_window`, defined on `Window`, group `mouse`** — A12's reading, which research § 4.3
already recommends and which is *measured* where A6's is idiomatic.

- All eight `mouse`-group actions live in one contiguous `# mouse actions {{{` block in
  `kitty/window.py` (master `:2003-2092`); six of the eight carry the `mouse_` prefix, and the two
  that do not are exactly the two whose behaviour does **not** depend on where the pointer is. This
  action's behaviour does.
- `self` **is** the window under the pointer for a mouse dispatch (`window.py:1420`), so no
  `window_for_dispatch` line is needed.
- **The group is mechanically inert** — measured, not inferred (V6): a bytecode census of the shipped
  binary finds zero group references in `dispatch_action` / `combine` / `drain_actions` /
  `on_mouse_event`, with a positive control that fires. The choice buys **discovery only**.

🚨 **Settled facts phase 3 must not relitigate:** do **not** name it `start_window_drag` —
`Boss.start_window_drag` exists in both refs with five required positional arguments and
`dispatch_action` resolves Boss first by bare `getattr`. And define it on **exactly one** class:
V26 measured that the Boss-side collision is **SILENT** (Python keeps the last definition, the new
action works, and the incumbent title-bar drag dies at thumbnail-callback time with *"takes from 1
to 2 positional arguments but 6 were given"* — no config error, no popup, nothing a "no errors in
the log" test would catch).

**Deferred half:** the final name/class/group is a taste call by the one person who decides. Ship
A12's, and put one sentence in the PR body offering A6's `Boss`/`win` framing as the graceful
fallback (cost: one `window_for_dispatch` line). That is the correct disposition for a question
whose answer lives in another person's head — not an agent's to guess, and not a reason to stall.

### Q5 — Does the `on_window_drop` ordering fix ship with the action? — **RULED**

**Yes — but as a SEPARATE COMMIT inside the same PR.**

A4 said "describe the divergence as pre-existing and out of scope." **V10 refutes that and has
better evidence:** at `window_title_bar_min_windows 0` (the default in **both** refs) no window has
a title-bar hit region at all, so **no title-bar drag can be started** — the defect requires
`toggle_window_title_bars` to have been pressed first, a precondition A4 never stated. **A
content-press action removes that precondition, making our action the first path that reaches this
divergence in kitty's stock default configuration.** Shipping the action alone therefore knowingly
introduces a user-visible wrong-behaviour path: `on_window_drop` calls
`_clear_force_show_title_bars()` **before** classifying the pointer (master `:2202` before `:2234`;
v `:2035` before `:2074`), so the preview draws quadrant 5 ("swap") over a drop that performs a
directional insert — executed and measured, with `min_windows 1` as the control that emits SWAP.

**Why a separate commit rather than one diff:** the fix touches shared drag code, and the
maintainer must be able to take the feature without it. One commit = one revert. V10 supplies the
nuance against itself that belongs in the commit message: the post-drag *clear* is documented
behaviour (`toggle_window_title_bars`'s own docstring), so only the **ordering inside
`on_window_drop`** is arguably a bug.

### Q6 — Does the patch try to suppress the force-show? — **RULED: NO**

Three reasons, in decreasing order of force:

1. **It is not reachable from the action** (V3). `window_being_dragged` is a four-field struct with
   no room for intent, and the force-show executes inside `TabManager.start_window_drag`, which the
   action never calls — the *thumbnail callback* does. Suppression means editing shared drag code or
   adding a struct field.
2. **What it buys is only the drag-over PREVIEW**, because the drop decision already runs after the
   clear (§ 5.15). The genuine loss is same-tab drops in `axis_x`/`axis_y` and Splits layouts.
3. **It would get the PR judged on the wrong diff.** The maintainer's single sharpest recorded review
   objection is about `set_geometry()` cost; arriving with a restructure of shared drag state
   attached to a new-feature PR invites exactly that.

**What phase 3 does instead:** state in the PR body, in one sentence, that the action inherits the
existing force-show via `start_window_drag` and calls `set_geometry()` itself zero times — § 4.7
item 6's pre-emptive pricing. Record the measured cost in this plan's § 7 so it is not lost: a PTY
resize (SIGWINCH to every child, down at drag start and back up at drag end, twice per pane in every
tab of every OS window), **plus** a second row per OS window showing fewer than `tab_bar_min_tabs`
tabs (V31), **plus at least four relayouts per tab, not two**, **plus** it clears the operator's
toggled-on bars machine-wide because `_clear_force_show_title_bars` iterates `boss.all_tab_managers`
while `toggle_window_title_bars` only ever sets the flag on `self.active_tab_manager`.

### Q9 — Does a real hand drag from our band work end to end? — **OPERATOR (W4), and it is the gate**

**Not deferred out of indifference — physically unavailable to an agent.** It needs a genuine
left-button press inside a sandbox window and real pointer motion; synthesising it moves the
operator's real cursor while he is working. It is ~60 seconds of his time, and § 10.2 raises its
stakes: it must be answered **in a sandbox config dir** before the arming line goes anywhere near
`config/kitty.conf`.

**Success criterion, stated so the answer is unambiguous:** the pane's thumbnail follows the cursor
and the pane re-orders on release. **Second answer it yields for free:** whether threshold-less
behaviour (Q2 route (ii)) is objectionable in use — which is why W2 ships both spellings.

**W4 is delivered as ONE executable script, not a worksheet.** See § 5.W4.

### Q10 — Does the graphics placement survive the drag's relayout? — **DEFERRED to W4, cannot block**

`start_window_drag` relayouts every tab → resizes PTYs → children redraw, and the overlay's own
docstring says kitty frees a placement *"whenever its anchoring cells are cleared or scrolled away"*
(`scripts/kitty-pane-title-overlay.py:25-28`). **Answered in the same sandbox session as Q9** — the
operator's hand is already on the mouse and a mid-drag screenshot is free at that moment.

**It cannot block either deliverable**, and phase 3 must not treat it as a gate: if the placement
does not survive, the overlay vanishes mid-drag and the 2 s refresh loop repaints it afterwards.
That is cosmetic. It is worth knowing **before it arrives as a bug report**, which is the entire
reason it is on the W4 checklist rather than dropped.

### Q12 — Which chord? — **RULED: `cmd+shift+left press`, with W4 free to overturn it**

The research body calls `cmd+left press` "best on every other axis" and names its one cost: it
**silently kills `cmd+left click → mouse_handle_click link`** (`config/kitty.conf:821`), because
arm 7 swallows the release so the `click` is never synthesised (§ 3.5 #7).

**That cost is larger than the body prices it, and this session read the provenance to find out.**
That binding is not incidental — it was built deliberately, to a problem the operator described, and
its ten-line rationale block says so in his own record:

```
config/kitty.conf:814-772  (commit 175eeb7d8, "feat(kitty): cmd+click opens links in Dia, in TUIs too")
#      which is exactly the "not always" the operator described.
# THE FIX IS A BINDING THAT IS LINK-ONLY AND GRAB-INDEPENDENT.
mouse_map cmd+left click grabbed,ungrabbed mouse_handle_click link
```

Silently undoing a fix built to his own complaint is worse than one extra modifier.
`cmd+shift+left press` was measured **FREE in both modes** on the loaded config with two
positive controls reading TAKEN (§ 7.3), it keeps the link click alive, and two modifiers is the
more deliberate gesture for something that rearranges his panes.

**Rejected, with reasons:** `ctrl+alt+left press` is kitty's shipped `mouse_selection rectangle`
(`definition.py:1285` v / `:1320` master) — ⛔ and it is the chord the existing upstream draft
wrongly uses (Q19 fixes it). `ctrl+cmd+left` collides with macOS right-click emulation. `opt+left`
takes the modifier this config deliberately hands to the application. Bare `left press` removes
plain drag-select from every pane.

**`cmd+left doublepress` is a real fourth option and is NOT rejected — it is W4's to try.**
§ 10.6(b) corrects the body's trigger-count map, which drops two members:

```
# v0.48.2 kitty/options/utils.py:60
mouse_trigger_count_map = {'doubleclick': -3, 'click': -2, 'release': -1, 'press': 1,
                           'doublepress': 2, 'triplepress': 3}
```

`doublepress` is a **press**-family trigger (positive count), so it fires synchronously like `press`
and does **not** wait for `click_interval` — and it was measured FREE in both modes. It would leave
`cmd+left click → link` alive *and* keep the single-modifier chord. Its cost is ergonomic (press,
release, press-and-hold-and-drag) and it interacts with § 3.5 #6's rename prompt. **This is exactly
the class of question 60 seconds of hand-time settles and no amount of reading does**, so W4 tries
all three and the operator picks. Shipping `cmd+shift+left press` as the default costs one word to
change afterwards.

### Q13 — If band-scoping is required, does that alone decide against route A? — **RULED: no, but it bounds A's role permanently**

**Measured and near-settled already:** `Boss.kitten` discards its return value, so a config-only
handler **always consumes** the press and cannot pass an out-of-region press through to the program
(§ 3.4, measured — a handler returning `True` still gave `dispatch_action -> true`). Route A is
therefore scope-capable only in the degenerate sense of *"arm, or do nothing, but always swallow"*.

**Ruling: accept the unscoped chord for route A.** It is acceptable here and the reasons are
specific, not hand-waved: the chord is two deliberate modifiers; `drag_threshold 5` means a press
that does not move is a no-op; and **our own config already ships two unscoped `mouse_map` lines**
(`right press` → pane menu, `config/kitty.conf:182-183`) that nobody has complained about.

🚨 **But record the consequence, because it is the clearest statement of why B exists.** Under A,
the chord is swallowed **everywhere in the pane**, including over Claude Code's composer. Under B,
a press below the header band **returns `True` and passes through** to the program. That is the
whole of Q13's answer and it is the answer to anyone later asking whether B is still worth building
once A works. It is.

### Q14 — Is the buttonless-promotion hazard worth an upstream report on its own? — **RULED: no separate report; it is the patch's own justification**

The motion path has **no button-held test in either ref**, so any leaked `window_being_dragged`
escalates to a real system DND with nothing held. It is pre-existing and **currently unreachable** —
the flag can only be set from a path whose release clears it. **A content-press action is what makes
it reachable**, so it is not a standalone bug report; it is a consequence of *our* feature and
belongs inside *our* PR, as the stated justification for guard 1 (arm only for
`GLFW_MOUSE_BUTTON_LEFT`) and guard 2 (refuse to arm when another drag state is live).

**Scope note:** whether anything at all is *posted* upstream is the operator's call and out of
scope. This ruling is about what the patch's PR body **says**, not about filing.

### Q15 — Does the `Tab*`-realloc hazard need a note or a guard? — **RULED: one sentence in the PR body, no guard**

`handle_button_event` takes `Tab *t = osw->tabs + osw->active_tab` **before** the synchronous Python
dispatch and dereferences it after, re-deriving only `w` and re-deriving it *through* the stale `t`,
while `add_tab` reallocs `os_window->tabs` (`ensure_space_for` = `realloc`,
`data-types.h:287-294`). A `combine` chain ending in `new_tab` reads freed memory, **in both refs**.

It is pre-existing, latent, and **adjacent evidence that the action must stay minimal** — which is
exactly the framing § 4.5 gives it and exactly what makes it useful in the PR body rather than as a
guard. A guard is scope the feature does not need. What the patch *does* inherit is a constraint on
its own doc text: keep the action's synchronous work minimal and free of tab creation.

### Q16 — Patch master, build 0.48.2, or both? — **RULED: both, and both trees are already built on this box**

`/private/tmp/kitty-dev` (master `1d67ecd`) and `/private/tmp/kitty-482` (v0.48.2) both exist with a
built launcher, and `go 1.27.1` is on PATH — verified this session. Master is what an upstream PR
must target; a patched 0.48.2 is the drop-in comparison against the operator's daily driver, which
removes a whole class of *"does this reproduce on the installed build"* ambiguity.

**Three constraints phase 3 must carry:**

1. **The test targets master ONLY.** `kitty_tests/base.py` is master-only; on 0.48.2 `BaseTest`
   lives in `kitty_tests/__init__.py` and `selection_drag.py`/`tab_drop.py` do not exist at all. Do
   **not** verify the patch by running the suite under `/Applications/kitty.app`. The 0.48.2 build
   is verified by sandbox and by hand, not by `./test.py`.
2. 🚨 **The 0.48.2 backport is NOT the same diff** — this follows from Q2 and is easy to miss.
   `OSWindow.mouse_left_press_x/y` is **master-only** (`grep -rn mouse_left_press kitty/ glfw/` in
   v0.48.2 → rc 1, zero hits). A threshold-preserving 0.48.2 build must **add the field and its
   write site** (~4 lines: two in `state.h`'s `OSWindow`, two in `glfw.c`'s press branch) before it
   can expose it. Budget W6 for that, not for a cherry-pick.
3. **Never prove "I am running the patched build" from `--version`** — master at `1d67ecd` still
   declares `Version(0, 48, 2)`, so both report `kitty 0.48.2`. The check that works:
   `kitty +runpy 'import kitty; print(kitty.__file__)'` — a `.py` under the build tree means dev, a
   `.pyc` under `/Applications/kitty.app` means installed.

**Path-length wall, carried forward because it silently fails a build:** `./dev.sh deps` fails at a
long path. The prebuilt bundle is relocated with `install_name_tool` and exactly one file lacks
Mach-O header padding; binary-searched, `max_root_len = 106` ⇒ a repo-path ceiling of **80
characters**. The session scratchpad root is 144 and does **not** work. Both existing trees are at
22-character paths and are fine. **The tree is location-bound** — moving it needs `make clean`.

### Q17 — Is a test that stops one call short of the OS acceptable upstream? — **RULED: yes; and do NOT propose the `in_test_mode` hatch**

Precedent is strong and in-tree: `selection_drag.py:221` patches
`kitty.window.start_drag_with_data` and `tab_drop.py:346` patches `kitty.tabs.set_window_being_dragged`
outright. Follow it.

🚨 **§ 5.21's correction is load-bearing and phase 3 will get this wrong without it: a kitty-WINDOW-drag
test must patch `kitty.tabs.start_drag_with_data`** (master `tabs.py:2059` / v `:1906`), **not** the
`kitty.window.start_drag_with_data` that `selection_drag.py:221` patches for the *text-selection*
drag. Same name, different module, different drag.

**The `in_test_mode` sub-question is ruled NO**, same reasoning as Q6: mirroring the hatch its
sibling has (`start_window_drag(Window*, bool in_test_mode)`, master `glfw.c:3619-3625`) is scope the
feature does not need and it risks the PR being judged on the wrong diff. § 5.21 also measured that
engaging dnd test mode changes nothing here, with `set_os_window_icon` as the working discriminator
(a bogus id gives a clean `KeyError`; the fake-window id **segfaults** dereferencing the NULL
handle — direct proof that `w != NULL && w->handle == NULL`).

### Q19 — Fix the record before anything is posted or landed? — **RULED: yes, and it is W1, the FIRST wave**

Pure correction, cheap, and every downstream artifact quotes these. **Nine items, not five.** § 10.2 adds one the research
§ 8 list does not have, and this session's measurement wave (§ 4.M) added three more:

| # | File | What | Disposition |
|---|---|---|---|
| 1 | `docs/research/kitty-upstream-drag-action-2026-09-16.md:139-142` | *"kitty 0.48.2 exposes 7 bindable `win` actions"* — wrong by ~6×; measured **41** `win` actions, **142** total, with positive and negative controls | Correct the figure. Keep the substantive half: across all 142, only five mention "drag" and **none begins a window drag at the pointer** — the instrument can see "drag", so that null is informative. |
| 2 | same file `:89` | the example chord `ctrl+alt+left press` **is kitty's shipped `mouse_selection rectangle`** | Replace with the Q12 chord. § 10.6(c) narrows it: it is TAKEN in `ungrabbed` only, FREE in `grabbed` — say **which mode**, or the next reader finds it free and reopens the question. |
| 3 | `config/kitty.conf:335-323` | *"the overlay … can never be dragged, however it is drawn"* — **REFUTED**; the band's pixels sit inside an ordinary mouse-mapped window region and the hit test is **bypassed** by the `\|\|` at `mouse.c:1362`, not satisfied | 🚨 **Mark refuted IN PLACE. Never delete** — the clause is the record of what was believed. The other two thirds of that sentence (*"not in kitty's hit-test"*, *"can never carry a hand cursor"*) **stand** and were attacked directly. |
| 4 | `config/kitty.conf:541-511` | the claim that the drag machinery *"hangs off real title-bar render data"* | Narrow it, in place: `window_title_render_data` is read in `mouse.c` at **exactly one line** (master `:1115` / v `:1072`), inside `mouse_region`'s hit test. **Only the HIT TEST needs a real bar**; neither the drag state machine nor the routing touches it. |
| 5 | `docs/research/kitty-upstream-drag-action-2026-09-16.md` (A10's table) | cites master `mouse.c:1432` for `} else if (r.window_border) {`; it is **`:1433`** (`:1432` is a `debug()` call) | Correct. |
| 6 | **`bin/cc-kitty-reload`'s header** | *"kitty parses its config at startup and then never looks again … every config change was live on disk and inert on screen until the operator quit and relaunched"* — **REFUTED on this box** by the live `__watch_conf__` watcher (§ 2) | 🚨 **Mark refuted in place, never delete.** Its *measurement* (SIGUSR1 → 30 rows → 28 rows, 2026-09-15) is sound and the tool is still useful — it reaches an instance whose watcher died, one started before the config file existed, or one with the option disabled. It is the **causal sentence beside the measurement** that was never tested. Leaving it is how the next session repeats § 2. |

| 7 | `config/kitty.conf:307` | calls `window_border_width` *"a 0.5pt hairline"* while **`:1108` sets it to `1pt`** — measured 2 device px at 2× (`effective_border() == 2`, `window.py:877-883`). Found in passing by the Q8 probe. | Correct the figure in place. Comment-only, so it lands under the same argument as items 3 and 4. |
| 8 | research `§ 7.4` / `§ 5.23` | both reason about remedy (b) via `layout/vertical.py`'s `start_offset=1, end_offset=1` — **not on this box's code path**, which is `enabled_layouts splits,stack` | Note the correction where W7 cites the remedy. See § 4.M/Q8(d) for the measured splits-layout result, which is **better** than the doc claims. |
| 9 | research `§ 7.3` | *"the live 2.1.260 binary asks for `?1000h` + `?1006h` only … motion is never reported to Claude Code"* — a **grep artifact**; the default mode is `full` (`?1000h ?1002h ?1003h ?1006h`) | Correct it where phase 3 quotes it. The conclusion survives for a different reason — arm 7 short-circuits motion **during** the drag. See § 4.M/Q11(a). |

**Items 3, 4 and 7 edit `config/kitty.conf`, and § 2 permits it.** Both are **comment-only**. A SIGUSR1
reload with byte-identical semantics is a no-op, so landing them cannot change the behaviour of the
operator's live kitty. W1 must nevertheless prove that rather than assume it: the W1 goal (§ 5)
requires a `diff` showing the edit touches only comment lines.

### Q21 — Is `window_title_bar_min_windows 1` a better design than the whole feature? — **RULED: no**

**Ruled, not deferred.** The record already answers it and re-asking is deference-fishing: it has
gone against the operator **twice**, and the reason is structural, not a preference that might have
drifted. At `min_w > 0 and visible >= min_w` the force-show is skipped entirely, so the drag costs
no row — **but that is precisely the ⌘⌥B ON state this feature exists to delete**, and it means
permanently visible monospace bars on every pane.

**The honest residual, stated rather than buried:** that "costs no row" property is real, and this
feature does not get it. § 7.2 is blunt about what the collapse does *not* buy — you stop paying the
row for the **decision** to rearrange; you still pay it for the **rearrange**.

### Q22 — Does the maintainer want the action to force-show bars? — **DEFERRED to PR review, and that is correct**

This is literally a question about another person's preference. His 2026-03-05 wording **couples**
them — *"a mappable action that when triggered shows the title bars and then auto hides them after
the drag operation is completed"* — which is suggestive but is **not a decision about this action**.

**What phase 3 does:** write the patch so the force-show is **inherited** (it comes free via
`start_window_drag`; the action never calls it) and say so in the PR body in one sentence, so he can
ask for it to change. **Do not engineer around it** — that is Q6, ruled NO. Quote his pre-blessing
in the PR body (PR 9450, 2026-03-05T02:33:07Z: *"draggable window title bars would be an important
feature, possibly with a mappable action … this belongs in a separate PR after this one is merged"*);
it converts the ask from controversial to requested.

### Q24 — Does `combine`'s `drain_actions` timer break a `combine`-based design? — **RULED: both halves, not either**

**(a) The action must never be a non-first element of a `combine`, and the doc text must say so.**
Any non-first action of a `combine` runs on a zero-delay timer **after** the GLFW callback returned
(`boss.py:2943-2950`), at which point `global_state.callback_os_window` is NULL — that pointer is set
at `glfw.c:268` on callback entry and NULLed on **every** exit, 15 sites.

**(b) AND the implementation must take coordinates from the window explicitly, never from
`global_state.callback_os_window`** (§ 4.5 guard 4). Doc text is advisory — a user can still write
the combine — so the code must be safe independently.

🚨 **The two halves compound, and this is the sharpest thing in this ruling.** With Q2's
`mouse_left_press_x/y`, guard 4 is satisfiable because the value lives on the `OSWindow` struct and
is reachable from the window. But § 10.3's caveat says that field is **never cleared** — so on the
`drain_actions` path it is not NULL, it is **STALE**: the origin of some *previous* left press
anywhere in the OS window. A C implementation reading `callback_os_window` there gets NULL and, under
the customary `if (!osw) return;`, a silent no-op. Reading the *stale field* instead gets a
**successful arm at the wrong origin** — a drag that begins from a point the user never pressed.
**Stale is worse than NULL**, which is why (a) is load-bearing rather than decorative and why the
doc text's prohibition must be explicit.

### § 4.M — THE SIX QUESTIONS THIS SESSION MEASURED RATHER THAN REASONED ABOUT

Q7, Q8, Q11, Q18, Q20 and Q23 could not be ruled from the phase-1 record alone: each turned on a
fact nobody had measured. This session measured all six with a nine-probe wave, each probe
adversarially verified. **They are grouped here rather than left in numeric order because their
provenance differs from every other ruling above — these are new measurements, not readings of the
research doc**, and a later session re-checking this plan should know which is which.

Two of them moved a ruling I had already drafted. Both corrections are folded into the rulings
above and flagged there.

#### Q7 — Which band-scoping unit? — **RULED: ROWS, value 2 — and pixels buy nothing here**

Measured twice, independently: by this session directly against the **real** `band_geometry`
imported from `scripts/kitty-pane-title-overlay.py` (not a retyped copy — that is the control that
makes the sweep mean anything), and by a probe that extended it with a fractional arm.

**(a) The row count is 2 everywhere reachable, and that is arithmetic, not luck.**

```
every integer cell 8..80 device px      ->  rows == 2 at all 73        (this session)
1,441 fractional samples, 0.05px over [8,80]  ->  rows == 2 at every one   (probe; production
                                                  feeds a float, ch = ypx/rows, overlay :765-770)
algebra:  rows == 2  iff  cell < round(1.378c) <= 2c  ->  holds for every c >= 2
          rows == 1 ONLY at cell == 1     band_geometry(1) = (1,1); band_geometry(2) = (3,4)
today, cell = 45 device px:  band_geometry(45) = (62, 90)  ->  90/45 = 2
```

**THE ROW-COUNT BOUNDARY DOES NOT EXIST IN ANY REACHABLE CELL SIZE.** The research doc's fear — that
the overlay's per-pane `band_cells()` and a static `2` in `kitty.conf` "agree today at every cell size
but the coupling is SILENT" — is half right and half wrong in an important way: **the coupling is not
fragile in cell size at all. It is fragile in exactly one constant.**

**(b) The real drift axis is `BAND_FILL_CELLS`, and the file's own comment invites the breaking move.**
`rows == 2` iff `BAND_FILL_CELLS ∈ [(c+0.5)/c, (2c+0.5)/c)` — at cell 45 that is
**[1.011, 2.011)**, today 1.378, margin 0.367 below and 0.633 above. But the overlay's own dial
ladder (`scripts/kitty-pane-title-overlay.py:224-239`) lists candidate bands of
45/54/58/62/68/90 px, i.e. `B ∈ {1.000, 1.200, 1.289, 1.378, 1.511, 2.000}` — and **`B = 1.000`
breaks `rows == 2`**, while the comment beside it says *"the next move in either direction is two
constants, not another architecture."* So the hazard is real and one edit away; it is simply not the
hazard the research doc named.

**(c) Exact pixels buy NOTHING for the region — and this is a THEOREM, not a sample.** Exact pixels
and `rows = 2` deliver byte-identical reachable-band coverage, and the probe's verifier sharpened the
status of that result: it holds **for every `BAND_FILL_CELLS`, every tolerance and every cell size**,
because `band_geometry` constructs `cover >= fill` so `min(cover, fill) == fill` identically. Reported
as an empirical sweep it invites a future reader to think it could drift with the dial. **It cannot.** So the `kitty/state.c`
accessor must **not** be added for the region argument — it buys nothing the operator can see.
🚨 **Add it for the Q2 reason (the press-instant origin / `drag_threshold`) and then take pixels for
free, exactly as research § 4.4 says — but do not let § 4.4's "pixels are strictly the better unit"
justify the accessor on region grounds.** The ORIGIN and the REGION are two different jobs with two
different natural units, and conflating them is what made § 4.4's pricing read as a single decision.

**(d) Do NOT scope to one row.** `rows = 1` loses 19 px of band today and **collapses to 4 px of
grabbable band at a 16 px cell**, because `window_drag_tolerance`'s frame is a constant in *device*
px (§ 7.4) while the band shrinks with the font.

**(e) The "over-coverage" § 7.5 prices as a defect is not one — with one honest qualifier.** § 7.5 says `cell_y <= 1` over-covers
the *visible* bar by 28 px at a 45 px cell. **The draggable region should match what the overlay
OCCLUDES, not what it paints.** The placement covers two whole cells; the unpainted 28 px tail is
filled with `GROUND = (0x1e,0x1e,0x24)` — the terminal background — so it reads as an empty line
**while hiding the pane's real content row 2**. A press there lands where our own overlay has made
the content unreadable. Treating it as header is correct.

⚠️ **The qualifier, because the first draft of this ruling over-claimed it:** the tail is over
*occluded-but-real terminal cells*, not over nothing — the text is still there, still selectable, just
invisible. So the claim is **display-true and interaction-false.** The interaction reading favours
`rows = 2` **harder**, not less: it gives **78 px of grabbable band against 50 px** for `rows = 1`, and
it removes a select-on-hidden-text fall-through in the very region the user believes is a title bar.
**`rows = 2`.**

**(f) Route A must not carry a static integer at all.** The kitten can compute the value at press
time: `cell_size_for_window(os_window_id)` plus the overlay's own `band_cells()`. 🚨 **And it MUST
guard the lookup** — a miss returns a silent `0`, which `band_geometry` turns into `rows = 1`, the
worst unit, **with no exception raised**. **Forbid a retyped `band_geometry` in the kitten**; import
the real one. Only route B's `rows: int` argument is a genuinely silent coupling, and that is what
the pinning test guards.

**(g) The pinning test, specified.** Derive the cell from the config through kitty's own font
machinery headlessly (`load_config` → `setup_for_testing(family, size, 144.0)` →
`round(pct * h / 100)`), assert `band_cells(cell)` equals the config literal (route B) or that **no
literal exists** (route A), and assert `tolerance < band/2`. 🚨 **Include the `BAND_FILL_CELLS = 1.0`
mutant control — without it the new test is green whether or not it is wired to anything**, which is
the decorative-test failure this repo has hit before.

⚠️ **Fix `tests/kitty-title-zero-shift.bats` FIRST — the probe reports 4 of 11 red on trunk since
`a49280bd9`.** Do not add a case to a family that is not running green. *(Do NOT also take the
probe's suggestion to delete that suite's header claim that headless derivation needs a live window:
its verifier found that refutation was measured in ONE environment — a kitty source tree with a
vendored 3.14 framework — and generalised. Re-measure before editing a claim in place.)* *(This session tried to
reproduce that independently and `cc-bats` REFUSED the run — two concurrent roots plus load — which
prints its reason and **exits 0**, i.e. through a `grep -E "^(ok|not ok)"` filter it is
indistinguishable from a clean pass. The red is therefore carried here as the probe's reading, not as
this session's own measurement, and W7 must re-run it and read the `1..N` plan line before believing
either number.)*

⚠️ **One honest UNMEASURED, and it is the only axis on which pixels could still win.** Whether
`pixel_scroll_offset_y`'s skew in `cell_y` (master `mouse.c:322` / v `:325`, bounded
`[0, cell_height)`; `pixel_scroll` measured **True** on our config) cancels against the graphics
placement's own render offset. If it does not cancel, a cell-unit predicate mis-fires by up to one
full cell **during a sub-line touchpad scroll** — a hazard the pixel unit does not have. It is
blocked because every route to a live window runs through the operator's kitty. **Put it on W4's
checklist**: a hand on a touchpad settles it in seconds, and W4 is already the wave with a hand in it.

#### Q18 — Rebuild the `draghold` CGEvent driver? — **RULED: it SURVIVES, so RECOVER rather than rewrite — but § 6.4's complaint stands until a commit lands**

The research § 6.4 instruction was *"Rebuild it, commit it, and record its invocation, or the next
session pays for it again."* **The probe found it before building anything** — searching the branch
graveyard first, which is this repo's own standing rule — and recovered the original source, the
compiled binary, and **four calling harnesses carrying the very invocation § 6.4 says was never
recorded**, all surviving in a prior session's scratchpad. Recovered byte-identical, recompiled as a
positive control, and rebuilt with a no-fire `--dry-run`/`--check` surface that compiles clean under
`-Wall -Wextra`.

**What W8 must commit, and the trap it closes:** the driver **and** the invocation line together —
`400 120` / `3000 120`, with **`steps=120`, not the built-in default of 40**. Committing the source
alone loses the working parameters again, which is precisely the failure § 6.4 names and the overlay
doc's § J states as a rule: *annotation that lives in a one-off file is lost on the next render by
construction; annotation that lives in the command is not.* Commit `verdict2.sh` alongside it — it is
the instrument that produced the § I9 table and it carries the `move_window` control and the
anti-blind-aim ABORT. Record the v0.48.2 AppKit delegate line numbers (**4367 / 4375 / 4408**) beside
master's (4287 / 4293 / 4321), since a sandbox probe may run either build.

🚨 **URGENT, and the probe's own framing understated it — its verifier caught this.** The surviving
copy lives under `/private/tmp/claude-501/<sid>/scratchpad/`, which is **per-session and reaped**.
The probe wrote *"the full source is reproduced verbatim in the artifact so the recovery survives"* —
but **that artifact is in the SAME ephemeral class**, not a durable second copy. There is no durable
copy anywhere. **"It did not need rebuilding" is true of today's filesystem and false of the repo, and
§ 6.4's complaint stands unchanged until a commit lands.** Treat W8 as recovery-with-a-deadline, not
as a no-op.

⚠️ **And do not ship the recovered source's own header prose unread.** Its verifier found the header
generalises past everything measured — it asserts the predecessor driver *"warped in milliseconds and
kitty never began a drag"* (refuted by the probe's own read of `drag.m`: no warp, ≈1.02 s, dwell
160 ms) and that *"the timings below are the ones that made the drag start"* (the probe's own caveats
say the responsible delta is **UNMEASURED**). That is phase 1's recurring defect reproduced inside
the fix: a story that explains the observation, written as if it had been tested. Commit the code and
the invocation; rewrite the header to what was measured.

#### Q20 — Does the 0.48.2 drop-classifier offset defect warrant an upstream report? — **RULED: no — it is already fixed upstream, was never reported, and upstream is a dead end for coordination**

Searched with a three-way control — a REST positive control (`/issues/8000` returned the real issue),
a **separate** search-API positive control (the same issue as top hit, required because `/issues/{n}`
and `/search/issues` are different code paths), and two negative controls returning `total=0` so a
zero is a reading rather than a hang. The probe also caught and corrected an instrument failure in
its own first batch: four `SSL: CERTIFICATE_VERIFY_FAILED` errors that, read as counts alone, would
have been indistinguishable from four genuine "no results".

| | |
|---|---|
| **Reported upstream?** | **No GitHub ISSUE matches** — by title enumeration plus body queries. ⚠️ **Not "never reported by anyone":** the repo has `has_discussions = true`, and GitHub's `is:issue`/`is:pr` search **does not cover Discussions**, so every query run here is structurally blind to a report there; the mailing list, Reddit and IRC are unsearched. The probe caveated this honestly and its headline did not carry the caveat forward — this row does. |
| **Fixed upstream?** | **Yes** — on master, 2026-09-14/15, as an **uncited side-effect of unrelated PR #10472** (two commits; `120cad0cb` by 白鸽/xiaobai050 is the first). |
| **Shipped?** | **No.** It reaches users only at 0.49.0, so **every kitty a user can install today still carries it.** |

**Three things this changes for the plan.** (1) **Do not plan around "upstream will fix this"** —
they already did, six weeks ago, and there is no thread we could find to join. *(That the maintainer found it himself is an inference from kitty's changelog convention — no `:iss:` beside the entry — not from any statement of his.)* (2) **Any
local backport is FOUR sites, not three.** The fourth is `v0.48.2 kitty/boss.py:2014-2015`
(`x -= central.left` / `y -= central.top`) — the **external file/URL drop path**, and it is the one
Kovid judged changelog-worthy; a backport omitting it fixes the case the operator does not hit and
leaves the case the changelog says users do. (3) **Do not attempt the backport as a revert of
master's diff** — that commit restructured the region +88/−87 (new `_pointer_in_title_bar_of`,
`is_visible_in_layout` filtering). The mechanical change is **deleting the six subtractions in
place**, strictly smaller and safer.

🚨 **A polarity correction, and this session's own brief carried the error.** `rel_x, rel_y = x, y`
is **master's FIXED form**; the v0.48.2 **defect is the SUBTRACTION**. Research § 5.9 has this right;
the probe brief's restatement of it did not, and a reader who quotes the brief will hunt for the cure
believing it is the disease. `grep -n 'rel_x\|rel_y' kitty/tabs.py` → **v0.48.2: 14 lines · master:
2 lines.**

**Free regression test if a backport is ever wanted:** master already wrote one that is directly
portable — `kitty_tests/tab_drop.py::TestWindowDropCoordinates::test_drop_with_offset_tab_bar`, whose
`(0,30)`/`(80,0)`/`(80,30)` offsets match the research doc's own A/B sweep.

**Scope, restated because it is the one thing this question could have violated:** the probe posted
nothing, opened nothing and commented nothing. Reporting remains the operator's call and is out of
scope — and here the correct advice is that there is nothing to report.

**Is the backport in scope for phase 3?** **No, and it is not filed either — it is DROPPED with its
reason recorded here.** It is inert on this box at the shipped default `tab_bar_edge bottom`
(§ 5.9), our W6 build is a comparison instrument rather than the operator's daily driver, and the
upstream fix arrives at 0.49.0 without anyone doing anything. Recorded so a later session does not
re-derive it.

#### Q8 — The `window_drag_tolerance` dead band — **RULED in three parts; one part is genuinely the operator's, at 70% conviction**

The research doc's own note said *"the 12 px is derived, not observed."* **It is now observed, to the
pixel, by three independent instruments at the operator's real live geometry** — a sandbox running
his interacting settings verbatim (`window_drag_tolerance 6` · `window_padding_width 0 5 0 5` ·
`draw_minimal_borders no` · `window_border_width 1pt` · Monaco 18 · `modify_font cell_height 94%` ·
`enabled_layouts splits,stack`), giving cell 22×45 device px, i.e. his real cell.

- **Instrument A**, in-process: a `no_ui` kitten that swaps `kitty.borders.set_borders_rects` for a
  spy and calls `tab.relayout_borders()`, executing the shipped `add_borders` verbatim and
  intercepting the real rect list, with the tolerance taken from the shipped
  `pt_to_px(opts.window_drag_tolerance, oswid)`.
- **Instrument B**, real events: `--debug-input` plus a per-pid `CGEventPostToPid` poster
  (`CGEventPost` / `CGWarpMouseCursorPosition` **never** called, so the operator's cursor never
  moved), 184 `mouseMoved` delivered; kitty prints its **own** device y, so no calibration is trusted.
- **Instrument C**: the source arithmetic, `round(pt × dpi/72)` at `state.c:93-97`, the same
  expression as v `mouse.c:1007-1008`.

```
dpi 144.0  scale 2.0  tolerance_device_px 12          ← the derived 12 is CONFIRMED
EATEN per pane:  top 12 · bottom 12 · left 2 · right 2       (the 5pt side padding absorbs 10 of 12)
--debug-input, real events:  y 0.0-13.0  -> "window border: top window id: 1"
                             y 14.0-844.0 -> "grabbed: ..."   (i.e. reaches the mousemap)
```

**(a) The 19.4% is CORRECT for this deliverable — and the probe's own headline overreached here, so
the correction is recorded rather than the claim.** The probe reported the loss as *"24 px/pane
ABSOLUTE, so 53.3% of a 1-row pane, **not** 19.4%"* and advised that *"a plan that prices this at
19.4% is pricing the wrong pane."* **That sentence must not ship.** Its adversarial verifier caught
why, and re-ran the rig to confirm it: the two figures have **two different denominators answering
two different questions.**

| figure | = | answers |
|---|---|---|
| **19.4%** | 12 / 62 | what fraction of **the overlay's painted drag band** is unreachable — **pane-height-invariant and scale-invariant** |
| 53.3% | 24 / 45 | what fraction of **a whole 1-row pane** is unreachable |

**For a band-scoped drag, the band fraction is the right price, and the research doc had it right.**
The 1-row figure is moot for an independent reason the rig itself supplies: at a 1-row geometry
`band_geometry(45)` needs **90 px of cover for a 62 px fill**, so **the band cannot be placed there at
all**. The 30-pane extrapolation inherits the same defect — the probe's own caveat 5 concedes those
panes were never built (the splits tree degenerated; panes 2..11 came out at height 0).

**What the probe DID establish, and it is genuinely new:** the loss is an **absolute 24 device px per
pane** — a *frame*, 12 top + 12 bottom, not a top edge — confirmed to the pixel by three instruments,
plus the divider dead zone in (b). The absolute figure is the one to carry into any argument about a
**pane**; the 19.4% is the one to carry into any argument about the **band**. Both are true; neither
replaces the other.

**(b) A 17 px dead zone INSIDE the divider that no artifact found.** The full-column run-length
encoding at x=1200 shows a gap belonging to neither pane's border rect:

```
[0,14) BORDER TOP w1 | [14,845) reachable | [845,871) BORDER BOTTOM w1
                     | [871,888) NEITHER  |                              ← 17 px, hits nothing
                     | [888,914) BORDER TOP w2 | [914,1745) reachable | [1745,1771) BORDER BOTTOM w2
```

**(c) Remedy (c) — lowering `window_drag_tolerance` — is DEAD. Close it.** Driving *eaten* to 0
requires `tolerance ≤ 0.24pt`, i.e. **0 device px** — which is exactly the un-grabbable hairline that
`config/kitty.conf:306-313` raised the tolerance to fix, and it widens the divider dead zone on the
way. The only defensible partial is 5pt, which buys back the left/right 2 px for a 15% smaller grab
target. Not worth it.

**(d) Remedy (b) — `draw_minimal_borders yes` — is the front-runner, and the research doc reasons
about it on the WRONG code path.** § 7.4 and § 5.23 cite `layout/vertical.py`'s
`start_offset=1, end_offset=1`. The operator runs `enabled_layouts splits,stack`, so **`vertical.py`
is not on his code path at all.** Measured on the real splits layout:

| | today (`draw_minimal_borders no`) | `draw_minimal_borders yes` |
|---|---|---|
| hsplit | 24 px frame on **every** pane | a single **12 px top edge**, non-topmost panes only |
| vsplit | 24 px frame on every pane | **ZERO** |
| divider dead zone | 17 px | **gone** |

**Its price is one thing and it is legible: the active-pane box disappears entirely.**

🚨 **(e) That last trade is the operator's, and it goes to him WITH the number.** It is a
visual-identity call, not a correctness one. Per the conviction rule, the probe puts **~70%** on his
preferring to keep the active-pane box — below the 90% threshold at which an agent implements — so it
is handed over rather than chosen. **It is handed over at W4, where he is already looking at a
sandbox, with both screenshots side by side, not as an abstract question.** If he keeps the box, the
answer is (a): **accept 24 px/pane**, which the band survives comfortably at `rows = 2` (90 px placement
− 12 px top = 78 px reachable).

**Two MUST-NOTs the plan inherits:**

1. 🚨 **Do not write "a press in the eaten band starts a border resize" unqualified.** That is true
   only for the **LEFT** button — v `mouse.c:1381` gates `drag_resize_start` on
   `GLFW_MOUSE_BUTTON_LEFT`. For any other chord it is a **SILENT no-op**, which is the worse failure
   because there is no feedback at all. *(Our Q12 chord is `cmd+shift+left`, so on this box the press
   does produce a visible resize cursor — but the doc text for deliverable B must state the general
   case.)*
2. **The dead band only ever affects the INITIAL press.** v `mouse.c:1362` puts
   `global_state.window_being_dragged.id` **ahead** of the border arm, so an already-armed drag is
   unaffected. Do not describe it as degrading the drag.

**Measured identically on v0.48.2 and master**, so deliverable B's `mouse_drag_window` inherits the
same dead band and **its doc text should say so** — a user binding it in a multi-pane tab will
otherwise report the top of their pane as broken.

⚠️ **Honest instrument bound, and it is the same wall Q9 hits.** `CGEventPostToPid` delivered
`mouseMoved` 184/184 to a background app but **never delivered `ldown`/`rdown`**, with and without
`kCGMouseEventClickState`, focused and unfocused. An armed `mouse_map right press` fired **0** times
**including on the content-area positive control** — so that arm is an *instrument failure, not a
result*. Delivering presses needs the sandbox app ACTIVE, which takes focus from the operator's live
session, and the probe correctly declined. What survives is strong but one inference short of
measurement: the branch **selection** is measured (moves and presses share `mouse_region(true, true)`,
v `mouse.c:1354`), and branch → mousemap is a code read (the only mousemap lookup is
`kitty/window.py:1399`, reached only from `mouse.c:212`, called only at `:760`/`:835`/`:894`, all
inside the `} else if (w) {` arm).

#### Q11 — Does Claude Code bind any ⌘-modified mouse press? — **RULED: NO, and it structurally cannot**

**kitty never puts SUPER on the wire.** Verified independently by this session in both refs, with the
positive control that makes the null informative:

```
grep -c GLFW_MOD_SUPER kitty/mouse.c     v0.48.2: 0      master: 0
v0.48.2 kitty/mouse.c:94-96              SHIFT -> cb, ALT -> cb, CONTROL -> cb ... and nothing else
POS CTRL, the token IS greppable and kitty DOES know it:
   kitty/keys.py:32   mod_mask = ... | GLFW_MOD_SUPER | ...
   glfw/glfw3.h:502   #define GLFW_MOD_SUPER 0x0008
   window.py:1396-1401 masks MOUSEMAP lookups with that mask   ← kitty's OWN map can key on ⌘
```

So a ⌘+left press reaches the child **byte-identical to a plain left press** (`ESC[<0;col;rowM`) — the
encoder drops the modifier, only the *mousemap* sees it. On the Claude Code side the probe confirmed
the same answer from the other direction, with a scoped negative control over the 4,300-byte window
holding the whole mouse dispatcher: **no `.super` read anywhere on the mouse path**, while the same
window returns `button&24`, `button&3`, `button&32`, `button&8` — so the null is a measurement, not an
absence of modifier logic. The 20+ `.super` reads that *do* exist in the binary are all on the
**keyboard** (CSI u) path.

**Close Q11. Do not spend a session on a synthetic-press probe for it.**

⚠️ **Bound the phrase "structurally cannot", because unbounded it forbids this plan's own remedy.**
It is true of **kitty's mouse-REPORTING encoder** — no app can learn about ⌘ from a mouse report. It
is *not* true of kitty→app communication in general: a `mouse_map cmd+left press … send_text`, or a
kitten writing to the pty, delivers arbitrary bytes on ⌘. Adding a ⌘ `mouse_map` is exactly what this
plan does, and it works *because* the mousemap sees the modifier the encoder drops
(`window.py:1396-1401` masks the lookup with a mask that includes `GLFW_MOD_SUPER`).

🚨 **But the same read refutes a claim in research § 7.3 that the plan would otherwise repeat, and
hardens Q12 from a preference into a near-certainty.**

**(a) § 7.3's second leg is a grep artifact.** It states the live 2.1.260 binary asks for
`?1000h + ?1006h` **only** — zero `?1002h`, zero `?1003h` — and concludes *"motion is never reported
to Claude Code."* Measured, the default mouse mode is **`full`** = `?1000h ?1002h ?1003h ?1006h`
(producer `wH()`, three call sites, and both override env vars measured absent on this box).
**Motion IS reported, up to the press.** The *conclusion* § 7.3 drew still holds, but for a different
reason that phase 3 must carry correctly: motion is suppressed **during** the drag only because
kitty's arm 7 short-circuits it (v `mouse.c:1362`), not because the program never asked.
*(Honest bound: "live mouse mode is `full`" is **statically** measured — producer plus call sites plus
the measured absence of both override env vars. The probe's three-arm pty capture came back identical
in all arms and is recorded as a NON-VERDICT, because reaching the REPL needs a logged-in config dir
and it correctly declined to copy credentials or to fire 15 `SessionStart` hooks into a shared
mailbox.)*

**(b) Q12's cost is larger again, and this settles it.** `cmd+left press` does not merely "kill a link
binding". It kills `config/kitty.conf:821`, which that file documents at `:752-767` as **the only
link-open gesture that works in a grabbed pane** — the reason plain left-click was rejected — and for
which the ⌘E hints route was **deliberately retired** (`:818-832`, decision `bbbedc12cb8b`). **Claude
Code does not backfill it** (its hyperlink shim is ghostty/Warp-only). And ⌘ is additionally
`show_hyperlink_targets cmd` (`:806`), so **hold-⌘-to-preview-then-click becomes
hold-⌘-to-preview-then-DRAG** — the two gestures share their modifier and their first half.

⚠️ **State the `:772` mechanism CONDITIONALLY, not absolutely — its verifier corrected this.**
`add_press` runs regardless of `handled`, and `release_is_click` never consults it, so **the
synthesized click survives a press-map UNLESS a drag was actually armed.** So `cmd+left press` kills
`:772` precisely where the drag arms, and leaves it alive where the press is consumed without arming.
That narrows the damage; it does not change the ruling, because the region where the drag arms is
exactly the header band, and the ⌘-preview collision in the sentence above is unconditional.
**`cmd+shift+left press` is therefore the recommendation, not the runner-up.** Q12 above already rules
that way; this is the evidence that takes it past argument.

**(c) A residual no artifact named, and it applies to BOTH routes.** If the handler **declines** to
start a drag — route A on `drag_threshold 0` or an out-of-band press, route B on a competing drag
state — then kitty has eaten the **PRESS** but still forwards the **RELEASE** (v `mouse.c:894-899`;
arm 7 short-circuits only while `window_being_dragged.id` is set). **Claude Code receives an unpaired
left release**, which can fire `onClickAt` against a stale selection anchor. Phase 3 must either make
the decline path explicit or accept it and say so in the doc text. This is a second, independent
reason the § 4.5 guard set matters: every guard that *refuses to arm* creates one of these.

#### Repo deployment (§ 10.7) — **RULED: take route A′, the kitten goes in `scripts/` and is named by ABSOLUTE path**

Not one of the numbered 24, but § 10.7 flagged it as uncovered and it decides W3's whole size. Measured
against a `git archive HEAD` simulation of the repo (2,760 tracked files, the six kitty arms 6/6 green
before mutation).

**Route A′ beats route A by three files and buys nothing away.** § 10.7 assumed the kitten must land in
`config/` and be symlinked into `~/.config/kitty/` — because research § 3.2 says *"a relative kitten
path resolves against `kitty.constants.config_dir`."* True, and the word doing the work is
**relative**. Verified directly:

```
v0.48.2 kitty/utils.py:646-651
def resolve_abs_or_config_path(path, env=None, conf_dir=None):
    path = os.path.expanduser(path)
    path = expandvars(path, env or {})          # ← ${HOME} expands
    if not os.path.isabs(path):                 # ← an ABSOLUTE path is used AS-IS
        path = os.path.join(conf_dir or config_dir, path)
```

| | route A (§ 10.7) | **route A′ (ruled)** |
|---|---|---|
| kitten lives in | `config/kitty-drag-window.py` | **`scripts/kitty-drag-window.py`** |
| config line | `kitten kitty-drag-window.py` | **`kitten ${HOME}/.claude/scripts/kitty-drag-window.py`** |
| `scripts/kitty-setup.sh` | needs a new `ln -sfn` | **no change** |
| `scripts/deploy-parity-assert.sh` | needs a new sibling arm | **no change** |
| repo files touched | 4 | **2 + 1 test case** |
| `tests/deploy-parity.bats` | must be re-derived | **107/107 green, measured unchanged** |

**§ 10.7's arm count is also corrected: THREE arms refuse an undeclared kitten, not four.**

🚨 **If phase 3 takes route A anyway, the `deploy-parity-assert.sh` change is a NEW SIBLING ARM after
`:766`, `want=0`, with a written reason — it must NOT widen `:766` itself**, which reddens the fire
test at `tests/deploy-parity.bats:2267`. Use the literal `ln -sfn "$REPO/config/kitty-drag-window.py"`
spelling, not a variable hop.

🚨 **ALWAYS include one new case in `tests/kitty-conf-bindings.bats` that names the new `.py` file
LITERALLY.** Without it `gate-select` answers `FULL <- unmapped:` and **ship-land runs no smoke at
all**, deferring the whole corpus to `postland-verify`, where it becomes a **post-land RED with a
possible AUTO-REVERT**. This is a land-gate mechanic, not a coverage nicety.

#### Q23 — Does the docs build pass with the proposed docstring? — **DEFERRED to W5, with the gate named**

The probe wave did not return a verdict on this one before the plan landed; it is the only question of
the nine left open, and it is the cheapest to close. **It is deferred rather than ruled, and the
criterion is mechanical:** `make docs` (or `./setup.py docs` — read `docs/Makefile` first) in
`/private/tmp/kitty-dev` with the § 4.6 docstring applied, **plus the positive control that makes a
clean build meaningful — deliberately introduce one dangling role (`:ac:\`no_such_action_xyz\``) and
confirm the build FAILS on it.** Without that control a clean build proves only that sphinx ran.

**Why the risk is low but non-zero:** every `:ac:`/`:opt:`/`:ref:`/`:doc:` role target in the proposed
docstring was verified to exist during phase 1, and `docs/conf.py:672-674` sets
`ac_role.warn_dangling = True` with `docs/Makefile:4-5,9` building `-n` plus `FAIL_WARN`, so a dangling
role breaks the build loudly rather than silently. **It is a W5 acceptance-checklist item, not a design
question**, which is why deferring it costs the plan nothing.
---

## § 5. THE WAVES

Each wave below is a dispatched session (locus **S**, § 0) unless stated. The `--goal` line is
mandatory and is written to the three-part shape: **one measurable end state · the check that prints
the proof · the constraint that must hold.** The goal evaluator is a separate tool-less model that
sees only what the session **surfaces**, so every goal names a command the session runs and prints.

### W0 — Unblock the land gate — **DONE (`ee0652933`, 2026-09-16, by a sibling session)**

**This wave was written, and discharged while this plan was being written.** Recorded rather than
deleted, because the *reason* it existed is the reusable part.

**Why it existed.** `tests/kitty-title-zero-shift.bats` was **red 4-of-11 on `origin/main`**,
deterministically, since `a49280bd9` — and it is a **`--direct` suite of ANY `config/kitty.conf`
edit**. So the moment a `config/kitty.conf` change entered a diff, `ship-land` would select it, find
it red, and **exit 6**, whose contract is *"a named `not ok` in a direct suite is a VERDICT about your
diff: fix it, do not retry unchanged."* It would not have been a verdict about the diff. **W1 edits
`config/kitty.conf` comments (Q19 items 3, 4, 7) and W7 edits it substantively — both were blocked
behind a red neither caused**, and the first draft of this plan missed the edge entirely.

**What the cure was, and it is the generalisable half.** `a49280bd9` removed the 22.5pt top reservoir
at the operator's own request and swapped the chords; it ran `kitty-conf-bindings` 30/30 and
`cc-kitty-reload` 14/14 **but not this suite — the one its change invalidated.** So the suite went on
guarding the pre-revert design. **A stale assertion becomes an inverted guard**: it was not detecting
a regression, it was demanding one.

**Verified by this session on the rebased worktree**, plan line present so the result is real:

```
1..11
ok 1 .. ok 11        tests/kitty-title-zero-shift.bats   (11/11)
```

**Phase 3 must still re-check it rather than trust this line** — it is a claim with a shelf life, and
`config/kitty.conf` is about to change twice more (W1, W7).

### W1 — Fix the record (Q19)

**Deliverable.** The six corrections of Q19, landed. Items 3, 4 and 6 are marked **refuted in
place** — the original wording stays, with the refutation beside it.

**Files.** `docs/research/kitty-upstream-drag-action-2026-09-16.md` (items 1, 2, 5) ·
`config/kitty.conf` (items 3, 4, **comments only**) · `bin/cc-kitty-reload` (item 6, header comment).

**Goal.** *Six record corrections are landed on origin/main with the three refuted claims marked in
place rather than deleted — proven by printing `git diff origin/main~1 origin/main -- config/kitty.conf`
and showing every changed line begins with `#`, plus a grep showing the original wording of each
refuted clause still present; do not delete any refuted clause and do not change any non-comment line
of config/kitty.conf.*

**Why the comment-only proof is in the goal:** it is the one mechanical check that separates a safe
W1 from a § 2 incident.

### W2 — Deliverable A, the config-only prototype (SANDBOX ONLY)

**Deliverable.** `kitty-drag-window.py` — a `no_ui` kitten implementing **both** arming spellings
(Q2) behind one switch, running only in a sandbox config dir. Not landed by this wave; W3 lands it.

**The five things the kitten must do, in order** (research § 3.3, with the § 10.6(a) correction):

1. 🚨 **Use kitty's documented four-parameter handler signature, window id THIRD.** The research
   body § 3.3 step 1 says the handler *"receives the window id as its second argument"* — true of
   the internal call (`boss.py:2326`) but **false of the file you write**, because
   `create_kitten_handler` wraps it as `partial(handle_result, [kitten] + orig_args)`
   (`runner.py:95`). Writing `def handle_result(args, wid, boss)` raises `TypeError` at press time,
   which `Boss.combine` turns into a **popup on every press**, not a visible stack trace.

   ```python
   # v0.48.2 docs/kittens/custom.rst:177-179  — THE CORRECT SHAPE
   from kittens.tui.handler import result_handler
   @result_handler(no_ui=True)
   def handle_result(args: list[str], answer: str, target_window_id: int, boss: Boss) -> None:
   ```
2. ⚠️ **The file MUST still define `main()`.** `import_kitten_main_module` does a bare `g['main']`
   subscript (`runner.py:65`) **before** the `no_ui` check, so a handler-only file raises `KeyError`
   at press time and opens an error overlay — measured (V27): `nomain_made_overlay: 1`, the handler
   never ran.
3. **Guard the `None`.** `current_mouse_position()` returns `Py_RETURN_NONE` on a window-lookup miss
   (master `state.c:1979` / v `:1745`). A naive `['cell_y'] < rows` raises `TypeError` → "Key action
   failed" popup on **every** press (V28).
4. **Refuse to arm when `get_options().drag_threshold == 0`.** At 0 the promotion test can never
   pass, so the flag is set and only a LEFT release can ever clear it — one keystroke from the wedge.
5. **Arm**, by whichever spelling the switch selects.

**Both spellings, so W4 can compare them (Q2):**

- **(i) threshold-preserving** — install a wrapper on `boss.handle_window_title_bar_mouse` (a plain
  instance attribute on a class with no `__slots__`, which `PyObject_CallMethod` re-resolves by
  `PyObject_GetAttr` on **every** event), capture the first delivered `(x, y)` pixel pair as the
  origin, call `set_window_being_dragged(wid, False, x, y)`. Measured on the shipped 0.48.2 with the
  naive route as the failing control in the same run: 3 px no trip · 4 px no trip · **9 px trips**,
  against `drag_threshold 5`; kitty stderr empty for the whole run.
- **(ii) threshold-free** — `set_window_being_dragged(wid, True, 0, 0)` then
  `request_callback_with_thumbnail("start_window_drag", os_window_id, wid)`, the same call kitty
  makes at v `tabs.py:1862`. ⚠️ **Spelling is ref-dependent:** `Boss.request_thumbnail` is
  master-only and measured **absent** from the shipped 0.48.2 build; `request_callback_with_thumbnail`
  is in both but takes **6 args at 0.48.2** (`"sK\|KpdI"`, `state.c:1781`) and **7 on master**
  (`"sK\|KpdIp"`, adding `no_scaling`). The prototype targets the **shipped 0.48.2**.

**Bind LEFT.** `if button != GLFW_MOUSE_BUTTON_LEFT: return` (v `tabs.py:1866-1867`) sits **above**
the only mouse-driven clear (v `:1877`). Measured: a LEFT release cleared `(99,False,10,20)` →
`(0,False,0,0)`; MIDDLE and RIGHT releases left it untouched. **And kitty's GLFW mods are not stock
GLFW** — SHIFT `0x1`, ALT `0x2`, CONTROL `0x4`, SUPER `0x8` (`glfw/glfw3.h:487,492,497,502`). Never
hardcode a mod integer.

**Goal.** *A sandbox kitty launched from its own KITTY_CONFIG_DIRECTORY arms a window drag from a
content-area chord press under BOTH arming spellings — proven by printing `get_window_being_dragged()`
before and after for each spelling plus the sandbox kitty's stderr showing no traceback; do not write
to ~/.config/kitty, do not write config/kitty.conf, and do not run any command against
KITTY_LISTEN_ON without `env -u`.*

### W3 — Deploy the kitten file — route A′, two files (§ 4.M/Repo deployment)

**Deliverable.** `scripts/kitty-drag-window.py` landed and reaching `~/.claude/scripts/` through the
repo's existing symlink farm, plus **one new case in `tests/kitty-conf-bindings.bats` naming the file
literally**. **INERT** — no config line references it yet (S3, M4).

**Route A′, measured, and it is three files smaller than § 10.7 assumed.** The kitten is named by
**absolute path** — `kitten ${HOME}/.claude/scripts/kitty-drag-window.py` — which
`resolve_abs_or_config_path` (v `kitty/utils.py:646-651`) uses as-is after `expandvars`, because the
`config_dir` join happens only `if not os.path.isabs(path)`. That removes the
`scripts/kitty-setup.sh` `ln -sfn` line and the `scripts/deploy-parity-assert.sh` sibling arm
entirely, and `tests/deploy-parity.bats` stays **107/107 green, measured unchanged**. Full comparison
and the route-A fallback spelling: § 4.M.

🚨 **The `tests/kitty-conf-bindings.bats` case is NOT optional and is not about coverage.** Without a
case naming the new `.py` file literally, `gate-select` answers `FULL <- unmapped:` and **`ship-land`
runs no smoke at all** — deferring the whole corpus to `postland-verify`, where it surfaces as a
**post-land RED with a possible AUTO-REVERT** against a diff that was fine.

**Goal.** *scripts/kitty-drag-window.py is landed and live under ~/.claude/scripts/ with every deploy
gate green — proven by printing `ls -la ~/.claude/scripts/kitty-drag-window.py`, the full TAP output
of tests/deploy-parity.bats including its `1..N` plan line, and the new kitty-conf-bindings case
passing; do not add any mouse_map line and do not reference the kitten from any config file.*

🚨 **Assert the `1..N` plan line before believing any bats result.** `cc-bats` refuses a run under
contention and says so on stdout, and piped through a `grep -E "^(ok|not ok)"` that refusal emits
**zero lines and exits 0** — which reads exactly like a suite that passed. *(This session hit exactly
that while trying to verify the § 4.M/Q7 red: `cc-bats: REFUSED — 2 concurrent bats execution
root(s)`.)*

### W4 — 🚨 THE OPERATOR GATE (Q9, Q10, Q8, Q12) — locus **L**, and only to hand over

**This is not an agent wave.** It needs a human hand on a real mouse, for roughly 60 seconds. The
lead's entire job is to make those 60 seconds cost nothing else.

**Delivered as ONE executable script, `/tmp/kitty-drag-w4.sh`, which:**

1. Launches a sandbox kitty (research § 6.3 recipe) from `/private/tmp/kitty-482/kitty/launcher/kitty`
   with its own `KITTY_CONFIG_DIRECTORY`, its socket **outside** `/tmp/kitty-*`, `env -u` on the
   three `KITTY_` vars, and two stacked panes plus the overlay running.
2. Writes the sandbox config with the W2 kitten bound, and offers the three chord candidates of Q12
   and both arming spellings of Q2 as **already-bound, simultaneously live** alternatives, so the
   operator tries them without editing anything.
3. Prints, in the pane, exactly what to press and what "working" looks like.
4. **Reads the verdict back itself** — `kitten @ --to <sandbox socket> ls` before and after, diffing
   the `neighbors` graph to prove the layout actually changed, and capturing a mid-drag screenshot
   for Q10. It must not ask the operator to interpret anything.
5. Is **safe to re-run** and leaves the operator's kitty untouched.

🚨 **Witness rule, learned the expensive way (memory: `witness-must-test-the-set-before-the-order`).**
The verdict reader compares a pane-adjacency graph before and after. **Closing a pane makes its two
neighbours adjacent**, so a differ that tests `moved` before `set-changed` reports ordinary churn as
a REORDER — and this tool's whole purpose is to supply the one proof a session must **not**
manufacture (a human action). Test `gone or new` FIRST and re-baseline; only a change among members
present on **both** sides may be called a reorder.

**What W4 answers:** Q9 (does it work end to end · is threshold-less objectionable) · Q10 (does the
graphics placement survive) · Q8 (is the dead band actually annoying in the hand) · Q12 (which chord).

**What W4 unblocks:** W7, and nothing else. It is also the phase-3 lead's **succession point**.

### W4 — RUN LOG (2026-09-16, the operator's own hand)

**Two runs, both INCONCLUSIVE, and the second one produced the fix.** Recorded because the next
session must not re-derive any of this, and because the apparatus is fine — what was missing was a
distinction it could not draw.

| run | flags | verdict | what it meant |
|---|---|---|---|
| 1 | *(default 120s watch)* | `NO-CHANGE`, panes 2→2 | no gesture observed. The script's watch is **120 s**, which is exactly the harness's foreground timeout, so the call backgrounded at the moment watching began and there was no visible `GO`. |
| 2 | `--watch-secs 420` | `SET-CHANGED`, panes **2→0**, `gone: 1, 2` | the sandbox OS window CLOSED during the watch. Not a reorder, and the witness correctly refused to call it one. Process stayed alive with a live socket; `kitten @ ls` returned `[]`; stderr held one benign `glCopyImageSubData` warning and **no traceback**. |

🚨 **THE GAP RUN 2 EXPOSED, AND IT IS THE REUSABLE PART.** The gate reads its answer from a
pane-adjacency diff, and that diff **cannot separate the two states the operator most needs told
apart**: *no chord ever fired* and *a chord fired and the drag did not complete*. Both render as "no
layout change". So an inconclusive run said nothing about which half to fix — the binding and the
modifiers, or the gesture — and two runs of a human's time bought no direction at all.

**The cure (landed `a57c4ba0c`):** `scripts/kitty-drag-window.py` appends one line per press —
timestamp, window id, spelling, rows, and the verdict string it returned, so a *decline* is recorded
as loudly as an arm. It is **opt-in on `KITTY_DRAG_LOG`** and unset in production, and every failure
inside it is swallowed, because a logging fault must never become a popup on a press — the same
hazard the four guards exist to avoid. `kitty-drag-w4.sh` passes the log to the sandbox and prints a
`PRESSES:` line above the Q9 reading; `PRESSES: NONE` now names the finding explicitly.

Verified both directions in a throwaway sandbox by invoking the kitten through **remote control
rather than any synthesised mouse event** (see § 8's note on why that distinction is load-bearing
here): with the variable set, two invocations returned `armed:preserving:installed` and `armed:free`
and both appear in the log; without it the kitten still arms and **no file is created**.

**To resume W4:** a teardown is REQUIRED, not cosmetic — a reused sandbox was launched without
`KITTY_DRAG_LOG` in its environment, so only a fresh kitty logs.

```
bash scripts/kitty-drag-w4.sh --teardown && bash scripts/kitty-drag-w4.sh --watch-secs 420
```

**Also open on this wave:** the Q10 **before** frame did not capture on run 1 while all 196 burst
frames did — so this is not a Screen Recording permission fault; the window was most likely not yet
mapped when the first shot fired. Q10 stays answerable by comparing an early burst frame to a late
one, but the clean before/after pair is not there. That path had never executed before the operator
ran it, deliberately: `screencapture` raises a TCC modal no subagent can answer.

### W5 — Deliverable B, the patch against master

**Deliverable.** A complete, formatted, type-checked, tested patch in `/private/tmp/kitty-dev`, plus
a PR body. **Not posted** — posting is the operator's call and out of scope.

**The file set is SETTLED and short** (research § 4.2, whose "zero regenerated files" half was
upgraded from a reading to a **measurement by executing kitty's real generator**, with a positive
control that fires):

| # | File | What |
|---|---|---|
| 1 | `kitty/window.py` | the `@ac('mouse', """…""")`-decorated `mouse_drag_window`, in the `# mouse actions {{{` block after `mouse_selection`. Doc text ready to paste at research § 4.6. |
| 2 | `kitty/options/utils.py` | a `@func_with_args('mouse_drag_window')` parser. **Mandatory because the action takes an argument** — `parse_key_action` does `parser = func_with_args.get(func); if parser is None: raise KeyError` the moment a `rest` exists. Template: `resize_window` — bare positional words, `log_error` + default on anything invalid, **never raise**. |
| 3 | `kitty/state.c` + `kitty/fast_data_types.pyi` | expose `mouse_left_press_x/y` (Q2). Two keys in the existing `Py_BuildValue` at master `state.c:1966-1980`, or a three-line getter. |
| 4 | `docs/changelog.rst` | one bullet at the **TOP** of `0.49.0 [future]`, blank line above and below, 2-space continuation indent, **no `:pull:` reference** — measured on three of his own `Update changelog` commits; he moves it into topical position and appends the ref himself. |
| 5 | `kitty_tests/window_drag.py` | the tests, below. |
| 6 | *(separate commit)* `kitty/tabs.py` | the Q5 `on_window_drop` ordering fix. |

**Do NOT touch** `docs/actions.rst` (a 14-line stub written at doc-build time), `docs/generated/*`
(gitignored), `tools/cmd/at/kitty_actions_generated.go` (gitignored and absent from both checkouts),
or `kitty/rc/action.py` (dispatches by string). **Decisive precedent:**
`git grep -ln toggle_window_title_bars` returns exactly **three** tracked files in both refs.
**Ship no default `mouse_map`** — it would drag `definition.py` and the regenerated `types.py` in.

**The four guards (§ 4.5), each with its reason:**

1. Arm **only** for `GLFW_MOUSE_BUTTON_LEFT` (or teach the handler to clear on the arming button) —
   the wedge, § 2.
2. **Refuse to arm when `active_drag_in_window` or `tracked_drag_in_window` is non-zero.**
   `active_drag_resize` needs no guard: its only writer sits in the `else if (r.window_border)`
   branch, mutually exclusive with the content branch, and while it is set the gate returns
   unconditionally so the arming press could never be delivered.
3. **Call `clear_click_queue` for its button.** Arm 7 swallows the release, so `add_press` ran but
   `dispatch_possible_click` never does — **the next plain click reads as a double click and selects
   a word.** kitty names this hazard and its cure in its own comment at master `mouse.c:673-675`,
   with the cure call at **`:676`** (§ 10.6 corrects the body's `672-675`/`:672`).
4. **Take start coordinates from the OS window under the pointer EXPLICITLY**, never from
   `global_state.callback_os_window` — see Q24 for why stale is worse than NULL here.

**Copy from the built-in press branch:** honour `drag_threshold 0` by refusing to arm; focus the
window on press (`boss.set_active_window(w, switch_os_window_if_needed=True)`); rely on the built-in
release path to clear — **no release binding is needed**; document the action as LEFT-button.

🚨 **§ 5.16's constraint, which decides the implementation's shape:** *"An implementation must set
`drag_started=True` and must route through `start_window_drag`; hand-rolling the payload yields a
drag with no preview and no unwind."* Read that together with Q2 — the action arms
`drag_started=False` and lets kitty's own motion path promote to `True` and call
`start_window_drag`. It must **not** compose the MIME payload itself.

**Tests** (research § 6.5, with § 10.5's correction folded in):

| | asserts |
|---|---|
| **T1** | the action is bindable in `mouse_map` — the only test that catches a rename breaking the documented config line |
| **T2** | 🚨 **the load-bearing one** — the action arms the drag. Assert `get_window_being_dragged()`, **never `combine`'s return value alone**, and pass `raise_error=True` |
| **T2-neg** | an unimplemented name is not consumed and writes nothing. **This is the control that makes T2 mean anything, and a bare `Mock()` destroys it.** |
| **T3** | threshold crossing starts the drag; a **sub-threshold** move must NOT request a thumbnail. **The only test that does the distance arithmetic**, so a wrong coordinate space is invisible to every other test in the suite. |
| **T4** | the payload — patch `kitty.tabs.draw_single_line_of_text` and **`kitty.tabs.start_drag_with_data`** (§ 5.21: *not* `kitty.window`'s), assert the MIME key and value, then `side_effect = OSError` and assert the state was cleared |
| **T5** | no window ⇒ no crash, state untouched |
| **T-pass** | **passthrough, asserted separately** — a region-restricted action that consumes when it should pass through is invisible to the arming test |

🚨 **T-pass is writable TODAY, on stock v0.48.2, with no plumbing — and the probe wave's first answer
here was wrong in the direction that would have cost phase 3 real work.** The measurement probe
reported that § 6.5's passthrough test is "only half unblocked" and should be SPLIT, with the
dispatch half deferred into deliverable B behind new plumbing (expose a capsule for the dnd fake
window, or register the mock window in `global_state`). **Its adversarial verifier refuted that**, and
the refutation is simply what "consumed" means in kitty: **consumption IS the return value**
(`boss.py:2032-2066`), and the return value is observable by **calling the action directly** — no
dispatched mouse event is required at all. The narrow true fact behind the probe's claim is only that
`send_mock_mouse_event_to_window` cannot address the **dnd fake window**; generalising that to the
whole test is the same shape phase 1 kept producing. **Write T-pass as one unit. Do not invent the
plumbing.**

**§ 10.5 correction, which makes the region half of T-pass writable at all:** the research § 6.5 blanket warning *"do
NOT reach for the `dnd_test_*` family"* is right for **twelve** of the thirteen hooks (they drive
`w->drag_source`, the OSC protocol a client program uses) and **wrong for `dnd_test_set_mouse_pos`**,
which touches no `drag_source` field and writes `w->mouse_pos.{cell_x,cell_y,global_x,global_y}`
directly (v `dnd.c:2457-2468` / master `:2778-2790`). Those are exactly the fields a region predicate
reads, and it is the **only** headless way to place the pointer inside vs outside the band. Narrow
the rule to: *the twelve `drag_source`/OSC hooks are off-limits; `dnd_test_set_mouse_pos` is the
region-test lever.*

**Helpers:** a `_fake_window()` contextmanager wrapping `dnd_test_create_fake_window()` /
`dnd_test_cleanup_fake_window()` that calls `set_window_being_dragged()` in its `finally` — **the
state is process-global** — and the `kitty_tests/keys.py:688` `Boss.__new__(TestBoss)` idiom.

**Acceptance checklist before the patch is called done** (research § 4.7): `./autoformat` (the
declared `pre_commit` hook — `ruff format`, `gofmt -s -l -w tools kittens`, `clang-format`;
**master-only**, neither exists at v0.48.2) · `ruff check .` clean **including the `ANN` ruleset**,
single quotes, 160 columns, **no `from __future__ import annotations` anywhere**, PEP 604 unions ·
`./test.py type-check` clean — the checker is **`ty` (Astral), not mypy** · `./test.py` clean · the
two literal CI greps: **no trailing whitespace anywhere** and **no space after `` :code:` ``** ·
commit message capitalised imperative, optional `Area: ` prefix, **no Conventional Commits**.

🚨 **The docstring is structurally load-bearing** and the shipped interpreter runs
`sys.flags.optimize = 2`, so docstrings are stripped in a frozen build. `@ac` survives that only
because it takes the help as a **string argument**. An **empty** doc raises `IndexError: pop from
empty list` at `kitty/actions.py:49`; a group outside `groups` raises `KeyError` at `:53` — each
taking the command palette, the docs build and the Go codegen down with it. Both measured.

**Goal.** *A patch adding the mouse_drag_window action is complete in /private/tmp/kitty-dev and
passes kitty's own gates — proven by printing the output of `./autoformat`, `ruff check .`,
`./test.py type-check`, and `./test.py --module window_drag` showing its plan line and zero failures;
do not post anything to any upstream tracker, do not open a PR, and do not modify
/Users/chrisren/Development/claude-infrastructure.*

### W6 — Deliverable B on v0.48.2

**Deliverable.** The same action, built against the version the operator actually runs, in
`/private/tmp/kitty-482`, so the feature can be compared against his daily driver.

**Not a cherry-pick — see Q16 constraint 2.** `mouse_left_press_x/y` is master-only; W6 must add the
field (`state.h`'s `OSWindow`) and its write site (`glfw.c`'s LEFT-press branch, before the
`mouse_event(...)` call) before exposing it. **No test wave**: `kitty_tests/base.py` is master-only.
Verification is the sandbox and the hand.

**Goal.** *A patched v0.48.2 build launches and arms a window drag from a content-area chord press —
proven by printing `kitty +runpy 'import kitty; print(kitty.__file__)'` resolving under
/private/tmp/kitty-482 (never `--version`, which reads 0.48.2 for both builds) and
`get_window_being_dragged()` before and after an armed press; do not install it over
/Applications/kitty.app and do not change the operator's default terminal.*

### W7 — Our config integration — lands ARMED-OFF; the arming line is 🚨 GATED ON W4

**Deliverable.** The `globinclude` drop-in and its (empty) arming file, the § 7.1 retirements, and
the Q7 coupling test. **This wave's landed diff arms nothing** (§ 2.2 M1).

```
# --- config/kitty.conf, landed by W7 -------------------------------------------------
# The window-drag chord lives in a drop-in so that landing this file arms NOTHING. An empty
# drop-in is silent; writing the line below into it arms the chord in ~100ms via kitty's own
# __watch_conf__ child, and emptying the file again withdraws it in ~3s with no restart.
# 🚨 DISARM BY EMPTYING THE FILE, NEVER BY DELETING IT — a deletion does not fire the watcher.
globinclude drag-arm.d/*.conf

# --- config/drag-arm.d/drag.conf, landed EMPTY; this is the line the operator writes ---
# The drag lives on the band we draw. `press`, not `click`: promotion happens on MOTION, and a
# `click` is only synthesised on release. `grabbed,ungrabbed` because Claude Code runs in
# essentially every pane and holds the mouse.
mouse_map cmd+shift+left press grabbed,ungrabbed <kitten under A · mouse_drag_window 2 under B>
```

🚨 **Do NOT gate safety on the kitten's own return instead** (§ 2.2 M3). A `mouse_map … kitten …`
**always consumes the event** regardless of what the kitten returns, so a sentinel-file or env guard
inside the kitten makes the ACTION inert while leaving the BINDING live — silently killing whatever
default that chord had. The drop-in is inert at the *binding* layer, which is the only layer where
inertness is real.

**Retires** (research § 7.1): `map cmd+opt+b` (`:552`) — its only job is to raise real, hit-tested
bars so a pane can be dragged · the `combine :` prefix on ⌘⇧B (`:502`), collapsing it to a single
`launch` · `scripts/kitty-pane-title-toggle.sh` (93 lines) and `config/kitty-title-on.conf`, plus
their `install.sh` and `scripts/deploy-parity-assert.sh` wiring · `tests/kitty-conf-bindings.bats`'s
`real_bar_key()` / `glance_key()` role classifier, which exists solely to arbitrate **two** chords.

⚠️ **Do NOT delete `window_title_bar_align` or the four `window_title_bar_{active,inactive}_{fg,bg}`
colours** (`kitty.conf:1210-1214`). They look dead once real bars are never deliberately raised and
they are not: `TabManager.start_window_drag` paints the **drag thumbnail** in them (master
`tabs.py:2052-2053`).

**Goal.** *The chord the operator selected in W4 is landed in config/kitty.conf with the retirements
of § 7.1 applied and every kitty test green — proven by printing the TAP output of
tests/kitty-conf-bindings.bats and tests/kitty-title-zero-shift.bats with their `1..N` plan lines,
and `ls -la ~/.claude/scripts/kitty-drag-window.py` **(CORRECTED 2026-09-16: the W7 goal still carried the route-A `~/.config/kitty/` spelling that § 4.M superseded when it ruled route A′; W3 measured the deploy edge and it is `~/.claude/scripts/`)**; do not land this wave unless W4 has been driven by
a human hand and the operator has chosen the chord.*

### W8 — Recover the `draghold` CGEvent driver (Q18) — off the critical path, but TIME-BOXED

🚨 **It was NOT lost — RECOVER it, do not rewrite it, and run this wave EARLY rather than last.**
§ 4.M/Q18 measured that the original source, the compiled binary and **four calling harnesses
carrying the invocation** all survive — **but only in a reapable per-session scratchpad, with no
durable copy anywhere.** It is the only automated route to the mouse leg of a drag. That doc's own § J names the exact
failure being repeated: *"annotation that lives in a one-off HTML file is lost on the next render by
construction; annotation that lives in the command is not."* **Search the graveyard before
building** (`git log --all --diff-filter=A`, `git log -S'draghold'`).

**Not on the critical path**: it regression-proofs the feature, it does not ship it. And the premise
that would have killed it is refuted — the overlay doc's § I7 claim that *"a synthetic CGEvent stream
may be unable to begin an NSDraggingSession at all"* was **withdrawn by § I9 of that same file**, in
bold, with a measured four-row table (three drags reordered panes, with a `move_window` control
passing in the same run).

**Goal.** *A committed draghold driver reproduces a window drag in a sandbox kitty and its exact
invocation is recorded in the repo — proven by printing the committed invocation line and the
`--debug-input` output containing "Dragging session started at:"; do not run it while the operator
may be using the mouse, and do not point it at the operator's kitty.*

---

## § 6. DEFINITION OF DONE

Phase 3 is complete when **all** of the following hold. Each is a *check that prints*, never a
judgement.

| # | Criterion | The check |
|---|---|---|
| 1 | The six record corrections are landed, with the three refuted claims marked **in place** | `git diff origin/main~N -- config/kitty.conf` shows comment-only lines; grep finds each original clause still present |
| 2 | The route-A kitten exists in the repo and is deployed | ~~`ls -la ~/.claude/scripts/kitty-drag-window.py` **(CORRECTED 2026-09-16: the W7 goal still carried the route-A `~/.config/kitty/` spelling that § 4.M superseded when it ruled route A′; W3 measured the deploy edge and it is `~/.claude/scripts/`)**~~ — **CORRECTED 2026-09-16 (phase 3): that is the route-A path, and § 4.M ruled route A′.** The check is **`ls -la ~/.claude/scripts/kitty-drag-window.py`**, which is what the W3 goal already says. `install.sh:689` globs `scripts/*.sh` **and** `scripts/*.py`, so the kitten deploys through the existing symlink farm with no new `install.sh` line, no `kitty-setup.sh` `ln -sfn`, and no `deploy-parity-assert.sh` arm. |
| 3 | Every deploy gate is green with the new linked source declared | `tests/deploy-parity.bats` TAP with its `1..N` line, 0 failures; `scripts/deploy-parity-assert.sh` clean |
| 4 | **A human has driven the gesture** and the chord is chosen | W4's script prints a before/after `neighbors` diff showing the layout changed, set-change tested BEFORE order |
| 5 | The operator's styled pane header is draggable in his live kitty | the chord works in his own panes, by his own hand |
| 6 | The upstream patch is complete and passes kitty's own gates on master | `./autoformat`; `ruff check .`; `./test.py type-check`; `./test.py --module window_drag` with its plan line and 0 failures |
| 7 | A patched v0.48.2 build arms the drag | `kitty +runpy 'import kitty; print(kitty.__file__)'` under `/private/tmp/kitty-482` **(never `--version`)**; state before/after |
| 8 | The docs build passes with the new docstring | Q23's check, § 4.M |
| 9 | Nothing in this plan posted anything upstream | no PR, no issue, no comment — the operator's call |

**Explicitly NOT in the DoD, and why:**

- **Q10's answer.** If the graphics placement does not survive the relayout, that is cosmetic and the
  2 s refresh loop repaints it. Knowing is on the W4 checklist; a particular answer is not a gate.
- **W8.** The `draghold` driver regression-proofs the feature; it does not ship it.
- **Upstream acceptance.** Not ours to gate on, and on the observed norm the merge is slow and he
  pushes his own `Update changelog` / `cleanup previous PR` commits afterwards.

---

## § 7. KNOWN ISSUES, RESIDUALS, AND THINGS THAT WILL LOOK LIKE BUGS

Recorded here so they arrive as *known* rather than as bug reports. None of these blocks phase 3.

1. **The drag still steals a row, and more than one.** § 7.2 is blunt: the collapse buys a zero-shift
   *glance* plus a drag that still steals a row, resizes every PTY twice, and fires **at least four**
   relayouts per tab. You stop paying the row for the **decision** to rearrange; you still pay it for
   the **rearrange**. Plus a **second** row per OS window showing fewer than `tab_bar_min_tabs` tabs
   (a drag independently forces the tab bar visible, v `tabs.py:1288-1291` → `state.c:1149`), and our
   config leaves `tab_bar_min_tabs` at the default **2** — the `tab_bar_min_tabs 1` line is
   **commented out** at `config/kitty.conf:685` — so every single-tab OS window pays it.
2. **One drag turns the operator's toggled-on bars off across every tab of every OS window.**
   `_clear_force_show_title_bars` iterates `boss.all_tab_managers` while `toggle_window_title_bars`
   only ever sets the flag on `self.active_tab_manager`.
3. **A double chord-press under threshold pops the rename prompt** (v `tabs.py:1878-1881` /
   master `:2031-2034` reach `w.set_window_title()`). Our band does not do this today and nobody
   asked for it. **Decide before it ships as a surprise** — it is on W4's list precisely because a
   hand finds it in seconds.
4. **The unrecoverable state.** If the dragged window closes while the flag is set **and** the
   pointer is over no window, arm 7 resolves `tw == NULL` and calls nothing at all, ever. There is no
   C-side clear and **window/tab teardown does not clear it either** (V5).
5. **Two uncaught-exception paths leave bars forced up fleet-wide.** `draw_single_line_of_text` can
   raise `KeyError`/`RuntimeError` and `len(title_pixels) // (width*4)` can raise `ZeroDivisionError`
   at `width == 0` — **none is an `OSError`**, so `except OSError` (master `tabs.py:2060`) does not
   catch them and `force_show_title_bars` stays True on every tab with only a traceback in the log.
   On **master** additionally, `child-monitor.c:980`'s `if (!w) return;` leaves
   `thumbnail_request_queue[0]` unpopped **with no timeout**, wedging every future window drag, tab
   drag and `kitten screenshot` for the life of the process.
6. **Route A monkeypatches / calls drifting APIs.** Spelling (i) patches a private method; spelling
   (ii) calls a thumbnail API whose spelling **and arity** both changed between 0.48.2 and master.
   Upstream can break either silently. This is Q1's reason A is not the durable answer.
7. **The press site is not inert.** `Window.drag_source.initial_left_press` is armed by
   `arm_potential_drag()` on **every** content-area LEFT press — with no modifier test, so a chord
   press arms it — and on the content-press drag path it is **never cleared**, because
   `clear_potential_drag()` runs only from `handle_button_event` and the release is taken by arm 7.
   **The two entry points leave different C state behind. Whether that ever changes an outcome is
   UNKNOWN** (V13) — recorded as an open unknown, not as a settled non-issue.

---

## § 8. METHOD NOTES FOR PHASE 3 — the traps that cost phase 1 real time

1. 🚨 **A SUBAGENT CANNOT ANSWER A PERMISSION PROMPT.** Three phase-1 research agents wedged forever
   because their Bash command began with `rm -rf`, which this box's PreToolUse hook escalates to an
   ask; the pipeline barrier then never resolved and the synthesis never spawned. **Never put
   `rm -r`, `rm -rf`, `git clean`, `kill` or `pkill` in a subagent brief — and say so in the brief.**
2. **Read the version tag on every citation.** The two refs are byte-identical on the load-bearing
   routing path and differ materially in five — now **six** (§ 10.3's `mouse_left_press_x/y`) —
   other places. A line number quoted without its ref lands a reader in a different function. This
   happened repeatedly during phase 1.
3. **A chord probe without two known-TAKEN positive controls cannot tell a free chord from a
   mis-numbered button.** GLFW numbers **LEFT=0, RIGHT=1, MIDDLE=2**, while `mouse_button_map`
   (`kitty/options/utils.py:59`) maps *names* to the `b1/b2/b3` **strings** and is not the integer.
   Phase 1's first pass used `left=1` — which is RIGHT — and read `cmd+left press` as TAKEN. Only
   the controls caught it.
4. **Judge a skeptic on `correctedClaim`, never on the boolean.** Phase 1's skeptics were told to
   default `refuted=true` when they could not confirm, so most "REFUTED" rows are **confirmations
   carrying a correction**.
5. **`--version` cannot tell you which kitty you are running.** § 6.3 / Q16 constraint 3.
6. **The build path ceiling is 80 characters** and the session scratchpad root is 144. § 6.2 / Q16.
7. **Assert the `1..N` TAP plan line before believing any bats result.** A `cc-bats` refusal under
   contention prints its reason and exits **0**, which through a `grep -E "^(ok|not ok)"` filter is
   indistinguishable from a clean pass.
8. **The raw phase-1 artifacts hold far more detail than the synthesis kept** — A1..A12 plus
   `_VERDICTS.md` at
   `/private/tmp/claude-501/-private-tmp-wt-kitty-overlay/8294ff72-2d70-4ad2-86b9-33bc226c6f0e/scratchpad/research/`.
   They are **not committed and will not survive a reboot**. Anything phase 3 needs from them must be
   quoted into a tracked file first.

9. 🚨 **AND THAT REBOOT HAPPENED — 2026-09-16 15:50, mid-phase-3, about nine minutes into the
   first implementation wave.** Item 8 was right and understated it. `/private/tmp` is reaped on
   **reboot**, not merely eventually, and it took **everything** in one stroke: both built kitty
   trees (`/private/tmp/kitty-dev`, `/private/tmp/kitty-482`), every phase-1 artifact
   (`A1..A12` + `_VERDICTS.md`), every phase-2 probe log, and one wave's entire in-flight patch.

   **What survived is exactly what had been written into the repo worktree** — W1's record
   corrections, W2's kitten, W8's recovered `draghold`. Nothing else. Three consequences, each
   worth more than the hour it cost:

   - **W8's "run it EARLY, not last" ruling was vindicated by about two minutes.** The scratchpad
     `draghold` was recovered into `tools/draghold/` at 15:41-15:43 and its source was reaped at
     15:50. Had W8 been scheduled last, as "off the critical path" invites, the only copy of the
     driver, its build line and all four invocation-carrying harnesses would be gone permanently.
     **An item's position in a schedule is part of its risk, not a detail of its priority** — and
     the thing that makes a wave urgent can be the perishability of its INPUT rather than the
     value of its output.
   - **Build at a DURABLE short path.** The ~80-character ceiling is what put the trees in
     `/private/tmp`, and durability was never weighed against it. `~/kitty-dev` and `~/kitty-482`
     are **25 characters**, comfortably under the ceiling, and survive a reboot. There was never a
     trade here — only an unexamined default. *(§ 5's W5/W6 goals and § 6 DoD item 7 still name
     the `/private/tmp` paths; read those as "the built master tree" and "the built v0.48.2 tree".
     A symlink at the old path keeps the literal checks resolving.)*
   - **A deliverable that lives only outside the repo is not a deliverable yet.** Deliverable B is
     a patch against someone else's tree, so it has no natural home here — which is exactly why it
     needs a deliberate one. Phase 3 therefore also tracks the patch and its PR body under
     `docs/patches/`, so B survives a reboot the way A already did.
     `Scope (grown): +track deliverable B's patch and PR body in the repo` — Follow-On Gate
     F1-F4 PASS: net-positive, grounded in this session's own measured incident rather than in
     speculation, inside the same safety envelope, and bounded to two files.

