#!/bin/bash
# shellcheck disable=SC2016  # file-wide: single quotes are load-bearing here in two places, and
# expanding either would destroy what the file is for. The RED guidance prints the literal
# `def cell(ph): …` an author must paste into their jq — substituting this shell's values into a
# prescribed fix is how a lint hands out a broken remedy. And every --selftest fixture body is
# written VERBATIM into a .sh file, where `${maybe:--}`, `$1` and `$(printf …)` must arrive
# unexpanded or the case asserts nothing about the recognizer it is meant to exercise.
# tsv-pad-lint.sh — the CHOKEPOINT arm of the TSV field-collapse convention (backlog e146d30857b4).
#
# WHY THE CLASS MATTERS: tab is an IFS-*whitespace* character, so `IFS=<tab> read` collapses a RUN
# of delimiters into one. An empty field therefore does NOT produce an empty variable — it shifts
# every later field one position LEFT, silently, with exit status 0. The read side cannot be
# repaired; the producer has to guarantee a non-empty cell AT THE EMITTER. Mechanism, and the two
# corrections to the original finding: docs/research/TSV_FIELD_COLLAPSE_2026-07-25.md, locked by
# tests/tsv-field-collapse.bats §1.
#
# WHY A CHOKEPOINT AND NOT (ONLY) A SUITE — this is the entire reason the file exists.
# tests/tsv-field-collapse.bats §3 has asserted this convention repo-wide since 2026-07-25, and it
# has re-reddened with a COMPLETELY DIFFERENT offender set every time:
#   2026-07-31  68e17e2a discharged its six named files (bin/cc-reaper, hooks/validate-bash.sh,
#               scripts/dispatch-acceptance.sh, scripts/scratchpad-reaper.sh,
#               scripts/store-bounds-census.sh, scripts/terminal-bench.sh).
#   by 2026-08-07  six DIFFERENT files had landed unpadded — bin/cc-queue,
#               scripts/assignee-pane-residency.sh, scripts/branch-reaper.sh,
#               scripts/terminal-bench.sh, scripts/thrash-block-recover.sh,
#               scripts/unattended-path-lint.sh — five of them AFTER that discharge.
#   2026-08-10  those were discharged in turn, and the live offenders were TWO MORE that appear in
#               no prior evidence: bin/cc-offload (an empty .state did not merely shift the row, it
#               CRASHED `cc-offload ls` on an unbound variable) and
#               scripts/backlog-consolidation-trigger.sh (an empty .project rendered the TITLE in
#               the project column with a blank title after it).
#
# The suite blocked none of those lands, and the reason is structural, not bad luck.
# scripts/gate-select.sh maps changed files to suites, and its `cited_only` rule (:280) requires a
# DIRECT edge's evidence to live in the suite's EXECUTABLE text — deliberately, because a path a
# suite merely CITES in a comment is not a functional dependency. The §3 guard names files ONLY
# inside its exemption heredoc, so a brand-new script is named nowhere: the suite is not a direct
# suite of the land that adds it, its failure is exonerable-as-adjacent, and the land goes through.
# Per-file remediation is therefore a treadmill that structurally cannot reach the next author, and
# the offender set turning over completely between reds is the measurement that says so.
# (memory: enforcement-must-live-at-the-chokepoint — a lint enforced solely by its own suite is
# post-hoc DETECTION; the chokepoint is the land itself.)
#
# THE RULE. A file under bin/ hooks/ scripts/ that contains an `IFS=<tab> read` is a violation
# unless it makes a deliberate, greppable statement that its author considered the collapse:
#   (1) it PADS at its own emitter        — `def cell(ph):` / `def cell:` / a python `_cell`
#   (2) it UN-PADS what an upstream emitter padded — `session_index_unpad` / `unpad()` / `TSV_PAD`
#   (3) another spelling of the same guarantee — `norm()`/`dash()` (awk right-fills to n fields),
#       or `${var:--}` (writes "-" for an absent cell and compares back to "-" on read)
#   (4) it is named in the reviewed exemption table below, WITH a reason
# Clauses 1-3 are the §3 guard's recognizer verbatim; clauses (3)'s two spellings were both flagged
# here first and turned out to be correct — the recognizer was the thing wrong, so it accepts any
# emitter that provably fills empties rather than enforcing one house style.
#
# THE RATCHET RUNS BOTH WAYS: an exemption naming a file that no longer exists, no longer reads TSV,
# or carries no reason is itself a violation. An exemption list that only grows is an amnesty.
#
# OWN-SCOPE — identical contract to test-afunix-path-lint / test-walltime-lint / git-identity-lint.
# A whole-tree blocking lint at the land gate is a FLEET-WIDE hard stop (an author refused over a
# file they never touched), and the blast radius here is every author's land gate. THREE states:
# own-set ABSENT ⇒ strict whole-tree; SET-BUT-EMPTY ⇒ "I change none of these" ⇒ nothing blocks;
# SET ⇒ block on those only, everything else advisory. `${VAR:-}` cannot express that, so presence
# rides on argument count here and on `${CC_TSVPAD_OWN+set}` at the entry point.
# Own-matching accepts an exact repo-relative path OR a bare basename, and the width of the BARE
# form is deliberate: too-narrow matching reports a file the author just added as "not in your diff
# — advisory" and the land goes through, which is precisely the hole this lint exists to close.
# Too-wide costs a loud, nameable refusal. (memory: gate-default-decides-failure-direction)
# A PATHED entry is NOT widened, though — see in_own's header.
#
# KNOWN LIMITS, stated rather than hidden. It scans bin/ hooks/ scripts/ only — the same population
# the §3 guard scans; a .bats fixture reading TSV is test code and out of scope. It keys on the
# literal `IFS=<tab> read` spelling, so `IFS="$(printf '\t')" read` and friends are invisible (the
# corpus has no such site — checked 2026-08-10). And a padded emitter is not proof the padding is
# CORRECT: only tests/tsv-field-collapse.bats §2's per-site regressions assert that.
#
# Exit: 0 = clean · 1 = violation (blocking, own-scoped) · 2 = NON-VERDICT — bad usage, no scan dir,
# or a scan that matched nothing at all. 2 is never dressed up as a claim about the tree.
#
# Env seams: CC_TSVPAD_OWN scopes which violations may BLOCK (see OWN-SCOPE) ·
# CC_TSVPAD_EXEMPTIONS overrides the embedded table (the selftest's seam) ·
# CC_TSVPAD_DIRS overrides the scanned dirs (default "bin hooks scripts").
set -uo pipefail

SELF="$0"
while [ -L "$SELF" ]; do
  _link="$(readlink "$SELF")"
  case "$_link" in
    /*) SELF="$_link" ;;
    *)  SELF="$(dirname "$SELF")/$_link" ;;
  esac
done
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"

# THE MARKER IS ASSEMBLED, NOT WRITTEN. Spelled literally, this file would match its OWN scan — it
# is a scanner, not a reader — and the fix for that must not be a self-exemption: a guard that
# exempts itself is one edit away from exempting the thing it guards
# (memory: guard-refusal-fires-on-its-own-harness). printf builds the exact 14 bytes
# `IFS=$'<backslash>t' read` while this source line contains no contiguous copy of them. The
# WHERE THE ASSEMBLY IS ACTUALLY CHECKED, stated precisely because the obvious answer is wrong:
# NOT by --selftest. Its fixtures are written FROM this same variable, so a corrupted marker
# produces fixtures carrying the corruption and every case still passes — measured, not feared: a
# mutant spelling this `IFS=$'QQt' read` scored a clean 19/19. A control generated by its own
# subject is vacuous (memory: control-must-replay-the-real-artifact, gate-must-not-key-on-its-own-
# signal). What DOES catch it is the empty-scan rule in lint_tree: against a real tree a broken
# marker matches nothing, and "nothing" is returned as a NON-VERDICT (exit 2), never as clean — the
# same mutant exits 2 there. tests/tsv-field-collapse.bats pins it independently, comparing this
# file's census against the suite's OWN literal grep.
TSV_READ_MARK="$(printf 'IFS=$%s\\t%s read' "'" "'")"

# ── the reviewed exemption table. Format: <path>|<reason>. ONLY EVER DELETE LINES. ───────────────
# Files that read TSV with `IFS=<tab> read` but legitimately carry no padding def. Each needs a
# REASON, and a reviewed exemption is cheaper than re-deriving the analysis at every future edit.
#
# Moved here VERBATIM from tests/tsv-field-collapse.bats (2026-08-10) so that the recognizer and the
# table have exactly ONE home. The suite now drives this file instead of re-implementing it: two
# auditors over one population that can disagree is its own defect class
# (memory: sibling-auditors-must-share-the-state-model), and the suite is where the drift would have
# been invisible — it would still have gone green while the gate judged something else.
tsv_exemptions() {
  cat <<'EOF'
bin/cc-blockers|already padded on feat/relogin-observability (0dac237) — that stream owns the file; a second fix here would only conflict
bin/cc-reaper|all three reads take pid<TAB>lstart[<TAB>etime] rows whose cell 1 is structurally non-empty: the .daemon writer (hooks/lead-crash-watchdog.sh:1155) prints "$!", and wd_daemon_table's awk builds cell 2 from a format string with LITERAL spaces between lstart's five components, so that cell holds at least four spaces even when every component is empty — and space is not in IFS here, so it does not collapse. lstart/etime are last
hooks/session-index-sweep.sh|consumer only; its producer (session_index_extract_enriched) pads at the emitter. The file is being rewritten on fix/infra-perfection, which deletes both reads
hooks/validate-bash.sh|both non-final cells come from rm_argv_scan's python emitter (hooks/lib/is-true-flag.sh, `"%d\t%d\t%s" % (1 if recursive else 0, 1 if force else 0, safe)`), so they are always exactly "0" or "1" — a %d of a bool cannot be empty. The only variable-content cell is the rm target, which is LAST. Both call sites share that one producer
scripts/lead-deathwatch.sh|reads a watch-file and the kqueue helper's output — neither is a jq producer, and both emit fixed-arity rows
scripts/desk-recycle-invariant.sh|resolve_desk guarantees all three cells non-empty before printing (cfg falls back to the CC default root; an empty cwd returns 1)
scripts/relogin-probes/e1-concurrent-logins.sh|producer REFUSES on an empty identity field rather than emitting one (all four are required), so non-empty is guaranteed at the source instead of padded — the same discharge as desk-recycle-invariant above
scripts/cloud-ceiling-probe.sh|both reads (:339 control, :376 ramp) consume fire_one, whose every exit emits a 2-cell row whose cell 1 is an OUTCOME LITERAL: classify_outcome returns exactly one of created / refused-quota / refused-other (:187-192, three unconditional printfs, no empty-reachable branch), and fire_one's two early exits print the literal `refused-other\t…` themselves (:258, :259). So cell 1 cannot be empty at any of the three sources. Cell 2 is the free-text message and is LAST, where an empty value assigns "" without shifting anything — and `read -r oc msg` has exactly two vars, so msg absorbs any tabs the message itself contains. Same discharge as e1-concurrent-logins and store-bounds-census above: non-empty guaranteed at the source rather than padded
scripts/scratchpad-reaper.sh|the jq producer CAN emit an empty cell ([(.pid // ""), (.session_id // "")]), but both cells are existence-TESTED on the line after the read ([ -n "$rpid" ] && [ -n "$rsid" ] || continue) — so an empty cell discards the row identically with or without the shift, and the reaper's live-set cannot change. Keyed on that test, not on proximity
scripts/store-bounds-census.sh|parse_manifest REFUSES to emit an OK row when any of its four fields is empty — it prints a BAD row instead ([ -z "${g:-}" ] || [ -z "${cap:-}" ] || … → BAD), so no OK row can carry an empty cell. The BAD rows are 2-field and only counted, never destructured. Same discharge as e1-concurrent-logins above
scripts/wrap-ledger.sh|count FIRST, free text LAST — and the code says so at the emitter. The one read (count_blocking_decisions) consumes a single `@tsv` row built as [ (length|tostring), (what_plain or "") ]: cell 1 is the length of a jq array rendered as a string, which cannot be empty, and it is additionally digit-VALIDATED on the next line (case "${n:-}" in ''|*[!0-9]*) → error). The only empty-reachable cell is the operator's own prose, which is LAST, so nothing a human types into a decision packet can shift the field the ⛔ rung branches on
scripts/unattended-path-lint.sh|both reads (:757 hooks, :804 launchd) share ONE producer, scan_shell's python emitter at :512 — `print("%s\t%d\t%s" % (path, lineno, word))`. Cell 1 is an argv path scan_shell was called with (non-empty by construction — an empty argv element names no file) and cell 2 is a %d of an int, which cannot be empty. The only variable-content cell is the extracted word, which is LAST and is existence-tested first thing in both loops ([ -n "$w" ] || continue). Same discharge as hooks/validate-bash.sh above, which shares the %d/%s-with-trailing-variable shape
scripts/thrash-block-recover.sh|producer REFUSES on an empty id (`select(($last.id // "") != "")`, added with this exemption) rather than emitting one, so cell 1 is non-empty at the source. Cell 2 is a literal "RECOVER"/"HOLD" from an if/else, and cells 3-5 are `|tostring` of array LENGTHS — none can be empty. Both reads (:135 render, :159 apply) share that one jq. Same discharge as e1-concurrent-logins and store-bounds-census above
hooks/escalation-watch.sh|both reads (total, and the per-class pass) consume ONE producer, unseen_rows' perl emitter, which guarantees every cell non-empty AT THE SOURCE rather than padding in jq. Cell 1: candidates() prints one of five LITERAL class names it chooses itself (handoff-alarm / announce-alarm / announce-degrade / completion-push / page — five unconditional printfs, no empty-reachable branch), and the emitter additionally pads it to "unknown" if that ever stops holding. It PADS rather than skipping, because dropping a record is precisely the silent loss this hook exists to prevent. Cell 2 is `(stat($path))[9]` with `$mt = 0 unless defined`, so it is always a number. Cell 3 is $path, which is LAST and is length-tested before the row is printed (`next unless defined $path && length $path`). Same discharge as e1-concurrent-logins and store-bounds-census above
scripts/branch-reaper.sh|the one read (:77, restore mode) consumes the manifest THIS script writes at :146 — printf '%s\t%s\n' "$b" "$sha", exactly two cells — and :145 drops any target whose refs/heads/$b does not rev-parse, so an empty name never reaches the writer and $sha is that verified output. A tab cannot widen the row into a third cell either: git check-ref-format rejects \t in a ref name. Belt-and-braces at the reader, since a manifest is a file a human can edit — :78 existence-tests BOTH cells and continues, so every degenerate 2-field row is discarded identically with or without the shift and `git branch` cannot run on a shifted pair
EOF
}

usage() { sed -n '2,/^set -uo/p' "$SELF" | sed 's/^# \{0,1\}//; /^set -uo/d'; }

exemption_text() {
  if [ -n "${CC_TSVPAD_EXEMPTIONS+set}" ]; then printf '%s\n' "$CC_TSVPAD_EXEMPTIONS"; else tsv_exemptions; fi
}

# exemption_reason <path> <table-text> — prints the reason; exit 1 if the path is not listed.
# `read p r` splits on the FIRST | only, which is load-bearing: reasons quote shell containing `||`.
exemption_reason() {
  local want="$1" p r
  while IFS='|' read -r p r; do
    [ "$p" = "$want" ] || continue
    printf '%s' "$r"
    return 0
  done <<EOF
$2
EOF
  return 1
}

# discharged <file> — the file makes a deliberate, greppable statement that its author considered
# the collapse. Clauses (1)-(3) of THE RULE above, verbatim from tests/tsv-field-collapse.bats §3.
discharged() {
  grep -qE 'def cell(\(ph\))?:|def _cell' "$1" && return 0
  grep -qE 'session_index_unpad|unpad\(\)|TSV_PAD' "$1" && return 0
  grep -qE '^norm\(\)|^dash\(\)' "$1" && return 0
  grep -qE '\$\{[A-Za-z_][A-Za-z0-9_]*:--\}' "$1" && return 0
  return 1
}

# THE BASENAME COLLAPSE, FIXED (2026-08-15, backlog c1a29f8ee045; land-arch §5.P2 arm 13 called the
# width deliberate, which it was — but the SECOND leg basenamed the OWN-SET too, so a PATHED entry
# `bin/z.sh` also matched a judged `scripts/z.sh`. That is not width in the direction the paragraph
# above argues for: a caller who spelled the directory said which file is theirs. The bare-entry leg
# is unchanged and still deliberately wide. Body shared VERBATIM with test-hermeticity-lint /
# git-identity-lint / utc-stamp-lint; contract in full at test-hermeticity-lint.sh's in_own, and
# tests/gate-ownscope-leak.bats pins the four copies identical.
in_own() { # $1=path the lint knows · $2=own-set text · $3=1 if an own-set was supplied at all
  [ "${3:-0}" = "1" ] || return 0          # no own-set supplied ⇒ everything is own ⇒ strict
  [ -n "$2" ] || return 1                  # supplied but empty ⇒ nothing is own ⇒ nothing blocks
  local e
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    case "$e" in
      */*) [ "$1" = "$e" ] && return 0
           case "$1" in */"$e") return 0 ;; esac ;;
      *)   [ "${1##*/}" = "$e" ] && return 0 ;;
    esac
  done <<< "$2"
  return 1
}

# lint_tree <root> <exemption-text> [<own-set>] → 0 clean · 1 violation · 2 NON-VERDICT
lint_tree() {
  local root="$1" table="$2" own="${3:-}" own_scoped=0
  [ "$#" -ge 3 ] && own_scoped=1
  [ -d "$root" ] || { echo "tsv-pad-lint: ⛔ not a directory: $root" >&2; return 2; }

  local dirs="" d
  for d in ${CC_TSVPAD_DIRS:-bin hooks scripts}; do
    [ -d "$root/$d" ] && dirs="$dirs $d"
  done
  [ -n "$dirs" ] || { echo "tsv-pad-lint: ⛔ no scan dir (${CC_TSVPAD_DIRS:-bin hooks scripts}) under $root" >&2; return 2; }

  local readers
  # shellcheck disable=SC2086  # deliberate word-split: $dirs is the list of scan dirs that exist
  readers="$(cd "$root" && grep -rlF -e "$TSV_READ_MARK" $dirs 2>/dev/null | sort)"
  if [ -z "$readers" ]; then
    # A scan that matches NOTHING is the one result this lint must never render as green: it is
    # what a broken marker looks like from the inside. (memory: sensor-default-off-ships-blindness)
    echo "tsv-pad-lint: ⛔ not one IFS=<tab> read site under$dirs — the scan or the assembled marker" >&2
    echo "  is broken. NON-VERDICT, not a clean tree." >&2
    return 2
  fi

  local f p r why bad=0 other=0 stuck=0 n=0 nex=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$((n + 1))
    discharged "$root/$f" && continue
    exemption_reason "$f" "$table" >/dev/null && continue
    if in_own "$f" "$own" "$own_scoped"; then
      printf '  UNPADDED %s: reads IFS=<tab> TSV with no padding def and no reviewed exemption\n' "$f"
      (cd "$root" && grep -nF -e "$TSV_READ_MARK" "$f") | sed 's/^/             /'
      bad=$((bad + 1))
    else
      printf '  unpad?   %s: unpadded TSV reader (NOT in your diff — advisory, not blocking)\n' "$f"
      other=$((other + 1))
    fi
  done <<EOF
$readers
EOF

  # The ratchet's other direction. An exemption list that only ever grows is an amnesty, and a line
  # whose subject moved on is worse than none: it reads as a reviewed discharge of a file nobody
  # has looked at since. (memory: work-item-remedy-can-become-forbidden)
  while IFS='|' read -r p r; do
    [ -n "$p" ] || continue
    nex=$((nex + 1))
    why=""
    if [ ! -f "$root/$p" ]; then why="the file is gone"
    elif ! grep -qF -e "$TSV_READ_MARK" "$root/$p"; then why="it no longer reads IFS=<tab> TSV"
    elif [ -z "$r" ]; then why="it carries no reason"
    fi
    [ -n "$why" ] || continue
    if in_own "$p" "$own" "$own_scoped"; then
      printf '  RATCHET  %s: stale exemption — %s. Delete its line.\n' "$p" "$why"
      stuck=$((stuck + 1))
    else
      printf '  ratchet? %s: stale exemption — %s (NOT in your diff — advisory)\n' "$p" "$why"
      other=$((other + 1))
    fi
  done <<EOF
$table
EOF

  [ "$other" -eq 0 ] || echo "tsv-pad-lint: $other pre-existing item(s) NOT in your diff — reported, not blocking (own-scope)."

  if [ "$bad" -gt 0 ]; then
    echo "tsv-pad-lint: ⛔ $bad file(s) above read IFS=<tab> TSV with nothing guaranteeing a non-empty cell."
    echo "  Tab is IFS-WHITESPACE: an empty cell does not read back empty, it shifts every later"
    echo "  column LEFT, silently, exit 0. Measured in this repo: a table row named after its own"
    echo "  verdict, a title rendered in the project column, and a crash on an unbound variable."
    echo '  Fix at the EMITTER — the read side cannot be repaired. In the jq that builds the row:'
    echo '       def cell(ph): (if . == null then "" else . end) | tostring'
    # printf, not echo: the line carries backslashes, and `echo` expanding them under a different
    # shell would print a real tab where the author needs the two characters `\t` to paste into jq.
    printf '%s\n' '                     | gsub("[\\t\\r\\n]"; " ") | if . == "" then ph else . end;'
    echo '  then pipe every non-LAST cell through it. `//` is NOT enough — it substitutes for'
    echo '  null/false and never for a present-but-empty string, which is the case that bites.'
    echo "  If the producer provably cannot emit an empty cell, add a REVIEWED exemption line"
    echo "  (<path>|<the argument>) to tsv_exemptions() in $SELF."
  fi
  if [ "$stuck" -gt 0 ]; then
    echo "tsv-pad-lint: ⛔ $stuck exemption(s) above are stale. Delete their lines — the table only shrinks."
  fi
  [ $((bad + stuck)) -eq 0 ] || return 1
  echo "tsv-pad-lint: clean — $n reader(s) under$dirs; $nex reviewed exemption(s), 0 unpadded."
  return 0
}

# ── --selftest: every case proves a RED path fires or a GREEN path does not, both directions ─────
# HERMETIC BY CONSTRUCTION — fixtures only, never the real tree, and that is a decision rather than
# an omission. The siblings assert their own tree is clean inside --selftest; here that would defeat
# the own-scope this lint is built around: ship-land runs --selftest BEFORE the scan, so one
# pre-existing offender anywhere in bin/ hooks/ scripts/ would fail the selftest and block EVERY
# author's land — the fleet-wide stop own-scope exists to prevent. Real-tree cleanliness is asserted
# where it belongs, by tests/tsv-field-collapse.bats, which drives this same lint.
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  # Fixture reader lines are built from $TSV_READ_MARK. That makes this selftest a test of the
  # RECOGNIZER and of own-scope, and deliberately NOT of the marker — see the note at TSV_READ_MARK
  # for why it cannot be, and where the marker is really pinned.
  mk() { # <case> <file> <body-before-the-read>
    mkdir -p "$d/$1/scripts"
    printf '#!/bin/bash\n%s\nwhile %s -r a b c; do :; done\n' "$3" "$TSV_READ_MARK" > "$d/$1/scripts/$2"
  }
  mk bare      z.sh ''
  mk cellph    z.sh 'CELL="def cell(ph): ."'
  mk cellplain z.sh 'JQ="def cell: ."'
  mk pycell    z.sh '# python: def _cell(v): return v'
  mk unpadfn   z.sh 'unpad() { printf %s "$1"; }'
  mk unpadsi   z.sh '# session_index_unpad handles it upstream'
  mk tsvpad    z.sh 'TSV_PAD=$(printf "\037")'
  mk normfn    z.sh 'norm() { awk "{print}"; }'
  mk defaultd  z.sh 'x="${maybe:--}"'
  mk exempted  z.sh ''
  # a padded sibling so the "exemption points at nothing" trees still have a reader to scan
  for c in gonefile nolonger; do mk "$c" keep.sh 'CELL="def cell(ph): ."'; done
  printf '#!/bin/bash\necho no tsv here\n' > "$d/nolonger/scripts/z.sh"
  mkdir -p "$d/nodir/other" && printf 'x\n' > "$d/nodir/other/f.txt"
  mk noreader  z.sh ''
  printf '#!/bin/bash\necho plain\n' > "$d/noreader/scripts/z.sh"

  fails=0
  chk() { # <expected-rc> <case> <exemptions> [<own-set>...] — label is $2 plus the message
    local want="$1" case="$2" table="$3"; shift 3
    local msg="$1"; shift
    if [ "$#" -ge 1 ]; then CC_TSVPAD_EXEMPTIONS="$table" lint_tree "$d/$case" "$table" "$1" >/dev/null 2>&1
    else CC_TSVPAD_EXEMPTIONS="$table" lint_tree "$d/$case" "$table" >/dev/null 2>&1; fi
    local rc=$?
    [ "$rc" = "$want" ] || { echo "SELFTEST FAIL: $msg (rc=$rc, wanted $want)"; fails=1; }
  }

  # RED — the shape this lint exists for: a reader with no statement of any kind.
  chk 1 bare      "" "an unpadded TSV reader did not go RED — the whole rule is inert"
  # GREEN — each recognizer clause, one case per clause (memory: per-site-mutation-attributes-coverage)
  chk 0 cellph    "" "\`def cell(ph):\` went RED — clause 1 lost"
  chk 0 cellplain "" "\`def cell:\` went RED — clause 1's second spelling lost"
  chk 0 pycell    "" "python \`def _cell\` went RED — clause 1's third spelling lost"
  chk 0 unpadfn   "" "a local \`unpad()\` went RED — clause 2 lost"
  chk 0 unpadsi   "" "\`session_index_unpad\` went RED — clause 2's second spelling lost"
  chk 0 tsvpad    "" "\`TSV_PAD\` went RED — clause 2's third spelling lost"
  chk 0 normfn    "" "an awk \`norm()\` right-fill went RED — clause 3 lost"
  chk 0 defaultd  "" 'a `${var:--}` emitter went RED — clause 3'"'"'s second spelling lost'
  # clause 4, both directions
  chk 0 exempted  "scripts/z.sh|a reviewed reason" "a reviewed exemption did not discharge its file"
  chk 1 exempted  "scripts/z.sh|"                  "an exemption with NO reason passed — the reason is the whole point"
  chk 1 gonefile  "scripts/vanished.sh|a reason"   "an exemption naming a MISSING file passed — the ratchet does not shrink"
  chk 1 nolonger  "scripts/z.sh|a reason"          "an exemption whose file no longer reads TSV passed — the ratchet does not shrink"
  # own-scope, all four states, on the RED case
  chk 0 bare "" "a violation OUTSIDE the own-set blocked — a lander refused over a file they never touched" "scripts/other.sh"
  chk 1 bare "" "a violation INSIDE the own-set did not block — own-scope disabled the rule"              "scripts/z.sh"
  chk 1 bare "" "an own-set naming only the BASENAME did not block — the widening is inert"               "z.sh"
  # THE COLLAPSE CONTROL (backlog c1a29f8ee045). The judged file is scripts/z.sh; an author who
  # changed bin/z.sh spelled a DIFFERENT file and must not be refused over this one. RED pre-fix,
  # because the second matching leg basenamed the own-set as well as the path. The case above and
  # this one differ only in whether the entry carries a `/` — which is exactly the rule.
  chk 0 bare "" "an own-set naming the same basename under ANOTHER dir blocked — the basename collapse" "bin/z.sh"
  chk 0 bare "" "an EMPTY own-set blocked — set-empty collapsed into unset"                               ""
  # NON-VERDICTS — never dressed up as a claim about the tree
  chk 2 nodir    "" "a tree with no scan dir did not exit 2 (LOUD)"
  chk 2 noreader "" "a tree where the scan matched NOTHING reported a verdict — that is what a broken marker looks like"
  CC_TSVPAD_EXEMPTIONS="" lint_tree "$d/does-not-exist" "" >/dev/null 2>&1
  [ "$?" = 2 ] || { echo "SELFTEST FAIL: a missing root did not exit 2 (LOUD)"; fails=1; }

  if [ "$fails" -eq 0 ]; then
    echo "tsv-pad-lint --selftest: 20/20 — RED on a bare unpadded reader, on a reasonless exemption, and on both stale-exemption shapes; GREEN on all eight recognizer spellings and on a reviewed exemption; own-scope blocks INSIDE / advises OUTSIDE / matches a bare basename / does NOT match the same basename under another directory (the collapse control) / passes set-empty; LOUD (exit 2) on a missing root, a tree with no scan dir, and a scan that matched nothing."
    exit 0
  fi
  echo "tsv-pad-lint --selftest: FAILED — the lint does not discriminate."
  exit 1
fi

# ── --print-scope: the population this lint JUDGES, as git pathspecs, one per line ────────────────
# Honours CC_TSVPAD_DIRS exactly as lint_tree does. `<dir>/*` is EXACT rather than approximate here:
# the scan is `grep -rlF … $dirs`, i.e. recursive over each dir, and a git pathspec's `*` matches `/`
# unless `:(glob)` magic is asked for — so the two cover the same file set.
#
# WHY IT EXISTS (backlog 0be0bd2c0b65) — the same seam scripts/permission-gate-lint.sh --print-scope
# documents at length, one lint over. ship-land built this lint's own-scope set from a hardcoded
# `-- 'bin/*' 'hooks/*' 'scripts/*'` and a comment saying the pathspec "must list every population
# the lint judges". A comment is not a mechanism, and the drift fails SILENTLY toward advisory: a
# land adding an unpadded reader under a dir the stale pathspec misses yields an own-set without it,
# the lint reports it advisory, and the rule is detection again.
#
# THE FALLBACK IS `:-`, DELIBERATELY — the same operator lint_tree uses, so the two can never
# disagree about what an unset-or-empty CC_TSVPAD_DIRS means (both fall back to "bin hooks scripts").
# Measured: `CC_TSVPAD_DIRS= --print-scope` prints the 3 embedded dirs, not zero.
# The consumer's NON-VERDICT is therefore reached by an UNRUNNABLE lint — a missing file, or an
# older copy that does not know this flag and exits 2 with empty stdout — never by an empty var here.
case "${1:-}" in
  --print-scope)
    _ps_restore_f=0; case "$-" in *f*) _ps_restore_f=1 ;; esac
    set -f
    # shellcheck disable=SC2086  # deliberate word-split of the dir list; globbing is off for exactly this
    for _ps_d in ${CC_TSVPAD_DIRS:-bin hooks scripts}; do printf '%s/*\n' "$_ps_d"; done
    [ "$_ps_restore_f" -eq 1 ] || set +f
    exit 0 ;;
esac

case "${1:-}" in -h|--help) usage; exit 0 ;; esac

if [ -n "${CC_TSVPAD_OWN+set}" ]; then
  lint_tree "${1:-$ROOT}" "$(exemption_text)" "$CC_TSVPAD_OWN"
else
  lint_tree "${1:-$ROOT}" "$(exemption_text)"
fi
exit $?
