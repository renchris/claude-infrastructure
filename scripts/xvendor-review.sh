#!/usr/bin/env bash
# xvendor-review.sh — one cross-vendor (OpenAI Codex) review of COMMITTED code, inside the envelope the
# grant was given on (ruling d610f8473106; design docs/research/lead-keeps-working-2026-10-24.md §3.9).
#
# Why a wrapper at all: the grant is "a Codex review on the ChatGPT subscription, of an export of the
# committed tree, with the model's reads confined to that export, never past 80% of the weekly meter".
# Every clause of that sentence is a check below, so the envelope lives in tracked code rather than in
# whatever flags a session remembers to type. The 80% guard was ported from the untracked xverify.py.
#
# THE ENVELOPE, in run order (each refusal happens before codex exec is ever launched):
#   1. <rev> (default HEAD) must be a commit of <repo>                                      else rc 2
#   2. meter, under an exclusive mkdir lock held from the read through codex's launch, so two sessions
#      cannot both read 79% and both call. Newest 20 rollout-*.jsonl under the REAL CODEX_HOME/sessions
#      by mtime; the last "rate_limits" line of each; the window with window_minutes >= 10080 among
#      primary/secondary, else primary. A reading whose resets_at has passed belongs to an expired
#      window: it counts as 0 and stderr says "window expired".
#      >= CC_XVR_METER_STOP (80) rc 5 · rollouts exist but none readable rc 4 · no rollouts: run, noted
#   3. `codex login status` must say "Logged in using ChatGPT" (subscription, never the API)  else rc 3
#   4. export: `git archive <rev> | tar -x` into a temp dir, then every path listed in
#      <repo>/.claude/xvendor-review.exclude (and the exported copy of that file) is deleted.
#      Uncommitted and untracked files are absent by construction.
#   4b. read confinement: a temp CODEX_HOME holding only a copy of auth.json and a config.toml whose
#      permission profile "xvr" grants read on ":minimal" and the export, nothing else. A per-run canary
#      (a random token under the real HOME) is read through `codex sandbox -P xvr`; if the token shows,
#      or the profile evidently did not load, nothing is reviewed                               rc 6
#   5. env -u OPENAI_API_KEY -u OPENAI_BASE_URL HOME=<temp> CODEX_HOME=<temp> timeout <s>
#        codex exec --skip-git-repo-check -C <export> [-m <model>] "<prompt>"
#   6. review on stdout; one IDL row; temp dirs deleted; lock released (all in the EXIT trap)
#
# STEP-0 FINDING — why there is no `-s` and no outer sandbox-exec (measured on codex-cli 0.147.0 against a
# local fake Responses API, zero quota):
#   - `codex exec -s read-only`: the model's shell command READ a canary under the real $HOME. -s confines
#     writes only.
#   - `-s read-only` plus a permission profile: -s overrides the profile; the canary was readable again.
#   - the config.toml profile below with NO -s/--sandbox flag: canary unreadable, export readable, a write
#     into the export denied, network (curl) denied. This is the only form that confined reads.
#   - an outer /usr/bin/sandbox-exec cannot host codex: its own seatbelt does not nest
#     (`sandbox_apply: Operation not permitted`) and it cannot canonicalize its config (EPERM).
#   So never pass -s/--sandbox, --dangerously-*, --add-dir or --approve-for-me here: each widens or
#   overrides the profile.
#
# MOVED BINARY — why codex is run by its realpath (measured 2026-10-26 on codex-cli 0.164.0, the standalone
# package that turned ~/.local/bin/codex into a symlink into ~/.codex/packages/standalone/releases/<v>/):
#   codex re-executes itself inside the profile's seatbelt to read AGENTS.md, by the path it was launched
#   as. Launched via the symlink, every exec failed before any model call: "sandbox-exec: execvp() of
#   '~/.local/bin/codex' failed: Operation not permitted" (exit 71). Launched by its realpath, it runs, its
#   bundled rg runs, and with the profile unchanged a file under ~/.codex outside the release dir is still
#   denied. So the fix adds nothing to the read set: no package dir, no ~/.codex, no $HOME.
#
# TWO SIDE EFFECTS of the temp CODEX_HOME, both carried back so the envelope costs the operator nothing:
#   - codex may refresh the OAuth token into <temp>/auth.json. A rotated refresh token lost with the temp
#     dir would log the operator out, so a changed, valid, SAME-account auth.json is copied back
#     atomically (mode 0600). A different account, or invalid JSON, is never copied.
#   - the run's rollout (with its rate_limits) lands in <temp>/sessions; each new rollout is copied to the
#     same relative path under the real CODEX_HOME/sessions, so the next meter read sees this run's spend.
#
# Usage: xvendor-review.sh --meter
#          → prints used_percent=<n> window_minutes=<m> source=<file>; rc 0, rc 4 if unreadable
#        xvendor-review.sh <repo> <prompt-file|-> [--rev <rev>] [--model <m>]
# Exit:  0 ok · 2 usage / bad rev / bad exclude path · 3 not a ChatGPT login, or no codex · 4 meter unreadable (or its
#        lock held past CC_XVR_LOCK_WAIT_S) · 5 meter >= stop · 6 read confinement unproven · otherwise
#        codex's own rc (124 = CC_XVR_TIMEOUT_S hit)
# Env:   CC_XVR_METER_STOP (80)    percent at or above which no call is made
#        CC_XVR_TIMEOUT_S (1800)   bound on codex exec
#        CC_XVR_LOCK_WAIT_S (600)  how long to wait for the meter lock before refusing
#        CC_XVR_LOCK_POLL_S (1)    poll interval while waiting
#        CC_IDL ($HOME/.claude/autonomy/idl.jsonl)   where the run's row is appended
#        CODEX_HOME ($HOME/.codex) the real codex home: auth source, meter source, copy-back target
#        TMPDIR (/tmp)             holds the lock, the export and the temp CODEX_HOME
# codex prints a harmless "could not create PATH aliases … temporary dir" warning under a temp
# CODEX_HOME; it is not an error.
set -uo pipefail

PROG="xvendor-review"
HOME_REAL="$HOME"
CODEX_REAL="${CODEX_HOME:-$HOME/.codex}"
STOP="${CC_XVR_METER_STOP:-80}"
TMPD="${TMPDIR:-/tmp}"; TMPD="${TMPD%/}"
LOCK="$TMPD/xvr-meter.lock"
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
PROFILE="xvr"
CONFINE="codex-permission-profile"

say() { printf '%s: %s\n' "$PROG" "$*" >&2; }

# ── state the EXIT trap reads ───────────────────────────────────────────────────────────────────────────
LOCK_HELD=0 EXP="" CH="" CANARY="" AUTH_SUM="" ROW=0 REPO="" REV="" M_USED="" M_WIN="" M_SRC=""

lock_release() {
  [ "$LOCK_HELD" = 1 ] || return 0
  # Only our own lock: a stale-lock taker may have replaced it after we were presumed dead.
  if [ "$(cat "$LOCK/pid" 2>/dev/null)" = "$$" ]; then rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null; fi
  LOCK_HELD=0
}

lock_take() {
  local max="${CC_XVR_LOCK_WAIT_S:-600}" poll="${CC_XVR_LOCK_POLL_S:-1}" deadline pid noted=0
  deadline=$(( $(date +%s) + max ))
  while ! mkdir "$LOCK" 2>/dev/null; do
    pid="$(cat "$LOCK/pid" 2>/dev/null)"
    # A holder whose pid is dead left the lock behind; take it. An empty pid is a holder between its
    # mkdir and its pid write, so it is waited on, not stolen.
    if [ -n "$pid" ] && ! ps -p "$pid" >/dev/null 2>&1; then
      say "stale meter lock (pid $pid gone): taking it"
      rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null; continue
    fi
    [ "$noted" = 1 ] || { say "meter lock held by pid ${pid:-?}: waiting up to ${max}s"; noted=1; }
    [ "$(date +%s)" -lt "$deadline" ] || return 1
    sleep "$poll"
  done
  printf '%s\n' "$$" > "$LOCK/pid"
  LOCK_HELD=1
}

# meter_read → sets M_USED M_WIN M_SRC. rc 0 a reading · 1 no rollouts at all · 4 rollouts, none readable.
meter_read() {
  local sess="$CODEX_REAL/sessions" files f line got now used win reset
  M_USED="" M_WIN="" M_SRC=""
  [ -d "$sess" ] || return 1
  files="$(find "$sess" -type f -name 'rollout-*.jsonl' -exec stat -f '%m %N' {} + 2>/dev/null \
           | sort -rn | head -20 | cut -d' ' -f2-)"
  if [ -z "$files" ]; then
    # Empty can also mean stat failed over rollouts that do exist; only a census can say "never used".
    [ -n "$(find "$sess" -type f -name 'rollout-*.jsonl' -print 2>/dev/null | head -1)" ] && return 4
    return 1
  fi
  while IFS= read -r f; do
    line="$(grep '"rate_limits"' "$f" 2>/dev/null | tail -1)"
    [ -n "$line" ] || continue
    # The weekly window if one is present, else primary; a window without a numeric used_percent is no reading.
    got="$(printf '%s\n' "$line" | jq -r '
      def ok: type == "object" and (.used_percent | type) == "number";
      (.payload.rate_limits // {}) as $r
      | ([$r.primary, $r.secondary] | map(select(ok and ((.window_minutes // 0) >= 10080))) | .[0])
        // (if ($r.primary | ok) then $r.primary else empty end)
      | "\(.used_percent) \(.window_minutes // 0) \(.resets_at // 0)"' 2>/dev/null)"
    [ -n "$got" ] || continue
    read -r used win reset <<<"$got"
    now="$(date +%s)"
    if awk -v r="$reset" -v n="$now" 'BEGIN { exit !(r + 0 > 0 && r + 0 < n + 0) }'; then
      say "meter: window expired (resets_at $reset passed; read ${used}%), counting it as 0"
      used=0
    fi
    M_USED="$used" M_WIN="$win" M_SRC="$f"
    return 0
  done <<<"$files"
  return 4
}

# shellcheck disable=SC2329  # copy_back, rmtree and on_exit run from the EXIT trap
# Carry the temp CODEX_HOME's side effects back to the real one (header, TWO SIDE EFFECTS).
copy_back() {
  [ -n "$CH" ] && [ -d "$CH" ] || return 0
  local a="$CH/auth.json" real="$CODEX_REAL/auth.json" acct_new acct_real tmp f rel dst
  if [ -f "$a" ] && [ -n "$AUTH_SUM" ] && [ "$(cksum < "$a")" != "$AUTH_SUM" ]; then
    acct_new="$(jq -er '.tokens.account_id // empty' "$a" 2>/dev/null)"
    acct_real="$(jq -er '.tokens.account_id // empty' "$real" 2>/dev/null)"
    if [ -n "$acct_new" ] && [ "$acct_new" = "$acct_real" ]; then
      tmp="$CODEX_REAL/.auth.json.xvr.$$"
      if (umask 077 && cp "$a" "$tmp") && chmod 600 "$tmp" && mv "$tmp" "$real"; then
        say "refreshed auth.json copied back to $CODEX_REAL"
      else rm -f "$tmp"; say "WARNING: could not copy the refreshed auth.json back"; fi
    else
      say "WARNING: the temp auth.json changed but is not valid same-account JSON; real one left alone"
    fi
  fi
  [ -d "$CH/sessions" ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="${f#"$CH/sessions/"}"; dst="$CODEX_REAL/sessions/$rel"
    [ -e "$dst" ] && continue
    mkdir -p "$(dirname "$dst")" && cp "$f" "$dst.xvr.$$" && mv "$dst.xvr.$$" "$dst" \
      || { rm -f "$dst.xvr.$$"; say "WARNING: could not copy rollout $rel back; the meter will not see it"; }
  done <<<"$(find "$CH/sessions" -type f -name 'rollout-*.jsonl' 2>/dev/null)"
}

# shellcheck disable=SC2329
rmtree() { [ -n "$1" ] && [ -d "$1" ] && find "$1" -depth -delete 2>/dev/null; return 0; }

# shellcheck disable=SC2329
on_exit() {
  local rc=$? meter=null
  trap - EXIT INT TERM HUP
  [ -n "$CANARY" ] && rm -f "$CANARY"
  copy_back
  rmtree "$EXP"; rmtree "$CH"
  lock_release
  if [ "$ROW" = 1 ]; then
    [ -n "$M_USED" ] && meter="$M_USED"
    mkdir -p "$(dirname "$IDL")" 2>/dev/null
    jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg repo "$REPO" --arg rev "$REV" \
      --argjson meter "$meter" --arg confine "$CONFINE" --argjson rc "$rc" \
      '{ts:$ts, tool:"xvendor-review", repo:$repo, rev:$rev, meter_before:$meter, confine:$confine, rc:$rc}' \
      >> "$IDL" 2>/dev/null || say "WARNING: could not append the IDL row to $IDL"
  fi
  exit "$rc"
}

usage() { sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }

# ── --meter ────────────────────────────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--meter" ]; then
  meter_read; m=$?
  case "$m" in
    0) printf 'used_percent=%s window_minutes=%s source=%s\n' "$M_USED" "$M_WIN" "$M_SRC"; exit 0 ;;
    1) say "meter: no rollouts under $CODEX_REAL/sessions (never used)"
       printf 'used_percent=0 window_minutes=0 source=none\n'; exit 0 ;;
    *) say "meter: rollouts exist under $CODEX_REAL/sessions but none holds a readable rate_limits"; exit 4 ;;
  esac
fi

# ── args ───────────────────────────────────────────────────────────────────────────────────────────────
[ $# -ge 2 ] || usage
case "$1" in -*) usage ;; esac
REPO_ARG="$1" PROMPT_ARG="$2"; shift 2
REV_ARG=HEAD MODEL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --rev)   [ $# -ge 2 ] || usage; REV_ARG="$2"; shift 2 ;;
    --model) [ $# -ge 2 ] || usage; MODEL="$2"; shift 2 ;;
    *) usage ;;
  esac
done

REPO="$(cd "$REPO_ARG" 2>/dev/null && pwd -P)" || { say "no such repo dir: $REPO_ARG"; exit 2; }
trap on_exit EXIT
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
ROW=1 REV="$REV_ARG"

# 1. a commit of <repo>, recorded by its full sha
if ! git -C "$REPO" cat-file -e "$REV_ARG^{commit}" 2>/dev/null; then
  say "$REV_ARG is not a commit of $REPO"; exit 2
fi
REV="$(git -C "$REPO" rev-parse --verify -q "$REV_ARG^{commit}")" || exit 2

if [ "$PROMPT_ARG" = - ]; then PROMPT="$(cat)"; else PROMPT="$(cat "$PROMPT_ARG" 2>/dev/null)"; fi
[ -n "${PROMPT//[[:space:]]/}" ] || { say "empty or unreadable prompt: $PROMPT_ARG"; exit 2; }

# 2. meter, under the lock
lock_take || { say "meter lock still held after ${CC_XVR_LOCK_WAIT_S:-600}s: refusing (fail closed)"; exit 4; }
meter_read; m=$?
case "$m" in
  0) if awk -v u="$M_USED" -v s="$STOP" 'BEGIN { exit !(u + 0 >= s + 0) }'; then
       say "meter at ${M_USED}% (window ${M_WIN} min, $M_SRC) >= stop ${STOP}%: not calling"; exit 5
     fi
     say "meter at ${M_USED}% (window ${M_WIN} min), stop ${STOP}%" ;;
  1) say "meter: no rollouts under $CODEX_REAL/sessions (never used): proceeding" ;;
  *) say "meter: rollouts exist but none holds a readable rate_limits: refusing (fail closed)"; exit 4 ;;
esac

# 3. codex by its resolved path (header, MOVED BINARY), a temp CODEX_HOME holding only the auth copy, and
#    a ChatGPT login read through it
CODEX_BIN="$(command -v codex)" && CODEX_BIN="$(realpath "$CODEX_BIN" 2>/dev/null)" && [ -x "$CODEX_BIN" ] \
  || { say "codex not found on PATH or its path does not resolve"; exit 3; }
CH="$(mktemp -d "$TMPD/xvr-home.XXXXXX")" && CH="$(cd "$CH" && pwd -P)" || { say "mktemp failed"; exit 2; }
if [ ! -f "$CODEX_REAL/auth.json" ]; then say "no $CODEX_REAL/auth.json: not logged in"; exit 3; fi
(umask 077 && cp "$CODEX_REAL/auth.json" "$CH/auth.json") && chmod 600 "$CH/auth.json" || exit 3
AUTH_SUM="$(cksum < "$CH/auth.json")"
login="$(env -u OPENAI_API_KEY -u OPENAI_BASE_URL HOME="$CH" CODEX_HOME="$CH" "$CODEX_BIN" login status 2>&1)"
case "$login" in
  *"Logged in using ChatGPT"*) ;;
  *) say "codex login status is not a ChatGPT login (got: ${login:0:80}): refusing"; exit 3 ;;
esac

# 4. the export: committed bytes only, minus the exclude list
EXP="$(mktemp -d "$TMPD/xvr.XXXXXX")" && EXP="$(cd "$EXP" && pwd -P)" || { say "mktemp failed"; exit 2; }
case "$EXP" in *'"'*|*\\*) say "export path $EXP cannot be written into TOML"; exit 2 ;; esac
git -C "$REPO" archive "$REV" | tar -x -C "$EXP" || { say "git archive $REV failed"; exit 2; }

exclude_one() { # one exclude line → deleted from the export; rc 2 on a path that could escape it
  local p="$1" m
  p="${p%$'\r'}"; p="${p%"${p##*[![:space:]]}"}"; p="${p#"${p%%[![:space:]]*}"}"
  case "$p" in ''|'#'*) return 0 ;; esac
  case "/$p/" in //*|*/../*) say "exclude path refused (absolute or ..): $p"; return 2 ;; esac
  p="${p%/}"
  # Unquoted on purpose so a glob (secrets/*, *.pem) expands; IFS=newline keeps spaces intact.
  local IFS=$'\n'
  shopt -s nullglob
  for m in "$EXP"/$p; do
    if [ -d "$m" ] && [ ! -L "$m" ]; then find "$m" -depth -delete; else rm -f "$m"; fi
  done
  shopt -u nullglob
  return 0
}
for xf in "$REPO/.claude/xvendor-review.exclude" "$EXP/.claude/xvendor-review.exclude"; do
  [ -f "$xf" ] || continue
  xl="$(cat "$xf")"
  while IFS= read -r line; do exclude_one "$line" || exit 2; done <<<"$xl"
done

# 4b. read confinement: the profile, then a canary read through codex's own runner (no model call)
printf 'default_permissions = "%s"\n\n[permissions.%s.filesystem]\n":minimal" = "read"\n"%s" = "read"\n' \
  "$PROFILE" "$PROFILE" "$EXP" > "$CH/config.toml" || exit 6
mkdir -p "$HOME_REAL/.cache" || { say "cannot create the canary dir"; exit 6; }
CANARY="$HOME_REAL/.cache/xvr-canary.$$"
token="xvr-canary-$$-$RANDOM$RANDOM-$(date +%s)"
(umask 077 && printf '%s\n' "$token" > "$CANARY") || { say "cannot write the canary"; exit 6; }
probe="$(env -u OPENAI_API_KEY -u OPENAI_BASE_URL HOME="$CH" CODEX_HOME="$CH" \
         "$CODEX_BIN" sandbox -P "$PROFILE" -C "$EXP" -- cat "$CANARY" 2>&1 </dev/null)"; prc=$?
rm -f "$CANARY"; CANARY=""
case "$probe" in *"$token"*)
  say "read confinement FAILED: the canary under \$HOME was readable through profile $PROFILE: no review"; exit 6 ;;
esac
# Proven only as a denial: cat of an existing file must fail, and fail as a sandbox refusal. Any other
# failure means the profile itself may not have loaded.
case "$prc:$probe" in
  0:*) say "read confinement unproven: the canary cat succeeded (rc 0): no review"; exit 6 ;;
  *[Nn]"ot permitted"*) ;;
  *) say "read confinement unproven: canary probe rc $prc without a sandbox denial (${probe:0:120}): no review"
     exit 6 ;;
esac

# 5. the review. Launched in the background so the meter lock is released once codex is running, not
#    held for the whole review.
if command -v timeout >/dev/null 2>&1; then BOUND=(timeout "${CC_XVR_TIMEOUT_S:-1800}")
elif command -v gtimeout >/dev/null 2>&1; then BOUND=(gtimeout "${CC_XVR_TIMEOUT_S:-1800}")
else BOUND=(/usr/bin/perl -e 'alarm shift; exec @ARGV or exit 127' "${CC_XVR_TIMEOUT_S:-1800}"); fi
ARGS=(exec --skip-git-repo-check -C "$EXP")
[ -n "$MODEL" ] && ARGS+=(-m "$MODEL")
ARGS+=("$PROMPT")
env -u OPENAI_API_KEY -u OPENAI_BASE_URL HOME="$CH" CODEX_HOME="$CH" "${BOUND[@]}" "$CODEX_BIN" "${ARGS[@]}" </dev/null &
cpid=$!
lock_release
wait "$cpid"
exit $?
