# shellcheck shell=bash
# lever-flags.sh — the bash 3.2 twin of hooks/lib/lever_flags.py: flag file, arm assignment, lineage.
# Contract and precedence are in lever_flags.py's docstring and docs/plans/USAGE_LEVERS.md § W7+ §3
# ("Flag file and arm lib"). The two libs MUST agree bit-for-bit on every arm, and
# tests/lever-flags.bats replays a corpus of units through both. Rules this file keeps identical:
#   · h = int(sha256(salt ":" unit)[:13], 16); every decision is an exact integer compare
#     (h*100 < pct * 2^52), which needs no float and fits bash's 64-bit arithmetic (h < 2^52).
#   · u (logged) = floor(h * 10^6 / 2^52) / 10^6, computed in two halves so nothing overflows.
#   · a lever entry is malformed (flag_src unreadable) on the same rules as _norm_lever: pct an
#     integral number 0..100, holdback 0..50, stage S0-S3, mode shadow|live|off, salts [A-Za-z0-9._-].
# Forks per call: one jq (the flag file), one sha256sum per hash, plus stat/date only for a live
# lever with pct > 0 (the dead-man read). Nothing here prints unless a function says so.
#
#   lf_arm <lever> <unit>   → sets LF_ARM LF_U LF_SPLIT LF_VARIANT LF_VARIANT_ID LF_PCT_EFF LF_SRC
#                             LF_STAGE LF_MODE LF_REV (JSON) LF_PARAMS_ID LF_THR (JSON); returns 0
#   lf_arm_json             → prints the arm just computed as one JSON object (lever_flags.arm's keys)
#   lf_lineage <sid>        → sets LF_LINEAGE LF_LINEAGE_SRC (env → arms/<sid> cache → the python
#                             resolver, which owns the pane file and proc cache → own sid)
#   lf_hash <salt> <unit>   → sets LF_H (decimal) and LF_U6 (0.xxxxxx)

if [ -z "${_LF_LOADED:-}" ]; then
_LF_LOADED=1
_lf_dir="${BASH_SOURCE[0]%/*}"; [ "$_lf_dir" = "${BASH_SOURCE[0]}" ] && _lf_dir=.
LF_SHA256=/sbin/sha256sum; [ -x "$LF_SHA256" ] || LF_SHA256=sha256sum
LF_TWO52=4503599627370496

lf_state_dir() { printf '%s' "${CC_LEVER_STATE_DIR:-$HOME/.claude/state/levers}"; }

lf_hook_kill_var() {
  case "$1" in D1) echo CC_IRS ;; D2) echo CC_WORKFLOW_SHADOW ;; D3) echo CC_IDLE_KEEPALIVE ;; D4) echo CC_SUBAGENT_LONG_BASH ;; esac
}
lf_decision() {
  case "$1" in D1) echo 43da49891e75 ;; D2) echo a4c54d1744d1 ;; D3) echo c0f9d5368147 ;; D4) echo 3df527edd333 ;; esac
}

lf_hash() { # <salt> <unit> → LF_H LF_U6
  local hex q r x y
  hex="$(printf '%s:%s' "$1" "$2" | "$LF_SHA256" 2>/dev/null)"
  hex="${hex:0:13}"
  case "$hex" in *[!0-9a-f]*|'') LF_H=""; LF_U6=""; return 1 ;; esac
  [ ${#hex} -eq 13 ] || { LF_H=""; LF_U6=""; return 1; }
  LF_H=$((16#$hex))
  q=$((LF_H >> 26)); r=$((LF_H & 67108863))
  x=$((q * 1000000)); y=$((r * 1000000))
  LF_U6="$(printf '0.%06d' $(( (x + (y >> 26)) >> 26 )))"
  return 0
}

lf_below() { [ $(( $1 * 100 )) -lt $(( $2 * LF_TWO52 )) ]; } # <h> <pct> → u < pct/100

# One jq read of the flag file for one lever. Fields joined by 0x1f; strings that are only logged
# arrive JSON-encoded, salts arrive raw (their charset is validated, so they carry no separator).
# shellcheck disable=SC2016  # a jq program: its $vars are jq's, not the shell's
_LF_JQ='
def intv($lo; $hi): (type == "number") and (. == floor) and (. >= $lo) and (. <= $hi);
def salt: (type == "string") and test("^[A-Za-z0-9._-]*$");
if length != 1 or (.[0] | type) != "object" or (.[0].levers | type) != "object" then "U"
else .[0] as $d | ($d.levers[$L]) as $e |
  if ($e | type) != "object" then "U"
  else
    (if $e | has("stage") then $e.stage else "S0" end) as $st |
    (if $e | has("mode") then $e.mode else "shadow" end) as $mo |
    (if $e | has("pct") then $e.pct else 0 end) as $p |
    (if $e | has("holdback") then $e.holdback else 0 end) as $hb |
    (if $e | has("salt") then $e.salt else "" end) as $s |
    (if $e | has("split_salt") then $e.split_salt else "" end) as $ss |
    $e.candidate as $c | $e.trip as $t |
    if (["S0","S1","S2","S3"] | any(. == $st) | not) or (["shadow","live","off"] | any(. == $mo) | not)
       or ($p | intv(0; 100) | not) or ($hb | intv(0; 50) | not) or ($s | salt | not) or ($ss | salt | not)
       or ($c != null and (($c | type) != "object"
            or ((if $c | has("share") then $c.share else 0 end) | intv(0; 100) | not)
            or ((if $c | has("round_salt") then $c.round_salt else "" end) | salt | not)))
       or ($t != null and ($t | type) != "object")
    then "U"
    else ["F", $st, $mo, ($p | floor | tostring), ($hb | floor | tostring), $s, $ss,
          ($e.params_id | tojson), ($e.thresholds_sha | tojson), ($d.rev | tojson),
          (if ($t | type) == "object" and (($t.acked_at | type) == "string" and $t.acked_at != "" | not) then "1" else "0" end),
          (if $c == null then "0" else "1" end), ($c.id | tojson),
          (if $c == null then "0" else ((if $c | has("share") then $c.share else 0 end) | floor | tostring) end),
          (if $c == null then "" else (if $c | has("round_salt") then $c.round_salt else "" end) end)]
         | join("\u001f")
    end
  end
end'

lf_read() { # <lever> → LF_SRC + entry fields (LF_E_*)
  local f out
  f="${CC_LEVER_FLAGS:-$(lf_state_dir)/flags.json}"
  LF_E_OK=0; LF_STAGE=S0; LF_MODE=shadow; LF_E_PCT=0; LF_E_HB=0; LF_E_SALT=""; LF_E_SSALT=""
  LF_PARAMS_ID=null; LF_THR=null; LF_REV=null; LF_E_TRIP=0; LF_E_CAND=0; LF_E_CID=null; LF_E_CSHARE=0; LF_E_CSALT=""
  if [ ! -e "$f" ] && [ ! -L "$f" ]; then LF_SRC=default; return 0; fi
  out="$(jq -rs --arg L "$1" "$_LF_JQ" < "$f" 2>/dev/null)" || out=""
  case "$out" in F*) ;; *) LF_SRC=unreadable; return 0 ;; esac
  local IFS=$'\037' tag
  # shellcheck disable=SC2034  # the LF_* fields are this lib's output
  read -r tag LF_STAGE LF_MODE LF_E_PCT LF_E_HB LF_E_SALT LF_E_SSALT LF_PARAMS_ID LF_THR LF_REV LF_E_TRIP LF_E_CAND LF_E_CID LF_E_CSHARE LF_E_CSALT <<< "$out"
  LF_SRC='file'; LF_E_OK=1
  return 0
}

lf_heartbeat_fresh() {
  local hb m now max
  hb="${CC_LEVER_HEARTBEAT:-$(lf_state_dir)/guard.heartbeat}"
  [ -e "$hb" ] || return 1
  m="$(stat -f %m "$hb" 2>/dev/null || stat -c %Y "$hb" 2>/dev/null)" || return 1
  case "$m" in ''|*[!0-9]*) return 1 ;; esac
  now="$(date +%s)"; max="${CC_LEVER_DEADMAN_S:-1800}"
  case "$max" in ''|*[!0-9]*) max=1800 ;; esac
  [ $((now - m)) -le "$max" ]
}

lf_arm() { # <lever> <unit>
  local lv="$1" unit="$2" kv v n p
  LF_LEVER="$lv"; LF_UNIT="$unit"; LF_ARM=ctrl; LF_U=""; LF_SPLIT=""; LF_VARIANT=""; LF_VARIANT_ID=null; LF_PCT_EFF=0
  case "$lv" in D1|D2|D3|D4) ;; *) return 2 ;; esac
  kv="$(lf_hook_kill_var "$lv")"
  eval "v=\${$kv:-}"
  if [ "$v" = off ]; then
    LF_SRC=hook-kill; LF_ARM=off; LF_STAGE=S0; LF_MODE=shadow; LF_REV=null; LF_PARAMS_ID=null; LF_THR=null; return 0
  fi
  if [ "${CC_LEVER_EXCLUDE:-}" = 1 ]; then
    LF_SRC=excluded; LF_ARM=excluded; LF_STAGE=S0; LF_MODE=shadow; LF_REV=null; LF_PARAMS_ID=null; LF_THR=null; return 0
  fi
  lf_read "$lv"
  for n in CC_LEVER_ALL "CC_LEVER_$lv"; do
    eval "v=\${$n:-}"
    case "$v" in off|control) LF_SRC="env-$v"; break ;; esac
  done
  if [ "$LF_E_OK" = 1 ] && [ "$LF_SRC" = file ] && [ "$LF_MODE" = live ] && [ "$LF_E_PCT" -gt 0 ] && [ "$LF_E_TRIP" = 0 ]; then
    if lf_heartbeat_fresh; then LF_PCT_EFF="$LF_E_PCT"; else LF_SRC=deadman; fi
  fi
  [ "$LF_E_OK" = 1 ] && [ -n "$LF_E_SALT" ] || return 0
  lf_hash "$LF_E_SALT" "$unit" || return 0
  local h="$LF_H"; LF_U="$LF_U6"; p="$LF_PCT_EFF"
  if [ "$p" -gt 0 ] && [ "$LF_E_HB" -gt 0 ] && ! lf_below "$h" $((100 - LF_E_HB)); then
    LF_ARM=holdback
  elif lf_below "$h" "$p"; then
    LF_ARM=treat
  fi
  if [ -n "$LF_E_SSALT" ] && lf_hash "$LF_E_SSALT" "$unit"; then
    if lf_below "$LF_H" 50; then LF_SPLIT='test'; else LF_SPLIT='train'; fi
  fi
  if [ "$LF_ARM" = treat ] && [ "$LF_E_CAND" = 1 ] && lf_hash "$LF_E_CSALT" "$unit"; then
    if lf_below "$LF_H" "$LF_E_CSHARE"; then LF_VARIANT=cand; LF_VARIANT_ID="$LF_E_CID"
    else LF_VARIANT=inc; LF_VARIANT_ID="$LF_PARAMS_ID"; fi
  fi
  return 0
}

lf_jstr() { # <s> → a JSON string (units and sids: escape \ and ", drop control bytes)
  local s="${1//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//[[:cntrl:]]/}"
  printf '"%s"' "$s"
}
lf_jopt() { if [ -n "$1" ]; then lf_jstr "$1"; else printf 'null'; fi; }

lf_arm_json() {
  local u="${LF_U:-null}"
  printf '{"arm":"%s","decision":"%s","flag_rev":%s,"flag_src":"%s","lever":"%s","mode":"%s","params_id":%s,"pct_eff":%s,"split":%s,"stage":"%s","thresholds_sha":%s,"u":%s,"unit":%s,"variant":%s,"variant_id":%s}' \
    "$LF_ARM" "$(lf_decision "$LF_LEVER")" "$LF_REV" "$LF_SRC" "$LF_LEVER" "$LF_MODE" "$LF_PARAMS_ID" "$LF_PCT_EFF" \
    "$(lf_jopt "$LF_SPLIT")" "$LF_STAGE" "$LF_THR" "$u" "$(lf_jstr "$LF_UNIT")" "$(lf_jopt "$LF_VARIANT")" "$LF_VARIANT_ID"
}

lf_safe() { case "$1" in ''|*[!A-Za-z0-9._:-]*|*..*) return 1 ;; esac; [ ${#1} -le 128 ]; }

# shellcheck disable=SC2034  # LF_LINEAGE and LF_LINEAGE_SRC are this function's output
lf_lineage() { # <sid> → LF_LINEAGE LF_LINEAGE_SRC
  local sid="$1" line w root="" src="" out
  LF_LINEAGE="$sid"; LF_LINEAGE_SRC=self
  if lf_safe "${CC_LEVER_LINEAGE:-}"; then LF_LINEAGE="$CC_LEVER_LINEAGE"; LF_LINEAGE_SRC='env'; return 0; fi
  lf_safe "$sid" || return 0
  if [ -r "$(lf_state_dir)/arms/$sid" ]; then
    IFS= read -r line < "$(lf_state_dir)/arms/$sid" || true
    for w in $line; do
      case "$w" in lineage=*) root="${w#lineage=}" ;; src=*) src="${w#src=}" ;; esac
    done
    if lf_safe "$root"; then LF_LINEAGE="$root"; LF_LINEAGE_SRC="${src:-cache}"; return 0; fi
  fi
  out="$(/usr/bin/python3 -I "$_lf_dir/lever_flags.py" lineage --sid "$sid" 2>/dev/null)" || out=""
  root="${out%%	*}"; src="${out#*	}"
  if lf_safe "$root" && [ "$out" != "$root" ]; then LF_LINEAGE="$root"; LF_LINEAGE_SRC="$src"; fi
  return 0
}
fi
