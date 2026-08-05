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

## The remaining question — WHO removes it

Unproven. Do not guess; the previous two rounds of guessing both cost a landed claim.

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
