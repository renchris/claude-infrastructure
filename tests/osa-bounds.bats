#!/usr/bin/env bats
#
# osa-bounds.bats — M5. The STANDING check that no osascript call in this repo can wait forever.
#
# WHY. An `osascript` call is an AppleEvent into another application, and an AppleEvent has no
# timeout of its own. If the target app (iTerm2, Dia, System Events, NotificationCenter) is wedged,
# sitting on its own modal, or paging under load, the call does not fail — it waits. The 2026-07-26
# machine-wide iTerm2/AppleEvent wedge is the incident this guards. Every osascript call site in this
# repo is best-effort (`|| true`, `2>/dev/null`), so a CUT costs one notification or one window
# activation; a HANG costs the hook, launchd job or crash handler that made the call. That asymmetry
# is the whole argument, and it is why the rule is "bounded everywhere", not "bounded where it seems
# to matter".
#
# WHY A GREP AND NOT A CODE CHANGE. The bound has to hold for call sites that do not exist yet.
# Converting today's sites fixes today; a standing lint is what makes the NEXT bare osascript fail
# in the gate instead of in production at 2am.
#
# THE CORRECTION. The obvious expression — grep for `osascript` — is useless here: this repo mentions
# the word in prose, in report strings, in a python argv list, and in a variable assignment, and it
# wraps real calls in per-file bounding helpers (`lcw_osa`, `wrc_osa`, `nty_osa`, …) that a naive
# pattern reads as unbounded. A check that fires on 20 healthy lines is functionally a deleted check —
# nobody reads its output twice. So the scan below is anchored to osascript in COMMAND POSITION with
# an actual flag after it, and every exclusion below is a NAMED class, not a blanket carve-out.
#
# EXEMPTION 1, stated rather than hidden: `osascript -e 'delay <n>'` is a sleep implemented in the
# osascript interpreter with NO target application. It cannot block on another process's event loop,
# which is the entire hazard. The pattern is narrow enough that no call carrying a `tell application`
# can launder itself through it, and the exempted lines are printed by the tree test rather than
# silently dropped.
#
# EXEMPTION 2, likewise: a line that only PRINTS the word — an echo/printf of a teardown hint for a
# human. No process is spawned, so bounding it would change a string and fix nothing. Stated in full
# at MENTION_RE below, where the rule is written as a statement about execution (no separator, no
# substitution ⇒ nothing on the line can run) rather than as "it looks like an echo"; it is likewise
# printed by its own tree test, and has a positive control proving a real call on an echo line is
# still caught.
#
# EXEMPTION 3, the same class as the scan's own `^[^#]*` guard, in the other spelling: a line-leading
# `//` COMMENT. `#` is one language's comment introducer, not the class "a comment cannot execute" —
# enumerating spellings instead of the class is the defect this repo already carries a scar from, and
# it convicted a healthy line on 2026-08-06 (bin/kitty-pane-menu-native.swift:5, a Swift comment
# explaining why JXA was rejected, whose markdown backticks around `osascript -l JavaScript` read to
# a SHELL-shaped scanner as command substitution). Rewording that prose would have satisfied the
# grep and fixed nothing: a check that fires on healthy lines is one people learn to route around.
# Stated in full at COMMENT_RE below. Two restrictions carry it, and neither is negotiable —
# LINE-LEADING, because `//` mid-line is shell parameter expansion (`${p//a/b}`) or a URL scheme, and
# exempting those would launder a real call sharing the line; and scoped BY EXTENSION to languages
# where `//` runs to end of line, because in shell it does not comment at all — `// x; osascript -e …`
# is a failed command followed by a REAL call. Both shapes have positive controls below. Widening
# the language list is a deliberate act; omitting a language only leaves the scan strict, which is
# the safe direction to be wrong in.
#
# RED-PROOF: fails against the pristine pre-change tree, where hooks/lib/osa.sh does not exist and
# bin/screenshot-to-clipboard.sh:18 + bin/dia-cdp-launch.sh:322 are bare calls:
#   t=$(mktemp -d); git archive eaa0cdeb | tar -x -C "$t"
#   CC_OSA_SUBJECT_ROOT="$t" bats tests/osa-bounds.bats
# Re-proved the same way for exemption 3 (2026-08-06): against the tree BEFORE scripts/kitty-setup.sh
# was converted, this suite is red on the tree assertion ONLY, naming exactly that site — so the
# exemption did not launder the real bug it landed alongside.
#
# DEAD-ASSERTION DISCIPLINE: bats bodies run under `set -eET`, and bash exempts `[[ ]]`, `(( ))` and
# `! cmd` from errexit — a non-final occurrence of those is a DEAD assertion that always passes
# (scripts/bats-assert-liveness.py). This suite uses POSIX `[ ]` and appends `|| false` where needed.
#
# GREP IS PINNED to /usr/bin/grep. The interactive shell here resolves `grep` to ugrep, whose ERE
# dialect differs (it rejects an empty alternation outright), so an unpinned scan would encode which
# grep the PATH happened to offer and could return a different verdict in the gate than on the desk.

# shellcheck disable=SC2034  # consumed by bats itself; file-level is the ONLY working placement (memory: bats-runtime-cap-placement)
BATS_TEST_TIMEOUT=180

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermeticity ratchet: never the live ~/
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off  # M11: pinned, not ambient
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  ROOT="${CC_OSA_SUBJECT_ROOT:-$REPO}"
  LIB="$ROOT/hooks/lib/osa.sh"
  G=/usr/bin/grep
  D="$BATS_TEST_TMPDIR"
}

# ── the scan: ONE implementation, used by both controls AND the tree assertion ──────────────────
# A control that exercised a re-typed copy of the expression would prove nothing about the
# expression the tree is actually judged by.
ac22_scan_raw() { # <path>… → rows before the mention-exemption (see MENTION_RE below)
  "$G" -rnE '^[^#]*(^|[[:space:];&|(`])osascript[[:space:]]+-' "$@" 2>/dev/null \
    | "$G" -vE '[a-z0-9_]+_(osa|bounded)[[:space:]]+([0-9]+[[:space:]]+)?osascript' \
    | "$G" -vE 'timeout[[:space:]]+[0-9]' \
    | "$G" -vE 'command -v' \
    | "$G" -vE 'additionalContext' \
    | "$G" -vE "osascript -e '(delay)[[:space:]]+[0-9.]+'"
}

# EXEMPTION 2, stated rather than hidden: a line that only NAMES osascript inside a hint it PRINTS.
# scripts/terminal-bakeoff.sh:248 echoes the teardown command a human should run; no osascript
# process is spawned, so "bounding" it would change a string and fix nothing.
#
# THE RULE IS NOT "it starts with echo" — that would be exactly the denylist-of-spellings defect this
# file already carries a scar from, and it would exempt `echo "$(osascript …)"`, a real call. The rule
# is a statement about EXECUTION: for the named osascript to run, the line must either introduce a new
# command (a `;`, `&`, `|` separator) or substitute one (`$(` or a backtick). Deny both and nothing on
# the line can execute — the word is an argument to echo/printf and cannot be anything else. `$` is
# tolerated only when NOT followed by `(`, so `$GHOSTTY_WIN` interpolates but `$(…)` never exempts.
# Anchored past grep's own `path:line:` prefix so the restriction covers the whole source line.
MENTION_RE='^[^:]*:[0-9]+:[[:space:]]*(echo|printf)[[:space:]]([^;&|`$]|\$[^(])*$'

# EXEMPTION 3, stated rather than hidden: a line whose first non-blank characters are `//`, in a file
# whose extension makes `//` a to-end-of-line comment. Nothing after it is code, so no process is
# spawned and "bounding" it would edit documentation and fix nothing.
#
# THE RULE IS NOT "the line contains //". In shell that is `${p//a/b}` or `http://`, and honouring it
# mid-line would exempt a real call sharing the line. It is not "the line starts with //" either: in
# shell `//` is not a comment introducer but a failed command, so `// prose; osascript -e '…'` runs
# the call — which is why the extension scope is load-bearing rather than decorative, and why both
# shapes are pinned by positive controls below. Anchored past grep's own `path:line:` prefix.
COMMENT_RE='^[^:]*\.(swift|js|mjs|cjs|jsx|ts|tsx):[0-9]+:[[:space:]]*//'

ac22_scan() { # <path>… → hazardous "file:line:text" rows
  ac22_scan_raw "$@" | "$G" -vE "$MENTION_RE" | "$G" -vE "$COMMENT_RE"
}
comment_exempt() { # <path>… → the rows exemption 3 removed (reported, never silently dropped)
  ac22_scan_raw "$@" | "$G" -E "$COMMENT_RE" || true
}
# The counterpart, and the reason exemption 3 is safe to have at all — an INDEPENDENT property, not a
# restatement of COMMENT_RE: that regex trusts an EXTENSION to mean "`//` comments to end of line",
# and the way that claim goes wrong is a file whose extension lies about its language. So ask a
# different question of the file itself — does it open with a SHELL shebang? A `.js`/`.swift` that
# does is a shell script wearing the wrong suffix, where a `//` line is a failed command that can be
# followed by a live one, and the exemption must not cover it.
comment_launder(){ # <path>… → comment-exempt rows from files that are actually SHELL (empty = clean)
  comment_exempt "$@" | cut -d: -f1 | sort -u | while IFS= read -r f; do
    [ -r "$f" ] || continue
    first="$(head -1 "$f" 2>/dev/null || true)"
    case "$first" in '#!'*sh*) printf '%s\n' "$f" ;; esac
  done
}
mention_exempt() { # <path>… → the rows exemption 2 removed (reported, never silently dropped)
  ac22_scan_raw "$@" | "$G" -E "$MENTION_RE" || true
}
# The counterpart, and the reason exemption 2 is safe to have at all — an INDEPENDENT property, not a
# restatement of MENTION_RE: in a genuinely-printed mention the word sits inside a quoted string, so
# an ODD number of double quotes precedes it. A row that got exempted while its osascript sits OUTSIDE
# any string is a laundered call, whatever the separator rule thought.
mention_launder(){ # <path>… → exempt rows whose osascript is NOT inside a quoted string (empty = clean)
  mention_exempt "$@" | awk '{ i=index($0,"osascript"); if(i==0) next;
    pre=substr($0,1,i-1); if (gsub(/"/,"\"",pre) % 2 == 0) print }'
}

# The counterpart to that last exclusion, and the reason it is safe. `delay N` runs inside the
# osascript interpreter — no `tell application`, no target process, so it cannot block on another
# app's event loop (measured: `osascript -e 'delay 2'` returns in 2.045s wall clock). That makes the
# 4 real sites in scripts/handoff-fire.sh portable sleeps rather than AppleEvents, and exempting them
# correct. But the exclusion above is a LINE-scoped `grep -v`, so it exempts everything else on the
# line too. This is the check that the exemption is not carrying a passenger: strip the delay
# invocations, and anything left that still calls out is a real, unbounded site.
# ONE implementation, exercised by both the tree assertion and its positive control below.
delay_launder(){ # <path>… → delay-exempt rows carrying another call (empty = clean)
  "$G" -rnE "osascript -e '(delay)[[:space:]]+[0-9.]+'" "$@" 2>/dev/null \
    | sed -E "s/osascript -e '(delay)[[:space:]]+[0-9.]+'/<DELAY>/g" \
    | "$G" -E 'osascript|tell application' || true
}

# ── POSITIVE CONTROL: the scan can FAIL ─────────────────────────────────────────────────────────
@test "AC22 control (+): a bare osascript call IS caught" {
  mkdir -p "$D/pos"
  printf '#!/bin/bash\nosascript -e %s\n' "'tell application \"Finder\" to activate'" > "$D/pos/bare.sh"
  n="$(ac22_scan "$D/pos" | "$G" -c . || true)"
  [ "$n" -eq 1 ] || { echo "the scan did NOT catch a bare osascript (n=$n) — it cannot fail, so a green tree means nothing"; false; }
}

@test "AC22 control (+): a bare call mid-pipeline, not at line start, is still caught" {
  # Anchoring only to the start of a line would miss every call in a compound command — the shape
  # most of this repo's real call sites actually have.
  mkdir -p "$D/pos2"
  printf '#!/bin/bash\ntrue && osascript -e %s || true\n' "'tell application \"iTerm2\" to activate'" > "$D/pos2/mid.sh"
  n="$(ac22_scan "$D/pos2" | "$G" -c . || true)"
  [ "$n" -eq 1 ] || { echo "a mid-command bare call escaped the scan (n=$n)"; false; }
}

# ── NEGATIVE CONTROLS: the scan does not fire on bounded or non-call lines ──────────────────────
@test "AC22 control (-): a wrapper-bounded call (hf_bounded / osa_bounded) is NOT flagged" {
  mkdir -p "$D/neg"
  {
    printf '#!/bin/bash\n'
    printf 'hf_bounded osascript -e %s\n'  "'tell application \"iTerm2\" to activate'"
    printf 'osa_bounded osascript -e %s\n' "'tell application \"Dia\" to activate'"
    printf 'lcw_osa osascript -e %s\n'     "'display notification \"x\"'"
    printf 'timeout 10 osascript -e %s\n'  "'display notification \"x\"'"
  } > "$D/neg/bounded.sh"
  n="$(ac22_scan "$D/neg" | "$G" -c . || true)"
  [ "$n" -eq 0 ] || { echo "the scan flagged a BOUNDED call — a check that fires on healthy lines gets ignored:"; ac22_scan "$D/neg"; false; }
}

@test "AC22 control (-): a wrapper taking its bound as an ARGUMENT is NOT flagged" {
  # THE SHAPE THAT BROKE THIS SCAN (2026-07-31). The exemption above used to require the wrapper to
  # sit IMMEDIATELY before `osascript`, which is true of hf_bounded/osa_bounded/lcw_osa but false of
  # `sup_bounded 10 osascript` — scripts/lead-supervisor.sh:159, landed the same day by e6d789a8 —
  # because the bound is passed as an argument. `sup_bounded` is a real timeout(1) wrapper
  # (lead-supervisor.sh:77-81, `-k 5`, rc 124 on a cut), so the scan was convicting a healthy line.
  #
  # This is the repo's `denylist-enumerates-spellings-not-the-class` defect, and the SECOND time this
  # particular grep has been miscalibrated (§11.2 records the first). The widening is deliberately
  # narrow — an optional NUMERIC argument only, never `.*` — because the exclusion is line-scoped, so
  # anything lazier would let a real bare call ride along on the same line.
  mkdir -p "$D/neg3"
  {
    printf '#!/bin/bash\n'
    printf 'sup_bounded 10 osascript - %s %s\n' '"$1"' '"$2"'
    printf 'hf_bounded 5 osascript -e %s\n' "'tell application \"iTerm2\" to activate'"
  } > "$D/neg3/argbound.sh"
  n="$(ac22_scan "$D/neg3" | "$G" -c . || true)"
  [ "$n" -eq 0 ] || { echo "the scan flagged a wrapper-with-bound-argument call:"; ac22_scan "$D/neg3"; false; }
}

@test "AC22 control (+): the widened exemption does NOT launder a bare call on the same line" {
  # The counterpart to the widening above, and the reason it is safe to widen at all. The exclusion
  # is line-scoped, so a tolerance that is too lazy exempts the worst case: a genuinely unbounded
  # call sharing a line with a bounded one. Only a NUMERIC argument is tolerated, so the separator
  # here keeps the second call visible.
  mkdir -p "$D/pos2"
  printf '#!/bin/bash\nsup_bounded 10 osascript -e %s\nosascript -e %s\n' \
    "'tell application \"Dia\" to activate'" \
    "'tell application \"Finder\" to activate'" > "$D/pos2/mixed.sh"
  n="$(ac22_scan "$D/pos2" | "$G" -c . || true)"
  [ "$n" -eq 1 ] || { echo "expected exactly the ONE bare call to survive the exemption (n=$n):"; ac22_scan "$D/pos2"; false; }
}

@test "AC22 control (-): prose, assignments and comments are NOT flagged" {
  # Every one of these is a real shape from this repo that a naive `grep osascript` reports.
  mkdir -p "$D/neg2"
  {
    printf '#!/bin/bash\n'
    printf '# osascript -e "commented out"\n'
    printf 'OSASCRIPT="${CC_OSASCRIPT_BIN:-osascript}"\n'
    printf 'echo "note: osascript window-open fails when headless"\n'
    printf 'if command -v osascript >/dev/null; then :; fi\n'
    printf "osascript -e 'delay 2' >/dev/null 2>&1\n"
  } > "$D/neg2/prose.sh"
  n="$(ac22_scan "$D/neg2" | "$G" -c . || true)"
  [ "$n" -eq 0 ] || { echo "false positives on non-call lines:"; ac22_scan "$D/neg2"; false; }
}

# ── THE STANDING ASSERTION ──────────────────────────────────────────────────────────────────────
@test "AC22: zero unbounded osascript calls across hooks/ bin/ scripts/" {
  rows="$(ac22_scan "$ROOT/hooks" "$ROOT/bin" "$ROOT/scripts" || true)"
  n="$(printf '%s' "$rows" | "$G" -c . || true)"
  [ "$n" -eq 0 ] || { echo "UNBOUNDED osascript call site(s) — each can wait forever on a wedged app:"; printf '%s\n' "$rows"; false; }
}

@test "AC22: the delay-exemption is reported, never silently dropped" {
  # An exemption nobody can see is indistinguishable from a hole. If this list ever grows something
  # that is not a bare interpreter delay, it is visible in the gate output.
  ex="$("$G" -rnE "osascript -e '(delay)[[:space:]]+[0-9.]+'" "$ROOT/hooks" "$ROOT/bin" "$ROOT/scripts" 2>/dev/null || true)"
  echo "delay-exempt sites (no target app, cannot block on another process):"
  printf '%s\n' "$ex"
  bad="$(delay_launder "$ROOT/hooks" "$ROOT/bin" "$ROOT/scripts" | "$G" -c . || true)"
  [ "$bad" -eq 0 ] || { echo "a real call laundered itself through the delay exemption:"; delay_launder "$ROOT/hooks" "$ROOT/bin" "$ROOT/scripts"; false; }
}

@test "AC22 control (+): a real call sharing a line with a delay does NOT escape the exemption" {
  # The exemption is only sound while a delay is the ONLY call on its line, and nothing in ac22_scan
  # can enforce that — its delay filter is a line-scoped `grep -v`, so a second, genuinely unbounded
  # call sharing the line is exempted along with the delay. Verified 2026-07-30 with exactly this
  # fixture: it escaped both ac22_scan AND the previous `tell application`-only guard, because
  # `display notification` names no application while still being a real AppleEvent (NotificationCenter).
  mkdir -p "$D/laund"
  {
    printf '#!/bin/bash\n'
    printf "osascript -e 'delay 2'; osascript -e 'display notification \"x\"'\n"
  } > "$D/laund/l.sh"
  s="$(ac22_scan "$D/laund" | "$G" -c . || true)"
  [ "$s" -eq 0 ] || { echo "precondition changed: ac22_scan now catches this unaided, so this guard's premise needs re-deriving"; false; }
  n="$(delay_launder "$D/laund" | "$G" -c . || true)"
  [ "$n" -eq 1 ] || { echo "the laundering guard did not fire (n=$n) — the delay exemption is a hole"; false; }
}

@test "AC22: the printed-mention exemption is reported, never silently dropped" {
  # Same discipline as the delay exemption above: an exemption nobody can see is indistinguishable
  # from a hole. If this list ever grows a row that is not a printed hint, it is visible in the gate.
  ex="$(mention_exempt "$ROOT/hooks" "$ROOT/bin" "$ROOT/scripts")"
  echo "mention-exempt sites (osascript NAMED in an echo/printf hint — no separator, no substitution, so nothing executes):"
  printf '%s\n' "$ex"
  bad="$(mention_launder "$ROOT/hooks" "$ROOT/bin" "$ROOT/scripts" | "$G" -c . || true)"
  [ "$bad" -eq 0 ] || { echo "a call outside any quoted string was exempted as a printed mention:"; mention_launder "$ROOT/hooks" "$ROOT/bin" "$ROOT/scripts"; false; }
}

@test "AC22 control (+): a real call sharing a line with an echo does NOT escape the mention-exemption" {
  # The mandatory counterpart to exemption 2, in the shape of the delay control above. A rule that
  # merely matched `echo` would exempt BOTH of these — the first executes osascript in a new command
  # after the separator, the second substitutes it into echo's own argument list. Neither is a
  # printed mention, and both must survive the exemption.
  mkdir -p "$D/mention"
  {
    printf '#!/bin/bash\n'
    printf 'echo "teardown hint: osascript -e ..."; osascript -e %s\n' "'tell application \"Finder\" to activate'"
    printf 'echo "$(osascript -e %s)"\n' "'tell application \"Dia\" to activate'"
  } > "$D/mention/m.sh"
  n="$(ac22_scan "$D/mention" | "$G" -c . || true)"
  [ "$n" -eq 2 ] || { echo "expected BOTH real calls to survive the mention exemption (n=$n):"; ac22_scan_raw "$D/mention"; echo "-- exempted:"; mention_exempt "$D/mention"; false; }
}

@test "AC22 control (-): a printed teardown hint is NOT flagged" {
  # The line the exemption exists for, reproduced as a fixture so the rule is pinned in BOTH
  # directions — a later tightening that re-convicts a printed hint fails here rather than in review.
  mkdir -p "$D/mention2"
  {
    printf '#!/bin/bash\n'
    printf '  echo "  (teardown: osascript -e %s)"\n' "'tell application \\\"Ghostty\\\" to close window (first window whose id is \\\"\$WIN\\\")'"
  } > "$D/mention2/hint.sh"
  n="$(ac22_scan "$D/mention2" | "$G" -c . || true)"
  [ "$n" -eq 0 ] || { echo "a printed teardown hint was flagged as a call site:"; ac22_scan "$D/mention2"; false; }
  m="$(mention_exempt "$D/mention2" | "$G" -c . || true)"
  [ "$m" -eq 1 ] || { echo "the hint was dropped by some OTHER filter (m=$m) — this control is vacuous"; false; }
}

@test "AC22: the comment-exemption is reported, never silently dropped" {
  # Same discipline as the two exemptions above: an exemption nobody can see is indistinguishable
  # from a hole. If this list ever grows a row from a file that is not really a //-comment language,
  # the launder check below names the file in the gate output.
  ex="$(comment_exempt "$ROOT/hooks" "$ROOT/bin" "$ROOT/scripts")"
  echo "comment-exempt sites (osascript NAMED in a line-leading // comment — nothing after it is code):"
  printf '%s\n' "$ex"
  bad="$(comment_launder "$ROOT/hooks" "$ROOT/bin" "$ROOT/scripts" | "$G" -c . || true)"
  [ "$bad" -eq 0 ] || { echo "a SHELL script wearing a //-comment extension was exempted — // is not a comment there:"; comment_launder "$ROOT/hooks" "$ROOT/bin" "$ROOT/scripts"; false; }
}

@test "AC22 control (+): a mid-line // does NOT launder a real call" {
  # The first of the two restrictions on exemption 3, pinned where it is actually load-bearing —
  # INSIDE a //-comment language, because the extension scope already excludes everything else. A URL
  # scheme puts `//` mid-line in a .mjs that shells out through a template literal, and that shell
  # string can carry a genuinely unbounded call; `${p//a/b}` is the same shape in shell. An exemption
  # that looked for the digraph anywhere on the line would exempt both.
  #
  # WITHOUT the .mjs row this control is VACUOUS, and measurably so: a mutant widening COMMENT_RE
  # from `[[:space:]]*//` to `.*//` SURVIVED the .sh-only version of this test, because a .sh is
  # already excluded by the extension scope — so it re-proved that restriction and said nothing
  # about this one.
  mkdir -p "$D/cmt"
  printf 'execSync(`open http://x && osascript -e %s`)\n' "'tell application \"Finder\" to activate'" > "$D/cmt/mid.mjs"
  printf '#!/bin/bash\np="${x//a/b}"; osascript -e %s\n' "'tell application \"Finder\" to activate'" > "$D/cmt/mid.sh"
  n="$(ac22_scan "$D/cmt" | "$G" -c . || true)"
  [ "$n" -eq 2 ] || { echo "a mid-line // laundered a real call (n=$n, expected 2):"; ac22_scan_raw "$D/cmt"; echo "-- exempted:"; comment_exempt "$D/cmt"; false; }
}

@test "AC22 control (+): a shell line beginning with // is not a comment, so its call is still caught" {
  # The second restriction, and the reason exemption 3 is scoped by EXTENSION rather than by line
  # shape alone. In shell `//` introduces nothing — it is a command that fails (it names a
  # directory) — so a separator after it starts a genuinely unbounded call. A line-shape-only rule
  # would exempt exactly this.
  mkdir -p "$D/cmt2"
  printf '#!/bin/bash\n// not a comment in shell; osascript -e %s\n' "'tell application \"Finder\" to activate'" > "$D/cmt2/sh.sh"
  n="$(ac22_scan "$D/cmt2" | "$G" -c . || true)"
  [ "$n" -eq 1 ] || { echo "a //-prefixed SHELL line laundered its call (n=$n):"; ac22_scan_raw "$D/cmt2"; echo "-- exempted:"; comment_exempt "$D/cmt2"; false; }
}

@test "AC22 control (+): a SHELL script wearing a .js extension is caught by the launder guard" {
  # comment_launder's whole job, exercised — without this it could sit permanently vacuous. COMMENT_RE
  # trusts the extension to mean "// comments to end of line"; this is the file where that trust is
  # misplaced, and `//` is a failed command whose `;` starts a live call. ac22_scan cannot see it —
  # the exemption is line-scoped and the extension says comment — which is the precondition the
  # independent shebang question exists to cover.
  mkdir -p "$D/cmt4"
  {
    printf '#!/usr/bin/env bash\n'
    printf '// not a comment here; osascript -e %s\n' "'tell application \"Finder\" to activate'"
  } > "$D/cmt4/x.js"
  s="$(ac22_scan "$D/cmt4" | "$G" -c . || true)"
  [ "$s" -eq 0 ] || { echo "precondition changed: ac22_scan now catches this unaided, so this guard's premise needs re-deriving"; false; }
  n="$(comment_launder "$D/cmt4" | "$G" -c . || true)"
  [ "$n" -eq 1 ] || { echo "the launder guard did not fire (n=$n) — the extension scope is unguarded"; false; }
}

@test "AC22 control (-): a // comment naming osascript is NOT flagged" {
  # The line the exemption exists for, reproduced as a fixture so the rule is pinned in BOTH
  # directions — a later tightening that re-convicts a source comment fails here rather than in
  # review. The markdown backticks are the shape that made this a false positive at all: to a
  # shell-syntax scanner they read as command substitution.
  mkdir -p "$D/cmt3"
  printf '// WHY A COMPILED BINARY, NOT JXA. The bridge (`osascript -l JavaScript`) is unreliable.\n' > "$D/cmt3/x.swift"
  n="$(ac22_scan "$D/cmt3" | "$G" -c . || true)"
  [ "$n" -eq 0 ] || { echo "a source comment was flagged as a call site:"; ac22_scan "$D/cmt3"; false; }
  m="$(comment_exempt "$D/cmt3" | "$G" -c . || true)"
  [ "$m" -eq 1 ] || { echo "the comment was dropped by some OTHER filter (m=$m) — this control is vacuous"; false; }
}

# ── the shared lib ──────────────────────────────────────────────────────────────────────────────
@test "osa.sh exists and its bound is REAL (a slow command is actually cut)" {
  [ -r "$LIB" ] || { echo "hooks/lib/osa.sh missing"; false; }
  # Positive control for the BOUND itself: without this, "osa_bounded ran" proves only that a
  # function exists, not that anything is bounded.
  run env CC_OSA_TIMEOUT_S=1 bash -c ". '$LIB'; osa_bounded sleep 20"
  [ "$status" -eq 124 ]
}

@test "osa.sh: a normal command passes through with its own exit status" {
  run bash -c ". '$LIB'; osa_bounded printf hi"
  [ "$status" -eq 0 ]
  [ "$output" = "hi" ]
  run bash -c ". '$LIB'; osa_bounded false"
  [ "$status" -eq 1 ]
}

@test "osa.sh: CC_OSA_TIMEOUT_BIN set-but-EMPTY genuinely disables the bound" {
  # `${VAR:-}` cannot tell unset from set-empty, so a seam written that way can never be turned OFF —
  # and a suite that cannot run the unbounded path cannot prove the bounded path differs from it.
  run env CC_OSA_TIMEOUT_BIN= CC_OSA_TIMEOUT_S=1 bash -c ". '$LIB'; [ -z \"\$CC_OSA_TB\" ] || exit 9; osa_bounded printf ok"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "osa.sh: with no timeout binary it degrades to UNBOUNDED, never to a lost call" {
  # Failing closed here would silently delete every notification on a machine without coreutils —
  # permanent, unlike the occasional hang it would be preventing.
  run env CC_OSA_TIMEOUT_BIN=/nonexistent/timeout bash -c ". '$LIB'; osa_bounded printf through"
  [ "$status" -eq 0 ]
  [ "$output" = "through" ]
}

# ── the two converted sites ─────────────────────────────────────────────────────────────────────
@test "converted: screenshot-to-clipboard and dia-cdp-launch call through osa_bounded" {
  for f in "$ROOT/bin/screenshot-to-clipboard.sh" "$ROOT/bin/dia-cdp-launch.sh"; do
    [ -r "$f" ] || { echo "missing $f"; false; }
    "$G" -qE 'osa_bounded osascript' "$f" || { echo "$f still calls osascript unbounded"; false; }
    # The lib must be reached through $0's PHYSICAL location: ~/bin holds per-file symlinks into the
    # checkout, and a directory of per-file symlinks never gains a NEW file.
    "$G" -qE 'readlink' "$f" || { echo "$f does not resolve \$0's symlink before sourcing the lib"; false; }
    "$G" -qE 'osa_bounded\(\) \{ timeout' "$f" || { echo "$f has no inline fallback if the lib is unreadable"; false; }
  done
}
