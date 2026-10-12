---
status: in-progress
---
# Accounts board + router freshness — implementation plan

Scope (frozen): make the SessionStart account board and the `claude` launcher's routing see auth changes (logout, /login, relogin) and live-session counts within about 30 s, and stop fleet-wide `concurrency-unmeasured` abstentions caused by a starved `ps`. Hard limits: no diff to the SessionStart hooks, the launcher or the keepwarm plist; zero model tokens; no change to the usage-endpoint cadence; no change to what the cache `ts` means.

Evidence labels: VERIFIED means read or measured, with the command named. INFERRED means derived. ESTIMATED means arithmetic on measured parts. Line numbers refer to `bin/claude-accounts` at origin/main `dcf7c53d6` unless another file is named. That file moves almost daily, so re-grep by function name before every edit.

## Phase 0 — Agent Team Orchestration

**Execution locus per wave** (S = dispatched session, T = in-session teammate, L = lead-inline):

| Wave | Content | Locus | Why |
|---|---|---|---|
| W0 | worktree, migration-number check, baselines | L | Five read-only commands; nothing to parallelise. |
| W1 | native census, router charge, `--census-ab-report`, then **Land A** | L | Every edit is in bin/claude-accounts, around the `None` contract and heal's rotation gate. One mind has to hold those invariants, and a teammate would need the same context. |
| W2 | provenance stamps, write lock, `cache_commit`, ledger/pollstate locks, cache-only `want_heal` | L | Same file, and W3 builds directly on it. |
| W3 | local overlay, `--local-refresh`, first read, sweep reuse guard | L | Same file; its rules interlock with W2's. |
| W4 | board: locked, mtime-preserving writes, sig sidecar, keepwarm renders from the committed cache, footer, `_util_tail` memo | L | Same file. |
| W5 | launchd plist, migration 0063, manifest row, cc-fleet count, store-bounds row, and their bats | T (one teammate, started when W3 starts) | File-disjoint from bin/claude-accounts and fully specified by §3 D9. Its precedents (0055, 0059, accounts-board.bats test 27) are self-contained reading that would otherwise cost lead context. |
| W6 | gate, **Land B**, converge, DoD checks, operator handoff | L | /ship owns the tree while in flight; landing and converging stay with the lead. |

**Team roster.**
- `lead`: the recycled implementer session. It owns W0-W4 and W6, and all commits, lands and converges.
- `jobwright`: one teammate, spawned with `Agent({name: "jobwright"})`. It owns W5 only.
- No background subagents write code. A read-only explorer may be used for grep sweeps if context gets tight.

**Task dependency graph.**
```
W0 → W1 → Land A → W2 → W3 → W4 → W6 (Land B) → [operator O1] → DoD 12-16 → manifest flip land
                          └→ W5 (jobwright, parallel with W3-W4) ─┘
```
- W5 depends only on the frozen D9 contract. That contract is: the verb name `--local-refresh`; the disabled line `local: disabled`; the stamp path; the kill-switch paths; and the plist values.
- W6 needs both W4 and W5.

**Worktree assignments.**
- A single worktree, `~/Development/.worktrees/accounts-freshness` on branch `feat/accounts-freshness`, created from origin/main in W0. Both the lead and jobwright use it.
- jobwright's files are disjoint from the lead's: launchd/staged/com.claude.accounts-local.plist, launchd/fleet.manifest, tests/cc-fleet.bats, config/store-bounds.manifest, migrations/0063-*, tests/accounts-local-job.bats, tests/migration-0063-*.
- The lead re-bases the branch onto origin/main after Land A, before starting W2, using `git rebase origin/main` on the branch only.

**Spawn wave order.**
1. W0 and W1 run lead-inline.
2. Land A, then the succession check.
3. W2 runs lead-inline.
4. At the start of W3, spawn jobwright with the D9 section and the W5 task list pasted verbatim.
5. The lead runs W3 and W4 while jobwright runs W5.
6. jobwright returns. The lead reviews its files, re-runs its suites and commits them.
7. W6.

**Teammate rules (W5).**
- Edit only the W5 files, inside the lead's worktree.
- Never commit.
- Never run `launchctl` against `gui/$UID` (stubs only), and never touch `~/Library/LaunchAgents`.
- Return the file list plus each suite's `1..N` line and ok count.

The lead reviews the work, re-runs the suites and commits.

**Lead context budget.**
- Read bin/claude-accounts only by the line ranges cited in this plan. It is 8,831 lines; never read it whole.
- Target at most 50% of the context window at Land A, and at most 75% at Land B.
- **Succession point:** right after Land A converges and DoD 1-6 pass. If context is above 45% at that point, write `~/.claude/handoff-briefs/accounts-board-freshness-W2-brief.md` (W2 as next, DoD-A results pasted in) and self-recycle. Otherwise continue.
- Hard succession at 75%, at any wave boundary.

**Repo rules that bind every wave** (from `.claude/CLAUDE.md` and `.claude/rules/agent-operating-lessons.md`):
- Never commit in the shared checkout. Work in `~/Development/.worktrees/accounts-freshness` on branch `feat/accounts-freshness`.
- Land only through the project-local `/ship`. Never wrap /ship in a timeout, and never write a tracked file while it is in flight.
- Verify a land by content: `git ls-tree origin/main -- <paths>`.
- Converge with `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, never with `--force`.
- A gate refusal is not a pass: assert each suite's `1..N` against its ok count.
- Landed is not tested: the land smoke is load-shed.
- launchd runs `/bin/bash` 3.2.
- Shellcheck runs bare at the gate.

## 1. Problem

On 2026-10-11 at 17:33-17:34 CDT (22:33-22:34Z), the board showed next3 as `logged-out` and `?` in every live-session cell. The launcher then fell back to its pinned account `next` instead of next3, whose weekly quota resets soonest.

Timeline (VERIFIED from claude-accounts.log, account-utilization.jsonl, route/route.jsonl, auth-timeseries.jsonl and keychain item attributes read with `security find-generic-password -s <svc>`, no `-w`):

| UTC | Event |
|---|---|
| 22:07:26 | next3's keychain item was absent (`NO_ITEM`). |
| 22:24:20, 22:28:30, 22:32:36 | Three consecutive sweeps logged `concurrency: ps UNAVAILABLE (TimeoutExpired … 10 seconds)`. The transcript walk also blew its 15 s budget each time. |
| 22:24:38 | Rows show `k_src=panes-stale`: inherit_k carried the last census. |
| 22:32:52 | All 4 rows show `k_src=unmeasured`. inherit_k keeps the ORIGINAL measurement stamp (:2266-2271), and the last real census (≤22:22Z, INFERRED from tick spacing) was past `K_GRACE_S=600` (:2214, :2287). |
| 22:33:24 | next3's `/login` CREATED its keychain item (cdat `20261011223324Z`). |
| 22:34:04 | Desk route returned `none`: next, next2 and next4 were `concurrency-unmeasured`, next3 was `logged-out`. The launch went `pinned — no fresh quota data`. |
| 22:34:11 | The keychain write at this time was `next`'s token refresh (its item's mdat), not next3's login. |
| 22:40:10 | The next sweep's ps succeeded (`panes-stale`), and next3 read auth ok, wk 13. This is the "17:36 board fixed both". |

There are two independent defects.

1. **The census instrument starves.**
   - `ps -wwEo pid=,command=` (:697-698) now emits 2.43 MB and took 0.5-10.2 s at load 84-780, against a 10 s timeout. The docstring (:678-680) assumed 118 KB and 67-95 ms.
   - It timed out 121 times on 2026-10-11. That day, 11 of 25 desk decisions abstained, all with `concurrency-unmeasured`.
   - Since inherit_k landed on 2026-09-11, 34 of 264 desk decisions abstained, 14 of them with 3 or more accounts unmeasured.
   - At 20:40 CDT the live cache had `k`, `k_stale` and `k_work` all null on every row.
   - The failure is fleet-wide by construction: one census serves all four accounts.
2. **Auth and live facts refresh only on a full network sweep.** keepwarm runs at StartInterval 180, and each sweep takes 20-527 s. A login or logout between sweeps is invisible to the board and the router for minutes.

Both the board and routing read /tmp/claude-accounts-cache.json, so fixing what goes into the cache, and how often, fixes both.

## 2. Constraints

- **C1: zero added latency on SessionStart.**
  - hooks/accounts-board.sh and hooks/session-start-dispatch.sh get NO diff. The hook stays a stat plus a cat (measured p50 61-90 ms).
  - The hook never forks claude-accounts: tests/accounts-board.bats test 13 enforces this, and `--readout` measured 5.33 s against a 5 s timeout.
  - The board stays a top-level systemMessage, so it costs 0 model tokens. The hook cannot go async (session-start-dispatch.sh:14-15).
- **C2: zero added latency on launch.**
  - lib/claude-launcher.zsh gets NO diff. Its call, `--route interactive --max-wait 0 --max-age 600` (:85), stays cache-or-abstain.
  - In-process changes on that path are limited to in-memory field choices over 4 rows: no new file opens, locks, forks, network calls or module imports.
  - Importing ctypes was measured at 11.6-13.8 ms of CPU and up to 279 ms of wall time.
- **C3: zero model tokens.** No new `fetch_wire_limits` (/v1/messages) call anywhere; each costs about 25 quota tokens (:1250-1256). The only new network call is an OAuth usage GET after a login (D6), which is not inference.
- **C4: endpoint throttle.**
  - The 429 budget is per token and sticky: a re-poll within 30 s gets a 429 97.6% of the time.
  - keepwarm stays at StartInterval 180 with `--max-age 90` (plist :35-39, :82-89). Shortening it was rejected on 2026-10-06.
  - Polls of the same token stay at least 90 s apart.
- **C5: `ts` keeps one meaning: when a sweep read quota.** Only get_data (:6369-6371) writes `ts`, `window`, `prev`, `no_heal` and `cfg_key`. Bumping `ts` from anywhere else would:
  - silence keepwarm (cache_read :5947-5948 against `--max-age 90` at :8344; the NO-OP bug documented at :6345-6352);
  - mask resets (_cache_predates_reset :5902-5927; reset_evidence_pending :1946-1964);
  - re-date quota through prev (:1814-1816);
  - falsify the `cached Ns` header.
- **C6: gates stay on measured counts.**
  - `row["k"]` and heal's `k_live` stay ps-measured until Phase 3. The readers: heal :1406 and :1431; handoff-fire's relogin gate reads `.k`; inherit_k docstring :2247-2258.
  - Never write an inherited or locally refreshed count into `row["k"]`.
- **C7: routing on quota.** An errored row is admitted only through `_throttle_admitted`, at 90 s or less (:4840, :4852-4865). A local auth flip alone must never make a row routable on old quota.
- **C8: recorders run only on sweeps.** The local pass never calls record_utilization, watch_resets or log_route_decision. save_lastgood is called only through D6's first read.
- **C9: launchd.** A new job needs all of the following:
  - its plist in launchd/staged/;
  - ProcessType Standard, with no LowPriorityIO;
  - a perl pre-exec alarm;
  - a declaration in fleet.manifest, with the cc-fleet count moved in the same commit;
  - installation by a c10 migration that the operator runs;
  - a kill switch;
  - shell code that is `/bin/bash` 3.2-safe.
- **C10: keychain split.** `no-keychain-item` is a real logout. `keychain-error` is an instrument failure and never becomes OK or logged-out.
- **C11: shared board artifact.** No per-reader facts, and no relative ages that rot inside the file (use clock times). The hook owns only the file's age (accounts-board.sh:41-45).

## 3. Design

D1-D2 ship as **Land A**; they are code-only and go live on converge. D3-D9 ship as **Land B**. D9's job goes live only when the operator runs migration 0063.

### D1 Native census (W1)

**Opt-in through config.**
- Add a NEW top-level key to the repo-tracked `accounts.json`: `"census": "ab"`, plus a `"_census"` doc string. The file is symlinked as `~/.claude/accounts.json`, so the key goes live on converge; this is not C10.
- Put it at top level, not under `"router"`. Fixtures copy `r["router"]` wholesale (tests/claude-accounts-schema-drift.bats:44-60), and the key must not reach them.
- Do not add it to `accounts.json.example`: desk-strand-replay.bats:23 runs against that file.

**Mode resolution, `_census_mode(cfg)`.** Precedence:
1. env `CC_ACCOUNTS_CENSUS` (`ps` or `ab`);
2. the sentinel `<local_dir>/census-ps`, which forces `ps`;
3. `cfg.get("census")`;
4. the default, `"ps"`.

`local_dir` is `$CC_ACCOUNTS_LOCAL_DIR`, else `~/.claude/state/accounts-local`. Because the default is `ps`, every existing fixture runs byte-identical to today. That makes the change hermetic by construction: the 27 `ca.concurrency = lambda` stubs and every CLI-level suite need no edits. A Phase 3 `native` mode is out of scope.

**Refactor concurrency() (:642-768) without changing behaviour.**
- Extract the classifier loop (:699-753) and the registry join (:754-768) into `_census_from_lines(cfg, entries)`, where `entries` yields `(line, home)` pairs.
- The ps path passes `home=None` (module `HOME`), so the ps path stays byte-identical.
- Refresh the docstring's "Not currently at risk" paragraph with today's measurement.

**`native_census(cfg) -> _Census | None`.** The returned object carries `.meta = {ms, cpu_ms, reason, tty_pop, reads}`.
- **Lazy loading.** `import ctypes`, `CDLL("/usr/lib/libproc.dylib")` and `CDLL(None)` all happen inside the function and are cached in a module global. Nothing is added at module scope (C2).
- **Process selection.** Call `proc_listallpids`, then `proc_pidinfo(pid, 3 /*PROC_PIDTBSDINFO*/)`. Keep processes with `pbi_uid == os.getuid()` and `e_tdev != 0xffffffff`. That is exactly the set `ps -wwEo` lists without `-a`/`-x`.
- **Which argv to read.** Read argv for any process where `pbi_comm` starts with `claude`, or `pbi_comm == "node"`, or `"claude" in proc_pidpath(pid)`. The last test covers versioned native binaries whose comm is a version string. Add every registry pid that is alive with a matching start time.
- **Parsing and classification.** Use KERN_PROCARGS2 (`sysctl` mib `{1, 49, pid}`): the first 4 bytes are argc, then exec_path, then argc argv strings, then env.
  - Build `"<pid> " + " ".join(argv + env)` and classify it through `_census_from_lines` with `home=` that process's own `HOME=` env value.
  - A `CLAUDE_CONFIG_DIR=~/…` value expands against that same HOME.
  - Per-process HOME is what keeps a scratch-HOME fixture from counting host sessions. In production every session's HOME equals the module's HOME, so the result equals ps.
- **Fail closed: return None with a `reason` when any of these hold.**
  - libproc or ctypes failed to load.
  - `listallpids` returned 0 or less.
  - The tty population is 0.
  - `time.thread_time()` used more than 1.0 s of CPU (measured: user 0.03-0.04 s for the whole census process).
  - Wall time exceeded 10 s.
  - **Registry canary:** a live, start-time-verified registry pid with `entrypoint != "sdk-cli"` and a tty that the scan did not read or did not attribute. Log those pids.
- **Validated by the synth slot** (`python3 -I /tmp/synth-probe/cmp4.py 1 --ps` at load 738): libproc took 354 ms against ps's 9,285 ms, and both found the same pid set, `{next:2, next2:3, next3:31, next4:2}`. Re-runs took 35.9 ms and 211.1 ms.
- **Registry alone was rejected:** 3 live `--agent-id` teammates had no `sessions/<pid>.json`.

`struct proc_bsdinfo`, field order (VERIFIED working in that probe). The total size must equal what `proc_pidinfo` returns:
```
u32 pbi_flags, pbi_status, pbi_xstatus, pbi_pid, pbi_ppid, pbi_uid, pbi_gid, pbi_ruid, pbi_rgid,
    pbi_svuid, pbi_svgid, rfu_1; char pbi_comm[16]; char pbi_name[32]; u32 pbi_nfiles, pbi_pgid,
    pbi_pjobc, e_tdev, e_tpgid; i32 pbi_nice; u64 pbi_start_tvsec, pbi_start_tvusec
```

**Placement inside concurrency() when the mode is `ab`.**
- Start native_census on a daemon thread before the ps subprocess. Join it after ps returns or fails, bounded at 10 s from the native start. Running concurrently means no added serial time, and the native result survives a ps failure.
- Publish the result through the module global `_NATIVE_LAST`. collect() sets it to None before calling concurrency() and reads it afterwards.
- concurrency()'s return value and its None contract are unchanged. A stubbed `ca.concurrency` never sets `_NATIVE_LAST`, so stubbed suites stay hermetic. The adversarial review's two placement fixes conflicted: one wanted a serial prefix, the other a pool task. This placement satisfies both.

**Per-sweep log line** (counts only, never argv or env):
```
census-ab: ps={..}|UNAVAILABLE native={..}|None(<reason>) agree=yes|no|n/a ps_ms=N native_ms=N native_cpu_ms=N
```

**`claude-accounts --census-ab-report`** (read-only; parses claude-accounts.log). It prints:
- the window in days;
- the line count and the ps-OK count;
- the exact-agreement rate among ps-OK lines, and the maximum absolute per-account difference;
- native-None counts by reason;
- native_ms p50/p90;
- a verdict line: `soak: PASS` when there are ≥7 days, ≥500 ps-OK lines, ≥99% exact agreement and a maximum difference of 1 or less; otherwise `soak: NOT-YET (<which criterion>)`. The ps-OK denominator is always printed.

### D2 Router charge (W1)

- **collect (:2531-2636).**
  - Stamp `k_as_of`, the ps scan's start epoch, when ps succeeded.
  - From `_NATIVE_LAST`, set `k_native` and `k_native_as_of` (the native scan's start epoch) on each row.
  - `row["k"]` and the probe's `k_live` stay ps-only (C6).
  - bound_kwork (:2985) gets the ps census, falling back to native. It only ever tightens; today a None census leaves k_work unbounded.
- **k_panes (:3061)** chooses, in order:
  1. `k_native`, when all of these hold: env `CC_ACCOUNTS_CENSUS != ps` (an os.environ lookup only; no file I/O on the launch path), its age is within the grace, and either row `k` is None or `k_native_as_of > k_as_of + 60`;
  2. row `k`;
  3. `k_stale` within the grace;
  4. None.
- **k_src (:3121)** returns `panes-native` when choice 1 wins. k_cap falls through to the resident cap, unchanged.
- **k_shown (:3107)** shows a native count unstarred, because it is a measurement. An inherited count stays `N*`.
- **_excluded (:4907, :4976)** is unchanged: `concurrency-unmeasured` still fires when no instrument produced a count within the grace. Section 15's rule that UNKNOWN refuses is kept.
- **inherit_k (:2272-2274)** dates a measured previous `k` by `pr.get("k_as_of")` and falls back to `prev["ts"]`. The grace then runs from the measurement, not from the end of a 20-100 s sweep.
- **_prev_snapshot (:6110-6131).** Add `"k_as_of"` on the `"quota_as_of", "stale_quota",` line ONLY. Leave the line `"k", "k_stale", "k_stale_as_of")}` byte-identical: tests/claude-accounts.bats:326-332 runs a mutant that seds exactly that line.
- **route-meta (:8718-8730)** adds `k_native_s=<age>`.
- **record_utilization (:6025)** adds `k_native` and `k_native_as_of`.
- **scripts/desk-strand-replay.py (:93-105)** carries those two fields into replay rows, so a `panes-native` record replays as charged rather than as unmeasured.

### D3 Provenance stamps (W2)

probe_account (:2294) sets:
- `auth_as_of`: the epoch just before read_creds (:2303);
- `rt_fp`: `_rt_fingerprint(refreshToken)` (:1630), when a refresh token is present;
- `quota_read_at`: the epoch, set on HTTP-200 reads only.

`quota_as_of` is NOT reused, because it means "inherited" (:1788-1790, :1814-1817). The top-level fields are unchanged (C5). A helper, `_as_epoch(v)`, accepts either an ISO string or a number.

### D4 Write coordination (W2)

- **`<cache_file>.wlock`.** Every cache writer and every board writer holds it for the critical section only:
  1. serialise the JSON before acquiring;
  2. acquire;
  3. re-read or re-stat as the rule requires;
  4. `os.replace` (and `os.utime` where needed);
  5. release.

  There is NO write-anyway bypass. The waits are:
  - **Sweep commit:** blocks, bounded at 65 s, which is the local pass's 60 s SIG_DFL alarm plus a margin. On expiry it logs `wlock wedged` and writes anyway; that is unreachable unless a holder survives SIGALRM.
  - **Local pass:** 2 s, then it skips the write for that pass.
  - **Board writers:** `LOCK_NB` with a 5 s retry, then skip and log.
- **`cache_commit(cfg, payload)`** replaces the `cache_write` call at get_data :6369. Under the wlock it:
  1. loads the overlay (D5), ignoring it on a `cfg_key` mismatch or when `local_ts` is more than 600 s old;
  2. applies `apply_local_overlay` rules (a)-(d) to a DEEPCOPY of the payload rows (never rule f);
  3. writes the cache;
  4. returns the merged rows.

  get_data still returns the sweep's own rows to its caller, so `--fresh` and `--json` stay pure measurement (:6175; bin/cc-relogin:201-209).
- **save_lastgood (:1730) becomes a merge.** It takes a flock on `LASTGOOD_PATH + ".lock"`, re-reads the ledger on disk, keeps the entry with the newer `quota_as_of` for each account, then does `os.replace`.
- **Pollstate.** The pollstate sidecar's load-modify-save (:1854-1872, note_usage_429/ok :1899-1915) runs under a flock on `<pollstate>.lock`. The threading.Lock at :1847 stays, for threads.
- **Per-account poll lock, `<cache_file>.poll-<acct>.lock`.**
  - probe_account holds it around fetch_usage, waiting at most 12 s (the fetch timeout) and then proceeding without it, so a sweep never stalls.
  - first_read takes it with `LOCK_NB`, and stays pending if it is held.
- **Cache-only readers get `want_heal=False`.** get_data's first cache_read (:6290) passes `want_heal=False` when `max_wait is not None and max_wait <= 0`.
  - A cache-only reader can never heal, so the no_heal refusal (:5952-5954) only ever made the launcher abstain on a `cc-relogin --fresh --no-heal` cache that had any errored row.
  - This is an in-memory boolean with no I/O. It also makes the synth design's rule (g) unnecessary.

### D5 Local overlay (W3)

**File:** `/tmp/claude-accounts-local.json`, derived from cache_file the same way board_path is (:6062-6080), by swapping `-cache.json` for `-local.json`. Its single writer is `--local-refresh`, serialised by `<cache_file>.local.lock`.

**Schema:**
```
{v:1, cfg_key, local_ts,
 census:{as_of, counts, headless, ms, reason},
 auth:{acct:{as_of, kstate, verdict, rt_fp, login_expires_at, login_expired}},
 first_read:{acct:{read_at, rt_fp, fields}}}
```
`auth.as_of` is the last time the item's state was confirmed: by a definitive read, or by an unchanged keychain identity since one.

**`apply_local_overlay(rows, overlay, payload_ts, writer)`.** Each rule applies only when the overlay stamp is newer than the row's matching stamp (`auth.as_of` against `auth_as_of`; `census.as_of` against `k_native_as_of`).
- **(a) Census.** Set `k_native` and `k_native_as_of`. Never touch `k`.
- **(b) T1, logout.** Applies when kstate is `no-keychain-item` and the row's auth is not `logged-out`.
  - Set `auth = error = "logged-out"` and `stale_quota = True`.
  - Keep `quota_as_of` if the row is already stale. Otherwise set it to `iso(quota_read_at or payload_ts)`.
- **(c) T2, recovery.** Applies when the row's auth is `logged-out` or `no-oauth-blob`, or is `login-required` or `token-invalid` with `rt_fp` different from the row's, AND the local verdict is `ok` or `stale`.
  - Set auth from the verdict, plus `rt_fp`, the `login_*` fields and `auth_recovered_at`.
  - Set `error = "quota pending — logged in HH:MM, first read not landed"`. Any errored row is data class, so this exits 3 (reason_class :5881-5883). The text avoids `throttled` and `cached`, which bin/cc-lr:897-899 and lr-move-batch.sh:178-180 string-match.
  - Clear `poll_throttled`, so a pending row is never throttle-admitted.
  - Keep `stale_quota`, `quota_as_of`, `lastgood_*` and `wire*`.
- **(d) T4.** On an ok row whose `rt_fp` changed, refresh the `login_*` fields and `rt_fp`.
- **(e) No change for failed observations.** A local keychain-error or timeout changes nothing, and sweep rows in `keychain-error` or `probe-error` are never recovered by T2.
- **(f) First read applied — `writer == "local"` only, never inside cache_commit.** Applies only when ALL of these hold:
  - `row.error` is exactly the pending marker;
  - `first_read[acct].rt_fp == row.rt_fp`;
  - `read_at >= payload_ts`;
  - `read_at >= max(quota_read_at, quota_as_of, wire_at)`.

  Then:
  - copy the fields;
  - re-derive each covered `*_reset_h` as `hrs_until(*_reset_at)`, and drop `rolled_since` and `reset_evidence` for the covered buckets;
  - set `quota_read_at = read_at` and `quota_src = "first-read"`;
  - drop `stale_quota`, `quota_as_of`, `lastgood_*` (except `lastgood_wire_rejects`), `poll_throttled` and `usage_held_s`;
  - clear `error`.

  Leave `wire*` and `lastgood_wire_rejects` alone: the veto conservatively stays until a sweep.
  - **Why this is bounded:** since `read_at >= payload_ts`, the hidden age is never more than what the cache `ts` already declares.
- **After any rule:** recompute `auth_actionable` and `login_fixable` on touched rows (:2633-2635).
- **Never touched by the overlay:** `ts`, `window`, `prev`, `no_heal`, `cfg_key`, and `*_reset_h` (except via rule f).

### D6 First read after a login, and the sweep reuse guard (W3)

**`first_read(cfg, name, token, rt_fp, at_fp)`.**
- **When it runs.** The local pass calls it only for rows carrying the pending marker whose local verdict is `ok`. It never runs on `stale`: an expired access token gets a 401, so that case is left to the sweep's heal.
- **Gates, in order:**
  1. The kill switch, `CC_ACCOUNTS_FIRST_READ=off` or `<local_dir>/first-read-off`.
  2. An attempt memo in the local state file, keyed on `at_fp = sha256(accessToken)[:16]`. The next attempt waits at least 90 s after any attempt; after a non-200 the wait doubles, capped at 600 s.
  3. The per-account poll lock, taken with `LOCK_NB`.
- **The shared backoff is not a gate.** `usage_backoff_left` (:1887) is NOT consulted, because it may have been earned by the old token (the budget is per token, :1833-1836).
- **The call:** `fetch_usage(cfg, token, retries=0)` (:1185). Outcomes:
  - **200:** fill the row with `_fill_quota(row, body)`, which is factored out of probe_account's 200 branch (:2478-2491) so both paths are identical. Build the ledger entry with `_ledger_entry(row, read_at)`, setting `quota_as_of = iso(read_at)`, and persist it through the D4 merge. Write `overlay.first_read[name]`. Call `note_usage_ok(name)`.
  - **429:** call `note_usage_429(name)`; the new token is throttled now.
  - **Anything else** (timeout, URLError, 401, 5xx): update the memo only; shared state is untouched.
- **Never called from first_read:** probe_account, fetch_wire_limits, heal, record_utilization, watch_resets.

**Sweep reuse guard in probe_account**, before the usage gate (:2405-2412).
- collect loads the overlay once and passes `first_reads=` as a new kwarg defaulting to None, so existing callers are unchanged.
- **Condition:** `first_reads[name].rt_fp == rt_fp`, and `now - read_at <= REPOLL_MIN_S`. REPOLL_MIN_S is 90 (env `CC_ACCOUNTS_REPOLL_MIN_S`).
- **Effect:** fill the row from the first read with no fetch.
  - `quota_read_at = read_at`, never now;
  - `quota_reused = True`;
  - the ledger entry gets `quota_as_of = iso(read_at)`.
- record_utilization (:5979) writes `quota_reused` rows with `stale: true`, so `_util_tail` drops them and no duplicate burn sample is recorded.
- The hidden age is at most 90 s plus the rest of the sweep. That is inside the measured drift band THROTTLE_ADMIT_S rests on (:4833-4840).

**Pruning.** Prune `overlay.first_read[name]` once a committed cache row has `quota_read_at >= read_at`, or once `read_at` is more than 600 s old.

### D7 `claude-accounts --local-refresh` (W3)

A branch in main() beside `--keepwarm` (:8300). It is a flag on the symlinked binary, so it rides converge (:8306-8311).

**Steps:**
1. **Setup and kill switch.** `mkdir -p` the local dir. If `CC_ACCOUNTS_LOCAL=off` or `<local_dir>/off` exists: touch the stamp, print exactly `local: disabled`, and exit 0. The stamp is `~/.claude/logs/accounts-local.stamp`, overridable with `CC_ACCOUNTS_LOCAL_STAMP`. Load cfg without resolving the claude binary.
2. **Single instance.** Take a flock on `<cache_file>.local.lock` with `LOCK_NB`. If it is held, touch the stamp, print `local: busy` and exit 0. Arm SIGALRM SIG_DFL at 60 s (`CC_ACCOUNTS_LOCAL_DEADLINE_S`). The budget is the deadline minus elapsed time.
3. **Census.**
   - If the mode is `ps`, schedule removal of `k_native` and `k_native_as_of` from cache rows; this is the rollback path.
   - Otherwise run `native_census(cfg)`, and write `overlay.census` atomically right away, before any keychain work.
   - Commit it to the cache through step 7 if the counts differ from the cached `k_native`, or the cached `k_native_as_of` is more than 120 s old.
4. **Auth, in two tiers.**
   - Stat `login.keychain-db` for `(st_ino, st_mtime_ns)`. If it is unchanged and the last attribute check was less than 300 s ago, reuse the stored metadata, re-deriving stale/ok and `login_expired` against now.
   - **Tier 1, otherwise.** Read attributes with `/usr/bin/security find-generic-password -s <svc> -a <kc>`. NO `-w`, never `-g`. Run the 4 reads on daemon threads, joined with an 8 s deadline.
     - rc 44 means `no-keychain-item`: a T1 candidate, with no secret read.
     - Otherwise parse cdat and mdat.
   - **Tier 2.** Do a secret read (read_creds, under the same daemon-thread deadline) only for items that appeared or whose cdat or mdat changed.
   - **Storage.** Write per-item metadata to `_sidecar(".local-state.json")` (mode 0600): `{cdat, mdat, present, expiresAt, refreshTokenExpiresAt, has_rt, rt_fp, at_fp, checked_at}`. Never store a token.
   - **Identity advance.** Advance an item's stored identity only on a definitive result: present and parsed, or no-keychain-item. A timeout or error is a keychain-error observation (rule e) and is retried on the next pass.
5. **Read the cache.** Read it TTL-ignored and cfg-key-checked, the same read `_prev_snapshot` does. If it is absent or the key mismatches, write the overlay and exit; the pass never creates a cache.
6. **Classify and record.** Classify T1, T2 and T4 per row (D5). Write `overlay.auth` atomically.
7. **Cache write**, on any transition or for step 3's census commit:
   1. serialise;
   2. take the wlock (2 s bound, else skip and log);
   3. re-read under the lock;
   4. run `apply_local_overlay(..., writer="local")`;
   5. CAS: the cache's `(st_ino, st_mtime_ns)` must be unchanged since the under-lock read;
   6. `os.replace`, with `ts`, `window`, `prev`, `no_heal` and `cfg_key` exactly as read.
8. **First read** (D6), for pending rows with verdict `ok`, only if at least 15 s of budget is left. On a 200, repeat step 7; rule (f) then applies.
9. **Prune** `overlay.first_read`.
10. **Board** (D8), only if at least 15 s of budget is left.
11. **Re-check the keychain.** Re-stat `login.keychain-db`. If it moved after step 4 began and at least 15 s of budget is left, loop once to step 4: launchd drops a WatchPaths fire that arrives during a tick (bin/cc-lr:1476-1478).
12. **Finish.** Touch the stamp. Print one `local: …` line on any transition, first read, render or failure, plus a heartbeat every 10 min.

**Never called by the pass:** heal, fetch_wire_limits, record_utilization, watch_resets, log_route_decision, ps, and the single-flight `<cache_file>.lock`.

### D8 Board (W4)

- **write_board** (:6083) becomes `write_board(cfg, lines, sig=None, keep_mtime=False, rendered_from_ts=None)`, run under the wlock (`LOCK_NB`, 5 s retry, else skip and log).
  - It does the `os.replace`, then writes `<board>.meta.json` with `{sig, rendered_from_ts, producer, at}`. The hook never reads the meta file.
  - With `keep_mtime`: `os.utime` the tmp file to the existing board's `(atime, mtime)` before the replace. If no board exists, return None and never create one. Abort if the cache `ts` is no longer `rendered_from_ts`.
- **keepwarm** (:8361-8365), after get_data, re-reads the cache (TTL-ignored, cfg-key-checked) and renders from a deepcopy of THOSE rows. Those are the overlay-merged rows cache_commit wrote; if the read fails it falls back to get_data's rows.
  - It still stamps the board's mtime as now. That mtime is the hook's producer-liveness signal (accounts-board.sh:41-45, :146-190).
  - This closes "keepwarm overwrites a newer local board".
- **`_board_sig(rows)`** is a per-row tuple `(acct, auth, "error" in r, k_shown(r))`, computed from the cache rows.
- **Local re-render.** The local pass re-renders through a factored `_render_board(cfg, rows, wj, cached)` (refresh_login_countdown, apply_assignments, apply_burn, `readout_lines(narrow=True)`) on a deepcopy, so `k_phantom` and `burn_*` never reach the cache.
  - **When it re-renders:** when the cache sig differs from the meta sig. An auth or error difference re-renders at once. A difference only in k re-renders at most once per 60 s, and only when `os.getloadavg()[0] / ncpu <= 10`.
  - **How:** `keep_mtime=True`, so a dead keepwarm still reads STALE and then gets withheld by the hook's mtime bands, exactly as today.
- **readout_lines(narrow)** (:7029, header :7085-7099) gains one footer line of clock times only: `auth/live HH:MM:SS · quota HH:MM:SS`. The first time is `max(auth_as_of, k_native_as_of)`; the second is `ts`.
- **The pending row's board note:** `next3 · logged in HH:MM; quota read pending, excluded from routing`.
- **`_util_tail` (:3588) gets a per-process memo.**
  - It is enabled only in `--keepwarm`, `--local-refresh` and `--readout`, and is off in `--route` and `--rank`.
  - Key: `(path, hours, size, mtime_ns of the path and its .gz siblings)`.
  - A request whose `hours` is no more than the cached `hours`, with the same file identity, is served by filtering the cached rows by its own cutoff (as dict copies). The achieved span is recomputed by the function's own rule.
  - This removes the second 16 MB parse per render: apply_burn reads 336 h (:3787), fleet_pace_line 72 h (:4725), and cProfile put `_util_tail` at 1.22 s of a 1.51 s render.

### D9 launchd job and migration (W5)

**`launchd/staged/com.claude.accounts-local.plist`.**

| Key | Value |
|---|---|
| ProgramArguments | `/bin/bash -c 'export PATH="$HOME/.claude/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"; exec /usr/bin/perl -e '\''alarm shift; exec @ARGV or die "exec: $!"'\'' 120 "$HOME/.claude/bin/claude-accounts" --local-refresh'` (the keepwarm idiom, plist :118) |
| StartInterval | 20 |
| RunAtLoad | true |
| WatchPaths | `[/Users/chrisren/Library/Keychains/login.keychain-db]` |
| ThrottleInterval | 10 |
| ProcessType | Standard, with no LowPriorityIO |
| StandardOutPath | `/Users/chrisren/.claude/logs/accounts-local.out.log` |
| StandardErrorPath | `/Users/chrisren/.claude/logs/accounts-local.err.log` |

The header comment covers:
- the `ts` contract;
- the floor-plus-accelerator rationale: WatchPaths is race-prone (`man launchd.plist`), and FSEvents went dark on 2026-09-08;
- the kill switches;
- the install line and the uninstall line, `launchctl bootout gui/$(id -u)/com.claude.accounts-local; rm ~/Library/LaunchAgents/com.claude.accounts-local.plist`.

**Other files in the same commit:**
- **launchd/fleet.manifest**, a new row beside :445 with a comment block: `com.claude.accounts-local | staged | 20 | ~/.claude/logs/accounts-local.stamp | - | 0063-accounts-local-job.sh`. This follows the 0051 and 0058 precedent of naming the migration. cc-fleet resolves recover_cmd under `docs/activation/pending-activation/`, so the comment carries the real command.
- **tests/cc-fleet.bats:700-706**, count 52 → 53, with a dated comment.
- **config/store-bounds.manifest**, the row `logs/accounts-local.*.log|5|-|append-only diagnostics; truncate with : > ~/.claude/logs/accounts-local.out.log (the stamp is the liveness evidence)`.

**`migrations/0063-accounts-local-job.sh`.** Re-check the number at land with `git log --all --name-only -- 'migrations/006*'`; 0061 and 0062 are taken by checkpoint commits.

Header:
```
# migration-class: c10
# migration-step: load com.claude.accounts-local (the 20 s local auth + live-session refresh for the account board and router), installing it from launchd/staged; launchctl is machine-wide, so this is yours
# migration-run: bash ~/Development/claude-infrastructure/migrations/0063-accounts-local-job.sh --confirm launchd
# migration-subject: ~/Development/claude-infrastructure/launchd/staged/com.claude.accounts-local.plist
# migration-verify: launchctl print gui/$(id -u)/com.claude.accounts-local 2>/dev/null | grep -q 'run interval = 20' && [ $(( $(date +%s) - $(stat -f %m "$HOME/.claude/logs/accounts-local.stamp" 2>/dev/null || echo 0) )) -lt 600 ]
# migration-batch-hold: manual — boots a LIVE launchd job; launchctl is machine-wide and the batch's scratch-HOME rehearsal cannot sandbox it
```
Notes on the header:
- The subject is the repo arm, so the oracle reads `staged-pending` while waiting, not `not-staged` (registration-state.sh:186-194).
- The verifier is config-dir-invariant.

Body (modelled on 0059 :53-99 and 0055 do_reload :170-200):
1. Dry run is the default; `--confirm launchd` acts.
2. **Precondition:** `CC_ACCOUNTS_LOCAL=off "$HOME/.claude/bin/claude-accounts" --local-refresh` must print exactly `local: disabled`. It refuses otherwise, and it never runs a real pass.
3. `mkdir -p ~/.claude/state/accounts-local`.
4. If the plist is identical (cmp) and the job is loaded, skip.
5. Back up the live plist, then cp to a tmp file and mv into place.
6. Never boot out a running tick: wait up to 130 s for `state != running`, else exit `busy: re-run`.
7. Boot out if loaded, wait with a bound, then bootstrap `gui/$(id -u)`.
8. Read back with `launchctl print` (state, run interval 20), then wait up to 60 s for the stamp to advance.
9. On success, print the follow-up: "agent: flip the fleet.manifest row staged→run".

Seams: `CC_0063_LAUNCHCTL`, `CC_MIGRATION_LA_DIR`, `CC_0063_CA_BIN` and a scratch HOME.

### Why the protected paths add zero latency and zero tokens

- **SessionStart.** The SessionStart files have no diff. The board is still one file, replaced atomically; the meta sidecar is never read.
- **Launch.** The launcher has no diff. On the binary's `--route`/`--rank` path the only deltas are:
  - in-memory field choices in k_panes, k_src and k_shown (os.environ lookup, dict gets over 4 rows);
  - a boolean in get_data's first cache_read;
  - about 600 extra bytes of JSON stamps, estimated at roughly 0.04 ms by scaling the measured 0.266 ms per 3.9 KB load.

  There are no new imports (ctypes is lazy), opens, locks, forks or network calls. The util memo is off. A bats audit hook proves this (§5).
- **Tokens.** No wire call is added. The first read is an OAuth usage GET, at most one per token per 90 s or more.

### Freshness targets

| Fact | Target | Basis |
|---|---|---|
| Auth (logout, /login, relogin) in the cache and router | ≤ 30 s worst case; about 10-15 s when WatchPaths fires | ESTIMATED: 20 s floor + pass. A no-change pass costs about 0.1-0.15 s CPU (measured parts: census user 0.03-0.04 s, compile user 0.04-0.05 s). Its wall time is 0.4-1.5 s at load 620-780. A rendering pass takes 8-9 s wall at load 650 (measured `--readout` real 8.13-9.07 s), so ticks slide to about 30-40 s while renders run. |
| Re-logged account becomes routable | detection + one usage GET (12 s timeout; typically 0.5-3 s) | ESTIMATED. It never routes on pre-logout quota. |
| Live-session count used by the router | ≤ 20 s + pass with the job running; otherwise the sweep's own native census | Measured 36-354 ms in a fresh process at load 620-780, against ps at 9.3-10.2 s. |
| Board | the next pass after the cache commit; routing never waits on the board | |
| Quota | unchanged by design | keepwarm 180/90; launcher ≤600 s; cc-route ≤90 s |
| 17:33 replay | Land A alone: at 22:34:04Z, next, next2 and next4 rank on quota instead of pinned. With the job: next3 routable by about 22:33:50Z, before the launch. | INFERRED |

## 4. Waves and tasks

Every acceptance check below is a command whose output is the proof. For bats, "green" means the `1..N` plan line equals the count of `^ok ` lines. Run suites serially: GNU parallel is absent, so `--jobs` executes 0 tests.

Helper (define once per shell):
```
bg(){ out=$(bats "$1" 2>&1); n=$(printf '%s\n' "$out" | sed -n 's/^1\.\.\([0-9]*\)$/\1/p'); ok=$(printf '%s\n' "$out" | grep -c '^ok '); echo "$1 plan=$n ok=$ok"; [ -n "$n" ] && [ "$n" = "$ok" ] || printf '%s\n' "$out" | grep -A5 '^not ok' | head -40; }
```

### W0 — DONE 2026-10-11 (compacted)

- Worktree: the recycled session's own `~/Development/.worktrees/feat/accounts-freshness` on `feat/accounts-freshness` (in place of T0.1's path). `BASE=dcf7c53d6`; plan copied in as `6edb6b4e5`.
- 0063 is free (0060-0062 taken).
- Baselines (load 367): hook p50 180.1 ms, max 265.1 ms; `--rank` real 1.72-1.81 s; interactive `none` with 3+ `concurrency-unmeasured`: 11 on 2026-10-11; `ps UNAVAILABLE` lines: 121 on 2026-10-11 (UTC dates).
- Learnings: at load ~420 `ps -axo` itself did not return within 120 s, and a probe sat in `os.waitpid` reaping a killed `ps` for minutes — the sweep's `ps` can outlive its 10 s timeout by far more than the timeout. The native census measured 14-119 ms with 362 tty processes and 83 argv reads at load 449. cc-bats refuses admission while 2 other roots run and load is high; the runner retries rather than waives. The launch-path open set measured identical on BASE and HEAD, and is wider than §5 lists: `{accounts.json, assign ledger, cache, util log}`, plus `route.jsonl` for `--route`.

### W0 — setup and baselines (L)

- **T0.1** `git -C ~/Development/claude-infrastructure fetch origin && git -C ~/Development/claude-infrastructure worktree add ~/Development/.worktrees/accounts-freshness -b feat/accounts-freshness origin/main`
  - Accept: `git -C ~/Development/.worktrees/accounts-freshness status -sb` prints `## feat/accounts-freshness`.
  - Record `BASE=$(git -C ~/Development/.worktrees/accounts-freshness rev-parse HEAD)`.
- **T0.2** `git -C ~/Development/claude-infrastructure log --all --name-only --format= -- 'migrations/006*' | sort -u`
  - Accept: 0063 is absent; otherwise take the next free number everywhere it appears in this plan.
- **T0.3** Baselines. Write them to `/tmp/af-baseline.txt`, not to the repo.
  - **Hook:**
    ```
    python3 -I -c 'import subprocess,time,statistics,os;e=dict(os.environ,DL_DIR="/nonexistent");t=[]
    for _ in range(20):
     s=time.perf_counter();subprocess.run(["bash",os.path.expanduser("~/.claude/hooks/accounts-board.sh")],input=b"{\"source\":\"startup\",\"cwd\":\"/tmp\"}",stdout=subprocess.DEVNULL,env=e);t.append((time.perf_counter()-s)*1000)
    print(f"hook p50={statistics.median(t):.1f}ms max={max(t):.1f}ms load={os.getloadavg()[0]:.0f}")'
    ```
  - **Launch proxy** (use `--rank`, never `--route`, which appends to route.jsonl): `for i in 1 2 3; do /usr/bin/time -p ~/.claude/bin/claude-accounts --rank interactive --max-wait 0 --max-age 600 >/dev/null; done 2>&1 | grep real`
  - **Abstentions:** `jq -r 'select(.slot=="interactive" and .outcome=="none") | select([.excluded[]?|select(.=="concurrency-unmeasured")]|length>=3) | .ts[0:10]' ~/.claude/route/route.jsonl | sort | uniq -c | tail -7`
  - **ps failures per day:** `grep 'concurrency: ps UNAVAILABLE' ~/.claude/logs/claude-accounts.log | cut -c1-10 | uniq -c | tail -7`

### W1-W4 — implemented 2026-10-11/12 (compacted; detailed tasks kept below for reference)

- Commits on `feat/accounts-freshness`: W1 `34107d4a5` (+ fixup `3acd8adc3`), bounded ps reap `9d5bb554f`, W2 `a9a20bae9`, W3+W4 `09f80c8c9`. Land A ships W1 + the reap fix from branch `feat/accounts-freshness-a` (worktree `~/Development/.worktrees/af-w1-test`), so W2 stays off trunk until Land B.
- **Scope (grown): +bounded ps reap.** Measured 2026-10-12 at load 330: `ps` "timed out after 10 seconds" yet `concurrency()` returned after 1,226 s, because `subprocess.run` waits unbounded for a SIGKILLed `ps` stuck in the kernel. In `ab` mode that stamped the native count 20 min stale, past its grace, defeating D1-D2. `_ps_census` now runs on a daemon thread joined at `PS_JOIN_S` = 15 s, which keeps every `subprocess.run` stub working.
- Live checks: native census 14-354 ms (362 tty processes, 80-83 argv reads, load 330-449); a live `--local-refresh` pass took 0.40-0.53 s wall, left cache `ts` byte-identical, made 0 usage polls, and its native counts equalled the cached ps counts exactly. Its first pass printed T4 for all four rows, which is expected: the live cache was written by pre-change code, so its rows had no `rt_fp`.
- Deviations from the text below, each deliberate:
  - The launch-path audit pins the measured open set `{accounts.json, assign ledger, cache, util log}` (+ `route.jsonl` for `--route`), identical on BASE and HEAD; §5 listed it without the assign ledger and route records.
  - The first-read prune is `quota_read_at > read_at` (strict), not `>=`: rule (f) and the reuse guard both set `quota_read_at = read_at`, so `>=` would prune the first read before the sweep's reuse guard could use it.
  - `_auth_verdict` mirrors probe_account: past the login cliff, or stale with no refresh token, is `login-required` (so T2 never recovers a dead login).
  - W3 and W4 are one commit: their edits interleave in one file and form one feature.
- bats admission: two research sessions re-took both cc-bats slots back to back for over 20 minutes, so runs use the wrapper's recorded waiver (`CC_BATS_MAX_ROOTS=0` with a reason), one suite at a time.

### W1 — native census and router charge, then Land A (L)

- **T1.1** Add the `accounts.json` `"census": "ab"` key and its `"_census"` doc, and `_census_mode()` (D1).
  - Accept: `jq -r .census accounts.json` prints `ab`; `jq -r .census accounts.json.example` prints `null`.
- **T1.2** The `_census_from_lines` refactor (D1).
  - Accept: `bg tests/account-fact-derivation.bats` and `bg tests/claude-accounts.bats` are green and unedited. The parity suite drives the real concurrency() with a fake subprocess.
- **T1.3** `native_census`: lazy import, selection, prefilter, procargs, per-process HOME, the fail-closed reasons and the canary.
  - Accept (live, read-only; prints counts only):
    ```
    python3 -I - <<'PY'
    import importlib.machinery as m, importlib.util as u, os
    p=os.path.expanduser('~/Development/.worktrees/accounts-freshness/bin/claude-accounts')
    l=m.SourceFileLoader('ca',p); ca=u.module_from_spec(u.spec_from_loader('ca',l)); l.exec_module(ca)
    ca.LOG_PATH='/tmp/af-probe.log'; cfg=ca.load_cfg(need_claude_bin=False)
    n=ca.native_census(cfg); print('native',None if n is None else dict(n), getattr(n,'meta',None))
    c=ca.concurrency(cfg); print('ps',None if c is None else dict(c))
    PY
    ```
    Expected: the native counts equal the ps counts (allow ±1 per account for churn between the two scans), and meta.reason is None. If they differ, stop and investigate before going on.
- **T1.4** In concurrency(): the ab thread, `_NATIVE_LAST` and the `census-ab:` log line. **T1.5** In collect(): the stamps, `k_native`, and the bound_kwork fallback. **T1.6** k_panes, k_src, k_shown, route-meta, record_utilization and desk-strand-replay.py. **T1.7** inherit_k dating and the `_prev_snapshot` line.
  - Accept: `bg tests/claude-accounts-census.bats` is green (§5). `bg` is green, with no edits, on each of: tests/claude-accounts-core.bats, tests/claude-accounts-parallel-collect.bats, tests/claude-accounts-freshness.bats, tests/claude-accounts-throttle-admit.bats, tests/claude-accounts-kwork-live-bound.bats, tests/claude-accounts-schema-drift.bats, tests/claude-accounts-wire-truth.bats, tests/cc-backlog-no-capacity-measured.bats, tests/desk-strand-replay.bats, tests/claude-launcher-router.bats and tests/accounts-board.bats.
  - Also check `grep -nE 'cp +[^ ]*accounts\.json' tests/*.bats`. Two hits are known: handoff-fire-launcher-map.bats:205 and keychain-account-narrowing.bats:75. If either suite runs the real binary with a failing census, pin `export CC_ACCOUNTS_CENSUS=ps` in its setup().
- **T1.8** `--census-ab-report`.
  - Accept: `bin/claude-accounts --census-ab-report` (worktree) prints a `soak:` line on the live log, and covered census-suite cases pass on fixture logs.
- **T1.9** Statics and gate selection.
  - Accept: `scripts/ship-land.sh --precheck --working` exits 0.
  - Then `scripts/gate-select.sh --explain --direct "$BASE"..HEAD` lists the suites the smoke would pick, and every one of them is green via `bg`.
- **T1.10** Land A: commit on the branch, then project-local `/ship`, then the §6 content check, then converge, then DoD 1-6.
  - File the Phase 3 item: `~/.claude/bin/cc-backlog add --project claude-infrastructure --title "Phase 3 ruling: make the native census gate-grade (heal + cc-relogin live_sessions)" --run "~/.claude/bin/claude-accounts --census-ab-report"`. The falsifier is that report's `soak:` line.
  - This is the **succession point** (Phase 0).

### W2 — stamps and write coordination (L)

- **T2.1** D3 stamps. **T2.2** The wlock plus `cache_commit`; until W3 lands, the overlay loader returns None. **T2.3** Ledger merge and pollstate flock. **T2.4** The per-account poll lock. **T2.5** Cache-only `want_heal=False`.
  - Accept: `bg tests/claude-accounts-local.bats` (W2 cases), plus a re-run of the W1 keep-green list. tests/claude-accounts-fresh-lock-bound.bats, tests/cc-relogin.bats, tests/cc-relogin-status.bats and tests/account-recovery-lane.bats must be green too.
  - Also: `git diff "$BASE" -- lib/claude-launcher.zsh hooks/accounts-board.sh hooks/session-start-dispatch.sh launchd/staged/com.claude.accounts-keepwarm.plist | wc -l` prints `0`.

### W3 — local overlay, `--local-refresh` and first read (L; the W5 teammate starts here)

- **T3.1** The overlay file and `apply_local_overlay` (D5). **T3.2** The `--local-refresh` verb (D7). **T3.3** `first_read`, the attempt memo, `_fill_quota` and `_ledger_entry` (D6). **T3.4** The sweep reuse guard and record_utilization's `quota_reused`.
  - Accept: `bg tests/claude-accounts-local.bats` (all cases in §5).
  - Also: `CC_ACCOUNTS_LOCAL=off bin/claude-accounts --local-refresh` prints exactly `local: disabled`.
- **T3.5** Live dry observation. No job is installed yet; this is one manual pass that writes only the overlay, the /tmp cache rows and the local state, and makes no network call when nothing transitions.
  - Command: `bin/claude-accounts --local-refresh; jq '{ts,local:(input|.local_ts)}' /tmp/claude-accounts-cache.json /tmp/claude-accounts-local.json`
  - Accept: the cache `ts` is identical before and after (capture it first with `jq .ts`), the overlay census counts equal T1.3's, and `grep -c 'fetch_usage\|usage poll' /tmp/af-probe.log` shows no poll.
  - Run this only from the worktree binary, with `CC_ACCOUNTS_FIRST_READ=off` set.

### W4 — board (L)

- **T4.1** write_board's lock, `keep_mtime` and meta. **T4.2** keepwarm renders from the committed cache. **T4.3** `_board_sig` and the local re-render gating. **T4.4** The footer line and the pending note. **T4.5** The `_util_tail` memo.
  - Accept: `bg tests/claude-accounts-local.bats` (board cases); `bg tests/claude-accounts-util-tail.bats` (the 5 existing cases plus the appended memo cases); `bg tests/accounts-board.bats` green and unedited (33 tests); `bg tests/claude-accounts-fleet-pace.bats`.

### W5 — job, migration and bookkeeping (T)

- **T5.1** The plist. **T5.2** The manifest row plus cc-fleet.bats 52→53 plus the store-bounds row, all in ONE commit with the plist. **T5.3** Migration 0063. **T5.4** tests/accounts-local-job.bats and tests/migration-0063-accounts-local-job.bats.
  - Accept: `bg` green on tests/accounts-local-job.bats, tests/migration-0063-accounts-local-job.bats, tests/cc-fleet.bats, tests/fleet-manifest-lint.bats, tests/install-staged-plist.bats, tests/deploy-migrations.bats (tests 4 and 6 included) and tests/store-bounds.bats.
  - Also: `plutil -lint launchd/staged/com.claude.accounts-local.plist` prints OK.

### W6 — gate, Land B, converge, verify (L)

- **T6.1** `scripts/ship-land.sh --precheck --working` exits 0. Every suite named in W1-W5 is green via `bg`, and so is the gate-select list for `"$BASE"..HEAD`.
- **T6.2** Land B via `/ship`, then the §6 content check, then converge, then DoD 7-11.
- **T6.3** Hand the operator O1 (§6). deploy-migrations files it into `cc-backlog needs` automatically from 0063's header; say it in the session close too.
- **T6.4** After the operator runs O1: DoD 12-16. Then land the manifest flip `staged`→`run` with a dated comment, keeping activate as `0063-accounts-local-job.sh`.

### W5-W6 — DONE 2026-10-12 (compacted)

- **One land, not two.** Land A and Land B shipped together as `82e2756cf` (range `931209017..82e2756cf`, 9 commits). Why: `ship-land.sh` lands the tree its working directory is in, and this harness resets the session's cwd to its primary worktree after every call, so a bare `ship-land.sh` could not run from the separate Land A worktree. Every W1-W5 suite was re-run on the exact shipped tree instead (30 suites, 697 tests, each `1..N` equal to its ok count). The plan's Land A succession point therefore did not occur.
- W5 by teammate jobwright, committed by the lead as `3a0ec60c5`. Three of its choices were accepted: the busy-wait runs BEFORE the install, so a "busy" exit never leaves new bytes beside an old loaded job; the stamp-advance check compares nanosecond mtime, because the precondition probe itself touches the stamp; and a dry run skips the CA probe, because the off-mode probe touches the stamp.
- Defects the gate or the keep-green run caught before landing: the census suite fixtured `HOME` only inside Python (hermeticity arm); 19 bash-3.2-dead `[[ ]]`/`!`/`&&` assertions (dead-assertion arm, auto-fixed plus 2 hand splits); and a new top-level `_iso_epoch` (epoch → ISO) silently shadowed the existing `_iso_epoch` (ISO → epoch), which aborted the transcript walk, so k_work went unmeasured (7 kwork-live-bound cases). It is now `_epoch_iso`, and the lesson is `docs/lessons/a-new-top-level-def-silently-shadows-a-same-named-helper.md`. Also hardened: with no `cache_file` in a config, the poll lock and the overlay path return None instead of falling back to the live `/tmp` files.
- Load-bound wall-clock cases (`claude-accounts-parallel-collect` 1-2, `claude-launcher-router` 24) failed at load 300-500 and failed identically on BASE (A/B in a BASE worktree); they pass at load ≤ 64.
- Converge: the land's own detached converge reached trunk tip `82e2756cf`; `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` confirmed "at trunk tip — nothing above the live layer". Live: `~/.claude/bin/claude-accounts` carries `def native_census`, and `~/.claude/accounts.json` says `census: ab`.
- Operator: O1 is backlog row `ddf3c6d8e1bb` (filed by deploy-migrations from 0063's header; `--run` is the `--confirm launchd` line). The Phase 3 ruling is row `e04527859ada` (blocked, not-yet-true; `--run` is `--census-ab-report`).
- DoD after the land: 1 PROTECTED-UNCHANGED (BASE..`82e2756cf`) · 2/3 census 14/14, including the audit-hook case (no ctypes; open set unchanged) · 4 all keep-green suites green, and the land's `tests/` diff is exactly §5's six files · 7 local 19/19 · 8 util-tail 8/8 · 9 accounts-local-job 4/4, migration-0063 6/6, cc-fleet 26/26, deploy-migrations 15/15, fleet-manifest-lint 20/20, install-staged-plist 6/6, store-bounds 23/23 · 10 `local: disabled` · 11 hook p50 56.8 ms at load 49 (baseline 180.1 ms at load 367; informational only). 5 and 6 are live observations recorded below as they arrive; 12-16 wait on O1.
- DoD 5, first live sweep under the new code (2026-10-12T06:57:05Z): `census-ab: ps={next:1,next4:1,next3:19,next2:3} native={next:1,next4:1,next3:19,next2:3} agree=yes ps_ms=710 native_ms=51 native_cpu_ms=27`; `--census-ab-report` prints `soak: NOT-YET` with its denominator, as expected on day 0. DoD 6 (72 h abstention count) is observational: re-run the T0.3 abstention jq filtered to `.ts >= "2026-10-12T06:55"` on or after 2026-10-15.
- DoD 5 addendum, the record §9 asked for: the first `ps=UNAVAILABLE` sweep that still carried native counts was 2026-10-12T16:52:27Z, `census-ab: ps=UNAVAILABLE native={next:2,next4:1,next3:17,next2:0} agree=n/a ps_ms=10489 native_ms=1022`. This is the incident's failure mode, now with a live count.
- **O1 done 2026-10-12 by the operator** (`0063 … --confirm launchd`: loaded, read back `run interval = 20`, stamp moved after 2 s). The fleet.manifest row was flipped `staged`→`run` in the same land as this note.
- **Scope (grown): +census re-commit below the tick.** DoD 15 measured live, in three windows: with D7's 120 s re-commit age the cached `k_native_as_of` reached 118 s; at 40 s (`8c2b9f7f2`) it still reached 74 s, because a strict `> 40` skips two 20 s ticks and the pass itself takes seconds; at 15 s (`17c36c5a1`), below the tick, every pass refreshes the stamp. Cost: one ~4-row CAS write per pass. D7 step 3's "120 s" is superseded by `LOCAL_CENSUS_RECOMMIT_S = 15`.
- DoD after O1:
  - 12: runs went 2→309 with last exit 0 and `run interval = 20 seconds`.
  - 13: in its 5-min window the stamp never aged past 21 s and `local_ts` past 20 s. In a later 30.4-min window at load ~230 (23/core), 2 of 89 samples showed a 49 s stamp, because the passes themselves slow under that load. Recorded, not hidden.
  - 14: over 41.5 min keepwarm swept +10 (≥ 5 required). The cache `ts` changed only on sweeps; the one change without a keepwarm line came from another caller's sweep, whose `census-ab:` line preceded it by 20 s.
  - 15: over 30.4 min on the 15 s code, the cached `k_native_as_of` was never more than 50 s old, and the board's live column showed no `?`.
  - 16 is observational: no login or logout has happened since the job loaded. Watch `accounts-local.out.log` for `local: T2 <acct>` and `local: first-read <acct> 200` at the next one.
  - The samples are in `/tmp/af/samples*.tsv`, one row per 20 s: runs, last exit, stamp age, `local_ts` age, cache `ts`, keepwarm swept count, max `k_native` age, and board `?` cells.

## 5. Tests to add or extend

**NEW `tests/claude-accounts-census.bats` (W1).** Python-level cases load the binary through SourceFileLoader (the tests/claude-accounts-core.bats:2489-2492 pattern), with HOME, LOG_PATH, LASTGOOD and CC_UTIL_LOG fixtured.
- **Parity.** `_census_from_lines` returns an identical `_Census` (counts, headless, live_sids, unknown) for ps-form lines and for procargs-form lines. Cover:
  - a `claude.exe --agent-id` teammate;
  - a title-rewritten `claude bg-spare` argv;
  - `-p` (counts as headless);
  - `--version` (skipped);
  - no CLAUDE_CONFIG_DIR (maps to next through `~/.claude`);
  - a trailing-slash config_dir;
  - `CLAUDE_CONFIG_DIR=~/…` expanding against the process's own HOME.
- **Hermeticity.** A procargs entry whose HOME differs from the module HOME is not attributed through the `~/.claude` mirror.
- **Fail closed.** With an injected lister seam (`ca._native_proc_entries`), each of these returns None with the named reason: a libproc load failure, an empty population, zero tty pids, a CPU over-budget clock stub, and the registry canary. A registry pid that misses the comm prefilter is gap-filled.
- **Lazy import.** `--rank interactive --max-wait 0 --max-age 600` and `--route interactive --max-wait 0 --max-age 600` (fixture config, records dir and HOME) run with a `sys.addaudithook` witness. They never import `ctypes`, and their `open` events are exactly {accounts.json, cache, util log (+ .gz siblings)}.
- **The 17:33 shape.** A fake subprocess raises TimeoutExpired, there is no k_stale within the grace, and native is injected with counts, under mode `ab`. Then `--route interactive` routes, route-meta says `k_src=panes-native`, `--json .rows[].k` is null, and heal sees `k_live None`.
  - MUTANT: dropping step 1 from k_panes brings back `concurrency-unmeasured` on every row, and the test goes red.
- **Mode.** `ps` (the default, with no `census` key) never runs native. The `census-ps` sentinel and `CC_ACCOUNTS_CENSUS=ps` both force ps, and with the env set `k_src != panes-native` on a cached `k_native` row.
- **inherit_k dating.** inherit_k dates a measured previous k by `k_as_of`.
  - MUTANT: dating by `prev.ts` admits a count past the grace.
- **Stub hermeticity.** A stubbed `ca.concurrency` leaves `_NATIVE_LAST` None, so no `k_native` appears.
- **Log format.** The `census-ab:` line has the documented format, and `--census-ab-report` gives `PASS`, `NOT-YET` and the denominator on fixture logs.

**NEW `tests/claude-accounts-local.bats` (W2-W4).** All network and keychain functions are monkeypatched: `fetch_usage`, `fetch_wire_limits`, the tier-1 attribute reader `_kc_attrs`, `read_creds` and `native_census`. Never touch the real keychain, the endpoint or /tmp live files.
- **No network.** A pass with no transitions makes 0 fetch_usage and 0 fetch_wire_limits calls. Positive control: logged-out → present with a new rt_fp makes exactly 1 fetch_usage call and 0 wire calls.
- **Keepwarm-silence guard.** After any pass, `ts`, `window`, `prev`, `no_heal` and `cfg_key` are byte-identical, and `--keepwarm --max-age 90` on a cache more than 90 s old logs `swept`.
  - MUTANT: a pass that bumps ts makes keepwarm log `served-cache`, and the test goes red.
- **Simulated login.** In ONE pass: the row goes `logged-out` → pending, exits 3, and the board text shows `logged in HH:MM; quota read pending`. A stubbed 200 makes it routable within that pass or the next, and the ledger entry has `quota_as_of == read_at`.
- **T1 logout.** One pass makes the row `logged-out` and excluded. This also holds on a `no_heal=True` payload, and `cache_read` with `max_wait=0` still serves it (D4).
- **Rule table.** T2 from `token-invalid` with the same rt_fp: no change. T4 refreshes `login_*`. keychain-error and probe-error rows never change. T2 clears `poll_throttled`.
- **Rule (f), blocker regressions.**
  - A 429 sweep after a first read keeps `poll_throttled`, `stale_quota`, `quota_as_of` and `wire`, and is refused at read_at+91 s.
  - (f) never fires inside cache_commit, never without the pending marker, and never when `read_at < payload_ts`.
  - It re-derives `*_reset_h` and drops `rolled_since`.
  - MUTANT: removing the marker restriction goes red.
- **Lost updates.**
  - A sweep payload older than the overlay keeps the recovery and the census through cache_commit.
  - A newer sweep stamp wins over the overlay.
  - The local CAS aborts when the cache changed under it.
  - Holding the single-flight `<cache>.lock` does not block a pass.
  - A stalled local wlock holder delays a sweep commit but never reverts it.
  - Two processes racing note_usage_429 on different accounts both persist.
  - save_lastgood merges and keeps the newer quota_as_of.
- **First-read guards.**
  - A timeout followed by a second pass within 90 s makes 0 calls.
  - A `stale` verdict makes 0 calls.
  - A held poll lock means 0 calls and the row stays pending.
  - The `first-read-off` sentinel means 0 calls.
- **Sweep reuse guard.** A first read 90 s old or younger with a matching rt_fp means no fetch, `quota_reused`, `quota_read_at == read_at`, and record_utilization writes `stale: true`. At 91 s, or with a mismatched rt_fp, the sweep polls.
- **Keychain stall.** A `security` stub that sleeps 30 s does not stop the census landing in the overlay and cache in that pass. The next pass re-reads the item that timed out.
- **Board.**
  - A local render preserves the existing mtime and never creates a missing board.
  - A sig mismatch after a cc-relogin-style write re-renders; a k-only difference waits 60 s and is gated on load.
  - `k_phantom` and `burn_*` never reach the cache.
  - keepwarm renders the overlay-merged rows (a recovered row stays recovered).
  - The footer shows clock times only.
- **Kill switches.** `off` prints `local: disabled` and still touches the stamp; `busy` touches the stamp.

**APPEND to `tests/claude-accounts-util-tail.bats`** (it exists with 5 cases; never recreate it):
- the memo returns exactly what an unmemoized read returns for 336 h then 72 h in one process;
- a 72 h-then-336 h request re-reads;
- a change in size or mtime_ns invalidates the memo;
- the memo is off under `--route` and `--rank`.

**NEW `tests/accounts-local-job.bats`** (the shape of accounts-board.bats tests 26-27, :637-662):
- `plutil -lint` passes;
- the literal ProgramArguments.2 with ` 120 ` swapped for ` 1 `, run under `/bin/bash` with a stalled stub, exits 142;
- with an echo stub it prints exactly `args:--local-refresh`;
- the keys are StartInterval 20, ThrottleInterval 10, RunAtLoad true, ProcessType Standard, no LowPriorityIO, and WatchPaths.0 = `/Users/chrisren/Library/Keychains/login.keychain-db`.

**NEW `tests/migration-0063-accounts-local-job.bats`** (the shape of tests/migration-0055-concurrency-scale-env-and-bands.bats setup :18-26: launchctl stub seam, CC_MIGRATION_LA_DIR, scratch HOME, everything under `/bin/bash`):
- dry run is the default and changes nothing;
- it refuses until the CA stub prints `local: disabled`, and the probe was invoked with `CC_ACCOUNTS_LOCAL=off`;
- it is idempotent on identical bytes when loaded;
- it never boots out a `state = running` job;
- bootstrap and readback happen in order;
- the header has class, step, run, subject (the repo arm), verify and batch-hold.

**EDIT `tests/cc-fleet.bats:700-706`:** 52 → 53, with a dated comment naming com.claude.accounts-local.

**Keep green, unedited:** tests/accounts-board.bats, tests/session-start-dispatch.bats, tests/claude-launcher-router.bats, tests/claude-accounts.bats, tests/claude-accounts-core.bats, tests/account-fact-derivation.bats, tests/claude-accounts-parallel-collect.bats, tests/claude-accounts-freshness.bats, tests/claude-accounts-fresh-lock-bound.bats, tests/claude-accounts-throttle-admit.bats, tests/claude-accounts-kwork-live-bound.bats, tests/claude-accounts-schema-drift.bats, tests/claude-accounts-wire-truth.bats, tests/claude-accounts-fleet-pace.bats, tests/cc-backlog-no-capacity-measured.bats, tests/desk-strand-replay.bats, tests/cc-relogin.bats, tests/cc-relogin-status.bats, tests/account-recovery-lane.bats, tests/fleet-manifest-lint.bats, tests/install-staged-plist.bats, tests/deploy-migrations.bats, tests/store-bounds.bats.

## 6. Install and converge

### Agent-runnable (no operator)

1. Pre-land, in the worktree: `scripts/ship-land.sh --precheck --working`, then `bg` every suite in §5 serially.
2. Land: project-local `/ship` from `~/Development/.worktrees/accounts-freshness`. Do not wrap it in a timeout, and do not touch tracked files until it returns.
3. Content check:
   ```
   git -C ~/Development/claude-infrastructure fetch origin && git -C ~/Development/claude-infrastructure show origin/main:bin/claude-accounts | grep -c 'def native_census'
   ```
   The count must be 1 (Land A). For Land B, also check `def apply_local_overlay`, plus `git ls-tree origin/main -- launchd/staged/com.claude.accounts-local.plist migrations/0063-accounts-local-job.sh`.
4. Converge: `cd ~/Development/claude-infrastructure && CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`. Never use `--force`. A refusal about evidence is a stop to report to the operator, not something to route around.
5. Live check:
   ```
   readlink ~/.claude/bin/claude-accounts; grep -c 'def native_census' ~/.claude/bin/claude-accounts; jq -r .census ~/.claude/accounts.json
   ```
6. If the land's smoke was shed, re-run your §5 suites against the converged tree; landed is not tested.
7. After O1: verify DoD 12-16, then land the manifest `staged`→`run` flip (steps 1-4 again).

### Operator-only (C10)

- **O1, activate the local job** (after Land B has converged):
  ```
  bash ~/Development/claude-infrastructure/migrations/0063-accounts-local-job.sh                    # dry run
  bash ~/Development/claude-infrastructure/migrations/0063-accounts-local-job.sh --confirm launchd
  ```
- **O2, Phase 3 ruling** (later): when `~/.claude/bin/claude-accounts --census-ab-report` prints `soak: PASS`, decide whether heal's rotation gate and cc-relogin's `live_sessions` (bin/cc-relogin:248-275) move to the native instrument. That change is a separate plan.
- **Rollback** (any time; no reload needed except for the last item):
  - `touch ~/.claude/state/accounts-local/off` makes the local pass a logged no-op.
  - `touch ~/.claude/state/accounts-local/first-read-off` stops only the usage GET.
  - `mkdir -p ~/.claude/state/accounts-local && touch ~/.claude/state/accounts-local/census-ps` stops native counts. It takes effect at the next sweep, or within 20 s while the job runs, because the pass strips `k_native`. For an instant effect on a shell's own reads, set `CC_ACCOUNTS_CENSUS=ps`.
  - Remove the job durably: `launchctl bootout gui/$(id -u)/com.claude.accounts-local; rm ~/Library/LaunchAgents/com.claude.accounts-local.plist`.
  - Full code revert: revert the land commit(s) through `/ship`, then converge.

## 7. Risks and how each is closed

| # | Risk | Closure |
|---|---|---|
| R1 | libproc returns a short or wrong population (struct or flag drift), so the census undercounts and fails open. | tty-pop > 0, the registry canary, and CPU and wall caps all return None. `row["k"]` stays ps-only until Phase 3. census-ab logs every sweep; `--census-ab-report`; the Phase 3 backlog item. |
| R2 | Native is slow inside a loaded sweep: in-sweep stages run 5-14x slower than a fresh process (keepwarm render age 46-122 s vs 8-9 s fresh, measured), so it returns None. | It runs concurrently with ps, so it adds no serial time. The CPU cap is 1 s against 0.03-0.04 s measured, and wall is 10 s. The local job refreshes `k_native` every 20 s regardless of sweeps. The report shows the native-None rate. DoD 6 checks the abstention claim. |
| R3 | The two cache writers lose an update. | The wlock has no bypass, a CAS guards the local replace, and the local writer keeps the `ts` it read, so a rollback moves quota and ts back together (fail-safe). cache_commit re-applies the overlay. A lost local update repairs itself on the next pass. Covered by mutant tests. |
| R4 | The first read adds polls or earns a 429. | At most one GET per token per 90 s or more, doubling after a non-200. No GET on `stale`. The poll lock is non-blocking. Kill switch. The 90 s reuse guard prevents a sweep double-poll. |
| R5 | Stale quota is laundered as fresh (blocker). | Rule (f) runs in the local writer only, only on the pending marker, and only with `read_at >= payload_ts` and read_at no older than the row's effective reading time. The ledger keeps the real `quota_as_of` (merge under flock). The reuse guard stamps `read_at`, never now. Covered by mutants. |
| R6 | Keychain stalls: 560 timeouts, p50 14.5 s (measured). | The census is written first. Reads run on daemon threads with an 8 s deadline. A timed-out item does not advance its identity, so it is retried. Budget checks skip the first read and the render. |
| R7 | WatchPaths misses events (FSEvents went dark on 2026-09-08), and 5 of 6 keychain writes come from other apps. | The 20 s StartInterval is the guarantee. The tier-1 attribute gate means other apps' writes cost about 4 attribute reads and no secret read. |
| R8 | keepwarm overwrites a newer local board. | keepwarm renders the overlay-merged cache, the sig check repairs any lag within one pass, and board writes are locked. |
| R9 | Test churn or ambient leakage. | Native is off unless accounts.json says `ab`, via a top-level key that fixtures do not copy. concurrency() is the single seam (`_NATIVE_LAST`). Native attribution uses each process's own HOME. The `_prev_snapshot` mutant line is untouched. |
| R10 | Rollback cannot reach the keepwarm job, whose plist is frozen. | The census-ps sentinel is read by producers (the sweep and the local pass, which strips `k_native`), the env var serves readers, and a revert plus converge works. |
| R11 | Manifest and migration bookkeeping: the count, a number collision, the recover_cmd path. | Plist, row, count and migration land in one commit. The number is re-checked at land. The row comment carries the real command. |
| R12 | A launch-path regression. | Lazy imports; the audit-hook test (no ctypes, identical open set); the memo is off on `--route`; the protected-file diff is 0. |
| R13 | Pre-existing problems, left unfixed and stated. | The keepwarm manifest row :445 still says `staged` and points at DO-NOT-RUN script 36. tty-less `claude -p` runs are invisible to both instruments (bound_kwork headless ≈ 0). The launcher's rc-3 label `no fresh quota data` is pinned by tests/claude-launcher-router.bats:245, :303 and :306 and is deferred. ps keeps costing 9-10 s per sweep until Phase 3. |

## 8. Rejected alternatives

- **Bump `ts` from the local pass.** Silences keepwarm, masks resets and re-dates quota (C5).
- **Kick com.claude.accounts-keepwarm** from hooks or cc-relogin. A kick on a cache older than 90 s becomes an endpoint sweep, which is the 2026-08-11 throttle incident (plist :82-89). A kick during a tick is dropped.
- **SessionStart kick** (builtin trigger-file write 0.054 ms; launchctl 4-10 ms, measured). Any diff to the protected hook breaks the structural zero-latency proof. It cannot help the session that is starting, and the 20 s floor plus WatchPaths cover the next one.
- **cc-relogin success kick.** Redundant: its phases write the keychain, so WatchPaths fires, and its `--fresh` cache write is caught by the board sig check within one pass.
- **Registry-only census.** Missed 3 live `--agent-id` teammates (pids 53516, 79002 and 96618 had no `sessions/<pid>.json`), and `kind` misclassifies `-p` (next4 counted 6 against a true 2).
- **Narrowed `ps`** (a pgrep subset). Slower: 2.9-5.9 s in the foreground, 51.9 s in the background (measured).
- **Raise K_GRACE_S, or route the desk lane while unmeasured.** That only widens the band, or reopens section 15's rule that UNKNOWN refuses. It is unnecessary once the instrument cannot starve.
- **Merge the overlay at read time in cache_read.** Adds an open and a parse to every launch (C2).
- **Board mtime = quota ts.** Changes what the hook's bands mean (producer liveness) and adds STALE noise to served-cache ticks.
- **A registry-dir WatchPaths watcher daemon.** Noisy from sdk-cli churn, blind to teammates, and close to rejected alternative A5 in ACCOUNT_ROUTING_V2.
- **A pending-activation shim for the manifest's activate column.** deploy-live materialises that directory into the operator's live queue (scripts/deploy-live.sh:1750), so a shim would file a second operator step for the same action (INFERRED). The 0051/0058 precedent is followed instead.
- **Review suggestion: reuse a first read in the sweep only when read_at ≥ sweep start.** That forces a second poll of a token read under 90 s ago, which is a 429 97.6% of the time within 30 s. Honest stamping within 90 s stays inside the measured drift band.
- **Persist burn and pace results across processes.** Deferred. The per-process memo and load-gated k-only renders bound the cost (about 1-2% of one core, ESTIMATED).

## 9. Definition of Done

Items 1-11 are agent-reachable. Items 12-16 need the operator's O1 first, after which the agent verifies them. Each item is a command with an expected output.

**After Land A**
1. **Protected files have no diff:** `git -C ~/Development/.worktrees/accounts-freshness diff --quiet "$BASE" HEAD -- hooks/accounts-board.sh hooks/session-start-dispatch.sh lib/claude-launcher.zsh launchd/staged/com.claude.accounts-keepwarm.plist && echo PROTECTED-UNCHANGED` prints `PROTECTED-UNCHANGED`. Re-check at Land B.
2. **Census suite:** `bg tests/claude-accounts-census.bats` gives plan = ok. This covers: forced ps failure → `--route interactive` routes with `k_src=panes-native` and the abstention mutant fails; the 17:33 shape; mode and rollback.
3. **Launch path:** the audit-hook case in (2) proves no ctypes import and an unchanged open set for `--rank`/`--route` cache-only.
4. **Keep-green:** every suite listed in §5 "Keep green" gives plan = ok, and `git diff "$BASE" --stat -- tests/` shows only §5's new or edited files.
5. **Live, within 1 h of converge:** `grep 'census-ab:' ~/.claude/logs/claude-accounts.log | tail -5` shows `native={…}` with counts on every sweep line, and `~/.claude/bin/claude-accounts --census-ab-report` prints a `soak:` line. Record the first `ps=UNAVAILABLE` line that carries native counts once one occurs.
6. **Live, 72 h after converge (observational; record it, do not block on it):** the T0.3 jq filtered to `.ts >= "<converge ISO>"` should count 0 interactive `none` decisions with 3 or more `concurrency-unmeasured`. The baseline was 11 on 2026-10-11.

**After Land B**

7. **Local suite:** `bg tests/claude-accounts-local.bats` gives plan = ok. In particular:
   - a simulated login flips the cache row and the board text in ONE pass, so the board flips within one local interval (≤ 20 s + pass once the job runs);
   - a simulated logout does the same;
   - a no-transition pass makes 0 network calls;
   - `ts` is byte-identical, and the ts-bump mutant fails;
   - every lost-update and first-read guard case passes.
8. **util-tail suite:** `bg tests/claude-accounts-util-tail.bats` gives plan = ok, with 5 + new cases.
9. **Job and bookkeeping:** `bg` gives plan = ok on accounts-local-job.bats, migration-0063, cc-fleet.bats (count 53), deploy-migrations.bats, fleet-manifest-lint.bats, install-staged-plist.bats and store-bounds.bats.
10. **Verb is live:** `CC_ACCOUNTS_LOCAL=off ~/.claude/bin/claude-accounts --local-refresh` prints exactly `local: disabled`.
11. **SessionStart hook:** the structural proof is item 1. As an informational check, the T0.3 hook p50 is within ±20 ms of the W0 baseline at comparable load (record the load). Wall-clock time is not an admissible verdict on this box.

**After O1 (operator), verified by the agent**

12. **Job loaded:** `launchctl print gui/$(id -u)/com.claude.accounts-local | grep -E 'run interval|runs =|last exit'` shows `run interval = 20 seconds`, `runs` increasing over 2 min, and `last exit code = 0`.
13. **Job ticking:** over 5 min, `stat -f %m ~/.claude/logs/accounts-local.stamp` never ages past 40 s, and `jq .local_ts /tmp/claude-accounts-local.json` is never more than 60 s old.
14. **keepwarm not silenced:** over 30 min, `grep -c 'keepwarm: swept' ~/.claude/logs/accounts-keepwarm.out.log` rises by 5 or more. Sampling `jq .ts /tmp/claude-accounts-cache.json` every 20 s shows ts changing only when a sweep line appears.
15. **Live column fresh:** over 30 min, sampled `jq '[.rows[]|.k_native_as_of]'` is never more than 60 s old, and the board's live column shows no `?` while the job runs.
16. **Next real login or relogin** (observational):
    - (item cdat/mdat from `security find-generic-password -s <svc> -a chrisren`, no `-w`) → `local: T2 <acct>` line in accounts-local.out.log: ≤ 30 s;
    - → `local: first-read <acct> 200`: ≤ 45 s;
    - the next desk decision in route.jsonl is not `none` or `pinned` because of that account.
