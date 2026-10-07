# Refute K01 — Mechanical "a VM never lands" guard

Checked 2026-10-06 against repo tip `593a21fc3` (HEAD = local `origin/main`, 0 behind; no fetch run, git is read-only here).

## Verdict

- **Proposed:** adopt, 70%, effort S.
- **Outcome:** NOT refuted. Corrected verdict **adopt, 62%**, with a narrower change than the row specifies.
- **Why it survives:** every cited fact checks out, the route is still open, and repo config that travels to the VM actively tells it to `/ship`.
- **Why conviction drops:** it moves no landed rows per unit of quota, one arm of the proposed change is not effort S, the title overclaims, and the env var is still unread in one of our VMs.

## 1. Cited facts, checked at the primary source

| Row claim | Result | Evidence |
|---|---|---|
| Brief sentence "Do NOT run /ship, do NOT push to trunk" at `bin/cc-dispatch:3084` | True today | `bin/cc-dispatch:3083-3084`, inside `if [ "$venue" = cloud ]` |
| `ship-land.sh` has no venue check | True today | measured: `grep -c CLAUDE_CODE_REMOTE scripts/ship-land.sh` = 0 |
| `ship-land.sh` has no identity check | True today | measured: `grep -n '%ae\|%ce\|WANT_EMAIL\|git_identity\|noreply' scripts/ship-land.sh` = 0 hits; the only "identity" arm is the fixture-escape lint at `:3695-3738` |
| Runbook says the VM "can push its own working branch and nothing else" | True, and stale | `docs/runbooks/cloud-fleet.md:27-28`; file last touched 2026-08-08 (`git log`) |
| "Stopped by instruction, not closed mechanically" | True as of the newest dated doc | `docs/research/off-identity-commits-trace-2026-10-02.md:62-74`, "Still open: a VM can push `main`" |
| Proxy "doesn't limit which branches a push can update" | True, live | `https://code.claude.com/docs/en/cloud-environments.md` line 242, fetched 2026-10-06 (HTTP 200, 59,241 bytes, same size as the saved copy) |
| `CLAUDE_CODE_REMOTE` is `true` in the session VM, "never `true` locally" | True, live | same page, lines 475-484 and 493 |
| Post says the credential "can push only to its own working branch" | True, and contradicted by the docs | `https://claude.dev/blog/claude-code-in-the-cloud/`, fetched 2026-10-06; `https://code.claude.com/docs/en/security.md` line 104: "A rule that access can bypass doesn't block a session's push" |

Plan eligibility is not a constraint: the env var is not plan-gated in the docs.

## 2. Is the pain point still open?

Open as a route, dormant in practice.

- **No later cure.** The only commit to `scripts/ship-land.sh`, `bin/cc-dispatch` or `scripts/lib/cloud-create.sh` since 2026-10-02 is `6830823be` (2026-10-03, instruction-budget ratchet), unrelated (measured: `git log --since=2026-10-02 -- <those paths>`).
- **No row tracks the residual.** `8f4eae55a0c7` closed WON'T-DO on 2026-10-02 (Enterprise-only email rule). A regex scan of `~/.claude/autonomy/backlog.jsonl` (4,241 items, measured) found no row for a script-side guard. The scan was narrow, so this is "none found", not proof.
- **Zero recurrence.** Measured: `git log origin/main --author=noreply@anthropic.com` = 88 commits, newest 2026-09-04T18:07:46Z. Measured: `git log origin/main --since=2026-09-05 --format='%ae|%ce' | sort | uniq -c` = 2,817 commits, one author/committer pair, the sanctioned address.
- **Detection exists.** `identity_landed_sweep` at `scripts/postland-verify.sh:4054,4097` (landed `13d8a9d98`, 2026-10-01); `com.claude.postland-verify` is loaded and `~/.claude/autonomy/postland/identity-scan.sha` was written 2026-10-06 12:12 (measured: `launchctl list`, `ls -la`).

## 3. What strengthens the row beyond what it says

- **The repo's own always-loaded instructions tell a VM to `/ship`.** `.claude/CLAUDE.md:18-26` is the standing-land authorization: complete, gate-green work "lands via the project-local `/ship` flow without a fresh ask". The post states that CLAUDE.md, rules and commands "travel with the repo", and `.claude/commands/ship.md` is tracked. The brief sentence is the only counterweight.
- **The second prose rail states a falsehood.** `scripts/lib/cloud-create.sh:285` (API lane, `588d49be6`, 2026-09-07) says "you cannot run this repo's /ship". The trace doc shows a VM did, 93 times.
- **Damage is not undoable by the pager.** The trace doc's "Out of scope" section says rewriting the 93 needs a force-push of `main`. Detection in 5 minutes bounds the count, not the cleanup.
- **The desk is safe from the guard.** Measured in this local session: `CLAUDE_CODE_REMOTE` unset, `CLAUDE_CODE_ENTRYPOINT=cli`.

## 4. What weakens it (corrections to the row)

1. **"One prose sentence" is two.** `bin/cc-dispatch:3084` (dispatcher lane) and `scripts/lib/cloud-create.sh:285` (API lane).
2. **The "identity hooks are absent" arm is not effort S.** The hooks are copies in `<git-common-dir>/hooks` (`scripts/git-identity-assert.sh:29,118-165`; measured: `core.hooksPath` unset, `pre-push` present in the shared `.git/hooks`). A fixture repo from `git init` has none.
   - Measured: 72 `tests/*.bats` suites reference `ship-land.sh`; 59 of those also mention a bare remote; 0 mention `hooksPath` or install the hook.
   - `.github/workflows/hermetic.yml:114,133` runs the suites on `ubuntu-latest` and `macos-latest`, also hookless.
   - Estimated consequence (by co-occurrence, not by running them): up to 59 suites lose their fixture lands unless each gets an override, and an override is a bypass a VM can also set.
   - Cheaper fallback with the same reach: refuse when the effective committer is `noreply@anthropic.com`, the address on all 88 measured VM commits. Fixtures do not use it.
3. **The title overclaims.** The guard closes `/ship` in a VM. `git push origin HEAD:main` stays open (docs line 242), and the VM owns its own copy of `ship-land.sh`. Only K02 (server-side rule, trial, 40%) is a mechanical closure.
4. **The env arm also fires inside VM-run bats fixtures.** `bin/cc-bats:385-403` unsets `CLAUDE_CODE_SESSION_KIND`, `CLAUDE_JOB_DIR` and `KITTY_PID`, not `CLAUDE_CODE_REMOTE`. A VM worker running a ship-land suite would see every fixture land refused. Needs one `unset` there and an explicit set in the guard's own test.
5. **Self-hosted runners set the same variable.** The 2.1.284 binary spawns its self-hosted child with `CLAUDE_CODE_REMOTE:"true"` beside `CLAUDE_CODE_REMOTE_ENVIRONMENT_TYPE:"self_hosted"` (measured: Python search of `/tmp/cloud-blog-eval/strings-284.txt`). A desk-hosted self-hosted runner would be refused by this guard, so it interacts with any self-hosted candidate.
6. **No throughput effect.** Self-landing has occurred 0 times since the 2026-09-02 brief change (measured, section 2), over 87 post-gate fires (reported by `a4-economics-and-live-state.md:13`, not re-measured). The change recovers no rows and no quota. It is integrity insurance.

## 5. The riskiest assumption

`CLAUDE_CODE_REMOTE=true` in sessions from our private `POST /v1/sessions`: likely, still unmeasured.

- Our create is `teleportToRemote`'s own body and asserts `environment_kind == "anthropic_cloud"` (`scripts/cloud-create-api.py:57-74,411-432`). It is the product CLI's path, not a separate one.
- The CLI itself keys cloud behaviour on the variable: `yc()` is `CLAUDE_CODE_REMOTE===true && ENVIRONMENT_KIND===undefined`, and the tool-call envelope reports `caller.kind` as `ccr_container` when it is set (measured: binary strings).
- Settings cannot override it: it is in the launch-environment-wins set ("the launch environment takes precedence over settings"), so a repo `env` block cannot unset it.
- Indirect in-VM evidence: 61 of the 93 VM commits carry a `Claude-Session: https://claude.ai/code/session_…` trailer (`off-identity-commits-trace-2026-10-02.md:21`), which the docs build from the sibling `CLAUDE_CODE_REMOTE_SESSION_ID` in a shell command (docs lines 333-340).
- Estimate (reasoning, not measurement): 90% that it is `true` in a Bash-tool child in our VMs.
- If absent, the env arm fails open, which is why a second, env-independent arm is worth keeping.
- Free probe, described and not run: one brief sentence asking the next organic fire to put `${CLAUDE_CODE_REMOTE-unset}` in its first commit body. The dispatchable cloud queue is 0 today (`a4-economics-and-live-state.md:14`, reported), so it waits for supply.

## 6. Alternatives considered

| Alternative | Ruled out because |
|---|---|
| Skip: 0 recurrences plus a 5-minute pager is enough | `.claude/CLAUDE.md:18-26` pushes every VM toward `/ship`; one brief regression re-opens it, and cleanup needs a force-push |
| Trial instead of adopt | The guard fails open and the desk never carries the variable, so there is nothing a trial would protect against |
| Server-side rule only (K02) | The right closure, but it needs a distinct landing actor and is untested; not a substitute at effort S |
| Repo PreToolUse or SessionStart hook (K03) | Depends on project hooks loading on our create path, which is unverified; the script guard does not |

## 7. Not verified

- The variable inside one of our VMs (no session was started; out of scope).
- Whether `ship-land.sh` at today's tip still completes on a Linux VM (not run).
- Freshness of `origin/main` beyond the local ref (no fetch).
- The 87 post-gate fire count (taken from `a4`).

## Corrected change

Refuse a land (after the `--precheck` dispatch at `scripts/ship-land.sh:5536`, before `inflight_claim`) when `CLAUDE_CODE_REMOTE=true` or the effective committer is `noreply@anthropic.com`; unset the variable in `bin/cc-bats`; fix `docs/runbooks/cloud-fleet.md:27-28` and `scripts/lib/cloud-create.sh:285`; rename the row to "refuse `/ship` in a cloud VM".
