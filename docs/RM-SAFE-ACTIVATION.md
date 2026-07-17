# rm-safe-allowlist — ACTIVATION runbook (C10: human-only)

The build is **complete, tested, and landed**: `hooks/rm-safe-allowlist.sh` is a deterministic
PreToolUse(Bash) hook that auto-allows `rm` of regenerable within-tree targets, with a 44-case
matrix + `tests/rm-safe-allowlist.bats` (10 tests, all green) pinning both directions. What
remains is **activation** — registering the hook in the five `settings.json` permission files —
**which is C10 (human-only)**: an agent must never edit the settings that govern its own
permissions. The agent built + tested + wrote this runbook + `docs/activation/rm-safe-activate.sh`;
**the operator runs it.** The agent NEVER edits any `settings.json` in place.

## What it fixes

The static `Bash(rm:*)` rule sits in the **`ask`** array of all 5 settings.json, so *every* `rm`
prompts — empirically ~21×/build on `rm -rf artifacts/`, the single biggest halt to 24/7
autonomous work (`docs/L3-L4-AUTONOMY-ROADMAP.md` §1). A PreToolUse `allow` decision overrides the
`ask` for provably-safe targets; unsafe `rm`s still fall through to the prompt.

## What gets activated

| Primitive | File | Activation act | Blast radius |
|---|---|---|---|
| the hook script | `hooks/rm-safe-allowlist.sh` | symlink into `~/.claude/hooks/` (install.sh also does this) | one file, reversible |
| registration | 5× `settings.json` | append the hook to the PreToolUse **Bash** matcher's `hooks` array | +1 array element/file; `ask` rule untouched |

## Safety model (why this is safe to auto-allow)

Allow is **opt-in to a whitelist**, never opt-out. The hook emits `allow` ONLY when **every**
target is a regenerable build/cache/artifact dir (or a path within one) — relative, no `..`, no
glob, no `~`, no bare `/` — **or** an absolute path strictly under `/tmp` / `/private/tmp`.
Everything else (a `.git` dir, `~`, `/`, any outside-repo absolute path, any non-whitelisted name)
gets **no decision** → the existing `ask` prompt still fires. It also re-checks the catastrophic
DANGER_PATTERNS (`rm -rf /`, `sudo rm`, fork bomb) and defers on match. Kill switch:
`RM_SAFE_ALLOWLIST_DISABLED=1`.

## Activation

```sh
# 1. DRY-RUN first — shows exactly which files would change, validates the transform, writes nothing:
./docs/activation/rm-safe-activate.sh

# 2. APPLY — backs up every file (*.bak-<ts>), transforms via jq to a temp, validates JSON, then mv:
./docs/activation/rm-safe-activate.sh --apply
```

The script is **idempotent** (re-runs report "already registered", never double-insert) and
**structural** (locates the Bash matcher via jq, never by line number — settings byte-sizes differ
per account). Verified against copies of all 5 real settings.json: only the rm hook is added;
everything outside `PreToolUse` is byte-identical.

## Verify after activation

```sh
# hook decides allow for a safe target:
printf '{"tool_input":{"command":"rm -rf artifacts"}}' | ~/.claude/hooks/rm-safe-allowlist.sh
#   → {"hookSpecificOutput":{...,"permissionDecision":"allow",...}}

# hook stays SILENT (defers to the prompt) for an unsafe target:
printf '{"tool_input":{"command":"rm -rf .git"}}' | ~/.claude/hooks/rm-safe-allowlist.sh   # → (no output)

# full regression:
bats tests/rm-safe-allowlist.bats     # 10 tests, all pass

# registered in every settings.json:
for d in ~/.claude ~/.claude-secondary ~/.claude-next ~/.claude-tertiary ~/.claude-quaternary; do
  jq -e '[.hooks.PreToolUse[]?|select(.matcher=="Bash").hooks[]?|.command]|index("~/.claude/hooks/rm-safe-allowlist.sh")!=null' "$d/settings.json" >/dev/null && echo "ok $d" || echo "MISSING $d"
done
```

## Rollback

The apply run prints exact `mv` commands to restore each `*.bak-<ts>`. Nothing destructive: the
hook script stays on trunk; removing the registration (or restoring the backup) fully reverts.
Or set `RM_SAFE_ALLOWLIST_DISABLED=1` in the environment to disable the hook without unwiring.
