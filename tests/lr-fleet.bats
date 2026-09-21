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
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.stamp"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock"
  unset CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE CC_PANE_CMD
  # W6b MADE `--recover` A POOL, and the default is 2. Every case written before this wave was
  # written against a driver that ran ONE lf_one at a time, so the suite's default is pinned to the
  # serial shape and the pool cases name the axis they exercise. A default that silently changed 30
  # cases' concurrency would make any flake among them unattributable.
  export LR_RECOVER_MAX_CONCURRENT=1
  export LR_POOL_POLL_S=0.05            # the pool's claim latency; the CASES assert on ordering logs
  # The admit lock's steal bound. Nothing in this suite should ever reach it — a case that does is
  # reporting a real wedge, not waiting one out.
  export LR_ADMIT_LOCK_WAIT_S=20
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
#
# 🚨 …AND THE ZEROED TAIL WAS STILL AN IDENTIFIER THAT EXISTS OUTSIDE THIS FIXTURE — in every OTHER
# CONCURRENT RUN OF THIS SAME FILE. The rule above was applied against the fleet and not against the
# suite itself. `:181` and `:195` spawn REAL `--resume "$SID"` processes that live 30 s, and
# `lr_resume_procs` (lr-lib.sh:461) greps the REAL process table with no seam, so run A's sleeper is
# a second holder to run B: `--locate` says DUPLICATE where the case pins RECOVERABLE. Measured
# 2026-09-20 by running this file twice at once — **16 of 65 tests fail in BOTH runs**, led by
# `locate: a resumed session's OWN pid is ONE holder` and `duplicates: the two censuses agree`. That
# is the "1 in ~6 full runs under load" flake W3 reported: load means concurrency, and two bats roots
# are allowed (ship-land's gate runs at CC_BATS_MAX_ROOTS=0 regardless), so a lander can be convicted
# for a sibling's sleeper. The tail is therefore derived PER TEST — unique by construction, while the
# `52e35019` prefix the display assertions match on is untouched.
  SID="52e35019-17e8-40f6-a54f-$(printf '%012d' "$(printf '%s' "$BATS_TEST_TMPDIR" | cksum | cut -d' ' -f1)")"
  # lr-handoff stub: records argv, exits per LRH_RC, prints the announcements the fleet parses
  export LR_HANDOFF_BIN="$BATS_TEST_TMPDIR/lr-handoff"
  cat > "$LR_HANDOFF_BIN" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "${LRH_LOG:?}"
# ORDERING LOG, NOT A CLOCK. A walltime assertion in this repo has to carry the sibling suites'
# load guard and two rounds have already been lost to load-fragile timing; an interleaving written
# by the subject itself is load-independent. Inert unless LRH_SLEEP is set.
[ -n "${LRH_SLEEP:-}" ] && { printf 'HF-START %s\n' "$$" >> "${LRH_SEQ:?}"; sleep "$LRH_SLEEP"; printf 'HF-END   %s\n' "$$" >> "$LRH_SEQ"; }
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
  # TWO REAL PROCESSES, because that is what the case name and the asserted message both say. The
  # fixture used to be `row 616; row 647` with row()'s default pid, i.e. ONE process under two pane
  # rows — so it asserted "more than one live process" over a world containing one, and passed only
  # because lr_holder_count counted ROWS. It is the pane-keyed-overwrite shape, which now has its
  # own case below and must NOT be what proves this one.
  /bin/sh -c 'sleep 30; :' --holder-a & local h1=$!
  /bin/sh -c 'sleep 30; :' --holder-b & local h2=$!
  blocked_tx "$SEC" "$SID"; row 616 "$SID" "$h1"; row 647 "$SID" "$h2"
  run bash "$FLEET" --recover
  [ "$status" -eq 1 ]
  [ ! -s "$LRH_LOG" ]
  [[ "$output" == *"DUPLICATE — more than one live process"* ]] || { echo "$output"; false; }
  kill "$h1" "$h2" 2>/dev/null || true
}

@test "locate: ONE pid under TWO pane rows is ONE holder — the pane-keyed-overwrite artifact" {
  # THE OTHER DOOR TO THE SAME FAILURE. The registry is PANE-keyed, so a session that changes panes
  # leaves TWO live rows carrying ONE pid (§ 11 #2). lr_holder_count used to compute rows + procs
  # and subtract only the row/proc OVERLAP — empty here, because there is no resume leaf — so it
  # returned 2, `--locate` said DUPLICATE, and `--recover` PARKED a pane that was recoverable. That
  # is the outcome the overlap fix was written to end, reached the other way. `bin/cc-limited` took
  # a pid SET and got it right, which is why `parity` is the assertion that surfaces it.
  # RED-PROOF: against pristine lr-lib.sh this prints DUPLICATE and the assertion below fails.
  /bin/sh -c 'sleep 30; :' --one-process & local h=$!
  blocked_tx "$SEC" "$SID"; row 616 "$SID" "$h"; row 647 "$SID" "$h"
  mark "$SEC" "$SID" 616
  run bash "$FLEET" --locate
  [[ "$output" != *"DUPLICATE"* ]] || { echo "$output"; false; }
  [[ "$output" == *"RECOVERABLE"* ]] || { echo "$output"; false; }
  parity                                  # BEFORE the kill: a dead holder is a different fixture
  kill "$h" 2>/dev/null || true
}
# RENAMED BY W6b. It used to read "sessions are sequenced one at a time", which is no longer true
# of the driver: `--recover` is a POOL of LR_RECOVER_MAX_CONCURRENT workers. What this case actually
# pins — and always did — is that --max bounds how many are STARTED, which is orthogonal to how
# many run at once. Setup pins the pool at 1, so this runs the shape it was written against.
@test "recover: --max bounds how many sessions a run starts" {
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
  # TWO REAL PROCESSES, one per pane. `--duplicates` is documented as "sessions held by MORE than
  # one live process" (lr-fleet.sh:13-15) and its gate is lr_holder_count, so the old fixture —
  # two rows over row()'s default pid — was ONE holder dressed as two and listed only because the
  # predicate counted rows. `--mark --live` must also name a pid that HOLDS a row, since the
  # tombstone records the live successor and lr-fleet.sh:911 finds its pane by matching that pid.
  /bin/sh -c 'sleep 30; :' --holder-a & local h1=$!
  /bin/sh -c 'sleep 30; :' --holder-b & local h2=$!
  blocked_tx "$SEC" "$SID"; row 616 "$SID" "$h1"; row 647 "$SID" "$h2"
  run bash "$FLEET" --duplicates
  [[ "$output" == *"DUPLICATE 52e35019: 2 registry pane(s)"* ]] || { echo "$output"; false; }
  run bash "$FLEET" --duplicates --mark "$SID" --live "$h2"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  tomb="$SEC/projects/$SLUG/$SID.HANDOFF.json"
  [ -f "$tomb" ]
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["superseded_by_pid"]==int(sys.argv[2]) and d["handed_off_to"].endswith(".claude-secondary"), d' "$tomb" "$h2"
  run bash "$FLEET" --duplicates --mark "$SID" --live "$h2"
  [ "$status" -eq 2 ]                                      # never overwrites a tombstone
  kill "$h1" "$h2" 2>/dev/null || true
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
  # The gap this control needs is a DUPLICATE park, and DUPLICATE now means what it says: TWO
  # PROCESSES. The old fixture made it with two rows over row()'s default pid, which is one process
  # and no longer a duplicate — so the gap has to be built honestly or this control proves nothing.
  /bin/sh -c 'sleep 30; :' --holder-a & local h1=$!
  /bin/sh -c 'sleep 30; :' --holder-b & local h2=$!
  blocked_tx "$SEC" "$SID"; row 616 "$SID" "$h1"; row 617 "$SID" "$h2"
  run bash "$FLEET" --recover
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"RECOVERY PARTIAL — 1 named gap(s)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"1 not owed"* ]] || { echo "$output"; false; }
  kill "$h1" "$h2" 2>/dev/null || true
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
  # W6b: lf_pick_target now calls lf_charge_assign and lf_rank_why, and writes the rank's stderr
  # under $FLEET_DIR/$RUN. An extraction that omits either helper does not test a smaller program,
  # it tests a DIFFERENT one — `command not found` is rc 127, which `|| true` would launder.
  sed -n '/^lf_acct_of_cfg() {/,/^}/p;/^_lf_target_holds_sid() {/,/^}/p;/^lf_rank_why() {/,/^}/p;/^lf_charge_assign() {/,/^}/p;/^lf_pick_target() {/,/^}/p' \
    "$FLEET" > "$BATS_TEST_TMPDIR/pick.sh"
  bash -c '
    . "$1" 2>/dev/null
    . "$2" 2>/dev/null || true
    . "$3"
    TARGET=auto; DRY=0; ACCOUNTS="$CC_ACCOUNTS_BIN"
    FLEET_DIR="$BATS_TEST_TMPDIR/pickfleet"; RUN=pick
    lf_pick_target "$4" "$5" "$6"; rc=$?
    # It SETS a global now rather than printing — the harness prints it, so every case written
    # against the old stdout contract reads byte-identically.
    printf "%s" "${LF_PICK_TARGET:-}"
    printf "\nSKIPPED=%s\n" "${LF_PICK_SKIPPED_HOLDER:-}"
    printf "REJECTED=%s\n" "${LF_PICK_REJECTED:-}"
    printf "WHY=%s\n" "${LF_RANK_WHY:-}"
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

@test "dedupe: a HUSK row is never the mirror's duplicate — the successor must not take its slot" {
  # THE FALSE GREEN THIS ENDS. lf_dedup_mirror collapses ~/.claude and ~/.claude-next, which are ONE
  # account behind a symlink, and it was keyed on the SID alone. After a transplant that is the wrong
  # key: the session exists under two accounts as two objects with OPPOSITE dispositions — the husk on
  # the source store, the live successor on the target — and "prefer any account that is not .claude"
  # handed the slot to the SUCCESSOR and discarded the husk. Measured 2026-09-20 on panes 110 and 126:
  # lf_locate emitted both HUSK rows, both panes were live and enumerable, lr_husk_state said HUSK for
  # both, and --locate printed NEITHER. A 0-HUSK census over two standing husks.
  run bash -c '
    printf "sid1\t/c/.claude\t.claude\t110\t99\t/w\t-\tHUSK\tlimit\tlimit\t-\n"   >  "$BATS_TEST_TMPDIR/rows"
    printf "sid1\t/c/.claude-tertiary\tnext3\t999\t98\t/w\t-\tRECOVERABLE\tlimit\tlimit\t-\n" >> "$BATS_TEST_TMPDIR/rows"
    sed -n "/^lf_dedup_mirror()/,/^}/p" "'"$FLEET"'" > "$BATS_TEST_TMPDIR/d.sh"; . "$BATS_TEST_TMPDIR/d.sh"
    lf_dedup_mirror < "$BATS_TEST_TMPDIR/rows"'
  [[ "$output" == *"HUSK"* ]] || { echo "the successor took the husk's slot: $output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ] || { echo "dedupe stopped deduping: $output"; false; }
}

@test "dedupe CONTROL: the plain mirror rule is unchanged — non-HUSK still prefers the real account" {
  run bash -c '
    printf "sid2\t/c/.claude\t.claude\t110\t99\t/w\t-\tRECOVERABLE\tlimit\tlimit\t-\n"  >  "$BATS_TEST_TMPDIR/rows"
    printf "sid2\t/c/.claude-next\tnext\t110\t99\t/w\t-\tRECOVERABLE\tlimit\tlimit\t-\n" >> "$BATS_TEST_TMPDIR/rows"
    sed -n "/^lf_dedup_mirror()/,/^}/p" "'"$FLEET"'" > "$BATS_TEST_TMPDIR/d.sh"; . "$BATS_TEST_TMPDIR/d.sh"
    lf_dedup_mirror < "$BATS_TEST_TMPDIR/rows"'
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"next"* ]] || { echo "the mirror rule changed: $output"; false; }
}

# ══════════════════════════════════════════════════════════════════════════════════════════════
# W6b (docs/research/lr100p-2026-09-19/PLAN_DRAFT.md § W6b) — RANK → ASSIGN → PROBE, SERIALIZED;
# AND A POOL INSTEAD OF A QUEUE.
#
# Four things are new and each is a separate failure if it goes untested: the rank is asked in the
# RECOVERY lane (W6a's survival floors, not a dispatch's), the pick CHARGES the router so a burst
# spreads, the admit section is SERIALIZED so N workers cannot read one census N times, and the
# actuator half is a POOL so five recoveries do not cost five serial 115-658 s runs.
#
# EVERY CASE ASSERTS ON AN ORDERING LOG, NEVER ON A CLOCK. Two rounds of this plan have been lost
# to load-fragile timing cases, and a walltime assertion here would need the sibling suites' load
# guard to mean anything. An interleaving written by the SUBJECT (the stub's own log) is load-
# independent: under any load, a serialized section cannot produce two STARTs in a row.
# ══════════════════════════════════════════════════════════════════════════════════════════════

# The argv-recording, configurable claude-accounts. One stub, driven by environment, because the
# cases differ only in what the router SAYS. `--assign` is answered with a bare exit 0 (the real
# one is a write-and-exit, dispatched before any sweep — bin/claude-accounts:5830), so no case can
# reach a live router or a live ledger.
acct_stub() {
  cat > "$CC_ACCOUNTS_BIN" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "${ACC_LOG:?}"
case "$*" in
  *--rank*)
    [ -n "${ACC_RANK_SLEEP:-}" ] && { printf 'RANK-START %s\n' "$$" >> "${ACC_SEQ:?}"; sleep "$ACC_RANK_SLEEP"; }
    [ -n "${ACC_RANK_ERR:-}" ] && printf '%b\n' "$ACC_RANK_ERR" >&2
    [ -n "${ACC_RANK_OUT:-}" ] && printf '%b' "$ACC_RANK_OUT"
    [ -n "${ACC_RANK_SLEEP:-}" ] && printf 'RANK-END   %s\n' "$$" >> "${ACC_SEQ:?}"
    exit "${ACC_RANK_RC:-0}" ;;
esac
exit 0
SH
  chmod +x "$CC_ACCOUNTS_BIN"
  export ACC_LOG="$BATS_TEST_TMPDIR/acct.argv"; : > "$ACC_LOG"
  export ACC_SEQ="$BATS_TEST_TMPDIR/acct.seq"; : > "$ACC_SEQ"
  # EVERY knob is exported HERE, empty, even the ones no case sets by default. A `VAR=x run …`
  # prefix on a bats FUNCTION only reaches the subprocess when VAR is already in the environment —
  # otherwise it is a plain shell variable and the stub never sees it. Measured on this file: the
  # empty-rank case silently exercised the no-reason arm instead of the reasons arm and PASSED a
  # weaker assertion, which is the fixture-quoting failure shape in reverse.
  export ACC_RANK_OUT='next2 0.9\nnext3 0.8\nnext4 0.5\n'
  export ACC_RANK_ERR=""
  export ACC_RANK_RC=0
  export ACC_RANK_SLEEP=""
}
# A section is SERIALIZED iff no START is reached while another is open. Reads the subject's own
# log; `n` guards against the vacuous pass where the log holds fewer than two entries.
no_overlap() { # <log> <start-token> — 0 when the log never overlaps AND holds ≥2 starts
  awk -v tok="$2" '
    $0 ~ tok"-START" { if (open) { print "OVERLAP at line " NR; bad = 1 } open = 1; n++ }
    $0 ~ tok"-END"   { open = 0 }
    END { if (n < 2) { print "VACUOUS: only " n+0 " start(s) — the case never ran two workers"; exit 1 }
          exit (bad ? 1 : 0) }' "$1"
}
overlapped() { # <log> <start-token> — 0 when the log DOES overlap (the pool actually ran two at once)
  awk -v tok="$2" '
    $0 ~ tok"-START" { if (open) { ov = 1 } open = 1; n++ }
    $0 ~ tok"-END"   { open = 0 }
    END { if (n < 2) { print "VACUOUS: only " n+0 " start(s)"; exit 1 }
          if (!ov) { print "NO OVERLAP: the two workers never ran together" ; exit 1 }
          exit 0 }' "$1"
}

@test "W6b: the rank is asked in the RECOVERY lane, bounded, and its stderr is kept" {
  # blocked_tx's DEFAULT model is claude-fable-5-1, which selects the fable lane — so the general
  # lane has to be asked for explicitly or this case silently asserts about the wrong one.
  acct_stub; blocked_tx "$SEC" "$SID" claude-opus-5 high; row 616 "$SID"
  run bash "$FLEET" --recover
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # A recovery is not a dispatch: the modifier is what turns on the SURVIVAL floors, so a target
  # with room for a fire but not for a transplant is excluded here rather than two hours later.
  grep -q -- '--rank general --recovery --max-wait 3' "$ACC_LOG" || { cat "$ACC_LOG"; false; }
  # The router's own words are kept on disk, which is what makes the park note re-derivable.
  ls "$LR_STATE_DIR"/fleet/*/rank.general.stderr >/dev/null 2>&1 || { ls -R "$LR_STATE_DIR/fleet"; false; }
}

@test "W6b: the fable tier asks the FABLE lane in recovery mode, not general" {
  acct_stub; blocked_tx "$SEC" "$SID" claude-fable-5-1 xhigh; row 616 "$SID"
  run bash "$FLEET" --recover
  grep -q -- '--rank fable --recovery --max-wait 3' "$ACC_LOG" || { cat "$ACC_LOG"; false; }
}

@test "W6b: --assign is charged exactly ONCE per pick, naming lr-fleet as the source" {
  acct_stub; blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --recover
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(grep -c -- '--assign' "$ACC_LOG")" = 1 ] || { cat "$ACC_LOG"; false; }
  grep -q -- '--assign next3 --src lr-fleet' "$ACC_LOG" || { cat "$ACC_LOG"; false; }
}

@test "W6b: --dry-run charges NOTHING — a phantom with no body decays only on its TTL" {
  acct_stub; blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --recover --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(grep -c -- '--assign' "$ACC_LOG")" = 0 ] || { cat "$ACC_LOG"; false; }
  [[ "$output" == *"not charging --assign"* ]] || { echo "$output"; false; }
}

@test "W6b: an empty rank parks carrying the ROUTER's own reasons, never 'returned nothing past'" {
  acct_stub; blocked_tx "$SEC" "$SID"; row 616 "$SID"
  # The recovery lane's all-thin shape: stdout `none`, exit 2 (POLICY), and the reasons on stderr.
  ACC_RANK_OUT='none\n' ACC_RANK_RC=2 \
  ACC_RANK_ERR='claude-accounts: no routable account for general: next2=recovery-weekly-thin; next3=recovery-5h-thin; next4=no-weekly-data' \
    run bash "$FLEET" --recover
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"recovery-weekly-thin"* ]] || { echo "$output"; false; }
  [[ "$output" == *"recovery-5h-thin"* ]] || { echo "$output"; false; }
  [[ "$output" != *"returned nothing past"* ]] || { echo "$output"; false; }
  [ ! -s "$LRH_LOG" ]
}

@test "W6b CONTROL: with no reason on stderr the park says the router printed none, and names the file" {
  acct_stub; blocked_tx "$SEC" "$SID"; row 616 "$SID"
  ACC_RANK_OUT='none\n' ACC_RANK_RC=2 ACC_RANK_ERR='' run bash "$FLEET" --recover
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"printed no reason"* ]] || { echo "$output"; false; }
  [[ "$output" == *"rank.*.stderr"* ]] || { echo "$output"; false; }
}

@test "W6b: the router naming an account the map does not declare is WALKED PAST, never fired at" {
  acct_stub; blocked_tx "$SEC" "$SID"; row 616 "$SID"
  ACC_RANK_OUT='nxet9 0.9\nnext3 0.8\n' run bash "$FLEET" --recover
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q -- '--target next3' "$LRH_LOG" || { cat "$LRH_LOG"; false; }
  [[ "$output" == *"does not declare"* ]] || { echo "$output"; false; }
  # …and it is never charged either: a charge against a name nothing resolves is a lost phantom.
  [ "$(grep -c -- '--assign nxet9' "$ACC_LOG")" = 0 ] || { cat "$ACC_LOG"; false; }
}

@test "W6b: two workers SERIALIZE the admit section — the rank stub's own log shows no overlap" {
  acct_stub; blocked_tx "$SEC" "$SID"; row 616 "$SID"
  s2="66660000-0000-4000-8000-00000000b001"; blocked_tx "$SEC" "$s2"; row 631 "$s2"
  # 1 s, not the draft's 3 s: the assertion is on the ORDERING, which a 1 s window makes just as
  # unambiguous while keeping the suite's own walltime honest.
  LR_RECOVER_MAX_CONCURRENT=2 ACC_RANK_SLEEP=1 run bash "$FLEET" --recover
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run no_overlap "$ACC_SEQ" RANK
  [ "$status" -eq 0 ] || { echo "$output"; cat "$ACC_SEQ"; false; }
}

@test "W6b: the ACTUATOR half is a POOL — two recoveries overlap, they are not queued" {
  acct_stub; blocked_tx "$SEC" "$SID"; row 616 "$SID"
  s2="66660000-0000-4000-8000-00000000b002"; blocked_tx "$SEC" "$s2"; row 632 "$s2"
  export LRH_SEQ="$BATS_TEST_TMPDIR/lrh.seq"; : > "$LRH_SEQ"
  LR_RECOVER_MAX_CONCURRENT=2 LRH_SLEEP=1 run bash "$FLEET" --recover
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run overlapped "$LRH_SEQ" HF
  [ "$status" -eq 0 ] || { echo "$output"; cat "$LRH_SEQ"; false; }
}

@test "W6b CONTROL: LR_RECOVER_MAX_CONCURRENT=1 is a queue again — the actuator never overlaps" {
  acct_stub; blocked_tx "$SEC" "$SID"; row 616 "$SID"
  s2="66660000-0000-4000-8000-00000000b003"; blocked_tx "$SEC" "$s2"; row 633 "$s2"
  export LRH_SEQ="$BATS_TEST_TMPDIR/lrh.seq"; : > "$LRH_SEQ"
  LR_RECOVER_MAX_CONCURRENT=1 LRH_SLEEP=1 run bash "$FLEET" --recover
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run no_overlap "$LRH_SEQ" HF
  [ "$status" -eq 0 ] || { echo "$output"; cat "$LRH_SEQ"; false; }
}

@test "W6b: a sid a LIVE run already claims is skipped and SAID, never driven twice" {
  acct_stub; blocked_tx "$SEC" "$SID"; row 616 "$SID"
  # The shape lr-reset-poller.sh:716 and bin/cc-lr:128 both write. $$ is this bats process: really
  # alive, really ours — never an id that could belong to a stranger (the pid-namespace-wraps rule).
  mkdir -p "$LR_STATE_DIR/runs/by-sid/$SID.active"
  printf '{"sid":"%s","pid":%d,"by":"cc-lr"}\n' "$SID" "$$" > "$LR_STATE_DIR/runs/by-sid/$SID.active/holder"
  run bash "$FLEET" --recover
  [ ! -s "$LRH_LOG" ] || { cat "$LRH_LOG"; false; }
  [[ "$output" == *"a live run already holds"* ]] || { echo "$output"; false; }
  [ -d "$LR_STATE_DIR/runs/by-sid/$SID.active" ]      # someone else's claim is left exactly as found
}

@test "W6b CONTROL: a claim held by a DEAD pid is stolen — a corpse must not wedge a sid forever" {
  acct_stub; blocked_tx "$SEC" "$SID"; row 616 "$SID"
  /bin/sh -c ':' & local dead=$!; wait "$dead" 2>/dev/null || true
  mkdir -p "$LR_STATE_DIR/runs/by-sid/$SID.active"
  printf '{"sid":"%s","pid":%d,"by":"cc-lr"}\n' "$SID" "$dead" > "$LR_STATE_DIR/runs/by-sid/$SID.active/holder"
  run bash "$FLEET" --recover
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q -- '--in-place' "$LRH_LOG" || { cat "$LRH_LOG"; echo "$output"; false; }
  [[ "$output" == *"which is DEAD — stealing it"* ]] || { echo "$output"; false; }
}

@test "W6b: --dry-run reserves NO run claim — a preview must not block the real recovery" {
  acct_stub; blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --recover --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -d "$LR_STATE_DIR/runs/by-sid/$SID.active" ] || { ls -R "$LR_STATE_DIR/runs"; false; }
}

@test "W6b: a completed pool worker RELEASES its claim — the next run is not locked out" {
  acct_stub; blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --recover
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -d "$LR_STATE_DIR/runs/by-sid/$SID.active" ] || { ls -R "$LR_STATE_DIR/runs"; false; }
  [ ! -d "$LR_STATE_DIR/admit.lock" ] || { ls -R "$LR_STATE_DIR"; false; }
}

@test "W6b: --one does NOT take the run claim — lr-reset-poller and cc-lr already hold it" {
  # THE REGRESSION THIS GUARDS. Both callers of `--one` reserve the sid BEFORE invoking it
  # (lr-reset-poller.sh:835, bin/cc-lr:220). A claim taken inside `--one` too would make the daemon
  # and cc-lr refuse every recovery they themselves had just reserved.
  acct_stub; blocked_tx "$SEC" "$SID"; row 616 "$SID"
  mkdir -p "$LR_STATE_DIR/runs/by-sid/$SID.active"
  printf '{"sid":"%s","pid":%d,"by":"cc-lr"}\n' "$SID" "$$" > "$LR_STATE_DIR/runs/by-sid/$SID.active/holder"
  run bash "$FLEET" --one "$SID"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q -- '--in-place' "$LRH_LOG" || { cat "$LRH_LOG"; echo "$output"; false; }
}

@test "W6b: an admit lock left by a DEAD holder is stolen AT ONCE, not waited out" {
  acct_stub; blocked_tx "$SEC" "$SID"; row 616 "$SID"
  /bin/sh -c ':' & local dead=$!; wait "$dead" 2>/dev/null || true
  mkdir -p "$LR_STATE_DIR/admit.lock"; printf '%s\n' "$dead" > "$LR_STATE_DIR/admit.lock/pid"
  # 60 s: long enough that a time-based steal cannot be what rescues this run inside the case's
  # own life, so the assertion below is about the DEAD-holder arm and nothing else.
  LR_ADMIT_LOCK_WAIT_S=60 run bash "$FLEET" --recover
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"admit lock"*"which is DEAD — stealing it"* ]] || { echo "$output"; false; }
  grep -q -- '--in-place' "$LRH_LOG" || { cat "$LRH_LOG"; false; }
}

@test "W6b: an admit lock held by a LIVE holder is waited out and then stolen, LOUDLY" {
  acct_stub; blocked_tx "$SEC" "$SID"; row 616 "$SID"
  mkdir -p "$LR_STATE_DIR/admit.lock"; printf '%s\n' "$$" > "$LR_STATE_DIR/admit.lock/pid"
  LR_ADMIT_LOCK_WAIT_S=1 run bash "$FLEET" --recover
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # A steal past a LIVE holder can double-admit, and that is a fact the operator gets to read.
  [[ "$output" == *"STEALING it"* ]] || { echo "$output"; false; }
  [[ "$output" == *"a second recovery may be admitted against one capacity reading"* ]] || { echo "$output"; false; }
}

@test "W6b: lf_row BOUNDS its note — the pool made results.tsv a concurrent file" {
  sed -n '/^lf_now() {/,/^}/p;/^lf_row() {/,/^}/p' "$FLEET" > "$BATS_TEST_TMPDIR/row.sh"
  mkdir -p "$BATS_TEST_TMPDIR/rowfleet/r"
  long="$(python3 -c 'print("x"*5000)')"
  FLEET_DIR="$BATS_TEST_TMPDIR/rowfleet" RUN=r LONG="$long" \
    bash -c '. "$1"; lf_row s p p a b mech "$LONG"' _ "$BATS_TEST_TMPDIR/row.sh"
  n="$(awk 'NR==1 { print length($0) }' "$BATS_TEST_TMPDIR/rowfleet/r/results.tsv")"
  [ "$n" -lt 1024 ] || { echo "row is $n bytes — O_APPEND is no longer atomic for it"; false; }
  [ "$(wc -l < "$BATS_TEST_TMPDIR/rowfleet/r/results.tsv" | tr -d ' ')" = 1 ]
}

@test "W6b: lf_row keeps a tab or newline in a note from re-columning the row" {
  sed -n '/^lf_now() {/,/^}/p;/^lf_row() {/,/^}/p' "$FLEET" > "$BATS_TEST_TMPDIR/row.sh"
  mkdir -p "$BATS_TEST_TMPDIR/rowfleet2/r"
  FLEET_DIR="$BATS_TEST_TMPDIR/rowfleet2" RUN=r \
    bash -c '. "$1"; lf_row s p p a b mech "$(printf "one\ttwo\nthree")"' _ "$BATS_TEST_TMPDIR/row.sh"
  [ "$(wc -l < "$BATS_TEST_TMPDIR/rowfleet2/r/results.tsv" | tr -d ' ')" = 1 ]
  [ "$(awk -F'\t' 'NR==1 { print NF }' "$BATS_TEST_TMPDIR/rowfleet2/r/results.tsv")" = 8 ]
}

@test "W6b: the holder-skip park note reaches the ROW — before this wave it died in a subshell" {
  # THE REPAIR, END TO END. `targets already hold this sid: …` landed 2026-09-20 with a passing
  # case over the DIRECT-call harness (_pick) and was unreachable from lf_one, which read the
  # function through `$( )`. Only a case that goes through --recover can see the difference.
  acct_stub; blocked_tx "$SEC" "$SID"; row 616 "$SID"
  QUA="$HOME/.claude-quaternary"; mkdir -p "$TER/projects/$SLUG" "$QUA/projects/$SLUG"
  : > "$TER/projects/$SLUG/$SID.jsonl.handed-off"     # next3 holds its retired source
  : > "$QUA/projects/$SLUG/$SID.jsonl"                # next4 holds the real transcript
  LR_CONFIG_DIRS="$SEC:$TER:$QUA" run bash "$FLEET" --recover
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"already holds this session (next3 next4)"* ]] || { echo "$output"; false; }
  [ ! -s "$LRH_LOG" ]
}

@test "W6b: a junk LR_RECOVER_MAX_CONCURRENT falls back rather than wedging the pool" {
  # `0` and a non-numeric both make the slot test "fewer than N in flight" unsatisfiable — 0 by
  # arithmetic, junk by `[: integer expression expected` — and an unsatisfiable slot test is not a
  # slow pool, it is a driver that never starts a worker and never returns. The fallback is what
  # keeps a typo in a launchd environment from wedging the daemon's whole request drain.
  acct_stub; blocked_tx "$SEC" "$SID"; row 616 "$SID"
  LR_RECOVER_MAX_CONCURRENT=nonsense run bash "$FLEET" --recover
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q -- '--in-place' "$LRH_LOG" || { cat "$LRH_LOG"; false; }
}

@test "W6b CONTROL: a zero LR_RECOVER_MAX_CONCURRENT falls back too" {
  acct_stub; blocked_tx "$SEC" "$SID"; row 616 "$SID"
  LR_RECOVER_MAX_CONCURRENT=0 run bash "$FLEET" --recover
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q -- '--in-place' "$LRH_LOG" || { cat "$LRH_LOG"; false; }
}

@test "W6b: route-meta is not a REASON — a park must not quote the router's input dump at the operator" {
  # A REAL shape, not a hypothetical: bin/claude-accounts' CacheOnlyUnavailable handler prints
  # `none` on stdout and `route-meta: cache=absent mode=cache-only waited_ms=0` on stderr. That
  # line is the decision's INPUTS, never its reason, and folding it into the park note would put
  # `k_eff`/`cliff_band` tokens in front of an operator who asked why nothing was routable.
  acct_stub; blocked_tx "$SEC" "$SID"; row 616 "$SID"
  ACC_RANK_OUT='none\n' ACC_RANK_RC=3 \
  ACC_RANK_ERR='route-meta: cache=absent mode=cache-only waited_ms=0' \
    run bash "$FLEET" --recover
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" != *"route-meta"* ]] || { echo "$output"; false; }
  [[ "$output" == *"printed no reason"* ]] || { echo "$output"; false; }
}
