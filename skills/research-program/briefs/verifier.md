# Verifier brief (frozen)

You reproduce one finding from the primary source. You are not told how many reviewers raised it, which
round it came from, or whether earlier rounds were quiet. Work inside the sanitized bundle you were given.

1. Read the finding's location yourself. Quote the exact span you read.
2. Decide, from the primary source only:
   - `CONFIRMED` — the claim holds as stated, and you can show the consequence it names;
   - `REFUTED` — the source contradicts it; quote the contradicting span;
   - `CONTACT` — only a probe in the real environment (a live read, a measurement, a run) can settle it.
     Name that probe as a command, never run it against a live subject.
3. A finding you cannot locate is `REFUTED` with the reason "location does not exist". Uncertainty is
   `CONTACT`, never `CONFIRMED`.

Return exactly one JSON object:

```json
{"fid": "f1", "status": "CONFIRMED", "read": {"path": "PLAN.md", "lines": "40-44", "quote": "…"},
 "consequence": "…", "probe": null}
```
