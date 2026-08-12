#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 39-smart-allowlist  —  wire hooks/smart-bash-allowlist.sh into the LIVE per-account settings.json
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: adds ONE entry to the FRONT of the existing PreToolUse `Bash` group, in every config dir:
#
#     PreToolUse[matcher="Bash"].hooks  ^= ~/.claude/hooks/smart-bash-allowlist.sh   (timeout 5)
#
#   FRONT, not append, and that placement is the hook's own documented contract: it runs BEFORE
#   validate-bash.sh so that its "allow" is the first non-empty decision. Order is not a safety
#   property here — a `deny` from any hook still overrides an `allow` from this one — but appending
#   would contradict the file's header and mislead the next reader.
#
# WHAT IT BUYS: the auto-mode classifier prompts on COMPOUND commands (`cd … && …`,
#   `export PATH=…; …`, `set -e`), which is what the beacon archive actually measures — 1,124
#   resolved prompts since 2026-07-31. A permissions.allow PATTERN can never reach those, because a
#   pattern is matched against the WHOLE command string. A PreToolUse hook is matched against
#   nothing — it reads the command and decides. That is the entire reason this exists, and the
#   reason the 30 allow-patterns landed in 86e354262 do not make it redundant.
#
# WHAT IT AUTO-APPROVES — three rules, none of which touch anything the operator has gated:
#     1  git commit            (never --no-verify; that is refused upstream in the same file)
#     3  sed -i <file>         target under $PWD, and not in DENY_DIR/DENY_SENSITIVE
#     5  chmod <safe-mode>     644/755/600/700/750/640/+x/u+x only, target under $PWD
#     6  sed -n <script>       read-only paging, positive-whitelisted address+print forms
#
# WHAT IT NO LONGER AUTO-APPROVES (retired in 732147576, BEFORE this activation was written):
#     2  rm -rf <build artifacts>      — deletion stays behind the operator's own gate
#     4  git push origin <feature>     — `Bash(git push:*)` is an operator `ask` rule
#   Both were removed because a PreToolUse hook emitting "allow" BYPASSES the permission system, so
#   wiring this would otherwise have silently revoked an `ask` rule as a side effect of a
#   prompt-reduction change — the rule would still sit in settings.json and simply stop working.
#   Rule 4 was additionally DEAD (its own extraction regex is an invalid character range, so
#   /usr/bin/grep exited 2 and it never fired) while carrying a reject list that omitted main and
#   master — so repairing the "typo" would have armed `git push origin main`. See
#   tests/smart-bash-allowlist-narrow.bats, which pins all of this against the pre-fix blob.
#
# WHY C10 (agent stages it; operator runs it): this mutates the live harness config of every
#   account, and it widens what proceeds without consent. The agent does not self-activate that.
#
# SAFETY: per-dir backup to <dir>/settings.json.pre-smart-allowlist.bak BEFORE any write · jq only,
#   never sed · post-write validation (parses AND the command is present AND it is at index 0 of the
#   Bash group) · a failed validation RESTORES that dir's backup and ABORTS LOUD · already-wired dirs
#   are SKIPPED (idempotent) · a dir with no PreToolUse Bash group is SKIPPED LOUD rather than having
#   one invented for it.
#
# KILL SWITCH (no rollback needed to silence it): SMART_ALLOWLIST_DISABLED=1 in the environment makes
#   the hook exit 0 before deciding anything.
#
# RUN IT:   CONFIRM=1 bash ~/.claude/autonomy/pending-activation/39-smart-allowlist-activate.sh
# Dry run:  bash ~/.claude/autonomy/pending-activation/39-smart-allowlist-activate.sh
# Rollback: bash ~/.claude/autonomy/pending-activation/39-smart-allowlist-activate.sh --rollback
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
LIVE="${CC_LIVE_DIR:-$HOME/.claude}"
BAK_SUFFIX=".pre-smart-allowlist.bak"
HOOK_REL="hooks/smart-bash-allowlist.sh"
# shellcheck disable=SC2088  # the tilde MUST stay literal: this string is written INTO settings.json,
# where Claude Code expands it itself. Every sibling hook command in that file is spelled the same way,
# and settings-drift-assert.sh normalizes by basename so a $HOME-expanded spelling would still compare
# equal — but it would be the only absolute machine-specific path in the file, and it would break the
# moment the config is copied to another box.
HOOK_CMD='~/.claude/hooks/smart-bash-allowlist.sh'
MATCH='smart-bash-allowlist'

DEFAULT_DIRS="$HOME/.claude $HOME/.claude-next $HOME/.claude-secondary $HOME/.claude-tertiary $HOME/.claude-quaternary"
CANDIDATE_DIRS="${CC_CONFIG_DIRS:-$DEFAULT_DIRS}"

echo "== 39-smart-allowlist =="
echo "repo: $REPO"

command -v jq >/dev/null 2>&1 || { echo "✗ jq required" >&2; exit 1; }

# ---- --rollback -----------------------------------------------------------------------------------
if [ "${1:-}" = "--rollback" ]; then
  echo "[rollback] restoring every $BAK_SUFFIX"
  n=0
  for d in $CANDIDATE_DIRS; do
    b="$d/settings.json$BAK_SUFFIX"
    [ -f "$b" ] || continue
    if jq -e . "$b" >/dev/null 2>&1; then
      cp -a "$b" "$d/settings.json" && rm -f "$b" && { echo "  ← $d/settings.json restored"; n=$((n+1)); }
    else
      echo "  ✗ $b does not parse — REFUSING to restore it. Fix by hand." >&2
    fi
  done
  [ "$n" -gt 0 ] && echo "✓ rolled back $n dir(s). The symlink is left in place (inert when unwired)." \
                 || echo "· nothing to roll back."
  exit 0
fi

# ---- preflight ------------------------------------------------------------------------------------
[ -f "$REPO/$HOOK_REL" ] || {
  echo "✗ hook not in the checkout: $REPO/$HOOK_REL" >&2
  echo "  (is the checkout on a trunk carrying 732147576? git -C $REPO pull --ff-only)" >&2
  exit 1; }

# Refuse to wire a hook that still carries the retired rules — this script's whole safety argument is
# that rules 2 and 4 are gone. A checkout predating 732147576 would silently wire the dangerous file.
if grep -qE '^\s*(GIT_PUSH_MATCH|RM_MATCH|SAFE_RM_TARGETS)=' "$REPO/$HOOK_REL"; then
  echo "✗ $REPO/$HOOK_REL still defines the RETIRED rule 2 / rule 4 variables." >&2
  echo "  This activation is only safe against the narrowed hook (732147576). Update the checkout." >&2
  exit 1
fi

DIRS=""
for d in $CANDIDATE_DIRS; do [ -f "$d/settings.json" ] && DIRS="$DIRS $d"; done
[ -n "$DIRS" ] || { echo "✗ no config dir with a settings.json found in: $CANDIDATE_DIRS" >&2; exit 1; }

# index of the PreToolUse group whose matcher is exactly "Bash" (null when absent)
bash_group_idx() { jq -r '[.hooks.PreToolUse // [] | to_entries[] | select(.value.matcher == "Bash") | .key][0] // "null"' "$1"; }
is_wired()       { jq -e --arg m "$MATCH" '[.hooks[]?[]?.hooks[]?.command? // empty] | any(contains($m))' "$1" >/dev/null 2>&1; }

echo
echo "Will do:"
echo "  0  ensure live symlink: $LIVE/$HOOK_REL"
for d in $DIRS; do
  S="$d/settings.json"
  if is_wired "$S"; then                       echo "  ·  $S — already wired, WILL SKIP"
  elif [ "$(bash_group_idx "$S")" = null ]; then echo "  !  $S — no PreToolUse Bash group, WILL SKIP (loud)"
  else                                          echo "  +  $S — prepend $HOOK_CMD to PreToolUse group $(bash_group_idx "$S") (backup → settings.json$BAK_SUFFIX)"
  fi
done
echo

if [ "${CONFIRM:-0}" != 1 ]; then
  echo "(dry run — nothing was written. Re-run with CONFIRM=1 to apply:)"
  echo "    CONFIRM=1 bash $LIVE/autonomy/pending-activation/39-smart-allowlist-activate.sh"
  exit 0
fi

# ---- 0: live symlink ------------------------------------------------------------------------------
echo "[0] live symlink under $LIVE"
if [ -L "$LIVE/hooks" ]; then
  echo "  = $LIVE/hooks is a dir-symlink ($(readlink "$LIVE/hooks")) — per-file link not applicable"
else
  src="$REPO/$HOOK_REL" dest="$LIVE/$HOOK_REL"
  if [ -e "$dest" ]; then echo "  = $dest"
  else
    mkdir -p "$(dirname "$dest")"
    ln -sfn "$src" "$dest" && echo "  → $dest (linked)" || { echo "  ✗ failed to link $dest" >&2; exit 1; }
  fi
fi

# ---- 1: wire each settings.json -------------------------------------------------------------------
echo "[1] settings.json"
ENTRY=$(jq -nc --arg c "$HOOK_CMD" '{type:"command", command:$c, timeout:5}')
wired=0; skipped=0; nogroup=0
for d in $DIRS; do
  S="$d/settings.json"
  if is_wired "$S"; then echo "  = $S (already wired)"; skipped=$((skipped+1)); continue; fi

  IDX=$(bash_group_idx "$S")
  if [ "$IDX" = null ]; then
    echo "  ! $S — no PreToolUse group with matcher \"Bash\". SKIPPED, not invented." >&2
    nogroup=$((nogroup+1)); continue
  fi

  B="$S$BAK_SUFFIX"
  cp -a "$S" "$B" || { echo "  ✗ backup failed — refusing to touch $S" >&2; exit 1; }

  tmp="$S.smart-allowlist-tmp.$$"
  if ! jq --argjson e "$ENTRY" --argjson i "$IDX" \
        '.hooks.PreToolUse[$i].hooks = ([$e] + (.hooks.PreToolUse[$i].hooks // []))' \
        "$S" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"; cp -a "$B" "$S"
    echo "  ✗ jq edit FAILED on $S — RESTORED from $B, file UNCHANGED. ABORTING." >&2
    exit 1
  fi
  mv -f "$tmp" "$S"

  # post-write validation: parses, the command is present, and it is at index 0 of the Bash group
  if ! jq -e . "$S" >/dev/null 2>&1 \
     || ! is_wired "$S" \
     || [ "$(jq -r --arg m "$MATCH" --argjson i "$IDX" '.hooks.PreToolUse[$i].hooks[0].command | contains($m)' "$S" 2>/dev/null)" != true ]; then
    cp -a "$B" "$S"
    echo "  ✗ post-write validation FAILED on $S — RESTORED from $B. ABORTING." >&2
    exit 1
  fi
  echo "  → $S (prepended to PreToolUse group $IDX; backup at $B)"
  wired=$((wired+1))
done

echo
echo "✓ wired=$wired  skipped=$skipped  no-bash-group=$nogroup"
[ "$wired" -gt 0 ] && {
  echo "  Verify:  jq -r '.hooks.PreToolUse[] | select(.matcher==\"Bash\") | .hooks[0].command' $HOME/.claude/settings.json"
  echo "  Silence without rollback:  export SMART_ALLOWLIST_DISABLED=1"
  echo "  Undo:    bash $LIVE/autonomy/pending-activation/39-smart-allowlist-activate.sh --rollback"
}
exit 0
