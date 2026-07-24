#!/usr/bin/env bash
# cc-interactive.sh — the ONE "WHO drove the last turn" primitive.
#
# ci_last_interactive_epoch <jsonl> → epoch SECONDS of the last REAL operator-typed prompt in the
# transcript, or empty string + return 1 when none is visible. This is the single signal the reaper's
# done-evidence cannot fake: "idle + clean + landed" is every interactive conversation's steady state
# between prompts (2026-07-24 Danny-Studio-60 / Opus-5 reaps of two live operator conversations), so
# a "done" decision must read WHO drove the last turn, not only WHEN. Consumers: cc-classify (now —
# its last_interactive_epoch is a thin wrapper over this); teammate-auto-shutdown + cc-teardown
# (landing next — the same WHO-drove signal on the self-close / final-gate legs).
#
# INTERACTIVE (ground-truthed against production transcripts 2026-07-20; kept in sync with
# hooks/lib/context-econ.sh ce_last_interactive_age — the canonical predicate this extracts):
#   type=="user" AND isMeta != true AND the content is one of
#     • a string (the ordinary typed prompt), OR
#     • an array with NO tool_result whose text blocks join to a non-empty string, OR
#     • an array with NO tool_result carrying an image block — an image-only paste (⌘V of a
#       screenshot) is operator PRESENCE even with no text (added 2026-07-24),
#   AND the text does not match the auto-traffic regex (task-notifications, <local-command-stdout>,
#   Stop-hook feedback, interrupt markers, our own ⟳/⚑/⚠ hook advisories). Operator slash-commands
#   COUNT (the operator is present). isMeta + "Stop hook feedback:" auto-drive re-prompts are excluded
#   on two independent axes, so a self-driving desk still reads NON-interactive (load-bearing: a
#   conversation-hold that counted its own auto-drive would deadlock every recycle). A tool_result
#   carried inside a user record is tool traffic, never an operator prompt — excluded.
#
# Env seams: CC_CLASSIFY_INTERACTIVE_TAIL_BYTES (default 2000000 — recency needs the tail only) ·
#   CC_CLASSIFY_AUTO_RX (the auto-traffic regex; same default as cc-classify/context-econ).
# FALLBACK: when the bounded tail yields nothing AND the file is LARGER than the tail window, a
#   whole-file scan with the IDENTICAL predicate runs. done-evidence scans the whole file, so the
#   interactive hold must too — else an operator turn buried beyond the tail window (a long transcript)
#   silently stops holding and the pane reaps mid-conversation (the tail-limited-hold residual).
#
# CONTRACT: pure reader, no writes; jq/bash only, no other deps. Empty + return 1 on any miss/failure
# (never a fatal), so a sourcing hook under set -u degrades to "no interactive turn", never an error.

ci_last_interactive_epoch() { # <jsonl> → epoch seconds on stdout (empty + return 1 when none visible)
  local f="${1:-}" tailb rx ep fsz prog
  [ -n "$f" ] && [ -f "$f" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  tailb="${CC_CLASSIFY_INTERACTIVE_TAIL_BYTES:-2000000}"
  rx="${CC_CLASSIFY_AUTO_RX:-^<task-notification>|^<local-command-stdout>|^Stop hook feedback:|^\\[Request interrupted|^⟳|^⚑|^⚠}"
  # The predicate, applied IDENTICALLY to the tail and (on a tail-miss) the whole file. fromjson? drops
  # the possibly-partial first tailed line; objects/strings guard scalar lines so one odd line can never
  # abort the scan (jq runtime errors are per-program, not per-line). $ntr/$nimg gate the array cases:
  # a tool_result anywhere ⇒ $t is jq `empty` (row dropped — tool traffic, and a tool-returned image is
  # not an operator paste); an image with no tool_result counts even when the joined text is empty.
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
  ep="$(tail -c "$tailb" "$f" 2>/dev/null | jq -Rr --arg rx "$rx" "$prog" 2>/dev/null | tail -1)"
  case "$ep" in
    ''|*[!0-9]*)
      # tail-miss: if the file exceeds the tail window an interactive turn may be buried earlier — the
      # hold must match done-evidence's whole-file reach, so re-scan the full file with the same program.
      fsz="$(wc -c < "$f" 2>/dev/null | tr -d ' ')"; case "$fsz" in ''|*[!0-9]*) fsz=0 ;; esac
      if [ "$fsz" -gt "$tailb" ]; then
        ep="$(jq -Rr --arg rx "$rx" "$prog" "$f" 2>/dev/null | tail -1)"
      fi
      ;;
  esac
  case "$ep" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$ep"
}
