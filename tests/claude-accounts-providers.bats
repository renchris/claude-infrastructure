#!/usr/bin/env bats
# claude-accounts — the ADDITIVE provider surface (--agents, the --readout appendix, the --json
# `providers` key). Registry: providers.json. Design + measurements:
# docs/plans/MULTI_PROVIDER_PLANS.md § W1 RESULT.
#
# What these tests are actually defending, in order of how expensive the mistake was to learn:
#
#  1. ROUTABILITY IS NOT PRESENCE. Antigravity is installed, authenticated, and on PATH — and is
#     the VS Code editor launcher with no non-interactive mode, so it can never be routed to.
#     grok-wiki called it `ready` on `command -v` alone. A row that renders routable on presence
#     is the defect; test 2 is its positive control.
#  2. AN AUTH LIST IS NOT A BILLING ANSWER. pi-claude authenticates against a Max plan we hold and
#     then bills per token through extra usage, which accounts.json forbids. It nearly shipped as
#     IN because Pi's README lists Claude Pro/Max under "Subscriptions". Test 3 pins that a
#     cost-failed provider can never render routable.
#  3. THE CLAUDE SURFACE IS LOAD-BEARING AND THE REGISTRY IS AN ACCESSORY. A JSON typo in a second
#     vendor's file must never take the dashboard down (test 1).
#
# ENVIRONMENT IS PINNED IN setup(), deliberately. This repo has been bitten by suites that
# silently became a function of the developer's terminal (the KITTY_WINDOW_ID inheritance item),
# so TERM/NO_COLOR and every provider env var a probe could read are fixed here. A test that
# passes only on the author's machine is not a test.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CA_BIN="$REPO/bin/claude-accounts"

  # --- HOME fixtured FIRST, before anything can read it. load_providers() falls back to
  #     ~/.claude/providers.json when CC_PROVIDERS_JSON is unset, and probe_provider() reads
  #     ~-relative auth paths — so an unfixtured suite would consult the OPERATOR's real registry
  #     and real credentials, and its verdict would depend on which backends they happen to have
  #     logged into. That is the whole hermeticity failure: the tests would still pass, for
  #     reasons that have nothing to do with the code under test.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"

  # --- terminal pinned: no colour, no width games, no inherited multiplexer identity
  export TERM=dumb
  export NO_COLOR=1
  unset KITTY_WINDOW_ID ITERM_SESSION_ID TMUX COLORTERM CLICOLOR_FORCE || true

  # --- provider env pinned: an API key leaking in from the developer's shell would flip an
  #     auth_state to `api-key` and silently change what these assertions mean.
  unset OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY GOOGLE_API_KEY XAI_API_KEY \
        GOOGLE_CLOUD_PROJECT GROK_API_KEY || true

  # --- PATH pinned to a scratch bin: `installed` must be decided by THIS fixture, never by
  #     whatever the developer happens to have globally installed.
  export FAKEBIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$FAKEBIN"
  export PATH="$FAKEBIN:/usr/bin:/bin"

  export CC_PROVIDERS_JSON="$BATS_TEST_TMPDIR/providers.json"
}

# Write a scratch registry from a JSON array passed as $1.
# Parsed with json.loads, NOT interpolated into a Python literal: JSON's true/false/null are not
# Python names, and embedding them raised NameError in every fixture that used one — a helper bug
# that fails the test for a reason that has nothing to do with the subject.
_registry() {
  python3 - "$CC_PROVIDERS_JSON" "$1" <<'PY'
import json, sys
json.dump({"providers": json.loads(sys.argv[2])}, open(sys.argv[1], "w"))
PY
}

# Create a fake executable on the scratch PATH that prints a version and exits 0.
_fakebin() {
  printf '#!/bin/sh\necho "%s"\n' "$2" > "$FAKEBIN/$1"
  chmod +x "$FAKEBIN/$1"
}

@test "registry: absent or malformed degrades to NO provider section, never an exception" {
  # absent
  rm -f "$CC_PROVIDERS_JSON"
  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"no provider registry"* ]]

  # malformed — the accessory must not be able to take the surface down
  printf '{ this is not json' > "$CC_PROVIDERS_JSON"
  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"no provider registry"* ]]

  # a valid registry whose `providers` is the wrong TYPE is also a miss, not a traceback
  printf '{"providers": "nope"}' > "$CC_PROVIDERS_JSON"
  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  [[ "$output" != *"Traceback"* ]]
}

@test "routable is decided by headless mode, NOT by the binary being present and authed" {
  # The Antigravity shape: installed ✓, authenticated ✓, headless ✗.
  _fakebin editorlike "9.9.9"
  cat > "$BATS_TEST_TMPDIR/creds.json" <<'JSON'
{"access_token": "AT", "refresh_token": "RT"}
JSON
  _registry '[{"name":"editorlike","label":"EditorLike","bin":"editorlike",
               "headless":null,"in_scope":false,
               "skip_reason":"NOT AN AGENT BACKEND — editor launcher",
               "plan":"SomePlan","bills_outside_plan":false,
               "auth":{"kind":"json_file","path":"'"$BATS_TEST_TMPDIR"'/creds.json"}}]'

  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  # it IS installed and it IS authenticated — both must show, so the row is not simply blank
  [[ "$output" == *"9.9.9"* ]]
  [[ "$output" == *"ok"* ]]
  # ...and it must STILL not be routable
  [[ "$output" != *"| EditorLike | ✅"* ]]
  [[ "$output" == *"NOT AN AGENT BACKEND"* ]]
  [[ "$output" == *"0 of 0 routable"* ]]
}

@test "POSITIVE CONTROL: the same row with a headless mode DOES render routable" {
  # Proves the previous test fails for the stated reason (missing headless mode) and not because
  # the fixture was unreachable, misspelled, or dropped on the floor.
  _fakebin editorlike "9.9.9"
  cat > "$BATS_TEST_TMPDIR/creds.json" <<'JSON'
{"access_token": "AT", "refresh_token": "RT"}
JSON
  _registry '[{"name":"editorlike","label":"EditorLike","bin":"editorlike",
               "headless":"editorlike exec","in_scope":true,
               "plan":"SomePlan","bills_outside_plan":false,
               "auth":{"kind":"json_file","path":"'"$BATS_TEST_TMPDIR"'/creds.json"}}]'

  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"| EditorLike | ✅"* ]]
  [[ "$output" == *"1 of 1 routable"* ]]
}

@test "a provider that bills OUTSIDE a held plan is never routable, and is flagged as money" {
  # The pi-claude shape: auth works against a plan we hold, usage bills per token anyway.
  _fakebin harness "1.2.3"
  _registry '[{"name":"harness-claude","label":"Harness · Claude","bin":"harness",
               "headless":"harness --print","in_scope":false,
               "skip_reason":"COST GATE FAIL — bills per token outside the plan",
               "plan":"Claude Pro/Max","bills_outside_plan":true}]'

  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  [[ "$output" != *"| Harness · Claude | ✅"* ]]   # a headless mode alone does NOT clear it
  [[ "$output" == *"YES"* ]]                       # the billing cell is loud
  [[ "$output" == *"COST GATE FAIL"* ]]
  [[ "$output" == *"bill OUTSIDE a plan we hold"* ]]
  [[ "$output" == *"0 of 0 routable"* ]]
}

@test "reason precedence: a provider failing BOTH gates reports the declared reason, not a guess" {
  # Grok fails on cost AND has no measured headless mode. Rendering "no headless mode" there
  # would misreport WHY it is not wired — the operator would go looking for a CLI flag when the
  # answer is that we hold no subscription.
  _registry '[{"name":"twogates","label":"TwoGates","bin":"twogates-absent",
               "headless":null,"in_scope":false,
               "skip_reason":"COST GATE FAIL — API-key-only, no plan held",
               "bills_outside_plan":true}]'

  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"COST GATE FAIL"* ]]
  [[ "$output" != *"no headless mode"* ]]
}

@test "an API key present is reported as a METERED credential, not as healthy auth" {
  _fakebin keyed "0.1"
  cat > "$BATS_TEST_TMPDIR/keyed.json" <<'JSON'
{"MY_API_KEY": "sk-live-xxxx", "access_token": "AT"}
JSON
  _registry '[{"name":"keyed","label":"Keyed","bin":"keyed",
               "headless":"keyed run","in_scope":true,"plan":"none",
               "bills_outside_plan":true,
               "auth":{"kind":"json_file","path":"'"$BATS_TEST_TMPDIR"'/keyed.json",
                       "api_key_field":"MY_API_KEY"}}]'

  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  # an access_token is ALSO present — "ok" would be the wrong read, because the billing
  # question is what the cost gate turns on
  [[ "$output" == *"API key (metered)"* ]]
}

@test "an unmeasurable cell renders UNKNOWN, never a guess and never a blank that reads as fine" {
  _registry '[{"name":"mystery","label":"Mystery","bin":"mystery-absent",
               "headless":null,"in_scope":false,"skip_reason":"DEFERRED — tier UNKNOWN",
               "plan":null,"bills_outside_plan":null}]'

  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" == *"not installed"* ]]
}

@test "a pinned model is marked UNPROVEN until the agent has reported its own id back" {
  _fakebin pinned "2.0"
  printf '{"model": {"name": "some-model-9"}}' > "$BATS_TEST_TMPDIR/settings.json"
  _registry '[{"name":"pinned","label":"Pinned","bin":"pinned",
               "headless":"pinned -p","in_scope":true,"plan":"HeldPlan",
               "bills_outside_plan":false,
               "model_pin":{"path":"'"$BATS_TEST_TMPDIR"'/settings.json","key":"model.name"}}]'

  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"some-model-9"* ]]
  [[ "$output" == *"unproven"* ]]

  # ...and PROVEN once the registry records how it was proven by invocation
  _registry '[{"name":"pinned","label":"Pinned","bin":"pinned",
               "headless":"pinned -p","in_scope":true,"plan":"HeldPlan",
               "bills_outside_plan":false,
               "proven_by":"pinned -p prints its model id",
               "model_pin":{"path":"'"$BATS_TEST_TMPDIR"'/settings.json","key":"model.name"}}]'
  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"proven"* ]]
  [[ "$output" != *"unproven"* ]]
}

@test "the model pin is read from the provider's OWN config, not from the registry's opinion" {
  # If the pin were echoed from the registry, editing the config would not change the render —
  # and the tool would report a pin that no longer exists.
  _fakebin pinned "2.0"
  printf '{"model": {"name": "first-model"}}' > "$BATS_TEST_TMPDIR/settings.json"
  _registry '[{"name":"pinned","label":"Pinned","bin":"pinned","headless":"pinned -p",
               "in_scope":true,"plan":"HeldPlan","bills_outside_plan":false,
               "model_pin":{"path":"'"$BATS_TEST_TMPDIR"'/settings.json","key":"model.name"}}]'
  run "$CA_BIN" --agents
  [[ "$output" == *"first-model"* ]]

  printf '{"model": {"name": "second-model"}}' > "$BATS_TEST_TMPDIR/settings.json"
  run "$CA_BIN" --agents
  [[ "$output" == *"second-model"* ]]
  [[ "$output" != *"first-model"* ]]
}

@test "--agents --json emits providers as data, and needs no Claude sweep to do it" {
  _fakebin harness "1.2.3"
  _registry '[{"name":"h","label":"H","bin":"harness","headless":"harness -p",
               "in_scope":true,"plan":"HeldPlan","bills_outside_plan":false}]'

  # No CLAUDE_ACCOUNTS_JSON is exported and no keychain/network is reachable on this PATH;
  # --agents must still answer, because it returns before get_data().
  run "$CA_BIN" --agents --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert list(d) == ['providers'], list(d)
p=d['providers'][0]
assert p['installed'] is True, p
assert p['routable'] is True, p
assert p['version'] == '1.2.3', p
"
}
