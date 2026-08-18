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
#
# ── THE DENOMINATOR, AND WHY IT IS *NOT* A 4th COLUMN HERE (2026-07-30, row 8 / §4.2) ───────────
# used_pct is a PERCENTAGE OF A NUMBER NOTHING DURABLY RECORDS. Measured: the context window
# appears only in the ephemeral statusline telemetry (74 files for 4,890 transcripts = 1.5%
# coverage, wiped on reboot) and NEVER in the durable transcript — verified by an exhaustive jq
# path-scan for window/max_tokens/limit keys with a positive control on message.usage.*. And it
# cannot be imputed from the model id: live telemetry shows claude-opus-4-8 running at BOTH
# 1,000,000 and 200,000. So every threshold in this subsystem (CC_CE_WALL=88, boundary T=73,
# T_IDLE=35, T_BUSY=75) is a percentage of an unrecorded quantity, and "p95 recycle fill" was
# unfalsifiable — not for want of a numerator, but because the DENOMINATOR WAS THROWN AWAY.
#
# The obvious fix — append the window as a 4th .hist column — WAS TRIED AND REJECTED ON MERIT
# during this build, and the reason is worth keeping: `.hist` lives in the SAME EPHEMERAL
# /tmp/cc-telemetry directory as the telemetry JSON it samples. A 4th column there would be exactly
# as unrecoverable as the value it was meant to preserve, so it buys no durability at all — while
# breaking two passing contract tests that pin the 3-field line. The 4-column version was written,
# measured against the suite, and reverted.
#
# So the denominator is captured where the record is actually DURABLE, and only there:
#   • ce_log_drop below → the IDL ($HOME/.claude/autonomy/idl.jsonl), on every fill-drop event
#   • the recycle-outcome store ($HOME/.claude/autonomy/recycle-events.jsonl), on every recycle
# Both are under $HOME and survive a reboot. `win` is still read here from the producer's LITERAL
# `.window` (never a 200000/1000000 guess — imputing it is the error this row committed and withdrew
# in Phase 1, where a hardcoded 1M turned an 85.3%-of-200K kill into a phantom "17.1% low-fill
# kill") and is passed to ce_log_drop, where an absent value lands as JSON null, never a default.
# ce_log_drop <tel_json> <from_pct> <to_pct> <tokens> <window> — record ONE fill-drop event to the
# IDL before ce_sample truncates the history that is its only trace (see the call site).
#
# Self-describing by construction (invariant R5): the record carries the window alongside the
# percentages, so a later reader cannot mis-scale it the way this row's own Phase 1 did. `window`
# is null — never a default — when the producer did not emit one.
#
# `hook` is "context-econ" so this never collides with the waiting-recycle / boundary-handoff
# namespaces already in the IDL, and `reason:"fill-drop"` is the parseable token consumers key on
# (R8 — one token, one meaning; the incumbent's overloaded `fired` meant four things).
# Fail-soft at every seam: no jq, no writable dir, or a kill switch ⇒ silent return 0.
# ── TEST CONTAINMENT (row 5e4ce121b64a residual (b)) ─────────────────────────────────────────────
# Both writers below resolve a DURABLE store, and both already prefer CLAUDE_CONFIG_DIR over $HOME
# for exactly this reason — see their own comments. That covers a suite which fixtures its config
# root. It does NOT cover a suite that fixtures NEITHER, and such a suite writes straight into the
# operator's live store.
#
# MEASURED 2026-08-18, and the census in the item UNDERSTATED it: tests/boundary-handoff.bats scopes
# neither HOME nor CLAUDE_CONFIG_DIR and appended 29 rows to the REAL
# ~/.claude/autonomy/recycle-events.jsonl on EVERY run — confirmed by before/after count, not by
# reading. 2,907 of that store's 3,743 rows carry fixture sids, so the durable denominator
# cc-ctx-audit reads for window/fill history is ~78% test exhaust, and it is still growing today.
# Only 61 of 512 suites scope a config root at all, so fixing the one suite that happened to be
# caught is whack-a-mole: the invariant belongs HERE, at the single point where a path becomes a
# write (memory: enforcement-must-live-at-the-chokepoint).
#
# THE INVARIANT: under bats, a store path resolving OUTSIDE BATS_TEST_TMPDIR is redirected into it.
# A suite that already scopes its own root — via CC_RECYCLE_EVENTS / CC_IDL / CLAUDE_CONFIG_DIR /
# HOME — resolves inside the tmpdir and passes through UNTOUCHED, so every existing fixture-isolation
# assertion keeps its meaning. Outside bats this is identity: production is never redirected.
_ce_contain() { # $1=resolved store path → the path, contained iff we are under bats
  case "${BATS_TEST_TMPDIR:-}" in
    '') printf '%s' "$1" ;;
    *) case "$1" in
         "$BATS_TEST_TMPDIR"/*) printf '%s' "$1" ;;
         *)                     printf '%s/%s' "$BATS_TEST_TMPDIR" "${1##*/}" ;;
       esac ;;
  esac
}

ce_log_drop() {
  local tel="${1:-}" from="${2:-0}" to="${3:-0}" tok="${4:-0}" win="${5:-}" idl sid ts
  [ "${CC_CE_DROP_LOG:-on}" = off ] && return 0
  command -v jq >/dev/null 2>&1 || return 0
  # CLAUDE_CONFIG_DIR before $HOME — a hook runs under a fixtured config root in tests and under the
  # session's own root in production, and reaching past it to $HOME made this writer create
  # directories under a suite's CANARY HOME (caught by waiting-recycle.bats' fixture-isolation test,
  # which asserts nothing lands outside the fixture root).
  idl="${CC_CE_IDL:-${CC_IDL:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/autonomy/idl.jsonl}}"
  idl="$(_ce_contain "$idl")"
  mkdir -p "$(dirname "$idl")" 2>/dev/null || return 0
  sid="${tel##*/}"; sid="${sid%.json}"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  # a non-numeric/absent window must land as JSON null, not as the string "-" and not as 0
  case "$win" in ''|-|*[!0-9]*) win=null ;; esac
  jq -cn --arg ts "$ts" --arg sid "$sid" \
        --argjson from "${from:-0}" --argjson to "${to:-0}" \
        --argjson tok "${tok:-0}" --argjson win "$win" \
    '{ts:$ts,hook:"context-econ",sid:$sid,disposition:"observed",reason:"fill-drop",
      from_pct:$from,to_pct:$to,drop_pct:($from-$to),input_tokens:$tok,window:$win}' \
    >> "$idl" 2>/dev/null || true
  return 0
}

# ce_record_recycle <tel_json> <verdict> <used_pct> <trigger> <mode> — append ONE self-describing
# record to the DURABLE recycle-outcome store ($HOME/.claude/autonomy/recycle-events.jsonl).
#
# WHY THIS EXISTS — the row's central defect. waiting-recycle wrote 32,075 IDL records and not one
# of them answers "did a session recycle, and at what fill". Two reasons, both structural:
#
#   1. NO DENOMINATOR. Every record carried used_pct, a percentage of a window nothing durably
#      recorded (see the ce_sample header). So even the fill it did log was uninterpretable later.
#   2. `disposition:"fired"` MEANT FOUR DIFFERENT THINGS — the Stage-1 advisory, the Stage-2 live
#      exec, the Stage-2 shadow would-fire, and the busy nudge all logged `fired`. Measured: of the
#      3 `fired` records in the entire live IDL, TWO were advisory nudges and one was a Stage-1
#      advisory. The count of actual executed recycles was ZERO, and the overloaded token made a
#      mechanism that has never once executed look like it was working.
#
# So `verdict` here is a CLOSED, PARSEABLE ENUM — exactly one of:
#   advised            Stage-1 told the model to recycle; nothing was executed
#   shadow-would-fire  Stage-2 composed everything and deliberately did NOT exec (damp-first)
#   executed           a recycle actually ran (the ONLY value that means the context was replaced)
#   nudged             the busy-medium pause-point advisory
#   refused            the actuator WAS invoked and exited non-zero — nothing was recycled. This
#                      record RETRACTS the immediately preceding `executed` for the same sid.
# One token, one meaning (invariant R8). A consumer can finally count executions without inferring.
#
# THE ONE PAIRING A CONSUMER MUST HONOUR — `executed` is a CLAIM until no `refused` retracts it.
# Count executions as `executed` MINUS the `refused` records that follow one for the same sid, never
# as a bare `grep -c executed`. This is forced by the actuator, not chosen: a successful
# `handoff-fire --recycle` types /exit, whose interrupt SIGKILLs the calling hook's process group, so
# the caller cannot reliably write anything AFTER a success — the success record must precede the
# call. A refusal returns normally (handoff-fire's recycle pre-pass refuses before any side effect),
# so it can only be written after. Before `refused` existed, waiting-recycle.sh discarded that rc
# entirely (`|| true`) and every refusal was banked here as a completed recycle — an ACTUATION LEDGER
# that counted declarations, which is precisely the defect MASTER_SESSION_LIFECYCLE L4 exists to kill.
#
# Fail-soft at every seam, like every function here: no jq / unwritable dir / kill switch ⇒ return 0
# and the caller is unaffected. Bounded (R7): pruned to half when it exceeds CC_RECYCLE_MAX.
# Kill switch: CC_RECYCLE_LOG=off. Path override: CC_RECYCLE_EVENTS.
ce_record_recycle() {
  local tel="${1:-}" verdict="${2:-}" used="${3:-}" trigger="${4:-}" mode="${5:-}"
  local store sid win tok ts max lines
  [ "${CC_RECYCLE_LOG:-on}" = off ] && return 0
  [ -n "$verdict" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  # CLAUDE_CONFIG_DIR before $HOME — see the same note in ce_log_drop. A default that reaches past
  # the fixtured config root turns every hook that calls this into a writer outside its own sandbox.
  store="${CC_RECYCLE_EVENTS:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/autonomy/recycle-events.jsonl}"
  store="$(_ce_contain "$store")"
  mkdir -p "$(dirname "$store")" 2>/dev/null || return 0
  # the denominator + numerator, read from the producer's LITERAL emission — never imputed
  win=''; tok=''
  if [ -n "$tel" ] && [ -f "$tel" ]; then
    win="$(jq -r '.window // empty' "$tel" 2>/dev/null || echo '')"; win="${win%.*}"
    tok="$(jq -r '.input_tokens // empty' "$tel" 2>/dev/null || echo '')"; tok="${tok%.*}"
  fi
  case "$win" in ''|*[!0-9]*) win=null ;; esac
  case "$tok" in ''|*[!0-9]*) tok=null ;; esac
  case "$used" in ''|*[!0-9]*) used=null ;; esac
  sid="${tel##*/}"; sid="${sid%.json}"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  jq -cn --arg ts "$ts" --arg sid "$sid" --arg v "$verdict" \
        --arg trigger "${trigger:-unknown}" --arg mode "${mode:-unknown}" \
        --argjson used "$used" --argjson tok "$tok" --argjson win "$win" \
    '{ts:$ts,sid:$sid,hook:"context-econ",verdict:$v,used_pct:$used,
      input_tokens:$tok,window:$win,trigger:$trigger,mode:$mode}' \
    >> "$store" 2>/dev/null || return 0
  max="${CC_RECYCLE_MAX:-5000}"
  lines="$(wc -l < "$store" 2>/dev/null | tr -d ' ')"; case "$lines" in ''|*[!0-9]*) lines=0 ;; esac
  if [ "$lines" -gt "$max" ]; then
    if tail -n $(( max / 2 )) "$store" > "$store.tmp.$$" 2>/dev/null; then
      mv -f "$store.tmp.$$" "$store" 2>/dev/null || rm -f "$store.tmp.$$" 2>/dev/null
    else
      rm -f "$store.tmp.$$" 2>/dev/null
    fi
  fi
  return 0
}

ce_sample() {
  local tel="${1:-}" hist ts used tok win last last_ts last_used max lines rec
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
  # THE DENOMINATOR (see the header). The producer's literal `.window`, never a guess: a missing or
  # non-numeric value stays EMPTY so a consumer reads UNKNOWN. `-` is the on-disk placeholder,
  # because a bare trailing space would make the 4th field indistinguishable from a legacy 3-field
  # line, and awk's positional read would then silently yield "" for BOTH cases.
  win="$(jq -r '.window // empty' "$tel" 2>/dev/null || echo '')"; win="${win%.*}"
  case "$win" in ''|*[!0-9]*) win='' ;; esac
  rec="$ts $used $tok"
  last="$(tail -1 "$hist" 2>/dev/null || true)"
  last_ts="${last%% *}"; case "$last_ts" in ''|*[!0-9]*) last_ts=0 ;; esac
  [ "$ts" -gt "$last_ts" ] || return 0
  if [ "$last_ts" -gt 0 ]; then
    last_used="$(printf '%s' "$last" | awk '{print $2}' 2>/dev/null)"
    case "$last_used" in ''|*[!0-9]*) last_used=0 ;; esac
    if [ "$used" -lt $(( last_used - 2 )) ]; then
      # ── THE FILL-DROP EVENT IS NOW RECORDED BEFORE THE EVIDENCE IS DESTROYED ──────────────────
      # A drop > 2 points is the ONLY signal this system has that a context was compacted or
      # replaced. The truncation below is CORRECT (the prior slope is poisoned and must not feed
      # ce_burn) — but for its whole life this branch detected the event and then overwrote the only
      # trace of it, leaving no counter, no log and no IDL line. The subsystem could therefore never
      # answer "how often did a context reset out from under us", which is half its own mandate.
      # Emit first, truncate second. Best-effort and fully guarded: a logging failure must never
      # cost the sample (the lib's contract), and no path here changes ce_burn's answer.
      ce_log_drop "$tel" "$last_used" "$used" "$tok" "$win" || true
      printf '%s\n' "$rec" > "$hist" 2>/dev/null || true
      return 0
    fi
  fi
  printf '%s\n' "$rec" >> "$hist" 2>/dev/null || true
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
# The scan reads the tail (CC_CE_TAIL_BYTES, default 2MB) and, on a tail-MISS over a file bigger than
# that window, re-scans the whole file with the identical program (see FALLBACK below).
#
# INTERACTIVE (ground-truthed against production transcripts, 2026-07-20):
#   type=="user" AND isMeta != true AND the content is one of
#     • a string (the ordinary typed prompt), OR
#     • an array with NO tool_result whose text blocks join to a non-empty string, OR
#     • an array with NO tool_result carrying an image block — an image-only paste (⌘V of a
#       screenshot) is operator PRESENCE even with no text (parity upgrade 2026-07-25),
#   AND the text does not match the auto-traffic regex. Auto-drive re-prompts (session-continue 🔧
#   loops, /goal Stop hooks) arrive as isMeta:true AND "Stop hook feedback:"-prefixed — excluded on
#   two independent axes, so an auto-driven desk still reads as NON-interactive (load-bearing: a
#   conversation-hold that counted its own auto-drive would deadlock every free-win recycle).
#   Operator slash-commands (<command-name>) COUNT (the operator is present); their paired
#   <local-command-stdout> echo, task-notifications, interrupt markers, <teammate-message> wrappers
#   (a LEAD's shutdown_request is the system asking the member to leave, not a human adopting the
#   pane), and our own ⟳/⚑/⚠ hook advisories do not. A tool_result inside a user record is tool
#   traffic, never a prompt.
#
# PARITY (2026-07-25): this predicate is the BACKSTOP for cc-classify §4.7's
# ci_last_interactive_epoch (hooks/lib/cc-interactive.sh) — the reaper's Gap-2 leg, reap-guard R-d and
# waiting-recycle S6 all gate on THIS one. It was strictly WEAKER than the gate it backs up (no
# image-only paste, no whole-file fallback), so an operator whose last turn was a screenshot paste, or
# whose prompt sat past the tail window, was invisible to every backstop. Both capabilities are now
# mirrored here — SAFER DIRECTION ONLY: each makes MORE turns count as operator presence ⇒ more holds,
# never fewer. tests/interactive-parity.bats pins the two implementations to shared fixtures.
# FALLBACK: when the bounded tail yields nothing AND the file is LARGER than the tail window, the whole
# file is re-scanned with the IDENTICAL program. done-evidence scans the whole file, so the hold must
# too — else a buried operator turn silently stops holding (the R1 tail-eviction residual).
ce_last_interactive_age() {
  local tp="${1:-}" tailb rx prog ep fsz now
  tailb="${CC_CE_TAIL_BYTES:-2000000}"
  # NOT "no operator turn" — we cannot read the file at all. Fail-closed answer, rc 2.
  { [ -n "$tp" ] && [ -f "$tp" ] && [ -r "$tp" ]; } || { printf 'unreadable'; return 2; }
  command -v jq >/dev/null 2>&1 || { printf 'unreadable'; return 2; }
  rx="${CC_CE_AUTO_RX:-^<task-notification>|^<local-command-stdout>|^<teammate-message|^Stop hook feedback:|^\\[Request interrupted|^⟳|^⚑|^⚠}"
  # The predicate, applied IDENTICALLY to the tail and (on a tail-miss) the whole file — held in
  # lockstep with cc-interactive.sh's ci_last_interactive_epoch by tests/interactive-parity.bats.
  # fromjson? drops the (possibly partial) first tailed line; `objects`/`strings` guard scalar lines so
  # one odd line can never abort the scan (jq runtime errors are per-program, not per-line). $ntr/$nimg
  # gate the array cases: a tool_result anywhere ⇒ $t is jq `empty` (row dropped — tool traffic, and a
  # tool-returned image is not an operator paste); an image with no tool_result counts even when the
  # joined text is empty.
  # shellcheck disable=SC2016  # $c/$ntr/$nimg/$t/$rx are jq variables — single quotes are REQUIRED
  prog='
      fromjson? | objects
      | select(.type=="user") | select(.isMeta != true)
      | (.message.content) as $c
      | (if ($c|type)=="array" then ([$c[]? | select(.type?=="tool_result")] | length) else 0 end) as $ntr
      | (if ($c|type)=="array" then ([$c[]? | select(.type?=="image")]       | length) else 0 end) as $nimg
      | ( if ($c|type)=="string" then $c
          elif ($c|type)=="array" and $ntr==0
          then ([$c[]? | select(.type?=="text") | .text] | join("\n"))
          else empty end ) as $t
      | select( ($t|length) > 0 or $nimg > 0 )
      | select($t | test($rx) | not)
      | (.timestamp | strings | sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch empty)'
  ep="$(tail -c "$tailb" "$tp" 2>/dev/null | jq -Rr --arg rx "$rx" "$prog" 2>/dev/null | tail -1)"
  case "$ep" in
    ''|*[!0-9]*)
      # tail-miss over a file bigger than the window ⇒ an operator turn may be buried before it. The
      # hold must reach as far as done-evidence does, so re-scan the whole file with the same program.
      fsz="$(wc -c < "$tp" 2>/dev/null | tr -d ' ')"; case "$fsz" in ''|*[!0-9]*) fsz=0 ;; esac
      if [ "$fsz" -gt "$tailb" ]; then
        ep="$(jq -Rr --arg rx "$rx" "$prog" "$tp" 2>/dev/null | tail -1)"
      fi
      ;;
  esac
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
    # comm= is LAST, so its value runs to end-of-line and its SPACES split: $2 is only the first
    # token of the executable path. This one GATES A DECISION — the `grep -qE "$rx"` below turns a
    # non-match into rss=0 ("unknown, not small") — so a binary living under a path with a space
    # (".../Library/Application Support/...") yielded "/Users/.../Application", failed the match, and
    # the signal silently read unknown for every such pid. Rebuild $2..NF. Same class as 273df7cd.
    line="$("${CC_CE_PS:-ps}" -o rss=,comm= -p "$pid" 2>/dev/null | awk 'NR==1{c = $2; for (i = 3; i <= NF; i++) c = c " " $i; print $1" "c}' || true)"
    rss="${line%% *}"; comm="${line#* }"
    case "$rss" in ''|*[!0-9]*) rss=0 ;; esac
    rx="${CC_CE_RSS_COMM_RX:-claude}"
    printf '%s' "$comm" | grep -qE "$rx" || rss=0        # pid recycled / not ours ⇒ unknown, not small
  fi
  printf '%s %s' "$tx" "$rss"
  return 0
}
