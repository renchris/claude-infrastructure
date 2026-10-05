#!/usr/bin/env bats
# research-kit-built-states — the two Stage 9 registry states of research method v1.2 (REPORT.md §11
# "When" and "The forecast splits in two"): `gate.sh built-freeze` enters build-certifying, every
# reader of the registry state (the resolver, the Stop hook's copy, the prompt nudge, the router's
# block, the scheduled jobs, `gate.sh requires`, `gate.sh render`) treats build-certifying and
# build-certified as active, and the research certificate states the forecast split.
#
# One known-good program (tests/fixtures/research-kit/build_good.py) is certified once under method
# 1.1, then its frame is moved to 1.2 and an operator cert signature is planted, because rows 18-19
# of a 1.2 frame are other modules' work. Every test restores that state and plants ONE input.

setup_file() {
  export HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$HOME"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "$CC_NOW" > "$BATS_FILE_TMPDIR/now"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  export CC_DECISIONS_DIR="$W/decisions" CC_IDL="$W/idl.jsonl"
  export CC_RESEARCH_ROUTER="$W/router.sh" CC_RESEARCH_CALIBRATION="$W/calibration.jsonl"
  mkdir -p "$W"
  REC="$("$BATS_TEST_DIRNAME/fixtures/research-kit/build_good.py" "$W")"
  echo "$REC" > "$BATS_FILE_TMPDIR/records-path"
  "$REPO/scripts/research-kit/gate.sh" run --program demo >/dev/null
  /usr/bin/python3 - "$REPO" "$REC" <<'PY'
import json, sys, time
repo, rec = sys.argv[1], sys.argv[2]
sys.path[:0] = [repo + "/scripts/research-kit/lib", repo + "/scripts/lib"]
import kit, operator_sign
from pathlib import Path
p = Path(rec) / "frame.json"
d = json.loads(p.read_text()); d["method_version"] = "1.2"; p.write_text(json.dumps(d))
sig = {"row": "research:demo/cert", "action": "cert", "target": None, "at": time.time(),
       "pins": {"cert/CERT-v1.json": operator_sign.file_pin(Path(rec) / "cert" / "CERT-v1.json")},
       "provenance": {"claude_ancestor": False, "chain": ["zsh", "kitty"]}}
with open(kit.sealed_dir("demo") / "signoff.jsonl", "a") as f:
    f.write(json.dumps(sig) + "\n")
PY
  ART="$W/artifact"
  mkdir -p "$ART"
  git -C "$ART" init -q
  git -C "$ART" config user.email t@example.com
  git -C "$ART" config user.name t
  echo one > "$ART/a.txt"
  git -C "$ART" add a.txt
  git -C "$ART" commit -qm built
  cp -Rp "$W" "$BATS_FILE_TMPDIR/golden"
}

setup() {
  export HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$HOME"
  unset CC_BATS_ACTIVE CC_RESEARCH_RECORDS CC_RESEARCH_BIN CC_RESEARCH_BLOCK CC_RESEARCH_ROUTER CC_RESEARCH_ROUTER_INNER
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  G="$REPO/scripts/research-kit/gate.sh"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(cat "$BATS_FILE_TMPDIR/now")"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions" CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_RESEARCH_CALIBRATION="$W/calibration.jsonl"
  export CC_RESEARCH_CLASSIFIER="$REPO/tests/fixtures/research-router/classifier-stub.sh"
  export CC_RESEARCH_CLASSIFIER_TIMEOUT=2
  export CC_RESEARCH_RENDER='printf "Research: demo version 1. CERTIFIED\n"'
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  REC="$(cat "$BATS_FILE_TMPDIR/records-path")"
  ART="$(cd "$W/artifact" && pwd -P)"
  ROOT="$(/usr/bin/python3 -c "import json; print(json.load(open('$CC_RESEARCH_REGISTRY'))['programs'][0]['cwd_roots'][0])")"
}

state() { /usr/bin/python3 -c "import json; print(json.load(open('$CC_RESEARCH_REGISTRY'))['programs'][0]['state'])"; }
# setstate <state>: the fixture writes the registry directly; the readers under test only read it.
setstate() {
  /usr/bin/python3 -c "import json; p='$CC_RESEARCH_REGISTRY'; d=json.load(open(p)); d['programs'][0]['state']='$1'; json.dump(d, open(p, 'w'))"
}
# jedit <file under REC> <python statement over d>: edit a JSON record in place.
jedit() {
  /usr/bin/python3 -c "import json; p='$REC/$1'; d=json.load(open(p)); $2; json.dump(d, open(p, 'w'))"
}
field() { /usr/bin/python3 -c "import json; print(json.load(open('$REC/$1'))['$2'])"; }
freeze() { "$G" built-freeze --program demo --artifact "$ART" "$@"; }
signoff() { printf '%s\n' "$1" >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"; }
# prompt <text> / tool <name>: one UserPromptSubmit and one PreToolUse through the real hooks.
prompt() {
  jq -nc --arg p "$1" --arg c "$ROOT" '{session_id:"s1",cwd:$c,prompt:$p}' \
    | bash "$REPO/hooks/research-precognition-nudge.sh"
}
tool() {
  jq -nc --arg t "$1" --arg c "$ROOT" '{session_id:"s1",cwd:$c,tool_name:$t,tool_input:{prompt:"x",description:"x"}}' \
    | bash "$REPO/hooks/research-block.sh" | jq -r '.hookSpecificOutput.permissionDecision // empty' | grep -q deny \
    && echo deny || echo allow
}

# ── rule 2: the verb ─────────────────────────────────────────────────────────────────────────────

@test "built-freeze on a signed 1.2 certificate pins the artifact's HEAD and sets build-certifying" {
  run freeze --wave W1 --wave W2
  [ "$status" -eq 0 ]
  [ "$(state)" = "build-certifying" ]
  [ "$(field built/freeze.json snapshot_sha)" = "$(git -C "$ART" rev-parse HEAD)" ]
  [ "$(field built/freeze.json artifact_root)" = "$ART" ]
  [ "$(field built/freeze.json frozen_at)" = "$CC_NOW" ]
  [ "$(field built/freeze.json research_cert)" = "CERT-v1" ]
  [ "$(field built/freeze.json waves_done)" = "['W1', 'W2']" ]
}

@test "a second built-freeze while build-certifying re-pins the snapshot a fix moved" {
  freeze --wave W1
  first="$(field built/freeze.json snapshot_sha)"
  echo two > "$ART/a.txt"
  git -C "$ART" commit -qam fix
  run freeze --wave W1
  [ "$status" -eq 0 ]
  [ "$(field built/freeze.json snapshot_sha)" = "$(git -C "$ART" rev-parse HEAD)" ]
  [ "$(field built/freeze.json snapshot_sha)" != "$first" ]
  [ "$(state)" = "build-certifying" ]
}

@test "built-freeze from build-certified is refused without --refreeze, and re-enters build-certifying with it" {
  freeze --wave W1
  setstate build-certified
  run freeze --wave W1
  [ "$status" -eq 2 ]
  [[ "$output" == *"--refreeze"* ]] || false
  [ "$(state)" = "build-certified" ]
  run freeze --refreeze
  [ "$status" -eq 0 ]
  [ "$(state)" = "build-certifying" ]
}

# ── rule 1: the refusals ─────────────────────────────────────────────────────────────────────────

@test "built-freeze refuses a frame that is not method 1.2" {
  jedit frame.json "d['method_version'] = '1.1'"
  run freeze --wave W1
  [ "$status" -eq 2 ]
  [[ "$output" == *"method 1.2"* ]] || false
  [ ! -e "$REC/built/freeze.json" ]
}

@test "built-freeze refuses a program whose registry state is not certified" {
  setstate certifying
  run freeze --wave W1
  [ "$status" -eq 2 ]
  [[ "$output" == *"'certifying'"* ]] || false
  [ "$(state)" = "certifying" ]
}

@test "built-freeze refuses when the newest certificate has a FAIL row" {
  jedit cert/CERT-v1.json "d['rows']['11'] = 'FAIL'"
  signoff "$(/usr/bin/python3 - "$REPO" "$REC" <<'PY'
import json, sys, time
sys.path[:0] = [sys.argv[1] + "/scripts/research-kit/lib", sys.argv[1] + "/scripts/lib"]
import operator_sign
from pathlib import Path
print(json.dumps({"action": "cert", "target": None, "at": time.time(),
    "pins": {"cert/CERT-v1.json": operator_sign.file_pin(Path(sys.argv[2]) / "cert" / "CERT-v1.json")},
    "provenance": {"claude_ancestor": False, "chain": ["zsh", "kitty"]}}))
PY
)"
  run freeze --wave W1
  [ "$status" -eq 2 ]
  [[ "$output" == *"FAIL row(s) 11"* ]] || false
  [ "$(state)" = "certified" ]
}

@test "built-freeze refuses when the only cert signature was written under an agent" {
  /usr/bin/python3 - "$CC_RESEARCH_HOME/demo/signoff.jsonl" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for r in rows:
    if r.get("action") == "cert":
        r["provenance"]["chain"] = ["claude"]
open(sys.argv[1], "w").write("".join(json.dumps(r) + "\n" for r in rows))
PY
  run freeze --wave W1
  [ "$status" -eq 2 ]
  [[ "$output" == *"no valid operator signature"* ]] || false
  [ "$(state)" = "certified" ]
}

@test "built-freeze refuses a signature that pins an older certificate than the newest" {
  cp "$REC/cert/CERT-v1.json" "$REC/cert/CERT-v2.json"
  run freeze --wave W1
  [ "$status" -eq 2 ]
  [[ "$output" == *"no valid operator signature"*"CERT-v2"* ]] || false
}

@test "built-freeze refuses when a valid reopen is signed after the certificate" {
  signoff '{"action":"reopen","target":null,"at":9e9,"pins":{},"because":"x","provenance":{"claude_ancestor":false,"chain":["zsh","kitty"]}}'
  run freeze --wave W1
  [ "$status" -eq 2 ]
  [[ "$output" == *"reopen"* ]] || false
  [ "$(state)" = "certified" ]
}

@test "built-freeze refuses a relative --artifact" {
  cd "$W"
  run "$G" built-freeze --program demo --artifact artifact
  [ "$status" -eq 2 ]
  [[ "$output" == *"not an absolute path"* ]] || false
}

@test "built-freeze refuses an --artifact that is not a git work tree" {
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  run "$G" built-freeze --program demo --artifact "$BATS_TEST_TMPDIR/plain"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a git work tree"* ]] || false
}

@test "built-freeze refuses a dirty work tree" {
  echo stray > "$ART/untracked.txt"
  run freeze --wave W1
  [ "$status" -eq 2 ]
  [[ "$output" == *"uncommitted"* ]] || false
  [ "$(state)" = "certified" ]
}

# ── rules 3-4: the resolver and its two copies ───────────────────────────────────────────────────

@test "rp_is_active is true in build-certifying and build-certified, and still false when closed" {
  local s
  for s in build-certifying build-certified; do
    setstate "$s"
    run /bin/bash -c '. "$1"; rp_is_active "$2"' _ "$REPO/scripts/lib/research-program.sh" "$ROOT"
    [ "$status" -eq 0 ]
  done
  setstate closed
  run /bin/bash -c '. "$1"; rp_is_active "$2"' _ "$REPO/scripts/lib/research-program.sh" "$ROOT"
  [ "$status" -eq 1 ]
}

@test "completion-assert's own prompt key accepts a program named in the prompt in either build state" {
  # The hook's three resolver functions, lifted out of the hook and run under /bin/bash 3.2.
  fn="$(sed -n '/^_ca_rp_lib() {/,/^if \[ "\$d4" -eq 1 \]/p' "$REPO/hooks/completion-assert.sh" | sed '$d')"
  [[ "$fn" == *"_ca_rp_prompt_active() {"* ]] || false
  export CC_RESEARCH_PROGRAM_LIB="$REPO/scripts/lib/research-program.sh"
  local s
  for s in build-certifying build-certified; do
    setstate "$s"
    run /bin/bash -c 'eval "$1"; _ca_rp_prompt_active "is demo done?" && printf "%s" "$_RP_RESULT"' _ "$fn"
    [ "$status" -eq 0 ]
    [ "$output" = "demo $s" ]
  done
  setstate closed
  run /bin/bash -c 'eval "$1"; _ca_rp_prompt_active "is demo done?"' _ "$fn"
  [ "$status" -eq 1 ]
}

@test "the prompt nudge stays silent for a work order in either build state" {
  local s
  for s in build-certifying build-certified; do
    setstate "$s"
    run prompt "build it: research the options for caching"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
  setstate closed
  run prompt "build it: research the options for caching"
  [[ "$output" == *"PRE-COGNITION"* ]] || false
}

# ── rule 5: the research block and the scheduled jobs ────────────────────────────────────────────

@test "the research block is on in either build state: a completeness turn denies Agent" {
  local s
  for s in build-certifying build-certified; do
    setstate "$s"
    prompt "are we done?" >/dev/null
    [ "$(tool Agent)" = deny ]
  done
  setstate closed
  prompt "are we done?" >/dev/null
  [ "$(tool Agent)" = allow ]
}

@test "job sweep with no --program visits a program in either build state" {
  local s
  for s in build-certifying build-certified; do
    setstate "$s"
    run /usr/bin/python3 "$REPO/bin/cc-research" job sweep
    [ "$status" -eq 0 ]
    [[ "$output" == *"job sweep demo: ok"* ]] || false
  done
}

# ── rule 6: requires ─────────────────────────────────────────────────────────────────────────────

@test "requires lets a build wave fire in certified and in both build states" {
  local s
  for s in certified build-certifying build-certified; do
    setstate "$s"
    run "$G" requires --program demo --wave B1
    [ "$status" -eq 0 ]
    [[ "$output" == "CLEAR demo wave B1: CERT-v1"* ]] || false
  done
}

@test "requires still refuses in registered and in certifying" {
  local s
  for s in registered certifying; do
    setstate "$s"
    run "$G" requires --program demo --wave B1
    [ "$status" -eq 1 ]
    [[ "$output" == *"registry state is '$s'"* ]] || false
  done
}

# ── rule 7: render ───────────────────────────────────────────────────────────────────────────────

@test "render in build-certifying prints the research certificate's lines plus the frozen Built line" {
  freeze --wave W1
  run "$G" render --program demo
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "Research: demo version 1. CERTIFIED"* ]] || false
  [[ "$output" == *"Signed frame: 100.00% closed."* ]] || false
  [ "${lines[${#lines[@]}-1]}" = "Built: frozen $(field built/freeze.json frozen_at), not yet certified" ]
}

@test "render in build-certified names the built certificate and its issue date" {
  freeze --wave W1
  issued="$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"cert":"BUILT-CERT-v1","version":1,"issued":"%s"}\n' "$issued" > "$REC/built/BUILT-CERT-v1.json"
  setstate build-certified
  run "$G" render --program demo
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "Research: demo version 1. CERTIFIED"* ]] || false
  [ "${lines[${#lines[@]}-1]}" = "Built: certified $issued (BUILT-CERT-v1) · implementation not signed" ]
}

@test "render in certified prints no Built line of this kind" {
  run "$G" render --program demo
  [ "$status" -eq 0 ]
  [[ "$output" != *"Built: frozen"* ]] || false
  [[ "$output" != *"Built: certified"* ]] || false
}

@test "E3c: in a build state the research lines drop their placeholder 'Built –', so render never says both" {
  freeze --wave W1
  run "$G" render --program demo
  [ "$status" -eq 0 ]
  [[ "$output" != *"Built –"* ]] || false
  [[ "$output" == *"Live – · Calibration: "* ]] || false
  # certified, before Stage 9, keeps the placeholder: the kit holds no build record yet
  setstate certified
  run "$G" render --program demo
  [[ "$output" == *"Built – · Live – · Calibration: "* ]]
}

# ── rules 8-9: the forecast split ────────────────────────────────────────────────────────────────

# issue: write the next certificate from 19 passing rows and print its forecast as JSON.
issue() {
  /usr/bin/python3 - "$REPO" <<'PY'
import json, sys
repo = sys.argv[1]
sys.path[:0] = [repo + "/scripts/research-kit/lib", repo + "/scripts/research-kit", repo + "/scripts/lib"]
import gate, gate_cert, kit
ctx = gate.make_ctx("demo")
path = gate_cert.write_certificate(ctx, [gate.Row(n, "row", gate.PASS) for n in range(1, 20)])
print(json.dumps(dict(json.load(open(path))["forecast"], share_const=kit.BUILD_FINDABLE_SHARE)))
PY
}

@test "a 1.2 certificate's forecast carries the split: the mean by the assumed share, the bound unsplit" {
  run issue
  [ "$status" -eq 0 ]
  run /usr/bin/python3 -c "
import json, sys
f = json.loads(sys.argv[1])
total = f['desk_mean'] + f['invisible_mean']
assert f['build_findable_share'] == f['share_const'], f
assert abs(f['before_impl_mean'] - f['share_const'] * total) < 1e-3, f
assert abs(f['after_impl_mean'] - (1 - f['share_const']) * total) < 1e-3, f
assert f['after_impl_bound95'] == f['desk_n95'] + f['invisible_bound95'], f
" "$output"
  [ "$status" -eq 0 ]
  grep -q '^Split: before implementation signoff about ' "$REC/cert/CERT-v2.md"
}

@test "a 1.1 certificate's forecast carries no split keys and its text no Split line" {
  jedit frame.json "d['method_version'] = '1.1'"
  run issue
  [ "$status" -eq 0 ]
  [[ "$output" != *"impl"* ]] || false
  [[ "$output" != *"build_findable_share"* ]] || false
  run grep -c '^Split:' "$REC/cert/CERT-v2.md"
  [ "$output" = "0" ]
}

@test "the Split line prints directly after the After-signoff line, only when the certificate carries the keys" {
  run "$G" render --program demo
  [[ "$output" != *"Split:"* ]] || false
  jedit cert/CERT-v1.json "d['forecast'].update(build_findable_share=0.585, before_impl_mean=1.17, after_impl_mean=0.83, after_impl_bound95=7)"
  run "$G" render --program demo
  [ "$status" -eq 0 ]
  at="$(printf '%s\n' "$output" | grep -n '^After signoff:' | cut -d: -f1)"
  [ -n "$at" ]
  [ "$(printf '%s\n' "$output" | sed -n "$((at + 1))p")" = "Split: before implementation signoff about 1.2 · after implementation signoff about 0.8 (at most 7 at 95%); build-findable share 0.585, share assumed" ]
}

# ── E3d: the implementation signature (REPORT.md §11 "Signing the implementation") ──────────────
# built_certified: a frozen snapshot, one built certificate on disk, registry build-certified.
built_certified() {
  freeze --wave W1
  printf '{"cert":"BUILT-CERT-v1","program":"demo","version":1,"issued":"%s"}\n' "$CC_NOW" > "$REC/built/BUILT-CERT-v1.json"
  setstate build-certified
}
# lib_sign: the signing library's own call with an operator's chain; it writes only the sealed log.
lib_sign() {
  /usr/bin/python3 -c "import sys; sys.path.insert(0, '$REPO/scripts/lib'); import operator_sign as o
o.ancestry = lambda pid=None: [{'pid': 2, 'comm': 'zsh', 'depth': 0}, {'pid': 3, 'comm': 'kitty', 'depth': 1}]
o.sign_research('research:demo/implementation', evidence='read BUILT-CERT-v1.md')"
}
# rechain <json list>: rewrite the chain of every implementation record, as a hand-written record would carry it.
rechain() {
  /usr/bin/python3 -c "import json, sys
p = '$CC_RESEARCH_HOME/demo/signoff.jsonl'
rows = [json.loads(l) for l in open(p) if l.strip()]
for r in rows:
    if r.get('action') == 'implementation':
        r['provenance']['chain'] = json.loads(sys.argv[1])
open(p, 'w').write(''.join(json.dumps(r) + '\n' for r in rows))" "$1"
}
SIGNER() { "$REPO/tests/fixtures/research-kit/fixture_signer.py" "$@"; }

@test "E3d built-signed refuses a built certificate nobody signed, and names the operator's command" {
  built_certified
  run "$G" built-signed --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"BUILT-CERT-v1 carries no operator signature"* ]] || false
  [[ "$output" == *"cc-signoff research:demo/implementation --evidence <what you read>"* ]] || false
  [ "$(state)" = "build-certified" ]
}

@test "E3d built-signed moves build-certified to implementation-signed on a valid operator signature" {
  built_certified; lib_sign
  [ "$(state)" = "build-certified" ]
  run "$G" built-signed --program demo
  [ "$status" -eq 0 ]
  [[ "$output" == "IMPLEMENTATION-SIGNED demo: BUILT-CERT-v1"*"registry -> implementation-signed" ]] || false
  [ "$(state)" = "implementation-signed" ]
}

@test "E3d built-signed refuses an agent-written signature and says it is void" {
  built_certified; lib_sign
  rechain '["zsh","claude"]'
  run "$G" built-signed --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"VOID"* ]] || false
  [ "$(state)" = "build-certified" ]
}

@test "E3d built-signed refuses a signature the built certificate changed under, and un-signs the registry" {
  built_certified; lib_sign
  "$G" built-signed --program demo
  printf ' ' >> "$REC/built/BUILT-CERT-v1.json"
  run "$G" built-signed --program demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE"*"registry -> build-certified"* ]] || false
  [ "$(state)" = "build-certified" ]
}

@test "E3d built-signed refuses a program that is not build-certified" {
  freeze --wave W1
  run "$G" built-signed --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"build-certifying"* ]] || false
  [ "$(state)" = "build-certifying" ]
}

@test "E3d the operator's one cc-signoff command signs and hands the registry move to gate.sh" {
  built_certified
  run SIGNER research:demo/implementation --evidence "read BUILT-CERT-v1.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SIGNED research:demo/implementation"* ]] || false
  [[ "$output" == *"pinned built/BUILT-CERT-v1.json = "* ]] || false
  [[ "$output" == *"registry -> implementation-signed"* ]] || false
  [ "$(state)" = "implementation-signed" ]
  grep -q '"fixture-signer"' "$CC_RESEARCH_HOME/demo/signoff.jsonl"
}

@test "E3d cc-signoff under a claude ancestor signs nothing and the registry stays build-certified" {
  built_certified
  ln -s /bin/bash "$BATS_TEST_TMPDIR/claude-fake-shell"
  before="$(wc -l < "$CC_RESEARCH_HOME/demo/signoff.jsonl")"
  # `; exit $?` keeps the fake shell alive as the CLI's parent (a lone -c command is exec'd in place)
  run "$BATS_TEST_TMPDIR/claude-fake-shell" -c "'$REPO/bin/cc-signoff' research:demo/implementation --evidence x; exit \$?"
  [ "$status" -eq 3 ]
  [[ "$output" == *"claude-fake-shell at depth 1"* ]] || false
  [ "$(wc -l < "$CC_RESEARCH_HOME/demo/signoff.jsonl")" = "$before" ]
  [ "$(state)" = "build-certified" ]
}

@test "E3d close refuses a build-certified program whose implementation is not signed" {
  built_certified
  run "$G" close --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"close refused"*"cc-signoff research:demo/implementation"* ]] || false
  [ "$(state)" = "build-certified" ]
}

@test "E3d close refuses implementation-signed when the signature went stale, and closes when it holds" {
  built_certified; lib_sign
  "$G" built-signed --program demo
  cp "$REC/built/BUILT-CERT-v1.json" "$BATS_TEST_TMPDIR/keep.json"
  printf ' ' >> "$REC/built/BUILT-CERT-v1.json"
  run "$G" close --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"STALE"* ]] || false
  [ "$(state)" = "implementation-signed" ]
  cp "$BATS_TEST_TMPDIR/keep.json" "$REC/built/BUILT-CERT-v1.json"
  run "$G" close --program demo
  [ "$status" -eq 0 ]
  [ "$(state)" = "closed" ]
}

@test "E3d close of a program that never entered Stage 9 needs no implementation signature" {
  run "$G" close --program demo
  [ "$status" -eq 0 ]
  [ "$(state)" = "closed" ]
}

@test "E3d requires admits a wave in implementation-signed only while the signature holds" {
  built_certified; lib_sign
  "$G" built-signed --program demo
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 0 ]
  printf ' ' >> "$REC/built/BUILT-CERT-v1.json"
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 1 ]
  [[ "$output" == *"implementation-signed"*"STALE"* ]]
}

@test "E3d requires --after-signoff refuses a wave until the implementation is signed" {
  built_certified
  run "$G" requires --program demo --wave B1 --after-signoff
  [ "$status" -eq 1 ]
  [[ "$output" == *"follows implementation signoff"*"cc-signoff research:demo/implementation"* ]] || false
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 0 ]
  lib_sign
  "$G" built-signed --program demo
  run "$G" requires --program demo --wave B1 --after-signoff
  [ "$status" -eq 0 ]
}

@test "E3d handoff-fire --gate-after-signoff refuses a post-signoff wave on an unsigned implementation" {
  built_certified
  echo "TASK — post-signoff wave fixture payload." > "$BATS_TEST_TMPDIR/p.txt"
  run bash "$REPO/scripts/handoff-fire.sh" --prompt-file "$BATS_TEST_TMPDIR/p.txt" --dry-run --requires-gate demo --gate-wave B1 --gate-after-signoff
  [ "$status" -eq 2 ]
  [[ "$output" == *"research gate REFUSES this build wave"*"follows implementation signoff"* ]] || false
  run bash "$REPO/scripts/handoff-fire.sh" --prompt-file "$BATS_TEST_TMPDIR/p.txt" --dry-run --gate-after-signoff
  [ "$status" -eq 2 ]
  [[ "$output" == *"--gate-after-signoff scopes --requires-gate"* ]]
}

@test "E3d render states the implementation signature: not signed, signed, stale, void" {
  built_certified
  run "$G" render --program demo
  [ "${lines[${#lines[@]}-1]}" = "Built: certified $CC_NOW (BUILT-CERT-v1) · implementation not signed" ]
  lib_sign
  "$G" built-signed --program demo
  run "$G" render --program demo
  [[ "${lines[0]}" == "Research: demo version 1. CERTIFIED"* ]] || false
  [[ "${lines[${#lines[@]}-1]}" == "Built: certified $CC_NOW (BUILT-CERT-v1) · implementation signed by the operator 20"*"Z" ]] || false
  printf ' ' >> "$REC/built/BUILT-CERT-v1.json"
  run "$G" render --program demo
  [[ "${lines[${#lines[@]}-1]}" == *"· implementation signature STALE (the built certificate changed after it): not signed" ]] || false
  rechain '["claude"]'
  run "$G" render --program demo
  [[ "${lines[${#lines[@]}-1]}" == *"· implementation signature VOID (agent-written): not signed" ]]
}

@test "E3d built-freeze from implementation-signed needs --refreeze, and the old signature does not cover the next certificate" {
  built_certified; lib_sign
  "$G" built-signed --program demo
  run freeze --wave W1
  [ "$status" -eq 2 ]
  [[ "$output" == *"--refreeze"* ]] || false
  [ "$(state)" = "implementation-signed" ]
  run freeze --refreeze
  [ "$status" -eq 0 ]
  [ "$(state)" = "build-certifying" ]
  printf '{"cert":"BUILT-CERT-v2","program":"demo","version":2,"issued":"%s"}\n' "$CC_NOW" > "$REC/built/BUILT-CERT-v2.json"
  setstate build-certified
  run "$G" built-signed --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"the signature on file covers BUILT-CERT-v1"* ]]
}

@test "E3d built-run refuses an implementation-signed program: a new certificate starts at built-freeze --refreeze" {
  built_certified; lib_sign
  "$G" built-signed --program demo
  run "$G" built-run --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"--refreeze"* ]] || false
  [ "$(state)" = "implementation-signed" ]
}

@test "E3d every reader of the registry treats implementation-signed as active until close" {
  setstate implementation-signed
  run /bin/bash -c '. "$1"; rp_is_active "$2"' _ "$REPO/scripts/lib/research-program.sh" "$ROOT"
  [ "$status" -eq 0 ]
  fn="$(sed -n '/^_ca_rp_lib() {/,/^if \[ "\$d4" -eq 1 \]/p' "$REPO/hooks/completion-assert.sh" | sed '$d')"
  export CC_RESEARCH_PROGRAM_LIB="$REPO/scripts/lib/research-program.sh"
  run /bin/bash -c 'eval "$1"; _ca_rp_prompt_active "is demo done?" && printf "%s" "$_RP_RESULT"' _ "$fn"
  [ "$output" = "demo implementation-signed" ]
  run prompt "build it: research the options for caching"
  [ -z "$output" ]
  prompt "are we done?" >/dev/null
  [ "$(tool Agent)" = deny ]
  run /usr/bin/python3 "$REPO/bin/cc-research" job sweep
  [[ "$output" == *"job sweep demo: ok"* ]]
}
