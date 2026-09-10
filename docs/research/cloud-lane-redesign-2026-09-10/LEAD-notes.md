# Lead notes (Fable 5.1 session dc4eb0fa) — measured on the lead while the wave ran, 2026-09-10 ~21:30Z

## Denominator reframing (measured, $S/eligible-sweep.json ⋈ $S/open.json)
- cc-eligible sweep over 296 non-done rows: eligible 22 = 5 open + 2 claimed + 15 blocked; refused 274 = 27 open + 2 claimed + 245 blocked.
- The C-doc's "23/353 = 6.5% ceiling" divides by a pile that is 88% operator-blocked. Over the agent-drainable 36: classifier admits 7 (19%); split-reachable 7 (19%) with no config, 13 (36%) with cross-repo attach + gh. See A1-reach-stratum.md.

## Lane self-maintenance (measured)
- Backlog rows mentioning the cloud lane (title/needs/evidence/source/condition regex): done 313/3118 (10.0%), blocked 27/260 (10.4%), open 5/31. Title-only: 144 done, 23 blocked.
- Trunk commits since 2026-08-01 touching lane files: 157 of 3,049 (5.1%) — W32 37, W33 56, W34 8, W35 16, W36 19, W37 21. Lane code+tests: 20,167 lines (bin/cc-cloud, cc-eligible, cc-offload, scripts/cloud-*, tests).
- Contrast: 88 declarations with land evidence (79 content-verified `.returned`). The lane has generated more closed backlog rows about itself (≥144 by title) than rows it has landed.

## Return arm (measured, idl + return.jsonl + sidecars)
- cloud-return-lane rows 97: cloud-return rc 0 ×3, 137 ×12 (cut at 5,400 s), 4 ×63 (lock held). Return-pass elapsed n=15: min 2,028 median 5,411 max 12,745 s.
- return.jsonl `returned` by day: 09-04 16 · 09-05 3 · 09-06 1 · 09-07 7 · 09-08 0 · 09-09 0 · 09-10 0. 09-08..10 dominated by pass-scope / abstain / land-refused-cached.
- `.land-cost` 54 files, 36 non-floor: median 344 s, max 3,977 s. `.land-refused` rc: 70×51, 65×17, 5×9, 69, 143, 6. `.returned`: returned 51, returned-close-failed 28, superseded 1.
- decl by day: 08-31 21 · 09-01 20 · 09-02 26 · 09-03 32 · 09-04 31 · 09-07 5 · 09-09 1 · 09-10 4 (two of today's on next3/next4 at items 1dd6fbb6766c, 2a65b9bf722d).

## Quota (claude-accounts --readout ~21:00Z)
- next weekly 100% LIMITED · next2 95% · next4 73% · next3 51%; all four "on pace to fill the window". Box load 13.1 on 10 cores; capacity-admit refused a spawn at 8 mid-turn sessions.

## Design hypotheses to test against the wave
H1 The 12.8% is dominated by the RETURN path's latency (tick-starved, lock-serialized, bound-cut), which manufactures both `superseded` and `conflict`; the VM's work itself is not the loss. (B1 curve, B3 inventory.)
H2 The only resource the fleet is short of that VMs can add is machine capacity; quota is shared (C1) and binding today (readout). (C1, C3.)
H3 The gate is the expensive local step for BOTH lanes; the off-box resource that does not spend Max quota is GitHub Actions, not Anthropic VMs. A trusted tree-sha green stamp would cut per-land box cost and latency for both lanes. (D3.)
H4 Supply, not capacity, bounds cloud post-cure: ~2 fires/day, 7-13 reachable rows. The flow (A2) decides whether that supply is structurally small.
