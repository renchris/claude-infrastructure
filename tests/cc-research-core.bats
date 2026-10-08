#!/usr/bin/env bats
# cc-research-core — the state verbs of bin/cc-research (scripts/research-kit/lib/cli_core.py):
# REPORT.md §8 item 9 (state half) and §10 item 17 (caps enforced in code).
#
# One known-good program (tests/fixtures/research-kit/build_good.py) is restored before every test;
# each test plants ONE input and asserts the verb's verdict, exit code, or that it wrote nothing.

setup_file() {
  export HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$HOME"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "$CC_NOW" > "$BATS_FILE_TMPDIR/now"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  export CC_DECISIONS_DIR="$W/decisions" CC_IDL="$W/idl.jsonl"
  mkdir -p "$W"
  "$BATS_TEST_DIRNAME/fixtures/research-kit/build_good.py" "$W" > "$BATS_FILE_TMPDIR/records-path"
  cp -Rp "$W" "$BATS_FILE_TMPDIR/golden"
}

setup() {
  export HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$HOME"
  unset CC_BATS_ACTIVE CC_RESEARCH_RECORDS
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CLI="$REPO/bin/cc-research"
  KIT="$REPO/scripts/research-kit"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(cat "$BATS_FILE_TMPDIR/now")"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  export CC_DECISIONS_DIR="$W/decisions" CC_IDL="$W/idl.jsonl"
  export CC_RESEARCH_ROUTER="$W/router.sh"
  export CC_RESEARCH_CC_DECIDE="$W/cc-decide-stub"
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  REC="$(cat "$BATS_FILE_TMPDIR/records-path")"
  FAKE_CLAUDE="$BATS_TEST_TMPDIR/claude-fake-shell"
  ln -sf /bin/bash "$FAKE_CLAUDE"
}

# jedit <file under REC> <python statement over d>: edit a JSON record in place.
jedit() {
  /usr/bin/python3 -c "import json; p='$REC/$1'; d=json.load(open(p)); $2; json.dump(d, open(p, 'w'))"
}
# jq_py <python expression over d>: evaluate against JSON on stdin.
jq_py() { /usr/bin/python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
# snap: every file under the work dir with its hash, so a pure read can be shown to write nothing.
snap() { (cd "$W" && find . -type f -print0 | sort -z | xargs -0 shasum); }
# stub_decide <json array>: a cc-decide whose `list --all --json` prints the given packets.
stub_decide() {
  printf '#!/bin/bash\nprintf %%s %q\n' "$1" > "$CC_RESEARCH_CC_DECIDE"
  chmod +x "$CC_RESEARCH_CC_DECIDE"
}
# name_packets <id...>: decision events naming each packet id (the program's packets).
name_packets() {
  local due
  due="$(date -u -v+1440H +%Y-%m-%dT%H:%M:%SZ)"
  for p in "$@"; do
    printf '{"id":"DR-1","packet":{"id":"%s","class":"C","due":"%s"}}\n' "$p" "$due" >> "$REC/decisions.jsonl"
  done
}
# sign <action>: a VALID operator signature (chain without claude) in the sealed log.
sign() {
  printf '{"row":"research:demo/%s","action":"%s","target":null,"at":%s,"pins":{},"provenance":{"claude_ancestor":false,"chain":["zsh","kitty"]}}\n' \
    "$1" "$1" "$(date +%s)" >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
}
# vault <state...>: a seed vault holding one original seed per given state.
vault() {
  /usr/bin/python3 -c "import sys; sys.path[:0]=['$KIT','$KIT/lib']; import seed
seed.save_vault('demo', {'seeds': [{'sid': 's%d' % i, 'cohort': 'original', 'state': s} for i, s in enumerate(sys.argv[1:])]}, 'test-key')" "$@"
}

# ── pass-throughs ──────────────────────────────────────────────────────────────────────────────

@test "gate pass-through preserves the gate's exit code: 0 on the good program, 1 on a failed row" {
  run "$CLI" gate run --program demo --consent-sealed-read
  [ "$status" -eq 0 ]
  [[ "$output" == *"CERTIFIED demo"* ]] || false
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  jedit frame.json "d['topic_owner']=''"
  run "$CLI" gate run --program demo --consent-sealed-read
  [ "$status" -eq 1 ]
}

@test "estimate, frame and index pass-throughs preserve a usage refusal (exit 2)" {
  run "$CLI" estimate --profile bogus --n0 3
  [ "$status" -eq 2 ]
  run "$CLI" frame no-such-verb
  [ "$status" -eq 2 ]
  run "$CLI" index --no-such-flag
  [ "$status" -eq 2 ]
  run "$CLI" estimate --profile lite --n0 2 --reps 5
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq_py "d['profile']")" = "lite" ]
}

@test "forecast prints the program's own forecast as JSON; freeze sets the registry to certifying" {
  run "$CLI" forecast --program demo
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq_py "d['r_max']")" = "6" ]
  run "$CLI" freeze --program demo
  [ "$status" -eq 0 ]
  [ "$(/usr/bin/python3 -c "import json; print(json.load(open('$CC_RESEARCH_REGISTRY'))['programs'][0]['state'])")" = "certifying" ]
}

# ── single checks ──────────────────────────────────────────────────────────────────────────────

@test "trace passes on the good program and fails on a finding with no trace" {
  run "$CLI" trace --program demo
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "PASS trace" ]] || false
  printf '{"id":"H-2","round":1}\n' >> "$REC/holes.jsonl"
  run "$CLI" trace --program demo
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "FAIL trace" ]] || false
  [[ "$output" == *"H-2"* ]] || false
}

@test "reconcile passes on the good program and fails on an unmapped residual" {
  run "$CLI" reconcile --program demo
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "PASS reconcile" ]] || false
  printf '{"id":"RS-2","why_unreachable":"elapsed-time"}\n' >> "$REC/residual.jsonl"
  run "$CLI" reconcile --program demo
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "FAIL reconcile" ]] || false
  [[ "$output" == *"unmapped: residual:RS-2"* ]] || false
}

@test "lint passes on the good program and fails on a /tmp path in the plan" {
  run "$CLI" lint --program demo
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "PASS lint" ]] || false
  printf 'Scratch lives in /tmp/x.\n' >> "$REC/PLAN.md"
  run "$CLI" lint --program demo
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "FAIL lint" ]] || false
  [[ "$output" == *"path under /tmp"* ]] || false
}

# ── verdict ────────────────────────────────────────────────────────────────────────────────────

@test "verdict prints the render's state lines, then pending concerns, the wait and the menu" {
  printf '%s\n' '{"id":"C-1","triage":"pending"}' '{"id":"C-2","triage":"pending"}' \
    '{"id":"C-2","triage":"counted"}' > "$REC/challenges.jsonl"
  run "$CLI" verdict demo
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "Research: demo — registered; not certified."* ]] || false
  [[ "$output" == *"Pending concerns: 1"* ]] || false
  [[ "$output" == *"Waiting on you since: nothing open"* ]] || false
  [[ "$output" == *"cc-signoff research:demo/reopen"* ]] || false
  run "$CLI" verdict --program demo --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq_py "sorted(d)")" = "['lines', 'menu', 'overridden_relays', 'pending_concerns', 'program', 'state', 'waiting_since']" ]
  [ "$(printf '%s' "$output" | jq_py "(d['program'], d['state'], d['pending_concerns'], d['waiting_since'])")" = "('demo', 'registered', 1, None)" ]
  [ "$(printf '%s' "$output" | jq_py "sorted(d['menu'][0])")" = "['effect', 'id', 'label', 'price']" ]
}

@test "verdict on a certified program relays the certificate's lines" {
  "$CLI" gate run --program demo --consent-sealed-read >/dev/null
  run "$CLI" verdict demo
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "Research: demo version 1. CERTIFIED"* ]] || false
}

@test "verdict is a pure read: it writes nothing anywhere under the program's stores" {
  name_packets pk1
  stub_decide '[{"id":"pk1","created":"2026-09-20T00:00:00Z","status":"open"}]'
  vault caught
  before="$(snap)"
  run "$CLI" verdict demo
  [ "$status" -eq 0 ]
  run "$CLI" verdict demo --json
  [ "$status" -eq 0 ]
  [ "$(snap)" = "$before" ]
}

@test "waiting since is the oldest OPEN program packet's created date" {
  name_packets pk1 pk2 pk3
  stub_decide '[{"id":"pk1","created":"2026-09-10T00:00:00Z","status":"actioned"},{"id":"pk2","created":"2026-09-25T00:00:00Z","status":"open"},{"id":"pk3","created":"2026-09-20T00:00:00Z"},{"id":"other","created":"2026-01-01T00:00:00Z","status":"open"}]'
  run "$CLI" verdict demo --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq_py "d['waiting_since']")" = "2026-09-20T00:00:00Z" ]
  run "$CLI" verdict demo
  [[ "$output" == *"Waiting on you since 2026-09-20T00:00:00Z"* ]] || false
}

@test "waiting since reads unknown, never omitted, when cc-decide cannot be read" {
  name_packets pk1
  export CC_RESEARCH_CC_DECIDE="$W/no-such-cc-decide"
  run "$CLI" verdict demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"Waiting on you since unknown"* ]] || false
  run "$CLI" verdict demo --json
  [ "$(printf '%s' "$output" | jq_py "d['waiting_since']")" = "unknown" ]
}

@test "the research block's certificate read still whitelists the exact verdict command, and it runs" {
  run /usr/bin/python3 -c "import sys; sys.path.insert(0, '$KIT'); import router
print(router.cert_read('cc-research verdict demo', 'demo'), router.cert_read('cc-research verdict --program demo', 'demo'))"
  [ "$output" = "True True" ]
  run "$CLI" verdict --program demo
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "Research: demo"* ]] || false
}

# ── menu ───────────────────────────────────────────────────────────────────────────────────────

@test "menu offers the extra round set as a change to the round cap, and the reopen" {
  run "$CLI" menu --program demo --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq_py "[m['id'] for m in d]")" = "['extra-round', 'reopen']" ]
  [[ "$(printf '%s' "$output" | jq_py "d[0]['effect']")" == *"6 to 7"* ]] || false
  [ "$(printf '%s' "$output" | jq_py "d[1]['price']")" = "a new certificate version" ]
  run "$CLI" menu --program demo
  [[ "$output" == *"cc-signoff research:demo/extra-round"* ]] || false
  [[ "$output" == *"cc-signoff research:demo/reopen"* ]] || false
}

@test "menu quotes the extra round as unable to lower the bound once every seed is caught" {
  vault caught caught
  run "$CLI" menu --program demo --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq_py "d[0]['effect']")" = "no further desk review can lower this; only contact or building can" ]
  vault caught planted
  run "$CLI" menu --program demo --json
  [ "$(printf '%s' "$output" | jq_py "d[0]['effect']")" != "no further desk review can lower this; only contact or building can" ]
}

@test "menu drops the extra round set once a valid extra-round signature exists" {
  sign extra-round
  run "$CLI" menu --program demo --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq_py "[m['id'] for m in d]")" = "['reopen']" ]
}

# ── pending ────────────────────────────────────────────────────────────────────────────────────

@test "pending lists every program not closed and survives a corrupt one" {
  mkdir -p "$W/other/docs/research/broken" "$W/third"
  "$KIT/gate.sh" register --program broken --root "$W/other" >/dev/null
  "$KIT/gate.sh" register --program gone --root "$W/third" >/dev/null
  "$KIT/gate.sh" close --program gone >/dev/null
  printf 'not json\n' > "$W/other/docs/research/broken/challenges.jsonl"
  run "$CLI" pending --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq_py "[(p['program'], p['state']) for p in d['programs']]")" = "[('demo', 'registered'), ('broken', 'unknown')]" ]
  [ "$(printf '%s' "$output" | jq_py "sorted(d['programs'][0])")" = "['menu', 'overridden_relays', 'pending_concerns', 'program', 'state', 'waiting_since']" ]
  [ "$(printf '%s' "$output" | jq_py "d['programs'][1]['overridden_relays']")" = "None" ]
}

@test "pending carries the program's overridden relays from route-counters.json" {
  printf '{"programs":{"demo":{"overrides":2,"last_override_at":"2026-10-06T00:00:00Z"},"elsewhere":{"overrides":9}}}\n' \
    > "$CC_RESEARCH_HOME/route-counters.json"
  run "$CLI" pending --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq_py "d['programs'][0]['overridden_relays']")" = "2" ]
  run "$CLI" pending
  [ "$status" -eq 0 ]
  [[ "$output" == *"demo: "*" · overrode 2 relay(s)"* ]] || false
  run "$CLI" verdict demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"Relays you overrode as misrouted: 2"* ]] || false
}

@test "pending reads 0 overridden relays with no counters file, and says nothing about them" {
  [ ! -e "$CC_RESEARCH_HOME/route-counters.json" ]
  run "$CLI" pending --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq_py "d['programs'][0]['overridden_relays']")" = "0" ]
  run "$CLI" pending
  [ "$status" -eq 0 ]
  [[ "$output" != *"overrode"* ]] || false
  run "$CLI" verdict demo
  [ "$status" -eq 0 ]
  [[ "$output" != *"overrode as misrouted"* ]] || false
}

@test "pending reads 0 overridden relays from a garbled counters file and still exits 0" {
  printf 'not json\n' > "$CC_RESEARCH_HOME/route-counters.json"
  run "$CLI" pending --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq_py "d['programs'][0]['overridden_relays']")" = "0" ]
  # valid JSON of the wrong shape is garbled too
  printf '{"programs":{"demo":{"overrides":"many"}}}\n' > "$CC_RESEARCH_HOME/route-counters.json"
  run "$CLI" pending --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq_py "d['programs'][0]['overridden_relays']")" = "0" ]
}

# ── budget (§10 item 17: caps enforced in code) ──────────────────────────────────────────────────

@test "budget start and end stamp a stage; the report shows days used against the budget" {
  run "$CLI" budget start --stage 2 --program demo
  [ "$status" -eq 0 ]
  run "$CLI" budget end --stage 2 --program demo
  [ "$status" -eq 0 ]
  run "$CLI" budget --program demo --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq_py "(d['stages']['2']['ended'] == '$CC_NOW', d['stages']['1']['budget_days'], d['stages']['1']['days'])")" = "(True, 0.5, 0.25)" ]
}

@test "budget refuses to re-start a started stage and writes nothing" {
  before="$(snap)"
  run "$CLI" budget start --stage 1 --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"stage 1 already started"* ]] || false
  [ "$(snap)" = "$before" ]
}

@test "budget refuses to end a stage that never started and writes nothing" {
  before="$(snap)"
  run "$CLI" budget end --stage 3 --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"stage 3 never started"* ]] || false
  [ "$(snap)" = "$before" ]
}

@test "budget refuses the next stage while the last is over its cap with no overrun packet" {
  jedit budget.json "d['stages']['1']['started']='2026-09-01T00:00:00Z'"
  run "$CLI" budget --program demo
  [ "$status" -eq 1 ]
  before="$(snap)"
  run "$CLI" budget start --stage 2 --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"stage 1"* ]] || false
  [ "$(snap)" = "$before" ]
  jedit budget.json "d['overrun_packets']={'1': 'pk9'}"
  run "$CLI" budget --program demo
  [ "$status" -eq 0 ]
  run "$CLI" budget start --stage 2 --program demo
  [ "$status" -eq 0 ]
}

# ── ceiling ────────────────────────────────────────────────────────────────────────────────────

@test "ceiling prints the profile's totals as printed and adds the operator's wait to the calendar" {
  export CC_NOW="2026-10-01T00:00:00Z"
  run "$CLI" ceiling --program demo --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq_py "(d['profile'], d['typical_days'], d['ceiling_days'], d['wait_days'], d['calendar_ceiling_days'], d['elapsed_days'])")" = "('lite', 6.5, 12.0, 0.0, 12.0, 1.0)" ]
  name_packets pk1
  stub_decide '[{"id":"pk1","created":"2026-09-29T00:00:00Z","status":"open"}]'
  run "$CLI" ceiling --program demo --json
  [ "$(printf '%s' "$output" | jq_py "(d['waiting_since'], d['wait_days'], d['calendar_ceiling_days'])")" = "('2026-09-29T00:00:00Z', 2.0, 14.0)" ]
}

@test "E3c: ceiling on a v1.2 frame adds the yield ceiling and the Stage 9 budget, as the contract page does" {
  export CC_NOW="2026-10-01T00:00:00Z"
  jedit frame.json "d['method_version']='1.2'"
  run "$CLI" ceiling --program demo --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq_py "(d['ceiling_days'], d['yield_ceiling_days'], d['stage9_days'], d['calendar_ceiling_days'])")" = "(18.75, 5.25, 1.5, 18.75)" ]
  run "$CLI" ceiling --program demo
  [[ "$output" == *"about 18.75 days (lite profile, §6.1, plus the v1.2 yield ceiling 5.25 d and Stage 9 1.5 d)"* ]]
}

# ── reopen ─────────────────────────────────────────────────────────────────────────────────────

@test "reopen under a claude ancestor is refused with exit 2, names the operator command, writes nothing" {
  "$CLI" gate run --program demo --consent-sealed-read >/dev/null
  before="$(snap)"
  run "$FAKE_CLAUDE" -c "'$CLI' reopen --program demo"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cc-signoff research:demo/reopen"* ]] || false
  [ "$(snap)" = "$before" ]
}
