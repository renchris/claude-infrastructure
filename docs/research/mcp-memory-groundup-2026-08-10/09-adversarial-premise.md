# 09 · Adversarial premise check — per-session MCP memory as a first-order lever for 150+ resident

**VERDICT: SUSTAINED** — the premise is wrong and its load-bearing number is stale by 8×. The repo's own later census already refuted it; the axis is noise next to base footprint, the leak class, and admission control.

## Three sharpest facts

1. **507 MB/session was re-measured at 62 MB/session — and it was never a per-session term.**
   `census-fleet.md:386-401` (memory-econ-rearchitecture-2026-08-10), argv[0]-anchored + ppid-walked:
   33 live sessions, 12 MCP procs, 2.00 GB → **62 MB/session**; only **4/33 (12%) host** any stack
   (140 MB RSS / ~325 MB footprint each); **76% of the class was ONE leaked pid** (7993, 1,519/2,000 MB).
   Re-projected at 150: 18 hosts × 325 MB ≈ **5.9 GB, not 49 GB** — verbatim: *"MCP children do not
   foreclose 150-resident."* The 507 provenance (`scaling-bottlenecks-2026-08-09.md:31`) divided a
   leak-dominated aggregate (2 node procs >2 GB) by n=10 sessions — aggregate misread as marginal.

2. **Live box now corroborates: MCP-class ≈ 1.3 GB total, fleet-wide.** My census
   (`ps axo pid,rss,command`, argv[0]-anchored): 9 chrome-devtools-mcp/npm-exec/node procs
   (254+170+169+156+150+110+49+47+45 MB) + Cursor's 149 MB helper ≈ **1,299 MB**; zero browsermcp; the
   stacks drive **no browser at all** (`census-fleet.md:413`). Caution: a naive `grep mcp` returned 20
   procs/6.45 GB — 9 were claude.exe sessions whose argv *briefs mention* "mcp" (~5.2 GB). This axis's
   measurements keep failing in the inflationary direction; 507 was the same class of error.

3. **The arithmetic can't make it first-order.** Zeroing MCP entirely recovers ≤5.9 GB at 150 ≈ 17
   sessions of the 340 MB base — but the gap from N≈103-132 to 150 is 6-16 GB (`bottleneck-refute.md:54`),
   and death is footprint-independent: survived 170.85 GiB, died at 146.72 GiB; the kill is the ramp
   (0→30 GB swap in 300 s, headroom 40→10 GB, `census-fleet.md:107`) plus claude.exe self-bursts (54 procs
   >4 GB in 11 days, max 41 GB, `scaling-bottlenecks-2026-08-09.md` §1b) plus the 4-8 concurrent-active
   load gate and KMAX=8×4 refusing the 33rd session — all binding before MCP RSS does.

## What an MCP-focused team misses

**29/33 sessions carry zero MCP — you cannot recover memory from sessions that don't spend it.** The
real levers in this class are (a) **leak containment** (one pid = 76% of the class; footprint peaked
3,213 MB) and (b) **subagent MCP inheritance** (`census-fleet.md:400` — each subagent in an
MCP-configured project spawns its own 4-proc stack; a 15-way wave multiplies it) — a *fan-out* cost,
not a *resident* cost. Consolidation for residents optimizes the already-empty 88%.
