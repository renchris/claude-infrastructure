#!/usr/bin/env bash
# cloud-lane-liveness.sh — is the cloud FIRE lane alive right now, or is it stalled?
#
#   scripts/cloud-lane-liveness.sh              human-readable reading + verdict
#   scripts/cloud-lane-liveness.sh --json       one JSON object (what the lane tick journals)
#   scripts/cloud-lane-liveness.sh --assert     exit 1 on STALLED, 3 on UNKNOWN, 0 on LIVE
#   scripts/cloud-lane-liveness.sh --selftest   drive verdict() with no network and no repo at all
#
# ── WHY THIS EXISTS (DRAIN_CIRCUIT_2026-09-01 §4 W10 item (5)) ───────────────────────────────────
# W9 closed with a three-arm prediction — fire ~25/day, retire ~25/day, land ~1/day — and W10
# re-adjudicated it four days on: the land arm CONFIRMED (1.25/day), the fire arm REFUTED by 10x
# (2.50/day), the retire arm unreadable off-box. W10's own closing finding is the one this file
# answers: **the prediction had three arms and only one was made falsifiable, and the arm that was
# wrong is one of the two that were not.** The fire arm had no stated falsifier, no threshold and no
# instrument; it was refuted at all only because fire ref names happen to carry timestamps, and the
# remedy W10 could write from a cloud VM was a shell one-liner in a prose fence. Nothing executes a
# prose fence. This file is that one-liner made into an instrument with a declared criterion, so the
# next reader re-measures instead of quoting — the repo's stale-justification rule applied to the
# exact document that states it.
#
# ── THE GAP IS THE STATISTIC. THE RATE IS NOT, AND THAT IS MEASURED, NOT PREFERRED ───────────────
# The obvious reading is fires/day, and it is the wrong one twice over:
#
#   · IT AVERAGES THE STALL AWAY. W10's window (09-07…09-10) reads 2.50 fires/day, and that same
#     window CONTAINS a 35.78 h silence and a zero day. A mean cannot say "the lane went quiet",
#     which is the only fault this plan has ever cared about.
#   · IT ROTS IN A DAY. Re-measured 2026-09-12 over the same expression, one day later: 09-11
#     delivered 13 fires by itself, and 09-07…09-11 reads 4.60/day — the SAME statistic over the
#     SAME lane moved 84 % in 24 h. W9's ~25/day was a two-day burst carried forward as a property
#     of the pipeline; 2.50/day is a four-day lull carried forward the same way. Any ceiling derived
#     from an observed rate inherits that, which is precisely the error being corrected.
#
# So the rate is REPORTED (it is real context) and the VERDICT is the gap. The two are kept apart
# deliberately — W2's add-don't-redefine, and §1.5's defect in its fourth costume: this plan has
# now conflated commits-for-closure, pile-size-for-disposition, and trunk-volume-for-lane-liveness;
# rate-for-liveness is the same mistake one step further in.
#
# ── THE OPEN GAP IS THE ONE THAT MATTERS, AND NOTHING WAS SAMPLING IT ────────────────────────────
# A stall IN PROGRESS has no closing endpoint, so a max-gap-between-fires is structurally blind to
# the live failure — it can only ever describe stalls that already ended. `now - last_fire` is
# therefore a gap candidate and it is the VERDICT arm; closed gaps in the window are reported beside
# it as history (`stalls`, `max_closed_gap_h`), never as a fault, or a 58.76 h silence that ended
# five days ago would hold the gate red forever.
#
# This is also why the instrument has to RIDE something. W10 could refute the fire arm after the
# fact because ref names are timestamped, i.e. the lane's history is legible whenever you look. But
# a stall is only ACTIONABLE while it is happening, and between dispatches nothing samples the lane
# at all. On 2026-09-08 the cloud lane fired zero times while trunk took 130 commits and no surface
# said so for three days. The carrier is `scripts/cloud-return-lane.sh`, which already ticks, already
# pays for the network, and — the property that matters — does NOT share a failure mode with the
# fire lane it observes: the return lane is spawned by the sweep, the fire lane by the dispatcher,
# so the observer stays up exactly when the subject goes down. §1.6's constraint holds: no new
# launchd job.
#
# ── THE READER CAN BE ITS OWN SUBJECT ────────────────────────────────────────────────────────────
# 🚨 Run from a cloud VM, this script's own boot-ping branch IS the newest fire ref, so `now - last`
# is ~0 by construction and the live arm CANNOT trip — a census matching itself, the repo's own
# `argv-census-must-not-carry-its-pattern-in-argv` shape in a different medium. Worse than useless:
# it means firing a session TO DIAGNOSE a stalled lane is the act that makes the lane read healthy.
# So the ref naming the current branch is excluded, and the exclusion is NAMED in the output. It is
# self-limiting — on the desk HEAD is never a fire ref, so nothing is dropped.
#
# ── "CANNOT LOOK" IS NEVER "NOTHING FOUND" ───────────────────────────────────────────────────────
# A failed `ls-remote` exits non-zero with zero rows, which is byte-identical to a remote holding no
# fires — and read as a verdict it would report the healthiest possible lane as the most stalled one
# (cloud-reconcile.sh:51 states the same law for the same reason). Sensor failure is UNKNOWN, rc 3,
# and every numeric field is null. A zeroed reading would be a claim this script has no evidence for.
#
# ── THE POPULATION CONTROL, WHICH CAN GO RED ─────────────────────────────────────────────────────
# The whole method rests on "nothing in this pipeline deletes a branch" (cloud-return.sh:529,
# cloud-retire-terminal.sh:55) — only that makes an ABSENT date a real absence rather than a
# collection artifact. It is pinned rather than trusted: refs dated on or before CC_LANE_BASELINE_DATE
# must number at least CC_LANE_BASELINE_N. Measured 425 by W9 (09-07), 426 by W10 (09-11) and 426
# again here (09-12) — monotone, as a never-deleting population must be. If it ever reads LOWER, a
# branch was deleted, an absent date stops being evidence, and this script must say UNKNOWN rather
# than report the shrunken census as a low fire rate.
#
# ── THE CEILING COMES FROM THE PLAN'S NAME, NOT FROM A BURST ─────────────────────────────────────
# 24 h, because the plan is "the 24/7 pipeline is an open loop" and a lane that is 24/7 and has not
# fired in a day has stalled by its own definition. Deriving it from an observed rate instead is the
# exact mistake W9 made and W10 refuted, so it is NOT derived from one. Polarity is measured rather
# than hoped: against the real ref series it trips on W9's 58.76 h deadlock and on W10's 31.14 h and
# 35.78 h gaps, and stays silent across every interval since 2026-09-10T12:31Z (max 6.33 h).
#
# Env seams: CC_LANE_REMOTE (origin) · CC_LANE_REPO · CC_LANE_FIRE_CEILING_H (24) ·
#   CC_LANE_WINDOW_DAYS (7) · CC_LANE_BASELINE_N (426) · CC_LANE_BASELINE_DATE (20260907) ·
#   CC_LANE_NOW (epoch override, tests) · CC_LANE_REFS_CMD (stub the ref read) ·
#   CC_LANE_SELF_BRANCH (override the self-exclusion)
# Exits: 0 LIVE · 1 STALLED (--assert only) · 2 usage · 3 UNKNOWN (sensor/control failed)
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"

REMOTE="${CC_LANE_REMOTE:-origin}"
REPO="${CC_LANE_REPO:-}"
CEILING_H="${CC_LANE_FIRE_CEILING_H:-24}"
WINDOW_D="${CC_LANE_WINDOW_DAYS:-7}"
BASE_N="${CC_LANE_BASELINE_N:-426}"
BASE_DATE="${CC_LANE_BASELINE_DATE:-20260907}"

MODE="report"
case "${1:-}" in
  ''|--report) MODE="report" ;;
  --json)      MODE="json" ;;
  --assert)    MODE="assert" ;;
  --selftest)  MODE="selftest" ;;
  -h|--help)   sed -n '2,9p' "$0"; exit 0 ;;
  *) printf 'cloud-lane-liveness: unknown argument %s\n' "${1:-}" >&2; exit 2 ;;
esac

# ── the verdict function, factored out so --selftest can drive every state with no box ───────────
# $1 sensor_ok (1 ok, 0 could not look)   $2 observed baseline count   $3 wanted baseline count
# $4 malformed `claude/*` ref count       $5 open gap seconds ("" = no fire ref at all)
# $6 ceiling seconds
# Echoes "<TOKEN>\t<one line>". TOKEN ∈ LIVE | STALLED | UNKNOWN.
#
# ORDER IS THE CONTRACT. Every UNKNOWN arm outranks the gap compare, because each one says the
# census could not be trusted — and a census that could not be trusted reports a QUIET lane, never
# a busy one, so letting any of them fall through to the compare would mint STALLED out of an
# instrument failure. That direction is not symmetric and it is the reason for the ordering.
verdict() {
  local sok="$1" obs="$2" want="$3" bad="$4" gap="$5" ceil="$6"
  if [ "$sok" != "1" ]; then
    printf 'UNKNOWN\tthe ref read failed — this is "cannot look", not "no fires"; nothing is claimed\n'; return
  fi
  if [ "$bad" -gt 0 ]; then
    printf 'UNKNOWN\t%d claude/* ref(s) are not well-formed fire refs — the lane may have been renamed, so an absent date is not evidence\n' "$bad"; return
  fi
  if [ "$obs" -lt "$want" ]; then
    printf 'UNKNOWN\trefs dated <=%s read %d against a pinned floor of %d — a branch was DELETED, so an absent date is a collection artifact and the census is void\n' "$BASE_DATE" "$obs" "$want"; return
  fi
  if [ -z "$gap" ]; then
    printf 'UNKNOWN\tno fire ref survives the self-exclusion — there is nothing to measure a gap from\n'; return
  fi
  if [ "$gap" -gt "$ceil" ]; then
    printf 'STALLED\tthe cloud fire lane has been silent for %s h against a ceiling of %s h — it is not firing NOW\n' "$(hours "$gap")" "$(hours "$ceil")"; return
  fi
  printf 'LIVE\tlast fire %s h ago, inside the %s h ceiling\n' "$(hours "$gap")" "$(hours "$ceil")"
}

# seconds -> hours, 2dp, with no bc and no locale exposure
hours() { awk -v s="$1" 'BEGIN{ printf "%.2f", s/3600 }'; }

# ── YYYYMMDDHHMMSS (14 digits, UTC) -> epoch, in awk ─────────────────────────────────────────────
# Deliberately NOT `date`: `date -d` is GNU-only and `date -j -f` is BSD-only, and this file must run
# both on the operator's macOS box and on a Linux cloud VM. Howard Hinnant's days-from-civil needs
# neither, and it is a pure function a test can pin.
ts_epoch() {
  awk -v t="$1" 'BEGIN{
    y = substr(t,1,4)+0; m = substr(t,5,2)+0; d = substr(t,7,2)+0;
    H = substr(t,9,2)+0; M = substr(t,11,2)+0; S = substr(t,13,2)+0;
    yy = y - (m <= 2 ? 1 : 0);
    era = int((yy >= 0 ? yy : yy-399) / 400);
    yoe = yy - era*400;
    doy = int((153*(m + (m > 2 ? -3 : 9)) + 2)/5) + d - 1;
    doe = yoe*365 + int(yoe/4) - int(yoe/100) + doy;
    days = era*146097 + doe - 719468;
    printf "%d", days*86400 + H*3600 + M*60 + S;
  }'
}

# ── the ref read ─────────────────────────────────────────────────────────────────────────────────
# One `ls-remote`, no fetch, no lock, no ref written — safe against a live remote mid-sweep, which
# is the only time some of these answers are interesting. CC_LANE_REFS_CMD replaces it wholesale so
# the suite can drive BOTH the happy path and the rc!=0-with-empty-stdout path that the law above
# is about; stubbing git itself would only test the stub.
read_refs() {
  if [ -n "${CC_LANE_REFS_CMD:-}" ]; then
    eval "$CC_LANE_REFS_CMD"
    return $?
  fi
  if [ -n "$REPO" ]; then git -C "$REPO" ls-remote --heads "$REMOTE" 'refs/heads/claude/**'
  else git ls-remote --heads "$REMOTE" 'refs/heads/claude/**'; fi
}

self_branch() {
  if [ -n "${CC_LANE_SELF_BRANCH+x}" ]; then printf '%s' "$CC_LANE_SELF_BRANCH"; return 0; fi
  if [ -n "$REPO" ]; then git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null
  else git rev-parse --abbrev-ref HEAD 2>/dev/null; fi
}

# ── selftest: every verdict state, driven with no network, no repo and no clock ──────────────────
if [ "$MODE" = "selftest" ]; then
  fail=0
  chk() { # $1 want-token  $2..  verdict args
    local want="$1"; shift
    local got; got="$(verdict "$@" | cut -f1)"
    if [ "$got" = "$want" ]; then printf '  ok   %-8s <- %s\n' "$got" "$*"
    else printf '  FAIL want=%-8s got=%-8s <- %s\n' "$want" "$got" "$*"; fail=1; fi
  }
  printf 'cloud-lane-liveness --selftest\n'
  chk UNKNOWN 0 426 426 0 3600 86400            # sensor could not look
  chk UNKNOWN 1 426 426 2 3600 86400            # lane renamed / malformed refs
  chk UNKNOWN 1 425 426 0 3600 86400            # population SHRANK -> a branch was deleted
  chk UNKNOWN 1 426 426 0 '' 86400              # nothing left to measure from
  chk STALLED 1 426 426 0 211536 86400          # W9's 58.76 h deadlock
  chk STALLED 1 426 426 0 112104 86400          # W10's 31.14 h gap
  chk STALLED 1 426 426 0 128808 86400          # W10's 35.78 h gap
  chk LIVE    1 426 426 0 22788  86400          # the 6.33 h gap of 09-10, the widest since
  chk LIVE    1 426 426 0 86400  86400          # exactly at the ceiling is NOT a stall
  chk STALLED 1 426 426 0 86401  86400          # one second over is
  chk LIVE    1 427 426 0 3600   86400          # a GROWING population is the healthy direction
  [ "$fail" = 0 ] && { printf 'selftest: all states discriminate\n'; exit 0; }
  printf 'selftest: FAILED\n'; exit 1
fi

# ── gather ───────────────────────────────────────────────────────────────────────────────────────
NOW="${CC_LANE_NOW:-$(date -u +%s)}"
raw="$(read_refs 2>/dev/null)"; sensor_rc=$?
sensor_ok=1; [ "$sensor_rc" -eq 0 ] || sensor_ok=0

# Names only. `ls-remote` emits "<sha>\t<ref>"; a stub may emit bare names. Both reduce here.
names="$(printf '%s\n' "$raw" | sed -E 's#^[0-9a-f]+[[:space:]]+##; s#^refs/heads/##' | grep -E '^claude/' || true)"
[ -n "$names" ] || names=""

self="$(self_branch)"; self="${self#refs/heads/}"

# The two censuses: well-formed fire stamps, and anything under claude/ that is NOT one.
stamps="$(printf '%s\n' "$names" | grep -E '^claude/fire-[0-9]{8}T[0-9]{6}Z' || true)"
malformed=$(printf '%s\n' "$names" | grep -cvE '^claude/fire-[0-9]{8}T[0-9]{6}Z' 2>/dev/null || true)
malformed="$(printf '%s' "${malformed:-0}" | tr -d ' ')"
case "$malformed" in ''|*[!0-9]*) malformed=0 ;; esac   # `wc`/`grep -c` pad on BSD; a digit guard
[ -n "$names" ] || malformed=0                          # no rows at all is a sensor story, not a rename

# SELF-EXCLUSION. Drop the ref naming the branch we are standing on, and only that one.
#
# `grep -xF … >/dev/null` and NOT `grep -qxF`: under `pipefail` an early-exiting consumer SIGPIPEs
# its producer, and the pipeline then reports the PRODUCER's death — so the condition reads FALSE on
# a MATCH, which here would silently restore the exact bug the self-exclusion exists to prevent. It
# is latent rather than absent today only because `$stamps` (444 refs, 15,983 B) still fits the 64 KB
# pipe buffer, so `printf` completes before `grep -q` can kill it. Measured by bisection on this box,
# matching the FIRST line so the consumer exits as early as it can: rc 0 up to 1,811 refs, rc 141
# (128+SIGPIPE) from **1,812 refs / 65,231 B** — while the drained form returns rc 0 at every size
# tried, to 4,000. So it inverts at ~4x the current pile, i.e. precisely as the ref population this
# script exists to watch grows, which is the worst possible schedule for it. Draining costs one full
# read of a list already in memory.
excluded=""
if [ -n "$self" ] && printf '%s\n' "$stamps" | grep -xF "$self" >/dev/null; then
  excluded="$self"
  stamps="$(printf '%s\n' "$stamps" | grep -vxF "$self" || true)"
fi

dates="$(printf '%s\n' "$stamps" | sed -E 's#^claude/fire-([0-9]{8})T([0-9]{6})Z.*#\1\2#' | grep -E '^[0-9]{14}$' | sort || true)"
n_refs=0; [ -n "$dates" ] && n_refs=$(printf '%s\n' "$dates" | wc -l | tr -d ' ')

baseline_obs=0
[ -n "$dates" ] && baseline_obs=$(printf '%s\n' "$dates" | awk -v d="$BASE_DATE" 'substr($0,1,8)<=d' | wc -l | tr -d ' ')

# ── the arms ─────────────────────────────────────────────────────────────────────────────────────
CEIL_S=$(( CEILING_H * 3600 ))
WIN_S=$(( WINDOW_D * 86400 ))
last_ts=""; open_gap=""
if [ -n "$dates" ]; then
  last_ts="$(printf '%s\n' "$dates" | tail -1)"
  last_ep="$(ts_epoch "$last_ts")"
  open_gap=$(( NOW - last_ep ))
  [ "$open_gap" -lt 0 ] && open_gap=0   # a clock skew must not read as a fire from the future
fi

# History arm: fires inside the window, the rate they imply, and every CLOSED gap over the ceiling.
# The gap's CLOSING fire decides membership, so a silence that began before the window and ended
# inside it still counts — which is the only way the 58.76 h deadlock is visible on the day it broke.
hist="$(printf '%s\n' "$dates" | awk -v now="$NOW" -v win="$WIN_S" -v ceil="$CEIL_S" '
  function ep(t,   y,m,d,H,M,S,yy,era,yoe,doy,doe,days) {
    y=substr(t,1,4)+0; m=substr(t,5,2)+0; d=substr(t,7,2)+0;
    H=substr(t,9,2)+0; M=substr(t,11,2)+0; S=substr(t,13,2)+0;
    yy = y - (m <= 2 ? 1 : 0);
    era = int((yy >= 0 ? yy : yy-399) / 400);
    yoe = yy - era*400;
    doy = int((153*(m + (m > 2 ? -3 : 9)) + 2)/5) + d - 1;
    doe = yoe*365 + int(yoe/4) - int(yoe/100) + doy;
    days = era*146097 + doe - 719468;
    return days*86400 + H*3600 + M*60 + S;
  }
  NF {
    e = ep($0);
    if (e >= now - win) n++;
    if (p != "" && e >= now - win) { g = e - p; if (g > mx) mx = g; if (g > ceil) st++; }
    p = e;
  }
  END { printf "%d %d %d", n+0, mx+0, st+0 }' 2>/dev/null)"
win_n="$(printf '%s' "$hist" | awk '{print $1+0}')"
max_closed="$(printf '%s' "$hist" | awk '{print $2+0}')"
stalls="$(printf '%s' "$hist" | awk '{print $3+0}')"
rate="$(awk -v n="${win_n:-0}" -v d="$WINDOW_D" 'BEGIN{ printf "%.2f", (d>0? n/d : 0) }')"

V="$(verdict "$sensor_ok" "$baseline_obs" "$BASE_N" "$malformed" "$open_gap" "$CEIL_S")"
TOKEN="$(printf '%s' "$V" | cut -f1)"
WHY="$(printf '%s' "$V" | cut -f2-)"

iso() { # YYYYMMDDHHMMSS -> ISO-8601 Z, for humans and for the journal
  [ -n "$1" ] || { printf ''; return; }
  printf '%s-%s-%sT%s:%s:%sZ' "${1:0:4}" "${1:4:2}" "${1:6:2}" "${1:8:2}" "${1:10:2}" "${1:12:2}"
}

# ── render ───────────────────────────────────────────────────────────────────────────────────────
# UNKNOWN nulls every number. A reading taken through a sensor that could not run is not a smaller
# reading, it is no reading, and a consumer summing these rows must not be handed a zero to add.
if [ "$MODE" = "json" ]; then
  if [ "$TOKEN" = "UNKNOWN" ]; then
    printf '{"verdict":"UNKNOWN","why":%s,"open_gap_h":null,"ceiling_h":%s,"last_fire":null,"self_excluded":%s,"window_days":%s,"fires_in_window":null,"rate_per_day":null,"stalls_in_window":null,"max_closed_gap_h":null,"refs_seen":null,"baseline_obs":null,"baseline_want":%s}\n' \
      "$(printf '%s' "$WHY" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/')" \
      "$CEILING_H" \
      "$( [ -n "$excluded" ] && printf '"%s"' "$excluded" || printf 'null' )" \
      "$WINDOW_D" "$BASE_N"
  else
    printf '{"verdict":"%s","why":%s,"open_gap_h":%s,"ceiling_h":%s,"last_fire":"%s","self_excluded":%s,"window_days":%s,"fires_in_window":%s,"rate_per_day":%s,"stalls_in_window":%s,"max_closed_gap_h":%s,"refs_seen":%s,"baseline_obs":%s,"baseline_want":%s}\n' \
      "$TOKEN" \
      "$(printf '%s' "$WHY" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/')" \
      "$(hours "$open_gap")" "$CEILING_H" "$(iso "$last_ts")" \
      "$( [ -n "$excluded" ] && printf '"%s"' "$excluded" || printf 'null' )" \
      "$WINDOW_D" "${win_n:-0}" "$rate" "${stalls:-0}" "$(hours "${max_closed:-0}")" \
      "${n_refs:-0}" "${baseline_obs:-0}" "$BASE_N"
  fi
else
  printf 'cloud-lane-liveness — the cloud FIRE lane, read from %s\n' "$REMOTE"
  if [ "$TOKEN" = "UNKNOWN" ]; then
    printf '  sensor        %s\n' "$( [ "$sensor_ok" = 1 ] && printf 'answered' || printf 'FAILED (rc %s)' "$sensor_rc" )"
  else
    printf '  last fire     %s  (%s h ago)\n' "$(iso "$last_ts")" "$(hours "$open_gap")"
    printf '  ceiling       %s h  — from the plan name (24/7), not from an observed rate\n' "$CEILING_H"
    printf '  window        %s d  · %s fire(s) · %s/day  ← CONTEXT, never the verdict\n' "$WINDOW_D" "${win_n:-0}" "$rate"
    printf '  history       %s stall(s) over the ceiling in-window · widest closed gap %s h\n' "${stalls:-0}" "$(hours "${max_closed:-0}")"
    printf '  population    %s fire refs · %s dated <=%s against a pinned floor of %s\n' "${n_refs:-0}" "${baseline_obs:-0}" "$BASE_DATE" "$BASE_N"
  fi
  [ -n "$excluded" ] && printf '  self-excluded %s  (this reader IS a fire; without this the live arm cannot trip)\n' "$excluded"
  printf '  VERDICT       %s — %s\n' "$TOKEN" "$WHY"
fi

case "$TOKEN" in
  UNKNOWN) exit 3 ;;
  STALLED) [ "$MODE" = "assert" ] && exit 1; exit 0 ;;
  *)       exit 0 ;;
esac
