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
# exclusion list that rots. What stays LIVE against the working tree is what can still actually
# regress: the process-count assertions (last test) and untracked-is-not-dirty (test 5). Do NOT
# "fix" a future red here by regenerating the baseline from HEAD — that compares the script to
# itself and passes vacuously forever.

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
  # from the prior telemetry FILE + 1 telemetry EMIT (it writes JSON, so it needs jq).
  [ "$(grep -cE 'jq -[rc] ' "$NEW")" -eq 3 ]
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
