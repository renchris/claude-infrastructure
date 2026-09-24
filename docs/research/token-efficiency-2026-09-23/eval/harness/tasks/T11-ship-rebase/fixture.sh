#!/bin/bash
# shellcheck disable=SC1091,SC2016  # sourced lib is resolved at run time; backticks are literal Markdown
# fixture.sh <dir> <origin> — a finished commit on local branch feat/timeout; meanwhile origin/main
# gained a README commit this clone has NOT fetched. Landing needs fetch + rebase + push.
set -euo pipefail; . "$(dirname "$0")/../../lib-fixture.sh"; fx_init "$1" "$2"
cat > "$FX/fetch.sh" <<'EOF'
#!/bin/bash
# fetch.sh <url> — print the HTTP status code of <url>.
curl -s -o /dev/null -w '%{http_code}\n' "$1"
EOF
chmod +x "$FX/fetch.sh"
cat > "$FX/test.sh" <<'EOF'
#!/bin/bash
# test.sh — static checks for fetch.sh (no network)
set -u; bash -n fetch.sh || exit 1
grep -q 'curl -s' fetch.sh || { echo "FAIL: curl call missing"; exit 1; }
echo "all tests passed"
EOF
chmod +x "$FX/test.sh"; printf '# fetch\n\n`./fetch.sh URL` prints the status code.\n' > "$FX/README.md"
fx_commit "feat: fetch.sh"; fx_origin
# someone else lands a README change on origin/main via a second clone
OTHER="$R.other"; rm -rf "$OTHER"
git clone -q -b main "$R" "$OTHER"
printf '# fetch\n\n`./fetch.sh URL` prints the HTTP status code of URL.\n\nRequires curl.\n' > "$OTHER/README.md"
git -C "$OTHER" -c user.name=Teammate -c user.email=mate@example.invalid commit -qam "docs: note the curl dependency"
git -C "$OTHER" push -q origin main; rm -rf "$OTHER"
# our finished work, on a local branch, based on the old main
git -C "${FX:?}" checkout -q -b feat/timeout
cat > "$FX/fetch.sh" <<'EOF'
#!/bin/bash
# fetch.sh [--timeout SECS] <url> — print the HTTP status code of <url> (default timeout 10s).
timeout=10
if [ "${1:-}" = "--timeout" ]; then timeout=$2; shift 2; fi
curl -s -m "$timeout" -o /dev/null -w '%{http_code}\n' "$1"
EOF
fx_commit "feat: --timeout flag for fetch.sh" "2026-09-11T11:00:00Z"
