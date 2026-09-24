# Dossier 5

## Brief
```
From /tmp/tokeff-gate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, extract the table whose first column header is ctx_type: for every row give ctx_type, contexts and the "$ own" value exactly as written. Then say in one sentence which ctx_type has the highest $ own per context. numbers: {"rows": <row count>}.
```

## Returned headline
The ctx_type table in BASELINE.md has 3 rows: main (1,055 contexts, $ own 19,747), workflow_agent (2,669 contexts, $ own 10,673) and subagent (362 contexts, $ own 2,098). main has the highest $ own per context at about $18.72, compared with about $5.80 for subagent and about $4.00 for workflow_agent.

## Returned numbers
`{"rows": 3}`

## answer.md
# B08-r8: ctx_type table from BASELINE.md

Source: /tmp/tokeff-gate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, lines 104-108 ("Billing type by context type", marked MEASURED, from `census.md`).

| ctx_type | contexts | $ own |
|---|---:|---:|
| main | 1,055 | 19,747 |
| workflow_agent | 2,669 | 10,673 |
| subagent | 362 | 2,098 |

Rows: 3

$ own per context (my arithmetic on the table values: $ own / contexts):
- main: 19,747 / 1,055 ≈ 18.72
- workflow_agent: 10,673 / 2,669 ≈ 4.00
- subagent: 2,098 / 362 ≈ 5.80

main has the highest $ own per context, about $18.72 per context. That is roughly 3.2x subagent (about $5.80) and 4.7x workflow_agent (about $4.00).


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "grep -n \"ctx_type\" /tmp/tokeff-gate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md; ls /tmp/tokeff-gate/f2/out/B08-r8/ 2>&1", "description": "Locate ctx_type table and check output dir"}`
   → 104:| ctx_type | contexts | $ own | share | cache read | cw 5m | cw 1h | output | $ @5.5 |
114:| ctx_type | static attachments, median (p90) | system + tools (2.1.280) | static total | mean prefix per response | static share of a mean request | static share of that ctx's $ |
124:| ctx_type | overall
2. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md", "offset": 98, "limit": 16}`
   → 98	| of which main thread idle >1h (517 wakes, mean 390k prefix) | 2,102 | 6.5% | 1,528 | `cache-writes.md` |
99	| Tool errors incl. recovery turns ($636 preventable) | 1,184 | 3.6% | 642 | `tool-errors.md` |
100	| Agent START writes (setup re-written by every sibling) | 1,760 | 5.4% | 1,362 | `cach
3. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B08-r8/answer.md <<'EOF'\n# B08-r8: ctx_type table from BASELINE.md\n\nSource: /tmp/tokeff-gate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, lines 104-108 (\"Billing type by context type\", marked MEASURED, from `census.md`).\n\n| ctx_type`
   → # B08-r8: ctx_type table from BASELINE.md

Source: /tmp/tokeff-gate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, lines 104-108 ("Billing type by context type", marked MEASURED, from `census.md`).
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B08-r8/answer.md", "headline": "The ctx_type table in BASELINE.md has 3 rows: main (1,055 contexts, $ own 19,747), workflow_agent (2,669 contexts, $ own 10,673) and subagent (362 contexts, $ own 2,098). main has the highest $ own per context at about $18.72, `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
