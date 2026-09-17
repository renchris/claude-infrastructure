#!/bin/bash
# effort-parity-assert.sh — assert the effort that surfaces ACTUALLY resolve matches the SSOT's
# declared effort_defaults (model-config.yaml). The scalar-key analogue of deploy-parity-assert.sh.
#
# Why: model-config.yaml claimed a "settings floor" of xhigh "symlinked into every CLAUDE_CONFIG_DIR".
# Disk truth (2026-07-24): the five settings.json are FIVE INDEPENDENT REAL files (zero symlinks) and
# had drifted BELOW the floor — ~/.claude=high, ~/.claude-{next,secondary,tertiary,quaternary}=low. So
# every teammate pane and every non-`--effort` surface on the four accounts silently resolved `low`,
# not the declared floor, and NOTHING caught it: claude-lint-models.sh is a model-id text lint (passes
# clean) and settings-drift-assert.sh compares only permissions.{deny,ask} + hooks — no scalar keys.
#
# Compares the SSOT's effort_defaults against three surfaces:
#   (b) settings.json "effortLevel" in every CLAUDE_CONFIG_DIR  — GATING: below the declared floor = drift.
#   (a) the MODERN launcher `claude()`'s --effort default in ~/.zshrc — GATING: != SSOT default = drift.
#       Its knob is ${CLAUDE_EFFORT:-${CLAUDE_OPUS5_EFFORT:-<v>}}. The legacy `claude-prev` track's
#       CLAUDE_DEFAULT_EFFORT is a SEPARATE knob by design and is reported NON-gating (see § (a) below).
#   (c) live `ps -eo command` claude sessions carrying --effort <v> — REPORT-ONLY: below-floor sessions are
#       SURFACED (⚠) but do NOT gate, because /effort legitimately re-tiers a live session; the DURABLE
#       drift is the static config, which is what silently resolves every non-wrapped surface. Set
#       CC_EFFORT_PS_STRICT=1 to make live below-floor sessions gate too.
#
# READ-ONLY: compares and reports. It NEVER edits any settings.json (an authority-ceiling / class-C
# surface — realigning the five files is the operator step, not this script), the zshrc, or any session.
# Exit 0 = parity · 1 = drift (a surface resolves below the floor / launcher default) · 3 = missing
# prerequisite (SSOT unreadable). Covered by tests/effort-parity.bats, fully hermetic via
# CC_EFFORT_SSOT / CC_EFFORT_DIRS / CC_EFFORT_ZSHRC / CC_EFFORT_PS / CC_EFFORT_PS_STRICT.
set -uo pipefail

# --- SSOT: the deployed live model-config.yaml, else this checkout's copy ---
# Post-consolidation (audit 02) both paths are the SAME FILE: model-config.yaml lives at the repo
# root (the one versioned SSOT, alongside accounts.json) and ~/.claude/model-config.yaml is a
# symlink to it, created by install.sh. The fallback matters only before that link exists — it used
# to point at templates/model-config.yaml, a SECOND copy that also claimed SSOT and had drifted.
SSOT="${CC_EFFORT_SSOT:-}"
if [ -z "$SSOT" ]; then
  if [ -f "$HOME/.claude/model-config.yaml" ]; then
    SSOT="$HOME/.claude/model-config.yaml"
  else
    _self_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    SSOT="$_self_root/model-config.yaml"
  fi
fi
DIRS="${CC_EFFORT_DIRS:-$HOME/.claude $HOME/.claude-next $HOME/.claude-secondary $HOME/.claude-tertiary $HOME/.claude-quaternary}"
ZSHRC="${CC_EFFORT_ZSHRC:-$HOME/.zshrc}"
PS_STRICT="${CC_EFFORT_PS_STRICT:-0}"

if [ ! -f "$SSOT" ]; then
  printf 'effort-parity-assert: SSOT model-config.yaml not readable (%s) — cannot assert.\n' "$SSOT" >&2
  exit 3
fi

# effort_defaults.<key> → its value within the `effort_defaults:` block (trailing comment stripped).
ssot_val() {
  awk -v k="$1" '
    /^effort_defaults:/ { inblk=1; next }
    inblk && /^[^[:space:]#]/ { inblk=0 }
    inblk {
      line=$0; sub(/#.*/, "", line)
      if (match(line, "^[[:space:]]+" k ":[[:space:]]*")) {
        v=substr(line, RLENGTH+1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); print v; exit
      }
    }' "$SSOT"
}
# low < medium < high < xhigh < max  → 1..5; unknown → 0.
effort_ord() {
  case "$1" in
    low) echo 1 ;; medium) echo 2 ;; high) echo 3 ;; xhigh) echo 4 ;; max) echo 5 ;; *) echo 0 ;;
  esac
}
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

FLOOR="$(ssot_val settings_floor)";  FLOOR="${FLOOR:-xhigh}"
LAUNCHER="$(ssot_val default)";      LAUNCHER="${LAUNCHER:-max}"
FLOOR_ORD="$(effort_ord "$FLOOR")"

drift=0
report() { printf '  %-9s %-32s %s\n' "$1" "$2" "$3"; }
printf 'effort-parity-assert: SSOT floor=%s launcher-default=%s\n  (%s)\n' "$FLOOR" "$LAUNCHER" "$SSOT"

# --- (b) settings.json effortLevel floor across every CLAUDE_CONFIG_DIR — GATING ---
for d in $DIRS; do
  f="$d/settings.json"
  name="$(basename "$d")/settings.json"
  if [ ! -f "$f" ]; then
    report "SKIP" "$name" "no settings.json at $d"
    continue
  fi
  lvl="$(lc "$(grep -oE '"effortLevel"[[:space:]]*:[[:space:]]*"[A-Za-z]+"' "$f" | head -1 | sed -E 's/.*"([A-Za-z]+)"[[:space:]]*$/\1/')")"
  if [ -z "$lvl" ]; then
    report "NOFLOOR" "$name" "no effortLevel key → binary default, NOT the $FLOOR floor"
    drift=1
    continue
  fi
  if [ "$(effort_ord "$lvl")" -lt "$FLOOR_ORD" ]; then
    report "BELOW" "$name" "effortLevel=$lvl < floor $FLOOR → non-wrapped surfaces resolve $lvl"
    drift=1
  else
    report "OK" "$name" "effortLevel=$lvl >= floor $FLOOR"
  fi
done

# --- (a) zshrc launcher --effort default — GATING ---
# 🚨 THE MODERN LAUNCHER IS `claude()` AND IT READS `CLAUDE_EFFORT`, NEVER `CLAUDE_DEFAULT_EFFORT`.
# ~/.zshrc states it outright: "CLAUDE_DEFAULT_EFFORT is deliberately NOT read (it is the stable
# track's knob)". Until 2026-09-16 this check grepped the FIRST `CLAUDE_DEFAULT_EFFORT:-<v>` in the
# file — which is a COMMENT in the header — and compared the LEGACY `claude-prev` track's `max`
# against the SSOT floor. It therefore reported DRIFT forever against a launcher that was already
# correct, i.e. it convicted a launcher for a variable that launcher does not read. A guard that
# reds on the correct value trains you to ignore it, and model-config.yaml:800-805 records that
# exact lesson about this exact script — the second instance, so read this one as a pattern.
# MEASURED 2026-09-16: claude() resolves ${CLAUDE_EFFORT:-${CLAUDE_OPUS5_EFFORT:-high}} = high =
# the SSOT floor. Record: docs/research/fable51-vs-opus5-routing-2026-09-16/.
if [ -f "$ZSHRC" ]; then
  # Comment lines are excluded on BOTH greps: each literal appears in the header prose as well as
  # in code, and `head -1` over an unfiltered file reaches the prose first.
  zdef="$(lc "$(grep -vE '^[[:space:]]*#' "$ZSHRC" \
          | grep -oE 'CLAUDE_EFFORT:-\$\{CLAUDE_OPUS5_EFFORT:-[A-Za-z]+' \
          | head -1 | sed 's/.*-//')")"
  if [ -z "$zdef" ]; then
    report "SKIP" "zshrc launcher" "no CLAUDE_EFFORT default found in $ZSHRC (claude() may have been renamed — re-derive before trusting this SKIP)"
  elif [ "$zdef" != "$(lc "$LAUNCHER")" ]; then
    report "DRIFT" "zshrc launcher" "claude() --effort default {CLAUDE_EFFORT:-{CLAUDE_OPUS5_EFFORT:-$zdef}} != SSOT $LAUNCHER"
    drift=1
  else
    report "OK" "zshrc launcher" "claude() --effort default = $LAUNCHER"
  fi
  # NON-GATING: the legacy `claude-prev` (stable 2.1.114) track keeps its own knob, deliberately.
  # Reported so a reader can see it is DIFFERENT ON PURPOSE rather than rediscovering it as drift.
  ldef="$(lc "$(grep -vE '^[[:space:]]*#' "$ZSHRC" | grep -oE 'CLAUDE_DEFAULT_EFFORT:-[A-Za-z]+' | head -1 | sed 's/.*-//')")"
  [ -n "$ldef" ] && report "NOTE" "zshrc claude-prev" "legacy track {CLAUDE_DEFAULT_EFFORT:-$ldef} — separate knob by design, not gated"
else
  report "SKIP" "zshrc launcher" "no zshrc at $ZSHRC"
fi

# --- (c) live `ps` claude sessions carrying --effort — REPORT-ONLY (gates only under PS_STRICT) ---
if [ -n "${CC_EFFORT_PS:-}" ] && [ -f "${CC_EFFORT_PS:-}" ]; then
  ps_out="$(cat "$CC_EFFORT_PS")"
else
  ps_out="$(ps -eo command= 2>/dev/null || true)"
fi
while IFS= read -r line; do
  case "$line" in
    *claude*--effort*) : ;;
    *) continue ;;
  esac
  eff="$(lc "$(printf '%s' "$line" | sed -nE 's/.*--effort[ =]+([A-Za-z]+).*/\1/p')")"
  [ -n "$eff" ] || continue
  if [ "$(effort_ord "$eff")" -lt "$FLOOR_ORD" ]; then
    report "PS-WARN" "live session" "--effort $eff < floor $FLOOR (re-tier via /effort or restart)"
    [ "$PS_STRICT" = 1 ] && drift=1
  fi
done <<EOF
$ps_out
EOF

if [ "$drift" -ne 0 ]; then
  printf '\neffort-parity-assert: DRIFT — a surface resolves effort BELOW the SSOT floor.\n' >&2
  printf 'The five settings.json are an authority-ceiling (class-C) surface: realigning them is the\noperator step, not this script.\n' >&2
  exit 1
fi
printf '\neffort-parity-assert: parity — every gating surface meets the SSOT floor.\n'
exit 0
