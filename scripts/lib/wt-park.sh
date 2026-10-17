# shellcheck shell=bash
# shellcheck disable=SC2034  # WT_R_* row fields are read by wt__row_emit through eval
# wt-park.sh — PARK / unpark and the pin predicate (DESIGN load-root-cause-2026-10-17 §3.2, §3.5; WP-9b).
#
# Sourced by wt-tombstone.sh at its tail, never on its own: it uses that file's helpers (wt__err,
# wt__now, wt__sids_of, wt__row_emit, …). bash 3.2 safe. Contract: W2-CONTRACT.md "PARK + pins".

[ -n "${_WT_PARK_SH:-}" ] && return 0
_WT_PARK_SH=1

WT_CRASH_LOG="${WT_CRASH_LOG:-$HOME/.claude/logs/claude-crashes.jsonl}"
WT_RESUME_DEBT_DIR="${WT_RESUME_DEBT_DIR:-$HOME/.claude/autonomy/resume-debt}"
WT_LR_DIR="${WT_LR_DIR:-$HOME/.reso/limit-recover}"
WT_RECYCLE_FAILED_DIR="${WT_RECYCLE_FAILED_DIR:-$HOME/.claude/autonomy/recycle-failed}"
WT_BOOT_RESUME_DIR="${WT_BOOT_RESUME_DIR:-$HOME/.claude/autonomy/boot-resume/events}"
WT_BACKLOG="${WT_BACKLOG:-$HOME/.claude/autonomy/backlog.jsonl}"

wt__park_path() { # <path> → absolute path with a canonical parent; works whether or not <path> exists
  # The index is keyed by sha1(path) and the path is GONE at unpark, so canonicalise the parent only:
  # park and unpark must hash the same string (/var vs /private/var on macOS).
  local p="${1%/}" d
  d="$(wt__canon "$(dirname "$p")")"
  printf '%s/%s' "${d%/}" "$(basename "$p")"
}

wt__mtime() { stat -f %m "$1" 2>/dev/null; }

wt__size() { stat -f %z "$1" 2>/dev/null; }

wt__path_re() { # <path> → ERE matching the path as a whole path token (itself or under it, never a sibling /x/wt-a-b)
  printf '(^|[^A-Za-z0-9._/-])%s([^A-Za-z0-9._-]|$)' "$(printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g')"
}

wt__idx_get() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1; }   # <index-file> <key>

# ---- PARK / unpark -------------------------------------------------------------------------------

wt__park_undo() { # <repo> <parked> <path> <branch> → best-effort return of a half-parked tree; always rc 2
  [ -n "$4" ] && "$WT_GIT" -C "$2" checkout -q "$4" 2>/dev/null
  "$WT_GIT" -C "$1" worktree unlock "$2" 2>/dev/null
  "$WT_GIT" -C "$1" worktree move "$2" "$3" 2>/dev/null || wt__err "UNDO FAILED: tree left at $2 (was $3)"
  return 2
}

wt_park() { # <path> <actor> <reason> --arm i|ii → prints the parked path
  # PARK is the lossless quiescent action: one same-volume rename, one lock, one index entry and a row.
  # Nothing is deleted. Arm (i) detaches HEAD so a landed branch stays deletable; arm (ii) stays attached
  # so git keeps refusing `branch -D` of unlanded work. Any failure after the move moves it back.
  [ $# -ge 5 ] && [ "$4" = --arm ] || { wt__err "usage: wt_park <path> <actor> <reason> --arm i|ii"; return 2; }
  local path actor="$2" reason="$3" arm="$5" repo id parked head branch="" sids ts key idx tmp lb="" lp=""
  case "$arm" in i|ii) ;; *) wt__err "bad --arm $arm"; return 2 ;; esac
  [ -d "$1" ] || { wt__err "$1 is not a directory"; return 2; }
  path="$(wt__park_path "$1")"
  repo="$(wt__repo_of "$path")" || { wt__err "$path is not in a git repository"; return 2; }
  [ "$(wt__canon "$repo")" != "$(wt__canon "$path")" ] || { wt__err "$path is the main worktree; only linked trees park"; return 2; }
  ( umask 077; mkdir -p "$WT_PARK_ROOT" "$WT_PARK_INDEX" ) || { wt__err "cannot create $WT_PARK_ROOT"; return 2; }
  [ "$(stat -f %d "$path")" = "$(stat -f %d "$WT_PARK_ROOT")" ] \
    || { wt__err "$path and $WT_PARK_ROOT are on different volumes; PARK is a rename only"; return 2; }
  id="$(wt__id_new "$path")"; parked="$WT_PARK_ROOT/$id"
  [ ! -e "$parked" ] || { wt__err "park target $parked already exists"; return 2; }
  head="$("$WT_GIT" -C "$path" rev-parse --verify -q HEAD 2>/dev/null)"
  [ "$arm" = i ] && branch="$("$WT_GIT" -C "$path" symbolic-ref -q --short HEAD 2>/dev/null)"
  sids="$(wt__sids_of "$path")"; ts="$(wt__ts)"
  "$WT_GIT" -C "$repo" worktree move "$path" "$parked" 2>/dev/null || { wt__err "worktree move $path failed — tree kept"; return 2; }
  "$WT_GIT" -C "$repo" worktree lock --reason "parked $ts from $path sids=$(printf '%s\n' "$sids" | paste -sd, -)" "$parked" 2>/dev/null \
    || { wt__err "lock of $parked failed"; wt__park_undo "$repo" "$parked" "$path" ""; return 2; }
  if [ -n "$branch" ]; then
    lb="$(wt__size "$("$WT_GIT" -C "$parked" rev-parse --absolute-git-dir)/logs/HEAD")"
    "$WT_GIT" -C "$parked" checkout -q --detach 2>/dev/null \
      || { wt__err "detach of $parked failed"; wt__park_undo "$repo" "$parked" "$path" ""; return 2; }
    lp="$(wt__size "$("$WT_GIT" -C "$parked" rev-parse --absolute-git-dir)/logs/HEAD")"
  fi
  key="$(wt__sha1 "$path")"; idx="$WT_PARK_INDEX/$key"
  tmp="$(mktemp "$WT_PARK_INDEX/.$key.XXXXXX")" \
    && printf 'path=%s\nrepo=%s\nparked=%s\nbranch=%s\nbranch_tip=%s\nts=%s\nid=%s\nsids=%s\nlogs_len=%s\nlogs_len_parked=%s\n' \
         "$path" "$repo" "$parked" "$branch" "${branch:+$head}" "$ts" "$id" "$(printf '%s\n' "$sids" | paste -sd, -)" "$lb" "$lp" > "$tmp" \
    && chmod 600 "$tmp" && mv -f "$tmp" "$idx" \
    || { rm -f "$tmp"; wt__err "index write failed"; wt__park_undo "$repo" "$parked" "$path" "$branch"; return 2; }
  wt__row_reset
  WT_R_event=worktree-parked; WT_R_id="$id"; WT_R_actor="$actor"; WT_R_reason="$reason"; WT_R_repo="$repo"
  WT_R_path="$path"; WT_R_branch="$("$WT_GIT" -C "$parked" symbolic-ref -q --short HEAD 2>/dev/null)"
  WT_R_branch="${WT_R_branch:-$branch}"; WT_R_head="$head"; WT_R_mode=none; WT_R_parked_path="$parked"
  WT_R_branch_tip="${branch:+$head}"; WT_R_sids="$sids"; WT_R_preserved_at="$parked"
  wt__row_emit || { rm -f "$idx"; wt__err "ledger write failed — park undone"; wt__park_undo "$repo" "$parked" "$path" "$branch"; return 2; }
  printf '%s\n' "$parked"
}

wt_parked_lookup() { # <path> → "<repo>\t<parked>"; rc 1 if not parked
  local idx; idx="$WT_PARK_INDEX/$(wt__sha1 "$(wt__park_path "$1")")"
  [ -f "$idx" ] || return 1
  printf '%s\t%s\n' "$(wt__idx_get "$idx" repo)" "$(wt__idx_get "$idx" parked)"
}

wt__husk() { # <dir> → rc 0 iff a NOGIT husk: every top-level entry is .claude-* or .next (empty counts)
  local e
  [ -d "$1" ] && [ ! -e "$1/.git" ] || return 1
  for e in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    case "$(basename "$e")" in .claude-*|.next) ;; *) return 1 ;; esac
  done
  return 0
}

wt_unpark() { # <path> → moves a parked tree back to its exact path; rc 1 not parked, rc 2 refused
  # Path-match, no sid: it restores the very tree that stood here, so it is lossless (§3.5 item 2).
  local path idx repo parked branch tip head husk="" gd lb lp why=""
  path="$(wt__park_path "$1")"; idx="$WT_PARK_INDEX/$(wt__sha1 "$path")"
  [ -f "$idx" ] || return 1
  repo="$(wt__idx_get "$idx" repo)"; parked="$(wt__idx_get "$idx" parked)"
  branch="$(wt__idx_get "$idx" branch)"; tip="$(wt__idx_get "$idx" branch_tip)"
  lb="$(wt__idx_get "$idx" logs_len)"; lp="$(wt__idx_get "$idx" logs_len_parked)"
  [ -d "$parked" ] || { wt__err "parked tree $parked is missing; index $idx left for a human"; return 2; }
  if [ -e "$path" ] || [ -L "$path" ]; then
    wt__husk "$path" || { wt__err "$path is occupied by more than a .claude-*/.next husk — not unparked"; return 2; }
    husk="$path.husk-$(wt__now)"
    mv "$path" "$husk" || { wt__err "cannot move husk $path aside"; return 2; }
  fi
  "$WT_GIT" -C "$repo" worktree unlock "$parked" 2>/dev/null
  if ! "$WT_GIT" -C "$repo" worktree move "$parked" "$path" 2>/dev/null; then
    "$WT_GIT" -C "$repo" worktree lock --reason "parked $(wt__idx_get "$idx" ts) from $path sids=$(wt__idx_get "$idx" sids)" "$parked" 2>/dev/null
    [ -n "$husk" ] && mv "$husk" "$path"
    wt__err "worktree move $parked → $path failed; still parked"; return 2
  fi
  head="$("$WT_GIT" -C "$path" rev-parse --verify -q HEAD 2>/dev/null)"
  if [ -n "$branch" ]; then
    gd="$("$WT_GIT" -C "$path" rev-parse --absolute-git-dir 2>/dev/null)"
    if ! "$WT_GIT" -C "$path" rev-parse --verify -q "refs/heads/$branch" >/dev/null 2>&1; then why="branch-gone"
    elif "$WT_GIT" -C "$repo" worktree list --porcelain 2>/dev/null | grep -qxF "branch refs/heads/$branch"; then why="checked-out-elsewhere"
    elif [ "$("$WT_GIT" -C "$path" rev-parse "refs/heads/$branch")" != "$head" ]; then why="tip-moved"
    elif ! "$WT_GIT" -C "$path" checkout -q "$branch" 2>/dev/null; then why="checkout-failed"
    elif [ -n "$lb" ] && [ "$(wt__size "$gd/logs/HEAD")" -gt "${lp:-0}" ] 2>/dev/null; then
      # Drop exactly park's detach + this re-attach, and only when nothing else logged while parked
      # (size was lp after the detach; one more entry since is ours), so the reflog reads as before.
      if [ "$(head -c "$lp" "$gd/logs/HEAD" | wc -l)" -eq "$(( $(head -c "$lb" "$gd/logs/HEAD" | wc -l) + 1 ))" ] \
         && [ "$(wc -l < "$gd/logs/HEAD")" -eq "$(( $(head -c "$lp" "$gd/logs/HEAD" | wc -l) + 1 ))" ]; then
        head -c "$lb" "$gd/logs/HEAD" > "$gd/logs/HEAD.wt-park" && mv -f "$gd/logs/HEAD.wt-park" "$gd/logs/HEAD"
      fi
    fi
    [ -z "$why" ] || wt__err "reattach=skipped:$why ($path stays detached at ${head:-?}; branch $branch)"
  fi
  wt__row_reset
  WT_R_id="$(wt__idx_get "$idx" id)"
  rm -f "$idx"
  WT_R_event=worktree-unparked; WT_R_actor="${WT_ACTOR:-wt_unpark}"
  WT_R_reason="${why:+reattach=skipped:$why}"; WT_R_repo="$repo"; WT_R_path="$path"; WT_R_parked_path="$parked"
  WT_R_branch="$branch"; WT_R_branch_tip="$tip"; WT_R_head="$head"; WT_R_mode=none
  wt__row_emit || wt__err "unparked $path but the ledger write failed"
  return 0
}

# ---- activity legs ------------------------------------------------------------------------------

wt_newest_transcript_mtime() { # <path> → newest transcript mtime (epoch) for this cwd; empty + rc 1 = unknown, not old
  local d m="" t
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    t="$(find "$d" -type f -name '*.jsonl' -exec stat -f %m {} + 2>/dev/null | sort -n | tail -1)"
    [ -n "$t" ] && { [ -z "$m" ] || [ "$t" -gt "$m" ]; } && m="$t"
  done <<EOF
$(wt__transcript_dirs_of "$(wt__park_path "$1")")
EOF
  [ -n "$m" ] || return 1
  printf '%s\n' "$m"
}

wt_recent_file() { # <path> <days> → rc 0 iff a working-tree file (not under .git) changed within <days>
  [ -n "$(find "$1" -name .git -prune -o -mtime -"$2" -print -quit 2>/dev/null)" ]
}

# ---- pins -----------------------------------------------------------------------------------------

wt__pin_crash() { # <path> <sids> → "sid=<s> until=<epoch>" for a CRASH ≤7 d with no later transcript write
  local now cut ts sid ep f m newest
  [ -n "$2" ] && [ -f "$WT_CRASH_LOG" ] || return 1
  now="$(wt__now)"; cut="$(date -u -r $((now - 604800)) +%Y-%m-%dT%H:%M:%SZ)"
  while IFS=' ' read -r ts sid; do
    [ -n "$sid" ] && [ "$ts" \> "$cut" ] || continue
    printf '%s\n' "$2" | grep -qxF "$sid" || continue
    ep="$(wt__epoch_of_ts "$ts")"; [ -n "$ep" ] || continue
    newest=0
    while IFS= read -r f; do
      [ -n "$f" ] && [ -f "$f/$sid.jsonl" ] || continue
      m="$(wt__mtime "$f/$sid.jsonl")"; [ "${m:-0}" -gt "$newest" ] && newest="$m"
    done <<EOF
$(wt__transcript_dirs_of "$1")
EOF
    [ "$newest" -gt $((ep + 60)) ] && continue   # resumed after the crash: a later SessionStart wrote
    printf 'sid=%s until=%s\n' "$sid" $((ep + 604800)); return 0
  done <<EOF
$(tail -n "${WT_CRASH_TAIL_N:-5000}" "$WT_CRASH_LOG" 2>/dev/null | grep '"class":"CRASH"' \
  | sed -n 's/.*"ts":"\([^"]*\)".*"sid":"\([^"]*\)".*/\1 \2/p' | sort -r)
EOF
  return 1
}

wt__pin_resume_debt() { # <path> <ttl-s> → open custody/resume debt whose cwd is this path (cc-custody's fold)
  local files row
  [ -d "$WT_RESUME_DEBT_DIR" ] || return 1
  files="$(grep -lE "$(wt__path_re "$1")" "$WT_RESUME_DEBT_DIR"/*.jsonl 2>/dev/null)"
  [ -n "$files" ] || return 1
  # shellcheck disable=SC2086  # one file per word: the store's names are hex digests
  row="$(jq -rn --arg p "$1" '[inputs]
      | map(. + {k: (if (.marker // "") != "" then ("m:"+.marker) else ("s:"+(.slug//"")+"|"+(.targetPane//"")) end)})
      | group_by(.k) | map(sort_by(.ts) | last) | map(select(.kind == "open"))
      | map(select(.cwd == $p or ((.cwd // "") | startswith($p + "/")))) | sort_by(.ts) | last // empty
      | "\(.slug // "-") \(.ts)"' $files 2>/dev/null)"
  [ -n "$row" ] || return 1
  printf 'sid=%s until=%s\n' "${row%% *}" $(( $(wt__epoch_of_ts "${row#* }" || echo 0) + $2 ))
}

wt__pin_lr() { # <sids> <ttl-s> → a limit-recover dir for a sid whose resume is not proven ("Resumed in place" receipt)
  local sid m r proven
  while IFS= read -r sid; do
    [ -n "$sid" ] && [ -d "$WT_LR_DIR/$sid" ] || continue
    m="$(wt__mtime "$WT_LR_DIR/$sid")"; [ $((m + $2)) -gt "$(wt__now)" ] || continue
    proven=0
    for r in "$WT_LR_DIR/$sid"/bundle-*/INGEST-VERIFIED.txt; do
      [ -f "$r" ] && case "$(tail -1 "$r")" in 'Resumed in place'*) proven=1 ;; esac
    done
    [ "$proven" = 1 ] && continue
    printf 'sid=%s until=%s\n' "$sid" $((m + $2)); return 0
  done <<EOF
$1
EOF
  return 1
}

wt__pin_recycle_failed() { # <sids> <ttl-s> → a recycle-failed packet for one of the sids
  local sid m
  while IFS= read -r sid; do
    [ -n "$sid" ] && [ -f "$WT_RECYCLE_FAILED_DIR/$sid.json" ] || continue
    m="$(wt__mtime "$WT_RECYCLE_FAILED_DIR/$sid.json")"; [ $((m + $2)) -gt "$(wt__now)" ] || continue
    printf 'sid=%s until=%s\n' "$sid" $((m + $2)); return 0
  done <<EOF
$1
EOF
  return 1
}

wt__pin_boot_resume() { # <path> <ttl-s> → a boot-resume event naming the path with no <id>.done
  local e m re
  [ -d "$WT_BOOT_RESUME_DIR" ] || return 1
  re="$(wt__path_re "$1")"
  for e in "$WT_BOOT_RESUME_DIR"/*; do
    case "$e" in *.done|*.planned|*.tmp) continue ;; esac
    [ -e "$e.done" ] && continue
    m="$(wt__mtime "$e")"; [ $((m + $2)) -gt "$(wt__now)" ] || continue
    grep -rqsE "$re" "$e" || continue
    printf 'sid=- until=%s event=%s\n' $((m + $2)) "$(basename "$e")"; return 0
  done
  return 1
}

wt__pin_backlog() { # <path> <ttl-s> → an open backlog row (latest event not done/falsify) naming the path
  local id last ev ts
  [ -f "$WT_BACKLOG" ] || return 1
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    last="$(grep -F "\"id\":\"$id\"" "$WT_BACKLOG" | tail -1 | jq -r '"\(.event // "") \(.ts // "")"' 2>/dev/null)"
    ev="${last%% *}"; ts="${last#* }"
    case "$ev" in done|falsify|close|closed|drop) continue ;; esac
    ts="$(wt__epoch_of_ts "$ts")"; [ -n "$ts" ] && [ $((ts + $2)) -gt "$(wt__now)" ] || continue
    printf 'sid=- until=%s id=%s\n' $((ts + $2)) "$id"; return 0
  done <<EOF
$(grep -E "$(wt__path_re "$1")" "$WT_BACKLOG" 2>/dev/null | jq -r '.id // empty' 2>/dev/null | sort -u)
EOF
  return 1
}

wt_pinned() { # <path> → rc 0 + "<kind> sid=<sid|-> until=<epoch>[ …]" for the first pin; rc 1 = no pin
  # Every pin is DERIVED from its source store and expires (crash 7 d, others by cleanupPeriodDays), so a
  # pin can never outlive its reason or freeze collection (§3.2 Pins). Bounded reads only.
  local path sids ttl d gd m
  path="$(wt__park_path "$1")"
  sids="$(wt__sids_of "$path")"
  ttl=$(( $(wt_cleanup_period_days) * 86400 ))
  if d="$(wt__pin_crash "$path" "$sids")"; then printf 'crash %s\n' "$d"; return 0; fi
  if d="$(wt__pin_resume_debt "$path" "$ttl")"; then printf 'resume-debt %s\n' "$d"; return 0; fi
  if d="$(wt__pin_lr "$sids" "$ttl")"; then printf 'limit-recover %s\n' "$d"; return 0; fi
  if d="$(wt__pin_recycle_failed "$sids" "$ttl")"; then printf 'recycle-failed %s\n' "$d"; return 0; fi
  if d="$(wt__pin_boot_resume "$path" "$ttl")"; then printf 'boot-resume %s\n' "$d"; return 0; fi
  if d="$(wt__pin_backlog "$path" "$ttl")"; then printf 'backlog %s\n' "$d"; return 0; fi
  gd="$("$WT_GIT" -C "$path" rev-parse --absolute-git-dir 2>/dev/null)"
  m="$(wt__mtime "$gd/logs/HEAD")"
  if [ -n "$gd" ] && [ -n "$m" ] && [ $(( $(wt__now) - m )) -lt 3600 ]; then
    printf 'owner sid=- until=%s\n' $((m + 3600)); return 0
  fi
  return 1
}

wt_pin_lock_sync() { # <repo> [--observe] → lock pinned unlocked trees "cc-pin:…"; unlock cc-pin locks whose pin is gone
  # Materialises the pin as a git lock for removers that never call wt_pinned (a raw `worktree remove`,
  # even with one --force, then refuses). Only cc-pin: locks are ours; a human or `parked` lock is never touched.
  local repo="$1" obs=0 line wt="" first=1 locked reason pin kind until
  [ "${2:-}" = --observe ] && obs=1
  while IFS= read -r line; do
    case "$line" in
      'worktree '*) wt="${line#worktree }"; locked=0; reason="" ;;
      locked) locked=1 ;;
      'locked '*) locked=1; reason="${line#locked }" ;;
      '')
        if [ "$first" = 1 ]; then first=0; continue; fi   # the main worktree is never locked here
        [ -n "$wt" ] && [ -d "$wt" ] || continue
        if [ "$locked" = 1 ]; then
          case "$reason" in cc-pin:*) ;; *) continue ;; esac
          until="$(printf '%s' "$reason" | sed -n 's/.*until=\([0-9]*\).*/\1/p')"
          if [ "${until:-0}" -gt "$(wt__now)" ] && wt_pinned "$wt" >/dev/null; then continue; fi
          if [ "$obs" = 1 ]; then wt__err "would_unlock $wt"; else "$WT_GIT" -C "$repo" worktree unlock "$wt" 2>/dev/null || wt__err "unlock $wt failed"; fi
        elif pin="$(wt_pinned "$wt")"; then
          kind="${pin%% *}"
          if [ "$obs" = 1 ]; then wt__err "would_lock $wt $kind"; continue; fi
          "$WT_GIT" -C "$repo" worktree lock --reason "cc-pin:$kind $(printf '%s' "$pin" | grep -o 'sid=[^ ]*') $(printf '%s' "$pin" | grep -o 'until=[0-9]*')" "$wt" 2>/dev/null \
            || wt__err "lock $wt failed"
        fi ;;
    esac
  done <<EOF
$("$WT_GIT" -C "$repo" worktree list --porcelain 2>/dev/null)

EOF
}
