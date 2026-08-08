# cc-registry: a fired peer's row IS written, then removed ~1s later (2026-08-05)

Measurement note for backlog item `1b0b5d2f1712`. It exists to **correct a claim landed in
`4cd1d2e4`'s own commit message**, which said `register()` "returns BEFORE its write (no orphaned
.tmp)". Direct observation refutes that. The orphan-gate fix in that commit stands — it is
independent of this mechanism — but the residue item must not start from the wrong premise.

## What was observed

A 150 ms-resolution transition watcher over `~/.claude/cc-registry` caught a full firing cycle on
pane 99 (worktree `wt-eafe3e78a852`, account claude-quaternary):

```
14:54:02        claude starts on pane 99 (pid 96052)
14:54:04.169  > 99.json = FULL   pid=96052 sid=049a6470   ← session-register.sh register() WROTE it
14:54:05.324  < 99.json          (gone)                   ← REMOVED 1.155 s later
14:54:54.428  > 99.json = PROV                            ← ensure_registration's 30 s fallback
~15:0x        > 99.json = FULL   (ms-precision startedAt) ← cc-reconcile healed it
```

pid 96052 was still alive at the time of writing, so the removal did **not** accompany the death of
the session that owned the row.

## What this establishes

- `register()` **does** write the row, promptly (~2 s after process start). The
  "returns before its write" inference in `4cd1d2e4` was wrong; it was drawn from the *absence* of
  an orphaned `.$pane.$$.tmp`, which is equally consistent with a **successful** write (the `mv`
  consumes the tmp) — a null from an instrument blind to the failure is not absence.
- The provisional row is therefore not evidence that registration failed. It is evidence that the
  row was **deleted inside `ensure_registration`'s 30 s poll window** (`handoff-fire.sh:1416-1420`
  tests file existence only, so a row that exists and then vanishes reads identically to one that
  never appeared).
- The earlier account correlation (all `register()`-written rows on claude-next, all
  provisional/backfilled ones on the other three) is a **confound for spawn mode**, not a property
  of the account: the desk fires peers on accounts 2/3/4 and runs its own sessions on claude-next.

## WHO removes it — RESOLVED 2026-08-05 (`0d675779`, `64b655be`)

**`claude mcp list`, fired by `hooks/session-start.sh:63` on every SessionStart, emits a SessionEnd
of its own.** Reason `"other"`, a fresh random `session_id`, and **no matching SessionStart** — while
inheriting the live pane's `CC_PANE_ID`/`ITERM_SESSION_ID` from the hook's environment.
`session-deregister.sh` then removed that pane's row, which by construction can never be the
phantom's own. It is 3 phantoms per start, not 1, whenever no MCP server reports `Connected` — the
retry loop runs the probe `MAX_ATTEMPTS` times.

Three independent measurements, none of them inference:

1. **The event exists.** A throwaway `CLAUDE_CONFIG_DIR` wiring nothing but a tracer on SessionEnd,
   then `claude mcp list`: one `SessionEnd` record, `reason:"other"`, sid `17b8b21f…`, `$PPID`'s
   command literally `claude mcp list`, `CC_PANE_ID` = the inherited pane. Zero SessionStart records.
2. **It removes a live row.** Same probe against the **deployed** `~/.claude/hooks/session-deregister.sh`
   with `CC_REGISTRY_DIR` fixtured and a row owned by `OWNER-SID-1111`: the row is gone after
   `claude mcp list` returns.
3. **The population agrees.** `session-start.sh` logs `Session started` then `MCP Status (attempt 1)`
   around the probe; `session-end.sh` logs `Session ended`. In `~/.claude/logs/sessions.log`,
   **5360 of 6208** `MCP Status (attempt 1)` lines are *immediately preceded* by a `Session ended`
   line — including at `14:54:05`, the second the pane-99 row vanished, with only ONE `Session
   started` in that cycle.

This also explains the repro note below: the trigger "lives in the chain" because the chain is what
contains the `claude` invocation — `session-start.sh:63` is the only one in any hook. A single-hook
harness has no phantom to see.

Fixed on both sides. `0d675779` — `session-deregister.sh` removes only on a proven tenancy match
(both sids present and equal); every unprovable case keeps the row, because a wrongly-kept row is a
dead row that `cc-sessions`/`cc-reconcile` already sweep on `kill -0`, while a wrongly-removed row
erases a live pane from the fleet's only addressing table. `64b655be` — `session-start.sh` runs the
probe under `env -u CC_PANE_ID -u ITERM_SESSION_ID`, so the phantom still fires but arrives
**paneless** and every pane-keyed SessionEnd consumer no-ops at its own gate, including ones not
written yet. `tests/session-registry.bats` carries the phantom's verbatim event shape; that test and
three sibling tenancy cases are RED against the pre-fix hook.

### The reasoning that was open before the measurement

Kept as written — it named the right suspect for the right reason, and the "not a defendant" caveat
was correct: the mechanism that fires the SessionEnd was still missing.

The only unconditional remover in the tree is `hooks/session-deregister.sh:25`:

```bash
pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; pane="${pane##*:}"
rm -f "$reg_dir/$pane.json" 2>/dev/null
```

It removes the pane's row **without checking the row belongs to the session that is ending** — no
`session_id` comparison. Its sibling `hooks/live-session-registry.sh:36-37`, written against the
same hazard, *does* compare before removing:

```bash
have=$(cut -f2 "$REG_DIR/$base" 2>/dev/null)
{ [ -z "$sid" ] || [ "$have" = "$sid" ]; } && rm -f "$REG_DIR/$base"
```

That asymmetry is the strongest candidate (a pane id is not a tenancy — `7c049231`), but a
SessionEnd firing ~1 s after a SessionStart on a *live* pane has not been demonstrated, and until
it is, `session-deregister.sh` is a suspect and not a defendant.

Ruled out by evidence, not by reasoning:

- **the `cc-sessions` stale sweep** — it *renames* to `.stale-<ts>`; no `.stale-*` file exists for
  any affected pane (only pane 48, from 2026-08-01).
- **`lead-crash-watchdog.sh:327`** — its `rm -f "$tdir/$pane.json"` targets the teardown-marker dir,
  not the registry; the registry is only ever read there.
- **`cc-reconcile`** — it heals and prunes, and its log accounts for every row it touched; it never
  ran in the 1.155 s window.

## How to reproduce cheaply

`claude -p "say ok"` on an account carrying the full 14-hook SessionStart chain, with the watcher
running. Note that the same hook, with the same stdin and env, invoked as the **only** SessionStart
hook in a throwaway `CLAUDE_CONFIG_DIR`, writes the row and it *survives* — so the trigger lives in
the chain, and a single-hook harness cannot see it. Any bisect of the 13 siblings must fixture the
ones with side effects (`mailbox-drain` consumes mail; `dod-persist` and `session-index-start`
write state).

## Why it matters while open

Between the removal and cc-reconcile's next pass (~6 min cadence; measured 45 s–3.4 min end to end)
the pane has no addressable row: `cc-notify` cannot reach it, `cc-board` reads it absent, and
`cc-backlog`'s `claimer_live` can answer PROVEN NOT-LIVE for a session-keyed claim held by a
perfectly healthy worker — a false death. The self-close orphan gate is no longer affected: as of
`4cd1d2e4` it resolves the sid from Claude Code's own per-pid registry when the row cannot answer.

## The WRITE side — same mechanism, other direction (2026-08-08, backlog `55e1e65c7548`)

Everything above is about a phantom **removing** a row. A child session can also **overwrite** one,
and that half had no gate at all. `register()` wrote `$pane.json` keyed on
`${CC_PANE_ID:-$ITERM_SESSION_ID}` — inherited by every child process — so any nested `claude`
firing a SessionStart replaced the tenant's row with its own pid and session_id, and that pid was
dead within seconds.

Three measurements, escalating:

1. **The hook has no tenancy gate.** Fixtured `CC_REGISTRY_DIR`, incumbent row owned by a live
   foreign pid: overwritten, no condition consulted.
2. **A real headless child does it end to end.** One `claude -p` fired from inside a live session,
   throwaway `CLAUDE_CONFIG_DIR` wiring only `session-register.sh`: pane 841 went from
   (pid 82949, `PARENT-SID-0001`) to (pid 38739, the child's sid), and 38739 was dead when the probe
   returned while 82949 ran throughout. **The child exited on "Not logged in" — it never reached the
   model.** So this is not cost-gated the way `d246307ff1e1` (the upgrade gate's throwaway sessions)
   suggested: invoking the CLI at all is enough, from any script that shells out to it.
3. **The same probe against the fixed hook leaves the row untouched** and journals
   `disposition:"refused"` naming ancestor pid 82949.

`hooks/live-session-registry.sh` had the identical defect one key over — it registers on the
session's **cwd**, equally inherited (measured: row pid 94327 → 94337, dead). That row is worse to
lose, because `worktree-gc.sh:361-372` `registry_live()` is a POSITIVE proof with nothing behind it:
a dead pid drops the worktree back to the cwd/lsof oracle that file's header exists to replace
("live `claude` procs routinely report cwd=/ … a single bad pass made a LIVE session's worktree look
dead and it was reaped"). One throwaway probe disarms the reap guard for the session that fired it.

**The remedy is ancestry, not liveness.** Both gates refuse only when the row's owning pid is a live
**ancestor** of the registering process — a nested claude got the pane id (or the cwd) by inheriting
it from the process that owns it, so ancestry *is* the proof the row is not ours. The cheaper "the
incumbent is live and is a claude" test was rejected because it convicts on pid REUSE (wedging a
pane forever) and on pane REUSE (a `--recycle` overlap would refuse the incoming tenant and leave
the pane holding a row about to become a corpse — this very bug, re-created by its own fix). Both
suites pin those two cases as controls that must still WRITE.

### A denominator note, because the first census was wrong

Asking "would this gate refuse anything legitimate?" was answered twice. A `ps -eo command=` grep for
`node_modules/.bin/claude` reported **25 of 50** live claude processes nested inside another — which
would have made the gate look catastrophic. That population is fiction: it counts wrappers such as
`bash ~/.claude/bin/cc-close-attrib …/claude …`, whose argv contains the path but whose `comm` is
`bash`. The gates match on `ps -o comm=`, exactly as `claude_ancestor_pid()` always has. Re-run with
the subject's own predicate: **27 live claude processes, 0 nested.** The refusal population is the
transient probes and nothing else. (memory: positive-control-the-denominator.)
