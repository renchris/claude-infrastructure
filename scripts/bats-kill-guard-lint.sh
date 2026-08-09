#!/bin/bash
# bats-kill-guard-lint — the load-flake class that has been fixed BY HAND nine times and never once
# by a gate: a process-kill in a .bats file whose stderr is silenced and whose exit STATUS is not.
#
# THE DEFECT, measured rather than reasoned about (f676d2f6, on /bin/bash 3.2.57, which is what bats
# runs here):
#     child ALIVE                    -> kill rc 0
#     child exited, UNREAPED zombie  -> kill rc 0     <- why it looks fine at idle
#     child exited AND reaped        -> kill rc 1     ESRCH
# The window opens after the REAP, not the exit, so it needs LOAD to show and never reproduces in
# isolation. Under bats' errexit that rc 1 aborts the enclosing body — a test that passed on its own
# merits goes red, or worse, a fixture aborts mid-way and leaves a TRUNCATED file the rest of the
# suite then misreads. It cost a refused push once already: the bats retry's extra executed count
# tripped the gate's own 1614≠1613 plan mismatch (debc016f).
#
# WHY A LINT, AND WHY NOW — and the answer is measured, not argued. The remedy is one token
# (`|| true`) and it has been applied NINE times across four commits: debc016f (land-lock),
# 956f4545 (one site; that sha is unreachable in this repo, rebase-dropped, but its sibling commits
# are present and its effect is verifiable by content), e90476e6 (six sites), f676d2f6
# (session-end-gc-lock). Each was a human who had just spent a session diagnosing a flake from
# scratch. Nothing in the gate ever looked for it.
#
# So the class simply came back. Dating every site alive on 2026-08-09 against the sweep that was
# supposed to have ended it (e90476e6, 2026-07-31):
#     2026-08-08  cc-await-ping.bats:460, :470, :479      written a week AFTER the sweep
#     2026-08-08  postland-verify-bisect-bound.bats:583   (two pkills on the one line)
#     2026-08-07  cc-backlog-condition-lease.bats:46
#     2026-08-05  cc-teardown-assignee-adopt.bats:368
#     2026-07-31  terminal-bench.bats:331, :332 · git-worktree-guard.bats:26 · cc-pane-headless.bats:46
# Eleven sites in nine days — six of them typed after the sweep, four on the sweep's own day and
# missed by it. That is the whole argument for a gate over a sweep: a sweep is a snapshot, and this
# class regenerates because the defective spelling is the natural one to type. The commit adding
# this lint guards all eleven, so the baseline is zero and the rule can be strict.
#
# THE RULE, stated as an idea rather than a list of spellings. A kill is a violation when the author
# has SILENCED THE DIAGNOSTIC BUT NOT THE STATUS:
#   · it is a signal-sending kill/pkill/killall in COMMAND POSITION (not an argument, not prose);
#   · its stderr is redirected away — the author's own admission that failure is expected;
#   · its exit status is NOT consumed (no `||`, not an if/while condition, not `run`, not negated);
#   · and it is not already on a failing path.
# Naming the CONTRADICTION rather than the token is what keeps this from being a denylist of
# spellings: a new way to write "kill a pid that may be gone" still trips it, and a deliberate
# assertion never does (memory: denylist-enumerates-spellings-not-the-class).
#
# THE TWO EXEMPTIONS, both measured against the real corpus, both with their own positive control in
# --selftest, because an exemption that is never proven to be narrow is just a hole:
#
#   1. STDERR NOT REDIRECTED ⇒ an ASSERTION, not cleanup. tests/cc-pane-headless.bats:195 is
#      `kill -9 "$pid"` on a `sleep 30` the test spawned two lines earlier: the kill MUST succeed,
#      its failure SHOULD red the test, and `|| true` there would delete a real assertion. The
#      author who wants to hear about it does not redirect stderr. This is the discriminator that
#      separates the 11 real sites from the 3 false ones, and it is the same signal every one of the
#      hand-fixed sites carried (every one: `2>/dev/null` present, `||` absent).
#
#   2. A PATH THAT ALREADY ENDS IN AN UNCONDITIONAL FAILURE. The corpus's commonest kill shape is
#      the failure diagnostic: `[ … ] || { echo "what went wrong"; kill "$holder" 2>/dev/null; false; }`
#      — twenty of them, including several in session-end-gc-lock.bats, whose author fixed that
#      file's deadpid helper in the very same commit and left these alone. Correctly: the group runs
#      ONLY when the assertion has already failed, and it ends in `false`, so the kill aborting early
#      changes the rc not at all. The exemption is self-justifying rather than heuristic — a path
#      terminating in an unconditional `false` IS a failing path however it was reached — but it is
#      still controlled in both directions, because an over-broad abstain deletes the common case
#      (memory: abstain-rule-can-retire-the-common-case).
#
# `kill -0` IS DELIBERATELY OUT OF SCOPE. It sends no signal; it is the corpus's liveness-probe idiom
# and is normally the assertion itself (`kill -0 "$wpid"` = "the recorded pid is a LIVE process").
# Guarding one would invert its meaning. A -0 probe that wants to be non-fatal is already written
# `if kill -0 … ; then`, which the command-position rule exempts anyway.
#
# HEREDOC BODIES ARE DATA, AND GETTING THIS WRONG IS HOW THE LINT GOES BLIND. A fixture writing a
# stub script (`cat > s.sh <<EOF … kill $1 2>/dev/null … EOF`) is not writing bats commands. But the
# first draft of this file detected the opener on the RAW line, so `printf 'cat <<EOF\n'` — a
# heredoc mentioned INSIDE a string — opened one that never closed and swallowed the remaining 8,667
# lines of the corpus (8.3%), taking four genuine defects with it and leaving a confident clean
# verdict over the hole. Openers are therefore detected on the QUOTE-STRIPPED line, and --selftest
# pins that exact regression (memory: lint-blindness-composes-and-hides-the-next-defect).
#
# STRICT, WHOLE-CORPUS, NO GRANDFATHER LIST. The three sibling ratchets grandfather inherited debt
# because their corpora are dirty; this one does not, because the same commit that adds it takes the
# corpus to ZERO. A clean baseline makes the strictest rule the free one — you may not add a site
# ANYWHERE — and it leaves no exemption list to rot silently (the failure mode
# test-hermeticity-lint's own comment warns a ratchet must never become).
#
# Exit: 0 = clean · 1 = a violation OR an UNREADABLE file · 2 = bad usage / nothing scannable (LOUD,
# never silent-green — a lint that could not run must not read like a lint that found nothing). The
# third state is why 1 covers both: a file the scanner could not read to the end yields no verdict at
# all, and a non-verdict must never be reported as clean.
#
# Env seams: CC_BATS_KILL_GUARD=off disables it entirely (the repo's standard kill switch, with a
# positive control in --selftest so "off" can never be what a green verdict means).
# Every fixture below is /Users/chrisren/.claude/bin/cc-bats SOURCE written literally, so the un-expanded `$p` / `${PROBE_PID:-}`
# are the defects under test and the single quotes are load-bearing. Declared once at file level
# rather than annotated twenty-one times; the sibling .bats ratchet excludes the same code for
# the same reason (its header calls these fixtures-building-shell-source-as-a-string).
# shellcheck disable=SC2016
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
# Resolved through $0's symlinks exactly as the sibling lints do: everything under ~/.claude/scripts/
# is a per-file symlink into this checkout, so a bare `dirname "$0"` yields ~/.claude, which has no
# tests/ (memory: self-identity-guard-must-fully-resolve).

# ── the detector ──────────────────────────────────────────────────────────────────────────────────
# One awk pass. Emits `path:line:col:text` per violating kill — per KILL, not per line, because
# tests/postland-verify-bisect-bound.bats:583 carries two on one line and a per-line report would
# under-count the fix (memory: per-site-mutation-attributes-coverage).
# Read from a QUOTED heredoc, and NOT via `$(cat <<EOF)`. Two drafts died on shell quoting before
# this shape: first a single-quoted string, which an APOSTROPHE in one of the comments below
# silently ended mid-program; then a heredoc inside a command substitution, which /bin/bash 3.2
# (what this shebang gets on macOS) still scans for quotes — so the awk regex /^'[^']*'/, with
# its odd apostrophe count, broke the file at a line 400 away from the cause. `read -r -d ''`
# involves no command substitution at all, so the body is inert text to the shell and the awk
# source can contain any quoting it likes.
IFS='' read -r -d '' DETECT <<'AWK_DETECT' || true

function blanks(n,   s) { s = sprintf("%*s", n, ""); return s }

# Blank quoted spans and comments, PRESERVING LENGTH so every column index stays true to the raw
# line, and CARRYING THE QUOTE STATE ACROSS LINES.
#
# The carry is not a refinement, it is the difference between a lint and a false-alarm generator.
# This corpus writes bats fixtures as multi-line single-quoted strings —
#     mkb bad '@test "x" {
#       kill -9 "$pid" 2>/dev/null
#     }'
# — so the kill sits on its own line, unindented by any quote THAT LINE can see. A per-line stripper
# reads it as a live command and flags a suite that is merely DESCRIBING one. This suite is itself
# the proof: written against the per-line version, it reported its own fixtures as corpus defects.
#
# Comments are consumed in the same pass, and that ordering is load-bearing in the other direction:
# strip them earlier and a `#` inside a string ends the line early; strip them later and an
# apostrophe in a prose comment (`# the kill's status`) opens a string that never closes and
# blanks the rest of the FILE. Neither is detectable from the outside — both just go quiet.
# COMMAND SUBSTITUTION RE-OPENS AN UNQUOTED CONTEXT, so the state is a STACK, not a flag. Inside
# double quotes, `$(` starts fresh quoting: in
#     run runhook "$(mkfix "You'll need to run gcloud auth login yourself")"
# the second `"` OPENS a new string rather than closing the first, and the apostrophe in "You'll" is
# inside it. A flat flag reads that line as closing the outer string and then opening one on the
# apostrophe, which never closes — and every line to EOF is blanked. Fifteen suites (4.2% of the
# corpus) ended mid-string that way, each a silent NON-VERDICT. The stack is what makes the count
# zero, which is the only reading of "clean" this lint is entitled to.
function strip_stateful(s,   out, i, L, c, prev, nxt) {
  out = ""; L = length(s)
  for (i = 1; i <= L; i++) {
    c = substr(s, i, 1); prev = (i > 1 ? substr(s, i-1, 1) : ""); nxt = substr(s, i+1, 1)
    if (qs == 0) {
      if (c == "\\") { out = out "  "; i++; continue }
      if (c == "#" && (i == 1 || prev ~ /[[:space:];&|(){}]/)) break
      if (c == "$" && nxt == "'") { qs = 4; out = out "  "; i++; continue }
      if (c == "'") { qs = 1; out = out " "; continue }
      if (c == "\"") { qs = 2; out = out " "; continue }
      if (c == "`") { qdepth++; qstack[qdepth] = 0; qs = 3; out = out " "; continue }
      if (c == "$" && nxt == "(") { qdepth++; qstack[qdepth] = 0; out = out c; continue }
      if (c == ")" && qdepth > 0) { qs = qstack[qdepth]; qdepth--; out = out c; continue }
      out = out c; continue
    }
    if (qs == 1) { if (c == "'") qs = 0; out = out " "; continue }
    if (qs == 4) {                       # $'...' — backslash escapes are real in here, so \' is NOT a close
      if (c == "\\") { out = out "  "; i++; continue }
      if (c == "'") qs = 0
      out = out " "; continue
    }
    if (qs == 3) { if (c == "`" && prev != "\\") { qs = qstack[qdepth]; if (qdepth > 0) qdepth-- } out = out " "; continue }
    # qs == 2
    if (c == "\\") { out = out "  "; i++; continue }
    if (c == "$" && nxt == "(") { qdepth++; qstack[qdepth] = 2; qs = 0; out = out " "; continue }
    if (c == "`") { qdepth++; qstack[qdepth] = 2; qs = 3; out = out " "; continue }
    if (c == "\"") qs = 0
    out = out " "
  }
  while (length(out) < L) out = out " "
  return out
}

# Event scan: control operators and their nesting depth. A `&` that is part of a redirection
# (`2>&1`, `&>`, `>&2`) is NOT an operator — reading it as one was what made `… 2>&1 || true` look
# unguarded in an early draft.
function scan(s,   i, L, c1, c2, prev) {
  ne = 0; depth = 0; i = 1; L = length(s)
  while (i <= L) {
    c1 = substr(s, i, 1); c2 = substr(s, i, 2); prev = (i > 1 ? substr(s, i-1, 1) : "")
    if (c1 == "(" || c1 == "{") { depth++; i++; continue }
    if (c1 == ")" || c1 == "}") { if (depth > 0) depth--; i++; continue }
    if (c2 == "||" || c2 == "&&") { ne++; ev_pos[ne]=i; ev_dep[ne]=depth; ev_kind[ne]=(c2=="||"?"OR":"AND"); i+=2; continue }
    if (c1 == "&") {
      if (prev == ">" || prev == "<" || substr(s, i+1, 1) == ">") { i++; continue }
      ne++; ev_pos[ne]=i; ev_dep[ne]=depth; ev_kind[ne]="SEP"; i++; continue
    }
    if (c1 == ";" || c1 == "|") { ne++; ev_pos[ne]=i; ev_dep[ne]=depth; ev_kind[ne]="SEP"; i++; continue }
    i++
  }
}

function depth_at(s, p,   i, c, d) {
  d = 0
  for (i = 1; i < p; i++) { c = substr(s, i, 1); if (c=="(" || c=="{") d++; else if ((c==")" || c=="}") && d>0) d-- }
  return d
}

# Is the kill at p the HEAD of a simple command? Preceded by a bare word ⇒ it is an ARGUMENT
# (`bash "$HOOK" kill`, `grep -E "…|kill -9|…"`), which is how the @test titles and the pkill-scope
# fixtures stop being 90% of the report.
function cmdpos(s, p,   before) {
  before = substr(s, 1, p - 1)
  sub(/[[:space:]]+$/, "", before)
  while (match(before, /(time|command|builtin|sudo|exec)$/)) {
    sub(/(time|command|builtin|sudo|exec)$/, "", before); sub(/[[:space:]]+$/, "", before)
  }
  if (before == "") return 1
  if (before ~ /!$/) return 0
  if (before ~ /(^|[[:space:];&|(){}])(if|while|until|elif|run|refute|assert|assert_success|assert_failure)$/) return 0
  if (before ~ /(^|[[:space:]])(then|do|else)$/) return 1
  if (before ~ /[;&|(){}]$/) return 1
  return 0
}

# Guarded means: the innermost AND-OR list enclosing the kill has ITS OWN status consumed by a `||`,
# at the nesting level of the kill or at any enclosing one. Two subtleties, both of which this lint
# got wrong first and both of which the real corpus caught:
#
#   · `&&` is TRANSPARENT here, not a terminator. POSIX: "-e shall be ignored when executing any
#     command of an AND-OR list other than the last", and in `a && b || true` the last command is
#     `true`, so a failing `a` is exempt. Treating `&&` as a terminator made
#     `[ -n "$P" ] && kill … && wait … || true` (git-worktree-guard.bats:26, as its fix leaves it)
#     read as unguarded — the lint flagging a line that was already correct.
#   · but a `&&` chain with NOTHING consuming it is still a violation, because a failing kill
#     short-circuits the list and the rc OF THE LIST becomes the rc of the kill. That is the shape
#     e90476e6 measured: `[ -n "$p" ] && kill "$p" 2>/dev/null` aborts, and a trailing `; true` does
#     not shield it, because it never runs.
# So what matters is never the operator immediately after the kill — it is whether the LIST the kill
# belongs to is spoken for. `;`, `&` and `|` end that list; `&&` extends it; `||` consumes it.
# Enclosing levels count too, which is how `{ kill "$F" && wait "$F"; } 2>/dev/null || true` is
# correctly clean: errexit suppression propagates into a compound whose own status is consumed.
function guarded(s, p,   d, e, j) {
  d = depth_at(s, p)
  for (e = 0; e <= d; e++) {
    for (j = 1; j <= ne; j++) {
      if (ev_pos[j] <= p || ev_dep[j] != e) continue
      if (ev_kind[j] == "OR") return 1
      if (ev_kind[j] == "AND") continue
      break
    }
  }
  return 0
}

# Does this kill sit on a path that ALREADY ends in an unconditional failure? Then its own rc cannot
# turn a green test red, and `|| true` would buy nothing.
function already_red(s, p,   d, i, j, tail, seg) {
  d = depth_at(s, p)
  tail = substr(s, p)
  # every segment after the kill, until the enclosing group closes
  for (i = 1; i <= ne; i++) {
    if (ev_pos[i] <= p) continue
    if (ev_dep[i] < d) break
    seg = substr(s, ev_pos[i] + (ev_kind[i] == "OR" || (substr(s, ev_pos[i], 2) == "&&") ? 2 : 1))
    sub(/^[[:space:]]*/, "", seg)
    if (seg ~ /^(false|exit[[:space:]]+[1-9]|return[[:space:]]+[1-9])([[:space:]]|;|$|\})/) return 1
  }
  return 0
}

# The author redirected the diagnostic away: 2>…, &>…, >&… . The FORM is not the point (a log file
# is the same admission as /dev/null); the admission is.
function stderr_silenced(s, p,   seg, i, stop) {
  stop = length(s) + 1
  for (i = 1; i <= ne; i++) if (ev_pos[i] > p && ev_pos[i] < stop) stop = ev_pos[i]
  seg = substr(s, p, stop - p)
  if (seg ~ /2[[:space:]]*>/) return 1
  if (seg ~ /&[[:space:]]*>/) return 1
  if (seg ~ />[[:space:]]*&/) return 1
  return 0
}

# THE THIRD STATE. If a file ends with the quote scanner still inside a string, every line after the
# opener was blanked and this file yielded NO VERDICT — not a clean one. Reported separately and
# loudly for the same reason bats-shellcheck-lint reports an UNANALYZABLE suite: the absence of
# findings in a file nothing could read is not evidence of anything
# (memory: claimed-outcome-vs-checked-outcome). Emitted at the NEXT file's first line and at END,
# because ENDFILE is a gawk extension and this must run on the BSD awk that ships with macOS.
FNR == 1 {
  if (prevfile != "" && qs != 0) printf "UNBALANCED\t%s\n", prevfile
  prevfile = FILENAME; hd = ""; qs = 0; qdepth = 0
}
END { if (prevfile != "" && qs != 0) printf "UNBALANCED\t%s\n", prevfile }
{
  raw = $0

  # RESYNC — the blast radius of a mis-parse is one @test, not the rest of the file. A line that
  # begins `@test ` or `}` in COLUMN ZERO is top-level /Users/chrisren/.claude/bin/cc-bats structure; nothing inside a quoted string
  # in this corpus starts that way, because an embedded fixture is always indented. Without this, one
  # construct the scanner reads wrongly (a nested shell-in-shell fixture, say) silently blanks every
  # line to EOF — the same unbounded blindness the heredoc bug had, arriving by a different door.
  # With it, the worst case is one unreadable test body, and the third state below still says so.
  if (hd == "" && raw ~ /^(@test |})/) { qs = 0; qdepth = 0 }

  s = strip_stateful(raw)

  # Heredoc bodies are data. The opener is looked for in the STRIPPED line — see the header; finding
  # it in the raw line is what blinded 8.3% of the corpus.
  if (hd != "") {
    t = raw; sub(/^[[:space:]]+/, "", t); sub(/[[:space:]]+$/, "", t)
    if (t == hd) hd = ""
    next
  }
  # The `<<` is located in the STRIPPED line — that is what proves it is a real operator and not a
  # heredoc MENTIONED inside a string — but the DELIMITER is read from the RAW line at that offset,
  # because a quoted delimiter (`<<'EOF'`, the commonest form here) has just been blanked away.
  # Reading it from the stripped line found no name, opened no heredoc, and handed the body to the
  # detector as live code; the apostrophes in that prose then wrecked the quote state for the rest of
  # the file. Both halves of this class fail silently, which is why the third state below exists.
  if (match(s, /<<-?/) && substr(s, RSTART, 3) != "<<<") {
    hrest = substr(raw, RSTART + RLENGTH)
    sub(/^[[:space:]]*/, "", hrest)
    m = ""
    if (match(hrest, /^'[^']*'/) || match(hrest, /^"[^"]*"/)) m = substr(hrest, 2, RLENGTH - 2)
    else if (match(hrest, /^\\?[A-Za-z_][A-Za-z0-9_]*/)) { m = substr(hrest, RSTART, RLENGTH); sub(/^\\/, "", m) }
    if (m != "") { hd = m; next }
  }

  if (s !~ /(kill|pkill|killall)/) next
  scan(s)

  off = 0
  while (1) {
    rest = substr(s, off + 1)
    if (!match(rest, /(kill|pkill|killall)/)) break
    p = off + RSTART; w = RLENGTH
    off = p + w - 1
    if (substr(s, p + w, 1) ~ /[A-Za-z0-9_-]/) continue
    if (p > 1 && substr(s, p - 1, 1) ~ /[A-Za-z0-9_.\/-]/) continue
    if (!cmdpos(s, p)) continue
    if (substr(s, p) ~ /^kill[[:space:]]+-0([[:space:]]|$)/) continue
    if (!stderr_silenced(s, p)) continue
    if (guarded(s, p)) continue
    if (already_red(s, p)) continue
    printf "%s:%d:%d: %s\n", FILENAME, FNR, p, raw
  }
}
AWK_DETECT


# detect <file>... → violations, one per line, as "path:line:col: <source>"
detect() { awk "$DETECT" "$@" 2>/dev/null; }

# collect_bats <target>... → .bats paths (a target may be a dir or a file)
collect_bats() {
  local t
  for t in "$@"; do
    if [ -d "$t" ]; then find "$t" -type f -name '*.bats' 2>/dev/null
    elif [ -f "$t" ]; then printf '%s\n' "$t"
    fi
  done
}

# lint_files <file>... → 0 clean · 1 violation · 2 nothing scannable
lint_files() {
  local f out bad=0 seen=0 unreadable=0
  local files=()
  for f in "$@"; do [ -f "$f" ] || continue; files+=("$f"); seen=$((seen + 1)); done
  [ "$seen" -gt 0 ] || { echo "bats-kill-guard-lint: ⛔ no .bats file to scan" >&2; return 2; }

  out="$(detect "${files[@]}")"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      UNBALANCED*)
        printf '  UNREADABLE %s — ends inside an unterminated string; nothing after that point was scanned\n' "${line#UNBALANCED	}"
        unreadable=$((unreadable + 1))
        ;;
      *)
        printf '  KILL-GUARD %s\n' "$line"
        bad=$((bad + 1))
        ;;
    esac
  done <<EOF
$out
EOF

  # An UNREADABLE file is a NON-VERDICT, and it fails CLOSED. The clean line below would otherwise be
  # asserting "no unguarded kill" over a file whose second half was never read — the same shape as a
  # damping marker on a fake success (memory: claimed-outcome-vs-checked-outcome). It blocks rather
  # than warns because the corpus baseline is zero, so the strict reading costs nothing today and the
  # resync above bounds any future case to one test body.
  if [ "$unreadable" -gt 0 ]; then
    echo "bats-kill-guard-lint: ⛔ $unreadable file(s) above could not be read to the end, so their"
    echo "  clean verdict would be a claim about lines nobody scanned. Usually an unbalanced quote in"
    echo "  a fixture; the scanner resyncs at a column-zero '@test ' or '}', so a file reaching EOF"
    echo "  still open has one that spans the rest of the file."
  fi

  if [ "$bad" -gt 0 ]; then
    echo "bats-kill-guard-lint: ⛔ $bad unguarded kill(s) above — stderr silenced, exit status not."
    echo "  Under bats' errexit a kill whose target was already REAPED returns 1 and aborts the body,"
    echo "  so a test that passed on its own merits goes red under load (and only under load)."
    echo "  Fix: guard the status the same way you guarded the noise —"
    echo "      kill \"\$p\" 2>/dev/null || true"
    echo "  A trailing '; true' does NOT shield it (it never runs), and neither does '&&' — the kill"
    echo "  is the last command of the AND-list, so errexit is not exempt there. If the kill is an"
    echo "  ASSERTION that the target is alive, drop the stderr redirect and let it speak."
    return 1
  fi
  [ "$unreadable" -eq 0 ] || return 1
  echo "bats-kill-guard-lint: clean — $seen suite(s) scanned, 0 unguarded kill(s), 0 unreadable."
  return 0
}

# ── --selftest: every case proves a RED path fires or a GREEN path does not, in BOTH directions ────
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)" || { echo "bats-kill-guard-lint --selftest: ⛔ mktemp failed" >&2; exit 2; }
  trap 'rm -rf "$d"' EXIT
  fails=0
  # printf, never a heredoc: bats' preprocessor strips `@test` inside one, which yields a vacuously
  # green fixture (the fixture-shape-parity scar).
  mkb() { printf '#!/usr/bin/env bats\n%s\n' "$2" > "$d/$1.bats"; }
  chk() { # <fixture> <expected-rc> <message>
    local rc; lint_files "$d/$1.bats" >/dev/null 2>&1; rc=$?
    [ "$rc" -eq "$2" ] || { echo "SELFTEST FAIL: $3 (rc $rc, expected $2)"; fails=1; }
  }

  # ── THE REAL ARTIFACTS. Every RED fixture below is a byte-for-byte replay of a line that actually
  # flaked, taken from the commit that fixed it, and every GREEN one is that same line as the fix
  # left it. A control that hand-approximates its subject passes vacuously
  # (memory: control-must-replay-the-real-artifact); these cannot, because the pair differs by
  # exactly the one token under test.
  mkb red_deadpid   'deadpid() { sleep 1 & local p=$!; kill "$p" 2>/dev/null; wait "$p" 2>/dev/null || true; echo "$p"; }'
  mkb green_deadpid 'deadpid() { sleep 1 & local p=$!; kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; echo "$p"; }'
  chk red_deadpid   1 "f676d2f6's deadpid helper — the line that flaked 1-in-3 at loadavg 13 — was not caught"
  chk green_deadpid 0 "the SAME helper as f676d2f6 fixed it went red — the lint does not accept its own remedy"

  mkb red_and    'teardown() { [ -n "${HOLDER_PID:-}" ] && kill "$HOLDER_PID" 2>/dev/null; true; }'
  mkb green_and  'teardown() { [ -n "${HOLDER_PID:-}" ] && kill "$HOLDER_PID" 2>/dev/null || true; }'
  chk red_and   1 "e90476e6's teardown shape (final && operand, trailing '; true') was not caught"
  chk green_and 0 "the guarded teardown went red"

  mkb red_loop   'teardown() { while read -r p; do [ -n "$p" ] && kill "$p" 2>/dev/null; done < "$D/pids"; }'
  mkb green_loop 'teardown() { while read -r p; do [ -n "$p" ] && kill "$p" 2>/dev/null || true; done < "$D/pids"; }'
  chk red_loop   1 "a kill inside a while-do body was not caught (the do-keyword position is command position)"
  chk green_loop 0 "the guarded loop body went red"

  mkb red_pkill   'teardown() { pkill -f "$WEDGE" 2>/dev/null; sleep 1; pkill -9 -f "$WEDGE" 2>/dev/null; }'
  chk red_pkill 1 "pkill was not caught — the class is the CONTRADICTION, not the spelling 'kill'"
  # …and BOTH of that line's pkills must be reported, not just the first: a per-line report would
  # under-count what a fix has to touch.
  n_pk="$(detect "$d/red_pkill.bats" | grep -c . || true)"
  [ "${n_pk:-0}" -eq 2 ] || { echo "SELFTEST FAIL: a 2-kill line reported ${n_pk:-0} finding(s), not 2 — per-site attribution lost"; fails=1; }

  # ── EXEMPTION 1 and its positive control: silence is the discriminator, so the SAME kill must be
  # red with the redirect and green without it. Proving only the green half would leave an exemption
  # that could quietly widen to everything (memory: guard-proxy-fails-in-both-directions).
  mkb green_assert '@test "x" {
  id="$(spawn -- sleep 30)"
  kill -9 "$pid"
}'
  mkb red_assert   '@test "x" {
  id="$(spawn -- sleep 30)"
  kill -9 "$pid" 2>/dev/null
}'
  chk green_assert 0 "an ASSERTION kill (stderr NOT redirected) was flagged — cc-pane-headless.bats:195's real shape"
  chk red_assert   1 "the same kill WITH stderr silenced went unflagged — the discriminator is inert"

  # ── EXEMPTION 2 and its positive control, both directions. Drop the `false` and the identical
  # line must go red, or the abstain has retired the common case.
  mkb green_failpath '@test "x" {
  [ "$status" -eq 1 ] || { echo "STOLE the lock from a live holder"; kill "$holder" 2>/dev/null; false; }
}'
  mkb red_failpath   '@test "x" {
  [ "$status" -eq 1 ] || { echo "STOLE the lock from a live holder"; kill "$holder" 2>/dev/null; }
}'
  chk green_failpath 0 "a kill on an already-failing path was flagged — session-end-gc-lock's real diagnostic shape"
  chk red_failpath   1 "the same group WITHOUT the terminal false went unflagged — the exemption is unbounded"

  # ── kill -0 is a probe, not a signal ───────────────────────────────────────────────────────────
  mkb green_probe '@test "x" {
  kill -0 "$wpid" 2>/dev/null
}'
  chk green_probe 0 "a kill -0 liveness probe was flagged — guarding one inverts its meaning"

  # ── the guard forms that DO consume the status ────────────────────────────────────────────────
  mkb green_group 'teardown() { { kill "$FOREIGN" && wait "$FOREIGN"; } 2>/dev/null || true; }'
  chk green_group 0 "a brace group guarded by a trailing || was flagged — errexit suppression propagates in"
  # The AND-OR list rule, both directions, on the REAL line git-worktree-guard.bats:26 carries. `&&`
  # extends the list rather than ending it, so the trailing `|| true` speaks for the kill too; drop
  # that one token and the identical chain must go red, or the transparency has become a hole.
  mkb green_andor 'teardown() { [ -n "${PROBE_PID:-}" ] && kill "$PROBE_PID" 2>/dev/null && wait "$PROBE_PID" 2>/dev/null || true; }'
  mkb red_andor   'teardown() { [ -n "${PROBE_PID:-}" ] && kill "$PROBE_PID" 2>/dev/null && wait "$PROBE_PID" 2>/dev/null; }'
  chk green_andor 0 "an && chain whose LIST is consumed by a trailing || was flagged — POSIX exempts every command of the list but the last"
  chk red_andor   1 "the same chain with NOTHING consuming it went unflagged — a failing kill short-circuits it and the rc of the list is the rc of the kill"
  mkb green_if    '@test "x" {
  if kill -TERM "$holder" 2>/dev/null; then echo gone; fi
}'
  chk green_if 0 "a kill in an if-condition was flagged — its status is consumed by the condition"

  # ── NOT a command: the shapes that made a naive detector 90% false positives ──────────────────
  mkb green_title '@test "R8 kill switch: CC_ROUTE_CLIFF_TERM=off restores pre-term scoring" {
  run true
}'
  mkb green_arg   '@test "x" {
  bash "$HOOK" kill >/dev/null 2>&1
  run grep -nE "session close|kill -9|pkill" "$S"
}'
  chk green_title 0 "a @test TITLE containing 'kill switch' was flagged as a command"
  chk green_arg   0 "'kill' as an ARGUMENT (a subcommand name, a grep pattern) was flagged as a command"

  # ── THE BLINDNESS REGRESSION. `<<EOF` inside a STRING is not a heredoc opener. Detecting it on the
  # raw line opened one that never closed and swallowed the rest of the file — 8,667 corpus lines,
  # four real defects, and a confident clean verdict over the hole. The fixture pins the shape that
  # caused it: a mention of a heredoc, then a genuine defect BELOW it.
  mkb green_heredoc_real '@test "x" {
  cat > "$D/s.sh" <<EOF
kill "$p" 2>/dev/null
EOF
  run true
}'
  chk green_heredoc_real 0 "a kill inside a REAL heredoc body was flagged — a stub script is data, not commands"
  mkb red_heredoc_string '@test "x" {
  printf '"'"'cat <<EOF\n'"'"' > "$D/w.sh"
  kill "$p" 2>/dev/null
}'
  chk red_heredoc_string 1 "a '<<EOF' inside a STRING blinded the lint to the real defect below it"

  # ── THE MULTI-LINE FIXTURE, which is what forced the quote state to carry across lines at all.
  # A suite that WRITES a defective fixture is describing a kill, not running one. The kill sits on
  # its own line with no quote that line can see, so a per-line stripper calls it a violation — and
  # this suite would then report its own fixtures as corpus defects.
  mkb green_embedded '@test "x" {
  mkb bad %@test "y" {
  kill "$p" 2>/dev/null
}%
  run true
}'
  # (% stands in for the single quote the fixture needs; substituted here so this heredoc stays
  # readable rather than drowning in escapes.)
  tr '%' "'" < "$d/green_embedded.bats" > "$d/green_embedded.tmp" && mv "$d/green_embedded.tmp" "$d/green_embedded.bats"
  chk green_embedded 0 "a kill inside a suite's own multi-line fixture string was flagged as a live command"

  # ── NESTED COMMAND SUBSTITUTION re-opens quoting, and getting it wrong blanks the rest of a file.
  # The `"` before You OPENS a string rather than closing the outer one, so the apostrophe in "You'll"
  # is inside it. Fifteen suites ended mid-string on this before the context stack; the defect BELOW
  # the nesting is what proves the file is still being read.
  mkb red_nested '@test "x" {
  run runhook "$(mkfix "Youll need to run gcloud auth login yourself")"
  kill "$p" 2>/dev/null
}'
  chk red_nested 1 "a nested command substitution blinded the lint to the defect below it"

  # ── THE THIRD STATE: a file that cannot be read to the end is a NON-VERDICT, and fails closed.
  # Both halves, because "no findings" and "nothing was scanned" are otherwise the same observation.
  printf '#!/usr/bin/env bats\n@test "x" {\n  echo "never closed\n  run true\n' > "$d/unread.bats"
  printf '#!/usr/bin/env bats\n@test "x" {\n  echo "closed"\n  run true\n' > "$d/read.bats"
  chk unread 1 "a file ending INSIDE an unterminated string passed — a clean verdict over unscanned lines"
  chk read   0 "the same fixture with the string closed went red — the third state is over-firing"
  out_unread="$(lint_files "$d/unread.bats" 2>&1)"
  case "$out_unread" in
    *UNREADABLE*) ;;
    *) echo "SELFTEST FAIL: the unreadable file was not NAMED — it must never be silently folded into the kill count"; fails=1 ;;
  esac

  # ── the kill switch, with the RED as its positive control ─────────────────────────────────────
  if CC_BATS_KILL_GUARD=off "$SELF" "$d/red_deadpid.bats" >/dev/null 2>&1; then :; else
    echo "SELFTEST FAIL: CC_BATS_KILL_GUARD=off did not disable the lint over a real RED"; fails=1
  fi
  if "$SELF" "$d/red_deadpid.bats" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: POSITIVE CONTROL — the identical run WITHOUT the kill switch was also green"; fails=1
  fi

  if [ "$fails" -eq 0 ]; then
    echo "bats-kill-guard-lint --selftest: all cases pass (RED fires, GREEN does not, both exemptions bounded)"
    exit 0
  fi
  exit 1
fi

# ── main ──────────────────────────────────────────────────────────────────────────────────────────
if [ "${CC_BATS_KILL_GUARD:-on}" = "off" ]; then
  echo "bats-kill-guard-lint: DISABLED (CC_BATS_KILL_GUARD=off)"
  exit 0
fi

targets=("$@")
[ "${#targets[@]}" -gt 0 ] || targets=("$ROOT/tests")

mapfile_bats=()
while IFS= read -r f; do [ -n "$f" ] && mapfile_bats+=("$f"); done <<EOF
$(collect_bats "${targets[@]}")
EOF

[ "${#mapfile_bats[@]}" -gt 0 ] || { echo "bats-kill-guard-lint: ⛔ no .bats file under: ${targets[*]}" >&2; exit 2; }
lint_files "${mapfile_bats[@]}"
