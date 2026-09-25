#!/bin/bash
# migration-class: c10
# migration-step: switch EVERY account (next, next2, next3, next4) to the slim instructions: each account's CLAUDE.md -> ~/.claude/CLAUDE.slim.md and rules/ -> ~/.claude/rules.slim (compact mission board only), via cc-instructions-variant. The F1 gate PASSED on 2026-09-25 (GATE.md § R4.5): 300 runs per arm pooled, success 94.7% vs 95.0% (CI lower bound -4.0 pp, margin -5), compliance 96.3% vs 96.4%, cost -34.1% per task (p<0.001), no guardrail worse; conviction 85%. All accounts or none; it refuses unless ~/.claude/CLAUDE.slim.md is byte-for-byte the gated file. Rewrites the account CLAUDE.md links, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0042-slim-claude-md-all-accounts.sh --confirm all-accounts
# migration-verify: [ -r "$HOME/.claude/accounts.json" ] && ! jq -r '.accounts[].config_dir' "$HOME/.claude/accounts.json" | sed "s|^~|$HOME|" | while IFS= read -r d; do [ "$(readlink "$d/CLAUDE.md")" = "$HOME/.claude/CLAUDE.slim.md" ] || echo miss; done | grep -q miss
#
# The verifier is config-dir-INVARIANT: it reads the one shared accounts.json and every account's link.
#
# ══ 0042 — slim instructions on every account (token-efficiency F1, round 4 + extension) ════════════
# WHAT IT CHANGES. Nothing in the repo and nothing in ~/.claude/CLAUDE.md. Each account config dir's
# CLAUDE.md is a symlink to the shared ~/.claude/CLAUDE.md, and its rules/ to ~/.claude/rules. This
# re-points both for every account, through the sanctioned switch `cc-instructions-variant set <acct>
# slim`, which records each account in ~/.claude/instruction-variants and logs the switch to
# ~/.claude/autonomy/instruction-variants.jsonl (so a census can split sessions by arm).
#
# WHY IT SURVIVES install.sh AND THE CONFIG MIRROR (the question a bare swap gets wrong).
#   · install.sh copies CLAUDE.global.md -> ~/.claude/CLAUDE.md whenever they differ. Overwriting
#     ~/.claude/CLAUDE.md with the slim text would therefore be reverted by the NEXT install run. This
#     migration never touches that file; the full text stays the SSOT and stays deployed.
#   · install.sh also copies CLAUDE.global.slim.md -> ~/.claude/CLAUDE.slim.md, so the slim file an
#     account now reads stays current with the repo, exactly as the full one does.
#   · The config mirror re-points every account entry at each session start, and it honours the
#     registry (lib/config-mirror.zsh, _cc_instructions_variant_target), so the arm is re-asserted,
#     not undone. tests/config-mirror-instructions-variant.bats pins that.
#   So the registry IS the durable state, and it lives outside every tree install.sh rewrites.
#
# WHAT THE GATE CERTIFIED, AND THE PIN. The gate tested one exact slim file, sha256 d446c60e…
# (round4/arms-MANIFEST.sha256), derived from the full file cecd5a0c…. If CLAUDE.global.slim.md is
# edited later, install.sh deploys the edit and this migration REFUSES: an ungated variant does not
# ship under this verdict. Re-gate it, then update PIN below. `cc-instructions-variant status`
# reports STALE when the full file moves past the one the slim file was derived from.
#
# ALL OR NONE (operator ruling 2026-09-23: accounts are interchangeable). If any account's switch
# fails, every account this run switched is reset before exit 1.
#
# Takes effect in NEW sessions only; running sessions keep what they loaded.
# Rollback (one line): for a in next next2 next3 next4; do ~/.claude/bin/cc-instructions-variant reset "$a"; done
#
# Usage: bash migrations/0042-slim-claude-md-all-accounts.sh --dry-run
#        bash migrations/0042-slim-claude-md-all-accounts.sh --confirm all-accounts
# bash 3.2-safe.
set -uo pipefail

PIN=d446c60e80a67db1e664473daf0218f83d6151cdf229c7220395d47793901a9e
SRC="$HOME/.claude"
SLIM="$SRC/CLAUDE.slim.md"
CIV="${CC_INSTRUCTIONS_VARIANT_BIN:-$SRC/bin/cc-instructions-variant}"
command -v jq >/dev/null 2>&1 || { printf '0042: jq required — nothing written\n' >&2; exit 1; }

mode=""
case "${1:-}" in
  --dry-run) mode=dry ;;
  --confirm) [ "${2:-}" = "all-accounts" ] || { printf '0042: --confirm must name its target: --confirm all-accounts\n' >&2; exit 2; }; mode=apply ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;
  *) printf '0042: unknown argument %s (use --dry-run or --confirm all-accounts)\n' "$1" >&2; exit 2 ;;
esac
[ -n "$mode" ] || { printf '0042: pass --dry-run to preview or --confirm all-accounts to apply\n' >&2; exit 2; }

[ -x "$CIV" ] || { printf '0042: %s not found — nothing written\n' "$CIV" >&2; exit 1; }
[ -f "$SLIM" ] || { printf '0042: %s not deployed (install.sh copies CLAUDE.global.slim.md) — nothing written\n' "$SLIM" >&2; exit 1; }
got="$({ shasum -a 256 "$SLIM" 2>/dev/null || sha256sum "$SLIM"; } | cut -d' ' -f1)"
[ "$got" = "$PIN" ] || {
  printf '0042: REFUSED — %s is sha256 %s, not the gated file %s. An ungated variant does not ship under the F1 verdict; re-gate it first.\n' "$SLIM" "$got" "$PIN" >&2
  exit 1
}

names="$(jq -r '.accounts[]?.name // empty' "$SRC/accounts.json" 2>/dev/null)"
[ -n "$names" ] || { printf '0042: no accounts in %s/accounts.json — nothing written\n' "$SRC" >&2; exit 1; }

dir_of() { jq -r --arg a "$1" '.accounts[]? | select(.name == $a) | .config_dir // empty' "$SRC/accounts.json" | sed "s|^~|$HOME|"; }

todo=""
for a in $names; do
  d="$(dir_of "$a")"
  if [ "$(readlink "$d/CLAUDE.md" 2>/dev/null)" = "$SLIM" ] && [ "$(readlink "$d/rules" 2>/dev/null)" = "$SRC/rules.slim" ]; then
    printf '0042: %s already on slim\n' "$a"
  else
    todo="$todo $a"
  fi
done
[ -z "$todo" ] && { printf '0042: already applied — every account reads %s\n' "$SLIM"; exit 0; }

printf '0042: will switch to slim:%s (CLAUDE.md -> %s, rules/ -> %s/rules.slim)\n' "$todo" "$SLIM" "$SRC"
[ "$mode" = dry ] && { printf '0042: DRY RUN — nothing written\n'; exit 0; }

bdir="$SRC/backups/slim-claude-md-0042-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" || { printf '0042: backup dir FAILED — nothing written\n' >&2; exit 1; }
[ -f "$SRC/instruction-variants" ] && cp -p "$SRC/instruction-variants" "$bdir/instruction-variants"
for a in $names; do
  d="$(dir_of "$a")"
  printf '%s CLAUDE.md=%s rules=%s\n' "$a" "$(readlink "$d/CLAUDE.md" 2>/dev/null)" "$(readlink "$d/rules" 2>/dev/null)"
done > "$bdir/links.txt"

done_list=""
for a in $todo; do
  if "$CIV" set "$a" slim; then
    done_list="$done_list $a"
  else
    printf '0042: switch FAILED on %s — resetting%s so no account is left on a different arm\n' "$a" "$done_list" >&2
    for b in $done_list; do "$CIV" reset "$b" >/dev/null 2>&1 || printf '0042: reset of %s ALSO failed — see %s/links.txt\n' "$b" "$bdir" >&2; done
    exit 1
  fi
done

# Verify by reading every link back (a different call from the one that made the change).
bad=0
for a in $names; do
  d="$(dir_of "$a")"
  [ "$(readlink "$d/CLAUDE.md")" = "$SLIM" ] || { printf '0042: %s/CLAUDE.md does not read back as %s\n' "$d" "$SLIM" >&2; bad=1; }
done
[ -f "$SRC/rules.slim/00-mission-board.md" ] || printf '0042: warning: %s/rules.slim has no mission board yet; the next session start renders it\n' "$SRC" >&2
# The two rollback lines print a literal "$a" for the operator to paste.
# shellcheck disable=SC2016
[ "$bad" -eq 0 ] || { printf '0042: VERIFY FAILED. Roll back: for a in next next2 next3 next4; do %s reset "$a"; done\n' "$CIV" >&2; exit 1; }
printf '0042: verified — every account reads %s (sha256 %s). Backup: %s. New sessions load it.\n' "$SLIM" "${PIN:0:16}" "$bdir"
# shellcheck disable=SC2016
printf '0042: rollback: for a in next next2 next3 next4; do %s reset "$a"; done\n' "$CIV"
