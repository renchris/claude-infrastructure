#!/bin/bash
# registration-state.sh — decide, MECHANICALLY, whether a staged registration actually reached the
# enforcing store, and WHICH way it failed when it did not.
#
# ── WHY THIS EXISTS ──────────────────────────────────────────────────────────────────────────────
# `migrations/` fixed the delivery half: a registration is executable state that the converger runs
# at deploy instead of a folder somebody is supposed to visit. It did NOT give anyone a way to ASK
# whether a given registration is in force. Today that question is answered by READING — open
# settings.json, find the entry, decide whether the value looks right — and a question answered by
# reading is one nobody asks on a normal day.
#
# That matters because a registration has more than two outcomes, and the failures are silent in
# DIFFERENT ways (BACKLOG_CONSOLIDATION_2026-08-09 §M5):
#
#   NOT-STAGED     the ledger says the migration ran, but the arm was never written. The subject
#                  file is absent, so the registration names a path that cannot execute.
#   NOT-DELIVERED  the arm is on disk and executable, but nothing sourced or registered it. This is
#                  the LOUDEST-looking and quietest-behaving state: `ls` shows the file, every
#                  consumer guard (`[ -f x ] && . x`) skips it, and the feature is a no-op.
#   OVERRIDDEN     the arm is registered, but something later set a DIFFERENT value at the same key
#                  — e.g. the command is present with the field that made it asynchronous removed,
#                  which converts a background hook into one that BLOCKS every session birth.
#
# A single boolean ("is it in settings.json?") collapses all three into one bit and reports the
# third as success. Each needs a different fix, so the check has to name which one it is.
#
# ── WHY A FOURTH STATE IS FIRST-CLASS, NOT AN ERROR ──────────────────────────────────────────────
# A `c10` migration is STAGED BY DESIGN and waits for a human (migrations/README.md). If the check
# treated "not in the enforcing store" as failure, every correctly-staged c10 would read red forever
# and the signal would be worth nothing (MEMORY.md alarm-polarity-and-attention-budget). So
# `staged-pending` is a PASS: it is the system working. Only a state that contradicts its own ledger
# is a failure. This is the same trap as an abstain rule that retires the common case
# (MEMORY.md abstain-rule-can-retire-the-common-case) — the question has four answers, not two.
#
# ── WHY THE VERIFIER IS DECLARED PER MIGRATION, NOT INFERRED ─────────────────────────────────────
# Inferring the target by parsing each migration's own source would make this check a second
# implementation of the thing it audits, and the two would drift — the exact defect M6 closed for
# account facts (two derivations of one fact). Instead each migration DECLARES its own oracle:
#
#   # migration-subject: <path>   the arm itself; absent ⇒ not-staged
#   # migration-verify:  <cmd>    exit 0 ⇒ the effect is live in the enforcing store
#   # migration-conflict:<cmd>    exit 0 ⇒ a DIFFERENT value is set at the same key ⇒ overridden
#
# A migration that declares no verifier is reported `unverifiable` and COUNTED SEPARATELY. It is
# never folded into the pass tally: a checker whose default answer is silence would make blindness
# the shipping path (MEMORY.md sensor-default-off-makes-blindness-the-shipping-path), and a summary
# that said "0 failures" over 7 migrations it could not read would be worse than no check at all.
#
# Output is one `verdict=` token per migration plus a summary line, because a consumer must be able
# to PARSE the answer rather than match prose (MEMORY.md claimed-outcome-vs-checked-outcome).
#
# Exit: 0 = no failing state · 1 = at least one not-staged / not-delivered / overridden · 2 = usage.
set -uo pipefail

# Resolve THIS file through its symlink chain before deriving the repo root. ~/.claude/scripts/ is
# per-file symlinks into the checkout, so on the live path an unresolved dirname would make REPO
# ~/.claude — which has no migrations/ — and this check would report "no migrations dir" or scan the
# wrong tree, only ever on the live path. No `readlink -f`: GNU-only, this box is BSD.
_self="${BASH_SOURCE[0]}"
while [ -L "$_self" ]; do
  _d="$(cd "$(dirname "$_self")" && pwd)"
  _self="$(readlink "$_self")"
  case "$_self" in /*) ;; *) _self="$_d/$_self" ;; esac
done
REPO="$(cd "$(dirname "$_self")/.." && pwd)"
# CC_MIGRATION_DIR exists so the suite can point this at a FIXTURE. Redirecting the store alone is
# not hermeticity — the test must also own $HOME, because the declared verifiers read
# ${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json and would otherwise answer from the real fleet
# config (MEMORY.md hermetic-in-stubs-not-in-interpreter).
MIG_DIR="${CC_MIGRATION_DIR:-$REPO/migrations}"
STATE="${CC_MIGRATION_STATE:-${CC_CLAUDE_DIR:-$HOME/.claude}/autonomy/migrations}"

usage() {
  cat >&2 <<'EOF'
usage: registration-state.sh [--json] [--only <name-substring>]
  Reports, per migration, whether its registration reached the enforcing store:
    verdict=registered      the effect is live
    verdict=staged-pending  c10, correctly awaiting the operator (PASS — not a failure)
    verdict=not-staged      ledger says run, but the arm was never written
    verdict=not-delivered   arm on disk, nothing registered/sourced it
    verdict=overridden      a different value is set at the same key
    verdict=partial         live in SOME config dirs and absent from others
    verdict=unverifiable    the migration declares no oracle (counted separately, never a pass)
EOF
  exit 2
}

JSON=0 ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1 ;;
    --only) ONLY="${2:-}"; shift ;;
    -h|--help) usage ;;
    *) printf 'registration-state: unknown arg %s\n' "$1" >&2; usage ;;
  esac
  shift
done

[ -d "$MIG_DIR" ] || { printf 'registration-state: no migrations dir at %s\n' "$MIG_DIR" >&2; exit 2; }

# Read a `# key: value` header from a migration. Only the FIRST match counts, and only from the
# comment block — a later occurrence inside the body is code, not a declaration.
hdr() { sed -n "s/^# $1: *//p" "$2" 2>/dev/null | head -1; }

# The ledger records one file per state dir. Absent from all of them = never seen by the converger.
ledger_state() {
  local name="$1" d
  for d in applied failed staged superseded; do
    [ -e "$STATE/$d/$name.json" ] && { printf '%s' "$d"; return; }
  done
  printf 'absent'
}

# config_dirs — every config dir whose settings.json a session can actually be launched against.
#
# WHY THIS IS NOT JUST $HOME/.claude. The declared verifiers read
# ${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json — ONE file — while the registration migrations
# deliberately write four or five, because those files are separate REAL files rather than symlinks
# into the checkout and were measured already divergent (0007's own header: 35 940 / 35 270 / 35 929
# / 35 947 B). So a registration present in ~/.claude and absent from ~/.claude-tertiary satisfied
# the verifier and read `registered`, while every session launched against tertiary was unarmed.
# That is the SAME silent half-coverage 0007 exists to abolish, reproduced one level up in the thing
# that checks it — a sibling auditor modelling fewer states than its subject
# (MEMORY.md sibling-auditors-must-share-the-state-model).
#
# An EXPLICIT CC_CLAUDE_DIR still wins and is the only dir consulted: it is how the suite fixtures
# this, and honouring it keeps the check answerable about one named config on purpose.
config_dirs() {
  local d found=""
  if [ -n "${CC_CLAUDE_DIR:-}" ]; then printf '%s\n' "$CC_CLAUDE_DIR"; return; fi
  for d in "$HOME"/.claude "$HOME"/.claude-next "$HOME"/.claude-secondary \
           "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
    [ -f "$d/settings.json" ] && { printf '%s\n' "$d"; found=1; }
  done
  [ -n "$found" ] || printf '%s\n' "$HOME/.claude"
}

n_reg=0 n_staged=0 n_fail=0 n_unver=0
rows=""

for f in "$MIG_DIR"/[0-9]*.sh; do
  [ -r "$f" ] || continue
  base="$(basename "$f")"
  name="${base%.sh}"
  [ -n "$ONLY" ] && case "$name" in *"$ONLY"*) ;; *) continue ;; esac

  class="$(hdr 'migration-class' "$f")"; class="${class:-unknown}"
  subject="$(hdr 'migration-subject' "$f")"
  verify="$(hdr 'migration-verify' "$f")"
  conflict="$(hdr 'migration-conflict' "$f")"
  lstate="$(ledger_state "$name")"

  # Expand a leading ~ in the declared subject the way the shell would; these headers are written
  # the same way the settings.json entries are, so they carry literal tildes.
  # shellcheck disable=SC2088  # the tilde is DELIBERATELY literal here: it is the PATTERN being
  # matched against a header string that was written with a literal ~, exactly as the settings.json
  # entries are. Expanding it would defeat the match this line exists to perform.
  case "$subject" in "~/"*) subject="$HOME/${subject#\~/}" ;; esac

  if [ -z "$verify" ]; then
    verdict="unverifiable"; why="declares no '# migration-verify:'"
    n_unver=$((n_unver + 1))
  else
    # Run the DECLARED verifier once per config dir, pointing it at that dir. The declaration needs
    # no change: it already reads ${CC_CLAUDE_DIR:-...}, so setting that var per iteration re-aims
    # the same oracle rather than introducing a second one.
    n_dirs=0 n_ok=0 missing=""
    while IFS= read -r _cd; do
      [ -n "$_cd" ] || continue
      n_dirs=$((n_dirs + 1))
      if CC_CLAUDE_DIR="$_cd" bash -c "$verify" >/dev/null 2>&1; then
        n_ok=$((n_ok + 1))
      else
        missing="$missing $(basename "$_cd")"
      fi
    done <<EOF
$(config_dirs)
EOF

    if [ "$n_ok" -gt 0 ] && [ "$n_ok" -eq "$n_dirs" ]; then
      verdict="registered"; why="verifier exit 0 in all $n_dirs config dir(s)"
      n_reg=$((n_reg + 1))
    elif [ "$n_ok" -gt 0 ]; then
      # Present in some configs and absent from others. This is a FAILING state, not a softer
      # "registered": whether a session gets the arm then depends on which config dir it launched
      # against, so the same box is simultaneously armed and unarmed and neither reading is wrong.
      verdict="partial"; why="live in $n_ok of $n_dirs config dir(s) — missing:$missing"
      n_fail=$((n_fail + 1))
    elif [ -n "$conflict" ] && bash -c "$conflict" >/dev/null 2>&1; then
      verdict="overridden"; why="a different value is set at the same key"
      n_fail=$((n_fail + 1))
    elif [ -n "$subject" ] && [ ! -e "$subject" ]; then
      verdict="not-staged"; why="arm absent: $subject"
      n_fail=$((n_fail + 1))
    elif [ "$lstate" = "staged" ] && [ "$class" = "c10" ]; then
      # Correctly awaiting a human. The arm exists, the ledger says staged, the effect is absent —
      # which is precisely what "staged" MEANS. Not a defect.
      verdict="staged-pending"; why="c10 awaiting the operator (by design)"
      n_staged=$((n_staged + 1))
    elif [ "$lstate" = "applied" ]; then
      verdict="not-delivered"; why="ledger=applied but the effect is absent"
      n_fail=$((n_fail + 1))
    else
      verdict="not-delivered"; why="effect absent (ledger=$lstate)"
      n_fail=$((n_fail + 1))
    fi
  fi

  printf 'verdict=%s migration=%s class=%s ledger=%s — %s\n' "$verdict" "$name" "$class" "$lstate" "$why"
  rows="$rows{\"migration\":\"$name\",\"class\":\"$class\",\"ledger\":\"$lstate\",\"verdict\":\"$verdict\"},"
done

if [ "$JSON" = 1 ]; then
  printf '[%s]\n' "${rows%,}"
fi

printf 'summary: registered=%s staged-pending=%s FAILING=%s unverifiable=%s\n' \
  "$n_reg" "$n_staged" "$n_fail" "$n_unver"

[ "$n_fail" -gt 0 ] && exit 1
exit 0
