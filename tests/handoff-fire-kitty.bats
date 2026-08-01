#!/usr/bin/env bats
# handoff-fire.sh — the kitty branch of the five terminal primitives (2026-07-31).
#
# WHY THIS EXISTS. Five functions in handoff-fire.sh reached the terminal exclusively through iTerm2:
# as_write / _as_tty_query (osascript), as_tab / spawn_frontmost (osascript), and it2py (the iterm2
# Python API). Every one of them is a vendor lock — from inside kitty there is no iTerm2 to answer,
# so each degraded down its own fail-loud path and a handoff could not fire at all. bin/it2-kitty
# already answers the `it2 session …` contract against `kitty @`, so the pane BACKEND was solved;
# these five were the remaining direct-to-iTerm2 calls that bypassed it.
#
# WHAT IS PINNED HERE, and why each is a property a reader could otherwise "simplify" away:
#   1. TERMINAL PINNING. Every test sets the terminal EXPLICITLY — `unset KITTY_WINDOW_ID;
#      IT2_WRAPPER_NO_KITTY=1` for the iTerm2 assertions, `KITTY_WINDOW_ID=…` for the kitty ones. A
#      suite whose verdict depends on which terminal the developer happens to sit in has already
#      broken twice in this repo.
#   2. _as_tty_query's TWO EXIT STATES. A FAILED query returns non-zero (as_tty retries it); an
#      ABSENT pane returns ZERO with empty output (as_tty believes it immediately). Inverting them
#      makes a live successor read as DEAD and closes a healthy session.
#   3. --keep-focus on the bgtab path. It is the entire reason it2py bgtab exists (C1: an autonomous
#      fire must not move the operator's focus). kitty focuses a newly-created tab by DEFAULT, so
#      dropping the flag is a silent focus steal that no other assertion would catch.
#   4. --match on tab/bgtab. kitty otherwise targets the ACTIVE tab, which is exactly the "handoff
#      fired into another window" drift the iTerm2 branch's window walk exists to prevent.
#   5. The stdout CONTRACTS the callers regex: "OK <id>" | "NOTFOUND" (as_tab) and
#      "Created new pane: <id>" (it2py bgtab).
#
# NOTHING HERE EXECUTES scripts/handoff-fire.sh — it FIRES REAL SESSIONS. Functions are EXTRACTED
# with sed, the established pattern in this repo (tests/handoff-fire-it2-bound.bats:26). kitty,
# osascript, ps and the it2 shim are all stubbed; the operator's real kitty is never driven.
#
# Every assertion is `[ ]`, `run`+status, or `… || false`. `[[ ]]` and `(( ))` are errexit-EXEMPT in
# bats and are silently DEAD anywhere but a body's last line — that has burned this repo twice.

setup() {
  # Pin the fire capacity gate OFF. handoff-fire's capacity_gate() refuses a net-new fire above
  # 2.0/core and this box lives well above that, so an unpinned suite goes red-by-LOAD rather than
  # by its subject — a verdict that depends on what else the operator is running. Named by
  # test-hermeticity-lint, which blocks the land on it (and was right: this file exercises
  # handoff-fire). Do NOT add to the fire allowlist instead.
  export CC_FIRE_CAPACITY_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"   # hermeticity ratchet: never live ~/

  # hf_bounded passthrough — same rationale as the sibling suites: these tests extract INDIVIDUAL
  # functions, so the real helper is not in scope. Its own semantics live in handoff-fire-it2-bound.
  hf_bounded() { "$@"; }

  # ── stubs ──────────────────────────────────────────────────────────────────────────────────────
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  KLOG="$BATS_TEST_TMPDIR/kitty.log"; : > "$KLOG"
  OLOG="$BATS_TEST_TMPDIR/osascript.log"; : > "$OLOG"
  ILOG="$BATS_TEST_TMPDIR/it2.log"; : > "$ILOG"
  PLOG="$BATS_TEST_TMPDIR/pybin.log"; : > "$PLOG"
  export KLOG OLOG ILOG PLOG

  KITTY="$STUB/kitty"
  cat > "$KITTY" <<'FAKE'
#!/bin/bash
# fake kitty: logs the full argv, then answers the three verbs this branch uses from env-driven
# fixtures. Never touches a real control socket.
printf '%s\n' "$*" >> "$KLOG"
[ "$1" = "@" ] || exit 64
shift
if [ "$1" = "--to" ]; then shift 2; fi
case "$1" in
  ls)           [ "${KFAKE_LS_RC:-0}" = 0 ] || exit "$KFAKE_LS_RC"; cat "$KFAKE_LS" ;;
  launch)       [ "${KFAKE_LAUNCH_RC:-0}" = 0 ] || exit "$KFAKE_LAUNCH_RC"
                printf '%s\n' "${KFAKE_LAUNCH_ID:-77}" ;;
  focus-window) exit "${KFAKE_FOCUS_RC:-0}" ;;
  *) exit 64 ;;
esac
FAKE
  chmod +x "$KITTY"
  export CC_TERM_KITTY="$KITTY"

  # osascript: the iTerm2-branch sentinel. Its OUTPUT is irrelevant to these tests — its INVOCATION
  # is the assertion (the iTerm2 path was taken), and stubbing it is also what keeps a pinned-iTerm2
  # test from reaching the operator's real iTerm2.
  cat > "$STUB/osascript" <<'FAKE'
#!/bin/sh
printf 'osascript %s\n' "$*" >> "$OLOG"
cat >/dev/null 2>&1 || true
printf '%s\n' "${KFAKE_OSA_OUT:-}"
FAKE
  chmod +x "$STUB/osascript"

  # ps: _as_tty_query maps kitty's window pid → tty through it. Stubbed so the verdict does not
  # depend on whether the bats runner happens to own a controlling terminal.
  cat > "$STUB/ps" <<'FAKE'
#!/bin/sh
printf '%s\n' "${KFAKE_TTY-ttys042}"
FAKE
  chmod +x "$STUB/ps"
  export PATH="$STUB:$PATH"

  # The it2 shim as_write routes through. Under kitty this is what execs bin/it2-kitty.
  SHIM="$HOME/.claude/bin/it2"
  cat > "$SHIM" <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" >> "$ILOG"
exit 0
FAKE
  chmod +x "$SHIM"
  REAL_IT2="$SHIM"

  # it2py's fallthrough interpreter (the `frontapp` verb must still reach it, unchanged).
  PYTHON_BIN="$STUB/pybin"
  cat > "$PYTHON_BIN" <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" >> "$PLOG"
cat >/dev/null 2>&1 || true
printf 'PyPath\n'
FAKE
  chmod +x "$PYTHON_BIN"

  # ── `kitty @ ls` fixture: window 25 focused (pid 4242) + window 31 unfocused (pid 5150) ─────────
  KFAKE_LS="$BATS_TEST_TMPDIR/ls.json"
  ls_focus 25
  export KFAKE_LS

  # ── extract the subject ────────────────────────────────────────────────────────────────────────
  # in_kitty and kt are ONE-LINERS with no `^}` of their own, so a /,/^}/ range would swallow the
  # next function. Extract them by their single line, and GUARD every extraction: an empty eval is
  # a vacuous pass, which is the failure mode this whole suite is supposed to prevent.
  x_kitty="$(sed -n '/^in_kitty() {/p' "$HF")";                    [ -n "$x_kitty" ]
  x_kt="$(sed -n '/^kt() {/p' "$HF")";                             [ -n "$x_kt" ]
  x_field="$(sed -n '/^kt_window_field() {/,/^}/p' "$HF")";        [ -n "$x_field" ]
  x_write="$(sed -n '/^as_write() {/,/^}/p' "$HF")";               [ -n "$x_write" ]
  x_ttyq="$(sed -n '/^_as_tty_query() {/,/^}/p' "$HF")";           [ -n "$x_ttyq" ]
  x_tab="$(sed -n '/^as_tab() {/,/^}/p' "$HF")";                   [ -n "$x_tab" ]
  x_sfm="$(sed -n '/^spawn_frontmost() {/,/^}/p' "$HF")";          [ -n "$x_sfm" ]
  x_py="$(sed -n '/^it2py() {/,/^}/p' "$HF")";                     [ -n "$x_py" ]
  eval "$x_kitty"; eval "$x_kt"; eval "$x_field"
  eval "$x_write"; eval "$x_ttyq"; eval "$x_tab"; eval "$x_sfm"; eval "$x_py"

  pin_iterm2
}

# Rewrite the ls fixture so window $1 is the focused one.
ls_focus() {
  local f="$1"
  printf '[{"id":1,"tabs":[{"windows":[{"id":25,"pid":4242,"is_focused":%s},{"id":31,"pid":5150,"is_focused":%s}]}]}]\n' \
    "$([ "$f" = 25 ] && printf true || printf false)" \
    "$([ "$f" = 31 ] && printf true || printf false)" > "$KFAKE_LS"
}

# TERMINAL PINNING — never inferred from the developer's environment.
pin_iterm2() { unset KITTY_WINDOW_ID; export IT2_WRAPPER_NO_KITTY=1; }
pin_kitty()  { export KITTY_WINDOW_ID=25; unset IT2_WRAPPER_NO_KITTY; }

# ── the predicate itself ─────────────────────────────────────────────────────────────────────────

@test "in_kitty is FALSE on iTerm2, TRUE in kitty, and the kill switch restores iTerm2" {
  pin_iterm2; run in_kitty; [ "$status" -ne 0 ]
  pin_kitty;  run in_kitty; [ "$status" -eq 0 ]
  export IT2_WRAPPER_NO_KITTY=1
  run in_kitty; [ "$status" -ne 0 ]
}

@test "the predicate is textually IDENTICAL to bin/it2-wrapper's — the three copies must not drift" {
  # A divert firing in one file and not another would create the pane with one backend and address
  # it with the other. kitty-divert-real-it2.bats pins the same agreement from the other side.
  norm() { grep -ho 'KITTY_WINDOW_ID[^&]*&&*[^]]*IT2_WRAPPER_NO_KITTY' "$1" | head -1 | tr -d '[:space:]"${}:-[]'; }
  local w h
  w="$(norm "$REPO/bin/it2-wrapper")"; h="$(norm "$HF")"
  [ -n "$w" ]
  [ "$w" = "$h" ]
}

# ── as_write ─────────────────────────────────────────────────────────────────────────────────────

@test "as_write in kitty routes through the it2 shim (ONE seam), not a second kitty spelling" {
  pin_kitty
  run as_write 25 "/exit"
  [ "$status" -eq 0 ]
  grep -qx 'session run -s 25 /exit' "$ILOG"
  # It must NOT open a second, divergent path straight at the control socket.
  [ ! -s "$KLOG" ]
}

@test "as_write in kitty survives self-close mode, where REAL_IT2 is not yet assigned" {
  # as_write is called from self-close (:2616/:2624), which exits ABOVE the top-level REAL_IT2=
  # line. A bare \$REAL_IT2 would trip set -u and abort the teardown mid-close.
  pin_kitty
  unset REAL_IT2
  run as_write 25 ""
  [ "$status" -eq 0 ]
  grep -qx 'session run -s 25 ' "$ILOG"
}

@test "as_write on iTerm2 still goes to osascript — kitty is never consulted" {
  pin_iterm2
  run as_write "ABC-DEF" "/exit"
  [ -s "$OLOG" ]
  [ ! -s "$KLOG" ]
  [ ! -s "$ILOG" ]
}

# ── _as_tty_query: the two exit states are the contract ──────────────────────────────────────────

@test "_as_tty_query in kitty resolves window id → pid → /dev/<tty>" {
  pin_kitty
  run _as_tty_query 25
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/ttys042" ]
}

@test "_as_tty_query: an ABSENT pane is exit 0 + EMPTY (believed), never a retryable failure" {
  # Getting this backwards costs 5 pointless retries and still reads correctly; the INVERSE (below)
  # is what kills a live session, so both directions are pinned.
  pin_kitty
  run _as_tty_query 999
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_as_tty_query: a FAILED query is NON-ZERO (retried), so a live successor is not judged dead" {
  pin_kitty
  export KFAKE_LS_RC=1                       # wedged kitty / no control socket
  run _as_tty_query 25
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "_as_tty_query: unparseable kitty JSON is a FAILED query too, not an empty fleet" {
  pin_kitty
  printf 'not json at all\n' > "$KFAKE_LS"
  run _as_tty_query 25
  [ "$status" -ne 0 ]
}

@test "_as_tty_query: a live window whose ps reports no tty (??) is exit 0 + empty, not a failure" {
  pin_kitty
  export KFAKE_TTY="??"
  run _as_tty_query 25
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_as_tty_query on iTerm2 still goes to osascript — kitty is never consulted" {
  pin_iterm2
  export KFAKE_OSA_OUT="/dev/ttys018"
  run _as_tty_query "ABC-DEF"
  [ "$status" -eq 0 ]
  [ -s "$OLOG" ]
  [ ! -s "$KLOG" ]
}

@test "the HANDOFF_TTY_FAIL_FILE selftest seam still short-circuits BEFORE the kitty branch" {
  # The seam models a failing bridge; it must stay reachable on both terminals or the load-robustness
  # proof in handoff-fire-completion-push.bats becomes kitty-dependent.
  pin_kitty
  export HANDOFF_TTY_FAIL_FILE="$BATS_TEST_TMPDIR/fail"; printf '2' > "$HANDOFF_TTY_FAIL_FILE"
  run _as_tty_query 25
  [ "$status" -ne 0 ]
  [ "$(cat "$HANDOFF_TTY_FAIL_FILE")" = "1" ]
  [ ! -s "$KLOG" ]
}

# ── as_tab ───────────────────────────────────────────────────────────────────────────────────────

@test "as_tab in kitty creates a TAB matched to the FIRING window and keeps the OK <id> contract" {
  pin_kitty
  export KFAKE_LAUNCH_ID=77
  run as_tab 25
  [ "$status" -eq 0 ]
  [ "$output" = "OK 77" ]
  grep -q -- '--type=tab' "$KLOG"
  grep -q -- '--cwd=current' "$KLOG"
  # Without --match kitty targets the ACTIVE tab — the fire drifts into another window.
  grep -q -- '--match id:25' "$KLOG"
}

@test "as_tab in kitty on a DEAD anchor echoes NOTFOUND and returns 0 (the caller classifies)" {
  # A non-zero return would be read as ERR(n) — a bridge error — instead of a gone window.
  pin_kitty
  export KFAKE_LAUNCH_RC=1
  run as_tab 25
  [ "$status" -eq 0 ]
  [ "$output" = "NOTFOUND" ]
}

@test "as_tab in kitty refuses a non-integer launch result rather than landing into it" {
  pin_kitty
  export KFAKE_LAUNCH_ID="Error: no matching window"
  run as_tab 25
  [ "$status" -eq 0 ]
  [ "$output" = "NOTFOUND" ]
}

@test "as_tab on iTerm2 still goes to osascript — kitty is never consulted" {
  pin_iterm2
  export KFAKE_OSA_OUT="OK ABC-DEF"
  run as_tab "XYZ"
  [ "$output" = "OK ABC-DEF" ]
  [ ! -s "$KLOG" ]
}

@test "as_tab with the kill switch set INSIDE kitty falls back to the iTerm2 path (A/B honoured)" {
  export KITTY_WINDOW_ID=25 IT2_WRAPPER_NO_KITTY=1 KFAKE_OSA_OUT="NOTFOUND"
  run as_tab 25
  [ "$output" = "NOTFOUND" ]
  [ ! -s "$KLOG" ]
  [ -s "$OLOG" ]
}

# ── spawn_frontmost ──────────────────────────────────────────────────────────────────────────────

@test "spawn_frontmost in kitty creates an OS-WINDOW and echoes the new id" {
  pin_kitty; FOLLOW=1
  export KFAKE_LAUNCH_ID=88
  run spawn_frontmost
  [ "$status" -eq 0 ]
  [ "$output" = "88" ]
  grep -q -- '--type=os-window' "$KLOG"
}

@test "spawn_frontmost AUTONOMOUS (--follow off) keeps the operator's focus (C1)" {
  # kitty focuses a new os-window by DEFAULT — the opposite polarity of iTerm2's `activate`. Without
  # --keep-focus an autonomous fire yanks the operator out of whatever they were doing.
  pin_kitty; FOLLOW=0
  run spawn_frontmost
  [ "$status" -eq 0 ]
  grep -q -- '--keep-focus' "$KLOG"
}

@test "spawn_frontmost WITH --follow raises the new window (no --keep-focus)" {
  pin_kitty; FOLLOW=1
  run spawn_frontmost
  [ "$status" -eq 0 ]
  ! grep -q -- '--keep-focus' "$KLOG" || false
}

@test "spawn_frontmost in kitty prints NOTHING on failure — the caller's fail-loud signal" {
  pin_kitty; FOLLOW=1
  export KFAKE_LAUNCH_RC=1
  run spawn_frontmost
  [ -z "$output" ]
}

@test "spawn_frontmost on iTerm2 still goes to osascript — kitty is never consulted" {
  pin_iterm2; FOLLOW=1
  export KFAKE_OSA_OUT="ABC-DEF"
  run spawn_frontmost
  [ "$output" = "ABC-DEF" ]
  [ ! -s "$KLOG" ]
}

# ── it2py ────────────────────────────────────────────────────────────────────────────────────────

@test "it2py active in kitty returns the FOCUSED window's id" {
  pin_kitty
  run it2py active
  [ "$status" -eq 0 ]
  [ "$output" = "25" ]
  ls_focus 31
  run it2py active
  [ "$output" = "31" ]
}

@test "it2py restore in kitty focuses the pane and confirms it took (rc 0)" {
  pin_kitty
  run it2py restore 25 "kitty"
  [ "$status" -eq 0 ]
  grep -q -- '--match id:25' "$KLOG"
}

@test "it2py restore returns rc 5 when kitty REFUSES the focus (not-restored, the C1 verdict)" {
  pin_kitty
  export KFAKE_FOCUS_RC=1
  run it2py restore 25 "kitty"
  [ "$status" -eq 5 ]
}

@test "it2py restore returns rc 5 when focus-window SUCCEEDS but focus did not actually move" {
  # focus-window can exit 0 having matched nothing. Without the re-read, a genuine focus steal would
  # report as restored and restore_focus_or_fail would leave the operator displaced.
  pin_kitty
  ls_focus 31                                  # the focused window is NOT the one we asked for
  run it2py restore 25 "kitty"
  [ "$status" -eq 5 ]
}

@test "it2py bgtab in kitty creates a BACKGROUND tab — --keep-focus is the whole point" {
  pin_kitty
  export KFAKE_LAUNCH_ID=77
  run it2py bgtab 25
  [ "$status" -eq 0 ]
  [ "$output" = "Created new pane: 77" ]       # EXACT format it2_bgtab regexes
  grep -q -- '--keep-focus' "$KLOG"
  grep -q -- '--type=tab' "$KLOG"
  grep -q -- '--match id:25' "$KLOG"
}

@test "it2py bgtab returns rc 1 when the anchor window is gone" {
  pin_kitty
  export KFAKE_LAUNCH_RC=1
  run it2py bgtab 25
  [ "$status" -eq 1 ]
}

@test "it2py bgtab refuses a non-integer launch result (rc 1), never a phantom pane id" {
  pin_kitty
  export KFAKE_LAUNCH_ID="Error: no matching window"
  run it2py bgtab 25
  [ "$status" -eq 1 ]
}

@test "it2py frontapp is UNCHANGED in kitty — it falls through to the Python driver" {
  # The frontmost macOS app is terminal-agnostic (System Events), so there is nothing to port. It
  # must NOT be captured by the kitty case arm.
  pin_kitty
  run it2py frontapp
  [ "$status" -eq 0 ]
  [ "$output" = "PyPath" ]
  [ -s "$PLOG" ]
  [ ! -s "$KLOG" ]
}

@test "it2py anchor is UNCHANGED in kitty too — headless anchoring was not ported" {
  # Pinned so a later reader does not assume the kitty arm covers every verb: resolve_headless_anchor
  # degrades to its documented rc-2 "inconclusive, refuse" state under kitty, which is the safe one.
  pin_kitty
  run it2py anchor "" 5
  [ -s "$PLOG" ]
  [ ! -s "$KLOG" ]
}

@test "every it2py verb on iTerm2 still reaches the Python driver — kitty is never consulted" {
  pin_iterm2
  run it2py active;            [ "$output" = "PyPath" ]
  run it2py restore ABC front; [ "$output" = "PyPath" ]
  run it2py bgtab ABC;         [ "$output" = "PyPath" ]
  [ ! -s "$KLOG" ]
}

# ── the bound ────────────────────────────────────────────────────────────────────────────────────

@test "every kitty control-socket call goes through hf_bounded (no unbounded fork in a fire path)" {
  # A wedged terminal API is what stalled self-close for ~100s on 2026-07-26. The kitty socket has no
  # serializing queue, but an unbounded call in a spawn path still hangs the fire with no diagnostic.
  [ -n "$x_kt" ]
  grep -qF 'hf_bounded' <<<"$x_kt"
  # …and nothing in the ported branches shells out to kitty except through kt(). Comments are
  # stripped first — this file's own prose names `kitty @` repeatedly, and a check that a comment
  # can fail is a check that will be silenced by rewording rather than by fixing.
  local code
  code="$(printf '%s\n' "$x_write" "$x_ttyq" "$x_tab" "$x_sfm" "$x_py" | sed 's/#.*//')"
  ! grep -qE '(^|[^_a-zA-Z])kitty @' <<<"$code" || false
}
