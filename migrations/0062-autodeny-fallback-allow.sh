#!/bin/bash
# migration-class: c10
# migration-step: take two in-house tools off the auto-mode classifier path that feeds the timed "will automatically deny" fallback: add the absolute/tilde spellings of cc-notify (already allowed by bare name) and of the read-only wrap-ledger.sh to permissions.allow in the ONE shared ~/.claude/settings.json (five rules, nothing removed). It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0062-autodeny-fallback-allow.sh --confirm settings.json
# migration-verify: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0062-autodeny-fallback-allow.sh" --verify
#
# ══ 0062 — narrow fallback allow rules (docs/research/autodeny-prompts-2026-10-11/, candidate C5) ═════
# The OTHER timed dialog. Claude Code 2.1.293 shows "Claude Code will automatically deny this request in
# M:SS" for two reasons: the dangerous-removal safety check (all 64 prompts in the census; NO allow rule
# can clear that one, so this migration does nothing for it — that is C1/C2's job), and the auto-mode
# classifier's denial-limit fallback: the 3rd consecutive classifier deny opens a timed dialog
# (verdicts.md, efficacy lens C4: `consecutiveDenials>=3` after the increment). An allow rule resolves
# BEFORE the classifier, so a command it covers can never be one of those three denies.
#
# The rules are spellings of tools that are already allowed or read-only. `Bash(cc-notify:*)` is a
# prefix rule, so it misses `~/.claude/bin/cc-notify …` and every other path spelling (lesson: "allow
# rule is a prefix"); `bash ~/.claude/scripts/wrap-ledger.sh` has no rule at all outside this repo's
# project settings, which carry only the relative `scripts/wrap-ledger.sh` spellings.
#
# HONEST IMPACT: small. About 1–3 fallback prompts in 6 weeks. Of the 3 inferred classifier fallbacks
# in the census, these rules break 2 streaks (2026-09-26, high confidence: the
# `~/Development/claude-infrastructure/bin/cc-notify` spelling was the 2nd deny; 2026-09-24, probable: `git ls-remote …; ~/.claude/bin/cc-notify …` becomes fully
# rule-allowed). The 2026-09-21 `kitty @ launch` streak is not covered, and there have been 0 inferred
# fallbacks since 2026-09-26. Side benefit: wrap-ledger.sh went to the classifier 59 times in the window
# and once was denied after a 242 s stage-2 classifier error; with a rule it never waits on the classifier.
# With the tengu_ticklish_whisper flag on, a rule allow does NOT reset the consecutive-deny counter; it
# only removes the deny, which is what breaks these streaks.
#
# CHECKED AGAINST THE DEPLOYED STATE (2026-10-11, read-only): none of the five, nor an equivalent, is in
# ~/.claude/settings.json (361 allow rules; the only cc-notify rule is the bare `Bash(cc-notify:*)`).
# The repo's .claude/settings.local.json has `Bash(/Users/chrisren/.claude/bin/cc-notify
# wt-opus5-upgrade-C2BFC5D4 *)`, one target only and project-scoped, so not equivalent. Every account's
# settings.json is a symlink to ~/.claude/settings.json, so one edit covers the fleet.
#
# NOT STRIPPED IN AUTO MODE (CC 2.1.293, /tmp/cc293-strings.txt): stripDangerousPermissionsForAutoMode
# (uV) drops a rule only when isDangerousBashPermission (Ydr) or isOverlyBroadBashAllowRule (xBo) holds.
# Both reduce to tIn(rule, interpreters): bare `bash`, `bash:*`, `bash *`, `bash*`, or `bash -…*`. For
# `bash ~/.claude/scripts/wrap-ledger.sh:*` the tail after `bash ` does not start with `-`, and `bash` is
# not in the network/cluster set {curl,wget,kubectl,aws,gcloud,gsutil} that gets the deeper check, so it
# survives. The other four do not start with an interpreter name at all. `~`-prefixed Bash rules are
# already in live use (`Bash(~/.claude/scripts/handoff-fire.sh:*)`).
#
# BLAST RADIUS: only ADDS five strings to permissions.allow. Nothing removed or reordered; ask and deny
# are untouched. Matching needs a word boundary (`cmd === rule || cmd.startsWith(rule + " ")`) and is
# per subcommand, so `~/.claude/bin/cc-notify x && rm -rf ~` still needs its own approval for the rm and
# `cc-notify-evil` does not match. PreToolUse hooks (validate-bash.sh) still run first.
#   · cc-notify (bin/cc-notify): all three spellings resolve to the SAME file (~/.claude/bin/cc-notify is
#     a symlink to ~/Development/claude-infrastructure/bin/cc-notify), and that binary is already granted
#     as `Bash(cc-notify:*)`, so no new capability is granted. What it does: appends one line to a
#     session inbox (~/.claude/mailbox/<uuid>.md) and its sent index, may queue a turn on an idle pane
#     through cc-wake, may send a damped phone push when the desk is down, and with --cloud sends one
#     message through cc-cloud. It deletes nothing but its own temp files; it reads launchd and iTerm2
#     state (read-only subcommands only) and never injects keystrokes.
#   · wrap-ledger.sh (scripts/wrap-ledger.sh, "pure-read Session-Close ledger computer"): its flag set is
#     fixed (--machine, --busy, --full, --goal, --readout, --session, --transcript, -h); any other argument
#     exits 2. Its only writes are its memo cache (${TMPDIR}/cc-wrap-ledger.<uid>/, temp file + atomic mv,
#     swept after 240 min), its lock dirs, and two detached cache fills: `cc-backlog list …` into the
#     shared backlog cache, and the report-only `deploy-link-parity.sh --stray-only` into
#     ~/.claude/state/link-stray.last. No git mutation, no backlog/decision writes. Stop hooks already run
#     it unattended at every close.
# Backed up first, verified by content. Rollback: the printed `cp -p` line. Takes effect in NEW sessions.
#
# Usage: bash migrations/0062-autodeny-fallback-allow.sh --dry-run | --check | --verify
#        bash migrations/0062-autodeny-fallback-allow.sh --confirm settings.json
# Exit: 0 applied / already applied / preflight ok / live · 1 failure (nothing written) or NOT live
#       (--verify) · 2 usage · 3 REFUSED, an account settings.json is forked (run 0037 first)
# shellcheck disable=SC2016  # every single-quoted string below is a jq program; $a/$want are jq variables
set -uo pipefail

N=0062
f="$HOME/.claude/settings.json"
parity="${CC_SETTINGS_PARITY_BIN:-$HOME/.claude/bin/cc-settings-parity}"
# Through its interpreter, never by path: a #! exec keeps ~1.1 KiB of kernel memory on macOS 15.8.1
# (docs/research/kalloc-longterm-2026-10-21/REPORT.md). Read from its own #! line, so a stub still runs.
_pl=""; IFS= read -r _pl < "$parity" 2>/dev/null || true
case "$_pl" in *python3*) parity_cmd=(/usr/bin/env python3 "$parity") ;; *) parity_cmd=("$parity") ;; esac
command -v jq >/dev/null 2>&1 || { printf '%s: jq required — nothing written\n' "$N" >&2; exit 1; }

mode=""
case "${1:-}" in
  --dry-run) mode=dry ;;
  --check) mode=check ;;
  --verify) mode=verify ;;
  --confirm) [ "${2:-}" = "settings.json" ] || { printf '%s: --confirm must name its target: --confirm settings.json\n' "$N" >&2; exit 2; }
             [ -z "${3:-}" ] || { printf '%s: unknown argument %s after --confirm settings.json\n' "$N" "$3" >&2; exit 2; }
             mode=apply ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;
  *) printf '%s: unknown argument %s (use --dry-run, --check, --verify or --confirm settings.json)\n' "$N" "$1" >&2; exit 2 ;;
esac
[ -n "$mode" ] || { printf '%s: pass --dry-run, --check, --verify or --confirm settings.json\n' "$N" >&2; exit 2; }

# The absolute spelling is this home's own path (on the operator's box: /Users/chrisren/.claude/bin/cc-notify).
WANT="$(jq -cn --arg abs "Bash($HOME/.claude/bin/cc-notify:*)" '[
  "Bash(~/.claude/bin/cc-notify:*)",
  $abs,
  "Bash(~/Development/claude-infrastructure/bin/cc-notify:*)",
  "Bash(bash ~/.claude/scripts/wrap-ledger.sh:*)",
  "Bash(~/.claude/scripts/wrap-ledger.sh:*)"
]')" || { printf '%s: could not build the rule list — nothing written\n' "$N" >&2; exit 1; }
missing() { jq -c --argjson want "$WANT" '$want - (.permissions.allow // [])' "$1" 2>/dev/null; }
has_rules() { [ "$(missing "$1")" = "[]" ]; }

[ -f "$f" ] || { printf '%s: %s not found — nothing written\n' "$N" "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '%s: %s is not valid JSON — nothing written\n' "$N" "$real" >&2; exit 1; }

if [ "$mode" = verify ]; then
  has_rules "$f" && { printf '%s: live — %s carries all five fallback allow rules\n' "$N" "$f"; exit 0; }
  printf '%s: NOT live — %s lacks: %s\n' "$N" "$f" "$(missing "$f")" >&2; exit 1
fi

jq -e '(.permissions // {}) | (.allow // []) | type == "array"' "$real" >/dev/null 2>&1 \
  || { printf '%s: permissions.allow is not an array — left unchanged\n' "$N" >&2; exit 1; }
"${parity_cmd[@]}" check >/dev/null 2>&1 || {
  printf '%s: REFUSED — accounts do not all share %s (%s check failed). Converge with 0037 first.\n' "$N" "$f" "$parity" >&2
  exit 3
}

if has_rules "$real"; then
  printf '%s: already applied — %s carries all five fallback allow rules\n' "$N" "$real"
  exit 0
fi
printf '%s: will add to permissions.allow in %s: %s\n' "$N" "$real" "$(missing "$real")"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written\n' "$N"; exit 0 ;;
  check) printf '%s: preflight ok — accounts share one file, the edit is well-formed; nothing written\n' "$N"; exit 0 ;;
esac

bdir="$HOME/.claude/backups/autodeny-fallback-allow-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '%s: backup FAILED — nothing written\n' "$N" >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
EDIT='.permissions = ((.permissions // {}) | .allow = ((.allow // []) + ($want - (.allow // []))))'
if ! jq --argjson want "$WANT" "$EDIT" "$real" > "$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '%s: jq edit FAILED — nothing written\n' "$N" >&2; exit 1
fi
same_rest=$(jq -n --slurpfile a "$real" --slurpfile b "$tmp" '($a[0] | del(.permissions.allow)) == ($b[0] | del(.permissions.allow))')
kept=$(jq -n --slurpfile a "$real" --slurpfile b "$tmp" '($b[0].permissions.allow[0:(($a[0].permissions.allow // []) | length)]) == ($a[0].permissions.allow // [])')
if [ "$same_rest" != true ] || [ "$kept" != true ] || ! has_rules "$tmp"; then
  rm -f "$tmp"; printf '%s: edit did not verify by content — nothing written\n' "$N" >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '%s: write FAILED — nothing written\n' "$N" >&2; exit 1; }
printf '%s: fallback allow rules added. Backup: %s/settings.json (restore: cp -p %s/settings.json %s)\n' "$N" "$bdir" "$bdir" "$real"
"${parity_cmd[@]}" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with the line above\n' "$N" >&2
has_rules "$f" || { printf '%s: did NOT verify through %s\n' "$N" "$f" >&2; exit 1; }
printf '%s: verified — %s carries all five rules. Takes effect in new sessions.\n' "$N" "$f"
exit 0
