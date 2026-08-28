#!/bin/bash
# pipefail-sigpipe-lint — a RATCHET on `producer | early-exit-consumer` under `set -o pipefail`.
#
# THE DEFECT, and it is in-tree history rather than a hypothesis. `ec9a43a9` fixed this in
# cc-relogin-poll's capability probe:
#
#     if "$ACCOUNTS_BIN" -h 2>/dev/null | grep -q -- '--login-status'; then   # WRONG
#
# `grep -q` exits the instant it matches. The producer is then SIGPIPEd on its NEXT write, and
# `set -o pipefail` promotes that 141 to the pipeline's status — so the `if` reads FALSE for a flag
# that is plainly advertised. The poller exited 3 DETECTION-UNAVAILABLE with the surface right
# there, and separately claimed a spurious WINDOW-CAPPED that silently narrowed a declared T-7d
# window to 72h. Both were read as deploy lag for weeks.
#
# MEASURED HERE, on /bin/bash 3.2.57 (arm64-apple-darwin24), 2026-08-08 — the numbers this rule's
# scoping is derived from, not inherited:
#
#   producer shape (match early, N bytes still to write)      FALSE verdict on a MATCH
#   ────────────────────────────────────────────────────────  ────────────────────────
#   separate process, 4 writes, match on line 2                 44/400   (11%)
#   streaming external producer,   1 KiB after the match        85/100
#   streaming external producer,   8 KiB after the match        95/100
#   streaming external producer,  16 KiB after the match        99/100
#   streaming external producer, ≥32 KiB after the match       100/100
#   `printf '%s' "$VAR"` builtin, 4 KiB, match first             0/200
#   same pipeline with pipefail OFF                              0/400
#   consumer drained (`grep PAT >/dev/null`, `awk 'NR<=N'`)      0/400
#
# THE 0/200 ROW IS A MEASUREMENT OF A SIZE, NOT OF A COMMAND WORD — re-measured 2026-08-17, same
# box, /bin/bash + /usr/bin/grep, builtin `printf '%s\n' "$VAR"` with the match on the FIRST line of
# a MULTI-LINE payload (the shape every site in this tree actually uses):
#
#   `printf '%s\n' "$VAR"` builtin, 4 KiB                        0/10
#   `printf '%s\n' "$VAR"` builtin, 62 KB                        0/10
#   `printf '%s\n' "$VAR"` builtin, 64 KiB                      10/10   ← the pipe buffer
#   `printf '%s\n' "$VAR"` builtin, 96 KB / 128 KB / 269 KB     10/10
#
# The boundary is not probabilistic and it is not the grep implementation: it is the 64 KiB pipe
# buffer. One write that FITS completes before the consumer is even scheduled; one that does not
# blocks mid-write and is SIGPIPEd exactly like an external producer, deterministically. (A brief
# measured against a differently-shaped payload put the knee lower and made it look statistical —
# 7/10 at 49 KB, 10/10 at 59 KB. Same conclusion, softer edge; the sharp one above is this shape.)
#
# A variable's contents are not bounded by inspection, so the builtin exemption cannot key on the
# command WORD — it keys on the ARGUMENT. A pure LITERAL keeps the 0/200 exemption (a literal you
# can read is a length you can read, and that is what the row above actually measured); a parameter
# expansion, command substitution, or backtick does not.
#
# TWO CORRECTIONS to what docs/plans/RELOGIN_BUILD_CONTRACT.md § "The defect" carries, both
# re-measured above and both load-bearing for this rule's scope:
#
#   · The discriminator is NOT output SIZE and not "the match is not on the last line" — it is
#     whether the producer makes MORE THAN ONE WRITE after the match. A single `write(2)` under the
#     64 KiB pipe buffer completes before the consumer is even scheduled, so `printf '%s' "$BIG"`
#     is safe at 4 KiB (0/200) while a 4-line separate process fails 11% and a streaming producer
#     fails 85% at ONE kilobyte. Builtin-producer sites with a LITERAL argument are therefore not
#     violations here — but a variable-sourced one is only safe while the variable stays under the
#     buffer, which nothing enforces (see the 64 KiB re-measurement above).
#   · zsh is NOT immune. The contract attributes an early 0/300 repro to "zsh does not share bash's
#     pipefail/SIGPIPE interaction"; re-measured, `zsh -c 'set -uo pipefail; …'` on a streaming
#     producer is 400/400 FALSE — identical to bash. That 0/300 was a SINGLE-WRITE producer, i.e.
#     the safe shape, so the repro proved the wrong thing. The real lesson survives ("reproduce
#     under the shipping interpreter") but its stated cause does not.
#
# WHY A RATCHET AND NOT A FLAG-DAY. The sweep behind this lint found 615 early-exit pipe consumers
# in the 315 files that enable pipefail; 367 sit in a status-consuming position, and 138 of those
# have a streaming producer. Rewriting 138 sites across 71 files — most latent, many in live hooks —
# is a larger and less reversible change than the bug it prevents, and it is the same judgment
# self-path-lint.sh already made for its 26. So the sites standing today are grandfathered BY FILE
# WITH THEIR COUNT and the rule binds where it is free: NEW code, and any file that GROWS a new one.
#
# The count is what makes this stricter than a bare path allowlist. self-path-lint grandfathers a
# path outright, which is right for a class swept to near-zero; here the worst offenders are files
# edited every week (scripts/handoff-fire.sh, hooks/lead-crash-watchdog.sh), and an outright
# exemption would mean the lint never protects exactly the files most likely to grow a new one. So
# the list can only SHRINK: a file that gains a violation goes RED, and a file that LOSES one also
# goes RED — telling you to lower the number. That downward half is not decoration; it is what stops
# a ratchet from silently becoming a permanent exemption list (memory:
# downward-ratchet-catches-the-over-scoped-marker).
#
# THE RULE — a line violates iff ALL FIVE hold. Each clause is a measurement above, not taste:
#   1. the file enables `pipefail` (else the 141 never reaches the pipeline's status);
#   2. the pipeline's LAST stage exits early — `grep -q|-l|-m N`, `head`, `sed …q`, `read`,
#      `awk …exit`. A draining consumer (`grep -c`, plain `grep`, `awk 'NR<=N'`) cannot orphan the
#      producer and is the fix, so it must not be the trigger;
#   3. the PRODUCER is not bounded by inspection. External/streaming always counts. `echo`/`printf`/
#      `:` of a pure LITERAL is one write of a length you can read off the line, and is exempt; the
#      same builtin fed a parameter expansion, a command substitution, or a backtick is NOT, because
#      the bytes it writes are whatever the variable happens to hold — 0/10 at 62 KB, 10/10 the
#      moment the write exceeds the 64 KiB pipe buffer. The command word is identical in both cases,
#      so only the argument can discriminate;
#   4. the pipeline's status is CONSUMED — an `if`/`elif`/`while`/`until` condition, a `!` operand,
#      or (under `set -e`) a bare pipeline or a top-level `VAR=$(…)`. `local`/`declare`/`export`
#      MASK the status (the builtin's own 0 wins), and `[ -n "$( … )" ]` discards it, so neither is
#      a violation however exposed the pipeline inside looks. A pipeline that is the LAST statement
#      of a function body (or brace group) is consumed too — see 4c below;
#   5. it is NOT already mitigated by a trailing `|| true` / `|| <fallback>`, which swallows the 141
#      before anything reads it.
#
# CLAUSE 4c — THE FUNCTION-FINAL PIPELINE (2026-08-28, backlog ca97c678b18b). Clause 4 asks "does
# anything READ this pipeline's status?" and answered it by looking at THIS LINE only: a control-flow
# keyword, a `!`, a `; rc=$?`, a following `&&`, or — under errexit — the bare pipeline itself. In a
# file with no `set -e` a bare pipeline therefore read as "nobody looks", which is exactly backwards
# when the pipeline is the last statement of a function body:
#
#     port_listening() {                 # ← no set -e in this file
#       ps -p "$1" -o command= | grep -q LISTEN
#     }
#     if port_listening "$pid"; then …   # ← THE READER, and it is nowhere near the pipeline
#
# The last command's status IS the enclosing construct's status (bash: a function returns the status
# of the last command executed; a `{ … }` group likewise). So a function-final pipeline does not go
# unread — its status ESCAPES the line and is read at every call site, which may be in another file
# entirely. That is the one position where "look at this line" is structurally unable to answer
# clause 4's question, and it is the shape the tree writes most: a one-pipeline predicate function.
#
# MEASURED on this tree, 2026-08-28: census 135 → 156, twenty-one sites in sixteen files, every one a
# genuine predicate-or-extractor function ending in an early-exit stage — among them
# scripts/lead-supervisor.sh:648 (`ps … | grep -qiF "$OWNER_PAT"`), bin/cc-comms-alarm-sweep:92
# (`printf '%s\n' "$LEGACY_UUIDS" | grep -qxF "$1"`, the in_allowlist shape r14 already pins in its
# `; rc=$?` spelling) and six bats `@test` bodies, whose closing pipeline IS the test's pass/fail.
#
# SCOPE, and why it is stated as "the enclosing construct" rather than "the function". The flush test
# is a lone `}` on its own line, which in shell closes a function body or a brace group — and the
# status propagates identically out of both, so the clause is sound for either without having to
# tell them apart. It deliberately does NOT fire on `} >/dev/null` or `} || true`: the first is a
# residual (the status does propagate through a redirect) and the second is clause 5 doing its job.
# MASKED positions stay green: `local v=$(p | head -1)` as the last statement returns the `local`
# builtin's own 0, not the pipeline's, so the escape never happens — which is why consumed() now
# distinguishes MASKED (0) from merely UNREAD-ON-THIS-LINE (2) instead of collapsing both to false.
#
# THE FIX, in the order to reach for it:
#   · `p | grep -q PAT`   → `p | grep PAT >/dev/null`     — plain grep drains; 0/400
#   · `p | grep -qE PAT`  → `p | grep -E PAT >/dev/null`
#   · `p | head -N`       → `p | awk 'NR<=N'`             — drains, same bytes out; 0/400
#   · `printf '%s' "$v" | grep -q P` → `case "$v" in *P*)` — no pipe at all, and one fewer fork
#   · producer UNBOUNDED or expensive (`tail -f`, `yes`, a repo-wide `find`): do NOT drain — capture
#     first (`out=$(p)`) and match with `case`/`[[`, which is what ec9a43a9 did and costs one fewer
#     fork than the pipe it replaces.
#
# Exit: 0 = clean · 1 = violation · 2 = bad usage / unusable scan tree / unrunnable check (LOUD,
# never silent-green — a non-verdict must never read as a pass).
#
# Env seams: CC_PIPEFAIL_ALLOWLIST overrides the embedded allowlist file (selftest) ·
#            CC_PIPEFAIL_OWN narrows which files BLOCK to this land's diff (gate own-scope) ·
#            CC_PIPEFAIL_ROOT overrides the scan root (selftest fixtures).

set -uo pipefail

SELF_NAME="pipefail-sigpipe-lint"

usage() {
  cat <<'USAGE'
pipefail-sigpipe-lint — ratchet on `producer | early-exit-consumer` under set -o pipefail.

  pipefail-sigpipe-lint.sh              scan the repo, honour the allowlist
  pipefail-sigpipe-lint.sh --selftest   prove the detector still discriminates (both directions)
  pipefail-sigpipe-lint.sh --census     print every violating site, ignoring the allowlist
  pipefail-sigpipe-lint.sh --regen      print an allowlist for the tree as it stands
  pipefail-sigpipe-lint.sh --print-scope  name the population it judges, as git pathspecs

Exit: 0 clean · 1 violation · 2 could not run (never silent-green).
USAGE
}

# ── scan root ────────────────────────────────────────────────────────────────────────────────────
# Resolve $0 through symlinks before deriving anything: everything under ~/.claude/scripts is a
# per-file symlink into a checkout, so an unresolved `dirname $0/..` lands in ~/.claude, which has
# no tests/ and no .git — the lint would then scan the wrong tree and report a cheerful zero.
# (memory: self-identity-guard-must-fully-resolve; enforced repo-wide by self-path-lint.sh.)
resolve_self() {
  local p="$1" d
  while [ -L "$p" ]; do
    d="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s' "$(cd "$(dirname "$p")" && pwd)/$(basename "$p")"
}
SELF="$(resolve_self "$0")"
ROOT="${CC_PIPEFAIL_ROOT:-$(cd "$(dirname "$SELF")/.." && pwd)}"

ALLOWLIST_DEFAULT="$(dirname "$SELF")/pipefail-sigpipe-allow.txt"
ALLOWLIST="${CC_PIPEFAIL_ALLOWLIST:-$ALLOWLIST_DEFAULT}"

# ── the population, NAMED ONCE ───────────────────────────────────────────────────────────────────
# The file shapes this lint judges, as git pathspecs. scan() tests membership with in_scan_set below
# and `--print-scope` prints the same list, so the two cannot disagree.
#
# A LIST AND A LOOP RATHER THAN A `case` ALTERNATION, and that is forced rather than stylistic: a
# case pattern coming from a variable is expanded as ONE pattern — the `|` inside it is a literal,
# not an alternation separator — so a five-shape population cannot be driven from a single string
# through `case … in $VAR)`. Splitting the string and asking `case` once per shape is the only
# spelling where the scan and --print-scope read the SAME declaration. It costs one builtin match
# per shape per file over `git ls-files`, which is not measurable beside the per-file greps below.
#
# These are bash patterns AND git pathspecs at once, deliberately: both match `/` with `*` (git needs
# `:(glob)` magic before `*` stops crossing a slash), so `*.sh` covers every depth in both readings
# and `bin/*` covers the whole subtree in both.
SCAN_PATHSPECS='*.sh *.bats bin/* hooks/* scripts/*'

# Split ONCE, with globbing OFF, into the array both consumers read. The `set -f` is not cosmetic and
# it is not a style choice: scan() runs `cd "$ROOT"` before it filters, so an unguarded `for p in
# $SCAN_PATHSPECS` PATHNAME-EXPANDS every shape against the repo root — `*.sh` becomes the root's own
# .sh files (or stays literal if there are none) and `bin/*` becomes every file in bin/. The
# population then silently narrows to whatever happens to sit in the tree, which is the same
# degrade-to-advisory direction this whole flag exists to close. RED-PROVED while writing this: the
# unguarded form dropped all six docs/activation/*.sh sites from `--census`, exit 0, no diagnostic.
SCAN_PATTERNS=()
_sp_restore_f=0; case "$-" in *f*) _sp_restore_f=1 ;; esac
set -f
# shellcheck disable=SC2086  # deliberate word-split into one pattern per shape; globbing is off
for _sp in $SCAN_PATHSPECS; do SCAN_PATTERNS+=("$_sp"); done
[ "$_sp_restore_f" -eq 1 ] || set +f
unset _sp _sp_restore_f

in_scan_set() { # $1=repo-relative path → 0 if this lint judges it
  local p
  for p in "${SCAN_PATTERNS[@]}"; do
    # shellcheck disable=SC2254  # $p is a PATTERN here; quoting it would make it a literal string
    case "$1" in $p) return 0 ;; esac
  done
  return 1
}

# ── the detector ─────────────────────────────────────────────────────────────────────────────────
# One awk program, fed one file at a time. Kept in awk rather than bash+grep because the analysis is
# positional (which stage is LAST, which command word is FIRST) and a line-regex cannot see that.
# shellcheck disable=SC2016  # the $1/$2/$0 below are AWK fields — single quotes are the point.
DETECT_AWK='
function ltrim(s) { sub(/^[ \t]+/, "", s); return s }

# Clause 2: does this last stage exit before draining its input?
function is_early(s,   t) {
  t = ltrim(s); sub(/^[({][ \t]*/, "", t); t = ltrim(t)
  if (t ~ /^(\/usr\/bin\/|\/bin\/)?(grep|egrep|fgrep)([ \t]|$)/) {
    # The q/l/L may sit ANYWHERE in a flag cluster — `-qi`, `-qE`, `-iq` are all early-exit. An
    # anchored `[qlL]$` reads only `-q` and silently passes the other three (caught by selftest).
    if (t ~ /(^|[ \t])-[A-Za-z]*[qlL][A-Za-z]*([ \t]|$)/) return 1
    if (t ~ /(^|[ \t])-m[ \t]*[0-9]/)                     return 1
    return 0                                    # -c and bare grep DRAIN: they are the fix
  }
  if (t ~ /^head([ \t]|$)/)          return 1
  if (t ~ /^read([ \t]|$)/)          return 1
  if (t ~ /^sed([ \t]).*[;\x27" \t]q([ \t;\x27"]|$)/) return 1
  if (t ~ /^awk([ \t]).*exit/)       return 1
  return 0
}

# Clause 3: is the producer external/STREAMING (many writes) rather than a single-write emitter?
# A producer only orphans itself if it still has a write to make when the consumer exits, so the
# test is "more than one write", not "external". Measured: `head -1 BIG | grep -q` 0/300 and
# `tail -1 BIG | grep -q` 0/300 (one line out, then exit) against `cat BIG | grep -q` 300/300.
function is_external(s,   t, p) {
  t = s
  # A pipeline nested in a command substitution has its OWN producer — take the innermost, or a
  # line like  echo "x: $(sed … | head -1)"  reads its command word as echo and is missed.
  p = 0
  while (match(t, /\$\(/)) { t = substr(t, RSTART + 2); p = 1 }
  # A line can hold several commands before the pipe — `has_tell=0; printf … | grep -iqE …` and
  # `[ -n "$MSG" ] && printf … | grep -iqE …`. The producer is the LAST of them, so read past every
  # `;` and every &&/|| (already mapped to \003/\002); taking the first command word instead reads
  # `has_tell=0` / `[` and calls a printf builtin external, which is the commonest safe form here.
  while (match(t, /[;\002\003][ \t]*/)) t = substr(t, RSTART + RLENGTH)
  t = ltrim(t)
  if (!p) {
    sub(/^(if|elif|while|until)[ \t]+/, "", t)
    sub(/^![ \t]*/, "", t)
    sub(/^(local|declare|typeset|export|readonly)[ \t]+/, "", t)
    sub(/^[A-Za-z_][A-Za-z0-9_]*\+?=/, "", t)
    sub(/^"/, "", t)
  }
  sub(/^[({][ \t]*/, "", t)
  t = ltrim(t)
  # A builtin producer is ONE write only while what it writes is BOUNDED BY INSPECTION. A literal
  # argument is; a parameter expansion, a command substitution, or a backtick is not. The same printf
  # that measured 0/200 at 4 KiB is 10/10 FALSE once the write exceeds the 64 KiB pipe buffer (see
  # the header table). The command WORD is identical in both cases, so only the argument can decide.
  if (t ~ /^(echo|printf|:)([ \t]|$)/) {
    if (t ~ /\$/ || t ~ /`/) return 1                  # variable/substitution-sourced — UNBOUNDED
    return 0                                           # pure literal — ONE write, 0/200 at 4 KiB
  }
  if (t ~ /^(head|tail)[ \t]+(-n[ \t]*)?-?[1-9]([ \t]|$)/) return 0   # bounded: ≤9 lines, one write
  return 1
}

# Clause 4: does anything READ this pipelines status?
#   1 = CONSUMED here · 0 = MASKED (the status is discarded by construction and can never escape)
#   2 = UNREAD ON THIS LINE (nothing here reads it, but it is still THIS pipelines status, so it
#       escapes as the enclosing constructs status if this is the last statement — clause 4c).
# The 0/2 split is load-bearing: collapsing both to false is what made a function-final pipeline
# invisible, and treating both as true would flag `local v=$(p | head -1)`, where the pipeline never
# reaches the function boundary at all.
function consumed(l, hase,   t, pre, i) {
  t = ltrim(l)
  # [ -n "$( … )" ] / [ -z … ] discard the substitutions status entirely.
  if (t ~ /\[\[?[ \t]+-[nz][ \t]+"?\$\(/) return 0
  # A pipeline inside a command substitution used as an ARGUMENT is masked: the status the shell
  # reads is the OUTER commands, and a substitution that dies 141 still yields its bytes. Only
  # VAR=$( … ) — where the substitution IS the whole RHS — lets the status through to errexit.
  # (No apostrophes in this awk source: it is a single-quoted bash string.)
  if ((i = index(t, "$(")) > 0) {
    pre = substr(t, 1, i - 1)
    sub(/^(if|elif|while|until)[ \t]+/, "", pre)
    sub(/^![ \t]*/, "", pre)
    sub(/^(local|declare|typeset|export|readonly)[ \t]+/, "", pre)
    pre = ltrim(pre)
    if (pre != "" && pre !~ /[A-Za-z_][A-Za-z0-9_]*\+?="?$/) return 0
  }
  if (t ~ /^(if|elif|while|until)[ \t]/)  return 1
  if (t ~ /^![ \t]/)                      return 1
  # local/declare/export return their OWN 0 — the pipelines status never survives the assignment.
  # This test must sit ABOVE the !hase line, not below it: MASKED and UNREAD used to be the same
  # answer (false), so the order could not matter; now it decides whether clause 4c may fire, and a
  # `local v=$(p | head -1)` closing a function must stay green because the function returns the
  # builtins 0. g6 pins the errexit direction, g32 the function-final one.
  if (t ~ /^(local|declare|typeset|export|readonly)[ \t]/) return 0
  if (!hase) return 2
  return 1
}

BEGIN { FS = "" }
{
  raw = $0

  # Heredoc bodies are DATA, not code — a scar shape quoted inside one is not executed.
  if (inhd) { if ($0 ~ hdterm) inhd = 0; next }

  line = ltrim(raw)
  # A COMMENT IS NOT CODE, AND THIS TEST MUST RUN BEFORE THE OPENER TEST BELOW. It used to sit
  # three lines AFTER it, and inhd is LATCHING state: a comment that merely MENTIONS a heredoc
  # opener armed the tracker, no terminator ever arrived, and every remaining line in the file was
  # then consumed as heredoc BODY. That is not a miscount — it is a latched false NEGATIVE, and a
  # census of 0 for a muted file is byte-identical to a census of 0 for a clean one.
  #
  # MEASURED ON THE UNFIXED TREE, 2026-08-27: of 402 scanned files TEN were latched at EOF and TWO
  # of them swallowed real sites — census 138 against a true 143. BOTH culprits are comments
  # DOCUMENTING shell mechanics: scripts/limit-recover/lr-reset-poller.sh:357 explains a
  # `python3 - <<PY` bug it once had, and hooks/completion-assert.sh:705 explains why `<<EOF` is not
  # an operator placeholder. In a tree whose house style is long mechanical rationales in comments,
  # the trigger is CORRELATED with the style, which is why this went unnoticed for so long.
  #
  # The consequence was worst where nothing else covered it: lr-reset-poller.sh was invisible from
  # :357 to EOF and carries NO allowlist row at all, so its four sites had never once been judged —
  # among them the monthly-spend detector, a THREE-stage pipeline over a `tail -c 20000` feed whose
  # inversion reads a genuine spend kill as ABSENT. A ratchet exists to refuse NEW violations; below
  # a latch point a new violation is born invisible, with no allowlist row to record it.
  #
  # RESIDUAL, NAMED RATHER THAN WIDENED: four files still latch at EOF after this fix, from `<<TOK`
  # inside quoted CODE rather than inside a comment. None of the four swallows a site today
  # (measured: the swallowed set is exactly the two files above). Tightening the opener test to
  # ignore quoted occurrences is a real change to what counts as an opener and wants its own
  # measurement; it is not folded in here. g31/g32 pin both directions of what IS fixed.
  if (line ~ /^#/ || line == "") next

  # Clause 4c — FLUSH. `pend` holds a line that satisfied clauses 1/2/3/5 and failed clause 4 only
  # with UNREAD-ON-THIS-LINE (2), i.e. its status is still live at the end of the line. If the very
  # next CODE line closes the enclosing construct, that status is the constructs return value and is
  # read at the call site. Blank lines and comments are already skipped above, so a trailing comment
  # between the pipeline and the brace does not hide the shape (r17) — but any other statement does
  # clear it, because then THAT statements status is what the construct returns (g33).
  if (pend != "") {
    if (line ~ /^\}[ \t]*$/) print pend
    pend = ""
  }

  if (match($0, /<<-?[ \t]*[\x27"]?[A-Za-z_][A-Za-z0-9_]*[\x27"]?/)) {
    tok = substr($0, RSTART, RLENGTH)
    sub(/^<<-?[ \t]*/, "", tok); gsub(/[\x27"]/, "", tok)
    hdterm = "^[ \t]*" tok "[ \t]*$"; inhd = 1
  }

  work = line
  gsub(/\|\|/, "\002", work)          # || is an OR-list, not a pipe
  gsub(/&&/,   "\003", work)          # ditto &&
  n = split(work, seg, "|")
  if (n < 2) next

  last = seg[n]
  if (!is_early(last))      next      # clause 2
  if (last ~ /\002/)        next      # clause 5 — a trailing || swallows the 141
  if (!is_external(seg[1])) next      # clause 3

  # Clause 3b — the NEUTRALISE fix. A producer wrapped as `{ p || true; } | consumer` cannot fail
  # the pipeline: the group swallows the 141 before pipefail sees it, so the early exit is KEPT.
  # That matters where draining is expensive — bin/cc-cloud greps a 245 MB binary, where the drain
  # form costs 904 ms and this one 11 ms (measured on an equivalent 38 MB stream), both 0/50.
  if (seg[1] ~ /\{/ && seg[1] ~ /\002/) next

  # Clause 4. An && FOLLOWING the pipeline consumes its status by itself — errexit is irrelevant,
  # because the whole point of `p | grep -q X && act` is that a false p suppresses act. Missing
  # this cost a real detection: bin/cc-cloud ran `strings -a $bin | grep -q Claude-Session &&
  # return 0` over a 245 MB binary in a file with no set -e, and measured 5/5 FALSE on a string
  # that IS present five times — the version gate had been failing 100% of the time, unnoticed.
  #
  # But the && only reaches THIS pipeline if nothing closed it first. A `)` before the && means the
  # pipeline was inside a substitution and the && tests the enclosing expression instead
  # (`[ -n "$(find … | head -1)" ] && continue`); a `;` before it means the && belongs to a later
  # command entirely (`f="$(… | head -1)"; [ -n "$f" ] && …`). Both are safe, and both appeared in
  # the tree the moment this clause landed.
  amp = index(last, "\003")
  if (amp > 0) { pre_amp = substr(last, 1, amp - 1); if (pre_amp ~ /[;)]/) amp = 0 }
  # Clause 4b — a $? CAPTURE reads the status, errexit or not. Clause 4 asks whether anything READS
  # this pipelines status, but answers it with `if (!hase) return 0`, i.e. only errexit or a
  # control-flow position counts. `p | grep -q X; rc=$?` is the most DIRECT read of a pipelines
  # status there is, and it was invisible: census 151 to 153. The two sites it hid are in_allowlist
  # in test-walltime-lint.sh and git-identity-lint.sh — both RATCHET lints feeding postland-verifys
  # verdict-affecting prelint, i.e. this lints own class of consumer.
  #
  # POSITIONAL, on `last`, and NOT a line regex — for the reason the header already gives. A $? on
  # this line can belong to something that is not this pipeline: bin/cc-escalations:301 spells
  # ( set +e; cmd; printf %s "$?" ) | grep -qx 5, where the $? is the PRODUCERs own. A first cut
  # matching $? anywhere on the line flagged it (census 151 to 154, one false positive). Requiring
  # the ASSIGNMENT form after the last stage separates them; g15/g16 pin both directions.
  # (No apostrophes here: this is inside the single-quoted DETECT_AWK string.)
  cap = (last ~ /;[ \t]*[A-Za-z_][A-Za-z0-9_]*=\$\?/)
  cons = consumed(line, HASE)
  if (amp == 0 && !cap && cons != 1) {
    # Not read HERE — but if it is UNREAD rather than MASKED, park it: the next code line decides
    # whether the status escapes as the enclosing constructs return value (clause 4c, flushed above).
    if (cons == 2) pend = sprintf("%s:%d:%s", FILE, FNR, line)
    next
  }

  printf "%s:%d:%s\n", FILE, FNR, line
}'

# ── scan ─────────────────────────────────────────────────────────────────────────────────────────
# Only files that enable pipefail (clause 1) — and never this lint or its own bats suite, both of
# which carry the scar shape verbatim as fixtures. A lint that scans its own fixtures reports itself.
scan() {
  local f rel
  cd "$ROOT" 2>/dev/null || { echo "⛔ $SELF_NAME: scan root unusable: $ROOT" >&2; exit 2; }
  command -v awk >/dev/null 2>&1 || { echo "⛔ $SELF_NAME: awk not on PATH" >&2; exit 2; }
  command -v git >/dev/null 2>&1 || { echo "⛔ $SELF_NAME: git not on PATH" >&2; exit 2; }

  # The detector is an awk program carried in a SINGLE-QUOTED bash string, so one stray apostrophe
  # in a comment inside it silently truncates the program — and a truncated detector scans every
  # file, matches nothing, and reports a clean tree. That is the exact silent-green a lint must
  # never have (it happened once while writing this file, and the census read 0 sites). Parse it
  # once, up front, and make the failure a LOUD non-verdict instead.
  if ! awk -v FILE=- -v HASE=0 "$DETECT_AWK" </dev/null >/dev/null 2>&1; then
    echo "⛔ $SELF_NAME: the detector program does not parse — this is a NON-VERDICT, not a clean" >&2
    printf '  tree. Most likely a bare apostrophe inside the DETECT_AWK string (use \\x27 instead).\n' >&2
    exit 2
  fi

  if [ -d "$ROOT/.git" ] || git rev-parse --git-dir >/dev/null 2>&1; then
    rel="$(git ls-files 2>/dev/null)"
  else
    rel="$(find . -type f \( -name '*.sh' -o -name '*.bats' -o -path './bin/*' -o -path './hooks/*' \) | sed 's|^\./||')"
  fi

  printf '%s\n' "$rel" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      scripts/pipefail-sigpipe-lint.sh|tests/pipefail-sigpipe-lint.bats) continue ;;
    esac
    in_scan_set "$f" || continue
    [ -f "$f" ] || continue
    # clause 1 — the file must actually enable pipefail
    grep -E '^[[:space:]]*set[[:space:]]+-[a-zA-Z]*o[[:space:]]+pipefail|^[[:space:]]*set[[:space:]]+-o[[:space:]]+pipefail' "$f" >/dev/null 2>&1 || continue
    local hase=0
    grep -E '^[[:space:]]*set[[:space:]]+-[a-zA-Z]*e[a-zA-Z]*([[:space:]]|$)|^[[:space:]]*set[[:space:]]+-o[[:space:]]+errexit' "$f" >/dev/null 2>&1 && hase=1
    awk -v FILE="$f" -v HASE="$hase" "$DETECT_AWK" "$f"
  done
}

# ── allowlist ────────────────────────────────────────────────────────────────────────────────────
# Format: `<path><TAB><count>`; blank lines and #-comments ignored.
allow_count() {
  local path="$1"
  [ -f "$ALLOWLIST" ] || { echo 0; return; }
  awk -F'\t' -v p="$path" '$1==p { print $2+0; found=1 } END { if (!found) print 0 }' "$ALLOWLIST" | head -1
}

# ── the scan's non-verdict, and why it needs re-raising by hand ─────────────────────────────────
# scan() guards four unusable states (dead ROOT, no awk, no git, an unparseable detector) and each
# says `exit 2` — the honest non-verdict. But `exit` cannot leave a COMMAND SUBSTITUTION: it ends
# the subshell and hands the status back to the caller, where `|| true` used to discard it. `hits`
# was then EMPTY, which is indistinguishable from "the tree is clean" — and against a non-empty
# allowlist that is not merely a lost non-verdict, it INVERTS into a positive claim: every
# grandfathered file reads cur=0 < alw=N, so the ratchet's downward half fires and the lint exits 1
# reporting 16 sites the operator never touched, then prescribes `--regen`, whose own scan is dead
# the same way and which would write a HEADER-ONLY allowlist — destroying the grandfathered baseline
# it was invoked to maintain. So the prescribed remedy was the destructive act.
#
# `--census` is the control that pins this to the subshell rather than to the exit: there scan runs
# in THIS shell, and exit 2 leaves the script correctly (measured 2026-08-14, all three call sites).
#
# Read the status instead. Anything non-zero out of scan is a NON-VERDICT, never a tree claim: on a
# healthy tree scan returns 0 (measured, 30 census lines / 16 regen rows), so this cannot false-fire.
scan_or_nonverdict() { # $1=varname to fill with the scan output; returns 2 on a non-verdict
  local __out __rc=0
  __out="$(scan)" || __rc=$?
  if [ "$__rc" -ne 0 ]; then
    echo "⛔ $SELF_NAME: the scan could not RUN (exit $__rc — cause printed above)." >&2
    echo "  This is a NON-VERDICT, not a claim about your tree: no file was judged, so nothing here" >&2
    echo "  is evidence that anything is clean, newly broken, or newly fixed. Do NOT run --regen on" >&2
    echo "  it — with no scan there is nothing to regenerate from, and it would empty the allowlist." >&2
    return 2
  fi
  printf -v "$1" '%s' "$__out"
  return 0
}

main_scan() {
  local hits rc=0
  scan_or_nonverdict hits || return 2

  local -a over=() under=()
  local paths f cur alw
  paths="$(printf '%s\n' "$hits" | grep -c . >/dev/null 2>&1; printf '%s\n' "$hits" | awk -F: 'NF{print $1}' | sort -u)"

  # every file named in the allowlist, plus every file with a live hit
  local all
  all="$(
    { printf '%s\n' "$paths"
      [ -f "$ALLOWLIST" ] && awk -F'\t' '!/^#/ && NF>=2 {print $1}' "$ALLOWLIST"
    } | awk 'NF' | sort -u
  )"

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    cur="$(printf '%s\n' "$hits" | awk -F: -v p="$f" '$1==p' | awk 'NF' | wc -l | tr -d ' ')"
    alw="$(allow_count "$f")"
    # own-scope: only files in THIS land's diff can BLOCK; others are advisory.
    #
    # THREE STATES, and `${VAR:-}` could only ever express two (land-architecture-100p §5 P2).
    # UNSET ⇒ no caller asked for scoping ⇒ strict, every file may block. SET-BUT-EMPTY ⇒ a caller
    # DID scope and this land touches none of this lint's population — so nothing of theirs is
    # here and nothing may block. `${CC_PIPEFAIL_OWN:-}` collapsed those into "strict", and
    # ship-land ALWAYS exports the variable, so the collapsed case was live rather than corner:
    # measured on a fixture, a land whose own-set was empty (one touching only launchd/ or
    # commands/, which this arm's pathspec does not list) was refused over a SIBLING's file, with
    # nothing of its own to fix. `+set` is the idiom every sibling lint already uses.
    local blocking=1
    if [ -n "${CC_PIPEFAIL_OWN+set}" ]; then
      blocking=0
      printf '%s\n' "$CC_PIPEFAIL_OWN" | grep -Fx -- "$f" >/dev/null 2>&1 && blocking=1
    fi
    if [ "$cur" -gt "$alw" ]; then
      over+=("$f|$cur|$alw|$blocking")
      [ "$blocking" -eq 1 ] && rc=1
    elif [ "$cur" -lt "$alw" ]; then
      under+=("$f|$cur|$alw|$blocking")
      [ "$blocking" -eq 1 ] && rc=1
    fi
  done <<EOF
$all
EOF

  local e
  if [ "${#over[@]}" -gt 0 ]; then
    echo "✗ $SELF_NAME: NEW early-exit pipe consumer under pipefail — reads FALSE on a match." >&2
    for e in "${over[@]}"; do
      IFS='|' read -r f cur alw blocking <<< "$e"
      printf '  %s  %s (was %s)%s\n' "$f" "$cur" "$alw" "$([ "$blocking" -eq 0 ] && echo '  [advisory — outside this land]')" >&2
      printf '%s\n' "$hits" | awk -F: -v p="$f" '$1==p { $1=""; sub(/^:/,""); print "      " $0 }' >&2
    done
    echo "  FIX: drain the consumer — 'grep -q P' → 'grep P >/dev/null'; 'head -N' → \"awk 'NR<=N'\"." >&2
    echo "       Unbounded producer? capture first: out=\$(p) then match with case/[[." >&2
  fi
  if [ "${#under[@]}" -gt 0 ]; then
    echo "✗ $SELF_NAME: a grandfathered site was FIXED but its allowlist count was not lowered." >&2
    echo "  This is the ratchet's downward half — without it the list becomes a permanent exemption." >&2
    for e in "${under[@]}"; do
      IFS='|' read -r f cur alw blocking <<< "$e"
      printf '  %s  now %s, allowlist says %s → set it to %s%s\n' "$f" "$cur" "$alw" "$cur" \
        "$([ "$blocking" -eq 0 ] && echo '  [advisory — outside this land]')" >&2
    done
    echo "  Regenerate with: scripts/pipefail-sigpipe-lint.sh --regen > scripts/pipefail-sigpipe-allow.txt" >&2
  fi
  [ "$rc" -eq 0 ] && echo "✓ $SELF_NAME: clean (allowlist honoured)"
  return "$rc"
}

regen() {
  # The scan is proven BEFORE the first header byte, and that ordering is the whole point. This is
  # normally invoked as `--regen > scripts/pipefail-sigpipe-allow.txt`, so the shell has already
  # TRUNCATED the destination before the script runs: whatever reaches stdout is the new allowlist.
  # Piping a dead scan into awk (the old form) emitted four header lines and no rows, at exit 0 —
  # a well-formed file declaring every grandfathered site fixed. Nothing downstream could tell that
  # from a genuinely clean tree. Now a non-verdict writes NOTHING and exits 2, so the truncated file
  # stays empty and `git diff` shows the whole allowlist deleted — loud, and one `git checkout` away.
  local hits
  scan_or_nonverdict hits || return 2
  printf '%s\n' "# pipefail-sigpipe-lint allowlist — <path><TAB><violation count>."
  echo "# Grandfathered sites only. This list may only SHRINK: the lint goes RED both when a file"
  echo "# GAINS a violation and when it LOSES one without the count being lowered."
  echo "# The ONE legitimate way it GROWS is a DETECTOR widening — a new clause makes sites visible"
  echo "# that were never judged before, so the baseline is re-taken in the same commit as the clause."
  echo "# Regenerate: scripts/pipefail-sigpipe-lint.sh --regen > scripts/pipefail-sigpipe-allow.txt"
  printf '%s\n' "$hits" | awk -F: 'NF{print $1}' | sort | uniq -c | awk '{ printf "%s\t%s\n", $2, $1 }' | sort
}

# ── selftest ─────────────────────────────────────────────────────────────────────────────────────
# Both directions, on fixtures assembled at runtime. A ratchet whose discrimination is unverified is
# not a gate: the clean verdict has to be able to come out RED, or it means nothing.
ST_TMP=""
selftest() {
  local pass=0 fail=0 tmp
  # The tmpdir is a GLOBAL: an EXIT trap fires after the function's locals are gone, so a `local`
  # here makes the trap itself die on `set -u` — which then masks the selftest's own verdict.
  ST_TMP="$(mktemp -d)" || { echo "⛔ $SELF_NAME: mktemp failed" >&2; exit 2; }
  tmp="$ST_TMP"
  trap 'rm -rf "${ST_TMP:-}"' EXIT

  mk() { # $1=name $2=body
    mkdir -p "$tmp/scripts"
    { echo '#!/bin/bash'; echo 'set -euo pipefail'; printf '%s\n' "$2"; } > "$tmp/scripts/$1.sh"
  }
  mk_noe() {
    mkdir -p "$tmp/scripts"
    { echo '#!/bin/bash'; echo 'set -uo pipefail'; printf '%s\n' "$2"; } > "$tmp/scripts/$1.sh"
  }
  expect() { # $1=name $2=RED|GREEN $3=label
    local out n
    out="$(CC_PIPEFAIL_ROOT="$tmp" ALLOWLIST=/dev/null CC_PIPEFAIL_ALLOWLIST=/dev/null bash "$SELF" --census 2>/dev/null)"
    n="$(printf '%s\n' "$out" | grep -c "scripts/$1\.sh:" 2>/dev/null || true)"
    if { [ "$2" = RED ] && [ "${n:-0}" -ge 1 ]; } || { [ "$2" = GREEN ] && [ "${n:-0}" -eq 0 ]; }; then
      pass=$((pass+1))
    else
      fail=$((fail+1)); echo "  ✗ $3 — expected $2, detector said ${n:-0} hit(s)" >&2
    fi
    rm -f "$tmp/scripts/$1.sh"
  }

  # ── must be RED: the real scar and its close relatives ──
  mk r1 "if \"\$BIN\" -h 2>/dev/null | grep -q -- '--login-status'; then :; fi"
  expect r1 RED "the ec9a43a9 scar, byte-for-byte"
  mk r2 "if git status --porcelain 2>/dev/null | grep -q .; then :; fi"
  expect r2 RED "git status | grep -q . (a dirty tree reads CLEAN)"
  mk r3 "v=\$(sed -n 's/x/y/p' /some/file | head -1)"
  expect r3 RED "VAR=\$(sed FILE | head -1) under set -e"
  mk r4 "if find . -name x 2>/dev/null | grep -q .; then :; fi"
  expect r4 RED "find | grep -q ."
  mk r5 "ps -o command= -p 1 | grep -qi kitty"
  expect r5 RED "bare pipeline under set -e"
  mk r6 "if ! launchctl list | grep -qE 'com\.x'; then :; fi"
  expect r6 RED "negated condition"
  mk r7 "if git log --oneline | grep -m1 pat; then :; fi"
  expect r7 RED "grep -m1 is early-exit too"
  mk r8 "if ps -p 1 -o command= | grep -qi kitty; then :; fi"
  expect r8 RED "q anywhere in a flag cluster (-qi), not just last"
  mk r9 "v=\"\$(cat /some/file | head -1)\""
  expect r9 RED "external producer nested in a whole-RHS \$( … ) under set -e"
  mk_noe r10 "strings -a \"\$bin\" 2>/dev/null | grep -q 'Claude-Session' && return 0"
  expect r10 RED "&& consumes the status with NO set -e (the cc-cloud 5/5-FALSE scar)"
  # r11/r12 were GREEN fixtures until 2026-08-17, labelled "measured 0/200". That measurement was of
  # a 4 KiB payload, not of the command word: re-measured, the SAME printf is 10/10 FALSE as soon as
  # the write passes 64 KiB. Left GREEN, this control certified the very bug the widening fixes.
  mk r11 "if printf '%s' \"\$MSG\" | grep -qE \"\$TELLS\"; then :; fi"
  expect r11 RED "printf builtin fed a VARIABLE — unbounded by inspection, 10/10 FALSE past 64 KiB"
  mk r12 "if echo \"\$X\" | grep -q pat; then :; fi"
  expect r12 RED "echo builtin fed a VARIABLE"
  # The backtick leg of the same rule — untested by r11/r12, which only exercise the `$` leg.
  # (The `$( … )` leg is caught at clause 3 too, but clause 4's argument-substitution rule — the one
  # g13 pins — masks the whole line before it is reached. That is pre-existing and deliberate, not a
  # gap this widening opened: no such site exists in the tree.)
  mk r13 "if printf '%s' \"\`git log --oneline\`\" | grep -q pat; then :; fi"
  expect r13 RED "builtin fed a BACKTICK substitution"

  # ── must be GREEN: every legitimate form the tree actually uses ──
  # The literal half of the builtin rule. Without these the suite would pass against a lint that
  # flagged EVERY builtin producer — proving "flags the variable one" is only half a discriminator.
  mk g1 "if printf '%s\\n' 'ready' | grep -q ready; then :; fi"
  expect g1 GREEN "printf of a pure LITERAL — one bounded write, measured 0/200"
  mk g2 "if echo done | grep -q done; then :; fi"
  expect g2 GREEN "echo of a pure LITERAL"
  mk g3 "if git status --porcelain | grep -c . >/dev/null; then :; fi"
  expect g3 GREEN "grep -c DRAINS — it is the fix, not the defect"
  mk g4 "if git status --porcelain | grep . >/dev/null; then :; fi"
  expect g4 GREEN "plain grep DRAINS — the canonical fix"
  mk g5 "v=\$(git log --oneline | awk 'NR<=1')"
  expect g5 GREEN "awk NR<=N drains — the head -N fix"
  mk g6 "local v=\$(git log | head -1)"
  expect g6 GREEN "local masks the pipeline status"
  mk g7 "if [ -n \"\$(git status --porcelain | head -1)\" ]; then :; fi"
  expect g7 GREEN "[ -n \"\$( … )\" ] discards the status"
  mk g8 "v=\$(git log | head -1) || true"
  expect g8 GREEN "a trailing || swallows the 141"
  mk_noe g9 "git log --oneline | head -5"
  expect g9 GREEN "status never read, and no set -e"
  mk g10 "cat <<'EOF'
if x | grep -q y; then :; fi
EOF"
  expect g10 GREEN "a scar quoted inside a heredoc is DATA, not code"
  mk g11 "if tail -1 \"\$LOG\" | grep -q '\"segi\":'; then :; fi"
  expect g11 GREEN "tail -1 producer — one line out then exit, measured 0/300"
  mk g12 "if head -1 \"\$f\" 2>/dev/null | grep -qx -- '---'; then :; fi"
  expect g12 GREEN "head -1 producer — bounded, measured 0/300"
  mk g13 "printf '  %s\\n' \"\$(sed -n 's/a/b/p' /some/file | head -1)\""
  expect g13 GREEN "\$( … ) as an ARGUMENT — the outer command's status wins"
  mk_noe g14 "{ strings -a \"\$bin\" 2>/dev/null || true; } | grep -q 'Claude-Session' && return 0"
  expect g14 GREEN "{ p || true; } NEUTRALISES the 141 and keeps the early exit"
  # ── THE `$?` CAPTURE (2026-08-26) ────────────────────────────────────────────────────────────
  # Clause 4 asks "does anything READ this pipeline's status?" — and, for a file with no errexit,
  # answered a DIFFERENT question: `if (!hase) return 0`, i.e. "only a control-flow position or
  # errexit counts". A `; rc=$?` immediately after the last stage is the most direct read there is,
  # and it was invisible. Census 151 → 153; the two sites it hid are in_allowlist in
  # scripts/test-walltime-lint.sh and scripts/git-identity-lint.sh — both RATCHET lints whose
  # verdict feeds postland-verify's verdict-affecting prelint, i.e. exactly this lint's own class of
  # consumer. Neither can invert TODAY (their lists are 15 bytes and empty against a 64 KiB pipe
  # buffer, and both files convert a could-not-run into exit 2 anyway), so this closes a DETECTOR
  # blind spot, not a live inversion — the next site in this shape may be neither so small nor so
  # well defended.
  mk_noe r14 "printf '%s\\n' \"\$2\" | grep -qxF \"\$1\"; rc=\$?"
  expect r14 RED "a \$? capture reads the status with NO set -e (the in_allowlist shape)"
  # ...and the two shapes that must NOT widen. Both are POSITIONAL, which is why the test is on the
  # LAST stage rather than on the line: a `$?` on this line can belong to something that is not this
  # pipeline. g15 is measured, not hypothetical — bin/cc-escalations:301 has exactly this form, and
  # a first cut of this clause that matched `$?` anywhere on the line flagged it (census 151 → 154).
  mk_noe g15 "( set +e; \"\$SELF\" ack x >/dev/null 2>&1; printf '%s' \"\$?\" ) | grep -qx 5"
  expect g15 GREEN "a \$? INSIDE the producer is the inner command's, never the pipeline's"
  mk_noe g16 "rc=\$?; git log --oneline | head -5"
  expect g16 GREEN "a \$? capture BEFORE the pipeline reads the PREVIOUS command's status"

  # ── THE COMMENTED-HEREDOC MUTE (2026-08-27) ───────────────────────────────────────────────────
  # The heredoc tracker is the detector's ONLY file-level latching state, and its opener test used
  # to run BEFORE the comment test. A comment that merely NAMES an opener armed it, no terminator
  # ever came, and the rest of the file was read as heredoc body: the file went silently and
  # permanently MUTE. Measured 10 latched files of 402, 5 swallowed sites across 2 of them.
  #
  # r15 is the defect verbatim — the comment shape is the one this tree actually writes, a sentence
  # explaining a heredoc bug — and it was GREEN before the fix. g31 is the arm that stops the fix
  # from being a widening: a comment ahead of a REAL heredoc must not stop the body being treated
  # as DATA, which is the property g10 already pins for the no-comment case. Two arms, opposite
  # directions, one variable between them: whether the heredoc that follows is real.
  mk r15 "# a note about \`python3 - <<PY\` and why it once broke
if git status --porcelain 2>/dev/null | grep -q .; then :; fi"
  expect r15 RED "a COMMENT naming a heredoc opener must not mute the rest of the file"
  mk g31 "# a note about \`cat <<EOF\` and what it does
cat <<'EOF'
if git status --porcelain | grep -q .; then :; fi
EOF"
  expect g31 GREEN "a comment ahead of a REAL heredoc still leaves the body as DATA"

  # ── THE FUNCTION-FINAL PIPELINE (2026-08-28, backlog ca97c678b18b) ────────────────────────────
  # Clause 4 read only THIS line, so in a file with no errexit a bare pipeline meant "nobody looks".
  # For the last statement of a function that is exactly backwards: the pipelines status IS the
  # functions return value, and the reader is at the call site — possibly in another file. r16/r17
  # are the defect; g32/g33/g34 are the three ways the status does NOT escape, and without them this
  # clause would be satisfied by a lint that flagged every pipeline in a non-errexit file.
  mk_noe r16 "port_listening() {
  ps -p \"\$1\" -o command= 2>/dev/null | grep -q LISTEN
}"
  expect r16 RED "function-final pipeline — its rc IS the function's return value"
  mk_noe r17 "port_listening() {
  ps -p \"\$1\" -o command= 2>/dev/null | grep -q LISTEN
  # a trailing note, which is this tree's house style
}"
  expect r17 RED "function-final pipeline with a trailing COMMENT before the brace"
  mk_noe g32 "first_line() {
  local v=\$(git log --oneline | head -1)
}"
  expect g32 GREEN "function-final but MASKED — local returns its own 0, the status never escapes"
  mk_noe g33 "port_listening() {
  git log --oneline | head -1
  echo done
}"
  expect g33 GREEN "not the LAST statement — the later command's status is what the function returns"
  mk_noe g34 "port_listening() {
  git status --porcelain | grep -q . || true
}"
  expect g34 GREEN "a trailing || swallows the 141 even in the function-final position"

  local total=$((pass+fail))
  if [ "$fail" -gt 0 ]; then
    echo "⛔ $SELF_NAME --selftest: $pass/$total — the detector no longer discriminates." >&2
    return 1
  fi
  echo "✓ $SELF_NAME --selftest: $pass/$total (both directions; builtin producer RED on a variable or substitution, GREEN on a literal; function-final pipeline RED, masked/non-final/|| GREEN)"
  return 0
}

# ── --print-scope: the population this lint JUDGES, as git pathspecs, one per line ────────────────
# SCAN_PATHSPECS is the SAME declaration scan() filters with (via in_scan_set), so the two cannot
# disagree: adding a judged file shape moves the scan and this answer in one edit.
#
# WHY IT EXISTS (backlog 5fc8ff411a7c, extending 0be0bd2c0b65 to the six arms left out of it).
# scripts/ship-land.sh built this lint's own-scope set — the files allowed to BLOCK a land — from a
# `-- 'bin/*' 'hooks/*' 'scripts/*' 'tests/*' 'docs/*' '*.sh'` pathspec RESTATED in ship-land. That
# restatement could not drift at RUNTIME (CC_PIPEFAIL_ROOT moves the scan ROOT, never the population),
# and that was the whole of its defence: it could still drift by a CODE edit to the judged shapes,
# with the same silent failure direction — an own-set that MISSES a file does not error, it is the
# legitimate spelling of "this land touches nothing I judge", so the finding degrades to advisory and
# the land proceeds.
#
# AND IT HAD ALREADY DRIFTED, which is why this arm is the one worth reading. The restated pathspec
# carried `docs/*` and `tests/*` — neither of which this lint judges as such — while MISSING `*.bats`,
# which it does judge at every depth. Today every .bats file lives under tests/, so the miss is
# latent and nothing is red; a .bats file added anywhere else would have been judged by this lint and
# absent from the own-set, i.e. advisory, i.e. landed. That is the drift the comment asked an author
# to prevent by hand, sitting in the tree, unnoticed, on an arm whose defence was that it could not
# drift.
# It prints SCAN_PATTERNS, the array in_scan_set matches against — not the raw string, and not a
# re-split of it. A second split here would be a second chance to get the globbing guard wrong, on
# the exact expansion that already had it wrong once (see the SCAN_PATTERNS note above).
if [ "${1:-}" = "--print-scope" ]; then
  printf '%s\n' "${SCAN_PATTERNS[@]}"
  exit 0
fi

case "${1:---scan}" in
  -h|--help) usage; exit 0 ;;
  --selftest) selftest; exit $? ;;
  --census)   scan; exit 0 ;;
  --regen)    regen; exit $? ;;   # $? not 0: regen returns 2 on a non-verdict, and a hardcoded 0
                                  # would re-swallow it at the last hop after all the work above.
  --scan)     main_scan; exit $? ;;
  *) usage >&2; exit 2 ;;
esac
