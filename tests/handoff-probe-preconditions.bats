#!/usr/bin/env bats
# THE READ-ONLY PRECONDITION PROBE, AND THE CROSS-ROOT SEARCH IT RESTS ON.
#
# W2 shipped `--probe-recycle-preconditions` as the refusable read that must happen BEFORE the
# transplant — it is the whole cure for the four husks of 2026-09-19, where the launcher refused
# 11-16 s AFTER the transcript had already moved. It shipped with NO direct test: the only thing
# naming it in tests/ was a STUB of the whole binary in lr-handoff-launcher-quoting.bats. It was
# therefore possible for the verb to be wrong in a way that no suite could see, and it was:
#
#   for _f in ${CC_PROJECTS_DIRS:-$HOME/.claude*/projects}/*/"$SID".jsonl
#
# `${LIST}/*/x` is ONE word before field splitting, so the literal suffix attaches only to the LAST
# element of $LIST; every earlier element expands to a bare directory path that no [ -f ] can match.
# Measured 2026-09-20 against the LIVE layer: the probe searched only ~/.claude-quaternary/projects
# and answered REFUSED:no-transcript for a session whose transcript sat in ~/.claude-tertiary —
# four of the five config roots invisible, i.e. the precheck refused ~80% of recoverable sessions.
# It fails CLOSED (it refuses, it moves nothing) so it cost no data; it made recovery impossible.
#
# WHY NO EXISTING FIXTURE COULD HAVE CAUGHT IT: every suite fixtures ONE config root, and with one
# root the broken form and the correct form are identical. Two disjoint identifier spaces given one
# shape make the address bug unreachable — docs/lessons/fixture-shape-hides-address-bugs.md. So
# every case here fixtures TWO roots and puts the subject in the FIRST.
#
# RED-PROOFS vs GUARDS, stated so no one has to re-derive it: cases 1 and 5 are the red-proofs —
# both fail on the unfixed tree, 1 with "the probe did not look in the FIRST config root" and 5
# with an empty result. Cases 2, 3 and 4 are GREEN IN BOTH ARMS by construction and are labelled
# so in their names: they pin the properties the fix must not trade away (the last root still
# works, a genuine miss still fails closed, the probe still writes nothing).
#
# The UNSET default hides it too (`$HOME/.claude*/projects/*/x` is one word carrying TWO globs, and
# that does expand across roots), and handoff-fire.sh:399 always SETS the variable — so the broken
# arm was the only one that ever ran.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # HERMETICITY (land ratchet): no live machine load, and the three seams that do NOT resolve
  # under $HOME point at absent paths inside the test dir.
  export CC_ADMIT_GATE=off
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"

  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  SID="a1b2c3d4-0000-4000-8000-000000000001"
  PANE=900
  printf '{"session_id":"%s","pane":"%s"}\n' "$SID" "$PANE" > "$CC_REGISTRY_DIR/$PANE.json"

  # TWO roots, deliberately. ROOT_A is FIRST in the list and is where the broken form cannot look.
  ROOT_A="$BATS_TEST_TMPDIR/cfgA/projects"; ROOT_B="$BATS_TEST_TMPDIR/cfgB/projects"
  mkdir -p "$ROOT_A/-some-repo" "$ROOT_B/-some-repo"
  export CC_PROJECTS_DIRS="$ROOT_A $ROOT_B"
}

# a transcript whose LAST assistant record is a usage-limit error
seed_limited_transcript() { # $1=dir
  printf '%s\n' \
    '{"type":"user","timestamp":"2026-09-20T00:00:00.000Z","message":{"role":"user","content":"go"}}' \
    '{"type":"assistant","timestamp":"2026-09-20T00:00:01.000Z","isApiErrorMessage":true,"message":{"role":"assistant","model":"<synthetic>","content":[{"type":"text","text":"You'"'"'ve hit your weekly limit \u00b7 resets 4am (America/Chicago)"}]}}' \
    > "$1/-some-repo/$SID.jsonl"
}

@test "probe: a transcript in the FIRST of two config roots is FOUND (cross-root search)" {
  seed_limited_transcript "$ROOT_A"
  run bash "$HF" --probe-recycle-preconditions --source-pane "$PANE" --source-session "$SID"
  # The verdict may legitimately be a later refusal (there is no real pane here) — what this case
  # pins is that the search REACHED the transcript at all.
  [[ "$output" != *"NO TRANSCRIPT"* ]] || {
    echo "the probe did not look in the FIRST config root:"; echo "$output"
    echo "CC_PROJECTS_DIRS=$CC_PROJECTS_DIRS"; ls -la "$ROOT_A/-some-repo"; false; }
  [[ "$output" == *"limit: kind=limit"* ]] || { echo "$output"; false; }
}

@test "probe: a transcript in the LAST config root is FOUND (equivalence guard — green both arms)" {
  # DELIBERATELY green before and after the fix: the broken form searched exactly this root. It is
  # here so the fix cannot be "search only the first root", and it is NOT a red-proof.
  seed_limited_transcript "$ROOT_B"
  run bash "$HF" --probe-recycle-preconditions --source-pane "$PANE" --source-session "$SID"
  [[ "$output" != *"NO TRANSCRIPT"* ]] || { echo "$output"; false; }
  [[ "$output" == *"limit: kind=limit"* ]] || { echo "$output"; false; }
}

@test "probe: a session in NO root is REFUSED:no-transcript, not silently admitted (guard — green both arms)" {
  # The polarity that matters: absence must REFUSE. A search that reaches every root is only safe
  # if a genuine miss still fails closed.
  run bash "$HF" --probe-recycle-preconditions --source-pane "$PANE" --source-session "$SID"
  [[ "$output" == *"REFUSED:no-transcript"* ]] || { echo "$output"; false; }
  [ "$status" -eq 5 ] || { echo "status=$status"; echo "$output"; false; }
}

@test "probe: it writes NOTHING — the fixture tree is byte-identical after a run (guard — green both arms)" {
  seed_limited_transcript "$ROOT_A"
  # SCOPED to what the probe reads — the two project roots and the registry. Hashing all of
  # $BATS_TEST_TMPDIR instead swept $HOME, where an unrelated interpreter drops .pyc caches, and
  # the case then failed on the INSTRUMENT rather than on its subject.
  snap() { find "$ROOT_A" "$ROOT_B" "$CC_REGISTRY_DIR" -type f -exec shasum {} \; | sort; }
  before="$(snap)"
  run bash "$HF" --probe-recycle-preconditions --source-pane "$PANE" --source-session "$SID"
  after="$(snap)"
  [ "$before" = "$after" ] || {
    echo "the READ-ONLY probe changed something:"; diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true; false; }
}

@test "subagent_dir_for_sid: a subagents dir in the FIRST of two config roots is FOUND" {
  # The SAME broken idiom, at a PRE-EXISTING site (not W2's), and this one is a safety hold: the
  # recycle gate asks this function whether the dying session still has live subagents. Answering
  # "none" for every session outside the last config root would let a recycle proceed over
  # in-flight work. Extracted by name so a sibling definition cannot answer for it.
  eval "$(awk '/^subagent_dir_for_sid\(\) \{/{p=1} p{print} p&&/^\}$/{exit}' "$HF")"
  mkdir -p "$ROOT_A/-some-repo/$SID/subagents"
  run subagent_dir_for_sid "$SID"
  [ "$output" = "$ROOT_A/-some-repo/$SID" ] || {
    echo "expected the FIRST root's dir, got '<$output>'"; echo "CC_PROJECTS_DIRS=$CC_PROJECTS_DIRS"; false; }
}
