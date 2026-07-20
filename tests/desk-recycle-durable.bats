#!/usr/bin/env bats
# desk-recycle-durable.bats — the three durability guarantees of the desk self-recycle mechanism.
#
# Each test pins one of the decay paths that let waiting-recycle.sh reach 5425 abstains / 0 fires:
#   1. arm-includes-current-config   — a MIGRATED CLAUDE_CONFIG_DIR is still armed (no stranding)
#   2. live-arm-fails-loud-without-brief — a refused `--live` leaves NO half-armed SHADOW state
#   3. not-armed-decay-alarms        — an inert desk PAGES instead of abstaining silently

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WR="$REPO/hooks/waiting-recycle.sh"
  ARM="$REPO/scripts/desk-arm-live.sh"
  DRI="$REPO/scripts/desk-recycle-invariant.sh"
  TMP="$BATS_TEST_TMPDIR/t"
  mkdir -p "$TMP"
  DESK_CWD="$TMP/deskcwd"; mkdir -p "$DESK_CWD"
  BRIEF="$TMP/brief.md"; printf 'canonical desk boot brief\n' > "$BRIEF"
}

armkey() { printf '%s|%s' "$1" "$2" | shasum | cut -c1-16; }

# ── 1. arm-includes-current-config ────────────────────────────────────────────────────────────────
# The stranding bug: desk-arm-live.sh armed a hardcoded ".claude + .claude-tertiary" while the desk
# had migrated to .claude-quaternary. Discovery must cover the config the desk ACTUALLY runs under,
# including one this script has never heard of.
@test "arm-includes-current-config: a migrated CLAUDE_CONFIG_DIR is still armed" {
  local home="$TMP/home"
  local old="$home/.claude" new="$home/.claude-quinary"     # deliberately a root no code names
  mkdir -p "$old/state" "$new/state" "$home/.claude/cc-roles"
  printf 'U-DESK\n' > "$home/.claude/cc-roles/desk"

  # stub the live desk process as running under the NEW, never-hardcoded config root
  mkdir -p "$TMP/bin"
  printf '#!/bin/bash\necho 4242\n' > "$TMP/bin/pgrep"
  printf '#!/bin/bash\necho "ITERM_SESSION_ID=w1t0p0:U-DESK CLAUDE_CONFIG_DIR=%s PWD=%s"\n' "$new" "$DESK_CWD" > "$TMP/bin/ps"
  chmod +x "$TMP/bin/pgrep" "$TMP/bin/ps"

  HOME="$home" PATH="$TMP/bin:$PATH" CC_ARM_WR="$WR" CC_ARM_BRIEF="$BRIEF" \
    CC_ARM_ROLES_DIR="$home/.claude/cc-roles" \
    run "$ARM" --cwd "$DESK_CWD" --brief "$BRIEF"
  [ "$status" -eq 0 ]

  # the migrated root must carry a full LIVE arm
  local k; k="$(armkey "$new" "$DESK_CWD")"
  [ -f "$new/state/waiting-recycle/arm-$k" ]
  [ -f "$new/state/waiting-recycle/live-$k" ]
  [ -s "$new/state/waiting-recycle/brief-$k" ]

  # and discovery reported it as ground truth, not inference
  [[ "$output" == *"live desk detected under CLAUDE_CONFIG_DIR=$new"* ]]
}

@test "arm-includes-current-config: pre-existing roots are still covered (over-cover, never under-cover)" {
  local home="$TMP/home2"
  local a="$home/.claude" b="$home/.claude-tertiary"
  mkdir -p "$a/state" "$b/state" "$a/cc-roles"
  mkdir -p "$TMP/bin2"
  printf '#!/bin/bash\nexit 1\n' > "$TMP/bin2/pgrep"     # no live desk resolves
  printf '#!/bin/bash\nexit 1\n' > "$TMP/bin2/ps"
  chmod +x "$TMP/bin2/pgrep" "$TMP/bin2/ps"

  HOME="$home" PATH="$TMP/bin2:$PATH" CC_ARM_WR="$WR" CC_ARM_BRIEF="$BRIEF" \
    CC_ARM_ROLES_DIR="$a/cc-roles" \
    run "$ARM" --cwd "$DESK_CWD" --brief "$BRIEF"
  [ "$status" -eq 0 ]
  [ -f "$a/state/waiting-recycle/arm-$(armkey "$a" "$DESK_CWD")" ]
  [ -f "$b/state/waiting-recycle/arm-$(armkey "$b" "$DESK_CWD")" ]
  # an unresolvable desk is a LOUD warning, not a silent success
  [[ "$output" == *"no live desk process resolved"* ]]
}

# ── 2. live-arm-fails-loud-without-brief ──────────────────────────────────────────────────────────
# The half-success bug: `arm --live` wrote arm- BEFORE validating the brief, then refused — leaving
# the desk armed-and-SHADOW forever. A refusal must be atomic.
@test "live-arm-fails-loud-without-brief: refuses loudly AND writes no markers" {
  local cfg="$TMP/cfg1"; mkdir -p "$cfg/state"
  cd "$DESK_CWD"
  CLAUDE_CONFIG_DIR="$cfg" run "$WR" arm --live
  [ "$status" -eq 2 ]
  [[ "$output" == *"--live requires a non-empty --brief"* ]]

  # THE REGRESSION THIS PINS: no half-armed residue of any kind
  local k; k="$(armkey "$cfg" "$DESK_CWD")"
  [ ! -f "$cfg/state/waiting-recycle/arm-$k" ]
  [ ! -f "$cfg/state/waiting-recycle/live-$k" ]
  [ ! -f "$cfg/state/waiting-recycle/brief-$k" ]
}

@test "live-arm-fails-loud-without-brief: a missing --brief file leaves prior state untouched" {
  local cfg="$TMP/cfg2"; mkdir -p "$cfg/state"
  cd "$DESK_CWD"
  CLAUDE_CONFIG_DIR="$cfg" run "$WR" arm --brief "$BRIEF"   # establish a good SHADOW arm
  [ "$status" -eq 0 ]
  local k; k="$(armkey "$cfg" "$DESK_CWD")"
  [ -f "$cfg/state/waiting-recycle/arm-$k" ]

  CLAUDE_CONFIG_DIR="$cfg" run "$WR" arm --brief "$TMP/does-not-exist.md" --live
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing/empty"* ]]
  # the refusal must not have promoted the desk to a live-but-briefless state
  [ ! -f "$cfg/state/waiting-recycle/live-$k" ]
}

@test "live-arm-fails-loud-without-brief: a valid --live arm writes the complete marker set" {
  local cfg="$TMP/cfg3"; mkdir -p "$cfg/state"
  cd "$DESK_CWD"
  CLAUDE_CONFIG_DIR="$cfg" run "$WR" arm --brief "$BRIEF" --live
  [ "$status" -eq 0 ]
  local k; k="$(armkey "$cfg" "$DESK_CWD")"
  [ -f "$cfg/state/waiting-recycle/arm-$k" ]
  [ -f "$cfg/state/waiting-recycle/live-$k" ]
  [ -s "$cfg/state/waiting-recycle/brief-$k" ]
}

# ── 3. not-armed-decay-alarms ─────────────────────────────────────────────────────────────────────
# The durability guarantee: an inert mechanism must PAGE, not abstain 5425 times in silence.
@test "not-armed-decay-alarms: an unarmed desk pages and exits nonzero" {
  local case="$TMP/decay"; mkdir -p "$case/home/.claude-quaternary/state/waiting-recycle" "$case/roles" "$case/pages" "$case/bin"
  printf 'U-DESK\n' > "$case/roles/desk"
  printf '#!/bin/bash\necho 4242\n' > "$case/bin/pgrep"
  printf '#!/bin/bash\necho "ITERM_SESSION_ID=w1t0p0:U-DESK CLAUDE_CONFIG_DIR=%s PWD=%s"\n' \
    "$case/home/.claude-quaternary" "$DESK_CWD" > "$case/bin/ps"
  chmod +x "$case/bin/pgrep" "$case/bin/ps"

  DRI_ROLES_DIR="$case/roles" DRI_IDL="$case/idl.jsonl" DRI_PAGES_DIR="$case/pages" \
    DRI_NOTIFY=/usr/bin/true DRI_PUSH=/nonexistent DRI_HOME="$case/home" \
    DRI_PS="$case/bin/ps" DRI_PGREP="$case/bin/pgrep" \
    run "$DRI" --once
  [ "$status" -ne 0 ]                                   # inert ⇒ nonzero, so a host can escalate
  ls "$case/pages"/desk-recycle-not-armed-* >/dev/null 2>&1
  # the page must carry a RUNNABLE fix (silver-platter rule), not prose
  grep -q 'desk-arm-live.sh --cwd' "$case/pages"/desk-recycle-not-armed-*
  # and the sweep must be recorded either way — "didn't page" must never look like "never ran"
  grep -q '"hook":"desk-recycle-invariant"' "$case/idl.jsonl"
}

@test "not-armed-decay-alarms: the half-armed SHADOW state is caught (the observed live bug)" {
  local case="$TMP/shadow"; local cfg="$case/home/.claude-quaternary"
  mkdir -p "$cfg/state/waiting-recycle" "$case/roles" "$case/pages" "$case/bin"
  printf 'U-DESK\n' > "$case/roles/desk"
  printf '#!/bin/bash\necho 4242\n' > "$case/bin/pgrep"
  printf '#!/bin/bash\necho "ITERM_SESSION_ID=w1t0p0:U-DESK CLAUDE_CONFIG_DIR=%s PWD=%s"\n' "$cfg" "$DESK_CWD" > "$case/bin/ps"
  chmod +x "$case/bin/pgrep" "$case/bin/ps"
  : > "$cfg/state/waiting-recycle/arm-$(armkey "$cfg" "$DESK_CWD")"   # armed, but no live-/brief-

  DRI_ROLES_DIR="$case/roles" DRI_IDL="$case/idl.jsonl" DRI_PAGES_DIR="$case/pages" \
    DRI_NOTIFY=/usr/bin/true DRI_PUSH=/nonexistent DRI_HOME="$case/home" \
    DRI_PS="$case/bin/ps" DRI_PGREP="$case/bin/pgrep" \
    run "$DRI" --once
  [ "$status" -ne 0 ]
  ls "$case/pages"/desk-recycle-shadow-* >/dev/null 2>&1
}

@test "not-armed-decay-alarms: a healthy LIVE-armed desk is silent (no false page)" {
  local case="$TMP/healthy"; local cfg="$case/home/.claude-quaternary"
  mkdir -p "$cfg/state/waiting-recycle" "$case/roles" "$case/pages" "$case/bin"
  printf 'U-DESK\n' > "$case/roles/desk"
  printf '#!/bin/bash\necho 4242\n' > "$case/bin/pgrep"
  printf '#!/bin/bash\necho "ITERM_SESSION_ID=w1t0p0:U-DESK CLAUDE_CONFIG_DIR=%s PWD=%s"\n' "$cfg" "$DESK_CWD" > "$case/bin/ps"
  chmod +x "$case/bin/pgrep" "$case/bin/ps"
  local k; k="$(armkey "$cfg" "$DESK_CWD")"
  : > "$cfg/state/waiting-recycle/arm-$k"; : > "$cfg/state/waiting-recycle/live-$k"
  printf 'brief\n' > "$cfg/state/waiting-recycle/brief-$k"

  DRI_ROLES_DIR="$case/roles" DRI_IDL="$case/idl.jsonl" DRI_PAGES_DIR="$case/pages" \
    DRI_NOTIFY=/usr/bin/true DRI_PUSH=/nonexistent DRI_HOME="$case/home" \
    DRI_PS="$case/bin/ps" DRI_PGREP="$case/bin/pgrep" \
    run "$DRI" --once
  [ "$status" -eq 0 ]
  ! ls "$case/pages"/desk-recycle-* >/dev/null 2>&1
}

@test "desk-recycle-invariant --selftest is green" {
  run "$DRI" --selftest
  [ "$status" -eq 0 ]
  [[ "$output" == *"GREEN"* ]]
}
