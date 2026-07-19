# ship-rail-push-allow — ACTIVATION runbook (C10: human-only)

The build is **complete, tested, and landed**: `hooks/ship-rail-push-allow.sh` is a deterministic
PreToolUse(Bash) hook that auto-allows the ONE ship-rail land push shape
(`git push origin HEAD:<branch>`, non-force), with `tests/ship-rail-push-allow.bats` (8 tests, all
green) pinning both directions. What remains is **activation** — registering the hook in the five
`settings.json` permission files — **which is C10 (human-only)**: an agent must never edit the
settings that govern its own permissions. The agent built + tested + wrote this runbook +
`docs/activation/ship-rail-push-activate.sh`; **the operator runs it.** The agent NEVER edits any
`settings.json` in place.

This is **Operator decision point #4** in `docs/plans/ORCHESTRATOR_DESK_24X7_PLAN.md`
("Ask-narrowing scope (T-P15-4): sanction the ship-rail-only push allow"). Sanctioning = running the
activation below.

## What it fixes (T-P15-4 / G-P15-3)

`defaultMode: auto` still HALTS on the `ask` array, and `Bash(git push:*)` sits there — so a
**model-issued land push strands** with no human to approve (the page is unconfigured; the prompt
blocks the turn). A PreToolUse `allow` decision overrides the `ask` for the exact non-force land
shape; every other push still prompts. The doctrine is *"land is autonomous-at-green"* — this
**UNBLOCKS** ship, it never re-blocks it.

### U2 resolved — why the infra rail did NOT already strand, and where the strand actually is

The desk-audit left **U2** open: *does the autonomous ship path escape the `git push:*` ask?* It
does — but for a reason that pinpoints the real gap. `scripts/ship-land.sh:186` runs
`git push origin HEAD:<trunk>` as a **subprocess** (a non-Bash-tool path), so the permission system
never sees it (confirmed by recent `tool:ship-land` lands in `~/.claude/land.log` completing
`exit 0` unattended). The strand is the **model-issued** land push — `commands/ship.md:43` ("on
trunk directly → `git push origin HEAD:<trunk>`", and the rebased-feature-branch fast-forward land) —
which *does* surface as a Bash tool call and hits the `ask`. This hook covers exactly that call.

### Complement to `smart-bash-allowlist.sh`, not a duplicate

`hooks/smart-bash-allowlist.sh` already allows `git push origin <feature>` but **deliberately
EXCLUDES** main/master/develop/production/prod/release (line ~118) — so the land-to-trunk push has
**no allow path**. This hook fills that one gap with the tightest possible shape: `HEAD:<branch>`,
non-force, origin-only. (`smart-bash-allowlist.sh` is itself currently unwired; this hook stands
alone and does not depend on it.)

## What gets activated

| Primitive | File | Activation act | Blast radius |
|---|---|---|---|
| the hook script | `hooks/ship-rail-push-allow.sh` | symlink into `~/.claude/hooks/` (install.sh also does this) | one file, reversible |
| registration | 5× `settings.json` | append the hook to the PreToolUse **Bash** matcher's `hooks` array | +1 array element/file; `ask` rule + force `deny` untouched |

## Safety model (why this is safe to auto-allow)

Allow is **opt-in to one shape**, never opt-out. The hook emits `allow` ONLY for the exact simple
command `git push origin HEAD:<branch>` — one remote (`origin`), the `HEAD:<ref>` land refspec, a
safe branch name (`[A-Za-z0-9][A-Za-z0-9._/-]*`, no `..`), **no flags, no force**. A non-force push
**cannot rewrite trunk history** — a non-fast-forward is rejected by the server (`ship-land.sh`
exit 7) — so the blast radius is "advance a ref you can already fast-forward", which is precisely the
land. Everything else — force in any form (`--force`, `-f`, `--force-with-lease`, a `+HEAD:`
refspec, `--mirror`, `--delete`), a non-`origin` remote, a bare `git push`, `-u`/`--set-upstream`,
or ANY compound / substitution / redirection — gets **no decision** → the existing `ask` prompt
still fires, and the `Bash(git push --force:*)` / `Bash(git push -f:*)` **deny** rules stay in
force. Kill switch: `SHIP_RAIL_PUSH_ALLOW_DISABLED=1`.

## Activation

```sh
# 1. DRY-RUN first — shows exactly which files would change, validates the transform, writes nothing:
./docs/activation/ship-rail-push-activate.sh

# 2. APPLY — backs up every file (*.bak-<ts>), transforms via jq to a temp, validates JSON, then mv:
./docs/activation/ship-rail-push-activate.sh --apply
```

The script is **idempotent** (re-runs report "already registered", never double-insert) and
**structural** (locates the Bash matcher via jq, never by line number — settings byte-sizes differ
per account). Only the ship-rail-push hook is added; everything outside `PreToolUse` is byte-identical.

## Verify after activation

```sh
# hook decides allow for the land shape:
printf '{"tool_input":{"command":"git push origin HEAD:main"}}' | ~/.claude/hooks/ship-rail-push-allow.sh
#   → {"hookSpecificOutput":{...,"permissionDecision":"allow",...}}

# hook stays SILENT (defers to the prompt) for force / bare / other-remote pushes:
printf '{"tool_input":{"command":"git push --force origin HEAD:main"}}' | ~/.claude/hooks/ship-rail-push-allow.sh  # → (no output)
printf '{"tool_input":{"command":"git push"}}'                          | ~/.claude/hooks/ship-rail-push-allow.sh  # → (no output)

# full regression:
bats tests/ship-rail-push-allow.bats     # 8 tests, all pass

# registered in every settings.json:
for d in ~/.claude ~/.claude-secondary ~/.claude-next ~/.claude-tertiary ~/.claude-quaternary; do
  jq -e '[.hooks.PreToolUse[]?|select(.matcher=="Bash").hooks[]?|.command]|index("~/.claude/hooks/ship-rail-push-allow.sh")!=null' "$d/settings.json" >/dev/null && echo "ok $d" || echo "MISSING $d"
done
```

## Rollback

The apply run prints exact `mv` commands to restore each `*.bak-<ts>`. Nothing destructive: the hook
script stays on trunk; removing the registration (or restoring the backup) fully reverts. Or set
`SHIP_RAIL_PUSH_ALLOW_DISABLED=1` in the environment to disable the hook without unwiring.
