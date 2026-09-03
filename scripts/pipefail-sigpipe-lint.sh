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
# ── A THIRD CORRECTION, 2026-08-28, and it is to the paragraph immediately above ────────────────
# Both of that paragraph's negative claims are FALSE, and the parenthetical it dismisses was right.
# Re-measured on this box, /bin/bash 3.2.57 + /usr/bin/grep, needle on line 1, INTERLEAVED (both
# arms in ONE process, order flipping every trial, so load is held constant BY CONSTRUCTION rather
# than by hope — a between-runs rate comparison inside a racy band does not reproduce):
#
#   at 13 B per line          fixed-string `grep -qF`     `grep -iqE` (46-branch ERE)
#     37,121 B / 2,856 lines      763/1,000  RACY             192/1,000  RACY
#     45,000 B / 3,462 lines      268/  300  RACY             244/  300  RACY
#     55,000 B / 4,231 lines      289/  300  RACY             277/  300  RACY
#     65,000 B / 5,000 lines      296/  300  RACY             291/  300  RACY
#     80,000 B / 6,154 lines      300/  300  ALWAYS           300/  300  ALWAYS
#   at 55 B per line
#     37,121 B /   676 lines        0/1,000  SAFE               0/1,000  SAFE
#   at 149 B per line
#     47,442 B /   320 lines        0/1,000  SAFE               0/1,000  SAFE
#
#   · "not probabilistic … deterministically" — REFUTED. 65,000 B reads 296/300, not 10/10; the
#     ALWAYS band does not begin until ~80,000 B. The sharp edge in the table above is an artifact
#     of n=10: at a true rate of 98.7%, ten trials show 10/10 about 88% of the time. The transition
#     is a GRADED BAND, which is the signature of a race and not of a boundary. The tree already
#     knew this and nobody carried it back here — tests/pipefail-sigpipe-lint.bats test 7 says so
#     in its own words ("measured 9/40 nonzero on this very arm … a GRADED BAND, not a step"), so
#     this file's header and this file's own test have been asserting opposite things about one
#     event (memory: alarm-must-key-on-the-store-not-the-sensor is the sibling shape; here it is
#     two diagnostics of one event, and the quieter one was right).
#   · "not the grep implementation" — REFUTED, and this is the clause that stopped anyone looking.
#     At 37,121 B / 2,856 lines the SAME feed bytes with the SAME needle in the SAME interleaved
#     run invert 763/1,000 under `grep -qF` and 192/1,000 under `grep -iqE`. Nothing differs but
#     the consumer's pattern. The mechanism is the reverse of the intuitive one: the SIGPIPE is
#     caused by the consumer EXITING EARLY, so a FASTER consumer is the DANGEROUS one — a fixed
#     string matches on the first read and closes the pipe while the producer still has chunks to
#     write, whereas an -iE consumer compiling a 46-branch DFA is slow enough that the producer
#     often drains and exits cleanly first.
#   · The parenthetical's "differently-shaped payload" was the LINE WIDTH, and it is the third
#     scope this table never carried. At a FIXED 37,121 B, 2,856 lines of 13 B invert 763/1,000
#     while 676 lines of 55 B invert 0/1,000. Every band above was measured at ONE width.
#
# SO: THESE NUMBERS ARE SCOPED TO (bytes, LINE WIDTH, CONSUMER, TRIAL COUNT), AND A BAND QUOTED
# WITHOUT ALL FOUR IS NOT A BAND. That is not pedantry — this repo has already shipped the same
# error one level down twice: a 64 KiB constant measured on a 2-stage pipeline and then reasoned
# about a 3-stage one it is ~2.8x wrong for, and a fixture whose stated size omitted the framing
# the fixture itself introduced (63,488 "62 KiB" was really 64,290 written).
#
# DELIBERATE ZERO, stated rather than hidden: NO TEST ARM PINS THE CONSUMER AXIS, and none can.
# The two consumers differ by 4.0x at 37,121 B and have converged completely by 80,000 B, so the
# axis exists ONLY inside the racy band — where a deterministic assertion is impossible by
# construction. A sweep for a size at which the fixed arm is ALWAYS while the -iE arm is still
# ZERO found none (45,000 / 55,000 / 65,000 / 80,000 / 100,000 / 120,000 B, 300 trials each,
# ~/.claude/autonomy/probe256-band.sh). That is precisely why a wrong claim about this axis could
# sit in this header indefinitely: nothing in the tree can go red over it, so the comment is the
# only carrier and the comment was the thing that was wrong.
#
# ── A FOURTH CORRECTION, 2026-08-28, and it is to the SIBLING ROW, which had never been re-measured
#    at all: THE THREE-STAGE BAND IS NOT SCOPED BY BYTES, AND ITS "BYTES" ARE THE WRONG BYTES. ────
# Seven sites in this tree publish "3-stage  printf | sed | grep -q  safe to 17,427 B · ALWAYS
# inverted from 23,227 B" (tests/gate-ownscope-leak.bats · scripts/moving-ref-control-lint.sh ·
# scripts/test-afunix-path-lint.sh · scripts/worktree-gc.sh · scripts/postland-verify.sh ·
# scripts/limit-recover/lr-reset-poller.sh, twice). The correction above re-measured only the
# 2-stage row and left that one standing. Re-measured on this box, needle on line 1, INTERLEAVED,
# 200 trials per cell (~/.claude/autonomy/probe257-3stage.sh):
#
#   producer bytes held at ~17,427 — THE PUBLISHED SAFE FLOOR — and the WIDTH varied:
#     17,420 B / 1,340 lines of 13 B    sed emits 14,740     0/200  SAFE
#     17,435 B /   317 lines of 55 B    sed emits 16,801    43/200  RACY
#     17,433 B /   117 lines of 149 B   sed emits 17,199    54/200  RACY
#   producer bytes held at ~23,227 — THE PUBLISHED *ALWAYS* FLOOR — width varied:
#     23,231 / 23,225 / 23,210 / 23,244 B at 13 / 25 / 55 / 149 B per line
#                                       137-149 of 200 — RACY, nowhere near ALWAYS.
#   the ALWAYS band is reached at 94,711 emitted bytes (200/200), ~4x higher than published.
#
#   · "safe to 17,427 B" — REFUTED. It is safe at ONE width and 43-54/200 at two others, on the
#     same producer bytes. It was measured at the narrow one.
#   · "ALWAYS inverted from 23,227 B" — REFUTED, and by the same n=20 artifact the 2-stage row was:
#     a 70% rate shows 20/20 about 0.08% of the time, so that reading was not merely imprecise.
#
# AND THE AXIS IS NEITHER BYTES NOR WIDTH NOR LINES. THE BINDING QUANTITY IS WHAT THE STAGE FEEDING
# grep *EMITS*. Measured with everything else nailed down — six cells of 400 lines x 55 B = 22,000
# producer bytes EXACTLY, identical line count, identical width, varying ONLY how many bytes the
# `sed` strips (~/.claude/autonomy/probe257-emit.sh, 400 trials per cell):
#
#     emits 21,200   244/400        emits 15,600     0/400
#     emits 18,000   279/400        emits 13,200     0/400
#     emits 16,400     1/400        emits 10,000     0/400
#
# Nothing about the producer differs across those six. Width was a CONFOUNDER in the width table
# above and not a cause: a 2-byte prefix stripped from a 13-byte line is 15.4% of it and from a
# 149-byte line 1.3%, so width and reduction ratio moved together in every earlier cell.
#
# 🚨 THIS TREE ALREADY KNEW, ONE FILE OVER, AND NOTHING CARRIED IT. scripts/postland-verify.sh:3359
# (commit 11a73819c, 2026-08-27) states it outright — "THE BINDING QUANTITY IS WHAT THE LAST PRE-grep
# STAGE EMITS, NOT WHAT THE PRODUCER WRITES" — and brackets its own transition at post-reduction
# 12,015 B correct / 21,873 B wrong, which straddles the knee measured here. It is the ONE site of
# the seven that got this right, and the other six went on quoting producer bytes for a further day.
# #256's co-sign fires again: WHEN A LOCAL COMMENT HAS TO CONTRADICT THE PUBLISHED NUMBER TO BE
# CORRECT, THE PUBLISHED NUMBER IS THE BUG. (Its RATES are not comparable to these — its last
# pre-grep stage is `tr`, which is block-buffered rather than line-buffered, and its consumer
# differs. The ordering and the named quantity are what agree; do not merge the tables.)
#
# DELIBERATE NON-RESULT, stated rather than rounded: THE KNEE IS NOT A ROUND BUFFER CONSTANT AND I
# DID NOT ESTABLISH ONE. 16,384 was predicted and REFUSED — 16,430 emitted bytes reads 0/400 and
# 16,960 reads 93/400, so the transition begins somewhere in between. Writing "the 16 KiB stdio
# buffer" here would have repeated, one level down, precisely the error the corrections above
# exist to undo: this header asserted "the 64 KiB pipe buffer" as a cause for two months and both
# of its negative clauses were false. A bracket that is measured beats a constant that is tidy.
#
# ── A FIFTH CORRECTION, 2026-08-29: THE EMITTED QUANTITY GOVERNS THE MIDDLE STAGE, AND THE MIDDLE
#    STAGE GOVERNS THE PRODUCER. EXPOSURE IS AN ORDERED LADDER, NOT A PIPELINE-WIDE PROPERTY. ─────
# The fourth correction established WHICH QUANTITY decides. It did not say WHICH STAGE that verdict
# is about, and every sibling comment reads it as a verdict about "the pipeline". Measured with
# per-stage attribution via PIPESTATUS (~/.claude/autonomy/probe258-shield.sh, 200 trials per cell,
# load 21-42, feed 400,000 B, external producer /bin/cat):
#
#     middle             drains?   middle emits     stage1 (producer)   stage2 (middle)
#     sed 's/^L//'         no          390,000          200/200            200/200
#     sort                 yes         400,000            0/200            200/200
#     wc -l                yes               9            0/200              0/200
#     jq -r 'select…'      yes               3            0/200              0/200
#     NEG control: the sed row re-run on a 200 B feed reads 0/200 on both stages.
#
# TWO INDEPENDENT PROTECTIONS, and the ladder is what makes them independent:
#   · stage 2 dies only if what STAGE 2 EMITS clears the knee — that is the fourth correction;
#   · stage 1 dies only if stage 2 died FIRST and stage 1 is still writing. So a middle that emits
#     UNDER the knee protects the producer completely, at ANY producer size. Measured at 400,090
#     producer bytes: `sed -n 's/…/\1/p'` emitting 9,516 B reads 0/200 on both stages, while the
#     SAME feed through `sed 's/^/x/'` emitting 416,504 B reads 200/200 on both. One producer, one
#     producer size, one middle program — and the PRODUCER's verdict flips on the MIDDLE's output.
#   · DRAINING is a second, SIZE-INDEPENDENT protection: it holds even when the middle DOES die.
#     The `sort` row dies 200/200 and its producer still reads 0/200, because a stage that reads to
#     EOF has already let the producer exit. Sufficient, not necessary.
#
# ⚠️ SO "HOW MANY STAGES CAN TAKE SIGPIPE" IS NOT THE STAGE COUNT: across those five cells, at one
# producer size, it is 0, 1 or 2. A three-stage site is not automatically worse than a two-stage
# one — it is worse only where its middle BOTH streams AND emits past the knee.
#
# THE REFUSED PREDICTION IS THE ONE THAT PAID (~/.claude/autonomy/predict258-site.v1-REFUSED.txt).
# It said a STREAMING middle exposes the producer at 400,000 B; measured 0/200, because it reasoned
# about the middle's INPUT. The middle's input is the one quantity in this system that governs
# nothing at all — which is the same error the fourth correction exists to undo, one rung down.
#
# THE POPULATION, measured on this census at 2026-08-29T06:08Z with ~/.claude/autonomy/pipe258.py,
# which segments the LOGICAL line: 126 rows → 119 two-stage, 7 three-stage, 0 four-plus. Of the
# seven, 3 have a STREAMING middle (install.sh:1128 · scripts/banner-shots.sh:258 ·
# scripts/banner-video.sh:167), 3 a DRAINING one (scripts/cloud-ceiling-probe.sh:179 and :351 via
# jq; scripts/test-overwrite-guard.sh:517 via xargs), and 1 has a middle no static screen can
# classify (scripts/test-overwrite-guard.sh:342, whose middle stage is a hook script).
# ⚠️ 13 of those 126 rows SPAN MORE THAN ONE PHYSICAL LINE, so a stage count taken off the census's
# own printed line is wrong for thirteen of them — segment the logical line or do not count at all.
# ────────────────────────────────────────────────────────────────────────────────────────────────
#
# ── A SIXTH CORRECTION, 2026-08-29: DRAINING-vs-STREAMING IS NOT THE DISCRIMINATOR EITHER. THE
#    MIDDLE STAGE'S REDUCTION RATIO IS, AND IT IS SET BY THE FEED'S CONTENT, NOT ITS SIZE. ────────
# The paragraph above states the correct two-part condition in its own words — "worse only where its
# middle BOTH streams AND emits past the knee" — and then partitions the population on the FIRST
# part alone, into 3 STREAMING and 3 DRAINING. Nothing was mis-measured; the partition dropped a
# clause its own sentence carries, and the three STREAMING rows were then read as the exposed set.
# Measured with per-stage PIPESTATUS attribution, 200 trials per cell, load 11.98, external
# producer /bin/cat except where noted (~/.claude/autonomy/probe259-ratio.sh, 9 cells, 9 written
# predictions, 0 mismatches at rc 93):
#
#     cell                              feed B    emitted B   stage1     stage2
#     install sed, REAL feed                70           10    0/200      0/200
#     install sed, 1 match in 458,810 B 458,810           10    0/200      0/200
#     install sed, ALL lines match      406,000      140,000  200/200    200/200
#     the same, builtin printf producer 406,000      140,000  200/200    200/200
#     banner sed, 1 match in 458,798 B  458,798            4    0/200      0/200
#     video  tr -d, 458,759 B           458,759      458,759  200/200    200/200
#     NEG: install sed, ALL match        14,500        5,000    0/200      0/200
#
# ROWS 2 AND 3 ARE THE FINDING: one producer program, one middle program, the same producer size to
# within 13% — and BOTH stages flip from 0/200 to 200/200 on the middle's REDUCTION RATIO alone
# (45,881:1 versus 2.9:1), which is a property of what the feed CONTAINS. The NEG row holds that
# all-match content shape constant and varies only size, reading 0/200, so row 3 is a claim about
# the emitted quantity and not about the shape. The builtin-producer row varies only the producer
# kind and does not move, confirming once more that the producer's identity is not the variable.
#
# SO THE THREE "STREAMING" ROWS ABOVE ARE NOT ONE CLASS, AND ONLY ONE OF THEM IS EXPOSED:
#   · scripts/banner-video.sh:167 — `tr -d '\r, '`, ratio ~1.0. Producer bytes ARE its governing
#     quantity. The ONE row where the reading in the paragraph above is correct. Still latent: its
#     ffprobe flags emit one integer.
#   · scripts/banner-shots.sh:265 — `sed -n 's/.*INNERH=…/\1/p'` emits 4 B from a 458,798 B page.
#     Immune at ANY producer size. Its own comment previously named the page's growth as the thing
#     that would put it back in play; that is refuted by cell E and the comment now says so.
#   · install.sh:1128 — `sed -n 's/.*verdict=\([a-z-]*\).*/\1/p'`. NOT TAKEN, and the measurement is
#     why: exposure needs ~14,000 `verdict=` lines, and scripts/python-deps.sh terminates every one
#     of its eight paths with a single `say "verdict=…"`. The hazard is unreachable by the
#     PRODUCER'S GRAMMAR, which is a stronger and more durable statement than the "latent by three
#     orders of magnitude" size bound it was carried under — a size bound grows with the tree and a
#     grammar bound does not. ⚠️ Its `|| true` asymmetry (guard on the producer line, none on the
#     line that reads it) is REAL and still unfixed; it is worth one token on a link that touches
#     install.sh anyway, and install.sh is named by 41 .bats files.
#
# ⚠️ THE GENERAL FORM, because this is the third link running in which the correct quantity was
# named and the partition was taken on something else: ASK WHAT A VERDICT IS A VERDICT ABOUT, THEN
# CHECK THAT THE PARTITION YOU DREW USES THE SAME VARIABLE THE SENTENCE ABOVE IT NAMES.
# ────────────────────────────────────────────────────────────────────────────────────────────────
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
#      a violation however exposed the pipeline inside looks;
#   5. it is NOT already mitigated by a trailing `|| true` / `|| <fallback>`, which swallows the 141
#      before anything reads it.
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
#
# ── A SEVENTH CORRECTION, 2026-09-01: THE QUOTE-BLIND SPLIT — GATE ONE OF TWO — NOW FIXED ───────
# Every clause above is a judgement about `last` — and `last` used to be chosen one line down by
# `n = split(work, seg, "|")`, a split that knew nothing about quoting. A consumer whose OWN
# ARGUMENT contains a `|` therefore never reached the clause ladder at all: seg[n] was a fragment of
# the PATTERN, is_early() read false on it, and the line was dropped before clause 2 rendered any
# verdict. There are two gates in this detector, all six corrections above are about the second,
# and the first carried no reasons — which is exactly why nobody had audited it.
# The split now runs through qmask() below; this block records what that cost and revealed.
#
# THE SHAPE IT HIDES IS NOT AN ODD ONE, IT IS THE COMMONEST THING A GUARD WRITES. An alternation is
# how a predicate lists the alternatives it must catch, so the sites this split drops skew hard
# toward guards: of the fourteen measured below, SEVEN are hooks or lints whose inversion PERMITS
# the thing they exist to refuse — hooks/rm-safe-allowlist.sh:53 (the dangerous-rm gate),
# hooks/ship-rail-push-allow.sh:62 (the force-push gate), hooks/git-worktree-guard.sh:48 and :69
# (branch-delete and worktree-remove), hooks/lead-crash-watchdog.sh:390,
# scripts/unattended-path-lint.sh:1107, scripts/wait-contract-lint.sh:67.
#
# MEASURED 2026-09-01 BY RUNNING THIS FILE'S OWN PROGRAM TWICE, not by re-implementing it: the
# shipped DETECT_AWK was extracted verbatim, and a mutant built from it differing in exactly ONE
# existing line (the split made quote-aware) — assertion-gated at one removed line, and that line
# the split. Over the same population, same clause-1 filter, same HASE per file:
#   control 125 rows, and the control REPRODUCES `--census` EXACTLY (0 rows of disagreement; that
#     consistency arm is what makes the other two numbers mean anything);
#   quote-aware 139 rows;  LOST = 0;  NEW = 14.  125 + 14 = 139, the partition sums.
# Instrument: ~/.claude/autonomy/{mkawk280.py,qmask280.awk,probe280-split.sh}, all four arms exact.
#
# ONE OF THE FOURTEEN IS LIVE-CAPABLE RATHER THAN LATENT, and it was drained in the same diff:
# scripts/ship-land.sh:3711, the rebase-continue conflict-marker refusal, whose feed is the
# REPLAYED COMMIT'S OWN staged diff — measured 0/20 correct at 200 KB, with 5 of the last 300 trunk
# commits at or past the racy floor. The other thirteen are bounded by inspection today (a single
# command line, a process name, one file's code), and LATENT IS NOT SAFE: every one of those feeds
# is an operational quantity that only grows and nothing announces the crossing.
#
# WHAT IT COST TO LAND, MEASURED 2026-09-02 ON THE SAME HARNESS, RE-RUN RATHER THAN INHERITED:
# thirteen, not fourteen, because #280 had already drained the fourteenth (ship-land.sh:3711) — and
# that site is absent from BOTH programs now, which is the check that distinguishes a real drain
# from a move out of the detector field of view (#243). Control 125 rows and REPRODUCES `--census`
# exactly; quote-aware 138; LOST = 0; NEW = 13; 125 + 13 = 138, the partition asserted to sum.
# Instrument: ~/.claude/autonomy/{mkawk281.py,qmask281.awk,probe281-widen.sh}, 8 arms, all exact.
#
# ALL THIRTEEN WERE DRAINED, AND THE ALLOWLIST DID NOT MOVE — that is the arithmetic that decided
# the scope rather than taste. Every affected file lands back on the count it already carried:
# lead-crash-watchdog 7 to 6, handoff-fire 7 to 5, s3b-lint 2 to 1, wait-contract-lint 3 to 2, and
# the six files that carried NO row at all (cc-memory-rotate, claude-kimi, git-worktree-guard x2,
# rm-safe-allowlist, ship-rail-push-allow, smoke-test, unattended-path-lint) return to zero.
# Grandfathering ANY of them would have meant RAISING a count, which this list's own law forbids —
# it may only SHRINK. So the option that reads as cheaper is the one this file already rules out.
#
# THE POPULATION SKEWED TOWARD GUARDS, AND THAT IS THE FINDING, not an incidental. An alternation
# is how a predicate lists the alternatives it must catch, so the spelling this split dropped is
# the spelling a guard naturally writes: SEVEN of the thirteen are hooks or lints whose inversion
# PERMITS the thing they exist to refuse — hooks/rm-safe-allowlist.sh (the dangerous-rm re-check),
# hooks/ship-rail-push-allow.sh (the never-auto-allow-force invariant), hooks/git-worktree-guard.sh
# x2 (branch-delete and worktree-remove), hooks/lead-crash-watchdog.sh (a deliberate self-close read
# as a crash), scripts/unattended-path-lint.sh (an over-exemption its own comment records fixing),
# scripts/wait-contract-lint.sh. A blind spot correlated with a code STYLE is not random, and it is
# worst exactly where that style is densest.
#
# ONE HALF-DRAIN REPAIRED WHILE HERE: wait-contract-lint.sh:66-67 is a single `&&` chain and only
# its SECOND half was ever visible (the first carries no `&&` on its own physical line, so clause 4
# never reached it). Draining only the visible half would have been #244's shape exactly — the
# drain takes the predicate and leaves the inline copy. Both halves are drained; the count moves by
# one because only one was ever counted.
#
# RESIDUAL, NAMED RATHER THAN WIDENED: qmask() is a quote/substitution masker, not a shell parser.
# It does not join CONTINUATION lines (that gap is owned by ca97c678b18b and pipe258.py is a
# working joiner nobody has wired in), and it treats a dangling quote as opening a context that
# runs to end of line. Neither shows up in today numbers — LOST = 0 says the mask never eats an
# operator pipe on this tree — but both are claims about a tree that grows.
#
# ── THAT RESIDUAL, MEASURED 2026-09-02, AND IT IS ONE RESIDUAL RATHER THAN TWO ─────────────────
# The paragraph above names the two gaps as independent. They are not: the second is a CONSEQUENCE
# of the first and cannot be repaired without it. By shell grammar a physical line carrying an
# unpartnered quote is one of exactly two things — the OPENING line of a multi-line quoted
# construct, whose tail is genuinely DATA and must not be judged, or the CLOSING line of one, whose
# tail is genuinely CODE and should be. The discriminator lives on a PREVIOUS line, so no
# line-local contract can be right about both, and the choice this function makes is not a bug to
# fix but the visible half of the missing join.
#
# ONE CLAUSE ABOVE IS AN OVER-CLAIM AND IS CORRECTED HERE. "LOST = 0 says the mask never eats an
# operator pipe on this tree" is not what LOST = 0 says: LOST counts FINDINGS the quote-aware
# program stopped reporting, so a masked operator pipe only becomes a LOST row if that site was a
# finding to begin with. Measured over the same scanned population: 2,125 lines across 240 files
# end with the quote context still open, and on 135 of them across 58 files at least one `|` was
# masked. The mask eats operator pipes; what LOST = 0 established is that doing so costs no verdict.
#
# THE LIVE EXAMPLE, verified rather than asserted: bin/cc-blockers:1271, the closing line of a
# multi-line jq program. Its first apostrophe CLOSES that program, so the `|` after it is an
# operator — and it is masked, measured 2 raw pipes and 1 survivor. No verdict moves only because
# the consumer is a `while ... read` loop, which is_early() does not match (measured 0, beside a
# positive control at 1 so the zero is not mute). The harmlessness is an accident of the consumer,
# not a property of the mask.
#
# AND THE OBVIOUS REPAIR IS WRONG FOR THIS TREE, which is why arm 25 of the suite now pins it. The
# sibling masker strip280.awk takes the opposite contract — "a quote with no partner is a LITERAL,
# so the tail stays RAW" — and adopting it here changes NOTHING: same two-extractor harness, same
# population, control reproduces --census exactly at 125, mutant 125, LOST = 0, NEW = 0, with a
# FIRE control proving the mutant CAN change a verdict, so the zero is a result and not a silence.
# It does not even repair cc-blockers:1271, whose first apostrophe has a later partner on the line.
# What it would break is the common case: this tree writes 2,125 opening lines of multi-line jq and
# awk programs, and under a partner test their tails are judged as code.
# Instrument: ~/.claude/autonomy/{mkawk282.py,mkmut282.py,probe282-dangle.sh,probe282-contract.sh,
# probe282-example.sh}, 20 gated predictions across three probes, one refused and repaired.
DETECT_AWK='
function ltrim(s) { sub(/^[ \t]+/, "", s); return s }

# GATE ONE. Mask every `|` that is INSIDE a quote or a substitution to \004, so the stage split
# below cuts on pipes that are shell OPERATORS and not on pipes that are pattern bytes. The
# segments are unmasked immediately after the split, so every clause still judges the real text.
#
# A context STACK, not a flag: a `|` is literal inside single quotes; inside double quotes it is
# literal too, EXCEPT within a $( ) where it is an operator again; and a backslash escapes the next
# byte in either. The naive one-flag version of this function read FIVE sites as LOST — a claim
# about the masker, not about the tree — and the rc-93 prediction gate is what refused it.
# (No apostrophes anywhere below: this is a single-quoted bash string. \047 = quote, \042 = dquote,
# \134 = backslash, \044 = dollar.)
function qmask(s,   i, c, d, n, st, out) {
  n = 0; out = ""; i = 1
  while (i <= length(s)) {
    c = substr(s, i, 1)
    d = substr(s, i + 1, 1)
    if (n > 0 && st[n] == 1) {
      if (c == "\047") { n-- }
      else if (c == "|") { out = out "\004"; i++; continue }
    } else if (n > 0 && st[n] == 2) {
      if (c == "\134") { out = out c d; i += 2; continue }
      if (c == "\042") { n-- }
      else if (c == "\044" && d == "(") { n++; st[n] = 3; out = out c d; i += 2; continue }
      else if (c == "|") { out = out "\004"; i++; continue }
    } else {
      if (c == "\134") { out = out c d; i += 2; continue }
      if (c == "\047") { n++; st[n] = 1 }
      else if (c == "\042") { n++; st[n] = 2 }
      else if (c == "\044" && d == "(") { n++; st[n] = 3; out = out c d; i += 2; continue }
      else if (c == ")" && n > 0 && st[n] == 3) { n-- }
    }
    out = out c; i++
  }
  return out
}

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
#
# ── AN EIGHTH CORRECTION, 2026-09-02: THE head/tail ARM WAS STATED IN LINES AND THE PHENOMENON IS
#    DENOMINATED IN BYTES, AND THE ARM ADMITTED NINE VALUES WHERE ONE WAS MEASURED. ──────────────
# The arm below used to read `-?[1-9]` with the reason "bounded: <=9 lines, one write". Both halves
# of that sentence are the same mistake: <=9 lines is not one write, because a line is unbounded in
# bytes and nine of them are nine times unbounded. The sibling arm EIGHT LINES ABOVE gets the unit
# right for echo/printf, in its own words — "ONE write only while what it writes is BOUNDED BY
# INSPECTION ... The command WORD is identical in both cases, so only the argument can decide" —
# and this arm decided from the command word and a LINE count, with the argument never inspected.
#
# WHAT THE MEASUREMENT SAID, and the first prediction was REFUSED, which is why the rest is trusted:
#   · `head -1 <one 218,900-byte line> | grep -q` — predicted >=15/20 orphaned, measured 0 of 20.
#     A LINE-ORIENTED early-exiting consumer cannot exit part-way through a line, so it drains
#     everything a ONE-line producer will ever write. The -1 exoneration is CORRECT and the reason
#     the old comment gave for it was not the reason it holds.
#   · `head -9 F | grep -q` with the needle on line 1 and 226,584 bytes after it — 20 of 20 FALSE,
#     producer rc 141 on every trial. With N>1 the consumer exits on line 1 while the producer
#     still owes lines 2..N, and THOSE bytes are bounded by nothing.
#   · Two negatives separate the claim from its neighbours: the same nine-line shape with a tiny
#     body reads 0/20 (it is the BYTES after the match point, not the line count), and the same big
#     body with the needle on line 9 reads 0/20 (it is an EARLY match, not merely N>1).
#   · FIRE control beside them: `cat` over the same fixture, 20/20 with producer rc 141.
#
# NOT A WIDENING IN EFFECT, measured before landing rather than after (this is the same discipline
# the seventh correction above used): the shipped DETECT_AWK was extracted verbatim as a control and
# a mutant built from it differing in exactly ONE existing line — this one — asserted at one changed
# line and that line the arm. Control reproduces `--census` EXACTLY at 125 rows; mutant 125;
# LOST = 0; NEW = 0; the partition sums. The eight values retired here exonerate NOTHING on this
# tree today, so the detector gets strictly stronger at zero cost in findings and no drains.
# ⚠️ AN INDEPENDENT READER COUNTED 20 LINES CARRYING `head|tail -[2-9]` BEFORE A PIPE, AND NONE OF
# THEM IS A MEMBER: on every one the head/tail is a MIDDLE or LAST stage, and this clause only ever
# judges seg[1]. That column is a SCREEN, not a verdict — it narrows, it does not decide.
# Instrument: ~/.claude/autonomy/{mkawk283.py,probe283-headline.sh,probe283-multiline.sh,
# probe283-arm.sh}; twelve gated predictions, one refused, and the refusal is what corrected the
# reason above rather than merely confirming it.
#
# ── A NINTH CORRECTION, 2026-09-02: THE EIGHTH CORRECTION IS RIGHT AND ITS REASON IS A CLAIM ABOUT
#    THE CONSUMER, IN A CLAUSE THAT WAS HANDED ONLY THE PRODUCER. ─────────────────────────────────
# Read the sentence above as a claim in its own right: "a LINE-ORIENTED early-exiting consumer
# cannot exit part-way through a line". Every word of it is true and it is the reason the -1
# exoneration holds. It is also denominated in the CONSUMER, and clause 3 was called as
# is_external(seg[1]) - the producer alone. Clause 2 had already decided early-exit yes/no and
# discarded WHICH consumer, so the justification covered a strict SUBSET of the consumers the
# exoneration was applied to. That is the eighth correction happening again one clause over: a
# verdict correct on every case anybody had tried, resting on a reason that reaches less far than
# the code does.
# THE SUBSET IS NOT HYPOTHETICAL - is_early admits two BYTE-oriented consumers by construction:
# its head arm is /^head([ \t]|$)/, which matches `head -c N`, and its read arm matches
# `read -n N` / `read -N N`. Neither has to reach a newline to exit.
#
# WHAT THE MEASUREMENT SAID. Producer held CONSTANT at `head -1` over one 218,901-byte line; the
# CONSUMER is the only variable, so a difference between cells cannot be attributed to anything
# else. 20 trials per cell, producer status read as NON-ZERO rather than -eq 141:
#   · `head -1 BIG | grep -q`    line-oriented   0 of 20 orphaned, producer rc 0    (the reason holds)
#   · `head -1 BIG | head -c 10` BYTE-oriented  20 of 20 orphaned, producer rc 141  (it does not)
#   · `head -1 BIG | read -n 1`  BYTE-oriented  20 of 20 orphaned, producer rc 141  (nor here)
#   · negative: `head -1 TINY | head -c 10`      0 of 20 - it is the BYTES still owed at the exit
#     point, not the identity of the consumer.
#   · FIRE control: `cat MULTI | grep -q` 20 of 20, rc 141.
# THE FIRE CONTROL REFUSED FIRST AND THE REFUSAL IS WHY THE REST IS TRUSTED: run 1 put that control
# on the ONE-LINE fixture and predicted 20 of 20, measuring 0. On a one-line file a line-oriented
# consumer cannot exit early whoever produces the bytes, so `cat` and `head -1` are the same
# experiment and the control could not discriminate - the named shape "your fixture makes the two
# candidate answers agree". Repaired with a MULTI-line fixture, which also bought a free re-check:
# `head -1 MULTI | grep -q` is 0 of 20, so the eighth correction survives on a many-line file too.
#
# NOT A WIDENING IN EFFECT: the conjunction of a head/tail -1 producer with a byte-oriented
# early-exit consumer is EMPTY on this tree today (0), against 6 `head -c` consumers and 192 lines
# carrying a head/tail -1 before a pipe - and that 192 is a SCREEN, not a population, since this
# clause only ever judges seg[1]. So this closes a DETECTOR blind spot at zero cost in findings and
# no drains, exactly as the eighth correction did.
# Instrument: ~/.claude/autonomy/probe284-consumer.sh; nine gated predictions, one refused.
#
# ── A TENTH CORRECTION, 2026-09-03: THE NINTH IS RIGHT ABOUT THE *KIND* OF THING THE CLAUSE NEEDS
#    AND WRONG ABOUT *WHICH ONE*. ──────────────────────────────────────────────────────────────
# (No apostrophes anywhere below: this is inside the single-quoted DETECT_AWK string, and one of
# them truncates the whole detector into a silent clean tree.)
# The ninth correction gave clause 3 a consumer to look at, and its reason is denominated in "the
# consumer" - but read that noun precisely and it is THE CONSUMER OF THE PRODUCER BEING JUDGED.
# The call site passed `last` = seg[n], the LAST stage of the pipeline. The producer under judgment
# is seg[1], and the consumer of seg[1] is seg[2]. Those are the same segment IF AND ONLY IF n == 2,
# and this function is never told n. So the unit was right and the REFERENT was not: a corrected
# clause can be handed the right KIND of thing and still the wrong one.
#
# IT FAILED IN BOTH DIRECTIONS, WHICH IS WHY THE REFERENT IS THE CULPRIT AND NOT THE PREDICATE.
# Producer held CONSTANT at `head -1` over one 218,901-byte line; the POSITION of the byte-oriented
# consumer is the only variable. 20 trials per cell, producer status read as NON-ZERO:
#   · `head -1 BIG | head -c 10`                  n=2  20/20 orphaned, rc 141   (anchor, #284 cell B)
#   · `head -1 BIG | grep -q`                     n=2   0/20                    (anchor, #284 cell A)
#   · `head -1 BIG | head -c 10 | grep -q`  BYTE MIDDLE 20/20 orphaned, rc 141
#         -> keyed on `last` (`grep -q`, line-oriented) the clause EXONERATED it. FALSE NEGATIVE.
#   · `head -1 BIG | sed | head -c 10`      line MIDDLE  0/20
#         -> keyed on `last` (`head -c 10`) the clause MINTED it. FALSE POSITIVE. A line-oriented
#            middle stage must read the whole line from the producer before it can emit one byte,
#            so it DRAINS seg[1] before the byte-oriented last stage can exit at all.
#   · `head -1 BIG | sed | grep -q`         both line    0/20  (the drain is done by the MIDDLE)
#   · FIRE control `cat MULTI | grep -q`                20/20, rc 141
# seg[2] answers all five correctly. Instrument: ~/.claude/autonomy/probe285-position.sh (six gated
# predictions, all exact) and probe285-detector.sh, which runs the SHIPPED script and a whole-file
# copy differing in exactly ONE line against a planted fixture and reads what each one SAYS about
# each plant: the shipped one is wrong about exactly one plant in each direction, the copy none.
#
# NOT A WIDENING AND NOT A NARROWING IN EFFECT: over the real tree the two censuses are identical -
# 125 rows both sides, 113 distinct (path, TEXT) keys both sides, LOST = 0 and NEW = 0, with a POS
# control on the key extractor at 43 distinct paths so a zero cannot come from a mute reader. 141
# lines carry a head/tail -1 producer with two or more pipes, but that is a SCREEN and not a
# population - it applies neither qmask nor is_early nor clause 1. So this closes a DETECTOR blind
# spot at zero cost in findings, as the eighth and ninth corrections did.
#
# ── AN ELEVENTH CORRECTION, 2026-09-03: THE TENTH FIXED WHICH INSTANCE *ONE* CLAUSE IS HANDED. THE
#    CLAUSE BESIDE IT WAS STILL DENOMINATED IN A DIFFERENT ONE. ────────────────────────────────────
# Clause 2 and clause 3 are one question about one ADJACENT PAIR - does this consumer exit while
# this producer still owes bytes - and a pipeline of n stages has n-1 pairs. After the tenth
# correction the ladder read:
#     if (!is_early(last))              next   # the consumer of the LAST pair
#     if (!is_external(seg[1], seg[2])) next   # the producer and consumer of the FIRST pair
# Each line is correct in isolation. Their CONJUNCTION describes a pair that does not exist whenever
# n >= 3, and they coincide exactly when n == 2 - which is every case any test in this tree covered.
#
# AND THE GROUND TRUTH BENEATH IT WAS READ ON THE WRONG STAGE TOO. The eighth through tenth
# corrections all measured "the PRODUCER status", meaning seg[1]. This lints verdict is about the
# PIPELINE status, and pipefail is denominated in EVERY stage: one orphaned middle fails the
# pipeline just as loudly as an orphaned first stage. The two readings agree for n == 2 and can
# disagree the moment a middle stage exists to be orphaned.
#
# WHAT THE MEASUREMENT SAID. 20 trials per cell, every status read as NON-ZERO rather than -eq 141,
# with seg1 / seg2 / PIPELINE read separately in the SAME trial:
#   · `head -1 BIG | sed -n p | head -c 10`  seg1 0/20 · seg2 20/20 · PIPELINE 20/20
#         -> this is the arm the tenth correction landed as GREEN (g18). Its stated reason - a
#            line-oriented middle drains the whole line before the last stage can exit - is TRUE of
#            seg[1] and does not make the LINE safe: the middle then owes 218,891 bytes to a
#            consumer that stops at 10. The arm is now r22, RED, with this measurement as its reason.
#   · same shape over a ONE-LINE body               all three 0/20  (it is the bytes still owed)
#   · `cat BIG | head -c 10 | wc -c`        seg1 20/20 · PIPELINE 20/20, and the shipped ladder was
#            SILENT: clause 2 read `wc -c`, which does not exit early. A FALSE NEGATIVE.
#   · `cat BIG | cat | wc -c`               0/20 everywhere - the discrimination cell for the one
#            above: identical producer, identical last stage, only the MIDDLE differs.
#   · anchors reproduced first: `cat MULTI | grep -q` 20/20, `head -1 BIG | grep -q` 0/20.
# Instruments: ~/.claude/autonomy/probe286-pair.sh (11 gated predictions, all exact) and
# probe286-verdict.sh (12, all exact).
#
# WHAT IT COSTS ON THIS TREE, MEASURED BEFORE LANDING. Control = the shipped script; mutant = a
# whole-file copy differing only in this block (mklint286.py asserts head and tail byte-identical).
# --census keyed on (path, TEXT): 125 rows / 113 keys -> 127 rows / 115 keys, LOST = 0, NEW = 2,
# POS control 43 distinct paths. Both new sites are `grep -nF ... | head -1 | cut -d: -f1` in
# tests/announce-before-retire.bats, and both are DRAINED in the same diff. Measured LATENT before
# draining - each needle matches exactly once today (96 and 128 bytes), so the producer owes nothing
# after head -1 exits, 0/20 - with a FIRE control on the identical shape at 20/20 proving the zero
# is real. Latent is not safe: the feed is how often a needle occurs in a 10,622-line file this
# chain edits, and nothing announces the crossing.
# Instrument: ~/.claude/autonomy/probe286-detector.sh (15 gated predictions, all exact) and
# probe286-feed.sh.
function is_byteearly(s,   t) {
  t = ltrim(s); sub(/^[({][ \t]*/, "", t); t = ltrim(t)
  # The flag may sit anywhere in a cluster and may be joined to its value (`-c10`), which is why
  # this cannot be an anchored test - the same reason is_early gives for its own q/l/L cluster scan.
  if (t ~ /^(\/usr\/bin\/|\/bin\/)?head([ \t]|$)/ && t ~ /(^|[ \t])-[A-Za-z]*c([ \t0-9]|$)/) return 1
  if (t ~ /^read([ \t]|$)/ && t ~ /(^|[ \t])-[A-Za-z]*[nN][ \t]*[0-9]/) return 1
  return 0
}
function is_external(s, cons,   t, p) {
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
  # ONE line only, AND ONLY AGAINST A LINE-ORIENTED CONSUMER. A line-oriented early-exiting consumer
  # cannot exit mid-line, so a one-line producer is always drained; -2 through -9 are NOT covered by
  # that argument and measured 20/20 FALSE. See the eighth correction above for those four cells,
  # and the NINTH for why this arm is handed `cons` at all: the reason on this line is a claim about
  # the CONSUMER, and a byte-oriented one exits mid-line and orphans the producer 20/20.
  # The TENTH correction is about WHICH consumer `cons` is: the caller now passes seg[2], the
  # consumer OF THIS PRODUCER, not seg[n]. They are the same segment only when the pipeline has two
  # stages, and this function never sees how many it has.
  if (t ~ /^(head|tail)[ \t]+(-n[ \t]*)?-?1([ \t]|$)/) return is_byteearly(cons)
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

# Clause 5, TWELFTH CORRECTION 2026-09-03: A || SWALLOWS THE PIPELINES STATUS ONLY AT THE TOP LEVEL
# OF THE LAST STAGE. The eleventh correction made clauses 2 and 3 agree about WHICH adjacent pair
# they judge. Clause 5 runs BEFORE that loop and drops the whole LINE, and it was keyed on a ||
# occurring ANYWHERE in seg[n]. Its own sibling clause 3b, twelve lines below, tests the SAME token
# and ALSO requires a group opener - because a || inside a group returns the GROUPs status, not the
# pipelines. So the two clauses agreed about the token and disagreed about its SCOPE, and the file
# already carried the deciding knowledge one clause away: g14 pins { p || true; } | consumer GREEN
# and says in its own label that the group NEUTRALISES the 141, which is a claim about WHERE the
# group is. Nothing pinned the mirror image, so nothing refused it.
#
# WHAT THE MEASUREMENT SAID. Producer held CONSTANT at `cat BIG` and the last command CONSTANT at
# `grep -q NEEDLE`; ONLY the bracketing around the || varies, so a difference between two cells
# cannot be attributed to either end. 20 trials per cell, status read as NON-ZERO rather than
# -eq 141, with PIPESTATUS read in the SAME shell that ran the pipeline:
#   · `cat BIG | grep -q N`                20/20 non-zero, PIPESTATUS [141 0]   FIRE ANCHOR
#   · `cat BIG | grep -q N || true`         0/20   - the || IS top level, and it does swallow
#   · `cat BIG | { grep -q N || true; }`   20/20 non-zero, PIPESTATUS [141 0] - BYTE-IDENTICAL to
#        the anchor. The group returns 0 and pipefail still takes the max over EVERY stage, so the
#        141 survives untouched. The shipped clause 5 exonerated this line: a FALSE NEGATIVE.
#   · `cat BIG | ( grep -q N || true )`    20/20 non-zero - ( ) and { } scope alike, so this cannot
#        key on the brace character the way clause 3b does.
#   · `cat BIG | ( grep -q N ) || true`     0/20 - the NEG that bounds the repair in the OTHER
#        direction: a group in the last stage with the || OUTSIDE it still swallows, so a repair
#        reading "any group opener disqualifies" would MINT this correct line. Only a depth walk
#        separates the two, which is why this is a function and not a regex.
#   · NEG on bytes: the brace shape over an 18-byte body reads 0/20, so the finding stays
#        denominated in the bytes still owed at the exit point and not in the bracketing alone.
#   · MIRROR, already correct and already pinned by g14: `{ cat BIG || true; } | grep -q N` 0/20.
# Instruments: ~/.claude/autonomy/probe287-scope.sh (7 gated predictions, all exact) and
# probe287-stage.sh. r23/r24/g20 pin all three directions.
#
# Quotes are tracked so that a group opener or a || inside a STRING cannot move the depth, and the
# closer arm is guarded at zero: the pipe split hands this function a FRAGMENT, so an unbalanced
# `)` from an enclosing substitution must not drive the depth negative and swallow a real top-level
# || below it. That guard is what keeps g8 - v=$(git log | head -1) || true - GREEN.
#
# AND IT FAILS SAFE ON A FRAGMENT IT CANNOT PARSE, WHICH THE FIRST CUT DID NOT AND WHICH COST A
# MEASURED FALSE POSITIVE. This detector reads PHYSICAL lines; 13 of the census rows span more than
# one. On a continuation line the quote state is unbalanced BY CONSTRUCTION, and a closing quote
# reads as an opening one - so bin/cc-claude-bin:64, whose `|| pin=""` closes an assignment opened
# on line 63, had its || read as QUOTED and was minted. That line is correct code: over the LOGICAL
# line the || is top level and does swallow the 141. Clause 5 is a SCREEN, and a screen that
# convicts on a fragment it cannot parse converts a known blind spot into a wrong verdict. So an
# fragment whose quote state is unbalanced AT A POINT WHERE IT ACTUALLY MATTERS returns 1 - the
# shipped exoneration, unchanged.
#
# BOTH HALVES OF THAT CONDITION ARE LOAD-BEARING AND THE FIRST CUT HAD ONLY ONE. Returning 1 on
# `q != 0` alone is far too blunt: the tail segment of any `VAR="$( a | b )"` ends on an unmatched
# closing quote, so it exonerated SEVEN sites the shipped detector flags - a ratchet SHRINK, which
# is the direction a6449cebc took to block every land in this repo. The ambiguity only bites when a
# || was SKIPPED because of the quote state, so both must hold: a skipped ||, and an unbalanced
# fragment to make the skip untrustworthy. A line with no || at all is unaffected, which is what
# those seven are. Measured across the three cuts: NEW 1 / LOST 0, then NEW 0 / LOST 7, then
# NEW 0 / LOST 0.
# (\002 is the masked ||; \047 quote, \042 dquote, \134 backslash.)
function toplevel_or(s,   i, c, d, q, qor) {
  d = 0; q = 0; qor = 0; i = 1
  while (i <= length(s)) {
    c = substr(s, i, 1)
    if (q == 1) { if (c == "\047") q = 0; else if (c == "\002") qor = 1; i++; continue }
    if (q == 2) { if (c == "\134") { i += 2; continue } if (c == "\042") q = 0; else if (c == "\002") qor = 1; i++; continue }
    if (c == "\134") { i += 2; continue }
    if (c == "\047") { q = 1; i++; continue }
    if (c == "\042") { q = 2; i++; continue }
    if (c == "(" || c == "{") { d++; i++; continue }
    if (c == ")" || c == "}") { if (d > 0) d--; i++; continue }
    if (c == "\002" && d == 0) return 1
    i++
  }
  if (q != 0 && qor) return 1          # a || we SKIPPED, on a fragment we cannot trust - exonerate
  return 0
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

  if (match($0, /<<-?[ \t]*[\x27"]?[A-Za-z_][A-Za-z0-9_]*[\x27"]?/)) {
    tok = substr($0, RSTART, RLENGTH)
    sub(/^<<-?[ \t]*/, "", tok); gsub(/[\x27"]/, "", tok)
    hdterm = "^[ \t]*" tok "[ \t]*$"; inhd = 1
  }

  work = line
  gsub(/\|\|/, "\002", work)          # || is an OR-list, not a pipe
  gsub(/&&/,   "\003", work)          # ditto &&
  n = split(qmask(work), seg, "|")
  for (qi = 1; qi <= n; qi++) gsub("\004", "|", seg[qi])
  if (n < 2) next

  last = seg[n]
  if (toplevel_or(last))    next      # clause 5 - a TOP-LEVEL trailing || swallows the 141

  # Clauses 2 and 3, ELEVENTH CORRECTION 2026-09-03 — they ask ONE question about ONE ADJACENT PAIR,
  # and a pipeline of n stages has n-1 of them. The tenth correction handed clause 3 the consumer of
  # seg[1]; clause 2 went on reading seg[n]. For n == 2 those are the same pair, which is every case
  # any test in this tree covers. For n >= 3 the conjunction was a claim about a pair that does not
  # exist — a producer from the first pair and a consumer from the last. pipefail is denominated in
  # EVERY stage, so the verdict is: does ANY adjacent pair orphan its producer.
  pi = 0
  for (ci = 1; ci < n; ci++) {
    if (!is_early(seg[ci + 1]))             continue   # clause 2, asked of THIS pair
    if (!is_external(seg[ci], seg[ci + 1])) continue   # clause 3, asked of THIS pair
    # Clause 3b — the NEUTRALISE fix. A producer wrapped as `{ p || true; } | consumer` cannot fail
    # the pipeline: the group swallows the 141 before pipefail sees it, so the early exit is KEPT.
    # That matters where draining is expensive — bin/cc-cloud greps a 245 MB binary, where the drain
    # form costs 904 ms and this one 11 ms (measured on an equivalent 38 MB stream), both 0/50.
    if (seg[ci] ~ /\{/ && seg[ci] ~ /\002/) continue
    pi = ci; break
  }
  if (pi == 0) next

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
  if (amp == 0 && !cap && !consumed(line, HASE)) next

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
  expect g12 GREEN "head -1 producer — one line out, and a line-oriented consumer drains it"
  # ── the head/tail producer arm pinned in BOTH directions, 2026-09-02 ──
  # r16/r17 are the FIRE CONTROLS for g11/g12 directly above: each pair differs in exactly ONE
  # variable — the line count — so a green suite over g11/g12 alone credits the arm with nothing.
  # Before the eighth correction in clause 3 these two read GREEN, because the arm exonerated all
  # nine values of `-[1-9]` on a reason measured only for `-1`. Do not merge the four into a loop:
  # the discrimination IS the pairing, and a loop over four subjects is the shape that has twice in
  # this repo produced a test whose title outran what it ran.
  mk r16 "if head -9 \"\$f\" 2>/dev/null | grep -qx -- '---'; then :; fi"
  expect r16 RED "head -9 producer — the consumer exits on line 1 and lines 2..9 are unbounded"
  mk r17 "if tail -5 \"\$LOG\" | grep -q '\"segi\":'; then :; fi"
  expect r17 RED "tail -5 producer — the same defect through the other spelling of the same arm"
  # ── the CONSUMER half of that same arm, pinned in both directions, 2026-09-02 (ninth correction) ──
  # g12 above pins `head -1 | grep -qx` GREEN and is correct, but it credits the arm with nothing on
  # the axis the arm's own reason is denominated in: the reason is "a LINE-oriented consumer cannot
  # exit mid-line", and g12 only ever tries a line-oriented one. r18 is its fire control and the pair
  # differs in exactly ONE variable — the consumer's FLAG, not its command word. g17 is the third
  # cell that makes the pair a discrimination rather than a coincidence: same producer, same consumer
  # COMMAND WORD as r18, line-oriented flag, and it must stay GREEN. That is the sibling builtin
  # arm's lesson applied here — the command word is identical in all three, so only the argument can
  # decide. Measured 20/20 orphaned with producer rc 141 on r18 and r19, 0/20 on g12 and g17.
  # Do not merge these into a loop, for the reason r16/r17 give directly above.
  mk r18 "if head -1 \"\$f\" | head -c 10 >/dev/null; then :; fi"
  expect r18 RED "head -1 producer, BYTE-oriented consumer — head -c exits mid-line, 20/20 orphaned"
  mk r19 "if head -1 \"\$f\" | read -r -n 1 v; then :; fi"
  expect r19 RED "head -1 producer, read -n consumer — the other byte-oriented spelling is_early admits"
  mk g17 "if head -1 \"\$f\" | head -5 >/dev/null; then :; fi"
  expect g17 GREEN "head -1 producer, LINE-oriented consumer — same command word as r18, only the flag differs"
  # ── WHICH consumer, pinned in both directions, 2026-09-03 (tenth correction) ──────────────────
  # r18/g17 above are both TWO-stage, where seg[2] and seg[n] are the same segment — so they pin the
  # ninth correction's predicate and say nothing at all about its REFERENT. These two are the same
  # two consumers at THREE stages, where the two differ, and they are each other's discrimination
  # cell: identical producer, identical pair of consumers, only the ORDER changes. Keyed on `last`
  # r20 was GREEN (a false negative) and g18 was RED (a false positive) — the same referent failing
  # in opposite directions, which is what makes this the call site's bug and not is_byteearly's.
  # Measured 20/20 orphaned with producer rc 141 on r20 and 0/20 on g18.
  # Do not merge these into a loop, for the reason r16/r17 give above.
  mk r20 "if head -1 \"\$f\" | head -c 10 | grep -q x; then :; fi"
  expect r20 RED "BYTE-oriented consumer in the MIDDLE — it is seg[1]'s own consumer and it orphans it 20/20"
  # ── WHICH PAIR, pinned in both directions, 2026-09-03 (eleventh correction) ───────────────────
  # r22 is the arm the tenth correction landed GREEN, as g18. Its reason — a line-oriented middle
  # drains the producer's whole line before the byte-oriented last stage can exit — is TRUE, and it
  # is true about seg[1] only. The middle then owes that whole line to a consumer that stops after
  # ten bytes. Measured on the identical fixture, all three statuses read in the SAME trial:
  # seg1 0/20, seg2 20/20, PIPELINE 20/20 — so the LINE is a defect and only the first stage is
  # innocent. The same shape over a ONE-LINE body is 0/20 everywhere, which keeps this denominated
  # in the bytes still owed rather than in the shape.
  # r21 is the case a ladder keyed on seg[n] cannot see AT ALL: the early exit is in the middle and
  # the last stage drains, so clause 2 answered about `wc -c` and dropped the line before clause 3
  # ran (seg1 20/20, PIPELINE 20/20). g19 is its discrimination cell — identical producer, identical
  # last stage, a middle that does not exit early — and it must stay GREEN, or the pair loop would
  # be passing by convicting every three-stage line rather than by locating the pair.
  # Do not merge these into a loop, for the reason r16/r17 give above.
  mk r22 "if head -1 \"\$f\" | sed s/x/x/ | head -c 10 >/dev/null; then :; fi"
  expect r22 RED "line-oriented MIDDLE drains seg[1] and is then orphaned itself 20/20 — the verdict is the PIPELINE's"
  mk r21 "if cat \"\$f\" | head -c 10 | wc -c >/dev/null; then :; fi"
  expect r21 RED "early exit in the MIDDLE with a DRAINING last stage — invisible to a ladder keyed on seg[n]"
  mk g19 "if cat \"\$f\" | cat | wc -c >/dev/null; then :; fi"
  expect g19 GREEN "r21's discrimination cell: same producer, same last stage, a middle that does not exit early"
  mk g13 "printf '  %s\\n' \"\$(sed -n 's/a/b/p' /some/file | head -1)\""
  expect g13 GREEN "\$( … ) as an ARGUMENT — the outer command's status wins"
  mk_noe g14 "{ strings -a \"\$bin\" 2>/dev/null || true; } | grep -q 'Claude-Session' && return 0"
  expect g14 GREEN "{ p || true; } NEUTRALISES the 141 and keeps the early exit"
  # ── WHICH SCOPE, pinned in all three directions, 2026-09-03 (twelfth correction) ───────────────
  # g14 directly above pins a || inside the PRODUCER's group GREEN, and its own label says the group
  # NEUTRALISES the 141 — which is a claim about WHERE the group is. Clause 5 tested the same token
  # in the LAST stage and never asked that question, so the mirror image of g14 was exonerated by a
  # clause whose sibling twelve lines away already knew better. Nothing pinned the mirror, so
  # nothing refused it.
  # Measured with the producer and the last command held CONSTANT and ONLY the bracketing varying,
  # 20 trials per cell, status read as NON-ZERO, PIPESTATUS read in the same shell as the pipeline:
  # `cat BIG | { grep -q N || true; }` is 20/20 non-zero at PIPESTATUS [141 0] — BYTE-IDENTICAL to
  # the unmitigated `cat BIG | grep -q N`, because the group returns 0 and pipefail still takes the
  # max over EVERY stage. g20 is the arm that stops this being a widening: a group in the last stage
  # with the || OUTSIDE it still swallows (0/20), so a repair reading "any group opener disqualifies"
  # would MINT that correct line. Only a depth walk separates r24 from g20, which is why clause 5 is
  # now a function. r23/r24 measured 20/20 orphaned; g20 and g8 measured 0/20.
  # Do not merge these into a loop, for the reason r16/r17 give above.
  mk r23 "if cat \"\$f\" | { grep -q x || true; }; then :; fi"
  expect r23 RED "|| inside the LAST stage's brace group does NOT swallow the pipeline's 141"
  mk r24 "if cat \"\$f\" | ( grep -q x || true ); then :; fi"
  expect r24 RED "the ( ) spelling of the same scope — the brace character is not the variable"
  mk g20 "if cat \"\$f\" | ( grep -q x ) || true; then :; fi"
  expect g20 GREEN "a group in the last stage with the || OUTSIDE it still swallows — the widening bound"
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

  local total=$((pass+fail))
  if [ "$fail" -gt 0 ]; then
    echo "⛔ $SELF_NAME --selftest: $pass/$total — the detector no longer discriminates." >&2
    return 1
  fi
  echo "✓ $SELF_NAME --selftest: $pass/$total (both directions; builtin producer RED on a variable or substitution, GREEN on a literal)"
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
