# memory-eval: does the right memory reach the agent?

`recall_eval.py` scores exact gold-path matches (R@1, R@5, MRR, each with a Wilson 95% interval;
the MRR interval is Wilson on n·MRR, so read it as approximate) per arm and per query style. Design:
`docs/research/truememory-2026-09-27.md` §3.5 and §5.11. Stdlib Python 3, under 1 s on the fixture.

**Arms**
- `loaded-only`: what the loader injects. Each store's `MEMORY.md` after the loader's strips
  (frontmatter, column-0 HTML comments), cut at 200 lines and 25,000 UTF-16 units; a gold file is
  reached if the surviving text links it. Resident `--rules` files count too, with the lessons their
  hooks link. The list is query-independent, so rank is order of appearance.
- `load-everything`: in-process FTS5 (porter unicode61) over every corpus file, fields name+H1 /
  description / body, `bm25` weights from `--weights a,b,c` (default 10,5,1).
- `retriever`: `bin/cc-memory-search --json --top 5 --store … --lessons … --rules … <query words>`
  as a subprocess, with `CC_MEMORY_SEARCH_WEIGHTS` set. Absent CLI: `ARM retriever NOT-RUN`.

**Styles**: `op` (operator verbatim), `op12` (its first 12 terms), `ag` (agent phrasing, written with
the gold known, so an upper bound), `authored` (the 50-query set, `--authored`).

**Classes kept out of hit/miss**: `gold-missing` (no gold in the corpus born before the miss, or the
record says so), `in-context-not-obeyed` (record `"outcome"`), `reinforced-superseding-memory` (the
top hit declares `Replaces:` / `Supersedes:`, or the record's `"superseding"` names it).

**Fixture** (synthetic, committed; pinned by `tests/memory-recall-eval.bats`):

    F=docs/research/memory-eval/fixture
    python3 docs/research/memory-eval/recall_eval.py --store $F/projects/demo-app/memory \
      --lessons $F/lessons --rules $F/rules/always-loaded.md --queries $F/queries.json

**Private gold** (`~/.claude/autonomy/memory-eval/field-queries.json`, never committed; absent means
a loud `NOT-RUN` and exit 0): pass one project's store, lessons and rules plus `--project <name>` for
the default scope, or every store for `--all` scope. Freeze first with `--snapshot DEST` (writes
`DEST/MANIFEST.sha256` and birth times), then score with `--corpus DEST`; a file that no longer
matches the manifest refuses with exit 3. Write results to
`~/.claude/autonomy/memory-eval/results-<date>.json` with `--out`, never into the repo.

**Holdout**: `sha1(id) % 5 == 0` is sealed. The default is `--split dev`; holdout numbers print only
with `--split holdout --unseal`. Not built: `capture_eval` (deferred), per-change f3 arms (dropped),
the `an3.py` recurrence counter (not found under the research directory).
