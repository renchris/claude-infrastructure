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
  [[ "$CC_MCP_NOINHERIT_ARGS" == *"--strict-mcp-config"* ]] || false
  [[ "$CC_MCP_NOINHERIT_ARGS" == *"--mcp-config="* ]] || false
  pass="${CC_MCP_NOINHERIT_ARGS##*--mcp-config=}"
  [ -f "$pass" ]
  # the two http servers survive, the stdio one is filtered out — the whole point of the passthrough
  run jq -r '.mcpServers | keys | join(",")' "$pass"
  [ "$output" = "motion,motion-plus" ]
}

@test "an ALLOWLISTED user-scope stdio server survives the passthrough (the ms365 case)" {
  # ms365 is user-scope stdio. Before the allowlist, `select(.value.command == null)` dropped it,
  # so a session launched with --strict-mcp-config could never see it however correctly it was
  # configured in .claude.json — the bug in docs/plans/MS365_MCP_ALL_ACCOUNTS.md § Status log.
  cat > "$CFG/.claude.json" <<'JSON'
{
  "mcpServers": {
    "motion":     {"type": "http", "url": "https://example.invalid/a"},
    "ms365":      {"type": "stdio", "command": "/bin/echo", "args": []},
    "some-stdio": {"command": "/bin/echo", "args": ["hi"]}
  }
}
JSON
  # shellcheck source=/dev/null
  source "$LIB"
  cc_mcp_noinherit_args "$CFG" "$BRIEF_PLAIN"
  pass="${CC_MCP_NOINHERIT_ARGS##*--mcp-config=}"
  [ -f "$pass" ]
  run jq -r '.mcpServers | keys | join(",")' "$pass"
  # ms365 survives; the UNlisted stdio server does not — so this is an allowlist, not a blanket
  # "stdio is fine now", and the http server is untouched.
  [ "$output" = "motion,ms365" ]
}

@test "CONTROL: with an empty allowlist the stdio server is filtered out again" {
  # The mutant that must fail. `CC_MCP_USERSCOPE_STDIO_ALLOW=` reproduces the pre-2026-08-15 filter
  # exactly, pinning that the allowlist — and nothing else — is what lets ms365 through. Without
  # this case, a test asserting only "ms365 survives" would stay green if someone deleted the stdio
  # filter wholesale, which is the design this change deliberately rejected: a user-scope stdio
  # server costs ~139 MB resident per session, so the default must stay "named servers only".
  cat > "$CFG/.claude.json" <<'JSON'
{
  "mcpServers": {
    "motion": {"type": "http", "url": "https://example.invalid/a"},
    "ms365":  {"type": "stdio", "command": "/bin/echo", "args": []}
  }
}
JSON
  # shellcheck source=/dev/null
  source "$LIB"
  # Set-but-EMPTY, on its own line. The `VAR= cmd` prefix form reads as a typo to shellcheck
  # (SC1007) and, for a shell FUNCTION rather than an external command, its persistence is
  # shell-dependent — so state the intent plainly instead. The lib reads `${VAR-ms365}` with `-`,
  # which distinguishes set-empty (allow nothing) from unset (the ms365 default).
  # shellcheck disable=SC2034  # read by the SOURCED lib, which shellcheck cannot follow
  CC_MCP_USERSCOPE_STDIO_ALLOW=""
  cc_mcp_noinherit_args "$CFG" "$BRIEF_PLAIN"
  pass="${CC_MCP_NOINHERIT_ARGS##*--mcp-config=}"
  [ -f "$pass" ]
  run jq -r '.mcpServers | keys | join(",")' "$pass"
  [ "$output" = "motion" ]
}

@test "the allowlist jq must not break the http passthrough (empty-passthrough regression)" {
  # REGRESSION, caught by RUNNING the expression rather than reading it. Written as
  # `($a | index(.key))` the pipe rebinds `.` to the ARRAY, so `.key` indexes an array with a
  # string; jq dies "Cannot index array with string", the whole filter fails, `pass` stays empty,
  # and the composer falls through to BARE --strict-mcp-config — which drops every server,
  # including the http ones the passthrough exists to save. The symptom is therefore not "ms365 is
  # missing", it is "motion is missing too", so assert the flag and the http servers together.
  # shellcheck source=/dev/null
  source "$LIB"
  cc_mcp_noinherit_args "$CFG" "$BRIEF_PLAIN"
  [[ "$CC_MCP_NOINHERIT_ARGS" == *"--mcp-config="* ]] || false
  pass="${CC_MCP_NOINHERIT_ARGS##*--mcp-config=}"
  [ -f "$pass" ]
  run jq -r '.mcpServers | length' "$pass"
  [ "$output" -ge 2 ]
}

@test "ms365 is wired into every account config dir, and the wiring is idempotent" {
  # The other half of the fix: the allowlist only matters if the server is actually IN each
  # account's user-scope config. Runs against the fixtured $HOME, so it asserts the merge semantics
  # — adds one key, preserves everything else — without touching the real account dirs.
  WIRE="$REPO/scripts/ms365-mcp-wire.sh"
  [ -x "$WIRE" ]

  mkdir -p "$HOME/.claude" "$HOME/.claude-tertiary"
  cat > "$HOME/.claude/accounts.json" <<'JSON'
{"accounts":[{"name":"next","config_dir":"~/.claude-secondary","launcher":"claude"},
             {"name":"next3","config_dir":"~/.claude-tertiary","launcher":"claude3"}]}
JSON
  # .claude-secondary already carries state that MUST survive the merge; .claude-tertiary is bare.
  cat > "$HOME/.claude-secondary/.claude.json" <<'JSON'
{"numStartups": 42, "mcpServers": {"motion": {"type": "http", "url": "https://example.invalid/a"}}}
JSON
  echo '{}' > "$HOME/.claude-tertiary/.claude.json"
  echo '{}' > "$HOME/.claude/.claude.json"

  run bash "$WIRE"
  [ "$status" -eq 0 ]

  # present in both account dirs…
  run jq -r '.mcpServers.ms365.type' "$HOME/.claude-secondary/.claude.json"
  [ "$output" = "stdio" ]
  run jq -r '.mcpServers.ms365.type' "$HOME/.claude-tertiary/.claude.json"
  [ "$output" = "stdio" ]
  # …the pre-existing server and the unrelated per-account counter both survive (merge, not write)…
  run jq -r '.mcpServers.motion.url' "$HOME/.claude-secondary/.claude.json"
  [ "$output" = "https://example.invalid/a" ]
  run jq -r '.numStartups' "$HOME/.claude-secondary/.claude.json"
  [ "$output" = "42" ]

  # …and a second run is a no-op reporting success, which is what makes it safe inside install.sh.
  run bash "$WIRE" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"already correct"* ]] || false
}

@test "the passthrough uses --mcp-config=VALUE — the space form eats the prompt" {
  # REGRESSION, not styling. `--mcp-config` is variadic: `--mcp-config <path> "<prompt>"` consumes
  # the prompt as a second config path, and a real fire died on it with ENAMETOOLONG while every
  # `-p`-shaped test stayed green (a `-p` prompt is never a loose positional). Assert the shape at
  # the composer AND at the typed line, because only the typed line has a bare positional.
  # shellcheck source=/dev/null
  source "$LIB"
  cc_mcp_noinherit_args "$CFG" "$BRIEF_PLAIN"
  [[ "$CC_MCP_NOINHERIT_ARGS" != *"--mcp-config "* ]] || false
  [[ "$CC_MCP_NOINHERIT_ARGS" == *"--mcp-config="* ]] || false

  run timeout 300 bash "$FIRE" --prompt-file "$BRIEF_PLAIN" --dry-run --account next2
  [ "$status" -eq 0 ]
  cmd="$(printf '%s\n' "$output" | grep '^command:')"
  [[ "$cmd" == *"--mcp-config="* ]] || false
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
  [[ "$output" == *"--strict-mcp-config"* ]] || false
  [[ "$output" == *"mcp:      project .mcp.json stdio servers OFF"* ]]
}

@test "POSITIVE CONTROL: handoff-fire --with-mcp does NOT carry them" {
  run timeout 300 bash "$FIRE" --prompt-file "$BRIEF_PLAIN" --dry-run --account next2 --with-mcp
  [ "$status" -eq 0 ]
  [[ "$output" != *"--strict-mcp-config"* ]] || false
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
  # shellcheck disable=SC2086  # $extra is raw flag TEXT ("" or "--strict-mcp-config") and MUST word-split
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

# ── layer 4: the project .mcp.json APPROVAL decision (cc_mcp_project_decision_args) ─────────────
#
# A SEPARATE AXIS from everything above. The flags above decide which servers LOAD; these decide
# whether the fired session is ASKED. On 2026-08-15 a recycled pane carrying --strict-mcp-config
# still stalled at "2 new MCP servers found in this project" — asked to approve servers it had
# already guaranteed would not run — with its brief unread behind the modal.
#
# THE VENDOR CONTRACT THESE TESTS ENCODE, read out of the 2.1.220 binary and then MEASURED against
# it (cwd /private/tmp/mcp-decide-probe, a .mcp.json with two fake stdio servers, config dir
# .claude-tertiary):
#   no flag                                    → both "⏸ Pending approval"   ← the modal's state
#   --settings '{"disabledMcpjsonServers":…}'  → both ABSENT from mcp list, no process spawned
#   --settings '{"enabledMcpjsonServers":…}'   → both approved and actually connected to
# The first line is the positive control: without it a green negative arm would prove nothing.
# Full derivation (SZr/ny_/wB and the three rejected alternatives):
# docs/research/mcp-modal-fire-stall-2026-08-15.md and the library's own header.

_mcp_proj() {   # $1=dir — write a two-server project .mcp.json
  cat > "$1/.mcp.json" <<'JSON'
{"mcpServers": {"srvA": {"command": "/bin/echo"}, "srvB": {"type": "stdio", "command": "/bin/echo"}}}
JSON
}

@test "decision: a dir with NO .mcp.json costs no flag at all" {
  # shellcheck source=/dev/null
  source "$LIB"
  mkdir -p "$WORK/nomcp"
  cc_mcp_project_decision_args "$WORK/nomcp" off
  [ -z "$CC_MCP_DECISION_ARGS" ]
}

@test "decision: MODE=off pre-REJECTS every declared server (grants nothing)" {
  # shellcheck source=/dev/null
  source "$LIB"
  mkdir -p "$WORK/proj-off"; _mcp_proj "$WORK/proj-off"
  cc_mcp_project_decision_args "$WORK/proj-off" off
  [[ "$CC_MCP_DECISION_ARGS" == "--settings="* ]] || false
  f="${CC_MCP_DECISION_ARGS#--settings=}"
  [ -f "$f" ]
  run jq -r '.disabledMcpjsonServers | join(",")' "$f"
  [ "$output" = "srvA,srvB" ]
  # The polarity is the whole point: a rejection may never be written as an approval, or the fire
  # would GRANT a repo's servers while claiming to have isolated them.
  run jq -r 'has("enabledMcpjsonServers")' "$f"
  [ "$output" = "false" ]
}

@test "decision: MODE=on pre-APPROVES them (the --with-mcp / MCP-brief case)" {
  # shellcheck source=/dev/null
  source "$LIB"
  mkdir -p "$WORK/proj-on"; _mcp_proj "$WORK/proj-on"
  cc_mcp_project_decision_args "$WORK/proj-on" on
  f="${CC_MCP_DECISION_ARGS#--settings=}"
  run jq -r '.enabledMcpjsonServers | join(",")' "$f"
  [ "$output" = "srvA,srvB" ]
  run jq -r 'has("disabledMcpjsonServers")' "$f"
  [ "$output" = "false" ]
}

@test "decision: the two modes never share a file (an --with-mcp fire cannot read a rejection)" {
  # shellcheck source=/dev/null
  source "$LIB"
  mkdir -p "$WORK/proj-both"; _mcp_proj "$WORK/proj-both"
  cc_mcp_project_decision_args "$WORK/proj-both" off; off_f="${CC_MCP_DECISION_ARGS#--settings=}"
  cc_mcp_project_decision_args "$WORK/proj-both" on;  on_f="${CC_MCP_DECISION_ARGS#--settings=}"
  [ "$off_f" != "$on_f" ]
  run jq -r 'has("disabledMcpjsonServers")' "$off_f"; [ "$output" = "true" ]
  run jq -r 'has("enabledMcpjsonServers")'  "$on_f";  [ "$output" = "true" ]
}

@test "decision: a serverless or malformed .mcp.json emits nothing (never an empty-list flag)" {
  # shellcheck source=/dev/null
  source "$LIB"
  mkdir -p "$WORK/proj-empty"; printf '{"mcpServers":{}}\n' > "$WORK/proj-empty/.mcp.json"
  cc_mcp_project_decision_args "$WORK/proj-empty" off
  [ -z "$CC_MCP_DECISION_ARGS" ]
  mkdir -p "$WORK/proj-bad"; printf 'not json at all\n' > "$WORK/proj-bad/.mcp.json"
  cc_mcp_project_decision_args "$WORK/proj-bad" off
  [ -z "$CC_MCP_DECISION_ARGS" ]
}

@test "decision: CC_MCP_DECIDE=off restores the pre-change behaviour and SAYS so" {
  # shellcheck source=/dev/null
  source "$LIB"
  mkdir -p "$WORK/proj-ks"; _mcp_proj "$WORK/proj-ks"
  CC_MCP_DECIDE=off cc_mcp_project_decision_args "$WORK/proj-ks" off
  [ -z "$CC_MCP_DECISION_ARGS" ]
  [[ "$CC_MCP_DECISION_REASON" == *"CC_MCP_DECIDE=off"* ]] || false
}

@test "E2E: a fire into a dir carrying .mcp.json puts --settings= on the typed command" {
  mkdir -p "$WORK/e2e"; _mcp_proj "$WORK/e2e"
  printf 'x\n' > "$WORK/p.txt"
  run env CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off \
      bash "$FIRE" --prompt-file "$WORK/p.txt" --cwd "$WORK/e2e" --in-place --account next2 --dry-run
  [ "$status" -eq 0 ]
  cmd="$(printf '%s\n' "$output" | sed -n 's/^command:  //p')"
  [[ "$cmd" == *"--settings="* ]] || { echo "no --settings on: $cmd"; false; }
  # `--settings=VALUE`, never the space form — same variadic-swallow hazard --mcp-config documents.
  [[ "$cmd" != *"--settings "* ]] || false
  f="$(printf '%s' "$cmd" | sed -n 's/.*--settings=\([^ ]*\).*/\1/p')"
  run jq -r '.disabledMcpjsonServers | join(",")' "$f"
  [ "$output" = "srvA,srvB" ]
}

@test "E2E: --with-mcp flips the SAME fire to an approval, not a rejection" {
  mkdir -p "$WORK/e2e-on"; _mcp_proj "$WORK/e2e-on"
  printf 'x\n' > "$WORK/p2.txt"
  run env CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off \
      bash "$FIRE" --prompt-file "$WORK/p2.txt" --cwd "$WORK/e2e-on" --in-place --account next2 --with-mcp --dry-run
  [ "$status" -eq 0 ]
  cmd="$(printf '%s\n' "$output" | sed -n 's/^command:  //p')"
  f="$(printf '%s' "$cmd" | sed -n 's/.*--settings=\([^ ]*\).*/\1/p')"
  [ -n "$f" ] || { echo "--with-mcp fire carried no decision — it is the arm whose servers REACH the approval gate"; false; }
  run jq -r '.enabledMcpjsonServers | join(",")' "$f"
  [ "$output" = "srvA,srvB" ]
}
