# Dossier 6

## Brief
```
From /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, extract the table whose first column header is ctx_type: for every row give ctx_type, contexts and the "$ own" value exactly as written. Then say in one sentence which ctx_type has the highest $ own per context. numbers: {"rows": <row count>}.
```

## Returned headline
The ctx_type table in BASELINE.md (lines 104-108) has 3 rows: main has 1,055 contexts and $ own of 19,747, workflow_agent has 2,669 and 10,673, and subagent has 362 and 2,098. main has the highest $ own per context at about $18.72 (19,747 / 1,055), against about $5.80 for subagent and $4.00 for workflow_agent.

## Returned numbers
`{"rows": 3}`

## answer.md
# ctx_type table from BASELINE.md

Source: /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, lines 104-108 ("Billing type by context type", labelled MEASURED, `census.md`).

| ctx_type | contexts | $ own |
|---|---:|---:|
| main | 1,055 | 19,747 |
| workflow_agent | 2,669 | 10,673 |
| subagent | 362 | 2,098 |

Rows: 3.

$ own per context (computed by dividing the two columns above): main about 18.72, subagent about 5.80, workflow_agent about 4.00.

The `main` ctx_type has the highest $ own per context, at about $18.72 (19,747 / 1,055), roughly 3x subagent and 4.7x workflow_agent.


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "grep -n \"ctx_type\" /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md; ls /tmp/tokeff-regate/f2/out/B08-r1/ 2>&1", "description": "Locate ctx_type table and check output dir"}`
   → 104:| ctx_type | contexts | $ own | share | cache read | cw 5m | cw 1h | output | $ @5.5 |
114:| ctx_type | static attachments, median (p90) | system + tools (2.1.280) | static total | mean prefix per response | static share of a mean request | static share of that ctx's $ |
124:| ctx_type | overall
2. `Read: {"file_path": "/tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md", "offset": 98, "limit": 16}`
   → 98	| of which main thread idle >1h (517 wakes, mean 390k prefix) | 2,102 | 6.5% | 1,528 | `cache-writes.md` |
99	| Tool errors incl. recovery turns ($636 preventable) | 1,184 | 3.6% | 642 | `tool-errors.md` |
100	| Agent START writes (setup re-written by every sibling) | 1,760 | 5.4% | 1,362 | `cach
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B08-r1 && cat > /tmp/tokeff-regate/f2/out/B08-r1/answer.md <<'EOF'\n# ctx_type table from BASELINE.md\n\nSource: /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, lines 104-108 (\"Billing type by context type\", labelled`
   → # ctx_type table from BASELINE.md

Source: /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, lines 104-108 ("Billing type by context type", labelled MEASURED, `census.md`).
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B08-r1/answer.md", "headline": "The ctx_type table in BASELINE.md (lines 104-108) has 3 rows: main has 1,055 contexts and $ own of 19,747, workflow_agent has 2,669 and 10,673, and subagent has 362 and 2,098. main has the highest $ own per context at about $`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
