# Wave B notes — B4, the parked-loop registry prefilter (REPORT ranks 16 + 11)

Not built. Conviction that the prefilter is net-positive: **55%** (bar: above 90%).

## What was proposed

Before the per-record walk in the poller's parked loop (`lr-reset-poller.sh` § 2, the
husk-noted path), run `grep -lqF <sid>` over the registry. If no registry file names the sid,
skip `lr_registry_live_rows` and `lr_registry_live_rows_in_cfg`, since neither can then find a
live row.

## Measured (read-only; 2026-10-11 ~05:24Z, load1 ~400, 46 registry files; 27 parked records, 32 `.husk-noted` markers)

One husk-noted record (0572baa6, cfg `~/.claude-quaternary`), two passes each:

| call | rc | wall |
|---|---|---|
| `grep -lqF <sid>` over the registry | 1 | 0.02-0.05 s |
| `lr_registry_live_rows` | 1 | 1.55-2.18 s |
| `lr_registry_live_rows_in_cfg` | 1 | 1.69-1.75 s |
| `lr_transplant_target` | 0 | 1.45-1.65 s |
| glob `projects/*/<sid>.jsonl.handed-off` | 0 | 0.41-0.71 s |
| glob `projects/*/<sid>.HANDOFF.json` | 0 | 0.56-0.62 s |
| `pgrep -f "resume <sid>"` | 1 | 0.12-0.17 s |

Script: `/tmp/wb-measure.sh <sid> <cfg> <lr-dir>` (sources lr-lib.sh and times each call; acts on nothing).

The path calls the registry walk at most twice per record (`:2194` behind `lrp_unmoved`, and
`:2225` `_in_cfg` on the target). So the prefilter saves about 1.7-3.9 s of the 13-28 s each
record costs, which is roughly 45-100 s per tick over 26 records at this load.

## Why it stays under 90%

1. **Wave C's D7 removes the same cost at its root.** D7 replaces the per-file basename+jq loop in
   `lr_registry_live_rows` with one jq (REPORT rank 11: 1.19 s down to 0.026 s), and
   `lr_registry_live_rows_in_cfg` is a caller of it. Once D7 lands, the prefilter saves about 0.05 s
   per record, which is noise. Built now, it would be a second spelling of the predicate ("does any
   registry row name this sid") in a second file. Its only lasting effect would be to shadow the
   real function, so a future change to registry matching would have to be made twice.
2. **The registry walk is not most of the per-record cost.** Even before D7 it is about 15-30% of
   the 13-28 s per record. The rest is `lr_transplant_target` (~1.5 s), two globs over every
   project dir of the store (~1-1.3 s; REPORT rank 29), the `lrp_unmoved` / `lr_state_current`
   reads, and python forks. The lever for rank 16 is the per-tick sid→transcript index (rank 29)
   and a cheaper transplant read, not the registry.
3. **Soundness holds, value does not.** The prefilter is sound: a row whose `.session_id` equals
   the sid contains it literally, because uuids need no JSON escaping. So the case against it is
   about value, not correctness.

## What would change the verdict

If D7 does not land, or lands without `_in_cfg` routed through it, the prefilter is worth about
2-4 s per record at load ~400, and conviction rises to about 85%. Re-measure with the script above
after wave C lands: `lr_registry_live_rows` under 0.1 s settles it as not needed.
