# gap-5: what emptied `sessions_fts` after the 2026-09-27 08:15Z rebuild

Every number here was MEASURED read-only on 2026-09-27/28 against copies of the live DB
(`/tmp/tm-research/gap5/session-index.db`, copied 00:51Z; `/tmp/tm-research/gap5/old.db`, copied from
`~/.claude/state/session-index.db.bak-2026-07-26`). Numbers labelled INFERRED or DOC are not measured.
The live DB, hooks, launchd jobs and repos were not modified.

## Verdict

The deleter is a `DROP TABLE sessions_fts`, not a `DELETE FROM sessions_fts`. The only live DROP sites
are the three migration blocks in `session_index_init_db`
(`claude-infrastructure/hooks/lib/session-index-helpers.sh:229-264`; the same code is in
`claude-session-search/hooks/lib/session-index-helpers.sh:116-157`).

The mechanism was reproduced piece by piece:

1. **The probe fails under lock.** The probe is
   `sqlite3 "$DB" "PRAGMA table_info(sessions);" 2>/dev/null | grep -c <col> || true` (`:230`, `:243`, `:258`).
   - It runs with **no busy timeout**.
   - It reads any sqlite3 failure as `0`, which means "column missing".
   - Under contention the probe returns "database is locked".
2. **The migration heredoc drops the table.** The heredoc at `:232-235` (and `:245-250`, `:260-263`) runs
   without `-bail`. Its `ALTER TABLE … ADD COLUMN` fails because the column is a duplicate, and sqlite3
   then **carries on and runs `DROP TABLE IF EXISTS sessions_fts`**.
3. **Errexit hides it.** sqlite3 exits with rc=1. Every caller runs under `set -euo pipefail`
   (`hooks/session-index-end.sh:5`, `hooks/session-index-start.sh:4`, `hooks/session-index-sweep.sh:14`,
   `claude-session-search/scripts/session-index-backfill.sh:8`). So the caller aborts **before** the
   `session_index_log "Migrated: …"` line at `:236`, `:251` and `:264`. That is why the log holds no
   "Migrated" line since 2026-03-23 (`grep -n Migrated ~/.claude/logs/session-index.log`: last hit is line 481).
4. **The index lock does not cover it.** The next `session_index_init_db` call re-creates an empty table
   through `CREATE VIRTUAL TABLE IF NOT EXISTS` (`:295`). init_db runs **outside the index lock** on:
   - every SessionStart stub (`session-index-start.sh:63`, in a backgrounded subshell with no lock);
   - every SessionEnd (`session-index-end.sh:29`, before the trylock at `:32`);
   - every 60 s sweep tick (`session-index-sweep.sh:75`, before the trylock at `:82`; also `:42` before `:44`).

   The lock therefore gives no protection.

## Evidence (MEASURED)

### A. The table was dropped and re-created, not emptied by DELETE
- **sqlite_master.** Rowids 19-23 are missing. `sessions_fts` sits at rowid 27, and its five shadow tables
  sit at 28-32 with root pages 6806, 6830, 6835, 6837 and 6838. Every other object keeps its low
  post-VACUUM root page (2-28).
  - Command: `sqlite3 session-index.db "select rowid,type,name from sqlite_master order by rowid"`.
- **Freelist.** The freelist (walked with a python page reader, see §Commands) holds 17,978 pages. They
  **include pages 20, 21, 22, 23 and 24**, exactly five pages: the root pages of the pre-drop shadow
  tables (data, idx, content, docsize, config).
  - They sit between `sqlite_autoindex_file_tracking_1` (19) and `idx_chunks_session` (25).
  - The last VACUUM ran at 2026-09-20 22:11:55 local (`session-index.log:32713`), so the drop came after it.
  - A `DELETE` cannot remove sqlite_master rows or free root pages. Only DROP+CREATE produces this layout.
- **Page count of `sessions_fts_data`.**
  - Live: 17 pages for 40 rows, rowids 2-44.
  - Replayed on a copy: the rebuild_fts SQL (`DELETE; INSERT…SELECT`), then `optimize`, then
    `DELETE FROM sessions_fts`, gives **10,629** data pages (FTS5 tombstones). 45 single-row upserts
    afterwards give **10,648**.
  - So a rebuild that was killed between its DELETE and its INSERT cannot produce today's state. The
    table is fresh.
- **Same signature in July.** The 07-26 backup shows the same fresh-table shape: 153 of 5,653 rows,
  rowids 1-154, 9 data pages. The first surviving row is 2026-07-25T21:03:43Z, after the 07-24 backfill.
  - **The wipe recurs.** The weekly backfill "FTS rebuild" (`backfill-scheduled.log:33,52,71,90`) has
    been the de-facto self-heal oscillating against it since at least July. This is the damping pattern
    the gap feared P1 would introduce, and it already exists.

### B. The window is 19:00:04Z to 19:01:37Z
- **Upper bound.** `sessions` rows indexed after 08:16Z (`sqlite3 … where indexed_at >= '2026-09-27T08:16'`)
  have no FTS row up to and including 9d72d5ea at 19:00:03-04Z. The first surviving row is bb889361 at
  19:01:46Z.
- **Rowid 1.** It is absent. Rowid 1 fits the f5fa3156 **stub** at 19:01:37Z
  (`session-index.log`: "14:01:37 Stub indexed for f5fa3156"). Its full re-index at 19:01:48Z then moved
  it to rowid 3, after bb889361 took rowid 2 at 19:01:46Z. So the new table existed by 19:01:37Z.
  - INFERRED from FTS5 rowid = max+1 plus the log order.

### C. Most probable individual caller (INFERRED, not proven)
- Two parallel `claude -p` probe sessions started at 19:01:32-35Z: bb889361 and f5fa3156, from session
  d90bd2e5, command `run rw-none "" & run rw-allow allow & wait` in `~/.claude/logs/bash-commands.log`.
  - They ran at load around 180 (`uptime` at 20:00 local read 182).
  - `cc-watchdog` recorded concurrent=8.
- f5fa3156's SessionStart stub logged. **bb889361's stub never logged**, although it is a primary session
  whose first_prompt is the rw-none prompt, so it did fire SessionStart.
  - A silent end is exactly what the errexit path produces (§D).
  - Other explanations exist. The stub's upsert could also have failed under errexit. So the candidates are:
    - the bb889361 SessionStart stub subshell, most likely;
    - a sweep tick near 19:00:46Z;
    - any other hook in the window.
- **The stale-lock reclaim at 14:01:46 local (19:01:46Z) is NOT the cause.**
  - The orphaned lock dir was created around 19:00:48Z. That matches the sweep's :46-48 tick phase
    (`~/.claude/state/session-index-sweep.last`).
  - init_db runs before any trylock, so the DROP path never touches the lock.
  - Reclaims are routine: 720 in total and 26 on 09-26/27 (`grep -c "Reclaiming stale index lock"`).
  - Its closeness to the first surviving rowid comes from the same load spike. It is not causal.

### D. Each link in the chain, reproduced on /tmp copies
- **Probe false-negative rate.** The exact `:230` probe, looped 1,500 times against a DB copy while 3
  short-lived writers and 2 openers churn it (`/tmp/tm-research/gap5/race/stress.sh`):
  - run 1: **39/1500 = 2.6%** return `0`;
  - run 2: **46/1500 = 3.1%** return `0`;
  - stderr every time: `Error: in prepare, database is locked (5)`.
  - The same probe with `.timeout 5000` (`stress_timeout.sh`) gave **0/1500**. Load differed between runs,
    so read this as indicative only.
- **Continue-on-error.** sqlite3 3.43.2 heredoc without `-bail`: statement 1 fails, statement 2 **still
  runs**, rc=1. With `-bail`, statement 2 does not run.
  - Measured with a non-DDL stand-in. A PreToolUse hook blocks DDL text in Bash commands, so no DROP was
    executed, even on a copy.
- **Silent exit.** The real `session_index_init_db`, sourced under `set -euo pipefail` against a junk
  non-SQLite file in a fake HOME (`/tmp/tm-research/gap5/errexit_probe.sh`), traces `has_col=0`, then
  the migration sqlite3, then **rc=1, no "Migrated" log line, and the line after init_db never reached**.
- **The sweep already hits this lock.** `~/.claude/logs/sweep-daemon.log` holds 3 lines of
  `Parse error near line 1/2: database is locked (5)`. That is the SCHEMA heredoc (`:268-271`), which sets
  its busy timeout only at line 3.
  - The probes' own failures are invisible because of `2>/dev/null`.

### E. Callers exonerated (MEASURED)
- **The DELETE-based sites** (the 10.6k-page signature in §A rules them out):
  - `session_index_rebuild_fts` (`helpers:1127-1133`; sibling `helpers:548-553`);
  - `claude-session-search/scripts/session-index-backfill.sh:635`;
  - `claude-session-search/install.sh:220`;
  - `session-index-tag.py:1010-1014` (a per-batch delete and re-insert).
- **Scheduling.** The backfill runs only on Sunday at 03:00 local (launchd `StartCalendarInterval`) and
  repairs itself in Phase 6. The tagger has no launchd job and `tagged_at` is set on 0 rows.
- **Retention** (`helpers:1083`) deletes `sessions` rows too. `sessions` grew from 9,351 to 9,422, so
  retention did not run here.
- **No agent Bash command** touched the index in the window (`bash-commands.log` 18:55-19:02Z).
- **Nothing else can DROP it.** `grep -rn "DROP TABLE IF EXISTS sessions_fts"` finds only the 6 migration
  sites and `assets/demo/build_demo_db.py:127`, which writes a demo DB path.

## What this means for the gap and the synthesis
- **A trigger or a DELETE log cannot find this deleter** (DOC, SQLite semantics, not executed here).
  SQLite has no DDL triggers, `CREATE TRIGGER` refuses virtual tables, and DROP fires no DELETE triggers.
  The cheap detector is a **table-identity fingerprint**:
  - `SELECT rootpage FROM sqlite_master WHERE name='sessions_fts_data'` plus the sqlite_master rowid of
    `sessions_fts`, logged each sweep tick;
  - a change without a VACUUM means DROP+CREATE.
- **The fix is P0-sized (XS-S) and belongs before any parity self-heal.** In both helper copies:
  - **Probe.** Use `session_index_sql` (busy timeout) and
    `SELECT name FROM pragma_table_info('sessions')`. On rc≠0 or empty output, log
    `init_db probe failed rc=N` and **skip all migrations**. Never infer "missing" from a failed read.
    `init_tracking` at `:1190-1196` already uses `session_index_sql`, so the pattern exists in-file.
  - **Migration.** Run it with `-bail` in one `BEGIN IMMEDIATE … COMMIT`: `ALTER`, `DROP`, `CREATE VIRTUAL`,
    then `INSERT…SELECT`. SQLite DDL is transactional, so a migration either completes and repopulates,
    or changes nothing. Log **before** the DDL.
  - **Hot paths.** Gate the hot paths on `PRAGMA user_version`, or take migrations out of the hooks and
    sweep entirely, so a probe that runs about 1,500+ times a day cannot destroy data.
  - **Regression test.** A bats case with an unreadable or locked DB asserts that `sessions_fts` survives
    and that a log line appears. The errexit_probe shows today's code fails that case.
- **Dispositions in SYNTHESIS.md §3.2 (#2):** it stays build-now. P1 changes as follows:
  - The "Harden the migration probes" bullet (`SYNTHESIS.md:164-165`) is **the root-cause fix, not
    hardening**. Promote it to P0, next to the awk fix.
  - The `BEGIN IMMEDIATE` rebuild drops to optional hygiene, because it is not the cause.
  - The sibling-repo item changes from "trace the rebuild callers" to "port the same init_db fix to
    `claude-session-search/hooks/lib/session-index-helpers.sh:116-157`". backfill.sh sources that copy
    (`:12`, `:48`).
  - Keep the hourly parity check, but make it alarm-first. Log the fingerprint and rebuild only once the
    probe fix is in. It stops being a damper once the deleter is gone.
- **#15 and #18** depend on #2 P0 plus the probe fix, not on the P1 self-heal. Their order is unchanged
  and they can start sooner.
- **#3 (heartbeats) gains a concrete case.** Hooks that die under errexit leave no log line; bb889361's
  missing stub line is one example.
- **Unrelated but seen.** A weekly oscillation in `sessions` itself:
  - retention removes 727-1,888 rows per week (`session-index.log:27104-32714`);
  - the backfill and history gap-fill re-add them.

  Not investigated. Flagged only.

## Commands and artefacts
- The DB copy, the 07-26 copy and `exp.db` (replay): `/tmp/tm-research/gap5/`.
- Stress harness: `/tmp/tm-research/gap5/race/stress.sh`, `stress_timeout.sh`, `zeros.log`.
- Errexit harness: `/tmp/tm-research/gap5/errexit_probe.sh` (fake HOME `/tmp/tm-research/gap5/fh`).
- Freelist walker: an inline python3 script reading the header at offsets 32/36 and following the trunk
  pages (in this session's transcript). Result: free=17,978, low free pages = [20, 21, 22, 23, 24].
