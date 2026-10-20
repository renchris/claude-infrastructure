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
#
# UNKNOWN IS NOT BROKEN (2026-10-18, docs/research/startup-hooks-2026-10-18/README.md §2 #4). A probe
# that is timed out (124), killed (137) or cannot run (127) under load proves nothing about the binary:
# that path printed a false "no working version" on 21 of 370 starts (5.7%) and kept a rollback a
# timeout could trigger. Such a probe is logged as UNKNOWN and the hook exits 0, silent, never
# re-pointing `current`. A rollback needs a HARD failure that repeats under a 10 s bound. A passing
# verdict is cached on (link target, inode, mtime), so a healthy start boots no 204 MB binary at all.

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
# START/END IDL rows: an async hook has no visible channel, and a harness kill leaves no record
# otherwise (docs/research/startup-hooks-2026-10-18/README.md §2 #22; hooks/lib/async-span.sh).
# shellcheck source=lib/async-span.sh disable=SC1091  # runtime-resolved beside this file
. "${BASH_SOURCE[0]%/*}/lib/async-span.sh" 2>/dev/null && async_span_begin pre-session-validate

# === SETTINGS MODEL PORTABILITY GUARD (2026-06-11) ===
# `/model <X>` "saved as default" writes "model" into the LAUNCHING account's
# settings.json, keyed by CLAUDE_CONFIG_DIR. Since migration 0037 every account's
# settings.json (~/.claude-next, ~/.claude-secondary, …) is a SYMLINK to the one shared
# ~/.claude/settings.json, so the strip below writes through the link (realpath, temp
# file in the REAL dir, os.replace onto the real file): replacing the link path itself
# would turn that account's link into a forked private copy. A window-bound frontier model (fable / claude-fable-5) left saved there poisons THAT
# account: the day it resolves to a stable binary (2.1.114 can't resolve the model)
# every plain `claude` launch dies with "There's an issue with the selected model".
# So the guard MUST read the launching account's settings via CLAUDE_CONFIG_DIR — a
# hardcoded ~/.claude/settings.json only heals the DEFAULT account and leaves every
# non-default account bricked (T-P10-3). Frontier sessions never need the saved default
# (claude-fable pins --model explicitly), so stripping it is always safe. Self-heal +
# warn. Observed live 2026-06-11 (a /model fable save broke stable-track probes). On new
# frontier tiers, extend the case pattern via the cc-upgrade skill (model.md).
SETTINGS_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
if [[ -f "$SETTINGS_FILE" ]] && command -v jq >/dev/null 2>&1; then
  # jq, not python3: this read runs on every start; python3 is spawned only for the rare strip below.
  saved_model=$(jq -r '.model // "" | tostring' "$SETTINGS_FILE" 2>/dev/null || echo '')
  case "$saved_model" in
    fable|claude-fable*)
      cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak-model-guard-$(date +%s)" 2>/dev/null || true
      python3 - "$SETTINGS_FILE" <<'PYEOF' 2>>"$LOG_FILE" || true
import json, os, sys, tempfile
real = os.path.realpath(sys.argv[1])
with open(real) as f:
    d = json.load(f)
d.pop('model', None)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(real), prefix='.settings-model-guard-')
with os.fdopen(fd, 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write('\n')
os.replace(tmp, real)
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

# `timeout` by ABSOLUTE path: the harness's PATH need not contain Homebrew, and a missing `timeout`
# used to read as a broken binary (rc 127). CC_PSV_TIMEOUT_BIN is the test seam.
TIMEOUT_BIN="${CC_PSV_TIMEOUT_BIN:-}"
if [[ -z "$TIMEOUT_BIN" ]]; then
  for _t in /opt/homebrew/bin/timeout /opt/homebrew/bin/gtimeout /usr/local/bin/timeout /usr/local/bin/gtimeout; do
    [[ -x "$_t" ]] && { TIMEOUT_BIN="$_t"; break; }
  done
  [[ -n "$TIMEOUT_BIN" ]] || TIMEOUT_BIN="$(command -v timeout 2>/dev/null || true)"
fi

# probe <binary> <seconds> → the exit code of a bounded `--version`; 127 when no bound is available
# (an unbounded probe could hold the session start, so it is never run).
probe() {
  [[ -n "$TIMEOUT_BIN" ]] || return 127
  CLAUDE_SKIP_AUTH=1 "$TIMEOUT_BIN" "$2" "$1" --version >/dev/null 2>&1
}
is_unknown() { [[ "$1" == 124 || "$1" == 137 || "$1" == 127 ]]; }

VERDICT_FILE="$HOME/.claude/state/pre-session-validate.verdict"
verdict_key() { # <binary> → "<link target> <inode> <mtime>" of what the binary resolves to
  local st; st="$(stat -L -f '%i %m' "$1" 2>/dev/null)" || return 1
  printf '%s %s' "$current_target" "$st"
}

if [[ -n "$current_binary" ]] && [[ "$manifest_skip" == 0 ]]; then
  key="$(verdict_key "$current_binary" || true)"
  if [[ -n "$key" && -f "$VERDICT_FILE" && "$(cat "$VERDICT_FILE" 2>/dev/null)" == "ok $key" ]]; then
    exit 0   # this exact binary already passed; nothing on disk has changed since
  fi
  rc=0; probe "$current_binary" 2 || rc=$?
  if [[ "$rc" != 0 ]] && ! is_unknown "$rc"; then
    rc=0; probe "$current_binary" 10 || rc=$?   # a hard failure must REPEAT under a generous bound
  fi
  if [[ "$rc" == 0 ]]; then
    if [[ -n "$key" ]]; then
      mkdir -p "${VERDICT_FILE%/*}" 2>/dev/null && printf 'ok %s\n' "$key" > "$VERDICT_FILE.$$" 2>/dev/null \
        && mv -f "$VERDICT_FILE.$$" "$VERDICT_FILE" 2>/dev/null || true
    fi
    exit 0   # Healthy — exit silently
  fi
  if is_unknown "$rc"; then
    log "UNKNOWN: $current_target --version probe rc=$rc (timeout/killed/no-timeout under load) — not a failure; current left as is"
    exit 0
  fi
fi

# BROKEN — find fallback
log "current version broken: $current_target — attempting rollback"
echo "[pre-session-validate] WARNING: $current_target failed --version check" >&2

# Find highest semver-sorted version directory that ISN'T the broken one
fallback=""
# ls|grep|sort -V -r is intentional: semver-DESCENDING scan of version dirs (a bare
# glob expands lexically — 2.1.10 before 2.1.9 — which would pick the wrong fallback).
# shellcheck disable=SC2010
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
  # Binary must answer --version under the same 10 s bound; an UNKNOWN probe is never a fallback
  crc=0; probe "$candidate_binary" 10 || crc=$?
  if [[ "$crc" == 0 ]]; then
    fallback="$candidate_path"
    break
  fi
  is_unknown "$crc" && { unknown_candidates=$(( ${unknown_candidates:-0} + 1 )); log "fallback $candidate UNKNOWN (rc=$crc)"; }
done

if [[ -z "$fallback" && "${unknown_candidates:-0}" -gt 0 ]]; then
  log "no VERIFIED fallback: ${unknown_candidates} candidate(s) UNKNOWN under load — current left as is"
  exit 0
fi
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
