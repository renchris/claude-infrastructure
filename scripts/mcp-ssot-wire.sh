#!/usr/bin/env bash
# mcp-ssot-wire.sh — render the ONE authored MCP server list (`mcp-servers.json` at repo root) into
# every user-scope config a session can actually read. Idempotent; called by install.sh, runnable by
# hand, `--check`-able. Plan: docs/plans/MCP_CONFIG_SSOT.md.
#
# Was `ms365-mcp-wire.sh`, which did exactly this for ONE hardcoded server. Everything that made that
# script correct is preserved verbatim below — merge-not-write, temp + rename, idempotence, --check,
# fail-open, the allowlist assertion. Only the server list became data.
#
# WHY RENDERED COPIES AND NOT `--mcp-config` POINTING AT THE SSOT (the design fork Wave 1 settled).
# Measured on 2.1.260: `claude mcp list` is structurally BLIND to --mcp-config — with user and
# project scope both empty it prints "No MCP servers configured" while the very same invocation
# demonstrably starts the server. Both of this machine's MCP sensors read exactly that command
# (hooks/session-start.sh:270, lib/cc-upgrade-gate/check13_mcp.sh:14), so flag-injection would make
# the session banner report 0 servers forever and make upgrade-gate check #13's PASS condition
# (>=1 "✔ Connected") permanently unreachable. Rendering keeps the servers where the sensors can see
# them, and reaches every entry point by construction — there is no chokepoint to get right, because
# it is the config file itself that changed.
#
# WHY THIS IS A SCRIPT AND NOT config-mirror.zsh. The mirror is the fleet's normal way to share
# config across account dirs, and it CANNOT carry this: `.claude.json` is in the isolate-set of all
# four account dirs (lib/config-mirror.zsh `_CC_ISOLATE`), deliberately, because it is the one state
# file that races between concurrent Claude Code processes. `mcpServers` lives in that file. So the
# mirror is structurally unable to share an MCP server, and hand-copying is what left ms365 in 1 dir
# of 4. An idempotent merge run by the installer is the durable form.
#
# WHY A MERGE AND NEVER A WRITE. `.claude.json` holds per-account state — oauthAccount, usage
# counters, per-project history, startup counts. It is rewritten by every live session. This script
# therefore reads, sets only the SSOT's own keys under `.mcpServers`, and writes through a temp +
# `mv` in the same directory, preserving everything else. It never templates the file. It also never
# DELETES a server it does not know about: an unrelated key in a config dir survives untouched.
#
# 🚨 THE POPULATION — this is where the predecessor was wrong, and it is why divergence #1 survived.
# The old loop was `accounts.json` config_dirs + `~/.claude`, on the comment "plus ~/.claude itself
# (the default dir a bare `claude` uses when CLAUDE_CONFIG_DIR is unset)". That is FALSE. Measured
# 2026-09-08 on 2.1.260 with two servers, one in each file, under a throwaway HOME: with
# CLAUDE_CONFIG_DIR unset the binary reads **$HOME/.claude.json**, NOT $HOME/.claude/.claude.json.
# So the file that comment was aiming at was never in the loop, `--check` printed 5/5 green, and
# ~/.claude.json went on carrying `npx -y @softeria/ms-365-mcp-server@latest` — the exact form this
# header documents as costing ~116 MB and a registry round-trip per session. A green checker whose
# denominator excludes the defect. Both files are now in the population, and they are DIFFERENT
# files: never collapse them.
#
# THE RESIDUAL RACE, stated rather than hidden. A live session rewrites its own `.claude.json` from
# an in-memory copy read at session start, so a session already running when this renders can write
# our key back out. That is why re-assertion (install.sh) and detection (`--check`, and
# tests/mcp-ssot-wire.bats) are the design, not a one-shot migration.
#
# SSOT SCHEMA (`mcp-servers.json`):
#   .mcpServers.<name>          the desired definition, verbatim. `command` may use ~ or ${HOME};
#                               they are expanded here so the written config holds a literal path.
#   .resolve.<name>             OPTIONAL, for a server whose command is a local binary:
#     .npm_package/.npm_version  installed if the command path is missing
#     .fallback                  written instead if it still cannot be resolved (FAIL-OPEN)
set -uo pipefail

# --check  report whether the SSOT's servers are present and correct; write nothing.
# --audit  --check PLUS the divergence direction the renderer deliberately cannot fix: a server
#          present in a config dir but ABSENT from the SSOT. The renderer is merge-only and never
#          deletes (an unrelated key must survive), so detection is the only honest guard for that
#          half — and it is the plan's DoD #7 ("a regression test that FAILS if a server is added to
#          one config dir and not the SSOT"). install.sh uses --check, not --audit, so one
#          deliberately-unmanaged server cannot wedge every install.
CHECK_ONLY=false
AUDIT=false
case "${1:-}" in
  --check) CHECK_ONLY=true ;;
  --audit) CHECK_ONLY=true; AUDIT=true ;;
  "")      ;;
  *)       echo "usage: $(basename "$0") [--check|--audit]" >&2; exit 2 ;;
esac

# Resolve $0 through its symlinks BEFORE deriving the root. ~/.claude/scripts/ is per-file symlinks
# into the checkout, so an unresolved `dirname "$0"/..` yields ~/.claude — no mcp-servers.json in the
# checkout, no accounts.json fallback, and the failure is invisible from a worktree because it only
# happens on the live path. No `readlink -f`: that is GNU-only and this box is BSD. Canonical loop:
# _resolve_self() in scripts/ship-land.sh.
_repo_root() {
  local p="${BASH_SOURCE[0]}" d
  while [ -L "$p" ]; do
    d="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  cd "$(dirname "$p")/.." && pwd
}
REPO_ROOT="$(_repo_root)"

_ssot() {
  for c in "$REPO_ROOT/mcp-servers.json" "$HOME/.claude/mcp-servers.json"; do
    [[ -f "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

_accounts_json() {
  for c in "$HOME/.claude/accounts.json" "$REPO_ROOT/accounts.json"; do
    [[ -f "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

# Ensure a `resolve`d server's binary exists. Echoes nothing; return 0 = resolvable.
_ensure_installed() {
  local cmd="$1" pkg="$2" ver="$3"
  [[ -x "$cmd" ]] && return 0
  $CHECK_ONLY && return 1
  # Tests render against a fixtured HOME where the durable path cannot exist; installing there
  # would reach the network and prove nothing about the merge semantics under test.
  [[ -n "${CC_MCP_WIRE_NO_INSTALL:-}" ]] && return 1
  [[ -n "$pkg" ]] || return 1
  command -v npm >/dev/null 2>&1 || return 1
  echo "  installing $pkg@$ver (removes the npx wrapper process, ~116 MB/session)"
  npm install -g "$pkg@$ver" >/dev/null 2>&1 || return 1
  [[ -x "$cmd" ]]
}

# A label that distinguishes $HOME/.claude.json from $HOME/.claude/.claude.json — `basename` on the
# file gives ".claude.json" for both, and `basename` on the dir gives the HOME name for the first.
_label() {
  local f="$1"
  [[ "$f" == "$HOME/.claude.json" ]] && { echo "${HOME}/.claude.json (CLAUDE_CONFIG_DIR unset)"; return; }
  basename "$(dirname "$f")"
}

main() {
  local ssot; ssot="$(_ssot)" || { echo "  ⚠ no mcp-servers.json — nothing to render" >&2; return 1; }
  local acc;  acc="$(_accounts_json)" || { echo "  ⚠ no accounts.json — cannot resolve the account dirs" >&2; return 1; }

  # Resolve every server to its final JSON, applying ~ expansion and the fail-open fallback.
  # Emitted as one object so the per-file merge below is a single pass.
  local resolved rc_res=0
  resolved="$(
    python3 - "$ssot" <<'PY'
import json, os, sys, shutil
ssot = json.load(open(sys.argv[1]))
servers = ssot.get("mcpServers") or {}
resolve = ssot.get("resolve") or {}
out, notes = {}, []
for name in sorted(servers):
    spec = json.loads(json.dumps(servers[name]))
    cmd = spec.get("command")
    if isinstance(cmd, str):
        cmd = os.path.expanduser(os.path.expandvars(cmd))
        spec["command"] = cmd
    r = resolve.get(name)
    # Only a resolve'd server with an ABSOLUTE command is a candidate for install/fallback; a bare
    # name like "npx" is resolved by PATH at spawn time and is not this script's business.
    if r and isinstance(cmd, str) and cmd.startswith("/") and not os.access(cmd, os.X_OK):
        # PAD EVERY CELL. Tab is IFS-WHITESPACE, so an empty cell does not read back empty — it
        # shifts every later column LEFT, silently, exit 0. `npm_package`/`npm_version` are both
        # optional in the SSOT, so this producer really can emit one. The read side cannot repair
        # it; the placeholder is stripped there.
        def _cell(v, ph="\x1e"):
            v = "" if v is None else str(v)
            v = v.replace("\t", " ").replace("\r", " ").replace("\n", " ")
            return v if v != "" else ph
        notes.append("\t".join(_cell(x) for x in (
            "NEEDS_INSTALL", name, cmd, r.get("npm_package", ""), r.get("npm_version", ""))))
    out[name] = spec
print(json.dumps({"servers": out, "notes": notes}))
PY
  )" || rc_res=$?
  [[ $rc_res -eq 0 && -n "$resolved" ]] || { echo "  ⚠ mcp-servers.json unreadable" >&2; return 1; }

  # Any server whose binary is missing: try to install it, else swap in its fallback.
  # Every cell is padded by the emitter above (tab is IFS-whitespace, so an empty cell would shift
  # the later columns left). Strip the placeholder back to empty here — this is the only reader.
  while IFS=$'\t' read -r tag name cmd pkg ver; do
    [[ "$tag" == "NEEDS_INSTALL" ]] || continue
    for _v in name cmd pkg ver; do
      [[ "${!_v}" == $'\x1e' ]] && printf -v "$_v" '%s' ""
    done
    if ! _ensure_installed "$cmd" "$pkg" "$ver"; then
      if $CHECK_ONLY; then
        echo "  ⚠ $name: $pkg not installed at the durable path — config will use the fallback"
      else
        echo "  ⚠ $name: could not install $pkg — falling back (slower, +116 MB/session)" >&2
      fi
      resolved="$(SSOT="$ssot" NAME="$name" CUR="$resolved" python3 -c '
import json, os
ssot = json.load(open(os.environ["SSOT"]))
cur = json.loads(os.environ["CUR"])
fb = ((ssot.get("resolve") or {}).get(os.environ["NAME"]) or {}).get("fallback")
if fb: cur["servers"][os.environ["NAME"]] = fb
print(json.dumps(cur))
')"
    fi
  done < <(RES="$resolved" python3 -c 'import json,os;[print(n) for n in json.loads(os.environ["RES"])["notes"]]')

  # THE POPULATION. Every account config dir from accounts.json, plus ~/.claude (read when
  # CLAUDE_CONFIG_DIR points at it explicitly — `claude-prev` defaults to it), plus $HOME/.claude.json
  # (read when CLAUDE_CONFIG_DIR is genuinely UNSET — see the header; these are different files).
  # Names are never guessed: next2/3/4 are secondary/tertiary/quaternary, and a loop over
  # `.claude-next{2,3,4}` matches nothing.
  local files; files="$(python3 -c "
import json,os
d=json.load(open('$acc'))
out=[os.path.join(os.path.expanduser(a['config_dir']),'.claude.json') for a in d.get('accounts',[])]
out.append(os.path.expanduser('~/.claude/.claude.json'))
out.append(os.path.expanduser('~/.claude.json'))
seen=set()
for p in out:
    if p not in seen:
        seen.add(p); print(p)
")"

  local rc=0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    local label; label="$(_label "$f")"
    if [[ ! -f "$f" ]]; then
      echo "  – $label: no .claude.json (account not initialised) — skipped"
      continue
    fi
    local verdict
    verdict="$(SERVERS_JSON="$resolved" CHECK_ONLY="$CHECK_ONLY" AUDIT="$AUDIT" python3 - "$f" <<'PY'
import json, os, sys, tempfile

path = sys.argv[1]
want = json.loads(os.environ["SERVERS_JSON"])["servers"]
check_only = os.environ["CHECK_ONLY"] == "true"
audit = os.environ.get("AUDIT") == "true"

try:
    with open(path) as fh:
        cfg = json.load(fh)
except Exception as e:
    print(f"ERROR unreadable ({e})")
    sys.exit(0)

have = cfg.get("mcpServers") or {}
missing   = sorted(n for n in want if n not in have)
drift     = sorted(n for n in want if n in have and have[n] != want[n])
# The other divergence direction: in a config dir, not in the SSOT. Reported only, never removed.
unmanaged = sorted(n for n in have if n not in want) if audit else []

if not missing and not drift and not unmanaged:
    print("OK all %d already correct" % len(want))
    sys.exit(0)
if check_only:
    bits = []
    if missing:   bits.append("absent: " + ",".join(missing))
    if drift:     bits.append("drift: " + ",".join(drift))
    if unmanaged: bits.append("not in the SSOT: " + ",".join(unmanaged))
    tag = "MISSING" if missing else ("DRIFT" if drift else "UNMANAGED")
    print(tag + " " + "; ".join(bits))
    sys.exit(0)

# NO APOSTROPHES ANYWHERE IN THIS HEREDOC. bash 3.2 (macOS /bin/bash, and what the off-box
# runner resolves for a bare `bash`) does not recognise a heredoc delimiter inside a command
# substitution -- it lexes this body as shell code, so one apostrophe opens an unterminated
# quote and the whole script dies at parse time. Ratchet: scripts/bash32-parse-lint.sh
# Merge: set only the keys the SSOT itself declares. An unrelated server already present is left alone.
cfg.setdefault("mcpServers", {}).update(want)
# temp + rename inside the same dir: atomic, and never leaves a truncated .claude.json behind
# if a live session is reading it mid-write.
d = os.path.dirname(path)
fd, tmp = tempfile.mkstemp(dir=d, prefix=".claude.json.mcpwire.")
try:
    with os.fdopen(fd, "w") as fh:
        json.dump(cfg, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, path)
except Exception as e:
    try: os.unlink(tmp)
    except OSError: pass
    print(f"ERROR write failed ({e})")
    sys.exit(0)
bits = []
if missing: bits.append("added " + ",".join(missing))
if drift:   bits.append("corrected " + ",".join(drift))
print("WROTE " + "; ".join(bits))
PY
)"
    case "$verdict" in
      OK*)             echo "  ✓ $label: ${verdict#OK }" ;;
      WROTE*)          echo "  ✓ $label: ${verdict#WROTE }" ;;
      MISSING*|DRIFT*|UNMANAGED*) echo "  ✗ $label: ${verdict#* }"; rc=1 ;;
      *)               echo "  ⚠ $label: $verdict"; rc=1 ;;
    esac
  done <<< "$files"

  # The config is only half the story: a fired session reads the mcp-noinherit passthrough, which
  # filters user-scope STDIO servers unless they are allowlisted. Wiring the config without that
  # allowlist reproduces the exact bug this whole change fixes, so assert it here.
  local lib; lib="$REPO_ROOT/scripts/lib/mcp-noinherit.sh"
  if [[ -f "$lib" ]] && ! grep -q 'CC_MCP_USERSCOPE_STDIO_ALLOW' "$lib"; then
    echo "  ✗ scripts/lib/mcp-noinherit.sh has no user-scope stdio allowlist —" >&2
    echo "    every fired session will filter the stdio servers back out (see the plan's Status log)" >&2
    rc=1
  fi
  return $rc
}

main "$@"
