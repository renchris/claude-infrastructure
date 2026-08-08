#!/bin/bash
# typed-send-lint — a RATCHET on TYPED COMMAND LINES.
#
# WHY: this operator's zsh runs with `setopt CORRECT`. Type a command line into an interactive pane
# whose first word the shell does not recognise — because a paste raced ZLE and lost a character,
# because autosuggestions rewrote the buffer mid-keystroke, because the pane was still booting — and
# zsh does NOT run it and does NOT fail. It parks the pane forever on
#     zsh: correct 'clade' to 'claude' [nyae]?
# waiting for a keypress from a human who is not there. The fire reports success; the work never
# starts. Observed 2026-07-26 as a 6m40s wedge that lost a whole dispatched work item silently.
#
# THE RULE: every site that types a COMMAND LINE into an interactive shell pane must route through a
# sanctioned VERIFIED-TYPING helper — one that pastes the line, READS THE PANE BACK to prove the line
# landed intact, and only then sends the Enter that makes the shell run it. The sanctioned helpers:
#   · it2_type_verified / _it2_type_line   (scripts/handoff-fire.sh)
#   · osa_type_verified                    (scripts/lib/cc-type-verified.sh)
# A raw send is a silent-hang landmine; a verified send degrades to a LOUD failure instead.
#
# THE RAW PRIMITIVES this flags — every way a shell pane can be made to execute a line:
#   · osascript `write text`      (iTerm2: writes the text AND a return — it executes)
#   · AppleScript `do script`     (Terminal.app / iTerm2 legacy: same)
#   · AppleScript `keystroke` / `key code`  (types into whatever has focus)
#   · `tmux send-keys`
#   · `it2 … session send` / `async_send_text`  (byte-level, and what the helpers are BUILT ON)
#
# THREE THINGS IT DELIBERATELY DOES NOT FLAG, because a lint with false positives gets turned off:
#   · A CONTROL-CHARACTER payload on a byte-level send — `session send -s "$id" $'\r'`, `$'\x15'`.
#     A bare CR or Ctrl-U types no command line, so no first word exists to be mis-corrected. This
#     is what keeps the nudge/scrub sends (handoff-fire.sh:1664, :1747) out of the report.
#   · The SANCTIONED HELPERS' OWN INTERNALS. They necessarily contain the raw primitive — that is
#     what they are. The exemption is by ENCLOSING FUNCTION NAME, not by file: a raw send elsewhere
#     in the same file is still a violation, and one placed AFTER the helper closes is still a
#     violation. A file-wide exemption would have made handoff-fire.sh — the file that owns the
#     helpers, and the one most likely to grow a new raw send — permanently unreachable.
#   · PROSE. This repo discusses `write text`, `keystroke` and `session send` in comments constantly
#     (desk-invariant.sh alone mentions "keystroke" nine times, always to say it does NOT do one).
#     Full-line comments are dropped, trailing comments are dropped, and every verb must be followed
#     by something argument-shaped — a quote, a paren, a `$`, a backslash — so a backticked mention
#     in prose cannot match. A detector that reports text ABOUT the defect reports the fix as the bug
#     (memory: detector-matching-its-own-skill-description).
#   Also out of scope by construction: `display notification` / `display dialog` osascript calls
#   (they type nothing), non-shell files, and tests/ subtrees (never symlink-deployed).
#
# WHY A RATCHET AND NOT A FLAG-DAY: the sites that carry the shape today are real and are being
# rewired, but a lint that cannot go green on the tree it ships with is rot — the nightly runs every
# scripts/*lint*.sh, so one standing red poisons the whole signal. Existing sites are grandfathered
# BY PATH (or by PATH::FUNCTION, which keeps the rest of a large file under jurisdiction) and the
# rule binds where it is free: NEW code. The list can only SHRINK — fixing a site and forgetting to
# delete its line is itself RED, which is what stops a ratchet from becoming a permanent exemption
# list.
#
# Exit: 0 = clean · 1 = violation(s) · 2 = bad usage / unusable scan tree / unrunnable detector
# (LOUD, never a silent green — a check whose own tool could not run has nothing to say about
# the tree, and 1 would read as "your tree is dirty").
#
# Usage: typed-send-lint.sh [scan-root]        (default: the repo root this script lives in)
#        typed-send-lint.sh --selftest         (fixtures, both directions)
#
# Env seams: CC_TYPEDSEND_ALLOWLIST overrides the embedded ratchet (used by --selftest and the
# tests) · CC_TYPEDSEND_SANCTIONED overrides the sanctioned-helper function-name set, so a new
# verified-typing helper can be admitted without a code change while its name is being settled.
#
# Per-line opt-out for an INTENTIONAL counter-example (a fixture, a doc string, a deliberate raw
# send that has been reviewed): `typed-send-lint:allow — <reason>`, accepted as a trailing marker or
# on the nearest preceding comment line. Never use it to silence a real site — that is the ratchet's
# job, and the ratchet is the one that gets audited.
#
# SC2016 is disabled FILE-WIDE, deliberately: nearly every --selftest fixture must contain a LITERAL
# `$'\r'`, `$LAUNCHER` or `$id` and must NOT expand it — expansion would substitute this script's
# environment into the sample being matched and quietly destroy the controls. The gate runs
# ShellCheck bare, where 20-odd such infos would be a hard red, and per-line directives would
# outnumber the code. (Note the capital in "ShellCheck" wherever this file names the tool in prose:
# a comment whose FIRST word is the lowercase directive name parses as a MALFORMED DIRECTIVE and
# aborts analysis of the entire file.)
# shellcheck disable=SC2016
set -uo pipefail

# Resolve $0 THROUGH symlinks before deriving ROOT — ~/.claude/scripts/ is a directory of per-file
# symlinks into this checkout, so an unresolved `dirname "$0"/..` lands in ~/.claude, which has no
# scripts/hooks/bin to scan and would exit 2 forever. (scripts/self-path-lint.sh is the ratchet that
# enforces this; no `readlink -f` — that is GNU-only and this box is BSD.)
_resolve_self() {  # <path> → absolute path, every symlink hop resolved
  local p="$1" d
  while [ -L "$p" ]; do
    d="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd)" "$(basename "$p")"
}
SELF="$(_resolve_self "${BASH_SOURCE[0]:-$0}")"
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"

# The symlink-deployed layers — the code that can actually fire a pane at runtime.
LAYERS="scripts hooks bin"

# ── the sanctioned verified-typing helpers, BY FUNCTION NAME ──────────────────────────────────────
# A raw primitive inside one of these is the helper doing its job. Anywhere else it is a landmine.
# Keyed on the name and not the file so the exemption ends where the function ends.
EMBEDDED_SANCTIONED="$(cat <<'SANCT'
it2_type_verified
_it2_type_line
osa_type_verified
_cc_tv_type_line
_cc_tv_scrub_type_read
_cc_tv_submit
_cc_tv_scrub
SANCT
)"

# ── the ratchet: sites grandfathered with a raw typed send. ────────────────────────────────────────
# ONLY EVER DELETE LINES FROM THIS LIST.
# Entries are repo-relative paths, optionally narrowed to one function with `path::function`. Prefer
# the narrow form: it leaves the REST of a large file under jurisdiction, and it goes stuck (RED) if
# the function is renamed or deleted, which a bare path cannot notice.
#
# The three TRANSIENT entries this list shipped with are GONE — they were the sites being rewired
# onto osa_type_verified while this lint was written, and deleting them is what the ratchet's
# downward half demanded once that rewire landed. Do not re-add them.
#
# The two handoff-fire entries are the real grandfathers: as_write() types `/exit` at a pane and
# it2_paste_submit() submits a brief into what it has proven is a composer — both older than this
# rule, both still owed a routing through a verified helper.
#
# bin/cc-pane::drv_iterm2_send is the FIRST entry this lint did not ship with, and the reason it is
# here rather than fixed is worth stating. It arrived on main 2026-08-07, independently of this
# work, and it is the exact shape the backlog item predicted would slip through: *"nothing today
# fails if someone adds a NEW surface that calls `session send` directly"*. The lint caught it on
# its first exposure — which is the lint doing its job, not a false positive. It is grandfathered
# rather than rewired because `cc-pane send <id> <text…>` is a GENERIC public verb whose payload is
# caller-supplied: it may legitimately carry control characters, which need no verification, as well
# as command lines, which do. Deciding that contract belongs to cc-pane's author, not to this
# change, and it has no in-repo callers yet — so the cost of leaving it is bounded and visible,
# while silently exempting it would defeat the whole point of the ratchet. Tracked in the backlog.
EMBEDDED_ALLOWLIST="$(cat <<'ALLOW'
scripts/handoff-fire.sh::as_write
scripts/handoff-fire.sh::it2_paste_submit
bin/cc-pane::drv_iterm2_send
ALLOW
)"

# ── the detector ──────────────────────────────────────────────────────────────────────────────────
# ONE awk pass per file, deliberately. The precedent lints built this predicate out of piped greps
# and then needed retry machinery, because under fork pressure a `grep` that could not RUN was
# indistinguishable from "no match" and the ratchet FABRICATED violations naming good files
# (memory: named-failure-vs-no-verdict). One fork has no such pipeline, and awk reports "I could not
# run" as a non-zero exit — a different signal from "I found nothing".
#
# No interval expressions ({n,m}) anywhere in the program: the classic one-true-awk that ships as
# /usr/bin/awk on this box has not always supported them, and a silently-unmatched pattern here is a
# false GREEN.
#
# Emits one TAB-separated record per violation:  <lineno>\t<function|->\t<kind>\t<raw line>
raw_typed_sends() {  # <file> <sanctioned-names, newline-delimited> → records; rc 0 = ran, non-0 = could not run
  # The sanctioned set crosses into awk COMMA-delimited, never newline-delimited: the one-true-awk
  # that is /usr/bin/awk here rejects a literal newline inside a `-v` assignment outright ("newline
  # in string"), which made the detector unrunnable for EVERY file — a whole-tree exit 2. Loud, and
  # caught by the selftest, but only because the third state exists at all.
  awk -v SANCT="$(printf '%s' "$2" | tr '\n' ',')" '
    BEGIN {
      Q = "\047"                       # a literal apostrophe: this program is single-quoted
      ARG = "[\"(\\\\$" Q "]"          # what an ARGUMENT looks like — quote, paren, $, backslash
      nsn = split(SANCT, sarr, ",")
      for (si = 1; si <= nsn; si++) if (sarr[si] != "") sanct[sarr[si]] = 1
      fn = "-"; infn = 0; pending = 0
    }
    function is_comment(s) { return s ~ /^[[:space:]]*#/ }

    # Drop a TRAILING comment so prose in one cannot be read as code. Quote-aware, so `${v#pat}` and
    # a "#" inside a string survive: only a hash that is outside quotes AND preceded by whitespace
    # opens a comment. An unbalanced quote (a string continued onto the next line) strips nothing,
    # which is the safe direction — it can only ever leave MORE text to match.
    function strip_comment(s,   i, c, p, q1, q2, L) {
      q1 = 0; q2 = 0; L = length(s)
      for (i = 1; i <= L; i++) {
        c = substr(s, i, 1)
        if (c == "\\") { i++; continue }
        if (c == "\"" && q2 == 0) { q1 = 1 - q1; continue }
        if (c == Q && q1 == 0)    { q2 = 1 - q2; continue }
        if (c == "#" && q1 == 0 && q2 == 0) {
          if (i == 1) return ""
          p = substr(s, i - 1, 1)
          if (p == " " || p == "\t") return substr(s, 1, i - 1)
        }
      }
      return s
    }

    # Is this line AppleScript at all? An AppleScript verb has no power outside a `tell` block or an
    # `osascript` invocation, so requiring that context costs no real detection — you cannot write
    # AppleScript that types without one — and it buys the false positive that matters: this repo
    # writes the WORDS in ordinary message strings all the time
    # (`badp "stunned: KEYSTROKED a live composer"`, `notify "… no keystroke \"here\""`). Without
    # this, a status message about NOT typing reads as typing.
    function as_ctx(s) {
      if (s ~ /osascript/) return 1
      if (s ~ /(^|[^A-Za-z0-9_])tell[[:space:]]/) return 1
      # a heredoc / -e continuation line where the verb IS the statement
      return (s ~ ("^[[:space:]]*[\"\\\\" Q "]?(write[[:space:]]+text|do[[:space:]]+script|keystroke|key[[:space:]]+code)"))
    }

    # Which raw primitive is on this line, if any. Sets POS to just past the verb so the payload can
    # be inspected. Every verb REQUIRES an argument-shaped follower — that is what keeps a backticked
    # mention in prose (`write text`, "no keystroke here") out of the report.
    function prim(s,   as) {
      as = as_ctx(s)
      if (as && match(s, "(^|[^A-Za-z0-9_])write[[:space:]]+text[[:space:]]*" ARG))              { POS = RSTART + RLENGTH; return "write-text" }
      if (as && match(s, "(^|[^A-Za-z0-9_])do[[:space:]]+script[[:space:]]*" ARG))               { POS = RSTART + RLENGTH; return "do-script" }
      if (as && match(s, "(^|[^A-Za-z0-9_])keystroke[[:space:]]+[\"\\\\$" Q "]"))                { POS = RSTART + RLENGTH; return "keystroke" }
      if (as && match(s, "(^|[^A-Za-z0-9_])keystroke[[:space:]]+(return|tab|space)([^A-Za-z0-9_]|$)")) { POS = RSTART + RLENGTH; return "keystroke" }
      if (as && match(s, "(^|[^A-Za-z0-9_])key[[:space:]]+code[[:space:]]+[0-9]"))               { POS = RSTART + RLENGTH; return "keystroke" }
      if (match(s, "(^|[^A-Za-z0-9_])send-keys[[:space:]]+[-\"\\\\$" Q "]"))                     { POS = RSTART + RLENGTH; return "send-keys" }
      if (match(s, "(^|[^A-Za-z0-9_])session[[:space:]]+send([^A-Za-z0-9_-]|$)"))          { POS = RSTART + RLENGTH; return "session-send" }
      if (match(s, "(^|[^A-Za-z0-9_])async_send_text([^A-Za-z0-9_]|$)"))                   { POS = RSTART + RLENGTH; return "async-send" }
      return ""
    }

    # A byte-level send whose payload is nothing but control characters types no command line, so no
    # first word exists for the shell to mis-correct. The cut at the first redirection/operator runs
    # from the VERB, never from the start of the line — `[ "$w" = 60 ] && … session send … $QUOTE\rQUOTE`
    # would otherwise be truncated before the payload was ever seen. Cutting conservatively can only
    # ever make a payload look LESS control-like, i.e. flag more — never less.
    function ctrl_only(rest,   t, i, w) {
      if (match(rest, /[>|;&]/)) rest = substr(rest, 1, RSTART - 1)
      sub(/^[[:space:]]+/, "", rest); sub(/[[:space:]]+$/, "", rest)
      if (rest == "") return 0
      i = split(rest, t, /[[:space:]]+/)
      w = t[i]
      return (w ~ ("^\\$" Q "(\\\\(x[0-9A-Fa-f]+|[0-7]+|[abefnrtv]))+" Q "$"))
    }

    {
      raw = $0
      # Function scope. The house style closes a function with a column-0 `}`; a one-liner opens and
      # closes on its own line. Anything this cannot follow leaves us at top level, which is the
      # fail-CLOSED direction: an untracked raw send is reported, never silently exempted.
      if (infn && raw ~ /^\}/) { infn = 0; fn = "-" }
      closes = 0
      if (match(raw, /^[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*\{/)) {
        hdr = substr(raw, RSTART, RLENGTH)
        sub(/^[[:space:]]*/, "", hdr)
        sub(/^function[[:space:]]+/, "", hdr)
        sub(/[[:space:]]*\(\).*$/, "", hdr)
        fn = hdr; infn = 1
        if (substr(raw, RSTART + RLENGTH) ~ /\}[[:space:]]*$/) closes = 1
      }

      hatch = (raw ~ /typed-send-lint:allow/)
      if (is_comment(raw)) { if (hatch) pending = 1; next }
      if (raw ~ /^[[:space:]]*$/) next        # a blank line does not consume a pending marker

      s = strip_comment(raw)
      k = prim(s)
      if (k != "") {
        if (hatch || pending) { }                                     # reviewed counter-example
        else if (fn in sanct) { }                                     # the helper doing its job
        else if ((k == "session-send" || k == "async-send") && ctrl_only(substr(s, POS))) { }
        else printf "%d\t%s\t%s\t%s\n", NR, fn, k, raw
      }
      pending = 0
      if (closes) { infn = 0; fn = "-" }
    }
  ' "$1"
}

# ── COULD-NOT-CHECK is a THIRD state, never a verdict ─────────────────────────────────────────────
CHECK_FAILED=0

# EXACT-LINE MEMBERSHIP WITHOUT A FORK. `printf … | grep -qxF` costs two forks per test and this runs
# per violation and per allowlist entry; wrapping both sides in newlines makes a plain shell pattern
# do the same exact-line test with none. The lint runs inside every land, on a box that routinely
# sits at load 20+, where forks are the scarce resource.
in_list() {  # $1=needle line · $2=newline-delimited haystack
  case "
$2
" in
    *"
$1
"*) return 0 ;;
  esac
  return 1
}

# ── is this file shell at all ─────────────────────────────────────────────────────────────────────
# bin/ is entirely extensionless, so extension alone cannot decide; a shebang read is the only honest
# test. Read via the `read` builtin rather than `head -n1 | grep`: same answer, two fewer forks.
is_shell() {
  case "$1" in *.sh) return 0 ;; *.py|*.pyc|*.md|*.json|*.yaml|*.yml|*.conf|*.manifest|*.plist|*.txt|*.applescript) return 1 ;; esac
  local first=""
  # rc deliberately ignored: a single-line file with no trailing newline sets `first` and still
  # returns non-zero, and that file is exactly the kind this has to classify correctly.
  IFS= read -r first < "$1" 2>/dev/null
  case "$first" in
    '#!'*bash*|'#!'*/bin/sh*|'#!'*"env sh"*) return 0 ;;
  esac
  return 1
}

# lint_tree <root> <allowlist-text> [sanctioned-text] — 0 clean · 1 violations · 2 unusable
lint_tree() {
  local root="$1" allow="$2" sanct="${3:-$EMBEDDED_SANCTIONED}"
  local f rel hits ln fnname kind text key bad=0 seen=0 stuck=0 layer found_layer=0
  local used="" entry
  CHECK_FAILED=0
  [ -d "$root" ] || { echo "typed-send-lint: ⛔ not a directory: $root" >&2; return 2; }

  local dirs=""
  for layer in $LAYERS; do
    [ -d "$root/$layer" ] && { dirs="$dirs $root/$layer"; found_layer=1; }
  done
  [ "$found_layer" -eq 1 ] || {
    echo "typed-send-lint: ⛔ none of the deployed layers ($LAYERS) exist under $root" >&2; return 2; }

  # shellcheck disable=SC2086  # $dirs is a deliberate word-split list of scan roots
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    # A tests/ subtree is never symlink-deployed (install.sh globs hooks/*.sh, scripts/*.sh, bin/* —
    # not hooks/tests/), so nothing there can fire a real pane.
    case "$f" in */.git/*|*/tests/*) continue ;; esac
    # A DETECTOR MUST NOT SCAN ITSELF. This file necessarily contains every primitive it hunts — the
    # --selftest fixtures replay the real artifacts, because a control that hand-approximates one
    # passes vacuously (memory: control-must-replay-the-real-artifact). What validates THIS file is
    # --selftest, which the gate runs alongside the scan.
    case "${f##*/}" in typed-send-lint.sh) continue ;; esac
    is_shell "$f" || continue
    seen=$((seen + 1))
    rel="${f#"$root"/}"

    hits="$(raw_typed_sends "$f" "$sanct")" || {
      CHECK_FAILED=1
      echo "typed-send-lint: ⛔ detector could not RUN for $rel" >&2
      continue
    }
    [ -n "$hits" ] || continue

    while IFS="$(printf '\t')" read -r ln fnname kind text; do
      [ -n "$ln" ] || continue
      key="$rel::$fnname"
      if in_list "$rel" "$allow"; then
        used="$used
$rel"
        in_list "$key" "$allow" && used="$used
$key"
        continue
      elif in_list "$key" "$allow"; then
        used="$used
$key"
        continue
      fi
      printf '  TYPED-SEND %s:%s  (%s' "$rel" "$ln" "$kind"
      [ "$fnname" = "-" ] || printf ' in %s()' "$fnname"
      printf ')\n'
      printf '             %s\n' "$text"
      bad=$((bad + 1))
    done <<EOF
$hits
EOF
  done <<EOF
$(find $dirs -type f 2>/dev/null)
EOF

  [ "$seen" -gt 0 ] || { echo "typed-send-lint: ⛔ no shell files under $root ($LAYERS)" >&2; return 2; }

  # Checked AFTER the scan so a killed detector cannot masquerade as a clean pass.
  if [ "$CHECK_FAILED" -ne 0 ]; then
    echo "typed-send-lint: ⛔ UNUSABLE — the detector failed to run (see above); no verdict." >&2
    echo "  This is NOT a violation report. Re-run when the box is quieter; do not 'fix' any file on it." >&2
    return 2
  fi

  # THE RATCHET ONLY SHRINKS. An entry whose file still exists and no longer raw-sends must go, and
  # saying so is what stops an allowlist from quietly becoming a permanent exemption list — that
  # entry is the dangerous kind, because it would silently cover the NEXT raw send added to that file.
  #
  # AN ENTRY OUT OF VIEW IS NOT A STALE ENTRY. The allowlist is rooted at the REPO, but the scan root
  # is a parameter — every fixture in this lint's own suite scans a two-file tree, and a scoped land
  # scans a subtree. Judging "it matched nothing" against a tree that never contained the file turns
  # every narrowed scan into a wall of false RATCHET lines and makes the lint unusable anywhere but
  # the repo root (it did exactly that on first run: 5 stale entries reported against a 1-file
  # fixture). So a path that is not present under THIS root is skipped — except on a full-tree run,
  # where absence really does mean the file was renamed or deleted and the line is dead weight.
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    in_list "$entry" "$used" && continue
    if [ ! -e "$root/${entry%%::*}" ]; then
      [ "$root" = "$ROOT" ] || continue
      printf '  RATCHET    %s no longer exists — delete its allowlist line\n' "$entry"
      stuck=$((stuck + 1))
      continue
    fi
    printf '  RATCHET    %s no longer raw-sends — delete its allowlist line\n' "$entry"
    stuck=$((stuck + 1))
  done <<EOF
$allow
EOF

  if [ "$bad" -gt 0 ]; then
    echo "typed-send-lint: ⛔ $bad site(s) above type a COMMAND LINE into a pane without echo-verifying it."
    echo "  Why it matters: this operator's zsh has \`setopt CORRECT\`. One dropped character and the"
    echo "  pane parks forever on  zsh: correct 'X' to 'Y' [nyae]?  with nobody there to answer — the"
    echo "  fire reports success and the work never starts (2026-07-26: a 6m40s wedge, one work item"
    echo "  lost silently)."
    echo "  Fix: route the line through a verified-typing helper, which pastes, READS THE PANE BACK to"
    echo "  prove the line landed intact, and only then sends the Enter:"
    echo "      osa_type_verified  \"\$pane\" \"\$cmd\"     # scripts/lib/cc-type-verified.sh (osascript)"
    echo "      it2_type_verified  \"\$it2\" \"\$id\" \"\$cmd\"  # scripts/handoff-fire.sh (it2 session send)"
    # printf, not echo: the line is ABOUT escape sequences and must print them verbatim.
    printf '%s\n' "  A control-character send (\$'\\r', \$'\\x15') is already fine — it types no command line."
    echo "  A reviewed counter-example takes a trailing \`typed-send-lint:allow — <reason>\` marker."
    echo "  Do NOT add to the allowlist."
  fi
  if [ "$stuck" -gt 0 ]; then
    echo "typed-send-lint: ⛔ $stuck allowlist entry(ies) above are stale."
    echo "  Fix: delete their lines from EMBEDDED_ALLOWLIST in $SELF — the ratchet only shrinks."
  fi
  [ $((bad + stuck)) -eq 0 ] || return 1
  echo "typed-send-lint: clean — $seen shell file(s) scanned; $(printf '%s\n' "$allow" | grep -c .) grandfathered, 0 new raw typed sends."
  return 0
}

# ── --selftest: every case proves a RED path FIRES or a GREEN path does NOT ───────────────────────
# A detector is only worth its clean verdict if it can be shown to discriminate; a control that
# cannot fail the same way as the real thing passes vacuously. Fixtures are written through quoted
# heredocs so every `$'\r'`, `$LAUNCHER` and `$id` reaches the file EXACTLY as the real code spells
# it — the shapes are recovered from the real sites, not hand-approximated.
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  fails=0
  # mk <case> [basename] — body on stdin; writes a scan root $d/<case> with one file under scripts/
  mk() {
    local case_="$1" base="${2:-probe.sh}"
    mkdir -p "$d/$case_/scripts"
    printf '#!/bin/bash\n' > "$d/$case_/scripts/$base"
    cat >> "$d/$case_/scripts/$base"
  }

  # ── RED: the real artifacts, one per primitive ────────────────────────────────────────────────
  # (a) THE scar shape — lr-handoff.sh:230 / lr-reset-poller.sh:218 / boot-resume-launch.sh:73.
  mk write_text <<'BODY'
osascript <<OSA
tell application "iTerm2"
  set newWin to (create window with default profile)
  tell current session of newWin to write text "exec /bin/bash $LAUNCHER"
end tell
OSA
BODY
  # (b) the same defect spelled through the it2 byte-level transport, with a real command payload.
  mk it2_send <<'BODY'
"$IT2" session send -s "$id" "exec /bin/bash $LAUNCHER"
BODY
  mk async <<'BODY'
async_send_text("exec /bin/bash $LAUNCHER")
BODY
  # (c) Terminal.app / focus-typing / tmux — the other three ways to make a shell run a line.
  mk do_script <<'BODY'
osascript -e "tell application \"Terminal\" to do script \"exec /bin/bash $LAUNCHER\""
BODY
  mk keystroke <<'BODY'
osascript -e 'tell application "System Events" to keystroke "exec /bin/bash claude"'
BODY
  mk tmux <<'BODY'
tmux send-keys -t "$pane" "exec /bin/bash $LAUNCHER" C-m
BODY

  # ── GREEN: the FIX, and every shape that must not be flagged ──────────────────────────────────
  # (d) THE FIX — the exact site of (a), routed through the sanctioned helper. Same file, same
  #     command, same pane; the only difference is that the line is echo-verified before the CR.
  mk routed <<'BODY'
. "$ROOT/scripts/lib/cc-type-verified.sh"
osa_type_verified "$pane" "exec /bin/bash $LAUNCHER" || exit 3
BODY
  # (e) the helper's OWN internals — it necessarily contains the raw primitive; that IS the helper.
  mk sanctioned <<'BODY'
osa_type_verified() { # $1=pane $2=command
  osascript - "$1" "$2" <<'AS'
on run argv
  tell application "iTerm2" to tell session id (item 1 of argv) to write text (item 2 of argv)
end run
AS
}
BODY
  # (e2) …and the it2 spelling of the same, from handoff-fire.sh:530.
  mk it2_helper <<'BODY'
_it2_type_line() { # $1=it2-bin $2=session-id $3=line
  hf_bounded "$1" session send -s "$2" "${BP_START}${wire}${BP_END}" || return 1
  hf_bounded "$1" session send -s "$2" $'\r'
}
BODY
  # (e3) THE OTHER DIRECTION, and the case the whole exemption turns on: the SAME body under a name
  #      that is NOT sanctioned. If the rule keyed on "it is inside a function" this would pass, and
  #      the exemption would be a hole anyone could walk through by wrapping their raw send.
  mk unsanctioned <<'BODY'
osa_write_raw() { # $1=pane $2=command
  osascript -e "tell application \"iTerm2\" to tell session id \"$1\" to write text \"$2\""
}
BODY
  # (e4) …and a raw send AFTER the helper closes, in the same file. Proves the exemption is scoped
  #      to the FUNCTION and not to the file — handoff-fire.sh owns the helpers AND 3700 other lines.
  mk after_helper <<'BODY'
_it2_type_line() { # $1=it2-bin $2=session-id $3=line
  hf_bounded "$1" session send -s "$2" "$wire" || return 1
}
"$IT2" session send -s "$sid" "exec /bin/bash $LAUNCHER"
BODY
  # (f) CONTROL-CHARACTER payloads — handoff-fire.sh:527/537/1664/1747. No command line is typed, so
  #     there is no first word for the shell to mis-correct. Flagging these would bury the signal.
  mk ctrl <<'BODY'
"$IT2" session send -s "$id" $'\r' >/dev/null 2>&1 || true
"$IT2" session send -s "$id" $'\x15' >/dev/null 2>&1 || true
[ "$waited" = 60 ] && hf_bounded "$IT2" session send -s "$SID" $'\r' >/dev/null 2>&1 || true
case "$waited" in 60|150|300) "$IT2" session send -s "$RSID" $'\r' >/dev/null 2>&1 || true ;; esac
BODY
  # (g) osascript that types NOTHING — the single most common osascript call in this tree.
  mk notify <<'BODY'
osascript -e 'display notification "gate red" with title "claude"' >/dev/null 2>&1 || true
osascript -e 'display dialog "continue?" buttons {"no","yes"}' >/dev/null 2>&1 || true
BODY
  # (h) PROSE. Every one of these appears verbatim in this repo today (desk-invariant.sh,
  #     handoff-fire.sh, cc-notify, mailbox-drain.sh). A detector that matches text ABOUT the defect
  #     reports the fix as the bug.
  mk prose <<'BODY'
# with spaces survives the osascript `write text` shell.
# No `write text` char-stream here → no ttys018 mis-inject.
# re-engagement must NEVER keystroke a live composer.
# IT2 is read-only here (session list, for pane liveness) — NEVER `session send`.
# delivered as CONTEXT via the non-keystroke inbox channel — never typed into your input line.
true
BODY
  # (h2) prose in a TRAILING comment (which a full-line-comment strip alone would not reach) AND —
  #      the harder half — the verbs sitting inside an ordinary MESSAGE STRING. desk-invariant.sh
  #      logs "NO keystroke into the live composer" nine times; a lint that reads a status message
  #      about NOT typing as typing is a lint nobody keeps on.
  mk prose_trailing <<'BODY'
notify "desk idle" "enqueued to the inbox — no keystroke \"here\""   # never a write text "cmd"
badp "stunned: KEYSTROKED a live composer (F7 regression)"
echo "this pane is driven with write text \"$cmd\" nowhere at all" >&2
BODY
  # (h3) …and the OTHER direction of that same judgement, or it is worthless: identical verb,
  #      identical quoting, but inside an osascript/tell context, where it really does type.
  mk msg_vs_osa <<'BODY'
osascript -e "tell current session of newWin to write text \"$cmd\"" >/dev/null
BODY
  # (i) the escape hatch, in both accepted placements…
  mk marker <<'BODY'
"$IT2" session send -s "$id" "exec /bin/bash $LAUNCHER"   # typed-send-lint:allow — fixture, never run
BODY
  mk marker_above <<'BODY'
# typed-send-lint:allow — reviewed: this pane is proven dead, the send is the teardown probe
"$IT2" session send -s "$id" "exec /bin/bash $LAUNCHER"
BODY
  # (i2) …and an ORDINARY comment above the line must NOT shield it, or every commented line in the
  #      repo becomes an exemption.
  mk marker_absent <<'BODY'
# an ordinary explanatory comment about what this launcher does
"$IT2" session send -s "$id" "exec /bin/bash $LAUNCHER"
BODY
  # (j) a non-shell file carrying the shape must not be scanned…
  mkdir -p "$d/nonshell/scripts"
  printf 'tell current session of w to write text "exec /bin/bash $L"\n' > "$d/nonshell/scripts/x.md"
  printf '#!/bin/bash\ntrue\n' > "$d/nonshell/scripts/ok.sh"
  # (j2) …nor a tests/ subtree, which is never symlink-deployed.
  mkdir -p "$d/subtree/hooks/tests"
  printf '#!/bin/bash\n"$IT2" session send -s "$id" "exec /bin/bash $L"\n' > "$d/subtree/hooks/tests/t.sh"
  printf '#!/bin/bash\ntrue\n' > "$d/subtree/hooks/ok.sh"

  # The reported case count is COUNTED, never typed: a hardcoded total silently drifts as cases are
  # added, and a selftest that misreports its own coverage is the last place to keep a stale number.
  checks=0
  expect() {  # <want-rc> <got-rc> <failure message>
    checks=$((checks + 1))
    [ "$2" -eq "$1" ] || { echo "SELFTEST FAIL: $3"; fails=1; }
  }
  red()   { lint_tree "$d/$1" "${2-}" >/dev/null 2>&1; expect 1 "$?" "$3"; }
  green() { lint_tree "$d/$1" "${2-}" >/dev/null 2>&1; expect 0 "$?" "$3"; }

  red   write_text  "" "a bare osascript \`write text\` of a launch command did not go RED — THE scar shape"
  red   it2_send    "" "a raw it2 \`session send\` of a command line did not go RED"
  red   async       "" "a raw async_send_text of a command line did not go RED"
  red   do_script   "" "an AppleScript \`do script\` did not go RED"
  red   keystroke   "" "an AppleScript \`keystroke\` did not go RED"
  red   tmux        "" "a \`tmux send-keys\` did not go RED"
  green routed      "" "the SAME site routed through osa_type_verified was flagged — the fix does not clear the lint"
  green sanctioned  "" "the sanctioned helper's OWN internals were flagged"
  green it2_helper  "" "_it2_type_line's own internals were flagged"
  red   unsanctioned "" "an identical body under a NON-sanctioned function name went GREEN — the exemption keys on being inside ANY function, so wrapping a raw send defeats it"
  red   after_helper "" "a raw send AFTER the sanctioned helper closed went GREEN — the exemption is file-wide, so the file that owns the helpers is unreachable"
  green ctrl        "" "a control-character payload (\$'\\r' / \$'\\x15') was flagged as a typed command line"
  green notify      "" "display notification / display dialog were flagged — they type nothing"
  green prose       "" "PROSE about the defect was reported as the defect"
  green prose_trailing "" "a verb in a TRAILING comment or an ordinary message string was reported as the defect"
  red   msg_vs_osa  "" "the SAME verb and quoting INSIDE an osascript context went GREEN — the AppleScript-context test is not discriminating, it is just switching the rule off"
  green marker      "" "a trailing typed-send-lint:allow marker did not suppress"
  green marker_above "" "a typed-send-lint:allow marker on the preceding comment line did not suppress"
  red   marker_absent "" "an ordinary comment above the line suppressed it — any comment now works as an exemption"
  green nonshell    "" "a non-shell file was scanned"
  green subtree     "" "a file in a tests/ subtree (never symlink-deployed) was scanned"

  # ── the ratchet: grandfathered is green, and it SHRINKS ────────────────────────────────────────
  green it2_send "scripts/probe.sh"                 "a grandfathered violation did not go GREEN"
  red   routed   "scripts/probe.sh"                 "a fixed-but-still-grandfathered file did not go RED (the ratchet is a permanent exemption list)"
  # …and the narrow `path::function` form, which is what keeps the REST of a large file in scope.
  mk fnscope <<'BODY'
as_write() { # $1=session $2=text
  osascript -e "tell application \"iTerm2\" to tell session id \"$1\" to write text \"$2\""
}
BODY
  green fnscope "scripts/probe.sh::as_write"        "a path::function allowlist entry did not grandfather its function"
  red   fnscope "scripts/probe.sh::other_fn"        "a path::function entry for a DIFFERENT function grandfathered the violation anyway — the narrow form is not narrow"
  mk fnscope2 <<'BODY'
as_write() { # $1=session $2=text
  osascript -e "tell application \"iTerm2\" to tell session id \"$1\" to write text \"$2\""
}
elsewhere() {
  "$IT2" session send -s "$id" "exec /bin/bash $LAUNCHER"
}
BODY
  red   fnscope2 "scripts/probe.sh::as_write"       "a second raw send ELSEWHERE in a partly-grandfathered file went GREEN — the narrow entry exempted the whole file"
  # An entry naming a path this root does not contain is OUT OF VIEW, not stale — otherwise every
  # narrowed scan (this suite's own fixtures, a scoped land) drowns in false RATCHET lines.
  green routed "scripts/somewhere-else.sh"          "an allowlist entry for a path outside the scan root was reported STALE — a narrowed scan is now unusable"

  # ── the REAL tree with the REAL allowlist. A stale ratchet is caught here too. The two failure
  #    codes must stay APART: 1 is a VERDICT about the tree, 2 says nothing whatever about it
  #    (memory: gate-never-ran-vs-gate-red).
  lint_tree "$ROOT" "$EMBEDDED_ALLOWLIST" >/dev/null 2>&1; rc_real=$?
  checks=$((checks + 1))
  case "$rc_real" in
    0) ;;
    2) echo "SELFTEST FAIL: could not scan $ROOT — a NON-VERDICT (bad ROOT?), NOT a stale allowlist"; fails=1 ;;
    *) echo "SELFTEST FAIL: the embedded allowlist is stale — the real tree is not clean"; fails=1 ;;
  esac

  # ── LOUD on an unusable scan tree, in both its forms.
  lint_tree "$d/nope" "" >/dev/null 2>&1; expect 2 "$?" "a missing scan root did not exit 2 (LOUD)"
  mkdir -p "$d/nolayers/docs"
  lint_tree "$d/nolayers" "" >/dev/null 2>&1; expect 2 "$?" "a root with NO deployed layers did not exit 2 (LOUD)"

  # ── COULD-NOT-CHECK is a non-verdict, not a violation. Shadowing awk on PATH reproduces what fork
  #    exhaustion (or another session's unscoped pkill) does to the detector. The contract is exit 2
  #    and NO named finding — a killed check that names a file reads as an attributable RED and sends
  #    people to "fix" code that was never broken (memory: named-failure-vs-no-verdict).
  stub="$d/stub"; mkdir -p "$stub"
  printf '#!/bin/bash\nexit 2\n' > "$stub/awk"; chmod +x "$stub/awk"
  out="$(PATH="$stub:$PATH" CC_TYPEDSEND_ALLOWLIST="" "$SELF" "$d/it2_send" 2>&1)"; rc_killed=$?
  expect 2 "$rc_killed" "an unrunnable detector did not exit 2 — a killed check must never be a verdict"
  checks=$((checks + 1))
  case "$out" in
    *TYPED-SEND*) echo "SELFTEST FAIL: an unrunnable detector still fabricated a TYPED-SEND finding"; fails=1 ;;
    *UNUSABLE*)   ;;
    *)            echo "SELFTEST FAIL: the non-verdict was not announced"; fails=1 ;;
  esac

  # ── the env seams, exercised at the ENTRYPOINT (where a caller actually reaches them).
  ( CC_TYPEDSEND_ALLOWLIST="scripts/probe.sh" "$SELF" "$d/it2_send" >/dev/null 2>&1 ); expect 0 "$?" "CC_TYPEDSEND_ALLOWLIST did not grandfather at the entrypoint"
  ( CC_TYPEDSEND_ALLOWLIST="" "$SELF" "$d/it2_send" >/dev/null 2>&1 );                  expect 1 "$?" "an EMPTY CC_TYPEDSEND_ALLOWLIST did not block at the entrypoint"
  ( CC_TYPEDSEND_ALLOWLIST="" CC_TYPEDSEND_SANCTIONED="osa_write_raw" "$SELF" "$d/unsanctioned" >/dev/null 2>&1 ); expect 0 "$?" "CC_TYPEDSEND_SANCTIONED did not admit a helper by name at the entrypoint"

  if [ "$fails" -eq 0 ]; then
    echo "typed-send-lint --selftest: $checks/$checks — RED on all six raw primitives (write text, it2 session send, async_send_text, do script, keystroke, tmux send-keys), on the same body under a NON-sanctioned function name, on a raw send after the sanctioned helper closed, on a bare comment used as an exemption, on the same verb+quoting moved INTO an osascript context, on a narrow entry asked to cover a second function, and on a stale ratchet entry; GREEN on the same site routed through osa_type_verified, on both sanctioned helpers' internals, on control-character payloads, on display notification/dialog, on prose in full-line and trailing comments, on both escape-hatch placements, on non-shell files and a tests/ subtree, and on a grandfathered violation by path and by path::function; GREEN on the real tree; LOUD on a missing root and on a root with no layers; NON-VERDICT on an unrunnable detector; both env seams live at the entrypoint."
    exit 0
  fi
  echo "typed-send-lint --selftest: FAILED ($checks case(s) run) — the detector does not discriminate."
  exit 1
fi

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  # The header block, DERIVED rather than a hardcoded line range: every edit to the header would
  # otherwise silently truncate --help mid-sentence.
  awk 'NR > 1 { if ($0 !~ /^#/) exit; if ($0 ~ /^# *shellcheck /) next; sub(/^# ?/, ""); print }' "$SELF"
  exit 0
fi

lint_tree "${1:-$ROOT}" "${CC_TYPEDSEND_ALLOWLIST-$EMBEDDED_ALLOWLIST}" "${CC_TYPEDSEND_SANCTIONED-$EMBEDDED_SANCTIONED}"
exit $?
