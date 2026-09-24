# Dossier 6

## Brief
```
From /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, extract the table whose first column header is ctx_type: for every row give ctx_type, contexts and the "$ own" value exactly as written. Then say in one sentence which ctx_type has the highest $ own per context. numbers: {"rows": <row count>}.
```

## Returned headline
In the BASELINE.md billing table (main 1,055 contexts / $ own 19,747; workflow_agent 2,669 / 10,673; subagent 362 / 2,098), main has the highest $ own per context at about $18.72, against $5.80 for subagent and $4.00 for workflow_agent (computed with python3).

## Returned numbers
`{"rows": 3}`

## answer.md
# B08-r1: ctx_type table from BASELINE.md

Source: /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, lines 104-108 ("Billing type by context type", marked MEASURED, `census.md`).

Note: three tables in the file have `ctx_type` as their first column header (lines 104, 114, 124). Only the one at line 104 has `contexts` and `$ own` columns, so that is the table extracted here.

| ctx_type | contexts | $ own |
|---|---:|---:|
| main | 1,055 | 19,747 |
| workflow_agent | 2,669 | 10,673 |
| subagent | 362 | 2,098 |

$ own per context (computed with python3 as $ own / contexts):
- main: 19,747 / 1,055 = 18.72
- subagent: 2,098 / 362 = 5.80
- workflow_agent: 10,673 / 2,669 = 4.00

**Answer:** `main` has the highest $ own per context, about $18.72 per context, compared with $5.80 for subagent and $4.00 for workflow_agent.


## Tool calls (5) with the first 300 chars of each result
1. `Bash: {"command": "grep -n \"ctx_type\" /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md; ls /tmp/tokeff-regate/f2/out/B08-r1/ 2>&1", "description": "Locate ctx_type table and check output dir"}`
   → Exit code 1
104:| ctx_type | contexts | $ own | share | cache read | cw 5m | cw 1h | output | $ @5.5 |
114:| ctx_type | static attachments, median (p90) | system + tools (2.1.280) | static total | mean prefix per response | static share of a mean request | static share of that ctx's $ |
124:| ctx_ty
2. `Read: {"file_path": "/tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md", "offset": 98, "limit": 36}`
   → 98	| of which main thread idle >1h (517 wakes, mean 390k prefix) | 2,102 | 6.5% | 1,528 | `cache-writes.md` |
99	| Tool errors incl. recovery turns ($636 preventable) | 1,184 | 3.6% | 642 | `tool-errors.md` |
100	| Agent START writes (setup re-written by every sibling) | 1,760 | 5.4% | 1,362 | `cach
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B08-r1 && python3 -c \"\nfor n,c,d in [('main',1055,19747),('workflow_agent',2669,10673),('subagent',362,2098)]: print(n, round(d/c,2))\"", "description": "Create output dir and compute $ own per context"}`
   → main 18.72
workflow_agent 4.0
subagent 5.8
4. `Write: {"file_path": "/tmp/tokeff-regate/f2/out/B08-r1/answer.md", "content": "# B08-r1: ctx_type table from BASELINE.md\n\nSource: /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, lines 104-108 (\"Billing type by context type\", marked MEASURED, `census.md`).\n\nNote: thre`
   → File created successfully at: /tmp/tokeff-regate/f2/out/B08-r1/answer.md (file state is current in your context — no need to Read it back)
5. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B08-r1/answer.md", "headline": "In the BASELINE.md billing table (main 1,055 contexts / $ own 19,747; workflow_agent 2,669 / 10,673; subagent 362 / 2,098), main has the highest $ own per context at about $18.72, against $5.80 for subagent and $4.00 for work`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
