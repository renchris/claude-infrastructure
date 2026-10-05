#!/usr/bin/env bash
# restore-heartbeat.sh — the restore heartbeat: who was live, and how, as of the last 300 s tick
# (W3 P3a-i, 2026-10-04; plan docs/research/session-durability-2026-10/W3-build-plan.md § Amendment B).
#
# WHY: a hard power-off runs no SessionEnd hook, so it leaves no tombstone; the alarm roster is taken
# at most once a day; and the registry fallback caps a restore at 4 sessions. Measured on 2026-10-04:
# at most 4 of ~18 live sessions came back. boot-resume.sh already ticks every 300 s under launchd,
# so each tick now records the live fleet first, and the restore reads the newest record.
#
#   hb_tick                          write this tick's heartbeat; rc 0 wrote · 1 nothing to write · 2 failed
#   hb_pick <dir> <lower> <upper> [--dead-kitty]
#                                    print "<start>\t<dir>" for the heartbeat dirs to restore from:
#                                    the newest whose start is in (lower, upper], plus any written in
#                                    the same tick (two kittys live together). rc 1 when none.
#   hb_prune                         drop heartbeat dirs older than CC_HB_RETAIN_DAYS (7)
#   hb_display_probe [pwid...]       no argument: one "uuid dx dy dw dh" row per display now attached;
#                                    with platform window ids: one hb.displays.tsv row per id found.
#                                    Tab-separated, read-only. rc 1 when Swift is absent or failed.
#
# Layout: <root>/<bootuuid>/<kitty-pid>/, root ~/.claude/autonomy/heartbeat. Each tick overwrites only
# its OWN boot and its own LIVE kitty pids, so neither a reboot (new uuid) nor a kitty restart (new
# pid) ever overwrites the record of the fleet that died. A dead kitty's directory is never written
# again: its last tick is the evidence. Every file is written to a temp name and moved into place.
#   hb.roster.json     the `cc-sessions --json` rows whose kitty_pid is this kitty (an array)
#   hb.start           the tick epoch, one line, one field; written LAST
#   hb.session.tsv     sid  account  model  effort  permission_mode  branch  pid
#                      account = the config dir of the newest transcript; model and effort from the
#                      last real assistant record, permission mode from the last permission-mode
#                      record, each falling back to the claude argv; branch from git in the cwd
#   hb.kitty-ls.json   the whole tree from ONE bounded `kitten @ ls`; on failure the last good one stays
#   hb.bg.tsv          sid  claude_pid  kind  pid  detail — kind child (non-MCP descendant, argv),
#                      watching (a live cc-await-ping .watching pid), listen (a TCP port a descendant
#                      listens on), agent-browser (a live ~/.agent-browser/<name>.pid; sid "-")
#   hb.roles.tsv       role  pane  sid (sid empty when the role's pane is not live)
#   hb.displays.tsv    platform_window_id  display_uuid  dx dy dw dh  fullscreen  wx wy ww wh — one row per
#                      kitty OS window in the tree's order (W3 P7): the display it is on (uuid and
#                      bounds), whether it fills that display, and its own bounds, all in the top-left
#                      global coordinates System Events uses. From one bounded Swift read (about 0.5 s);
#                      on failure the last good one stays
# Empty TSV cells are written as $'\037' (boot-resume.sh's field-collapse guard).
#
# cc-sessions SWEEPS registry rows of dead sessions started over 24 h ago. boot-resume.sh therefore
# runs the tick AFTER it has read the registry on the first run of a new boot (see its step 0).
#
# Under a bats harness (the three variables restore-lock.sh's restore_refuse_under_bats reads) a tick
# whose cc-sessions or kitten seam is unset does not touch the real one: a test once reached the live
# kitty (1deb094d2).
#
# /bin/bash 3.2 safe: launchd runs it. Sourced: defines functions only.
# Seams: CC_HEARTBEAT_DIR · CC_HB_SESSIONS_BIN · CC_HB_KITTEN_BIN · CC_HB_PS_BIN · CC_HB_LSOF_BIN ·
#   CC_HB_NOW · CC_HB_RETAIN_DAYS · CC_HB_SWIFT_BIN · CC_HB_TIMEOUT_BIN ("" forces the perl bound) · CC_BOOTUUID_OVERRIDE ·
#   CC_ROLES_DIR · CC_HB_MAILBOX_DIR · CC_HB_AGENT_BROWSER_DIR

HB_PAD=$'\037'

hb_root() { printf '%s' "${CC_HEARTBEAT_DIR:-$HOME/.claude/autonomy/heartbeat}"; }

_hb_under_bats() { [ -n "${BATS_TEST_FILENAME:-}${BATS_TEST_TMPDIR:-}${BATS_VERSION:-}" ]; }

_hb_bootuuid() {
  if [ -n "${CC_BOOTUUID_OVERRIDE+x}" ]; then printf '%s' "$CC_BOOTUUID_OVERRIDE"; return 0; fi
  /usr/sbin/sysctl -n kern.bootsessionuuid 2>/dev/null | tr -d '[:space:]'
}

# _hb_to <secs> <cmd...> — run bounded, rc 124 on timeout. Stock macOS has no timeout(1); without
# one, a perl alarm kills the call's whole process group (cc-resume-layout.sh's kb() idiom).
_hb_to() {
  local t="$1" tb; shift
  tb="${CC_HB_TIMEOUT_BIN-$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null \
      || { [ -x /opt/homebrew/bin/timeout ] && printf '%s' /opt/homebrew/bin/timeout; })}"
  if [ -n "$tb" ]; then "$tb" "$t" "$@"; return $?; fi
  /usr/bin/perl -e 'my $t = shift; my $pid = fork; exit 125 unless defined $pid;
    if ($pid == 0) { setpgrp(0, 0); exec { $ARGV[0] } @ARGV; exit 127 }
    $SIG{ALRM} = sub { kill "TERM", -$pid; select(undef, undef, undef, 0.5); kill "KILL", -$pid; exit 124 };
    alarm $t; waitpid($pid, 0); exit(($? & 127) ? 128 + ($? & 127) : $? >> 8)' "$t" "$@"
}

# _hb_mv <tmp> <dest> — atomic replace; a failed move leaves the last good file and drops the temp.
_hb_mv() { mv -f "$1" "$2" 2>/dev/null || { rm -f "$1" 2>/dev/null; return 1; }; }

# _hb_start_of <dir> — the first field of the first line of <dir>/hb.start, digits only, else "".
_hb_start_of() {
  local s
  s="$(head -n 1 "$1/hb.start" 2>/dev/null | awk '{ print $1 }')"
  case "$s" in ''|*[!0-9]*) return 0 ;; esac
  printf '%s' "$s"
}

_hb_sessions_bin() {
  if [ -n "${CC_HB_SESSIONS_BIN:-}" ]; then printf '%s' "$CC_HB_SESSIONS_BIN"; return 0; fi
  _hb_under_bats && return 0
  local c
  for c in "$(dirname "${BASH_SOURCE[0]}")/../../bin/cc-sessions" "$HOME/.claude/bin/cc-sessions"; do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  command -v cc-sessions 2>/dev/null || true
}

_hb_kitten_bin() {
  if [ -n "${CC_HB_KITTEN_BIN:-}" ]; then printf '%s' "$CC_HB_KITTEN_BIN"; return 0; fi
  _hb_under_bats && return 0
  local c
  for c in /Applications/kitty.app/Contents/MacOS/kitten /opt/homebrew/bin/kitten /usr/local/bin/kitten; do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
}

_hb_swift_bin() {
  if [ -n "${CC_HB_SWIFT_BIN:-}" ]; then printf '%s' "$CC_HB_SWIFT_BIN"; return 0; fi
  _hb_under_bats && return 0
  [ -x /usr/bin/swift ] && printf '%s' /usr/bin/swift
  return 0
}

# hb_display_probe [platform_window_id...] — see the header. The window list is the one
# cc-resume-layout.sh's per-monitor mode reads (CGWindowListCopyWindowInfo: a kitty OS window's
# platform_window_id is its CGWindow number); displays come from NSScreen, because
# CGGetActiveDisplayList returned none under the swift interpreter (measured 2026-10-05). A window
# counts as fullscreen when it is as wide as its display and at most a notch strip shorter.
hb_display_probe() {
  local sw td rc=0
  sw="$(_hb_swift_bin)"
  [ -n "$sw" ] && [ -x "$sw" ] || return 1
  td="$(mktemp -d "${TMPDIR:-/tmp}/hbdisp.XXXXXX" 2>/dev/null)" || return 1
  cat > "$td/d.swift" <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation
var ds: [(String, CGRect)] = []
for sc in NSScreen.screens {
    guard let num = sc.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
    let id = CGDirectDisplayID(num.uint32Value)
    let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
    let s = u.map { CFUUIDCreateString(nil, $0) as String } ?? "display-\(id)"
    ds.append((s, CGDisplayBounds(id)))
}
let want = CommandLine.arguments.dropFirst().compactMap { Int($0) }
if want.isEmpty {
    for d in ds { print("\(d.0)\t\(Int(d.1.minX))\t\(Int(d.1.minY))\t\(Int(d.1.width))\t\(Int(d.1.height))") }
    exit(0)
}
var found: [Int: CGRect] = [:]
if let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] {
    for w in list {
        guard let num = w[kCGWindowNumber as String] as? Int, want.contains(num),
              let b = w[kCGWindowBounds as String] as? [String: Any],
              let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { continue }
        found[num] = r
    }
}
for p in want {
    guard let r = found[p] else { continue }
    guard let d = ds.first(where: { $0.1.contains(CGPoint(x: r.midX, y: r.midY)) }) else { continue }
    let fs = (abs(r.width - d.1.width) < 2 && r.height >= d.1.height - 80) ? 1 : 0
    print("\(p)\t\(d.0)\t\(Int(d.1.minX))\t\(Int(d.1.minY))\t\(Int(d.1.width))\t\(Int(d.1.height))\t\(fs)\t\(Int(r.minX))\t\(Int(r.minY))\t\(Int(r.width))\t\(Int(r.height))")
}
SWIFT
  _hb_to "${CC_HB_SWIFT_TIMEOUT:-20}" "$sw" "$td/d.swift" "$@" 2>/dev/null || rc=1
  rm -rf "$td"
  return "$rc"
}

# _hb_transcript <sid> <cwd> — "<config-basename>\t<path>" of the session's NEWEST transcript, or "".
# The project slug is the cwd with / and . turned into -, so the direct path is tried first; the glob
# over every project dir (thousands per account) is the fallback for a cwd that moved.
_hb_transcript() {
  local sid="$1" cwd="$2" slug d p m best="" bm=0 bd=""
  slug="$(printf '%s' "$cwd" | tr '/.' '--')"
  for d in "$HOME"/.claude*; do
    [ -d "$d/projects" ] || continue
    p="$d/projects/$slug/$sid.jsonl"
    [ -n "$cwd" ] && [ -f "$p" ] || continue
    m="$(stat -f %m "$p" 2>/dev/null)"; case "$m" in ''|*[!0-9]*) continue ;; esac
    [ "$m" -gt "$bm" ] && { bm="$m"; best="$p"; bd="$d"; }
  done
  if [ -z "$best" ]; then
    for p in "$HOME"/.claude*/projects/*/"$sid".jsonl; do
      [ -f "$p" ] || continue
      m="$(stat -f %m "$p" 2>/dev/null)"; case "$m" in ''|*[!0-9]*) continue ;; esac
      [ "$m" -gt "$bm" ] && { bm="$m"; best="$p"; bd="${p%%/projects/*}"; }
    done
  fi
  bd="${bd##*/}"   # the registry's account is the config dir's basename WITHOUT its dot
  [ -n "$best" ] && printf '%s\t%s' "${bd#.}" "$best"
  return 0
}

# _hb_argv_flag <args> <flag> — the value after --flag (or --flag=value) in a claude argv line.
_hb_argv_flag() {
  printf '%s\n' "$1" | awk -v f="$2" '{
    for (i = 1; i <= NF; i++) {
      if ($i == f && i < NF) { print $(i + 1); exit }
      if (index($i, f "=") == 1) { print substr($i, length(f) + 2); exit }
    } }'
}

_hb_cell() { if [ -n "$1" ]; then printf '%s' "$1" | tr '\t\n' '  '; else printf '%s' "$HB_PAD"; fi; }

# _hb_session_tsv <roster.json> <ps.txt> — one hb.session.tsv row per roster row, on stdout.
_hb_session_tsv() {
  local rows sid cwd acct pid tr tacct tpath args fields model effort pm br
  # Padded at the emitter (tsv-pad-lint): tab is IFS-whitespace, so an empty cell would shift the rest.
  rows="$(jq -r --arg pad "$HB_PAD" 'def cell(ph): (if . == null then "" else . end) | tostring
            | gsub("[\\t\\r\\n]"; " ") | if . == "" then ph else . end;
          .[] | [(.session_id | cell($pad)), (.cwd | cell($pad)), (.account | cell($pad)),
                 (.pid | cell($pad))] | @tsv' "$1" 2>/dev/null)"
  while IFS=$'\t' read -r sid cwd acct pid; do
    [ -n "$sid" ] && [ "$sid" != "$HB_PAD" ] || continue
    [ "$cwd" = "$HB_PAD" ] && cwd=""; [ "$acct" = "$HB_PAD" ] && acct=""; [ "$pid" = "$HB_PAD" ] && pid=""
    model=""; effort=""; pm=""; br=""
    tr="$(_hb_transcript "$sid" "$cwd")"; tacct="${tr%%	*}"; tpath="${tr#*	}"
    if [ -n "$tr" ] && [ -f "$tpath" ]; then
      acct="$tacct"
      fields="$(tail -n "${CC_HB_TRANSCRIPT_TAIL:-1500}" "$tpath" 2>/dev/null | jq -Rrn '
        [inputs | fromjson? | select(type == "object")] as $r
        | ($r | map(select(.type == "assistant" and (.isSidechain | not)
                           and ((.message.model // "") | . != "" and . != "<synthetic>"))) | last) as $a
        | ($r | map(select(.type == "permission-mode")) | last | .permissionMode // "") as $pm
        | [($a.message.model // ""), ($a.effort // ""), $pm] | @tsv' 2>/dev/null)"
      model="$(printf '%s' "$fields" | cut -f1)"; effort="$(printf '%s' "$fields" | cut -f2)"
      pm="$(printf '%s' "$fields" | cut -f3)"
    fi
    if [ -n "$pid" ]; then
      args="$(awk -v p="$pid" '$1 == p { $1 = ""; $2 = ""; print; exit }' "$2" 2>/dev/null)"
      [ -n "$model" ] || model="$(_hb_argv_flag "$args" --model)"
      [ -n "$effort" ] || effort="$(_hb_argv_flag "$args" --effort)"
      [ -n "$pm" ] || pm="$(_hb_argv_flag "$args" --permission-mode)"
    fi
    if [ -n "$cwd" ] && [ -d "$cwd" ]; then
      # symbolic-ref: empty on a detached HEAD, and right on a branch with no commit yet.
      br="$(_hb_to 5 git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null </dev/null)"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$sid" "$(_hb_cell "$acct")" "$(_hb_cell "$model")" \
      "$(_hb_cell "$effort")" "$(_hb_cell "$pm")" "$(_hb_cell "$br")" "$(_hb_cell "$pid")"
  done <<EOF
$rows
EOF
}

# _hb_bg_tsv <roster.json> <ps.txt> <lsof.txt> — hb.bg.tsv rows on stdout.
_hb_bg_tsv() {
  local claims mb ab f k p n
  claims="$(jq -r '.[] | select((.pid // "") != "" and (.session_id // "") != "")
                  | "\(.pid)\t\(.session_id)"' "$1" 2>/dev/null)"
  mb="${CC_HB_MAILBOX_DIR:-$HOME/.claude/mailbox}"
  # watchers: "<pid>\t<key>" for each .watching file whose pid is alive
  {
    for f in "$mb"/*.watching; do
      [ -f "$f" ] || continue
      p="$(sed -n 's/^pid=\([0-9][0-9]*\).*/\1/p' "$f" 2>/dev/null | head -n 1)"
      [ -n "$p" ] && kill -0 "$p" 2>/dev/null || continue
      k="${f##*/}"; printf 'W\t%s\t%s\n' "$p" "${k%.watching}"
    done
    printf '%s\n' "$claims" | awk -F'\t' 'NF == 2 { print "C\t" $1 "\t" $2 }'
    awk '/^p[0-9]+$/ { p = substr($0, 2); next } /^n/ && p != "" { print "L\t" p "\t" substr($0, 2) }' "$3" 2>/dev/null
    awk '{ pid = $1; ppid = $2; $1 = ""; $2 = ""; sub(/^  */, ""); gsub(/\t/, " "); print "P\t" pid "\t" ppid "\t" substr($0, 1, 400) }' "$2" 2>/dev/null
  } | awk -F'\t' -v pad="$HB_PAD" '
      $1 == "C" { sid[$2] = $3; next }
      $1 == "W" { watch[$2] = $3; next }
      $1 == "L" { if (!(($2 SUBSEP $3) in seenl)) { seenl[$2 SUBSEP $3] = 1; ports[$2] = ports[$2] (ports[$2] == "" ? "" : " ") $3 } next }
      $1 == "P" { parent[$2] = $3; args[$2] = $4; order[++n] = $2; next }
      END {
        for (i = 1; i <= n; i++) {
          p = order[i]; if (p in sid) continue
          a = parent[p]; hops = 0; owner = ""
          while (a != "" && a != "0" && a != "1" && hops < 64) { if (a in sid) { owner = a; break } a = parent[a]; hops++ }
          if (owner == "") { if (p in watch) print pad "\t" pad "\twatching\t" p "\t" watch[p]; continue }
          if (p in watch) print sid[owner] "\t" owner "\twatching\t" p "\t" watch[p]
          else if (tolower(args[p]) !~ /mcp/) print sid[owner] "\t" owner "\tchild\t" p "\t" args[p]
          if (p in ports) print sid[owner] "\t" owner "\tlisten\t" p "\t" ports[p]
        } }'
  ab="${CC_HB_AGENT_BROWSER_DIR:-$HOME/.agent-browser}"
  for f in "$ab"/*.pid; do
    [ -f "$f" ] || continue
    p="$(tr -cd '0-9' < "$f" 2>/dev/null)"
    [ -n "$p" ] && kill -0 "$p" 2>/dev/null || continue
    n="${f##*/}"; printf '%s\t%s\tagent-browser\t%s\t%s\n' "$HB_PAD" "$HB_PAD" "$p" "${n%.pid}"
  done
}

# _hb_roles_tsv <all-roster.json> — role  pane  sid, one row per cc-roles file.
_hb_roles_tsv() {
  local rd f pane sid
  rd="${CC_ROLES_DIR:-$HOME/.claude/cc-roles}"
  for f in "$rd"/*; do
    [ -f "$f" ] || continue
    pane="$(head -n 1 "$f" 2>/dev/null | tr -d '[:space:]')"
    sid=""
    [ -n "$pane" ] && sid="$(jq -r --arg p "$pane" '[.[] | select((.paneUUID // "" | tostring) == $p) | .session_id][0] // ""' "$1" 2>/dev/null)"
    printf '%s\t%s\t%s\n' "${f##*/}" "$(_hb_cell "$pane")" "$(_hb_cell "$sid")"
  done
}

hb_tick() {
  local root now uuid sb kb tmpd kps kp dir sock pw ok=0 failed=0
  root="$(hb_root)"; now="${CC_HB_NOW:-$(date +%s)}"
  uuid="$(_hb_bootuuid)"; [ -n "$uuid" ] || uuid=nouuid
  sb="$(_hb_sessions_bin)"
  [ -n "$sb" ] && [ -x "$sb" ] || { echo "restore-heartbeat: no cc-sessions — no heartbeat this tick" >&2; return 2; }
  kb="$(_hb_kitten_bin)"
  tmpd="$(mktemp -d "${TMPDIR:-/tmp}/hb.XXXXXX" 2>/dev/null)" || return 2
  # A roster that does not parse as an array is no evidence: write nothing, keep every last good file.
  if ! _hb_to 30 "$sb" --json > "$tmpd/all.json" 2>/dev/null \
     || ! jq -e 'type == "array"' "$tmpd/all.json" >/dev/null 2>&1; then
    rm -rf "$tmpd"; echo "restore-heartbeat: cc-sessions --json failed or did not parse — kept the last heartbeat" >&2
    return 2
  fi
  _hb_to 10 "${CC_HB_PS_BIN:-/bin/ps}" -axo pid=,ppid=,args= > "$tmpd/ps.txt" 2>/dev/null || : > "$tmpd/ps.txt"
  _hb_to 10 "${CC_HB_LSOF_BIN:-/usr/sbin/lsof}" -nP -iTCP -sTCP:LISTEN -Fpn > "$tmpd/lsof.txt" 2>/dev/null || :
  # Every LIVE kitty: those the sessions name, plus those with a directory this boot that are still up
  # with no session left (their roster becomes [], which is an answer: nothing was live there).
  kps="$( { jq -r '.[] | (.kitty_pid // 0) | tostring' "$tmpd/all.json" 2>/dev/null
            for dir in "$root/$uuid"/*; do [ -d "$dir" ] && printf '%s\n' "${dir##*/}"; done; } \
          | grep -E '^[0-9]+$' | sort -u)"
  for kp in $kps; do
    # A dead kitty's last heartbeat is the evidence of its fleet: never overwrite it.
    if [ "$kp" != 0 ]; then kill -0 "$kp" 2>/dev/null || continue; fi
    dir="$root/$uuid/$kp"
    ( umask 077; mkdir -p "$dir" ) 2>/dev/null || { failed=$((failed + 1)); continue; }
    if ! jq --argjson k "$kp" '[.[] | select(((.kitty_pid // 0) | tonumber? // 0) == $k)]' "$tmpd/all.json" \
           > "$dir/.hb.roster.json.tmp" 2>/dev/null || ! _hb_mv "$dir/.hb.roster.json.tmp" "$dir/hb.roster.json"; then
      failed=$((failed + 1)); continue
    fi
    _hb_session_tsv "$dir/hb.roster.json" "$tmpd/ps.txt" > "$dir/.hb.session.tsv.tmp" 2>/dev/null \
      && _hb_mv "$dir/.hb.session.tsv.tmp" "$dir/hb.session.tsv"
    if [ "$kp" != 0 ] && [ -n "$kb" ] && [ -x "$kb" ]; then
      sock="$(jq -r '[.[] | .kitty_listen_on // empty][0] // ""' "$dir/hb.roster.json" 2>/dev/null)"
      [ -n "$sock" ] || sock="unix:/tmp/kitty-$kp"
      if _hb_to 5 "$kb" @ --to "$sock" ls > "$dir/.hb.kitty-ls.json.tmp" 2>/dev/null \
         && jq -e 'type == "array"' "$dir/.hb.kitty-ls.json.tmp" >/dev/null 2>&1; then
        _hb_mv "$dir/.hb.kitty-ls.json.tmp" "$dir/hb.kitty-ls.json"
      else
        rm -f "$dir/.hb.kitty-ls.json.tmp"
      fi
    fi
    # The display of each OS window in the tree. A short or malformed answer keeps the last good file.
    if [ "$kp" != 0 ] && [ -f "$dir/hb.kitty-ls.json" ]; then
      pw="$(jq -r '.[]? | .platform_window_id // empty' "$dir/hb.kitty-ls.json" 2>/dev/null | grep -E '^[0-9]+$' | tr '\n' ' ')"
      # shellcheck disable=SC2086  # $pw is a space-separated list of numeric window ids
      if [ -n "$pw" ] && hb_display_probe $pw > "$dir/.hb.displays.tsv.tmp" 2>/dev/null \
         && [ -s "$dir/.hb.displays.tsv.tmp" ] \
         && awk -F'\t' 'NF != 11 || $1 !~ /^[0-9]+$/ { bad = 1 } END { exit bad }' "$dir/.hb.displays.tsv.tmp"; then
        _hb_mv "$dir/.hb.displays.tsv.tmp" "$dir/hb.displays.tsv"
      else
        rm -f "$dir/.hb.displays.tsv.tmp"
      fi
    fi
    _hb_bg_tsv "$dir/hb.roster.json" "$tmpd/ps.txt" "$tmpd/lsof.txt" > "$dir/.hb.bg.tsv.tmp" 2>/dev/null \
      && _hb_mv "$dir/.hb.bg.tsv.tmp" "$dir/hb.bg.tsv"
    _hb_roles_tsv "$tmpd/all.json" > "$dir/.hb.roles.tsv.tmp" 2>/dev/null \
      && _hb_mv "$dir/.hb.roles.tsv.tmp" "$dir/hb.roles.tsv"
    printf '%s\n' "$now" > "$dir/.hb.start.tmp" 2>/dev/null && _hb_mv "$dir/.hb.start.tmp" "$dir/hb.start" \
      && ok=$((ok + 1))
  done
  rm -rf "$tmpd"
  hb_prune
  [ "$failed" -gt 0 ] && return 2
  [ "$ok" -gt 0 ] && return 0
  return 1
}

hb_prune() {
  local root now keep d st
  root="$(hb_root)"; now="${CC_HB_NOW:-$(date +%s)}"
  case "$root" in ''|/) return 0 ;; esac
  keep=$(( ${CC_HB_RETAIN_DAYS:-7} * 86400 ))
  for d in "$root"/*/*; do
    [ -d "$d" ] && [ ! -L "$d" ] || continue
    st="$(_hb_start_of "$d")"
    [ -n "$st" ] || st="$(stat -f %m "$d" 2>/dev/null)"
    case "$st" in ''|*[!0-9]*) continue ;; esac
    [ $((now - st)) -gt "$keep" ] && rm -rf "${root:?}/${d#"$root"/}"
  done
  for d in "$root"/*; do [ -d "$d" ] && [ ! -L "$d" ] && rmdir "$d" 2>/dev/null; done
  return 0
}

hb_pick() {
  local base="$1" lo="$2" hi="$3" dead="${4:-}" d st max=0 cands=""
  case "$lo$hi" in *[!0-9]*|'') return 1 ;; esac
  for d in "$base" "$base"/* "$base"/*/*; do
    [ -f "$d/hb.roster.json" ] || continue
    st="$(_hb_start_of "$d")"; [ -n "$st" ] || continue
    [ "$st" -gt "$lo" ] && [ "$st" -le "$hi" ] || continue
    if [ "$dead" = --dead-kitty ]; then
      case "${d##*/}" in 0|''|*[!0-9]*) continue ;; *) kill -0 "${d##*/}" 2>/dev/null && continue ;; esac
    fi
    cands="${cands}${st}	${d}
"
    [ "$st" -gt "$max" ] && max="$st"
  done
  [ "$max" -gt 0 ] || return 1
  # Same tick = within half a tick of the newest: two kittys live at the cut both come back; a kitty
  # that died earlier in that boot (its fleet already moved on) does not.
  printf '%s' "$cands" | awk -F'\t' -v m="$max" -v s="${CC_HB_UNION_SLACK:-150}" 'NF == 2 && $1 >= m - s' | sort -u
}
