#!/usr/bin/env bats
# smart-bash-allowlist — the curl arm must DEFER (never allow, never deny) on SSRF shapes.
#
# Why (2026-09-29, docs/research/hook-ask-confirmations-2026-09-28.md §6 Round 2). Outside reso,
# curl-gate.py is out of scope and this hook's curl positive-whitelist was the only hook on a curl
# command: it hook-ALLOWED `curl http://169.254.169.254/`, `curl http://192.168.1.1/`, --resolve and
# `http_proxy=… curl …`, skipping the permission classifier. These shapes now defer to the normal
# permission flow. Defer, not deny: a LAN read such as a router admin page is legitimate outside
# reso, and this file can only ever say allow or nothing. The internal-address test is the shared
# hooks/lib/curl_ssrf.py, the same code curl-gate.py uses.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  printf '{"permissions":{"allow":[],"ask":[],"deny":[]}}\n' > "$HOME/.claude/settings.json"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  HOOK="$REPO/hooks/smart-bash-allowlist.sh"
  export PROJ="$BATS_TEST_TMPDIR/proj"; mkdir -p "$PROJ"
}

decide() {
  local cmd="$1" json
  json=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")
  if (cd "$PROJ" && printf '%s' "$json" | bash "$HOOK" 2>/dev/null | grep -q '"permissionDecision": *"allow"'); then
    echo allow
  else
    echo defer
  fi
}

@test "internal URL hosts defer in every spelling; a public read is still allowed" {
  [ "$(decide 'curl http://169.254.169.254/latest/')" = defer ]
  [ "$(decide 'curl -s http://192.168.1.1/')" = defer ]
  [ "$(decide 'curl http://2852039166/')" = defer ]
  [ "$(decide 'curl http://0xA9FEA9FE/')" = defer ]
  [ "$(decide 'curl -g http://[fd00:ec2::254]/')" = defer ]
  [ "$(decide 'curl http://169.254.169.254.nip.io/')" = defer ]
  [ "$(decide 'curl http://metadata.google.internal/')" = defer ]
  [ "$(decide 'curl -sSL https://example.com/')" = allow ]
  [ "$(decide 'curl -s http://localhost:3000/health')" = allow ]
}

@test "--resolve defers; the same read without it is allowed" {
  [ "$(decide 'curl --resolve example.com:443:93.184.216.34 https://example.com/')" = defer ]
  [ "$(decide 'curl --resolve example.com:80:169.254.169.254 http://example.com/')" = defer ]
  [ "$(decide 'curl -s https://example.com/')" = allow ]
}

@test "a proxy or curlrc env assignment defers; an unrelated assignment does not" {
  [ "$(decide 'http_proxy=http://192.168.1.50:3128 curl http://example.com/')" = defer ]
  [ "$(decide 'export https_proxy=http://p.example:1; curl -s https://example.com/')" = defer ]
  [ "$(decide 'CURL_HOME=/tmp/x curl -s https://example.com/')" = defer ]
  [ "$(decide 'FOO=1 curl -s https://example.com/')" = allow ]
}

@test "a missing shared normalizer DEFERS the curl arm rather than allowing it" {
  local d="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$d/hooks/lib"
  cp "$REPO/hooks/smart-bash-allowlist.sh" "$d/hooks/"
  cp "$REPO/hooks/lib/smart-bash-allowlist.py" "$d/hooks/lib/"
  HOOK="$d/hooks/smart-bash-allowlist.sh"
  [ "$(decide 'curl -s https://example.com/')" = defer ]
  [ "$(decide 'git status')" = allow ]   # positive control: the copied hook still decides
}
