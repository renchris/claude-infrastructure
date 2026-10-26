# kitty PR #10742: the upstream fix for issue #10741

Posted 2026-10-25 as https://github.com/kovidgoyal/kitty/pull/10742. It is one commit, `b2087a7b4` on `renchris/kitty` branch `macos-pty-name-without-dev-walk`, based on upstream master `debcde56c`. It closes RCA.md rank 1, item 4: kitty's main thread froze at `spawn()` → `ttyname_r()` → `lstat()` on the wedged `ttys063`.

## The change

On macOS, `spawn()` in `kitty/child.c` now gets the pty name with `ptsname_r(master)` (one `TIOCPTYGNAME` ioctl and a `stat()` of that one path) instead of `ttyname_r(slave)`, which calls `devname_r()` and walks `/dev`. The change is behind `#ifdef __APPLE__`, adds 11 lines and one changelog bullet, and keeps Kovid's open-by-name plus `TIOCSCTTY` design. Other platforms keep `ttyname_r()`.

Why it was built this way:
- **Keep the reopen by name.** In July 2022 Kovid replaced it with an fd-only `TIOCSCTTY` (`72f3e8cd4`) and restored open plus ioctl the next day (`9535bc94f`). So this PR changes only where the name comes from.
- **macOS only.** On Linux, `ptsname_r()` can return the wrong path when there is more than one devpts instance, which glibc's `ttyname_r` identity check avoids. OpenBSD and DragonFly have no `ptsname_r`.
- **Nothing else on the main thread walks `/dev`.** Apple's `openpty()` calls `ptsname_r()` and then `open()` on that name, and xnu's devfs lookup by name loads only the matched node.

## What it does not fix

`/usr/bin/login` (it starts the default shell on macOS) calls `ttyname()` itself, so a new window's shell can still hang while a `/dev` entry is stuck. Only kitty's own main thread is fixed.

## Evidence

All of it was run on the exact posted commit. Copies are in `~/incident-2026-10-25/kitty-pr-10741-evidence/` (local, not in the repo).
- **Sandbox test.** `sandbox-exec` with `(deny file-read-data (literal "/dev"))` makes listing `/dev` fail, so it stands in for a stuck entry without touching a real node. On master, `spawn()` raises EPERM. With the PR, `spawn()` succeeds, and an `stty` round trip through `/dev/tty` proves the child's controlling terminal is the slave. Without the rule, both builds pass (`final-matrix.log`).
- **Real kitty.** A separate built kitty instance opened its first window and a tab through remote control. Both had their pty as controlling terminal, and job control and `logname` worked (`gui-smoke-b2087a7b4.log`). The running kitty and `/Applications` were not touched.
- **Test suite.** `./test.py` ran 1144 tests on both master and the PR, with the same single failure, `test_mime_cache`, which is environmental (`tests-*.log`).
- **Formatting.** CI's `clang-format` 23.1.3 `--dry-run --Werror` passed.
- **Review.** A four-lens final review (claim check against live master, maintainer taste, cold read, adversarial correctness) found no code defect. Its text fixes were applied before posting.

## Build notes for the next kitty PR on this machine

- `./dev.sh build` currently fails: `install_name_tool` cannot rewrite the bundled Python's rpaths ("larger updated load commands do not fit"). Use `python3.14 setup.py build --debug` with `~/slang/bin` on PATH, after copying `SymbolsNerdFontMono-Regular.ttf` into `fonts/`.
- Run `test.py` with `kitty/launcher` first on PATH. Otherwise `kitty_exe()` finds `/Applications/kitty.app`, and every Python test worker dies with `NameError: worker_main`, so 0 Python tests run and the Go tests still pass.
