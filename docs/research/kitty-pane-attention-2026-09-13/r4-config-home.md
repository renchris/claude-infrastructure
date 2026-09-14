# R4 — Where kitty's config actually lives, and how panes get spawned

Read-only investigation, 2026-09-13. Nothing edited, nothing restarted. The running kitty
(pid 97084) was queried over its existing control socket only; no pane was created or closed
(`CC_KITTY_NO_SPAWN_CHECK=1` on the one checker run).

---

## 1. The headline correction: kitty is NOT running on defaults

The lead's finding is confirmed, but its **implication is inverted**. The symlink is dangling,
and the running instance is nevertheless fully configured.

**The symlink (confirmed dangling):**

```
~/.config/kitty/kitty.conf -> /private/tmp/adn-land.v9Ngbj/config/kitty.conf
```

- `test -e` ⇒ DANGLING. `/private/tmp/adn-land.v9Ngbj/` does not exist.
- Symlink birth **and** mtime: `2026-09-13T17:50:31` — i.e. **today**.

**The running instance predates the break by four days:**

| Fact | Value | Source |
|---|---|---|
| kitty pid | 97084 | `$KITTY_PID` |
| kitty started | **Wed 9 Sep 18:56:14 2026** (etime 04-01:41) | `ps -p 97084 -o lstart=,etime=` |
| symlink went dangling | **13 Sep 17:50:31** | `stat -f %SB` |
| kitty version | 0.48.2 | `kitty --version` |

**Three independent live readings prove a real config was loaded and is still held in memory.**
Each differs from kitty's built-in default:

| Option | Live value (`kitty @ get-colors` / `kitty @ ls`) | kitty default | repo `config/kitty.conf` |
|---|---|---|---|
| `background` | `#1e1e24` | `#000000` | `#1e1e24` (:634) |
| `active_border_color` | `#6194f3` | `#00ff00` | `#6194f3` (:730) |
| `inactive_border_color` | `#3a4555` | `#cccccc` | `#3a4555` (:731) |
| `enabled_layouts` | `["splits","stack"]` | `*` (all 7) | `splits,stack` (:64) |
| `listen_on` (implied) | socket `unix:/tmp/kitty-97084` exists | remote control OFF | `unix:/tmp/kitty-{kitty_pid}` (:111) |
| `foreground` | `#e6e6e6` | `#dddddd` | — |

Live values match the repo SSOT byte-for-byte. **Verdict: the running instance loaded
`config/kitty.conf` at 2026-09-09 18:56 and holds every value. It is healthy.**

🚨 **The exposure is a RESTART, not the present state.** kitty reads its config only at startup
(and on explicit reload). The next `Cmd+Q` → reopen reads a dangling path, finds nothing, and
drops to built-in defaults — losing every binding, the `splits` layout, and
`allow_remote_control`/`listen_on`. kitty-setup.sh's own closing note says
`allow_remote_control` and `listen_on` "are the only two options kitty cannot reload", so the
loss would be unrecoverable without a second restart after repair.

**Options the live instance reports** (brief's requested list; values not exposed by remote
control are taken from the loaded SSOT, marked ¹):

```
active_border_color        #6194f3          (live, get-colors)
inactive_border_color      #3a4555          (live, get-colors)
background                 #1e1e24          (live, get-colors)
background_opacity         1.0              (live, kitty @ ls)
window_border_width        1pt              ¹ config/kitty.conf:729
draw_minimal_borders       <not set in conf ⇒ kitty default `yes`>
window_padding_width       2 4              ¹ config/kitty.conf:719
inactive_text_alpha        <not set in conf ⇒ kitty default `1.0`>
dynamic_background_opacity <not set in conf ⇒ kitty default `no`>
allow_remote_control       socket-only      ¹ config/kitty.conf:95  (proven live: socket answers)
listen_on                  unix:/tmp/kitty-{kitty_pid}  ¹ :111 (proven live: /tmp/kitty-97084)
tab_bar_style              <not set in conf ⇒ kitty default `fade`>
tab_title_template         "{fmt.fg.red}{bell_symbol}{activity_symbol}{fmt.fg.tab}
                            {f'[{num_windows}] ' if num_windows > 1 else ''}
                            {f'⧉ ' if layout_name == 'stack' else ''}{title}"   ¹ :428
```

⚠️ `draw_minimal_borders`, `inactive_text_alpha`, `dynamic_background_opacity` and
`tab_bar_style` are **absent from the repo conf**, so they sit at kitty defaults. Note
`draw_minimal_borders yes` (the default) means kitty draws borders ONLY between adjacent
windows and omits the outer edge — directly relevant to any border-styling change.

**Config search order checked (macOS, kitty 0.48.2), every location:**

| Location | State |
|---|---|
| `$KITTY_CONFIG_DIRECTORY` | UNSET |
| `$XDG_CONFIG_HOME` | UNSET (so `~/.config` applies) |
| `~/.config/kitty/kitty.conf` | **dangling symlink** — the only entry in the dir |
| `~/Library/Preferences/kitty` | does not exist |
| `~/.kitty` | does not exist |
| `/Users/chrisren/Development/claude-infrastructure/config/kitty.conf` | **EXISTS, git-tracked, 755 lines, 55,580 B** |

Note `kitty --debug-config` **does not exist** on 0.48.2 (`Unknown flag: --debug-config`) — the
brief's suggested probe is unavailable. `kitty @ get-colors` + `kitty @ ls` were used instead.

---

## 2. The durable config path — it already exists and is the SSOT

**`~/Development/claude-infrastructure/config/kitty.conf`** is the single source of truth. It is
git-tracked, 755 lines, and is the file the running instance loaded.

The deploy mechanism is `scripts/kitty-setup.sh`:

```sh
scripts/kitty-setup.sh:36   REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
scripts/kitty-setup.sh:37   KCONF_DIR="${CC_KITTY_CONFIG_DIR:-$HOME/.config/kitty}"
scripts/kitty-setup.sh:179  SRC_CONF="$REPO/config/kitty.conf"
scripts/kitty-setup.sh:188  ln -sfn "$SRC_CONF" "$KCONF_DIR/kitty.conf"
scripts/kitty-setup.sh:190  [ "$(readlink "$KCONF_DIR/kitty.conf")" = "$SRC_CONF" ] && ok … || no …
```

⇒ **A styling change belongs in `config/kitty.conf` in this repo.** It reaches the live layer by
re-running `scripts/kitty-setup.sh` (which re-points the symlink) and then restarting kitty. No
new file or new deploy path is needed for the config itself.

### 2a. ROOT CAUSE of the dangling link — and a guard that could not fire

`$REPO` is derived from the script's own location (`:36`). The link therefore points wherever
the script was **run from**. `/private/tmp/adn-land.v9Ngbj` is an ephemeral tree that was reaped,
so `$REPO` resolved to a temp checkout at 17:50 today and the link followed it there.

kitty-setup.sh **already has a guard for exactly this**, and it names this failure in its own
words (`:97-107`):

```
kitty-setup: REFUSING to link the live layer from a NON-CANONICAL tree
  why : deploy fast-forwards the CHECKOUT, so a link into any other tree can
        never be moved by a land — and dangles once that tree is reaped.
```

**It did not fire.** Its predicate (`:88-106`) is:

```sh
_gdir=$(git -C "$REPO" rev-parse --git-dir); _gcommon=$(git -C "$REPO" rev-parse --git-common-dir)
[ "$_gdir" = "$_gcommon" ] && REPO_IS_LINKED_WT=0 || REPO_IS_LINKED_WT=1
[ "${REPO_IS_LINKED_WT:-0}" != 1 ] || <refuse>
```

The guard fires **only for a linked git worktree**. Two classes evade it, and both land on the
permissive default:

1. a **standalone clone or plain copy** in `/tmp` ⇒ `_gdir == _gcommon` ⇒ `REPO_IS_LINKED_WT=0`;
2. a **non-git tree** (tarball/`cp -R`) ⇒ both empty ⇒ `REPO_IS_LINKED_WT=""` ⇒ the `:-0` default.

`adn-land.v9Ngbj` appears in **no** `git worktree list` entry and in **no** file in this repo or
`~/.claude`, so it was not one of ours — consistent with class 1 or 2.

⇒ **The guard's predicate is `is a linked worktree` where the invariant it wants is `is a durable
path`.** This is the [aggregate-control / untested-belief] family: a checker whose population is
derived from a belief nobody tested. The durable predicate is a prefix test —
`case "$REPO" in "$REAL_HOME"/*) ok ;; *) refuse ;;` — which catches all three classes including
the one that actually bit. **Not fixed (read-only brief); reported.**

### 2b. The break is detectable but UNMONITORED

`scripts/kitty-setup.sh --check` catches it cleanly (run live, read-only):

```
1. kitty.conf
  ✗ kitty.conf is not linked to …/claude-infrastructure/config/kitty.conf
…
23 ok, 1 missing
```

Every other rung is green. But **nothing schedules this check**: no `~/Library/LaunchAgents`
plist references `kitty-setup` or `kitty-drift`, and `scripts/autonomy-sweep.sh` has no kitty
arm (its 2 `kitty` hits are unrelated comments). So the condition is silent until the next
restart surfaces it as a total loss of configuration.

Compounding it, `scripts/deploy-parity-assert.sh:742` **deliberately exempts** this file:

```sh
config/kitty.conf)   want=0 ;;
```

with a long, correct rationale (the destination is `$HOME/.config/kitty/kitty.conf`, not
`$CFG/<rel>`, so a per-file link would be *wrong*). Its own comment concedes the path is
"Unreachable from THIS walk today" because the `_tracked` pathspec at `:432` lists no `config/`
directory. So the repo's standing deploy auditor is structurally blind to this symlink's health
— by design, and correctly so for its question, but it means **no shipped always-on instrument
watches this link**.

### 2c. One live consumer, degrading correctly *today*

`scripts/handoff-fire.sh:1157-1163` reads the conf at spawn time to learn the socket template:

```sh
kitty_socket_template() {
  tmpl="$(sed -n 's/^…listen_on…/\1/p' "${CC_KITTY_CONF:-$HOME/.config/kitty/kitty.conf}" 2>/dev/null | tail -1 | tr -d '[:space:]')"
  [ -n "$tmpl" ] || tmpl="unix:${CC_FIRE_KITTY_SOCK_DIR:-/tmp}/kitty-{kitty_pid}"
}
```

On the dangling link the `sed` fails, `2>/dev/null` swallows it, `tmpl` is empty, and the
fallback is `unix:/tmp/kitty-{kitty_pid}` — which **happens to equal** the running config. So
firing works today. The function's own header documents the hazard precisely: the fallback is
"silently wrong the moment `listen_on` is retuned", and the failure shape is that every daemon
fire reverts to iTerm2, "byte-identical to *kitty is not running*". **A `listen_on` change made
while the link is dangling would be invisible and would break autonomous fires.** This is a
reason to fix the link *before* touching `listen_on`, not after.

---

## 3. Pane identity — how `ITERM_SESSION_ID` is faked, and whether it is stable

The shim is **in `~/.zshrc`**, not in a repo script at runtime. `scripts/kitty-setup.sh:290`
*writes* the block; the live copy is:

```sh
~/.zshrc:695    export ITERM_SESSION_ID="w0t0p0:$KITTY_WINDOW_ID"
```

Live in this pane: `KITTY_WINDOW_ID=321`, `ITERM_SESSION_ID=w0t0p0:321`. ✔ consistent.

**Why the shape:** `~/.zshrc:679-680` records Claude Code's own detection —

```
TERM_PROGRAM==="iTerm.app" || !!ITERM_SESSION_ID || terminal==="iTerm.app"
… derives the leader pane id as ITERM_SESSION_ID.slice(indexOf(":")+1) — so the COLON IS
```

i.e. CC takes everything after the first colon as the pane id. `w0t0p0:` is inert padding; the
kitty window id is the payload.

`~/.zshrc:684-693` records that the override is **UNCONDITIONAL** inside kitty (it used to be
guarded by `[ -z "$ITERM_SESSION_ID" ]`), because a stale inherited iTerm2 value is worse than
none — an iTerm2 UUID pointing at a pane that is not yours.

**Stability — three-layer answer:**

1. **Within a pane's life: stable.** `KITTY_WINDOW_ID` is assigned by kitty at window creation
   and never changes. It is a small monotonically-increasing integer (live ids seen: 265, 276,
   321, 326).
2. **Across a kitty restart: NOT stable.** Ids restart from a low counter, so a recorded id from
   a previous kitty process can collide with a live pane. `scripts/autonomy-sweep.sh:856` notes
   ids are "numeric … (kitty-normalised: `240 7 263 …`)" and warns a marker for pane `4`
   substring-matches.
3. **Inheritance is the live hazard.** `KITTY_WINDOW_ID` is exported into the environment and
   **inherited by every child**, including an iTerm2 pane launched from kitty. The repo's answer
   is `bin/cc-in-kitty`, which replaces the env check with an **ancestry** check (kitty must be
   a parent process). `tests/handoff-selfclose-kitty-identity.bats:162` pins the direction that
   must not flip: "a genuine iTerm2 pane with a POLLUTED `KITTY_WINDOW_ID` keeps its iTerm2 UUID".

So: **a pane's identity is stable and addressable for the life of the kitty process**, and
`kitty @ --match "id:$KITTY_WINDOW_ID"` is the correct way to address it. Do not persist an id
across a kitty restart.

---

## 4. Every `kitty @` / remote-control call site

**Architecture first:** `handoff-fire.sh` does **not** call `kitty @` directly. It calls `it2`
(the iTerm2 CLI surface). `~/.claude/bin/it2` is a **copy** of `bin/it2-wrapper`, which checks
`bin/cc-in-kitty` (ancestry) and, inside kitty, `exec`s `bin/it2-kitty` — the translation layer
that owns every kitty primitive.

```
handoff-fire.sh ──> it2 (= bin/it2-wrapper copy at ~/.claude/bin/it2)
                      │  bin/it2-wrapper:114-127  resolve it2-kitty + cc-in-kitty
                      │  bin/it2-wrapper:123      exec "$_it2_kitty" "$@"   ← the divert
                      │  bin/it2-wrapper:259      exec "$REAL_IT2" "$@"     ← genuine iTerm2
                      └─> bin/it2-kitty ──> kitty @ launch / focus-window / … (the socket)
```

`bin/it2-wrapper:127` refuses a third state explicitly: *"exists but is not executable — refusing
to fall through to iTerm2 from inside kitty"*.

**Call sites (file:line → what it does):**

| File:line | Call | Purpose |
|---|---|---|
| `bin/it2-kitty` (whole file, ~950+ lines) | the full `kitty @` surface | **The primitive owner.** Translates every `it2` verb into `kitty @`. `:35` documents the `ITERM_SESSION_ID="w0t0p0:<KITTY_WINDOW_ID>"` contract; `:953` documents the login-PATH race and the `.zshrc` synthesis |
| `bin/kitty-split-launch.sh:17,161,171` | `kitty @ launch --match "window_id:<anchor>" --next-to "id:<anchor>"` | **Anchored split.** Header (`:5-15`) records why: a bare `--location=vsplit` places relative to kitty's *active* window, not the caller's, so a split fired from a background pane landed in the wrong tab. `--next-to` pins it. Prints the new window id — `:161` notes it is the ONLY place that id exists. `:48` records `--session-id $KITTY_WINDOW_ID` fixing a self-retire failure. `:109` anchor defaults to `$KITTY_WINDOW_ID`. `:81` notes **no in-tree caller** (⌘D is bound to `kitty-split-cwd.sh` instead) — used by resume/handoff paths |
| `bin/cc-resume-layout.sh:183` | `kitty @ ls` piped to python | Reads `platform_window_id` (the CGWindow number) to map a kitty window onto a physical screen |
| `bin/cc-resume-layout.sh:303` (per `tests/handoff-recycle-pane-survives.bats:9`) | `kitty @ launch --type=os-window … -- "$RESUME_ONE"` | Recreates a whole OS window during session recovery |
| `bin/cc-resume-layout.sh:325` | `kitty @ action` | Equalize; comment warns it acts on the ACTIVE window, not the invoking one |
| `bin/cc-resume-layout.sh:362-363` | `kitty @ focus-window --match "id:$KITTY_WINDOW_ID"` | Restores focus to the caller at the end |
| `bin/cc-resume-layout.sh:28` | `kitty @ detach-window --target-tab id:N` | Documented trap: matches a **tab** id, not a window id |
| `bin/cc-resume-layout.sh:41` | `kitty @ resize-os-window --action` | Notes it offers resize/hide/toggle and **nothing that moves** a window |
| `bin/cc-kitty-socket` | socket address resolution | Resolves the control socket when `KITTY_LISTEN_ON` is absent (launchd/daemon jobs carry none). `tests/cc-kitty-socket.bats:4` — "what stops autonomous spawns falling [back to iTerm2]"; `:99` `KITTY_LISTEN_ON` fast path wins when live, `:106` stale socket falls through to a glob |
| `bin/cc-kitty-bin` | locates the kitty binary | Named as a precedent at `autonomy-sweep.sh:1865` |
| `bin/cc-in-kitty` | ancestry check, no `kitty @` | Terminal identity. Honors `CC_TERM` verbatim ahead of every check (`:51,67-69`) |
| `bin/kitty-split-cwd.sh` | split helper | The program ⌘D / ⌘⇧D name in `config/kitty.conf` |
| `bin/kitty-confirm-close` | close guard | ⌘W / ⌃⇧W / ⌘⇧W |
| `bin/kitty-pane-menu` + `bin/kitty-pane-menu-native.swift` | ⌘→ "Move Session to…" | Native NSMenu, compiled by `kitty-setup.sh:245` (`swiftc`) |
| `scripts/handoff-fire.sh:1157-1163` | reads `kitty.conf` (not `kitty @`) | `kitty_socket_template()` — see §2c |
| `scripts/handoff-fire.sh:1202` | kitty control-socket call, bounded via `hf_bounded` | Same bounding as every osascript |
| `assets/demo/kitty-panes-capture.sh:21` | `kitty --instance-group=ccpanes --config <repo>/config/kitty.conf` | Demo capture — a **separate** instance, good precedent for testing a conf change without touching the running one |
| `install.sh:1167` | note re `Bash(kitten @ send-text:*)` permission | A locally-accreted permission entry not in the template |

**Everything reachable from a hook or launchd goes through `bin/cc-kitty-socket`**, because those
contexts have no `KITTY_LISTEN_ON`. `kitty-setup.sh --check` confirms this works live:
*"daemon-PATH probe: 'session list' works with no Homebrew on PATH (26 panes)"*.

---

## 5. Migration state — honest reading: COMPLETE in practice, PERMANENTLY SHIMMED by design

**This is not an in-flight migration.** There is no cutover plan to finish. The settled
architecture is: *keep the iTerm2 `it2` call surface forever; translate it to kitty at the edge.*

Evidence:

- `teammateMode=iterm2` in **all five** config dirs (`.claude`, `.claude-next`,
  `.claude-secondary`, `.claude-tertiary`, `.claude-quaternary`) — all green in `--check`. The
  string "iterm2" is what Claude Code requires; the kitty divert happens below it.
- `ITERM_SESSION_ID` is **synthesised** rather than replaced, because CC's own detection
  (`~/.zshrc:679-680`) keys on it.
- `it2` call sites are **live, not dead**: `handoff-fire.sh` still calls `it2` and osascript
  throughout (`:1410, :1548, :1760, :8067, :8121, :8130`).
- `bin/it2-wrapper:80-101` records the shim being *hardened* (2026-08-05), not retired.
- `install.sh:1324-1352` wires kitty **unconditionally when kitty is present** — "Zero-click by
  default … a new user never has [to]". This is shipped, supported behaviour.

**osascript/AppleEvents paths remain live for genuine iTerm2 panes.** `handoff-fire.sh:6362`
records the architectural constraint that AppleEvents fail unreliably from detached/orphaned
processes — which is part of why the kitty socket path is preferred where available.

Research record: `docs/research/kitty-selfclose-chain-2026-08-04.md`. Drift instrumentation
exists (`scripts/kitty-drift-run.sh`, `scripts/kitty-drift-collect.sh`, data at
`docs/research/data/kitty-drift-*.tsv`, 2026-07-31) but is **not scheduled** — it was a
measurement campaign, not a standing monitor.

Test coverage is substantial and pins the conf itself:
`tests/kitty-conf-bindings.bats` (12 tests incl. **two mutant controls** —
"dropping our cmd+shift+d line lets close_window win, and the guard sees it" `:119`, and the
confirm-helper equivalent `:234`), plus `kitty-setup-*`, `kitty-split-launch-*`,
`kitty-socket-address`, `kitty-recovery-launch`, `kitty-divert-real-it2`,
`handoff-selfclose-kitty-identity`, `cc-kitty-socket`.

⚠️ **Consequence for a styling change:** `tests/kitty-conf-bindings.bats` asserts on the *text*
of `config/kitty.conf`. A styling edit must not disturb the pinned lines (the split chords, the
`splits` layout at `:135`, `window_drag_tolerance` `:143`, `drag_threshold` `:159`, the close
chords `:225`). Run that suite after editing.

---

## 6. Deploy path for a new file — the precise naming rule

**Config:** `config/kitty.conf` is **not** deployed by `install.sh`'s symlink machinery at all
(`install.sh` contains no `config/` loop; `deploy-parity-assert.sh:742` declares `want=0`). It is
deployed **only** by `scripts/kitty-setup.sh:188`. Editing the repo file is enough *once the
symlink is repaired*, because it is a symlink — edits are live-on-restart with no redeploy step.

**A new helper script — three options, in order of preference:**

1. **Name it `bin/cc-kitty-<thing>`** (or any `bin/cc-*`). `install.sh:923-935` symlinks the
   globs `bin/cc-* bin/desk-* bin/ms365-*` into `~/.claude/bin/`, explicitly *"Glob both
   families rather than naming files, so a new … tool deploys without another install.sh edit."*
   Precedents already in tree: `bin/cc-kitty-bin`, `bin/cc-kitty-socket`, `bin/cc-in-kitty`.
   **This is the zero-friction path — no installer edit, no parity declaration.**
2. A name outside those globs (e.g. `bin/kitty-foo.sh`) gets **no symlink from install.sh** and
   requires an explicit `ln -sfn` line in `kitty-setup.sh` (joining the seven at
   `:188,201,205,210,221,222,223`). `deploy-parity-assert.sh`'s comment block records that
   kitty-setup deploys **nine** repo sources by **three** actions (7 `ln -sfn`, 1 `cp` at `:215`,
   1 `swiftc` at `:245`), and that `tests/deploy-parity.bats` asserts the partitions **SUM** —
   so an eighth link target **refuses** rather than being silently absorbed. Adding one means
   updating that test.
3. If the helper must be invoked by a kitty **key binding**, it must additionally be named in
   `config/kitty.conf` and deployed to `~/.claude/bin/` by kitty-setup (the ⌘D/⌘W/⌘→ precedent),
   because kitty resolves the binding's program at press time from the live layer.

⚠️ `install.sh:926-930` notes `~/.claude/bin` is **load-bearing by absolute path** (the
`/handoff --notify-back` trailer references `$HOME/.claude/bin/cc-notify`), so that is the
correct destination.

---

## 7. Adversarial pass — what I checked that the brief did not ask

1. **"Is the running instance actually on defaults?"** — the brief's framing. Checking it
   properly *inverted* the answer (§1). Had a styling change been made and kitty restarted to
   "see it", the operator would have lost every binding and blamed the change.
2. **"Does anything already detect this?"** — yes, `kitty-setup.sh --check`, and it is green on
   23/24 rungs. **But nothing schedules it** (no LaunchAgent, no autonomy-sweep arm), and the
   standing deploy auditor exempts the path by design (§2b). The gap is monitoring, not detection.
3. **"Does the dangling link break anything RIGHT NOW?"** — one live consumer,
   `handoff-fire.sh kitty_socket_template()`. It degrades to a fallback that coincidentally
   matches the live config, so fires still work — but that coincidence dissolves the moment
   `listen_on` is retuned (§2c). Ordering constraint for any future work.
4. **"Why didn't the existing guard fire?"** — the predicate is `is a linked worktree`, the
   invariant wanted is `is a durable path`; two evasion classes land on the permissive default
   (§2a). This is the actual root cause and it is a one-line-class fix, not reported by any tool.
5. **Options absent from the conf.** `draw_minimal_borders`, `inactive_text_alpha`,
   `dynamic_background_opacity`, `tab_bar_style` are unset ⇒ kitty defaults. `draw_minimal_borders
   yes` (default) suppresses outer-edge borders — a border-styling change that assumes full
   borders will not render as expected (§1).
6. **Will a styling edit redden a test?** Yes, potentially — `tests/kitty-conf-bindings.bats`
   asserts on the conf's text and ships two mutant controls (§5).

**Residual uncertainties, named:**

- The exact provenance of `/private/tmp/adn-land.v9Ngbj` is **unrecoverable** — the tree is
  reaped and the string appears in no file in this repo or `~/.claude`. Whether it was a
  standalone clone (guard-evasion class 1) or a non-git copy (class 2) cannot be determined.
  Both evade the guard identically, so the remedy is the same either way.
- Which process wrote the symlink at 17:50 today is likewise not recoverable from disk; the
  bash logs mention `kitty-setup` but were not pattern-matched to a timestamped invocation
  (grep found the token in 4 log files; attributing one to 17:50:31 was not pursued, as the
  mechanism is already proven by `:36`/`:188`).
- `draw_minimal_borders` / `inactive_text_alpha` / `tab_bar_style` live values were inferred
  from *"absent from the loaded conf ⇒ kitty default"*, not read from the instance — kitty's
  remote control exposes colors and window structure but not these scalars. The inference is
  sound (the conf is the only input) but is an inference, marked ¹ in §1.

---

## 8. Recommended sequence (not executed — read-only brief)

1. **Repair the symlink first, before any styling edit and before any kitty restart:**
   `scripts/kitty-setup.sh` run **from the canonical checkout**
   (`~/Development/claude-infrastructure`). Verify with `--check` ⇒ expect `24 ok, 0 missing`.
2. Make the styling change in `config/kitty.conf` (the symlink makes it live-on-restart).
3. Run `tests/kitty-conf-bindings.bats`.
4. Preview without touching the running instance using the demo precedent:
   `kitty --instance-group=<name> --config <repo>/config/kitty.conf`
   (`assets/demo/kitty-panes-capture.sh:21`).
5. Only then restart kitty. Note `allow_remote_control`/`listen_on` need a full `Cmd+Q`, not
   `Ctrl+Cmd+,`.
6. Consider hardening `kitty-setup.sh`'s guard to a durable-path prefix test (§2a) and adding a
   scheduled `--check` arm (§2b). Both are out of this brief's read-only scope.
