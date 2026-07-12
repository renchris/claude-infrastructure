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

cfg="" model="claude-opus-4-8" effort="max"
case "$ACCT" in
  next|claude-next)            cfg="$HOME/.claude-next" ;;
  next2|claude-next2)          cfg="$HOME/.claude-secondary" ;;
  next3|claude-next3)          cfg="$HOME/.claude-tertiary" ;;
  next4|claude-next4)          cfg="$HOME/.claude-quaternary" ;;
  fable|claude-fable)          cfg="$HOME/.claude-next";       model="claude-fable-5"; effort="high" ;;
  fable2|claude-fable2)        cfg="$HOME/.claude-secondary";  model="claude-fable-5"; effort="high" ;;
  fable3|claude-fable3)        cfg="$HOME/.claude-tertiary";   model="claude-fable-5"; effort="high" ;;
  fable4|claude-fable4)        cfg="$HOME/.claude-quaternary"; model="claude-fable-5"; effort="high" ;;
  /*|~*)                       cfg="${ACCT/#\~/$HOME}" ;;
  *) echo "lr-fire-resume: unknown account '$ACCT'" >&2; exit 2 ;;
esac
[[ -n "$MODEL" ]] && model="$MODEL"
[[ -n "$EFFORT" ]] && effort="$EFFORT"
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

BIN="$HOME/.claude-183/node_modules/.bin/claude"
[[ -x "$BIN" ]] || BIN="$HOME/.claude-183/node_modules/@anthropic-ai/claude-code/bin/claude.exe"

# Single-line prompt only — the composer submits on CR; newlines are unsafe here.
PROMPT=${PROMPT//$'\n'/ }

export LR_CFG="$cfg" LR_BIN="$BIN" LR_MODEL="$model" LR_EFFORT="$effort" LR_SID="$SID" LR_PROMPT="$PROMPT"
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
