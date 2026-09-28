# Safe disk cleanup with Claude Code (Windows)

Claude Code measures where the disk space went and writes a cleanup plan. It cannot delete,
move or change your files: you review the plan and run every change yourself, and every change can
be undone.

## Setup

1. In PowerShell (as administrator): `wsl --install`, restart, open **Ubuntu** and create a user.
2. In Ubuntu, paste:

```
curl -fsSLo /tmp/safe-cleanup.sh https://raw.githubusercontent.com/renchris/claude-infrastructure/main/templates/safe-disk-cleanup/install-wsl.sh && bash /tmp/safe-cleanup.sh
```

It installs everything, checks the safety setup, and starts Claude with the task already given.

## What keeps your files safe

- **Sandbox.** Claude's shell runs in an OS sandbox that can write only to `~/cleanup-workspace`,
  with no fallback to running unsandboxed. WSL is also stopped from launching Windows programs,
  which would run outside that sandbox.
- **Guard hook.** Every delete, move, copy or overwrite command is blocked before it runs.
- **Permission rules.** Claude's file-editing tools are denied every Windows file.
- **Quarantine, not deletion.** The cleanup script you run moves files to `C:\cleanup-quarantine`,
  and a restore script moves them back. Space is freed only when you delete that folder yourself.

Back up anything irreplaceable first. Undo the setup: see the header of `install-wsl.sh`.
