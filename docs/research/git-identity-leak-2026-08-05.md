# Git-identity leak — census of every path that can write `user.email`/`user.name` into a real repo

**Date:** 2026-08-05 · **Scope:** read-only investigation, no edits, no commits.
**Root-cause class (given):** `git -C ""` is a documented no-op — it does **not** change directory —
so `git -C "$dir" config user.email t@t` with `$dir` empty writes the fixture identity into
**whatever repo owns the current working directory**.

---

## 🚨 LIVE POISONER — caught in the act, still running (added after the census)

**`pid 57191` — `/bin/bash ~/Development/.worktrees/wt-kitty-menu/scripts/postland-verify.sh
--run-if-needed`, started 2026-08-05 00:51:28, still running 12 h 41 m later — is re-poisoning
`~/Development/claude-infrastructure/.git/config` every ~2–3 minutes right now.**

Proof, from a fully idle control window (zero processes of mine running, verified by `pgrep`):

| Observation | Value |
|---|---|
| `.git/config` mtime at t0 | `1785961809` |
| `.git/config` mtime at t0+100 s | **`1785961841`** — written while nothing of mine ran |
| `.git/worktrees/wt-run-57191/logs/HEAD` newest entry at the same moment | `… t <t@t> **1785961841** -0700 commit: b` |
| Reflog line count over 45 s | 836 → 837 (**still growing**) |
| Cell mint time | 2026-08-05 **03:21** — inside the stated 02:00–03:45 window |

The config write and the `a`/`b` commit are **the same event, to the second**. This is a runaway
`git bisect run` (`do_bisect`, `postland-verify.sh:824-825`) that has been stepping for ~10 hours
inside `~/.claude/autonomy/postland/wt-run-57191`, a **real linked worktree** of the primary
checkout. Every step: writes `[user] t / t@t` into the shared config, commits `a` then `b` into the
operator's real object store on the worktree's detached HEAD, then checks back out to `6e8e18d1`.

**Correction to an earlier line in this document:** I initially attributed the 13:04–13:05 `a`/`b`
commits to a sibling session's repro. That was wrong. They are pid 57191's bisect steps. The
"cleaned config at 13:06:23" was a sibling's cleanup, which pid 57191 then immediately undid.

**Operator action (this is the one thing that stops the bleeding):**

▶ Run this:

`kill 57191 && git -C ~/Development/claude-infrastructure worktree remove --force ~/.claude/autonomy/postland/wt-run-57191 && git -C ~/Development/claude-infrastructure config --local --unset-all user.email && git -C ~/Development/claude-infrastructure config --local --unset-all user.name`

### What is proven, and what is not

**Proven.** The bisected file is `tests/cc-blockers.bats` — head of the `10:21Z` RED failing list in
`runner.log`, and the **only** producer of commit subjects `a` and `b` in the whole tree
(`tests/cc-blockers.bats:563-567`: `git init -q "$D/repo"` → `git -C "$D/repo" config user.email
t@t` → `commit -qm a` → `commit -qm b`). The bisect runner executes it with cwd = the linked
worktree, whose config **is** the primary checkout's config.

**Not proven.** *Why* `"$D/repo"` resolves to the real repo inside that runner. `$D` is
`$BATS_TEST_TMPDIR`, which I measured to be robust under a hostile/absent/empty/trailing-slash
`TMPDIR` (bats 1.13.0 always produced a real path). Running the same suite, and the same three
individual tests, from an isolated clone-worktree did **not** reproduce the write.

**Refuted, by measurement — do not repeat this hypothesis.** `git bisect run` does **not** export
`GIT_DIR`/`GIT_WORK_TREE` into its run script. A direct probe (`git bisect run` on a throwaway repo,
runner echoing its env and then `git -C <fixture> config user.email t@t`) printed `GIT_DIR=[]
GIT_WORK_TREE=[]` and wrote **only** the fixture's config; the real repo stayed clean. The
attractive "inherited GIT_DIR overrides `-C`" story is false.

---

## Verdict (answer first)

**The leak is not one bad line — it is one bad *place*. `scripts/postland-verify.sh` runs the entire
273-suite bats corpus with `cwd` inside a REAL linked worktree of `claude-infrastructure`, and every
linked worktree shares the primary checkout's `.git/config`.** Any corpus site that loses its path
argument therefore writes `[user] name=t / email=t@t` into the operator's shared config, and ~137
worktrees plus the primary checkout inherit it instantly.

| | Convicted | Confidence | Why |
|---|---|---|---|
| **C1** | **The exposure itself** — `postland-verify.sh:609/655/663/1104/1106` (`( cd "$WORKTREE" && … bats … )`) and `do_bisect` at `:824-825` (`git -C "$WORKTREE" bisect run "$runner"`, which git executes with cwd = `$WORKTREE`). `$WORKTREE` = `~/.claude/autonomy/postland/wt-run-$$`, a **real `git worktree add`** off `$HOME/Development/claude-infrastructure` (`prepare_worktree`, `:96/:108`). | **HIGH** | Direct read of the code + live artefact: the cell `~/.claude/autonomy/postland/wt-run-57191` still exists, minted **2026-08-05 03:21 PDT — inside the stated 02:00–03:45 poisoning window** — with `BISECT_RUN`/`BISECT_LOG` present and `.git/worktrees/wt-run-57191/logs/HEAD` authored `t <t@t>` throughout. A poison written from inside that cell lands in the shared config by construction. |
| **C2** | The **`git -C "$1"` fixture helpers** in the bats corpus (`waiting-recycle.bats:944`, `cc-respawn.bats:12`, `reap-guard.bats:13`, `cc-teardown-safety-gate.bats:11`, `statusline-identity.bats:97`, `cc-reaper.bats:20`, `cc-classify.bats:77`, `teammate-auto-shutdown.bats:352/652`, `bats-shellcheck-lint.bats:96`, `handoff-fire-repo-resolution.bats:69`) — all write the **exact observed signature** `user.email t@t` + `user.name t`, and bats bodies run **without `set -u`**, so a zero-arg or empty-var call is `git -C ""` = silent cwd write. | **MEDIUM-HIGH** for the class; **not pinned to one line** | Every call site I could enumerate passes a non-empty literal-prefixed path today, so I will not name a single line as *the* one. The class is nonetheless the only mechanism that produces the exact `t`/`t@t` pair with no error. |
| **C3** | `tests/gate-manifest.bats:226-227, 242-243, 259-260` — `repo="$BATS_TEST_TMPDIR/repoN"; mkdir -p "$repo"; cd "$repo"` with an **unguarded `cd`**, followed by `git init -q; git config user.email t@t; git config user.name t` with **no `-C` at all**. If that `cd` ever fails, cwd stays the postland worktree and the write is a direct hit — same exact signature. | **MEDIUM** | Code read. This is the only `t@t`-signature site whose failure mode is *by construction* a cwd write; its trigger (a failed `cd` into a just-`mkdir`'d tmpdir) is rare but not impossible (tmpdir reaped mid-run, ENOSPC). |
| **C0 (supersedes C2/C3 as the ACTUAL live cause)** | **pid 57191's runaway `postland-verify` bisect** — see the section above. Timestamp-matched to the second in an idle control. | **PROVEN** | The `a`/`b` commits and the config writes are the same events, still occurring. |

**What was NOT the cause:** the global `~/.gitconfig` is intact (`user.name=Chris Ren`,
`user.email=ren.chris@outlook.com`). Both repos' *local* `[user]` blocks are currently empty — the
poison has already been removed by another session, so the surviving evidence is the authored
commits and the worktree reflogs, not the config files.

---

## The mechanism, stated once

```
postland-verify.sh
  prepare_worktree <sha>          →  git -C ~/Development/claude-infrastructure \
                                       worktree add --detach ~/.claude/autonomy/postland/wt-run-$$ <sha>
  run_scoped_suite / confirm_hang →  ( cd "$WORKTREE" && TMPDIR=… bats <file> )
  do_bisect                       →  git -C "$WORKTREE" bisect run "$runner"   # runner's cwd == $WORKTREE
```

`~/.claude/autonomy/postland/wt-run-*/.git` is a **gitfile** pointing at
`~/Development/claude-infrastructure/.git/worktrees/wt-run-*`, whose `commondir` is `../..`. A
linked worktree has **no config of its own** — `git config --local` in it writes
`<primary>/.git/config`. So:

> one `git config user.email t@t` executed with an empty/absent `-C` anywhere in the 273-suite
> corpus ⇒ the operator's primary checkout **and all ~137 worktrees** are poisoned at once.

`prepare_worktree` already carries the *adjacent* guard — it refuses when the cell path resolves to
the live repo (`"$wtp" = "$repop"`). That guard protects the **working tree**. It does nothing for
the **shared config**, which is the surface that was actually hit.

### Timeline corroboration

| Time (PDT) | Event | Source |
|---|---|---|
| 2026-08-05 00:12Z run | postland RED on `af3393716b2b`, 12 failing suites | `~/.claude/autonomy/postland/runner.log` |
| **2026-08-05 03:21** | `wt-run-57191` cell minted (dir mtime; `BISECT_*` files present) | `ls -la ~/.claude/autonomy/postland/wt-run-57191` |
| 2026-08-05 10:21Z | postland RED on `7ded71b83209`, failing list **headed by `tests/cc-blockers.bats`** → `red_actions` → `do_bisect` | `runner.log` |
| 2026-08-05 10:40 onward | dozens of `checkout … / commit: a / commit: b` reflog entries, all authored `t <t@t>` | `.git/worktrees/wt-run-57191/logs/HEAD` |
| 2026-08-05 13:06:23 | primary `.git/config` `[user]` block removed | config mtime |

The **03:21 cell mint sits inside the stated 02:00–03:45 window**. That is the strongest available
temporal link, and it is a link to the *place*, not yet to a single line.

---

## Full census

Method: `grep -rn` over the checkout, **plus `grep -rn --dereference-recursive`** over
`~/.claude/{bin,scripts,hooks,commands,agents,skills}` and `~/.claude-next/*` (the live layer is
per-file symlinks; plain `-r` skips them and returns a false zero). Reso covered separately.

**Totals:** 125 matching lines in `claude-infrastructure` (16 outside `tests/`), 16 in the
dereferenced `~/.claude` layer (all symlinks to the same checkout files — **no divergent copy**),
12 in `~/.claude-next` (same), 5 in reso (4 are permission-allowlist strings, 1 is a guarded script).

### A. Non-test code (`bin/`, `scripts/`, `hooks/`)

| Site | Code | Class | Reason |
|---|---|---|---|
| `bin/cc-bind:146` | `cd "$tmp" \|\| exit 1` … `git init -q .; git config user.email t@t; git config user.name t` | **SAFE** | Inside `( … )`; `cd … \|\| exit 1` is guarded; `tmp="$(mktemp -d …)" \|\| die` at `:142`. |
| `bin/cc-dispatch:1266` | `( mkdir -p "$wtrepo" && cd "$wtrepo" && git init -q . && git config user.email t@t && … )` | **SAFE** | Full `&&` chain — an empty `$wtrepo` fails at `mkdir -p ""` and short-circuits before any config write. |
| `bin/cc-value:349, 404, 427` | `git -C "$REPO"/"$EMPTY"/"$UNATTR" config user.email t@t` | **SAFE** | All three are `"$tmp/<suffix>"` with a literal path segment, so never the empty string; `tmp` from a `\|\| die`-guarded `mktemp -d`. |
| `bin/cc-respawn:209` | `git -C "$wt" config user.email t@t` | **SAFE** | `wt="$tmp/wt"` — literal suffix. |
| `bin/cc-teardown:866` | `mkrepo() { local r="$1"; … git -C "$r" config user.email t@t; }` | **SAFE (fail-fast)** | File runs under `set -u` and every call passes `"$d/<name>"`; a zero-arg call aborts on `$1: unbound variable` rather than writing. |
| `bin/cc-teardown-safety-gate.sh:128` | same shape | **SAFE (fail-fast)** | Same reasoning; `d` from `mktemp -d \|\| die`. |
| `scripts/reap-guard.sh:251` | `local repo="$1" … git -C "$repo" config user.email t@t` | **SAFE (fail-fast)** | `set -u`; `d="$(mktemp -d …)" \|\| die`. |
| `scripts/postland-verify.sh:1344` | `git -C "$d/src" config user.email pv@selftest.local` | **SAFE** | Literal suffix; and the identity is `pv@selftest.local`, not the observed signature. |
| `scripts/supervisor-e2e.sh:44, 59` | `REPO="$SBX/repo"` / `local r="$1"` | **SAFE** | `set -u`, literal suffix, `SBX=$(mktemp -d)`. |
| `scripts/boundary-hook-e2e.sh:28` | `REPO="$SBX/repo"` | **SAFE** | Same. |
| `scripts/telemetry-e2e.sh:142, 167` | `VLREPO="$V8/repo"`, `EMPTYR="$V8/empty"` | **SAFE-ish** | Literal suffix, but `V8=$(mktemp -d)` is **unchecked** (`set -u` only, no `\|\| exit`). A failed `mktemp` yields `/repo` → `git init` fails loudly; it cannot become `""`. **Worth hardening (see F3).** |
| `scripts/reaper-e2e.sh:60` | `REPO="$D/repo"` | **SAFE-ish** | Same shape as above. |
| **`scripts/postland-verify.sh:609, 655, 663, 824-825, 1104, 1106`** | `( cd "$WORKTREE" && … bats … )`, `git -C "$WORKTREE" bisect run` | **🔴 LEAKY — the amplifier** | Writes nothing itself, but **makes every corpus site's cwd a real linked worktree of the operator's repo.** Without this, an empty-`-C` fixture would poison a throwaway; with it, it poisons the live layer. |

### B. Test corpus — the leaky shapes

| Shape | Sites | Class |
|---|---|---|
| `git -C "$1" config user.email t@t` in a fixture helper (bats ⇒ **no `set -u`** ⇒ a missing arg is `""`, not an error) | `waiting-recycle.bats:944-945` (`_wr_repo`), `cc-respawn.bats:12`, `reap-guard.bats:13` (`mkgit`), `cc-teardown-safety-gate.bats:11` (`mkrepo`), `statusline-identity.bats:97` (`mk_repo`), `cc-reaper.bats:20` (`mkrepo`), `cc-classify.bats:77/85`, `teammate-auto-shutdown.bats:352/652/878`, `bats-shellcheck-lint.bats:96`, `handoff-fire-repo-resolution.bats:69`, `lr-handoff-launcher-quoting.bats:88-89`, `cc-tlid.bats:23-24` | **🔴 LEAKY (latent)** — every call site today passes a non-empty path, so none is *currently* firing; but nothing prevents a future/edited call, and the failure is **silent and un-erroring**. All of these write the exact observed `t` / `t@t`. |
| identity write with **no `-C`**, preceded by an **unguarded `cd`** | `gate-manifest.bats:226-227, 242-243, 259-260` (`cd "$repo"` then `git init -q; git config user.email t@t`), `operator-readout.bats:43`, `memory-nudge-budget.bats:186`, `anti-deference-nudge.bats:27`, `activation-watch.bats:225`, `task-quality-gate.bats:20/99`, `completion-assert.bats:38`, `cc-do.bats:268`, `session-writes.bats:79`, `subagent-stop-r1.bats:69`, `desk-land.bats:20`, `cc-do.bats:351` | **🔴 LEAKY** — a failed `cd` leaves cwd = the postland worktree and the write hits the shared config. `gate-manifest.bats` is the highest-value of these because it uses the **exact** `t@t`/`t` signature; the `( cd "$w"; … )` group uses `t@e.com`, which does **not** match the observed poison and so is a lower-priority (but still real) leak. |
| identity write with no `-C` and **no `cd` at all** (relies on the caller's cwd) | `land-verify.bats:15-16`, `land-gate-cas.bats:42-43`, `wrap-ledger.bats:18-19`, `gate-home-isolation.bats:38-39`, `gate-select.bats:39-40`, `ship-backup-reap.bats:26-27`, `ship-land.bats:15-16`, `stranded-sweep.bats:15-16`, `branch-reaper.bats:20/32`, `gate-manifest.bats` (above) | **⚠️ CONDITIONAL** — safe only because each `setup()` `cd`s into a fixture first. These use `tester@example.com` / `t@example.com`, again not the observed signature. |
| `git -c user.email=… ` (transient `-c`, never persisted) | `desk-assert.bats:30/32`, `git-worktree-guard.bats:17`, `cc-tlid.bats:24`, `handoff-recycle-durable-cwd.bats:55`, `handoff-fire-failed-cleanup.bats:42`, `install-stale-refusal.bats:31/32/55`, `install-worktree-refusal.bats:49/50`, `worktree-memory-link.bats:19`, `cc-dispatch-projects.bats:156`, `branch-reaper.bats:20/32` | **✅ SAFE by construction** — `-c` never writes a config file. **This is the shape everything else should be converted to.** |
| `GIT_AUTHOR_*` / `GIT_COMMITTER_*` env | `deploy-now.bats:25-26`, `deploy-live.bats:16`, `self-certifying-close.bats:30-31`, `worktree-gc.bats` (many), `cc-value`, `reap-guard.bats:15`, `cc-classify.bats:92` | **✅ SAFE** — process-scoped, never persisted. |

### C. `~/.claude` and `~/.claude-next` (dereferenced)

16 hits in `~/.claude`, 12 in `~/.claude-next` — **every one resolves to the same checkout file
already listed in §A**. There is no divergent live-layer copy carrying its own identity write.
(Confirmed with `grep -r --dereference-recursive`; a plain `grep -r` returns a false zero here.)

### D. `reso-management-app`

| Site | Class | Reason |
|---|---|---|
| `docs/research/ship-reconcile-failopen-repro.sh:17-20` — `WORK="$(mktemp -d)"; trap …; cd "${WORK}" \|\| exit 1; git init -q -b main . && git config user.email t@t && git config user.name t` | **SAFE** | `cd … \|\| exit 1` is guarded. |
| `.claude/settings.local.json:470-471, 475-476` — allowlist rows `Bash(git -C /tmp/advV/reso-management-app config user.email t@t.t)` and `…/advJ/…` | **🔴 EVIDENCE, not code** | These are *agent-typed ad-hoc commands* that were approved into the permission allowlist. They prove the operating pattern that poisons reso: an agent hand-runs `git -C "$SOMEDIR" config user.email …` inside an adversarial-repro flow. When `$SOMEDIR` is empty in that hand-written line, cwd is the reso checkout. |
| No launchd daemon, hook, or script in reso writes a git identity. | — | Census clean otherwise. |

**Reso conclusion:** reso has **no automated leaky site**. Its poisoning is best explained by an
ad-hoc agent command (the `advV`/`advJ` family above), which is consistent with the earlier
poisoning date (on/before 2026-07-29) and with the 6+ `t <t@t>` commits observed at
2026-08-05 00:52–01:31 (a dep-audit session). **Different cause, same class.**

### E. Daemons / cadence entrypoints that reach these sites

`ls ~/Library/LaunchAgents` → 45 plists. The ones that can execute corpus code:

| Plist | Cadence | Reaches |
|---|---|---|
| `com.claude.postland-verify` | `StartInterval 300` (every 5 min), `RunAtLoad false` | **the whole corpus, inside a real linked worktree** — C1 |
| `com.claude.nightly-regression` | `StartCalendarInterval 04:00` | `bats tests/` + gate/lint selftests — runs **from the repo root** (see `scripts/nightly-regression.sh`), so a cwd-collapse there hits the primary checkout directly |
| `com.claude.deploy-live` | `StartInterval 600`, `RunAtLoad true` | deploy path; reads postland stamps, no identity write |
| `com.claude.worktree-gc-infra` | periodic | excludes `~/.claude/autonomy/postland` by design (`worktree-gc-infra-run.sh:142`) — which is *why* the crashed cell `wt-run-57191` survived to be found |

`postland-verify` at a 5-minute interval and `nightly-regression` at 04:00 are both live inside the
02:00–03:45 window. `nightly-regression` at 04:00 is just outside it; **postland-verify is the only
scheduled corpus runner that provably had a cell open at 03:21.**

---

## Fixes

### Per-site (minimal, mechanical)

| Site class | Fix |
|---|---|
| `git -C "$1" config user.…` helpers (§B row 1) | `local r="${1:?mkrepo: path required}"` as the helper's first line. Under bats (no `set -u`) `${1:?}` still aborts the test — that is the point: a missing path must be **loud**, never a cwd write. |
| Unguarded `cd "$x"` before an identity write (§B row 2, incl. `gate-manifest.bats:226/242/259`) | `cd "$repo" \|\| return 1` (bats) / `\|\| exit 1` (scripts). Two files already do it right — `operator-surface-scope.bats:144` and `self-certifying-close.bats:46` use `cd "$w" \|\| exit 1`; copy that. **⚠️ NECESSARY BUT NOT SUFFICIENT — see the correction below.** |

> **Correction (2026-08-05, measured while building the agent-typed guard — `e91a371a`).** The
> `cd "$repo" || exit 1` remedy prescribed in the row above is **inert against the exact failure
> this document is about.** `cd ""` **succeeds**: rc 0, cwd unchanged (probed directly, this box,
> same git/bash as the incident). So `||` never fires and `&&` never short-circuits — the guard
> catches a *nonexistent* path and lets an *empty* one through, into the current repo, silently.
> It is still worth applying (it does catch the typo/stale-path class), but **it does not close
> the empty-variable hole and must not be recorded as having closed it.**
>
> The test that actually discriminates is the same one the tree-wide lint's rule 2 already
> states, applied to the `cd` argument as well as to `-C`: *after deleting every expansion, does
> any literal text survive?* `"$tmp/repo"` → `/repo` survives (safe). `"$x"` and `""` → nothing
> survives (refuse). `"${x:?}"` is safe by a different route — it aborts on empty rather than
> expanding to it. Any `$(…)`/backtick target is refused outright: it is computed at runtime and
> can come back empty, which is precisely the unchecked-`mktemp -d` row two lines down.
>
> **Consequence for the lint yet to be built:** rules 1–3 as written scan for the *presence* of a
> `cd … ||` guard. That predicate would mark every empty-variable site GREEN. Score the argument,
> not the guard.
| No-`cd`, no-`-C` writes (§B row 3) | Convert to `git -C "$fixture"` with a literal path segment, or better to the transient `-c user.email=… -c user.name=…` form (§B row 4), which cannot persist at all. |
| Unchecked `mktemp -d` (`telemetry-e2e.sh:141/166`, `reaper-e2e.sh`) | `V8=$(mktemp -d) \|\| exit 1` — matches the `\|\| die "mktemp"` idiom already used in `cc-bind`, `cc-teardown`, `reap-guard.sh`, `postland-verify.sh`. |
| **The amplifier — `postland-verify.sh`** | Before minting the cell, set the shared config's identity **explicitly and harmlessly for the run**, or better: export `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` and add a **post-run assertion** that `git -C "$REPO" config --local --get user.email` is still absent/unchanged, aborting the run RED if a suite mutated it. A one-line `git -C "$REPO" config --local --unset-all user.email` in the exit trap would *paper over* the leak; the assertion is what converts a silent corruption into a visible RED. |

### The one durable guard (recommended — kills the whole class)

Add `scripts/git-identity-lint.sh`, a sibling of the existing `scripts/test-hermeticity-lint.sh`
and `scripts/test-walltime-lint.sh`, wired into the **same pre-corpus whole-tree prelint slot** that
`postland-verify.sh` already runs (`runner.log` shows `prelint: scripts/test-hermeticity-lint.sh
clean (whole-tree strict)` on every run, and a red prelint **skips the corpus** — so the enforcement
chokepoint already exists and is already blocking).

It should refuse, tree-wide:

1. `git config user.(email|name)` with **no `-C`** — unless the same logical line is inside a
   `cd … || (exit|return)`-guarded group, or the file is one of a short, shrinking allowlist.
2. `git -C "$VAR" config user.` where `$VAR` is a **bare variable with no literal path segment**
   and no preceding `[ -n "$VAR" ]` / `${VAR:?}` assertion. (`"$tmp/repo"` passes; `"$1"` and
   `"$REPO"` do not.)
3. `git -C "$1"` in any function whose first line is not `${1:?…}` / `[ -n "$1" ]`.

Ratchet it the way `test-walltime-lint.sh` is ratcheted (allowlist file, count only ever decreases),
so the ~40 existing sites can be paid down without blocking today's land.

**Second, cheaper guard, worth having regardless:** a `PreToolUse` deny-rule (or a repo-local
`git` wrapper on the agents' PATH) that refuses any `git … config user.(email|name)` whose `-C`
argument is empty. That covers the *reso* half of this incident, which is not corpus code at all but
agent-typed one-liners — a corpus lint can never see those.

---

## Loose ends / what I did not prove

- **A runaway process, not just a bad line.** The single highest-value finding is operational:
  `postland-verify.sh --run-if-needed` has no wall-clock bound on `do_bisect`, so a bisect whose
  runner keeps mutating the bisected history (each step adds `a`/`b` commits, extending the range —
  see `BISECT_LOG`, where the chosen "bad" revisions are themselves subjects `b`) **never
  terminates**. `worktree-gc` excludes `~/.claude/autonomy/postland` by design
  (`worktree-gc-infra-run.sh:142`), and `WT_STALE_S=28800` (8 h) only reaps cells **on entry to a new
  run** — it cannot reap a cell whose owning process is still alive. Recommended: bound `do_bisect`
  with `timeout`, and make `git bisect start` refuse (or `bisect reset` + abort) if the range grows
  between steps.
- **I did not pin the original write to a single line.** Every `git -C "$1"` call site in the corpus
  currently passes a non-empty path, and a partial live re-run of `tests/cc-blockers.bats` inside an
  isolated clone-worktree (8 of 80 tests) left that clone's config **clean**. The convicted class is
  solid; the specific line is not, and I have not manufactured one.
- The `a`/`b` dangling commits are a **sibling session's repro**, created 2026-08-05 13:04–13:05
  while this investigation was running. `tests/cc-blockers.bats:520-524` is the only producer of
  those commit subjects in the tree, but its writes are `git -C "$D/repo"` with a literal `/repo`
  segment, which cannot collapse to `""` — so cc-blockers is **not** convicted by them.
- `~/.claude/autonomy/postland/wt-run-57191` is a **crashed cell still registered as a live
  worktree** (`.git/worktrees/wt-run-57191` present, `BISECT_RUN`/`BISECT_EXPECTED_REV` parked). It
  is excluded from `worktree-gc` by design. It is holding a stale bisect and should be pruned —
  filed here, not acted on, because this was a read-only pass.

---

## Reconciliation of the concurrent fixes (2026-08-05 16:30, backlog `c2e571188ad2`)

Five branches attacked this class within ~90 minutes. **Two of them must never land**, and the
reason is not visible from their subjects — hence this section rather than a lint rule.

### Verdict

| Branch | Verdict | Basis |
|---|---|---|
| `wt-ae2ce4298dac` (`5f1d0757`) | **LAND — strongest shape** | 21 `${1:?fn: path required}` guards at the BINDING + 17 guarded `cd`. Guards where the defect lives: helper functions that take `$1` and never checked it. |
| `fix/gi-corpus` (`159c7748`) | **DO NOT LAND AS-IS** | Real but small unique coverage; the bulk is inert-by-construction (below). |
| `fix/gi-bisect` (`2f159a7b`) | **RETIRE — landing it REGRESSES trunk** | Subsumed entirely by trunk. |
| `fix/gi-lint` (`b7f0f8bd`) | **HOLD — duplicate** | Second implementation of a lint that `wt-ae2ce4298dac` also carries (untracked `scripts/git-identity-lint.sh`). One must win; neither is landed. |
| `integ/git-identity` (`5f505ff4`) | **RETIRE — stale merge, actively misleading** | Contains **1 of `fix/gi-corpus`'s 3 commits** (`36d55cf2`; `63d83926` and `159c7748` are absent). Anyone landing it believing it is "the reconciled branch" gets the pre-fix shape. |

### Why `fix/gi-bisect` would regress trunk

Trunk's `do_bisect` (`scripts/postland-verify.sh`, via `7c32cc6f` + `0c16d12f`) already carries
everything that branch offers — the `RETURN` trap (and trunk's *self-disarms*, which the branch's
does not), the `bisect UNBOUNDED` log when no `timeout(1)` resolves, and the rc-124 culprit-parse
skip — **plus** `BISECT_MAX_STEPS`, which the branch lacks. The step cap is the bound that answers
the measured cause: the 12h41m walk was not slow steps, it was a **growing range**, and a wall bound
cannot see that. Backlog `4368b1ac7548` filed exactly this worry ("if gi-bisect lands its wall-only
version and mine is rebased away, re-add the step cap") — it is resolved in trunk's favour, so the
branch is now pure downside. All five branches are 12–21 commits behind trunk; a two-dot merge of
this one deletes 1,815 lines.

### Why `fix/gi-corpus` is not the weaker shape the backlog item describes — and still should not land

The item characterises it as guarding "at the first `-C` USE … leaving the following
`config user.email` on the bare variable". **That was true of `36d55cf2` only.** Its later two
commits added binding guards in colon form, so `mkrepo` now reads:

```bash
: "${1:?mkrepo: repo path required}"          # binding guard, first statement
mkdir -p "$1"; git -C "$1" init -q
git -C "${1:?repo path required}" config user.email t@t; git -C "$1" config user.name t
```

Measured over the 59 files both branches touch: `fix/gi-corpus` = 20 binding + 16 use-site;
`5f1d0757` = 25 binding + 0 use-site; trunk = 5 + 1. So the **downgrade risk the item flagged did
not materialise** — a conflict resolution cannot silently demote binding guards to use-site guards,
because gi-corpus guards at the binding too.

What disqualifies it is the *other* half of the item's read, which is exactly right: it is *wider*
than the census. In its 21 non-overlapping files the guarded variables **cannot be empty** —

```bash
R="$BATS_TEST_TMPDIR/main"                    # trailing literal segment
git -C "${R:?repo path required}" config user.email t@t
```

`$R` is at minimum `/main`; `${R:?}` can never fire. This is the same class the census already
acquitted (`git -C "$D/repo"`, Loose ends above). Landing ~18 such guards adds churn, protects
nothing, and — worse — teaches the shape by example while leaving the *following* `config user.name`
on the bare variable in the same line. Its genuine delta over `5f1d0757` is ~6 sites; those are
worth cherry-picking onto the binding-guard commit, not landing wholesale.

### Note on measurement

Three successive greps here returned **0 for every ref including the commit that provably has 21
guards**. The pattern missed the quote (`local r="${1:?…}"`), then missed the colon form
(`: "${1:?…}"`) — and each null read as "absent" rather than "instrument blind". Every count above
is positive-controlled (files-present + known-hit assertions). A guard census keyed on one spelling
of the guard measures the spelling, not the guard.

### `git-identity-lint.sh` cannot adjudicate any of this

It convicts the *absence* of a guard, not its *placement*, its *reachability*, or whether the
variable it guards can ever be empty. On the evidence above it would pass `integ/git-identity`
(stale), pass `fix/gi-bisect` (which regresses an unrelated bound), and reward the inert guards.
This section is the gate.

---

## Erratum — the section above drifted within 90 minutes (2026-08-06 00:30Z, backlog `80ae77910cd0`)

Backlog `80ae77910cd0` filed a correction against `c2e571188ad2` at **23:20Z**, and `c2e571188ad2`
was closed at **23:30Z** by the section above. Both were accurate when written; **four of their
statements are no longer true**, and the way each went stale is the reusable part.

Everything below is re-derived by CONTENT against `origin/main` at `7ff68f1a`. **Branch refs are
mutable and three of them moved inside this window — re-derive, do not quote this table.**

### What the correction got RIGHT (upheld)

**`c2e571188ad2` was wrong that `wt-ae2ce4298dac` landed "bisect bounds".** At `7c32cc6f~1`,
`scripts/postland-verify.sh:825` read a bare `git -C "$WORKTREE" bisect run "$runner"` — no wall,
no step cap, nothing. Trunk carries both only since today: `BISECT_TO` (line 179, via `7c32cc6f`)
and `BISECT_MAX_STEPS` (line 190, via `0c16d12f`).

The step-cap work existed **only inside auto-checkpoint commits** (`5373cc71` et al, reachable via
`git log --all -S BISECT_MAX_STEPS`), never on a real branch — so every branch-level search read 0
and `git rev-list` agreed. **The same trap is live right now for this section's own top
recommendation:** `5f1d0757` ("LAND — strongest shape") is held by `wt-ae2ce4298dac`,
`wip/ae2ce4298dac/LAST` and `checkpoints/ae2ce4298dac/*` — and `git cherry` reports it `+`, i.e.
**still unlanded**. A verdict of "LAND" is not a landing.

### The guards half: 16 of 21 landed, and the 5 that did not are the downgrade

`c2e571188ad2` says `wt-ae2ce4298dac` "LANDED the guards at the BINDING"; backlog `ae2ce4298dac`
closed on "85 corpus sites guarded … whole-tree lint reads clean — 485 files, 0 escaping identity
writes". Both are *nearly* right, and the gap is the thing this section exists to catch.

Census over the 30 files `5f1d0757` touches, classifier positive-controlled against a hand-read file
(`bin/cc-teardown`) before being trusted — binding = `local r="${1:?…}"` / `: "${1:?…}"`, use-site =
`git -C "${r:?…}"`:

| | binding | use-site |
|---|---|---|
| `5f1d0757` | 21 | 0 |
| `origin/main` | 16 | 24 |

**Five binding guards never landed.** In four of those files trunk carries the use-site shape
instead — `bin/cc-teardown`, `bin/cc-teardown-safety-gate.sh`, `tests/cc-reaper.bats`,
`tests/teammate-auto-shutdown.bats`, all reading:

```bash
local r="$1"; mkdir -p "$r"                                    # ← trunk: binding UNGUARDED
git -C "${r:?repo path required}" init -q; git -C "$r" config user.email t@t
```

That is verbatim the fragile shape `c2e571188ad2` described: protection depends on the guarded
statement running *first*, and the following `config user.email` sits on the bare variable. The
section above concluded "the downgrade risk the item flagged did not materialise" — **true of
`fix/gi-corpus`, false of trunk.** It did materialise, by the other route: the binding-shape commit
simply never landed, so nothing had to be mis-resolved.

The fifth (`tests/cc-tlid.bats`) has no guard in that helper, but it is **not** a leak — it uses
transient `git -C "$1" -c user.email=t@t commit`, not `git config user.email`, so it cannot persist
an identity into a shared `.git/config`. The lint's "0 escaping identity writes" is correct here.
Its residual risk under an empty `$1` is a junk empty commit in the caller's repo (the
`git -C "" ` no-op class), not an identity write.

**And this is exactly why "whole-tree lint reads clean" could not have caught any of it.** A clean
lint is fully compatible with 5 unlanded binding guards, because the lint convicts *absence* and
four of the five sites are not absent — they are weaker. The closing section of the reconciliation
was right in principle; this is the instance.

### What has since ROTTED

**`git-identity-lint.sh` is no longer absent from trunk.** The correction's `git ls-tree origin/main
-- scripts/git-identity-lint.sh` was genuinely empty at 23:20Z. `9313ded5` (author 21:57Z, **commit
23:43Z**) first entered `origin/main` at **23:47:58Z** — 28 minutes *after* the correction was
filed. Author date would have dated this wrong by 1h50m; the honest oracle is the `origin/main`
reflog entry that first contains the sha.

**But the half that mattered survives, sharper than "absent": the lint is wired at the wrong
chokepoint for the claim `c2e571188ad2` made.** It is a blocking **land** gate —
`scripts/ship-land.sh:1151`, `SHIP_LAND_GITID_LINT` — and it is *not* in postland's prelint band
(`scripts/postland-verify.sh:301` = `test-walltime-lint.sh` + `test-hermeticity-lint.sh` only). So
"`git-identity-lint.sh` in postland's blocking prelint slot" names a slot that still does not exist.

This makes the preceding section **more** load-bearing, not less: a reconciler landing `gi-corpus`
will now watch that lint run and PASS, and a pass is easy to misread as adjudication. It still
convicts only the *absence* of a guard — never its placement.

### What is RESOLVED (the `gi-bisect` third of `c2e571188ad2`)

`2f159a7b` was cherry-picked `-x` and landed as `7c32cc6f` (trailer verified in the commit body),
and the step cap landed as `0c16d12f`. The overlapping hunk with backlog `4368b1ac7548` no longer
exists; `fix/gi-bisect` needs no separate land.

⚠️ **The count over-reports here.** `git rev-list --count origin/main..fix/gi-bisect` = **1**, which
reads as one unlanded commit, while `git cherry origin/main fix/gi-bisect` = `- 2f159a7b` — content
fully in trunk. This repo's standing rule is "verify by CONTENT, never by count" because a count
under-reports after a sibling rebase; a cherry-pick makes the same count *over*-report. Same rule,
opposite direction, and only `git cherry` gets both right.

### Live branch state (`origin/main` = `7ff68f1a`, 2026-08-06 00:30Z)

| Branch | Live sha | vs trunk | Section above said |
|---|---|---|---|
| `wt-ae2ce4298dac` | `5f1d0757` | **UNLANDED** (`git cherry` `+`) | "LAND — strongest shape" — still true, still not done |
| `fix/gi-corpus` | `129b16b1` | ahead 4 | `159c7748` — **sha drifted** |
| `fix/gi-bisect` | `2f159a7b` | contained (count says 1) | "RETIRE" — correct |
| `fix/gi-lint` | `b7f0f8bd` | ahead 1 | "neither is landed" — **stale, one landed** |
| `fix/gi-selfexclude` | `01b52124` | ahead 0 — landed | not listed (did not exist yet) |
| `integ/git-identity` | `a25ed2e4` | ahead 0 — contained | `5f505ff4` — **stale**; that sha is a lint-hardening commit, not the stale merge described |

### Still open — unchanged by any of this

The `fix/gi-corpus` binding-vs-use-site guard-placement reconcile. `c2e571188ad2` is right that it
needs a human read and not a gate, and the lint landing does not change that.

Now joined by a smaller, sharper one: **promote the 5 unlanded binding guards** listed above.
Unlike the `gi-corpus` reconcile this is mechanical — 4 files, one line each, moving `${1:?}` from
the `-C` use-site to the `local` binding, no behaviour change when `$1` is non-empty — but it is
still someone else's un-landed branch content in a class whose whole failure mode is careless
resolution, so it is filed rather than swept in here.
