#!/bin/bash
# pane-spawn-coverage-lint — a RATCHET on pane-spawn sites that leave no row (item 1467ea1dad4f).
#
# WHY THIS IS A GATE AND NOT A DOC. `scripts/lib/pane-spawn-log.sh` exists to make exactly one
# inference sound:
#
#     a pane that exists with NO row in ~/.claude/logs/pane-spawns.jsonl was spawned by something
#     OUTSIDE this tree.
#
# That inference is what separates §S4.1's two surviving hypotheses — an unlogged caller vs an
# undocumented detached child — and it is only as good as COVERAGE. One uninstrumented spawn site
# downgrades it to "outside the tree, or that one site", which is the ambiguity being closed. A
# census that lives in a comment decays the first time someone adds a `launch`; a lint in the
# always-run gate phase cannot (memory `enforcement-must-live-at-the-chokepoint` — a check in its
# own suite is DETECTION; the gate is where it becomes a gate).
#
# THE RULE — narrow, and decidable from one file. A line that ISSUES a terminal-surface primitive
# must have a logger call within CC_PSC_WINDOW lines of it. Three primitive families, each chosen
# because it CREATES a surface rather than addressing one:
#
#   1. `launch --type=` / `launch --location=`   kitty remote-control window/tab/os-window creation
#   2. `create tab with` · `create window with` · `split vertically with` · `split horizontally with`
#                                                iTerm2 AppleScript surface creation
#   3. `detach-window` WITHOUT `--target-tab`    kitty: no target ⇒ a NEW OS window; with a target
#                                                it only re-homes an existing one and creates nothing
#
# `launch --type=background` is EXCLUDED from family 1 and that is a correctness point, not a
# convenience: kitty's `background` type runs a program with NO window at all. config/kitty.conf
# uses it to fire bin/kitty-pane-menu itself. Flagging it would demand a pane-spawn row for
# something that spawns no pane — and a rule that fires where its subject does not exist is the
# always-fires alarm (memory `alarm-polarity-and-attention-budget`).
#
# ── THE ARGV-LIST FORM OF FAMILY 1 (backlog a54e2e838acc) ───────────────────────────────────────
# Family 1 was written as `launch[[:space:]]+--type=`, i.e. it requires LITERAL WHITESPACE between
# the verb and its flag. That is how a shell writes an argv — `kitty @ launch --type=os-window`, and
# `KARGS=(launch --type=os-window)` too, since an unquoted array separates its elements with spaces.
# It is NOT how a list-based language writes one. `subprocess.run(["kitty","@","launch",
# "--type=os-window"])` separates the same two tokens with `","`, matches nothing, and the file reads
# as having ZERO spawn sites. That is a false NEGATIVE in a coverage ratchet — the expensive
# direction, and the silent one: the docstring gap above (c6a47d8c3ccb) refused a land and named the
# file, while this one simply never fires. The same blind spot covers a QUOTED shell array,
# `KARGS=("launch" "--type=os-window")`, so this was never really a Python fact — it is a fact about
# quoting, and `.py` is merely where the quoted form is idiomatic rather than unusual.
#
# THE RULE ADDED IS ADJACENCY, NOT PROXIMITY, and that distinction was measured rather than
# reasoned. The obvious widening — allow anything between the verb and the flag, `launch.{0,40}--
# type=` — has a LIVE TIER-1 FALSE POSITIVE in this tree today: bin/cc-where:175 is prose reading
# "an overlay launch on it — kitty @ launch with `--type=overlay --keep-focus`", in a file with zero
# logger calls, so that widening would refuse every land until someone instrumented a file that
# spawns nothing. Requiring the two tokens to be ADJACENT LIST ELEMENTS — verb element, then
# immediately a `--flag` element — is decidable from one line, and English does not put a quote and
# a comma between a verb and its flag. Censused over the 426-file population: the adjacency form
# adds 0 lines, the proximity form adds exactly that one false positive.
#
# ⚠ STATED LIMIT, as tier 2's is: a list SPLIT ACROSS LINES is still invisible, because every
# predicate here is line-scoped. `["kitty", "@", "launch",\n "--type=os-window"]` — what a formatter
# produces once the call exceeds its column budget — is not reached, and closing it would need the
# multi-line parsing the tier-2 note already declines on the same grounds. The single-line form is
# what a hand-written call looks like, and it is what the one at-risk file in the tree would produce:
# scripts/assignee-chain-state.py already builds `["kitty", "@"] + [...] + ["ls"]`, one token from a
# site, and that concatenation shape IS caught.
#
# ── TWO TIERS, BECAUSE A PRIMITIVE AND THE LINE THAT ISSUES IT ARE OFTEN NOT THE SAME LINE ──────
# Measured over this tree: five of the 23 sites are DECLARATIONS, not invocations —
# `KARGS=(launch --type=os-window)` builds an argv issued 70 lines later; `set newTab to (create tab
# with default profile)` sits inside a heredoc whose `osascript` call is 24 lines above it. A pure
# proximity rule reports all five, every one a false positive, and a lint with a 5/23 false-positive
# rate is one people turn off. So:
#
#   TIER 1 (BLOCKING)  a primitive in a file with NO logger call anywhere. This is the case that
#                      actually matters — a new spawner, or an existing one nobody instrumented —
#                      and it has no false positives by construction.
#   TIER 2 (NOTICE)    a primitive whose file IS instrumented but whose own occurrence has no logger
#                      within the window. Printed, counted, never blocking.
#
# ⚠ STATED PLAINLY BECAUSE IT IS THE RULE'S REAL LIMIT: tier 2 means a SECOND, uninstrumented spawn
# added to an ALREADY-instrumented file is a notice and not a block. Closing that would need
# heredoc- and array-aware parsing in bash — more machinery than the check is worth, and machinery
# whose own failure mode is silent. The notice is the mitigation; it names the file and line.
#
# WHAT IS DELIBERATELY NOT FLAGGED, and why each exclusion is safe rather than convenient:
#   • CALLERS of an instrumented primitive — `it2 session split`, `handoff-fire.sh …`,
#     `kitty-split-launch.sh …`. The callee owns the row. Flagging callers too would demand a row
#     per LAYER, and "how many panes were spawned" would stop being a count anybody can take.
#   • `tests/` — fixtures and stubs spawn nothing real.
#   • This file and the library, which contain the patterns as data (self-exclusion, the same
#     treatment utc-stamp-lint.sh gives its own scar fixtures).
#   • The ALLOWLIST below — one entry, with its reason stated in-band so it cannot rot silently.
#
# ── COULD-NOT-RUN IS A THIRD STATE, NEVER A VERDICT (backlog 91c6f91062ae) ──────────────────────
# Until 2026-08-13 this lint had exactly ONE exit-2 path — "scan root is not a directory" — and all
# three of its per-file predicates were written to swallow their own failure:
#
#   `grep -nE … "$f" 2>/dev/null || true`   a grep that could not RUN (rc>=2) became "no sites"
#   `cat "$f" 2>/dev/null`                  a read that failed became "no logger call anywhere"
#   `sed -n "lo,hip" "$f" 2>/dev/null`      a failed context read became "no logger call nearby"
#
# Each of those degrades a DEAD predicate into a shape indistinguishable from a real answer, and
# they degrade in BOTH directions: a dead grep reports a clean file (false green), while a dead cat
# or sed reports a file with no coverage (a FABRICATED violation naming a file that is fine). Both
# sibling lints closed exactly this gap deliberately and each records what it cost —
# test-hermeticity's ratchet fabricated violations against clean files under fork exhaustion, which
# is worse than a bare non-verdict because it reads as an attributable RED.
#
# The remedy here is theirs: every predicate retries 3x 1s apart (they are pure and cheap, so
# re-running is free), reports failure IN BAND as the single record SCAN_SENTINEL — fail-SAFE, never
# a fabricated finding — and the run is then condemned to exit 2 with no verdict at all. ship-land
# already routes exit 2 to arm_nonverdict, so the plumbing was there and this arm simply never
# used it.
#
# 🚨 AND IT IS THE PREREQUISITE FOR THE MEMO BELOW, not a tidy-up beside it. A false green that
# lasts one run is a bad afternoon; a false green KEYED ON CONTENT by a memo that never re-runs the
# file is permanent.
#
# ── THE PER-FILE MEMO ────────────────────────────────────────────────────────────────────────────
# 19.5 ms/file over 404 files = 7.3s, measured through ship-land's own_run, re-paid in full on every
# optimistic round a sibling invalidates (exit 42) over a tree identical but for the sibling's delta.
# scripts/lib/gate-memo.sh's BATCH API (memo_batch_arm/hit/record) hashes the whole population in
# ONE `git hash-object` fork and then answers from builtins at 0.33 ms/file — the per-file API's
# 16.8 ms/file would have paid 17 to save 19, which is why the batch form exists at all.
#
# Only "this file emitted nothing" is ever cached (gate-memo invariant 1: a finding is never cached
# and always re-prints itself), and only from a run in which no predicate failed. That second veto
# is ABSOLUTE and never a per-file delta — see the record site.
#
# The batch API is INDEX-KEYED, so THE POPULATION IS BUILT EXACTLY ONCE and the same array is both
# armed on and walked. Two globs written to look alike are the one way this API can serve one file's
# verdict for another.
#
# Kill switch: CC_PSC_MEMO=off (SHIP_LAND_MEMO=off also disables it, via memo_init).
#
# Exit: 0 = every site covered · 1 = an uncovered site · 2 = bad usage / unreadable scan dir /
#       a predicate that could not RUN (LOUD, never silent-green — an unreadable tree is not a
#       clean tree, and a scan that could not run is not a verdict)
#
# Env seams: CC_PSC_WINDOW (proximity lines, default 12) · CC_PSC_ALLOWLIST (overrides the embedded
# ratchet; set-EMPTY genuinely means "no exemptions", which `${VAR:-}` could not express) ·
# CC_PSC_MEMO=off (disarm the memo) · CC_PSC_OWN (newline-separated repo-relative paths; only these
# may BLOCK, everything else prints ADVISORY — this is what BOUNDS the gate at its ship-land.sh call
# site, so an uninstrumented spawner someone else left cannot freeze every land by everyone.
# Set-EMPTY is honored verbatim: a land that changed no scannable file blocks on nothing).
set -uo pipefail

WINDOW="${CC_PSC_WINDOW:-12}"
# Consume --selftest BEFORE $1 is read as a scan root, or the flag resolves to a directory named
# "--selftest" and the lint reports rc=2 on its own verification path.
SELFTEST=0
if [ "${1:-}" = "--selftest" ]; then SELFTEST=1; shift; fi

# THE POPULATION'S DIRECTORIES, NAMED ONCE. collect_files walks these and `--print-scope` prints
# them, so the dirs that can hold a spawn site are declared in exactly one place.
PSC_LAYERS="bin scripts hooks commands"

# ── --print-scope: the population this lint JUDGES, as git pathspecs, one per line ────────────────
# Answered HERE, ahead of `ROOT="${1:-$SELF_ROOT}"` below, for the same reason --selftest is consumed
# above: past that line the flag resolves to a directory named "--print-scope" and the lint reports a
# non-verdict on its own scope question.
#
# `<layer>/*` is a SUPERSET of what collect_files keeps — that walk also filters by name (`*.sh`,
# `*.py`, or no extension at all, the last of which no git pathspec can express) — and the direction
# is the safe one. The own-set is matched against the paths this lint REPORTS, so an entry naming a
# file it never judges is inert; an own-set that MISSES a judged file is the failure, because it does
# not error — it is the legitimate spelling of "this land touches nothing I judge", so the finding
# degrades to advisory and the land proceeds.
#
# WHY IT EXISTS (backlog 5fc8ff411a7c, extending 0be0bd2c0b65 to the six arms left out of it).
# scripts/ship-land.sh built this lint's own-scope set from a `-- 'bin/*' 'hooks/*' 'scripts/*'
# 'commands/*'` pathspec RESTATED in ship-land. That restatement could not drift at RUNTIME (this
# lint has no env seam on its population), and that was the whole of its defence: it could still
# drift by a CODE edit to PSC_LAYERS, silently, in the advisory direction.
if [ "${1:-}" = "--print-scope" ]; then
  _ps_restore_f=0; case "$-" in *f*) _ps_restore_f=1 ;; esac
  # Globbing OFF for the split: an unquoted expansion would also PATHNAME-EXPAND each layer against
  # the caller's CWD and print real repo paths instead of the pathspec.
  set -f
  for _ps_l in $PSC_LAYERS; do printf '%s/*\n' "$_ps_l"; done
  [ "$_ps_restore_f" -eq 1 ] || set +f
  exit 0
fi
# SELF is symlink-resolved and ABSOLUTE — ~/.claude reaches this file through a per-file symlink, so
# an unresolved $0 keys the memo on a path that differs per caller for identical bytes, and
# SELF_ROOT would land in ~/.claude rather than the checkout. The sibling lint shipped both of those
# in one iteration (a relative SELF made the key unobtainable from any other directory, so the memo
# silently never armed).
SELF="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
case "$SELF" in /*) ;; *) SELF="$(cd "$(dirname "$SELF")" && pwd)/$(basename -- "$SELF")" ;; esac
# SELF_ROOT is where the LINT lives; ROOT is what it SCANS. They are the same in the gate and
# deliberately different under --selftest, so the library must be sourced from SELF_ROOT — sourcing
# it from the scan root would leave the memo fail-closed OFF on every synthetic corpus.
SELF_ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
ROOT="${1:-$SELF_ROOT}"

# The ratchet. `path::reason` — the reason is REQUIRED and is printed on every run, so an exemption
# has to keep justifying itself to whoever reads the gate output.
_default_allowlist() {
  cat <<'ALLOW'
scripts/terminal-bakeoff.sh::a one-off TERMINAL COMPARISON bench. Its surfaces are WezTerm and Ghostty windows plus a DETACHED private kitty instance on its own socket (`kitty --listen-on … --detach`), none of which can host an agent session — so a pane it makes can never be mistaken for one of the fleet's, which is the only confusion this lint exists to prevent.
scripts/typed-send-lint.sh::a LINT, and its spawn-shaped lines are FIXTURE TEXT, not spawns. They live inside --selftest heredocs that are written into a mktemp sandbox so the detector can be run against them and proven to go RED; nothing there is ever executed, and the file creates no terminal surface at any point. Instrumenting it would mean calling cc_log_pane_spawn from a scanner that spawns nothing, which would put FALSE rows in the very log this lint exists to keep trustworthy.
ALLOW
}

if [ -n "${CC_PSC_ALLOWLIST+set}" ]; then ALLOWLIST="$CC_PSC_ALLOWLIST"; else ALLOWLIST="$(_default_allowlist)"; fi

# The logger call shapes that COUNT as coverage — TWO, and a per-file shim is deliberately NOT one
# of them.
#
# THE SHIM WAS TRIED AND IT BROKE SEVEN SUITES. The first version of this instrumentation defined a
# one-line `_spawn_log()` at the top of each file and called that. It went red immediately, because
# handoff-fire.sh's `as_tab`, `spawn_frontmost`, `it2py` and `mark_fired_peer` — and
# lr-reset-poller's `spawn_gui` — are sed-EXTRACTED as isolated units by their suites, which
# `eval` the function body with none of its file's top-level definitions present. A call to a
# top-level shim is then a `command not found` inside the unit under test: 41 failures, and
# handoff-fire.sh's own comments had already named the trap ("a new collaborator would be a 127
# under `set -e` — the trap this file has already paid for once").
#
# So the only accepted form is the one that survives extraction: an INLINE `command -v` guard around
# the library function. It depends on nothing but the library, and in an extracted context the guard
# short-circuits to a clean no-op. Accepting a shim spelling here would invite the same breakage back.
_covered_by() {
  grep -qE 'cc_log_pane_spawn|log_pane_spawn\(' <<<"$1"
}

rc=0 checked=0 flagged=0 noticed=0 advised=0 seen=0 _emit0=0
SELF_BASE="$(basename -- "$SELF")"

# ── COULD-NOT-RUN: every per-file predicate RETRIES, then reports IN BAND ────────────────────────
# The sentinel is RETURNED rather than CHECK_FAILED being set inside these functions, and that is
# forced rather than stylistic: every caller reads them through `$( )`, so an assignment made in one
# would happen in a SUBSHELL and be discarded — the flag would read 0 in the parent and an
# unrunnable scan would exit 0, silent-green, which is the exact conflation the third state exists
# to prevent. Three tries 1s apart: these are pure reads, so re-running one is free.
SCAN_SENTINEL='!SCAN-FAILED'
CHECK_FAILED=0
# TEST SEAM — the DELAY between tries, never the NUMBER of them. The three-try count is the safety
# property (a transient failure must be re-asked before the run is condemned) and is fixed in the
# code; --selftest sets this to 0 so nine real seconds of sleeping do not enter every land's gate,
# and pins the count separately by COUNTING the shim's invocations. A seam that could change the
# try count would let the harness collapse the state under test.
PSC_RETRY_SLEEP="${CC_PSC_RETRY_SLEEP:-1}"
PSC_SITE_RE='launch[[:space:]]+--type=|launch[[:space:]]+--location=|create tab with|create window with|split vertically with|split horizontally with|detach-window'
# …and family 1 again, as ADJACENT QUOTED ARGV ELEMENTS — see "THE ARGV-LIST FORM" in the header.
# Two alternations, not a loosened first one: the whitespace form above is left byte-for-byte alone,
# so this can only ADD matches and can never change a verdict the tree already has.
PSC_SITE_RE="$PSC_SITE_RE|launch[\"'][[:space:],]*[\"']--type=|launch[\"'][[:space:],]*[\"']--location="

# psc_body <file> — the file's bytes, for the file-level coverage question. An EMPTY file is an
# ANSWER (rc 0, no output); only a read that could not run yields the sentinel.
psc_body() {
  local out rc
  for _ in 1 2 3; do
    out="$(cat "$1" 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 0 ]; then printf '%s\n' "$out"; return 0; fi
    sleep "$PSC_RETRY_SLEEP"
  done
  echo "pane-spawn-coverage-lint: ⛔ could not READ $1 after 3 tries (cat rc=$rc)" >&2
  printf '%s\n' "$SCAN_SENTINEL"   # fail-SAFE: a non-verdict, never "this file has no log call"
}

# psc_sites <file> — "<lineno>:<line>" per primitive occurrence. grep rc 1 is NO MATCH, which is an
# ANSWER; only rc>=2 is a predicate that could not RUN. Collapsing the two under `|| true` is what
# let a dead grep report a clean file, and it was the false-GREEN half of this gap.
psc_sites() {
  local out rc
  for _ in 1 2 3; do
    out="$(grep -nE "$PSC_SITE_RE" "$1" 2>/dev/null)"; rc=$?
    if [ "$rc" -le 1 ]; then [ -n "$out" ] && printf '%s\n' "$out"; return 0; fi
    sleep "$PSC_RETRY_SLEEP"
  done
  echo "pane-spawn-coverage-lint: ⛔ site scan could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
  printf '%s\n' "$SCAN_SENTINEL"
}

# psc_context <file> <lineno> — the ±WINDOW window around a site. A dead sed here was the
# FABRICATED-VIOLATION half: an empty context reads as "no log call nearby" and names a clean file.
psc_context() {
  local out rc lo hi
  lo=$(( $2 > WINDOW ? $2 - WINDOW : 1 )); hi=$(( $2 + WINDOW ))
  for _ in 1 2 3; do
    out="$(sed -n "${lo},${hi}p" "$1" 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 0 ]; then printf '%s\n' "$out"; return 0; fi
    sleep "$PSC_RETRY_SLEEP"
  done
  echo "pane-spawn-coverage-lint: ⛔ context read could not RUN for $1:$2 after 3 tries (sed rc=$rc)" >&2
  printf '%s\n' "$SCAN_SENTINEL"
}

# ── PYTHON DOCSTRINGS: THE COMMENT FORM THAT CARRIES NO `#` (backlog c6a47d8c3ccb) ──────────────
# scan_file drops a leading-`#` line because a comment DESCRIBES a primitive rather than issuing
# one — "without this the lint would flag its own documentation", as the selftest case says. That
# argument is about PROSE, not about shell, and Python's `#` comments already inherit it. Python's
# OTHER comment form does not: a docstring line opens with no `#`, so prose citing
# `launch --type=os-window` inside one is read as a spawn site, and in a file that issues nothing
# that is a TIER 1 BLOCK — a land refused because its diff DOCUMENTED a primitive. `.py` has been
# in collect_files' -name set since this lint shipped, so the scan reaches those files; only the
# skip rule never learned the language.
#
# FAILS TOWARD FLAGGING, AND THAT IS THE ENTIRE DESIGN. This is a MODEL of the file, and a wrong
# model that deletes a real site is the uninstrumented spawner the ratchet exists to catch — the
# one direction that costs something. So the model REFUSES rather than guesses, in three places,
# and each refusal falls back to exactly today's behaviour:
#   • a body mixing `"""` and `'''`  ⇒ no skips at all; one toggle cannot track two delimiters
#   • a toggle still OPEN at EOF     ⇒ no skips at all; the quoting is not what this model thinks
#   • an inline triple-quoted string ⇒ not prose unless the line OPENS with the delimiter, so
#                                      `x = f("""…""")` is judged exactly as it is today
# A false positive is the worst any of those can do, and a missed spawner is unreachable from here.
# Pinned in --selftest in BOTH directions: the prose cases go green, and a real invocation sitting
# in a file that also contains docstrings stays RED.
#
# Costs nothing on the common path — scan_file calls this only for a `.py` file that ALREADY has a
# site match, which is 0 of the 36 `.py` files under bin/ scripts/ hooks/ commands/ today.
#
# Reads the body scan_file ALREADY read through psc_body's guarded retry, so this adds no predicate
# that can die and no fourth could-not-run path; it is pure shell over a string in hand.
psc_docstring_lines() {
  local body="$1"
  local line stripped d n rest nr=0 open=0 out=""
  # One delimiter or none. Both present ⇒ refuse (see the header above).
  case "$body" in
    *'"""'*)
      case "$body" in *"'''"*) return 0 ;; esac
      d='"""' ;;
    *"'''"*) d="'''" ;;
    *) return 0 ;;
  esac
  while IFS= read -r line; do
    nr=$((nr + 1))
    n=0; rest="$line"
    while :; do
      case "$rest" in *"$d"*) n=$((n + 1)); rest="${rest#*"$d"}" ;; *) break ;; esac
    done
    if [ "$open" = 1 ]; then
      # Interior of a docstring, including the line that closes it: prose either way.
      out="$out$nr|"
    else
      stripped="${line#"${line%%[![:space:]]*}"}"
      # Only a line that OPENS with the delimiter is a docstring. A triple-quoted string used
      # mid-expression is left alone — that is the third refusal above.
      case "$stripped" in
        "$d"*|[rRbBuUfF]"$d"*|[rRbBuUfF][rRbBuUfF]"$d"*) out="$out$nr|" ;;
      esac
    fi
    [ $((n % 2)) = 1 ] && open=$((1 - open))
  done <<EOF
$body
EOF
  # Unbalanced ⇒ the model did not resolve ⇒ skip nothing.
  [ "$open" = 0 ] || return 0
  [ -z "$out" ] || printf '|%s' "$out"
}

# THE EMIT DETECTOR. Every branch in scan_file that prints a finding increments exactly one of these
# three, so their sum is unchanged across a file IFF that file emitted nothing. `checked` is
# deliberately NOT in the sum: it counts SITES, and a file whose every site is covered increments it
# while emitting nothing — which is precisely the cacheable case.
psc_emit_sum() { printf '%s' "$(( flagged + noticed + advised ))"; }

# ── the memo ────────────────────────────────────────────────────────────────────────────────────
PSC_MEMO_OK=0 PSC_CHECKER="" PSC_MEMO_HITS=0 PSC_MEMO_RAN=0
PSC_FILES=()
if [ "${CC_PSC_MEMO:-on}" != "off" ] && [ -r "$SELF_ROOT/scripts/lib/gate-memo.sh" ]; then
  # shellcheck source=/dev/null
  . "$SELF_ROOT/scripts/lib/gate-memo.sh" 2>/dev/null || true
fi

psc_memo_arm() {  # $@ = the EXACT ordered population → 0 = armed
  PSC_MEMO_OK=0
  [ "${CC_PSC_MEMO:-on}" != "off" ] || return 1
  command -v memo_init >/dev/null 2>&1 || return 1
  command -v memo_batch_arm >/dev/null 2>&1 || return 1  # an older lib ⇒ memo OFF, today's behaviour
  memo_init || return 1                    # dirty tree · no git dir · unwritable store ⇒ memo OFF
  local selfblob readset
  selfblob="$(git hash-object -- "$SELF" 2>/dev/null)" || return 1
  [ -n "$selfblob" ] || return 1
  # THE READ SET, written as an executable declaration rather than described in prose. Everything
  # that can change what "this file emitted nothing" means:
  #   lint   — the detector itself, which carries both regexes, both tiers and every exclusion
  #   window — CC_PSC_WINDOW decides tier 2 DIRECTLY; a wider window turns a NOTICE into silence
  #   allow  — hashed BY VALUE, because CC_PSC_ALLOWLIST changes what this lint calls green without
  #            changing one byte of it, and it also selects the population
  #
  # CC_PSC_OWN is deliberately ABSENT, and that is an argument rather than an oversight: own-scope
  # decides only WHICH emission an uncovered site becomes — blocking, or ADVISORY. Both are
  # emissions, so a file with an uncovered site is never recorded under either. "Emitted nothing"
  # means every site was covered within the window, which no own-set can change. Pinned by the
  # own-scope memo cases in tests/pane-spawn-memo.bats, in both directions.
  readset="$(
    printf 'psc-readset/v1\n'
    printf 'lint=%s\n'   "$selfblob"
    printf 'window=%s\n' "$WINDOW"
    printf 'allow=%s\n'  "$ALLOWLIST"
  )" || return 1
  PSC_CHECKER="psc/$(printf '%s' "$readset" | git hash-object --stdin 2>/dev/null)"
  [ "$PSC_CHECKER" != "psc/" ] || return 1
  memo_batch_arm "$PSC_CHECKER" "$@" || return 1
  PSC_MEMO_OK=1
  return 0
}

# THE POPULATION, BUILT EXACTLY ONCE — see the batch-memo note in the header. BOTH skip filters (the
# self/library exclusion and the allowlist) live HERE, so a file skipped for either reason is absent
# from the armed list and the walked list alike, and the index cannot drift. Building it twice is
# the only way this API can serve one file's verdict for another.
collect_files() {
  local d f rel
  # shellcheck disable=SC2086  # deliberate word-split of PSC_LAYERS; the list is a fixed literal
  for d in $PSC_LAYERS; do
    [ -d "$ROOT/$d" ] || continue
    while IFS= read -r f; do
      case "$(basename -- "$f")" in "$SELF_BASE"|pane-spawn-log.sh) continue ;; esac
      rel="${f#"$ROOT"/}"
      # Allowlisted?
      if printf '%s\n' "$ALLOWLIST" | grep -qF -- "$rel::"; then continue ;fi
      PSC_FILES[${#PSC_FILES[@]}]="$f"
    done < <(find "$ROOT/$d" -type f \( -name '*.sh' -o -name '*.py' -o ! -name '*.*' \) 2>/dev/null)
  done
}

scan_file() {
  local f="$1" rel line n ctx file_covered body sites docprose
  rel="${f#"$ROOT"/}"
  body="$(psc_body "$f")"
  if [ "$body" = "$SCAN_SENTINEL" ]; then CHECK_FAILED=1; return 0; fi
  file_covered=0; _covered_by "$body" && file_covered=1
  sites="$(psc_sites "$f")"
  if [ "$sites" = "$SCAN_SENTINEL" ]; then CHECK_FAILED=1; return 0; fi
  [ -n "$sites" ] || return 0
  # Python's docstring prose — computed HERE, after the early return above, so a `.py` file with no
  # site match never pays for it. `|n|` delimited so the per-line test is a `case`, never a pipe.
  docprose=""
  case "$f" in *.py) docprose="$(psc_docstring_lines "$body")" ;; esac
  # A heredoc, NOT `< <(grep …)`: the population is scanned once above so its failure can be seen,
  # and re-running the grep here would be a second, unguarded predicate.
  while IFS=: read -r n line; do
      [ -n "$n" ] || continue
      # Comment lines describe primitives; they do not issue them. Leading-# only, so an inline
      # trailing comment on a real launch still counts as the launch it is.
      case "$(printf '%s' "$line" | sed 's/^[[:space:]]*//')" in '#'*) continue ;; esac
      # …and the same argument for the comment form that carries no `#`. A `case` and not a
      # `printf | grep -qxF`: under the `set -o pipefail` above, grep -q SIGPIPEs its producer and
      # the pipeline reads FALSE precisely WHEN IT MATCHES — the trap this file's own tier-2 notice
      # case records having fallen into.
      case "$docprose" in *"|$n|"*) continue ;; esac
      # `--type=background` runs a program with NO window — not a surface, so not a site.
      case "$line" in *--type=background*) continue ;; esac
      # `detach-window` is a primitive ONLY without a target tab.
      case "$line" in *detach-window*) case "$line" in *--target-tab*) continue ;; esac ;; esac
      checked=$((checked + 1))
      ctx="$(psc_context "$f" "$n")"
      if [ "$ctx" = "$SCAN_SENTINEL" ]; then CHECK_FAILED=1; continue; fi
      _covered_by "$ctx" && continue
      if [ "$file_covered" = 1 ]; then
        printf 'NOTICE %s:%s: primitive not within %s lines of a log call (file IS instrumented):\n    %s\n' \
          "$rel" "$n" "$WINDOW" "$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-120)" >&2
        noticed=$((noticed + 1)); continue
      fi
      # OWN-SCOPE. CC_PSC_OWN unset ⇒ every finding blocks (the standalone/audit posture). SET,
      # including set to EMPTY, is honored verbatim: an empty own-set means this land changed no
      # scannable file, so nothing may block. Only a file in the set can turn rc red; everything
      # else prints as ADVISORY and is counted. This is what bounds the gate — see the
      # `gate_bounded:` markers at its ship-land.sh call site.
      # DRAINED, not -q. Same class as bats-shellcheck-lint's own-scope predicate, and the same
      # fail-OPEN direction: under `set -uo pipefail` grep exits on the first match, the producer
      # takes SIGPIPE, pipefail hands back non-zero, the `!` turns that into TRUE, and a file that
      # IS in this land's own-set takes the ADVISORY branch — the finding stops blocking and the
      # land proceeds. The own-set is CHANGED PATHS rather than changed lines, so this one is
      # LATENT rather than live (the whole scannable corpus bounds it well under the 37,121-byte
      # safe floor for this two-stage shape); it is drained anyway because latency is a property of
      # today's diff sizes, not of the code, and nothing announces the crossing.
      if [ -n "${CC_PSC_OWN+set}" ] && ! printf '%s\n' "$CC_PSC_OWN" | grep -xF -- "$rel" >/dev/null; then
        printf 'ADVISORY %s:%s: pane-spawn in a file with NO log call anywhere (outside this diff):\n    %s\n' \
          "$rel" "$n" "$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-120)" >&2
        advised=$((advised + 1)); continue
      fi
      printf '%s:%s: pane-spawn in a file with NO log call anywhere:\n    %s\n' \
        "$rel" "$n" "$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-120)" >&2
      flagged=$((flagged + 1)); rc=1
  done <<EOF
$sites
EOF
}

# THE WALK. `seen` moves exactly once per iteration, as the first statement and before any
# `continue`, so the index below is DERIVED as `seen - 1` rather than kept in a parallel counter
# that eventually drifts from the position in PSC_FILES.
scan_all() {
  local f
  for f in ${PSC_FILES[@]+"${PSC_FILES[@]}"}; do
    seen=$((seen + 1))
    if [ "$PSC_MEMO_OK" = "1" ] && memo_batch_hit "$((seen - 1))"; then
      PSC_MEMO_HITS=$((PSC_MEMO_HITS + 1))
      continue
    fi
    PSC_MEMO_RAN=$((PSC_MEMO_RAN + 1))
    _emit0="$(psc_emit_sum)"
    scan_file "$f"
    # ── THE RECORD, the ONLY place a green is earned here. Two vetoes, both fail-safe: ──
    # (1) this file emitted something ⇒ it is a finding, and a finding is NEVER cached (gate-memo
    #     invariant 1) — it must re-print itself from the file on every run.
    # (2) CHECK_FAILED is set ⇒ some predicate in this run could not RUN. Every unrunnable state
    #     here is fail-SAFE — psc_body/psc_sites/psc_context each return a sentinel rather than a
    #     fabricated answer — so a non-verdict looks EXACTLY like a clean file at this site.
    #     Caching it would freeze a could-not-check into a permanent green keyed on content, the one
    #     way a memo turns "I don't know" into "green".
    #
    #     🚨 ABSOLUTE, never a per-file delta. A delta vetoes only the FIRST file whose predicate
    #     dies; every file after it compares equal to its own baseline and is RECORDED — out of a
    #     run that exits 2 and whose whole point is that it produced no verdict. The sibling lint
    #     shipped exactly that bug for one iteration and only its own control caught it.
    if [ "$PSC_MEMO_OK" = "1" ] \
       && [ "$(psc_emit_sum)" = "$_emit0" ] \
       && [ "$CHECK_FAILED" -eq 0 ]; then
      memo_batch_record "$((seen - 1))"
    fi
  done
}

if [ "$SELFTEST" = 1 ]; then
  T="$(mktemp -d)" || exit 2
  trap 'rm -rf "$T"' EXIT
  mkdir -p "$T/scripts"
  pass=0 total=0
  # --selftest owns the DETECTOR on synthetic fixtures with no history; tests/pane-spawn-memo.bats
  # owns the MEMO against a real committed corpus. That split is the repo's standing rule, and here
  # it is also mechanical: memo_init keys off the CURRENT directory's git state, not $ROOT, so a
  # selftest left memo-armed would write entries for /tmp fixtures into whatever repo the caller
  # happens to be standing in. Asking either harness to do the other's job yields a vacuous pass.
  export CC_PSC_MEMO=off
  export CC_PSC_RETRY_SLEEP=0   # the DELAY only — the three-try count is pinned by counting below
  _case() { # $1=name $2=expected-rc $3=file-body
    total=$((total + 1))
    printf '%s\n' "$3" > "$T/scripts/case.sh"
    ( CC_PSC_ALLOWLIST="" "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" "$T" >/dev/null 2>&1 )
    local got=$?
    if [ "$got" = "$2" ]; then pass=$((pass + 1)); else echo "  selftest FAIL: $1 (want rc=$2, got rc=$got)" >&2; fi
  }
  # RED — an uncovered kitty launch, which is the exact shape of every site this item instrumented.
  _case "bare kitty launch is RED" 1 'kt launch --type=window --location=vsplit --cwd=current'
  # RED — the iTerm2 half. Both backends must be detectable or the rule is half a rule.
  _case "bare osascript create window is RED" 1 'osascript -e "set newWin to (create window with default profile)"'
  _case "bare osascript split vertically is RED" 1 'osascript -e "set p to (split vertically with default profile)"'
  # RED — detach-window with NO target creates an OS window.
  _case "untargeted detach-window is RED" 1 'kitty("detach-window", "--match", "id:3")'
  # GREEN — the two accepted forms, and only those.
  _case "covered by an inline command -v guard is GREEN" 0 \
    'command -v cc_log_pane_spawn >/dev/null 2>&1 && cc_log_pane_spawn split kitty 1 /tmp x
kt launch --type=window --cwd=current'
  # The `log_pane_spawn(` CALL FORM — named for the form, not for a language. _case writes
  # `case.sh`, so this fixture is Python-SHAPED in a shell filename and proves nothing about how a
  # `.py` file is scanned; the _pycase block below owns that axis (backlog c6a47d8c3ccb).
  _case "covered by the log_pane_spawn( call form is GREEN" 0 'log_pane_spawn("os-window","kitty","3","d")
kitty("detach-window", "--match", "id:3")'
  # RED — a per-file shim is NOT coverage. This is the extraction trap the header describes: it
  # LOOKS instrumented and is a `command not found` inside every sed-extracted unit test.
  _case "a per-file _spawn_log shim does NOT count as coverage" 1 '_spawn_log split kitty "" /tmp x
kt launch --type=window --cwd=current'
  # GREEN — a TARGETED detach re-homes an existing window and creates no surface.
  _case "targeted detach-window is GREEN" 0 'kitty("detach-window","--match","id:3","--target-tab","id:9")'
  # GREEN — a caller of an instrumented primitive is not itself a primitive.
  _case "a session-split CALLER is GREEN" 0 'it2 session split -s w0t0p0:42'
  # GREEN — prose describing a primitive is not one. Without this the lint would flag its own
  # documentation and every design comment in handoff-fire.sh.
  _case "a commented primitive is GREEN" 0 '# kt launch --type=window is what the split path used to do'
  # TIER 2 — a logger 40 lines away is a NOTICE, not a block, because the file IS instrumented.
  # This is the declaration shape (array literal / heredoc body) the tree really contains.
  _case "a logger beyond the window in an instrumented file is a NOTICE, not RED" 0 \
    "$(printf 'cc_log_pane_spawn split kitty 1 /tmp x\n%s\nkt launch --type=window\n' "$(for i in $(seq 1 40); do echo ": $i"; done)")"
  # …and the notice must actually be EMITTED, or tier 2 is silent absorption wearing a tier's name.
  total=$((total + 1))
  printf 'cc_log_pane_spawn split kitty 1 /tmp x\n%s\nkt launch --type=window\n' \
    "$(for i in $(seq 1 40); do echo ": $i"; done)" > "$T/scripts/case.sh"
  # CAPTURE, then match — never `… | grep -q`. Under the `set -uo pipefail` above, grep -q exits on the
  # first match, SIGPIPEs the producer, and the pipeline's status becomes 141: the probe reads FALSE
  # precisely WHEN IT MATCHES. Measured here — this case failed while the notice was being printed
  # correctly (memory `pipefail-inverts-early-exit-probe`, 358 candidate sites in this tree).
  _nout="$(CC_PSC_ALLOWLIST="" "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" "$T" 2>&1 >/dev/null || true)"
  case "$_nout" in
    *NOTICE*) pass=$((pass + 1)) ;;
    *) echo "  selftest FAIL: tier-2 notice was not printed" >&2 ;;
  esac
  # `--type=background` spawns no window, so it is not a site at all — in an UNinstrumented file,
  # which is the only condition under which a real site would block.
  _case "launch --type=background is not a site" 0 'kitty @ launch --type=background -- /bin/echo hi'

  # ── THE LANGUAGE AXIS (backlog c6a47d8c3ccb) ────────────────────────────────────────────────────
  # Every case above writes `case.sh`, so none of them says anything about a `.py` file — including
  # the `log_pane_spawn(` one, whose fixture is Python-SHAPED but lands in a shell filename. `.py`
  # is in collect_files' -name set, so these are real scan targets and need their own fixture.
  _pycase() { # $1=name $2=expected-rc $3=file-body
    total=$((total + 1))
    rm -f "$T/scripts/case.sh"
    printf '%s\n' "$3" > "$T/scripts/case.py"
    ( CC_PSC_ALLOWLIST="" "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" "$T" >/dev/null 2>&1 )
    local got=$?
    if [ "$got" = "$2" ]; then pass=$((pass + 1)); else echo "  selftest FAIL: $1 (want rc=$2, got rc=$got)" >&2; fi
    # Restore the invariant the shell cases and the own-scope block below both rely on.
    rm -f "$T/scripts/case.py"
    printf ': nothing here\n' > "$T/scripts/case.sh"
  }
  # GREEN — the defect this closed: prose inside a multi-line docstring, in a file that issues
  # nothing. Pre-fix this is rc 1, a tier-1 block on a file whose only sin is documenting kitty.
  # shellcheck disable=SC2016  # authoring a Python DOCSTRING: the backticks are prose, not a command
  _pycase "a primitive cited in a multi-line docstring is GREEN" 0 '"""Helper notes.

The kitty primitive is `launch --type=os-window`, which creates a new OS window.
We deliberately do not use it here.
"""


def main() -> None:
    print("nothing spawned")'
  # GREEN — the one-line docstring, the commonest shape of all.
  # shellcheck disable=SC2016  # authoring a Python DOCSTRING: the backticks are prose, not a command
  _pycase "a primitive cited in a one-line docstring is GREEN" 0 '"""Notes: the primitive is `launch --type=os-window`."""


def main() -> None:
    print("nothing spawned")'
  # RED — THE CONTROL THAT MUST FAIL. A real invocation as a shell command string, in a file that
  # ALSO carries a docstring, so the toggle is exercised and must not swallow the site below it.
  # Without this case the two greens above are satisfied by a lint that simply stopped looking.
  _pycase "a real invocation BELOW a docstring is still RED" 1 '"""Spawns a window."""

import subprocess


def main() -> None:
    subprocess.run("kitty @ launch --type=os-window", shell=True, check=True)'
  # RED — the mixed-delimiter refusal. `"""` and `'"'''"'` in one body means one toggle cannot track
  # it, so NOTHING is skipped and the file is judged exactly as it is today. Deliberate, not a gap.
  # shellcheck disable=SC2016  # authoring a Python DOCSTRING: the backticks are prose, not a command
  _pycase "mixed triple-quote delimiters skip nothing (fails toward flagging)" 1 '"""Notes: `launch --type=os-window` creates a window."""

X = '"'''"'other'"'''"'


def main() -> None:
    print("nothing spawned")'
  # RED — the unbalanced refusal. A docstring the model never saw close means the model did not
  # resolve, so it declines to act at all rather than guessing a region.
  # shellcheck disable=SC2016  # authoring a Python DOCSTRING: the backticks are prose, not a command
  _pycase "an unbalanced docstring skips nothing (fails toward flagging)" 1 '"""Notes: `launch --type=os-window` creates a window.


def main() -> None:
    print("nothing spawned")'
  # RED — a triple-quoted string used MID-EXPRESSION is not a docstring opener, so the line is
  # judged as the code it is. This is the third refusal, and it is the one that keeps the skip from
  # being a general "any line near a quote" amnesty.
  _pycase "an inline triple-quoted string is not a docstring opener" 1 'CMD = ("""kitty @ launch --type=os-window""")


def main() -> None:
    print(CMD)'

  # ── THE ARGV-LIST FORM (backlog a54e2e838acc) ───────────────────────────────────────────────────
  # The cases above all issue their primitive as a shell command STRING. None of them says anything
  # about the form a list-based language actually writes, where the separator is `","` and not a
  # space — which is why the gap survived the language axis being added at all.
  # RED — the shape the row was filed on. Pre-fix this is rc 0: the file reads as having no sites.
  _pycase "a launch issued as ADJACENT ARGV LIST elements is RED" 1 'import subprocess


def main() -> None:
    subprocess.run(["kitty", "@", "launch", "--type=os-window"], check=True)'
  # RED — the same form with no spaces at all, and via `--location=`, so neither the separator
  # spacing nor the second flag of family 1 is load-bearing.
  _pycase "a compact argv list and --location= are both RED" 1 'import subprocess


def main() -> None:
    subprocess.run(["kitty","@","launch","--location=vsplit"], check=True)'
  # RED — the CONCATENATION shape, which is what the one at-risk file in this tree already builds.
  _pycase "a launch appended as a list fragment is RED" 1 'import subprocess


def main() -> None:
    cmd = ["kitty", "@"] + ["launch", "--type=os-window"]
    subprocess.run(cmd, check=True)'
  # GREEN — and instrumented, so the new form is a real SITE that coverage can satisfy, not merely
  # a new way to go red. Without this the three cases above are met by a rule that only ever blocks.
  _pycase "an instrumented argv-list launch is GREEN" 0 'import subprocess


def main() -> None:
    log_pane_spawn("os-window", "kitty", "3", "d")
    subprocess.run(["kitty", "@", "launch", "--type=os-window"], check=True)'
  # GREEN — `--type=background` spawns no window in ANY form. The downstream exclusion is keyed on
  # the line, so it must compose with the new alternation rather than being bypassed by it.
  _pycase "an argv-list --type=background is still not a site" 0 'import subprocess


def main() -> None:
    subprocess.run(["kitty", "@", "launch", "--type=background", "--", "/bin/echo", "hi"])'
  # RED — the quoted SHELL array, which is the same quoting fact in the other language and proves
  # this was never a Python-only gap.
  # shellcheck disable=SC2016  # authoring a shell FIXTURE: ${KARGS[@]} is expanded by the fixture
  _case "a quoted shell array launch is RED" 1 'KARGS=("launch" "--type=os-window")
kitty @ "${KARGS[@]}"'
  # GREEN — THE GUARD ON THE WIDENING ITSELF, and it is a real line: bin/cc-where:175, prose in a
  # file with no logger call. A proximity rule (`launch` … `--type=` within N chars) flags it and
  # refuses every land; the adjacency rule cannot. Note there is no leading `#` here — the comment
  # skip is deliberately NOT what saves this case, or it would prove nothing about the regex.
  # shellcheck disable=SC2016  # a fixture quoting the tree's own prose: the backticks are prose
  _case "prose naming a launch and a --type= flag is GREEN" 0 '    an overlay launch on it — kitty @ launch with `--type=overlay --keep-focus`):'
  # ── OWN-SCOPE, both directions. This is the clause that BOUNDS the gate, so an unverified one
  # would be a `gate_bounded:` marker asserting a budget nothing enforces.
  printf 'kt launch --type=window --cwd=current\n' > "$T/scripts/case.sh"
  total=$((total + 1))   # IN scope ⇒ still blocks
  ( CC_PSC_ALLOWLIST="" CC_PSC_OWN="scripts/case.sh" "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" "$T" >/dev/null 2>&1 )
  [ $? = 1 ] && pass=$((pass + 1)) || echo "  selftest FAIL: an IN-scope violation must still block" >&2
  total=$((total + 1))   # OUT of scope ⇒ advisory, rc 0
  if ( CC_PSC_ALLOWLIST="" CC_PSC_OWN="scripts/somebody-else.sh" "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" "$T" >/dev/null 2>&1 ); then
    pass=$((pass + 1))
  else echo "  selftest FAIL: an OUT-of-scope violation must not block" >&2; fi
  total=$((total + 1))   # …and it must SAY so, or the bound is silent absorption
  _aout="$(CC_PSC_ALLOWLIST="" CC_PSC_OWN="scripts/somebody-else.sh" "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" "$T" 2>&1 >/dev/null || true)"
  case "$_aout" in
    *ADVISORY*) pass=$((pass + 1)) ;;
    *) echo "  selftest FAIL: an out-of-scope violation was silently dropped, not reported ADVISORY" >&2 ;;
  esac
  total=$((total + 1))   # set-EMPTY is honored verbatim: nothing in scope ⇒ nothing blocks
  if ( CC_PSC_ALLOWLIST="" CC_PSC_OWN="" "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" "$T" >/dev/null 2>&1 ); then
    pass=$((pass + 1))
  else echo "  selftest FAIL: CC_PSC_OWN set-EMPTY must block on nothing" >&2; fi
  total=$((total + 1))   # UNSET ⇒ the standalone/audit posture, everything blocks
  ( CC_PSC_ALLOWLIST="" "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" "$T" >/dev/null 2>&1 )
  [ $? = 1 ] && pass=$((pass + 1)) || echo "  selftest FAIL: CC_PSC_OWN UNSET must block on everything" >&2

  # LOUD on an unreadable root — a scan that cannot read must never report clean.
  total=$((total + 1))
  ( "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" "$T/definitely-not-here" >/dev/null 2>&1 )
  [ $? = 2 ] && pass=$((pass + 1)) || echo "  selftest FAIL: missing root should exit 2" >&2

  # A root that IS a directory but holds no scannable file proved nothing about coverage. Without
  # this it reports OK, which is one directory typo away from a green gate over an unscanned tree.
  total=$((total + 1))
  mkdir -p "$T/emptyroot"
  ( "$SELF" "$T/emptyroot" >/dev/null 2>&1 )
  [ $? = 2 ] && pass=$((pass + 1)) || echo "  selftest FAIL: a root with nothing to scan should exit 2, not report OK" >&2

  # ── COULD-NOT-RUN, ONE CASE PER PREDICATE (backlog 91c6f91062ae) ────────────────────────────────
  # Each case is a PATH shim that fails for exactly ONE file and execs the real tool otherwise, so
  # only the predicate under test dies. That precision is what makes these cases mean anything: this
  # lint also greps a HERESTRING (_covered_by), greps the allowlist with no path argument, and seds
  # STDIN to trim leading space — a blanket "make grep fail" would kill those too and the case would
  # go red for a reason it does not name.
  #
  # THE THREE MUTANTS ARE NOT THE SAME MUTANT. Before this fix each predicate degraded differently,
  # and two of the three degraded toward a FABRICATED RED rather than a false green:
  #   grep dead ⇒ "no primitive sites"     ⇒ rc 0, silent green over an unscanned file
  #   cat dead  ⇒ "no logger call in file" ⇒ rc 1, a tier-1 block naming a file that is fine
  #   sed dead  ⇒ "no logger call nearby"  ⇒ rc 1, the same fabricated block one tier down
  # All three must now be rc 2 — a non-verdict — and each must have been RE-ASKED three times first.
  REAL_GREP="$(command -v grep)"; REAL_CAT="$(command -v cat)"; REAL_SED="$(command -v sed)"
  SHIM="$T/shim"; mkdir -p "$SHIM"
  _deadcase() { # $1=tool $2=real-path $3=human name
    total=$((total + 1))
    printf 'kt launch --type=window --cwd=current\n' > "$T/scripts/case.sh"
    rm -f "$SHIM/hits" "$SHIM/grep" "$SHIM/cat" "$SHIM/sed"
    { echo '#!/bin/bash'
      # shellcheck disable=SC2016  # authoring the shim: $a and $@ are read by the SHIM, not by us
      printf 'for a in "$@"; do [ "$a" = "%s" ] && { echo x >> "%s"; exit 3; }; done\n' \
        "$T/scripts/case.sh" "$SHIM/hits"
      printf 'exec %s "$@"\n' "$2"
    } > "$SHIM/$1"
    chmod +x "$SHIM/$1"
    ( PATH="$SHIM:$PATH" CC_PSC_ALLOWLIST="" "$SELF" "$T" >/dev/null 2>&1 )
    local got=$? tries=0
    [ -f "$SHIM/hits" ] && tries="$("$REAL_GREP" -c . "$SHIM/hits")"
    if [ "$got" = 2 ] && [ "$tries" = 3 ]; then pass=$((pass + 1))
    else echo "  selftest FAIL: $3 (want rc=2 after 3 tries, got rc=$got after $tries)" >&2; fi
    rm -f "$SHIM/hits" "$SHIM/grep" "$SHIM/cat" "$SHIM/sed"
  }
  _deadcase grep "$REAL_GREP" "a dead SITE SCAN must be a non-verdict, not a clean file"
  _deadcase cat  "$REAL_CAT"  "a dead FILE READ must be a non-verdict, not an uninstrumented file"
  _deadcase sed  "$REAL_SED"  "a dead CONTEXT READ must be a non-verdict, not an uncovered site"

  if [ "$pass" = "$total" ]; then
    echo "pane-spawn-coverage-lint --selftest: $pass/$total — tier 1 RED on bare kitty/osascript/detach primitives in an uninstrumented file; tier 2 emits a NOTICE (not RED) for a declaration-shape site in an instrumented file; GREEN on both accepted call forms, a targeted detach, --type=background, a caller, and a comment; in a .py file, GREEN on a primitive merely CITED in a one-line or multi-line docstring while a real invocation below one stays RED, and the three deliberate refusals (mixed delimiters, an unbalanced docstring, an inline triple-quoted string) each skip nothing and keep today's verdict; family 1 is detected as ADJACENT ARGV LIST elements too — spaced, compact, --location=, and appended-fragment forms all RED, an instrumented one GREEN, --type=background still not a site, the quoted shell array RED — while prose naming a launch beside a --type= flag stays GREEN, which is the bound a proximity rule would have broken; LOUD on an unreadable root and on a root with nothing to scan; own-scope blocks INSIDE the diff, reports ADVISORY OUTSIDE it, honors set-EMPTY, and stays strict when unset; and each of the three per-file predicates (site scan, file read, context read) is RE-ASKED 3x and then condemns the run to exit 2 rather than degrading into a clean file or a fabricated violation."
    exit 0
  fi
  echo "pane-spawn-coverage-lint --selftest: $pass/$total FAILED — the detector does not discriminate." >&2
  exit 1
fi

[ -d "$ROOT" ] || { echo "pane-spawn-coverage-lint: scan root '$ROOT' is not a directory" >&2; exit 2; }
echo "pane-spawn-coverage-lint: scanning $ROOT (proximity ${WINDOW} lines)" >&2
if [ -n "$ALLOWLIST" ]; then
  printf '%s\n' "$ALLOWLIST" | while IFS= read -r a; do
    [ -n "$a" ] && printf '  allowlisted: %s\n    reason: %s\n' "${a%%::*}" "${a#*::}" >&2
  done
fi
collect_files
if [ "${#PSC_FILES[@]}" -gt 0 ]; then
  psc_memo_arm "${PSC_FILES[@]}" || true
fi
scan_all
if [ "$PSC_MEMO_OK" = "1" ]; then
  echo "pane-spawn-coverage-lint: per-file memo — $PSC_MEMO_HITS verdict(s) carried, $PSC_MEMO_RAN proven fresh." >&2
fi
# NOTHING TO SCAN IS NOT A CLEAN TREE. A scan root that is a directory but holds no bin/, scripts/,
# hooks/ or commands/ file proved nothing about coverage, and reporting OK over it is the same
# silent-green this third state exists to close — one directory typo away from a green gate.
if [ "$seen" -eq 0 ]; then
  echo "pane-spawn-coverage-lint: ⛔ nothing to scan under $ROOT (no bin/, scripts/, hooks/ or commands/ file)" >&2
  exit 2
fi
# CHECKED AFTER the findings are printed and BEFORE any verdict is reported. An unrunnable predicate
# condemns the whole run: the lines above may be real, but the run as a whole has no verdict to give.
if [ "$CHECK_FAILED" -ne 0 ]; then
  echo "pane-spawn-coverage-lint: ⛔ UNUSABLE — a predicate could not RUN (see above); no verdict." >&2
  echo "  This is NOT a coverage report. Re-run when the box is quieter; do not 'fix' any file on it." >&2
  exit 2
fi
if [ "$rc" = 0 ]; then
  echo "pane-spawn-coverage-lint: OK — $checked pane-spawn site(s) across the $PSC_MEMO_RAN file(s) scanned this run ($PSC_MEMO_HITS of $seen carried by the memo); $noticed tier-2 notice(s), $advised advisory (outside this diff)." >&2
else
  echo "pane-spawn-coverage-lint: RED — $flagged of $checked pane-spawn site(s) leave no row." >&2
  echo "  Every spawn must call cc_log_pane_spawn (scripts/lib/pane-spawn-log.sh), or the log's" >&2
  echo "  'no row ⇒ not from this tree' inference is false and §S4.1's ambiguity is back." >&2
fi
exit "$rc"
