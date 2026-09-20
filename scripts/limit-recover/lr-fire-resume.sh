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
# (the SSOT frontier model @high — claude-fable-5-1 since 2026-09-03; this comment names the id
# only as of today, the code reads the SSOT). An absolute config-dir path is accepted as-is (Opus@max).
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
# --permission-mode: carried from the SOURCE session's argv (LIMIT_RECOVER_100P, 2026-09-09). This
# used to be hardcoded `auto` in the spawn below, so a `plan` session silently came back as `auto`
# — the same launch-vs-runtime confusion as the tier, one axis over. The default stays `auto`.
PERM_MODE="${LR_PERMISSION_MODE:-auto}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BR="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --permission-mode) PERM_MODE="$2"; shift 2 ;;
    --prompt) PROMPT="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --summary) SUMMARY=1; shift ;;
    --force-split) FORCE_SPLIT=1; shift ;;
    *) echo "lr-fire-resume: unknown arg $1" >&2; exit 2 ;;
  esac
done

# ══ THE RUN'S STATE, AND THE ONE FACT THE WATCHER CANNOT INFER (W2, 2026-09-19) ════════════════
# This script runs INSIDE the pane, in a shell the recycle watcher cannot reach. Every way it can
# fail before `expect` — a refused capacity gate, an unresolvable binary, a worktree that will not
# materialise — looks IDENTICAL from outside: no claude process ever appears. Measured 2026-09-19
# (U04 §3): the watcher polled that silence for 90 s, retyped the same command into the same
# refusal, and reported "no process appeared" with no cause. `relaunch.rc` is the positive
# discriminator — an rc on disk, in the run's own dir, written BEFORE the exit — so the watcher
# reads a fact in ~2 s (D1-FT R2 (a)).
#
# ABSENT RUN DIR ⇒ INERT, not fatal: this script is also run by hand, where there is no run.
_LRF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || _LRF_DIR=""
for _lrf_lib in "$_LRF_DIR/lr-lib.sh" \
                "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/limit-recover/lr-lib.sh" \
                "$HOME/.claude/scripts/limit-recover/lr-lib.sh"; do
  # shellcheck disable=SC1090  # runtime-resolved library ladder
  [ -f "$_lrf_lib" ] && { . "$_lrf_lib" 2>/dev/null || true; break; }
done
lr_state() { # $1=state $2=stage $3=detail — always rc 0; the writer itself is loud on failure
  [ -n "${LR_RUN_DIR:-}" ] || return 0
  if ! command -v lr_state_append >/dev/null 2>&1; then
    echo "!! lr-fire-resume: lr-lib.sh unreachable — state '$1' NOT recorded" >&2; return 0
  fi
  lr_state_append "$LR_RUN_DIR" "$1" "${2:-}" "${3:-}" || true
  return 0
}
lr_relaunch_rc() { # $1=rc $2=why — write ONCE; the first cause is the real one
  [ -n "${LR_RUN_DIR:-}" ] || return 0
  [ -f "$LR_RUN_DIR/relaunch.rc" ] && return 0
  lr_state FAILED "${3:-relaunch}" "rc=$1 — $2"
  mkdir -p "$LR_RUN_DIR" 2>/dev/null || { echo "!! lr-fire-resume: cannot write $LR_RUN_DIR/relaunch.rc — the watcher will have to infer this failure from silence" >&2; return 0; }
  printf '%s\n' "$1" > "$LR_RUN_DIR/relaunch.rc" 2>/dev/null \
    || echo "!! lr-fire-resume: cannot write $LR_RUN_DIR/relaunch.rc — the watcher will have to infer this failure from silence" >&2
  return 0
}
# EVERY pre-expect failure, not just the ones someone remembered. The trap is DISARMED immediately
# before expect runs (`trap - EXIT`), so nothing after the TUI starts can write an rc — a post-expect
# exit is the session ENDING, which is not a relaunch failure and must never be recorded as one.
_lrf_exit_trap() {
  local rc=$?
  [ "$rc" -ne 0 ] && lr_relaunch_rc "$rc" "lr-fire-resume exited before the TUI started"
  return 0
}
trap _lrf_exit_trap EXIT

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
  #
  # 🚨 THE ASSIGNMENT IS IN THE LOOP BODY, NOT THE LOOP VARIABLE, AND THAT IS THE WHOLE FIX.
  # bash 3.2.57 — /bin/bash on macOS, which is what runs this script — re-runs setlocale() on an
  # ORDINARY assignment to LC_ALL/LC_CTYPE but NOT on a for-loop binding. Measured under
  # `env -i PATH=… LC_ALL=C /bin/bash`, with ${#p} on a 2-char/4-byte string:
  #     local LC_ALL=en_US.UTF-8          → 2   (characters)
  #     local LC_ALL='' LC_CTYPE=en_US…   → 2   (characters)
  #     for LC_CTYPE in en_US.UTF-8; …    → 4   (BYTES — silently inert)
  # The first version of this fix used the loop-variable form and was inert in CI. It passed its own
  # verification because that ran `LC_ALL=C bats …`, which leaves LANG set — so `local LC_ALL=''`
  # fell through to the ambient en_CA.UTF-8 and the walk was correct for a reason the harness does
  # not provide. scripts/offbox-run.sh uses `env -i … LC_ALL=C` with NO LANG at all. Verify any
  # change to this block under that exact env, never under a bare LC_ALL=C.
  local LC_ALL='' LC_CTYPE cand probe
  for cand in C.UTF-8 en_US.UTF-8 UTF-8; do
    LC_CTYPE="$cand"
    probe='❯'
    [ "${#probe}" -eq 1 ] && break
  done
  # 🚨 THE SECOND LOCALE SEAM, AND IT IS NOT THE ONE ABOVE. The block above pins the locale that
  # BASH splits under. It cannot pin the locale that EXPECT decodes under, because expect is a
  # third program this script spawns and Tcl reads the ambient LC_ALL for itself — `encoding
  # system` is `utf-8` under a UTF-8 locale and `iso8859-1` under LC_ALL=C. That choice decides
  # whether the pattern bytes bash just emitted are ONE character or THREE, and a backslash in
  # front of them means opposite things in the two readings:
  #     utf-8      `\❯`  → ❯ is not alphanumeric ⇒ a literal-escape ⇒ COMPILES
  #     iso8859-1  `\â`  → â IS alphanumeric in Latin-1 ⇒ an unknown escape class ⇒ REFUSES with
  #                        "couldn't compile regular expression pattern: invalid escape \ sequence"
  # The refusal kills the expect program outright, so the arm never runs, the keylog stays EMPTY
  # and the script still exits 0 — it fails OPEN and SILENT. Measured 2026-09-20 under the exact
  # harness env (`env -i … LC_ALL=C`, scripts/offbox-run.sh): 8 of 11 in
  # tests/lr-resume-answer-width.bats, the same count and the same suite as the 2026-08-12 byte-
  # split, which is why it read as a relapse of a cure that is in fact still working.
  # THE CURE: a backslash goes in front of ASCII PUNCTUATION ONLY. Every Tcl ARE metacharacter is
  # ASCII, so nothing is lost; a non-ASCII character is always a literal and must be emitted bare,
  # which matches under either encoding because the pattern and the input decode the same way.
  # Membership is tested against a literal set rather than `[[:ascii:]]` or a range: a glob range
  # is collation-dependent and a class table is interpreter-dependent, and this file runs under
  # macOS /bin/bash 3.2.57. `${set#*"$ch"}` is plain POSIX expansion and needs neither.
  local ASCII_PUNCT=' !"#$%&'\''()*+,-./:;<=>?@[\]^_`{|}~'
  # ANSI CSI (colour, cursor-move) | any whitespace incl. the wrap newline | box rules.
  local SEP=$'(?:\033\\[[0-9;?]*[a-zA-Z]|[[:space:]]|│|┃|┆|╎)*'
  n=${#phrase}
  for (( i=0; i<n; i++ )); do
    ch="${phrase:$i:1}"
    [ "$ch" = " " ] && continue          # a wrapped space may be absent — never require it
    case "$ch" in
      [a-zA-Z0-9]) out+="$ch" ;;
      *)
        if [ "${ASCII_PUNCT#*"$ch"}" != "$ASCII_PUNCT" ]; then
          out+="\\$ch"                   # escape regex metacharacters: ( ) . - ' etc.
        else
          out+="$ch"                     # non-ASCII (❯, box rules): literal, never backslashed
        fi
        ;;
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
      [ "$CC_ACCT_IS_FABLE" = 1 ] && { model="claude-fable-5-1"; effort="high"; }
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
#
# ── ONE ADMISSION DECISION (LIMIT_RECOVER_100P W2, 2026-09-19) ─────────────────────────────────
# This gate is the SECOND evaluation of a net-zero operation the driver already evaluated, in a
# process the driver cannot parameterise — the split that produced four husks on 2026-09-19
# (U05 §3.3: probe ADMIT, launcher REFUSE 11-16 s later, transplant already done). The launcher
# now carries the driver's decision as a one-shot token, and the four variables below are set
# CALL-SCOPED — a `VAR=… cmd` prefix, never an `export` — because anything exported here rides
# into the recovered session's environment for its whole life and every hook it ever runs
# (D1-safety R1, FATAL). The `env -u` list on the spawn line is the second half of that rule.
#   CC_ADMIT_TOKEN      the driver's admission, redeemed once (absent/expired ⇒ a FRESH evaluation)
#   CC_ADMIT_WANT_SID   sid enforcement: a token minted for another session is refused, not replayed
#   CC_ADMIT_LOAD_TERM  the SAME switch the driver's probe used, so this is not a different gate
#   CC_ADMIT_BUDGET_KEY per-RUN refusal counter: one recovery's refusals cannot release another's
if [ -n "$_LR_CA" ]; then
  # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
  . "$_LR_CA"
  # LR_RUN is set only by the FLEET driver (lr-fleet.sh / lr-handoff.sh). This script's OTHER
  # documented entry point is a direct invocation — § Usage says "run it in the terminal/pane that
  # should own the resumed session" — and there LR_RUN is unset, so reading it bare under `set -u`
  # aborted the whole script at this line. Its three siblings on the same prefix were all guarded
  # (`${LR_ADMIT_TOKEN:-}`, `${LR_LOAD_TERM:-off}`), which is exactly what made the one unguarded
  # read invisible. The fallback is NOT empty: the budget key carries a per-run isolation invariant
  # ("one recovery's refusals cannot release another's"), and an empty key would pool every direct
  # invocation into ONE shared counter — so the direct path keys on its own sid instead.
  _lr_bkey="${LR_RUN:-}"; _lr_bkey="${_lr_bkey##*/}"; : "${_lr_bkey:=direct-$SID}"
  if ! CC_ADMIT_TOKEN="${LR_ADMIT_TOKEN:-}" CC_ADMIT_WANT_SID="$SID" \
       CC_ADMIT_LOAD_TERM="${LR_LOAD_TERM:-off}" CC_ADMIT_BUDGET_KEY="$_lr_bkey" \
       cc_capacity_admit lr-fire-resume "resume $SID on $ACCT"; then
    echo "✗ $(cc_capacity_admit_reason)" >&2
    echo "  Shed load first (close finished panes / let the wave drain), then re-run this exact command." >&2
    echo "  Override for one resume: CC_ADMIT_GATE=off ; raise the bar: CC_ADMIT_MAX_LOAD_PER_CORE=<n>" >&2
    # THE POSITIVE DISCRIMINATOR. The watcher outside this pane has no way to learn WHY no claude
    # appeared — it polled a corpse for 90 s and reported "no process appeared". `relaunch.rc` is
    # written BEFORE the exit, in the run's own dir, so the watcher reads a FACT (rc 9 = the gate
    # refused) in ~2 s instead of inferring one from silence (D1-FT R2 (a)).
    lr_relaunch_rc 9 "gate: $(cc_capacity_admit_reason)"
    exit 9
  fi
  echo "-- $(cc_capacity_admit_reason)" >&2
  lr_state 'gate-admitted' gate "$(cc_capacity_admit_reason)"
else
  echo "!! lr-fire-resume: capacity-admit: ABSENT (scripts/lib/capacity-admit.sh unreachable) — spawning UNGATED" >&2
  lr_state 'gate-absent' gate "capacity-admit.sh unreachable — spawning UNGATED"
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
# The mode-cycling hint was the third alternative and is DELETED (W3): measured 0 hits across CC
# 2.1.260's rendered status line, so it could only ever widen the pattern against a string the
# binary no longer paints. (Its literal spelling is deliberately not written here — the acceptance
# grep for this wave is a file-wide count, so a comment quoting the phrase would defeat it.)
# A ready signal that cannot fire is not a belt — it is the reason the
# 8 s QUIET arm below exists, because a READY phrase is version-coupled by construction and the
# pty going silent is not.
LR_RE_READY="$(lr_wrap_re 'for shortcuts')|$(lr_wrap_re 'auto mode on')"
export LR_RE_READY
export LR_ASIS="$(( SUMMARY == 0 ? 1 : 0 ))"
case "$PERM_MODE" in
  auto|default|plan|acceptEdits|bypassPermissions|dontAsk) ;;
  *) echo "lr-fire-resume: --permission-mode must be auto|default|plan|acceptEdits|bypassPermissions|dontAsk (got '$PERM_MODE')" >&2; exit 2 ;;
esac
export LR_CFG="$cfg" LR_BIN="$BIN" LR_MODEL="$model" LR_EFFORT="$effort" LR_SID="$SID" LR_PROMPT="$PROMPT" LR_PERM="$PERM_MODE"
# ── CLOSE-ATTRIBUTION WRAPPER ────────────────────────────────────────────────────────────────────
# A RESUMED SESSION USED TO DIE UNATTRIBUTABLY. Every other launch path interposes
# bin/cc-close-attrib (see ~/.zshrc's claude-next* launchers); the spawn below did not, so a session
# recovered here could produce no close-record however it died — and the crash watchdog's whole
# ladder is built on that record. Measured 2026-09-08: of 20 live leads, 15 were wrapped and 5 were
# not, and ALL FIVE unwrapped ones were spawns from this line. Meanwhile 151 of September's 151
# `abrupt-unknown` crashes carry no record at all
# (docs/research/death-attribution-coverage-2026-09-08.md).
#
# FAIL-OPEN, and that is why the spawn has two branches rather than an interpolated prefix. An
# unresolvable wrapper must cost the RECORD, never the RECOVERY — this is the limit-recovery path,
# and a session that does not come back is a strictly worse outcome than one that comes back
# unattributed. An empty prefix cannot be spliced into the existing spawn line either: expect would
# hand `env` an empty argument to exec. So LR_WRAP is empty ⇒ the original line runs unchanged.
LR_WRAP="$HOME/.claude/bin/cc-close-attrib"
[[ -x "$LR_WRAP" ]] || LR_WRAP=""
export LR_WRAP
# ── THE PANE MUST OUTLIVE THE SESSION IN IT ──────────────────────────────────────────────────────
# This used to be `exec expect`, which made expect(1) this pane's TERMINAL process: nothing under
# it, nothing after it. Every way a resumed CC can end — a crash, a usage limit, and above all the
# `/exit` that `handoff-fire.sh --recycle` types — therefore ended the PANE too, because kitty
# closes a window whose only child has exited, and lr-handoff hands this script to kitty in the
# pane's ROOT argv slot (`launch … -- /bin/bash "$LAUNCHER"`, lr-handoff.sh:690) including the
# `--type=os-window` fallback, where the window that dies is a whole OS window.
#
# bin/reso-resume-one — the file this one is a derivative of — took this cure in c67bda626 after
# pane 32 was destroyed by its own /exit on 2026-08-26. This script is the last member of that
# class to adopt it; docs/research/recycle-pane-survivability-2026-08-26.md states the rule for
# the fleet: *any* pane an agent may later be asked to recycle must end its command with a shell,
# and calls the survivability gate "a guard rather than a guarantee".
#
# 🚨 `lr_rc=0` + `|| lr_rc=$?` are LOAD-BEARING, and are the one place this differs from the
# sibling. reso-resume-one runs `set -uo pipefail`; THIS file runs `set -euo pipefail` (:23), so a
# bare `expect …` returning non-zero would abort the script under errexit and never reach the
# fall-through — the pane would still die on exactly the exits this change exists to survive.
# A command on the left of `||` is exempt from errexit, which is what makes the rc readable.
# ══ WHAT THE EXPECT PROGRAM CAN ASK THE WORLD (W3, 2026-09-19) ════════════════════════════════
# An expect(1) program has no shell functions and no library: everything it needs from this box it
# must `exec`. Rather than spell shell pipelines inline as Tcl strings — where every quote is a new
# way to corrupt the program — the three questions it asks are exported as WHOLE shell programs in
# environment variables, which Tcl passes to `bash -c` as ONE argv element and therefore cannot
# mangle. Same discipline as the LR_RE_* patterns above: composed in bash, consumed uninterpreted.
#
#   LR_PROBE      the submission probe (a FILE, not a program string) — the transcript oracle
#   LR_SCREEN_SH  the screen verdict — EMPTY | DRAFT | DRAFT-MINE | MENU | UNKNOWN
#   LR_NOTE_SH    one lr_state_append, for the states only the expect program can witness
#
# EVERY ONE OF THEM IS ALLOWED TO FAIL, AND EACH FAILURE HAS ITS OWN WORD. UNKNOWN is not EMPTY and
# an unreadable transcript is not "not submitted": the action that follows a false EMPTY is typing
# into a session whose screen was never read (memory predicate-refusal-is-not-a-negative).
LR_PROBE=""
for _lrf_probe in "$_LRF_DIR/lr-submit-probe.sh" \
                  "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/limit-recover/lr-submit-probe.sh" \
                  "$HOME/.claude/scripts/limit-recover/lr-submit-probe.sh"; do
  [ -x "$_lrf_probe" ] && { LR_PROBE="$_lrf_probe"; break; }
done
[ -n "$LR_PROBE" ] || echo "!! lr-fire-resume: lr-submit-probe.sh unreachable — SUBMISSION cannot be measured for this run" >&2
LR_LIB_PATH="${_lrf_lib:-}"
LR_IT2="$HOME/.claude/bin/it2"
[ -x "$LR_IT2" ] || LR_IT2=""
LR_PANE="${ITERM_SESSION_ID:-}"; LR_PANE="${LR_PANE##*:}"
# The needle the composer must contain for a re-Enter to be allowed: the head of the prompt, printable
# ASCII only and whitespace-stripped, because that is the exact shape the screen reader produces.
LR_SCREEN_WANT="$(printf '%s' "$PROMPT" | LC_ALL=C tr -cd '[:print:]' | LC_ALL=C tr -d '[:space:]' | cut -c1-40)"
LR_SCREEN_SH="$(cat <<'LRSCREENSH'
# EMPTY | DRAFT | DRAFT-MINE | MENU | UNKNOWN — the composer, read out of band from the pane itself.
# The box is found by its BORDER RUNS (a repeat of U+2500), never by a literal TUI phrase: a phrase
# dies at the wrap, a border run is width-invariant by construction. This is composer_content()'s
# parse (handoff-fire.sh), reproduced here because expect cannot call a bash function.
[ -n "${LR_IT2:-}" ] && [ -n "${LR_PANE:-}" ] || { printf UNKNOWN; exit 0; }
scr="$("$LR_IT2" session read -s "$LR_PANE" -n "${LR_SCREEN_LINES:-24}" 2>/dev/null)" || scr=""
[ -n "$scr" ] || { printf UNKNOWN; exit 0; }
# A SELECTOR LINE is `❯` followed by an ordinal — a parked menu. The composer box draws `❯` too, so
# "contains ❯" would call every healthy screen a menu; the ordinal is what identifies an option.
if LC_ALL=C grep -qE '❯[[:space:]]*[0-9]+\.' <<<"$scr"; then printf MENU; exit 0; fi
body="$(LC_ALL=C awk -v b='────────────' '
  { line[NR] = $0; if (index($0, b) > 0) { b2 = b1; b1 = NR } }
  END { if (b1 == 0 || b2 == 0 || b1 - b2 < 2) exit 9; for (i = b2 + 1; i < b1; i++) print line[i] }' <<<"$scr")" \
  || { printf UNKNOWN; exit 0; }
# [:print:] drops the newlines AND the box ink, so an empty composer reduces to the empty string.
body="$(printf '%s' "$body" | LC_ALL=C tr -cd '[:print:]')"
# The never-typed-in placeholder, matched as a WHOLE row: a real draft that merely starts with
# `Try "` must still read as a draft, because the cost of a loose match is typing over live text.
if LC_ALL=C grep -qE '^[[:space:]]*Try "[^"]*("|\.\.\.)[[:space:]]*$' <<<"$body"; then body=""; fi
body="$(printf '%s' "$body" | LC_ALL=C tr -d '[:space:]')"
[ -n "$body" ] || { printf EMPTY; exit 0; }
if [ -n "${LR_SCREEN_WANT:-}" ]; then
  case "$body" in *"$LR_SCREEN_WANT"*) printf DRAFT-MINE; exit 0 ;; esac
fi
printf DRAFT
LRSCREENSH
)"
LR_NOTE_SH="$(cat <<'LRNOTESH'
# ONE lr_state_append, from inside the expect program. Inert without a run dir (this script is also
# run by hand) and LOUD when the library is unreachable — a state log that drops lines silently is
# worse than none, because its silence reads as "nothing happened".
[ -n "${LR_RUN_DIR:-}" ] || exit 0
for _n_lib in "${LR_LIB_PATH:-}" \
              "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/limit-recover/lr-lib.sh" \
              "$HOME/.claude/scripts/limit-recover/lr-lib.sh"; do
  [ -n "$_n_lib" ] && [ -f "$_n_lib" ] && { . "$_n_lib" 2>/dev/null || true; break; }
done
command -v lr_state_append >/dev/null 2>&1 || {
  echo "!! lr-fire-resume: lr-lib.sh unreachable — state '${LR_ST_STATE:-}' NOT recorded" >&2; exit 0; }
lr_state_append "$LR_RUN_DIR" "${LR_ST_STATE:-}" "${LR_ST_STAGE:-}" "${LR_ST_DETAIL:-}" || true
LRNOTESH
)"
export LR_PROBE LR_LIB_PATH LR_IT2 LR_PANE LR_SCREEN_WANT LR_SCREEN_SH LR_NOTE_SH

lr_rc=0
# THE RELAUNCH-RC TRAP IS DISARMED HERE, and this line is the whole of its scope rule: everything
# above is "the launcher failed before the TUI existed" (a relaunch failure the watcher must see);
# everything below is the SESSION's own lifetime, whose end is not a relaunch failure and must never
# be recorded as one (W2).
trap - EXIT
lr_state relaunch-typed expect "spawning $model/$effort on $(basename "$cfg")"
# shellcheck disable=SC2016  # single quotes are REQUIRED: the body below is an expect(1) program,
#   and its $env(...)/$bin references must reach expect uninterpreted. Bash expansion here would
#   corrupt the script — the values are passed in via the LR_* environment exported above.
expect -c '
  set timeout 300
  set cfg    $env(LR_CFG)
  set bin    $env(LR_BIN)
  set model  $env(LR_MODEL)
  set effort $env(LR_EFFORT)
  set perm   [expr {[info exists env(LR_PERM)] ? $env(LR_PERM) : "auto"}]
  set sid    $env(LR_SID)
  set prompt $env(LR_PROMPT)
  set injected 0
  set asis $env(LR_ASIS)
  set menu_answered 0
  # THE QUIET BUDGET. `timeout` in expect means "no new output for N seconds", and a booting TUI
  # paints continuously — so silence is the positive fact that the frame has settled. 8 s replaces
  # the old 300 s `timeout {}`, which was not a wait but a silent give-up: a READY phrase the binary
  # had stopped painting meant the prompt was simply never typed and nothing anywhere said so.
  set quiet [expr {[info exists env(LR_QUIET_S)] ? $env(LR_QUIET_S) : 8}]
  # ── THE THREE QUESTIONS THIS PROGRAM ASKS THE WORLD ───────────────────────────────────────────
  # Each is one `exec` of a whole shell program handed over in the environment (see the LR_*_SH
  # block in the bash above). Every one of them may fail, and each failure has its own WORD —
  # never a fall-through to the answer that licenses typing.
  proc lr_note {state stage detail} {
    global env
    if {![info exists env(LR_NOTE_SH)]} { return }
    catch { exec env LR_ST_STATE=$state LR_ST_STAGE=$stage LR_ST_DETAIL=$detail \
                 /bin/bash -c $env(LR_NOTE_SH) }
  }
  proc lr_screen {} {
    global env
    if {![info exists env(LR_SCREEN_SH)]} { return UNKNOWN }
    set v ""
    catch { set v [string trim [exec /bin/bash -c $env(LR_SCREEN_SH)]] }
    if {$v eq ""} { return UNKNOWN }
    return $v
  }
  # submitted <ts> | queued <ts> | none | unreadable | skip — `unreadable` and `skip` are NOT `none`.
  proc lr_probe {t0} {
    global env
    if {![info exists env(LR_PROBE)] || $env(LR_PROBE) eq ""} { return {skip {}} }
    if {![info exists env(LR_SUBMIT_TOKEN)] || $env(LR_SUBMIT_TOKEN) eq ""} { return {skip {}} }
    set out ""
    if {[catch { set out [exec $env(LR_PROBE) $env(LR_CFG) $env(LR_SID) $t0 \
                               $env(LR_SUBMIT_TOKEN)] }]} { return {unreadable {}} }
    set w [split [string trim $out]]
    if {[llength $w] == 0} { return {unreadable {}} }
    if {[lindex $w 0] eq "none"} { return {none {}} }
    return [list [lindex $w 0] [lindex $w 1]]
  }
  # THE SUBMISSION BASELINE, captured BEFORE the spawn. Everything the probe accepts must be NEWER
  # than this instant, which is what keeps the identical prompt of a PREVIOUS attempt out of the answer.
  set t0 [clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S} -gmt 1]
  # A wrapped prompt spans far more bytes than expect buffers by default (2000): at 8 columns one
  # menu is several KB of text and cursor-move chrome. A width-invariant pattern that cannot fit in
  # the match buffer is not width-invariant at all.
  match_max 200000
  # THE SPAWN ENV IS A WHITELIST-BY-OVERRIDE, AND EVERYTHING ELSE LEAKS. This line names only the
  # two variables it means to SET, so every other variable of whoever invoked the script rides into
  # the recovered session. One of them is load-bearing: CLAUDE_CODE_CHILD_SESSION=1 is exported by
  # any Claude session, and it turns transcript saving OFF in the child — so a recovery fired from
  # an agent pane comes up, works, and writes NOTHING, which is the one outcome limit-recovery
  # exists to prevent. Measured 2026-09-05 on session 2de07510: two runs, and the transplanted
  # transcript stayed byte-identical at 3521401b across both (cc-backlog c6089dc2efe6). `-u` UNSETS
  # rather than blanking: an empty string is a value, and a consumer testing presence rather than
  # truthiness would still read it as set.
  #
  # The two branches differ ONLY by the cc-close-attrib prefix (see the LR_WRAP block in the bash
  # above for why an empty prefix cannot simply be interpolated). The wrapper execs the binary in
  # place, so the spawned pty, the process group and every pattern below are unchanged by it.
  set wrap $env(LR_WRAP)
  if {$wrap ne ""} {
    spawn -noecho env -u CLAUDE_CODE_CHILD_SESSION -u LR_RUN -u LR_RUN_DIR -u LR_ADMIT_TOKEN -u LR_SUBMIT_TOKEN -u LR_LOAD_TERM -u CC_ADMIT_TOKEN -u CC_ADMIT_WANT_SID -u CC_ADMIT_LOAD_TERM -u CC_ADMIT_BUDGET_KEY DISABLE_AUTOUPDATER=1 CLAUDE_CONFIG_DIR=$cfg $wrap $bin --permission-mode $perm --model $model --effort $effort --resume $sid
  } else {
    spawn -noecho env -u CLAUDE_CODE_CHILD_SESSION -u LR_RUN -u LR_RUN_DIR -u LR_ADMIT_TOKEN -u LR_SUBMIT_TOKEN -u LR_LOAD_TERM -u CC_ADMIT_TOKEN -u CC_ADMIT_WANT_SID -u CC_ADMIT_LOAD_TERM -u CC_ADMIT_BUDGET_KEY DISABLE_AUTOUPDATER=1 CLAUDE_CONFIG_DIR=$cfg $bin --permission-mode $perm --model $model --effort $effort --resume $sid
  }

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
  # THE MAIN LOOP RUNS ON THE QUIET BUDGET, not on 300 s. This one line is what makes the arm below
  # a WAIT rather than a give-up: at 300 s the timeout arm was unreachable in practice — lr-handoff
  # awaits the whole recycle inside 900 s and the watcher calls it dead at 180 s, so nothing ever
  # observed it fire. Each answer_menu arm restores it explicitly, because answer_menu leaves 300.
  set timeout $quiet
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
      # answer_menu leaves `timeout` at 300; re-entering the loop with it would restore the
      # silent 300 s give-up this wave deleted.
      set timeout $quiet
      exp_continue
    }
    -re $env(LR_RE_TRUST) {
      sleep 1
      answer_menu 0 $env(LR_RE_TRUST_RB) $env(LR_RE_TRUST_RB) "folder trust"
      # answer_menu leaves `timeout` at 300; re-entering the loop with it would restore the
      # silent 300 s give-up this wave deleted.
      set timeout $quiet
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
      # answer_menu leaves `timeout` at 300; re-entering the loop with it would restore the
      # silent 300 s give-up this wave deleted.
      set timeout $quiet
      exp_continue
    }
    -re $env(LR_RE_READY) {
      if {$prompt ne "" && !$injected} {
        set injected 1
        # 0.3/0.2/0.2, down from 2/1/1. The three sleeps exist to let the composer mount and to keep
        # the ^U, the text and the CR from coalescing into one paste the TUI reads as a single
        # keystroke — a settling delay, not a wait for a remote event. 4 s of the old budget was
        # pure latency on every recovery, and the submit poll below now measures the outcome
        # instead of guessing at it.
        sleep 0.3
        send "\025"
        sleep 0.2
        send -- $prompt
        sleep 0.2
        send "\r"
      }
    }
    timeout {
      # ── THE QUIET ARM: WHAT USED TO BE `timeout {}` ─────────────────────────────────────────
      # The pty has painted nothing for $quiet seconds, so the frame has settled and READY never
      # matched. That is the version-coupling failure, and it is the one this file cannot prevent:
      # the status-line wording belongs to the binary, not to us. The cure is to stop asking the SCREEN
      # for a phrase and ask it for a SHAPE — an empty composer box between two border runs.
      #
      # 🚨 NEVER A BLIND CR INTO A QUIET PTY. A parked menu is quiet too, and Enter on one takes the
      # highlighted default — which on the resume menu is "resume from summary" (spends usage,
      # loses the goal) and on the trust prompt is worse. So the ONLY screen that licenses typing is
      # one that affirmatively reads EMPTY; MENU, DRAFT and UNKNOWN all park and SAY SO. That is the
      # 2026-08-06 rule this repo already runs on: typing needs the affirmative (memory
      # probe-that-acts-on-absence-must-confirm-presence).
      if {$prompt ne "" && !$injected} {
        set sv [lr_screen]
        if {$sv eq "EMPTY"} {
          set injected 1
          lr_note READY-QUIET inject "READY never matched; composer reads EMPTY after ${quiet}s quiet — typing"
          send_user "\nlr-fire-resume: READY never matched, but the composer reads EMPTY after ${quiet}s of quiet — typing the prompt on that evidence.\n"
          sleep 0.3
          send "\025"
          sleep 0.2
          send -- $prompt
          sleep 0.2
          send "\r"
        } else {
          lr_note READY-NOT-SEEN inject "screen reads $sv after ${quiet}s quiet — prompt NOT typed"
          send_user "\n✗ READY NEVER SEEN — prompt NOT typed: the pty went quiet for ${quiet}s and the screen reads $sv, not an empty composer. NOTHING was sent, because Enter on a parked menu takes its default. Type the prompt by hand in this pane.\n"
        }
      }
    }
    eof { exit }
  }
  if {$injected} {
    # ══ SUBMISSION IS A RECORD IN THE TRANSCRIPT, NEVER A PHRASE ON THE SCREEN ══════════════════
    # WHAT THIS REPLACES. The old verifier waited for the TUI chrome that renders while a turn is
    # running, and re-sent CR up to five times until it appeared. It failed in both directions:
    #   · it is a SCREEN PHRASE, so it is width- and version-coupled exactly like the READY
    #     signal one block up — and when it stops rendering, the loop sends FIVE blind CRs;
    #   · it renders while ANY turn is running, so a harness notification turn satisfies it while
    #     the injected prompt is still sitting unsubmitted in the composer. That is the same
    #     defect the engagement oracle carries and the reason 1 in 5 RECOVERED verdicts was false.
    # The cure is the run TOKEN: lr-handoff puts it in the prompt text, so a user record carrying
    # it is proof that THIS prompt reached THIS session, and nothing else can forge it.
    #
    # THREE ANSWERS, THREE ACTIONS, AND `none` IS THE ONLY ONE THAT LICENSES A KEYSTROKE.
    #   submitted ⇒ done, and the ts is the engagement baseline the watcher will use.
    #   queued    ⇒ typed and accepted, behind a running turn: keep polling to the engage bound.
    #               A re-CR here would append a SECOND copy of the prompt to the queue.
    #   none      ⇒ nothing reached the transcript. ONE more Enter, and only after the screen
    #               affirmatively shows OUR prompt sitting in the composer (DRAFT-MINE) — that is
    #               the 2026-07-11 stranded-ingest case, a leading-/ prompt whose first CR the
    #               slash-command autocomplete swallowed as a menu-select.
    #   unreadable/skip ⇒ NOT MEASURED. Never a keystroke, and never a green word in the log.
    #
    # 🚨 NOTHING BELOW MAY `exit`. expect exiting closes the master pty, which kills the resumed
    # session — the husk this whole project exists to prevent. Every path falls through to
    # `interact`, including the failures.
    set poll [expr {[info exists env(LR_SUBMIT_POLL_S)] ? $env(LR_SUBMIT_POLL_S) : 30}]
    set qmax [expr {[info exists env(RCY_ENGAGE_TIMEOUT)] ? $env(RCY_ENGAGE_TIMEOUT) : 180}]
    if {$qmax < $poll} { set qmax $poll }
    set deadline $poll
    set verb skip
    set ts ""
    set recr 0
    for {set t 0} {$t < $deadline} {incr t} {
      set r [lr_probe $t0]
      set verb [lindex $r 0]
      set ts   [lindex $r 1]
      if {$verb eq "submitted"} { break }
      if {$verb eq "skip"} { break }
      if {$verb eq "queued" && $deadline < $qmax} { set deadline $qmax }
      if {$verb eq "none" && !$recr && $t >= [expr {$poll - 1}]} {
        set recr 1
        set sv [lr_screen]
        if {$sv eq "DRAFT-MINE"} {
          lr_note SUBMIT-RECR submit "prompt still in the composer after ${poll}s — one more CR"
          send_user "\nlr-fire-resume: the prompt is still sitting in the composer after ${poll}s (nothing in the transcript) — sending ONE more Enter.\n"
          send "\r"
          set deadline [expr {$t + 10}]
        } else {
          send_user "\nlr-fire-resume: nothing in the transcript after ${poll}s and the composer reads $sv, not our prompt — NOT re-sending Enter.\n"
          break
        }
      }
      sleep 1
    }
    if {$verb eq "submitted"} {
      lr_note submitted submit "user record carrying the run token at $ts"
      send_user "\nlr-fire-resume: SUBMITTED — the prompt is in the transcript at $ts.\n"
    } elseif {$verb eq "queued"} {
      lr_note queued submit "enqueued at $ts; still behind a running turn at the ${deadline}s bound"
      send_user "\nlr-fire-resume: QUEUED — the prompt was accepted at $ts and is waiting behind a running turn. It has NOT started yet.\n"
    } elseif {$verb eq "unreadable"} {
      lr_note INDETERMINATE:submit submit "the target transcript could not be read — submission NOT measured"
      send_user "\nlr-fire-resume: submission NOT MEASURED — the target transcript could not be read. This is not a failure and it is not a success; read the pane.\n"
    } elseif {$verb eq "skip"} {
      send_user "\nlr-fire-resume: submission not verified — this run carries no submit token (a by-hand run, or lr-submit-probe.sh is unreachable).\n"
    } else {
      lr_note FAILED:submit submit "no record of the prompt in the transcript within ${deadline}s"
      send_user "\n✗ NOT SUBMITTED — the prompt never reached the transcript within ${deadline}s. The session is alive and TASK-LESS. Type the prompt by hand in this pane.\n"
    }
    set timeout 300
  }
  interact
' || lr_rc=$?
# ── FALL THROUGH TO A SHELL, so the pane outlives the session (see the block above the expect) ────
# ONE caller must NOT get a shell, and it is identified by an AFFIRMATIVE fact rather than by the
# absence of one:
#   · stdin is not a tty — no controlling terminal, so there is no pane to keep alive and `zsh -i`
#     would sit reading EOF in a loop. This is the shape lr-handoff.sh:813 warns about by name
#     ("running it from a Bash TOOL call ... kills the resumed session the moment expect's interact
#     reads EOF on a non-tty stdin"), and the tests never reach here at all: they extract the expect
#     program and run it standalone (tests/lr-fire-resume-close-attrib.bats).
# The sibling's second guard (CC_RR_NO_INTERACT) has NO analogue here on purpose — that knob exists
# because reso-resume-one's expect program can skip `interact`; this one always interacts, so a tty
# on stdin is exactly the "this is a real pane" fact, and a real pane must survive.
# The exit code is preserved on the non-shell path so a caller that reads it still reads expect's.
if [ ! -t 0 ]; then
  exit "$lr_rc"
fi
printf '\n[lr-fire-resume] session ended (rc %s) — this pane is now an ordinary shell.\n' "$lr_rc" >&2
# `-l -i` is load-bearing, not cosmetic, for the reason bin/cc-pane-runner:69 records: ~/.zprofile
# puts ~/.claude/shims on PATH and ~/.zshrc synthesizes ITERM_SESSION_ID from KITTY_WINDOW_ID, so a
# non-login non-interactive shell yields a pane that is alive and UNADDRESSABLE — and the launcher
# names a recycle relaunches with are zsh FUNCTIONS defined only in the interactive rc.
exec "${SHELL:-/bin/zsh}" -l -i
