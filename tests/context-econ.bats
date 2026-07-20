#!/usr/bin/env bats
# context-econ.sh — the shared context-economics signal lib (burn/forecast + interactive recency).
#
# Coverage: ce_sample (append / ts-dedup / fill-drop reset / prune bound), ce_burn (canonical slope +
# forecast math, every unknown-degrades-to-"0 -1" seam, window exclusion, at-wall clamp),
# ce_last_interactive_age (the INTERACTIVE taxonomy against PRODUCTION-SHAPED fixture lines —
# fixture-shape parity with the real transcript producer per the 2026-07-19 fixture-parity rule:
# human turns, Stop-hook auto-drive feedback (isMeta:true + prefix), tool_result turns,
# task-notifications, <command-name> operator commands, our own ⟳ advisories, millis timestamps).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # shellcheck source=../hooks/lib/context-econ.sh
  . "$REPO/hooks/lib/context-econ.sh"
  T="$BATS_TEST_TMPDIR"
  TEL="$T/sid.json"; HIST="$T/sid.hist"; TX="$T/tx.jsonl"
}

mk_tel() { printf '{"ts":%s,"used_pct":%s,"input_tokens":%s}' "$1" "$2" "${3:-100000}" > "$TEL"; }
iso_now_ms() { date -u -r "$1" +%Y-%m-%dT%H:%M:%S.123Z 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.123Z; }

# ── ce_sample ─────────────────────────────────────────────────────────────────────────────────────
@test "sample: first telemetry appends one 'ts used tokens' line" {
  now=$(date +%s); mk_tel "$now" 42 84000
  ce_sample "$TEL"
  [ "$(cat "$HIST")" = "$now 42 84000" ]
}
@test "sample: same-ts re-poll is deduped (idempotent across hooks sharing the file)" {
  now=$(date +%s); mk_tel "$now" 42
  ce_sample "$TEL"; ce_sample "$TEL"
  [ "$(wc -l < "$HIST" | tr -d ' ')" = 1 ]
}
@test "sample: newer ts appends; fill-DROP >2 resets the series to the new sample (compaction)" {
  now=$(date +%s)
  mk_tel "$(( now - 60 ))" 50; ce_sample "$TEL"
  mk_tel "$now" 51; ce_sample "$TEL"
  [ "$(wc -l < "$HIST" | tr -d ' ')" = 2 ]
  mk_tel "$(( now + 10 ))" 12; ce_sample "$TEL"       # 51 → 12: compacted/recycled window
  [ "$(wc -l < "$HIST" | tr -d ' ')" = 1 ]
  grep -q "^$(( now + 10 )) 12" "$HIST"
}
@test "sample: prune bound — exceeding CC_CE_HIST_MAX rewrites to the newest half" {
  export CC_CE_HIST_MAX=10
  now=$(date +%s)
  for i in $(seq 1 11); do mk_tel "$(( now - 120 + i ))" "$(( 30 + i / 4 ))"; ce_sample "$TEL"; done
  [ "$(wc -l < "$HIST" | tr -d ' ')" = 5 ]
}
@test "sample: garbage/missing telemetry is a no-op (never fails, never writes)" {
  printf 'not json' > "$TEL"; ce_sample "$TEL"
  [ ! -f "$HIST" ]
  ce_sample "$T/absent.json"
}

# ── ce_burn ───────────────────────────────────────────────────────────────────────────────────────
@test "burn: canonical math — +5pct over 300s ⇒ burn_x100=100, forecast (88-60)*100/100 = 28min" {
  now=$(date +%s); mk_tel "$now" 60
  printf '%s 55 1\n%s 60 1\n' "$(( now - 300 ))" "$now" > "$HIST"
  [ "$(ce_burn "$TEL")" = "100 28" ]
}
@test "burn: unknown seams all degrade to '0 -1' — no hist, one sample, short span, flat, declining" {
  now=$(date +%s); mk_tel "$now" 60
  [ "$(ce_burn "$TEL")" = "0 -1" ]                                   # no hist at all
  printf '%s 60 1\n' "$now" > "$HIST";                       [ "$(ce_burn "$TEL")" = "0 -1" ]
  printf '%s 55 1\n%s 60 1\n' "$(( now - 60 ))" "$now" > "$HIST";  [ "$(ce_burn "$TEL")" = "0 -1" ]  # span 60 < 120
  printf '%s 60 1\n%s 60 1\n' "$(( now - 300 ))" "$now" > "$HIST"; [ "$(ce_burn "$TEL")" = "0 -1" ]  # flat
  printf '%s 62 1\n%s 60 1\n' "$(( now - 300 ))" "$now" > "$HIST"; [ "$(ce_burn "$TEL")" = "0 -1" ]  # declining
}
@test "burn: samples OLDER than the window are excluded from the slope" {
  now=$(date +%s); mk_tel "$now" 60
  # ancient fast climb + only ONE in-window sample ⇒ no in-window pair ⇒ unknown
  printf '%s 10 1\n%s 60 1\n' "$(( now - 5000 ))" "$now" > "$HIST"
  [ "$(ce_burn "$TEL")" = "0 -1" ]
}
@test "burn: at/past the wall clamps forecast to 0 (act NOW)" {
  now=$(date +%s); mk_tel "$now" 89
  printf '%s 80 1\n%s 89 1\n' "$(( now - 300 ))" "$now" > "$HIST"
  read -r _b fc <<<"$(ce_burn "$TEL")"
  [ "$fc" = 0 ]
}
@test "burn: CC_CE_WALL override moves the forecast target" {
  export CC_CE_WALL=70
  now=$(date +%s); mk_tel "$now" 60
  printf '%s 55 1\n%s 60 1\n' "$(( now - 300 ))" "$now" > "$HIST"
  [ "$(ce_burn "$TEL")" = "100 10" ]
}

# ── ce_last_interactive_age — PRODUCTION-SHAPED fixtures (fixture-parity) ─────────────────────────
# Line shapes below mirror the live producer verbatim (sampled 2026-07-20): a real human turn is
# type:user + userType:external + isMeta:null + STRING content; Stop-hook auto-drive feedback is
# isMeta:true AND "Stop hook feedback:"-prefixed; tool results are content-ARRAY tool_result items.
mk_human() { # $1=epoch $2=text
  printf '{"parentUuid":"p","isSidechain":false,"userType":"external","cwd":"/x","sessionId":"s","version":"2.1.207","type":"user","isMeta":null,"message":{"role":"user","content":"%s"},"uuid":"u","timestamp":"%s"}\n' "$2" "$(iso_now_ms "$1")" >> "$TX"
}
mk_stophook() { printf '{"type":"user","isMeta":true,"userType":"external","message":{"role":"user","content":"Stop hook feedback:\\n[keep going with the goal]"},"timestamp":"%s"}\n' "$(iso_now_ms "$1")" >> "$TX"; }
mk_toolres()  { printf '{"type":"user","userType":"external","message":{"role":"user","content":[{"tool_use_id":"t","type":"tool_result","content":"ok"}]},"timestamp":"%s"}\n' "$(iso_now_ms "$1")" >> "$TX"; }
mk_tasknote() { printf '{"type":"user","message":{"role":"user","content":"<task-notification>\\n<task-id>x</task-id>done"},"timestamp":"%s"}\n' "$(iso_now_ms "$1")" >> "$TX"; }
mk_cmd()      { printf '{"type":"user","isMeta":null,"userType":"external","message":{"role":"user","content":"<command-name>/model</command-name>\\n<command-message>model</command-message>"},"timestamp":"%s"}\n' "$(iso_now_ms "$1")" >> "$TX"; }
mk_cmdout()   { printf '{"type":"user","message":{"role":"user","content":"<local-command-stdout>Set model</local-command-stdout>"},"timestamp":"%s"}\n' "$(iso_now_ms "$1")" >> "$TX"; }
mk_advisory() { printf '{"type":"user","message":{"role":"user","content":"⟳ MONITORING AUTO-RECYCLE — quiet boundary advisory"},"timestamp":"%s"}\n' "$(iso_now_ms "$1")" >> "$TX"; }
mk_assist()   { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"watching"}]},"timestamp":"%s"}\n' "$(iso_now_ms "$1")" >> "$TX"; }

@test "recency: fresh human turn → small age; trailing tool noise does not mask it" {
  now=$(date +%s)
  mk_human "$(( now - 30 ))" "how is the build going?"
  mk_toolres "$(( now - 10 ))"; mk_assist "$(( now - 5 ))"
  age="$(ce_last_interactive_age "$TX")"
  [ -n "$age" ] && [ "$age" -ge 25 ] && [ "$age" -le 60 ]
}
@test "recency: auto-drive traffic ONLY (stop-hook feedback, tool results, task-notes, cmd stdout, our advisory) → empty" {
  now=$(date +%s)
  mk_stophook "$(( now - 10 ))"; mk_toolres "$(( now - 9 ))"; mk_tasknote "$(( now - 8 ))"
  mk_cmdout "$(( now - 7 ))"; mk_advisory "$(( now - 6 ))"; mk_assist "$(( now - 5 ))"
  [ -z "$(ce_last_interactive_age "$TX")" ]
}
@test "recency: the discriminator pair — OLD human + FRESH auto ⇒ returns the HUMAN age (auto never counts)" {
  now=$(date +%s)
  mk_human "$(( now - 2000 ))" "start the wave"
  mk_stophook "$(( now - 5 ))"; mk_toolres "$(( now - 3 ))"
  age="$(ce_last_interactive_age "$TX")"
  [ -n "$age" ] && [ "$age" -ge 1990 ]
}
@test "recency: an operator slash-command (<command-name>) COUNTS as presence" {
  now=$(date +%s)
  mk_cmd "$(( now - 20 ))"; mk_toolres "$(( now - 5 ))"
  age="$(ce_last_interactive_age "$TX")"
  [ -n "$age" ] && [ "$age" -le 60 ]
}
@test "recency: peer-injected text (cc-notify types a plain turn) COUNTS — 2-way coordination holds" {
  now=$(date +%s)
  mk_human "$(( now - 40 ))" "cc-notify from worker A2: gate green, landing next"
  age="$(ce_last_interactive_age "$TX")"
  [ -n "$age" ] && [ "$age" -le 70 ]
}
@test "recency: missing/empty transcript and no-timestamp lines → empty (never errors)" {
  [ -z "$(ce_last_interactive_age "$T/absent.jsonl")" ]
  : > "$TX"; [ -z "$(ce_last_interactive_age "$TX")" ]
  printf '{"type":"user","message":{"role":"user","content":"hello"}}\n' >> "$TX"   # no timestamp
  printf 'garbage not json\n' >> "$TX"
  [ -z "$(ce_last_interactive_age "$TX")" ]
}
@test "recency: CC_CE_AUTO_RX override extends the exclusion set" {
  now=$(date +%s)
  export CC_CE_AUTO_RX='^NOISE:'
  mk_human "$(( now - 10 ))" "NOISE: synthetic chatter"
  [ -z "$(ce_last_interactive_age "$TX")" ]
}
