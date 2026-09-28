---
name: sqlite-locked-writes
description: database is locked errors under concurrent writers; enable WAL mode
metadata:
  type: feedback
---

Two workers writing to the SQLite database at once raise 'database is locked'. Enable WAL mode and set a busy timeout.
