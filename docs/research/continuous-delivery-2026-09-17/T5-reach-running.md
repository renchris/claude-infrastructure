# T5 — What each artifact class requires to reach a RUNNING kitty session

Subject: operator kitty **pid 73832** (started `Wed 16 Sep 20:13:53 2026`), kitty **0.48.2**.
Source read at `~/k482` (verified same version as the running binary — see Instrument).
All work READ-ONLY against the live kitty: no keystrokes, no `kitty @ action`, no signals to 73832.

## Instrument / provenance

- `/Applications/kitty.app/Contents/MacOS/kitty --version` → `kitty 0.48.2` ; `kitten --version` → `kitten 0.48.2`
  ; `~/k482/kitty/constants.py:25` → `version: Version = Version(0, 48, 2)`. **The source tree I read is the
  binary that is running.**
- Live watcher argv, RAN (`ps -axo pid=,ppid=,lstart=,command=`):
  ```
  73832     1 Wed 16 Sep 20:13:53 2026  /Applications/kitty.app/Contents/MacOS/kitty
  74784 73832 Wed 16 Sep 20:13:53 2026  /Applications/kitty.app/Contents/MacOS/kitten __watch_conf__ 73832 100 /etc/xdg/kitty/kitty.conf /Users/chrisren/.config/kitty/kitty.conf
  ```
  Argv = `<kitty_pid> <debounce_ms> <config_paths...>` (`~/k482/tools/watch/api.go:234`). Debounce **100 ms**.
- **Controlled experiment (RAN).** I ran the *same* `kitten __watch_conf__` binary against a sandbox config
  tree under the scratchpad, targeting a throwaway `bash` process of my own that traps `SIGUSR1` and logs
  `$EPOCHREALTIME`. The live kitty was never the signal target. Both the watcher (stdin held by `sleep N`,
  exits on EOF) and the trap process (bounded `for` loop) self-terminate — nothing was killed.
  Scripts + logs: `<scratchpad>/watchtest/{run1,run2,run3}.sh`, `arm{1,2,3}.log`.

---

## THE TABLE

| # | Artifact class | Reload mechanism | Trigger | Latency | Restart REQUIRED? | Conviction |
|---|---|---|---|---|---|---|
| a | `kitty.conf` (option lines) | fs-watch → `SIGUSR1` → `Boss.load_config_file` → `apply_new_options` | any write to a file **in the resolved conf set** | **~0.12–0.21 s** (RAN) | **No — for most options.** **YES** for a named minority, and **2 of ours are in it** (`listen_on`, `macos_option_as_alt`) | 97% |
| b | `globinclude` drop-ins `~/.config/kitty/drag-arm.d/*.conf` | same watcher, set re-derived on every event | write / create / **empty** a matching file. **DELETE does not fire.** Dir must already be "warm" | ~0.10–0.21 s once warm; **never**, if cold | No | 97% |
| c | per-keypress shell script (`kitty-pane-title-toggle.sh`) | none needed — `execvp`'d fresh per press | next keypress | next press | **No** | 96% |
| d | long-lived python daemon (`kitty-pane-title-overlay.py`) | none — code is in RAM for the process lifetime | only a **new process**; requires the old one to exit (idle-exit) or be killed | until daemon exit | **No restart of *kitty*; yes restart of the *daemon*** | see §d |
| e | the kitty **binary** (C patch) | none | — | — | **YES — full kitty restart** | 99% |
| f | `~/.claude/**` hooks & scripts (per-file symlinks) | no reload layer; each invocation `open()`s the path | next invocation | next invocation | **No** — but an **ADD** is invisible until `install.sh` creates the link | 95% |

---

## (a) `kitty.conf` — the option lines

### Mechanism, read from source

1. `~/k482/kitty/boss.py:1418-1422` spawns the watcher **once per boss lifetime**:
   ```python
   if opts.auto_reload_config >= 0 and not hasattr(self, 'config_reload_watcher_process') and opts.all_config_paths:
       self.config_reload_watcher_process = subprocess.Popen(
           [kitten_exe(), '__watch_conf__', str(os.getpid()), str(int(opts.auto_reload_config * 1000))] +
           list(opts.all_config_paths), stdin=subprocess.PIPE)
   ```
2. The watcher's action is a signal, nothing more — `~/k482/tools/watch/api.go:223-225`:
   `func signal_kitty_to_reload_config(kitty_pid int) error { return unix.Kill(kitty_pid, unix.SIGUSR1) }`
3. kitty's C signal handler only sets a flag — `~/k482/kitty/child-monitor.c:1537-1539`:
   `case SIGUSR1: ss->reload_config = true; break;`
4. Which lands in `Boss.load_config_file` (`boss.py:3199`) → `apply_new_options` (`boss.py:3146`).

### What `apply_new_options` actually re-applies (boss.py:3146-3188)

`set_options` → `apply_options_update` → `set_layout_options` → `set_default_env` → `set_font_family` +
`os_window_font_size` + `tm.resize()` → `cocoa_clear_global_shortcuts` → `mappings.update_keymap()` →
`cocoa_recreate_global_menu()` → `tm.apply_options()` for every tab manager → theme refresh → per-window
`refresh(reload_all_gpu_data=True)` → `load_shader_programs.recompile_if_needed()`.
Also `clear_font_caches`, `open_actions.clear_caches`, `clear_mime_cache`, `tab_bar.clear_caches`.

Note `load_config_file`'s own docstring: *"Loading a config file **replaces** all config options"* — it is not a
merge, so an option deleted from the file reverts to its default on reload.

### RAN — signal latency, arm 1 (`arm1.log`)

| event | action | SIG? | Δ from event |
|---|---|---|---|
| A | append a line to `main.conf` | **yes** | **182 ms** |
| H | `touch main.conf` (mtime only, no content change) | **yes** | **147 ms** |

Debounce is 100 ms, so the floor is ~0.1 s and observed total is ~0.12–0.21 s. **The repo's "~3 s" figure is
not the signal latency** — the SIGUSR1 arrives in ~0.15 s. If ~3 s was observed end-to-end it is either
observation overhead or kitty-side redraw, not the watcher.

### RESTART-REQUIRED options — the enumeration (READ, `~/k482/kitty/options/definition.py`)

Every option whose own `long_text` says reload does not (fully) work:

| Option | definition.py | What the doc says |
|---|---|---|
| `listen_on` | L2812 | "Changing this option by reloading the config is **not supported**." |
| `macos_option_as_alt` | L3254 | "Changing this option by reloading the config is **not supported**." |
| `macos_hide_from_tasks` | L3266 | "…**not supported**." |
| `macos_custom_beam_cursor` | L3394 | "…**not supported**." |
| `dynamic_background_opacity` | L2449 | "…**not supported**." |
| `update_check_interval` | L2923 | "…**not supported**." |
| `startup_session` | L2951 | "…**not supported**." |
| `wayland_enable_ime` | L3437 | "…not supported, it will not have any effect." (Linux only) |
| `momentum_scroll` | L824 | "Changes to this setting only take effect **after a kitty restart**." |
| `undercurl_style` | L254 | "…via reloading the config or remote control is **undefined**." |
| `underline_exclusion` | L270 | "…**undefined**." |
| `scrollback_lines` | L524 | on reload, only *newly created* windows |
| `scrollback_pager_history_size` | L747 | on reload, only *newly created* windows |
| `term` | L3147 | only *newly created* windows |
| `watcher` | L2882 | only windows created *after* the reload |
| `underline_hyperlinks` | L982 | to/from `always` only affects new windows |
| `cursor_shape` | L387 | only changed if the app has not set it |
| `background_opacity` | L2395 | has a perf cost; reload caveat |
| (general) | L4469-4470 | "a handful of options cannot be dynamically changed and **require a full restart**… when changing shortcuts for actions located on the **macOS global menu bar**, a full restart is needed." |

### 🚨 Are any of OURS in that set? YES — two.

RAN, `grep -n` over `config/kitty.conf`:

```
107:allow_remote_control socket-only
123:listen_on unix:/tmp/kitty-{kitty_pid}      <-- RESTART-REQUIRED (definition.py:2812)
296:macos_option_as_alt left                    <-- RESTART-REQUIRED (definition.py:3254)
867:scrollback_lines 2000                       <-- new windows only (definition.py:524)
915:macos_quit_when_last_window_closed no
1240:window_padding_width  0 5 0 5
1508:globinclude drag-arm.d/*.conf
```

**Consequence:** a change to `listen_on` or `macos_option_as_alt` will be silently accepted by the reload and
have **no effect** — the reload path gives no error. `listen_on` in particular is load-bearing here: it is what
mints `/tmp/kitty-{kitty_pid}`, the socket `scripts/kitty-drag-w4.sh` keys its safety glob on.
Also per L4469: **a new/changed macOS global-menu-bar shortcut needs a full restart**, even though
`cocoa_recreate_global_menu()` runs on reload.

`window_padding_width` (L1240) is **not** in the restart set — it is applied via `tm.resize()`. Good, because the
title-band work drives it.

---

## (b) `globinclude` drop-ins — `~/.config/kitty/drag-arm.d/*.conf`

### Mechanism (READ)

The watcher does **not** watch files; it watches the **parent directory** of every conf file,
**non-recursively**, and re-derives the whole conf set on every event
(`~/k482/tools/watch/api.go:112-208`):

```go
new_all_paths := get_set_of_config_files(config_paths)
if new_all_paths.Has(resolve_path(event.Path)) {
        ... rebuild desired_dirs; sync_watched_dirs()
        if err := action(); err != nil { ... }      // <-- SIGUSR1 only inside this branch
}
```

`get_set_of_config_files` (api.go:90-110) re-parses the top-level configs with a real `ConfigParser`
and collects `AllIncludedFiles`. `globinclude` is expanded with `filepath.Glob` **at parse time**
(`~/k482/tools/config/api.go:221-229`), and a file is registered only when `os.ReadFile` succeeded
(`tools/config/api.go:122-123`, reached from api.go:258-262).

**So the reload predicate is: "is the changed path a member of the conf set *as it exists right now*?"**

### 🚨 That single line explains the repo's empty-vs-delete asymmetry

- **Emptying** a drop-in: the file still exists → still matches the glob → still in `new_all_paths` →
  `Has(event.Path)` is TRUE → **SIGUSR1 fires**.
- **Deleting** a drop-in: it no longer matches the glob → no longer in `new_all_paths` →
  `Has(event.Path)` is **FALSE** → **no signal, and kitty keeps running the deleted file's settings**
  until something else touches a conf file.

### RAN — arm 1 proves it (`arm1.log`), sandbox, same binary

| event | action | SIG? | Δ |
|---|---|---|---|
| B | append to `sub.d/a.conf` | **yes** | 159 ms |
| C | **empty** `sub.d/a.conf` (`: > file`) | **yes** | **149 ms** |
| D | **remove** `sub.d/a.conf` (moved out of dir) | **NO** | — (4 s waited) |
| E | restore it | **yes** | 133 ms |
| F | create a **new** matching `sub.d/b.conf` | **yes** | 122 ms |
| G | create a **non**-matching `sub.d/c.txt` | **NO** | — (3 s waited) |

**The repo's claim is correct and now has a mechanism and a control.** (G is the negative control that
proves the instrument can say "no" for a reason other than the delete.)

### 🚨 SECOND, UNRECORDED FINDING — a COLD drop-in directory is not watched at all

`desired_dirs` is built from the conf set **at watcher start**, and is only rebuilt inside the
`Has(event.Path)` branch (api.go:186-198). If the drop-in directory did not exist when the watcher started,
the glob matched nothing, so the directory is in neither `desired_dirs` nor `watched_dirs`.

**This is the live situation.** RAN:
- watcher 74784 started `Wed 16 Sep 20:13:53`
- `ls -la ~/.config/kitty` → `drwxr-xr-x@ 3 chrisren staff 96 Sep 16 22:47 drag-arm.d` — **created 2 h 33 min
  after the watcher**.

Arm 2 reproduces it exactly (`arm2.log`), with the drop-in dir absent at watcher start:

| event | action | SIG? |
|---|---|---|
| P | `mkdir sub.d` | **NO** |
| Q | create `sub.d/a.conf` (matches the glob!) | **NO** |
| R | modify `sub.d/a.conf` | **NO** |
| S | `touch main2.conf` | **yes** (214 ms) — *this* is the event that rebuilds `desired_dirs` and adopts `sub.d` |
| T | modify `sub.d/a.conf` again | **yes** (126 ms) — now warm |

**Operational rule:** after creating a *new* drop-in directory, one write to `kitty.conf` itself is required
before drop-in edits are live-reloadable at all. Until then, drop-in writes are silently inert.

### THIRD FINDING — the symlink means the watched directory is the REPO, not `~/.config/kitty`

`~/.config/kitty/kitty.conf` → `/Users/chrisren/Development/claude-infrastructure/config/kitty.conf` (RAN, `ls -la`).
`get_set_of_config_files` stores `safe_eval_symlinks(...)` of each path (api.go:104-107), so the **fully
resolved repo path** is what lands in the set, and the repo's `config/` directory is what gets watched.
Meanwhile `resolve_path(event.Path)` resolves only the *directory* component (api.go:75-80), not the file.

Arm 3 (`arm3.log`), a sandbox with the identical topology:

| event | action | SIG? | Δ |
|---|---|---|---|
| X | edit the **real repo-side file** the symlink points at | **yes** | **159 ms** |
| Y | edit the drop-in through the link dir | **yes** | 104 ms |
| Z | re-create the **symlink itself** (`ln -sf`) | **NO** | — |

**Consequence:** editing `config/kitty.conf` **in this repo** reloads the operator's live kitty within ~0.15 s.
There is no "deploy" step for kitty.conf at all — the repo file *is* the live file. A `/ship` is for durability
and review, not for reach. Conversely, re-pointing the symlink does **not** trigger a reload.

### Bootstrap corollary worth stating

`opts.all_config_paths` is captured once at `Boss.start` and the spawn is guarded by
`not hasattr(self, 'config_reload_watcher_process')` (boss.py:1418) — the watcher is **never re-spawned**,
so a reload that changes `auto_reload_config` (its debounce) or the top-level config path set does not take
effect until kitty restarts.

### 🚨 RAN — the LIVE watcher's own state, read without touching it

`lsof -p 74784` (read-only). The macOS backend is **kqueue** (`fswatcher@v1.3.0/watcher_darwin.go:15`,
`kqueueOpenFlags = unix.O_EVTONLY`), which needs **one open fd per watched path**, so the watcher's fd
table *is* a printout of what it is watching:

```
kitten 74784 ... 3u  KQUEUE
kitten 74784 ... 4r  DIR  /Users/chrisren/.config/kitty/drag-arm.d              <-- DROP-IN DIR: WARM
kitten 74784 ... 5r  REG  /Users/chrisren/.config/kitty/drag-arm.d/drag.conf    <-- the live drop-in
kitten 74784 ... 6r  DIR  /Users/chrisren/.config/kitty
kitten 74784 ... 8r  REG  /Users/chrisren/Development/claude-infrastructure/config/kitty.conf
kitten 74784 ... 10r DIR  /Users/chrisren/Development/claude-infrastructure/config   <-- THE REPO DIR
kitten 74784 ... 12r DIR  .../config/drag-arm.d
kitten 74784 ... 13r REG  .../config/drag-arm.d/drag.conf.example
kitten 74784 ... 14r DIR  .../config/hook-chains.d
kitten 74784 ... 11r,15r..23r,25r REG  .../config/{coldcompile.patterns,iterm2-perf.keys,live-only.manifest,qos-*.patterns,store-bounds.manifest,kitty-title-{on,off}.conf,...}
```

Three things this settles outright:

1. **`~/.config/kitty/drag-arm.d` IS currently watched (fd 4) and its `drag.conf` IS in the set (fd 5).**
   The cold-start hazard above was real but has already been discharged: `config/kitty.conf` was written at
   `23:28:24` — *after* the drop-in dir appeared at `22:47:59` — and that write is exactly arm 2's event S,
   the one that rebuilds `desired_dirs`. **Drop-in edits on this kitty are live right now.**
2. **The repo's own `config/` directory is watched (fd 10)** — the live consequence of the symlink, and
   independent confirmation of arm 3. Every write to *any* file in `config/` (patterns files, manifests,
   hook-chains) wakes the watcher and costs a full re-parse of the 119 KB `kitty.conf`; the watcher then
   correctly declines to signal, because those paths are not in the conf set.
3. **The 3 watched roots are `{repo config/, ~/.config/kitty, ~/.config/kitty/drag-arm.d}`**, exactly as
   `desired_dirs` derives them. The other DIR fds (12, 14) are *entries* of a watched root; kqueue opens an
   fd per entry and `scanDirectoryLocked` (`watcher_kqueue.go:175-213`) registers new entries as they appear.

**Caveat, stated rather than hidden:** `isSystemFile` (`fswatcher/filters.go:68-82`) drops events *before*
the membership test for any basename starting `~ ._ .DS_Store` or ending `.tmp .bak .swp .swo ~ .plist
.download .part`. A drop-in written by an editor that leaves `drag.conf~` is invisible; `*.conf` itself is
safe. (READ only — not exercised.)

### Corroboration and one discrepancy

- The repo's `config/kitty.conf:1456-1458` says arming takes **~100 ms** — my RAN figure of **122-182 ms**
  agrees, and the 100 ms is the debounce floor (`__watch_conf__ 73832 **100**`).
- The same line says disarming by emptying "withdraws it in **~3 s**". **The SIGUSR1 arrives in ~0.15 s
  (RAN).** The residual is kitty-side: `apply_new_options` clears font caches, recompiles shaders and does
  `refresh(reload_all_gpu_data=True)` for every window across 11-13 panes. I did **not** measure kitty's
  apply time (doing so means watching the live kitty react). **Both figures can be true of different
  things** — signal vs. visible effect. Conviction that ~3 s is apply-time rather than a bad reading: 60%.
- `config/kitty.conf:1500` records, from the **Python** side, that the glob resolves relative to the path
  kitty is *given*, not the symlink target. I reached the same conclusion independently from the **Go**
  side: `ConfigParser.ParseFiles` (`tools/config/api.go:274-286`) applies `filepath.Abs` only — never
  `EvalSymlinks` — before taking `filepath.Dir(path)` as the include base. **Two independent instruments,
  same answer.** Note the asymmetry the repo does not record: the *watcher* fully resolves symlinks for its
  watched-path set (`safe_eval_symlinks`, `tools/watch/api.go:104-107`) while the *include base* stays
  unresolved — which is why it watches the repo dir and the live drop-in dir at the same time.

---

## (c) Per-keypress shell script — `scripts/kitty-pane-title-toggle.sh`

**CONFIRMED: no reload of anything is needed. Conviction 96%.**

Binding (`config/kitty.conf:596`):
```
map cmd+shift+b combine : launch --type=background --allow-remote-control ${HOME}/.claude/scripts/kitty-pane-title-overlay.py off --all : launch --type=background --allow-remote-control ${HOME}/.claude/scripts/kitty-pane-title-toggle.sh toggle
```
`--type=background` routes to `Boss.run_background_process` (`kitty/launch.py:788-792` → `boss.py:2913-2915`),
whose body is a plain `subprocess.Popen(cmd, env=env, cwd=cwd, ...)`. **A fresh process per press**; kitty
holds no handle on the script's bytes. Latency to pick up an edit = **the next keypress**.

Two consequences that are easy to miss:

- The bound path is `${HOME}/.claude/scripts/…`, i.e. the **symlink** — so (c) inherits (f). The kernel
  resolves the link at `execve`, so the repo file's *current* bytes run. Verified live: all five kitty
  scripts are symlinks into the checkout (RAN, `readlink`).
- 🚨 **⌘⇧B is itself a full manual config reload.** The script's last line is
  `kitty @ load-config --ignore-overrides "$CONF_ON|$CONF_OFF"` (`kitty-pane-title-toggle.sh:94`), and
  **both halves open with `include kitty.conf`** (`config/kitty-title-on.conf:52`,
  `config/kitty-title-off.conf:18`). So a chord press re-reads the whole main config.
  **This is the reliable manual lever when the watcher declines** — notably after a *deletion*, the one
  case §b proves the watcher will not act on.

Two follow-ons about the toggle halves themselves:

- `config/kitty-title-{on,off}.conf` are **NOT in the watcher's conf set** — `kitty.conf` does not include
  them (the include runs the other way). They hold fds (7/18, 19/25) only as *entries* of watched dirs, so
  an edit to them wakes the watcher and is correctly declined. **Editing a toggle half reaches the live
  kitty only on the next chord press**, never automatically. Conviction 90%.
- After a press, `opts.all_config_paths` becomes the ON/OFF file (`kitty/config.py:192`). A later SIGUSR1
  calls `load_config_file()` with no args, which reuses `old_opts.all_config_paths` (`boss.py:3201-3202`) —
  so an auto-reload **preserves the current toggle state** rather than reverting it. Conviction 85% (READ).

---

## (d) The long-lived python daemon — `scripts/kitty-pane-title-overlay.py daemon`

**RAN, live right now:**
```
79958  ppid 1  Wed 16 Sep 23:53:34 2026  etime 12:43
  .../Python /Users/chrisren/.claude/scripts/kitty-pane-title-overlay.py daemon --initial=off --all
```
Socket/lock present: `~/.claude/autonomy/kitty-title-overlay.{sock,lock}`, both `Sep 16 23:53`.

| Property | Value | Evidence |
|---|---|---|
| Spawned by | the **client half of the same script**, on a press, only when `_client()` cannot connect | `kitty-pane-title-overlay.py:1337-1340` |
| Spawn mode | `subprocess.Popen(..., start_new_session=True, close_fds=True)` → detached, **ppid 1** | `:128-137`; RAN `ppid=1` |
| Code freshness | **frozen at exec.** A `.py` edit has **zero** effect on pid 79958 | process semantics |
| Exit condition 1 | its kitty dies — `os.kill(kpid, 0)` fails | `:1229-1232` |
| Exit condition 2 | **`IDLE_EXIT = 6 * 3600`** (6 h) — *and only while the titles are OFF*: `if not st["on"] and time.time() - st["touched"] > IDLE_EXIT` | `:1155`, `:1234` |
| Exit condition 3 | a `quit` message on its socket → `break` | `:1266-1267` |
| Singleton guard | `flock(LOCK_EX\|LOCK_NB)`; a second daemon `return 0` — "another daemon owns this" | `:1131-1134` |

### 🚨 Can a client press force a respawn? **No — and that is why a kill was reached for.**

`main()` (`:1336-1343`) tries `_client(arg)` **first**. A live daemon answers `ok`, so `return 0` fires and
`_spawn_daemon` is **never reached**. Even if it were, the `flock` makes the new process exit immediately.
So while pid 79958 lives, every press is served by the **old code**, no matter how many times the file is
edited or how many times the chord is pressed. `IDLE_EXIT` cannot help either while `st["on"]` is true.

### 🚨 BUT a graceful lever already exists and does not need a kill

```
~/.claude/scripts/kitty-pane-title-overlay.py stop
```
`main()` `:1333-1335` → `_client("quit")` → the accept loop breaks (`:1266`), the `finally` wipes the
placements and **unlinks the socket** (`:1271-1278`). The next press then finds no socket, `_client`
returns False, and `_spawn_daemon` starts a **fresh process with the new code** (~400 ms, per the comment
at `:1156`). **The hand-kill tonight was not required** — `stop` is the sanctioned path, and unlike a kill
it also erases the on-screen placements first. Conviction 93% (READ of a clean, well-commented path; I did
not RUN it, because doing so would alter the operator's live overlay state).

**Restart of *kitty*: NO. Restart of the *daemon*: YES, for any code change.**

---

## (e) The kitty binary — the C-patch class

**CONFIRMED: a full kitty restart is REQUIRED. Conviction 99%.**

- RAN, `lsof -p 73832 | awk '$4=="txt"'`:
  `kitty 73832 ... txt REG ... 456864 ... /Applications/kitty.app/Contents/MacOS/kitty` — the stock
  0.48.2 app-bundle binary is **mapped into the running process**. Replacing the file on disk does not
  change the mapped image.
- There is **no re-exec path**: `grep -n "os.execv|execvp" kitty/boss.py kitty/main.py` returns only
  `subprocess.Popen` call sites (`main.py:399`, `boss.py:2916`) — neither replaces the kitty process.
- There is **no `restart` remote-control command**: `ls ~/k482/kitty/rc/` lists 41 commands
  (`load_config.py`, `set_font_size.py`, …) and nothing that restarts or reloads the binary.
- The reload path tops out at Python-level `apply_new_options`; the C layer only ever sets
  `ss->reload_config = true` (`child-monitor.c:1537`).
- The operator's kitty is **not** running a patched build: patched trees exist at `~/kitty-dev` and
  `/private/tmp/kitty-dev` (RAN `ls -d`), but pid 73832's `txt` is `/Applications/kitty.app`.

### 🚨 ADVERSARIAL FINDING — (e) is TWO classes, not one. `kitten` is a separate binary.

`ls -la /Applications/kitty.app/Contents/MacOS/` shows **two** executables:
`kitty` (456,864 B) and `kitten` (51,748,288 B — the Go binary).

| sub-class | Reaches a running kitty how | Restart required? |
|---|---|---|
| **e1 — `kitty`** (C/Python core: layout, drag, rendering, `boss.py`) | only by replacing the process | **YES, full kitty restart** |
| **e2 — `kitten`, invoked per call** (`kitty @ …` from the toggle script, any `launch` of a kitten) | fresh `execve` per invocation | **No** — next invocation |
| **e2b — `kitten`, long-lived children** (`__watch_conf__` pid 74784, `__atexit__` pid 74737, both started at `20:13:53` with kitty) | never re-spawned: `boss.py:1418` guards on `not hasattr(self, 'config_reload_watcher_process')` | **YES, full kitty restart** |

So patching `kitten` is *partially* live: a `kitty @` call picks it up immediately, while the config
watcher keeps running the old Go code until kitty itself restarts. Anything landed in
`tools/watch/` or `tools/config/` therefore does **not** take effect on pid 73832 at all.

**Cost of the (e1) restart, stated because it is the whole reason this class matters:** pid 73832 owns
11-13 live panes, several of them Claude Code sessions. A restart is not a reload; it is a session event.

---

## (f) `~/.claude/**` hooks and scripts — the per-file symlink layer

**RAN, sandbox with the identical topology** (`<scratchpad>/symtest`):

| step | action | result |
|---|---|---|
| 1 | invoke `live/tool.sh` (symlink → `repo/tool.sh`) | `V1` |
| 2 | **EDIT** `repo/tool.sh`, do **not** re-link, invoke `live/tool.sh` again | **`V2-EDITED`** — the edit rode the link |
| 3 | **ADD** `repo/added.sh`, invoke `live/added.sh` | **rc 127**, `no such file or directory` |

**So: a landed EDIT is live on the next invocation; a landed ADD is invisible until a link exists.**
The linker is `install.sh:198-217` (`link_file` → `ln -sf`), driven by
`install.sh:689-696`:
```bash
for script in "$REPO_DIR"/scripts/*.sh "$REPO_DIR"/scripts/*.py; do
  [[ -f "$script" ]] || continue
  if $IS_GLOBAL; then link_file "$script" "$CONFIG_DIR/scripts/$(basename "$script")"
  else                copy_file "$script" "$CONFIG_DIR/scripts/$(basename "$script")"; fi
done
```
Two gaps this glob has, both recorded in the file itself:
- **Top-level only** — `scripts/lib/`, `scripts/limit-recover/`, `scripts/backlog-consolidation/` each need
  their own explicit pass (`install.sh:733`, `:769`, `:792`). A new *subdirectory* would be silently undeployed.
- **`bin/` is globbed by NAME** (`bin/cc-* bin/desk-* bin/ms365-*`) — a tool named anything else gets no link.

### 🚨 The "edits ride the link" premise is only true once install.sh has actually linked the file — and
### this exact file is the recorded counterexample

`install.sh:682-688`, verbatim:

> MEASURED 2026-09-15. `scripts/kitty-pane-title-overlay.py` landed on trunk and never reached the live
> layer: **203 of 205 entries in `~/.claude/scripts/` are symlinks and this was one of two real files**, a
> one-off copy nothing updates. `deploy-live.sh` reported "at trunk tip — nothing above the live layer to
> deploy" while the deployed copy still read `TYPE_RATIO 0.845` against the checkout's `0.707`.

I re-checked the present state (RAN, `readlink`): **all five** kitty artifacts are symlinks today —
`kitty-pane-title-{overlay.py,toggle.sh}`, `kitty-drag-w4.sh`, `kitty-title-band-watcher.py`,
`kitty-drag-window.py`. The hazard is closed for these files, but the class is **not** structural: nothing
stops a real file reappearing, and when it does the symptom is silence, not an error. **Verify by
`readlink`, never by the converge counter** — that is the repo's own `🚀 LIVE_ADDS` rule in miniature.

---

## The one-line answer per class

| Class | To make new code run in kitty **73832** |
|---|---|
| a `kitty.conf` | **Nothing.** Write `config/kitty.conf` in the repo → live in ~0.15 s. Except `listen_on` / `macos_option_as_alt` / macOS menu-bar shortcuts → **restart**. |
| b drop-in | Write/empty `~/.config/kitty/drag-arm.d/*.conf` → live in ~0.15 s. **Never disarm by deleting** — press ⌘⇧B, or touch `kitty.conf`, to force it. |
| c toggle script | **Nothing.** Next keypress. |
| d overlay daemon | `…/kitty-pane-title-overlay.py stop`, then press the chord. **No kill, no kitty restart.** |
| e1 kitty binary | **Full kitty restart** — 11-13 live panes. No alternative exists. |
| e2 kitten binary | Next `kitty @` call — **but the config watcher keeps old code until kitty restarts.** |
| f `~/.claude` script | EDIT: next invocation, free. ADD: run `install.sh` (or `scripts/deploy-live.sh`, which runs it) first. |

## Conviction register

| Row | Conviction | Basis |
|---|---|---|
| a mechanism + latency | **97%** | RAN (arms 1/3, live `lsof`) + source at 4 sites |
| a restart-required list | **93%** | READ only — enumerated from `definition.py`; not exercised per option |
| a — `listen_on`/`macos_option_as_alt` are ours | **99%** | RAN `grep` on `config/kitty.conf:123,296` |
| b empty-fires / delete-does-not | **97%** | RAN arm 1 D+C with negative control G |
| b cold-directory hazard | **95%** | RAN arm 2; live state proven already-warm by `lsof` fd 4 |
| b repo `config/` is watched | **96%** | RAN arm 3 X + live `lsof` fd 10 |
| c fresh exec per press | **96%** | source `launch.py:788` → `boss.py:2914`; not timed live |
| c ⌘⇧B is a full reload | **92%** | READ: script line 94 + both halves `include kitty.conf` |
| d lifecycle + no forced respawn | **95%** | RAN process/socket state + source at 6 sites |
| d `stop` is the graceful lever | **93%** | READ only — deliberately not run against the live overlay |
| e1 restart required | **99%** | RAN `lsof txt` + absence of any re-exec/rc-restart path |
| e2 kitten split | **90%** | READ + RAN process list; not exercised by patching |
| f EDIT rides / ADD does not | **95%** | RAN symlink experiment + `install.sh` source + live `readlink` |
| "~3 s" is kitty apply-time | **60%** | signal measured at 0.15 s; kitty's side deliberately NOT measured |

## What I did NOT do

- Never signalled, keyed, dragged or `kitty @ action`-ed pid 73832. All signals went to my own trap
  processes; every sandbox process was self-bounded (`sleep N |` for the watcher, a bounded `for` for the
  trap), so nothing needed `kill`.
- Did not measure kitty's own reload-apply time — that requires watching the live kitty react. This is the
  one open number (the ~3 s residual).
- Did not exercise the restart-required option list per option; it is READ from `definition.py` prose.

---

## Adversarial pass — what it changed

I ran the self-check *after* drafting, and it moved two things.

### 1. My first enumeration of the restart-required set was made with a LINE-BASED grep, and `definition.py` WRAPS its prose

`allow_remote_control` appeared to carry "Changing this option by reloading the config is not supported"
under a targeted re-check, which would have made a **third** of our options restart-required. Re-run
properly — splitting the file into `opt(...)` blocks, whitespace-normalizing each block, then matching —
the answer is that my *targeted* re-check was the broken instrument: its 2,600-character window ran past
`allow_remote_control` (decl L2764) into `listen_on` (decl L2796) and picked up **`listen_on`'s** caveat.

**Corrected, block-bounded enumeration: 20 options carry a reload/restart caveat.** The §a table lists 19
of them; the only omission is **`linux_display_server`** (decl L3415) — Linux-only, inert here.

**`allow_remote_control` is ACQUITTED: its block carries no reload caveat.** This matters, because it is
what keeps `kitty @ load-config` — the manual lever in §c — available across a reload.

The near-miss is the lesson: a caveat sentence split across two source lines is invisible to `grep`, and a
per-option window that is not bounded by the *next* declaration attributes a neighbour's prose. Both
failures are silent and both point the same way — toward over-reporting restart-required options.
Conviction in the corrected list: **95%** (was 93%).

### 2. The `kitty @` lever in §c is confirmed ALIVE — and the socket namespace is polluted

RAN: `ls -la /tmp/kitty-73832` → `srwxr-xr-x ... Sep 16 20:13` — the remote-control socket exists, so
`allow_remote_control socket-only` + `listen_on unix:/tmp/kitty-{kitty_pid}` are working and ⌘⇧B's
`kitty @ load-config` can reach pid 73832. **The §c manual-reload lever is real, not theoretical.**

But `ls -la /tmp/kitty-*` shows the namespace holds **10 entries, only one of which is a socket**:
```
lrwxr-xr-x  /tmp/kitty-482  -> /Users/chrisren/k482        <-- symlink, not a socket
lrwxr-xr-x  /tmp/kitty-dev  -> /Users/chrisren/kdev        <-- symlink, not a socket
srwxr-xr-x  /tmp/kitty-73832                               <-- the only real socket
-rwxr-xr-x  /tmp/kitty-autoformat-disarm.sh, kitty-chord-redisarm.sh, kitty-disarm-handover.sh,
            kitty-drag-resume-nudge.sh, kitty-drag-w4-resume.md, kitty-live-before.txt, ...
```
`scripts/kitty-drag-w4.sh` keys its "never signal a live kitty" refusal on the `/tmp/kitty-*` **glob** —
deliberately, so it cannot go stale across a reboot the way a pid does. A glob-only consumer becomes *more*
conservative as the namespace fills, so no correct consumer is fooled. But this is the recorded hazard
("a namespace chosen as a safety predicate is one you must then stop writing into") now measured at
**9 non-socket squatters to 1 socket**. Out of scope for T5; flagged because it is one `ls` away and the
ratio is worse than the rule anticipated.

### 3. Axes I checked and found NOT to matter

- **Does the watcher survive a kitty crash?** Yes-and-exits-cleanly: kitty passes `stdin=subprocess.PIPE`
  (`boss.py:1422`) and the watcher's goroutine cancels its context on stdin EOF
  (`tools/watch/api.go:211-220`). No orphan watcher class exists. (READ, 90%.)
- **Is there a second reload trigger besides SIGUSR1?** `kitty @ load-config` (`kitty/rc/load_config.py`),
  and that is all — the rc command list has no other config-affecting entry.
- **Does a reload revert the ⌘⇧B toggle?** No — `load_config_file()` with no args reuses
  `old_opts.all_config_paths` (`boss.py:3201-3202`), which after a press is the ON/OFF half.
