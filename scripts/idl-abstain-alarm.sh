#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the selftest's `cond && okp || badp` reporter idiom (okp/badp always return 0)
# idl-abstain-alarm.sh — T-P6-4 / "abstain-alarm D9": the IDL abstention monitor.
#
# WHY (blind-check law §3i, boundary-handoff:17-19): a check whose whole job is to FIRE
# but which ABSTAINS 100% of the time is indistinguishable from a DEAD check — "didn't
# fire" and "never evaluated" are the same observation. The canonical incident (P0-1):
# the gate-green producer was never wired, so boundary-handoff abstained 100% in prod
# ("gate-not-green-at-head" / "no-telemetry") — FM1(b) silently inert behind a green
# selftest. This monitor sweeps the IDL and PAGES (via the nightly-regression host) when
# a check is PROVABLY inert.
#
# THE FALSE-POSITIVE TRAP (boundary-handoff:41-49, re-observed 2026-07-19): the naive
# rule "abstained==100% over N>=10 REGARDLESS of reason" is a STRUCTURAL false positive.
# Every live hook is at 100% abstained today — waiting-recycle (not-armed),
# boundary-handoff (below-threshold), completion-assert (ledger-clean/no-close-tell),
# anti-deference-nudge (no-tell) — all HEALTHY-DORMANT (the guard WAS evaluated and the
# fire condition was legitimately false). A regardless-of-reason alarm would page on all
# four every night. So this monitor DISCRIMINATES the abstention REASON:
#   BLIND    — the check could not OBSERVE its guard at all (missing input / telemetry /
#              transcript / repo). 100%-blind over N>=10 == "no check" == INERT == PAGE.
#   DORMANT  — the guard WAS reached; the fire condition was legitimately not met.
#              100%-dormant is a healthy quiet advisory — NEVER a page.
# A single DORMANT abstention proves the check CAN reach its guard, so a hook is inert
# only when EVERY in-window abstention is blind (blind_share >= CC_ABSTAIN_BLIND_PCT,
# default 100). New/unclassified reasons default to DORMANT (fail toward NOT paging) and
# are surfaced in the DORMANT-100 report line for human review — no silent 3am false page.
#
# ── THE cc-backlog reap ENROLLMENT (backlog 420b9cb2166c) ────────────────────────────
# `cc-backlog reap` decides whether a claim's WORKER is dead. Its two oracles are
# three-valued, and on a NON-VERDICT (rc 2 — registry absent/wedged, or the occupancy
# probe never ran) it KEEPs the claim and says so: `keep claimer-unresolved` /
# `keep worktree-unresolved`. Those are not a quiet guard — they are literally "I could
# not observe the thing I exist to observe", the exact class §3i pages on. A registry
# that stays dark makes reap unable to reap ANY dead worker, and nothing else notices:
# the items simply never come back to the wave.
#
# Reap did not emit that signal into this sweep, for a stated reason (cc-backlog:996) —
# its journal rows are {actor:"cc-backlog-reap", action:"verdict"}, the cc-dispatch row
# family, deliberately NOT {hook, disposition}, so that adding a decision journal could
# not enroll reap in a nightly PAGING population against whose reason vocabulary it had
# never been calibrated. That calibration is what this section is.
#
# THE PROJECTION IS DONE HERE, NOT AT THE WRITER, for two reasons. (1) Blast radius:
# `.hook` + `.disposition` are read by cc-audit, cc-digest, cc-discover, desk-invariant,
# desk-recycle-invariant and subagent-stop; hook-shaping the writer would enroll reap in
# ALL of them at once, where the item asks for exactly one consumer. (2) History: a
# writer-side change is visible only for rows written AFTER it lands, so the 14-day
# window would be partially blind for 14 days; projecting at the reader sees every row
# already on disk. tests/cc-backlog.bats pins the row as NOT hook-shaped — that pin stays
# green and keeps meaning what it says.
#
# THE CALIBRATION (reap's KEEP vocabulary is its abstention vocabulary — see the arrays):
#   claimer-live         DORMANT  oracle 1 ANSWERED: the claimer is alive. Guard reached.
#   owned-wait           DORMANT  oracle 2 ANSWERED: the worktree is occupied. Guard reached.
#   claimer-unresolved   BLIND    rc 2 — the liveness registry gave no answer at all.
#   worktree-unresolved  BLIND    rc 2 — the occupancy probe could not be asked at all.
# block/reopen verdicts are the check ACTING, so they map to fired (or `failed` when the
# ledger REFUSED the transition — `acted:false`) and they break the 100%-abstained
# condition, exactly as a hook's own fire does.
#
# WHAT THIS DOES AND DOES NOT COVER — reap's abstention is BOUNDED: past
# CC_BACKLOG_UNRESOLVED_MAX_S a blind keep escalates to `block …-unresolvable-…`, which
# parks the item in front of a human. That escalation is a FIRE here, so a starvation
# that reaches the ceiling reads HEALTHY and does not also page. That is the intended
# split, not a gap: this alarm is the backstop for blindness NOBODY ELSE announces, and
# the loud half already announces itself. The case it uniquely catches is the quiet one —
# a dark registry while items still complete on their own, where reap abstains forever,
# escalates nothing, and its liveness oracle is inert with no other tell.
#
# A NEW REAP REASON MUST NOT SILENTLY LAND IN THE DORMANT DEFAULT. "Unclassified ⇒
# DORMANT" is the right global bias, but for THIS enrollment it is a fail-open: a future
# blind keep-reason would be classified quiet and the enrollment would go half-inert with
# a green suite. `--vocab-lint` asserts reap's emitted keep-vocabulary equals the two
# arrays below, in BOTH directions (memory: downward-ratchet-catches-the-over-scoped-marker),
# and fails loud if its extractor matches nothing at all.
#
# VERDICT per hook, over the lookback window (schema = objects with BOTH .hook +
# .disposition, plus cc-backlog-reap verdict rows projected into it):
#   INERT (RED, exit!=0)   total>=N_MIN AND abstained==total AND blind_share>=BLIND_PCT
#   DORMANT-100 (green)    total>=N_MIN AND abstained==total AND blind_share< BLIND_PCT   (reported, not paged)
#   HEALTHY (green)        has fired/passed, OR total<N_MIN
#
# Read-only. Appends one summary line to CC_ABSTAIN_LOG. On >=1 INERT hook it prints the
# inert hook(s) and exits non-zero, so the nightly-regression host writes ONE page to
# autonomy/pages/ (drainable by the P0-15 desk consumer). C10: no live edits — the
# already-loaded nightly-regression plist runs THIS repo script (no re-install needed).
#
# Modes: --run (default; live sweep, exit reflects inert) · --report (table, ALWAYS exit 0) ·
#        --vocab-lint [cc-backlog] (reap keep-vocabulary completeness, source-only, no IDL) ·
#        --selftest (RED-provable, side-effect-free).
# Env seams (tests + tuning): CC_IDL · CC_ABSTAIN_LOG · CC_ABSTAIN_NMIN (10) ·
#        CC_ABSTAIN_LOOKBACK_DAYS (14) · CC_ABSTAIN_BLIND_PCT (100) ·
#        CC_ABSTAIN_BLIND_REASONS (space/newline list — REPLACES the default blind set) ·
#        CC_ABSTAIN_NOW (epoch — deterministic "now" for tests).
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
LOG="${CC_ABSTAIN_LOG:-$HOME/.claude/autonomy/abstain-alarm.log}"
NMIN="${CC_ABSTAIN_NMIN:-10}"
LOOKBACK_DAYS="${CC_ABSTAIN_LOOKBACK_DAYS:-14}"
BLIND_PCT="${CC_ABSTAIN_BLIND_PCT:-100}"

# cc-backlog reap's KEEP vocabulary, split by class — the SSOT for both the blind set below
# and `--vocab-lint`. Kept as its own pair of arrays rather than folded into the flat list
# because the lint has to check the DORMANT half too: a reap keep-reason that is in NEITHER
# array is the fail-open this enrollment cannot afford (see the header).
_reap_keep_blind=(claimer-unresolved worktree-unresolved)
_reap_keep_dormant=(claimer-live owned-wait)

# BLIND reason-tokens (matched against the reason substring BEFORE the first ':'). These are
# the unambiguous "could not observe my guard" reasons drawn from the live hook vocabulary
# (boundary-handoff / anti-deference-nudge / completion-assert / waiting-recycle), plus the
# reap keep-reasons above. Everything NOT listed is treated as DORMANT (condition-not-met) —
# conservative against false pages.
_default_blind=(no-jq no-session-id no-stdin no-telemetry stale-telemetry \
                no-transcript-path transcript-missing not-a-repo no-cwd no-assistant-text \
                "${_reap_keep_blind[@]}")
if [ -n "${CC_ABSTAIN_BLIND_REASONS:-}" ]; then
  # shellcheck disable=SC2206  # intentional word-split of the override list
  BLIND=($CC_ABSTAIN_BLIND_REASONS)
else
  BLIND=("${_default_blind[@]}")
fi
BLIND_JSON="$(printf '%s\n' "${BLIND[@]}" | jq -Rsc 'split("\n")|map(select(length>0))')"

now_epoch() { echo "${CC_ABSTAIN_NOW:-$(date +%s)}"; }
now_iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ── the sweep: aggregate the IDL per hook, classify, report, and set the exit code ──
# $1 = mode: "run" (exit reflects inert) | "report" (always 0)
sweep() {
  local mode="${1:-run}"
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

  command -v jq >/dev/null 2>&1 || {
    # No jq: this monitor cannot observe ITS OWN guard — fail loud, not silent-green.
    printf 'idl-abstain-alarm: RED — jq unavailable, cannot sweep the IDL (self-blind)\n'
    printf '%s idl-abstain-alarm: RED self-blind (no-jq)\n' "$(now_iso)" >> "$LOG" 2>/dev/null || true
    [ "$mode" = report ] && return 0 || return 1
  }

  if [ ! -f "$IDL" ] || [ ! -s "$IDL" ]; then
    printf 'idl-abstain-alarm: GREEN — no IDL at %s (nothing to sweep)\n' "$IDL"
    printf '%s idl-abstain-alarm: GREEN no-idl\n' "$(now_iso)" >> "$LOG" 2>/dev/null || true
    return 0
  fi

  local now cutoff
  now="$(now_epoch)"
  cutoff="$(( now - LOOKBACK_DAYS * 86400 ))"

  # malformed-line accounting (plan ethos: report, never silently drop)
  local raw parsed malformed
  raw="$(grep -cve '^[[:space:]]*$' "$IDL" 2>/dev/null || echo 0)"
  parsed="$(jq -R 'fromjson? // empty' "$IDL" 2>/dev/null | grep -c . || echo 0)"
  malformed="$(( raw - parsed ))"; [ "$malformed" -lt 0 ] && malformed=0

  # one jq pass → one TSV row per hook: hook total abstained productive failed blind
  # TSV field-collapse guard (docs/research/TSV_FIELD_COLLAPSE_2026-07-25.md): tab is
  # IFS-*whitespace*, so `IFS=$'\t' read` collapses a RUN of tabs and an empty `.hook` group key
  # would shift all five COUNTS one place left — an inert-hook detector reporting another hook's
  # numbers, which is precisely the silent-green this alarm exists to catch. Only `.hook` can be
  # empty (the rest are `length`), and it pads to $'\037' rather than a visible placeholder
  # because the reader tests it for emptiness (`[ -n "$hook" ] || continue`).
  # DENOMINATOR = EVALUATIONS ONLY (2026-08-08). Both problem verdicts key on `abst == total`, so a
  # record in `total` that is NOT an evaluation of the guard can only ever WEAKEN them. The shipped
  # contract is exactly four dispositions (premortem-gate.sh:90 — "every check ships emitting
  # {fired|passed|abstained|failed}"); housekeeping rows that never reached the guard are not
  # evaluations and must not dilute it. waiting-recycle emits `gc`/bats-pollution sweep records and
  # session-continue emits `armed`/`cleared` lifecycle rows, neither of which evaluates anything.
  # Measured live: waiting-recycle at total=2868 abst=2864 fired=0 reported HEALTHY on the strength
  # of 4 `gc` rows, while the idle-recycle actuator had fired ZERO times in 14 days — see
  # docs/research/idle-recycle-not-proactive-2026-08-08.md. Strictly TIGHTENING: a hook with no
  # evaluations leaves the table rather than posing as healthy, and nothing previously INERT or
  # DORMANT-100 can become HEALTHY through this filter.
  # memory: positive-control-the-denominator - new-enum-member-falls-into-fail-closed-default
  local agg TSV_PAD=$'\037'
  local EVAL_JSON='["fired","passed","abstained","failed"]'
  agg="$(jq -Rrn --argjson cutoff "$cutoff" --argjson blind "$BLIND_JSON" \
                 --argjson evals "$EVAL_JSON" --arg pad "$TSV_PAD" '
    def cell: (if . == null then "" else . end) | tostring
              | gsub("[\\t\\r\\n]"; " ") | if . == "" then $pad else . end;
    [ inputs
      | (fromjson? // null) | select(. != null)
      # Shape FIRST, window second: the IDL is dominated by lead-supervisor heartbeat rows (27k of
      # 33k live, and this file has historically reached 370k lines), so the cheap key test must stay
      # in front of the fromdateiso8601 parse — the nightly does three O(n) passes over this file.
      | select(((.hook? != null) and (.disposition? != null))
               or ((.actor? == "cc-backlog-reap") and (.action? == "verdict")))
      | select(((.ts // "") | fromdateiso8601? // 0) >= $cutoff)
      # Hook rows pass through; cc-backlog reap verdict rows are PROJECTED into the same shape
      # (see the header § reap enrollment). The hook branch is tested FIRST so that a row
      # carrying both shapes — should the writer ever be hook-shaped too — is counted ONCE,
      # under its own schema, instead of twice.
      | (if (.hook? != null) and (.disposition? != null) then
           { hook: .hook, disp: .disposition, rt: ((.reason // "") | split(":")[0]) }
         elif (.actor? == "cc-backlog-reap") and (.action? == "verdict") then
           # keep = no transition = abstained. block/reopen = the check acting; `acted:false`
           # is the ledger REFUSING that transition, which is a failure of the action, not an
           # abstention — either way it proves reap reached its guard. A row with no `.acted`
           # at all reads productive, the direction that does not manufacture a page.
           { hook: "cc-backlog-reap",
             disp: (if .verdict == "keep" then "abstained"
                    elif .acted == false then "failed"
                    else "fired" end),
             rt: ((.reason // "") | split(":")[0]) }
         else empty end)
      # DENOMINATOR = EVALUATIONS ONLY (d8ac7a22), applied to the PROJECTED disposition rather than
      # the raw `.disposition`. It has to run here: a reap verdict row carries no `.disposition` at
      # all, so the raw-field form would drop EVERY reap row and leave this enrollment inert. On a
      # hook row the two are the same field, so the d8ac7a22 contract is unchanged; on a reap
      # row the projection only ever yields the four contract dispositions, so all of them are
      # evaluations — which is correct, since idl_verdict writes nothing BUT verdicts.
      | select(.disp as $d | ($evals | index($d)) != null) ]
    | group_by(.hook)
    | map(. as $g | {
        hook:       $g[0].hook,
        total:      ($g | length),
        abstained:  ([ $g[] | select(.disp=="abstained") ] | length),
        productive: ([ $g[] | select(.disp=="fired" or .disp=="passed") ] | length),
        failed:     ([ $g[] | select(.disp=="failed") ] | length),
        blind:      ([ $g[] | select(.disp=="abstained")
                            | select(.rt as $x | ($blind | index($x)) != null) ] | length) })
    | .[]
    | [ (.hook | cell), .total, .abstained, .productive, .failed, .blind ] | @tsv
  ' "$IDL" 2>/dev/null || true)"

  local -a inert=() dormant100=()
  local nhooks=0 healthy=0
  local hook total abst prod failed blind pct verdict
  while IFS=$'\t' read -r hook total abst prod failed blind; do
    [ "$hook" = "$TSV_PAD" ] && hook=""       # un-pad: "" still means "no hook key", so skip
    [ -n "$hook" ] || continue
    nhooks=$(( nhooks + 1 ))
    pct=0; [ "$abst" -gt 0 ] && pct=$(( blind * 100 / abst ))
    if   [ "$total" -ge "$NMIN" ] && [ "$abst" -eq "$total" ] && [ "$pct" -ge "$BLIND_PCT" ]; then
      verdict=INERT;       inert+=("$hook")
    elif [ "$total" -ge "$NMIN" ] && [ "$abst" -eq "$total" ]; then
      verdict=DORMANT-100; dormant100+=("$hook")
    else
      verdict=HEALTHY;     healthy=$(( healthy + 1 ))
    fi
    printf '  %-11s %-22s total=%-4s abst=%-4s fired/passed=%-3s failed=%-3s blind=%-3s (%d%%)\n' \
      "$verdict" "$hook" "$total" "$abst" "$prod" "$failed" "$blind" "$pct"
  done <<< "$agg"

  local n_inert="${#inert[@]}" summary
  summary="hooks=$nhooks inert=$n_inert dormant100=${#dormant100[@]} healthy=$healthy window=${LOOKBACK_DAYS}d nmin=$NMIN blind_pct=$BLIND_PCT"
  [ "$malformed" -gt 0 ]      && summary="$summary malformed=$malformed"
  [ "$n_inert" -gt 0 ]        && summary="$summary INERT:[${inert[*]}]"
  [ "${#dormant100[@]}" -gt 0 ] && summary="$summary DORMANT-100:[${dormant100[*]}]"
  printf '%s idl-abstain-alarm: %s\n' "$(now_iso)" "$summary" >> "$LOG" 2>/dev/null || true

  if [ "$n_inert" -gt 0 ]; then
    printf 'idl-abstain-alarm: RED — %d inert check(s): %s\n' "$n_inert" "${inert[*]}"
    printf '  each abstained 100%% over >=%d evals with ONLY blind (cannot-observe) reasons — a check\n' "$NMIN"
    printf '  that cannot see its guard is no check (blind-check law §3i). detail: %s\n' "$LOG"
    [ "$mode" = report ] && return 0 || return 1
  fi
  printf 'idl-abstain-alarm: GREEN — %s\n' "$summary"
  return 0
}

# ── --vocab-lint: the reap keep-vocabulary completeness guard ───────────────────────────────────
# The enrollment classifies reap's KEEP reasons by hand, and the sweep's global default for an
# unclassified reason is DORMANT. That bias is right everywhere else and is a FAIL-OPEN here: a
# future blind keep-reason would be classified quiet, this enrollment would go half-inert, and the
# suite would stay green (memory: new-enum-member-falls-into-fail-closed-default). This asserts the
# two _reap_keep_* arrays are EXACTLY reap's emitted keep-vocabulary, in BOTH directions.
#
# Extraction is POSITIONAL awk over `idl_verdict "$id" keep <token>` — idl_verdict's signature fixes
# the verdict at $3 and the reason at $4 — rather than a regex, so no grep-flavour difference can
# move the verdict. Every failure mode is loud:
#   · reap emits a token neither array classifies      → RED (the fail-open this exists to close)
#   · an array classifies a token reap no longer emits → RED (the downward half — a classification
#     outliving its subject is a marker whose scope silently outgrew it, memory:
#     downward-ratchet-catches-the-over-scoped-marker)
#   · zero call sites matched, or a non-literal reason → RED. An extractor that cannot see its
#     subject must never report all-clear (memory: control-must-replay-the-real-artifact).
# Only `keep` needs classifying: block/reopen are the check ACTING, and any verdict word other than
# `keep` projects to fired — no reason lookup, so no fail-open to guard.
_in_list() { local n="$1"; shift; local x; for x in "$@"; do [ "$x" = "$n" ] && return 0; done; return 1; }

# shellcheck disable=SC2016  # the diagnostics QUOTE cc-backlog source (`idl_verdict "$id" keep …`);
                             # those $ must reach the operator's eye unexpanded.
vocab_lint() {
  local src="${1:-$(dirname "$SELF")/../bin/cc-backlog}"
  if [ ! -r "$src" ]; then
    printf 'idl-abstain-alarm --vocab-lint: RED — cannot read %s (nothing to lint)\n' "$src" >&2
    return 1
  fi
  local emitted; emitted="$(awk '$1=="idl_verdict" && $3=="keep" {print $4}' "$src" | sort -u)"
  if [ -z "$emitted" ]; then
    printf 'idl-abstain-alarm --vocab-lint: RED — 0 `idl_verdict … keep <reason>` call sites in %s\n' "$src" >&2
    printf '  This is the extractor going blind, NOT the subject coming up clean: with no keep\n' >&2
    printf '  verdicts to classify the whole lint would pass vacuously. Fix the extractor.\n' >&2
    return 1
  fi
  local -a emitted_arr=(); local tok rc=0
  while IFS= read -r tok; do [ -n "$tok" ] && emitted_arr+=("$tok"); done <<< "$emitted"

  for tok in "${emitted_arr[@]}"; do
    case "$tok" in *[!a-z0-9-]*)
      printf 'idl-abstain-alarm --vocab-lint: RED — keep reason %s is not a literal token\n' "$tok" >&2
      printf '  A reason passed as a variable cannot be classified from source. Give that keep site\n' >&2
      printf '  a literal token, as the other four have.\n' >&2
      rc=1; continue ;;
    esac
    if ! _in_list "$tok" "${_reap_keep_blind[@]}" && ! _in_list "$tok" "${_reap_keep_dormant[@]}"; then
      printf 'idl-abstain-alarm --vocab-lint: RED — reap emits `keep %s`, classified by NEITHER array\n' "$tok" >&2
      printf '  It would default to DORMANT and this enrollment would never page on it. Add it to\n' >&2
      printf '  _reap_keep_blind (the check could not OBSERVE its guard) or _reap_keep_dormant (the\n' >&2
      printf '  guard was reached and the condition was legitimately false).\n' >&2
      rc=1
    fi
  done
  for tok in "${_reap_keep_blind[@]}" "${_reap_keep_dormant[@]}"; do
    if ! _in_list "$tok" "${emitted_arr[@]}"; then
      printf 'idl-abstain-alarm --vocab-lint: RED — %s is classified here but reap emits no `keep %s`\n' "$tok" "$tok" >&2
      printf '  A stale classification hides a rename: the NEW spelling is then unclassified and\n' >&2
      printf '  defaults to DORMANT. Drop this token, or follow the rename.\n' >&2
      rc=1
    fi
  done

  if [ "$rc" -eq 0 ]; then
    printf 'idl-abstain-alarm --vocab-lint: GREEN — %d reap keep-reason(s) all classified (blind=[%s] dormant=[%s])\n' \
      "${#emitted_arr[@]}" "${_reap_keep_blind[*]}" "${_reap_keep_dormant[*]}"
  fi
  return "$rc"
}

# ════════════════ selftest — RED-prove the discriminator (deterministic, side-effect-free) ═════════
PASS=0; FAIL=0
# shellcheck disable=SC2317  # reached only in --selftest
okp()  { printf '  ok   %-58s\n' "$1"; PASS=$(( PASS + 1 )); }
# shellcheck disable=SC2317
badp() { printf '  FAIL %-58s\n' "$1"; FAIL=$(( FAIL + 1 )); }
# shellcheck disable=SC2317
selftest() {
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/abstain-alarm-selftest.XXXXXX")" || { echo mktemp failed; exit 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$d'" EXIT
  local NOW=1752900000 FIXTS OLDTS
  FIXTS="$(date -u -r "$NOW" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 2026-07-19T04:00:00Z)"
  OLDTS="$(date -u -r "$(( NOW - 30 * 86400 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 2026-06-19T04:00:00Z)"

  emit() { # <file> <n> <hook> <disp> <reason> [ts]
    local i ts="${6:-$FIXTS}"
    for ((i = 0; i < $2; i++)); do
      printf '{"ts":"%s","hook":"%s","sid":"s%d","disposition":"%s","reason":"%s"}\n' \
        "$ts" "$3" "$i" "$4" "$5" >> "$1"
    done
  }
  emit_reap() { # <file> <n> <verdict> <reason> <acted true|false> — the ACTOR-shaped reap row
    local i
    for ((i = 0; i < $2; i++)); do
      printf '{"ts":"%s","actor":"cc-backlog-reap","action":"verdict","id":"i%d","verdict":"%s","reason":"%s","acted":%s,"claim_by":"h-1","claim_age_s":9000,"attempts":1,"fast_fail":0,"claimer_rc":2,"worktree":null,"detail":"d"}\n' \
        "$FIXTS" "$i" "$3" "$4" "$5" >> "$1"
    done
  }
  run_alarm() { # <idl> [mode-arg] → runs the real script with a fixed clock
    env CC_IDL="$1" CC_ABSTAIN_NOW="$NOW" CC_ABSTAIN_LOG="$d/log" CC_ABSTAIN_NMIN=10 \
        CC_ABSTAIN_LOOKBACK_DAYS=14 CC_ABSTAIN_BLIND_PCT=100 "$SELF" "${2:---run}"
  }

  echo "idl-abstain-alarm --selftest:"

  # A. 100%-blind over N>=10 → INERT (RED, names the hook)
  local A="$d/a.jsonl"; emit "$A" 12 inert-hook abstained no-telemetry
  local out rc
  out="$(run_alarm "$A")"; rc=$?
  [ "$rc" -ne 0 ]                              && okp "A blind-100 → nonzero exit" || badp "A blind-100 exited 0"
  printf '%s' "$out" | grep -q 'inert-hook'    && okp "A blind-100 → names the inert hook" || badp "A did not name inert-hook"
  printf '%s' "$out" | grep -q 'INERT'         && okp "A blind-100 → INERT verdict printed" || badp "A no INERT verdict"

  # B. 100%-dormant over N>=10 → GREEN, NOT flagged (the boundary-handoff false-positive guard)
  local B="$d/b.jsonl"; emit "$B" 12 dormant-hook abstained below-threshold
  out="$(run_alarm "$B")"; rc=$?
  [ "$rc" -eq 0 ]                              && okp "B dormant-100 → exit 0" || badp "B dormant-100 nonzero exit"
  ! printf '%s' "$out" | grep -q 'INERT'       && okp "B dormant-100 → no INERT flag" || badp "B falsely flagged dormant as INERT"
  printf '%s' "$out" | grep -q 'DORMANT-100'   && okp "B dormant-100 → reported DORMANT-100" || badp "B not reported DORMANT-100"

  # C. mixed: 11 dormant + 1 blind (blind_share ~8% < 100) → GREEN (one dormant proves it can observe)
  local C="$d/c.jsonl"; emit "$C" 11 mixed-hook abstained below-threshold; emit "$C" 1 mixed-hook abstained no-telemetry
  out="$(run_alarm "$C")"; rc=$?
  [ "$rc" -eq 0 ]                              && okp "C mixed(1 blind) → exit 0" || badp "C mixed exited nonzero"
  ! printf '%s' "$out" | grep -q 'INERT'       && okp "C mixed → not INERT" || badp "C mixed wrongly INERT"

  # D. sub-threshold: 5 blind (< NMIN=10) → GREEN (insufficient evidence)
  local D="$d/d.jsonl"; emit "$D" 5 rare-hook abstained no-telemetry
  out="$(run_alarm "$D")"; rc=$?
  [ "$rc" -eq 0 ]                              && okp "D sub-threshold blind → exit 0" || badp "D sub-threshold nonzero"
  ! printf '%s' "$out" | grep -q 'INERT'       && okp "D sub-threshold → not INERT" || badp "D sub-threshold wrongly INERT"

  # E. has a fire: 5 fired + 7 blind-abstained (abst!=total) → HEALTHY
  local E="$d/e.jsonl"; emit "$E" 5 firing-hook fired ok; emit "$E" 7 firing-hook abstained no-telemetry
  out="$(run_alarm "$E")"; rc=$?
  [ "$rc" -eq 0 ]                              && okp "E has-fired → exit 0" || badp "E has-fired nonzero"
  ! printf '%s' "$out" | grep -q 'INERT'       && okp "E has-fired → not INERT" || badp "E has-fired wrongly INERT"

  # F. outside the window: 12 blind but OLD ts → excluded → GREEN
  local F="$d/f.jsonl"; emit "$F" 12 stale-hook abstained no-telemetry "$OLDTS"
  out="$(run_alarm "$F")"; rc=$?
  [ "$rc" -eq 0 ]                              && okp "F outside-window → exit 0" || badp "F outside-window nonzero"
  ! printf '%s' "$out" | grep -q 'INERT'       && okp "F outside-window → excluded" || badp "F outside-window not excluded"

  # G. non-hook schema (supervisor/checkpoint lines) → ignored → GREEN
  local G="$d/g.jsonl"; local i
  for ((i = 0; i < 12; i++)); do
    printf '{"ts":"%s","actor":"lead-supervisor","kind":"checkpoint","sid":"s%d"}\n' "$FIXTS" "$i" >> "$G"
  done
  out="$(run_alarm "$G")"; rc=$?
  [ "$rc" -eq 0 ]                              && okp "G non-hook lines → exit 0" || badp "G non-hook nonzero"
  printf '%s' "$out" | grep -q 'hooks=0'       && okp "G non-hook lines → hooks=0 (ignored)" || badp "G non-hook lines counted"

  # H. a malformed line does not crash the sweep; valid inert hook still detected
  local H="$d/h.jsonl"; emit "$H" 12 inert2 abstained no-transcript-path; printf '{bad json not closed\n' >> "$H"
  out="$(run_alarm "$H")"; rc=$?
  [ "$rc" -ne 0 ]                              && okp "H malformed+inert → still RED (no crash)" || badp "H malformed swallowed the inert signal"
  printf '%s' "$out" | grep -q 'inert2'        && okp "H malformed → valid line still swept" || badp "H malformed dropped valid line"

  # I. missing IDL → GREEN
  out="$(run_alarm "$d/does-not-exist.jsonl")"; rc=$?
  [ "$rc" -eq 0 ]                              && okp "I missing IDL → exit 0" || badp "I missing IDL nonzero"
  printf '%s' "$out" | grep -q 'no IDL'        && okp "I missing IDL → green no-idl message" || badp "I missing IDL wrong message"

  # J. --report NEVER fails, even with an inert hook present
  out="$(run_alarm "$A" --report)"; rc=$?
  [ "$rc" -eq 0 ]                              && okp "J --report over inert → exit 0 (never pages)" || badp "J --report exited nonzero"
  printf '%s' "$out" | grep -q 'INERT'         && okp "J --report still SHOWS the inert hook" || badp "J --report hid the inert hook"

  # K. combined INERT + DORMANT in one file → RED, names ONLY the inert
  local K="$d/k.jsonl"; emit "$K" 12 real-inert abstained no-cwd; emit "$K" 12 fine-dormant abstained not-armed
  out="$(run_alarm "$K")"; rc=$?
  [ "$rc" -ne 0 ]                              && okp "K combined → RED" || badp "K combined not RED"
  printf '%s' "$out" | grep -qE '1 inert check\(s\): .*real-inert' && okp "K combined → names ONLY real-inert (1 inert)" || badp "K combined did not name exactly real-inert"

  # L. custom blind override: a normally-DORMANT reason becomes blind via env → INERT
  local L="$d/l.jsonl"; emit "$L" 12 custom-hook abstained widget-missing
  out="$(env CC_IDL="$L" CC_ABSTAIN_NOW="$NOW" CC_ABSTAIN_LOG="$d/log" CC_ABSTAIN_NMIN=10 \
            CC_ABSTAIN_BLIND_REASONS="widget-missing" "$SELF" --run)"; rc=$?
  [ "$rc" -ne 0 ]                              && okp "L blind-override → INERT on custom reason" || badp "L blind-override did not fire"

  # ── M/N: a NON-EVALUATION record must not enter the denominator ───────────────────────────────
  # Both problem verdicts require `abst == total`, and `total` used to count EVERY record carrying
  # {.hook,.disposition} — including housekeeping that never reached the guard (waiting-recycle's
  # `gc`/bats-pollution sweep). One such record breaks the equality and the hook falls through to
  # HEALTHY, the same verdict a firing hook gets. Measured live 2026-08-08: waiting-recycle at
  # total=2868 abst=2864 fired=0 read HEALTHY on the strength of 4 `gc` rows, while the recycle
  # actuator had fired ZERO times in 14 days. N is the dangerous direction — a genuinely INERT hook
  # laundered green — so it is pinned separately from the merely-mis-verdicted M.
  # memory: positive-control-the-denominator · new-enum-member-falls-into-fail-closed-default
  local M="$d/m.jsonl"; emit "$M" 12 gc-dormant abstained not-armed
  printf '{"ts":"%s","hook":"gc-dormant","sid":"g0","disposition":"gc","reason":"bats-pollution"}\n' "$FIXTS" >> "$M"
  out="$(run_alarm "$M")"; rc=$?
  [ "$rc" -eq 0 ]                              && okp "M gc record → exit 0" || badp "M gc record nonzero exit"
  printf '%s' "$out" | grep -q 'DORMANT-100'   && okp "M gc record does NOT launder dormant-100 → HEALTHY" || badp "M gc record laundered dormant-100 into HEALTHY"

  local N="$d/n.jsonl"; emit "$N" 12 gc-inert abstained no-telemetry
  printf '{"ts":"%s","hook":"gc-inert","sid":"g0","disposition":"gc","reason":"bats-pollution"}\n' "$FIXTS" >> "$N"
  out="$(run_alarm "$N")"; rc=$?
  [ "$rc" -ne 0 ]                              && okp "N gc record does NOT launder INERT → green" || badp "N one gc record laundered an INERT hook green"
  printf '%s' "$out" | grep -q 'gc-inert'      && okp "N gc record → inert hook still named" || badp "N inert hook not named"
  # ── the cc-backlog reap enrollment (backlog 420b9cb2166c) ──
  # Case G above already proves a NON-reap actor row stays invisible; these prove the reap
  # projection is real in both polarities, and that its productive verdicts break the 100%.

  # O. reap's UNRESOLVED keeps are BLIND → INERT under the hook name cc-backlog-reap
  local O="$d/reap-m.jsonl"; emit_reap "$O" 12 keep claimer-unresolved false
  out="$(run_alarm "$O")"; rc=$?
  [ "$rc" -ne 0 ]                                  && okp "O reap claimer-unresolved → nonzero exit" || badp "O reap blind keeps exited 0"
  printf '%s' "$out" | grep -q 'cc-backlog-reap'   && okp "O reap → projected under hook cc-backlog-reap" || badp "O reap row not projected"
  printf '%s' "$out" | grep -q 'INERT'             && okp "O reap blind-100 → INERT verdict" || badp "O reap no INERT verdict"

  # O2. the OTHER blind keep-reason, so the pair is proved per-token, not by one representative
  local O2="$d/reap-m2.jsonl"; emit_reap "$O2" 12 keep worktree-unresolved false
  out="$(run_alarm "$O2")"; rc=$?
  [ "$rc" -ne 0 ]                                  && okp "O2 reap worktree-unresolved → nonzero exit" || badp "O2 worktree-unresolved did not page"

  # P. reap's ANSWERED keeps are DORMANT → never a page (the polarity that must not invert)
  local P="$d/reap-n.jsonl"; emit_reap "$P" 12 keep owned-wait false
  out="$(run_alarm "$P")"; rc=$?
  [ "$rc" -eq 0 ]                                  && okp "P reap owned-wait → exit 0" || badp "P reap dormant keeps paged"
  printf '%s' "$out" | grep -q 'DORMANT-100'       && okp "P reap owned-wait → DORMANT-100" || badp "P reap dormant not reported"

  # P2. claimer-live is the other DORMANT token, and mixing it with 11 blind keeps must suppress:
  # one answered oracle proves reap CAN observe (the boundary-handoff false-positive guard, on reap).
  local P2="$d/reap-n2.jsonl"; emit_reap "$P2" 11 keep claimer-unresolved false; emit_reap "$P2" 1 keep claimer-live false
  out="$(run_alarm "$P2")"; rc=$?
  [ "$rc" -eq 0 ]                                  && okp "P2 reap 11 blind + 1 claimer-live → exit 0" || badp "P2 one dormant keep did not suppress"

  # Q. a BLOCK is the check acting → productive → breaks abstained==total even with 11 blind keeps.
  # This is the documented seam: a starvation that reaches its ceiling escalates to a human and is
  # therefore NOT also paged here.
  local Q="$d/reap-o.jsonl"; emit_reap "$Q" 11 keep claimer-unresolved false; emit_reap "$Q" 1 block unresolvable-claimer true
  out="$(run_alarm "$Q")"; rc=$?
  [ "$rc" -eq 0 ]                                  && okp "Q reap block(acted) → productive, not INERT" || badp "Q reap block still paged"

  # R. a REFUSED transition (acted:false) is `failed`, not an abstention — reap still reached its
  # guard, so it must not count toward the 100%-abstained condition either.
  local R="$d/reap-p.jsonl"; emit_reap "$R" 11 keep claimer-unresolved false; emit_reap "$R" 1 reopen dead-worker false
  out="$(run_alarm "$R")"; rc=$?
  [ "$rc" -eq 0 ]                                  && okp "R reap reopen(refused) → failed, not INERT" || badp "R refused transition counted as abstention"

  # S. --vocab-lint against the REAL bin/cc-backlog: the classification matches the live producer.
  out="$("$SELF" --vocab-lint 2>&1)"; rc=$?
  [ "$rc" -eq 0 ]                                  && okp "S vocab-lint vs real cc-backlog → GREEN" || badp "S vocab-lint RED against the real producer"

  # T. MUTANT: a new keep reason nothing classifies must RED — the fail-open this lint closes.
  local T="$d/cc-backlog-mutant"
  # shellcheck disable=SC2016  # a mutant of cc-backlog SOURCE — the $ are the subject, not expansions
  { printf 'idl_verdict "$id" keep brand-new-blindness false "$by"\n'
    printf 'idl_verdict "$id" keep claimer-live false "$by"\n'
    printf 'idl_verdict "$id" keep owned-wait false "$by"\n'
    printf 'idl_verdict "$id" keep claimer-unresolved false "$by"\n'
    printf 'idl_verdict "$id" keep worktree-unresolved false "$by"\n'; } > "$T"
  out="$("$SELF" --vocab-lint "$T" 2>&1)"; rc=$?
  [ "$rc" -ne 0 ]                                  && okp "T vocab-lint mutant (new reason) → RED" || badp "T unclassified keep reason passed"
  printf '%s' "$out" | grep -q 'brand-new-blindness' && okp "T vocab-lint names the unclassified token" || badp "T did not name the new token"

  # U. MUTANT, downward half: a classified token the producer no longer emits must RED too.
  local U="$d/cc-backlog-renamed"
  # shellcheck disable=SC2016  # ditto — cc-backlog source under mutation
  { printf 'idl_verdict "$id" keep claimer-live false "$by"\n'
    printf 'idl_verdict "$id" keep owned-wait false "$by"\n'
    printf 'idl_verdict "$id" keep claimer-unresolved false "$by"\n'; } > "$U"
  out="$("$SELF" --vocab-lint "$U" 2>&1)"; rc=$?
  [ "$rc" -ne 0 ]                                  && okp "U vocab-lint mutant (dropped reason) → RED" || badp "U stale classification passed"
  printf '%s' "$out" | grep -q 'worktree-unresolved' && okp "U vocab-lint names the stale token" || badp "U did not name the stale token"

  # V. the extractor's OWN blindness control: a source with no keep call sites must RED, never
  # report all-clear. Without this, an extractor that stops matching reads as a clean subject.
  : > "$d/cc-backlog-empty"
  out="$("$SELF" --vocab-lint "$d/cc-backlog-empty" 2>&1)"; rc=$?
  [ "$rc" -ne 0 ]                                  && okp "V vocab-lint on 0 call sites → RED (not vacuous)" || badp "V blind extractor reported all-clear"

  echo "idl-abstain-alarm --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "idl-abstain-alarm --selftest: GREEN — blind-100 pages, dormant-100 suppressed, mixed/sub-threshold/window/non-hook/malformed/override all correct; cc-backlog reap enrolled (blind keeps page, answered keeps do not, block/reopen break the 100%) with its keep-vocabulary lint RED-proved both ways."
}

case "${1:-}" in
  --selftest)   selftest ;;
  --report)     sweep report ;;
  --vocab-lint) vocab_lint "${2:-}" ;;
  ""|--run)     sweep run ;;
  *) printf 'idl-abstain-alarm: unknown arg %s (use --run | --report | --vocab-lint | --selftest)\n' "$1" >&2; exit 2 ;;
esac
