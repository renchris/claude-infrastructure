# Refute K07 — "Put the cloud surface into the cc-upgrade audit and retire the 2.1.289 target"

Date of all reads: 2026-10-06. Repo: `/Users/chrisren/Development/.worktrees/wt-cc-205652-27362` (read-only).
Labels: **M** = measured by me (command named), **D** = primary source states it, **I** = my inference.

## Verdict

- refuted: **false** (the category "adopt" survives; the proposed change text does not survive as written)
- corrected verdict: **adopt, narrowed**, conviction **65%** (proposer: 80%), effort S for the holds.md edit, S-M if a gate probe is added
- Effect on landed rows per unit of quota: **none** (I). This is upgrade hygiene for the desk half of the lane.

## 1. What I checked against the primary source

| Row claim | Result | Evidence |
|---|---|---|
| `holds.md:49` says "Target 2.1.289" | TRUE | `skills/cc-upgrade/holds.md:49` "**Target 2.1.289; never 2.1.285–2.1.287.**" (M, Read). Last touched 2026-10-04 (`git log`: `43cefd9c5`, `216a7aa75`); no later commit on any branch (M, `git log --all --since=2026-10-04 -- skills/cc-upgrade/` empty) |
| cc-upgrade has no cloud row | TRUE | `grep -n -i cloud skills/cc-upgrade/*.md` = 0 hits (M). MANIFEST rows 2.1.280-2.1.284: 0 mentions of "cloud" (M, python over `~/.claude-versions/MANIFEST.jsonl`, 35 rows) |
| The 281-284 audit filed cloud rows as out of scope | TRUE, in three axis notes | `docs/research/sonnet55-utilization-2026-09-28/notes/cc284-teams.md:5` "not referenced by our config"; `cc284-hooks.md:80`; `cc284-workflows.md:5-6` "NEUTRAL for this fleet" (M). The four audit axes in `skills/cc-upgrade/audit.md:76-86` contain no cloud or headless-transport axis, so the gap is structural |
| 2.1.291 fixes a 2.1.290 cloud regression and a 2.1.288 quit regression | TRUE | Live `raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md` fetched 2026-10-06, byte-identical to the saved copy (M, `cmp`); L100-101. 2.1.289 and 2.1.290 sections (L103-325) hold no fix for the quit loss (M, grep 0 hits), so 2.1.288-2.1.290 all carry it |
| 2.1.288 narrows the 30 min background cap to `-p`, SDK, CI, cloud; SIGTERM fix; 2.1.292 `-p` background fix | TRUE | L402, L366, L22 (M) |
| `bin/cc-notify:737` uses `--cloud` | TRUE | `bin/cc-notify:737,739`: `"$CLOUD_CLAUDE" -p "$MSG" --strict-mcp-config --cloud "$CLOUD_ID" --output-format json` (M) |
| `bin/cc-dispatch:3432` uses `--cloud` | **FALSE as cited** | Line 3432 is `local -a up_args=(up --via api --task …)`: it calls `cc-offload up --via api`, i.e. `scripts/cloud-create-api.py`, a Python HTTP client that runs no claude binary (M). The only binary `--cloud` consumer on the pipeline path is cc-notify, reached through `bin/cc-offload:766,838` |
| Send path is "vendor-internal" | **CLOSED** | `--cloud [description\|session_id\|url]` is public in `--help` on 2.1.284 (`help-284.txt:70`) and 2.1.291 (`help-homebrew-291.txt:64`); the live CLI reference documents the send form: "With a session ID … queue a message into that existing session instead, with `-p`" (`https://code.claude.com/docs/en/cli-reference.md` L77, fetched 2026-10-06, M). Create path stays private (open) |
| `strings` check for the two create tokens is feasible | TRUE | `grep -a -o -F` on both executables: `ccr-byoc-2025-07-29` 284=7 / 291=7; `/v1/environment_providers/cloud/create` 284=2 / 291=2; `reuse_outcome_branches` 5 / 5 (M). No drift today |

## 2. Where the proposed change is wrong

1. **"for the cloud lane" is misattributed: the fleet pin gates almost none of the cloud lane.**
   - Create: binary-free. Body is `{title, events, session_context, environment_id}` and headers are Authorization, Content-Type, anthropic-version, x-organization-uuid, anthropic-beta (`scripts/cloud-create-api.py:259-272, 408-433`, M). No client version travels, so the VM cannot run "the caller's version" on our create path (I, from the code). This settles the proposer's riskiest assumption in its favour and, by the same step, voids a pin hold as protection against the 2.1.290 in-VM regression. `c1-hostile-reviewer.md:130` reaches the same reading (I there too). In-VM version has never been measured in the repo (M, grep of cloud research docs: 0 hits).
   - Send: the only pin-governed arm, and only through cc-offload, which passes `CC_CLAUDE_BIN=$CLOUD_CLAUDE` from `cc-claude-bin` = `~/.claude-284/...` (`bin/cc-offload:91-95,766,838`; `cc-claude-bin --explain`, M). A hand-run `cc-notify --cloud` (the form printed at `bin/cc-dispatch:910` and `scripts/handoff-fire.sh:14220`) takes `command -v claude` first (`bin/cc-notify:664-666`), which resolves to `/opt/homebrew/bin/claude` = **2.1.291**, unpinned, symlink dated Oct 6 01:32 (M, `/bin/bash -c 'command -v claude'`, `--version`). That arm is already outside holds.md and was on whatever Homebrew installed before.
   - The valid reason for "never 2.1.288-2.1.290" is fleet-wide (last messages lost on quit, on a fleet that quits and resumes for limit-recover), not cloud-specific.

2. **"floor 2.1.291" cannot be written as the replacement target from a changelog read.**
   - Age: 2.1.291 published 2026-10-06T03:32Z, 2.1.292 at 17:10Z (M, npm registry). `audit.md:95-96`: "A version with <1 week of field exposure is a moving target"; `holds.md:84`: background-daemon window is a BLOCKER "until the LAST fix in the cluster", and 2.1.292 still adds background-session fixes (L24-25).
   - **New landmine the row missed (M):** the 2.1.291 binary carries three Agent-tool description templates, "Each agent you launch has a budget of {N} tokens…", absent from 2.1.284 (`grep -a -o -F 'has a budget of'`: 284=0, 291=6; 'The budget does not count the context the agent starts with': 0 / 2). No changelog line in 2.1.289-2.1.292 mentions it (M, grep "budget" over L1-325: only the WebSearch refill at L262). Upstream issue #99932 (open, filed 2026-10-06, 0 comments; a user report, unverified) says N reads 30,000, is not configurable, and that it is unclear whether it is enforced. Enforcement is unprobed here. For a fleet built on subagent fan-outs this is at least a CAUTION, and it is exactly the changelog-silent shape `holds.md:70-75` warns about.
   - Correct wording: "2.1.289 target RETIRED; nothing below 2.1.291 is eligible (2.1.288-2.1.290 lose the last messages on quit, CHANGELOG 2.1.291); no target named until the band audit, which must probe the per-agent token budget (strings 284=0, 291=6; #99932)".

3. **The send-arm audit check duplicates fail-closed runtime detection.** An unsupported `--cloud` exits 4 with `reason=flag-unsupported` (`bin/cc-notify:748-762`), an unreadable answer is treated as a refusal, exit 8 (`:767-782`), and the first is under test (`tests/cc-notify.bats:1095-1103`). The flag is public and documented (section 1). Cost of late detection: one idle VM and a refused brief (I). If a pre-activation probe is still wanted, its home is a gate file, not audit prose: `skills/cc-upgrade/gate.md:86-92` ("A feature being adopted gets its own probe … add `lib/cc-upgrade-gate/checkNN_<feature>.sh`"), with the table and count that `tests/cc-upgrade-skill.bats` compares. A no-quota form exists: a send to an undeclared id returns `{ok:false,…"Session not found"}` (`bin/cc-notify:683-688`, measured there 2026-08-08; not re-run by me).

4. **The strings canary measures the client, not the server.** Identical counts show the CLI still uses those shapes, not that the server keeps accepting ours (candidates.md section 6 says the same). It is still the only early warning available for the private create (F1) and costs one grep per audit, so it stays.

## 3. What survives (the narrowed adopt)

- holds.md pre-audit note: retire "Target 2.1.289" with the L101 evidence and the budget landmine; do not name 2.1.291 as the target.
- holds.md section 2 (walked by every axis, `audit.md:88`): one cloud row stating (a) cloud-session changelog rows are incident notices, not pin constraints, because neither the create nor the VM reads the pin; (b) the pin-governed arm is `cc-notify:737` via `cc-offload:766`; (c) grep the candidate for `ccr-byoc-2025-07-29` and `/v1/environment_providers/cloud/create`, drift reopens K11.
- Why it is worth doing although it moves no rows: a regression is documented only under the version that fixes it, so an audit that reads 2.1.285 to its stated target 2.1.289 (`audit.md:68`) never sees the 2.1.291 line that condemns 2.1.289 (I).

## 4. Alternatives considered

- **skip** (hygiene only, leave it to the next band audit): ruled out because of the fix-placement blind spot above and because holds.md already takes pre-audit notes without a MANIFEST row (`43cefd9c5`, `216a7aa75`).
- **already-have**: ruled out; no cloud coverage exists in the skill, MANIFEST, or the three 284 axis notes.
- **Make cc-notify resolve the pin before PATH** (`bin/cc-notify:664-672`): the real fix for the unpinned Homebrew send arm; a code change outside this row. Reported, not proposed.

## 5. Not verified

- Which Claude Code version a cloud VM runs (never measured; K03's probe would read it).
- Whether the per-agent token budget in 2.1.291 is enforced, flag-gated, or advisory; whether it first shipped in 2.1.290 or 2.1.291 (the issue says absent from 2.1.289).
- The launchd dispatcher's PATH (the Homebrew resolution was measured in my shell; the pipeline path sets `CC_CLAUDE_BIN` and is unaffected either way).
- The bogus-id send probe (it would call the API; described, not run).
