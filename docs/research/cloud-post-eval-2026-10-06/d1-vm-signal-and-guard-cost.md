# D1 lens: is there a reliable "I am inside a cloud VM" signal for a ship-land guard, and what does the guard break

Checked 2026-10-06 at repo tip `03b7e413c` (worktree `wt-cc-205652-27362`), local refs only (last fetch 2026-10-06 22:59 local, `FETCH_HEAD` mtime). Nothing was run that mutates the repo, GitHub or a cloud account. No suite was executed.

Labels: **M** = measured here (command named), **D** = documented by a source, **I** = inferred.

Address labels (no addresses printed): `SANCTIONED` = the desk's `git config user.email`; `ACCT-next2/3/4`, `ACCT-next(hotmail)` = four other operator addresses, each seen under exactly one firing account.

## Headline

- The env arm (`CLAUDE_CODE_REMOTE=true`) is documented and has zero desk false positives, but **no artifact from one of our VMs has ever recorded it**. It stays unmeasured.
- The identity arm (`noreply@anthropic.com`) is **not** a reliable VM signal: 49 of 341 surviving VM branches (14.4%) carry no `noreply` committer at all, and 27 of them commit as the desk's own sanctioned address.
- New: main carries **104** VM-made commits (UTC committer stamps), not 93. **11 are under the sanctioned identity**, so they are outside the "93 off-identity" count and invisible to the identity pager.
- Zero recurrence still holds on a signal that does not depend on identity: 0 of 2,863 commits on main since 2026-09-05T00:00Z carry a `+0000` committer stamp.
- Guard cost at the desk and in CI: 0 tests trip either arm. Cost inside a VM: about 219 tests in 21 suites (static estimate) hit the env arm unless a scrub or a scoping rule is added.
- Placement: `scripts/ship-land.sh:5538`, beside `land_outer_timeout_preflight`, exit 2.

## 1. The env signal: evidence that `CLAUDE_CODE_REMOTE` is set in OUR VMs

| Source searched | Result | Label |
|---|---|---|
| Commit messages, all refs, VM-marked (committer `noreply` or a `claude.ai/code/session_` trailer): 1,549 of 27,912 commits | 0 mention `CLAUDE_CODE_REMOTE`; 0 `printenv`/env dump; 0 `CLAUDECODE`; 0 `IS_SANDBOX` | M: `git log --all --format=%B` + Python regex |
| Pickaxe `git log --all -S'CLAUDE_CODE_REMOTE'` | 63 commits, every one desk identity and desk timezone (`-0500`/`-0700`); 0 VM-authored | M |
| Added lines of all 548 unlanded VM commits (`origin/claude/*` not on main) | 0 lines with `CLAUDE_CODE_*=`, `CLAUDECODE=`, `printenv`; 1 unrelated hit (`CLAUDE_CODE_RESUME_THRESHOLD_MINUTES`) | M: `git show --unified=0` per commit |
| `~/.claude/autonomy/cloud` (3,413 files: 757 `.decl`, 727 `.sends`, 98 `.land-refused`, ...) | 0 files; the directory holds desk-side bookkeeping only, no VM transcript | M: `grep -rl` |
| `~/.claude/logs/cloud-return-lane.log` (5.2 MB) | 0 hits | M: `grep -c` |
| Locally pulled VM transcripts (`~/.claude*/projects/-home-user*`, `-root*`) | 0 directories | M: `ls` |
| Tracked code reading the variable | 0 files outside `docs/research/` (14 files mention it, all research notes) | M: `git grep -c` |

- **No VM of ours ever printed its environment.** Direct evidence: none. (M)
- What the docs say, re-fetched 2026-10-06 (HTTP 200):
  - `https://code.claude.com/docs/en/env-vars.md` line 360: "Set automatically to `true` when Claude Code is running as a cloud session. Read this from a hook or setup script". (D)
  - `https://code.claude.com/docs/en/cloud-environments.md` line 484: "the session VM's environment carries that variable as `true`, it's never `true` locally". (D)
  - same page line 242: the proxy "doesn't limit which branches a push can update". (D)
- What the 2.1.284 binary says (`/tmp/cloud-blog-eval/strings-284.txt`, 196 matching lines):
  - The variable is in the launch-environment-wins set, so a repo `settings.json` `env` block cannot unset it. (M)
  - 0 `delete …CLAUDE_CODE_REMOTE` sites: the CLI does not strip it from its own environment, so a Bash-tool child inherits it. (M for the count, I for inheritance)
  - One site spawns a child with `CLAUDE_CODE_REMOTE:"true"` next to `CLAUDE_CODE_REMOTE_ENVIRONMENT_TYPE:"self_hosted"`: a self-hosted runner on the operator's box would trip the env arm. (M)
- **K01's indirect evidence does not hold.** It cited the `Claude-Session:` trailer on 61 of the 93 as a sign of the sibling `CLAUDE_CODE_REMOTE_SESSION_ID`. The same trailer is on 317 main commits made before 2026-08-10 with a `-0700` committer stamp, on a desk where no `CLAUDE_CODE_REMOTE*` key exists (`git log origin/main --until=2026-08-10 --grep=claude.ai/code/session_`). The trailer is harness-supplied, not a shell read of an env var. (M, I)
- Desk false positives for the env arm: 0.
  - This session: variable unset, `CLAUDE_CODE_ENTRYPOINT=cli`, Darwin, uid 501. (M)
  - Live processes: 0 of 49 env-readable processes (21 `node`, 28 `bash`; 20 of them CLI sessions) carry any `CLAUDE_CODE_REMOTE*` key (`ps eww`, key names only). (M)
  - launchd landers (`scripts/cloud-return-lane.sh`, `scripts/postland-verify.sh:3299`) inherit no session env. (I)
- Our create path asserts `environment_kind == "anthropic_cloud"` (`scripts/cloud-create-api.py:68-74,108`), the product's own cloud kind. (D, from the script)

## 2. The identity signal

### 2a. Unlanded VM commits (`origin/claude/*`, not on main): 341 heads, 548 commits

Command: `git log --format='%ae|%ce|%an|%cn' --remotes='origin/claude/*' --not origin/main`. Every one of the 548 has a `+0000` committer stamp; the desk stamps `-0500` or `-0700`. (M)

| Committer email | Commits | Names used |
|---|---|---|
| `noreply@anthropic.com` | 459 (83.8%) | Claude (4 of them authored under an operator address) |
| `SANCTIONED` (the desk's own address) | 41 | Chris Ren 27, Claude 9, renchris 5 |
| `ACCT-next3` | 30 | Claude 27, Claude (cloud) 3 |
| `ACCT-next2` | 11 | Claude 10, Chris Ren 1 |
| `ACCT-next4` | 6 | Claude 5, Chris Ren 1 |
| `ACCT-next(hotmail)` | 1 | Claude |

- 27 unlanded VM commits are **byte-identical in name and email to a desk commit** (`Chris Ren <SANCTIONED>`). (M)
- None of the 89 non-`noreply` commits carries an `Original-commit:` or `Cloud-session:` trailer, so none is a desk re-author (`scripts/cloud-reconcile.sh:89`). 55 carry `Co-Authored-By`, which the desk's `commit-msg` hook blocks (`scripts/cloud-reconcile.sh:90`). (M)

Per session (branch):

| Slice | Branches | `noreply` only | no `noreply` committer | mixed |
|---|---|---|---|---|
| All surviving heads | 341 | 292 | 48 (14.1%) | 1 |
| Fired before 2026-09-05 | 325 | 281 | 43 | 1 |
| Fired 2026-09-05 or later | 16 | 11 | 5 (31%) | 0 |

- Latest instances: `claude/fire-20260920T160244Z-44379-1` (3 commits as `Chris Ren <SANCTIONED>`), `claude/fire-20260921T082747Z-37696-1` (4 commits as `Claude <ACCT-next4>`). (M)
- Firing account against identity (`~/.claude/autonomy/cloud/*.decl`, `account=`): `ACCT-next2` appears only under account next2 (6 branches), `ACCT-next3` only under next3 (12), `ACCT-next4` only under next4 (3), the hotmail alias only under next (1). `SANCTIONED` appears under all four (5, 7, 11, 4). (M)
  - Reading: three addresses are the firing account's own login; the sanctioned address is self-configured by the VM from repo history. (I)
- Survivorship caveat: pruned branches are not in this sample (`~/.claude/autonomy/cloud/branch-prune-deleted.tsv`). (M that the file exists; effect on the rate is unknown)

### 2b. VM-made commits that reached main

Command: `git log origin/main --format=…%cd --date=format:%z`; 6,977 commits.

| Committer on a `+0000`-stamped main commit | Commits | In the trace doc's "93"? |
|---|---|---|
| `noreply@anthropic.com` | 89 | yes (88 + 1 hotmail-authored) |
| `ACCT-next(hotmail)` | 4 | yes |
| `SANCTIONED` (6 as Chris Ren, 5 as Claude) | **11** | **no** |
| Total | **104** | 93 |

- All 104 fall between 2026-08-24T18:26Z and 2026-09-04T18:07Z. (M)
- 5 of the 11 sanctioned-identity commits (`56e60e4b9`, `df84e8837`, `cadd8e65d`, `7557fc1c5`, `aa80db372`) were first seen on this Mac by `fetch origin main: fast-forward` 2 to 10 minutes after their UTC committer stamp (shared checkout's `logs/refs/remotes/origin/main`). They were not pushed from this Mac. (M) They are VM self-lands under the desk's identity. (I)
- The other 6 (`06038c606` … `92608b867`, 2026-08-24) predate the reflog's first entry (2026-08-25T04:48:54Z) and cannot be attributed by reflog. (M)
- By arrival event: 52 reflog fetch entries carried 94 of the 104. 47 were all-`noreply`, 1 mixed, **4 had no `noreply` committer** (6 commits). (M)

### 2c. A guard keyed on `noreply@anthropic.com`

| Measure | False negatives | False positives |
|---|---|---|
| Historic VM-made commits on main | 15 of 104 (14.4%) | n/a |
| Historic arrival events on main | 4 of 52 (7.7%) | n/a |
| Surviving VM sessions | 48 of 341 (14.1%); 5 of 16 fired since 2026-09-05 | n/a |
| Desk commits on main since 2026-09-05T00:00Z | n/a | 0 of 2,863 (one author/committer pair, `SANCTIONED`) |
| Desk land of a VM branch | n/a | 0 if the arm reads the effective committer (`git var GIT_COMMITTER_IDENT`); the desk re-authors before landing (`scripts/cloud-reconcile.sh:78-89`) |
| Test fixtures | n/a | 0; see section 3 |

- The address is never shared with a legitimate desk or CI commit: every `noreply`-committed commit on main (89) has a `+0000` stamp and falls in the VM window. (M)
- The reverse fails: the desk's sanctioned address **is** shared with VMs (41 unlanded commits, 11 on main). (M)

### 2d. Consequence for "detected within 5 minutes"

- `identity_landed_sweep` compares `%ae` and `%ce` to the sanctioned address and nothing else (`scripts/postland-verify.sh:4054`, test at `:4071-4072`). (M)
- A VM that self-lands under the sanctioned identity is not paged. That happened for 11 of 104 historic VM-made commits on main (10.6%). (M, I)
- The "0 of 2,817 off-identity" figure therefore does not by itself show zero self-lands. The UTC-stamp count does: 0 of 2,863 since 2026-09-05T00:00Z (2,783 at `-0500`, 80 at `-0700`). (M)
- The two post-2026-09-05 main commits with a session trailer and sanctioned identity (`e3a7ace41`, `9fe923385`) have `-05:00` committer stamps and arrived by `update by push` from this Mac at 2026-09-20T21:42:47Z: a desk land, not a VM land. (M)

## 3. What the guard costs in the test corpus and CI

| Fact | Value | Label |
|---|---|---|
| `tests/*.bats` suites | 974 | M: `ls` |
| Suites referencing `ship-land.sh` | 72 (2,448 tests) | M: `git grep -l`, `grep -c '^@test'` |
| Suites whose tests execute the script in land mode (no `--precheck`, no `--dry-run`) | 21 suites, about 219 tests; 190 of them in five suites: `ship-land.bats` 134, `land-gate-cas.bats` 21, `gate-home-isolation.bats` 18, `land-gate-memo.bats` 10, `gate-selftest-memo.bats` 7 | Estimated: static regex over `@test` blocks, not a run |
| Tests that are precheck-only / dry-run-only | about 16 / about 15 | Estimated, same method |
| Tracked tests, scripts, hooks, workflows that set or read `CLAUDE_CODE_REMOTE` | 0 | M: `git grep -c` |
| Test files containing `noreply@anthropic.com` | 2: `tests/cloud-reconcile.bats` (7 lines), `tests/postland-verify-identity.bats` (3) | M |
| Of those, suites that run the real land path | 0; `tests/cloud-reconcile.bats:28` states it does not run the real `ship-land` | D (suite header) |
| Fixture identity in the land suites | repo-local `git config user.email tester@example.com` (`tests/ship-land.bats:15`, `tests/land-gate-cas.bats:42`, `tests/gate-home-isolation.bats:38`, `tests/ship-land-outer-timeout.bats:20`, `tests/gate-precheck.bats:38`) | M |
| CI | `.github/workflows/hermetic.yml:114,133`: `ubuntu-latest` and `macos-latest`; no `git config` identity line in the workflow | M |
| `tests/ship-land.bats` in CI | excluded from the hourly partition (`scripts/offbox-excluded.manifest:280`); the other four core land suites are in it | M |

Where each arm trips:

| Runner | Env arm | Identity arm (effective committer) |
|---|---|---|
| Desk (`bats`, `cc-bats`, the land gate) | 0 tests (variable unset, section 1) | 0 tests (fixtures set a local identity) |
| GitHub Actions | 0 tests (not a cloud session) (I) | 0 tests |
| Inside a cloud VM | every land-mode test: about 219 in 21 suites (estimated) | 0 tests if the fixture's local `user.email` wins; unverified for a VM that exports `GIT_COMMITTER_EMAIL` |

- `bin/cc-bats:385-403` already unsets three ambient session marks (`CLAUDE_CODE_SESSION_KIND`, `CLAUDE_JOB_DIR`, `KITTY_PID`) and not this one. One more `unset` there covers runs that go through `cc-bats`. (M)
- Whether a VM's `bats` resolves to `cc-bats` is unverified. A VM-recorded note says it installed tools with `apt-get` (16 VM commit messages mention `apt-get`). (M for the count)
- **Measured base rate for this exact kind of change.** `ba8e5c24a` (2026-09-28) added a context-keyed preflight refusal at the same line, exit 2:
  - It touched 7 files: 4 existing suites, 1 new 114-line suite, `postland-verify.sh`, `ship-land.sh`. (M: `git show --stat`)
  - It broke the desk's cloud return lane for two days: "every automated cloud land exited 2 `reason=outer-timeout` before it began (3 of 3 `.land-refused` artifacts since …)" (`scripts/cloud-return-lane.sh:189-195`; fix `3650c703b`, 2026-09-30). `~/.claude/logs/cloud-return-lane.log` holds 3 such refusals. (D, M)
  - One prior refusal of this shape, one legitimate lander broken.
- A venue guard reaches VMs as soon as it lands: a VM clones trunk at fire time, and "sessions run their OWN worktree copy of ship-land.sh" (`.claude/rules/agent-operating-lessons-situational.md:105`). (D, I)

## 4. Where the refusal goes, and its exit code

| Item | Location | Why |
|---|---|---|
| Refusal | `scripts/ship-land.sh:5538`, as a sibling call on the same condition as `[[ "$DRY_RUN" = "1" ]] \|\| land_outer_timeout_preflight` | `--precheck` has already been dispatched at `:5536` and `main_precheck` always exits (`:5401-5505`); `--dry-run` skips the line |
| Function body | beside `land_outer_timeout_preflight` at `:1457-1467` | same shape: `verdict=refused reason=…`, context-keyed, before the lock |
| Must stay above | `inflight_claim` at `:5592` | refusals above it "file nothing" (`:5588-5591`); `land_failure_inbox` returns unless `INFLIGHT_FILE` is set (`:950`) |
| Optional second site | `main_locked`, after `:5170`, guarded on `DRY_RUN != 1` | the push is at `:5248` (re-push further down) and `ship-land.sh __locked …` bypasses `main_outer` (`:5703-5707`); an env test adds no fork inside the mutex |
| Exit code | **2** | header `:127`: "2 preflight refusal"; the sibling uses 2 (`:1464`) |

- Exit 2 is outside `permission-gate-lint`'s ratchet (`scripts/permission-gate-lint.sh:50`, `:263-266`), so the per-file count for `ship-land.sh` does not move. (M)
- Exit 4 is the wrong family: the lint would count an announced `exit 4` as a new permission gate needing a `gate_bounded:` budget (`ship-land.sh` already carries 25 such markers), and `.claude/commands/ship.md:125` tells the reader exit 4 means "re-run from a dedicated worktree". (M, I)
- A new code would need the header at `:127-135` and `ship.md` updated; no consumer in `desk-land.sh`, `cloud-return.sh`, `cloud-reconcile.sh`, `cc-reaper` or `postland-verify.sh` branches on 2 or 4. (M: `git grep`, 0 hits)
- An exit 2 here writes one `land.log` row through `_land_exit_trap` (`:1536-1538`); inside a VM that row is VM-local. (M for the trap, I for the VM)
- Existing test pattern to copy: `tests/ship-land-outer-timeout.bats:52,74,81,86` (refused with rc 2; override; `--dry-run` not refused; negative control). (M)

## 5. What moves the choice

| Finding | Effect on A (guard) | Effect on B (guard + ruleset) | Effect on C (leave) |
|---|---|---|---|
| Env var unrecorded in any of our VMs | A's primary arm is still an assumption | B does not depend on it | none |
| Identity arm misses 14% of VM sessions, 7.7% of historic arrival events | A's fallback arm is weaker than K01 assumed ("the address on all 88") | raises B: the only closure with no VM-side signal | none |
| 11 VM-made commits on main under the sanctioned identity | a `noreply` arm would not have stopped them | same | weakens C: the pager cannot see this class |
| 0 UTC-stamped commits on main since 2026-09-05 | A recovers no throughput | same | supports C on recurrence only |
| 0 desk/CI trips; placement and exit code have a direct precedent | A is cheap at the desk | n/a | n/a |
| The precedent refusal broke the return lane for 2 days | A needs a negative control for every desk lander | n/a | n/a |
| Self-hosted child carries `CLAUDE_CODE_REMOTE=true` | A's env arm refuses a desk-hosted runner | n/a | n/a |

## 6. Alternatives considered

| Alternative signal or design | Evidence | Verdict |
|---|---|---|
| Linux and uid 0 | VM commits record "Linux running as root" (`00c4f91c3`, 2026-09-20), "cloud VMs that run as root" (`efbbea43e`, 2026-09-21; `d4f404d9a`, 2026-08-29), `$HOME=/root` with the checkout under `/home/user` (`bac2c454e`, 2026-09-02). Desk is Darwin uid 501 (M). The CI runner is uid 1001 per `efbbea43e`. | The only VM fingerprint the VMs themselves recorded. Not a product contract; a root container runner would trip it. Usable as a second arm in place of the email. (I) |
| Committer timezone `+0000` | 548 of 548 unlanded VM commits, 104 of 104 VM-made main commits, 0 of 2,863 desk commits since 2026-09-05 | Not usable in a pre-push guard (ship-land restamps on rebase). Usable in the post-land pager as a second predicate. (M, I) |
| Range-keyed email (`git log BASE..HEAD --format=%ce`) instead of effective committer | same 14% miss; also fires at the desk on an un-re-authored VM range, where today the refusal arrives as exit 7 (`scripts/cloud-reconcile.sh:79-84`) | No better as a VM signal. (I) |
| Scope the env arm to a non-local `origin` URL so fixtures never trip | fixture remotes are local bare repos (16 of the 72 suites create one); the VM's `origin` URL form was not read | Removes the need for an override a VM could also set. Unverified. (I) |
| Override variable in the style of `SHIP_ALLOW_OUTER_TIMEOUT=1` | 6 suites and 2 desk lanes already carry that one | A VM can set it too; it converts the guard into a second prose rail. (I) |
| Hooks-absent arm from the original K01 row | fixtures from `git init` have no hooks | Not re-measured here; K01 section 4.2 already dropped it. |

## 7. Not verified, and the cheapest way to close each

- **The variable inside one of our VMs.** Free probe, described and not run: one brief sentence asking the next organic fire to write `${CLAUDE_CODE_REMOTE-unset}`, `id -u`, `uname -s` and `git var GIT_COMMITTER_IDENT` into its boot commit body. 75 `.decl` files are dated since 2026-09-05, so supply exists when the queue is non-empty.
- **How a VM gets a non-`noreply` identity** (account email versus self-configured). The account correlation is measured; the mechanism is not.
- **The land-mode test count.** 219 is a static estimate; a traced run of the 21 suites would measure it.
- **Whether fixture-local `user.email` wins inside a VM.** Depends on whether the VM identity lives in global config or in exported `GIT_*` variables. One VM commit (`fc93cf718`, 2026-08-25) describes an ambient `~/.gitconfig`, which suggests global config.
- **Reflog attribution for 10 of the 104** (predate the reflog's first entry).
- **Freshness beyond the local refs.** No fetch was run.

## 8. Re-checks of the prior investigation's claims

| Claim (source) | Result |
|---|---|
| `CLAUDE_CODE_REMOTE` is `true` in the session VM, never locally (`refute-K01.md` row 7) | Confirmed live; also at `env-vars.md` line 360 |
| Proxy does not limit branches (`refute-K01.md` row 6) | Confirmed live, line 242 |
| No ruleset, no branch protection | Confirmed today: `gh api repos/renchris/claude-infrastructure-private/rulesets` returns `[]`; `…/branches/main/protection` returns 404; repo is private, owner type User |
| "refuse when the effective committer is `noreply@anthropic.com`, the address on all 88 measured VM commits" (`refute-K01.md` 4.2) | Incomplete: 88 is the off-identity subset. 104 VM-made commits are on main and 15 do not carry that committer |
| Session trailer as indirect evidence of the env var (`refute-K01.md` section 5) | Does not hold; 317 desk commits carry the same trailer |
| 59 of 72 suites "mention a bare remote" (`refute-K01.md` 4.2) | 16 of 72 match `--bare`; the hooks arm that number supported is already dropped |
| "0 of 2,817" since 2026-09-05 | 2,863 with an explicit `--since=2026-09-05T00:00:00Z`; a bare date makes git use the current time of day. Still 0 off-identity |
| `bin/cc-bats:385-403` does not unset the variable | Confirmed |
| Self-hosted child gets `CLAUDE_CODE_REMOTE:"true"` | Confirmed in the 2.1.284 strings |

Scratch files from this pass (helper lists and two fetched doc pages) are under `/tmp/decisions-eval/` with a `.d1-` prefix.
