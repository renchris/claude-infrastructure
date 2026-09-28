# TrueMemory: operations, robustness and engineering practice

Axis: tier_switch/*, model_server.py, model_client.py, instrumentation/*, telemetry.py, tier_config.py,
mps_utils.py, docs/resource-budgets.md, docs/compatibility.md, CHANGELOG.md (read in full), and the
names and docstrings of the regression tests. Clone: /tmp/truememory-src @ 063e5b8 (2026-08-29), pyproject 0.7.6.2.
All paths below are relative to /tmp/truememory-src unless they are absolute.

Labels:
- **MEASURED**: I ran it, or read the code line myself. For runs, the command is named.
- **CLAIMED**: stated by the README, docs, CHANGELOG or a docstring, and not verified by me.
- **ESTIMATED**: derived by arithmetic from measured parts. The method is given.

Measurement harness (everything is isolated under /tmp; nothing touched ~/.claude or the real HOME):
- `uv venv -p 3.12 /tmp/tm-research/venv`, then `uv pip install /tmp/truememory-src pytest pytest-timeout`.
- Environment: `HOME=/tmp/tm-research/home HF_HUB_OFFLINE=1 (after first download) HF_HOME=/tmp/tm-research/hf TRUEMEMORY_TELEMETRY=off`.
- The server was started directly with `python -m truememory.model_server`. I never used
  `ensure_server_running()`, because it runs `lsregister` (see red flags).
- Scripts: /tmp/tm-research/scratch/{rss_import.py, measure_server.py, measure2.py, client_rss.py, client_with_server.py, rerank_err.py}.
- Raw outputs: /tmp/tm-research/scratch/{base.out, tests.out, fulltests.out, fulltests2.out}; server logs in /tmp/tm-research/home/server*.stderr.
- Box: M1 Max, 64 GB, 10 physical cores. The rest of the fleet (about 15 sessions) was running during measurement, so latencies carry noise.

---------------------------------------------------------------------------------------------------

## 0. Headline answers to the brief

### 0.1 Is the model server shared? (MEASURED by code read and by a run)

- Yes. There is one daemon per user, not one per session.
  - It is an AF_UNIX socket at `~/.truememory/model.sock` (model_server.py:67-74).
  - It holds an exclusive `flock` on `model_server.lock` for its whole lifetime (model_server.py:837-862, 873).
  - It is spawned detached with `start_new_session=True` (_platform.py:82-99; model_client.py:212-296).
  - It renames itself `TrueMemory` with setproctitle (model_server.py:978-982).
  - It exits after `TRUEMEMORY_MODEL_SERVER_IDLE` seconds idle (default 300, model_server.py:72, 744-776). An in-flight counter blocks idle exit (model_server.py:463-477, 756).
- Only two callers start it: MCP-server startup (mcp_server.py:2360-2362) and the ingest CLI (ingest/cli.py:133-134).
- **The Claude Code hooks never start it.** Hooks reach the model through `vector_search.get_model()` (vector_search.py:231-256) and `reranker.get_reranker()` (reranker.py:212-224). Both call `use_model_server()`, which is True only if the socket exists and the PID is alive (model_client.py:535-547). Otherwise the hook process **loads the full model locally**.
  - MEASURED (client_rss.py with the server down and no env override, tier=base): 678 MB RSS, torch imported, 17.1 s for add+search.
  - MEASURED (`/usr/bin/time -l python -m truememory.ingest.hooks.user_prompt_submit` with a recall-intent prompt, server down): 8.14 s wall, 709 MB max RSS.
  - The same hook with a non-recall prompt: 0.13 s, 37.7 MB.
  - So the ~80 MB-per-session budget holds only while the daemon is up. After 5 idle minutes, each recall-bearing hook invocation costs roughly 0.7 GB and 8-17 s until something restarts the daemon.

### 0.2 RAM and CPU footprint (MEASURED unless marked)

| Component | Result | How measured |
|---|---|---|
| MCP server process (per Claude session), after import | 86 MB RSS, torch not imported, 1.03 s import | rss_import.py, with mcp pinned <2 (see red flag 1) |
| Docs claim for the same | "~80 MB" per MCP session | docs/resource-budgets.md:10,60. CLAIMED; consistent with the import-time figure |
| Hook process, non-recall prompt | 0.13 s, 37.7 MB | `/usr/bin/time -l` on user_prompt_submit |
| Hook/client process doing add+search, server warm (base) | 4.0-4.4 s total, search 1.4-1.8 s, 201 MB RSS; torch is still imported client-side | client_with_server.py |
| Hook/client process, server down (base) | 17-20 s, 678-709 MB | above |
| Hook/client process, server down (edge) | 4.25 s, 125 MB, no torch | client_rss.py with TRUEMEMORY_NO_MODEL_SERVER=1 and edge tier |
| Model server, idle before any load | 40 MB RSS, 5 threads, 0.000 s CPU over 5 s idle | measure_server.py edge |
| Model server, edge embed only | 170 MB RSS; warm single embed p50 1.1 ms, p95 1.8 ms | measure_server.py edge |
| Model server, edge + MiniLM reranker (torch loaded) | 745 MB RSS; warm rerank of 25 pairs p50 27 ms | measure_server.py edge |
| Model server, base, Qwen3 loaded on MPS | 666-673 MB RSS, **footprint 1.60 GB** (`footprint -p`); warm single embed p50 25-40 ms, p90 65-112 ms | measure2.py |
| Model server, base + gte-modernbert reranker | footprint 2.64-2.68 GB; warm rerank of 25 pairs p50 417 ms-1.97 s (noisy) | measure2.py |
| Model server, base, after MPS OOM (sticky CPU) | RSS 1.8-2.0 GB, footprint 2.5 GB (`top` MEM 3.6 GB); pinned at about 1 core (98% CPU) | ps/top on PID 97941 and 8605 |
| Model server, base, `TRUEMEMORY_DEVICE=cpu` | RSS 1.40 GB, footprint 433 MB; warm single embed p50 451 ms, p90 1.14 s; a 16-text batch did not finish within 130 s | measure2.py |
| Docs claim | server about 500 MB (edge) / about 1.5 GB (base/pro) | resource-budgets.md:15-19. CLAIMED; broadly consistent with the footprints above |

ESTIMATED for our box (15 sessions, method: measured parts × counts):
- Daemon up, base tier: 15 × 86 MB + one daemon at about 2.7 GB footprint ≈ 4.0 GB steady.
- Daemon idle-exited: each recall-bearing hook adds about 0.7 GB transiently for 8-17 s, and nothing caps how many run at once.
- Ingest workers: the dynamic spawn cap allows up to 6 on base tier (hooks/core.py:70-78, 218-232: ceiling = min((64-2)/1.0, 6)). Each worker may run `claude -p` for extraction (ingest/models.py:463-487), plus its own local Qwen3 if the daemon is down. The claude-CLI RSS is not measured here; guessing about 0.4 GB, that is up to ≈ 6 × (0.7 + 0.4) ≈ 6.6 GB.

### 0.3 MPS on a 64 GB box (MEASURED)

- The default watermark is `ratio = max(min(0.08, 2.5/total_gb), 1.5/total_gb)` (model_server.py:25-40), which gives 2.5 GB on 64 GB.
- A 64-text batch and a 16-text batch (~80 tokens each) both hit MPS OOM. The 16-text case matters because the default `TRUEMEMORY_MPS_BATCH_SIZE` is 16 (vector_search.py:691). An 8-text batch passed in 1.4 s.
- After an OOM the server flips to permanent ("sticky") CPU.
- The server hard-sets `OMP_NUM_THREADS=1` (model_server.py:27-30), so CPU fallback is single-threaded:
  - 16 texts took 59.7 s.
  - 64 texts took more than 120 s and tripped the client's default timeout (base.out).
  - After the client gave up, the orphaned server kept burning about 1 core at 1.8-1.9 GB for minutes. The in-flight counter blocks idle exit until the encode finishes. I killed PIDs 97941 and 8605 by hand.
- Measured log line: `MPS OOM in the embed path — degrading the embed model to CPU for the lifetime of this model server` (server.stderr, server2.stderr).

---------------------------------------------------------------------------------------------------

## 1. Model server (model_server.py). Every item MEASURED by reading.

1. **Lock before bind (M-20).**
   - Takes an exclusive `flock` on `model_server.lock` before touching any socket or PID artifact (837-862, 873). The fd is held for the process lifetime.
   - The PID is written only after a successful bind (900-902), so the server never advertises before it listens.
   - The PID pre-check in `main()` is advisory only (989-1001).
2. **Cleanup only what this process owns.** `_safe_to_cleanup_artifacts()` (85-105) refuses to unlink the socket, PID, port or token files when PID_PATH names a *different live* PID, i.e. a successor after a crash. `_cleanup` is idempotent via `_cleaned_up` (933-936). It is registered with atexit (1006) and on SIGTERM/INT/HUP (967-987).
3. **Idle reaper that respects in-flight work (M-74).**
   - `handle_request` bumps `_inflight` and stamps `_last_activity` at start and at end (463-477).
   - The idle checker exits only if `elapsed >= IDLE_TIMEOUT and inflight == 0` (744-776). It unblocks `accept()` with a dummy connect (761-775).
4. **Server-side deadline (M-44).** The client sends an absolute epoch `deadline`. The server rejects expired requests before taking the global lock or encoding (485-496).
5. **Protocol versioning (M-53).** Every response carries `"protocol": 1` (732-742). The client raises `ProtocolMismatchError` on non-JSON or a version mismatch and does not retry autostart on it (model_client.py:394-418, 454-458).
6. **Bounded framing (#458).**
   - 4-byte length header with a `_MAX_MESSAGE_SIZE` of 10 MB, checked on requests (699-707) and on responses (739-740).
   - A per-connection socket timeout of 30 s (672-676).
7. **No pickle (#457).** JSON with base64 ndarrays and a dtype allowlist on the server side (108-131). The client decoder has **no** dtype allowlist (model_client.py:79-84); this is minor, since the trust boundary is the server.
8. **Fast lane for single-text requests (#577).**
   - It tries the global lock without blocking. If the lock is busy, it encodes on a lazily loaded **CPU copy** of the model outside the lock, so hook queries never queue behind batch ingest or OOM recovery (416-461).
   - Parity is guarded: the lane is used only for model IDs with a deterministic builder (340-346, 361-395). The (model, tier, id) identity is an immutable dataclass snapshot published by one reference assignment (137-151, 348-359).
   - Cost: a second resident copy of the model, which is extra RAM.
9. **Sticky CPU degradation after MPS OOM (#577).**
   - Marked once and logged loudly, with the state written to `model_server.status` (201-233).
   - Recovery runs atomically under the lock. The expensive batch re-encode runs *outside* the lock (534-562). The rerank path mirrors this (580-613).
   - The reasoning is in the code (549-554): re-promoting to MPS "guaranteed the next OOM (retry storms)".
10. **Throttler activation on sustained load.**
    - More than 10 embed requests in 30 s turns on `DynamicThrottler` (157-158, 509-523). Fewer than 3 in the window turns it off (573-576).
    - M-43 fix: the throttler reference is captured into a local under the lock (525-532, 565-571).
11. **Other.**
    - The directory is chmod 0700 (864-870); the socket is 0600 (883).
    - On the Windows TCP path, an HMAC token is compared with `hmac.compare_digest`, written atomically with its mode set before rename (779-803), and hardened with an icacls ACL (805-835).
12. **Weaknesses found by reading** (red flags 5-8):
    - `_write_status_file` is not atomic (223-233).
    - `model_server.status` is not in the cleanup list (942), so a sticky-CPU status outlives the server. MEASURED: the file persisted after SIGTERM. The MCP health check reads it without checking the PID (mcp_server.py:874-910), so it reports "degraded" permanently.
    - The PID file is written with plain `write_text` (902).
    - `throttler.before_batch()` runs on the request thread and can `time.sleep` 20 s during `_triple_sample` (throttler.py:87-89, 148-155).
    - `OMP_NUM_THREADS=1` (27) makes CPU fallback single-threaded (MEASURED above).

## 2. Client (model_client.py). Every item MEASURED by reading.

1. **One total deadline (M-76).** A single monotonic deadline covers connect, send and receive. The remaining budget is re-applied before each blocking operation (299-309, 312-350, 353-392). The old per-operation timeouts could blow the budget by 4x (CLAIMED in the docstring, 357-358).
2. **Process-wide fast-fail for hooks.**
   - `set_request_timeout()` (60-76) is armed by every hook recall path through `get_recall_deadline()`: `TRUEMEMORY_HOOK_RECALL_TIMEOUT`, default 5 s, malformed values fall back to the default (ingest/hooks/_shared.py:96-116).
   - Callers include session_start.py:945-955 and user_prompt_submit.py:466-476, 594-596, 653-655.
   - On expiry the call raises `TimeoutError` with no autostart retry (437-485), and the engine falls back to FTS-only search.
3. **Autostart.** It unlinks stale artifacts when the PID is dead (231-237), spawns detached, and waits for the socket up to min(30 s, remaining budget) (285-296). If the wait times out, the spawned server keeps warming for later calls (215-219).
4. **Side effects.** `_ensure_app_bundle()` builds `~/.truememory/TrueMemory.app`, hard-links the Python binary into it, and runs `lsregister -f` (94-166). See red flag 9.
5. **Residual race (reasoned, not measured).** A client that sees "no live PID" unlinks SOCK_PATH (231-235). The server binds the socket (882) before it writes the PID (902). A client landing in that window can unlink a live server's socket path. That server stays up, still holds the bind lock, and gets no traffic until its idle exit (≤300 s). Meanwhile new starters fail the lock, so hooks fall back to loading the model locally.

## 3. tier_switch/* (re-embed orchestration). Every item MEASURED by reading.

- **manager.py**
  - Claim flag so a failure before the thread starts cannot brick the singleton (M-51, 107-189).
  - The sync (CLI) path takes a non-blocking `flock` on `rebuild.lock` (192-227). **The async MCP path does not** (117-189), so a CLI rebuild and an MCP rebuild in different processes can overlap.
  - The config switch runs only after a successful rebuild (`_finalize_rebuild`, 371-401; CHANGELOG 0.6.9 lines 175-177): "config flip before rebuild completion" left users on a new tier with zero vectors.
  - The config write is atomic (mkstemp + os.replace) under a cross-process lock (403-452).
  - `backup_db` uses **`shutil.copy2` on a WAL database** (475-495), which is not a consistent snapshot. Compare storage.py:416-450, which uses the SQLite backup API and keeps 3 backups.
- **worker.py**
  - Hard timeout of 2.5 h (19, 115-122). Cancel flag (44-46).
  - Progress is persisted per batch in `vector_cache_registry` (166-171), so a delta rebuild resumes (cache.py:141-209). The status row carries a heartbeat (238-290).
  - **The OOM path `continue`s with no counter** (136-144). A persistent OOM at batch=1 spins until the 2.5 h timeout.
  - `_is_oom_error` matches the substring "oom" (292-304), so "room" or "zoom" in an error message trigger a false positive.
- **state_machine.py + throttler.py + sensors.py**
  - States are PROBING, STABLE and BACKOFF, with asymmetric intervals: halve on critical, step down on warning, ramp up by one step after 3 good checks, 120 s cooldowns (state_machine.py:16-141).
  - Three sensors: MPS driver-allocated memory against the cap, growth rate per 20 s, and thermal via `pmset -g therm` with a 5 s timeout (sensors.py:15-105).
  - "Triple sample" means 3 readings 10 s apart; any warning in any sample vetoes a ramp (throttler.py:148-171).
  - Per-RAM machine profiles (throttler.py:23-36). Cache flush only in STABLE or BACKOFF (114-119). Fixed in CHANGELOG 0.6.9: "STABLE never returned to PROBING".
- **cache.py**
  - `preflight_ram_check`: at least 8 GB total and at least 2 GB available before a Base/Pro rebuild (212-233).
  - Delta rebuild uses `last_embedded_id` as a watermark (141-209).

## 4. Config, hooks and ingest robustness (outside the named files, but the source of the reusable patterns)

- **Config corruption quarantine** (mcp_server.py:134-222).
  - Reads through a cache with a 5 s TTL plus an mtime check. Uses `utf-8-sig` so a BOM is tolerated.
  - Valid JSON that is not an object is treated as corrupt.
  - On corruption it renames to `config.json.corrupt.<ts>` and prints a stderr hint, never a silent `{}` (CHANGELOG 0.5.0, line 407).
- **Config writes** (mcp_server.py:60-125, 246-313).
  - Two locks: a cross-process `flock` on `config.json.lock` (blocking), plus a thread lock.
  - mkstemp, then `os.replace` with a Windows retry.
  - Invalidates the cache after writing. Degrades to "proceed unlocked" if flock is impossible.
- **Env-var hygiene (#639)**: `_env_int` returns the default on garbage and clamps to [lo, hi] (_platform.py:26-56). This kills the import-time crash class and the negative-LIMIT = unlimited class.
- **Liveness-based stale lock (#461, #649 M-31)** (ingest/pipeline.py:90-330).
  - A lock is stale only when its holder PID is dead. TTL applies only when no PID is attributable.
  - Waiting on `flock(LOCK_EX)` is the authority. The PID and mtime heartbeat are diagnostics only.
  - After acquiring, the code checks that the path's inode still equals the locked fd's inode, and retries if the lock file was replaced underneath (247-310).
  - The dedup-then-store critical section runs under this lock to stop a TOCTOU between concurrent Stop hooks (194-246).
- **Memory-pressure-adaptive spawn cap** (hooks/core.py:40-445).
  - Ceiling by tier: edge = physical cores - 1, capped at 5; base/pro = (RAM - 2 GB) / per-process cost, capped at 6.
  - Pressure input: `memory_pressure` free %, with <15% critical and <40% warn (120-146). **Swap growth delta** above 0.5 GB counts as an emergency (149-170, 235-238).
  - Response: an emergency drops the cap to 1; a warn seen twice in a row halves it; the cap ramps up by 1 at most every 120 s.
  - State is persisted with a 300 s expiry (80-82, 172-216).
  - The spawn gate is `flock` plus a PID file filtered for liveness, not pgrep, because of a race between Popen and pgrep (382-445).
  - Over-cap work is queued to `~/.truememory/backlog/<sid>.json` instead of running inline (803-830). CHANGELOG 0.5.0 line 415 says the inline fallback had been blocking Claude Code shutdown for 10-60 s.
- **Backlog claim protocol** (mcp_server.py:1854-1944; ingest/hooks/_shared.py:343-430).
  - Claim by atomic rename `.json → .processing`.
  - The worker PID is recorded in the claim. On success the worker unlinks the claim. On failure the claim stays.
  - `cleanup_stale_processing` restores a claim only if it is older than 30 min AND its PID is dead.
  - Corrupt markers go to quarantine `.corrupt` rather than being recycled as poison pills (#644 M-14).
  - The hourly extraction budget is a flock'd JSON counter, with a **refund** when the gate denies the spawn (M-71).
- **Stale-transcript scanner** (ingest/hooks/session_start.py:455-620).
  - A non-blocking flock acts as a singleton; if another scanner holds it, this one skips.
  - Uses a **watermark**: O(new), not O(all).
  - M-37: when the cap is hit, the watermark is **held at the cutoff** so deferred work stays in the window.
  - Marker pruning runs before any early return (#694: 54K+ markers accumulated in prod, CLAIMED).
- **Detached maintenance with a recursion guard.**
  - SessionStart spawns drain+scan as a child with `TRUEMEMORY_MAINTENANCE_CHILD=1`, and a child re-entering the hook refuses to spawn (session_start.py:623-672).
  - It never falls back to running inline when the spawn fails (M-38).
  - Every hook's `main()` returns early under `TRUEMEMORY_EXTRACTION`, which is set in the env of the `claude -p` extraction subprocess (ingest/models.py:469-470; user_prompt_submit.py:729).
- **Parent-death watcher (#401)** (mcp_server.py:1962-2024).
  - Records the initial PPID. Self-exits via `os._exit(0)` only on a **transition** of PPID to 1.
  - It is disabled when the process was started with PPID == 1, and it never signals siblings.
  - `os._exit(0)` after `mcp.run` avoids a PyTorch teardown deadlock (2374-2395; CHANGELOG 0.6.3 line 308).
- **DB handle self-heal (#684)**: `_ensure_connection` probes the cached handle with `PRAGMA schema_version` and reconnects on `sqlite3.Error` (engine.py:372-400).
- **Crash-safe migrations.**
  - #686: the staging "done" marker is written in the same commit as the rows.
  - #647: an `in_progress` build marker is written in the same transaction as the DELETE; resume from max(rowid) instead of re-wiping.
  - #650: pre-migration backups use the SQLite backup API, rotated to keep N, plus an actionable `DatabaseOpenError` naming the newest backup (storage.py:255-330, 348-450).
- **Recall cache contract (#559, #645).**
  - A 5-minute file cache for SessionStart recall. The key covers intensity, budget, producer and a normalized DB path.
  - **Never negatively cache after a transient failure**: an empty result is cached only if at least one query succeeded (session_start.py:1010-1075).
  - Invalidated on delete, update and batch commit.
- **Atomic marker writes**: PID-unique temp file, chmod before rename, `os.replace` (ingest/hooks/_shared.py:121-146). There is no fsync (see red flags).
- **Instrumentation overlay** (instrumentation/*).
  - Opt-in. Monkeypatches are idempotent via a sentinel attribute. Every wrapper swallows its own errors.
  - Writes to a **separate** SQLite DB, with WAL, `busy_timeout`, 7-day retention, and pruning every 1000 emits plus a 24 h wall-clock fallback.
  - Privacy contract: IDs, scores and timings only; no content (patch.py:1-15, writer.py:1-158, signals.py:1-16).
- **Telemetry** (telemetry.py). See red flag 3.

## 5. Bug classes fixed, from the regression-test names and docstrings (165 test files; 99 `test_issue_*`)

| Class | Tests (docstring source) | Pattern that fixed it |
|---|---|---|
| Stale locks / no PID validation | 461, 649 (M-31), spawn_gate, 644 | PID-liveness authority; inode revalidation; claim files carrying a PID |
| Lock scope too wide (inference or regex under the write lock) | 468, 496, 591, 692, consolidation_lock (#401) | Pre-compute outside the lock; SAVEPOINT txn hygiene; batch commits (590) |
| Missing write lock | 484 (consolidate), 455 | Route every mutation through `_write_lock` |
| Atomic writes / rename semantics | 641, 643 (Path.rename → os.replace), 691, config_corruption | mkstemp/pid-tmp + os.replace + cross-process flock |
| Corruption UX | 650, 640 (schema validation at every reader), config_corruption (F04) | Quarantine rename, actionable error, backup rotation |
| Crash mid-migration / partial rebuild | 483, 485/499 (flag set before success), 647, 686 | Same-txn done markers; set "done" flags only after success |
| NaN / Inf vectors | 465, 485, 492 | Validate at the single choke point `serialize_f32`; async NaN fix |
| MPS OOM | 459, 489, 577 | Shared `is_mps_oom`; sticky CPU; retry outside the lock; fast lane |
| Socket bounds / RCE | 457 (pickle), 458 (size), 514 (dtype, response size), tcp_transport, 598 | JSON + allowlist + size caps + HMAC |
| Server lifecycle | 646 (bind lock, throttler TOCTOU, deadline, protocol, inflight) | See section 1 |
| Poisoned DB handle | 684 | Probe + reconnect |
| Parent death / orphans | parent_death_watcher (#401) | PPID transition watcher |
| Subprocess hangs | subprocess_timeouts (F23) | `timeout=30` on every `claude` CLI call |
| Env-var crash at import | 639, encoding_gate_bad_env | `_env_int` with clamps |
| Unbounded growth | 694 (markers), 650 (backups), instrumentation retention, 560 (O(n) scan) | Prune before early returns; rotation; watermark |
| Unbounded synchronous work on the hot path | 693 (store rate limit), 557 (async drain), 690/689 (skip reranker / redundant FTS) | Debounce; detach; skip expensive stages on recall |
| Races in queue/claim | 644, 422 (drainer must not unlink the claim on spawn), 635 | Rename-claim; success-only unlink; refund |
| Negative caching / stale cache | 559, 645 | Key completeness; invalidate on mutation; no negative cache on error |
| Injection / sanitization | 637, 638, memory_render_escape, 696 (log sanitize) | Tag escaping; byte sub-budgets |
| Silent degradation | 592, CHANGELOG 0.5.0 health payload | `health` / `degradation` sections in stats |
| File permissions | 688, platform_compat | 0700 dir, 0600 files |
| Test isolation | ci_isolation (#426), 697 | Hermetic sockets, offline env centralized |

**Test runs (MEASURED, in the /tmp venv with mcp pinned below 2):**
- Ops subset of 30 files: **278 passed in 16.15 s**.
- Full suite with `-m "not network" -x`: 622 passed, 7 skipped, then **1 failed** (`test_issue_465_qwen3_nan_async::test_issue_465_flag_set_immediately`, "qwen3_nan_fix_applied flag not set"). The full non-`-x` result is in fulltests2.out; totals are appended at the bottom of this file.

**Upstream CI (MEASURED, `gh run list`):**
- CI on main has **failed** since 2026-08-29.
- The dependabot PR widening `mcp` to `<3.0` (#726) failed CI on its branch (2026-07-29) and was merged anyway (1e71e80).
- Open PR #729, "RSS memory watchdog, idle unloader, LRU caches", is unmerged.

## 6. CHANGELOG operational highlights (read in full: 0.1.1 → 0.7.6.0)

- The CHANGELOG stops at 0.7.6.0 (2026-06-08). The 0.7.6.1 and 0.7.6.2 "BLAST OFF v2/v3 hardening" releases, which cover #639-#697, are only in git log (MEASURED: `git log`).
- 0.7.2.0 (lines 70-165): "76 agents, 675 findings, 7 criticals", 37 fixed. CLAIMED.
  - This release added `encode_with_mps_fallback` **restoring MPS after CPU fallback** (lines 97-99; mps_utils.py:113-139).
  - Issue #577 later concluded that re-promotion guarantees the next OOM, but only the **server** path became sticky. The in-process path still re-promotes (mps_utils.py:131-137), and it is used by vector_search, hybrid and engine (MEASURED by grep: hybrid.py:188-190; vector_search.py:719-720, 827, 909, 976, 1120, 1177, 1200, 1254, 1260; engine.py:729-734, 1175-1188).
- 0.6.9 (lines 167-203): "MPS memory balloon: 17 GB of MPS on a 24 GB machine" during tier switch. Capped by watermark, with a live peak of 1.88 GB (CLAIMED). Also the 2.5 h hard timeout and the adaptive throttler.
- 0.6.3 (line 308): the PyTorch teardown deadlock, fixed with `os._exit(0)`.
- 0.5.0 (lines 390-458):
  - Busy-timeout single source of truth (10 s).
  - Stop-hook spawn cap with a backlog instead of inline ingest.
  - A health payload. The config corrupt-rename.
  - `timeout=30` on the claude CLI and `timeout=600` on pip.
- 0.6.4-0.6.7 (lines 251-284): telemetry introduced as opt-out, with an email prompt added to onboarding "ensuring the telemetry dashboard captures emails from all users" (lines 246-249).

---------------------------------------------------------------------------------------------------

## 7. Red flags (each MEASURED unless marked)

1. **The HEAD install is broken.**
   - pyproject allows `mcp<3.0` (1e71e80). A fresh install resolves mcp 2.2.0, and `import truememory.mcp_server` fails with `ModuleNotFoundError: No module named 'mcp.server.fastmcp' ... This is mcp 2.x` (rss_import.py run).
   - The last release commit pinned `<2.0` (`git show e7f1fd7:pyproject.toml`). main CI has been red since 2026-08-29.
   - sentence-transformers 6.1.0 was also admitted (#731); CI failed there too.
2. **The shared-daemon memory budget does not hold for hooks.** When the daemon is idle-exited, hooks load models in-process: 678-709 MB and 8-17 s per recall-bearing hook (section 0.1).
3. **Telemetry is on by default and phones home.**
   - It sends `user_id`, a hashed IOPlatformUUID, and **email** when configured, to `telemetry-api-production-c2a3.up.railway.app` (telemetry.py:45, 60-96, 106-157, 160-184).
   - `user_prompt_submit._try_capture_email` **scans user prompts for email addresses** and saves them into config (user_prompt_submit.py:681-723).
   - That write uses a fixed temp name `config.tmp` and **no cross-process lock**, which contradicts the #641 "atomic + cross-process-locked config writes" claim.
4. **The default MPS cap plus the default batch size causes OOM** on a 64 GB M1 Max: 2.5 GB cap vs. 16-text batches. Sticky CPU at `OMP_NUM_THREADS=1` then drives a >120 s encode and client timeout, and the orphaned server keeps grinding at about 1 core and 1.9 GB (section 0.3).
5. **Stale health status.** `model_server.status` is not cleaned up on exit (model_server.py:942) and is read without a PID check (mcp_server.py:886-893). MEASURED: it persisted after SIGTERM.
6. **Spawn cap state is updated outside the lock.** `spawn_gate()` calls `_get_spawn_cap()` before taking the flock (hooks/core.py:392), although `_load_cap_state` and `_save_cap_state` say "Must be called while holding the spawn flock" (176, 198). Also, `int(os.environ["TRUEMEMORY_SPAWN_CAP"])` is a bare `int()` (259-264), which is the class #639 claims to have removed.
7. **Unbounded OOM retry** in the tier-switch worker (worker.py:136-144). A **non-atomic WAL backup** (manager.py:475-495). **No rebuild lock on the async path** (manager.py:117-189).
8. **The throttler sleeps on the request thread**: about 0.05 s plus 0.02 s × batch per call, and a 20 s triple-sample (throttler.py:91-92, 148-155; called from model_server.py:529-532).
9. **Surprising system side effects from the client.**
   - It hard-links the Python binary into `~/.truememory/TrueMemory.app` and registers it with LaunchServices via `lsregister -f` (model_client.py:94-166).
   - setproctitle renames the daemon to `TrueMemory` (model_server.py:978-982). MEASURED: `pgrep -f truememory.model_server` finds nothing, so a process reaper matching on the cmdline misses it.
   - The installer rewrites `~/.claude/settings.json` hooks and `~/.claude/CLAUDE.md` (hooks/adapters/claude.py:130-230; CHANGELOG 0.6.0 lines 352-356). The CLAUDE.md template asserts "TrueMemory as the primary long-horizon memory, with built-in auto-memory for session notes only" (line 355-356). That conflicts with our file-based memory.
10. **No fsync** in any atomic write: `_shared._atomic_write_text` (121-146), `ModelServer._atomic_write_text` (779-803), `_save_config` (283-289). Power-loss durability is not guaranteed, although rename atomicity holds.
11. **PID reuse is unguarded.** Every liveness check is `os.kill(pid, 0)` or `psutil.pid_exists` with no process start-time check (_platform.py:63-75; hooks/core.py:332-346; _shared.py:230-253).
12. **Unbounded, verbose logs.**
    - `model_server.stderr` is appended forever with no rotation (model_client.py:253-254). MEASURED: 190 HF "HTTP Request" INFO lines in one online session; 37-54 KB across a few starts.
    - A failed reranker load is retried on every request with no negative cache (MEASURED in server2.stderr: repeated "No modules.json found ... initializing a new CrossEncoder").
13. **Not every file is 0600.** `buffers/<sid>.jsonl` (raw prompt text) is 0644 and `memories.db` is 0644, although the parent directory is 0700 (MEASURED: `ls -la`). This is weaker than the #688 "owner-only" wording but protected by the directory mode.
14. **CHANGELOG drift.** It stops at 0.7.6.0 while the code is 0.7.6.2. The 0.7.2.0 claim "restores to MPS after successful CPU encoding" is contradicted by the #577 sticky-CPU rationale; both behaviours coexist on different paths.

---------------------------------------------------------------------------------------------------

## 8. What transfers to our bash/python hook fleet (claude-infrastructure)

Each entry gives the pattern, the TrueMemory reference, our target, and why.

**T1. Kernel-released locks instead of mkdir + TTL.**
- Pattern: stop reclaiming locks by age.
- TrueMemory: pipeline.py:107-140 ("liveness — not age — is the authority") and 247-310.
- Ours: bin/cc-memory-rotate:114-115 and 342-350 use an mkdir lock with a 180 s age reclaim and state "macOS has no flock(1)".
- **MEASURED on this box:** `/usr/bin/lockf` exists. Both command form (`lockf -t 0 file cmd` → rc 75 when held) and **fd form** (`exec 9>f; lockf -s -t 0 9` → second holder rc 75, rc 0 after release, and **rc 0 after the holder is SIGKILLed**) work in bash.
- So the kernel releases the lock on death and no stale-reclaim path is needed. A long rotate (>180 s) can no longer be stolen from a live holder, which is exactly TrueMemory's M-31 bug.
- Caveat: children inherit fd 9, so close it (`9>&-`) before detaching anything.

**T2. PID-attributed claims for queues.**
- TrueMemory: rename `.json → .processing`, record the worker PID, unlink only on success, and restore a claim only when it is older than the threshold AND its PID is dead. Poison markers go to quarantine `.corrupt`. Budget slots are refunded on deny (mcp_server.py:1854-1944; _shared.py:257-430).
- Ours: harvest (hooks/harvest-skill-end.sh), memory-index-drain and any backlog/mailbox queue.

**T3. Memory-pressure-adaptive concurrency.**
- TrueMemory: `memory_pressure` free %, **swap-growth delta** rather than absolute swap, a hysteresis count, halve on warn, drop to 1 on critical, ramp up +1 per 120 s, persisted state with expiry (hooks/core.py:120-310).
- Why it matters here: our box has a VM-compressor exhaustion history. This is a ready-made governor for any hook that spawns work (harvest, rotate, headless `claude -p`), or a gate that defers optional memory work (nudges, compaction) under pressure.
- `memory_pressure` reported "System-wide memory free percentage: 62%" when I ran it on this box, so the input parses here.

**T4. Deadline propagation.**
- TrueMemory:
  - A total monotonic deadline re-applied per operation (model_client.py:353-392).
  - A process-wide short deadline for hook paths, with an FTS-only fallback (_shared.py:96-116).
  - The deadline travels with the request so the worker drops expired work before the expensive part (model_server.py:485-496).
- Ours: memory-index-drain.sh:145-175 already states the "per-call bounds multiply" lesson. What is new is shipping the absolute deadline to children (env var `DEADLINE_EPOCH`), so detached helpers fail cheap instead of finishing work nobody waits for.

**T5. Watermark scanning that never skips deferred work.**
- TrueMemory: O(new) scans by mtime watermark. When the cap is hit, the watermark is held at the cutoff instead of advancing to now. Pruning runs before every early return (session_start.py:455-620; #694, #560).
- Ours: any scan of `~/.claude/projects/*/memory` or transcripts (harvest, rotate citation scan, worktree-memory-link).

**T6. Fail safe, never fail silent.**
- TrueMemory:
  - Quarantine corrupt state with a timestamped rename plus a one-line stderr hint (mcp_server.py:184-205).
  - Treat valid-but-wrong-shape JSON as corrupt (163-172).
  - `_env_int`-style clamps for every numeric knob (_platform.py:26-56).
- Ours: frontmatter-parse failures in topic files, `.rotate.log`, and hook env knobs such as `MEMORY_NUDGE_INTERVAL`. A garbage value must not crash the hook at start or mean "unlimited".

**T7. No negative caching after transient failure.**
- TrueMemory: cache an empty result only if at least one query succeeded. Key the cache on every input that changes the output. Invalidate on mutation (session_start.py:1030-1075; #645).
- Ours: any cached measure, such as the memory-index-measure result or a nudge's budget figure, if cached.

**T8. Self-only orphan exit.**
- TrueMemory: record the initial PPID and exit only on a transition to PPID 1. Never signal siblings (mcp_server.py:1962-2024).
- Ours: long-lived helpers and detached watchers.
- Addendum from our own lesson in commit 157a76c: a detached bash is reaped after ten minutes, so detach.sh is necessary but not sufficient.

**T9. Recursion and fork-storm guards via env.**
- TrueMemory: `TRUEMEMORY_EXTRACTION=1` on `claude -p` children makes every hook `main()` return immediately. `TRUEMEMORY_MAINTENANCE_CHILD=1` blocks respawn (models.py:469-470; session_start.py:623-631).
- Ours: any hook that shells out to `claude -p` (harvest, compaction). The headless child loads our whole hook fleet, so it needs a sentinel that the memory hooks honour at line 1.

**T10. Detach, never inline, when spawning fails.**
- TrueMemory: M-38 (session_start.py:664-671) and the Stop-hook backlog instead of inline ingest, which had blocked shutdown for 10-60 s (CHANGELOG 0.5.0 line 415).
- The reasoning: spawn fails exactly when the system is unhealthy, so synchronous fallback strikes at the worst moment.

**T11. "Set done flag only after success" and same-transaction markers.**
- TrueMemory: #485/#499, #647, #686, and the tier switch writing config only after finalize (manager.py:371-401).
- Ours: cc-memory-rotate already verifies COLD before rewriting the index (bin/cc-memory-rotate:109-113). Apply the same order to compaction and harvest: write and verify the destination, then retire the source.

**T12. Surface degradation explicitly.**
- TrueMemory: a `health` / `degradation` payload with the last error per subsystem (#592; CHANGELOG 0.5.0 line 400).
- Caution: TrueMemory's own implementation leaves a stale status file (red flag 5). Key every status file by writer PID and treat a dead writer's status as unknown.

**T13. Where our design is already stronger.**
- Our index rewrite uses optimistic concurrency: temp + rename with a stat re-check and bounded retry (bin/cc-memory-rotate:109-114). TrueMemory's `_try_capture_email` and `_write_status_file` have no equivalent.
- We measure the loader's real units (hooks/lib/memory-index-measure.sh). TrueMemory's budgets are char counts with a truncation marker (session_start.py:965-1000). These are not worth porting.

**What not to adopt:**
- The embedding daemon itself: +1.6-2.7 GB footprint, MPS OOM behaviour at defaults, and it does not cover hook processes.
- The telemetry.
- The installer's rewrites of settings.json and CLAUDE.md.
- AGPL-3.0 means only ideas transfer, not code.

---------------------------------------------------------------------------------------------------
## Appendix: full test-suite result (MEASURED)

Command:
`HF_HUB_OFFLINE=1 /tmp/tm-research/venv/bin/python -m pytest -q -m "not network" --timeout=120 tests/`
Run in /tmp/truememory-src with HOME=/tmp/tm-research/home and mcp pinned to 1.30.0.

Result: **3 failed, 1939 passed, 8 skipped, 3 deselected** in 206.74 s.

All three failures are in the NaN re-embed flag / background-thread area:
- test_issue_465_qwen3_nan_async::test_issue_465_flag_set_immediately
- test_issue_485_nan_thread::TestIssue485NanFlagAfterCompletion::test_issue_485_nan_flag_set_after_completion
- test_issue_485_nan_thread::TestIssue499NanThreadLoadsSqliteVec::test_issue_499_nan_thread_loads_sqlite_vec

I did not isolate the cause. It could be environmental: sentence-transformers 6.1 / torch 2.14 admitted by the widened pins, or real models present in HF_HOME. Raw output is in /tmp/tm-research/scratch/fulltests2.out.

After the run no model server from this study was left alive (checked with `ps` for the `TrueMemory` proctitle). The `TrueMemory`-matching processes still running belong to a sibling agent's harness under /tmp/tm-sandbox and were not touched.
