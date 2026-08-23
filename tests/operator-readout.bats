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
  # Project labels in this suite are FIXTURES, not projects — and `cc-backlog add` now WARNS on an
  # explicit --project outside the dispatch set (df2b6a40a5dc), which bats folds into $output. Off
  # here because dispatchability is not this suite's subject; tests/cc-backlog-project-dispatch.bats
  # owns it, unfixtured, in both directions.
  export CC_BACKLOG_PROJECT_WARN=off
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
  # per-test fold-cache dir: the cache keys on (mtime,size,path) of the store, and fixture
  # stores are REWRITTEN (not appended) — same-second same-size rewrites would alias across
  # tests through the global default dir. Isolation per test removes the class.
  export CC_ORB_BLG_CACHE_DIR="$BATS_TEST_TMPDIR/blg-cache"
  export WRAP_LEDGER_BIN="$REPO/scripts/wrap-ledger.sh"
  export WRAP_TRUNK="origin/main"
  # point the shared checkout at an EMPTY fixture by default → no deploy-lag step
  export CC_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/no-such-checkout"
  export CC_OPREADOUT_NOW=1000000
  export CC_OPREADOUT_TTL_S=900
  # `cc-backlog add` ends in dispatch_kick(), which backgrounds a real `cc-dispatch --decide`. This
  # file fixtures CC_BACKLOG_FILE but not $HOME, so unpinned the kick resolved the operator's LIVE
  # marker and LIVE ~/.claude/bin/cc-dispatch — measured at 2 spawns per run of this suite. Because
  # CC_DISPATCH_IDL is unset here, that dispatcher then journals decisions about a TEMP TEST backlog
  # into the operator's PRODUCTION idl.jsonl. Same seam that reddened tests/cc-dispatch.bats case (b);
  # all three legs pinned for the reason given there.
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/.dispatch-kick"
  export CC_BACKLOG_KICK_BIN="$BATS_TEST_TMPDIR/no-such-dispatch"
  # ⚠️ The escalation dead-letter stores (D3's `◆ N escalation record(s) unseen` line) MUST be
  # redirected here. Unexported they fall back to their $HOME defaults, i.e. the OPERATOR's live
  # ~/.claude — measured 2026-08-07, that injected a real 47-record line into the rendered block and
  # reddened 2 byte-identity tests that had nothing to do with escalations. Same class as the
  # autonomy-sweep suite's reaper-dir note: an unseamed default turns a hermetic suite into an
  # assertion about the machine it happens to run on.
  export CC_HANDOFF_ALARM_DIR="$BATS_TEST_TMPDIR/handoff-alarms"
  export CC_ANNOUNCE_ALARM_DIR="$BATS_TEST_TMPDIR/announce-alarms"
  export CC_COMPLETION_RECORDS_DIR="$BATS_TEST_TMPDIR/completion-push"
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages"
  # The FIFTH store (R-6) rides the SAME hazard, and by a nastier route: its seam is the WRITER's
  # mailbox variable, so an unexported CC_MAILBOX_DIR points the count at the operator's live
  # ~/.claude/mailbox/dead-letter exactly as the four above once pointed at their live stores.
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"
  export CC_SWEEP_SEEN_DIR="$BATS_TEST_TMPDIR/sweep-seen"
  mkdir -p "$CC_ACTIVATION_DIR" "$CC_DECISIONS_DIR" "$CC_HANDOFF_ALARM_DIR" \
           "$CC_ANNOUNCE_ALARM_DIR" "$CC_COMPLETION_RECORDS_DIR" "$CC_PAGES_DIR" \
           "$CC_MAILBOX_DIR/dead-letter" "$CC_SWEEP_SEEN_DIR"
  : > "$CC_BACKLOG_FILE"
}

# ── D3: the escalation counted line ──────────────────────────────────────────────────────────────
mk_escalation() { # <n> — one undrained handoff-alarm record
  printf '{"kind":"handoff-alarm","class":"strand-risk","detail":"pane never closed","ts":"x"}\n' \
    > "$CC_HANDOFF_ALARM_DIR/alarm-$1.json"
}
mk_escalation_seen() { # <n> — …and the sweep's REAL marker for it (sha256 of the FULL path)
  : > "$CC_SWEEP_SEEN_DIR/$(printf '%s' "$CC_HANDOFF_ALARM_DIR/alarm-$1.json" | shasum -a 256 | cut -c1-32)"
}
mk_deadletter() { # <sid> — one M3 close-path dead letter, in handoff-fire's own shape
  printf '## from desk\nthe seam ruling you asked for\n' > "$CC_MAILBOX_DIR/dead-letter/$1.md"
}
mk_deadletter_ran() { # <sid> — the store's EXISTENCE EVIDENCE, deliberately not a record (R4)
  printf '2026-08-13T00:00:00Z terminal-close sid=%s pending=2\n' "$1" \
    >> "$CC_MAILBOX_DIR/dead-letter/.ran"
}

hookrun() { # $1=cwd → run hook mode with stdin JSON; stdout in $output
  printf '{"session_id":"t-%s","cwd":"%s"}' "$BATS_TEST_NUMBER" "${1:-}" | "$HOOK"
}

# ── EXPECT A PATH THE WAY THE RENDERER PRINTS IT, NOT THE WAY THE FIXTURE SPELLS IT ───────────────
# The deploy platter prints through the hook's own `tildify` (hooks/operator-readout.sh:255 —
# `${1/#$HOME/~}`), so an assertion naming an ABSOLUTE fixture path is only correct while the
# fixture happens to live OUTSIDE $HOME. At this desk it does — $TMPDIR is /var/folders/… — so five
# deploy-platter assertions read as sound for as long as anyone ran them here. Under
# scripts/offbox-run.sh (and any harness handing a suite a fresh HOME with TMPDIR inside it)
# BATS_TEST_TMPDIR IS under $HOME, the platter renders `~/tmp/bats-run-…/present-deploy.sh`, and the
# four POSITIVE ones went red for the RENDERING rather than the routing they exist to test.
#
# 🚨 The fifth was worse and was NOT red: the `! grep -qF "▶ bash $live"` control at the held-lane
# case passed off-box *because nothing could ever match it* — a neutered assertion, not an absent
# one, and the only arm stopping "refusing lanes are held" from being satisfied by holding every
# lane. Routing it through here is what makes it able to fail again.
#
# Mirrored rather than extracted: the transform is one parameter expansion, and the suite already
# pins it END-TO-END in "deploy platter: the SEAM's default is the live ~/.claude/scripts copy",
# which asserts the rendered `~/.claude/…` form directly. That case is the contract; this is only
# how the fixture-path cases spell what it already guarantees.
tild() { printf '%s' "${1/#$HOME/~}"; }

# clean repo, HEAD == origin/main (landed → ✅-shaped git state)
mkrepo_landed() {
  local o="$BATS_TEST_TMPDIR/o-$1.git" w="$BATS_TEST_TMPDIR/w-$1"
  git init -q --bare "$o"; git clone -q "$o" "$w"
  ( cd "$w" || exit 1; git config user.email t@e.com; git config user.name t; git checkout -q -b main
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
  echo "$output" | grep -q "▶ bash $(tild "$live")   \[deploy: live layer 1 behind origin/main\]"
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
  echo "$output" | grep -qF "bash $(tild "$w/scripts/deploy-live.sh")" || false
  ! echo "$output" | grep -q 'absent-deploy.sh' || false
}

@test "I11 POSITIVE CONTROL: the live script is used verbatim when it DOES exist" {
  w="$(mkrepo_landed i11b)"
  ( cd "$w"; echo z > z.txt; git add z.txt; git commit -q -m more; git push -q origin main
    git reset -q --hard HEAD~1 ) >/dev/null 2>&1
  export CC_SHARED_CHECKOUT="$w"
  live="$BATS_TEST_TMPDIR/present-deploy.sh"; printf '#!/bin/bash\n' > "$live"
  CC_DEPLOY_SCRIPT="$live" run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -qF "bash $(tild "$live")" || false
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
  # Production invariant, mirrored: the fold is a pure function of the append-only store — any
  # status change APPENDS to backlog.jsonl. The blg cache keys on the store's (mtime,size), so a
  # stub whose OUTPUT changes while the store stands still is a state production cannot reach;
  # append a byte here so every stub change is a store change, exactly as in the real ledger.
  printf '\n' >> "$CC_BACKLOG_FILE"
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
  _stub_backlog "[]"       # through the helper, so the store-append invariant holds (blg cache)
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

# ── ✎ A VALUE IS MISSING (2026-08-22 operator incident) ───────────────────────────────────────────
# THE DEFECT: a close plattered `aws sns subscribe … --notification-endpoint <your-address>` under a
# run marker. `▶` is a PROMISE — "paste this" — and a template breaks it in the one place the
# operator trusts. completion-assert D5 catches the MODEL's prose, but only at Stop, i.e. after they
# have already read it. The rows THIS hook renders from disk it can refuse to platter, which is the
# only half of this defect that is prevention rather than apology.
@test "PLACEHOLDER: a stored run command with a hole in it renders ✎ SUPPLY, never ▶" {
  _stub_backlog "[ $(_blocked_item ph-1 "Subscribe the alerts inbox" \
      "the email address the bridge alarms should go to" \
      "aws sns subscribe --topic-arn arn:x --protocol email --notification-endpoint <your-address>" S1) ]"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR" --sid S1
  [ "$status" -eq 0 ]
  # NAMES the missing value, and says what it IS — the filer's own prose, the only party who knows
  echo "$output" | grep -q '✎ SUPPLY <your-address> — the email address the bridge alarms should go to   \[this session ph-1\]' || false
  # the mark it must NOT get, and the command it must NOT hand over: there is nothing here to select
  ! echo "$output" | grep -q '▶' || false
  ! echo "$output" | grep -q 'aws sns subscribe' || false
}

@test "PLACEHOLDER: the two conventional literals convict too (YOUR_ / PASTE_)" {
  _stub_backlog "[ $(_blocked_item ph-2 "Set the key" "operator must mint it" "aws configure set key YOUR_KEY_ID" S1),
                   $(_blocked_item ph-3 "Post the token" "operator must copy it" "curl -H tok:PASTE_TOKEN_HERE x" S1) ]"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR" --sid S1
  echo "$output" | grep -q '✎ SUPPLY YOUR_KEY_ID' || false
  echo "$output" | grep -q '✎ SUPPLY PASTE_TOKEN_HERE' || false
}

@test "PLACEHOLDER: a shell-RESOLVED token is not a placeholder — the row stays ▶" {
  # \$VAR / ~ / \$(cmd) are resolved by the shell on paste, so a line carrying them is genuinely
  # runnable. The regression this guards is the tempting one: widening the shape until the board
  # convicts itself and every ▶ becomes a ✎.
  _stub_backlog "[ $(_blocked_item ph-4 "Load the dispatcher" "operator must load it" \
      'launchctl load ~/L/$USER-dispatcher.plist' S1) ]"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR" --sid S1
  echo "$output" | grep -q '▶ launchctl load ~/L/\$USER-dispatcher.plist' || false
  ! echo "$output" | grep -q '✎' || false
}

@test "PLACEHOLDER: a hole inside a TRAILING # COMMENT does not convict a runnable command" {
  # MEASURED, not hypothetical: of the 71 live blocked rows carrying a `run`, exactly one matches the
  # shape — 6484a07b7221, ending `… exit \$_rc   # last attempt: rc=143 (SIGTERM), head pinned at
  # <unrecorded>`. That command runs perfectly. Convicting it would put a "supply a value" row on the
  # board for a value nobody needs — the board lying, which is how it teaches the operator to skim.
  _stub_backlog "[ $(_blocked_item ph-5 "Retry the land" "operator must retry it" \
      'bash ship-land.sh; exit $_rc   # last attempt: rc=143, head pinned at <unrecorded>' S1) ]"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR" --sid S1
  echo "$output" | grep -q '▶ bash ship-land.sh' || false
  ! echo "$output" | grep -q '✎' || false
}

@test "PLACEHOLDER: a decision packet's run_command is held to the same rule" {
  # The decision leg has its own ▶ arm; a fix covering only the backlog leg would leave the same
  # unpasteable line reachable by another route.
  cat > "$CC_DECISIONS_DIR/dph.json" <<'EOJ'
{"id":"dph1234","class":"C","status":"open","created":"2026-08-22T00:00:00Z",
 "what_plain":"Subscribe the alerts inbox to the topic. Tail.",
 "run_command":"aws sns subscribe --notification-endpoint <your-address>"}
EOJ
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '✎ SUPPLY <your-address> — Subscribe the alerts inbox to the topic' || false
  ! echo "$output" | grep -q 'aws sns subscribe' || false
}

@test "PLACEHOLDER COLOUR: ✎ carries SGR, ▶ rows stay byte-identical (paste-safety not traded)" {
  # MEASURED (docs/research/tui-systemmessage-render-2026-08-22.md): a Stop systemMessage renders in
  # the TUI's own grey, an ESC we emit survives verbatim to the terminal, and markdown does NOT
  # render — so ANSI is the only colour lever in this block, and it is the operator's ask ("so I can
  # see it and not gloss over it"). THE CONSTRAINT: a runnable line must not change one byte for it.
  _stub_backlog "[ $(_blocked_item pc-1 "Subscribe" "the address alarms go to" \
      "aws sns subscribe --notification-endpoint <your-address>" S1),
                   $(_blocked_item pc-2 "Load it" "operator must load it" "launchctl load ~/x.plist" S1) ]"
  plain="$(CC_OPREADOUT_COLOR=0 "$HOOK" --render --cwd "$BATS_TEST_TMPDIR" --sid S1)"
  lit="$(CC_OPREADOUT_COLOR=1 "$HOOK" --render --cwd "$BATS_TEST_TMPDIR" --sid S1)"
  esc="$(printf '\033')"
  # off ⇒ not one escape byte anywhere (this is what /wrap's model-captured pull surface gets)
  ! printf '%s' "$plain" | grep -q "$esc" || false
  # on ⇒ the SUPPLY clause carries the TUI's own warning amber, closed with 22;39 — NOT 0m: this line
  # renders INSIDE the TUI's styled block, and 0m would reset attributes the renderer set around us
  printf '%s' "$lit" | grep -q "${esc}\[1;38;2;255;193;7mSUPPLY <your-address>${esc}\[22;39m" || false
  # …and the ▶ row is byte-identical with colour on and off
  [ "$(printf '%s' "$plain" | grep '▶')" = "$(printf '%s' "$lit" | grep '▶')" ]
  # the mark is NEVER preceded by an escape: the downstream `^ [0-9]+ (▶|◆|✎)` count and every test
  # anchored on ' ✎ ' would break if colour started before it
  printf '%s' "$lit" | grep -q " ✎ ${esc}\[" || false
}

@test "PLACEHOLDER: NO_COLOR is honoured, and --render at a non-tty is plain by default" {
  _stub_backlog "[ $(_blocked_item pc-3 "Subscribe" "the address" "cmd --to <your-address>" S1) ]"
  esc="$(printf '\033')"
  run env NO_COLOR=1 CC_OPREADOUT_COLOR=auto "$HOOK" --render --cwd "$BATS_TEST_TMPDIR" --sid S1
  ! echo "$output" | grep -q "$esc" || false
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR" --sid S1     # bats captures ⇒ stdout is not a tty
  ! echo "$output" | grep -q "$esc" || false
  echo "$output" | grep -q '✎ SUPPLY <your-address>' || false
}

@test "PLACEHOLDER: hook mode DOES colour — its destination is the TUI, and that is measured" {
  # The one deliberate push/pull difference. Hook output is decoded by the TUI (jq emits the ESC as
  # the \\u001b escape the pty probe measured surviving); --render's is captured by the MODEL, where
  # escape bytes are noise it would relay as prose. Pinned so the difference stays a decision rather
  # than being rediscovered later as a bug.
  w="$(mkrepo_landed phc)"
  _stub_backlog "[ $(_blocked_item pc-4 "Subscribe" "the address alarms go to" "cmd --to <your-address>" live-sid-9) ]"
  msg="$(hookrun_sid live-sid-9 "$w" | jq -r '.systemMessage')"
  printf '%s' "$msg" | grep -q "$(printf '\033')\[1;38;2;255;193;7mSUPPLY" || false
}

@test "PLACEHOLDER: a missing lib degrades to TODAY'S render, never to convict-everything" {
  # The failure mode worse than the defect: an empty \$ph makes jq's `test(\"\")` true for EVERY row,
  # so a lib that failed to resolve would turn the whole board into ✎. The fallback defs answer
  # `false`, restoring the pre-2026-08-22 render exactly.
  _stub_backlog "[ $(_blocked_item ph-6 "Load it" "operator must load it" "launchctl load ~/x.plist" S1),
                   $(_blocked_item ph-7 "Subscribe" "the address" "cmd --to <your-address>" S1) ]"
  hidden="$BATS_TEST_TMPDIR/hidden-hook"; mkdir -p "$hidden/lib"
  cp "$HOOK" "$hidden/"; cp "$REPO/hooks/lib/idl-log.sh" "$hidden/lib/"
  HOME="$BATS_TEST_TMPDIR/nohome" CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/nocfg" \
    run bash "$hidden/operator-readout.sh" --render --cwd "$BATS_TEST_TMPDIR" --sid S1
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q '✎' || false
  echo "$output" | grep -q '▶ launchctl load ~/x.plist' || false
}

# ── 🚀 (face 4 of the inertness generator) ────────────────────────────────────────────────────────
# wrap-ledger grew a rung between 📦 and 👤: landed on trunk, but the LIVE LAYER — the store
# behaviour actually reads — is behind past its converge budget, or a migration carrying the
# conclusion into settings.json / a plist / PATH FAILED. This renderer decides by `case "$RUNG"`, and
# an unhandled member leaves `state` EMPTY (MEMORY.md new-enum-member-falls-into-fail-closed-default)
# — the ledger would compute the one fact the operator needs and the renderer would drop it silently.
# A STUB ledger is the right instrument here: it isolates the renderer's dispatch from the (separately
# tested) question of when the real ledger decides to emit 🚀.
stub_ledger() { # $1=RUNG, rest = extra KEY=VALUE lines
  local rung="$1"; shift
  local f="$BATS_TEST_TMPDIR/stub-ledger-$BATS_TEST_NUMBER.sh"
  { printf '#!/bin/bash\n'
    printf 'case "${1:-}" in --machine) ;; *) printf "stub\\n"; exit 0 ;; esac\n'
    printf 'printf "RUNG=%s\\n"\n' "$rung"
    printf 'printf "AHEAD=0\\nSHAS=\\nDIRTY_N=0\\nGATE=green\\nREMAINDER=0\\nUNLANDED=0\\n"\n'
    local kv; for kv in "$@"; do printf 'printf "%s\\n"\n' "$kv"; done
  } > "$f"
  chmod +x "$f"; printf '%s' "$f"
}

@test "🚀: a lagging live layer renders its own state and a runnable step, never an empty header" {
  w="$(mkrepo_landed rocket)"
  run env - \
    HOME="$HOME" PATH="$PATH" CC_BACKLOG_FILE="$CC_BACKLOG_FILE" \
    CC_ACTIVATION_DIR="$CC_ACTIVATION_DIR" CC_DECISIONS_DIR="$CC_DECISIONS_DIR" \
    CC_SHARED_CHECKOUT="$CC_SHARED_CHECKOUT" CC_OPREADOUT_NOW="$CC_OPREADOUT_NOW" \
    CC_OPREADOUT_TTL_S="$CC_OPREADOUT_TTL_S" WRAP_TRUNK="origin/main" \
    WRAP_LEDGER_BIN="$(stub_ledger "🚀" "LIVE_LAG=41" "MIG_FAILED=0")" \
    bash "$HOOK" --render "$w"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | grep -q '🚀' || { echo "no 🚀 in the block: $output"; false; }
  printf '%s' "$output" | grep -q '41 commit' || { echo "the lag was not named: $output"; false; }
  printf '%s' "$output" | grep -q 'deploy-live.sh' || { echo "no runnable step: $output"; false; }
  # The defect this case exists for: an unhandled rung renders a header with an EMPTY state.
  ! printf '%s' "$output" | grep -qE 'OPERATOR ▸[[:space:]]*$' \
    || { echo "empty state — the rung fell into the default arm: $output"; false; }
  true
}

@test "🚀: ADDED files are reported as the cause instead of the budget" {
  w="$(mkrepo_landed rocketadd)"
  run env - HOME="$HOME" PATH="$PATH" CC_BACKLOG_FILE="$CC_BACKLOG_FILE" \
    CC_ACTIVATION_DIR="$CC_ACTIVATION_DIR" CC_DECISIONS_DIR="$CC_DECISIONS_DIR" \
    CC_SHARED_CHECKOUT="$CC_SHARED_CHECKOUT" CC_OPREADOUT_NOW="$CC_OPREADOUT_NOW" \
    CC_OPREADOUT_TTL_S="$CC_OPREADOUT_TTL_S" WRAP_TRUNK="origin/main" \
    WRAP_LEDGER_BIN="$(stub_ledger "🚀" "LIVE_LAG=1" "LIVE_ADDS=3" "MIG_FAILED=0")" \
    bash "$HOOK" --render "$w"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | grep -q '3 NEW file' || { echo "the added files were not named: $output"; false; }
  printf '%s' "$output" | grep -q 'deploy-live.sh' || { echo "no runnable step: $output"; false; }
  # A lag of 1 is deep INSIDE the converge budget, so the budget sentence would be a false reason
  # attached to a true rung — and it is the reason that tells the operator the file is missing, not
  # merely old (backlog 99b715f31a98).
  ! printf '%s' "$output" | grep -q 'PAST its converge budget' \
    || { echo "reported the budget for an added-file breach: $output"; false; }
  true
}

# a ledger with NO LIVE_ADDS field at all — the pre-2026-08-09 shape, and the one a live layer that
# is itself behind still emits. It must fall to the budget sentence, not to an empty or malformed
# one (MEMORY.md new-enum-member-falls-into-fail-closed-default).
@test "🚀: a ledger that emits no LIVE_ADDS still renders the budget cause" {
  w="$(mkrepo_landed rocketold)"
  run env - HOME="$HOME" PATH="$PATH" CC_BACKLOG_FILE="$CC_BACKLOG_FILE" \
    CC_ACTIVATION_DIR="$CC_ACTIVATION_DIR" CC_DECISIONS_DIR="$CC_DECISIONS_DIR" \
    CC_SHARED_CHECKOUT="$CC_SHARED_CHECKOUT" CC_OPREADOUT_NOW="$CC_OPREADOUT_NOW" \
    CC_OPREADOUT_TTL_S="$CC_OPREADOUT_TTL_S" WRAP_TRUNK="origin/main" \
    WRAP_LEDGER_BIN="$(stub_ledger "🚀" "LIVE_LAG=41" "MIG_FAILED=0")" \
    bash "$HOOK" --render "$w"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | grep -q '41 commit' || { echo "the lag was not named: $output"; false; }
  ! printf '%s' "$output" | grep -q 'NEW file' || { echo "invented an added-file cause: $output"; false; }
  true
}

@test "🚀: a FAILED migration is reported as the cause instead of the lag" {
  w="$(mkrepo_landed rocketmig)"
  run env - HOME="$HOME" PATH="$PATH" CC_BACKLOG_FILE="$CC_BACKLOG_FILE" \
    CC_ACTIVATION_DIR="$CC_ACTIVATION_DIR" CC_DECISIONS_DIR="$CC_DECISIONS_DIR" \
    CC_SHARED_CHECKOUT="$CC_SHARED_CHECKOUT" CC_OPREADOUT_NOW="$CC_OPREADOUT_NOW" \
    CC_OPREADOUT_TTL_S="$CC_OPREADOUT_TTL_S" WRAP_TRUNK="origin/main" \
    WRAP_LEDGER_BIN="$(stub_ledger "🚀" "LIVE_LAG=0" "MIG_FAILED=2")" \
    bash "$HOOK" --render "$w"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | grep -q '2 migration' || { echo "the failed migrations were not named: $output"; false; }
  printf '%s' "$output" | grep -q 'deploy-migrations.sh' || { echo "wrong remedy — a failed migration is not fixed by a redeploy: $output"; false; }
}

# ── the close block must not platter a deploy the lane rejects (DEPLOY_LANE_GROUND_UP §2.6 D5) ────
# The I11 pair above proves this row names a path that EXISTS. That was half the rule: for 534
# consecutive refusals it also named a command that could not SUCCEED, and both teach the operator
# the same thing — the board lies. The hook now asks the lane itself (`--dry-run --offline`, its own
# tier verdict with no network so the probe cannot manufacture the refusal it reports) and renders
# ⊘ HELD instead. bin/cc-do asks the SAME arbiter, which is what keeps the two surfaces agreeing
# about policy rather than merely carrying the same copy of it.

@test "deploy-lag: a lane that REFUSES renders ⊘ HELD and draws no runnable slot" {
  w="$(mkrepo_landed dheld)"
  ( cd "$w"; echo z > z.txt; git add z.txt; git commit -q -m more; git push -q origin main
    git reset -q --hard HEAD~1 ) >/dev/null 2>&1
  export CC_SHARED_CHECKOUT="$w"
  live="$BATS_TEST_TMPDIR/refusing-deploy.sh"
  printf '#!/bin/bash\necho "deploy-live: REFUSED — no GREEN tree is a DESCENDANT of live HEAD" >&2\nexit 1\n' > "$live"
  CC_DEPLOY_SCRIPT="$live" run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '⊘ deploy HELD: live layer 1 behind origin/main' || false
  echo "$output" | grep -q 'the lane refuses: no GREEN tree is a DESCENDANT' || false
  ! echo "$output" | grep -qF "▶ bash $(tild "$live")" || false   # never offered as a step
  echo "$output" | grep -q '1 held' || false              # named in the governing partition
}

@test "POSITIVE CONTROL: a lane that would ADVANCE still renders the ▶ deploy step" {
  # Pairs with the leg above: without it, "refusing lanes are held" is satisfied by holding every
  # lane, and the row would silently never be runnable again. Same fixture, exit code flipped.
  w="$(mkrepo_landed dadv)"
  ( cd "$w"; echo z > z.txt; git add z.txt; git commit -q -m more; git push -q origin main
    git reset -q --hard HEAD~1 ) >/dev/null 2>&1
  export CC_SHARED_CHECKOUT="$w"
  live="$BATS_TEST_TMPDIR/advancing-deploy.sh"; printf '#!/bin/bash\nexit 0\n' > "$live"
  CC_DEPLOY_SCRIPT="$live" run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -qF "bash $(tild "$live")" || false
  ! echo "$output" | grep -q 'HELD' || false
  ! echo "$output" | grep -q 'held' || false
}

@test "held is asked of the lane with --offline, so a Stop hook never fetches to render a board" {
  # The mechanism, pinned where it is load-bearing rather than incidental: this hook runs at EVERY
  # turn close. A probe that fetched would put a network round-trip on each one, and a fetch that
  # FAILED would die rc 1 — which this renderer would read as a deploy blocker it had itself caused.
  # The stub records its own argv, so this is the real invocation and not a text grep over the hook.
  w="$(mkrepo_landed dargv)"
  ( cd "$w"; echo z > z.txt; git add z.txt; git commit -q -m more; git push -q origin main
    git reset -q --hard HEAD~1 ) >/dev/null 2>&1
  export CC_SHARED_CHECKOUT="$w"
  live="$BATS_TEST_TMPDIR/argv-deploy.sh"; argv="$BATS_TEST_TMPDIR/argv.seen"
  printf '#!/bin/bash\necho "$*" > "%s"\nexit 1\n' "$argv" > "$live"
  CC_DEPLOY_SCRIPT="$live" run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ -f "$argv" ]
  grep -q -- '--offline' "$argv" || false
  grep -q -- '--dry-run' "$argv" || false
}

# ── blg_list_cached — the backlog-fold cache (scaling-bottlenecks-2026-08-09 §5 P0-3) ─────────

@test "blg cache: two reads of an unchanged store fold once; an append re-folds" {
  fn="$BATS_TEST_TMPDIR/fn.sh"
  sed -n '/^blg_list_cached()/,/^}/p' "$HOOK" > "$fn"
  [ -s "$fn" ]   # extraction anchor still present — renames must update this test
  stub="$BATS_TEST_TMPDIR/blg-stub"
  printf '#!/bin/bash\necho x >> "$COUNT_FILE"\necho "[{\\"id\\":\\"i1\\"}]"\n' > "$stub"
  chmod +x "$stub"
  export COUNT_FILE="$BATS_TEST_TMPDIR/count"; : > "$COUNT_FILE"
  store="$BATS_TEST_TMPDIR/blg-cache-store.jsonl"; printf '{"a":1}\n' > "$store"
  run bash -c "BLG_FILE='$store'; . '$fn'; blg_list_cached '$stub' --blocked --json; blg_list_cached '$stub' --blocked --json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"id":"i1"'*'"id":"i1"'* ]] || false # both reads returned the fold
  [ "$(wc -l < "$COUNT_FILE" | tr -d ' ')" = "1" ]  # ONE underlying fold for two reads
  printf '{"a":2}\n' >> "$store"                    # append moves (mtime,size) → exact miss
  run bash -c "BLG_FILE='$store'; . '$fn'; blg_list_cached '$stub' --blocked --json"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$COUNT_FILE" | tr -d ' ')" = "2" ]
}

@test "blg cache: distinct list args never share an entry" {
  fn="$BATS_TEST_TMPDIR/fn.sh"
  sed -n '/^blg_list_cached()/,/^}/p' "$HOOK" > "$fn"
  stub="$BATS_TEST_TMPDIR/blg-stub2"
  printf '#!/bin/bash\nshift\necho "ARGS:$*"\n' > "$stub"; chmod +x "$stub"
  store="$BATS_TEST_TMPDIR/blg-args-store.jsonl"; printf '{"a":1}\n' > "$store"
  run bash -c "BLG_FILE='$store'; . '$fn'; blg_list_cached '$stub' --blocked --json; blg_list_cached '$stub' --open --json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ARGS:--blocked --json"* ]] || false
  [[ "$output" == *"ARGS:--open --json"* ]]
}

@test "blg cache: a failing tool caches nothing and yields empty (matches the uncached contract)" {
  fn="$BATS_TEST_TMPDIR/fn.sh"
  sed -n '/^blg_list_cached()/,/^}/p' "$HOOK" > "$fn"
  stub="$BATS_TEST_TMPDIR/blg-stub3"
  printf '#!/bin/bash\nexit 1\n' > "$stub"; chmod +x "$stub"
  store="$BATS_TEST_TMPDIR/blg-fail-store.jsonl"; printf '{"a":1}\n' > "$store"
  run bash -c "BLG_FILE='$store'; . '$fn'; blg_list_cached '$stub' --blocked --json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$(find "$CC_ORB_BLG_CACHE_DIR" -type f ! -name '.w.*' 2>/dev/null)" ]
}

# ── D3: the escalation dead-letter counted line (additive; hooks/escalation-watch.sh owns the
#    per-class SessionStart render, this is the ONE standing count on the close surface) ──────────

@test "ESCALATIONS: undrained records render ONE counted ◆ line carrying its listing command" {
  # A record must exist alongside at least one real step, because this line rides the block — it is
  # deliberately NOT a fire predicate (that would be a behavioural change, not an additive line).
  printf '#!/bin/bash\necho hi\n' > "$CC_ACTIVATION_DIR/10-plain-activate.sh"
  mk_escalation 1; mk_escalation 2; mk_escalation 3
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '◆ 3 escalation record(s) unseen — cc-escalations ack --all' || false
}

@test "ESCALATIONS: an M3 dead letter counts into the SAME ◆ line, its .ran evidence does not" {
  # R-6. The M3 dead-letter store was written by handoff-fire and read by nothing, so its records
  # could not reach the operator at all. It joins the existing count rather than getting a line of
  # its own: one predicate — "a durable record nothing has drained" — must have ONE standing line.
  printf '#!/bin/bash\necho hi\n' > "$CC_ACTIVATION_DIR/10-plain-activate.sh"
  mk_escalation 1
  mk_deadletter 01998f3a-dead-4beef-9c21-000000000001
  mk_deadletter_ran 01998f3a-dead-4beef-9c21-000000000001   # evidence, NOT a record
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  # 2, not 3: `.ran` must not inflate the count, or an empty-but-ran store would read as outstanding
  # work forever — the exact collapse the writer created that file to prevent.
  echo "$output" | grep -q '◆ 2 escalation record(s) unseen' || false
}

@test "ESCALATIONS: a dead letter drops out of the count once acked (the off switch reaches here too)" {
  printf '#!/bin/bash\necho hi\n' > "$CC_ACTIVATION_DIR/10-plain-activate.sh"
  mk_deadletter dl-x
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '◆ 1 escalation record(s) unseen' || false     # positive control
  : > "$CC_SWEEP_SEEN_DIR/$(printf '%s' "$CC_MAILBOX_DIR/dead-letter/dl-x.md" | shasum -a 256 | cut -c1-32)"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'escalation record' || false
}

@test "ESCALATIONS: zero records ⇒ the line is ABSENT (control for the assertion above)" {
  printf '#!/bin/bash\necho hi\n' > "$CC_ACTIVATION_DIR/10-plain-activate.sh"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ -n "$output" ]                                    # positive control: the block DID render
  ! echo "$output" | grep -q 'escalation record' || false
}

@test "ESCALATIONS: the count uses the sweep's REAL sha-key marker, so drained records drop out" {
  printf '#!/bin/bash\necho hi\n' > "$CC_ACTIVATION_DIR/10-plain-activate.sh"
  mk_escalation 1; mk_escalation 2; mk_escalation 3
  mk_escalation_seen 2
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '◆ 2 escalation record(s) unseen' || false
}

@test "ESCALATIONS: a completion-push record with verdict verified is NOT counted" {
  printf '#!/bin/bash\necho hi\n' > "$CC_ACTIVATION_DIR/10-plain-activate.sh"
  printf '{\n  "kind": "completion-push",\n  "verdict": "push-failed(rc=5)"\n}\n' > "$CC_COMPLETION_RECORDS_DIR/push-1.json"
  printf '{\n  "kind": "completion-push",\n  "verdict": "verified"\n}\n'          > "$CC_COMPLETION_RECORDS_DIR/push-2.json"
  run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '◆ 1 escalation record(s) unseen' || false
}

@test "ESCALATIONS: the line is UNNUMBERED, so the downstream NSTEPS count is unchanged" {
  # NSTEPS greps `^ [0-9]+ (▶|◆)`. These are records a machine should have drained, not operator
  # steps, so counting them as steps would inflate the rung the close reports.
  # Measured under CLASSBUDGET=on, NOT the collapse default: collapse numbers nothing, so both sides
  # would be 0 and the assertion would hold no matter what this line does. `|| true` because
  # `grep -c` exits 1 on a zero count, which is a count, not an error.
  printf '#!/bin/bash\necho hi\n' > "$CC_ACTIVATION_DIR/10-plain-activate.sh"
  ref="$(CC_OPREADOUT_CLASSBUDGET=on "$HOOK" --render --cwd "$BATS_TEST_TMPDIR" | grep -cE '^ [0-9]+ (▶|◆)' || true)"
  [ "$ref" -ge 1 ] || false                     # the metric is live, so a no-op cannot pass this
  mk_escalation 1; mk_escalation 2
  out="$(CC_OPREADOUT_CLASSBUDGET=on "$HOOK" --render --cwd "$BATS_TEST_TMPDIR")"
  now="$(printf '%s\n' "$out" | grep -cE '^ [0-9]+ (▶|◆)' || true)"
  printf '%s\n' "$out" | grep -q '◆ 2 escalation record(s) unseen' || false   # …and the line IS there
  [ "$ref" = "$now" ]
}

@test "ESCALATIONS: the line renders identically under every class-budget mode" {
  printf '#!/bin/bash\necho hi\n' > "$CC_ACTIVATION_DIR/10-plain-activate.sh"
  mk_escalation 1
  for m in collapse on off; do
    CC_OPREADOUT_CLASSBUDGET="$m" run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
    echo "$output" | grep -q '◆ 1 escalation record(s) unseen — cc-escalations ack --all' || false
  done
}

# ── W2 CUSTODY on the 🔧 state line (custody v1.1, item d29b73103189) ────────────────────────────
# wrap-ledger ranks OPEN CUSTODY ahead of every remaining arm and short-circuits the chain, so a
# custody-driven 🔧 reaches this renderer with DIRTY_N=0, GATE fresh and REMAINDER=0 — every term
# the 🔧 arm knew about empty — and rendered the contentless fallback "🔧 in progress — loose ends".
# Same class as the 🚀 dispatch defect the stub_ledger block above exists for, with one difference
# that is why it survived: the fallback here is a TRUE sentence, so nothing looked broken. A stub
# ledger is again the right instrument — when the real ledger decides to emit a custody 🔧 is
# tests/wrap-ledger.bats's question, not this renderer's.
#
# A stub of its own, rather than stub_ledger above: that one appends its extras AFTER the default
# block, and `lf()` reads with `head -1`, so an extra naming a default key (DIRTY_N, REMAINDER) is
# silently shadowed by the default. Harmless for the 🚀 cases, which only ever add NEW keys — but
# these cases need to vary the incumbent terms in order to prove custody composes with them rather
# than replacing them, so the overrides have to come FIRST.
stub_ledger_over() { # $1=RUNG, rest = KEY=VALUE lines that WIN over the defaults
  local rung="$1"; shift
  local f="$BATS_TEST_TMPDIR/stub-ledger-over-$BATS_TEST_NUMBER.sh"
  { printf '#!/bin/bash\n'
    printf 'case "${1:-}" in --machine) ;; *) printf "stub\\n"; exit 0 ;; esac\n'
    printf 'printf "RUNG=%s\\n"\n' "$rung"
    local kv; for kv in "$@"; do printf 'printf "%s\\n"\n' "$kv"; done
    printf 'printf "AHEAD=0\\nSHAS=\\nDIRTY_N=0\\nGATE=green\\nREMAINDER=0\\nUNLANDED=0\\n"\n'
  } > "$f"
  chmod +x "$f"; printf '%s' "$f"
}
custody_env() { # renders with a stub ledger; an activation step satisfies the fire predicate
  printf '#!/bin/bash\n' > "$CC_ACTIVATION_DIR/14-custody-activate.sh"
  env - HOME="$HOME" PATH="$PATH" CC_BACKLOG_FILE="$CC_BACKLOG_FILE" \
    CC_ACTIVATION_DIR="$CC_ACTIVATION_DIR" CC_DECISIONS_DIR="$CC_DECISIONS_DIR" \
    CC_SHARED_CHECKOUT="$CC_SHARED_CHECKOUT" CC_OPREADOUT_NOW="$CC_OPREADOUT_NOW" \
    CC_OPREADOUT_TTL_S="$CC_OPREADOUT_TTL_S" WRAP_TRUNK="origin/main" \
    WRAP_LEDGER_BIN="$1" bash "${2:-$HOOK}" --render "$3"
}

@test "🔧 custody: dispatched sessions that have not returned are NAMED, with their listing command" {
  w="$(mkrepo_landed custodyfix)"
  run custody_env "$(stub_ledger "🔧" "CUSTODY_OPEN=2")" "$HOOK" "$w"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | grep -q '2 dispatched session(s) NOT returned' \
    || { echo "the custody cause was dropped: $output"; false; }
  printf '%s' "$output" | grep -q 'cc-custody list --open --cwd .' \
    || { echo "no drivable listing command: $output"; false; }
  # the contentless fallback must be GONE, not merely accompanied
  ! printf '%s' "$output" | grep -q 'in progress — loose ends' \
    || { echo "still rendering the fallback: $output"; false; }
}

@test "🔧 custody CONTROL: CUSTODY_OPEN=0 leaves the existing 🔧 wording byte-for-byte alone" {
  w="$(mkrepo_landed custodyzero)"
  run custody_env "$(stub_ledger_over "🔧" "CUSTODY_OPEN=0" "DIRTY_N=3")" "$HOOK" "$w"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | grep -q '🔧 in progress — 3 file(s) uncommitted' \
    || { echo "the incumbent wording moved: $output"; false; }
  ! printf '%s' "$output" | grep -q 'dispatched session' || { echo "invented custody: $output"; false; }
  ! printf '%s' "$output" | grep -q 'cc-custody' || { echo "invented a custody command: $output"; false; }
}

@test "🔧 custody: a ledger with NO CUSTODY_OPEN field at all is a clean zero, never a malformed line" {
  w="$(mkrepo_landed custodyabsent)"
  run custody_env "$(stub_ledger_over "🔧" "DIRTY_N=1")" "$HOOK" "$w"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | grep -q '🔧 in progress — 1 file(s) uncommitted' \
    || { echo "an absent field corrupted the line: $output"; false; }
  ! printf '%s' "$output" | grep -q 'dispatched session' || false
}

@test "🔧 custody: custody LEADS a mixed cause — the work not in this tree is named first" {
  w="$(mkrepo_landed custodymixed)"
  run custody_env "$(stub_ledger_over "🔧" "CUSTODY_OPEN=1" "DIRTY_N=2" "REMAINDER=4")" "$HOOK" "$w"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # every cause survives — a partition, not a replacement
  printf '%s' "$output" | grep -q '1 dispatched session(s) NOT returned · 2 file(s) uncommitted · 4 DoD item(s) open' \
    || { echo "wrong partition or ordering: $output"; false; }
}

# PINNED TO A SHA, NEVER A MOVING REF. `origin/main` was the pre-v1.1 tree only until custody landed
# on it (6cedafbf5); from that moment the staleness guard matched and this case reported
# `ok … # skip control is not pre-v1.1` on every run — green, and proving nothing. A stale control
# does not fail, it SKIPS, and bats renders a skip as `ok`; the guard is a hard FAILURE now.
# tests/wake-floor.bats:164-170 documents the hazard.  73ceb76aa = 6cedafbf5~1.
CC_READOUT_CUSTODY_PREFIX_SHA="${CC_READOUT_CUSTODY_PREFIX_SHA:-73ceb76aa}"
@test "RED-PROOF: the pre-v1.1 renderer (pinned sha) drops a custody 🔧 to 'loose ends'" {
  local old="$BATS_TEST_TMPDIR/pre-custody-hook"; mkdir -p "$old"
  git -C "$REPO" archive "$CC_READOUT_CUSTODY_PREFIX_SHA" hooks | tar -x -C "$old" \
    || skip "pre-fix tree $CC_READOUT_CUSTODY_PREFIX_SHA unavailable"
  [ -f "$old/hooks/operator-readout.sh" ] || false
  ! grep -q 'CUSTODY_OPEN' "$old/hooks/operator-readout.sh" || false
  w="$(mkrepo_landed custodyred)"
  run custody_env "$(stub_ledger "🔧" "CUSTODY_OPEN=2")" "$old/hooks/operator-readout.sh" "$w"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # RED: the ledger computed the ONE fact the operator needed and the renderer said nothing about it.
  printf '%s' "$output" | grep -q 'in progress — loose ends' \
    || { echo "control did not reproduce the drop: $output"; false; }
}

# ── ✎ A VALUE IS MISSING (operator incident 2026-08-22) ─────────────────────────────────────────
# A close plattered `aws sns subscribe … --notification-endpoint <your-address>` under a run
# marker. `▶` is a PROMISE — "paste this" — and a template breaks it in the one place the operator
# trusts. completion-assert catches it in the MODEL's prose but only at Stop, i.e. after they have
# read it. This renderer emits its OWN rows from disk, so here it can PREVENT rather than apologise.

ph_stub() { # $1 = the `run` value the store would hold → path to a cc-backlog stub emitting it
  local stub="$BATS_TEST_TMPDIR/cc-backlog-ph-stub-$BATS_TEST_NUMBER"
  cat > "$stub" <<EOS
#!/bin/bash
printf '[{"id":"ph0000000001","title":"Subscribe to the alert topic","needs":"the email address alarms should go to","run":"$1","status":"blocked"}]\n'
EOS
  chmod +x "$stub"; printf '%s' "$stub"
}

@test "✎: a stored command carrying a placeholder must NOT render as ▶" {
  # The exact incident command. If this ever renders ▶ again, the operator can paste a template.
  s="$(ph_stub 'aws sns subscribe --protocol email --notification-endpoint <your-address>')"
  CC_BACKLOG_BIN="$s" run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  ! echo "$output" | grep -q '▶ aws sns subscribe' || false
  echo "$output" | grep -q '✎' || false
}

@test "✎: the row NAMES the missing token, so the operator knows what to supply" {
  s="$(ph_stub 'aws sns subscribe --protocol email --notification-endpoint <your-address>')"
  CC_BACKLOG_BIN="$s" run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  # The token itself, and the filer's prose saying what the value IS — "a value is missing" alone
  # is useless, which is the whole complaint that produced this row.
  echo "$output" | grep -q '<your-address>' || false
  echo "$output" | grep -q 'the email address alarms should go to' || false
}

@test "✎ CONTROL: a complete command still renders ▶ (the check has to be able to NOT fire)" {
  # Without this, "never platter a template" is satisfiable by never plattering anything.
  s="$(ph_stub 'aws sns subscribe --protocol email --notification-endpoint ren.chris@outlook.com')"
  CC_BACKLOG_BIN="$s" run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '▶ aws sns subscribe' || false
  ! echo "$output" | grep -q '✎' || false
}

@test "✎ CONTROL: an angle-bracket inside a trailing # comment does NOT flag the row" {
  # MEASURED false positive: of the 71 live blocked rows carrying a run, exactly one matched the
  # placeholder shape — its command ends `… # last attempt: rc=143, head pinned at <unrecorded>`.
  # That command runs perfectly. Flagging it would put a "supply a value" row on the board for a
  # value nobody needs, and a board that cries wolf is one the operator learns to skim.
  s="$(ph_stub 'bash deploy.sh   # last attempt: rc=143 (SIGTERM), head pinned at <unrecorded>')"
  CC_BACKLOG_BIN="$s" run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '▶ bash deploy.sh' || false
  ! echo "$output" | grep -q '✎' || false
}

@test "✎: the row is COUNTED — it is work the operator must act on, not a footnote" {
  s="$(ph_stub 'aws sns subscribe --notification-endpoint <your-address>')"
  CC_BACKLOG_BIN="$s" run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  # NSTEPS greps '^ [0-9]+ (▶|◆|✎)' downstream; a ✎ that fell out of the count would let the
  # header read "0 runnable" while a real operator step sat on the board.
  echo "$output" | grep -qE '^ +[0-9]* *✎|✎' || false
}

# ══════════════════════════════════════════════════════════════════════════════════════════════════
# IMPACT RANKING + PREMISE AGE on the blocked class (operator directive 2026-08-23)
#
# THE FAILURE THAT ORDERED THIS. The operator asked what was blocking the cloud lane. The close
# said "blocked on credentials only you can grant" and named three row ids. The reply was: "What is
# it??? Spell it out. I don't want to have to scan the entire walls of text to go fish what you are
# needing me to do." Three of 188 blocked an entire lane and NOTHING distinguished them from the
# other 185, because the class itemized only at `cn <= 3` and printed a bare count above that — so
# the pile named nothing exactly where naming is the only thing that helps. The `yours` class fixed
# a NARROWER case (steps THIS session filed) and structurally cannot reach this one: those three
# rows were filed days earlier by other sessions, so they are in no current session's bucket, and
# they are 3-of-188, so they never clear the size gate. Invisible at every close, forever.
#
# THE SECOND DEFECT, found the same hour, and it is not a ranking problem: NOTHING EVER
# RE-VALIDATES A BLOCKED ROW. One of the three (1dca461d4b90, install the GitHub App) had been
# stale for two months — installed, all-repositories, write access, for the entire window in which
# it kept rendering as a live demand. A perfectly ranked list of dead asks is still a wall.
#
# WHAT THE FIXTURES PIN. The impact signal is read off the REAL append-only store
# ($CC_BACKLOG_FILE) — one `block` record per time a session reached this row, could not proceed,
# and filed it again — while the fold itself stays stubbed, so these cases pin the ranking without
# depending on `cc-backlog block`'s own transition rules. Premise age is measured from the last
# `block` record and from nothing else: `lastTs` on the fold is moved by `link`/`venue`
# bookkeeping that re-examines nothing (measured live: two rows blocked once on 2026-07-20 and
# never touched again scored 2nd and 3rd on a lastTs-derived span, purely off one `link`).
# ══════════════════════════════════════════════════════════════════════════════════════════════════

# 2026-08-20T00:00:00Z. Pinned so "unchecked 30d" is an assertion about the fixture, not about the
# day the suite runs (same reason CC_OPREADOUT_NOW is pinned for the damping latch).
RANK_NOW=1787184000

_block_evt() {  # $1=id $2=ISO ts — one `block` record, the unit the impact count counts
  printf '{"id":"%s","ts":"%s","event":"block"}\n' "$1" "$2" >> "$CC_BACKLOG_FILE"
}

_rank_fixture() {  # 5 low-impact rows + $1 as the id of the high-impact one
  local hi="$1"
  _block_evt "$hi" 2026-07-21T00:00:00Z; _block_evt "$hi" 2026-07-25T00:00:00Z
  _block_evt "$hi" 2026-08-01T00:00:00Z; _block_evt "$hi" 2026-08-05T00:00:00Z
  _block_evt "$hi" 2026-08-10T00:00:00Z
  local i; for i in 1 2 3 4 5; do _block_evt "b-$i" 2026-08-19T00:00:00Z; done
  _stub_backlog "[ $(_blocked_item "$hi" "Grant the cloud lane its credential" "operator must grant" "" ""),
                   $(_blocked_item b-1 "one"   "operator" "" ""), $(_blocked_item b-2 "two"   "operator" "" ""),
                   $(_blocked_item b-3 "three" "operator" "" ""), $(_blocked_item b-4 "four"  "operator" "" ""),
                   $(_blocked_item b-5 "five"  "operator" "" "") ]"
}

@test "RANK: the highest-impact blocked row is NAMED at a class size where nothing used to be" {
  # THE RED-PROOF. Pre-fix this rendered `◆ 6 blocked backlog — your call` and not one id; the
  # class named items only at cn<=3, i.e. never at the size that matters.
  _rank_fixture zz-cloud            # sorts LAST alphabetically — see the id-order case below
  CC_OPREADOUT_NOW_EPOCH=$RANK_NOW run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'zz-cloud' || false
  echo "$output" | grep -q 'blocked 5×' || false
  echo "$output" | grep -q 'Grant the cloud lane its credential' || false
  # A COUNT MAY FOLLOW A NAME; IT MAY NEVER REPLACE ONE. The 6 is still on the header, and so is
  # the command that lists all of them — the completeness guarantee is untouched.
  echo "$output" | grep -q '◆ 6 blocked backlog — work keeps stopping at these 2   cc-backlog list --blocked' || false
}

@test "RANK is by IMPACT, not by id order — the named row is the one work kept stopping at" {
  # `zz-cloud` sorts after every `b-N`, so a renderer that named "the first N" would name b-1/b-2.
  _rank_fixture zz-cloud
  CC_OPREADOUT_NOW_EPOCH=$RANK_NOW run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  # first named row is the high-impact one, not the alphabetically-first
  first="$(echo "$output" | grep -E '^   ◆ ' | head -1)"
  echo "$first" | grep -q 'zz-cloud' || false
  ! echo "$first" | grep -q 'b-1' || false
}

@test "RANK is by IMPACT, not recency — a row blocked 5× outranks five blocked TODAY" {
  # The low-impact rows are re-blocked on the pinned `now`; the high-impact one has not been
  # touched in 10 days. Recency ordering would bury it; impact ordering does not.
  _rank_fixture aa-cloud
  _block_evt b-1 2026-08-20T00:00:00Z; _block_evt b-2 2026-08-20T00:00:00Z
  printf '\n' >> "$CC_BACKLOG_FILE"       # store change ⇒ fold-cache miss, as in production
  CC_OPREADOUT_NOW_EPOCH=$RANK_NOW run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -E '^   ◆ ' | head -1 | grep -q 'aa-cloud' || false
}

@test "STALENESS: a named row carries how long its premise has gone unre-asserted" {
  # 1dca461d4b90's defect: filing is write-once, so a dead premise renders as a live demand
  # forever. The age is measured from the last `block` record — 2026-08-10 vs a pinned 2026-08-20.
  _rank_fixture zz-cloud
  CC_OPREADOUT_NOW_EPOCH=$RANK_NOW run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q 'zz-cloud  blocked 5× · unchecked 10d' || false
}

@test "STALENESS: the share of the class whose premise nobody re-asserted is stated out loud" {
  # A ranked list of dead asks is still a wall to audit by hand. Horizon lowered to 5d so the
  # fixture's own 10d row crosses it and the 1d rows do not — i.e. the count discriminates.
  _rank_fixture zz-cloud
  CC_OPREADOUT_NOW_EPOCH=$RANK_NOW CC_OPREADOUT_STALE_D=5 run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '─ 1 of 6 last re-checked >5d ago — premise unverified' || false
  # CONTROL — the line must be able to NOT fire: at a horizon above every row's age it is absent.
  CC_OPREADOUT_NOW_EPOCH=$RANK_NOW CC_OPREADOUT_STALE_D=90 run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  ! echo "$output" | grep -q 'premise unverified' || false
}

@test "FAIL-OPEN: an unparseable store degrades to the incumbent count, never to an empty class" {
  # This is a Stop hook on the live path. A ranking that errors must lose the RANKING, not the
  # class — the 6 rows and their listing command still have to reach the operator.
  _rank_fixture zz-cloud
  printf 'this is not json\n' >> "$CC_BACKLOG_FILE"     # `jq -s` over the store now aborts
  CC_OPREADOUT_NOW_EPOCH=$RANK_NOW run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '◆ 6 blocked backlog — your call   cc-backlog list --blocked' || false
  ! echo "$output" | grep -q 'work keeps stopping' || false
}

@test "NO NAMING WITHOUT A MEASUREMENT: a store that distinguishes nothing keeps the plain count" {
  # Naming 2 arbitrary rows out of 188 is the "3 of 174 is noise" defect wearing a ranking. Rows
  # with no block record at all (every fixture that stubs the fold directly) earn no slot.
  _stub_backlog "[ $(_blocked_item n-1 "one" "operator" "" ""), $(_blocked_item n-2 "two" "operator" "" ""),
                   $(_blocked_item n-3 "three" "operator" "" ""), $(_blocked_item n-4 "four" "operator" "" ""),
                   $(_blocked_item n-5 "five" "operator" "" "") ]"
  CC_OPREADOUT_NOW_EPOCH=$RANK_NOW run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '◆ 5 blocked backlog — your call   cc-backlog list --blocked' || false
}

@test "the named head is SUPPORTING DETAIL: it changes no downstream count and stays in budget" {
  # The head rows are indented by three, so `^ (▶|◆)` (one line per class) and `^ [0-9]+ (▶|◆|✎)`
  # (NSTEPS) go on counting exactly what they counted. A head that inflated NSTEPS would make the
  # header claim operator steps that do not exist.
  _rank_fixture zz-cloud
  CC_OPREADOUT_NOW_EPOCH=$RANK_NOW run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$(echo "$output" | grep -cE '^ (▶|◆)')" -eq 1 ]
  [ "$(echo "$output" | grep -cE '^ [0-9]+ (▶|◆|✎)')" -eq 0 ]
  echo "$output" | head -1 | grep -q '6 need your call' || false
  # and it fits a terminal — the constraint every collapse line in this file is held to.
  [ "$(echo "$output" | awk '{print length($0)}' | sort -rn | head -1)" -le 100 ]
}

# ── ARM 2: the pre-fix renderer, at a LITERAL pinned sha ─────────────────────────────────────────
# NOT `origin/main`: a land advances that ref past this fix, and the control then compares the fix
# to itself and passes vacuously (that error cost a land rc 6 on 2026-08-22). ebf071b2a is the
# parent of the ranking commit and holds the renderer as it was when the operator hit the wall.
CC_READOUT_RANK_PREFIX_SHA="${CC_READOUT_RANK_PREFIX_SHA:-ebf071b2a}"

@test "RED-PROOF: the pre-rank renderer (pinned sha) names NOTHING in a 6-row blocked class" {
  local old="$BATS_TEST_TMPDIR/pre-rank-hook"; mkdir -p "$old"
  git -C "$REPO" archive "$CC_READOUT_RANK_PREFIX_SHA" hooks | tar -x -C "$old" \
    || skip "pre-fix tree $CC_READOUT_RANK_PREFIX_SHA unavailable"
  [ -f "$old/hooks/operator-readout.sh" ] || false
  # the control must be a tree that genuinely predates the fix, not a re-copy of it
  ! grep -q 'blgtop' "$old/hooks/operator-readout.sh" || false
  _rank_fixture zz-cloud
  CC_OPREADOUT_NOW_EPOCH=$RANK_NOW run "$old/hooks/operator-readout.sh" --render --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # RED, and this is the operator's whole complaint in one assertion: six rows, one of them hit
  # five times, and the block says only how many there are.
  echo "$output" | grep -q '◆ 6 blocked backlog — your call' \
    || { echo "control did not reproduce the pre-fix line: $output"; false; }
  ! echo "$output" | grep -q 'zz-cloud' \
    || { echo "control ALREADY names the high-impact row — the arm proves nothing: $output"; false; }
  ! echo "$output" | grep -q 'premise unverified' || false
}
