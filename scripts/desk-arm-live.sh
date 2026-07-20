#!/usr/bin/env bash
# desk-arm-live.sh — arm the monitoring desk's waiting-recycle DETERMINISTIC auto-recycle in LIVE
# mode, DURABLY and idempotently. This is the go-live actuator for `waiting-recycle.sh` Stage 2.
#
# Usage: desk-arm-live.sh [--cwd <desk-dir>] [--brief <file>] [--shadow] [--dry-run]
#   --cwd    desk working dir to arm (default: the repo ~/.claude symlinks from — the desk's home)
#   --brief  Stage-2 successor-prompt template (default: <repo>/docs/templates/desk-boot-brief.md)
#   --shadow arm SHADOW (log would-fire, no exec) instead of LIVE — for a soak-first go-live
#   --dry-run print what it would arm, change nothing
#
# WHY THIS EXISTS (the CFG-stranding root cause, disk-verified 2026-07-19):
#   `waiting-recycle.sh arm` keys its sentinel by shasum("$CLAUDE_CONFIG_DIR|$PWD") and writes it
#   under "$CLAUDE_CONFIG_DIR/state/waiting-recycle". So an arm is only visible to a desk running
#   under the SAME config dir. The desk MIGRATES config dirs across a recycle (observed
#   .claude-tertiary -> .claude in ~2 days) and its state dir can be wiped — either strands the arm
#   under a CONFIG THE LIVE DESK NEVER CHECKS. A stranded arm makes the hook silently abstain
#   `not-armed` on every poll (1309 such abstains observed; 0 shadow fires) — the mechanism decays to
#   a no-op with NO signal, which reintroduces the human-in-the-loop dependency the auto-recycle
#   exists to remove. A one-shot manual `arm` re-strands on the next migration.
#
#   Fix: arm the desk cwd under EVERY config dir it may run under — DISCOVERED at arm time (all
#   $HOME/.claude* config roots + this process's $CLAUDE_CONFIG_DIR + the config the LIVE DESK PROCESS
#   is actually running under, read from its environment), never a hardcoded list. See the
#   CONFIG-ROOT DISCOVERY block below for why a declared list re-strands on every migration.
#   Arming a (cfg, cwd) where no monitoring desk runs is harmless — the hook fires ONLY for a session
#   whose own (cfg, cwd) matches AND is a monitoring desk that trips the trigger; a stray sentinel with
#   no such session never fires. So this over-covers safely and is re-runnable (self-heals a wipe or a
#   migration). The desk cwd is resolved from the ~/.claude symlink source, so it is machine-portable.
#
# LANDMINE-SAFE: `waiting-recycle.sh arm` itself preserves the cross-generation loop-breaker — a
#   RE-arm of an already-armed cwd does NOT clear its cooldown (only a fresh opt-in does). So this
#   helper is safe to re-run by anyone, including a successor desk on boot: the loop-breaker survives.
#   `--live` is refused by the CLI unless a non-empty --brief template exists (FM-D: no task-less fire).
#
# KILL SWITCHES (unchanged): per-desk `waiting-recycle.sh clear` (from the desk cwd) ·
#   global `waiting-recycle.sh kill`. This helper never touches those.
#
# Env seams (tests): CC_ARM_WR (waiting-recycle.sh path) · CC_ARM_CFGS (space-separated config roots —
#   OVERRIDES discovery entirely) · CC_ARM_BRIEF (brief template) · CC_ARM_HOOK (installed hook used to
#   resolve the default cwd) · CC_ARM_ROLES_DIR + CC_ARM_DESK_ROLE (live-desk config detection)
set -uo pipefail

SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"

# The waiting-recycle.sh CLI we delegate to (repo copy next to us, else the installed hook).
WR="${CC_ARM_WR:-$SELF_DIR/../hooks/waiting-recycle.sh}"
[ -x "$WR" ] || WR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/waiting-recycle.sh"

# Installed hook (a symlink into the main checkout) — its target's grandparent is the desk's cwd.
HOOK="${CC_ARM_HOOK:-$HOME/.claude/hooks/waiting-recycle.sh}"

resolve_desk_cwd() { # echo the repo that HOOK symlinks from, or nothing
  local tgt
  [ -e "$HOOK" ] || return 1
  tgt="$(readlink "$HOOK" 2>/dev/null || echo "$HOOK")"
  case "$tgt" in /*) ;; *) tgt="$(dirname "$HOOK")/$tgt" ;; esac   # relativize a relative link
  ( cd "$(dirname "$tgt")/.." 2>/dev/null && pwd )
}

CWD="" ; BRIEF="" ; MODE_FLAG="--live" ; MODE="LIVE" ; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --cwd)     CWD="${2:?--cwd needs a dir}"; shift 2 ;;
    --brief)   BRIEF="${2:?--brief needs a file}"; shift 2 ;;
    --shadow)  MODE_FLAG=""; MODE="SHADOW"; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "desk-arm-live: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$CWD" ]   || CWD="$(resolve_desk_cwd || true)"
[ -n "$CWD" ]   || { echo "desk-arm-live: could not resolve desk cwd (pass --cwd)" >&2; exit 2; }
[ -d "$CWD" ]   || { echo "desk-arm-live: desk cwd not a directory: $CWD" >&2; exit 2; }
CWD="$(cd "$CWD" && pwd)"                                        # canonicalize
[ -n "$BRIEF" ] || BRIEF="${CC_ARM_BRIEF:-$CWD/docs/templates/desk-boot-brief.md}"
case "$BRIEF" in /*) ;; *) BRIEF="$(cd "$(dirname "$BRIEF")" 2>/dev/null && pwd)/$(basename "$BRIEF")" ;; esac
{ [ -f "$BRIEF" ] && [ -s "$BRIEF" ]; } || { echo "desk-arm-live: brief missing/empty: $BRIEF" >&2; exit 2; }
[ -x "$WR" ]    || { echo "desk-arm-live: waiting-recycle.sh not executable: $WR" >&2; exit 2; }

# ── CONFIG-ROOT DISCOVERY (migration-proof, 2026-07-20) ───────────────────────────────────────────
# A HARDCODED root list is the stranding bug itself. The prior default was
# "$HOME/.claude $HOME/.claude-tertiary"; the desk had since migrated to $HOME/.claude-quaternary, so
# re-running this actuator armed two configs the live desk never reads and left the real one untouched
# — 5425 `not-armed` abstains, 0 fires. Any future `.claude-quinary` would strand it again identically.
# So the set is DISCOVERED, never declared, from three independent sources (union, deduped):
#   (a) every $HOME/.claude* that is actually a config root (has state/ or projects/ or settings.json)
#   (b) $CLAUDE_CONFIG_DIR of THIS process — the config the arming session itself runs under
#   (c) the config dir the LIVE DESK PROCESS is running under, read from its own environment
# (c) is the load-bearing one: it is ground truth rather than inference, so the desk's *actual* config
# is covered even if it migrated somewhere this script has never heard of and (a) somehow misses it.
# Over-covering is harmless by construction (see LANDMINE-SAFE above): the hook fires only for a
# session whose own (cfg,cwd) matches AND which holds the desk role, so a sentinel with no matching
# session is inert. Under-covering is the failure that costs a day. CC_ARM_CFGS still overrides (tests).

resolve_desk_cfg() { # echo the CLAUDE_CONFIG_DIR of the live process holding the desk role, if any
  local roles_dir="${CC_ARM_ROLES_DIR:-$HOME/.claude/cc-roles}" role="${CC_ARM_DESK_ROLE:-desk}"
  local uuid pid env_cfg
  uuid="$(head -1 "$roles_dir/$role" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$uuid" ] || return 1
  # find the claude process whose iTerm pane uuid matches the registered desk role
  for pid in $(pgrep -f claude 2>/dev/null); do
    ps eww -p "$pid" 2>/dev/null | tr ' ' '\n' | grep -q "^ITERM_SESSION_ID=.*${uuid}$" || continue
    env_cfg="$(ps eww -p "$pid" 2>/dev/null | tr ' ' '\n' | grep '^CLAUDE_CONFIG_DIR=' | head -1)"
    env_cfg="${env_cfg#CLAUDE_CONFIG_DIR=}"
    [ -n "$env_cfg" ] && { printf '%s\n' "$env_cfg"; return 0; }
    printf '%s\n' "$HOME/.claude"; return 0            # unset env ⇒ the CC default root
  done
  return 1
}

discover_cfg_roots() {
  local c
  for c in "$HOME"/.claude*; do                        # (a) every plausible config root on disk
    [ -d "$c" ] || continue
    { [ -d "$c/state" ] || [ -d "$c/projects" ] || [ -f "$c/settings.json" ]; } && printf '%s\n' "$c"
  done
  [ -n "${CLAUDE_CONFIG_DIR:-}" ] && [ -d "$CLAUDE_CONFIG_DIR" ] && printf '%s\n' "$CLAUDE_CONFIG_DIR"   # (b)
  resolve_desk_cfg || true                             # (c) ground truth: the live desk's own config
}

if [ -n "${CC_ARM_CFGS:-}" ]; then
  IFS=' ' read -r -a CFG_ROOTS <<< "$CC_ARM_CFGS"
else
  DESK_CFG="$(resolve_desk_cfg || true)"
  # canonicalize + dedupe, order-stable
  IFS=$'\n' read -r -d '' -a CFG_ROOTS < <(
    discover_cfg_roots | while read -r c; do (cd "$c" 2>/dev/null && pwd); done | awk '!seen[$0]++'
    printf '\0'
  )
  [ "${#CFG_ROOTS[@]}" -gt 0 ] || { echo "desk-arm-live: discovered NO config roots under $HOME (expected at least $HOME/.claude)" >&2; exit 2; }
  if [ -n "$DESK_CFG" ]; then
    echo "desk-arm-live: live desk detected under CLAUDE_CONFIG_DIR=$DESK_CFG"
  else
    echo "desk-arm-live: WARNING — no live desk process resolved from cc-roles; arming discovered roots only." >&2
    echo "desk-arm-live: WARNING — if the desk later boots under a NEW config root, re-run this actuator." >&2
  fi
fi

echo "desk-arm-live: cwd=$CWD"
echo "desk-arm-live: brief=$BRIEF ($(wc -l < "$BRIEF" | tr -d ' ') lines)"
echo "desk-arm-live: mode=$MODE  configs=${CFG_ROOTS[*]}"

rc=0
for cfg in "${CFG_ROOTS[@]}"; do
  key="$(printf '%s|%s' "$cfg" "$CWD" | shasum 2>/dev/null | cut -c1-16)"
  if [ "$DRY" = 1 ]; then
    echo "  [dry-run] would arm $MODE → $cfg/state/waiting-recycle/arm-$key"
    continue
  fi
  # Delegate to the CLI with the desk's cwd as PWD and this config dir as CLAUDE_CONFIG_DIR, so the
  # sentinel lands on the exact (cfg, cwd) key the desk's own hook invocation will look up.
  if out="$( cd "$CWD" && CLAUDE_CONFIG_DIR="$cfg" "$WR" arm --brief "$BRIEF" ${MODE_FLAG:+$MODE_FLAG} 2>&1 )"; then
    echo "  ✓ $cfg → arm-$key ($MODE): $out"
  else
    echo "  ✗ $cfg → arm-$key FAILED: $out" >&2
    rc=1
  fi
done

[ "$DRY" = 1 ] && { echo "desk-arm-live: dry-run only, nothing changed"; exit 0; }
[ "$rc" = 0 ] && echo "desk-arm-live: done — desk auto-recycle is $MODE across ${#CFG_ROOTS[@]} config root(s). Kill: waiting-recycle.sh clear (per-desk) / kill (global)."
exit "$rc"
