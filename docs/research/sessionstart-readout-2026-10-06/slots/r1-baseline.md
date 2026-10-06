# R1 — SessionStart board latency baseline and token cost (measured 2026-10-06, 06:22–06:40Z)

Harness: `bash /tmp/ssr-research/r1-harness.sh <N> <hookA> [hookB]` (two hooks → runs interleaved A,B,A,B; per-arm interpreter via `R1_BASH_A`/`R1_BASH_B`; fresh/stale board via `R1_BOARD_MODE=fresh|stale`; raw samples in `/tmp/ssr-research/r1-raw-<label>.csv`; first warm-up stdout in `r1-out-<label>.txt` as the receipt of which path ran). Batch drivers: `/tmp/ssr-research/r1-batches.sh` (log `r1-batches.log`), batch 6 log `r1-batch6.log`.

Method: one python3 process times `subprocess.run([interp, hook], stdin=payload, stdout=/dev/null)` with `time.perf_counter_ns` (fork+exec+wait); 3 untimed warm-ups per arm; nearest-rank percentiles. Payload `{"source":"startup","cwd":"/Users/chrisren/Development/.worktrees/sessionstart-readout","transcript_path":""}`. Every run: `DL_DIR=/tmp/ssr-research/dl-sandbox` (copy of the real `.state/`, already latched for today → the common already-latched path), `CC_ACCOUNTS_BOARD=/tmp/ssr-research/r1-board.txt` (copy of the live board, 2194–2203 bytes across batches), `CLAUDE_CODE_ENTRYPOINT=cli` (as a live interactive session has it, so `dl_banner()` walks its whole gate), cwd = the worktree, inherited `LANG=en_CA.UTF-8`. Machine: 10 cores, macOS 15.7.9, shared with other research slots — load reported, not hidden.

## Results (all measured, ms)

| # | arm | interpreter | n | p50 | p90 | p99 | max | load 1/5/15 start → end |
|---|---|---|---|---|---|---|---|---|
| 1 | accounts-board.sh, fresh board | /bin/bash 3.2.57 | 300 | **902.2** | 984.8 | **1889.2** | 3725.1 | 32.93 70.06 61.17 → 34.69 44.46 51.48 |
| 1 | accounts-board.sh, fresh board (interleaved) | /opt/homebrew/bin/bash 5.3.15 (PATH bash) | 300 | **61.5** | 81.6 | **124.2** | 143.1 | same batch |
| 2 | accounts-board.sh, stale board (mtime −10 min) | /bin/bash 3.2.57 | 100 | 892.7 | 1132.4 | 1499.9 | 1715.9 | 34.69 44.46 51.48 → 22.38 37.00 47.73 |
| 2 | accounts-board.sh, stale board (interleaved) | bash 5.3.15 | 100 | 69.4 | 83.4 | 132.9 | 151.6 | same batch |
| 3 | session-start-dispatch.sh, `CC_SSD_CHILDREN=accounts-board.sh` (child via `env bash` → 5.3.15) | /bin/bash 3.2.57 (its shebang) | 300 | **89.3** | 222.2 | **411.0** | 506.6 | 22.38 37.00 47.73 → 46.42 40.50 48.15 |
| 3 | bare accounts-board.sh (interleaved control) | bash 5.3.15 | 300 | **67.5** | 159.7 | **279.1** | 308.7 | same batch |
| 4 | activation-watch.sh | /bin/bash 3.2.57 (shebang) | 50 | 168.5 | 245.6 | 294.4 | 294.4 | 46.42 40.50 48.15 → 45.71 40.69 48.08 |
| 4 | escalation-watch.sh (interleaved) | /bin/bash 3.2.57 (shebang) | 50 | 105.4 | 163.8 | 296.7 | 296.7 | same batch |
| 4 | frontier-status.sh | bash 5.3.15 (`env bash` shebang) | 50 | 42.6 | 82.8 | 146.6 | 146.6 | 45.71 40.69 48.08 → 44.06 40.43 47.95 |
| 4 | config-mirror-assert.sh, `CLAUDE_CONFIG_DIR` unset (exit-0 path only) | /bin/bash 3.2.57 | 50 | 3.9 | 5.8 | 97.5 | 97.5 | same batch |
| 5 | dispatch over the 5 read-only children (activation, escalation, board, config-mirror[unset], frontier) | /bin/bash 3.2.57 | 50 | 178.6 | 227.3 | 273.4 | 273.4 | 44.06 40.43 47.95 → 43.03 40.32 47.82 |
| 6a | accounts-board.sh original | /bin/bash 3.2.57 | 100 | 1159.4 | 2247.6 | 3867.4 | 6522.3 | 44.58 40.36 47.27 → 47.24 47.61 49.41 |
| 6a | /tmp variant: line 164 → `case` glob (interleaved) | /bin/bash 3.2.57 | 100 | **91.4** | 152.6 | 237.3 | 324.9 | same batch |
| 6b | accounts-board.sh original | bash 5.3.15 | 150 | 121.5 | 159.9 | 207.9 | 216.6 | 47.24 47.61 49.41 → 69.24 52.72 51.18 |
| 6b | /tmp variant (interleaved) | bash 5.3.15 | 150 | 116.5 | 147.1 | 198.5 | 203.4 | same batch |

Floor controls (batch of 20, load ~70): `#!/bin/bash exit 0` p50 2.9 ms; one `jq -nc` p50 9.2 ms.

Absolute numbers drift with load (bash-5 board p50 61.5 ms in batch 1 vs 121.5 ms in batch 6b at higher load); compare only arms in the same interleaved batch.

## (b) Which bash Claude Code actually uses — measured

- All 16 live `claude` processes (`pgrep -x claude`): their `ps eww` `PATH` resolves `bash` to `/opt/homebrew/bin/bash` (16/16). Command: `ps eww -o command= -p <pid>` → `PATH=` → `PATH="$pp" /bin/bash -c 'command -v bash'`; output `16 /opt/homebrew/bin/bash`.
- The dispatcher's own shebang is `#!/bin/bash` (hooks/session-start-dispatch.sh:1), so the dispatcher always runs 3.2. It execs each child by path (session-start-dispatch.sh:52), so `accounts-board.sh`'s `#!/usr/bin/env bash` (hooks/accounts-board.sh:1) resolves through the inherited PATH. Probe (`/tmp/ssr-research/probe-hooks/ver.sh`, an `env bash` child printing `$BASH_VERSION`, run through the real dispatcher): with a live claude PATH → `5.3.15(1)-release BASH=/opt/homebrew/bin/bash`; with `PATH=/usr/bin:/bin` → `3.2.57(1)-release BASH=/bin/bash`.
- Registration: `~/.claude/settings.json:1213-1217` registers only `~/.claude/hooks/session-start-dispatch.sh` (timeout 12, no `async`). The board hook is not registered on its own anymore.
- So in production the board runs under **bash 5.3.15 (p50 61.5 / p99 124.2 ms)**. "/bin/bash 3.2 as the harness runs it" (plan row R1) describes the dispatcher, not the board child. The board runs on 3.2 only when a session's PATH lacks /opt/homebrew/bin, or when something calls `/bin/bash hooks/accounts-board.sh` directly. Every `#!/bin/bash` child (all except frontier-status and the board) runs on 3.2 regardless of PATH.
- Locale also varies across live processes: 11/16 carry `LC_ALL=C`, 3 only `LANG=en_CA.UTF-8`, 4 `LC_CTYPE=C.UTF-8` (same `ps eww` loop). This matters only on 3.2 (next section).

## Why the board costs ~0.9 s on bash 3.2 — measured root cause

- One line: `if [ -z "${body//[[:space:]]/}" ]` (hooks/accounts-board.sh:164), a whitespace-strip used only as an emptiness test over the 2,088-char ANSI-laden board.
- Isolated cost (`/usr/bin/time -p /bin/bash -c 'x="${body//[[:space:]]/}"'`, one run each). The cost grows superlinearly with size:

| body | bash 3.2, UTF-8 locale | bash 3.2, `LC_ALL=C` | bash 3.2, `LC_CTYPE=C.UTF-8` | bash 5.3 |
|---|---|---|---|---|
| 1× board (2,088 chars) | 0.87–0.94 s | 0.16 s | 0.86 s | 0.01 s |
| 2× (4,176) | 6.47 s | 0.84 s | 6.74 s | — |
| 4× (8,352) | 43.59 s | — | — | 0.05 s |

- A board about twice today's size would take ~6.5 s on 3.2, past the old 5 s board timeout and close to the dispatcher's 9 s per-child bound (session-start-dispatch.sh:37). The plan's wording changes (age, load, "about 1% left" caveats) all add bytes, so this line is the hidden coupling between "say more" and "no slower at p99" on 3.2. On 5.3 it does not matter: 4× is 0.05 s.
- Behaviour-equivalent O(n) replacement, measured on a /tmp copy (`/tmp/ssr-research/variant/accounts-board.sh`, line 164 → `if case "$body" in *[![:space:]]*) false ;; *) true ;; esac; then`):
  - same stdout as the original on the live board (`diff` → `SAME-OUTPUT`);
  - a whitespace-only board still takes the EMPTY branch;
  - 3.2 p50 **1159.4 → 91.4 ms**, p99 3867.4 → 237.3 ms (batch 6a, interleaved);
  - 5.3 p50 121.5 → 116.5 ms, p99 207.9 → 198.5 ms (batch 6b): no regression.
  - Alone, the `case` test costs 0.00 s at 1× and at 4× under 3.2.

## (c) Dispatch overhead — measured (batch 3, interleaved, n=300 each)

- Dispatch with the board child minus the bare board under bash 5.3: **p50 +21.8 ms** (89.3 − 67.5), p90 +62.5, **p99 +131.9 ms** (411.0 − 279.1), max +197.9.
- The tail is load-inflated: 1-min load rose 22 → 46 within the batch. The dispatcher's own work per run: a 3.2 spawn, `mktemp -d`, `cat` of the payload, one watchdog subshell plus `sleep`, `kill`, a `jq` merge, and `rm -rf` (session-start-dispatch.sh:42-88).
- The receipt `r1-out-dispatch-board.txt` (2,799 bytes) is the board's systemMessage passed through unchanged.
- The full nine-child chain was **not** measured (four children write state; see (d)). Its wall time is max(children) + overhead. The read-only subset gives a floor: p50 178.6 / p99 273.4 ms (batch 5), set by activation-watch (p50 168.5).

## (d) Dispatch children — read-only or state-writing

| child | class | evidence | timed? |
|---|---|---|---|
| accounts-board.sh | read-only except the `banner-latch` write (accounts-board.sh:122), which is sandboxed by `DL_DIR` | `producer_state` is `launchctl list` + `ps` reads only (:66-82) | yes (rows 1-3, 6) |
| activation-watch.sh | read-only on the default `watch` path | `watch()` :456-480 calls parity/inert/envarm axes: `git rev-parse` / `cat-file` / `rev-list` (:345-363), `launchctl` reads; the only writes sit in `selftest()` :488+ (mktemp under $TMPDIR, `--selftest` only) | yes, 50 |
| escalation-watch.sh | read-only | `watch()` reads the idl.jsonl tail, `perl -e 1`, `date` (escalation-watch.sh, `watch`/`sweep_liveness`/`scan_health`); writes only in `--selftest` | yes, 50 |
| frontier-status.sh | read-only | sed/grep/awk of model-config.yaml and the cwd ledger, then echo (frontier-status.sh:13-40) | yes, 50 |
| config-mirror-assert.sh | **writes** when `CLAUDE_CONFIG_DIR` names an account dir: `_cc_sync_account` (config-mirror-assert.sh:17) does `mkdir -p` / `ln -sfn` / `rm -f` (`~/.claude/lib/config-mirror.zsh:118,205,177`) | read-only only on the account-1 path (unset or `~/.claude`), which exits immediately | **only the exit-0 path** (50); the account-dir path is unmeasured |
| session-start.sh | **writes** | `>> "$LOG_FILE"` (session-start.sh:18,34), `> "$LAST_PRUNE_FILE"` (:45), plus prune and an MCP probe | no |
| setup-plan-symlinks.sh | **writes** | `ln -sfn` into cwd `.claude-plans` (setup-plan-symlinks.sh:24) | no |
| setup-task-symlinks.sh | **writes** | `ln -sfn` (:78,141,146), `.active-list-id` (:142,147), index `mv` | no |
| session-index-start.sh | **writes** | `log_idl` on EXIT to idl.jsonl (session-index-start.sh:17), sqlite `session_index_upsert_with_fts` (:85) | no |

`origin-identity.sh` (sourced by the board): `oi_origin_class` reads only. Its one writer, `write_fired_cwd_index` (lib/origin-identity.sh:79), is never called inside the lib.

## (e) Token cost and channel

- **Bytes**, from `r1-out-*.txt` with ANSI counted by the regex `\x1b\[[0-9;]*[A-Za-z]`:

| board path | systemMessage bytes | ANSI bytes | ANSI share | est. tokens (bytes/3.5) | est. tokens, ANSI stripped | hook stdout (JSON-escaped) |
|---|---|---|---|---|---|---|
| fresh | 2,193–2,199 (2,089 chars, 16 lines) | 1,306–1,308 (114 sequences) | **59.5%** | **~628** | ~255 | 2,799–2,805 |
| stale | 2,490 | 1,306 | 52.4% | ~711 | ~338 | — |

- **Live record:** the lead session's transcript (`~/.claude/projects/-Users-chrisren-Development--worktrees-sessionstart-readout/e6c3f109-….jsonl`) holds one `attachment` of `type: hook_system_message`, `hookName: SessionStart:startup`, at `2026-10-06T06:12:51.872Z`. It is 2,603 bytes / 1,175 plain chars: the board plus config-mirror-assert's FORKED-entries line, merged by the dispatcher.
- **Model visibility: the current binary sends it 0 tokens.** In `~/.claude-284/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (the binary the live `bg-pty-host` daemon runs), `grep -a -o 'hook_system_message:[^,]{0,40}'` → `hook_system_message:()=>[]`, exactly once. An empty content list means the attachment contributes no message to the API request. In the same binary `hook_additional_context:(e)=>{if(e.content.length===0)return[]…` builds content.
- This repeats the binary corroboration in docs/research/final-response-shaping-2026-08-08.md:59 (`hook_system_message:()=>[]`) and the corpus count in docs/research/token-efficiency-2026-09-23/measure/hooks.md:64 ("display only: 3,015 items, 1.62M chars, $0").
- The ~628-token figure is therefore what the board *would* cost if moved to `additionalContext`, not a current cost.
- **What R5b proves, and what it does not.** `docs/research/R5b-sessionstart-render-probe.py` (32 lines):
  - It runs `~/.claude-220` claude under a pty for 14 s and greps the **pty bytes** for three markers plus the alt-screen switch.
  - It proves **terminal rendering** only: top-level `systemMessage` rendered, the nested form did not, `additionalContext` did not appear on screen.
  - It does not inspect the transcript or the API request. The "transcript inspected" / "enters model context ✅/❌" columns come from DESK_ROUTER_AND_STARTUP_V1.md §2.7 (:208-216), not from this script.
  - It was run against v2.2.0, not today's binary. The model-invisibility claim rests on the binary mapping above, which I re-checked on the current binary, not on R5b.
  - It also relies on the dispatch registration staying sync: session-start-dispatch.sh:14-15 says an async hook's systemMessage reaches the model.

## Deviations and caveats

- Two unsandboxed runs: the equivalence `diff` ran the original under 5.3 and the variant under 3.2 against the real board and the real `DL_DIR`. The real `banner-latch` was already latched for today and stayed unchanged (mtime `Oct 6 00:58:03`, content `2026-10-06 efc64441e27b8e54`, checked with `stat` after the runs). No other state was touched.
- The harness exec's the interpreter directly. Claude Code adds its own command-spawn wrapper (not measured here; estimated at about one shell spawn, ~3 ms from the noop floor).
- The first-of-day latch path (write latch + `cat` banner) was not timed; it fires once a day.
- Load was 22–70 (1-min) on 10 cores throughout. p99/max mostly reflect the scheduler. Use the interleaved pairs for deltas.
