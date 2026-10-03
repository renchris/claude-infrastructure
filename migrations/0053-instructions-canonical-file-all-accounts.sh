#!/bin/bash
# migration-class: c10
# migration-step: point EVERY account (next, next2, next3, next4) back at the ONE canonical instructions file: each account's CLAUDE.md -> ~/.claude/CLAUDE.md and rules/ -> ~/.claude/rules, through `cc-instructions-variant reset <acct>` (0042's own documented rollback). Since 0042 every session loads the slim file AND, through Claude Code's ancestor walk, ~/.claude/CLAUDE.md and ~/.claude/rules/ a second time (~124k chars now that install.sh deploys slim there; ~60k after this). Refuses until install.sh has put the selected variant into ~/.claude/CLAUDE.md. All accounts or none. Rewrites the account CLAUDE.md links, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0053-instructions-canonical-file-all-accounts.sh --confirm all-accounts
# migration-subject: ~/.claude/CLAUDE.full.md
# migration-verify: python3 -c 'import json,os,sys; h=os.path.expanduser("~"); c=h+"/.claude"; r=os.path.realpath; a=json.load(open(c+"/accounts.json")).get("accounts") or []; ds=[os.path.expanduser(x["config_dir"]) for x in a]; sys.exit(0 if ds and all(r(d+"/CLAUDE.md")==r(c+"/CLAUDE.md") and r(d+"/rules")==r(c+"/rules") for d in ds) else 1)'
#
# The verifier is config-dir-INVARIANT: it reads the one shared accounts.json and every account's link.
#
# ══ 0053 — one canonical instructions file (docs/plans/INSTRUCTION_BUDGET.md D1-D4) ══════════════════
# THE DEFECT. Claude Code loads the account's own CLAUDE.md and rules/ as User memory, then walks the
# cwd's ancestors and loads every CLAUDE.md and .claude/rules/*.md it finds as Project memory — and
# for any cwd under $HOME that walk reaches ~/.claude/CLAUDE.md and ~/.claude/rules/. It skips them
# only when the account's files resolve to the SAME realpath (processedPaths). Before 0042 they did.
# 0042 pointed every account at CLAUDE.slim.md and rules.slim, so from 2026-09-25 every session loaded
# slim + the full ~/.claude/CLAUDE.md + both boards + a stale rules essay: ~181k chars.
#
# STEP 1 (already agent-side, install.sh via deploy-live): ~/.claude/CLAUDE.md holds the selected
# global variant (registry `global <v>`, default slim) as a regular file, the full text deploys to
# ~/.claude/CLAUDE.full.md, and ~/.claude/rules/ holds only the mission board. STEP 2 (this): point the
# accounts back at those, so the realpath dedupe works again. Measured by the critic on 2.1.284,
# 2.1.278 and 2.1.114 (docs/research/instruction-budget-2026-10-03/critic.md §2.1, shape v4): no
# double load, no claudeMdExcludes, no launcher dependency. A symlinked ~/.claude/CLAUDE.md is NOT
# equivalent — 2.1.114 still double-loads it — which is why install.sh writes a regular file.
#
# WHAT IT CHANGES. For each account: drops its 0042 line from ~/.claude/instruction-variants and
# re-runs the config mirror (`cc-instructions-variant reset`), which re-points CLAUDE.md and rules at
# the shared entries and reads both back. Then moves ~/.claude/rules.slim (nothing loads it any more;
# `cc-mission render` stops writing it once it is gone) into the backup dir. ~/.claude/CLAUDE.slim.md
# stays: install.sh deploys it and it is the source ~/.claude/CLAUDE.md is copied from.
#
# PROBE (the composition, not just the links — critic.md §6.2; 0042's verifier checked targets only).
# Auth-free; run from a scratch dir UNDER $HOME, with each account's config dir:
#   mkdir -p ~/.cc-context-probe && cd ~/.cc-context-probe && \
#     CLAUDE_CONFIG_DIR=~/.claude-quaternary claude -p /context | sed -n '/Memory files/,/^$/p'
# Pass = no row whose type is Project and whose path is under ~/.claude/, and ~/.claude/CLAUDE.md (or
# its account spelling) appears exactly once. Before this migration the same probe shows
# "Project ~/.claude/CLAUDE.md" and "Project ~/.claude/rules/00-mission-board.md" beside the User rows
# (ab-contamination.md probe c5). The migration-verify line above is the realpath half of this, which
# needs no binary.
#
# ALL OR NONE (operator ruling 2026-09-23: accounts are interchangeable). If any account's reset
# fails, the registry is restored from the backup and every account this run touched is re-synced
# (back onto its 0042 arm) before exit 1.
#
# Takes effect in NEW sessions only; running sessions keep what they loaded.
# Rollback (prints its own exact lines with the backup path on success):
#   cp <backup>/instruction-variants ~/.claude/ && mv <backup>/rules.slim ~/.claude/ && re-sync each account
#
# Usage: bash migrations/0053-instructions-canonical-file-all-accounts.sh --dry-run
#        bash migrations/0053-instructions-canonical-file-all-accounts.sh --confirm all-accounts
# bash 3.2-safe.
set -uo pipefail

SRC="$HOME/.claude"
CIV="${CC_INSTRUCTIONS_VARIANT_BIN:-$SRC/bin/cc-instructions-variant}"
MIRROR="$SRC/lib/config-mirror.zsh"
command -v jq >/dev/null 2>&1 || { printf '0053: jq required — nothing written\n' >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf '0053: python3 required — nothing written\n' >&2; exit 1; }

mode=""
case "${1:-}" in
  --dry-run) mode=dry ;;
  --confirm) [ "${2:-}" = "all-accounts" ] || { printf '0053: --confirm must name its target: --confirm all-accounts\n' >&2; exit 2; }; mode=apply ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;
  *) printf '0053: unknown argument %s (use --dry-run or --confirm all-accounts)\n' "$1" >&2; exit 2 ;;
esac
[ -n "$mode" ] || { printf '0053: pass --dry-run to preview or --confirm all-accounts to apply\n' >&2; exit 2; }

rp() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }

[ -x "$CIV" ] || { printf '0053: %s not found — nothing written\n' "$CIV" >&2; exit 1; }

# STEP 1 MUST HAVE CONVERGED. Re-pointing the accounts at a ~/.claude/CLAUDE.md that still holds the
# full text would put every account on full (2x the slim tokens) — a regression, not a fix.
v="$(awk '$1 == "global" { print $2; exit }' "$SRC/instruction-variants" 2>/dev/null)"; v="${v:-slim}"
want="$SRC/CLAUDE.$v.md"
[ -f "$want" ] || { printf '0053: %s is not deployed — run deploy-live (install.sh) first; nothing written\n' "$want" >&2; exit 1; }
if [ -L "$SRC/CLAUDE.md" ] || ! cmp -s "$want" "$SRC/CLAUDE.md"; then
  printf '0053: REFUSED — ~/.claude/CLAUDE.md is not yet a regular-file copy of the selected variant (%s). install.sh does that; converge first (deploy-live), then re-run. Nothing written.\n' "${want##*/}" >&2
  exit 1
fi
[ -d "$SRC/rules" ] && [ ! -L "$SRC/rules" ] || { printf '0053: ~/.claude/rules is not a real directory — nothing written\n' >&2; exit 1; }
extra="$(cd "$SRC/rules" && for f in *; do [ -e "$f" ] || continue; case "$f" in 00-mission-board.md|00-mission-board.md.tmp) ;; *) printf ' %s' "$f" ;; esac; done)"
[ -z "$extra" ] || { printf '0053: REFUSED — ~/.claude/rules holds more than the mission board:%s. install.sh retires those; converge first. Nothing written.\n' "$extra" >&2; exit 1; }

names="$(jq -r '.accounts[]?.name // empty' "$SRC/accounts.json" 2>/dev/null)"
[ -n "$names" ] || { printf '0053: no accounts in %s/accounts.json — nothing written\n' "$SRC" >&2; exit 1; }
dir_of() { jq -r --arg a "$1" '.accounts[]? | select(.name == $a) | .config_dir // empty' "$SRC/accounts.json" | sed "s|^~|$HOME|"; }

want_md="$(rp "$SRC/CLAUDE.md")"; want_rules="$(rp "$SRC/rules")"
on_canon() {  # <dir> → 0 when both entries resolve to the canonical ones
  [ "$(rp "$1/CLAUDE.md")" = "$want_md" ] && [ "$(rp "$1/rules")" = "$want_rules" ]
}

todo=""
for a in $names; do
  d="$(dir_of "$a")"
  [ -d "$d" ] || { printf '0053: account %s has no config dir %s — nothing written\n' "$a" "$d" >&2; exit 1; }
  if on_canon "$d"; then printf '0053: %s already on ~/.claude/CLAUDE.md\n' "$a"; else todo="$todo $a"; fi
done
if [ -z "$todo" ]; then
  printf '0053: already applied — every account resolves to ~/.claude/CLAUDE.md and ~/.claude/rules\n'
  exit 0
fi

printf '0053: will re-point:%s (CLAUDE.md -> %s, rules/ -> %s/rules; the %s variant, %s bytes)\n' \
  "$todo" "$SRC/CLAUDE.md" "$SRC" "$v" "$(wc -c < "$SRC/CLAUDE.md" | tr -d ' ')"
[ "$mode" = dry ] && { printf '0053: DRY RUN — nothing written\n'; exit 0; }

bdir="$SRC/backups/instructions-canonical-0053-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" || { printf '0053: backup dir FAILED — nothing written\n' >&2; exit 1; }
[ -f "$SRC/instruction-variants" ] && cp -p "$SRC/instruction-variants" "$bdir/instruction-variants"
for a in $names; do
  d="$(dir_of "$a")"
  printf '%s CLAUDE.md=%s rules=%s\n' "$a" "$(readlink "$d/CLAUDE.md" 2>/dev/null)" "$(readlink "$d/rules" 2>/dev/null)"
done > "$bdir/links.txt"

resync_dir() { zsh -fc "source '$MIRROR'; _cc_sync_config_mirror '$1'" >/dev/null 2>&1 || true; }

done_list=""
for a in $todo; do
  if "$CIV" reset "$a"; then
    done_list="$done_list $a"
  else
    printf '0053: reset FAILED on %s — restoring the registry and re-syncing%s so no account is left on a different file\n' "$a" "$done_list" >&2
    if [ -f "$bdir/instruction-variants" ]; then cp -p "$bdir/instruction-variants" "$SRC/instruction-variants"; fi
    for b in $done_list $a; do resync_dir "$(dir_of "$b")"; done
    exit 1
  fi
done

# Verify by resolving every account's entries (a different call from the one that made the change).
bad=0
for a in $names; do
  d="$(dir_of "$a")"
  on_canon "$d" || { printf '0053: %s does not resolve to ~/.claude/CLAUDE.md and ~/.claude/rules\n' "$d" >&2; bad=1; }
done
[ "$bad" -eq 0 ] || { printf '0053: VERIFY FAILED. Backup: %s (links.txt, instruction-variants)\n' "$bdir" >&2; exit 1; }

# Nothing loads rules.slim any more; moving it stops cc-mission writing a second board.
if [ -d "$SRC/rules.slim" ] && [ ! -L "$SRC/rules.slim" ]; then
  mv "$SRC/rules.slim" "$bdir/rules.slim" || printf '0053: warning: could not move %s/rules.slim into the backup (harmless; nothing loads it)\n' "$SRC" >&2
fi

printf '0053: verified — every account resolves to ~/.claude/CLAUDE.md (%s variant) and ~/.claude/rules. Backup: %s. New sessions load it once.\n' "$v" "$bdir"
printf '0053: probe (auth-free): mkdir -p ~/.cc-context-probe && cd ~/.cc-context-probe && CLAUDE_CONFIG_DIR=~/.claude-quaternary claude -p /context — expect no Project row under ~/.claude/\n'
# shellcheck disable=SC2016
printf '0053: rollback: cp %s/instruction-variants %s/ && mv %s/rules.slim %s/ && for d in %s; do zsh -fc "source %s; _cc_sync_config_mirror $d"; done\n' \
  "$bdir" "$SRC" "$bdir" "$SRC" "$(for a in $names; do printf '%s ' "$(dir_of "$a")"; done)" "$MIRROR"
