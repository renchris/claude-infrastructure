#!/usr/bin/env bats
# handoff-fire.sh — DAEMON/HEADLESS kitty detection (2026-08-05, item b0b4ec40d63a).
#
# WHY THIS EXISTS. in_kitty()'s original clause reads the FIRING PROCESS's own env, which is right
# for an interactive caller and blind for the callers handoff-fire actually serves: a launchd job,
# the desk dispatcher and a Stop hook inherit neither KITTY_WINDOW_ID nor ITERM_SESSION_ID. That is
# not "iTerm2" — it is NO TERMINAL AT ALL, the case spawn() already names ANCHOR_INTENT=0 — and every
# one of those callers took the iTerm2 branch by default and fired an iTerm2 surface on a box whose
# only live terminal is kitty. The fix asks the BOX (a live control socket) instead of the env.
#
# WHAT IS PINNED HERE, and why each would otherwise be "simplified" back out:
#   1. THE DIRECTION THAT MUST NOT FLIP. A genuine iTerm2 pane ($ITERM_SESSION_ID set, no
#      KITTY_WINDOW_ID) must stay iTerm2 EVEN WITH A LIVE KITTY ON THE BOX. Diverting that is the
#      exact mirror of the 2026-07-31 outage, where a polluted env drove a background kitty from
#      inside real iTerm2 panes and every assignee spawn died at use time.
#   2. THE SOCKET MUST ANSWER. A socket FILE outlives a SIGKILLed kitty, so the file's existence is
#      not liveness. The stale-socket case is a positive control: same file, kitty refuses, verdict
#      must be NOT-kitty.
#   3. CC_TERM_KITTY_TO IS EXPORTED. `kitty @` with no --to reads KITTY_LISTEN_ON from the env —
#      exactly what this caller lacks. Detecting kitty without addressing it swaps one silent
#      failure for another, and nothing else in the suite would notice.
#   4. NOT pgrep. macOS pgrep excludes the caller's ANCESTORS by default, and kitty is an ancestor of
#      everything in its own pane — so a pgrep probe works for the launchd caller and returns empty
#      in every hand-check. The source is pinned against reintroducing it.
#   5. REAL_IT2 → bin/it2-kitty, not the shim. The shim's own gate re-reads the env we do not have
#      and then cc-in-kitty's ANCESTRY check, which a launchd caller fails by construction.
#   6. THE ANCHOR VERB. Without a kitty `anchor`, detection succeeds and the fire then REFUSES —
#      resolve_headless_anchor reads the iTerm2 driver's failure as INCONCLUSIVE.
#
# NOTHING HERE EXECUTES scripts/handoff-fire.sh — it FIRES REAL SESSIONS. Functions are EXTRACTED
# with sed, the established pattern (tests/handoff-fire-kitty.bats:124). kitty and ps are stubbed;
# the operator's real kitty is never driven.
#
# Every assertion is `[ ]`, `run`+status, or `… || false`. `[[ ]]` and `(( ))` are errexit-EXEMPT in
# bats and are silently DEAD anywhere but a body's last line — that has burned this repo twice.

setup() {
  # Pin the fire capacity gate OFF — this file names handoff-fire, so test-hermeticity-lint rule 2
  # requires it, and it was right: an unpinned suite goes red-by-LOAD rather than by its subject.
  export CC_FIRE_CAPACITY_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"   # hermeticity ratchet: never live ~/

  # hf_bounded passthrough — same rationale as the sibling suites: these tests extract INDIVIDUAL
  # functions, so the real helper is not in scope. Its own semantics live in handoff-fire-it2-bound.
  hf_bounded() { "$@"; }

  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  KLOG="$BATS_TEST_TMPDIR/kitty.log"; : > "$KLOG"
  export KLOG

  # SOCKET DIR. A REAL AF_UNIX socket is required — the probe's guard is `[ -S ]`, and a plain file
  # would make every case here vacuous. sun_path is capped at 104 bytes on Darwin, so the bind is
  # ASSERTED rather than assumed: a path too long must go RED here, never quietly skip the fixture.
  SOCKDIR="$BATS_TEST_TMPDIR/sock"; mkdir -p "$SOCKDIR"
  export CC_FIRE_KITTY_SOCK_DIR="$SOCKDIR"
  /usr/bin/python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' \
    "$SOCKDIR/kitty-4242"
  [ -S "$SOCKDIR/kitty-4242" ]

  # fake kitty: logs argv, then answers `@ --to <sock> ls`. KFAKE_KITTY_RC forces a refusal (the
  # stale-socket control); KFAKE_LS names the JSON fixture `ls` prints.
  KITTY="$STUB/kitty"
  cat > "$KITTY" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >> "$KLOG"
[ "$1" = "@" ] || exit 64
shift
if [ "$1" = "--to" ]; then shift 2; fi
case "$1" in
  ls) [ "${KFAKE_KITTY_RC:-0}" = 0 ] || exit "$KFAKE_KITTY_RC"; cat "${KFAKE_LS:-/dev/null}" ;;
  *)  exit 64 ;;
esac
FAKE
  chmod +x "$KITTY"
  export CC_TERM_KITTY="$KITTY"
  # shellcheck disable=SC2034  # consumed by the eval-extracted probe, which shellcheck cannot see
  CC_KITTY_BIN="$KITTY"

  # ps: kitty_sockets reads `ps -Ao pid=,comm=`. The table carries the kitty instance AND its kitten
  # helpers, because "kitten" is the near-miss the basename match has to reject.
  cat > "$STUB/ps" <<'FAKE'
#!/bin/sh
printf '%s\n' "${KFAKE_PS-  4242 /Applications/kitty.app/Contents/MacOS/kitty
   758 /Applications/kitty.app/Contents/MacOS/kitten
   755 /usr/bin/login}"
FAKE
  chmod +x "$STUB/ps"
  export PATH="$STUB:$PATH"

  # `kitty @ ls` fixture: os-window 1 holds a tab of two windows, 28 focused; os-window 2 holds a
  # single-window tab (id 9) so the room-aware fallback has somewhere else to land.
  KFAKE_LS="$BATS_TEST_TMPDIR/ls.json"; export KFAKE_LS
  cat > "$KFAKE_LS" <<'JSON'
[{"id":1,"tabs":[{"windows":[{"id":28,"pid":4242,"is_focused":true},
                             {"id":31,"pid":5150,"is_focused":false}]}]},
 {"id":2,"tabs":[{"windows":[{"id":9,"pid":6000,"is_focused":false}]}]}]
JSON

  # ── extract the subject ────────────────────────────────────────────────────────────────────────
  # in_kitty and kt are ONE-LINERS with no `^}` of their own, so a /,/^}/ range would swallow the
  # next function. GUARD every extraction: an empty eval is a vacuous pass, the failure mode this
  # suite exists to prevent.
  x_kitty="$(sed -n '/^in_kitty() {/p' "$HF")";                       [ -n "$x_kitty" ]
  x_kt="$(sed -n '/^kt() {/p' "$HF")";                                [ -n "$x_kt" ]
  x_head="$(sed -n '/^kitty_headless() {/,/^}/p' "$HF")";             [ -n "$x_head" ]
  x_socks="$(sed -n '/^kitty_sockets() {/,/^}/p' "$HF")";             [ -n "$x_socks" ]
  x_ans="$(sed -n '/^kitty_socket_answers() {/,/^}/p' "$HF")";        [ -n "$x_ans" ]
  x_field="$(sed -n '/^kt_window_field() {/,/^}/p' "$HF")";           [ -n "$x_field" ]
  x_py="$(sed -n '/^it2py() {/,/^}/p' "$HF")";                        [ -n "$x_py" ]
  x_res="$(sed -n '/^resolve_headless_anchor() {/,/^}/p' "$HF")";     [ -n "$x_res" ]
  eval "$x_kitty"; eval "$x_kt"; eval "$x_head"; eval "$x_socks"; eval "$x_ans"
  eval "$x_field"; eval "$x_py"; eval "$x_res"

  pin_daemon
}

# TERMINAL PINNING — never inferred from the developer's environment. Each of the three is a
# DIFFERENT question, and the whole fix lives in telling them apart.
pin_daemon() { unset KITTY_WINDOW_ID ITERM_SESSION_ID IT2_WRAPPER_NO_KITTY CC_TERM_KITTY_TO _HF_KITTY_HEADLESS; }
pin_iterm2() { pin_daemon; export ITERM_SESSION_ID="w0t0p0:E5D77446-0000-0000-0000-000000000000"; }
pin_kitty()  { pin_daemon; export KITTY_WINDOW_ID=28; }

# ── the probe ────────────────────────────────────────────────────────────────────────────────────

@test "a daemon caller with NO terminal env resolves the LIVE kitty socket — the whole item" {
  pin_daemon
  in_kitty || false
  [ "$CC_TERM_KITTY_TO" = "unix:$SOCKDIR/kitty-4242" ]
}

@test "CC_TERM_KITTY_TO is EXPORTED, so every later kt() can address the socket it found" {
  pin_daemon
  in_kitty || false
  # Detection without addressing is the silent half-fix: `kitty @` with no --to reads KITTY_LISTEN_ON
  # from an env this caller does not have. Prove the export survives into a CHILD process — a plain
  # assignment would satisfy every other case in this file and still leave `kitty @` unaddressed.
  run /usr/bin/env sh -c 'printf %s "${CC_TERM_KITTY_TO:-}"'
  [ "$output" = "unix:$SOCKDIR/kitty-4242" ]
}

@test "a GENUINE iTerm2 pane stays iTerm2 even with a live kitty — the 2026-07-31 mirror" {
  # $ITERM_SESSION_ID with no KITTY_WINDOW_ID is a real iTerm2 pane. Diverting it would send the
  # operator's handoff into a kitty window they are not looking at.
  pin_iterm2
  run in_kitty; [ "$status" -ne 0 ]
  [ -z "${CC_TERM_KITTY_TO:-}" ]
}

@test "an in-pane kitty caller never reaches the probe — the env clause still answers first" {
  pin_kitty
  in_kitty || false
  # The probe forks ps + kitty; the interactive path must not pay for it, and must not overwrite an
  # operator/inherited socket choice either.
  [ -z "${CC_TERM_KITTY_TO:-}" ]
  run grep -c . "$KLOG"
  [ "$output" = "0" ]
}

@test "IT2_WRAPPER_NO_KITTY=1 kills the probe too — one switch governs both clauses" {
  pin_daemon; export IT2_WRAPPER_NO_KITTY=1
  run in_kitty; [ "$status" -ne 0 ]
}

@test "CC_FIRE_KITTY_PROBE=off restores the old env-only behaviour" {
  pin_daemon; export CC_FIRE_KITTY_PROBE=off
  run in_kitty; [ "$status" -ne 0 ]
}

@test "POSITIVE CONTROL: a socket FILE that does not ANSWER is not a live kitty" {
  # A socket file outlives a SIGKILLed kitty. If the file alone decided, every case above would pass
  # for the wrong reason — the fixture is identical here and only kitty's answer changes.
  pin_daemon; export KFAKE_KITTY_RC=1
  run in_kitty; [ "$status" -ne 0 ]
}

@test "a live kitty with NO socket file is not drivable, and is refused" {
  pin_daemon; rm -f "$SOCKDIR/kitty-4242"
  run in_kitty; [ "$status" -ne 0 ]
}

@test "kitten helpers are NOT mistaken for the kitty instance" {
  # `kitten __watch_conf__` / `kitten run-shell` outnumber the instance and own no socket. Give the
  # helper the pid whose socket EXISTS, so a basename match that accepted `kitten` would pass.
  pin_daemon
  export KFAKE_PS="  4242 /Applications/kitty.app/Contents/MacOS/kitten
   755 /usr/bin/login"
  run in_kitty; [ "$status" -ne 0 ]
}

@test "an operator-named CC_TERM_KITTY_TO is honoured but still VERIFIED" {
  pin_daemon; export CC_TERM_KITTY_TO="unix:$SOCKDIR/kitty-4242"
  in_kitty || false
  # …and a stale export must not divert us onto a dead socket.
  pin_daemon; export CC_TERM_KITTY_TO="unix:$SOCKDIR/kitty-4242" KFAKE_KITTY_RC=1
  run in_kitty; [ "$status" -ne 0 ]
}

@test "the probe is MEMOIZED — in_kitty is called on nearly every primitive and forks ps + kitty" {
  pin_daemon
  in_kitty || false
  local first; first="$(grep -c . "$KLOG")"
  in_kitty || false; in_kitty || false
  [ "$(grep -c . "$KLOG")" = "$first" ]
}

# ── the pgrep regression anchor ──────────────────────────────────────────────────────────────────

@test "REGRESSION ANCHOR: the probe must not use pgrep — macOS pgrep hides the caller's ANCESTORS" {
  # Measured 2026-08-05: `pgrep -f /Applications/kitty.app/Contents/MacOS/kitty` returns NOTHING from
  # inside a kitty pane (pgrep(1): "the current pgrep or pkill process and all of its ancestors are
  # excluded"), while `pgrep -a` and `ps -Ao pid=,comm=` both find it, and the control — Dock/Finder,
  # hardened apps that are NOT ancestors — matches fine. So this is ancestry, not entitlements. The
  # polarity is the trap: a pgrep probe WORKS for the launchd caller and is empty in every
  # hand-check, so the next author reaching for the obvious spelling has to fail a test to do it.
  # Scoped to the PROBE's own three functions, deliberately. A file-wide grep convicts two innocents:
  # the comment above kitty_headless, which names pgrep on purpose to say why it is wrong, and an
  # unrelated self-close WARNING that hands the operator a `pgrep -fl` to run in their own shell.
  # An anchor that fires on the explanation of the bug is one somebody deletes.
  printf '%s\n%s\n%s\n' "$x_head" "$x_socks" "$x_ans" > "$BATS_TEST_TMPDIR/probe.txt"
  run grep -c 'pgrep' "$BATS_TEST_TMPDIR/probe.txt"
  [ "$output" = "0" ]
  # …and the replacement is actually present, so this cannot pass by the probe having no lookup at
  # all — which is the only other way to have zero pgreps.
  run grep -c 'ps -Ao pid=,comm=' "$BATS_TEST_TMPDIR/probe.txt"
  [ "$output" = "1" ]
}

# ── REAL_IT2: the daemon's it2 is the TRANSLATOR, not the shim ───────────────────────────────────

load_hf_block() { eval "$(sed -n '/^IT2_SHIM=/,/# test seam (same convention as cc-sessions)/p' "$HF")" || true; }

@test "a daemon caller resolves bin/it2-kitty directly — the shim would forward it to iTerm2" {
  # bin/it2-wrapper diverts on the same env we do not have, then on cc-in-kitty's ANCESTRY check,
  # which a launchd caller fails by construction. Its forward target is an iTerm2 Python-API client
  # with no iTerm2 to talk to (exit 2), so the shim is the WRONG answer here even though it is the
  # right one for an in-pane kitty caller.
  pin_daemon
  FAKE_REAL="$BATS_TEST_TMPDIR/real-it2"; printf '#!/bin/sh\nexit 0\n' > "$FAKE_REAL"; chmod +x "$FAKE_REAL"
  printf 'REAL_IT2="%s"\n' "$FAKE_REAL" > "$HOME/.claude/bin/it2"; chmod +x "$HOME/.claude/bin/it2"
  KITTY_IT2="$BATS_TEST_TMPDIR/it2-kitty"; printf '#!/bin/sh\nexit 0\n' > "$KITTY_IT2"; chmod +x "$KITTY_IT2"
  load_hf_block
  [ "$REAL_IT2" = "$BATS_TEST_TMPDIR/it2-kitty" ]
}

@test "with kitty NOT live, a daemon caller still resolves the raw iTerm2 binary (unchanged)" {
  pin_daemon; export KFAKE_KITTY_RC=1
  FAKE_REAL="$BATS_TEST_TMPDIR/real-it2"; printf '#!/bin/sh\nexit 0\n' > "$FAKE_REAL"; chmod +x "$FAKE_REAL"
  printf 'REAL_IT2="%s"\n' "$FAKE_REAL" > "$HOME/.claude/bin/it2"; chmod +x "$HOME/.claude/bin/it2"
  KITTY_IT2="$BATS_TEST_TMPDIR/it2-kitty"; printf '#!/bin/sh\nexit 0\n' > "$KITTY_IT2"; chmod +x "$KITTY_IT2"
  load_hf_block
  [ "$REAL_IT2" = "$FAKE_REAL" ]
}

# ── it2py anchor, kitty side ─────────────────────────────────────────────────────────────────────

@test "it2py anchor resolves the FOCUSED window and its tab's window count" {
  pin_daemon; in_kitty || false
  run it2py anchor "" 5
  [ "$status" -eq 0 ]
  [ "$output" = "28 2" ]
}

@test "it2py anchor prefers the DESK pane when it has room — same order as the iTerm2 verb" {
  pin_daemon; in_kitty || false
  run it2py anchor "9" 5
  [ "$status" -eq 0 ]
  [ "$output" = "9 1" ]
}

@test "it2py anchor skips a preferred pane whose tab is FULL and lands where there is room" {
  # cap 2: window 28's tab is at the cap, window 9's is not. A room-blind pick would answer "28 2"
  # and the caller would split an already-full tab into slivers.
  pin_daemon; in_kitty || false
  run it2py anchor "" 2
  [ "$status" -eq 0 ]
  [ "$output" = "9 1" ]
}

@test "it2py anchor with NOTHING free still answers, with the TRUE count, so the caller spills" {
  pin_daemon; in_kitty || false
  run it2py anchor "" 1
  [ "$status" -eq 0 ]
  [ "$output" = "28 2" ]
}

@test "it2py anchor on an EMPTY box is a VERDICT (NO-LIVE-SESSION, rc 0), never a failure" {
  pin_daemon; in_kitty || false
  printf '[]\n' > "$KFAKE_LS"
  run it2py anchor "" 5
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'NO-LIVE-SESSION'
}

@test "it2py anchor on a FAILED query returns non-zero — 'could not determine' is not 'empty'" {
  # Collapsing these two is what leaked ~12 iTerm2 windows/hour on 2026-07-30. resolve_headless_anchor
  # maps rc≠0 to 2 (REFUSE) and NO-LIVE-SESSION to 1 (a fresh window is then honest).
  pin_daemon; in_kitty || false
  export KFAKE_KITTY_RC=3
  run it2py anchor "" 5
  [ "$status" -ne 0 ]
}

# ── resolve_headless_anchor: kitty ids are INTEGERS, not UUIDs ────────────────────────────────────

@test "resolve_headless_anchor ACCEPTS a numeric kitty id — the UUID pattern alone would refuse" {
  # Pre-fix the `????????-* [0-9]*` arm could only reject "28 2", which reads as "unparseable ⇒
  # inconclusive ⇒ refuse": the daemon would detect the right terminal, resolve a good anchor, and
  # then decline to fire.
  pin_daemon; in_kitty || false
  run resolve_headless_anchor
  [ "$status" -eq 0 ]
  [ "$output" = "28 2" ]
}

@test "resolve_headless_anchor maps the three states apart under kitty (0 / 1 / 2)" {
  pin_daemon; in_kitty || false
  printf '[]\n' > "$KFAKE_LS"
  run resolve_headless_anchor; [ "$status" -eq 1 ]      # DETERMINED empty
  export KFAKE_KITTY_RC=3
  run resolve_headless_anchor; [ "$status" -eq 2 ]      # could not determine
}

@test "CC_FIRE_HEADLESS_ANCHOR=off still refuses under kitty (kill switch unchanged)" {
  pin_daemon; in_kitty || false
  export CC_FIRE_HEADLESS_ANCHOR=off
  run resolve_headless_anchor; [ "$status" -eq 2 ]
}
