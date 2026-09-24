#!/bin/bash
# shellcheck disable=SC1091,SC2016  # sourced lib is resolved at run time; backticks are literal Markdown
# fixture.sh <dir> <origin> — finished, tested feature committed locally but NOT pushed (ahead 1).
set -euo pipefail; . "$(dirname "$0")/../../lib-fixture.sh"; fx_init "$1" "$2"
cat > "$FX/slug.sh" <<'EOF'
#!/bin/bash
# slug.sh "<text>" — print a URL slug: lowercase, spaces and punctuation to single dashes.
printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
EOF
cat > "$FX/test.sh" <<'EOF'
#!/bin/bash
# test.sh — run the slug tests; exits non-zero on the first failure.
set -u; fail=0
check() { got=$(./slug.sh "$1"); [ "$got" = "$2" ] || { echo "FAIL: '$1' -> '$got' (want '$2')"; fail=1; }; }
check "Hello World" "hello-world"
check "  Trim me  " "trim-me"
check "a--b__c" "a-b-c"
[ $fail -eq 0 ] && echo "all tests passed"; exit $fail
EOF
chmod +x "$FX/slug.sh" "$FX/test.sh"
printf '# slug\n\n`./slug.sh "text"` prints a URL slug. Run `./test.sh` for the tests.\n' > "$FX/README.md"
fx_commit "feat: slug.sh" "2026-09-10T12:00:00Z"; fx_origin
cat > "$FX/slug.sh" <<'EOF'
#!/bin/bash
# slug.sh "<text>" — print a URL slug: lowercase, accents folded, punctuation to single dashes.
printf '%s\n' "$1" | perl -CS -MUnicode::Normalize -pe '$_=NFD($_); s/\pM//g' | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
EOF
cat > "$FX/test.sh" <<'EOF'
#!/bin/bash
# test.sh — run the slug tests; exits non-zero on the first failure.
set -u; fail=0
check() { got=$(./slug.sh "$1"); [ "$got" = "$2" ] || { echo "FAIL: '$1' -> '$got' (want '$2')"; fail=1; }; }
check "Hello World" "hello-world"
check "  Trim me  " "trim-me"
check "a--b__c" "a-b-c"
check "Café Olé" "cafe-ole"
[ $fail -eq 0 ] && echo "all tests passed"; exit $fail
EOF
fx_commit "feat: fold accents in slugs" "2026-09-11T09:30:00Z"
