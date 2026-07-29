-- RECONSTRUCTED, not observed. robobun's queue schema is private.
-- The lease columns are a LEAD ADDITION, not a copy of Bun: measurement (§0.1) shows 83% of
-- robobun's closed-unmerged PRs are self-closed duplicates of a sibling worker's PR opened
-- minutes earlier -- i.e. the real queue does NOT lease work before dispatch. Leasing is cheap
-- and removes that entire failure class.
CREATE TABLE work_item (
  id            BIGSERIAL PRIMARY KEY,
  run_token     TEXT NOT NULL,            -- reusable campaign handle; NOT unique per PR (see §6 C1)
  slug          TEXT NOT NULL,
  repo          TEXT NOT NULL,            -- token namespace deliberately spans repos
  source        TEXT NOT NULL,            -- 'issue'|'conformance'|'ci-flake'|'dead-code'|'perf'|'crash'
  source_ref    TEXT,                     -- e.g. 'oven-sh/bun#35936'
  fingerprint   TEXT,                     -- LEAD ADDITION: normalized symptom key for pre-dispatch dedupe
  state         TEXT NOT NULL DEFAULT 'queued',
  iteration     INT  NOT NULL DEFAULT 0,  -- survives gate rejections
  gate_passed   INT  NOT NULL DEFAULT 0,
  gate_rejected INT  NOT NULL DEFAULT 0,
  leased_by     TEXT,                     -- LEAD ADDITION
  leased_until  TIMESTAMPTZ,              -- LEAD ADDITION
  branch        TEXT,
  pr_number     INT,
  UNIQUE (repo, run_token, slug)
);
CREATE INDEX ON work_item (state, id);
CREATE UNIQUE INDEX ON work_item (repo, fingerprint) WHERE state IN ('queued','leased','in_progress');

-- Atomic claim: no two workers can hold the same item, so no duplicate-PR race.
-- UPDATE work_item SET state='leased', leased_by=$1, leased_until=now()+interval '2 hours'
--  WHERE id = (SELECT id FROM work_item WHERE state='queued'
--              ORDER BY id FOR UPDATE SKIP LOCKED LIMIT 1) RETURNING *;
