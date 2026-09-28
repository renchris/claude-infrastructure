#!/usr/bin/env bash
# episodic_cue.sh — the narrow episodic cue (truememory-2026-09-27.md §3.18, item #18). Sourced.
#
# WHAT: `episodic_cue_line "<prompt>"` prints ONE line pointing at `claude-search` when a typed
# prompt refers to earlier work ("like we did before", "a week ago", "we may have done this
# before"), and prints nothing otherwise. It injects NOTHING from other sessions: the cue names a
# search, and the agent decides whether to run it.
#
# WHY NARROW: the broad cue set (before/again/…) fired on 31% of typed prompts, mostly long briefs,
# at an estimated precision near 6% (premise-episodic-session-recall.md:30-33). This set is tuned to
# catch the 4 cited misses (gap-2.md:54-57: #78 #88 #106 #110) at a fire rate near 1.5% of typed
# prompts; the measured numbers are in the commit that added this file.
#
# PROVISIONAL (research §5.17 / #35 found no gain for push consumers): it ships only because every
# fire is logged and scripts/episodic-cue-outcome.py measures, nightly, whether a fire was followed
# by a claude-search. Its adoption rides on that log.
#
# Contract:
#   - Eligibility mirrors the ruling shadow (hooks/memory-nudge.sh:62-66): a prompt starting with
#     `<`, one carrying HANDOFF-ENGAGE/HANDOFF-PING, one over 4,000 chars, or a blank one is not
#     typed and never fires.
#   - Every call writes ONE IDL row under its own name `memory-nudge:episodic` (X2): fired <pattern>,
#     or abstained no-match / not-typed / kill-switch / classify-error. The IDL path is $CC_IDL, else
#     $HOME/.claude/autonomy/idl.jsonl; the session id is the caller's $SID.
#   - Each fire appends {ts,sid,cwd,pattern,nouns,prompt_len,prompt_sha1} to
#     $HOME/.claude/state/episodic-cue.jsonl (X4: one physical dir). $CWD is the caller's cwd.
#   - Kill switch CC_EPISODIC_CUE=off (logged as abstained kill-switch; prints nothing).
#   - Nothing here writes stdout except the cue line, and every failure is swallowed.
# Portable to /bin/bash 3.2. `^` in jq's Oniguruma is start-of-LINE, so start-of-string is \A.

# Deref this file's own path (the live layer links it per file) so idl-log.sh resolves beside the
# REAL file, in the checkout, even when only this file is linked (X1; hooks/memory-nudge.sh:120-134).
_ec_deref() {
  local p="$1" t n=0
  readlink -f "$p" 2>/dev/null && return 0
  while [ -L "$p" ] && [ "$n" -lt 20 ]; do
    t="$(readlink "$p")"
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
    n=$(( n + 1 ))
  done
  printf '%s\n' "$p"
}
_EC_LIB_DIR="$(dirname "$(_ec_deref "${BASH_SOURCE[0]}")")"

# One jq program: eligibility, the first matching pattern, and the noun query, joined by U+001F.
# Nouns: lowercase [a-z0-9-] words of 3+ chars (single-quote safe by construction), stopwords, the
# cue's own trigger vocabulary and the operator's filler words dropped, deduped, at most 6.
# shellcheck disable=SC2016  # jq program, not shell
_EC_JQ='
def pats: [
  {n:"last-session",      r:"\\b(last|earlier|an? (previous|prior|earlier|past)) (session|conversation|chat)s?\\b"},
  {n:"like-we-did",       r:"\\blike we did\\b"},
  {n:"did-we",            r:"\\b(did|have) we (ever |already |previously )?(do|did|build|built|use|used|try|tried|discuss|discussed|research|researched|figure|figured|solve|solved|fix|fixed|run|ran|make|made|write|wrote|find|found|look|looked)\\b"},
  {n:"used-it-times",     r:"\\bused (it|this|that) ([0-9]+(-[0-9]+)?|a few|a couple of|several|two|three) times\\b"},
  {n:"time-ago",          r:"\\b(a|one|two|three|a few|a couple of|last) (day|days|week|weeks|month|months) ago\\b"},
  {n:"retrieve-research", r:"\\b(retrieve|recall|pull up|dig up) (that|the|our) [^.?!]{0,60}\\b(research|investigation|analysis|findings)\\b"},
  {n:"done-before",       r:"\\b(may|might|probably|already|must) have done (this|that|it) before\\b"},
  {n:"we-did-before",     r:"\\bwe (did|tried|built|discussed|researched|solved) (this|that|it) (before|previously|already)\\b"}
];
def stop: ("a about above after again ago all already also am an and any are as at be because been before being below between both but by can cannot could did do does doing done down during each earlier few for from further had has have having he her here hers him his how i if in into is it its itself just last let like may me might more most must my myself no nor not now of off on once only or other our ours out over own past please previous prior probably pull quite really recall remember retrieve run same session sessions she should so some such than that the their them then there these they this those through time times to too under until up us use used very was way we week weeks month months day days were what when where which while who whom why will with would you your yours yes ok okay one two three four couple several made make get got know think want need see look find found chat conversation just sat given asked completed actionable results work lot able absolute perfection percentile improve check feel few thanks everything something thing things sure maybe better good great new old still even much many well back going getting entire ultracode comprehensively exhaustively investigate maximally towards however https http www com"
           | split(" ") | map({key: ., value: true}) | from_entries);
# Identifier-like words (any capital: a name, a product, an acronym) are ranked ahead of plain words,
# each group in prompt order, so the query of a long prompt keeps its proper nouns; numbers are
# dropped. (No apostrophes in these comments: this program is a single-quoted shell string.)
def nouns($p):
  stop as $s
  | [$p | scan("[A-Za-z0-9][A-Za-z0-9-]*[A-Za-z0-9]")
      | {w: ascii_downcase, id: test("[A-Z]")}
      | select((.w | length) >= 3 and (.w | test("\\A[0-9]") | not) and ($s[.w] | not))]
  | ([.[] | select(.id)] + [.[] | select(.id | not)]) | map(.w)
  | reduce .[] as $w ([]; if any(.[]; . == $w) then . else . + [$w] end)
  | .[:6] | join(" ");
def verdict($p):
  if ($p | type) != "string" then ["not-typed", ""]
  elif ($p | length) > 4000 or ($p | test("\\A\\s*<")) or ($p | test("HANDOFF-(ENGAGE|PING)"))
       or ($p | test("\\S") | not) then ["not-typed", ""]
  else
    ([pats[] | select(. as $x | $p | test($x.r; "i")) | .n][0]) as $m
    | if $m == null then ["no-match", ""] else ["fired:" + $m, nouns($p)] end
  end;
(try verdict($p) catch ["classify-error", ""]) | join("\u001f")'

_ec_idl() { # <disposition> <reason> [extra-json]
  local idl="$_EC_LIB_DIR/idl-log.sh"
  [ -r "$idl" ] || return 0
  # shellcheck source=idl-log.sh
  # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
  . "$idl" || return 0
  idl_init "${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}" memory-nudge:episodic SID
  log_idl "$@"
}

episodic_cue_line() {
  local _ec_cue=""
  {
    local p="${1:-}" line v nouns pat sha row dir
    if [ "${CC_EPISODIC_CUE:-on}" = off ]; then
      _ec_idl abstained kill-switch
    else
      line="$(jq -rn --arg p "$p" "$_EC_JQ" 2>/dev/null)" || line=""
      [ -n "$line" ] || line="classify-error"
      IFS=$'\x1f' read -r v nouns <<< "$line" || true
      case "$v" in
        fired:*)
          pat="${v#fired:}"
          [ -n "$nouns" ] || nouns="<topic>"
          sha="$(printf '%s' "$p" | shasum -a 1 | cut -d' ' -f1)" || sha=""
          dir="$HOME/.claude/state"
          mkdir -p "$dir" || true
          row="$(jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sid "${SID:-?}" \
                  --arg cwd "${CWD:-$PWD}" --arg pattern "$pat" --arg nouns "$nouns" \
                  --argjson len "${#p}" --arg sha "$sha" \
                  '{ts:$ts,sid:$sid,cwd:$cwd,pattern:$pattern,nouns:$nouns,prompt_len:$len,prompt_sha1:$sha}')" \
            && [ -n "$row" ] && printf '%s\n' "$row" >> "$dir/episodic-cue.jsonl"
          _ec_idl fired "$pat" "$(jq -cn --arg p "$pat" --arg n "$nouns" '{pattern:$p,nouns:$n}')"
          _ec_cue="EPISODIC CUE: this prompt refers to earlier work. Before re-deriving it, search past sessions: claude-search '$nouns' (add --deep-search for chunk text; workflow results are indexed too)."
          ;;
        *) _ec_idl abstained "${v:-classify-error}" ;;
      esac
    fi
  } >/dev/null 2>&1 || true
  [ -z "$_ec_cue" ] || printf '%s\n' "$_ec_cue"
  return 0
}
