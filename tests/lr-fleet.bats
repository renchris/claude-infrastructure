#!/usr/bin/env bats
# scripts/limit-recover/lr-fleet.sh — the /limit-recover fleet front end (LIMIT_RECOVER_100P).
# Hermetic: four fixture stores under $HOME, a fixture registry, a recording lr-handoff stub, a
# claude-accounts stub, and the capacity gate pinned open. Nothing here types into a pane.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FLEET="$REPO/scripts/limit-recover/lr-fleet.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/bin"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"; mkdir -p "$LR_STATE_DIR/locks"
  export CC_ADMIT_GATE=off
  export CC_FIRE_CAPACITY_GATE=off      # hermeticity: --one fires through handoff-fire capacity_gate()
  export CC_ACCOUNT_MAP="$BATS_TEST_TMPDIR/absent-map"
  SEC="$HOME/.claude-secondary"; TER="$HOME/.claude-tertiary"
  SLUG="-Users-x-thing"; mkdir -p "$SEC/projects/$SLUG" "$TER/projects/$SLUG"
  export LR_CONFIG_DIRS="$SEC:$TER"
  CWD="$BATS_TEST_TMPDIR/wt"; mkdir -p "$CWD"
  # The incident sid, with a ZEROED tail. The full 2026-09-09 uuid is LIVE on this box (a tmux
# `claude --resume <that uuid>` has been running since 00:51Z), and both liveness censuses under
# test — lr-select's `pgrep -f "resume <sid>"` and lr-lib's `ps -axo command=` / `--resume <sid>`
# — read the REAL process table, so the fixture's own registry row stopped being the only voice:
# --locate said DUPLICATE where the case pins RECOVERABLE, and the poller retired the record before
# it could nudge. A fixture may never name an identifier that can exist outside it (memory:
# hermetic-in-stubs-not-in-interpreter). The `52e35019` prefix is kept — it is what the display
# assertions match on, and it is how this suite stays legible against the incident it was written from.
  SID="52e35019-17e8-40f6-a54f-000000000000"
  # lr-handoff stub: records argv, exits per LRH_RC, prints the announcements the fleet parses
  export LR_HANDOFF_BIN="$BATS_TEST_TMPDIR/lr-handoff"
  cat > "$LR_HANDOFF_BIN" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "${LRH_LOG:?}"
case "${LRH_MODE:-inplace}" in
  inplace) echo "lr-handoff: recycled IN PLACE — pane X continues session Y" >&2 ;;
  replace) echo "lr-handoff: REPLACED in place — successor pane 701 fired beside source pane 616 on 'next3'" >&2 ;;
esac
echo "/bundle/path"
exit "${LRH_RC:-0}"
SH
  chmod +x "$LR_HANDOFF_BIN"; export LRH_LOG="$BATS_TEST_TMPDIR/lrh.log"; : > "$LRH_LOG"
  export CC_ACCOUNTS_BIN="$HOME/bin/claude-accounts"
  cat > "$CC_ACCOUNTS_BIN" <<'SH'
#!/bin/bash
case "$*" in *--rank*) printf 'next2 0.9\nnext3 0.8\nnext4 0.5\n' ;; esac
SH
  chmod +x "$CC_ACCOUNTS_BIN"
  # ── the census's own seams (LIMIT_DETECT_100P W3) ───────────────────────────────────────────
  # THE SLOW SCAN STAYS THE DEFAULT IN THIS SUITE, deliberately. `lf_census` delegates to
  # bin/cc-limited, whose `--json` is a RICHER schema than the 11-field list these cases assert on
  # (`--locate --json` execs straight into it), so making the census the default here would be
  # testing a different surface in 30 cases that were written about this one. The census path is
  # entered explicitly, by `parity` and by the cases named for it.
  export LF_SLOW_SCAN=1
  export CC_LIMITED="$REPO/bin/cc-limited"
  export CC_LIMITED_MARKER_DIR="$BATS_TEST_TMPDIR/markers"; mkdir -p "$CC_LIMITED_MARKER_DIR"
  export CC_LIMITED_ROOTS="$SEC:$TER"
  export CC_LIMITED_ACCOUNTS="$BATS_TEST_TMPDIR/accounts.json"
  cat > "$CC_LIMITED_ACCOUNTS" <<JSON
{"accounts":[{"name":"next2","config_dir":"$SEC","aliases":["secondary"]},
             {"name":"next3","config_dir":"$TER","aliases":["tertiary"]}]}
JSON
}
# The stop-failure marker row the census enumerates, DERIVED FROM THE TRANSCRIPT rather than
# hand-written beside it. The two producers read different stores, so a fixture that states the
# death twice can hand them different facts, and the parity diff would then be measuring the
# fixture. Pane comes from the caller: it is the REGISTRY's fact, which the slow scan reads there
# and the census reads here.
mark() { # $1=store $2=sid [$3=pane]
  mkdir -p "$CC_LIMITED_MARKER_DIR"
  python3 "$REPO/tests/helpers/lr-mark.py" "$1/projects/$SLUG/$2.jsonl" "$2" "$1" "$CWD" "${3:-}" \
    >> "$CC_LIMITED_MARKER_DIR/rate_limit__fixture.jsonl"
}
# ── THE BOTH-PATHS DIFF — what EARNS the delegation (§ 11 #9) ─────────────────────────────────
# `lf_locate` is not retired; it stays permanently as `--slow-scan`, so the census is only allowed
# to stand in for it while the two describe the same fleet. This diffs the RENDERED census, which
# is lossless for every column (printf pads, it never truncates).
# ERR-AGE IS EXCLUDED, AND THAT IS NOT A LOOPHOLE: it is a clock read taken by two processes at
# two instants, so no implementation could make it byte-equal — and at display resolution the two
# runs straddle a minute boundary about once in sixty, which would be a flake rather than a
# finding. Every column that describes the SESSION — sid, account, pane, pid, tier, disposition,
# kind(s), cwd — is compared byte for byte.
parity() {
  local slow census
  slow="$(LF_SLOW_SCAN=1 bash "$FLEET" --locate 2>/dev/null | tr -s ' ' | awk '{ $8=""; print }')"
  census="$(LF_SLOW_SCAN=0 bash "$FLEET" --locate 2>/dev/null | tr -s ' ' | awk '{ $8=""; print }')"
  [ -n "$slow" ] || { echo "PARITY: the slow scan rendered nothing — the fixture never reached it"; return 1; }
  diff <(printf '%s\n' "$slow") <(printf '%s\n' "$census") \
    || { echo "PARITY BROKEN — slow scan (<) vs census (>)"; return 1; }
}
blocked_tx() { # $1=store $2=sid [$3=model $4=effort]
  local f="$1/projects/$SLUG/$2.jsonl"
  printf '{"type":"user","cwd":"%s","timestamp":"2026-09-08T22:00:00.000Z","message":{"role":"user","content":"go"}}\n' "$CWD" > "$f"
  printf '{"type":"assistant","timestamp":"2026-09-08T22:30:00.000Z","effort":"%s","message":{"role":"assistant","model":"%s","content":[{"type":"text","text":"work"}]}}\n' "${4:-xhigh}" "${3:-claude-fable-5-1}" >> "$f"
  printf '{"type":"assistant","timestamp":"2026-09-08T23:11:09.000Z","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 7:50pm"}]}}\n' >> "$f"
}
row() { printf '{"paneUUID":"%s","session_id":"%s","pid":%d,"account":"claude-secondary","cwd":"%s"}\n' "$1" "$2" "${3:-$$}" "$CWD" > "$CC_REGISTRY_DIR/$1.json"; }

@test "locate: a limit-blocked session with a live registry pane is RECOVERABLE, with its pane and transcript tier" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"; mark "$SEC" "$SID" 616
  run bash "$FLEET" --locate
  [ "$status" -eq 0 ]
  # ACCT is the account NAME, not the config-dir basename: lr-fleet resolves it through the repo's
  # own lib/account-map.generated.sh (CC_ACCOUNT_MAP is only the first candidate, and pinning it at
  # an absent path falls through to that in-repo map rather than to the basename).
  # The census is COLUMN-PADDED, so the row is matched on a whitespace-squeezed copy — pinning the
  # literal single-space spelling asserts the column widths, which is not what this case is about.
  [[ "$(printf '%s' "$output" | tr -s ' ')" == *"52e35019 next2 616"* ]] || { echo "$output"; false; }
  [[ "$output" == *"claude-fable-5-1/xhigh"* ]] || { echo "$output"; false; }
  [[ "$output" == *"RECOVERABLE"* ]] || { echo "$output"; false; }
  parity
}
@test "locate: a session that took a real turn since its limit error is NOT blocked (the tail rule)" {
  blocked_tx "$SEC" "$SID"
  printf '{"type":"assistant","timestamp":"2026-09-09T01:00:00.000Z","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"back"}]}}\n' >> "$SEC/projects/$SLUG/$SID.jsonl"
  run bash "$FLEET" --locate
  # the empty-census line was reworded when the census stopped being limit-only (2026-09-09):
  # it now covers caps AND network/stall deaths, so it can no longer say "limit-blocked".
  [[ "$output" == *"(no blocked session anywhere"* ]] || { echo "$output"; false; }
}
@test "locate: no live process holding it is NO-PANE; a teammate transcript is TEAMMATE" {
  blocked_tx "$SEC" "$SID"; mark "$SEC" "$SID"
  tm="9b9b9b9b-0000-4000-8000-000000000002"; blocked_tx "$SEC" "$tm"
  sed -i '' '1s/{"type":"user",/{"type":"user","agentName":"w1",/' "$SEC/projects/$SLUG/$tm.jsonl"
  mark "$SEC" "$tm"
  run bash "$FLEET" --locate
  [[ "$output" == *"52e35019"*"NO-PANE"* ]] || { echo "$output"; false; }
  [[ "$output" == *"9b9b9b9b"*"TEAMMATE"* ]] || { echo "$output"; false; }
  parity
}
# REPOINTED BY THE W9a/W10 MERGE (LIMIT_RECOVER_100P § 10 W10). This test pinned ONE disposition
# over a fixture that the HUSK state model splits in two, and the split is the whole point of W10:
# a transplant makes one session into two objects with OPPOSITE dispositions, and which one a row
# is depends on whether the SOURCE pane is still alive.
#   live source row  → HUSK          (something is still standing and needs retiring)
#   no source row    → TRANSPLANTED→ (the move is complete; nothing to act on)
# The original fixture carried `row 616 "$SID"`, i.e. a LIVE source row, so it was the HUSK case
# all along and the assertion became an inverted guard the moment the state existed. Both halves
# are kept as separate tests so neither disposition is left unpinned — an unpinned disposition can
# be deleted by a later change with every suite still green.
@test "locate: a transplanted session whose SOURCE pane is gone is TRANSPLANTED" {
  blocked_tx "$SEC" "$SID"
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SID" "$SEC" "$TER" > "$LR_STATE_DIR/locks/$SID.lock"
  : > "$TER/projects/$SLUG/$SID.jsonl"
  run bash "$FLEET" --locate
  [[ "$output" == *"TRANSPLANTED→"* ]] || { echo "$output"; false; }
  [[ "$output" != *"HUSK"* ]] || { echo "$output"; false; }
}

@test "locate: the SAME fixture with a live source row is HUSK, not TRANSPLANTED" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SID" "$SEC" "$TER" > "$LR_STATE_DIR/locks/$SID.lock"
  : > "$TER/projects/$SLUG/$SID.jsonl"
  run bash "$FLEET" --locate
  [[ "$output" == *"HUSK"* ]] || { echo "$output"; false; }
}
@test "locate: two live processes on one sid is DUPLICATE, never RECOVERABLE" {
  # TWO PROCESSES, not two rows over one process — the distinction the case name makes and the
  # fixture used to elide by letting both rows default to `$$`. One pid under two pane rows is the
  # pane-keyed-overwrite artifact (§ 11 #2): ONE holder, and the census says so. The parity diff
  # is what surfaced it, and `lr_holder_count` (lr-lib.sh:474) still counts ROWS there — reported.
  /bin/sh -c 'sleep 30; :' --holder-a & local h1=$!
  /bin/sh -c 'sleep 30; :' --holder-b & local h2=$!
  blocked_tx "$SEC" "$SID"; row 616 "$SID" "$h1"; row 647 "$SID" "$h2"
  mark "$SEC" "$SID" 616
  run bash "$FLEET" --locate
  [[ "$output" == *"DUPLICATE"* ]] || { echo "$output"; false; }
  parity
  kill "$h1" "$h2" 2>/dev/null || true
}
@test "locate: a resumed session's OWN pid is ONE holder — RECOVERABLE, never DUPLICATE" {
  # THE OVERLAP. A session resumed by the poller carries `--resume <sid>` in its own argv, so the
  # single process holding it appears in BOTH censuses — the registry row AND the argv sweep. The
  # un-deduped test (`[ $n -gt 1 ] || lr_resume_procs`) therefore called every singly-held resumed
  # session DUPLICATE, and `--recover` parked it behind a prescription (`--duplicates`) that
  # subtracts the overlap and so reported nothing to resolve. Measured 2026-09-19 on 09e64dcb:
  # one registry row (pane 111, pid 37018), one resume pid — 37018 — and the pane was unrecoverable.
  blocked_tx "$SEC" "$SID"
  mark "$SEC" "$SID" 616
  # A process whose ARGV carries the marker, standing in for the resumed session itself. `; :`
  # defeats the shell's last-command exec optimisation, which would replace this argv with sleep's.
  /bin/sh -c 'sleep 30; :' --resume "$SID" &
  local holder=$!
  row 616 "$SID" "$holder"
  run bash "$FLEET" --locate
  [[ "$output" != *"DUPLICATE"* ]] || { echo "$output"; false; }
  [[ "$output" == *"RECOVERABLE"* ]] || { echo "$output"; false; }
  parity                                  # BEFORE the kill: a dead holder is a different fixture
  kill "$holder" 2>/dev/null || true
}

@test "duplicates: the two censuses agree — a single holder is a duplicate to NEITHER" {
  # The CONTROL for the case above, and the divergence itself: --locate and --duplicates must
  # return the same verdict over one population. Before the shared predicate they did not.
  blocked_tx "$SEC" "$SID"
  /bin/sh -c 'sleep 30; :' --resume "$SID" &
  local holder=$!
  row 616 "$SID" "$holder"
  run bash "$FLEET" --duplicates
  kill "$holder" 2>/dev/null || true
  [[ "$output" == *"no session is held by more than one live process"* ]] || { echo "$output"; false; }
}

@test "locate --json emits one object per session with the same fields" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --locate --json
  echo "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[0]["pane"]=="616" and d[0]["disposition"]=="RECOVERABLE", d'
}

@test "recover: drives lr-handoff --in-place with the pane, the transcript tier and a target that is NOT the limited account" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --recover
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q -- "--sid $SID --config-dir $SEC --cwd $CWD --target next3 --launch --in-place --source-pane 616 --model claude-fable-5-1 --effort xhigh" "$LRH_LOG" || { cat "$LRH_LOG"; false; }
  [[ "$output" == *"RECOVERY COMPLETE — 1 in place (same pane id), 0 replaced"* ]] || { echo "$output"; false; }
}
@test "recover: the ranked winner is skipped when it IS the limited account (its 5h window just closed)" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  # .claude-secondary IS next2 in the repo's account map, which lr-fleet resolves even with
  # CC_ACCOUNT_MAP pinned at an absent path — so rank next2 first and it must be passed over.
  printf '#!/bin/bash\ncase "$*" in *--rank*) printf "next2 0.9\\nnext4 0.5\\n" ;; esac\n' > "$CC_ACCOUNTS_BIN"
  run bash "$FLEET" --recover
  grep -q -- "--target next4" "$LRH_LOG" || { cat "$LRH_LOG"; false; }
}
@test "recover --dry-run composes the same argv and touches nothing" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --recover --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would recover 52e35019: pane 616"*"--in-place --source-pane 616"* ]] || { echo "$output"; false; }
  [ ! -s "$LRH_LOG" ]
}
@test "recover: a REPLACE announcement is reported as replaced beside its source, with the new pane id" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  LRH_MODE=replace run bash "$FLEET" --recover
  [ "$status" -eq 0 ]
  [[ "$output" == *"52e35019  616      701"* ]] || { echo "$output"; false; }
  [[ "$output" == *"replace-in-place/RECOVERED"* ]] || { echo "$output"; false; }
  [[ "$output" == *"0 in place (same pane id), 1 replaced beside their source"* ]] || { echo "$output"; false; }
}
@test "recover: lr-handoff rc 4 (transplanted, relaunch unverified) is a NAMED gap — RECOVERY PARTIAL, exit 1" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  LRH_RC=4 run bash "$FLEET" --recover
  [ "$status" -eq 1 ]
  [[ "$output" == *"RECOVERY PARTIAL — 1 named gap"* ]] || { echo "$output"; false; }
  [[ "$output" == *"recycle-in-place/PARTIAL"*"transplanted but the relaunch did not verify"* ]] || { echo "$output"; false; }
}
@test "recover: a DUPLICATE is parked and named, never recovered over two live processes" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"; row 647 "$SID"
  run bash "$FLEET" --recover
  [ "$status" -eq 1 ]
  [ ! -s "$LRH_LOG" ]
  [[ "$output" == *"DUPLICATE — more than one live process"* ]] || { echo "$output"; false; }
}
@test "recover: sessions are sequenced one at a time and --max bounds a run" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  s2="66660000-0000-4000-8000-000000000003"; blocked_tx "$SEC" "$s2"; row 630 "$s2"
  run bash "$FLEET" --recover --max 1
  [ "$status" -eq 1 ]
  [ "$(grep -c -- '--in-place' "$LRH_LOG")" = 1 ]
  [[ "$output" == *"--max 1 reached"* ]] || { echo "$output"; false; }
}

@test "enqueue: a request per RECOVERABLE session lands in the poller's requests dir and names the kickstart" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --enqueue --target next4
  [ "$status" -eq 0 ]
  [ -f "$LR_STATE_DIR/requests/$SID.json" ]
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["source_pane"]=="616" and d["target"]=="next4", d' "$LR_STATE_DIR/requests/$SID.json"
  # NO `-k` (LIMIT_DETECT_100P W3). `kickstart -k` KILLS a running poller before restarting it,
  # and the tick a caller has just enqueued work for is exactly the one that may be mid-transplant.
  [[ "$output" == *"launchctl kickstart gui/"* ]] || { echo "$output"; false; }
  [[ "$output" != *"kickstart -k"* ]] || { echo "$output"; false; }
}

@test "duplicates: a sid held by two live registry panes is listed with both, and --mark writes the SUPERSEDED tombstone" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"; row 647 "$SID"
  run bash "$FLEET" --duplicates
  [[ "$output" == *"DUPLICATE 52e35019: 2 registry pane(s)"* ]] || { echo "$output"; false; }
  run bash "$FLEET" --duplicates --mark "$SID" --live "$$"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  tomb="$SEC/projects/$SLUG/$SID.HANDOFF.json"
  [ -f "$tomb" ]
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["superseded_by_pid"]==int(sys.argv[2]) and d["handed_off_to"].endswith(".claude-secondary"), d' "$tomb" "$$"
  run bash "$FLEET" --duplicates --mark "$SID" --live "$$"
  [ "$status" -eq 2 ]                                      # never overwrites a tombstone
}
@test "duplicates --mark refuses a dead --live pid: a SUPERSEDED tombstone must name a live successor" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --duplicates --mark "$SID" --live 4194103
  [ "$status" -eq 2 ]
}
@test "iron rule 7: the fleet driver never pushes, ships or deploys" {
  run grep -nE 'git push|/ship|ship-land|deploy-live' "$FLEET"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

# ══════════════════════════════════════════════════════════════════════════════
# D7 (docs/plans/NONLIMIT_RESUME_LADDER.md § W1.2) — the census that does not expire
# silently: KIND per UNIT, the error record's AGE, and the registry hole filled
# from the argv leaf.
# ══════════════════════════════════════════════════════════════════════════════

# A network death. Envelope copied from § Finding 2 — identical to a cap's, which is
# why only the TEXT ever separated them and the shape gate is what makes the widened
# read safe.
net_tx() { # $1=store $2=sid
  local f="$1/projects/$SLUG/$2.jsonl"
  printf '{"type":"user","cwd":"%s","timestamp":"2026-09-09T14:30:00.000Z","message":{"role":"user","content":"go"}}\n' "$CWD" > "$f"
  printf '{"type":"assistant","timestamp":"2026-09-09T14:35:00.000Z","effort":"high","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"work"}]}}\n' >> "$f"
  printf '{"type":"assistant","timestamp":"%s","error":"server_error","isApiErrorMessage":true,"message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"API Error: Can'"'"'t reach the API server — check your internet or DNS (ENOTFOUND)"}]}}\n' "$(date -u -d '20 minutes ago' +%FT%T.000Z 2>/dev/null || date -u -v-20M +%FT%T.000Z)" >> "$f"
}

# A cap FIRST, then a network death. Two classes in ONE session — the mixed case.
mixed_tx() { # $1=store $2=sid
  local f="$1/projects/$SLUG/$2.jsonl"
  {
    printf '{"type":"user","cwd":"%s","timestamp":"2026-09-09T13:00:00.000Z","message":{"role":"user","content":"go"}}\n' "$CWD"
    printf '{"type":"assistant","timestamp":"2026-09-09T13:10:00.000Z","effort":"high","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"work"}]}}\n'
    printf '{"type":"assistant","timestamp":"2026-09-09T13:20:00.000Z","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 7:50pm"}]}}\n'
    printf '{"type":"assistant","timestamp":"%s","error":"server_error","isApiErrorMessage":true,"message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"API Error: Can'"'"'t reach the API server — check your internet or DNS (ENOTFOUND)"}]}}\n' "$(date -u -d '10 minutes ago' +%FT%T.000Z 2>/dev/null || date -u -v-10M +%FT%T.000Z)"
  } > "$f"
}

@test "D7: a network-blocked session with a live pane is IDLE-AFTER-ERROR — the state, not an instruction to the operator" {
  net_tx "$SEC" "$SID"; row 616 "$SID"
  mark "$SEC" "$SID" 616
  run bash "$FLEET" --locate
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -q 'IDLE-AFTER-ERROR' || { echo "$output"; false; }
  # The old name was a to-do addressed to a human; it must be gone from the display.
  if echo "$output" | grep -q 'RESUME-IN-PLACE'; then echo "old disposition name still rendered"; false; fi
  parity
}

@test "D7: the census carries the ERROR RECORD's AGE, so a row cannot read as a standing to-do after the session re-engaged" {
  net_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --locate --json
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert len(d)==1, d
r=d[0]
assert r["disposition"]=="IDLE-AFTER-ERROR", r
age=int(r["err_age_s"])
# ~20 minutes by construction. Bounds, not equality: the fixture stamps a real clock.
assert 900 < age < 2400, age
'
  run bash "$FLEET" --locate
  echo "$output" | grep -qE 'ERR-AGE' || { echo "$output"; false; }
  echo "$output" | grep -qE '(19|20|21)m' || { echo "$output"; false; }
}

@test "D7: classes MIX in one session — kind is the LAST death, kinds reports both" {
  # The bug this fixes: the old predicate grepped the whole 20KB tail for the limit
  # text and answered `limit` if ANY line matched. Here the cap came first and the
  # network drop is the death the session is sitting on, so `limit` would send a
  # transplant to fix a problem that no longer exists.
  mixed_tx "$SEC" "$SID"; row 616 "$SID"
  mark "$SEC" "$SID" 616
  run bash "$FLEET" --locate --json
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
r=d[0]
assert r["kind"]=="network", r          # the LAST record decides
assert r["kinds"]=="limit+network", r   # and neither class is lost
assert r["disposition"]=="IDLE-AFTER-ERROR", r
'
  run bash "$FLEET" --locate
  echo "$output" | grep -q 'limit+network' || { echo "$output"; false; }
  parity
}

@test "D7 CONTROL: the reverse order — network first, cap LAST — is a real cap and stays RECOVERABLE" {
  # Same two records, order swapped, one variable. Without this arm the test above
  # passes under a predicate that simply always answers `network`.
  f="$SEC/projects/$SLUG/$SID.jsonl"
  {
    printf '{"type":"user","cwd":"%s","timestamp":"2026-09-09T13:00:00.000Z","message":{"role":"user","content":"go"}}\n' "$CWD"
    printf '{"type":"assistant","timestamp":"2026-09-09T13:10:00.000Z","effort":"high","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"work"}]}}\n'
    printf '{"type":"assistant","timestamp":"2026-09-09T13:20:00.000Z","error":"server_error","isApiErrorMessage":true,"message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"API Error: Can'"'"'t reach the API server (ENOTFOUND)"}]}}\n'
    printf '{"type":"assistant","timestamp":"2026-09-09T13:30:00.000Z","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 7:50pm"}]}}\n'
  } > "$f"
  row 616 "$SID"; mark "$SEC" "$SID" 616
  run bash "$FLEET" --locate --json
  echo "$output" | python3 -c '
import json,sys
r=json.load(sys.stdin)[0]
assert r["kind"]=="limit", r
assert r["kinds"]=="network+limit", r
assert r["disposition"]=="RECOVERABLE", r
'
  parity
}

@test "D7: enqueue refuses a MIXED row whose latest death is the network — an account move must not be spent on a cured problem" {
  mixed_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --enqueue --target next3
  # IDLE-AFTER-ERROR is not RECOVERABLE/NO-PANE, and `kind` is network: refused twice over.
  [ ! -f "$LR_STATE_DIR/requests/$SID.json" ] || { echo "a transplant was enqueued for a network death"; false; }
}

@test "D7 CONTROL: enqueue still accepts a genuine cap" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --enqueue --target next3
  [ -f "$LR_STATE_DIR/requests/$SID.json" ] || { echo "$output"; false; }
}

@test "D7: THE REGISTRY HOLE — a session held only by an argv leaf reports that pid, not '-'" {
  # Measured 2026-09-09: lr_registry_live_rows returned rc 1 for a session whose pid
  # was alive and holding `claude … --resume <sid>` since the previous evening. The
  # census asserted RESUMING with no pid at all, which is a live process reported as
  # an unlocatable one.
  net_tx "$SEC" "$SID"
  mark "$SEC" "$SID"
  # No registry row at all. A stub `ps` is the only honest way to put a --resume leaf
  # in the process table without launching a real claude.
  mkdir -p "$BATS_TEST_TMPDIR/psbin"
  cat > "$BATS_TEST_TMPDIR/psbin/ps" <<PS
#!/bin/bash
case "\$*" in
  *lstart*) exec /bin/ps "\$@" ;;
  *) printf '%s\n' " 77720     1 claude --permission-mode auto --resume $SID" ;;
esac
PS
  chmod +x "$BATS_TEST_TMPDIR/psbin/ps"
  PATH="$BATS_TEST_TMPDIR/psbin:$PATH" run bash "$FLEET" --locate --json
  echo "$output" | python3 -c '
import json,sys
r=json.load(sys.stdin)[0]
assert r["disposition"]=="RESUMING", r
assert r["pid"]=="77720", r
'
  # UNDER THE SAME STUB. Without the prefix this would compare the two paths over a world with no
  # resume leaf at all — a green diff about a fixture the case is not testing.
  PATH="$BATS_TEST_TMPDIR/psbin:$PATH" parity
}

@test "D7 CONTROL: with no registry row AND no argv leaf the row is NO-PANE and the pid stays '-'" {
  net_tx "$SEC" "$SID"
  mark "$SEC" "$SID"
  mkdir -p "$BATS_TEST_TMPDIR/psbin"
  cat > "$BATS_TEST_TMPDIR/psbin/ps" <<'PS'
#!/bin/bash
case "$*" in
  *lstart*) exec /bin/ps "$@" ;;
  *) printf '%s\n' " 12345     1 /bin/bash -c something-unrelated" ;;
esac
PS
  chmod +x "$BATS_TEST_TMPDIR/psbin/ps"
  PATH="$BATS_TEST_TMPDIR/psbin:$PATH" run bash "$FLEET" --locate --json
  echo "$output" | python3 -c '
import json,sys
r=json.load(sys.stdin)[0]
assert r["disposition"]=="NO-PANE", r
assert r["pid"]=="-", r
'
  PATH="$BATS_TEST_TMPDIR/psbin:$PATH" parity
}

# ─── 2026-09-12 · four defects measured during a live two-pane recovery ───────────────────────
# The census RENDERS ${sid:0:8} and --one/--mark REJECTED that exact string, so the operator had to
# round-trip through `--locate --json | jq` to recover a full uuid. An identifier a tool prints must
# be one it accepts. (Family: fixture-identifier-shape-collapses-two-spaces — two identifier spaces,
# one of them display-only.)
@test "D8: --one accepts the 8-char sid the census PRINTS, and says what it resolved to" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --one "${SID:0:8}" --target next3 --source-pane 616
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"resolves to $SID"* ]] || { echo "$output"; false; }
  grep -q -- "--sid $SID " "$LRH_LOG" || { cat "$LRH_LOG"; false; }
}

@test "D8: --one REFUSES an ambiguous prefix rather than picking one — a wrong recovery is unrecoverable" {
  a="abcd1234-0000-4000-8000-000000000001"; b="abcd1234-0000-4000-8000-000000000002"
  blocked_tx "$SEC" "$a"; blocked_tx "$SEC" "$b"
  run bash "$FLEET" --one abcd1234 --target next3
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *AMBIGUOUS* ]] || { echo "$output"; false; }
  [ ! -s "$LRH_LOG" ] || { cat "$LRH_LOG"; false; }
}

# A reaped worktree cannot host a resume. The pre-fix --recover offered these for recovery, and the
# spawn would have died in a missing directory.
@test "D8: a NO-PANE session whose cwd was reaped is CWD-GONE and is never handed to lr-handoff" {
  blocked_tx "$SEC" "$SID"
  gone="$BATS_TEST_TMPDIR/reaped-worktree"
  sed -i '' "s#\"cwd\":\"$CWD\"#\"cwd\":\"$gone\"#" "$SEC/projects/$SLUG/$SID.jsonl"
  CWD="$gone" mark "$SEC" "$SID"   # AFTER the reap: a marker naming the live cwd would be a
                                   # fixture disagreement, and the diff would measure that
  run bash "$FLEET" --locate
  [[ "$output" == *"52e35019"*"CWD-GONE"* ]] || { echo "$output"; false; }
  run bash "$FLEET" --recover
  [[ "$output" == *"CWD-GONE"* ]] || { echo "$output"; false; }
  [ ! -s "$LRH_LOG" ] || { cat "$LRH_LOG"; false; }
  parity
}

# 20 teammate rows made `--recover` report PARTIAL on every possible run: a verdict that cannot be
# COMPLETE carries no information (memory: alarm-polarity-and-attention-budget). A teammate is
# lead-owned BY DESIGN — nothing is owed by anyone.
@test "D8: skips that are owed NOTHING do not read as gaps — a teammate-only census is COMPLETE" {
  tm="9b9b9b9b-0000-4000-8000-000000000002"; blocked_tx "$SEC" "$tm"
  sed -i '' '1s/{"type":"user",/{"type":"user","agentName":"w1",/' "$SEC/projects/$SLUG/$tm.jsonl"
  run bash "$FLEET" --recover
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"RECOVERY COMPLETE"* ]] || { echo "$output"; false; }
  [[ "$output" == *"1 not owed"* ]] || { echo "$output"; false; }
}

# CONTROL for the case above — the fix must not turn every skip into a non-gap. A DUPLICATE is a
# REAL gap (two live writers) and must still force PARTIAL, sitting beside a by-design teammate.
@test "D8 CONTROL: a genuine gap still reports PARTIAL even when a by-design skip sits beside it" {
  tm="9b9b9b9b-0000-4000-8000-000000000002"; blocked_tx "$SEC" "$tm"
  sed -i '' '1s/{"type":"user",/{"type":"user","agentName":"w1",/' "$SEC/projects/$SLUG/$tm.jsonl"
  blocked_tx "$SEC" "$SID"; row 616 "$SID"; row 617 "$SID"
  run bash "$FLEET" --recover
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"RECOVERY PARTIAL — 1 named gap(s)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"1 not owed"* ]] || { echo "$output"; false; }
}

# ── THE PHANTOM-ACTIVE CORRECTION (2026-09-19) ───────────────────────────────────────────────────
# A usage-limit kill never runs the Stop hook, so the session's `kind:"prompt"` beat freezes while
# its pid stays alive — and cc_sp_active counts it mid-turn forever. Measured that day: 8 blocked
# panes inflated the census to 12 against a ceiling of 8, so the recovery of those very sessions was
# refused for its whole budget. These pin the correction AND its two directions.
_ph_setup() { # <kind: limit|network> <pid> → beat dir + transcript fixture; echoes the sid
  local ekind="$1" pid="$2" sid="aaaaaaaa-1111-2222-3333-000000000000"
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats-$ekind-$pid"; mkdir -p "$CC_BEAT_DIR"
  printf '{"sid":"%s","pane":"9","cwd":"/x","pid":%s,"lstart":"Sat 19 Sep 00:00:00 2026","t":1,"kind":"prompt","who":"auto","seq":2}\n' \
    "$sid" "$pid" > "$CC_BEAT_DIR/$sid.json"
  local f="$SEC/projects/$SLUG/$sid.jsonl"
  if [ "$ekind" = limit ]; then
    printf '{"type":"assistant","timestamp":"2026-09-19T20:00:00.000Z","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 4:30pm"}]}}\n' > "$f"
  else
    printf '{"type":"assistant","timestamp":"2026-09-19T20:00:00.000Z","error":"server_error","isApiErrorMessage":true,"message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"API Error: Can'"'"'t reach the API server — check your internet or DNS (ENOTFOUND)"}]}}\n' > "$f"
  fi
  printf '%s' "$sid"
}

_ph_count() { # → lf_phantom_actives, with only the function under test loaded
  sed -n '/^lf_phantom_actives() {/,/^}/p' "$FLEET" > "$BATS_TEST_TMPDIR/ph.sh"
  bash -c '. "$1" 2>/dev/null; . "$2"; lf_phantom_actives' _ \
    "$REPO/scripts/limit-recover/lr-lib.sh" "$BATS_TEST_TMPDIR/ph.sh"
}

@test "phantom: a LIVE pid whose frozen prompt beat ends in a usage-limit error is subtracted" {
  _ph_setup limit "$$" >/dev/null          # $$ is this bats process: really alive, really ours
  run _ph_count
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "phantom CONTROL: a NETWORK death is NOT subtracted — its retry ladder may still be running" {
  _ph_setup network "$$" >/dev/null
  run _ph_count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "phantom CONTROL: a DEAD pid is not subtracted — the census already discards it" {
  dead=$(bash -c 'echo $$')                # a pid that has certainly exited
  while kill -0 "$dead" 2>/dev/null; do dead=$((dead + 1)); done
  _ph_setup limit "$dead" >/dev/null
  run _ph_count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

# ── W1(a)/(c): NON-BLOCKING INVOCATION, AND A NOTE THAT NAMES THE CAUSE ───────────────────────────
#
# (c) The rc-4 note said "transplanted but the relaunch did not verify" and nothing else, so every
# PARTIAL read as an unexplained failure. The cause is on disk at the moment it happens — the
# launcher's own capacity refusal, `~/.claude/autonomy/idl.jsonl` caller `lr-fire-resume`, carrying
# `term=load|active|headroom|segments|reserve-active` (capacity-admit.sh:418). 10/10 refusals on the
# morning of 2026-09-19 were `term=load`, a term the gate's own comment documents as WRONG INPUT and
# which is OFF for every other caller. The note must carry it, or the operator re-derives it by hand.
#
# (a) `--one … --detach` returns to the caller in ≤3 s having spawned the driver under setsid. The
# 2026-09-19 lead spent 24.4 turn-minutes in foreground `until` polls over exactly this call
# (U11 §2). The stub below sleeps 10 s: a blocking invocation cannot pass.

@test "W1(c): a PARTIAL (rc 4) names the launcher's own refusal — term= joined from the IDL" {
  export CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  # The refusal is written DURING the attempt, by the launcher inside the pane — which is why the
  # join has a floor at the attempt's own start. A pre-seeded row would be indistinguishable from a
  # two-day-old refusal, and joining THAT is the defect (memory: work-item-next-step-inherits-its-
  # store's-half-life). So the stub writes it, exactly where lr-fire-resume does.
  cat > "$LR_HANDOFF_BIN" <<SH
#!/bin/bash
printf '%s\n' "\$*" >> "\${LRH_LOG:?}"
printf '{"ts":"%s","hook":"capacity-admit","sid":"?","disposition":"refused","reason":"capacity","gate":"capacity-admit","verdict":"refuse","basis":"measured","caller":"lr-fire-resume","what":"resume $SID on next3","detail":"load 2.57/core > 2.0 (refusal 2 of budget 3)","term":"load","terms":"load,headroom,segments,active"}\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$CC_ADMIT_IDL"
echo "lr-handoff: --in-place: the recycle did NOT verify (handoff-fire rc=1)" >&2
echo "/bundle/path"
exit 4
SH
  chmod +x "$LR_HANDOFF_BIN"
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --one "$SID" --target next3 --source-pane 616
  [ "$status" -eq 4 ] || { echo "$output"; false; }
  r="$(cat "$(cat "$LR_STATE_DIR/fleet/last")/results.tsv")"
  printf '%s' "$r" | grep -q 'term=load' || { echo "$r"; echo "$output"; false; }
  printf '%s' "$r" | grep -q 'PARTIAL' || { echo "$r"; false; }
}

@test "W1(a): --detach returns in ≤3s while the driver is still running, and prints its log path" {
  export CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_NOTIFY_BIN="$BATS_TEST_TMPDIR/cc-notify"
  cat > "$CC_NOTIFY_BIN" <<SH
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/notify.log"
SH
  chmod +x "$CC_NOTIFY_BIN"
  # a SLOW actuator: a blocking --one cannot return before this finishes
  cat > "$LR_HANDOFF_BIN" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "${LRH_LOG:?}"
sleep 10
echo "lr-handoff: recycled IN PLACE — pane X continues session Y" >&2
echo "/bundle/path"
exit 0
SH
  chmod +x "$LR_HANDOFF_BIN"
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  t0=$(date +%s)
  run bash "$FLEET" --one "$SID" --target next3 --source-pane 616 --detach
  t1=$(date +%s)
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ $((t1 - t0)) -le 3 ] || { echo "took $((t1 - t0))s — the caller was BLOCKED: $output"; false; }
  [[ "$output" == *"log="* ]] || { echo "no log path printed: $output"; false; }
  logp="$(printf '%s' "$output" | tr ' ' '\n' | sed -n 's/^log=//p' | tail -1)"
  [ -n "$logp" ] || { echo "$output"; false; }
  # the driver is DETACHED, not skipped: the actuator is reached after the caller is already back
  until [ -s "$LRH_LOG" ] || [ $(( $(date +%s) - t0 )) -gt 30 ]; do sleep 1; done
  grep -q -- '--in-place' "$LRH_LOG" || { echo "the detached driver never ran the actuator"; cat "$logp" 2>/dev/null; false; }
  # …and its verdict reaches the requester as mail carrying a verdict= token
  until [ -s "$BATS_TEST_TMPDIR/notify.log" ] || [ $(( $(date +%s) - t0 )) -gt 60 ]; do sleep 2; done
  grep -q 'verdict=' "$BATS_TEST_TMPDIR/notify.log" || { echo "no verdict mail:"; cat "$BATS_TEST_TMPDIR/notify.log" 2>/dev/null; cat "$logp" 2>/dev/null; false; }
}


# ═══ W4 — the resolver stops guessing, and the in-place claim becomes falsifiable ═══════════════

# ONE SESSION, TWO CENSUSES, COUNTED TWICE. lr_resume_procs already collapses the cc-close-attrib
# WRAPPER onto its claude child, but nothing collapsed the registry row onto the SAME pid the argv
# census reports — and after a recovery those are always the same process, because lr-handoff
# relaunches with `--resume <sid>` and the SessionStart hook writes the row for that pid. So every
# recovered session read DUPLICATE on the next census and was parked instead of recovered
# (measured 2026-09-19 on 28f07827 and cb227486). The `--duplicates` arm has subtracted registry
# pids from the resume set since it was written; lf_locate never did.
@test "W4: a registry pid that IS the --resume process is ONE writer, not two — RECOVERABLE" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"          # row() writes pid $$, which is alive
  mkdir -p "$BATS_TEST_TMPDIR/psbin"
  cat > "$BATS_TEST_TMPDIR/psbin/ps" <<PS
#!/bin/bash
case "\$*" in
  *lstart*) exec /bin/ps "\$@" ;;
  *) printf '%s\n' " $$     1 claude --permission-mode auto --resume $SID" ;;
esac
PS
  chmod +x "$BATS_TEST_TMPDIR/psbin/ps"
  PATH="$BATS_TEST_TMPDIR/psbin:$PATH" run bash "$FLEET" --locate
  [[ "$output" == *"RECOVERABLE"* ]] || { echo "$output"; false; }
  [[ "$output" != *"DUPLICATE"* ]] || { echo "$output"; false; }
}

# CONTROL for the case above — the subtraction must not disarm the real thing it guards. A resume
# process that is NOT any registry pid is a second writer and still forces DUPLICATE.
@test "W4 CONTROL: a --resume process that is NOT the registry pid is still a second writer" {
  # the stub pid is 424242, never 1: lr_resume_procs keeps only LEAVES, and a pid that is another
  # row's ppid is dropped as the cc-close-attrib wrapper — pid 1 is its own parent in a one-row
  # stub, so it filtered itself out and this control passed for the wrong reason on its first run.
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  mkdir -p "$BATS_TEST_TMPDIR/psbin"
  cat > "$BATS_TEST_TMPDIR/psbin/ps" <<PS
#!/bin/bash
case "\$*" in
  *lstart*) exec /bin/ps "\$@" ;;
  *) printf '%s\n' " 424242     1 claude --permission-mode auto --resume $SID" ;;
esac
PS
  chmod +x "$BATS_TEST_TMPDIR/psbin/ps"
  PATH="$BATS_TEST_TMPDIR/psbin:$PATH" run bash "$FLEET" --locate
  [[ "$output" == *"DUPLICATE"* ]] || { echo "$output"; false; }
}

# THE CENSUS IS 99.8% OF THE IDENTIFICATION COST AND --one ALREADY HOLDS THE SID. U14 §0 measured
# lf_locate at 40.3 / 64.5 / 86.1 s against a 0.007 s registry read, and the cheap resolver already
# sat a few lines BELOW the census call as its miss path. The order is inverted here. The mutant is
# the proof: an lf_locate that exits 99 the moment it is entered must never be reached.
@test "W4: --one resolves from the registry and the store — the census is never reached" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  mut="$BATS_TEST_TMPDIR/fleet-nocensus.sh"
  sed 's|^lf_locate() { # → TSV rows on stdout|lf_locate() { echo "CENSUS RAN" >\&2; exit 99|' "$FLEET" > "$mut"
  grep -q 'CENSUS RAN' "$mut" || { echo "the lf_locate anchor moved — re-pin this mutant"; false; }
  # THE MUTANT MUST RESOLVE THE REPO'S OWN lr-lib, NOT THE LIVE ONE (W2). lr-fleet.sh resolves its
  # library script-relative FIRST and then falls back to $CLAUDE_CONFIG_DIR / $HOME/.claude — and a
  # mutant in $BATS_TEST_TMPDIR misses the first entry, so it was silently loading the OPERATOR'S
  # LIVE lr-lib.sh (an ambient CLAUDE_CONFIG_DIR survives the fixtured $HOME). That is a
  # hermeticity leak this suite's header says it does not have, and it surfaced the moment the
  # subject grew a function the live copy did not carry yet: the case then failed on the deploy
  # lag rather than on its subject. Copying the sibling beside the mutant pins the FIRST entry.
  cp "$REPO/scripts/limit-recover/lr-lib.sh" "$BATS_TEST_TMPDIR/lr-lib.sh"
  # the mutant is LIVE: --locate still walks straight into it. Without this the case below passes
  # for a sed that matched nothing (memory: green-in-both-arms-is-an-equivalence-guard).
  # The marker, not the exit code, is the oracle: every caller reads lf_locate through a COMMAND
  # SUBSTITUTION, so `exit 99` ends the subshell and the parent carries on at rc 0. That is also
  # why the assertion below is the marker's ABSENCE rather than a status.
  run bash "$mut" --locate
  [[ "$output" == *"CENSUS RAN"* ]] || { echo "$output"; false; }
  run bash "$mut" --one "$SID" --target next3 --source-pane 616
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"CENSUS RAN"* ]] || { echo "$output"; false; }
  grep -q -- "--sid $SID --config-dir $SEC --cwd $CWD --target next3 --launch --in-place --source-pane 616" "$LRH_LOG" || { cat "$LRH_LOG"; false; }
}

# `pane_after` was initialised to `pane` and only ever moved when lr-handoff ANNOUNCED a new pane,
# so "recovered in the same pane id" was a claim the row could not fail: a relaunch that died
# between /exit and SessionStart rendered identically to one that came back. Read it from the
# registry AFTER the run instead — the row is rewritten on every SessionStart, so its absence is
# exactly the failure this column exists to name.
@test "W4: pane_after is read from the registry AFTER the run — an absent row is a NAMED gap" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  cat > "$LR_HANDOFF_BIN" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "${LRH_LOG:?}"
rm -f "${CC_REGISTRY_DIR:?}"/616.json       # the relaunch that never re-registered
echo "lr-handoff: recycled IN PLACE — pane X continues session Y" >&2
echo "/bundle/path"
SH
  chmod +x "$LR_HANDOFF_BIN"
  run bash "$FLEET" --recover
  [[ "$output" == *"52e35019  616      ?"* ]] || { echo "$output"; false; }
  [[ "$output" == *"UNPROVEN"* ]] || { echo "$output"; false; }
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

# ── W9a: --mark's tombstone check is over EVERY store, and --duplicates dedupes by sid ───────────
# A backgrounded holder is reaped here rather than inline: an assertion that fails leaves the
# inline `kill` unreached, and a stray `sleep` in the process table is exactly the kind of live
# identifier a later fixture can collide with.
teardown() {
  local p
  for p in ${W9A_REAP:-}; do kill "$p" 2>/dev/null || true; done
}

@test "W9a: --mark REFUSES a sid whose tombstone lives in ANOTHER store — a transplanted session is already disambiguated" {
  # THE DEFECT. The transcript search `break 2`s on the FIRST store holding <sid>.jsonl and the
  # existence check was keyed on that store alone, so a session transplanted to another account —
  # whose `handed_off_to` tombstone is in the TARGET root — got a SECOND tombstone. Downstream
  # hf_transplant_evidence refuses on finding two, so the stale pane becomes unretirable.
  blocked_tx "$SEC" "$SID"                                  # transcript (and so `$tomb`) in SEC
  other="$TER/projects/$SLUG/$SID.HANDOFF.json"             # the transplant's tombstone, elsewhere
  printf '{"handed_off_to":"%s","ts":"2026-09-19T00:00:00Z"}\n' "$TER" > "$other"
  before="$(find "$SEC/projects/$SLUG" -type f | wc -l | tr -d ' ')"
  run bash "$FLEET" --duplicates --mark "$SID" --live "$$"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"$other"* ]] || { echo "$output"; false; }            # it NAMES what it found
  [[ "$output" == *"already disambiguated"* ]] || { echo "$output"; false; }
  [ ! -f "$SEC/projects/$SLUG/$SID.HANDOFF.json" ] || { echo "second tombstone written"; false; }
  [ "$(find "$SEC/projects/$SLUG" -type f | wc -l | tr -d ' ')" -eq "$before" ]
}

@test "W9a CONTROL: with no tombstone in ANY store --mark still writes exactly one" {
  # The widening must not cost the happy path. Green in both arms by construction — this is an
  # equivalence guard against the over-broad fix, not a red-proof of the defect above.
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --duplicates --mark "$SID" --live "$$"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$SEC/projects/$SLUG/$SID.HANDOFF.json" ]
  [ "$(find "$SEC/projects/$SLUG" "$TER/projects/$SLUG" -name "$SID.HANDOFF.json" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "W9a: a MIRRORED store is ONE tombstone, not two — same-store stays the overwrite refusal, cross-store is named once" {
  # `~/.claude-next/projects` is a SYMLINK onto `~/.claude/projects`, so a widening that compared
  # PATHS would read one physical tombstone as two: same-store would mis-report as a transplant to
  # somewhere else, and a cross-store refusal would name the same file twice. Resolved-path dedupe
  # (the shape hf_transplant_evidence:2068-2078 already uses) is what keeps both honest.
  MIR="$HOME/.claude-next"; mkdir -p "$MIR"; ln -s "$SEC/projects" "$MIR/projects"

  # arm A — cross-store, seen through BOTH spellings: refused once, path printed once.
  blocked_tx "$TER" "$SID"                                  # `$tomb` would be in TER
  printf '{"handed_off_to":"%s"}\n' "$SEC" > "$SEC/projects/$SLUG/$SID.HANDOFF.json"
  LR_CONFIG_DIRS="$TER:$SEC:$MIR" run bash "$FLEET" --duplicates --mark "$SID" --live "$$"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c "$SID.HANDOFF.json$")" -eq 1 ] || { echo "$output"; false; }
  [ ! -f "$TER/projects/$SLUG/$SID.HANDOFF.json" ] || { echo "second tombstone written"; false; }

  # arm B — same store, reached through both spellings: the ORIGINAL overwrite refusal, never the
  # transplant one. One physical file in one store is not evidence of a move.
  blocked_tx "$SEC" "$SID"
  LR_CONFIG_DIRS="$SEC:$MIR" run bash "$FLEET" --duplicates --mark "$SID" --live "$$"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"refusing to overwrite a tombstone"* ]] || { echo "$output"; false; }
  [[ "$output" != *"already disambiguated"* ]] || { echo "$output"; false; }
}

@test "W9a: --duplicates prints a sid ONCE however many registry rows it has" {
  # The census iterates registry FILES, so the very population this mode exists to report — a sid
  # with two rows — was reached twice and printed its whole block twice (measured: 7f533f05).
  # Both pids are REAL: a hardcoded 'impossible' pid is a claim about a wrapping namespace that a
  # live process can answer (docs/lessons/a-fixture-s-pid-range-is-a-claim-about-a-shared-wrapping-namespa.md).
  blocked_tx "$SEC" "$SID"
  sleep 30 & holder=$!; W9A_REAP="$holder"
  row 616 "$SID" "$$"; row 647 "$SID" "$holder"
  run bash "$FLEET" --duplicates
  [ "$(printf '%s\n' "$output" | grep -c '^DUPLICATE 52e35019')" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"DUPLICATE 52e35019: 2 registry pane(s)"* ]] || { echo "$output"; false; }
  [[ "$output" != *"no session is held by more than one live process"* ]] || { echo "$output"; false; }
}

# ══ HUSK — a LIVE pane on a store whose session has already MOVED (W10, LIMIT_RECOVER_100P § 10) ══
# Measured 2026-09-19: panes 110 (pid 95369), 126 (48984) and 150 (17221) were all live, all still
# showing the afternoon's weekly-limit error with an empty composer, and `--locate` listed NONE of
# them while `--duplicates` found all three. TWO walls stood between that state and the census, and
# clearing either one alone would have landed an inert arm:
#   1. the GLOB. lr-transplant.sh:98 renames the source `<sid>.jsonl.handed-off`, and `*.jsonl`
#      does not match it — for all three sids the only `.jsonl` left anywhere was the successor's.
#   2. the LAST-ASSISTANT-WORD filter, which drops the row the moment the successor takes a turn.
# The pane id here is unforgeable from outside the fixture: leg (c1) of lr_husk_state reads the REAL
# process table, and a numeric pane could be named by an unrelated `__recycle` watcher on this box
# (memory: hermetic-in-stubs-not-in-interpreter).
husk_lock() { printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SID" "$SEC" "$TER" > "$LR_STATE_DIR/locks/$SID.lock"
              : > "$TER/projects/$SLUG/$SID.jsonl"; }
husk_successor_turn() { printf '{"type":"assistant","timestamp":"2026-09-09T00:52:00.000Z","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"the successor speaking"}]}}\n' >> "$SEC/projects/$SLUG/$SID.jsonl"; }

@test "locate: a live pane whose session has MOVED is HUSK — even after a real turn follows the limit" {
  blocked_tx "$SEC" "$SID"; husk_successor_turn; row HUSKP-9x7z "$SID"; husk_lock
  run bash "$FLEET" --locate
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"HUSK"* ]] || { echo "$output"; false; }
  [[ "$output" == *"52e35019"* ]] || { echo "$output"; false; }
}

# THE RED-PROOF for wall 2: the ONLY difference from the case above is the lock. Without it the row
# is dropped by the last-assistant-word filter and never reaches a disposition at all, so the case
# above passes because of the change and not because the fixture was visible anyway.
@test "locate CONTROL: the same fixture with NO transplant lock prints no row at all" {
  blocked_tx "$SEC" "$SID"; husk_successor_turn; row HUSKP-9x7z "$SID"
  run bash "$FLEET" --locate
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"52e35019"* ]] || { echo "$output"; false; }
}

@test "locate: a source copy renamed .jsonl.handed-off is enumerated when — and only when — it is a HUSK" {
  blocked_tx "$SEC" "$SID"
  mv "$SEC/projects/$SLUG/$SID.jsonl" "$SEC/projects/$SLUG/$SID.jsonl.handed-off"
  row HUSKP-9x7z "$SID"; husk_lock
  run bash "$FLEET" --locate
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"HUSK"* ]] || { echo "$output"; false; }
}

# THE RED-PROOF for wall 1, and the guard on its blast radius. 63 `.handed-off` copies sit on this
# box against 2,631 live transcripts; enumerating them would flood the census with settled history
# if any of them could reach a disposition. One is a husk or it is invisible — there is no third.
@test "locate CONTROL: a .handed-off copy with a live row but NO lock stays invisible" {
  blocked_tx "$SEC" "$SID"
  mv "$SEC/projects/$SLUG/$SID.jsonl" "$SEC/projects/$SLUG/$SID.jsonl.handed-off"
  row HUSKP-9x7z "$SID"
  run bash "$FLEET" --locate
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"52e35019"* ]] || { echo "$output"; false; }
}

@test "locate: LR_HUSK_RETIRE=off returns BOTH arms to the pre-W10 census, byte for byte" {
  blocked_tx "$SEC" "$SID"; husk_successor_turn; row HUSKP-9x7z "$SID"; husk_lock
  LR_HUSK_RETIRE=off run bash "$FLEET" --locate
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"HUSK"* ]] || { echo "$output"; false; }
  [[ "$output" != *"52e35019"* ]] || { echo "$output"; false; }
}

# ── THE ROUTER MUST NOT PICK A TARGET THAT ALREADY HOLDS THE SESSION (2026-09-20) ───────────────
# `07e30aeb` was transplanted next3 → next2; next3 kept a 5,339 B stub + a `.jsonl.handed-off`
# tombstone while next2 holds the 1.1 MB transcript. Every later retry routed next2 → next3 and died
# on `lr-transplant: REFUSED — … already exists` — three times, deterministically. That refusal is
# CORRECT (it stops a stub shadowing the real transcript); choosing that destination is the defect.
_pick() { # <source acct> <tier> <sid> → lf_pick_target's answer, with only what it needs loaded
  sed -n '/^lf_acct_of_cfg() {/,/^}/p;/^_lf_target_holds_sid() {/,/^}/p;/^lf_pick_target() {/,/^}/p' \
    "$FLEET" > "$BATS_TEST_TMPDIR/pick.sh"
  bash -c '
    . "$1" 2>/dev/null
    . "$2" 2>/dev/null || true
    . "$3"
    TARGET=auto; ACCOUNTS="$CC_ACCOUNTS_BIN"
    lf_pick_target "$4" "$5" "$6"; rc=$?
    printf "\nSKIPPED=%s\n" "${LF_PICK_SKIPPED_HOLDER:-}"
    exit $rc' _ \
    "$REPO/scripts/limit-recover/lr-lib.sh" "$REPO/lib/account-map.generated.sh" \
    "$BATS_TEST_TMPDIR/pick.sh" "$1" "$2" "$3"
}

@test "router: a candidate holding this sid's .handed-off tombstone is SKIPPED, not chosen" {
  mkdir -p "$TER/projects/$SLUG"
  : > "$TER/projects/$SLUG/$SID.jsonl.handed-off"      # next3 = this session's retired source
  run _pick next2 claude-opus-5 "$SID"
  [ "$status" -eq 0 ]
  [[ "$output" == next4* ]] || false                   # next3 skipped, next4 taken
  [[ "$output" == *"SKIPPED=next3"* ]]
}

@test "router CONTROL: with no holder, the first ranked account past the source is still chosen" {
  run _pick next2 claude-opus-5 "$SID"
  [ "$status" -eq 0 ]
  [[ "$output" == next3* ]]
}

@test "router CONTROL: every candidate holding the sid is rc 1 — park, never route into a refusal" {
  mkdir -p "$TER/projects/$SLUG" "$HOME/.claude-quaternary/projects/$SLUG"
  : > "$TER/projects/$SLUG/$SID.jsonl.handed-off"
  : > "$HOME/.claude-quaternary/projects/$SLUG/$SID.jsonl"
  LR_CONFIG_DIRS="$SEC:$TER:$HOME/.claude-quaternary" run _pick next2 claude-opus-5 "$SID"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SKIPPED=next3 next4"* ]]
}

# ══════════════════════════════════════════════════════════════════════════════
# W3 (docs/plans/LIMIT_DETECT_100P.md § 3) — THE CENSUS AS A CONSUMER SEES IT.
# `lf_census` delegates to bin/cc-limited and must honour its exit-code contract
# rather than its stdout: 0 rendered · 5 instrument unreadable (stdout EMPTY by
# contract) · 6 degraded (rows ARE printed). The failure these cases exist to
# prevent is the one the census itself was built against — an empty list at exit
# 0 is indistinguishable from a healthy fleet.
# ══════════════════════════════════════════════════════════════════════════════

@test "W3: rc 5 REFUSES the run and leaves census.tsv ABSENT — an empty file reads as a clean fleet" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  printf '#!/bin/sh\necho "cc-limited: instrument unreadable: accounts.json" >&2\nexit 5\n' \
    > "$BATS_TEST_TMPDIR/cc-limited-5"; chmod +x "$BATS_TEST_TMPDIR/cc-limited-5"
  CC_LIMITED="$BATS_TEST_TMPDIR/cc-limited-5" LF_SLOW_SCAN=0 run bash "$FLEET" --recover
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"INSTRUMENT UNREADABLE"* ]] || { echo "$output"; false; }
  [[ "$output" == *"left ABSENT rather than empty"* ]] || { echo "$output"; false; }
  # THE FILE ITSELF, not the message. A run dir carrying a 0-byte census.tsv is what every later
  # reader — this driver's own --report included — would read as "the fleet was clean".
  run bash -c 'ls "$LR_STATE_DIR"/fleet/*/census.tsv 2>/dev/null'
  [ -z "$output" ] || { echo "census.tsv exists: $output"; false; }
  # and the actuator was never reached
  [ ! -s "$LRH_LOG" ] || { cat "$LRH_LOG"; false; }
}

@test "W3 CONTROL: rc 6 is DEGRADED, not unreadable — the rows are delivered and the run proceeds" {
  # The contract's own words: rows ARE printed at 6. Treating 6 like 5 would discard a census that
  # is merely incomplete, which is the opposite error and just as silent.
  blocked_tx "$SEC" "$SID"
  cat > "$BATS_TEST_TMPDIR/cc-limited-6" <<SH
#!/bin/sh
echo "cc-limited: degraded: marker file capped" >&2
printf '$SID\t$SEC\tnext2\t-\t-\t$CWD\t-\tNO-PANE\tlimit\tlimit\t99\n'
exit 6
SH
  chmod +x "$BATS_TEST_TMPDIR/cc-limited-6"
  CC_LIMITED="$BATS_TEST_TMPDIR/cc-limited-6" LF_SLOW_SCAN=0 run bash "$FLEET" --locate
  [[ "$output" == *"census DEGRADED"* ]] || { echo "$output"; false; }
  [[ "$output" == *"52e35019"*"NO-PANE"* ]] || { echo "$output"; false; }
}

@test "W3: with no executable cc-limited the fallback is the slow scan, and it SAYS so" {
  # Silence here would make a permanently-degraded fleet look like a fast one.
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  CC_LIMITED="$BATS_TEST_TMPDIR/does-not-exist" LF_SLOW_SCAN=0 run bash "$FLEET" --locate
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"falling back to the slow scan"* ]] || { echo "$output"; false; }
  [[ "$output" == *"RECOVERABLE"* ]] || { echo "$output"; false; }
}

@test "W3: --one resolves from the store and NEVER invokes the census (the 40-86 s it used to cost)" {
  # W4 measured 40.3 / 64.5 / 86.1 s of census on a path that had already been handed the sid.
  # The store resolver still runs first; this pins that the delegation did not quietly re-add it.
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  cat > "$BATS_TEST_TMPDIR/cc-limited-spy" <<SH
#!/bin/sh
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/census-calls"
exit 4
SH
  chmod +x "$BATS_TEST_TMPDIR/cc-limited-spy"; : > "$BATS_TEST_TMPDIR/census-calls"
  CC_LIMITED="$BATS_TEST_TMPDIR/cc-limited-spy" LF_SLOW_SCAN=0 LRH_RC=0 \
    run bash "$FLEET" --one "${SID:0:8}" --target next3
  [ ! -s "$BATS_TEST_TMPDIR/census-calls" ] || { cat "$BATS_TEST_TMPDIR/census-calls"; false; }
  grep -q -- "--sid $SID" "$LRH_LOG" || grep -q -- "$SID" "$LRH_LOG" || { cat "$LRH_LOG"; false; }
}

@test "W3: --enqueue writes one request per RECOVERABLE row, through the census" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"; mark "$SEC" "$SID" 616
  LF_SLOW_SCAN=0 run bash "$FLEET" --enqueue --target next3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$LR_STATE_DIR/requests/$SID.json" ] || { echo "$output"; ls -R "$LR_STATE_DIR"; false; }
  run bash -c 'set -- "$1"/requests/*.json; echo $#' _ "$LR_STATE_DIR"
  [ "$output" = 1 ] || { echo "$output"; false; }
  [[ "$output" != *"kickstart -k"* ]] || { echo "$output"; false; }
}

# ══════════════════════════════════════════════════════════════════════════════
# RED-PROOF — W3 (LIMIT_DETECT_100P § 3), run 2026-09-20 against pristine 4ef1f2d66
# with ONLY the three source files reverted (tests and tests/helpers kept):
#
#   $ git checkout HEAD -- scripts/limit-recover/lr-fleet.sh \
#       scripts/limit-recover/lr-reset-poller.sh scripts/gen-account-map.sh
#   $ bats tests/lr-fleet.bats
#   1..59
#   not ok 17 enqueue: a request per RECOVERABLE session lands in the poller's requests dir and names the kickstart
#   not ok 55 W3: rc 5 REFUSES the run and leaves census.tsv ABSENT — an empty file reads as a clean fleet
#   not ok 56 W3 CONTROL: rc 6 is DEGRADED, not unreadable — the rows are delivered and the run proceeds
#   not ok 57 W3: with no executable cc-limited the fallback is the slow scan, and it SAYS so
#   not ok 59 W3: --enqueue writes one request per RECOVERABLE row, through the census
#
# ⚠️ THE `parity` ROWS ARE NOT IN THAT LIST, AND THAT IS HONEST RATHER THAN A GAP. Against
# pristine source `lf_census` does not exist and `LF_SLOW_SCAN` is read by nobody, so BOTH arms of
# every `parity` call resolve to `lf_locate` and the diff is empty by construction — green in both
# arms, which is an equivalence guard and never a red-proof. Their power was demonstrated by
# MUTATION instead, the only thing that can show it:
#
#   $ # delete the `kinds` backfill from lf_census_fill, keep everything else
#   $ bats tests/lr-fleet.bats -f "classes MIX|reverse order"
#   1..2
#   not ok 1 D7: classes MIX in one session — kind is the LAST death, kinds reports both
#   not ok 2 D7 CONTROL: the reverse order — network first, cap LAST — is a real cap and stays RECOVERABLE
#
# and by what they caught while this wave was being written — four divergences, each one a column
# the census got wrong and nothing else would have noticed: TIER (`-`, a missing model field),
# PID (carrying pane_now), KINDS (one class where the slow scan reports `limit+network`), and the
# empty-field column shift that `IFS=$'\t' read` produces on a row with no pane and no pid.

# ══ --retire-husks — POSITIVE PROOF, never absence of evidence (W10, LIMIT_RECOVER_100P § 10) ════
# A husk looks exactly like live work in the operator's window, so the dangerous failure is not
# "failed to close one" — it is "closed one that was still being used". Every gate below is a READ,
# and the cases that matter are the REFUSALS.
@test "retire-husks: with no HUSK anywhere it closes nothing and says so" {
  run bash "$FLEET" --retire-husks
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"no HUSK"* ]] || { echo "$output"; false; }
}

@test "retire-husks: LR_HUSK_RETIRE=off is census-only — it must never close" {
  blocked_tx "$SEC" "$SID"; husk_successor_turn; row HUSKP-9x7z "$SID"; husk_lock
  LR_HUSK_RETIRE=off run bash "$FLEET" --retire-husks
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"census only"* || "$output" == *"no HUSK"* ]] || { echo "$output"; false; }
}

@test "retire-husks: without --yes it never closes, however complete the proof" {
  # The confirmation gate. Everything else can be satisfied and the default is still to print, not
  # to act — an actuator aimed at the operator's own visible windows does not get to be implicit.
  blocked_tx "$SEC" "$SID"; husk_successor_turn; row HUSKP-9x7z "$SID"; husk_lock
  run bash "$FLEET" --retire-husks
  [[ "$output" != *"RETIRED"* ]] || { echo "it closed without --yes: $output"; false; }
}

@test "retire-husks: --pane narrows to one husk and ignores the others" {
  blocked_tx "$SEC" "$SID"; husk_successor_turn; row HUSKP-9x7z "$SID"; husk_lock
  run bash "$FLEET" --retire-husks --pane NOT-THIS-PANE
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"HUSKP-9x7z"* ]] || { echo "--pane did not narrow: $output"; false; }
}
