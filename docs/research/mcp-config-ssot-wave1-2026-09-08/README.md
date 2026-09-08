# MCP_CONFIG_SSOT — Wave 1 research artifacts (2026-09-08)

The four per-axis artifacts behind `docs/plans/MCP_CONFIG_SSOT.md` § Wave 1 — research findings.
The plan carries the conclusions; these carry the working. Committed because the plan CITES them by
path, and they were written to a session scratchpad that gets reaped — a cited path that resolves
nowhere is a deletion wearing a pointer's clothes.

| file | axis | how it was produced |
|---|---|---|
| `A-flag-semantics.md` | `--mcp-config` / `--strict-mcp-config` semantics on 2.1.260 | lead, empirical (marker-file probe) |
| `BDEF-lead.md` | chokepoint · ms365 interaction · migration surface · SSOT location | lead, serial |
| `C-governance.md` | what `mcp-no-inherit` actually encodes, and the five couplings | subagent |
| `G-adversarial.md` | baseline-blind red-team of the design | subagent (frontier-derivation) |

**Why B, D, E and F were run on the lead rather than fanned out:** the wave was fired as 7
subagents and the machine's capacity gate refused 5 of them (16 sessions mid-turn against a ceiling
of 8). The gate's own instruction is to run the work serially rather than retry-storm it, so that
is what happened. C and G are the two that were admitted.

**Read `G-adversarial.md` against the tree as it was mid-session:** it inspected an in-progress
worktree and correctly reported the SSOT as untracked with no install.sh call site and no bats —
that was this session's own uncommitted work, and all three landed in `b64f32457`. Its findings on
2.1.260's plugin/marketplace MCP scope, the fatal zero-byte SSOT, and `--mcp-config` being ignored
in `--cloud` sessions are unaffected by that and remain open observations.
