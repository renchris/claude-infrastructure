#!/bin/bash
# c10-batch.sh — run every pending c10 migration as ONE operator act, in a safe order, with a
# per-step verify, a stop at the first failure, and a one-command rollback.
#
# WHY. Every c10 migration (settings.json, launchd, ~/.zshrc) is staged and waits for the operator
# to run it by hand. On 2026-09-30 fourteen of them were pending, each a separate paste, and each
# per-dir one widened the four forked account settings.json files further. This collapses them into
# one command whose order is fixed by what the migrations need, not by when they were written.
#
# WHERE THE STEP LIST COMES FROM. The staged ledger (~/.claude/autonomy/migrations/staged/*.json)
# plus any c10 migration in migrations/ that has no ledger entry yet (the next converge would stage
# it). Never from backlog rows. A candidate is DROPPED when its file is gone or declares
# `# migration-superseded-by:`, SKIPPED as live when its own `# migration-verify:` already exits 0
# (the same oracle scripts/registration-state.sh reads — the settle sweep in deploy-migrations.sh
# retires those at the next converge), and HELD when it declares `# migration-batch-hold:`:
#     # migration-batch-hold: decision <cc-decide id>   runs only once that packet is `actioned`
#     # migration-batch-hold: manual <reason>           never runs here; its run line is printed
#
# ORDER. 0037 (one shared settings.json) first: every later settings migration either refuses a
# forked fleet (0039-0041, 0046-0048) or loops the account dirs and is a no-op on a linked one only
# because ~/.claude comes first (README rule 7). 0024 last, so unit-gate.sh stays PreToolUse[0]
# whatever an earlier step inserts. Everything else lexical. After each step: its own verify, then
# `cc-settings-parity check` (once 0037 has run) — a step that re-forked an account stops the batch.
#
# Usage:
#   bash scripts/c10-batch.sh --list                 # the step list and why each candidate is in or out
#   bash scripts/c10-batch.sh --check                # FULL REHEARSAL in a scratch HOME (live settings
#                                                    # copied, forks and all); prints PASS/FAIL per step
#   bash scripts/c10-batch.sh --confirm settings.json   # run it for real (backs up first)
#   bash scripts/c10-batch.sh --verify               # rc 0 iff every runnable step's effect is live
#   bash scripts/c10-batch.sh --rollback <backup-dir>   # restore the settings files a --confirm saved
# Exit: 0 ok · 1 a step failed (stopped; rollback printed) · 2 usage · 3 nothing to do is NOT an error (0)
# Seams: CC_MIGRATIONS_STATE (ledger), CC_C10_REPO (migrations source), CC_DECIDE_BIN.
# bash 3.2-safe.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
REPO="${CC_C10_REPO:-$(cd "$(dirname "$SELF")/.." && pwd)}"
MIG_DIR="$REPO/migrations"
STATE="${CC_MIGRATIONS_STATE:-$HOME/.claude/autonomy/migrations}"
DECIDE="${CC_DECIDE_BIN:-$HOME/.claude/bin/cc-decide}"
FIRST="0037-settings-parity"
LAST="0024-unit-gate-registration"

say() { printf '%s\n' "$*"; }
die() { printf 'c10-batch: %s\n' "$*" >&2; exit "${2:-1}"; }

mig_field() { # <file> <field> — same parse as deploy-migrations.sh: the header ends at the first statement
  awk -v k="$2" '
    /^[^#]/ && !/^[[:space:]]*$/ { if (seen) exit }
    /^#!/ { next }
    $0 ~ "^# *" k " *:" { seen=1; sub("^# *" k " *: *", ""); print; exit }
  ' "$1" 2>/dev/null | head -1
}

# run_verify <file> [home] — the migration's own oracle, in a subshell with HOME re-aimed.
run_verify() {
  local v; v="$(mig_field "$1" migration-verify)"
  [ -n "$v" ] || return 1
  env -u CC_CLAUDE_DIR -u CLAUDE_CONFIG_DIR HOME="${2:-$HOME}" CC_MIGRATION_REPO="$REPO" \
    timeout 120 bash -c "$v" </dev/null >/dev/null 2>&1
}

decision_actioned() { # <id>
  [ -x "$DECIDE" ] || return 1
  "$DECIDE" list --all --json 2>/dev/null | jq -e --arg i "$1" 'any(.[]; .id == $i and .status == "actioned")' >/dev/null 2>&1
}

# candidates — one migration name per line: the staged ledger ∪ un-ledgered c10 files.
candidates() {
  {
    for j in "$STATE"/staged/*.json; do [ -f "$j" ] && basename "$j" .json; done
    for f in "$MIG_DIR"/[0-9]*.sh; do
      [ -f "$f" ] || continue
      [ "$(mig_field "$f" migration-class)" = c10 ] || continue
      n="$(basename "$f" .sh)"
      [ -f "$STATE/applied/$n.json" ] || [ -f "$STATE/staged/$n.json" ] || [ -f "$STATE/superseded/$n.json" ] \
        || echo "$n"
    done
  } | sort -u
}

# classify — prints "<state>\t<name>\t<detail>" for every candidate; state ∈ step|live|held|dropped
classify() {
  local n f sup hold kind arg
  for n in $(candidates); do
    f="$MIG_DIR/$n.sh"
    if [ ! -f "$f" ]; then printf 'dropped\t%s\tno migrations/%s.sh on this checkout\n' "$n" "$n"; continue; fi
    sup="$(mig_field "$f" migration-superseded-by)"
    if [ -n "$sup" ]; then printf 'dropped\t%s\tsuperseded: %s\n' "$n" "${sup%% — *}"; continue; fi
    if run_verify "$f"; then printf 'live\t%s\tits migration-verify already exits 0\n' "$n"; continue; fi
    hold="$(mig_field "$f" migration-batch-hold)"
    if [ -n "$hold" ]; then
      kind="${hold%% *}"; arg="${hold#* }"; arg="${arg%% *}"
      if [ "$kind" = decision ] && decision_actioned "$arg"; then
        printf 'step\t%s\tdecision %s actioned\n' "$n" "$arg"; continue
      fi
      printf 'held\t%s\t%s\n' "$n" "$hold"; continue
    fi
    printf 'step\t%s\t%s\n' "$n" "$(mig_field "$f" migration-run)"
  done
}

# ordered_steps — the runnable names, FIRST first, LAST last, the rest lexical.
ordered_steps() {
  local all; all="$(classify | awk -F'\t' '$1=="step"{print $2}')"
  local nl='
'
  case "$nl$all$nl" in *"$nl$FIRST$nl"*) echo "$FIRST" ;; esac
  printf '%s\n' "$all" | grep -vx -e "$FIRST" -e "$LAST" | grep -v '^$'
  case "$nl$all$nl" in *"$nl$LAST$nl"*) echo "$LAST" ;; esac
  return 0
}

# run_step <name> <home> — the migration's own run line, zero keystrokes.
run_step() {
  local f="$MIG_DIR/$1.sh" run
  run="$(mig_field "$f" migration-run)"
  [ -n "$run" ] || run="bash $f"
  ( cd "$REPO" && env -u CC_CLAUDE_DIR -u CLAUDE_CONFIG_DIR -u CC_MIGRATION_STATE \
      HOME="$2" CC_MIGRATION_REPO="$REPO" timeout 300 bash -c "$run" </dev/null 2>&1 )
}

parity_ok() { HOME="$1" "$1/.claude/bin/cc-settings-parity" check >/dev/null 2>&1; }

# run_batch <home> <label> — every step in order; stop at the first failure. Prints PASS/FAIL lines.
run_batch() {
  local home="$1" n out rc=0 linked=0 fails=0
  for n in $(ordered_steps); do
    out="$(run_step "$n" "$home")"; rc=$?
    if [ "$rc" -ne 0 ]; then
      say "FAIL  $n — run exited $rc"; printf '%s\n' "$out" | tail -5 | sed 's/^/      /'; fails=1; break
    fi
    if ! run_verify "$MIG_DIR/$n.sh" "$home"; then
      say "FAIL  $n — ran, but its migration-verify does not pass"; printf '%s\n' "$out" | tail -5 | sed 's/^/      /'; fails=1; break
    fi
    [ "$n" = "$FIRST" ] && linked=1
    if [ "$linked" -eq 1 ] && ! parity_ok "$home"; then
      say "FAIL  $n — verified, but an account settings.json is no longer linked to the shared file"; fails=1; break
    fi
    say "PASS  $n"
  done
  if [ "$fails" -eq 0 ]; then
    local first; first="$(jq -r '.hooks.PreToolUse[0].hooks[0].command // ""' "$home/.claude/settings.json" 2>/dev/null)"
    case "$first" in
      *unit-gate.sh) say "PASS  final — PreToolUse[0] is unit-gate.sh; every account shares one settings.json" ;;
      *) if ordered_steps | grep -qx "$LAST"; then say "FAIL  final — PreToolUse[0] is '$first', not unit-gate.sh"; fails=1; fi ;;
    esac
  fi
  return "$fails"
}

# backup_settings <dest> — every account settings.json, recording link-or-file, plus the shared file.
backup_settings() {
  local dest="$1" d p
  mkdir -p "$dest" || return 1
  cp -p "$(cd "$HOME/.claude" && pwd -P)/settings.json" "$dest/shared.settings.json" || return 1
  : > "$dest/MANIFEST"
  for d in "$HOME"/.claude "$HOME"/.claude-*; do
    p="$d/settings.json"
    [ -e "$p" ] || [ -L "$p" ] || continue
    case "$d" in *.bak*|*backup*) continue ;; esac
    if [ -L "$p" ]; then printf 'link\t%s\t%s\n' "$p" "$(readlink "$p")" >> "$dest/MANIFEST"
    else cp -p "$p" "$dest/$(basename "$d").settings.json" && printf 'file\t%s\t%s\n' "$p" "$(basename "$d").settings.json" >> "$dest/MANIFEST"; fi
  done
}

cmd_rollback() {
  local src="${1:-}" kind p val
  [ -n "$src" ] && [ -f "$src/MANIFEST" ] || die "--rollback needs a backup dir holding MANIFEST" 2
  while IFS="$(printf '\t')" read -r kind p val; do
    case "$kind" in
      file) rm -f "$p" && cp -p "$src/$val" "$p" && say "restored $p" ;;
      link) [ "$p" = "$HOME/.claude/settings.json" ] && continue
            rm -f "$p" && ln -s "$val" "$p" && say "relinked $p -> $val" ;;
    esac
  done < "$src/MANIFEST"
  # the shared file last, through its real path, so a link restored above points at the old bytes
  cp -p "$src/shared.settings.json" "$(cd "$HOME/.claude" && pwd -P)/settings.json" && say "restored the shared ~/.claude/settings.json"
}

# scratch_home — a HOME whose settings are COPIES of the live ones (forks preserved) and whose code
# (hooks, bin, scripts, lib, the checkout) is THIS repo, so a rehearsal touches nothing real.
scratch_home() {
  local s d p rel
  s="$(mktemp -d "${TMPDIR:-/tmp}/c10-batch-check.XXXXXX")" || return 1
  mkdir -p "$s/.claude/autonomy" "$s/.claude/backups" "$s/Development"
  ln -s "$REPO" "$s/Development/claude-infrastructure"
  for d in hooks bin scripts lib config; do [ -d "$REPO/$d" ] && ln -s "$REPO/$d" "$s/.claude/$d"; done
  cp -p "$(cd "$HOME/.claude" && pwd -P)/settings.json" "$s/.claude/settings.json"
  [ -f "$HOME/.claude/accounts.json" ] && cp -p "$HOME/.claude/accounts.json" "$s/.claude/accounts.json"
  for d in "$HOME"/.claude-*; do
    p="$d/settings.json"; [ -e "$p" ] || continue
    case "$d" in *.bak*|*backup*) continue ;; esac
    rel="$(basename "$d")"; mkdir -p "$s/$rel"
    if [ -L "$p" ] && [ "$(cd "$(dirname "$(readlink "$p")")" 2>/dev/null && pwd -P)" = "$(cd "$HOME/.claude" && pwd -P)" ]; then
      ln -s "$s/.claude/settings.json" "$s/$rel/settings.json"
    else
      cp -pL "$p" "$s/$rel/settings.json"
    fi
  done
  printf '%s' "$s"
}

cmd_list() {
  local rows; rows="$(classify)"
  say "c10 batch — step list (ledger: $STATE, migrations: $MIG_DIR)"
  local i=0 n
  for n in $(ordered_steps); do i=$((i+1)); printf '  %2d. %s\n' "$i" "$n"; done
  [ "$i" -gt 0 ] || say "  (no runnable step)"
  printf '%s\n' "$rows" | awk -F'\t' '$1!="step" && NF {printf "  %-7s %s — %s\n", $1, $2, $3}'
}

case "${1:-}" in
  --list) cmd_list ;;
  --check)
    command -v jq >/dev/null 2>&1 || die "jq required" 1
    s="$(scratch_home)" || die "could not build a scratch HOME" 1
    say "c10 batch REHEARSAL in $s (copies of the live settings; nothing real is touched)"
    run_batch "$s"; rc=$?
    if [ "$rc" -eq 0 ]; then
      say "REHEARSAL GREEN — $(ordered_steps | grep -c .) step(s)"
      case "$s" in */c10-batch-check.??????) rm -rf "$s" ;; esac
    else
      say "REHEARSAL RED — scratch HOME kept for inspection: $s"
    fi
    exit "$rc" ;;
  --verify)
    bad=0
    for n in $(classify | awk -F'\t' '$1=="step"{print $2}'); do say "NOT LIVE  $n"; bad=1; done
    classify | awk -F'\t' '$1=="held"{printf "HELD      %s — %s\n", $2, $3}'
    [ "$bad" -eq 0 ] && say "VERIFIED — every runnable c10 step's effect is live"
    exit "$bad" ;;
  --confirm)
    [ "${2:-}" = "settings.json" ] || die "--confirm must name its target: --confirm settings.json" 2
    command -v jq >/dev/null 2>&1 || die "jq required" 1
    steps="$(ordered_steps)"
    [ -n "$steps" ] || { say "c10 batch: nothing to run — every c10 step is live, held or superseded"; cmd_list; exit 0; }
    bk="$HOME/.claude/backups/c10-batch-$(date +%Y%m%d%H%M%S)"
    backup_settings "$bk" || die "backup to $bk FAILED — nothing run" 1
    say "c10 batch: backup in $bk"
    run_batch "$HOME"; rc=$?
    if [ "$rc" -ne 0 ]; then
      say "c10 batch STOPPED. Undo every settings change this run made with:"
      say "  bash $SELF --rollback $bk"
      exit 1
    fi
    say "c10 batch GREEN. Open NEW sessions to pick the changes up. Rows close at the next converge's settle sweep."
    say "Undo: bash $SELF --rollback $bk"
    exit 0 ;;
  --rollback) cmd_rollback "${2:-}" ;;
  *) die "usage: --list | --check | --verify | --confirm settings.json | --rollback <dir>" 2 ;;
esac
