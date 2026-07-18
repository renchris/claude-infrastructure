#!/usr/bin/env bash
# ship-land.sh — the ENTIRE claude-infrastructure landing pipeline as ONE fail-closed
# script (was prose in .claude/commands/ship.md a model could skip or paraphrase).
#
#   scripts/ship-land.sh [--trunk <branch>] [--dry-run]
#
# Pipeline (fail-closed at every step):
#   preflight (OUTSIDE lock): shared-checkout refusal · dirty-tree refusal ·
#     escalation-scan (destructive SQL / credential patterns ⇒ PARK a decision packet,
#     exit 3, never auto-land) · safety backup ref
#   → land-lock'd child (serialized machine-wide per repo via land-lock.sh):
#       last-moment `git fetch` → `git rebase` (conflict ⇒ exit 5) → GATE (shellcheck +
#       bats + `bash -n` + py_compile for changed shell/python INCLUDING extensionless
#       by shebang; red ⇒ exit 6) → `git push HEAD:<trunk>` (non-ff ⇒ exit 7) →
#       land-verify.sh (content not intact on trunk ⇒ exit 8) → stranded-sweep
#       (exit 1 ⇒ REVIEW verdict, surfaced, never auto-recovered) → self-attesting
#       land.log line {verify,sweep,esc_scan,sid}.
#
# --dry-run stops after the gate (no push). Exit codes: 0 landed · 2 preflight refusal ·
# 3 escalation PARK · 4 shared-checkout refusal · 5 rebase conflict · 6 gate red ·
# 7 push non-ff · 8 content-verify failed.
#
# TRAILER CONVENTION (ownership-decidable sweep, T-P9-4): a session's commits should
# carry a `Session-Id: <CLAUDE_CODE_SESSION_ID>` trailer so `stranded-sweep.sh --mine
# <sid>` can recover only own-drops. ship-land stamps land.log with the sid (a
# post-hoc commit trailer is impossible), and adds the trailer to any commit IT makes.
#
# Env overrides (mostly for tests): SHIP_LAND_SHARED_CHECKOUT · SHIP_LAND_SESSION_BRANCH_RE
# · SHIP_LAND_ALLOW_SHARED=1 · SHIP_LAND_ESC_RE · SHIP_LAND_DECISIONS_DIR · LAND_LOG ·
# LAND_LOCK_DIR (see land-lock.sh).
#
# bash 3.2-safe (no declare -A / mapfile; empty-array expansion guarded under `set -u`).
# `pipefail` load-bearing; NO `set -e`.
set -uo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAND_LOCK="${SCRIPT_DIR}/land-lock.sh"
LAND_VERIFY="${SCRIPT_DIR}/land-verify.sh"
STRANDED_SWEEP="${SCRIPT_DIR}/stranded-sweep.sh"

ESC_RE_DEFAULT='DROP[[:space:]]+TABLE|DROP[[:space:]]+COLUMN|DROP[[:space:]]+DATABASE|DROP[[:space:]]+SCHEMA|TRUNCATE[[:space:]]+TABLE|DELETE[[:space:]]+FROM|ALTER[[:space:]]+TABLE[[:space:]].+[[:space:]]DROP|-----BEGIN[[:space:]A-Z]*PRIVATE[[:space:]]+KEY'
# NOTE: auth/session/navigation code lands are ALSO escalation-worthy (operator ruling),
# but this repo's normal churn is full of those words — a substring scan would self-park
# every land. Keep the default to high-signal destructive-SQL / credential patterns and
# let a repo extend it via SHIP_LAND_ESC_RE. (Surfaced to the lead as a design tradeoff.)

# ---- helpers ---------------------------------------------------------------

is_shell_file() {  # *.sh/*.bash OR a shell shebang (portable — no GNU \b)
  case "$1" in *.sh|*.bash) return 0 ;; esac
  [[ -f "$1" ]] || return 1
  head -1 "$1" 2>/dev/null | grep -qiE '^#!.*(bash|zsh|ksh|dash|(/| )sh)'
}

is_python_file() {  # *.py OR a python shebang (the extensionless-glob-miss fix)
  case "$1" in *.py) return 0 ;; esac
  [[ -f "$1" ]] || return 1
  head -1 "$1" 2>/dev/null | grep -qiE '^#!.*python'
}

esc_scan() {  # $1=range → prints matched escalation lines (empty ⇒ clean)
  local range="$1" re body
  re="${SHIP_LAND_ESC_RE:-$ESC_RE_DEFAULT}"
  body="$(git diff "$range" 2>/dev/null | grep -E '^[-+]' | grep -Ev '^(\+\+\+|---) ' || true)"
  printf '%s\n' "$body" | grep -inE "$re" || true
}

write_decision_packet() {  # $1=id $2=branch $3=range $4=hits
  local id="$1" branch="$2" range="$3" hits="$4" dir
  dir="${SHIP_LAND_DECISIONS_DIR:-$HOME/.claude/autonomy/decisions}"
  mkdir -p "$dir" 2>/dev/null || true
  ID="$id" BRANCH="$branch" RANGE="$range" HITS="$hits" SID="${CLAUDE_CODE_SESSION_ID:-}" \
    python3 - "$dir/$id.json" <<'PY'
import json, os, sys
pkt = {
    "id": os.environ["ID"],
    "class": "B",
    "what_plain": ("ship-land refused to auto-land branch %r: the landing range %r contains an "
                   "escalation-surface pattern (destructive SQL / credential). Auto-landing "
                   "destructive or security-sensitive changes is disallowed; a human must review "
                   "and land." % (os.environ["BRANCH"], os.environ["RANGE"])),
    "options": ["review the flagged lines and land manually via /ship",
                "amend the commit to remove the escalation pattern, then re-run",
                "veto — do not land"],
    "recommendation": "review the flagged lines and land manually if correct",
    "default_if_no_veto": None,
    "staged": True,
    "session_id": os.environ.get("SID", ""),
    "matched": [ln for ln in os.environ["HITS"].strip().splitlines() if ln][:20],
}
with open(sys.argv[1], "w") as f:
    json.dump(pkt, f, indent=2)
print(sys.argv[1])
PY
}

attest_land() {  # $1=verify $2=sweep $3=esc $4=exit — self-attesting land.log line
  local log; log="${LAND_LOG:-$HOME/.claude/land.log}"
  mkdir -p "$(dirname "$log")" 2>/dev/null || true
  printf '{"ts":"%s","tool":"ship-land","repo":"%s","branch":"%s","sid":"%s","verify":"%s","sweep":"%s","esc_scan":"%s","exit":%s}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${REPO_ROOT}" "${BRANCH}" "${CLAUDE_CODE_SESSION_ID:-}" \
    "$1" "$2" "$3" "$4" >> "$log" 2>/dev/null || true
}

detect_trunk() {
  local t
  t="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')"
  [[ -z "$t" ]] && t="main"
  printf '%s' "$t"
}

run_gate() {  # $1=range → 0 green / 1 red
  local range="$1" p rc=0
  local shellfiles=() pyfiles=()
  while IFS= read -r -d '' p; do
    [[ -z "$p" ]] && continue
    is_shell_file "$p" && shellfiles+=("$p")
    is_python_file "$p" && pyfiles+=("$p")
  done < <(git diff --name-only -z "$range" 2>/dev/null)

  if [[ ${#shellfiles[@]} -gt 0 ]]; then
    echo "→ gate: shellcheck + bash -n on ${#shellfiles[@]} shell file(s)" >&2
    shellcheck "${shellfiles[@]}" >&2 || { echo "✗ gate: shellcheck RED" >&2; rc=1; }
    for p in "${shellfiles[@]}"; do
      bash -n "$p" 2>&1 >&2 || { echo "✗ gate: bash -n RED: $p" >&2; rc=1; }
    done
  fi
  if [[ ${#pyfiles[@]} -gt 0 ]]; then
    echo "→ gate: py_compile on ${#pyfiles[@]} python file(s) (incl. extensionless-by-shebang)" >&2
    python3 -m py_compile "${pyfiles[@]}" >&2 || { echo "✗ gate: py_compile RED" >&2; rc=1; }
  fi
  if [[ -d tests ]] && ls tests/*.bats >/dev/null 2>&1; then
    echo "→ gate: bats tests/" >&2
    bats tests/ >&2 || { echo "✗ gate: bats RED" >&2; rc=1; }
  fi
  return "$rc"
}

# ---- locked phase (re-exec'd under land-lock) ------------------------------

main_locked() {
  local TRUNK="$1" DRY_RUN="$2"
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

  echo "→ ship-land[locked]: last-moment fetch origin/$TRUNK" >&2
  git fetch origin "$TRUNK" 2>/dev/null || echo "⚠ ship-land: fetch failed — using local origin/$TRUNK" >&2

  if ! git rebase "origin/$TRUNK" >&2; then
    echo "✗ ship-land: rebase onto origin/$TRUNK hit a conflict — resolve it, then re-run /ship. Rebase left in progress; backup ref intact." >&2
    exit 5
  fi

  local LAND_BASE RANGE
  LAND_BASE="$(git rev-parse "origin/$TRUNK")"
  RANGE="$LAND_BASE..HEAD"

  if [[ -z "$(git rev-list "$RANGE" 2>/dev/null)" ]]; then
    echo "✓ ship-land: nothing to land (origin/$TRUNK already contains HEAD)."
    exit 0
  fi

  if ! run_gate "$RANGE"; then
    echo "✗ ship-land: GATE RED — not pushing." >&2
    exit 6
  fi

  if [[ "$DRY_RUN" = "1" ]]; then
    echo "→ ship-land --dry-run: reconciled onto origin/$TRUNK + gate GREEN; STOPPING before push."
    echo "  would push HEAD ($(git rev-parse --short HEAD)) → origin/$TRUNK:"
    git diff --stat "$RANGE"
    exit 0
  fi

  local LANDED_HEAD
  LANDED_HEAD="$(git rev-parse HEAD)"

  if ! git push origin "HEAD:$TRUNK" >&2; then
    echo "✗ ship-land: push to origin/$TRUNK REJECTED (non-fast-forward — a sibling beat you inside the window). Re-run /ship to re-fetch+rebase+re-verify. Backup ref intact." >&2
    exit 7
  fi

  git fetch origin "$TRUNK" 2>/dev/null || true
  if ! "$LAND_VERIFY" "$LAND_BASE..$LANDED_HEAD" "origin/$TRUNK" "$LANDED_HEAD"; then
    echo "✗ ship-land: post-push CONTENT-VERIFY FAILED — your paths are NOT intact on origin/$TRUNK (a concurrent rebase-land dropped content — the 2026-07-11 incident class). Backup ref ship/backup-* holds your commit; recover + re-land." >&2
    attest_land "FAIL" "n/a" "clean" 8
    exit 8
  fi

  local sweep_out sweep_rc sweep_field
  sweep_out="$("$STRANDED_SWEEP" "$TRUNK" 2>&1)"; sweep_rc=$?
  if [[ "$sweep_rc" -eq 0 ]]; then
    sweep_field="clean"
    echo "✓ ship-land: stranded-sweep clean."
  else
    sweep_field="review"
    echo "⚠ ship-land: stranded-sweep flags commit(s) for REVIEW — peer WIP is expected on a multi-session box; recover ONLY your own dropped work, NEVER cherry-pick peer WIP onto $TRUNK:" >&2
    printf '%s\n' "$sweep_out" >&2
  fi

  attest_land "ok" "$sweep_field" "clean" 0
  echo "✓ ship-land: LANDED $(git rev-parse --short "$LANDED_HEAD") → origin/$TRUNK; content-verified; sweep=$sweep_field."
  exit 0
}

# ---- outer phase (preflight → launch locked child) -------------------------

main_outer() {
  local DRY_RUN=0 TRUNK=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1; shift ;;
      --trunk) TRUNK="${2:-}"; shift 2 ;;
      --trunk=*) TRUNK="${1#--trunk=}"; shift ;;
      -h|--help) sed -n '2,30p' "$SELF"; exit 0 ;;
      *) echo "✗ ship-land: unknown argument '$1'" >&2; exit 2 ;;
    esac
  done
  [[ -z "$TRUNK" ]] && TRUNK="$(detect_trunk)"

  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  local TOP; TOP="$(cd "$REPO_ROOT" && pwd -P)"

  # --- shared-checkout refusal (G-P9-4, in code) ---
  local SHARED; SHARED="${SHIP_LAND_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"
  [[ -d "$SHARED" ]] && SHARED="$(cd "$SHARED" && pwd -P)"
  local SESSION_RE; SESSION_RE="${SHIP_LAND_SESSION_BRANCH_RE:-^(feat|fix|chore|docs|refactor|test|perf|style|build|ci)/.+}"
  if [[ "$TOP" = "$SHARED" ]]; then
    if [[ "$BRANCH" =~ ^(main|master|develop|production|prod|release) ]]; then
      echo "✗ ship-land: REFUSING to land from the shared checkout ($SHARED) on protected branch '$BRANCH'. This is the $(basename "$SHARED") symlink source and often sits on a foreign session's branch; landing here risks landing onto a branch you did not create / being rebase-dropped. Re-run from a dedicated worktree (claude -w <name>)." >&2
      exit 4
    elif [[ "$BRANCH" =~ $SESSION_RE ]] || [[ "${SHIP_LAND_ALLOW_SHARED:-0}" = "1" ]]; then
      echo "⚠ ship-land: landing from the shared checkout on session branch '$BRANCH' (allowed). Prefer a dedicated worktree." >&2
    else
      echo "✗ ship-land: REFUSING to land from the shared checkout ($SHARED) on non-session branch '$BRANCH'. Re-run from a dedicated worktree, or set SHIP_LAND_ALLOW_SHARED=1 if you own this branch." >&2
      exit 4
    fi
  fi

  # --- dirty-tree refusal ---
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    echo "✗ ship-land: working tree has uncommitted changes — commit the in-scope work first (explicit paths, never a blind add -A), then land. Refusing to land a dirty tree." >&2
    git status --short >&2
    exit 2
  fi

  git fetch origin "$TRUNK" 2>/dev/null || echo "⚠ ship-land: preflight fetch failed — using local origin/$TRUNK" >&2
  local BASE RANGE
  BASE="$(git merge-base "origin/$TRUNK" HEAD 2>/dev/null || true)"
  if [[ -z "$BASE" ]]; then
    echo "✗ ship-land: cannot find a merge-base with origin/$TRUNK — is '$TRUNK' the right trunk? (use --trunk)" >&2
    exit 2
  fi
  RANGE="$BASE..HEAD"
  if [[ -z "$(git rev-list "$RANGE" 2>/dev/null)" ]]; then
    echo "✓ ship-land: nothing to land (origin/$TRUNK already contains HEAD)."
    exit 0
  fi

  # --- escalation-scan (blast-radius cap, T-P9-6) → PARK, never auto-land ---
  local hits; hits="$(esc_scan "$RANGE")"
  if [[ -n "$hits" ]]; then
    local id; id="shipland-esc-$(git rev-parse --short HEAD)"
    local pkt; pkt="$(write_decision_packet "$id" "$BRANCH" "$RANGE" "$hits")"
    echo "⛔ ship-land: escalation-surface pattern in the landing range — PARKED for human review, NOT auto-landed." >&2
    printf '%s\n' "$hits" | sed 's/^/    /' >&2
    echo "  decision packet: ${pkt:-$id}" >&2
    attest_land "n/a" "n/a" "hit" 3
    exit 3
  fi

  # --- safety backup ref (rollback point) ---
  git branch -f "ship/backup-$(git rev-parse --short HEAD)" HEAD >/dev/null 2>&1 || true

  # --- launch the locked pipeline as ONE child under the machine-wide landing lock ---
  exec "$LAND_LOCK" -- "$SELF" __locked "$TRUNK" "$DRY_RUN"
}

# ---- dispatch --------------------------------------------------------------

if [[ "${1:-}" = "__locked" ]]; then
  shift
  main_locked "$@"     # always exits internally
else
  main_outer "$@"      # exec's the locked child, or exits on a preflight refusal
fi
