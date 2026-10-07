# Refutation of K05: cloud-only Stop hook as a pre-return gate

Written 2026-10-06 (local). Repo read-only at `/Users/chrisren/Development/.worktrees/wt-cc-205652-27362`, HEAD `593a21fc3`. Nothing was started, fired, dispatched or changed.
Labels: **M** = measured here (command named), **R** = reader claim I did not re-measure, **D** = documented (source and fetch date), **E** = estimated (method named), **T** = theoretical.

## Verdict

- Proposed: trial, conviction 35%, effort M.
- Corrected: **skip**, conviction **72%**. `refuted = true`.
- One line: of the hook's three arms, one duplicates a Stop hook the platform already runs, one checks a condition that is true for about 3% of branches at stop time, and the third targets a red that the existing refusal loop recovered 4 of 4 times; landed rows in the measured window move by 0.

## What the row gets right (checked)

| claim | check | result |
|---|---|---|
| Push and "gate green before commit" are prose at `bin/cc-dispatch:3084` | M: read of `bin/cc-dispatch:3083-3084` | True today. The cloud rail is one string: "gate green before commit; commit on THIS branch and PUSH it ... Do NOT run /ship" |
| Project settings carry no hooks | M: read of `.claude/settings.json` | True. Keys are `disabledMcpjsonServers` and `permissions` only |
| Repo hooks run in Anthropic-hosted sessions | D: `https://code.claude.com/docs/en/cloud-environments.md` fetched live 2026-10-06, 59,241 bytes, same size as the cached copy; lines 272, 441, 492 | True as documented, limited to "a session with one repository". Never observed on our private `POST /v1/sessions` create path |
| 6 of 31 fires took an rc 6 refusal: dead-assertion x4, TSV x1, suite x1 | M: `jq 'select(.outcome=="land-refused")' ~/.claude/autonomy/cloud/return.jsonl` since 09-22, plus `grep "✗ gate"` over the six `.land-refused` bodies | True. Six sessions, seven rc 6 rows (one session refused twice). 31 declarations carry a fire stamp of 09-22 or later (M: `grep -l` over `*.decl`) |
| Stop hook input has `last_assistant_message` | D: `https://code.claude.com/docs/en/hooks.md:2577`, fetched 2026-10-06 | True, and irrelevant: the proposed hook reads git state and two lints, not the reply text |

## Corrections to the row

1. **`doc-sht.md:19` does not support the claim it is cited for.** That page is the self-hosted CI recipe; the Stop hook there is installed "on the runner host's `~/.claude/`", and line 11 limits self-hosted environments to Team and Enterprise (D, cached copy of 2026-10-06). Our accounts are Max. The Anthropic-hosted claim rests on `doc-cloud-environments.md:272,441` alone.
2. **The "unpushed" arm duplicates a platform mechanism.** "Anthropic-hosted sessions run a `Stop` hook ... that prompts Claude to commit and push its work. The runner doesn't install one." (D: `https://code.claude.com/docs/en/self-hosted-environments-configuration.md:410`, fetched 2026-10-06; saved at `/tmp/cloud-blog-eval/scratch/k05-shc.md`). The reference script blocks once per turn on uncommitted changes or unpushed commits and bails on `stop_hook_active`. The row lists push-before-finish as prose only; the platform already mechanises it. Not observed in one of our VMs: no file under `docs/`, `scripts/` or `bin/` mentions the platform hook (M: `grep -rIl "stop-hook-git-check\|stop-hook-nudge"` returns only local-hook research).
3. **F21 is closed on the measured window.** 31 of 31 fires since 09-22 have a `.seen` sidecar, the record of a pushed ref (M: loop over `*.decl` with a fire stamp of 09-22 or later, testing for `.seen`). Lifetime 209 of 727 never pushed (R `a3-failure-ledger.md:95`); the last 15 days are 0 of 31.
4. **The "conflicts with origin/main" arm checks the wrong moment.** Replay of 381 stranded branches against the trunk commit at their own push: 3.1% conflict at t+0, 6.3% at +1 h, 25.2% at +24 h (M by the repo's own study, `docs/research/cloud-lane-redesign-2026-09-10/B1-stranded-branches.md:139-145`). The conflict pain (F39) is made by land latency after the session has stopped. A stop-time check sees roughly 1 branch in 32.
5. **The stated risk is aimed at the wrong component.** The two lints are portable: `scripts/bats-assert-liveness.py` imports only `argparse, glob, os, re, sys, traceback` (M: `grep "^import"`), and `scripts/tsv-pad-lint.sh` has no `stat -f`, `sed -i ''`, `date -j` or `plutil` (M: grep; only `readlink` and `mktemp`). F14 and F15 are about bats suites, not these static lints. The real loop risk is item 6.
6. **The platform loop cap does not bound a wrong red.** "after stop hooks have continued the turn eight times in a row, Claude Code overrides the next block ... The count of consecutive continuations resets each time Claude calls a tool." (D: `hooks.md:2579`, fetched 2026-10-06; cap added in 2.1.143, `CHANGELOG.md:4713`; env name present 4 times in the 2.1.284 binary, M: `grep -c CLAUDE_CODE_STOP_HOOK_BLOCK_CAP strings-284.txt`). A worker that edits or re-runs between blocks resets the count, so the hook must carry its own per-head counter. That is a second copy of `CC_REFUSAL_MAX_CYCLES` (`scripts/cloud-refusal-route.sh:100`, default 2).

## The pain point, measured session by session

Source: `~/.claude/autonomy/cloud/<id>.{land-refused,refusal-route,returned,retired,land-cost}` and `return.jsonl` (M, read 2026-10-06).

| session | red | router arm | end state | refusal to returned | desk time on the refused attempt |
|---|---|---|---|---|---|
| `01RfAyCB` 09-23 | dead-assertion, `tests/lr-lock.bats:175` | vm | returned, goal MET | 66 min | at most 45 s |
| `01Y5jpt8` 10-01 | dead-assertion, 5 lines in one suite | vm | returned, goal MET | 49 min | 155 s |
| `01MUcVcT` 10-01 | dead-assertion | vm | returned, goal MET | 71 min | 54 s |
| `01B69bzF` 10-01 | dead-assertion, twice | vm, 2 cycles | returned, goal MET | 87 min | 81 s + 62 s |
| `01A1uFXp` 09-23 | TSV field-collapse | **stale, routed none** | retired `conflict` | lost | 158 s (`.land-cost`) |
| `01GsyQPa` 09-22 | one failing suite | local-only: "the verdict names none of this session's own files" | superseded | lost | 1,414 s (`.land-cost`) |

Desk time is the gap from the pass's `pass-scope` row to the `land-refused` row, an upper bound (M: `jq` + `awk` over `return.jsonl`).

Findings:

- **Dead-assertion: 4 of 4 recovered by the existing loop.** The hook adds no landed row here. It would save five follow-up turns, 397 s of desk time (sum of the five attempts above) and 49 to 87 minutes of latency per session, over 15 days.
- **The cheap reds die early in the gate.** The dead-assertion arm runs in the statics phase, before bats (`scripts/ship-land.sh:4030-4112`; artifact order confirms it). The refused attempt costs 45 to 155 s against 1,205 to 2,467 s for the successful land of the same sessions (`.land-cost`). The desk land arm is the lane's bound (R `candidates.md:10`), and these refusals are under 10% of one land each.
- **TSV: lost, but not for want of a pre-return gate.** The router filed it `stale` and told nobody; that is the latent defect F32 (`stale_resolved()` tests file presence, `scripts/cloud-refusal-route.sh:400`, file last touched `7d72371ca` 2026-09-06, M: `git log -1`). The branch was retired `conflict` at epoch 1790169599, three seconds after its sibling `01RfAyCB` landed at 1790169596 on two of the same files (`lr-transplant.sh`, `VOLUNTARY_ACCOUNT_SWITCH.md`). Had the hook caught the TSV red in the VM, the two siblings would still have raced for the same files (T): at best a swap of which one landed.
- **Suite red: outside the hook.** The two cheap lints do not run suites, and the router found the red named none of the VM's files.
- **No rc 6 since 10-01T15:11Z** across 7 later fires (M: outcome counts in `return.jsonl` after 10-01T16:10Z: 96 pass-scope, 34 land-conflict, 24 land-deferred, 21 nothing-to-land, 12 waiting, 4 returned, 0 land-refused).

Net effect on the yardstick: **landed rows +0** in the window (M for the four dead-assertion sessions; T for the TSV sibling race). Quota saved: five follow-up turns into warm-then-idle sessions in 15 days (E: count of `vm` rows in the `.refusal-route` files). Latency saved feeds landability at about 3.4 points per hour (93.4% at push, 90.0% at +1 h, `B1-stranded-branches.md:139-140`), so about 0.17 rows per 31 fires (E: 5 round trips x 1 h x 0.034).

## Why a trial cannot be read now

- Supply: 1 open row, 120 blocked, 4,120 done (M: `bin/cc-backlog list --all --json | jq` group by status). Fires per day by branch stamp: 3, 2, 3, 2 on 10-01, 10-02, 10-04, 10-06 (M).
- Event rate: 5 lint reds per 31 fires, so about one per 6 fires, about one every 3 days at 2 fires a day (E). A before/after comparison on that rate needs weeks.
- Precondition: hook loading on sessions made by the private two-call create is unobserved (K03's probe, not run; the dispatchable cloud queue was 0, R `a4`).
- Side effect not in the row: a hook in tracked `.claude/settings.json` also spawns on every Stop of every local session in this repo and its worktrees, exiting early. The file's own `_what` says "the operator's ~/.claude/settings.json owns the fleet-wide hooks" (`.claude/settings.json:2`).

## Alternatives considered

| alternative | effort | why it beats or loses to K05 |
|---|---|---|
| Name the two commands in the cloud rail at `bin/cc-dispatch:3084` (`python3 scripts/bats-assert-liveness.py --format text <changed suites>`, `scripts/tsv-pad-lint.sh .`) | S | No dependency on hook loading. "Gate green" has no runnable referent in the VM today: `--precheck --working` exits 9 without shellcheck (`scripts/cloud-venue-provision.sh:24-27`) and the provisioner has zero callers (R `candidates.md:18`). Precedent for an exact-command rail: never-pushed went from 209 of 727 to 0 of 31 (R, M). Prose, so weaker than mechanism |
| Fix the router's `stale` predicate (`cloud-refusal-route.sh:400`, content not presence) | S | Addresses the one lint red the loop failed to route (TSV). Already proposed in `B2-refusal-autopsy.md:128-218` (R `a3:111`) |
| Desk runs `bats-assert-liveness-fix.py` during re-author | M | Zero quota and zero round trip, but the desk would edit VM-authored test bodies and the fixer declines some shapes (`scripts/ship-land.sh:4103-4108`). Ruled out on custody |
| K05 as written | M | Three arms, one useful, behind an unrun probe |
| Lint arm only, as a rider if K03's hook block lands and its probe reads present | S | The only form worth revisiting; needs its own per-head block counter |

## Adversarial pass on this refutation

- "Mechanism beats prose is this repo's own doctrine." It is, and the refusal loop is mechanism: 4 of 4. The claim under test is added value over it, not over nothing.
- "At higher volume the round trips add up." At any volume the saving per affected fire is one follow-up turn and under 160 s of desk time, and the affected share is about 1 fire in 6. It scales with volume but never becomes the bound; the bound is the successful land (866 to 1,205 s median, R `candidates.md:75`).
- "The loop is bounded at 2 cycles and one session used both." True (`01B69bzF`). A third red would have gone to the originator, whose delivery is itself defective (F33, R). This is the strongest argument for the lint arm and the reason conviction is 72, not 90.
- "The platform push hook may be absent on API-created sessions." Possible; unobserved either way. The measured 31 of 31 pushed holds regardless of which mechanism produced it.
- "n is 6." Yes. Every count here is small; none of them points the other way.

## Not verified

- Whether any hook, platform or repo, runs in sessions created through `POST /v1/sessions`.
- Whether the git proxy accepts a force-push to the session's own branch, which a VM-side rebase would need.
- The quota cost of one refusal follow-up turn; no per-turn meter exists for cloud sessions.
- Whether the in-VM Claude Code build carries the 2.1.259 fix for blocking Stop hooks missing the prompt cache (`CHANGELOG.md:2309`).

## Trigger to revisit

Any one of: K03's probe shows repo hooks load on our create path and a hooks block lands anyway; a dead-assertion or TSV red exhausts `CC_REFUSAL_MAX_CYCLES` and the row is lost; lint reds exceed 1 fire in 4 over 30 fires.
