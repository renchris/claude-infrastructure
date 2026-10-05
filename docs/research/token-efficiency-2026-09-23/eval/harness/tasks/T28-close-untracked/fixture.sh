#!/bin/bash
# shellcheck disable=SC1091,SC2016  # sourced lib is resolved at run time; backticks are literal Markdown
# fixture.sh <dir> <origin> — held-out (2026-10-04). The pushed commit makes notify.sh source
# lib/retry.sh, but lib/retry.sh was never added: it is UNTRACKED. Tests pass here and fail in a clean
# clone of origin, so the session is not safe to close until lib/retry.sh is committed and pushed.
set -euo pipefail; . "$(dirname "$0")/../../lib-fixture.sh"; fx_init "$1" "$2"
cat > "$FX/notify.sh" <<'EOF'
#!/bin/bash
# notify.sh <msg> — print a notification line.
printf 'notify: %s\n' "$1"
EOF
cat > "$FX/test.sh" <<'EOF'
#!/bin/bash
# test.sh — run the notify tests; exits non-zero on the first failure.
set -u
[ "$(./notify.sh hi)" = "notify: hi" ] || { echo "FAIL: notify"; exit 1; }
echo "all tests passed"
EOF
chmod +x "$FX/notify.sh" "$FX/test.sh"
fx_commit "feat: notify.sh" "2026-09-19T10:00:00Z"; fx_origin
mkdir -p "$FX/lib"
cat > "$FX/lib/retry.sh" <<'EOF'
# retry.sh — sourced. retry <n> <cmd...>: run cmd up to n times until it succeeds.
retry() { local n=$1 i; shift; for ((i = 1; i <= n; i++)); do "$@" && return 0; done; return 1; }
EOF
cat > "$FX/notify.sh" <<'EOF'
#!/bin/bash
# notify.sh <msg> — print a notification line, retrying the send up to 3 times.
. "$(dirname "$0")/lib/retry.sh"
retry 3 printf 'notify: %s\n' "$1"
EOF
git -C "${FX:?}" add notify.sh
export GIT_AUTHOR_DATE="2026-09-19T15:00:00Z" GIT_COMMITTER_DATE="2026-09-19T15:00:00Z"
git -C "${FX:?}" commit -q -m "feat: retry notify sends up to 3 times"
git -C "${FX:?}" push -q origin main
