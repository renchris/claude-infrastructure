#!/bin/bash
# permission-gate-lint — a per-file RATCHET on UNBOUNDED permission gates on the actuation paths.
#
# WHY: docs/research/inertness-generator-2026-08-07.md §2.3 names the generator. New affirmative-
# permission gates keep being BORN on the deploy/land paths because the blame is asymmetric: an
# advance that breaks something has an author — the gate that let it through — while a REFUSAL that
# strands 104 commits for days has none. Every individual author is therefore correct to add one
# more "only proceed if X holds", and the class reproduces forever.
#
# The scar this is built from: deploy-live.sh's green-stamp gate. `no GREEN stamp among the newest
# N commits ⇒ die` is a perfectly sound predicate that, once the verifier stopped stamping, emitted
# 545 IDENTICAL refusals and froze the live layer for days. Nothing in it was wrong except that it
# had no clock: the refusal was a STANDING STATE, and a standing state generates no event, so no
# one was ever told. The fix (dcf2f11a) did not loosen the predicate — it gave it a BUDGET
# (MAX_LAG_COMMITS / MAX_LAG_HOURS) whose expiry converts the standing state into a degraded
# advance plus a page.
#
# THE RULE (§9, as narrowed after the deploy lane's adversarial reply — the un-narrowed form,
# "no new affirmative-permission predicates", was rejected because some gates must exist):
#
#     No gate on an actuation path may be UNBOUNDED. Every affirmative-permission predicate must
#     carry a finite budget whose expiry converts the standing state into an EVENT — advance+page,
#     escalate, or revert.
#
# WHY THE LINT REQUIRES A DECLARATION AND DOES NOT INFER THE BOUND: "is this gate bounded" is not
# decidable from bash, and the 2026-07-30 panel's finding (§2.7) is precisely that "the expectation
# is never a durable, machine-readable declaration". An inferred bound would be a guess that goes
# stale silently; a declaration is a fact the author states and the next reader can check. So the
# marker is the contract:
#
#     # gate_bounded: MAX_LAG_COMMITS/MAX_LAG_HOURS — expiry authorises the T2 degraded advance
#
# accepted as a TRAILING marker on the refusal, on the contiguous comment block directly above it,
# or on either of those for the ENCLOSING gate condition (a multi-line gate declares its bound
# once, at the gate, not once per exit leg). It MUST carry text after the colon: a bare
# `gate_bounded:` names no budget and is therefore not a declaration, only the appearance of one.
#
# WHY A PER-FILE COUNT AND NOT A PATH ALLOWLIST: a path allowlist would exempt scripts/ship-land.sh
# wholesale — and with it every NEW gate leg anyone adds to it, which is exactly the reproduction
# this exists to stop. The ratchet is `<path> <count>`. The count going UP is the finding ("you
# added a gate; declare its bound"). The count going DOWN is ALSO a finding ("update the ratchet —
# it only shrinks"), mirroring self-path-lint's stuck-entry rule: without that half, a ratchet
# quietly becomes a permanent exemption list.
#
# WHY MEMBERSHIP IS BY GLOB AND NOT BY A FILE LIST: the reproduction mechanism is NEW gates in NEW
# files. A list would have to be edited by the same person adding the gate. A glob puts the next
# scripts/deploy-*.sh in scope on the day it is created, with no one's cooperation.
#
# WHAT IS DELIBERATELY OUT OF SCOPE, because a lint that fires on everything is worth nothing:
#   · `exit 2` — this repo's NON-VERDICT code. A could-not-run is not a permission gate; it already
#     has the right polarity (it refuses to claim anything) and it cannot become a standing state
#     that reads as normal.
#   · usage / unknown-arg / --help errors — an operator typo is an event by construction.
#   · dependency probes (`command -v jq >/dev/null || die`) — the budget for a missing binary is
#     "install it", and the refusal names it. Nothing accumulates behind it.
#   · UNANNOUNCED `exit N` / `return 1` — a bare `[ -n "$sha" ] || return 1` inside a boolean helper
#     is that function's FALSE value, not a refusal. The class here is a gate that STANDS and
#     STRANDS, and every such gate announces itself: 545 refusals were 545 messages. So `exit`/
#     `return` count only where the construct tells someone (`>&2`, a `.page` write, `GATE_RED=1`);
#     `die` and `GATE_RED=1` and `REFUSED` announce by construction and need no such test.
#     Calibrated: without this, postland-verify.sh alone reported 20 findings, every one of them a
#     predicate helper returning false.
#
# Exit: 0 = clean · 1 = violation · 2 = bad usage / unusable scan tree / unrunnable check (LOUD,
# never silent-green — a check that could not RUN has nothing to say about the tree).
#
# Env seams: CC_PERMGATE_SET overrides the actuation globs · CC_PERMGATE_RATCHET overrides the
# embedded ratchet (selftest) · CC_PERMGATE_OWN narrows which findings BLOCK (see the own-scope
# note below).
#
# SC2016 is disabled FILE-WIDE below, which is unusual and deliberate. The detector patterns and
# every --selftest fixture must contain LITERAL shell text — `$STAMPS_DIR`, `$TARGET`, `$0` — and
# must NOT expand it; expansion would substitute this script's own environment for the sample being
# matched and quietly destroy the fixtures, which are lifted verbatim from the real scar. The gate
# runs `shellcheck` bare (ship-land.sh), so at default severity these infos would be a hard RED, and
# per-line directives would outnumber the code. (Note the capital in "ShellCheck" wherever this file
# discusses the tool in prose: a comment whose first word is the lowercase directive name is parsed
# as a MALFORMED DIRECTIVE and aborts analysis of the entire file — memory slug for that scar is
# `shellcheck-prose-comment-aborts-analysis`.)
# shellcheck disable=SC2016
set -uo pipefail

# Resolve $0 THROUGH symlinks before deriving ROOT. ~/.claude/scripts/ is a directory of per-file
# symlinks into this checkout, so invoked through the live layer a bare `dirname "$0"/..` is
# ~/.claude — no scripts/ of the checkout, no tests/, no .git — and this lint would scan the wrong
# tree and report it clean. macOS ships the BSD userland, so there is no `readlink -f`; the manual
# loop is the portable form (bash 3.2 safe). This file must also pass self-path-lint itself.
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

# ── THE ACTUATION SET: files that mutate the ENFORCING stores ──────────────────────────────────────
# The live symlink layer, the trunk pointer, the deployed revision. A gate here can strand the whole
# machine; a gate in a reporting script cannot. Globs, not paths, so a new deploy script is in scope
# the day it is written (see the header). Repo-relative, whitespace-separated.
EMBEDDED_SET="install.sh scripts/deploy-* scripts/*land* scripts/ship-* scripts/postland-*"

# ── the ratchet: <repo-relative-path> <count of undeclared guard-refusals today>. ──────────────────
# SEEDED FROM MEASUREMENT, not from judgment — every count below was produced by running the
# detector in this file over the real tree. A count may only go DOWN, and it goes down by DECLARING
# a bound (or deleting a gate), never by editing this number alone: the lint fails on a stale entry
# exactly as it fails on a new gate.
EMBEDDED_RATCHET="$(cat <<'RATCHET'
install.sh 1
scripts/deploy-live.sh 10
scripts/deploy-parity-assert.sh 1
scripts/desk-land.sh 7
scripts/land-verify.sh 1
scripts/ship-backup-reap.sh 2
scripts/ship-land.sh 17
RATCHET
)"

# ── the detector ──────────────────────────────────────────────────────────────────────────────────
# ONE awk pass per file, deliberately. The precedent lints built this predicate out of piped greps
# and then needed retry machinery, because under fork pressure a `grep` that could not RUN is
# indistinguishable from "no match" — and a ratchet reading 0 for a file that has 10 gates does not
# report a missing check, it reports a count that went DOWN, i.e. it FABRICATES a violation naming a
# good file (memory: named-failure-vs-no-verdict). One fork has no such pipeline, and awk reports "I
# could not run" as a non-zero exit, which is a different signal from "I found nothing".
#
# THE GUARD-REFUSAL SHAPE, and why it needs a real block stack rather than a lookback window:
# a guard-refusal is a refusal reached because an AFFIRMATIVE condition did not hold. In the scar
# itself the affirmative test and the refusal are 18 lines and three nesting levels apart —
#
#     if [ ! -d "$STAMPS_DIR" ]; then          ← the affirmative test, negated
#       if [ "$BOOTSTRAP" -eq 0 ] && ...; then
#         if [ "$AUTO" -eq 1 ]; then
#           if damp_ok "no-stamps-dir:..."; then
#             ...
#             die "no stamps dir (...)"        ← the refusal
#
# — so a flat "nearest opener within N lines" finds `if damp_ok`, which is not negated, and misses
# the gate entirely. Measured: with a lookback window the two real stamps-dir refusals were both
# MISSED; with the stack they both fire. So the pass maintains an if/while/case stack and asks
# whether ANY enclosing condition carries the negated-affirmative shape.
#
# Heredoc bodies and single-quoted printf/echo formats are skipped as DATA. postland-verify.sh
# GENERATES a bisect runner containing `|| exit 125` in a printf format string; a detector that
# matches text ABOUT a refusal reports emitted source as control flow (memory:
# detector-matching-its-own-skill-description). Full-line comments are stripped for the same reason
# — this header alone contains the shape several times over.
perm_gate_refusals() {  # <file> → "line:text" per undeclared guard-refusal; rc 0 = ran, non-0 = could not run
  awk '
    BEGIN { ANN = 6; MAXENC = 6 }   # ANN: how far back an announcement may sit. MAXENC: enclosing depth.
    { n++; line[n] = $0 }
    function is_comment(s) { return s ~ /^[[:space:]]*#/ }
    function is_data(s)    { return s ~ /^[[:space:]]*(printf|echo)[[:space:]]+.\x27/ ||
                                    s ~ /^[[:space:]]*(printf|echo)[[:space:]]+\x27/ }
    # ANNOUNCED — the refusal tells someone. See the header: this is what separates a gate that
    # STANDS and STRANDS from a boolean helper returning false.
    function announces(s) { return (s ~ />&2/ || s ~ /GATE_RED=1/ || s ~ /\.page/) }
    # Scoped OUT: an operator typo and a missing binary are EVENTS by construction, not standing
    # states — nothing accumulates behind either one.
    function scoped_out(s) {
      return (s ~ /unknown arg/ || s ~ /[Uu]sage/ || s ~ /--help/ || s ~ /command -v/)
    }
    # The negated-affirmative shape: this refusal is reached because a test for a GOOD state failed.
    function negated(s) {
      if (s ~ /\[\[?[[:space:]]*![[:space:]]*-/) return 1          # [ ! -d ... ] / [[ ! -f ... ]]
      if (s ~ /-z[[:space:]]/) return 1                            # [ -z "$x" ]
      if (s ~ /\|\|[[:space:]]*die/) return 1
      if (s ~ /\|\|[[:space:]]*exit/) return 1
      if (s ~ /\|\|[[:space:]]*return[[:space:]]+1/) return 1
      if (s ~ /(^|[[:space:]])if[[:space:]]+!/) return 1           # if ! cmd; then
      return 0
    }
    # The declaration must carry TEXT after the colon. A bare `gate_bounded:` names no budget, and a
    # marker that can be satisfied by typing the word is not a contract (self-path-lint case j2 makes
    # the same point about a bare comment: if any comment suppresses, every comment is an exemption).
    function marker(s) { return s ~ /gate_bounded:[[:space:]]*[^[:space:]]/ }
    function decl_above(i,   k) {   # marker on the contiguous comment block directly above line i
      for (k = i - 1; k >= 1; k--) {
        if (line[k] ~ /^[[:space:]]*$/) continue
        if (!is_comment(line[k])) return 0
        if (marker(line[k])) return 1
      }
      return 0
    }
    END {
      depth = 0; hd = ""
      for (i = 1; i <= n; i++) {
        s = line[i]

        # A heredoc body is DATA. Entered on <<WORD / <<-WORD / <<"WORD", left on the delimiter
        # alone on a line. Skipping it also keeps its `if`/`fi` text out of the block stack, which
        # would otherwise desynchronise every enclosing condition below it.
        if (hd != "") { if (s ~ ("^[[:space:]]*" hd "[[:space:]]*$")) hd = ""; continue }
        if (!is_comment(s) && match(s, /<<-?["\x27]?[A-Za-z_][A-Za-z0-9_]*/)) {
          hd = substr(s, RSTART, RLENGTH); sub(/^<<-?["\x27]?/, "", hd)
        }

        if (!is_comment(s) && !is_data(s)) {
          verb = ""
          if (s ~ /(^|[^A-Za-z0-9_.$])die[[:space:]]/) verb = "die"
          else if (s ~ /GATE_RED=1/) verb = "gatered"
          else if (s ~ /REFUSED/) verb = "refused"
          else {
            # exit 2 is the NON-VERDICT code and is not a permission gate. Removed from a COPY
            # first, so a line carrying both `exit 2` and `exit 1` still reports on the exit 1.
            t = s; gsub(/exit[[:space:]]+2([^0-9]|$)/, " ", t)
            if (t ~ /(^|[^A-Za-z0-9_])exit[[:space:]]+[1-9]/) verb = "exit"
            else if (s ~ /(^|[^A-Za-z0-9_])return[[:space:]]+1([^0-9]|$)/) verb = "return"
          }
          if (verb != "" && !scoped_out(s)) {
            ok = 1
            if (verb == "exit" || verb == "return") {
              ann = announces(s)
              for (k = i - 1; k >= 1 && k >= i - ANN; k--) {
                w = line[k]
                if (is_comment(w) || w ~ /^[[:space:]]*$/) continue
                # `GATE_RED=1` immediately above is the SAME refusal leg (the ship-land idiom is
                # two lines: set the flag, then return). Counting both would make one gate read as
                # two, and the ratchet number would then encode the spelling rather than the gate.
                if (w ~ /GATE_RED=1/ && k >= i - 2) { ann = -1; break }
                if (announces(w)) ann = 1
                if (w ~ /^[[:space:]]*(if|elif|while|until|fi|done|\})/) break
              }
              if (ann != 1) ok = 0
            }
            if (ok) {
              guard = negated(s); bounded = (marker(s) || decl_above(i))
              for (e = depth; e > 0 && e > depth - MAXENC; e--) {
                if (cond[e] == "") continue
                if (negated(cond[e])) guard = 1
                if (marker(cond[e]) || decl_above(condln[e])) bounded = 1
                if (scoped_out(cond[e])) { guard = 0; break }
              }
              if (guard && !bounded) printf "%d:%s\n", i, s
            }
          }
        }

        # ── the block stack. cond[] holds the CONDITION text of each open if/elif/while/until (empty
        #    for for/case, which are not conditions), condln[] the line it sits on so the declaration
        #    can be looked for above the GATE and not only above the exit leg.
        if (is_comment(s)) continue
        if (s ~ /^[[:space:]]*(fi|done|esac)([[:space:]]|;|$)/) { if (depth > 0) depth--; continue }
        if (s ~ /^[[:space:]]*(if|while|until|for)[[:space:]]/) {
          if (s ~ /(^|;|[[:space:]])(fi|done)[[:space:]]*$/) continue   # one-liner: opens and closes
          depth++; condln[depth] = i
          cond[depth] = (s ~ /^[[:space:]]*(if|while|until)[[:space:]]/) ? s : ""
          continue
        }
        if (s ~ /^[[:space:]]*case[[:space:]]/) { depth++; condln[depth] = i; cond[depth] = ""; continue }
        if (s ~ /^[[:space:]]*elif[[:space:]]/ && depth > 0) { cond[depth] = s; condln[depth] = i; continue }
      }
    }
  ' "$1"
}

# ── COULD-NOT-CHECK is a THIRD state, never a verdict ─────────────────────────────────────────────
# A run whose detector could not execute has nothing to say about the tree. It must exit 2 — NOT 1,
# which every caller reads as "your tree is dirty", and not 0, which is a silent green. Here the
# stakes are higher than in a boolean lint: a killed detector returns 0 findings, and 0 against a
# ratchet of 10 is a count that went DOWN, which would print "update the ratchet — it only shrinks"
# about a file nobody touched.
CHECK_FAILED=0

# ── OWN-SCOPE — which findings may BLOCK, as distinct from which are REPORTED ─────────────────────
# The rule is "do not ADD an undeclared gate". Enforcing it over the whole actuation set would make
# every lander answerable for every other lander's file, and because trunk is shared that is a
# FLEET-WIDE hard stop (memory: whole-tree-lint-is-a-fleet-wide-hard-stop). Everything is still
# scanned and every finding still printed — one outside the set is LABELLED, never hidden — only the
# EXIT CODE narrows.
#
# THREE states, not two, and `${VAR:-}` cannot express them. ABSENT own-set ⇒ strict, judge the whole
# actuation set (a bare human run, the postland net). PRESENT BUT EMPTY ⇒ "this land changes no file
# in the actuation set", so NOTHING may block — the docs-only land. Presence is carried by ARGUMENT
# COUNT here and by `${CC_PERMGATE_OWN+set}` at the entrypoint.
#
# EXACT-LINE MEMBERSHIP WITHOUT A FORK: wrapping both haystack and needle in newlines makes a plain
# shell pattern do the same exact-line test that `grep -qxF` would, with no process. This lint runs
# inside every land, on a box that routinely sits at load 20+, where forks are the scarce resource.
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

in_own() {  # $1=rel path · $2=own-set text · $3=1 if an own-set was supplied at all
  [ "${3:-0}" = "1" ] || return 0          # no own-set supplied ⇒ everything is own ⇒ strict
  [ -n "$2" ] || return 1                  # supplied but empty ⇒ nothing is own ⇒ nothing blocks
  in_list "$1" "$2"
}

# ── ratchet lookup, fork-free. Sets RATCHET_N; empty ⇒ the path has no line, which is count 0. ─────
# A file in the actuation set with NO ratchet line is treated as 0 — that is what makes a brand-new
# deploy script land-blocked on its first undeclared gate instead of silently grandfathered.
RATCHET_N=""
ratchet_lookup() {  # $1=rel path · $2=ratchet text
  local p c
  RATCHET_N=""
  while read -r p c; do
    case "$p" in ''|'#'*) continue ;; esac
    [ "$p" = "$1" ] || continue
    RATCHET_N="$c"
    return 0
  done <<EOF
$2
EOF
  return 1
}

# ── which files are in the actuation set, under a given root ──────────────────────────────────────
# Globbed, then de-duplicated: `scripts/*land*` and `scripts/ship-*` both match ship-land.sh, and a
# file counted twice would be judged twice and reported twice. Directories and non-existent glob
# expansions are dropped (bash 3.2 has no nullglob here by default, and enabling it globally would
# change behaviour for every other expansion in the file).
ACTUATION_FILES=""
collect_actuation() {  # $1=root · $2=glob set
  local root="$1" g f rel restore_f=0
  local globs=()
  ACTUATION_FILES=""

  # SPLIT THE SET WITH GLOBBING OFF, then expand each glob against the SCAN ROOT. An unquoted `$2`
  # in a for-list undergoes word splitting AND pathname expansion, so with globbing on the set is
  # expanded TWICE: once here against whatever directory the caller happens to be in — which for a
  # land is the repo root, where `scripts/deploy-*` matches — and the resulting REAL repo paths are
  # then looked for under the scan root, where they do not exist. The verdict would then be a
  # function of the caller's CWD: correct from anywhere else, an empty set (exit 2, NON-VERDICT)
  # from the repo root. Measured: it made every --selftest fixture except the two named
  # deploy-live.sh read as "no actuation file exists".
  case "$-" in *f*) restore_f=1 ;; esac
  set -f
  # shellcheck disable=SC2206  # deliberate IFS split of the glob set; globbing is off for exactly this
  globs=($2)
  [ "$restore_f" -eq 1 ] || set +f
  # bash 3.2 errors on "${arr[@]}" for an EMPTY array under `set -u`, so the emptiness test is not
  # cosmetic — without it an empty CC_PERMGATE_SET kills the lint instead of reporting a NON-VERDICT.
  [ "${#globs[@]}" -gt 0 ] || return 0

  for g in "${globs[@]}"; do
    for f in "$root"/$g; do
      [ -f "$f" ] || continue          # also drops a glob that matched nothing (no nullglob here)
      rel="${f#"$root"/}"
      # scripts/*land* and scripts/ship-* both match ship-land.sh; a file counted twice would be
      # judged twice and reported twice, and its ratchet line would have to encode the duplication.
      in_list "$rel" "$ACTUATION_FILES" && continue
      ACTUATION_FILES="$ACTUATION_FILES$rel
"
    done
  done
}

# lint_tree <root> <ratchet-text> [own-set-text] — 0 clean · 1 findings · 2 unusable
lint_tree() {
  local root="$1" ratchet="$2" own="${3:-}" own_scoped=0
  local rel hits cnt want bad=0 other=0 seen=0 stuck=0 l p c
  [ "$#" -ge 3 ] && own_scoped=1
  CHECK_FAILED=0
  [ -d "$root" ] || { echo "permission-gate-lint: ⛔ not a directory: $root" >&2; return 2; }

  collect_actuation "$root" "${CC_PERMGATE_SET:-$EMBEDDED_SET}"
  [ -n "$ACTUATION_FILES" ] || {
    echo "permission-gate-lint: ⛔ no actuation-set file exists under $root" >&2
    echo "  (set: ${CC_PERMGATE_SET:-$EMBEDDED_SET}) — this is a NON-VERDICT, not a clean tree." >&2
    return 2; }

  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    # A DETECTOR MUST NOT SCAN ITSELF. This file necessarily CONTAINS the shapes it hunts — the
    # header quotes the real scar and the --selftest fixtures replay it verbatim, because a control
    # that hand-approximates the artifact passes vacuously (memory: control-must-replay-the-real-
    # artifact). Today no actuation glob reaches it; the skip is here so widening CC_PERMGATE_SET
    # cannot silently turn the lint into its own first violation. --selftest is what validates it.
    case "${rel##*/}" in permission-gate-lint.sh) continue ;; esac
    seen=$((seen + 1))

    hits="$(perm_gate_refusals "$root/$rel")" || {
      CHECK_FAILED=1
      echo "permission-gate-lint: ⛔ detector could not RUN for $rel" >&2
      continue
    }
    cnt=0
    if [ -n "$hits" ]; then
      while IFS= read -r l; do
        [ -n "$l" ] && cnt=$((cnt + 1))
      done <<EOF
$hits
EOF
    fi

    ratchet_lookup "$rel" "$ratchet"
    want="${RATCHET_N:-0}"
    case "$want" in ''|*[!0-9]*) want=0 ;; esac

    if [ "$cnt" -gt "$want" ]; then
      if in_own "$rel" "$own" "$own_scoped"; then
        printf '  PERM-GATE %s — %s undeclared guard-refusal(s), ratchet allows %s\n' "$rel" "$cnt" "$want"
        printf '%s\n' "$hits" | sed 's/^/              /'
        bad=$((bad + 1))
      else
        printf '  permgate? %s (%s > %s, NOT in your diff — advisory, not blocking)\n' "$rel" "$cnt" "$want"
        other=$((other + 1))
      fi
    elif [ "$cnt" -lt "$want" ]; then
      if in_own "$rel" "$own" "$own_scoped"; then
        printf '  RATCHET   %s now has %s undeclared gate(s), not %s — lower its ratchet line\n' "$rel" "$cnt" "$want"
        stuck=$((stuck + 1))
      else
        printf '  ratchet?  %s improved but still ratcheted at %s (NOT in your diff — advisory)\n' "$rel" "$want"
        other=$((other + 1))
      fi
    fi
  done <<EOF
$ACTUATION_FILES
EOF

  # A ratchet line for a path that is no longer in the actuation set is the same stuck entry in its
  # other spelling — the file was renamed or deleted and the allowance survived it. Left unchecked,
  # a rename is a free reset of the count to zero-with-a-grandfathered-line.
  while read -r p c; do
    case "$p" in ''|'#'*) continue ;; esac
    [ -n "$c" ] || continue
    in_list "$p" "$ACTUATION_FILES" && continue
    if in_own "$p" "$own" "$own_scoped"; then
      printf '  RATCHET   %s is ratcheted at %s but is not in the actuation set — delete its line\n' "$p" "$c"
      stuck=$((stuck + 1))
    else
      printf '  ratchet?  %s is ratcheted but absent (NOT in your diff — advisory)\n' "$p"
      other=$((other + 1))
    fi
  done <<EOF
$ratchet
EOF

  [ "$seen" -gt 0 ] || { echo "permission-gate-lint: ⛔ no scannable actuation file under $root" >&2; return 2; }
  [ "$other" -eq 0 ] || echo "permission-gate-lint: $other pre-existing item(s) NOT in your diff — reported, not blocking (own-scope)."

  # Checked AFTER the own-scope report so a killed detector cannot masquerade as a clean own-scope
  # pass: own-scope narrows WHICH findings block, it never makes an unrunnable check trustworthy.
  if [ "$CHECK_FAILED" -ne 0 ]; then
    echo "permission-gate-lint: ⛔ UNUSABLE — the detector failed to run (see above); no verdict." >&2
    echo "  This is NOT a finding report, and the counts above are NOT a ratchet drift. Re-run when" >&2
    echo "  the box is quieter; do not 'fix' any file or edit any ratchet line on the strength of it." >&2
    return 2
  fi

  if [ "$bad" -gt 0 ]; then
    echo "permission-gate-lint: ⛔ $bad actuation file(s) above gained an UNBOUNDED permission gate."
    echo "  Why it matters: a gate that refuses is a STANDING STATE, and a standing state generates no"
    echo "  event, so nobody is told. deploy-live's green-stamp gate emitted 545 identical refusals and"
    echo "  froze the live layer for days; every one of them read as normal (inertness-generator §2.3)."
    echo "  Fix — give the gate a BUDGET whose expiry converts the standing state into an event"
    echo "  (advance+page, escalate, or revert), then DECLARE it so the next reader can check it:"
    echo "      # gate_bounded: MAX_LAG_COMMITS/MAX_LAG_HOURS — expiry authorises a degraded advance"
    echo "      if [ -z \"\$TARGET\" ]; then die \"...\"; fi"
    echo "  The marker is accepted as a trailing comment on the refusal, on the comment block directly"
    echo "  above it, or on either for the ENCLOSING gate condition (declare a multi-line gate once)."
    echo "  It MUST carry text after the colon — a bare \`gate_bounded:\` names no budget."
    echo "  scripts/deploy-live.sh:377-398 + 457-490 is the worked example (dcf2f11a): the predicate"
    echo "  did not loosen, it gained a clock."
  fi
  if [ "$stuck" -gt 0 ]; then
    echo "permission-gate-lint: ⛔ $stuck ratchet line(s) above are stale — the ratchet only shrinks."
    echo "  Fix: lower (or delete) them in EMBEDDED_RATCHET in $SELF. A ratchet that is not re-tightened"
    echo "  after an improvement is a permanent exemption list wearing a ratchet's name."
  fi
  [ $((bad + stuck)) -eq 0 ] || return 1
  echo "permission-gate-lint: clean — $seen actuation file(s) scanned; no new undeclared permission gate."
  return 0
}

# ── --selftest: every case proves a RED path FIRES or a GREEN path does NOT, both directions ───────
# A detector is only worth its clean verdict if it can be shown to discriminate, and the two controls
# that matter are the REAL artifact before and after the real fix — a hand-approximated control
# passes vacuously (memory: control-must-replay-the-real-artifact).
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  fails=0
  # mk <case> <relpath-under-case> <body>
  mk() { mkdir -p "$d/$1/$(dirname "$2")"; { printf '#!/bin/bash\n'; printf '%s\n' "$3"; } > "$d/$1/$2"; }

  # ── THE RED CONTROL: the real pre-fix gate, lifted verbatim from 0c393936:scripts/deploy-live.sh.
  #    Two gates, both UNBOUNDED. The second one is the scar itself: once the verifier stopped
  #    stamping it emitted 545 identical refusals and froze the live layer for days. Note that the
  #    affirmative test and the refusal are 18 lines and four nesting levels apart — this fixture is
  #    what proves the block stack is doing real work, because a lookback window misses both.
  mk unbounded scripts/deploy-live.sh 'TARGET=""; UNSTAMPED=0; BANNER=""
if [ ! -d "$STAMPS_DIR" ]; then
  # The verification net is not active yet. Deploying is a decision, not a default.
  if [ "$BOOTSTRAP" -eq 0 ] && [ "$FORCE" -eq 0 ]; then
    if [ "$AUTO" -eq 1 ]; then
      if damp_ok "no-stamps-dir:$STAMPS_DIR"; then
        mkdir -p "$PAGES_DIR" 2>/dev/null || true
        die "no stamps dir ($STAMPS_DIR) — the post-land verification net is not active. Run 14-land-pipeline-v2-activate.sh."
      fi
      exit 1   # same refusal, inside the damp window: an honest non-zero, silently
    fi
    die "no stamps dir ($STAMPS_DIR) — the post-land verification net is not active. Re-run with --bootstrap to deploy origin/main UNSTAMPED."
  fi
  TARGET="$TIP_SHA"
else
  if [ -z "$TARGET" ]; then
    if [ "$AUTO" -eq 1 ] && ! damp_ok "no-green:$STAMPS_DIR"; then exit 1; fi
    die "no GREEN stamp among the newest $SCAN_N commits of origin/main — nothing is safe to deploy (verifier: $POSTLAND_BIN)"
  fi
fi'

  # ── THE GREEN CONTROL: the FIX (dcf2f11a), lifted from scripts/deploy-live.sh:377-398 + 445-510,
  #    with the bound DECLARED. Same refusal, same `[ -z "$TARGET" ]` predicate, same `die` — the only
  #    difference is that a budget now exists and is stated. This is the case that proves the rule
  #    keys on DECLAREDNESS and not merely on the absence of a refusal; without it the lint could be
  #    passing simply because it stopped detecting anything.
  mk declared scripts/deploy-live.sh 'LAG_COMMITS="$(g rev-list --count "$HEAD_SHA..origin/main" 2>/dev/null || echo 0)"
LAG_TRIP=""
if [ "$LAG_COMMITS" -gt "$MAX_LAG_COMMITS" ]; then
  LAG_TRIP="$LAG_COMMITS commit(s) behind trunk (budget $MAX_LAG_COMMITS)"
elif [ "$LAG_HOURS" -gt "$MAX_LAG_HOURS" ]; then
  LAG_TRIP="${LAG_HOURS}h since the live commit was authored (budget ${MAX_LAG_HOURS}h)"
fi

# gate_bounded: CC_DEPLOY_MAX_LAG_COMMITS (25) / CC_DEPLOY_MAX_LAG_HOURS (6) — whichever trips first
# authorises the T2 degraded advance to the newest NOT-RED commit, with a banner naming the clock.
# The standing state therefore expires into an EVENT rather than accumulating (dcf2f11a).
if [ -z "$TARGET" ]; then
  if [ "$LAG_COMMITS" -gt 0 ] && [ -n "$LAG_TRIP" ]; then
    case "$DEGRADE" in
      off|OFF|0|no|NO|false|FALSE) : ;;
      *) TARGET="$(newest_not_red)" ;;
    esac
  fi
  if [ -z "$TARGET" ]; then
    if [ "$AUTO" -eq 1 ] && ! damp_ok "$RKEY"; then exit 1; fi
    die "$RMSG — nothing is safe to deploy (verifier: $POSTLAND_BIN)"
  fi
fi'

  # ── the marker must be a CONTRACT, not a word ──────────────────────────────────────────────────
  # (c) an ordinary comment above the gate must NOT suppress it, or every commented line in the repo
  #     becomes an exemption (the sibling failure self-path-lint case j2 exists to prevent).
  mk bare_comment scripts/deploy-x.sh '# The verification net is not active yet, so we refuse.
if [ ! -d "$STAMPS_DIR" ]; then
  die "no stamps dir ($STAMPS_DIR) — the post-land verification net is not active."
fi'
  # (d) …and a marker with NOTHING after the colon names no budget, so it must not suppress either.
  mk empty_marker scripts/deploy-x.sh '# gate_bounded:
if [ ! -d "$STAMPS_DIR" ]; then
  die "no stamps dir ($STAMPS_DIR) — the post-land verification net is not active."
fi'
  # (e) the trailing placement, on the refusal itself.
  mk marker_trailing scripts/deploy-x.sh 'if [ ! -d "$STAMPS_DIR" ]; then
  die "no stamps dir"   # gate_bounded: 6h of absence escalates to a page and an unstamped advance
fi'

  # ── the scope-outs. Each is a refusal that is NOT a permission gate; if any of them counts, the
  #    lint fires on ordinary error handling and nobody will keep it on.
  mk nonverdict scripts/deploy-x.sh 'if [ ! -f "$MANIFEST" ]; then
  echo "cannot read $MANIFEST" >&2
  exit 2
fi'
  mk usage scripts/deploy-x.sh 'case "$1" in
  *) printf "deploy-live: unknown arg %s\n" "$1" >&2; exit 1 ;;
esac'
  mk depprobe scripts/deploy-x.sh 'command -v jq >/dev/null 2>&1 || die "jq is required and is not on PATH"'
  # A boolean helper returning false is not a refusal — it is that function is FALSE value. Without
  # this scope-out postland-verify.sh alone reported 20 such lines (measured).
  mk predicate scripts/deploy-x.sh 'is_green() {
  [ -n "$1" ] || return 1
  [ -f "$STAMPS/$1.json" ] || return 1
  return 0
}'

  # ── jurisdiction: a file OUTSIDE the actuation set carries the shape and must not be scanned. It
  #    is placed beside a real actuation file so the case cannot pass merely by finding nothing.
  mkdir -p "$d/outside/scripts"
  printf '#!/bin/bash\nif [ ! -d "$X" ]; then die "no X"; fi\n' > "$d/outside/scripts/render-census.sh"
  printf '#!/bin/bash\ntrue\n' > "$d/outside/scripts/deploy-ok.sh"

  # The reported case count is COUNTED, never typed: a hardcoded total silently drifts as cases are
  # added, and a selftest that misreports its own coverage is the last place to keep a stale number.
  checks=0
  expect() {  # <want-rc> <got-rc> <failure message>
    checks=$((checks + 1))
    [ "$2" -eq "$1" ] || { echo "SELFTEST FAIL: $3"; fails=1; }
  }
  red()   { lint_tree "$d/$1" "${2-}" >/dev/null 2>&1; expect 1 "$?" "$3"; }
  green() { lint_tree "$d/$1" "${2-}" >/dev/null 2>&1; expect 0 "$?" "$3"; }

  red   unbounded  "" "the REAL pre-fix unbounded green-stamp gate (0c393936) did not go RED — the detector does not see the scar it exists for"
  green declared   "" "the REAL fix (dcf2f11a) with its bound DECLARED went RED — the rule is keying on the presence of a refusal, not on declaredness"
  red   bare_comment "" "an ordinary comment above the gate suppressed it — any comment now works as an exemption"
  red   empty_marker "" "a bare \`gate_bounded:\` with no budget after the colon suppressed — the marker is satisfiable by typing the word"
  green marker_trailing "" "a trailing gate_bounded: marker on the refusal did not suppress"
  green nonverdict "" "an \`exit 2\` NON-VERDICT was counted as a permission gate"
  green usage      "" "an unknown-arg usage error was counted as a permission gate"
  green depprobe   "" "a \`command -v\` dependency probe was counted as a permission gate"
  green predicate  "" "a boolean helper returning 1 was counted as a permission gate"
  green outside    "" "a file OUTSIDE the actuation set was scanned"

  # ── THE VERDICT MUST NOT BE A FUNCTION OF THE CALLER'S CWD ─────────────────────────────────────
  # This is a scar from building the lint, not a hypothetical: `for g in $SET` glob-expanded the
  # actuation set against the CURRENT directory before it was ever joined to the scan root, so from
  # the repo root — which is exactly where a land runs — the globs became real repo paths, none of
  # which exist under a fixture, and every fixture read as an empty set (exit 2, a NON-VERDICT). It
  # is the worst available polarity: correct from a worktree, silently unusable from the one place
  # it is enforced. Both directions are pinned, from the one CWD where the globs DO match.
  ( cd "$ROOT" && lint_tree "$d/bare_comment" "" >/dev/null 2>&1 ); expect 1 "$?" "run from the repo root, a RED fixture did not go RED — the actuation set is being globbed against the caller's CWD"
  ( cd "$ROOT" && lint_tree "$d/nonverdict" "" >/dev/null 2>&1 ); expect 0 "$?" "run from the repo root, a GREEN fixture did not go GREEN — the actuation set is being globbed against the caller's CWD"

  # ── the ratchet, in all three directions. Without the DOWN half an allowlist is permanent.
  #    `unbounded` measures 3 undeclared gates; the counts below are relative to that.
  green unbounded "scripts/deploy-live.sh 3"  "the EXACT ratchet count did not go GREEN"
  red   unbounded "scripts/deploy-live.sh 2"  "a count ABOVE the ratchet did not go RED — a new gate lands unnoticed"
  red   unbounded "scripts/deploy-live.sh 4"  "a count BELOW the ratchet did not go RED — the ratchet is not shrinking"
  # A ratchet line naming a path that is not in the actuation set is the same stale entry after a
  # rename, and a rename must not be a free reset of the count.
  red   declared  "scripts/gone-away.sh 2"    "a ratchet line for a path outside the actuation set did not go RED"

  # ── the REAL tree with the REAL ratchet. A stale ratchet is caught here too, and its two failure
  #    codes must stay APART: 1 is a VERDICT about the tree, 2 is a NON-VERDICT that says nothing
  #    whatever about the ratchet (memory: gate-never-ran-vs-gate-red).
  lint_tree "$ROOT" "$EMBEDDED_RATCHET" >/dev/null 2>&1; rc_real=$?
  checks=$((checks + 1))
  case "$rc_real" in
    0) ;;
    2) echo "SELFTEST FAIL: could not scan $ROOT — a NON-VERDICT (bad ROOT? no actuation files?), NOT a stale ratchet"; fails=1 ;;
    *) echo "SELFTEST FAIL: the embedded ratchet is stale — re-measure and update EMBEDDED_RATCHET"; fails=1 ;;
  esac

  # ── LOUD on an unusable scan tree, in both its forms.
  lint_tree "$d/nope" "" >/dev/null 2>&1; expect 2 "$?" "a missing scan root did not exit 2 (LOUD)"
  mkdir -p "$d/empty/docs"
  lint_tree "$d/empty" "" >/dev/null 2>&1; expect 2 "$?" "a root with NO actuation file did not exit 2 (LOUD) — an empty set is a NON-VERDICT, not a clean tree"

  # ── OWN-SCOPE: both directions, because a scope that can only PASS is not a scope.
  lint_tree "$d/unbounded" "" "scripts/other.sh" >/dev/null 2>&1; expect 0 "$?" "a finding OUTSIDE the own-set blocked (own-scope not applied)"
  lint_tree "$d/unbounded" "" "scripts/deploy-live.sh" >/dev/null 2>&1; expect 1 "$?" "a finding INSIDE the own-set did not block — own-scope disabled the rule"
  lint_tree "$d/unbounded" "scripts/deploy-live.sh 4" "scripts/other.sh" >/dev/null 2>&1; expect 0 "$?" "a stale ratchet entry OUTSIDE the own-set blocked"
  lint_tree "$d/unbounded" "scripts/deploy-live.sh 4" "scripts/deploy-live.sh" >/dev/null 2>&1; expect 1 "$?" "a stale ratchet entry INSIDE the own-set did not block"
  # THE DOCS-ONLY CASE — an own-set SUPPLIED BUT EMPTY means "I change no actuation file", so nothing
  # may block. The next two differ ONLY in arity, so together they prove the three states are really
  # distinguished and that `${3:-}` has not collapsed two of them.
  lint_tree "$d/unbounded" "" "" >/dev/null 2>&1; expect 0 "$?" "an EMPTY own-set blocked — set-empty collapsed into unset, docs-only lands hard-stop"
  lint_tree "$d/unbounded" "" >/dev/null 2>&1; expect 1 "$?" "an ABSENT own-set did not block — strict default lost"
  # entrypoint-level parity for the same distinction, via the real env seams.
  ( unset CC_PERMGATE_OWN; CC_PERMGATE_RATCHET="" "$SELF" "$d/unbounded" >/dev/null 2>&1 ); expect 1 "$?" "CC_PERMGATE_OWN unset did not block at the entrypoint"
  ( CC_PERMGATE_OWN="" CC_PERMGATE_RATCHET="" "$SELF" "$d/unbounded" >/dev/null 2>&1 ); expect 0 "$?" "CC_PERMGATE_OWN set-but-empty blocked at the entrypoint"

  # ── COULD-NOT-CHECK is a non-verdict, not a verdict. Shadowing awk in a subshell reproduces what
  #    fork exhaustion (or another session's unscoped pkill) does to the detector. The contract is
  #    exit 2 and NO named finding — and here the stakes are sharper than in a boolean lint: a killed
  #    detector returns 0 hits, and 0 against a ratchet of 10 would print "the ratchet only shrinks"
  #    about a file nobody touched, sending someone to LOWER a real allowance on the strength of a
  #    check that never ran.
  # ShellCheck's SC2329 reachability follows one level of function indirection from the shadow's
  # scope; here awk is two hops away (lint_tree → perm_gate_refusals → awk), which is the "or ignored
  # if invoked indirectly" case the check itself names — and that indirection IS the point of the
  # fixture. Disabled per-construct rather than file-wide, so a genuinely dead function elsewhere in
  # this file would still be reported.
  # shellcheck disable=SC2329
  ( awk() { return 2; }
    out="$(lint_tree "$d/unbounded" "scripts/deploy-live.sh 3" 2>&1)"; rc=$?
    [ "$rc" -eq 2 ] || { echo "SELFTEST FAIL: an unrunnable detector did not exit 2 (got $rc) — a killed check must never be a verdict"; exit 1; }
    case "$out" in
      *PERM-GATE*) echo "SELFTEST FAIL: an unrunnable detector still fabricated a PERM-GATE finding"; exit 1 ;;
      *RATCHET*)   echo "SELFTEST FAIL: an unrunnable detector reported a ratchet drift — 0 hits is not an improvement"; exit 1 ;;
    esac
    exit 0
  ); expect 0 "$?" "an unrunnable detector was treated as a verdict (see the message above)"
  # …and it stays a non-verdict WITH an own-set supplied: own-scope narrows which findings BLOCK, it
  # never makes an unrunnable check trustworthy. Guards the composition of the two mechanisms.
  # shellcheck disable=SC2329  # same indirect invocation as the case above
  ( awk() { return 2; }
    lint_tree "$d/unbounded" "" "scripts/deploy-live.sh" >/dev/null 2>&1
    [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: an unrunnable detector under own-scope did not exit 2"; exit 1; }
    exit 0
  ); expect 0 "$?" "an unrunnable detector under own-scope was treated as a verdict"

  if [ "$fails" -eq 0 ]; then
    echo "permission-gate-lint --selftest: $checks/$checks — RED on the REAL pre-fix unbounded gate (0c393936, the 545-refusal scar), on a bare comment used as an exemption, on a \`gate_bounded:\` with no budget after it, on a count above AND below the ratchet, and on a ratchet line outside the actuation set; GREEN on the REAL fix (dcf2f11a) with its bound DECLARED — same predicate, same die — on a trailing marker, on exit 2, on usage errors, on dependency probes, on boolean helpers, on files outside the actuation set, and on the real tree with the real ratchet; LOUD on a missing root and on an empty actuation set; own-scope blocks INSIDE / advises OUTSIDE for both finding kinds across all three arity states; NON-VERDICT on an unrunnable detector (with and without an own-set), with no fabricated finding and no fabricated ratchet drift."
    exit 0
  fi
  echo "permission-gate-lint --selftest: FAILED ($checks case(s) run) — the detector does not discriminate."
  exit 1
fi

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  # The header block, DERIVED rather than a hardcoded line range: every edit to the header would
  # otherwise silently truncate --help mid-sentence.
  awk 'NR > 1 { if ($0 !~ /^#/) exit; if ($0 ~ /^# *shellcheck /) next; sub(/^# ?/, ""); print }' "$SELF"
  exit 0
fi

# CC_PERMGATE_OWN — newline-delimited repo-relative paths the caller is answerable for. UNSET ⇒
# strict whole-set blocking. SET (including set to EMPTY) ⇒ own-scope, where empty legitimately means
# "I change no actuation file, so nothing may block me". `+set` is the only test that separates
# those; `${CC_PERMGATE_OWN:-}` would collapse them and silently reinstate the hard stop for
# precisely the docs-only land that motivates own-scope.
if [ -n "${CC_PERMGATE_OWN+set}" ]; then
  lint_tree "${1:-$ROOT}" "${CC_PERMGATE_RATCHET-$EMBEDDED_RATCHET}" "$CC_PERMGATE_OWN"
else
  lint_tree "${1:-$ROOT}" "${CC_PERMGATE_RATCHET-$EMBEDDED_RATCHET}"
fi
exit $?
