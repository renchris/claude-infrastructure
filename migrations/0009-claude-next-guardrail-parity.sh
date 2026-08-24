#!/bin/bash
# shellcheck disable=SC2088  # file-wide: the tildes in the `wire` calls are DELIBERATELY unexpanded.
# They are literal settings.json values, expanded by the harness at dispatch, and `~/.claude/hooks/X`
# is the spelling the other four config dirs already carry. Substituting $HOME would write a
# machine-absolute path into a file whose whole purpose here is to MATCH its siblings.
# migration-class: c10
# migration-step: restore the 7 guardrail hooks that .claude-next alone is missing (unattended-ask guard, session-deregister, desk-brief-inject, session-beat x2, handed-off-session-guard, coldcompile-admit) — it links 5 hook files and edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0009-claude-next-guardrail-parity.sh
# migration-subject: ~/.claude-next/settings.json
# migration-verify: jq -e '[.hooks.PreToolUse[].hooks[]?.command] + [.hooks.SessionEnd[].hooks[]?.command] + [.hooks.SessionStart[].hooks[]?.command] + [.hooks.Stop[].hooks[]?.command] + [.hooks.UserPromptSubmit[].hooks[]?.command] | map(tostring) | (any(test("cc-unattended-ask-guard\\.sh")) and any(test("session-deregister\\.sh")) and any(test("desk-brief-inject\\.sh")) and any(test("session-beat\\.sh stop")) and any(test("session-beat\\.sh prompt")) and any(test("handed-off-session-guard\\.sh")) and any(test("coldcompile-admit\\.sh")))' "$HOME/.claude-next/settings.json" >/dev/null
# migration-conflict: test -e "$HOME/.claude-next/hooks" && ! test -L "$HOME/.claude-next/hooks" && ! test -e "$HOME/.claude-next/hooks/session-beat.sh"
#
# The conflict oracle separates the two ways this can read unsatisfied, because they need OPPOSITE
# fixes. "Not delivered" = the settings entries were never added. "Overridden" = the entries exist
# but .claude-next/hooks/ is still the forked real dir missing their targets — in which case adding
# settings entries made it WORSE, not better (see WHY THE LINKS COME FIRST below).
#
# ══ 0009 — the guardrail-parity restoration for .claude-next ═══════════════════════════════════
# Backlog: 4ce34a4f703c.  Measured 2026-08-11 (the item's own 2026-07-29 numbers had decayed; the
# disproof is filed as a sibling item).
#
# WHAT IS WRONG. The fleet runs five INDEPENDENT config dirs and picks one BY ACCOUNT at fire time,
# so the guardrail set a session gets is a side effect of quota routing: what a session MAY DO
# depends on which account fired it. Measured across all five settings.json today, 70 of 75 distinct
# (event, hook) pairs are wired everywhere and 5 are missing from .claude-next ALONE:
#
#     PreToolUse      | cc-unattended-ask-guard.sh     ← a PERMISSION RAIL, not a nicety
#     SessionEnd      | session-deregister.sh
#     SessionStart    | desk-brief-inject.sh
#     Stop            | session-beat.sh stop
#     UserPromptSubmit| session-beat.sh prompt
#
# ── SIXTH ENTRY ADDED 2026-08-22 (backlog ba255d25bdc3), and the DATE is the point ────────────────
#
#     UserPromptSubmit| handed-off-session-guard.sh    ← wired with NO timeout key; see wire()
#
# This was NOT an omission in the list above. hooks/handed-off-session-guard.sh was added to the repo
# on 2026-08-17 (bac277d95); this migration was written on 2026-08-11 (a19e3d9cf), six days EARLIER.
# The list was complete over its population when written, and the population then grew.
#
# That is the mechanism worth recording, because it will happen again. A new fleet-wide hook reaches
# the three symlinked config dirs' hooks/ for free, but settings.json is a REAL FILE in all five dirs
# — nothing symlinks it, and install.sh merges only into the ONE $CONFIG_DIR it is invoked for. So
# every hook wired into the canonical settings.json needs .claude-next wired by hand, i.e. by a c10
# migration, EVERY TIME. 0013 (unforking .claude-next/hooks) cures the FILE half of this permanently
# and is the right long-term fix; it does not cure the SETTINGS half, and nothing currently does.
# A recurring gap with no owning mechanism is the thing to fix, not each instance of it — but that is
# a fleet-wide design call, and this migration's job is parity for the instances now on the board.
#
# ── SEVENTH ENTRY ADDED 2026-08-24 (drain recycle #194), and it does NOT fit the story above ──────
#
#     PreToolUse      | coldcompile-admit.sh           ← matcher "Bash", timeout 10
#
# The paragraph above predicted its own next failure — "it will happen again" — and it did. But the
# DATE does not support the same explanation, and saying so is the point of recording it. hooks/
# coldcompile-admit.sh landed 2026-08-09 (8db131c2a), TWO DAYS BEFORE this migration was written on
# 2026-08-11 (a19e3d9cf). handed-off-session-guard.sh was genuinely later (bac277d95, 2026-08-16);
# this one was not. So one of two things is true, and THIS REPO CANNOT DISTINGUISH THEM: either the
# 2026-08-11 census under-counted a pair that was already wired, or the pair was wired into the
# canonical settings.json some time after the file landed. `~/.claude/settings.json` is a real,
# UNTRACKED file — it is not a symlink into this repo, and the tracked `.claude/settings.json` is
# this repo's own project settings and carries none of the fleet hook set — so there is no history to
# date the WIRING against, only the file's own add. Recorded as unresolved rather than guessed.
#
# What is NOT in doubt is today's state, measured 2026-08-24 with the independent detector rather
# than with this file's own list: scripts/settings-drift-assert.sh reports FIVE divergences, all
# "missing in: .claude-next", and coldcompile-admit.sh is one of them. The other four are this
# migration's own — and session-beat.sh x2 is NOT among them, because it is already wired in
# .claude-next (both events, target resolves), so two of the six entries above are now no-ops.
#
# THE CONSEQUENCE FOR THE OPERATOR, which is why this is a code change and not a note. Backlog row
# 6a428f48fd2e instructs "run migration 0009 — expect: 5 divergences -> GREEN". Before this edit that
# was FALSE: 0009 wired six entries, four of which are drift-list members, and left coldcompile-admit
# untouched, so the true outcome was 5 -> 1. Worse, the `migration-verify:` predicate on line 10 is
# keyed on this migration's OWN enumeration and never mentioned coldcompile, so the migration runner
# would have marked the step verified while step 3's drift assertion — an independent detector —
# still printed DRIFT. A gate keyed on its own signal cannot see what its author did not list. Both
# halves are fixed here: the wire below, and the seventh clause in `migration-verify`.
#
# `claude` — the bare launcher, i.e. account 1 and the busiest — defaults to CLAUDE_CONFIG_DIR=
# ~/.claude-next (~/.zshrc:460). So the dir missing the unattended-ask guard is not an obscure
# fallback; it is the default.
#
# WHY ONLY THIS DIR, AND WHY IT CANNOT SELF-HEAL. This is the load-bearing finding, and it is why a
# settings-only fix would be wrong. ~/.claude-next/hooks is a FORKED REAL DIRECTORY (53 entries);
# .claude-secondary, .claude-tertiary and .claude-quaternary each symlink hooks -> ~/.claude/hooks
# (75 entries). The mirror (lib/config-mirror.zsh:78-81) runs in safe mode by default and, on
# finding a forked real dir, `continue`s rather than converting it — deliberately, because
# converting mv's the real dir aside and is unsafe while that account has live panes. The
# consequence is that .claude-next silently misses EVERY hook file added since its fork, forever,
# while the three symlinked dirs converge for free. That is the whole explanation for the item's
# "2 of 5" becoming "1 of 5" with nobody acting: .claude-quaternary self-healed because it
# symlinks. .claude-next did not because it does not.
#
# WHY THE LINKS COME FIRST (the ordering is load-bearing, not tidiness). Five of the six hook
# TARGETS are absent from .claude-next/hooks: cc-unattended-ask-guard.sh, desk-brief-inject.sh,
# session-beat.sh, handed-off-session-guard.sh and coldcompile-admit.sh (re-measured 2026-08-24).
# (session-deregister.sh is already linked — its settings entry is simply missing.)
# A settings.json entry pointing at a hook file that does not exist is not inert: the harness
# dispatches it and the exec fails, on EVERY matching event. For PreToolUse that is every Bash /
# AskUserQuestion call in the account. So wiring before linking would convert a missing guardrail
# into a broken account — strictly worse than the defect. This migration links first, verifies each
# link resolves, and wires ONLY what it has already proven runnable.
#
#   ⚠️ CORRECTION 2026-08-22 — the hazard that ordering guards against does not actually exist here,
#   and the paragraph above is kept only because the ordering it produces is still the right one.
#   Every hook COMMAND in .claude-next/settings.json is spelled `~/.claude/hooks/…`; 0 of 66 resolve
#   through $CLAUDE_CONFIG_DIR (measured 2026-08-22, and 0013's header measures the same thing
#   independently at :31-38). So a settings entry reaches the CANONICAL hooks dir and cannot dangle
#   on account of .claude-next/hooks/ lacking the file — mailbox-wake-arm.sh and goal-inert-watch.sh
#   are already wired there while equally absent from that dir, with the account running. Link-first
#   is therefore ADDITIVE AND HARMLESS rather than load-bearing: it is retained because the links are
#   independently wanted (they are what the 55 runtime $CLAUDE_CONFIG_DIR/hooks/… resolution sites
#   read), not because wiring first would break anything. Do not cite this paragraph as evidence for
#   the dangling-hook hazard elsewhere.
#
# SCOPE — deliberately 5 files, not the 22 that differ. .claude-next/hooks is 22 entries behind
# ~/.claude/hooks. This migration links exactly the five it wires and no others. The remaining 17
# are filed separately: deciding whether each absence is a fork artifact or a deliberate omission is
# a judgment call per file, and a blind 22-file sweep on a C10 surface would activate hooks in the
# default account that nobody chose to activate there. Fixing the forked-dir GENERATOR (converting
# hooks/ to a symlink) is likewise filed, not done here — it requires every .claude-next pane
# closed, which a migration cannot assert.
#
#   WHY THE SIXTH ENTRY IS NOT THAT SWEEP, stated explicitly because the counter moved from 4 to 5.
#   The declined sweep and this addition are over DIFFERENT POPULATIONS. The 22 are hook FILES absent
#   from .claude-next/hooks; for most of them no settings.json anywhere wires them, so wiring one
#   WOULD be activating something in the default account that nobody chose — which is the objection,
#   and it stands. handed-off-session-guard.sh is in the intersection: an absent file that the OTHER
#   FOUR config dirs already wire, and that settings-drift-assert.sh therefore names as a divergence
#   in its own output. Adding it activates nothing new fleet-wide; it stops one account being the
#   exception. The selection rule this migration has always used is "the lines the detector names",
#   and that rule is what picked the sixth — not a widened net. 0013 remains the answer for the 22.
#
# IDEMPOTENT + REVERSIBLE. Every step is skip-if-already-done. Each settings write is preceded by a
# timestamped backup and followed by a by-content verify; a failed verify restores and reports. The
# links are additive (ln -sfn into the existing real dir) — nothing is moved or deleted, so the
# rollback for the link half is `rm` of the three links.
# bash 3.2-safe.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '0009: jq required\n' >&2; exit 1; }

SRC_HOOKS="${CC_SRC_HOOKS:-$HOME/.claude/hooks}"
DST="${CC_DST_CONFIG:-$HOME/.claude-next}"
DST_HOOKS="$DST/hooks"
F="$DST/settings.json"
rc=0

[ -f "$F" ] || { printf '0009: %s absent — nothing to do (not a fleet config)\n' "$F"; exit 0; }

# ── 1. LINK the hook files this migration is about to wire ────────────────────────────────────────
# Only these four. Each is verified to resolve to a readable file AFTER linking, because a link
# created against a missing source is exactly the dangling-hook hazard described above.
for h in cc-unattended-ask-guard.sh desk-brief-inject.sh session-beat.sh session-deregister.sh \
         handed-off-session-guard.sh coldcompile-admit.sh; do
  src="$SRC_HOOKS/$h"
  dst="$DST_HOOKS/$h"
  if [ ! -f "$src" ]; then
    printf '0009: SOURCE MISSING %s — cannot link or wire %s\n' "$src" "$h" >&2; rc=1; continue
  fi
  if [ -e "$dst" ]; then
    printf '0009: hooks/%s — already present\n' "$h"; continue
  fi
  mkdir -p "$DST_HOOKS" 2>/dev/null
  if ln -sfn "$src" "$dst" 2>/dev/null && [ -f "$dst" ]; then
    printf '0009: hooks/%s — linked -> %s\n' "$h" "$src"
  else
    rm -f "$dst" 2>/dev/null
    printf '0009: hooks/%s — link FAILED or does not resolve; left absent\n' "$h" >&2; rc=1
  fi
done

# ── 2. WIRE the five settings entries ─────────────────────────────────────────────────────────────
# Each row: <event> <matcher-or-empty> <command> <timeout-or-empty> <match-substring>
# An empty timeout writes NO `timeout` key — the spelling the four sibling dirs carry for
# handed-off-session-guard.sh. See wire()'s header for why a plausible 5 would be wrong there.
# The command spellings are copied from ~/.claude/settings.json so the drift assertion (which
# normalizes by basename+args) sees them as the SAME hook.
# ONE backup for the whole run, taken lazily before the FIRST write and never again.
#
# It used to be taken inside wire(), i.e. once per entry — which is wrong in two ways that only a
# test caught. The backup became a MOVING TARGET: the fifth one captured a file that already had
# four of this migration's edits in it, so "restore the backup" had no single meaning. And the file
# COUNT was clock-dependent — five writes inside one second collapse onto one name, five that
# straddle a tick leave five — so rollback instructions could not even say which file to name.
# Lazily, so a fully-wired (idempotent) re-run writes no backup at all.
BAK=""
ensure_backup() { # → 0 backup exists (or was just made) · 1 could not make one
  [ -n "$BAK" ] && return 0
  # declared and assigned separately: `local b=$(…)` returns local's own status, so a failing `date`
  # would go unnoticed and silently name the backup "$F.bak-0009-" — a fixed name that the NEXT run
  # would then overwrite, quietly destroying the only pre-migration copy.
  local stamp b
  stamp="$(date +%Y%m%d%H%M%S)" || return 1
  b="$F.bak-0009-$stamp"
  cp -p "$F" "$b" || return 1
  BAK="$b"
  printf '0009: backup taken: %s\n' "$BAK"
  return 0
}

wire() { # <event> <matcher> <command> <timeout|""> <hook-file-that-must-exist>
  # An EMPTY timeout means "write no `timeout` key at all", and it is a spelling this function has to
  # be able to produce rather than a nicety. The fleet's canonical settings.json carries 81 hook
  # entries WITH a timeout and 3 without — keychain-guard.sh, waiting-recycle.sh and
  # handed-off-session-guard.sh — and this migration's whole contract is that .claude-next ends up
  # MATCHING its four siblings. Substituting a plausible 5 for an absent key would satisfy
  # settings-drift-assert.sh, because that detector normalizes by basename+args and never compares
  # timeouts (scripts/settings-drift-assert.sh:14,26) — i.e. it would close the drift line while
  # silently minting a divergence the detector is structurally blind to. Whether those three SHOULD
  # carry a ceiling is a real question (scripts/settings-hook-timeouts.sh exists to answer it, and its
  # header argues yes), but it is a fleet-wide C10 judgment owned elsewhere; a parity migration that
  # answered it unilaterally, in one dir, would be deciding it by side effect.
  local ev="$1" matcher="$2" cmd="$3" tmo="$4" needs="$5" tmp

  # never wire a hook whose target is not runnable — the whole point of step 1's ordering
  if [ ! -f "$DST_HOOKS/$needs" ]; then
    printf '0009: %s/%s — target hooks/%s absent; NOT wired (would fail on every event)\n' \
      "$ev" "$cmd" "$needs" >&2; rc=1; return
  fi

  if jq -e --arg ev "$ev" --arg c "$cmd" \
       '[.hooks[$ev][]?.hooks[]?.command] | map(tostring) | any(. == $c)' "$F" >/dev/null 2>&1; then
    printf '0009: %s | %s — already wired\n' "$ev" "$cmd"; return
  fi

  ensure_backup || { printf '0009: %s — backup FAILED, not touching it\n' "$F" >&2; rc=1; return; }

  tmp="$F.tmp-0009-$$"
  # Append into the EXISTING matcher group when one exists, else create that group. Never disturb a
  # sibling group: a matcher group is a dispatch unit, and folding two together silently changes
  # which events every hook in them sees.
  if jq --arg ev "$ev" --arg m "$matcher" --arg c "$cmd" --argjson t "${tmo:-null}" '
        ( {"type":"command","command":$c}
          + (if $t == null then {} else {"timeout":$t} end) ) as $entry
        | .hooks[$ev] = (
          (.hooks[$ev] // []) as $groups
          | ( [ $groups | to_entries[]
                | select( (if $m == "" then (.value.matcher // "") == ""
                           else (.value.matcher // "") == $m end) ) | .key ] ) as $hit
          | if ($hit | length) > 0
            then ( $groups | .[$hit[0]].hooks += [$entry] )
            else ( $groups + [ (if $m == "" then {} else {matcher:$m} end)
                               + {hooks:[$entry]} ] )
            end
        )' "$F" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    # verify BY CONTENT before replacing the live file: present exactly once, under the right event
    if jq -e --arg ev "$ev" --arg c "$cmd" \
         '[.hooks[$ev][]?.hooks[]? | select((.command | tostring) == $c)] | length == 1' \
         "$tmp" >/dev/null 2>&1; then
      mv "$tmp" "$F" && printf '0009: %s | %s — wired\n' "$ev" "$cmd"
    else
      rm -f "$tmp"; printf '0009: %s | %s — edit did not verify; left unchanged\n' "$ev" "$cmd" >&2; rc=1
    fi
  else
    rm -f "$tmp"; printf '0009: %s | %s — jq edit FAILED; left unchanged\n' "$ev" "$cmd" >&2; rc=1
  fi
}

wire PreToolUse       "AskUserQuestion" "~/.claude/hooks/cc-unattended-ask-guard.sh" 5 cc-unattended-ask-guard.sh
wire SessionEnd       ""                "~/.claude/hooks/session-deregister.sh"      5 session-deregister.sh
wire SessionStart     ""                "~/.claude/hooks/desk-brief-inject.sh"       5 desk-brief-inject.sh
wire Stop             ""                "~/.claude/hooks/session-beat.sh stop"       5 session-beat.sh
wire UserPromptSubmit ""                "~/.claude/hooks/session-beat.sh prompt"     5 session-beat.sh
wire UserPromptSubmit ""                "~/.claude/hooks/handed-off-session-guard.sh" "" handed-off-session-guard.sh
# Matcher "Bash" and timeout 10 are not chosen — they are the spelling .claude, .claude-secondary and
# .claude-quaternary all three carry verbatim, read off them 2026-08-24. Same reasoning as the empty
# timeout above: this migration's contract is that .claude-next ends up MATCHING its siblings, so a
# plausible value substituted here would mint a divergence settings-drift-assert.sh cannot see.
wire PreToolUse       "Bash"            "~/.claude/hooks/coldcompile-admit.sh"       10 coldcompile-admit.sh

# ── 3. report the drift assertion's verdict, so the migration's own effect is measured ────────────
DRIFT_BIN="${CC_DRIFT_BIN:-$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")/scripts/settings-drift-assert.sh}"
if [ -x "$DRIFT_BIN" ]; then
  printf '0009: post-migration drift assertion —\n'
  bash "$DRIFT_BIN" 2>&1 | sed 's/^/0009:   /'
else
  printf '0009: NOTE — settings-drift-assert.sh not executable at %s; effect unmeasured\n' "$DRIFT_BIN" >&2
fi

exit "$rc"
