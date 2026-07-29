#!/bin/bash
# cc-beat.sh — the READ side of the session presence beat (SESSION_REGISTRY_V2 §4.2).
#
# The beat inverts how "who drove the last turn" is answered. v1 re-derived it per sweep, per
# session, by scanning multi-MB transcripts (hooks/lib/cc-interactive.sh) — correct but paid
# ~19,412 times to make 80 decisions, and, worse, evaluated ONCE per sweep as a batch snapshot then
# acted on up to 2,099s later (p99; max 15.5h measured). An operator who typed during the sweep was
# invisible to the decision that closed their pane (the 2026-07-24 live-conversation reaps).
#
# v2: the SESSION attests presence at the instant it knows it (hooks/session-beat.sh, ~2ms), and
# this library reads that attestation in O(1) — cheap enough to re-take IMMEDIATELY before a close,
# which is what makes the ≤60s decision-freshness contract structural rather than aspirational.
#
# API (pure reader — no writes, no side effects):
#   cb_last_beat <sid>      → the beat JSON on stdout; empty + return 1 when absent/unreadable
#   cb_operator_age <sid>   → seconds since the last who=operator beat; empty + return 1 if UNKNOWN
#   cb_system_live          → return 0 iff the beat SYSTEM is demonstrably producing (see below)
#
# THE EXISTENCE GATE (cb_system_live) — why this exists and why it is not optional:
#   The read side is fail-CLOSED: "cannot prove the operator is absent" ⇒ refuse the close (R3).
#   Applied naively that rule silently inerts the whole reaper the moment the producer is not
#   deployed — every session would look beat-less, every reap would refuse, and the system would
#   report a healthy 100% abstain. That is the absence-alarm trap: an absence assertion is only
#   meaningful where the producer's world provably EXISTS. cb_system_live is that existence
#   evidence — a beat-less WORLD is a DETECTED condition the caller must surface loudly, distinct
#   from a beat-less SESSION inside a live world, which is genuinely suspicious. Callers must
#   branch on the two, never collapse them.
#
# CONTRACT: jq/bash 3.2 only. Empty + non-zero on every miss (never fatal), so a hook sourcing this
#   under `set -u` degrades to "unknown" rather than dying. Mirrors hooks/lib/cc-interactive.sh.
#
# Env seams (tests): CC_BEAT_DIR · CC_BEAT_LIVE_MAX_S · CC_BEAT_NOW

cb_beat_dir() { printf '%s' "${CC_BEAT_DIR:-$HOME/.claude/cc-beats}"; }

cb_now() { # seamed clock (tests pin it; durable value, never an mtime)
  local n="${CC_BEAT_NOW:-}"
  case "$n" in ''|*[!0-9]*) date +%s ;; *) printf '%s' "$n" ;; esac
}

cb_last_beat() { # <sid> → beat JSON | empty+1
  local sid="${1:-}" f
  [ -n "$sid" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  f="$(cb_beat_dir)/$sid.json"
  [ -f "$f" ] || return 1
  # Validate as JSON before emitting: a torn/partial file must read as ABSENT (→ caller refuses),
  # never as a malformed row a consumer might parse into a false "no operator" answer.
  jq -e . "$f" 2>/dev/null || return 1
}

cb_operator_age() { # <sid> → seconds since last who=operator beat | empty+1 (UNKNOWN)
  local sid="${1:-}" j t now
  j="$(cb_last_beat "$sid" 2>/dev/null)" || return 1
  # operatorT is the sticky high-water mark of operator presence — a later who=auto beat (a Stop
  # turn, our own auto-drive re-prompt) must NEVER lower it. Presence, once shown, decays only by
  # the clock. Producer keeps it; a beat lacking the field is pre-v2 and reads UNKNOWN, not zero.
  t="$(printf '%s' "$j" | jq -r '.operatorT // empty' 2>/dev/null)"
  case "$t" in ''|*[!0-9]*) return 1 ;; esac
  now="$(cb_now)"
  # A clock that moved backwards (NTP step, a pinned test clock) must not forge a huge age and
  # thereby a false "operator long gone" — clamp at 0, the safe direction.
  if [ "$now" -lt "$t" ] 2>/dev/null; then printf '0'; return 0; fi
  printf '%s' "$(( now - t ))"
}

cb_system_live() { # return 0 iff ANY beat is younger than CC_BEAT_LIVE_MAX_S (the existence gate)
  local d max now f t
  d="$(cb_beat_dir)"
  [ -d "$d" ] || return 1
  max="${CC_BEAT_LIVE_MAX_S:-900}"
  case "$max" in ''|*[!0-9]*) max=900 ;; esac
  now="$(cb_now)"
  command -v jq >/dev/null 2>&1 || return 1
  for f in "$d"/*.json; do
    [ -f "$f" ] || continue
    t="$(jq -r '.t // empty' "$f" 2>/dev/null)"
    case "$t" in ''|*[!0-9]*) continue ;; esac
    [ "$(( now - t ))" -le "$max" ] 2>/dev/null && return 0
  done
  return 1
}
