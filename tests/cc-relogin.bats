#!/usr/bin/env bats
# cc-relogin — the unattended OAuth re-auth executor. These tests are HERMETIC by construction:
# every external surface is a stub (claude-accounts, ps, /usr/bin/security, the claude binary,
# cc-authbrowser) and the heal lock lives under CC_RELOGIN_TMP. Nothing here ever performs a real
# sign-in, reads a real keychain item, or launches a real browser — that is a human-gated step.

setup() {
  # HERMETIC $HOME (scripts/test-hermeticity-lint.sh — the ratchet that binds every NEW suite).
  # The header above already claims hermeticity, and every seam this suite KNOWS about is stubbed;
  # but bin/cc-relogin resolves its own state under ~, so unfixtured the subject still reads and
  # writes the operator's live layer. Free here — nothing below reads $HOME.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  C="$REPO/bin/cc-relogin"
  D="$BATS_TEST_TMPDIR"
  CFG="$D/cfg-next3"
  LOCK="$D/claude-accounts-heal-next3.lock"
  export CC_RELOGIN_TMP="$D"
  export CC_RELOGIN_WARN_H=72
  export CC_RELOGIN_LOG="$D/cc-relogin.log"
  export CC_RELOGIN_ACCOUNTS_BIN="$D/stub-accounts"
  export CC_RELOGIN_PS_BIN="$D/stub-ps"
  export CC_RELOGIN_SECURITY_BIN="$D/stub-security"
  export CC_RELOGIN_AUTHBROWSER_BIN="$D/stub-authbrowser"

  # --- stubs: each serves a per-CALL fixture (foo.1.json, foo.2.json, …) so a "before" and an
  # --- "after" sweep can differ, falling back to foo.json when no per-call file exists.
  hdr() { { echo '#!/usr/bin/env bash'; echo "FIX=\"$D\""; } > "$1"; }

  # A bare `! cmd` is a SILENT NO-OP in bats unless it is the last line of the @test (POSIX
  # exempts !-inverted pipelines from errexit; shellcheck SC2314). Verified on bats 1.13.0.
  # Every negative assertion goes through this helper instead.
  refute() { run "$@"; [ "$status" -ne 0 ]; }

  hdr "$D/stub-accounts"
  cat >> "$D/stub-accounts" <<'STUB'
echo "accounts $*" >> "$FIX/accounts-calls"
bump() { local f="$FIX/n-$1" n; n=$(cat "$f" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$f"; echo "$n"; }
if [[ "$*" == *--relogin-info* ]]; then
  n=$(bump info)
  if [ -f "$FIX/info.rc" ]; then echo "unknown account: bogus (next|next2|next3|next4)" >&2; exit "$(cat "$FIX/info.rc")"; fi
  p="$FIX/info.$n.json"; [ -f "$p" ] || p="$FIX/info.json"; cat "$p"; exit 0
fi
if [[ "$*" == *--fresh* ]]; then
  n=$(bump fresh); p="$FIX/fresh.$n.json"; [ -f "$p" ] || p="$FIX/fresh.json"; cat "$p"; exit 0
fi
exit 1
STUB

  hdr "$D/stub-ps"
  cat >> "$D/stub-ps" <<'STUB'
n=$(cat "$FIX/n-ps" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$FIX/n-ps"
p="$FIX/ps.$n"; [ -f "$p" ] || p="$FIX/ps"
if [ -f "$p" ]; then cat "$p"; fi
exit 0
STUB

  hdr "$D/stub-security"
  cat >> "$D/stub-security" <<'STUB'
echo "security $*" >> "$FIX/security-calls"
[ -f "$FIX/creds.json" ] || exit 44
cat "$FIX/creds.json"
STUB

  hdr "$D/stub-claude"
  cat >> "$D/stub-claude" <<'STUB'
{ echo "argv=$*"; echo "CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR"
  echo "CLAUDE_CODE_OAUTH_SCOPES=$CLAUDE_CODE_OAUTH_SCOPES"
  echo "RT_LEN=${#CLAUDE_CODE_OAUTH_REFRESH_TOKEN}"; } >> "$FIX/claude-calls"
echo "Login successful."
if [ -f "$FIX/claude.out" ]; then cat "$FIX/claude.out"; fi
exit "$(cat "$FIX/claude.rc" 2>/dev/null || echo 0)"
STUB

  hdr "$D/stub-authbrowser"
  echo 'echo "authbrowser $*" >> "$FIX/authbrowser-calls"' >> "$D/stub-authbrowser"
  chmod +x "$D"/stub-*

  # --- fixture writers -------------------------------------------------------------------------
  mk_info() { # <n|all> <has_refresh_token> [keychain_state] [config_dir]
    local f="$D/info.$1.json"; [ "$1" = all ] && f="$D/info.json"
    cat > "$f" <<EOF
{"name":"next3","config_dir":"${4:-$CFG}","launcher":"claude-next3","email":"e@example.test",
 "dia_profile":"Claude3","dia_profile_dir":"/p",
 "keychain_service":"Claude Code-credentials-deadbeef","keychain_state":"${3:-present}",
 "claude_bin":"$D/stub-claude","oauth_scopes":"user:profile user:inference",
 "has_refresh_token":$2}
EOF
  }
  mk_fresh() { # <n|all> <auth> [login_expires_at] [login_expires_h]
    local f="$D/fresh.$1.json" extra=""
    [ "$1" = all ] && f="$D/fresh.json"
    [ -n "${3:-}" ] && extra="$extra,\"login_expires_at\":\"$3\""
    [ -n "${4:-}" ] && extra="$extra,\"login_expires_h\":$4"
    cat > "$f" <<EOF
{"window":{},"cached":false,"rows":[{"acct":"next3","email":"e@example.test",
 "launcher":"claude-next3","k":0,"auth":"$2"$extra}]}
EOF
  }
  mk_creds() { echo '{"claudeAiOauth":{"refreshToken":"rt-FIXTURE-not-a-real-token"}}' > "$D/creds.json"; }
  ps_live() { printf '%s\n' "/opt/c/bin/claude --resume  CLAUDE_CONFIG_DIR=$CFG" > "$D/ps.$1"; }
  # The common "needs a relogin, phase 1 available, no live sessions" fixture set.
  needy() { mk_info all true; mk_fresh 1 logged-out "2026-08-01T00:00:00Z"; mk_creds; }
  hold_lock() { # background holder of the heal lock -> pid in $HOLDER. NOT via $(…): a command
                # substitution would block on the backgrounded child's inherited stdout pipe.
    python3 -c 'import fcntl,sys,time;f=open(sys.argv[1],"w");fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB);time.sleep(30)' \
      "$LOCK" >/dev/null 2>&1 &
    HOLDER=$!
    sleep 0.5
  }
}

# ---- arg surface ----------------------------------------------------------------------------

@test "--help exits 0 and documents the CLI" {
  run "$C" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q -- '--no-browser'
  echo "$output" | grep -q 'PROVEN'
}

@test "no account name → REFUSED (2)" {
  run "$C"
  [ "$status" -eq 2 ]
}

@test "unexpected argument → REFUSED (2)" {
  run "$C" next3 --wat
  [ "$status" -eq 2 ]
}

# ---- the gate -------------------------------------------------------------------------------

@test "unknown account → REFUSED (2)" {
  echo 1 > "$D/info.rc"
  run "$C" bogus
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi 'unknown account'
}

@test "healthy account (deadline far away) → REFUSED (2), nothing attempted" {
  mk_info all true; mk_fresh all ok "2027-01-01T00:00:00Z" 900
  run "$C" next3
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'no re-auth needed'
  [ ! -f "$D/claude-calls" ]
}

@test "login_expires_h inside the warn window → NOT refused (proceeds past the need gate)" {
  mk_info all true; mk_fresh 1 ok "2026-08-01T00:00:00Z" 10; mk_creds
  run "$C" next3 --dry-run --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .need_reason)" = "login_expires_h=10 <= warn 72.0" ]
}

@test "§2 degraded detection: no login_* fields and nothing else wrong → REFUSED, loudly" {
  mk_info all true; mk_fresh all ok
  run "$C" next3
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'UNAVAILABLE'
}

@test "k>0 at the pre-lock snapshot → REFUSED (2), never touches the token" {
  needy; ps_live 1
  run "$C" next3
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'live session'
  [ ! -f "$D/claude-calls" ]
}

@test "heal lock already held → REFUSED (2)" {
  needy
  hold_lock
  run "$C" next3
  kill "$HOLDER" 2>/dev/null || true
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'heal lock busy'
  [ ! -f "$D/claude-calls" ]
}

@test "under-lock re-check: k==0 at snapshot, k>0 under the lock → REFUSED (2)" {
  needy; ps_live 2                      # first ps call clean, second (under the lock) live
  run "$C" next3
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'under the lock'
  [ ! -f "$D/claude-calls" ]
}

@test "headless one-shots (claude -p) are NOT live sessions — mirrors concurrency()" {
  needy
  printf '%s\n' "/opt/c/bin/claude -p hello  CLAUDE_CONFIG_DIR=$CFG" > "$D/ps"
  run "$C" next3 --dry-run
  [ "$status" -eq 0 ]
}

@test "attribution uses the LAST CLAUDE_CONFIG_DIR= on the line (ps -E appends env after argv)" {
  needy
  printf '%s\n' "/opt/c/bin/claude --resume CLAUDE_CONFIG_DIR=/decoy  CLAUDE_CONFIG_DIR=$CFG" > "$D/ps"
  run "$C" next3
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'live session'
}

@test "bare claude counts toward the ~/.claude-next account (~/.claude mirrors it)" {
  mk_info all true "present" "$D/.claude-next"; mk_fresh 1 logged-out; mk_creds
  printf '%s\n' "/opt/c/bin/claude --resume" > "$D/ps"
  run "$C" next3
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'live session'
}

@test "ps unavailable → live count UNKNOWN → REFUSED, never assumed idle" {
  needy
  export CC_RELOGIN_PS_BIN="$D/no-such-ps"
  run "$C" next3
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'UNKNOWN'
}

# ---- --dry-run ------------------------------------------------------------------------------

@test "--dry-run: gate + plan, exit 0, mutates nothing, releases the lock" {
  needy
  run "$C" next3 --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'nothing mutated'
  [ ! -f "$D/claude-calls" ]            # no `claude auth login`
  [ ! -f "$D/security-calls" ]          # no keychain read
  [ ! -f "$D/authbrowser-calls" ]       # no browser
  run python3 -c 'import fcntl,sys;f=open(sys.argv[1],"w");fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)' "$LOCK"
  [ "$status" -eq 0 ]                   # the lock was released on exit
}

@test "--dry-run --json: result is 'dry-run', never a false 'proven'" {
  needy
  run "$C" next3 --dry-run --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .result)" = "dry-run" ]
  [ "$(echo "$output" | jq -r .dry_run)" = "true" ]
  [ "$(echo "$output" | jq -r '.plan | length')" -eq 2 ]
}

# ---- phase 1 + verify-by-effect ---------------------------------------------------------------

@test "phase 1 + moved deadline → PROVEN (0)" {
  mk_info all true; mk_creds
  mk_fresh 1 logged-out "2026-08-01T00:00:00Z"
  mk_fresh 2 ok         "2026-09-01T00:00:00Z"
  run "$C" next3
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'deadline moved'
}

@test "phase 1 passes the account's scopes VERBATIM and its own config dir" {
  mk_info all true; mk_creds
  mk_fresh 1 logged-out "2026-08-01T00:00:00Z"; mk_fresh 2 ok "2026-09-01T00:00:00Z"
  run "$C" next3
  [ "$status" -eq 0 ]
  grep -q 'argv=auth login' "$D/claude-calls"
  grep -qx "CLAUDE_CODE_OAUTH_SCOPES=user:profile user:inference" "$D/claude-calls"
  grep -qx "CLAUDE_CONFIG_DIR=$CFG" "$D/claude-calls"
  grep -q 'RT_LEN=2[0-9]' "$D/claude-calls"
}

@test "report-only success (deadline did NOT move) with --no-browser → UNVERIFIED (5)" {
  mk_info all true; mk_creds
  mk_fresh 1 logged-out "2026-08-01T00:00:00Z"
  mk_fresh 2 ok         "2026-08-01T00:00:00Z"     # binary said "Login successful." — deadline stuck
  run "$C" next3 --no-browser
  [ "$status" -eq 5 ]
  echo "$output" | grep -q 'did NOT move'
}

@test "report-only success while auth is still broken → UNVERIFIED (5)" {
  mk_info all true; mk_creds
  mk_fresh 1 logged-out "2026-08-01T00:00:00Z"; mk_fresh 2 token-invalid "2026-09-01T00:00:00Z"
  run "$C" next3 --no-browser
  [ "$status" -eq 5 ]
  echo "$output" | grep -q "expected 'ok'"
}

@test "phase 1 never substitutes for phase 2: unmoved deadline escalates (→ 4, not 0/5)" {
  mk_info all true; mk_creds
  mk_fresh 1 logged-out "2026-08-01T00:00:00Z"; mk_fresh 2 ok "2026-08-01T00:00:00Z"
  run "$C" next3
  [ "$status" -eq 4 ]                   # reached phase 2 rather than declaring victory
  [ "$(echo "$output" | grep -c .)" -ge 1 ]
}

@test "§2 tolerance: no login_expires_at anywhere → PROVEN but the gap is named" {
  mk_info all true; mk_creds
  mk_fresh 1 logged-out; mk_fresh 2 ok
  run "$C" next3
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'UNVERIFIABLE'
}

@test "phase 1 binary failure + --no-browser → HEADLESS-EXHAUSTED (3)" {
  needy; echo 1 > "$D/claude.rc"
  run "$C" next3 --no-browser
  [ "$status" -eq 3 ]
  echo "$output" | grep -q 'phase 1 failed'
}

@test "no refresh token + --no-browser → HEADLESS-EXHAUSTED (3)" {
  mk_info all false; mk_fresh 1 logged-out
  run "$C" next3 --no-browser
  [ "$status" -eq 3 ]
  echo "$output" | grep -q 'no refresh token'
  [ ! -f "$D/claude-calls" ]
}

@test "keychain item unreadable + --no-browser → HEADLESS-EXHAUSTED (3), no login attempted" {
  mk_info all true; mk_fresh 1 logged-out          # no creds.json → stub-security exits 44
  run "$C" next3 --no-browser
  [ "$status" -eq 3 ]
  [ ! -f "$D/claude-calls" ]
}

# ---- phase 2 + error + shape -------------------------------------------------------------------

@test "phase 2 is reached when phase 1 is impossible and a browser is allowed → 4" {
  mk_info all false; mk_fresh 1 logged-out
  run "$C" next3
  [ "$status" -eq 4 ]
  echo "$output" | grep -qi 'phase 2'
}

@test "malformed --fresh --json → ERROR (1)" {
  mk_info all true; echo 'not json' > "$D/fresh.json"
  run "$C" next3
  [ "$status" -eq 1 ]
}

@test "--json emits the frozen result object" {
  mk_info all true; mk_creds
  mk_fresh 1 logged-out "2026-08-01T00:00:00Z"; mk_fresh 2 ok "2026-09-01T00:00:00Z"
  run "$C" next3 --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .acct)" = "next3" ]
  [ "$(echo "$output" | jq -r .result)" = "proven" ]
  [ "$(echo "$output" | jq -r .exit)" = "0" ]
  [ "$(echo "$output" | jq -r .phase_reached)" = "verify" ]
  [ "$(echo "$output" | jq -r .before.auth)" = "logged-out" ]
  [ "$(echo "$output" | jq -r .after.auth)" = "ok" ]
  [ "$(echo "$output" | jq -r .before.login_expires_at)" = "2026-08-01T00:00:00Z" ]
  [ "$(echo "$output" | jq -r .after.login_expires_at)" = "2026-09-01T00:00:00Z" ]
  [ -n "$(echo "$output" | jq -r .detail)" ]
}

@test "both measurement reads are --fresh --no-heal: a read that can heal is not independent" {
  mk_info all true; mk_creds
  mk_fresh 1 logged-out "2026-08-01T00:00:00Z"; mk_fresh 2 ok "2026-09-01T00:00:00Z"
  run "$C" next3
  [ "$status" -eq 0 ]
  # before + after, and NEITHER may re-enter probe_account's heal() -> `claude auth login`
  [ "$(grep -c -- '--fresh' "$D/accounts-calls")" -eq 2 ]
  [ "$(grep -- '--fresh' "$D/accounts-calls" | grep -c -- '--no-heal')" -eq 2 ]
  refute grep -e '--fresh --json' -e '--fresh$' "$D/accounts-calls"
}

@test "--json on a refusal carries the same shape" {
  mk_info all true; mk_fresh all ok "2027-01-01T00:00:00Z" 900
  run "$C" next3 --json
  [ "$status" -eq 2 ]
  [ "$(echo "$output" | jq -r .result)" = "refused" ]
  [ "$(echo "$output" | jq -r .phase_reached)" = "gate" ]
}

@test "a token in the child's output is redacted out of the result object and the log" {
  mk_info all true; mk_creds; echo 1 > "$D/claude.rc"
  mk_fresh 1 logged-out "2026-08-01T00:00:00Z"
  echo 'oauth failed for sk-ant-oat01-AAAAAAAAAAAAAAAAAAAAAAAA' > "$D/claude.out"
  run "$C" next3 --no-browser --json
  [ "$status" -eq 3 ]
  echo "$output" | grep -q 'REDACTED'
  echo "$output" > "$D/out.txt"
  refute grep -q 'sk-ant-oat01-A' "$D/out.txt"
  refute grep -q 'sk-ant-oat01-A' "$CC_RELOGIN_LOG"
}

@test "exit 7 CONSENT-GATE is retained for consumers but no code path emits it" {
  [ "$(grep -c 'EXIT_CONSENT_GATE' "$C")" -eq 1 ]     # the definition only — never passed to emit()
  grep -q '7: "consent-gate"' "$C"
}
