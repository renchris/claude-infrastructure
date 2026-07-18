# Mission-Ledger Activation Snippets

Wiring lines for the desk mission-ledger (Program D substrate). **Operator-applied** —
C10 authority ceiling: this repo BUILDS + TESTS the machinery and documents the one-line
activation; the operator wires it into live `~/.claude/settings.json`. Nothing here edits
live config.

Assumes hooks are installed at `~/.claude/hooks/` and bins at `~/.claude/bin/` (the repo is
byte-in-sync with `~/.claude` per the p14 audit).

---

## 1. Plan-index reconcile at SessionStart (Task 1 / G-P14-3)

Rebuild `~/.claude/plans-index.json` from disk truth every session start: prunes phantom
entries (file-missing ⇒ drop), adds on-disk plans, refreshes `generated`. Idempotent and
fast (bounded `find -maxdepth 1` over the plan dirs).

Add to the `hooks.SessionStart` array in `~/.claude/settings.json`:

```json
{ "type": "command", "command": "$HOME/.claude/hooks/plan-index-update.sh reconcile" }
```

One-shot from a shell (manual reconcile / cron):

```bash
~/.claude/hooks/plan-index-update.sh reconcile
```

The PostToolUse indexer half needs no new wiring — it is the existing
`plan-index-update.sh` PostToolUse:Write|Edit hook, now covering `*/docs/plans/*.md` and
`*/.claude-plans/*.md` in addition to `~/.claude/plans`.

---

## 2. Truthful SessionStart plan counts (Task 2 / G-P14-1)

**No new wiring** — `setup-plan-symlinks.sh` is already a SessionStart hook. It now emits
`Plans: <open>/<total> open for <project> · <total> all` from real disk + index reads
(was the "Plans: 0" lie). For the count to be trustworthy the index must be fresh, so keep
the §1 reconcile line ahead of it in the SessionStart array.

---
