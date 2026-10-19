# cmd_bare — a hook command with its explicit-interpreter prefix stripped, so a reader that matches
# hook commands by string sees `/bin/bash ~/.claude/hooks/x.sh` and `~/.claude/hooks/x.sh` as ONE
# hook. Every hook command runs through an explicit interpreter since 2026-10-18 (a `#!` exec leaks
# 1 KiB of kernel memory on macOS 15.7.9; docs/research/panic-2026-10-18-zone-map-shebang-leak.md),
# and settings written before that still carry the bare spelling. Mirrors BARE_RE in
# scripts/hook-interp.py; tests/hook-interp.bats holds the two to one corpus. Strips only when a path
# follows, so `/bin/bash -c '…'` is left alone. Use: jq -L "$REPO/scripts/lib" 'include "hook-cmd-bare"; …'
def cmd_bare: sub("^(/bin/(ba|z)?sh|/usr/bin/env +(ba|z)?sh|/usr/bin/env +python3?) +(?=[~$/])"; "");
