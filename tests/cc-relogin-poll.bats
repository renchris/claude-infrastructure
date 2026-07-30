#!/usr/bin/env bats
# cc-relogin-poll — the cadence layer: catch the T−7d login-renewal window, escalate LOUD at T−48h.
# Fully hermetic: `claude-accounts` and `cc-relogin` are file-driven stubs in BATS_TEST_TMPDIR, the
# clock is fixed (CC_RELOGIN_POLL_NOW), and the board/log/state all live in the tmpdir. NOTHING here
# authenticates, mutates an account, or loads a LaunchAgent — the real binaries are never invoked.

setup() {
  # HERMETIC $HOME (scripts/test-hermeticity-lint.sh — the ratchet that binds every NEW suite):
  # the subject resolves its own state under ~, so unfixtured this suite reads/writes the
  # operator's LIVE layer. Everything this suite asserts is already redirected elsewhere.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  P="$REPO/bin/cc-relogin-poll"
  D="$BATS_TEST_TMPDIR"
  export CC_RELOGIN_POLL_LOG="$D/poll.log"
  export CC_RELOGIN_POLL_STATE_DIR="$D/state"
  export CC_REAPER_IDL="$D/idl.jsonl"
  export CC_RELOGIN_POLL_ACCOUNTS_BIN="$D/claude-accounts"
  export CC_RELOGIN_POLL_RELOGIN_BIN="$D/cc-relogin"
  export CC_RELOGIN_POLL_TIMEOUT_S=10
  NOW=1784544000                       # fixed clock — every deadline below is relative to this
  export CC_RELOGIN_POLL_NOW="$NOW"
  CALLS="$D/relogin.calls"
  : > "$D/fixture"

  # fake claude-accounts — every surface is file-driven, so each test declares its own reality.
  # The no-flag fallthrough mimics `main`: an UNKNOWN flag prints the human table and exits 0.
  cat > "$D/claude-accounts" <<'STUB'
#!/usr/bin/env bash
D="$(dirname "$0")"
case "${1:-}" in
  -h|--help)
    echo "usage: claude-accounts [--json] [--fresh] [--relogin-info NAME]"
    [ -f "$D/ls_supported" ] && echo "  claude-accounts --login-status      per-account login deadline"
    # --window-h is advertised separately: the poller probes for it independently, and a build
    # with --login-status but WITHOUT --window-h is the real deployed shape it must degrade on.
    [ -f "$D/wh_supported" ] && echo "      --window-h N   override login_warn_h for this call"
    exit 0 ;;
  --login-status)
    # Record the ARGV so a test can prove the poller asked for its OWN window rather than
    # accepting this surface's default filter.
    printf '%s\n' "$*" >> "$D/ls.argv"
    if [ -f "$D/wh_supported" ]; then
      # Behave like the real flag: only rows inside the REQUESTED window are emitted. Without
      # this the fixture would answer a 168h question with a 72h-filtered table and the whole
      # defect under test would be invisible again.
      wh=72; [ "${2:-}" = "--window-h" ] && wh="${3:-72}"
      [ -f "$D/ls.tsv" ] && awk -F'\t' -v lim="$wh" '{ h=$5
          if (h ~ /^now$/)     { v = 0 }
          else if (h ~ /m$/)   { v = (h+0)/60 }
          else if (h ~ /d\+$/) { v = 99999 }
          else if (h ~ /d$/)   { v = (h+0)*24 }
          else                 { v = h+0 }
          if (v <= lim) print }' "$D/ls.tsv"
      exit "$(cat "$D/ls.rc" 2>/dev/null || echo 0)"
    fi
    # No --window-h on this build ⇒ the REAL surface still filters, at its own login_warn_h of
    # 72h. Emitting the whole table here would model a build that does not exist and would hide
    # the cap the poller has to degrade on.
    [ -f "$D/ls.tsv" ] && awk -F'\t' '{ h=$5
        if (h ~ /^now$/)     { v = 0 }
        else if (h ~ /m$/)   { v = (h+0)/60 }
        else if (h ~ /d\+$/) { v = 99999 }
        else if (h ~ /d$/)   { v = (h+0)*24 }
        else                 { v = h+0 }
        if (v <= 72) print }' "$D/ls.tsv"
    exit "$(cat "$D/ls.rc" 2>/dev/null || echo 0)" ;;
esac
printf '%s\n' "$*" >> "$D/accounts.argv"
if [ -f "$D/fresh.json" ] && printf '%s\n' "$@" | grep -qx -- --fresh; then cat "$D/fresh.json"; exit 0; fi
if [ -f "$D/cached.json" ]; then cat "$D/cached.json"; exit 0; fi
echo "ACCT   K   AUTH"
exit 0
STUB
  chmod +x "$D/claude-accounts"

  cat > "$D/cc-relogin" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CALLS"
echo "cc-relogin stub invoked: \$*"
echo "cc-relogin stub stderr line" >&2
exit "\$(cat "$D/relogin.rc" 2>/dev/null || echo 0)"
STUB
  chmod +x "$D/cc-relogin"
}

iso_in_h() { local s=$((NOW + $1 * 3600)); date -u -r "$s" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$s" +%Y-%m-%dT%H:%M:%SZ; }
mk() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$D/fixture"; }   # <acct> <hours-to-deadline> <k>

# ── FIXTURE/PRODUCER PARITY (2026-07-30, ACCOUNT_ROUTING_V2 M2) ────────────────────────────────
# The --login-status fixture below used to emit an ISO stamp in `when` and a bare integer in
# `hours`. The REAL claude-accounts emits neither: `when` is _fmt_when() — 'Sun 13:21' inside a
# week, 'Sat Aug 08' beyond it, never parseable as ISO — and `hours` is fmt_h() — '30m' / '41.5h' /
# '3.7d' / 'now' / '99d+'. So every ls-leg test drove a surface that does not exist, iso_epoch()
# always succeeded, and hours_secs() — the function that actually derives the deadline in
# production — was NEVER EXERCISED. That is what let a 24x deadline error live in it: '3.7d' parsed
# as 3 HOURS, which made a T-90h account escalate at T-3h. A fixture is a contract CLAIM; it has to
# be the producer's LITERAL emission.
fmt_h_like() { # mirror of claude-accounts fmt_h — the exact vocabulary the poller must parse
  awk -v h="$1" 'BEGIN{
    if (h < 0)      { print "now" }
    else if (h < 1) { printf "%dm", int(h*60) }
    else if (h < 48){ printf "%.1fh", h }
    else if (h >= 2400) { print "99d+" }
    else            { printf "%.1fd", h/24 }
  }'
}
fmt_when_like() { # mirror of claude-accounts _fmt_when — a human LOCAL string, never ISO
  local s=$((NOW + $1 * 3600))
  date -r "$s" '+%a %H:%M' 2>/dev/null || date -d "@$s" '+%a %H:%M'
}

# render the fixture into ONE detection surface: ls | json | none
build() {
  local a h k at st
  : > "$D/rows.login"; : > "$D/rows.plain"; : > "$D/ls.tsv"
  rm -f "$D/ls_supported" "$D/wh_supported" "$D/fresh.json" "$D/ls.argv"
  while IFS=$'\t' read -r a h k; do
    [ -n "$a" ] || continue
    at="$(iso_in_h "$h")"; st=EXPIRING; [ "$h" -le 0 ] && st=REQUIRED
    jq -nc --arg a "$a" --argjson k "$k" --arg at "$at" \
      '{acct:$a,k:$k,launcher:("claude-"+$a),auth:"ok",login_expires_at:$at,login_expired:false,login_fixable:true}' >> "$D/rows.login"
    jq -nc --arg a "$a" --argjson k "$k" '{acct:$a,k:$k,launcher:("claude-"+$a),auth:"ok"}' >> "$D/rows.plain"
    # PRODUCER-LITERAL, not ISO+integer: see the fixture/producer-parity note above.
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$a" "$st" "token-expiry" "$(fmt_when_like "$h")" "$(fmt_h_like "$h")" "claude-$a" >> "$D/ls.tsv"
  done < "$D/fixture"
  jq -sc '{window:{},cached:true,rows:.}' "$D/rows.plain" > "$D/cached.json"   # k only — no login_* fields
  case "$1" in
    # `ls` = the LANDED shape: --login-status AND --window-h, so the poller can ask for its own
    # T-trigger window. `ls-narrow` = the shape actually deployed while the checkout lags —
    # --login-status only, still filtered at claude-accounts' 72h login_warn_h.
    ls)        touch "$D/ls_supported" "$D/wh_supported" ;;
    ls-narrow) touch "$D/ls_supported" ;;
    json) jq -sc '{window:{},cached:false,rows:.}' "$D/rows.login" > "$D/fresh.json" ;;
    none) : ;;
  esac
}
ncalls() { [ -f "$CALLS" ] && grep -c . "$CALLS" || echo 0; }
json() { printf '%s\n' "$output" | tail -1; }   # bats merges stderr into $output; the JSON is last
nrows()  { [ -f "$CC_REAPER_IDL" ] && jq -rs '[.[]|select(.kind=="relogin-blocked")]|length' "$CC_REAPER_IDL" || echo 0; }
attempts() { jq -r '.attempts' "$CC_RELOGIN_POLL_STATE_DIR/relogin-poll-$1.json"; }

# ── trigger math ────────────────────────────────────────────────────────────────────────────

@test "outside the T-7d window → no-op, invokes nothing, exit 0" {
  mk next3 240 0        # 10 days out
  build json
  run "$P" --json
  [ "$status" -eq 0 ]
  [ "$(ncalls)" -eq 0 ]
  json | jq -e '.action=="none" and .candidates==0' >/dev/null
}

@test "inside the T-7d window → invokes cc-relogin for that account" {
  mk next3 100 0        # ~4.2 days out
  build json
  run "$P"
  [ "$status" -eq 0 ]
  [ "$(ncalls)" -eq 1 ]
  grep -q '^next3$' "$CALLS"
}

@test "the trigger is T-7d, NOT the 72h warn — a 5-day-out deadline already attempts" {
  mk next3 120 0        # 5 days: inside 7d, well outside any 72h warn
  build json
  run "$P" --json
  [ "$status" -eq 0 ]
  [ "$(ncalls)" -eq 1 ]
  json | jq -e '.hours_left==120 and .action=="invoked"' >/dev/null
}

@test "--trigger-days narrows the window (3d → a 5-day-out deadline is not yet due)" {
  mk next3 120 0
  build json
  run "$P" --trigger-days 3 --json
  [ "$status" -eq 0 ]
  [ "$(ncalls)" -eq 0 ]
  json | jq -e '.candidates==0' >/dev/null
}

@test "a deadline that already moved is an idempotent no-op on the next tick" {
  mk next3 100 0
  build json
  run "$P"; [ "$status" -eq 0 ]; [ "$(ncalls)" -eq 1 ]
  : > "$D/fixture"; mk next3 720 0     # renewed: 30 days out
  build json
  run "$P" --json
  [ "$status" -eq 0 ]
  [ "$(ncalls)" -eq 1 ]                # still just the first tick's call
  json | jq -e '.action=="none"' >/dev/null
}

# ── escalation (T-48h) ──────────────────────────────────────────────────────────────────────

@test "T-48h with no window caught → exactly one class-C row + exit 5" {
  mk next3 40 0
  build json
  run "$P"
  [ "$status" -eq 5 ]
  [ "$(nrows)" -eq 1 ]
  run jq -rs '.[0]|[.kind,.acct,.recover_cmd]|@tsv' "$CC_REAPER_IDL"
  [ "$output" = "$(printf 'relogin-blocked\tnext3\tcc-relogin next3')" ]
}

@test "the class-C row carries an exact runnable recover_cmd, not a paraphrase" {
  mk next2 12 0
  build json
  run "$P"; [ "$status" -eq 5 ]
  cmd="$(jq -rs '.[0].recover_cmd' "$CC_REAPER_IDL")"
  # `[ ]`, NOT `[[ ]]`: a non-final `[[ ]]` does not fail a bats test (verified on bats 1.13 —
  # bash skips the ERR trap for it, exactly like a `!`-inverted pipeline), so it would be a second
  # silent dead-assertion class. Only `[ ]` and plain commands are actually enforced here.
  [ "$cmd" = "cc-relogin next2" ]                          # one line, argv-shaped, names the account
  [ "$(printf '%s' "$cmd" | grep -c .)" -eq 1 ]
  # No prose, no placeholder. NEVER write this as a bare `! grep …`: POSIX exempts a `!`-inverted
  # pipeline from errexit, so a non-final one is a DEAD assertion that can never fail the test.
  # `run` + an explicit status check is the only form bats actually enforces.
  run grep -qiE 'run |please|<|>|\.\.\.' <<< "$cmd"
  [ "$status" -ne 0 ]
  jq -es '.[0]|has("deadline") and has("reason") and .actor=="cc-relogin-poll"' "$CC_REAPER_IDL" >/dev/null
}

@test "escalation is deduped — one row per (acct, deadline), not one per tick" {
  mk next3 40 0
  build json
  run "$P"; [ "$status" -eq 5 ]
  run "$P"; [ "$status" -eq 5 ]        # still ESCALATED state…
  run "$P"; [ "$status" -eq 5 ]
  [ "$(nrows)" -eq 1 ]                 # …but the operator is paged exactly once
}

@test "a NEW deadline after escalation re-arms the page (dedup key is acct+deadline)" {
  mk next3 40 0
  build json
  run "$P"; [ "$status" -eq 5 ]; [ "$(nrows)" -eq 1 ]
  : > "$D/fixture"; mk next3 20 0      # deadline moved closer (a re-issued, still-unfixed cliff)
  build json
  run "$P"; [ "$status" -eq 5 ]
  [ "$(nrows)" -eq 2 ]
}

@test "escalation fires BEFORE the attempt, so a failing child cannot swallow it" {
  mk next3 40 0
  build json
  echo 1 > "$D/relogin.rc"             # every attempt fails
  run "$P"
  [ "$status" -eq 5 ]
  [ "$(nrows)" -eq 1 ]                 # row raised despite the failure
  [ "$(ncalls)" -eq 1 ]                # and the attempt still happened
  # ORDER is the invariant, not just co-occurrence: a hung/crashing attempt must not be able to
  # preempt the page. Assert the ESCALATED line precedes the ATTEMPT line in the log.
  esc="$(grep -n 'ESCALATED next3' "$CC_RELOGIN_POLL_LOG" | head -1 | cut -d: -f1)"
  att="$(grep -n 'ATTEMPT #1 next3' "$CC_RELOGIN_POLL_LOG" | head -1 | cut -d: -f1)"
  [ -n "$esc" ] && [ -n "$att" ] && [ "$esc" -lt "$att" ]
}

@test "--escalate-hours tunes the loud-before-the-deadline point" {
  mk next3 100 0
  build json
  run "$P" --escalate-hours 120        # 100h left < 120h → escalate
  [ "$status" -eq 5 ]
  [ "$(nrows)" -eq 1 ]
}

# ── attempts, not successes ─────────────────────────────────────────────────────────────────

@test "attempts are counted on FAILURE (a success-only counter never trips)" {
  mk next3 100 0
  build json
  echo 1 > "$D/relogin.rc"
  run "$P"; [ "$status" -eq 0 ]        # a child failure is data, not a poller error
  run "$P"; [ "$status" -eq 0 ]
  run "$P"; [ "$status" -eq 0 ]
  [ "$(attempts next3)" -eq 3 ]
  [ "$(ncalls)" -eq 3 ]
}

@test "the attempt cap escalates early — the bound covers the failure mode it bounds" {
  mk next3 100 0                       # far outside the T-48h escalate window
  build json
  echo 1 > "$D/relogin.rc"
  export CC_RELOGIN_POLL_MAX_ATTEMPTS=2
  run "$P"; [ "$status" -eq 0 ]
  run "$P"; [ "$status" -eq 0 ]
  run "$P"; [ "$status" -eq 5 ]        # 2 failed attempts against this deadline → loud
  [ "$(nrows)" -eq 1 ]
  jq -rs '.[0].reason' "$CC_REAPER_IDL" | grep -q 'attempt'
}

@test "child stdout+stderr land in the poll log" {
  mk next3 100 0
  build json
  run "$P"
  grep -q 'cc-relogin stub stderr line' "$CC_RELOGIN_POLL_LOG"
  grep -q 'ATTEMPT #1 next3' "$CC_RELOGIN_POLL_LOG"
}

# ── the lock invariant + the k pre-filter ───────────────────────────────────────────────────

@test "every claude-accounts read passes --no-heal (detection must not rotate a token)" {
  # A bare `--fresh --json` may run the headless heal (`claude auth login`) — a credential
  # mutation that ALSO takes /tmp/claude-accounts-heal-<acct>.lock, the one lock this poller is
  # forbidden to hold. Detection is read-only or it is a lock-order inversion waiting to happen.
  mk next3 100 0
  build json
  run "$P"
  [ -f "$D/accounts.argv" ]
  while read -r line; do
    case "$line" in *--no-heal*) ;; *) echo "heal-capable read: [$line]"; return 1 ;; esac
  done < <(grep -e '--json' "$D/accounts.argv")
}

@test "the poller NEVER takes the heal lock (it would deadlock its own child)" {
  run bash -c "grep -v '^[[:space:]]*#' '$P' | grep -c 'claude-accounts-heal\|flock'"
  [ "$output" -eq 0 ]
}

@test "k>0 skips the doomed invocation and does NOT burn an attempt" {
  mk next3 100 3
  build json
  run "$P" --json
  [ "$status" -eq 0 ]
  [ "$(ncalls)" -eq 0 ]
  [ "$(attempts next3)" -eq 0 ]
  # .k is asserted exactly: an empty field sliding the launcher into k would also "skip", and
  # that tautology is precisely how the field-collapse bug hid (see SEP in the poller).
  json | jq -e '.action=="skipped-busy" and .k=="3"' >/dev/null
}

@test "an empty field never shifts the parse — k==0 rows are still attempted" {
  build none      # hand-written rows with an ABSENT login_expires_h → an empty middle field
  jq -nc '{window:{},cached:false,rows:[{acct:"next3",k:0,launcher:"claude-next3",
           login_expires_at:"'"$(iso_in_h 100)"'",login_expired:false,login_fixable:true}]}' > "$D/fresh.json"
  run "$P" --json
  [ "$status" -eq 0 ]
  json | jq -e '.k=="0" and .action=="invoked"' >/dev/null
  [ "$(ncalls)" -eq 1 ]
}

# ── §2 version tolerance: the detection ladder ──────────────────────────────────────────────

@test "ladder 1 — --login-status is used when the binary advertises it" {
  mk next3 100 0
  build ls
  run "$P" --json
  [ "$status" -eq 0 ]
  json | jq -e '.detection=="login-status" and .action=="invoked"' >/dev/null
  [ "$(ncalls)" -eq 1 ]
}

@test "ladder 1 — k for the pre-filter is resolved even though the TSV has no k column" {
  mk next3 100 4
  build ls
  run "$P" --json
  [ "$status" -eq 0 ]
  json | jq -e '.detection=="login-status" and .k=="4" and .action=="skipped-busy"' >/dev/null
}

@test "ladder 1 — an UNREADABLE k still attempts (a broken pre-filter is never a silent skip)" {
  mk next3 100 0
  build ls
  rm -f "$D/cached.json"                # the k lookup now returns junk, not a number
  run "$P" --json
  [ "$status" -eq 0 ]
  [ "$(ncalls)" -eq 1 ]                 # attempted anyway — cc-relogin's own gate is authoritative
  json | jq -e '.action=="invoked"' >/dev/null
}

@test "ladder 2 — an unadvertised flag degrades to the --fresh --json login_* fields" {
  mk next3 100 0
  build json                            # no ls_supported → --login-status is never called
  run "$P" --json
  [ "$status" -eq 0 ]
  json | jq -e '.detection=="json-fields"' >/dev/null
}

@test "ladder 2 — login_expires_h is honored when login_expires_at is absent" {
  build none                            # base fixtures, then hand-write an h-only row
  jq -nc '{window:{},cached:false,rows:[{acct:"next4",k:0,launcher:"claude-next4",login_expires_h:100,login_expired:false}]}' > "$D/fresh.json"
  run "$P" --json
  [ "$status" -eq 0 ]
  json | jq -e '.detection=="json-fields" and .acct=="next4" and .hours_left==100' >/dev/null
  [ "$(ncalls)" -eq 1 ]
}

@test "ladder 3 — NO surface → exit 3 DETECTION-UNAVAILABLE, never a silent 'nothing to do'" {
  mk next3 100 0
  build none                            # `main` reality: no --login-status, no login_* fields
  run "$P"
  [ "$status" -eq 3 ]
  [ "$(ncalls)" -eq 0 ]
  echo "$output" | grep -q 'DETECTION-UNAVAILABLE'
  grep -q 'DETECTION-UNAVAILABLE' "$CC_RELOGIN_POLL_LOG"
  grep -q -- '--login-status' "$CC_RELOGIN_POLL_LOG"     # the log NAMES the missing surface
}

@test "ladder 3 — the exit-0 human table of an unknown flag is not mistaken for 'all clear'" {
  mk next3 40 0                         # inside the escalate window — a silent miss would be severe
  build none
  run "$P" --json
  [ "$status" -eq 3 ]                   # NOT 0
  [ "$(nrows)" -eq 0 ]
  json | jq -e '.detection=="unavailable" and .exit==3' >/dev/null
}

# ── staggering ──────────────────────────────────────────────────────────────────────────────

@test "at most ONE account per tick, nearest deadline first" {
  mk next  100 0
  mk next2 60  0
  mk next4 80  0
  build json
  run "$P" --json
  [ "$status" -eq 0 ]
  [ "$(ncalls)" -eq 1 ]
  grep -q '^next2$' "$CALLS"            # 60h is nearest
  json | jq -e '.acct=="next2" and .candidates==3' >/dev/null
}

@test "successive ticks walk the queue one account at a time" {
  mk next  100 0
  mk next2 60  0
  build json
  run "$P"; grep -q '^next2$' "$CALLS"
  : > "$D/fixture"; mk next 100 0; mk next2 720 0    # next2 renewed → next is now nearest
  build json
  run "$P"
  [ "$(ncalls)" -eq 2 ]
  grep -q '^next$' "$CALLS"
}

# ── --dry-run ───────────────────────────────────────────────────────────────────────────────

@test "--dry-run invokes nothing, raises nothing, writes no state — and exits 0" {
  mk next3 40 0                         # inside BOTH the trigger and the escalate window
  build json
  run "$P" --dry-run --json
  [ "$status" -eq 0 ]
  [ "$(ncalls)" -eq 0 ]
  [ ! -f "$CC_REAPER_IDL" ]
  [ ! -f "$CC_RELOGIN_POLL_STATE_DIR/relogin-poll-next3.json" ]
  json | jq -e '.dry_run==true and .action=="dry-run" and .escalated==true and .exit==0' >/dev/null
}

# ── CLI surface + exit-code reachability ────────────────────────────────────────────────────

@test "--once is accepted and means exactly one tick" {
  mk next3 100 0
  build json
  run "$P" --once
  [ "$status" -eq 0 ]
  [ "$(ncalls)" -eq 1 ]
}

@test "unknown arg → exit 1" {
  run "$P" --wat
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'unknown arg'
}

@test "non-numeric --trigger-days / --escalate-hours → exit 1" {
  run "$P" --trigger-days seven; [ "$status" -eq 1 ]
  run "$P" --escalate-hours ""; [ "$status" -eq 1 ]
}

@test "-h prints usage and exits 0 without touching anything" {
  run "$P" -h
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'cc-relogin-poll \[--json\]'
  echo "$output" | grep -q 'DETECTION-UNAVAILABLE'
  [ ! -f "$CC_RELOGIN_POLL_LOG" ]
}

@test "--json emits valid JSON on every reachable exit code (0, 3, 5)" {
  mk next3 240 0; build json
  run "$P" --json; [ "$status" -eq 0 ]; json | jq -e . >/dev/null
  : > "$D/fixture"; mk next3 40 0; build json
  run "$P" --json; [ "$status" -eq 5 ]; json | jq -e '.escalated==true and .exit==5' >/dev/null
  : > "$D/fixture"; mk next3 40 0; build none
  run "$P" --json; [ "$status" -eq 3 ]; json | jq -e '.exit==3' >/dev/null
}

# ── the staged LaunchAgent ──────────────────────────────────────────────────────────────────

@test "plist is valid, staged-not-loaded, and carries the PATH export + RunAtLoad false" {
  PL="$REPO/launchd/staged/com.claude.relogin.plist"
  plutil -lint "$PL" >/dev/null
  grep -q 'export PATH="$HOME/.claude/bin:$PATH"' "$PL"     # zsh -lc does NOT source .zshrc
  plutil -extract RunAtLoad raw "$PL" | grep -qx false
  [ "$(plutil -extract StartInterval raw "$PL")" = 3600 ]
  [ "$(plutil -extract ProcessType raw "$PL")" = Background ]
  plutil -extract StandardOutPath raw "$PL" | grep -q '^/Users/chrisren/.claude/logs/'
  plutil -extract StandardErrorPath raw "$PL" | grep -q '^/Users/chrisren/.claude/logs/'
  grep -q 'OPERATOR ACTIVATION' "$PL"                       # C10 step named in the header comment
}

@test "the poller and the plist body never invoke launchctl (staging is not activation)" {
  # Asserted against the CODE, not against ~/Library/LaunchAgents: once the operator performs the
  # C10 activation that file legitimately exists, so a file-absence check would be a future
  # false alarm. The durable invariant is that no code path of ours loads the job.
  run bash -c "grep -v '^[[:space:]]*#' '$P' | grep -c launchctl"
  [ "$output" -eq 0 ]
  # the plist names launchctl ONLY inside its leading XML comment (the operator runbook); the
  # executable body after the comment close must be free of it
  run bash -c "sed -n '/-->/,\$p' '$REPO/launchd/staged/com.claude.relogin.plist' | grep -c launchctl"
  [ "$output" -eq 0 ]
}

# ── M2: the detection window must match this poller's OWN policy (ACCOUNT_ROUTING_V2) ───────────
# `--login-status` is a pre-FILTERED view gated at claude-accounts' login_warn_h (72h) — a HUMAN
# warning constant, not this poller's policy. Reading it bare capped the declared T-7d attempt
# window at 72h: 96 of 168 hours structurally unreachable, on the one lever (a k==0 moment) that
# needs every hour it can get. The same cap produced a wrong HUMAN verdict — RELOGIN_AUTOMATION_PLAN
# concluded "the cliff is closed until roughly 2026-08-23" off this surface's exit 0 while `next`
# was 8 days from its cliff.

@test "M2: the poller ASKS for its own T-trigger window, not this surface's default filter" {
  mk next3 100 0                  # 4.2d out: inside T-7d, well OUTSIDE the 72h filter
  build ls
  run "$P" --json
  [ "$status" -eq 0 ] || false
  # it asked for 168h explicitly...
  grep -q -- '--window-h 168' "$D/ls.argv" || false
  # ...and therefore SAW the account the 72h view hides
  json | jq -e '.detection=="login-status" and .candidates==1 and .acct=="next3"' >/dev/null || false
  [ "$(ncalls)" -eq 1 ] || false
}

@test "M2: --trigger-days is what it asks for — the window follows the POLICY, not a constant" {
  mk next3 100 0
  build ls
  run "$P" --trigger-days 3 --json
  [ "$status" -eq 0 ] || false
  grep -q -- '--window-h 72' "$D/ls.argv" || false     # 3d = 72h
  # DISCRIMINATING CONTROL: at a 3-day policy a 4.2-day deadline is correctly NOT due, so the
  # widened ask cannot be mistaken for "always attempt".
  json | jq -e '.candidates==0 and .action=="none"' >/dev/null || false
  [ "$(ncalls)" -eq 0 ] || false
}

@test "M2 FAIL-SOFT: on a build without --window-h the cap is LOUD, never a silent nothing-due" {
  mk next3 100 0
  build ls-narrow                 # --login-status only: the shape deployed while the checkout lags
  run "$P" --json
  [ "$status" -eq 0 ] || false
  # it must NOT pass a flag the build does not advertise...
  # (asserted via `run` + status, never `grep -c … || echo 0`: grep -c prints "0" AND exits 1 on no
  # match, so the fallback appends a SECOND "0" and the integer test errors out — a broken
  # assertion that reads as a failing subject.)
  [ -s "$D/ls.argv" ] || false                 # the surface WAS called — absence is not vacuous
  run grep -q -- '--window-h' "$D/ls.argv"
  [ "$status" -ne 0 ] || false
  # ...and the cap must be on the record, plus the nothing-due line must DISCLAIM the window it
  # did not actually apply (the old line named T-7d while looking at 72h).
  grep -q 'WINDOW-CAPPED' "$CC_RELOGIN_POLL_LOG" || false
  grep -q 'WINDOW CAPPED' "$CC_RELOGIN_POLL_LOG" || false
  grep -q 'does NOT cover T-7d' "$CC_RELOGIN_POLL_LOG" || false
}

@test "M2 POSITIVE CONTROL: with --window-h supported, no cap is claimed" {
  mk next3 100 0
  build ls
  run "$P" --json
  [ "$status" -eq 0 ] || false
  [ -s "$CC_RELOGIN_POLL_LOG" ] || false       # the log WAS written — the absence below is real
  run grep -q 'WINDOW-CAPPED' "$CC_RELOGIN_POLL_LOG"
  [ "$status" -ne 0 ] || false
}

# ── M2b: hours_secs is UNIT-AWARE — the 24x deadline error the cap was hiding ────────────────────

@test "M2b: a DAYS-formatted deadline is not read as hours (was 24x under, escalating 3d early)" {
  mk next3 90 0                   # fmt_h renders 90h as "3.8d" — the exact shape that broke
  build ls
  run "$P" --json
  [ "$status" -eq 0 ] || false
  # 3.8d = 91.2h. The pre-fix parser produced 3h, which is inside the 48h escalation window and
  # would have raised a class-C board row three days early, keyed on a WRONG deadline.
  json | jq -e '.hours_left >= 88 and .hours_left <= 94' >/dev/null || false
  json | jq -e '.escalated == false' >/dev/null || false
  [ "$(nrows)" -eq 0 ] || false
}

@test "M2b: every shape fmt_h can emit is parsed or explicitly REFUSED — never silently truncated" {
  # Exercised through the SUBJECT's own source, extracted to a file and sourced — never piped into
  # `. /dev/stdin`, which competes for the stdin a sourced script may itself read.
  sed -n '/^hours_secs()/,/^}/p' "$P" > "$D/hs.sh"
  [ -s "$D/hs.sh" ] || false                 # the extraction itself must not silently yield nothing
  grep -q 'awk' "$D/hs.sh" || false          # ...and must be the unit-aware body, not a stale stub
  run bash -c '
    . "'"$D"'/hs.sh"
    fail=0
    chk() { got="$(hours_secs "$1")"; [ "$got" = "$2" ] || { echo "hours_secs($1) = ${got:-<empty>}, want ${2:-<empty>}"; fail=1; }; }
    chk "30m"    1800
    chk "0m"     0
    chk "41.5h"  149400
    chk "2.0d"   172800
    chk "3.7d"   319680
    chk "now"    0
    chk "-3"     0
    chk "12"     43200
    chk "99d+"   ""
    chk "?"      ""
    chk "-"      ""
    chk ""       ""
    chk "garbage" ""
    exit $fail'
  [ "$status" -eq 0 ] || false
}

@test "M2b: a MINUTES deadline is seen, not dropped — the most urgent shape of all" {
  mk next3 0 0                    # 0h ⇒ REQUIRED, and fmt_h renders it "0m", not a bare number
  build ls
  run "$P" --json
  # exit 5 = ESCALATED, the designed loud verdict at T-0 — not an error (see the poller's Exit note)
  [ "$status" -eq 5 ] || false
  json | jq -e '.candidates==1 and .acct=="next3"' >/dev/null || false
  json | jq -e '.escalated == true' >/dev/null || false
  [ "$(nrows)" -eq 1 ] || false
  # The pre-fix parser REFUSED "0m" outright (a non-digit made it return empty), so this row was
  # `continue`d and the most urgent deadline of all produced candidates=0.
  grep -q 'hours_secs\|0m' "$D/ls.tsv" || false
}

@test "M2b: a REQUIRED row with NO parseable deadline is acted on NOW, not silently dropped" {
  # next3's real 2026-07-24 shape: the refresh grant was REJECTED with time still on the stamp, so
  # --login-status fills both deadline columns with "—" and the verdict is driven by the cause.
  # Before this, the poller `continue`d such a row: the account that most needed it was invisible.
  build ls
  printf 'next3\tREQUIRED\ttoken-invalid\t—\t—\tclaude-next3\n' > "$D/ls.tsv"
  printf '1\n' > "$D/ls.rc"
  run "$P" --json
  [ "$status" -eq 5 ] || false                       # ESCALATED — loud, exactly as intended
  json | jq -e '.candidates==1 and .acct=="next3" and .escalated==true' >/dev/null || false
  [ "$(nrows)" -eq 1 ] || false
  # DISCRIMINATING CONTROL: the same shape as EXPIRING is genuinely unknowable and MUST be skipped
  # rather than given a fabricated now-deadline.
  rm -rf "$CC_RELOGIN_POLL_STATE_DIR" "$CC_REAPER_IDL"; : > "$CC_RELOGIN_POLL_LOG"
  printf 'next3\tEXPIRING\tlogin-expiry\t—\t—\tclaude-next3\n' > "$D/ls.tsv"
  run "$P" --json
  [ "$status" -eq 0 ] || false
  json | jq -e '.candidates==0' >/dev/null || false
}
