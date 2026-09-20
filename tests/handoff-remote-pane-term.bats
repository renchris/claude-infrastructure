#!/usr/bin/env bats
# handoff-fire.sh — hf_remote_pane_term: WHICH TERMINAL OWNS PANE P (LIMIT_RECOVER_100P §10 W8).
#
# WHY THIS EXISTS. The remote recycle / remote self-close / recycle-precondition probe all name a
# pane this process does not own, and all three used to settle the terminal by asking
# pin_term_verdict_for_watcher → bin/cc-in-kitty, which walks THIS PROCESS's ancestry. Every driver
# that matters in limit recovery has no kitty ancestor by construction — scripts/lib/detach.sh
# passes start_new_session=True, a `nohup … &` from a tool call is reparented at once, and the
# launchd poller never had one — so cc-in-kitty returns its DEFINITIVE not-kitty (rc 1), the pin
# exports CC_TERM=iterm2, the pane→tty query goes to an iTerm2 that is not running, and
# hf_remote_source_pin refuses "pane P resolved to no tty" over a pane that is alive and enumerable.
# Measured: that refusal in 9 of 9 daemon- or detached-driven in-place recycles on record, each one
# a tombstoned husk (the transplant had already completed, so the session moved and nothing
# recycled). bin/cc-in-kitty is NOT changed — its definitive no is right about the driver; the fix
# asks a different question of a different subject.
#
# WHAT IS PINNED HERE, and each one is load-bearing:
#   1. THE ORPHAN CASE, which is the whole item. cc-in-kitty stubbed to rc 1 (the detached driver)
#      + an integer pane a live socket lists ⇒ the resolved terminal is STILL kitty. This is the
#      red-proof: without hf_remote_pane_term the same fixture resolves iterm2, and the negative
#      control below asserts exactly that over the pin alone.
#   2. THREE STATES, NOT TWO. "a socket answered and does not list P" (rc 1, terminal) and "no
#      socket answered at all" (rc 3, park/retry) demand opposite actions, and collapsing them is
#      the 0c93f779ecfa defect one layer down. Each gets its own case.
#   3. NOTHING IS EXPORTED ON A NEGATIVE. A caller that parks must not inherit a half-pinned
#      terminal, and a stale CC_TERM_KITTY_TO must be rolled back rather than left pointing at a
#      socket that failed to enumerate.
#   4. THE KILL SWITCH IS INERT, BOTH WAYS. CC_REMOTE_PANE_TERM=off exports nothing at all, so
#      today's ancestry pin runs byte-identically underneath it.
#   5. THE UUID SHAPE NEEDS NO PROBE. An iTerm2 session id can never be a kitty window id, and a
#      probe against it could only ever time out — so it is answered from the shape, and the case
#      asserts no kitty call was made at all.
#
# NOTHING HERE EXECUTES scripts/handoff-fire.sh — it FIRES REAL SESSIONS. Functions are EXTRACTED
# with sed, the established pattern (tests/handoff-fire-kitty-daemon.bats:156). kitty and ps are
# stubbed; the operator's real kitty is never driven.
#
# Every assertion is `[ ]`, `run`+status, or `… || false`. `[[ ]]` and `(( ))` are errexit-EXEMPT in
# bats and are silently DEAD anywhere but a body's last line — that has burned this repo twice.

# A REAL AF_UNIX socket, asserted — kitty_sockets' `[ -S ]` pre-filter would drop a plain file and
# make every case here vacuous. The bind is RELATIVE: Darwin caps sun_path at 104 bytes against THE
# STRING HANDED TO bind(2), and an absolute bind under postland's corpus TMPDIR is +21 bytes over a
# session TMPDIR — the shape that took a whole sibling suite down inside the one gate that judges
# this tree (tests/handoff-fire-kitty-daemon.bats:41).
mksock() {
  /usr/bin/python3 -c 'import os,socket,sys; d,b=os.path.split(os.path.abspath(sys.argv[1])); os.chdir(d); socket.socket(socket.AF_UNIX).bind(b)' "$1"
  [ -S "$1" ]
}

setup() {
  # test-hermeticity-lint rule 2: this file names handoff-fire, so the fire capacity gate is pinned
  # OFF — an unpinned suite goes red by LOAD rather than by its subject.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"   # never the live ~/
  unset CC_KITTY_CONF   # kitty_socket_template's default is part of the fixture, not the box's
  # SEAMS THAT DO NOT RESOLVE UNDER $HOME (test-hermeticity-lint rules 5a/5b). Fixturing $HOME does
  # not redirect an ABSOLUTE /tmp default, nor a BARE NAME the subject then executes off the
  # operator's PATH — tests/cc-relogin-status.bats fixtured $HOME from birth and still counted the
  # operator's live pending approvals and ran their deployed claude-accounts once per test. An
  # ABSENT path is the right value here: these sensors fail open on one.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/handoff-account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/claude-accounts-heal-"

  # hf_bounded passthrough — these tests extract INDIVIDUAL functions, so the real helper is not in
  # scope. Its own semantics live in tests/handoff-fire-it2-bound.bats.
  hf_bounded() { "$@"; }

  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  KLOG="$BATS_TEST_TMPDIR/kitty.log"; : > "$KLOG"; export KLOG

  SOCKDIR="$BATS_TEST_TMPDIR/sock"; mkdir -p "$SOCKDIR"
  export CC_FIRE_KITTY_SOCK_DIR="$SOCKDIR"
  mksock "$SOCKDIR/kitty-4242"

  mkdir -p "$HOME/.config/kitty"
  printf 'listen_on unix:%s/kitty-{kitty_pid}\n' "$SOCKDIR" > "$HOME/.config/kitty/kitty.conf"

  # fake kitty: logs argv, then answers `@ --to <sock> ls` from a JSON FIXTURE FILE. The JSON is
  # heredoc'd to disk and `cat`ed rather than embedded in a quoted printf — a stub that carries JSON
  # inline dies on its first apostrophe and the fail-open consumer then reads a healthy verdict
  # (docs/lessons/fixture-stub-cannot-carry-an-apostrophe.md).
  KITTY="$STUB/kitty"
  cat > "$KITTY" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >> "$KLOG"
[ "$1" = "@" ] || exit 64
shift
# The ADDRESS IS HONOURED, not ignored: a real kitty cannot connect to a socket that is not there,
# and a fixture that answers every address alike makes the stale-socket cases vacuous — the probe
# would "verify" a dead export and never fall through to the live one.
if [ "$1" = "--to" ]; then
  case "$2" in unix:/*) [ -S "${2#unix:}" ] || exit 1 ;; esac
  shift 2
fi
case "$1" in
  ls) [ "${KFAKE_KITTY_RC:-0}" = 0 ] || exit "$KFAKE_KITTY_RC"; cat "${KFAKE_LS:-/dev/null}" ;;
  *)  exit 64 ;;
esac
FAKE
  chmod +x "$KITTY"
  export CC_TERM_KITTY="$KITTY"
  export CC_KITTY_BIN="$KITTY"

  # ps: kitty_sockets reads `ps -Ao pid=,comm=`. The table carries the kitty instance AND a kitten
  # helper, because "kitten" is the near-miss the basename match has to reject.
  cat > "$STUB/ps" <<'FAKE'
#!/bin/sh
printf '%s\n' "${KFAKE_PS-  4242 /Applications/kitty.app/Contents/MacOS/kitty
   758 /Applications/kitty.app/Contents/MacOS/kitten
   755 /usr/bin/login}"
FAKE
  chmod +x "$STUB/ps"
  export PATH="$STUB:$PATH"

  KFAKE_LS="$BATS_TEST_TMPDIR/ls.json"; export KFAKE_LS
  cat > "$KFAKE_LS" <<'JSON'
[{"id":1,"tabs":[{"windows":[{"id":110,"pid":4242,"is_focused":true},
                             {"id":31,"pid":5150,"is_focused":false}]}]},
 {"id":2,"tabs":[{"windows":[{"id":9,"pid":6000,"is_focused":false}]}]}]
JSON

  # THE DRIVER IS AN ORPHAN. cc-in-kitty's DEFINITIVE not-kitty (rc 1) is the input state of the
  # whole item — a detached driver reaches launchd without meeting kitty. It is stubbed rather than
  # avoided so the negative control can show what the ancestry pin does with the SAME fixture.
  cat > "$HOME/.claude/bin/cc-in-kitty" <<'FAKE'
#!/bin/sh
exit "${FAKE_CIK_RC:-1}"
FAKE
  chmod +x "$HOME/.claude/bin/cc-in-kitty"

  # ── extract the subject ────────────────────────────────────────────────────────────────────────
  # kt is a ONE-LINER with no `^}` of its own, so a /,/^}/ range would swallow the next function.
  # GUARD every extraction: an empty eval is a vacuous pass, the failure mode this suite prevents.
  x_kt="$(sed -n '/^kt() {/p' "$HF")";                                   [ -n "$x_kt" ]
  x_socks="$(sed -n '/^kitty_sockets() {/,/^}/p' "$HF")";                [ -n "$x_socks" ]
  x_tmpl="$(sed -n '/^kitty_socket_template() {/,/^}/p' "$HF")";         [ -n "$x_tmpl" ]
  x_ans="$(sed -n '/^kitty_socket_answers() {/,/^}/p' "$HF")";           [ -n "$x_ans" ]
  x_field="$(sed -n '/^kt_window_field() {/,/^}/p' "$HF")";              [ -n "$x_field" ]
  x_term="$(sed -n '/^hf_remote_pane_term() {/,/^}/p' "$HF")";           [ -n "$x_term" ]
  x_pin="$(sed -n '/^pin_term_verdict_for_watcher() {/,/^}/p' "$HF")";   [ -n "$x_pin" ]
  eval "$x_kt"; eval "$x_socks"; eval "$x_tmpl"; eval "$x_ans"; eval "$x_field"
  eval "$x_term"; eval "$x_pin"

  clean_term
}

# The remote question must not be answerable from the driver's own environment, so every case
# starts with none of it set. CC_TERM is the seam both the pin and the resolver write.
clean_term() { unset CC_TERM CC_TERM_KITTY_TO KITTY_WINDOW_ID ITERM_SESSION_ID IT2_WRAPPER_NO_KITTY; }

# ── the resolver ─────────────────────────────────────────────────────────────────────────────────

@test "THE ITEM: an orphaned driver (cc-in-kitty rc 1) resolves a listed integer pane as KITTY" {
  # This is the 0-of-9 case. FAKE_CIK_RC=1 is the detached driver's honest, correct answer about
  # ITSELF; the pane is 110, which the live socket enumerates.
  export FAKE_CIK_RC=1
  hf_remote_pane_term 110 || false
  [ "$CC_TERM" = kitty ]
  [ -n "$CC_TERM_KITTY_TO" ]
  [ "$CC_TERM_KITTY_TO" = "unix:$SOCKDIR/kitty-4242" ]
  # …and the pin that used to decide this is now a no-op, because CC_TERM is already set.
  pin_term_verdict_for_watcher
  [ "$CC_TERM" = kitty ]
}

@test "NEGATIVE CONTROL: the ancestry pin ALONE, same fixture, resolves iterm2 — the pre-fix state" {
  # Without the resolver there is exactly one answer available, and it is the wrong one. If this
  # ever reads kitty the control is vacuous and the case above proves nothing.
  export FAKE_CIK_RC=1
  pin_term_verdict_for_watcher
  [ "$CC_TERM" = iterm2 ]
  [ -z "${CC_TERM_KITTY_TO:-}" ]
}

@test "an integer pane a live socket ANSWERS but does NOT list ⇒ rc 1 REMOTE-PANE-ABSENT" {
  # Definite negative about the PANE: the socket enumerated the whole fleet and 999 is not in it.
  run hf_remote_pane_term 999
  [ "$status" -eq 1 ]
}

@test "REMOTE-PANE-ABSENT exports nothing — a refusing caller must inherit no terminal" {
  clean_term
  set +e; hf_remote_pane_term 999; rc=$?; set -e
  [ "$rc" -eq 1 ]
  [ -z "${CC_TERM:-}" ]
  [ -z "${CC_TERM_KITTY_TO:-}" ]
}

@test "no socket ANSWERS ⇒ rc 3 REMOTE-PANE-RESOLVER-UNAVAILABLE, and CC_TERM stays unset" {
  # The socket FILE is still there (it outlives a SIGKILLed kitty) — only the answer is gone. That
  # is a non-verdict about the resolver and must never read as a fact about the pane.
  export KFAKE_KITTY_RC=1
  set +e; hf_remote_pane_term 110; rc=$?; set -e
  [ "$rc" -eq 3 ]
  [ -z "${CC_TERM:-}" ]
  [ -z "${CC_TERM_KITTY_TO:-}" ]
}

@test "no live kitty at all (empty ps table) ⇒ rc 3, never rc 1" {
  # Nothing to ask ⇒ nothing was learned. The two ways of having no answer must agree on the code.
  export KFAKE_PS=""
  run hf_remote_pane_term 110
  [ "$status" -eq 3 ]
}

@test "a socket that answers but returns UNPARSEABLE json ⇒ rc 3, not rc 1" {
  # kt_window_field exits 1 when the QUERY failed, which is a resolver fault and must not license
  # the terminal ABSENT verdict — only a clean enumeration may.
  printf 'not json at all\n' > "$KFAKE_LS"
  run hf_remote_pane_term 110
  [ "$status" -eq 3 ]
}

@test "a UUID pane resolves iterm2 from its SHAPE, with no kitty call at all" {
  run hf_remote_pane_term "w0t0p0:E5D77446-1111-2222-3333-444444444444"
  [ "$status" -eq 0 ]
  clean_term
  hf_remote_pane_term "E5D77446-1111-2222-3333-444444444444" || false
  [ "$CC_TERM" = iterm2 ]
  [ -z "${CC_TERM_KITTY_TO:-}" ]
  # A UUID can never be a kitty window id, so a probe could only ever time out. Nothing was asked.
  [ ! -s "$KLOG" ]
}

@test "an iTerm2-shaped pane id keeps its w0t0p0: prefix out of the verdict" {
  hf_remote_pane_term "w0t0p0:E5D77446-1111-2222-3333-444444444444" || false
  [ "$CC_TERM" = iterm2 ]
}

@test "CC_REMOTE_PANE_TERM=off ⇒ rc 0 and NOTHING exported — today's pin runs underneath" {
  export CC_REMOTE_PANE_TERM=off
  hf_remote_pane_term 110 || false
  [ -z "${CC_TERM:-}" ]
  [ -z "${CC_TERM_KITTY_TO:-}" ]
  [ ! -s "$KLOG" ]
  # …and with the switch off the ancestry pin still decides, exactly as it does today.
  export FAKE_CIK_RC=1
  pin_term_verdict_for_watcher
  [ "$CC_TERM" = iterm2 ]
}

@test "an explicit CC_TERM is never overwritten — same contract as the pin's first line" {
  export CC_TERM=iterm2
  hf_remote_pane_term 110 || false
  [ "$CC_TERM" = iterm2 ]
  [ ! -s "$KLOG" ]
}

@test "an empty pane id is not the remote form — rc 0, nothing exported, nothing asked" {
  hf_remote_pane_term "" || false
  [ -z "${CC_TERM:-}" ]
  [ ! -s "$KLOG" ]
}

@test "a STALE CC_TERM_KITTY_TO is VERIFIED, not trusted, and rolled back when it cannot enumerate" {
  # A dead address must not divert the resolver, and must not survive a failed resolution either.
  export CC_TERM_KITTY_TO="unix:$SOCKDIR/kitty-99999"   # no such socket file — a dead export
  export KFAKE_PS=""                                     # …and no live kitty to fall back to
  set +e; hf_remote_pane_term 110; rc=$?; set -e
  [ "$rc" -eq 3 ]
  [ "$CC_TERM_KITTY_TO" = "unix:$SOCKDIR/kitty-99999" ]   # restored, not silently rewritten
  [ -z "${CC_TERM:-}" ]
}

@test "a stale CC_TERM_KITTY_TO is replaced by the socket that DOES answer" {
  export CC_TERM_KITTY_TO="unix:$SOCKDIR/kitty-99999"
  hf_remote_pane_term 110 || false
  [ "$CC_TERM" = kitty ]
  [ "$CC_TERM_KITTY_TO" = "unix:$SOCKDIR/kitty-4242" ]
}

@test "the resolver ADDRESSES the socket it found — --to is on the wire, not just detected" {
  # Detecting kitty without addressing it swaps one silent failure for another: `kitty @` with no
  # --to reads KITTY_LISTEN_ON, which is exactly what a detached driver does not have.
  hf_remote_pane_term 110 || false
  grep -q -- "--to unix:$SOCKDIR/kitty-4242" "$KLOG" || false
}

# ── the static half: the constraints the sibling suites impose on this function ──────────────────

@test "the function body carries no literal 'as_tty \"' — the pin-order judge greps for it" {
  # tests/handoff-selfclose-terminal-pin-order.bats:109-126 computes an offset from the FIRST
  # `as_tty "` in the self-close window; a new occurrence would break a control that is not about
  # this function at all. as_tty_classified is the form to use if a tty is ever needed here.
  body="$(sed -n '/^hf_remote_pane_term() {/,/^}/p' "$HF")"
  [ -n "$body" ]
  run bash -c 'printf "%s" "$1" | grep -c "as_tty \""' _ "$body"
  [ "$output" = "0" ]
}

@test "the function is DEFINED above every one of its call sites" {
  # A function must be defined before execution reaches its first use, and all three callers sit
  # thousands of lines below. An ordering slip is silent until the one path that takes it runs.
  def="$(grep -n '^hf_remote_pane_term() {' "$HF" | head -1 | cut -d: -f1)"
  [ -n "$def" ]
  first="$(grep -n '^ *[A-Z_]*TERM_RC=0; hf_remote_pane_term ' "$HF" | head -1 | cut -d: -f1)"
  [ -n "$first" ]
  [ "$def" -lt "$first" ]
  # …and all three call sites are wired, one per remote entry point.
  n="$(grep -c '^ *[A-Z_]*TERM_RC=0; hf_remote_pane_term ' "$HF")"
  [ "$n" -eq 3 ]
}

@test "kitty_headless is NOT called — it is env-gated the wrong way for a remote pane" {
  # kitty_headless refuses when KITTY_WINDOW_ID or ITERM_SESSION_ID is set, which is right for the
  # SELF question and exactly backwards here: the driver's env says nothing about who owns P.
  # COMMENTS STRIPPED FIRST — the body EXPLAINS why it does not call kitty_headless, and a bare
  # substring grep would convict it of its own rationale. Only executable text is judged.
  body="$(sed -n '/^hf_remote_pane_term() {/,/^}/p' "$HF" | sed 's/[[:space:]]*#.*$//')"
  [ -n "$body" ]
  run bash -c 'printf "%s" "$1" | grep -c "kitty_headless"' _ "$body"
  [ "$output" = "0" ]
  # …and kitty_socket_template, which is unsubstituted and cannot enumerate, is not called either.
  run bash -c 'printf "%s" "$1" | grep -c "kitty_socket_template"' _ "$body"
  [ "$output" = "0" ]
  # The two it MUST use, so this case cannot pass by the function having no body at all.
  run bash -c 'printf "%s" "$1" | grep -c "kitty_sockets"' _ "$body"
  [ "$output" -ge 1 ]
}

@test "the resolver works with a kitty pane's OWN env set — the env is not the gate" {
  # The mirror of the case above, behaviourally: kitty_headless would refuse this outright.
  export KITTY_WINDOW_ID=31
  hf_remote_pane_term 110 || false
  [ "$CC_TERM" = kitty ]
}

@test "…and with a genuine iTerm2 env set too, when the PANE is a kitty integer" {
  # The 2026-07-31 outage was an iTerm2 pane diverted to kitty. That is the SELF question and is
  # not this one: here the caller has explicitly named somebody else's integer pane id.
  export ITERM_SESSION_ID="w0t0p0:E5D77446-0000-0000-0000-000000000000"
  hf_remote_pane_term 110 || false
  [ "$CC_TERM" = kitty ]
}
