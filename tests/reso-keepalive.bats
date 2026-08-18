#!/usr/bin/env bats
# bin/reso-keepalive — backlog 6ab41e312a13, the other half of stranded commit 410f920c9.
#
# WHAT WAS STRANDED. 410f920c9 tracked BOTH resume actuators; only `bin/reso-resume-one` reached
# origin/main. `bin/reso-keepalive` did not, so it kept living untracked at
# ~/.reso/bin/reso-keepalive while scripts/boot-resume.sh:85-86 resolved and ran it — outside the
# ship gate, outside shellcheck, outside every suite. That is the whole class this file closes: an
# actuator nothing can lint is an actuator nothing can detect rot in, and the on-disk copy had
# rotted exactly as predicted (it is still the pre-410f920c zsh version, with the frozen literal).
#
# THE TWO PROPERTIES ASSERTED HERE are the two the recovered file's own header claims, because a
# claim in a comment is not a mechanism — nothing executes a comment (memory:
# contract-prose-can-understate-the-mechanism, inverted: here the prose OVERstates until pinned).
#
#   1. MARKERS is env-overridable and an EMPTY list EXITS. It used to be a frozen literal — the 12
#      worktrees of the 2026-07-04 recovery, baked in where no caller could reach them, and
#      boot-resume.sh passes only the interval. Sampled 2026-08-09, some of those worktrees no
#      longer existed: a nudger aimed at nothing, looping forever, silently.
#   2. iTerm2 is addressed by BUNDLE ID behind an is-running guard, never by name. The name form
#      resolves via CFBundleName, loses terminology when the app is not already running (-2740 /
#      -2741), and can LAUNCH a terminal on a headless box. This is the ratchet
#      tests/iterm2-appname-lint.bats exists to hold, and it could not see this file while it was
#      untracked.
#
# The nudge loop itself is deliberately NOT executed: it is an infinite `while :` that sends
# keystrokes into live panes. A suite that ran it would type into the operator's real sessions.
# What is testable without actuating is the guard that decides whether the loop is entered at all,
# and the addressing form — so that is exactly what is tested.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # The kitty arm makes bin/it2-kitty a subject of this suite, and it READS variables this repo
  # INJECTS into every pane it launches — so every descendant of a fired pane carries them, bats
  # included when an agent runs this suite from the pane that fired it. Inheriting one makes the
  # suite go red exactly THERE and green everywhere else, which reads as a genuine trunk red.
  # `unset`, never the inherited-value allowlist: scripts/test-hermeticity-lint.sh says so verbatim.
  unset CC_PANE_CMD_INTERACTIVE CC_PANE_CMD
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  KA="$REPO/bin/reso-keepalive"
  export CC_KEEPALIVE_LOG="$BATS_TEST_TMPDIR/keepalive.log"
  # Own the actuator seam: with a stub it2 on the path the script resolves, no case can reach a
  # real pane even if the loop were entered.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$CC_KEEPALIVE_LOG.it2"\n' > "$BATS_TEST_TMPDIR/bin/it2"
  chmod +x "$BATS_TEST_TMPDIR/bin/it2"
  export CC_IT2_BIN="$BATS_TEST_TMPDIR/bin/it2"
}

# ── THE KITTY ARM (backlog 71c2c19d6c63 · a94c9e5722f7) AND THE THIRD SKIP PREDICATE (d591c8d990b5)
#
# The rows: this actuator was iTerm2-only, so on a kitty fleet the whole idle-pane keepalive arm was
# INERT — each recovered session finished a turn, rendered a close block and idled, and a human had
# to re-nudge every ~30 min, which is exactly the 8h-unattended case the arm exists to remove.
#
# CAUSE CORRECTION, MEASURED HERE (71c2c19d6c63 names `bin/it2` as already diverting to kitty):
# there is no `bin/it2` in this repo. The divert lives in `bin/it2-wrapper` and covers `session
# split` / `session close` for teammate panes — not a send path — and the kitty adapter is a third
# file, `bin/it2-kitty`. More to the point, none of that was ever reachable from here: this script
# resolves `CC_IT2_BIN` to the REAL python it2 binary by default, which bypasses the wrapper AND the
# adapter. "0 kitty references" understated it — the send path resolved PAST every divert.
#
# WHY THESE CASES CAN RUN THE LOOP, WHICH THE HEADER ABOVE SAYS IT DELIBERATELY DOES NOT.
# The header's reason is that the loop types keystrokes into live panes. Both actuator seams are
# owned here — `CC_IT2_BIN` (already, since the original suite) and `CC_KEEPALIVE_KITTY_BIN` — so no
# case can reach a real pane, and `CC_KEEPALIVE_ONCE=1` bounds it to a single cycle. The unbounded
# `while :` is still never entered. What is asserted is the DECISION (nudge / skip), which is the
# part that was wrong; delivery through a stub is only how the decision is observed.
#
# ONE MUTANT PER SITE. The kitty arm, each of the three skip predicates, the unreadable-screen
# fail-closed, and the shared-enumeration property are six distinct sites and get six cases — a
# single case covering "kitty works" would credit none of them.

# Stand up a stub kitty adapter speaking it2-kitty's contract (`session list --json` → [{id,cwd,
# title,pid}] · `session read -s <id>` → screen text · `session send -s <id> <text>`), with one
# target pane whose cwd carries the marker and whose screen is $1.
_stub_kitty() {
  local screen="$1"
  export CC_KITTY_SCREEN="$screen"
  export CC_KITTY_SENDLOG="$BATS_TEST_TMPDIR/kitty.send"
  cat > "$BATS_TEST_TMPDIR/bin/it2-kitty" <<'STUB'
#!/usr/bin/env bash
[ "$1" = session ] || exit 64
verb="$2"; shift 2
sid=""; while [ $# -gt 0 ]; do case "$1" in -s) sid="$2"; shift 2 ;; --json) shift ;; *) break ;; esac; done
case "$verb" in
  list) printf '[{"id":"7","title":"claude","cwd":"/tmp/wt-pool-1","pid":123}]\n' ;;
  read) printf '%s\n' "$CC_KITTY_SCREEN" ;;
  send) printf '%s|%s\n' "$sid" "$*" >> "$CC_KITTY_SENDLOG" ;;
  *) exit 64 ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/it2-kitty"
  export CC_KEEPALIVE_KITTY_BIN="$BATS_TEST_TMPDIR/bin/it2-kitty"
}

# osascript is called by BARE NAME, so a stub earlier on PATH intercepts the iTerm2 arm and records
# the AppleScript it was handed. Returning nothing means "no idle iTerm2 panes", which keeps the
# kitty cases single-armed.
_stub_osascript() {
  export CC_OSA_LOG="$BATS_TEST_TMPDIR/osa.script"
  printf '#!/usr/bin/env bash\ncat >> "$CC_OSA_LOG"\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/osascript"
  chmod +x "$BATS_TEST_TMPDIR/bin/osascript"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

_one_cycle() { run timeout 20 env CC_KEEPALIVE_ONCE=1 CC_KEEPALIVE_MARKERS="wt-pool-1" "$KA" 1 fake-session-id; }

@test "kitty: an idle marked pane IS nudged — the arm is not inert off iTerm2" {
  _stub_osascript; _stub_kitty "welcome back
? for shortcuts"
  _one_cycle
  [ "$status" -eq 0 ] || { echo "one cycle did not exit 0 (status $status): $output"; false; }
  [ -s "$CC_KITTY_SENDLOG" ] || { echo "no kitty pane was nudged — the kitty arm is inert"; false; }
  grep -q '^7|' "$CC_KITTY_SENDLOG" || { echo "nudge did not target the marked pane: $(cat "$CC_KITTY_SENDLOG")"; false; }
}

@test "kitty: a pane MID-TURN is skipped — never interrupt a running turn" {
  _stub_osascript; _stub_kitty "doing the thing
  esc to interrupt"
  _one_cycle
  [ "$status" -eq 0 ]
  [ ! -s "${CC_KITTY_SENDLOG:-/nonexistent}" ] || { echo "nudged a pane that was mid-turn: $(cat "$CC_KITTY_SENDLOG")"; false; }
}

@test "kitty: a pane at a DECISION PROMPT is skipped — a blind auto-typer answering a dialog is worse than an idle pane" {
  _stub_osascript; _stub_kitty "Do you want to proceed?
  Tab to amend"
  _one_cycle
  [ "$status" -eq 0 ]
  [ ! -s "${CC_KITTY_SENDLOG:-/nonexistent}" ] || { echo "nudged a pane sitting at a prompt: $(cat "$CC_KITTY_SENDLOG")"; false; }
}

@test "d591c8d990b5 — a pane AWAITING ITS OWN ARMED WATCHER is skipped; silence is not evidence of stall" {
  # The measured case (2026-08-10 04:5xZ, pane 142): idle for 30 min by the transcript-growth test,
  # while its own footer read "1 monitor still running" and its last message said the monitor wakes
  # it to content-verify each landed diff. That is the "Awaiting ARMED is the legitimate non-close
  # state" the close protocol blesses — nudging it would have interrupted a correct wait and risked
  # duplicating a wave collection. The discriminator is an armed wake of its own, not silence.
  _stub_osascript; _stub_kitty "waiting for the land to finish
  1 monitor still running"
  _one_cycle
  [ "$status" -eq 0 ]
  [ ! -s "${CC_KITTY_SENDLOG:-/nonexistent}" ] || { echo "nudged a pane that was legitimately awaiting its own watcher: $(cat "$CC_KITTY_SENDLOG")"; false; }
}

@test "kitty: an UNREADABLE screen is not an idle pane — fail closed" {
  # Absence is also what a hang looks like. An empty get-text means the screen could not be read,
  # which is the one state a nudger must not read as "quiet, go ahead".
  _stub_osascript; _stub_kitty ""
  _one_cycle
  [ "$status" -eq 0 ]
  [ ! -s "${CC_KITTY_SENDLOG:-/nonexistent}" ] || { echo "nudged a pane whose screen could not be read: $(cat "$CC_KITTY_SENDLOG")"; false; }
}

@test "ONE ENUMERATION, TWO RENDERINGS — the third predicate reaches the iTerm2 arm too" {
  # hooks/lib/pane-modal.sh names the standing risk this pins: a screen predicate copied into a
  # second file rots independently of the first. The skip fragments must be declared once and
  # rendered into BOTH the AppleScript `contains` clauses and the kitty grep — so overriding the
  # enumeration must change the AppleScript the iTerm2 arm actually runs.
  _stub_osascript; _stub_kitty "idle"
  run timeout 20 env CC_KEEPALIVE_ONCE=1 CC_KEEPALIVE_MARKERS="wt-pool-1" \
      CC_KEEPALIVE_AWAIT="sentinel-await-fragment" "$KA" 1 fake-session-id
  [ "$status" -eq 0 ] || { echo "one cycle did not exit 0 (status $status): $output"; false; }
  [ -s "$CC_OSA_LOG" ] || { echo "the iTerm2 arm ran no AppleScript at all"; false; }
  grep -q 'esc to interrupt' "$CC_OSA_LOG" || { echo "the mid-turn fragment is not in the generated AppleScript"; false; }
  grep -q 'sentinel-await-fragment' "$CC_OSA_LOG" || { echo "the awaiting-watcher predicate never reaches the iTerm2 arm — two enumerations, not one"; false; }
}

@test "the actuator is TRACKED — the whole point of the row" {
  [ -f "$KA" ] || { echo "bin/reso-keepalive is not in the tree"; false; }
  [ -x "$KA" ] || { echo "bin/reso-keepalive is not executable"; false; }
}

@test "an EMPTY marker list exits 0 and SAYS so — it never loops blind" {
  # The failure this replaces is silent: a frozen list whose worktrees no longer exist gives a
  # nudger with nothing to aim at, looping forever with no output. Exiting loudly is the fix.
  run timeout 10 env CC_KEEPALIVE_MARKERS="" "$KA" 1 fake-session-id
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "no target markers" || { echo "empty markers did not announce: $output"; false; }
}

@test "CONTROL: a whitespace-only marker list is also EMPTY, not a marker named ' '" {
  # `[ -z "${MARKERS// /}" ]` is the guard; a plain `[ -z "$MARKERS" ]` would let a space through
  # and re-enter the loop with one bogus marker. This is the case that tells them apart.
  run timeout 10 env CC_KEEPALIVE_MARKERS="   " "$KA" 1 fake-session-id
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "no target markers" || { echo "whitespace-only list was treated as a marker: $output"; false; }
}

@test "MARKERS is env-overridable — the literal is a DEFAULT, not a freeze" {
  # ASSERTED AS BEHAVIOUR, NOT AS SPELLING. The first cut of this case grepped for the literal
  # `CC_KEEPALIVE_MARKERS:-`, which pinned the TEXT of the expansion rather than what it does — and
  # it went red the moment that text was corrected to `${VAR-default}` to fix a real bug, indicting
  # the fix instead of the defect (memory: stale-assertion-becomes-an-inverted-guard).
  #
  # The behavioural pair below discriminates without entering the nudge loop, because the two env
  # states must diverge: an EXPLICITLY EMPTY override exits 0 (cases 2 and 3 above), while UNSET
  # must NOT exit — the default list is in force, so the script proceeds and is killed by the
  # timeout. A file that ignored the env var entirely would run in both; one that had dropped the
  # default would exit in both. Only a correct `${VAR-default}` gives one of each.
  run timeout 5 env CC_KEEPALIVE_MARKERS="" "$KA" 1 fake-session-id
  [ "$status" -eq 0 ] || { echo "an explicit empty override did not disable it (status $status)"; false; }
  run timeout 5 "$KA" 1 fake-session-id
  [ "$status" -eq 124 ] || { echo "UNSET should fall back to the default list and keep running, got status $status"; false; }
  # The default itself must still be there: dropping it would silently change every existing
  # caller, and boot-resume.sh passes only the interval.
  grep -q 'wt-cc-030951-65335' "$KA" || { echo "the original default was dropped — existing callers change behaviour"; false; }
}

@test "iTerm2 is addressed by BUNDLE ID, never by name" {
  grep -q 'application id "com.googlecode.iterm2"' "$KA" || { echo "not addressed by bundle id"; false; }
  run grep -nE 'application "iTerm' "$KA"
  [ "$status" -ne 0 ] || { echo "addresses iTerm2 by NAME — loses terminology and can launch it: $output"; false; }
}

@test "the is-running guard short-circuits BEFORE any tell block" {
  # Order is the property: a guard placed after `tell` has already resolved (and possibly launched)
  # the app. Assert the guard line precedes the first tell.
  local g t
  g="$(grep -n 'is running) then return' "$KA" | head -1 | cut -d: -f1)"
  t="$(grep -n '^tell application' "$KA" | head -1 | cut -d: -f1)"
  [ -n "$g" ] || { echo "no is-running short-circuit found"; false; }
  [ -n "$t" ] || { echo "no tell block found — the fixture no longer matches the subject"; false; }
  [ "$g" -lt "$t" ] || { echo "the is-running guard ($g) comes AFTER the tell ($t)"; false; }
}

@test "shellcheck can READ it — the reason it is bash and not zsh" {
  # 410f920c9's header records that as the repo's first zsh script under bin/, shellcheck refused
  # it outright (SC1071) — i.e. tracking a file the gates cannot read is only half the move. If a
  # later edit reintroduces a zsh shebang this goes red, which is the point.
  head -1 "$KA" | grep -q 'bash' || { echo "shebang is not bash — shellcheck cannot read it"; false; }
  run shellcheck -S error "$KA"
  [ "$status" -eq 0 ] || { echo "shellcheck -S error is not clean: $output"; false; }
}
