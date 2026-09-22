#!/usr/bin/env bats
# statusline-identity — the slim rewrite (audit 06 §5.2) must be OUTPUT-IDENTICAL.
#
# The refactor collapses 8 `echo "$INPUT" | jq` pipelines into one `jq … | @tsv`, and 4 git
# invocations into 2 (`git status --porcelain=v2` replacing `branch --show-current` plus both
# `git diff --quiet` index walks). 109 ms -> ~25-30 ms per render, at 0.15-0.37 renders/s per
# pane. A perf refactor of a thing every pane displays is only safe if the bytes do not move.
#
# So this suite does not assert what the output "should" look like — it diffs the slim script
# against the LAST COMMITTED PRE-SLIM version, byte for byte, over a matrix of payloads x repo
# states. BOTH sides are extracted from git, not hand-copied, so neither can drift.
#
# Harness laws: L1 the baseline is the real prior script from git history; L2 the matrix covers
# the branches that actually differ (feature branch vs main vs detached vs non-repo, clean vs
# dirty, 1M vs 200k window, used_percentage present vs absent); L3 `[ ]` / `diff` only; L4 the
# harness self-checks that the baseline really is the old implementation, so a bad extraction
# cannot make every case pass vacuously.
#
# ── WHY THE SLIM SIDE IS PINNED TO ITS COMMIT, NOT TO HEAD (2026-08-05) ───────────────────────
# This suite originally diffed the pre-slim baseline against the WORKING-TREE statusline.sh. That
# was right while the refactor was in flight, and it is wrong now: it silently promotes "the perf
# refactor moved no bytes" into "statusline.sh may NEVER change its output again". Nobody agreed
# to the second rule, and later commits deliberately broke it — the session-count marker was
# redesigned four times, each for a stated readability reason:
#     f6b0f8a3  negative-circled glyphs — the outline set is unreadable in kitty
#     6a8686a4  instance chip in ASCII — both circled glyph sets failed at the eyes
#     c0970351  paren ring — a one-cell circle is capped by GEOMETRY, not fonts
#     fbbbbef2  per-terminal instance marker — glyph on iTerm2, ASCII ring elsewhere
#     7ab0acb5  gate on TERM_PROGRAM only — ITERM_SESSION_ID is spoofed inside kitty
# So tests 2-9 reddened the tree for every lander, blaming a perf commit for a design decision.
#
# The perf commit is INNOCENT, and that is measured, not argued: pre-slim (93720eb8) vs the slim
# commit as landed (df6b328f) is byte-identical on all 16 matrix cases, and df6b328f renders
# byte-identically to BOTH its parent and its child. The first divergence in this script's whole
# history is f6b0f8a3, one commit later. Attribution came from rendering every historical revision
# — the commit SUBJECT would have misled here, since df6b328f's subject IS the byte-identity claim
# and reading it as the suspect inverts the verdict.
#
# Hence the pin: the matrix compares pre-slim vs the slim commit, both resolved from git BY
# CONTENT (never by hardcoded sha, so a rebase cannot silently repoint them). It certifies exactly
# the claim it was written to certify, and it can no longer convict later design work.
#
# ⚠️ READ THIS BEFORE CALLING TESTS 2-9 VACUOUS: they are a FROZEN PROOF, not a live guard, and
# that is deliberate. A live byte-identity guard is not available at any price — the marker is
# INTENTIONALLY volatile, so any live baseline either freezes the design or needs a hand-maintained
# exclusion list that rots. Do NOT "fix" a future red here by regenerating the baseline from HEAD —
# that compares the script to itself and passes vacuously forever.
#
# ── WHICH QUESTION EACH LAYER ANSWERS (2026-08-09) ────────────────────────────────────────────
# This suite now has TWO layers, because it was asked TWO different questions and the pin above
# only answered the first:
#
#   LAYER 1 — tests 1-9, FROZEN.  "Did the perf refactor move the bytes?"  Answered NO, over a
#             matrix of payloads x repo states, against two blobs resolved from git by content.
#             Historical certification. It cannot go red for a change to statusline.sh, by design.
#   LAYER 2 — the tests below, LIVE.  "Do these specific identity fields still render?"  Per FIELD
#             against the WORKING TREE, so it guards what layer 1 stopped guarding.
#
# Why layer 2 had to exist: with layer 1 frozen, the only live behaviour left was
# untracked-is-not-dirty (test 5) and the process counts (test 10) — and test 5 is a NEGATIVE
# (`no *`), so it is structurally blind to the marker DISAPPEARING. Measured 2026-08-09 by
# mutation: seven single-line mutants of statusline.sh — the fixed-48 buffer offset, IFS=$'\t' in
# the payload read, main-branch suppression, the MECE worktree de-dup, the dirty marker, the effort
# segment, the instance marker — ALL SEVEN left the suite 10/10 green. Two of those seven are
# literal restorations of bugs statusline.sh's own header records as having SHIPPED (the fixed-48
# offset that rendered 37%-real as "86%" on a 1M window, statusline.sh:16-20; the IFS field-shift
# that read remaining_percentage AS used_percentage, statusline.sh:52-55). A suite that cannot
# catch its subject's own two known regressions is not guarding it.
#
# Layer 2 asserts FIELDS, never bytes, and that is what stops the drift recurring: the five 2026-08-02
# marker redesigns would not have reddened one test below. The marker's own coverage is therefore
# DIFFERENTIAL — instance 3 renders differently from instance 1, and the stable launcher renders
# nothing — which holds for any glyph anyone picks next. The one thing layer 2 pins exactly is
# arithmetic (the context %), because that is where both shipped bugs actually lived.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # HERMETICITY (run_gate's blocking test-hermeticity ratchet, and it was RIGHT to block this on
  # arrival): statusline.sh reads $HOME on two paths — the `${1/#$HOME/~}`-style display shortening
  # and the config-dir instance map — so an unfixtured suite renders against the operator's real home
  # and the byte-diff below would compare two runs that BOTH depend on live state. Fixture it before
  # anything else in setup, so every test inherits it (a per-test HOME leaves the others leaking).
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  NEW="$REPO/statusline.sh"
  OLD="$BATS_TEST_TMPDIR/statusline-baseline.sh"
  # The pre-slim version = statusline.sh as of the commit before the slim landed. Find the
  # newest commit whose statusline.sh still had the per-field jq pipelines.
  local sha
  sha=$(cd "$REPO" && git log --format=%H -- statusline.sh \
        | while read -r c; do
            if git show "$c:statusline.sh" 2>/dev/null | grep -q "jq -r '.context_window.used_percentage"; then
              echo "$c"; break
            fi
          done)
  [ -n "$sha" ] || skip "no pre-slim baseline found in history"
  (cd "$REPO" && git show "$sha:statusline.sh") > "$OLD"
  # The slim side of the diff — statusline.sh as the perf refactor LANDED it, i.e. the OLDEST
  # commit that has the porcelain=v2 rewrite. Resolved by content and by AGE (--reverse), so it
  # names the refactor itself rather than any later commit that inherited it, and so no hardcoded
  # sha can be silently repointed by a rebase. Pinned rather than read from the working tree: see
  # the header — the marker is intentionally volatile, and diffing HEAD convicts design work.
  SLIM="$BATS_TEST_TMPDIR/statusline-slim.sh"
  local slim_sha
  slim_sha=$(cd "$REPO" && git log --reverse --format=%H -- statusline.sh \
        | while read -r c; do
            if git show "$c:statusline.sh" 2>/dev/null | grep -q 'porcelain=v2'; then
              echo "$c"; break
            fi
          done)
  [ -n "$slim_sha" ] || skip "no slim commit found in history"
  (cd "$REPO" && git show "$slim_sha:statusline.sh") > "$SLIM"
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/telemetry"
  mkdir -p "$CC_TELEMETRY_DIR"
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK"
}

# The baseline must really be the OLD implementation, or every diff passes for free.
@test "harness self-check: the baseline is the pre-slim implementation" {
  grep -q "jq -r '.context_window.used_percentage" "$OLD"
  grep -q 'git branch --show-current' "$OLD"
  # `|| false` is LOAD-BEARING: a non-final `!` is errexit-EXEMPT under bats, so this line was DEAD —
  # it could not fail. In the harness self-check whose entire purpose is "the baseline really is the
  # old implementation, or every diff below passes for free", a dead assertion is the vacuous pass it
  # exists to prevent. Found by a dead-assertion sweep of this row's suites, 2026-07-29
  # (memory bats-dead-assertions-errexit-exemptions). Only NON-final ones are exempt — the last `!`
  # in this body is the test's own exit status and is live.
  ! grep -q 'porcelain=v2' "$OLD" || false
  # ...and the new one is not
  grep -q 'porcelain=v2' "$NEW"
  ! grep -q "jq -r '.context_window.used_percentage" "$NEW" || false
  # The SLIM side needs the same two-way check, and for the same reason: it is the other half of
  # every diff below, so an extraction that silently returned the pre-slim blob (or HEAD) would
  # make the whole matrix pass for free. Assert it is post-slim AND that it is not merely a copy
  # of the baseline. `|| false` on the negative for the errexit-exemption reason above.
  grep -q 'porcelain=v2' "$SLIM"
  ! grep -q "jq -r '.context_window.used_percentage" "$SLIM" || false
  ! cmp -s "$OLD" "$SLIM" || false
}

# fixture payloads --------------------------------------------------------------------------
payload_full() {
  jq -nc '{session_id:"aaaa-bbbb-cccc",
           transcript_path:"/Users/x/.claude-tertiary/projects/-Users-x-p/aaaa.jsonl",
           model:{id:"claude-opus-4-8"}, effort:{level:"max"},
           context_window:{context_window_size:1000000, used_percentage:47,
                           remaining_percentage:53, total_input_tokens:470000},
           exceeds_200k_tokens:true, cwd:"/Users/x/p"}'
}
payload_legacy() {   # no used_percentage → the reserved-space ESTIMATE path, 200k window
  jq -nc '{session_id:"dddd-eeee-ffff",
           transcript_path:"/Users/x/.claude-next/projects/-Users-x-p/dddd.jsonl",
           model:{id:"claude-opus-4-8"}, effort:{level:"medium"},
           context_window:{context_window_size:200000, remaining_percentage:70,
                           total_input_tokens:60000},
           cwd:"/Users/x/p"}'
}
payload_bare() {     # no effort, no context_window, no transcript_path
  jq -nc '{session_id:"9999-8888-7777", model:{id:"claude-opus-4-8"}, cwd:"/Users/x/p"}'
}

# run both scripts on the same payload in the same cwd and compare bytes
identical() { # <payload-producer> <dir>
  local p a b
  p=$("$1")
  a=$(cd "$2" && printf '%s' "$p" | bash "$OLD" 2>/dev/null | cat -v)
  b=$(cd "$2" && printf '%s' "$p" | bash "$SLIM" 2>/dev/null | cat -v)
  [ "$a" = "$b" ] || {
    printf 'PRE-SLIM: %s\nSLIM:     %s\n' "$a" "$b" >&2
    return 1
  }
}

mk_repo() { # <dir> <branch>
  # `git -C ""` is a NO-OP, not an error — an empty <dir> would write this identity into the cwd repo.
  : "${1:?mk_repo: repo path required}"
  mkdir -p "$1"; git init -q "$1"
  git -C "$1" config user.email t@t; git -C "$1" config user.name t
  printf 'x\n' > "$1/f"; git -C "$1" add -A; git -C "$1" commit -qm init
  [ -n "${2:-}" ] && git -C "$1" checkout -q -b "$2"
  return 0
}

# ── the matrix ─────────────────────────────────────────────────────────────────────────────────

@test "identical on a FEATURE branch, clean worktree (all 3 payloads)" {
  mk_repo "$WORK/wt-feature-x" feature-x
  identical payload_full   "$WORK/wt-feature-x"
  identical payload_legacy "$WORK/wt-feature-x"
  identical payload_bare   "$WORK/wt-feature-x"
}

@test "identical on a feature branch with UNSTAGED changes (the dirty marker)" {
  mk_repo "$WORK/dirty-unstaged" feature-y
  printf 'changed\n' > "$WORK/dirty-unstaged/f"
  identical payload_full   "$WORK/dirty-unstaged"
  identical payload_legacy "$WORK/dirty-unstaged"
}

@test "identical on a feature branch with STAGED changes" {
  mk_repo "$WORK/dirty-staged" feature-z
  printf 'changed\n' > "$WORK/dirty-staged/f"
  git -C "$WORK/dirty-staged" add -A
  identical payload_full "$WORK/dirty-staged"
}

@test "identical with only UNTRACKED files — must NOT be marked dirty either way" {
  mk_repo "$WORK/untracked" feature-u
  printf 'new\n' > "$WORK/untracked/brand-new-file"
  identical payload_full "$WORK/untracked"
  # and prove the shared verdict is "clean" (a * here would be a real behaviour change).
  # DELIBERATELY against $NEW, the WORKING TREE script, not the pinned $SLIM: this one asserts a
  # behaviour rather than a byte sequence, so unlike the diff above it stays a live regression
  # guard and is unaffected by the marker redesigns. Keep it on $NEW.
  run bash -c "cd '$WORK/untracked' && payload='$(payload_full)'; printf '%s' \"\$payload\" | bash '$NEW'"
  ! echo "$output" | grep -q '\*'
}

@test "identical on the worktree-named dir (the MECE de-duplication branch)" {
  mk_repo "$WORK/wt-dedupe-me" dedupe-me     # dir == wt-<branch> ⇒ branch segment dropped
  printf 'changed\n' > "$WORK/wt-dedupe-me/f"
  identical payload_full "$WORK/wt-dedupe-me"
}

@test "identical on main (branch segment suppressed) and when detached" {
  mk_repo "$WORK/on-main" ""
  identical payload_full "$WORK/on-main"
  git -C "$WORK/on-main" checkout -q --detach
  identical payload_full "$WORK/on-main"
  identical payload_bare "$WORK/on-main"
}

@test "identical outside any git repo" {
  mkdir -p "$WORK/not-a-repo"
  identical payload_full   "$WORK/not-a-repo"
  identical payload_legacy "$WORK/not-a-repo"
  identical payload_bare   "$WORK/not-a-repo"
}

@test "identical on empty and malformed payloads" {
  mk_repo "$WORK/edge" feature-e
  local a b
  a=$(cd "$WORK/edge" && printf '' | bash "$OLD" 2>/dev/null | cat -v)
  b=$(cd "$WORK/edge" && printf '' | bash "$SLIM" 2>/dev/null | cat -v)
  [ "$a" = "$b" ]
  a=$(cd "$WORK/edge" && printf '{not json' | bash "$OLD" 2>/dev/null | cat -v)
  b=$(cd "$WORK/edge" && printf '{not json' | bash "$SLIM" 2>/dev/null | cat -v)
  [ "$a" = "$b" ]
}

# ── and the refactor actually removed the processes it claimed to ──────────────────────────────
@test "the payload is read by ONE jq extraction, and git is called twice" {
  # per-FIELD reads (`jq -r '.something'`) are what the refactor removed; the telemetry EMIT
  # legitimately keeps its `echo "$INPUT" | jq -c`, so count field reads, not the word jq.
  [ "$(grep -cF 'echo "$INPUT" | jq -r' "$OLD")" -eq 7 ]     # per-field payload reads, gone:
  [ "$(grep -cF 'echo "$INPUT" | jq -r' "$NEW")" -eq 0 ]
  [ "$(grep -cF '"$INPUT" | jq -r' "$NEW")" -eq 1 ]          # replaced by exactly ONE extraction
  # every jq invocation that remains, and why it has to: 1 extraction + 1 memoized pid read
  # from the prior telemetry FILE + 1 telemetry EMIT (it writes JSON, so it needs jq) + 1
  # durable-window EMIT (same reason, and it runs ONCE per session behind a grep guard rather than
  # per render — row 5e4ce121b64a residual (b)). The count stays EXACT deliberately: the invariant
  # this pins is not "few jq calls" but "every jq call on a per-render path is enumerated here with
  # its reason", so an unexplained addition still reddens. The durable-window READ is not in this
  # count because it reuses PAY_WINDOW from the single extraction instead of re-reading the payload.
  [ "$(grep -cE 'jq -[rc] ' "$NEW")" -eq 4 ]
  [ "$(grep -cE 'jq -[rc] ' "$OLD")" -eq 9 ]
  grep -qF "jq -r '.pid // empty'" "$NEW"
  # git: count CODE lines only — the new header explains the old `git diff` probes in prose.
  code() { grep -vE '^[[:space:]]*#' "$1"; }
  [ "$(code "$NEW" | grep -cE '^[[:space:]]*(COMMIT|GIT_STATUS)=\$\(git')" -eq 2 ]
  [ "$(code "$NEW" | grep -c 'git diff')" -eq 0 ]
  [ "$(code "$NEW" | grep -c 'git branch --show-current')" -eq 0 ]
  [ "$(code "$OLD" | grep -cE '^[[:space:]]*(COMMIT|BRANCH)=\$\(git')" -eq 2 ]
  [ "$(code "$OLD" | grep -c 'git diff --quiet')" -eq 1 ]     # the two index walks, one line
}

# ═══ LAYER 2 — the LIVE per-field guard (see "WHICH QUESTION EACH LAYER ANSWERS") ═══════════════
# Everything below runs the WORKING-TREE script ($NEW) and asserts a FIELD. Nothing below compares
# a byte sequence to a baseline, so a marker redesign cannot redden any of it.

payload_1m_estimate() {  # no used_percentage → the ESTIMATE path, on a 1M window
  jq -nc '{session_id:"1111-2222-3333",
           transcript_path:"/Users/x/.claude-next/projects/-Users-x-p/1111.jsonl",
           model:{id:"claude-opus-4-8"}, effort:{level:"medium"},
           context_window:{context_window_size:1000000, remaining_percentage:70,
                           total_input_tokens:300000},
           cwd:"/Users/x/p"}'
}
payload_divergent() {    # used_percentage and remaining_percentage deliberately NOT complementary
  # Fixture design note: payload_full carries used:47 / remaining:53, so "display used_percentage"
  # and "compute 100 - remaining_percentage" produce the SAME 47 and no assertion over it can tell
  # the two apart — a mutant swapping one for the other survived the whole suite (2026-08-09).
  # 47/40 discriminates the FIELD. It is a discriminating fixture, not a claim that a real payload
  # diverges this far.
  jq -nc '{session_id:"6666-6666-6666",
           transcript_path:"/Users/x/.claude-tertiary/projects/-Users-x-p/6666.jsonl",
           model:{id:"claude-opus-4-8"}, effort:{level:"max"},
           context_window:{context_window_size:1000000, used_percentage:47,
                           remaining_percentage:40},
           cwd:"/Users/x/p"}'
}
payload_stable() {       # the STABLE launcher's config dir — not in the ordinal map ⇒ no marker
  jq -nc '{session_id:"5555-5555-5555",
           transcript_path:"/Users/x/.claude/projects/-Users-x-p/5555.jsonl",
           model:{id:"claude-opus-4-8"}, effort:{level:"high"},
           context_window:{context_window_size:1000000, used_percentage:47},
           cwd:"/Users/x/p"}'
}

# Render $NEW and strip SGR colour, so an assertion names a FIELD rather than a byte sequence.
# Every ambient input the script reads is PINNED here, because the VERIFIER'S OWN environment
# reaches it — measured on this box 2026-08-09: a live session exports
# CLAUDE_CONFIG_DIR=~/.claude-secondary (so a payload without transcript_path would render the
# marker for whichever ACCOUNT ran the suite), ITERM_SESSION_ID (~/.zshrc exports it INSIDE kitty
# by design — statusline.sh:314-320), and TERM=xterm-kitty. Unpinned, these tests would assert the
# verifier's terminal instead of the script. Later VAR=VAL wins (env(1); verified).
render() { # <payload-producer> <dir> [VAR=VAL ...]
  local p d; p=$("$1"); d="$2"; shift 2
  ( cd "$d" && printf '%s' "$p" \
      | env -u CLAUDE_INSTANCE_N -u ITERM_SESSION_ID -u KITTY_WINDOW_ID \
            CLAUDE_CONFIG_DIR= TERM_PROGRAM=not-iterm TERM=xterm-256color \
            "$@" bash "$NEW" 2>/dev/null
  ) | sed $'s/\033\[[0-9;]*m//g'
}
# The line is ${GLYPH_PREFIX}${PCT_SEG}${OUTPUT} and OUTPUT starts with the dir name, so the dir
# splits the head from the body. Keeping them apart is what makes this layer drift-proof: the
# marker is asserted only DIFFERENTIALLY (below), and the body assertions cannot see a marker
# redesign at all.
#
# The head carries TWO fields since the context % moved off the end of the line (2026-08-11), so
# marker_of alone is no longer the instance marker — chip_of and pct_of split it, and every
# instance-marker assertion below uses chip_of. That is not cosmetic: `m3 != m1` compares two
# payloads whose percentages ALSO differ (47 vs 78), so on the raw head it passes on the
# PERCENTAGE alone and stops testing the account identity it exists to test.
#
# Mutation-measured 2026-08-11, blanking the ordinal so both chips render `()`:
#     marker_of   m3=[() 47% ]  m1=[() 78% ]   ->  m3 != m1 PASSES — blind to the mutant
#     chip_of     m3=[()]       m1=[()]        ->  m3 != m1 RED    — catches it
# Scope of that claim, stated exactly: the CASE still reddens under marker_of, but via the
# unrelated `[ -z "$mstable" ]` assertion (a chipless render's head becomes "47% ", so it is
# no longer empty). So the erosion is one assertion going vacuous behind a neighbour that
# happens to fail — the kind that survives a green suite the moment the neighbour changes.
marker_of() { printf '%s' "${1%%"$2"*}"; }                       # <line> <dir> — chip + context %
# ── W4 (U07 2026-09-19): the head gained an IDENTITY segment between the chip and the % ────────
# statusline.sh now renders `#<pane> <sid8> ` there — two fields that are unique by construction,
# where every other field on the line is a property of a GROUP or of a MOMENT (U07 §4: two of
# sixteen live panes render a byte-identical line). It is peeled off HERE, at the head parser,
# rather than asserted away in each case, so every marker assertion below keeps testing the
# MARKER — `[ "$spoof" = "$base" ]` in the iTerm2-gate case sets ITERM_SESSION_ID and would
# otherwise compare a head that carries `#901` against one that does not, and pass for the
# wrong reason.
#
# The peel names the two token SHAPES rather than a position, because each half is rendered
# independently (statusline.sh omits the pane token when no pane env is set and the sid8 token
# when the payload carries no session_id — that independence is what the two new cases below
# mutation-check). `marker_of` stays RAW: `body_of` subtracts it from the line as a literal
# prefix, and `pct_of` already reads the LAST space-separated token, so neither needs the peel.
peel_id() { # <head> → the head with the identity segment removed
  printf '%s' "$1" | sed -e 's/#[^ ]* //' -e 's/#[0-9][^ ]* //' \
                         -e 's/[0-9a-fA-F][0-9a-fA-F-]\{7\} //'
}
chip_of()   { local m; m=$(marker_of "$1" "$2")                  # the instance marker alone
              m="$(peel_id "$m")"                                # drop `#<pane> <sid8> ` (W4)
              m="${m% [0-9]*% · }"                               # chip present: "(3) 47% · "
              m="${m#[0-9]*% · }"                                # chip absent:  "47% · "
              printf '%s' "$m"; }
pct_of()    { local m; m=$(marker_of "$1" "$2"); m="${m% · }"; printf '%s' "${m##* }"; }
body_of()   { local m; m=$(marker_of "$1" "$2"); printf '%s' "${1#"$m"}"; }

@test "live: dir, short commit, feature branch and the DIRTY marker all render" {
  mk_repo "$WORK/live-plain" some-branch
  local sha line
  sha=$(git -C "$WORK/live-plain" rev-parse --short HEAD)
  line=$(render payload_full "$WORK/live-plain")
  [ "$(body_of "$line" live-plain)" = "live-plain ($sha)  some-branch · max" ]
  # the POSITIVE twin of test 5. Test 5 asserts NO `*` for untracked files; on its own that is
  # satisfied by a dirty marker that never renders at all (mutation-confirmed 2026-08-09).
  printf 'changed\n' > "$WORK/live-plain/f"
  line=$(render payload_full "$WORK/live-plain")
  [ "$(body_of "$line" live-plain)" = "live-plain ($sha)  some-branch* · max" ]
  # and staged-only is dirty too (porcelain v2 `1` records, either index side)
  git -C "$WORK/live-plain" add -A
  line=$(render payload_full "$WORK/live-plain")
  [ "$(body_of "$line" live-plain)" = "live-plain ($sha)  some-branch* · max" ]
}

@test "live: main and detached HEAD suppress the branch segment" {
  mk_repo "$WORK/live-main" ""
  local sha line
  sha=$(git -C "$WORK/live-main" rev-parse --short HEAD)
  line=$(render payload_full "$WORK/live-main")
  [ "$(body_of "$line" live-main)" = "live-main ($sha) · max" ]
  git -C "$WORK/live-main" checkout -q --detach
  line=$(render payload_full "$WORK/live-main")
  [ "$(body_of "$line" live-main)" = "live-main ($sha) · max" ]
  # a branch that is NOT main/master must still show — otherwise "suppressed" is unfalsifiable
  git -C "$WORK/live-main" checkout -q -b keeper
  line=$(render payload_full "$WORK/live-main")
  [ "$(body_of "$line" live-main)" = "live-main ($sha)  keeper · max" ]
}

@test "live: a wt-<branch> dir renders the branch ONCE, dirty folded onto the dir (MECE)" {
  mk_repo "$WORK/wt-live-dedupe" live-dedupe
  local sha line
  sha=$(git -C "$WORK/wt-live-dedupe" rev-parse --short HEAD)
  line=$(render payload_full "$WORK/wt-live-dedupe")
  [ "$(body_of "$line" wt-live-dedupe)" = "wt-live-dedupe ($sha) · max" ]
  printf 'changed\n' > "$WORK/wt-live-dedupe/f"
  line=$(render payload_full "$WORK/wt-live-dedupe")
  [ "$(body_of "$line" wt-live-dedupe)" = "wt-live-dedupe* ($sha) · max" ]
  # ...and the de-dup must not fire when the dir does NOT encode the branch, or "renders once"
  # is unfalsifiable — the same repo on a renamed branch keeps its separate branch segment.
  git -C "$WORK/wt-live-dedupe" checkout -q -b unrelated
  line=$(render payload_full "$WORK/wt-live-dedupe")
  [ "$(body_of "$line" wt-live-dedupe)" = "wt-live-dedupe ($sha)  unrelated* · max" ]
}

@test "live: the effort segment renders the payload's own effort level" {
  mk_repo "$WORK/live-effort" some-branch
  local line
  line=$(render payload_full "$WORK/live-effort")     # effort: max
  [ "${line% · max}" != "$line" ]
  line=$(render payload_legacy "$WORK/live-effort")   # effort: medium
  [ "${line% · medium}" != "$line" ]
  # absent effort must render NO empty segment (payload_bare has no .effort)
  line=$(render payload_bare "$WORK/live-effort")
  ! printf '%s' "$line" | grep -q ' ·  ' || false
  ! printf '%s' "$line" | grep -q ' · $' || false
}

@test "live: context % — exact on the parity path, WINDOW-SCALED on the estimate path" {
  mk_repo "$WORK/live-ctx" some-branch
  local line
  # parity path: used_percentage is displayed as-is (integer-truncated), never recomputed.
  line=$(render payload_full "$WORK/live-ctx")
  [ "$(pct_of "$line" live-ctx)" = "47%" ]
  # ...and it really is that FIELD being read: on a payload whose two figures do not sum to 100,
  # deriving from remaining_percentage would render 60%. This is the assertion that fails if the
  # parity path ever starts recomputing what the payload already states exactly.
  line=$(render payload_divergent "$WORK/live-ctx")
  [ "$(pct_of "$line" live-ctx)" = "47%" ]
  ! printf '%s' "$line" | grep -q '60%' || false
  # estimate path (no used_percentage): 97000 reserved tokens are scaled to the REAL window.
  #   200k → offset 48 → 70-48 = 22 remaining → 78% used
  #   1M   → offset  9 → 70- 9 = 61 remaining → 39% used
  # SAME remaining_percentage (70), different window ⇒ different answer. This pair is the whole
  # point: with the pre-2026-07-13 FIXED 48-point offset the 1M case renders 78% — the measured
  # ~2.3x overstatement that relieved a 47%-real lead as "95% context" (statusline.sh:16-20).
  line=$(render payload_legacy "$WORK/live-ctx")
  [ "$(pct_of "$line" live-ctx)" = "78%" ]
  line=$(render payload_1m_estimate "$WORK/live-ctx")
  [ "$(pct_of "$line" live-ctx)" = "39%" ]
  # and the fields must stay POSITIONAL: payload_1m_estimate has no used_percentage, so a
  # whitespace IFS in the one-shot payload read would shift remaining_percentage into USED and
  # render 70%. The US separator is what keeps empty fields positional (statusline.sh:52-55).
  ! printf '%s' "$line" | grep -q '70%' || false
  # no context block at all when the payload carries neither figure
  line=$(render payload_bare "$WORK/live-ctx")
  ! printf '%s' "$line" | grep -q '%' || false
}

@test "live: the parallel-instance marker distinguishes instances and is ABSENT on stable" {
  mk_repo "$WORK/live-inst" some-branch
  # DIFFERENTIAL, never a glyph literal — the marker was redesigned five times on 2026-08-02 and
  # is expected to change again. What must hold for ANY design: a mapped config dir renders SOME
  # marker, two different instances render DIFFERENT ones, and the stable launcher renders none.
  local m3 m1 mstable
  m3=$(chip_of "$(render payload_full   "$WORK/live-inst")" live-inst)   # .claude-tertiary → 3
  m1=$(chip_of "$(render payload_legacy "$WORK/live-inst")" live-inst)   # .claude-next     → 1
  mstable=$(chip_of "$(render payload_stable "$WORK/live-inst")" live-inst)
  [ -n "$m3" ]
  [ -n "$m1" ]
  [ "$m3" != "$m1" ]
  [ -z "$mstable" ]
  # route 1: the explicit override wins over the config-dir map, and a malformed one falls
  # through to the map rather than blanking the marker (statusline.sh:246-249).
  local mov mbad
  mov=$(chip_of "$(render payload_full "$WORK/live-inst" CLAUDE_INSTANCE_N=7)" live-inst)
  [ -n "$mov" ]
  [ "$mov" != "$m3" ]
  mbad=$(chip_of "$(render payload_full "$WORK/live-inst" CLAUDE_INSTANCE_N=nonsense)" live-inst)
  [ "$mbad" = "$m3" ]
}

@test "live: the iTerm2 glyph gate keys on TERM_PROGRAM, not on a spoofable ITERM_SESSION_ID" {
  mk_repo "$WORK/live-term" some-branch
  # MOVED, not weakened (W2.5): every assertion below is unchanged; only the fixture moved onto
  # the path where the gate still lives. A mapped config dir now renders the ACCOUNT NAME
  # (`next3`), and a name is not a one-cell glyph — the whole geometry argument the gate exists
  # for is about drawing a NUMBER inside one cell — so there is no per-terminal choice left to
  # make there. Route 1 ($CLAUDE_INSTANCE_N) is naming-INDEPENDENT by contract, so an instance
  # identified only by number still has an ordinal to draw and still takes this gate.
  local base iterm spoof kitty
  ordinal() { chip_of "$(render payload_full "$WORK/live-term" CLAUDE_INSTANCE_N=3 "$@")" live-term; }
  base=$(ordinal)
  iterm=$(ordinal TERM_PROGRAM=iTerm.app)
  [ "$iterm" != "$base" ]      # iTerm2 opts IN by name — otherwise the gate is doing nothing
  # 🚨 the 7ab0acb5 regression, stated as an EQUALITY so no glyph literal appears: ~/.zshrc
  # exports ITERM_SESSION_ID inside kitty BY DESIGN (Claude Code gates its pane backend on it),
  # so a render that trusts it hands the unreadable small glyph back to kitty — which shipped,
  # and broke within minutes. Setting it alone must change NOTHING.
  spoof=$(ordinal ITERM_SESSION_ID=w0t0p0:901)
  [ "$spoof" = "$base" ]
  # belt-and-braces conjunct: an iTerm2 session launched from a kitty pane inherits the kitty
  # vars permanently, so $TERM — set by the emulator on each attach — wins the tie.
  kitty=$(ordinal TERM_PROGRAM=iTerm.app TERM=xterm-kitty)
  [ "$kitty" = "$base" ]
}

@test "live: the instance marker is the ORDINAL, on the config-dir map and the override alike" {
  mk_repo "$WORK/live-name" some-branch
  # REVERSED from W2.5 (operator ruling 2026-08-11, "change it back to N"). W2.5 had made this
  # case assert the account NAME — `(next3)` — on the argument that an ordinal makes you hold
  # `.claude-tertiary → 3 → next3` in your head. The operator reversed it on sight: the mapping
  # is one they know cold, and `(next3)` spends 5 more columns than `(3)` on every render.
  #
  # This is the ONE literal-content assertion in this suite, and it stays deliberate through the
  # reversal: the marker's DESIGN is differential above, but WHICH instance it identifies is
  # content, not decoration. A future redesign is free to change the frame, never to stop
  # answering the question — and both directions of this preference are now on record, so the
  # name is not re-proposed as if it had never been tried.
  #
  # $render pins TERM_PROGRAM=not-iterm, so the chip is the ASCII ring, not the circled glyph.
  local m3 m1
  m3=$(chip_of "$(render payload_full   "$WORK/live-name")" live-name)   # .claude-tertiary → 3
  m1=$(chip_of "$(render payload_legacy "$WORK/live-name")" live-name)   # .claude-next     → 1
  [[ "$m3" == *"(3)"* ]] || { printf 'marker: %s\n' "$m3" >&2; false; }
  [[ "$m1" == *"(1)"* ]] || { printf 'marker: %s\n' "$m1" >&2; false; }
  # the NAME is not carried alongside the ordinal — that is the whole content of the reversal,
  # and without this the case passes on a chip that renders BOTH
  [[ "$m3" != *next* ]] || { printf 'marker: %s\n' "$m3" >&2; false; }
  # route 1 stays naming-independent by contract and renders its own number
  local mov
  mov=$(chip_of "$(render payload_full "$WORK/live-name" CLAUDE_INSTANCE_N=7)" live-name)
  [ -n "$mov" ]
  [[ "$mov" == *"(7)"* ]] || { printf 'marker: %s\n' "$mov" >&2; false; }
  [[ "$mov" != *next* ]] || { printf 'marker: %s\n' "$mov" >&2; false; }
}

# ── UNKNOWN IS ITS OWN STATE (VOLUNTARY_ACCOUNT_SWITCH §8a, 2026-09-22) ───────────────────────
# A blank marker meant two opposite things: "the STABLE launcher, which has no ordinal by design"
# and "I could not work out which account this is". Identical pixels, opposite meanings, and no
# assertion in this suite could tell them apart — `[ -z "$mstable" ]` above is satisfied by both.
# The measurement that makes this worth a case rather than a comment: 60.6% of substantial
# post-idle work lands on a non-perishable account, because the operator types into whichever
# pane is in front of him and cannot see whose quota he is spending. An ABSENT label reads as
# "nothing to see", so silence was the worst available rendering of "unknown".
#
# Both arms are pinned because the two UNKNOWN sources are independent: an unmapped config dir
# (an 11th instance added to ~/.zshrc and not to the ordinal map) and NO config dir at all (no
# transcript_path and no $CLAUDE_CONFIG_DIR — $render pins the latter empty for every case here).
payload_unmapped() {     # a config dir the ordinal map has never heard of
  jq -nc '{session_id:"7777-7777-7777",
           transcript_path:"/Users/x/.claude-undecennary/projects/-Users-x-p/7777.jsonl",
           model:{id:"claude-opus-4-8"}, effort:{level:"high"},
           context_window:{context_window_size:1000000, used_percentage:47},
           cwd:"/Users/x/p"}'
}
payload_nocfg() {        # no transcript_path at all ⇒ CFG is empty and nothing can be inferred
  jq -nc '{session_id:"8888-8888-8888",
           model:{id:"claude-opus-4-8"}, effort:{level:"high"},
           context_window:{context_window_size:1000000, used_percentage:47},
           cwd:"/Users/x/p"}'
}

@test "live: an UNRESOLVABLE account renders UNKNOWN — never blank, never a guessed ordinal" {
  mk_repo "$WORK/live-unk" some-branch
  local munmapped mnocfg mstable m3
  munmapped=$(chip_of "$(render payload_unmapped "$WORK/live-unk")" live-unk)
  mnocfg=$(chip_of   "$(render payload_nocfg    "$WORK/live-unk")" live-unk)
  mstable=$(chip_of  "$(render payload_stable   "$WORK/live-unk")" live-unk)
  m3=$(chip_of       "$(render payload_full     "$WORK/live-unk")" live-unk)   # .claude-tertiary → 3

  # 1. THE WHOLE POINT: unknown is not silence. This is the assertion the pre-change script fails.
  [ -n "$munmapped" ] || { printf 'unmapped chip was BLANK — indistinguishable from stable\n' >&2; false; }
  [ -n "$mnocfg" ]    || { printf 'no-config chip was BLANK — indistinguishable from stable\n' >&2; false; }
  # 2. …and stable is still silence, because that account IS known and blank is its answer.
  [ -z "$mstable" ] || { printf 'stable chip: %s\n' "$mstable" >&2; false; }
  # 3. Both unknown sources are ONE state, so they render ONE way.
  [ "$munmapped" = "$mnocfg" ]
  # 4. It is never mistaken for a known instance.
  [ "$munmapped" != "$m3" ]
  # 5. NEVER A GUESS: no digit (that would name an account) and no account name.
  [[ "$munmapped" != *[0-9]* ]] || { printf 'unknown chip carries a digit: %s\n' "$munmapped" >&2; false; }
  [[ "$munmapped" != *claude* ]] || { printf 'unknown chip carries a name: %s\n' "$munmapped" >&2; false; }
  [[ "$munmapped" != *next* ]]   || { printf 'unknown chip carries a name: %s\n' "$munmapped" >&2; false; }
  # 6. The per-terminal gate exists to draw a NUMBER in one cell; there is no number here, so
  #    iTerm2 must take the same rendering as everything else.
  local miterm
  miterm=$(chip_of "$(render payload_unmapped "$WORK/live-unk" TERM_PROGRAM=iTerm.app TERM=xterm-256color)" live-unk)
  [ "$miterm" = "$munmapped" ]
}

@test "live: RED ARM — deleting the UNKNOWN arm puts the two states back to identical" {
  # Positive control (A07 item 38): a case asserting a DIFFERENCE passes trivially if the
  # difference is drawn by something else on the line, so mutate the one arm that draws it and
  # require this suite's own claim to break. Without this, case 1 above is unfalsified.
  mk_repo "$WORK/live-unk-red" some-branch
  local mutant; mutant="$WORK/statusline-mutant.sh"
  sed 's/^            \*)                    NUNK=1 ;;$/            *) : ;;/' "$NEW" > "$mutant"
  # the mutation must actually have landed — a sed that matched nothing would pass vacuously
  ! diff -q "$NEW" "$mutant" >/dev/null || { printf 'mutation did not apply — the arm moved\n' >&2; false; }

  local saved_new; saved_new="$NEW"
  NEW="$mutant"
  local mu ms
  mu=$(chip_of "$(render payload_unmapped "$WORK/live-unk-red")" live-unk-red)
  ms=$(chip_of "$(render payload_stable   "$WORK/live-unk-red")" live-unk-red)
  NEW="$saved_new"
  [ "$mu" = "$ms" ] || { printf 'mutant still distinguished them: [%s] vs [%s]\n' "$mu" "$ms" >&2; false; }
  [ -z "$mu" ] || { printf 'mutant chip was not blank: %s\n' "$mu" >&2; false; }
}

# ── W4 · IDENTITY IN THE PIXELS (U07 2026-09-19) ──────────────────────────────────────────────
# Measured that day on 16 live sessions: panes 122 and 124 rendered the BYTE-IDENTICAL statusline,
# 6 of 16 shared the cwd basename and all 6 shared the git sha (one checkout), and the sha MOVES
# under a session that has done nothing. So a perfectly fresh, perfectly read screenshot did not
# identify a session, and the two fields that fix it by construction were already in the script's
# hands at zero fork cost: $KITTY_WINDOW_ID is inherited env and PAY_SID is parsed by the single
# jq extraction. These cases pin the FIELD and its INDEPENDENCE — the suite's own history records
# seven single-line mutants of statusline.sh leaving it 10/10 green, so each half here has a
# stated red arm rather than a shared one.
payload_nosid() {   # no session_id at all — the sid8 half must vanish, the pane half must not
  jq -nc '{transcript_path:"/Users/x/.claude-tertiary/projects/-Users-x-p/aaaa.jsonl",
           model:{id:"claude-opus-4-8"}, effort:{level:"max"},
           context_window:{context_window_size:1000000, used_percentage:47},
           cwd:"/Users/x/p"}'
}

@test "live: the identity segment renders the pane and the sid8 between the chip and the context %" {
  mk_repo "$WORK/live-id" some-branch
  local line head
  line=$(render payload_full "$WORK/live-id" KITTY_WINDOW_ID=117)
  head=$(marker_of "$line" live-id)
  # POSITION is the whole point: 9 of 16 live panes are <=38 columns and already amputate the sha
  # and the effort, so identity has to sit at the ellipsis-immune edge (U07 2b).
  [ "$head" = "(3) #117 aaaa-bbb 47% · " ] || { printf 'head: [%s]\n' "$head" >&2; false; }
  # ...and the body is untouched — the segment is additive, not a re-layout.
  [ "$(body_of "$line" live-id)" = "live-id ($(git -C "$WORK/live-id" rev-parse --short HEAD))  some-branch · max" ]
}

@test "live: RED ARM — the pane half vanishes with its env var, and the sid8 half with its payload field" {
  mk_repo "$WORK/live-idmut" some-branch
  local both nopane nosid
  both=$(marker_of "$(render payload_full   "$WORK/live-idmut" KITTY_WINDOW_ID=117)" live-idmut)
  # (a) no pane env at all (render already pins BOTH spellings unset) — the sid8 survives alone.
  nopane=$(marker_of "$(render payload_full "$WORK/live-idmut")" live-idmut)
  # (b) a payload with no session_id — the pane survives alone.
  nosid=$(marker_of "$(render payload_nosid "$WORK/live-idmut" KITTY_WINDOW_ID=117)" live-idmut)
  [[ "$both"   == *"#117"*   ]] || { printf 'both: [%s]\n'   "$both"   >&2; false; }
  [[ "$both"   == *"aaaa-bbb"* ]] || { printf 'both: [%s]\n' "$both"   >&2; false; }
  [[ "$nopane" != *"#"*      ]] || { printf 'nopane: [%s]\n' "$nopane" >&2; false; }
  [[ "$nopane" == *"aaaa-bbb"* ]] || { printf 'nopane: [%s]\n' "$nopane" >&2; false; }
  [[ "$nosid"  == *"#117"*   ]] || { printf 'nosid: [%s]\n'  "$nosid"  >&2; false; }
  [[ "$nosid"  != *"aaaa-bbb"* ]] || { printf 'nosid: [%s]\n' "$nosid" >&2; false; }
  # neither half is a placeholder: an absent source renders NOTHING, so the absence is readable
  [ "$nopane" = "(3) aaaa-bbb 47% · " ] || { printf 'nopane: [%s]\n' "$nopane" >&2; false; }
}

@test "live: the pane falls back to ITERM_SESSION_ID's tail, and KITTY_WINDOW_ID wins the tie" {
  mk_repo "$WORK/live-idterm" some-branch
  # ~/.zshrc exports ITERM_SESSION_ID=w0t0p0:$KITTY_WINDOW_ID INSIDE kitty, and
  # hooks/session-register.sh:127 keys the registry FILENAME on exactly this `##*:` strip — so the
  # two spellings must resolve to the same integer or the statusline and the registry disagree
  # about what a pane is called. Reading it for its VALUE is fine; reading it as a TERMINAL claim
  # is the banned move the glyph block records shipping and reverting.
  local iterm both
  iterm=$(marker_of "$(render payload_full "$WORK/live-idterm" ITERM_SESSION_ID=w0t0p0:901)" live-idterm)
  [[ "$iterm" == *"#901"* ]] || { printf 'iterm: [%s]\n' "$iterm" >&2; false; }
  both=$(marker_of "$(render payload_full "$WORK/live-idterm" ITERM_SESSION_ID=w0t0p0:901 KITTY_WINDOW_ID=117)" live-idterm)
  [[ "$both" == *"#117"* ]] || { printf 'both: [%s]\n' "$both" >&2; false; }
  [[ "$both" != *901*    ]] || { printf 'both: [%s]\n' "$both" >&2; false; }
}

@test "live: a non-UTF-8 locale falls back to a plain # — the mark is never a mojibake box" {
  mk_repo "$WORK/live-idloc" some-branch
  local utf8 c
  utf8=$(marker_of "$(render payload_full "$WORK/live-idloc" KITTY_WINDOW_ID=117 LC_ALL=en_US.UTF-8)" live-idloc)
  c=$(marker_of "$(render payload_full "$WORK/live-idloc" KITTY_WINDOW_ID=117 LC_ALL=C)" live-idloc)
  [[ "$utf8" == *"#117"* ]] || { printf 'utf8: [%s]\n' "$utf8" >&2; false; }
  [[ "$c"    == *"#117"* ]] || { printf 'C: [%s]\n'    "$c"    >&2; false; }
  [[ "$c"    == *"#117"* ]] || { printf 'C: [%s]\n'    "$c"    >&2; false; }   # `#` renders in EVERY locale: Monaco has no U+2317, so the mark no longer depends on the locale
}

@test "live: the telemetry row carries the pane, so a reader can join a sid to a pane without ps" {
  mk_repo "$WORK/live-idtel" some-branch
  render payload_full "$WORK/live-idtel" KITTY_WINDOW_ID=117 >/dev/null
  [ -f "$CC_TELEMETRY_DIR/aaaa-bbbb-cccc.json" ] || { ls -la "$CC_TELEMETRY_DIR"; false; }
  [ "$(jq -r '.pane' "$CC_TELEMETRY_DIR/aaaa-bbbb-cccc.json")" = "117" ]
  # RED ARM: with no pane env the field is NULL, never the string "" — a reader joining on it must
  # be able to tell "no pane" from "a pane called nothing".
  rm -f "$CC_TELEMETRY_DIR/aaaa-bbbb-cccc.json"
  render payload_full "$WORK/live-idtel" >/dev/null
  [ "$(jq -r '.pane' "$CC_TELEMETRY_DIR/aaaa-bbbb-cccc.json")" = "null" ]
}


# ── W5 · LIMIT_DETECT_100P §3/§4 + §11 #13 (2026-09-20) ───────────────────────────────────────
# The chip itself landed from the SIBLING plan (LIMIT_RECOVER_100P W4, 33a9563fb + aaedbf3dd) and
# LIMIT_DETECT_100P §13 records it as done — so these rows do not re-prove that the field exists.
# They close the cases the landed five do NOT reach, which are exactly the ones W5's DoD names:
# the chip under CLIPPING (its whole reason for being left-anchored), BOTH sources absent at once,
# and the fork-count gate §11 #13 makes the real gate for this wave.
#
# RED-PROOF DISCIPLINE: the cure is already on trunk, so none of these can go red against pristine
# HEAD — a row that passes in both arms is an equivalence guard, not a proof (docs/lessons/
# green-in-both-arms-...). Each row below therefore states the MUTANT of statusline.sh that kills
# it, and every one of those mutants was executed; the footer carries the pasted red output.

@test "live: at 30 columns the chip is INTACT while the sha and the effort are amputated" {
  # This is the position argument, made falsifiable. U07 measured 9 of 16 live panes at <=38
  # columns, so a right-anchored identity would be clipped in exactly the panes where a screenshot
  # is the only way to ask which session this is. The terminal does the clipping, so the assertion
  # is over the first 30 ANSI-STRIPPED columns of the rendered line.
  mk_repo "$WORK/live-idclip" some-branch
  local line clip
  line=$(render payload_full "$WORK/live-idclip" KITTY_WINDOW_ID=117)
  clip="${line:0:30}"
  # (a) the whole chip — mark, pane and sid8 — survives the cut, with room to spare.
  [[ "$clip" == *"#117 aaaa-bbb"* ]] || { printf 'clip: [%s]\n' "$clip" >&2; false; }
  # (b) CONTROL, and it is what makes (a) mean anything: the fields the chip was placed AHEAD of
  # are genuinely gone at this width. Without this the row would pass on a 200-column line.
  [[ "$clip" != *"$(git -C "$WORK/live-idclip" rev-parse --short HEAD)"* ]] \
    || { printf 'clip: [%s]\n' "$clip" >&2; false; }
  [[ "$clip" != *"max"* ]] || { printf 'clip: [%s]\n' "$clip" >&2; false; }
  # (c) and the line really is longer than the cut, so (b) is clipping rather than an empty render.
  [ "${#line}" -gt 30 ]
  # MUTANT: move ID_SEG to the right of ${OUTPUT} in the final echo -> (a) fails.
}

@test "live: with NEITHER source the segment is absent ENTIRELY — no mark, no orphan separator" {
  # W5's DoD row says this case renders `#? <sid8>`. It does not, and that is the SIBLING's
  # deliberate cure, argued in statusline.sh's own block comment: a placeholder identifies nothing
  # and makes its own absence unfalsifiable. The DoD was written before that landed
  # (docs/lessons/dod-can-demand-what-the-cure-removed). This row pins the LANDED semantics, and
  # pins them as an exact head so a future `?` placeholder cannot creep back in unnoticed.
  mk_repo "$WORK/live-idnone" some-branch
  local head
  # payload_nosid carries no session_id, and render() unsets BOTH pane spellings.
  head=$(marker_of "$(render payload_nosid "$WORK/live-idnone")" live-idnone)
  [ "$head" = "(3) 47% · " ] || { printf 'head: [%s]\n' "$head" >&2; false; }
  # stated three ways, because the failure modes differ: no mark, no `?`, and no doubled space
  # where the two omitted tokens used to be.
  [[ "$head" != *"#"* ]] || { printf 'head: [%s]\n' "$head" >&2; false; }
  [[ "$head" != *"?"* ]] || { printf 'head: [%s]\n' "$head" >&2; false; }
  [[ "$head" != *"  "* ]] || { printf 'head: [%s]\n' "$head" >&2; false; }
  # MUTANT: ID_SEG="${_idmark}${ID_PANE:-?} ${PAY_SID:0:8} " (the DoD's own spelling) -> all four fail.
}

@test "live: a SET-BUT-EMPTY KITTY_WINDOW_ID falls through to ITERM_SESSION_ID" {
  # The input is real: a pane that left kitty, and every `env KITTY_WINDOW_ID=` wrapper, presents
  # the variable SET and EMPTY. Rendering a session with NO pane while a pane id was available is
  # the one failure the chip exists to prevent.
  #
  # ⚠️ MEASURED, and it corrects the obvious reading of this row — the protection is NOT the `:-`
  # in `${KITTY_WINDOW_ID:-}`. Mutating that to `${KITTY_WINDOW_ID-}` leaves this row GREEN, because
  # both spellings yield the empty string and the iTerm2 fallback is guarded on the resulting VALUE
  # (`[ -z "$ID_PANE" ]`), not on whether the variable was set. That survivor is recorded in the
  # footer. What this row therefore pins is the GUARD's shape, and the mutant below is the
  # realistic defect it excludes: a fallback "tightened" to fire only when kitty's var is UNSET.
  mk_repo "$WORK/live-idempty" some-branch
  local head
  head=$(marker_of "$(render payload_full "$WORK/live-idempty" KITTY_WINDOW_ID= ITERM_SESSION_ID=w0t0p0:901)" live-idempty)
  [ "$head" = "(3) #901 aaaa-bbb 47% · " ] || { printf 'head: [%s]\n' "$head" >&2; false; }
  # MUTANT: `if [ -z "${KITTY_WINDOW_ID+x}" ]` in place of `if [ -z "$ID_PANE" ]`
  #         -> head becomes "(3) aaaa-bbb 47% · ", the pane silently lost.
}

@test "live: an ITERM_SESSION_ID with NO colon yields the whole value, as the registry reads it" {
  # `${ID_PANE##*:}` on a colonless string is the string itself. That is not an accident of the
  # idiom, it is the contract: hooks/session-register.sh keys the registry FILENAME on the SAME
  # strip, so the statusline and the registry must agree on what a pane is called for either
  # spelling. A `${ID_PANE#*:}` (single-#) mutant returns the whole string here too but breaks the
  # w0t0p0: form, which the neighbouring case already pins — together they fix the operator.
  mk_repo "$WORK/live-idbare" some-branch
  local head
  head=$(marker_of "$(render payload_full "$WORK/live-idbare" ITERM_SESSION_ID=773)" live-idbare)
  [ "$head" = "(3) #773 aaaa-bbb 47% · " ] || { printf 'head: [%s]\n' "$head" >&2; false; }
  # MUTANT: ID_PANE="${ID_PANE%%:*}" -> "#773" survives here but the w0t0p0:901 case above reddens.
}

@test "live: with NO instance marker the line STARTS with the chip — left-anchored at column 0" {
  # `left-anchored` is asserted everywhere else RELATIVE to the instance chip, which means every
  # one of those rows still passes if the segment silently moves to the end of a line that happens
  # to have no chip. The stable config dir is the real render with an empty GLYPH_PREFIX, so this
  # is the only case where the claim `column 0` is even expressible.
  mk_repo "$WORK/live-idcol0" some-branch
  local line
  line=$(render payload_stable "$WORK/live-idcol0" KITTY_WINDOW_ID=117)
  [ "${line:0:14}" = "#117 5555-555 " ] || { printf 'line: [%s]\n' "$line" >&2; false; }
  # CONTROL: the stable payload really does suppress the ordinal, or the assertion above is
  # measuring a chip that was there all along.
  [[ "$line" != *"("[0-9]")"* ]] || { printf 'line: [%s]\n' "$line" >&2; false; }
  # MUTANT: emit ${PCT_SEG}${ID_SEG} instead of ${ID_SEG}${PCT_SEG} -> line starts "47% · #117".
}

@test "§11 #13 GATE: the chip block creates ZERO subprocesses (fork count == baseline)" {
  # THE gate for this wave, per LIMIT_DETECT_100P §11 #13 — the render rows above are a
  # must-stay-green note, this is the thing that may not regress. P6's whole cost argument is that
  # both halves are already in the script's hands: $KITTY_WINDOW_ID is inherited env and PAY_SID
  # comes from the single jq extraction, so the block is pure parameter expansion at 0 forks.
  #
  # ⚠️ The amendment spells the test "contains no $(, no backtick and no |". Taken LITERALLY that
  # is false against the landed block, which contains `||` (a list operator) and the locale
  # `case`'s `*UTF-8*|*utf-8*` alternation — neither of which forks anything. Matching the
  # SPELLING would redden on correct code and invite someone to "fix" a fork-free block
  # (docs/lessons/... denylist-enumerates-spellings-not-the-class). So the class is matched
  # instead, delete-then-match: remove the two non-forking uses of `|`, then any survivor is a
  # pipeline.
  local blk mut
  blk="$BATS_TEST_TMPDIR/chipblock.sh"
  # comment LINES go (they quote backticks in prose); a trailing comment is ` #<space>`, which
  # cannot match the `_idmark='#'` literal.
  awk '/^ID_PANE=/,/^fi$/' "$NEW" | sed -e '/^[[:space:]]*#/d' -e 's/ #[[:space:]].*$//' > "$blk"
  # the extraction is real, not an empty file passing for free
  [ "$(wc -l < "$blk")" -ge 8 ]
  grep -q 'ID_SEG=' "$blk"

  forks() { # <file> -> count of subprocess-creating constructs
    sed -e 's/||//g' -e '/;;[[:space:]]*$/s/^[^)]*)//' "$1" \
      | grep -cE '\$\(|`|\|' || true
  }
  [ "$(forks "$blk")" -eq 0 ] || { printf 'block:\n%s\n' "$(cat "$blk")" >&2; false; }

  # POSITIVE CONTROL — a predicate that can only ever say zero is not a gate. The same function
  # over the whole script must CONVICT (statusline.sh is full of $( ) and pipelines), and each of
  # the three constructs must be caught individually when injected into a copy of the real block.
  [ "$(forks "$NEW")" -gt 0 ]
  for mut in 'ID_SEG="$(echo x)"' 'ID_SEG="`echo x`"' 'ID_SEG="$ID_SEG"; echo x | cat'; do
    cp "$blk" "$blk.mut"; printf '%s\n' "$mut" >> "$blk.mut"
    [ "$(forks "$blk.mut")" -gt 0 ] || { printf 'mutant NOT caught: %s\n' "$mut" >&2; false; }
  done
}
@test "live: outside a git repo only the non-git fields render" {
  mkdir -p "$WORK/live-norepo"
  local line
  line=$(render payload_full "$WORK/live-norepo")
  local body; body=$(body_of "$line" live-norepo)
  [ "$body" = "live-norepo · max" ]
  [ "$(pct_of "$line" live-norepo)" = "47%" ]   # the % left the body but must still render
  # on the BODY, not the line — the instance marker carries its own parens, so testing the whole
  # line here would assert the marker's current design and re-introduce exactly the drift
  # this layer exists to stop.
  ! printf '%s' "$body" | grep -q '(' || false      # no commit parens, no branch, no dirty marker
  ! printf '%s' "$body" | grep -q '\*' || false
}

# ── the DURABLE denominator (row 5e4ce121b64a residual (b)) ───────────────────────────────────
# Fill % = input_tokens / window. The window reached a durable store on only two EVENT-conditioned
# paths — a fill-drop (IDL) and a recycle (recycle-events) — so a session that did neither had no
# denominator at all and was excluded from every retrospective read. The statusline renders on
# essentially every turn, so writing it HERE makes coverage a function of "the session existed".
#
# These tests are OUTPUT-BLIND on purpose: they assert the side-effect file, never the rendered
# line, so the frozen byte-identity proof above (tests 2-9) keeps its meaning.
payload_win() {  # transcript_path OUTSIDE the bats tmpdir — proves the containment redirect
  jq -nc '{session_id:"win-sid-1",
           transcript_path:"/Users/x/.claude-tertiary/projects/-Users-x-p/win.jsonl",
           model:{id:"claude-opus-5"}, effort:{level:"high"},
           context_window:{context_window_size:200000, used_percentage:12},
           cwd:"/Users/x/p"}'
}
payload_nowin() {  # the harness emitted NO window — it must be written as NOTHING, never imputed
  jq -nc '{session_id:"nowin-sid-1",
           transcript_path:"/Users/x/.claude-tertiary/projects/-Users-x-p/nowin.jsonl",
           model:{id:"claude-opus-5"}, effort:{level:"high"},
           context_window:{used_percentage:12},
           cwd:"/Users/x/p"}'
}

@test "durable window: one row carrying sid, window and model is written for the session" {
  mk_repo "$WORK/win-a" some-branch
  render payload_win "$WORK/win-a" >/dev/null
  local store="$BATS_TEST_TMPDIR/session-window.jsonl"
  [ -f "$store" ] || false
  run jq -r 'select(.sid=="win-sid-1") | "\(.window) \(.model)"' "$store"
  [ "$status" -eq 0 ] || false
  [ "$output" = "200000 claude-opus-5" ] || false
}

@test "durable window: re-rendering the SAME session does not grow the store (it is an upsert)" {
  mk_repo "$WORK/win-b" some-branch
  render payload_win "$WORK/win-b" >/dev/null
  render payload_win "$WORK/win-b" >/dev/null
  render payload_win "$WORK/win-b" >/dev/null
  local store="$BATS_TEST_TMPDIR/session-window.jsonl"
  [ "$(grep -c 'win-sid-1' "$store")" -eq 1 ] || false
}

@test "durable window: a payload with NO window writes NO row — the denominator is never imputed" {
  mk_repo "$WORK/win-c" some-branch
  render payload_nowin "$WORK/win-c" >/dev/null
  local store="$BATS_TEST_TMPDIR/session-window.jsonl"
  # positive control: the writer IS reachable from this fixture, so an empty store here means
  # "declined to write", not "never ran at all"
  render payload_win "$WORK/win-c" >/dev/null
  [ -f "$store" ] || false
  [ "$(grep -c 'win-sid-1' "$store")" -eq 1 ] || false
  [ "$(grep -c 'nowin-sid-1' "$store" || true)" -eq 0 ] || false
}

@test "durable window: under bats a store outside the tmpdir is REDIRECTED into it" {
  mk_repo "$WORK/win-d" some-branch
  render payload_win "$WORK/win-d" >/dev/null
  # the payload's config root is /Users/x/.claude-tertiary — a path this box does not own. The
  # row must land in the fixture, and nothing may be created at the resolved path.
  [ -f "$BATS_TEST_TMPDIR/session-window.jsonl" ] || false
  [ ! -e "/Users/x/.claude-tertiary/autonomy/session-window.jsonl" ] || false
}

# ══════════════════════════════════════════════════════════════════════════════════════════════
# RED-PROOF — the six W5 rows above (2026-09-20, LIMIT_DETECT_100P W5)
#
# ⚠️ WHY THESE ARE MUTANTS AND NOT A PRE-FIX RED. W5's brief asks each new row to be run RED
# against pristine HEAD. That is unsatisfiable here and saying so is the point: the cure LANDED
# FIRST, from the sibling plan (LIMIT_RECOVER_100P W4 — 33a9563fb, 'identity in the pixels'), so
# pristine HEAD already renders the chip and every row below is green in both arms. A row green in
# both arms is an equivalence guard, and the only evidence it has power is the death of a mutant
# (docs/lessons/green-in-both-arms-is-an-equivalence-guard-not-a-red-proof.md). Each row therefore
# names the mutant of statusline.sh that kills it; all six were EXECUTED, and the output is pasted
# verbatim below. Reproduce: apply the diff shown, run the filter shown, restore.
#
# ── M1 · identity moved to the RIGHT of ${OUTPUT} ─────────────────────────────────────────────
#   -echo -e "${GLYPH_PREFIX}${ID_SEG}${PCT_SEG}${OUTPUT}${RESET}"
#   +echo -e "${GLYPH_PREFIX}${PCT_SEG}${OUTPUT}${ID_SEG}${RESET}"
#   $ bats --filter "30 columns" tests/statusline-identity.bats
#   1..1
#   not ok 1 live: at 30 columns the chip is INTACT while the sha and the effort are amputated
#   #   `[[ "$clip" == *"#117 aaaa-bbb"* ]] || { printf 'clip: [%s]\n' "$clip" >&2; false; }' failed
#   # clip: [(3) 47% · live-idclip (dd63e18]
#
# ── M2 · the DoD's `#?` placeholder creeps back in ────────────────────────────────────────────
#   -ID_SEG=""
#   +ID_SEG="#? "
#   $ bats --filter "NEITHER source" tests/statusline-identity.bats
#   1..1
#   not ok 1 live: with NEITHER source the segment is absent ENTIRELY — no mark, no orphan separator
#   #   `[ "$head" = "(3) 47% · " ] || { printf 'head: [%s]\n' "$head" >&2; false; }' failed
#   # head: [(3) #? 47% · ]
#
# ── M3 · the iTerm2 fallback tightened to fire only when kitty's var is UNSET ─────────────────
#   -if [ -z "$ID_PANE" ]; then ID_PANE="${ITERM_SESSION_ID:-}"; ID_PANE="${ID_PANE##*:}"; fi
#   +if [ -z "${KITTY_WINDOW_ID+x}" ]; then ID_PANE="${ITERM_SESSION_ID:-}"; ID_PANE="${ID_PANE##*:}"; fi
#   $ bats --filter "SET-BUT-EMPTY" tests/statusline-identity.bats
#   1..1
#   not ok 1 live: a SET-BUT-EMPTY KITTY_WINDOW_ID falls through to ITERM_SESSION_ID
#   #   `[ "$head" = "(3) #901 aaaa-bbb 47% · " ] || { printf 'head: [%s]\n' "$head" >&2; false; }' failed
#   # head: [(3) aaaa-bbb 47% · ]
#
#   🚨 SURVIVOR, recorded rather than hidden — the mutant this row was FIRST written against did
#   NOT kill it, and the row's stated rationale was wrong until this run corrected it:
#       -ID_PANE="${KITTY_WINDOW_ID:-}"
#       +ID_PANE="${KITTY_WINDOW_ID-}"
#       1..1
#       ok 1 live: a SET-BUT-EMPTY KITTY_WINDOW_ID falls through to ITERM_SESSION_ID
#   Both spellings yield the empty string, and the fallback is guarded on the resulting VALUE, so
#   the `:-` is not what protects this case. Anyone hardening that line should know the suite is
#   BLIND to `:-` vs `-` here, and that the guard's shape is what carries the behaviour.
#
# ── M4 · a colonless ITERM_SESSION_ID treated as "no pane" ────────────────────────────────────
#   -if [ -z "$ID_PANE" ]; then ID_PANE="${ITERM_SESSION_ID:-}"; ID_PANE="${ID_PANE##*:}"; fi
#   +if [ -z "$ID_PANE" ]; then ID_PANE="${ITERM_SESSION_ID:-}"; if [ "${ID_PANE#*:}" = "$ID_PANE" ]; then ID_PANE=""; else ID_PANE="${ID_PANE##*:}"; fi; fi
#   $ bats --filter "NO colon" tests/statusline-identity.bats
#   1..1
#   not ok 1 live: an ITERM_SESSION_ID with NO colon yields the whole value, as the registry reads it
#   #   `[ "$head" = "(3) #773 aaaa-bbb 47% · " ] || { printf 'head: [%s]\n' "$head" >&2; false; }' failed
#   # head: [(3) aaaa-bbb 47% · ]
#
# ── M5 · the two head segments swapped ────────────────────────────────────────────────────────
#   -echo -e "${GLYPH_PREFIX}${ID_SEG}${PCT_SEG}${OUTPUT}${RESET}"
#   +echo -e "${GLYPH_PREFIX}${PCT_SEG}${ID_SEG}${OUTPUT}${RESET}"
#   $ bats --filter "column 0" tests/statusline-identity.bats
#   1..1
#   not ok 1 live: with NO instance marker the line STARTS with the chip — left-anchored at column 0
#   #   `[ "${line:0:14}" = "#117 5555-555 " ] || { printf 'line: [%s]\n' "$line" >&2; false; }' failed
#   # line: [47% · #117 5555-555 live-idcol0 (174d866)  some-branch · high]
#
# ── M6 · a $( ) inside the chip block (the §11 #13 gate) ──────────────────────────────────────
#   +    ID_SEG="$(printf %s "$ID_SEG")"
#   $ bats --filter "ZERO subprocesses" tests/statusline-identity.bats
#   1..1
#   not ok 1 §11 #13 GATE: the chip block creates ZERO subprocesses (fork count == baseline)
#   #   `[ "$(forks "$blk")" -eq 0 ] || { printf 'block:\n%s\n' "$(cat "$blk")" >&2; false; }' failed
#   # block:  ... ID_SEG="$(printf %s "$ID_SEG")" ...
#
# ── P6 timing, re-measured for the W5 DoD (same box, 30 renders x 3 reps per arm) ──────────────
# Baseline = 09c0a7b1a:statusline.sh, the last revision before the chip landed. CPU = user+sys
# from /usr/bin/time -p, so a saturated box inflates the variance but not the measure.
#   baseline  user+sys 1.76 / 1.64 / 1.65 s  ->  mean 1.683 s  =  56.1 ms per render
#   chip      user+sys 1.67 / 1.74 / 1.78 s  ->  mean 1.730 s  =  57.7 ms per render
#   delta +1.6 ms/render — inside the DoD's ±3 ms band, and ALSO inside the 4 ms within-arm spread,
#   i.e. the instrument cannot resolve the effect it is being asked about. That is precisely §11
#   #13's finding ("the ±3 ms band is 15x the effect"), and why the GATE is the fork count above
#   and this row is a recorded measurement rather than an assertion. Load at measurement: 14.7/core.
# ══════════════════════════════════════════════════════════════════════════════════════════════
