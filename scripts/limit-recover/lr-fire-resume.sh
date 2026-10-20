#!/bin/bash
# lr-fire-resume.sh — resume a (possibly transplanted) session on a given account,
# auto-answering the resume prompts, then optionally injecting one first prompt.
# Derivative of ~/.reso/bin/reso-resume-one, extended with prompt injection.
#
# Usage: lr-fire-resume.sh <account|cfg-dir> <worktree> <sid>
#          [--branch BR] [--model M] [--effort E] [--prompt "ONE-LINE"] [--repo PATH]
#          [--summary] [--force-split] [--no-prompt]
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
#   --no-prompt    Resume and type NOTHING once the session is ready: the pre-ready menus are
#                  still answered, then the composer is left alone and a READY / READY-QUIET note
#                  is recorded instead. Refused together with a non-empty --prompt.
#   --extra-args "TOKENS" / --extra-env "NAME=v ..."  identity a relaunch must carry (a teammate's
#                  --agent-id/--agent-name/--team-name/...; see the note after the arg loop).
#
# Exit codes before the TUI starts, each also written to $LR_RUN_DIR/relaunch.rc: 2 usage ·
# 9 the capacity gate refused and the run dir's owner retries · 75 the gate refused and the launch is
# QUEUED as one durable requests/<sid>.cc-lr.json (no run dir; REPORT lr-wake-2026-10-18 K3) ·
# 10 the launch lock is held · 11 a live holder of <sid> · 12 the member guard (a teammate its lead
# dropped or a same-id successor holds, or a team-blind resume of an Agent Teams member).
#
# Environment seams: LR_CLAUDE_BIN (a binary to run instead of cc-claude-bin's answer),
# LR_PRESEED_DONE (skip lr-preseed-env.sh), LR_RECR_SCHEDULE (re-send look offsets, default 5,15,30,45),
# LR_LAUNCH_GUARD=off (no launch lock, no holder re-check), CC_RESUME_TEAMMATE_GUARD=off|checked
# (skip the team-blind member test: the caller already read the closed argv), LR_TEAM_PS_SNAPSHOT.
set -euo pipefail

ACCT="${1:?account}"; WT="${2:?worktree}"; SID="${3:?session-id}"; shift 3
BR="" MODEL="" EFFORT="" PROMPT="" REPO="${LR_REPO:-$HOME/Development/reso-management-app}"
SUMMARY=0 FORCE_SPLIT=0 NO_PROMPT=0 EXTRA_ARGS="" EXTRA_ENV=""
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
    --no-prompt) NO_PROMPT=1; shift ;;
    --extra-args) EXTRA_ARGS="$2"; shift 2 ;;
    --extra-env) EXTRA_ENV="$2"; shift 2 ;;
    *) echo "lr-fire-resume: unknown arg $1" >&2; exit 2 ;;
  esac
done
# --no-prompt is a promise that NOTHING is typed after ready, so a prompt beside it is a contradiction
# the caller must resolve, never one this script silently picks a side of.
if [[ $NO_PROMPT -eq 1 && -n "$PROMPT" ]]; then
  echo "lr-fire-resume: --no-prompt and a non-empty --prompt are mutually exclusive" >&2; exit 2
fi
[[ $NO_PROMPT -eq 1 ]] && PROMPT=""
# --extra-args / --extra-env: identity that must survive the relaunch (cc-lr upgrade's team
# procedure, 2026-09-23). A TEAMMATE comes back only with its --agent-id/--agent-name/--team-name/...
# flags and CLAUDECODE=1 CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 (without the gate var the team flags
# are silently ignored); a LEAD comes back to its own team file only with
# CLAUDE_INTERNAL_ASSISTANT_TEAM_NAME=<team> (else it rewrites that file leader-only). Both are split
# on spaces inside expect, so every token is held to a strict charset — no quoting can hide in one.
set -f   # the unquoted expansions below split, and must never glob
for _lrf_tok in $EXTRA_ARGS; do
  case "$_lrf_tok" in *[!A-Za-z0-9_@=./:,+-]*|'') echo "lr-fire-resume: --extra-args token '$_lrf_tok' is outside [A-Za-z0-9_@=./:,+-]" >&2; exit 2 ;; esac
done
for _lrf_tok in $EXTRA_ENV; do
  case "$_lrf_tok" in [A-Za-z_]*=*) ;; *) echo "lr-fire-resume: --extra-env token '$_lrf_tok' is not NAME=value" >&2; exit 2 ;; esac
  case "$_lrf_tok" in *[!A-Za-z0-9_@=./:,+-]*) echo "lr-fire-resume: --extra-env token '$_lrf_tok' is outside [A-Za-z0-9_@=./:,+-]" >&2; exit 2 ;; esac
done
set +f

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
# lr-team.sh: the successor census the member guard asks (lr_agent_id_holders). Its own loop
# variable, because LR_LIB_PATH below is read off $_lrf_lib.
for _lrf_team in "$_LRF_DIR/lr-team.sh" \
                 "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/limit-recover/lr-team.sh" \
                 "$HOME/.claude/scripts/limit-recover/lr-team.sh"; do
  # shellcheck disable=SC1090  # runtime-resolved library ladder
  [ -f "$_lrf_team" ] && { . "$_lrf_team" 2>/dev/null || true; break; }
done
# >>> lr-say
# ── WHAT THE PANE SHOWS: ONE LINE PER EVENT (lr-wake 2026-10-18, RC8, Wave H2) ───────────────────
# A refusal husk spent 7 lines on one fact, and 14 of the 18 preflight lines on screen that night
# decided nothing (g-message-design §2.1-2.2). So the preflight speaks ONCE: a `--` note goes to the
# cc-say log only (lib/cc-say.sh; CC_SAY_VERBOSE=1 prints it), an anomaly is logged and remembered
# for the one line printed just before claude starts, and a refusal is one `✗`/`⏸` line carrying at
# most one command. The renderer is the checkout's sibling (through this file's symlink), else the
# live layer; with neither, a plain stand-in keeps the same one-line shape.
_lrf_real="$(readlink "${BASH_SOURCE[0]}" 2>/dev/null)" || _lrf_real=""
for _lrf_c in "${_LRF_DIR:+$_LRF_DIR/../../lib/cc-say.sh}" "${_lrf_real:+${_lrf_real%/*}/../../lib/cc-say.sh}" \
              "${HOME:-}/.claude/lib/cc-say.sh"; do
  # shellcheck disable=SC1090  # runtime-resolved library ladder
  [ -n "$_lrf_c" ] && [ -r "$_lrf_c" ] && { . "$_lrf_c" 2>/dev/null || true; break; }
done
if ! command -v cc_say >/dev/null 2>&1; then
  cc_say() {
    local g='─'
    case "$1" in ok) g='✓' ;; fail) g='✗' ;; warn) g='⚠' ;; wait) g='⏸' ;; run) g='⟳' ;; esac
    printf '%s %s%s%s\n' "$g" "$2" "${3:+ · $3}" "${4:+ · ▶ $4}" >&2
  }
  cc_say_detail() { :; }
fi
# Local, never exported: the expect spawn below passes this environment to claude, and a session
# whose hooks inherited CC_SAY_TOOL=lr-fire-resume would sign every line it logs as this script.
# The tail blocks below (lr-successor and after) are also run on their own by tests, so this block is
# fenced (`>>> lr-say`) for them to prepend, and reads nothing it does not guard.
# shellcheck disable=SC2034  # CC_SAY_TOOL / CC_SAY_SID are read by cc_say through bash's dynamic scope
_lrf_say()    { local CC_SAY_TOOL=lr-fire-resume CC_SAY_SID="${SID:-}"; cc_say "$@"; }
# shellcheck disable=SC2034  # as above
_lrf_detail() { local CC_SAY_TOOL=lr-fire-resume CC_SAY_SID="${SID:-}"; cc_say_detail "$@"; }
_LRF_ANOM="" _LRF_ANOM_N=0 _LRF_ANOM_P=0
# The launch line names ONE anomaly: the first, unless a later one switched a safety rail off (two
# live copies, no launch lock, no capacity gate) — that one takes the slot, the rest are counted.
_lrf_anom() { # $1=the anomaly in ≤4 words, for the launch line $2=the full sentence, for the log [$3=1 a rail is off]
  _LRF_ANOM_N=$(( _LRF_ANOM_N + 1 ))
  if [ -z "$_LRF_ANOM" ] || { [ "${3:-0}" = 1 ] && [ "$_LRF_ANOM_P" = 0 ]; }; then
    _LRF_ANOM="$1"; _LRF_ANOM_P="${3:-0}"
  fi
  _lrf_detail "⚠ $1" "${2:-}"
}
# <<< lr-say
lr_state() { # $1=state $2=stage $3=detail — always rc 0; the writer itself is loud on failure
  [ -n "${LR_RUN_DIR:-}" ] || return 0
  if ! command -v lr_state_append >/dev/null 2>&1; then
    _lrf_anom "run state not recorded" "lr-lib.sh unreachable — state '$1' NOT recorded"; return 0
  fi
  lr_state_append "$LR_RUN_DIR" "$1" "${2:-}" "${3:-}" || true
  return 0
}
lr_relaunch_rc() { # $1=rc $2=why — write ONCE; the first cause is the real one
  [ -n "${LR_RUN_DIR:-}" ] || return 0
  [ -f "$LR_RUN_DIR/relaunch.rc" ] && return 0
  lr_state FAILED "${3:-relaunch}" "rc=$1 — $2"
  mkdir -p "$LR_RUN_DIR" 2>/dev/null || { _lrf_anom "relaunch.rc not written" "cannot write $LR_RUN_DIR/relaunch.rc — the watcher will have to infer this failure from silence"; return 0; }
  printf '%s\n' "$1" > "$LR_RUN_DIR/relaunch.rc" 2>/dev/null \
    || _lrf_anom "relaunch.rc not written" "cannot write $LR_RUN_DIR/relaunch.rc — the watcher will have to infer this failure from silence"
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

# ── THE WORKTREE ARGUMENT IS A PATH, NOTHING ELSE (lr-wake 2026-10-18, e §2) ──────────────────────
# Overnight a rescue agent built a cwd with a sed that also matched a comment line, and `whose` plus
# a newline plus the path reached a launch line. Absolute, and free of control characters — but NOT
# required to exist: a missing tree is restored, unparked or re-added below, which is the job of
# that block, so a `-d` here would break exactly the resumes it exists for.
case "$WT" in
  /*) ;;
  *) echo "lr-fire-resume: worktree must be an absolute path (got '$WT')" >&2; exit 2 ;;
esac
case "$WT" in
  *[[:cntrl:]]*) echo "lr-fire-resume: worktree contains a control character: $(printf %q "$WT")" >&2; exit 2 ;;
esac

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
  _lrf_detail "tombstone check" "$_LR_TV"
else
  if [[ $FORCE_SPLIT -eq 1 ]]; then
    _lrf_anom "two live copies (--force-split)" \
      "--force-split — resuming a transplanted session ANYWAY: $_LR_TV · Two live copies of $SID now exist. Land from only ONE of them." 1
  else
    printf 'lr-fire-resume: %s\n' "$_LR_TV" >&2
    echo "  Resume it where it actually went, or if you deliberately want two live copies," >&2
    echo "  re-run this exact command with --force-split." >&2
    exit 3
  fi
fi

# >>> lr-launch-lock
# ── ONE LAUNCHER PER SESSION, AND NO LAUNCH OVER A LIVE HOLDER (W2c, plan Phase 0 contract) ───────
# Two launchers racing for one sid, or one launcher resuming a sid a live claude still holds, is the
# split brain the tombstone guard cannot see: nothing was transplanted, the session is simply open
# twice. Both locks below are a `mkdir` (atomic) plus a one-line JSON `holder`; a holder is STALE when
# its pid is dead or zombie, when that pid now names a different process (lstart moved), or when the
# holder is unreadable in a dir older than 60 s. lstart is always `TZ=UTC LC_ALL=C ps -o lstart=`
# with runs of spaces squeezed, the form the registry rows carry. LR_PS_BIN is the test seam.
_lrl_ps() { "${LR_PS_BIN:-/bin/ps}" "$@"; }
_lrl_lstart() { TZ=UTC LC_ALL=C _lrl_ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //;s/ $//'; }
_lrl_alive() { # $1=pid → 0 when a non-zombie process holds it
  local st
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  st="$(_lrl_ps -o stat= -p "$1" 2>/dev/null | tr -d ' ')" || st=""
  [ -n "$st" ] && [ "${st#Z}" = "$st" ]
}
_lrl_holder_write() { # $1=lock dir $2=role $3=pid — atomic (tmp + mv), never concatenated JSON
  local tmp="$1/holder.tmp.$$"
  jq -cn --arg r "${LR_RECORD_ID:-}" --arg a "${LR_ATTEMPT:-}" --arg role "$2" --argjson pid "$3" \
        --arg l "$(_lrl_lstart "$3")" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{record_id:$r,attempt:$a,role:$role,pid:$pid,lstart:$l,at:$at}' > "$tmp" 2>/dev/null \
    && mv -f "$tmp" "$1/holder"
}
_lrl_field() { jq -r --arg k "$2" '.[$k] // "" | tostring' "$1" 2>/dev/null || true; } # $1=file $2=key → "" when unreadable
_lrl_stale() { # $1=lock dir → 0 when its holder may be taken
  local h="$1/holder" pid lst now mt
  pid="$(_lrl_field "$h" pid)"
  if [ -z "$pid" ]; then
    mt="$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0)"; now="$(date +%s)"
    [ $((now - mt)) -gt 60 ]; return
  fi
  _lrl_alive "$pid" || return 0
  lst="$(_lrl_field "$h" lstart)"
  [ -n "$lst" ] && [ "$lst" != "$(_lrl_lstart "$pid")" ]
}
lr_git_lock() { # $1=lock dir — waits LR_GIT_LOCK_WAIT_S (30) polling 0.5 s; rc 1 on timeout
  local d="$1" tries=$(( ${LR_GIT_LOCK_WAIT_S:-30} * 2 ))
  mkdir -p "$(dirname "$d")" 2>/dev/null || true
  until mkdir "$d" 2>/dev/null; do
    if _lrl_stale "$d"; then
      _lrf_detail "stealing a stale git lock" "holder: $(cat "$d/holder" 2>/dev/null || echo none)"
      rm -rf "$d"
    else
      [ "$tries" -gt 0 ] || return 1
      sleep 0.5
    fi
    tries=$((tries - 1))
  done
  _lrl_holder_write "$d" lr-fire-resume-git "$$" || true
}
lr_sid_holders() { # $1=sid → one "pid P (source)" line per live holder of that session
  local sid="$1" f row c
  # A process that IS the session: `--resume <sid>` as a token pair, in a row that is not a shell
  # string merely mentioning it, not a wrapper whose child also matches, and not this script's line.
  _lrl_ps -axo pid=,ppid=,stat=,args= 2>/dev/null | awk -v sid="$sid" -v self="$$" '
    { pp[$1] = $2; a = $0; sub(/^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]+[^ \t]+[ \t]+/, "", a)
      n = split(a, w, /[ \t]+/); hit = 0
      for (i = 1; i < n; i++) if (w[i] == "--resume" && w[i + 1] == sid) hit = 1
      if (!hit || $3 ~ /^Z/) next
      b = w[1]; sub(/.*\//, "", b)
      if (b ~ /^(bash|sh|zsh|expect|env|grep|ps|awk|sed|python3)$/) next
      cand[$1] = $2 }
    END { x = self; while (x != "" && x + 0 > 1 && !(x in anc)) { anc[x] = 1; x = pp[x] }
          for (p in cand) par[cand[p]] = 1
          for (p in cand) if (!(p in anc) && !(p in par)) print "pid " p " (process: --resume " sid ")" }'
  # The registry row and the account session file, each read fail-open PER FILE: an unreadable row
  # is skipped, never allowed to refuse a launch on its own.
  for f in "${LR_REGISTRY_DIR:-$HOME/.claude/cc-registry}"/*.json; do
    [ -f "$f" ] || continue
    row="$(jq -r '[.session_id // "", (.pid // "" | tostring), .lstart // ""] | join("|")' "$f" 2>/dev/null)" || continue
    IFS='|' read -r _r_sid _r_pid _r_lst <<<"$row" || true
    [ "$_r_sid" = "$sid" ] && _lrl_alive "$_r_pid" || continue
    _r_lst="$(printf '%s' "$_r_lst" | tr -s ' ' | sed 's/^ //;s/ $//')"
    [ -z "$_r_lst" ] || [ "$_r_lst" = "$(_lrl_lstart "$_r_pid")" ] || continue
    echo "pid $_r_pid (registry: $f)"
  done
  for c in ${LR_CFG_DIRS:-$HOME/.claude $HOME/.claude-next $HOME/.claude-secondary $HOME/.claude-tertiary $HOME/.claude-quaternary}; do
    for f in "$c"/sessions/*.json; do
      [ -f "$f" ] || continue
      row="$(jq -r '[.sessionId // "", (.pid // "" | tostring)] | join("|")' "$f" 2>/dev/null)" || continue
      IFS='|' read -r _r_sid _r_pid <<<"$row" || true
      [ "$_r_sid" = "$sid" ] && _lrl_alive "$_r_pid" && echo "pid $_r_pid (sessions: $f)"
    done
  done
  return 0
}
lr_launch_guard() { # (a) take or re-take the launch lock, (b) refuse over any live holder of $SID
  local d h pid role rec hs
  if [ "${LR_LAUNCH_GUARD:-on}" = off ]; then
    _lrf_anom "LR_LAUNCH_GUARD=off" "LR_LAUNCH_GUARD=off — no launch lock and no holder re-check for $SID" 1
    return 0
  fi
  d="$LR_LOCK_DIR"; h="$d/holder"
  mkdir -p "$(dirname "$d")" 2>/dev/null || true
  if ! mkdir "$d" 2>/dev/null; then
    pid="$(_lrl_field "$h" pid)"; rec="$(_lrl_field "$h" record_id)"; role="$(_lrl_field "$h" role)"
    # OURS is this attempt of this record (a retry of the same attempt), or this very process.
    if { [ -n "$rec" ] && [ "$rec" = "${LR_RECORD_ID:-}" ] && [ "$(_lrl_field "$h" attempt)" = "${LR_ATTEMPT:-}" ]; } \
       || [ "$pid" = "$$" ] || _lrl_stale "$d"; then
      :
    else
      echo "REFUSED — launch lock held by pid $pid (role ${role:-?}, record ${rec:-none})" >&2
      lr_relaunch_rc 10 "launch-lock: held by pid $pid (role ${role:-?}, record ${rec:-none})"
      exit 10
    fi
  fi
  _lrl_holder_write "$d" lr-fire-resume "$$" || _lrf_anom "launch lock unstamped" "could not write $h"
  # One line per typer acquisition in the reconciler's launch.log — the §C7 double-typer audit
  # counts distinct typer pids per (sid, attempt). Best effort, and only where the dir exists.
  _lrl_log="${LR_RECON_ROOT:-${LR_STATE_DIR:-$HOME/.reso/limit-recover}/recon}"
  [ -d "$_lrl_log" ] && printf '%s\t%s\tlr-fire-resume\ttaken\tpid=%s\tattempt=%s\trecord=%s\n' \
    "$(date +%s)" "$SID" "$$" "${LR_ATTEMPT:-?}" "${LR_RECORD_ID:-}" >>"$_lrl_log/launch.log" 2>/dev/null
  hs="$(lr_sid_holders "$SID")"
  if [ -n "$hs" ]; then
    echo "REFUSED — $SID already has a live holder; resuming it again would open it twice:" >&2
    printf '%s\n' "$hs" | sed 's/^/  /' >&2
    lr_relaunch_rc 11 "holder: $(printf '%s' "$hs" | tr '\n' ';')"
    exit 11
  fi
}
# <<< lr-launch-lock

# ── THE MEMBER GUARD: AN AGENT TEAMS MEMBER BELONGS TO ITS LEAD (2026-10-16) ───────────────────────
# On 2026-10-16 a member approved its lead's shutdown_request and a relaunch path brought it back
# outside its team, where it idles forever (docs/research/teammate-resurrection-2026-10-16/REPORT.md
# § 4.2 step 8). Every in-place relaunch types THIS script (the watcher's re-type,
# --relaunch-at-shell, a hand run of launch.sh), so it is the one door where that is refused:
#   (a) a team relaunch (--agent-id in --extra-args) whose lead's team file no longer lists the
#       member, or whose --agent-id a live claude already carries (a successor);
#   (b) a resume with NO --agent-id of a session whose transcript head says it is a member, unless
#       the caller already read the closed argv (CC_RESUME_TEAMMATE_GUARD=checked) or opted out (off).
# rc 12 in both. Nothing it cannot read refuses: no jq, no library, or a predicate that could not run
# proceeds with a loud line, because the guard exists to stop a known member, not to strand a resume.
# The launch lock it runs under is left as rc 10/11 leave it: holder = this pid, stale once it exits.
lr_member_guard() {
  local tok prev="" id="" name="" team="" rc=0 n=""
  set -f   # EXTRA_ARGS is split on spaces here exactly as expect splits it, and must never glob
  for tok in $EXTRA_ARGS; do
    case "$prev" in
      --agent-id) id="$tok" ;;
      --agent-name) name="$tok" ;;
      --team-name) team="$tok" ;;
    esac
    case "$tok" in
      --agent-id=*) id="${tok#--agent-id=}" ;;
      --agent-name=*) name="${tok#--agent-name=}" ;;
      --team-name=*) team="${tok#--team-name=}" ;;
    esac
    prev="$tok"
  done
  set +f
  if [ -n "$id" ]; then
    # The id is <name>@<team>; explicit flags win, the id fills what they left out.
    [ -n "$name" ] || name="${id%%@*}"
    [ -n "$team" ] || team="${id#*@}"
    if ! command -v lr_member_row >/dev/null 2>&1 || ! command -v lr_agent_id_holders >/dev/null 2>&1; then
      _lrf_anom "member guard undecided" "member guard UNDECIDED for teammate $id — lr-lib.sh/lr-team.sh unreachable; relaunching it unchecked"
      return 0
    fi
    lr_member_row "$cfg" "$team" "$name" || rc=$?
    case "$rc" in
      0) ;;
      2) _lrf_anom "member row unread" "member row of teammate $id UNREAD (no jq) — relaunching it without the member-row check" ;;
      *)
        echo "REFUSED — teammate $id: no member row in ${cfg%/}/teams/$team/config.json; its lead dropped it, so relaunching it would resurrect a retired member" >&2
        lr_relaunch_rc 12 "teammate $id: no member row - its lead dropped it"
        exit 12
        ;;
    esac
    n="$(lr_agent_id_holders "$id" 2>/dev/null)" || n=""
    case "$n" in
      '' | *[!0-9]*) _lrf_anom "successor census unread" "successor census for teammate $id UNREAD — relaunching it unchecked" ;;
      0) ;;
      *)
        echo "REFUSED — teammate $id is superseded: $n live claude process(es) already carry --agent-id $id" >&2
        lr_relaunch_rc 12 "teammate $id: superseded - $n live holder(s) of its --agent-id"
        exit 12
        ;;
    esac
    return 0
  fi
  case "${CC_RESUME_TEAMMATE_GUARD:-}" in off | checked) return 0 ;; esac
  if ! command -v lr_team_member >/dev/null 2>&1; then
    _lrf_anom "team membership undecided" "team membership of $SID UNDECIDED — lr-lib.sh unreachable; resuming it unchecked"
    return 0
  fi
  lr_team_member "$SID" "$cfg" "$WT" >/dev/null || rc=$?
  case "$rc" in
    0)
      echo "REFUSED — team-blind resume of an Agent Teams member: $SID's transcript head names its team and this resume carries no --agent-id, so it would come back outside its team. A caller that read the closed argv and found no --agent-id sets CC_RESUME_TEAMMATE_GUARD=checked." >&2
      lr_relaunch_rc 12 "team-blind resume of an Agent Teams member"
      exit 12
      ;;
    2) _lrf_anom "team membership undecided" "team membership of $SID UNDECIDED (the teammate predicate could not run) — resuming it unchecked" ;;
  esac
  return 0
}

# ── A PARKED TREE IS UNPARKED, A REMOVED ONE RESTORED ONLY FOR ITS OWN SESSION (2026-10-17) ─────
# docs/research/load-root-cause-2026-10-17/DESIGN.md §3.5 item 4a, the same two steps as
# bin/reso-resume-one. A PARKED tree is moved back on a path match alone (lossless; pool slots are never
# parked); without it the add below fails, because the branch is checked out at the parked path. The
# unpark runs inside the per-repo git lock, since `git worktree move` writes .git/worktrees as an add
# does. A REMOVED tree is restored through cc-wt-restore ONLY when its tombstone names this sid, and only
# where the exit-2 refusal stood; a prompted unattended resume must never revive landed work. Every
# missing-cwd outcome is one resume-reaped row (X7 phase 1). A missing library keeps the behaviour from
# before this block exactly. CC_RESUME_TOMBSTONE_LIB, when set, is the only library looked at.
_lrf_s="${BASH_SOURCE[0]}"
while [ -L "$_lrf_s" ]; do
  _lrf_t="$(readlink "$_lrf_s" 2>/dev/null)" || break
  case "$_lrf_t" in /*) _lrf_s="$_lrf_t" ;; *) _lrf_s="$(dirname "$_lrf_s")/$_lrf_t" ;; esac
done
_lrf_sd="$(cd "$(dirname "$_lrf_s")" 2>/dev/null && pwd)" || _lrf_sd=""
_LRF_WTL=""
if [ -n "${CC_RESUME_TOMBSTONE_LIB+set}" ]; then
  [ -f "${CC_RESUME_TOMBSTONE_LIB}" ] && _LRF_WTL="${CC_RESUME_TOMBSTONE_LIB}"
else
  for _lrf_d in "${_lrf_sd:+$_lrf_sd/../lib/wt-tombstone.sh}" "$HOME/.claude/scripts/lib/wt-tombstone.sh"; do
    [ -n "$_lrf_d" ] && [ -f "$_lrf_d" ] && { _LRF_WTL="$_lrf_d"; break; }
  done
fi
if [ -n "$_LRF_WTL" ]; then
  # shellcheck disable=SC1090  # runtime-resolved library
  { . "$_LRF_WTL" 2>/dev/null && command -v wt_unpark >/dev/null 2>&1; } || _LRF_WTL=""
fi
_LRF_WTR=""
for _lrf_d in "${_lrf_sd:+$_lrf_sd/../../bin/cc-wt-restore}" "$HOME/.claude/bin/cc-wt-restore"; do
  [ -n "$_lrf_d" ] && [ -x "$_lrf_d" ] && { _LRF_WTR="$_lrf_d"; break; }
done
lr_reaped() { # $1=outcome → one resume-reaped row; never fails
  [ -z "$_LRF_WTL" ] || wt_resume_reaped lr-fire-resume "$WT" "$SID" "$1"
  return 0
}
lr_wt_glock() { # $1=repo → the per-repo git lock dir, keyed on the common dir as the add below keys it
  local gcd
  gcd="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  printf '%s\n' "${LR_STATE_DIR:-$HOME/.reso/limit-recover}/locks/git-$(printf '%s' "$gcd" | shasum | cut -c1-40)"
}
lr_restore_sid() { # → rc 0 iff a tombstone names $SID and cc-wt-restore brought $WT back
  local canon row repo gl="" rc=0
  [ -n "$_LRF_WTL" ] && [ -n "$_LRF_WTR" ] || return 1
  canon="$(cd "$(dirname "$WT")" 2>/dev/null && pwd -P)/$(basename "$WT")" || canon="$WT"
  row="$(wt_tomb_find "$canon" --sid "$SID" 2>/dev/null)" || row="$(wt_tomb_find "$WT" --sid "$SID" 2>/dev/null)" || return 1
  repo="$(printf '%s' "$row" | jq -r '.repo // empty' 2>/dev/null)" || repo=""
  if [ -n "$repo" ] && gl="$(lr_wt_glock "$repo")"; then
    lr_git_lock "$gl" || { echo "✗ lr-fire-resume: git lock $gl still held — $WT not restored" >&2; return 1; }
  else
    gl=""
  fi
  "$_LRF_WTR" "$WT" --sid "$SID" --yes >/dev/null || rc=$?
  [ -z "$gl" ] || rm -rf "$gl"
  [ "$rc" -eq 0 ] || return 1
  _lrf_detail "restored from its tombstone" "restored $WT from its tombstone (sid $SID matched), detached at the recorded head"
}
if [ -n "$_LRF_WTL" ] && _lrf_pk="$(wt_parked_lookup "$WT" 2>/dev/null)"; then
  _lrf_gl="$(lr_wt_glock "${_lrf_pk%%	*}")" || _lrf_gl=""
  if [ -z "$_lrf_gl" ] || ! lr_git_lock "$_lrf_gl"; then
    echo "✗ lr-fire-resume: $WT is parked, but the git lock for its repo (${_lrf_gl:-unresolvable}) was not taken — not unparked" >&2
    lr_reaped exit-1; exit 1
  fi
  _lrf_up=0; WT_ACTOR=lr-fire-resume wt_unpark "$WT" || _lrf_up=$?
  rm -rf "$_lrf_gl"
  case "$_lrf_up" in
    0) _lrf_detail "unparked" "unparked $WT — the parked tree is back at its own path"; lr_reaped unparked ;;
    2) echo "✗ lr-fire-resume: $WT is parked and could not be unparked (reason above)" >&2; lr_reaped exit-1; exit 1 ;;
  esac
fi

# Recreate a reaped worktree when a branch is known (reso-resume-one logic).
if [[ ! -d "$WT" ]]; then
  if [[ -n "$BR" ]] && git -C "$REPO" show-ref --verify --quiet "refs/heads/$BR"; then
    # NO PRUNE OF THE WORKTREE LIST HERE: it deletes the metadata of EVERY missing worktree, including a
    # sibling's that is missing only for a moment, and that sibling then cannot be re-added as itself.
    # The add is serialised on one lock per repository (keyed on the common dir), so two launchers
    # recreating two worktrees of one repo cannot race on .git/worktrees either.
    _lr_gcd="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)" || { lr_reaped exit-1; exit 1; }
    _lr_glock="${LR_STATE_DIR:-$HOME/.reso/limit-recover}/locks/git-$(printf '%s' "$_lr_gcd" | shasum | cut -c1-40)"
    if ! lr_git_lock "$_lr_glock"; then
      echo "✗ lr-fire-resume: git lock $_lr_glock still held after ${LR_GIT_LOCK_WAIT_S:-30}s (holder: $(cat "$_lr_glock/holder" 2>/dev/null || echo none))" >&2
      lr_reaped exit-2; exit 2
    fi
    _lr_wt_rc=0; _lr_wt_out="$(git -C "$REPO" worktree add "$WT" "$BR" 2>&1)" || _lr_wt_rc=$?
    [ -z "$_lr_wt_out" ] || printf '%s\n' "$_lr_wt_out" >&2
    # Without the prune, a worktree that is "missing but already registered" refuses the add. -f is
    # safe for exactly that case and no other: only when the branch is registered at $WT alone, since
    # -f would also let the branch be checked out twice.
    if [ "$_lr_wt_rc" -ne 0 ] && [[ "$_lr_wt_out" == *"missing but already registered worktree"* ]]; then
      _lr_wt_abs="$(cd "$(dirname "$WT")" 2>/dev/null && pwd -P)/$(basename "$WT")"
      _lr_wt_else="$(git -C "$REPO" worktree list --porcelain | awk -v br="refs/heads/$BR" -v a="$WT" -v b="$_lr_wt_abs" '
        /^worktree / { p = substr($0, 10) } $0 == "branch " br && p != a && p != b { print p }')"
      if [ -z "$_lr_wt_else" ]; then
        _lrf_detail "worktree re-added" "$WT is registered but missing — re-adding it with -f"
        _lr_wt_rc=0; git -C "$REPO" worktree add -f "$WT" "$BR" >&2 || _lr_wt_rc=$?
      else
        echo "✗ lr-fire-resume: $WT is registered but missing, and $BR is also checked out at: $_lr_wt_else — refusing -f" >&2
      fi
    fi
    rm -rf "$_lr_glock"
    [ "$_lr_wt_rc" -eq 0 ] || { lr_reaped exit-1; exit 1; }
    lr_reaped recreated-branch
  elif lr_restore_sid; then
    lr_reaped restored
  else
    echo "lr-fire-resume: worktree $WT missing and no --branch to recreate it" >&2; lr_reaped exit-2; exit 2
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
# LR_PRESEED_DONE: the caller already preseeded this account (the fleet does it once per account, the
# W5 rig has no account at all), so a second pass here would only re-write the same config.
if [[ -n "${LR_PRESEED_DONE:-}" ]]; then
  _lrf_detail "preseed skipped" "LR_PRESEED_DONE=$LR_PRESEED_DONE"
else
  "$_LR_DIR/lr-preseed-env.sh" "$cfg" "$WT" || true
fi

# Resolve the binary from the ONE SSOT (bin/cc-claude-bin), never a local constant. This used to
# hardcode ~/.claude-183, which by 2026-08-01 was wrong twice over: that directory had been advanced
# in place to 2.1.215 (name no longer matches content), and the interactive launcher had since moved
# to ~/.claude-219 — so a limit-recover resume relaunched a session on a DIFFERENT binary than the
# one it was recovering, and on a build with no claude-opus-5 at all. Fail CLOSED: a resume that
# cannot name its binary must not silently pick another one.
# LR_CLAUDE_BIN replaces that resolution outright (the W5 rig runs a stub TUI); it is held to the same
# fail-closed check, so a typo is the error below and never a fall-back to the real binary.
if [[ -n "${LR_CLAUDE_BIN:-}" ]]; then
  BIN="$LR_CLAUDE_BIN"
else
  BIN="$("$_LR_DIR/../../bin/cc-claude-bin" 2>/dev/null)" || BIN=""
fi
if [[ -z "$BIN" || ! -f "$BIN" || ! -x "$BIN" ]]; then
  echo "✗ lr-fire-resume: cannot resolve the claude binary (LR_CLAUDE_BIN='${LR_CLAUDE_BIN:-}', cc-claude-bin found none)." >&2
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
# ── A REFUSED LAUNCH WITH NO RUN DIR IS QUEUED ONCE (lr-wake 2026-10-18, REPORT §4 Wave C, K3) ─────
# requests/<sid>.cc-lr.json, the request lane lr-reset-poller.sh retries with backoff and admits on
# its own clock. Fields: sid, mode, cause, account, cwd, model, effort, prompt, first_refused_at
# (never rewritten), refusals. The poller owns next_at, cap_k and spawned_at; nothing here sets them.
# A re-refusal UPDATES the same file (refusals+1), so three re-runs still leave one request. Not
# carried: --summary, --permission-mode, --branch — a queued resume comes back with the defaults.
LR_REQ_STATE="${LR_STATE_DIR:-$HOME/.reso/limit-recover}"
LR_REQ_FILE="$LR_REQ_STATE/requests/$SID.cc-lr.json"
lr_refusal_knob() { # $1=the refusing term → the knob that moves that term's ceiling, or nothing
  case "${1:-}" in
    load)             printf CC_ADMIT_MAX_LOAD_PER_CORE ;;
    headroom)         printf CC_ADMIT_MIN_HEADROOM_GB ;;
    segments)         printf LR_SEGMENT_PCT ;;
    active)           printf CC_ADMIT_ACTIVE_CEILING ;;
    reserve-headroom) printf CC_ADMIT_RESERVE_GB ;;
    reserve-active)   printf CC_ADMIT_ACTIVE_RESERVE ;;
    reserve-slots)    printf CC_ADMIT_RESERVE_SLOTS ;;
  esac
  return 0
}
lr_queue_owner() { # → who else already owns this session's retry, or nothing; never fails
  local f pid
  [ -f "$LR_REQ_STATE/parked/$SID.json" ] && { printf 'a parked record'; return 0; }
  for f in "$LR_REQ_STATE/requests/$SID"*.json; do
    [ -f "$f" ] && [ "$f" != "$LR_REQ_FILE" ] && { printf 'a %s request' "${f##*/}"; return 0; }
  done
  # A run claim counts only while its holder is provably alive: a dead claim owns nothing, and the
  # poller files a request whose sid a live run holds as superseded anyway, so writing one is safe.
  f="$LR_REQ_STATE/runs/by-sid/$SID.active"
  if [ -d "$f" ] && command -v lr_claim_holder_pid >/dev/null 2>&1 \
     && pid="$(lr_claim_holder_pid "$f" 2>/dev/null)" \
     && [ "$(lr_claim_holder_state "$f" "$pid" 2>/dev/null)" = live ]; then
    printf 'a live run (pid %s)' "$pid"
  fi
  return 0
}
lr_queue_write() { # → rc 0 only when requests/<sid>.cc-lr.json holds this refusal, read back
  local tmp="$LR_REQ_FILE.tmp.$$"
  command -v jq >/dev/null 2>&1 || return 1
  mkdir -p "${LR_REQ_FILE%/*}" 2>/dev/null || return 1
  if [ -f "$LR_REQ_FILE" ]; then
    jq '.refusals = (((.refusals // 0) | tonumber? // 0) + 1)' "$LR_REQ_FILE" > "$tmp" 2>/dev/null \
      || { rm -f "$tmp"; return 1; }
  else
    jq -n --arg sid "$SID" --arg a "$ACCT" --arg cwd "$WT" --arg m "$model" --arg e "$effort" \
          --arg p "$PROMPT" --argjson t "$(date +%s)" \
      '{sid: $sid, mode: "recover", cause: "capacity", account: $a, cwd: $cwd,
        first_refused_at: $t, refusals: 1}
       + (if $m != "" then {model: $m} else {} end)
       + (if $e != "" then {effort: $e} else {} end)
       + (if $p != "" then {prompt: $p} else {} end)' > "$tmp" 2>/dev/null \
      || { rm -f "$tmp"; return 1; }
  fi
  mv -f "$tmp" "$LR_REQ_FILE" 2>/dev/null || { rm -f "$tmp"; return 1; }
  # A request the poller cannot parse owns nothing, and rc 75 lets the pane close.
  jq -e '.cause == "capacity" and (.refusals | type) == "number"' "$LR_REQ_FILE" >/dev/null 2>&1
}
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
#   CC_ADMIT_MAX_SEGMENT_PCT the swap ceiling the probe used (LR_SEGMENT_PCT; unset ⇒ the spawn 50)
#   CC_ADMIT_BUDGET_KEY per-RUN refusal counter: one recovery's refusals cannot release another's
# ── A SWAP RUNS NO IN-PANE GATE (design-swap-v3 I8 / F13, 2026-10-04) ───────────────────────────
# This gate runs AFTER the pane's old claude has exited. For a no-prompt account swap of an idle
# pane that is the one place a refusal does harm: the token lr-handoff minted is refused
# token-stale once it is past its 1,020 s TTL (a worker that waited for the pane to go idle can
# outlive it), the script exits 9, and the pane sits at a bare shell with nobody carrying the
# session. A swap is also net-zero here (one claude out, one in) and owes no turn. So the lane
# admits it before /exit (batch admission, then its slot) and the launcher says LR_ADMIT_MODE=swap.
# Only with --no-prompt: a prompted resume owes a turn and is gated as before. The mode is unset on
# the spawn line, so the resumed session never inherits it. Kill switch LR_ADMIT_SWAP=off.
if [ "${LR_ADMIT_MODE:-}" = swap ] && [ "${LR_ADMIT_SWAP:-on}" != off ] && [[ $NO_PROMPT -eq 1 ]]; then
  _lrf_detail "gate-exempt: swap" "a no-prompt account swap is admitted before /exit; nothing refuses after it"
  lr_state 'gate-exempt' gate "swap: no in-pane capacity gate for a no-prompt account swap of $SID on $ACCT"
elif [ -n "$_LR_CA" ]; then
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
  # A launch the queue already holds is judged on the QUEUE's clock (capacity-admit reads it as
  # CC_ADMIT_QUEUED_SINCE), so a poller spawn whose token could not be redeemed is not charged as a
  # fresh first refusal. Only without a run dir: a run-dir owner keeps its own budget.
  _lr_qs=""
  if [ -z "${LR_RUN_DIR:-}" ] && [ -f "$LR_REQ_FILE" ]; then
    _lr_qs="$(jq -r '.first_refused_at // empty' "$LR_REQ_FILE" 2>/dev/null)" || _lr_qs=""
  fi
  if ! CC_ADMIT_TOKEN="${LR_ADMIT_TOKEN:-}" CC_ADMIT_WANT_SID="$SID" \
       CC_ADMIT_LOAD_TERM="${LR_LOAD_TERM:-off}" CC_ADMIT_BUDGET_KEY="$_lr_bkey" \
       CC_ADMIT_MAX_SEGMENT_PCT="${LR_SEGMENT_PCT:-50}" CC_ADMIT_QUEUED_SINCE="$_lr_qs" \
       cc_capacity_admit lr-fire-resume "resume $SID on $ACCT"; then
    # ONE LINE, AND NO INVITATION TO RE-RUN (lr-wake 2026-10-18, RC2/RC8). This used to print the
    # reason plus "Shed load first …, then re-run this exact command" plus an override line that
    # always named CC_ADMIT_MAX_LOAD_PER_CORE, whatever term refused. Overnight an agent did re-run
    # it, 25 times, and every refusal left a plain shell. The full reason still reaches the IDL row
    # and, with a run dir, relaunch.rc; the pane gets the verdict and the term's numbers
    # (cc_capacity_admit_short: `box full 9/8`). The knob that moves THAT term's ceiling and the full
    # reason are detail (CC_SAY_VERBOSE=1 prints them; the pane-say log keeps them): a pane-width line
    # has room for the fact, and an override is not the operator's next move (Wave H2).
    _lr_term="$(cc_capacity_admit_refusal 2>/dev/null)" || _lr_term=""
    _lr_term="${_lr_term%% *}"; [ -n "$_lr_term" ] || _lr_term="${CC_ADMIT_REFUSED_TERM:-}"
    _lr_knob="$(lr_refusal_knob "$_lr_term")"
    _lr_fact="$(cc_capacity_admit_short 2>/dev/null)" || _lr_fact=""
    [ -n "$_lr_fact" ] || _lr_fact="box busy (${_lr_term:-capacity})"
    CC_SAY_DETAIL="${_lr_knob:+knob $_lr_knob · }$(cc_capacity_admit_reason)"
    if [ -n "${LR_RUN_DIR:-}" ]; then
      # rc 9: the run dir's owner retries (K3). THE POSITIVE DISCRIMINATOR: the watcher outside this
      # pane cannot learn WHY no claude appeared, so `relaunch.rc` is written BEFORE the exit and it
      # reads a fact in ~2 s instead of inferring one from silence (D1-FT R2 (a)). The owed marker
      # tells the pane runner a durable record owns the retry, so it may close this pane.
      _lrf_say wait "${SID:0:8} refused ($_lr_fact)" "its run retries"
      lr_relaunch_rc 9 "gate: $(cc_capacity_admit_reason)"
      [ -z "${CC_PANE_EXIT_OWED:-}" ] || : > "$CC_PANE_EXIT_OWED" 2>/dev/null || true
      exit 9
    fi
    # rc 75: no run dir, so nothing would retry this launch but a re-run. Queue it ONCE instead —
    # unless something already owns the retry — and exit 75, which the pane runner closes on.
    _lr_why=""
    if [ -n "$EXTRA_ARGS$EXTRA_ENV" ]; then
      _lr_why="a teammate identity cannot ride the queue"
    elif _lr_own="$(lr_queue_owner)" && [ -n "$_lr_own" ]; then
      CC_SAY_DETAIL="$CC_SAY_DETAIL · $_lr_own owns the retry" _lrf_say wait "${SID:0:8} already queued" "$_lr_fact"
      exit 75
    elif lr_queue_write; then
      _lrf_say wait "${SID:0:8} queued ($_lr_fact)" "the queue retries it"
      exit 75
    else
      _lr_why="the request could not be written"
    fi
    # NOTHING RETRIES THIS ONE, so the line carries the one command that does: `cc-lr recover` drives
    # lr-fleet --one under its own guards (it refuses a teammate, which only its lead re-spawns).
    # The term's numbers ride inside the verdict on every refusal line, because cc_say cuts and drops
    # a fact before it moves a command to its own row, and "not resumed" without why is half an answer.
    CC_SAY_DETAIL="$CC_SAY_DETAIL · not queued: $_lr_why"   # the knob stays first: a verbose row is cut from the right
    if [ -n "$EXTRA_ARGS$EXTRA_ENV" ]; then
      _lrf_say fail "${SID:0:8} not resumed ($_lr_fact)" "$_lr_why"
    else
      _lrf_say fail "${SID:0:8} not resumed ($_lr_fact)" "not queued" "cc-lr recover ${SID:0:8}"
    fi
    exit 9
  fi
  CC_SAY_DETAIL=""
  _lrf_detail "capacity admitted" "$(cc_capacity_admit_reason)"
  lr_state 'gate-admitted' gate "$(cc_capacity_admit_reason)"
else
  _lrf_anom "capacity gate absent" "capacity-admit: ABSENT (scripts/lib/capacity-admit.sh unreachable) — spawning UNGATED" 1
  lr_state 'gate-absent' gate "capacity-admit.sh unreachable — spawning UNGATED"
fi

# ── WHERE A RUN WITH NO RUN DIR WRITES ITS RECORD (lr-wake 2026-10-18, e §5 fix 6) ─────────────────
# A by-hand or rescue run has no LR_RUN_DIR, so its state notes and pane captures used to go nowhere:
# pane 430 left one log line and no screen, which is why nobody can say how its Enter was lost. Notes
# and captures fall back to a per-run dir here. LR_RUN_DIR itself stays unset — its presence is what
# decides rc 9 against rc 75 above and who reads relaunch.rc — so the fallback has its own name.
LR_NOTE_DIR="${LR_RUN_DIR:-${LR_STATE_DIR:-$HOME/.reso/limit-recover}/fire-resume/$SID/$(date -u +%Y%m%dT%H%M%SZ)-$$}"
mkdir -p "$LR_NOTE_DIR" 2>/dev/null || LR_NOTE_DIR=""
export LR_NOTE_DIR

# ── EVERY TYPED PROMPT CARRIES A TOKEN (lr-wake 2026-10-18, e §5 fix 4) ─────────────────────────────
# Without one the submit poll had nothing to look for, so it gave up before its first look: pane
# 430's run had no token, sent no second Enter, and logged only "submission not verified". A run the
# driver handed no token mints its own, in the form composer-intent.sh recognises as rail-token. It is
# never exported past the spawn: the spawn line unsets LR_SUBMIT_TOKEN.
if [ -z "${LR_SUBMIT_TOKEN:-}" ] && [ -n "$PROMPT" ]; then
  LR_SUBMIT_TOKEN="run:$(printf '%s' "$SID" | cut -c1-8):$(date -u +%Y%m%dT%H%M%SZ):$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
  case "$LR_SUBMIT_TOKEN" in
    run:????????:????????T??????Z:[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
      export LR_SUBMIT_TOKEN
      _lrf_detail "submit token minted" "no submit token from the driver — minted $LR_SUBMIT_TOKEN for this run" ;;
    *) LR_SUBMIT_TOKEN="" ;;
  esac
fi

# ── A LONG PROMPT IS NEVER TYPED (lr-wake 2026-10-18, RC5) ──────────────────────────────────────────
# Above Claude Code's paste threshold a typed prompt arrives as chips, never as text, so neither the
# composer read-back nor a human can see what is in the box: pane 430's 2,050-byte brief became
# `[Pasted text #1][Pasted text #2]re) -->` and sat unsubmitted for 8 h. Over LR_PROMPT_INLINE_MAX
# characters (800, counting the token suffix appended below) the whole prompt goes to a file in the
# run dir, newlines intact, and the typed text is one short pointer line that renders as text and
# starts with this rail's own marker.
LR_PROMPT_FILE=""
_lr_max="${LR_PROMPT_INLINE_MAX:-800}"; case "$_lr_max" in ''|*[!0-9]*) _lr_max=800 ;; esac
_lr_tok="${LR_SUBMIT_TOKEN:-}"; _lr_room=$(( _lr_max - ${#_lr_tok} - 18 ))
if [ -n "$PROMPT" ] && [ "${#PROMPT}" -gt "$_lr_room" ] && [ -n "$LR_NOTE_DIR" ]; then
  LR_PROMPT_FILE="$LR_NOTE_DIR/prompt.md"
  if printf '%s\n' "$PROMPT" > "$LR_PROMPT_FILE" 2>/dev/null; then
    lr_state 'prompt-file' inject "the ${#PROMPT}-character prompt is in $LR_PROMPT_FILE; a pointer line is typed"
    PROMPT="[limit-recover] Your relaunch prompt is ${#PROMPT} characters, so it is in a file: read $LR_PROMPT_FILE and follow it."
  else
    _lrf_anom "long prompt typed inline" "could not write $LR_PROMPT_FILE — typing the ${#PROMPT}-character prompt inline"
    LR_PROMPT_FILE=""
  fi
fi

# Single-line prompt only — the composer submits on CR; newlines are unsafe here. No ESC either: the
# prompt is sent inside a bracketed-paste frame, and an ESC[201~ in its text would end that frame early.
PROMPT=${PROMPT//$'\n'/ }
PROMPT=${PROMPT//$'\e'/}

# ── THE RUN TOKEN RIDES THE PROMPT, AND THIS IS THE ONLY PLACE THAT CAN GUARANTEE IT (W3p F1) ────
# The token's whole job is to be findable in the TARGET transcript, and it gets there iff it is in
# the TEXT THIS SCRIPT TYPES. Every path ends here — lr-handoff's fast prompt, its fail-closed
# fallback, and a by-hand `--prompt` with no launcher at all — so this is the chokepoint (memory
# enforcement-must-live-at-the-chokepoint), and putting the append anywhere upstream leaves it
# unverifiable: lr-handoff's launcher DECIDES its prompt at runtime in the pane, so the token's
# VALUE appears in that file exactly once (the export) on both of its prompt paths. That is what
# left this wave inert — handoff-fire's arming gate counted occurrences in the launcher, read
# `found 1 occurrence(s)`, and handed the watcher no token on every real recycle.
#
# IDEMPOTENT ON PURPOSE: a prompt that already carries the token is left alone, so an upstream
# append (lr-handoff's fail-closed path does one) composes with this instead of doubling it.
# APPENDED, never prefixed: the re-CR's DRAFT-MINE needle is the prompt's first 40 characters, and
# the composer's own echo is what it is compared against.
#
# LR_SUBMIT_TOKEN_IN_PROMPT is the CONTRACT IDENTIFIER handoff-fire.sh's arming gate greps for on
# the copy the launcher will actually exec. The launcher names a durable path, i.e. the LIVE layer,
# which may predate this change (memory launcher-runs-the-live-layer, and the same wire lr-handoff
# already asserts for LR_ADMIT_TOKEN at lr-handoff.sh:522) — arming a token a live lr-fire-resume
# will never type would convict every healthy recycle, which is the failure the gate exists for.
LR_SUBMIT_TOKEN_IN_PROMPT=0
if [ -n "${LR_SUBMIT_TOKEN:-}" ] && [ -n "$PROMPT" ]; then
  case "$PROMPT" in
    *"$LR_SUBMIT_TOKEN"*) LR_SUBMIT_TOKEN_IN_PROMPT=1 ;;
    *) PROMPT="$PROMPT (submit token: $LR_SUBMIT_TOKEN)"; LR_SUBMIT_TOKEN_IN_PROMPT=1 ;;
  esac
fi
if [ "$LR_SUBMIT_TOKEN_IN_PROMPT" = 1 ]; then
  lr_state 'submit-token-armed' inject "the typed prompt carries $LR_SUBMIT_TOKEN"
else
  # An anomaly only when a prompt is typed: a --no-prompt resume has nothing to prove submitted.
  if [ -n "$PROMPT" ]; then
    _lrf_anom "no submit proof" "no submit token in the typed prompt — submission cannot be proved from the transcript for this run"
  else
    _lrf_detail "no submit token" "no prompt is typed, so there is no submission to prove"
  fi
fi

# ── THE OWED PROMPT RIDES THE SPAWN ARGV, NOT THE KEYBOARD (gap 1, 2026-10-20) ──────────────────────
# `claude --resume <sid> "<prompt>"` submits the prompt itself once the session is up, with no typing
# (bin/reso-resume-one --prompt-file, piloted 2026-10-05 and in production since). Typing it waited
# for a painted composer under ONE 8 s wall-clock deadline: 15 of 78 prompted relaunches since 10-01
# ended READY-NOT-SEEN, 44% at 10/core or more, because boot time under load outlasts any fixed
# clock (docs/research/lr-sustained-load-2026-10-20/gap-1-post-relaunch-prompt-delivery.md §2).
# On argv the relay types NOTHING after the menus: it answers the pre-ready menus as before and then
# waits on the transcript probe alone. The note `prompt-argv` (after relaunch-typed) is what tells
# the reconciler's fallback C that this attempt's prompt is already in flight (settle.py).
# Two heads stay on the typed path: a leading `/` is parsed as a slash command out of an initial
# prompt (handoff-fire.sh check_slash_head), and a leading `-` would be read as an option.
# LR_PROMPT_ARGV=off is the kill switch back to typing.
_lr_argv_knob="${LR_PROMPT_ARGV:-on}"
LR_PROMPT_ARGV=0
if [ -n "$PROMPT" ]; then
  if [ "$_lr_argv_knob" = off ]; then
    _lrf_detail "prompt typed" "LR_PROMPT_ARGV=off — the prompt is typed after READY, not passed on argv"
  else
    case "$PROMPT" in
      /*|-*) _lrf_detail "prompt typed" "the prompt starts with '${PROMPT:0:1}', which the CLI would parse from argv — typing it instead" ;;
      *) LR_PROMPT_ARGV=1 ;;
    esac
  fi
fi
export LR_PROMPT_ARGV

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
  _lrf_detail "resume-summary prompt suppressed" "suppressed at the source — resuming FULL AS-IS"
elif [[ $SUMMARY -eq 1 ]]; then
  _lrf_anom "from a /compact summary" "--summary — resuming from a /compact SUMMARY (spends usage, loses fidelity and the /goal)"
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
export LR_EXTRA_ARGS="$EXTRA_ARGS" LR_EXTRA_ENV="$EXTRA_ENV"
export LR_NO_PROMPT="$NO_PROMPT"
# THE RE-SEND LOOK SCHEDULE: the seconds after the first CR at which a still-unsubmitted composer is
# read again (W0: a stranded prompt is visible within seconds, and the old first look at poll-1 left
# it sitting for ~29 s). Validated here because Tcl reads a leading-zero number as octal and an
# unordered list would look twice at one instant; anything invalid falls back to the default, loudly.
_lr_sched="${LR_RECR_SCHEDULE:-5,15,30,45}"; _lr_ok=1; _lr_prev=0
case "$_lr_sched" in *[!0-9,]*|,*|*,|*,,*) _lr_ok=0 ;; esac
if [ "$_lr_ok" = 1 ]; then
  for _lr_n in ${_lr_sched//,/ }; do
    case "$_lr_n" in 0*) _lr_ok=0; break ;; esac
    [ "$_lr_n" -gt "$_lr_prev" ] || { _lr_ok=0; break; }
    _lr_prev="$_lr_n"
  done
fi
if [ "$_lr_ok" = 0 ]; then
  _lrf_anom "bad LR_RECR_SCHEDULE" "LR_RECR_SCHEDULE='$_lr_sched' is not a list of strictly ascending positive integers — using 5,15,30,45"
  _lr_sched="5,15,30,45"
fi
export LR_RECR_SCHEDULE="$_lr_sched"
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
[ -n "$LR_PROBE" ] || _lrf_anom "no submit probe" "lr-submit-probe.sh unreachable — SUBMISSION cannot be measured for this run"
LR_LIB_PATH="${_lrf_lib:-}"
LR_IT2="$HOME/.claude/bin/it2"
[ -x "$LR_IT2" ] || LR_IT2=""
# CC_PANE_ID FIRST, ITERM_SESSION_ID only as the fallback — the order lr-fleet.sh:758 already
# uses and tests/cc-pane.bats ratchets. A STALE ITERM_SESSION_ID can sit beside a live
# CC_PANE_ID after a transplant, and this file runs INSIDE a transplanted pane, which is
# exactly the population that inverts. The `##*:` strip is safe for either spelling.
LR_PANE="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; LR_PANE="${LR_PANE##*:}"
# The needle the composer must contain for a re-Enter to be allowed: the head of the prompt, filtered
# and whitespace-stripped exactly as the screen reader below filters the box (D6.8: non-ASCII is
# content, only ❯, U+00A0 and control bytes are dropped), and cut on CHARACTERS, never bytes.
_lrf_ink() { LC_ALL=C perl -0777 -pe 's/\xE2\x9D\xAF|\xC2\xA0//g; tr/\x00-\x1F\x7F//d' | LC_ALL=C tr -d '[:space:]'; }
LR_SCREEN_WANT="$(printf '%s' "$PROMPT" | _lrf_ink | perl -CS -0777 -ne 'print substr($_, 0, 40)')"
# …AND THE RUN'S NONCE, for the composer that shows no head at all (2026-09-27, pane 751). Claude Code
# collapses a long paste into a `[Pasted text #1]` chip, so the 40-char head above is never on screen
# and a pristine paste read DRAFT: no re-Enter, and the session sat TASK-LESS for hours. The submit
# token's final field is 8 random hex minted for THIS run, so seeing it in the composer is proof the
# text is ours, whatever form the head took.
LR_SCREEN_NONCE=""
[ "$LR_SUBMIT_TOKEN_IN_PROMPT" = 1 ] && LR_SCREEN_NONCE="${LR_SUBMIT_TOKEN##*:}"
# The reconciler mints `lrr-` + 12 hex (lr_recon/act.py) with no `:` in it, so the strip above leaves
# the whole token, which is random for THIS run in the same way and is kept whole.
case "$LR_SCREEN_NONCE" in
  [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
  lrr-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
  *) LR_SCREEN_NONCE="" ;;
esac
# …AND A CHIP WITH ONLY A FRAGMENT OF OUR TAIL AFTER IT (pane 815, the same morning). The typed
# prompt is collapsed into the chip and only the last few keystrokes land as text after it — `2bd7`,
# half the nonce — so the whole-nonce needle above misses too. The tail of OUR prompt is random
# (it ends in the nonce), so a fragment of it after a chip is ours; a fragment must be ≥2 characters.
LR_SCREEN_TAIL="$(printf '%s' "$PROMPT" | _lrf_ink | perl -CS -0777 -ne 'print length($_) > 48 ? substr($_, -48) : $_')"
# …AND A LONE CHIP WITH NOTHING AFTER IT (4fe9935f, 2026-10-13). A one-line prompt over Claude Code's
# paste threshold arrives as ONE chip and the composer shows `[Pasted text #N]` and nothing else, so
# none of the three needles above has anything to match: the run read DRAFT, the +5 s re-CR was
# withheld, and the session sat with its relaunch prompt unsubmitted. The `#N` is NOT a count of
# lost pastes: 2.1.293 mints text and image chips from ONE counter floored past every id in the
# resumed transcript, and that transcript held `[Image #1]`, so the first paste of the process was
# #2. A lone chip is therefore the WHOLE prompt, never its tail. It counts as ours when its line
# count is our prompt's newline count, \r\n|\r|\n each counted once — handoff-fire.sh
# paste_readback_ok's placeholder rule, which keeps the number pinned so a different paste reads
# DRAFT. Unset (by-hand runs, no prompt) disables it.
LR_SCREEN_NL=""
if [ -n "$PROMPT" ]; then
  _lrf_s="${PROMPT//$'\r\n'/$'\n'}"; _lrf_s="${_lrf_s//$'\r'/$'\n'}"; _lrf_s="${_lrf_s//[!$'\n']/}"
  LR_SCREEN_NL="${#_lrf_s}"
fi
IFS='' read -r -d '' LR_SCREEN_SH <<'LRSCREENSH' || true
# EMPTY | DRAFT | DRAFT-MINE | MENU | UNKNOWN — the composer, read out of band from the pane itself.
# The box is found by its BORDER RUNS (a repeat of U+2500), never by a literal TUI phrase: a phrase
# dies at the wrap, a border run is width-invariant by construction. This is composer_content()'s
# parse (handoff-fire.sh), reproduced here because expect cannot call a bash function.
[ -n "${LR_IT2:-}" ] && [ -n "${LR_PANE:-}" ] || { printf UNKNOWN; exit 0; }
# DIM IS NOT CONTENT (lr-wake 2026-10-18 RC5; the rule cc-tui.sh cc_tui_composer_rows runs on). Claude
# Code paints its prompt suggestion faint (SGR 2) inside the box, and real input is never faint: read
# without the rendering, a suggestion looked like a DRAFT. So the pane is read WITH its rendering, the
# box is found on an escape-stripped copy, and its rows come from a copy with every faint run dropped.
# Both copies keep one output line per input line, so they index alike. A reader that refuses --ansi
# (an older it2, a stub) falls back to the plain read, where the two copies are the same text.
lr_rd() { "$LR_IT2" session read -s "$LR_PANE" -n "$1" --ansi 2>/dev/null || "$LR_IT2" session read -s "$LR_PANE" -n "$1" 2>/dev/null; }
lr_plain() { LC_ALL=C perl -pe 's/\e\[[0-?]*[ -\/]*[@-~]|\e\][^\a\e]*(?:\a|\e\\)?|\e.//g'; }
lr_nodim() {
  LC_ALL=C perl -ne '
    chomp; my ($d, $o) = (0, "");
    while (/\G(?:\e\[([0-9;:]*)m|\e\[[0-?]*[ -\/]*[@-~]|\e\][^\a\e]*(?:\a|\e\\)?|\e.|([^\e]))/gcs) {
      if (defined $1) {
        my @p = split /;/, $1, -1; @p = ("") unless @p;
        for (my $i = 0; $i < @p; $i++) {
          my ($c) = split /:/, $p[$i], 2; $c = "" unless defined $c;
          if ($c eq "" || $c eq "0" || $c eq "22") { $d = 0 }
          elsif ($c eq "2") { $d = 1 }
          elsif ($c =~ /^[345]8$/ && $p[$i] !~ /:/) {
            my $m = defined $p[$i + 1] ? $p[$i + 1] : "";
            $i += $m eq "5" ? 2 : $m eq "2" ? 4 : 0;
          }
        }
      } elsif (defined $2) { $o .= $2 unless $d }
    }
    print "$o\n";'
}
# DRAFT-MINE, and when the caller asks (LR_SCREEN_RECORD=1, at an unsubmitted verdict) the box is also
# recorded as this pane's residue, so the next verified rail clears it as rail-residue
# (composer-intent.sh) instead of holding on it as a draft for good.
mine() {
  if [ "${LR_SCREEN_RECORD:-0}" = 1 ] && [ -n "${body:-}" ]; then
    rd="${CC_COMPOSER_RESIDUE_DIR:-$HOME/.claude/logs/composer-residue}"
    mkdir -p "$rd" 2>/dev/null \
      && printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$body" > "$rd/${LR_PANE//\//_}" 2>/dev/null
  fi
  printf DRAFT-MINE; exit 0
}
raw="$(lr_rd "${LR_SCREEN_LINES:-24}")" || raw=""
[ -n "$raw" ] || { printf UNKNOWN; exit 0; }
scr="$(printf '%s\n' "$raw" | lr_plain)"
LR_NODIM="$(printf '%s\n' "$raw" | lr_nodim)"; export LR_NODIM
# A SELECTOR LINE is `❯` followed by an ordinal — a parked menu. The composer box draws `❯` too, so
# "contains ❯" would call every healthy screen a menu; the ordinal is what identifies an option.
if LC_ALL=C grep -qE '❯[[:space:]]*[0-9]+\.' <<<"$scr"; then printf MENU; exit 0; fi
# THE SLASH-COMMAND MENU IS NOT A DIALOG WHEN IT NAMES THE BOX'S OWN COMMAND (2026-10-11). A typed
# `/exit` opens the suggestion menu above the box and its highlighted row is `  ❯ /exit  Exit the CLI`,
# a ❯ at indent 1-4, so this read UNKNOWN on every such screen (slot-reader-sweep.md: the real
# 2.1.293 capture and all five widths). Only a highlight naming the command the box itself holds is
# exempt: with the menu open a CR submits the HIGHLIGHT, so any other one stays UNKNOWN. The rule is
# handoff-fire.sh composer_content's (0e882c9ac); tests/composer-parser-parity.bats pins both.
body="$(LC_ALL=C awk -v b='────────────' -v u='─' -v g='❯' -v nb=$'\302\240' '
  function slashcmd(s,   t) {
    t = s; sub(/^ +/, "", t)
    if (index(t, g) != 1) return ""
    t = substr(t, length(g) + 1)
    while (substr(t, 1, 1) == " " || index(t, nb) == 1) t = substr(t, (substr(t, 1, 1) == " ") ? 2 : length(nb) + 1)
    if (substr(t, 1, 1) != "/") return ""
    sub(/[ \t\r].*$/, "", t); return t
  }
  function selector(s,   t, n) {
    t = s; sub(/^ +/, "", t); n = length(s) - length(t)
    if (!(n >= 1 && n <= 4 && index(t, g) == 1)) return 0
    return !(cmd != "" && slashcmd(s) == cmd)
  }
  { line[NR] = $0; if (index($0, b) > 0) { b2 = b1; b1 = NR; gb = 0 } else if (index($0, g) > 0) gb = 1 }
  END { if (gb) exit 9
        if (b1 > 0 && b2 == 0) { print NR - b1; exit 8 }
        if (b1 == 0 || b2 == 0 || b1 - b2 < 2) exit 9
        if (index(line[b2], u) != 1) exit 9
        cmd = (index(line[b2 + 1], g) == 1) ? slashcmd(line[b2 + 1]) : ""
        for (i = 1; i < b2; i++) if (selector(line[i])) exit 9
        n = split(ENVIRON["LR_NODIM"], nd, "\n")
        for (i = b2 + 1; i < b1; i++) print ((i <= n) ? nd[i] : line[i]) }' <<<"$scr")" \
  && rc=0 || rc=$?
# A TALL COMPOSER (goal-arm-readback, 2026-10-10): a long prompt wrapped in a narrow pane puts the
# TOP border above the 24-row window, and a healthy composer read UNKNOWN. Only in that shape (a
# bottom border, no top) is a bigger window read, and its box counts only when shaped like a
# composer: same bottom row; top rule at column 0; first row the prompt glyph; every later row
# blank or two-space indented; no prompt glyph under it (a dialog draws its selector with one);
# no dialog option row (❯ at indent 1-4) above it. A first row that is a continuation is a box
# Claude Code capped and scrolled; it can only ever match the tail of OUR text (DRAFT-MINE needs
# the head or the nonce, so in practice it reads DRAFT). The last three checks, and the top rule at
# column 0, guard the 24-row read too. Anything else stays UNKNOWN. The same rule lives in handoff-fire.sh composer_content
# (docs/research/goal-arm-readback-2026-10-10/REPORT.md).
if [ "$rc" = 8 ] && [ "${LR_SCREEN_LINES_MAX:-200}" -gt "${LR_SCREEN_LINES:-24}" ] 2>/dev/null; then
  off="$body"
  raw="$(lr_rd "${LR_SCREEN_LINES_MAX:-200}")" || raw=""
  scr="$(printf '%s\n' "$raw" | lr_plain)"
  LR_NODIM="$(printf '%s\n' "$raw" | lr_nodim)"; export LR_NODIM
  body="$(LC_ALL=C awk -v b='────────────' -v u='─' -v g='❯' -v off="$off" '
    function border(s) { return index(s, b) > 0 }
    function selector(s,   t, n) { t = s; sub(/^ +/, "", t); n = length(s) - length(t); return (n >= 1 && n <= 4 && index(t, g) == 1) }
    { line[NR] = $0 }
    END {
      bot = NR - off
      if (bot < 2 || !border(line[bot])) exit 9
      for (top = bot - 1; top > 0 && !border(line[top]); top--) ;
      if (top < 1 || bot - top < 2 || index(line[top], u) != 1) exit 9
      if (index(line[top + 1], g) != 1 && (substr(line[top + 1], 1, 2) != "  " || line[top + 1] ~ /^[ \t\r]*$/)) exit 9
      for (i = top + 2; i < bot; i++)
        if (line[i] !~ /^[ \t\r]*$/ && substr(line[i], 1, 2) != "  ") exit 9
      for (i = bot + 1; i <= NR; i++)
        if (index(line[i], g) > 0) exit 9
      for (i = 1; i < top; i++) if (selector(line[i])) exit 9
      n = split(ENVIRON["LR_NODIM"], nd, "\n")
      for (i = top + 1; i < bot; i++) print ((i <= n) ? nd[i] : line[i])
    }' <<<"$scr")" && rc=0 || rc=$?
fi
[ "$rc" = 0 ] || { printf UNKNOWN; exit 0; }
# The box ink (❯, U+00A0) and the control bytes go; every other character is content (D6.8), so an
# empty composer reduces to the empty string and a non-ASCII draft does not.
body="$(printf '%s' "$body" | LC_ALL=C perl -0777 -pe 's/\xE2\x9D\xAF|\xC2\xA0//g; tr/\x00-\x1F\x7F//d')"
# The never-typed-in placeholder, matched as a WHOLE row: a real draft that merely starts with
# `Try "` must still read as a draft, because the cost of a loose match is typing over live text.
if LC_ALL=C grep -qE '^[[:space:]]*Try "[^"]*("|\.\.\.)[[:space:]]*$' <<<"$body"; then body=""; fi
body="$(printf '%s' "$body" | LC_ALL=C tr -d '[:space:]')"
[ -n "$body" ] || { printf EMPTY; exit 0; }
if [ -n "${LR_SCREEN_WANT:-}" ]; then
  case "$body" in *"$LR_SCREEN_WANT"*) mine ;; esac
fi
if [ -n "${LR_SCREEN_NONCE:-}" ]; then
  case "$body" in *"$LR_SCREEN_NONCE"*) mine ;; esac
fi
# EVERY LEADING CHIP GOES, NOT THE FIRST (lr-wake 2026-10-18, pane 430: `[Pasted text #1][Pasted
# text #2]re) -->`). Stripping through the first `]` left the second chip in the "tail", so our own
# box read DRAFT and earned no Enter. The prefix must be chips and nothing else; any other text before
# the tail leaves `rest` equal to the box, which matches no tail fragment.
case "$body" in
  "[Pastedtext#"*"]"?*)
    rest="$(printf '%s' "$body" | LC_ALL=C sed -E 's/^(\[Pastedtext#[0-9]+(\+[0-9]+lines)?\])+//')"
    if [ -n "${LR_SCREEN_TAIL:-}" ] && [ "$rest" != "$body" ] && [ "${#rest}" -ge 2 ]; then
      case "$LR_SCREEN_TAIL" in *"$rest"*) mine ;; esac
    fi ;;
esac
# A lone chip whose line count is our prompt's (see LR_SCREEN_NL): the whole box, anchored.
case "${LR_SCREEN_NL:-}" in
  ''|*[!0-9]*) ;;
  0) LC_ALL=C grep -qE '^\[Pastedtext#[0-9]+\]$' <<<"$body" && mine ;;
  *) LC_ALL=C grep -qE "^\[Pastedtext#[0-9]+[+]${LR_SCREEN_NL}lines\]\$" <<<"$body" && mine ;;
esac
printf DRAFT
LRSCREENSH
IFS='' read -r -d '' LR_NOTE_SH <<'LRNOTESH' || true
# ONE lr_state_append, from inside the expect program. A by-hand run writes to its fallback dir
# (LR_NOTE_DIR), inert only when neither exists, and LOUD when the library is unreachable — a state
# log that drops lines silently is worse than none, because its silence reads as "nothing happened".
_n_dir="${LR_RUN_DIR:-${LR_NOTE_DIR:-}}"
[ -n "$_n_dir" ] || exit 0
for _n_lib in "${LR_LIB_PATH:-}" \
              "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/limit-recover/lr-lib.sh" \
              "$HOME/.claude/scripts/limit-recover/lr-lib.sh"; do
  [ -n "$_n_lib" ] && [ -f "$_n_lib" ] && { . "$_n_lib" 2>/dev/null || true; break; }
done
command -v lr_state_append >/dev/null 2>&1 || {
  echo "!! lr-fire-resume: lr-lib.sh unreachable — state '${LR_ST_STATE:-}' NOT recorded" >&2; exit 0; }
lr_state_append "$_n_dir" "${LR_ST_STATE:-}" "${LR_ST_STAGE:-}" "${LR_ST_DETAIL:-}" || true
LRNOTESH
# ONE pane capture into the run bundle, for the moments whose cause no log can rebuild later: the CR
# sent unconfirmed, the re-CR withheld, NOT SUBMITTED (4fe9935f, 2026-10-13 — the CR was lost and
# nothing on disk could say what the composer held when it was sent). Prints the file it wrote, and
# writes a NO CAPTURE file rather than nothing when the pane cannot be read, so a missing screen is
# never mistaken for a capture nobody asked for.
IFS='' read -r -d '' LR_CAPTURE_SH <<'LRCAPTURESH' || true
d="${LR_RUN_DIR:-${LR_NOTE_DIR:-}}"
[ -n "$d" ] && [ -d "$d" ] || exit 0
tag="$(printf '%s' "${LR_CAP_TAG:-capture}" | LC_ALL=C tr -c 'A-Za-z0-9_-' '-')"
out="$d/screen-$tag-$(date -u +%Y%m%dT%H%M%SZ).txt"
if [ -z "${LR_IT2:-}" ] || [ -z "${LR_PANE:-}" ]; then
  printf 'NO CAPTURE: no pane reader (LR_IT2=%s LR_PANE=%s)\n' "${LR_IT2:-}" "${LR_PANE:-}" > "$out" || exit 0
else
  { printf '# %s · pane %s · %s · last %s rows\n' "${LR_CAP_TAG:-capture}" "$LR_PANE" \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${LR_CAPTURE_LINES:-60}"
    "$LR_IT2" session read -s "$LR_PANE" -n "${LR_CAPTURE_LINES:-60}" 2>&1 || printf 'NO CAPTURE: the pane read failed (rc %s)\n' "$?"
  } > "$out" || exit 0
fi
printf '%s' "$out"
LRCAPTURESH
# The launch-lock holder handover (see lr_launch_guard): once expect has spawned claude, the lock is
# held by THAT pid, so a later launcher finds a live holder while it runs and a stale one once it is
# gone. Nothing ever releases it; empty when the guard is off, which makes the expect side a no-op.
LR_LOCK_DIR="${LR_LAUNCH_LOCK:-${LR_STATE_DIR:-$HOME/.reso/limit-recover}/locks/$SID.launch}"
IFS='' read -r -d '' LR_LOCK_SH <<'LRLOCKSH' || true
d="${LR_LOCK_DIR:-}"; p="${LR_LOCK_PID:-}"
[ -n "$d" ] && [ -d "$d" ] || exit 0
case "$p" in ''|*[!0-9]*) exit 0 ;; esac
l="$(TZ=UTC LC_ALL=C "${LR_PS_BIN:-/bin/ps}" -o lstart= -p "$p" 2>/dev/null | tr -s ' ' | sed 's/^ //;s/ $//')"
jq -cn --arg r "${LR_RECORD_ID:-}" --arg a "${LR_ATTEMPT:-}" --argjson pid "$p" --arg l "$l" \
      --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{record_id:$r,attempt:$a,role:"claude",pid:$pid,lstart:$l,at:$at}' > "$d/holder.tmp.$$" \
  && mv -f "$d/holder.tmp.$$" "$d/holder"
LRLOCKSH
[ "${LR_LAUNCH_GUARD:-on}" = off ] && LR_LOCK_SH=""
export LR_PROBE LR_LIB_PATH LR_IT2 LR_PANE LR_SCREEN_WANT LR_SCREEN_NONCE LR_SCREEN_TAIL LR_SCREEN_SH LR_NOTE_SH
export LR_SCREEN_NL LR_CAPTURE_SH
export LR_LOCK_DIR LR_LOCK_SH
# ══ NOTHING WRITES TO THE PANE TTY ONCE THE TUI OWNS IT (2026-09-28) ═════════════════════════════
# The expect program used to report every step with send_user, i.e. raw bytes on the very tty
# Claude Code was painting. Those lines landed inside the composer box, wrapped mid-word, and
# survived the next redraw (three panes relaunched by cc-lr upgrade that evening; cc-tui.bats models
# the torn frame they leave). Status now goes to LR_SAY_LOG, beside the run state when there is a
# run dir and under the limit-recover state dir when this is a by-hand run. A verdict that needs a
# human also goes to the session inbox through cc-notify, which surfaces as context at the next
# boundary and never as keystrokes. The stderr lines ABOVE this point stay: before the spawn this
# pane is an ordinary shell.
if [ -n "${LR_RUN_DIR:-}" ]; then
  LR_SAY_LOG="$LR_RUN_DIR/lr-fire-resume.log"
else
  LR_SAY_LOG="${LR_STATE_DIR:-$HOME/.reso/limit-recover}/fire-resume/$SID.log"
fi
mkdir -p "$(dirname "$LR_SAY_LOG")" 2>/dev/null || true
LR_NOTIFY="${LR_NOTIFY_BIN:-$HOME/.claude/bin/cc-notify}"
[ -x "$LR_NOTIFY" ] || LR_NOTIFY=""
export LR_SAY_LOG LR_NOTIFY

# A refusal here is a launcher failure before the TUI exists, so it runs before the trap is disarmed
# and before relaunch-typed; still as late as possible, so the holder census is fresh (rc 10 / 11).
lr_launch_guard
lr_member_guard
lr_rc=0
# THE RELAUNCH-RC TRAP IS DISARMED HERE, and this line is the whole of its scope rule: everything
# above is "the launcher failed before the TUI existed" (a relaunch failure the watcher must see);
# everything below is the SESSION's own lifetime, whose end is not a relaunch failure and must never
# be recorded as one (W2).
trap - EXIT
# The pane runner's started marker (K3): from here on claude starts, so a later non-zero exit is the
# session ending, never a launch that did not happen. Unset when no runner launched this pane.
[ -z "${CC_PANE_STARTED_FILE:-}" ] || : > "$CC_PANE_STARTED_FILE" 2>/dev/null || true
# The expect program turns echo OFF before interact; every exit path it can take must not hand the
# fall-through shell a terminal that no longer echoes, so the original state is restored here too.
lr_tty_saved=""
[ -t 0 ] && lr_tty_saved="$(stty -g 2>/dev/null)"
# THE ONE PREFLIGHT LINE (Wave H2): everything above was detail, so the pane says what it decided —
# amber, naming the first anomaly, when any check degraded; gray when every check passed.
if [ -n "$_LRF_ANOM" ]; then
  _lrf_n=""; [ "$_LRF_ANOM_N" -gt 1 ] && _lrf_n=" +$(( _LRF_ANOM_N - 1 ))"
  _lrf_say warn "resuming ${SID:0:8} on ${ACCT##*/}" "$_LRF_ANOM$_lrf_n"
else
  _lrf_say run "resuming ${SID:0:8} on ${ACCT##*/}" "checks ok"
fi
lr_state relaunch-typed expect "spawning $model/$effort on $(basename "$cfg")"
# AFTER relaunch-typed: settle.launcher_settled reads only what follows this attempt's last start.
if [ "$LR_PROMPT_ARGV" = 1 ]; then
  lr_state prompt-argv inject "the ${#PROMPT}-character prompt rides the spawn argv; nothing is typed"
fi
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
  # ARGV DELIVERY (gap 1): the prompt is the last spawn argument and this program types nothing
  # after the menus. aprompt is a LIST so an absent prompt passes NO argument (an empty positional
  # would be submitted as an empty prompt), and one element keeps the text a single argument.
  set argvp [expr {[info exists env(LR_PROMPT_ARGV)] && $env(LR_PROMPT_ARGV) eq "1" && $prompt ne ""}]
  set aprompt [list]
  if {$argvp} { lappend aprompt $prompt }
  set injected 0
  # With no prompt to type (--no-prompt), readiness is still a fact worth recording: the W3 phase
  # oracle derives MOVED from these notes. Latched, so one run writes at most one.
  set ready_noted 0
  set asis $env(LR_ASIS)
  set menu_answered 0
  # >>> lr-tty-quiet  (byte-identical in lr-fire-resume.sh AND bin/reso-resume-one; tests/lr-fire-resume-reply-drain.bats diffs it)
  # NO ECHO BEFORE interact (2026-09-24, pane 405; 2026-10-16 in reso-resume-one). Until interact
  # the pane tty stays cooked with ECHO on, so the terminal replies to the TUI boot queries
  # (XTVERSION, kitty keyboard flags, DA1) were painted across the composer row as
  # ^[P>|kitty(0.48.2)^[\^[[?5u^[[?62;52;c, junk that also breaks any read of the screen. The call
  # site before the drain restores THIS original state, and the bash caller restores it on any exit.
  set lr_tty_orig ""
  if {[catch {exec /bin/stty -g <@ stdin 2>/dev/null} lr_tty_orig]} {
    set lr_tty_orig ""
  } else {
    catch {exec /bin/stty -echo <@ stdin 2>/dev/null}
  }
  # <<< lr-tty-quiet
  # THE LOOK INTERVAL, NOT A QUIET WINDOW (corrected 2026-10-20, gap 1 §0). In Expect 5.45 the
  # `timeout` of an expect command counts WALL CLOCK from the start of that command, and output that
  # matches no pattern does NOT reset it; only exp_continue does (measured: a child printing every
  # 1 s against `set timeout 3` timed out at 3040 ms). So this is how often the timeout arm below
  # looks at the screen, never proof that the frame has settled.
  set quiet [expr {[info exists env(LR_QUIET_S)] ? $env(LR_QUIET_S) : 8}]
  # THE WAIT BOUND: how long, from the spawn, the timeout arm keeps re-arming while the TUI has not
  # mounted a composer. One look at 8 s lost 15 of 78 prompted relaunches since 10-01 to boots of
  # 12-112 s under load. Wall clock and bounded, so a recovery is still attempted whatever the load.
  set readywait [expr {[info exists env(LR_READY_WAIT_S)] ? $env(LR_READY_WAIT_S) : 180}]
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
  # THE STATUS CHANNEL IS A FILE, NEVER THE PANE (2026-09-28). The pane tty belongs to the TUI from
  # the spawn on, and bytes written to it by this program paint over the composer. lr_say appends
  # one line to LR_SAY_LOG. lr_tell does that AND mails the session inbox, for the verdicts a human
  # must act on. cc-notify runs in the background with every stream on /dev/null, because a Tcl exec
  # in the background otherwise inherits this program stdout, which is the pane.
  proc lr_say {msg} {
    global env
    if {![info exists env(LR_SAY_LOG)] || $env(LR_SAY_LOG) eq ""} { return }
    catch {
      set fh [open $env(LR_SAY_LOG) a]
      puts $fh "[clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%SZ} -gmt 1] $msg"
      close $fh
    }
  }
  proc lr_tell {msg} {
    global env
    lr_say $msg
    if {![info exists env(LR_NOTIFY)] || $env(LR_NOTIFY) eq ""} { return }
    catch { exec $env(LR_NOTIFY) --from lr-fire-resume $env(LR_SID) "lr-fire-resume: $msg" < /dev/null >& /dev/null & }
  }
  # WAIT BY READING, NEVER BY SLEEPING, once the prompt is typed (2026-09-24, pane 405). A bare
  # sleep reads nothing from the spawn, the pty buffer fills and claude BLOCKS on its own output:
  # the resumed transcript went silent for 246 s, exactly the length of the submit poll. This relays
  # what the session paints (log_user is on) for about $secs seconds, then returns. Only the waits
  # AFTER the prompt is typed use it: before that, the READY and menu matchers read the buffer.
  proc lr_pump {secs} {
    set end [expr {[clock seconds] + $secs}]
    while {[clock seconds] < $end} {
      set timeout 1
      if {[catch {expect { -re {.+} {} timeout {} eof { return } }}]} {
        sleep 1
        return
      }
    }
  }
  # record 1 also files a DRAFT-MINE box as this pane residue (LR_SCREEN_SH says why).
  proc lr_screen {{record 0}} {
    global env
    if {![info exists env(LR_SCREEN_SH)]} { return UNKNOWN }
    set v ""
    catch { set v [string trim [exec env LR_SCREEN_RECORD=$record /bin/bash -c $env(LR_SCREEN_SH)]] }
    if {$v eq ""} { return UNKNOWN }
    return $v
  }
  # The pane as it is NOW, saved into the bundle (LR_CAPTURE_SH). Returns the file, or a phrase
  # saying none was written, for the note that cites it.
  proc lr_capture {tag} {
    global env
    if {![info exists env(LR_CAPTURE_SH)]} { return "no capture" }
    set p ""
    catch { set p [string trim [exec env LR_CAP_TAG=$tag /bin/bash -c $env(LR_CAPTURE_SH)]] }
    if {$p eq ""} { return "no capture" }
    return $p
  }
  # THE CR IS SENT ONLY ONCE THE COMPOSER HAS AFFIRMATIVELY PAINTED OUR TEXT (2026-09-22).
  # The three settle sleeps around the inject were cut from 2/1/1 to 0.3/0.2/0.2 in ba5e3c1e1, whose
  # own comment names the hazard they exist for: keeping the text and the CR from coalescing into
  # one paste the TUI reads as a single keystroke. At 0.2s into a TUI still loading ~94KB of
  # instructions, its SessionStart hooks and 6 MCP servers, they coalesced — and a trailing CR
  # inside a paste is a literal NEWLINE, not a submit. The signature is on the pane: an empty Claude
  # Code composer renders exactly ONE body row, and both stranded panes rendered the wrapped prompt
  # PLUS a trailing blank row, which is the CR sitting in the composer as text.
  #
  # A FIXED SLEEP CANNOT FIX THIS, because the quantity it must outlast is the TUI event loop under
  # a boot it does not control. So wait for the EVIDENCE instead: poll the composer until it reads
  # DRAFT-MINE, which is proof the TUI consumed our text as its own event and that a CR after it is
  # a separate keystroke. The bound falls through to the pre-2026-09-22 behaviour, so a screen
  # oracle that cannot read the pane can never make this worse than it already was.
  #
  # MENU IS THE ONE ANSWER THAT FORBIDS THE KEYSTROKE, keeping the rule the rest of this file runs
  # on: Enter on a parked menu takes its highlighted default (memory
  # probe-that-acts-on-absence-must-confirm-presence).
  proc lr_submit_cr {} {
    global env
    set bound [expr {[info exists env(LR_SUBMIT_PAINT_S)] ? $env(LR_SUBMIT_PAINT_S) : 8}]
    # LR_SUBMIT_PAINT_S=0 is the EXPLICIT OPT-OUT — send the CR the moment the text is typed, which
    # is the pre-2026-09-22 behaviour exactly. It is a kill switch and a test seam, not a degraded
    # path, so it records nothing: a CR-UNCONFIRMED note here would say the composer was unreadable
    # when in fact it was never asked.
    if {$bound <= 0} { send -- "\r"; return }
    for {set i 0} {$i < $bound} {incr i} {
      set sv [lr_screen]
      if {$sv eq "DRAFT-MINE"} {
        lr_note composer-painted inject "composer shows our draft after ${i}s — the CR is a separate keystroke"
        send -- "\r"
        return
      }
      if {$sv eq "MENU"} {
        lr_note CR-WITHHELD inject "a menu is parked over the composer — Enter would take its default, so NOTHING was sent"
        lr_tell "CR WITHHELD — a menu is parked over the composer. Enter would take its highlighted default, so nothing was sent. Read the pane."
        return
      }
      lr_pump 1
    }
    # NOT MEASURED, so fall through rather than withhold: our own text is already typed, so a CR
    # here can only submit it or be swallowed exactly as before — it cannot answer a menu we would
    # have read. Withholding would strand every run whose pane is unreadable.
    set cap [lr_capture CR-UNCONFIRMED]
    lr_note CR-UNCONFIRMED inject "composer never read DRAFT-MINE within ${bound}s — sending the CR unconfirmed, as before; screen: $cap"
    send -- "\r"
  }
  # ONE BRACKETED PASTE, THEN THE CR AS ITS OWN KEYSTROKE (lr-wake 2026-10-18, RC5). The prompt used
  # to go in as raw keystrokes, and Claude Code splits an unframed burst by read timing: on pane 430
  # it became two paste chips plus a 7-character tail, the reader could not prove the box was ours,
  # and the Enter was lost. The TUI turns bracketed paste on (DECSET 2004), so the frame makes the
  # whole prompt ONE paste event whatever the pty does to the bytes, and lr_submit_cr gates the CR on
  # the composer showing our text, so it never rides inside the paste. The bash side strips ESC from
  # the prompt, so no byte of it can close the frame early. LR_BRACKETED_PASTE=off types raw keys.
  proc lr_inject {} {
    global env prompt_b
    sleep 0.3
    send "\025"
    sleep 0.2
    if {[info exists env(LR_BRACKETED_PASTE)] && $env(LR_BRACKETED_PASTE) eq "off"} {
      send -- $prompt_b
    } else {
      send -- "\033\[200~$prompt_b\033\[201~"
    }
    lr_submit_cr
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
  # CLAUDE_CODE_DISABLE_AGENT_VIEW=1 takes "Move to background and exit" out of the /exit
  # background-work dialog (W0 item 3), so no later exit can hand this session to a bg worker.
  #
  # The two branches differ ONLY by the cc-close-attrib prefix (see the LR_WRAP block in the bash
  # above for why an empty prefix cannot simply be interpolated). The wrapper execs the binary in
  # place, so the spawned pty, the process group and every pattern below are unchanged by it.
  set wrap $env(LR_WRAP)
  # Identity tokens (validated to a strict charset in bash above), empty for an ordinary session.
  set xargs [expr {[info exists env(LR_EXTRA_ARGS)] ? [regexp -all -inline {\S+} $env(LR_EXTRA_ARGS)] : {}}]
  set xenv  [expr {[info exists env(LR_EXTRA_ENV)] ? [regexp -all -inline {\S+} $env(LR_EXTRA_ENV)] : {}}]
  if {$wrap ne ""} {
    spawn -noecho env -u CLAUDE_CODE_CHILD_SESSION -u LR_RUN -u LR_RUN_DIR -u LR_ADMIT_TOKEN -u LR_SUBMIT_TOKEN -u LR_LOAD_TERM -u LR_SEGMENT_PCT -u LR_ADMIT_MODE -u CC_ADMIT_TOKEN -u CC_ADMIT_WANT_SID -u CC_ADMIT_LOAD_TERM -u CC_ADMIT_BUDGET_KEY -u LR_EXTRA_ARGS -u LR_EXTRA_ENV -u LR_RECORD_ID -u LR_ATTEMPT -u LR_NOTE_DIR -u CC_ADMIT_ACTOR -u CC_PANE_STARTED_FILE -u CC_PANE_EXIT_OWED DISABLE_AUTOUPDATER=1 CLAUDE_CODE_DISABLE_AGENT_VIEW=1 {*}$xenv CLAUDE_CONFIG_DIR=$cfg $wrap $bin --permission-mode $perm --model $model --effort $effort --resume $sid {*}$xargs {*}$aprompt
  } else {
    spawn -noecho env -u CLAUDE_CODE_CHILD_SESSION -u LR_RUN -u LR_RUN_DIR -u LR_ADMIT_TOKEN -u LR_SUBMIT_TOKEN -u LR_LOAD_TERM -u LR_SEGMENT_PCT -u LR_ADMIT_MODE -u CC_ADMIT_TOKEN -u CC_ADMIT_WANT_SID -u CC_ADMIT_LOAD_TERM -u CC_ADMIT_BUDGET_KEY -u LR_EXTRA_ARGS -u LR_EXTRA_ENV -u LR_RECORD_ID -u LR_ATTEMPT -u LR_NOTE_DIR -u CC_ADMIT_ACTOR -u CC_PANE_STARTED_FILE -u CC_PANE_EXIT_OWED DISABLE_AUTOUPDATER=1 CLAUDE_CODE_DISABLE_AGENT_VIEW=1 {*}$xenv CLAUDE_CONFIG_DIR=$cfg $bin --permission-mode $perm --model $model --effort $effort --resume $sid {*}$xargs {*}$aprompt
  }
  set tspawn [clock seconds]
  # The launch lock now names the spawned claude (env and the wrapper both exec in place, so this
  # pid IS the session). A failure here costs the handover, never the recovery.
  if {[info exists env(LR_LOCK_SH)] && $env(LR_LOCK_SH) ne ""} {
    catch { exec env LR_LOCK_PID=[exp_pid] /bin/bash -c $env(LR_LOCK_SH) }
  }
  # ══ THE RELAY IS BYTE-TRANSPARENT (2026-09-28) ═══════════════════════════════════════════════
  # /usr/bin/expect is 5.45 on Tcl 8.5, which cannot hold a 4-byte UTF-8 character. Decoding the
  # session output through the default utf-8 channel turned each byte of an emoji into its own
  # Latin-1 character and re-encoded it, so the peer-mail line painted as `ð¬ peer mail` and every
  # astral glyph the TUI draws was mangled for the life of the session, in the relay AND in
  # interact. BMP characters survived, which is why the arrow on the same line looked fine. The
  # locale is not the cause: this measured the same under UTF-8, LC_ALL=C and env -i.
  # So both channels carry BYTES. Anything this program compares against that stream or types into
  # it goes through lr_b, which re-encodes it with the encoding Tcl decoded it with, restoring its
  # original bytes. If either fconfigure fails, BOTH stay as they were and lr_b is the identity: a
  # half-binary relay would double-encode every non-ASCII byte, which is worse than the old defect.
  set lr_bytes 0
  if {![catch {fconfigure $user_spawn_id -encoding binary}]} {
    if {[catch {fconfigure $spawn_id -encoding binary}]} {
      catch {fconfigure $user_spawn_id -encoding [encoding system]}
    } else {
      set lr_bytes 1
    }
  }
  proc lr_b {s} {
    global lr_bytes
    if {$lr_bytes} { return [encoding convertto [encoding system] $s] }
    return $s
  }
  # The reply drain decodes what it keeps as utf-8 explicitly, so its keystrokes go back the same way.
  proc lr_b_utf8 {s} {
    global lr_bytes
    if {$lr_bytes} { return [encoding convertto utf-8 $s] }
    return $s
  }
  set re_menu        [lr_b $env(LR_RE_MENU)]
  set re_asis_strong [lr_b $env(LR_RE_ASIS_STRONG)]
  set re_asis        [lr_b $env(LR_RE_ASIS)]
  set re_trust       [lr_b $env(LR_RE_TRUST)]
  set re_trust_rb    [lr_b $env(LR_RE_TRUST_RB)]
  set re_fs          [lr_b $env(LR_RE_FS)]
  set re_fs_rb       [lr_b $env(LR_RE_FS_RB)]
  set re_overage     [lr_b $env(LR_RE_OVERAGE)]
  set re_ready       [lr_b $env(LR_RE_READY)]
  set prompt_b       [lr_b $prompt]

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
      lr_say "$what — selector confirmed by the trigger, answered."
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
      lr_say "$what — selector confirmed by $seen, answered."
      return 1
    }
    lr_tell "WARNING — could not confirm the selector for $what; sent NOTHING. Answer it by hand in the pane. Refusing to guess: the next option down is destructive."
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
    -re $re_menu {
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
          answer_menu 1 $re_asis_strong $re_asis "resume full session as-is"
        } else {
          answer_menu 0 $re_menu $re_menu "resume from summary (--summary)" 1
        }
      }
      # answer_menu leaves `timeout` at 300; re-entering the loop with it would restore the
      # silent 300 s give-up this wave deleted.
      set timeout $quiet
      exp_continue
    }
    -re $re_trust {
      sleep 1
      answer_menu 0 $re_trust_rb $re_trust_rb "folder trust"
      # answer_menu leaves `timeout` at 300; re-entering the loop with it would restore the
      # silent 300 s give-up this wave deleted.
      set timeout $quiet
      exp_continue
    }
    # informational overage NOTICE (Enter dismisses either way — safe). Opt-in upsells
    # (extra-usage/remote-control/passes) are declined at the SOURCE via lr-preseed-env.sh
    # raising their *SeenCount gates — never blindly answered here (Enter could enable them).
    -re $re_overage { send "\r"; exp_continue }
    # fullscreen upsell: option 2 is "Not now" (options verified in the 2.1.220 bundle:
    # ["Yes, try it", "Not now"]). Previously this sent Down+CR BLIND, so a reordered menu would
    # have selected "Yes, try it" and restarted the session mid-recovery; now the selector is read
    # back first, and an unconfirmed selector parks instead of guessing.
    -re $re_fs {
      sleep 1
      answer_menu 1 $re_fs_rb $re_fs_rb "fullscreen upsell (Not now)"
      # answer_menu leaves `timeout` at 300; re-entering the loop with it would restore the
      # silent 300 s give-up this wave deleted.
      set timeout $quiet
      exp_continue
    }
    -re $re_ready {
      if {$argvp} {
        # The composer is mounted and the prompt is already in the CLI: nothing to type. The
        # transcript probe below is the verdict. Not a READY note: at stage ready that would read as
        # a finished no-prompt run to the reconciler.
        lr_note READY-ARGV inject "the ready signal matched [expr {[clock seconds] - $tspawn}]s after spawn; the prompt went on argv, nothing typed"
      } elseif {$prompt ne "" && !$injected} {
        set injected 1
        # 0.3/0.2/0.2 inside lr_inject, down from 2/1/1. The sleeps let the composer mount and keep
        # the ^U and the paste apart — a settling delay, not a wait for a remote event. 4 s of the
        # old budget was pure latency on every recovery, and the submit poll below now measures the
        # outcome instead of guessing at it.
        lr_inject
      } elseif {$prompt eq "" && !$ready_noted} {
        set ready_noted 1
        lr_note READY ready "the ready signal matched and there is no prompt to type — nothing was sent"
      }
    }
    timeout {
      # ── THE LOOK ARM: WHAT USED TO BE `timeout {}` ──────────────────────────────────────────
      # READY has not matched within $quiet seconds of the last (re)arm. Two causes look alike here:
      # the binary stopped painting the READY phrase (version coupling, which no wording here can
      # prevent), or the TUI has simply not mounted yet (a slow boot, the common case under load).
      # So the SCREEN is asked for a SHAPE (an empty composer box between two border runs) and,
      # until $readywait seconds from the spawn, any other answer RE-ARMS the wait instead of
      # ending it. A look is cheap (under 1 s at load 250) and types nothing.
      set waited [expr {[clock seconds] - $tspawn}]
      if {$argvp} {
        # The prompt is already in the CLI. Keep the menu arms live until READY or the bound; the
        # transcript probe ends the wait early once the prompt has landed.
        set pv [lindex [lr_probe $t0] 0]
        if {$pv ne "submitted" && $pv ne "queued" && $waited < $readywait} {
          set timeout $quiet
          exp_continue
        }
      }
      #
      # 🚨 NEVER A BLIND CR INTO A QUIET PTY. A parked menu is quiet too, and Enter on one takes the
      # highlighted default — which on the resume menu is "resume from summary" (spends usage,
      # loses the goal) and on the trust prompt is worse. So the ONLY screen that licenses typing is
      # one that affirmatively reads EMPTY; MENU, DRAFT and UNKNOWN all park and SAY SO. That is the
      # 2026-08-06 rule this repo already runs on: typing needs the affirmative (memory
      # probe-that-acts-on-absence-must-confirm-presence).
      if {$argvp} {
        # handled above: nothing is typed on argv, and the poll below gives the verdict
      } elseif {$prompt ne "" && !$injected} {
        set sv [lr_screen]
        if {$sv eq "EMPTY"} {
          set injected 1
          lr_note READY-QUIET inject "READY never matched; composer reads EMPTY ${waited}s after spawn — typing"
          lr_say "READY never matched, but the composer reads EMPTY ${waited}s after spawn — typing the prompt on that evidence."
          lr_inject
        } elseif {$waited < $readywait} {
          # NOT MOUNTED YET is not a verdict (gap 1): re-arm and look again, up to the bound.
          if {![info exists lookwait]} {
            set lookwait 1
            lr_say "READY not seen and the screen reads $sv ${waited}s after spawn — still booting, looking again every ${quiet}s up to ${readywait}s."
          }
          set timeout $quiet
          exp_continue
        } else {
          set cap [lr_capture READY-NOT-SEEN]
          lr_note READY-NOT-SEEN inject "screen reads $sv ${waited}s after spawn (bound ${readywait}s) — prompt NOT typed; screen: $cap"
          lr_tell "✗ READY NEVER SEEN — prompt NOT typed: ${waited}s after spawn the screen reads $sv, not an empty composer. NOTHING was sent, because Enter on a parked menu takes its default. Type the prompt by hand in the pane. Screen: $cap"
        }
      } elseif {$prompt eq "" && !$ready_noted} {
        if {[lr_screen] eq "EMPTY"} {
          set ready_noted 1
          lr_note READY-QUIET ready "READY never matched; the composer reads EMPTY after ${quiet}s quiet and there is no prompt to type"
        }
      }
    }
    eof { exit }
  }
  if {$injected || $argvp} {
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
    # recr COUNTS KEYSTROKES SENT, NOT SCREEN READS ATTEMPTED (2026-09-22).
    # It used to be a one-shot latch set BEFORE the branch, so the NOT-MEASURED arm below spent the
    # whole re-CR budget without sending anything: at t=29 a still-booting TUI reads EMPTY, the
    # latch closed, the deadline stretched to qmax, and the screen was never consulted again for the
    # remaining 150s. Measured on panes 503 and 480 (sessions b6125384, 2825e1e5): both sat with the
    # prompt in the composer and a trailing newline where the CR landed, both wrote FAILED:submit,
    # and re-running this oracle against pane 503 afterwards returned DRAFT-MINE — the evidence that
    # licenses the re-CR was there, just not at t=29. 4 of 4 runs reaching this stage ended
    # FAILED:submit; the two that recovered did so because a human pressed Enter.
    # So: EMPTY/UNKNOWN reschedules the LOOK, DRAFT-MINE spends a SEND, and the two are now separate
    # budgets (memory: predicate-refusal-is-not-a-negative, empty-vs-no-surface).
    set recr 0
    set recrmax [expr {[info exists env(LR_SUBMIT_RECR_MAX)] ? $env(LR_SUBMIT_RECR_MAX) : 2}]
    # THE LOOK SCHEDULE (LR_RECR_SCHEDULE, validated in bash): the composer is looked at these many
    # WALL-CLOCK seconds after the first CR, then every 15 s. Wall clock, not t: t counts loop turns,
    # which run ~1.3 s each on a loaded box, so a look at t=5 landed at 9 s. A look that ran late skips
    # the entries it already passed, so a slow box never fires two looks back to back. The deadline
    # stays in turns; since a turn is never shorter than a second, t never passes el.
    set sched {}
    if {[info exists env(LR_RECR_SCHEDULE)]} {
      foreach s [split $env(LR_RECR_SCHEDULE) ","] { if {$s ne ""} { lappend sched $s } }
    }
    if {[llength $sched] == 0} { set sched {5 15 30 45} }
    set si 0
    set nextlook [lindex $sched 0]
    set tcr [clock milliseconds]
    # The poll must outlive the first look: a deadline of `poll` turns shorter than it would end the
    # run with FAILED:submit without ever reading the composer.
    if {$deadline < $nextlook + 1} { set deadline [expr {$nextlook + 1}] }
    # ON ARGV NOTHING WAS TYPED, so there is no composer draft a re-Enter could submit and no
    # keystroke is ever owed: no looks, and the probe alone is polled to the engagement bound.
    if {$argvp} {
      set recrmax 0
      if {$deadline < $qmax} { set deadline $qmax }
    }
    set unmeasured 0
    for {set t 0} {$t < $deadline} {incr t} {
      set r [lr_probe $t0]
      set verb [lindex $r 0]
      if {$argvp && $verb eq "skip"} { break }
      set ts   [lindex $r 1]
      if {$verb eq "submitted"} { break }
      if {$verb eq "queued" && $deadline < $qmax} { set deadline $qmax }
      # SKIP LOOKS AS NONE DOES (lr-wake 2026-10-18, pane 430). A run with no probe used to break
      # here, before its first look: no second Enter, no note, one log line. The transcript cannot
      # answer for it, but the composer still can, so it gets the same looks and the same gated
      # re-Enters, and ends on an explicit UNSUBMITTED or UNVERIFIED below.
      set look [expr {$verb eq "none" || $verb eq "skip"}]
      set el [expr {([clock milliseconds] - $tcr) / 1000}]
      # Turns and seconds drift apart on a loaded box, so while a scheduled look is still ahead and
      # could still act, the deadline is kept two turns out rather than trusted to line up.
      if {$look && $recr < $recrmax && $si < [llength $sched] && $deadline < $t + 2} {
        set deadline [expr {$t + 2}]
      }
      if {$look && $recr < $recrmax && $el >= $nextlook} {
        while {$si < [llength $sched] && [lindex $sched $si] <= $el} { incr si }
        if {$si < [llength $sched]} {
          set nextlook [lindex $sched $si]
        } else {
          set nextlook [expr {$el + 15}]
        }
        set sv [lr_screen]
        if {$sv eq "DRAFT-MINE"} {
          incr recr
          lr_note SUBMIT-RECR submit "prompt still in the composer ${el}s after the first CR — one more CR"
          lr_say "the prompt is still sitting in the composer ${el}s after the first CR (nothing in the transcript) — sending ONE more Enter."
          send "\r"
          # EXTEND, NEVER SHRINK. This used to be an unconditional `set deadline [expr {$t + 10}]`,
          # which on a run whose deadline had already been stretched to qmax CUT it back to 10s and
          # threw away both the remaining engage budget and the second re-CR the fix above buys.
          # It also covers the NEXT scheduled look, which may lie past t+15.
          set dl [expr {$t + 15}]
          if {$nextlook + 1 > $dl} { set dl [expr {$nextlook + 1}] }
          if {$deadline < $dl} { set deadline $dl }
        } elseif {$sv eq "EMPTY" || $sv eq "UNKNOWN"} {
          # NOT MEASURED — and it must not share an action with DRAFT/MENU, which SETTLE the
          # question. EMPTY is the composer state a SUCCESSFUL submit LEAVES BEHIND, and UNKNOWN is
          # the oracle reporting that it read no pane at all (its first guard returns UNKNOWN
          # before any read when LR_PANE — `${ITERM_SESSION_ID##*:}` — is empty). Neither is a
          # negative; breaking on them convicts a submit that worked.
          #
          # NO APOSTROPHE MAY APPEAR ANYWHERE IN THIS BLOCK, and not as a style rule: every line
          # here lives inside `expect -c ...`, a SINGLE-QUOTED bash string, so one of them CLOSES
          # that string and the whole file stops PARSING — the same class as the bash-3.2 paren
          # trap the header records. Measured twice on 2026-09-21: first by two possessives in
          # this very comment, then again by the warning against them, which quoted the character.
          # The check is `/bin/bash -n` on this file.
          #
          # A CURLY BRACE IS THE SAME HAZARD ONE LAYER IN, and it bit this comment too: Tcl counts
          # braces LEXICALLY across a braced block and does not exempt a line starting with `#`,
          # so an unbalanced one written inside a comment closes the enclosing block early. The
          # third red of the day was this paragraph naming the else-branch in literal Tcl. Keep
          # every brace in this block balanced, comments included; `expect -f` is the check.
          #
          # Measured 2026-09-21 on the /limit-recover ingest of session 83c4f1b8: this branch broke
          # the poll at t=29 and wrote `FAILED:submit "within 30s"` at 00:18:35Z — and that prompt
          # user record is in the transcript at 00:18:35.510Z. The submit had WORKED; a resumed TUI on
          # this box takes ~30s to boot (~94KB of always-loaded instructions, the SessionStart
          # hooks, 6 MCP servers) before its first record lands, so a 30s bound sits below the
          # latency it is judging. The honest window is the one the queued path and handoff-fire
          # already use for this same question: RCY_ENGAGE_TIMEOUT.
          #
          # WHICH of the two values it was on that run is NOT recoverable — both take this branch
          # and the old FAILED note dropped $sv (the sibling READY-NOT-SEEN note records it; this
          # one did not). That gap is why the note below writes $sv. Do not read the incident as
          # evidence for one value over the other; the fix is correct for both.
          #
          # Neither reading licenses a keystroke, so: no CR, and poll the transcript — the only
          # instrument that can settle it — to the engagement budget.
          # (memory: predicate-refusal-is-not-a-negative · empty-vs-no-surface ·
          #  gate-default-decides-failure-direction)
          # With no probe there is no transcript to poll, so nothing later can settle it: stop here
          # and let the verdict below say UNVERIFIED with this reading.
          if {$verb eq "skip"} { break }
          if {$deadline < $qmax} { set deadline $qmax }
          # ONCE, not per look. The look is now rescheduled every 15s rather than latched off after
          # the first one, so an unguarded note here would write ten identical lines into the state
          # log and bury the verdict that follows them.
          if {!$unmeasured} {
            set unmeasured 1
            lr_note SUBMIT-UNMEASURED submit "screen reads $sv ${el}s after the first CR — not a negative; re-reading the composer on the look schedule and polling the transcript to ${deadline}s"
            lr_say "nothing in the transcript ${el}s after the first CR and the screen reads $sv — NOT a measured failure (an EMPTY composer is what a successful submit leaves, and UNKNOWN means no pane was read). No keystroke sent; re-reading the composer on the look schedule and polling the transcript to ${deadline}s."
          }
        } else {
          set cap [lr_capture RECR-WITHHELD]
          lr_say "nothing in the transcript ${el}s after the first CR and the composer reads $sv, not our prompt — NOT re-sending Enter; polling the transcript to ${deadline}s. screen: $cap"
          # STOP LOOKING, KEEP POLLING. This used to `break`, which with the first look at 5 s ended
          # the poll and wrote FAILED:submit while an accepted Enter can take 1.6-11 s (W0) to land.
          set recr $recrmax
        }
      }
      lr_pump 1
    }
    if {$verb eq "submitted"} {
      lr_note submitted submit "user record carrying the run token at $ts"
      lr_say "SUBMITTED — the prompt is in the transcript at $ts."
    } elseif {$verb eq "queued"} {
      lr_note queued submit "enqueued at $ts; still behind a running turn at the ${deadline}s bound"
      lr_say "QUEUED — the prompt was accepted at $ts and is waiting behind a running turn. It has NOT started yet."
    } elseif {$verb eq "unreadable"} {
      lr_note INDETERMINATE:submit submit "the target transcript could not be read — submission NOT measured"
      lr_say "submission NOT MEASURED — the target transcript could not be read. This is not a failure and it is not a success; read the pane."
    } elseif {$verb eq "skip"} {
      # NEVER GREEN WITHOUT A PROBE. Our own text still in the box is UNSUBMITTED, a fact, and the
      # box is filed as this pane residue so a later rail clears it; anything else is UNVERIFIED.
      set sv [lr_screen 1]
      set cap [lr_capture UNSUBMITTED]
      if {$sv eq "DRAFT-MINE"} {
        lr_note UNSUBMITTED submit "no submit probe; our prompt is still in the composer after $recr re-Enter(s); screen: $cap"
        lr_tell "✗ UNSUBMITTED — the prompt is still sitting in the composer after $recr re-Enter(s), and no submit probe was reachable to check the transcript. Check the pane. Screen at this moment: $cap"
      } else {
        lr_note UNVERIFIED:submit submit "no submit probe; the composer reads $sv after $recr re-Enter(s); screen: $cap"
        lr_tell "⚠ UNVERIFIED — no submit probe was reachable, so nothing proves the prompt landed; the composer reads $sv after $recr re-Enter(s). Check the pane. Screen at this moment: $cap"
      }
    } else {
      # Read the box once more first: our own text still there is filed as this pane residue.
      lr_screen 1
      set cap [lr_capture NOT-SUBMITTED]
      if {$argvp} {
        lr_note FAILED:submit submit "the prompt went on the spawn argv and no record of it is in the transcript within ${deadline}s; screen: $cap"
        lr_tell "✗ NOT SUBMITTED — the prompt went on the spawn argv and is not in the transcript within ${deadline}s. The CLI may still be holding it behind a slow boot or a dialog: check the pane, and type the prompt by hand only if the session is idle and has not answered it. Screen at this moment: $cap"
      } else {
        lr_note FAILED:submit submit "no record of the prompt in the transcript within ${deadline}s; screen: $cap"
        lr_tell "✗ NOT SUBMITTED — the prompt never reached the transcript within ${deadline}s. The session is alive and may be TASK-LESS: check the composer, and type the prompt by hand only if it is not already answered. Screen at this moment: $cap"
      }
    }
    set timeout 300
  }
  # >>> lr-reply-drain  (byte-identical in scripts/limit-recover/lr-fire-resume.sh AND bin/reso-resume-one;
  #     tests/lr-fire-resume-reply-drain.bats extracts it from both by these marker lines and diffs them)
  # ── DRAIN THE PANE BEFORE interact, AND DROP THE TERMINAL REPORTS IN IT ─────────────────────
  # Everything above ran for up to minutes WITHOUT reading our own stdin (the pane tty). Meanwhile
  # the TUI queried the terminal at boot and turned on mouse tracking, so the terminal answers queue
  # on that tty: the XTVERSION reply (ESC P > | kitty ... ESC backslash), the kitty keyboard reply
  # (ESC [ ? 5 u), the DA1 reply (ESC [ ? 62 ; 52 ; c), and every mouse motion report
  # (ESC [ < 35 ; 45 ; 24 M). interact then forwarded that whole backlog into the new pty as TYPED
  # text, and the resumed composer held it verbatim (measured 2026-09-23, pane 405).
  # So: read what is already queued, without blocking and within a fixed bound, drop the reports,
  # and hand everything else (a human keystroke typed during boot) to the session untouched.
  # The tty goes raw for the read because a cooked tty releases nothing until a newline, and no
  # report ends in one; it is restored to its exact prior state before interact takes over.
  proc lr_reply_filter {s} {
    # string reports: DCS (ESC P), OSC (ESC ]), APC (ESC _), PM (ESC ^), ended by ST or BEL
    regsub -all {\x1b[P\]_^][^\x1b\x07]*(\x07|\x1b\\)} $s {} s
    # SGR mouse reports: ESC [ < b ; x ; y M or m
    regsub -all {\x1b\[<[0-9;]*[Mm]} $s {} s
    # private-prefix CSI replies: DA1/DA2 (c), kitty keyboard flags (u), DECRPM ($y). A real key
    # never carries the ? > = prefix, so a kitty-protocol key (ESC [ 97 ; 5 u) passes untouched.
    regsub -all {\x1b\[[?>=][0-9;:]*[$]?[A-Za-z]} $s {} s
    # cursor position report: ESC [ row ; col R
    regsub -all {\x1b\[[0-9]+;[0-9]+R} $s {} s
    # a report cut in half by the end of the read: drop the unterminated prefix, a lone ESC included
    regsub {\x1b([P\]_^][^\x1b\x07]*\x1b?|\[[<?>=]?[0-9;:]*[$]?)?$} $s {} s
    return $s
  }
  proc lr_drain_user {} {
    set tty 0
    set saved ""
    if {![catch {exec /bin/stty -g <@ stdin 2>/dev/null} saved]} {
      set tty 1
      catch {exec /bin/stty raw -echo <@ stdin 2>/dev/null}
    }
    set buf ""
    catch {
      fconfigure stdin -blocking 0 -translation binary
      set idle 0
      for {set i 0} {$i < 40 && $idle < 3} {incr i} {
        set chunk [read stdin]
        if {$chunk eq ""} { incr idle; after 20 } else { set idle 0; append buf $chunk }
      }
    }
    catch {fconfigure stdin -blocking 1}
    if {$tty} { catch {exec /bin/stty $saved <@ stdin 2>/dev/null} }
    return [encoding convertfrom utf-8 [lr_reply_filter $buf]]
  }
  # <<< lr-reply-drain
  # echo back ON before the drain snapshots the tty, so the state it restores is the ORIGINAL one
  if {$lr_tty_orig ne ""} { catch {exec /bin/stty $lr_tty_orig <@ stdin 2>/dev/null} }
  set lr_keep [lr_drain_user]
  if {$lr_keep ne ""} { send -- [lr_b_utf8 $lr_keep] }
  interact
' || lr_rc=$?
[ -z "$lr_tty_saved" ] || stty "$lr_tty_saved" 2>/dev/null || true
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
# >>> lr-successor
# A STAGED SUCCESSOR RUNS HERE INSTEAD OF BEING TYPED (docs/plans/RECYCLE_KEYSTROKELESS_DELIVERY.md §D1).
# A recycle stages its relaunch in lib/pane-successor.sh before it sends /exit; this process holds the
# pane's tty, so it claims the stage (an atomic rename the watcher reads as the ack) and execs it. On
# 2026-10-09 the typed form failed 16 times at load ~45 per core and stranded pane 44. Anything
# unreadable — no lib, no stage, a refused take — falls through to the ordinary shell below unchanged.
lr_succ_s="$0" lr_succ_lib=""
while [ -L "$lr_succ_s" ]; do
  lr_succ_t="$(readlink "$lr_succ_s" 2>/dev/null)" || break
  case "$lr_succ_t" in /*) lr_succ_s="$lr_succ_t" ;; *) lr_succ_s="$(dirname "$lr_succ_s")/$lr_succ_t" ;; esac
done
lr_succ_d="$(cd "$(dirname "$lr_succ_s")" 2>/dev/null && pwd)" || lr_succ_d=""
for lr_succ_c in "${lr_succ_d:+$lr_succ_d/../../lib/pane-successor.sh}" "${HOME:-}/.claude/lib/pane-successor.sh"; do
  [ -n "$lr_succ_c" ] && [ -r "$lr_succ_c" ] && { lr_succ_lib="$lr_succ_c"; break; }
done
# shellcheck source=/dev/null  # runtime-resolved: checkout sibling, else the live layer
if [ -n "$lr_succ_lib" ] && . "$lr_succ_lib" 2>/dev/null \
   && lr_succ_claimed="$(cc_pane_successor_take)" && [ -n "$lr_succ_claimed" ]; then
  printf '\n' >&2
  CC_SAY_DETAIL="staged successor $lr_succ_claimed" _lrf_say run "${SID:+${SID:0:8} }ended, starting successor" "claude exited rc $lr_rc"
  cc_pane_successor_exec "$lr_succ_claimed" 1 || true
fi
# <<< lr-successor
# WHAT FOLLOWS, SAID ONCE (lr-wake 2026-10-18, h defect 6). "This pane is now an ordinary shell" was
# printed after every exit, the planned /exit of a recycle included, where handoff-fire types the
# relaunch at this shell a moment later: the same false husk banner as complaint (c). A recycle
# pending for this pane (lib/pane-recycle-pending.sh reads the recycler's own lock) gets one line
# naming what follows; only when nothing follows does the pane say it is a shell. The pending check
# fails toward "pending", so it is asked only when there is a pane id to ask it about.
# Both lines go through the shared renderer (lib/cc-say.sh, Wave H2).
lr_pend_lib="" lr_pend_id="${KITTY_WINDOW_ID:-${LR_PANE:-}}"
for lr_succ_c in "${lr_succ_d:+$lr_succ_d/../../lib/pane-recycle-pending.sh}" "${HOME:-}/.claude/lib/pane-recycle-pending.sh"; do
  [ -n "$lr_succ_c" ] && [ -r "$lr_succ_c" ] && { lr_pend_lib="$lr_succ_c"; break; }
done
# shellcheck source=/dev/null  # runtime-resolved: checkout sibling, else the live layer
if [ -n "$lr_pend_id" ] && [ -n "$lr_pend_lib" ] && . "$lr_pend_lib" 2>/dev/null \
   && cc_pane_recycle_pending "$lr_pend_id"; then
  printf '\n' >&2; _lrf_say run "${SID:0:8} relaunch follows here" "claude exited rc $lr_rc"
else
  printf '\n' >&2; _lrf_say warn "${SID:0:8} ended, pane is an ordinary shell" "rc $lr_rc · close it (Ctrl-D)"
fi
# `-l -i` is load-bearing, not cosmetic, for the reason bin/cc-pane-runner:69 records: ~/.zprofile
# puts ~/.claude/shims on PATH and ~/.zshrc synthesizes ITERM_SESSION_ID from KITTY_WINDOW_ID, so a
# non-login non-interactive shell yields a pane that is alive and UNADDRESSABLE — and the launcher
# names a recycle relaunches with are zsh FUNCTIONS defined only in the interactive rc.
# A pane launched `… | tee log` would hand that shell (and any claude typed in it) the pipe as stdout,
# and claude reads a non-tty stdout as print mode: re-point it at the pane's terminal, as
# lib/pane-successor.sh's loop does (recycle-failure-2026-10-14 F2). No controlling tty ⇒ unchanged.
if [ -t 0 ] && { [ ! -t 1 ] || [ ! -t 2 ]; } && [ -w /dev/tty ] && (: >/dev/tty) 2>/dev/null; then
  exec >/dev/tty 2>/dev/tty; _lrf_detail "re-attached to /dev/tty" "output was not the terminal (a pipe or file)"
fi
exec "${SHELL:-/bin/zsh}" -l -i
