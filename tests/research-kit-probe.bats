#!/usr/bin/env bats
# research-kit-probe — scripts/research-kit/probe-run.sh: the only writer of probes.jsonl, and the
# environment doctor (REPORT.md §3.4). Evidence levels are computed from how a probe ran, so each
# planted input below must earn less than the level a sloppy runner would have recorded.

setup() {
  unset CC_BATS_ACTIVE
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  PR="$REPO/scripts/research-kit/probe-run.sh"
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/research"
  export CC_RESEARCH_REGISTRY="$CC_RESEARCH_HOME/programs.json"
  export CC_RESEARCH_RECORDS="$BATS_TEST_TMPDIR/records"
}

last_field() { # <jq-ish python expr over the last probe record>
  /usr/bin/python3 -c "import json; r=[json.loads(l) for l in open('$CC_RESEARCH_RECORDS/probes.jsonl')][-1]; print($1)"
}

@test "a negative control that exits 0 records no refutation and earns level 0" {
  run "$PR" run --program demo --id P-1 --kind read --closes PR-1 --negative-control 'true' -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"level=E0"* ]]
  [ "$(last_field 'r["negative_control"]["reported_refutation"]')" = "False" ]
}

@test "a negative control that fails lets a read earn its primary-read level" {
  run "$PR" run --program demo --id P-2 --kind read --closes PR-1 --negative-control 'false' -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"level=E2"* ]]
}

@test "a measurement with 3 samples is anecdote (E1); 5 with a load control is E4" {
  run "$PR" run --program demo --id P-3 --kind measure --n 3 --load-control --negative-control false -- true
  [[ "$output" == *"level=E1"* ]]
  run "$PR" run --program demo --id P-4 --kind measure --n 5 --negative-control false -- true
  [[ "$output" == *"level=E1"* ]]
  run "$PR" run --program demo --id P-5 --kind measure --n 5 --load-control --negative-control false -- true
  [[ "$output" == *"level=E4"* ]]
}

@test "--mutates-live is refused: probes never change the live subject" {
  run "$PR" run --program demo --id P-6 --kind spike --mutates-live --negative-control false -- true
  [ "$status" -eq 2 ]
  [ ! -e "$CC_RESEARCH_RECORDS/probes.jsonl" ]
}

@test "a probe with no negative control and no reason is refused" {
  run "$PR" run --program demo --id P-7 --kind read -- true
  [ "$status" -eq 2 ]
}

@test "a duplicate probe id is refused; probes are append-only" {
  "$PR" run --program demo --id P-8 --kind read --no-negative-control 'inventory' -- true
  run "$PR" run --program demo --id P-8 --kind read --no-negative-control 'inventory' -- true
  [ "$status" -eq 2 ]
  [ "$(grep -c '"P-8"' "$CC_RESEARCH_RECORDS/probes.jsonl")" -eq 1 ]
}

@test "a failing command records its exit and earns no level" {
  run "$PR" run --program demo --id P-9 --kind read --negative-control false -- false
  [[ "$output" == *"exit=1"* ]]
  [[ "$output" == *"level=E0"* ]]
  [ -f "$CC_RESEARCH_RECORDS/evidence/P-9/stdout" ]
}

@test "stdin is /dev/null: a probe running cat returns at once" {
  run "$PR" run --program demo --id P-10 --kind read --timeout 5 --negative-control false -- cat
  [ "$status" -eq 0 ]
  [[ "$output" == *"exit=0"* ]]
}

# A fake interactive zsh: evaluates the fenced command in bash with `print` and `whence` shims, a
# PATH holding a tool the agent's PATH does not, and terminal escape noise on the answer line.
fake_zsh() {
  mkdir -p "$BATS_TEST_TMPDIR/ipath"
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/ipath/codex"
  chmod +x "$BATS_TEST_TMPDIR/ipath/codex"
  cat > "$BATS_TEST_TMPDIR/fake-zsh" <<EOF
#!/bin/bash
shift
export PATH="$BATS_TEST_TMPDIR/ipath:/usr/bin:/bin"
print() { shift; shift; printf '\033]1337;CurrentDir=/x\007%s\n' "\$*"; }
whence() { command -v "\$2"; }
echo "banner from an rc file"
eval "\$1"
EOF
  chmod +x "$BATS_TEST_TMPDIR/fake-zsh"
  export CC_RESEARCH_ZSH="$BATS_TEST_TMPDIR/fake-zsh"
}

@test "doctor finds a tool that exists only on the interactive PATH and says the agent cannot see it" {
  fake_zsh
  PATH=/usr/bin:/bin run "$PR" doctor --program demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex"*"$BATS_TEST_TMPDIR/ipath/codex"*"hidden from the agent PATH"* ]]
  /usr/bin/python3 -c "
import json; d = json.load(open('$CC_RESEARCH_RECORDS/evidence/doctor/env.json'))
assert d['tools']['codex']['interactive'] == '$BATS_TEST_TMPDIR/ipath/codex', d['tools']['codex']
assert d['tools']['codex']['hidden_from_agent'] is True
assert d['envs'] == ['interactive-zsh', 'launchd-bash32', 'agent-shell']"
}

@test "doctor reads the launchd interpreter as bash 3.2 and records a live-read probe" {
  fake_zsh
  "$PR" doctor --program demo
  [ "$(last_field 'r["kind"], r["id"]')" = "live-read P-doctor-1" ]
  grep -q '3.2.57' "$CC_RESEARCH_RECORDS/evidence/doctor/env.json"
}
