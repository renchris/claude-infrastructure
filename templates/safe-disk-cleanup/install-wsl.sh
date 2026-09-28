#!/bin/bash
# install-wsl.sh — one-paste setup of Claude Code for a READ-ONLY disk cleanup of a Windows PC.
#
# Run inside WSL2 Ubuntu:
#   curl -fsSLo /tmp/safe-cleanup.sh https://raw.githubusercontent.com/renchris/claude-infrastructure/main/templates/safe-disk-cleanup/install-wsl.sh && bash /tmp/safe-cleanup.sh
#
# Why WSL2: Claude Code's OS sandbox runs on macOS, Linux and WSL2 only. Inside it, Claude can READ
# C:\ (as /mnt/c) but its shell can WRITE only ~/cleanup-workspace.
#
# What it does (safe to re-run; backs up anything it changes), then verifies and starts Claude:
#   1. Installs the sandbox's dependencies (bubblewrap, socat) and Claude Code if missing.
#   2. Stops WSL launching Windows programs (.exe), which would run outside the sandbox — now and
#      after restarts (/etc/wsl.conf).
#   3. Installs a guard hook that blocks every delete / move / copy / overwrite / .exe command.
#   4. Merges safety settings into ~/.claude/settings.json: sandbox on with no escape hatch, refuse to
#      start unsandboxed, bypass mode disabled, Claude's file tools denied every Windows file.
#   5. Creates ~/cleanup-workspace with the rules Claude follows (CLAUDE.md).
#   6. Starts Claude in that folder with the task already given.
#
# Undo: cp ~/.claude/settings.json.before-cleanup-kit ~/.claude/settings.json, and delete the
#       [interop] lines this script added to /etc/wsl.conf (then `wsl --shutdown` from Windows).
set -euo pipefail

TEST="${CLEANUP_KIT_TEST:-0}"        # 1 = skip system steps and the launch (tests only)
CLAUDE_DIR="$HOME/.claude"
HOOK="$CLAUDE_DIR/hooks/no-destructive-bash.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
WS="$HOME/cleanup-workspace"
export PATH="$HOME/.local/bin:$PATH"

if [ "$TEST" != 1 ] && ! grep -qi microsoft /proc/version 2>/dev/null; then
  echo "Run this inside WSL2 Ubuntu on the Windows PC."; exit 1
fi
mkdir -p "$CLAUDE_DIR/hooks" "$WS"
WINUSER=""

# ---------------------------------------------------------------- 1-2. system steps
if [ "$TEST" != 1 ]; then
  WINUSER="$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r' || true)"
  echo "Installing the sandbox's dependencies (Ubuntu asks for your Linux password):"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get update -qq
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bubblewrap socat python3 curl </dev/null
  if ! command -v claude >/dev/null 2>&1; then
    curl -fsSLo /tmp/claude-install.sh https://claude.ai/install.sh && bash /tmp/claude-install.sh </dev/null
  fi
  if ! grep -q '^\[interop\]' /etc/wsl.conf 2>/dev/null; then
    if [ -f /etc/wsl.conf ]; then sudo cp /etc/wsl.conf /etc/wsl.conf.before-cleanup-kit; fi
    printf '\n[interop]\nenabled=false\nappendWindowsPath=false\n' | sudo tee -a /etc/wsl.conf >/dev/null
  fi
  for f in /proc/sys/fs/binfmt_misc/WSLInterop /proc/sys/fs/binfmt_misc/WSLInterop-late; do
    if [ -e "$f" ]; then echo 0 | sudo tee "$f" >/dev/null; fi   # takes effect immediately
  done
fi
WINUSER="${WINUSER:-<your Windows user name>}"

# ---------------------------------------------------------------- 3. guard hook
cat > "$HOOK" <<'HOOK_EOF'
#!/bin/bash
# PreToolUse(Bash) guard: refuse any command that can delete, move, overwrite or change files, or
# that launches a Windows program (which would run outside the sandbox). Fail-closed: if the
# command cannot be read, it is blocked; a false positive just makes Claude rewrite the command.
# Redirects to /dev/null (e.g. 2>/dev/null) write nothing, so they are removed first.
cmd_text="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["tool_input"]["command"])' 2>/dev/null)" || {
  echo "BLOCKED by no-destructive-bash: could not read the command, so it is refused." >&2; exit 2; }
payload="$(printf '%s' "$cmd_text" | sed -E 's#[0-9&]*>>? *(/dev/null|&[0-9])##g')"
pattern='(^|[^A-Za-z0-9_.-])(rm|rmdir|unlink|mv|cp|shred|srm|truncate|dd|rsync|trash|chmod|chown|chattr|sudo|git|tee|touch|ln|install|powershell|pwsh|cmd|wsl|explorer|start)([^A-Za-z0-9_-]|$)|\.exe|-delete|-exec|xargs|rmtree|os\.remove|os\.rename|shutil\.|fs\.rm|rmSync|unlinkSync|renameSync|\.claude/|>[^&]'
if printf '%s' "$payload" | grep -Eq -- "$pattern"; then
  echo "BLOCKED by no-destructive-bash: this session is read-only. Do not delete, move, copy or overwrite anything, and do not run Windows programs. Put the proposed action in cleanup.ps1 instead, for the user to review and run themselves." >&2
  exit 2
fi
exit 0
HOOK_EOF
chmod +x "$HOOK"

# ---------------------------------------------------------------- 4. settings merge
if [ -f "$SETTINGS" ] && [ ! -f "$SETTINGS.before-cleanup-kit" ]; then
  cp "$SETTINGS" "$SETTINGS.before-cleanup-kit"
fi
python3 - "$SETTINGS" <<'PY_EOF'
import json, os, sys
path = sys.argv[1]
s = {}
if os.path.exists(path) and open(path).read().strip():
    s = json.load(open(path))
def union(a, b): return list(dict.fromkeys((a or []) + b))
p = s.setdefault("permissions", {})
p["defaultMode"] = "acceptEdits"                 # free edits inside the workspace only
p["disableBypassPermissionsMode"] = "disable"
p["deny"] = union(p.get("deny"), [
    "Bash(rm *)", "Bash(rmdir *)", "Bash(mv *)", "Bash(sudo *)", "Bash(find * -delete*)",
    "Bash(powershell.exe *)", "Bash(cmd.exe *)",
    "Edit(//mnt/**)", "Edit(~/.claude/**)", "Read(~/.ssh/**)"])
sb = s.setdefault("sandbox", {})
sb["enabled"] = True                    # shell writes limited to the start folder
sb["autoAllowBashIfSandboxed"] = True   # read-only scans run without prompts
sb["allowUnsandboxedCommands"] = False  # no "retry outside the sandbox" escape hatch
sb["failIfUnavailable"] = True          # refuse to start rather than run unsandboxed
fs = sb.setdefault("filesystem", {})
fs["denyRead"] = union(fs.get("denyRead"), ["~/.ssh"])
pre = s.setdefault("hooks", {}).setdefault("PreToolUse", [])
if "no-destructive-bash" not in json.dumps(pre):
    pre.append({"matcher": "Bash", "hooks": [
        {"type": "command", "command": 'bash "$HOME/.claude/hooks/no-destructive-bash.sh"'}]})
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
PY_EOF

# ---------------------------------------------------------------- 5. workspace rules
if [ -f "$WS/CLAUDE.md" ] && [ ! -f "$WS/CLAUDE.md.bak" ]; then cp "$WS/CLAUDE.md" "$WS/CLAUDE.md.bak"; fi
cat > "$WS/CLAUDE.md" <<'MD_EOF'
# Disk cleanup — rules for Claude (read every session)

You are helping the owner of this Windows PC free up storage. You run inside WSL2 (Ubuntu), and
the Windows C: drive is at `/mnt/c`. **You are strictly read-only on this machine.** You look,
measure and propose; the owner decides and runs every change themselves, from Windows.

## Hard rules
- Never delete, move, rename, copy, overwrite or empty anything outside this folder. A hook, the
  sandbox and the permission rules enforce this. If a command is blocked, do not look for another
  way to do the same thing; write the proposed action into `cleanup.ps1` instead.
- Never run Windows programs (`powershell.exe`, `cmd.exe`, any `*.exe`). They would run outside the sandbox.
- The only files you may create or edit are inside this folder (`~/cleanup-workspace`).
- Look at metadata (names, sizes, dates, counts), not file contents, unless the owner asks.
  Never open files inside OneDrive: reading one can download it from the cloud.
- Never propose touching anything under PROTECTED below, even if it looks like junk.

## PROTECTED
- C:\Windows, C:\Program Files, C:\Program Files (x86), C:\ProgramData, C:\Recovery
- C:\pagefile.sys, C:\hiberfil.sys, C:\swapfile.sys (only Windows settings may change these)
- C:\Users\__WINUSER__\Documents, \Desktop, \Pictures, \Videos, \Music
- C:\Users\__WINUSER__\OneDrive (and any other cloud-synced folder)
- C:\Users\__WINUSER__\AppData\Roaming, except cache folders you can prove are caches
- any folder containing a `.git` directory
- (the owner's own additions go below this line)

## How to classify every candidate
| Class | Meaning | What goes in the plan |
|---|---|---|
| A. Regenerable | temp files, caches (browser, npm, pip, NuGet, Gradle), logs, build output, `node_modules`, crash dumps | proposed for quarantine, or the tool's own clean command |
| B. Duplicate | byte-identical copies, proven by checksum (`sha256sum`) | quarantine all but one; name the copy kept |
| C. Unique personal data | documents, photos, video, projects, old phone backups, installers you cannot re-download | **never proposed**; listed with size so the owner decides |
| D. System or app internals | anything else under C:\Windows, Program Files, AppData, installed apps | never proposed |

When unsure, it is class C.

Some space can only be reclaimed safely by Windows itself. List these for the owner, never as
script items: Settings › System › Storage › Temporary files (includes Windows Update cleanup and
Windows.old), Storage Sense, Settings › Apps › Installed apps (uninstall), and tools' own cleanup
commands (`npm cache clean --force`, `docker system prune`, `pip cache purge`).

## Deliverables (all inside this folder)
1. `inventory.md`: where the space is, largest first: `df -h /mnt/c`, then top folders under
   `/mnt/c/Users/__WINUSER__`, then files over 500 MB. Scans of /mnt/c are slow; go folder by folder.
2. `plan.md`: one table row per candidate: Windows path · size · class · why it is safe · how to
   get it back. Total reclaimable at the top. **Stop here and wait for the owner's review.**
3. After the owner approves: `cleanup.ps1` and `restore.ps1` (contract below). Every path in
   Windows form (`C:\Users\...`). Do not run them.

## Script contract for `cleanup.ps1`
- `param([switch]$Apply)` and `$ErrorActionPreference = 'Stop'`. The item list is written into the
  script as literal paths, never computed at run time (no wildcards, no `Get-ChildItem -Recurse`).
- Without `-Apply` it is a **dry run** that prints each move and the total size.
- It never deletes. Each item is **moved** with `Move-Item -LiteralPath` to
  `C:\cleanup-quarantine\<date>\` + its original path without the drive colon (same drive, so the
  move is instant and reversible).
- Per item: skip if the source is gone; refuse if the destination exists; refuse any path outside
  `C:\Users\__WINUSER__` or under a PROTECTED path.
- After each successful move, append `original<TAB>quarantine` to
  `C:\cleanup-quarantine\<date>\manifest.tsv`.
- At the end, verify every manifest line (source absent, destination present) and print the result.
- `restore.ps1` reads the manifest and moves everything back, refusing to overwrite anything that
  has reappeared at the original path. It also needs `-Apply` to act.

## How the owner runs them (tell them exactly this once the scripts exist)
In Windows PowerShell, dry run first:

    powershell -ExecutionPolicy Bypass -File \\wsl.localhost\Ubuntu\home\__LINUXUSER__\cleanup-workspace\cleanup.ps1

then the same line with ` -Apply` on the end. To undo: the same line for `restore.ps1`, with ` -Apply`.
Space is only freed when the owner deletes `C:\cleanup-quarantine\<date>` in File Explorer and
empties the Recycle Bin, after using the PC normally for a week or two.
MD_EOF
sed -i.sedbak -e "s|__WINUSER__|$WINUSER|g" -e "s|__LINUXUSER__|$USER|g" "$WS/CLAUDE.md"
rm -f "$WS/CLAUDE.md.sedbak"

# ---------------------------------------------------------------- verify (fail closed)
fail=0
probe() { local got
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$2" | bash "$HOOK" 2>/dev/null; got=$?
  if [ "$got" = "$1" ]; then echo "  PASS  guard exit $got for: $2"; else echo "  FAIL  guard exit $got (wanted $1) for: $2"; fail=1; fi; }
echo "Verifying:"
set +e
probe 2 'rm -rf /mnt/c/Users/me/Downloads/old'
probe 2 'find /mnt/c -name x.log -delete'
probe 2 'mv /mnt/c/Users/me/a /mnt/c/b'
probe 2 '/mnt/c/Windows/System32/cmd.exe /c del x'
probe 0 'du -sh /mnt/c/Users/* 2>/dev/null'
if python3 - "$SETTINGS" <<'PY_EOF'
import json, sys
s = json.load(open(sys.argv[1])); sb = s["sandbox"]; p = s["permissions"]
ok = (sb["enabled"] is True and sb["allowUnsandboxedCommands"] is False and sb["failIfUnavailable"] is True
      and p["disableBypassPermissionsMode"] == "disable" and "Edit(//mnt/**)" in p["deny"]
      and "no-destructive-bash" in json.dumps(s["hooks"]["PreToolUse"]))
sys.exit(0 if ok else 1)
PY_EOF
then echo "  PASS  settings: sandbox locked, bypass disabled, Windows files not editable"
else echo "  FAIL  settings did not read back as expected: $SETTINGS"; fail=1; fi
if [ "$TEST" != 1 ]; then
  if bwrap --ro-bind / / --dev /dev true 2>/dev/null; then echo "  PASS  sandbox engine (bubblewrap) runs"
  else echo "  FAIL  bubblewrap cannot start a sandbox here"; fail=1; fi
  if command -v claude >/dev/null; then echo "  PASS  Claude Code installed"; else echo "  FAIL  Claude Code not installed"; fail=1; fi
  # With interop off, a Windows program cannot start from WSL. This harmless no-op must FAIL.
  if /mnt/c/Windows/System32/cmd.exe /c exit >/dev/null 2>&1; then
    echo "  FAIL  WSL can still launch Windows programs — in Windows PowerShell run: wsl --shutdown, reopen Ubuntu, re-run this"
    fail=1
  else echo "  PASS  WSL cannot launch Windows programs"; fi
fi
set -e
if [ "$fail" != 0 ]; then echo; echo "NOT READY — nothing was started. Fix the FAIL lines above and re-run."; exit 1; fi

# ---------------------------------------------------------------- 6. start Claude with the task
TASK='Read CLAUDE.md in this folder and follow it for the whole session. First ask me which folders on my PC must never be touched, and add my answer to the PROTECTED list in CLAUDE.md. Then build inventory.md with read-only commands, going from the whole C: drive down to the biggest folders, and write plan.md per CLAUDE.md, biggest wins first. Stop and let me review it. Once I say "approved" (minus any rows I strike), write cleanup.ps1 and restore.ps1 per the contract, do not run them, and tell me exactly what to run in PowerShell and how to undo or finish.'
if [ "$TEST" = 1 ]; then echo "READY (test mode: Claude not started)"; exit 0; fi
echo; echo "READY. Starting Claude in ~/cleanup-workspace. If it asks you to log in, do that first; the task continues after."
cd "$WS"
exec claude "$TASK" </dev/tty
