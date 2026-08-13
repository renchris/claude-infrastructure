#!/bin/bash
# gate-memo.sh — blob-sha-keyed verdict memo for the land gate's PURE checks (land-arch P3,
# backlog 963bbebe7c9a).
#
# WHAT THIS IS FOR. 22-23% of lands re-round: a sibling lands mid-gate, our optimistic round is
# invalidated (exit 42), and the whole unlocked gate runs AGAIN over a tree that is byte-identical
# except for the sibling's delta. Every second of that re-proves a verdict about file content that
# did not change. THIS FILE REMOVES THAT WASTE FOR THE FILE-LOCAL STATICS, and — measured, not
# assumed — those are a small share of it. Re-derive before quoting; these decay (repo memory:
# published-figure-decays-with-its-source). This worktree, 2026-08-10:
#
#   statics re-round (shellcheck + `bash -n`, 3-file diff)   2.15-2.27s  ->  0.14s   (3 samples each)
#   whole gate, cold                                                          149s
#   whole gate, re-round                                                127-137s
#
# So the memo takes the statics phase to ~zero and moves the WHOLE gate by ~2s in ~130s. The
# remainder is the fifteen ratchet arms: ~88s of main runs (test-hermeticity 30.7s, git-identity
# 11.5s, unattended-path 11.1s, pane-spawn 7.3s, walltime 5.7s, pipefail 5.3s, kill-guard 4.8s,
# utc-stamp 4.7s, afunix 4.3s, self-path 1.6s, …) plus ~24s of `--selftest` preambles
# (unattended-path 12.9s, utc-stamp 5.3s, self-path 2.0s, …). See the section at the foot of this
# file for why those are NOT memoized here.
#
# THE ONE INVARIANT. A memo may only ever return a green it has already EARNED, for exactly the
# inputs it earned it on. Every other outcome — a miss, an unreadable entry, a corrupt entry, a key
# it cannot compute, a tree it cannot trust — RUNS THE CHECK. There is no path through this file
# that turns "I don't know" into "green" (repo memory: gate-default-decides-failure-direction).
# Concretely, that shows up three ways:
#   1. Only rc 0 is ever recorded. A red is never cached, so a red always re-runs and always
#      re-prints its own findings — the operator never gets a finding replayed from a cache, and a
#      corrupt cache can never manufacture one.
#   2. Every entry RESTATES its own key in its body, and a hit requires an exact literal match of
#      the whole line. A truncated write, a hand-edit, a hash collision, or a `chmod 000` all read
#      as a miss, not as a green.
#   3. memo_init refuses outright — memo OFF for the whole process — on anything it cannot stand
#      behind: a dirty worktree, an unresolvable git dir, a hasher that will not hash. OFF means
#      every lookup misses, i.e. exactly today's behaviour.
#
# WHAT IS *NOT* KEYED HERE, DELIBERATELY. This memoizes verdicts. It does not choose suites. The
# set of arms and suites the gate runs is identical with and without it — the memo only changes
# whether an arm's ALREADY-DECIDED answer has to be recomputed. Changed-file-scoped suite selection
# is proposal S3 and it is REJECTED (docs/research/land-architecture-100p-2026-08-10.md §5);
# tests/land-gate-memo.bats pins that tripwire.
#
# WHY NOTHING HERE IS HEAVY, AND WHY THAT MATTERS. P1 (145fab7d) just emptied the mutex — measured
# hold 72s -> 3s — and the in-lock fallback lane re-enters run_gate. So the memo's own cost has to
# be negligible even there. Per arm it is: one `git ls-tree` over the arm's population and one
# `git hash-object --stdin` (two forks, no per-file disk walk), then a single small read or write.
# The salt is computed ONCE per process. Nothing here loops over the tree file-by-file.
#
# Kill switch: SHIP_LAND_MEMO=off (also the A/B lever — see tests/land-gate-memo.bats).
# Store: <git-common-dir>/ship-land-memo/ — inside the git dir, so never tracked, never /tmp, and
# shared by every worktree of this repo (post_state_path's reasoning, ship-land.sh:708).

# ---- state (set by memo_init) ----------------------------------------------
MEMO_OK=0        # 1 = usable. 0 = every lookup misses and every record is a no-op.
MEMO_DIR=""
MEMO_SALT=""
MEMO_HITS=0      # counters for the attestation line + the A/B measurement
MEMO_RUNS=0

memo_init() {  # 0 = memo usable · 1 = memo OFF (and every later call degrades to run-the-check)
  MEMO_OK=0; MEMO_DIR=""; MEMO_SALT=""; MEMO_HITS=0; MEMO_RUNS=0

  [[ "${SHIP_LAND_MEMO:-on}" = "off" ]] && return 1

  # A DIRTY TREE DISABLES THE MEMO, and this is load-bearing rather than tidy. The population
  # fingerprint below is computed with `git ls-tree HEAD` — the COMMITTED tree — because hashing
  # ~600 files individually would cost more than the checks it saves. That is only equal to what
  # the linters actually read if the worktree matches HEAD. main_outer already refuses a dirty tree
  # (ship-land.sh, "dirty-tree refusal"), so in the real lander this is always true; asserting it
  # here anyway means a test harness, a future caller, or a mid-gate edit can never silently turn
  # `ls-tree` into a stale-verdict generator. One `git status` call, once per process.
  [[ -n "$(git status --porcelain 2>/dev/null)" ]] && return 1

  local gd
  gd="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  [[ -n "$gd" ]] || return 1
  MEMO_DIR="$gd/ship-land-memo"
  mkdir -p "$MEMO_DIR" 2>/dev/null || return 1
  [[ -w "$MEMO_DIR" ]] || return 1

  # THE SALT IS THE CHECKERS' OWN IDENTITY. A ShellCheck upgrade changes what "green" means, so an
  # entry earned under 0.10.0 must not be honoured under 0.11.0 — without this the memo becomes a
  # stale-verdict generator, which is the one failure mode worse than the cost it saves. Every
  # interpreter that decides a memoized verdict is in here: ShellCheck, bash (`bash -n`), python3
  # (py_compile), and git (the hasher itself). A version command that FAILS contributes its own
  # empty literal, so a missing checker keys differently from a present one rather than colliding.
  #
  # (Every line of this comment is deliberately worded so that none of them BEGINS with the
  # linter's own name: a comment whose first word is that name is parsed as a directive, and a
  # malformed one aborts the whole file — the lint then reads NOTHING and reports clean. Repo
  # memory: lint-blindness-composes-and-hides-the-next-defect.)
  MEMO_SALT="$(
    printf 'gate-memo/v1\n'
    printf 'shellcheck=%s\n' "$(shellcheck --version 2>/dev/null | awk '/^version:/{print $2}' || true)"
    printf 'bash=%s\n'       "$(bash --version 2>/dev/null | head -1 || true)"
    printf 'python3=%s\n'    "$(python3 --version 2>&1 || true)"
    printf 'git=%s\n'        "$(git --version 2>/dev/null || true)"
  )" || return 1

  MEMO_OK=1
  return 0
}

_memo_hash() {  # stdin → a stable digest. git is already a hard dependency of the whole lander.
  git hash-object --stdin 2>/dev/null
}

_memo_path() {  # $1=key-digest → the entry path ("" ⇒ unusable, caller must treat as a miss)
  [[ "$MEMO_OK" = "1" && -n "$1" ]] || return 1
  printf '%s/%s\n' "$MEMO_DIR" "$1"
}

_memo_get() {  # $1=key-digest → 0 IFF a valid, readable, exactly-matching green entry exists.
  local f body
  f="$(_memo_path "$1")" || return 1
  [[ -r "$f" ]] || return 1                       # absent OR unreadable ⇒ miss ⇒ run the check
  body="$(cat "$f" 2>/dev/null)" || return 1
  # EXACT match on the whole body, key restated inside. A truncated or hand-edited entry, a stray
  # newline, an empty file, or a digest collision all fail this and re-run. Never a prefix match.
  [[ "$body" = "gate-memo v1 green $1" ]]
}

_memo_put() {  # $1=key-digest — best-effort; a failed write costs a re-run next time, nothing more.
  local f
  f="$(_memo_path "$1")" || return 0
  # Written via a temp + rename so a killed land can never leave a HALF-WRITTEN body that some
  # later read might match. (It could not match anyway — see _memo_get — but a torn file that is
  # never even a candidate is cheaper to reason about than one that is.)
  local tmp="$f.$$.tmp"
  printf 'gate-memo v1 green %s' "$1" > "$tmp" 2>/dev/null && mv -f "$tmp" "$f" 2>/dev/null
  rm -f "$tmp" 2>/dev/null
  return 0
}

# ---- per-FILE memo: the file-local pure statics ------------------------------
# The three statics are pure functions of ONE file's bytes: the linter is invoked without `-x`, so
# it follows no `source`, and `bash -n` / py_compile never leave the file they are handed. That is
# what makes a blob-sha key EXACT rather than approximate. (Comment lines here avoid opening with
# the linter's own name — see the note in memo_init.)

memo_file_key() {  # $1=checker-id $2=path → digest on stdout, or nothing (⇒ caller treats as miss)
  local blob
  [[ "$MEMO_OK" = "1" ]] || return 1
  # hash-object reads the FILE ON DISK, not the index — so this arm is exact even if the
  # cleanliness assertion above ever stops holding.
  blob="$(git hash-object -- "$2" 2>/dev/null)" || return 1
  [[ -n "$blob" ]] || return 1
  printf '%s\nchecker=%s\nblob=%s\n' "$MEMO_SALT" "$1" "$blob" | _memo_hash
}

memo_file_hit() {  # $1=checker-id $2=path → 0 IFF this exact content already passed this exact checker
  local k; k="$(memo_file_key "$1" "$2")" || return 1
  [[ -n "$k" ]] || return 1
  _memo_get "$k"
}

memo_file_record() {  # $1=checker-id $2=path — only ever called on a PROVEN-green run
  local k; k="$(memo_file_key "$1" "$2")" || return 0
  [[ -n "$k" ]] && _memo_put "$k"
  return 0
}

memo_partition() {  # $1=checker-id, then paths… → prints only the paths that are NOT known-green.
  # NOTE ON THE COUNTERS: this runs in a $( ) subshell at the call site, so MEMO_HITS/MEMO_RUNS
  # incremented here would be discarded. They are therefore counted by the CALLER, from the sizes
  # of the two lists — which is also the only count that cannot drift from what actually ran.
  local checker="$1" p; shift
  for p in "$@"; do
    memo_file_hit "$checker" "$p" || printf '%s\n' "$p"
  done
}

memo_count() {  # $1=carried $2=run — the caller's own tally, folded into memo_summary
  MEMO_HITS=$(( MEMO_HITS + $1 ))
  MEMO_RUNS=$(( MEMO_RUNS + $2 ))
}

# ---- why the repo-wide RATCHET arms are NOT memoized here --------------------
# P3's spec asks for a second mechanism beside this one: "cache each arm's verdict against lint-sha
# + scanned-set state, or make the arm diff-incremental where that is SOUND. Where an arm cannot be
# keyed soundly, leave it alone and say so." This is the saying-so, with the measurements that
# decided it (this worktree, 2026-08-10 — re-derive rather than quote, they decay).
#
# 1. THE ARMS, NOT THE STATICS, ARE THE RE-ROUND COST — so the item's framing ("re-proving the
#    statics is the waste") is off by the ratio, and P3's "<=10s re-round" target is not reachable
#    by memoizing statics at all. Measured re-round: 127-137s whole-gate, of which the statics are
#    ~2.2s and the fifteen arms ~112s (~88s main + ~24s selftest — the breakdown is at the top of
#    this file). The memo above retires the 2.2s completely and leaves the 112s untouched.
#
# 2. AN ARM'S VERDICT IS NOT FILE-LOCAL, so the blob-sha key above does not transfer to it.
#    test-hermeticity rule 4 asks whether two tools name the SAME scratch path — a property of a
#    PAIR of files, so no per-file verdict for either one exists to cache.
#
#    🚨 CORRECTED 2026-08-13 (backlog cf440684e0e1). THE SECOND SENTENCE IS FALSE, and it was the
#    only named obstacle on the path this file's closing paragraph calls "what WOULD reach the
#    target". Rule 4's scan is `for f in …` and both of its predicates take ONE file; nothing in it
#    compares two files. The misreading came from the arm's VOCABULARY — it prints `COLLIDES … two
#    concurrent runs share it` — but the collision is between two runs of the SAME tool, which is a
#    property of that one file. The header says so outright: "the compliant position is not
#    'fixture $HOME' but 'make the path PER-RUN UNIQUE'".
#
#    What IS cross-population in that lint is rules 5 and 6, which judge a suite against a table
#    extracted from bin+scripts+hooks. That does not defeat a per-file key either — it just has to
#    be IN it. See test-hermeticity-lint.sh's HERM_READSET, which declares the table alongside the
#    allowlists and the lint's own blob, and tests/herm-suite-memo.bats, which pins that a table
#    change convicts a suite whose own bytes never moved.
#
# 3. THE ARM-LEVEL KEY THE SPEC PRESCRIBES HAS A MEASURED CEILING BELOW THE TARGET. Keying an arm
#    on (lint blob + its scanned-set state) lets a re-round skip it only when the SIBLING's delta
#    missed that arm's population entirely. Over the last 200 lands on origin/main that was true
#    for 35-46% of lands per arm, and 27% against a whole-tree-minus-prose population. So it
#    retires between one and two re-rounds in five COMPLETELY and does nothing at all for the rest
#    — it cannot deliver the spec's "<=10s at load" in the general case.
#
# 4. AND THE POPULATION DECLARATION IT WOULD HAVE TO KEY ON IS NOT A SUPERSET TODAY. The natural
#    source is each arm's own-scope pathspec, which ship-land already maintains under a stated
#    invariant ("THE PATHSPEC IS THE GATE'S SCOPE, and it must list every population the lint
#    judges"). Two counter-examples found by reading the lints: unattended-path-lint also judges
#    settings.json, which its pathspec does not list, and pipefail's pathspec lists docs/* — so
#    neither "the declared spec" nor "the tree minus prose" is reliably a superset of what the
#    lints read. Keying on a non-superset is exactly the stale-verdict generator the invariant at
#    the top of this file forbids, and an unsound memo on a repo-wide arm is worse than the 60s it
#    saves.
#
# What WOULD reach the target is per-file memoization INSIDE each lint's scan loop — the same blob
# key as above, applied where the population actually is. That needs a file-locality proof per lint
# (rule 4 above already fails it for one) and touches ~15 gate scripts, so it is a separate item,
# not a silent widening of this one. Filed rather than chosen: see the P3 note in
# docs/research/land-architecture-100p-2026-08-10.md.
#
# ── STATUS 2026-08-13: that item is STARTED, and the first lint is done ───────────────────────────
# test-hermeticity-lint.sh now memoizes per suite, using this file's own memo_file_hit/record with a
# checker-id that carries its read set. It was chosen by RE-MEASURING rather than from the numbers
# above, which had decayed: the arms are now ~135s (not ~112s) and test-hermeticity alone is 46.0s
# of it — 34%, and nothing else is close. Its shape is 10.4s fixed + 0.069s per suite, so the memo
# retires the 32s per-suite loop on a re-round and leaves the fixed table build.
#
# ⚠️ MEASURE THE ARM THE WAY THE GATE INVOKES IT. Timing these lints by running them bare gives the
# wrong answer for any arm whose own-set narrows the SCAN rather than just the blocking: measured
# bare, bats-shellcheck-lint is 50.5s and looks like the biggest target in the gate; measured
# through own_run as ship-land actually calls it, it is 0.07s.
#
# THE REMAINING ARMS ARE NOT BLOCKED ON A STANDARD. Reason 4 below is the prerequisite of the
# ARM-LEVEL key in reason 3, and reason 3 is measured-insufficient, so it stays rejected. A per-file
# memo is keyed on its own lint's inputs, so an unmemoized lint runs exactly as it does today — the
# rollout is incomplete, never unsound, and no lint waits on any other.

memo_summary() {  # one line for the gate's stderr — counters, not prose
  [[ "$MEMO_OK" = "1" ]] || { echo "→ gate: statics memo OFF (${SHIP_LAND_MEMO:-on}) — every static ran." >&2; return 0; }
  echo "→ gate: statics memo — ${MEMO_HITS} file verdict(s) carried, ${MEMO_RUNS} proven fresh." >&2
}
