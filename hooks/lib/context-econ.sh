#!/usr/bin/env bash
# context-econ.sh — shared context-economics SIGNALS for the recycle/boundary hooks (2026-07-20).
#
# WHY (operator goal): "know intelligently, not hardcoded, when to recycle" needs three signals no
# single threshold carries — VELOCITY (burn rate → forecast minutes to the auto-compact wall),
# VALUE (is a live 2-way exchange in flight? a conversation leaves NO git/mailbox trace, so the
# S1–S5 holds misclassify it as idle — the "74% mid-conversation" incident), and the existing FILL.
# This lib computes the first two; the consuming hooks (waiting-recycle.sh, boundary-handoff.sh)
# compose them onto their tier policies. Design + ground-truth corpus:
# docs/research/context-econ-2026-07-20.md.
#
# CONTRACT: pure readers except ce_sample (appends one line to the per-SID history file). Sourced
# by hooks — set -u safe, NO set -e, every seam guarded; a signal failure must degrade to the
# pre-upgrade behavior ("0 -1" / empty), never cost the hook. All output on stdout, exit 0 always.
#
# Env seams (tests): CC_CE_WIN_S · CC_CE_WALL · CC_CE_MIN_SPAN_S · CC_CE_HIST_MAX ·
#                    CC_CE_TAIL_BYTES · CC_CE_AUTO_RX · CC_CE_PS · CC_CE_RSS_COMM_RX
#
# ── THE SIZE AXIS (2026-07-29, K02 — audit raw/a12.md K02 + raw/a3.md S1) ──────────────────────
# FILL and VELOCITY above both key on used_pct, which is the CONTEXT WINDOW's occupancy. Compaction
# resets it; the session's cumulative on-disk transcript and its process footprint do NOT reset. So
# a session can be size-dangerous at LOW fill and every trigger in this lib reads it as healthy —
# the K02 blind spot ("auto-recycle is SIZE-BLIND"). ce_size adds the missing axis.
#
# MEASURED, 2026-07-29 (n=29 live sessions with a resolvable pid; 67 telemetry files) — the numbers
# that decided the design, re-derive before changing a threshold:
#   • pearson(transcript_MB, RSS_MB) = +0.26. tx spans 0–22.4 MB while RSS spans 431–1000 MB.
#     ⇒ bytes and RSS are INDEPENDENT axes. Neither is a proxy for the other; a size trigger that
#       reads only one of them is blind to most of the population.
#   • pearson(used_pct, transcript_MB) = +0.65 — correlated but NOT redundant: the largest live
#     transcript (22.4 MB) sat at 61% fill, i.e. BELOW boundary-handoff's T=73. ⇒ additive.
#   • |input_tokens/window*100 − used_pct| ≤ 0.50 pt (mean 0.25) across all 67 files.
#     ⇒ THE `input_tokens` COLUMN IS NOT A SIZE PROXY. It is an algebraic restatement of used_pct
#       and it resets on compaction — the very axis K02 says is blind. The audit's roadmap line
#       called col-3 "a ready size proxy"; its own raw finding (a3 S1) had already refuted that
#       ("both unused *and* the wrong axis"). ce_sample keeps writing col-3 (it is an honest record
#       of window tokens) but NOTHING may build a size trigger on it. This note is the refutation's
#       load-bearing home: the next reader reaches for col-3 first.
#
# WHY THE TWO AXES GET DIFFERENT POWERS AT THE CONSUMERS (policy lives in the hooks, stated here so
# the split is not re-litigated from scratch):
#   • transcript BYTES may drive an auto-recycle. It is monotonic, it is the leak class itself
#     (invariant I5), and a recycle is the ONLY thing that resets it — a fresh SID opens a fresh
#     JSONL at 0 bytes, where /compact does not shrink the file at all.
#   • RSS may only PAGE inside an auto-exec path. It is the metric that actually kills (a
#     per-process ceiling), but every live session already sits ≥431 MB with the observed max at
#     1000 MB — barely 2× headroom — and the dangerous level is UNKNOWN (the 07-22 crash diagnosis
#     records the per-process death mechanism as UNPROVEN, and the crash class was later superseded
#     by a CC-version regression). Auto-recycling the fleet on a guessed RSS number is a hazard with
#     no evidence behind it. Consumers log the measured value on EVERY eval instead, so the
#     threshold can be calibrated from real data rather than promoted on a guess.

# ce_sample <tel_json> — append "ts used_pct input_tokens" to <tel_json%.json>.hist iff the
# telemetry ts is strictly newer than the last recorded sample (idempotent across hooks polling the
# same file). A fill DROP > 2 points means the window was compacted/replaced — the prior slope is
# poisoned, so the series restarts at the new sample. Bounded: prune to HIST_MAX/2 lines when the
# file exceeds CC_CE_HIST_MAX (default 120).
ce_sample() {
  local tel="${1:-}" hist ts used tok last last_ts last_used max lines
  { [ -n "$tel" ] && [ -f "$tel" ]; } || return 0
  command -v jq >/dev/null 2>&1 || return 0
  hist="${tel%.json}.hist"
  # every substitution carries a fallback: the lib must survive errexit callers too (contract above)
  ts="$(jq -r '.ts // 0' "$tel" 2>/dev/null || echo '')"; ts="${ts%.*}"
  case "$ts" in ''|*[!0-9]*) return 0 ;; esac
  [ "$ts" -gt 0 ] || return 0
  used="$(jq -r '.used_pct // empty' "$tel" 2>/dev/null || echo '')"; used="${used%.*}"
  case "$used" in ''|*[!0-9]*) return 0 ;; esac
  tok="$(jq -r '.input_tokens // 0' "$tel" 2>/dev/null || echo 0)"; tok="${tok%.*}"
  case "$tok" in ''|*[!0-9]*) tok=0 ;; esac
  last="$(tail -1 "$hist" 2>/dev/null || true)"
  last_ts="${last%% *}"; case "$last_ts" in ''|*[!0-9]*) last_ts=0 ;; esac
  [ "$ts" -gt "$last_ts" ] || return 0
  if [ "$last_ts" -gt 0 ]; then
    last_used="$(printf '%s' "$last" | awk '{print $2}' 2>/dev/null)"
    case "$last_used" in ''|*[!0-9]*) last_used=0 ;; esac
    if [ "$used" -lt $(( last_used - 2 )) ]; then
      printf '%s %s %s\n' "$ts" "$used" "$tok" > "$hist" 2>/dev/null || true
      return 0
    fi
  fi
  printf '%s %s %s\n' "$ts" "$used" "$tok" >> "$hist" 2>/dev/null || true
  max="${CC_CE_HIST_MAX:-120}"
  lines="$(wc -l < "$hist" 2>/dev/null | tr -d ' ')"; case "$lines" in ''|*[!0-9]*) lines=0 ;; esac
  if [ "$lines" -gt "$max" ]; then
    if tail -n $(( max / 2 )) "$hist" > "$hist.tmp.$$" 2>/dev/null; then
      mv -f "$hist.tmp.$$" "$hist" 2>/dev/null || rm -f "$hist.tmp.$$" 2>/dev/null
    else
      rm -f "$hist.tmp.$$" 2>/dev/null
    fi
  fi
  return 0
}

# ce_burn <tel_json> — echo "burn_x100 forecast_min".
#   burn_x100:   fill velocity, pct-points/min ×100 (integer), slope oldest-in-window → newest.
#   forecast_min: minutes until CC_CE_WALL (default 88) at that velocity, from the newest sample;
#                 0 = at/past the wall already; -1 = unknown (sparse/flat/declining — the honest
#                 answer; consumers MUST treat -1 as "no forecast", i.e. legacy behavior).
# Trust gate: ≥2 samples spanning ≥ CC_CE_MIN_SPAN_S (120s) inside CC_CE_WIN_S (900s).
ce_burn() {
  local tel="${1:-}" hist win minspan wall now cut first_ts first_used last_ts last_used span d burn remaining fc
  win="${CC_CE_WIN_S:-900}"; minspan="${CC_CE_MIN_SPAN_S:-120}"; wall="${CC_CE_WALL:-88}"
  hist="${tel%.json}.hist"
  { [ -n "$tel" ] && [ -s "$hist" ]; } || { printf '0 -1'; return 0; }
  now="$(date +%s)"; cut=$(( now - win ))
  # one pass: oldest sample not older than the window start, plus the newest sample
  read -r first_ts first_used last_ts last_used <<EOF
$(awk -v cut="$cut" '
      ($1+0) >= cut { if (!seen) { ft=$1; fu=$2; seen=1 } lt=$1; lu=$2 }
      END { if (!seen) print 0,0,0,0; else print ft+0, fu+0, lt+0, lu+0 }' "$hist" 2>/dev/null)
EOF
  first_ts="${first_ts:-0}"; first_used="${first_used:-0}"; last_ts="${last_ts:-0}"; last_used="${last_used:-0}"
  [ "$first_ts" -gt 0 ] 2>/dev/null || { printf '0 -1'; return 0; }
  span=$(( last_ts - first_ts ))
  [ "$span" -ge "$minspan" ] || { printf '0 -1'; return 0; }
  d=$(( last_used - first_used ))
  [ "$d" -gt 0 ] || { printf '0 -1'; return 0; }
  burn=$(( d * 6000 / span ))
  [ "$burn" -gt 0 ] || { printf '0 -1'; return 0; }
  remaining=$(( wall - last_used ))
  if [ "$remaining" -le 0 ]; then fc=0; else fc=$(( remaining * 100 / burn )); fi
  printf '%s %s' "$burn" "$fc"
  return 0
}

# ce_transcript_visible <path> <tail_bytes> — 0 iff at least ONE well-formed JSON object is visible
# in the same reach the scan below uses (the tail; then the whole file when the file is bigger than
# the tail window). This is the DISCRIMINATOR behind the three-valued answer of
# ce_last_interactive_age: a transcript we CAN parse but that holds no operator turn is a FACT
# ("nobody typed"); a transcript we cannot parse at all is an ABSENCE OF EVIDENCE — and a reap
# consumer must never read the second as the first.
ce_transcript_visible() {
  local p="${1:-}" tb="${2:-2000000}" hit fsz
  hit="$(tail -c "$tb" "$p" 2>/dev/null | jq -Rr 'fromjson? | objects | "1"' 2>/dev/null | head -1)"
  [ -n "$hit" ] && return 0
  fsz="$(wc -c < "$p" 2>/dev/null | tr -d ' ')"; case "$fsz" in ''|*[!0-9]*) fsz=0 ;; esac
  if [ "$fsz" -gt "$tb" ]; then
    hit="$(jq -Rr 'fromjson? | objects | "1"' "$p" 2>/dev/null | head -1)"
    [ -n "$hit" ] && return 0
  fi
  return 1
}

# ce_last_interactive_age <transcript_path> — echo the age in seconds of the last INTERACTIVE turn.
# THREE-VALUED (2026-07-25 — the empty-answer split). The old contract answered "" for three
# different worlds — no operator turn, jq missing, unreadable/corrupt transcript — and both reap
# consumers (bin/cc-reaper's Gap-2 coordination-abandoned leg, scripts/reap-guard.sh R-d) read that
# one "" as "no adoption" and fell through to REAP. Absence of evidence became evidence of absence
# on the two legs that back up cc-classify §4.7, whose own rule is stricter ("no readable transcript
# → active"). So:
#   "<digits>"    the age in seconds of the last interactive turn (0 when the clock reads backwards)
#   ""      rc 0  GENUINELY NO OPERATOR TURN — the transcript parsed, nobody typed. A fact.
#   "unreadable"  rc 2  we could not READ the answer: no path / not a regular file / unreadable /
#                 no jq / not one well-formed JSON object anywhere in reach. Consumers that gate a
#                 DESTRUCTIVE act (reap, close, archive) MUST treat this as DEFER — never as "no
#                 adoption". Advisory consumers (waiting-recycle S6, boundary-handoff wording) already
#                 sanitize any non-numeric answer to "" and are unaffected by the split.
# The scan itself stays bounded to the tail (CC_CE_TAIL_BYTES, default 2MB — recency needs the tail
# only; an interactive turn older than the tail is old enough not to hold).
#
# INTERACTIVE (ground-truthed against production transcripts, 2026-07-20):
#   type=="user" AND isMeta != true AND content is a string (or text blocks with NO tool_result)
#   AND the text does not match the auto-traffic regex. Auto-drive re-prompts (session-continue 🔧
#   loops, /goal Stop hooks) arrive as isMeta:true AND "Stop hook feedback:"-prefixed — excluded on
#   two independent axes, so an auto-driven desk still reads as NON-interactive (load-bearing: a
#   conversation-hold that counted its own auto-drive would deadlock every free-win recycle).
#   Operator slash-commands (<command-name>) COUNT (the operator is present); their paired
#   <local-command-stdout> echo, task-notifications, interrupt markers, and our own ⟳/⚑/⚠ hook
#   advisories do not.
ce_last_interactive_age() {
  local tp="${1:-}" tailb rx ep now
  tailb="${CC_CE_TAIL_BYTES:-2000000}"
  # NOT "no operator turn" — we cannot read the file at all. Fail-closed answer, rc 2.
  { [ -n "$tp" ] && [ -f "$tp" ] && [ -r "$tp" ]; } || { printf 'unreadable'; return 2; }
  command -v jq >/dev/null 2>&1 || { printf 'unreadable'; return 2; }
  rx="${CC_CE_AUTO_RX:-^<task-notification>|^<local-command-stdout>|^Stop hook feedback:|^\\[Request interrupted|^⟳|^⚑|^⚠}"
  # fromjson? drops the (possibly partial) first tailed line; `objects`/`strings` guard scalar lines
  # so one odd line can never abort the scan (jq runtime errors are per-program, not per-line).
  ep="$(tail -c "$tailb" "$tp" 2>/dev/null | jq -Rr --arg rx "$rx" '
      fromjson? | objects
      | select(.type=="user") | select(.isMeta != true)
      | (.message.content) as $c
      | ( if ($c|type)=="string" then $c
          elif ($c|type)=="array" and ([$c[]? | select(.type?=="tool_result")] | length)==0
          then ([$c[]? | select(.type?=="text") | .text] | join("\n"))
          else empty end ) as $t
      | select(($t|length) > 0)
      | select($t | test($rx) | not)
      | (.timestamp | strings | sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch empty)
    ' 2>/dev/null | tail -1)"
  case "$ep" in
    ''|*[!0-9]*)
      # No interactive turn in the answer — but WHICH world? A parseable transcript with no operator
      # turn is the fact ""; a transcript that yields not one well-formed record (corrupt, truncated,
      # binary, empty) is "unreadable". Splitting them here is the whole point of the three-valued
      # contract: only the first may ever license a reap.
      if ce_transcript_visible "$tp" "$tailb"; then printf ''; return 0; fi
      printf 'unreadable'; return 2
      ;;
  esac
  now="$(date +%s)"
  if [ "$now" -ge "$ep" ]; then printf '%s' $(( now - ep )); else printf '0'; fi
  return 0
}

# ce_size <transcript_path> <tel_json> — echo "tx_bytes rss_kb". See the SIZE AXIS header above.
#   tx_bytes: the session transcript's on-disk size. 0 = unknown (no/absent path) — NEVER a fire.
#   rss_kb:   resident set size of the session's OWN claude process, resolved via the telemetry
#             `.pid`. 0 = unknown, which must read as "no signal", never as "small".
#
# BOTH ZEROS ARE "UNKNOWN", NOT "SAFE-AND-SMALL". Consumers gate on `>= threshold`, so an unknown
# degrades to the pre-size behavior (false-NEGATIVE bias, the house rule for every signal here).
#
# The pid guard is load-bearing: a telemetry file outlives its session (67 files live, 29 resolvable
# pids at measurement time), and pids RECYCLE. Charging a dead session's pid — now some unrelated
# process — would read a stranger's RSS as this session's. So the comm must still look like claude
# (CC_CE_RSS_COMM_RX) or the answer is 0/unknown. One `ps` fork per call; consumers decide cadence.
ce_size() {
  local tp="${1:-}" tel="${2:-}" tx=0 rss=0 pid="" line comm rx
  if [ -n "$tp" ] && [ -f "$tp" ]; then
    tx="$(stat -f%z "$tp" 2>/dev/null || stat -c%s "$tp" 2>/dev/null || echo 0)"
    case "$tx" in ''|*[!0-9]*) tx=0 ;; esac
  fi
  if [ -n "$tel" ] && [ -f "$tel" ] && command -v jq >/dev/null 2>&1; then
    pid="$(jq -r '.pid // empty' "$tel" 2>/dev/null || echo '')"
    case "$pid" in ''|*[!0-9]*) pid="" ;; esac
  fi
  if [ -n "$pid" ] && [ "$pid" -gt 0 ] 2>/dev/null; then
    # `ps -o rss=,comm=` — comm is the EXECUTABLE path, so it survives the argv-truncation trap that
    # bites `ps -o comm=` on long command lines and the brief-matching trap that bites `pgrep -f`.
    #
    # awk, NOT `${line%% *}` on raw ps output: `ps -o rss=` RIGHT-ALIGNS in a width-varying column, so a
    # small RSS comes back as "  1984 bash" and `${line%% *}` yields the EMPTY string ⇒ rss=0 ⇒ the axis
    # reads "unknown" and silently never fires. It happens to parse correctly only when the digits fill
    # the column exactly, so this is a defect that PASSES a spot-check on one live pid and dies on the
    # next — the same silent-no-op shape as the dead column this signal replaces. awk splits on runs of
    # whitespace and ignores leading blanks, so the width can never matter.
    line="$("${CC_CE_PS:-ps}" -o rss=,comm= -p "$pid" 2>/dev/null | awk 'NR==1{print $1" "$2}' || true)"
    rss="${line%% *}"; comm="${line#* }"
    case "$rss" in ''|*[!0-9]*) rss=0 ;; esac
    rx="${CC_CE_RSS_COMM_RX:-claude}"
    printf '%s' "$comm" | grep -qE "$rx" || rss=0        # pid recycled / not ours ⇒ unknown, not small
  fi
  printf '%s %s' "$tx" "$rss"
  return 0
}
