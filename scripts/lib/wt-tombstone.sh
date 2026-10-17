# shellcheck shell=bash
# shellcheck disable=SC2034  # WT_R_* row fields are read by wt__row_emit through eval
# wt-tombstone.sh — one repo-qualified, reversible record before any automated worktree removal,
# plus PARK / unpark and the pin predicate (DESIGN load-root-cause-2026-10-17 §3, note X6, WP-9).
#
# SOURCE this file; it defines functions only and changes no shell option of its caller. It must run
# under /bin/bash 3.2 (bin/cc-reaper and launchd jobs use it): no associative arrays, no `${x,,}`,
# no `mapfile`, no `case` + `continue` inside `$( )`.
#
# API contract (every caller codes against it): docs/research/load-root-cause-2026-10-17/W2-CONTRACT.md
# The PARK / pin half lives in wt-park.sh beside this file and is sourced at the end.
#
# Every path below has an env override so the §3.7 lab runs in a throwaway HOME, never on real trees.

[ -n "${_WT_TOMBSTONE_SH:-}" ] && return 0
_WT_TOMBSTONE_SH=1

WT_GIT="${WT_GIT:-git}"
WT_LEDGER="${WT_LEDGER:-${CC_WTGC_DISPOSAL_LOG:-$HOME/.claude/autonomy/worktree-disposals.jsonl}}"
WT_TOMB_DIR="${WT_TOMB_DIR:-$HOME/.claude/autonomy/worktree-tombstones}"
WT_STATE_DIR="${WT_STATE_DIR:-$HOME/.claude/state}"
WT_EVENTS_FILE="${WT_EVENTS_FILE:-$WT_STATE_DIR/wt-events.jsonl}"
WT_WAKE_FILE="${WT_WAKE_FILE:-$WT_STATE_DIR/worktree-gc.wake}"
WT_PARK_INDEX="${WT_PARK_INDEX:-$WT_STATE_DIR/wt-parked}"
WT_PARK_ROOT="${WT_PARK_ROOT:-$HOME/Development/.worktrees/.parked}"
# Colon-separated config roots; each may hold settings.json and projects/. Empty ⇒ glob ~/.claude*.
WT_CONFIG_ROOTS="${WT_CONFIG_ROOTS:-}"

wt__now() { printf '%s' "${WT_NOW:-$(date +%s)}"; }   # epoch; WT_NOW is the lab clock

wt__ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

wt__json_esc() { # <s> → JSON string body (no quotes); control chars dropped
  printf '%s' "${1:-}" | LC_ALL=C sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | LC_ALL=C tr -d '\000-\010\013-\037'
}

wt__sha1() { printf '%s' "$1" | shasum -a 1 | cut -c1-40; }

wt__canon() { # <path> → physical absolute path if it exists, else the input unchanged
  if [ -d "$1" ]; then (cd -P -- "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; else printf '%s' "$1"; fi
}

wt__id_new() { # <path> → a fresh tombstone id: <utc-stamp>-<8 hex of path>-<pid><rand>
  printf '%s-%s-%s%s' "$(date -u +%Y%m%dT%H%M%SZ)" "$(wt__sha1 "$1" | cut -c1-8)" "$$" "${RANDOM:-0}"
}

wt__repo_of() { # <worktree-path> → absolute path of the main worktree (dirname of the common dir)
  local cd
  cd="$("$WT_GIT" -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [ -n "$cd" ] || return 1
  case "$cd" in */.git) printf '%s' "${cd%/.git}" ;; *) printf '%s' "$cd" ;; esac
}

wt__common_dir_of() { "$WT_GIT" -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null; }

wt__trunk_of() { # <repo> → the trunk ref to compare against: $WT_TRUNK, origin/HEAD's target, else origin/main
  if [ -n "${WT_TRUNK:-}" ]; then printf '%s' "$WT_TRUNK"; return 0; fi
  local t
  t="$("$WT_GIT" -C "$1" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  if [ -n "$t" ]; then printf '%s' "$t"; return 0; fi
  if "$WT_GIT" -C "$1" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then printf 'origin/main'; return 0; fi
  return 1   # AC-4: an unresolvable trunk is its own verdict; callers must not treat it as "landed"
}

wt__ledger_append() { # <json-object-line> → one append to the disposal ledger; rc≠0 if the write failed
  local dir; dir="$(dirname "$WT_LEDGER")"
  mkdir -p "$dir" 2>/dev/null || return 1
  printf '%s\n' "$1" >> "$WT_LEDGER" 2>/dev/null
}

wt__config_roots() { # → one config root per line (env list, else every ~/.claude* dir holding settings.json or projects/)
  if [ -n "$WT_CONFIG_ROOTS" ]; then printf '%s\n' "$WT_CONFIG_ROOTS" | tr ':' '\n' | sed '/^$/d'; return 0; fi
  local d
  for d in "$HOME"/.claude "$HOME"/.claude-*; do
    [ -d "$d/projects" ] || [ -f "$d/settings.json" ] || continue
    printf '%s\n' "$d"
  done
}

wt__slug() { printf '%s' "$1" | sed 's#[/.]#-#g'; }   # Claude Code's projects/<slug> naming

wt__err() { printf 'wt-tombstone: %s\n' "$*" >&2; }

wt__jstr() { if [ -n "${1:-}" ]; then printf '"%s"' "$(wt__json_esc "$1")"; else printf 'null'; fi; }

wt__jarr() { # <newline-separated list> → JSON array of strings
  local out="" l
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    out="$out${out:+,}\"$(wt__json_esc "$l")\""
  done <<EOF
${1:-}
EOF
  printf '[%s]' "$out"
}

wt__jobj() { # <lines "name sha"> → JSON object of strings
  local out="" k v
  while read -r k v; do
    [ -n "$k" ] || continue
    out="$out${out:+,}\"$(wt__json_esc "$k")\":\"$(wt__json_esc "$v")\""
  done <<EOF
${1:-}
EOF
  printf '{%s}' "$out"
}

# THE ROW. One fixed key list, so every row carries every key (null, never omitted) and a reader can
# tell "not recorded" from "not applicable" by the row's event alone. A writer sets WT_R_<key> and
# calls wt__row_emit; wt__row_reset clears the previous row's values first. Arrays are newline lists,
# `lockfiles` is "name sha" lines, `landed` is raw (true|false|null).
WT__ROW_STR="event id actor reason repo path branch head trunk mode preserved tomb_ref logs_head wip_ref checkpoint_ref parked_path branch_tip preserved_at destroyed_ignored"
WT__ROW_ARR="sids preserved_list caches_skipped identical_skipped reflog_refs"

wt__row_reset() {
  local k
  for k in $WT__ROW_STR $WT__ROW_ARR lockfiles landed; do unset "WT_R_$k"; done
}

wt__row_emit() { # → appends the row built from WT_R_*; rc≠0 if the ledger write failed
  local line k v
  line="{\"ts\":\"$(wt__ts)\""
  for k in $WT__ROW_STR; do eval "v=\${WT_R_$k:-}"; line="$line,\"$k\":$(wt__jstr "$v")"; done
  for k in $WT__ROW_ARR; do eval "v=\${WT_R_$k:-}"; line="$line,\"$k\":$(wt__jarr "$v")"; done
  line="$line,\"lockfiles\":$(wt__jobj "${WT_R_lockfiles:-}"),\"landed\":${WT_R_landed:-null}}"
  wt__ledger_append "$line"
}

wt__transcript_dirs_of() { # <path> → every config root's projects/<slug> dir for this cwd or a subdirectory of it
  # Claude Code slugs a cwd by mapping / and . to -, so "/x/wt-a/sub" and "/x/wt-a-sub" share a slug.
  # The exact slug is unambiguous; a longer one counts only if one of its transcripts names a cwd under
  # this path (one bounded read per candidate dir), so a sibling worktree's sessions never pin this one.
  local p="$1" slug root d f cwd
  slug="$(wt__slug "$p")"
  while IFS= read -r root; do
    [ -d "$root/projects" ] || continue
    for d in "$root/projects/$slug" "$root/projects/$slug"-*; do
      [ -d "$d" ] || continue
      if [ "$d" = "$root/projects/$slug" ]; then printf '%s\n' "$d"; continue; fi
      for f in "$d"/*.jsonl; do
        [ -f "$f" ] || continue
        cwd="$(head -c 65536 "$f" 2>/dev/null | grep -o '"cwd":"[^"]*"' | head -1 | sed 's/^"cwd":"//; s/"$//')"
        case "$cwd" in "$p"/*) printf '%s\n' "$d" ;; esac
        break
      done
    done
  done <<EOF
$(wt__config_roots)
EOF
}

wt__sids_of() { # <path> → session ids whose transcript cwd is this path (or under it), one per line
  local d f
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    for f in "$d"/*.jsonl; do [ -f "$f" ] && basename "$f" .jsonl; done
  done <<EOF
$(wt__transcript_dirs_of "$1")
EOF
}

wt__landed() { # <repo> <trunk> <commit> → prints true|false (null when no trunk)
  if [ -z "$2" ] || [ -z "$3" ]; then printf 'null'; return 0; fi
  if "$WT_GIT" -C "$1" cherry "$2" "$3" 2>/dev/null | grep -q '^+'; then printf 'false'; else printf 'true'; fi
}

wt__epoch_of_ts() { date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null; }

# ---- residue classification (note X6: cache rule, cmp rule, lockfile rule) ------------------------

wt__bounded() { # <cmd…> → runs it under gtimeout WT_LOCKCHECK_TIMEOUT; no gtimeout ⇒ fail (counts as residue)
  local gt
  gt="$(command -v gtimeout 2>/dev/null)"
  if [ -z "$gt" ] && [ -x /opt/homebrew/bin/gtimeout ]; then gt=/opt/homebrew/bin/gtimeout; fi
  [ -n "$gt" ] || return 1
  "$gt" "${WT_LOCKCHECK_TIMEOUT:-20}" "$@" >/dev/null 2>&1
}

wt__lockfile_cache() { # <tree> <rel-entry> → 0 + prints "name sha" when the dir is reproducible from a lockfile beside it
  local tree="$1" rel="$2" base dir
  base="$(basename "$rel")"
  dir="$tree/$(dirname "$rel")"
  case "$base" in
    node_modules)
      if [ -f "$dir/pnpm-lock.yaml" ] && [ -f "$dir/node_modules/.pnpm/lock.yaml" ] \
         && cmp -s "$dir/pnpm-lock.yaml" "$dir/node_modules/.pnpm/lock.yaml"; then
        printf 'pnpm-lock.yaml %s\n' "$(shasum -a 256 "$dir/pnpm-lock.yaml" | cut -c1-64)"; return 0
      fi
      if [ -f "$dir/package-lock.json" ] && command -v npm >/dev/null 2>&1 \
         && (cd "$dir" && wt__bounded npm ls --all); then
        printf 'package-lock.json %s\n' "$(shasum -a 256 "$dir/package-lock.json" | cut -c1-64)"; return 0
      fi ;;
    .venv)
      # --check never writes: the venv and uv.lock keep their mtimes (asserted in tests/wt-tombstone.bats).
      if [ -f "$dir/uv.lock" ] && command -v uv >/dev/null 2>&1 \
         && (cd "$dir" && wt__bounded uv sync --check --locked --offline); then
        printf 'uv.lock %s\n' "$(shasum -a 256 "$dir/uv.lock" | cut -c1-64)"; return 0
      fi ;;
  esac
  return 1
}

wt__classify() { # <tree> <repo> → lines "C <rel>" cache, "I <rel>" identical provisioning copy, "R <rel>" residue, "L <name sha>" lockfile
  local tree="$1" repo="$2" ent rel base lf
  while IFS= read -r -d '' ent; do
    case "$ent" in '!! '*) ;; *) continue ;; esac
    rel="${ent#!! }"; rel="${rel%/}"
    base="$(basename "$rel")"
    case "$base" in
      .next|__pycache__|.ruff_cache|.pytest_cache|.mypy_cache|.turbo|.eslintcache|*.tsbuildinfo)
        printf 'C %s\n' "$rel"; continue ;;
      node_modules|.venv)
        if lf="$(wt__lockfile_cache "$tree" "$rel")"; then printf 'C %s\nL %s\n' "$rel" "$lf"; continue; fi ;;
    esac
    case "$rel" in
      .env*|*/.env*|.claude/settings.local.json)
        if [ -f "$tree/$rel" ] && [ ! -L "$tree/$rel" ] && [ -f "$repo/$rel" ] && cmp -s "$tree/$rel" "$repo/$rel"; then
          printf 'I %s\n' "$rel"; continue
        fi ;;
    esac
    printf 'R %s\n' "$rel"
  done < <("$WT_GIT" -C "$tree" status --porcelain --ignored -z 2>/dev/null)
}

wt__wip_snapshot() { # <tree> → prints a commit holding tracked + untracked working content (nothing written to the tree)
  local tree="$1" head idx tmp t c
  head="$("$WT_GIT" -C "$tree" rev-parse --verify -q HEAD)" || return 1
  idx="$("$WT_GIT" -C "$tree" rev-parse --path-format=absolute --git-path index 2>/dev/null)"
  tmp="$(mktemp)" || return 1
  { [ -s "$idx" ] && cp "$idx" "$tmp"; } || { : > "$tmp"; GIT_INDEX_FILE="$tmp" "$WT_GIT" -C "$tree" read-tree HEAD 2>/dev/null; }
  t="$(GIT_INDEX_FILE="$tmp" "$WT_GIT" -C "$tree" -c core.splitIndex=false add -A >/dev/null 2>&1 \
       && GIT_INDEX_FILE="$tmp" "$WT_GIT" -C "$tree" write-tree 2>/dev/null)"
  rm -f "$tmp"
  [ -n "$t" ] || return 1
  c="$("$WT_GIT" -C "$tree" commit-tree "$t" -p "$head" -m "wt-tombstone wip snapshot of $tree" 2>/dev/null)" || return 1
  printf '%s' "$c"
}

# ---- the record --------------------------------------------------------------------------------------

wt_reflog_refs() { # <worktree-gitdir> <repo> <trunk> <id> → refs created for reflog-only, unlanded commits; rc 2 if one failed
  # Removal deletes <gitdir>/logs/HEAD, so a commit reachable only from it (a reset, amend or rebase
  # inside the tree) becomes gc-able, and landed() never sees it because it runs `git cherry` on HEAD.
  local gd="$1" repo="$2" trunk="$3" id="$4" logs c n=0
  logs="$gd/logs/HEAD"
  [ -f "$logs" ] || return 0
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    if [ -n "$trunk" ] && "$WT_GIT" -C "$repo" rev-parse -q --verify "$c^" >/dev/null 2>&1; then
      "$WT_GIT" -C "$repo" cherry "$trunk" "$c" "$c^" 2>/dev/null | grep -q '^+' || continue
    fi
    n=$((n + 1))
    "$WT_GIT" -C "$repo" update-ref "refs/wt-tombstone/$id/reflog-$n" "$c" 2>/dev/null \
      || { wt__err "cannot create refs/wt-tombstone/$id/reflog-$n"; return 2; }
    printf 'refs/wt-tombstone/%s/reflog-%s\n' "$id" "$n"
  done < <(awk '{print $1; print $2}' "$logs" | grep -E '^[0-9a-f]{40,64}$' | grep -v '^0*$' | sort -u \
           | "$WT_GIT" -C "$repo" cat-file --batch-check='%(objectname) %(objecttype)' 2>/dev/null \
           | awk '$2=="commit"{print $1}' \
           | "$WT_GIT" -C "$repo" rev-list --stdin --not --branches --tags --remotes --glob="refs/wt-tombstone/$id/*" 2>/dev/null)
}

wt_residue_restore() { # <id> <path> → moves an mv-ed residue back into the tree (its removal was refused)
  local src="$WT_TOMB_DIR/$1/residue" path="$2" rel rc=0
  [ -d "$src" ] || return 0
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    mkdir -p "$path/$(dirname "$rel")" 2>/dev/null
    mv "$src/$rel" "$path/$rel" 2>/dev/null || { wt__err "could not move $rel back from $src"; rc=2; }
  done <<EOF
$(cat "$WT_TOMB_DIR/$1/residue.list" 2>/dev/null)
EOF
  return $rc
}

wt__capture() { # <tree> <tdir> <mode> <residue-list> → 0 captured (stdout: preserved marker) / 2 failed
  local tree="$1" tdir="$2" mode="$3" list="$4" rel dest kb=0 k
  [ -n "$list" ] || return 0
  printf '%s\n' "$list" > "$tdir/residue.list" || return 2
  if [ "$(stat -f %d "$tree")" != "$(stat -f %d "$tdir")" ]; then
    # Across volumes a rename is impossible and a clone is a copy: tar, with the old cap.
    while IFS= read -r rel; do
      k="$(du -sk "$tree/$rel" 2>/dev/null | cut -f1)"; kb=$((kb + ${k:-0}))
    done <<EOF
$list
EOF
    [ "$kb" -le 51200 ] || { wt__err "residue ${kb} KB crosses volumes and exceeds the 50 MB cap — keep the tree"; return 2; }
    printf '%s\n' "$list" | (cd "$tree" && tar -cf "$tdir/residue.tar" -T -) 2>/dev/null || return 2
    printf '%s/residue.tar' "$(basename "$tdir")"; return 0
  fi
  while IFS= read -r rel; do
    dest="$tdir/residue/$rel"
    mkdir -p "$(dirname "$dest")" || return 2
    if [ "$mode" = clone ]; then
      cp -RPc "$tree/$rel" "$dest" 2>/dev/null || cp -RP "$tree/$rel" "$dest" 2>/dev/null || return 2
    else
      mv "$tree/$rel" "$dest" 2>/dev/null || return 2
    fi
  done <<EOF
$list
EOF
  printf '%s/residue' "$(basename "$tdir")"
}

wt__undo() { # <mode> <id> <path> → puts an mv-ed residue back; always rc 2
  [ "$1" = mv ] && wt_residue_restore "$2" "$3"
  return 2
}

wt_tombstone() { # <path> <actor> <reason> [--mode mv|clone] [--wip] [--checkpoint-ref R] [--event E] → prints id
  # Writes everything a later restore needs BEFORE the caller removes the tree: the residue (moved or
  # cloned on one volume, no cap), a durable ref for a head trunk does not contain, refs for reflog-only
  # work, a copy of logs/HEAD and, for a forced dirty removal, a wip snapshot. The row goes last, so a
  # row always means a complete record; any failure undoes the move and returns 2 (KEEP the tree).
  [ $# -ge 3 ] || { wt__err "usage: wt_tombstone <path> <actor> <reason> [opts]"; return 2; }
  local path="$1" actor="$2" reason="$3" mode=mv wip=0 ckref="" event=worktree-disposed
  shift 3
  while [ $# -gt 0 ]; do
    case "$1" in
      --wip) wip=1; shift; continue ;;
      --mode|--checkpoint-ref|--event) [ $# -ge 2 ] || { wt__err "$1 needs a value"; return 2; } ;;
      *) wt__err "unknown option $1"; return 2 ;;
    esac
    case "$1" in --mode) mode="$2" ;; --checkpoint-ref) ckref="$2" ;; --event) event="$2" ;; esac
    shift 2
  done
  case "$mode" in mv|clone) ;; *) wt__err "bad --mode $mode"; return 2 ;; esac
  [ -d "$path" ] || { wt__err "$path is not a directory"; return 2; }
  path="$(wt__canon "$path")"
  local repo trunk gd head branch id tdir cls residue caches ident lockf preserved="" target refs="" wipc=""
  repo="$(wt__repo_of "$path")" || { wt__err "$path is not in a git repository"; return 2; }
  trunk="$(wt__trunk_of "$repo")" || trunk=""
  gd="$("$WT_GIT" -C "$path" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
  head="$("$WT_GIT" -C "$path" rev-parse --verify -q HEAD 2>/dev/null)"
  branch="$("$WT_GIT" -C "$path" symbolic-ref -q --short HEAD 2>/dev/null)"
  id="$(wt__id_new "$path")"
  tdir="$WT_TOMB_DIR/$id"
  ( umask 077; mkdir -p "$tdir" ) || { wt__err "cannot create $tdir"; return 2; }
  chmod 700 "$WT_TOMB_DIR" "$tdir" 2>/dev/null

  cls="$(wt__classify "$path" "$repo")"
  residue="$(printf '%s\n' "$cls" | sed -n 's/^R //p')"
  caches="$(printf '%s\n' "$cls" | sed -n 's/^C //p')"
  ident="$(printf '%s\n' "$cls" | sed -n 's/^I //p')"
  lockf="$(printf '%s\n' "$cls" | sed -n 's/^L //p')"

  ( umask 077; wt__capture "$path" "$tdir" "$mode" "$residue" > "$tdir/.preserved" ) || {
    [ "$mode" = mv ] && wt_residue_restore "$id" "$path"
    wt__err "residue capture failed for $path — tree kept"; return 2; }
  preserved="$(cat "$tdir/.preserved" 2>/dev/null)"; rm -f "$tdir/.preserved"

  target="$head"
  if [ -n "$ckref" ]; then
    target="$("$WT_GIT" -C "$path" rev-parse --verify -q "$ckref^{commit}" 2>/dev/null)" \
      || { wt__err "checkpoint ref $ckref does not resolve"; wt__undo "$mode" "$id" "$path"; return 2; }
  fi
  local tomb_ref=""
  if [ -n "$target" ] && ! { [ -n "$trunk" ] && "$WT_GIT" -C "$repo" merge-base --is-ancestor "$target" "$trunk" 2>/dev/null; }; then
    tomb_ref="refs/wt-tombstone/$id/head"
    "$WT_GIT" -C "$repo" update-ref "$tomb_ref" "$target" 2>/dev/null \
      || { wt__err "cannot create $tomb_ref"; wt__undo "$mode" "$id" "$path"; return 2; }
  fi
  if [ -n "$gd" ]; then
    refs="$(wt_reflog_refs "$gd" "$repo" "$trunk" "$id")" || { wt__undo "$mode" "$id" "$path"; return 2; }
  fi
  local logs_head=""
  if [ -f "$gd/logs/HEAD" ]; then
    ( umask 077; cp "$gd/logs/HEAD" "$tdir/logs-HEAD" ) || { wt__err "cannot copy logs/HEAD"; wt__undo "$mode" "$id" "$path"; return 2; }
    logs_head="$id/logs-HEAD"
  fi
  local wip_ref=""
  if [ "$wip" = 1 ] && [ -n "$("$WT_GIT" -C "$path" status --porcelain 2>/dev/null)" ]; then
    wipc="$(wt__wip_snapshot "$path")" || { wt__err "wip snapshot failed for $path"; wt__undo "$mode" "$id" "$path"; return 2; }
    wip_ref="refs/wt-tombstone/$id/wip"
    "$WT_GIT" -C "$repo" update-ref "$wip_ref" "$wipc" 2>/dev/null || { wt__err "cannot create $wip_ref"; wt__undo "$mode" "$id" "$path"; return 2; }
  fi

  wt__row_reset
  WT_R_event="$event"; WT_R_id="$id"; WT_R_actor="$actor"; WT_R_reason="$reason"; WT_R_repo="$repo"
  WT_R_path="$path"; WT_R_branch="$branch"; WT_R_head="$head"; WT_R_trunk="$trunk"; WT_R_mode="$mode"
  WT_R_landed="$(wt__landed "$repo" "$trunk" "$head")"; WT_R_sids="$(wt__sids_of "$path")"
  WT_R_preserved="$preserved"; WT_R_preserved_list="$residue"; WT_R_caches_skipped="$caches"
  WT_R_identical_skipped="$ident"; WT_R_lockfiles="$lockf"; WT_R_tomb_ref="$tomb_ref"; WT_R_reflog_refs="$refs"
  WT_R_logs_head="$logs_head"; WT_R_wip_ref="$wip_ref"; WT_R_checkpoint_ref="$ckref"
  WT_R_preserved_at="${tomb_ref:-${branch:+refs/heads/$branch}}"; WT_R_preserved_at="${WT_R_preserved_at:-$head}"
  WT_R_destroyed_ignored="$(printf '%s\n%s\n' "$caches" "$ident" | sed '/^$/d' | paste -sd, -)"
  wt__row_emit || { wt__err "ledger write failed ($WT_LEDGER) — tree kept"; wt__undo "$mode" "$id" "$path"; return 2; }
  printf '%s\n' "$id"
}

wt__admin_record() { # <repo> <trunk> <admin-dir> <actor> <reason> → one admin-pruned row for a worktree admin entry
  local repo="$1" trunk="$2" adm="$3" h branch="" head="" path="" id tdir refs="" logs_head=""
  h="$(cat "$adm/HEAD" 2>/dev/null)"
  case "$h" in
    'ref: '*) branch="${h#ref: refs/heads/}"; head="$("$WT_GIT" -C "$repo" rev-parse --verify -q "${h#ref: }" 2>/dev/null)" ;;
    *) head="$h" ;;
  esac
  path="$(cat "$adm/gitdir" 2>/dev/null)"; path="${path%/.git}"
  id="$(wt__id_new "${path:-$adm}")"; tdir="$WT_TOMB_DIR/$id"
  ( umask 077; mkdir -p "$tdir" ) || return 2
  if [ -f "$adm/logs/HEAD" ]; then ( umask 077; cp "$adm/logs/HEAD" "$tdir/logs-HEAD" ) && logs_head="$id/logs-HEAD"; fi
  refs="$(wt_reflog_refs "$adm" "$repo" "$trunk" "$id")" || return 2
  wt__row_reset
  WT_R_event="admin-pruned"; WT_R_id="$id"; WT_R_actor="$4"; WT_R_reason="$5"; WT_R_repo="$repo"; WT_R_path="$path"
  WT_R_branch="$branch"; WT_R_head="$head"; WT_R_trunk="$trunk"; WT_R_mode=none
  WT_R_landed="$(wt__landed "$repo" "$trunk" "$head")"; WT_R_reflog_refs="$refs"; WT_R_logs_head="$logs_head"
  WT_R_preserved_at="${branch:+refs/heads/$branch}"
  wt__row_emit
}

wt__prune_record() { # <repo> <actor> <reason> → admin-pruned rows for every entry `worktree prune` would remove
  local repo="$1" cd trunk name rc=0
  cd="$(wt__common_dir_of "$repo")" || return 2
  trunk="$(wt__trunk_of "$repo")" || trunk=""
  while IFS= read -r name; do
    [ -n "$name" ] && [ -d "$cd/worktrees/$name" ] || continue
    wt__admin_record "$repo" "$trunk" "$cd/worktrees/$name" "$2" "$3" || rc=2
  done < <("$WT_GIT" -C "$repo" worktree prune --dry-run -v 2>&1 | sed -n 's/^Removing worktrees\/\([^:]*\):.*/\1/p')
  return $rc
}

wt_prune_logged() { # <repo> [prune-args…] → records admin-pruned rows, then runs the prune unchanged; returns ITS rc
  local repo="$1"; shift
  wt__prune_record "$repo" "${WT_ACTOR:-wt_prune_logged}" "prune" \
    || wt__err "admin-pruned logging incomplete for $repo (the prune still runs)"
  "$WT_GIT" -C "$repo" worktree prune "$@"
}

wt_branch_deleted_row() { # <repo> <branch> <sha> <actor> [reason]
  wt__row_reset
  WT_R_event="branch-deleted"; WT_R_id="$(wt__id_new "$1:$2")"; WT_R_repo="$1"; WT_R_branch="$2"; WT_R_head="$3"
  WT_R_actor="$4"; WT_R_reason="${5:-}"; WT_R_mode=none; WT_R_preserved_at="$3"
  wt__row_emit
}

wt_emit_event() { # <ev> <path> [sid] → one append to the queue + a touch of the wake file; never fails the caller
  local repo
  repo="$(wt__repo_of "$2" 2>/dev/null)" || repo=""
  { mkdir -p "$(dirname "$WT_EVENTS_FILE")" "$(dirname "$WT_WAKE_FILE")" \
    && printf '{"ev":%s,"path":%s,"sid":%s,"repo":%s,"ts":"%s"}\n' "$(wt__jstr "$1")" "$(wt__jstr "$2")" \
         "$(wt__jstr "${3:-}")" "$(wt__jstr "$repo")" "$(wt__ts)" >> "$WT_EVENTS_FILE" \
    && touch "$WT_WAKE_FILE"; } 2>/dev/null || wt__err "event $1 for $2 not queued"
  return 0
}

wt_tomb_find() { # <path> [--sid S] [--branch B] → newest removal row for path (sid OR branch match when given); rc 1 none
  local path="$1" sid="" br="" row
  shift
  while [ $# -ge 2 ]; do
    case "$1" in --sid) sid="$2" ;; --branch) br="$2" ;; esac
    shift 2
  done
  [ -f "$WT_LEDGER" ] || return 1
  row="$(jq -cR --arg p "$path" --arg s "$sid" --arg b "$br" '
    fromjson? | select(.path == $p and ((.event // "") | IN("worktree-disposed","guard-snapshot","admin-pruned")))
    | select(($s == "" and $b == "") or ($s != "" and ((.sids // []) | index($s)) != null) or ($b != "" and .branch == $b))
  ' "$WT_LEDGER" 2>/dev/null | tail -1)"   # -R + fromjson?: one torn legacy line never hides later rows
  [ -n "$row" ] || return 1
  printf '%s\n' "$row"
}

wt_cleanup_period_days() { # → max cleanupPeriodDays over the config roots; a root without the key counts 30
  local root v max=0 any=0
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    any=1
    v="$(jq -r '.cleanupPeriodDays // empty' "$root/settings.json" 2>/dev/null)"
    case "$v" in ''|*[!0-9]*) v=30 ;; esac
    [ "$v" -gt "$max" ] && max="$v"
  done <<EOF
$(wt__config_roots)
EOF
  [ "$any" = 1 ] || max=30
  printf '%s\n' "$max"
}

wt_ref_expire() { # <repo> → deletes refs/wt-tombstone/<id>/* older than cleanupPeriodDays and never restored; residue untouched
  local repo="$1" days cutoff id ts ep ref idx
  days="$(wt_cleanup_period_days)"
  cutoff=$(( $(wt__now) - days * 86400 ))
  [ -f "$WT_LEDGER" ] || return 0
  # One ledger pass: "<id>\t<event>\t<ts>" per row that carries an id.
  idx="$(jq -rR 'fromjson? | select(.id != null) | [.id, (.event // ""), (.ts // "")] | @tsv' "$WT_LEDGER" 2>/dev/null)"
  for id in $("$WT_GIT" -C "$repo" for-each-ref --format='%(refname)' refs/wt-tombstone/ 2>/dev/null | cut -d/ -f3 | sort -u); do
    printf '%s\n' "$idx" | awk -F'\t' -v i="$id" '$1==i && $2=="restored"{f=1} END{exit !f}' && continue
    ts="$(printf '%s\n' "$idx" | awk -F'\t' -v i="$id" '$1==i{print $3; exit}')"
    [ -n "$ts" ] || continue                       # no row: unknown provenance, keep
    ep="$(wt__epoch_of_ts "$ts")"; [ -n "$ep" ] || continue
    [ "$ep" -lt "$cutoff" ] || continue
    for ref in $("$WT_GIT" -C "$repo" for-each-ref --format='%(refname)' "refs/wt-tombstone/$id/" 2>/dev/null); do
      "$WT_GIT" -C "$repo" update-ref -d "$ref" 2>/dev/null
    done
    wt__row_reset; WT_R_event="ref-expired"; WT_R_id="$id"; WT_R_repo="$repo"; WT_R_actor=wt_ref_expire
    WT_R_reason="older than cleanupPeriodDays=$days"; WT_R_mode=none
    wt__row_emit
  done
}

wt_purge() { # <id> --operator → removes a tombstone's residue; refuses without the operator flag
  local id="$1"
  [ "${2:-}" = --operator ] || { wt__err "purge removes paid residue for good; only an operator runs it (--operator)"; return 2; }
  case "$id" in ''|*/*|.|..) wt__err "bad id '$id'"; return 2 ;; esac
  [ -d "$WT_TOMB_DIR/$id" ] || { wt__err "no tombstone $id"; return 1; }
  rm -rf "${WT_TOMB_DIR:?}/$id" || return 2
  wt__row_reset; WT_R_event="residue-purged"; WT_R_id="$id"; WT_R_actor=operator; WT_R_mode=none
  wt__row_emit
}

# ---- WP-9b (wt-park.sh) implements PARK, unpark and the pins named in W2-CONTRACT.md ----

_wt_park_lib="$(dirname "${BASH_SOURCE[0]}")/wt-park.sh"
# shellcheck source=/dev/null
[ -f "$_wt_park_lib" ] && . "$_wt_park_lib"
unset _wt_park_lib
