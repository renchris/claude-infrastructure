#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats: every @test body IS its own subshell, so an `export` inside one
#   is meant to be test-local (SC2030/SC2031), and setup()'s helpers run from those subshells
#   rather than file scope (SC2329).
#
# THE KEYCHAIN SERVICE STRING IS NOT UNIQUE, AND TWO READERS BET THAT IT WAS.
#
# Measured 2026-09-16 on this box: TWO generic-password items share the service
# 'Claude Code-credentials-136fa815' —
#     acct="chrisren"  payload {claudeAiOauth, mcpOAuth}   ← the real credential
#     acct="unknown"   payload {mcpOAuth}                  ← returned FIRST by an -a-less lookup
# so `security find-generic-password -s <svc> -w` parses fine and KeyErrors on 'claudeAiOauth'.
#
# Cost of the two sites that omitted -a:
#   · scripts/cloud-create-api.py  — the cloud return lane abstained 719 times from
#     2026-09-11T23:20:56Z and closed 0 rows for four days, reporting "keychain item … holds no
#     OAuth access token", i.e. a WORLD-shaped cause (bad credential, go re-login) for a fact about
#     the READER. `cc-relogin --dry-run next4` refused the prescribed remedy the whole time as
#     "no re-auth needed — healthy (auth=ok)".
#   · bin/cc-relogin — read_refresh_token() returned None, so phase 1 reported "refresh token
#     unreadable from keychain" and fell through to a BROWSER login on an account whose refresh
#     grant was valid for three more weeks. Its -a branch existed but was unreachable, because
#     --relogin-info does not emit keychain_account.
#
# WHY THE STUB IS SHAPED THIS WAY. The axis under test is whether the reader NARROWS by account,
# so a stub that ignores -a holds that axis constant and the suite would be decorative on the one
# thing it exists for [[fixture-identifier-shape-collapses-two-spaces]]. This stub therefore
# reproduces the production SHAPE: it serves the mcpOAuth-only blob when -a is absent and the full
# blob when -a matches. Case 1 proves the stub can tell them apart before anything else runs.
#
# Every refusal is paired with a MUTANT that removes the cure and must go red — a green suite
# credits no site [[per-site-mutation-attributes-coverage]].

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/kcnarrow.XXXXXX")"
  # HERMETIC $HOME. Both subjects default their accounts path under ~/ (cloud-create-api's
  # ACCOUNTS, cc-relogin's ACCOUNTS_JSON at :99), so an unfixtured run reads the operator's real
  # config — and reading live state is precisely how the first draft of this suite reached the real
  # keychain and printed a live token. The env seams below already point both subjects at the
  # fixture; this makes the ambient path unreachable rather than merely unused.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude" "$HOME/bin"
  export REPO WORK
  mkdir -p "$WORK/bin"

  # The stub. Quoted heredoc: the JSON carries no apostrophe, but quoting it is what keeps it that
  # way [[fixture-stub-cannot-carry-an-apostrophe]].
  cat > "$WORK/bin/security" <<'STUB'
#!/usr/bin/env bash
# Mimics `security find-generic-password`. The ONLY axis it models is -a narrowing.
acct=""
for ((i=1; i<=$#; i++)); do
  if [ "${!i}" = "-a" ]; then j=$((i+1)); acct="${!j}"; fi
done
if [ "$acct" = "chrisren" ]; then
  printf '%s\n' '{"claudeAiOauth":{"accessToken":"AT-REAL-TOKEN","refreshToken":"RT-REAL-TOKEN"},"mcpOAuth":{}}'
else
  printf '%s\n' '{"mcpOAuth":{}}'
fi
exit 0
STUB
  chmod +x "$WORK/bin/security"

  cat > "$WORK/accounts.json" <<'ACCT'
{"keychain_account":"chrisren",
 "accounts":[{"name":"next4","config_dir":"~/.claude-quaternary",
              "keychain_service":"Claude Code-credentials-136fa815"}]}
ACCT
  export CC_ACCOUNTS_JSON="$WORK/accounts.json"
  export CLAUDE_ACCOUNTS_JSON="$WORK/accounts.json"
  # Belt and braces: if a subject ever ignores its seam and falls back to ~/.claude/accounts.json,
  # it finds the FIXTURE, never the operator's file.
  cp "$WORK/accounts.json" "$HOME/.claude/accounts.json"
}

teardown() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }

# ---------------------------------------------------------------- stub control

@test "1 the stub can tell the two items apart (without this, every case below is vacuous)" {
  bare="$("$WORK/bin/security" find-generic-password -s svc -w)"
  narrowed="$("$WORK/bin/security" find-generic-password -s svc -a chrisren -w)"
  case "$bare" in *claudeAiOauth*) echo "stub leaks the real blob to an -a-less call"; return 1 ;; esac
  case "$narrowed" in *claudeAiOauth*) : ;; *) echo "stub withholds the blob from -a chrisren"; return 1 ;; esac
}

# ------------------------------------------------- scripts/cloud-create-api.py

_cca_token() {   # $1 = path to the module under test
  PATH="$WORK/bin:$PATH" python3 - "$1" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("cca", sys.argv[1])
m = importlib.util.module_from_spec(spec)
sys.argv = ["cloud-create-api"]
spec.loader.exec_module(m)
tok = m.access_token(m.account_row("next4"))
# NEVER print a token value. A helper that echoes its secret on the happy path echoes a REAL one
# the day a stub is bypassed — which is what leaked a live next4 refresh token on 2026-09-16.
print("FIXTURE-TOKEN" if tok == "AT-REAL-TOKEN" else f"OTHER len={len(tok)}")
PY
}

@test "2 cloud-create-api reads the credential through the account-narrowed lookup" {
  run _cca_token "$REPO/scripts/cloud-create-api.py"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  case "$output" in *FIXTURE-TOKEN*) : ;; *) echo "got: $output"; return 1 ;; esac
}

@test "3 MUTANT: drop -a from cloud-create-api and the read must fail (pins the cure, not the file)" {
  sed 's/"-s", service, "-a", kc_account, "-w"/"-s", service, "-w"/' \
      "$REPO/scripts/cloud-create-api.py" > "$WORK/mutant-cca.py"
  if cmp -s "$REPO/scripts/cloud-create-api.py" "$WORK/mutant-cca.py"; then
    echo "mutant applied to NOTHING — the anchor moved, so this case proves nothing"; return 1
  fi
  run _cca_token "$WORK/mutant-cca.py"
  [ "$status" -ne 0 ] || { echo "mutant still succeeded: $output"; false; }
  case "$output" in *claudeAiOauth*) : ;; *) echo "unexpected failure mode: $output"; return 1 ;; esac
}

# ------------------------------------------------------------- bin/cc-relogin

_ccr_refresh() {
  # CC_RELOGIN_SECURITY_BIN is the documented seam (bin/cc-relogin:97). PATH alone does NOT reach
  # this reader: SECURITY_BIN defaults to the ABSOLUTE /usr/bin/security, so a PATH-only stub is
  # silently bypassed and the test hits the real keychain.
  CC_RELOGIN_SECURITY_BIN="$WORK/bin/security" \
  CLAUDE_ACCOUNTS_JSON="$WORK/accounts.json" \
  PATH="$WORK/bin:$PATH" python3 - "$1" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("ccr", sys.argv[1])
spec = importlib.util.spec_from_loader("ccr", loader)
m = importlib.util.module_from_spec(spec)
sys.argv = ["cc-relogin"]
loader.exec_module(m)
# --relogin-info does not emit keychain_account; that omission is the bug, so the fixture
# reproduces it and the fallback is what must supply the account.
tok = m.read_refresh_token({"keychain_service": "Claude Code-credentials-136fa815"})
print("FIXTURE-TOKEN" if tok == "RT-REAL-TOKEN" else ("NONE" if not tok else f"OTHER len={len(tok)}"))
PY
}

@test "4 cc-relogin phase 1 reads the refresh token when --relogin-info omits keychain_account" {
  run _ccr_refresh "$REPO/bin/cc-relogin"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  case "$output" in *FIXTURE-TOKEN*) : ;; *) echo "got: $output"; return 1 ;; esac
}

@test "5 MUTANT: remove cc-relogin's accounts.json fallback and phase 1 goes blind again" {
  sed 's/info.get("keychain_account") or _accounts_keychain_account()/info.get("keychain_account")/' \
      "$REPO/bin/cc-relogin" > "$WORK/mutant-ccr"
  if cmp -s "$REPO/bin/cc-relogin" "$WORK/mutant-ccr"; then
    echo "mutant applied to NOTHING — the anchor moved, so this case proves nothing"; return 1
  fi
  run _ccr_refresh "$WORK/mutant-ccr"
  case "$output" in *FIXTURE-TOKEN*) echo "mutant still read the token"; return 1 ;; esac
}

@test "6 the suite cannot reach the real keychain (a bypassed stub is how case 4 leaked a live token)" {
  # `env` cannot invoke a bash function — doing so exits 127 and this case passes VACUOUSLY,
  # which it did on first write. _ccr_refresh already exports the seam itself.
  run _ccr_refresh "$REPO/bin/cc-relogin"
  [ "$status" -ne 127 ] || { echo "case is vacuous: helper not found"; false; }
  case "$output" in
    sk-ant-*|*sk-ant-*) echo "REAL CREDENTIAL REACHED — the stub is bypassed"; return 1 ;;
  esac
}
