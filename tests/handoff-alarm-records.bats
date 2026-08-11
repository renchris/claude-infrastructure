#!/usr/bin/env bats
# handoff-fire: the three failure alarms CAPTURE BEFORE THEY NOTIFY.
#
# Regression under test (2026-08-07, docs/plans/HANDOFF_FAILURE_DETECTION_V2.md §D1). STRAND-RISK,
# HUSK-PANE and RECYCLE-DEAD each pushed with `cc-notify … >/dev/null 2>&1 || true` — an idiom that
# cannot fail, cannot be observed, and on a box with no `~/.claude/cc-roles/` (the operator's
# deliberate state) drops the message with exactly the silence of success. Each of those pushes is
# the ONLY artifact its failure ever produces, so the drop was total loss.
#
# Three properties are pinned here:
#   1. the RECORD is written FIRST and depends on nothing but mkdir+printf — it survives a refused
#      push, and its shape is the frozen interface D2/D3/D5 read.
#   2. the push's rc and `verdict=` token are KEPT, in the three states the old idiom collapsed into
#      one: `reached` (the desk got it) · `recorded` (a mailbox has it) · `refused-rcN` (nowhere).
#   3. every SITE is converted — one mutant per site, restored from the real pre-change artifact in
#      git history rather than a hand-edited approximation.
#
# Behavioural: the real hf_alarm and the real hf_bounded are extracted from the shipped script and
# driven under the shipped shell options (`set -euo pipefail`), so the assertions run the artifact.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude" "$BATS_TEST_TMPDIR/bin"
  # HERMETICITY (the repo's test-hermeticity ratchet). $HOME alone does not cover it: handoff-fire
  # refuses a net-new fire above 2.0/core and this box lives above that (red-by-LOAD, not by
  # subject), so the gate is pinned off for the whole file rather than per test.
  export CC_FIRE_CAPACITY_GATE=off
  # The three non-$HOME seams handoff-fire.sh reaches for. Fixturing $HOME does not redirect an
  # ABSOLUTE /tmp default, nor a BARE NAME the subject then executes off the operator's PATH — so
  # without these the suite would read the operator's live account-sweep stamp and could run their
  # deployed claude-accounts. Absent paths are the right value: these sensors fail open on one.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/handoff-account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/bin/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/claude-accounts-heal-"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  FIRE="$REPO/scripts/handoff-fire.sh"
  [ -f "$FIRE" ] || skip "handoff-fire.sh not found at $FIRE"

  ALARM_DIR="$BATS_TEST_TMPDIR/alarms"
  export CC_HANDOFF_ALARM_DIR="$ALARM_DIR"
  NOTIFY_LOG="$BATS_TEST_TMPDIR/notify.log"
  export NOTIFY_LOG

  # The push stub. It records its argv (so invocation AND non-invocation are both assertable),
  # answers on stderr the way cc-notify does — a `verdict=` token the caller must parse — and
  # exits ${STUB_RC:-3}: the DEFAULT is the refusal, because refusal is this box's live state and
  # a fixture whose default is success would test the path that is not failing.
  cat > "$BATS_TEST_TMPDIR/bin/cc-notify" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NOTIFY_LOG"
printf 'cc-notify: verdict=%s enqueued=0\n' "${STUB_VERDICT:-unresolvable}" >&2
exit "${STUB_RC:-3}"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/cc-notify"
  export CC_NOTIFY_BIN="$BATS_TEST_TMPDIR/bin/cc-notify"

  # Extract the real functions. Each is a plain `name() { … }` block terminated by a lone `}`.
  # HF_TIMEOUT_BIN is pinned empty by the driver: the no-bound branch is the shipped fallback on a
  # box without timeout(1), and the bound itself is orthogonal to the capture contract under test.
  #
  # THE WHOLE CHAIN, not just the named callee. `hf_bounded` is now a thin wrapper that delegates to
  # `hf_bounded_s "$HF_TIMEOUT_S"`, so extracting `hf_bounded` alone yields a function whose body
  # calls a command that does not exist in the driver — rc 127. That does not fail loudly here: it
  # is swallowed by hf_alarm's own `|| _rc=$?` (which exists precisely so a push can never abort its
  # caller), and every verdict silently becomes `refused-rc127`. So the suite would keep asserting
  # against a push that was never made, while reading exactly like a transport refusal. Extract what
  # the subject actually depends on, and pin HF_TIMEOUT_S because the wrapper reads it under `set -u`.
  LIB="$BATS_TEST_TMPDIR/lib.sh"
  {
    sed -n '/^hf_bounded_s()/,/^}/p' "$FIRE"
    sed -n '/^hf_bounded()/,/^}/p'   "$FIRE"
    sed -n '/^hf_alarm()/,/^}/p'     "$FIRE"
  } > "$LIB"
  # Fail loud if the chain ever changes shape again, rather than degrading into rc 127 as above.
  grep -q '^hf_bounded_s()' "$LIB" || { echo "hf_bounded_s not extractable from $FIRE"; return 1; }
}

# Drive hf_alarm under the shipped shell options. `set -euo pipefail` is not decoration: the whole
# helper is written around not aborting its caller when the push refuses, and a driver without -e
# would pass vacuously on exactly that bug. CALLER-CONTINUED proves the caller survived.
alarm() { # $1=class $2=pane $3=sid $4=successor $5=detail
  run bash -c "set -euo pipefail; HF_TIMEOUT_BIN=''; HF_TIMEOUT_S=10; . '$LIB'; hf_alarm \"\$@\"; echo CALLER-CONTINUED" _ "$@"
}

records()  { ls "$ALARM_DIR"/alarm-*.json 2>/dev/null; }
rec()      { cat "$ALARM_DIR"/alarm-*.json 2>/dev/null; }
verdict()  { cat "$ALARM_DIR"/alarm-*.json.verdict 2>/dev/null; }
pushes()   { cat "$NOTIFY_LOG" 2>/dev/null; }
count()    { printf '%s' "$1" | grep -c . || true; }

# The MUTANT: the newest revision whose handoff-fire.sh still carried the legacy silent push for
# this class. Keyed on the DEFECT, not on HEAD — a mutant fetched from `HEAD` stops being a mutant
# the moment this change lands, which is how a per-site control silently retires itself.
pristine_hf() { # $1=class token → prints the path to the pre-change artifact
  local rev out="$BATS_TEST_TMPDIR/pristine-$1.sh"
  [ -s "$out" ] && { printf '%s\n' "$out"; return 0; }
  for rev in $(git -C "$REPO" rev-list -n 200 HEAD -- scripts/handoff-fire.sh); do
    git -C "$REPO" show "$rev:scripts/handoff-fire.sh" > "$out" 2>/dev/null || continue
    if grep -qE "$1.*>/dev/null 2>&1 \|\| true" "$out"; then printf '%s\n' "$out"; return 0; fi
  done
  return 1
}

# ── 1. the record: written first, shaped as the frozen interface ─────────────────────────────────

@test "the record is written with the frozen shape, on ONE line, with no jq in the path" {
  [ -z "$(records)" ]                                   # control: the dir starts empty…
  alarm strand-risk PANE-1 SID-1 SUCC-1 "HANDOFF-STRAND-RISK: successor died before the close instant"
  [ "$status" -eq 0 ]
  [ -n "$(records)" ]                                   # …and the call is what fills it
  [ "$(count "$(records)")" -eq 1 ]

  [ "$(rec | wc -l | tr -d ' ')" -eq 1 ]                # a multi-line record is an unreadable record
  rec | grep -q '"kind":"handoff-alarm"' || false
  rec | grep -q '"class":"strand-risk"' || false
  rec | grep -q '"pane":"PANE-1"' || false
  rec | grep -q '"sid":"SID-1"' || false
  rec | grep -q '"successor":"SUCC-1"' || false
  rec | grep -q '"detail":"HANDOFF-STRAND-RISK: successor died before the close instant"' || false
  rec | grep -qE '"ts":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"' || false

  # The filename is a sort key and a collision guard: two watchers can alarm in the same second.
  basename "$(records)" | grep -qE '^alarm-[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9]+\.json$' || false
}

@test "with no CC_HANDOFF_ALARM_DIR the record lands under \$HOME, never in the cwd" {
  unset CC_HANDOFF_ALARM_DIR
  alarm husk-pane PANE-2 "" "" "HANDOFF-HUSK-PANE: pane still open"
  [ "$status" -eq 0 ]
  [ -n "$(ls "$HOME/.claude/handoff-alarms"/alarm-*.json 2>/dev/null)" ]
}

# ── 2. the verdict sidecar: the three states `|| true` collapsed into one ─────────────────────────

@test "rc 0 + verdict=delivered ⇒ reached — the desk actually got it" {
  STUB_RC=0 STUB_VERDICT=delivered alarm strand-risk P S U "HANDOFF-STRAND-RISK: x"
  [ "$status" -eq 0 ]
  [ "$(verdict)" = reached ]
  echo "$output" | grep -q 'push=reached' || false
}

@test "rc 0 + any other verdict ⇒ recorded — a mailbox has it, nobody has read it" {
  STUB_RC=0 STUB_VERDICT=mailbox-only alarm husk-pane P S U "HANDOFF-HUSK-PANE: x"
  [ "$status" -eq 0 ]
  [ "$(verdict)" = recorded ]
  # control for the test above: the same rc, a different token, a DIFFERENT verdict — so `reached`
  # is discriminating rather than whatever rc 0 always prints.
  [ "$(verdict)" != reached ]
}

@test "a REFUSED push is recorded as refused-rc3, keeps its record, and does NOT break the caller" {
  # The live failure: no ~/.claude/cc-roles/, so every push refuses. The record is the only thing
  # that survives it — and under `set -e` a naive capture would abort the watcher mid-teardown.
  STUB_RC=3 alarm recycle-dead RECY-1 "" "" "HANDOFF-RECYCLE-DEAD: never engaged"
  [ "$status" -eq 0 ]
  [ "$(verdict)" = refused-rc3 ]
  [ -n "$(records)" ]                                   # capture survived the refusal
  rec | grep -q '"class":"recycle-dead"' || false
  echo "$output" | grep -q 'CALLER-CONTINUED' || false
  echo "$output" | grep -q 'push=refused-rc3' || false
}

@test "the watcher log line names the class, the record and the push outcome" {
  # The sites run inside detached watchers, so stdout IS the operator-facing artifact.
  STUB_RC=0 STUB_VERDICT=delivered alarm strand-risk P S U "HANDOFF-STRAND-RISK: x"
  echo "$output" | grep -qE "^hf_alarm class=strand-risk record=alarm-[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9]+\.json push=reached$" || false
}

# ── 3. the push is still made, and still says what the sibling suites read ────────────────────────

@test "the push carries the site's message VERBATIM, so it stays greppable downstream" {
  # bin/cc-mail, hooks/mailbox-drain.sh and four sibling suites key on the HANDOFF-<CLASS> token.
  # Capture-before-notify demotes the push; it must not rewrite it.
  alarm husk-pane PANE-9 "" "" "HANDOFF-HUSK-PANE: self-close of PANE-9 typed /exit successfully"
  pushes | grep -q 'HANDOFF-HUSK-PANE: self-close of PANE-9 typed /exit successfully' || false
  pushes | grep -q -- '--role desk' || false
}

# ── 4. the kill switch ───────────────────────────────────────────────────────────────────────────

@test "CC_HF_ALARM_RECORDS=0 restores the legacy push-only path: NO record, push still made" {
  CC_HF_ALARM_RECORDS=0 alarm strand-risk P S U "HANDOFF-STRAND-RISK: legacy"
  [ "$status" -eq 0 ]
  [ -z "$(records)" ]
  # POSITIVE CONTROL beside the absence: the push DID happen, so the empty dir means "records off",
  # not "the helper did nothing".
  pushes | grep -q 'HANDOFF-STRAND-RISK: legacy' || false
}

@test "control: the SAME call without the kill switch DOES write a record" {
  # Two-sided, or the test above would pass on a helper that never records at all.
  alarm strand-risk P S U "HANDOFF-STRAND-RISK: legacy"
  [ -n "$(records)" ]
}

# ── 5. sanitization: the record survives what the details actually contain ────────────────────────

@test "a detail with quotes, newlines, tabs and a backslash still yields ONE parseable JSON line" {
  [ -x /usr/bin/python3 ] || skip "no /usr/bin/python3 to adjudicate JSON validity"
  # Not hypothetical: the recycle detail interpolates `$(cat "$CMDFILE")`, a whole relaunch command.
  alarm recycle-dead RECY-2 "" "" 'HANDOFF-RECYCLE-DEAD: he said "boom"
and then	a back\slash'
  [ "$status" -eq 0 ]
  [ "$(rec | wc -l | tr -d ' ')" -eq 1 ]
  /usr/bin/python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$(records)"
  # the text is MAPPED, not deleted — an unreadable detail is a lost alarm by another route
  rec | grep -q "he said 'boom'" || false
  rec | grep -q 'back/slash' || false

  # ORACLE CONTROL: the adjudicator above must be able to REJECT. An unsanitized body built from the
  # same detail has to fail, or `json.load` succeeding proves nothing about the sanitizer.
  printf '{"detail":"he said "boom""}\n' > "$BATS_TEST_TMPDIR/unsanitized.json"
  ! /usr/bin/python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \
      "$BATS_TEST_TMPDIR/unsanitized.json" 2>/dev/null || false
}

# ── 6. RED-PROOF: none of the above can pass against the pre-change artifact ──────────────────────

@test "RED-PROOF: hf_alarm does not exist in the pristine tree, so every case above was red" {
  local p; p="$(pristine_hf HANDOFF-STRAND-RISK)" || {
    echo "no revision of handoff-fire.sh in the last 200 carries the legacy silent push — the"
    echo "mutant source is gone and these controls can no longer discriminate"; false; }
  local mut="$BATS_TEST_TMPDIR/pristine-lib.sh"
  sed -n '/^hf_alarm()/,/^}/p' "$p" > "$mut"
  [ ! -s "$mut" ]                                       # the function is absent pre-change…
  # …and the extraction technique itself works, so the emptiness is the subject, not the sed.
  sed -n '/^hf_alarm()/,/^}/p' "$FIRE" > "$BATS_TEST_TMPDIR/live-lib.sh"
  [ -s "$BATS_TEST_TMPDIR/live-lib.sh" ]
  grep -q '^hf_alarm()' "$BATS_TEST_TMPDIR/live-lib.sh" || false
}

# ── 7. PER-SITE coverage: one mutant per site, anchored exactly once ──────────────────────────────
#
# Behavioural coverage above is on hf_alarm itself; these three pin that each SITE actually calls
# it. Driving the full watcher path per site would mean 180s of real sleeps, so the assertion is
# made at the call seam — but with the same discipline: the token anchors exactly once in each
# file, and the pre-change artifact must FAIL the identical oracle.

# A SITE, not a LINE. The first form of this oracle required the class token to sit ON the hf_alarm
# call, which is true only of a site making ONE claim. The husk site does not: it re-reads the pane
# at the failure instant and makes THREE (live / husk / unknown), so its token lives on a `_pg=`
# assignment inside a case arm and the single alarm below carries the class that arm chose. Pinning
# the old line-shape would have forced that tri-state to be REVERTED to satisfy a test — the
# assertion outliving its subject and becoming a guard on the bug. So the oracle moved up one
# level: the SITE must reach hf_alarm with THIS class and must not reach a silent cc-notify push.
# It keeps its teeth: the pre-change artifact has no hf_alarm at all, so it still fails — which the
# three tests below assert explicitly rather than assume.
site_is_converted() { # $1=file $2=class-token $3=hf_alarm class
  local line n from win
  [ "$(grep -c "$2" "$1")" -eq 1 ] || { echo "token $2 anchors $(grep -c "$2" "$1")× in $1, not once"; return 1; }
  line="$(grep "$2" "$1")"
  case "$line" in
    *'>/dev/null 2>&1 || true'*) echo "site $2 still carries the banned silent-push idiom"; return 1 ;;
  esac
  n="$(grep -n "$2" "$1" | cut -d: -f1)"
  from=$(( n > 6 ? n - 6 : 1 ))                 # a tri-state site decides the class just ABOVE the claim
  win="$(sed -n "${from},$((n + 30))p" "$1")"
  case "$win" in
    *"hf_alarm $3 "*) ;;                        # one-claim site: literal class at the call
    *"_cls=$3"*)                                # tri-state site: the arm decides, one call raises
      case "$win" in
        *'hf_alarm "$_cls"'*) ;;
        *) echo "site $2 sets _cls=$3 but never raises hf_alarm \"\$_cls\": $line"; return 1 ;;
      esac ;;
    *) echo "site $2 does not reach hf_alarm $3: $line"; return 1 ;;
  esac
  case "$win" in
    *'cc-notify'*'>/dev/null 2>&1 || true'*) echo "site $2 still reaches a silent cc-notify push"; return 1 ;;
  esac
  return 0
}

@test "SITE strand-risk: converted here, and the pre-change artifact fails the same oracle" {
  run site_is_converted "$FIRE" HANDOFF-STRAND-RISK strand-risk
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local p; p="$(pristine_hf HANDOFF-STRAND-RISK)" || { echo "no mutant source"; false; }
  run site_is_converted "$p" HANDOFF-STRAND-RISK strand-risk
  [ "$status" -ne 0 ]
}

@test "SITE husk-pane: converted here, and the pre-change artifact fails the same oracle" {
  run site_is_converted "$FIRE" HANDOFF-HUSK-PANE husk-pane
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local p; p="$(pristine_hf HANDOFF-HUSK-PANE)" || { echo "no mutant source"; false; }
  run site_is_converted "$p" HANDOFF-HUSK-PANE husk-pane
  [ "$status" -ne 0 ]
}

@test "SITE recycle-dead: converted here, and the pre-change artifact fails the same oracle" {
  run site_is_converted "$FIRE" HANDOFF-RECYCLE-DEAD recycle-dead
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local p; p="$(pristine_hf HANDOFF-RECYCLE-DEAD)" || { echo "no mutant source"; false; }
  run site_is_converted "$p" HANDOFF-RECYCLE-DEAD recycle-dead
  [ "$status" -ne 0 ]
}

@test "no collateral: the completion push keeps its own guard and is NOT an alarm site" {
  # D1 owns three sites. The completion push and the succession announce are a different mechanism
  # with a different failure model; converting them here would be scope no reviewer asked for.
  [ "$(grep -c 'if \[ -x "\$HOME/.claude/bin/cc-notify" \]' "$FIRE")" -eq 1 ]
  [ "$(grep -c '^    hf_alarm ' "$FIRE")" -eq 3 ]
}
