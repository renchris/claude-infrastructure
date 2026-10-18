#!/usr/bin/env bats
# validate-bash — the SURFACE and LAUNCHER denies (lr-wake incident 2026-10-18, REPORT §4 Wave D
# and §5 Q9): kitty tabs, `handoff-fire --tab`, `handoff-fire --launcher <temp path>`, and loading a
# LaunchAgent plist the repo does not ship.
#
# This hook is live for EVERY session on the box once converged, so each deny is PAIRED with the
# sanctioned form that must still pass — the one lever apart — and with the deny's own prescribed
# remedy fed back through the hook (a guard that refuses its own cure is a defect, memory
# work-item-remedy-can-become-forbidden). Case (M) is the control that can fail: a mutant hook with
# the deny arm removed must ALLOW the incident command, so a green suite credits the arm, not the
# fixture (memory per-site-mutation-attributes-coverage).
#
# RED on origin/main: no surface rule exists, so every DENY case below reads allow there.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/validate-bash.sh"
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1 CC_WCLAIM_GATE=off CC_LINEAGE_GATE=off CC_FIRE_CAPACITY_GATE=off
  # the hook's probes name handoff-fire; pin every seam it could resolve off the live box
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/handoff-account-sweep.json" \
         CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts" CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/claude-accounts-heal-"
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
}

probe() { # <command> [hook]
  run bash -c 'jq -nc --arg c "$1" "{tool_input:{command:\$c}, cwd:\"/tmp\", session_id:\"vb-surface\"}" | "$0"' \
    "${2:-$HOOK}" "$1"
}
decision() { printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo none; }
denied() { [ "$(decision)" = deny ]; }
not_denied() { [ "$(decision)" != deny ] || { echo "DENIED: $output"; false; }; }
reason() { printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason'; }

# ── tabs ─────────────────────────────────────────────────────────────────────────────────────────
@test "DENY kitty @ launch --type=tab (and the two-token --type tab, and kitten)" {
  probe 'kitty @ launch --type=tab --keep-focus --match id:344 /bin/zsh'
  denied; reason | grep -q 'TABS ARE RETIRED' || false
  probe 'kitten @ --to unix:/tmp/kitty-1 launch --type tab --cwd=current'
  denied
}

@test "DENY a new_tab action through remote control" {
  probe 'kitty @ action new_tab_with_cwd'
  denied
}

@test "ALLOW kitty @ launch of a split, an fullscreen os-window, an ls piped to grep new_tab, a grep for --type=tab" {
  probe 'kitty @ launch --type=window --location=vsplit --match window_id:344 --next-to id:344 /bin/zsh'
  not_denied
  probe 'kitty @ launch --type=os-window --os-window-state=fullscreen --keep-focus /bin/zsh'
  not_denied
  probe 'kitty @ ls | grep -c new_tab'
  not_denied
  probe "grep -rn -- '--type=tab' bin/ scripts/"
  not_denied
}

# ── handoff-fire --tab ───────────────────────────────────────────────────────────────────────────
@test "DENY the incident's handoff-fire --tab fire verbatim (pane 344, 03:02:38Z)" {
  # shellcheck disable=SC2088  # the literal text an agent types: the hook reads it unexpanded
  probe '~/.claude/scripts/handoff-fire.sh --prompt-file /tmp/fire-8db0e6f1.txt --account next --tab --surface-reason "rescue relaunch of a stranded session, not new work"'
  denied; reason | grep -q 'split-right' || false
}

@test "DENY --tab inside a for loop and behind env assignments" {
  probe 'for s in a b; do CC_X=1 bash ~/.claude/scripts/handoff-fire.sh --prompt-file /tmp/f-$s.txt --tab; done'
  denied
}

@test "ALLOW the deny's own remedies: --split-right, and --window with the operator-rule surface reason" {
  # shellcheck disable=SC2088  # the literal text an agent types: the hook reads it unexpanded
  probe '~/.claude/scripts/handoff-fire.sh --prompt-file /tmp/fire-x.txt --worktree x --split-right --notify-back 463 --goal "x done — proven by y; do not z"'
  not_denied
  # shellcheck disable=SC2088  # the literal text an agent types: the hook reads it unexpanded
  probe '~/.claude/scripts/handoff-fire.sh --prompt-file /tmp/fire-x.txt --worktree x --window --surface-reason "operator rule: no tabs, <=4 panes"'
  not_denied
}

@test "ALLOW text that only MENTIONS --tab: a goal string, a grep, --help piped to grep, a commit message" {
  # shellcheck disable=SC2088  # the literal text an agent types: the hook reads it unexpanded
  probe '~/.claude/scripts/handoff-fire.sh --prompt-file /tmp/f.txt --split-right --goal "landed — never fire with --tab"'
  not_denied
  probe "scripts/handoff-fire.sh --help | grep -- '--tab'"
  not_denied
  probe 'git commit -m "fix: handoff-fire --tab is retired"'
  not_denied
}

# ── handoff-fire --launcher <temp> ───────────────────────────────────────────────────────────────
@test "DENY the incident's /tmp rescue launcher (e-input-gibberish.md:36, made concrete)" {
  probe 'for s8 in e52f1f63 5232121f; do cwd=$(sed -n "s/x/y/p" /tmp/lr-rescue/resume-$s8.sh); ~/.claude/scripts/handoff-fire.sh --prompt-file /tmp/p.txt --cwd "$cwd" --launcher /tmp/lr-rescue/resume-$s8.sh --account next2; done'
  denied; reason | grep -q 'lr-fleet.sh --one' || false
  probe 'handoff-fire.sh --launcher=/private/tmp/x.sh --split-right'
  denied
  probe 'handoff-fire.sh --launcher "$TMPDIR/x.sh"'
  denied
}

@test "ALLOW a --launcher that is a tier name or a repo path, and the rails the deny names" {
  # shellcheck disable=SC2088  # the literal text an agent types: the hook reads it unexpanded
  probe '~/.claude/scripts/handoff-fire.sh --prompt-file /tmp/f.txt --launcher claude-fable-x --split-right'
  not_denied
  # shellcheck disable=SC2088  # the literal text an agent types: the hook reads it unexpanded
  probe '~/.claude/scripts/limit-recover/lr-fleet.sh --one 2e9ed9f2'
  not_denied
  probe 'cc-lr recover 2e9ed9f2 --target next3'
  not_denied
}

# ── LaunchAgents (Q9) ────────────────────────────────────────────────────────────────────────────
@test "DENY loading the incident's agent-installed plist, a temp plist, and one named by a variable" {
  probe 'launchctl load -w ~/Library/LaunchAgents/com.reso.drain-to-next3.plist'
  denied; reason | grep -q 'not a plist this repo ships' || false
  probe 'launchctl bootstrap gui/501 /tmp/com.reso.drain-to-next3.plist'
  denied
  probe 'launchctl bootstrap gui/$(id -u) "$LA/$PLIST"'
  denied
  probe 'bash -c "launchctl load /tmp/x.plist"'
  denied
  probe 'out=$(launchctl load /tmp/y.plist 2>&1); echo "$out"'
  denied
}

@test "DENY a SHIPPED plist name copied to a temp dir (the name alone is not provenance)" {
  probe 'launchctl load /tmp/com.claude.deploy-live.plist'
  denied
}

@test "ALLOW loading a plist the repo ships, from ~/Library/LaunchAgents or from the repo dir" {
  [ -f "$REPO/launchd/com.claude.deploy-live.plist" ]
  [ -f "$REPO/scripts/limit-recover/com.reso.lr-reset-poller.plist" ]
  probe 'launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.claude.deploy-live.plist'
  not_denied
  probe 'launchctl load -w $HOME/Library/LaunchAgents/com.reso.lr-reset-poller.plist'
  not_denied
  probe "launchctl bootstrap gui/501 $REPO/launchd/staged/com.claude.relogin.plist"
  not_denied
}

@test "ALLOW the sanctioned installers (their launchctl runs inside the script) and read-only launchctl" {
  probe 'bash install.sh'
  not_denied
  probe 'CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh'
  not_denied
  probe 'bash scripts/limit-recover/lr-recon-launchd.sh install'
  not_denied
  probe 'bash docs/activation/pending-activation/13-mailbox-gc-activate.sh'
  not_denied
  probe 'launchctl print gui/501/com.reso.drain-to-next3'
  not_denied
  probe 'launchctl list | grep com.reso'
  not_denied
  probe 'launchctl bootout gui/501/com.reso.drain-to-next3'
  not_denied
}

# ── (M) the arm is what denies, not the fixture ──────────────────────────────────────────────────
@test "(M) a mutant hook with the surface deny arms removed ALLOWS the incident --tab fire" {
  M="$BATS_TEST_TMPDIR/mut/hooks"; mkdir -p "$M"
  ln -s "$REPO/hooks/lib" "$M/lib"
  grep -q '^    hf-tab)$' "$HOOK"                    # the anchor the mutant removes exists
  awk '/^  case "\$_vss_hit" in$/ {skip = 1} skip && /^  esac$/ {skip = 0; next} !skip' "$HOOK" > "$M/validate-bash.sh"
  ! grep -q 'hf-tab)' "$M/validate-bash.sh" || false
  # shellcheck disable=SC2088  # the literal text an agent types: the hook reads it unexpanded
  probe '~/.claude/scripts/handoff-fire.sh --prompt-file /tmp/f.txt --account next --tab' "$M/validate-bash.sh"
  not_denied
  # shellcheck disable=SC2088  # the literal text an agent types: the hook reads it unexpanded
  probe '~/.claude/scripts/handoff-fire.sh --prompt-file /tmp/f.txt --account next --tab'
  denied
}
