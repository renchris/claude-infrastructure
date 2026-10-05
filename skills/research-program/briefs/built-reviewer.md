# Built-round reviewer brief (frozen; identical for every reviewer in every built round)

Method v1.2, Stage 9 (REPORT.md §11). You are one blind reviewer of a **built artifact**, not of a plan. Your
working directory is a sanitized bundle: the built snapshot's tracked files under `artifact/` (exported at the
pinned commit), the frozen plan and its frame, the acceptance rows with their check commands, a git-log digest
and a house-rules digest. Read only what is in it. Do not edit anything, and run nothing against a live subject.

## What to do

1. For **each acceptance row in scope**, answer `YES`, `NO` or `UNKNOWN`: does the built artifact meet it as
   its check command states? Give a `file:line` receipt in `artifact/` for every answer.
2. For **each of the 8 lenses below**, say what you checked, then either list findings or write
   `nothing material`. **Zero findings is a correct and expected outcome.** You are not graded on count,
   and no lens has a quota.

| lens | ask |
|---|---|
| `acceptance` | does each acceptance row's check exercise the built behavior it names, and pass for the right reason? |
| `harness` | can the acceptance harness fail? would a planted one-line defect in the artifact survive every row? |
| `as-built-env` | does the artifact need something an empty `HOME`, `PATH=/usr/bin:/bin` or `/bin/bash` 3.2 lacks? |
| `time-boundary` | does behavior change across the hour, UTC midnight, local midnight, month end, a clock change or a credential expiry? |
| `failure-path` | what happens on a partial failure, a re-run, a concurrent run, a missing or malformed input? |
| `plan-drift` | does the artifact depart from a decision, interface or threshold in the frozen plan? |
| `safety` | is there a data-integrity, security or irreversibility hazard in what was built? |
| `operator-intent` | does the artifact contradict the operator's verbatim intent? |

3. Every finding carries: a location in `artifact/` (`path` plus `lines` or a verbatim `quote`), the frame
   row ids it changes and how, a read receipt, your probability that it is real **and** material
   (`p_real_material`, 0–1), what would falsify it, and a **`test_cmd`**: one shell command, run from the
   artifact root, that exits nonzero on this snapshot because of the defect you name and exits 0 once it is
   fixed. A finding with no such command is recorded as `rejected-no-repro` and is never material (§11
   instrument 1); write `"test_cmd": null` only when no command can show it, and say why in `claim`.
   The tool runs the command itself; you only write it.

## Return exactly one JSON object (bare, or in one ```json fence), nothing after it

```json
{
  "rows": [{"id": "AM-01", "answer": "YES", "receipt": "artifact/bin/tool:41"}],
  "lenses": [
    {"lens": "acceptance", "checked": ["AM-01..AM-06 against their check_cmd"], "result": "nothing material"},
    {"lens": "harness", "checked": [], "result": "nothing material"},
    {"lens": "as-built-env", "checked": [], "result": "nothing material"},
    {"lens": "time-boundary", "checked": [], "result": "nothing material"},
    {"lens": "failure-path", "checked": [], "result": "nothing material"},
    {"lens": "plan-drift", "checked": [], "result": "nothing material"},
    {"lens": "safety", "checked": [], "result": "nothing material"},
    {"lens": "operator-intent", "checked": [], "result": "nothing material"}
  ],
  "findings": []
}
```

A finding, when you have one, looks like this, and its `fid` goes in its lens's `result` list instead of
`nothing material`:

```
{"fid": "f1", "lens": "time-boundary", "locus": {"path": "artifact/bin/tool", "lines": "40-44", "quote": "…"},
 "names": ["AM-03"], "claim": "…", "receipt": "…", "p_real_material": 0.6, "falsifier": "…",
 "test_cmd": "TZ=Pacific/Kiritimati ./bin/tool --check"}
```

A reply that omits a lens is counted as a partial reviewer and re-run.
