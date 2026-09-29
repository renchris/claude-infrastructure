#!/usr/bin/env bats
# curl-gate.py — three pre-existing trunk holes (round 6, docs/research/hook-ask-confirmations-2026-09-28.md §7).
#
# 1. EMPTY HOST. curl 8.7.1 accepts 1–3 slashes after http:/https: and connects to what follows
#    (`curl -v http:/127.0.0.1:9/x` → "Trying 127.0.0.1:9"), while urlparse reads the host as empty,
#    so `http:/169.254.169.254/latest/` was an open-read ALLOW. The gate now judges the host curl
#    contacts, and asks whenever the host is still empty.
# 2. zsh `${v::=…}` (and `${v:=…}` / `${v=…}`) REASSIGNS v in /bin/zsh, which the Bash tool runs, so a
#    literal `for v in <ok>` binding no longer says where curl goes. Such a name is unresolvable.
# 3. ANSI-C `$'…'` strings honour `\'`, so `$'x\' #'` is ONE word; the lexer read the `#` as a comment
#    and ate the real curl that followed.
#
# Harness as in curl-gate-host-dollar.bats: real entrypoint, literal payloads, key on the decision.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  GATE="$REPO/hooks/curl-gate.py"
  ROOT="/Users/chrisren/Development/reso-management-app"
}

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
main_d() { run_gate main "$1" decision; }

# ── 1. empty host ────────────────────────────────────────────────────────────────────────────────

@test "http:/IMDS (one slash) is judged as the host curl contacts: deny" {
  run main_d 'curl -s http:/169.254.169.254/latest/'
  [ "$output" = "deny" ]
}

@test "http:///IMDS (three slashes) and HTTP:/ upper-case: deny" {
  run main_d 'curl -s http:///169.254.169.254/latest/'
  [ "$output" = "deny" ]
  run main_d 'curl -s HTTP:/169.254.169.254/latest/'
  [ "$output" = "deny" ]
}

@test "http:/example.com/ gets the same verdict as http://example.com/" {
  run main_d 'curl -s http://example.com/'
  want="$output"
  run main_d 'curl -s http:/example.com/'
  [ "$output" = "$want" ]
  [ "$want" = "allow" ]
}

@test "--url http:/IMDS: deny" {
  run main_d 'curl -s --url http:/169.254.169.254/latest/'
  [ "$output" = "deny" ]
}

@test "undeterminable host (no slashes, four slashes) asks" {
  run main_d 'curl -s https:169.254.169.254/'
  [ "$output" = "ask" ]
  run main_d 'curl -s http:////169.254.169.254/'
  [ "$output" = "ask" ]
}

@test "one-slash URL with a variable host is still a host-dollar ask" {
  run main_d 'read H <<< x; curl -s http:/$H/latest'
  [ "$output" = "ask" ]
}

# ── 2. zsh assign-default reassignment ───────────────────────────────────────────────────────────

@test "for-bound name reassigned by zsh u::= (IMDS) is unresolvable: not allow" {
  run main_d 'for u in "https://ok.com/"; do : ${u::=http://169.254.169.254/}; curl "$u"; done'
  [ "$output" = "ask" ]
}

@test "assigned name reassigned by the u::= / u:= / u= expansions: not allow" {
  run main_d 'u=https://ok.com/; : ${u::=http://169.254.169.254/}; curl -s "$u"'
  [ "$output" = "ask" ]
  run main_d 'u=https://ok.com/; : ${u:=http://169.254.169.254/}; curl -s "$u"'
  [ "$output" = "ask" ]
  run main_d 'u=https://ok.com/; : ${u=http://169.254.169.254/}; curl -s "$u"'
  [ "$output" = "ask" ]
}

@test "plain literal loop still resolves (control)" {
  run main_d 'for u in "https://ok.com/"; do curl -s "$u"; done'
  [ "$output" = "allow" ]
}

# ── 3. ANSI-C strings vs the comment stripper ───────────────────────────────────────────────────

@test "a \\' inside \$'…' does not turn the rest of the line into a comment: deny" {
  run main_d "echo \$'x\\' #' ; curl -s http://169.254.169.254/"
  [ "$output" = "deny" ]
}

@test "a real # comment after \$'…' still strips (control)" {
  run main_d "echo \$'a\\'b' # curl -s http://169.254.169.254/"
  [ "$output" = "allow" ]
  run main_d "curl -s http://example.com/ # \$'x\\' http://169.254.169.254/"
  [ "$output" = "allow" ]
}

@test "the ANSI-C fix is tighten-only: a command plain shlex denied stays denied" {
  # Replay row toolu_01XoDyXA8zsBqSYJrPhSHBZu: the curl is only text inside a $'…' argument, which
  # the fixed lexer reads correctly as no curl; trunk denied it unparseable, and round 6 loosens nothing.
  run main_d "t(){ :; }; t \$'echo don\\'t; curl -s https://evil.example.com/x'"
  [ "$output" = "deny" ]
}
