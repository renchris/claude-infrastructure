#!/bin/bash
# lr-fire-resume.sh — resume a (possibly transplanted) session on a given account,
# auto-answering the resume prompts, then optionally injecting one first prompt.
# Derivative of ~/.reso/bin/reso-resume-one, extended with prompt injection.
#
# Usage: lr-fire-resume.sh <account|cfg-dir> <worktree> <sid>
#          [--branch BR] [--model M] [--effort E] [--prompt "ONE-LINE"] [--repo PATH]
#
# Account labels: next next2 next3 next4 (Opus@max) · fable fable2 fable3 fable4
# (claude-fable-5@high). An absolute config-dir path is accepted as-is (Opus@max).
# Run it in the terminal/pane that should own the resumed session.
set -euo pipefail

ACCT="${1:?account}"; WT="${2:?worktree}"; SID="${3:?session-id}"; shift 3
BR="" MODEL="" EFFORT="" PROMPT="" REPO="${LR_REPO:-$HOME/Development/reso-management-app}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BR="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --prompt) PROMPT="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    *) echo "lr-fire-resume: unknown arg $1" >&2; exit 2 ;;
  esac
done

# ── the OPUS default is RESOLVED from the SSOT, never a local constant ────────────────────────────
# This line read `model="claude-opus-4-8"` and the opus path never overrode it: lr-handoff appends
# --model only on the fable branch, and the account map sets a model only when CC_ACCT_IS_FABLE=1.
# So EVERY non-fable transplant resumed on Opus 4.8 while ~/.claude/model-config.yaml has said
# `opus_latest: claude-opus-5` since 2026-07-25. That is a MODEL-GENERATION downgrade, and it is
# invisible: nothing in the resumed pane announces which model it came up on, and the operator's
# constraint for a moved session is that it returns at the SAME model and effort. Same family as the
# effort demotion one commit earlier, one level worse.
#
# FAIL CLOSED, for the reason this file already gives at the binary resolution below: a resume that
# cannot name what it is resuming ON must not silently pick something else. That is precisely how a
# stale constant survives — the fallback is what makes the wrong answer look like a working one.
# Only reached when nothing has already decided the model (a fable account, or an explicit --model),
# so an unreadable SSOT cannot break a resume that never needed it. Seam: LR_MODEL_CONFIG.
lr_resolve_opus_model() { # → opus_latest from the model-config SSOT on stdout, or empty
  local cfgfile="${LR_MODEL_CONFIG:-$HOME/.claude/model-config.yaml}" v
  [ -f "$cfgfile" ] || return 1
  # Scoped to the `versions:` block and stopping at the next top-level key: `opus_latest` must not be
  # answered by a same-named key under some other section, and `opus_prior` (claude-opus-4-8 — the
  # very id this replaces) sits on the NEXT line, so an unanchored grep would re-create the bug.
  v="$(awk '
    /^versions:/ { f = 1; next }
    f && /^[^[:space:]#]/ { exit }
    f && /^[[:space:]]+opus_latest:[[:space:]]/ { print $2; exit }
  ' "$cfgfile" 2>/dev/null | tr -d "\"' ")"
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

cfg="" model="" effort="max"
# Backed by the accounts.json-generated map (any N accounts) — see lib/account-map.generated.sh.
# shellcheck source=/dev/null
for _CC_AM in "${CC_ACCOUNT_MAP:-}" "$(dirname "$0")/../../lib/account-map.generated.sh" "$HOME/.claude/lib/account-map.generated.sh"; do
  [ -n "$_CC_AM" ] && [ -f "$_CC_AM" ] && { source "$_CC_AM"; break; }
done
case "$ACCT" in
  /*|~*)                       cfg="${ACCT/#\~/$HOME}" ;;
  *)
    if cc_acct_dir_for_name "$ACCT"; then
      cfg="$CC_ACCT_DIR"
      [ "$CC_ACCT_IS_FABLE" = 1 ] && { model="claude-fable-5"; effort="high"; }
    else
      echo "lr-fire-resume: unknown account '$ACCT'" >&2; exit 2
    fi
    ;;
esac
[[ -n "$MODEL" ]] && model="$MODEL"
[[ -n "$EFFORT" ]] && effort="$EFFORT"
# Nothing above decided a model ⇒ this is the opus path, and its default comes from the SSOT.
if [[ -z "$model" ]]; then
  model="$(lr_resolve_opus_model)" || model=""
  if [[ -z "$model" ]]; then
    echo "✗ lr-fire-resume: cannot resolve versions.opus_latest from ${LR_MODEL_CONFIG:-$HOME/.claude/model-config.yaml}." >&2
    echo "  Refusing to guess: a resume on an unnamed model generation is the silent downgrade this check exists to stop." >&2
    echo "  Pass the model explicitly (--model claude-opus-5), or repair the SSOT." >&2
    exit 1
  fi
fi
[[ -d "$cfg" ]] || { echo "lr-fire-resume: config dir $cfg missing" >&2; exit 2; }

# Recreate a reaped worktree when a branch is known (reso-resume-one logic).
if [[ ! -d "$WT" ]]; then
  if [[ -n "$BR" ]] && git -C "$REPO" show-ref --verify --quiet "refs/heads/$BR"; then
    git -C "$REPO" worktree prune 2>/dev/null || true
    git -C "$REPO" worktree add "$WT" "$BR" || exit 1
  else
    echo "lr-fire-resume: worktree $WT missing and no --branch to recreate it" >&2; exit 2
  fi
fi
cd "$WT"

# Clear crashed-session mouse-reporting garbage.
printf '\033[?1000l\033[?1002l\033[?1003l\033[?1006l\033[?1015l'

# Resolve the human-in-the-loop startup blockers AT THE SOURCE before spawning the TUI:
#   - the iTerm2 clear-scrollback GUI modal (a sheet ABOVE the PTY — expect cannot answer it)
#   - the folder-trust arrow-menu (pre-accepted in the target account's config)
# so the expect block below only has to fast-path benign, in-PTY prompts. Fail-open.
_LR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$_LR_DIR/lr-preseed-env.sh" "$cfg" "$WT" || true

# Resolve the binary from the ONE SSOT (bin/cc-claude-bin), never a local constant. This used to
# hardcode ~/.claude-183, which by 2026-08-01 was wrong twice over: that directory had been advanced
# in place to 2.1.215 (name no longer matches content), and the interactive launcher had since moved
# to ~/.claude-219 — so a limit-recover resume relaunched a session on a DIFFERENT binary than the
# one it was recovering, and on a build with no claude-opus-5 at all. Fail CLOSED: a resume that
# cannot name its binary must not silently pick another one.
BIN="$("$_LR_DIR/../../bin/cc-claude-bin" 2>/dev/null)" || BIN=""
if [[ -z "$BIN" || ! -x "$BIN" ]]; then
  echo "✗ lr-fire-resume: cannot resolve the claude binary (cc-claude-bin found none)." >&2
  echo "  Set CC_CLAUDE_BIN=/path/to/claude, or check the claude() _bin pin in ~/.zshrc." >&2
  exit 1
fi

# ── machine-capacity admission (MACHINE_CAPACITY_V2 §12.1: this path BYPASSED the only hardware
#    term in the tree). Placed HERE, immediately before the `exec expect` that actually spawns the
#    TUI, and AFTER every cheap validation above: a resume rejected for an unknown account or an
#    unresolvable binary must fail on THAT, with that message, not on a load reading.
#
#    Bounded by construction (scripts/lib/capacity-admit.sh) — §12.2 measured that the unbounded
#    gate would refuse every recovery path on a healthy box and could never recover, so a limit-
#    recovery resume must be delayable but never permanently blockable. CC_ADMIT_BUDGET consecutive
#    refusals and the next one admits + pages.
#
#    ABSENT LIBRARY IS LOUD, NOT FATAL: this is a hand-run recovery tool, and refusing to recover
#    because a telemetry library is missing would be the gate causing the outage it exists to
#    prevent. Say so on stderr and proceed ungated — the one thing it must never do is proceed
#    SILENTLY (§12.2: "inertness must be LOUD rather than a silent admit").
_LR_CA=""
for _d in "$_LR_DIR/../lib/capacity-admit.sh" \
          "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/capacity-admit.sh" \
          "$HOME/.claude/scripts/lib/capacity-admit.sh"; do
  [ -f "$_d" ] && { _LR_CA="$_d"; break; }
done
if [ -n "$_LR_CA" ]; then
  # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
  . "$_LR_CA"
  if ! cc_capacity_admit lr-fire-resume "resume $SID on $ACCT"; then
    echo "✗ $(cc_capacity_admit_reason)" >&2
    echo "  Shed load first (close finished panes / let the wave drain), then re-run this exact command." >&2
    echo "  Override for one resume: CC_ADMIT_GATE=off ; raise the bar: CC_ADMIT_MAX_LOAD_PER_CORE=<n>" >&2
    exit 9
  fi
  echo "-- $(cc_capacity_admit_reason)" >&2
else
  echo "!! lr-fire-resume: capacity-admit: ABSENT (scripts/lib/capacity-admit.sh unreachable) — spawning UNGATED" >&2
fi

# Single-line prompt only — the composer submits on CR; newlines are unsafe here.
PROMPT=${PROMPT//$'\n'/ }

export LR_CFG="$cfg" LR_BIN="$BIN" LR_MODEL="$model" LR_EFFORT="$effort" LR_SID="$SID" LR_PROMPT="$PROMPT"
# shellcheck disable=SC2016  # single quotes are REQUIRED: the body below is an expect(1) program,
#   and its $env(...)/$bin references must reach expect uninterpreted. Bash expansion here would
#   corrupt the script — the values are passed in via the LR_* environment exported above.
exec expect -c '
  set timeout 300
  set cfg    $env(LR_CFG)
  set bin    $env(LR_BIN)
  set model  $env(LR_MODEL)
  set effort $env(LR_EFFORT)
  set sid    $env(LR_SID)
  set prompt $env(LR_PROMPT)
  set injected 0
  spawn -noecho env DISABLE_AUTOUPDATER=1 CLAUDE_CONFIG_DIR=$cfg $bin --permission-mode auto --model $model --effort $effort --resume $sid
  trap {
    set rows [stty rows]
    set cols [stty columns]
    stty rows $rows columns $cols < $spawn_out(slave,name)
  } WINCH
  expect {
    -re {Resume from summary \(recommended\)} {
      # Large-session resume fix (2026-07-11): on a 400k-token session the summary
      # prompt HEADER (the "substantial portion of your usage" line) streams several
      # seconds before Ink mounts the SelectInput and enables raw mode, so a CR fired
      # the instant that header appeared (the old trigger) was swallowed and the menu
      # hung — observed on 4 monster sessions 2026-07-11. Trigger instead on option 1
      # text, which renders only once SelectInput is mounting, then settle for raw
      # mode and tap CR a few times spaced out. Extra taps land on the now-empty
      # composer (a no-op); the menu-specific trigger keeps this from firing on the
      # trust/fullscreen prompts (handled below), and it leaves the post-load
      # shortcuts signal un-consumed so --prompt injection still fires downstream.
      # RE-CHECK the "(recommended)" wording on any CC bump.
      for {set k 0} {$k < 3} {incr k} { sleep 2; send "\r" }
      exp_continue
    }
    -re {you created or one you trust|Quick safety check} { sleep 1; send "1"; send "\r"; exp_continue }
    # informational overage NOTICE (Enter dismisses either way — safe). Opt-in upsells
    # (extra-usage/remote-control/passes) are declined at the SOURCE via lr-preseed-env.sh
    # raising their *SeenCount gates — never blindly answered here (Enter could enable them).
    -re {spent .* on the Anthropic API this session} { send "\r"; exp_continue }
    # fullscreen upsell: Down+CR selects "Not now" (option 2). Order verified for CC 2.1.183 —
    # RE-CHECK on any CC bump (a reordered menu would select "Yes, try it" and restart the session).
    -re {new fullscreen renderer|Try the new fullscreen} { sleep 1; send "\033\[B"; send "\r"; exp_continue }
    -re {shift.tab to cycle|auto mode on|\? for shortcuts} {
      if {$prompt ne "" && !$injected} {
        set injected 1
        sleep 2
        send "\025"
        sleep 1
        send -- $prompt
        sleep 1
        send "\r"
      }
    }
    timeout {}
    eof { exit }
  }
  if {$injected} {
    # VERIFY the submit. A leading-/ prompt opens the slash-command autocomplete,
    # which can swallow the first CR (menu-select, not submit) — the prompt then
    # sits in the composer forever (observed 2026-07-11, ingest prompt stranded).
    # "esc to interrupt" renders only while a turn is actually running: the
    # un-fakeable submitted signal. Re-send CR until seen (an extra CR on an empty
    # composer is a no-op; on an open menu it closes/accepts it).
    set timeout 6
    set submitted 0
    for {set i 0} {$i < 5 && !$submitted} {incr i} {
      expect {
        -re {esc to interrupt} { set submitted 1 }
        timeout { send "\r" }
        eof { exit }
      }
    }
    if {!$submitted} {
      send_user "\nlr-fire-resume: WARNING — prompt may not have submitted; press Enter in the pane.\n"
    }
    set timeout 300
  }
  interact
'
