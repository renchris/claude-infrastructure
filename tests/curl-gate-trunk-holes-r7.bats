#!/usr/bin/env bats
# curl-gate.py — three pre-existing trunk holes found in round 7 (docs/research/hook-ask-confirmations-2026-09-28.md §7).
#
# 1. BACKSLASH AUTH-SWITCH. `http://169.254.169.254\@api.github.com/x` was an allow to "allowlisted
#    host api.github.com": urlparse takes the host after the last `@`, while a WHATWG reading ends the
#    authority at the `\`. Every reading is judged now and the strictest wins.
# 2. FUNCTION / ALIAS BODY. main()'s entry filter split statements on `[;&|\n]`, `$(`, backtick and `(`
#    only, so `f(){ curl …; }` and `function f { curl …; }` were never judged, and an alias value is a
#    single word the pipeline never reads as a command.
# 3. CASE PATTERN. `case a in a) curl …;; esac` — the `)` of a pattern did not end a statement either.
#
# Harness as in curl-gate-trunk-holes.bats: real entrypoint, literal payloads, key on the decision.

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
agent_d() { run_gate agent "$1" decision; }

# ── 1. backslash in the authority ────────────────────────────────────────────────────────────────

@test "backslash auth-switch, literal: IMDS before the \\@ is denied, not read as api.github.com" {
  run main_d 'curl -s "http://169.254.169.254\@api.github.com/x"'
  [ "$output" = "deny" ]
  run main_d 'curl -s http://169.254.169.254\\@api.github.com/x'
  [ "$output" = "deny" ]
  run agent_d 'curl -s "http://169.254.169.254\@api.github.com/x"'
  [ "$output" = "deny" ]
}

@test "backslash auth-switch through an assignment and a literal for-list: deny" {
  run main_d 'u="http://169.254.169.254\@api.github.com/x"; curl -s "$u"'
  [ "$output" = "deny" ]
  run main_d 'for u in "http://169.254.169.254\@api.github.com/x"; do curl -s "$u"; done'
  [ "$output" = "deny" ]
}

# curl 8.7.1 refuses a `\` in the host itself ("URL rejected: Bad hostname"), so the WHATWG reading
# is the only one that can name a target: IMDS there denies, a public host keeps trunk's verdict.
@test "a backslash inside the host: the strictest reading wins, a public one keeps its verdict" {
  run main_d 'curl -s "http://169.254.169.254\.x/y"'
  [ "$output" = "deny" ]
  run main_d "curl -s 'https://www\.example\.com/x'"
  [ "$output" = "allow" ]
}

@test "multi-URL: a bracketed authority behind an earlier ask stays an ask, not an internal error" {
  run main_d "curl -s ftp://example.com/a 'https://[^x\\\\]/b'"
  [ "$output" = "ask" ]
}

@test "alias fallback: the words alias and curl in an untokenisable heredoc are not an alias" {
  run main_d "$(printf 'cat > /tmp/x.md <<EOF\nuse an alias, not curl\nit'"'"'s\nEOF\ncurl -s https://api.github.com/x')"
  [ "$output" = "allow" ]
}

@test "control: a backslash in the PATH changes nothing" {
  run main_d 'curl -s "https://api.github.com/repos/a\b"'
  [ "$output" = "allow" ]
}

# ── 2. function and alias bodies ─────────────────────────────────────────────────────────────────

@test "f(){ curl IMDS; }; f is judged: deny" {
  run main_d 'f(){ curl -s http://169.254.169.254/x; }; f'
  [ "$output" = "deny" ]
}

@test "function f { curl IMDS; }; f is judged: deny" {
  run main_d 'function f { curl -s http://169.254.169.254/x; }; f'
  [ "$output" = "deny" ]
}

@test "alias whose value is a curl is judged as that curl: deny" {
  run main_d 'alias g="curl -s http://169.254.169.254/x"; g'
  [ "$output" = "deny" ]
  run main_d "alias -g g='curl -s http://169.254.169.254/x'"
  [ "$output" = "deny" ]
}

@test "control: an alias to an allowlisted read stays allowed" {
  run main_d 'alias g="curl -s https://api.github.com/x"; g'
  [ "$output" = "allow" ]
}

# ── 3. case patterns ─────────────────────────────────────────────────────────────────────────────

@test "case a in a) curl IMDS;; esac is judged: deny" {
  run main_d 'case a in a) curl -s http://169.254.169.254/x;; esac'
  [ "$output" = "deny" ]
}

@test "case a in *) curl IMDS;; esac is judged: deny" {
  run main_d 'case a in *) curl -s http://169.254.169.254/x;; esac'
  [ "$output" = "deny" ]
}

@test "control: a command with no curl statement stays unjudged" {
  run main_d 'echo {curl,wget}'
  [ "$output" = "allow" ]
}
