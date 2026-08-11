#!/usr/bin/env bats
# MCP no-inherit for agent fan-out (backlog eece54939e7f · W3 of MCP_MEMORY_100P_IMPLEMENTATION).
#
# The subject is scripts/lib/mcp-noinherit.sh + its wiring in scripts/handoff-fire.sh: a fired
# session must NOT start the project stdio servers of whatever repo it lands in, unless its brief
# declares MCP work or the caller passes --with-mcp.
#
# TWO LAYERS, DELIBERATELY:
#   1. hermetic — the composition decision (default OFF / brief-disarm / --with-mcp), asserted
#      against a fixture config dir. No account, no network, no spend. These are the tests that run
#      on every commit.
#   2. live (opt-in, CC_MCP_LIVE_PROBE=1) — a real `claude -p` in a scratch project carrying a fake
#      logging stdio server, proving the composed flags actually change what the CLI spawns. This is
#      the POSITIVE CONTROL for the whole mechanism and it is the only arm that can catch a vendor
#      change; it is opt-in because it needs a real config dir, not because it is optional evidence.
#      Recorded verdict 2026-08-11 on 2.1.220 (see docs/plans/MCP_MEMORY_100P_IMPLEMENTATION.md W3).
#
# Every "does not spawn" assertion below is paired with one that DOES spawn. A guard whose negative
# arm passes because the fixture is broken proves nothing, and this fixture has three ways to be
# silently inert (no .mcp.json written, a server that cannot start, a log path nothing writes to).

setup() {
  # HERMETIC PINS. This suite executes handoff-fire.sh, so it inherits that script's whole ambient
  # surface — and the land gate is right to refuse without these: an unfixtured run reads the
  # operator's live ~/, their real machine load, and their deployed claude-accounts. Same four seams
  # as tests/handoff-fire-argv-launch.bats, for the same reason: fixturing $HOME alone does not
  # redirect an absolute /tmp default or a BARE NAME the subject executes off the live PATH.
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # …and terminal identity: handoff-fire is terminal-aware, so an inherited KITTY_WINDOW_ID from the
  # developer's own pane would decide which arm runs. Same pin as tests/boot-resume-launch.bats.
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1

  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/lib/mcp-noinherit.sh"
  FIRE="$REPO/scripts/handoff-fire.sh"
  SERVER="$REPO/tests/fixtures/mcp-noinherit/fake-stdio-server.py"

  WORK="$BATS_TEST_TMPDIR/work"; mkdir -p "$WORK"

  # The account the dry-run tests name must resolve to a config dir UNDER the fixtured $HOME, with
  # user-scope http servers in it — otherwise the passthrough cannot be built and the assertions
  # below would silently measure the no-passthrough fallback instead of the shipped path.
  mkdir -p "$HOME/.claude-secondary"
  cat > "$HOME/.claude-secondary/.claude.json" <<'JSON'
{"mcpServers": {"motion": {"type": "http", "url": "https://example.invalid/a"}}}
JSON
  # A fixture config dir standing in for an account: two http servers (which must SURVIVE) and one
  # stdio server (which must NOT). The stdio entry is what proves the filter keys on `command`
  # rather than on a name we happened to pick.
  CFG="$WORK/.claude-fixture"
  mkdir -p "$CFG"
  cat > "$CFG/.claude.json" <<'JSON'
{
  "mcpServers": {
    "motion":      {"type": "http", "url": "https://example.invalid/a"},
    "motion-plus": {"type": "http", "url": "https://example.invalid/b"},
    "some-stdio":  {"command": "/bin/echo", "args": ["hi"]}
  }
}
JSON
  BRIEF_PLAIN="$WORK/brief-plain.txt"
  printf 'Refactor the ledger module and land it. No browser work.\n' > "$BRIEF_PLAIN"
  BRIEF_BROWSER="$WORK/brief-browser.txt"
  printf 'Screenshot the dashboard using browsermcp and report.\n' > "$BRIEF_BROWSER"
}

teardown() {
  return 0   # everything lives under $BATS_TEST_TMPDIR, which bats removes
}

# ── layer 1: the composition decision ──────────────────────────────────────────────────────────

@test "default: composes strict-mcp-config and preserves the user-scope http servers" {
  # shellcheck source=/dev/null
  source "$LIB"
  cc_mcp_noinherit_args "$CFG" "$BRIEF_PLAIN"
  [[ "$CC_MCP_NOINHERIT_ARGS" == *"--strict-mcp-config"* ]]
  [[ "$CC_MCP_NOINHERIT_ARGS" == *"--mcp-config="* ]]
  pass="${CC_MCP_NOINHERIT_ARGS##*--mcp-config=}"
  [ -f "$pass" ]
  # the two http servers survive, the stdio one is filtered out — the whole point of the passthrough
  run jq -r '.mcpServers | keys | join(",")' "$pass"
  [ "$output" = "motion,motion-plus" ]
}

@test "the passthrough uses --mcp-config=VALUE — the space form eats the prompt" {
  # REGRESSION, not styling. `--mcp-config` is variadic: `--mcp-config <path> "<prompt>"` consumes
  # the prompt as a second config path, and a real fire died on it with ENAMETOOLONG while every
  # `-p`-shaped test stayed green (a `-p` prompt is never a loose positional). Assert the shape at
  # the composer AND at the typed line, because only the typed line has a bare positional.
  # shellcheck source=/dev/null
  source "$LIB"
  cc_mcp_noinherit_args "$CFG" "$BRIEF_PLAIN"
  [[ "$CC_MCP_NOINHERIT_ARGS" != *"--mcp-config "* ]]
  [[ "$CC_MCP_NOINHERIT_ARGS" == *"--mcp-config="* ]]

  run timeout 300 bash "$FIRE" --prompt-file "$BRIEF_PLAIN" --dry-run --account next2
  [ "$status" -eq 0 ]
  cmd="$(printf '%s\n' "$output" | grep '^command:')"
  [[ "$cmd" == *"--mcp-config="* ]]
  [[ "$cmd" != *"--mcp-config "* ]]
}

@test "POSITIVE CONTROL: a brief that declares browser work leaves the servers ON" {
  # shellcheck source=/dev/null
  source "$LIB"
  cc_mcp_noinherit_args "$CFG" "$BRIEF_BROWSER"
  [ -z "$CC_MCP_NOINHERIT_ARGS" ]
  [[ "$CC_MCP_NOINHERIT_REASON" == *"browsermcp"* ]]
}

@test "the reason is never empty — a silent control is the failure this replaced" {
  # shellcheck source=/dev/null
  source "$LIB"
  for b in "$BRIEF_PLAIN" "$BRIEF_BROWSER"; do
    cc_mcp_noinherit_args "$CFG" "$b"
    [ -n "$CC_MCP_NOINHERIT_REASON" ]
  done
  # …and it must survive being called the way a caller naturally writes it. The first wiring used
  # `X=$(cc_mcp_noinherit_args …)`, whose subshell swallowed the reason and rendered `(undecided)`.
  cc_mcp_noinherit_args "$CFG" "$BRIEF_PLAIN"
  [ -n "$CC_MCP_NOINHERIT_REASON" ]
}

@test "no user-scope servers → still isolates, and SAYS the http servers went too" {
  # shellcheck source=/dev/null
  source "$LIB"
  empty="$WORK/.claude-empty"; mkdir -p "$empty"; echo '{}' > "$empty/.claude.json"
  cc_mcp_noinherit_args "$empty" "$BRIEF_PLAIN"
  [ "$CC_MCP_NOINHERIT_ARGS" = "--strict-mcp-config" ]
  [[ "$CC_MCP_NOINHERIT_REASON" == *"--with-mcp"* ]]
}

@test "CC_MCP_NOINHERIT=off disarms it entirely" {
  # shellcheck source=/dev/null
  source "$LIB"
  CC_MCP_NOINHERIT=off cc_mcp_noinherit_args "$CFG" "$BRIEF_PLAIN"
  [ -z "$CC_MCP_NOINHERIT_ARGS" ]
  [[ "$CC_MCP_NOINHERIT_REASON" == *"off"* ]]
}

# ── layer 1b: the wiring, through the real script's dry run ────────────────────────────────────

@test "handoff-fire --dry-run: default fire carries the isolation flags" {
  run timeout 300 bash "$FIRE" --prompt-file "$BRIEF_PLAIN" --dry-run --account next2
  [ "$status" -eq 0 ]
  [[ "$output" == *"--strict-mcp-config"* ]]
  [[ "$output" == *"mcp:      project .mcp.json stdio servers OFF"* ]]
}

@test "POSITIVE CONTROL: handoff-fire --with-mcp does NOT carry them" {
  run timeout 300 bash "$FIRE" --prompt-file "$BRIEF_PLAIN" --dry-run --account next2 --with-mcp
  [ "$status" -eq 0 ]
  [[ "$output" != *"--strict-mcp-config"* ]]
  [[ "$output" == *"--with-mcp: project .mcp.json servers left ON"* ]]
}

# ── layer 2: live spawn behaviour (opt-in) ─────────────────────────────────────────────────────
# Enable with:  CC_MCP_LIVE_PROBE=1 CC_MCP_PROBE_CFG=$HOME/.claude-tertiary cc-bats tests/mcp-no-inherit.bats
# Use a config dir whose account is rate-limited: the spawn happens during startup, before the
# first API request, so the whole arm costs $0 and the 429 that follows is the expected end state.

live_probe() { # $1=extra flags → echoes the number of stdio STARTs this session itself caused
  local extra="$1" proj="$WORK/proj" log="$WORK/spawn-$RANDOM.ndjson"
  mkdir -p "$proj"; : > "$log"
  python3 - "$proj" "$SERVER" "$log" <<'PY'
import json,sys
proj,server,log=sys.argv[1],sys.argv[2],sys.argv[3]
json.dump({"mcpServers":{"w3probe":{"command":"python3","args":[server,log,"bats"]}}},
          open(proj+"/.mcp.json","w"),indent=2)
PY
  ( cd "$proj" && CLAUDE_CONFIG_DIR="$CC_MCP_PROBE_CFG" timeout 180 "$CC_MCP_PROBE_BIN" \
      -p 'x' $extra --output-format json </dev/null >/dev/null 2>&1 || true )
  # Attribute by the recorded PARENT COMMAND, never by a bare count: a SessionStart hook in this
  # fleet runs `claude mcp list`, a flagless child CLI that health-starts every approved server and
  # lands its own START line in the same log. Counting lines would convict the session under test
  # for a spawn it did not make — and would make the negative arm unfailable in the other direction.
  python3 -c "
import json,sys
n=0
for l in open('$log'):
    d=json.loads(l)
    if d.get('ev')=='START' and ' -p ' in d.get('pcmd',''): n+=1
print(n)"
}

@test "LIVE: a default-flagged session starts NO project stdio server, --with-mcp shape DOES" {
  [ "${CC_MCP_LIVE_PROBE:-0}" = 1 ] || skip "opt-in: set CC_MCP_LIVE_PROBE=1 (+ CC_MCP_PROBE_CFG)"
  : "${CC_MCP_PROBE_CFG:=$HOME/.claude-tertiary}"
  : "${CC_MCP_PROBE_BIN:=$HOME/.claude-220/node_modules/.bin/claude}"
  export CC_MCP_PROBE_CFG CC_MCP_PROBE_BIN
  [ -x "$CC_MCP_PROBE_BIN" ] || skip "probe binary absent: $CC_MCP_PROBE_BIN"

  # POSITIVE CONTROL FIRST. If the unflagged arm does not spawn, the fixture is inert and the
  # negative arm below would "pass" while measuring nothing.
  control="$(live_probe "")"
  [ "$control" -ge 1 ]

  isolated="$(live_probe "--strict-mcp-config")"
  [ "$isolated" -eq 0 ]
}
