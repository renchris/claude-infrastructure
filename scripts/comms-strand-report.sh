#!/bin/bash
# comms-strand-report.sh — re-derivable inventory of cross-session mail delivery loss.
#
# THIS SCRIPT IS THE CITATION for docs/plans/CROSS_SESSION_COMMS_V2.md §2 (M1-M8). A count in a
# design doc is a CLAIM; a script anyone can re-run is data. Written because this rebuild's own
# Phase 1 found that a handed-down "3,333 stranded lines" was TOTAL LINES, not loss — the honest
# figure was 1,764 never-surfaced. Numbers that gate a design decision must be re-derivable.
#
#   comms-strand-report.sh            human table
#   comms-strand-report.sh --json     machine-readable object
#
# THE THREE COUNTS ARE NOT INTERCHANGEABLE — conflating them is how the handed-down number was wrong:
#   total    = every line ever delivered into the box (includes mail that WAS read before death)
#   unseen   = lines - .seen   → never SURFACED to any model. The honest loss figure.
#   unacked  = lines - .acked  → never PROVABLY consumed. The fail-loud guard's own signal.
#
# ── WHY THE LIVENESS DETECTOR IS POSITIVE-CONTROLLED ─────────────────────────────────────────────
# Every box whose pane is not in the live list is counted as stranded. So if the detector silently
# returns nothing, EVERY box reads as dead and the script fabricates a catastrophe. That is not
# hypothetical: while measuring §2 this rebuild ran `it2 --list --json` (a verb that does not exist),
# got empty output and rc 0, and reported "0 live panes" — a fabricated number that would have made
# all 97 mailboxes look stranded. The fix is structural, not care: a readable list must contain a
# pane we KNOW is alive (our own, when we have one), and a list that is missing, non-array, timed
# out, or fails its own control produces verdict=unknown and NO strand numbers at all.
# A non-verdict is not a zero (memory: named-failure-vs-no-verdict, absence-alarm-needs-evidence).
#
# Env: CC_MAILBOX_DIR · CC_STRAND_IT2_TIMEOUT_S (25) · CC_STRAND_FIXTURE_RE (test-UUID exclusion)
# Exit: 0 = report produced · 3 = no liveness oracle (verdict=unknown; no numbers claimed)
set -uo pipefail

MBDIR="${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}"
IT2_TIMEOUT="${CC_STRAND_IT2_TIMEOUT_S:-25}"
# The live alarm store is ~40% fixture noise (501 of 1,258 entries carry one test UUID, leaked by
# suites into the live dir — cc-backlog 817faf3a4968). Mailboxes are cleaner, but the same suites
# use the same keys, so exclude them from every denominator rather than quietly inflating the loss.
FIXTURE_RE="${CC_STRAND_FIXTURE_RE:-^(AAAAAAAA|BBBBBBBB|DEADBEEF|CAFEBABE|0BADF00D|11111111|22222222|33333333|44444444)-}"
JSON=0
[ "${1:-}" = "--json" ] && JSON=1

_lib=""
for c in "$(dirname "$0")/../hooks/lib/mailbox-pending.sh" \
         "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/mailbox-pending.sh" \
         "$HOME/.claude/hooks/lib/mailbox-pending.sh"; do
  [ -f "$c" ] && { _lib="$c"; break; }
done
[ -n "$_lib" ] || { echo "comms-strand-report: mailbox-pending.sh not found" >&2; exit 3; }
# shellcheck disable=SC1090
. "$_lib"

# ── liveness oracle, BOUNDED and POSITIVE-CONTROLLED ─────────────────────────────────────────────
LIVE_LIST="$(mktemp 2>/dev/null || echo /tmp/strand-live.$$)"
trap 'rm -f "$LIVE_LIST" 2>/dev/null' EXIT INT TERM
ORACLE="unknown"

it2_bin=""
for c in "$HOME/.claude/bin/it2" "$(command -v it2 2>/dev/null)"; do
  [ -n "$c" ] && [ -x "$c" ] && { it2_bin="$c"; break; }
done

if [ -n "$it2_bin" ] && command -v jq >/dev/null 2>&1; then
  raw="$(timeout "$IT2_TIMEOUT" "$it2_bin" session list --json 2>/dev/null || true)"
  # A VALID JSON ARRAY (even []) means the list is readable; anything else is no oracle at all.
  if [ -n "$raw" ] && printf '%s' "$raw" | jq -e 'type=="array"' >/dev/null 2>&1; then
    printf '%s' "$raw" | jq -r '.[].id // empty' 2>/dev/null | tr '[:lower:]' '[:upper:]' | sort -u > "$LIVE_LIST"
    ORACLE="readable"
    # POSITIVE CONTROL: if we are in a pane, that pane MUST be in the list we just read. If it is
    # not, the list is not describing this machine's reality and every "dead" verdict below is void.
    own="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; own="${own##*:}"; own="$(printf '%s' "$own" | tr '[:lower:]' '[:upper:]')"
    if [ -n "$own" ]; then
      if grep -qxF "$own" "$LIVE_LIST"; then
        ORACLE="controlled"
      else
        ORACLE="control-failed"
      fi
    fi
  fi
fi

# ── the SECOND identity space (backlog 8370af320af5) ─────────────────────────────────────────────
# A box key is written in one of two spaces. cc-notify addresses panes, so many boxes are pane-keyed
# — and that is the only space the list above describes. But the session registry also carries a
# `session_id`, and boxes exist under that too, so every session-uuid-keyed box was unmatched and
# counted dead. Measured 2026-08-17 before this fix: of 544 boxes it called 534 dead, and eight of
# those belonged to sessions that were live at that instant, including the one running the report.
# Under kitty the spaces are not even the same shape (pane ids read `102`, `131`), so the match
# could not have succeeded by accident.
#
# The registry is therefore a REQUIRED second oracle, on the same terms as the first: unreadable, or
# readable but not describing this machine, means no numbers. Anything weaker keeps the failure —
# with the registry unread, every uuid-keyed box is fabricated-dead, and that fabrication IS the
# headline number this report exists to state.
if [ "$ORACLE" = "readable" ] || [ "$ORACLE" = "controlled" ]; then
  sessions_bin="${CC_SESSIONS_BIN:-}"
  if [ -z "$sessions_bin" ]; then
    for c in "$HOME/.claude/bin/cc-sessions" "$(command -v cc-sessions 2>/dev/null)"; do
      [ -n "$c" ] && [ -x "$c" ] && { sessions_bin="$c"; break; }
    done
  fi
  reg=""
  [ -n "$sessions_bin" ] && reg="$(timeout "$IT2_TIMEOUT" "$sessions_bin" --json 2>/dev/null || true)"
  if [ -z "$reg" ] || ! printf '%s' "$reg" | jq -e 'type=="array"' >/dev/null 2>&1; then
    ORACLE="registry-unreadable"
  else
    printf '%s' "$reg" | jq -r '.[] | (.session_id // empty), (.paneUUID // empty)' 2>/dev/null \
      | tr '[:lower:]' '[:upper:]' | grep -v '^$' >> "$LIVE_LIST"
    sort -u -o "$LIVE_LIST" "$LIVE_LIST"
    # CONTROL, on the axis the pane-id control cannot see. The old control asked whether THIS PANE was
    # in the pane list; it was, so it passed while blind to the only space that fails. This one asks
    # whether the registry knows this pane at all — a registry describing some other machine is not an
    # oracle for this one, and its session_ids would then adjudicate nothing.
    if [ -n "${own:-}" ]; then
      if printf '%s' "$reg" | jq -e --arg p "$own" '[.[] | (.paneUUID // "") | ascii_upcase] | index($p) != null' >/dev/null 2>&1; then
        :
      else
        ORACLE="control-failed"
      fi
    fi
  fi
fi

# A missing/failed oracle must NOT be reported as "everything is stranded".
if [ "$ORACLE" = "unknown" ] || [ "$ORACLE" = "control-failed" ] || [ "$ORACLE" = "registry-unreadable" ]; then
  if [ "$JSON" = 1 ]; then
    printf '{"verdict":"unknown","oracle":"%s","reason":"no positive-controlled pane-liveness oracle; no strand numbers claimed"}\n' "$ORACLE"
  else
    echo "comms-strand-report: verdict=unknown oracle=$ORACLE"
    echo "  NO strand numbers are reported: without a positive-controlled live-pane list every"
    echo "  mailbox would read as dead and the result would be fabricated. Fix the oracle first:"
    echo "    $HOME/.claude/bin/it2 session list --json | jq -r '.[].id' | head"
  fi
  exit 3
fi

# ── walk the store ───────────────────────────────────────────────────────────────────────────────
boxes=0 fixture=0 live_boxes=0 dead_boxes=0
dead_total=0 dead_unseen=0 dead_unacked=0
dead_withmail=0 dead_withfwd=0 dead_nocursor=0 live_unacked=0

for f in "$MBDIR"/*.md; do
  [ -f "$f" ] || continue
  k="$(basename "$f" .md)"
  if printf '%s' "$k" | grep -qE "$FIXTURE_RE"; then fixture=$(( fixture + 1 )); continue; fi
  boxes=$(( boxes + 1 ))
  ku="$(printf '%s' "$k" | tr '[:lower:]' '[:upper:]')"
  un="$(mailbox_unacked_count "$k")"
  if grep -qxF "$ku" "$LIVE_LIST"; then
    live_boxes=$(( live_boxes + 1 )); live_unacked=$(( live_unacked + un ))
  else
    dead_boxes=$(( dead_boxes + 1 ))
    dead_total=$((  dead_total  + $(mailbox_lines "$k") ))
    dead_unseen=$(( dead_unseen + $(mailbox_pending_count "$k") ))
    dead_unacked=$(( dead_unacked + un ))
    [ "$un" -gt 0 ] && dead_withmail=$(( dead_withmail + 1 ))
    [ -f "$MBDIR/$k.forward" ] && dead_withfwd=$(( dead_withfwd + 1 ))
    [ -f "$MBDIR/$k.acked" ]   || dead_nocursor=$(( dead_nocursor + 1 ))
  fi
done

# .forward coverage — the measured reach of the cooperative-push repair mechanism (§2 M8).
fwd_pct=0
[ "$dead_boxes" -gt 0 ] && fwd_pct=$(( dead_withfwd * 1000 / dead_boxes ))

# wake-arm rate over LIVE panes (§2 M15). NOTE: reads 0 while the wake floor is undeployed — that is
# an inertness signal, not a design verdict. Deploy truth belongs to row 1; see §2.1(b).
live_panes=0 armed=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  live_panes=$(( live_panes + 1 ))
  mailbox_wake_armed "$p" && armed=$(( armed + 1 ))
done < "$LIVE_LIST"

if [ "$JSON" = 1 ]; then
  printf '{"verdict":"ok","oracle":"%s","boxes":%d,"fixture_excluded":%d,"live_boxes":%d,"dead_boxes":%d,' \
    "$ORACLE" "$boxes" "$fixture" "$live_boxes" "$dead_boxes"
  printf '"dead_total_lines":%d,"dead_never_surfaced":%d,"dead_never_consumed":%d,' \
    "$dead_total" "$dead_unseen" "$dead_unacked"
  printf '"dead_boxes_with_mail":%d,"dead_boxes_with_forward":%d,"forward_coverage_permille":%d,' \
    "$dead_withmail" "$dead_withfwd" "$fwd_pct"
  printf '"dead_boxes_no_ack_cursor":%d,"live_unacked":%d,"live_panes":%d,"wake_armed":%d}\n' \
    "$dead_nocursor" "$live_unacked" "$live_panes" "$armed"
  exit 0
fi

echo "comms-strand-report  verdict=ok oracle=$ORACLE  ($MBDIR)"
echo
printf '  mailboxes                        %6d   (fixture-keyed excluded: %d)\n' "$boxes" "$fixture"
printf '  live-pane boxes                  %6d   unacked in them: %d\n' "$live_boxes" "$live_unacked"
printf '  dead-pane boxes                  %6d\n' "$dead_boxes"
echo
echo "  --- loss in dead-pane boxes (the three counts are NOT interchangeable) ---"
printf '    total lines ever delivered     %6d\n' "$dead_total"
printf '    NEVER SURFACED (lines-.seen)   %6d   <-- the honest loss figure\n' "$dead_unseen"
printf '    never consumed (lines-.acked)  %6d   <-- fail-loud guard signal\n' "$dead_unacked"
echo
printf '    dead boxes holding >=1 unacked %6d\n' "$dead_withmail"
printf '    dead boxes with NO .acked      %6d   (nothing was ever read from these)\n' "$dead_nocursor"
printf '    dead boxes WITH a .forward     %6d   = %d.%d%% coverage of the push repair\n' \
  "$dead_withfwd" "$(( fwd_pct / 10 ))" "$(( fwd_pct % 10 ))"
echo
printf '  wake path armed                  %6d of %d live panes\n' "$armed" "$live_panes"
[ "$live_panes" -gt 0 ] && [ "$armed" = 0 ] && \
  echo "    (0 armed: check whether the wake floor is DEPLOYED before reading this as a design failure —"
[ "$live_panes" -gt 0 ] && [ "$armed" = 0 ] && \
  echo "     grep -c wake \$HOME/.claude/hooks/session-continue.sh)"
exit 0
