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

# ── TEST CONTAINMENT (row 5e4ce121b64a residual (b)) ─────────────────────────────────────────────
# Both durable writers prefer CLAUDE_CONFIG_DIR over $HOME so a fixtured suite stays in its sandbox.
# That never covered a suite fixturing NEITHER: measured 2026-08-18, tests/boundary-handoff.bats
# appended 29 rows to the operator's REAL ~/.claude/autonomy/recycle-events.jsonl on every run, and
# 2,907 of that store's 3,743 rows are fixture sids — the durable window/fill denominator
# cc-ctx-audit reads is ~78% test exhaust. These cases pin the invariant at the lib, because only 61
# of 512 suites scope a config root and per-suite fixes cannot hold the line.
# The canary HOME must be genuinely OUTSIDE BATS_TEST_TMPDIR — that is the whole leak. A canary
# nested INSIDE the tmpdir is already contained, so it passes through by design and asserting a
# redirect on it tests nothing (this suite's first draft made exactly that mistake and red for it).
outside_home() { mktemp -d "${TMPDIR:-/tmp}/ce-canary-XXXXXX"; }

@test "containment: with NO seam set, the recycle store lands in the tmpdir, never the real \$HOME" {
  OUT="$(outside_home)"; HOME="$OUT"
  unset CC_RECYCLE_EVENTS CLAUDE_CONFIG_DIR
  now=$(date +%s); mk_tel "$now" 42
  ce_record_recycle "$TEL" executed 42 test manual
  [ -f "$BATS_TEST_TMPDIR/recycle-events.jsonl" ]
  [ ! -e "$OUT/.claude/autonomy/recycle-events.jsonl" ]
  rm -rf "$OUT"
}
@test "containment: with NO seam set, the IDL lands in the tmpdir, never the real \$HOME" {
  OUT="$(outside_home)"; HOME="$OUT"
  unset CC_CE_IDL CC_IDL CLAUDE_CONFIG_DIR
  now=$(date +%s); mk_tel "$now" 42
  ce_log_drop "$TEL" 80 40 100000 1000000
  [ -f "$BATS_TEST_TMPDIR/idl.jsonl" ]
  [ ! -e "$OUT/.claude/autonomy/idl.jsonl" ]
  rm -rf "$OUT"
}
# CONTROL — containment must not RELOCATE a suite that already scoped itself, or every existing
# fixture-isolation assertion silently changes meaning. An explicit seam inside the tmpdir is honored
# verbatim, at its own path, not rewritten to the default basename.
@test "CONTROL: an explicit in-tmpdir seam is passed through untouched, not redirected" {
  export CC_RECYCLE_EVENTS="$BATS_TEST_TMPDIR/nested/mine.jsonl"
  now=$(date +%s); mk_tel "$now" 42
  ce_record_recycle "$TEL" executed 42 test manual
  [ -f "$BATS_TEST_TMPDIR/nested/mine.jsonl" ]
  [ ! -e "$BATS_TEST_TMPDIR/recycle-events.jsonl" ]
}
# CONTROL — outside bats the helper is IDENTITY. Production must never be redirected; a containment
# that fired in production would silently move the operator's durable store to a stale path.
@test "CONTROL: outside bats (no BATS_TEST_TMPDIR) the path is returned unchanged" {
  run env -u BATS_TEST_TMPDIR bash -c \
    ". '$REPO/hooks/lib/context-econ.sh'; _ce_contain /Users/x/.claude/autonomy/recycle-events.jsonl"
  [ "$status" -eq 0 ]
  [ "$output" = "/Users/x/.claude/autonomy/recycle-events.jsonl" ]
}

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
@test "recency: a PARSEABLE transcript with no usable turn → empty (never errors)" {
  # a well-formed record with no timestamp + one garbage line: the file PARSES, so the answer is the
  # FACT "" (nobody typed a usable turn) — not the unreadable verdict below.
  printf '{"type":"user","message":{"role":"user","content":"hello"}}\n' >> "$TX"   # no timestamp
  printf 'garbage not json\n' >> "$TX"
  run ce_last_interactive_age "$TX"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── the EMPTY-ANSWER SPLIT (2026-07-25) ───────────────────────────────────────────────────────────
# "" used to mean any of {no operator turn, jq missing, unreadable/corrupt transcript}, and both reap
# consumers (cc-reaper's Gap-2 leg, reap-guard R-d) read that one "" as "no adoption" → fall through
# to REAP. The contract is now three-valued: "" = a FACT (parsed, nobody typed) · "unreadable" (rc 2)
# = ABSENCE OF EVIDENCE, which a destructive consumer must treat as DEFER.
@test "split: a MISSING transcript path → 'unreadable' (rc 2), never '' " {
  run ce_last_interactive_age "$T/absent.jsonl"
  [ "$status" -eq 2 ]; [ "$output" = "unreadable" ]
}
@test "split: an EMPTY transcript → 'unreadable' (rc 2) — zero records proves nothing about presence" {
  : > "$TX"
  run ce_last_interactive_age "$TX"
  [ "$status" -eq 2 ]; [ "$output" = "unreadable" ]
}
@test "split: a CORRUPT transcript (not one well-formed record) → 'unreadable' (rc 2)" {
  printf 'not json at all\nhalf a line {"type":"user"\n\001\002 binary junk\n' > "$TX"
  run ce_last_interactive_age "$TX"
  [ "$status" -eq 2 ]; [ "$output" = "unreadable" ]
}
@test "split: no jq → 'unreadable' (rc 2), not the silent '' the reap legs read as no-adoption" {
  now=$(date +%s); mk_human "$(( now - 30 ))" "operator here"
  run env PATH=/var/empty /bin/bash -c '. "'"$REPO"'/hooks/lib/context-econ.sh"; ce_last_interactive_age "'"$TX"'"'
  [ "$status" -eq 2 ]; [ "$output" = "unreadable" ]
}
@test "split: THE DISCRIMINATOR PAIR — corrupt-only ⇒ unreadable vs corrupt+one good record ⇒ ''" {
  printf 'garbage not json\n' > "$TX"
  run ce_last_interactive_age "$TX"; [ "$output" = "unreadable" ]
  printf '{"type":"assistant","message":{"role":"assistant","content":[]},"timestamp":"x"}\n' >> "$TX"
  run ce_last_interactive_age "$TX"; [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "split: the visibility probe reaches PAST the tail window (a big file with a corrupt tail)" {
  # tail window deliberately tiny: the tail is pure garbage, but the file is larger than the window and
  # its head holds a well-formed record ⇒ the file IS readable ⇒ "" (fact), not 'unreadable'.
  printf '{"type":"assistant","message":{"role":"assistant","content":[]},"timestamp":"x"}\n' > "$TX"
  head -c 400 /dev/zero | tr '\0' 'x' >> "$TX"
  export CC_CE_TAIL_BYTES=64
  run ce_last_interactive_age "$TX"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "recency: CC_CE_AUTO_RX override extends the exclusion set" {
  now=$(date +%s)
  export CC_CE_AUTO_RX='^NOISE:'
  mk_human "$(( now - 10 ))" "NOISE: synthetic chatter"
  [ -z "$(ce_last_interactive_age "$TX")" ]
}

# ── ce_size — THE SIZE AXIS (2026-07-29, K02) ─────────────────────────────────────────────────────
# The axis used_pct is blind to: a compacted session resets its fill but not its transcript or its
# process footprint. Both metrics report 0 for UNKNOWN, never for "safe and small" — consumers gate on
# `>=`, so an unknown degrades to the pre-size behavior.
mk_ps() { # $1=rss-column-text $2=comm → a `ps` stub on CC_CE_PS
  local p="$BATS_TEST_TMPDIR/ps-${BATS_TEST_NUMBER}"
  printf '#!/bin/bash\nprintf "%%s %%s\\n" "%s" "%s"\n' "$1" "$2" > "$p"; chmod +x "$p"; printf '%s' "$p"; }
mk_tel_pid() { # $1=pid → telemetry carrying that pid
  local p="$BATS_TEST_TMPDIR/tel-${BATS_TEST_NUMBER}.json"
  printf '{"ts":1,"pid":%s}' "$1" > "$p"; printf '%s' "$p"; }

@test "size: transcript bytes are read exactly; a missing/empty path is 0 = UNKNOWN not small" {
  printf '0123456789' > "$T/tx.jsonl"
  [ "$(ce_size "$T/tx.jsonl" '')" = "10 0" ]
  [ "$(ce_size "$T/absent.jsonl" '')" = "0 0" ]
  [ "$(ce_size '' '')" = "0 0" ]
}
@test "size: RSS resolves via the telemetry pid when the comm still looks like claude" {
  export CC_CE_PS="$(mk_ps 700000 /usr/local/bin/claude)"
  [ "$(ce_size '' "$(mk_tel_pid 4242)")" = "0 700000" ]
}
@test "size: RIGHT-ALIGNED ps output parses — the width must never decide whether the axis works" {
  # `ps -o rss=` pads to a varying column width, so a small RSS arrives as "  1984 bash". A
  # ${line%%' '*} parse yields EMPTY there ⇒ rss=0 ⇒ the axis silently never fires, while a wide
  # value spot-checks fine. Both widths must give the number.
  export CC_CE_PS="$(mk_ps '    1984' /usr/local/bin/claude)"
  [ "$(ce_size '' "$(mk_tel_pid 4242)")" = "0 1984" ]
  export CC_CE_PS="$(mk_ps 1048576 /usr/local/bin/claude)"
  [ "$(ce_size '' "$(mk_tel_pid 4242)")" = "0 1048576" ]
}
@test "size: pid-recycle guard — a live pid whose comm is NOT claude reports 0 (unknown), not a stranger's RSS" {
  # Telemetry files outlive their sessions and pids recycle, so charging the pid blind would read an
  # unrelated process's footprint as this session's.
  export CC_CE_PS="$(mk_ps 900000 /bin/loginwindow)"
  [ "$(ce_size '' "$(mk_tel_pid 4242)")" = "0 0" ]
  export CC_CE_RSS_COMM_RX='loginwindow'          # seam works in the other direction too
  [ "$(ce_size '' "$(mk_tel_pid 4242)")" = "0 900000" ]
}
@test "size: no pid / non-numeric pid / dead pid → rss 0, never an error" {
  export CC_CE_PS="$(mk_ps 700000 /usr/local/bin/claude)"
  printf '{"ts":1}' > "$T/nopid.json";            [ "$(ce_size '' "$T/nopid.json")" = "0 0" ]
  printf '{"ts":1,"pid":"abc"}' > "$T/badpid.json"; [ "$(ce_size '' "$T/badpid.json")" = "0 0" ]
  printf '{"ts":1,"pid":0}' > "$T/zeropid.json";  [ "$(ce_size '' "$T/zeropid.json")" = "0 0" ]
  export CC_CE_PS=/nonexistent-ps                  # ps itself unavailable
  [ "$(ce_size '' "$(mk_tel_pid 4242)")" = "0 0" ]
}
@test "size: input_tokens is NOT a size proxy — col-3 tracks used_pct, transcript bytes do not" {
  # The premise this axis had to replace (audit roadmap called col-3 "a ready size proxy"; measured
  # |input_tokens/window*100 - used_pct| <= 0.5pt across 67 live files). Encoded as a test so the
  # refutation is executable: a COMPACTED session's col-3 falls while its transcript keeps growing.
  local big="$T/big.jsonl"
  mk_tel 100 80 800000 ; ce_sample "$TEL"                       # full window, big col-3
  printf 'x%.0s' $(seq 1 5000) > "$big"                         # 5000-byte transcript
  before="$(ce_size "$big" '')"
  mk_tel 200 5 50000 ; ce_sample "$TEL"                         # compaction: fill AND col-3 collapse
  printf 'y%.0s' $(seq 1 5000) >> "$big"                        # a transcript only ever GROWS
  after="$(ce_size "$big" '')"
  [ "$before" = "5000 0" ] || false
  [ "$after" = "10000 0" ] || false                             # size axis rose while col-3 fell
  tail -1 "$HIST" | grep -q ' 5 50000$'                         # col-3 really did collapse
}
