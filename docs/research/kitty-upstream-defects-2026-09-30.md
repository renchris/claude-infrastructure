# Two upstream kitty defects: recorded, not patched into the daily terminal

Backlog rows 7e067b9377ff (fonts_data) and a205ef0a3659 (tick_lock). Ticket kitty.2 of the
2026-09-30 backlog master plan.

## Decision: record, do not patch the daily terminal now

Both defects are real and both are still in the newest release, v0.49.2 (checked 2026-09-30). Neither
has crashed this machine's kitty: the live kitty has run since the 2026-09-30 15:29 reboot, ran 13+
days before that (pid 73832, from 2026-09-16 20:13), and `~/Library/Logs/DiagnosticReports` holds 0
kitty reports today. The fleet calls `kitty @` on the live socket routinely, so "any remote-control
call can crash it" is a possible path, not an observed one. The fixes are small, so they ride the one
patched build staged for the title band (ticket kitty.3, row b015a245aa4f) rather than a separate
binary swap; the operator decides whether that build is adopted.

## The defects, with v0.49.1 receipts (v0.49.2 is identical at these sites)

**fonts_data.** `kitty/fonts.c` `restore_window_font_groups()` (:216-226) sets
`w->fonts_data = NULL` and only restores it if a font group with the saved id still exists.
`kitty/state.c` then dereferences it unguarded in `dpi_for_os_window` (:88),
`viewport_for_window` (:1190-1191) and `cell_size_for_window` (:1203-1204); the last two are exported
to Python, so a kitten, a watcher or a `kitty @` command reaches them. More unguarded reads sit at
:511, :761 and the tab-bar layout; the falsifier keys on the three named functions.

**tick_lock.** `glfw/cocoa_init.m` `_glfwPlatformPostEmptyEvent()` (:1071-1078) runs on the
child-monitor thread and does `} else if (tick_lock) { [tick_lock lock]; … }`, while
`_glfwPlatformRunMainLoop()` (:1088-1099) does `[tick_lock release]; tick_lock = NULL;` when the main
loop returns. The NULL check and the message send are not atomic with the release, so a post racing
shutdown can message a freed NSLock.

## The falsifier

`scripts/checks/kitty-upstream-defects.sh` reads a release's source (default: the latest GitHub
release) and tests each defect's structure, not line numbers. Exit 1 = still present (the row stays
open), 0 = fixed upstream (the row's premise is gone), 2 = could not tell (abstain). Pinned by
`tests/kitty-upstream-defects.bats`. The rows store:

```
bash ~/.claude/scripts/checks/kitty-upstream-defects.sh --defect fonts_data
bash ~/.claude/scripts/checks/kitty-upstream-defects.sh --defect tick_lock
```

Run on 2026-09-30 with no `--src`: both `state=present`, `verdict=PRESENT ref=v0.49.2`, exit 1.
The same run against v0.49.1 and against the local 0.48.2 tree also exits 1.

The old falsifiers were unsound in both directions: `CFBundleShortVersionString != 0.48.2` flips on
any upgrade, including to 0.49.x, which still carries both defects; `sed -n 1047p` on a frozen local
checkout can never flip.

## Drafted upstream issues (the operator files them, if they choose)

### Issue 1

**Title:** macOS: NULL dereference of os_window->fonts_data in viewport_for_window / cell_size_for_window after font groups are restored

**Body:**

`restore_window_font_groups()` in kitty/fonts.c sets `w->fonts_data = NULL` for every OS window and
only restores it when a font group with the saved `temp_font_group_id` is found. Several readers in
kitty/state.c dereference `os_window->fonts_data` with no NULL check, including two functions exported
to Python (`viewport_for_window`, `cell_size_for_window`) and `dpi_for_os_window`. If the lookup ever
misses, the next call from Python (a kitten, a watcher, a remote-control command) or a DPI query
dereferences NULL.

Seen by reading v0.49.2 source: fonts.c:216-226, state.c:88, :1190-1191, :1203-1204. There is no
reproduction yet. The guarded form costs one line per site, for example:

```c
WITH_OS_WINDOW(os_window_id)
if (!os_window->fonts_data) goto end;
cell_width = os_window->fonts_data->fcm.cell_width;
```

and in `dpi_for_os_window`, fall back to `global_state.default_dpi` when `fonts_data` is NULL.

### Issue 2

**Title:** macOS: _glfwPlatformPostEmptyEvent can message a released NSLock during main-loop shutdown

**Body:**

In glfw/cocoa_init.m, `_glfwPlatformPostEmptyEvent()` is called from the child-monitor thread and does:

```objc
} else if (tick_lock) {
    [tick_lock lock];
    request_tick_callback();
    [tick_lock unlock];
}
```

`_glfwPlatformRunMainLoop()` does `[tick_lock release]; tick_lock = NULL;` after `[NSApp run]`
returns. The NULL check and the `lock` message are not synchronised with the release, so a post that
passes the check just before shutdown can message a deallocated object. Seen by reading v0.49.2
source (:1071-1078 and :1093-1096). A minimal fix is to create the lock once and never release or
NULL it (it is a process-lifetime object), or to stop the monitor thread before releasing it.
