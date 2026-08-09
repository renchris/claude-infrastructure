#!/usr/bin/env bats
# turbopack-worker-cap-audit.sh — the observability half of Wave C's "cap the worker pool".
#
# $HOME is fixtured and every behavioural case runs against a FIXTURE root, because the script's
# default root is $HOME/Development: an auditor whose tests depend on the operator's actual
# checkouts reports on a population that changes under it, and its verdict would flip the day
# someone clones a repo. Case 8 is the single exception — it points explicitly at the real tree,
# READ-ONLY, and asserts only what cannot drift (it parses; it found at least one app).
#
# The exit code is a VERDICT here (0 covered / 3 uncovered), so every case asserts on it — a test
# that only read stdout would pass for an implementation that always exits 0, which is exactly the
# failure a caller gating on this would inherit.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  AUDIT="$REPO/scripts/turbopack-worker-cap-audit.sh"
  D="$BATS_TEST_TMPDIR"
  # The script's default root is $HOME/Development, so $HOME is fixtured BEFORE anything runs —
  # otherwise every case here would audit the operator's live checkouts and its verdict would flip
  # the day someone clones a repo. The real path is captured first, for the one case that wants it.
  REAL_HOME="$HOME"
  export HOME="$D/home"; mkdir -p "$HOME/Development"
  ROOT="$D/dev"; mkdir -p "$ROOT"
  OPT=turbopackPluginRuntimeStrategy
}

# Build a fixture app. $1 name · $2 installed version or "" for none · $3 schema-carries-option (y/n)
# · $4 config body · $5 dev script · $6 build script
mkapp() {
  local a="$ROOT/$1"; mkdir -p "$a"
  jq -n --arg d "${5:-next dev}" --arg b "${6:-next build}" \
    '{name:"x", dependencies:{next:"16.2.6"}, scripts:{dev:$d, build:$b}}' > "$a/package.json"
  printf '%s\n' "${4:-module.exports = {}}" > "$a/next.config.js"
  if [ -n "$2" ]; then
    mkdir -p "$a/node_modules/next/dist/server"
    jq -n --arg v "$2" '{version:$v}' > "$a/node_modules/next/package.json"
    if [ "$3" = y ]; then
      printf 'const s = { %s: z.enum(["workerThreads","childProcesses"]) }\n' "$OPT" \
        > "$a/node_modules/next/dist/server/config-schema.js"
    else
      printf 'const s = { turbopackMemoryLimit: z.number() }\n' \
        > "$a/node_modules/next/dist/server/config-schema.js"
    fi
  fi
}

state_of() { # $1 = json output, $2 = app
  printf '%s' "$1" | jq -r --arg a "$2" '.apps[] | select(.app==$a) | .state'
}

@test "1 a supported app with no flag is UNCOVERED, and the exit code says so" {
  mkapp exposed 16.2.6 y
  run bash "$AUDIT" --root "$ROOT" --json
  [ "$status" -eq 3 ]
  [ "$(state_of "$output" exposed)" = "uncovered" ]
  [ "$(printf '%s' "$output" | jq -r .verdict)" = "uncovered" ]
}

@test "2 POSITIVE CONTROL — the same app WITH the flag reads set, and the run goes green" {
  # Without this, case 1 passes for an auditor that reports every app as uncovered forever, and the
  # `uncovered` verdict would carry no information at all.
  mkapp capped 16.2.6 y "module.exports = { experimental: { $OPT: 'workerThreads' } }"
  run bash "$AUDIT" --root "$ROOT" --json
  [ "$status" -eq 0 ]
  [ "$(state_of "$output" capped)" = "set" ]
  [ "$(printf '%s' "$output" | jq -r .verdict)" = "covered" ]
}

@test "3 support is read from the INSTALLED SCHEMA, not from the version label" {
  # The live box carries the drift this guards: reso-playwright declares ^15.5.11 with 14.2.30
  # installed. A version-number test would have called it modern and audited it wrongly.
  mkapp mislabelled 16.2.6 n            # says 16.2.6, schema has no such option
  run bash "$AUDIT" --root "$ROOT" --json
  [ "$status" -eq 0 ]
  [ "$(state_of "$output" mislabelled)" = "n/a" ]
  [ "$(printf '%s' "$output" | jq -r '.apps[] | select(.app=="mislabelled") | .supports')" = "no" ]
}

@test "4 next not installed ⇒ n/a, never a false accusation" {
  mkapp bare ""
  run bash "$AUDIT" --root "$ROOT" --json
  [ "$status" -eq 0 ]
  [ "$(state_of "$output" bare)" = "n/a" ]
  [ "$(printf '%s' "$output" | jq -r '.apps[] | select(.app=="bare") | .installed')" = "not-installed" ]
}

@test "5 a --webpack opt-out counts only when it covers dev AND build" {
  mkapp halfout 16.2.6 y "module.exports = {}" "next dev" "ANALYZE=true next build --webpack"
  mkapp fullout 16.2.6 y "module.exports = {}" "next dev --webpack" "next build --webpack"
  run bash "$AUDIT" --root "$ROOT" --json
  [ "$status" -eq 3 ]
  [ "$(state_of "$output" halfout)" = "uncovered" ]   # analyze-only opt-out is not a mitigation
  [ "$(state_of "$output" fullout)" = "webpack" ]
}

@test "6 a directory without a next dependency is not scanned at all" {
  mkdir -p "$ROOT/notnext"
  jq -n '{name:"y", dependencies:{react:"19"}}' > "$ROOT/notnext/package.json"
  mkapp exposed 16.2.6 y
  run bash "$AUDIT" --root "$ROOT" --json
  [ "$(printf '%s' "$output" | jq -r .scanned)" = "1" ]
  [ "$(printf '%s' "$output" | jq -r '[.apps[] | select(.app=="notnext")] | length')" = "0" ]
}

@test "7 the verdict token goes to stderr on every format, so a table caller can still parse it" {
  mkapp exposed 16.2.6 y
  run bash -c 'bash "$1" --root "$2" --quiet 2>&1 >/dev/null' _ "$AUDIT" "$ROOT"
  [[ "$output" == *"verdict=uncovered"* ]] || false
  [[ "$output" == *"uncovered=1"* ]]
}

@test "8 it runs on the real population, READ-ONLY, and emits a parseable verdict" {
  # The one case that meets the live tree, and it is explicitly pointed at it rather than reaching
  # it through an unfixtured $HOME — the auditor only ever reads, and the assertion is limited to
  # properties that cannot drift as repos come and go (it parses, and it found at least one app).
  [ -d "$REAL_HOME/Development" ] || skip "no live Development tree on this box"
  run bash -c 'bash "$1" --root "$2" --json 2>/dev/null' _ "$AUDIT" "$REAL_HOME/Development"
  [ "$status" -eq 0 ] || [ "$status" -eq 3 ]
  printf '%s' "$output" | jq -e '.scanned >= 1 and (.verdict | test("covered|uncovered"))' >/dev/null
}

@test "9 an empty root is not an error and is not a false all-clear" {
  # The fixtured $HOME/Development has no apps in it. A scan of nothing must report scanned=0 and
  # exit 0 — an auditor that reported `covered` over an empty population would read green forever
  # if its root were ever wrong.
  run bash "$AUDIT" --root "$HOME/Development" --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .scanned)" = "0" ]
  [ "$(printf '%s' "$output" | jq -r '.apps | length')" = "0" ]
}
