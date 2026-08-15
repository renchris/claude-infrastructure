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

  # --- where a counting fakebin records its invocations. The provider memo is counted by having
  #     the child ITSELF leave a mark, never by wall-clock: a timing assertion would be the
  #     flakiest possible way to ask "was this spawned twice?".
  export COUNTER="$BATS_TEST_TMPDIR/spawns"
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

# Same, but it appends one line to $COUNTER every time it is executed. `_count` is how many child
# processes the tool actually spawned.
_countbin() {
  printf '#!/bin/sh\nprintf "x\\n" >> "%s"\necho "%s"\n' "$COUNTER" "$2" > "$FAKEBIN/$1"
  chmod +x "$FAKEBIN/$1"
}

_count() {
  if [ -f "$COUNTER" ]; then
    wc -l < "$COUNTER" | tr -d ' '
  else
    echo 0
  fi
}

# The one registry every memo test uses. Held in a helper so a test that must EDIT the registry
# can be read as "the same thing, with one field changed".
_memo_registry() {
  _registry '[{"name":"h","label":"'"${1:-H}"'","bin":"harness","headless":"harness -p",
               "in_scope":true,"plan":"HeldPlan","bills_outside_plan":false}]'
}

@test "registry: absent or malformed degrades to NO provider section, never an exception" {
  # absent
  rm -f "$CC_PROVIDERS_JSON"
  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"no provider registry"* ]] || false

  # malformed — the accessory must not be able to take the surface down
  printf '{ this is not json' > "$CC_PROVIDERS_JSON"
  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"no provider registry"* ]] || false

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
  [[ "$output" == *"9.9.9"* ]] || false
  [[ "$output" == *"ok"* ]] || false
  # ...and it must STILL not be routable
  [[ "$output" != *"| EditorLike | ✅"* ]] || false
  [[ "$output" == *"NOT AN AGENT BACKEND"* ]] || false
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
  [[ "$output" == *"| EditorLike | ✅"* ]] || false
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
  [[ "$output" != *"| Harness · Claude | ✅"* ]] || false # a headless mode alone does NOT clear it
  [[ "$output" == *"YES"* ]] || false              # the billing cell is loud
  [[ "$output" == *"COST GATE FAIL"* ]] || false
  [[ "$output" == *"bill OUTSIDE a plan we hold"* ]] || false
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
  [[ "$output" == *"COST GATE FAIL"* ]] || false
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
  [[ "$output" == *"UNKNOWN"* ]] || false
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
  [[ "$output" == *"some-model-9"* ]] || false
  [[ "$output" == *"unproven"* ]] || false

  # ...and PROVEN once the registry records how it was proven by invocation
  _registry '[{"name":"pinned","label":"Pinned","bin":"pinned",
               "headless":"pinned -p","in_scope":true,"plan":"HeldPlan",
               "bills_outside_plan":false,
               "proven_by":"pinned -p prints its model id",
               "model_pin":{"path":"'"$BATS_TEST_TMPDIR"'/settings.json","key":"model.name"}}]'
  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"proven"* ]] || false
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
  [[ "$output" == *"first-model"* ]] || false

  printf '{"model": {"name": "second-model"}}' > "$BATS_TEST_TMPDIR/settings.json"
  run "$CA_BIN" --agents
  [[ "$output" == *"second-model"* ]] || false
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

# ---- the provider probe memo --------------------------------------------------------------------
#
# probe_provider() was 3.68s of a 3.7s `claude-accounts --json` on the live registry, re-paid by
# cc-context, cc-value, cc-board, cc-wave-plan and cc-blockers on every invocation. What costs the
# time is exclusively the CHILD PROCESSES, so those — and only those — are memoised.
#
# The invariant these tests sit next to, and must never be read as relaxing: "the model pin is read
# from the provider's OWN config" (above) edits a provider's settings.json between two runs with
# the registry untouched, and demands the render change. It is this memo's standing control — it
# passes in both worlds precisely because a whole-probe cache would break it.

@test "memo: a provider's CLI is spawned ONCE per TTL, not once per invocation" {
  _countbin harness "1.2.3"
  _memo_registry "H"

  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.2.3"* ]] || false
  cold="$(_count)"
  if [ "$cold" -ne 1 ]; then
    echo "expected exactly 1 spawn on the cold call, counted $cold" >&2
    return 1
  fi

  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  # The RENDER must be unchanged. A cache that changes what the surface says is a bug wearing a
  # speed-up's clothes, so the version assertion is repeated rather than assumed.
  [[ "$output" == *"1.2.3"* ]] || false
  warm="$(_count)"
  if [ "$warm" -ne 1 ]; then
    echo "the second call re-spawned the provider CLI: $warm spawns total, expected 1" >&2
    return 1
  fi
}

@test "memo: editing the registry invalidates it on the very next call" {
  _countbin harness "1.2.3"
  _memo_registry "H-before"

  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  warm="$(_count)"
  if [ "$warm" -ne 1 ]; then
    echo "precondition failed: expected a memo HIT before the edit, counted $warm spawns" >&2
    return 1
  fi

  # ONLY the label changes — nothing in the probe's argv, nothing about the binary. So the sole
  # thing that can invalidate here is the registry's own mtime/size, which is exactly the claim.
  _memo_registry "H-after-a-longer-label"
  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"H-after-a-longer-label"* ]] || false
  after="$(_count)"
  if [ "$after" -ne 2 ]; then
    echo "a registry edit did not invalidate the memo: expected 2 spawns, counted $after" >&2
    return 1
  fi
}

@test "memo: --fresh bypasses it, exactly as it bypasses the account cache" {
  _countbin harness "1.2.3"
  _memo_registry "H"

  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  warm="$(_count)"
  if [ "$warm" -ne 1 ]; then
    echo "precondition failed: expected a memo HIT, counted $warm spawns" >&2
    return 1
  fi

  run "$CA_BIN" --agents --fresh
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.2.3"* ]] || false
  after="$(_count)"
  if [ "$after" -ne 2 ]; then
    echo "--fresh was served from the memo: expected 2 spawns, counted $after" >&2
    return 1
  fi
}

@test "memo: a corrupt store degrades to a miss AND is replaced, never a traceback" {
  export CC_PROVIDER_CACHE="$BATS_TEST_TMPDIR/provider-probe.json"
  printf '{ this is not json' > "$CC_PROVIDER_CACHE"
  _countbin harness "1.2.3"
  _memo_registry "H"

  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  [[ "$output" != *"Traceback"* ]] || false
  [[ "$output" == *"1.2.3"* ]] || false

  # Degrading is only half of it: a store that stays corrupt costs a spawn on every call forever,
  # so the same pass must repair it.
  run python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if isinstance(d, dict) and len(d) == 1 else 1)' "$CC_PROVIDER_CACHE"
  if [ "$status" -ne 0 ]; then
    echo "corrupt memo was not replaced with a valid one-entry store" >&2
    return 1
  fi
}

@test "memo: replacing the BINARY invalidates it, with the registry untouched" {
  # MUTANT-PROVEN, not pre-fix-proven: this one passes against the un-memoised subject too,
  # because an absent cache is trivially never stale. Its control is a WEAKER memo — one keyed on
  # the registry alone, as the work item literally proposed — under which the second render serves
  # the OLD version string and this test reds. That is why the key carries the resolved binary's
  # realpath + mtime + size and not just providers.json's.
  _countbin harness "1.2.3"
  _memo_registry "H"

  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.2.3"* ]] || false

  _countbin harness "9.9.9"
  run "$CA_BIN" --agents
  [ "$status" -eq 0 ]
  if [[ "$output" != *"9.9.9"* ]]; then
    echo "an upgraded provider binary was reported at its OLD version from the memo" >&2
    return 1
  fi
  [[ "$output" != *"1.2.3"* ]]
}
