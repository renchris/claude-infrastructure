#!/usr/bin/env bash
# hooks/lib/transcript-age.sh — the session's own transcript mtime as a liveness signal.
#
# ONE SOURCE for a predicate that had exactly one implementation and two more consumers that needed
# it. Extracted verbatim from scripts/lead-supervisor.sh (item 1c324d9fcc32), which keeps its
# behavior by sourcing this file. Consumers: lead-supervisor.sh (stall adjudication),
# hooks/boundary-handoff.sh + hooks/waiting-recycle.sh (the stale-telemetry fallback, row
# 5e4ce121b64a residual (a)).
#
# WHY IT EXISTS. The session's JSONL is appended on EVERY message / tool event, so its mtime is a FAR
# fresher liveness signal than telemetry `ts`. The telemetry writer is the statusline, which stops
# emitting when a pane is not actively rendering (statusline.sh:48 — "a session inside ONE long
# operation, or genuinely hung, renders ZERO times"): a healthy BACKGROUNDED / long-turn /
# idle-interactive session goes telemetry-stale for hours while its transcript stays warm (measured
# 2026-07-19: a live session at 3.5-DAY-stale telemetry with a 5-min-warm transcript).
#
# THE SENTINEL IS THE CONTRACT. Prints the transcript's age in seconds; a huge sentinel
# (999999999) when it cannot be resolved (no config_dir / missing file) so the caller treats
# "unprovable" as COLD — fail-safe: we never exempt a stall we cannot disprove. Every consumer MUST
# preserve that direction; reading the sentinel as "warm" would turn an unresolvable path into a
# blanket exemption.

# transcript_age <cwd> <config_dir> <sid> → prints age_s (999999999 = unresolved ⇒ cold)
transcript_age(){
  local cwd="$1" cfg="$2" sid="$3" slug tp mt
  { [ -n "$cwd" ] && [ -n "$cfg" ] && [ -n "$sid" ]; } || { printf '%s' 999999999; return; }
  # CC projects/ dir mangling: EVERY character outside [a-zA-Z0-9] → '-'. This read `sed 's|[/.]|-|g'`
  # under the comment "every '/' and '.' → '-'", which is narrower than the encoder
  # (`A.replace(/[^a-zA-Z0-9]/g,"-")`, and 1,661 live project dirs all match ^[-a-zA-Z0-9]+$). The
  # direction matters here: a narrow slug names a directory that CANNOT exist, so the `[ -f "$tp" ]`
  # below misses, transcript_age returns its unresolved sentinel — which this caller reads as COLD —
  # and a demonstrably-alive session with a fresh transcript is paged STALL? anyway. The warm-transcript
  # exemption at the call site is exactly what stops that, and it was unreachable for any cwd holding
  # a character other than '/', '.', '-' or alphanumerics (e.g. ~/Development/doc_classifier, a real
  # repo on this box). Fail direction: a FALSE page about a healthy session.
  slug="$(printf '%s' "$cwd" | LC_ALL=C sed 's/[^a-zA-Z0-9]/-/g')"
  tp="$cfg/projects/$slug/$sid.jsonl"
  [ -f "$tp" ] || { printf '%s' 999999999; return; }
  mt="$(stat -f %m "$tp" 2>/dev/null || stat -c %Y "$tp" 2>/dev/null || echo 0)"   # BSD stat, then GNU fallback
  printf '%s' "$(( $(date +%s) - ${mt:-0} ))"
}
