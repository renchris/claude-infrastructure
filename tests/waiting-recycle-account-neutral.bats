#!/usr/bin/env bats
# waiting-recycle.sh — the SAFETY controls must not be a function of routing (backlog fc54aeebec4a).
#
# THE BUG: every sentinel this hook owns lives under $CLAUDE_CONFIG_DIR — twice over (STATE_DIR is
# $CLAUDE_CONFIG_DIR/state/waiting-recycle AND key_cwd/key_role hash "$CFG|…" into the filename).
# $CLAUDE_CONFIG_DIR is the ACCOUNT, and the account is chosen by the router, not the operator.
# Measured pre-fix: `arm` under one config dir → `status` under another reads "not armed"; `kill`
# under one → a session on another reads no kill at all; `clear` likewise.
#
# THE HALF UNDER TEST HERE. The arm side fails SAFE (an unseen arm does nothing) and already has an
# owner: scripts/desk-recycle-invariant.sh pages on exactly that stranding. The two SAFETY controls
# fail OPEN — `kill` calls itself the GLOBAL blanket kill-switch and `clear` the per-desk one, and a
# routing decision could step around both. Those are what this suite pins.
#
# DISCRIMINATOR PAIR (REMOVE half = the REAL pre-fix artifact from git, this same file run against a
# tree holding the pre-fix hooks/waiting-recycle.sh): tests 1, 2 and 3 RED there. Tests 4 and 5 are
# the anti-regression controls — the kill must stay undoable from either side, and the legacy
# account-scoped writes must stay byte-identical so scripts/desk-recycle-invariant.sh's own
# re-derivation of this layout keeps resolving. Both are green on BOTH sides by design.
#
# NOTE the state dir is deliberately NOT overridden: CC_WR_STATE_DIR would paper over the very
# resolution under test. Hermeticity comes from CLAUDE_CONFIG_DIR + HOME + CC_WR_COORD_DIR all being
# fixture paths, so the operator's live state is never read or written.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/waiting-recycle.sh"
  export CC_WR_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel"
  # The account-neutral root is left to its DEFAULT ($COORD/state/waiting-recycle-shared) so this
  # suite proves the default location is account-independent, not merely that a seam exists.
  export CC_WR_COORD_DIR="$BATS_TEST_TMPDIR/coord"; export CC_WR_UUID="DESK-UUID-ACCT"
  export CC_WR_T_IDLE=55 CC_WR_T_BUSY=75 CC_WR_MAX=3 CC_WR_COOLDOWN_S=600 CC_WR_AGE_MAX=180
  export CC_WR_T_NUDGE=101
  export CC_WR_NOTIFY="$BATS_TEST_TMPDIR/notify-noop.sh"
  printf '#!/bin/bash\nexit 0\n' > "$CC_WR_NOTIFY"; chmod +x "$CC_WR_NOTIFY"
  mkdir -p "$CC_TELEMETRY_DIR" "$CC_WR_COORD_DIR/cc-roles"
  # Two accounts, differing ONLY in the config dir the router hands the session.
  A="$BATS_TEST_TMPDIR/cfg-next";  mkdir -p "$A"
  B="$BATS_TEST_TMPDIR/cfg-next3"; mkdir -p "$B"
  SHARED="$CC_WR_COORD_DIR/state/waiting-recycle-shared"
  DESK="$BATS_TEST_TMPDIR/desk"; mkdir -p "$DESK"
  git -C "$BATS_TEST_TMPDIR/desk" init -q
  echo seed > "$DESK/f.txt"; git -C "$BATS_TEST_TMPDIR/desk" add -A
  git -C "$BATS_TEST_TMPDIR/desk" -c user.email=t@t -c user.name=t commit -qm init
}

# Same cwd, same operator, same command — only the routed account differs.
cli_on()   { local cfg="$1"; shift; ( cd "$DESK" && CLAUDE_CONFIG_DIR="$cfg" bash "$HOOK" "$@" ); }
drive_on() { local cfg="$1" sid="$2" tx="$BATS_TEST_TMPDIR/tx.jsonl"
  jq -nc '{type:"assistant",message:{content:[{type:"text",text:"next3 still running; waiting."}]}}' > "$tx"
  printf '{"session_id":"%s","ts":%s,"used_pct":90,"cwd":"%s"}' "$sid" "$(date +%s)" "$DESK" > "$CC_TELEMETRY_DIR/$sid.json"
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","tool_input":{"command":"echo poll"}}' \
    "$sid" "$tx" "$DESK" | CLAUDE_CONFIG_DIR="$cfg" bash "$HOOK"; }
last_reason() { jq -r '.reason' "$CC_WR_IDL" | tail -1; }

# ── DISCRIMINATORS ────────────────────────────────────────────────────────────────────────────────
@test "kill: the GLOBAL kill-switch set on one account silences a session routed to another" {
  cli_on "$A" kill >/dev/null
  run drive_on "$B" k1
  [ "$status" -eq 0 ]; [ -z "$output" ]
  # Suppressed, and the record says WHERE the kill came from — a merged token would hide that the
  # binding kill was set elsewhere.
  [ "$(last_reason)" = "global-kill:shared" ]
  [ "$(jq -r '.reason|split(":")[0]' "$CC_WR_IDL" | tail -1)" = "global-kill" ]
  # …and the account that set it is unchanged.
  run drive_on "$A" k2
  [ "$(last_reason)" = "global-kill" ]
}

@test "clear: an opt-out set on one account suppresses a session routed to another" {
  cli_on "$A" clear >/dev/null
  run drive_on "$B" c1
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(last_reason)" = "disarmed:shared" ]
  [ "$(jq -r '.reason|split(":")[0]' "$CC_WR_IDL" | tail -1)" = "disarmed" ]
  [ "$(jq -r '.disarm_src' "$CC_WR_IDL" | tail -1)" = "shared" ]
  # On the account that SET it, the local marker is what binds — reported as local, not shared.
  run drive_on "$A" c2
  [ "$(last_reason)" = "disarmed" ]
  [ "$(jq -r '.disarm_src' "$CC_WR_IDL" | tail -1)" = "local" ]
  # …and `status` on the OTHER account names it rather than reading as a hook that forgot.
  run cli_on "$B" status
  echo "$output" | grep -q "DISARMED"
  echo "$output" | grep -q "scope: every account"
}

@test "clear writes an account-neutral copy, and arm removes it (an opt-out must stay liftable)" {
  cli_on "$A" clear >/dev/null
  ls "$SHARED"/disarm-* >/dev/null                     # pre-fix: no such store exists at all
  cli_on "$A" arm >/dev/null
  # NOT `! ls …`: bash exempts a negated command from errexit, so that spelling asserts nothing.
  [ -z "$(ls "$SHARED"/disarm-* 2>/dev/null)" ]
  run drive_on "$B" a1                                  # and the far account is no longer suppressed
  [ "$(last_reason)" != "disarmed:shared" ]
}

# ── ANTI-REGRESSION CONTROLS (green on BOTH sides of the pair, deliberately) ──────────────────────
@test "control: unkill from the OTHER account lifts the kill (it must not become un-undoable)" {
  cli_on "$A" kill >/dev/null
  cli_on "$B" unkill >/dev/null
  run drive_on "$B" u1
  [[ "$(last_reason)" != global-kill* ]] || false
  run drive_on "$A" u2
  [[ "$(last_reason)" != global-kill* ]]
}

@test "control: the account-scoped writes are unchanged, so the sibling reader still resolves" {
  # scripts/desk-recycle-invariant.sh re-implements this layout (its own key_for() + reads of
  # $cfg/state/waiting-recycle/{OFF,disarm-*}). Relocating a marker would strand it and turn the
  # machine's armedness alarm into a false pager, so the legacy writes must survive verbatim.
  cli_on "$A" clear >/dev/null
  [ -n "$(ls "$A/state/waiting-recycle"/disarm-* 2>/dev/null)" ]
  cli_on "$A" kill >/dev/null
  [ -f "$A/state/waiting-recycle/OFF" ]
  # …and nothing was written into the OTHER account's store by either command.
  [ -z "$(ls "$B/state/waiting-recycle" 2>/dev/null)" ]
}
