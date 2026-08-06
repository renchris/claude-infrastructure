#!/bin/bash
# shellcheck disable=SC2016  # file-wide: --selftest AUTHORS shell fixtures, so `$( )` and `$G` inside
# those single-quoted bodies must reach the fixture file unexpanded — that is the point of them.
# subshell-cleanup-lint.sh — the SUBSHELL-ERASES-THE-CLEANUP-RECORD class, detected TRANSITIVELY.
#
# THE CLASS. A script records what it must clean up in a GLOBAL, and a trap handler consults that
# global to decide. If the assignment happens anywhere inside a call tree the script ENTERS THROUGH
# COMMAND SUBSTITUTION, the assignment lands in the `$( )` child — which neither exports it back nor
# runs the parent's EXIT trap. The parent's handler then reads the pre-call value and tears down
# NOTHING. Nothing fails: the run is green, the resource leaks on every path including success, and
# only an age reaper (hours later, if one exists at all) collects it.
#
# THE INSTANCE IT WAS WRITTEN FOR. postland-verify.sh mints a disposable git worktree cell per run.
# `prepare_worktree`'s only effect that outlives it is `WT_MINTED="$WORKTREE"` — the sole thing
# `teardown_worktrees` consults. `verb_bisect` read its result as `c="$(do_bisect …)"`, and
# `do_bisect` calls `prepare_worktree`. A cell leaked per invocation, reaped 8h later by age.
#
# WHY THIS LINT IS TRANSITIVE, AND WHY THAT IS THE WHOLE POINT. A first attempt keyed on "is the
# ASSIGNING function itself substituted?" It answered NO here — `prepare_worktree` is called one
# level deeper, inside `do_bisect` — swept the seven other worktree-minting scripts, came back
# clean, and then FAILED its positive control against the pre-fix artifact. A detector that cannot
# find the instance you already hold has measured nothing, so its clean result was a NON-VERDICT,
# not an all-clear. That is why this one builds a real call graph and takes a closure over it: the
# DEPTH of the assignment is precisely the dimension the blind version was keyed against.
#
# THE SWEEP THIS SHIPPED WITH (2026-08-06, 356 tracked shell files). Exactly one live instance: the
# two `$(do_bisect …)` sites in scripts/postland-verify.sh, still present on origin/main at the time
# — the memory note for this class recorded the subshell as already deleted, and it never was, so
# the leak had been running in the post-land verifier the whole time. Fixed in the same commit (see
# BISECT_CULPRIT there). Everything else is clean at every strictness this tool offers: 0 findings
# at default, 0 with --loose, 0 with --shapes all. The seven other worktree-minting scripts named in
# the backlog item are among the 356 and are genuinely clean — which is now a claim with a control
# behind it, rather than the earlier non-verdict.
#
# WHAT IT REPORTS. Per substitution site whose callee's call tree assigns a global that a trap
# handler consults destructively: the site, the variable, the chain from substituted callee down to
# the assigning function, and the trap read site. The chain is printed because the finding is only
# actionable with it — "some global is stale" is not a defect report, "WT_MINTED is assigned two
# frames below a $( )" is.
#
# STRICTNESS. By default a candidate global must be read by the handler closure ON A LINE THAT ALSO
# DESTROYS SOMETHING (rm/kill/worktree remove/…, or a call to a function that does). That filter is
# what separates a cleanup RECORD from a log path — both are globals a handler reads. `--loose`
# drops it. `--shapes all` adds pipelines, whose every component is a subshell too (bash `lastpipe`
# is off by default), so a piped function loses its assignments exactly as a `$( )` callee does.
#
# PERFORMANCE IS A CORRECTNESS PROPERTY HERE, not a nicety. This runs in postland-verify's PRELINTS
# slot, under LINT_QOS, where the measured background-band tax reaches 84x and LINT_TO is 600s —
# sized for a ~3s foreground lint with 2.4x headroom. The first version of this file forked two awk
# processes per file (712) and matched every known function name as a regex against every line: 16.4s
# foreground, i.e. ~1380s taxed, i.e. it would have blown the bound and turned EVERY post-land run
# into a CUT — fleet-fatal, and invisible to the only person who could see it, because by hand it
# takes 16 seconds and works fine. So: ONE awk process for the whole sweep, one read per file,
# identifier tokenisation instead of per-function regex, adjacency-list BFS instead of a repeated
# edge scan, closures cached per root. Keep it that way — `time` it before landing a change here,
# and read one foreground second as ~84 taxed.
#
# HOW ITS CLEAN VERDICT STAYS WORTH SOMETHING. `--selftest` proves the SHAPES discriminate, both
# directions, on fixtures. `--mutants` proves it is not blind on the SHIPPED CORPUS: per file that
# installs a named trap handler, that file's own trap-consulted global is injected into a function
# the file already substitutes, and the lint must catch it. Fixtures alone cannot retire the
# complaint that produced this lint — the previous detector passed its author's cases and still could
# not see the instance in hand.
#
# LIMITS, STATED SO A CLEAN RESULT MEANS SOMETHING. Call detection is textual and deliberately
# OVER-inclusive: any identifier token matching a defined function name is an edge, because
# under-inclusion is what made the previous detector blind. `case` patterns inside a `$( )` can
# unbalance its paren scan. Process substitution `<(f)` is a subshell this does not model. Quote
# flags reset per line (see split_subs for why that direction is chosen deliberately).
set -uo pipefail

usage() {
  cat <<'USAGE'
usage: subshell-cleanup-lint.sh [--json] [--loose] [--shapes cmdsub|all] [--list] [--selftest] [--mutants] [FILE...]

  no FILE       sweep every tracked shell file in the repo
  --json        one JSON object per finding
  --loose       drop the destructive-use filter on trap-consulted globals
  --shapes all  also report pipeline components, not just $( )
  --list        print the files that would be scanned, then exit 0
  --selftest    prove the detector discriminates on SHAPES, both directions, then exit
  --mutants     prove it is not blind on the REAL corpus: per trap-handler file, inject that file's
                own trap-consulted global into a function the file already substitutes, then exit

exit: 0 clean · 1 findings · 2 usage / unusable scan (LOUD, never silent-green)
USAGE
}

JSON=0; LOOSE=0; SHAPES=cmdsub; LIST=0; SELFTEST=0; MUTANTS=0; FILES=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)     JSON=1 ;;
    --loose)    LOOSE=1 ;;
    --shapes)   shift; SHAPES="${1:-cmdsub}"
                case "$SHAPES" in cmdsub|all) ;; *) echo "subshell-cleanup-lint: --shapes takes cmdsub|all" >&2; exit 2 ;; esac ;;
    --list)     LIST=1 ;;
    --selftest) SELFTEST=1 ;;
    --mutants)  MUTANTS=1 ;;
    -h|--help)  usage; exit 0 ;;
    --) shift; while [ "$#" -gt 0 ]; do FILES+=("$1"); shift; done; break ;;
    -*) echo "subshell-cleanup-lint: unknown flag $1" >&2; usage >&2; exit 2 ;;
    *)  FILES+=("$1") ;;
  esac
  shift
done

# Repo root resolved from THIS script through its symlinks, never from $PWD: the live ~/.claude layer
# reaches this file by symlink, and a $PWD-relative root would scan whatever tree the caller stood in.
# No `readlink -f` — GNU-only, and this box is BSD.
_self="${BASH_SOURCE[0]}"
while [ -L "$_self" ]; do
  _d="$(cd "$(dirname "$_self")" && pwd)"; _t="$(readlink "$_self")"
  case "$_t" in /*) _self="$_t" ;; *) _self="$_d/$_t" ;; esac
done
ROOT="$(cd "$(dirname "$_self")/.." 2>/dev/null && pwd -P)" || { echo "subshell-cleanup-lint: ⛔ cannot resolve repo root" >&2; exit 2; }

# ── the awk engine ────────────────────────────────────────────────────────────────────────────────
IFS= read -r -d '' PROG <<'AWK' || true
BEGIN {
  SUBSEP = "\001"; Q = sprintf("%c", 39)
  DESTR  = "(^|[ \t;&|(){}])(rm|rmdir|unlink|kill|pkill|shred|truncate)([ \t]|$)"
  DESTR2 = "(worktree[ \t]+remove|launchctl[ \t]+(bootout|kill|remove)|tmux[ \t]+kill|close-window|rm[ \t]+-)"
  # after one of these, the NEXT token is a command — `if f; then` must still yield an edge to f
  split("if then else elif do while until time exec eval command builtin nohup", KWL, " ")
  for (i in KWL) KW[KWL[i]] = 1
}

# Comments off, quote-aware. Quote characters and their contents are KEPT here (split_subs decides
# what is code); stripping quoted text at this stage would erase `x="$(f)"`, i.e. the whole class.
function strip_comment(s,   out, i, c, n, q, prev) {
  out = ""; q = ""; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q != Q && c == "\\") { out = out c substr(s, i + 1, 1); i++; continue }
    if (q == "") {
      if (c == Q || c == "\"") { q = c; out = out c; continue }
      if (c == "#") {
        prev = (i == 1) ? "" : substr(s, i - 1, 1)
        if (prev == "" || prev == " " || prev == "\t" || prev == ";" || prev == "&" || prev == "|" || prev == "(")
          return out
        out = out c; continue
      }
      out = out c; continue
    }
    if (c == q) q = ""
    out = out c
  }
  return out
}
# ${…} removed so remaining braces are structural, not parameter expansions.
function debrace(s,   t, prev) {
  t = s
  do { prev = t; gsub(/\$\{[^{}]*\}/, "$", t) } while (t != prev)
  return t
}
# Heredoc terminator opened on this line, or "".
# `<<<` and `$((` are neutralised FIRST: a here-string matches as `<<` + a word and would open a
# phantom heredoc that swallows the rest of the file — every later line skipped, verdict CLEAN.
# Blindness is the one failure this lint may not have, so the paths that produce a silent all-clear
# are handled explicitly rather than left to luck.
function hd_term(s,   t, w) {
  t = s
  gsub(/<<</, "   ", t); gsub(/\$\(\(/, "   ", t)
  if (!match(t, /<<-?[ \t]*("[^"]*"|[A-Za-z_][A-Za-z0-9_]*)/))
    if (!match(t, /<<-?[ \t]*\047[^\047]*\047/)) return ""
  w = substr(t, RSTART, RLENGTH)
  HD_QUOTED = (w ~ /"/ || w ~ /\047/) ? 1 : 0
  sub(/^<<-?[ \t]*/, "", w); gsub(/["\047]/, "", w)
  return w
}

# Splits a line into S_in (code inside a live $( ) / ` `) and S_out (live code outside quotes).
# QUOTE-AWARE, and that is load-bearing rather than pedantic: self-path-lint.sh documents the
# resolve-self loop by ECHOING it, so the literal text `d="$(cd …)"` sits inside a double-quoted
# argument. Read as code that is an assignment to a trap-consulted global two frames under a
# substitution — a textbook instance of this very class, and entirely fictional. String CONTENT is
# DATA: dropped. Only `$( )` and backticks inside DOUBLE quotes stay live (single quotes make even
# those literal), which is the shell's own rule.
#
# SQ/DQ reset every line; CS/BT persist. Deliberately asymmetric. A stuck quote flag would drop the
# rest of the file and report CLEAN — silent blindness. A stuck paren counter merely routes code into
# S_in, where calls are still edges and still roots, so it fails toward NOISE. Both are wrong; only
# one is quiet. The cost is that a genuine multi-line double-quoted string reads as code on its
# continuation lines, which yields a visible, adjudicable finding instead of a silent all-clear.
function split_subs(s,   i, n, c, c2) {
  S_in = ""; S_out = ""; n = length(s); SQ = 0; DQ = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1); c2 = substr(s, i, 2)
    if (CS > 0) {
      if (c == "\\") { S_in = S_in "  "; i++; continue }
      if (c2 == "$(") { CS++; S_in = S_in " "; i++; continue }
      if (c == "(") { CS++; S_in = S_in " "; continue }
      if (c == ")") { CS--; S_in = S_in " "; continue }
      S_in = S_in c; continue
    }
    if (BT) { if (c == "`") { BT = 0; S_in = S_in " " } else S_in = S_in c; continue }
    if (SQ) { if (c == Q) SQ = 0; continue }
    if (DQ) {
      if (c == "\\") { i++; continue }
      if (c == "\"") { DQ = 0; continue }
      if (c2 == "$(") { CS++; i++; continue }
      if (c == "`") { BT = 1; continue }
      continue
    }
    if (c == "\\") { S_out = S_out " "; i++; continue }
    if (c == Q) { SQ = 1; continue }
    if (c == "\"") { DQ = 1; continue }
    if (c2 == "$(") { CS++; i++; continue }
    if (c == "`") { BT = 1; continue }
    S_out = S_out c
  }
}

# A one-pass scanner that yields identifier tokens AT A COMMAND POSITION. Both halves are load-
# bearing and both were learned the hard way:
#   • per-known-function REGEX (v1) was correct but O(lines x functions) — 16.4s, over the band bound.
#   • plain tokenisation with NO position check (v2) was fast and catastrophically imprecise: the
#     token `main` inside `$(git rev-parse origin/main)` registered main() as a substituted callee,
#     whose closure is the entire program, and postland-verify went from 2 findings to 30 — with the
#     FIXED file failing its own negative control. Over-inclusion is cheap for an EDGE and ruinous
#     for a ROOT, because a root drags its whole closure in behind it.
# Command position = start, or after ; | & ( ) { } !, or after a shell keyword. Whitespace alone does
# NOT make one, which is exactly what rejects `origin/main` (preceded by `/`) and `git -C` (`-`).
# A trap INSTALL (`trap cleanup_exit EXIT`) is deliberately not an edge either: the handler is
# registered separately, and treating installation as a call put main() one hop from every teardown.
function calls_in(txt, arr,   i, n, c, tok, cmdpos) {
  n = length(txt); i = 1; cmdpos = 1; tok = ""
  while (i <= n + 1) {
    c = (i <= n) ? substr(txt, i, 1) : " "
    if (c ~ /[A-Za-z0-9_]/) { tok = tok c; i++; continue }
    if (tok != "") {
      if (cmdpos && (tok in FN)) arr[tok] = 1
      cmdpos = (tok in KW) ? 1 : 0
      tok = ""
    }
    if (c == ";" || c == "|" || c == "&" || c == "(" || c == ")" || c == "{" || c == "}" || c == "!") cmdpos = 1
    else if (c != " " && c != "\t") cmdpos = 0
    i++
  }
}
function reads_in(txt, arr,   t, name) {
  t = txt
  while (match(t, /\$\{?[A-Za-z_][A-Za-z0-9_]*/)) {
    name = substr(t, RSTART, RLENGTH); sub(/^\$\{?/, "", name)
    arr[name] = 1
    t = substr(t, RSTART + RLENGTH)
  }
}
function assigns_in(txt, arr,   t, name) {
  t = txt
  while (match(t, /(^|[ \t;&|(){}])(export[ \t]+)?[A-Za-z_][A-Za-z0-9_]*\+?=/)) {
    name = substr(t, RSTART, RLENGTH)
    sub(/^[ \t;&|(){}]*/, "", name); sub(/^export[ \t]+/, "", name); sub(/\+?=$/, "", name)
    if (name != "") arr[name] = 1
    t = substr(t, RSTART + RLENGTH)
  }
}
function locals_in(txt, arr,   t, rest, i, n, parts, w) {
  t = txt
  while (match(t, /(^|[ \t;&|(){}])(local|declare|typeset|readonly)[ \t]+/)) {
    rest = substr(t, RSTART + RLENGTH); sub(/[;&|].*$/, "", rest)
    n = split(rest, parts, /[ \t]+/)
    for (i = 1; i <= n; i++) {
      w = parts[i]
      if (w ~ /^-/) continue
      sub(/=.*$/, "", w)
      if (w ~ /^[A-Za-z_][A-Za-z0-9_]*$/) arr[w] = 1
    }
    t = substr(t, RSTART + RLENGTH)
  }
}

# ── per-file buffering: one read, one awk process for the whole sweep ──────────────────────────────
FNR == 1 && NR > 1 { analyze() }
FNR == 1 { NL = 0; HASTRAP = 0; FILE = FILENAME; sub("^" ROOTP "/", "", FILE); NFILES++ }
{ RAW[FNR] = $0; NL = FNR; if ($0 ~ /(^|[ \t;&|(){}])trap([ \t]|$)/) HASTRAP = 1 }
END { if (NL > 0) analyze(); print NFILES " " NPARSED > COUNTFILE; exit 0 }

function reset_file() {
  split("", FN); split("", FNEND); split("", EDGE); split("", ADJ)
  split("", ASSIGN); split("", ASSIGNLN); split("", LOCALV); split("", READV)
  split("", DFN); split("", TRAPH); split("", TRAPREAD); split("", TRAPCAND)
  split("", TV); split("", TVLN); split("", TVH); split("", CLOS); split("", GA); split("", DUSE)
  split("", RS_NAME); split("", RS_KIND); split("", RS_LINE); split("", RS_SCOPE); split("", RS_TEXT)
  split("", SEENF); split("", RAW); split("", AVARS); split("", RVARS)
  split("", TXT); split("", SOUT); split("", SIN); split("", INHD); split("", SCOPE)
  split("", LR); split("", LD); split("", LC); split("", FCOUNT)
  NS = 0; CS = 0; BT = 0; FOUND_F = 0
}
function cur_scope() { return (CUR == "") ? "@global" : CUR }

# A function ENDS at a close brace on its OWN indentation, not at a brace count reaching zero.
# Counting was tried and is wrong here: self-path-lint.sh embeds a multi-line single-quoted awk
# program whose indented braces are DATA, the count never returned to zero, and every later
# top-level assignment — including a global-scope `d="$(mktemp -d)"` — was attributed to the
# enclosing function. That manufactured a finding from nothing, and could equally have hidden a real
# one by filing it under the wrong scope. Per-line quote reset cannot rescue a count (the blob spans
# lines by construction); indentation can, because a function's close brace is written where the
# function was. A single-line function (`f() { …; }` — 147 of them in this repo) is recognised by its
# own line's live braces balancing, so it never opens a range that swallows its successors.
#
# ONE character walk per line, total. Pass A caches the comment-stripped text and the code/substitution
# split for every line and records that line's enclosing scope; pass B reads the cache and never walks
# again. The earlier shape walked each line up to five times (strip+split in pass A, a peek to test for
# a function opener, then strip+split again in pass B) for 8.0s over 356 files — which at the measured
# 84x background tax is 672s against a 600s LINT_TO, i.e. still a CUT. Caching is what makes this
# lint affordable at the chokepoint, so it is a correctness property, not a tidiness one.
function analyze(   i, raw, txt, code, nm, ind, no, nc, t) {
  # A file that installs NO trap cannot exhibit this class — there is no handler to read a stale
  # record — so the expensive parse is skipped for it. This is a SOUND filter, not a sample: the
  # test is the `trap` word anywhere in the file, comments included, so it errs toward parsing.
  # Both counts are printed at the end (parsed / total) precisely so the population can never be
  # narrowed silently; 94 of 354 files install a trap here, and the filter is what buys the
  # headroom this lint needs under the background band.
  if (!HASTRAP) { reset_file(); return }
  NPARSED++
  CS = 0; BT = 0; HD = ""; HDQ = 0; CUR = ""; IND = ""
  for (i = 1; i <= NL; i++) {
    raw = RAW[i]
    if (HD != "") {
      SCOPE[i] = cur_scope()
      if (raw ~ ("^[ \t]*" HD "[ \t]*$")) { HD = ""; INHD[i] = 3; continue }
      if (HDQ) { INHD[i] = 1; continue }                 # quoted heredoc: literal bytes, never walked
      txt = strip_comment(raw); split_subs(txt)          # an UNQUOTED heredoc does expand $( )
      TXT[i] = txt; SOUT[i] = S_out; SIN[i] = S_in; INHD[i] = 2
      continue
    }
    txt = strip_comment(raw); split_subs(txt)
    TXT[i] = txt; SOUT[i] = S_out; SIN[i] = S_in; INHD[i] = 0
    code = debrace(S_out)
    SCOPE[i] = cur_scope()
    if (CUR == "") {
      if (match(code, /^[ \t]*(function[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]*(\(\))?[ \t]*\{/)) {
        nm = substr(code, RSTART, RLENGTH)
        ind = nm; sub(/[^ \t].*$/, "", ind)
        sub(/^[ \t]*/, "", nm); sub(/^function[ \t]+/, "", nm); sub(/[ \t]*(\(\))?[ \t]*\{$/, "", nm)
        if (nm ~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
          FN[nm] = i; SCOPE[i] = nm
          no = gsub(/\{/, "", code); nc = gsub(/\}/, "", code)
          if (no == nc) FNEND[nm] = i; else { CUR = nm; IND = ind }
        }
      }
    } else if (code ~ ("^" IND "\\}")) { FNEND[CUR] = i; CUR = "" }
    t = hd_term(txt); if (t != "") { HD = t; HDQ = HD_QUOTED }
  }
  for (i = 1; i <= NL; i++) if (INHD[i] != 1 && INHD[i] != 3) scan_cached(i)
  build_adj(); resolve(); report(); reset_file()
}

function scan_cached(i,   a, v, key, first, body, pipetxt, scope, txt, k, rl, cl) {
  scope = SCOPE[i]; txt = TXT[i]
  k = ++FCOUNT[scope]
  if (txt ~ DESTR || txt ~ DESTR2) { DFN[scope] = 1; LD[scope, k] = 1 }

  split("", a); assigns_in(SOUT[i], a); assigns_in(SIN[i], a)
  for (v in a) {
    key = scope SUBSEP v
    if (!(key in ASSIGN)) { ASSIGN[key] = 1; ASSIGNLN[key] = i; AVARS[scope] = AVARS[scope] " " v }
  }
  split("", a); locals_in(txt, a)
  for (v in a) LOCALV[scope SUBSEP v] = 1
  split("", a); reads_in(txt, a); rl = ""
  for (v in a) {
    key = scope SUBSEP v; rl = rl " " v
    if (!(key in READV)) { READV[key] = i; RVARS[scope] = RVARS[scope] " " v }
  }
  LR[scope, k] = rl

  split("", a); calls_in(SOUT[i], a); cl = ""
  for (v in a) { cl = cl " " v; if (v != scope) EDGE[scope SUBSEP v] = 1 }
  split("", a); calls_in(SIN[i], a)
  for (v in a) { cl = cl " " v; EDGE[scope SUBSEP v] = 1; add_root(v, "cmdsub", i, scope, txt) }
  LC[scope, k] = cl

  # `||` and `|&` stripped BEFORE looking for a pipe: a bare /\|/ test fires on every short-circuit
  # in the file, which is how this option first reported 15 findings, nearly all of them `… || log …`
  # lines with no pipeline in them at all.
  if (SHAPES == "all") {
    pipetxt = SOUT[i]
    gsub(/\|\|/, " ", pipetxt); gsub(/\|&/, " ", pipetxt)
    if (pipetxt ~ /\|/) { split("", a); calls_in(pipetxt, a); for (v in a) add_root(v, "pipe", i, scope, txt) }
  }

  if (match(txt, /(^|[ \t;&|(){}])trap[ \t]+/)) {
    body = substr(txt, RSTART + RLENGTH); first = substr(body, 1, 1)
    if (first == Q || first == "\"") {
      sub(/^.[ \t]*/, "", body)
      if (first == Q) sub(/\047.*$/, "", body); else sub(/".*$/, "", body)
      split("", a); calls_in(body, a); for (v in a) TRAPH[v] = i
      # A SINGLE-quoted trap body expands when the trap FIRES, so its reads are fire-time reads of
      # whatever the parent holds then. A DOUBLE-quoted body expanded at INSTALL captures the value
      # and cannot exhibit this class at all.
      if (first == Q) { split("", a); reads_in(body, a); for (v in a) TRAPREAD[v] = i }
    } else {
      sub(/^[ \t]*/, "", body)
      if (match(body, /^[A-Za-z_][A-Za-z0-9_]*/)) TRAPCAND[substr(body, RSTART, RLENGTH)] = i
    }
  }
}

# EVERY substitution site is retained, keyed by ORDINAL and not by callee. Keeping one site per
# callee is not a cosmetic loss: postland-verify substituted `do_bisect` at TWO lines, and the
# earlier one (red_actions) was immune BY ACCIDENT — the parent had already minted at the same path,
# so its record happened to cover the child's re-mint. Only the LATER site (verb_bisect) actually
# leaked. A first-site-wins collector therefore reports the harmless line and hides the live defect,
# and a fix applied where it points changes nothing.
function add_root(callee, kind, ln, scope, txt) {
  NS++
  RS_NAME[NS] = callee; RS_KIND[NS] = kind; RS_LINE[NS] = ln; RS_SCOPE[NS] = scope; RS_TEXT[NS] = txt
}

function build_adj(   pair, P) {
  for (pair in EDGE) { split(pair, P, SUBSEP); ADJ[P[1]] = ADJ[P[1]] " " P[2] }
}

# Both O(facts) instead of O(facts) PER QUERY, computed once the file is fully seen:
#   GA[v]   — v is assigned somewhere without being local there, i.e. it really is a global.
#   DUSE[f,v] — f consults v ON A LINE THAT DESTROYS: either directly, or by calling a function whose
#   own body destroys. This is what separates a cleanup RECORD from a log path, and it needs the whole
#   file first — DFN[] is only complete once every function has been read.
function resolve(   key, P, scope, k, n, i, parts, m, j, cparts, destr) {
  for (key in ASSIGN) {
    split(key, P, SUBSEP)
    if (!((P[1] SUBSEP P[2]) in LOCALV)) GA[P[2]] = 1
  }
  for (scope in FCOUNT) {
    for (k = 1; k <= FCOUNT[scope]; k++) {
      destr = ((scope SUBSEP k) in LD)
      if (!destr && (scope, k) in LC) {
        m = split(LC[scope, k], cparts, " ")
        for (j = 1; j <= m; j++) if (cparts[j] != "" && DFN[cparts[j]]) { destr = 1; break }
      }
      if (!destr) continue
      n = split(LR[scope, k], parts, " ")
      for (i = 1; i <= n; i++) if (parts[i] != "") DUSE[scope SUBSEP parts[i]] = 1
    }
  }
}

# members of root's call closure, space-delimited, cached per root
function closure(root,   q, qh, qt, cur, i, n, parts, seen, out) {
  if (root in CLOS) return CLOS[root]
  split("", seen); qh = 1; qt = 1; q[1] = root; seen[root] = 1; out = " " root
  while (qh <= qt) {
    cur = q[qh]; qh++
    if (!(cur in ADJ)) continue
    n = split(ADJ[cur], parts, " ")
    for (i = 1; i <= n; i++) {
      if (parts[i] == "" || (parts[i] in seen)) continue
      seen[parts[i]] = 1; qt++; q[qt] = parts[i]; out = out " " parts[i]
    }
  }
  CLOS[root] = out
  return out
}
function chain(root, target,   q, qh, qt, cur, i, n, parts, seen, out) {
  if (root == target) return root
  split("", seen); split("", PAR); qh = 1; qt = 1; q[1] = root; seen[root] = 1
  while (qh <= qt) {
    cur = q[qh]; qh++
    if (!(cur in ADJ)) continue
    n = split(ADJ[cur], parts, " ")
    for (i = 1; i <= n; i++) {
      if (parts[i] == "" || (parts[i] in seen)) continue
      seen[parts[i]] = 1; PAR[parts[i]] = cur; qt++; q[qt] = parts[i]
      if (parts[i] == target) { qh = qt + 1; break }
    }
  }
  if (!(target in PAR)) return root " → … → " target
  out = target; cur = target
  while (cur in PAR) { cur = PAR[cur]; out = cur " → " out }
  return out
}

function report(   h, f, v, n, si, r, k2, mem, j, nv, vs, x) {
  for (v in TRAPCAND) if (v in FN) TRAPH[v] = TRAPCAND[v]
  for (h in TRAPH) {
    if (!(h in FN)) continue
    n = split(closure(h), mem, " ")
    for (j = 1; j <= n; j++) {
      f = mem[j]
      if (f == "") continue
      nv = split(RVARS[f], vs, " ")
      for (x = 1; x <= nv; x++) {
        v = vs[x]
        if (v == "" || (v in TV)) continue
        if ((f SUBSEP v) in LOCALV) continue
        if (!(v in GA)) continue
        if (!LOOSE && !((f SUBSEP v) in DUSE)) continue
        TV[v] = f; TVLN[v] = READV[f SUBSEP v]; TVH[v] = h
      }
    }
  }
  for (v in TRAPREAD) {
    if ((v in TV) || !(v in GA)) continue
    TV[v] = "trap-body"; TVLN[v] = TRAPREAD[v]; TVH[v] = "trap-body"
  }

  for (si = 1; si <= NS; si++) {
    r = RS_NAME[si]
    if (!(r in FN)) continue
    n = split(closure(r), mem, " ")
    for (j = 1; j <= n; j++) {
      f = mem[j]
      if (f == "") continue
      nv = split(AVARS[f], vs, " ")
      for (x = 1; x <= nv; x++) {
        v = vs[x]; k2 = f SUBSEP v
        if (v == "" || !(v in TV) || (k2 in LOCALV)) continue
        if ((RS_LINE[si] SUBSEP v) in SEENF) continue
        SEENF[RS_LINE[si] SUBSEP v] = 1
        if (JSON) {
          printf "{\"file\":\"%s\",\"line\":%s,\"var\":\"%s\",\"shape\":\"%s\",\"sub_callee\":\"%s\",\"in_function\":\"%s\",\"chain\":\"%s\",\"assigned_in\":\"%s\",\"assigned_line\":%s,\"trap_handler\":\"%s\",\"trap_reader\":\"%s\",\"trap_read_line\":%s}\n",
            FILE, RS_LINE[si], v, RS_KIND[si], r, RS_SCOPE[si], chain(r, f), f, ASSIGNLN[k2], TVH[v], TV[v], TVLN[v]
        } else {
          printf "  ✗ %s:%s: %s — assigned inside a %s child; the trap reads the parent's stale copy\n",
            FILE, RS_LINE[si], v, (RS_KIND[si] == "cmdsub" ? "$( )" : "pipeline")
          printf "      site:  %s\n", trim(RS_TEXT[si])
          printf "      chain: %s   (assigns %s at :%s)\n", chain(r, f), v, ASSIGNLN[k2]
          printf "      trap:  %s → %s reads %s at :%s\n", TVH[v], TV[v], v, TVLN[v]
        }
        FOUND++
      }
    }
  }
  if (FOUND > 0) { printf "%s\n", FOUND > FOUNDFILE }
}
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
AWK

# ── file enumeration ──────────────────────────────────────────────────────────────────────────────
# `git ls-files`, not `find`: an untracked scratch copy is not something the repo ships, and a
# finding in one is a finding nobody can land a fix for.
enumerate() {
  local f first
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$ROOT/$f" ] || continue
    case "$f" in
      *.sh) printf '%s\n' "$ROOT/$f"; continue ;;
      *.bats|*.md|*.json|*.plist|*.py|*.js) continue ;;
    esac
    first="$(head -1 "$ROOT/$f" 2>/dev/null)"
    case "$first" in
      '#!'*bash*|'#!'*/sh|'#!'*env\ sh) printf '%s\n' "$ROOT/$f" ;;
    esac
  done <<EOF
$(git -C "$ROOT" ls-files 2>/dev/null)
EOF
}

# ── the scan, with awk's failure treated as UNSCANNED and never as clean ──────────────────────────
# The finding COUNT crosses back through a file, not through the exit status of a pipeline: awk's own
# `exit` would be indistinguishable from a scanner crash, and "printed nothing" is byte-identical to
# "clean". A non-zero awk rc or any awk stderr is exit 2 — unusable, never silent-green.
#
# CALL THIS WITHOUT A COMMAND SUBSTITUTION. It both prints findings AND records the population in
# POP for the caller. The first version captured its output instead, so POP was assigned in the
# substitution child and the parent printed "clean —  file(s) parsed of  scanned" with both numbers
# blank. That is this lint's own class, in the lint, caught only because the output went visibly
# empty. Documented rather than quietly fixed, because the shape is that easy to reach: a function
# that RETURNS text and RECORDS state loses the state the moment a caller captures the text.
POP=""
scan_files() { # <file…> → prints findings; rc 0 clean · 1 findings · 2 unusable
  local errf cntf popf out arc n
  [ "$#" -gt 0 ] || { echo "subshell-cleanup-lint: ⛔ no files to scan" >&2; return 2; }
  errf="$(mktemp -t sclint-err.XXXXXX)" || { echo "subshell-cleanup-lint: ⛔ mktemp failed" >&2; return 2; }
  cntf="$(mktemp -t sclint-cnt.XXXXXX)" || { rm -f "$errf"; echo "subshell-cleanup-lint: ⛔ mktemp failed" >&2; return 2; }
  popf="$(mktemp -t sclint-pop.XXXXXX)" || { rm -f "$errf" "$cntf"; echo "subshell-cleanup-lint: ⛔ mktemp failed" >&2; return 2; }
  # LC_ALL=C, deliberately. This scanner walks a line character by character looking for ASCII
  # structure (`$(`, quotes, braces, `;`); every multibyte character in the source is DATA to it. In
  # a UTF-8 locale macOS awk tries to widen each byte and dies — `towc: multibyte conversion failure`
  # — on this repo's own comment glyphs (→ ⛔ ✗ …), which is how a whole 1755-line file came back
  # UNSCANNED. Byte orientation also makes the verdict independent of the caller's LANG: a gate whose
  # answer depends on the environment it was invoked from is not a gate.
  out="$(LC_ALL=C awk -v ROOTP="$ROOT" -v JSON="$JSON" -v LOOSE="$LOOSE" -v SHAPES="$SHAPES" \
            -v FOUNDFILE="$cntf" -v COUNTFILE="$popf" "$PROG" "$@" 2>"$errf")"
  arc=$?
  if [ "$arc" != 0 ] || [ -s "$errf" ]; then
    echo "subshell-cleanup-lint: ⛔ SCANNER FAILED (awk rc=$arc) — these files are UNSCANNED, not clean" >&2
    sed 's/^/  awk: /' "$errf" >&2
    rm -f "$errf" "$cntf" "$popf"; return 2
  fi
  n="$(head -1 "$cntf" 2>/dev/null)"; n="${n:-0}"
  POP="$(head -1 "$popf" 2>/dev/null)"
  rm -f "$errf" "$cntf" "$popf"
  [ "$n" = 0 ] && return 0
  [ "$JSON" = 1 ] || echo "subshell-cleanup-lint: trap-consulted global(s) assigned inside a subshell"
  [ -n "$out" ] && printf '%s\n' "$out"
  [ "$JSON" = 1 ] || cat <<'FIX'
  Fix: do not enter the minting call tree through a substitution. Return the value through a
  global out-parameter and drop the `$( )`, so the shell that RECORDS the cleanup is the shell
  that RUNS the trap. Do NOT set the record at the call site instead — that re-implements the
  minter's bookkeeping outside it and goes stale the moment the mint path changes.
FIX
  return 1
}

# ── --selftest: every case proves a RED path FIRES or a GREEN path does NOT, both directions ──────
# A detector is only worth its clean verdict if it can be shown to discriminate. These controls are
# the SHAPES; the real pre-fix artifact is pinned in tests/subshell-cleanup-lint.bats, and that is
# the control that matters most — a hand-written approximation can pass vacuously where the true
# artifact would not.
if [ "$SELFTEST" = 1 ]; then
  d="$(mktemp -d)" || exit 2
  trap 'rm -rf "$d"' EXIT
  fails=0
  mk() { printf '#!/bin/bash\n%s\n' "$2" > "$d/$1.sh"; }
  ck() { # <case> <want-rc> <why> [extra-flags…]
    local c="$1" want="$2" why="$3" got; shift 3
    bash "$_self" "$@" "$d/$c.sh" >/dev/null 2>&1; got=$?
    if [ "$got" = "$want" ]; then printf '  ok   %s — %s\n' "$c" "$why"
    else printf '  FAIL %s — %s (want rc=%s, got %s)\n' "$c" "$why" "$want" "$got"; fails=$((fails + 1)); fi
  }

  # RED: the class at depth 2 — the exact shape the one-level detector was blind to.
  mk transitive 'G=""
cleanup() { rm -rf "$G"; }
trap cleanup EXIT
mint() { G="/tmp/cell.$$"; mkdir -p "$G"; }
outer() { mint; echo done; }
r="$(outer)"'
  ck transitive 1 'an assignment TWO frames under a substitution is found'

  # RED: depth 1 — the case the blind detector did catch. It must still fire.
  mk onelevel 'G=""
cleanup() { rm -rf "$G"; }
trap cleanup EXIT
mint() { G="/tmp/cell.$$"; }
r="$(mint)"'
  ck onelevel 1 'an assignment ONE frame under a substitution is found'

  # GREEN: the same call tree without the substitution — this is the fix shape.
  mk direct 'G=""
cleanup() { rm -rf "$G"; }
trap cleanup EXIT
mint() { G="/tmp/cell.$$"; }
outer() { mint; }
outer
r="$G"'
  ck direct 0 'the same tree called WITHOUT a substitution is clean — the fix shape'

  # GREEN: a local of that name is not the parent's record.
  mk localvar 'G=""
cleanup() { rm -rf "$G"; }
trap cleanup EXIT
mint() { local G; G="/tmp/x"; }
r="$(mint)"'
  ck localvar 0 'a LOCAL shadowing the trap global is not the record'

  # GREEN: the trap reads it, but nothing destructive keys on it (a log path, not a record).
  mk logpath 'G=""
cleanup() { printf "%s\n" "$G" >> /dev/null; }
trap cleanup EXIT
mint() { G="/tmp/log"; }
r="$(mint)"'
  ck logpath 0 'a trap-read global with no destructive use is not a cleanup record'
  ck logpath 1 'and --loose DOES report it — the precision knob is real, not decorative' --loose

  # GREEN: an assignment that is STRING DATA, not code — self-path-lint.sh's echoed documentation.
  mk stringdata 'G=""
cleanup() { rm -rf "$G"; }
trap cleanup EXIT
doc() { echo "  the canonical loop is G=\"\$(cd x)\" — as DATA"; }
r="$(doc)"'
  ck stringdata 0 'an assignment inside a quoted string is data, not an assignment'

  # PIPELINE shape: off by default, on under --shapes all. Both directions, so neither is inert.
  mk piped 'G=""
cleanup() { rm -rf "$G"; }
trap cleanup EXIT
mint() { G="/tmp/cell"; }
mint | cat'
  ck piped 0 'a piped assignment is NOT reported by default (the frozen class is a substitution)'
  ck piped 1 'and IS reported under --shapes all' --shapes all

  # A short-circuit is not a pipeline — the bug that made --shapes all report 15 phantom findings.
  mk shortcircuit 'G=""
cleanup() { rm -rf "$G"; }
trap cleanup EXIT
mint() { G="/tmp/cell"; }
mint || true'
  ck shortcircuit 0 '`||` is not a pipe: no phantom pipeline finding' --shapes all

  # A file with no trap at all is skipped by the population filter — and must stay clean, not error.
  mk notrap 'G=""
mint() { G="/tmp/cell"; }
r="$(mint)"'
  ck notrap 0 'a file that installs no trap cannot exhibit the class'

  # An unscannable input must be LOUD (2), never clean (0).
  ck /nonexistent-case 2 'a missing file exits 2 — unusable, never silent-green'

  if [ "$fails" = 0 ]; then echo "subshell-cleanup-lint: --selftest PASS"; exit 0; fi
  echo "subshell-cleanup-lint: --selftest FAILED ($fails)" >&2; exit 1
fi

# ── --mutants: proof of NON-BLINDNESS on the real corpus, not on fixtures ─────────────────────────
# The complaint that produced this lint was not that the old one was wrong — it was that its CLEAN
# result was a NON-VERDICT, because it could not find the instance already in hand. Fixtures cannot
# retire that complaint: they test the shapes the author thought of, on files the author wrote. This
# does it on the shipped corpus. For every file that installs a NAMED trap handler, it injects THAT
# FILE'S OWN trap-consulted global into a function THAT FILE ALREADY calls through `$( )`, and
# requires the lint to catch it. A file whose real form is clean but whose mutant is missed is BLIND,
# and that is the only outcome here that is a defect in the lint.
#
# Nothing is hand-listed — both the global and the target function are derived per file. The first
# version of this harness DID hand-list them, and "found" blindness in reaper-e2e.sh by injecting
# LOCK_DIR, a name that file never uses: a wrong control reads exactly like a blind detector, so the
# control must be derived from the same file it judges.
if [ "$MUTANTS" = 1 ]; then
  md="$(mktemp -d)" || exit 2
  trap 'rm -rf "$md"' EXIT
  ok=0; blind=0; live=0; skip=0
  printf '%-44s %-20s %-18s %s\n' FILE GLOBAL 'VIA $( )' VERDICT
  while IFS= read -r sf; do
    [ -f "$sf" ] || continue
    LC_ALL=C /usr/bin/grep -qE '^[ \t]*trap[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+(EXIT|INT|TERM|ERR|HUP)' "$sf" || continue
    rel="${sf#"$ROOT"/}"
    # the global a named handler consults on a line that destroys something
    g="$(LC_ALL=C awk '
      /^[ \t]*trap[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+(EXIT|INT|TERM|ERR|HUP)/ {
        h=$0; sub(/^[ \t]*trap[ \t]+/,"",h); sub(/[ \t].*$/,"",h); H[h]=1; next }
      { L[NR]=$0 }
      END { for (h in H) { inb=0
          for (i=1;i<=NR;i++) {
            if (L[i] ~ ("^[ \t]*" h "[ \t]*\\(\\)[ \t]*\\{")) inb=1
            else if (inb && L[i] ~ /^[ \t]*\}/) inb=0
            if (!inb || L[i] !~ /(rm[ \t]+-|rmdir|kill|worktree[ \t]+remove|close-window|bootout)/) continue
            t=L[i]
            while (match(t, /\$\{?[A-Za-z_][A-Za-z0-9_]*/)) {
              v=substr(t,RSTART,RLENGTH); sub(/^\$\{?/,"",v)
              if (v !~ /^([0-9]|HOME|PWD|IFS|[a-z])$/) { print v; exit }
              t=substr(t,RSTART+RLENGTH) } } } }' "$sf")"
    # a MULTI-LINE function this file already calls through a substitution
    fn="$(LC_ALL=C awk '
      /^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)[ \t]*\{[ \t]*$/ {
        n=$0; sub(/^[ \t]*/,"",n); sub(/[ \t]*\(\).*$/,"",n); ML[n]=1; next }
      { line=$0
        while (match(line, /\$\([ \t]*[A-Za-z_][A-Za-z0-9_]*/)) {
          t=substr(line,RSTART,RLENGTH); sub(/^\$\([ \t]*/,"",t)
          if (t in ML) { print t; exit }
          line=substr(line,RSTART+RLENGTH) } }' "$sf")"
    if [ -z "$g" ] || [ -z "$fn" ]; then
      printf '%-44s %-20s %-18s %s\n' "$rel" "${g:--}" "${fn:--}" "not testable"
      skip=$((skip + 1)); continue
    fi
    bash "$_self" "$sf" >/dev/null 2>&1 || { printf '%-44s %-20s %-18s %s\n' "$rel" "$g" "$fn" "LIVE FINDING"; live=$((live + 1)); continue; }
    mf="$md/$(basename "$sf").mutant"
    LC_ALL=C awk -v fn="$fn" -v g="$g" '
      !d && $0 ~ ("^[ \t]*" fn "[ \t]*\\(\\)[ \t]*\\{[ \t]*$") { print; printf "  %s=\"/tmp/mutant\"\n", g; d=1; next }
      { print }' "$sf" > "$mf"
    if bash "$_self" "$mf" >/dev/null 2>&1; then
      printf '%-44s %-20s %-18s %s\n' "$rel" "$g" "$fn" "BLIND — mutant NOT caught"
      blind=$((blind + 1))
    else
      printf '%-44s %-20s %-18s %s\n' "$rel" "$g" "$fn" "ok"
      ok=$((ok + 1))
    fi
  done <<EOF
$(enumerate)
EOF
  printf '\nsubshell-cleanup-lint --mutants: ok=%s blind=%s live=%s not-testable=%s\n' "$ok" "$blind" "$live" "$skip"
  # A floor on the TESTABLE count, not just blind=0: as the corpus changes, files can drift out of
  # testability, and a guard that quietly ends up proving nothing is the failure this whole lint
  # exists to prevent. Zero blind AND enough files actually exercised, or this is not a pass.
  [ "$blind" = 0 ] && [ "$live" = 0 ] && [ "$ok" -ge 5 ] && exit 0
  echo "subshell-cleanup-lint: --mutants FAILED (blind=$blind live=$live testable=$ok, floor 5)" >&2
  exit 1
fi

if [ "${#FILES[@]}" -eq 0 ]; then
  while IFS= read -r f; do [ -n "$f" ] && FILES+=("$f"); done <<EOF
$(enumerate)
EOF
fi
if [ "$LIST" = 1 ]; then printf '%s\n' "${FILES[@]}"; exit 0; fi
if [ "${#FILES[@]}" -eq 0 ]; then echo "subshell-cleanup-lint: ⛔ no files to scan" >&2; exit 2; fi
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "subshell-cleanup-lint: ⛔ no such file: $f" >&2; exit 2; }
done

scan_files "${FILES[@]}"; rc=$?
[ "$rc" = 0 ] || exit "$rc"
# The population is reported as parsed/total, never as a bare "clean": a filter that silently
# narrowed what it looked at would make this line a claim about a smaller repo than the one shipped.
[ "$JSON" = 1 ] || printf 'subshell-cleanup-lint: clean — %s file(s) parsed of %s scanned (the rest install no trap, so the class is impossible in them)\n' \
  "${POP##* }" "${POP%% *}"
exit 0
