#!/usr/bin/env bash
# cc-type-verified.sh — VERIFIED TYPING of a command line into an iTerm2 pane, over the OSASCRIPT
# transport. Source, don't execute. Pure function definitions, no side effects (safe under `set -u`).
#
# ── WHY THIS EXISTS (backlog item 270106134cc8) ────────────────────────────────────────────────────
# This operator's ~/.zshrc:53 sets `setopt CORRECT`. zsh offers a spelling correction for an unknown
# COMMAND WORD as ZLE *reads* the line — before any of it executes — and the offer is an interactive
# prompt: `zsh: correct 'X' to 'Y' [nyae]?`. No automated caller can answer it. The pane parks
# FOREVER while the firing script reports success: a whole dispatched work item lost, silently
# (observed 2026-07-26, 6m40s wedge; a second class-instance 2026-07-29 on `go` → `god`).
#
# scripts/handoff-fire.sh learned this the expensive way and carries the full discipline
# (FIRE_NOCORRECT_LINE + _it2_type_line). A 2026-07-30 call-site sweep found it was the ONLY file
# that did. Three production sites use the same create-pane-then-write-text pattern, cite
# handoff-fire.sh as their model in their own comments, and never picked the discipline up:
#   · scripts/limit-recover/lr-reset-poller.sh  (spawn_gui)  — UNATTENDED, from a LaunchAgent
#   · scripts/limit-recover/lr-handoff.sh       (split + fallback window)
#   · scripts/boot-resume-launch.sh                          — runs at BOOT, from launchd
# None was a live defect at filing time, WHICH IS THE POINT: each survived on a property NOTHING
# PINNED — `exec` happens to be a builtin, `/bin/bash` happens to be an absolute path, and
# boot-resume-launch's shq() happens to single-quote every word (zsh skips correction for a quoted
# command word). Drop the quoting, point CC_RESUME_ONE_BIN at a bare name, or add a branch whose
# first word is a bare command, and two of the three park forever with nobody present to answer.
#
# ── WHY A SHARED HELPER AND NOT A COPY-PASTED `unsetopt` LINE ──────────────────────────────────────
# The naive fix — blind-send `unsetopt correct correct_all` before the command — is WORSE THAN IT
# LOOKS, and the reason is the whole justification for this file. The pane being typed into is
# FRESHLY CREATED, so its zsh may not have finished starting: ZLE, zsh-autosuggestions and
# zsh-syntax-highlighting all process input per-character, and bracketed-paste-magic deliberately
# re-injects a paste through ZLE as keystrokes. A line typed into that window can arrive MANGLED.
# And a mangled `unsetopt` — `unstopt`, say — is no longer a zsh builtin, so it is ITSELF
# correction-eligible: the disarm line becomes a new instance of the exact hang it was added to
# prevent. That is precisely why handoff-fire ECHO-VERIFIES its disarm line rather than blind-sending
# it, and why "prepend one line at three sites" is not the fix. The discipline is the fix, so the
# discipline is what gets shared.
#
# ── WHY THE OSASCRIPT TRANSPORT, NOT handoff-fire's it2 CLI ────────────────────────────────────────
# handoff-fire's _it2_type_line drives the `it2` CLI, which needs the iTerm2 Python API (a python
# with the `iterm2` module, plus the API enabled in a running iTerm2). Two of the three callers here
# run from launchd — one of them at BOOT, when iTerm2 has only just been asked to start — so taking a
# Python-API dependency would trade a rare silent hang for a common hard failure on the one path that
# has no operator watching. MEASURED 2026-08-07 on this box: the osascript transport supports the
# FULL discipline natively, with no such dependency —
#   · `write text "…" newline no`  types WITHOUT submitting (the un-submitted input line is real)
#   · `contents of <session>`      reads the visible screen back, INCLUDING that pending input line
#   · `write text "" newline yes`  sends the bare CR that submits it
# So this is the same proof-gated discipline, expressed over the transport its callers already use
# and already depend on. Nothing about the guarantee is weaker; only the plumbing differs.
#
# ── THE GUARANTEE ──────────────────────────────────────────────────────────────────────────────────
# The destructive keystroke — Enter, which makes the shell RUN the line — is gated on POSITIVE PROOF
# that the intact line is sitting on the input line. A mangled line is NEVER executed: it is scrubbed
# and retyped. Exhausting the attempts fails LOUD (rc 1) rather than sending a hopeful CR.
#
# CONTRACT
#   osa_type_verified <session-uuid> <command>   → 0 verified + submitted · 1 fail-loud
#   CC_NOCORRECT_LINE   the canonical disarm line (byte-identical to handoff-fire's
#                       FIRE_NOCORRECT_LINE; tests/typed-send-shared-discipline.bats pins the pair)
#
# SEAMS (all overridable so tests run in ms rather than seconds)
#   CC_TYPE_ATTEMPTS    typed attempts per line          (default 4)
#   CC_TYPE_SETTLE      seconds after typing, before the read-back  (default 0.5)
#   CC_TYPE_PRESETTLE   seconds after the scrub, before typing      (default 0.12)
#   CC_NOCORRECT        1 = type the disarm line first; 0 = skip it (default 1)
#   CC_OSASCRIPT_BIN    the osascript binary (test seam; boot-resume-launch.sh already uses this name)
#   CC_TYPE_TIMEOUT_S   per-AppleEvent wall-clock bound  (default 15)
#   CC_TYPE_TIMEOUT_BIN explicit timeout(1); SET-BUT-EMPTY means UNBOUNDED, honored verbatim

CC_NOCORRECT_LINE='unsetopt correct correct_all 2>/dev/null || true'

# Sentinel returned by the AppleScript when the uuid resolves to no live session — OR when iTerm2 is
# not running at all. Distinguishing "the pane is gone" from "the screen did not contain the line"
# matters: the first is terminal and retrying is pure latency, the second is exactly what a retry is
# for.
#
# iTerm2 IS ADDRESSED BY BUNDLE ID, BEHIND AN `is running` PROBE, and never by name (the rule
# scripts/boot-resume-launch.sh and lr-reset-poller.sh landed 2026-07-31/08-07). "iTerm2" is only
# the CFBundleName of iTerm.app, so a NAME lookup resolves solely while iTerm2 already runs; on this
# kitty-migrated fleet it otherwise raises an undismissable "Where is iTerm2?" modal — and every
# caller here is unattended, so nobody would dismiss it. The `is running` probe is the one reference
# that never LAUNCHES the app, which matters just as much: resurrecting the abandoned terminal
# behind the operator is what made those callers remove `open -a iTerm` in the first place.
CC_TV_NOSESS='__CC_TV_NO_SUCH_SESSION__'

CC_TYPE_TIMEOUT_S="${CC_TYPE_TIMEOUT_S:-15}"

# An AppleEvent has no timeout of its own: a wedged iTerm2 does not fail the call, it waits forever
# (the machine-wide AppleEvent wedge of 2026-07-26). Bound it. Same probe order and same
# set-but-empty-means-unbounded discipline as hooks/lib/osa.sh — restated rather than sourced,
# because this file's two launchd callers must not depend on a second lib being deployed first.
if [ -n "${CC_TYPE_TIMEOUT_BIN+set}" ]; then
  CC_TV_TB="${CC_TYPE_TIMEOUT_BIN}"
else
  CC_TV_TB=""
  for _cc_tv_c in "$(command -v timeout 2>/dev/null || true)" \
                  "$(command -v gtimeout 2>/dev/null || true)" \
                  /usr/bin/timeout /opt/homebrew/bin/timeout /usr/local/bin/timeout \
                  /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_cc_tv_c" ] && [ -x "$_cc_tv_c" ] && { CC_TV_TB="$_cc_tv_c"; break; }
  done
  unset _cc_tv_c
fi

# No timeout(1) anywhere ⇒ run UNBOUNDED rather than lose the call: failing closed here would delete
# every resume on a box without coreutils, which is worse than the occasional hang it would prevent.
_cc_tv_bounded() {
  if [ -z "$CC_TV_TB" ] || [ ! -x "$CC_TV_TB" ]; then "$@"; return $?; fi
  "$CC_TV_TB" -k 3 "$CC_TYPE_TIMEOUT_S" "$@"
}

# ── the three AppleEvents ──────────────────────────────────────────────────────────────────────────
# All keep their script in ARGV as `-e` fragments and pass the DATA as trailing argv items. Two
# separate reasons, both load-bearing:
#   · QUOTING — the command being typed is arbitrary shell text (quotes, backslashes, `$`). Splicing
#     it into an AppleScript string literal is a quoting minefield; `on run argv` sidesteps it
#     entirely. (Verified 2026-08-07: `osascript -e … -e … 'arg'` does populate argv.)
#   · OBSERVABILITY — tests/lr-reset-poller.bats' osascript stub observes the spawn through ARGV and
#     says so at the call site: a heredoc "would move it to stdin and silently blind three GUI-spawn
#     assertions". Keeping the script in `-e` preserves that fixture shape for every caller.
_cc_tv_scrub_type_read() { # <sid> <wire> <presettle> <settle> → the pane's visible contents on stdout
  _cc_tv_bounded "${CC_OSASCRIPT_BIN:-osascript}" \
    -e 'on run argv' \
    -e 'set sid to item 1 of argv' \
    -e 'set txt to item 2 of argv' \
    -e "if not (application id \"com.googlecode.iterm2\" is running) then return \"$CC_TV_NOSESS\"" \
    -e 'tell application id "com.googlecode.iterm2"' \
    -e 'repeat with w in windows' \
    -e 'repeat with t in tabs of w' \
    -e 'repeat with s in sessions of t' \
    -e 'if id of s is sid then' \
    -e 'tell s to write text (ASCII character 21) newline no' \
    -e 'delay ((item 3 of argv) as number)' \
    -e 'tell s to write text txt newline no' \
    -e 'delay ((item 4 of argv) as number)' \
    -e 'return (contents of s)' \
    -e 'end if' \
    -e 'end repeat' \
    -e 'end repeat' \
    -e 'end repeat' \
    -e 'end tell' \
    -e "return \"$CC_TV_NOSESS\"" \
    -e 'end run' \
    "$1" "$2" "$3" "$4" 2>/dev/null
}

_cc_tv_submit() { # <sid> — send the bare CR that executes the verified line
  _cc_tv_bounded "${CC_OSASCRIPT_BIN:-osascript}" \
    -e 'on run argv' \
    -e 'set sid to item 1 of argv' \
    -e "if not (application id \"com.googlecode.iterm2\" is running) then return \"$CC_TV_NOSESS\"" \
    -e 'tell application id "com.googlecode.iterm2"' \
    -e 'repeat with w in windows' \
    -e 'repeat with t in tabs of w' \
    -e 'repeat with s in sessions of t' \
    -e 'if id of s is sid then' \
    -e 'tell s to write text "" newline yes' \
    -e 'return "ok"' \
    -e 'end if' \
    -e 'end repeat' \
    -e 'end repeat' \
    -e 'end repeat' \
    -e 'end tell' \
    -e "return \"$CC_TV_NOSESS\"" \
    -e 'end run' \
    "$1" 2>/dev/null
}

_cc_tv_scrub() { # <sid> — Ctrl-U, discarding whatever half-line is on the input line
  _cc_tv_bounded "${CC_OSASCRIPT_BIN:-osascript}" \
    -e 'on run argv' \
    -e 'set sid to item 1 of argv' \
    -e "if not (application id \"com.googlecode.iterm2\" is running) then return \"$CC_TV_NOSESS\"" \
    -e 'tell application id "com.googlecode.iterm2"' \
    -e 'repeat with w in windows' \
    -e 'repeat with t in tabs of w' \
    -e 'repeat with s in sessions of t' \
    -e 'if id of s is sid then' \
    -e 'tell s to write text (ASCII character 21) newline no' \
    -e 'return "ok"' \
    -e 'end if' \
    -e 'end repeat' \
    -e 'end repeat' \
    -e 'end repeat' \
    -e 'end tell' \
    -e "return \"$CC_TV_NOSESS\"" \
    -e 'end run' \
    "$1" >/dev/null 2>&1 || true
}

# ── ONE verified typed line: scrub → type (no CR) → echo-verify → CR ──────────────────────────────
#
# NONCE-ANCHORED, inheriting handoff-fire's fix for the claimed-outcome-vs-checked-outcome class.
# The read surface is the WHOLE visible screen, which includes STALE EVIDENCE OF SUCCESS: a copy of
# this very command left in the scrollback by an earlier failed attempt, an earlier spawn into the
# same pane, or the echoed line sitting above a wedged `[nyae]` prompt. Grepping the screen for a
# FIXED string — the command itself — therefore lets the check PASS on evidence from a previous
# FAILURE, and the CR then runs a mangled fragment. Each attempt instead mints a fresh nonce and
# types `: <nonce>; <line>`, so what is sought is unique to THIS attempt and no residue can satisfy
# it. `:` is the POSIX no-op builtin — never correction-eligible, argument ignored — so the executed
# semantics are unchanged and the prefix is inert in zsh and bash alike.
_cc_tv_type_line() { # <sid> <line> → 0 verified + submitted · 1 fail-loud
  local sid="$1" line="$2" attempt nonce wire want screen
  local attempts="${CC_TYPE_ATTEMPTS:-4}"
  local settle="${CC_TYPE_SETTLE:-0.5}" presettle="${CC_TYPE_PRESETTLE:-0.12}"

  [ -n "$sid" ] || return 1
  # Emptiness is judged on the CALLER's line, never on the wire form: the nonce prefix makes the wire
  # non-empty for every input, so checking the wire would silently submit an empty command.
  [ -n "$(printf '%s' "$line" | tr -d '[:space:]')" ] || return 1

  for attempt in $(seq 1 "$attempts"); do
    # Fresh per ATTEMPT, not per call: attempt N must not be satisfiable by attempt N-1's echo.
    nonce="cctv-$$-${attempt}-${RANDOM:-0}"
    wire=": $nonce; $line"
    want="$(printf '%s' "$wire" | tr -d '[:space:]')"

    screen="$(_cc_tv_scrub_type_read "$sid" "$wire" "$presettle" "$settle" || true)"
    # The pane is GONE — terminal. Retrying cannot resurrect it, and the caller needs the failure now.
    case "$screen" in *"$CC_TV_NOSESS"*) return 1 ;; esac

    # Whitespace stripped from BOTH sides so a line that WRAPPED across terminal columns still matches.
    if printf '%s' "$screen" | tr -d '[:space:]' | grep -qF -- "$want"; then
      _cc_tv_submit "$sid" >/dev/null 2>&1 && return 0
    fi
    _cc_tv_scrub "$sid"          # drop the mangled/half line before retrying
    sleep "$settle" 2>/dev/null || true
  done
  return 1
}

# ── the caller-facing entry point ──────────────────────────────────────────────────────────────────
# Types the spell-correction disarm as its OWN accepted line, then the command, each under the proof
# above. The disarm must be a separate ACCEPTED line: because CORRECT fires at READ time, an inline
# `unsetopt correct` on the same line cannot help — it has not run when the line is read. (That is
# the same reason handoff-fire moved its package-manager chain out of the typed line entirely.)
#
# The disarm is BEST-EFFORT BY DESIGN and must never fail an otherwise-healthy spawn: it can only
# ever REMOVE a way to hang. Under bash the whole line is a silent no-op (`unsetopt` not found →
# stderr suppressed → `|| true`), so it is safe to type into any shell — which is why this, and not
# the zsh-only `nocorrect` reserved word, is the shared form. (`nocorrect` shields ONE word and is a
# zsh parser construct; a bash-shelled pane would answer it with `command not found` and never run
# the command at all. handoff-fire can use it because its typed word is provably a zsh alias; these
# callers type absolute paths that a bash pane would otherwise run fine.)
#
# The COMMAND's own verification is NOT best-effort: its failure is the caller's failure.
osa_type_verified() { # <session-uuid> <command> → 0 verified + submitted · 1 fail-loud
  local sid="$1" cmd="$2"
  [ -n "$sid" ] || return 1
  [ -n "$(printf '%s' "$cmd" | tr -d '[:space:]')" ] || return 1
  if [ "${CC_NOCORRECT:-1}" = 1 ]; then
    _cc_tv_type_line "$sid" "$CC_NOCORRECT_LINE" \
      || echo "cc-type-verified: could not disarm zsh spell-correction in pane $sid — proceeding (the command line is still echo-verified)" >&2
  fi
  _cc_tv_type_line "$sid" "$cmd"
}
