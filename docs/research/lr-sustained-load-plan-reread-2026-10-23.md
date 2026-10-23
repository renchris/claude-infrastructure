# LR sustained-load plan: re-read against trunk (2026-10-23, cloud session)

Item `de0bbab2e527`, "advance Implementation plan: the remaining limit-recover levers under permanent
load". Plan: `docs/plans/LR_SUSTAINED_LOAD_IMPL.md`. Run off-box (Anthropic VM,
`CLAUDE_CODE_REMOTE=true`), so no live state, no launchd, no kitty and no rig were reachable.

## Verdict

**The premise is partly stale.** The dispatcher's snapshot read "25 of 27 sections not DONE" and listed
W0b, W1, W2 … as PENDING. That was the plan's markers going stale. The work itself was not pending:
every buildable wave (W0b-W16, plus the unplanned W14f) landed on 2026-10-20/21. The lead's status
table (`impl/PLAN-STATUS.md`) and `REPORT.md` §8.1 (`9ae04b09a`, "every §4/§7 lever LANDED or
FILED") already recorded that. No wave headings or body status lines had been updated, so
`plan-phase-scan.sh` kept reading them as untouched.

**The plan is still open, and that is correct.** Everything left is gated on the operator, on the
live box, or on the clock. None of it can be done from a cloud VM:

| Remaining | Gate | Row / packet |
|---|---|---|
| Owed Tier-L pairs: W2 g9, W4 g9, W4b move9, W6 cure, W8, W9 T2, W10, W11 g9+g30, W12b typed-relaunch, W13 g30 idle-fanout, W14 kitty-deaf, W16 shed-e1 | the live rig on the desk, one run box-wide, kitty fd/coalition limits | `bbe7b5b1ba63` |
| Expectation flips that follow those runs (`load-expect.json` T1/T2/T5/target:W8; `g1-allow.tsv` `debt:typed-relaunch`) | the run verdicts | via the lead |
| W5 Part A flip to `on` | packet `4ffc4e1e5f1c` | `718ef4662d91` |
| W12 identity flip to `on` | ≥30 agreeing `recycle-kid-shadow` rows | `a76128229b2a` |
| W15 mode `on` | packet `0223cae3d185` + a ≥30/core latency bin | — |
| W16 `on`; T6 rig matrix (`lr-shed.py --tick` in an arm, not built) | packet `76a584cc935b`; shadow step `f259e20643bf` | — |
| W12b part 2 | packet `db44ab0ebc55` | — |
| W17 self-recovery | entry trigger: packet `4ab193daae88` (deadline 2026-11-03), R4 live, a measured wall | PARKED |
| Reconciler reload R4+R5 (W11, W13, W14, W14f go live) | operator | steps `3853d91f9626`, `7f151e71f291` |
| B8 kitty restart | operator | `1c94119a286d` |

The only buildable item is W16's T6 rig matrix. Building it blind from a VM that cannot run the rig
would be invented work, against the brief, so it was left for a desk session.

## What was run

- `git fetch --unshallow`; `git rev-list --count HEAD..origin/main` => 0, so this tree is trunk.
- `git rev-parse origin/main:bin/cc-dispatch` => `91998d21fe1f…`. That is EQUAL to the brief's
  dispatcher blob, so the dispatcher that fired this session is trunk.
- `git merge-base --is-ancestor <sha> origin/main` on all 45 shas that PLAN-STATUS.md cites.
  - 44 are ancestors.
  - `cfdb341d2` (the W14 now-audit mutant fix) is not a valid object. Its rebased landing is
    `6adbd797f`, "the efficacy-6 pacer mutant anchors on its own site again", which fixes the same
    void mutant that W11 caused.
- Each wave's section in the plan now carries what trunk shows:
  - **heading DONE**, when its done-condition is met on trunk with nothing owed: W0b, W1, W3, W7;
  - **body `**Status**: IN PROGRESS`**, when its code landed but a Tier-L run or flip is still owed
    (W2, W4, W4b, W5, W6, W8-W16, Phase 0). This follows the plan's own rule: "A wave is done when
    its code is landed, converged and proven by Tier G plus its Tier-L pair (owed runs included)";
  - **`PARKED`**, which the scanner reads as PENDING: W17.
- After the edit:
  - `plan-phase-scan.sh` => 5 DONE, 16 IN_PROGRESS, 6 PENDING (W17 and the five non-wave sections).
  - `--falsify` => rc 1. The plan is not falsified, which is the true state.

## For whoever closes the plan

The `--falsify` probe treats every level-≥2 PENDING section as open work. Four sections are reference
text and will never carry a marker: "Operator decisions and actions", "The guarantee", "Risks and open
questions" and "Dropped". So the plan stays unfalsifiable even after its last wave closes. Once the
owed queue and the packets settle, close the plan through its frontmatter (`status: complete`). That
is the probe's branch (a), and it does not depend on section markers. Do not mark reference sections
DONE to make the probe pass.
