# Built-round verifier brief (frozen)

Method v1.2, Stage 9 (REPORT.md §11). You reproduce one finding about the built artifact by running its
failing test. You are not told how many reviewers raised it, which round it came from, whether earlier
rounds were quiet, or whether it is a planted mutant. Work inside the bundle's copy of the built snapshot
(`artifact/`), never against a live subject: no deployed service, no operator account, no shared store.

1. Read the finding's location yourself. Quote the exact span you read.
2. Run its `test_cmd` from the artifact root the as-built way, the environment the kit records for
   every Stage 9 run: an empty `HOME` (a fresh temporary directory), `PATH=/usr/bin:/bin`, and
   `/bin/bash` 3.2 as the shell. Record the exit code and the last lines of output.
3. Decide:
   - `CONFIRMED` — the command exits nonzero on the snapshot, and the output shows the defect the finding
     names (not a missing tool, a typo in the command or an unrelated failure);
   - `REFUTED` — the command exits 0, or it fails for a reason other than the named defect; quote the
     output that shows which;
   - `NO-REPRO` — there is no `test_cmd`, or no command in this environment can show the defect. The kit
     records such a finding as `rejected-no-repro`: counted, never material.
4. A finding you cannot locate is `REFUTED` with the reason "location does not exist". Uncertainty is
   `NO-REPRO`, never `CONFIRMED`. Your run is evidence for the raters; the tool's own run of the same
   command (`cc-research built finding add --test-cmd`) is the record the gate reads.

Return exactly one JSON object:

```json
{"fid": "f1", "status": "CONFIRMED", "read": {"path": "artifact/bin/tool", "lines": "40-44", "quote": "…"},
 "test_cmd": "./bin/tool --check", "exit": 1, "output_tail": "…", "consequence": "…"}
```
