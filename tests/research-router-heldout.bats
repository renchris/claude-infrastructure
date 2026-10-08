#!/usr/bin/env bats
# research-router-heldout — the candidate builder for the router's sealed held-out set and the
# router's gate-row-15 contract (REPORT.md §10 open items 11, 12 and 13; wave B1 of
# docs/plans/RESEARCH_PROGRAM_BUILD.md). Row 15 is driven end to end: candidates -> heldout.py seal
# -> two raters -> heldout.py evaluate with CC_RESEARCH_ROUTER pointing at `router.py classify`.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset CC_BATS_ACTIVE CC_RESEARCH_ROUTER CC_RESEARCH_ROUTER_INNER
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/rh" CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/rh/programs.json"
  export CC_RESEARCH_VAULT_KEY="test-key"
  export CC_RESEARCH_CLASSIFIER="$REPO/tests/fixtures/research-router/classifier-stub.sh"
  export CC_RESEARCH_CLASSIFIER_TIMEOUT=2
  CAND="$REPO/scripts/research-kit/heldout-candidates.py"
  H="$REPO/scripts/research-kit/heldout.py"
  ROUTER="$REPO/scripts/research-kit/router.py"
  T="$BATS_TEST_TMPDIR/projects/p"; mkdir -p "$T"
  # wave E1l: RULE E1k's passing figures on record and a quiet machine planted in the fixture home
  mkdir -p "$CC_RESEARCH_HOME/router-heldout"
  printf '{"rule":"E1k","run":2,"source":"fixture","rows":120,"fallbacks":1,"held_one_silent":0,"verdict":"PASS"}\n' \
    > "$CC_RESEARCH_HOME/router-heldout/real-load.json"
  printf '5\n' > "$CC_RESEARCH_HOME/router-heldout/load1.fixture"
}

# rec <type> <text> [extra-json] — one transcript record.
rec() {
  if [ "$1" = user ]; then
    jq -nc --arg t "$2" --argjson x "${3:-{\}}" '{type:"user",timestamp:"2026-09-20T10:00:00Z",message:{content:$t}} + $x'
  else
    jq -nc --arg t "$2" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}'
  fi
}

@test "§10 items 12-13: the candidate builder fills every stratum and drops machine-authored and meta records" {
  {
    rec user "are we 100% complete?"
    rec user "is this all before we close? anything we're missing"
    rec assistant "✅ Complete & live on trunk."
    rec user "ok what is the status of the wave"
    rec user "are you sure?"
    rec user "really?"
    rec user "are you sure about line 212 of foo.sh?"
    rec user "build the importer next"
    rec user "<task-notification>are we done</task-notification>"
    rec user "[handoff from x] are we done"
    rec user "are we done? (meta)" '{"isMeta":true}'
    rec user "TASK — are we done"
    rec user "are we 100% complete?"
  } > "$T/s1.jsonl"
  run python3 "$CAND" --transcripts "$T/*.jsonl" --out "$BATS_TEST_TMPDIR/c.jsonl"
  [ "$status" -eq 0 ]
  # It prints counts, never a prompt. A challenge WITH a location is gap-seeking, not pushback:
  # it lands in regex-missed, where the raters label it (a concern, §4.1).
  [ "$(printf '%s' "$output" | grep -c 'importer')" -eq 0 ]
  c="$BATS_TEST_TMPDIR/c.jsonl"
  [ "$(jq -r 'select(.stratum=="regex-matched") | .prompt' "$c")" = "are we 100% complete?" ]
  [ "$(jq -r 'select(.stratum=="regex-missed") | .prompt' "$c" | sort | tr '\n' '|')" = "are you sure about line 212 of foo.sh?|is this all before we close? anything we're missing|ok what is the status of the wave|" ]
  [ "$(jq -r 'select(.stratum=="pushback") | .prompt' "$c" | sort | tr '\n' '|')" = "are you sure?|really?|" ]
  [ "$(jq -r 'select(.stratum=="other") | .prompt' "$c" | sort | tr '\n' '|')" = "build the importer next|" ]
  [ "$(jq -r .source "$c" | head -1)" = "s1@2026-09-20T10:00:00" ]
  [ "$(grep -c 'task-notification\|handoff from\|(meta)\|TASK' "$c")" -eq 0 ]
}

@test "§10 item 13: a missing stratum is reported, so seal is never fed a set it will refuse" {
  rec user "build the importer next" > "$T/s1.jsonl"
  run python3 "$CAND" --transcripts "$T/*.jsonl" --out "$BATS_TEST_TMPDIR/c.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no regex-matched, regex-missed, pushback candidate"* ]]
}

@test "the per-stratum sample is capped and deterministic" {
  for i in $(seq 1 30); do rec user "build widget $i"; done > "$T/s1.jsonl"
  python3 "$CAND" --transcripts "$T/*.jsonl" --cap 7 --out "$BATS_TEST_TMPDIR/a.jsonl" || true
  python3 "$CAND" --transcripts "$T/*.jsonl" --cap 7 --out "$BATS_TEST_TMPDIR/b.jsonl" || true
  [ "$(wc -l < "$BATS_TEST_TMPDIR/a.jsonl" | tr -d ' ')" -eq 7 ]
  cmp -s "$BATS_TEST_TMPDIR/a.jsonl" "$BATS_TEST_TMPDIR/b.jsonl"
}

@test "wave E1c: the prompt history is a second store, a challenge is pushback wherever it sits, and one stratum takes its own cap" {
  {
    rec user "are we 100% complete?"
    rec user "build the importer next"
  } > "$T/s1.jsonl"
  mkdir -p "$BATS_TEST_TMPDIR/acct"
  {
    jq -nc '{display:"hmm, are you sure?",timestamp:1790000000000}'
    jq -nc '{display:"that cant be right",timestamp:1790000000001}'
    jq -nc '{display:"how do you know line 40 is wrong?",timestamp:1790000000002}'
    jq -nc '{display:"/wrap",timestamp:1790000000003}'
    jq -nc '{display:"are we 100% complete?",timestamp:1790000000004}'
    jq -nc '{display:"anything else we are missing",timestamp:1790000000005}'
    for i in 1 2 3 4 5; do jq -nc --arg i "$i" '{display:("build gadget " + $i),timestamp:1790000000010}'; done
    printf 'not json\n'
  } > "$BATS_TEST_TMPDIR/acct/history.jsonl"
  run python3 "$CAND" --transcripts "$T/*.jsonl" --history "$BATS_TEST_TMPDIR/acct/history.jsonl" --cap-for other=3 --out "$BATS_TEST_TMPDIR/c.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 transcript(s), 1 history file(s)"* ]] || false
  [ "$(printf '%s' "$output" | grep -c 'gadget')" -eq 0 ]
  c="$BATS_TEST_TMPDIR/c.jsonl"
  [ "$(jq -r 'select(.stratum=="pushback") | .prompt' "$c" | sort | tr '\n' '|')" = "hmm, are you sure?|that cant be right|" ]
  # a challenge WITH a location stays out of pushback; the transcript's copy of a prompt wins
  [ "$(jq -r 'select(.stratum=="regex-matched") | .source' "$c")" = "s1@2026-09-20T10:00:00" ]
  [ "$(jq -r 'select(.stratum=="regex-missed") | .prompt' "$c")" = "anything else we are missing" ]
  [ "$(jq -r 'select(.stratum=="other") | .prompt' "$c" | wc -l | tr -d ' ')" -eq 3 ]
  [ "$(jq -r 'select(.prompt=="hmm, are you sure?") | .source' "$c")" = "history:acct@1790000000000" ]
  [ "$(grep -c '/wrap' "$c")" -eq 0 ]
  run python3 "$CAND" --transcripts "$T/*.jsonl" --cap-for bogus=3 --out "$c"
  [ "$status" -eq 2 ]
}

@test "gate row 15 contract: router.py classify prints ONE route label, and exits non-zero on a fallback" {
  run bash -c "printf 'are we done?' | python3 '$ROUTER' classify"
  [ "$status" -eq 0 ]
  [ "$output" = completeness ]
  run bash -c "printf 'STUB-ERROR' | python3 '$ROUTER' classify"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  # wave E1h: the work-order marker counts only for the program being routed
  run bash -c "printf 'x --requires-gate demo' | CC_RESEARCH_CLASSIFIER=false CC_RESEARCH_RENDER=true python3 '$ROUTER' classify --program demo"
  [ "$output" = work-order ]
  run bash -c "printf 'x --requires-gate demo' | CC_RESEARCH_CLASSIFIER=false python3 '$ROUTER' classify"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "ruling 4bf73c4e55d5: a classifier answering in 6.5 s is labeled by classify and by row 15's route, not dropped" {
  # The limit is 9 s on both sides (REPORT.md §9, ruled 2026-10-04); it was 6 s, which a cold
  # `claude -p` on haiku overran at load (wave B1 notes). The setup's 2 s test override is lifted so
  # the shipped default is what runs.
  unset CC_RESEARCH_CLASSIFIER_TIMEOUT
  run bash -c "printf 'x' | CC_RESEARCH_CLASSIFIER='cat >/dev/null; sleep 6.5; echo completeness' python3 '$ROUTER' classify"
  [ "$status" -eq 0 ]
  [ "$output" = completeness ]
  run python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import heldout; print(heldout.route("cat >/dev/null; sleep 6.5; echo pushback", "x"))' "$REPO/scripts/research-kit"
  [ "$output" = pushback ]
}

# A sealed, two-rater-labeled set of 12 per stratum, labeled the way the stub answers.
seal_set() {
  local i
  for i in $(seq 1 12); do
    printf '{"prompt":"are we done with part %s?","stratum":"regex-matched"}\n' "$i"
    printf '{"prompt":"is it good to close now, %s","stratum":"regex-missed"}\n' "$i"
    printf '{"prompt":"are you sure, %s?","stratum":"pushback"}\n' "$i"
    printf '{"prompt":"build widget %s","stratum":"other"}\n' "$i"
  done > "$BATS_TEST_TMPDIR/c.jsonl"
  "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0 >/dev/null
  "$H" rater-sheet --out "$BATS_TEST_TMPDIR/sheet.jsonl" >/dev/null
  python3 - "$BATS_TEST_TMPDIR/sheet.jsonl" "$BATS_TEST_TMPDIR/labels.jsonl" <<'EOF'
import json, sys
out = open(sys.argv[2], "w")
for l in open(sys.argv[1]):
    r = json.loads(l); p = r["prompt"]
    lab = "pushback" if "sure" in p else "work-order" if "build" in p else "completeness"
    out.write(json.dumps({"id": r["id"], "label": lab}) + "\n")
EOF
  "$H" label --rater openai --labels "$BATS_TEST_TMPDIR/labels.jsonl" >/dev/null
  "$H" label --rater google --labels "$BATS_TEST_TMPDIR/labels.jsonl" >/dev/null
}

@test "gate row 15 measures router.py classify on the sealed set and passes it" {
  seal_set
  CC_RESEARCH_ROUTER="python3 '$ROUTER' classify" run "$H" evaluate --consent-sealed-read
  [ "$status" -eq 0 ]
  [[ "$output" == *"stratum regex-missed: 12/12"* ]]
}

@test "§10 item 11: an always-failing classifier fails row 15 on its fallback rate" {
  seal_set
  CC_RESEARCH_CLASSIFIER=false CC_RESEARCH_ROUTER="python3 '$ROUTER' classify" run "$H" evaluate --consent-sealed-read
  [ "$status" -eq 1 ]
  [[ "$output" == *"fallback rate 1.00"* ]]
}

@test "a router that always falls back scores 0 recall in every completeness stratum and names its fallback share" {
  seal_set
  CC_RESEARCH_ROUTER="cat >/dev/null; exit 1" run "$H" evaluate --consent-sealed-read
  [ "$status" -eq 1 ]
  [[ "$output" == *"stratum regex-matched: recall 0/12"* ]] || false
  [[ "$output" == *"stratum pushback: recall 0/12"* ]] || false
  [[ "$output" == *"48 of 48 routed item(s) fell back (share 1.00)"* ]]
}

@test "one fallback inside the fallback-rate bound is still a recall miss, never a relay" {
  seal_set
  # One regex-matched prompt falls back (1/48 = 0.02, under the 0.10 rate); the stratum drops to 11/12.
  CC_RESEARCH_ROUTER="p=\$(cat); case \"\$p\" in 'are we done with part 1?') exit 1 ;; esac; printf '%s' \"\$p\" | python3 '$ROUTER' classify" run "$H" evaluate --consent-sealed-read
  [ "$status" -eq 1 ]
  [[ "$output" == *"stratum regex-matched: recall 11/12"* ]] || false
  [[ "$output" == *"1 of 48 routed item(s) fell back (share 0.02)"* ]]
}

@test "§10 items 11-12: a classifier that labels everything a work order fails recall in every completeness stratum" {
  seal_set
  CC_RESEARCH_CLASSIFIER="cat >/dev/null; echo work-order" CC_RESEARCH_ROUTER="python3 '$ROUTER' classify" run "$H" evaluate --consent-sealed-read
  [ "$status" -eq 1 ]
  [[ "$output" == *"stratum regex-matched: recall 0/12"* ]] || false
  [[ "$output" == *"stratum pushback: recall 0/12"* ]]
}

# A stub vendor CLI: reads the rater brief (its LAST argument), answers one JSON line per prompt.
stub_vendor() { # <path> <anthropic|openai>
  cat > "$1" <<STUB
#!/usr/bin/env python3
import json, re, sys
brief = sys.argv[-1]
lines = []
for m in re.finditer(r'^\{"id": "([0-9a-f]+)", "prompt": "(.*)"\}$', brief, re.M):
    p = m.group(2)
    lab = "pushback" if "sure" in p else "work-order" if "build" in p else "completeness"
    lines.append(json.dumps({"id": m.group(1), "label": lab}))
reply = "\n".join(lines)
if "$2" == "anthropic":
    print(json.dumps({"result": reply, "modelUsage": {"claude-rater-1": {"outputTokens": 5}}}))
else:
    print(json.dumps({"type": "thread.started", "thread_id": "t1"}))
    print(json.dumps({"type": "item.completed", "item": {"type": "agent_message", "text": reply}}))
STUB
  chmod +x "$1"
}

@test "§10 item 13: two raters of two vendor families label the sealed set through the courier path; a same-family second rater is refused" {
  for i in $(seq 1 12); do
    printf '{"prompt":"are we done with part %s?","stratum":"regex-matched"}\n' "$i"
    printf '{"prompt":"is it good to close now, %s","stratum":"regex-missed"}\n' "$i"
    printf '{"prompt":"are you sure, %s?","stratum":"pushback"}\n' "$i"
    printf '{"prompt":"build widget %s","stratum":"other"}\n' "$i"
  done > "$BATS_TEST_TMPDIR/c.jsonl"
  "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0 >/dev/null
  RATE="$REPO/scripts/research-kit/heldout-rate.py"
  stub_vendor "$BATS_TEST_TMPDIR/claude-stub" anthropic
  stub_vendor "$BATS_TEST_TMPDIR/codex-stub" openai
  mkdir -p "$BATS_TEST_TMPDIR/codex/2026"
  printf '{"model":"gpt-rater-2"}\n' > "$BATS_TEST_TMPDIR/codex/2026/rollout-x-t1.jsonl"
  export CC_RESEARCH_CODEX_SESSIONS="$BATS_TEST_TMPDIR/codex"
  run python3 "$RATE" --vendor anthropic --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would send 48 prompt(s)"* ]] || false
  CC_RESEARCH_BIN_ANTHROPIC="$BATS_TEST_TMPDIR/claude-stub" run python3 "$RATE" --vendor anthropic
  [ "$status" -eq 0 ]
  [[ "$output" == *"anthropic:claude-rater-1: 48 label(s) recorded"* ]] || false
  # frontier is the Anthropic family too
  CC_RESEARCH_BIN_ANTHROPIC="$BATS_TEST_TMPDIR/claude-stub" run python3 "$RATE" --vendor frontier
  [ "$status" -eq 2 ]
  [[ "$output" == *"another vendor family"* ]] || false
  CC_RESEARCH_BIN_OPENAI="$BATS_TEST_TMPDIR/codex-stub" run python3 "$RATE" --vendor openai
  [ "$status" -eq 0 ]
  # The set now measures: router.py classify passes row 15 against these gold labels.
  CC_RESEARCH_ROUTER="python3 '$ROUTER' classify" run "$H" evaluate --consent-sealed-read
  [ "$status" -eq 0 ]
}

@test "wave E1c: a rater labels a named set in batches, asks a short batch again once, and records nothing while one stays short" {
  for i in $(seq 1 12); do
    printf '{"prompt":"are we done with part %s?","stratum":"regex-matched"}\n' "$i"
    printf '{"prompt":"is it good to close now, %s","stratum":"regex-missed"}\n' "$i"
    printf '{"prompt":"are you sure, %s?","stratum":"pushback"}\n' "$i"
    printf '{"prompt":"build widget %s","stratum":"other"}\n' "$i"
  done > "$BATS_TEST_TMPDIR/c.jsonl"
  "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0 >/dev/null
  sed 's/part \([0-9]*\)/piece \1/; s/now, /today, /; s/sure, /certain, /; s/widget/gizmo/' "$BATS_TEST_TMPDIR/c.jsonl" > "$BATS_TEST_TMPDIR/c2.jsonl"
  "$H" --set v2 seal --candidates "$BATS_TEST_TMPDIR/c2.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t2.jsonl" --fraction 1.0 >/dev/null
  RATE="$REPO/scripts/research-kit/heldout-rate.py"
  stub_vendor "$BATS_TEST_TMPDIR/claude-real" anthropic
  # counts its calls; the 3rd call labels an id nobody asked about when FAIL_THIRD is set
  cat > "$BATS_TEST_TMPDIR/claude-stub" <<STUB
#!/bin/bash
n=\$(( \$(cat "$BATS_TEST_TMPDIR/calls" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$BATS_TEST_TMPDIR/calls"
if { [ "\$n" -ge 3 ] && [ "\${FAIL_THIRD:-}" = always ]; } || { [ "\$n" -eq 3 ] && [ "\${FAIL_THIRD:-}" = once ]; }; then echo '{"result": "{\\"id\\": \\"nope\\", \\"label\\": \\"other\\"}", "modelUsage": {"claude-rater-1": {}}}'; exit 0; fi
exec "$BATS_TEST_TMPDIR/claude-real" "\$@"
STUB
  chmod +x "$BATS_TEST_TMPDIR/claude-stub"
  run python3 "$RATE" --vendor anthropic --set v2 --batch 20 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would send 48 prompt(s) of set v2 to anthropic in 3 call(s)"* ]] || false
  # the last batch comes back short twice: asked again once, then nothing is recorded
  FAIL_THIRD=always CC_RESEARCH_BIN_ANTHROPIC="$BATS_TEST_TMPDIR/claude-stub" run python3 "$RATE" --vendor anthropic --set v2 --batch 20
  [ "$status" -eq 2 ]
  [[ "$output" == *"labeled 40 of 48 prompt(s); nothing recorded"* ]] || false
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" -eq 4 ]
  [ "$("$H" --set v2 status 2>/dev/null | jq '[.[].raters | length] | add')" -eq 0 ]
  # short once: the second asking of that batch is whole, and every label is recorded
  rm -f "$BATS_TEST_TMPDIR/calls"
  FAIL_THIRD=once CC_RESEARCH_BIN_ANTHROPIC="$BATS_TEST_TMPDIR/claude-stub" run python3 "$RATE" --vendor anthropic --set v2 --batch 20
  [ "$status" -eq 0 ]
  [[ "$output" == *"anthropic:claude-rater-1: 48 label(s) recorded"* ]] || false
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" -eq 4 ]
  # v2 took the labels; v1 has none
  [ "$("$H" --set v1 status 2>/dev/null | jq '[.[].raters | length] | add')" -eq 0 ]
  [ "$("$H" --set v2 status 2>/dev/null | jq '[.[].raters["anthropic:claude-rater-1"]] | add')" -eq 48 ]
}

@test "a rater that labels only part of the set records nothing" {
  for i in $(seq 1 12); do for s in regex-matched regex-missed pushback other; do
    printf '{"prompt":"p %s %s","stratum":"%s"}\n' "$s" "$i" "$s"; done; done > "$BATS_TEST_TMPDIR/c.jsonl"
  "$H" seal --candidates "$BATS_TEST_TMPDIR/c.jsonl" --tuning-out "$BATS_TEST_TMPDIR/t.jsonl" --fraction 1.0 >/dev/null
  printf '#!/bin/bash\necho %s\n' "'{\"result\": \"{\\\"id\\\": \\\"nope\\\", \\\"label\\\": \\\"other\\\"}\", \"modelUsage\": {\"m\": {}}}'" > "$BATS_TEST_TMPDIR/bad"
  chmod +x "$BATS_TEST_TMPDIR/bad"
  CC_RESEARCH_BIN_ANTHROPIC="$BATS_TEST_TMPDIR/bad" run python3 "$REPO/scripts/research-kit/heldout-rate.py" --vendor anthropic
  [ "$status" -eq 2 ]
  [[ "$output" == *"labeled 0 of 48"* ]] || false
  [ "$("$H" status | jq '[.[].raters | length] | add')" -eq 0 ]
}

# ── wave E1h ────────────────────────────────────────────────────────────────────────────────────

@test "wave E1h: --live-frame makes a history row what the hook received: no ! line, a paste expanded from the row or the cache, a lost paste dropped" {
  : > "$T/s1.jsonl"
  mkdir -p "$BATS_TEST_TMPDIR/acct/paste-cache" "$BATS_TEST_TMPDIR/elsewhere/paste-cache"
  printf 'the cached paste body' > "$BATS_TEST_TMPDIR/acct/paste-cache/abc123.txt"
  printf 'a paste kept by another account' > "$BATS_TEST_TMPDIR/elsewhere/paste-cache/def456.txt"
  {
    jq -nc '{display:"!git status",timestamp:1,pastedContents:{}}'
    jq -nc '{display:"build gadget one",timestamp:2,pastedContents:{}}'
    jq -nc '{display:"review this [Pasted text #1 +3 lines] please",timestamp:3,pastedContents:{"1":{id:1,type:"text",content:"INLINE BODY"}}}'
    jq -nc '{display:"and this [Pasted text #1 +9 lines]",timestamp:4,pastedContents:{"1":{id:1,type:"text",contentHash:"abc123"}}}'
    jq -nc '{display:"lost [Pasted text #1 +2 lines]",timestamp:5,pastedContents:{"1":{id:1,type:"text",contentHash:"000000"}}}'
    jq -nc '{display:"none [Pasted text #2]",timestamp:6,pastedContents:{}}'
    jq -nc '{display:"far [Pasted text #1 +1 lines]",timestamp:7,pastedContents:{"1":{id:1,type:"text",contentHash:"def456"}}}'
  } > "$BATS_TEST_TMPDIR/acct/history.jsonl"
  c="$BATS_TEST_TMPDIR/c.jsonl"
  # as before without the flag: the display strings, the ! line among them
  run python3 "$CAND" --transcripts "$T/*.jsonl" --history "$BATS_TEST_TMPDIR/acct/history.jsonl" --out "$c"
  [ "$(jq -r .prompt "$c" | wc -l | tr -d ' ')" -eq 7 ]
  [ "$(grep -c 'Pasted text' "$c")" -eq 5 ]
  run python3 "$CAND" --transcripts "$T/*.jsonl" --history "$BATS_TEST_TMPDIR/acct/history.jsonl" --live-frame --out "$c"
  [[ "$output" != *"BODY"* ]] || false
  [ "$(jq -r .prompt "$c" | sort | tr '\n' '|')" = "and this the cached paste body|build gadget one|review this INLINE BODY please|" ]
  run python3 "$CAND" --transcripts "$T/*.jsonl" --history "$BATS_TEST_TMPDIR/acct/history.jsonl" --live-frame \
    --paste-cache "$BATS_TEST_TMPDIR/else*/paste-cache" --out "$c"
  [ "$(jq -r .prompt "$c" | grep -c 'a paste kept by another account')" -eq 1 ]
  [ "$(jq -r .prompt "$c" | wc -l | tr -d ' ')" -eq 4 ]
}

@test "wave E1h: a rater labels a clear tuning file into a labels file, by the sealed set's ids, once, and prints no prompt" {
  for i in $(seq 1 6); do
    printf '{"prompt":"are we done with part %s?","stratum":"regex-matched"}\n' "$i"
    printf '{"prompt":"build widget %s","stratum":"other"}\n' "$i"
  done > "$BATS_TEST_TMPDIR/tune.jsonl"
  printf '{"prompt":"build widget 1","stratum":"other"}\n' >> "$BATS_TEST_TMPDIR/tune.jsonl"   # a repeat is rated once
  RATE="$REPO/scripts/research-kit/heldout-rate.py"
  stub_vendor "$BATS_TEST_TMPDIR/claude-stub" anthropic
  stub_vendor "$BATS_TEST_TMPDIR/codex-stub" openai
  mkdir -p "$BATS_TEST_TMPDIR/codex/2026"
  printf '{"model":"gpt-rater-2"}\n' > "$BATS_TEST_TMPDIR/codex/2026/rollout-x-t1.jsonl"
  export CC_RESEARCH_CODEX_SESSIONS="$BATS_TEST_TMPDIR/codex"
  run python3 "$RATE" --vendor anthropic --tuning "$BATS_TEST_TMPDIR/tune.jsonl" --out "$BATS_TEST_TMPDIR/la.jsonl" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would send 12 prompt(s) of tuning file tune.jsonl"*"in 1 call(s)"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/la.jsonl" ]
  CC_RESEARCH_BIN_ANTHROPIC="$BATS_TEST_TMPDIR/claude-stub" run python3 "$RATE" --vendor anthropic --batch 5 \
    --tuning "$BATS_TEST_TMPDIR/tune.jsonl" --out "$BATS_TEST_TMPDIR/la.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"anthropic:claude-rater-1: 12 label(s) written"* ]] || false
  [[ "$output" != *"widget"* ]] || false
  CC_RESEARCH_BIN_OPENAI="$BATS_TEST_TMPDIR/codex-stub" run python3 "$RATE" --vendor openai \
    --tuning "$BATS_TEST_TMPDIR/tune.jsonl" --out "$BATS_TEST_TMPDIR/lo.jsonl"
  [ "$status" -eq 0 ]
  [ "$(jq -r '"\(.rater) \(.label)"' "$BATS_TEST_TMPDIR/la.jsonl" "$BATS_TEST_TMPDIR/lo.jsonl" | sort | uniq -c | tr -s ' ' | tr '\n' ';')" = " 6 anthropic:claude-rater-1 completeness; 6 anthropic:claude-rater-1 work-order; 6 openai:gpt-rater-2 completeness; 6 openai:gpt-rater-2 work-order;" ]
  # the ids are heldout.py's ids of the prompts
  want="$(python3 -c 'import hashlib;print(hashlib.sha256(b"build widget 3").hexdigest()[:12])')"
  [ "$(jq -r --arg w "$want" 'select(.id==$w) | .label' "$BATS_TEST_TMPDIR/la.jsonl")" = work-order ]
  # a labels file is written once; --tuning needs --out and takes no --set; no sealed set was needed
  CC_RESEARCH_BIN_ANTHROPIC="$BATS_TEST_TMPDIR/claude-stub" run python3 "$RATE" --vendor anthropic \
    --tuning "$BATS_TEST_TMPDIR/tune.jsonl" --out "$BATS_TEST_TMPDIR/la.jsonl"
  [ "$status" -eq 2 ]
  [[ "$output" == *"written once"* ]] || false
  run python3 "$RATE" --vendor anthropic --tuning "$BATS_TEST_TMPDIR/tune.jsonl"
  [ "$status" -eq 2 ]
  [ ! -e "$CC_RESEARCH_HOME/router-heldout/sealed.enc" ]
  # a rater that never labels one prompt: nothing is written, unless --allow-short covers it
  skip_id="$(python3 -c 'import hashlib;print(hashlib.sha256(b"build widget 2").hexdigest()[:12])')"
  printf '#!/bin/bash\n"%s" "$@" | sed "s/{[^{}]*%s[^{}]*}//"\n' "$BATS_TEST_TMPDIR/claude-stub" "$skip_id" > "$BATS_TEST_TMPDIR/claude-short"
  chmod +x "$BATS_TEST_TMPDIR/claude-short"
  CC_RESEARCH_BIN_ANTHROPIC="$BATS_TEST_TMPDIR/claude-short" run python3 "$RATE" --vendor anthropic \
    --tuning "$BATS_TEST_TMPDIR/tune.jsonl" --out "$BATS_TEST_TMPDIR/ls.jsonl"
  [ "$status" -eq 2 ]
  [[ "$output" == *"labeled 11 of 12 prompt(s); nothing recorded"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/ls.jsonl" ]
  CC_RESEARCH_BIN_ANTHROPIC="$BATS_TEST_TMPDIR/claude-short" run python3 "$RATE" --vendor anthropic --allow-short 1 \
    --tuning "$BATS_TEST_TMPDIR/tune.jsonl" --out "$BATS_TEST_TMPDIR/ls.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"11 label(s) written"*"1 prompt(s) left unlabeled"* ]] || false
  [ "$(wc -l < "$BATS_TEST_TMPDIR/ls.jsonl" | tr -d ' ')" -eq 11 ]
  run python3 "$RATE" --vendor anthropic --allow-short 1
  [ "$status" -eq 2 ]
}
