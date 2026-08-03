# The vanished pane and the unresumable session — 2026-08-02

Two independent defects, one incident. Both landed in `6a67dfe2`. Written so a successor does not
re-derive any of it; every claim below is a disk read, and the commands that produced them are here.

## The incident

The desk session `625efe2a-24b0-46b8-81df-80ca8d13d7ee` (account **next3** / `~/.claude-tertiary`,
kitty pane **218**, cwd `~/Development/claude-infrastructure`) decided at `01:07:23Z` to recycle
itself — "All green … Firing the recycle" — and ran `handoff-fire.sh --prompt-file
/tmp/fire-setup-token-v2.txt --recycle`. At `01:08:20Z` the teardown marker was written and the
session was killed. **No successor ever appeared.** The operator saw a pane vanish, opened a new one
by hand (pane 234, account 1), and typed the resume hint Claude itself had printed:

```
claude --resume 625efe2a-24b0-46b8-81df-80ca8d13d7ee
→ No conversation found with session ID: 625efe2a-24b0-46b8-81df-80ca8d13d7ee
```

Both halves of that sentence were false. The session had not crashed, and the conversation existed.

## Defect 1 — the recycle killed a pane it could no longer reach

`--recycle` is exit-and-relaunch *in the same pane*: handoff-fire composes a shell command line and a
detached watcher types it once `claude` exits. All of that worked. The composed line, recovered from
`${TMPDIR}/handoff-recycle-cmd-218-1785719299-JDEsX1.sh`:

```
cd /Users/chrisren/Development/claude-infrastructure && nocorrect CLAUDE_ISOLATION_SKIP=1 \
  claude3 "$(cat ${TMPDIR}/handoff-prompt-nb-bVz0BS)"
```

Right account (`claude3` = next3), right cwd, payload attached and marker-stamped. What failed was the
typing. From `${TMPDIR}/handoff-recycle-218-1785719299-2f5JJP.log`:

```
→ armed: __recycle pid=59714 pgid=59714 sid=218 tty=/dev/ttys005
→ claude exited after 6s — typing relaunch
!! it2 relaunch write failed twice — run manually in the pane: …
```

**Cause.** `detach()` spawns the watcher with `start_new_session=True`, so it reparents to launchd *by
construction*. `bin/cc-in-kitty` discriminates on **ancestry**, not on the `KITTY_*` env vars — and
that is correct, because those vars inherit transitively into iTerm2 and a naive env test makes the
divert fire in the wrong terminal. But an orphan has no kitty ancestor to find, so for the watcher the
walk can only ever answer "not kitty". Every pane write was routed to the real iTerm2 CLI and died
against a kitty pane id. The watcher was not misconfigured; it was structurally unable to re-derive a
fact the foreground could still see.

**Scope — systemic, not a one-off.** Every real recycle since the kitty migration fails identically:

| watcher log | pane | launcher | verdict |
|---|---|---|---|
| `handoff-recycle-176-1785659296` | 176 | `claude4` | write failed twice |
| `handoff-recycle-2-1785669744`   | 2   | `claude2` | write failed twice |
| `handoff-recycle-173-1785695807` | 173 | `claude4` | write failed twice |
| `handoff-recycle-218-1785719299` | 218 | `claude3` | write failed twice |

Corroborated independently by the teardown store: `~/.claude/watchdog/teardown/` holds **63 `recycle`
records against 14 `successor` records**, and every `successor` record carries an iTerm2 UUID pane —
the newest dated `2026-07-30T01:28:24Z`, the day before the machine moved to kitty. Ten recycles since
then, zero successors.

**Fix (two parts, `scripts/handoff-fire.sh`).**

1. `pin_term_verdict_for_watcher` — resolve the terminal in the FOREGROUND, where the ancestry walk is
   valid, and hand the verdict down through `cc-in-kitty`'s own documented `CC_TERM` seam. Definitive
   verdicts only; exit 2 (UNVERIFIABLE) pins nothing, so the watcher keeps its fail-closed default
   rather than inheriting a guess. This is *not* the rc-block export that `cc-in-kitty`'s header
   forbids: that caches a verdict into every process on the box forever, this hands a just-measured
   one to a single short-lived child whose lineage we deliberately destroyed.
2. `pane_proof` / `await_pane_proof` — the arm handshake proved only that the watcher could write its
   own **log**. It now must also prove it can reach the **pane**, over the real transport
   (`session list` through the same shim the write will take), *before* anything is killed.

**The class, stated so it outlives this instance:** kill-first-discover-second. `await_armed` was a
liveness proof for the wrong subject. Any irreversible act gated on a proxy must gate on the actual
actuator instead — and the proxy here was not merely weak, it was *independent* of the thing that
failed.

## Defect 2 — resume reported a live session as absent

The transcript was intact the entire time: **8.6 MB, 1411 records**, at
`~/.claude-tertiary/projects/-Users-chrisren-Development-claude-infrastructure/625efe2a-….jsonl`.

A session id resolves only under `$CLAUDE_CONFIG_DIR/projects/<hash-of-cwd>/`, and on this machine
both halves are ambient (4 accounts × per-worktree project dirs). `lib/cc-resume-shell.sh` exists
precisely to fix that — `_cc_resume_pin` resolves the id and redirects the launcher. It works; run
now it returns `CC_RESUME_CFG=/Users/chrisren/.claude-tertiary` for this very id.

**It never ran.** `~/.zshrc` sources the lib behind `[[ -f … ]]`, an existence test evaluated **once**,
at shell start. The symlink `~/.claude/lib/cc-resume-shell.sh` was born `12:06:27`; pane 218's shell
started before `11:53:38`. The consumer then guards on `typeset -f`, which is **fail-open** — so the
capability did not fail, it silently degraded to the stock behaviour it was written to replace.

**Fix.** `_cc_lib <func> <libfile>` re-sources at USE time and returns whether the function is
genuinely in scope. Both libs are pure definitions, so it is free, idempotent, and it also repairs the
stale-**body** half of the class rather than only the absent-function half. Live in `~/.zshrc`; shipped
in `settings-templates/zshrc-snippet.sh`.

**Honest limit.** This covers everything under `~/.claude/lib/`, which is where the failure was and
where new capability lands. It does **not** cover launcher bodies defined inline in `~/.zshrc` — a pane
older than an rc edit still runs the old `claude()`. Closing that needs the launchers to become PATH
scripts; the evidence says that is possible (the launcher already `cd`s in a subshell and passes the
config dir as a per-command env var, so nothing actually requires a function), but it relocates ~50 rc
lines and is a larger change than this class currently earns.

## How to resume 625efe2a

From a shell started **after** `2026-08-02 12:06:27` (any new pane), the plain hint now works —
`_cc_lib` loads the pin, which redirects to `~/.claude-tertiary` and to the session's birth cwd:

```
claude --resume 625efe2a-24b0-46b8-81df-80ca8d13d7ee
```

An older pane needs `exec zsh` first. The escape hatch if the resolver is ever wrong:
`CLAUDE_CONFIG_DIR=$HOME/.claude-tertiary claude --resume <id>` from
`~/Development/claude-infrastructure`.

**What that session was carrying,** for anyone who would rather continue the work than the context:
the setup-token v2 thread, backlog `170a3b38f8c9`, with its full recycle payload preserved at
`/tmp/recycle-setup-token.txt`. Nothing was lost — its `auth-timeseries` sampler *survived* the kill
(detached, still writing) and still covers the next3/next4 credential-expiry proof window; `dd02f7df`
is on trunk by content; all four `.oauth_refresh.lock` paths are absent, so the dangling-lock fix is
intact.

## Live proof — the orphan repro, and the two ways it can lie to you

Run on the deployed layer after the deploy below. It reproduces the exact failure and then shows the
fix closing it, using the **real** function out of the live script rather than a paraphrase:

```bash
eval "$(sed -n '/^pin_term_verdict_for_watcher() {/,/^}/p' ~/.claude/scripts/handoff-fire.sh)"
pin_term_verdict_for_watcher            # foreground: ancestry walk valid → CC_TERM=kitty
# then spawn a child with start_new_session=True, let the spawner EXIT, and have the child
# sleep before probing (see /tmp/probe3.sh in the session that wrote this)
```

| condition | `ppid` | `cc-in-kitty` | `it2 session list` | pane reachable |
|---|---|---|---|---|
| orphan, no `CC_TERM` (**the bug**) | 1 | rc 1 — *"INHERITED, not ours"* | iTerm2 error, 0 lines | **no** |
| orphan, `CC_TERM` pinned (**the fix**) | 1 | rc 0 — *"explicit override"* | kitty, pane present | **yes** |

**Two traps, both of which produced a false result before the true one.** They are the reason this
section exists at all:

1. **A no-delay repro proves nothing.** The first attempt used `Popen(...).communicate()`, which keeps
   the spawner alive — so the child's parent was still a kitty descendant and the ancestry walk
   *succeeded*. It reported "reachable" for both arms, i.e. it failed to reproduce a bug that is
   sitting right there in four production logs. The child must outlive its spawner before it is an
   orphan at all.
2. **A hand-rolled control can be the broken thing.** The second attempt built its own environment in
   Python and did not actually propagate `CC_TERM` to the child, so the fixed arm looked *inert* —
   momentarily indicting a fix that was fine. Replaying the **real** artifact (`sed`-extract the live
   function, run it, inherit its env) is what separated the two. A control that cannot fail the same
   way the subject fails is not a control.

## Landed ≠ live (read this before assuming the fix is in effect)

`~/.claude/scripts/handoff-fire.sh` is a symlink into the **shared checkout's working tree**, not into
trunk. A land therefore does nothing for running sessions until the live layer advances.

**The deploy lane was deadlocked, and the cause was not the gate.** `deploy-live.sh --force` — which
skips the green-stamp walk entirely — still refused:

```
deploy-live: REFUSED — target dd88bc68d030 is not a descendant of live HEAD 0824716f65e7
             — this would ROLL BACK the live layer
```

The shared checkout's `main` carried **`0824716f`** (`perf(kitty): throttle redraws at high pane
count`, `config/kitty.conf` +25), committed straight onto it at 13:06 on 2026-08-02 and never landed.
Trunk and the live layer had **diverged**, so every advance in either lane read as a rollback. That is
why the gated lane looked like a stamp problem for days: a green stamp would not have helped either.

**Resolution.** Cherry-pick the stranded commit onto trunk (`dec053fb`, `-x`), confirm `git cherry
origin/main HEAD` reports `-` (upstream by patch-id, so the checkout's copy is a pure duplicate), then
reset the checkout to trunk and deploy. Both discarded objects were verified already-on-trunk first —
`0824716f` (`git diff dec053fb` = 0 lines) and the dirty `lib/config-mirror.zsh` (`git diff
origin/main` = 0 lines). Live is now byte-identical to trunk, `0 ahead / 0 behind`, clean.

**The generalisable lesson:** a *single* unlanded commit in the shared checkout silently disables the
deploy lane for the whole machine. It does not announce itself as a divergence — it announces itself
as a rollback refusal, and (in the gated lane) as a missing green stamp. `git cherry origin/main HEAD`
is the one-line diagnostic; a `+` there means the live layer cannot advance no matter what the
verifier says.

The persistent trunk-red is a **separate, still-open** condition — `cc-blockers` reports
`newest 5 all red, 1 green of 63 ever`. None of the twelve suites in those stamps touches anything in
`acbaba85`/`6a67dfe2`, and one (`tests/desk-recycle-durable.bats`) ran **green** directly at trunk this
session, so the red predates this diff and excludes it. Until it converges, the deploy lane needs
`--force` on every advance.

```
# what the deploy lane is waiting on
cc-blockers
git -C ~/Development/claude-infrastructure cherry origin/main HEAD    # '+' ⇒ divergence, lane dead
jq -r --arg v red 'select(.verdict==$v).failing[]?' ~/.claude/autonomy/postland/stamps/*.json \
  | sort | uniq -c | sort -rn
```

## Verification

`tests/handoff-fire-pane-proof.bats` — 10/10 GREEN against the fixed subject, 10/10 RED against
`origin/main`'s pre-fix copy. 125 neighbouring handoff/recycle tests green.

Two vacuity traps were hit and are worth repeating, because both produce a *passing* test that proves
nothing:

- The suite's own positive control passed against pre-fix code, which emits **neither** log line —
  written affirmative-first, only its final assertion decided the verdict. The decisive assertion must
  go **last**. The repo's own `bats-assert-liveness` ratchet then flagged five more of the same shape;
  `scripts/bats-assert-liveness-fix.py` is the sanctioned repair.
- The suite caught a real defect in the fix before it shipped: a bare `"$cik"` under
  `set -euo pipefail` would have aborted handoff-fire outright on the **iTerm2** path, because
  `cc-in-kitty`'s normal answer for "not kitty" is exit 1 — a probe whose honest negative verdict kills
  its caller.
