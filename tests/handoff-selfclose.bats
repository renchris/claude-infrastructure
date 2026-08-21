#!/usr/bin/env bats
# Regression guard for handoff-fire.sh SELF-CLOSE — the successor ENGAGEMENT gate + the close-instant
# re-verify + the light pre-close inventory (2026-07-24).
#
# The gaps these lock down:
#   1. ENGAGEMENT (not just liveness). The arm-time successor gate used to be a bare process-existence
#      check (ps | grep node|claude). A successor that BOOTED but never ingested work (cold-fire
#      auto-submit race, /goal-length rejection) passed it — the predecessor closed and the work
#      stranded in BOTH panes. The gate now ALSO requires the successor's transcript to show ≥1 real
#      assistant turn (reusing the spawn-path assistant_turn_in predicate). --successor-assume-engaged
#      skips ONLY that half (for a successor whose transcript is unreadable from this account).
#   2. CLOSE-INSTANT RE-VERIFY. The successor is verified once at arm time, but the detached watcher
#      closes up to ~180s later — a successor dying in that window stranded both panes. The watcher now
#      re-checks the successor's liveness immediately before the close; dead ⇒ do NOT close, page the
#      desk, leave the predecessor alive, exit nonzero.
#   3. PRE-CLOSE INVENTORY (light, WARN-only): unread mail in this session's inbox + peers this session
#      fired that have no live session.
#
# Technique mirrors tests/handoff-splitright.bats: PATH shims for osascript/ps/git (the gate path,
# driven via --dry-run so the gate runs but nothing is armed/closed), a HOME override with recording
# it2/cc-notify stubs (the __selfclose watcher path, invoked directly), and sed-extracted functions
# for the inventory unit checks. `bash "$HF" __selfclose …` runs the watcher body in the foreground —
# no detach, no real panes.

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. handoff-fire.sh's
  # capacity_gate reads the box's live loadavg AND (M10) its memory headroom, exiting 9 when either is
  # past its bar, so an unpinned suite goes RED purely because the box is busy — the corpus deciding a
  # verdict on machine state instead of on the tree. Both terms are pinned off here (they are the two
  # TERMS of one exit 9, handoff-fire.sh:4487); tests/handoff-fire-capacity-gate.bats is the ONE place
  # the gate runs ON, against synthetic inputs.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  # PIN THE TERMINAL. Every test in this file asserts the iTerm2 path and stubs `osascript`, but
  # handoff-fire.sh's primitives now branch on KITTY_WINDOW_ID (in_kitty), so run from inside kitty
  # the subject takes the kitty branch while only osascript is stubbed — and the suite's verdict
  # silently becomes a function of which terminal the developer is sitting in. Measured 2026-08-01:
  # unpinned from kitty this file went red; env-pinned it returns to its exact baseline count, and
  # baseline HEAD is green either way. The dependency PREDATES the branch (nothing read
  # KITTY_WINDOW_ID before); the branch only made it observable. Same pin, same reason, as
  # tests/it2-wrapper.bats and tests/cc-pane.bats. The kitty branches have their own coverage in
  # tests/handoff-fire-kitty.bats. Unset the real var AND pin the kill switch — both spellings.
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  # …AND PIN THE SEAM THE ENV PIN CANNOT REACH. The two lines above pin the DIVERT decision; identity
  # (kitty_identity) reads CC_TERM FIRST and only then falls back to them, and self-close resolves
  # that verdict at entry from the ancestry walk. So a developer running this suite from inside kitty
  # gets CC_TERM=kitty pinned under it, as_tty takes the kitty branch, and the osascript stub these
  # tests are built on is never consulted. Measured 2026-08-05 by simulating the resolved verdict
  # (`CC_TERM=kitty bats …`): 4 red here, 6 in handoff-selfclose-session-pin, 5 in
  # handoff-orphaned-assignee — on TRUNK as well as with the entry pin, i.e. pre-existing and purely
  # a function of which terminal the developer sits in. This is the same "PIN THE TERMINAL" intent as
  # above, spelled in the one place that actually governs identity.
  export CC_TERM=iterm2
  # handoff-fire.sh bounds every external iTerm2 call (osascript / it2 CLI / iterm2 python) through
  # hf_bounded — a timeout(1) wrapper — because a wedged iTerm2 API blocks them indefinitely. These
  # suites EXTRACT individual functions instead of sourcing the script, so that helper is not in
  # scope and an extracted function would die with "hf_bounded: command not found". A passthrough
  # keeps the extracted behaviour byte-identical and deterministic; the helper's OWN semantics
  # (bound applied, expiry -> 124, set-but-empty disable seam) are covered by
  # tests/handoff-fire-it2-bound.bats against the real definition.
  hf_bounded() { "$@"; }
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"

  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  OSA_GONE_DIR="$BATS_TEST_TMPDIR/gone"; mkdir -p "$OSA_GONE_DIR"
  PS_DEAD_DIR="$BATS_TEST_TMPDIR/dead";  mkdir -p "$PS_DEAD_DIR"
  PS_BLIND_DIR="$BATS_TEST_TMPDIR/blind"; mkdir -p "$PS_BLIND_DIR"
  export OSA_GONE_DIR PS_DEAD_DIR PS_BLIND_DIR

  # as_tty's query: `osascript - <uuid>` → print TTY-<uuid>, or empty when a gone-marker exists.
  cat > "$SHIM/osascript" <<'SH'
#!/usr/bin/env bash
uuid=""
while [ $# -gt 0 ]; do
  case "$1" in
    -e) shift 2 2>/dev/null || shift ;;   # -e '<script>' (delay/as_write) → no-op success
    -)  shift ;;
    *)  uuid="$1"; shift ;;
  esac
done
[ -n "$uuid" ] || exit 0
[ -n "${OSA_GONE_DIR:-}" ] && [ -e "$OSA_GONE_DIR/$uuid" ] && exit 0   # pane absent → empty tty
printf '%s' "TTY-$uuid"
exit 0
SH

  # liveness probe. pane_cc_state (handoff-fire.sh) reads a pane in THREE queries — the tty's root
  # pids, the descendant CLOSURE of those, and the tty's FOREGROUND process group — so a stub that
  # answers every `-t` with the word "claude" leaves the pid/closure forms unanswered and every pane
  # reads `unknown`, which is fail-safe and therefore refuses every gate below. Modelled per tty:
  #   shell   pid=P    ppid=1  comm=zsh
  #   claude  pid=P+1  ppid=P  comm=claude   — a DESCENDANT, never a root: this is exactly the
  #                                            `expect` shape (claude on a nested pty) that the
  #                                            closure leg exists to see.
  # A dead-marked tty ($PS_DEAD_DIR/<tty>) keeps its shell and loses the CC child ⇒ `shell` — the
  # real state of a pane whose CC exited, and still `!= cc`, so every dead-path test decides as
  # before. P is assigned per tty from a registry file so all forms agree across invocations.
  cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
reg="${PS_TTY_REG:-/nonexistent}"
root_pid() {                     # $1=tty → that pane's root pid, stable across invocations
  local t="$1" n
  n="$(grep -nxF -- "$t" "$reg" 2>/dev/null | head -1 | cut -d: -f1)"
  if [ -z "$n" ]; then printf '%s\n' "$t" >> "$reg"; n="$(wc -l < "$reg" | tr -d ' ')"; fi
  printf '%s' "$(( 700000 + n * 10 ))"
}
tty_live() { [ -z "${PS_DEAD_DIR:-}" ] || [ ! -e "$PS_DEAD_DIR/$1" ]; }
# BLIND is a THIRD state, not a synonym for dead. A tty with no readable processes is a tty we
# cannot READ (pane gone, bridge hiccup) — pane_cc_state calls that `unknown` and must never
# downgrade it to "shell-only", which is the fail-dangerous default. Without this the shim can only
# model live and exited, so `unknown` is unreachable and the branch that handles it is untestable.
tty_blind() { [ -n "${PS_BLIND_DIR:-}" ] && [ -e "$PS_BLIND_DIR/$1" ]; }

fmt="" tty="" pid="" pgid="" all=0
while [ $# -gt 0 ]; do
  case "$1" in
    -axo|-Ao) fmt="$2"; all=1; shift 2 ;;
    -o)       fmt="$fmt${2:-}"; shift 2 ;;
    -t)       tty="${2##*/}"; shift 2 ;;
    -p)       pid="${2:-}"; shift 2 ;;
    -g)       pgid="${2:-}"; shift 2 ;;
    *)        shift ;;
  esac
done

if [ "$all" = 1 ]; then                    # the closure: every registered pane, so any root resolves
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    p="$(root_pid "$t")"; printf '%s 1\n' "$p"
    tty_live "$t" && printf '%s %s\n' "$((p + 1))" "$p"
  done < "$reg"
  exit 0
fi
if [ -n "$pid" ]; then                     # per-pid identity, for pid_is_cc over the closure
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    p="$(root_pid "$t")"
    if   [ "$pid" = "$p" ];                              then c=zsh;    a=-zsh
    elif [ "$pid" = "$((p + 1))" ] && tty_live "$t";     then c=claude; a=/opt/cc/bin/claude
    else continue; fi
    case "$fmt" in *comm*) printf '%s\n' "$c" ;; *tty*) printf '%s\n' "$t" ;; *args*) printf '%s\n' "$a" ;; esac
    exit 0
  done < "$reg"
  exit 0                                   # unknown pid → no line, as ps does for a reaped one
fi
if [ -n "$pgid" ]; then                    # the foreground group: shells only (claude is on its pty)
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    p="$(root_pid "$t")"; [ "$pgid" = "$p" ] || continue
    case "$fmt" in *comm*) printf '%s zsh\n' "$p" ;; *) printf '%s\n' "$p" ;; esac
    exit 0
  done < "$reg"
  exit 0
fi
[ -n "$tty" ] || exit 0
tty_blind "$tty" && exit 0                 # unreadable tty → no rows at all → pane_cc_state=unknown
p="$(root_pid "$tty")"
case "$fmt" in                             # tpgid BEFORE pid — "tpgid" contains "pid"
  *tpgid*) printf '%s\n' "$p" ;;
  *pid*)   printf '%s\n' "$p" ;;
  # The pane is EXPECT-WRAPPED, so the pre-pane_cc_state probe (`-o comm= -t | grep node|claude`)
  # sees only `expect` and calls a LIVE pane dead. No caller reads this form any more; modelling it
  # honestly is what makes these tests DISCRIMINATING — a regression to the old one-line probe reads
  # every pane here as dead and turns the suite red, instead of passing on a stub that says "claude".
  *comm*)  tty_live "$tty" && printf '%s\n' "expect" ;;
  *)       printf '%s\n' "$p" ;;
esac
exit 0
SH

  # only `git rev-parse --is-inside-work-tree` is hit in the dry-run gate path — report "not a work
  # tree" so the dirty-tree guard is skipped (hermetic, independent of the test's CWD).
  cat > "$SHIM/git" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = rev-parse ] && exit 1
exit 0
SH
  chmod +x "$SHIM/osascript" "$SHIM/ps" "$SHIM/git"
  export PATH="$SHIM:$PATH"
  export PS_TTY_REG="$BATS_TEST_TMPDIR/ps-tty-reg"; : > "$PS_TTY_REG"

  REGDIR="$BATS_TEST_TMPDIR/reg";  mkdir -p "$REGDIR"
  PROJDIR="$BATS_TEST_TMPDIR/proj"; mkdir -p "$PROJDIR"
  export CC_REGISTRY_DIR="$REGDIR" CC_PROJECTS_DIRS="$PROJDIR"

  SUCC="SUCC-PANE"; PRED="PRED-PANE"; SUCC_SESS="succ-sess-0"
  printf '{"session_id":"%s"}\n' "$SUCC_SESS" > "$REGDIR/$SUCC.json"   # registry row → transcript name

  # ORIGIN GATE (2026-07-26): self-close is available ONLY to a session that was FIRED BY an
  # originator. Every test below models a fired PEER retiring — the only legitimate self-close —
  # so stamp $PRED as one. This was previously implicit; the gate makes it explicit.
  # The gate's own behaviour (refuse/allow/override) is covered by the tests at the end of this file.
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired"; mkdir -p "$CC_FIRED_DIR"
  # cwd is THIS PANE's cwd, not the hardcoded "/tmp" this fixture carried while nothing read the
  # field. The origin gate now tenancy-binds the stamp on cwd (item aba6bcbff6de), so a placeholder
  # path makes $PRED a stale tenant and every test below refuses at the ORIGIN gate before reaching
  # the successor gate it is actually about. $PWD is correct by construction: setup() and the `run`
  # it prepares share one cwd.
  printf '{"paneUUID":"%s","cwd":"%s","firedBy":"ORIGINATOR","firedAt":"2026-07-26T18:00:00Z","selfRetire":true}\n' \
    "$PRED" "$PWD" > "$CC_FIRED_DIR/$PRED.json"
}

# a fake HOME with it2 + cc-notify stubs that RECORD their args (for the watcher tests).
mk_home() { # $1=dir
  local h="$1"; mkdir -p "$h/.claude/bin" "$h/.claude/cc-roles"
  # `session list` must ENUMERATE the panes this fixture models. The __selfclose watcher now proves
  # the pane is reachable over the real transport before it acts on it (handoff-fire.sh pane_proof,
  # 2026-08-02 — a detached watcher that could not reach its pane closed the predecessor anyway).
  # Every test below models a HEALTHY close, i.e. a pane the watcher CAN reach, so a stub answering
  # the empty list would assert the opposite of the scenario it is set up for. $PANE_LIST lets an
  # individual test override the set; unset means "predecessor and successor both present".
  cat > "$h/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
if [ "${1:-}" = session ] && [ "${2:-}" = list ]; then
  if [ -n "${PANE_LIST:-}" ] && [ -f "$PANE_LIST" ]; then cat "$PANE_LIST"
  else printf '%s\n' PRED-PANE SUCC-PANE PREDSID SUCC-B; fi
  exit 0
fi
# $IT2_CLOSE_FAIL models the iTerm2 python-API socket refusing the CLOSE while every other verb
# still answers — the real 2026-07-26 failure (1 of 16 self-closes), and the only way to reach the
# post-close diagnosis branch. Inert unless a test sets it, so every existing case is unchanged.
if [ -n "${IT2_CLOSE_FAIL:-}" ] && [ "${1:-}" = session ] && [ "${2:-}" = close ]; then exit 1; fi
exit 0
SH
  cat > "$h/.claude/bin/cc-notify" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/ccnotify-calls.log"
exit 0
SH
  chmod +x "$h/.claude/bin/it2" "$h/.claude/bin/cc-notify"
  printf 'DESK-PANE\n' > "$h/.claude/cc-roles/desk"
}

# ── 1. ENGAGEMENT GATE ─────────────────────────────────────────────────────────────────────────

@test "gate: successor process-alive but transcript has ZERO assistant turns → exit 3, no close" {
  printf '%s\n' \
    '{"type":"user","message":{"content":"do the thing"}}' \
    '{"type":"system","subtype":"init"}' > "$PROJDIR/$SUCC_SESS.jsonl"   # born, never ran
  run bash "$HF" self-close --dry-run --session-id "$PRED" --successor "$SUCC"
  [ "$status" -eq 3 ]
  [[ "$output" == *"NEVER ENGAGED"* ]] || false
  [[ "$output" == *"--successor-assume-engaged"* ]] || false # recovery hint present
  ! [[ "$output" == *"dry run (self-close)"* ]]        # aborted BEFORE the plan → no close side of it
}

@test "gate: successor with a real assistant turn → engagement verified, gate passes" {
  printf '%s\n' \
    '{"type":"user","message":{"content":"go"}}' \
    '{"type":"assistant","message":{"content":"on it — starting the task"}}' > "$PROJDIR/$SUCC_SESS.jsonl"
  run bash "$HF" self-close --dry-run --session-id "$PRED" --successor "$SUCC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"successor engagement verified"* ]] || false
  [[ "$output" == *"dry run (self-close)"* ]]          # reached the plan → gate passed
}

@test "gate: --successor-assume-engaged skips the engagement check when the transcript is unreadable" {
  # No transcript at all → engagement would fail, but the flag skips ONLY that half.
  run bash "$HF" self-close --dry-run --session-id "$PRED" --successor "$SUCC" --successor-assume-engaged
  [ "$status" -eq 0 ]
  [[ "$output" == *"engagement check SKIPPED"* ]] || false
  [[ "$output" == *"dry run (self-close)"* ]]
}

@test "gate: --successor-assume-engaged still ENFORCES liveness (dead successor → exit 3)" {
  : > "$PS_DEAD_DIR/TTY-$SUCC"                          # pane resolves but no claude on its tty
  run bash "$HF" self-close --dry-run --session-id "$PRED" --successor "$SUCC" --successor-assume-engaged
  [ "$status" -eq 3 ]
  [[ "$output" == *"no live claude on successor"* ]]   # liveness half is NOT skipped by the flag
}

# ── 1b. TERMINAL IDENTITY AT THE SUCCESSOR GATE (item ec1bf0a497ba, 2026-08-05) ──────────────────
#
# e9cabc46 fixed `tty=none` by making identity honour the ANCESTRY verdict (kitty_identity) and
# pinning it before the pane→tty query at the /exit arm. But self-close asks as_tty THREE times and
# that pin sat at the LAST one, so on a KITTY_*-polluted iTerm2 box the two earlier queries kept the
# pre-fix behaviour. The successor-liveness gate is one of them — it runs ~160 lines earlier — so
# `--successor` still hard-aborted `exit 3 "successor pane … not found in iTerm2"` while the
# `--terminal` mode that skips this gate was the one verified working. A fired peer could retire
# only by declaring nothing continued its work; a genuine succession could not close at all.
#
# The remedy is the pin at self-close ENTRY: identity is a property of the PROCESS, so resolving it
# per-query is a fix that must be re-applied at every future call site, and an entry pin cannot be
# missed by one. It landed as d6fee16b (item 12f2524f8b83).
#
# COMPLEMENTARY, NOT DUPLICATE COVERAGE. tests/handoff-selfclose-terminal-pin-order.bats guards that
# fix STRUCTURALLY — the pin's line number precedes the first as_tty's — plus the identity predicate
# at function level. That is the sharper failure message, and it is blind to exactly one thing: a
# window it does not span. It anchors SC_SID → SUC_TTY, so a FOURTH as_tty added before the pin, or
# an identity correctly resolved and then defeated downstream, both keep it green. The two tests
# below close that by driving the real binary end to end — `bash "$HF" self-close --dry-run
# --successor` through the actual gate — and asserting on the user-visible verdict rather than on
# the arrangement of two lines. Both were verified RED against the pre-fix subject.

@test "gate: KITTY_* INHERITED into an iTerm2 pane — the successor gate still resolves its tty" {
  # THE 56A3C488 SHAPE, reproduced: a genuine iTerm2 pane whose env carries KITTY_WINDOW_ID/KITTY_PID
  # inherited from an iTerm2.app that was once launched out of a kitty pane, and a cc-in-kitty that
  # correctly reports "not ours" (exit 1). CC_TERM is UNSET on purpose — undoing setup's pin is what
  # makes this test about the subject resolving identity rather than the harness handing it over.
  local h="$BATS_TEST_TMPDIR/polluted-home"; mk_home "$h"; export HOME="$h"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$h/.claude/bin/cc-in-kitty"
  chmod +x "$h/.claude/bin/cc-in-kitty"
  export KITTY_WINDOW_ID=2 KITTY_PID=567
  unset IT2_WRAPPER_NO_KITTY CC_TERM
  # Hermetic kitty transport: an explicit non-executable CC_TERM_KITTY makes cc-kitty-bin REFUSE
  # (it never substitutes a different kitty), so the kitty branch fails deterministically instead of
  # querying the operator's live kitty and making this suite a function of their real windows.
  export CC_TERM_KITTY="$BATS_TEST_TMPDIR/no-such-kitty"
  export HANDOFF_TTY_RETRIES=1        # the kitty branch's miss is immediate; no need to wait it out

  printf '%s\n' \
    '{"type":"user","message":{"content":"go"}}' \
    '{"type":"assistant","message":{"content":"on it — starting the task"}}' > "$PROJDIR/$SUCC_SESS.jsonl"
  run bash "$HF" self-close --dry-run --session-id "$PRED" --successor "$SUCC"

  # DECISIVE ASSERTION LAST (the ordering lesson this repo already paid for): the abort string is
  # what the pre-fix subject emits, and the status is what it exits.
  [[ "$output" != *"not found in iTerm2"* ]] || false
  [[ "$output" == *"successor engagement verified"* ]] || false
  [ "$status" -eq 0 ]
}

@test "gate: a genuine kitty pane is NOT diverted to iTerm2 by the entry pin" {
  # Non-vacuity for the test above. If the entry pin resolved "iterm2" unconditionally it would
  # satisfy that assertion and silently break every real kitty box — the mirror of the 2026-07-31
  # outage. cc-in-kitty exit 0 = kitty IS our ancestor, so identity must stay kitty, the osascript
  # stub must NOT be consulted, and the gate must fail on the unreachable kitty transport.
  local h="$BATS_TEST_TMPDIR/kitty-home"; mk_home "$h"; export HOME="$h"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$h/.claude/bin/cc-in-kitty"
  chmod +x "$h/.claude/bin/cc-in-kitty"
  export KITTY_WINDOW_ID=2 KITTY_PID=567
  unset IT2_WRAPPER_NO_KITTY CC_TERM
  export CC_TERM_KITTY="$BATS_TEST_TMPDIR/no-such-kitty"
  export HANDOFF_TTY_RETRIES=1

  run bash "$HF" self-close --dry-run --session-id "$PRED" --successor "$SUCC"
  # RE-KEYED (item 87a515ed087e). The assertion here is a PROXY for "identity stayed kitty and the gate
  # therefore refused" — that is what makes this the non-vacuity control for the test above, and it is
  # unchanged. But the state it actually produces is a resolver that could not answer at all (the kitty
  # transport is deliberately unreachable), and the pre-split subject reported that as "not found in
  # iTerm2" — naming a terminal this session is not even using, about a pane nothing had looked at.
  # The refusal is the same refusal; only the verdict on it is now true.
  [ "$status" -eq 7 ]
  # `|| false` is not decoration: this assertion used to be the LAST line of the test, where bats
  # takes the test's exit status, and a bare `[[ ]]` was therefore live. Adding a line after it made
  # it DEAD — a conditional keyword mid-test does not abort (bats-assert-liveness.py caught exactly
  # this on the first run of the new diff).
  [[ "$output" == *"CANNOT TELL"* ]] || false
  [[ "$output" != *"not found in iTerm2"* ]] || false   # the false claim is GONE, not merely joined
}

# ── 1c. RESOLVER CANNOT TELL vs PANE ABSENT (item 87a515ed087e, 2026-08-20) ─────────────────────
#
# THE DEFECT. as_tty printed the empty string for two facts that are not the same fact: a query that
# SUCCEEDED and reported no such pane (a definite negative ABOUT THE PANE), and a query that never
# succeeded at all (a non-verdict about the RESOLVER, which has looked at nothing). The successor
# gate consumed only `[ -z "$SUC_TTY" ]`, so both produced one message — "successor pane <uuid> not
# found in iTerm2 — the continuation is NOT there; fix the uuid, or --terminal if truly nothing
# continues" — and both prescriptions in it are WRONG in the wedged half. `--terminal` retires this
# pane declaring that nothing continues the work, which over a live-but-unresolvable successor
# strands it with nothing looking for it; "fix the uuid" sends the operator hunting a correct id
# that was never rejected. This is 0c93f779ecfa one layer up: that row fixed exactly this conflation
# in cc-notify ("resolver unavailable" vs "target genuinely unknown") after it cost the desk six
# non-delivered advisories and two wrong diagnoses, and item 87a515ed087e asked for the same split
# here. The sibling gate immediately below (successor_pin, rc 0/1/2) already had three states; the
# non-verdict was destroyed one layer above it, before it could ever arrive.
#
# THE POLARITY DOES NOT MOVE. Both arms still REFUSE — this close is irreversible and gated on
# positive proof, so a non-verdict can never license it. What splits is the rc and the diagnosis.
#
# The two arms are driven by DIFFERENT seams, which is what makes them discriminable at all:
#   WEDGED  HANDOFF_TTY_FAIL_FILE — the query itself returns non-zero, every time, past the budget.
#   ABSENT  $OSA_GONE_DIR/<uuid>  — the query SUCCEEDS and prints nothing (setup's osascript shim).

@test "RED-PROOF wedged resolver: exit 7 CANNOT TELL, and BOTH wrong prescriptions are withdrawn" {
  # Pre-fix this exits 3 with the absent branch's message. Every assertion below was verified RED
  # against the pre-split subject.
  local failf="$BATS_TEST_TMPDIR/ttyfail-wedge"; printf '99\n' > "$failf"
  run env HANDOFF_TTY_FAIL_FILE="$failf" HANDOFF_TTY_RETRIES=4 HANDOFF_TTY_RETRY_SLEEP_S=0 \
      bash "$HF" self-close --dry-run --session-id "$PRED" --successor "$SUCC"

  # PREMISE CONTROL FIRST — the fixture must actually have WEDGED the resolver. If the seam were not
  # consumed the query would have succeeded and this case would be about the resolved path instead,
  # with every assertion below true of nothing (memory: harness-default-collapses-the-states-under-test).
  #
  # A FLOOR AND A NOT-DRY CHECK, never `-eq <exact>`. This path crosses MORE than one as_tty site —
  # verify_self_pane's ownership probe runs first and burns its own budget (measured: 8 consumed for
  # a 4-attempt budget, i.e. two sites), so an exact count would red on the subject's own growth the
  # next time a site is added and never on a regression (memory:
  # exact-count-assertion-tripwires-its-own-subject). The floor is what the premise actually needs.
  local left; left="$(cat "$failf")"
  [ "$left" -lt 99 ]                                       # the seam WAS exercised
  [ "$left" -gt 0 ]                                        # …and never ran DRY — a dry file lets a
                                                           # later query SUCCEED, silently changing
                                                           # the state under test out from under it
  [ "$(( 99 - left ))" -ge 4 ]                             # at least one FULL budget burned to exhaustion

  [ "$status" -eq 7 ]
  [[ "$output" == *"CANNOT TELL"* ]] || false
  [[ "$output" == *"NOT a finding about the successor"* ]] || false
  # THE TWO RETIRED PRESCRIPTIONS. These are the harm, not the wording: an operator acting on either
  # one damages a succession that was never shown to be broken.
  [[ "$output" == *"Do NOT pass --terminal on this verdict"* ]] || false
  [[ "$output" != *"the continuation is NOT there"* ]] || false
  [[ "$output" != *"fix the uuid"* ]] || false
  ! [[ "$output" == *"dry run (self-close)"* ]] || false   # still REFUSED — polarity unmoved
}

@test "BY DESIGN GREEN both sides: a resolver that ANSWERS 'no such pane' keeps exit 3, byte-identical" {
  # NOT a red-proof case, deliberately, and named so no reader mistakes it for one. Its whole job is
  # to prove the split did not move the DEFINITE NEGATIVE — the state that was always classified
  # correctly. It passes pre-fix and post-fix alike; a diff that "fixed" the wedged half by making
  # every empty tty a cannot-tell would go red here, which is the only way this case can fail.
  : > "$OSA_GONE_DIR/$SUCC"                                # query succeeds, prints nothing
  run bash "$HF" self-close --dry-run --session-id "$PRED" --successor "$SUCC"
  [ "$status" -eq 3 ]
  [[ "$output" == *"not found in iTerm2"* ]] || false
  [[ "$output" == *"the continuation is NOT there"* ]] || false
  [[ "$output" != *"CANNOT TELL"* ]] || false
}

@test "DISCRIMINATION: a TRANSIENT failure inside the retry budget still RESOLVES — 7 is exhaustion, not any failure" {
  # Non-vacuity for the red-proof case. If exit 7 fired on any failed query the load-robustness the
  # retry loop exists for would be gone — a bridge hiccup would abort a healthy close, which is the
  # T-P2-1 flake in the other direction. Two failures inside a budget of four must still resolve and
  # let the gate proceed to its real verdict.
  # 6 failures against a budget of 4, and TWO as_tty sites on this path: the ownership probe upstream
  # burns its full 4 (it fails open — "self-identity UNPROVEN … proceeding"), leaving exactly 2 for
  # the SUCCESSOR gate, which must absorb them and resolve on its third attempt. Sized this way on
  # purpose: a smaller count is swallowed entirely upstream and the case would never exercise the
  # gate it names at all.
  local failf="$BATS_TEST_TMPDIR/ttyfail-transient"; printf '6\n' > "$failf"
  printf '%s\n' \
    '{"type":"user","message":{"content":"go"}}' \
    '{"type":"assistant","message":{"content":"on it"}}' > "$PROJDIR/$SUCC_SESS.jsonl"
  run env HANDOFF_TTY_FAIL_FILE="$failf" HANDOFF_TTY_RETRIES=4 HANDOFF_TTY_RETRY_SLEEP_S=0 \
      bash "$HF" self-close --dry-run --session-id "$PRED" --successor "$SUCC"
  [ "$(cat "$failf")" -eq 0 ]                              # the seam WAS exercised — 2 real failures
  [ "$status" -eq 0 ]
  [[ "$output" != *"CANNOT TELL"* ]] || false
  [[ "$output" == *"dry run (self-close)"* ]] || false     # reached the plan → gate passed
}

# ── 2. CLOSE-INSTANT RE-VERIFY (the __selfclose watcher) ─────────────────────────────────────────

@test "watcher: successor DEAD at close-instant → no close, desk paged, predecessor left alive" {
  H="$BATS_TEST_TMPDIR/home-abort"; mk_home "$H"
  : > "$PS_DEAD_DIR/TTY-A"                              # predecessor already exited → skip wait loop
  : > "$PS_DEAD_DIR/TTY-B"                              # successor DIED before the close instant
  run env HOME="$H" bash "$HF" __selfclose PREDSID TTY-A SUCC-B TTY-B
  [ "$status" -ne 0 ]
  [[ "$output" == *"ABORTED at close-instant"* ]] || false
  [[ "$output" == *"NO LONGER ALIVE"* ]] || false
  # The invariant is "no CLOSE", not "no it2 call at all". Since 2026-08-02 the watcher's second act
  # is a READ-ONLY `session list` reachability probe, so the log now exists on every path — asserting
  # its absence would test the probe's existence rather than the predecessor's survival, and would go
  # red for a change that makes the close strictly safer.
  ! grep -q "session close" "$H/it2-calls.log" 2>/dev/null || false # predecessor alive
  grep -q "HANDOFF-STRAND-RISK" "$H/ccnotify-calls.log"  # desk paged (best-effort)
}

@test "watcher: successor ALIVE at close-instant → closes predecessor + focuses successor, no page" {
  H="$BATS_TEST_TMPDIR/home-ok"; mk_home "$H"
  : > "$PS_DEAD_DIR/TTY-A"                              # predecessor exited → skip wait loop
  # (no dead-marker for TTY-B → successor alive at the close instant)
  run env HOME="$H" bash "$HF" __selfclose PREDSID TTY-A SUCC-B TTY-B
  [ "$status" -eq 0 ]
  grep -q "session close -f -s PREDSID" "$H/it2-calls.log"
  grep -q "session focus SUCC-B" "$H/it2-calls.log"
  [ ! -f "$H/ccnotify-calls.log" ]                     # happy path pages nobody
  [[ "$output" == *"focus handed to successor SUCC-B"* ]]
}

# ── 2b. A FAILED CLOSE MUST DIAGNOSE, NOT ASSUME (item 71909cbeee08) ─────────────────────────────
# When the 4 close attempts are exhausted this branch used to state, unconditionally, "claude
# exited, pane still open … the session is already gone" — to the operator AND to the desk page.
# It asserted two facts it had never checked. On 2026-07-30 (session c5f80b8b) both were FALSE: the
# session was live and answering. The evidence was already in hand and thrown away — the wait loop
# 50 lines above computes cc_alive and prints "⚠ CC still alive" on the way past.
#
# The states have OPPOSITE remedies, which is why one message cannot serve all three. A husk: close
# it, nothing is at risk. A LIVE session behind a failed close: do not touch it — and an operator
# who believes the old page closes a pane with work in it. "Unknown" is its own answer and must not
# be rounded to either neighbour (pane_cc_state's own rule: an unreadable tty is not a death).
#
# The verdict is re-read AT THE FAILURE INSTANT, ~190s and four attempts after the loop's, so these
# cases pin the branch and not a stale variable.

@test "close fails + CC CONFIRMED GONE → the husk wording, and it may say the session is gone" {
  H="$BATS_TEST_TMPDIR/home-husk"; mk_home "$H"
  : > "$PS_DEAD_DIR/TTY-A"                              # CC exited → pane_cc_state(TTY-A)=shell
  run env HOME="$H" IT2_CLOSE_FAIL=1 bash "$HF" __selfclose PREDSID TTY-A
  [[ "$output" == *"is a HUSK"* ]] || false
  [[ "$output" == *"claude confirmed gone"* ]] || false
  [[ "$output" == *"the session is already gone"* ]] || false
  grep -q "HANDOFF-HUSK-PANE" "$H/ccnotify-calls.log"
  grep -q "CONFIRMED gone" "$H/ccnotify-calls.log"
}

@test "close fails + CC STILL RUNNING → says NOT gone, and the page says NOT a husk" {
  # THE REGRESSION ITSELF. Pre-fix this printed "claude exited … the session is already gone" and
  # paged "session is gone" over a session that was still answering. The grace seam is what makes
  # the branch reachable at all: it is only entered after the wait loop gives up on a LIVE CC.
  H="$BATS_TEST_TMPDIR/home-live"; mk_home "$H"
  # no dead-marker for TTY-A → CC alive throughout, so the loop expires rather than breaking
  run env HOME="$H" IT2_CLOSE_FAIL=1 HF_SELFCLOSE_GRACE_S=1 HF_SELFCLOSE_GRACE_STEP_S=1 \
      bash "$HF" __selfclose PREDSID TTY-A
  [[ "$output" == *"CC still alive"* ]] || false        # the loop's own verdict, unchanged
  [[ "$output" == *"the session is NOT gone"* ]] || false
  [[ "$output" == *"STILL RUNNING"* ]] || false
  # the two false assertions must be ABSENT, not merely outweighed by a truer sentence beside them
  ! [[ "$output" == *"the session is already gone"* ]] || false
  ! [[ "$output" == *"is a HUSK"* ]] || false
  grep -q "HANDOFF-CLOSE-FAILED-LIVE" "$H/ccnotify-calls.log"
  grep -q "NOT a husk" "$H/ccnotify-calls.log"
  ! grep -q "HANDOFF-HUSK-PANE" "$H/ccnotify-calls.log" || false
}

@test "close fails + tty UNREADABLE → says UNKNOWN, and claims neither death nor life" {
  # The third state, and the one an over-eager fix would collapse into "husk" (its neighbour on the
  # fail-safe side) — which is how the original defect was written in the first place.
  H="$BATS_TEST_TMPDIR/home-unk"; mk_home "$H"
  : > "$PS_BLIND_DIR/TTY-A"                             # tty readable by nobody → unknown
  run env HOME="$H" IT2_CLOSE_FAIL=1 HF_SELFCLOSE_GRACE_S=1 HF_SELFCLOSE_GRACE_STEP_S=1 \
      bash "$HF" __selfclose PREDSID TTY-A
  [[ "$output" == *"is UNKNOWN"* ]] || false
  ! [[ "$output" == *"the session is already gone"* ]] || false
  ! [[ "$output" == *"STILL RUNNING"* ]] || false
  grep -q "HANDOFF-CLOSE-FAILED-UNKNOWN" "$H/ccnotify-calls.log"
}

@test "grace seam is INERT unless set — the shipped bound is still 180s/5s" {
  # A seam that silently changed the production grace would be a worse bug than the one it tests.
  grep -qF 'HF_SELFCLOSE_GRACE_S:-180' "$HF"
  grep -qF 'HF_SELFCLOSE_GRACE_STEP_S:-5' "$HF"
}

# ── 3. PRE-CLOSE INVENTORY (light, WARN-only) ────────────────────────────────────────────────────

@test "inventory: WARNs when this session has unread mail (a)" {
  eval "$(sed -n '/^selfclose_inventory_warn() {/,/^}/p' "$HF")"
  mailbox_pending_count() { echo 2; }                  # stub the shared cursor primitive
  FIRED_DIR=""                                         # skip (b)
  run selfclose_inventory_warn "MYSID" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 unread message(s)"* ]]
}

@test "inventory: WARNs on a peer this session fired that has no live session (b)" {
  eval "$(sed -n '/^selfclose_inventory_warn() {/,/^}/p' "$HF")"
  mailbox_pending_count() { echo 0; }                  # no unread → (a) silent
  as_tty() { echo ""; }                                # fired pane unresolvable → orphan
  FIRED_DIR="$BATS_TEST_TMPDIR/fired"; mkdir -p "$FIRED_DIR"
  printf '{"paneUUID":"DEADPEER","firedBy":"MYSID"}\n'   > "$FIRED_DIR/DEADPEER.json"
  printf '{"paneUUID":"OTHERPEER","firedBy":"SOMEONE"}\n' > "$FIRED_DIR/OTHERPEER.json"   # not ours
  run selfclose_inventory_warn "MYSID" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 peer(s) fired by this session"* ]]
}

# RED-PROOF for the orphan probe itself. The test above resolves the pane to "" and so takes the
# orphan branch WITHOUT ever reaching the liveness read — which is why the pre-pane_cc_state probe
# survived here unnoticed. This is the case that separates them: a peer that IS alive, with its CC
# behind `expect`'s nested pty, so the pane's own tty carries only `expect`. The old one-line probe
# reads that live peer as DEAD and warns the operator its work is stranded; pane_cc_state crosses
# the nested pty via the descendant closure and stays silent.
@test "inventory: a LIVE peer behind expect's nested pty is NOT counted as an orphan" {
  eval "$(sed -n '/^selfclose_inventory_warn() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^pid_is_cc() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^pane_cc_state() {/,/^}/p' "$HF")"
  mailbox_pending_count() { echo 0; }                  # no unread → (a) silent
  as_tty() { echo "TTY-LIVEPEER"; }                    # resolves, and that pane HAS a live CC
  FIRED_DIR="$BATS_TEST_TMPDIR/fired"; mkdir -p "$FIRED_DIR"
  printf '{"paneUUID":"LIVEPEER","firedBy":"MYSID"}\n' > "$FIRED_DIR/LIVEPEER.json"
  run selfclose_inventory_warn "MYSID" ""
  [ "$status" -eq 0 ]
  [[ "$output" != *"fired by this session"* ]]
}

@test "inventory: silent when nothing is pending" {
  eval "$(sed -n '/^selfclose_inventory_warn() {/,/^}/p' "$HF")"
  mailbox_pending_count() { echo 0; }
  FIRED_DIR="$BATS_TEST_TMPDIR/fired-empty"; mkdir -p "$FIRED_DIR"
  run selfclose_inventory_warn "MYSID" ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── ORIGIN GATE (operator invariant, 2026-07-26) ────────────────────────────────────────────────
# "A main session should and wouldn't self-close on itself, the same way a team LEAD never self
# closes itself while in progress or when its done." Self-close belongs ONLY to a session with an
# ORIGINATOR to hand back to. cc-classify:596 already refuses to REAP an unstamped (operator-launched)
# pane; until this gate, that same pane could still kill ITSELF via --terminal. Oracle = the
# fired-peer stamp handoff-fire writes at fire time (mark_fired_peer).

@test "origin gate: an UNSTAMPED (operator-launched) session is REFUSED --terminal" {
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired-none"; mkdir -p "$CC_FIRED_DIR"
  run bash "$HF" self-close --terminal --session-id "ORIGIN-1111" --dry-run
  [ "$status" -eq 2 ] || false
  echo "$output" | grep -qi "ORIGIN session" || false
  echo "$output" | grep -qi "no fired-peer stamp" || false
}

@test "origin gate: an unstamped session is refused --successor too (not just --terminal)" {
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired-none2"; mkdir -p "$CC_FIRED_DIR"
  run bash "$HF" self-close --successor "SOMEPANE-9999" --session-id "ORIGIN-2222" --dry-run
  [ "$status" -eq 2 ] || false
  echo "$output" | grep -qi "ORIGIN session" || false
}

@test "origin gate: a FIRED PEER (stamp present) passes the origin gate" {
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired-yes"; mkdir -p "$CC_FIRED_DIR"
  # The fixture's cwd is THIS PANE's cwd, and that is load-bearing rather than cosmetic. It used to
  # be a hardcoded "/tmp" and a firedAt ten days in the past, which is precisely the stale-tenancy
  # stamp the gate now refuses (item aba6bcbff6de) — so on the fixed subject this test kept passing
  # for the WRONG REASON: the new refusal does not contain the literal "ORIGIN session", so the
  # grep below could not see it and a refused close read as a pass. Pinning the fixture to the real
  # cwd restores what the test's own name claims it asserts.
  PEERWT="$BATS_TEST_TMPDIR/peer-wt"; mkdir -p "$PEERWT"; cd "$PEERWT"
  printf '{"paneUUID":"PEER-3333","cwd":"%s","firedBy":"ORIGIN-1111","firedAt":"2026-07-26T18:00:00Z","selfRetire":true}\n' \
    "$PEERWT" > "$CC_FIRED_DIR/PEER-3333.json"
  run bash "$HF" self-close --terminal --session-id "PEER-3333" --dry-run
  # It may still stop at a LATER gate (dirty tree, registry) — it must NOT stop at the origin gate.
  # `[ ]` form, not `&& false`: a non-final `A && B` is errexit-EXEMPT, so the original could never
  # fail. `[ ]` is live in ANY position, which is what the liveness ratchet is asking for.
  # Both refusal spellings are matched, so a future third one cannot make this vacuous again.
  [ "$(echo "$output" | grep -ciE "ORIGIN session|DIFFERENT session")" -eq 0 ]
  [ "$status" -ne 2 ] || echo "$output" | grep -qviE "ORIGIN session|DIFFERENT session" || false
}

# ── STAMP TENANCY (2026-08-05, item aba6bcbff6de) ────────────────────────────────────────────────
# The gate above asked one question of the stamp — is the file non-empty — while cc-classify, which
# the gate names as its model, has required TENANCY since 2026-07-24 (bin/cc-classify:378). Two
# sibling auditors, one state, two state models: the reaper refuses to reap what the self-killer
# will close. Under iTerm2's 128-bit UUIDs that was safe by accident; kitty numbers windows with
# small integers and REUSES them, so a stale stamp can authorise a live, unrelated pane's suicide.
# Measured 2026-08-05: cc-fired held numeric stamps at 33…497 while the live kitty was issuing ids
# 2–37, with id 33 simultaneously a live window and an open stamp.
#
# RED-PROOF, stated so a later reader does not mistake green for coverage. Against a pristine
# `git archive HEAD` tree only TWO of the seven below go red — "a stamp for a DIFFERENT cwd" and
# "an OPEN stamp … is NAMED". They are the ones asserting NEW behaviour. The other five are
# CONTRACT-PRESERVATION tests and are green on both trees BY DESIGN: they assert that the tenancy
# check ABSTAINS everywhere it cannot prove staleness, which is the property that stops this fix
# becoming the false negative it was written to cure. A green-on-both test here is the point, not a
# gap — but only because these two red ones exist beside it.

@test "tenancy: a stamp for a DIFFERENT cwd is a stale tenant → REFUSED (kitty id reuse)" {
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired-stale"; mkdir -p "$CC_FIRED_DIR"
  OTHER="$BATS_TEST_TMPDIR/some-other-worktree"; mkdir -p "$OTHER"
  HERE="$BATS_TEST_TMPDIR/this-pane"; mkdir -p "$HERE"; cd "$HERE"
  printf '{"paneUUID":"28","cwd":"%s","firedBy":"2","firedAt":"2026-08-01T10:00:00Z","selfRetire":true,"closedAt":null}\n' \
    "$OTHER" > "$CC_FIRED_DIR/28.json"
  run bash "$HF" self-close --terminal --session-id "28" --dry-run
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "DIFFERENT session" || false
  # The refusal must name BOTH sides — a mismatch the operator cannot see is not a diagnosis.
  echo "$output" | grep -qF "$OTHER" || false
  echo "$output" | grep -qF "$HERE" || false
  # …and must NOT misdiagnose it as an origin session, which points at the wrong remedy.
  [ "$(echo "$output" | grep -ci "this is an ORIGIN session")" -eq 0 ]
}

@test "tenancy: ABSTAINS when the stamp has no cwd — unknown keeps the pre-change behaviour" {
  # The calibration control. This change may only refuse what it can PROVE stale; everything
  # unresolvable must behave exactly as it did before, or it has invented a new false negative —
  # the mirror of the bug it fixes. A stamp with no cwd field is unknown, and unknown passes.
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired-nocwd"; mkdir -p "$CC_FIRED_DIR"
  HERE="$BATS_TEST_TMPDIR/pane-nocwd"; mkdir -p "$HERE"; cd "$HERE"
  printf '{"paneUUID":"41","firedBy":"2","firedAt":"2026-08-01T10:00:00Z","selfRetire":true}\n' \
    > "$CC_FIRED_DIR/41.json"
  run bash "$HF" self-close --terminal --session-id "41" --dry-run
  [ "$(echo "$output" | grep -ciE "ORIGIN session|DIFFERENT session")" -eq 0 ]
}

@test "tenancy: a stamp whose cwd no longer EXISTS is unknown, not stale (worktree GC'd)" {
  # Same calibration, the other unresolvable shape: a peer whose worktree was removed after it was
  # fired must still be able to retire. Only a POSITIVE refutation — both paths resolve and differ —
  # may refuse.
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired-gonewt"; mkdir -p "$CC_FIRED_DIR"
  HERE="$BATS_TEST_TMPDIR/pane-gonewt"; mkdir -p "$HERE"; cd "$HERE"
  printf '{"paneUUID":"42","cwd":"%s/removed-worktree","firedBy":"2","firedAt":"2026-08-01T10:00:00Z","selfRetire":true}\n' \
    "$BATS_TEST_TMPDIR" > "$CC_FIRED_DIR/42.json"
  run bash "$HF" self-close --terminal --session-id "42" --dry-run
  [ "$(echo "$output" | grep -ciE "ORIGIN session|DIFFERENT session")" -eq 0 ]
}

@test "tenancy: /tmp vs /private/tmp is the SAME directory, not a mismatch" {
  # macOS reaches one directory by two paths. A raw string compare would manufacture a stale verdict
  # and refuse a genuine peer, so both sides are resolved before they are compared.
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired-symlink"; mkdir -p "$CC_FIRED_DIR"
  [ -d /private/tmp ] || skip "no /private/tmp on this platform"
  cd /tmp
  printf '{"paneUUID":"43","cwd":"/private/tmp","firedBy":"2","firedAt":"2026-08-01T10:00:00Z","selfRetire":true}\n' \
    > "$CC_FIRED_DIR/43.json"
  run bash "$HF" self-close --terminal --session-id "43" --dry-run
  [ "$(echo "$output" | grep -ciE "ORIGIN session|DIFFERENT session")" -eq 0 ]
}

@test "tenancy: CC_SELFCLOSE_TENANCY=0 reverts to bare presence (R8 kill switch)" {
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired-killswitch"; mkdir -p "$CC_FIRED_DIR"
  OTHER="$BATS_TEST_TMPDIR/elsewhere"; mkdir -p "$OTHER"
  HERE="$BATS_TEST_TMPDIR/pane-ks"; mkdir -p "$HERE"; cd "$HERE"
  printf '{"paneUUID":"44","cwd":"%s","firedBy":"2","firedAt":"2026-08-01T10:00:00Z","selfRetire":true}\n' \
    "$OTHER" > "$CC_FIRED_DIR/44.json"
  CC_SELFCLOSE_TENANCY=0 run bash "$HF" self-close --terminal --session-id "44" --dry-run
  [ "$(echo "$output" | grep -ciE "ORIGIN session|DIFFERENT session")" -eq 0 ]
}

@test "orphan diagnostic: an OPEN stamp for this cwd under another id is NAMED (still refused)" {
  # The mirror failure. A resume, a crash-recreate or a kitty restart re-numbers the pane, orphaning
  # a real peer's stamp under its OLD id. The gate still refuses — a cwd is not exclusive — but
  # "no stamp anywhere" and "your stamp is at 28.json" send the operator to different remedies.
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired-orphan"; mkdir -p "$CC_FIRED_DIR"
  HERE="$BATS_TEST_TMPDIR/orphan-wt"; mkdir -p "$HERE"; cd "$HERE"
  printf '{"paneUUID":"28","cwd":"%s","firedBy":"2","firedAt":"2026-08-05T10:00:00Z","selfRetire":true,"closedAt":null}\n' \
    "$HERE" > "$CC_FIRED_DIR/28.json"
  run bash "$HF" self-close --terminal --session-id "31" --dry-run   # renumbered: 28 → 31
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "ORIGIN session" || false
  echo "$output" | grep -qF "28.json" || false
  echo "$output" | grep -qi "orphaned, not missing" || false
}

@test "orphan diagnostic: a CLOSED stamp is spent and is never offered as evidence" {
  # The control that stops the diagnostic becoming a second false positive: a peer that already
  # retired leaves a closedAt-stamped record behind, and a LATER pane reusing that worktree must not
  # be told a peer was fired for it.
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired-closed"; mkdir -p "$CC_FIRED_DIR"
  HERE="$BATS_TEST_TMPDIR/reused-wt"; mkdir -p "$HERE"; cd "$HERE"
  printf '{"paneUUID":"28","cwd":"%s","firedBy":"2","firedAt":"2026-08-05T10:00:00Z","selfRetire":true,"closedAt":"2026-08-05T11:00:00Z"}\n' \
    "$HERE" > "$CC_FIRED_DIR/28.json"
  run bash "$HF" self-close --terminal --session-id "31" --dry-run
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "ORIGIN session" || false
  [ "$(echo "$output" | grep -c "28.json")" -eq 0 ]
}

@test "origin gate: an EMPTY stamp file is treated as absent (fail-safe, refuse)" {
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired-empty-stamp"; mkdir -p "$CC_FIRED_DIR"
  : > "$CC_FIRED_DIR/PEER-4444.json"          # zero-byte ⇒ unusable ⇒ must NOT authorise a close
  run bash "$HF" self-close --terminal --session-id "PEER-4444" --dry-run
  [ "$status" -eq 2 ] || false
  echo "$output" | grep -qi "ORIGIN session" || false
}

@test "origin gate: --allow-origin-close is the documented, loud override" {
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired-none3"; mkdir -p "$CC_FIRED_DIR"
  run bash "$HF" self-close --terminal --session-id "ORIGIN-5555" --allow-origin-close --dry-run
  # Was `&& false` followed by a bare `true` — dead twice over: errexit-exempt in non-final
  # position, and the trailing `true` reset the status even if it had not been.
  [ "$(echo "$output" | grep -ci "ORIGIN session")" -eq 0 ]
}
