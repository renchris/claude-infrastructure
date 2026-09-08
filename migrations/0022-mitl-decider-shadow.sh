#!/bin/bash
# migration-class: c10
# migration-step: register hooks/model-permission-decider.py on PreToolUse/Bash in SHADOW mode (timeout 60) so it logs the verdicts it WOULD emit — it edits settings.json, the live permission surface, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0022-mitl-decider-shadow.sh
# migration-subject: ~/.claude/hooks/model-permission-decider.py
# migration-verify: jq -e '[.hooks.PreToolUse[]?|select(.matcher=="Bash")|.hooks[]?|select(.command|test("model-permission-decider"))|select(.command|test("MITL_MODE=shadow"))|.timeout] | any(. == 60)' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
# migration-conflict: jq -e '[.hooks.PreToolUse[]?|select(.matcher=="Bash")|.hooks[]?|select(.command|test("model-permission-decider"))|.command] | (length > 0) and (any(test("MITL_MODE=shadow")) | not)' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
#
# 0022 — the wiring half of docs/research/model-in-the-loop-permissions-2026-08-12.md. The decider
# landed DELIBERATELY UNWIRED in 112323297 and has been inert on disk since 2026-08-12: measured
# 2026-09-08, `model-permission-decider` appears in ZERO settings files across the fleet and
# ~/.claude/autonomy/mitl-decider/ does not exist, so the shadow log the enforce decision is
# supposed to rest on has a population of zero. Face 3 of the inertness generator, exactly: built,
# tested, deployed to the live layer by symlink, and registered nowhere.
#
# WHY SHADOW, AND WHY SHADOW IS THE WHOLE OF THIS MIGRATION. The decider's own header records the
# measurement that makes enforce unratifiable today: a PreToolUse `allow` BYPASSES the permission
# system completely — in the 2026-08-12 experiment an `allow` sailed past the allowed-working-
# directory write guard, a hard rule and not merely an `ask` entry. So arming enforce is a decision
# that must rest on evidence from THIS machine, and there is none. In shadow the decider emits
# nothing: main()'s `finish()` calls emit() only when MITL_MODE == "enforce", so every path here
# writes a JSONL record to ~/.claude/autonomy/mitl-decider/decisions-<YYYY-MM>.jsonl and returns 0
# with an empty stdout — byte-identical, to the harness, to the hook not being configured.
# The audit the row asks for ("a few hundred decisions, then look for any allow the operator would
# not have given") is a LATER, separate step over that log. This migration only creates the
# population.
#
# WHY THE MODE IS SPELLED IN THE REGISTRATION AND NOT LEFT TO THE DEFAULT. `MITL_MODE` defaults to
# "shadow" in the decider (two sites: main() and guarded_main()), so a bare registration would be
# shadow today. But the default is the thing that flips when enforce is eventually ratified, and a
# registration that inherits it would arm every config dir at once, silently, in a commit nobody
# read as a fleet change. Naming the mode at the registration makes the arming an explicit, greppable
# edit to settings.json — the same surface the operator would have to visit anyway. The verifier
# above therefore requires BOTH the path and `MITL_MODE=shadow`; the conflict arm reports
# `overridden` if some other value is set at that key, which is precisely the "armed without a
# ratification" state this header exists to make visible.
#
# THE ENV PREFIX IS PROVEN, NOT ASSUMED. Hook `command` strings go through a shell: the fleet
# already registers `$HOME/.claude/hooks/qos-rewrite.sh` on this same PreToolUse/Bash matcher and
# it runs, which is only possible if the string is expanded by a shell rather than exec'd directly.
# So a leading `VAR=value` assignment is honoured for the same reason `$HOME` is. `$HOME` is used
# here rather than `~` for that same measured precedent.
#
# WHY c10. settings.json is the live permission/hook surface of every account, so the converger may
# not edit it unattended; scripts/deploy-migrations.sh STAGES this and files one operator-owned step
# (event-keyed, so a re-file on every converge folds onto the same id). Promotion, if the operator
# ever wants the converger to own it, is a one-word diff on line 2.
set -uo pipefail

# shellcheck disable=SC2016  # $HOME is DELIBERATELY literal: this string is stored INTO
# settings.json, where the shell CC runs hooks under expands it at hook-run time. Expanding it here
# would hard-code this machine's $HOME into a config mirrored across five config dirs.
CMD='MITL_MODE=shadow $HOME/.claude/hooks/model-permission-decider.py'
SUBJECT="$HOME/.claude/hooks/model-permission-decider.py"
TMO=60
rc=0

command -v jq >/dev/null 2>&1 || { printf '0022: jq required\n' >&2; exit 1; }

# ── precondition, re-derived at CONSUMPTION rather than trusted from the header ──────────────────
# A registration naming a path that does not run is a registered no-op, and it reads GREEN.
# (MEMORY.md registration-precondition-must-assert-version-not-executability: -x alone can pass on a
# stale live copy, so the version check below asserts the shadow default is actually IN the file
# that would run — not merely that some file is there.)
if [ ! -x "$SUBJECT" ]; then
  printf '0022: NOT registered — %s is missing or not executable.\n' "$SUBJECT" >&2
  printf '      hooks/ is symlinked into the live layer by install.sh; run it (or deploy-live) first.\n' >&2
  exit 1
fi
if ! grep -q 'MITL_MODE' "$SUBJECT"; then
  printf '0022: NOT registered — %s does not read MITL_MODE; the live copy predates shadow mode.\n' "$SUBJECT" >&2
  exit 1
fi

for dir in "$HOME"/.claude "$HOME"/.claude-next "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  # Fleet discriminator borrowed from an entry every fleet config already carries. Testing for OUR
  # entry would be false everywhere and skip all five — a migration that always succeeds by doing
  # nothing.
  if ! jq -e '[.hooks.PreToolUse[]?|select(.matcher=="Bash")] | length > 0' "$f" >/dev/null 2>&1; then
    printf '0022: %s — no PreToolUse/Bash matcher; skipped (not a fleet config)\n' "$f"
    continue
  fi

  if jq -e --arg c "$CMD" \
       '[.hooks.PreToolUse[]?|select(.matcher=="Bash")|.hooks[]?.command] | any(. == $c)' \
       "$f" >/dev/null 2>&1; then
    printf '0022: %s — already registered\n' "$f"
    continue
  fi

  # A DIFFERENT registration of the same subject (a bare path, or MITL_MODE=enforce) is not ours to
  # silently duplicate or rewrite: appending would leave two deciders on one matcher, and rewriting
  # an enforce entry would be this script disarming a decision it never made.
  if jq -e '[.hooks.PreToolUse[]?|select(.matcher=="Bash")|.hooks[]?.command] | any(test("model-permission-decider"))' \
       "$f" >/dev/null 2>&1; then
    printf '0022: %s — a DIFFERENT model-permission-decider registration is present; left unchanged\n' "$f" >&2
    rc=1
    continue
  fi

  bak="$f.bak-0022-$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak" || { printf '0022: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; continue; }

  tmp="$f.tmp-0022-$$"
  # Append into the EXISTING Bash matcher's hooks array — never create a second Bash matcher, and
  # never clobber the siblings already there.
  # shellcheck disable=SC2016  # $c/$t are JQ variables bound by --arg/--argjson below, not shell
  # expansions. Double-quoting here would let the shell eat them before jq ever sees them.
  jq_expr='(.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks) += [{"type":"command","command":$c,"timeout":$t}]'

  if jq --arg c "$CMD" --argjson t "$TMO" "$jq_expr" "$f" > "$tmp" 2>/dev/null \
     && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    # Verify BY CONTENT before it replaces the live file, and re-assert that the other hook arrays
    # survived — a settings file that silently stops running everything it holds is the failure this
    # whole mechanism exists to prevent.
    if jq -e --arg c "$CMD" --argjson t "$TMO" \
         '([.hooks.PreToolUse[]?|select(.matcher=="Bash")|.hooks[]?|select(.command==$c)|.timeout] | any(. == $t))
          and ([.hooks.PreToolUse[]?|select(.matcher=="Bash")|.hooks[]?.command] | any(test("validate-bash")))
          and (.hooks.Stop | type == "array" and length > 0)' "$tmp" >/dev/null 2>&1; then
      mv "$tmp" "$f" && printf '0022: %s — registered (PreToolUse/Bash, shadow, timeout %s)\n' "$f" "$TMO"
      printf '0022: %s — backup: %s\n' "$f" "$bak"
    else
      rm -f "$tmp"; printf '0022: %s — edit failed its content check; left unchanged\n' "$f" >&2; rc=1
    fi
  else
    rm -f "$tmp"; printf '0022: %s — jq edit FAILED; left unchanged\n' "$f" >&2; rc=1
  fi
done

exit "$rc"
