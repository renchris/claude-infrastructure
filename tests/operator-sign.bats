#!/usr/bin/env bats
# operator-sign — the operator-only signing library (scripts/lib/operator_sign.py) and its two CLIs,
# bin/cc-signoff (mission rows + the research namespace) and bin/cc-mission (the VOID render).
# REPORT.md §8 item 4: refuse a claude ancestor, pin content, read agent-written records as void.
#
# Every arm has a planted input that must be refused or read as void. The ancestry refusal is made
# deterministic by running the CLI under a symlink to bash whose NAME contains "claude" (ps reports
# the exec'd path; a copied /bin/bash is killed by code signing), so the test convicts the same way
# whether the suite runs inside a Claude session or under launchd. The `; exit $?` after the CLI is
# load-bearing: bash execs a single-command `-c` string in place, which replaces the fake shell and
# leaves only the suite's real ancestors to convict (measured 2026-10-05, wave E3d).

setup() {
  unset CC_BATS_ACTIVE
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/research"
  export CC_RESEARCH_REGISTRY="$CC_RESEARCH_HOME/programs.json"
  export CC_RESEARCH_RECORDS="$BATS_TEST_TMPDIR/records"
  mkdir -p "$HOME" "$CC_RESEARCH_RECORDS/cert"
  printf '{"program":"demo","version":1}\n' > "$CC_RESEARCH_RECORDS/frame.json"
  FAKE_CLAUDE="$BATS_TEST_TMPDIR/claude-fake-shell"
  ln -s /bin/bash "$FAKE_CLAUDE"
}

# py <code>: run Python with the library importable.
py() {
  /usr/bin/python3 -c "import sys; sys.path.insert(0, '$REPO/scripts/lib'); import operator_sign as o
$1"
}

# A signature line as the operator's own terminal would leave it (chain without claude).
fixture_sig() { # <action> <target|null> <pins-json> [chain-json]
  mkdir -p "$CC_RESEARCH_HOME/demo"
  printf '{"action":"%s","target":%s,"at":%s,"pins":%s,"provenance":{"claude_ancestor":false,"chain":%s}}\n' \
    "$1" "$2" "$(date +%s)" "$3" "${4:-[\"zsh\",\"kitty\"]}" >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
}

@test "research signoff under a claude ancestor is refused with exit 3 and writes nothing" {
  run "$FAKE_CLAUDE" -c "'$REPO/bin/cc-signoff' research:demo/frame --evidence frame.json; exit \$?"
  [ "$status" -eq 3 ]
  [[ "$output" == *"descended from a claude process"* ]] || false
  [ ! -e "$CC_RESEARCH_HOME/demo/signoff.jsonl" ]
}

@test "mission signoff under a claude ancestor is refused with exit 3" {
  mkdir -p "$HOME/.claude/autonomy/customer/rows"
  printf '{"id":"r1","state":"awaiting-signoff","paths":[]}\n' > "$HOME/.claude/autonomy/customer/rows/r1.json"
  run "$FAKE_CLAUDE" -c "'$REPO/bin/cc-signoff' r1 --evidence https://example.com; exit \$?"
  [ "$status" -eq 3 ]
  grep -q '"awaiting-signoff"' "$HOME/.claude/autonomy/customer/rows/r1.json"
}

@test "verdict: a chain naming claude is void even with the flag false" {
  run py 'print(o.verdict({"provenance": {"claude_ancestor": False, "chain": ["zsh", "node", "claude"]}}))'
  [ "$output" = "void" ]
}

@test "verdict: a record with no chain is void" {
  run py 'print(o.verdict({"provenance": {"claude_ancestor": False}}))'
  [ "$output" = "void" ]
}

@test "verdict: a clean chain with current pins is valid" {
  run py 'print(o.verdict({"pins": {"f": "a"}, "provenance": {"chain": ["zsh", "kitty"]}}, {"f": "a"}))'
  [ "$output" = "valid" ]
}

@test "a frame signature goes stale when one byte of the frame changes" {
  pin="$(py 'print(o.file_pin(o.kit.records_dir("demo") / "frame.json"))')"
  fixture_sig frame null "{\"frame.json\":\"$pin\"}"
  run py 'print(o.latest_valid("demo", "frame") is not None)'
  [ "$output" = "True" ]
  printf '{"program":"demo","version":2}\n' > "$CC_RESEARCH_RECORDS/frame.json"
  run py 'r = o.research_records("demo", "frame")[0]; print(r["_verdict"], o.latest_valid("demo", "frame"))'
  [ "$output" = "stale None" ]
}

@test "an agent-written research record never counts as the latest valid one" {
  pin="$(py 'print(o.file_pin(o.kit.records_dir("demo") / "frame.json"))')"
  fixture_sig frame null "{\"frame.json\":\"$pin\"}" '["zsh","claude"]'
  run py 'print(o.latest_valid("demo", "frame"))'
  [ "$output" = "None" ]
}

@test "parse_row: veto needs a decision id, and nothing else takes one" {
  run py 'print(o.parse_row("research:demo/veto"), o.parse_row("research:demo/frame/DR-1"), o.parse_row("research:demo/veto/DR-1")["target"])'
  [ "$output" = "None None DR-1" ]
}

@test "sign_research pins the frame, then refuses a second extra round set" {
  run py '
o.ancestry = lambda pid=None: [{"pid": 2, "comm": "zsh", "depth": 0}, {"pid": 3, "comm": "kitty", "depth": 1}]
rec = o.sign_research("research:demo/frame", evidence="read frame.json")
print(sorted(rec["pins"]), o.latest_valid("demo", "frame")["_verdict"])
o.sign_research("research:demo/extra-round", because="bound still wide")
try:
    o.sign_research("research:demo/extra-round", because="again")
    print("SECOND-ALLOWED")
except o.Refused as e:
    print("refused", e.code)'
  [ "${lines[0]}" = "['frame.json'] valid" ]
  [ "${lines[1]}" = "refused 2" ]
}

@test "frame and cert signatures need --evidence; reopen needs --because" {
  run py '
o.ancestry = lambda pid=None: [{"pid": 2, "comm": "zsh", "depth": 0}]
for row, kw in (("research:demo/frame", {}), ("research:demo/reopen", {})):
    try:
        o.sign_research(row, **kw); print("ALLOWED")
    except o.Refused:
        print("refused")'
  [ "$output" = "$(printf 'refused\nrefused')" ]
}

@test "a cert signature with no certificate on disk is refused" {
  run py '
o.ancestry = lambda pid=None: [{"pid": 2, "comm": "zsh", "depth": 0}]
try:
    o.sign_research("research:demo/cert", evidence="cert"); print("ALLOWED")
except o.Refused:
    print("refused")'
  [ "$output" = "refused" ]
}

@test "the mission board lists a signed row whose chain names claude as VOID" {
  ROWS="$HOME/.claude/autonomy/customer/rows"
  mkdir -p "$ROWS"
  printf '{"id":"v1","lead":"L","venue":"V","artifact":"floor-plan","state":"signed","signoff":{"at":1,"pins":{},"provenance":{"claude_ancestor":false,"chain":["zsh","claude"]}}}\n' > "$ROWS/v1.json"
  run "$REPO/bin/cc-mission" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"VOID (agent-written signature)"* ]]
}

@test "the mission board lists a signed row with no recorded chain as VOID" {
  ROWS="$HOME/.claude/autonomy/customer/rows"
  mkdir -p "$ROWS"
  printf '{"id":"v2","lead":"L","venue":"V","artifact":"floor-plan","state":"signed","signoff":{"at":1,"pins":{},"provenance":{"claude_ancestor":false}}}\n' > "$ROWS/v2.json"
  run "$REPO/bin/cc-mission" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"VOID (agent-written signature)"* ]]
}

# ── the implementation signature (method v1.2, REPORT.md §11; wave E3d) ─────────────────────────

# built <n> / registered <state>: a built certificate on disk, and the program's registry state.
built() {
  mkdir -p "$CC_RESEARCH_RECORDS/built"
  printf '{"cert":"BUILT-CERT-v%s","program":"demo","version":%s}\n' "$1" "$1" > "$CC_RESEARCH_RECORDS/built/BUILT-CERT-v$1.json"
}
registered() {
  /usr/bin/python3 -c "import sys; sys.path.insert(0, '$REPO/scripts/research-kit/lib'); import kit
kit.registry_set('demo', '$1', cwd_roots=['$BATS_TEST_TMPDIR'])"
}
OPERATOR='o.ancestry = lambda pid=None: [{"pid": 2, "comm": "zsh", "depth": 0}, {"pid": 3, "comm": "kitty", "depth": 1}]'

@test "E3d parse_row: implementation is a research action and takes no target" {
  run py 'print(o.parse_row("research:demo/implementation")["action"], o.parse_row("research:demo/implementation/DR-1"))'
  [ "$output" = "implementation None" ]
}

@test "E3d an implementation signature under a claude ancestor is refused with exit 3 and writes nothing" {
  built 1; registered build-certified
  run "$FAKE_CLAUDE" -c "'$REPO/bin/cc-signoff' research:demo/implementation --evidence built/BUILT-CERT-v1.md; exit \$?"
  [ "$status" -eq 3 ]
  [[ "$output" == *"descended from a claude process ($FAKE_CLAUDE at depth 1)"* ]] || false
  [[ "$output" == *"cc-signoff research:demo/implementation --evidence <what you read>"* ]] || false
  [ ! -e "$CC_RESEARCH_HOME/demo/signoff.jsonl" ]
}

@test "E3d an implementation signature pins the newest built certificate by path and hash" {
  built 1; built 2; registered build-certified
  run py "$OPERATOR"'
rec = o.sign_research("research:demo/implementation", evidence="read BUILT-CERT-v2.md")
print(sorted(rec["pins"]), rec["pins"]["built/BUILT-CERT-v2.json"] == o.file_pin(o.kit.records_dir("demo") / "built" / "BUILT-CERT-v2.json"))
print(o.implementation_state("demo")["status"], o.implementation_state("demo")["cert"])'
  [ "${lines[0]}" = "['built/BUILT-CERT-v2.json'] True" ]
  [ "${lines[1]}" = "signed BUILT-CERT-v2" ]
}

@test "E3d an implementation signature needs --evidence" {
  built 1; registered build-certified
  run py "$OPERATOR"'
try:
    o.sign_research("research:demo/implementation"); print("ALLOWED")
except o.Refused as e:
    print("refused", e.code, "--evidence is required" in str(e))'
  [ "$output" = "refused 2 True" ]
  [ ! -e "$CC_RESEARCH_HOME/demo/signoff.jsonl" ]
}

@test "E3d an implementation signature with no built certificate on disk is refused" {
  registered build-certified
  run py "$OPERATOR"'
try:
    o.sign_research("research:demo/implementation", evidence="x"); print("ALLOWED")
except o.Refused as e:
    print("refused", e.code, "no built certificate" in str(e))'
  [ "$output" = "refused 2 True" ]
}

@test "E3d an implementation signature is refused while the program is not build-certified" {
  built 1
  for s in certified build-certifying closed; do
    registered "$s"
    run py "$OPERATOR"'
try:
    o.sign_research("research:demo/implementation", evidence="x"); print("ALLOWED")
except o.Refused as e:
    print("refused", e.code, "build-certified" in str(e))'
    [ "$output" = "refused 2 True" ]
  done
  [ ! -e "$CC_RESEARCH_HOME/demo/signoff.jsonl" ]
}

@test "E3d an implementation signature goes stale when one byte of the built certificate changes" {
  built 1; registered build-certified
  py "$OPERATOR"'
o.sign_research("research:demo/implementation", evidence="read it")'
  run py 'print(o.implementation_state("demo")["status"])'
  [ "$output" = "signed" ]
  printf ' ' >> "$CC_RESEARCH_RECORDS/built/BUILT-CERT-v1.json"
  run py 'print(o.implementation_state("demo")["status"], o.latest_valid("demo", "implementation"))'
  [ "$output" = "stale None" ]
}

@test "E3d an agent-written implementation record is void and never counts as signed" {
  built 1; registered build-certified
  pin="$(py 'print(o.file_pin(o.kit.records_dir("demo") / "built" / "BUILT-CERT-v1.json"))')"
  fixture_sig implementation null "{\"built/BUILT-CERT-v1.json\":\"$pin\"}" '["zsh","claude"]'
  run py 'print(o.implementation_state("demo")["status"])'
  [ "$output" = "void" ]
  : > "$CC_RESEARCH_HOME/demo/signoff.jsonl"
  printf '{"action":"implementation","target":null,"at":1,"pins":{"built/BUILT-CERT-v1.json":"%s"},"provenance":{"claude_ancestor":false}}\n' "$pin" >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
  run py 'print(o.implementation_state("demo")["status"])'
  [ "$output" = "void" ]
}

@test "E3d a signature on an older built certificate does not cover the newest one" {
  built 1; registered build-certified
  py "$OPERATOR"'
o.sign_research("research:demo/implementation", evidence="read it")'
  built 2
  run py 's = o.implementation_state("demo"); print(s["status"], s["cert"])'
  [ "$output" = "superseded BUILT-CERT-v2" ]
  run py 'print(o.implementation_state("nothing-built-here-x")["status"])'
  [ "$output" = "unsigned" ]
}

@test "E3d the fixture signer refuses the live research store" {
  run env -u CC_RESEARCH_HOME "$REPO/tests/fixtures/research-kit/fixture_signer.py" research:demo/implementation --evidence x
  [ "$status" -eq 2 ]
  [[ "$output" == *"fixtures only"* ]] || false
  live="$(/usr/bin/python3 -c "import os,pwd; print(pwd.getpwuid(os.getuid()).pw_dir)")/.claude/autonomy/research"
  CC_RESEARCH_HOME="$live" run "$REPO/tests/fixtures/research-kit/fixture_signer.py" research:demo/implementation --evidence x
  [ "$status" -eq 2 ]
  [[ "$output" == *"fixtures only"* ]]
}
