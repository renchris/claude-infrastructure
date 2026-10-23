#!/usr/bin/env bats
# hooks/lib/origin-identity.sh — the sourceable origin/fired-peer oracle (CLOSE_INTEGRITY W1).
#
# WHAT IS PINNED, and why each direction matters:
#   · fired_stamp_tenancy's FIVE states, incl. the new `spent` (closedAt set): before it existed a
#     reused kitty id in the same cwd read `valid` and handed a brand-new ORIGIN session a
#     self-retiring contract (report-seams §1b). spent-vs-valid is the load-bearing split.
#   · oi_origin_class's CONTRACT polarity: every state that does not POSITIVELY prove fired-peer
#     maps to `origin` — a false `origin` costs ≤cap latched blocks; a false `fired-peer` silently
#     exempts a real origin session from the close contract forever.
#   · The marker is the proof channel on BOTH spent and absent paths — cwd alone never authorises
#     (the operator-pane-in-the-peer's-worktree negative, same as adoption's).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO_ROOT/hooks/lib/origin-identity.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired"; mkdir -p "$CC_FIRED_DIR"
  # Pin the fire capacity gate: handoff-fire's capacity_gate() refuses a net-new fire above
  # 2.0/core and this box lives well above that, so an unpinned suite goes red-by-LOAD rather
  # than by its subject (test-hermeticity ratchet). Inert for the cases here — they exercise the
  # oracle, never a fire — which is exactly why it must be pinned rather than relied upon.
  export CC_FIRE_CAPACITY_GATE=off
  WT="$BATS_TEST_TMPDIR/wt"; mkdir -p "$WT"
  OTHER="$BATS_TEST_TMPDIR/other"; mkdir -p "$OTHER"
  TP="$BATS_TEST_TMPDIR/transcript.jsonl"
  # The control that the file under test is the real one (control-must-replay-the-real-artifact).
  grep -q '^oi_origin_class() {' "$LIB"
}

# stamp <pane> <cwd> <closedAt-json> [marker] — a v2-shaped record, minimal fields.
stamp() {
  jq -n --arg p "$1" --arg c "$2" --argjson closed "$3" --arg m "${4:-}" \
    '{paneUUID:$p, cwd:$c, selfRetire:true, closedAt:$closed}
     + (if $m == "" then {} else {marker:$m} end)' > "$CC_FIRED_DIR/$1.json"
}
call() { bash -c ". '$LIB'; $1"; }

# ── fired_stamp_tenancy: five states ───────────────────────────────────────────────────────────

@test "tenancy: absent" {
  [ "$(call "fired_stamp_tenancy '$CC_FIRED_DIR/9.json' '$WT'")" = absent ]
}

@test "tenancy: valid — cwd matches, closedAt null" {
  stamp 9 "$WT" null
  [ "$(call "fired_stamp_tenancy '$CC_FIRED_DIR/9.json' '$WT'")" = valid ]
}

@test "tenancy: SPENT — cwd matches but closedAt is set (the reused-id hole this state closes)" {
  stamp 9 "$WT" '"2026-08-10T00:00:00Z"'
  [ "$(call "fired_stamp_tenancy '$CC_FIRED_DIR/9.json' '$WT'")" = spent ]
}

@test "tenancy: stale — a stamp for a DIFFERENT cwd, even when spent there" {
  # cwd mismatch outranks closedAt: the stamp is someone else's either way.
  stamp 9 "$OTHER" '"2026-08-10T00:00:00Z"'
  [ "$(call "fired_stamp_tenancy '$CC_FIRED_DIR/9.json' '$WT'")" = stale ]
}

@test "tenancy: unknown — kill-switch CC_SELFCLOSE_TENANCY=0 covers spent too (R8 restores pre-tenancy behavior)" {
  stamp 9 "$WT" '"2026-08-10T00:00:00Z"'
  run bash -c ". '$LIB'; CC_SELFCLOSE_TENANCY=0 fired_stamp_tenancy '$CC_FIRED_DIR/9.json' '$WT'"
  [ "$output" = unknown ]
}

@test "tenancy: unknown — stamp with no cwd field" {
  printf '{"paneUUID":"9","selfRetire":true}\n' > "$CC_FIRED_DIR/9.json"
  [ "$(call "fired_stamp_tenancy '$CC_FIRED_DIR/9.json' '$WT'")" = unknown ]
}

# ── oi_origin_class: the contract-polarity mapping ─────────────────────────────────────────────

@test "class: valid stamp ⇒ fired-peer" {
  stamp 9 "$WT" null
  [ "$(call "oi_origin_class 9 '$WT'")" = fired-peer ]
}

@test "class: spent + marker in MY transcript ⇒ fired-peer (same peer lingering after close)" {
  stamp 9 "$WT" '"2026-08-10T00:00:00Z"' HANDOFF-ENGAGE-1-2-3
  printf '{"type":"user","message":{"content":"brief HANDOFF-ENGAGE-1-2-3 end"}}\n' > "$TP"
  [ "$(call "oi_origin_class 9 '$WT' '$TP'")" = fired-peer ]
}

@test "class: spent + marker NOT in my transcript ⇒ origin (new tenant of a reused id)" {
  stamp 9 "$WT" '"2026-08-10T00:00:00Z"' HANDOFF-ENGAGE-1-2-3
  printf '{"type":"user","message":{"content":"an ordinary operator prompt"}}\n' > "$TP"
  [ "$(call "oi_origin_class 9 '$WT' '$TP'")" = origin ]
}

@test "class: spent + NO transcript given ⇒ origin (proof channel closed ⇒ not proven)" {
  stamp 9 "$WT" '"2026-08-10T00:00:00Z"' HANDOFF-ENGAGE-1-2-3
  [ "$(call "oi_origin_class 9 '$WT'")" = origin ]
}

@test "class: stale stamp ⇒ origin" {
  stamp 9 "$OTHER" null
  [ "$(call "oi_origin_class 9 '$WT'")" = origin ]
}

@test "class: absent + open by-cwd record whose marker is in MY transcript ⇒ fired-peer (id changed under a live peer)" {
  stamp 351 "$WT" null HANDOFF-ENGAGE-9-9-9
  call "write_fired_cwd_index '$CC_FIRED_DIR' 351 '$WT'"
  printf '{"type":"user","message":{"content":"x HANDOFF-ENGAGE-9-9-9 y"}}\n' > "$TP"
  [ "$(call "oi_origin_class 353 '$WT' '$TP'")" = fired-peer ]
}

@test "class: absent + open by-cwd record but marker NOT in my transcript ⇒ origin (cwd alone never authorises)" {
  stamp 351 "$WT" null HANDOFF-ENGAGE-9-9-9
  call "write_fired_cwd_index '$CC_FIRED_DIR' 351 '$WT'"
  printf '{"type":"user","message":{"content":"operator pane in the same worktree"}}\n' > "$TP"
  [ "$(call "oi_origin_class 353 '$WT' '$TP'")" = origin ]
}

@test "class: absent + by-cwd record already CLOSED ⇒ origin (a spent record proves nothing here either)" {
  stamp 351 "$WT" '"2026-08-10T00:00:00Z"' HANDOFF-ENGAGE-9-9-9
  call "write_fired_cwd_index '$CC_FIRED_DIR' 351 '$WT'"
  printf '{"type":"user","message":{"content":"x HANDOFF-ENGAGE-9-9-9 y"}}\n' > "$TP"
  [ "$(call "oi_origin_class 353 '$WT' '$TP'")" = origin ]
}

@test "class: plain absent, no index ⇒ origin — the operator-launched default" {
  [ "$(call "oi_origin_class 353 '$WT' ")" = origin ]
}

@test "class: no pane AND no cwd ⇒ unknown (nothing was asked; the consumer abstains)" {
  [ "$(call "oi_origin_class '' ''")" = unknown ]
}

# ── mutation control: the spent split is load-bearing, not decorative ──────────────────────────

@test "CONTROL: flipping closedAt null↔set flips the class verdict (valid path vs spent path)" {
  stamp 9 "$WT" null
  v1="$(call "oi_origin_class 9 '$WT'")"
  stamp 9 "$WT" '"2026-08-10T00:00:00Z"'
  v2="$(call "oi_origin_class 9 '$WT'")"
  [ "$v1" = fired-peer ]
  [ "$v2" = origin ]
}

# ── oi_marker_inbound: the marker must have ARRIVED, not merely been TYPED (item fd5196ac31ef) ──
#
# THE DEFECT. Both marker proofs were a bare `grep -qF marker transcript` — a PRESENCE test where
# the question is DIRECTION. A session that fires a peer WITHOUT --worktree fires into its own cwd,
# via a Bash TOOL CALL, so the composed prompt lands in the FIRING session's transcript as tool_use
# input and again as the tool_result coming back. The by-cwd index then finds the peer's open stamp
# on that shared cwd, the grep matches, and the ORIGIN session is classed `fired-peer` — exempting
# it from completion-assert D6's origin close contract for as long as the stamp stays open.
#
# EVERY CASE BELOW USES ONE MARKER AND ONE VERDICT-CHANGING VARIABLE: the RECORD SHAPE the marker
# sits in. The four outbound shapes were all `fired-peer` before this fix and are `origin` after;
# the two inbound shapes are `fired-peer` in BOTH worlds and are therefore preservation controls —
# they prove the fix narrowed the oracle to direction and did not simply break the proof channel.
#
# ONE MUTANT PER SITE (MEMORY per-site-mutation-attributes-coverage): the record-level
# `toolUseResult` skip and the block-level tool_result/tool_use drop are separate exclusions, so
# each gets a case that isolates it — a green suite must credit both, not one covering for the other.

# outbound_toolresult_block <file> — a user record carrying the marker ONLY inside a tool_result
# block, with NO toolUseResult sibling: isolates the BLOCK-level filter.
outbound_toolresult_block() {
  cat > "$1" <<'JSON'
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"fired ok HANDOFF-ENGAGE-9-9-9 pane 481"}]}}
JSON
}

@test "inbound: absent + by-cwd peer, marker ONLY in a tool_result BLOCK ⇒ origin (the fd5196ac31ef defect)" {
  stamp 351 "$WT" null HANDOFF-ENGAGE-9-9-9
  call "write_fired_cwd_index '$CC_FIRED_DIR' 351 '$WT'"
  outbound_toolresult_block "$TP"
  [ "$(call "oi_origin_class 353 '$WT' '$TP'")" = origin ]
}

@test "inbound: absent + by-cwd peer, marker in a user record carrying toolUseResult ⇒ origin (record-level skip)" {
  stamp 351 "$WT" null HANDOFF-ENGAGE-9-9-9
  call "write_fired_cwd_index '$CC_FIRED_DIR' 351 '$WT'"
  cat > "$TP" <<'JSON'
{"type":"user","toolUseResult":{"stdout":"HANDOFF-ENGAGE-9-9-9 armed"},"message":{"role":"user","content":"HANDOFF-ENGAGE-9-9-9"}}
JSON
  [ "$(call "oi_origin_class 353 '$WT' '$TP'")" = origin ]
}

@test "inbound: absent + by-cwd peer, marker ONLY in an assistant tool_use input ⇒ origin (the fire the originator RAN)" {
  stamp 351 "$WT" null HANDOFF-ENGAGE-9-9-9
  call "write_fired_cwd_index '$CC_FIRED_DIR' 351 '$WT'"
  cat > "$TP" <<'JSON'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"handoff-fire.sh --marker HANDOFF-ENGAGE-9-9-9"}}]}}
JSON
  [ "$(call "oi_origin_class 353 '$WT' '$TP'")" = origin ]
}

@test "inbound: SPENT stamp + marker only outbound ⇒ origin (the same defect on the spent arm)" {
  stamp 9 "$WT" '"2026-08-10T00:00:00Z"' HANDOFF-ENGAGE-1-2-3
  cat > "$TP" <<'JSON'
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"HANDOFF-ENGAGE-1-2-3 done"}]}}
JSON
  [ "$(call "oi_origin_class 9 '$WT' '$TP'")" = origin ]
}

@test "PRESERVATION: absent + by-cwd peer, marker inbound as a plain-string prompt ⇒ fired-peer (both worlds)" {
  # The shape measured on the real peer's transcript 2026-08-20: type=user, content a bare string.
  stamp 351 "$WT" null HANDOFF-ENGAGE-9-9-9
  call "write_fired_cwd_index '$CC_FIRED_DIR' 351 '$WT'"
  cat > "$TP" <<'JSON'
{"type":"user","message":{"role":"user","content":"You are wave W-MEASURE ... HANDOFF-ENGAGE-9-9-9 (ignore)"}}
JSON
  [ "$(call "oi_origin_class 353 '$WT' '$TP'")" = fired-peer ]
}

@test "PRESERVATION: marker inbound as a TEXT BLOCK in an array prompt ⇒ fired-peer (both worlds)" {
  stamp 351 "$WT" null HANDOFF-ENGAGE-9-9-9
  call "write_fired_cwd_index '$CC_FIRED_DIR' 351 '$WT'"
  cat > "$TP" <<'JSON'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"brief HANDOFF-ENGAGE-9-9-9 end"}]}}
JSON
  [ "$(call "oi_origin_class 353 '$WT' '$TP'")" = fired-peer ]
}

@test "CONTROL: one marker, one transcript, ONLY the record shape differs ⇒ the verdict flips" {
  # The whole fix in one assertion: presence is identical in both files, direction is not. Pre-fix
  # both read fired-peer, so this control CAN fail — it is not decorative.
  stamp 351 "$WT" null HANDOFF-ENGAGE-9-9-9
  call "write_fired_cwd_index '$CC_FIRED_DIR' 351 '$WT'"
  IN="$BATS_TEST_TMPDIR/in.jsonl"; OUT="$BATS_TEST_TMPDIR/out.jsonl"
  cat > "$IN"  <<'JSON'
{"type":"user","message":{"role":"user","content":"prompt HANDOFF-ENGAGE-9-9-9 tail"}}
JSON
  outbound_toolresult_block "$OUT"
  grep -qF HANDOFF-ENGAGE-9-9-9 "$IN"                       # both carry it — presence is a tie
  grep -qF HANDOFF-ENGAGE-9-9-9 "$OUT"
  [ "$(call "oi_origin_class 353 '$WT' '$IN'")"  = fired-peer ]
  [ "$(call "oi_origin_class 353 '$WT' '$OUT'")" = origin ]
}

@test "CONTROL: oi_marker_inbound answers NO on an unreadable/absent transcript (unresolvable ⇒ origin side)" {
  # Assert the function EXISTS first: without this the two rc checks below pass pre-fix for the
  # wrong reason — an undefined function exits 127, which is also "≠ 0" (MEMORY
  # red-proof-fixture-must-not-call-the-subject: a fixture that cannot fail credits nothing).
  call "declare -F oi_marker_inbound >/dev/null"
  run call "oi_marker_inbound HANDOFF-ENGAGE-9-9-9 '$BATS_TEST_TMPDIR/nope.jsonl'"
  [ "$status" -ne 0 ]
  run call "oi_marker_inbound '' '$TP'"
  [ "$status" -ne 0 ]
}

# ── KITTY GENERATION (pane-end-of-life 2026-10-22, A6) ─────────────────────────────────────────────
# kitty ids restart at 1 per process, so a stamp from an earlier kitty names a window a new pane may
# hold. The live kitty is OI_KITTY_PID = this bats process (alive), its start OI_KITTY_START_EPOCH.
# RED on origin/main: no generation check exists, so every `stale` below reads `valid` there.
gen_env() { unset KITTY_PID; export OI_KITTY_PID="$$" OI_KITTY_START_EPOCH=1792600000 OI_KITTY_COUNT=1; }
gstamp() { # <pane> <firedAt> [kittyPid] [closedAt-json]
  jq -n --arg p "$1" --arg c "$WT" --arg f "$2" --arg k "${3:-}" --argjson closed "${4:-null}" \
    '{paneUUID:$p, cwd:$c, selfRetire:true, firedAt:$f, closedAt:$closed}
     + (if $k == "" then {} else {kittyPid:($k|tonumber)} end)' > "$CC_FIRED_DIR/$1.json"
}

@test "A6 tenancy: a stamp whose kittyPid names a kitty that is gone is STALE, not valid" {
  gen_env; gstamp 16 2026-10-22T00:00:00Z 99999999
  [ "$(call "fired_stamp_tenancy '$CC_FIRED_DIR/16.json' '$WT'")" = stale ]
}

@test "A6 tenancy: a LEGACY numeric stamp fired before the live kitty started is STALE (16.json, fired 10-18)" {
  gen_env; gstamp 16 2026-10-18T12:00:00Z
  [ "$(call "fired_stamp_tenancy '$CC_FIRED_DIR/16.json' '$WT'")" = stale ]
}

@test "A6 CONTROL: this kitty's stamps stay valid — same kittyPid, or a legacy one fired after the start" {
  gen_env
  gstamp 16 2026-10-18T12:00:00Z "$$"
  [ "$(call "fired_stamp_tenancy '$CC_FIRED_DIR/16.json' '$WT'")" = valid ]
  gstamp 17 2026-10-22T23:00:00Z
  [ "$(call "fired_stamp_tenancy '$CC_FIRED_DIR/17.json' '$WT'")" = valid ]
}

@test "A6 ABSTAINS: no live kitty (iTerm2, launchd), or a non-numeric id, judges nothing by generation" {
  gen_env; gstamp 16 2026-10-18T12:00:00Z; gstamp AAAA-UUID 2026-10-18T12:00:00Z
  [ "$(call "fired_stamp_tenancy '$CC_FIRED_DIR/AAAA-UUID.json' '$WT'")" = valid ]
  unset OI_KITTY_PID
  [ "$(call "fired_stamp_tenancy '$CC_FIRED_DIR/16.json' '$WT'")" = valid ]
}

@test "A6 GC: closes open stamps of an older kitty once per generation, keeps this kitty's and the closed ones" {
  gen_env
  gstamp 16 2026-10-18T12:00:00Z                       # legacy, older  → closed
  gstamp 18 2026-10-21T00:00:00Z 99999999              # older kittyPid → closed
  gstamp 19 2026-10-22T23:00:00Z "$$"                  # this kitty     → untouched
  gstamp 20 2026-10-18T12:00:00Z "" '"2026-10-19T00:00:00Z"'   # already closed → untouched
  call "oi_gc_old_generation_stamps '$CC_FIRED_DIR'"
  [ "$(jq -r .closedReason "$CC_FIRED_DIR/16.json")" = kitty-restarted ]
  [ "$(jq -r .closedReason "$CC_FIRED_DIR/18.json")" = kitty-restarted ]
  [ "$(jq -r .closedAt "$CC_FIRED_DIR/19.json")" = null ]
  [ "$(jq -r .closedAt "$CC_FIRED_DIR/20.json")" = 2026-10-19T00:00:00Z ]
  [ "$(jq -r '.closedReason // "none"' "$CC_FIRED_DIR/20.json")" = none ]
  # once per generation: a second pass under the same kitty is a no-op
  gstamp 21 2026-10-18T12:00:00Z
  call "oi_gc_old_generation_stamps '$CC_FIRED_DIR'"
  [ "$(jq -r .closedAt "$CC_FIRED_DIR/21.json")" = null ]
}

@test "A6 GC: with two kitties running, a LEGACY stamp is left open (its id may be the other kitty's)" {
  gen_env; export OI_KITTY_COUNT=2
  gstamp 16 2026-10-18T12:00:00Z
  gstamp 18 2026-10-21T00:00:00Z 99999999
  call "oi_gc_old_generation_stamps '$CC_FIRED_DIR'"
  [ "$(jq -r .closedAt "$CC_FIRED_DIR/16.json")" = null ]
  [ "$(jq -r .closedReason "$CC_FIRED_DIR/18.json")" = kitty-restarted ]
}
