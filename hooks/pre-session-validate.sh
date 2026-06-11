#!/bin/bash
# pre-session-validate.sh — SessionStart hook: auto-rollback broken versions.
#
# Every time `claude` launches, this hook verifies ~/.claude-versions/current
# points at a working binary. If the current version is broken (e.g., a fresh
# npm install promoted a crashing build), it atomically re-points `current`
# to the next-highest known-good version and emits a stderr warning so the
# user knows about the fallback.
#
# This is the safety net that prevents "auto-upgrade broke my session" — the
# user always gets a working Claude even if the latest tag is broken.
#
# Kill switch: export PRE_SESSION_VALIDATE_DISABLED=1
#
# Exit codes:
#   0 — OK (session proceeds)
#   0 with stderr — rolled back (session proceeds with different version)
#   No other exits — we never block a session (fail-open).

set -euo pipefail

# Kill switch
if [[ "${PRE_SESSION_VALIDATE_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

readonly VERSIONS_DIR="$HOME/.claude-versions"
readonly LOG_FILE="$HOME/.claude/logs/pre-session-validate.log"

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Consume stdin (SessionStart hook receives JSON but we don't need it)
cat >/dev/null 2>&1 || true

# === SETTINGS MODEL PORTABILITY GUARD (2026-06-11) ===
# `/model <X>` "saved as default" writes "model" into ~/.claude/settings.json,
# which is SYMLINKED into every CLAUDE_CONFIG_DIR (next/secondary/tertiary) — so
# a window-bound frontier model (fable / claude-fable-5) saved from an eval-track
# session poisons the STABLE track: 2.1.114 can't resolve it and every plain
# `claude` launch dies with "There's an issue with the selected model".
# Frontier sessions never need the saved default (claude-fable pins --model
# explicitly), so stripping it is always safe. Self-heal + warn. Observed live
# 2026-06-11 (a /model fable save broke stable-track probes). On new frontier
# tiers, extend the case pattern via the /model-upgrade skill.
SETTINGS_FILE="$HOME/.claude/settings.json"
if [[ -f "$SETTINGS_FILE" ]] && command -v python3 >/dev/null 2>&1; then
  saved_model=$(python3 -c "import json;print(json.load(open('$SETTINGS_FILE')).get('model',''))" 2>/dev/null || echo '')
  case "$saved_model" in
    fable|claude-fable*)
      cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak-model-guard-$(date +%s)" 2>/dev/null || true
      python3 - "$SETTINGS_FILE" <<'PYEOF' 2>>"$LOG_FILE" || true
import json, os, sys, tempfile
p = sys.argv[1]
with open(p) as f:
    d = json.load(f)
d.pop('model', None)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p), prefix='.settings-model-guard-')
with os.fdopen(fd, 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write('\n')
os.replace(tmp, p)
PYEOF
      log "model guard: stripped non-portable saved model '$saved_model' from settings.json"
      echo "[pre-session-validate] stripped saved default model '$saved_model' from shared settings.json (window-bound frontier model would break the stable track; frontier launchers pin --model explicitly)." >&2
      ;;
  esac
fi

if [[ ! -L "$VERSIONS_DIR/current" ]]; then
  log "no current symlink at $VERSIONS_DIR/current — nothing to validate"
  exit 0
fi

current_target=$(readlink "$VERSIONS_DIR/current")
current_version=$(basename "$current_target")

# MANIFEST skip gate: if the currently-pointed version is flagged as skip,
# treat it as broken even if `--version` responds. Catches regressions that
# pass surface-level health checks but crash at runtime (e.g., 2.1.111/2.1.112
# getAppState). Fails forward to the rollback path below. A subsequent
# `candidate` or `stable` entry overrides an earlier `skip` (last line wins).
manifest="$VERSIONS_DIR/MANIFEST.jsonl"
manifest_skip=0
if [[ -f "$manifest" ]]; then
  status_flag=$(grep -E "\"version\":\"${current_version//./\\.}\"" "$manifest" 2>/dev/null \
    | tail -1 | sed -nE 's/.*"status":"([^"]+)".*/\1/p' || true)
  if [[ "$status_flag" == "skip" ]]; then
    manifest_skip=1
    log "current version $current_version is MANIFEST-flagged skip — forcing rollback"
    echo "[pre-session-validate] WARNING: $current_version is on MANIFEST skip-list" >&2
  fi
fi

find_binary() {
  local ver_dir="$1"
  for candidate in \
    "$ver_dir/node_modules/.bin/claude" \
    "$ver_dir/bin/claude"; do
    [[ -x "$candidate" ]] && { echo "$candidate"; return 0; }
  done
  return 1
}

current_binary="$(find_binary "$current_target" || echo '')"

# Sanity-check: binary exists, responds to --version, AND isn't MANIFEST-skip
if [[ -n "$current_binary" ]] && [[ "$manifest_skip" == 0 ]] \
   && CLAUDE_SKIP_AUTH=1 timeout 2 "$current_binary" --version >/dev/null 2>&1; then
  # Healthy — exit silently
  exit 0
fi

# BROKEN — find fallback
log "current version broken: $current_target — attempting rollback"
echo "[pre-session-validate] WARNING: $current_target failed --version check" >&2

# Find highest semver-sorted version directory that ISN'T the broken one
fallback=""
for candidate in $(ls -1 "$VERSIONS_DIR" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+' | sort -V -r); do
  candidate_path="$VERSIONS_DIR/$candidate"
  # Skip the current broken target
  [[ "$candidate_path" == "$current_target" ]] && continue
  # Skip MANIFEST-flagged (last line wins; candidate/stable overrides earlier skip)
  if [[ -f "$manifest" ]]; then
    cand_status=$(grep -E "\"version\":\"${candidate//./\\.}\"" "$manifest" 2>/dev/null \
      | tail -1 | sed -nE 's/.*"status":"([^"]+)".*/\1/p' || true)
    if [[ "$cand_status" == "skip" ]]; then
      log "fallback skip $candidate (MANIFEST status=skip)"
      continue
    fi
  fi
  # Must have a working binary
  candidate_binary="$(find_binary "$candidate_path" || echo '')"
  [[ -n "$candidate_binary" ]] || continue
  # Binary must answer --version in <2s
  if CLAUDE_SKIP_AUTH=1 timeout 2 "$candidate_binary" --version >/dev/null 2>&1; then
    fallback="$candidate_path"
    break
  fi
done

if [[ -z "$fallback" ]]; then
  log "no working fallback found — session will likely fail"
  echo "[pre-session-validate] ERROR: no working version in $VERSIONS_DIR" >&2
  exit 0  # fail-open: let the session continue and die loudly
fi

# Atomic re-point
ln -sfn "$fallback" "$VERSIONS_DIR/current"
log "rolled back: $current_target → $fallback"
echo "[pre-session-validate] reverted $(basename "$VERSIONS_DIR/current" | xargs readlink 2>/dev/null || echo "?") → $(basename "$fallback")" >&2

exit 0
