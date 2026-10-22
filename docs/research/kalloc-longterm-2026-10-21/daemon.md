# Daemon axis: stop running scripts on the hook hot path (kalloc long-term, 2026-10-22)

Scope: evaluate (a) a long-lived hook dispatcher daemon, (b) compiled rewrites of the hottest hooks,
(c) bash loadable builtins / a persistent coproc. For each: leak effect, latency/CPU, failure modes,
migration cost, and how Claude Code invokes hooks. Recommend one.
Read-only run. The only file written is this one. Box state during the run: load 120-160 on 10 cores
(`uptime`), 46 Claude Code processes, all 2.1.293 (`ps -axo command= | grep claude-293`).

Tags: **MEASURED** = command named, output on this box. **INFERRED** = follows from measured
inputs by stated reasoning. **ESTIMATED** = arithmetic on measured inputs with an assumption named.

## Verdict

1. **No hook architecture is a leak lever any more. A daemon would buy load, not leak.** Of
   the box's `#!` execs in the census window, **15.8% (1,319 of 8,351; 1.81/s of 11.48/s)** come
   from hook process trees (MEASURED, E1). Almost all of those are four by-path calls:
   `/usr/bin/shasum` from `cc-permission-beacon.sh` (758), `waiting-recycle.sh` (113) and
   `dispatch-assert.sh` (18), plus `bin/cc-kqwait` from `mailbox-wake-arm.sh` and its detached
   worker (331) (MEASURED, E2). Three one-line edits remove the same `#!` execs a daemon would
   remove, about 0.16 GiB/day (ESTIMATED: 1.81/s x 1.098 elements x 86,400 s x 1 KiB). The other
   **84%** is outside hooks: temp-dir test fixtures 44%, `/tmp` sandboxes 20%, repo `bin/`/`scripts/`
   run by sessions and launchd 18%, `/usr/bin` perl scripts 11%, Homebrew 6.5% (MEASURED, E1b).
   (a), (b) and (c) cannot reach any of it.
2. **The load case for collapsing hooks is ~10x what the 2026-08 rejection weighed.** Hook trees are
   **30% of all execs on the box: 134,959 of 448,557 in 727 s, 186/s** (MEASURED, E1). That is about
   **124 exec events per Bash tool call** (MEASURED count / 770 Bash calls), where the brief assumed
   "20+". In CPU that is roughly 0.5-0.8 cores (ESTIMATED, E4). The rejection in
   `docs/plans/HOOK_CHAIN_COST.md:123-136` priced the whole chain at 0.054 cores and 480 Bash
   calls/h. The census shows 3,813/h.
3. **Recommendation: (b), built as one compiled dispatcher with no daemon.** Register one entry per
   event/matcher group in Claude Code's **exec form** (`command` + `args`, no `sh -c`). The entry
   runs a small Mach-O (`cc-hook`) that parses the payload once, runs the ported hooks in-process,
   and runs every not-yet-ported hook as `/bin/bash member.sh` with the same payload, all members
   in parallel. If the binary is missing or panics, a pure-builtin bash launcher falls back to the
   existing `hooks/hook-chain.sh`. A daemon (a) adds a shared runtime dependency and a launchd
   lifecycle to save at most ~3 Mach-O execs per Bash call. Its zero-exec form, `type:"http"`
   hooks, **fails open** on 2.1.293: guards are silently disarmed while the daemon is down. (c)
   cannot load into `/bin/bash` 3.2 (MEASURED, E8) and covers ~10% of hook execs.
4. **Do first, before any of the above: "Stage 0", a config-only switch to exec form.** Each shell-form hook today
   runs **3 exec events in its leader pid** (`/bin/sh` → `bash` as sh → `/bin/bash hook.sh`), and
   4 when it goes through `/usr/bin/env` (MEASURED, E1c). Exec form cuts that to 1, about **27% of
   all hook execs** (ESTIMATED from E1c), at +3.7 ms CPU and +5.4 ms wall saved per hook invocation
   (MEASURED, E4). No hook code changes.

## Evidence

### E1. Exec census (root `eslogger exec`, owned by another session; read-only here)

Source: `~/.cache/kalloc-exec-census/20261021T235112/exec.jsonl`, streamed with `python3 -I`.
Window: **2026-10-22 04:51:16 → 05:03:23 UTC, 727.2 s, 448,557 exec events, 617/s**. eslogger was
still appending afterwards (pid 90981 alive at 00:01 CDT), so later reads of the same file see more
rows. E1b used a longer read, so its absolute counts differ.

Classifier (MEASURED inputs, INFERRED rule). Claude Code adds `CLAUDE_PROJECT_DIR` to a hook's env
(binary code, E6) and this Bash tool's env lacks it (`echo ${CLAUDE_PROJECT_DIR:-unset}` => `unset`).
So "hook-tree" means an exec whose env has `CLAUDE_PROJECT_DIR`. Hooks are spawned `detached` (E6),
so each hook is its own process-group leader. The hook name is the label of the group leader's
first exec (`target.group_id == pid`).

| class | exec events | `#!` execs | `#!`/s |
|---|---|---|---|
| other (env scrubbed: tests, sandboxes, non-session) | 207,377 | 5,446 | 7.49 |
| hook-tree | 134,959 | 1,319 | 1.81 |
| session-child (`CLAUDECODE=1`: Bash tool, agents, MCP) | 100,808 | 1,523 | 2.09 |
| launchd/xpc (`XPC_SERVICE_NAME` set) | 5,363 | 63 | 0.09 |
| statusline | 50 | 0 | 0 |
| **total** | 448,557 | **8,351** | **11.48** |

Hook-tree exec events by hook. "Inv" = invocations, counted as leader `/bin/sh` execs carrying the
hook path. The first 15 rows are hooks on the Bash-tool path.

| hook | execs | inv | execs/inv | `#!` |
|---|---|---|---|---|
| validate-bash.sh | 21,954 | 770 | **28.5** | 2 |
| research-block.sh (`*`) | 6,485 | 890 | 7.3 | 2 |
| coldcompile-admit.sh | 6,006 | 765 | 7.9 | 2 |
| cc-permission-beacon.sh (all tools) | 5,466 | 892 | 6.1 | **716** |
| git-worktree-guard.sh | 5,213 | 756 | 6.9 | 2 |
| mailbox-drain.sh (all tools) | 4,890 | 889 | 5.5 | 4 |
| smart-bash-allowlist.sh | 4,612 | 764 | 6.0 | 5 |
| waiting-recycle.sh | 4,512 | 737 | 6.1 | 110 |
| post-tool-batch.sh | 4,253 | 831 | 5.1 | 0 |
| memory-index-drain.sh | 4,086 | 755 | 5.4 | 4 |
| qos-rewrite.sh | 3,981 | 758 | 5.3 | 4 |
| keychain-guard.sh | 3,842 | 756 | 5.1 | 1 |
| teammate-checkpoint.sh (all tools) | 3,354 | 882 | 3.8 | 4 |
| ship-rail-push-allow / rm-safe / offload / log-bash / pr-gate / relay / curl-gate-scope | 2,389-3,260 each | 734-775 | 3.2-4.3 | 0-4 |
| hook:? (detached workers in their own pgid) | 10,849 | — | — | 249 |
| mailbox-wake-arm.sh (Stop/SessionStart) | 9,372 | 29 | 323 | 88 |

- Bash tool calls in the window: **~770** (validate-bash invocations; MEASURED), so 1.06/s, 3,813/h.
- Hooks that fire only on Bash: 73,699 exec events, 96 per call. With the all-tool hooks
  (research-block, beacon, mailbox-drain, teammate-checkpoint, post-tool-batch): **~124 exec events
  per Bash call** (MEASURED sums / 770; slightly high because the all-tool hooks also fire on other tools).
- Top images in hook trees (MEASURED): `/bin/bash` 30,579 · `jq` 24,464 · `/bin/sh` 16,885 ·
  `grep` 13,903 · `sed` 7,975 · `tr` 4,052 · `cat` 3,738 · `/usr/bin/env` 3,713 · Homebrew `bash`
  3,669 · `dirname` 3,049 · `readlink` 2,837 · `ps` 1,994 · `head` 1,789 · `git` 1,646 · `date`
  1,571 · `stat` 1,566 · `awk` 1,387 · `perl` 1,130 · python3.11 1,093 (x2 images).

**E1b. Where all `#!` execs come from** (MEASURED, a later and longer read of the same file:
10,915 `#!` execs). By script location: temp dirs (`/private/var/folders/.../T/`: pytest/bats/
mktemp stubs) **44.1%**, `/private/tmp` (agentsync rehearsal sandboxes, fixtures) **20.2%**, repo
`bin/ scripts/ hooks/` incl. worktrees **18.1%**, macOS system (mostly `/usr/bin/shasum`, a perl
script) **10.8%**, Homebrew **6.5%**, node/npm 0.1%. Interpreters: bash 5,711, env 1,818, sh 1,673,
perl 1,172, python3.x 541.

**E1c. How Claude Code's hook spawn looks in the kernel** (MEASURED, the first 4 execs of each
hook's group-leader pid):

| chain in the leader pid | count |
|---|---|
| `/bin/sh` → `bash`(argv0 `/bin/sh`) → `/bin/bash hook.sh` | 11,588 |
| `/bin/sh` → `bash`(sh) → `/usr/bin/env` → `bash hook.sh` | 3,130 |
| `/bin/sh` → `bash`(sh) → `/bin/bash` → `/bin/sh` | 965 |
| `/bin/sh` → `bash`(sh) → `/bin/bash` → python3.11 | 751 |

So the shell form costs 2 extra exec events per hook (3 with `env`). Over 16,434 invocations that
is ~36,000 of 134,959 hook-tree execs (27%) (ESTIMATED: 11,588x2 + 3,130x3 + 1,716x2).

### E2. `#!` execs inside hook trees, by (hook, script) (MEASURED, same pass)

`cc-permission-beacon.sh` → `/usr/bin/shasum` **758** · hook:? → `bin/cc-kqwait` 238 ·
`waiting-recycle.sh` → `shasum` 113 · `mailbox-wake-arm.sh` → `cc-kqwait` 93 · hook:? →
`cc-decide` 22 · `dispatch-assert.sh` → `shasum` 18 · hook:? → `cc-backlog` 15 · then ≤8 each.
Sources: `hooks/cc-permission-beacon.sh:193` (`printf '%s' "$canon" | shasum -a 256`),
`hooks/waiting-recycle.sh:406,423,436`, `hooks/dispatch-assert.sh:163`. The Stop-path conversion
(`hooks/lib/shasum-direct.sh`) never reached these three. **INFERRED:** sourcing
`shasum-direct.sh` in these three files, and calling `cc-kqwait` as `/bin/bash …/cc-kqwait`,
removes ~1.6 of the 1.81 hook-tree `#!`/s with no architecture change.

### E3. `#!` rate vs zone growth (INFERRED consistency check, not a fit)

`~/.claude/logs/kalloc-zone-series.tsv` (raw bytes): 1792636010 → 1792644507 is 292,767,744 →
380,556,288 B, so **10.1 KiB/s ≈ 10.1 elements/s** over 2.4 h before the census. Census `#!` rate:
11.48/s x 1.098 elements/exec (the 15.8.1 A/B) = 12.6 elements/s. Same order, so `#!` execs can
account for all of the residual. The other ~605 non-`#!` execs/s (Mach-O, many of them ad-hoc
signed Homebrew binaries such as `jq`, Homebrew `bash`, `git`) then retain ~0 per exec. A rate of
0.02/exec would already add 12/s, which the series does not show. **INFERRED** (cred noise and
window mismatch remain). This matters for every option below: a compiled ad-hoc Mach-O hook client
is leak-free.

### E4. Per-exec cost at load ~125-157 (MEASURED, one `bash` loop, 300 iterations, `time`)

Two interleaved rounds at load 125 (CPU = user+sys per iteration, wall = real / 300):

| arm | CPU/iter | wall/iter |
|---|---|---|
| `/usr/bin/true` | 2.0 ms | 4.2-4.4 ms |
| `/bin/bash /dev/null` (exec form) | 2.8 ms | 6.4-7.4 ms |
| `/bin/sh -c "/bin/bash /dev/null"` (shell form) | **6.5 ms** | **12.2-12.3 ms** |
| `echo '{}' \| jq -r .a` | 4.85 ms | 11 ms |
| `python3 -I -S -c pass` (one 200-iteration run, load 157) | — | 41 ms |

- Shell form → exec form saves **3.7 ms CPU and 5.4 ms wall per hook invocation**. At 22.6
  invocations/s that is ~0.08 cores (ESTIMATED).
- All hook trees together: 134,959 events x ~2.5-3.5 ms CPU / 727 s ≈ **0.46-0.65 cores**, plus
  bash interpretation (validate-bash.sh is 2,543 lines), so call it **0.5-0.8 cores**, 5-8% of the
  box (ESTIMATED). Against that, `HOOK_CHAIN_COST.md:127-133` measured 0.054 cores mean at
  480 Bash calls/h and load 16.
- Latency: hooks for one event run **in parallel** (docs, E6), so Bash-call wall time is the
  slowest PreToolUse member plus the slowest PostToolUse member. validate-bash at 28.5 execs x
  ~5-12 ms wall per exec at this load is ~150-350 ms (ESTIMATED). The only per-hook timing on
  disk is UserPromptSubmit (`~/.claude/logs/hook-timing.jsonl`, this boot, n=482 each; MEASURED):
  mailbox-drain p50 589 / p90 1,397 ms, research-precognition-nudge p50 230 / p90 584 ms,
  memory-nudge p50 109 ms. An in-process port of these runs in well under 10 ms (ESTIMATED).
  Wrapper-bias caveat (`HOOK_CHAIN_COST.md:75-80`): use the interleaved deltas above, not the
  absolute values.

### E5. Prior adjudication in this repo (it must be answered, not ignored)

- `hooks/hook-chain.sh:23-50` (landed 8bbf1d9f0 2026-09-03, deliberately not wired). The bash
  collapse does not pay: real 6-guard chain 174 ms serial vs ~180 ms dispatcher. Sourcing made
  validate-bash *slower* (94 → 142 ms, :39-44). Safety law at :65-80: no skip mode, a silent
  inert state is forbidden, every member always runs. Per-member timeouts are lost (:83-89).
- `docs/plans/HOOK_CHAIN_COST.md:158-243` rejected the broker on four grounds. (1) yield vs stakes,
  0.054 cores. (2) a client is still a process per registered entry. (3) blast radius ("a hook
  failure must never block a tool by accident"). (4) "daemons in this repo demonstrably rot".
  §2.3 (:96-121) measured ~81-92% of chain cost *inside* hooks, not in registration.
- `docs/research/panic-2026-10-18-zone-map-shebang-leak.md:267-269` did not file improvement 2
  because after 0070 each hook is a Mach-O bash exec, so collapse "buys load, not leak". The census
  confirms this (E1, E2).

What changed since then: ground (1) is ~10x larger now (E4). Ground (2) is moot, because
exec-form registration plus one entry per group removes the per-entry processes. Grounds (3) and
(4) still hold against a *daemon*. They are the reason (b) beats (a).

### E6. How Claude Code 2.1.293 invokes hooks (MEASURED from the installed binary + official docs)

From `~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (Bun-compiled Mach-O,
code slice at byte offset ~195,048,995, read with `python3 -I` mmap):
- **Shell form** (no `args`): `gye(zn,[],{env:Xn,cwd:ln,shell:si,detached:En,...})` with
  `si=!0` on macOS, so `sh -c "<command>"`. `En=!it` (not Windows), so **detached**: each hook gets
  its own session and process group, confirmed by E1c leaders.
- **Exec form** (`args` present): `gye(hn[0],hn[1],{env:Xn,cwd:ln,detached:En,...})`, **no shell**.
  `${CLAUDE_PROJECT_DIR}` (and plugin vars) are substituted inside `command`/`args`. `~` and
  `$HOME` are NOT expanded, so paths must be absolute. A warning fires when `command` contains
  whitespace with `args` set.
- Hook env: inherited env + `CLAUDE_PROJECT_DIR`, `COLUMNS`/`LINES`, and `CLAUDE_ENV_FILE` on
  SessionStart/Setup/CwdChanged/FileChanged.
- `async` / `asyncRewake` exist (background, no timeout enforced).
- **`type:"http"` hooks exist in 2.1.293** (strings `HTTP hook blocked: … allowedHttpHookUrls`,
  header env interpolation via `allowedEnvVars`).

From https://code.claude.com/docs/en/hooks (WebFetch 2026-10-22):
- HTTP hooks POST the event JSON. A 2xx JSON body uses the command-hook JSON schema. **Connection
  failure, non-2xx and plain-text bodies are non-blocking errors: the action goes ahead.**
  `onFailure:"block"` "Requires Claude Code v2.1.295 or later". The fleet runs 2.1.293, and
  `onFailure:"block"` does not occur as a literal in the binary (grep count 0).
- SessionStart supports only `command` and `mcp_tool` hooks.
- Matching hooks run in parallel. The same handler defined in several settings files runs once.
- Exit 2 blocks, with stderr as the message. Any other non-zero exit is a non-blocking error.
  Default timeout is 600 s (30 s on UserPromptSubmit).
- `sh -c` on macOS for shell form. `/bin/sh` is a Mach-O shim (`file /bin/sh`), and
  `/private/var/select/sh -> /bin/bash`, which explains E1c's sh → bash re-exec.

### E7. Live registration (MEASURED, `jq` over `~/.claude/settings.json`)

104 hook commands. **0** are bare `#!` paths now: every one starts `/bin/bash`, `/usr/bin/env
bash|python3`, or is a `date`/`true` builtin line. The status line is `/bin/bash
~/.claude/statusline.sh`. Per Bash call: 10 PreToolUse(Bash) + `research-block` (`*`), 8
PostToolUse entries matching Bash, and 1 PostToolBatch, about 20 registered entries. 100 hook
scripts start `#!/bin/bash` (78) or `#!/usr/bin/env bash` (22) (`head -1 hooks/*.sh`).

### E8. Bash loadables and coproc (MEASURED)

- `/bin/bash` is 3.2.57, a platform binary (`codesign -dv`: Platform identifier=16). `enable -f
  /opt/homebrew/lib/bash/realpath realpath` → `dlopen … symbol not found in flat namespace
  '_list_optarg'`. The Homebrew loadables are built for the 5.3 ABI and cannot load into 3.2.
- `/opt/homebrew/bin/bash` 5.3.15 (ad-hoc signed) loads them: `strftime`, `realpath` work. The
  shipped set: accept basename chmod csv cut dirname dsv fdflags finfo fltexpr getconf head id kv ln
  logname mkdir mkfifo mktemp mypid pathchk print printenv push realpath rm rmdir seq setpgid sleep
  stat strftime strptime sync tee truefalse tty uname unlink whoami. **None for jq, grep, sed, tr,
  awk, git or ps**, which are ~60% of hook-tree execs (E1).
- `coproc` needs bash ≥4 (3.2 lacks it). A coproc cannot outlive one hook invocation, because
  Claude Code spawns a fresh detached process tree per hook (E6).

## The options

### Stage 0 (prerequisite for every option): exec-form registration

`{"type":"command","command":"/bin/bash","args":["/Users/chrisren/.claude/hooks/x.sh","arg"]}`.
- Leak: 0 change (sh and bash are Mach-O already).
- Win: −2 to −3 exec events per hook invocation, ~27% of hook-tree execs (E1c). −3.7 ms CPU and
  −5.4 ms wall per invocation (E4).
- Failure modes: no `~`/`$HOME` expansion (e.g. `/bin/bash $HOME/.claude/hooks/qos-rewrite.sh`
  needs an absolute path). Matching by command string breaks: `scripts/hook-interp.py`,
  `scripts/lib/hook-cmd-bare.jq` (`cmd_bare`), `install.sh`'s within-event union,
  `scripts/settings-drift-assert.sh`, the hook-chain live-parity guard and the staged migrations
  must all learn the `args` form. Migration 0070's history (panic doc :237-242) shows that this
  normalizer work is most of the cost.
- Cost: one migration across 5 config dirs plus the normalizer. Days, not weeks.

### (a) Long-lived dispatcher daemon

Three variants:
- **a1: `type:"http"` hooks to a localhost daemon.** 0 execs per hook, the only zero-process design.
  On 2.1.293, though, daemon down = connection failure = **non-blocking error, the tool runs**
  (E6). Every guard (validate-bash, rm-safe, keychain, git-worktree, ship-rail, pr-gate) silently
  disarms, which breaks `hook-chain.sh:65-80` ("a silent admit is the failure mode"). Even with
  2.1.295's `onFailure:"block"`, daemon down blocks every tool call in ~40 sessions. Neither mode
  falls back to the scripts. SessionStart cannot use it. The daemon also lacks per-session env
  (`CLAUDE_CONFIG_DIR` differs across 5 config dirs, `CLAUDE_PID`, `CLAUDE_CODE_SESSION_ID`); headers
  with `allowedEnvVars` can forward them. Exit-2/stderr semantics must be re-expressed as JSON
  decisions. Acceptable only for purely observational hooks (log-bash, beacon clear), and those
  are cheap.
- **a2: tiny compiled client (exec form) → unix socket → daemon, with fallback.** 1 Mach-O exec per
  group. On ECONNREFUSED or timeout the client `execv`s the legacy chain, so daemon down equals
  today (safe). But the client is exactly (b)'s binary plus a socket and a launchd job, so the
  daemon's marginal value over (b) is warm state (parsed settings, git facts) and ~1-2 ms of
  process start per group. The cost is a shared dependency for 20+ hooks across 12 events, version
  skew between the daemon and the hook files (a hook edit must invalidate the daemon), and the
  rot record (`HOOK_CHAIN_COST.md:187-189`: 10 of 28 plists absent from the live layer at the
  time).
- **a3: daemon owns pre-forked bash workers that `source` hook functions.** This removes only the
  registration execs. The ~70% inside hooks stays: jq/grep/sed are still forked per call. It also
  adds state bleed between requests (globals, traps, `set -e`, cwd, per-session env), which is why
  hook-chain's source mode runs each member in a subshell (`hook-chain.sh:61-63`). Its yield is
  close to Stage 0's, at far higher risk.
- Leak (all variants): removes the hook-tree `#!` share (1.81/s) only for hooks the daemon
  reimplements natively. The E2 edits remove the same share for free. 0 effect on the other 84%.
- Migration cost: high. Daemon, client, protocol, launchd lifecycle, readiness at boot (boot-resume
  restores ~40 sessions, all firing SessionStart at once), version handshake, plus the native ports
  that produce the actual win.

### (b) Compiled rewrites, delivered as one dispatcher binary (recommended)

- Shape: `cc-hook <Event> <Group>` (Rust or Go; `swiftc` is also present, and
  `bin/kitty-pane-menu-native.swift` is precedent). It is registered in exec form through a
  pure-builtin launcher, `/bin/bash ~/.claude/hooks/cc-hook-launch.sh <Event> <Group>`, which runs
  `[ -x "$BIN" ] && exec "$BIN" "$@"; exec /bin/bash hook-chain.sh <chain>`. Cost: 2 Mach-O execs
  per group, ~6 per Bash call, against ~124 today. The binary reads stdin once, parses the JSON once,
  and derives the shared facts once (session_id, cwd, transcript_path, config dir, desk/teammate
  role; `HOOK_CHAIN_COST.md:151-154` counted 12 hooks parsing `.session_id`, 9 `.cwd`, 6
  `.transcript_path`). It runs ported members in-process and unported members as `/bin/bash
  member.sh` with the identical payload, **concurrently**, so wall time does not regress the way
  hook-chain's serial exec mode did. Decisions are aggregated with the harness precedence that
  `hook-chain.sh:147` already encodes (deny > ask > allow, every member always runs). Per-member
  deadlines go on threads, which closes hook-chain's lost-timeout gap (:83-89) without a `timeout`
  fork.
- Fail-safe: a missing or non-executable binary falls back to the legacy chain via the launcher. A
  panic in a native member is caught and that member re-runs as its legacy script. A registry/disk
  mismatch refuses loudly (exit 2), per hook-chain's law. There is no daemon, so there is no
  "daemon down" state. Residual risk: the launcher itself is missing, which equals a hook missing
  today.
- Leak: native ports compute sha256 in-process and call no `#!` script. Net leak effect is the same
  as the E2 edits (~0.16 GiB/day, once). New `#!` execs on this path become structurally
  impossible for ported hooks.
- Win (ESTIMATED): with Stage 0 plus the collapse alone, hook-tree execs fall from ~124 to ~84 per
  Bash call. Each native port then removes that hook's inner execs. Porting the observational/
  abstain set and the small guards takes the Bash path to ≲15 per call, and validate-bash last to
  ~6. End state: hook trees go from 186/s to ~10-20/s (from 30% of box execs to ~3%), about
  0.4-0.7 cores returned, and PreToolUse/PostToolUse wall from hundreds of ms to ~10 ms.
- Migration cost: incremental and reversible per member. Hot-path bash is large: ~9,000 lines across
  the 20 Bash-path hooks plus 12,919 lines of `hooks/lib/` (`wc -l`), with 1,169 bats files in
  `tests/`. Order the work by exec share x semantic risk. First beacon, mailbox-drain,
  teammate-checkpoint, post-tool-batch, memory-index-drain, log-bash, research-block,
  coldcompile-admit and the waiting-recycle abstain path (observational, or they abstain). Then the
  small guards (rm-safe, keychain, ship-rail, git-worktree-guard, smart-bash-allowlist,
  curl-gate-scope, pr-gate, qos-rewrite) behind a differential corpus replayed from real payloads,
  asserting byte-identical stdout and exit code legacy vs native. validate-bash goes last (22% of
  Bash-path execs alone, 2,543 lines, 12 test files, a DANGER gate with R-3's history at
  `HOOK_CHAIN_COST.md:377-387`). Use libc `regcomp`/`regexec` (POSIX ERE, what BSD `grep -E`
  uses; INFERRED, verify) rather than RE2-style engines, which lack backreferences, so pattern
  semantics stay identical.

### (c) Bash loadable builtins / persistent coproc

- Requires moving hooks off `/bin/bash` 3.2 to Homebrew bash 5.3 (E8). That couples every hook to a
  Homebrew upgrade, and the loadables' ABI moves with it.
- Covers dirname, readlink→realpath, head, stat, date→strftime, basename, mkdir, cat-free reads:
  ~13,000 of 134,959 hook execs (~10%) (ESTIMATED from E1 image counts). jq (18%), grep (10%),
  sed (6%) and tr have no loadable. A custom libjq loadable is new C code with a crash surface
  inside the guard's own process.
- Coproc: lives only within one hook invocation (E8), so it saves at most the repeated jq parses
  inside one hook. Rewriting those to a single `jq` call does the same without a coproc.
- Leak: none (all Mach-O already). Migration: low per hook, low yield.

## Comparison

| | leak effect beyond the E2 edits | execs per Bash call (now ~124) | CPU returned (EST) | failure if its piece is gone | migration |
|---|---|---|---|---|---|
| Stage 0 exec form | 0 | ~84 | ~0.08-0.15 cores | n/a (config) | days, normalizer work |
| (a1) http daemon | 0 | ~0 + daemon work | ~0.5-0.7 | **guards fail open** (2.1.293) or all tools blocked (≥2.1.295) | high |
| (a2) socket daemon + fallback client | 0 | ~3-6 | ~0.5-0.7 | falls back to legacy (safe) | highest (daemon + ports) |
| (a3) pre-forked bash workers | 0 | ~60-84 | ~0.1-0.2 | falls back, state bleed | high |
| **(b) compiled dispatcher, no daemon** | 0 | **~6 at end state** | **~0.4-0.7** | launcher falls back to `hook-chain.sh` (safe) | medium-high, incremental |
| (c) loadables / coproc | 0 | ~110 | ~0.05 | Homebrew upgrade breaks ABI | low, low yield |

## Recommendation

**(b), on top of Stage 0. Do not build a daemon.** For the leak goal, do the E2 edits now (three
`shasum` call sites, one `cc-kqwait` call). After them the hook path contributes ~0 to the leak,
and this axis has nothing more to give. The leak's remaining 84% sits in test fixtures, sandboxes
and session/launchd script runs (E1b), which belongs to the shim and lint axes. (b) is the
long-term fix for the hook layer's load (30% of box execs). It is the only option that is both
structurally exec-free on the hot path and fail-safe without a running service.

Verification per stage: re-run the same `eslogger exec` census and compare exec events per Bash
call (target: ≤ 84 after Stage 0, ≤ 15 after the observational and small-guard ports) and
hook-tree `#!`/s (target ~0 after the E2 edits). Also compare Δ(data.kalloc.1024 − cred)/s at
matched load via `scripts/kalloc-leak-rate.sh`.

## Concerns, unknowns, deviations

- E1b's 44% temp-dir share is the largest single leak source found. These are test harnesses
  writing `#!` stubs (pytest `launchctl-stub`, bats `stub/jq|readlink|python3|grep|dirname`,
  agentsync rehearsal `sb`/`run.sh`) and running them by PATH. Lessons
  `a-shebang-less-stub-seals-only-the-shell-arm` (stubs must have a shebang) and the leak pull
  against each other. A stub runner or `BASH_ENV`-style function stubs is the shim axis's call.
  Flagged, not evaluated here.
- The hook-tree classifier depends on `CLAUDE_PROJECT_DIR`. A hook that scrubs env (`env -i`) is
  counted as "other". hook:? (10,849 execs) are detached workers whose group leader carried no hook
  path, so the per-hook attribution is a lower bound.
- E3 compares a raw-byte zone series with an exec census from a slightly later window. It is a
  consistency check, not a fit.
- E4's absolute values carry the wrapper bias noted in `HOOK_CHAIN_COST.md:75-80`. The deltas
  between arms are interleaved and stand.
- Not checked: whether a running 2.1.293 session re-reads an `args`-form entry on settings change
  without a restart, and whether `install.sh`/drift tooling already tolerates `args`.
- Deviation: none from the brief. No repo, settings, launchd or session was touched. The census
  file was read, not written. No sudo.

## Critique

Adversarial review, 2026-10-22 00:10-00:30 CDT, read-only. The only write is this section: no sudo,
no kill, no files under `~/.cache/kalloc-longterm-ab/`, and the census file was read, not written.
Census passes were mine: `python3 -I` streaming `exec.jsonl` up to `time > 2026-10-22T05:03:23.4`.

**Overall.** Two verdicts hold: "no daemon" and "hooks are not the leak lever". The second is
stronger than the doc says. Four things need correcting:
(1) the per-second figures are rates for one busy window, not daily rates;
(2) the list of E2 edits is incomplete, and a cheaper fix exists for `shasum`;
(3) the doc misses Claude Code's `if` field and fork-free pre-gates, which together get about 40%
of hook execs out with no new binary;
(4) the regex recipe in (b) is wrong as written, and Stage 0 as written would downgrade 22 hooks
from bash 5.3 to 3.2.

### C1. Census counts: CONFIRMED
- My pass found 448,462 events from 04:51:16.50 to 05:03:23.40, against the doc's 448,557.
- These match the doc exactly: 8,351 `#!` execs, 134,959 hook-tree events with 1,319 `#!`, and
  100,808 session-child events with 1,523 `#!`.
- No hook-tree event carries a `BATS_*` or `PYTEST_CURRENT_TEST` env, so tests are not leaking into
  the `CLAUDE_PROJECT_DIR` classifier.
- My xpc/other split differs, because terminal envs carry `XPC_SERVICE_NAME=0`. That does not
  matter here.
- E1 and E2 disagree with each other: beacon `#!` 716 vs 758, waiting-recycle 110 vs 113,
  wake-arm 88 vs 93. My counts are 734, 111 and 81. None of this changes a conclusion.

### C2. "1.81 `#!`/s, 15.8%, ~0.16 GiB/day": a window rate presented as a standing rate (REFUTED as daily)
**Bash call rate.**
- The census window had 764 Bash calls, or 3,782/h (MEASURED: `bash-commands.log` lines stamped
  inside the window).
- The trailing 23 full hours (10-21T05 to 10-22T04) had 22,917 calls, or **996/h**.
- So the window ran at **3.8x the day's mean**. No full hour in the trailing day exceeded 2,738.

**One session caused 85% of the hook-tree `shasum` execs.**
- 764 of the 904 came from session `1e7dc0e1` (MEASURED: grouped by `CLAUDE_CODE_SESSION_ID`).
- That session had a Bash permission prompt pending from 04:39:14 to 05:17:06 UTC, which spans the
  whole census window. Source: `~/.claude/autonomy/permission-archive/2026-10.jsonl`, with
  `waited_s:2272` and `resolved_by:"Stop"`.
- While a beacon is pending, every PostToolUse in that session runs 2 `jq` and 2 `shasum`, then
  exits on a signature mismatch (`hooks/cc-permission-beacon.sh:416-427`). The session's subagents
  kept running tools the whole time.
- The comment at `:405-407` calls this the "rare path ... never on ordinary tool traffic". With a
  multi-agent session holding a prompt open, it becomes the hot path.

**The steady part is `cc-kqwait`.** It ran 298 times, spread over 14 sessions at about 26 each.

**Corrected value of the E2 edits: 0.04-0.16 GiB/day** (ESTIMATED). The floor is the `cc-kqwait`
part alone: 0.41/s x 1.098 x 86,400 x 1 KiB. The ceiling is the doc's window figure. The hook share
of the daily leak is probably under 15.8%. The direction of the doc's conclusion is unchanged, and
stronger.

### C3. "~10x the 2026-08 load case" and "0.5-0.8 cores": OVERSTATED
- **The robust number is per call.** My count is ~131 execs per Bash call (MEASURED: summed
  execs/invocation over the 20 Bash-path hooks); the doc has ~124.
- **At the 996/h day mean** (ESTIMATED, same per-exec CPU as the doc):
  - exec cost alone is 124-131 x 996 / 3600 x 2.5-3.5 ms ≈ 0.09-0.13 cores;
  - with interpretation, about **0.1-0.2 cores**, roughly 2-4x the 0.054 cores at
    `HOOK_CHAIN_COST.md:127-133`.
- **CPU per call is close to August's.** August: 0.054 x 3600 / 480 ≈ 0.41 s. Now: 0.47-0.76 s.
  The growth is mostly call volume.
- (b)'s full prize is therefore about 1-2% of the box on average, and 3-5% at peak hours. That is
  the risk budget `HOOK_CHAIN_COST.md:131-136` asks interventions to be sized against.

### C4. Representativeness of the 84% non-hook split (concern; another axis's verdict)
- **About 69% of the window's `#!` execs (5,786 of 8,351) are tied to agentsync /
  agent-context-sync work** (MEASURED count; matched heuristically on script path or `PWD`, so the
  attribution is INFERRED).
- `PWD=~/Development/agent-context-sync` alone accounts for 4,383.
- The temp-dir `#!` execs came from only 11 POSIX sessions. One of them, sid 56995 with a scrubbed
  env, made 2,955 of the 3,833. Its scripts were pytest `launchctl-stub`, `uv`, `scutil` and
  `agentsync` stubs.
- So the doc's "44% test stubs" is mostly another repo's suite, not claude-infrastructure's bats
  stubs. The tension with the `a-shebang-less-stub-seals-only-the-shell-arm` lesson is of unknown
  size.
- One 12-minute window cannot rank the non-hook sources. Repeat the census at an ordinary hour
  before acting on the 84% split.

### C5. The E2 edit list: incomplete and partly misplaced; a cheaper fix exists
**Where the edits actually are.**
- `cc-kqwait` is not called from `mailbox-wake-arm.sh`. It runs by path at
  `bin/cc-await-ping:913` (`"$KQ_BIN" … &`, inside its wait loop).
- `mailbox-wake-arm.sh:234` runs `cc-await-ping` (a `#!/bin/bash` script) by path.
- The full list is therefore `cc-permission-beacon.sh:193`, `waiting-recycle.sh:406,423,436` (hit
  only on a memo miss), `dispatch-assert.sh:163`, `bin/cc-await-ping:913` and
  `mailbox-wake-arm.sh:234`. That is not "three one-line edits".
- `cc-kqwait` ends by `exec`ing a compiled binary (`bin/cc-kqwait:261`). Resolving that binary once
  and calling it directly drops even the bash hop.

**A cheaper fix than `shasum-direct.sh`.**
- `/sbin/sha1sum` and `/sbin/sha256sum` are Mach-O (hard links of `md5`, `ls -la /sbin`). On stdin
  their output is byte-identical to `shasum` (MEASURED: `printf abc |` both tools gives the same
  `hash  -`).
- They cost **2.5-2.8 ms CPU and 4.5-5.0 ms wall**, against **13.6-14 ms CPU and 16-18 ms wall** for
  `/usr/bin/perl /usr/bin/shasum` (MEASURED: 100-iteration zsh loops, 2 rounds, load 73-97).

**The beacon gate needs no hash at all.** `gated_invocation_ran` (`:205`) only tests that two
signatures are equal and non-empty. Comparing the two non-empty canonical strings directly is
equivalent, barring a 64-bit prefix collision. That removes both forks on the storm path in C2.

**"~0 after the edits" is overstated.**
- About 117 other hook-tree `#!` execs remain in the window, about 0.16/s: `cc-decide` 25,
  `cc-backlog` 14, `cc-custody` 10, `cc-research` 8, `cc-resume-debt` 8, `cc-await-ping` 7. These
  are `bin/` tools run by name, which is the shim/lint axis.
- SessionStart bursts (boot-resume, about 40 sessions at once) were not in the window.

### C6. Missed option: the `if` field (config only, zero execs on a non-match)
**It exists in 2.1.293.**
- Command-hook schema in the binary (near byte 184,713,700): `if:Mt()`, described as "Permission
  rule syntax to filter when this hook runs (e.g., "Bash(git *)") ... Avoids spawning hooks for
  non-matching commands."
- The evaluator (byte ~195,081,124) returns no hook and logs "Skipping hook due to if condition ...
  not matching".

**What the docs say** (https://code.claude.com/docs/en/hooks):
- every subcommand of a compound command is checked;
- a command whose subcommands cannot be determined runs the hook anyway;
- the filter is "best-effort", so use the permission system for a hard allow or deny.

**Where it is safe.**
- It is safe by construction for **allow-only hooks** (`rm-safe-allowlist`, `ship-rail-push-allow`):
  a missed match means the normal prompt, never a bypass.
- It is safe for **advisory hooks** (`relay-verbatim`).
- It is **not** safe for deny guards (keychain, git-worktree, pr-gate, curl-gate), where a matcher
  miss is a bypass.
- No live entry uses `if` today (MEASURED: `jq` over `~/.claude/settings.json`).

**Also missed: fork-free pre-gates on the raw payload.**
- `pr-gate.sh:52` and `curl-gate-scope.sh:82` already run a substring test on the raw payload before
  any fork.
- `keychain-guard.sh:38` and `git-worktree-guard.sh:49` run the same kind of test only after `jq`
  (plus 2 `sed` in the worktree guard). A superset substring test on the raw JSON, placed first,
  keeps the guard's semantics. After Stage 0, a non-matching call would then cost exactly 1 exec.

**Combined effect** (ESTIMATED from my per-invocation counts):
- Stage 0 takes ~131 to ~87 execs per Bash call.
- Adding `if` on the 3 allow/advisory hooks, plus pre-gates on keychain, git-worktree and
  coldcompile, takes it to **~72-80**.
- That needs no new binary and no change to any deny guard. What (b) adds beyond that is mostly
  `validate-bash.sh`.

### C7. Stage 0 has an interpreter trap the doc does not state
- Today the 22 `/usr/bin/env bash` entries run **Homebrew bash 5.3**. In the hook trees, `env`
  shows 3,713 execs and Homebrew `bash` 3,669, which match (MEASURED, E1).
- `scripts/hook-interp.py:8-13` kept `env` verbatim on purpose.
- The doc's Stage 0 example uses `/bin/bash`, and its 27% figure assumes env hooks go from 4 execs to
  1. Rewriting them to `/bin/bash` downgrades 22 hooks to bash 3.2. 18 of the 22 use `set -u`
  (MEASURED, `grep`), and bash 3.2 under `set -u` aborts on an empty `"${a[@]}"`.
- Fix: use `"command":"bash"`. Exec form resolves `command` on `PATH` (docs), so it is still 1 exec
  with today's interpreter.
- The doc's open question about live pickup is partly answered by the docs: "Direct edits to hooks in
  settings files are normally picked up automatically by the file watcher". That is untested here.

**Stage 0 timing: CONFIRMED.** My re-run at load 105-120 (`/usr/bin/time -p`, 200 iterations,
2 rounds):

| arm | CPU | wall |
|---|---|---|
| exec form | 2.8-3.05 ms | 7.0-7.3 ms |
| shell form | 6.55-6.75 ms | 13.5-14.4 ms |
| **saving** | **3.7 ms** | **6.4-7.2 ms** |

### C8. The regex recipe in (b): REFUTED as written
The doc says to use "libc `regcomp`/`regexec` (POSIX ERE, what BSD `grep -E` uses)". I tested it
with `ctypes` against `libSystem` on this box:

| pattern | input | `/usr/bin/grep -E` (BSD 2.6.0) | `REG_EXTENDED` | `+REG_ENHANCED` | `+REG_ENHANCED+REG_NEWLINE` |
|---|---|---|---|---|---|
| `\bconfig\b` | `git config --get x` | match | **no match** | match | match |
| `\bconfig\b` | `git bconfigb x` | no match | **match** | no match | no match |
| `^rm ` | `echo a\nrm -rf x` | match | no match | no match | match |

- Plain POSIX ERE inverts the word-boundary guard.
- Matching grep needs `REG_EXTENDED|REG_ENHANCED|REG_NEWLINE`, or a line split.
- These are the same two traps the repo already measured for bash `=~` (`HOOK_CHAIN_COST.md:399-412`;
  R-3 retired at `:377`, 56 of 1,672 corpus pairs diverging).
- A native `validate-bash` must clear `scripts/validate-bash-differential.sh` first.
- In this Bash tool `grep` is a ugrep shell function; hooks resolve `/usr/bin/grep`
  (`/bin/bash -c 'command -v grep'`).

### C9. Claims re-checked and CONFIRMED
**The 2.1.293 binary and the docs.**
- The 2.1.293 HTTP hook schema has no `onFailure`. Its fields are type, url, if, timeout, headers,
  allowedEnvVars, statusMessage, once and cloud. The binary's 80 `onFailure` hits belong to
  `policyHelpers`.
- Docs: a connection failure is a non-blocking error, `onFailure` needs 2.1.295, and SessionStart
  takes only command and mcp_tool hooks.
- `args` exec form is present in the command-hook schema (`Dp()`).

**Shells.**
- `/bin/bash` 3.2.57 fails to load Homebrew loadables (`_list_optarg`) and has no `coproc`.
  Homebrew bash 5.3.15 loads `realpath`.
- `/private/var/select/sh -> /bin/bash`.

**Repo cites and timings.**
- The cited lines in `hook-chain.sh` (:23-50, :61-89, :147) and `HOOK_CHAIN_COST.md` (:75-80,
  :123-136, :151-154, :158-243, :187-189) say what the doc says they say.
- UserPromptSubmit timings, recomputed this boot (n=506): `mailbox-drain` p50 573 ms, p90 1,379 ms.

**E3 is stronger than stated.** Rows 184 and 191 of the zone series give 10.1 KiB/s. The doc
missed an interval that brackets the census: rows `1792644507` → `1792645729` (1,222 s, containing
the 727 s window) give 380,556,288 → 397,224,960 B, which is **13.3 elements/s raw against 12.6
predicted**. That supports "Mach-O execs retain ~0" (roughly ≤0.003 per exec, INFERRED, with
cred noise of about ±1.6/s).

**The lineage caveat does not undercut 1.098 here** (INFERRED).
- willmcginnis (claude-code#66020) found the first `#!` in a lineage cheap on M1 26.6.2.
- But the 15.7.9 A/B gives 0.94, 1.98 and 2.86 for 1, 2 and 3 nested `#!` scripts (panic doc
  :79-82), which is about 1 per `#!` whatever its position.
- How the 15.8.1 `run2.sh` itself was launched is not recorded. Arm C in
  `kalloc-longterm-ab/run.sh` will test this on 15.8.1.

### C10. Operational note (outside the doc's claims)
- At 00:12 CDT the census `eslogger` (pid 90981) was still running, 21 min in.
- Its stop command (`sudo -A pkill -INT -f ^/usr/bin/eslogger exec$`, pid 24146) is blocked on an
  `osascript` password dialog (pid 24190, up 11:42).
- `exec.jsonl` was 8.13 GB and growing. With 3.8 TiB free there is no immediate risk.
- I did not touch it.

### Verdict on the recommendation
**"Do not build a daemon": UPHELD.**

**"(b) as the long-term fix": DOWNGRADED.** At day-mean volume, its prize is about 0.1-0.2 cores.
Do these first:
1. The leak edits, all of them (C5): `/sbin/sha*sum`, or no hash at all in the beacon gate; and
   `/bin/bash` or the compiled binary at `cc-await-ping:913` and `mailbox-wake-arm:234`.
2. Stage 0, with `"command":"bash"` for the env hooks (C7).
3. `if` on the allow-only and advisory hooks, plus fork-free pre-gates (C6).

Then re-census at an ordinary hour. Fund (b), meaning a native `validate-bash` behind the
differential corpus, only if the per-call cost at real volume still justifies it.
