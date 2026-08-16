#!/usr/bin/env bash
# ms365-mcp-wire.sh — make the Microsoft 365 / Graph MCP server present and identical in EVERY
# account's user-scope config. Idempotent; called by install.sh, runnable by hand, `--check`-able.
#
# WHY THIS IS A SCRIPT AND NOT config-mirror.zsh (the question docs/plans/MS365_MCP_ALL_ACCOUNTS.md
# step 4 asks). The mirror is the fleet's normal way to share config across account dirs, and it
# CANNOT carry this: `.claude.json` is in the isolate-set of all four account dirs
# (lib/config-mirror.zsh `_CC_ISOLATE`), deliberately, because it is the one state file that races
# between concurrent Claude Code processes. `mcpServers` lives in that file. So the mirror is
# structurally unable to share an MCP server, and hand-copying is what left ms365 in 1 dir of 4.
# An idempotent merge run by the installer is the durable form: it re-asserts on every install.sh.
#
# WHY A MERGE AND NEVER A WRITE. `.claude.json` holds per-account state — oauthAccount, usage
# counters, per-project history, startup counts. It is rewritten by every live session. This script
# therefore reads, adds exactly one key under `.mcpServers`, and writes through a temp + `mv`,
# preserving everything else byte-for-byte. It never templates the file.
#
# WHY NOT `npx -y @softeria/ms-365-mcp-server@latest` (the form that was configured). Measured
# 2026-08-15: that spawns TWO node processes — an `npm exec` wrapper at 115.6 MB plus the server at
# 139.3 MB = ~255 MB per session — and re-resolves `@latest` against the registry on every single
# session start (6.0 s cold / 2.1 s warm). Calling the installed binary directly drops the wrapper
# process entirely (~255 MB → ~139 MB, −45%) and removes the registry round-trip. With a fleet that
# runs 16+ concurrent sessions on a box with a memory-storm panic history, the wrapper is 1.8 GB of
# pure overhead.
#
# WHY THE fnm `aliases/default` PATH AND NOT THE VERSIONED ONE. `npm prefix -g` resolves to
# .../fnm/node-versions/v22.21.1/installation — a path that silently disappears the day node is
# upgraded, taking the MCP server with it and giving no error anyone would see. fnm keeps
# `aliases/default` as a symlink it repoints on `fnm default <ver>`, so that path survives the
# upgrade. It still needs the PACKAGE to be there, which is precisely why this script verifies and
# reinstalls rather than assuming — and why it is wired into install.sh instead of being a one-shot.
#
# FAIL-OPEN. If the binary cannot be resolved or installed, the config is written with the `npx`
# form instead. A slower, heavier server that works beats a tidy path that does not.
set -uo pipefail

SERVER_NAME="ms365"
PKG="@softeria/ms-365-mcp-server"
PKG_VERSION="0.143.0"

CHECK_ONLY=false
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=true

_accounts_json() {
  for c in "$HOME/.claude/accounts.json" "$(dirname "${BASH_SOURCE[0]}")/../accounts.json"; do
    [[ -f "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

# Resolve the command+args the config should carry. Echoes a JSON object for `.mcpServers.ms365`.
_resolve_server_cmd() {
  local fnm_default="$HOME/Library/Application Support/fnm/aliases/default/bin/ms-365-mcp-server"
  if [[ -x "$fnm_default" ]]; then
    printf '{"type":"stdio","command":%s,"args":[],"env":{}}' "$(printf '%s' "$fnm_default" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')"
    return 0
  fi
  # Not installed at the durable path — fall back to npx so the capability still works.
  printf '{"type":"stdio","command":"npx","args":["-y","%s@%s"],"env":{}}' "$PKG" "$PKG_VERSION"
}

_ensure_installed() {
  local fnm_default="$HOME/Library/Application Support/fnm/aliases/default/bin/ms-365-mcp-server"
  [[ -x "$fnm_default" ]] && return 0
  $CHECK_ONLY && return 1
  command -v npm >/dev/null 2>&1 || return 1
  echo "  installing $PKG@$PKG_VERSION (removes the npx wrapper process, ~116 MB/session)"
  npm install -g "$PKG@$PKG_VERSION" >/dev/null 2>&1 || return 1
  [[ -x "$fnm_default" ]]
}

main() {
  local acc; acc="$(_accounts_json)" || { echo "  ⚠ no accounts.json — cannot wire $SERVER_NAME" >&2; return 1; }

  if ! _ensure_installed; then
    if $CHECK_ONLY; then
      echo "  ⚠ $PKG not installed at the durable fnm path — config will use the npx fallback"
    else
      echo "  ⚠ could not install $PKG — falling back to npx (slower, +116 MB/session)" >&2
    fi
  fi

  local server_json; server_json="$(_resolve_server_cmd)"

  local rc=0
  # Every account config dir from the SSOT, plus ~/.claude itself (the default dir a bare
  # `claude` uses when CLAUDE_CONFIG_DIR is unset). Names never guessed: next2/3/4 are
  # secondary/tertiary/quaternary, and a loop over `.claude-next{2,3,4}` matches nothing.
  local dirs; dirs="$(python3 -c "
import json,os
d=json.load(open('$acc'))
out=[os.path.expanduser(a['config_dir']) for a in d.get('accounts',[])]
out.append(os.path.expanduser('~/.claude'))
seen=set()
for p in out:
    if p not in seen:
        seen.add(p); print(p)
")"

  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    local f="$dir/.claude.json"
    if [[ ! -f "$f" ]]; then
      echo "  – $(basename "$dir"): no .claude.json (account not initialised) — skipped"
      continue
    fi
    local verdict
    verdict="$(SERVER_NAME="$SERVER_NAME" SERVER_JSON="$server_json" CHECK_ONLY="$CHECK_ONLY" \
      python3 - "$f" <<'PY'
import json, os, sys, tempfile

path = sys.argv[1]
name = os.environ["SERVER_NAME"]
want = json.loads(os.environ["SERVER_JSON"])
check_only = os.environ["CHECK_ONLY"] == "true"

try:
    with open(path) as fh:
        cfg = json.load(fh)
except Exception as e:
    print(f"ERROR unreadable ({e})")
    sys.exit(0)

have = (cfg.get("mcpServers") or {}).get(name)
if have == want:
    print("OK already correct")
    sys.exit(0)
if check_only:
    print("MISSING absent" if have is None else "DRIFT differs from desired")
    sys.exit(0)

cfg.setdefault("mcpServers", {})[name] = want
# temp + rename inside the same dir: atomic, and never leaves a truncated .claude.json behind
# if a live session is reading it mid-write.
d = os.path.dirname(path)
fd, tmp = tempfile.mkstemp(dir=d, prefix=".claude.json.ms365wire.")
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
print("ADDED wired" if have is None else "UPDATED corrected drift")
PY
)"
    case "$verdict" in
      OK*)      echo "  ✓ $(basename "$dir"): $SERVER_NAME ${verdict#OK }" ;;
      ADDED*|UPDATED*) echo "  ✓ $(basename "$dir"): $SERVER_NAME ${verdict#* }" ;;
      MISSING*|DRIFT*) echo "  ✗ $(basename "$dir"): $SERVER_NAME ${verdict#* }"; rc=1 ;;
      *)        echo "  ⚠ $(basename "$dir"): $verdict"; rc=1 ;;
    esac
  done <<< "$dirs"

  # The config is only half the story: a fired session reads the mcp-noinherit passthrough, which
  # filters user-scope STDIO servers unless they are allowlisted. Wiring the config without that
  # allowlist reproduces the exact bug this whole change fixes, so assert it here.
  local lib; lib="$(dirname "${BASH_SOURCE[0]}")/lib/mcp-noinherit.sh"
  if [[ -f "$lib" ]] && ! grep -q 'CC_MCP_USERSCOPE_STDIO_ALLOW' "$lib"; then
    echo "  ✗ scripts/lib/mcp-noinherit.sh has no user-scope stdio allowlist —" >&2
    echo "    every fired session will filter $SERVER_NAME back out (see the plan's Status log)" >&2
    rc=1
  fi
  return $rc
}

main "$@"
