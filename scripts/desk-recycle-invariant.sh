#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the selftest's `cond && okp || badp` reporter idiom (okp/badp return 0)
# shellcheck disable=SC2016  # file-wide: jq program bodies are intentionally single-quoted ($x = jq var)
# desk-recycle-invariant.sh — the desk self-recycle ARMEDNESS invariant (the anti-decay organ).
#
# WHY (the 2026-07-20 incident, disk-verified): `waiting-recycle.sh` is the desk's deterministic
# self-recycle. It fired ZERO times in its entire deployed life while logging 5425 `not-armed`
# abstains. Two independent decay paths, neither of which produced ONE signal:
#
#   (1) STRANDED — the arm sentinel is keyed by shasum("$CLAUDE_CONFIG_DIR|$PWD") under
#       $CLAUDE_CONFIG_DIR/state/waiting-recycle. The desk MIGRATED config dirs
#       (.claude-tertiary → .claude-quaternary) while `desk-arm-live.sh` still armed a hardcoded
#       ".claude + .claude-tertiary". The live desk read a config that had no arm at all.
#   (2) HALF-ARMED (SHADOW-forever) — `arm --live` wrote the arm marker BEFORE validating that a
#       --brief template existed, then refused. Result on disk under .claude-quaternary: `arm-<key>`
#       present, `live-<key>` + `brief-<key>` absent. That passes the hook's opt-in gate and reads
#       "armed" to `status`, but Stage 2 can only ever shadow-log. Armed and inert.
#
# WHY THE EXISTING ALARM CANNOT SEE THIS (idl-abstain-alarm.sh:19-27): that monitor discriminates
# BLIND (could not observe the guard ⇒ page) from DORMANT (guard reached, condition legitimately
# false ⇒ never page), and it names `waiting-recycle (not-armed)` as its canonical DORMANT example.
# That classification is CORRECT and must not change: for the ~20 builder sessions polling this hook
# every minute, `not-armed` genuinely is healthy-dormant — a builder must never self-recycle. The
# reason token is simply not decidable in isolation; it is dormant for a builder and inert for the
# desk. And decay path (2) is invisible to abstention analysis altogether, because a shadow would-fire
# logs disposition=`fired` (reason `stage2-shadow`) — the abstain-alarm scores it HEALTHY.
#
# So this check asserts the POSITIVE invariant instead of mining abstentions:
#
#     THE SESSION HOLDING THE DESK ROLE IS ARMED **LIVE** (arm + live + brief markers all present)
#     UNDER THE CONFIG DIR THAT PROCESS IS ACTUALLY RUNNING UNDER.
#
# Resolved from ground truth every sweep — cc-roles → pane uuid → live pid → that pid's OWN
# CLAUDE_CONFIG_DIR + PWD — so it is correct by construction across any future config migration.
# It cannot rot into a no-op the way a declared root list does: if it cannot resolve the desk's
# config, that is itself a RED verdict, not a silent skip.
#
# VERDICTS (each RED-proven in --selftest):
#   ok          arm + live + brief all present under the desk's real (cfg,cwd)        exit 0, no page
#   shadow      armed but NOT live (missing live- or brief-) — decay path (2)          exit 1, PAGE
#   stranded    no arm under the desk's real cfg, but armed under some OTHER cfg       exit 1, PAGE
#   not-armed   no arm anywhere for the desk cwd (and role-arm is SHADOW-only)         exit 1, PAGE
#   disarmed    operator `clear` opt-out present — legitimate, reported not paged      exit 0, no page
#   killed      global KILL switch set — legitimate, reported not paged                exit 0, no page
#   no-desk     no role file / no live desk process — desk-invariant.sh owns that      exit 0, no page
#
# DESIGN LAW (inherited from desk-invariant.sh): PAGES only. It never arms, never edits the desk,
# never execs a recycle — a check that self-heals cannot be trusted to report. Remediation is handed
# to the operator as ONE runnable command (silver-platter rule). Every branch writes an IDL record.
#
# Wired into scripts/desk-invariant.sh (already launchd-loaded via com.claude.desk-invariant.plist,
# 300s) so going live needs NO launchctl reload — deliberately, because a plist change is a C10
# operator step and this fix must not queue behind one.
#
# Modes: --once (default; live sweep, exit reflects verdict) · --report (verdict + detail, ALWAYS
#        exit 0) · --selftest (hermetic, RED-provable, side-effect-free).
# Env seams (all overridable — the override surface is what makes --selftest hermetic):
#   DRI_ROLES_DIR · DRI_ROLE · DRI_IDL · DRI_PAGES_DIR · DRI_NOTIFY · DRI_PUSH · DRI_PS ·
#   DRI_PGREP · DRI_HOME · DRI_STATE_SUBDIR · DRI_PAGE_DEDUP_S
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

ROLE="${DRI_ROLE:-desk}"
ROLES_DIR="${DRI_ROLES_DIR:-$HOME/.claude/cc-roles}"
IDL="${DRI_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
PAGES_DIR="${DRI_PAGES_DIR:-$HOME/.claude/autonomy/pages}"
NOTIFY_CMD="${DRI_NOTIFY:-}"                       # empty → builtin osascript
PUSH="${DRI_PUSH:-$HOME/.claude/hooks/push-critical.sh}"
PS_CMD="${DRI_PS:-ps}"
PGREP_CMD="${DRI_PGREP:-pgrep}"
H="${DRI_HOME:-$HOME}"
STATE_SUBDIR="${DRI_STATE_SUBDIR:-state/waiting-recycle}"
PAGE_DEDUP_S="${DRI_PAGE_DEDUP_S:-3600}"           # one page per verdict per hour (no 3am storm)
JQ="$(command -v jq 2>/dev/null || echo jq)"

# ── IDL (one record per sweep — "didn't page" must never be confusable with "never ran") ──────────
log_idl() { # $1=verdict $2=detail
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  "$JQ" -cn --arg ts "$ts" --arg v "$1" --arg d "$2" \
    '{ts:$ts,hook:"desk-recycle-invariant",disposition:$v,reason:$d}' >> "$IDL" 2>/dev/null || true
}

page() { # $1=verdict $2=message $3=remediation-command
  local marker="$PAGES_DIR/.dedup-desk-recycle-$1"
  mkdir -p "$PAGES_DIR" 2>/dev/null || true
  if [ -f "$marker" ]; then
    local age; age=$(( $(date +%s) - $(cat "$marker" 2>/dev/null || echo 0) ))
    [ "$age" -lt "$PAGE_DEDUP_S" ] 2>/dev/null && return 0
  fi
  date +%s > "$marker" 2>/dev/null || true
  # durable page file (drained by the P0-15 desk consumer)
  local pf ts_now
  ts_now="$(date +%s)"
  pf="$PAGES_DIR/desk-recycle-$1-$ts_now.md"
  {
    printf '# DESK SELF-RECYCLE INERT — %s\n\n%s\n\n' "$1" "$2"
    printf '**Fix (runnable):**\n\n```\n%s\n```\n\n' "$3"
    printf '_Detected by scripts/desk-recycle-invariant.sh. The desk self-recycle cannot fire in this state._\n'
  } > "$pf" 2>/dev/null || true
  # out-of-band (API-independent) operator surfaces
  if [ -n "$NOTIFY_CMD" ]; then "$NOTIFY_CMD" "Desk recycle INERT ($1)" "$2" >/dev/null 2>&1 || true
  else command -v osascript >/dev/null 2>&1 && \
    osascript -e "display notification \"${2//\"/}\" with title \"Desk recycle INERT (${1//\"/})\"" >/dev/null 2>&1 || true
  fi
  [ -x "$PUSH" ] && "$JQ" -cn --arg m "$2" '{message:$m}' | "$PUSH" >/dev/null 2>&1
  return 0
}

key_for() { printf '%s|%s' "$1" "$2" | shasum 2>/dev/null | cut -c1-16; }

# ── ground truth: the config dir + cwd the LIVE desk process is running under ──────────────────────
# Read from the process's OWN environment, never inferred from a list this script maintains.
resolve_desk() { # echo "<cfg>\t<cwd>\t<uuid>"; nonzero when no live desk resolves
  local uuid pid envs cfg cwd
  uuid="$(head -1 "$ROLES_DIR/$ROLE" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$uuid" ] || return 1
  for pid in $("$PGREP_CMD" -f claude 2>/dev/null); do
    envs="$("$PS_CMD" eww -p "$pid" 2>/dev/null | tr ' ' '\n')"
    printf '%s\n' "$envs" | grep -q "^ITERM_SESSION_ID=.*${uuid}$" || continue
    cfg="$(printf '%s\n' "$envs" | grep '^CLAUDE_CONFIG_DIR=' | head -1)"; cfg="${cfg#CLAUDE_CONFIG_DIR=}"
    cwd="$(printf '%s\n' "$envs" | grep '^PWD=' | head -1)";               cwd="${cwd#PWD=}"
    [ -n "$cfg" ] || cfg="$H/.claude"                  # unset ⇒ the CC default root
    [ -n "$cwd" ] || return 1
    printf '%s\t%s\t%s\n' "$cfg" "$cwd" "$uuid"; return 0
  done
  return 1
}

# any OTHER config root that holds an arm for this cwd (distinguishes stranded from never-armed)
other_armed_cfgs() { # $1=cwd  $2=cfg-to-exclude
  local c k
  for c in "$H"/.claude*; do
    [ -d "$c" ] || continue
    [ "$c" = "$2" ] && continue
    k="$(key_for "$c" "$1")"
    [ -f "$c/$STATE_SUBDIR/arm-$k" ] && printf '%s ' "$c"
  done
}

evaluate() {
  local resolved cfg cwd uuid sd k verdict detail fix others
  if ! resolved="$(resolve_desk)"; then
    verdict=no-desk
    detail="no live desk process resolves from $ROLES_DIR/$ROLE (desk-invariant.sh owns desk existence)"
    log_idl "$verdict" "$detail"; printf 'desk-recycle-invariant: %s — %s\n' "$verdict" "$detail"; return 0
  fi
  IFS=$'\t' read -r cfg cwd uuid <<< "$resolved"
  sd="$cfg/$STATE_SUBDIR"; k="$(key_for "$cfg" "$cwd")"

  # operator opt-outs are legitimate quiet states, never a page
  if [ -f "$sd/OFF" ]; then
    verdict=killed; detail="global KILL switch set ($sd/OFF) — operator opt-out"
    log_idl "$verdict" "$detail"; printf 'desk-recycle-invariant: %s — %s\n' "$verdict" "$detail"; return 0
  fi
  if [ -f "$sd/disarm-$k" ]; then
    verdict=disarmed; detail="per-desk disarm marker present (cfg=$cfg cwd=$cwd) — operator opt-out"
    log_idl "$verdict" "$detail"; printf 'desk-recycle-invariant: %s — %s\n' "$verdict" "$detail"; return 0
  fi

  fix="\$HOME/.claude/scripts/desk-arm-live.sh --cwd $cwd"
  if [ ! -f "$sd/arm-$k" ]; then
    others="$(other_armed_cfgs "$cwd" "$cfg" | sed 's/ $//')"
    if [ -n "$others" ]; then
      verdict=stranded
      detail="desk runs under cfg=$cfg but its arm lives under: $others (cwd=$cwd, key=$k) — config migration stranded the sentinel"
    else
      verdict=not-armed
      detail="no arm sentinel for the desk under ANY config root (cfg=$cfg cwd=$cwd key=$k)"
    fi
  elif [ ! -s "$sd/brief-$k" ] || [ ! -f "$sd/live-$k" ]; then
    verdict=shadow
    local miss=""
    [ -f "$sd/live-$k" ]  || miss="live-$k"
    [ -s "$sd/brief-$k" ] || miss="${miss:+$miss + }brief-$k"
    detail="desk is ARMED but SHADOW-only under cfg=$cfg (missing: $miss) — Stage 2 can never exec"
  else
    verdict=ok
    detail="armed LIVE under cfg=$cfg cwd=$cwd (arm+live+brief present, key=$k)"
    log_idl "$verdict" "$detail"; printf 'desk-recycle-invariant: %s — %s\n' "$verdict" "$detail"; return 0
  fi

  log_idl "$verdict" "$detail"
  printf 'desk-recycle-invariant: %s — %s\n' "$verdict" "$detail" >&2
  page "$verdict" "Desk self-recycle is INERT ($verdict): $detail" "$fix"
  return 1
}

# ── selftest: hermetic, RED-provable ──────────────────────────────────────────────────────────────
selftest() {
  local d PASS=0 FAIL=0
  # NOTE: the cleanup path must reference a GLOBAL — an EXIT trap runs after the function frame is
  # gone, so a `local` d is unbound there and `set -u` turns cleanup into a spurious error exit.
  d="$(mktemp -d)"; _DRI_TMP="$d"; trap 'rm -rf "${_DRI_TMP:-}"' EXIT
  okp()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
  badp() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

  # stub ps/pgrep so a fake "desk process" resolves with a chosen cfg + cwd
  mk_stubs() { # $1=case-dir $2=uuid $3=cfg $4=cwd
    mkdir -p "$1/bin" "$1/roles" "$1/pages"
    printf '%s\n' "$2" > "$1/roles/$ROLE"
    cat > "$1/bin/pgrep" <<'EOF'
#!/bin/bash
echo 4242
EOF
    cat > "$1/bin/ps" <<EOF
#!/bin/bash
echo "ITERM_SESSION_ID=w1t0p0:$2 CLAUDE_CONFIG_DIR=$3 PWD=$4"
EOF
    chmod +x "$1/bin/pgrep" "$1/bin/ps"
  }
  run_case() { # $1=case-dir  → echoes verdict, preserves exit code in $rc
    local out rc
    out="$( DRI_ROLES_DIR="$1/roles" DRI_IDL="$1/idl.jsonl" DRI_PAGES_DIR="$1/pages" \
            DRI_NOTIFY="/usr/bin/true" DRI_PUSH="/nonexistent" DRI_HOME="$1/home" \
            DRI_PS="$1/bin/ps" DRI_PGREP="$1/bin/pgrep" "$SELF" --once 2>&1 )"; rc=$?
    printf '%s\n' "$out" >/dev/null
    "$JQ" -r '.disposition' "$1/idl.jsonl" 2>/dev/null | tail -1
    return $rc
  }
  armkey() { printf '%s|%s' "$1" "$2" | shasum | cut -c1-16; }

  local U=U-DESK CWD=/desk/cwd

  # 1. ok — arm + live + brief present under the cfg the desk actually runs under
  local c1="$d/ok" cfg1
  cfg1="$c1/home/.claude-quaternary"; mkdir -p "$cfg1/$STATE_SUBDIR"
  mk_stubs "$c1" "$U" "$cfg1" "$CWD"
  local k1; k1="$(armkey "$cfg1" "$CWD")"
  : > "$cfg1/$STATE_SUBDIR/arm-$k1"; : > "$cfg1/$STATE_SUBDIR/live-$k1"; echo brief > "$cfg1/$STATE_SUBDIR/brief-$k1"
  [ "$(run_case "$c1")" = ok ] && okp "ok: fully-armed desk verdicts ok" || badp "ok: verdict=$(run_case "$c1")"
  ls "$c1/pages"/desk-recycle-* >/dev/null 2>&1 && badp "ok: paged on a healthy desk" || okp "ok: no page"

  # 2. shadow — the HALF-ARMED state (arm present, live+brief absent). MUST page.
  local c2="$d/shadow" cfg2
  cfg2="$c2/home/.claude-quaternary"; mkdir -p "$cfg2/$STATE_SUBDIR"
  mk_stubs "$c2" "$U" "$cfg2" "$CWD"
  : > "$cfg2/$STATE_SUBDIR/arm-$(armkey "$cfg2" "$CWD")"
  [ "$(run_case "$c2")" = shadow ] && okp "shadow: half-armed (arm w/o live+brief) verdicts shadow" || badp "shadow: verdict=$(run_case "$c2")"
  ls "$c2/pages"/desk-recycle-shadow-* >/dev/null 2>&1 && okp "shadow: PAGED" || badp "shadow: did NOT page"

  # 3. stranded — armed under a DIFFERENT config than the desk runs under (the migration bug). MUST page.
  local c3="$d/stranded" cfg3 old3
  cfg3="$c3/home/.claude-quaternary"; old3="$c3/home/.claude-tertiary"
  mkdir -p "$cfg3/$STATE_SUBDIR" "$old3/$STATE_SUBDIR"
  mk_stubs "$c3" "$U" "$cfg3" "$CWD"
  local k3; k3="$(armkey "$old3" "$CWD")"
  : > "$old3/$STATE_SUBDIR/arm-$k3"; : > "$old3/$STATE_SUBDIR/live-$k3"; echo brief > "$old3/$STATE_SUBDIR/brief-$k3"
  [ "$(run_case "$c3")" = stranded ] && okp "stranded: arm under a stale cfg verdicts stranded" || badp "stranded: verdict=$(run_case "$c3")"
  ls "$c3/pages"/desk-recycle-stranded-* >/dev/null 2>&1 && okp "stranded: PAGED" || badp "stranded: did NOT page"

  # 4. not-armed — no arm anywhere. MUST page.
  local c4="$d/none" cfg4
  cfg4="$c4/home/.claude-quaternary"; mkdir -p "$cfg4/$STATE_SUBDIR"
  mk_stubs "$c4" "$U" "$cfg4" "$CWD"
  [ "$(run_case "$c4")" = not-armed ] && okp "not-armed: no arm anywhere verdicts not-armed" || badp "not-armed: verdict=$(run_case "$c4")"
  ls "$c4/pages"/desk-recycle-not-armed-* >/dev/null 2>&1 && okp "not-armed: PAGED" || badp "not-armed: did NOT page"

  # 5. disarmed — operator opt-out is quiet (no page), proving the check does not nag a deliberate off
  local c5="$d/disarmed" cfg5
  cfg5="$c5/home/.claude-quaternary"; mkdir -p "$cfg5/$STATE_SUBDIR"
  mk_stubs "$c5" "$U" "$cfg5" "$CWD"
  : > "$cfg5/$STATE_SUBDIR/disarm-$(armkey "$cfg5" "$CWD")"
  [ "$(run_case "$c5")" = disarmed ] && okp "disarmed: operator opt-out verdicts disarmed" || badp "disarmed: verdict=$(run_case "$c5")"
  ls "$c5/pages"/desk-recycle-* >/dev/null 2>&1 && badp "disarmed: paged an operator opt-out" || okp "disarmed: no page"

  # 6. no-desk — no role file at all → quiet skip (desk-invariant.sh owns desk existence)
  local c6="$d/nodesk"; mkdir -p "$c6/home" "$c6/roles" "$c6/pages" "$c6/bin"
  mk_stubs "$c6" "$U" "$c6/home/.claude" "$CWD"; rm -f "$c6/roles/$ROLE"
  [ "$(run_case "$c6")" = no-desk ] && okp "no-desk: unresolvable desk verdicts no-desk" || badp "no-desk: verdict=$(run_case "$c6")"
  ls "$c6/pages"/desk-recycle-* >/dev/null 2>&1 && badp "no-desk: paged (desk-invariant.sh owns this)" || okp "no-desk: no page"

  printf 'desk-recycle-invariant --selftest: %d passed, %d failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "desk-recycle-invariant --selftest: GREEN — ok/shadow/stranded/not-armed/disarmed/no-desk all RED-proven."
}

case "${1:-}" in
  --selftest) selftest ;;
  --report)   evaluate || true ;;
  ""|--once)  evaluate ;;
  *)          printf 'desk-recycle-invariant: unknown arg %s (use --once | --report | --selftest)\n' "$1" >&2; exit 2 ;;
esac
