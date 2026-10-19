#!/bin/bash
# UserPromptSubmit Hook — Memory Crystallization Nudge
#
# Periodic in-session reminder (every MEMORY_NUDGE_INTERVAL prompts, default 12)
# to persist DURABLE knowledge to MEMORY.md / a topic file, with the hermes-agent
# anti-capture list embedded. Fires while context is LIVE — UserPromptSubmit
# reaches the model MID-SESSION, while the context being nudged about is still in
# hand.
#
#   This used to read "the ONLY event whose additionalContext reaches the model
#   mid-session (Stop cannot inject; GH anthropics/claude-code#37559)". That is
#   STALE: measured 2026-08-08 on 2.1.220, Stop additionalContext DOES reach the
#   model (docs/research/final-response-shaping-2026-08-08.md). UserPromptSubmit
#   remains correct, and is now the stronger of two live options rather than the
#   only one — Stop fires when the turn is already over, and every model-facing
#   Stop channel forces an extra turn, so nudging there would arrive too late to
#   act on AND cost a round-trip.
#
# Adapted from hermes-agent agent/background_review.py (nudge_interval=10), minus
# the autonomous write: this NUDGES, the model decides + the human reviews.
#
# APPEND-TIME BUDGET (2026-07-31). The index is loaded with a hard read limit
# (24.4 KiB = 24985 B — superseded, see UNITS below); past it the loader SILENTLY DROPS THE TAIL — the NEWEST
# entries, i.e. a rule written today may never load again, and no reader can tell.
# Three manual compaction passes each re-inflated within days because nothing
# measured the budget at the moment of APPEND; the "<=200-char" line in the nudge
# below was prose with no measurement behind it (hooks measured 203 B avg on
# 2026-07-31 — the advisory was simply ignored). So this hook now MEASURES the
# live index every time it speaks and hands the model a byte budget it can act on,
# plus the cardinality ceiling that a byte budget alone cannot express.
# Every figure is computed at runtime: a hardcoded one decays against its subject.
#
# UNITS, CORRECTED 2026-08-15 (cc-backlog 7a56de4c54ab). Every figure below used to be RAW BYTES
# of the file on disk. The loader does not count those: it strips YAML frontmatter and block HTML
# comments, trims, and compares CHARACTERS (UTF-16 code units) against 25000 — plus a 200-LINE cap
# this hook never measured at all. On a dense index of `—`/`⇒`/`·` entries under a `--- … ---`
# header the raw read over-measures by a wide margin, so the alarm fired on a breach that had not
# happened and the rotor it actuates archived entries that still fit. The derivation and the
# safe-direction argument live in hooks/lib/memory-index-measure.sh, which is now the ONE measure
# this hook, the PreToolUse gate and cc-memory-rotate all read. Constants tuned in bytes
# (HOOK_TARGET, HEADROOM_TARGET) are now read as chars — they are advisory floors feeding a
# runtime-derived allowance (see EFF_TARGET), so the ~10% change of meaning does not decide
# anything the code asserts.
set -euo pipefail
# Per-hook timing stamps (hooks/lib/hook-timing.sh; README §5 Wave 7, A9-F9): two builtin file
# writes, no fork — session-beat's detached worker folds them into ~/.claude/logs/hook-timing.jsonl.
# [ -f ] first: under `set -e`, bash 3.2 EXITS the hook when `.` cannot find its file, even
# inside an `if` — a missing lib must cost the stamp, never the hook (measured 2026-10-19).
_ht_l="${BASH_SOURCE[0]%/*}/lib/hook-timing.sh"
# shellcheck source=lib/hook-timing.sh disable=SC1091  # runtime-resolved beside this file
if [ -f "$_ht_l" ] && . "$_ht_l" 2>/dev/null; then ht_begin memory-nudge; fi

# `0` is the documented kill switch and exits silently. Anything that is not a non-negative
# integer (`abc`, `-3`, `12x`) is a typo, not a request to switch the nudge off, so it falls back to
# the default 12. The old `[ -gt 0 ] || exit 0` read every such typo as the kill switch and the
# nudge went quiet with nothing to say why (truememory-2026-09-27.md §3.3). `10#` strips leading
# zeros, which bash arithmetic would otherwise read as octal (`012` = 10).
INTERVAL="${MEMORY_NUDGE_INTERVAL:-12}"
case "$INTERVAL" in ''|*[!0-9]*) INTERVAL=12 ;; esac
INTERVAL=$(( 10#$INTERVAL ))
[ "$INTERVAL" -gt 0 ] || exit 0

INPUT=$(cat)
# ── RULING SHADOW classifier (truememory-2026-09-27.md §3.23-3.27 "speech-act-nudge-trigger", #26) ──
# Folded into the ONE jq call that already reads session_id, so scoring every prompt costs no extra
# fork. It emits sid, verdict, pattern, excerpt and prompt length joined by U+001F (a non-whitespace
# IFS, so an empty field stays empty). SHADOW ONLY: the verdict is logged below and never reaches
# stdout. Restatement patterns are tried first, so "don't forget, i told you" is a restatement.
# Eligibility: a prompt starting with `<` (task-notification, teammate-message, system tags), one
# carrying HANDOFF-ENGAGE/HANDOFF-PING, one over 4,000 chars (a brief) or a blank one is not typed.
# No quoted-span stripping (TrueMemory's _QUOTED_SPAN_RE eats contractions, MEASURED). `^` in jq's
# Oniguruma is start-of-string, so sentence starts are spelled \A, after [.!?] or after a newline.
# A classifier error cannot cost the session id: `try` turns it into the verdict classify-error.
# shellcheck disable=SC2016  # jq program, not shell: nothing in it is meant to expand
_MN_RULING_JQ='
def rules: [
  {c:"restatement", n:"remember",            r:"\\bremember\\b[:,]?(?!\\s+(when|what|how|why|where|who|if|that)\\b)"},
  {c:"restatement", n:"from-now-on",         r:"\\bfrom now on\\b"},
  {c:"restatement", n:"i-told-you",          r:"\\bi told you\\b"},
  {c:"restatement", n:"keep-forgetting",     r:"\\bkeep forgetting\\b"},
  {c:"ruling",      n:"we-adverb",           r:"\\bwe (always|just|never|don[\u0027\u2019]t|do not|should always|should never)\\b"},
  {c:"ruling",      n:"sentence-imperative", r:"(\\A\\s*|[.!?]\\s+|\\n\\s*)(always|never|don[\u0027\u2019]t|do not|stop|make sure|going forward)\\b"},
  {c:"ruling",      n:"the-rule-is",         r:"\\bthe rule is\\b"},
  {c:"ruling",      n:"every-time-you",      r:"\\bevery time you\\b"}
];
def verdict($p):
  if ($p | type) != "string" then ["no-prompt", "-", "-"]
  elif ($p | length) > 4000 or ($p | test("\\A\\s*<")) or ($p | test("HANDOFF-(ENGAGE|PING)"))
       or ($p | test("\\S") | not) then ["not-typed", "-", "-"]
  else
    ([rules[] | . as $x | [$p | match($x.r; "i")][0] | select(. != null)
      | {c: $x.c, n: $x.n, o: .offset}][0]) as $m
    | if $m == null then ["no-match", "-", "-"]
      else ([$m.o - 120, 0] | max) as $s
        | [$m.c, $m.n, ($p[$s:$s + 300] | gsub("[[:cntrl:]]+"; " "))]
      end
  end;
(.session_id // "" | tostring | gsub("[[:cntrl:]]"; "/")) as $sid
| (try verdict(.prompt) catch ["classify-error", "-", "-"]) as $v
| ([$sid] + $v + [(.prompt | if type == "string" then length else 0 end | tostring),
                  (.cwd // "" | tostring | gsub("[\u001f\n]"; ""))] | join("\u001f"))
  + "\n" + (.prompt | if type == "string" then . else "" end)'
# ONE jq for everything this hook reads from stdin (load-hook-timeouts-2026-10-11, item 5): the
# classifier line above, then the cwd as its last field, then a newline and the RAW prompt for the
# episodic cue. Those used to be two more jq forks on every prompt. The prompt is last and taken as
# "everything after the first newline", so its own newlines and U+001F bytes survive; `jq -j` adds
# no newline and the `x` sentinel keeps the prompt's trailing newlines, which a bare $( ) strips.
_MN_RULING_LINE="$( { printf '%s' "$INPUT" | jq -j "$_MN_RULING_JQ" 2>/dev/null || true; }; printf x)"
_MN_RULING_LINE="${_MN_RULING_LINE%x}"
_mn_nl=$'\n'
_mn_prompt="${_MN_RULING_LINE#*"$_mn_nl"}"
[ "$_mn_prompt" != "$_MN_RULING_LINE" ] || _mn_prompt=""
_MN_RULING_LINE="${_MN_RULING_LINE%%"$_mn_nl"*}"
CWD=""
IFS=$'\x1f' read -r SID _MN_RV _MN_RPAT _MN_REXC _MN_RLEN CWD <<< "$_MN_RULING_LINE" || true
[ -z "$SID" ] && exit 0
# Defensive: session_id is a harness UUID; refuse anything with path/shell chars
case "$SID" in *[!a-zA-Z0-9_-]*) exit 0 ;; esac

# Counter lives under the config dir actually in play — a hardcoded ~/.claude
# splits the count from the session when CLAUDE_CONFIG_DIR points elsewhere.
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE_DIR="${MEMORY_NUDGE_STATE_DIR:-$CFG/state}"
[ -d "$STATE_DIR" ] || mkdir -p "$STATE_DIR" 2>/dev/null || true

# ── PROCESS BUDGET (2026-10-11, docs/research/load-hook-timeouts-2026-10-11 item 5). This hook ran
# ~40-75 process creations on EVERY prompt — 1.39 s measured at load ~420, and 28 of 162
# UserPromptSubmit cancels — while eleven prompts in twelve print nothing. Everything below that is
# not needed to decide "not due" is now either builtin, cached, or skipped by a gate that is
# strictly weaker than the decision it guards; tests/memory-nudge-forks.bats counts the calls.
# The clock is read ONCE: the IDL rows (via _IDL_NOW, see hooks/lib/idl-log.sh), the daily prune
# and the rotor latch all take their time from it.
_MN_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || _MN_TS=""
case "$_MN_TS" in [0-9][0-9][0-9][0-9]-*T*Z) ;; *) _MN_TS="" ;; esac
_MN_DAY="${_MN_TS%%T*}"
# shellcheck disable=SC2034  # read by the sourced hooks/lib/idl-log.sh, which shellcheck does not follow
_IDL_NOW="$_MN_TS"

# Prune stale per-session counters (>1 day). -mtime +1 is BSD-safe (unlike -mmin). ONCE A DAY, not
# once a prompt: the directory is shared by every account and held ~1,000 counter files, so the
# per-prompt `find` walked all of them to delete, on almost every prompt, nothing. The stamp holds
# the UTC day of the last prune and is written BEFORE pruning, so a killed prune is not re-run on
# every prompt; with no clock it prunes every time, as before. The same pass ages out this hook's
# own caches (memory-nudge-*.cache below), which bounds how stale a cached path can get.
_mn_pruned=""
[ -r "$STATE_DIR/memory-nudge-prune.day" ] && { read -r _mn_pruned < "$STATE_DIR/memory-nudge-prune.day" || true; }
if [ -z "$_MN_DAY" ] || [ "$_mn_pruned" != "$_MN_DAY" ]; then
  [ -z "$_MN_DAY" ] || printf '%s\n' "$_MN_DAY" > "$STATE_DIR/memory-nudge-prune.day" 2>/dev/null || true
  find "$STATE_DIR" \( -name 'nudge-*.count' -o -name 'nudge-*.mcount' -o -name 'memory-nudge-*.cache' \) -mtime +1 -delete 2>/dev/null || true
fi

# ── MACHINE PROMPTS COUNT SEPARATELY, ON A ×4 INTERVAL (docs/research/startup-hooks-2026-10-18/
# README.md §2 #7; A9-beyond-startup.md R4). A prompt starting with `<` (task-notification,
# teammate-message, system tags — the classifier's not-typed predicate above) is the harness or a
# peer talking, not the operator, yet 471k of 526k nudge chars in 48 h rode those prompts. They now advance their OWN counter, nudge-<sid>.mcount, and fire every INTERVAL×4;
# typed prompts keep nudge-<sid>.count and the plain INTERVAL. The suffix keeps .mcount out of the
# `nudge-*.count` glob, and scripts/idl-abstain-alarm.sh reads both files, dividing each by its
# own interval, so the expected-fires denominator stays exact. A builtin `case`: no fork.
_mn_lead="${_mn_prompt#"${_mn_prompt%%[![:space:]]*}"}"
case "$_mn_lead" in
  '<'*) CF="$STATE_DIR/nudge-${SID}.mcount"; _MN_IV=$(( INTERVAL * 4 )) ;;
  *)    CF="$STATE_DIR/nudge-${SID}.count";  _MN_IV="$INTERVAL" ;;
esac
COUNT=0
[ -r "$CF" ] && { read -r COUNT < "$CF" || true; }
case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac
COUNT=$(( 10#$COUNT + 1 ))
printf '%s' "$COUNT" > "$CF"
# Due on the periodic slot? (The other way to be due — an over-cap index on a session's first
# prompt — needs the measurement, and is decided below.)
_MN_PERIODIC=0
[ $(( COUNT % _MN_IV )) -ne 0 ] || _MN_PERIODIC=1

# ── Locate the index this session actually loads ──────────────────────────────
# Slug = project root with '/' and '.' folded to '-'. For a linked worktree the
# harness keys on the MAIN worktree, so resolve through the git COMMON dir; a
# cwd-keyed slug is the fallback for a non-repo cwd.
# Deref through the live symlink (this file IS ~/.claude/hooks/memory-nudge.sh when invoked
# live) so a sibling binary resolves in the CHECKOUT, where it exists the moment the trunk
# fast-forwards — same load-bearing pattern as backup-before-write.sh's _mib_deref: an
# underefed dirname would miss a newly-ADDED sibling until a deploy links it, and fail open
# silently (MEMORY.md deployed-layer-bootstrap-circle / the LIVE_ADDS budget rule).
# Resolved ONCE into _MN_SELF / _MN_DIR (it was re-run, with a `dirname` fork, for every sibling);
# a path that is not itself a link needs no readlink, since its siblings resolve the same.
_mn_deref() {
  local p="$1" t n=0
  [ -L "$p" ] || { printf '%s\n' "$p"; return 0; }
  readlink -f "$p" 2>/dev/null && return 0
  while [ -L "$p" ] && [ "$n" -lt 20 ]; do
    t="$(readlink "$p")"
    case "$t" in /*) p="$t" ;; *) case "$p" in */*) p="${p%/*}/$t" ;; *) p="./$t" ;; esac ;; esac
    n=$(( n + 1 ))
  done
  printf '%s\n' "$p"
}
_MN_SELF="$(_mn_deref "${BASH_SOURCE[0]}")"
case "$_MN_SELF" in */*) _MN_DIR="${_MN_SELF%/*}" ;; *) _MN_DIR=. ;; esac
[ -n "$_MN_DIR" ] || _MN_DIR=/

# CWD came out of the one stdin jq above.
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"

_mn_idl="$_MN_DIR/lib/idl-log.sh"

# ── RULING SHADOW log. Runs on EVERY prompt that got this far — before the interval and damping
# exits below — so each counted prompt gets exactly one `memory-nudge:ruling` IDL row (its own name,
# acceptance X2): fired <class> on a match, else abstained no-match / not-typed / kill-switch.
# The existing MEMORY_NUDGE_INTERVAL=0 kill switch still exits before this (and before the counter),
# so the expected-fires denominator (raw nudge-*.count prompts) and these rows stop together.
# A fire also appends one row a labeller can judge to $HOME/.claude/state/ruling-shadow.jsonl
# (X4: one physical dir, not $CFG/state). Wave E promotes or kills this on that log
# (docs/plans/TRUEMEMORY_ADOPTION.md:222). Nothing here writes to stdout, and every failure is
# swallowed: a shadow must not be able to change or break the hook.
# RETIRED 2026-09-28 (Wave E, #26 DROP, research §5.18): OFF unless CC_RULING_SHADOW=on. An unset
# switch logs `abstained kill-switch` (a reached guard) on every counted prompt and writes no shadow
# row, so the registry row still sees one row per prompt; `on` re-arms it for a delivery-research wave.
_mn_ruling_shadow() {
  local why="$_MN_RV" have_idl=0 sha row dir
  if [ -r "$_mn_idl" ]; then
    # shellcheck source=lib/idl-log.sh
    # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
    . "$_mn_idl" && idl_init "${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}" memory-nudge:ruling SID && have_idl=1
  fi
  [ "${CC_RULING_SHADOW:-off}" = on ] || why=kill-switch
  # The abstain row is written on EVERY counted prompt, so it takes the one-printf writer
  # (log_idl_fixed: same bytes, no jq/date/wc/tr forks) whenever the sourced lib carries it.
  case "$why" in
    restatement|ruling) ;;
    *) if [ "$have_idl" -eq 1 ]; then
         if declare -F log_idl_fixed >/dev/null; then log_idl_fixed abstained "${why:-classify-error}"
         else log_idl abstained "${why:-classify-error}"; fi
       fi
       return 0 ;;
  esac
  sha=$( { printf '%s' "$INPUT" | jq -j '.prompt' | shasum -a 1 | cut -d' ' -f1; } 2>/dev/null ) || sha=""
  dir="$HOME/.claude/state"
  mkdir -p "$dir" 2>/dev/null || true
  row=$(jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sid "$SID" --arg cwd "$CWD" \
          --arg class "$why" --arg pattern "$_MN_RPAT" --arg excerpt "$_MN_REXC" \
          --arg len "$_MN_RLEN" --arg sha "$sha" \
          '{ts:$ts,sid:$sid,cwd:$cwd,class:$class,pattern:$pattern,excerpt:$excerpt,
            prompt_len:($len|tonumber? // 0),prompt_sha1:$sha}' 2>/dev/null) \
    && printf '%s\n' "$row" >> "$dir/ruling-shadow.jsonl" 2>/dev/null
  [ "$have_idl" -eq 0 ] || log_idl fired "$why" \
    "$(jq -cn --arg p "$_MN_RPAT" '{pattern:$p}' 2>/dev/null)"
}
_mn_ruling_shadow || true

# ── EPISODIC CUE (truememory-2026-09-27.md §3.18, #18; PROVISIONAL). One narrow-cue line pointing at
# claude-search when a typed prompt refers to earlier work; it injects nothing from other sessions.
# Computed on EVERY counted prompt, like the shadow above, and it rides whichever JSON this hook
# prints: cue-only on a non-due prompt (_mn_not_due); on a due one it leads, except that a 🚨 warning
# stays first (see the final jq). Exactly
# one JSON object either way. The lib logs its own `memory-nudge:episodic` IDL row per prompt and
# every fire to ~/.claude/state/episodic-cue.jsonl, which scripts/episodic-cue-outcome.py reads
# nightly — adoption rides on that log. Resolved through the dereferenced self-path (X1), and a
# missing lib costs the cue and nothing else. Kill switch CC_EPISODIC_CUE=off.
_MN_CUE=""
_mn_ep="$_MN_DIR/lib/episodic_cue.sh"
if [ -r "$_mn_ep" ]; then
  # $_mn_prompt (raw, trailing newlines kept) came out of the one stdin jq at the top.
  # shellcheck source=lib/episodic_cue.sh
  # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
  . "$_mn_ep" && _MN_CUE="$(episodic_cue_line "$_mn_prompt" 2>/dev/null)" || _MN_CUE=""
fi
_mn_not_due() {
  [ -z "$_MN_CUE" ] || jq -cn --arg ctx "$_MN_CUE" \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
  exit 0
}

MEM="${MEMORY_INDEX_PATH:-}"
WANT="$MEM"
RROOT=""
_MN_RESOLVED=0   # 1 = MEM/WANT/RROOT came from the candidate walk below (no override)

# ── WHERE-CACHE (2026-10-11, load-hook-timeouts item 5). The candidate index paths depend only on
# the cwd and the config dir, yet resolving them cost a `git rev-parse`, a `dirname`, two `pwd -P`
# subshells and up to four `tr`s on every prompt. They are cached per cwd as lines: cwd, config
# dir, the git toplevel (RROOT, read on the due path), then each candidate in walk order. Which
# candidate EXISTS is never cached — every prompt re-tests each with a builtin `[ -f ]`, so an index
# created after the cache was written is found on the next prompt. What can go stale is only the
# git root itself (a cwd that later becomes, or stops being, a repo); the daily prune deletes a
# cache untouched for over a day, which bounds that. A cwd or path carrying a newline is never
# cached (one line per field), and a cache whose cwd/config lines differ is a miss.
_mn_where_read() {
  local c g l
  [ -f "$_MN_WC" ] || return 1
  _mn_cands=""
  { IFS= read -r c && IFS= read -r g && IFS= read -r RROOT || return 1
    while IFS= read -r l; do _mn_cands="$_mn_cands$l$_mn_nl"; done
  } < "$_MN_WC" 2>/dev/null || return 1
  [ "$c" = "$CWD" ] && [ "$g" = "$CFG" ] && [ -n "$_mn_cands" ]
}
_mn_where_compute() {
  local out gcd root cand phys base s nocache=0
  _mn_cands=""
  case "$CWD$CFG" in *"$_mn_nl"*) nocache=1 ;; esac
  # ONE git for both answers. Inside a .git dir it prints the common dir and then fails on the
  # toplevel, which is exactly what the two separate calls answered, so the output is read
  # whatever the exit code.
  out="$(cd "$CWD" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir --show-toplevel 2>/dev/null)" || true
  gcd="${out%%"$_mn_nl"*}"
  RROOT=""
  case "$out" in *"$_mn_nl"*) RROOT="${out#*"$_mn_nl"}"; RROOT="${RROOT%%"$_mn_nl"*}" ;; esac
  # Nothing at all: not a repo, or a git too old for --path-format — the toplevel alone still answers.
  [ -n "$out" ] || RROOT="$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" || RROOT=""
  root=""
  if [ -n "$gcd" ]; then
    case "$gcd" in */*) root="${gcd%/*}"; [ -n "$root" ] || root=/ ;; *) root=. ;; esac
  fi
  # Try each base in BOTH its logical and physical form: git reports a fully
  # resolved path while the harness keys on the cwd it was handed, and on macOS
  # /var vs /private/var share no prefix — one spelling silently finds nothing.
  for cand in "$root" "$CWD"; do
    [ -n "$cand" ] || continue
    phys=$(cd "$cand" 2>/dev/null && pwd -P) || phys=""
    for base in "$cand" "$phys"; do
      [ -n "$base" ] || continue
      case "$base" in *"$_mn_nl"*) nocache=1 ;; esac
      s="${base//\//-}"; s="${s//./-}"   # the slug: '/' and '.' folded to '-'
      _mn_cands="$_mn_cands$CFG/projects/$s/memory/MEMORY.md$_mn_nl"
    done
  done
  case "$RROOT" in *"$_mn_nl"*) nocache=1 ;; esac
  [ "$nocache" -eq 0 ] || return 0
  printf '%s\n%s\n%s\n%s' "$CWD" "$CFG" "$RROOT" "$_mn_cands" > "$_MN_WC" 2>/dev/null || true
}
if [ -z "$MEM" ]; then
  _MN_RESOLVED=1
  _mn_ck="${CWD//\//-}"
  if [ "${#_mn_ck}" -gt 120 ]; then _mn_ck="${_mn_ck: -120}"; fi
  _MN_WC="$STATE_DIR/memory-nudge-where-${#CWD}-${_mn_ck}.cache"
  _mn_where_read || _mn_where_compute
  _mn_c="$_mn_cands"
  while [ -n "$_mn_c" ]; do
    p="${_mn_c%%"$_mn_nl"*}"; _mn_c="${_mn_c#*"$_mn_nl"}"
    [ -n "$p" ] || continue
    # WANT is where the index BELONGS, recorded whether or not it exists yet. MEM is only set
    # when the file is already there, so on a brand-new project MEM stays empty — and that is
    # precisely the session that has to be told the path, because it is the one about to
    # CREATE the index. See the nudge text below for why naming it matters.
    [ -n "$WANT" ] || WANT="$p"
    [ -f "$p" ] && { MEM="$p"; break; }
  done
fi
# NAME THE PHYSICAL PATH (2026-09-27). On the symlinked accounts $CFG/projects/<slug>/memory is
# reached through a symlink into ~/.claude/projects/, and bin/cc-close-attrib pins the harness's
# autoMemoryDirectory to the REAL path. CC's write carve-out matches the path AS SPELLED, so a
# write to the symlinked spelling this hook used to print raised a permission prompt auto mode
# cannot approve — measured 2026-09-27: the model followed this nudge to
# ~/.claude-next/projects/…/memory/ and the operator had to click Yes. Resolve the deepest
# EXISTING ancestor (memory/ may not exist yet) and re-append the rest, exactly as
# cc-close-attrib does, so the two agree. MEMORY_INDEX_PATH above is an override, left as given.
# Only the nudge text reads WANT, so this runs on the due path only (called below the due check).
_mn_want_physical() {
  [ "$_MN_RESOLVED" -eq 1 ] && [ -n "$WANT" ] || return 0
  _mn_probe="${WANT%/*}" _mn_rest="/${WANT##*/}"
  while [ -n "$_mn_probe" ] && [ ! -d "$_mn_probe" ]; do
    _mn_rest="/${_mn_probe##*/}$_mn_rest"; _mn_probe="${_mn_probe%/*}"
  done
  if [ -n "$_mn_probe" ] && _mn_real="$(cd -P "$_mn_probe" 2>/dev/null && pwd -P)" && [ -n "$_mn_real" ]; then
    WANT="${_mn_real%/}$_mn_rest"
  fi
}

# ── Measure (fail-safe: a side-car must never fail wider than itself) ─────────
# An unresolvable measure, or a cap this hook cannot read, costs the BUDGET half and nothing
# else: the crystallization nudge is the reason this hook exists and does not depend on either.
# Exiting here instead would let a missing side-car silence the primary duty — a side-car
# failing wider than itself, which is the one thing this whole subsystem refuses to do.
MEASURE_OK=1
# 🚨 THE `||` GUARD ABOVE WAS INERT, AND THE COMMENT ABOVE DESCRIBED SOMETHING THAT DID NOT HAPPEN.
# This read `. <lib> 2>/dev/null || . "$CFG/…" 2>/dev/null || MEASURE_OK=0`, which LOOKS fail-safe
# and is not: `.` is a POSIX SPECIAL BUILTIN, and a special builtin that fails terminates a
# non-interactive shell — before the `||` is ever consulted. So a copy of this hook with no lib
# beside it exited at this line and printed NOTHING: not the budget block it is allowed to lose,
# but the crystallization nudge that is the whole reason the hook exists. Exactly the side-car
# failing wider than itself that the paragraph above swears off (memory:
# addon-failure-exceeds-its-blast-radius), and the LIVE_ADDS shape too — until the converger runs,
# a landed ADD is absent, so this silenced the primary duty fleet-wide the moment it shipped.
# Measured: `set -euo pipefail; . /nonexistent || echo fallback; echo after` prints neither
# `fallback` nor `after` and exits 1, while the `[ -r ]` form below prints both.
# Testing readability FIRST is what makes the fallback reachable at all.
_mn_lib="$_MN_DIR/lib/memory-index-measure.sh"
[ -r "$_mn_lib" ] || _mn_lib="$CFG/hooks/lib/memory-index-measure.sh"
if [ -r "$_mn_lib" ]; then
  # shellcheck source=/dev/null   # SC1091 suppression: this gate calls shellcheck without -x
  . "$_mn_lib" 2>/dev/null || MEASURE_OK=0
else
  MEASURE_OK=0
fi
LIMIT=""; LINE_LIMIT=""
if [ "$MEASURE_OK" -eq 1 ]; then
  LIMIT=$(mim_limit) || MEASURE_OK=0            # chars of the loader-visible index, not disk bytes
  LINE_LIMIT=$(mim_line_limit) || MEASURE_OK=0  # the OTHER cap: the loader truncates on either
fi
HOOK_TARGET="${MEMORY_HOOK_TARGET:-115}"  # the compact-memory 'one governing rule' length — a FLOOR, not a target (see EFF_TARGET)
HEADROOM_TARGET="${MEMORY_HEADROOM_TARGET:-2500}"  # compact-memory's "done" = ~2.5 KB under the limit

# _mn_stats <index> → "TOTAL LINES N ENTRY_U PFX_U DROPPED", every figure counted over the
# EFFECTIVE content in the loader's own unit, so the advisory and the gate cannot disagree.
#   DROPPED — entries whose own start offset already falls at/after the limit. Exact, not
#   overage/mean-line: a real index is not uniform and its TAIL is exactly where an average is
#   least true (measured 2026-08-08, the averaged form announced 6 where the exact count was 4).
_mn_stats() {
  jq -nr --rawfile c "$1" --argjson lim "$LIMIT" --argjson llim "$LINE_LIMIT" "$MIM_JQ_DEFS"'
    def u: mim_units;
    ($c | mim_effective) as $e
    | ($e | split("\n")) as $L
    | [$L[] | select(startswith("- ["))] as $E
    | ([$E[] | (u + 1)] | add // 0) as $entry
    | ([$E[] | sub("^(?<p>- \\[[^]]*\\]\\([^)]*\\) — ).*$"; "\(.p)") | (u + 1)] | add // 0) as $pfx
    # DROPPED IS THE UNION OF BOTH CAPS, because the loader truncates on EITHER (units > $lim OR
    # lines > $llim) and the two cut at different places. Counting only the byte offset reported
    # 0 dropped on an index cut by the LINE cap — the newest entries invisible and the sensor
    # announcing nothing — and under-reported a dual breach by every entry sitting between the
    # line cut and the char cut. $i is 0-based over the effective lines, so the loader keeps line
    # numbers 1..$llim and an entry at $i+1 > $llim is gone whatever its offset says.
    | (reduce range(0; ($L | length)) as $i ({off:0, n:0};
         ($L[$i]) as $l
         | {off: (.off + ($l | u) + 1),
            n:   (.n + (if ($l | startswith("- [")) and ((.off >= $lim) or (($i + 1) > $llim))
                        then 1 else 0 end))}) | .n) as $dropped
    | "\($e | u) \($e | mim_lines) \($E | length) \($entry) \($pfx) \($dropped)"
  ' 2>/dev/null
}

# _mn_parse_stats — split $STATS into its six fields with one builtin `read` (it was seven
# `printf | cut` forks), sanitized exactly as before.
_mn_parse_stats() {
  TOTAL="" LINES="" N="" ENTRY_B="" PFX="" DROPPED_U=""
  read -r TOTAL LINES N ENTRY_B PFX DROPPED_U <<< "$STATS" || true
  case "${TOTAL:-x}" in ''|*[!0-9]*) TOTAL="" ;; esac
  case "${LINES:-x}" in ''|*[!0-9]*) LINES=0 ;; esac
  case "${N:-x}" in ''|*[!0-9]*) N=0 ;; esac
}

# ── STATS CACHE (2026-10-11, load-hook-timeouts item 5). `_mn_stats` is a jq over the whole index,
# and the index changes a few times a day while this hook runs on every prompt of every session.
# Its line is cached per index (with the two caps it was computed against) and trusted only while
# builtin `-nt` tests prove nothing it depends on changed: the cache is newer than the index, than
# this hook and than the measure lib. `-nt` here is WHOLE SECONDS (bash 3.2), so a cache is written
# only when the session's counter file — written at the top of THIS prompt, before the measurement
# read the index — is strictly newer than the index: the index then was last written in an earlier
# second than the read, and any later write lands in a second >= the counter's. That check is
# repeated after the write and empties the cache if it no longer holds, so an index write racing
# the measurement can never leave a stale line behind; the worst case is one extra measurement.
_mn_stats_cached() {
  local a b l
  [ -f "$_MN_SC" ] && [ "$_MN_SC" -nt "$MEM" ] && [ "$_MN_SC" -nt "$_MN_SELF" ] \
    && [ "$_MN_SC" -nt "$_mn_lib" ] || return 1
  { read -r a b l < "$_MN_SC"; } 2>/dev/null || return 1
  [ "$a" = "$LIMIT" ] && [ "$b" = "$LINE_LIMIT" ] || return 1
  case "$l" in ''|*[!0-9\ ]*) return 1 ;; esac
  # shellcheck disable=SC2086  # deliberate word split: six numeric fields
  set -- $l
  [ "$#" -eq 6 ] || return 1
  STATS="$l"
}
_mn_stats_store() {
  case "$STATS" in ''|*[!0-9\ ]*) return 0 ;; esac
  [ "$CF" -nt "$MEM" ] || return 0
  printf '%s %s %s\n' "$LIMIT" "$LINE_LIMIT" "$STATS" > "$_MN_SC" 2>/dev/null || return 0
  [ "$CF" -nt "$MEM" ] || : > "$_MN_SC" 2>/dev/null || true
}

# ── COST GATE on a NON-DUE prompt (2026-10-11). On such a prompt the measurement can matter in
# exactly two ways: the rotor (TOTAL >= ROTATE_AT) and the over-cap alarm that makes a session's
# first prompt due (TOTAL >= LIMIT, or LINES > LINE_LIMIT). _mn_raw_small proves neither can happen
# without starting jq: raw BYTES are never fewer than loader units (every UTF-16 unit costs >= 1
# byte, a surrogate pair 4; stripping only removes), and raw lines are never fewer than effective
# lines (stripping and trimming only remove). So bytes below min(ROTATE_AT, LIMIT) with lines at or
# under LINE_LIMIT means the measurement could not have changed anything, and is skipped. It is a
# builtin read loop under LC_ALL=C (${#l} = bytes), stopping at the first line that crosses either
# bound. Residual, stated: bash `read` drops NUL bytes that jq would count, so an index made of
# NULs could read small; such a file is not an index, and a due prompt still measures it in full.
_mn_raw_small() {
  local LC_ALL=C l b=0 n=0 at="$LIMIT"
  [ -r "$MEM" ] || return 1
  [ "$ROTATE_AT" -lt "$at" ] 2>/dev/null && at="$ROTATE_AT"
  while IFS= read -r l || [ -n "$l" ]; do
    b=$(( b + ${#l} + 1 )); n=$(( n + 1 ))
    [ "$b" -lt "$at" ] && [ "$n" -le "$LINE_LIMIT" ] || return 1
  done < "$MEM"
}

BUDGET_CTX=""
TOTAL="" LINES=0 N=0 ENTRY_B="" PFX="" DROPPED_U=""
if [ "$MEASURE_OK" -eq 1 ] && [ -n "$MEM" ] && [ -f "$MEM" ]; then
  ROTATE_AT="${MEMORY_ROTATE_AT:-$(( LIMIT - 1500 ))}"
  MN_KEY="${MEM//\//-}"
  if [ "${#MN_KEY}" -gt 120 ]; then MN_KEY="${MN_KEY: -120}"; fi
  _MN_SC="$STATE_DIR/memory-nudge-stats-${#MEM}-${MN_KEY}.cache"
  STATS=""
  # The periodic slot always measures afresh (one jq in twelve prompts), so the figures the nudge
  # PRINTS never come from a cache. The residual the `-nt` test cannot see — an index replaced by
  # a copy carrying an OLDER mtime (`cp -p`, `rsync -t`; no writer of the index does that) — can
  # then only delay the rotor and the first-prompt alarm, until the next slot, write or prune.
  if [ "$_MN_PERIODIC" -eq 0 ] && _mn_stats_cached; then
    :
  elif [ "$_MN_PERIODIC" -eq 0 ] && _mn_raw_small; then
    :   # gated: nothing on this prompt can read the figures, so they stay unset
  else
    STATS=$(_mn_stats "$MEM") || STATS=""
    _mn_stats_store
  fi
  _mn_parse_stats

  # ── ACTUATE, then advise (2026-08-10). Twelve hand-compactions in 14 days proved advisory
  # text cannot hold this line: insertion is machine-speed (Edit appends, plus Bash `>>`
  # appends the PreToolUse byte-gate never sees — one caught live 2026-08-10T07:51Z), while
  # removal was human-speed. cc-memory-rotate mechanizes the operator-approved cold split
  # (2026-07-30, compact-memory.md § two-tier hot/cold); this hook fires fleet-wide on every
  # prompt, so whichever door grew the file, the next prompt anywhere rotates it back under
  # budget. Actuation runs on EVERY over-threshold prompt regardless of the nudge's damping
  # cadence below — advisory cadence and actuation are different duties. After this, the 🚨
  # branch means rotation COULD NOT clear it — an alarm that fires on breaches it could have
  # fixed itself carries no bits (MEMORY.md alarm-polarity-and-attention-budget).
  # (ROTATE_AT is set at the top of this block: the cost gate reads it too.)
  ROTATE_NOTE=""
  if [ -n "$TOTAL" ] && [ "$TOTAL" -ge "$ROTATE_AT" ] 2>/dev/null; then
    RB="${MEMORY_ROTATE_BIN:-}"
    if [ -z "$RB" ]; then
      for c in "$_MN_DIR/../bin/cc-memory-rotate" \
               "$CFG/bin/cc-memory-rotate"; do
        if [ -x "$c" ]; then RB="$c"; break; fi
      done
    fi
    PRE_TOTAL="$TOTAL"
    # LATCH. Rotation is deterministic in its inputs: given the same index bytes and the same topic
    # corpus, a rotor that answered `exhausted` answers `exhausted` again. Re-running it on EVERY
    # prompt therefore buys nothing and costs the hook its whole budget — measured 2026-09-05 at
    # 118s against a forced breach with CLAUDE_PROJECT_DIR set, versus the 5s this hook declares, so
    # the harness killed the hook and DISCARDED an additionalContext it had already computed.
    # Attempt it once per index STATE per DAY: the state component re-arms the moment the index
    # actually changes, and the date component bounds the worst case (a corpus change the index
    # cannot see) at one day. Stamp construction mirrors hooks/memory-index-drain.sh:108-119 — the
    # length guard is load-bearing on bash 3.2, where `${k: -120}` on a shorter string yields "".
    #
    # A WALL-CLOCK BOUND ON THE ROTOR IS DELIBERATELY *NOT* HERE, and that is the whole finding:
    # a real rotation of a 20-entry fixture needs more than 3s under load, so every bound small
    # enough to fit the 5s budget also cuts legitimate rotations (measured — at 3s,
    # memory-nudge-budget.bats 27/28 fail with "Auto-rotation was DEFERRED"; the same shape at 8s
    # broke memory-index-drain.bats 19). The rotor has to get cheaper before it can be bounded;
    # until then this latch cuts how OFTEN the expensive path runs rather than cutting it mid-flight.
    _mn_stat() {
      local v
      v=$(stat -f '%m %z' -- "$1" 2>/dev/null) || v=""
      case "$v" in *[!0-9\ ]*|'') v="" ;; esac
      if [ -n "$v" ]; then printf '%s' "$v"; return 0; fi
      stat -c '%Y %s' -- "$1" 2>/dev/null
    }
    MN_LATCHED=0
    # (MN_KEY is set at the top of this block: the stats cache is keyed the same way.)
    MN_STAMP="$STATE_DIR/memrotate-${#MEM}-${MN_KEY}.stat"
    # The day is the UTC day of the clock read at the top (one `date` a prompt, not two); with no
    # clock it falls back to asking `date`, as before. Either way it is a day, which is the bound.
    _mn_rday="$_MN_DAY"; [ -n "$_mn_rday" ] || _mn_rday="$(date +%Y-%m-%d)"
    MN_NOWSTAT="$(_mn_stat "$MEM") $_mn_rday"
    case "$MN_NOWSTAT" in ' '*) MN_NOWSTAT="" ;; esac
    _mn_was=""
    [ -r "$MN_STAMP" ] && { read -r _mn_was < "$MN_STAMP" || true; }
    if [ -n "$MN_NOWSTAT" ] && [ "$MN_NOWSTAT" = "$_mn_was" ]; then
      MN_LATCHED=1
    fi
    if [ -n "$RB" ] && [ -x "$RB" ] && [ "$MN_LATCHED" -eq 0 ]; then
      # Record BEFORE acting, per memory-index-drain.sh:126-128: if the rotor dies, the next real
      # index write changes the stat and re-arms this anyway, whereas recording after would let a
      # killed rotor re-run the actuator on the identical file every single prompt.
      if [ -n "$MN_NOWSTAT" ]; then printf '%s' "$MN_NOWSTAT" >"$MN_STAMP" 2>/dev/null || true; fi
      RV=$("$RB" "$MEM" 2>/dev/null) || RV="${RV:-verdict=error}"
      case "$RV" in
        verdict=rotated*|verdict=noop*)
          if [ "${RV#verdict=rotated}" != "$RV" ]; then
            ROTATE_NOTE=" AUTO-ROTATED to hold the read limit (${RV#verdict=rotated }): moved lines are VERBATIM in the cold record — restore = paste the line back."
          fi
          STATS=$(_mn_stats "$MEM") || STATS=""
          _mn_stats_store
          _mn_parse_stats
          ;;
        *)
          # In the pressure band under the LIMIT an exhausted rotor is the designed steady
          # state (stage 2 arms only at breach) — not a failure; note it only when the index
          # is actually breached and rotation was its remedy.
          if [ "$PRE_TOTAL" -ge "$LIMIT" ] 2>/dev/null; then
            ROTATE_NOTE=" Auto-rotation ran and could NOT clear it (${RV:-no verdict})."
          fi
          ;;
      esac
    else
      if [ "$PRE_TOTAL" -ge "$LIMIT" ] 2>/dev/null; then
        ROTATE_NOTE=" Auto-rotation unavailable: cc-memory-rotate not resolvable from this hook."
      fi
    fi
  fi
fi

# ── DUE CHECK, BEFORE any advisory text is built (2026-10-11, load-hook-timeouts item 5).
# Fire on the FIRST prompt and every Nth after. An over-limit index is a live,
# actionable fault, so it speaks up immediately rather than waiting for the
# periodic slot; when the index is healthy this stays on the periodic cadence.
# OVERFLOW is read off the figures, by the same two tests that pick the 🚨 arms below (char cap,
# then line cap, both only for a measured index with entries), so everything after this line —
# `wc -c`, the advice arithmetic, the path and rules-file resolution — runs on due prompts only.
OVERFLOW=0
if [ "$MEASURE_OK" -eq 1 ] && [ -n "$TOTAL" ] && [ "${N:-0}" -gt 0 ] 2>/dev/null; then
  if [ "$TOTAL" -ge "$LIMIT" ] || [ "$LINES" -gt "$LINE_LIMIT" ]; then OVERFLOW=1; fi
fi
if [ "$OVERFLOW" -eq 1 ]; then
  [ "$COUNT" -eq 1 ] || [ "$_MN_PERIODIC" -eq 1 ] || _mn_not_due
else
  [ "$_MN_PERIODIC" -eq 1 ] || _mn_not_due
fi
_mn_want_physical

if [ "$MEASURE_OK" -eq 1 ] && [ -n "$MEM" ] && [ -f "$MEM" ]; then
  if [ -n "$TOTAL" ] && [ "${N:-0}" -gt 0 ] 2>/dev/null; then
    # Measure the ENTRY lines only: the file also carries a header/provenance block,
    # and folding that fixed cost into a per-entry average overstates every hook.
    # (_mn_stats counted these over the EFFECTIVE content, in the loader's unit, one newline
    # per entry line included in both — so TOTAL = header + PFX + Sigma_hook holds exactly.)
    # ENTRY_B and PFX were split out of $STATS by _mn_parse_stats.
    PFX_AVG=$(( PFX / N ))
    HOOK_AVG=$(( (ENTRY_B - PFX) / N ))
    # Cardinality ceiling: what the limit affords at a disciplined hook length.
    MAXN=$(( LIMIT / (PFX_AVG + HOOK_TARGET) ))
    # FILING FORM (2026-08-06, backlog 0b3a8b19d4d4). Sessions reading this advisory file the
    # condition as backlog work, and they put the live size in the TITLE — which is the cc-backlog
    # event key (project+title+source), so one standing condition minted 21 items instead of one
    # and the ledger's own done-guard never fired (004502cf59ab closed 21:28:01Z, its twin
    # 0fc2ae0d0140 claimed 21:34:01Z). Hand over the condition-keyed form in BOTH branches: those
    # mints happened at 20.5 KB and 22.5 KB — under this limit, off the harness's own product-side
    # "approaching the limit" reminder — so a form that only spoke when breached would miss most.
    # ── RAW BYTES, CARRIED ONLY TO BE CONTRADICTED ───────────────────────────────────────────
    # Every size this hook prints is a LOADER UNIT (UTF-16 code units over the stripped, trimmed
    # index). `wc -c` on the same file reads BYTES, and on an index dense with `—`/`⇒`/`·` the two
    # differ by mim_overhead — 1,332 on the live claude-infrastructure index, 2026-09-08. That gap
    # has been filed as a breach FOUR times (cc-backlog 150c50055e1c, 7c266e16fc94, 0b3d53bcd1fd,
    # and a re-mint of the first at 2026-09-08T05:54:58Z that reverted a correction made six hours
    # earlier and cost a dispatched worker session). The path is identical every time: the reader
    # sees this hook say "chars", reaches for the instrument that measures chars, gets bytes, and
    # compares them against a unit cap.
    #
    # Three files already say "never wc -c" in prose — memory-index-measure.sh's header,
    # compact-memory.md:28, and this index's own line 4 — and all three failed, because prose
    # cannot reach someone who does not believe they are guessing. So do not instruct: PRE-EMPT.
    # Print the number `wc -c` is about to return, immediately before the line that asks for a
    # size. A reader who runs it then lands on a figure this hook has already named as the wrong
    # unit, and cannot file it as an overage without contradicting a line they just read.
    #
    # Computed HERE, after the rotor above may have rewritten the index, so it describes the file
    # as it now stands. Unreadable or non-numeric leaves the clause omitted rather than guessed at,
    # and a file whose bytes equal its units (pure ASCII, no frontmatter) says nothing at all —
    # there is no trap to warn about and a clause that always fires carries no bits.
    RAW=$(wc -c <"$MEM" 2>/dev/null | tr -d ' ')
    case "${RAW:-x}" in ''|*[!0-9]*) RAW="" ;; esac
    UNIT_NOTE=""
    if [ -n "$RAW" ] && [ -n "$TOTAL" ] && [ "$RAW" -gt "$TOTAL" ] 2>/dev/null; then
      UNIT_NOTE="UNITS — READ BEFORE QUOTING A SIZE: every figure above is a LOADER UNIT (UTF-16 code units, counted AFTER YAML frontmatter and block HTML comments are stripped and the result trimmed), not a byte. \`wc -c\` on this file reads ${RAW} bytes, a gap of $(( RAW - TOTAL )) against the ${TOTAL} that count. Measure with hooks/lib/memory-index-measure.sh (\`mim_measure_file\`), never \`wc -c\`."
      # TWO TOKENS THIS CLAUSE MAY NOT USE, both learned by a RED land gate rather than by review.
      # `more than the` is tests/memory-nudge-budget.bats:115's NEGATIVE discriminator for a
      # different diagnosis branch ("recovers ~N chars — more than the M needed"), so a legend
      # riding EVERY branch that spelled it convicted the branch that must not say it. And `🚨` is
      # this hook's alarm marker — seven `hasnt … '🚨'` assertions use it to mean "no breach was
      # reported", and the hook's own OVERFLOW test matches it at string START. Wearing it here
      # would be self-contradictory anyway: this clause exists to say the index is NOT over budget.
      # THE TRAP WINDOW, and the only place this escalates. When the byte reading is over the cap
      # while the unit reading is under it, the two instruments return OPPOSITE VERDICTS on the
      # same healthy file — that is not a units footnote any more, it is a breach report waiting to
      # be written, and it is exactly the state that produced all four filings. Outside this window
      # the legend above is enough: a gap that cannot flip the verdict cannot manufacture an
      # overage, and a warning that shouted at every index would carry no bits when it mattered.
      if [ "$RAW" -gt "$LIMIT" ] && [ "$TOTAL" -le "$LIMIT" ] 2>/dev/null; then
        UNIT_NOTE="$UNIT_NOTE PHANTOM-BREACH WINDOW: \`wc -c\` (${RAW}) is OVER the ${LIMIT} cap while the unit count (${TOTAL}) is UNDER it by $(( LIMIT - TOTAL )). THIS INDEX IS NOT OVER BUDGET and nothing is being dropped. Filing it as an overage is a known false positive — cc-backlog 150c50055e1c, 7c266e16fc94 and 0b3d53bcd1fd were all closed as exactly this error. Do not file one; if a row already claims it, the disproof is the deliverable."
      fi
    fi
    FILING="FILING: if you file this as work it is ONE standing condition, not a new item per measurement — \`cc-backlog add --condition memory-index-over-budget --project <project> --title \"<the live size>\"\`. The size belongs in the title; putting it in the key is what minted 21 items for this one condition."
    # Hoisted above the breach arms because BOTH of them need it: the count is the UNION over the
    # two caps (see _mn_stats), and it used to be read inside the char arm only — so the LINE arm,
    # the one case where the char offset says nothing, announced a silent tail with no count of it.
    # (DROPPED_U was split out of $STATS by _mn_parse_stats.)
    case "$DROPPED_U" in ''|*[!0-9]*) DROPPED_U=0 ;; esac
    if [ "$TOTAL" -ge "$LIMIT" ]; then
      OVER=$(( TOTAL - LIMIT ))
      # EXACT, not averaged. The old form (OVER / mean-line-cost) reads the index as
      # though every entry were mean-length; a real index is not, and its TAIL is
      # exactly where the estimate is applied. Measured 2026-08-08 against the live
      # store it announced 6 dropped entries where the exact count was 4 — a number
      # the operator sizes a compaction pass from. Count instead the entries whose
      # own start offset falls at/after the limit — counted by _mn_stats over the
      # EFFECTIVE content in the loader's unit, because an offset walked in raw
      # bytes over the raw file names a different entry than the one the loader
      # actually cuts (frontmatter and comments shift every offset after them).
      DROPPED="$DROPPED_U"
      # Over the limit means at least the final entry is cut, even when the overage
      # falls INSIDE that entry and no start offset is past the limit.
      case "$DROPPED" in ''|*[!0-9]*|0) DROPPED=1 ;; esac
      # Which lever can actually reach the target? Say so — do not make the reader derive it.
      #
      # DERIVE the allowance; never assert it (2026-08-10, backlog 7e2df754d0b8). 1676a681 fixed
      # exactly this bug one position over — MAXN was computed at the aspirational 115 B and read as
      # runway — but RECOVER kept the constant, so the LEVER verdict stayed derived-from-nothing.
      # 115 is the OUTPUT of (limit - headroom_target - header - Sigma_prefix - N)/N on one day's
      # file, not an input: it re-derives to 154 B at N=95 and 171 B at N=98. At N=95 with a 151 B
      # hook average every hook is INSIDE its allowance and 0 B is recoverable, yet the constant
      # reported ~3.6 KB of phantom excess and announced "hook LENGTH is the binding lever" — on the
      # branch that fires only when the index is already breached, i.e. exactly when the reader most
      # needs the true lever (MEMORY.md memory-index-compaction-economics).
      #
      # HOOK_TARGET keeps its job, but as a FLOOR rather than a target, so the constant can only ever
      # make us claim LESS: above it, the derived allowance governs (hooks already inside it recover
      # nothing); below it, we refuse to claim recovery that would require hooks shorter than one
      # governing rule — the spec calls ~67 B/entry "below one sentence" and unreachable, so a cut
      # to there is not a lever, it is a promise no honest pass can keep.
      # PFX already carries one newline per entry (sed emits a line per line), and ENTRY_B carries
      # them too, so TOTAL = header + PFX + Sigma_hook exactly — subtracting N again would double-
      # count the newlines and understate the allowance by 1 B/entry.
      DERIVED=$(( (LIMIT - HEADROOM_TARGET - (TOTAL - ENTRY_B) - PFX) / N ))
      EFF_TARGET="$HOOK_TARGET"
      [ "$DERIVED" -gt "$EFF_TARGET" ] 2>/dev/null && EFF_TARGET="$DERIVED"
      RECOVER=0
      [ "$HOOK_AVG" -gt "$EFF_TARGET" ] && RECOVER=$(( N * (HOOK_AVG - EFF_TARGET) ))
      LEVER_KIND=cardinality
      if [ "$RECOVER" -ge "$OVER" ]; then
        LEVER_KIND=shorten
        LEVER="hook LENGTH is the binding lever: hooks average ${HOOK_AVG} chars against the ${EFF_TARGET} char allowance this index actually affords, so shortening the $N existing hooks recovers ~${RECOVER} chars — more than the ${OVER} needed, and it deletes no rules."
      elif [ "$RECOVER" -gt 0 ]; then
        LEVER_KIND=shorten
        LEVER="BOTH levers are needed: shortening all $N hooks from ${HOOK_AVG} to the ${EFF_TARGET} char allowance recovers only ~${RECOVER} of the ${OVER} chars needed, so archive under the DURABILITY criterion for the remainder (ceiling is ~${MAXN} entries; the index holds $N)."
      else
        LEVER="hooks are already at ${HOOK_AVG} chars (at/under the ${EFF_TARGET} char allowance this index affords), so shortening CANNOT reach the limit — this is CARDINALITY: the index holds $N entries against a ceiling of ~${MAXN}. Archiving under the DURABILITY criterion is the only non-lossy lever."
      fi
      # 🚨 A DUAL BREACH IS NOT A CHAR BREACH. This arm used to be a bare `if TOTAL >= LIMIT` with
      # the line cap as its `elif`, so an index over BOTH caps got a char-only headline and the
      # line breach was never mentioned at all. Worse, the LEVER above could then read "hook LENGTH
      # is the binding lever … shortening recovers ~N — more than needed" — a lever that provably
      # cannot free a LINE, handed to the reader on the one branch where they most need the true
      # one. Shortening moves the char figure and nothing else, so once the line cap is also
      # breached the only honest lever is cardinality, whatever the char arithmetic says.
      DUAL_NOTE=""
      if [ -n "$LINES" ] && [ -n "$LINE_LIMIT" ] && [ "$LINES" -gt "$LINE_LIMIT" ] 2>/dev/null; then
        DUAL_NOTE=" IT IS OVER BOTH CAPS — also ${LINES} lines vs the ${LINE_LIMIT}-line cap (over by $(( LINES - LINE_LIMIT ))), and the loader cuts at whichever comes FIRST."
        # ONLY the two levers that CLAIM SHORTENING SUFFICES are overridden. The third arm above
        # already selected cardinality on its own arithmetic and is not wrong here — replacing it
        # too would make the char arm's own cardinality branch UNREACHABLE for any index dense
        # enough to breach both caps, i.e. exactly the population it was written for, and the
        # suite would lose that coverage silently while still reading green.
        if [ "$LEVER_KIND" = shorten ]; then
          LEVER="BOTH caps are breached, so this is CARDINALITY: shortening hooks moves the char figure and cannot free a LINE. Removing entries is the only lever that reaches both — archive under the DURABILITY criterion (the index holds $N entries against a ceiling of ~${MAXN})."
        fi
      fi
      BUDGET_CTX="🚨 MEMORY INDEX OVER ITS READ LIMIT — ${TOTAL} chars vs the ${LIMIT} char loader limit (over by ${OVER}).${DUAL_NOTE}${ROTATE_NOTE} The loader drops the TAIL silently: the NEWEST ${DROPPED} entries begin past the limit, so they did not load this session and no reader can tell. Anything you append now is written into the invisible tail. ${LEVER} BEFORE appending anything new: archive or shorten to get under ${LIMIT} chars (run /compact-memory; its lossy half is PROPOSE-ONLY — show diffs, get approval). If you must record something now, apply ONE-IN-ONE-OUT: archive an entry in the same edit that adds one. ${UNIT_NOTE} ${FILING}"
    elif [ "$LINES" -gt "$LINE_LIMIT" ]; then
      # THE OTHER CAP. The loader truncates on (chars > LIMIT) OR (lines > LINE_LIMIT), and on an
      # index of one-line entries the LINE cap binds FIRST — an index can sit comfortably inside
      # its char budget with its newest entries already invisible. Nothing here measured this
      # before 2026-08-15, so this breach had no sensor at all. Only removing a LINE clears it;
      # shortening hooks moves the char figure and nothing else.
      # The count is the UNION one, so on THIS arm it is the line-cut half — the char offset says
      # nothing here by construction. Stated only when it is non-zero: an index can be over the
      # line cap on non-entry lines alone, and asserting "1 entry" there would be a fact we do not
      # have (the char arm's floor-to-1 is sound for ITS cut and is not transferable to this one).
      DROP_NOTE=""
      [ "$DROPPED_U" -gt 0 ] && DROP_NOTE=" The NEWEST ${DROPPED_U} entries begin past that line."
      BUDGET_CTX="🚨 MEMORY INDEX OVER ITS LINE LIMIT — ${LINES} lines vs the ${LINE_LIMIT}-line loader limit (over by $(( LINES - LINE_LIMIT ))).${ROTATE_NOTE} The loader drops the TAIL silently: everything after line ${LINE_LIMIT} did not load this session and no reader can tell,${DROP_NOTE} and anything you append now is written into that invisible tail. This is the CARDINALITY cap, not the size one — the index is ${TOTAL}/${LIMIT} chars, so shortening hooks cannot reach it; only removing a line can. BEFORE appending anything new: archive under the DURABILITY criterion (run /compact-memory; its lossy half is PROPOSE-ONLY — show diffs, get approval). If you must record something now, apply ONE-IN-ONE-OUT: archive an entry in the same edit that adds one. ${UNIT_NOTE} ${FILING}"
    else
      HEADROOM=$(( LIMIT - TOTAL ))
      # THE ADVERTISED BUDGET MAY NEVER EXCEED WHAT THE GATE WILL GRANT. HEADROOM answers "how much
      # room is left in the INDEX"; the per-entry cap answers "how long may ONE LINE be", and
      # hooks/lib/memory-index-budget.sh refuses on the second (dim=entry) whatever the first says.
      # On a young index the two are far apart — 20000 chars of headroom against a 300-unit line —
      # so the unclamped form told a writer to compose a hook the append-time gate then refused,
      # with the advisory and the gate disagreeing about the same write. The smaller of the two is
      # the only number that is true of both.
      #
      # Both terms carry the SAME prefix subtraction because LINE_BUDGET is a HOOK budget, not a
      # line budget: the message spends it after "keep its hook <=", and a line costs PFX_AVG
      # before a word of content. Clamping to the raw cap would still over-advertise by exactly
      # that prefix. Read via mim_entry_limit rather than spelled here — one literal, three readers
      # (tests/memory-nudge-budget.bats pins that no fourth spelling appears).
      ENTRY_CAP=""
      if [ "$MEASURE_OK" -eq 1 ]; then ENTRY_CAP=$(mim_entry_limit) || ENTRY_CAP=""; fi
      LINE_BUDGET=$(( HEADROOM - PFX_AVG ))
      if [ -n "$ENTRY_CAP" ]; then
        ENTRY_BUDGET=$(( ENTRY_CAP - PFX_AVG ))
        [ "$ENTRY_BUDGET" -lt "$LINE_BUDGET" ] && LINE_BUDGET="$ENTRY_BUDGET"
      fi
      [ "$LINE_BUDGET" -lt 0 ] && LINE_BUDGET=0
      SLOTS=$(( MAXN - N ))
      # RUNWAY vs CEILING. MAXN/SLOTS derive from HOOK_TARGET, so they answer
      # "how many entries WOULD fit if every one were rewritten to target" — a
      # rewrite, not room to add. The number a session actually needs is what
      # fits at the density this index is ALREADY written at. Measured
      # 2026-08-06 the two read 37 vs 11 (3.4x), and the inflated one had
      # already propagated into a backlog item's premise as "37 free
      # cardinality slots", framing a cardinality-bound index as length-bound.
      # Lead with the observed-density figure; keep the ceiling, marked conditional.
      LINE_COST=$(( PFX_AVG + HOOK_AVG + 1 ))
      [ "$LINE_COST" -gt 0 ] || LINE_COST=1
      FITS=$(( HEADROOM / LINE_COST ))
      # TWO caps, so runway is the SMALLER of them. Reporting char headroom alone would promise
      # slots the line cap will not honour — the cap that binds first is the one to report.
      LINE_SLOTS=$(( LINE_LIMIT - LINES ))
      [ "$LINE_SLOTS" -lt 0 ] && LINE_SLOTS=0
      BOUND=chars
      if [ "$LINE_SLOTS" -lt "$FITS" ]; then FITS="$LINE_SLOTS"; BOUND=lines; fi
      # ONLY NEAR A CAP (docs/research/startup-hooks-2026-10-18/README.md §2 #7). This ~1,000-char
      # line rode every periodic nudge on an index with room to spare, where it changes nothing the
      # model writes. It now prints at >=80% of EITHER cap — the backlog re-mints the FILING form
      # exists for happened at 20.5 KB and 22.5 KB, both above that — and whenever there is news
      # whatever the level: a rotation just moved lines out, or the `wc -c` reading is over the cap
      # (the PHANTOM-BREACH window above). The 🚨 arms above are untouched.
      if [ $(( TOTAL * 5 )) -ge $(( LIMIT * 4 )) ] || [ $(( LINES * 5 )) -ge $(( LINE_LIMIT * 4 )) ] \
         || [ -n "$ROTATE_NOTE" ] || [ "${RAW:-0}" -gt "$LIMIT" ]; then
        BUDGET_CTX="MEMORY INDEX BUDGET (live): ${TOTAL}/${LIMIT} chars and ${LINES}/${LINE_LIMIT} lines across $N entries — ~${FITS} entry slots left, bound by ${BOUND} (${HEADROOM} chars of headroom at the ${LINE_COST} chars/line this index is ACTUALLY written at; ${SLOTS} char-slots only if every existing entry were first rewritten to the ${HOOK_TARGET} char target — that is a rewrite, not runway). A new index line costs ~${PFX_AVG} chars of prefix before a word of content, so keep its hook <= ${HOOK_TARGET} chars (hard cap this append: ${LINE_BUDGET}). Past either cap the loader drops the NEWEST entries silently.${ROTATE_NOTE} ${UNIT_NOTE} ${FILING}"
      fi
    fi
  fi
fi

# (The due check moved above the advisory text; OVERFLOW is set there.)
# One IDL row per DECISION turn (hook `memory-nudge`); non-fire turns exited above, so this adds no
# per-prompt cost. scripts/idl-expected-fires.tsv measures these rows against the fires the
# nudge-*.count files imply, so a nudge that stops firing pages SILENT instead of going quiet.
# $_mn_idl was resolved above for the ruling shadow; re-sourcing resets the lib's state.
if [ -r "$_mn_idl" ]; then
  # shellcheck source=lib/idl-log.sh
  # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
  . "$_mn_idl"
  idl_init "${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}" memory-nudge SID
  _mn_why=periodic; [ "$OVERFLOW" -eq 0 ] || _mn_why=overflow
  log_idl fired "$_mn_why" "$(jq -cn --argjson c "$COUNT" --argjson i "$_MN_IV" '{count:$c,interval:$i}' 2>/dev/null)"
fi

# PIN THE PATH. The product's own memory instruction says "add a one-line pointer in `MEMORY.md`"
# without a path, so a session that has to CREATE the index guesses — and the observed guess is one
# level up, at projects/<slug>/MEMORY.md. That location is invisible twice over: the cross-account
# memory mirror shares projects/<slug>/memory/ and nothing above it, and the mirror's merge only
# knows "$d/MEMORY.md" INSIDE memory/, so a misplaced index is neither shared nor unioned. Measured
# 2026-08-22: 39 slugs correct, and the misplaced ones were written by exactly the sessions that
# created their project's memory for the first time. This hook already resolves the right path for
# its budget measurement; naming it in the nudge costs nothing and is the only authoring site of
# this instruction we control (the rest is in the Claude Code binary).
if [ -n "$WANT" ]; then
  WHERE="the index is $WANT — create it there, NOT one level up at the project root (an index outside memory/ is invisible to the cross-account mirror), and topic files beside it"
else
  WHERE="the index lives at <config-dir>/projects/<slug>/memory/MEMORY.md — inside memory/, NOT one level up at the project root (an index outside memory/ is invisible to the cross-account mirror), and topic files beside it"
fi

# ── WHERE A DURABLE RULE IS MINTED, which is no longer the index ─────────────────────────────
# The index is CAPPED (25,000 chars / 200 lines) and past either cap the loader silently drops
# the NEWEST entries — so every rule minted there competes with every other for a fixed budget
# and the newest one loses. A project `.claude/rules/*.md` file loads unprompted with no cap of
# that size (measured: 60,089 chars / 358 lines — 2.4x the char cap — loaded head and tail
# intact), so a rule written there is on the same always-loaded surface WITHOUT the forced pass.
# That is why the guidance below sends a durable, generalizable RULE to the rules file while
# MEMORY.md plus its topic file stay correct for everything else.
#
# PROJECT-level, never USER-level. Both `~/.claude/rules/*.md` and `<project>/.claude/rules/*.md`
# load in interactive and `claude -p` sessions (re-measured 2026-09-09; bin/cc-mission:16-21 and
# docs/research/token-efficiency-2026-09-23/audit/C6.rules-essay.md), but the user-level directory
# loads in EVERY repo, so a project's lesson written there costs context in unrelated sessions.
#
# THE SITUATIONAL FILE (2026-09-23). The project rules file was split into a resident half
# (agent-operating-lessons.md, the few lessons that fire on any work) and
# agent-operating-lessons-situational.md, which a per-account claudeMdExcludes glob can drop
# (docs/research/token-efficiency-2026-09-23/audit/C7.labels.md). New lessons go to the situational
# file, because admitting a lesson to the resident half is a curated decision, not something a
# periodic nudge should make on every append. It does NOT always load — claudeMdExcludes can drop it,
# and migration 0036 does — so the text below states that CONDITIONALLY rather than computing it:
# this hook fires per prompt, and a jq read of settings here would be paid on every one of them.
#
# This is PROSE, not enforcement, and it is sited here deliberately with its limits stated: this
# hook fires at UserPromptSubmit, every Nth prompt, a full turn after any write, and its only
# channel is additionalContext. It cannot gate a write and does not pretend to. The actuator for
# a rule that is ALREADY in the index is cc-memory-rotate; this text is only about where the
# NEXT one is written.
RULES_HINT="the project's situational rules file at <project>/.claude/rules/agent-operating-lessons-situational.md (PROJECT-level — ~/.claude/rules/ loads in every repo)"
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  RULES_HINT="$CLAUDE_PROJECT_DIR/.claude/rules/agent-operating-lessons-situational.md (create it if missing)"
elif [ "$_MN_RESOLVED" -eq 1 ]; then
  # RROOT came with the cwd's index paths (the where-cache above); no second git.
  [ -z "$RROOT" ] || RULES_HINT="$RROOT/.claude/rules/agent-operating-lessons-situational.md (create it if missing)"
elif RROOT=$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null); then
  [ -n "$RROOT" ] && RULES_HINT="$RROOT/.claude/rules/agent-operating-lessons-situational.md (create it if missing)"
fi
# ORDER INVERTED 2026-09-03, and the order is load-bearing in two directions. This said "append
# one index line to MEMORY.md and create the topic file" — index FIRST. But the index write is the
# one that can be REFUSED (hooks/lib/memory-index-budget.sh denies a crossing write at PreToolUse),
# so on a full index the session lost the pointer AND had not yet written the body: the whole rule
# evaporated at exactly the moment the system was under pressure and most needed to keep it.
# File-first makes the durable half unconditional — a refused pointer then costs a pointer, not a
# lesson, and the remedy is one-in-one-out on an index whose body already exists. It is also the
# precondition for any gate that must READ a rule's topic file at the moment its index line is
# written (routing on durability needs the frontmatter to exist).
#
# PROCEDURE BY POINTER (docs/research/startup-hooks-2026-10-18/README.md §2 #7). The full ~2,260-char
# procedure (the pointer tier, the lesson-body rule, corrections and supersession, the SKIP list)
# rode every fire, verbatim, in every session. It now lives VERBATIM in
# docs/memory-nudge-procedure.md, and the nudge keeps the orders a writer needs without opening it:
# file first, the absolute index path, where a rule goes and the exclusion caveat. The doc is named
# by absolute path in the CHECKOUT, through the dereferenced _MN_DIR, like every other sibling here.
# A relative _MN_DIR (the hook run as `bash hooks/memory-nudge.sh`) is anchored at $PWD first.
case "$_MN_DIR" in /*) _MN_PROC="$_MN_DIR" ;; *) _MN_PROC="$PWD/$_MN_DIR" ;; esac
case "$_MN_PROC" in
  */hooks) _MN_PROC="${_MN_PROC%/hooks}/docs/memory-nudge-procedure.md" ;;
  *)       _MN_PROC="$_MN_PROC/../docs/memory-nudge-procedure.md" ;;
esac
NUDGE="MEMORY CHECK (periodic): if this session surfaced a durable, generalizable rule, decision (+why), confirmed constraint or user feedback not already stored (run cc-memory-search <terms>), persist it now — topic file FIRST, with Write, not Bash, then its one-line pointer; $WHERE. A durable rule goes to $RULES_HINT as one hook line, body in docs/lessons/<slug>.md (it loads unless claudeMdExcludes lists it; if so, keep the MEMORY.md bullet). Full procedure: $_MN_PROC. Nothing durable? Ignore this."

# Build with jq: the message interpolates measured values, and shell quoting is
# not JSON quoting — a hand-rolled heredoc would be a quoting bug waiting to land.
# A 🚨 overflow warning stays the first thing in the context; otherwise the episodic cue leads, so
# the routine budget line does not bury it.
if [ "$OVERFLOW" -eq 1 ]; then
  _mn_ctx="${BUDGET_CTX:+$BUDGET_CTX }${_MN_CUE:+$_MN_CUE }$NUDGE"
else
  _mn_ctx="${_MN_CUE:+$_MN_CUE }${BUDGET_CTX:+$BUDGET_CTX }$NUDGE"
fi
jq -cn --arg ctx "$_mn_ctx" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
exit 0
