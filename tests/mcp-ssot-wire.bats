#!/usr/bin/env bats
# MCP SSOT renderer — mcp-servers.json + scripts/mcp-ssot-wire.sh (plan: docs/plans/MCP_CONFIG_SSOT.md).
#
# WHAT IS UNDER TEST, and why it is a renderer rather than a `--mcp-config` flag. Measured on 2.1.260
# during Wave 1: `claude mcp list` is structurally BLIND to --mcp-config — with user and project
# scope both empty it prints "No MCP servers configured" while the same invocation demonstrably
# STARTS the server. Both of this machine's MCP sensors read that command (hooks/session-start.sh,
# lib/cc-upgrade-gate/check13_mcp.sh), so flag-injection would blind them permanently. Rendering the
# SSOT into the config keeps the sensors truthful, so these tests pin the RENDER contract.
#
# THE RED-PROOF THAT MATTERS is "the population includes $HOME/.claude.json". The predecessor
# (scripts/ms365-mcp-wire.sh) looped over accounts.json + ~/.claude on the comment "the default dir a
# bare claude uses when CLAUDE_CONFIG_DIR is unset" — which is FALSE: unset means $HOME/.claude.json,
# never $HOME/.claude/.claude.json. That one wrong belief is why `--check` printed 5/5 green for
# weeks while the sixth file carried a different ms365 endpoint. Every case below that touches
# ~/.claude.json fails against the predecessor and passes against the renderer.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WIRE="$REPO/scripts/mcp-ssot-wire.sh"
  SSOT="$REPO/mcp-servers.json"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude" "$HOME/.claude-secondary" "$HOME/.claude-tertiary"
  # The fixtured HOME cannot hold the durable fnm binary, and installing it would reach the network
  # and prove nothing about the merge semantics under test. The fail-open path is asserted directly.
  export CC_MCP_WIRE_NO_INSTALL=1
  cat > "$HOME/.claude/accounts.json" <<'JSON'
{"accounts":[{"name":"next","config_dir":"~/.claude-secondary","launcher":"claude"},
             {"name":"next3","config_dir":"~/.claude-tertiary","launcher":"claude3"}]}
JSON
  # .claude-secondary carries state that MUST survive the merge; the rest are bare.
  echo '{"numStartups":42,"mcpServers":{"unrelated-server":{"type":"http","url":"https://example.invalid/a"}}}' \
    > "$HOME/.claude-secondary/.claude.json"
  echo '{}'                  > "$HOME/.claude-tertiary/.claude.json"
  echo '{}'                  > "$HOME/.claude/.claude.json"
  echo '{"numStartups":7}'   > "$HOME/.claude.json"
}

# --- the SSOT itself -------------------------------------------------------------------------

@test "mcp-servers.json is valid JSON and is the only authored server list" {
  [ -f "$SSOT" ]
  run python3 -c "import json,sys; d=json.load(open('$SSOT')); assert d['mcpServers']; print(len(d['mcpServers']))"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "every SSOT stdio command is absolute or a bare name — never a repo-relative path" {
  # A repo-relative command would resolve against the SESSION's cwd, not the checkout, and would
  # silently fail in every project but this one.
  run python3 - "$SSOT" <<'PY'
import json, sys
bad = []
for n, s in json.load(open(sys.argv[1]))["mcpServers"].items():
    c = s.get("command")
    if isinstance(c, str) and not (c.startswith(("/", "~", "${")) or "/" not in c):
        bad.append(f"{n}={c}")
print(",".join(bad))
PY
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- the render contract ---------------------------------------------------------------------

@test "renders every SSOT server into every account config dir" {
  run bash "$WIRE"
  [ "$status" -eq 0 ]
  for f in "$HOME/.claude-secondary/.claude.json" "$HOME/.claude-tertiary/.claude.json"; do
    for name in $(python3 -c "import json;print(' '.join(json.load(open('$SSOT'))['mcpServers']))"); do
      run python3 -c "import json;print('yes' if '$name' in (json.load(open('$f')).get('mcpServers') or {}) else 'NO')"
      [ "$output" = "yes" ]
    done
  done
}

@test "RED-PROOF: the population includes \$HOME/.claude.json, the file an unset CLAUDE_CONFIG_DIR reads" {
  # The predecessor never wrote this file. This is the case that was silently failing.
  run bash "$WIRE"
  [ "$status" -eq 0 ]
  run python3 -c "import json;print(len(json.load(open('$HOME/.claude.json')).get('mcpServers') or {}))"
  [ "$output" -ge 1 ]
}

@test "RED-PROOF: \$HOME/.claude.json and \$HOME/.claude/.claude.json are DIFFERENT files" {
  # Collapsing them is the mistake the predecessor's comment encoded. Both are rendered, and each
  # keeps its own unrelated state.
  run bash "$WIRE"
  [ "$status" -eq 0 ]
  run python3 -c "import json;print(json.load(open('$HOME/.claude.json'))['numStartups'])"
  [ "$output" = "7" ]
  run python3 -c "import json;print('numStartups' in json.load(open('$HOME/.claude/.claude.json')))"
  [ "$output" = "False" ]
}

@test "MERGE, never write: an unrelated server and unrelated state both survive" {
  run bash "$WIRE"
  [ "$status" -eq 0 ]
  run python3 -c "import json;print(json.load(open('$HOME/.claude-secondary/.claude.json'))['mcpServers']['unrelated-server']['url'])"
  [ "$output" = "https://example.invalid/a" ]
  run python3 -c "import json;print(json.load(open('$HOME/.claude-secondary/.claude.json'))['numStartups'])"
  [ "$output" = "42" ]
}

@test "idempotent: a second run reports already-correct and changes nothing" {
  run bash "$WIRE"; [ "$status" -eq 0 ]
  before="$(python3 -c "import sys;sys.stdout.write(open('$HOME/.claude-tertiary/.claude.json').read())")"
  run bash "$WIRE" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"correct"* ]] || false
  after="$(python3 -c "import sys;sys.stdout.write(open('$HOME/.claude-tertiary/.claude.json').read())")"
  [ "$before" = "$after" ]
}

@test "--check FAILS on drift and the run REPAIRS it" {
  run bash "$WIRE"; [ "$status" -eq 0 ]
  # Corrupt one server's definition in one dir only — the silent-divergence shape.
  python3 - <<PY
import json
p = "$HOME/.claude-tertiary/.claude.json"
d = json.load(open(p))
name = sorted(d["mcpServers"])[0]
d["mcpServers"][name] = {"type": "stdio", "command": "/bin/false", "args": [], "env": {}}
json.dump(d, open(p, "w"))
PY
  run bash "$WIRE" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"drift"* ]] || false
  run bash "$WIRE"
  [ "$status" -eq 0 ]
  run bash "$WIRE" --check
  [ "$status" -eq 0 ]
}

# --- DoD #7 ------------------------------------------------------------------------------------

@test "DoD#7: --audit FAILS when a server is added to one config dir and not the SSOT" {
  run bash "$WIRE"; [ "$status" -eq 0 ]
  # --check must still pass: the renderer is merge-only and deliberately never deletes, so one
  # unmanaged server may not wedge every install.sh.
  run bash "$WIRE" --check
  [ "$status" -eq 0 ]
  # …but --audit is the divergence guard and must catch it.
  run bash "$WIRE" --audit
  [ "$status" -eq 1 ]
  [[ "$output" == *"not in the SSOT"* ]] || false
  [[ "$output" == *"unrelated-server"* ]] || false
}

@test "DoD#7 control: with no unmanaged server anywhere, --audit is GREEN" {
  # Without this the case above passes for any always-failing audit.
  python3 -c "
import json; p='$HOME/.claude-secondary/.claude.json'
d=json.load(open(p)); d['mcpServers'].pop('unrelated-server'); json.dump(d,open(p,'w'))"
  run bash "$WIRE"; [ "$status" -eq 0 ]
  run bash "$WIRE" --audit
  [ "$status" -eq 0 ]
}

# --- fail-open ----------------------------------------------------------------------------------

@test "FAIL-OPEN: an unresolvable local binary falls back rather than writing a dead path" {
  # The fixtured HOME has no fnm tree, so ms365's durable path cannot exist. A slower server that
  # works beats a tidy path that does not — assert the fallback was written, not the missing binary.
  run bash "$WIRE"
  [ "$status" -eq 0 ]
  run python3 - <<PY
import json, os
ssot = json.load(open("$SSOT"))
cfg  = json.load(open("$HOME/.claude-tertiary/.claude.json"))
bad = []
for name, r in (ssot.get("resolve") or {}).items():
    got = cfg["mcpServers"][name]
    want_cmd = os.path.expanduser(ssot["mcpServers"][name].get("command", ""))
    if want_cmd.startswith("/") and not os.access(want_cmd, os.X_OK):
        if got != r.get("fallback"):
            bad.append(name)
print(",".join(bad))
PY
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an unwritable/absent config file is SKIPPED, never created" {
  rm -f "$HOME/.claude-tertiary/.claude.json"
  run bash "$WIRE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped"* ]] || false
  [ ! -f "$HOME/.claude-tertiary/.claude.json" ]
}
