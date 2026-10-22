# Shim design: stop `#!` execs from reaching the kernel (kalloc long-term, 2026-10-21/22)

Axis: shim. Read-only research. I changed no file outside this one, wrote no measurement files,
and ran no sudo or launchd commands. Labels used throughout: **MEASURED** means a command and its
output on this box, cited. **SOURCE** means code or a public report, cited. **INFERRED** means
reasoning from those, with the gap named.

## 0. Answer first

1. **Build one compiled C multi-call launcher, `cc-shim`.** A `#!` path exec becomes two Mach-O
   execs in the same pid: the shim, then the script's own interpreter with the script as an
   argument. It copies xnu's `#!` parsing exactly (§3), so argv, `$0`, env, pid, exit status,
   signals and the tty all match a kernel `#!` exec.
   The leak is per *`#!` image activation*. `/bin/bash leaf.sh` retains 0.007 ± 0.101 elements and
   `#!` leaf retains 1.098 ± 0.104 on 15.8.1 (panic doc lines 332-335). So a shim'd call retains
   about 0, whatever its lineage (§5).
2. **One rule finds the real script, in every directory:** invoked `D/N` → `dirname(D)/.<basename D>-real/N`.
   For `~/.claude/bin/cc-x` that is `~/.claude/.bin-real/cc-x`. The `-real` directory sits at the
   same depth as `D`, so `$(dirname "$0")/../scripts`, `../hooks/lib` and `${0##*/}` (the
   cc-qos-exec aliases) keep resolving. The same rule serves our tools, wrappers for programs we
   don't own (`shasum`), and test stubs.
3. **Deploy it in place only in the exec-only namespace** (`~/.claude/bin`, `~/bin`, `~/.reso/bin`).
   Do not deploy it in `~/.claude/scripts` or `~/.claude/hooks`. Those paths are also run through
   an explicit interpreter (`/bin/bash ~/.claude/hooks/x.sh` is how 80 settings hooks and 102
   code references call them, and 23 launchd jobs plus 40 session commands in 1.6 days run
   `bash ~/.claude/scripts/…`). Bash refuses a Mach-O file given to it as a script, so an in-place
   shim there breaks those callers. For `scripts/` and `hooks/`, the contract stays "run with
   the interpreter" and a land-gate lint enforces it (option d).
4. **The bin shim alone is not the main lever.** The 10-minute root census (§1) puts only about
   3-5% of the remaining leak through `~/.claude/bin`. The rest of that window: test-suite stubs
   and rehearsals about 70%, `/usr/bin/shasum` 13%, one repo call site (`cc-await-ping` →
   `cc-kqwait`) 4.7%. The shim is still the right *primitive*, because the same binary fixes
   the `shasum` share through a `~/.claude/bin/shasum` wrapper and the test share through a stub
   factory. But the rollout order should follow the census, not the directory tree (§7).
5. **Lineage effect: one test decides the strategy.** Every live Claude session descends from a
   `#!` exec of `~/.claude/bin/cc-close-attrib` (§5.3, MEASURED). If 15.8.1 behaves like Photon's
   26.5.x and willmcginnis's M1 26.6.2 (the first `#!` in a lineage is nearly free and each later
   one costs about 1), shimming the handful of *root* launchers would make most first-level `#!`
   execs in session trees cheap. That would cut far more than per-file conversion. Test T-0
   (§6) settles it without root and should run before any other rollout step.

## 1. What still triggers it: the census (MEASURED)

Source: `~/.cache/kalloc-exec-census/20261021T235112/exec.jsonl` (eslogger was still running when
I read it). I used the first 600.0 s, 2026-10-22 04:51:16-05:01:16 UTC. Pipeline: `jq -r` of
time, pid, ppid, `event.exec.script` (null or not), the target path, `is_platform_binary`, the
caller's image and args[1..2], fed to one `awk` pass.

| Quantity | Value |
|---|---|
| exec events | 373,392 |
| `#!` execs (`event.exec.script != null`) | **7,000 = 11.67/s** |
| non-platform Mach-O execs | 60,914 = 101.5/s (jq 24,886, git 17,616, Homebrew bash 3,960, claude.exe 3,370, …) |
| zone, raw `data.kalloc.1024` bytes, `~/.claude/logs/kalloc-zone-series.tsv` rows `1792644507 380556288` → `1792645729 397224960` (this window inside them) | 16,668,672 B / 1,222 s = **13.3 elements/s** (raw, no `cred` subtraction; the interval before read 7.9/s) |
| predicted from `#!` count × 1.098 | 12.8/s |

So **`#!` execs account for about the whole leak**. Non-platform, ad-hoc-signed Mach-O execs ran at
101.5/s in the same window. If each retained even 0.1 element, the zone would grow ≥ 10/s more
than observed. The bound is INFERRED and loose (one window, raw series, `cred` noise of thousands
of elements). It is the evidence that an ad-hoc compiled shim does not itself leak. `cc-kqwait`'s
cached binary is that same shape: `flags=0x20002(adhoc,linker-signed)` from `codesign -dv
~/.cache/cc-kqwait/cd59cf435412e852-arm64/cc-kqwait`, 35,120 bytes. It was exec'd 326 times in
the window.

### 1.1 Shares by class (7,000 `#!` execs)

| Class (script path) | n | share | notes |
|---|---|---|---|
| tmp: test fixtures, stubs, rehearsals (`/var/folders/…`, `/tmp/…`) | 4,907 | 70.1% | by cwd: `~/Development/agent-context-sync` 3,169, `/tmp/…` (agentsync rehearsals) 953, `~/.claude/autonomy/postland` (postland bats) 543, worktrees 196 |
| system | 909 | 13.0% | `/usr/bin/shasum` (`#!/usr/bin/perl`) 906 |
| claude-infrastructure main checkout | 704 | 10.1% | top: `bin/cc-kqwait` 326, `bin/cc-backlog` 87 (incl. worktrees), `bin/claude-accounts` 43, `bin/cc-in-kitty` 43, `bin/cc-decide` 42 |
| worktrees | 274 | 3.9% | `.tools/sandboxed` 70, `unattended-path-lint.sh` 53-56, worktree `cc-backlog` 42 |
| Homebrew | 146 | 2.1% | bats-core libexec 90, kitty cask wrapper `.homebrew-command-wrappers/kitty` 44, brew 8 |
| `~/.claude` real files, other, node | 60 | 0.9% | node_modules 11, `.git/hooks` 4 |

Overlapping tags: pytest temp dirs 2,659; bats run dirs and bats-core 807; uv/venv console-script
entry points (`…/uv/tools/agentsync/bin/agentsync`, `…/bin/python`) 818.

By interpreter: bash 4,324, perl 906, `/usr/bin/env` 704, sh 698, python3.x 368.

**`shasum`'s callers have our PATH.** 822 of the 906 `shasum` execs carried a `PATH=` starting with
`/Users/chrisren/.claude/bin` (from `event.exec.env`). 691 had cwd `agent-context-sync` and 711 were
`-a 256`. A `~/.claude/bin/shasum` shim link would reach at least 91% of them, and nothing we own
is named `shasum`, so there is no name collision.

**How repo scripts get exec'd.** I took the argv entry that names the script, i.e. the path as
passed to execve (xnu substitutes `ip_user_fname`, §3):

| Route | n |
|---|---|
| main-checkout physical path (`$ROOT/bin/x` after a readlink resolve) | 419 (326 of them `cc-kqwait`, from `bin/cc-await-ping:853` `KQ_BIN="$_ca_root/bin/cc-kqwait"`) |
| through a `~/.claude` live link | 288: `bin/` 152, `hooks/` 89 (mostly `~/.claude/hooks/../bin/…` and `hooks/../scripts/../bin/…`), `scripts/` 32, `shims/` 11, `autonomy/` 4 |
| worktree path | 242 |
| relative or bare | 52 |

An in-place `~/.claude/bin` shim reaches the 152 plus the `hooks/../bin` forms, about 190-240
execs, or **2.7-3.4% of all `#!` in this window**. A PATH-first overlay would reach only the
bare-name subset of those. Neither reaches the 419 physical-path calls, which need call-site
fixes, a single one of which is 4.7%.

**Caveat (load-bearing).** This is one 10-minute window, at 23:51-00:01 CDT, during an
agent-context-sync pytest and rehearsal campaign. The class shares will move with workload. Repeat
the census in at least three windows (a busy day, a night, a land wave) before fixing the rollout
order. An exec-only census also cannot attribute work through fork-only subshells: my
ancestor-attribution pass returned noise (`tr`, `grep`, `sed` as the "parents" of `shasum`).
Adding `fork` events to eslogger fixes that.

## 2. Options evaluated

| | (a) one Mach-O multi-call launcher | (b) per-file Mach-O wrappers from install.sh | (c) move real scripts out of PATH, leave wrappers | (d) land-gate lint |
|---|---|---|---|---|
| Correctness | Exact xnu `#!` emulation in one place; one test matrix covers every entry | Same logic compiled ~600 times; a codegen bug ships ~600 times | Same as (a) when the wrapper is (a); the hazard is *where* it is placed (row "breaks") | No runtime effect; stops regressions only |
| Breaks | Explicit-interpreter callers of a shimmed path (`bash <mach-o>` → "cannot execute binary file", 126) | Same | Same, plus every content reader of the moved path | Nothing |
| Maintenance | 1 C file (~250 lines), 1 build, rebuilt only when its hash changes | ~600 binaries × 35 KB ≈ 21 MB (estimated from the 35,120 B `cc-kqwait`), rebuild and re-sign on every script add, rename or delete; 600 cdhashes | Every auditor that mirrors the link model must learn the new shape | 1 lint + selftest + ratchet baseline |
| Scale (new tools) | Automatic: install links each new `#!` bin tool to the shim | Automatic but slow | Automatic | Needed for call forms the shim cannot see |
| Covers | Calls that go *through the shimmed path* | Same | Same | Call sites in tracked code; nothing typed by agents |
| Verdict | **Adopt**, in place in the exec-only dirs | Reject: the cost of (a) times N with no added correctness | Adopt **only** as (a)'s layout (`.bin-real/` beside `bin/`), and **only** for exec-only dirs | **Adopt**, ratcheted |

Why not a PATH-first overlay directory (an (a) variant)? It leaves every existing contract untouched,
which is attractive. But it needs a PATH change in `~/.zshrc:287` (an operator dotfile), in 39
plists and in every script that sets PATH. It reaches only bare-name calls, while most internal
calls are absolute ladder paths (`scripts/lib/cc-common.sh:35-44`, `resolve_bin`: beside-script →
`../bin` → `$CONFIG_DIR/bin` → PATH). And it would *miss* the session root launcher, which
`~/.zshrc:504` and `:508` run as the absolute path `"$HOME/.claude/bin/cc-close-attrib"`. In-place
reaches all of those. Keep the overlay as the fallback if in-place proves too disruptive in phase 2.

Why in-place is safe for `bin/` but not for `scripts/` and `hooks/` (MEASURED):
- Explicit-interpreter references to live paths in tracked code (`git grep` over bin, scripts,
  hooks; docs excluded): `/bin/bash ~/.claude/hooks/` 102, `/usr/bin/env … hooks/` 18,
  `bash ~/.claude/scripts/` 44, `/bin/bash ~/.claude/scripts/` 10, `python3 ~/.claude/scripts/` 8,
  `bash ~/.claude/bin/` 5 and `/bin/bash ~/.claude/bin/` 7. That is 84 files.
- Live settings: every hook command now starts `/bin/bash` or `/usr/bin/env` (`jq` over
  `~/.claude/settings.json`; the only others are `date` ×2 and `true`).
- Sessions, last 200,000 lines of `~/.claude/logs/bash-commands.log` (2026-10-20T08:58Z onward):
  23 commands run `bash|sh ~/.claude/bin/…`, 40 run `bash|sh|python3 ~/.claude/scripts/…`, and
  575 name `~/.claude/scripts/*.sh|py` by path.
- launchd: all 39 `com.claude.*` plists start `/bin/bash` (35) or `/bin/zsh` (4). Inside `-c`,
  23 then exec their main script **by path**, e.g. `exec "$HOME/.claude/scripts/team-orphan-reaper.sh"`.
  The research-kit jobs run `/bin/bash /Users/chrisren/.claude/scripts/research-kit/jobs/…`, which
  is explicit.

So `bin/` is the one namespace whose contract is already "exec it". Its 12 explicit-interpreter
code references and about 14 agent-typed calls a day are the whole break surface: convert the 12,
and let the lint and the PreToolUse hook catch the agent-typed ones (§4.4).

## 3. The launcher: `cc-shim` behaviour spec

SOURCE for the kernel behaviour being copied: xnu `bsd/kern/kern_exec.c` (apple-oss-distributions
main), `exec_shell_imgact` and `exec_extract_strings`, plus `bsd/sys/imgact.h:69` `IMG_SHSIZE 512`.
`IS_WHITESPACE` is space or tab (line 344). `IS_EOL` is `#` or `\n` (line 345).
- The line must start `#!`. Leading space and tab are skipped. EOL before any interpreter → ENOEXEC.
  No EOL within 512 bytes → ENOEXEC. Trailing whitespace is trimmed. **CR is not whitespace** (it
  stays part of the last token), and `#` ends the line.
- The line is split on space and tab into *several* argv entries (the comment reads "break out
  the arguments, if any, which are separated by white space"). macOS does not pass one combined
  argument the way Linux does.
- The script argument is `ip_user_fname`, the path string handed to execve, unresolved. The
  caller's argv[0] is consumed and dropped.
- An interpreter that is itself a script is refused (`IMGPF_INTERPRET`). Set-id bits on scripts are
  cleared (`sugid_scripts == 0`).

`cc-shim` algorithm (C, libSystem only, static buffers, no malloc on the fast path):

```
main(argc, argv, envp, apple):
  P = value of "executable_path=" in apple[]          # the path passed to execve, unresolved
      (fallback _NSGetExecutablePath)
  N = basename(P)
  if N == "cc-exec":                                   # explicit mode: cc-exec <script> [args]
      T = argv[1]; args = argv[2..]
  else:
      D = dirname(P); if D is relative or holds "/./" or "/../": D = realpath(D)
      T = dirname(D) + "/." + basename(D) + "-real/" + N   # ~/.claude/bin/x -> ~/.claude/.bin-real/x
      args = argv[1..]
  hops = CC_SHIM_HOPS ("<pid>:<n>"): n+1 if pid == getpid() else 1
  if hops > 16: die 126 "cc-shim: exec loop through N (16 same-pid hops)"
  fd = open(T, O_RDONLY|O_CLOEXEC)  -> ENOENT: die 127 "cc-shim: N: no target T"
  access(T, X_OK) fails             -> die 126 (the kernel needs +x on the script; keep that)
  buf = read(fd, 512); close(fd)
  if buf starts with Mach-O or fat magic: execve(T, [argv0, args…], env')   # wraps a binary
  if buf lacks "#!": execve("/bin/sh", ["sh", T, args…], env')              # execvp's ENOEXEC rule
  parse buf exactly as exec_shell_imgact (above)    -> tokens[0..k]; on ENOEXEC die 126
  execve(tokens[0], [tokens…, T, args…], env')     # T = the -real path string, unresolved
  on failure: die 127 (ENOENT) / 126 (other) with "cc-shim: <interp>: <strerror>"
env' = envp with CC_SHIM_HOPS replaced; nothing else is added or removed.
```

What it preserves:
- **pid.** It execs and never forks, so `$$`, pidfiles, `kill <pid>`, `wait`, process group,
  session and controlling tty all stay the same.
- **Signals.** Mask and ignored dispositions survive execve the same way they do for a direct
  exec. The shim installs no handler.
- **stdin, stdout, stderr and the tty.** It opens one file with `O_CLOEXEC` and closes it before
  exec, so the descriptor table is unchanged.
- **Exit status.** It is the interpreter's own, because there is no parent shim process.
- **ps and pgrep.** MEASURED: a kernel `#!` run and an explicit-interpreter run already look the
  same. `ps -axo pid=,comm=,args=` shows `4565 /bin/bash /bin/bash …/rotate-autonomy-logs.sh`
  (launchd runs that one by path) and `2936 /bin/bash /bin/bash …/compressor-sentinel.sh`;
  `ps -co comm` reads `bash` for both. The shim produces that same argv.
- **Interpreter choice.** `#!/usr/bin/env bash` still execs `/usr/bin/env`, a platform Mach-O,
  which resolves `bash` on the caller's PATH. The launchd /bin/bash 3.2 rule in
  `agent-operating-lessons.md:47` therefore keeps holding.

What changes:
- **`$0` and `BASH_SOURCE[0]`** become `…/.bin-real/N` instead of `…/bin/N`. The depth is the
  same, so every `..`-relative path and every basename keeps working. 23 bin files use an
  unresolved own-directory (`dirname "$0"` or `__file__` with no readlink or realpath; list in
  §6 T-3). They resolve against `.bin-real`, whose `..` is still `~/.claude`. The lesson "symlinked
  `$0` splits siblings" does not get worse, because the `-real` entries are the same per-file
  links that exist today. No bin file compares `$0` to a `~/.claude` path string or re-execs
  `"$0" "$@"` (`git grep` returned 0 for both).
- **Beside-script ladder calls** (`"$(dirname "$0")/cc-sessions"`, e.g. `bin/cc-backlog:6344`)
  now land on `.bin-real/cc-sessions`. That is still a `#!` exec: it works but leaks. The fix is
  in `resolve_bin` (one place, 37 calls in 13 files) and the lint ratchet for the inline ladders.

The trap that must be closed before rollout: **PATH-walkers loop.** `bin/cc-qos-exec:59-66` walks
PATH for the next `shellcheck` or `ffmpeg` that does not `-ef` its own file and is not a link
named `cc-qos-exec`. With `~/.claude/bin/shellcheck` → `cc-shim` → `.bin-real/shellcheck` →
`cc-qos-exec`, its walk would pick `~/.claude/bin/shellcheck` again, an endless same-pid exec
chain. The hop guard turns that into a loud 126, but shellcheck, pytest and ffmpeg would still
break. cc-qos-exec and cc-bats must therefore skip any candidate that `-ef`
`$CONFIG_DIR/libexec/cc-shim`, or their names stay in the exclusion list until they do.

## 4. Concrete design: files

| File | Change |
|---|---|
| `tools/cc-shim/cc-shim.c` (new) | §3. Has `--selftest`: parses a built-in table of shebang lines and checks the tokens. |
| `tools/cc-shim/build.sh` (new) | `clang -Os -Wall -Werror -o "$CONFIG_DIR/libexec/cc-shim-<sha16(src)>-$(uname -m).$$"`, selftest, smoke-exec of a temp `#!` probe, `mv -f`, then `ln -sfn` to `$CONFIG_DIR/libexec/cc-shim`. A no-op when the hash already exists. Same cache shape as `bin/cc-kqwait:286-288`. clang output is linker-signed ad hoc (MEASURED on cc-kqwait). |
| `install.sh` | New `link_exec <src> <dest>` beside `link_file` (`install.sh:198`). If the shim built and passed its selftest, `src` starts with `#!`, and its name is not in the exclusion list: `ln -sf src "$(dirname dest)/../.$(basename dir)-real/<name>"`, then `ln -sf "$CONFIG_DIR/libexec/cc-shim" dest`. Otherwise it falls through to `link_file`, which is today's behaviour. Used by the bin loops at `install.sh:1201` (cc-*, desk-*, ms365-*, dl, dl-sync) and `:1212` (qos names, once cc-qos-exec is patched), and for `~/bin` (`:536`, `:560`) and `~/.reso/bin` (`:589`). **Not** used by the hooks loop (`:324`, `:332`) or the scripts loop (`:691`). Also links `~/.claude/bin/cc-exec` → cc-shim, and the wrapper rows below. A `CC_SHIM_INSTALL=0` switch relinks everything directly, which is the rollback. |
| `config/shim-wrap.tsv` (new) | Wrappers for programs we don't own, `name<TAB>target`: `shasum	/usr/bin/shasum` first (13% of the window). Then `kitty	/opt/homebrew/Caskroom/kitty/0.48.2/.homebrew-command-wrappers/kitty`, or better, point PATH callers at `/Applications/kitty.app/Contents/MacOS/kitty` directly. |
| `config/shim-exclude.names` (new) | Bin names never shimmed. Seed: the PATH-walkers until patched (`cc-qos-exec` and its alias names from `config/qos-shim.names`, `bats` → `cc-bats`), and any tool documented as "run with bash". |
| `bin/cc-qos-exec`, `bin/cc-bats` | Skip PATH candidates that `-ef` the shim (2 lines each). |
| `scripts/lib/cc-common.sh` `resolve_bin` | When the beside-script candidate's directory is `*/.bin-real`, return `$CONFIG_DIR/bin/<name>` (the shim) instead. |
| `bin/cc-await-ping:853` | `KQ_BIN` prefers `$HOME/.claude/bin/cc-kqwait` (shimmed), or prefixes `/usr/bin/env bash`. One line, 4.7% of the window. |
| `tests/lib/cc-stub.bash` (new), plus a pytest fixture in agent-context-sync (its repo) | `cc_stub DIR NAME BODY` writes `DIR/../.<D>-real/NAME` (`#!` body, +x) and links `DIR/NAME` → cc-shim. With no shim (Linux CI, or a hermetic HOME without `$CC_SHIM`) it writes the plain `#!` file as now. |
| `scripts/exec-form-lint.sh` (new) + `scripts/hook-interp.py` (new `lint-callsites` mode, same predicate) | Option (d), §4.4. |
| `scripts/ship-land.sh` `run_gate` | New arm beside the HOOK SHEBANG arm (`:3865-3894`), same shape: diff-scoped (bin/, scripts/, hooks/, launchd/, tests/, settings-templates/, tools/cc-shim/), `selftest_ok`, `gate_bounded` escape `SHIP_LAND_EXEC_FORM_LINT=/nonexistent`, `arm_nonverdict` on exit 2. |
| `launchd/*.plist` + a migration | 23 jobs: `exec "$HOME/.claude/scripts/x.sh"` → `exec /bin/bash "$HOME/.claude/scripts/x.sh"`, prefix taken from the script's own shebang, verbatim (the 0070 rule, `hook-interp.py`). |
| `scripts/deploy-link-parity.sh`, `scripts/deploy-parity-assert.sh` | Teach both the link_exec shape. A bin entry is correct when it → cc-shim **and** `.bin-real/<name>` → the checkout file. Otherwise they report a correct deploy as drift. |
| `tests/cc-shim.bats`, `tests/exec-form-lint.bats` (new) | §6. |

### 4.4 The lint (option d), ratcheted

Rules, judged on the land's diff and against a committed baseline count per rule. New instances
fail and existing ones are grandfathered, the same ratchet model the gate already runs:
- **R1. bin/ is exec-only.** No `(bash|sh|zsh|python3|/usr/bin/env X) <path>/bin/<tool>` for a
  tracked bin tool, in code or plists. Fix-it: drop the interpreter.
- **R2. scripts/ and hooks/ are interpreter-run.** No exec by path of a tracked `#!` file under
  `scripts/` or `hooks/` in command position (start of a simple command or after `exec`,
  `then`, `do`, `timeout N`, `gtimeout N`, `nohup`, `taskpolicy -c X`, `xargs`, `find -exec`),
  nor as `subprocess.*([<path>, …])` heads. Fix-it: the target's own shebang verbatim (0070's
  rule), or `cc-exec <path>` when the path is a variable of unknown type. Size today (ESTIMATED,
  regex at command position over tracked names): **367 lines in 262 files** under bin, scripts
  and hooks, plus 79 in tests.
- **R3.** launchd `ProgramArguments` may not exec a `#!` script by path.
- **R4.** In tests, no new inline `#!` stub writes. Use `cc_stub`. Size today: 505 of 1,587
  tracked test files contain `printf|echo '#!…'` (MEASURED, `git grep -lE "(printf|echo) ['\"]#!" -- tests`).
- **Selftest.** A fixture with one violation per rule must go red, and its fix-it must go green
  (mirrors `hook-shebang-lint.sh --selftest`).
- Agent-typed `bash ~/.claude/bin/x` cannot be linted. `hooks/validate-bash.sh` (PreToolUse) can
  print a one-line hint ("bin tools are exec-only; drop `bash`") on that exact form. The failure
  itself is loud (126, "cannot execute binary file"), never silent.

## 5. The lineage effect

### 5.1 What is measured

- **Photon, 26.5.x (SOURCE, via willmcginnis's summary in
  [#66020 comment 5839216939](https://github.com/anthropics/claude-code/issues/66020#issuecomment-5839216939)).**
  Retention by depth of scripts launching scripts was 0.016, 0.99, 2.00 and 3.01 KiB at depths
  1-4. "Compiled binaries stayed flat."
- **willmcginnis.**
  - M4 26.4.1: every `#!` child cost 0.98-1.12, whether its parent was a `#!` script or Mach-O.
  - M1 26.6.2: about 1.03 with a `#!` parent, but 0.01-0.37 "as the first `#!` exec in a lineage".
    The cost came from "repeated `#!` execs within one process lineage, even with a Mach-O relay
    such as `env` or `sh -c` in between".
  - Mach-O child, any configuration: −0.03 to 0.04.
  - Failed execs (interpreter missing, not executable, a directory, or itself a script): 0.0003.
  - Interpreter `/usr/bin/true` vs `/bin/bash`: the same cost.
  - "We have not separated the OS build from the chip."
- **This box.**
  - 15.7.9, panic doc lines 76-84: one `#!` 0.94 ± 0.06; `#!` that runs a compiled binary
    0.89 ± 0.09; 2 nested 1.98 ± 0.13; 3 nested 2.86 ± 0.20; `sh top.sh` running one `#!` inside
    0.91 ± 0.17; `bash leaf.sh` ≈ 0.
  - 15.8.1, lines 332-335: `#!` leaf 1.098 ± 0.104; `/bin/bash leaf.sh` 0.007 ± 0.101.
  - Both harnesses ran from Claude sessions. How the 15.8.1 driver was started (`bash run2.sh` or
    `./run2.sh`) is not recorded in `~/.cache/kalloc-158-ab/` or the transcripts I could grep.

### 5.2 Does a Mach-O relay fully avoid it?

- **A relay placed *between* two `#!` execs: no.** That is willmcginnis's M1 finding. The second
  `#!` still costs about 1.
- **The shim is not that kind of relay. It removes the `#!` exec.** The kernel never runs
  `exec_shell_imgact` (`IMGPF_INTERPRET` is never set), so no shell-script pathname is ever
  handed to the exec hooks. Photon's LLDB dump found "a shell-script pathname in every one" of
  600 retained buffers.
- **A shim'd exec inside an already-tainted lineage costs about 0.** All three data sets
  measure a Mach-O exec, including the interpreter exec itself (`bash leaf.sh`), at 0 to 0.04
  whatever the parent: 15.7.9 shows "`#!` that runs a compiled binary" −0.05 ± 0.11 against one
  `#!`, and willmcginnis's Mach-O child column reads −0.03 to 0.04. The shim's own non-platform
  exec is bounded by the census (§1).
- **Answer.** The shim fully avoids the cost of every exec it handles, in any lineage (INFERRED
  from MEASURED components). Test T-1 measures the composite directly.

### 5.3 Why the lineage question still matters: it decides the strategy

All live sessions descend from `#!` launchers. MEASURED with `ps` ancestry chains of every live
`claude`/node process, grouped:

> `claude <- bash ~/.claude/bin/cc-close-attrib <- expect -c <- bash ~/.reso/bin/reso-resume-one <- -zsh -ic <- login -f <- kitty`

Every chain shows `bash ~/.claude/bin/cc-close-attrib`. ps cannot tell a kernel `#!` from an
explicit interpreter (§3), but `~/.zshrc:504` and `:508` call `"$HOME/.claude/bin/cc-close-attrib"`
by path, and it is `#!/usr/bin/env bash`. Likewise `reso-resume-one` (`#!/usr/bin/env bash`,
`scripts/boot-resume-launch.sh:123`). The 23 by-path launchd jobs root their own trees the same way.

One model fits Photon (cost = depth − 1), willmcginnis's M1 (first in a lineage is cheap, relays
don't reset it) and this box (cost ≈ depth, measured *from* tainted session trees): **a `#!` exec
leaks only when an ancestor, or an earlier image of the same pid, was itself a `#!` exec.** This is
INFERRED and unproven on 15.8.1. Under it the whole fleet pays about 1 per `#!` today because
every root is tainted, and shimming roughly 30 root launchers (cc-close-attrib, reso-resume-one,
the 23 by-path launchd mains, kitty's wrapper, pytest/bats entry points via `python -m` or the
shim) would make every *first-level* `#!` below them about free. Under the other model (M4 26.4.1:
every `#!` costs 1), only removing each `#!` exec helps. In both cases the in-place bin shim cleans
`cc-close-attrib` at no extra cost, because zshrc calls it through `~/.claude/bin`.

## 6. Test plan

The leak arms reuse `~/.cache/kalloc-158-ab/` (residual = `data.kalloc.1024` − `cred` from
`zprint`, interleaved arms, 3,000 execs per arm, 6 pairs, a least-squares drift term as in
`fit.py`), with output under `~/.cache/kalloc-longterm-ab/`. A 3,000-exec arm separates 0 from 1
per exec at about 7σ per pair (ESTIMATED from the ~390-element arm spread at this load, panic doc
line 337).

| ID | What | Pass |
|---|---|---|
| **T-0 lineage (run first; decides §5.3)** | From a **clean root**: a process whose ancestors are all Mach-O and none was exec'd via `#!`. Launch it with `launchctl submit` (measurement axis, removed afterwards) or a new kitty window via `kitty @ launch` (operator). Arms: C0 bash loop → `#!` leaf; C1 `/bin/bash taint.sh` → loop leaf; C2 `./taint.sh` (`#!`) → loop leaf; C3 `./taint.sh` → `env bash -c` loop leaf (relay); C4 cc-shim → `taint.sh` → loop leaf; B `/bin/bash leaf` control | Lineage model holds if C0 ≈ C1 ≈ C4 ≈ 0 and C2 ≈ C3 ≈ 1. If every arm ≈ 1 except B, every `#!` costs 1 on 15.8.1 |
| T-1 shim cost | Inside a session (tainted) and from the clean root: `/bin/bash leaf.sh` vs `.bin/leaf` → cc-shim vs `#!` leaf by path | shim − bash within ±0.1/exec; `#!` ≈ 1.1 |
| T-2 kernel differential (bats, no root) | For each shebang form, run the same probe once by kernel `#!` and once via cc-shim, and diff: argv as a probe interpreter prints it, `$0`, `BASH_SOURCE`, exit code, stdout/stderr bytes, `$$` equal to the spawned pid, `ps -o comm=,args=`, `pgrep -f`, env (except `CC_SHIM_HOPS`), `stty` under `script -q /dev/null`, a pipe on stdin, a `trap '' INT` set before exec still in force, `kill -TERM <pid>` reaching the script. Forms: `#!/bin/bash`, `#!/bin/bash -e`, `#!/usr/bin/env bash`, `#!/usr/bin/env python3 -u`, `#!  /bin/sh  `, `#!/bin/sh # c`, CRLF, a line of 511, 512 and 513 bytes, `#!` alone, no shebang, a Mach-O target, interpreter missing, interpreter that is a script, target without +x, target missing, dangling `-real` link | Identical on every observable. The documented exceptions are `$0` (`-real` dir) and the interpreter-is-a-script case |
| T-3 `$0` audit | Run each of the 23 unresolved-dir bin files (`cc-announce cc-bind cc-classify cc-config-slot cc-context cc-crash-report cc-digest cc-discover cc-escalations cc-halt cc-recover-safeguard cc-respawn cc-roles cc-run cc-sessions cc-spawn-verify cc-teardown-safety-gate.sh cc-value cc-wait cc-wake cc-wave-plan claude-kimi desk-register`) with `--help`, `--selftest` or a dry-run, both ways, in a temp `CONFIG_DIR` shaped like the live layer (copy `-Rp`, per the "subject reads its own path" lesson) | Same output and exit code |
| T-4 call-form matrix | bash, zsh, `/bin/sh -c`, python `subprocess` (list and shell), node `child_process.spawn`, `posix_spawnp`, `xargs`, `find -exec`, `gtimeout`, `taskpolicy`, `nohup`, launchd-style `/bin/bash -c 'exec …'`; bare name, absolute, relative, `~/.claude/hooks/../bin/x` | All reach the script. `bash ~/.claude/bin/x` fails loudly (126), which documents the R1 contract |
| T-5 loops | Unpatched cc-qos-exec behind a shimmed alias | Stops at 16 hops with 126 and a message, not a hang; patched cc-qos-exec runs the real tool |
| T-6 deploy | `install.sh` run twice changes nothing the second time; the shim build is atomic under a 10,000-exec loop running while it rebuilds; a failed build or selftest falls back to `link_file`; `CC_SHIM_INSTALL=0` restores direct links; deploy-link-parity and deploy-parity-assert both read green on the new shape, and red on a broken `-real` link | 0 failed execs; auditors discriminate |
| T-7 latency | 2,000 execs each: kernel `#!` vs cc-shim, idle and at fleet load | p50 added ≤ 1 ms |
| T-8 fleet | Re-run the eslogger census (3 windows) and `scripts/kalloc-leak-rate.sh` per Bash call against 52.1 elements/call and the post-0070 ~11/s | `#!` count drops by the class share each phase targeted; the zone slope follows |

## 7. Rollout, ordered by census share (change once T-0 is in)

1. **T-0 and T-1.** No repo change. They decide between the root-cleaning and exec-removal routes.
2. **cc-shim, build, install `link_exec`** for `~/.claude/bin`, `~/bin`, `~/.reso/bin`, plus
   `cc-exec` and the `shasum` wrapper. Effect in the window: `shasum` about 12% (822 / 7,000) and
   bin about 3%. It also cleans the session root `cc-close-attrib` and `reso-resume-one` for free.
3. **Point fixes from the census.** `cc-await-ping:853` → `cc-kqwait` (4.7%), then the launchd
   plist migration (23 roots).
4. **Stub factory and R4.** In claude-infrastructure, and an agent-context-sync PR: its pytest
   stubs, `launchctl-stub`, uv entry points via `python -m`, and `shasum -a 256` → `hashlib`. In
   this window that is about 60-70%, though the size depends on workload.
5. **R1-R3 lint ratchet and the `resolve_bin` change.** Burn down the 367 estimated call sites
   over time, hottest first, ranked by the census.

## 8. Risks and open items

- **Build-chain dependency.** If clang or the Xcode CLT disappears, `link_exec` falls back to
  `link_file`, and the leak returns silently. install should print `cc-shim: unavailable
  (<reason>)` loudly and the capacity alarm should carry it.
- **macOS 27, if ever adopted.** The shim stays harmless there: two Mach-O execs, about 1 ms. It
  can stay or be removed with `CC_SHIM_INSTALL=0`.
- **Not reachable by any shim.** Absolute-path execs of the checkout or worktrees (the 419 + 242
  in §1) and bats-core's own internal libexec chain (90 in the window). Only R2 call-site fixes
  or upstream changes reach them.
- **Unverified here.**
  - The `executable_path=` apple string holds the unresolved symlink path (T-2 covers it).
  - The `com.apple.provenance` xattr on locally built binaries does not slow exec under load.
    MEASURED present on `cc-kqwait`, which execs fine 326 times in 10 minutes.
  - The census shares outside one window.

## Critique

Adversarial review of this axis, 2026-10-22 00:30-00:55 CDT. Method: I re-ran the census pipeline,
re-read the cited xnu source, files, settings and plists, traced live process ancestry, and read the
measurement axis's shim-premise A/B, which finished at 00:40 (`~/.cache/kalloc-longterm-ab/`). I
wrote nothing except this section. No sudo, no repo, launchd or session change. Side effects: one
`shasum` exec (a `#!`, about 1 KiB retained) and several read-only jq/awk passes over `exec.jsonl`.
Labels are as in this doc. "My SE" means a standard error I estimated from the per-arm spread.

### Verdicts on the main claims

1. **Census numbers (§1): CONFIRMED exactly.** I re-ran the first 600 s (`head -n 400000 exec.jsonl | jq | awk`).
   It gives 373,392 events, 7,000 `#!` (11.67/s), 60,914 non-platform Mach-O, `shasum` 906 and
   `cc-kqwait` 326. The class shares are 70.1 / 13.0 / 10.1 / 3.9 / 2.1 / 0.9 %, and the routes are
   phys 419 and worktree 242. I count 263 live-link routes against the doc's 288 because my argv
   match differs; that does not change any conclusion.
2. **"`#!` execs explain about the whole leak": SUPPORTED, but the error band is wider than §1 shows.**
   - Second interval, zone rows `1792645729 → 1792646678` (949 s), MEASURED with an awk pass over
     `exec.jsonl`: 19,509 `#!` execs, 9,027 of them from the A/B harness.
   - At 1.098 per exec that predicts 22.6 elements/s. The raw zone grew 18.8/s, a ratio of 0.83
     (interval 1 was 1.04).
   - This boot's hourly zone rate ranges from 8.0 to 15.7 elements/s (`kalloc-zone-series.tsv`,
     awk by hour). So the 4% match in one window was partly luck. About ±20% is the honest band,
     and leak sources other than `#!` cannot be ruled out below about 15% of the total.
3. **Shim cost ≈ 0 inside a tainted lineage (§0.1, §5.2, labelled INFERRED): now MEASURED, with a margin.**
   - Source: `~/.cache/kalloc-longterm-ab/rows-n3000.tsv`, 4 interleaved cycles × 3,000 execs.
     These are my raw residual/exec means, without the drift fit.
   - Results per exec: `#!` leaf 1.044; `/bin/bash leaf` −0.013; **Mach-O launcher → `/bin/bash leaf` 0.073**;
     `/bin/bash` parent → launcher → leaf 0.108; `#!` → `#!` 2.359 (1.18 per `#!`).
   - The launcher (`launch.c`, ad hoc linker-signed, provenance xattr) has cc-shim's shape. Its run
     is tainted: `run.sh` (pid 81760) descends from `bash ~/.claude/bin/cc-close-attrib` (ps chain).
   - L − B = 0.09 ± 0.07 (my SE), so a cost of up to about 0.2 per exec is not yet excluded.
   - The per-arm SD here is 0.087-0.108 per exec. At that spread, T-1's "within ±0.1" pass needs
     **≥ 8 pairs**, not 6 (ESTIMATED).
4. **Latency (§8 "about 1 ms", T-7 "≤ 1 ms"): LIKELY REFUTED.** In the same rows, arm_secs/3000
   gives `#!` 5.96 ms, `/bin/bash` 6.01 ms and launcher 9.54 ms per exec, at load1 143-159. So one
   extra non-platform Mach-O exec costs about **+3.5 ms** under fleet load (MEASURED, 4 arms each).
   Re-base T-7 on this figure, or find the cause first. The ASP/syspolicyd checks per exec in kernel.md §6 are the
   likely suspect (INFERRED).
5. **xnu parsing spec (§3): CONFIRMED** against `xnu-11417.140.69`
   (`~/.cache/kalloc-longterm-ab/kernel/xnu-src/xnu-11417.140.69/bsd_kern_kern_exec.c`):
   - `IS_WHITESPACE`/`IS_EOL` are at :343-344 in the 15.x tag (the doc's 344/345 is a different tag).
   - `exec_shell_imgact` is at :601-735. The argument split and the argv[0] → `ip_user_fname`
     swap are at :5958-6022. `IMG_SHSIZE` 512 is at `imgact.h:69`. `executable_path=` holds the
     user path as copied in (:474-545).
   - **Missing from T-2:** the header buffer is zero-filled past EOF (:2375-2376). A short file whose
     `#!` line has no newline never reaches an EOL, so the kernel returns ENOEXEC. The *caller*
     then falls back: bash runs it itself, execvp uses `/bin/sh`, and Python raises. The shim's
     "die 126" changes that behaviour. `link_exec` should refuse to shim a file with no newline in
     its first 512 bytes.
6. **"A `~/.claude/bin/shasum` link reaches ≥ 91% of `shasum` execs" (§1.1; rollout step 2 "about 12%"): REFUTED.**
   - A `PATH=` entry in the env proves `~/.claude/bin` was on PATH, not that the call used the bare name.
   - agent-context-sync calls shasum **only by absolute path**: `scripts/install.sh:1051`
     (`… | /usr/bin/shasum -a 256`), `:4401` and `launcher/build.sh:57`. A test pins the string
     (`tests/test_deploy_pack.py:6524`), and git grep finds no bare call in its code.
   - The census agrees: 691 of 906 `shasum` execs ran with cwd agent-context-sync, a `/bin/bash`
     parent image and stdin input (jq over the first 600 s).
   - So a PATH link reaches at most about 215 execs: about 24% of `shasum`, about 3% of all `#!`.
   - Cheaper and complete fix: in agent-context-sync, use `hashlib`, or `/sbin/sha256sum`. That is a
     platform Mach-O whose stdin output is byte-identical to `shasum -a 256` (MEASURED,
     `printf abc | …`). No shim is needed.
   - `shasum`'s share also moves between windows: 12.9% / 1.6% / 5.4% (item 13).
7. **Lineage (§0.5, §5.3): half confirmed, half not supported.**
   - **a. "Sessions descend from a `#!` exec of cc-close-attrib": the mechanism is CONFIRMED, the scope is OVERSTATED.**
     - `scripts/limit-recover/lr-fire-resume.sh:1181` sets `LR_WRAP="$HOME/.claude/bin/cc-close-attrib"`,
       and `:1740` spawns `env … $wrap $bin …` by path. The script's shebang is `#!/usr/bin/env bash`.
       ps shows `bash /Users/…/cc-close-attrib` with no `/bin/`, which is exactly the argv an
       env shebang produces.
     - Scope, MEASURED with a ps walk now: 21 of 26 top-level claude processes have a cc-close-attrib
       ancestor. Four run under Xcode Python (likely `claude -p` helpers).
     - One teammate pane runs under `/bin/bash …/claude-infrastructure/bin/cc-pane-runner`. That is a
       `#!` exec by path too: `zsh -c 'exec "$CC_PANE_RUNNER"'`, with RUNNER=`$SELF_DIR/cc-pane-runner`
       (`bin/it2-kitty:413`, `:1300`). It goes through the **checkout path**, which the in-place
       `~/.claude/bin` shim does not cover. That is one more root that needs a call-site fix.
     - **This contradicts kernel.md §1d**, which reads `bash cc-close-attrib` as an explicit
       interpreter and concludes "the first `#!` in a lineage also leaks on 15.x". That conclusion is
       unsupported, so T-0 is still open.
     - `run2.sh` is mode 0644 (`ls -la ~/.cache/kalloc-158-ab/`), so the 15.8.1 driver *was* run
       through an interpreter. The doc's "not recorded" can be closed. The conclusion does not change,
       because the lineage above it was tainted.
   - **b. "Shimming about 30 root launchers would cut far more than per-file conversion": NOT SUPPORTED by the census.**
     - My ancestry walk over the first 600 s used pid → ppid from exec events. A root is an old image
       of claude.exe or ppid 1. Pid reuse is guarded by matching image and ppid.
     - Result, MEASURED with that heuristic: **1,181 `#!` (16.9%) at level 0** below a root;
       1,503 (21.5%) at level ≥ 1, which still cost about 1 each under the lineage model; and 4,316
       (61.7%) unresolvable (the parent was exec'd before the window, or a fork-only subshell).
       Of the resolvable execs, 44% are at level 0.
     - So even if T-0 confirms the model, cleaning the roots saves 17-79% (central about 44%), not
       "far more". Run T-0 because it is cheap, but **do not gate the rollout on it**.
     - T-0 caveat: a `kitty @ launch` child is a clean root only if the kitty pid itself started
       from `open`/launchd. If it started from `/opt/homebrew/bin/kitty`, that file is a
       `#!/bin/bash … exec kitty.app` wrapper and the kitty pid is tainted. Prefer `launchctl submit`.
8. **"The bin break surface is 12 code references plus agent-typed calls" (§2): INCOMPLETE.**
   - `hooks/qos-rewrite.sh:187-192` checks `[ "$_SHIM" -ef "$CC_BATS_TARGET" ]` with
     `_SHIM=~/.claude/bin/bats`. With `bats` → cc-shim that test is false, and the hook goes back to
     rewriting bare `bats` tokens, the corruption class recorded in the same file (2026-08-21).
     Add it beside cc-qos-exec/cc-bats in §4 and T-5.
   - "ps and pgrep: the shim produces that same argv" (§3) is false as written: the script argument
     becomes `…/.bin-real/N`. The impact looks small. git grep finds no pgrep/pkill pattern that
     names a bin/ path (0 hits), and lr_recon matches basenames (`telemetry.py:111-113`). But
     `lr_recon/tests/test_observe.py:364` hard-codes `bash /Users/chrisren/.claude/bin/cc-close-attrib`.
   - "`bash ~/.claude/bin/` 5, `/bin/bash ~/.claude/bin/` 7" does not reproduce. `git grep -F`
     returns 0 for both tilde forms over bin, scripts, hooks, launchd and tests, and the
     `"$HOME/.claude/bin/` forms give 7 + 1. It is the same order of magnitude; recount with the
     exact regex before converting.
   - §0.3 and summary line 5 list "23 launchd jobs" among the explicit-interpreter callers of scripts/.
     §2 itself says those 23 exec their main script **by path**, so a scripts/ shim would *help*
     them. My plutil pass finds 22 `exec "<path>"` mains plus 2 that reach claude-accounts through
     `perl … exec @ARGV`. The explicit `/bin/bash …/scripts/…` jobs are the 7 research-* jobs and
     boot-resume. The case against shimming scripts/ still stands on the settings hooks and code
     references, not on launchd.
9. **The `resolve_bin` change (§4) is TOO NARROW.** It only remaps a beside-script candidate in
   `*/.bin-real`. Callers that resolve `$0` to its physical path land in the checkout's bin/. That is
   the 419-exec "phys" class, e.g. `bin/cc-await-ping:853-854` `$_ca_root/bin/cc-kqwait`. Remap any
   `<repo>/bin/<name>` candidate to `$CONFIG_DIR/bin/<name>` when that entry is a shim link, or the
   largest repo class stays untouched.
10. **cc-await-ping → cc-kqwait (§4, 4.7%): a cheaper fix was missed.**
    - `bin/cc-kqwait` already publishes its compiled binary as `~/.cache/cc-kqwait/current-<arch>`
      (hot path at :261, publish at :291-295; `ls` shows `current-aarch64` → the cached Mach-O).
    - cc-await-ping can exec that binary directly and keep the bash tool as the fallback. That is
      1 exec instead of 3-4 (shim, env, bash, Mach-O), no `#!`, and no bash parse of a 300-line file
      with embedded C on every wait.
    - Unverified (INFERRED): that the binary's staleness check still works without
      `CC_KQWAIT_SELF`/`CC_KQWAIT_SRC` in its environment.
11. **R4 baseline "505 test files": UNDERCOUNT.** The regex misses heredoc stubs. 347 test files have
    a heredoc opener followed by a `#!` line. With the printf/echo form, the union is **649** of
    1,589 tracked test files (git grep pipeline at HEAD aa7a40f0f, where the doc's own regex
    gives 506).
12. **Citations: line numbers drift, content matches.** At HEAD aa7a40f0f the beside-script ladder is
    at `bin/cc-backlog:6372` (doc: 6344), and the HOOK SHEBANG arm starts at
    `scripts/ship-land.sh:3907` (doc: 3865-3894). These reproduce exactly:
    - settings hooks: 80 `/bin/bash`, 21 `/usr/bin/env`, 2 `date`, 1 `true` (jq);
    - launchd: 39 plists, 35 `/bin/bash`, 4 `/bin/zsh` (plutil);
    - `cc-qos-exec:59-66`, `install.sh:198` and `:1201`.
13. **The census caveat matters, and three windows sharpen it** (MEASURED: grep `"script":{` | jq over `exec.jsonl`):

    | Window (UTC) | `#!` | agent-context-sync tests and rehearsals | `shasum` | repo | `cc-kqwait` |
    |---|---|---|---|---|---|
    | W1 04:51-05:01 | 6,997 | 45% (pytest cwd) + about 17% (/tmp rehearsals) | 12.9% | 9.3% | 4.7% |
    | W2 05:08-05:24 (46% was the A/B harness) | 19,509 | 27% + 10% postland | 1.6% | 4.5% | 2.4% |
    | W3 05:41-about 05:49 (partial) | 6,052 | about 72% (`/tmp/r23z77fix*`, `z76verify*`: `launchctl-stub`, `scutil`, `uv` stubs) | 5.4% | 13.7% | 4.5% |

    In every window, the stubs written by agent-context-sync's test and rehearsal harnesses are the
    largest single producer. `cc-kqwait` holds steady at 2-5%. `shasum` and the repo class move by
    a factor of 3-8.

### Options the doc missed or ranked too low

- **Lead with the stub factory, not with the in-place bin deployment.** The doc's own rollout puts
  the stubs at step 4. The data says they come first: about 60-75% of `#!` in every window is
  agent-context-sync stubs reached through PATH. Such a stub must be an executable, so a `#!`-free
  stub must be a Mach-O: this is where the cc-shim *binary* earns its keep. As measured, the
  `~/.claude/bin` deployment reaches about 3% plus roots of unproven value (item 7b), and it carries
  the break and loop risks in item 8. Proposed order:
  1. the shim binary + `cc_stub`, and an agent-context-sync PR (its stubs, `hashlib` for `shasum`);
  2. cc-kqwait direct exec;
  3. the launchd plist migration and the `cc-pane-runner`/`cc-close-attrib` root call sites;
  4. the lint ratchet;
  5. the in-place bin deployment last.
- **Run portable test campaigns off the host kernel.** In a Linux container or VM, the guest kernel
  handles `#!`. Docker is installed (`/usr/local/bin/docker`; kernel.md notes `com.docker.vmnetd`),
  and `bin/cc-venue` already routes work to cloud VMs. This is unmeasured and only fits suites that
  do not need macOS, but it is the one option that removes the test share without touching every
  stub.
- **Rejected on inspection; the doc did not list these:**
  - Interposing execve with `DYLD_INSERT_LIBRARIES` fails, because SIP strips `DYLD_*` at every
    `/bin/bash` and `/usr/bin/env` hop.
  - A `#!`-less polyglot (the kernel's ENOEXEC costs about 0.0003, then the caller falls back)
    breaks Python `subprocess` and `posix_spawn` callers such as launchd and libuv, which report
    ENOEXEC instead of falling back.
  - The doc's choice of a Mach-O launcher over both stands.

### Net

- **Sound:** the core premise is now measured. A Mach-O launcher that execs the interpreter costs
  0.07 ± 0.04 elements per exec against 1.04 for a `#!` exec, inside a tainted lineage. The parser
  spec is faithful to xnu 15.x.
- **Weak:**
  - The size claims that set the rollout order: the `shasum` reach is refuted, and the
    root-cleaning upside is overstated.
  - The latency target: +3.5 ms per exec measured, against "≤ 1 ms".
  - Four breakage or coverage gaps: the qos-rewrite `-ef` check, the narrow `resolve_bin`, the
    no-newline ENOEXEC case, and `cc-pane-runner` roots exec'd through the checkout path.
- **Ops note (not this axis):** the "10-minute" eslogger census (pid 90981) had run 59 min by
  00:51 CDT. `exec.jsonl` was 25.3 GB, still growing, with no `summary.txt`. Stopping it needs
  sudo; the disk has 3.7 TiB free (`df -h`).
