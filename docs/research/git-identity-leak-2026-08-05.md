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
| Unguarded `cd "$x"` before an identity write (§B row 2, incl. `gate-manifest.bats:226/242/259`) | `cd "$repo" \|\| return 1` (bats) / `\|\| exit 1` (scripts). Two files already do it right — `operator-surface-scope.bats:144` and `self-certifying-close.bats:46` use `cd "$w" \|\| exit 1`; copy that. |
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
