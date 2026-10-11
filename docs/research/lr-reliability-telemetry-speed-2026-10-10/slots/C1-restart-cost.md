# C1 — restart cost: CPU-seconds and kitty-socket RPCs of one session restart

Slot C1-restart-cost · trunk 110ea9a64 · measured 2026-10-11T03:47Z-04:15Z at loadavg 150-296 · strictly passive (no restart, no kitty RPC, no it2).

## Answer first

- One restart costs about **8-20 CPU-s on the recover path** (estimated: client init 3-7, `claude mcp list` probe 2-4, MCP servers 1-2.3, hooks 1-3, RPC chain about 1). **The move path adds about 28 CPU-s more**, and that cost comes from the rail itself: `lr-move-worker`'s prove loop runs `lr_move_verdict` about every 5 s for a measured p50 of 153 s. Each poll forks about 80 jq/basename subshells over the 35 registry rows (`lr-lib.sh:284-293`, called twice per poll).
- **Transcript replay is not a cost driver.** Measured spawn-to-composer-painted is 4-10 s and does not depend on transcript size (r = -0.13, n = 25). A JSON-parse proxy costs 2.3 ms/MB, so the 241 MB outlier comes to 0.56 s.
- **The biggest avoidable cost in the session itself is a second Claude client.** `session-start.sh` runs `claude mcp list` 0.67 times per session start (340 probes for 509 starts in 6.93 d, measured). Each probe boots a full client and spawns every MCP server, and 40% of probes never log a result.
- **Kitty RPCs:** about 10-14 per recycle (estimated from call sites; nothing logs them), plus 0-26 composer reads from `lr-fire-resume`. Two things inflate this. Every `it2 session send` makes two RPCs (`kitty @ ls` plus `send-text`). Every 24-line read fetches the whole 2000-line scrollback (`get-text --extent all`).
- **The box is CPU-saturated, mostly in the kernel:** `top -l 2`: 44.13% user, 54.80% sys, 1.6% idle at load 295.9. So the cost of each fork is a real cost. The expect layer stays resident by design, but it is cheap (it is ruled out below).

## Per-component table (one restart)

M = measured (command named in the receipts), E = estimated (method named).

| Component | CPU-s per restart | M/E | kitty RPCs | Candidate fix | Expected saving |
|---|---|---|---|---|---|
| Claude Code client init + first render | 2.3-5.2 for a bare `claude -p` (no hooks or MCP). Up to 7.2 for an interactive session 42 s after launch (includes the start of the first turn) | E: bounded from measured TIME of young processes (pids 36581/36584: 4.8-5.2 s at 245 s age, current rate 0.012/s; pid 46978: 7.22 s at 42 s) | 0 | none in the repo | — |
| Transcript replay (`--resume`) | 0.01 at p50 (3.2 MB), 0.11 at 45 MB, 0.56 at the 241 MB maximum | E: Python `json.loads` proxy (measured) | 0 | none needed (ruled out) | — |
| MCP stdio servers | 1.04 per ms365 node (n = 31, flat with age). In `~/Development/personal`, add 0.9 for the `npx` wrapper and about 0.35 for each uvx+python mac-messages pair | M | 0 | `~/Development/personal/.mcp.json`: call the ms365 binary directly instead of `npx -y` | about 0.9 CPU-s and 15-46 MB per session in that cwd |
| SessionStart hooks: 10 registrations = 9 direct + `session-start-dispatch.sh` fanning out to 10 more, so 19 scripts | not measured; estimated 1-3 | E: fork count × 5-10 ms (measured jq at 6 ms CPU) | 0 | add per-child timing to `session-start-dispatch.sh` | unknown until measured |
| └ `claude mcp list` probe (`session-start.sh:375-392`) | 0.67 probes per start × 3-6 = 2-4 expected | count M, CPU per probe E (one client init plus one ms365 spawn) | 0 | **C1-2** | about 66-90% fewer probes |
| lead-crash-watchdog daemon (one per session) | about 3.3 average over its lifetime (120 CPU-s across 36 daemons) | M | 0 | none (no leak; mapped 1:1 to live leads) | — |
| statusline (`~/.claude/statusline.sh`, 598 lines, about 6 jq + 2 git + a ps walk per refresh) | not measured | — | 0 | — | — |
| expect layer (`lr-fire-resume.sh:985-1574`) | 0.08-4.14 over its lifetime, 11.2 total across 11 resident | M | 0 | none (ruled out) | — |
| lr-fire-resume submit probe: one bash + `/usr/bin/python3` tail read per 1 s turn | 0.1-0.4 (p50 about 12 turns) | E | 0 | — | — |
| lr-fire-resume composer looks (`lr_screen`, `:848`/`:875`) | 0.05-0.1 per look on the client side (it2 → cc-in-kitty `ps -Ao` 0.04 s sys → it2-kitty → timeout → kitty) | E | 0-26 × `get-text --extent all`; at least 18 measured over 42 runs | **C1-3** | about 40× less payload per read |
| `handoff-fire.sh --recycle` (precheck, pane proof, composer gate, focus, `/exit` typing and read-back, vanish check every 15 s) | not measured | — | about 10-14 (E, from call sites), plus 1 per 15 s of exit wait | **C1-4** | 4-6 fewer `kitty @ ls` per recycle |
| **move path only:** `lr-move-worker.sh` prove loop (`:177-195`) | about 0.95 per poll × about 30 polls (p50 153 s ÷ about 5 s cadence) ≈ 28 | E from measured primitives | 0 | **C1-1** | about 0.55 CPU-s and 1.4 s of wall time per poll, so about 16 CPU-s per moved session |

---

## C1-1 · The move prove loop forks about 80 subshells per poll to scan 35 registry rows

- **Symptom.** After a move, `lr-move-worker` polls `lr_move_verdict` until the move is proven. Each poll calls `lr_registry_live_rows` twice: once through `lr_move_holders` (`lr-move-lib.sh:58`) and once directly (`lr-move-lib.sh:95`). It also takes one full `ps -axo pid=,ppid=,command=` table (`lr_resume_procs`, `lr-lib.sh:550`). `lr_registry_live_rows` runs `$(basename "$f")` and `$(jq …)` for every file in `~/.claude/cc-registry` (`lr-lib.sh:284-287`), plus 4 more jq calls for each matching row (`:288-293`). The same function also runs per parked record in the poller (`lr-reset-poller.sh:2159, 2171, 2203 (via _in_cfg :321), 2233`). That is the "bash/basename subshell about once a second" signature from the 03:21-03:41Z LIVE CASE tick.
- **Measured frequency.**
  - Move prove phase across all 5 move batches: n = 18, p50 153 s, p90 327 s, max 337 s (Python over `~/.reso/limit-recover/move/*/*.events.jsonl`, `actuated` → `result`).
  - Registry size: 35 rows (`ls ~/.claude/cc-registry/*.json | wc -l`).
  - One emulated scan of `lr-lib.sh:284-287` over those 35 rows: **0.72-0.79 s wall, 0.28-0.29 CPU-s**. A single jq call over the same rows: **0.01 s wall, about 0 CPU-s** (`/usr/bin/time -p /tmp/c1_regscan.sh old|new`, load about 290).
  - `ps -axo pid=,ppid=,command=`: 0.62-0.71 s wall, 0.21-0.22 CPU-s.
  - Per-poll estimate: about 0.95 CPU-s and about 3 s of wall time, so about 28 CPU-s per moved session at p50.
- **Root cause.** `scripts/limit-recover/lr-lib.sh:284-293` forks a subshell plus an exec per registry file per call. `scripts/limit-recover/lr-move-lib.sh:58` and `:95` scan the registry twice per poll when once is enough.
- **Fix.**
  1. Replace the loop in `lr_registry_live_rows` with one `jq -r --arg s "$sid" 'select((.session_id // .sessionId) == $s) | [(.paneUUID // (input_filename|ltrimstr(…)|rtrimstr(".json"))), .pid, (.account // "-"), .cwd] | @tsv' "$regdir"/*.json`. Then run `kill -0` on each returned pid in bash.
  2. Keep the per-file loop only as a fallback when the single jq exits non-zero, because one malformed row aborts a multi-file jq.
  3. In `lr_move_verdict`, call `lr_registry_live_rows` once and derive the holders from those rows plus `lr_resume_procs`.
- **Bats test.** Put a counting `jq` shim and a counting `basename` shim first on PATH, with a 35-row fixture registry (one matching row, one dead-pid row, one dotfile, one malformed row). Assert byte-identical output from the old and new functions. Assert jq invocations ≤ 2 on the clean fixture (fallback only on the malformed one) and basename invocations = 0. Assert `lr_move_verdict` calls `lr_registry_live_rows` once (spy counter).
- **Expected saving.** About 0.55 CPU-s and 1.4 s of wall time per poll, so about 16 CPU-s per moved session (E). The poller saves about 0.75 s of wall time per call, at up to 4 calls per parked record. That alone does **not** explain the 48 s/record in the LIVE CASE; it is one contributor.
- **Fix size:** S. **Conviction:** 75. The root cause and the cost per call are measured. The per-poll total and the poll count are estimates.
- **Receipt.** `lr-lib.sh:284-293`, `lr-move-lib.sh:58,95`, `lr-move-worker.sh:177-195`. Command `/usr/bin/time -p /tmp/c1_regscan.sh old` gave `real 0.79 user 0.11 sys 0.18`; with `new` it gave `real 0.01 user 0.00 sys 0.00`.
- **Alternatives considered.** Slowing the prove-loop cadence: rejected as the first fix, because it lengthens time-to-verdict and a cheaper poll gets the same result. Caching the registry across polls: rejected, because the poll exists to see fresh rows.

## C1-2 · Every second session start runs a second Claude client (`claude mcp list`) to refresh a 300 s cache

- **Symptom.**
  - `session-start.sh` is a dispatched SessionStart child of `session-start-dispatch.sh`. It serves the MCP status from `$CLAUDE_CONFIG_DIR/.mcp-probe-cache`.
  - If the cache is older than `MCP_CACHE_TTL=300` (`session-start.sh:142`), it spawns a background `--refresh-mcp-cache` (`:385`, `:180-200`). If the cache is missing, not `ok`, or older than 86400 s, it probes inline (`:388-391`).
  - Either way the probe is `claude mcp list` (`:245-248` region). That is a full Node client boot, and it health-checks every configured MCP server by spawning the stdio servers.
- **Measured frequency.**
  - `~/.claude/logs/sessions.log`, 2026-10-04 to 2026-10-11 (6.93 d): 509 `Session started` lines and **340 `MCP probe binary` lines (0.67 per start, 49/day)**.
  - 203 of those probes logged `MCP Status` within 30 s (wall p50 7 s, p90 9 s, max 28 s). **137 (40%) logged nothing.**
  - Replaying the same start times against a single shared cache: TTL 300 gives 250 probes, TTL 3600 gives 85, TTL 21600 gives 24.
- **Root cause.** `~/.claude/hooks/session-start.sh:142` (TTL 300 s) together with `:385` (refresh on every start past the TTL). The account caches are only minutes to hours old (`stat` on `.mcp-probe-cache`: quaternary 22:45, next 21:46, tertiary 19:29 local), so starts keep paying for refreshes. CPU per probe: E 3-6 s (one client init from C1's table plus about 1 s per spawned ms365 server).
- **Fix.**
  1. Raise `CC_MCP_CACHE_TTL` to 21600.
  2. In `_mcp_spawn_refresh`, skip the refresh when the 1-minute load per core is above 2 (the same `sysctl -n vm.loadavg`/`hw.ncpu` read `hf_load_per_core` uses). The served answer stays the cached one, and its age is already reported in `MCP_AGE`.
- **Bats test.** Use a stub `claude` that appends to a counter file, plus a cache file aged 400 s. With defaults, assert 0 refresh spawns. With the cache aged 30000 s, assert 1. With a stub load of 50/10, assert 0 even when the cache is past the TTL.
- **Expected saving.** About 2-4 CPU-s per session start (E). Probe count drops from 340 to about 33-116 per week (66-90%, scaled from the simulation by the measured 340/250 multi-account factor).
- **Fix size:** S. **Conviction:** 65. The count is measured. The CPU per probe is not, because no probe was running during the window.
- **Receipt.** `awk '/^\[2026-10-(0[4-9]|1[01])/' ~/.claude/logs/sessions.log`, then: `grep -c 'Session started'` gives 509, `grep -c 'MCP probe binary'` gives 340, `grep -c 'MCP Status (attempt'` gives 200. `session-start.sh:375-392` is quoted in this slot's tool log.
- **Alternatives considered.** Deleting the probe: rejected, because its `additionalContext` warning on degraded MCP is a feature. Moving the probe to launchd: rejected, because a fixed schedule across 5 accounts gives more probes than TTL 21600 does.

## C1-3 · A 24-line composer read pulls the whole 2000-line scrollback over the kitty socket

- **Symptom.**
  - `lr-fire-resume.sh:848` reads the composer with `it2 session read -n 24`, and handoff-fire's `composer_content` does the same (`handoff-fire.sh:4055-4056`, with `--ansi` first and a plain fallback, so up to 2 RPCs).
  - `bin/it2-kitty:1483-1486` turns any `-n N` into `kitty @ get-text --extent all [--ansi] | tail -n N`.
  - `scrollback_lines 2000` (`~/.config/kitty/kitty.conf`), so every look makes kitty serialize up to 2000+rows lines on its UI thread just to return 24.
- **Measured frequency.** From `bundle-*/events.jsonl` since 2026-10-03: 42 lr-fire-resume spawns, **13 `SUBMIT-RECR`** (each preceded by a read that returned DRAFT-MINE), 5 `SUBMIT-UNMEASURED` runs (at least one read each, and more by design every 15 s up to 180 s), and 7 `READY-NOT-SEEN`. That gives a lower bound of 18 whole-scrollback reads. The exact count is not measurable because the oracle notes only once per run (`lr-fire-resume.sh:1490-1494`). Recycles in the same window: 51 `recycle-engaged` events, each with at least one composer-gate read.
- **Root cause.** `bin/it2-kitty:1483-1486` uses `--extent all` for every `-n`, including N values that fit on the visible screen. The caller asks for 24 lines at `scripts/limit-recover/lr-fire-resume.sh:848`.
- **Fix.**
  1. Add `--screen` to `it2 session read`, mapping to `get-text --extent screen`.
  2. Use it in the two composer oracles (`lr-fire-resume.sh:848`, `handoff-fire.sh:4055-4056`). The composer box is always on the visible screen. The existing 200-line fallbacks (`:875`, `:4142`) keep `--extent all` for a scrolled box.
- **Bats test.** Use a stub `kitty` that records its argv. Assert that `session read -s 7 -n 24 --screen` emits `get-text --match id:7 --extent screen`, and that `session read -s 7 -n 500` still emits `--extent all`. Re-run the existing oracle fixtures (`tests/lr-fire-resume-*.bats`) unchanged.
- **Expected saving.** Payload per read drops from up to about 2050 lines to the screen height, about 50 lines (E: about 40×). That is fewer bytes through the kitty main loop, which the recycle-failures-kitty F1 verdict named as the transport that falls behind under load.
- **Fix size:** S. **Conviction:** 50. The code path is certain. The kitty-side CPU of `--extent all` was not measured, because this brief forbids RPCs.
- **Receipt.** `bin/it2-kitty:1483-1486` (`kt get-text --match "id:$SESSION" --extent all`) and `lr-fire-resume.sh:848` (`session read -s "$LR_PANE" -n "${LR_SCREEN_LINES:-24}"`). `grep scrollback_lines ~/.config/kitty/kitty.conf` gives `scrollback_lines 2000`.

## C1-4 · Each `it2 session send` costs two RPCs (`kitty @ ls` plus `send-text`), and recycles type in 4-6 sends

- **Symptom.**
  - `bin/it2-kitty` send (`:1311-1318`) calls `prove_target` (`:527-552`), which calls `pane_exists`, which runs `kt ls --match id:$1` (`:432`), before `kt send-text`.
  - The recycle's `/exit` path makes 5 RPCs: `hf_exit_readback` (`handoff-fire.sh:3319` `/exit`, read-back, `:3328` CR).
  - `_it2_type_line` (`:3825-3848`: ^U, text, verify read, CR) makes 7. The Escape and bg-work sends (`:10251, 10289, 10597, 10654, 10692`) make 2 each.
- **Measured frequency.** Not measurable: no log records kitty RPCs. Static estimate is about 10-14 RPCs per happy-path recycle, of which about 4-6 are `prove_target` `ls` calls. The prior count of about 10 (lr100p D1 critique, line 56) predates the read-back and focus gates. Recycles: 51 in 6.9 d (`handoffs.jsonl` `recycle-engaged` since 2026-10-04), with firer-to-engaged p50 111 s and p90 178 s.
- **Root cause.** `bin/it2-kitty:1317` runs `prove_target` again for every send, even when the same caller proved the same window id moments earlier (`pane_proof`, `handoff-fire.sh:3566`).
- **Fix.**
  1. Have the caller export `CC_TERM_PROVEN=<id>:<kitty_pid>:<epoch>` after its own `kitty @ ls` proof.
  2. `prove_target` skips `pane_exists` when id and kitty pid match and the proof is less than 10 s old.
  3. Keep the kitty-pid socket check, which costs no RPC.
- **Bats test.** Use a stub `kitty` that counts `ls` calls. Three sends with a fresh `CC_TERM_PROVEN` should produce 0 `ls` calls; with a stale (11 s) or mismatched proof, 3. The existing `send-text exits 0 for a nonexistent id` refusal test must still pass when no proof is exported.
- **Expected saving.** 4-6 RPCs per recycle (E), about 0.036-0.1 s each when the socket is healthy, and up to the 10 s `HF_TIMEOUT_S` each when it is not.
- **Fix size:** M (it touches a safety gate). **Conviction:** 45. The 10 s window reopens a small gap: a pane closed within 10 s of its proof would get a send reported as success.
- **Receipt.** `bin/it2-kitty:432, 527-552, 1311-1318`; `handoff-fire.sh:3319-3333, 3825-3873`.

---

## Ruled out

- **Transcript replay as the boot driver.**
  - Recovered sessions since 2026-10-03 (n = 44): transcript p50 3.2 MB, p90 5.7 MB, max 45.3 MB. The all-time maximum, 241.4 MB (`4101dbdf`, recovered 2026-09-14), is not current.
  - Spawn-to-`composer-painted` is p50 6 s, p90 8 s, max 10 s (n = 25), and the 45.3 MB transcript painted in 5 s; Pearson r(size, latency) = -0.13.
  - The parse proxy: `python3 -I /tmp/c1_parse.py` takes 0.11 s on 45.3 MB and 0.56 s on 241.4 MB (4139 lines, so bytes sit in a few huge attachment lines).
- **The expect layer as a CPU cost.** It *is* resident for the whole session: `interact` at `lr-fire-resume.sh:1573`, the bash parent waits (`:777-794`, `:1574`), then falls through to `exec zsh` (`:1618`). There are 11 resident expects now (10 lr-fire-resume, 1 reso-resume-one), with 30 MB RSS in total. CPU is 0.08-4.14 s each over 25 min to 2.3 days, at most 0.09 CPU-s/h.
- **lead-crash-watchdog leaking per restart.** Mapping each resident watchdog to its lead through `lead-crash-watchdog.log` (`spawned watchdog daemon pid=…`) gave 31 live leads (`kill -0`; one of them is `claude bg-spare` 10156). One lead, 4039, was dead and its watchdog was still classifying it (log line `death class=RECYCLE`, 23:04 local). The other grep hits were bats processes whose pids had been reused, not watchdogs.
- **MCP stdio servers as a large cost.** ms365 node uses 1.04 CPU-s each and does not grow with age (1.12 s at 5 min, 1.00 s at 2 days); 31 instances total 615 MB RSS and 32.3 CPU-s. The `npx` and `uvx` extras appear only in cwd `~/Development/personal` (project `.mcp.json`).
- **`lr-move-worker.sh` as a kitty RPC source.** It makes 0 direct RPCs; it only passes `SOCK` through (`:158`). Its cost is ps/jq (C1-1).
- **The submit probe reading whole transcripts.** `lr-submit-probe.sh` seeks to a bounded tail window (`seek(0, SEEK_END)` then `size - n`).
- **The ps ancestry walk in handoff-fire's watcher.** `pin_term_verdict_for_watcher` (`handoff-fire.sh:2055-2068`) pins `CC_TERM=kitty` once. After that, `cc-in-kitty` exits before its `ps -Ao` walk (`bin/cc-in-kitty`, at the `CC_TERM` check). lr-fire-resume does not pin it, but that costs at most 26 × 0.04 s sys.

## Uncertain

- **SessionStart hook CPU** is not measurable: there is no hook-timing log under `~/.claude/logs`, and the only debug log, `~/.claude-quaternary/debug/*.txt`, dates from 2026-09-05. Running hooks to measure them was forbidden.
- **Client init** is a bound, not a measurement. A 240 s passive watch (`/tmp/c1_watch.sh`, 2 s sampling) saw 0 new `claude` processes, so no `--resume` boot was caught.
- **RPCs per recycle** are a static estimate. A one-line `CC_TERM_KITTY_RPC_LOG` append in `kt()` (`bin/it2-kitty:207`) would make the count measurable.
- **The 0.95 CPU-s per prove poll** is assembled from measured parts (registry scan 0.28, `ps -axo command` 0.21, `ps -Ao` 0.04, jq 6 ms each). The whole poll was not timed, because sourcing the driver library was forbidden.
- **The box context.** Long-idle sessions burn a median 0.0086 CPU-s/s each (n = 18 sessions older than 6 h, two-point `ps` sample 120 s apart), which is about 0.25 cores across 29 sessions. `claude bg-spare` pid 10156 has used 183 CPU-min in 9.35 days. Neither cost is per restart.
- **Cross-slot pointer (A3).** The lead-crash-watchdog registrations show live holders for the "no run" LIVE CASE sessions: `6defb493` is pid 19890 (expect from `reso-resume-one next`, alive 1 d 22 h), `516b9da9` is pid 1207, and `5507881f` is pid 95136.
