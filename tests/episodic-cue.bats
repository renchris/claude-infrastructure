#!/usr/bin/env bats
# episodic-cue.bats — hooks/lib/episodic_cue.sh (truememory §3.18, item #18): the narrow episodic cue
# fires on the 4 cited misses (gap-2.md:54-57), stays silent on ordinary prompts, skips non-typed
# prompts, writes exactly one `memory-nudge:episodic` IDL row per call, logs each fire to
# $HOME/.claude/state/episodic-cue.jsonl, honours CC_EPISODIC_CUE=off, and resolves idl-log.sh
# through a per-file symlink (X1). Hermetic: HOME, CC_IDL and CLAUDE_CONFIG_DIR live in the test tmpdir.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"
  unset CC_EPISODIC_CUE
  LIB="$REPO/hooks/lib/episodic_cue.sh"
}

# Run the lib in a fresh bash so each case sources it cleanly: $1 = lib path, $2 = prompt.
cue() {
  SID=sid-test CWD=/work/cwd bash -c '. "$1"; episodic_cue_line "$2"' _ "$1" "$2"
}

# The four target prompts (gap-2.md:54-57), verbatim from ~/.claude/history-union.jsonl `display`.
T78="I just sat down with 'Bennu Highland Guest' wifi with given code for '3 hours of access' 5276066077. Please do what we can do on our end to improve our internet speed/access/reliability to 100th percentile absolute perfection like we did before with our other wifi channels at our past visited cafes."
T88='Can you check our git history from a few months ago, I feel like we used it 2-3 times. And we particularly prompted it to be using a "diff" since last time we used it so it doesnt rescan the ENTIRE repository again.'
T106="$(cat <<'EOF'
I asked this before with a Dyanmic Workflow about a week ago that completed but got no actionable work/results back from you (I think it was engufled during self-recycles)

Can we retreive that research and work?

Pierre Jouet, from their pinterest, has a copious amount of professional photoshoot (thus would be 3000x4000 full frame camera resolution) in the hundreds in their account. However, the social media version is very pixelated for social media (ex. 300x400). Are we able to retreive this original source to work against for all of our Pierre Jouet source imaging photo generations?

Again, Pierre Jouet has a lot of bottles in our catalog.
EOF
)"
T110='ultracode  comprehensively and exhaustively investigate https://github.com/buildingjoshbetter/TrueMemory (we may have done this before) towards maximally extracting or applying to our current agent memory workflow'

@test "all 4 target prompts fire, one cue line naming claude-search" {
  local t out
  for t in "$T78" "$T88" "$T106" "$T110"; do
    out="$(cue "$LIB" "$t")"
    [ "$(printf '%s\n' "$out" | grep -c .)" -eq 1 ] || { echo "no single cue for: $t -> $out"; false; }
    [[ "$out" == "EPISODIC CUE: this prompt refers to earlier work."*"claude-search '"* ]] || false
  done
}

@test "the cue carries content words, identifier-like ones first, no filler or numbers" {
  run cue "$LIB" "$T78"
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-search 'bennu highland guest wifi code hours'"* ]] || false
  run cue "$LIB" "$T110"
  [[ "$output" == *"claude-search 'truememory github buildingjoshbetter "* ]] || false
  run cue "$LIB" "$T106"
  [[ "$output" == *"claude-search 'dyanmic workflow pierre jouet "* ]] || false
}

@test "the fire rows name the pattern each target was caught by" {
  local t
  for t in "$T78" "$T88" "$T106" "$T110"; do cue "$LIB" "$t" >/dev/null; done
  run jq -r '.reason' "$CC_IDL"
  [ "${lines[*]}" = "like-we-did used-it-times time-ago done-before" ]
}

@test "a recycle brief naming the previous session does not fire" {
  run cue "$LIB" 'Context: the previous session in this pane finished its work and landed it.'
  [ -z "$output" ]
  run cue "$LIB" 'in an earlier session we mapped the tenant schema'
  [[ "$output" == "EPISODIC CUE:"* ]] || false
}

@test "nouns are single-quote safe and capped at 6 words" {
  run cue "$LIB" "like we did with Bob's 'kitty' tabs, alpha beta gamma delta epsilon zeta eta"
  [ "$status" -eq 0 ]
  local q
  q="${output#*claude-search \'}"; q="${q%%\'*}"
  [ "$(printf '%s' "$q" | wc -w | tr -d ' ')" -le 6 ] || false
  [[ "$q" != *"'"* ]] || false
  [[ "$output" == *" (add --deep-search for chunk text; workflow results are indexed too)." ]] || false
}

@test "ordinary prompts do not fire and log abstained no-match" {
  local c
  for c in 'fix the failing test in hooks/foo.sh' 'run it again before you land' \
           'did the gate pass?' 'we did it, ship it' 'make the table narrower'; do
    run cue "$LIB" "$c"
    [ "$status" -eq 0 ]
    [ -z "$output" ] || { echo "fired on control: $c -> $output"; false; }
  done
  [ "$(jq -s '[.[] | select(.hook == "memory-nudge:episodic" and .disposition == "abstained" and .reason == "no-match")] | length' "$CC_IDL")" -eq 5 ]
}

@test "non-typed prompts are skipped as not-typed even when they match" {
  local big
  big="$(printf 'like we did before %.0s' $(seq 1 250))"
  for p in "<task-notification>like we did before</task-notification>" \
           "   <teammate-message>a week ago</teammate-message>" \
           "HANDOFF-ENGAGE like we did before" "HANDOFF-PING a week ago" "   " "$big"; do
    run cue "$LIB" "$p"
    [ -z "$output" ] || { echo "fired on non-typed prompt"; false; }
  done
  [ "$(jq -s '[.[] | select(.reason == "not-typed")] | length' "$CC_IDL")" -eq 6 ]
}

@test "every call writes exactly one IDL row under memory-nudge:episodic with the session id" {
  cue "$LIB" "$T78" >/dev/null
  cue "$LIB" 'nothing to see' >/dev/null
  [ "$(wc -l < "$CC_IDL" | tr -d ' ')" -eq 2 ]
  run jq -r '[.hook, .sid, .disposition, .reason] | join(" ")' "$CC_IDL"
  [ "${lines[0]}" = "memory-nudge:episodic sid-test fired like-we-did" ]
  [ "${lines[1]}" = "memory-nudge:episodic sid-test abstained no-match" ]
}

@test "a fire appends one episodic-cue.jsonl row with every field; an abstain appends none" {
  local log="$HOME/.claude/state/episodic-cue.jsonl" sha
  cue "$LIB" "$T110" >/dev/null
  cue "$LIB" 'nothing to see' >/dev/null
  [ "$(wc -l < "$log" | tr -d ' ')" -eq 1 ]
  sha="$(printf '%s' "$T110" | shasum -a 1 | cut -d' ' -f1)"
  run jq -r --arg sha "$sha" --argjson len "${#T110}" '
    [(.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")), .sid == "sid-test", .cwd == "/work/cwd",
     .pattern == "done-before", (.nouns | length > 0), .prompt_len == $len, .prompt_sha1 == $sha]
    | all' "$log"
  [ "$output" = true ]
}

@test "CC_EPISODIC_CUE=off prints nothing, logs kill-switch, writes no fire row" {
  CC_EPISODIC_CUE=off run cue "$LIB" "$T78"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(jq -r '.reason' "$CC_IDL")" = kill-switch ]
  [ ! -e "$HOME/.claude/state/episodic-cue.jsonl" ]
}

@test "X1: a lib reached through a lone per-file symlink still resolves idl-log.sh" {
  mkdir -p "$BATS_TEST_TMPDIR/live/lib"
  ln -s "$LIB" "$BATS_TEST_TMPDIR/live/lib/episodic_cue.sh"
  [ ! -e "$BATS_TEST_TMPDIR/live/lib/idl-log.sh" ]
  run cue "$BATS_TEST_TMPDIR/live/lib/episodic_cue.sh" "$T88"
  [[ "$output" == "EPISODIC CUE:"* ]] || false
  [ "$(jq -r '.hook + " " + .reason' "$CC_IDL")" = "memory-nudge:episodic used-it-times" ]
}

@test "an unwritable state dir and IDL never break the caller or leak to stdout" {
  export CC_IDL="/nonexistent-dir-$$/x/idl.jsonl"
  printf 'x' > "$BATS_TEST_TMPDIR/blocker"
  export HOME="$BATS_TEST_TMPDIR/blocker"
  run cue "$LIB" "$T78"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == "EPISODIC CUE:"* ]] || false
}
