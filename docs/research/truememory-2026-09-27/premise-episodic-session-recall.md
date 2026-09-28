# Premise check: episodic-session-recall (lens=premise), 2026-09-27

## Do we already have it?
- The CLI half already exists. ~/.claude/bin/claude-search symlinks to ~/Development/claude-session-search/bin/claude-search.
  session-search.py:38 sets DB_PATH=~/.claude/session-index.db. :534-546 runs bm25 over sessions_fts. :601-620 runs chunks_fts (--deep-search).
  :97 extract_temporal handles "a week ago". :1762-1775 add --format json, --project, --after/--before and --preview.
  So the proposed `cc-memory-search --episodes` would duplicate it. bin/cc-memory-search does not exist (ls bin).
- A SessionStart pointer already exists. hooks/session-index-start.sh:27 calls session-search.py --context-inject, which emits
  "Search: claude-search \"query\"". :29-40 filters the line when it is uninformative.
- Agents already reach for it on their own. MEASURED: the #88 session 696eb098 ran `claude-search "exhaust-improvements"` (its transcript, tool call 41).
  search_log holds 66 rows 2026-09-07..09-23 and 658 in total (sqlite, read-only).
- No automatic cue-triggered episodic injection exists. There is no hook or commit for it: grep of hooks/ bin/ commands/ skills/ rules, and git log --all --grep.
  MEMORY_KNOWLEDGE_V2.md §4 R6 (:254-260) only bounds the foreign reader. It does not reject this idea.

## Is the gap real? Each cited incident, MEASURED from its transcript or the index
- #78 (d71e8e48, cafe wifi): at tool call 2 the agent ran `find ~/Development/personal -iname '*wifi*'`, found wifi-diagnosis/ and read its README.
  It resolved this itself. The operator's later fix was a skill (/cafe-wifi-optimization, session 0edb047a 09-26), which is procedural, not episodic.
- #88 (696eb098): the agent ran git log --all --grep and claude-search itself. The index was already in use.
- #106 (adb89f78, tertiary): the agent found last week's workflow in about 5 calls by `find .../workflows/wf_*.json | grep perrier`.
  The index row for the source session 5e498dc5 is a stub: message_count 0, first_prompt, keywords and files_changed all empty.
  --episodes could not have pointed to it.
- #110: 0 of the 9,411 rows mention truememory or buildingjosh (LIKE over first_prompt, keywords, files_changed, summary).
- Result: 0 of 4 cited incidents would have changed (MEASURED, small n).

## Index state (MEASURED, sqlite3 read-only, 2026-09-27)
- sessions: 9,411 rows, 2025-10-04..2026-09-27. 4,231 of them are before 2026-08-19.
- sessions_fts: 29 rows. chunks_fts: 679 (160 sessions). FTS 'kitty' returns 0, but a LIKE over first_prompt and keywords returns 206.
- Populated fields: first_prompt 7,666; summary 22; keywords 6,472; files_changed 3,823 (449 contain docs/research or docs/plans).

## Cost of the cue regex (MEASURED over /tmp/tm-research/prompts-typed.jsonl)
- Strict typed prompts: 652 of 2,113 fire (31%), mostly long briefs containing "before" or "again".
- Strict prompts of 600 chars or less: 69 of 1,463 fire (4.7%). The TM subset alone fires on 11.
- About 4 true episodic asks in 30 days gives an ESTIMATED precision of about 6% for the union regex.
