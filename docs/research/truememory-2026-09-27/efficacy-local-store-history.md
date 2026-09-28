# efficacy lens: local-store-history
Clone: /tmp/truememory-src, shallow (50 commits, HEAD 063e5b8 2026-08-29), so older history is cut.

What TM actually has:
- storage.py:416-450 _backup_database: SQLite Online Backup API snapshot, used only before schema migration (call site storage.py:500), rotated to keep 3 (storage.py:351, 365-393). Introduced by f48d110 (#691/#707). Tested: tests/test_issue_691_atomic_writes.py:75-98 (single-file snapshot holds 10 rows), tests/test_issue_650_db_corruption.py:64-108 (rotation cap and no accumulation on failing migration). I could NOT run the tests: the package is not installed (PackageNotFoundError), and I did not install it.
- tier_switch/manager.py:475-495 backup_db: shutil.copy2 of a WAL DB (not consistent, no -wal copy), keep 3; called at manager.py:168 and :258. The same bug class #691 fixed elsewhere, still present here.
- Supersede: dedup.py:11 says "old memory is superseded (not deleted)", but the UPDATE path goes pipeline.py:741-750 -> engine.py:1196 -> storage.py:1150-1182, an in-place UPDATE with no prior-version row. So TM keeps no history of automated mutations.
- Benchmarks: no benchmark code path calls a backup (grep hits are only JSON result files). The mechanism does not affect the benchmark numbers; it is data-integrity hygiene.
- Issues: #691 and #650 closed (data-integrity). #686 (vector migration loses all vectors on crash) and #246/#302 (backlog drain lost 394-418 sessions) are further data-loss incidents; none was resolved by versioned history.

Verdict basis: TM has no per-mutation history and no undo. The git-per-store proposal is ours, not extracted from TM. TM's evidence is at most a negative lesson: 3 rotated pre-migration snapshots and in-place UPDATE are the exact gap our R2 names.
Our side (measured now): 39 non-symlink non-empty stores (the candidate says 36), 14 symlinked; 0 have a .git dir; bin/cc-memory-forget does not exist; restic SOURCE is ~/.claude/archives/claude-code/ (restic-claude-archive-backup.sh:58); R2 text confirmed at MEMORY_KNOWLEDGE_V2.md:231-237.
