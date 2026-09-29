#!/usr/bin/env bash
# lr-recon-fence.sh — the one-actuator-family predicate (§C10) and the mkdir lock helpers (§C7).
#
# WHY: the reconciler daemon and every older actuator (lr-fleet, lr-handoff, recycle_fire, the
# poller's arms, cc-resume-debt, boot-resume) can each type into the same pane. §C10 gives each
# session exactly one owner at a time. `lr_recon_defers <sid>` answers "does the reconciler own
# this session right now?": rc 0 = DEFER (the caller must not act), rc 1 = ACT. Rules, in order:
#   1. $LR_STATE_DIR/recon.on absent                      → act    "recon-off"
#   2. $LR_RECON_ROOT/owned/<sid> absent                  → act    "not-owned"
#   3. caller's LR_RECORD_ID == owned.record_id           → act    "own-actuator"
#   4. heartbeat progress advanced ≤ LR_RECON_FENCE_FRESH_S (180) ago, where
#      age = now − max(progress_wall, kern.waketime)      → DEFER  "heartbeat-fresh"
#      (a wake restarts the clock, so a laptop lid never makes a live daemon look dead; an
#      unreadable heartbeat skips this rule, it does not defer by itself)
#   5. any owned.procs (pid, lstart) alive                → DEFER  "proc-alive:<role>:<pid>"
#      (regardless of heartbeat: a dead or crash-looping daemon cannot unlock actuation while any
#      process it started for the session still runs)
#   6. otherwise                                          → act    "lapsed"
# A malformed owned file ⇒ DEFER "owned-unreadable": we cannot tell whose it is, and the failure
# to fail toward is "nobody acts", never "two actuators type into one pane".
# On "lapsed" the caller must still take locks/<sid>.launch and re-check H(sid) before typing;
# the callers are wired in W4, this file only answers the question.
#
# No jq: this runs from hooks and the poller under /bin/bash 3.2. The owned/heartbeat/holder
# files are COMPACT JSON (json.dumps separators=(",",":")) and are parsed with awk/sed over that
# form only; a pretty-printed owned file reads as malformed ⇒ DEFER (the safe side). The python
# mirror is lr_recon/fence.py; the W5 rig compares the two.
#
# Verdict goes to stderr as `lr-recon-fence: verdict=defer|act sid=<sid8> reason=<reason>`;
# stdout stays empty so `$(…)` callers never capture noise.
#
# Seams: LR_STATE_DIR (default $HOME/.reso/limit-recover), LR_RECON_ROOT (default
# $LR_STATE_DIR/recon), LR_RECON_NOW (epoch), LR_RECON_WAKETIME (epoch; else parsed from
# `sysctl -n kern.waketime`; unreadable ⇒ 0), LR_RECON_FENCE_FRESH_S, LR_RECON_LOCK_GRACE_S.
#
# Sourced: defines functions only (no `set -e`, no side effects). Executed: CLI —
#   lr-recon-fence.sh defers <sid>                                     exit 0 defer / 1 act
#   lr-recon-fence.sh lock-take <dir> <record_id> <attempt> <role> [pid]  0 taken/1 held/2 cannot
#   lr-recon-fence.sh lock-release <dir> [pid]                         0 released / 1 not ours
#   lr-recon-fence.sh proc-alive <pid> <lstart>                        0 alive / 1 dead
#   lr-recon-fence.sh live                                             0 recon.on + fresh heartbeat / 1
# Sourced callers use lr_recon_may_act <sid> <role> [always] / lr_recon_act_done (W4, below).

_lr_recon_state_dir() {
  printf '%s' "${LR_STATE_DIR:-${HOME}/.reso/limit-recover}"
}

_lr_recon_root() {
  printf '%s' "${LR_RECON_ROOT:-$(_lr_recon_state_dir)/recon}"
}

# Trim leading/trailing blanks (ps pads LSTART with trailing spaces).
_lr_recon_trim() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# The contract lstart form: runs of spaces collapsed to one, then trimmed ("Sep  9" → "Sep 9"),
# the way observe.py renders it. Applied to BOTH sides of every comparison.
_lr_recon_lstart_norm() {
  _lr_recon_trim "$(printf '%s' "$1" | tr -s ' ')"
}

_lr_recon_is_num() {
  case "$1" in
    ''|*[!0-9.]*|*.*.*|.) return 1 ;;
  esac
  return 0
}

# The process's LSTART under TZ=UTC LC_ALL=C in the collapsed ProcId form; empty if gone.
_lr_recon_lstart_of() {
  _lr_recon_lstart_norm "$(TZ=UTC LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null)"
}

# §10 #12: liveness is exact — same pid AND same start time AND not a zombie.
lr_recon_proc_alive() {
  local pid="$1" want cur stat
  case "$pid" in ''|*[!0-9]*|0) return 1 ;; esac
  want="$(_lr_recon_lstart_norm "$2")"
  [ -n "$want" ] || return 1
  cur="$(_lr_recon_lstart_of "$pid")"
  [ -n "$cur" ] && [ "$cur" = "$want" ] || return 1
  stat="$(_lr_recon_trim "$(ps -o stat= -p "$pid" 2>/dev/null)")"
  [ -n "$stat" ] || return 1
  case "$stat" in Z*) return 1 ;; esac
  return 0
}

_lr_recon_now() {
  if _lr_recon_is_num "${LR_RECON_NOW:-}"; then
    printf '%s' "$LR_RECON_NOW"
  else
    date +%s
  fi
}

# kern.waketime reads `{ sec = N, usec = M } Sun Sep 27 18:32:27 2026`; unreadable ⇒ 0.
_lr_recon_waketime() {
  local raw sec
  if _lr_recon_is_num "${LR_RECON_WAKETIME:-}"; then
    printf '%s' "$LR_RECON_WAKETIME"
    return 0
  fi
  raw="$(sysctl -n kern.waketime 2>/dev/null)"
  sec="$(printf '%s' "$raw" | sed -n 's/^{ *sec *= *\([0-9][0-9]*\).*/\1/p')"
  printf '%s' "${sec:-0}"
}

# Parse a compact owned/<sid> file. Prints `R\t<record_id>` then one `P\t<role>\t<pid>\t<lstart>`
# per proc, in order; prints `E` (and nothing else) when the file is not the compact shape.
_lr_recon_parse_owned() {
  tr -d '\r\n' <"$1" 2>/dev/null | awk '
    function str(obj, key,   m) {
      if (match(obj, "\"" key "\":\"[^\"]*\"")) {
        m = substr(obj, RSTART + length(key) + 4, RLENGTH - length(key) - 5)
        return m
      }
      return "\001"
    }
    {
      s = $0
      rid = str(s, "record_id")
      if (rid == "\001" || rid == "") { print "E"; exit }
      i = index(s, "\"procs\":[")
      if (i == 0) { print "E"; exit }
      rest = substr(s, i + 9)
      n = 0
      while (substr(rest, 1, 1) == "{") {
        j = index(rest, "}")
        if (j == 0) { print "E"; exit }
        obj = substr(rest, 1, j)
        rest = substr(rest, j + 1)
        if (!match(obj, /"pid":[0-9]+[,}]/)) { print "E"; exit }
        pid = substr(obj, RSTART + 6, RLENGTH - 7)
        ls = str(obj, "lstart")
        if (ls == "\001") { print "E"; exit }
        role = str(obj, "role")
        if (role == "\001") role = ""
        out[++n] = "P\t" role "\t" pid "\t" ls
        c = substr(rest, 1, 1)
        if (c == ",") rest = substr(rest, 2)
        else if (c != "]") { print "E"; exit }
      }
      if (substr(rest, 1, 1) != "]") { print "E"; exit }
      print "R\t" rid
      for (k = 1; k <= n; k++) print out[k]
      done = 1
      exit
    }
    END { if (!done && NR == 0) print "E" }
  '
}

# Prints progress_wall from the heartbeat, or nothing if the heartbeat is unreadable.
_lr_recon_progress_wall() {
  [ -f "$1" ] || return 0
  tr -d '\r\n' <"$1" 2>/dev/null | awk '
    { if (match($0, /"progress_wall":-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?[,}]/))
        print substr($0, RSTART + 16, RLENGTH - 17) }'
}

_lr_recon_verdict() {
  # $1 defer|act  $2 sid  $3 reason
  printf 'lr-recon-fence: verdict=%s sid=%s reason=%s\n' "$1" "$(printf '%s' "$2" | cut -c1-8)" "$3" >&2
}

lr_recon_defers() {
  local sid="$1" state root owned parsed tag a b c rid pw now wake fresh
  state="$(_lr_recon_state_dir)"
  root="$(_lr_recon_root)"
  if [ ! -e "$state/recon.on" ]; then
    _lr_recon_verdict act "$sid" "recon-off"; return 1
  fi
  owned="$root/owned/$sid"
  case "$sid" in ''|*/*) owned="" ;; esac
  if [ -z "$owned" ] || [ ! -f "$owned" ]; then
    _lr_recon_verdict act "$sid" "not-owned"; return 1
  fi
  parsed="$(_lr_recon_parse_owned "$owned")"
  rid="$(printf '%s\n' "$parsed" | sed -n 's/^R	//p')"
  if [ -z "$rid" ]; then
    _lr_recon_verdict defer "$sid" "owned-unreadable"; return 0
  fi
  if [ -n "${LR_RECORD_ID:-}" ] && [ "$LR_RECORD_ID" = "$rid" ]; then
    _lr_recon_verdict act "$sid" "own-actuator"; return 1
  fi
  pw="$(_lr_recon_progress_wall "$root/heartbeat")"
  if [ -n "$pw" ]; then
    now="$(_lr_recon_now)"
    wake="$(_lr_recon_waketime)"
    fresh="${LR_RECON_FENCE_FRESH_S:-180}"
    _lr_recon_is_num "$fresh" || fresh=180
    if awk -v n="$now" -v p="$pw" -v w="$wake" -v f="$fresh" \
      'BEGIN { base = (p + 0 > w + 0) ? p + 0 : w + 0; exit !((n + 0) - base <= f + 0) }'; then
      _lr_recon_verdict defer "$sid" "heartbeat-fresh"; return 0
    fi
  fi
  while IFS='	' read -r tag a b c; do
    [ "$tag" = "P" ] || continue
    if lr_recon_proc_alive "$b" "$c"; then
      _lr_recon_verdict defer "$sid" "proc-alive:${a}:${b}"; return 0
    fi
  done <<EOF
$parsed
EOF
  _lr_recon_verdict act "$sid" "lapsed"
  return 1
}

# ── §C7 lock pattern: mkdir; write holder; work; rm -rf. A taker that finds the holder's exact
# (pid, lstart) dead steals at once. A lock dir with NO readable holder (a taker died between
# mkdir and the holder write) is stolen only after LR_RECON_LOCK_GRACE_S (30) of dir age, so a
# taker mid-write is never robbed. ─────────────────────────────────────────────────────────────

_lr_recon_holder_raw() {
  [ -f "$1/holder" ] || return 0
  tr -d '\r\n' <"$1/holder" 2>/dev/null
}

_lr_recon_holder_field() {
  # $1 raw holder, $2 pid|lstart
  case "$2" in
    pid) printf '%s' "$1" | sed -n 's/.*"pid":\([0-9][0-9]*\)[,}].*/\1/p' ;;
    lstart) printf '%s' "$1" | sed -n 's/.*"lstart":"\([^"]*\)".*/\1/p' ;;
  esac
}

_lr_recon_dir_age() {
  local m
  m="$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null)"
  _lr_recon_is_num "$m" || { printf '0'; return 0; }
  printf '%s' "$(( $(date +%s) - m ))"
}

# True when the lock at $1, whose holder reads $2, is provably abandoned.
_lr_recon_holder_dead() {
  local raw="$1" dir="$2" hp hl grace
  hp="$(_lr_recon_holder_field "$raw" pid)"
  hl="$(_lr_recon_holder_field "$raw" lstart)"
  if [ -n "$hp" ] && [ -n "$hl" ]; then
    lr_recon_proc_alive "$hp" "$hl" && return 1
    return 0
  fi
  grace="${LR_RECON_LOCK_GRACE_S:-30}"
  _lr_recon_is_num "$grace" || grace=30
  [ "$(_lr_recon_dir_age "$dir")" -ge "${grace%%.*}" ]
}

_lr_recon_json_safe() {
  case "$1" in *'"'*|*\\*) return 1 ;; esac
  [ "$(printf '%s' "$1" | tr -d '[:cntrl:]')" = "$1" ]
}

lr_recon_lock_take() {
  local dir="$1" rid="$2" attempt="$3" role="$4" pid="${5:-$$}" ls tmp raw tomb try=0
  [ -n "$dir" ] || return 2
  case "$attempt" in ''|*[!0-9]*) return 2 ;; esac
  case "$pid" in ''|*[!0-9]*) return 2 ;; esac
  _lr_recon_json_safe "$rid" && _lr_recon_json_safe "$role" || return 2
  ls="$(_lr_recon_lstart_of "$pid")"
  [ -n "$ls" ] || return 2
  mkdir -p "$(dirname "$dir")" 2>/dev/null
  while [ "$try" -lt 3 ]; do
    try=$((try + 1))
    if mkdir "$dir" 2>/dev/null; then
      tmp="$dir.holder.tmp.$$.$RANDOM"
      printf '{"record_id":"%s","attempt":%s,"role":"%s","pid":%s,"lstart":"%s","at":%s.0}\n' \
        "$rid" "$attempt" "$role" "$pid" "$ls" "$(date +%s)" >"$tmp" 2>/dev/null \
        && mv -f "$tmp" "$dir/holder" 2>/dev/null && return 0
      rm -f "$tmp" 2>/dev/null
      return 2
    fi
    [ -d "$dir" ] || return 2
    raw="$(_lr_recon_holder_raw "$dir")"
    _lr_recon_holder_dead "$raw" "$dir" || return 1
    # Steal: rename away, then verify the tomb holds the SAME holder we judged dead; a different
    # one means a racing taker got there first and we must give its lock back.
    tomb="$dir.stolen.$$.$RANDOM"
    mv "$dir" "$tomb" 2>/dev/null || continue
    if [ "$(_lr_recon_holder_raw "$tomb")" != "$raw" ]; then
      [ -e "$dir" ] || mv "$tomb" "$dir" 2>/dev/null
      return 1
    fi
    rm -rf "$tomb"
  done
  return 1
}

lr_recon_lock_release() {
  local dir="$1" pid="${2:-$$}" raw hp hl cur
  [ -d "$dir" ] || return 1
  raw="$(_lr_recon_holder_raw "$dir")"
  hp="$(_lr_recon_holder_field "$raw" pid)"
  [ -n "$hp" ] && [ "$hp" = "$pid" ] || return 1
  hl="$(_lr_recon_holder_field "$raw" lstart)"
  cur="$(_lr_recon_lstart_of "$pid")"
  hl="$(_lr_recon_lstart_norm "$hl")"
  if [ -n "$hl" ] && [ -n "$cur" ] && [ "$hl" != "$cur" ]; then
    return 1
  fi
  rm -rf "$dir"
}

# ── W4 caller helpers: the ONE way a legacy actor asks the fence and takes the launch lock ─────────
# Every call site (poller arms, lf_one, the lr-upgrade drives, cc-lr, cc-resume-debt,
# boot-resume-launch) goes through lr_recon_may_act, so "lapsed ⇒ act only under the launch lock"
# is one implementation and not seven.

# rc 0 when recon.on exists AND the heartbeat's progress advanced within the fresh window
# (sleep-adjusted, the same rule as lr_recon_defers step 4); rc 1 otherwise. No verdict line.
lr_recon_live() {
  local root pw now wake fresh
  [ -e "$(_lr_recon_state_dir)/recon.on" ] || return 1
  root="$(_lr_recon_root)"
  pw="$(_lr_recon_progress_wall "$root/heartbeat")"
  [ -n "$pw" ] || return 1
  now="$(_lr_recon_now)"
  wake="$(_lr_recon_waketime)"
  fresh="${LR_RECON_FENCE_FRESH_S:-180}"
  _lr_recon_is_num "$fresh" || fresh=180
  awk -v n="$now" -v p="$pw" -v w="$wake" -v f="$fresh" \
    'BEGIN { base = (p + 0 > w + 0) ? p + 0 : w + 0; exit !((n + 0) - base <= f + 0) }'
}

_lr_recon_launch_lock_dir() {
  printf '%s/locks/%s.launch' "$(_lr_recon_state_dir)" "$1"
}

# One line per typer acquisition in recon/launch.log — the double-typer audit (§C7). Best effort.
_lr_recon_launch_log() {
  # $1 sid $2 role $3 verdict
  local root
  root="$(_lr_recon_root)"
  [ -d "$root" ] || return 0
  # An actuator the reconciler spawned carries its record and attempt in the env (lr_recon act.py);
  # the audit keys a take on them. A legacy actor has neither and is its own key.
  printf '%s\t%s\t%s\t%s\tpid=%s%s%s\n' "$(date +%s)" "$1" "$2" "$3" "$$" \
    "${LR_ATTEMPT:+	attempt=$LR_ATTEMPT}" "${LR_RECORD_ID:+	record=$LR_RECORD_ID}" \
    >>"$root/launch.log" 2>/dev/null
  return 0
}

# lr_recon_may_act <sid> <role> [always]  → rc 0 ACT · rc 1 DEFER (the caller must not touch the sid)
# ACT after a "lapsed" verdict — and after ANY act verdict when "always" is passed (the relaunch
# typers: cc-resume-debt, boot-resume-launch) — happens only while this process holds
# locks/<sid>.launch; its path is exported in LR_LAUNCH_LOCK (lr-fire-resume asserts it) and the
# caller releases it with lr_recon_act_done. Otherwise LR_LAUNCH_LOCK is exported empty. A child
# that inherits a LIVE LR_LAUNCH_LOCK for the same sid acts under it (lock=inherited) and never
# releases it — the parent that took it does.
# A launch lock held by a LIVE other process ⇒ DEFER. A lock that cannot be created: DEFER on
# "lapsed" (the reconciler may still own the sid), ACT unlocked on "always" with the reconciler off
# (the legacy world keeps working). Verdict: `lr-recon-fence: gate=act|defer sid=… role=… lock=…`.
lr_recon_may_act() {
  local sid="$1" role="${2:-legacy}" always="${3:-}" why dir rc inherited=""
  dir="$(_lr_recon_launch_lock_dir "$sid")"
  # INHERITED: a parent actor (cc-lr → lf_one → lr-handoff) already holds this sid's launch lock
  # and exported it. Its live holder is the one legitimate "someone else holds it" — re-taking it
  # would make the child defer to its own parent. Never released by the child (see act_done).
  if [ -n "${LR_LAUNCH_LOCK:-}" ] && [ "$LR_LAUNCH_LOCK" = "$dir" ] \
    && ! _lr_recon_holder_dead "$(_lr_recon_holder_raw "$dir")" "$dir"; then
    inherited=1
  fi
  _LR_RECON_LOCK_MINE=""
  LR_LAUNCH_LOCK=""
  export LR_LAUNCH_LOCK
  why="$(lr_recon_defers "$sid" 2>&1 >/dev/null)"
  rc=$?
  [ -n "$why" ] && printf '%s\n' "$why" >&2
  if [ "$rc" -eq 0 ]; then
    printf 'lr-recon-fence: gate=defer sid=%s role=%s lock=none\n' "$(printf '%s' "$sid" | cut -c1-8)" "$role" >&2
    return 1
  fi
  case "$why" in
    *reason=lapsed*) ;;
    *) [ "$always" = always ] || { printf 'lr-recon-fence: gate=act sid=%s role=%s lock=none\n' \
         "$(printf '%s' "$sid" | cut -c1-8)" "$role" >&2; return 0; } ;;
  esac
  if [ -n "$inherited" ]; then
    LR_LAUNCH_LOCK="$dir"
    export LR_LAUNCH_LOCK
    _lr_recon_launch_log "$sid" "$role" inherited
    printf 'lr-recon-fence: gate=act sid=%s role=%s lock=inherited\n' "$(printf '%s' "$sid" | cut -c1-8)" "$role" >&2
    return 0
  fi
  lr_recon_lock_take "$dir" "legacy:$role" 0 "$role" "$$"
  rc=$?
  case "$rc" in
    0)
      LR_LAUNCH_LOCK="$dir"
      _LR_RECON_LOCK_MINE=1
      export LR_LAUNCH_LOCK
      _lr_recon_launch_log "$sid" "$role" taken
      printf 'lr-recon-fence: gate=act sid=%s role=%s lock=taken\n' "$(printf '%s' "$sid" | cut -c1-8)" "$role" >&2
      return 0 ;;
    1)
      _lr_recon_launch_log "$sid" "$role" held
      printf 'lr-recon-fence: gate=defer sid=%s role=%s lock=held\n' "$(printf '%s' "$sid" | cut -c1-8)" "$role" >&2
      return 1 ;;
  esac
  case "$why" in
    *reason=lapsed*)
      printf 'lr-recon-fence: gate=defer sid=%s role=%s lock=cannot\n' "$(printf '%s' "$sid" | cut -c1-8)" "$role" >&2
      return 1 ;;
  esac
  printf 'lr-recon-fence: gate=act sid=%s role=%s lock=cannot\n' "$(printf '%s' "$sid" | cut -c1-8)" "$role" >&2
  return 0
}

# Release the launch lock lr_recon_may_act took (a no-op when it took none). Safe to repeat.
lr_recon_act_done() {
  [ -n "${LR_LAUNCH_LOCK:-}" ] || return 0
  [ "${_LR_RECON_LOCK_MINE:-}" = 1 ] && lr_recon_lock_release "$LR_LAUNCH_LOCK" "$$" 2>/dev/null
  _LR_RECON_LOCK_MINE=""
  LR_LAUNCH_LOCK=""
  export LR_LAUNCH_LOCK
  return 0
}

_lr_recon_fence_main() {
  local cmd="${1:-}"
  [ $# -gt 0 ] && shift
  case "$cmd" in
    defers)
      [ $# -eq 1 ] || { echo "usage: lr-recon-fence.sh defers <sid>" >&2; return 2; }
      lr_recon_defers "$1" ;;
    lock-take)
      [ $# -ge 4 ] || { echo "usage: lr-recon-fence.sh lock-take <dir> <record_id> <attempt> <role> [pid]" >&2; return 2; }
      lr_recon_lock_take "$@" ;;
    lock-release)
      [ $# -ge 1 ] || { echo "usage: lr-recon-fence.sh lock-release <dir> [pid]" >&2; return 2; }
      lr_recon_lock_release "$@" ;;
    live)
      lr_recon_live ;;
    proc-alive)
      [ $# -eq 2 ] || { echo "usage: lr-recon-fence.sh proc-alive <pid> <lstart>" >&2; return 2; }
      lr_recon_proc_alive "$@" ;;
    *)
      echo "usage: lr-recon-fence.sh defers|lock-take|lock-release|proc-alive|live …" >&2
      return 2 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  _lr_recon_fence_main "$@"
  exit $?
fi
