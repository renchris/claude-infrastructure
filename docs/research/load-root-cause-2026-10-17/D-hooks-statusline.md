# D — Hook and statusline fork cost per tool call (2026-10-17)

Axis owner: worker D of the load-root-cause wave. Read-only investigation. No hook, test, reaper or
installer was run. Stop-hook cost is OWNED by the in-flight Wave 4c session
(`~/.claude/handoff-briefs/load-wave-4c-stop-hook-ledger.md`); it is cited here, not re-proposed.

## 0. Verdict

**Hooks and the statusline are NOT a root cause of load 365-520. They are a second-order term,
about 4-6% of machine-wide process creation (ESTIMATED) and well under 5% of CPU.** That matches
the one root exec trace on record (O5, 2026-10-12: all hook scripts together ≈ 3-5% of execs, ≈ 84%
from agent-context-sync test runs; `docs/research/load-hook-timeouts-2026-10-11/O5-EXEC-TRACE.md`).
The cost that is left can still be roughly halved with changes that do the same work with fewer
processes and change no verdict or output. The largest single structural lever is to move the
advisory PostToolUse chain out of process-per-hook. The cheap levers are listed in § 5.

| Quantity | Value | Tag / method |
|---|---|---|
| Machine fork rate now | 1,443 / 1,615 / 1,730 forks/s (three 10 s windows, load 45-50) | MEASURED: pid-counter delta, `perl /tmp/d-hooks-pidrate.pl` (forks a child every 10 s and diffs the pids, wrap-corrected) |
| Tool calls now | 0.95 tools/s, 0.84 Bash/s (07:38-07:49Z) | MEASURED: `~/.claude/logs/tool-batch-census.jsonl` (PostToolBatch row per batch) |
| Tool calls, 15 h window | 15,493 tools (Bash 84.7%); mean 0.29/s; 10-min buckets median 139, p90 353, p95 448, max 649; peak hour 1,753 | MEASURED: `python3 -I /tmp/d-hooks-tbc.py tool-batch-census.jsonl{.1,}` (2026-10-16T16:4x → 10-17T07:3x) |
| Cross-check | bash-commands.log 01:00-01:59Z = 915 Bash; census hour 01 = 1,099 tools × 0.847 ≈ 931 | MEASURED, two independent writers (`validate-bash.sh:2305` vs `post-tool-batch.sh:128`) agree within 2% |
| Subagent share of tool calls | 59.6% (9,660 of 16,215) carry an `agent_id` | MEASURED: perl over the census `agent_id` field |
| Hook processes per Bash call | 20 (11 PreToolUse, 8 PostToolUse, 1 PostToolBatch) | MEASURED from `~/.claude/settings.json` |
| External execs per Bash call, hooks | ≈ 55 inside the hooks + 20 hook launches (1 fork + 1-2 execs each) ≈ 75-95 | ESTIMATED: executed-path code reading, weighted by the measured 94% compound-command share and the 59.6% subagent share (§ 3) |
| Hook share of forks now | 0.84 Bash/s × 75-95 + ≈ 3/s for other tools ≈ 66-83 execs/s ≈ 4-5.5% of 1,443-1,730/s | ESTIMATED from the two MEASURED rates above |
| python3 starts per Bash call | 1.4 (smart-bash-allowlist on every call, bash-output-offload on lead calls) | ESTIMATED from code + subagent share |
| Statusline refresh rate | 0.30 refreshes/s machine-wide (9 in 30 s, 1 of 23 interactive sessions active); O5 saw 33 in 30 s = 1.1/s | MEASURED: `perl /tmp/d-hooks-sl-rate.pl` (mtime changes of `/tmp/cc-telemetry/*.json`, 4 Hz, 30 s), O5 attribution file |
| Statusline execs per refresh | ≈ 10-11, plus `git status` 40-70 ms wall / 50 ms sys in a 9,018-file worktree | ESTIMATED execs (code); MEASURED git time `/usr/bin/time -p env GIT_OPTIONAL_LOCKS=0 git status --porcelain=v2 --branch --no-ahead-behind --untracked-files=no` ×3 |
| Statusline share of forks | 0.3-1.1/s × 11 ≈ 3-12 execs/s ≈ 0.2-0.8% | ESTIMATED |

The lead's "150 new pids per 5 s" figure is ~50× below the pid-counter rate measured here. A `ps`
snapshot diff cannot see processes that live under 5 s, and nearly all of these do. Use the
pid-counter method for fork rates.

## 1. Prior art this builds on (and does not repeat)

- `docs/plans/HOOK_CHAIN_COST.md` §2-3 (closed 2026-08-09): process creation is the cost. On the
  modal path ~81-92% of chain time is spent INSIDE hooks (their child execs), not in launching them.
  It rejected a broker and measured the dispatcher collapse NEGATIVE on wall time (174 vs ~180 ms).
- `docs/research/hook-chain-occupancy-readjudication-2026-09-08.md` §4.1, §5.2: in its default exec
  mode the collapse removes no fork. It lowers peak concurrency (10 → 2). Parallel dispatch costs
  2.9× (2.45-5.32) the occupancy of serial at quiet ambient, and more as ambient rises.
- `docs/research/validate-bash-fork-census-2026-08-17.md`: 24 externals on `safe-short` when the
  file was 1,012 lines. It is now 2,306 lines, but its hot path was re-plumbed to ONE payload `jq`
  (`hooks/validate-bash.sh:63`) and a fork-free logger (`:2299-2305`).
- `docs/plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md` Waves 1-4b: UserPromptSubmit (WP1-WP6) and Stop
  (Wave 4/4b) were already streamlined. Wave 4c (Stop ledger) is in flight under another session.
- `docs/plans/HOOK_SURFACE_100P.md` §3f: handler types. `http` = "the answer to the per-hook fork
  tax only once that service does [exist]". `mcp_tool` silently disables EVERY hook in its file on
  2.1.114.
- `docs/research/load-hook-timeouts-2026-10-11/investigations.json` [3]: capability table (`if`
  filter CL 2.1.85, exec form `args` CL 2.1.139, in-process plugin "mods"). Also
  `docs/research/claude-code-mods-2026-10-03/REPORT.md` §5 (C8 hot-path fork suppression rejected
  at 1.2% of turn time; installed-plugin modules gated by `tengu_plugin_hooks_modules:false`).

Fleet binary now: 28 of 31 `claude` processes run `~/.claude-293/node_modules/.bin/claude`; 2 run
`/opt/homebrew/bin/claude` (version not read); 1 `claude.exe` (MEASURED: `pgrep -x claude` →
`ps -o comm= -p …`). `~/.claude-versions/current` still points at 2.1.114 (MEASURED: `readlink`).

## 2. Q1 — registered hook commands per event, and forks per firing

Source: `~/.claude/settings.json` (45 KB, Oct 12). `~/.claude-next`, `-secondary`, `-tertiary`,
`-quaternary` all symlink their `settings.json` to it (MEASURED: `readlink`). Each has 101 hook
commands and the same `statusLine` (`settings.json:1279-1281`). The other `~/.claude-*` dirs
(`-156 … -293`, `-next4`, `-plans`, `-scratch`, `-tasks`, `-versions`) have no `settings.json`. Of
the project files, `.claude/settings.json` and `.claude/settings.local.json` here, and
agent-context-sync's `.claude/settings.local.json`, register no hooks and no statusLine.

| Event (matcher) | Registered commands that fire | Forks/execs per firing (ESTIMATED unless noted) |
|---|---|---|
| PreToolUse Bash | 10 Bash + `research-block.sh` (`*`, `settings.json:884`) = **11** | ≈ 31 internal + 11 launches. Per hook below |
| PreToolUse Write/Edit/MultiEdit | backup-before-write, check-edit-boundary, plan-agent-teams-default, workflow-script-edit-allow + research-block = **5** | not traced (5.4% of calls) |
| PreToolUse Agent / AskUserQuestion / WebFetch-WebSearch / ms365 mail | 2+1 / 1+1 / 1+1 / 1+1 | not traced (<1% of calls each) |
| PreToolUse any other tool (Read, Grep, …) | research-block = **1** | ≈ 5 + 1 launch |
| PostToolUse Bash | log-bash, waiting-recycle, relay-verbatim, memory-index-drain, bash-output-offload + match-all teammate-checkpoint, cc-permission-beacon clear, mailbox-drain post-tool = **8** | ≈ 21 internal (subagent-weighted) + 8 launches |
| PostToolUse Write/Edit/MultiEdit | post-file-edit, plan-index-update, validate-plan-structure, plan-version-commit, memory-index-drain + 3 match-all = **8** | not traced |
| PostToolUse other tools | 3 match-all (+1 for TaskCreate/Update, ExitPlanMode, ms365 get-mail) | ≈ 7 + 3 launches |
| PostToolBatch | post-tool-batch = **1** per batch | 2 (`jq` :90, `stat` :124) + 1 launch |
| PostToolUseFailure | Bash 3, other 2 | rare |
| UserPromptSubmit | **7** (`settings.json:970`) | streamlined in Wave 1: memory-nudge 4-7 on a non-due prompt (WP3), mailbox-drain one jq (WP4), handoff-intent-nudge cheap grep first (WP1), session-beat prompt detaches (WP6). ≈ 25-40 per prompt (ESTIMATED); fires on prompts, loop ticks and task notifications |
| Stop | **13** (`settings.json:1014`) | OWNED by Wave 4c. Ledger ≈ 60-90 starts per cold compute (plan § Wave 4b) |
| SessionStart | **10** (4 async) + InstructionsLoaded 1 | once per session; spawns 2 long-lived processes (lead-crash-watchdog ×33-37, poll 30 s ≈ 3 execs/poll ≈ 3.5 execs/s fleet-wide; mailbox-wake-arm timeout 14400) |
| SessionEnd | **7** | once per session |
| Notification | permission_prompt 2, elicitation_dialog 2, idle_prompt 1 | rare |
| PermissionRequest | Bash 3, AskUserQuestion 2, ExitPlanMode 2, Write/Edit 2, other 1 | per prompt shown |
| PreCompact / PostCompact / CwdChanged / ConfigChange / TaskCompleted / TeammateIdle / WorktreeCreate / PermissionDenied / StopFailure | 2+1 / 1 / 1 / 1 / 1 / 1 / 1 / 1 / 1 | rare |
| FileChanged | `file-changed.sh` registered TWICE (matchers `/Users/chrisren/.claude/file-watch-paths` and `*`, `settings.json:607,617`) | open question: does one change fire it twice? |

### 2.1 Per-hook executed path on a Bash call (ESTIMATED from code)

Weights: 94.0% of Bash commands are compound (MEASURED: 6,458 commands in the last 3 MB of
`bash-commands.log`; 6,068 contain one of `; & | < > ( )` backtick newline; 390 simple, 14 with an
env prefix). 59.6% of calls are subagent calls, where `cc_hook_skip` (`hooks/lib/hook-profile.sh:34-43`)
makes the advisory and lead-only hooks exit right after launch.

| Hook | Common-path externals | Sites |
|---|---|---|
| smart-bash-allowlist | `readlink` + **`exec python3`** (every call) | `hooks/smart-bash-allowlist.sh` (readlink loop, `exec python3 "$_CORE"` last line); `hooks/lib/smart-bash-allowlist.py:41-45` imports |
| curl-gate-scope | `readlink` + `dirname`, BEFORE the scope test that exits 0 | `hooks/curl-gate-scope.sh:52-57` resolve; `:76-100` scope; python3 only on delegate `:72` |
| validate-bash | `jq` (single parse) + `dirname` + a few more; not re-censused | `hooks/validate-bash.sh:63`, `:85`; logger `:2299-2305` is fork-free |
| git-worktree-guard | `jq` + 2× `sed`, BEFORE the case that exits 0 for non-git commands | `hooks/git-worktree-guard.sh:28`, `:38-39`, case `:42-45` |
| keychain-guard | `jq` | `hooks/keychain-guard.sh:26`, case `:38` |
| rm-safe-allowlist | `jq` + `grep` (sudo-rm test runs BEFORE the cheap `^rm` test) | `hooks/rm-safe-allowlist.sh:46`, `:55`, `:62-66` |
| ship-rail-push-allow | `jq` (compound exits at the case) | `hooks/ship-rail-push-allow.sh:55`, `:62-64` |
| qos-rewrite | `head` + `jq` on compound (exits `:285-287`); +14 on simple (`grep`, 2 `dirname`, `readlink`, 3+8 per-pattern `grep`) | `hooks/qos-rewrite.sh:108`, `:112`, `:336-343`, `table_match :344-357` |
| coldcompile-admit | `head` + `jq` + `grep`(bats) + 2 `dirname` + `readlink` + 3 per-pattern `grep` ≈ 9 on compound (94%) | `hooks/coldcompile-admit.sh:75`, `:79`, `:103-104`, `:125-133`, `:145-153` |
| pr-gate | `cat` | `hooks/pr-gate.sh:41`, case `:48-51` |
| research-block (`*`) | `dirname` + rr_init `readlink`/`dirname` + payload `jq` + registry `jq` + `_rp_canon` subshells ≈ 5 | `hooks/research-block.sh:21-36`, `hooks/lib/research-router.sh:18-19`, `scripts/lib/research-program.sh:73-81` |
| log-bash | lead: 4× `jq` on the same payload + `mkdir -p` + `date` = 6; subagent 0 | `hooks/log-bash.sh:37-41`, `:57-58` |
| waiting-recycle | lead: `cat` + 3× `jq` (same payload) + 2× `shasum\|cut` + IDL logging ≈ 13; subagent: `cat` | `hooks/waiting-recycle.sh:638`, `:734-736`, `:755`, `:763` |
| relay-verbatim | lead: `jq` | `hooks/relay-verbatim.sh:23`, case `:27-32` |
| teammate-checkpoint (all tools) | `mkdir -p` + `dirname` BEFORE the subagent skip; lead: + `jq` (+`git rev-parse` outside worktrees) + counter write; every 5th lead call in a dirty tree: `git status --porcelain`, index `cp`, `git add -A` on a temp index, `write-tree`, 2 `rev-parse`, `commit-tree`, `update-ref` | `hooks/teammate-checkpoint.sh:49`, `:89-92`, `:94`, `:119`, `:147-154`, `:308`, `:387-427` |
| cc-permission-beacon clear (all tools) | `cat` + `jq` + 2 heartbeat truncations | `hooks/cc-permission-beacon.sh:66-67`, `beat`/`arch_beat`, `:351-412` |
| memory-index-drain | lead: `jq` + `readlink` + 2 `dirname` + `stat` + `cat` ≈ 6-8 | `hooks/memory-index-drain.sh:67`, `:80-86`, `:122`, `:142` |
| bash-output-offload | lead: `readlink` + `dirname` + **`python3`** | `hooks/bash-output-offload.sh:46`, `:51-59` |
| post-tool-batch | `jq` + `stat` | `hooks/post-tool-batch.sh:90`, `:124` |

**Process-start prices on this box right now** (MEASURED, `perl /tmp/d-hooks-pystart.pl`, 11
interleaved runs, load 57-60): `python3 -c pass` median 45.3 ms; `python3 -S -c pass` 31.5 ms;
`python3 -c 'import json,os,re,sys'` 47.2 ms vs 36.2 ms with `-S`; `bash -c :` 5.0 ms;
`/usr/bin/true` 6.0 ms; `sh -c /usr/bin/true` 14.4 ms. `jq` costs 6.5-7.2 ms on a hook-shaped call
(MEASURED, `perl /tmp/d-hooks-jq.pl`, 15 runs). `/usr/bin/jq` (1.7.1-apple) retires 18.3M
instructions against Homebrew jq's 25.4M (`/usr/bin/time -l`), which is ≤1 ms and not worth a PATH
change. **One python3 start costs as much as ~7 jq or ~9 bash starts.**

## 3. Q2 — the statusline

`statusLine: {"type":"command","command":"~/.claude/statusline.sh"}` (`settings.json:1279-1281`).
There is no `refreshInterval`, so it runs only on events. `~/.claude/statusline.sh` is a COPY (not a
symlink) and is byte-identical to the repo's `statusline.sh` (MEASURED: `cmp` printed nothing).

**Cadence (cited, code.claude.com/docs/en/statusline § "When the status line updates"):** it runs
at session start and resume, and again on each new assistant message, `/compact`, permission-mode
change, vim toggle, `command` change, rate-limit `resets_at`, and prompt-cache `expires_at`.
"Claude Code debounces updates at 300ms … If a new update triggers while your script is still
running, Claude Code cancels the in-flight script." So the ceiling is ~3.3 runs/s per streaming
session. Only interactive main sessions run it. The docs' own tip: "commands like `git status` can
cause lag … caches git information … every 5 seconds".

**Per refresh, executed path (ESTIMATED from code):**

| Line | External |
|---|---|
| `statusline.sh:40` | `cat` |
| `:77-86` | `jq` (one payload parse) |
| `:152` | `grep -c` mailbox (only when a mailbox file exists) |
| `:222` | `jq -r .pid` of `/tmp/cc-telemetry/<sid>.json` |
| `:226-228` | `ps`/`sed`/`ps`/`tr` per hop, only when the cached pid is dead |
| `:237-245` | `jq -c` writes telemetry; `:246` `mv` |
| `:299` | `grep -q` over `autonomy/session-window.jsonl` (439,356 bytes, MEASURED `ls -la`) |
| `:343` | `basename "$(pwd)"` |
| `:344` | `git rev-parse --short HEAD` |
| `:348` | `git status --porcelain=v2 --branch --no-ahead-behind --untracked-files=no`. It lstat()s every tracked file and, without `GIT_OPTIONAL_LOCKS=0`, may rewrite the 1.2 MB index under `index.lock` |

That is ≈ 10-11 execs plus one full lstat pass of the tree per refresh. MEASURED here: 9,018
tracked files in a claude-infrastructure worktree (292 in agent-context-sync), and `git status`
took 0.04-0.07 s real and 0.05 s sys per run at load ~70-100. No `GIT_OPTIONAL_LOCKS`, fsmonitor or
cache appears in the script (MEASURED: `grep -n 'GIT_OPTIONAL_LOCKS\|fsmonitor\|cache' statusline.sh`
→ none).

**× sessions:** 23 interactive sessions have a telemetry file (MEASURED: 23 `*.json` in
`/tmp/cc-telemetry`). Measured now 0.30 runs/s → ≈ 3 execs/s and ≈ 15 ms/s of sys. At O5's 1.1/s
→ ≈ 12 execs/s and ≈ 55 ms/s. Upper bound if all 23 stream at once (~0.3/s each, the rate one active
session showed) → ≈ 7/s → ≈ 75 execs/s and ≈ 0.35 cores of kernel time in 9k-file repos
(ESTIMATED). That bound is where the statusline would matter. The 300 ms cancel also means that
under load a slow `git status` is often killed before it prints, so the work is wasted.

## 4. Where a Bash call's hook cost goes now, ranked (ESTIMATED execs per Bash call)

1. Launches: 20 hook processes. Open question: are they 1 or 2 execs each? (§ 7)
2. coldcompile-admit ≈ 8.7 (the table walk runs on the 94% compound path)
3. waiting-recycle ≈ 5.8 avg (13 per lead call)
4. research-block ≈ 5 (also fires on every non-Bash tool)
5. teammate-checkpoint ≈ 3.6 avg, plus a heavy git snapshot every 5th lead call in a dirty tree
6. validate-bash ≈ 3-6 (not re-censused)
7. git-worktree-guard 3; mailbox-drain ≈ 3; memory-index-drain ≈ 2.8 avg; log-bash 2.4 avg; qos-rewrite 2.8 avg
8. python3: 1.4 starts per call ≈ 63 ms of process start per call at load 57 (MEASURED unit price) — the largest single CPU item per call

## 5. Q3 — the remaining per-tool-call costs and throughput-neutral fixes

All of these keep the same verdicts and outputs. None of them waits, throttles, sheds, demotes or
caps anything. Each removes processes on a path that today pays for them and then discards the
result.

### R1 (P1) — remove python3 site import from the two per-call python hooks
`-S` cut start-up by 14 ms (31%) bare and 11 ms with the hooks' real stdlib imports (MEASURED
above). Both scripts import only stdlib plus a module in their own lib dir. smart-bash-allowlist
gets `curl_ssrf` via `sys.path[0]` (the script dir), which `-S` keeps. bash-output-offload inserts
`CC_BO_LIB` into `sys.path` itself. lesson_recall.py and curl_ssrf.py import only stdlib (MEASURED:
`grep '^import\|^from'`). Do NOT use `-I`: it drops the script dir and breaks `import curl_ssrf`.
Sites: `hooks/smart-bash-allowlist.sh` (last line `exec python3 "$_CORE"` → `exec python3 -S "$_CORE"`),
`hooks/bash-output-offload.sh:59` (`python3 -c` → `python3 -S -c`). Effect: ≈ 1.4 × 11-14 ms ≈
15-20 ms of process start per Bash call. At 0.84 Bash/s that is ≈ 0.015 cores (ESTIMATED).

### R2 (P1) — reorder cheap exits ahead of forks, and resolve paths by parameter expansion
Same precedent as `da3949756` (wrap-ledger: 11 `dirname` → 0) and Wave 1 WP1 (cheap test first).
- `curl-gate-scope.sh:52-58`: move the symlink and `HOOK_DIR` resolution into `delegate()`. Only
  that path uses `$GATE`. −2 per Bash call.
- `git-worktree-guard.sh:38-45`: add a superset pre-test on the raw `$cmd`
  (`case "$cmd" in *git*worktree*remove*|*git*branch*) ;; *) exit 0 ;; esac`) before the 2 `sed`
  calls. Any command the existing case would admit contains these substrings, so it is a strict
  superset and the outcome is equal. −2.
- `rm-safe-allowlist.sh:55-66`: all three tests end in `exit 0` with no output, so run the in-shell
  `[[ "$CMD" =~ ^[[:space:]]*rm[[:space:]] ]] || exit 0` first. −1.
- `pr-gate.sh:41`, `cc-permission-beacon.sh:66`, `waiting-recycle.sh:638`: `$(cat)` →
  `IFS= read -r -d '' VAR || true`, the form the sibling hooks already use. −1 each where it fires
  (beacon fires on every tool).
- `teammate-checkpoint.sh:49`: `mkdir -p "$WATCHDOG_DIR" "$(dirname "$LOG_FILE")"` runs on every
  tool call, before the subagent skip at `:89-92`. Guard it with `[ -d … ] ||` and `${LOG_FILE%/*}`.
  −2 on every tool call, subagents included.
- `log-bash.sh:37-41`: 4 `jq` on one payload → one `jq` with a field separator, keeping the per-field
  fallback (Wave 4 learning 1, plan:76). `:57` `mkdir -p` → `[ -d ] ||`. −4 per lead Bash call.
- `waiting-recycle.sh:734-736`: 3 `jq` → 1. Memoize the `shasum` keys `:755`, `:763` per (CFG, CWD)
  in a file named by the key's own inputs (they are pure functions of their inputs). −2 to −4 per
  lead call.
- `research-block.sh:21-23`, `hooks/lib/research-router.sh:18-19`, `memory-index-drain.sh:80-86`,
  `bash-output-offload.sh:51-59`, `coldcompile-admit.sh:125-133`, `qos-rewrite.sh:336-343`:
  `dirname` → `${p%/*}`. Keep `readlink`, since bash 3.2 has no builtin. −1 to −3 each.
- `qos-rewrite.sh:108`, `coldcompile-admit.sh:75`: `head -c 200000` → `IFS= read -r -d '' -n 200000`
  under `LC_ALL=C` (byte count). −1 each per call.
Total ≈ −15 to −18 execs per Bash call (ESTIMATED), ≈ 13-15 execs/s at the current 0.84 Bash/s.

### R3 (P1) — one union `grep` before the per-pattern table walks
`coldcompile-admit.sh:103-104` + `:145-153` (and `qos-rewrite.sh:344-357` on the 6% simple path)
start one `grep -qE` per table row, and on a miss, which is nearly every call, all of them run. Run
one pre-test with every row's ERE (`grep -qE -e "$bats_re" -e "$p1" -e "$p2" -e "$p3"`, the
patterns read in the shell with the same parsing as today). If it exits 1, nothing would have
matched, so exit 0 exactly as now. If it exits 0, run today's first-match walk unchanged. If it
exits 2 (one bad ERE), fall back to today's walk, which tolerates a bad row per row
(`2>/dev/null`). That keeps the outcome equal in every case. −2 to −3 per compound Bash call.

### R4 (P1) — `if` filters on the hooks that act only on a named command (allow/advisory hooks only)
Claude Code skips the process spawn when a tool call does not match `if`
(code.claude.com/docs/en/hooks: "the `if` check would fail and `block-rm.sh` would never run,
avoiding the process spawn overhead"; "When Claude Code can't determine which commands the Bash
input runs, it runs your hook regardless"). `if` exists since CL 2.1.85 (investigations.json [3]).
That predates every binary in the fleet, including 2.1.114.
- `ship-rail-push-allow.sh` → `"if": "Bash(git push origin HEAD:*)"`. It only allows the
  non-compound form (`:62-80`), which the parser always resolves.
- `pr-gate.sh` → `"if": "Bash(gh pr *)"`.
- `relay-verbatim.sh` (PostToolUse) → one entry per rendered command, after the probe in the verify
  recipe confirms the wildcard matches path-prefixed spellings (`~/.claude/bin/claude-accounts --readout`).
Deny guards (`git-worktree-guard`, `keychain-guard`, `validate-bash`) stay unconditional. The docs
call `if` "best-effort" and say not to use it for hard denies. Effect: −3 hook process trees ≈ −6 to
−8 execs per Bash call. Operator-only: a `settings.json` edit through a c10 migration.

### R5 (P1) — statusline: the same display from fewer processes
- Run all statusline git with `GIT_OPTIONAL_LOCKS=0` (`statusline.sh:344`, `:348`). The display is
  unchanged. It stops a display-only reader from rewriting the 1.2 MB index and taking `index.lock`,
  which can make the session's own `git add`/`commit` fail with "index.lock exists". That makes
  session work less contended, not slower.
- Per-session git cache, `/tmp/cc-telemetry/.git-<sid>`, keyed by `$PWD`, the bytes of
  `$(git rev-parse --git-dir)/HEAD`, the `-nt` order of the index file against the cache file, and a
  ≤ 2 s age (builtin `-nt` against a touch-stamp, no `date`). On a hit: 0 git execs. A refresh then
  costs ≈ 3-4 execs and no tree walk. Branch and commit stay exact (HEAD-keyed). Only the `*` dirty
  marker can lag a working-tree edit by ≤ 2 s. That is under the 300 ms-debounced refresh pace of a
  streaming session, and tighter than the docs' own 5 s example.
- Fold `jq` ×3 → 1 (`:77-86`, `:222`, `:237-245`). Read the cached pid with a builtin
  (`IFS= read -r line <file; [[ $line =~ \"pid\":([0-9]+) ]]`), then let the one `jq` print both the
  display fields and the telemetry object. The ts cadence of the telemetry write stays the same:
  cc-wedge-watch, cc-board and 14 other readers depend on it (MEASURED: `grep -rl cc-telemetry` → 17
  files).
- `:343` `basename "$(pwd)"` → `${PWD##*/}`.
- `:299` `grep -q` over 439 KB → test a per-sid marker created right after the append at `:301-303`.
  On a missing marker, fall back to today's grep, so the outcome is equal.
Effect: ≈ 10-11 → ≈ 4 execs per refresh, and the lstat pass on cache hits only. At O5's 1.1/s that
is ≈ −7 execs/s and ≈ −40 ms/s of sys. At the all-streaming bound it is ≈ −50 execs/s and
≈ −0.3 cores (ESTIMATED). Note: `~/.claude/statusline.sh` is a copy, so the change must go through
the installer that writes it.

### R6 (P2) — exec form `args` for every command hook
CC spawns `command` via a shell unless `args` is set ("Exec form (`args` present): … spawns it
directly … There is no shell", hooks docs; CL 2.1.139). If the wrapper shell is a real extra exec,
that is 20 execs and ≈ 20 × 5 ms of start per Bash call, the largest launch-side item. It is
UNMEASURED: bash's one-shot `-c` exec may already replace the wrapper in place, and O5's `sh` (355)
and `bash` (960) counts per 30 s fit neither 1 nor 2 execs per hook. **Blocker:** 2.1.114 predates
2.1.139. HOOK_SURFACE_100P §3f measured that an unknown handler TYPE kills every hook in the file on
114. An unknown KEY is unprobed. Do this only after the probe in the verify recipe, or after 2.1.114
leaves `~/.claude-versions/current`.

### R7 (P2, the long-term "100th percentile") — take the advisory PostToolUse chain out of process-per-hook
On a Bash call, 6 of the 8 PostToolUse hooks are advisory or lead-only (log-bash, relay-verbatim,
teammate-checkpoint counter, memory-index-drain, bash-output-offload, waiting-recycle), plus
cc-permission-beacon clear, mailbox-drain post-tool and post-tool-batch. On 59.6% of calls
(subagents) the advisory ones launch only to exit. Two mechanisms remove the processes outright
rather than moving them:
- **`http` handler type to one per-machine, launchd-kept service.** Claude Code itself POSTs the
  payload: no client process, no `jq` (the service parses once), no launch. On connection failure or
  non-2xx the result is a "non-blocking error" (hooks docs), the same fail-open an advisory hook has
  today on timeout. That answers HOOK_CHAIN_COST §3's objection 2 ("a broker client is still a
  process"). Its objections 3 and 4 (blast radius, daemon rot) remain. Scope it to advisory hooks
  only, never a permission or deny hook: a squatted localhost port could otherwise answer "allow".
  Effect ≈ −8 launches and −20 internal execs per Bash call, ≈ 40% of hook execs (ESTIMATED). Blocker:
  `http` on 2.1.114 is "—" (HOOK_SURFACE_100P §3f:1263), and an unknown type disables the whole file
  on 114. So it needs 2.1.114 retired from the shared settings, or the http entries placed in a
  settings file only ≥2.1.220 binaries read.
- **In-process plugin hook module ("mods").** CC's own process, zero forks
  (investigations.json [3]). Blocked: `tengu_plugin_hooks_modules:false` cached on 4 config dirs, and
  REPORT.md §5 C8 "if the mod dies the hooks lose function rather than falling back".
Prefer `http` on the merits: it is a public settings type and needs no server flag.

## 6. Options considered and rejected (with reasons)

- **Per-machine daemon queried over a unix socket by a thin client** (the brief's suggestion):
  the client is still one process per hook, and the launch is the part it cannot remove.
  HOOK_CHAIN_COST §3 rejected it on yield, blast radius and daemon rot. The `http` type (R7) is the
  variant that removes the client.
- **Single dispatcher per event (`hooks/hook-chain.sh`):** exec mode removes no fork and adds one
  (readjudication §4.1). Source mode broke on members' `exit` and made the largest member 48 ms
  slower (HOOK_CHAIN_COST §3). Serial dispatch lowers occupancy (2.9×) but lengthens the PreToolUse
  critical path from max to sum, which slows the session's tool call: that violates the binding
  constraint without a high-load wall-time A/B showing parity. Its `config/hook-chains.d/` lists also
  drifted 4 members behind settings once (readjudication §1).
- **A dispatcher that exits once for subagent calls and runs members in parallel for leads:** it
  would save ≈ 5 launches on 60% of calls, but members' stdout JSON (relay-verbatim additionalContext,
  bash-output-offload updatedToolOutput) would have to be merged the way CC merges separate hooks,
  which is undocumented. That is an equivalence risk, so it is folded into R7 instead.
- **`async: true`:** moves latency, not work, and has no enforced timeout, so processes pile up
  (DESIGN.md rejected list; plan:157).
- **`if` on deny guards** (git-worktree-guard, keychain-guard, validate-bash): the docs call `if`
  best-effort and say not to use it to enforce a deny.
- **Swap Homebrew jq for `/usr/bin/jq`:** same 1.7.1, ≤ 1 ms per call (MEASURED). Not worth a
  resolution change across 100 hooks.
- **Thinning the statusline telemetry write cadence:** its `ts` is read as a liveness signal by 17
  files (cc-wedge-watch, cc-board, …). It is folded into the one jq (R5), not throttled.
- **Load-threshold early exits, nice/taskpolicy on hooks, fewer sessions:** out by the operator's
  constraint.
- **Re-doing UserPromptSubmit or Stop:** Waves 1, 4 and 4b landed. Wave 4c owns the Stop ledger.

## 7. Open questions

1. Is a command hook 1 or 2 execs (wrapper shell + script)? O5's binary counts fit neither. This
   decides whether R6 is worth 20 execs per Bash call or zero. Recipe: the O5 eslogger capture
   (operator, root), counting `bash -c ~/.claude/hooks/*` wrapper execs against the script execs.
2. validate-bash's current executed-path exec count: not re-censused, because the census harness
   (`scripts/hook-fork-census.sh`) runs the live hook, which appends to `~/.claude/logs`. Recipe: run
   it with `HOME` pointed at a scratch copy.
3. Does 2.1.114 accept an unknown hook KEY (`args`; `if` predates it) without disabling the file?
   And which version is `/opt/homebrew/bin/claude` (2 live processes)?
4. Does one FileChanged event run `file-changed.sh` twice (`settings.json:607` and `:617`)?
5. The fork rate during the load-400-520 period was not measured here: load had fallen to 45-160
   while this ran. At 1,443-1,730 forks/s with load ~50, hooks are ~4-5.5%. Under a gate storm the
   denominator grows and the share falls.
6. Out of axis, for the lead: `hooks/qos-rewrite.sh` (b) already rewrites agent `pytest`,
   `shellcheck`, `npm install` and more to `taskpolicy -c utility` (`config/qos-batch.patterns`). That
   is an existing QoS demotion of session work, a class the operator's constraint now rules out for
   new fixes. Its interaction with the 35-43-minute pytest-xdist gates is not measured here.

## 8. Verify recipes

- **Fork count per hook, any R1-R3 change:** the existing pattern
  `tests/*-forks.bats` + `tests/stop-hook-forks-helpers.bash` (rebuild the pre-change hook from git,
  compare stdout, stderr and state byte for byte on a corpus, then assert the exec count drops). Use
  a corpus drawn from `~/.claude/logs/bash-commands.log` (6,458 real commands; 94% compound) plus
  subagent and lead payloads. Prove each with a mutant (revert → red).
- **python -S parity:** run both scripts with and without `-S` over the same corpus. Diff stdout and
  stderr. Time 11 interleaved runs (`/tmp/d-hooks-pystart.pl` pattern).
- **R3 union pre-test:** fixture with a deliberately invalid ERE row → must fall back and still
  match a later valid row.
- **R4 `if`:** scratch `CLAUDE_CONFIG_DIR` on 2.1.293 and on 2.1.114 with a logging hook carrying
  `if`. (a) It fires on `git push origin HEAD:main`, `cd x && gh pr create …` and the path-prefixed
  `claude-accounts --readout`. (b) It does not fire on `ls`. (c) On 114, a sibling hook without `if`
  still fires (the file is not disabled). Then compare `tool-batch-census` Bash counts against hook
  invocation counts before and after.
- **R5 statusline:** feed recorded payloads (from `/tmp/cc-telemetry/*.json` shapes) to old and new
  scripts in the same cwd. Compare output byte for byte over a sequence: edit a file, `git add`,
  commit, switch branch. Allow the dirty marker to lag ≤ 2 s, with HEAD and branch exact at every
  step. Count execs with a PATH shim. Confirm no index write: index mtime unchanged after 100
  refreshes with `GIT_OPTIONAL_LOCKS=0`.
- **Machine effect:** pid-counter rate (`/tmp/d-hooks-pidrate.pl`) together with the census Bash
  rate over the same 10 min, before and after converge. Expect ≈ −25 to −35 execs/s at 0.84 Bash/s
  from R1-R4 (≈ 1.5-2% of today's forks) and more at the all-streaming statusline bound.

## Commands used (all read-only; scratch scripts under /tmp/d-hooks-*)

`python3 -I -c '<dump hooks>' ~/.claude/settings.json`; `readlink` on each `~/.claude-*/settings.json`;
`tail -c … bash-commands.log | perl …` (rates and compound share); `python3 -I /tmp/d-hooks-tbc.py`
(census); `perl /tmp/d-hooks-sl-rate.pl` (statusline rate); `perl /tmp/d-hooks-pidrate.pl` (fork
rate); `perl /tmp/d-hooks-pystart.pl`, `perl /tmp/d-hooks-jq.pl` (start prices);
`/usr/bin/time -p env GIT_OPTIONAL_LOCKS=0 git status …` ×3; `git ls-files | wc -l`;
`pgrep -x claude` + `ps -o comm= -p`; `uptime` before and after each timed block (load 45-160 during
this run). Sources: code.claude.com/docs/en/statusline, code.claude.com/docs/en/hooks.
