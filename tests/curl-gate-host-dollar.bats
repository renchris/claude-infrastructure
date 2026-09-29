#!/usr/bin/env bats
# curl-gate.py — an unresolved `$` or backtick in a URL's AUTHORITY (host or port).
#
# THE HOLE (docs/research/hook-ask-confirmations-2026-09-28.md §7, round 4). The gate judged
# `http://$H/latest` by its literal text, so the "host" was the string `$h`: not internal, not
# loopback, and a GET — an open-read ALLOW, while the shell sent the request wherever $H pointed
# (169.254.169.254 in the first case below). The port position is the same hole: after host:port a
# glued variable can start with `@`, which turns everything before it into userinfo and the rest
# into a new host (`curl -v "http://127.0.0.1:1@127.0.0.1:9/x"` connects to port 9).
#
# THE RULE. For URLs the gate itself parses, after same-command literal bindings are resolved
# (partial substitution: one unresolved name no longer abandons the whole token), any `$` or
# backtick left in the authority → main thread ASK, agent context (payload `agent_id`) DENY. A
# resolvable variable in the authority whose value carries `@` or `\` (a host switch) counts too.
#
# OUT OF SCOPE BY RULING: a curl argument whose WHOLE URL is a variable (`"$u"`, `"$BASE/a"`) keeps
# its "No URL parsed" ask and gets no deny — that clause would catch 216 of 225 such asks.
#
# Harness laws as in curl-gate-decide.bats: real entrypoint, literal payloads, key on the decision.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  GATE="$REPO/hooks/curl-gate.py"
  ROOT="/Users/chrisren/Development/reso-management-app"
  unset CC_CURL_HOST_DOLLAR
}

# run_gate <main|agent> <command> <field> → the decision (allow on empty stdout) or the reason.
run_gate() {
  CTX="$1" CMD="$2" FIELD="$3" CWD="$ROOT" python3 -c '
import json,os,subprocess,sys
pay={"session_id":"t","cwd":os.environ["CWD"],"hook_event_name":"PreToolUse",
     "tool_name":"Bash","tool_input":{"command":os.environ["CMD"]}}
if os.environ["CTX"]=="agent": pay["agent_id"]="a1b2c3"
p=subprocess.run([sys.executable,sys.argv[1]],input=json.dumps(pay),capture_output=True,text=True)
out=p.stdout.strip()
h=json.loads(out)["hookSpecificOutput"] if out else {}
if os.environ["FIELD"]=="decision": print(h.get("permissionDecision","allow"))
else: print(h.get("permissionDecisionReason",""))
' "$GATE"
}
main_d()  { run_gate main  "$1" decision; }
agent_d() { run_gate agent "$1" decision; }

AGENT_REASON="Refused inside a subagent: the host or port in this URL is a variable the gate cannot check. Write scheme://host:port/ literally in the curl command (one curl per host if needed), or loop over a literal host list, e.g. for h in a.com b.com; do curl \"https://\$h/x\"; done; a variable may only come after the first literal '/', e.g. \"http://example.com/\${p#/}\". Do not move the request into a script, wget, python or nc."

# ── Must-pass shapes: not allow ──────────────────────────────────────────────────────────────────

@test "read-bound host (IMDS via read): main asks" {
  run main_d 'read H <<< 169.254.169.254; curl -s http://$H/latest'
  [ "$output" = "ask" ]
}

@test "read-bound host (IMDS via read): agent denies with the verbatim reason" {
  run agent_d 'read H <<< 169.254.169.254; curl -s http://$H/latest'
  [ "$output" = "deny" ]
  run run_gate agent 'read H <<< 169.254.169.254; curl -s http://$H/latest' reason
  [ "$output" = "$AGENT_REASON" ]
}

@test "assigned value that restructures the authority (/#) is not allowed" {
  run main_d "h='169.254.169.254/#'; curl -s \"https://\$h.reso.gl/x\""
  [ "$output" != "allow" ]
  run agent_d "h='169.254.169.254/#'; curl -s \"https://\$h.reso.gl/x\""
  [ "$output" = "deny" ]
}

@test "variable glued after host:port carrying @ (userinfo host switch): main asks, agent denies" {
  run main_d "p='@127.0.0.1:65432/version'; curl \"http://127.0.0.1:65431\$p\""
  [ "$output" = "ask" ]
  run agent_d "p='@127.0.0.1:65432/version'; curl \"http://127.0.0.1:65431\$p\""
  [ "$output" = "deny" ]
}

@test "unresolved variable glued after an allowlisted host:port: main asks, agent denies" {
  run main_d 'curl "https://harbour.reso.gl:443$A"'
  [ "$output" = "ask" ]
  run agent_d 'curl "https://harbour.reso.gl:443$A"'
  [ "$output" = "deny" ]
}

@test "unresolved port variable: localhost:\$PORT asks" {
  run main_d 'curl -s "http://localhost:$PORT/api/health"'
  [ "$output" = "ask" ]
}

@test "partial substitution: resolved scheme var, unresolved host var still asks" {
  run main_d 's=https; curl -s "$s://$H/x"'
  [ "$output" = "ask" ]
  run agent_d 's=https; curl -s "$s://$H/x"'
  [ "$output" = "deny" ]
}

@test "partial substitution: loop resolves the host but a second unresolved host var remains" {
  run agent_d 'for h in a.com b.com; do curl -s "https://$h.$D/x"; done'
  [ "$output" = "deny" ]
}

@test "partial substitution exposes an internal host hidden behind an unresolved path var" {
  run main_d 'for h in 169.254.169.254; do curl -s "http://$h/$p"; done'
  [ "$output" = "deny" ]
}

@test "backtick in the host: asks" {
  run main_d 'curl -s "http://`cat h.txt`/x"'
  [ "$output" = "ask" ]
}

@test "command substitution in the host: asks" {
  run main_d 'curl -s "http://$(cat h.txt)/x"'
  [ "$output" = "ask" ]
}

@test "braced unresolved host: asks" {
  run main_d 'curl -s "https://${HOST}/x"'
  [ "$output" = "ask" ]
}

# ── Must-pass shapes: unchanged / allowed ────────────────────────────────────────────────────────

@test "literal host loop resolves and allows, in both contexts" {
  run main_d 'for h in studio60 insomniacdenver; do curl -s "https://$h.reso.gl/x"; done'
  [ "$output" = "allow" ]
  run agent_d 'for h in studio60 insomniacdenver; do curl -s "https://$h.reso.gl/x"; done'
  [ "$output" = "allow" ]
}

@test "literal host loop with an unresolved PATH var still allows (partial substitution)" {
  run agent_d 'for h in a.com b.com; do curl -s "https://$h/$p"; done'
  [ "$output" = "allow" ]
}

@test "literal PATH loop glued after the host allows: its values start the path" {
  run agent_d 'for p in /guests /lists; do curl -s "https://studio60.reso.gl$p"; done'
  [ "$output" = "allow" ]
  run agent_d 'for u in /a /b; do curl -s "http://localhost:3010$u"; done'
  [ "$output" = "allow" ]
}

@test "variable after the first literal / is unchanged: \${p#/}" {
  run agent_d 'curl "http://example.com/${p#/}"'
  [ "$output" = "allow" ]
}

@test "variable after the first literal / is unchanged: \$path" {
  run agent_d 'curl "https://ok.com/$path"'
  [ "$output" = "allow" ]
}

@test "variable in the query is not the authority" {
  run agent_d 'curl -s "https://ok.com?q=$Q"'
  [ "$output" = "allow" ]
}

@test "resolved literal port assignment allows" {
  run agent_d 'PORT=3000; curl -s "http://localhost:$PORT/api/health"'
  [ "$output" = "allow" ]
}

@test "whole-URL variable keeps its No URL parsed ask — no deny, even in an agent" {
  run agent_d 'curl -s "$u"'
  [ "$output" = "ask" ]
  run agent_d 'curl -s "$BASE/a"'
  [ "$output" = "ask" ]
}

@test "argv stops at the curl's own closing ): a later echo arg is not judged" {
  run agent_d 'echo $(curl -s https://ok.com/a) http://$H/x'
  [ "$output" = "allow" ]
}

@test "a \$ in a non-curl command's URL is not judged" {
  run agent_d 'echo "http://$H/x"; curl -s https://ok.com/a'
  [ "$output" = "allow" ]
}

# ── Kill switch ──────────────────────────────────────────────────────────────────────────────────

@test "kill switch CC_CURL_HOST_DOLLAR=off restores the trunk verdict" {
  CC_CURL_HOST_DOLLAR=off run agent_d 'curl "https://harbour.reso.gl:443$A"'
  [ "$output" = "allow" ]
}
