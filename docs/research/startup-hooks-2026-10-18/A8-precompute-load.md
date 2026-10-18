# A8 — Precompute and load handling for SessionStart hooks

Axis A8 of the 9-axis startup-hooks study (2026-10-18). Scope: for every SessionStart hook and dispatcher
child, can its output be precomputed (a producer that already exists, event-driven, or a TTL cache)?
What staleness band is honest, and what must be loud when the producer is stale? Separately: should hooks
adapt to load, and is QoS/priority a lever? Constraint carried throughout: no fix may throttle, cap,
kill or demote live session work, or reduce sessions.

Read-only throughout. No hook script was executed. Helpers written for this axis, all read-only and all
in this directory: `a8_burst_census.py`, `a8_child_timing.py`, `a8_exec_cost.sh`, `a8_load_join.py`,
`a8_account_load.py`. I also ran the sibling A3 helper `a3_dispatch_census.py` read-only.

Tags: **[M]** = measured (the command is given), **[E]** = estimated (the method is given).

---

## 0. Answer in five lines

1. **The dispatcher's 9 s kill band is mostly one child doing O(18,000) work: config-mirror-assert's
   memory-mirror walk. Load is a minor factor.** At the same load, sessions on the three
   isolated-`projects` accounts (secondary, tertiary, quaternary) run the dispatcher at p50 **7.6 s** against
   **2.6 s** on the shared accounts (load < 100), and pass 9 s in **35 % vs 0 %** of runs. At load ≥ 100
   the figures are 88 % vs 8 %. Of the 100 dispatcher runs ≥ 9 s that I could join to a load sample, 95 are on the isolated
   accounts [M]. A read-only replica of that walk alone took **7.3–13.3 s** at load ~515 [M]. The work
   heals only the NEXT session (config-mirror-assert.sh:6-7). The zsh launcher already does the same walk
   before every launch on those accounts (~/.zshrc:185-187, :241, :257).
2. **Precompute pays where the input is fleet- or account-global and changes far more slowly than sessions
   start.** That covers the mirror status, activation drift, escalation-pipeline health, the mission board
   render (≈1.5 s of git+python per start [E from M]), and the version-health verdict. It does NOT pay for
   per-session state that must be delivered exactly once (recycle packet, mailbox, desk brief). Those
   need fewer forks and a self-deadline instead.
3. **The accounts-board pattern holds under this load.** The board was stale at render in at most 3 of
   ~378 starts, and withheld/unavailable in at most 2+2 [M, an upper bound]. So a Standard-QoS launchd producer at 180 s stays fresh even
   at ~50 load per core. A Background-QoS producer would not: there are Background producers on this box,
   and they must not carry precompute (see §5).
4. **Do not gate hooks on `vm.loadavg`.** The dispatcher correlates only weakly with load (Spearman 0.25),
   and most of its runs >= 9 s happened at load < 100 [M]. Load is bursty, not sustained: hourly means are
   mostly 10–90, with spikes of 300–500 [M]. Instead, adapt by measured **elapsed time**: a `$SECONDS`
   self-deadline makes a slow hook emit its cheapest correct form, with a loud "degraded" tag, before any
   kill. That changes the hook's output. It never touches session work.
5. **QoS is not a lever for the hooks themselves.** Hook processes run at PRI 31 / NI 0, the same band as
   `claude` [M]. They are not in the starving background band. Raising them needs root and would come at
   the expense of session work. The live QoS hazard is a different one: a load-flapping 2 s wall-clock
   health check in pre-session-validate.sh. It has logged 582 false "broken" verdicts, and it holds an
   auto-rollback path that has fired in flip-flop pairs minutes apart (§3.9).

---

## 1. Method and data

| Source | What | Command / tool |
|---|---|---|
| 411 main transcripts, last 2 days | SessionStart hook attachments: hookName, command, durationMs, timedOut, stdout | `/tmp/startup-hooks-census-files.txt` (given) |
| A3 per-child presence | which child signature is present per dispatcher run | `python3 -I a3_dispatch_census.py /tmp/startup-hooks-census-files.txt --rows /tmp/a8-a3rows.tsv` |
| IDL ledger | session-index-start writes one sid-keyed row from an EXIT trap (hooks/session-index-start.sh:14-17) | `a8_child_timing.py` |
| Load history | `load_1m` every 60 s, 9,603 samples 10-08 20:51 .. 10-18 01:24 (`~/.claude/logs/capacity-alarm.jsonl`, written by com.claude.capacity-alarm) | `a8_load_join.py`, `a8_account_load.py` |
| Live processes | priority and QoS of hook processes right now | `ps -axo pid,ppid,pri,ni,stat,etime,time,command \| rg '/hooks/'` |
| Exec cost under live load | the primitives hooks fork | `bash a8_exec_cost.sh 7` |
| launchd producers | ProcessType / StartInterval of every claude/chrisren job | `plutil -extract ProcessType raw <plist>` |
| Static reading | every SessionStart hook, its libs, cc-mission, config-mirror.zsh | file:line cited inline |

Known bias, inherited from the brief: hook_success carries durationMs only when the hook printed something. The
dispatcher, dod-persist and mailbox-drain print on almost every start, so their samples are near-complete.
desk-brief-inject prints only for the desk pane, so it has n=1.

---

## 2. Measurements

### M1 — Hook processes are NOT in the background QoS band [M]

`ps -axo pid,ppid,pri,ni,stat,etime,time,command | rg '/hooks/'` (01:08 CDT, load 470/503/541):
every live hook process showed **PRI 31, NI 0**. That covers operator-readout.sh and its wrap-ledger/cc-backlog children,
mailbox-wake-arm.sh, cc-await-ping and 48 lead-crash-watchdog.sh. Claude processes are also PRI 31.
Runnable-process sample (`ps -axo pri,stat,comm`, R state): Chrome at PRI 20 (16) and PRI 4 (10), claude at
31 (12), Browser at PRI 4 (11), bash at 20 (8), xpcproxy at PRI 4 (6). There are 44 `bash` at PRI 4 overall.
**Reading:** startup hooks compete as equals with sessions, and they outrank everything clamped to the
background band. They are not being starved by a QoS demotion. On Darwin `nice` does not demote. Only
`taskpolicy -c background` reaches PRI 4, and no SessionStart registration or hook applies it.

### M2 — Wall cost of the primitives hooks fork, under live load [M]

`bash a8_exec_cost.sh 7` at load 551 → 551 (01:18:39–01:18:47):

| Primitive | min | median | max (ms) |
|---|---|---|---|
| timer overhead (2 perl execs, subtract from the rest) | 8 | 15 | 27 |
| `/usr/bin/true` | 18 | 25 | 109 |
| `bash -c :` / `zsh -fc :` | 17 / 19 | 23 / 27 | 110 / 86 |
| `jq -n 1` | 20 | 26 | 64 |
| `python3 -I -c pass` | 38 | 67 | 229 |
| `python3 -c 'import json,subprocess,pathlib'` | 63 | 151 | 264 |
| `perl -MDigest::SHA -e 1` | 25 | 33 | 46 |
| `launchctl list` | 21 | 22 | 117 |
| `git rev-parse --show-toplevel` | 27 | 56 | 124 |
| `cat` of the 2 KB board | 25 | 92 | 144 |

**Rule of thumb [E, from this table]:** at this load a fork+exec costs ~10–80 ms of wall time (median ~25 ms
net), a Python start with imports ~150 ms, and git ~55 ms. So a hook's wall cost ≈ (its exec count) × 25–50 ms,
plus the I/O it does. "Precompute" here mostly means "move execs off the critical path".

### M3 — The dispatcher's kill band is an ACCOUNT effect, at equal load [M]

`python3 -I a8_account_load.py` (dispatcher runs joined to the nearest load_1m sample within 120 s):

| Account class (transcript path) | Load band | n | p50 ms | p90 ms | ≥ 9 s |
|---|---|---|---|---|---|
| ISOLATED (`~/.claude-{secondary,tertiary,quaternary}`) | < 100 | 168 | **7,564** | 9,484 | 59 (**35 %**) |
| ISOLATED | ≥ 100 | 41 | 9,828 | 10,948 | 36 (**88 %**) |
| SHARED (`~/.claude/projects`, used by ~/.claude and ~/.claude-next whose projects/ symlinks to it) | < 100 | 131 | **2,569** | 4,247 | 0 (**0 %**) |
| SHARED | ≥ 100 | 61 | 4,527 | 7,980 | 5 (8 %) |

In both load bands, the isolated accounts take **+5.0 s at p50** and account for **95 of the 100** joined
dispatcher runs ≥ 9 s.

**Which child.** The per-account children are:
- config-mirror-assert.sh: exits at line 10-11 for ~/.claude only, and runs the mirror for every other
  account.
- session-start.sh: its MCP cache is keyed per config dir (:140-141), and every account's cache is
  currently present.
- setup-task-symlinks.sh: its store is per config dir (hooks/lib/task-helpers.sh:22). But every account's
  `tasks/` is a symlink to the same 917-dir store, so it is identical across accounts [M,
  `ls -1 $d/tasks | wc -l` → 917 ×5].
- session-index-start.sh: p50 0.8 s (M5), so not it.

What separates isolated from shared is in config-mirror's library. `_CC_ISOLATE` lists `projects` only for
secondary/tertiary/quaternary (lib/config-mirror.zsh:45-48). `_cc_sync_memory_mirror` returns early unless
`projects` is isolated (:298), and otherwise iterates **the union of every project slug in both trees**
(:300-302). That is 18,228 / 18,197 / 18,148 / 18,171 entries [M, `ls -1 <dir>/projects | wc -l`].

**A3 cannot see this kill.** A3's always-printer check passes in 100/101 runs ≥ 9 s. config-mirror-assert
prints nothing when healthy and nothing when killed, so its death is invisible by construction. The
"mirror" signature in A3 also matches the accounts-board text on .claude-next runs (verified: an account-1
path's systemMessage carries `knowledge-layer mirror (.claude-next): ⚠ 2 FORKED …`), so it is not a
kill detector either.

### M4 — A read-only replica of the memory-mirror walk alone [M]

```
/usr/bin/time -p /bin/zsh -fc 'zmodload -F zsh/stat b:zstat; typeset -A s;
  for p in ~/.claude/projects/*(N/); do s[${p:t}]=1; done;
  for p in ~/.claude-quaternary/projects/*(N/); do s[${p:t}]=1; done; n=0;
  for k in ${(k)s}; do d=~/.claude-quaternary/projects/$k/memory;
    if [[ -L $d ]]; then zstat -L -A z +link -- $d; ((n++)); fi; done; print slugs=${#s} links=$n'
```
slugs=18,896, links=17,484. Wall time **13.31 / 7.94 / 7.25 s**, CPU 2.4 / 1.8 / 1.7 s, at load ~515. This is the walk
alone, with no mirror writes, no config-entry loop over the 1,288 ~/.claude entries, no
`python3 cc-settings-parity` (config-mirror-assert.sh:46-50) and no `cc-agent-budget-flags` (:95-99). On its
own it exceeds the dispatcher's 9 s child bound (session-start-dispatch.sh:41) in 1 of 3 runs.

### M5 — session-index-start is fast but its output is always discarded [M]

`python3 -I a8_child_timing.py`: 366 of 410 dispatcher runs have a matching IDL row (all `exit:0`, none
`exit:143`; I verified that bash 3.2 runs the EXIT trap under SIGTERM with
`timeout 1 /bin/bash -c 'trap "echo EXIT-TRAP-RAN" EXIT; /bin/sleep 3'`). Child end minus dispatcher start:
p50 **0.8 s**, p75 1.6, p90 3.2, p99 7.8, max 14.3 s. Only 4 runs ≥ 9 s. Not the kill-band driver.
**But** A3 shows its `Session index` line present in **0 of 404** successful runs. The filter at
hooks/session-index-start.sh:45-50 drops the line whenever every recent entry reads "(no summary)". So the
`python3 session-search.py --context-inject` at :37 is critical-path work whose output never ships.

### M6 — Which hooks actually track load [M]

`python3 -I a8_load_join.py`:

| Hook | n | Spearman(load_1m, ms) | p50 at load < 100 | p50 at load 300–400 | timeouts at < 100 vs ≥ 100 |
|---|---|---|---|---|---|
| session-start-dispatch.sh (12 s) | 401 | **0.25** | 5,435 | 7,650 | 0/299 vs 4/102 |
| dod-persist.sh (5 s, sync) | 349 | **0.56** | 1,714 | 4,924 | 2/283 vs 12/66 |
| mailbox-drain.sh session-start (5 s, sync) | 322 | **0.65** | 1,529 | 5,183 | 4/239 vs 28/83 |

**Reading:** the dispatcher is dominated by a fixed cost (M3/M4). The two separate sync hooks are fork-bound
and degrade with load. Their timeouts concentrate at load ≥ 100: dod-persist 0.7 % vs 18 %, mailbox-drain
1.7 % vs 34 %. Their lever is fewer forks per start plus a self-deadline.

### M7 — Slow starts are not burst contention [M]

`python3 -I a8_burst_census.py` (dispatcher runs by the number of OTHER dispatcher starts within ±30 s):
isolated starts (0 others, n=197) p50 6,365 ms, 27 % ≥ 9 s; 1–2 others (n=61) p50 5,835, 25 %; 3–5 others
(n=152) p50 3,430, 25 %. A burst of simultaneous starts does not slow them. So deduplicating concurrent
computation (single-flight across sessions) is not where the latency is. Removing per-start O(N) work is.

### M8 — Load is bursty, not sustained (correction to the brief) [M]

Hourly mean load_1m from capacity-alarm (UTC):
- 10-14..10-17: mostly 9–90.
- Spikes: 10-16 T06 **359**, 10-16 T18 **310**, 10-17 T18 169.
- Since 10-18 T00: 353 / 321 / 513.

Command: `tail -n 4000 capacity-alarm.jsonl | jq -r '[.ts[0:13], .load_1m]|@tsv' | awk …`. Of the 401
joined dispatcher runs, **299 happened at load < 100**. Any "only when loaded" fix would therefore miss most of
the problem.

### M9 — The precompute pattern's freshness under this load [M]

`xargs rg -c -F '<phrase>' < /tmp/a8-dispfiles.txt` (383 transcripts that contain a dispatcher record):
- `STALE by`: 3
- `numbers withheld`: 2
- `accounts board unavailable`: 2
- `is RUNNING but its current tick`: 1
- `EMPTY — the producer`: 2

These are upper bounds, because transcripts that quote accounts-board.sh's source (this study's own) also
match. Against ~378 rendered boards, the Standard-QoS keepwarm producer (StartInterval 180) was fresh in
**≥ 97 %** of starts.

### M10 — cc-mission render on every start costs ≈ 1.5 s at load ~520 [E from M]

hooks/session-start.sh:460-462 runs `timeout 20 cc-mission render` synchronously, before the child prints
(:464-471). Inside the dispatcher's 9 s child bound, a slow render therefore takes the MCP line down with it.
The render is Python (bin/cc-mission:38-53 imports; `operator_sign` imports hashlib/subprocess), and for
each of the 7 rows it runs `git ls-tree` + `git log origin/main -- <paths>` (path_state, :101-121, called at
:173 and :235) and `git rev-parse` for signed rows (:124-125, :195). I replayed the same read-only git
queries for the 7 rows: **12 git calls + 14 jq = 1,687 ms** at load 537 [M]. Subtracting ~26 ms × 14 for jq
(M2) and adding a Python start (151 ms, M2) gives **≈ 1.5 s per start** [E]. The board's inputs are the row
files, origin/main, and the DATE (the stamp is date-granular, :285). It only writes when the bytes change
(:298-307). The hook's own comment concedes a one-session lag by design (session-start.sh:437-439).

### M11 — pre-session-validate flaps on load and validates a track no session runs [M]

`~/.claude/logs/pre-session-validate.log`: **582** "current version broken" lines and 558 "no working
fallback found". By day: 13 on 10-16, 10 on 10-17, 5 so far on 10-18. The same binary passes on other starts
the same day, because healthy starts are silent. The check is `timeout 2 "$current_binary" --version`
(hooks/pre-session-validate.sh:115), a Node start under a 2 s wall bound. Past rollbacks came in flip-flop
pairs minutes apart: 05-20 21:58:55 114→80 then 21:59:28 80→114, 06-13 13:22 / 21:50, 07-21 08:52:29 / 08:54:43.
That is the signature of a wall-clock health check reading load as breakage.

Every live session runs `~/.claude-293` (39 `node_modules/.bin/claude` + 9 `claude.exe` processes [M,
`ps -axo command | rg -o '^/[^ ]*claude[^ ]*'`]). `~/.claude-versions/current` → 2.1.114 is read only by
`bin/claude-latest`, `bin/claude-versions` and `scripts/smoke-test.sh` [M, `rg -l 'claude-versions/current'`].
Today the scan finds no fallback, because 2.1.113 is MANIFEST-skip and 2.1.183 has no
`node_modules/.bin/claude`. If any fallback qualified, a load spike would re-point `current` (:159).

### M12 — launchd producers by QoS band [M]

`plutil -extract ProcessType raw` over ~/Library/LaunchAgents:
- **Standard or default** (usable for precompute; these do not starve): accounts-keepwarm (180 s), accounts-local (20 s),
  capacity-alarm (60 s), qos-census (600 s), autonomy-sweep (300 s, default), deploy-live (600 s, default),
  postland-verify (300 s), worktree-gc-infra (600 s), team-orphan-reaper (600 s).
- **Background** (PRI 4 at saturation; must NOT carry startup precompute): session-search-sweep (60 s),
  desk-invariant, dispatcher, discovery, cc-reaper, cc-gc, auth-timeseries, log-rotation, relogin,
  teammate-reap-alarm, browse-mirror.

---

## 3. Per-hook decision: precompute, event-driven, TTL cache, or keep inline

Decision rule, consistent with docs/research/load-hook-timeouts-2026-10-11/DESIGN.md:231 ("every daemon is
new load … prefer lazy caches checked with builtin `-nt` … reuse producers that already exist"):
- **Event-driven** when one code path owns every mutation of the input. The writer renders the snippet at
  write time.
- **Existing Standard producer** when the input changes outside our code or with time (quota windows,
  launchctl state, sweep liveness).
- **Lazy stale-while-revalidate inside the hook** (zero-fork `-nt`/age check, detached single-flight refresh)
  when neither exists. session-start.sh's MCP cache (:101-124) is the house template.
- **Keep inline** when the content is per-session and must be delivered exactly once. Then the levers are
  fewer forks and a self-deadline.

| # | Hook / child | Scope of the input | What changes it | Strategy | Honest staleness band | Loud behaviour when stale | Per-start saving |
|---|---|---|---|---|---|---|---|
| 3.1 | **config-mirror-assert** (dispatcher child) | per ACCOUNT; memory mirror per (account, slug) | deploy/migration (new ~/.claude entries), a session in a NEW cwd (new slug), a settings edit | **Split.** Inline: own slug + top-level entries only. Full 18k walk: detached, single-flight, stamp-throttled sweep. Warnings (forks, settings parity, budget flags) → per-account status file written by the sweep | fresh < 1 h; stale < 24 h shown with its age; older → withheld | `knowledge-layer mirror status is <age> old — sweep <name> last ran <ts>, last result <rc>; run: zsh -fc '…_cc_sync_account <cfg>'` as a systemMessage (0 tokens) | **≈ 5.0 s p50 on 3 of 4 accounts** [M, M3 difference]; removes ~95 of 100 kill-band runs [M] |
| 3.2 | **session-start.sh → cc-mission render** | fleet-global | row files (cc-mission writes), origin/main moves (land/deploy), date rollover | **Event-driven + lazy.** cc-mission's row-writing subcommands and post-land render. The hook does a zero-fork check (board date ≠ today, or rows dir `-nt` board) → detached render, never a wait | 1 day (the stamp is date-granular, cc-mission:285) | board's rendered date older than yesterday → systemMessage `mission board not re-rendered since <date>; run cc-mission render` | **≈ 1.5 s** off the session-start child at load ~520 [E, M10] |
| 3.3 | session-start.sh → MCP probe | per account | MCP config / binary changes | Already SWR (:374-392). Two gaps: (a) at MAX_AGE (86,400 s, :143) it probes **inline** on the critical path (2.5–15 s, :125-127), and ~/.claude's cache is 24 days old [M, stat]; (b) refresh failures are not recorded, so the secondary cache sits at 8.5 h despite TTL 300 [M, stat]. Fix: never probe inline; past MAX_AGE emit `MCP: UNKNOWN (cache <age>; refresh pending)` and detach; record each failed refresh (ts, reason) beside the cache | TTL 300 s fresh; ≤ 24 h shown with its age (as today) | carries the failed-refresh count and the reason | up to the 9 s bound on starts that would inline-probe [E] |
| 3.4 | **session-index-start** | per cwd | session summaries, written by session-search-sweep (Background QoS) | **Drop the inline `--context-inject`** (keep the stub upsert at :69-107), or move it to a per-cwd file written by the sweep only when informative. Zero python at start | n/a (output shipped 0/404 times) | none needed: nothing that was ever shown disappears | p50 0.8 s / p90 3.2 s / p99 7.8 s of child time [M, M5]; one python3 per start |
| 3.5 | activation-watch axes 2–3 | fleet-global | converge/deploy-live (repo mirror), operator `.done` markers, launchctl state | **Existing producer:** deploy-live (600 s, default QoS) writes `activation-watch --parity` + axis-3 results to a status file after each converge. Axis 4 (env arm, per-session environment, :243-331) **stays inline**: it reads its own env and costs one grep | fresh < 30 min; stale < 6 h shown with its age; older → "drift check last ran <age> ago" | names the producer and prints `bash activation-watch.sh --parity` | ≈ 8–15 execs (2× launchctl, diff -rq, git rev-list, git per live-only file) ≈ 0.3–0.8 s [E, M2] |
| 3.6 | escalation-watch | fleet-global | autonomy-sweep ticks; perl installs | **Producer-owned heartbeat:** autonomy-sweep (Standard, 300 s) touches a heartbeat file each tick, and the hook does one `stat` instead of `tail -c 1 MB \| tail \| grep \| tail` over a 25 MB ledger (:93-94). Cache the perl capability verdict, keyed by `[ "$(command -v perl)" -nt verdict ]` (zero-fork) | already defined: 900 s (:42) | as today; the heartbeat's own age **is** the liveness signal, never a third party's | ≈ 5 execs + 1 MB read + perl ≈ 0.2–0.4 s [E] |
| 3.7 | setup-plan-symlinks | per project + plans-index | plan files, plans-index reconcile | Lazy TTL: cache `Plans: x/y` per project in `.claude-plans/.counts`. Recompute when `docs/plans`, `.claude-plans` or `plans-index.json` is `-nt` the cache, or after 10 min (in-place status edits do not move dir mtime) | 10 min, labelled `(as of HH:MM)` | n/a (advisory count) | 2 find + awk over all plans + 2 jq ≈ 0.2–0.5 s [E] |
| 3.8 | frontier-status | fleet config + per-cwd ledger | model-config.yaml edits, ledger edits | Pure-bash `while read` instead of sed + 4 grep + 4 awk + date (:18-29); or cache keyed by `-nt` | n/a | n/a | ≈ 12 execs ≈ 0.3–0.6 s [E] |
| 3.9 | **pre-session-validate** (async) | per installed track | installs, re-pointing `current` | **Event-driven:** validate when `readlink current` or the binary's mtime differs from a verdict file. A timeout means **UNKNOWN (slow), never broken**, and is never grounds for a rollback. Roll back only on a non-zero exit that reproduces once more with a 10 s bound | verdict valid until the target changes | verdict file carries its age and reason. A **broken** verdict → loud systemMessage naming the track and `claude-versions` | one Node `--version` per start (M2: Python-class cost or worse); stops ~580 false alarms; closes the load-triggered rollback path |
| 3.10 | accounts-board | fleet-global | quota sweeps (time) | **Already precomputed** (keepwarm). Keep | 300 s / 3,600 s (accounts-board.sh:38-40) | already prescriptive (`producer_state`, :66-82) | — (calibration: ≥ 97 % fresh, M9) |
| 3.11 | setup-task-symlinks | per project | task writes | Already split: the store sweep is detached and throttled (:171-181). The active-list summary stays inline | — | — | — |
| 3.12 | recycle-failed-inject | per SESSION, exactly once | handoff-fire writes the packet (already event-driven) | **Keep inline.** Already O(1) when there is no packet (:38) | — | — | — |
| 3.13 | **dod-persist** (sync, 5 s) | per SESSION lineage × per repo store | writes only via persist_dod (PreCompact, `set`) and dod_lineage_record | (a) **Memoize within the run.** `dod_lineage_ancestors` (git rev-parse + awk over the 398 KB, 3,524-line lineage.tsv, dod-path.sh:125-153) runs ≥ 3× per start: via dod_read_content (:190-201), `_dod_lineage_pred` (dod-persist.sh:312) and per-file `dod_filter_for` (:331). `dod_read_files` (git config/rev-parse/shasum) runs ≥ 3×. (b) **Event-driven index:** persist_dod appends a header row (ts, session, toplevel, byte offset) to `repo-X.idx`, and SessionStart reads the index rather than filtering the 90 KB store twice with a bash `while read` (dod-path.sh:158-175). (c) **Self-deadline**, §4 | the store is exact (event-driven) | if over budget: emit the one-line pointer (`Durable DoD: injection skipped, over N s; read: dod-persist.sh get`) rather than being killed silently | (a) ≈ halves forks [E: ~50–60 → ~25–30 execs]; p50 1.7 s → ~0.9 s at low load, 4.9 → ~2.5 s at load 300–400 [E, proportional] |
| 3.14 | **mailbox-drain session-start** (sync, 5 s) | per SESSION, exactly once | peers send (cc-notify) | Keep inline (emit-then-commit already makes a kill a delay, not a loss, :277-311, :918-930). **Event-driven render:** the sender stores the rendered headline with the line, so the drain skips `python3 mail_headline.py` (:876) and the stale-forward python (:859). Plus a self-deadline | exact | if over budget: deliver the raw body without headlines, tagged `(headlines skipped: drain over N s)`, and commit | 1–2 python3 starts ≈ 0.15–0.5 s each under load [E, M2]; the 34 % timeout rate at load ≥ 100 [M] should fall |
| 3.15 | desk-brief-inject (sync) | per pane | role file | Keep. Already ~10–15 execs. The `[ -f role ]` gate could run before sourcing the IDL lib, saving a few | — | — | small |
| 3.16 | net-context-stamp (async) | machine-global | network change | Optional TTL: reuse the last line when the default gateway is unchanged within 5 min. Off the critical path, CPU only | — | — | ≈ 12 execs of CPU per start [E] |
| 3.17 | session-register / live-session-registry (async) | per SESSION writes | — | Keep (registries must be per session) | — | — | — |

---

## 4. Load-adaptive behaviour: what to do and what not to do

**Do not read `vm.loadavg` to decide what to skip.**
1. M6/M8: most slow dispatcher runs are at load < 100, and load is bursty.
2. Prior design rejected exactly this (load-hook-timeouts-2026-10-11/DESIGN.md:229): "loadavg is
   permanently above any such threshold here and is inflated by starved work".
3. Skipping a check because the box is busy is the silent drop this study exists to remove.

**Do adapt to measured elapsed time, by degrading OUTPUT, never session work.** This is the "self-deadline"
pattern:
- Each sync hook gets a soft budget below its harness timeout: dod-persist and mailbox-drain ~3.5 s of 5 s;
  each dispatcher child ~7.5 s of 9 s.
- At checkpoints, `[ "$SECONDS" -ge "$SOFT" ]` (a builtin, no syscall; /bin/bash 3.2 has 1 s resolution,
  which is enough) switches the hook to its cheapest correct form:
  - DoD: the pointer line.
  - Mailbox: the raw body without headlines.
  - Mirror: "check deferred to the background sweep".
- The degraded output carries a tag that names the hook, says what was skipped, and gives the command for
  the full output.
- Every degradation also appends one line to a small ledger, e.g. `~/.claude/state/startup-degrade.tsv`,
  holding ts, sid, hook, elapsed and what was skipped. The degradation rate is then measurable, and A-axis
  alarms can read it.

Under load this turns a kill (lost output, no record) into a delivered, labelled, smaller output. It costs
nothing when the machine is idle.

**Optional, later:** if a load signal is wanted for choosing between inline and detached work, use the
foreground run queue (convoy-gauge's `run_default`/`run_ui`), as DESIGN.md:181 proposes for the gates. Have an
existing Standard producer write it to a state file, and read it with the builtin `read < file` (zero forks).
Not needed for any recommendation here.

## 5. QoS and priority

- **Hooks are in the right band already** [M1: PRI 31, NI 0, same as claude]. Do not wrap any startup
  work in `taskpolicy -b` / `-c background`. At saturation that band does not run
  (DESIGN.md:101, :228), and a hook in it would be killed at its timeout with nothing printed.
- **Raising hook priority is not available, and it is not wanted.** A negative nice needs root.
  `taskpolicy` clamps down, not up. Any gain would come at the expense of live session work, which the
  constraint forbids. M3 also shows the dominant cost is filesystem metadata work that is present at load
  < 100, so priority would not remove it.
- **Detached refreshers and sweeps** that hooks spawn (the mirror sweep in 3.1, the mission render in 3.2,
  the MCP refresh) inherit PRI 31 today. For must-finish background work, the prior design's rule applies:
  `taskpolicy -c utility`, never `background` (DESIGN.md:101).
- **Producers that carry precompute must be Standard QoS** (M12). Two rules follow:
  - Do not put startup precompute on session-search-sweep, desk-invariant, dispatcher or cc-reaper.
  - 3.4's "sweep writes per-cwd context" option inherits session-search-sweep's Background band, so it
    must show staleness. Dropping the inline call is the safer choice of the two.

---

## 6. Recommendations (ranked)

Each item gives the change, file:line, expected impact, effort, risk, whether settings.json must change, and
conviction (0–100).

**R1. Take config-mirror-assert's O(18k) memory-mirror walk off the per-session path (inline: own slug only;
full walk: detached throttled sweep; warnings: per-account status file).**
- Where: config-mirror-assert.sh:17 (the `_cc_sync_account` call); lib/config-mirror.zsh:293-302 (add a
  `--slug <encoded-cwd>` mode that checks just that slug); a stamp-throttled detached sweep in the shape of
  setup-task-symlinks.sh:171-181 (CC_*_MIN_S stamp, `( … </dev/null >/dev/null 2>&1 & )`, `taskpolicy -c
  utility`); the sweep writes `<cfg>/.mirror-status`, and the hook emits it through the accounts-board-style
  two-band reader.
- Impact:
  - ≈ **5.0 s off the p50 session start** on secondary/tertiary/quaternary [M3 difference], and the dispatcher
    stops being the slowest sync hook there.
  - Closes ~95 of the 100 joined kill-band runs [M3].
  - The mirror's adopt step (lib/config-mirror.zsh:330-339: `mv $_ents` then `rmdir && ln`) is no longer
    SIGTERMed mid-flight. A kill between the mv and the ln leaves an EMPTY real memory dir on that account,
    and safe mode never merges it back (:342, `(( convert )) || continue`). That is a silent memory loss path
    the 9 s watchdog makes reachable [E, static reading].
- Effort M. Risk: low to medium. The sweep must keep the ADOPT semantics, and a new-slug session is healed
  inline because its own slug is always checked. No settings.json edit (the child list lives in
  session-start-dispatch.sh:40).
- Conviction **88**.

**R1b (beyond startup). Apply the same split to the zsh launchers.** `claude2/3/4` and `claude-prev2/3/4`
run the full `_cc_sync_account` before `claude` even starts (~/.zshrc:185-187, :241, :257), so launch on
those accounts pays the walk once (launcher) and again (SessionStart).
- Impact ≈ 5–13 s of launch latency on isolated accounts [E from M4].
- Effort S once R1's `--slug` mode exists. Risk low. The edit is to ~/.zshrc, which is operator-owned
  (outside the repo).
- Conviction **75**.

**R2. Make cc-mission render event-driven and remove it from session-start.sh's critical path.**
- Where: hooks/session-start.sh:446-462 → replace with a zero-fork check (the board's `rendered <date>`
  token is not today, or `[ ~/.claude/autonomy/customer/rows -nt ~/.claude/rules/00-mission-board.md ]`) →
  detached single-flight render. Also render from `save_row` (bin/cc-mission:142-146), the single writer
  of the row files, which cmd_touch/cmd_add/cmd_seed (:422, :478, :544) go through, and from post-land
  (origin/main moved).
- Impact ≈ **1.5 s** off the session-start child at load ~520 [E, M10], and it removes the coupling where a
  slow render kills the MCP line.
- Effort S. Risk low. The comment at :437-439 already concedes a one-session lag. Add a loud systemMessage
  if the board's rendered date is older than yesterday. No settings.json edit.
- Conviction **85**.

**R3. Stop the per-start `python3 session-search.py --context-inject` whose output shipped 0 of 404 times.**
- Where: hooks/session-index-start.sh:37-63. Keep the stub upsert (:69-107).
- Impact: p50 0.8 s / p90 3.2 s / p99 7.8 s of child time, and one Python start per session start [M5]. 0
  tokens lost (nothing was shipped).
- Effort S. Risk low. If someone wants it back later, gate it on a per-cwd "informative" file written by the
  sweep. No settings.json edit.
- Conviction **80**.

**R4. pre-session-validate: an event-driven verdict, slow ≠ broken, no rollback on a timeout.**
- Where: hooks/pre-session-validate.sh:111-118 (verdict cache keyed by `readlink current` + binary mtime);
  :115/:146 (exit 124 → UNKNOWN-slow, no rollback); :159 (require a reproduced non-zero exit at a 10 s bound).
- Impact:
  - One Node start fewer per session start.
  - ~580 false "broken / no working version" alarms gone [M11], including the one in the 05:49Z incident.
  - Closes a destructive action triggered by load.
- Effort S. Risk low. Rollback stays available for genuinely broken builds. No settings.json edit.
- Conviction **82**.

**R5. A self-deadline in dod-persist and mailbox-drain (degrade output, tag it, ledger it).**
- Where: dod-persist.sh:407-421 (the SessionStart branch); mailbox-drain.sh before the python renders at
  :859 and :876.
- Impact: converts the measured 18 dod-persist and 34 mailbox-drain timeouts [M, a8_burst_census.py] from
  "nothing shipped, no record" into a labelled, smaller payload plus a ledger row. Expected timeout rate at
  load ≥ 100: 18 %/34 % → near 0 [E: a hook that self-limits at 3.5 s rarely meets a 5 s kill, though
  harness spawn latency is outside its control: desk-brief-inject's single record was cancelled at 13.4 s
  against a 5 s timeout].
- Effort S–M. Risk low. Mailbox already commits after emitting, so degraded delivery is still exact. No
  settings.json edit.
- Conviction **78**.

**R6. dod-persist: memoize lineage and read-file resolution within one run; then an event-driven header
index.**
- Where: dod-persist.sh:310-356, hooks/lib/dod-path.sh:125-226.
- Impact: (a) ≈ halves the hook's ~50–60 execs [E]; p50 1.7 → ~0.9 s at low load, ~4.9 → ~2.5 s at load
  300–400 [E, proportional to fork count, M6]. (b) removes the two bash-loop passes over the 90 KB store.
- Effort: (a) S, (b) M. Risk: low for (a), a pure refactor pinned by tests/dod-persist.bats. Medium for (b),
  a new artifact with a writer/reader contract. No settings.json edit.
- Conviction **70**.

**R7. Move activation-watch axes 2–3 and escalation-watch onto producers that already exist (deploy-live,
autonomy-sweep), read with two-band staleness.**
- Where: activation-watch.sh:456-479, :175-241, :352-454; escalation-watch.sh:76-108; the producers'
  scripts (scripts/deploy-live.sh, scripts/autonomy-sweep.sh).
- Impact ≈ 0.5–1.2 s of child time [E, M2 × exec counts]. Producer death becomes loud through the bands
  rather than through each session recomputing it.
- Effort M. Risk: low to medium. Liveness must stay keyed on the producer's OWN artifact, the
  escalation-watch header's rule (:27-33). No settings.json edit.
- Conviction **62**.

**R8. MCP probe: never inline on the critical path; record failed refreshes.**
- Where: hooks/session-start.sh:374-392 (cache-miss branch → emit UNKNOWN + detach); :180-202 (write a
  failure stamp); :414-427 (the claim carries "N refresh attempts failed since <ts>: <reason>").
- Impact: removes a 2.5–15 s inline probe from every start that misses the cache (a default-account session
  today, since ~/.claude's cache is 24 days old [M]), and makes the silently rotting secondary cache (8.5 h
  against a 300 s TTL) visible.
- Effort S. Risk low. A first-ever start loses one real answer and shows UNKNOWN with a reason, which the
  three-state design already allows (:415-418). No settings.json edit.
- Conviction **68**.

**R9. A shared "precomputed snippet" reader lib, so every precomputed hook is loud the same way.**
- Where: new `hooks/lib/precomputed.sh` that generalizes accounts-board.sh:51-190: missing / unreadable-age /
  empty / fresh / stale / ancient, with `producer_state` via one `launchctl list <label>`, always as a
  top-level systemMessage (0 tokens). Producers write atomically (tmp+mv) with a header: produced_at,
  producer label, input fingerprint. The reader optionally checks `[ input -nt snippet ]` (zero-fork) to say
  "inputs changed after render; refresh queued".
- Impact: closes the class of "a precomputed board silently goes stale" for R1/R2/R7 at once.
- Effort M. Risk low. No settings.json edit.
- Conviction **65**.

**R10 (minor). frontier-status in pure bash; setup-plan-symlinks counts cached for 10 min.**
- Impact ≈ 0.5–1.0 s of combined child time [E].
- Effort S. Risk low. No settings.json edit.
- Conviction **45**. These children never hit the bound (A3: present in 101/101 runs ≥ 9 s), so the saving only
  shows once R1–R3 have lowered the dispatcher's floor.

**Not recommended:**
- loadavg-gated skips (§4).
- `taskpolicy -b` on any startup work (§5).
- Raising hook priority (§5).
- A new launchd daemon for any of this: every item above reuses keepwarm, deploy-live, autonomy-sweep or
  cc-mission's own writers, or a lazy in-hook refresh.

**Expected combined effect [E].** On isolated accounts at low load, R1+R2+R3 bring the dispatcher from p50
7.6 s to roughly the shared-account floor minus R2/R3 (≈ 2.6 − 1.0 ≈ 1.5–2 s). The startup span is then set by
dod-persist and mailbox-drain (p50 ~1.5–1.7 s at low load; R5/R6 aim at their load tail). On shared accounts
the dispatcher drops from 2.6 s to about 1.5 s. Method: M3 class medians minus the M5/M10 component costs. The
components overlap in parallel, so this is an upper bound on the saving.

## 7. Dependencies on other axes

- The dispatcher still drops a killed child's output with no record (session-start-dispatch.sh:61-68, stderr
  closed at :33). R1 removes most kills but not the mechanism. The fault-tolerance axis owns making a kill
  loud (named child, elapsed time, recovery command).
- The token axis owns whether the MCP / Plans / Tasks / Frontier lines belong in additionalContext at all.
  This axis only makes them cheap.

## 8. Open questions

1. Direct per-child timing for config-mirror-assert, activation-watch and escalation-watch does not exist:
   they leave no sid-keyed trace. Attribution here is by elimination at equal load (M3) plus a replica of
   the walk (M4). A one-line `ts sid child elapsed rc` ledger written by the dispatcher would confirm it
   directly. That is the fault-tolerance axis's fix.
2. How long does the config-entry loop (1,288 ~/.claude entries, lib/config-mirror.zsh:140) plus
   `python3 cc-settings-parity` take on .claude-next? Inferred < ~2.6 s from the shared-class p50, not
   measured separately.
3. `save_row` (bin/cc-mission:142) does not call `cmd_render` itself, as far as the lines read show. Is any
   other trigger (post-land, a launchd job) already rendering the board? Its mtime was 00:28 while sessions
   started at 01:14 [M, stat + sessions.log], which fits "unchanged bytes are not rewritten" (:298-307),
   not "never rendered".
4. Why does the secondary account's MCP refresh keep failing (cache 8.5 h old at TTL 300 s)? Failures are not
   logged (only `ok` is cached, session-start.sh:116-119). R8 makes that visible.
5. Harness spawn latency under load: desk-brief-inject's only timed record was cancelled at 13.4 s against a
   5 s timeout, and the incident's dispatcher at 13.5 s against 12 s. How much of the tail is Claude Code
   starting and reaping hooks rather than the hooks themselves? That needs `--debug` per-hook timings
   (2.1.296+, per LOAD_AND_PROMPT_HOOK_TIMEOUTS O4).
6. 48 lead-crash-watchdog.sh processes are alive, 4 older than a day [M, ps]. This is a startup-spawned
   resident cost outside this axis; flagged for whichever axis owns long-lived hook children.
