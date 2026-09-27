# A symlinked auto-memory dir prompts on every write — only `autoMemoryDirectory` clears it

**2026-09-24.** Measured on Claude Code 2.1.280. Fixed in `bin/cc-close-attrib`.

## Symptom

On `.claude-next`, `-secondary`, `-tertiary` and `-quaternary`, every write to the session's
auto-memory dir raised a permission prompt — one auto mode cannot approve. `~/.claude` itself
was unaffected.

## Cause

The auto-memory dir on those accounts is reached through a symlink into `~/.claude/projects/`:
`~/.claude-next/projects` is a whole-dir symlink, and on the other three each
`projects/<slug>/memory` is. CC's write carve-out ("auto memory files are allowed for writing")
matches the path **as spelled**. Its symlink landing check then resolves the real target, finds
it outside the working dirs, and raises `safetyCheck` with `classifierApprovable:false`. The
headless error names it directly: *"… resolves through a symlink to
/Users/chrisren/.claude/projects/…/memory/probe-off.md, which is outside the allowed working
directories."*

## What does not clear it (headless probes, `claude.exe -p`, haiku, `CLAUDE_CONFIG_DIR=~/.claude-next`)

- allow rule `Write(//Users/chrisren/.claude/projects/**)`: still denied
- `--add-dir ~/.claude/projects`: still denied
- a PreToolUse hook returning `permissionDecision: allow`: still denied. A safetyCheck
  outranks a hook allow.

## What clears it

`--settings '{"autoMemoryDirectory":"<the REAL path>"}'`. The carve-out then matches the
resolved path and the symlink check has nothing to object to.

`autoMemoryDirectory` is ONE fixed directory, read from flag, user or policy settings (project
settings ignore it), so it cannot go in a settings.json. `bin/cc-close-attrib` works it out for
each launch:

- slug = CC's canonical root: the parent of `git rev-parse --git-common-dir` (the MAIN
  worktree's root for a linked worktree), else `$PWD`, with `[^a-zA-Z0-9]` replaced by `-`.
  Predicted 13/13 real memory writes, including 5 worktree/subdir cases.
- It skips a slug over 200 chars (CC appends a hash) and a non-ASCII root (CC counts UTF-16
  units).
- It merges into an existing `--settings`, because CC reads one. `scripts/lib/mcp-noinherit.sh`
  already passes one on fired launches.
- If anything is in doubt, it leaves argv untouched. Kill switch: `CC_MEMDIR_REALPATH=off`.

End-to-end A/B through the wrapper (same probe, one variable): `CC_MEMDIR_REALPATH=off` got the
denial above, and the default arm wrote `~/.claude/projects/-private-tmp-memprobe-e2e/memory/probe-on.md`.

## Residual

CC re-emits its parsed `--settings` into child-dispatch args (`h6e`/`eve` in the 2.1.280
bundle), so CC-spawned teammates very likely inherit the fix. This has not been verified end to
end on a teammate pane.

## The general rule

If a path-scoped permission prompt survives allow rules, `--add-dir` and hook allows, look for
a symlink between the spelled path and the real one. Point the path setting at the real path.
Do not try to widen the permission.

## 2026-09-27: the fix held, and our own hook routed around it

A `.claude-next` reso session (2.1.280, auto mode) still prompted on
`Write ~/.claude-next/projects/-Users-chrisren-Development-reso-management-app/memory/project-promoter-data-rbac-ruling.md`.
The operator clicked Yes 16 s later. The launcher fix was working: the session's own system
prompt named the real `~/.claude/projects/…/memory/` path. The symlinked spelling came from
**`hooks/memory-nudge.sh`**, which built the index path from `$CLAUDE_CONFIG_DIR/projects/…` and
printed it in its periodic nudge ("the index is … — create it there"). The model obeyed the
more specific instruction. Pinning `autoMemoryDirectory` only moves which spelling the carve-out
accepts. Every other writer of that path still had to agree with it, and one did not.

Headless A/B on the same binary, same `--settings autoMemoryDirectory=<real>`, same
`CLAUDE_CONFIG_DIR=~/.claude-next`, with only the spelling or the hook varying:

| arm | permission_denials | file written |
|---|---|---|
| real spelling | 0 | yes |
| symlinked spelling, no hook | 1 | no |
| symlinked spelling + PreToolUse `updatedInput` rewriting `file_path` to the real path | 0 | yes |
| same, `permissionDecision: allow` added | 0 | yes |
| Read + Edit through the symlinked spelling, with the rewrite | 0 | yes (edit applied) |

A hook **`allow`** cannot clear the safetyCheck, but a hook **`updatedInput`** can. The rewrite
changes the path the check evaluates, where an allow only tries to override the verdict. No
decision is needed, so every other permission rule still runs on the rewritten path.

Two fixes, so that no spelling prompts:

- `hooks/memory-nudge.sh` names the physical path, resolved as `cc-close-attrib` resolves it.
- `hooks/backup-before-write.sh`, which already runs on `Write|Edit|MultiEdit` so no settings.json
  change was needed, rewrites any `*/.claude*/projects/*/memory/*` path whose physical form
  differs to that physical form. Kill switch: `CC_MEMPATH_CANON=off`. Tests are in
  `tests/memory-path-canon.bats`.

**The general rule, sharpened:** a canonical-path fix is only as strong as the least canonical
path you print. After pinning a path setting, grep every model-facing emitter of that path
(hooks, skills, commands). Then make the chokepoint canonicalize, so an unforeseen spelling
is repaired rather than refused.
