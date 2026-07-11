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
    -re {Resume from summary} { send "\r"; exp_continue }
    -re {substantial portion of your usage} { send "\r"; exp_continue }
    -re {shift.tab to cycle|auto mode on|\? for shortcuts} {
      if {$prompt ne "" && !$injected} {
        set injected 1
        sleep 2
        send -- $prompt
        sleep 1
        send "\r"
      }
    }
    timeout {}
    eof { exit }
  }
  interact
'
