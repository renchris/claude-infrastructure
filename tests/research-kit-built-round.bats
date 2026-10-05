#!/usr/bin/env bats
# research-kit-built-round — method v1.2, REPORT.md §11: `round.sh run --kind built`, the Stage 9
# reviewer round over the BUILT artifact. It runs only while the registry reads build-certifying
# with a pinned built snapshot, in order, capped by the profile's built-round cap (lite: 3), never
# after the stop rule fired; its bundle carries the snapshot's tracked files and its matrix pins
# the built snapshot, not the plan freeze. Prior rounds are fixture matrices; a fake courier
# stands in for the vendor CLIs.

setup() {
  unset CC_BATS_ACTIVE
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  R="$REPO/scripts/research-kit/round.sh"
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/research"
  export CC_RESEARCH_REGISTRY="$CC_RESEARCH_HOME/programs.json"
  export CC_RESEARCH_RECORDS="$BATS_TEST_TMPDIR/records"
  mkdir -p "$CC_RESEARCH_RECORDS/rounds" "$CC_RESEARCH_RECORDS/built" "$CC_RESEARCH_HOME/demo"
  printf '{"profile":"lite","plan":"PLAN.md","method_version":"1.2"}\n' > "$CC_RESEARCH_RECORDS/frame.json"
  printf '{"snapshot_sha":"plan-freeze-sha"}\n' > "$CC_RESEARCH_RECORDS/freeze.json"
  printf '# plan\n' > "$CC_RESEARCH_RECORDS/PLAN.md"
  echo "review" > "$BATS_TEST_TMPDIR/brief.txt"
  A="$BATS_TEST_TMPDIR/artifact"
  mkdir -p "$A"
  printf 'built\n' > "$A/app.txt"
  git -C "$A" init -q
  git -C "$A" -c user.name=t -c user.email=t@t add app.txt
  git -C "$A" -c user.name=t -c user.email=t@t commit -qm built
  printf 'scratch\n' > "$A/untracked.txt"
  SHA="$(git -C "$A" rev-parse HEAD)"
  printf '{"snapshot_sha":"%s","artifact_root":"%s","research_cert":"CERT-v1","waves_done":[]}\n' "$SHA" "$A" \
    > "$CC_RESEARCH_RECORDS/built/freeze.json"
  state build-certifying
  export CC_RESEARCH_COURIER="$BATS_TEST_TMPDIR/courier"
  cat > "$CC_RESEARCH_COURIER" <<'STUB'
#!/bin/bash
verb="$1"; shift
rid=""; pid=""; vendor=""; extra=""
while [ $# -gt 0 ]; do
  case "$1" in --round) rid="$2" ;; --pid) pid="$2" ;; --vendor) vendor="$2" ;; --extra) extra="$2" ;; esac
  shift
done
if [ "$verb" = bundle ]; then
  echo "bundle $rid" >> "$CC_RESEARCH_RECORDS/runs.log"
  [ -n "$extra" ] && (cd "$extra" && find . | sort) > "$CC_RESEARCH_RECORDS/extra-$rid.txt"
  exit 0
fi
[ "$verb" = run ] || exit 0
d="$CC_RESEARCH_RECORDS/rounds/$rid/panels"; mkdir -p "$d"
printf '{"pid":"%s","status":"complete"}\n' "$pid" > "$d/$pid.json"
echo "$vendor $pid" >> "$CC_RESEARCH_RECORDS/runs.log"
STUB
  chmod +x "$CC_RESEARCH_COURIER"
  preflight 1
}

state() { # <registry state>
  printf '{"programs":[{"slug":"demo","aliases":[],"cwd_roots":["%s"],"state":"%s"}]}\n' "$BATS_TEST_TMPDIR" "$1" \
    > "$CC_RESEARCH_REGISTRY"
}
preflight() { # <age in hours> [dead vendor]
  /usr/bin/python3 -c "
import json, sys, time
at = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time() - float(sys.argv[1]) * 3600))
json.dump({v: {'ok': v != sys.argv[2], 'model_id': None, 'error': None if v != sys.argv[2] else 'walled', 'at': at}
           for v in ('anthropic', 'frontier', 'openai', 'google')}, open(sys.argv[3], 'w'))" \
    "$1" "${2:-}" "$CC_RESEARCH_HOME/demo/preflight.json"
}
mat() { # <n> [extra json fields]: a closed, counted built round b<n>
  mkdir -p "$CC_RESEARCH_RECORDS/rounds/b$1"
  printf '{"round":"b%s","kind":"built","seq":%s,"closed":true,"counted":true%s}\n' "$1" "$1" "${2:-,\"quiet\":false}" \
    > "$CC_RESEARCH_RECORDS/rounds/b$1/matrix.json"
}
run_built() { run "$R" run --program demo --kind built --round "$1" --plan "$CC_RESEARCH_RECORDS/PLAN.md" --brief "$BATS_TEST_TMPDIR/brief.txt"; }
field() { /usr/bin/python3 -c "import json; m=json.load(open('$CC_RESEARCH_RECORDS/rounds/$1/matrix.json')); print(($2))"; }

@test "a built round is refused unless the registry reads build-certifying" {
  state certified
  run_built 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"frozen built snapshot"* ]] || false
  [ ! -e "$CC_RESEARCH_RECORDS/rounds/b1" ]
}

@test "a built round is refused without a pinned built snapshot" {
  rm "$CC_RESEARCH_RECORDS/built/freeze.json"
  run_built 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"no built/freeze.json"* ]]
}

@test "a built round runs as b1 over the profile's slots and pins the built snapshot, not the plan freeze" {
  run_built 1
  [ "$status" -eq 0 ]
  [ "$(field b1 'm["kind"], len(m["slots"]), m["counted"], m["snapshot_sha"] == "'"$SHA"'"')" = "('built', 8, True, True)" ]
}

@test "the bundle carries the built snapshot's tracked files and nothing else from the work tree" {
  run_built 1
  [ "$status" -eq 0 ]
  grep -qx './app.txt' "$CC_RESEARCH_RECORDS/extra-b1.txt"
  run grep -c 'untracked\|\.git' "$CC_RESEARCH_RECORDS/extra-b1.txt"
  [ "$output" = "0" ]
}

@test "skipping a built round is refused, and so is opening one before the last closed" {
  run_built 2
  [ "$status" -eq 2 ]
  [[ "$output" == *"out of order"* ]] || false
  mat 1 ',"quiet":false'
  /usr/bin/python3 -c "import json; p='$CC_RESEARCH_RECORDS/rounds/b1/matrix.json'; m=json.load(open(p)); m['closed']=False; json.dump(m, open(p,'w'))"
  run_built 2
  [ "$status" -eq 2 ]
  [[ "$output" == *"not closed"* ]]
}

@test "a built round past the profile's cap is refused, and a signed extra round set does not raise it" {
  mat 1; mat 2; mat 3
  run_built 4
  [ "$status" -eq 2 ]
  [[ "$output" == *"past the lite cap of 3 built rounds"* ]] || false
  printf '{"action":"extra-round","target":null,"at":1,"pins":{},"because":"x","provenance":{"claude_ancestor":false,"chain":["zsh","kitty"]}}\n' \
    >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
  run_built 4
  [ "$status" -eq 2 ]
}

@test "the built round at the cap is verification-only" {
  mat 1; mat 2
  run_built 3
  [ "$status" -eq 0 ]
  [ "$(field b3 'm["verification_only"], m["r_max"]')" = "(True, 3)" ]
}

@test "no built round after the stop rule fired" {
  mat 1 ',"quiet":true'; mat 2 ',"quiet":true'
  run_built 3
  [ "$status" -eq 2 ]
  [[ "$output" == *"the last 2 counted built rounds were quiet"* ]]
}

@test "a built round needs the same fresh all-live preflight as a certification round" {
  preflight 1 google
  run_built 1
  [ "$status" -eq 3 ]
  [ ! -e "$CC_RESEARCH_RECORDS/rounds/b1" ]
}

@test "closing a built round counts its own holes, never certification round 1's" {
  printf '%s\n' '{"id":"H-1","round":1,"verification":{"status":"CONFIRMED"},"materiality":{"level":"MATERIAL"}}' \
    > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run_built 1
  run "$R" close --program demo --round b1
  [ "$status" -eq 0 ]
  [ "$(field b1 'm["quiet"], m["new_material"]')" = "(True, 0)" ]
}

@test "a confirmed material hole of the built round makes it not quiet" {
  printf '%s\n' '{"id":"H-9","round":"b1","verification":{"status":"CONFIRMED"},"materiality":{"level":"MATERIAL"}}' \
    > "$CC_RESEARCH_RECORDS/holes.jsonl"
  run_built 1
  run "$R" close --program demo --round b1
  [ "$status" -eq 0 ]
  [ "$(field b1 'm["quiet"], m["new_material"]')" = "(False, 1)" ]
}

@test "cc-research built-round runs the same round with the kind fixed to built" {
  run "$REPO/bin/cc-research" built-round --program demo --round 1 --plan "$CC_RESEARCH_RECORDS/PLAN.md" --brief "$BATS_TEST_TMPDIR/brief.txt"
  [ "$status" -eq 0 ]
  [ "$(field b1 'm["kind"]')" = "built" ]
}
