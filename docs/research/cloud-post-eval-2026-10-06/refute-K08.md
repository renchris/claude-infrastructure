# Refutation pass — K08 (version glob before 2.1.300; "hidden flag" comments)

Date of every measurement below: 2026-10-06. Repo state: `HEAD == main == origin/main == 593a21fc3` (measured: `git rev-parse --short`).

**Result: verdict SURVIVES (adopt), conviction 85%. One half of the row is mis-described (the comments), and the change has zero effect on landed rows per unit of quota.**

## 1 · What I tried to break, and what happened

| Attack | Result | Evidence (all measured unless marked) |
|---|---|---|
| The glob is not what the row says | Failed. `bin/cc-offload:301` reads `2.1.2[2-9]*\|2.[2-9]*\|[3-9].*` | Read of `bin/cc-offload:297-310` |
| 2.1.300 does not actually FAIL | Failed. Replaying the `case` arm in bash: `2.1.299` PASS, `2.1.300` FAIL, `2.1.1000` FAIL, `10.0.0` FAIL | bash loop over 15 version strings against the literal pattern |
| Already fixed on trunk | Failed. One commit ever touched the pattern (`237ecf243`, the introducing one); `main` and `origin/main` equal `HEAD` | `git log --oneline -S'2.1.2[2-9]' -- bin/cc-offload` |
| The deployed copy differs from the worktree | Failed. `~/.claude/bin/cc-offload` is a symlink into the main checkout and is byte-identical; same line 301 | `cmp -s`, `grep -n` |
| A test already pins the high side | Failed. `tests/cc-offload.bats:283-290` fixtures `2.1.114` (FAIL); `:296-297` fixtures `2.1.220` (PASS). Nothing at or above 2.1.300 | Read of the bats file |
| Flags are not public in 2.1.284 | Failed. Launcher pin resolves to `~/.claude-284/node_modules/.bin/claude`, `--version` = `2.1.284 (Claude Code)`, `--help` lines 70 / 89 / 251 = `--cloud`, `--environment`, `--teleport` | `bin/cc-claude-bin --explain`; `--help \| grep -n` |
| 2.1.292 / near-daily is wrong | Failed. npm `latest` = `next` = 2.1.292, published 2026-10-06T17:10:31Z; `stable` = 2.1.285. 21 releases from 2.1.270 (09-12T18:52Z) to 2.1.292 = 0.88/day | `curl registry.npmjs.org/@anthropic-ai/claude-code`, `time` map |
| The defect reaches fires (the proposer's riskiest assumption) | Failed. It is setup-only (section 2) | grep + reads below |
| The version line will jump to 2.2.0 first | Cannot determine. 2.1.0 shipped 2026-01-07; 292 patch numbers and no minor bump in 9 months. The glob already passes 2.2+, so the fix costs nothing either way | npm `time` map; reasoning |
| The comments are stale | **Partly succeeded** (section 3) | `--help` on four installed binaries |

## 2 · Blast radius: setup grading only (the riskiest assumption holds)

- Exactly one `--version` read exists across `bin/cc-offload`, `bin/cc-cloud`, `bin/cc-notify`, `scripts/lib/cloud-create.sh`, `scripts/handoff-fire.sh`: `bin/cc-offload:299` (measured: grep for `--version`).
- `cmd_setup` has one caller, the `setup)` verb at `bin/cc-offload:996`. No script, no launchd plist, no dispatcher code calls `cc-offload setup` (measured: grep over `bin/`, `scripts/`, `tests/`, `docs/`, `~/Library/LaunchAgents`; hits are the bats test and one prose line, `docs/plans/CLOUD_OBSERVABILITY.md:1669`).
- The 24/7 pipeline fires `cc-offload up --via api ...` (`bin/cc-dispatch:3432`); the default lane is `api` (`bin/cc-offload:524`). `up` never consults the version.
- The send arm decides flag support from the real call's own refusal text, not from a version (`bin/cc-notify:743-752`: `*"nknown option"*"--cloud"*` and siblings). No version dependence there.
- Naming nit: R1 is labelled "create binary", but under the default API lane the binary does not create a session; it only carries the headless send (`bin/cc-offload:766`, `:838`).

Consequence at 2.1.300+: `cc-offload setup` prints `✗ create binary  2.1.3xx has no --cloud verb`, `✗ NOT READY`, exits 3 (`bin/cc-offload:384-386`), and prescribes `export CC_CLOUD_CREATE_BIN=<a 2.1.220+ claude>` (`:305`). Fires continue. The harm is a false verdict from the one readiness grader plus a remediation that points at an older binary; the header of the same file records that exact drift as a past incident ("kept firing 2.1.220 after the launcher moved to 2.1.260", `bin/cc-offload:87-89`, cc-backlog `e8b753cac339`).

**Landed rows per unit of quota: no change.** This is mechanism hygiene. It answers the user's question ("is the blog/update helpful to the pipeline?") only as a side-finding; it should be ranked below any candidate that moves yield.

## 3 · The comments half of the row is mis-described

The row says the comments "still call the flag hidden" and proposes updating "the two comments".

- `bin/cc-cloud:76-80` says `--cloud` is "present and HIDDEN on 2.1.215/219/220", dated 2026-08-07. That is version-scoped, and still true: `--help | grep -c -- '--cloud '` returns **0 on 2.1.219 and 2.1.220**, **1 on 2.1.260, 2.1.280, 2.1.284** (and on Homebrew 2.1.291, help line 64). Measured on `~/.claude-{219,220,260,280,284}` and `/opt/homebrew/bin/claude`.
- `bin/cc-offload:303` ("do NOT infer support from --help, it is blind to hidden flags") is the action text of the UNKNOWN arm. It is still correct advice for any binary in the 2.1.220 to pre-2.1.260 range, and two such rollback dirs are on disk (`~/.claude-219`, `~/.claude-220`).
- There are six such sites, not two: `bin/cc-cloud:76-80`, `bin/cc-offload:303`, `bin/cc-notify:133-134`, `:743-744`, `:755` (a runtime stderr string), `scripts/cloud-ceiling-probe.sh:94`.

Correct edit: additive, not a rewrite. Append "public in `--help` on 2.1.260 / 280 / 284 / 291 (measured 2026-10-06); hidden on 2.1.219 / 220". Rewriting them to "no longer hidden" would make a true, version-scoped statement false. The first public version lies between 2.1.221 and 2.1.260 and was not pinned down; the saved changelog (`/tmp/cloud-blog-eval/CHANGELOG.md`) has no `--cloud` entry (grep: hits only for `--teleport` and `--environment`).

## 4 · Extra facts the row lacks

- The glob also **false-PASSes 2.1.22 through 2.1.29** (January 2026 builds with no cloud verb) and false-FAILs any major version of two digits. A numeric compare closes all three holes.
- When it bites (estimate, linear extrapolation of 0.88 releases/day; 8 more releases): 2.1.300 publishes about 2026-10-15. The launcher pin moves by hand in jumps; version-dir birth dates are 219 on 07-24, 220 on 08-01, 260 on 09-03, 280 on 09-22, 284 on 09-28 (measured: `stat -f %SB`). The first pin move after about 10-15 flips `setup` to NOT READY.
- Precedent for the fix shape exists: `sort -V` compare at `scripts/limit-recover/lr-upgrade.sh:191`; `sort -V` orders `2.1.29 < 2.1.220 < 2.1.300 < 2.1.1000 < 10.0.0` correctly on this box (measured).
- The fix must strip the ` (Claude Code)` suffix that `--version` prints, keep the empty-string UNKNOWN arm, and add bats fixtures for 2.1.300, 2.1.1000 and 2.1.29.

## 5 · Alternatives considered

| Alternative | Ruled out because |
|---|---|
| Capability probe via `--help \| grep -- --cloud` | Returns 0 on 2.1.219 / 220, which do have the verb (measured). This is why the code bans the inference |
| `strings \| grep` probe, as `trailer_supported` does (`bin/cc-cloud:713-719`) | Works, but heavier, and that function is marked "not yet wired" (`:712`). Version compare is sufficient for a grader |
| Extend the glob (`2.1.[3-9][0-9][0-9]*` etc.) | Same class of defect, breaks again at four digits or a new major |
| Delete R1's version check and rely on cc-notify's behavioural refusal | Loses the pre-fire diagnostic; the behavioural check only runs after a session exists |
| Skip: no fire depends on it | Rejected. Effort is one case arm plus three fixtures, and a false FAIL with a backwards remediation in the sole readiness grader is cheap to prevent before about 10-15 |

## 6 · Uncertainties

- Whether Anthropic bumps to 2.2.0 before 2.1.300: unknown, and harmless to the fix.
- Backlog search for an existing row used four literal patterns over `~/.claude/autonomy/backlog.jsonl` (26,978 lines) and found none; a differently worded row could exist.
- First version where `--cloud` became public: bracketed to (2.1.220, 2.1.260], not measured more finely.

## 7 · Corrected verdict

**adopt, 85%, effort S.** Scope it as: numeric compare at `bin/cc-offload:301` (floor 2.1.220), three new bats fixtures, and an additive dated note at the hidden-flag sites. Label it hygiene with zero yield effect.
