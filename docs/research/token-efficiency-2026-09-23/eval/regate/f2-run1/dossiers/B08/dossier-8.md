# Dossier 8

## Brief
```
From /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, extract the table whose first column header is ctx_type: for every row give ctx_type, contexts and the "$ own" value exactly as written. Then say in one sentence which ctx_type has the highest $ own per context. numbers: {"rows": <row count>}.
```

## Returned headline
The ctx_type billing table (BASELINE.md line 104) has 3 rows: main (1,055 contexts, $ own 19,747), workflow_agent (2,669, 10,673) and subagent (362, 2,098), and main has the highest $ own per context at about $18.72 (python3 division), against $5.80 for subagent and $4.00 for workflow_agent.

## Returned numbers
`{"rows": 3}`

## answer.md
# B08: the ctx_type table in BASELINE.md

Source: /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, lines 104-108 ("Billing type by context type", MEASURED, `census.md`).

| ctx_type | contexts | $ own |
|---|---:|---:|
| main | 1,055 | 19,747 |
| workflow_agent | 2,669 | 10,673 |
| subagent | 362 | 2,098 |

Rows: 3

`main` has the highest $ own per context: about $18.72 per context, against $5.80 for subagent and $4.00 for workflow_agent. I worked these out as $ own divided by contexts with python3.

Note: two other tables in the file also have ctx_type as their first column header (line 114, static tokens, and line 124, cache hit rate). Neither has a contexts column or a "$ own" column, so the table at line 104 is the only one that fits the brief.


## Tool calls (5) with the first 300 chars of each result
1. `Bash: {"command": "grep -n \"ctx_type\" /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md; ls /tmp/tokeff-regate/f2/out/B08-r5/ 2>&1", "description": "Locate the ctx_type table and check output dir"}`
   → Exit code 1
104:| ctx_type | contexts | $ own | share | cache read | cw 5m | cw 1h | output | $ @5.5 |
114:| ctx_type | static attachments, median (p90) | system + tools (2.1.280) | static total | mean prefix per response | static share of a mean request | static share of that ctx's $ |
124:| ctx_ty
2. `Read: {"file_path": "/tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md", "offset": 95, "limit": 40}`
   → 95	| Worker contexts (subagent + workflow agents) | 12,771 | 39.3% | 7,652 | `census.md` |
96	| Stop-hook forced continuation turns (3,029; 1,973 waste-likely = $939) | 3,623 | 11.1% | 1,649 | `hooks.md` |
97	| Cache rewrites after a miss (36% of write $) | 3,316 | 10.2% | 2,404 | `cache-writes.md` 
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B08-r5 && python3 -c \"\nfor n,c,d in [('main',1055,19747),('workflow_agent',2669,10673),('subagent',362,2098)]: print(n, round(d/c,2))\"", "description": "Create output dir and compute $ own per context"}`
   → main 18.72
workflow_agent 4.0
subagent 5.8
4. `Write: {"file_path": "/tmp/tokeff-regate/f2/out/B08-r5/answer.md", "content": "# B08: the ctx_type table in BASELINE.md\n\nSource: /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, lines 104-108 (\"Billing type by context type\", MEASURED, `census.md`).\n\n| ctx_type | conte`
   → File created successfully at: /tmp/tokeff-regate/f2/out/B08-r5/answer.md (file state is current in your context — no need to Read it back)
5. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B08-r5/answer.md", "headline": "The ctx_type billing table (BASELINE.md line 104) has 3 rows: main (1,055 contexts, $ own 19,747), workflow_agent (2,669, 10,673) and subagent (362, 2,098), and main has the highest $ own per context at about $18.72 (python3 `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
