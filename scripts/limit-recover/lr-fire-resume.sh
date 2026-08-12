#!/bin/bash
# lr-fire-resume.sh — resume a (possibly transplanted) session on a given account,
# auto-answering the resume prompts, then optionally injecting one first prompt.
# Derivative of ~/.reso/bin/reso-resume-one, extended with prompt injection.
#
# Usage: lr-fire-resume.sh <account|cfg-dir> <worktree> <sid>
#          [--branch BR] [--model M] [--effort E] [--prompt "ONE-LINE"] [--repo PATH]
#          [--summary] [--force-split]
#
# Account labels: next next2 next3 next4 (Opus@max) · fable fable2 fable3 fable4
# (claude-fable-5@high). An absolute config-dir path is accepted as-is (Opus@max).
# Run it in the terminal/pane that should own the resumed session.
#
#   --summary      Resume from a /compact SUMMARY instead of the full session. OPT-IN, and it
#                  COSTS: the summary is produced by a real /compact turn, so it spends usage on
#                  the recovering account and the resumed session comes back with compacted
#                  fidelity — the /goal, the exact tool history and the un-summarised reasoning
#                  are gone. Use it for cheap recovery of a session whose detail no longer
#                  matters. The DEFAULT is a zero-loss as-is resume (see § THE AS-IS DEFAULT).
#   --force-split  Resume a session that has already been TRANSPLANTED to another account,
#                  deliberately creating two live copies. See § THE TOMBSTONE GUARD.
set -euo pipefail

ACCT="${1:?account}"; WT="${2:?worktree}"; SID="${3:?session-id}"; shift 3
BR="" MODEL="" EFFORT="" PROMPT="" REPO="${LR_REPO:-$HOME/Development/reso-management-app}"
SUMMARY=0 FORCE_SPLIT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BR="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --prompt) PROMPT="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --summary) SUMMARY=1; shift ;;
    --force-split) FORCE_SPLIT=1; shift ;;
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

# ── WIDTH-INVARIANT PROMPT MATCHING ──────────────────────────────────────────────────────────────
# THE DEFECT (backlog c4b016c2d2a6). Every arm below used to match a LITERAL phrase, e.g.
# `Resume from summary \(recommended\)`. That is not a property of the prompt, it is a property of
# the prompt AT A PARTICULAR TERMINAL WIDTH. Ink hard-wraps a narrow pane mid-word, and it also
# emits an SGR colour sequence in the middle of a styled label, so the phrase a human reads is
# almost never contiguous in the byte stream. Measured 2026-08-10 against real captures of Claude
# Code 2.1.220's own select component at 8/20/40/80 columns: the literal
# `Dark mode (colorblind-friendly)` appears at NO width at all — not even 80 — because a colour
# escape sits between "mode " and "(colorblind". The old arms worked by luck on unstyled phrases in
# wide panes, and three transplants parked 20+ minutes at the menu in panes of 8 and ~18 columns.
#
# The polarity is the worst kind: panes get NARROWER as more sessions are split in, so a literal
# match fails hardest exactly when a recovery matters most, and it is green in any wide dev pane.
#
# THE CURE: match the phrase's characters in order, allowing only WRAP CHROME between them —
# ANSI escape sequences, whitespace/newlines, and box rules. Nothing alphanumeric may intervene, so
# the match stays tight: it cannot drift across an adjacent menu option, because that option's own
# letters and digits block it. Spaces in the phrase are dropped entirely rather than required,
# because word-wrap CONSUMES the space it breaks on ("from summary" → "from\nsummar").
lr_wrap_re() { # phrase → an expect(1)/Tcl regex that matches it at ANY terminal width
  local phrase="$1" out="" ch i n
  # CHARACTERS, NOT BYTES — and this function must decide that for itself, because every phrase it
  # is called with carries `❯`, the selector glyph, which is THREE BYTES in UTF-8. `${#phrase}` and
  # `${phrase:i:1}` split by character only under a multibyte LC_CTYPE; under C/POSIX they split by
  # byte, so `❯2.` becomes five fragments, each separately backslash-escaped into the Tcl regex,
  # and the readback that confirms which option the selector is on stops matching. That readback is
  # the entire safety of answering this menu: without it the arm cannot tell option 1 (`Resume from
  # summary` — runs /compact, spends usage, drops the session goal) from option 2 (`Resume full
  # session as-is`), which is the second defect recorded in this file's own history.
  # This is NOT hypothetical and NOT only a test concern: nothing else in this script pins a locale,
  # so any C-locale caller — launchd, cron, a headless recovery — got the byte split. It surfaced as
  # 8 of 11 reds in tests/lr-resume-answer-width.bats off-box, where the harness pins LC_ALL=C
  # (scripts/offbox-run.sh); the ASCII-only cases stayed green, which is why it read as width-
  # specific rather than locale-specific.
  # The probe is bash's OWN splitting, not an external tool's: `${#probe}` is the exact operation
  # the walk below depends on, and both LC_ALL and LC_CTYPE are function-local, so nothing outside
  # this call sees the change. If no UTF-8 locale exists the loop leaves the last candidate set and
  # the walk degrades to the old byte behaviour rather than erroring — strictly no worse than before.
  local LC_ALL='' LC_CTYPE probe='❯'
  for LC_CTYPE in C.UTF-8 en_US.UTF-8 UTF-8; do
    probe='❯'
    [ "${#probe}" -eq 1 ] && break
  done
  # ANSI CSI (colour, cursor-move) | any whitespace incl. the wrap newline | box rules.
  local SEP=$'(?:\033\\[[0-9;?]*[a-zA-Z]|[[:space:]]|│|┃|┆|╎)*' 
  n=${#phrase}
  for (( i=0; i<n; i++ )); do
    ch="${phrase:$i:1}"
    [ "$ch" = " " ] && continue          # a wrapped space may be absent — never require it
    case "$ch" in
      [a-zA-Z0-9]) out+="$ch" ;;
      *)           out+="\\$ch" ;;       # escape regex metacharacters: ( ) . - ' etc.
    esac
    out+="$SEP"
  done
  printf '%s' "$out"
}

# ── THE TOMBSTONE GUARD ──────────────────────────────────────────────────────────────────────────
# THE DEFECT (backlog 24c9955d6c4f). lr-transplant.sh writes a per-session tombstone — the lock at
# ~/.reso/limit-recover/locks/<sid>.lock, naming the account the session MOVED TO. That lock guarded
# the TRANSPLANT path only: nothing on the RESUME path ever read it. On 2026-08-10 17:36Z the
# operator ran /limit-recover in the three ORIGINAL panes the morning after an overnight transplant.
# The recovery opened the tombstone directory — it wrote its own audit INTO it — and resumed anyway.
# Two sessions went live in two accounts at once; one diverged and landed independently.
#
# A tombstone that is only ever WRITTEN is a record. Reading it on the path that can cause the harm
# is what makes it a guard.
#
# WHICH RESUMES ARE REFUSED. Not all of them — resuming ON the transplant target is the whole point
# of a transplant, and a guard that blocked it would break the primary path. The discriminator is
# WHERE this resume is landing: the target itself is the successor and is always allowed; any OTHER
# account is a second live copy of a moved session, which is exactly the incident.
#
# WHY ABSENCE-OF-SUCCESSOR IS THE ONLY AUTOMATIC ALLOW. Control (b) requires that a tombstone whose
# successor is provably dead must NOT block a real recovery — a guard that strands a recovery is
# worse than the bug. The tempting test is "the successor transcript has not been touched for N
# hours", and it is rejected on precedent: stamp-age as a liveness proxy goes FALSE during exactly
# the long quiet runs that matter, so it would hand back a false all-clear on a live session. What
# IS provable from disk is ABSENCE: the tombstone names a target that holds no transcript for this
# sid at all, so there is no second copy to collide with. Everything else prints the successor's
# last activity and hands the judgement to the operator behind --force-split.
lr_tombstone_verdict() { # sid resuming-cfg-dir → reason on stdout; rc 0 = allowed, 3 = refused
  local sid="$1" here="$2"
  local state="${LR_STATE_DIR:-$HOME/.reso/limit-recover}"
  local lock="$state/locks/$sid.lock"
  local to to_real here_real hits=() line acct

  [ -f "$lock" ] || { echo "no tombstone for $sid — never transplanted"; return 0; }

  # No pipe. `sed … | head -1` under `set -o pipefail` returns 141 once the producer outruns the
  # ~64KB pipe buffer and head exits while sed is still writing — measured at 262KB: rc 141.
  # STATED PRECISELY, because the obvious stronger claim is false and a mutant proved it: at THIS
  # call site the fault is latent, not live. The function is invoked as an `if` condition, which
  # suppresses `set -e`, and the substitution still captures what head printed before it died — so
  # the verdict came out identical either way. It is fixed as a SHAPE (the ship gate's rule): the
  # same line one refactor away from a plain call site would abort the resume at the moment it
  # found the target. There is deliberately no test for it: a control that cannot fail is worse
  # than no control, because it reads as coverage.
  to="$(sed -n '/"to":"/{s/.*"to":"\([^"]*\)".*/\1/p;q;}' "$lock")"
  if [ -z "$to" ]; then
    # FAIL CLOSED. An unparseable tombstone means we cannot say where the session went, and
    # "cannot say" is not "nowhere" — this is the one case where refusing is the safe answer.
    echo "tombstone $lock exists but names no target — refusing to guess where $sid went"
    return 3
  fi

  _lr_rp() { if [ -d "$1" ]; then (cd "$1" && pwd -P); else printf '%s' "$1"; fi; }
  to_real="$(_lr_rp "$to")"; here_real="$(_lr_rp "$here")"
  if [ "$to_real" = "$here_real" ]; then
    echo "this IS the transplant target ($to) — the successor resuming itself"
    return 0
  fi

  while IFS= read -r line; do [ -n "$line" ] && hits+=("$line"); done \
    < <(ls "$to"/projects/*/"$sid".jsonl 2>/dev/null || true)
  if [ ${#hits[@]} -eq 0 ]; then
    echo "tombstone names $to, but no transcript for $sid survives there — successor is gone, recovery allowed"
    return 0
  fi

  acct="$(cc_acct_name_for_dir_basename "$(basename "$to_real")" 2>/dev/null || true)"
  [ -n "$acct" ] || acct="$(basename "$to_real")"
  echo "REFUSED — $sid was transplanted away and its successor is still on disk."
  echo "  went to:      $acct  ($to)"
  echo "  successor:    ${hits[0]}"
  echo "  last activity: $(date -r "${hits[0]}" -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)"
  echo "  tombstone:    $lock"
  return 3
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

# Split-brain refusal BEFORE any side effect (no worktree creation, no config writes, no TUI).
if _LR_TV="$(lr_tombstone_verdict "$SID" "$cfg")"; then
  echo "-- lr-fire-resume: tombstone check: $_LR_TV" >&2
else
  if [[ $FORCE_SPLIT -eq 1 ]]; then
    echo "!! lr-fire-resume: --force-split — resuming a transplanted session ANYWAY:" >&2
    printf '%s\n' "$_LR_TV" | sed 's/^/   /' >&2
    echo "   Two live copies of $SID now exist. Land from only ONE of them." >&2
  else
    printf 'lr-fire-resume: %s\n' "$_LR_TV" >&2
    echo "  Resume it where it actually went, or if you deliberately want two live copies," >&2
    echo "  re-run this exact command with --force-split." >&2
    exit 3
  fi
fi

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

# ── THE AS-IS DEFAULT ────────────────────────────────────────────────────────────────────────────
# THE DEFECT (backlog d1490376b963). This script pressed Enter on the HIGHLIGHTED DEFAULT of the
# resume-return menu, which is option 1, `Resume from summary (recommended)`. That runs /compact:
# it spends a real turn of the recovering account's usage, returns the session with compacted
# fidelity, and drops its /goal. Option 2 is literally `Resume full session as-is`. The operator's
# constraint for a moved session is that it comes back AS-IS — that is the whole point of a
# zero-loss transplant — so the script was answering the opposite of the requirement, silently.
#
# THE CURE IS AT THE SOURCE, not at the keyboard. Claude Code decides whether to show that menu in
# one function, and both of its thresholds are read from the ENVIRONMENT
# (`Rue(process.env.CLAUDE_CODE_RESUME_THRESHOLD_MINUTES, 70)`, where Rue falls back to the default
# on unset-or-NaN). A session younger than the threshold never reaches the dialog and simply resumes
# FULL AS-IS — which is the behaviour we want. So raising the threshold out of reach is not a
# keystroke trick: it removes the question instead of answering it. Nothing is rendered, so no
# terminal width can break it, and it is structurally impossible to land on option 3,
# `Don't ask me again`, which is unrecoverable and would silently disable the dialog account-wide.
#
# THIS IS VERSION-COUPLED, AND THAT IS WHY THE FALLBACK BELOW STILL EXISTS. The env var is read
# through an internal symbol of the 2.1.220 bundle; a future build can drop or rename it, and then
# the menu comes back and this script goes inert without saying so. The expect arm below therefore
# stays fully wired and is exercised by its own test with the suppression FORCED OFF
# (LR_RESUME_SUPPRESS=off) — a fallback with no test is a fallback we would discover is broken
# during the next recovery. RE-CHECK the var name on any CC bump.
if [[ $SUMMARY -eq 0 && "${LR_RESUME_SUPPRESS:-on}" != "off" ]]; then
  export CLAUDE_CODE_RESUME_THRESHOLD_MINUTES=999999999
  echo "-- lr-fire-resume: resume-summary prompt suppressed at the source — resuming FULL AS-IS" >&2
elif [[ $SUMMARY -eq 1 ]]; then
  echo "!! lr-fire-resume: --summary — resuming from a /compact SUMMARY (spends usage, loses fidelity and the /goal)" >&2
fi

# Width-invariant answers for every in-PTY prompt this script fast-paths. Each menu answer is
# ORDINAL-ANCHORED and READ BACK before it is committed: the option ORDER is verified against the
# 2.1.220 bundle's own option arrays, but a reordered menu in a later build must not be able to
# select something destructive, so nothing is ever sent blind. RE-CHECK the wordings on any CC bump.
LR_RE_MENU="$(lr_wrap_re '❯1. Resume')"
LR_RE_ASIS_STRONG="$(lr_wrap_re '❯2. Resume full')"
LR_RE_ASIS="$(lr_wrap_re '❯2. Resume')"
LR_RE_TRUST="$(lr_wrap_re 'Quick safety check')"
LR_RE_TRUST_RB="$(lr_wrap_re '❯1. Yes, I trust')"
LR_RE_FS="$(lr_wrap_re 'Try the new fullscreen renderer')"
LR_RE_FS_RB="$(lr_wrap_re '❯2. Not now')"
LR_RE_OVERAGE="$(lr_wrap_re 'on the Anthropic API this session')"
export LR_RE_MENU LR_RE_ASIS_STRONG LR_RE_ASIS LR_RE_TRUST LR_RE_TRUST_RB LR_RE_FS LR_RE_FS_RB LR_RE_OVERAGE
# The post-load "ready" signal gates --prompt injection. It lives in the status line, which wraps in
# a narrow pane exactly like everything else — so a literal match here did not merely mis-answer a
# menu, it silently DROPPED the injected prompt and left the recovered session sitting idle.
LR_RE_READY="$(lr_wrap_re 'for shortcuts')|$(lr_wrap_re 'auto mode on')|$(lr_wrap_re 'shift+tab to cycle')"
export LR_RE_READY
export LR_ASIS="$(( SUMMARY == 0 ? 1 : 0 ))"
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
  set asis $env(LR_ASIS)
  set menu_answered 0
  # A wrapped prompt spans far more bytes than expect buffers by default (2000): at 8 columns one
  # menu is several KB of text and cursor-move chrome. A width-invariant pattern that cannot fit in
  # the match buffer is not width-invariant at all.
  match_max 200000
  spawn -noecho env DISABLE_AUTOUPDATER=1 CLAUDE_CONFIG_DIR=$cfg $bin --permission-mode auto --model $model --effort $effort --resume $sid

  # Move the selector to option $steps+1 and CONFIRM it landed there before committing. Returns 1
  # when confirmed and the CR was sent, 0 when it could not be confirmed — in which case NOTHING is
  # sent and the prompt is deliberately left for a human. Parking costs minutes; a blind CR on an
  # unconfirmed selector costs a /compact, and a blind extra Down costs the do-not-ask-again option, which
  # is unrecoverable. RE-CHECK on any CC bump: the ordinal is the anchor, never the position.
  proc answer_menu {steps strong weak what {pre 0}} {
    for {set i 0} {$i < $steps} {incr i} { send "\033\[B"; sleep 1 }
    if {$pre} {
      # The arm that called us matched the SELECTOR LINE itself, so the option is already
      # confirmed and there is nothing further to read back. Re-reading here cannot work and must
      # not be attempted: expect consumes the buffer up to the end of a match, so the anchor the
      # readback needs has already been eaten, and with no keystroke sent nothing repaints it —
      # the readback would time out forever and park a prompt that was correctly identified.
      send "\r"
      send_user "\nlr-fire-resume: $what — selector confirmed by the trigger, answered.\n"
      return 1
    }
    set timeout 10
    set seen ""
    expect {
      -re $strong { set seen "label" }
      timeout {
        # A narrow pane TRUNCATES a long option label (measured at 8 columns), so the full label is
        # not always readable. The ordinal is, and it is what identifies the option.
        expect { -re $weak { set seen "ordinal" } timeout { set seen "" } }
      }
    }
    set timeout 300
    if {$seen ne ""} {
      send "\r"
      send_user "\nlr-fire-resume: $what — selector confirmed by $seen, answered.\n"
      return 1
    }
    send_user "\nlr-fire-resume: WARNING — could not confirm the selector for $what; sent NOTHING.\n"
    send_user "  Answer it by hand in this pane. Refusing to guess: the next option down is destructive.\n"
    return 0
  }
  trap {
    set rows [stty rows]
    set cols [stty columns]
    stty rows $rows columns $cols < $spawn_out(slave,name)
  } WINCH
  expect {
    -re $env(LR_RE_MENU) {
      # The resume-return menu rendered anyway — the source suppression above did not take (an
      # older/newer binary, or LR_RESUME_SUPPRESS=off). The trigger is the selector line of option 1,
      # which renders only once the select is mounted and raw mode is on; that also preserves the
      # 2026-07-11 fix, where a CR fired at the streaming header was swallowed and the menu hung.
      #
      # ANSWERED ONCE, EVER. Ink repaints the whole frame on every keypress, so without this latch
      # exp_continue would re-enter on the repaint and walk the selector down to option 3 —
      # the do-not-ask-again option — which is unrecoverable and account-wide.
      if {!$menu_answered} {
        set menu_answered 1
        sleep 1
        if {$asis} {
          answer_menu 1 $env(LR_RE_ASIS_STRONG) $env(LR_RE_ASIS) "resume full session as-is"
        } else {
          answer_menu 0 $env(LR_RE_MENU) $env(LR_RE_MENU) "resume from summary (--summary)" 1
        }
      }
      exp_continue
    }
    -re $env(LR_RE_TRUST) {
      sleep 1
      answer_menu 0 $env(LR_RE_TRUST_RB) $env(LR_RE_TRUST_RB) "folder trust"
      exp_continue
    }
    # informational overage NOTICE (Enter dismisses either way — safe). Opt-in upsells
    # (extra-usage/remote-control/passes) are declined at the SOURCE via lr-preseed-env.sh
    # raising their *SeenCount gates — never blindly answered here (Enter could enable them).
    -re $env(LR_RE_OVERAGE) { send "\r"; exp_continue }
    # fullscreen upsell: option 2 is "Not now" (options verified in the 2.1.220 bundle:
    # ["Yes, try it", "Not now"]). Previously this sent Down+CR BLIND, so a reordered menu would
    # have selected "Yes, try it" and restarted the session mid-recovery; now the selector is read
    # back first, and an unconfirmed selector parks instead of guessing.
    -re $env(LR_RE_FS) {
      sleep 1
      answer_menu 1 $env(LR_RE_FS_RB) $env(LR_RE_FS_RB) "fullscreen upsell (Not now)"
      exp_continue
    }
    -re $env(LR_RE_READY) {
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
