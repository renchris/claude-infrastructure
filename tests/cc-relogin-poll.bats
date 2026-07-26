#!/usr/bin/env bats
# cc-relogin-poll — the cadence layer: catch the T−7d login-renewal window, escalate LOUD at T−48h.
# Fully hermetic: `claude-accounts` and `cc-relogin` are file-driven stubs in BATS_TEST_TMPDIR, the
# clock is fixed (CC_RELOGIN_POLL_NOW), and the board/log/state all live in the tmpdir. NOTHING here
# authenticates, mutates an account, or loads a LaunchAgent — the real binaries are never invoked.

setup() {
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
    exit 0 ;;
  --login-status)
    [ -f "$D/ls.tsv" ] && cat "$D/ls.tsv"
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

# render the fixture into ONE detection surface: ls | json | none
build() {
  local a h k at st
  : > "$D/rows.login"; : > "$D/rows.plain"; : > "$D/ls.tsv"; rm -f "$D/ls_supported" "$D/fresh.json"
  while IFS=$'\t' read -r a h k; do
    [ -n "$a" ] || continue
    at="$(iso_in_h "$h")"; st=EXPIRING; [ "$h" -le 0 ] && st=REQUIRED
    jq -nc --arg a "$a" --argjson k "$k" --arg at "$at" \
      '{acct:$a,k:$k,launcher:("claude-"+$a),auth:"ok",login_expires_at:$at,login_expired:false,login_fixable:true}' >> "$D/rows.login"
    jq -nc --arg a "$a" --argjson k "$k" '{acct:$a,k:$k,launcher:("claude-"+$a),auth:"ok"}' >> "$D/rows.plain"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$a" "$st" "token-expiry" "$at" "$h" "claude-$a" >> "$D/ls.tsv"
  done < "$D/fixture"
  jq -sc '{window:{},cached:true,rows:.}' "$D/rows.plain" > "$D/cached.json"   # k only — no login_* fields
  case "$1" in
    ls)   touch "$D/ls_supported" ;;
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
