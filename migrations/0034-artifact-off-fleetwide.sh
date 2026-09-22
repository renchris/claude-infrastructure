#!/bin/bash
# migration-class: c10
# migration-step: set enableArtifact=false in every config dir's settings.json so the Artifact tool and its three artifact-* skills are off fleet-wide — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0034-artifact-off-fleetwide.sh
# migration-verify: jq -e '.enableArtifact == false' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
# migration-conflict: jq -e 'has("enableArtifact") and .enableArtifact != false' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
#
# 0034 — operator request 2026-09-21: turn the claude.ai Artifact publisher off.
#
# WHAT IT TURNS OFF, AND WHY THIS ONE KEY IS THE WHOLE LEVER. Measured by reading the running
# binary (~/.claude-260/.../bin/claude.exe, 2.1.260), the artifact surface resolves through ONE
# predicate:
#
#   var Gl = { enableKey:"enableArtifact", legacyDisableKey:"disableArtifact",
#              envDisableVar:"CLAUDE_CODE_DISABLE_ARTIFACT", defaultOn:true }
#   function l1e(){ return Wl(Gl) }
#   function Ar(){ return !l1e().enabled }            // "artifact surface is off"
#
# and every consumer hangs off it:
#   - the Artifact TOOL            isArtifactToolEnabled -> getEnableArtifactPref() ?? defaultOn
#   - reading published artifacts  isArtifactReadEnabled, same pref
#   - the three bundled SKILLS     function JI(){ return P3t()===null }
#                                  function P3t(){ if(Ar()) return "switched_off"; ... }
#     and artifact-design / artifact-diagramming / artifact-capabilities are each registered with
#     `isEnabled: JI`. So one key retires the tool AND all three skills.
#
# WHY NOT DISABLE THE SKILL INSTEAD. That was the obvious move and it does NOT work: the binary
# carries a fallback that INLINES the same rules whenever the skill is missing —
#   "**Page contract** (the `artifact-design` skill is not available in this session,
#     so its rules follow here):"
# so suppressing the skill (disableBundledSkills, deletion, shadowing) leaves the identical house
# styling in the prompt while also killing every OTHER bundled skill. The tool-level switch is the
# only lever that removes the styling guidance rather than relocating it.
#
# WHY enableArtifact AND NOT disableArtifact. Both work — `disableArtifact:true` is honoured as
# `legacyDisableKey`. `enableArtifact` is the current key, it is the one `/config` writes when the
# toggle is user-controllable (isEnableArtifactUserControllable), and writing the current key keeps
# a later TUI toggle reading the same field instead of fighting a legacy one.
#
# PRECEDENCE HAS NO TRAP HERE. The resolver (Vl) walks policySettings, flagSettings, userSettings
# and pushes a disable if ANY layer carries enableKey===false or legacyDisableKey===true. Disable
# wins from any layer, so a user-settings false cannot be silently outvoted.
#
# WHY IT WRITES EVERY CONFIG DIR. ~/.claude, -next, -tertiary and -quaternary each hold a separate
# REAL settings.json (verified 2026-09-21: none is a symlink, and none carries any of these keys
# today, so all four run the defaultOn=true path). Sessions launch against all four. Writing one
# leaves three accounts still publishing.
#
# BLAST RADIUS. Removing a publish surface, never widening one. It also turns off READING published
# artifacts through the tool (isArtifactReadEnabled shares the pref) — accepted: the operator's
# stated use is neither publishing nor reading. Fully reversible with no state to unwind: flip the
# value to true, or delete the key to return to the vendor default. Each file is backed up first
# and every edit is verified BY CONTENT before it replaces the live file.
#
# TAKES EFFECT IN NEW SESSIONS. Already-running panes keep the tool they started with.
set -uo pipefail

rc=0
changed=0
command -v jq >/dev/null 2>&1 || { printf '0034: jq required\n' >&2; exit 1; }

for dir in "$HOME"/.claude "$HOME"/.claude-next "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  if ! jq -e . "$f" >/dev/null 2>&1; then
    printf '0034: %s — not valid JSON; left unchanged\n' "$f" >&2; rc=1; continue
  fi

  if jq -e '.enableArtifact == false' "$f" >/dev/null 2>&1; then
    printf '0034: %s — already off\n' "$f"
    continue
  fi

  bak="$f.bak-0034-$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak" || { printf '0034: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; continue; }

  tmp="$f.tmp-0034-$$"
  if jq '.enableArtifact = false' "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    # Verify BY CONTENT: the key is false, AND no sibling key was lost. A jq slip that emitted a
    # one-key object would be valid JSON, would satisfy the verifier above, and would silently
    # delete the whole fleet config — the failure this repo has measured most often is an edit that
    # reads GREEN while destroying what it sat beside.
    before_keys=$(jq -r 'keys[]' "$f" | sort | tr '\n' ' ')
    after_keys=$(jq -r 'keys[]|select(. != "enableArtifact")' "$tmp" | sort | tr '\n' ' ')
    if jq -e '.enableArtifact == false' "$tmp" >/dev/null 2>&1 && [ "$before_keys" = "$after_keys" ]; then
      mv "$tmp" "$f" && printf '0034: %s — enableArtifact=false (backup: %s)\n' "$f" "$bak" && changed=$((changed+1))
    else
      rm -f "$tmp"; printf '0034: %s — edit did not verify; left unchanged\n' "$f" >&2; rc=1
    fi
  else
    rm -f "$tmp"; printf '0034: %s — jq edit FAILED; left unchanged\n' "$f" >&2; rc=1
  fi
done

printf '0034: %d config dir(s) changed. Takes effect in NEW sessions.\n' "$changed"
printf '0034: to revert — jq \x27del(.enableArtifact)\x27 on each settings.json, or set it to true.\n'
exit "$rc"
