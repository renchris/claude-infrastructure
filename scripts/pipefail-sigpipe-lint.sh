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
# TWO CORRECTIONS to what docs/plans/RELOGIN_BUILD_CONTRACT.md § "The defect" carries, both
# re-measured above and both load-bearing for this rule's scope:
#
#   · The discriminator is NOT output SIZE and not "the match is not on the last line" — it is
#     whether the producer makes MORE THAN ONE WRITE after the match. A single `write(2)` under the
#     64 KiB pipe buffer completes before the consumer is even scheduled, so `printf '%s' "$BIG"`
#     is safe at 4 KiB (0/200) while a 4-line separate process fails 11% and a streaming producer
#     fails 85% at ONE kilobyte. Builtin-producer sites are therefore NOT violations here.
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
#   3. the PRODUCER is external/streaming. `echo`/`printf`/`:` of a shell variable is ONE write and
#      measured 0/200 — flagging it would be a false positive on the commonest safe form in the tree
#      (229 of the 367 status-consuming sites);
#   4. the pipeline's status is CONSUMED — an `if`/`elif`/`while`/`until` condition, a `!` operand,
#      or (under `set -e`) a bare pipeline or a top-level `VAR=$(…)`. `local`/`declare`/`export`
#      MASK the status (the builtin's own 0 wins), and `[ -n "$( … )" ]` discards it, so neither is
#      a violation however exposed the pipeline inside looks;
#   5. it is NOT already mitigated by a trailing `|| true` / `|| <fallback>`, which swallows the 141
#      before anything reads it.
#
# THE FIX, in the order to reach for it:
#   · `p | grep -q PAT`   → `p | grep PAT >/dev/null`     — plain grep drains; 0/400
#   · `p | grep -qE PAT`  → `p | grep -E PAT >/dev/null`
#   · `p | head -N`       → `p | awk 'NR<=N'`             — drains, same bytes out; 0/400
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
  if (t ~ /^(echo|printf|:)([ \t]|$)/)                 return 0   # ONE write — 0/200 at 4 KiB
  if (t ~ /^(head|tail)[ \t]+(-n[ \t]*)?-?[1-9]([ \t]|$)/) return 0   # bounded: ≤9 lines, one write
  return 1
}

# Clause 4: does anything READ this pipelines status?
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
  if (!hase) return 0
  # local/declare/export return their OWN 0 — the pipelines status never survives the assignment.
  if (t ~ /^(local|declare|typeset|export|readonly)[ \t]/) return 0
  return 1
}

BEGIN { FS = "" }
{
  raw = $0

  # Heredoc bodies are DATA, not code — a scar shape quoted inside one is not executed.
  if (inhd) { if ($0 ~ hdterm) inhd = 0; next }
  if (match($0, /<<-?[ \t]*[\x27"]?[A-Za-z_][A-Za-z0-9_]*[\x27"]?/)) {
    tok = substr($0, RSTART, RLENGTH)
    sub(/^<<-?[ \t]*/, "", tok); gsub(/[\x27"]/, "", tok)
    hdterm = "^[ \t]*" tok "[ \t]*$"; inhd = 1
  }

  line = ltrim(raw)
  if (line ~ /^#/ || line == "") next

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
  if (amp == 0 && !consumed(line, HASE)) next

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
      *.sh|*.bats|bin/*|hooks/*|scripts/*) ;;
      *) continue ;;
    esac
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

  # ── must be GREEN: every legitimate form the tree actually uses ──
  mk g1 "if printf '%s' \"\$MSG\" | grep -qE \"\$TELLS\"; then :; fi"
  expect g1 GREEN "printf builtin producer — ONE write, measured 0/200"
  mk g2 "if echo \"\$X\" | grep -q pat; then :; fi"
  expect g2 GREEN "echo builtin producer"
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

  local total=$((pass+fail))
  if [ "$fail" -gt 0 ]; then
    echo "⛔ $SELF_NAME --selftest: $pass/$total — the detector no longer discriminates." >&2
    return 1
  fi
  echo "✓ $SELF_NAME --selftest: $pass/$total (both directions)"
  return 0
}

case "${1:---scan}" in
  -h|--help) usage; exit 0 ;;
  --selftest) selftest; exit $? ;;
  --census)   scan; exit 0 ;;
  --regen)    regen; exit $? ;;   # $? not 0: regen returns 2 on a non-verdict, and a hardcoded 0
                                  # would re-swallow it at the last hop after all the work above.
  --scan)     main_scan; exit $? ;;
  *) usage >&2; exit 2 ;;
esac
