#!/usr/bin/env bats
# operator-readout.sh — Stop hook: the silver-platter close renderer. Proves:
#   · fire predicate (steps>0 ∨ 📦; silent on ✅/🔧-with-no-steps)
#   · every step source renders its EXACT runnable command (fixture-parity: fixtures are created
#     by the REAL producers — cc-decide / cc-backlog / activation-file convention — never by
#     hand-rolled JSON, per the fixture-shape-parity rule)
#   · degradation order for decisions: run_command → staged_artifact_path → prose-◆
#   · damping: change→render, unchanged+TTL→silent, TTL-elapsed→re-render
#   · pure-advisory contract: output is {systemMessage}, NEVER {decision:"block"}; exit 0 always
#   · compose-guard (continue-armed), kill-switch, cap+footer counts, B ≤24h veto summary
#   · IDL B-3: one {fired|abstained} line per hook invocation

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/operator-readout.sh"
  DECIDE="$REPO/bin/cc-decide"
  BACKLOG="$REPO/bin/cc-backlog"

  export CC_OPREADOUT_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_ACTIVATION_DIR="$BATS_TEST_TMPDIR/activation"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_BIN="$BACKLOG"
  export WRAP_LEDGER_BIN="$REPO/scripts/wrap-ledger.sh"
  export WRAP_TRUNK="origin/main"
  # point the shared checkout at an EMPTY fixture by default → no deploy-lag step
  export CC_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/no-such-checkout"
  export CC_OPREADOUT_NOW=1000000
  export CC_OPREADOUT_TTL_S=900
  mkdir -p "$CC_ACTIVATION_DIR" "$CC_DECISIONS_DIR"
  : > "$CC_BACKLOG_FILE"
}

hookrun() { # $1=cwd → run hook mode with stdin JSON; stdout in $output
  printf '{"session_id":"t-%s","cwd":"%s"}' "$BATS_TEST_NUMBER" "${1:-}" | "$HOOK"
}

# clean repo, HEAD == origin/main (landed → ✅-shaped git state)
mkrepo_landed() {
  local o="$BATS_TEST_TMPDIR/o-$1.git" w="$BATS_TEST_TMPDIR/w-$1"
  git init -q --bare "$o"; git clone -q "$o" "$w"
  ( cd "$w"; git config user.email t@e.com; git config user.name t; git checkout -q -b main
    echo base > base.txt; git add base.txt; git commit -q -m base; git push -q -u origin main ) >/dev/null 2>&1
  printf '%s' "$w"
}
# clean tree, one commit ahead (committed-but-unlanded → 📦)
mkrepo_unlanded() {
  local w; w="$(mkrepo_landed "$1")"
  ( cd "$w"; echo x > x.txt; git add x.txt; git commit -q -m "unlanded work" ) >/dev/null 2>&1
  printf '%s' "$w"
}

# ── fire predicate ────────────────────────────────────────────────────────────────────────────────

@test "no steps + landed-clean repo → silent (exit 0, no output), IDL abstain logged" {
  w="$(mkrepo_landed a)"
  run hookrun "$w"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q '"disposition":"abstained","reason":"nothing-to-surface"' "$CC_IDL"
}

@test "no steps + 📦 unlanded repo → fires with the parked state line and /ship verb" {
  w="$(mkrepo_unlanded b)"
  run hookrun "$w"
  [ "$status" -eq 0 ]
  msg="$(printf '%s' "$output" | jq -r '.systemMessage')"
  printf '%s' "$msg" | grep -q '📦 parked — 1 commit(s)'
  printf '%s' "$msg" | grep -q '→ /ship'
}

@test "pure-advisory contract: fired output carries systemMessage and NEVER decision:block" {
  w="$(mkrepo_unlanded c)"
  run hookrun "$w"
  printf '%s' "$output" | jq -e '.systemMessage' >/dev/null
  printf '%s' "$output" | jq -e 'has("decision") | not' >/dev/null
}

# ── step sources (fixture-parity: real producers) ────────────────────────────────────────────────

@test "COLLAPSE: 2 un-run activations render ONE cc-do line naming both stems; .done never appears" {
  # The operator's 2026-07-31 close: nine numbered lines, the activation ones wrapping to FOUR
  # terminal lines each because `CONFIRM=1 bash <60-char path> && touch <same 60-char path>.done`
  # names the same path twice. Collapse emits one short line instead. Its stems are what make the
  # line informative rather than a bare count.
  printf '#!/bin/bash\necho hi\n' > "$CC_ACTIVATION_DIR/10-plain-activate.sh"
  printf '#!/bin/bash\n[ "${CONFIRM:-0}" = 1 ] || exit 0\n' > "$CC_ACTIVATION_DIR/11-gated-activate.sh"
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/12-done-activate.sh"
  : > "$CC_ACTIVATION_DIR/12-done-activate.sh.done"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '▶ cc-do   \[2 runnable: ' || false
  echo "$output" | grep -q '11-gated-activate' || false          # CONFIRM-gated named first (F6)
  echo "$output" | grep -q '10-plain-activate' || false
  ! echo "$output" | grep -q '12-done-activate' || false
  # THE POINT: the long double-path form is GONE from the default render.
  ! echo "$output" | grep -q '&& touch' || false
}

@test "COLLAPSE: 2-3 judgment items name EVERY id — the round-trip case cc-decide veto needs" {
  _legacy_pkt shipland-esc-aaaaaaa
  _legacy_pkt shipland-esc-bbbbbbb
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '◆ 2 decisions — your call: ' || false
  echo "$output" | grep -q 'shipland-esc-aaaaaaa' || false
  echo "$output" | grep -q 'shipland-esc-bbbbbbb' || false
}

@test "COLLAPSE: exactly ONE runnable step is still itemised verbatim, not collapsed to a count" {
  # A count of 1 says strictly less than the step itself, and costs the same line.
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/10-solo-activate.sh"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '▶ cc-do 10-solo-activate   \[activation\]' || false
  ! echo "$output" | grep -q 'runnable:' || false
}

@test "I11 DEGRADATION: cc-do absent → the long bash+touch form renders (the one that DOES run)" {
  # A close naming a command the machine does not have is worse than a long command that works.
  # bin/cc-* deploys by install.sh glob, so this hook can land before the driver reaches PATH.
  printf '#!/bin/bash\necho hi\n' > "$CC_ACTIVATION_DIR/10-plain-activate.sh"
  printf '#!/bin/bash\n[ "${CONFIRM:-0}" = 1 ] || exit 0\n' > "$CC_ACTIVATION_DIR/11-gated-activate.sh"
  CC_DO_BIN=none run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'bash .*/10-plain-activate.sh && touch .*/10-plain-activate.sh.done   \[activation\]' || false
  echo "$output" | grep -q 'CONFIRM=1 bash .*/11-gated-activate.sh' || false
  ! echo "$output" | grep -q 'cc-do' || false
}

@test "COLLAPSE: >3 runnable drops the stem list entirely — a partial naming is noise, not info" {
  # Naming 3 of 174 pushed these lines past 130 chars, i.e. back into the wrapping this change
  # exists to kill, while telling the operator almost nothing. Above 3, cc-do enumerates.
  for i in 1 2 3 4 5; do printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/5$i-x-activate.sh"; done
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '▶ cc-do   \[5 runnable\]' || false
  ! echo "$output" | grep -q '5 runnable:' || false
  # bounded by construction: the whole step render is ONE line here, not five.
  nlines="$(echo "$output" | grep -cE '^ (▶|◆)')"
  [ "$nlines" -eq 1 ]
  # and it fits a terminal — the entire point.
  [ "$(echo "$output" | awk '{print length($0)}' | sort -rn | head -1)" -le 100 ]
}

@test "COLLAPSE: 2-3 runnable DO name every stem (the naming is complete, so it round-trips)" {
  for i in 1 2 3; do printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/6$i-y-activate.sh"; done
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '▶ cc-do   \[3 runnable: ' || false
  echo "$output" | grep -q '61-y-activate' || false
  echo "$output" | grep -q '63-y-activate' || false
  ! echo "$output" | grep -q '+' || false
}

@test "COLLAPSE: many judgment items become ONE counted line per class, carrying ids + the listing cmd" {
  # 19 decisions itemised is the wall; 19 counted with 3 ids named is a decision point. `cc-decide
  # veto` resolves an EXACT id, so the ids must survive the collapse or there is nothing to paste.
  for i in 1 2 3 4 5; do _legacy_pkt "shipland-esc-many$i"; done
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '◆ 5 decisions — your call   cc-decide list --open' || false
  ! echo "$output" | grep -q 'shipland-esc-many1' || false
  [ "$(echo "$output" | awk '{print length($0)}' | sort -rn | head -1)" -le 100 ]
  nlines="$(echo "$output" | grep -cE '^ (▶|◆)')"
  [ "$nlines" -eq 1 ]
}

@test "open class-C decision with staged artifact renders '▶ bash <staged>' (real cc-decide packet)" {
  "$DECIDE" open --class C --what "Wire the widget. Full detail here." \
    --staged-artifact "$BATS_TEST_TMPDIR/staged-fix.sh" >/dev/null
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q "▶ bash $BATS_TEST_TMPDIR/staged-fix.sh   \[decision C "
  echo "$output" | grep -q 'Wire the widget'
}

@test "open class-C without command degrades to ◆ first-sentence; class-A never renders" {
  "$DECIDE" open --class C --what "Choose the reboot posture. Long tail of context that must not appear." >/dev/null
  "$DECIDE" open --class A --what "Auto-decided audit trail entry. Never operator-facing." >/dev/null
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '◆ \[decision C .*\] Choose the reboot posture'
  ! echo "$output" | grep -q 'Long tail of context' || false
  ! echo "$output" | grep -q 'audit trail entry'
}

# ── a hard block wearing the wrong label still reaches the board ───────────────────────────────
# scripts/ship-land.sh writes its park packet directly rather than through `cc-decide open`, and the
# legacy shape was class B with NO status, NO default and NO deadline. `cc-decide open` REFUSES that
# combination (class-B requires both), so such a packet can only be hand-written — it is a hard block
# mislabelled, and six of them sat parked and unrendered. Fixtures here are raw JSON for that reason.
_legacy_pkt() {  # $1=id  [$2=extra jq object]
  local extra="${2:-}"
  [ -n "$extra" ] || extra='{}'
  jq -n --arg id "$1" '{id:$id, class:"B", what_plain:"ship-land refused to auto-land branch x. Tail.",
                        options:[], recommendation:"review"}
                       + ('"$extra"')' > "$CC_DECISIONS_DIR/$1.json"
  [ -s "$CC_DECISIONS_DIR/$1.json" ] || { echo "_legacy_pkt: fixture build failed" >&2; return 1; }
}

@test "a status-less class-B with no default/deadline renders on the board (the ship-land park shape)" {
  _legacy_pkt shipland-esc-deadbee
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q 'ship-land refused to auto-land'
  # labelled with the class it actually CARRIES, so the row reconciles with `cc-decide list --all`
  echo "$output" | grep -q '◆ \[decision B shipland-esc-deadbee\]'
}

@test "board ids ROUND-TRIP: the printed decision id is the whole id, not an 8-char slice" {
  # `cc-decide veto|action` resolves an EXACT id — a truncated one is "unknown id", and every
  # shipland-esc-* packet used to collapse to the same unusable label "shipland".
  _legacy_pkt shipland-esc-1111111
  _legacy_pkt shipland-esc-2222222
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q 'shipland-esc-1111111'
  echo "$output" | grep -q 'shipland-esc-2222222'
  ! echo "$output" | grep -q '\[decision B shipland\]' || false
}

@test "the decision overflow pointer does NOT filter to --class C (it would hide the folded rows)" {
  # The pointer must reproduce the rows it summarises; `--class C` would hide every folded class-B.
  for i in 1 2 3 4 5 6 7 8 9; do _legacy_pkt "shipland-esc-over$i"; done
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q 'cc-decide list --open'
  ! echo "$output" | grep -q 'cc-decide list --open --class C' || false
}

@test "a WELL-FORMED class-B (default+deadline) still does NOT render as an operator step" {
  # The control that keeps the fold narrow: a real class-B auto-fires at its deadline and is covered
  # by the ≤24h auto-fire line, not by the human-gated steps. Only the never-resolvable B folds in.
  "$DECIDE" open --class B --what "Pick an account. Tail." \
    --default "continue on next2" --deadline "2099-01-01T00:00:00Z" >/dev/null
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  ! echo "$output" | grep -q '◆ \[decision B .*\] Pick an account' || false
}

@test "actioned/vetoed class-C packets stop rendering (status is honored)" {
  id="$("$DECIDE" open --class C --what "Transient gate. Done soon.")"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q 'Transient gate'
  "$DECIDE" action "$id" --evidence t >/dev/null
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  ! echo "$output" | grep -q 'Transient gate'
}

@test "blocked backlog item renders ◆ with its needs text (real cc-backlog producer)" {
  id="$("$BACKLOG" add --title "Rotate the API key" --project infra)"
  "$BACKLOG" block "$id" --needs "operator must mint the key in the vendor console" >/dev/null
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '◆ \[backlog .*\] Rotate the API key — needs: operator must mint the key'
}

@test "forward-compat: a backlog item carrying a run/run_command field renders it as ▶" {
  # main's fold whitelists fields (no run yet); feat/board-runnable-commands adds it. The
  # renderer's contract seam is `cc-backlog list --blocked --json` output — stub that binary
  # with the board branch's emission shape and prove the ▶ path is already wired.
  stub="$BATS_TEST_TMPDIR/cc-backlog-stub"
  cat > "$stub" <<'EOS'
#!/bin/bash
printf '[{"id":"abc123def456","title":"Load the dispatcher","needs":"run the loader","run":"launchctl load ~/L/dispatcher.plist","status":"blocked"}]\n'
EOS
  chmod +x "$stub"
  CC_BACKLOG_BIN="$stub" run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '▶ launchctl load ~/L/dispatcher.plist   \[backlog abc123def456: Load the dispatcher\]'
}

@test "deploy-lag: shared checkout on main behind origin/main renders the green-stamp-gated deploy command" {
  w="$(mkrepo_landed d)"
  ( cd "$w"; echo z > z.txt; git add z.txt; git commit -q -m more; git push -q origin main
    git reset -q --hard HEAD~1 ) >/dev/null 2>&1   # local main now 1 behind its origin/main
  export CC_SHARED_CHECKOUT="$w"
  # HERMETIC via the CC_DEPLOY_SCRIPT seam. It used to assert the operator's real
  # ~/.claude/scripts/deploy-live.sh, which did not exist for the entire window in which
  # com.claude.deploy-live logged 59 `cannot execute: No such file or directory` failures — so the
  # test would have gone red exactly when the platter was broken, and for the wrong reason. The
  # DEFAULT is pinned by its own case below (memory: hermetic-suite-leaks-caller-identity).
  live="$BATS_TEST_TMPDIR/dl-default.sh"; printf '#!/bin/bash\n' > "$live"
  CC_DEPLOY_SCRIPT="$live" run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q "▶ bash $live   \[deploy: live layer 1 behind origin/main\]"
}

@test "deploy platter: the SEAM's default is the live ~/.claude/scripts copy" {
  # The seam makes the branch testable; this keeps the production default itself from drifting
  # unnoticed, which a fixtured seam alone cannot see.
  grep -q 'DEPLOY_SCRIPT="\${CC_DEPLOY_SCRIPT:-\$HOME/.claude/scripts/deploy-live.sh}"' "$HOOK"
}

@test "class-B is never itemized; ≤24h deadline appears only as the veto summary line" {
  "$DECIDE" open --class B --what "Imminent default. Detail." \
    --default "proceed" --deadline "2026-07-20T12:00:00Z" >/dev/null
  "$DECIDE" open --class B --what "Far-future default. Detail." \
    --default "proceed" --deadline "2099-01-01T00:00:00Z" >/dev/null
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/13-x-activate.sh"   # ensure the block fires
  CC_OPREADOUT_NOW=1784894400 run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"                  # 2026-07-23T12:00:00Z epoch-ish
  ! echo "$output" | grep -q 'Imminent default' || false
  ! echo "$output" | grep -q 'Far-future default' || false
  echo "$output" | grep -q '1 class-B default(s) auto-fire ≤24h (earliest 2026-07-20T12:00:00Z) — veto: cc-decide veto <id>'
}

# ── composition: cap, counts, header ─────────────────────────────────────────────────────────────

@test "cap: >MAX steps → numbered MAX, footer counts the overflow and the total is in the header" {
  for i in 1 2 3; do printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/2$i-s-activate.sh"; done
  CC_OPREADOUT_MAX=2 CC_OPREADOUT_CLASSBUDGET=on run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q 'OPERATOR ▸ 3 manual step(s)'
  echo "$output" | grep -q ' 2 ▶ '
  ! echo "$output" | grep -q ' 3 ▶ ' || false
  echo "$output" | grep -q '+1 more'
}

# ══════════════════════════════════════════════════════════════════════════════════════════════════
# CLASS BUDGET — OPERATOR_SURFACE_V2 §4 M2 (the row's headline mechanism)
#
# THE DEFECT, measured live 2026-07-29: 55 steps = 1 deploy + 12 activation + 14 decision-C +
# 28 blocked-backlog, rendered through MAX=6 in fixed source order, so the first class-C decision
# sat at position 14 and the first blocked-backlog item past 27 — TWO OF FIVE CLASSES UNREACHABLE
# AT ANY QUEUE DEPTH, with `+49 more` as their only trace. The starved classes were precisely the
# ones needing a human. An alarm that always fires 55 times carries the same zero bits as one that
# cannot fire; a `+N more` footer promises "more of what you just saw".
# ══════════════════════════════════════════════════════════════════════════════════════════════════

mk4() { # the live shape, scaled down: N activations + N class-C decisions + N blocked backlog items.
  # Real producers only (fixture-shape-parity): cc-decide / cc-backlog / the activation-file
  # convention — never hand-rolled JSON, so a producer-side schema change breaks the test, not
  # the fixture silently.
  local n="${1:-6}" i id
  for i in $(seq 1 "$n"); do printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/3$i-a-activate.sh"; done
  for i in $(seq 1 "$n"); do "$DECIDE" open --class C --what "Decision $i. Detail." >/dev/null; done
  for i in $(seq 1 "$n"); do
    id="$("$BACKLOG" add --title "Blocked item $i" --project infra)"
    "$BACKLOG" block "$id" --needs "operator step $i" >/dev/null
  done
}

@test "CLASS BUDGET: at MAX=6 with 6 items in each of 3 classes, NO class is starved" {
  # The acceptance criterion, stated as the read that proves it: every class present in the step set
  # must appear in the render — itemized or as its own counted rollup. Pre-fix, `decision` and
  # `backlog` appeared in neither.
  mk4 6
  CC_OPREADOUT_CLASSBUDGET=on run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'activation' || false
  echo "$output" | grep -q 'decision C' || false
  echo "$output" | grep -q '\[+.* more decision\]' || false
}

@test "CLASS BUDGET: each starved class rolls up with its OWN exact listing command (I5)" {
  mk4 6
  CC_OPREADOUT_CLASSBUDGET=on run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -qF '↳ for f in ~/.claude/autonomy/pending-activation/*.sh; do [ -f "$f.done" ] || echo "$f"; done' || false
  # Was `cc-decide list --open --class C`. The decisions leg now also renders a class-B packet that
  # carries neither a default nor a deadline (a hard block wearing the wrong label — six live
  # `shipland-esc-*` packets are exactly that), so a `--class C` filter would hide precisely the rows
  # an operator followed this pointer to see. The class-budget contract this test pins is unchanged:
  # each starved class still rolls up with its OWN exact listing command — that command just has to
  # reproduce the rows it summarises.
  echo "$output" | grep -qF '↳ cc-decide list --open' || false
}

@test "CLASS BUDGET POSITIVE CONTROL: a class that FITS gets no rollup at all" {
  # Without this, a rollup emitted unconditionally would pass every test above while telling the
  # operator there is more to see when there is not — the invented-blocker failure, and the reason
  # a detector's negative is not data until the positive case is pinned beside it.
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/40-only-activate.sh"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '40-only-activate' || false
  ! echo "$output" | grep -q "↳" || false
  ! echo "$output" | grep -q 'more activation' || false
}

@test "CLASS BUDGET: output is BOUNDED BY CONSTRUCTION at MAX + one rollup per class" {
  # 20 items in each of three classes. The bound is structural, not a magic number: <= MAX itemized
  # plus at most one rollup per class.
  mk4 20
  CC_OPREADOUT_MAX=6 CC_OPREADOUT_CLASSBUDGET=on run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  nlines="$(echo "$output" | grep -cE '^ [0-9]+ (▶|◆|↳)')"
  [ "$nlines" -le 10 ]
  [ "$nlines" -ge 7 ]                       # 6 itemized + >=1 rollup: it did not silently shrink
}

@test "CLASS BUDGET F6: CONFIRM-gated (effect-bearing) activations outrank print-only ones" {
  # Filename order put 18-fleet-activate.sh (12 dark launchd labels) permanently below
  # 04-page-channel-activate.sh and always in the truncated tail. CONFIRM-gating is the free signal.
  printf '#!/bin/bash\necho hi\n'                        > "$CC_ACTIVATION_DIR/04-plain-activate.sh"
  printf '#!/bin/bash\necho hi\n'                        > "$CC_ACTIVATION_DIR/05-plain-activate.sh"
  printf '#!/bin/bash\n[ "${CONFIRM:-0}" = 1 ] || exit 0\n' > "$CC_ACTIVATION_DIR/18-gated-activate.sh"
  CC_OPREADOUT_MAX=1 run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '18-gated-activate' || false
  ! echo "$output" | grep -q ' 1 ▶ .*04-plain' || false
}

@test "CLASS BUDGET kill switch: CC_OPREADOUT_CLASSBUDGET=off restores flat order AND the footer" {
  # I8 — every mechanism ships a switch, and the switch must restore the incumbent, ORDERING
  # INCLUDED. Gating only the allocation left F6's reorder live under `off`; caught by asserting
  # byte-level behaviour rather than "looks the same".
  printf '#!/bin/bash\necho hi\n'                        > "$CC_ACTIVATION_DIR/04-plain-activate.sh"
  printf '#!/bin/bash\n[ "${CONFIRM:-0}" = 1 ] || exit 0\n' > "$CC_ACTIVATION_DIR/18-gated-activate.sh"
  CC_OPREADOUT_CLASSBUDGET=off CC_OPREADOUT_MAX=1 run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q ' 1 ▶ .*04-plain-activate' || false     # glob order, not CONFIRM order
  ! echo "$output" | grep -q "↳" || false                          # no rollups
  echo "$output" | grep -q '+1 more' || false                      # the legacy aggregate footer
}

@test "I11: the deploy platter FALLS BACK to the repo copy when the live script is absent" {
  # ~/.claude/scripts/deploy-live.sh did not exist for the whole window in which
  # com.claude.deploy-live logged 59 `cannot execute: No such file or directory` failures, and both
  # this hook and the board handed it over anyway. A recover command that cannot run is worse than
  # no row: it teaches the operator the board lies.
  w="$(mkrepo_landed i11)"
  ( cd "$w"; echo z > z.txt; git add z.txt; git commit -q -m more; git push -q origin main
    git reset -q --hard HEAD~1 ) >/dev/null 2>&1
  mkdir -p "$w/scripts"; printf '#!/bin/bash\n' > "$w/scripts/deploy-live.sh"
  export CC_SHARED_CHECKOUT="$w"
  CC_DEPLOY_SCRIPT="$BATS_TEST_TMPDIR/absent-deploy.sh" run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -qF "bash $w/scripts/deploy-live.sh" || false
  ! echo "$output" | grep -q 'absent-deploy.sh' || false
}

@test "I11 POSITIVE CONTROL: the live script is used verbatim when it DOES exist" {
  w="$(mkrepo_landed i11b)"
  ( cd "$w"; echo z > z.txt; git add z.txt; git commit -q -m more; git push -q origin main
    git reset -q --hard HEAD~1 ) >/dev/null 2>&1
  export CC_SHARED_CHECKOUT="$w"
  live="$BATS_TEST_TMPDIR/present-deploy.sh"; printf '#!/bin/bash\n' > "$live"
  CC_DEPLOY_SCRIPT="$live" run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -qF "bash $live" || false
}

@test "state line: dirty repo renders 🔧 with the uncommitted-file fact" {
  w="$(mkrepo_landed e)"; echo dirt > "$w/dirt.txt"
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/14-y-activate.sh"
  run "$HOOK" --render --cwd "$w"
  echo "$output" | grep -q '🔧 in progress — 1 file(s) uncommitted'
}

# ── damping ──────────────────────────────────────────────────────────────────────────────────────

@test "damping: unchanged within TTL → abstain (cheap stamp path); after TTL → re-fires; change → immediate" {
  # UPDATED for row 13 M3 (MACHINE_CAPACITY_V2.md §8.5.3), deliberately — not by relaxation.
  # The damp used to hash the RENDERED block, so it suppressed OUTPUT and saved ZERO CPU. A cheap
  # pre-render stamp now abstains BEFORE render_block, which introduces a SECOND abstain reason.
  # This test previously asserted only "latched-ttl"; it now names BOTH paths, which is strictly
  # more precise. The reason string has no consumer outside this file (verified: grep -rn
  # 'latched-ttl' over *.sh/*.bats/*.md and the extensionless bin/ hits only the hook and this test).
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/15-z-activate.sh"
  w="$(mkrepo_landed f)"
  CC_OPREADOUT_NOW=1000000 hookrun "$w" | jq -e '.systemMessage' >/dev/null
  # nothing moved at all ⇒ the CHEAP gate short-circuits before paying for a render
  out2="$(CC_OPREADOUT_NOW=1000100 hookrun "$w")"
  [ -z "$out2" ] || false
  grep -q '"reason":"stamp-unchanged-ttl:100s<900s"' "$CC_IDL" || false
  # after the TTL it must re-assert even though the stamp is STILL unchanged
  out3="$(CC_OPREADOUT_NOW=1001000 hookrun "$w")"
  printf '%s' "$out3" | jq -e '.systemMessage' >/dev/null
  # a NEW step re-renders immediately even inside the TTL window
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/16-new-activate.sh"
  out4="$(CC_OPREADOUT_NOW=1001010 hookrun "$w")"
  printf '%s' "$out4" | jq -r '.systemMessage' | grep -q '16-new-activate'
}

@test "M3: stamp MOVED but content identical → render is paid, then latched-ttl, and the TTL is NOT extended" {
  # The subtle correctness case. When the stamp moves the cheap gate cannot short-circuit, the
  # render is paid, and the CONTENT hash then decides. Two things must hold:
  #   (a) the abstain is the CONTENT path (latched-ttl), not the stamp path;
  #   (b) the stored timestamp keeps its ORIGINAL value — if a no-op render refreshed the ts, a
  #       never-changing block could suppress its own 15-min re-assert indefinitely just by being
  #       touched, which is a silent loss of the operator's re-assert guarantee.
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/15-z-activate.sh"
  w="$(mkrepo_landed f)"
  CC_OPREADOUT_NOW=1000000 hookrun "$w" | jq -e '.systemMessage' >/dev/null
  latch="$(ls "$CC_OPREADOUT_STATE_DIR"/*.last | head -1)"
  read -r h0 ts0 st0 < "$latch"
  [ "$ts0" = "1000000" ] || false
  [ -n "$st0" ] || false                        # 3-field latch is the new format
  # Move the stamp WITHOUT changing the block: the backlog file's mtime is in the stamp, and an
  # empty backlog renders no line either way.
  #
  # `touch -t <explicit>`, never a bare `touch` — a REPRODUCIBLE 1-in-3 flake, diagnosed 2026-07-29
  # rather than dismissed. `cheap_stamp` reads `stat -f %m`, which has ONE-SECOND granularity, so
  # when the harness is fast enough that the first render and this touch land in the same second the
  # stamp does NOT move, the cheap gate short-circuits, and the abstain reason is
  # `stamp-unchanged-ttl` instead of `latched-ttl`. The test then fails for a timing reason while the
  # behaviour under test is correct. A wall-clock-derived fixture value is not determinism.
  touch -t 202601010000 "$CC_BACKLOG_FILE"
  out="$(CC_OPREADOUT_NOW=1000200 hookrun "$w")"
  [ -z "$out" ] || false
  grep -q '"reason":"latched-ttl:200s<900s"' "$CC_IDL" || false
  read -r h1 ts1 st1 < "$latch"
  [ "$h1" = "$h0" ] || false                    # content genuinely unchanged
  [ "$ts1" = "1000000" ] || false               # (b) ts preserved, NOT bumped to 1000200
  [ "$st1" != "$st0" ] || false                 # (a) new stamp persisted ⇒ next turn is cheap
}

@test "M3: a PRE-M3 two-field latch is never mistaken for a match — it re-renders and upgrades the format" {
  # Backward-compat. Latches already on disk carry "<hash> <ts>" with no stamp field. An ABSENT
  # field must never read as equality, or the first turn after the upgrade would be suppressed.
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/15-z-activate.sh"
  w="$(mkrepo_landed f)"
  CC_OPREADOUT_NOW=1000000 hookrun "$w" | jq -e '.systemMessage' >/dev/null
  latch="$(ls "$CC_OPREADOUT_STATE_DIR"/*.last | head -1)"
  read -r h0 _ts0 _st0 < "$latch"
  printf '%s %s\n' "$h0" 1000000 > "$latch"      # downgrade to the pre-M3 format
  out="$(CC_OPREADOUT_NOW=1000100 hookrun "$w")"
  [ -z "$out" ] || false
  # content is unchanged so it still abstains — but via the CONTENT path, which proves the render ran
  grep -q '"reason":"latched-ttl:100s<900s"' "$CC_IDL" || false
  read -r _h1 _ts1 st1 < "$latch"
  [ -n "$st1" ] || false                         # format upgraded to 3 fields
}

@test "M3: CC_READOUT_DAMP=off bypasses the cheap gate (kill switch restores the old cost path)" {
  # NON-VACUITY GUARD. Caught by the RED-proof: asserting only "no stamp reason appears when the
  # switch is off" passes trivially against the PRE-M3 hook, which has no stamp path at all — the
  # test would have gone green while proving nothing about the switch. So assert BOTH directions:
  # the stamp path must be OBSERVED with the switch on, and then absent with it off.
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/15-z-activate.sh"
  w="$(mkrepo_landed f)"
  CC_OPREADOUT_NOW=1000000 hookrun "$w" | jq -e '.systemMessage' >/dev/null

  # (1) switch ON (default): the cheap stamp path must actually fire
  : > "$CC_IDL"
  out_on="$(CC_OPREADOUT_NOW=1000100 hookrun "$w")"
  [ -z "$out_on" ] || false
  grep -q '"reason":"stamp-unchanged-ttl:100s<900s"' "$CC_IDL" || false

  # (2) switch OFF: same state, but the abstain must now come from the CONTENT latch
  : > "$CC_IDL"
  out_off="$(CC_OPREADOUT_NOW=1000200 CC_READOUT_DAMP=off hookrun "$w")"
  [ -z "$out_off" ] || false
  grep -q '"reason":"latched-ttl:200s<900s"' "$CC_IDL" || false
  ! grep -q 'stamp-unchanged-ttl' "$CC_IDL" || false
}

@test "M3: POSITIVE CONTROL — the cheap gate cannot suppress a genuinely new manual step" {
  # The one failure mode that would matter operationally: a pre-render gate abstaining while a real
  # operator step is pending. The stamp includes the activation dir's mtime precisely so that cannot
  # happen — this asserts the detector FIRES rather than trusting the reasoning.
  w="$(mkrepo_landed f)"
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/15-z-activate.sh"
  CC_OPREADOUT_NOW=1000000 hookrun "$w" | jq -e '.systemMessage' >/dev/null
  out2="$(CC_OPREADOUT_NOW=1000050 hookrun "$w")"
  [ -z "$out2" ] || false                        # damped, as expected
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/17-urgent-activate.sh"
  out3="$(CC_OPREADOUT_NOW=1000060 hookrun "$w")"
  printf '%s' "$out3" | jq -r '.systemMessage' | grep -q '17-urgent-activate' || false
}

# ── guards ───────────────────────────────────────────────────────────────────────────────────────

@test "kill-switch CC_OPREADOUT_DISABLE=1 → silent abstain" {
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/17-k-activate.sh"
  out="$(printf '{"session_id":"k","cwd":""}' | CC_OPREADOUT_DISABLE=1 "$HOOK")"
  [ -z "$out" ]
  grep -q '"reason":"disabled"' "$CC_IDL"
}

@test "compose-guard: armed continue sentinel → abstain continue-armed (session-continue owns the turn)" {
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/18-c-activate.sh"
  w="$(mkrepo_landed g)"
  sent="$BATS_TEST_TMPDIR/armed-sentinel"; : > "$sent"
  out="$(printf '{"session_id":"cg","cwd":"%s"}' "$w" | CC_CONTINUE_SENTINEL="$sent" "$HOOK")"
  [ -z "$out" ]
  grep -q '"reason":"continue-armed"' "$CC_IDL"
}

@test "malformed decision JSON is skipped, never crashes the render (fail-open per file)" {
  printf 'NOT JSON{{{' > "$CC_DECISIONS_DIR/broken.json"
  "$DECIDE" open --class C --what "Still renders. Yes." >/dev/null
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Still renders'
}

@test "--render with nothing pending prints the explicit none-line (pull surface never silent)" {
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$output" = "OPERATOR ▸ no manual steps pending." ]
}

# ── open-queue visibility (operator crux 2026-07-25: a full auto-drain queue was invisible) ──

@test "queue-only: OPEN backlog items for the cwd project fire the render as the governing line" {
  w="$(mkrepo_landed q1)"
  "$BACKLOG" add --title "narrated follow-on pass" --project "$(basename "$w")" >/dev/null
  run hookrun "$w"
  [ "$status" -eq 0 ]
  msg="$(printf '%s' "$output" | jq -r '.systemMessage')"
  printf '%s' "$msg" | grep -q "OPERATOR ▸ queue: 1 open ($(basename "$w"))"
  printf '%s' "$msg" | grep -q "cc-dispatch auto-drains"
  # The per-project listing command was DROPPED from this line (2026-07-31): at ~140 chars the
  # footer wrapped to a second terminal row, and this token was the longest on it. The rollup-
  # carries-a-command invariant still holds — `board: cc-blockers` reaches the same items and is
  # already on the line. Pinned so a future re-add is a deliberate act, not a regression.
  ! printf '%s' "$msg" | grep -q -- "--project $(basename "$w")" || false
  grep -q '"queue_open":1' "$CC_IDL"
}

@test "queue rides the FOOTER when manual steps exist (steps stay the governing line)" {
  w="$(mkrepo_landed q2)"
  printf '#!/bin/bash\necho hi\n' > "$CC_ACTIVATION_DIR/30-q-activate.sh"
  "$BACKLOG" add --title "queued item" --project "$(basename "$w")" >/dev/null
  run hookrun "$w"
  msg="$(printf '%s' "$output" | jq -r '.systemMessage')"
  # The governing line states the IDEA (what is runnable), not the category+count. Minto Ch 7 p. 94:
  # "There are three problems" tells the kind, not the idea — `1 manual step(s)` was exactly that.
  printf '%s' "$msg" | head -1 | grep -q '1 runnable now'
  ! printf '%s' "$msg" | head -1 | grep -q 'manual step(s)' || false
  printf '%s' "$msg" | grep -q 'queue: 1 open'
}

@test "governing line PARTITIONS runnable vs judgment — the summary of the level below" {
  # Minto's first pyramid rule: an idea at any level must SUMMARISE the ideas grouped below it.
  # Below this line sit exactly two groupings — what cc-do can clear, and what needs a human — so
  # the honest summary is that partition, not a total that conflates them.
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/80-p-activate.sh"
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/81-p-activate.sh"
  _legacy_pkt shipland-esc-part1
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | head -1 | grep -q '2 runnable now, 1 need your call' || false
  ! echo "$output" | head -1 | grep -q '3 manual step(s)' || false
}

@test "governing line degrades honestly when a side is EMPTY (no '0 runnable now')" {
  # A partition that prints a zero leg is worse than the label it replaced — it asserts an idea
  # about a grouping that does not exist.
  _legacy_pkt shipland-esc-only1
  _legacy_pkt shipland-esc-only2
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | head -1 | grep -q '2 need your call' || false
  ! echo "$output" | head -1 | grep -q 'runnable' || false
}

@test "queue counts ONLY status==open of the cwd project: claimed, blocked and other-project items excluded" {
  w="$(mkrepo_landed q3)"
  local p; p="$(basename "$w")"
  id1="$("$BACKLOG" add --title "claimed one" --project "$p")"; "$BACKLOG" claim "$id1" --by tq3 >/dev/null
  id2="$("$BACKLOG" add --title "blocked one" --project "$p")"; "$BACKLOG" block "$id2" --needs "operator: key" >/dev/null
  "$BACKLOG" add --title "other project" --project elsewhere >/dev/null
  run hookrun "$w"
  msg="$(printf '%s' "$output" | jq -r '.systemMessage')"
  # the blocked item still renders as its ◆ step; NO queue line (0 open for this project)
  printf '%s' "$msg" | grep -q 'blocked one'
  ! printf '%s' "$msg" | grep -q 'queue:'
}

@test "pull-surface parity: --render shows the same queue line (one renderer)" {
  w="$(mkrepo_landed q4)"
  "$BACKLOG" add --title "parity item" --project "$(basename "$w")" >/dev/null
  run "$HOOK" --render --cwd "$w"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "queue: 1 open ($(basename "$w"))"
}

# ══════════════════════════════════════════════════════════════════════════════════════════════════
# `yours` — the steps THIS session filed (cc-backlog needs → .session / .run)
#
# THE DEFECT: a step the agent discovered THIS turn ("authenticate motion-plus in /mcp") lands as a
# blocked backlog item, and therefore folded into the standing `◆ 180 blocked backlog — your call`
# count — indistinguishable from 180 items the operator has been ignoring for weeks. The `👤` rung
# says "N step(s) need you; see the OPERATOR block", so line 1 pointed at a block that could not
# answer the question line 1 had just raised.
#
# STUBBED cc-backlog throughout (CC_BACKLOG_BIN): `needs`, `.session` and `.run` are landing on the
# real binary in a sibling change, and a suite that depended on it would be a function of that
# half-finished state rather than of this renderer. The seam under test is exactly the emission
# shape of `cc-backlog list --blocked --json`, which is what the stub pins.
# ══════════════════════════════════════════════════════════════════════════════════════════════════

_stub_backlog() {  # $1 = the JSON array `list --blocked --json` must emit
  printf '%s\n' "$1" > "$BATS_TEST_TMPDIR/blocked.json"
  export STUB_BLOCKED="$BATS_TEST_TMPDIR/blocked.json"
  cat > "$BATS_TEST_TMPDIR/cc-backlog-stub" <<'EOS'
#!/bin/bash
# only two reads exist in the renderer: the blocked fold and the open-queue count.
case "$*" in
  *--blocked*) cat "$STUB_BLOCKED" ;;
  *)           printf '[]\n' ;;
esac
EOS
  chmod +x "$BATS_TEST_TMPDIR/cc-backlog-stub"
  export CC_BACKLOG_BIN="$BATS_TEST_TMPDIR/cc-backlog-stub"
}

_blocked_item() { # $1=id $2=title $3=needs $4=run("" for none) $5=session("" for none)
  jq -nc --arg id "$1" --arg t "$2" --arg n "$3" --arg r "$4" --arg s "$5" \
    '{id:$id, title:$t, needs:$n, status:"blocked"}
     + (if $r != "" then {run:$r} else {} end)
     + (if $s != "" then {session:$s} else {} end)'
}

hookrun_sid() { # $1=session_id $2=cwd
  printf '{"session_id":"%s","cwd":"%s"}' "$1" "${2:-}" | "$HOOK"
}

@test "YOURS: a step this session filed WITH .run is itemized ▶ with its exact command, FIRST" {
  # The whole point: it must not be reachable only by following a count. The command is on the
  # board, above everything the operator has been ignoring for weeks.
  _stub_backlog "[ $(_blocked_item y-1 "Authenticate motion-plus" "operator must authenticate" "claude --mcp auth motion-plus" S1),
                   $(_blocked_item b-1 "Rotate the API key" "operator must mint the key" "" ""),
                   $(_blocked_item b-2 "Approve the vendor SOW" "operator must sign" "" "") ]"
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/70-y-activate.sh"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR" --sid S1
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '▶ claude --mcp auth motion-plus   \[this session y-1: Authenticate motion-plus\]' || false
  # FIRST: immediately under the governing line, above the runnable and judgment classes.
  [ "$(echo "$output" | grep -n 'this session y-1' | head -1 | cut -d: -f1)" -eq 2 ]
  echo "$output" | head -1 | grep -q '1 step(s) are yours' || false
}

@test "YOURS: a session-filed step with NO .run is itemized ◆ — the file's existing judgment mark" {
  # `▶`/`◆` are the file's vocabulary and `▸` is the header's own glyph; no new mark is minted.
  _stub_backlog "[ $(_blocked_item y-2 "Restart Cursor" "operator must restart Cursor to reload the extension" "" S1) ]"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR" --sid S1
  echo "$output" | grep -q '◆ \[this session y-2\] Restart Cursor — needs: operator must restart Cursor' || false
  ! echo "$output" | grep -q '▶' || false
  ! echo "$output" | grep -q '▸ .*y-2' || false
}

@test "YOURS DOUBLE-COUNT GUARD: an item counted in yours is SUBTRACTED from the backlog count" {
  # THE most likely way to get this wrong. 3 blocked items, 1 filed by this session ⇒ the operator
  # must see 1 itemized + a count of 2, never 1 itemized + a count of 3 (a phantom extra item that
  # exists nowhere on disk). The exclusion is structural — the class is decided once, in the jq
  # that reads the single `list --blocked --json` stream — and this pins it from the outside.
  _stub_backlog "[ $(_blocked_item y-9 "Authenticate motion-plus" "operator must authenticate" "" S1),
                   $(_blocked_item b-8 "Rotate the API key" "operator must mint the key" "" ""),
                   $(_blocked_item b-9 "Approve the vendor SOW" "operator must sign" "" "") ]"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR" --sid S1
  echo "$output" | grep -q '◆ \[this session y-9\] Authenticate motion-plus' || false
  echo "$output" | grep -q '◆ 2 blocked backlog — your call' || false
  ! echo "$output" | grep -q '3 blocked backlog' || false
  # and it appears EXACTLY once in the whole block — not itemized here and counted there
  [ "$(echo "$output" | grep -c 'y-9')" -eq 1 ]
  echo "$output" | head -1 | grep -q '1 step(s) are yours · 2 need your call' || false
}

@test "YOURS: items filed by a DIFFERENT session are NOT yours — render is byte-identical to no-sid" {
  # The standing pile belongs to whoever filed it. A session must never adopt another's steps.
  _stub_backlog "[ $(_blocked_item o-1 "Someone else's step" "operator must do it" "run-this" OTHER),
                   $(_blocked_item b-7 "Rotate the API key" "operator must mint the key" "" "") ]"
  mine="$("$HOOK" --render --cwd "$BATS_TEST_TMPDIR" --sid S1)"
  none="$("$HOOK" --render --cwd "$BATS_TEST_TMPDIR")"
  [ "$mine" = "$none" ]
  ! printf '%s' "$mine" | grep -q 'this session' || false
  ! printf '%s' "$mine" | grep -q 'are yours' || false
  printf '%s' "$mine" | grep -q '◆ 2 blocked backlog — your call' || false
}

@test "YOURS: no session id on stdin ⇒ yours EMPTY and the block is the unchanged render" {
  # A missing session id must never promote the standing pile into `yours` — the failure mode where
  # every blocked item on the machine suddenly reads as "you just saw this happen".
  w="$(mkrepo_landed ys)"
  _stub_backlog "[ $(_blocked_item y-5 "Authenticate motion-plus" "operator must authenticate" "" S1),
                   $(_blocked_item b-5 "Rotate the API key" "operator must mint the key" "" "") ]"
  msg="$(printf '{"cwd":"%s"}' "$w" | "$HOOK" | jq -r '.systemMessage')"
  ref="$("$HOOK" --render --cwd "$w")"
  [ "$msg" = "$ref" ]
  ! printf '%s' "$msg" | grep -q 'are yours' || false
  printf '%s' "$msg" | grep -q '◆ 2 blocked backlog — your call' || false
}

@test "YOURS fires the block alone: session-filed step + every other class empty + ✅ git" {
  # The fire predicate extension. Without it the `👤` rung's "see the OPERATOR block" would point at
  # a block that never rendered, because a clean landed repo with no standing steps is silent.
  w="$(mkrepo_landed yf)"
  _stub_backlog "[ $(_blocked_item y-6 "Authenticate motion-plus" "operator must authenticate" "claude --mcp auth motion-plus" S6) ]"
  out="$(hookrun_sid S6 "$w")"
  [ -n "$out" ]
  msg="$(printf '%s' "$out" | jq -r '.systemMessage')"
  printf '%s' "$msg" | head -1 | grep -q 'OPERATOR ▸ 1 step(s) are yours · ✅ live on trunk' || false
  printf '%s' "$msg" | grep -q '▶ claude --mcp auth motion-plus   \[this session y-6' || false
  # control: the SAME repo with no session-filed step is silent, so the fire came from `yours`
  : > "$STUB_BLOCKED"; printf '[]\n' > "$STUB_BLOCKED"
  export CC_OPREADOUT_STATE_DIR="$BATS_TEST_TMPDIR/state2"
  [ -z "$(hookrun_sid S6 "$w")" ]
}

@test "YOURS is exempt from the COLLAPSE: itemized while the standing classes stay counted" {
  # The one place the volume rule yields. These are the steps from the work the operator just
  # watched happen; the rest is the pile.
  _stub_backlog "[ $(_blocked_item y-7 "Authenticate motion-plus" "operator must authenticate" "claude --mcp auth motion-plus" S1),
                   $(_blocked_item b-1 "one" "operator" "" ""), $(_blocked_item b-2 "two" "operator" "" ""),
                   $(_blocked_item b-3 "three" "operator" "" ""), $(_blocked_item b-4 "four" "operator" "" ""),
                   $(_blocked_item b-5 "five" "operator" "" "") ]"
  for i in 1 2 3 4; do printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/7$i-c-activate.sh"; done
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR" --sid S1
  echo "$output" | grep -q '▶ claude --mcp auth motion-plus   \[this session y-7' || false   # itemized
  echo "$output" | grep -q '▶ cc-do   \[4 runnable\]' || false                               # collapsed
  echo "$output" | grep -q '◆ 5 blocked backlog — your call   cc-backlog list --blocked' || false
  echo "$output" | head -1 | grep -q '1 step(s) are yours · 4 runnable now, 5 need your call' || false
}

@test "YOURS is exempt from MAX: 4 session steps all itemize at MAX=1" {
  # MAX bounds the STANDING itemisation. A session's own steps are few by construction and are the
  # entire reason the 👤 rung exists, so the budget does not reach them.
  _stub_backlog "[ $(_blocked_item y-a "step a" "operator a" "cmd-a" S1), $(_blocked_item y-b "step b" "operator b" "cmd-b" S1),
                   $(_blocked_item y-c "step c" "operator c" "cmd-c" S1), $(_blocked_item y-d "step d" "operator d" "cmd-d" S1) ]"
  CC_OPREADOUT_MAX=1 run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR" --sid S1
  for id in y-a y-b y-c y-d; do echo "$output" | grep -q "this session $id" || false; done
  ! echo "$output" | grep -q 'more yours' || false
}

@test "YOURS rollup: 6 session steps → 5 itemized + ONE ↳ carrying cc-backlog list --blocked" {
  # Bounded anyway: above YMAX the tail becomes the standard class-rollup, so the completeness
  # guarantee (I10 — a class can be shortened, never deleted) holds here like everywhere else.
  items=""
  for i in 1 2 3 4 5 6; do
    items="${items:+$items,} $(_blocked_item "y-r$i" "step $i" "operator $i" "cmd-$i" S1)"
  done
  _stub_backlog "[ $items ]"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR" --sid S1
  [ "$(echo "$output" | grep -c 'this session y-r')" -eq 5 ]
  echo "$output" | grep -q '↳ cc-backlog list --blocked   \[+1 more yours\]' || false
  echo "$output" | head -1 | grep -q '6 step(s) are yours' || false
  # the rollup names the class it summarises, and the 6th item is NOT silently dropped
  [ "$(echo "$output" | grep -c '↳')" -eq 1 ]
}

@test "YOURS under CC_OPREADOUT_CLASSBUDGET=on: numbered like its neighbours, still first + exempt" {
  # The numbering follows the surrounding MODE (bare under collapse, numbered under itemisation) so
  # the downstream `^ [0-9]+ (▶|◆)` step count keeps counting whatever that mode counts.
  _stub_backlog "[ $(_blocked_item y-8 "Authenticate motion-plus" "operator must authenticate" "cmd-8" S1),
                   $(_blocked_item b-6 "Rotate the API key" "operator must mint the key" "" "") ]"
  CC_OPREADOUT_CLASSBUDGET=on run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR" --sid S1
  echo "$output" | grep -q ' 1 ▶ cmd-8   \[this session y-8: Authenticate motion-plus\]' || false
  echo "$output" | grep -q ' 2 ◆ \[backlog b-6\] Rotate the API key' || false
  echo "$output" | head -1 | grep -q 'OPERATOR ▸ 1 step(s) are yours · 2 manual step(s)' || false
}

@test "YOURS: hook mode takes the session id from stdin (the live path), not only --sid" {
  # --sid is the pull surface's seam; the Stop hook's own SID comes from the harness JSON. Both must
  # reach the same renderer or push and pull drift — the defect one-renderer exists to prevent.
  w="$(mkrepo_landed yh)"
  _stub_backlog "[ $(_blocked_item y-h "Authenticate motion-plus" "operator must authenticate" "cmd-h" live-sid-123) ]"
  msg="$(hookrun_sid live-sid-123 "$w" | jq -r '.systemMessage')"
  printf '%s' "$msg" | grep -q '▶ cmd-h   \[this session y-h' || false
  ref="$("$HOOK" --render --cwd "$w" --sid live-sid-123)"
  [ "$msg" = "$ref" ]
}
