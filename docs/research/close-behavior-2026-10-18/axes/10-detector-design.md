# Axis 10 — Detector design and false-positive measurement (2026-10-18)

Status: in progress (written incrementally).

Goal: a deterministic check that says "this session left drivable follow-on undriven", silent when
nothing drivable remains. Read-only study; prototype lives in `/tmp/detector-proto/` (not in repo).

## 1. Corpus survey: what markers the docs use today

Corpus: `docs/research/*/README.md` (55 files) and `docs/plans/*.md` (122 files) [M: `ls … | wc -l`].

Doc counts containing each marker (R = research READMEs, P = plans) [M: `grep -lE` per pattern]:

| Marker (regex) | R (of 55) | P (of 122) |
|---|---|---|
| heading `Wave N` | 2 | 7 |
| heading implementation / waves / rollout / phases | 1 | 44 |
| heading recommend… | 1 | 7 |
| heading next steps / follow-on / remaining / TODO | 2 | 9 |
| table column `Conv.` / `Conviction` / `Confidence` | 7 | 5 |
| prose `NN% conviction` / `conviction NN` | 5 | 18 |
| table column `Status` | 1 | 13 |
| word `landed` | 22 | 118 |
| `✅` | 2 | 51 |
| `DONE` | 2 | 89 |
| backticked 7-12 hex sha | 31 | 117 |
| open checkbox `- [ ]` | 0 | 1 |
| `Scope (frozen)` | 3 | 89 |
| `**Status**:` line | 2 | 29 |

Observations:

- Plans carry a document-level YAML `status:` frontmatter (open / in-progress / complete /
  superseded) enforced for new plans by `hooks/validate-plan-structure.sh:6,37,78` and read by
  `scripts/find-plan.sh:40-55` (`--list-open`). Census [M: `head -12 | grep -m1 ^status:`]: 66
  complete, 30 open, 23 in-progress, 2 superseded, 1 done. That is a DOCUMENT verdict, not a per-row
  one, and nothing at Stop/close time reads it.
- Research READMEs have NO convention: 1 of 55 has frontmatter `status:` (grok-wiki-audit), 2 have a
  `Status:` line; headings are free-form (`## Answer`, `## Results`, `## Verdicts`). The startup-hooks
  README is the only research README with `### Wave N` headings.
- Where per-row status exists it is free text in a `Status` cell (13 plans), e.g.
  `docs/plans/LOAD_ROOT_CAUSE_2026_10_17.md:35`, `docs/plans/HANDOFF_HIGH_VALUE_CAPTURE.md:20`.
- The dominant way the corpus records "this row was driven" is NOT on the row. It is a separate
  ledger that names the row id: a task table (`docs/plans/NONLIMIT_RESUME_LADDER.md:65` `T10 | W3-R1 —
  land … | DONE 2026-09-17 | … c50a363b1`, for the recommendation row at `:880`), a later landing table
  (`:899` `R1 | … | LANDED | c50a363b1`), a dated status log (`docs/plans/LIMIT_DETECT_100P.md:587-640`
  "W0 is DONE — `b3f320fc5`"), a "What landed, by spec item" table
  (`docs/research/kitty-crash-2026-10-15/README.md:435-447`), or a header `Status (date, phase 2): … landed at
  fb3edd4ff` (`kitty-crash…/README.md:7`). One research README marks status in-row the way a checker
  needs it: `docs/research/opus55-utilization-2026-09-22/README.md:232-275` ("1. ✅ **… — DONE 2026-09-22**
  (landed `501e4490e` …)").
- The incident doc has neither form: §2 ranked rows (`startup-hooks…/README.md:29-75`) carry
  `Conv.` but no status; §5 wave units (`:159-222`) carry neither conviction nor status, and reference
  §2 rows by `#N` (`1.2 Event name (#3)`, `:164`).
