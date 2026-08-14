#!/usr/bin/env bats
# scripts/backlog-consolidation/{group,link}.py — grouping live rows into master efforts.
#
# WHAT IS ACTUALLY BEING PINNED. The mechanism under test is not "does a regex match" — it is the
# CONDITION LEASE's population. Every row joined to a condition becomes a sibling that can refuse a
# claim, so a wrong join is not a cosmetic misfile: it either freezes work (joining a HELD row makes
# the whole group unclaimable) or it moves a row out of a group whose lease is protecting a live
# worker (a re-key). Those two are the tests that matter, and both are red-proved per site.
#
# THE FIXTURE STORE IS BUILT WITH THE REAL bin/cc-backlog, never hand-written JSONL. The subject
# reads the FOLD (`list --all --json`), so a hand-rolled fixture would test this suite's idea of the
# fold rather than cc-backlog's — the exact sibling-auditor drift this repo keeps paying for
# (memory: sibling-auditors-must-share-the-state-model).

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  GROUP="$REPO/scripts/backlog-consolidation/group.py"
  LINK="$REPO/scripts/backlog-consolidation/link.py"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  export CC_BACKLOG_BIN="$CB"
}

# `! cmd` is exempt from errexit in bash, so a negative written that way only fails as the LAST line
# of a body. This returns non-zero directly and so fails anywhere.
refute_match() { [ "$(printf '%s' "$1" | grep -c "$2")" -eq 0 ]; }

add() { bash "$CB" add --project claude-infrastructure --title "$1" --source "${2:-fx}"; }
# `// ""` is load-bearing, not defensive. cmd_list RE-OMITS an empty condition (so a consumer can
# tell "no condition" from "an empty one"), so a bare `.condition` yields null and `jq -r` prints the
# four-character string "null" — which is non-empty, so every `[ -z ... ]` negative in this file
# passed vacuously against a subject that had written nothing. Three tests certified the opposite of
# what they read before this was found (memory: verification-harness-vacuous-pass-traps).
cond_of() { bash "$CB" list --all --json | jq -r --arg i "$1" '.[]|select(.id==$i)|(.condition // "")'; }
n_live() { bash "$CB" list --all --json | jq '[.[]|select(.status=="open" or .status=="blocked" or .status=="claimed")]|length'; }

# ── the two lease hazards ───────────────────────────────────────────────────────────────────────

@test "a row that ALREADY carries a condition is never re-keyed" {
  id=$(add "deploy-live REFUSES: no GREEN tree descends live HEAD")
  bash "$CB" link "$id" --condition hand-keyed-by-a-human
  run python3 "$GROUP" --apply
  [ "$status" -eq 0 ]
  # The taxonomy would route this to master-convergence-deadlock; the guard must win.
  [ "$(cond_of "$id")" = "hand-keyed-by-a-human" ]
}

@test "a CLAIMED row is never joined — joining a held row freezes its whole group" {
  held=$(add "cc-dispatch mislabels a wave-overflow as QUOTA CLIFF")
  sib=$(add "cc-dispatch defers every row with reason at-ceiling and fires nothing")
  bash "$CB" claim "$held" --by "$(hostname)-$$"
  run python3 "$GROUP" --apply
  [ "$status" -eq 0 ]
  [ -z "$(cond_of "$held")" ]
  # The unheld sibling is still grouped: the skip is scoped to the held row, not to its family.
  [ "$(cond_of "$sib")" = "master-fire-gate" ]
}

@test "a claimed row is reported as skipped rather than silently dropped" {
  held=$(add "cc-dispatch mislabels a wave-overflow as QUOTA CLIFF")
  bash "$CB" claim "$held" --by "$(hostname)-$$"
  run python3 "$GROUP" --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq '.claimed_skipped')" -eq 1 ]
}

# ── the match window (HEAD_CHARS) — both directions ─────────────────────────────────────────────

@test "an operator phrase in the OPENING clause routes the row to master-operator-gated" {
  id=$(add "Close the orphaned duplicate-worker panes in wt-149789b69fc4 BY HAND (iTerm2 cmd-W)")
  run python3 "$GROUP" --apply
  [ "$status" -eq 0 ]
  [ "$(cond_of "$id")" = "master-operator-gated" ]
}

@test "CONTROL — the SAME phrase 400 chars in does NOT steal the row (the incidental-mention bug)" {
  pad="$(printf 'context %.0s' $(seq 1 60))"
  id=$(add "19 skills live in ~/.claude/skills with NO tracked source — untracked and unlandable. $pad and the remedy was applied by hand (which is how it drifted)")
  run python3 "$GROUP" --apply
  [ "$status" -eq 0 ]
  # It must land in the store-integrity wave on `skills`, NOT in the operator batch.
  [ "$(cond_of "$id")" = "master-enforcing-store" ]
}

@test "underscores are word characters, so SCREAMING_SNAKE plan names must still classify" {
  id=$(add "advance START_LATENCY_ROUTER — claude1 pin + auto-routed claude")
  run python3 "$GROUP" --apply
  [ "$status" -eq 0 ]
  [ "$(cond_of "$id")" = "master-account-facts" ]
}

# ── the DoD invariants, so a later rule addition cannot silently break them ─────────────────────

@test "every master the taxonomy can emit has a plan file — a wave with no roadmap is unrunnable" {
  run python3 -c "
import sys; sys.path.insert(0, '$REPO/scripts/backlog-consolidation')
import group
print(' '.join(group.MASTERS))"
  [ "$status" -eq 0 ]
  for m in $output; do
    f="$REPO/docs/plans/$(printf '%s' "$m" | tr 'a-z-' 'A-Z_').md"
    [ -f "$f" ] || { echo "no plan file for $m at $f"; return 1; }
  done
}

@test "the taxonomy emits at most TEN masters (the effort budget is countable on two hands)" {
  run python3 -c "
import sys; sys.path.insert(0, '$REPO/scripts/backlog-consolidation')
import group; print(len(group.MASTERS))"
  [ "$status" -eq 0 ]
  [ "$output" -le 10 ]
}

@test "every taxonomy rule compiles and carries a non-empty reason" {
  run python3 -c "
import re, sys; sys.path.insert(0, '$REPO/scripts/backlog-consolidation')
import group
for m, p, why in group.TAXONOMY:
    re.compile(p)
    assert why.strip(), m
    assert m.startswith('master-'), m
print('ok')"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

# ── link.py, the writer ─────────────────────────────────────────────────────────────────────────

@test "link.py is DRY by default — a plan alone writes nothing" {
  id=$(add "re-land cloud-pipeline: ship-land exited 6")
  run bash -c "printf '%s master-stranded-work\n' '$id' | python3 '$LINK' --plan -"
  [ "$status" -eq 0 ]
  [ -z "$(cond_of "$id")" ]
  [ "$(printf '%s' "$output" | grep -c 'DRY RUN')" -eq 1 ]
}

@test "link.py skips and NAMES each refused population rather than failing the batch" {
  live=$(add "re-land probe-corpus: ship-land exited 6")
  done_id=$(add "a row that is already finished")
  bash "$CB" "done" "$done_id" --evidence "landed"
  run bash -c "printf '%s master-stranded-work\n%s master-stranded-work\ndeadbeefdead master-stranded-work\n' '$live' '$done_id' | python3 '$LINK' --plan - --run"
  [ "$status" -eq 0 ]
  [ "$(cond_of "$live")" = "master-stranded-work" ]
  # ANCHORED, not a substring. A mutation run caught this line passing against a mutant that had
  # renamed the counter to `unknown-id-MUT` — `grep 'unknown-id'` matched the mutant's own label, so
  # the assertion could not tell the rule from its corpse (memory: denylist-enumerates-spellings).
  [ "$(printf '%s' "$output" | grep -cE '^  skipped +[0-9]+ +not-live$')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -cE '^  skipped +[0-9]+ +unknown-id$')" -eq 1 ]
}

@test "link.py refuses to RE-KEY a conditioned row on its own — the enforcing copy of that rule" {
  # WHY THIS TEST EXISTS AND THE group.py ONE ABOVE IS NOT ENOUGH. Mutation-testing found that
  # deleting group.py's already-conditioned skip left the suite GREEN: this writer applies the same
  # predicate, and `cc-backlog link` refuses a re-key with rc 4 besides. Three copies of one rule,
  # two of which can actually refuse a write — so the site that ENFORCES it needs its own mutant.
  id=$(add "deploy-live REFUSES: no GREEN tree descends live HEAD")
  bash "$CB" link "$id" --condition hand-keyed-by-a-human
  run bash -c "printf '%s master-convergence-deadlock\n' '$id' | python3 '$LINK' --plan - --run"
  [ "$status" -eq 0 ]
  [ "$(cond_of "$id")" = "hand-keyed-by-a-human" ]
  [ "$(printf '%s' "$output" | grep -c 'already-conditioned')" -eq 1 ]
}

@test "link.py refuses a CLAIMED row on its OWN, not only via group.py's filter" {
  # PER-SITE COVERAGE. The lease-freeze guard exists in BOTH files, and the group.py test above
  # exercises only group.py's copy — a plan handed straight to the writer (a human at a terminal, a
  # future producer) reaches link.py's copy with nothing in front of it. A green suite that credits
  # no site is the defect (memory: per-site-mutation-attributes-coverage).
  held=$(add "re-land w2-cloud-rails: ship-land exited 5")
  bash "$CB" claim "$held" --by "$(hostname)-$$" >/dev/null
  run bash -c "printf '%s master-stranded-work\n' '$held' | python3 '$LINK' --plan - --run"
  [ "$status" -eq 0 ]
  [ -z "$(cond_of "$held")" ]
  [ "$(printf '%s' "$output" | grep -c 'claimed-would-freeze-group')" -eq 1 ]
}

@test "link.py asserts conservation=ok over a real write" {
  a=$(add "re-land deskless: ship-land exited 6")
  b=$(add "re-land detector-derive: ship-land exited 6")
  before=$(n_live)
  run bash -c "printf '%s master-stranded-work\n%s master-stranded-work\n' '$a' '$b' | python3 '$LINK' --plan - --run"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'conservation=ok')" -eq 1 ]
  [ "$(n_live)" -eq "$before" ]
}

@test "a writer that LOSES a row is caught: conservation=FAILED, rc 1" {
  # THE CONTROL FOR THE CONTROL. conservation=ok above cannot distinguish "the assertion works" from
  # "the assertion is inert", because a link genuinely changes nothing — so the FAILED arm needs a
  # subject that really does destroy a row. This stub is cc-backlog's interface with one lie in it:
  # its `link` closes the row instead of joining it, which is exactly the class the assertion exists
  # to catch (a fold that turned out to have a status arm).
  stub="$BATS_TEST_TMPDIR/stub-backlog"
  store="$BATS_TEST_TMPDIR/stub-store.json"
  printf '%s\n' '[{"id":"aaaaaaaaaaaa","status":"open","title":"t","project":"p","condition":""},{"id":"bbbbbbbbbbbb","status":"open","title":"u","project":"p","condition":""}]' > "$store"
  # The stub speaks the BULK interface (`link --plan -`, ids on stdin), because that is the one
  # call link.py now makes — a stub still answering the per-row form would be testing an interface
  # nothing uses (memory: sibling-auditors-must-share-the-state-model).
  cat > "$stub" <<STUB
#!/usr/bin/env bash
case "\$1" in
  list) cat "$store" ;;
  link) while read -r i _; do
          [ -n "\$i" ] || continue
          jq --arg i "\$i" 'map(select(.id != \$i))' "$store" > "$store.tmp" && mv "$store.tmp" "$store"
        done ;;
esac
STUB
  chmod +x "$stub"
  run bash -c "printf 'aaaaaaaaaaaa master-stranded-work\n' | python3 '$LINK' --plan - --run --bin '$stub'"
  [ "$status" -eq 1 ]
  # A FLOOR, not an exact count: the writer names each harmed row AND then summarises, so `-eq 1`
  # reds on the subject's own diagnostics growing rather than on a regression — which is what it did
  # when the span fix landed (memory: exact-count-assertion-tripwires-its-own-subject).
  [ "$(printf '%s' "$output" | grep -c 'conservation=FAILED')" -ge 1 ]
  [ "$(printf '%s' "$output" | grep -c 'GONE')" -ge 1 ]
  refute_match "$output" 'conservation=ok'
}

@test "SPAN: a sibling's write during link.py's run is 'unknown', never FAILED" {
  # Measured on the mechanical fold's first real apply: 46 links, 0 refused, and
  # `conservation=FAILED live 555→555 · open 330→331` — a sibling had unblocked an unrelated row
  # during the three minutes it took. A link has no status arm, so a changed count cannot be ours.
  a=$(add "re-land deskless: ship-land exited 6")
  wrap="$BATS_TEST_TMPDIR/cb-sibling"
  cat > "$wrap" <<WRAP
#!/usr/bin/env bash
if [ "\$1" = link ]; then
  bash "$CB" "\$@"; rc=\$?
  bash "$CB" add --project other --title "a sibling filed this mid-run" --source sib >/dev/null 2>&1
  exit \$rc
fi
exec bash "$CB" "\$@"
WRAP
  chmod +x "$wrap"
  run bash -c "printf '%s master-stranded-work\n' '$a' | python3 '$LINK' --plan - --run --bin '$wrap'"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'conservation=unknown')" -eq 1 ]
  refute_match "$output" 'conservation=FAILED'
  [ "$(cond_of "$a")" = "master-stranded-work" ]
}

@test "SPAN CONTROL — harming a row we linked is still FAILED, so 'unknown' is not an amnesty" {
  a=$(add "re-land probe-corpus: ship-land exited 6")
  wrap="$BATS_TEST_TMPDIR/cb-harm"
  # `link` now arrives as `link --plan -` with the ids on stdin, so the wrapper reads the plan
  # itself to learn which row to harm — it can no longer take the id from \$2.
  cat > "$wrap" <<WRAP
#!/usr/bin/env bash
if [ "\$1" = link ]; then
  plan="\$(cat)"
  printf '%s\n' "\$plan" | bash "$CB" "\$@"; rc=\$?
  printf '%s\n' "\$plan" | while read -r i _; do
    [ -n "\$i" ] && bash "$CB" block "\$i" --needs "harmed by the wrapper" >/dev/null 2>&1
  done
  exit \$rc
fi
exec bash "$CB" "\$@"
WRAP
  chmod +x "$wrap"
  run bash -c "printf '%s master-stranded-work\n' '$a' | python3 '$LINK' --plan - --run --bin '$wrap'"
  [ "$status" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'conservation=FAILED')" -ge 1 ]
  [ "$(printf '%s' "$output" | grep -c 'open→blocked')" -eq 1 ]
}

@test "link.py --dir replays a triage wave's verdicts.json, KEEP/UPDATE only" {
  d="$BATS_TEST_TMPDIR/triage"; mkdir -p "$d"
  keep=$(add "a kept row about cc-dispatch deferring everything")
  pruned=$(add "a row the triage wave pruned")
  printf '{"%s": ["dispatch", "KEEP"], "%s": ["dispatch", "PRUNE"]}\n' "$keep" "$pruned" > "$d/verdicts.json"
  run python3 "$LINK" --dir "$d" --run
  [ "$status" -eq 0 ]
  [ "$(cond_of "$keep")" = "master-fire-gate" ]
  [ -z "$(cond_of "$pruned")" ]
}

@test "link.py refuses a plan and a triage dir together — two sources of truth is the defect" {
  run python3 "$LINK" --plan - --dir /tmp
  [ "$status" -ne 0 ]
}
