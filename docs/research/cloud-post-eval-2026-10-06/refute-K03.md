# Refute K03 — cloud-only SessionStart hook that calls the provisioner

Read 2026-10-06 (repo tip `593a21fc3`, worktree `/Users/chrisren/Development/.worktrees/wt-cc-205652-27362`). Read-only: no session fired, no repo file touched, no ledger written.

Labels: **[M]** measured here (command named) · **[D]** documented (file:line or URL) · **[E]** estimated (method named) · **[I]** inferred.

## Verdict

- **refuted: true.** Proposed `trial (55%, effort M)` does not survive.
- **Corrected verdict: skip, conviction 70%.**
- The external feature is real and the row's citations are accurate. What fails is the value claim: each of the three legs addresses a pain that is closed, obsolete, or measured at zero rows, and the provisioner as written does not fit the hook's contract.
- Carve-out, not part of K03's proposed change: the one-line `CLOUD-HOOK-PROBE` in `candidates.md` section 4 (0 extra sessions, S effort) stands on its own. Only K05 actually depends on hook loading; K01 and K09 need only an env var and `command -v gh`, which one brief sentence can read.

## 1. Does the row say what the sources say?

| Claim in the row | Check | Result |
|---|---|---|
| Unshallow is a prose rail at `bin/cc-dispatch:3210` | Read `:3209-3210` | True [M] |
| `scripts/cloud-venue-provision.sh` is 767 lines with zero callers | `wc -l`; `grep -rn cloud-venue-provision` | True [M]. Only non-doc hits: the comment at `bin/cc-dispatch:3156` and its own suite `tests/cloud-venue-provision.bats` |
| Project settings has no `hooks` key | Read `.claude/settings.json:1-57` | True [M]. Keys: `_what`, `_why_*`, `disabledMcpjsonServers`, `permissions` |
| Hook route declined 08-29 on a rule, not a measurement | Read `scripts/cloud-venue-provision.sh:8-12` | True [D] |
| Repo hooks load "in a session with one repository"; `CLAUDE_CODE_REMOTE`; 600 s | `curl https://code.claude.com/docs/en/cloud-environments.md` (HTTP 200, byte-identical to the cached copy: `diff` rc 0) | True [M] at `:272`, `:388`, `:441`, `:475-484`, `:492-496` |
| Release assets of an unattached repo 403 (cited `:242`) | same file | True, but the line is **`:243`**; `:242` is push restrictions |
| `ineligible-deep-history` refused 9 of 220 since 09-22 | `jq 'select(.event=="venue" and .ts>="2026-09-22")' ~/.claude/autonomy/backlog.jsonl`, grouped by `venueWhy` prefix | True [M]: 220 events, 32 cloud, 9 deep-history, 9 distinct ids |
| npm `bats@1.13.0` and PyPI `shellcheck-py 0.11.0.1` exist | registry JSON via `curl` | True [M]; the PyPI release ships a `manylinux_2_17_x86_64` wheel |
| Depth refusal is at `bin/cc-eligible:759` | Read `:754-763` | Imprecise. `:759` is the constant `CLOUD_DEPTH = 50`. The class is declared at `:465`, made blocking at `:592`, minted at `:1267` |

## 2. Is the pain still open? Leg by leg

### Leg A — unshallow (F11)

- The brief rail landed 2026-09-01 (`22b8824c6`, `git log -S` on `bin/cc-dispatch`) [M].
- 146 research docs are dated 09-05 to 10-06. 33 describe a cloud-VM run; 20 of those record `--unshallow` or `--is-shallow-repository` [M: `grep` loop over `docs/research/*2026-09-0[5-9]…10-0*.md`].
- Every VM verdict doc I opened from 09-23 on records the deepen: `lr-transplant-lockless-hop-verdict-2026-09-23.md:14`, `agents-omit-claudemd-autorevert-failed-2026-09-26.md:23`, `truememory-adoption-cloud-verdict-2026-09-28.md:13`, `autonomy-core-install-close-2026-09-28.md:5`, `cc-backlog-add-update-needs-silent-verdict-2026-10-02.md:21`, `limit-recover-zero-memory-close-2026-10-06.md:13` [M].
- Shallow-induced misdiagnoses recorded after 09-03: **0** [M: `grep -i shallow` joined with wrong/misread/re-deriv/horizon over the same 146 docs; the only hit credits the deepen for preventing a re-derivation, `literal-install-coverage-cured-2026-09-09.md:100`].
- Uncertainty: this is survivorship. A session that skipped the rail and died as `conflict` or `superseded` leaves no doc. The 13 VM docs without a mention are ambiguous, not non-compliant. `a3-failure-ledger.md` attributes the 9 of 31 conflict/superseded fires to land latency, sibling refires and a preflight bug, not to the horizon (not re-derived by me).

### Leg B — tools (F12)

- The provisioner's stated purpose is "make a cloud VM's OWN land path able to render a verdict" (`scripts/cloud-venue-provision.sh:2`).
- That path has been forbidden since 2026-09-02: "Do NOT run /ship, do NOT push to trunk, do NOT land anything yourself" (`bin/cc-dispatch:3084`, introduced by `0efcc073d`) [M]. The last VM-side land is 2026-09-04T18:07Z (`docs/research/off-identity-commits-trace-2026-10-02.md:69-70`) [D].
- So F12's symptom ("every VM-side land exits 9", 08-11 to 08-29) was closed by removing VM-side landing, not by provisioning. The provisioner file itself was last changed 2026-08-29 (`git log`: `09e69f026`) [M].
- What remains is ad hoc installs: `npx bats@1` (10-02 doc `:26`), a fresh bats-core clone (09-26 doc `:25`), "bats and rsync were installed" (09-23 doc `:21`). Cost: one or two tool calls per session [E: count of install commands in those three docs].
- Would pre-installed tools cut desk refusals? The 12 newest `~/.claude/autonomy/cloud/*.land-refused` bodies (09-20 to 10-01) fail on: dead-assertion ratchet x4, outer-timeout x3, TSV field-collapse x1, suite cut twice x1, offbox-admission x1, unattended-path selftest x1, no marker x1. In every body that reached it, the statics arm passed. **0 of 12 were caused by a missing or stale bats or shellcheck** [M: `grep` over those 12 files].

### Leg C — drop the depth refusal

- All 9 refused rows are `done`, closed on the desk. Time from venue stamp to `done`: 3 min to 7 h 11 min, median 64 min [M: `jq` per id on `backlog.jsonl`].
- The repo already priced this change on 09-10: full-depth clone unlocks "2 / 0 / 2" rows, agent-drainable yield "0–2", cost "1–2 h (`CLOUD_DEPTH` + an abort interlock)", under the heading "Reach is not the constraint" (`docs/research/cloud-lane-redesign-2026-09-10.md:68-79`) [D]. No hook was required for it then.
- Moving those rows to cloud would trade a lane that closed 9 of 9 within hours for one that lands 58.6–65.5% of declarations at 1.38 fires per item (`a4-economics-and-live-state.md:13`, not re-derived).
- A SessionStart hook cannot serve as the interlock that would justify the drop. SessionStart cannot block, and a non-zero exit "Shows stderr to user only" (`https://code.claude.com/docs/en/hooks.md:875`, fetched today) [M]. The provisioner reports every failure as rc 1 or 3 on stderr (`scripts/cloud-venue-provision.sh:594-595,611-619,766-767`). A failed unshallow would leave the worker shallow with nothing in its context. The prose rail must stay either way.

## 3. Measured constraints the row does not carry

- **Hook budget.** `runner_state()` runs `bats -c tests/*.bats` over the whole corpus (`scripts/cloud-venue-provision.sh:378-383`). The corpus was 556 suites when the provisioner last ran; it is 974 today [M: `ls tests/*.bats | wc -l`]. One gather with real bats 1.13.0 took **161 s** and returned 18,977 tests, rc 0 [M: `/opt/homebrew/bin/bats -c tests/*.bats` on the desk, load average 22–36, so an upper-ish figure for this box; the VM is unmeasured]. The provisioner calls it at least twice per run (census `:563`, assertion `:732`) and four times when it installs (`:682`, `:712`). That is 5+ minutes [E: 2 x 161 s] against a 600 s cancel, on every start **and resume** (cloud doc `:496`), including the docs-only rows that need neither tool.
- **Supply.** 4,241 ids in the ledger: 4,121 done, 119 blocked, **1** open or claimed [M: `awk` fold of `add/done/reopen/block/unblock`; approximate, it ignores other events]. `a4` reports 1.9 fires/day and 0 dispatchable cloud-eligible rows. Cloud and local draw on one quota pool (`a4:11`). A hook that changes about two sessions a day cannot move landed rows per unit of quota.
- **Release download.** `:637` fetches a release asset from `koalaman/shellcheck`, which the doc says now 403s (`cloud-environments.md:243`). The row names this. Not measured in a VM since 09-04. The bats-core `git clone` at `:686` did work in a VM on 09-26.
- **Riskiest assumption, still unmeasured.** No tracked code reads `CLAUDE_CODE_REMOTE` (`grep -rn`: hits only under `docs/`) [M]. Indirect support only: a VM's `pwd` is the clone itself (`docs/research/cloud-vm-roundtrip-2026-08-10.md:12-13`), which matches the doc's single-repository condition, and VMs ran the project `/ship` command.

## 4. Adversarial pass on this refutation

- "20 docs recording the deepen is survivorship." Accepted; stated in Leg A. It lowers my conviction, it does not restore the row: no source ties a post-09-03 loss to the horizon.
- "A five-line unshallow-only hook is cheap insurance against prose drift." True, and it is a different proposal: S effort, no provisioner, no download rewrite, no refusal drop. It still rests on the unmeasured loading assumption and still fails silently.
- "Volume may return." Then Leg A's determinism gains value. `a4` flags the same caveat for yield. Revisit with the probe result in hand.
- "The VM gather may be far faster than the desk's." Possible; unmeasured. The probe can time it.
- "K01, K05 and K09 hang on this hook." Only K05 does. K01 keys on the env var or on absent identity hooks; K09 keys on `command -v gh`.

## 5. Alternatives considered

- **One brief sentence telling the worker to run the provisioner.** Ruled out: its tools arm serves a land path the brief forbids, and the gather cost applies there too.
- **Environment setup script (K14).** Runs as root before launch and is cached about 7 days (cloud doc `:396-423`), which would absorb the install cost. Ruled out here for the reason the row gives: per-account web state on four accounts, and it cannot unshallow a per-session clone [I].
- **Narrowed trial: probe line only.** Kept as the carve-out above; it is the section 4 experiment, not K03's change.

## 6. Corrections to the candidate row

1. `doc-cloud-environments.md:242` should be `:243` for the release-asset 403.
2. `bin/cc-eligible:759` is the `CLOUD_DEPTH` constant; the refusal is minted at `:1267` (class `:465`, blocking tuple `:592`).
3. "F12 missing tools" is dated 08-11 to 08-29 and concerns VM-side landing, forbidden since `0efcc073d` (09-02).
4. "9 of 220 refused" omits that 9 of 9 were closed locally, median 64 min after the stamp.
5. The row omits the gather cost: 974 suites, 161 s per `bats -c` on the desk, at least two per provisioner run.
6. Section 4's "K01, K05 and K09 hang on the same unverified fact" overstates: only K05 needs hook loading.

Scratch files from this pass: `/tmp/cloud-blog-eval/scratch/k03-*`.
