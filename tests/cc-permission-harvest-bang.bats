#!/usr/bin/env bats
# cc-permission-harvest --bang: the operator's `!` commands as a candidate source for allow rules.
#
# What these arms protect. The list is only worth having if it does NOT allowlist the gates, so the
# arms below are mostly about what is REFUSED: a --confirm script, sudo, a deploy, a pane close, a
# cc-do queue item, a classifier-denied shape. Each must land in its gate bucket and never reach a
# proposal. Two rules are proposed from the fixture, and the arms pin exactly those two, so a
# widened classifier fails here as an EXTRA rule, not silently.
#
# Population laws (measured on the live stores 2026-10-01): a bang is a USER record whose content
# STARTS with `<bash-input>` in a top-level transcript. A quote of the marker inside a tool result
# and a subagent file are not bangs. Mirrored stores dedupe by realpath, copied ones by uuid.
#
# Harness laws, following tests/cc-permission-harvest-apply.bats: HOME is redirected and every
# settings file the tool could write is generated under it; write arms key on byte identity; apply
# runs strip the agent-session markers the runner itself carries. Two arms are MUTANTS: they run a
# copy of the tool with one fix reverted and assert the observable flips, so each fix is shown to
# be what makes its arm pass.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  HARVEST="$REPO/bin/cc-permission-harvest"
  FIXD="$REPO/tests/fixtures/permission-harvest"
  Q="$FIXD/qjson.py"
  python3 "$FIXD/mkbang.py" "$HOME"
  OUT="$BATS_TEST_TMPDIR/out"
  PROP="$OUT/latest.json"
  SETTINGS="$HOME/.claude/settings.json"
  export CC_PERMHARVEST_TRANSCRIPTS="$HOME/.claude*/projects"
  export CC_PERMHARVEST_SETTINGS_GLOB="$HOME/.claude*/settings.json"
  export CC_PERMHARVEST_CORPUS="$HOME/corpus.log"
  export CC_PERMARCHIVE_DIR="$HOME/no-archive"
  unset CLAUDE_CONFIG_DIR CC_PERMHARVEST_OUT
}

q() { python3 "$Q" "$PROP" "$@"; }

sha() { shasum -a 256 "$1" | awk '{print $1}'; }

harvest() { python3 "$HARVEST" --bang --out "$OUT" "$@"; }

# The write half runs as the operator would: no agent-session markers in the environment.
as_operator() { env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT "$@"; }

proposal() {
  run harvest --json
  [ "$status" -eq 0 ]
  [ -f "$PROP" ]
}

# A copy of the tool beside its matcher lib, with ONE source substitution applied.
mutant() {
  local from="$1" to="$2" dir="$BATS_TEST_TMPDIR/mutant"
  mkdir -p "$dir/bin" "$dir/hooks/lib"
  cp "$REPO/hooks/lib/permission_matcher.py" "$dir/hooks/lib/"
  FROM="$from" TO="$to" python3 - "$HARVEST" "$dir/bin/cc-permission-harvest" <<'PY'
import os, sys
s = open(sys.argv[1]).read()
assert s.count(os.environ["FROM"]) == 1, "mutation site not unique"
open(sys.argv[2], "w").write(s.replace(os.environ["FROM"], os.environ["TO"]))
PY
  MUTANT="$dir/bin/cc-permission-harvest"
}

@test "population: 16 bangs, mirrors deduped, a quoted marker and a subagent file are not bangs" {
  proposal
  [ "$(q get inputs.records_total)" = 16 ]
  [ "$(q get inputs.sessions_in_window)" = 5 ]
}

@test "provenance: a ▶ Run this: block, an inline span and an unprompted command are told apart" {
  proposal
  [ "$(q get provenance.marker)" = 14 ]
  [ "$(q get provenance.inline)" = 1 ]
  [ "$(q get provenance.none)" = 1 ]
}

@test "the agent's own classifier-denied attempt is joined to the bang and counted by category" {
  proposal
  [ "$(q get agent_attempt.classifier)" = 1 ]
  [ "$(q get 'classifier_categories.[Self-Modification]')" = 1 ]
  [ "$(q get buckets.classifier.count)" = 1 ]
}

@test "every gate class lands in its own bucket" {
  proposal
  # `git -C <path> push` is production too: the path between `git` and `push` hid it once.
  [ "$(q get buckets.production.count)" = 2 ]
  for b in consent_gate privilege live_session operator_queue gui_view one_shot compound; do
    [ "$(q get "buckets.$b.count")" = 1 ] || { echo "bucket $b"; false; }
  done
  [ "$(q get buckets.read_only.count)" = 6 ]
  [ "$(q get buckets.unclassified.count)" = 0 ]
}

@test "exactly two rules are proposed: the read-only prefix and the exact flag form" {
  proposal
  run q proposed
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'Bash(cc-decide list:*)\nBash(cc-do --list)')" ]
  [ "$(q receipt 'Bash(cc-do --list)' kind)" = exact ]
  # Exempt from the prefix-widening gate only; every other gate passed on its own.
  [ "$(q receipt 'Bash(cc-do --list)' exempt_gates | python3 -c 'import json,sys; print(",".join(json.load(sys.stdin)))')" = FLAG_HEAD ]
}

@test "a gate-bucket command never reaches a rule, even where its verb is otherwise read-only" {
  proposal
  for rule in 'Bash(cc-do:*)' 'Bash(kitten @ close-window:*)' 'Bash(fleet-sync now)' \
              'Bash(sudo pmset:*)' 'Bash(aws amplify:*)'; do
    run q has "$rule"
    [ "$status" -ne 0 ] || { echo "proposed: $rule"; false; }
  done
}

@test "a read-only form seen once is refused on MIN_EVIDENCE, never proposed" {
  proposal
  [ "$(q code 'Bash(cc-custody list:*)')" = MIN_EVIDENCE ]
}

@test "--check re-runs the BANG pipeline: both rules KEEP and nothing is written" {
  proposal
  before="$(sha "$SETTINGS")"
  run python3 "$HARVEST" --bang --out "$OUT" --check "$PROP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bash(cc-decide list:*)"*"KEEP → fleet"* ]] || false
  [[ "$output" == *"Bash(cc-do --list)"*"KEEP → fleet"* ]] || false
  [ "$(sha "$SETTINGS")" = "$before" ]
}

@test "apply writes the two rules, keeps the file's \\u escapes, and --falsify then retires" {
  proposal
  run python3 "$HARVEST" --bang --out "$OUT" --falsify "$PROP"
  [ "$status" -eq 1 ]
  run as_operator env CONFIRM=1 python3 "$HARVEST" --bang --out "$OUT" --apply "$PROP"
  [ "$status" -eq 0 ]
  python3 - "$SETTINGS" <<'PY'
import json, sys
text = open(sys.argv[1]).read()
allow = json.loads(text)["permissions"]["allow"]
assert allow == ["Bash(git status:*)", "Bash(cc-decide list:*)", "Bash(cc-do --list)"], allow
assert "\\u2014" in text and "—" not in text, "escapes were rewritten"
PY
  run python3 "$HARVEST" --bang --out "$OUT" --falsify "$PROP"
  [ "$status" -eq 0 ]
}

@test "a rule edited into a bang proposal is dropped at apply time, never written" {
  proposal
  python3 - "$PROP" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
e = dict(d["proposed"][0]); e["rule"] = "Bash(kitten @ close-window:*)"; e["head"] = "kitten @ close-window"
d["proposed"].append(e)
json.dump(d, open(sys.argv[1], "w"))
PY
  run as_operator env CONFIRM=1 python3 "$HARVEST" --bang --out "$OUT" --apply "$PROP"
  [[ "$output" == *"Bash(kitten @ close-window:*)"* ]] || false
  run grep -c 'close-window' "$SETTINGS"
  [ "$output" = 0 ]
}

@test "an agent session is refused at apply (exit 4) and nothing is written" {
  proposal
  before="$(sha "$SETTINGS")"
  run env CLAUDECODE=1 CONFIRM=1 python3 "$HARVEST" --bang --out "$OUT" --apply "$PROP"
  [ "$status" -eq 4 ]
  [ "$(sha "$SETTINGS")" = "$before" ]
}

@test "mutant: with ensure_ascii=False restored, apply rewrites the escapes (the arm above catches it)" {
  proposal
  mutant 'ensure_ascii=ascii_file)' 'ensure_ascii=False)'
  run as_operator env CONFIRM=1 python3 "$MUTANT" --bang --out "$OUT" --apply "$PROP"
  [ "$status" -eq 0 ]
  run grep -c '\\u2014' "$SETTINGS"
  [ "$output" = 0 ]
}

@test "mutant: counting any record that mentions the marker inflates the population" {
  mutant $'text = _bang_text(content)\n            if not text.lstrip().startswith(BANG_MARK):' \
         $'text = json.dumps(content)\n            if BANG_MARK not in text:'
  run python3 "$MUTANT" --bang --out "$OUT" --json
  [ "$status" -eq 0 ]
  [ "$(q get inputs.records_total)" != 16 ]
}
