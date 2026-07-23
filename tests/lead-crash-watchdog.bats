#!/usr/bin/env bats
# lead-crash-watchdog.sh — death classification (classify_death via the --classify
# entrypoint). The watchdog fires whenever a lead pid dies while its pid-file survives,
# which conflates THREE things: a deliberate self-recycle (handoff-fire --recycle / self-
# close), a genuine crash (jetsam OOM / abort), and an operator ⌘W. classify_death
# separates the deliberate recycle from the rest and, on a real crash, attributes cause —
# jetsam-oom (a JetsamEvent within ~6 min, highest confidence) outranking everything.
#
# Coverage: recycle via disposition phrase · recycle via successor-brief text · abrupt
# crash · large-context OOM heuristic · jetsam-oom overrides recycle text · missing
# transcript degrades to CRASH (bias: unsure ⇒ CRASH).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/lead-crash-watchdog.sh"
  # sandbox account root + jetsam + teardown-marker + registry dirs — no live paths touched
  export CC_ACCOUNT_BASES="$BATS_TEST_TMPDIR/acct"
  export CC_JETSAM_DIRS="$BATS_TEST_TMPDIR/jetsam"
  export CC_TEARDOWN_DIR="$BATS_TEST_TMPDIR/teardown"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry"
  mkdir -p "$CC_ACCOUNT_BASES/projects/proj" "$CC_JETSAM_DIRS" "$CC_TEARDOWN_DIR" "$CC_REGISTRY_DIR"
}

# write a fixture transcript for <sid> whose tail contains <body-text>, padded to <kb> KB
mk_tx() { # $1=sid  $2=tail-text  $3=kb(optional, default 1)
  local p="$CC_ACCOUNT_BASES/projects/proj/$1.jsonl"
  local kb="${3:-1}"
  # pad with filler records so transcript_kb is realistic, then the meaningful tail last
  head -c $(( kb * 1024 )) /dev/zero | tr '\0' 'x' > "$p"
  printf '\n{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$2" >> "$p"
}

classify() { bash "$HOOK" --classify "$1"; }
cls() { classify "$1" | cut -f1; }        # CLASS field
cause() { classify "$1" | cut -f2; }      # CAUSE field

@test "deliberate recycle via DISPOSITION: CLOSE phrase → RECYCLE" {
  mk_tx s_disp "DISPOSITION: CLOSE — the recycle IS the continuation; firing now"
  run cls s_disp
  [ "$status" -eq 0 ]; [ "$output" = "RECYCLE" ]
}

@test "deliberate recycle via successor-brief text (recycled at N%) → RECYCLE" {
  mk_tx s_brief "Continue the session — recycled at 69% as the Context Stewardship free-win"
  [ "$(cls s_brief)" = "RECYCLE" ]
}

@test "abrupt death, small context, no markers → CRASH / abrupt-unknown" {
  mk_tx s_abrupt "Waiting on the full-suite gate and push now." 1
  [ "$(cls s_abrupt)" = "CRASH" ]
  [ "$(cause s_abrupt)" = "abrupt-unknown" ]
}

@test "large context (>4MB), no markers → CRASH / suspected-oom-large-context" {
  mk_tx s_big "mid-tool output, nothing conclusive here" 5000
  [ "$(cls s_big)" = "CRASH" ]
  [ "$(cause s_big)" = "suspected-oom-large-context" ]
}

@test "jetsam within 6 min OUTRANKS recycle text → CRASH / jetsam-oom" {
  mk_tx s_jetsam "DISPOSITION: CLOSE — this pane becomes the successor"
  : > "$CC_JETSAM_DIRS/JetsamEvent-2099-01-01-000000.ips"   # fresh mtime = within 6 min
  [ "$(cls s_jetsam)" = "CRASH" ]
  [ "$(cause s_jetsam)" = "jetsam-oom" ]
}

@test "missing transcript degrades to CRASH / no-transcript (bias: unsure ⇒ CRASH)" {
  [ "$(cls s_absent_xyz)" = "CRASH" ]
  [ "$(cause s_absent_xyz)" = "no-transcript" ]
}

# ── teardown-marker classification (the durable signal handoff-fire.sh writes on a chosen
#    recycle/self-close, superseding the brittle prose-grep). Sandboxed via CC_TEARDOWN_DIR +
#    CC_REGISTRY_DIR (setup). A marker is fresh iff its mtime is within 30 min.

@test "fresh sid-keyed teardown marker → RECYCLE / deliberate-teardown" {
  mk_tx s_td_sid "mid-tool output, nothing conclusive here"
  : > "$CC_TEARDOWN_DIR/s_td_sid.json"                        # fresh marker keyed by session id
  [ "$(cls s_td_sid)" = "RECYCLE" ]
  [ "$(cause s_td_sid)" = "deliberate-teardown" ]
}

@test "pane-keyed teardown marker resolved via registry → RECYCLE / deliberate-teardown" {
  mk_tx s_td_pane "mid-tool output, nothing conclusive here"
  # no sid-keyed marker; a registry row maps sid → pane uuid, and the marker is keyed by pane
  printf '{"paneUUID":"PANE-AAA","session_id":"s_td_pane"}\n' > "$CC_REGISTRY_DIR/PANE-AAA.json"
  : > "$CC_TEARDOWN_DIR/PANE-AAA.json"                        # fresh marker keyed by pane uuid
  [ "$(cls s_td_pane)" = "RECYCLE" ]
  [ "$(cause s_td_pane)" = "deliberate-teardown" ]
}

@test "teardown marker older than 30 min is ignored → CRASH" {
  mk_tx s_td_stale "mid-tool output, nothing conclusive here"
  : > "$CC_TEARDOWN_DIR/s_td_stale.json"
  touch -mt "$(date -v-40M +%Y%m%d%H%M)" "$CC_TEARDOWN_DIR/s_td_stale.json"   # backdate 40 min
  [ "$(cls s_td_stale)" = "CRASH" ]
}

@test "no teardown marker (empty dirs) → CRASH, marker path does not false-positive" {
  mk_tx s_td_none "mid-tool output, nothing conclusive here"
  [ "$(cls s_td_none)" = "CRASH" ]
  [ "$(cause s_td_none)" = "abrupt-unknown" ]
}

@test "jetsam within 6 min OUTRANKS a fresh teardown marker → CRASH / jetsam-oom" {
  mk_tx s_td_jetsam "mid-tool output, nothing conclusive here"
  : > "$CC_TEARDOWN_DIR/s_td_jetsam.json"                     # fresh teardown marker...
  : > "$CC_JETSAM_DIRS/JetsamEvent-2099-01-01-000001.ips"     # ...but jetsam still outranks it
  [ "$(cls s_td_jetsam)" = "CRASH" ]
  [ "$(cause s_td_jetsam)" = "jetsam-oom" ]
}
