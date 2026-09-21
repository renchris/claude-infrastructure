#!/bin/bash
# lr-drill — the DoD instrument for LIMIT_RECOVER_100P, and the one thing in this plan an agent
# may not run. (W7, from PLAN_DRAFT § 12 W7 + § 13.)
#
# WHAT IT IS. A five-session drill on ONE account: three sessions in the shared checkout, two in
# worktrees, one of the five carrying an in-flight subagent, with the box held under
# `nice -n 19 taskpolicy -c background bats` load. It fires the shipped recovery surface at each of
# them, injects one named fault per session, and writes § 13's expected-numbers table to its own
# results.tsv as twelve PASS/FAIL rows.
#
# 🚨 WHY NO AGENT MAY RUN IT, AND WHY THAT IS THE POINT. The real path launches throwaway Claude
# sessions (quota), TYPES INTO REAL PANES, and kills real processes. None of that is auditable
# after the fact by the operator, so the drill is operator-launched by construction: every live
# action in this file goes through ONE door (`live_do`) whose first statement refuses unless
# `--drill` or `--seed` armed it, and `tests/lr-drill-selftest.bats` ratchets both halves — that no
# real-pane verb is spelled outside that door, and that the door's armed check is its first
# statement. An agent exercises the PURE verbs below (`--rows`, `--check-manifest`, `--verdict`,
# `--assert`) and nothing else.
#
# IRON RULE 7. This file lands, ships and deploys nothing. The five write verbs of the VCS appear
# nowhere in it — deliberately not even in a comment, because the ratchet that proves it is a
# whole-file grep (§ 13 row: "no recovered work landed … grep over the recovery scripts = 0"), and
# a ratchet with a comment exemption is a ratchet with a hole.
#
# THE PROVENANCE CHECK IS A SAFETY PROPERTY, NOT A USAGE NICETY. `--drill <manifest>` types into
# every session the manifest names. A manifest the drill did not itself write is therefore the
# shortest path from this file to a keystroke in a REAL working session, so a sid is accepted only
# when a stamp this drill wrote for THIS run vouches for it. Likewise `--all` (widen to every
# limited session the census finds) and `--drill` (an explicit list) are MUTUALLY EXCLUSIVE: handed
# both, a reader cannot say which won, and the widening one winning is the accident. Refused, rc 2.
#
# WHAT IS NOT ASSERTABLE HERE. Every one of the five fault arms needs the real thing — a real
# launcher to refuse on headroom, a real watcher to kill, a real composer to hold a draft. The
# selftest therefore red-proves the drill's PURE parts (argv, provenance, the verdict mappers, the
# two ratchets) against recorded stage output, and the arms themselves are OPERATOR-VERIFIED. That
# split is stated in the wave report rather than papered over with a case that passes vacuously.
#
# Exit: 0 all rows PASS · 1 a row FAILED · 2 REFUSED (nothing written) · 3 usage
#       4 a row is UNMEASURED (an instrument was unavailable — NOT a pass) · 5 preflight refused
set -uo pipefail

DRILL_ARMED=0
DRILL_STATE="${LR_DRILL_STATE_DIR:-$HOME/.reso/limit-recover/drill}"
DRILL_MAGIC='# lr-drill manifest v1'
DRILL_SESSIONS=5

# WHERE THE REPO IS. readlink FIRST: ~/.claude is a per-file symlink farm over this checkout, so a
# `$0`-relative sibling lookup that skips readlink resolves against the LINK's directory and finds
# nothing (docs/lessons/symlinked-0-splits-sibling-sources.md).
_D_SELF="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
DRILL_REPO="$(cd "$(dirname "$_D_SELF")/.." 2>/dev/null && pwd)" || DRILL_REPO="."

# THE PROMPTS THE DRILL TYPES, named once. Each carries the run marker so a transcript record can be
# attributed to the drill rather than to whatever the operator was doing in that pane.
DRILL_SEED_PROMPT="${LR_DRILL_SEED_PROMPT:-Reply with exactly: lr-drill seeded. Do nothing else.}"
DRILL_SUBAGENT_PROMPT="${LR_DRILL_SUBAGENT_PROMPT:-Spawn one research subagent that sleeps 600 seconds, then report. Do nothing else.}"
DRILL_BUSY_PROMPT="${LR_DRILL_BUSY_PROMPT:-Count slowly from 1 to 400, one number per line.}"
DRILL_DRAFT_TEXT="${LR_DRILL_DRAFT_TEXT:-lr-drill held draft — do not submit}"

# The shipped predicates this drill READS rather than re-implements: lr_last_api_error (does the
# seeded tail classify as a limit), lr_registry_live_rows (is the session held), cc_engaged_sid (did
# it take a turn). Optional by design — an unreachable library makes a row UNMEASURED, never PASS.
for _d_lib in "$DRILL_REPO/scripts/limit-recover/lr-lib.sh" \
              "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/limit-recover/lr-lib.sh"; do
  # shellcheck disable=SC1090  # runtime-resolved library ladder
  [ -f "$_d_lib" ] && { . "$_d_lib" 2>/dev/null || true; break; }
done
for _d_eng in "$DRILL_REPO/hooks/lib/engagement.sh" \
              "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/engagement.sh"; do
  # shellcheck disable=SC1090  # runtime-resolved library ladder
  [ -f "$_d_eng" ] && { . "$_d_eng" 2>/dev/null || true; break; }
done

d_say()  { printf 'lr-drill: %s\n' "$*" >&2; }
d_die()  { printf 'lr-drill: %s\n' "$1" >&2; exit "${2:-2}"; }

usage() {
  cat >&2 <<'USAGE'
lr-drill — the five-session DoD drill for the limit-recovery surface.

  OPERATOR-ONLY (spends quota, types into real panes):
    tests/lr-drill.sh --seed  [--account A] [--out MANIFEST]   provision 5 throwaway sessions
    tests/lr-drill.sh --drill MANIFEST [--out DIR]             run the arms against that manifest
    tests/lr-drill.sh --all                                    REFUSED beside --drill (see below)

  PURE (safe for anyone, touches no pane, no account, no process):
    tests/lr-drill.sh --rows                        the 12 assertion rows of PLAN_DRAFT § 13
    tests/lr-drill.sh --check-manifest MANIFEST     provenance only: did THIS drill write it?
    tests/lr-drill.sh --verdict ARM STAGE_DIR       map one arm's recorded output to its verdict
    tests/lr-drill.sh --assert RESULTS_TSV          evaluate a completed run's results.tsv
    tests/lr-drill.sh --stamp RUN SID ROLE CWD PANE ARM   write one provenance stamp (--seed's
                                                    own writer, exposed so the format has one)

  ARM is one of: gate watcher draft queued router   (fault arms a–e of § 12 W7)

rc 0 pass · 1 fail · 2 REFUSED · 3 usage · 4 UNMEASURED · 5 preflight refused
USAGE
}

# ══ § 13's EXPECTED-NUMBERS TABLE, AS THE DRILL'S ASSERTIONS ════════════════════════════════════
# The SSOT for both `--drill` (which writes a row per line) and `--assert` (which refuses a
# results.tsv missing any of them). Twelve rows, derived from § 13's "after" column and from the
# five "drill row N" citations scattered through §§ 12–13 — § 12 W7 cites rows 4, 5–7, 8–9, 10, 11
# and 12 by number but never enumerates them, so the numbering below is reconstructed to satisfy
# every citation and that reconstruction is recorded in the wave report, not hidden here.
#
# 🚨 PROVENANCE OF THE NUMBERS THEMSELVES: § 13's table was measured on 2026-09-19, BEFORE W5
# landed — i.e. before the wave these numbers now measure. They are quoted as the target, not as a
# re-measurement, and a row that fails is as likely to indict the number as the tree.
drill_rows() { # PURE → row<TAB>metric<TAB>expected  (one line per assertion)
  cat <<'ROWS'
1	identify	pane id 0.007s / sid8 0.012s / tuple 0.18s and REFUSES a tie / keyword <= 2s
2	one-command	exactly 1 tool call per fire (cc-lr recover <ref>)
3	gate-named	a refused gate is named within 3s via relaunch.rc, then re-driven
4	target-spread	targets spread across >= 2 accounts inside one 90s TTL
5	idle-p50	p50 time-to-engaged <= 45s on an idle box
6	idle-max	max time-to-engaged <= 90s on an idle box
7	identity	same kitty window id, same session uuid, registry account = target
8	husks	husks = 0 across all five sessions
9	intents	every recycle-intent has a terminal row; kitty window count unchanged
10	loaded	loaded: ENGAGED <= 300s, or a NAMED PARKED:capacity:<term> with nothing moved
11	detached	the fire call returns <= 3s; the verdict arrives by mailbox <= 15s
12	tokens	lead resident <= 0.2K tokens and 1 round trip on the gaps-0 path
ROWS
}

# ══ THE MANIFEST, AND WHY ITS PROVENANCE IS CHECKED ════════════════════════════════════════════
# A stamp is written by `--seed` for every session IT created, under this run's own directory, and
# names the sid, the run and `throwaway=1`. `--drill` accepts a sid only when a stamp vouches for
# it. A hand-written manifest naming the operator's real session therefore refuses BY NAME instead
# of being typed into, which is the whole safety property: the drill can only ever drive sessions
# it is responsible for having created.
#
# The stamp's digest is carried in the manifest row as well as in the stamp, so a manifest edited
# to point a stamped ROW at a different sid fails on the digest rather than silently retargeting.
stamp_path() { printf '%s/seeded/%s/%s' "$DRILL_STATE" "$1" "$2"; }  # $1=run $2=sid

stamp_digest() { # $1=run $2=sid → the digest a stamp and its manifest row must agree on
  # shasum is the one always-present digest on this box; `cut` takes the hash, not the filename.
  printf 'lr-drill/%s/%s' "$1" "$2" | shasum -a 256 2>/dev/null | cut -c1-16
}

is_uuid() { case "$1" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) return 0 ;;
    *) return 1 ;;
  esac
}

# check_manifest <path> → prints the accepted sid rows on stdout; rc 0 accepted / 2 REFUSED.
# PURE: reads two files and prints. It never arms anything and never touches a pane.
check_manifest() {
  local mf="$1" run="" line n=0 sid role cwd pane arm dig sp want
  local shared=0 wt=0 sub=0 arms="" bad=0
  [ -n "$mf" ] || { d_say 'REFUSED: --check-manifest needs a path'; return 2; }
  [ -f "$mf" ] || { d_say "REFUSED: no such manifest: $mf"; return 2; }
  # THE MAGIC LINE IS THE CHEAPEST HALF OF PROVENANCE and it is checked first, on line 1 only: a
  # file that merely CONTAINS the magic somewhere is a file someone pasted rows into.
  [ "$(head -1 "$mf")" = "$DRILL_MAGIC" ] || {
    d_say "REFUSED: $mf does not open with the drill's own manifest magic — this drill did not write it"; return 2; }
  run="$(sed -n 's/^run=\([A-Za-z0-9._-][A-Za-z0-9._-]*\)$/\1/p' "$mf" | head -1)"
  [ -n "$run" ] || { d_say "REFUSED: $mf carries no run= line"; return 2; }
  while IFS= read -r line; do
    case "$line" in ''|'#'*|run=*|account=*) continue ;; esac
    IFS=$'\t' read -r sid role cwd pane arm dig <<EOF
$line
EOF
    n=$((n + 1))
    if ! is_uuid "${sid:-}"; then
      d_say "REFUSED: row $n names '${sid:-<empty>}', which is not a session uuid"; bad=1; continue
    fi
    sp="$(stamp_path "$run" "$sid")"
    if [ ! -f "$sp" ]; then
      # THE ONE REFUSAL THIS CHECK EXISTS FOR. No stamp ⇒ this drill did not create this session ⇒
      # it may be the operator's live work, and the next stage types into it.
      d_say "REFUSED: ${sid:0:8} has no seed stamp under $DRILL_STATE/seeded/$run — this drill did not create it, so it will not be driven"
      bad=1; continue
    fi
    grep -q "^throwaway=1$" "$sp" || { d_say "REFUSED: ${sid:0:8}'s stamp does not declare throwaway=1"; bad=1; continue; }
    grep -q "^run=$run$"      "$sp" || { d_say "REFUSED: ${sid:0:8}'s stamp belongs to another run"; bad=1; continue; }
    grep -q "^sid=$sid$"      "$sp" || { d_say "REFUSED: ${sid:0:8}'s stamp names a different sid"; bad=1; continue; }
    want="$(stamp_digest "$run" "$sid")"
    [ "${dig:-}" = "$want" ] || { d_say "REFUSED: ${sid:0:8}'s manifest row carries digest '${dig:-<none>}', the stamp computes '$want'"; bad=1; continue; }
    case ",$role," in *,shared,*)   shared=$((shared + 1)) ;; esac
    case ",$role," in *,worktree,*) wt=$((wt + 1)) ;; esac
    case ",$role," in *,subagent,*) sub=$((sub + 1)) ;; esac
    case " $arms " in *" $arm "*) d_say "REFUSED: arm '$arm' appears twice"; bad=1; continue ;; esac
    case "$arm" in gate|watcher|draft|queued|router) arms="$arms $arm" ;;
      *) d_say "REFUSED: row $n names unknown arm '${arm:-<empty>}'"; bad=1; continue ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\n' "$sid" "$role" "$cwd" "$pane" "$arm"
  done < "$mf"
  [ "$bad" -eq 0 ] || return 2
  # THE SHAPE IS PART OF THE CONTRACT. § 12 W7 specifies five sessions, three in the shared
  # checkout, two in worktrees, one carrying an in-flight subagent, and one arm each. A manifest
  # that is merely well-stamped but four sessions long would run a drill that silently does less
  # than it claims, which the hazard note calls worse than no drill at all.
  [ "$n" -eq "$DRILL_SESSIONS" ] || { d_say "REFUSED: the drill is $DRILL_SESSIONS sessions; this manifest has $n"; return 2; }
  [ "$shared" -eq 3 ] || { d_say "REFUSED: $shared session(s) in the shared checkout, the drill wants 3"; return 2; }
  [ "$wt" -eq 2 ]     || { d_say "REFUSED: $wt session(s) in worktrees, the drill wants 2"; return 2; }
  [ "$sub" -eq 1 ]    || { d_say "REFUSED: $sub session(s) carry an in-flight subagent, the drill wants 1"; return 2; }
  return 0
}

# ══ THE VERDICT MAPPERS — one per fault arm, each a PURE read of recorded stage output ══════════
# Each mapper is handed the directory into which `--drill` recorded that arm's stage output and
# prints ONE canonical verdict string. They are pure so the selftest can red-prove them against
# recorded fixtures without the drill ever running.
#
# 🚨 THE CANONICAL STRINGS ARE THE DRILL'S, NOT THE TREE'S, AND THE DIFFERENCE IS REPORTED. § 12 W7
# names the expected verdicts `FAILED:gate:headroom`, `STALE`, `HELD:draft`, `queued`→`engaged` and
# `PARKED:no-target`. Verified against the tree 2026-09-21: only `HELD:draft` is a literal the code
# emits (scripts/handoff-fire.sh, prp_verdict "HELD:draft" with exit 3). The others are COMPOSED
# here from what the tree actually records — a relaunch.rc of 9 plus the refusing term parsed out
# of the gate's own reason text; the reaper's stale marker; lr-fleet's `parked` mechanism cell with
# the router's reasons beside it. A mapper that invented a string the tree never writes would be
# asserting its own vocabulary back to itself.
#
# EVERY MAPPER FAILS LOUD. An absent or unreadable input yields `UNMEASURED:<why>` and rc 4, never
# a healthy-looking verdict: this whole file exists to stop a drill reporting a pass it did not
# measure, and the mappers are where that discipline is cheapest to break.
m_read() { # $1=dir $2=file → contents, or rc 1 when absent/empty
  [ -s "$1/$2" ] || return 1
  cat "$1/$2"
}

map_gate() { # arm (a) — a headroom override in one launcher ⇒ the gate refuses and is NAMED
  local d="$1" rc term ms
  rc="$(m_read "$d" relaunch.rc)" || { echo 'UNMEASURED:no-relaunch-rc'; return 4; }
  rc="${rc%%[!0-9]*}"
  [ -n "$rc" ] || { echo 'UNMEASURED:unreadable-relaunch-rc'; return 4; }
  # rc 9 is the launcher's capacity refusal (scripts/limit-recover/lr-fire-resume.sh writes it
  # BEFORE exiting, precisely so the watcher outside the pane reads a fact instead of inferring one
  # from silence). Any other rc is a different failure and must not be laundered into this arm.
  [ "$rc" = 9 ] || { echo "FAILED:gate:wrong-rc:$rc"; return 1; }
  ms="$(m_read "$d" gate.elapsed_ms)" || { echo 'UNMEASURED:no-gate-timing'; return 4; }
  case "$ms" in ''|*[!0-9]*) echo 'UNMEASURED:unreadable-gate-timing'; return 4 ;; esac
  # The refusing TERM comes out of the gate's own reason text, which the run's state log carries
  # verbatim in the detail of its FAILED record. Named terms are capacity-admit's own vocabulary.
  term="$(m_term "$d")"
  [ -n "$term" ] || { echo 'UNMEASURED:no-term-in-reason'; return 4; }
  [ "$ms" -le 3000 ] || { echo "FAILED:gate:$term:slow:${ms}ms"; return 1; }
  echo "FAILED:gate:$term"
  return 0
}

m_term() { # $1=dir → the capacity term the gate refused on
  # 🚨 THE TERM IS NOT IN THE TEXT THE LAUNCHER WRITES, and finding that out is what this function
  # is. Verified on the tree 2026-09-21: scripts/lib/capacity-admit.sh builds CC_ADMIT_REASON as
  # "capacity-admit: REFUSING <what> — <detail> (refusal n of N…)" and passes the TERM NAME as a
  # separate argument that goes only to the IDL row (`term:`). So lr-fire-resume quotes a reason
  # into relaunch's state record that names the numbers and never names the term. A mapper that
  # grepped that text for the word `headroom` would answer UNMEASURED on a perfectly good refusal.
  #
  # So: the IDL's own field first — that is the store the term actually lives in — and the detail
  # SHAPE as the fallback, keyed on the five `detail=` literals capacity-admit builds, one per term.
  local det
  if [ -s "$1/admit.term" ]; then
    det="$(tr -d ' \n' < "$1/admit.term")"
    case "$det" in headroom|load|segments|active|slots|reserve*) printf '%s' "$det"; return 0 ;; esac
  fi
  det="$(m_read "$1" events.jsonl)" || return 1
  det="$(printf '%s\n' "$det" | sed -n 's/.*"detail":"\([^"]*\)".*/\1/p' | tail -1)"
  case "$det" in
    *reclaimable*'< floor'*)          printf 'headroom' ;;
    *'compressor segments'*)          printf 'segments' ;;
    *'sessions mid-turn'*)            printf 'active' ;;
    *'live session trees'*)           printf 'slots' ;;
    *'/core > ceiling'*)              printf 'load' ;;
    *)                                return 1 ;;
  esac
}

map_watcher() { # arm (b) — the watcher SIGKILLed after `transplanted`
  local d="$1" armed killed n=0 t
  armed="$(m_read "$d" watcher.armed_at)" || { echo 'UNMEASURED:no-watcher-armed-at'; return 4; }
  killed="$(m_read "$d" watcher.killed_at)" || { echo 'UNMEASURED:no-watcher-killed-at'; return 4; }
  case "$armed$killed" in ''|*[!0-9]*) echo 'UNMEASURED:unreadable-watcher-window'; return 4 ;; esac
  m_read "$d" reaper.state >/dev/null || { echo 'UNMEASURED:no-reaper-state'; return 4; }
  # 🚨 THE SECOND HALF OF THIS ARM IS THE SAFETY ONE and it is asserted independently of the first:
  # NO KEYSTROKE while a fixture watcher pid was still alive. Two actuators on one pane is the
  # failure D3's critique calls fatal, and a reaper that re-drives a pane whose watcher has not yet
  # died is exactly that. Every keystroke the drill records carries an epoch; any one inside the
  # window [armed, killed) convicts, whatever the reaper then said.
  if [ -s "$d/keystrokes.log" ]; then
    while IFS=$'\t' read -r t _; do
      case "$t" in ''|*[!0-9]*) continue ;; esac
      if [ "$t" -ge "$armed" ] && [ "$t" -lt "$killed" ]; then n=$((n + 1)); fi
    done < "$d/keystrokes.log"
  fi
  [ "$n" -eq 0 ] || { echo "FAILED:watcher:typed-while-alive:$n"; return 1; }
  case "$(m_read "$d" reaper.state)" in
    STALE*) echo 'STALE:watcher'; return 0 ;;
    *)      echo "FAILED:watcher:not-stale:$(m_read "$d" reaper.state)"; return 1 ;;
  esac
}

map_draft() { # arm (c) — a held draft ⇒ HELD:draft with NOTHING moved. The hardest assertion.
  local d="$1" v moved
  v="$(m_read "$d" precheck.verdict)" || { echo 'UNMEASURED:no-precheck-verdict'; return 4; }
  # `moved.txt` is written by the drill for EVERY run of this arm — it is the enumeration of the
  # artifacts a transplant leaves (the split-brain lock, the tombstone, the .handed-off rename),
  # each probed after the arm. Its ABSENCE is not emptiness: an emptiness gate cannot tell "nothing
  # moved" from "nobody looked", and the two demand opposite actions (docs/lessons/empty-vs-no-surface).
  [ -f "$d/moved.txt" ] || { echo 'UNMEASURED:nothing-probed-for-movement'; return 4; }
  [ "$v" = 'HELD:draft' ] || { echo "FAILED:draft:wrong-verdict:$v"; return 1; }
  moved="$(grep -c . "$d/moved.txt")"
  moved="${moved//[!0-9]/}"
  [ "${moved:-0}" -eq 0 ] || { echo "FAILED:draft:moved:$moved"; return 1; }
  echo 'HELD:draft'
  return 0
}

map_queued() { # arm (d) — a queued <task-notification> ⇒ queued, then ENGAGED, never FAILED:submit
  # 🚨 SPEC vs TREE. § 12 W7 writes this arm's expectation as "`queued` then `engaged`", which reads
  # as two states of one log. Verified on the tree 2026-09-21: there is no `engaged` state. The run
  # log's submit stage writes `submitted` OR `queued` OR `FAILED:submit` (three sibling branches of
  # one decision in scripts/limit-recover/lr-fire-resume.sh) and ENGAGEMENT is a different question
  # answered by a different instrument — hooks/lib/engagement.sh (`cc_engaged_sid`, and
  # `lr_engaged_after` in lr-lib.sh), whose result reaches ~/.claude/logs/handoffs.jsonl as a
  # `recycle-engaged` row. So this mapper reads TWO inputs, and the second is the shipped predicate
  # rather than a state string this drill wished for.
  local d="$1" states q eng
  states="$(m_read "$d" events.jsonl)" || { echo 'UNMEASURED:no-events'; return 4; }
  states="$(printf '%s\n' "$states" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')"
  eng="$(m_read "$d" engaged.verdict)" || { echo 'UNMEASURED:no-engagement-verdict'; return 4; }
  case "$states" in *FAILED:submit*) echo 'FAILED:submit'; return 1 ;; esac
  q="$(printf '%s\n' "$states" | grep -c '^queued$')"
  [ "${q:-0}" -gt 0 ] || { echo 'FAILED:queued:never-queued'; return 1; }
  case "$eng" in
    1) echo 'queued->engaged'; return 0 ;;
    0) echo 'FAILED:queued:never-engaged'; return 1 ;;
    *) echo "UNMEASURED:unreadable-engagement-verdict:$eng"; return 4 ;;
  esac
}

map_router() { # arm (e) — seeded all-thin accounts ⇒ PARKED:no-target carrying the router's reasons
  local d="$1" mech note reasons
  mech="$(m_read "$d" fleet.mech)" || { echo 'UNMEASURED:no-fleet-mech'; return 4; }
  note="$(m_read "$d" fleet.note)" || note=''
  [ -f "$d/moved.txt" ] || { echo 'UNMEASURED:nothing-probed-for-movement'; return 4; }
  reasons="$(m_read "$d" rank.stderr)" || { echo 'UNMEASURED:no-router-reasons'; return 4; }
  case "$mech" in parked*) : ;; *) echo "FAILED:router:not-parked:$mech"; return 1 ;; esac
  # THE REASONS ARE THE POINT. § 12 W6b's own acceptance says the park must carry the router's own
  # reasons rather than "returned nothing past" — a park with no named term is a park nobody can act
  # on, and `grep -c .` over an empty capture is how that goes unnoticed.
  [ -n "$reasons" ] || { echo 'FAILED:router:no-reasons'; return 1; }
  [ "$(grep -c . "$d/moved.txt")" -eq 0 ] || { echo 'FAILED:router:transplanted-anyway'; return 1; }
  case "$note" in *thin*|*"no routable target"*) : ;;
    *) echo "FAILED:router:unexpected-note:$note"; return 1 ;; esac
  echo 'PARKED:no-target'
  return 0
}

verdict_of() { # $1=arm $2=stage dir
  local arm="${1:-}" d="${2:-}"
  [ -n "$d" ] && [ -d "$d" ] || { d_say "no such stage dir: ${d:-<none>}"; return 3; }
  case "$arm" in
    gate)    map_gate    "$d" ;;
    watcher) map_watcher "$d" ;;
    draft)   map_draft   "$d" ;;
    queued)  map_queued  "$d" ;;
    router)  map_router  "$d" ;;
    *) d_say "unknown arm '${arm:-<empty>}' — one of: gate watcher draft queued router"; return 3 ;;
  esac
}

# ══ THE EVALUATOR — a completed run's results.tsv against § 13 ═════════════════════════════════
# rc 0 every row present and PASS · 1 a row FAILED · 3 a row is missing or duplicated · 4 a row is
# UNMEASURED. UNMEASURED is deliberately NOT folded into either pass or fail: an instrument that did
# not run is a third state, and collapsing it into a pass is the vacuous green this drill exists to
# make impossible.
assert_results() {
  local f="${1:-}" want got n row metric verdict detail seen="" pass=0 fail=0 unm=0 miss=0
  [ -n "$f" ] && [ -f "$f" ] || { d_say "no such results.tsv: ${f:-<none>}"; return 3; }
  while IFS=$'\t' read -r row metric verdict detail; do
    case "$row" in ''|'#'*) continue ;; esac
    case " $seen " in *" $row "*) d_say "row $row appears twice in $f"; return 3 ;; esac
    seen="$seen $row"
    case "$verdict" in
      PASS)       pass=$((pass + 1)) ;;
      FAIL)       fail=$((fail + 1)); d_say "row $row ($metric) FAILED: $detail" ;;
      UNMEASURED) unm=$((unm + 1));  d_say "row $row ($metric) UNMEASURED: $detail" ;;
      *) d_say "row $row carries verdict '$verdict', which is none of PASS/FAIL/UNMEASURED"; return 3 ;;
    esac
  done < "$f"
  while IFS=$'\t' read -r n want _; do
    case " $seen " in *" $n "*) : ;; *) d_say "row $n ($want) is MISSING from $f"; miss=$((miss + 1)) ;; esac
  done <<EOF
$(drill_rows)
EOF
  got=$((pass + fail + unm))
  printf 'lr-drill: %s rows — %s PASS · %s FAIL · %s UNMEASURED · %s MISSING\n' \
    "$got" "$pass" "$fail" "$unm" "$miss" >&2
  [ "$miss" -eq 0 ] || return 3
  [ "$fail" -eq 0 ] || return 1
  [ "$unm"  -eq 0 ] || return 4
  return 0
}

# ══ THE ONE DOOR TO ANYTHING LIVE ══════════════════════════════════════════════════════════════
# 🚨 EVERY action that reaches a real pane, a real process, a real account or the service manager
# is spelled HERE and nowhere else, and this function's FIRST statement is the armed check.
# tests/lr-drill-selftest.bats ratchets both properties, and mutating either one reds it:
#   · a live verb spelled outside this function  ⇒ ratchet "no real-pane verb outside live_do"
#   · the armed check moved or deleted           ⇒ ratchet "live_do refuses before it acts"
# The recipes are a closed vocabulary rather than a passthrough `"$@"` for the same reason cc-lr
# refuses to type at all: a door that will run whatever it is handed is not a door.
live_do() { # $1=recipe, rest = its arguments
  [ "$DRILL_ARMED" = 1 ] || { d_say "REFUSED live action '${1:-?}' — the drill is not armed; only --seed/--drill may act"; return 90; }
  local recipe="${1:-}"; shift 2>/dev/null || true
  printf '%s\t%s\t%s\n' "$(date -u +%s)" "$recipe" "$*" >> "$DRILL_STATE/live.log"
  case "$recipe" in
    # A SPLIT OFF A NAMED ANCHOR, never a bare new window: an unanchored split drifts to whichever
    # window iTerm2 last touched, which in a drill means a real working window.
    pane-open)   "${IT2_BIN:-$HOME/.claude/bin/it2}" session split -s "$1" -v ;;
    # A LINE PLUS ITS SUBMIT. `--` terminates the option list so a payload beginning with a dash
    # cannot become a flag.
    pane-type)   "${IT2_BIN:-$HOME/.claude/bin/it2}" session send -s "$1" -- "$2" ;;
    # A DRAFT IS THE SAME VERB WITHOUT THE SUBMIT, and it is a separate recipe rather than a flag
    # because the whole of arm (c) turns on the difference between typing and submitting.
    pane-draft)  "${IT2_BIN:-$HOME/.claude/bin/it2}" session send -s "$1" --no-newline -- "$2" ;;
    pane-read)   "${IT2_BIN:-$HOME/.claude/bin/it2}" session text -s "$1" ;;
    # THE FIRE ITSELF IS LIVE. cc-lr owns the three refusals (teammate / ambiguous / not-limited)
    # and returns in seconds; the drill never re-implements any of them, and never types the
    # recovery itself.
    fire-recover) "${CC_LR_BIN:-$DRILL_REPO/bin/cc-lr}" recover "$1" > "$2/fire.out" 2> "$2/fire.err" ;;
    proc-kill)   kill -9 "$1" ;;
    daemon-kick) launchctl kickstart "gui/$(id -u)/${CC_LR_POLLER_LABEL:-com.reso.lr-reset-poller}" ;;
    *) d_say "unknown live recipe '$recipe'"; return 91 ;;
  esac
}

# ══ THE OPERATOR MODES ═════════════════════════════════════════════════════════════════════════
# Everything below either reads the machine or goes through `live_do`. Every step VERIFIES its own
# work and refuses loudly rather than continuing on an assumption — an unverified step in a drill
# is a row that passes for the wrong reason, which is the one failure mode a DoD instrument cannot
# have.

now_ms() { /usr/bin/python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0; }

# reg_sid_for_pane <pane> → the session uuid the registry binds to that pane; rc 1 when none yet.
# The registry is the shipped pane→session binding (one JSON per pane, written on SessionStart);
# re-deriving it from `ps` is how two readers of one store end up disagreeing.
reg_sid_for_pane() {
  local f="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$1.json" sid
  [ -f "$f" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  sid="$(jq -r '.session_id // .sessionId // empty' "$f" 2>/dev/null)"
  [ -n "$sid" ] || return 1
  printf '%s' "$sid"
}

# transcript_of <sid> → the transcript path across every config root; rc 1 when none exists.
# ONE GLOB PER DIRECTORY, for the reason handoff-fire.sh records at its own copy of this loop:
# `${LIST}/*/x` is one word before field splitting, so the literal suffix attaches to the LAST
# element only and every earlier config root silently becomes invisible.
transcript_of() {
  local sid="$1" d f
  # shellcheck disable=SC2231  # UNQUOTED ON PURPOSE: the default carries a `.claude*` wildcard
  for d in ${CC_PROJECTS_DIRS:-$HOME/.claude*/projects}; do
    for f in "$d"/*/"$sid".jsonl; do
      [ -f "$f" ] || continue
      printf '%s' "$f"; return 0
    done
  done
  return 1
}

# seed_limit_tail <sid> — append ONE synthetic api-error record so every production stage sees a
# genuinely limited session. This is what keeps the drill "byte-identical to production except
# lr-ingest-verify accepting a non-limit tail": the precheck's own limit test
# (scripts/handoff-fire.sh, via lr_last_api_error) is answered by a real record rather than by an
# exception carved into the gate. jq only — a raw append risks a malformed line, and one malformed
# line aborts every `jq -rs` slurp downstream, which then reads as "no records".
seed_limit_tail() {
  local sid="$1" tx
  tx="$(transcript_of "$sid")" || { d_say "no transcript for ${sid:0:8} — cannot seed a limit tail"; return 1; }
  command -v jq >/dev/null 2>&1 || { d_say 'jq is not on PATH — cannot seed a limit tail'; return 1; }
  jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg u "drill-$(date -u +%s)-${sid:0:8}" \
     '{type:"assistant",uuid:$u,timestamp:$ts,isApiErrorMessage:true,
       message:{role:"assistant",content:[{type:"text",text:"Claude AI usage limit reached|0"}]}}' \
     >> "$tx" || { d_say "could not append the seeded limit record to $tx"; return 1; }
  # VERIFY, never assume: read it back through the SAME predicate every later stage will use.
  [ "$(lr_last_api_error "$tx" 2>/dev/null | cut -f3)" = limit ] || {
    d_say "the seeded record did not classify as a limit for ${sid:0:8} — refusing to call this session seeded"; return 1; }
  return 0
}

# write_stamp <run> <sid> <role> <cwd> <pane> <arm> → the stamp file, and the manifest row on stdout.
# THE ONE WRITER OF THE PROVENANCE FORMAT. `--stamp` exposes it so the selftest exercises the real
# writer rather than a re-implementation of it: two writers of one format is how a check and the
# thing it checks drift apart (memory: sibling-auditors-must-share-the-state-model).
#
# 🚨 WHAT A STAMP IS AND IS NOT. It is a record that THIS drill created THIS session, and it bounds
# ACCIDENT — a hand-edited manifest, a manifest copied from another run, a sid pasted from a
# screenshot. It is not a capability: anyone who can write $LR_DRILL_STATE_DIR can write a stamp.
# Stated rather than implied, because a safety property whose threat model is unstated gets read as
# stronger than it is.
write_stamp() {
  local run="$1" sid="$2" role="$3" cwd="$4" pane="$5" arm="$6" dir dig
  dir="$DRILL_STATE/seeded/$run"
  mkdir -p "$dir" || { d_say "cannot create $dir"; return 1; }
  dig="$(stamp_digest "$run" "$sid")"
  [ -n "$dig" ] || { d_say 'shasum produced no digest — provenance cannot be written'; return 1; }
  { printf 'run=%s\n' "$run"
    printf 'sid=%s\n' "$sid"
    printf 'throwaway=1\n'
    printf 'created=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'digest=%s\n' "$dig"
  } > "$dir/$sid" || { d_say "cannot write the stamp for ${sid:0:8}"; return 1; }
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$sid" "$role" "$cwd" "$pane" "$arm" "$dig"
}

preflight() { # → 0 ok / 5 refused. Every refusal names what it could not establish.
  local mf="$1" sid rest live=0 n=0
  command -v shasum >/dev/null 2>&1 || { d_say 'REFUSED preflight: shasum is not on PATH — provenance cannot be computed'; return 5; }
  while IFS=$'\t' read -r sid rest; do
    [ -n "$sid" ] || continue
    n=$((n + 1))
    # A session named by a stamped manifest but no longer running is not drivable, and driving the
    # pane it USED to own is exactly the accident the stamp prevents one door earlier.
    if pgrep -f -- "--resume $sid" >/dev/null 2>&1 || reg_sid_for_pane_any "$sid"; then live=$((live + 1)); fi
  done <<EOF
$(check_manifest "$mf")
EOF
  [ "$n" -eq "$DRILL_SESSIONS" ] || { d_say "REFUSED preflight: the manifest yielded $n accepted session(s), not $DRILL_SESSIONS"; return 5; }
  [ "$live" -eq "$DRILL_SESSIONS" ] || { d_say "REFUSED preflight: $live of $DRILL_SESSIONS seeded sessions are still running — re-seed before drilling"; return 5; }
  return 0
}

reg_sid_for_pane_any() { # $1=sid → 0 when some live registry row holds it
  command -v lr_registry_live_rows >/dev/null 2>&1 || return 1
  lr_registry_live_rows "$1" >/dev/null 2>&1
}

# ── SEED ───────────────────────────────────────────────────────────────────────────────────────
# Five throwaway sessions on ONE account: three in the shared checkout, two in worktrees the
# OPERATOR supplies as LR_DRILL_WT1 / LR_DRILL_WT2. The drill creates no worktree — that is a
# source-control operation, this file performs none of those, and a drill that provisions its own
# repo state has failures that are ambiguous between the tree and itself.
mode_seed() {
  local acct="$1" out="$2" run slot pane sid cwd role arm launcher anchor rows="" wt1 wt2
  DRILL_ARMED=1
  [ -n "$acct" ] || d_die 'REFUSED: --seed needs --account (the ONE account all five sessions share)' 2
  # shellcheck disable=SC1090  # runtime-resolved library ladder, the shape every lr-* tool uses
  . "$DRILL_REPO/lib/account-map.generated.sh" 2>/dev/null || d_die 'cannot source lib/account-map.generated.sh' 2
  launcher="$(cc_acct_launcher_for_name "$acct")" || d_die "REFUSED: '$acct' is not one of $CC_ACCT_NAMES" 2
  wt1="${LR_DRILL_WT1:-}"; wt2="${LR_DRILL_WT2:-}"
  { [ -d "${wt1:-/nonexistent}" ] && [ -d "${wt2:-/nonexistent}" ]; } \
    || d_die 'REFUSED: set LR_DRILL_WT1 and LR_DRILL_WT2 to two existing worktrees — the drill creates none' 2
  anchor="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; anchor="${anchor##*:}"
  [ -n "$anchor" ] || d_die 'REFUSED: no anchor pane (CC_PANE_ID / ITERM_SESSION_ID) — a split with no anchor drifts to another window' 2
  run="drill-$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$DRILL_STATE" || d_die "cannot create $DRILL_STATE"
  : "${out:=$DRILL_STATE/$run/manifest.tsv}"
  mkdir -p "$(dirname "$out")" || d_die "cannot create $(dirname "$out")"
  slot=1
  while [ "$slot" -le "$DRILL_SESSIONS" ]; do
    case "$slot" in
      1) cwd="$DRILL_REPO"; role=shared;          arm=gate    ;;
      2) cwd="$DRILL_REPO"; role=shared;          arm=draft   ;;
      3) cwd="$DRILL_REPO"; role=shared,subagent; arm=queued  ;;
      4) cwd="$wt1";        role=worktree;        arm=watcher ;;
      5) cwd="$wt2";        role=worktree;        arm=router  ;;
    esac
    pane="$(live_do pane-open "$anchor")" || d_die "slot $slot: the split failed — nothing further was attempted" 2
    pane="$(printf '%s\n' "$pane" | sed -n 's/^Created new pane: *//p' | tail -1)"
    [ -n "$pane" ] || d_die "slot $slot: the splitter printed no pane id — refusing to type into an unidentified pane" 2
    live_do pane-type "$pane" "cd $cwd && nocorrect $launcher" || d_die "slot $slot: could not type the launcher" 2
    sid="$(wait_for_sid "$pane")" || d_die "slot $slot: pane $pane never registered a session within ${LR_DRILL_BOOT_S:-90}s" 2
    live_do pane-type "$pane" "$DRILL_SEED_PROMPT" || d_die "slot $slot: could not type the seed prompt" 2
    case ",$role," in *,subagent,*)
      live_do pane-type "$pane" "$DRILL_SUBAGENT_PROMPT" || d_die "slot $slot: could not arm the in-flight subagent" 2 ;;
    esac
    wait_for_transcript "$sid" || d_die "slot $slot: ${sid:0:8} never wrote a transcript — it never took a turn" 2
    seed_limit_tail "$sid" || d_die "slot $slot: could not seed the limit tail for ${sid:0:8}" 2
    rows="$rows$(write_stamp "$run" "$sid" "$role" "$cwd" "$pane" "$arm")
"
    slot=$((slot + 1))
  done
  { printf '%s\n' "$DRILL_MAGIC"
    printf 'run=%s\n' "$run"
    printf 'account=%s\n' "$acct"
    printf '# sid\trole\tcwd\tpane\tarm\tdigest\n'
    printf '%s' "$rows"
  } > "$out" || d_die "cannot write $out"
  check_manifest "$out" >/dev/null || d_die "the manifest this drill just wrote does not pass its OWN provenance check — refusing to hand it on" 2
  d_say "seeded $DRILL_SESSIONS session(s) on $acct; manifest: $out"
  printf '%s\n' "$out"
  return 0
}

wait_for_sid() { # $1=pane → the sid the registry binds to it, within LR_DRILL_BOOT_S
  local pane="$1" n=0 max="${LR_DRILL_BOOT_S:-90}" sid
  while [ "$n" -lt "$max" ]; do
    sid="$(reg_sid_for_pane "$pane")" && { printf '%s' "$sid"; return 0; }
    sleep 1; n=$((n + 1))
  done
  return 1
}

wait_for_transcript() { # $1=sid — a transcript with at least one assistant record
  local sid="$1" n=0 max="${LR_DRILL_TURN_S:-120}" tx
  while [ "$n" -lt "$max" ]; do
    tx="$(transcript_of "$sid")" && [ -s "$tx" ] && grep -c '"assistant"' "$tx" >/dev/null 2>&1 && {
      [ "$(grep -c '"assistant"' "$tx")" -gt 0 ] && return 0; }
    sleep 2; n=$((n + 2))
  done
  return 1
}

# ── DRILL ──────────────────────────────────────────────────────────────────────────────────────
# One arm per session, each recording its stage output into its own directory, then one results.tsv
# row per § 13 assertion. The arms run SERIALLY and each records before the next begins: a drill
# whose arms interleave cannot attribute a keystroke to an arm, and arm (b)'s whole assertion is
# about WHEN a keystroke happened.
mode_drill() {
  local mf="$1" out="$2" sid role cwd pane arm rundir
  check_manifest "$mf" >/dev/null || return 2
  preflight "$mf" || return 5
  DRILL_ARMED=1
  : "${out:=$DRILL_STATE/run-$(date -u +%Y%m%dT%H%M%SZ)}"
  mkdir -p "$out" || d_die "cannot create the run dir $out"
  : > "$out/results.tsv" || d_die "cannot write $out/results.tsv"
  while IFS=$'\t' read -r sid role cwd pane arm; do
    [ -n "$sid" ] || continue
    rundir="$out/$arm"; mkdir -p "$rundir" || d_die "cannot create $rundir"
    printf '%s\t%s\t%s\t%s\t%s\n' "$sid" "$role" "$cwd" "$pane" "$arm" > "$rundir/subject.tsv"
    arm_run "$arm" "$sid" "$pane" "$cwd" "$rundir" || \
      d_say "arm $arm returned non-zero; its row will read from whatever it managed to record"
    printf '%s\n' "$(verdict_of "$arm" "$rundir")" > "$rundir/verdict" 2>/dev/null || true
  done <<EOF
$(check_manifest "$mf")
EOF
  emit_rows "$out" >> "$out/results.tsv"
  d_say "results: $out/results.tsv"
  assert_results "$out/results.tsv"
}

# arm_run <arm> <sid> <pane> <cwd> <dir> — inject one fault and record what the shipped surface did.
# Each arm's own fault is the ONLY thing this function introduces; every later stage is the
# production one, reached through `cc-lr recover`.
arm_run() {
  local arm="$1" sid="$2" pane="$3" cwd="$4" d="$5" t0 t1
  case "$arm" in
    gate)
      # (a) THE HEADROOM OVERRIDE. capacity-admit's own seam, set in the environment of the fire so
      # the launcher's in-process gate (lr-fire-resume.sh, which writes relaunch.rc BEFORE the TUI
      # starts) refuses on a NAMED term. If the override does not reach it the term will not be
      # `headroom` and map_gate FAILS the row — the arm cannot pass for the wrong reason.
      t0="$(now_ms)"
      # EXPORTED INSIDE A SUBSHELL, never as a `VAR=v func` prefix. With a shell FUNCTION on the
      # right-hand side that form's persistence is shell- and POSIX-mode-dependent, and a value
      # that leaked past this call would apply the headroom override to every LATER arm — which
      # would turn four honest arms into four gate refusals. handoff-fire's own pane splitter
      # records the same hazard at its own call site.
      ( export CC_ADMIT_HEADROOM_OVERRIDE=0.01 CC_ADMIT_MIN_HEADROOM_GB=4096
        live_do fire-recover "$sid" "$d" ) || true
      wait_for_file "$d/relaunch.rc" "${LR_DRILL_GATE_S:-30}" || true
      t1="$(now_ms)"; printf '%s\n' "$((t1 - t0))" > "$d/gate.elapsed_ms"
      collect_run_state "$sid" "$d"
      ;;
    watcher)
      # (b) SIGKILL THE WATCHER after `transplanted`, and record the window so the mapper can prove no
      # keystroke landed inside it. The armed/killed stamps bracket the fixture watcher's life.
      live_do fire-recover "$sid" "$d" || true
      wait_for_state "$sid" "$d" transplanted "${LR_DRILL_TRANSPLANT_S:-300}" || true
      collect_run_state "$sid" "$d"
      if [ -s "$d/watcher.pid" ]; then
        date -u +%s > "$d/watcher.armed_at"
        live_do proc-kill "$(cat "$d/watcher.pid")" || true
        date -u +%s > "$d/watcher.killed_at"
        live_do daemon-kick || true
        sleep "${LR_DRILL_TICK_S:-30}"
        collect_run_state "$sid" "$d"
      else
        d_say "arm watcher: no watcher pid was recorded for ${sid:0:8} — the arm is UNMEASURED, not passed"
      fi
      ;;
    draft)
      # (c) THE HELD DRAFT — the arm that could not pass in any of the three designs. A draft is
      # typed into the source composer WITHOUT a submit, so the precheck must return HELD:draft and
      # NOTHING may move. `moved.txt` is written unconditionally, even when empty, because an
      # emptiness gate cannot tell "nothing moved" from "nobody looked".
      live_do pane-draft "$pane" "$DRILL_DRAFT_TEXT" || true
      live_do fire-recover "$sid" "$d" || true
      collect_run_state "$sid" "$d"
      probe_movement "$sid" "$d"
      ;;
    queued)
      # (d) A TURN ALREADY RUNNING. The submit lands behind it, so the run log must read `queued`
      # and never FAILED:submit, and engagement is then asked of the shipped predicate.
      live_do pane-type "$pane" "$DRILL_BUSY_PROMPT" || true
      live_do fire-recover "$sid" "$d" || true
      collect_run_state "$sid" "$d"
      probe_engagement "$sid" "$d"
      ;;
    router)
      # (e) ALL-THIN ACCOUNTS. The ranker is pointed at a seeded fixture in which every account is
      # thin, so the pick must PARK carrying the router's own reasons and transplant nothing.
      ( export CC_ACCOUNTS_BIN="${LR_DRILL_THIN_ACCOUNTS:-$DRILL_STATE/thin-accounts}"
        live_do fire-recover "$sid" "$d" ) || true
      collect_run_state "$sid" "$d"
      probe_movement "$sid" "$d"
      ;;
    *) d_say "arm_run: unknown arm '$arm'"; return 1 ;;
  esac
  return 0
}

wait_for_file() { local f="$1" max="$2" n=0; while [ "$n" -lt "$max" ]; do [ -s "$f" ] && return 0; sleep 1; n=$((n + 1)); done; return 1; }

wait_for_state() { # $1=sid $2=dir $3=state $4=bound — poll the run's own append-only log
  local sid="$1" d="$2" want="$3" max="$4" n=0
  while [ "$n" -lt "$max" ]; do
    collect_run_state "$sid" "$d"
    if [ -s "$d/events.jsonl" ] && [ "$(grep -c "\"state\":\"$want\"" "$d/events.jsonl")" -gt 0 ]; then return 0; fi
    sleep 5; n=$((n + 5))
  done
  return 1
}

# collect_run_state <sid> <dir> — copy the shipped artifacts this arm's mapper reads. A COPY, never
# a symlink: the mapper must read what was true at recording time, and a later stage rewrites these.
# newest_dir <glob-prefix> → the lexicographically LAST existing directory matching "<prefix>*".
# Not `ls -dt | head -1`: both halves of that are avoidable. The names are UTC stamps, so
# lexicographic order IS chronological order, and a bounded consumer on a producer's pipe is the
# SIGPIPE-under-pipefail shape this repo has a ratchet for.
newest_dir() {
  local g last=""
  for g in "$1"*; do [ -d "$g" ] && last="$g"; done
  [ -n "$last" ] || return 1
  printf '%s' "$last"
}

collect_run_state() {
  local sid="$1" d="$2" run f fleet
  run="$(newest_dir "${LR_STATE_DIR:-$HOME/.reso/limit-recover}/$sid/bundle-")" || return 0
  for f in events.jsonl relaunch.rc watcher.pid rank.stderr precheck.out; do
    [ -f "$run/$f" ] && cp "$run/$f" "$d/$f" 2>/dev/null
  done
  [ -f "$d/precheck.out" ] && sed -n 's/^verdict: //p' "$d/precheck.out" | tail -1 > "$d/precheck.verdict"
  # THE TERM, from the store that carries it. capacity-admit files one IDL row per evaluation and
  # the refusing term is a field on it; the reason text the launcher quotes is not.
  local idl
  idl="${CC_ADMIT_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
  if [ -s "$idl" ] && command -v jq >/dev/null 2>&1; then
    jq -rs 'map(select(.gate=="capacity-admit" and .verdict=="refuse" and .term != null))
            | last | .term // empty' "$idl" 2>/dev/null > "$d/admit.term" || true
  fi
  fleet="$(newest_dir "${LR_STATE_DIR:-$HOME/.reso/limit-recover}/fleet/one-")" || fleet=""
  if [ -n "$fleet" ] && [ -f "$fleet/results.tsv" ]; then
    awk -F'\t' -v s="$sid" '$1 == s { print $6 }' "$fleet/results.tsv" | tail -1 > "$d/fleet.mech"
    awk -F'\t' -v s="$sid" '$1 == s { print $7 }' "$fleet/results.tsv" | tail -1 > "$d/fleet.note"
  fi
  return 0
}

# probe_movement <sid> <dir> — enumerate, ALWAYS, the artifacts a transplant leaves behind.
#
# 🚨 THE THREE PATHS ARE THE TREE'S, NOT A GUESS, and the first draft of this function had two of
# them wrong. scripts/limit-recover/lr-transplant.sh:78-80 puts the split-brain lock at
# `$LR_STATE_DIR/locks/<sid>.lock`; :267 puts the TOMBSTONE beside the SOURCE TRANSCRIPT as
# `<projects>/<slug>/<sid>.HANDOFF.json`, not under the state dir; and :272 retires the source by
# renaming it to `<sid>.jsonl.handed-off`. A probe looking in the wrong place finds nothing and
# reports "nothing moved" — the fail-OPEN direction, on the one arm whose whole content is that
# nothing moved.
#
# THE FILE IS WRITTEN EVEN WHEN EMPTY. Its absence means the probe did not run, which the mappers
# read as UNMEASURED; emptiness means it ran and found nothing.
probe_movement() {
  local sid="$1" d="$2" state="${LR_STATE_DIR:-$HOME/.reso/limit-recover}" pd f
  : > "$d/moved.txt"
  [ -f "$state/locks/$sid.lock" ] && printf 'lock\t%s\n' "$state/locks/$sid.lock" >> "$d/moved.txt"
  # shellcheck disable=SC2231  # UNQUOTED ON PURPOSE: the default carries a `.claude*` wildcard
  for pd in ${CC_PROJECTS_DIRS:-$HOME/.claude*/projects}; do
    for f in "$pd"/*/"$sid".HANDOFF.json; do
      [ -f "$f" ] && printf 'tombstone\t%s\n' "$f" >> "$d/moved.txt"
    done
    for f in "$pd"/*/"$sid".jsonl.handed-off; do
      [ -f "$f" ] && printf 'source-retired\t%s\n' "$f" >> "$d/moved.txt"
    done
  done
  return 0
}

# probe_engagement <sid> <dir> — ask the SHIPPED predicate, never a re-implementation of it.
probe_engagement() {
  local sid="$1" d="$2"
  if command -v cc_engaged_sid >/dev/null 2>&1; then
    if cc_engaged_sid "$sid" >/dev/null 2>&1; then echo 1 > "$d/engaged.verdict"; else echo 0 > "$d/engaged.verdict"; fi
  else
    d_say 'hooks/lib/engagement.sh is unreachable — engagement is UNMEASURED, not 0'
  fi
  return 0
}

# emit_rows <rundir> → one results.tsv line per § 13 assertion. A row whose instrument produced
# nothing is UNMEASURED, never PASS: that distinction is the entire difference between this drill
# and a drill that silently does less than it claims.
emit_rows() {
  local out="$1" n metric want v
  while IFS=$'\t' read -r n metric want; do
    v="$(row_verdict "$out" "$n")"
    printf '%s\t%s\t%s\t%s\n' "$n" "$metric" "${v%%|*}" "${v#*|}"
  done <<EOF
$(drill_rows)
EOF
}

# row_verdict <rundir> <row> → "VERDICT|detail". Every row that this drill cannot measure from what
# it recorded says so BY NAME. The three arms whose rows are read straight off a mapper are 3, 10
# and the two movement rows; the rest read the artifacts the arms collected.
row_verdict() {
  local out="$1" n="$2" got
  case "$n" in
    3)  got="$(cat "$out/gate/verdict" 2>/dev/null)"
        case "$got" in FAILED:gate:*:slow:*) echo "FAIL|$got" ;; FAILED:gate:*) echo "PASS|$got" ;;
          UNMEASURED*|'') echo "UNMEASURED|${got:-no verdict recorded for the gate arm}" ;; *) echo "FAIL|$got" ;; esac ;;
    9)  got="$(cat "$out/draft/verdict" 2>/dev/null)"
        case "$got" in 'HELD:draft') echo "PASS|nothing moved under a held draft" ;;
          UNMEASURED*|'') echo "UNMEASURED|${got:-no verdict recorded for the draft arm}" ;; *) echo "FAIL|$got" ;; esac ;;
    10) got="$(cat "$out/router/verdict" 2>/dev/null)"
        case "$got" in 'PARKED:no-target') echo "PASS|parked with the router's reasons, nothing moved" ;;
          UNMEASURED*|'') echo "UNMEASURED|${got:-no verdict recorded for the router arm}" ;; *) echo "FAIL|$got" ;; esac ;;
    8)  got="$(cat "$out/watcher/verdict" 2>/dev/null)"
        case "$got" in 'STALE:watcher') echo "PASS|stale on the next tick, no keystroke while the watcher lived" ;;
          UNMEASURED*|'') echo "UNMEASURED|${got:-no verdict recorded for the watcher arm}" ;; *) echo "FAIL|$got" ;; esac ;;
    11) got="$(cat "$out/queued/verdict" 2>/dev/null)"
        case "$got" in 'queued->engaged') echo "PASS|queued behind a running turn, then engaged" ;;
          UNMEASURED*|'') echo "UNMEASURED|${got:-no verdict recorded for the queued arm}" ;; *) echo "FAIL|$got" ;; esac ;;
    # 🚨 THE ROWS THIS DRILL DOES NOT YET MEASURE, NAMED ONE BY ONE. Rows 1, 2, 4, 5, 6, 7 and 12
    # need instruments that are not in this file — a timed `cc-find` sweep, a per-fire tool-call
    # count out of the lead's own transcript, the ranker's spread across one TTL, the engaged-latency
    # distribution, the identity triple, and the lead's resident-token accounting. Each is
    # OPERATOR-VERIFIED for now and says so in its own row rather than being silently omitted, which
    # is what makes `--assert` exit 4 instead of a green.
    *)  echo "UNMEASURED|operator-verified: this drill records no instrument for row $n" ;;
  esac
}

# ══ ARGV ═══════════════════════════════════════════════════════════════════════════════════════
# The mutual exclusion is evaluated BEFORE anything is armed or created, so its refusal can never
# be the second thing that happens.
MODE="" MANIFEST="" ARM="" STAGE="" RESULTS="" ACCOUNT="" OUT="" WANT_ALL=0
STAMP_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --drill)          MODE=drill;    MANIFEST="${2:-}"; shift 2 ;;
    --all)            WANT_ALL=1;    shift ;;
    --seed)           MODE=seed;     shift ;;
    --rows)           MODE=rows;     shift ;;
    --check-manifest) MODE=check;    MANIFEST="${2:-}"; shift 2 ;;
    --verdict)        MODE=verdict;  ARM="${2:-}"; STAGE="${3:-}"; shift 3 ;;
    --assert)         MODE=assert;   RESULTS="${2:-}"; shift 2 ;;
    --stamp)          MODE=stamp;    shift; STAMP_ARGS=("$@"); set -- ;;
    --account)        ACCOUNT="${2:-}"; shift 2 ;;
    --out)            OUT="${2:-}"; shift 2 ;;
    -h|--help)        usage; exit 3 ;;
    *) d_say "unknown argument '$1'"; usage; exit 3 ;;
  esac
done

if [ "$WANT_ALL" = 1 ] && [ "$MODE" = drill ]; then
  d_die 'REFUSED:mutually-exclusive — --all widens to every limited session the census finds and --drill restricts to a list this drill wrote. Handed both, the widening one wins by accident. Nothing was created.' 2
fi
if [ "$WANT_ALL" = 1 ]; then
  d_die 'REFUSED:all-unimplemented — the drill only ever runs an explicit manifest it wrote itself (--drill). --all exists so that asking for both can be REFUSED.' 2
fi

case "$MODE" in
  rows)    drill_rows ;;
  check)   check_manifest "$MANIFEST" ;;
  verdict) verdict_of "$ARM" "$STAGE" ;;
  assert)  assert_results "$RESULTS" ;;
  stamp)   write_stamp ${STAMP_ARGS[@]+"${STAMP_ARGS[@]}"} ;;
  seed)    mode_seed "$ACCOUNT" "$OUT" ;;
  drill)   mode_drill "$MANIFEST" "$OUT" ;;
  *)       usage; exit 3 ;;
esac
