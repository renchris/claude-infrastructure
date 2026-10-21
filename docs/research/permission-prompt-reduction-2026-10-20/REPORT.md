# Permission-prompt reduction — 14-day census, widening, replay (2026-10-20)

Operator instruction of 2026-10-20 (ruling on decision `29d62f1ad390`, verbatim): *"we want a little
human in the loop as possible (permission prompts is virtually always a yes, so improve our
allowlist/config/settings such that our past usage of commands are pattern recognized and allowed;
only raise questions if <90% conviction after exhaustive own research)"*. The same packet was
resolved **narrows**: outside research programs, results touching money, auth, third parties,
publishing, self-modification or production keep a one-line yes/no.

Window: the 14 days ending 2026-10-21 06:10 UTC. Instruments, all read-only:
`cc-permission-harvest 14`, `cc-hook-asks 14`, `cc-autodeny-census --since 14d`, a transcript join
for every refused row, a transcript count of classifier denies, and `replay.py` (this directory).

## 1. The answer first

**Replayed against the last 14 days, the widened hooks plus migration 0074 auto-allow 97 of the
649 Bash permission dialogs (14.9%, 72.7 h of the 488 h sessions waited) as measured, and about
224 (34.5%, ~240 h, roughly half the waiting) once the 127 dialogs that ask in the replay only
because their worktree has since been reaped are counted at run time. They also clear 195 of the
308 validate-bash confirmation asks (63%).** Today's hooks clear 23 (3.5%) of the same dialogs.
Not one of ~1,100 prompts in the window was refused on its merits (§2.1).

What still asks is mostly arbitrary code: interpreters and ad-hoc scripts (`python3`, `bash -c`,
`uv run`, `./sb`, `check-names.sh` — ~238 dialogs), which an allow rule would approve blind and
which the auto-mode classifier is there to judge; then live-state git/rm checks that found
something to lose (~76), and curl-gate's security asks (141, unchanged). §3.4 lists every class
and why it stays.

**Landing and converging are the operator's.** The auto-mode classifier refused this session the
guard-suite runs and the grep-site fixture re-pin as self-modification, and nothing was routed
around it. The hook change, migration 0074 and this report are committed on branch
`perm-prompt-reduction-2026-10-20`; one script finishes it:
`bash ~/Development/.worktrees/perm-prompt-reduction-2026-10-20/scripts/permission-widening-2026-10-20-finish.sh --confirm settings.json`
(re-pin, gate, land, converge, then 0074; without `--confirm settings.json` it stops before the
settings write).

## 2. Census — where the prompts came from

Four sources, counted separately because they are different mechanisms. Sources 1 and 2 overlap
where a hook ask on the main thread also raised the dialog the beacon recorded (39 rows joined);
they are not summed.

| # | source | count | approved | refused on its merits | other end | waited |
|---|---|---|---|---|---|---|
| 1 | Claude Code permission dialog (beacon archive, `PermissionRequest`) — Bash | **644** in 257 sessions | 539 | **0** (see §2.1) | 99 Stop-resolved, 6 abandoned | 486.8 h |
| 1b | same archive, non-Bash | 45 | 2 (`Edit`, `EnterWorktree`) | 0 | 43 are `AskUserQuestion` — questions, not permission prompts | — |
| 2 | PreToolUse hook `ask` (`cc-hook-asks`) | **449** — validate-bash 308, curl-gate 141 | 361 ran | **0** (see §2.1) | 72 auto-denied unanswered, 12 interrupted, 3 teammate denials, 3 pending/unknown | ~316 h |
| 3 | Claude Code's built-in dangerous-removal check (timed auto-deny) | **84** (60 timed out, 12 capped, 12 immediate); 59 in workflow slots | — | — | plus 60 preempted at once by `rm-prompt-preempt` | — |
| 4 | auto-mode classifier deny (not a prompt: a refusal) | **~215** unique tool uses (141 main, 91 subagent/workflow) | — | — | top reasons: unexplained server-side 51, Modify Shared Resources 35, Credential Exploration 22, Auto-Mode Bypass 14, Self-Modification 12 | — |

`waited` for approved archive rows runs to the tool's completion (the beacon clears on
`PostToolUse`), so it overstates the human wait by each command's runtime.

### 2.1 Nothing was refused on its merits

Every refusal-shaped row was joined to its transcript:

- **Archive Stop-resolved (99) and abandoned (6)**: 40 joinable. 6 carry "The user doesn't want to
  proceed" — and in **all 6** the operator's next message is `[Request interrupted by user for tool
  use]` followed by arming a `/goal`: the operator interrupting a session stalled 20 min–2 h to
  re-drive it, not a verdict on the command. 16 were denied at once by the `rm-prompt-preempt`
  hook, 8 by Claude Code's dangerous-removal check, 10 actually ran; 65 had no joinable command
  text.
- **Hook asks "rejected" (3)**: all teammates, each denied after ~8,300 s with "Permission denied"
  at team teardown — not a human reading the command.

So the operator's premise holds on this window: **0 of ~1,100 prompts was refused on its merits.**

### 2.2 Source 1 by bucket (`cc-permission-harvest`, MECE over 644)

| bucket | rows | what it means |
|---|---|---|
| structural | 370 (57.5%) | `$( )`, redirect to a file, heredoc, `cd`+`git`, multi-`cd` … gated before any allow rule; only a hook `allow` clears these |
| ask_hit | 156 (24.2%) | an operator `ask` rule fired — **every one `Bash(git push:*)`** |
| hook_raised | 39 (6.1%) | curl-gate 22, validate-bash 17 |
| rule_gap | 52 (8.1%) | a leaf no allow rule covers |
| gap_unrecoverable | 19 (3.0%) | rule gap whose cwd is gone |
| hook_or_classifier | 5 (0.8%) | |
| truncated | 3 (0.5%) | |

**`git push` alone is in 307 of the 644 dialogs (47.7%)** — 156 non-structural plus 146 structural
approved plus 5 Stop-resolved — overwhelmingly `git push origin HEAD:main` from `/ship` flows in
agent-context-sync, reso-web-app, sevenrooms-bridge and their worktrees. Both reso repos document
that a push to `main` deploys nothing. `hooks/ship-rail-push-allow.sh` was built to clear exactly
this shape and is inert while the ask rule stands (deny > ask > allow; measured 2026-10-03).

The harvester's own rule-layer proposal for the window is **0 rules** (63 candidates refused: 40
interpreter/shell heads on `ACE_CLASS`, the rest on refused-prompt collision, evidence floor or
path-bound). That confirms `prefix-rules-cannot-express-shell-programs`: the lever is the hook layer.

### 2.3 Source 2 by reason

| hook | reason | asks | outcome |
|---|---|---|---|
| validate-bash | `rm -r on non-build-artifact target` | 160 | 82 ran, **71 auto-denied unanswered**, 3 interrupted, 1 teammate denial, 3 pending/unknown |
| validate-bash | `git reset --hard can destroy uncommitted work` | 116 | 110 ran, 5 interrupted, 1 auto-denied |
| validate-bash | `git restore of the WORKING TREE` | 19 | 15 ran, 2 teammate denials, 2 interrupted |
| validate-bash | `git stash drop on an entry not selected by its own tag` | 11 | 11 ran |
| validate-bash | `git clean -x/-X` | 2 | 2 ran |
| curl-gate | `No URL parsed; review manually` | 98 | 98 ran |
| curl-gate | POST to an unknown host / GET to an unvetted host with a credential | 43 | 43 ran |

rm targets: 71 literal `/tmp` paths, 48 variables, 40 relative (mostly after `cd /tmp/x &&`), 1
other. reset shapes: 37 `cd`+`-C`, 31 `cd`, the rest heredoc briefs that only MENTION the verb.

## 3. The widening — what changed, and the evidence for each arm

Every arm is a positive grammar decided on the resolved path; anything it cannot decide keeps asking
exactly as before. Hook decisions merge deny > ask > allow, so a validate-bash ask always outranks a
smart-bash allow.

### 3.1 `hooks/validate-bash.sh`

| arm | change | evidence (14 days) |
|---|---|---|
| AGENT SCRATCH (`is_scratch_temp_path`) | strictly under `/private/tmp`, outside the reserved top-level names the fleet's live state uses (dot-files, `cc-*`, `claude*`, `land-lock*`, `com.*`, `tmux-*`, `kitty-<n>`, `launchd*`, `powerlog`, `Cursor-*`, `*.sock`), and holding no socket (bounded `find -type s`) | /tmp is the agents' landfill (census of its top-level names); every live-infra entry found sits under one of those names |
| rm SCRATCH-TEMP | `rm -r` of an agent-scratch target — literal, same-command variable, or relative resolved through the scan's per-statement cwd (a `cd` chained by `&&` replaces the cwd, any other separator adds to it) | 160 asks, 0 refused on merits, 71 auto-denied |
| rm deep artifacts | `__pycache__`, `node_modules`, `.next`, `.turbo`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `.tox`, `htmlcov` at any depth of a relative path; `build`/`dist`/`out`/`target` stay top-only (`scripts/build` can be source) | 8 asks |
| GIT-OWNERSHIP cd/`-C` | a literal `cd <dir>` / `git -C <dir>` is tracked instead of making the command opaque; every dir the statement may run in must pass | 102 of 116 reset asks carried `cd` or `-C` |
| GIT-OWNERSHIP scratch | reset/restore in a scratch repo need no lossless proof; a stash drop needs the repo's COMMON dir in scratch too (a /tmp worktree of a real repo shares its stash) | reset 116, restore 19, drop 11 — all approved |
| heredoc mentions | when heredoc bodies cannot execute (`vb_classify`), the scan reads `CMD_NOHD`, so a brief that mentions `git reset --hard` is not an invocation | the heredoc-brief share of the 116 |
| PUSH (new) | asks unless non-force, literal remote and refspecs, and every remote is a github/gitlab/bitbucket repo owned by `CC_VB_PUSH_OWNERS` (default `renchris`) or a local path. **Inert until migration 0074** removes the blanket ask; it is what keeps third-party pushes behind a prompt after it | 307 push dialogs; of the 178 clones under `~/Development` with an `origin`, 96 are `renchris` and the rest someone else's — why owner, not remote name, is the test |

### 3.2 `hooks/lib/smart-bash-allowlist.py` (the hook `allow` that clears structural prompts)

| arm | change | evidence (blocker counts over the 601 still-asking rows) |
|---|---|---|
| write scope | redirect targets, `tee`, `cp` (destination), `mv` (both ends), `touch`, `mktemp`, `ln` — admitted into the project (cwd subtree, never `.git/`, never when cwd is `$HOME` or `/`) or agent scratch; relative targets judged against the cwd and every literal `cd` | `cat >` 51, `echo >` 32, `printf >` 16, `: >` 14, `tee` 11, `cp` 40, `touch` 5, `mv` 5, `mktemp` 27 |
| redirect check first | every arm's redirect targets are judged before the arm (git commit / sed / chmod used to return ahead of the scanner) | closes an existing hole |
| local git | add, commit, switch, rebase (not `-x`/`-i`), merge (not `-s`), cherry-pick, revert, stash push/apply/drop, clone (not `-c`, `ext::`), init, worktree (not `--force`), pull, tag, branch, mv, rm (not `-f`), notes, apply, am, reset/restore (validate-bash judges the lossy forms), checkout `-b`/`-B`/`--detach` only, config (safe keys, repo-local), push (non-force, literal); `-C <literal>` and safe `-c` keys peeled; the fence re-checked on the canonical form | `git add` 91, `git rebase` 58, `git branch` 36, `git -C` 35, `git clone` 25, `git init` 20, `git -c` 14, `git config` 10, `git stash` 9, `git switch` 7 |
| push | allowed as a segment; still behind the fence while `Bash(git push:*)` stands | 302 rows carry the fence; 127 have it as their ONLY blocker |
| rm in a compound | the same scratch category, with same-command variable resolution and `$(mktemp -d)` provenance | `rm` 55 |
| wrappers | `timeout`, `time`, `nice`, `nohup`, `taskpolicy` judged by the command they run | `timeout` 10 |
| inert builtins | `read`, `continue`, `break`, `exit`, `return`, `shift`, `wait`, `umask`, `unset`, `local`/`declare`, `command -v`; input-redirect-only segments | `read` 15, `continue` 8, `exit` 6, `break` 5 |
| read-only verbs | `uptime`, `shellcheck`, `nproc`, `getconf`, `vm_stat`, `sha256sum`, `ioreg`; git `cherry`, `ls-remote`, `range-diff`, `show-ref`, `show-branch`, `fsck` | `uptime` 6, `shellcheck` 8, `git ls-remote` 5 |

### 3.3 Settings — `migrations/0074-git-push-ask-to-hook.sh` (c10, operator-run)

Removes exactly `Bash(git push:*)` from `~/.claude/settings.json` (every account links to it).
Refuses unless the live `validate-bash.sh` carries the PUSH arm, backs up, verifies by content.
**Stays**: deny `git push --force`/`-f`; ask `fly deploy` (production) and `git stash clear`
(irreversible, every session's stash).

### 3.4 What deliberately still asks, and why

| class | why it stays |
|---|---|
| interpreters and ad-hoc scripts (`python3`, `bash -c`, `node`, `uv run`, `./sb`, `check-names.sh` …) | arbitrary code: an allow approves whatever it is handed (`ACE_CLASS`), and the auto-mode classifier is the judge the operator chose for it; it is also where the classifier's Credential Exploration / Production / Exfiltration refusals live |
| pushes to someone else's repository; delete/mirror/forced refspecs | third party / publishing — kept by the "narrows" ruling |
| `fly deploy`, production paths | production — kept by the ruling |
| `git stash clear`, `git clean -x` | irreversible across sessions / paid gitignored assets |
| curl-gate asks (unresolvable URL, unknown-host POST, credentialed GET) | reso-management-app's security gate; an unresolved URL can be an internal address or carry a secret, which the instruction keeps behind a question (touches a secret) |
| writes outside the project and agent scratch (`~`, `/etc`, `.git/`, `.claude/settings*`, reserved /tmp names, socket-holding dirs) | live state, credentials, self-modification |
| Claude Code's built-in dangerous-removal check; classifier denies | no allow rule or hook clears them by design (§2.2 of permission-matcher-truth-2026-08-20); the remedy is command shape (`rm-prompt-preempt`) |

## 4. Replay — the share of the 14-day sample the new rules now auto-allow

`replay.py` re-runs every recorded command through a hook tree and a fleet `ask` set. Measured
2026-10-21; the window grew by 1–5 rows between passes.

**Source 1 — Claude Code permission dialogs (Bash)**

| tree | `git push` ask | dialogs auto-allowed | waited cleared |
|---|---|---|---|
| live `~/.claude/hooks` (today) | kept | 23 / 648 (3.5%) | 4.9 h / 488 h |
| this branch | kept | 49 / 648 (7.6%) | 22.1 h |
| this branch + migration 0074 | removed | **97 / 649 (14.9%)** | **72.7 h** |
| same, counting the 127 rows whose worktree was reaped (they ask in the replay only because their remote cannot be read now) | removed | **~224 / 649 (~34.5%)** | **~240 h** |

Of the 552 still asking after 0074 (classified against the new allowlist): arbitrary code
(interpreters, ad-hoc scripts) ~238; a push whose only blocker is the unreadable remote of a
reaped worktree 127, plus 5 whose remote really is someone else's or unresolvable; validate-bash
live-state asks that found something to lose ~76; other verbs not on the allowlist ~90; subshell
grouping the decomposer refuses 19; curl 10; truncated 3.

**Source 2 — PreToolUse hook asks (cc-hook-asks, 449)**

| hook | asks | live tree clears | this branch clears |
|---|---|---|---|
| validate-bash | 308 | 2 | **195 (63%)** — reset 70 of 116, rm -r 108 of 160, restore 13 of 19, stash drop 2 of 11 |
| curl-gate | 141 | unchanged by this work | unchanged — reported as still asking |

The replay recovers each hook ask's cwd from its transcript; for the 118 curl asks raised in
workflow slots that recovery lands on the parent session's cwd, outside curl-gate's project
scope, so the replay's own "cleared" figure for curl-gate is an artifact and is not used. The
validate-bash figures use the same recovery on both trees, so their difference is the change.

**Instrument defects found and fixed during the measurement** (each would have overstated or
hidden the result): validate-bash prints multi-line JSON, which a last-line parse read as "no
decision"; a reduced PATH put `/usr/bin/python3` 3.9 first, which crashes curl-gate.py silently;
the cwd index re-read a session's transcripts per row.

## 5. Reproduce

```
cc-hook-asks 14 --json --out /tmp/ppr/hookasks.json
/usr/bin/python3 docs/research/permission-prompt-reduction-2026-10-20/replay.py --tree ~/.claude/hooks --hookasks /tmp/ppr/hookasks.json
/usr/bin/python3 docs/research/permission-prompt-reduction-2026-10-20/replay.py --hookasks /tmp/ppr/hookasks.json
/usr/bin/python3 docs/research/permission-prompt-reduction-2026-10-20/replay.py --ask-drop 'Bash(git push:*)' --hookasks /tmp/ppr/hookasks.json
```

Limits: the replay runs today's hooks against the commands as recorded, so a live-state check
(validate-bash's lossless reset proof, a socket scan) reads the repo or directory as it is now, and a
row whose cwd has since been reaped is judged against the fleet rules alone. A cleared row means
every arm that raised it is gone and some hook now emits `allow`; a row whose remaining step would
go to the auto-mode classifier is counted as still asking.
