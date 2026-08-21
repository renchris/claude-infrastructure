#!/bin/bash
# qos-rewrite.sh — PreToolUse(Bash) hook. THE QoS CHOKEPOINT, MOVED TO THE TOOL BOUNDARY.
#
# WHY THIS EXISTS (MACHINE_CAPACITY_V2.md §11.3 M7). bin/cc-bats already moved demotion from the
# CALLER to the TOOL — measured to be the right inversion. But a PATH shim only covers invocations
# that go through PATH, and two holes survived it (§11.2 live axis, 2026-07-29/30):
#
#   1. THE ABSOLUTE-PATH SPELLING. `timeout 90 /opt/homebrew/bin/bats t.bats` never consults PATH,
#      so it never meets the shim. qos-census sat at a ~69.4%-proc coverage CEILING for exactly
#      this reason — the residual is not carelessness, it is a spelling the mechanism cannot see.
#   2. EVERYTHING THAT IS NOT bats — the LARGER live term. Whole-box truth: 3.1% of CPU demoted.
#      `uv run pytest -m load` 0.67 cores at PRI 31 · a recurring `du -sh` at PRI 46 (BOOSTED
#      ABOVE default) · `npm install` 15.6% · `shellcheck` at 458 MB. One shim per tool is N shims,
#      each with its own PATH-ordering failure mode.
#
# THE INVERSION: there is exactly one boundary every agent-issued command must cross that no
# spelling can route around — the Bash TOOL call itself. A PreToolUse hook emitting `updatedInput`
# rewrites the command that actually executes. Confirmed empirically on live 2.1.219 in BOTH
# decision modes (§11.2 probe row); this file ships the NO-decision form, so the permission flow is
# untouched and every existing Bash hook still sees what it saw before.
#
# The operator's own terminal does NOT pass through this hook. Only AGENTS demote; hand-typed
# interactive work is unaffected by construction, not by a rule someone has to remember.
#
# NOT admission control. Nothing here waits, sleeps, queues, or polls load — demotion only (R1).
#
# THREE TRANSFORMS. (a) fires alone and returns; (b) and (c) are PREFIXES over the same command and
# COMPOSE, so a row in both tables yields both prefixes rather than silently dropping one:
#   (a) any-spelling `bats` token  →  cc-bats                (converge on the PROVEN artifact)
#   (b) a batch-table match        →  taskpolicy prefix, SIMPLE commands ONLY   (WHERE it runs)
#   (c) a bound-table match        →  cc-cpubound prefix, SIMPLE commands ONLY  (HOW LONG it may run)
#
# WHY (c) EXISTS, AND WHY IT IS A CPU CEILING (backlog 2af4c4908422; MACHINE_CAPACITY_V2.md:1513-1519
# class "B — single runaway action in one session", control point = this boundary, asking for "a
# RESOURCE guard — never a denylist of binary names"). (b) decides what a command COMPETES WITH; it
# has never bounded how long one may run. On 2026-08-02 an agent's Bash-tool `grep` — rewritten by the
# interactive shell function to `ugrep -G …` — hit catastrophic backtracking on ONE HTML file and
# burned 12m48s of CPU at 7.84 GiB RSS. Demotion would not have stopped it; it would have made it
# slower. macOS gives an unprivileged spawner no memory ceiling at all (RLIMIT_AS/RSS/DATA are EINVAL
# on Darwin, measured, with RLIMIT_CPU/NOFILE/NPROC/FSIZE setting fine in the same process as the
# positive control), so the one ceiling that exists is CPU time — and it is the RIGHT one here,
# because it bounds compute rather than patience: a command that is slow because it WAITS is never
# touched. Mechanism, measured semantics and the declared blind spot live in bin/cc-cpubound.
#
# (b) and (c) COMPOSE rather than race because they answer different questions and the first-wins
# rule would have made the answer depend on table order — a silent, order-dependent drop is exactly
# the class of bug this file's conservatism exists to avoid. The bound goes OUTERMOST so the ceiling
# covers the whole chain including taskpolicy's own exec.
#
# FAIL-OPEN IS THE HARD CONTRACT (row 6's standing constraint: a hook failure must never block a
# tool). Every path exits 0. Every path that cannot be SURE prints NOTHING — and no output means
# the command runs verbatim, exactly as if this file did not exist. There is no partial-JSON path.
#
# THE NON-OBVIOUS HALF OF FAIL-OPEN: a rewrite can break a command that would otherwise have
# worked. `bats` → a cc-bats that is not there is exit 127; `taskpolicy -c <bogus>` is exit 64 and
# the program NEVER RUNS (measured 2026-07-30: only utility|background|maintenance parse). So every
# binary this file names is checked EXECUTABLE and every band is checked against the allowlist
# BEFORE we rewrite. Refusing to rewrite costs one undemoted process; a bad rewrite costs the
# agent's command.
#
# KNOWN COVERAGE RESIDUAL, day one — a leading `VAR=value` assignment (lead review 2026-07-30).
# Transform (b) declines any command whose first word is an env assignment, because the prefix is
# PREPENDED: `taskpolicy -c utility CC_X=1 pytest` hands `CC_X=1` to taskpolicy as the program to
# exec, and it dies. The form is COMMON in this fleet's agent Bash calls (`CC_X=1 timeout 500 …`),
# so this is a REAL residual for the table patterns, not a theoretical one. Transform (a) is
# unaffected — token replacement finds `bats` wherever it sits, assignment or no. Declining is the
# day-one call rather than re-ordering the caller's env into the prefix, which would make this hook
# responsible for env semantics it cannot see. qos-census measures whatever residual this leaves;
# that is the honest loop. `tests/qos-rewrite.bats` pins BOTH halves (the skip and the control that
# the same command without the assignment IS prefixed) so changing this is a decision, not drift.
#
# Seams (set-but-EMPTY is honoured VERBATIM everywhere — the `${VAR-default}` single-dash form,
# never `${VAR:-default}`, because a seam that cannot turn a thing OFF is not a seam; cc-bats:25):
#   CC_QOS_REWRITE=off      → whole hook off, exit 0 before anything else (kill switch, R8).
#   CC_QOS_PATTERNS=<path>  → pin the pattern table; SET-BUT-EMPTY disables transform (b) ONLY.
#   CC_QOS_CC_BATS=<path>   → pin the cc-bats target; SET-BUT-EMPTY disables transform (a) ONLY.
#   CC_QOS_TASKPOLICY=<p>   → pin taskpolicy(8); set-but-empty ⇒ transform (b) off entirely.
#   CC_QOS_BOUND_PATTERNS=<path> → pin the CPU-ceiling table; SET-BUT-EMPTY disables (c) ONLY.
#   CC_QOS_CPUBOUND=<path>  → pin cc-cpubound; set-but-empty ⇒ transform (c) off entirely.
#
# THE BAND, AND WHY nice(1) IS NOT IN THE PREFIX (M1-rev, 2026-07-30; §11.9 per lead message).
# Two measured facts changed the shape of this prefix after day one:
#   1. `nice` IS DECORATIVE. `nice -n 19` moves NI to 19 and leaves PRI at 31 — verified again on
#      this box. It never demoted anything. It was in the day-one prefix on the assumption that it
#      composed with the clamp; it does not, it just costs a fork. So the prefix is now taskpolicy
#      ALONE, and there is no nice-only fallback tier: a missing taskpolicy means NO rewrite, which
#      is the honest state rather than a prefix that looks covered to a census and demotes nothing.
#   2. `-c background` IS TOO SHARP for long batch work — a ~84–89× tax, because it confines the
#      process to the 2 E-cores (shared with ~628 system procs) at I/O tier 2, with a ×84 fork
#      penalty. `-c utility` costs ~2.4× under the same load (PRI 20, P-core-eligible, tier-1 I/O)
#      and still yields to interactive PRI 31 — which is the only property this row actually needs.
# The band is NOT hardcoded here: it comes from the table's band column, so re-tuning it stays a
# config edit (§11.7). All three clamps stay admitted by the allowlist below.
#
# bash 3.2 SAFE: no `case` inside command substitution, no IFS-on-control-char splitting
# (memory bash32-case-in-substitution-zsh-repro-trap). Runs under /bin/bash as a hook.

# Kill switch is FIRST — before `set`, before stdin, before any resolution that could fail.
[ "${CC_QOS_REWRITE:-on}" = "off" ] && exit 0

set -uo pipefail

# ── read the payload, BOUNDED ─────────────────────────────────────────────────────────────────
# A hook runs on EVERY Bash call, so its own cost is a fleet-wide term (§8.5.4). An unbounded read
# of an attacker-or-accident-sized command is a memory term we refuse to take: 200 KB is ~2 orders
# of magnitude above any real command line, and a command truncated at that bound simply fails the
# match and runs verbatim (fail-open, not fail-weird).
INPUT=$(head -c 200000) || exit 0
[ -n "$INPUT" ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# ── emit the envelope, or nothing at all ──────────────────────────────────────────────────────
# Built by jq --arg so escaping is jq's problem, never ours (a hand-rolled quote here is how a hook
# ships malformed JSON to a parser that then has to guess). Compact: one line, one object.
# Deliberately NO permissionDecision field — the rewrite applies on its own (§11.2 probe), and
# claiming a decision would take the permission flow over from the hooks that own it.
emit() { # <rewritten command>
  jq -cn --arg c "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",updatedInput:{command:$c}}}' 2>/dev/null \
    || exit 0
  exit 0
}

# ── idempotency: never wrap what is already wrapped ───────────────────────────────────────────
# ALL THREE transforms are skipped, not just (a). A command already naming cc-bats self-demotes; one
# already carrying `taskpolicy -c` is already in a band; one already naming cc-cpubound already
# carries a ceiling, and a second ceiling would be the tighter of two numbers chosen by nobody.
# Re-wrapping is harmless in effect and costs a fork pair — and this file exists to reduce load,
# not to add it (cc-bats:97-104).
case "$CMD" in
  *cc-bats*|*'taskpolicy -c'*|*cc-cpubound*) exit 0 ;;
esac

# ══ TRANSFORM (a) — any-spelling `bats` token → cc-bats ═══════════════════════════════════════
# The target is resolved and CHECKED EXECUTABLE first: rewriting to a cc-bats that is not deployed
# would turn a working gate run into exit 127.
if [ -n "${CC_QOS_CC_BATS+set}" ]; then
  CC_BATS_TARGET="$CC_QOS_CC_BATS"      # set-but-EMPTY ⇒ transform (a) OFF, honoured verbatim
else
  CC_BATS_TARGET="${HOME:-}/.claude/bin/cc-bats"
fi

if [ -n "$CC_BATS_TARGET" ] && [ -x "$CC_BATS_TARGET" ]; then
  # NO REPLACEMENT ESCAPING IS NEEDED ANY MORE, and that is a consequence of the substituter, not
  # an oversight. sed needed the target escaped because `\` and `&` are special in a replacement and
  # `%` was our delimiter (verified 2026-07-30 against targets containing each of the three); the
  # awk pass below never puts the target through a replacement parser at all — it builds the result
  # with substr() and concatenation — and receives it through ENVIRON rather than -v, which would
  # itself process escape sequences. One fork saved on every Bash call, and one whole class of
  # metacharacter bug that can no longer exist.
  if [ -n "$CC_BATS_TARGET" ]; then
    # THE TOKEN PATTERN, and why each piece is load-bearing (all four verified on BSD sed):
    #   (^|[[:space:]])      the token starts a word — `my.bats.file` and `t.bats` never match
    #   (/[^[:space:]]*/)?   an optional ABSOLUTE directory prefix that must END in `/`. This is
    #                        the guard that keeps `bats /abs/path/tests/foo.bats` from rewriting
    #                        its own ARGUMENT: the prefix cannot end mid-component, so `.../x.`
    #                        + `bats` is not a match. A relative prefix is deliberately NOT
    #                        matched — `bats -r tests/bats` must leave `tests/bats` alone.
    #   bats                 the literal, and nothing else
    #   ([[:space:]]|$)      the token ends a word; `$` inside the group anchors correctly here
    # /g so a wrapper form (`timeout 90 <path>/bats`, `env FOO=1 <path>/bats`) is covered without
    # having to know the wrapper.
    #
    # THE BARE TOKEN IS DROPPED WHEN A PATH SHIM ALREADY COVERS IT (backlog 1d20ff5ee344).
    # The "accepted narrowing" this comment used to declare — that a bare `bats` used as DATA is
    # rewritten too, blast radius "a surprising echo" — was measured and it is not that small: the
    # substitution is /g over the WHOLE command text with only whitespace boundaries, so it also
    # rewrites inside quoted literals and heredoc BODIES. It corrupted a tests/ literal and an
    # operator's transplant file. Reproduced 2026-08-15: `echo hello bats world` came back as
    # `echo hello <path>/cc-bats world`.
    #
    # What makes it droppable rather than merely regrettable is that the bare case is now REDUNDANT.
    # A `bats` shim is installed beside this target (`~/.claude/bin/bats` → the repo's bin/cc-bats)
    # and `~/.claude/bin` is FIRST on the PATH every agent Bash call runs with, so a bare token that
    # is actually EXECUTED resolves to the wrapper through PATH — in any position, including under
    # `timeout`/`env`, because execution consults PATH regardless of what precedes the word. What
    # PATH cannot intercept is an ABSOLUTE spelling of some other bats, and that is exactly the arm
    # kept below.
    #
    # Conditional, and fail-safe in the direction that matters: with no shim beside the target the
    # pattern is unchanged, so this can only ever rewrite LESS than before, never differently. A
    # miss costs a bats run its QoS band; it can never corrupt a command. Compared with `-ef` (same
    # device+inode, symlinks followed) rather than by path, because the shim IS a symlink.
    _SHIM="${CC_BATS_TARGET%/*}/bats"
    if [ -x "$_SHIM" ] && [ "$_SHIM" -ef "$CC_BATS_TARGET" ]; then
      _PFX='(/[^[:space:]]*/)'      # absolute spellings only — PATH owns the bare token
    else
      _PFX='(/[^[:space:]]*/)?'     # no shim: the bare token still has no other chokepoint
    fi
    # ── THE SUBSTITUTION SKIPS QUOTED REGIONS (backlog e2eaaa0f4907, fixed 2026-08-21) ───────────
    # WHAT WAS STILL BROKEN AFTER THE BARE TOKEN WAS DROPPED. Narrowing the pattern to absolute
    # spellings fixed the COMMON corruption, not the CLASS: `sed` sees one flat string, so the
    # surviving arm still rewrote an absolute spelling wherever it appeared, including inside a
    # quoted argument and a heredoc BODY. Reproduced 2026-08-21 from a drain session's own probe —
    # `bats -f 'check /usr/local/bin/bats path' t.bats` came back with its FILTER rewritten, and a
    # heredoc that WROTE a file landed the substituted bytes on disk. The chain's own working rule
    # ("write probes to a file and run them with bash") routes straight through this path, so the
    # blast radius is agent-authored file CONTENT, not merely a surprising echo.
    #
    # WHY QUOTE-SKIPPING AND NOT COMMAND-POSITION-ONLY. The row proposed either. Command-position
    # would delete the wrapper coverage the pattern comment above says `/g` exists for — `timeout 90
    # <path>/bats`, `env FOO=1 <path>/bats` are matched today WITHOUT this file knowing the wrapper,
    # and an allowlist of wrapper spellings is the denylist defect one layer out. Quote-skipping
    # subtracts only the positions where the token is DATA, which is exactly the harm.
    #
    # THE WALK IS FAIL-SAFE IN ONE DIRECTION BY CONSTRUCTION, which is what makes it safe to put in
    # front of every agent Bash call. It tracks shell quote state char by char; when its model of
    # the quoting disagrees with the shell's, it does so by believing it is INSIDE a quote (an odd
    # apostrophe in a heredoc body — `don't` — parks it there), and inside a quote it substitutes
    # nothing. A miss costs a bats run its QoS band; it cannot corrupt a command. An awk that is
    # missing or errors yields an empty NEWCMD, which the guard below already treats as "no rewrite".
    #
    # A HEREDOC BODY IS NOT A QUOTED REGION, so quote-skipping alone does NOT cover it — and the
    # heredoc is the case that was actually MEASURED doing damage (a probe file was written with
    # substituted bytes). Rather than parse `<<[-]WORD` bodies in front of every Bash call, the walk
    # stops substituting at the first unquoted `<<`: everything after a heredoc or herestring
    # operator is copied verbatim. That is deliberately wider than the body itself — a rewritable
    # token after a heredoc loses its QoS band — and it is the same trade the rest of this block
    # makes, spending a miss to buy the guarantee that agent-authored DATA is never edited.
    #
    # SENTINEL (SOH) marks a run edge that is NOT the true string edge, so `^`/`$` cannot match
    # there — a token abutting a quote is not whitespace-delimited and sed did not match it either.
    # Re-prepending it after each match reproduces sed's /g resume semantics, where `^` no longer
    # applies. Both sentinel bytes are declined outright if the command already carries one.
    #
    # The `*bats*` pre-filter is STRICTLY WEAKER than the pattern it guards — every match contains
    # the literal — so it cannot shadow a real match (memory: cost-gate-must-be-strictly-weaker),
    # and it keeps the char walk off the overwhelming majority of commands.
    case "$CMD" in
      *$'\001'*|*$'\034'*) NEWCMD="" ;;   # a sentinel byte is already present — decline, fail-safe
      *bats*)
        NEWCMD=$(printf '%s' "$CMD" | \
          CC_QOS_REPL="$CC_BATS_TARGET" \
          CC_QOS_PAT="(^|[[:space:]])${_PFX}bats([[:space:]]|\$)" awk '
            function subst(t, atStart, atEnd,   res, rest, m, lead, tail) {
              rest = (atStart ? "" : SENT) t (atEnd ? "" : SENT)
              res  = ""
              while (match(rest, PAT)) {
                m    = substr(rest, RSTART, RLENGTH)
                lead = substr(m, 1, 1);         if (lead !~ /[[:space:]]/) lead = ""
                tail = substr(m, length(m), 1); if (tail !~ /[[:space:]]/) tail = ""
                res  = res substr(rest, 1, RSTART - 1) lead REPL tail
                rest = SENT substr(rest, RSTART + RLENGTH)
              }
              return res rest
            }
            BEGIN { RS = "\034"; SENT = sprintf("%c", 1)
                    REPL = ENVIRON["CC_QOS_REPL"]; PAT = ENVIRON["CC_QOS_PAT"] }
            {
              s = $0; n = length(s); out = ""; run = ""; st = 0; i = 1
              while (i <= n) {
                c = substr(s, i, 1)
                if (st == 0) {                                   # unquoted
                  if (c == "\\")                { run = run substr(s, i, 2); i += 2; continue }
                  if (c == "<" && substr(s, i + 1, 1) == "<") {  # heredoc/herestring — all data
                    out = out subst(run, (out == ""), 0) substr(s, i)
                    run = ""; i = n + 1; break
                  }
                  if (c == "\047" || c == "\"") { out = out subst(run, (out == ""), 0) c
                                                  run = ""; st = (c == "\047") ? 1 : 2
                                                  i++; continue }
                  run = run c; i++
                } else if (st == 1) {                            # inside single quotes
                  out = out c; if (c == "\047") st = 0; i++
                } else {                                         # inside double quotes
                  if (c == "\\") { out = out substr(s, i, 2); i += 2; continue }
                  out = out c; if (c == "\"") st = 0; i++
                }
              }
              out = out subst(run, (out == ""), 1)
              gsub(SENT, "", out)
              printf "%s", out
            }' 2>/dev/null) || NEWCMD=""
        ;;
      *) NEWCMD="" ;;
    esac
    if [ -n "$NEWCMD" ] && [ "$NEWCMD" != "$CMD" ]; then
      emit "$NEWCMD"
    fi
  fi
fi

# ══ TRANSFORMS (b) and (c) — PREFIXING transforms, shared pre-conditions first ════════════════
# Both prepend a wrapper to the command, so both are governed by the same two refusals. They are
# hoisted ABOVE table resolution because they are properties of the COMMAND, not of any table: a
# compound line is unprefixable no matter which table matched it, and checking that once means a
# new transform cannot forget to check it.

# ── only a SINGLE SIMPLE command may be prefixed ──────────────────────────────────────────────
# A prefix is string surgery, and string surgery on a compound line is how you demote the wrong
# half: `taskpolicy -c utility du -s x | sort` would demote `du` but the pipeline's parse is no
# longer ours to reason about, and `a && pytest` would put the prefix on `a`.
# Conservative by design — anything with structure is left ALONE (fail-open, §11.3 M7: "never wrap
# compounds by string surgery"). `(`/`)` cover the brief's `$(` and command grouping in one test.
# The single-quoted metacharacters are LITERALS to match, mirroring rm-safe-allowlist.sh:53-56.
#
# For transform (c) this refusal is also what makes the ceiling SAFE, not merely careful: measured
# over 8.8 days and 56,269 paired Bash calls, 2.611% of ALL agent commands run over 60 s, but of the
# 233 SIMPLE commands starting with a search binary, ZERO exceeded even 30 s. The >60 s "search"
# calls are pipelines that pipe a heavy job through grep, and they are all excluded right here.
case "$CMD" in
  *';'*|*'&'*|*'|'*|*'<'*|*'>'*|*'('*|*')'*|*'`'*|*$'\n'*) exit 0 ;;
esac

# A leading `VAR=value` assignment cannot be prefixed: `taskpolicy -c background VAR=1 pytest`
# tries to EXEC `VAR=1` and dies. The env is the caller's, so we decline rather than re-order it.
# This is a DELIBERATE, MEASURED residual, not an oversight — see KNOWN COVERAGE RESIDUAL in the
# header for why it is the day-one call and what pins it. It doubles as transform (c)'s documented
# opt-out: a command the rewriter declines is a command that runs unbounded.
printf '%s' "$CMD" | grep -qE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' && exit 0

# ── resolve the CHECKOUT directory ONCE, THROUGH SYMLINKS FIRST ───────────────────────────────
# ~/.claude/hooks/<name> is a per-file symlink into the checkout, so a naive
# `dirname "$BASH_SOURCE"` yields ~/.claude/hooks and `../config/...` resolves to
# ~/.claude/config/... — which does not exist and never will, because a symlinked directory does
# not acquire links for NEW files (memory deploy-lag-checkout-behind-origin,
# shared-lib-source-ladder-collapses-when-deployed: the top-level dirs do not auto-deploy).
# Resolving $0 physically lands us in the CHECKOUT's hooks/, where ../config/ is real.
# bash 3.2-safe: macOS has no `readlink -f`.
# ~/.claude/hooks/<name> is a per-file symlink into the checkout, so a naive
# `dirname "$BASH_SOURCE"` yields ~/.claude/hooks and `../config/...` resolves to
# ~/.claude/config/... — which does not exist and never will, because a symlinked directory does
# not acquire links for NEW files (memory deploy-lag-checkout-behind-origin,
# shared-lib-source-ladder-collapses-when-deployed: the top-level dirs do not auto-deploy).
# Resolving $0 physically lands us in the CHECKOUT's hooks/, where ../config/ and ../bin/ are real.
# bash 3.2-safe: macOS has no `readlink -f`.
#
# `../bin/cc-cpubound` is deliberately resolved the SAME way rather than as ~/.claude/bin/cc-cpubound
# (which is how transform (a) finds cc-bats): a NEW file has no symlink in the live layer until the
# next converge tick, so pointing at the checkout makes transform (c) work the moment it lands
# instead of leaving a silent up-to-10-minute window where the table matches and nothing is bounded.
_self="${BASH_SOURCE[0]:-$0}"
_hops=0
while [ -L "$_self" ] && [ "$_hops" -lt 20 ]; do
  _d=$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd) || break
  _self=$(readlink "$_self") || break
  case "$_self" in /*) ;; *) _self="$_d/$_self" ;; esac
  _hops=$((_hops + 1))
done
_dir=$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd) || _dir=""

# ── walk a table: `<field1><TAB><ERE>`, first match wins ───────────────────────────────────────
# Shared by (b) and (c) — one reader, so the two tables cannot drift in how they parse.
# `|| [ -n "$line" ]` so a final line with no trailing newline is still read. No IFS splitting on
# a control character anywhere (memory bash32-case-in-substitution-zsh-repro-trap); the fields come
# out by parameter expansion, which cannot silently no-op. Prints field 1 of the first matching row
# and returns 0; returns 1 on an unreadable table or no match, so "no table" and "no match" are the
# same fail-open outcome for the caller.
table_match() { # <table path>
  local _t="$1" line _f1 _ere
  [ -n "$_t" ] && [ -r "$_t" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}                                 # tolerate a CRLF table
    case "$line" in ''|'#'*) continue ;; esac
    _f1=${line%%$'\t'*}
    _ere=${line#*$'\t'}
    [ "$_f1" != "$line" ] || continue                  # no TAB on this line ⇒ malformed, skip
    [ -n "$_f1" ] && [ -n "$_ere" ] || continue
    if printf '%s' "$CMD" | grep -qE "$_ere" 2>/dev/null; then printf '%s' "$_f1"; return 0; fi
  done < "$_t"
  return 1
}

# ══ TRANSFORM (c) — bound table → CPU-ceiling prefix ══════════════════════════════════════════
# Computed BEFORE (b) only so it can sit outermost in the emitted string; neither depends on the
# other, and either may be empty.
BOUND_PREFIX=""
if [ -n "${CC_QOS_BOUND_PATTERNS+set}" ]; then
  BTABLE="$CC_QOS_BOUND_PATTERNS"       # set-but-EMPTY ⇒ transform (c) OFF, honoured verbatim
else
  BTABLE=""
  [ -n "$_dir" ] && BTABLE="$_dir/../config/qos-bound.patterns"
fi
SECS="$(table_match "$BTABLE")" || SECS=""
if [ -n "$SECS" ]; then
  # CEILING ALLOWLIST — digits only, and > 0. Same reasoning as the band allowlist below: a config
  # file must not be able to break a tool call. cc-cpubound itself also refuses a bad ceiling and
  # runs the command unbounded, so this is the belt to its braces — but the belt matters, because
  # here we can decline to rewrite at all rather than emit a wrapper that will only complain.
  case "$SECS" in
    ''|*[!0-9]*) SECS="" ;;
    *) [ "$SECS" -gt 0 ] 2>/dev/null || SECS="" ;;
  esac
fi
if [ -n "$SECS" ]; then
  # Resolve cc-cpubound and check it EXECUTABLE before naming it — rewriting to a wrapper that is
  # not there turns a working search into exit 127, which is the bad-rewrite failure this file's
  # header refuses. Single-dash `${VAR-default}` so a set-but-EMPTY seam turns (c) off verbatim.
  if [ -n "${CC_QOS_CPUBOUND+set}" ]; then
    CPUBOUND_BIN="$CC_QOS_CPUBOUND"
  else
    CPUBOUND_BIN=""
    # Normalised (`cd -P`) rather than left as `hooks/../bin/…`: unlike the table path, this string
    # is EMITTED, so the agent reads it in its own command line and in any error it reports. The
    # extra fork is paid only on a command that actually matched.
    _bindir=$(cd -P "$_dir/../bin" 2>/dev/null && pwd) || _bindir=""
    [ -n "$_bindir" ] && CPUBOUND_BIN="$_bindir/cc-cpubound"
  fi
  if [ -n "$CPUBOUND_BIN" ] && [ -x "$CPUBOUND_BIN" ]; then
    BOUND_PREFIX="$CPUBOUND_BIN $SECS "
  fi
fi

# ══ TRANSFORM (b) — batch table → demotion prefix ═════════════════════════════════════════════
if [ -n "${CC_QOS_PATTERNS+set}" ]; then
  TABLE="$CC_QOS_PATTERNS"              # set-but-EMPTY ⇒ transform (b) OFF, honoured verbatim
else
  TABLE=""
  [ -n "$_dir" ] && TABLE="$_dir/../config/qos-batch.patterns"
fi
BAND="$(table_match "$TABLE")" || BAND=""

# BAND ALLOWLIST — measured 2026-07-30: taskpolicy(8) parses ONLY these three, and on anything else
# exits 64 WITHOUT RUNNING THE PROGRAM. An unvalidated band in a config file would therefore turn
# every matching command into a no-op failure. A config file must not be able to break a tool call.
case "$BAND" in
  utility|background|maintenance) ;;
  *) BAND="" ;;
esac

TP_PREFIX=""
if [ -n "$BAND" ]; then
  # ── resolve taskpolicy(8); missing ⇒ no demotion prefix ─────────────────────────────────────
  # Single-dash `${VAR-default}`: the default applies only when the var is UNSET, so a set-but-EMPTY
  # seam is honoured verbatim and turns transform (b) off. Hooks run without Homebrew on PATH, so
  # this is absolute (the lesson lead-crash-watchdog.sh:23 records for timeout(1)).
  # ONE binary, not two — see THE BAND, AND WHY nice(1) IS NOT IN THE PREFIX in the header.
  TP_BIN="${CC_QOS_TASKPOLICY-/usr/sbin/taskpolicy}"
  if [ -n "$TP_BIN" ] && [ -x "$TP_BIN" ]; then
    TP_PREFIX="$TP_BIN -c $BAND "
  fi
fi

# ── emit once, or not at all ──────────────────────────────────────────────────────────────────
# Neither prefix, no rewrite: silence means the command runs verbatim. Either or both, one emit —
# so a command in both tables gets both wrappers instead of whichever table was read first.
[ -n "$BOUND_PREFIX" ] || [ -n "$TP_PREFIX" ] || exit 0

emit "${BOUND_PREFIX}${TP_PREFIX}${CMD}"
