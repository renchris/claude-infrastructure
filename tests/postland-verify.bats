#!/usr/bin/env bats
# postland-verify.sh — the ASYNC POST-LAND VERIFICATION NET.
#
# RED-PROOF suite written against the FROZEN CONTRACT, never against the script:
# every expected value below is derived from a contract clause quoted in a comment
# beside the assertion. Nothing here was obtained by running the SUT first.
#
# CONTRACT (the clause each test binds to):
#   C1 verbs    --run-if-needed | --run <sha> | bisect <file> <good> <bad> |
#               is-green <sha> (0 stamped-green / 1 not) | status | --selftest
#   C2 killsw   POSTLAND_VERIFY=off  =>  immediate exit 0
#   C3 state    $CC_POSTLAND_DIR/{stamps/<tree-sha>.json,last-green,queue,
#               run.lock.d/,flakes.jsonl,runner.log}   (the SUT owns creation)
#   C4 stamp    {tree,commit,verdict:"green"|"red",failing[],ts,run_s,retries,
#               suites,checks,shellcheck_advisory}
#   C4b denom   `suites` is the COUNT handed to bats — the denominator of the population the
#               verdict judged. 0 on every path where the corpus never ran (a prelint red skips
#               it). Without it a green cannot be told from a green-by-collapsed-corpus.
#   C9b render  `status` resolves last-green (a COMMIT sha) through to its TREE-keyed stamp and
#               prints BOTH names plus the verdict READ OFF DISK. A stamp that is absent renders
#               MISSING; a commit this checkout cannot resolve renders UNRESOLVABLE. Never a bare
#               sha — that is what let a correct pointer be misread as dangling.
#   C24 band    the ladder's RETRY runs in the UTILITY band, not the corpus's background clamp:
#               it is a seconds-long decision procedure on the critical path to a green stamp, and
#               at PRI 4 it is starved into the non-verdict that blocks deploy forever. RETRY_QOS
#               never expands empty (nice is its floor) — bash 3.2 + set -u would die instead.
#   C29 windows the ladder's 3 runs are BACK TO BACK on one box, so they sample ONE LOAD WINDOW and
#               a >=2/3 there is one experiment, not three. C24 varies the retry's PRIORITY, which
#               is the other half of the same law and NOT a substitute: a box at load 15 is at load
#               15 for all three attempts. Measured across C24's own landing, the false-conviction
#               fingerprint SURVIVED it — 7 of 34 consecutive red pairs fully disjoint before,
#               7 of 47 after, with 1 green in 46 sweeps before and 2 in 54 after. So a LADDER
#               conviction is a CANDIDATE: it reds only when a LATER sweep, >=CONVICT_SPREAD on,
#               convicts the same file again. One window ⇒ the C23 abstention (cut, retried) —
#               which IS the second window, so no extra run is ever scheduled. Deterministic reds
#               (prelints, bash -n, the C13b sentinel) are exempt and never delayed. The gate is
#               separation in TIME, never a lower load: the box has no quiet window, and waiting
#               for one is gate_admit again (C19/R1).
#   C5 target   origin/main of $CC_POSTLAND_REPO; ABSTAIN (exit 0) when that
#               TREE already has a stamp
#   C6 mutex    run.lock.d mkdir+{pid,lstart} — a second LIVE instance exits 0 quietly;
#               a DEAD-pid lock is reaped and the run proceeds
#   C6b ident   a pid is not an identity. The holder is genuinely alive iff its pid is alive AND
#               that pid's CURRENT start time equals the lstart recorded at acquire. A live pid
#               whose lstart DIFFERS is a stranger holding a RECYCLED pid — the real holder is
#               dead, so the lock is stale and is reaped at any age. A live pid whose lstart
#               MATCHES is never reaped at any age (H2). A lock carrying a pid but NO lstart was
#               taken by a pre-fix process: its identity is unverifiable, so it is honoured like a
#               live holder but ONLY until LOCK_TTL — never forever. Same rule, same dialect, as
#               land-lock.sh:lock_is_stale, which fixed this class on 2026-07-25.
#   C7 verdict  bats over the TREE CORPUS inside a DETACHED worktree MINTED FOR THIS RUN
#               and REMOVED on exit (v2 §4.2.1 — the reused cell carried cross-tree residue)
#   C18 partition  the corpus is tests/*.bats MINUS scripts/host-suites.manifest, passed to
#               bats as an explicit FILE LIST (never `tests/`); ONE list also indexes
#               suite_file_at, so hang attribution cannot desync from what ran. A missing
#               manifest ⇒ empty ⇒ everything runs (fail-closed toward MORE proof)
#   C19 qos     no admission control anywhere: the singleton must progress at ANY load
#   C20 revert  on a reproducible RED with a BISECTED culprit C, and only then: revert C on
#               its own branch and land it via the land lane. Refused if POSTLAND_AUTOREVERT=off ·
#               C is itself a revert · $CC_POSTLAND_DIR/reverts/<C> says the revert already LANDED
#               (never twice — permanent, and now PAGED rather than silent) or its bounded retry
#               budget is spent (POSTLAND_REVERT_RETRY_MAX, default 3); a marker whose revert never
#               landed RE-ARMS on a moved trunk tip or POSTLAND_REVERT_RETRY_DECAY_S — C26 ·
#               POSTLAND_MAX_REVERTS attempts already made this run · no land lane present.
#               An UNDECIDABLE bisect pages + backlogs and attempts ZERO reverts.
#   C25 adjudic the bisect PROBE runs under the TMPDIR the CORPUS measured under — the same string
#               when red_actions is the caller, the same template (hence the same LENGTH) when the
#               `bisect` verb mints its own. Without it a red that exists only at the corpus's longer
#               prefix cannot reproduce at any probe, and the walk is left with nothing to convict.
#               B10/B13 (postland-verify-bisect-bound.bats) make that walk REFUSE rather than name the
#               tip; this clause is the ATTRIBUTION half — it lets the walk find the real culprit
#               instead of leaving an env-dependent red permanently unattributed.
#   C21 green   a green stamp also writes <git-common-dir>/gate-green = the COMMIT sha —
#               in v2 the verifier is the only party that can make the full-suite claim
#   C22 prelint the whole-tree meta-lints run STANDALONE before the corpus, own-set seams
#               UNSET (whole-tree strict); non-zero ⇒ named RED that outranks a cut; OUR
#               bound firing proves nothing ⇒ cut, never red and never green
#   C23 ladder  a RETRY whose OWN bound fired decides NOTHING — the same rule C22 applies to a lint
#               and classify_hang applies to the suite run. It is neither a fail (nothing proven) nor
#               a pass (nothing cleared) ⇒ the run downgrades to a CUT and is retried next sweep.
#               The re-run is the failing TEST (`bats -f`), not its whole file, so the bound can
#               actually fit what it bounds; POSTLAND_RETRY_GRANULARITY=file restores file-wide.
#   C8 retries  the failing FILE is re-run alone up to 2 more times;
#               >=2/3 fails => reproducible RED; 1/3 => flake (flakes.jsonl,
#               EXCLUDED from the verdict); all-flake => verdict green
#   C9 green    stamp green + last-green advances to the commit sha
#   C10 red     stamp red, last-green NOT advanced,
#               $CC_PAGES_DIR/postland-red-<culprit12>.page (line 1 = epoch),
#               backlog add attempted via $CC_BACKLOG_BIN, osascript attempted
#   C11 idl     EVERY invocation appends a line to $CC_IDL with
#               check:"postland-verify", decision:"fired"|"abstained"
#   C12 requeue after a run it re-resolves origin/main and loops once if it moved
#   C13 cut     a non-zero run emitting ZERO `not ok` named no failing test => it was
#               TRUNCATED (killed/starved), not red. It stamps verdict "cut" for
#               diagnosability, but a cut is a DIAGNOSTIC, never a verdict: C5's
#               abstain fires only on green|red, so a cut tree is RE-RUN next sweep
#               (abstaining on it strands the tree unverified forever and keeps
#               is-green false, which makes ship-land call the net INERT). Bounded:
#               after $CC_POSTLAND_CUT_MAX consecutive cuts on one tree an honest
#               postland-cut-<tree12>.page that names no test + a cool-off; any real
#               verdict clears both the streak and the page. BOTH stamp-consulting
#               call sites are verdict-aware — the entry gate AND C12's requeue-loop
#               break — so a mid-sweep move onto a cut tree is verified, not dropped.
#   C30 grammar ONE spelling of the TAP result line, shared by every reader: a completed test is
#               `^(ok|not ok) [0-9]+` and a FAILED one is `^not ok [0-9]+`, so the failure set is a
#               strict SUBSET of the completed set and `notok > 0` IMPLIES `tap_done > 0`. The <N>
#               is the only thing separating a result line from arbitrary text opening with those
#               bytes, and arbitrary text is routine — the corpus TAP is captured `2>&1`, so an
#               unprefixed stderr write splices in raw and a killed run truncates a line mid-buffer.
#               When the readers disagreed, one TAP could be BOTH "0 tests completed" (what the
#               stall watcher cuts on) and "a failure exists" (what C13b convicts on) — runner.log
#               2026-07-30T05:47:21Z and 06:04:21Z, `STALL … at test 0` then `RED failing=tests/`.
#               Distinct from C13c, which decides the same branch on the RUN'S rc: C13c answers
#               "was anyone speaking about the tree", C30 answers "is this line a verdict at all".
#   C32 lease   ONE RED EPISODE ON ONE SUITE IS ONE PIECE OF WORK, however many rows it mints. This
#               file has four mint sites and C13e-g cover only the condition-keyed one; the other
#               three (AUTO-REVERT <outcome>, AUTO-REVERT INERT, HUNG) are title-keyed on a sha or a
#               tree, which is right for keeping one ATTEMPT per row and shares no field with the
#               RED row naming the same suite. So each of them JOINS its row to cond_slug(<suite>)
#               via `cc-backlog link` after the add — never `add --condition`, which derives the id
#               FROM the condition and would drop the second row's content instead of deduping it.
#               The dedupe is then the CLAIM's (cc-backlog claim guard 6), not the mint's: both rows
#               survive, and only the second DISPATCH is deferred while the first is live.
#   C33 locale THE {pid,lstart} IDENTITY MUST BE RENDERED CANONICALLY. `ps -o lstart=` formats through
#               LC_TIME, so the SAME live pid reads "Tue Aug 11 15:20:07 2026" from the launchd daemon
#               (no LANG ⇒ C) and "Tue 11 Aug 15:20:07 2026" from a session (LANG=en_CA.UTF-8). C6b
#               compares a RECORDED string to a FRESHLY READ one, so that skew made a LIVE holder read
#               as a recycled pid: the reader took the reap branch and a SECOND full-corpus verifier
#               started beside the first (measured 2026-08-11 — two live 441-suite runs; 8 of the 9
#               overlapping run-pairs in 170 stamps on that one day; ~50% of recent cuts read `KILLED
#               by signal 15|9 (machine pressure)`, which was the duplicate's own load). proc_lstart
#               pins LC_ALL=C and trims ps's padding at BOTH sites. An EMPTY fresh reading is an
#               unreadable INSTRUMENT, not a mismatch, and is honoured TTL-bounded — the fail
#               direction here is asymmetric: `stranger ⇒ reap` is the only branch that can mint a
#               second verifier, so an unverifiable identity must make the reader MORE patient.
#
# ISOLATION: scratch bare origin + clone under $BATS_TEST_TMPDIR, fresh $HOME, and
# argv-recording stubs for cc-backlog/osascript/cc-notify on PATH. No real repo, no
# real ~/.claude state, no network. Exit codes are asserted ONLY where the contract
# fixes them (0 for kill-switch/abstain/lock-skip/green); a RED run's exit code is
# unspecified by the contract, so it is deliberately NOT asserted.

setup() {
  # Project labels in this suite are FIXTURES, not projects — and `cc-backlog add` now WARNS on an
  # explicit --project outside the dispatch set (df2b6a40a5dc), which bats folds into $output. Off
  # here because dispatchability is not this suite's subject; tests/cc-backlog-project-dispatch.bats
  # owns it, unfixtured, in both directions.
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="${CC_POSTLAND_BIN:-$REPO/scripts/postland-verify.sh}"
  [ -f "$SUT" ] || skip "postland-verify.sh not present in this worktree"

  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/state"     # C3 — SUT creates it
  export CC_POSTLAND_REPO="$BATS_TEST_TMPDIR/repo"
  # DELIBERATELY NOT setting CC_POSTLAND_WORKTREE: pinning it made every test exercise the
  # fixed-path override and left the DEFAULT mint path — the only one production ever uses —
  # untested. The seam still works and has its own test below; the suite drives the default.
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages"        # externally owned dir
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  # v2: there is NO admission control to disable any more (C19) — the old CC_GATE_MAX_LOAD=0 export
  # lived here because every --run-if-needed reached gate_admit and stalled on this very box.
  # AUTO-REVERT OFF BY DEFAULT FOR THIS SUITE (C20): a red fixture must never be one guard away
  # from pushing. The revert tests below opt IN explicitly, so a guard that silently stopped
  # working cannot hide behind a blanket suite-wide switch.
  export POSTLAND_AUTOREVERT=off
  # C29 shrinks a BOUND, it does not disable a guard. Corroboration requires two things: a second
  # SWEEP, and >=CONVICT_SPREAD seconds between them. Only the second is impossible in a suite whose
  # sweeps are seconds apart, so only the second is relaxed — CC_POSTLAND_CONVICT stays ON for every
  # test in this file, and each red test drives its own second_window explicitly. A blanket
  # CC_POSTLAND_CONVICT=off here would be the same anti-pattern the AUTOREVERT comment above names:
  # a guard that silently stopped working would hide behind the switch. The floor itself, and the
  # kill switch itself, each have their own test below.
  export CC_POSTLAND_CONVICT_SPREAD_S=0
  # C28: the SUT now EXPORTS CC_BATS_MAX_ROOTS=0 (its cc-bats admission exemption), and C28's stubs
  # assert that the child sees it. An ambient value would supply that `0` for free and the assertion
  # would pass with the export DELETED — measured, not theorised: the first mutation run of C28 was
  # green on all three because this suite was invoked as `CC_BATS_MAX_ROOTS=0 bats …`. Same trap
  # tests/cc-bats-admission.bats records in its own setup ("an ambient value would decide the verdict
  # instead of the test"); clearing it here is what makes the SUT the only possible source.
  unset CC_BATS_MAX_ROOTS
  # Per-run worktree cells (C7) land here, so a leak is visible to the tests rather than landing
  # in the developer's real ~/Development/.worktrees.
  export CC_POSTLAND_WT_ROOT="$BATS_TEST_TMPDIR/cells"
  STUB="$BATS_TEST_TMPDIR/bin"; REC="$BATS_TEST_TMPDIR/rec"
  export CC_BACKLOG_BIN="$STUB/cc-backlog"
  mkdir -p "$HOME" "$CC_PAGES_DIR" "$STUB" "$REC"
  local s
  for s in cc-backlog osascript cc-notify; do
    printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/%s.argv"\nexit 0\n' "$REC" "$s" > "$STUB/$s"
    chmod +x "$STUB/$s"
  done
  # cc-backlog ALONE also ECHOES AN ID, because the real one does and a caller now READS it.
  # `add` returns the item id on stdout — on the idempotent path too (bin/cc-backlog cmd_add) — and
  # postland-verify's file_linked captures it to aim the follow-up `link`. A stub that printed
  # nothing made every link structurally unreachable under test while the production path linked
  # fine: the harness would have certified a mint-side dedupe it could not exercise (memory:
  # default-off-sensor / harness-default-collapses-the-states-under-test). The id is a fixed
  # 12-hex-shaped literal — tests assert the SHAPE of the argv pair, never the value, and the
  # real-binary case below is what pins identity. Everything else discards this stdout, so no
  # existing assertion moves.
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/cc-backlog.argv"\ncase "$1" in add) echo stubbedid00 ;; esac\nexit 0\n' \
    "$REC" > "$STUB/cc-backlog"
  chmod +x "$STUB/cc-backlog"
  export PATH="$STUB:$PATH"

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  # Guarded at the BINDING: `git -C ""` is a NO-OP, so an empty $CC_POSTLAND_REPO would write this
  # fixture identity into the caller's repo. Guarding here proves $R for every use site below.
  R="${CC_POSTLAND_REPO:?postland fixture: repo path required}"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$R" 2>/dev/null
  git -C "$R" symbolic-ref HEAD refs/heads/main
  git -C "$R" config user.email tester@example.com
  git -C "$R" config user.name tester
  mkdir -p "$R/tests"
  printf '@test "p" { true; }\n' > "$R/tests/ok.bats"   # a passing suite => green
  printf '#!/bin/bash\nexit 0\n' > "$R/foo.sh"; chmod +x "$R/foo.sh"
  push_commit base
}

teardown() {
  # `|| true` matters: an already-exited sleep makes kill the FAILING last command
  # of the && list, which errexit would turn into a spurious test failure.
  [ -f "$BATS_TEST_TMPDIR/live.pid" ] \
    && kill "$(cat "$BATS_TEST_TMPDIR/live.pid")" 2>/dev/null || true
  true
}

# ── fixture helpers ─────────────────────────────────────────────────────────────
push_commit() { git -C "$R" add -A; git -C "$R" commit -q -m "$1"; git -C "$R" push -qf origin HEAD:main; }
origin_head() { git -C "$R" rev-parse origin/main; }
origin_tree() { git -C "$R" rev-parse "origin/main^{tree}"; }
stamps_n()    { find "$CC_POSTLAND_DIR/stamps" -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }
# C33: the CANONICAL rendering of a pid's start time — the exact string the SUT's proc_lstart writes.
# A fixture that records a lock identity with a bare `ps` is recording it in whatever locale the
# developer's shell happens to carry, which is the very skew C33 fixes; every lstart fixture below
# goes through this so the tests assert the contract rather than the harness's own environment.
canon_lstart() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//;s/ *$//'; }
idl_last()    { tail -n1 "$CC_IDL" | jq -r "$1"; }
pages_n()     { find "$CC_PAGES_DIR" -name 'postland-red-*.page' 2>/dev/null | wc -l | tr -d ' '; }
cells_n()     { find "$CC_POSTLAND_WT_ROOT" -maxdepth 1 -name 'wt-*' 2>/dev/null | wc -l | tr -d ' '; }
cut_pages_n() { find "$CC_PAGES_DIR" -name 'postland-cut-*.page' 2>/dev/null | wc -l | tr -d ' '; }
rev_pages_n() { find "$CC_PAGES_DIR" -name 'postland-revert-*.page' 2>/dev/null | wc -l | tr -d ' '; }

# Collapse duplicate slashes into $PWD's normal form; result in $NORM (a GLOBAL, deliberately: a
# `case` inside `$( )` is a silent no-op under the bash 3.2 that ships as /bin/bash, and returning
# via stdout would force exactly that shape — memory bash32-case-in-substitution-zsh-repro-trap).
# Uses only `[ ]` and parameter expansion, both live under errexit.
#
# WHY EVERY RECORDED-CWD COMPARISON BELOW GOES THROUGH IT: a child's $PWD is slash-normalized BY
# CONSTRUCTION (bash's `cd` collapses duplicate separators), so comparing it byte-wise against a
# path built from an inherited env var asserts something about the SHAPE OF $TMPDIR rather than
# about where the cell was minted. That conflation is what produced six consecutive post-land REDs
# (stamps 4cea43d9 dc12c8db 9a3cfa48 5a409e07 22e866db 15fb714a, 2026-07-28/29): a doubled
# separator inherited from $TMPDIR left three assertions off by exactly one slash.
#
# AND WHY NORMALIZING HERE IS LOAD-BEARING, NOT COSMETIC: this suite runs INSIDE the very verifier
# it tests, so a comparison that fails on an inherited `//` makes the tree UN-GREENABLE by any
# verifier predating the producer fix — while deploy-live is fail-closed on a green stamp and the
# live layer only advances through it. That is a bootstrap circle (memory
# deployed-layer-bootstrap-circle) and it is broken from this side. The producer's own invariant —
# that it never MANUFACTURES a doubled separator — is not weakened by this; it is asserted
# separately and RED-provably by the trailing-slash test below.
norm() { NORM="$1"; while [ "${NORM#*//}" != "$NORM" ]; do NORM="${NORM%%//*}/${NORM#*//}"; done; }

# A `bats` stand-in on $CC_POSTLAND_BATS reproducing the fingerprint of a REAL truncation — the
# peer `pkill -9 -f bats-core/bats` this clause exists for: a plan promising N results, fewer
# emitted, ZERO `not ok`, exit 137 (128+SIGKILL). Stubbing the PRODUCER, not the symptom.
stub_bats() {   # $1 = name, $2 = body after the --version guard; echoes the stub's path
  printf '#!/bin/bash\n[ "$1" = "--version" ] && { echo "Bats 1.13.0"; exit 0; }\n%s\n' "$2" \
    > "$STUB/bats-$1"
  chmod +x "$STUB/bats-$1"
  printf '%s' "$STUB/bats-$1"
}

# a tests/ helper whose exit code is driven by an out-of-worktree state file, so it
# survives the SUT's fresh checkout and its per-file retry ladder (C8)
add_stateful_test() {   # $1 = basename, $2 = body of the helper script
  printf '%s\n' "$2" > "$R/tests/$1-helper.sh"
  chmod +x "$R/tests/$1-helper.sh"
  printf '@test "%s" { run bash "$BATS_TEST_DIRNAME/%s-helper.sh"; [ "$status" -eq 0 ]; }\n' \
    "$1" "$1" > "$R/tests/$1.bats"
}
# C29: a LADDER conviction is a candidate, not a verdict — the same file must be convicted again by
# a LATER sweep before it reds. The first sweep therefore stamps `cut` (nothing proven) and leaves
# the tree unstamped-green, which is exactly what makes it eligible to run again; this drives that
# second run. Named rather than inlined so every red test states, at its own call site, that its
# conviction spans two windows. Deterministic reds (prelints, bash -n) never need it.
second_window() { run bash "$SUT" --run-if-needed; }

# ── C2 kill switch ──────────────────────────────────────────────────────────────
@test "POSTLAND_VERIFY=off is an immediate no-op exit 0" {
  run env POSTLAND_VERIFY=off bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]                    # C2
  [ "$(stamps_n)" = "0" ]                # no verification happened...
  [ "$(cells_n)" = "0" ]                 # ...not even a C7 worktree cell was minted
  # (asserted by COUNTING cells, not by `[ ! -e "$CC_POSTLAND_WORKTREE" ]`: with the fixed-path
  # override no longer set, that expands to `[ ! -e "" ]`, which is vacuously true — a dead
  # assertion that would pass just as happily if the kill switch had stopped working.)
}

# ── C7 the fixed-path seam still works (production uses the default; this keeps it from rotting)
@test "C7: CC_POSTLAND_WORKTREE is still honored verbatim as the cell path" {
  export CC_POSTLAND_WORKTREE="$BATS_TEST_TMPDIR/pinned-cell"
  b="$(stub_bats pinned "printf '%s\n' \"\$PWD\" > '$REC/pinned.txt'; printf '1..1\nok 1 p\n'")"
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  norm "$CC_POSTLAND_WORKTREE"
  [ "$(cat "$REC/pinned.txt")" = "$NORM" ]                   # minted AT the pinned path...
  [ ! -d "$CC_POSTLAND_WORKTREE" ]                            # ...and still torn down (C7)
  [ "$(cells_n)" = "0" ]                                      # and nothing under the default root
}

# ── C7 slash normalization: a trailing-slash TMPDIR must not reach the corpus doubled ────────────
@test "C7: a trailing-slash TMPDIR reaches the corpus with no doubled separator" {
  # THE ROOT CAUSE OF SIX CONSECUTIVE POST-LAND REDS on this very file (stamps 4cea43d9 dc12c8db
  # 9a3cfa48 5a409e07 22e866db 15fb714a, 2026-07-28/29 — deploy-live sat fail-closed the whole
  # time and the live layer fell 58 commits behind trunk). launchd hands its jobs
  # TMPDIR=/var/folders/…/T/ WITH a trailing slash, and `mktemp` copies its template VERBATIM, so
  # `mktemp -d "${TMPDIR}/postland-run.XXXXXX"` produced `…/T//postland-run.X` — a doubled
  # separator in the MIDDLE of the string. RUN_TMP is handed to the corpus as its TMPDIR, and bats
  # chops only a TRAILING slash (bats:121 `BATS_TMPDIR=${BATS_TMPDIR%/}`), so that interior `//`
  # propagated into BATS_RUN_TMPDIR → BATS_TEST_TMPDIR → every path a test derives from it, while
  # bash's `cd` COLLAPSES duplicate slashes when it sets $PWD. Every assertion comparing a child's
  # recorded cwd to such a path then missed by exactly one slash — in the real corpus TAP at
  # 22e866dbb7ae, exactly the three positive cell-path claims failed (lines 164, 267 and 923 AT
  # THAT SHA: C7's pinned path, the mint/teardown cell, C20's revert cwd) while all 50 of their
  # siblings passed. That is why it never reproduced standalone: a plain trailing-slash TMPDIR is
  # the one shape bats chops correctly, so only the nested corpus run ever saw the doubled form.
  b="$(stub_bats slashnorm "printf 'tmpdir=%s\n' \"\$TMPDIR\" > '$REC/slash.txt'; printf '1..1\nok 1 p\n'")"
  # The base is NORMALIZED before the trailing slash is appended, so this test measures only what
  # the SUT itself adds. Passing $BATS_TEST_TMPDIR raw would inherit whatever the OUTER run's
  # $TMPDIR looked like — and this suite runs inside that outer run, so the guard would convict the
  # verifier for its caller's string (the bootstrap circle noted at norm() above).
  norm "$BATS_TEST_TMPDIR"; base="$NORM"
  run env TMPDIR="$base/" CC_POSTLAND_BATS="$b" bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  t="$(sed -n 's/^tmpdir=//p' "$REC/slash.txt")"
  # POSITIVE CONTROL: the corpus really did receive OUR per-run dir, so the claim below cannot be
  # satisfied by an empty/unset value (which trivially contains no `//`).
  [ -n "$t" ]
  [ "${t%/postland-run.*}" != "$t" ]
  # ...and no doubled separator survived into it. A live `[ ]` on a prefix strip, so a regression
  # fails the test rather than being skipped as an errexit-exempt compound.
  [ "${t%%//*}" = "$t" ]
}

# ── C9 green ────────────────────────────────────────────────────────────────────
@test "green run stamps the target TREE green, full schema, and advances last-green" {
  target="$(origin_head)"; tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  s="$CC_POSTLAND_DIR/stamps/$tree.json"          # C3: stamps/<tree-sha>.json
  [ -f "$s" ]
  run jq -r '.verdict' "$s"; [ "$output" = "green" ]     # C9 (tests/ok.bats passes)
  run jq -r '.tree'    "$s"; [ "$output" = "$tree" ]     # C4
  run jq -r '.commit'  "$s"; [ "$output" = "$target" ]   # C4
  # C4 — the full stamp field set, so a partial writer goes RED here
  run jq -e 'has("tree") and has("commit") and has("verdict") and has("failing")
             and has("ts") and has("run_s") and has("retries") and has("checks")
             and has("shellcheck_advisory")' "$s"
  [ "$status" -eq 0 ]
  [ "$(cat "$CC_POSTLAND_DIR/last-green")" = "$target" ] # C9: last-green = commit sha
}

# ── C1 is-green ─────────────────────────────────────────────────────────────────
@test "is-green: 0 for a stamped-green sha, 1 for an unverified one" {
  target="$(origin_head)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  run bash "$SUT" is-green "$target"
  [ "$status" -eq 0 ]                              # C1: stamped green => 0
  # an unverified commit: real sha, real (different) tree, never run through the net
  echo change >> "$R/foo.sh"
  git -C "$R" add -A; git -C "$R" commit -q -m unverified
  run bash "$SUT" is-green "$(git -C "$R" rev-parse HEAD)"
  [ "$status" -eq 1 ]                              # C1: not stamped => 1
}

# ── C5 abstain ──────────────────────────────────────────────────────────────────
@test "re-invocation on an already-stamped tree abstains without re-running" {
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  before="$(stamps_n)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]                              # C5: abstain is exit 0
  [ "$(stamps_n)" = "$before" ]                    # no second verification
  [ "$(idl_last '.decision')" = "abstained" ]      # C11
}

# ── C11 IDL ─────────────────────────────────────────────────────────────────────
@test "every invocation appends one postland-verify IDL line" {
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ -f "$CC_IDL" ]
  # grep -c '' (not wc -l) so a final unterminated line still counts
  [ "$(grep -c '' "$CC_IDL")" = "1" ]              # C11: one line per invocation
  [ "$(idl_last '.check')" = "postland-verify" ]
  [ "$(idl_last '.decision')" = "fired" ]          # C11: it ran
  run bash "$SUT" --run-if-needed
  [ "$(grep -c '' "$CC_IDL")" = "2" ]              # the abstain also records
}

# ── C1 status ───────────────────────────────────────────────────────────────────
@test "status is a read-only report that exits 0" {
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  before="$(stamps_n)"
  run bash "$SUT" status
  [ "$status" -eq 0 ]                              # C1
  [ "$(stamps_n)" = "$before" ]                    # reporting verifies nothing
}

# ── C7 worktree ─────────────────────────────────────────────────────────────────
# The cell is EPHEMERAL in v2, so "where did the suite run?" can no longer be answered by
# looking at the filesystem afterwards — by then the correct answer is "nowhere". It is
# answered by a SPY standing in for bats, which records its own cwd/HEAD/detachment at the
# only moment they exist. Asserting the leftovers would have quietly become an assertion
# about teardown rather than about where the verdict was computed.
@test "verification runs in a DETACHED worktree at the target, leaving CC_POSTLAND_REPO untouched" {
  target="$(origin_head)"
  repo_head_before="$(git -C "$R" rev-parse HEAD)"
  b="$(stub_bats spy "{ echo cwd=\$PWD; echo head=\$(git rev-parse HEAD); git symbolic-ref -q HEAD >/dev/null 2>&1 && echo detached=no || echo detached=yes; test -f .git && echo islink=yes || echo islink=no; } > '$REC/where.txt'; printf '1..1\nok 1 p\n'")"
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ -f "$REC/where.txt" ]                                            # the spy really ran
  grep -q "^head=$target\$"   "$REC/where.txt"                       # C7: at the TARGET sha
  grep -q '^detached=yes$'    "$REC/where.txt"                       # C7: detached
  grep -q '^islink=yes$'      "$REC/where.txt"                       # a linked worktree, not a clone
  # C7: and NOT in the repo — whose working tree is the live ~/.claude layer
  run grep -q "^cwd=$R\$" "$REC/where.txt"
  [ "$status" -ne 0 ]
  [ "$(git -C "$R" rev-parse HEAD)" = "$repo_head_before" ]
  [ -z "$(git -C "$R" status --porcelain)" ]
}

# ── C7 lifecycle: minted per run, then removed ──────────────────────────────────
@test "C7: the worktree cell is MINTED for the run and REMOVED afterwards (no residue, no leak)" {
  # the cell must EXIST while the verdict is computed...
  b="$(stub_bats live "printf '%s\n' \"\$PWD\" > '$REC/cell.txt'; printf '1..1\nok 1 p\n'")"
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  cell="$(cat "$REC/cell.txt")"
  [ -n "$cell" ]
  # minted where v2 says: a live `[ ]` on prefix-stripping, so a wrong root fails the test
  norm "$CC_POSTLAND_WT_ROOT"
  [ "${cell#"$NORM"/wt-run-}" != "$cell" ]
  # ...and be gone afterwards, with git's own worktree list agreeing (a `rm -rf` alone would
  # leave a registered-but-missing worktree that blocks the next `worktree add` on that path).
  [ ! -d "$cell" ]
  run bash -c "git -C '$R' worktree list | grep -cF '$cell'"
  [ "$output" = "0" ]
  [ -z "$(find "$CC_POSTLAND_WT_ROOT" -maxdepth 1 -name 'wt-run-*' 2>/dev/null)" ]
  # POSITIVE CONTROL — a SECOND run mints again rather than reusing: a different path proves
  # freshness, and this test cannot pass by the verifier simply never creating a cell at all.
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed        # same tree ⇒ abstains, so move it
  echo moved >> "$R/foo.sh"; push_commit "second tree"
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  cell2="$(cat "$REC/cell.txt")"
  [ -n "$cell2" ]
  [ ! -d "$cell2" ]
}

# ── C7 lifecycle, the OTHER minter: the standalone `bisect` verb ────────────────
# do_bisect mints a cell exactly like a `--run` does, but its two callers reach it from opposite
# sides of a SUBSHELL. red_actions runs on a tree the run already minted for, so the parent's
# WT_MINTED already names the cell and the EXIT trap removes it. verb_bisect is the first thing in
# the process to mint — and while it called do_bisect through command substitution, that subshell's
# assignment to WT_MINTED could not reach the parent that runs the trap. teardown_worktrees saw an
# EMPTY WT_MINTED and removed nothing, so the verb leaked its cell on EVERY path, success included,
# while the `--run-if-needed` test above tore its own down. That test could never see it: it drives
# a verb whose mint happens in the parent shell.
#
# The runner fix (do_bisect returning through BISECT_CULPRIT) landed without a regression test, so
# nothing held the property it established. This is that test. It is written against the CONTRACT —
# "after the verb, no cell survives" — not against the return mechanism, so a later refactor that
# keeps the property passes and one that reintroduces a subshell anywhere in the mint's call tree
# fails, whichever way the culprit is returned.
@test "C7: the standalone bisect verb tears its cell down too — on success AND on undecidable" {
  printf '@test "subj" { true; }\n' > "$R/tests/subj.bats"; push_commit "subj green"
  good="$(origin_head)"
  printf '@test "subj" { false; }\n' > "$R/tests/subj.bats"; push_commit "the culprit"
  culprit="$(origin_head)"
  echo unrelated >> "$R/foo.sh"; push_commit "innocent tip"
  bad="$(origin_head)"

  run bash "$SUT" bisect subj.bats "$good" "$bad"
  [ "$status" -eq 0 ]
  # POSITIVE CONTROL, and it is what stops "0 cells" passing vacuously: naming the CULPRIT rather
  # than the tip proves the runner really executed inside a minted, bisecting cell. A verb that
  # minted nothing (and so had nothing to leak) could not have produced this sha.
  [ "$output" = "$culprit" ]
  [ "$(cells_n)" = "0" ]

  # ...and the undecidable path mints just the same: the subject file is absent at every step, so
  # every runner invocation SKIPs and no culprit is decided. The cell is still owed a teardown.
  run bash "$SUT" bisect nosuch.bats "$good" "$bad"
  [ "$status" -ne 0 ]
  [ "$(cells_n)" = "0" ]
}

# ── C5 tree-keying ──────────────────────────────────────────────────────────────
@test "stamps key on TREE: an amended commit (same tree, new sha) abstains" {
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  before="$(stamps_n)"; tree_before="$(origin_tree)"; head_before="$(origin_head)"
  # --amend with no staged change => identical tree, different commit sha
  git -C "$R" commit -q --amend -m "same tree, new sha"
  git -C "$R" push -qf origin HEAD:main
  [ "$(origin_tree)" = "$tree_before" ]            # fixture invariant: tree unchanged
  [ "$(origin_head)" != "$head_before" ]           # fixture invariant: sha changed
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ "$(stamps_n)" = "$before" ]                    # C5: keyed on tree, not commit
  [ "$(idl_last '.decision')" = "abstained" ]      # C11
}

# ── C12 requeue ─────────────────────────────────────────────────────────────────
@test "a target that moved after a green run is verified on the next invocation" {
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ "$(stamps_n)" = "1" ]
  echo moved >> "$R/foo.sh"                        # new tree => supersession
  push_commit "superseding commit"
  moved_tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ "$(stamps_n)" = "2" ]                          # C12: the new tree is verified too
  [ -f "$CC_POSTLAND_DIR/stamps/$moved_tree.json" ]
}

# ── C6 mutex ────────────────────────────────────────────────────────────────────
@test "a LIVE run.lock.d holder makes the second instance exit 0 without running" {
  mkdir -p "$CC_POSTLAND_DIR/run.lock.d"
  sleep 300 >/dev/null 2>&1 &
  live=$!
  echo "$live" > "$BATS_TEST_TMPDIR/live.pid"      # teardown kills it
  echo "$live" > "$CC_POSTLAND_DIR/run.lock.d/pid" # a lock held by a LIVE pid
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]                              # C6: quiet exit 0
  [ "$(stamps_n)" = "0" ]                          # it did NOT verify
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]
}

@test "a DEAD-pid run.lock.d is reaped and the run proceeds" {
  mkdir -p "$CC_POSTLAND_DIR/run.lock.d"
  bash -c 'exit 0' & dead=$!; wait "$dead" 2>/dev/null || true
  echo "$dead" > "$CC_POSTLAND_DIR/run.lock.d/pid"   # pid is gone => stale lock
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ "$(stamps_n)" = "1" ]                          # C6: reaped, verification ran
  [ -f "$CC_POSTLAND_DIR/stamps/$(origin_tree).json" ]
}

# ── C6b {pid,lstart} identity ───────────────────────────────────────────────────
# The two tests above cannot tell a RECYCLED pid from the original holder — both write a bare pid,
# which is exactly the information the pre-fix mutex had. That gap was the wedge: a holder that died
# and whose pid the OS handed to an unrelated process read as permanently live, and $LOCK_TTL is
# consulted only on the EMPTY-holder branch, so nothing ever released it. Every test below therefore
# writes an lstart, because that is the byte the verdict now turns on.
@test "C6b: a RECYCLED pid (alive, lstart DIFFERS) is a stranger — the lock is reaped, not honoured" {
  mkdir -p "$CC_POSTLAND_DIR/run.lock.d"
  sleep 300 >/dev/null 2>&1 &
  live=$!
  echo "$live" > "$BATS_TEST_TMPDIR/live.pid"      # teardown kills it
  echo "$live" > "$CC_POSTLAND_DIR/run.lock.d/pid"
  # The recorded identity of the DEAD original holder. A start time in 1970 cannot be any live
  # process's, so this is a stranger by construction and never by a timing accident.
  echo "Thu Jan  1 00:00:00 1970" > "$CC_POSTLAND_DIR/run.lock.d/lstart"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ "$(stamps_n)" = "1" ]                          # C6b: reaped => the run PROCEEDED (no wedge)
  [ -f "$CC_POSTLAND_DIR/stamps/$(origin_tree).json" ]
}

@test "C6b CONTROL: a GENUINE live holder (lstart MATCHES) is never reaped — at any age" {
  # The control that stops the fix from degenerating into "always reap": if this ever passes while
  # the reap is unconditional, the mutex has silently stopped being a mutex. Aged 6 years past
  # LOCK_TTL deliberately — H2 is "never at ANY age", not "not yet".
  mkdir -p "$CC_POSTLAND_DIR/run.lock.d"
  sleep 300 >/dev/null 2>&1 &
  live=$!
  echo "$live" > "$BATS_TEST_TMPDIR/live.pid"      # teardown kills it
  echo "$live" > "$CC_POSTLAND_DIR/run.lock.d/pid"
  canon_lstart "$live" > "$CC_POSTLAND_DIR/run.lock.d/lstart"       # the SAME process, still running
  touch -t 202001010000 "$CC_POSTLAND_DIR/run.lock.d"               # ...and long past LOCK_TTL
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]                              # C6: quiet exit 0
  [ "$(stamps_n)" = "0" ]                          # it did NOT verify
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]
}

@test "C6b compat: a pid-only lock (pre-fix holder) is honoured, but only until LOCK_TTL" {
  # A lock taken by a process from before the identity rule carries no lstart, so its identity is
  # unverifiable. Fail-safe direction is too-patient, not too-eager — but bounded, because an
  # unverifiable holder is precisely what a TTL exists for. Both halves are asserted, since a rule
  # that only ever honours (or only ever reaps) is not a compatibility rule.
  mkdir -p "$CC_POSTLAND_DIR/run.lock.d"
  sleep 300 >/dev/null 2>&1 &
  live=$!
  echo "$live" > "$BATS_TEST_TMPDIR/live.pid"      # teardown kills it
  echo "$live" > "$CC_POSTLAND_DIR/run.lock.d/pid" # pid, NO lstart => pre-fix shape
  run bash "$SUT" --run-if-needed                  # inside TTL: honoured
  [ "$status" -eq 0 ]
  [ "$(stamps_n)" = "0" ]
  touch -t 202001010000 "$CC_POSTLAND_DIR/run.lock.d"   # past TTL: the escape the pre-fix code lacked
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ "$(stamps_n)" = "1" ]                          # reaped on age alone => never a permanent wedge
}

# ── C33 locale-canonical identity ───────────────────────────────────────────────
# `ps -o lstart=` formats through LC_TIME. The daemon runs under launchd (no LANG ⇒ C) and renders
# "Tue Aug 11 15:20:07 2026"; a session-fired run under LANG=en_CA.UTF-8 renders the SAME instant as
# "Tue 11 Aug 15:20:07 2026". C6b's rule compares a RECORDED string to a FRESHLY READ one, so that
# skew made a live holder read as a recycled pid, the reader took the reap branch, and a SECOND
# full-corpus verifier started beside the first — measured on this box 2026-08-11 (two live 441-suite
# runs; 8 of the 9 overlapping run-pairs in 170 stamps fell on that one day). Two corpora on one box
# is self-inflicted machine pressure, and ~50% of recent cuts read `KILLED by signal 15|9`.
#
# `ps` IS STUBBED, deliberately: the real one only exhibits the skew on a box whose locale differs
# from C, so a test driving /bin/ps would silently degrade to a no-op on a C-locale machine and
# certify the fix while proving nothing (memory: default-off-sensor / harness-default-collapses-
# the-states-under-test). The stub emulates exactly the one behaviour under test — lstart renders
# per-locale — and defers everything else to the real binary.
stub_locale_ps() { # <mode: skew|blind> — install a $PATH `ps` that emulates the C33 hazard
  cat > "$STUB/ps" <<PS
#!/bin/bash
q=
for a in "\$@"; do [ "\$a" = "lstart=" ] && q=1; done
[ -n "\$q" ] || exec /bin/ps "\$@"
case "$1" in
  blind) exit 0 ;;                                     # the instrument cannot be read at all
  *) if [ "\${LC_ALL:-}" = "C" ]; then printf 'Tue Aug 11 15:20:07 2026    \n'
     else                              printf 'Tue 11 Aug 15:20:07 2026    \n'; fi ;;
esac
PS
  chmod +x "$STUB/ps"
}

@test "C33: a LIVE holder recorded under a DIFFERENT LC_TIME is honoured — no second verifier" {
  mkdir -p "$CC_POSTLAND_DIR/run.lock.d"
  sleep 300 >/dev/null 2>&1 &
  live=$!
  echo "$live" > "$BATS_TEST_TMPDIR/live.pid"      # teardown kills it
  echo "$live" > "$CC_POSTLAND_DIR/run.lock.d/pid"
  stub_locale_ps skew
  # The daemon's record: rendered in C, with ps's column padding left intact, because that is what
  # a lock already on disk looks like. Post-fix the READ side trims, so padding is not identity.
  LC_ALL=C ps -o lstart= -p "$live" > "$CC_POSTLAND_DIR/run.lock.d/lstart"
  [ -s "$CC_POSTLAND_DIR/run.lock.d/lstart" ]      # the fixture is armed, not silently empty
  # ...read back by a session-shaped environment, which renders the same instant day-first.
  # UNSET rather than set-empty: that is the shape a real session carries (LANG alone), and an
  # empty LC_ALL= before a command is SC1007 — the gate is right that it reads as a typo.
  unset LC_ALL LC_TIME
  export LANG=en_CA.UTF-8
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]                              # C6: quiet exit 0
  [ "$(stamps_n)" = "0" ]                          # C33: it did NOT start a second verifier
  [ "$(cat "$CC_POSTLAND_DIR/run.lock.d/pid")" = "$live" ]   # ...and did not steal the lock
}

@test "C33: an UNREADABLE lstart instrument does not convict a LIVE holder" {
  # `ps` returning nothing for a pid `kill -0` has just proved alive is a FAILED PROBE, not a
  # stranger. Pre-C33 the empty reading fell straight through the `rec != cur` comparison into the
  # reap branch, so an instrument failure — the one condition under which nothing is known — was
  # the one that produced two live verifiers. Fail-safe direction is honour-and-bound, as with the
  # missing-lstart compat rule above; the TTL half is asserted so this cannot become "honour forever".
  mkdir -p "$CC_POSTLAND_DIR/run.lock.d"
  sleep 300 >/dev/null 2>&1 &
  live=$!
  echo "$live" > "$BATS_TEST_TMPDIR/live.pid"      # teardown kills it
  echo "$live" > "$CC_POSTLAND_DIR/run.lock.d/pid"
  printf 'Tue Aug 11 15:20:07 2026\n' > "$CC_POSTLAND_DIR/run.lock.d/lstart"
  stub_locale_ps blind
  run bash "$SUT" --run-if-needed                  # inside TTL: honoured
  [ "$status" -eq 0 ]
  [ "$(stamps_n)" = "0" ]
  touch -t 202001010000 "$CC_POSTLAND_DIR/run.lock.d"        # past TTL: still never a permanent wedge
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ "$(stamps_n)" = "1" ]
}

@test "C6b: the acquirer records its OWN {pid,lstart} — the identity the rule compares against" {
  # Without the lstart WRITE every production lock is a compat lock and the recycled-pid wedge comes
  # back (bounded by LOCK_TTL rather than forever) — with all three tests above still green, because
  # each writes its own fixture. Only a lock this SUT took can prove it, and one can only be observed
  # while the SUT still HOLDS it, so the corpus is made to wedge and the holder is read mid-run.
  # POLLED, never slept: nothing here depends on how fast the box is.
  printf '@test "wedge" { sleep 60; }\n' > "$R/tests/wedge.bats"
  push_commit "a suite that wedges (mutex-identity path)"
  bash "$SUT" --run-if-needed >/dev/null 2>&1 &    # stdout/stderr detached: a bg job holding bats'
  runner=$!                                        # pipe open would hang the suite, not this test
  echo "$runner" > "$BATS_TEST_TMPDIR/live.pid"    # teardown kills it
  L="$CC_POSTLAND_DIR/run.lock.d"
  for _ in $(seq 1 120); do [ -s "$L/pid" ] && break; sleep 0.5; done
  [ -s "$L/pid" ]                                  # the SUT took the lock
  holder="$(cat "$L/pid")"
  [ -s "$L/lstart" ]                               # ...and recorded an identity, not just a pid
  [ "$(cat "$L/lstart")" = "$(canon_lstart "$holder")" ]   # ...its OWN, in the C33 canonical form
  # `wait` is not politeness: without it bash reports the SIGTERMed job on stderr ("Terminated: 15"),
  # which lands in this suite's own TAP stream as a non-TAP line.
  kill "$runner" 2>/dev/null || true
  wait "$runner" 2>/dev/null || true
}

# ── C10 red ─────────────────────────────────────────────────────────────────────
@test "RED run: red stamp, last-green FROZEN, page file + backlog add fired" {
  run bash "$SUT" --run-if-needed                  # establish a green baseline
  [ "$status" -eq 0 ]
  green="$(cat "$CC_POSTLAND_DIR/last-green")"
  printf '@test "f" { false; }\n' > "$R/tests/bad.bats"   # fails 3/3 => C8 red
  push_commit "the culprit"
  bad="$(origin_head)"; badtree="$(origin_tree)"
  run bash "$SUT" --run-if-needed                  # window 1 — C29: a candidate, stamped cut
  s="$CC_POSTLAND_DIR/stamps/$badtree.json"
  [ -f "$s" ]
  run jq -r '.verdict' "$s"; [ "$output" = "cut" ]                 # C29: one window proves nothing
  second_window                                    # window 2 re-convicts the same file => RED
  run jq -r '.verdict' "$s"; [ "$output" = "red" ]                 # C10
  run jq -e '.failing | length > 0' "$s"; [ "$status" -eq 0 ]      # C4: names the file
  [ "$(cat "$CC_POSTLAND_DIR/last-green")" = "$green" ]            # C10: NOT advanced
  # C10: $CC_PAGES_DIR/postland-red-<culprit12>.page, line 1 = epoch seconds
  page="$CC_PAGES_DIR/postland-red-${bad:0:12}.page"
  [ -f "$page" ]
  head -n1 "$page" | grep -qE '^[0-9]{10,}$'
  grep -q "${bad:0:12}" "$REC/cc-backlog.argv"                     # C10: backlog add
  [ -f "$REC/osascript.argv" ]                                     # C10: notify attempt
}

# ── C8 flake ────────────────────────────────────────────────────────────────────
@test "1-of-3 flake is excluded from the verdict: green stamp, flakes.jsonl, no page" {
  # fails only on its FIRST ever run => 1 fail / 3 attempts => flake, not red
  m="$BATS_TEST_TMPDIR/flake-marker"
  add_stateful_test flaky "$(printf '#!/bin/bash\nM="%s"\n[ -f "$M" ] && exit 0\ntouch "$M"\nexit 1\n' "$m")"
  push_commit "flaky suite"
  tree="$(origin_tree)"; target="$(origin_head)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "green" ]                          # C8: all-flake => green
  [ -s "$CC_POSTLAND_DIR/flakes.jsonl" ]           # C8: the flake is recorded...
  grep -q flaky "$CC_POSTLAND_DIR/flakes.jsonl"    # ...and names the file
  [ "$(pages_n)" = "0" ]                           # C10 pages are RED-only
  [ "$(cat "$CC_POSTLAND_DIR/last-green")" = "$target" ] # C9 still advances
}

@test "2-of-3 failures are reproducible RED, not a flake" {
  run bash "$SUT" --run-if-needed                  # green baseline => a bisect floor
  [ "$status" -eq 0 ]
  green="$(cat "$CC_POSTLAND_DIR/last-green")"
  # fails attempts 1 and 2, passes attempt 3 => 2/3 => a conviction (the C8 boundary case;
  # a SUT that short-circuits at 2 fails never reaches attempt 3 — still convicted).
  # MODULAR, not "n>=3": C29 makes this a TWO-sweep test, so the fixture has to present the same
  # 2-of-3 shape in EACH window (attempts 1,2,3 then 4,5,6). A plain >=3 latch would pass outright
  # in window 2 and the file would clear as a flake — the test would then pass for the wrong reason
  # on a broken SUT, which is the failure this whole clause exists to prevent.
  c="$BATS_TEST_TMPDIR/counter"
  add_stateful_test twofail "$(printf '#!/bin/bash\nC="%s"\nn=$(cat "$C" 2>/dev/null || echo 0)\nn=$((n+1))\necho "$n" > "$C"\n[ $((n %% 3)) -eq 0 ] && exit 0\nexit 1\n' "$c")"
  push_commit "reproducibly failing suite"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed                  # window 1 => candidate, not a verdict
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                            # C29: a same-window 2/3 is ONE experiment
  second_window                                    # window 2 convicts 2/3 again => RED
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "red" ]                            # C8: >=2/3 => reproducible RED
  [ "$(pages_n)" = "1" ]                           # C10
  [ "$(cat "$CC_POSTLAND_DIR/last-green")" = "$green" ]   # C10: NOT advanced
  [ ! -s "$CC_POSTLAND_DIR/flakes.jsonl" ] || ! grep -q twofail "$CC_POSTLAND_DIR/flakes.jsonl"
}

# ── C23 the ladder's OWN bound: a re-run that never returned decides nothing ──────────────────────
# THE 0-GREEN-STAMP DEADLOCK, root-caused 2026-07-29. The ladder re-ran the whole FILE under
# FILE_TO=300 and counted ANY non-zero rc as a fail — 124 included, which `bounded` itself documents
# as "OUR bound fired". Every other 124 site in the SUT already refuses to read its own bound as
# evidence about the tree (C22 prelint ⇒ cut · confirm_hang ⇒ the HUNG discriminator · classify_hang
# case 1 · the stall unify). This was the ONE site that did, and that is the whole deadlock: a suite
# slower than the bound could only ever be CONVICTED, never exonerated — both retries returned 124,
# `fails` reached 3/3, and the tree got a "reproducible RED" that no re-run could ever clear. Result:
# 33 stamps, 0 green EVER, so deploy-live refused forever and the live layer sat 32 commits behind.
# MEASURED: this very suite is ~50 min solo (51 tests × scratch git repos) = 10x the bound, and
# flakes.jsonl 2026-07-28T19:39Z carries `exit 124 / notok=0` for tests/postland-verify.bats at load
# 6.61 — while the LAND gate filed that identical signal correctly as `cut-not-red`. The convicted
# suites were exactly the heaviest ones (waiting-recycle 98 tests, cc-reaper 80, ship-land 74,
# cc-backlog 61, postland-verify 51) — the tell that the bound, not the tree, was doing the deciding.
@test "C23: a retry whose OWN bound fires is a CUT, never a RED (the 0-green-stamp deadlock)" {
  run bash "$SUT" --run-if-needed                  # green baseline => last-green to freeze against
  [ "$status" -eq 0 ]
  green="$(cat "$CC_POSTLAND_DIR/last-green")"
  # Fails FAST the first time, so the corpus TAP names the file and the ladder is entered; then
  # WEDGES on every re-run, so the ladder's OWN bound is the only thing that can end the retry.
  m="$BATS_TEST_TMPDIR/wedge-marker"
  add_stateful_test slowfail "$(printf '#!/bin/bash\nM="%s"\n[ -f "$M" ] && sleep 60\ntouch "$M"\nexit 1\n' "$m")"
  push_commit "a suite too slow for the ladder's bound"
  tree="$(origin_tree)"
  POSTLAND_FILE_TIMEOUT_S=3 POSTLAND_RETRY_TIMEOUT_S=3 run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                            # C23: our own bound proves nothing ⇒ cut, and
                                                   # emphatically NOT the red that blocks deploy
  [ "$(pages_n)" = "0" ]                           # C10: pages are RED-only
  [ "$(cat "$CC_POSTLAND_DIR/last-green")" = "$green" ]   # never advances on a non-verdict
}

# NO GREEN BASELINE IN THE TWO GRANULARITY TESTS, DELIBERATELY — it is what keeps their count about
# the LADDER. With no last-green, red_actions hands do_bisect an empty `good` and it returns at its
# own first guard, having minted nothing and RUN nothing, so the witness counts the corpus run and
# the retries and nothing else. Bisect probe counts are B10-B16's, in postland-verify-bisect-bound.bats.
#
# WHY THIS IS A DECOUPLING AND NOT A TIDY-UP. The original fixture DID run a green baseline, and its
# accounting — "2 = corpus (1) + C20's bisect re-running the whole file (1)" — was measured and
# correct when it landed (833dcf35, 2026-07-29). It went FALSE eight days later with neither side
# changing: 937c6fc5 added a TIP CONFIRMATION that re-runs the failing file whenever the walk names
# `bad`, which is exactly this fixture's shape (a one-commit range, so the walk's only candidate IS
# the tip and the confirmation is its deliberately-redundant second run), and 4348ddc2 added a floor
# probe on the same path (N/A here — the file does not exist at the floor, so it costs no run).
# Measured against that pair: 3 where the test said 2, and 5 where it said 4. Both C23 tests went
# reproducibly red for a change in a mechanism they do not test and cannot see. The count no longer
# spans it, so a third endpoint guard can land tomorrow and these two stay green.
@test "C23: the re-run is the failing TEST, not its whole file (what makes the bound fit)" {
  # ONE file, TWO tests: one fails every time, one records every execution of itself.
  wit="$BATS_TEST_TMPDIR/witness"
  printf '@test "boom" { false; }\n@test "wit" { echo x >> "%s"; }\n' "$wit" > "$R/tests/pair.bats"
  push_commit "one failing test beside a witness"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  second_window                                    # C29: conviction spans two sweeps
  # The PREMISE of the count, asserted rather than assumed: no last-green ⇒ no bisect ⇒ nothing but
  # the ladder can move the number below. Restore a baseline run above and this fails HERE, at the
  # reason, instead of leaving the count to drift by whatever the bisect happens to cost that month.
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]
  # WITNESS ACCOUNTING (measured, so nobody has to re-derive it): 2 = the corpus run in EACH of the
  # two C29 windows, alone. The four RETRIES contribute ZERO, because each re-ran only the named
  # test. The paired file-granularity test below is the control: same fixture, 6 — and that delta of
  # exactly 4 IS the retries, 2 per window.
  [ "$(wc -l < "$wit" | tr -d ' ')" = "2" ]
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "red" ]                            # C8 still convicts: "boom" failed 3/3, twice over
}

@test "C23: POSTLAND_RETRY_GRANULARITY=file restores the whole-file re-run" {
  wit="$BATS_TEST_TMPDIR/witness2"
  printf '@test "boom" { false; }\n@test "wit" { echo x >> "%s"; }\n' "$wit" > "$R/tests/pair2.bats"
  push_commit "the granularity seam"
  tree="$(origin_tree)"
  # `run env VAR=…` rather than a bare `VAR=… run …`: an env prefix on a bats FUNCTION has
  # POSIX-vs-bash persistence quirks, and this seam must reach BOTH windows unambiguously. It is
  # also the form the rest of this suite already uses for seams (see the CC_POSTLAND_BATS sites).
  run env POSTLAND_RETRY_GRANULARITY=file bash "$SUT" --run-if-needed   # C29 window 1
  run env POSTLAND_RETRY_GRANULARITY=file bash "$SUT" --run-if-needed   # C29 window 2
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]           # same premise: no bisect inside this number
  # 6 = per C29 window [corpus (1) + TWO WHOLE-FILE retries (2)] × 2. Against the test-granular
  # default the same fixture yields 2 — the seam is what moves those four executions, and now the
  # ONLY thing that can.
  [ "$(wc -l < "$wit" | tr -d ' ')" = "6" ]
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "red" ]                            # the seam changes HOW the ladder re-runs, never WHAT it decides
}

# ── C29 the ladder's three runs are ONE load window ───────────────────────────────────────────────
# THE FALSE-CONVICTION DEFECT, filed 2026-07-28, re-measured 2026-08-08. classify_failures re-runs a
# failing test twice more BACK TO BACK — seconds apart, same box, inside one run. So its three
# observations sample ONE LOAD WINDOW, and ">=2/3 agreed" means only "it failed twice under the same
# ambient load" — which is what a starved box produces just as reliably as a bug.
# GATE_ARCHITECTURE_PLAN.md already recorded the law one variable off: "re-running is evidence only
# if the environment actually changed" (written about a ladder that re-ran under the same wrong PATH
# three times and called the agreement reproducible).
#
# WHY THIS IS NOT C24 AGAIN, WHICH IS THE WHOLE POINT. C24 (08dd4e3c) closed the FIRST half of that
# law: the retry now runs in the UTILITY band instead of the corpus's background clamp, so the
# re-run genuinely does happen in a different environment. It helped and it stays. But the variable
# it moves is PRIORITY, not AMBIENT LOAD — a box at load 15 is at load 15 for all three attempts,
# and a suite losing to memory or IO pressure loses in utility too. MEASURED over the 100 stamps on
# disk, split at C24's own landing:
#     PRE  C24 (n=46): 42 red · 1 green · 2 cut · 1 hung — 7 of 34 consecutive red pairs DISJOINT
#     POST C24 (n=54): 48 red · 2 green · 4 cut        — 7 of 47 consecutive red pairs DISJOINT
# The fingerprint SURVIVED the band fix. A genuine red re-convicts the SAME file until somebody
# fixes it; a convicted set that reshuffles sweep to sweep (prev=11 now=2 overlap=0 · prev=12 now=1
# overlap=0 · prev=9 now=1 overlap=0) is the box talking, not the tree. Two greens in 54 sweeps, and
# a red is not just a wrong stamp — it is terminal for that tree (C5 abstains on it forever) and it
# arms the bisect and AUTO-REVERT, which pushes a revert of an innocent commit to trunk.
#
# WHAT THIS IS NOT: more retries. §8 of LAND_PIPELINE_V2 forbids that class outright ("raising the
# ceiling / more retries / bigger budgets" = parameter motion in a broken frame), and nothing here
# adds an attempt, a poll, a sleep or a budget — the in-run ladder is untouched and costs what it
# always did. Only the WORTH of one window's agreement changes: it becomes the C23 abstention, and
# the cut C23 already performs is itself the second window. Nor is it a wait for a quiet box — that
# is gate_admit (C19/R1), and this box has no quiet window by construction. The gate is separation
# in TIME, which the clock always eventually satisfies; load is recorded, never tested.
@test "C29: a conviction that does NOT reproduce in a second window is a flake, not a RED" {
  # THE WHOLE POINT, stated as a fixture: fails 3/3 inside window 1 — unanimous, by the old rule an
  # open-and-shut "reproducible RED" — and then passes once the window moves. That is precisely the
  # shape a load-starved suite has, and precisely what the old ladder could not tell from a bug.
  c="$BATS_TEST_TMPDIR/window-counter"
  add_stateful_test loadflake "$(printf '#!/bin/bash\nC="%s"\nn=$(cat "$C" 2>/dev/null || echo 0)\nn=$((n+1))\necho "$n" > "$C"\n[ "$n" -le 3 ] && exit 1\nexit 0\n' "$c")"
  push_commit "a suite that fails 3/3 in one window and passes in the next"
  tree="$(origin_tree)"
  target="$(origin_head)"
  run bash "$SUT" --run-if-needed                  # window 1: attempts 1,2,3 all fail
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                            # C29: 3/3 in ONE window still proves nothing
  [ "$(pages_n)" = "0" ]                           # C10: pages stay RED-only
  second_window                                    # window 2: attempt 4 passes
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "green" ]                          # C29: the second window CLEARED it
  [ "$(cat "$CC_POSTLAND_DIR/last-green")" = "$target" ]   # C9: and the tree is provable again
  [ "$(pages_n)" = "0" ]                           # nothing was ever paged as a red
}

@test "C29: the SPREAD floor holds — two sweeps too close together do not corroborate" {
  # CONVICT_SPREAD is what stops a run's own ladder, or two runs that happen to land back to back,
  # from counting as two windows. Asserted with the floor RAISED, so the sweeps below cannot clear
  # it, and controlled at the other side of the boundary in the same body.
  printf '@test "f" { false; }\n' > "$R/tests/bad.bats"
  push_commit "always fails"
  tree="$(origin_tree)"
  # CUT_MAX pinned, not inherited: this is the one test that takes THREE sweeps on ONE tree, and the
  # default CUT_MAX is 3 — so the third sweep clears the cool-off refusal by a margin of exactly
  # zero. Lower that unrelated constant to 2 and this test goes red for a reason that has nothing to
  # do with corroboration, which is precisely the coupling the suite keeps pinning out.
  export CC_POSTLAND_CUT_MAX=99
  run env CC_POSTLAND_CONVICT_SPREAD_S=3600 bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]
  run env CC_POSTLAND_CONVICT_SPREAD_S=3600 bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                            # C29: seconds apart is not a second WINDOW
  # POSITIVE CONTROL at the other side of the boundary — the identical tree with the floor dropped
  # must red, else this test would pass just as happily if corroboration were dead in every case.
  run env CC_POSTLAND_CONVICT_SPREAD_S=0 bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "red" ]
}

@test "C29: a VERDICT spends the candidates — a green in between cannot corroborate a later red" {
  # The trap this closes: candidate rows live for CONVICT_TTL (24h), so without an explicit clear a
  # file convicted once, then EXONERATED by a green corpus, then failing once more hours later would
  # be red off a SINGLE window — C29 rebuilt out of its own state. Fails runs 1-3 (window 1), passes
  # run 4 (window 2 ⇒ green ⇒ candidates spent), fails from run 5 on.
  c="$BATS_TEST_TMPDIR/spend-counter"
  add_stateful_test spender "$(printf '#!/bin/bash\nC="%s"\nn=$(cat "$C" 2>/dev/null || echo 0)\nn=$((n+1))\necho "$n" > "$C"\n[ "$n" -eq 4 ] && exit 0\nexit 1\n' "$c")"
  push_commit "convicted, then exonerated, then failing again"
  t1="$(origin_tree)"
  run bash "$SUT" --run-if-needed                  # window 1 => candidate recorded
  second_window                                    # window 2 => GREEN, ledger cleared
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$t1.json"
  [ "$output" = "green" ]                          # precondition, asserted not assumed
  printf '# retarget\n' >> "$R/tests/spender.bats"
  push_commit "a new tree, same suite, now failing again"
  t2="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$t2.json"
  [ "$output" = "cut" ]                            # C29: the pre-green row may NOT corroborate
  second_window                                    # ...and a genuine second window still converges
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$t2.json"
  [ "$output" = "red" ]
}

# ── C29b a verdict spends only the candidates it ADJUDICATED ──────────────────────────────────────
# THE EVIDENCE LEAK, filed 2026-08-11, measured off runner.log 2026-08-22. `conviction_clear` wiped
# the WHOLE ledger at all three verdict sites. That is right for a GREEN — it ran the corpus,
# everything passed, so every candidate row predating it is genuinely stale — and wrong for a RED,
# which exonerates nothing: it names file A and says nothing whatever about file B, dropped from
# FAILING in that same run only because C29 ruled one window insufficient. 42 of 79 pendings were
# wiped; 22 of those by a RED or a HUNG (27.8% of all pendings), 7 of them SAME-RUN — the pending
# and the verdict seconds apart inside one corroborate_convictions loop.
#
# WHY NO TEST CAUGHT IT FOR ELEVEN DAYS, and what that demands of these three: every C29 fixture
# above puts exactly ONE failing file in the tree, and with one file there is no such thing as
# "one corroborates while another pends" — the mixed state that reaches the RED branch with a live
# pending is unreachable from a single-file fixture, so the bug had no shape to fail in. These
# fixtures therefore put TWO files in one run, which is the whole point.
@test "C29b: a RED does not spend a file it never adjudicated (the SAME-RUN wipe)" {
  led="$CC_POSTLAND_DIR/convictions"
  printf '@test "f" { false; }\n' > "$R/tests/alwaysbad.bats"      # A — fails from run 1
  # B — passes run 1, fails from run 2 on, so it enters FAILING one window BEHIND A. That offset is
  # the fixture's entire job: it is what makes run 2 corroborate A while B is still on its first.
  c="$BATS_TEST_TMPDIR/late-counter"
  add_stateful_test latebad "$(printf '#!/bin/bash\nC="%s"\nn=$(cat "$C" 2>/dev/null || echo 0)\nn=$((n+1))\necho "$n" > "$C"\n[ "$n" -le 1 ] && exit 0\nexit 1\n' "$c")"
  push_commit "two suites, one failing a window ahead of the other"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed                  # window 1: A fails (pends), B passes
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                            # precondition, asserted not assumed
  second_window                                    # window 2: A corroborates => RED, B pends
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "red" ]
  run jq -r '.failing | join(",")' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "${output#*alwaysbad}" != "$output" ]          # ...on A, the file it actually adjudicated
  # THE ASSERTION THE UNSCOPED WIPE CANNOT SATISFY: B's row was written seconds earlier by the very
  # loop that produced this verdict, and the verdict said nothing about B.
  [ -f "$led" ]
  run grep -c 'tests/latebad.bats' "$led"
  # SEPARATE STATEMENTS, not `A && B`: errexit exempts every command in a && list except the one
  # after the final &&, so a mid-test `A && B` whose A fails short-circuits and execution CONTINUES
  # — the LHS is dead. Caught by the land's own dead-assertion ratchet on this very diff.
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]                              # B's candidacy SURVIVES the red
  # ...and the other half of "only what it adjudicated": A was convicted, so A's rows ARE spent.
  # Without this the test would also pass if the fix simply stopped clearing anything, which is the
  # stale-row trap conviction_clear's first paragraph exists to prevent.
  run grep -c 'tests/alwaysbad.bats' "$led"
  [ "$output" = "0" ]
}

@test "C29b: the preserved candidacy CONVERGES — B reds in its own second window" {
  # The state assertion above proves the row survives; this proves the row is still WORTH something,
  # which is the claim that actually matters. Each wipe costs a full corpus run to re-earn, and the
  # two files the ledger named most often (handoff-fire-capacity-gate, handoff-fire-completion-push)
  # pended twice, were wiped twice, and were never once convicted.
  printf '@test "f" { false; }\n' > "$R/tests/alwaysbad.bats"
  c="$BATS_TEST_TMPDIR/late-counter"
  add_stateful_test latebad "$(printf '#!/bin/bash\nC="%s"\nn=$(cat "$C" 2>/dev/null || echo 0)\nn=$((n+1))\necho "$n" > "$C"\n[ "$n" -le 1 ] && exit 0\nexit 1\n' "$c")"
  push_commit "two suites, one failing a window ahead of the other"
  t1="$(origin_tree)"
  # CUT_MAX pinned for the same reason test "the SPREAD floor holds" pins it: this fixture takes
  # three sweeps, and a cool-off refusal on an unrelated constant would red it for a reason that has
  # nothing to do with corroboration.
  export CC_POSTLAND_CUT_MAX=99
  run bash "$SUT" --run-if-needed                  # window 1
  second_window                                    # window 2 => RED on A, B pending
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$t1.json"
  [ "$output" = "red" ]                            # precondition
  printf '# retarget\n' >> "$R/tests/alwaysbad.bats"
  push_commit "a new tree, both suites still failing"
  t2="$(origin_tree)"
  run bash "$SUT" --run-if-needed                  # B's SECOND window — A starts over, B converges
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$t2.json"
  [ "$output" = "red" ]                            # unscoped-wipe answer here is `cut`: B re-pends
  run jq -r '.failing | join(",")' "$CC_POSTLAND_DIR/stamps/$t2.json"
  [ "${output#*latebad}" != "$output" ]            # ...and it is B that reds, off the preserved row
}

@test "C29b CONTROL: a GREEN still spends the ledger WHOLE (green on both arms, by design)" {
  # Labelled a CONTROL, not a falsifier, because it passes before the fix as well — its job is to
  # catch an OVER-SCOPED one. The asymmetry is the entire argument: the fix must preserve on a red
  # and must NOT preserve on a green, and a change that made preservation the default would leave
  # every assertion above green while re-opening the stale-row trap C29 exists to prevent.
  led="$CC_POSTLAND_DIR/convictions"
  c="$BATS_TEST_TMPDIR/window-counter"
  add_stateful_test loadflake "$(printf '#!/bin/bash\nC="%s"\nn=$(cat "$C" 2>/dev/null || echo 0)\nn=$((n+1))\necho "$n" > "$C"\n[ "$n" -le 3 ] && exit 1\nexit 0\n' "$c")"
  push_commit "convicted in window 1, exonerated in window 2"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed                  # window 1 => a candidate row exists
  [ -f "$led" ]                                    # the control's own positive control: it was THERE
  run grep -c 'tests/loadflake.bats' "$led"
  [ "$status" -eq 0 ]                              # separate statements — see the note above
  [ "$output" -ge 1 ]
  second_window                                    # window 2 => GREEN
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "green" ]
  [ ! -f "$led" ]                                  # a real exoneration spends EVERY candidate
}

@test "C29b census: every conviction_clear call site is scoped, or is provably the green" {
  # A CENSUS, which no runtime fixture can be. The three tests above exercise the three verdict
  # branches that exist TODAY; a fourth added later would wipe the pendings again and every one of
  # them would still pass. Sites are named INDIVIDUALLY rather than pattern-guessed, so a genuinely
  # new call site cannot hide among them. Anchored on statement position (`cut_clear; …`), because
  # the same identifier appears in prose in four comments and a substring count would drift with the
  # documentation rather than with the code.
  run grep -c 'cut_clear; conviction_clear' "$SUT"
  [ "$output" = "3" ]                              # hung, green, red — no fourth verdict site
  run grep -c 'cut_clear; conviction_clear "\${CONVICT_PENDED\[@\]' "$SUT"
  [ "$output" = "2" ]                              # the two that adjudicate nothing about a pending
  run grep -c 'cut_clear; conviction_clear  ' "$SUT"
  [ "$output" = "1" ]                              # ...and exactly one bare call: the green
}

@test "C29: a DETERMINISTIC red is never delayed — bash -n convicts in ONE window" {
  # The exemption, and why it is safe: syntax and the whole-tree prelints reproduce BY CONSTRUCTION,
  # so a second window cannot tell them anything and delaying them would only leave a broken trunk
  # broken for another sweep. Only LADDER convictions — the load-attributable ones — are corroborated.
  printf 'if [ ; then\n' > "$R/bad-syntax.sh"
  chmod +x "$R/bad-syntax.sh"
  push_commit "a file that cannot parse"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed                  # ONE sweep only — no second_window here
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "red" ]                            # C29: deterministic reds skip corroboration
  run jq -r '.failing | join(",")' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "${output#*bad-syntax.sh}" != "$output" ]      # ...and the stamp names it
}

@test "C29: CC_POSTLAND_CONVICT=off restores the one-window red (the kill switch)" {
  printf '@test "f" { false; }\n' > "$R/tests/bad.bats"
  push_commit "always fails"
  tree="$(origin_tree)"
  run env CC_POSTLAND_CONVICT=off bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "red" ]                            # one sweep, one verdict — the pre-C29 behaviour
}

@test "C29: the selftest's load-branch guard is LIVE (it must be able to fail)" {
  # Same shape as C19's control, and for the same reason: the guard asserts an ABSENCE, so it is
  # worth nothing unless its pattern can actually match. It is also the pattern that matched ITSELF
  # when first written unanchored — which is why it is anchored to statement position.
  run grep -cE '^[[:space:]]*(if|while|until)[[:space:]].*(loadavg|load1)' "$SUT"
  [ "$output" = "0" ]                              # the runner branches on load NOWHERE
  printf 'f() {\n  while [ "$(load1)" -gt 8 ]; do sleep 15; done\n}\n' > "$BATS_TEST_TMPDIR/bait.sh"
  run grep -cE '^[[:space:]]*(if|while|until)[[:space:]].*(loadavg|load1)' "$BATS_TEST_TMPDIR/bait.sh"
  [ "$output" = "1" ]                              # ...and the pattern DOES catch a quiet-box wait
  # the recorded-for-evidence assignment must stay legal, else the guard forbids the wrong thing
  run grep -cE '^[[:space:]]*load="\$\(load1\)"' "$SUT"
  [ "$output" -ge 1 ]
}

# ── C13 CUT ≠ RED ────────────────────────────────────────────────────────────────────────────
# A TAP with ZERO `not ok` in a non-zero run was TRUNCATED (killed/starved), not failed.
# Stamping it red is a lie with teeth: the red stamp is what deploy-live.sh and ship-land's
# postland_net_live read, so with every run cut NO GREEN STAMP CAN EVER EXIST — deploy-live
# refuses forever and the liveness guard silently reads "not adopted ⇒ trust". (Measured
# 2026-07-26: 4 of the last 5 runner.log verdicts were `failing=tests/ retries=0` — all cuts.)
@test "C13: a TRUNCATED run (non-zero, ZERO not-ok) stamps CUT — not red — and never pages" {
  fake="$BATS_TEST_TMPDIR/bats-cut"
  # NOTE: must answer --version — env_fingerprint() parses it into the stamp's JSON, and a
  # fake that echoes TAP there corrupts the stamp (cost one red test to learn).
  printf '#!/bin/bash\n[ "$1" = --version ] && { echo "Bats 1.13.0"; exit 0; }\nexit 1\n' > "$fake"
  chmod +x "$fake"                                                 # rc=1 with ZERO output
  tree="$(origin_tree)"
  run env CC_POSTLAND_BATS="$fake" bash "$SUT" --run-if-needed
  s="$CC_POSTLAND_DIR/stamps/$tree.json"
  [ -f "$s" ]
  run jq -r '.verdict' "$s"; [ "$output" = "cut" ]               # NOT "red"
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]                          # a cut earns nothing
  [ "$(find "$CC_PAGES_DIR" -name 'postland-red-*' | wc -l | tr -d ' ')" = "0" ]
}

@test "C13 control: a run with a REAL not-ok still stamps RED (the cut path must not swallow it)" {
  fake="$BATS_TEST_TMPDIR/bats-red"
  printf '#!/bin/bash\n[ "$1" = --version ] && { echo "Bats 1.13.0"; exit 0; }\necho "1..1"\necho "not ok 1 boom"\necho "# (in test file tests/ok.bats, line 2)"\nexit 1\n' > "$fake"
  chmod +x "$fake"
  tree="$(origin_tree)"
  # TWO WINDOWS (C29), unlike its C13b sibling above. The difference is the `# (in test file …)`
  # diagnostic this fake emits: it makes the not-ok ATTRIBUTABLE, so classify_failures runs the
  # LADDER and the conviction is load-attributable. C13b's fake omits the diagnostic, takes the
  # `FAILING=("tests/")` sentinel path before the ladder, and so is exempt and still reds in one.
  run env CC_POSTLAND_BATS="$fake" bash "$SUT" --run-if-needed     # C29 window 1 => candidate
  s="$CC_POSTLAND_DIR/stamps/$tree.json"
  [ -f "$s" ]
  run jq -r '.verdict' "$s"; [ "$output" = "cut" ]                 # one window proves nothing
  run env CC_POSTLAND_BATS="$fake" bash "$SUT" --run-if-needed     # C29 window 2 => verdict
  run jq -r '.verdict' "$s"; [ "$output" = "red" ]
}

# ── C13h the zero-not-ok branch must NAME the rc, not just assert "truncated" ────────────────────
# The verdict was never wrong here — a truncated run is a cut, and C13 above pins that. What was
# missing is the CAUSE. Branch (a) returned above the rc ladder that branch (c) has always had, so
# every truncation logged one fixed string and threw the rc away. MEASURED 2026-08-10: nine
# consecutive sweeps logged `zero not-ok in a non-zero run - truncated` with no rc, while the
# runner's own stderr file carried `Killed: 9` twelve times — an EXTERNAL signal death, which is the
# opposite finding from our own bound firing, and the log could not tell them apart. Diagnosing it
# required an lsof against a live run. These two pin the discrimination, not the wording.
@test "C13h: a SIGNAL-KILLED run (rc 137, ZERO not-ok) names the signal — still cut, never red" {
  fake="$BATS_TEST_TMPDIR/bats-sigkill"
  # rc 137 = 128+9: what bash reports when SIGKILL reaps the corpus (a peer, the OOM killer — not us).
  printf '#!/bin/bash\n[ "$1" = --version ] && { echo "Bats 1.13.0"; exit 0; }\nexit 137\n' > "$fake"
  chmod +x "$fake"
  tree="$(origin_tree)"
  run env CC_POSTLAND_BATS="$fake" bash "$SUT" --run-if-needed
  s="$CC_POSTLAND_DIR/stamps/$tree.json"
  [ -f "$s" ]
  run jq -r '.verdict' "$s"; [ "$output" = "cut" ]                 # unchanged: signal death is a cut
  grep -q 'KILLED by signal 9' "$CC_POSTLAND_DIR/runner.log"       # …and the cause is now RECOVERABLE
}

# THE CONTROL, and it is the half that makes the test above mean anything: rc 1 must NOT claim a
# signal. Without this, hardcoding the SIGKILL string into the branch would pass C13h — the exact
# vacuous pass the old fixed message already was.
@test "C13h control: rc 1 with ZERO not-ok names the plain rc — it must NOT invent a signal" {
  fake="$BATS_TEST_TMPDIR/bats-rc1"
  printf '#!/bin/bash\n[ "$1" = --version ] && { echo "Bats 1.13.0"; exit 0; }\nexit 1\n' > "$fake"
  chmod +x "$fake"
  tree="$(origin_tree)"
  run env CC_POSTLAND_BATS="$fake" bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"; [ "$output" = "cut" ]
  # `run` + an explicit status test, NOT a bare `! grep`: bash exempts a negated command from
  # errexit, so `! grep -q …` can never fail a bats test — the assertion would be DEAD and this
  # control, whose entire job is to be able to fail, would be the vacuous pass it exists to catch.
  run grep -q 'KILLED by signal' "$CC_POSTLAND_DIR/runner.log"
  [ "$status" -ne 0 ]                                   # must NOT invent a signal on a plain rc 1
  grep -q 'the run exited 1' "$CC_POSTLAND_DIR/runner.log"
}

# ── C13c the NAME-CARRY branch must ask WHOSE bound fired ────────────────────────────────────────
# The LAST 124-blind site in the SUT, and the twin of C23 one function away. C13's cut guard keys on
# `notok == 0`; the name-carry branch beneath it (C13b — `not ok` present, no `# (in test file …)`)
# then files RED without ever reading rc — so a run OUR OWN bound cut, which happens to carry one
# unattributable `not ok`, is convicted as a reproducible failure of the tree. bats answers with
# exactly TWO codes about the tree (0 = all passed, 1 = something failed); every other code says the
# run could not be MADE, which is the predicate C23 already applies at the retry site (`case $rc in
# 0|1`). MEASURED — this is not hypothetical: runner.log 2026-07-30T06:04:21Z stamped
# `RED 4399852f21c2 failing=tests/ run_s=999 retries=0 flakes=0`, 41 s after its own
# `STALL: no TAP progress for 900s at test 0 — cutting the run`. `retries=0` is the tell that this
# branch returned before the ladder ever ran, and `failing=tests/` is reachable from nowhere else.
# That verdict minted the backlog item "post-land RED: tests/ @ 4399852f21c2" — an item pointing at a
# DIRECTORY, unactionable by construction — and on a run where the bisect DOES decide, red_actions
# passes that culprit to auto_revert, so a loaded box can revert a commit off a run in which nothing
# failed. Same event at 05:47:21Z (9586f1ac51f5); a third stall at 06:25:03Z landed GREEN on its
# requeue — the tree was fine throughout.
# THE DISCRIMINATING CONTROL IS ALREADY IN THIS SUITE and must stay green: "C13b: a not-ok with NO
# file diagnostic stays RED and carries the test NAME" drives the byte-identical TAP at rc 1, where
# bats IS speaking about the tree. rc is the only axis between the two, which is exactly the fix.
@test "C13c: an unattributable not-ok in a run OUR OWN bound cut is never a RED" {
  fake="$BATS_TEST_TMPDIR/bats-stallcut"
  # One unattributable `not ok` (no file diagnostic ⇒ the name-carry branch), then WEDGES — so the
  # stall watcher is the only thing that can end the run and rc is OURS (124), never bats' verdict.
  # sleep 30, not 600: the stall bound below cuts at ~4s, so anything past that is pure headroom —
  # and this fixture's lifetime is also the BOUND on a leak. If the corpus shape ever lets
  # classify_hang map a suspect, confirm_hang re-runs this same fake under FILE_TO (300s); an
  # orphaned grandchild would hold the outer bats TAP fd for exactly as long as the sleep.
  printf '#!/bin/bash\n[ "$1" = --version ] && { echo "Bats 1.13.0"; exit 0; }\necho "1..1"\necho "not ok 1 boom"\nsleep 30\n' > "$fake"
  chmod +x "$fake"
  tree="$(origin_tree)"
  run env CC_POSTLAND_BATS="$fake" POSTLAND_STALL_S=3 POSTLAND_STALL_POLL_S=1 \
      bash "$SUT" --run-if-needed
  s="$CC_POSTLAND_DIR/stamps/$tree.json"
  [ -f "$s" ]
  # cut and hung are BOTH legitimate landings for "our bound fired" (classify_hang decides between
  # them on whether the suspect maps and re-wedges alone). The invariant this test pins is the one
  # the defect broke: it is not a RED, and it never files the `tests/` sentinel.
  run jq -r '.verdict' "$s"; [ "$output" != "red" ]
  [ "$(pages_n)" = "0" ]                                   # C10: pages are RED-only
  run grep -c 'failing=tests/' "$CC_POSTLAND_DIR/runner.log"
  [ "$output" = "0" ]
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]                   # a non-verdict earns nothing either
}

# ── C13 a CUT stamp is a DIAGNOSTIC, never a verdict ────────────────────────────
# c605a2e correctly reclassified signal-death as CUT rather than RED, and stamps
# `cut` for diagnosability. But C5's abstain keyed on stamp EXISTENCE, so the very
# next sweep abstained and the tree was NEVER re-verified — is-green stayed false,
# which drives ship-land to call the whole net INERT and degrade gates scoped→FULL.
# ASSERTION FORM: bats runs under errexit, where a non-final `[[ ]]`/`!`/`A && B` is
# errexit-EXEMPT and therefore DEAD. Everything below is a live `[ ]` or `run` + `[ ]`.

@test "C13: a cut tree is RETRIED on the next sweep, never abstained as already-stamped" {
  b="$(stub_bats killed "printf '1..3\nok 1 a\n'; exit 137")"
  export CC_POSTLAND_BATS="$b"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed                        # sweep 1 → the cut
  [ "$status" -eq 0 ]
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                                  # trunk's diagnostic stamp is kept
  run bash "$SUT" --run-if-needed                        # sweep 2 → MUST re-run
  [ "$status" -eq 0 ]
  [ "$(idl_last '.reason')" != "already-stamped" ]       # THE regression: it stranded here
  [ "$(pages_n)" = "0" ]                                 # a cut is still never a RED page
}

@test "C13: a REAL verdict (green/red) still abstains — the fix must not disable C5" {
  run bash "$SUT" --run-if-needed                        # real bats → green
  [ "$status" -eq 0 ]
  before="$(stamps_n)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ "$(stamps_n)" = "$before" ]                          # C5 intact: no second verification
  [ "$(idl_last '.reason')" = "already-stamped" ]
}

@test "C13: after CUT_MAX consecutive cuts an HONEST page is written, then the box cools off" {
  b="$(stub_bats killed "printf '1..3\nok 1 a\n'; exit 137")"
  export CC_POSTLAND_BATS="$b" CC_POSTLAND_CUT_MAX=1
  run bash "$SUT" --run-if-needed
  [ "$(cut_pages_n)" = "1" ]
  p="$(find "$CC_PAGES_DIR" -name 'postland-cut-*.page' | head -1)"
  head -1 "$p" | grep -qE '^[0-9]+$'                     # page protocol: line 1 is an epoch
  grep -q 'NOT a test failure' "$p"
  run grep -c '^failing:' "$p"
  [ "$output" = "0" ]                                    # it never claims a named failing test
  run bash "$SUT" --run-if-needed                        # a hostile box is not re-fed every tick
  [ "$status" -eq 0 ]
  [ "$(idl_last '.reason')" = "cut-cooloff" ]
}

@test "C13: a green after cuts clears the streak and the standing cut page" {
  b="$(stub_bats killed "printf '1..3\nok 1 a\n'; exit 137")"
  # CUT_COOLOFF=0 so the streak still PAGES at CUT_MAX but the next sweep is not deferred —
  # this test is about a green superseding a cut, not about the cool-off (covered above).
  export CC_POSTLAND_CUT_MAX=1 CC_POSTLAND_CUT_COOLOFF=0
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed
  [ "$(cut_pages_n)" = "1" ]
  run bash "$SUT" --run-if-needed                        # real bats now → a genuine green
  [ "$status" -eq 0 ]
  tree="$(origin_tree)"
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "green" ]                                # the cut stamp is superseded
  [ "$(cut_pages_n)" = "0" ]                             # standing cut page cleared
  [ ! -f "$CC_POSTLAND_DIR/cuts" ]                       # streak reset
}

# The entry gate is not the only place the stamp is consulted: C12's requeue loop asks the same
# question about the tree the target MOVED to, and asked it by EXISTENCE. Fixing only the gate
# leaves the second actuator keyed on the old predicate — the moved head is dropped unverified
# for that sweep. Enumerate call sites, not mechanisms.
@test "C13: the REQUEUE loop is verdict-aware too — a move onto a CUT tree is still verified" {
  base_head="$(origin_head)"
  # 1. a REAL cut stamp for the moved-to tree, written by the real producer (never hand-forged)
  echo moved >> "$R/foo.sh"
  push_commit "the superseding commit"
  moved_head="$(origin_head)"; moved_tree="$(origin_tree)"
  b="$(stub_bats killed "printf '1..3\nok 1 a\n'; exit 137")"
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$moved_tree.json"
  [ "$output" = "cut" ]                                  # precondition, asserted not assumed
  # 2. rewind origin so the sweep STARTS on the unstamped base and the move lands on the cut tree
  git -C "$R" push -qf origin "$base_head:main"
  rm -f "$CC_POSTLAND_DIR/cuts"                          # isolate the loop from the cool-off path
  # 3. a stub that moves origin/main DURING the run — the C12 race, reproduced by the producer
  b2="$(stub_bats mover "git -C '$R' push -qf origin '$moved_head:main' >/dev/null 2>&1
printf '1..1\nok 1 p\n'")"
  CC_POSTLAND_BATS="$b2" run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ "$(origin_head)" = "$moved_head" ]                   # the move really happened mid-sweep
  # THE regression: an existence-keyed break leaves this "cut" — the head lands unverified.
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$moved_tree.json"
  [ "$output" = "green" ]
}

# The control above emits a `# (in test file …)` diagnostic, so it exercises the ATTRIBUTED
# path and leaves the boundary itself unguarded. This is the boundary: `not ok` present,
# diagnostic ABSENT. Both cases reach classify_failures with an EMPTY `pairs`, so a predicate
# keyed on attribution ("no failing FILE ⇒ no verdict") collapses them and silently discards a
# real regression — no stamp, no page, the tree re-verified forever. Only a predicate keyed on
# the `not ok` COUNT keeps them apart. Guarding it here is the point: the collapse was live
# once, and nothing in the suite would have caught its return.
@test "C13b: a not-ok with NO file diagnostic stays RED and carries the test NAME" {
  fake="$BATS_TEST_TMPDIR/bats-nodiag"
  printf '#!/bin/bash\n[ "$1" = --version ] && { echo "Bats 1.13.0"; exit 0; }\necho "1..1"\necho "not ok 1 boom"\nexit 1\n' > "$fake"
  chmod +x "$fake"                                    # a NAMED failure, with nothing to attribute it to
  tree="$(origin_tree)"
  run env CC_POSTLAND_BATS="$fake" bash "$SUT" --run-if-needed
  s="$CC_POSTLAND_DIR/stamps/$tree.json"
  [ -f "$s" ]                                         # NOT the cut path: a stamp must exist
  run jq -r '.verdict' "$s"; [ "$output" = "red" ]    # C10 — a named failure is a verdict
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]              # C10 — last-green NOT advanced
  [ "$(pages_n)" = "1" ]                              # C10 — it PAGES (the swallow paged nothing)
  # and the page is actionable: TAP named the test, so the page must not say "(unattributed)".
  grep -q 'boom' "$CC_PAGES_DIR"/postland-red-*.page || false
}

# C13c above retires the case where OUR OWN bound cut the run (rc 124) — that is never a RED now.
# This is the case that SURVIVES it: rc 1, so bats really did fail, with a `not ok` it cannot pin to
# a file. C13b already guards that verdict and the PAGE it writes. But the page is TRANSIENT — the
# green branch of run_target deletes every postland-red-*.page — while the backlog item OUTLIVES the
# run, and the item was the one dropping the name, minting the bare sentinel "post-land RED: tests/
# @ <sha>". Not hypothetical: item 7ddd2c171e43 carried exactly that title, and by the time a worker
# opened it the 06:42 green had already deleted the page holding the only copy of the name — so the
# item was unactionable BY CONSTRUCTION. A guard on the page alone cannot catch that: the page passes
# and the durable record rots anyway. Pin the name into the DURABLE artifact.
@test "C13d: the DURABLE backlog title carries the test NAME, not just the sentinel" {
  fake="$BATS_TEST_TMPDIR/bats-nodiag"
  printf '#!/bin/bash\n[ "$1" = --version ] && { echo "Bats 1.13.0"; exit 0; }\necho "1..1"\necho "not ok 1 boom"\nexit 1\n' > "$fake"
  chmod +x "$fake"                                    # a NAMED failure, with nothing to attribute it to
  run env CC_POSTLAND_BATS="$fake" bash "$SUT" --run-if-needed
  [ -f "$REC/cc-backlog.argv" ]                       # the RED path did reach the backlog
  # The bare sentinel is what shipped before and is NOT enough: the name must ride along, in the
  # same `file::test` shape the page and the notify already use.
  grep -q 'post-land RED: tests/::boom @' "$REC/cc-backlog.argv"
  # ...and the durable item must AGREE with the transient page, so the two cannot drift apart.
  grep -q 'failing: tests/::boom' "$CC_PAGES_DIR"/postland-red-*.page
}

# ── C13e–C13g: EVERY reproducible failure is filed, ONCE (backlog fa58a8151140) ──────────────────
# C13d above pinned that the ONE item carries a NAME. It could not see the two defects around it,
# because a single-failure fixture cannot distinguish "files the failures" from "files the FIRST
# failure", and a single-run fixture cannot distinguish "one item" from "one item PER RUN":
#   · red_actions filed FAILING[0] and nothing else. FAILING is corpus/TAP-ordered, so a suite that
#     never sorts first was unfilable BY CONSTRUCTION. Measured over runner.log at the time of the
#     fix: 69 RED runs, 472 failing-suite observations, 69 items, and 38 of 58 distinct suites filed
#     ZERO times. tests/gate-home-isolation.bats was the extreme — 28 appearances, 0 filings, 0 rows
#     in flakes.jsonl (so never a flake correctly withheld, just never looked at).
#   · the title carried the sha and the key was project+title+source, so every sweep minted a NEW
#     item for the same standing red — memory per-event-key-defeats-per-finding-dedupe.
# These three pin the fix from both sides: everything gets filed, and re-filing is idempotent.
# The fixture emits a THREE-file TAP and the failing files are deliberately NOT in the order that
# would let a FAILING[0]-only implementation pass by luck.
multi_red_bats() {  # → $BATS_TEST_TMPDIR/bats-multi: 3 attributed failures; retries convict too
  local f="$BATS_TEST_TMPDIR/bats-multi"
  cat > "$f" <<'STUB'
#!/bin/bash
[ "$1" = --version ] && { echo "Bats 1.13.0"; exit 0; }
# The retry ladder re-runs ONE test (`-f <regex> <file>`). It must PLAN >0 and exit 1, or the
# ladder reads a non-verdict and the file is never convicted at all.
[ "$1" = "-f" ] && { echo "1..1"; echo "not ok 1 replay"; exit 1; }
echo "1..3"
echo "not ok 1 alpha"
echo "# (in test file tests/aaa-sorts-first.bats, line 3)"
echo "not ok 2 bravo"
echo "# (in test file tests/gate-home-isolation.bats, line 4)"
echo "not ok 3 charlie"
echo "# (in test file tests/it2-kitty.bats, line 5)"
exit 1
STUB
  chmod +x "$f"; printf '%s' "$f"
}

@test "C13e: EVERY failing suite is filed, not just the one that sorts first" {
  fake="$(multi_red_bats)"
  # TWO WINDOWS (C29): the fixture's failures are ATTRIBUTED, so they are ladder convictions and
  # window 1 only stamps a cut — which files nothing, so every assertion below would read an absent
  # backlog. The stub is stateless (no run counter), so window 2 presents the identical 3-file TAP.
  run env CC_POSTLAND_BATS="$fake" bash "$SUT" --run-if-needed   # window 1 => candidate, cut
  run env CC_POSTLAND_BATS="$fake" bash "$SUT" --run-if-needed   # window 2 => RED, files them
  [ -f "$REC/cc-backlog.argv" ]
  # The one the old code DID file — the control. If this fails the fixture never reached red_actions.
  grep -q 'post-land RED: tests/aaa-sorts-first.bats::alpha @' "$REC/cc-backlog.argv"
  # THE regression: these two never sort first, so FAILING[0]-only filing dropped them silently.
  grep -q 'post-land RED: tests/gate-home-isolation.bats::bravo @' "$REC/cc-backlog.argv"
  grep -q 'post-land RED: tests/it2-kitty.bats::charlie @' "$REC/cc-backlog.argv"
  # ...and each carries its OWN test name, which is why FAILNAME exists: a shared FAILTEST would
  # have labelled all three "alpha" and made items 2 and 3 point at the wrong test.
  [ "$(grep -c 'post-land RED:' "$REC/cc-backlog.argv")" = "3" ]
}

# The digit trap, pinned as its own case because it fails SILENTLY and selectively. cc-backlog's
# valid_condition() rejects any key containing a digit and REFUSES the whole add (rc 2) — and this
# call site is best-effort, so the refusal prints nowhere. A cond_slug that stripped or passed
# digits through would therefore file 295 of 305 suites and drop exactly the 10 whose names carry
# one (it2-*, iterm2-*, cc-dispatch-v2, subagent-stop-r1, …) — re-creating this bug's own
# invisibility for a different subset. The fixture's third file is one of them ON PURPOSE.
@test "C13f: a digit-bearing suite name still yields a VALID condition key (the silent-drop trap)" {
  fake="$(multi_red_bats)"
  run env CC_POSTLAND_BATS="$fake" bash "$SUT" --run-if-needed   # C29 window 1 => cut, files nothing
  run env CC_POSTLAND_BATS="$fake" bash "$SUT" --run-if-needed   # window 2 => RED, files them
  # Digits are SPELLED OUT, not stripped — so it stays distinct from a hypothetical `it-kitty`.
  grep -q -- '--condition postland-red-it-two-kitty' "$REC/cc-backlog.argv"
  # Every condition passed must satisfy the REAL predicate, read from cc-backlog itself rather than
  # restated here — a copy of the rule could drift from the rule and the test would still pass.
  eval "$(sed -n '/^valid_condition() {/,/^}/p' "$REPO/bin/cc-backlog")"
  # Process substitution, NOT `... | while read`: a piped loop runs in a SUBSHELL, so `n` would be
  # incremented in a child and read back as 0 in the parent — the count assertion below would then
  # fail even on a correct run (memory subshell-erases-the-cleanup-record, same mechanism).
  local k n=0
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    valid_condition "$k" || { echo "cc-backlog would REFUSE: $k"; false; }
    n=$((n + 1))
  done < <(grep -o -- '--condition [a-z0-9-]*' "$REC/cc-backlog.argv" | awk '{print $2}')
  [ "$n" = "3" ]                                   # all three, not just the ones that happen to pass
}

# The dedupe half, driven through the REAL cc-backlog rather than the recording stub: the flag being
# PRESENT proves nothing about whether a second sweep mints a second item. Two runs, two different
# shas, same standing failures — the shape that minted 69 items for the same reds.
@test "C13g: a second RED sweep re-files the SAME items, it does not mint new ones" {
  fake="$(multi_red_bats)"
  export CC_BACKLOG_BIN="$REPO/bin/cc-backlog"        # the real one — the stub cannot dedupe
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  # MANDATORY with the real binary: `cc-backlog add` fires dispatch_kick, which backgrounds
  # `cc-dispatch --decide` — and kick_bin resolves via `command -v`, i.e. the OPERATOR's real
  # dispatcher, which spawns real worker sessions. The sandboxed $HOME does not save us: it only
  # moves the debounce marker, so the kick is never debounced and fires EVERY time. A test that
  # spawns live agents is not a test.
  export CC_BACKLOG_KICK=off
  # TWO SWEEPS PER RED (C29) — and this test's whole subject is what a SECOND red sweep does, so be
  # explicit that the pairs below are windows, not repeats. A ladder conviction files nothing until
  # a later sweep re-convicts it, so each "sweep" this test reasons about is now a window PAIR.
  run env CC_POSTLAND_BATS="$fake" bash "$SUT" --run-if-needed   # window 1 => candidate, cut
  run env CC_POSTLAND_BATS="$fake" bash "$SUT" --run-if-needed   # window 2 => RED, files 3
  [ -f "$CC_BACKLOG_FILE" ]
  local after1; after1="$(jq -r 'select(.event=="add").id' "$CC_BACKLOG_FILE" | sort -u | wc -l | tr -d ' ')"
  [ "$after1" = "3" ]                                 # one per failing suite, not one per run
  # A real tree change is REQUIRED, not decoration: push_commit runs `git commit` with no --allow-empty,
  # so an unchanged fixture exits 1 ("nothing to commit") and the test dies here having proved only
  # the first sweep. The second sweep is the whole point — a new sha AND a new tree, so the stamp
  # gate does not short-circuit on `already-stamped`.
  echo second > "$R/second-fixture"
  push_commit second                                  # a NEW sha ⇒ a new run over the same red set
  # Window 1 again on the NEW tree: the verdict above spent the candidate ledger (conviction_clear
  # runs beside cut_clear at every verdict), so this red has to earn its two windows from scratch —
  # which is exactly the property that keeps a stale row from convicting off one experiment.
  run env CC_POSTLAND_BATS="$fake" bash "$SUT" --run-if-needed   # window 1 => cut
  run env CC_POSTLAND_BATS="$fake" bash "$SUT" --run-if-needed   # window 2 => RED, re-files the same 3
  local after2; after2="$(jq -r 'select(.event=="add").id' "$CC_BACKLOG_FILE" | sort -u | wc -l | tr -d ' ')"
  [ "$after2" = "3" ]                                 # THE regression: was 6 (a fresh item per sweep)
  # And the reason it holds: identity is the CONDITION, which carries no sha/count/timestamp.
  run jq -r 'select(.event=="add").condition' "$CC_BACKLOG_FILE"
  [ -n "$output" ]
  # `! grep -q`, NOT `grep -qv`: with -v a MULTI-LINE input passes as long as ONE line is clean, so
  # it would have green-lit a set where two keys were fine and the third carried a sha. Measured,
  # not assumed — `printf 'aa\nbb2\n' | grep -qv '[0-9]'` exits 0.
  ! printf '%s' "$output" | grep -q '[0-9]' || { echo "a condition key carries a digit: $output"; false; }
}

# ── C13i: the SHA in a per-entry title is per-entry too (backlog 8740c03e428c) ───────────────────
# C13e pins that every failing suite gets filed and C13d that each carries its OWN test name. The
# third field — the SHA — was still the scalar `$c12`, a verdict do_bisect reached for FAILING[0]
# ALONE, stamped onto every title. So a non-primary row named a commit where its own suite is GREEN:
# item 99df8fdb4fda read '@ f60b7ca220ee', bisected for tests/boot-resume-launch.bats, while
# tests/boundary-handoff.bats passes at that sha. The durable row outlives the page, so that title is
# the whole of what a worker gets — and it points them at `git revert` on an innocent commit.
#
# WHY THIS FIXTURE IS NOT multi_red_bats: with no last-green, do_bisect ABSTAINS, `culprit` falls
# back to the target, and `$c12` and `sha12 $sha` are the SAME STRING — so every assertion below
# would pass against the unfixed subject. The bug is only observable where the bisect CONVICTS a sha
# the target is not, which needs three things this stub buys and multi_red_bats cannot: a green
# window to set the floor, a marker commit to converge on, and an innocent commit on top so culprit
# != target. `[ -f BAD ]` is the same tree-driven discriminator stub_bats_marker uses one suite over
# (tests/postland-verify-bisect-bound.bats), because the probe's cwd IS the bisect cell.
bisectable_multi_red_bats() {   # green until BAD appears, then the 3-file attributed TAP
  local f="$BATS_TEST_TMPDIR/bats-bisectable"
  cat > "$f" <<'STUB'
#!/bin/bash
[ "$1" = --version ] && { echo "Bats 1.13.0"; exit 0; }
# The floor and every interior probe answer from the TREE, not from a counter: this is what makes
# the walk decidable instead of red-everywhere (which bisect_floor_ok correctly refuses, B13).
if [ ! -f BAD ]; then echo "1..1"; echo "ok 1 fine"; exit 0; fi
# The retry ladder re-runs ONE test (`-f <regex> <file>`) and must PLAN >0 and exit 1, or the ladder
# reads a non-verdict and the file is never convicted at all.
[ "$1" = "-f" ] && { echo "1..1"; echo "not ok 1 replay"; exit 1; }
echo "1..3"
echo "not ok 1 alpha"
echo "# (in test file tests/aaa-sorts-first.bats, line 3)"
echo "not ok 2 bravo"
echo "# (in test file tests/gate-home-isolation.bats, line 4)"
echo "not ok 3 charlie"
echo "# (in test file tests/it2-kitty.bats, line 5)"
exit 1
STUB
  chmod +x "$f"; printf '%s' "$f"
}

@test "C13i: a NON-PRIMARY failing entry names the TARGET sha, not the primary's bisected culprit" {
  fake="$(bisectable_multi_red_bats)"
  export CC_POSTLAND_BATS="$fake"
  # Cuts accumulate across the four windows below; the cool-off would refuse the last one for a
  # reason that has nothing to do with this test's subject.
  export CC_POSTLAND_CUT_MAX=99

  # THE SUITES THE TAP NAMES MUST EXIST IN THE TREE, and this is not fixture decoration — it is the
  # difference between a walk and a non-verdict. do_bisect writes a runner whose first line is
  # `[ -f <file> ] || exit 125`, and 125 is git's "cannot test this commit", so with the file absent
  # EVERY probe abstains and `bisect run` returns no first-bad (measured: why=no-first-bad steps=1,
  # both arms then agreeing on the target and this test passing vacuously against the unfixed
  # subject). They must exist at the FLOOR too, or bisect_floor_ok takes its "the file did not exist
  # at the last-green" branch and skips the confirmation the control below reads. Contents are
  # irrelevant — CC_POSTLAND_BATS answers for every suite in this fixture.
  local s
  for s in aaa-sorts-first gate-home-isolation it2-kitty; do
    printf '@test "%s" { true; }\n' "$s" > "$R/tests/$s.bats"
  done
  push_commit "the suites the TAP names"

  run bash "$SUT" --run-if-needed                     # no BAD yet => GREEN, sets the bisect floor
  [ "$status" -eq 0 ]
  [ -f "$CC_POSTLAND_DIR/last-green" ]                # control: the floor exists, so a walk is possible

  touch "$R/BAD"; push_commit "the culprit"           # first bad commit
  culprit="$(origin_head)"
  echo innocent > "$R/innocent"; push_commit "innocent, on top"   # target != culprit
  target="$(origin_head)"
  culprit12="${culprit:0:12}"; target12="${target:0:12}"
  # THE VACUITY GUARD. If these were equal the two arms of the fix render one string and every
  # assertion below passes against the unfixed subject — the fixture, not the code, would be what
  # made the test green.
  [ "$culprit12" != "$target12" ]

  run bash "$SUT" --run-if-needed                     # window 1 => candidate, cut
  second_window                                       # window 2 => RED, files all three

  [ -f "$REC/cc-backlog.argv" ]
  # CONTROL that the bisect really CONVICTED rather than abstaining: the page is state-keyed on the
  # culprit, so its existence under the culprit's sha — not the target's — is the walk's own verdict.
  # Without this the test could pass on a run where do_bisect gave up and both arms agreed by luck.
  [ -f "$CC_PAGES_DIR/postland-red-$culprit12.page" ]
  grep -q 'bisected from last-green' "$CC_PAGES_DIR/postland-red-$culprit12.page"

  # The PRIMARY keeps the bisect's answer — the fix must not blanket-replace the sha, or it would
  # throw away the one attribution that was correct all along.
  grep -q "post-land RED: tests/aaa-sorts-first.bats::alpha @ $culprit12" "$REC/cc-backlog.argv"
  # THE REGRESSION, both non-primary entries: pre-fix these carried $culprit12 — a sha bisected for a
  # different suite entirely.
  grep -q "post-land RED: tests/gate-home-isolation.bats::bravo @ $target12" "$REC/cc-backlog.argv"
  grep -q "post-land RED: tests/it2-kitty.bats::charlie @ $target12" "$REC/cc-backlog.argv"
  # ...stated once more as a COUNT, because the two greps above would both pass if the fix had
  # replaced every sha with the target: exactly one row may name the culprit.
  [ "$(grep -c "post-land RED:.*@ $culprit12" "$REC/cc-backlog.argv")" = "1" ]
  [ "$(grep -c "post-land RED:.*@ $target12" "$REC/cc-backlog.argv")" = "2" ]
}

# ── C32: ONE RED EPISODE, ONE LEASE — every mint site JOINS the suite's condition group ─────────
# C13e-g above cover ONE of this file's four mint sites: red_actions' per-entry loop, which is
# condition-keyed and therefore idempotent and lease-visible. The other three (AUTO-REVERT
# <outcome>, AUTO-REVERT INERT, HUNG) were title-keyed on a sha or a tree — correct for keeping one
# ATTEMPT per row, and silently fatal for dedupe, because a title key shares no field with the RED
# row naming the same suite. Filed as 4f657ed3e064 off a live incident: fd458e142ddc ("post-land
# RED") and 28740c313840 ("AUTO-REVERT FAILED"), tests/cc-backlog-venue.bats @ 508c2b9db0ea, one
# suite, two rows, both dispatched, two workers, a rebase collision.
#
# THE FIX IS `link`, NOT `add --condition` — see file_linked's header in the SUT for why the
# obvious spelling would delete the second row's content instead of deduping it. The property
# therefore splits in two, and NEITHER half is sufficient alone:
#   · the CALL SITES emit the pair (add → link) — pinned below off a live SUT run;
#   · the LINK ACTUALLY ARMS THE LEASE — pinned below against the REAL cc-backlog, with the
#     unlinked state as the control, because a refusal proves nothing until the same claim is shown
#     to SUCCEED without the link (memory: control-must-be-able-to-fail).
@test "C32: a HUNG item is JOINED to its suite's condition group, not merely filed" {
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  echo hf > "$R/hung-fixture"; push_commit "hung fixture"
  stub_bats_mode hung
  POSTLAND_SUITE_TIMEOUT_S=4 POSTLAND_FILE_TIMEOUT_S=4 run bash "$SUT" --run-if-needed
  [ -f "$REC/cc-backlog.argv" ]
  grep -q 'post-land HUNG' "$REC/cc-backlog.argv"     # control: the mint site was reached at all
  # THE CLAIM — and the key is DERIVED, never a literal. The page is the producer's own record of
  # which suite wedged, and cond_slug is read out of the SUT rather than restated here: a copy of
  # the rule could drift from the rule and this test would still pass (the C13f pattern, and memory
  # sibling-auditors-must-share-the-state-model).
  local page wedged expect
  page="$(find "$CC_PAGES_DIR" -name 'postland-hung-*.page' | head -1)"
  [ -n "$page" ]
  wedged="$(sed -n 's/^wedged:  \([^ ]*\) at .*/\1/p' "$page" | head -1)"
  [ -n "$wedged" ]                                    # control: the page names a suite...
  eval "$(sed -n '/^cond_slug() {/,/^}/p' "$REPO/scripts/postland-verify.sh")"
  expect="$(cond_slug "$wedged")"
  grep -qF "link stubbedid00 --condition $expect" "$REC/cc-backlog.argv"
  # ...and the link is aimed at the id the ADD returned, which is the only thing making it reach
  # the row that was just filed. A link naming some other id would join the wrong work.
  grep -q 'post-land HUNG.*stubbedid00\|^add .*post-land HUNG' "$REC/cc-backlog.argv"
}

@test "C32: two rows, one condition — the SECOND claim is REFUSED (the lease the link arms)" {
  # The REAL binary, not the recording stub: the stub cannot fold a ledger, so it can record the
  # link and prove nothing about what the link DOES. CC_BACKLOG_KICK=off is mandatory with the real
  # one — `add` fires dispatch_kick, which resolves the OPERATOR's cc-dispatch via `command -v` and
  # spawns live worker sessions (the C13g warning, same mechanism).
  local B="$REPO/bin/cc-backlog" me red arv
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/lease.jsonl" CC_BACKLOG_KICK=off
  me="$(hostname -s 2>/dev/null || hostname)-$$"      # a claimer this box reads as LIVE (kill -0 $$)
  # The incident's two rows, filed exactly as their producers file them.
  red="$("$B" add --title 'post-land RED: tests/cc-backlog-venue.bats::cloud claim @ 508c2b9db0ea' \
           --condition postland-red-cc-backlog-venue \
           --project claude-infrastructure --source postland-verify)"
  arv="$("$B" add --title 'post-land AUTO-REVERT FAILED(step=revert rc=90): tests/cc-backlog-venue.bats @ 508c2b9db0ea (revert none)' \
           --project claude-infrastructure --source postland-verify)"
  [ -n "$red" ] && [ -n "$arv" ] && [ "$red" != "$arv" ] || false # control: two ids, as the incident had
  "$B" claim "$red" --by "$me"                             # worker 1 takes the RED row
  # ── THE CONTROL: unlinked, the second row dispatches too. This is the state that SHIPPED, and
  # without it the refusal below could be produced by anything (a done-latch, a row lease, a
  # malformed id) and would still read as a pass.
  run "$B" claim "$arv" --by "$me"
  [ "$status" -eq 0 ]
  "$B" reopen "$arv" --force >/dev/null                    # put it back for the real question
  # ── THE CLAIM: joined to the RED row's condition, guard (6) sees one piece of work with a live
  # holder and declines to mint a second worker onto it.
  "$B" link "$arv" --condition postland-red-cc-backlog-venue >/dev/null
  run "$B" claim "$arv" --by "$me"
  [ "$status" -eq 4 ]
  [[ "$output" == *"verdict=sibling-held"* ]] || false
  [[ "$output" == *"$red"* ]] || false                     # ...and it NAMES the row holding it
  # A refused claim must append NOTHING — the item stays open and the next dispatch pass retries
  # once the sibling releases. A refusal that also consumed the row would trade a duplicate worker
  # for a lost one.
  run jq -r --arg i "$arv" 'select(.id==$i and .event=="claim") | .id' "$CC_BACKLOG_FILE"
  [ "$(printf '%s\n' "$output" | grep -c .)" = "1" ]       # the CONTROL's claim only, not a second
}

# ── NO PATH NORMALIZATION: the corpus runs in the environment being gated (settled 2026-07-29) ──
# The inverse of what these tests used to assert. A prepend lived in the SUT (5abe5934) and turned
# a minimal-PATH red green — by running the corpus in an environment that never occurs. This gate's
# problem is false SIGNAL, so faking the environment costs more than it buys: it hides the case
# where the ARTIFACT UNDER TEST depends on ambient PATH. That case was real (deploy-parity-assert.sh
# reported NOPATH, a property of the CALLER's environment, as deployment DRIFT), and normalization
# would have kept it invisible. Suites own their hermeticity; the gate owns nothing but the truth.
# These lock the absence in, so the prepend cannot quietly return.

@test "the SUT does not rewrite PATH — no prepend, no wholesale override" {
  # No assignment to PATH anywhere outside a comment: the corpus inherits the caller's PATH.
  run bash -c "grep -vE '^[[:space:]]*#' '$SUT' | grep -nE '^[[:space:]]*(export )?PATH=' || true"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a daemon-like PATH reaches bats UNCHANGED (the environment is the subject, not a variable)" {
  # Drive the real SUT far enough to prove it never edits PATH, by comparing what a child sees.
  before="/usr/bin:/bin"
  run env -i HOME="$HOME" PATH="$before" TERM=dumb bash -c \
    "grep -vE '^[[:space:]]*#' '$SUT' | grep -E '^[[:space:]]*(export )?PATH=' >/dev/null && echo MUTATES || printf '%s' \"\$PATH\""
  [ "$status" -eq 0 ]
  [ "$output" = "$before" ]
}

@test "the anti-regression rationale is present, not just the absence (so it cannot be re-added blind)" {
  grep -q 'DELIBERATELY DOES NOT NORMALIZE PATH' "$SUT" || false
  grep -q 'Do not re-add a PATH prepend here' "$SUT"
}

# ── C15–C17 HUNG: the one state carved OUT of the cut population ────────────────
# C13 above settled "a truncated run is not a RED". These settle the split INSIDE that
# population: a MACHINE event (peer pkill / OOM / starvation) stays a CUT — unactionable,
# retried, cooled off — while a suite that genuinely never RETURNS, and whose suspect file
# wedges AGAIN alone on a pristine checkout, is a proven property of the TREE. Retrying is
# the right answer to the first and the one answer guaranteed never to clear the second.
# A stub `bats` on the SUT's own $CC_POSTLAND_BATS seam gives the death SHAPES exactly; the
# real signal (a genuine SIGKILL) and the real bound (a genuine timeout(1) expiry) are NOT
# stubbed, and the first test is a positive control against the REAL producer.
stub_bats_mode() {   # $1 = mode; writes $BATS_TEST_TMPDIR/stub-bats and exports the seam
  cat > "$BATS_TEST_TMPDIR/stub-bats" <<'STUB'
#!/bin/bash
case "$1" in --version) echo "Bats 0.0.0-stub"; exit 0 ;; --count) echo 1; exit 0 ;; esac
case "${PV_STUB_MODE:-}" in
  # the plan line and then nothing — only the SUT's own bound can end it
  hung)     echo "1..3"; sleep 60 ;;
  # a hang whose TAP ALSO carries a job-control line — the C16 ordering case. On some
  # bats/shell combinations timeout(1)'s own SIGTERM makes the hang print exactly this,
  # so a signal-first ladder would misfile every such hang as a machine cut.
  hungsig)  echo "1..3"; echo "bats: line 336: 42124 Terminated: 15   exec bats-exec-suite"; sleep 60 ;;
  # planned, completed nothing, exit 1, NOBODY signalled it (the no-timeout leg)
  stall)    echo "1..3"; exit 1 ;;
  # wedges as a SUITE, completes as a FILE => the confirm re-run must exonerate it.
  # v2 passes the corpus as an explicit FILE LIST, never the literal `tests/` (C18), so the
  # discriminator is ARGUMENT COUNT: >1 path = the suite run, exactly 1 = the confirm re-run.
  # Keying on "tests/" was keying on the v1 invocation SHAPE, and it silently stopped matching
  # the producer — the stub then completed instantly and the hang it exists to fake never
  # happened. A fixture is a claim about the real producer; when the producer changes shape the
  # fixture must be re-derived from it, not left passing for a new reason.
  flaky)    if [ "$#" -gt 1 ] || [ "${1:-}" = "tests/" ]; then echo "1..3"; sleep 60; else echo "1..1"; echo "ok 1 a"; exit 0; fi ;;
  # bats OUTLIVED the child it lost: rc is a plain 1, the only trace is the shell's
  # job-control line. This is the literal 9c5d0ba74e79 observation.
  survivor) echo "1..3"; echo "ok 1 a"
            echo "bats: line 336: 42124 Killed: 9   exec bats-exec-suite"; exit 1 ;;
  # the SAME words, but as a TEST'S OWN captured output (`# `-prefixed) — this repo has
  # reaper suites that print exactly this, and it must NOT read as a signal.
  reaper)   echo "1..3"; echo "ok 1 a"; echo "# Killed: 9"; exit 1 ;;
  *)        echo "1..3"; echo "ok 1 a"; exit 1 ;;
esac
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/stub-bats"
  export CC_POSTLAND_BATS="$BATS_TEST_TMPDIR/stub-bats" PV_STUB_MODE="$1"
}
hung_pages_n() { find "$CC_PAGES_DIR" -name 'postland-hung-*.page' 2>/dev/null | wc -l | tr -d ' '; }

@test "C15/C16 REAL hang (real bats, real timeout): HUNG naming the file, not a CUT" {
  run bash "$SUT" --run-if-needed                  # green baseline
  [ "$status" -eq 0 ]
  green="$(cat "$CC_POSTLAND_DIR/last-green")"
  printf '@test "wedge" { sleep 60; }\n' > "$R/tests/wedge.bats"
  push_commit "a suite that wedges"
  tree="$(origin_tree)"
  POSTLAND_SUITE_TIMEOUT_S=6 POSTLAND_FILE_TIMEOUT_S=6 run bash "$SUT" --run-if-needed
  s="$CC_POSTLAND_DIR/stamps/$tree.json"
  [ -f "$s" ]
  run jq -r '.verdict' "$s"; [ "$output" = "hung" ]                 # C15
  run jq -r '.failing[0]' "$s"; [ "$output" = "tests/wedge.bats" ]  # names the FILE that wedged
  [ "$(cat "$CC_POSTLAND_DIR/last-green")" = "$green" ]             # C15: last-green frozen
  [ "$(pages_n)" = "0" ]                                            # C13: NOT a RED
  [ "$(cut_pages_n)" = "0" ]                                        # ...and NOT a machine cut
  [ -n "$(find "$CC_PAGES_DIR" -name 'postland-hung-wedge-*.page' 2>/dev/null)" ]
  # POSITIVE CONTROL on the REAL producer: real bats, real wedge, real timeout(1) — the bound
  # genuinely fires rather than the 124 arriving from somewhere in the fixture. It runs against
  # the fixture repo's own copy of the suite, because the verifier's cell no longer outlives the
  # run (C7); pointing it at that path would have made the control assert teardown, not wedging.
  tb="$(command -v timeout || command -v gtimeout || echo /opt/homebrew/bin/timeout)"
  run env -u TMPDIR "$tb" -k 2 4 bats "$R/tests/wedge.bats"
  [ "$status" -eq 124 ]
}

@test "C16: rc 124 outranks a job-control line in the TAP — hang, not cut" {
  # THE ORDERING GUARD. timeout(1) SIGTERMs the whole group, so on some bats/shell
  # combinations a hang's own TAP carries `Terminated: 15`; a signal-first ladder would
  # then misfile every hang as a machine cut and send it to the wrong owner forever.
  # Asserted as a CODE property: this TAP has both, and rc 124 must win. Swap the two
  # branches in classify_hang and this test goes red (verdict becomes "cut").
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  echo hsf > "$R/hungsig-fixture"; push_commit "hang that also prints a signal line"
  tree="$(origin_tree)"
  stub_bats_mode hungsig
  POSTLAND_SUITE_TIMEOUT_S=4 POSTLAND_FILE_TIMEOUT_S=4 run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "hung" ]
  page="$(find "$CC_PAGES_DIR" -name 'postland-hung-*.page' | head -1)"
  [ -n "$page" ]
  grep -q 'timeout:4s' "$page"                      # attributed to OUR bound, not to sig:15
}

@test "STALL bound: a wedge is cut on TAP silence in seconds, not on the wall backstop" {
  # The primary bound is PROGRESS (POSTLAND_STALL_S), not duration. Discriminator vs the old
  # wall-only code: the wall here is 60s, so ONLY the stall path can produce a verdict this fast —
  # run_s in the stamp must be well under the wall. Same hung classification, same named file.
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  printf '@test "wedge" { sleep 60; }\n' > "$R/tests/wedge.bats"
  push_commit "a suite that wedges (stall path)"
  tree="$(origin_tree)"
  POSTLAND_STALL_S=3 POSTLAND_STALL_POLL_S=1 POSTLAND_SUITE_TIMEOUT_S=60 POSTLAND_FILE_TIMEOUT_S=6 \
    run bash "$SUT" --run-if-needed
  s="$CC_POSTLAND_DIR/stamps/$tree.json"
  [ -f "$s" ]
  run jq -r '.verdict' "$s"; [ "$output" = "hung" ]
  run jq -r '.failing[0]' "$s"; [ "$output" = "tests/wedge.bats" ]
  run jq -r '.run_s' "$s"; [ "$output" -lt 30 ] || false   # the WALL (60s) provably did not fire
}

@test "STALL bound: slow-but-PROGRESSING corpus is never cut (non-regression control)" {
  # The other half of the split the stall bound exists for: each result lands within the stall
  # window, so progress keeps resetting the clock and the run finishes GREEN even though its total
  # wall exceeds several stall windows. (Passes pre-change too — this is the control that pins the
  # stall bound to STALLS; the discriminating half is the run_s assertion above.)
  #
  # THE PROGRESS IS STUBBED, NOT SLEPT, and that is load-bearing (row 19ae324e9697, filed
  # 2026-08-08). The previous form pushed a REAL four-test corpus of `{ sleep 2; }` against a 4s
  # window, which left ~2s of the window for bats per-test overhead. That overhead is UNBOUNDED
  # under load, so this control was measured 16/16 green at load 8-10 and RED at load 12-25,
  # identically on trunk — it was measuring the box, not the SUT, and no constant tweak fixes that.
  # A stub writing TAP on a clock we own removes the load-dependent term outright: all eight results
  # come from ONE process, so the inter-result gap is a bare `sleep 1` with no bats test lifecycle
  # inside it, leaving 3s of the 4s window as slack against scheduler jitter (the old form's slack
  # had to absorb a whole per-test spawn+setup+teardown). It still discriminates: eight 1s gaps put
  # the total wall at 8s, twice the window, so a stall clock that failed to reset on progress would
  # cut this run at t=4s and no green could be stamped — verified by mutation, 2026-08-24.
  b="$(stub_bats slowprogress "case \"\$1\" in --count) echo 8; exit 0 ;; esac
printf '1..8\n'
for i in 1 2 3 4 5 6 7 8; do sleep 1; printf 'ok %s s%s\n' \"\$i\" \"\$i\"; done")"
  export CC_POSTLAND_BATS="$b"
  tree="$(origin_tree)"
  POSTLAND_STALL_S=4 POSTLAND_STALL_POLL_S=1 POSTLAND_SUITE_TIMEOUT_S=120 POSTLAND_FILE_TIMEOUT_S=30 \
    run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "green" ]
}

# ── PRE-PLAN GRACE: the counting pass emits no TAP, so it cannot share the stall clock ──────────
# `bats <N files>` runs bats-gather-tests over every file BEFORE printing `1..N`, and writes nothing
# to the TAP stream while it does. tap_done is therefore 0 for a healthy run and a wedged one alike,
# and a stall clock started at t=0 cuts the healthy one — a FALSE CUT that the ledger records
# identically to a real wedge (a cut names no suite, so nothing is ever traced back to it).
# Measured 2026-08-10 under the real band: 403 suites gather in 72s quiet, and the 2026-07-29 bisect
# caught the same pass still running at >600s at load 33-48 over 141 files.

@test "PRE-PLAN grace: a slow COUNTING pass is never cut — the stall clock starts at the plan line" {
  # THE DISCRIMINATING TEST. The stall bound here is 2s and the counting pass takes 5s, so on the
  # pre-fix code this run is cut before it ever plans; the grace (floored at 900s) is the only thing
  # that can carry it to the plan line. Nothing else in this test can produce a green.
  b="$(stub_bats slowcount "case \"\$1\" in --count) echo 1; exit 0 ;; esac
sleep 5
printf '1..1\nok 1 p\n'")"
  export CC_POSTLAND_BATS="$b"
  tree="$(origin_tree)"
  POSTLAND_STALL_S=2 POSTLAND_STALL_POLL_S=1 POSTLAND_SUITE_TIMEOUT_S=60 \
    run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "green" ]
  # ...and the transition was actually observed, not merely survived by the run being short.
  grep -q 'bats finished counting' "$CC_POSTLAND_DIR/runner.log"
  # POSITIVE CONTROL on the predicate itself, so this cannot pass by tap_planned never matching.
  # The two states int_or_zero collapses onto 0 must read DIFFERENTLY here: an emitted `1..0` is
  # PLANNED (a finished empty corpus, which must leave the grace), an empty TAP is not.
  printf '' > "$BATS_TEST_TMPDIR/empty.tap"
  run grep -aqE '^1\.\.[0-9]' "$BATS_TEST_TMPDIR/empty.tap"; [ "$status" -ne 0 ]
  printf '1..0\n' > "$BATS_TEST_TMPDIR/zero.tap"
  run grep -aqE '^1\.\.[0-9]' "$BATS_TEST_TMPDIR/zero.tap"; [ "$status" -eq 0 ]
}

@test "PRE-PLAN grace: a pass that NEVER plans is still cut, and lands as a non-verdict" {
  # The other half — the grace must not become a hole a genuine gather-wedge escapes through.
  # POSTLAND_STALL_S is left at its 900s default here ON PURPOSE: the stall clock provably cannot
  # be what ends this run, so only the pre-plan bound can, and the wall (120s) is 15x the grace.
  b="$(stub_bats nevercount "case \"\$1\" in --count) echo 1; exit 0 ;; esac
sleep 300")"
  export CC_POSTLAND_BATS="$b"
  echo ppf > "$R/preplan-fixture"; push_commit "pre-plan wedge fixture"
  tree="$(origin_tree)"
  POSTLAND_PRE_PLAN_GRACE_S=4 POSTLAND_STALL_POLL_S=1 POSTLAND_SUITE_TIMEOUT_S=120 \
    POSTLAND_FILE_TIMEOUT_S=4 run bash "$SUT" --run-if-needed
  grep -q 'PRE-PLAN STALL' "$CC_POSTLAND_DIR/runner.log"
  s="$CC_POSTLAND_DIR/stamps/$tree.json"
  [ -f "$s" ]
  # A NON-VERDICT, never a conviction: a run that never planned proves nothing about any suite.
  run jq -r '.verdict' "$s"; [ "$output" != "green" ]
  run jq -r '.verdict' "$s"; [ "$output" != "red" ]
  [ "$(pages_n)" = "0" ]
  # THE WALL PROVABLY DID NOT FIRE — this is the grace, not the backstop it is nested inside.
  run jq -r '.run_s' "$s"; [ "$output" -lt 60 ] || false
}

@test "PRE-PLAN grace: the window is DERIVED from corpus size, not a constant that rots" {
  # A fixed grace is how this defect class recurs — the corpus grew 141 -> 403 suites in two weeks,
  # so any constant sized today erodes silently (memory: bound-must-fit-the-band-not-the-bench,
  # third tell). Asserted on the arithmetic the log reports: 4 suites x 2s = 8s, with the floor
  # lowered out of the way so the derivation is the only thing that can produce that number.
  printf '@test "a" { true; }\n' > "$R/tests/a.bats"
  printf '@test "b" { true; }\n' > "$R/tests/b.bats"
  printf '@test "c" { true; }\n' > "$R/tests/c.bats"
  b="$(stub_bats nevercount2 "case \"\$1\" in --count) echo 1; exit 0 ;; esac
sleep 300")"
  export CC_POSTLAND_BATS="$b"
  push_commit "four suites, none of which will ever be counted"
  POSTLAND_PRE_PLAN_PER_SUITE_S=2 POSTLAND_PRE_PLAN_FLOOR_S=1 POSTLAND_STALL_POLL_S=1 \
    POSTLAND_SUITE_TIMEOUT_S=120 POSTLAND_FILE_TIMEOUT_S=4 run bash "$SUT" --run-if-needed
  grep -q 'grace 8s over 4 suite(s)' "$CC_POSTLAND_DIR/runner.log"
}

@test "PRE-PLAN grace: REAL bats emits no TAP until it has counted (the premise, on the producer)" {
  # THE PREMISE CHECK. Every pre-plan test above drives a STUB, and a stub is a claim ABOUT the real
  # producer — when the producer changes shape a stub keeps passing for a new reason (this suite has
  # already been bitten: see the `flaky` mode's note on keying off the v1 invocation shape). The fix
  # rests entirely on one property of bats itself, so assert it against bats itself.
  # Both assertions are ORDERING/CONTENT properties, deliberately not wall-clock ones: a timing floor
  # would be a flake surface on a fast box and would go red for a bats that merely got quicker, which
  # is not a regression. The measured cost is recorded instead — 19ms/file at load 7 (10 files 279ms,
  # 30 files 696ms, 60 files 1116ms), i.e. ~72s for the real 403-suite corpus.
  d="$BATS_TEST_TMPDIR/realgather"; mkdir -p "$d"
  i=0; while [ "$i" -lt 60 ]; do printf '@test "t%s" { true; }\n' "$i" > "$d/t$i.bats"; i=$(( i + 1 )); done
  # (1) The counting pass does its whole job while emitting NOTHING that any TAP reader can see —
  #     which is exactly why tap_done cannot distinguish it from a wedge. EQUALITY, not a grep for
  #     TAP shapes: `run` captures stdout+stderr into $output, so "the whole output is exactly the
  #     count" is strictly stronger than "no line looks like TAP" — it rules out any extra byte,
  #     TAP-shaped or not. (It also replaces a genuinely DEAD assertion: `… | grep -q … && false ||
  #     true` can never fail, because both branches reach the `|| true`. Caught by this repo's own
  #     dead-assertion ratchet at land time, which is exactly the vacuous control this suite's
  #     header warns about.)
  run env CC_BATS_MAX_ROOTS=0 bats --count "$d"/t*.bats
  [ "$status" -eq 0 ]
  [ "$output" = "60" ]
  # (2) Nothing precedes the plan line in a real run, so "no plan yet" really is the whole blind
  #     window — there is no earlier signal the watcher could have keyed on instead.
  run env CC_BATS_MAX_ROOTS=0 bats "$d"/t*.bats
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | head -1)" = "1..60" ]
}

@test "C15: a HUNG tree is ABSTAINED as a real verdict, never re-run forever" {
  # the counterpart to C13's "a cut tree is RETRIED": a hang is PROVEN about the tree, so
  # re-running it every sweep re-proves a decided fact and burns a full suite per tick.
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  printf '@test "wedge" { sleep 60; }\n' > "$R/tests/wedge.bats"
  push_commit "a suite that wedges"
  POSTLAND_SUITE_TIMEOUT_S=6 POSTLAND_FILE_TIMEOUT_S=6 run bash "$SUT" --run-if-needed
  n1="$(stamps_n)"
  POSTLAND_SUITE_TIMEOUT_S=6 run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ "$(idl_last '.reason')" = "already-stamped" ]   # abstained, unlike a cut
  [ "$(stamps_n)" = "$n1" ]
}

@test "C15: cut and hung route to DIFFERENT owners (cut=quiet box, hung=timeout-wrap)" {
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  echo hf > "$R/hung-fixture"; push_commit "hung fixture"
  tree="$(origin_tree)"
  stub_bats_mode hung
  POSTLAND_SUITE_TIMEOUT_S=4 POSTLAND_FILE_TIMEOUT_S=4 run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "hung" ]
  page="$(find "$CC_PAGES_DIR" -name 'postland-hung-*.page' | head -1)"
  [ -n "$page" ]
  grep -q 'un-stubbed external seam' "$page"        # the HUNG repair...
  grep -q 'timeout-wrap' "$page"
  grep -q 'NOT a cut' "$page"
  run grep -ci 'Re-run on a quiet box' "$page"      # ...and NOT the CUT repair
  [ "$status" -eq 1 ]                               # 1 = matched nothing (2 = no such file)
  [ -f "$REC/cc-backlog.argv" ]
  grep -q 'HUNG' "$REC/cc-backlog.argv"
  run grep -c 'post-land RED' "$REC/cc-backlog.argv"
  [ "$status" -eq 1 ]                               # C13: never filed as a RED
}

@test "C15: a hang candidate whose file does NOT wedge alone degrades to a CUT" {
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  # TWO suites, deliberately: the stub tells "the SUITE run" from "the confirm re-run" by argument
  # count (v2 passes a file LIST, never `tests/`), and with a one-suite corpus those two are
  # byte-identical invocations — the fixture could not express the distinction it exists to test.
  printf '@test "second" { true; }\n' > "$R/tests/second.bats"
  echo ff > "$R/flaky-fixture"; push_commit "suite wedges, file does not"
  tree="$(origin_tree)"
  stub_bats_mode flaky
  POSTLAND_SUITE_TIMEOUT_S=4 POSTLAND_FILE_TIMEOUT_S=4 run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                             # unproven => we refuse to invent a hang
  [ "$(hung_pages_n)" = "0" ]
  [ "$(pages_n)" = "0" ]
}

@test "C15: a job-control death line stays a CUT even when bats itself exits 1" {
  # the live 9c5d0ba74e79 shape: the suite ran, the child was SIGKILLed, bats survived and
  # returned a plain 1 — so rc alone says nothing and only the TAP carries the evidence.
  # A signal is a MACHINE event: it must reach the cut path, never be promoted to a hang.
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  echo svf > "$R/survivor-fixture"; push_commit "survivor fixture"
  tree="$(origin_tree)"
  stub_bats_mode survivor
  run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]
  [ "$(hung_pages_n)" = "0" ]                       # named from the TAP, not from rc
  [ "$(pages_n)" = "0" ]                            # and emphatically not the RED it used to be
}

@test "C15: a test's OWN '# Killed: 9' output is not mistaken for a signal" {
  # the false-positive guard: this repo has reaper/kill suites that print those words, and
  # bats prefixes captured test output with '# '. Reading it as a signal is harmless HERE
  # (both roads end at a cut) but it would silently disarm the hang ladder's ordering.
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  echo rf > "$R/reaper-fixture"; push_commit "reaper-output fixture"
  tree="$(origin_tree)"
  stub_bats_mode reaper
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                             # partial progress, no real signal
  # POSITIVE CONTROL on the discriminator itself: the same words WITHOUT the '# ' prefix
  # must match, so this test cannot pass by the regex simply never matching anything.
  printf '1..3\nok 1 a\n# Killed: 9\n' > "$BATS_TEST_TMPDIR/reaper.tap"
  run grep -aE '^[^#]*(Killed|Terminated): *[0-9]+' "$BATS_TEST_TMPDIR/reaper.tap"
  [ "$status" -eq 1 ]                               # the test's OWN output: NOT a signal
  printf '1..3\nok 1 a\nbats: 42 Killed: 9 exec\n' > "$BATS_TEST_TMPDIR/real.tap"
  run grep -aE '^[^#]*(Killed|Terminated): *[0-9]+' "$BATS_TEST_TMPDIR/real.tap"
  [ "$status" -eq 0 ]                               # the shell's job-control line: IS a signal
}

@test "C17: the suite run is really bounded, with the configured seconds" {
  # a RECORDING timeout(1) — proves the bound is actually applied and carries
  # POSTLAND_SUITE_TIMEOUT_S, rather than trusting that a 124 came from somewhere.
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/timeout.argv"\nexec %s "$@"\n' \
    "$REC" "$(command -v timeout || command -v gtimeout || echo /opt/homebrew/bin/timeout)" \
    > "$STUB/rec-timeout"
  chmod +x "$STUB/rec-timeout"
  CC_POSTLAND_TIMEOUT_BIN="$STUB/rec-timeout" POSTLAND_SUITE_TIMEOUT_S=77 run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ -f "$REC/timeout.argv" ]                        # C17: the bound was applied at all...
  grep -q -- '-k 10 77 ' "$REC/timeout.argv"        # ...with the configured budget
}

@test "C17: unbounded, a hang candidate degrades to a CUT — HUNG is never fabricated" {
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  green="$(cat "$CC_POSTLAND_DIR/last-green")"
  echo sf > "$R/stall-fixture"; push_commit "stall fixture"
  tree="$(origin_tree)"
  stub_bats_mode stall                              # planned 3, completed 0, exit 1, NO signal
  # set-but-EMPTY is honored verbatim => no timeout(1) at all => nothing can ever return 124
  CC_POSTLAND_TIMEOUT_BIN= run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                             # C17: unprovable => never a hang verdict
  [ "$(pages_n)" = "0" ]                            # C13: and emphatically not a RED
  [ "$(hung_pages_n)" = "0" ]
  [ "$(cat "$CC_POSTLAND_DIR/last-green")" = "$green" ]
}

# ════ v2 (LAND_PIPELINE_V2 §4.2) ═════════════════════════════════════════════════════════════════
# C18 partition · C19 no admission control · C20 auto-revert · C21 gate-green · C22 pre-corpus lints.
# Every one carries a POSITIVE CONTROL, because each is a test that a thing does NOT happen — and an
# absence-assertion passes just as happily when the mechanism is dead as when it is working.

# ── C18 partition ───────────────────────────────────────────────────────────────
@test "C18: the corpus is tests/*.bats MINUS the manifest — the LIST bats receives proves it" {
  printf '@test "h" { true; }\n' > "$R/tests/hostonly.bats"
  printf '@test "t" { true; }\n' > "$R/tests/treeonly.bats"
  mkdir -p "$R/scripts"
  printf '# host suites\ntests/hostonly.bats\n' > "$R/scripts/host-suites.manifest"
  push_commit "a partitioned tree"
  b="$(stub_bats argv "printf '%s\n' \"\$@\" > '$REC/argv.txt'; printf '1..1\nok 1 p\n'")"
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ -f "$REC/argv.txt" ]
  run grep -cxF 'tests/treeonly.bats' "$REC/argv.txt"; [ "$output" = "1" ]  # tree suite: RAN
  run grep -cxF 'tests/ok.bats'       "$REC/argv.txt"; [ "$output" = "1" ]
  run grep -cxF 'tests/hostonly.bats' "$REC/argv.txt"; [ "$output" = "0" ]  # host suite: EXCLUDED
  run grep -cxF 'tests/'              "$REC/argv.txt"; [ "$output" = "0" ]  # never the DIRECTORY
  # POSITIVE CONTROL — the identical tree with the manifest REMOVED must run hostonly. Without it
  # this test would pass if the corpus were empty, or if hostonly.bats had simply never existed.
  git -C "$R" rm -q "$R/scripts/host-suites.manifest"
  push_commit "no manifest ⇒ everything runs"
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  run grep -cxF 'tests/hostonly.bats' "$REC/argv.txt"; [ "$output" = "1" ]  # missing ⇒ MORE proof
}

# ── C19 no admission control ────────────────────────────────────────────────────
@test "C19: no admission control survives anywhere in the runner (it must never wait on load)" {
  run grep -cE '^[[:space:]]*gate_admit' "$SUT"
  [ "$output" = "0" ]
  # POSITIVE CONTROL on the PATTERN: it must match a real call site, else this test is a
  # tautology that would keep passing if the regex silently stopped matching anything.
  printf 'x() {\n  gate_admit "full suite"\n}\n' > "$BATS_TEST_TMPDIR/probe.sh"
  run grep -cE '^[[:space:]]*gate_admit' "$BATS_TEST_TMPDIR/probe.sh"
  [ "$output" = "1" ]
  # and no load-polling loop survives under another name
  run grep -cE 'CC_GATE_ADMIT_MAX_WAIT|CC_GATE_ADMIT_POLL|ADMIT-DEFER|ADMIT-PROCEED' "$SUT"
  [ "$output" = "0" ]
}

# ── C21 gate-green ──────────────────────────────────────────────────────────────
@test "C21: a GREEN stamp writes <git-common-dir>/gate-green = the COMMIT sha; a RED never does" {
  gc="$(git -C "$R" rev-parse --git-common-dir)"
  case "$gc" in /*) ;; *) gc="$R/$gc" ;; esac
  rm -f "$gc/gate-green"
  target="$(origin_head)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ -f "$gc/gate-green" ]
  [ "$(cat "$gc/gate-green")" = "$target" ]        # the COMMIT — what the consumers compare to HEAD
  [ "$(cat "$gc/gate-green")" != "$(origin_tree)" ] # ...explicitly NOT the tree the stamp is keyed on
  # CONTROL: an unproven tree must never advance the marker (the whole point of the claim).
  printf '@test "f" { false; }\n' > "$R/tests/bad.bats"
  push_commit "a red tree"
  run bash "$SUT" --run-if-needed
  second_window                                    # C29: make it an actual RED, not merely a cut —
                                                   # this test's claim is about a RED, and a
                                                   # one-window cut would satisfy it vacuously
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$(origin_tree).json"
  [ "$output" = "red" ]                            # the premise, asserted not assumed
  [ "$(cat "$gc/gate-green")" = "$target" ]        # still the last PROVEN commit
}

# ── C20 auto-revert ─────────────────────────────────────────────────────────────
# A stub land lane on the CC_POSTLAND_SHIP_BIN seam. It RECORDS the cwd/branch/subject it was
# invoked with — the contract is "landed FROM the revert worktree, on the revert's own branch" —
# and then really pushes, so "trunk healed" is observed end-to-end rather than mocked away.
ship_stub() {
  printf '#!/bin/bash\n{ echo "cwd=$PWD"; echo "branch=$(git rev-parse --abbrev-ref HEAD)"; echo "subject=$(git log -1 --format=%%s)"; } >> "%s/ship.argv"\ngit push -q origin HEAD:main\n' \
    "$REC" > "$STUB/ship-land"
  chmod +x "$STUB/ship-land"
  export CC_POSTLAND_SHIP_BIN="$STUB/ship-land"
}
# A green baseline FIRST: last-green is the bisect floor, and with no floor there is no bisected
# culprit and therefore (by the bisected-culprit-only guard) no revert at all.
arv_red() {   # [subject] → echoes the culprit sha
  bash "$SUT" --run-if-needed >/dev/null 2>&1 || true
  printf '@test "boom" { false; }\n' > "$R/tests/bad.bats"
  push_commit "${1:-the culprit}"
  # C29 WINDOW 1, burned here. A ladder conviction is a candidate until a SECOND separate sweep
  # re-convicts it, so after one run there is no red — and therefore no bisect and no revert for
  # these tests to observe. This spends the first window (it stamps `cut`; the suite default
  # POSTLAND_AUTOREVERT=off applies, and a cut fires no revert under any setting) so the CALLER's
  # own sweep is the one that reds. Deliberately NOT CC_POSTLAND_CONVICT=off: C20 must be proved
  # against the real conviction path, not a version of it with the new guard switched out.
  bash "$SUT" --run-if-needed >/dev/null 2>&1 || true
  origin_head
}
# Same red, but the culprit is UNREVERTABLE: a follow-on commit edits the culprit's own file, so
# `git revert <culprit>` off the trunk tip conflicts and auto_revert stops at rc 90 (step=revert)
# instead of landing. This is the real shape — the 2026-08-06 incident reverted 13bfa557db3a, whose
# fleet.manifest row and activation script two later commits had amended. The bisect still names the
# culprit (the red starts there and never clears), so the tip-confirmation path is not involved.
arv_red_unrevertable() {   # → echoes the culprit sha
  local culprit
  bash "$SUT" --run-if-needed >/dev/null 2>&1 || true
  printf '@test "boom" { false; }\n' > "$R/tests/bad.bats"
  push_commit "the culprit"
  culprit="$(origin_head)"
  printf '@test "boom" { false; }\n@test "boom too" { false; }\n' > "$R/tests/bad.bats"
  push_commit "a follow-on amending the culprit's own file"
  # C29 WINDOW 1 on the FOLLOW-ON tree — the one the caller's sweep will judge. Burned after the
  # follow-on lands, not before, because the candidate ledger is keyed on the FILE and the tree the
  # caller reds is this one. Same reasoning as arv_red above.
  bash "$SUT" --run-if-needed >/dev/null 2>&1 || true
  printf '%s' "$culprit"
}
ship_field() { sed -n "s/^$1=//p" "$REC/ship.argv" | head -1; }
# The same seam REFUSING to land: the revert commits, then the land lane says no. exit 6 is the
# real one — live marker 47a5350498ee, step=land, revert df989882dc02 — and it is the arm whose
# `do:` line must go on working while the rc-90 arm's is corrected (C27 below).
ship_stub_fail() {
  printf '#!/bin/bash\n{ echo "cwd=$PWD"; echo "branch=$(git rev-parse --abbrev-ref HEAD)"; } >> "%s/ship.argv"\nexit 6\n' \
    "$REC" > "$STUB/ship-land"
  chmod +x "$STUB/ship-land"
  export CC_POSTLAND_SHIP_BIN="$STUB/ship-land"
}
# <c12> <fixed-string> → prints 1 if the page's `do:` line contains it, 0 if not. A COUNT, so the
# caller asserts with a live `[ "$output" = ... ]`; a `[[ ]]` match would be errexit-exempt and
# therefore a dead assertion (see the ASSERTION FORM note above C13).
do_has() { sed -n 's/^do: *//p' "$CC_PAGES_DIR/postland-revert-$1.page" | head -1 | grep -cF -- "$2"; }

@test "C20: a reproducible RED with a BISECTED culprit is reverted and landed via the land lane" {
  ship_stub
  culprit="$(arv_red)"
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed
  [ -f "$REC/ship.argv" ]                                     # the land lane WAS invoked...
  [ "$(ship_field branch)" = "postland-revert-${culprit:0:12}" ]   # ...on the revert's own branch
  cwd="$(ship_field cwd)"
  norm "$CC_POSTLAND_WT_ROOT"
  [ "${cwd#"$NORM"/wt-revert-}" != "$cwd" ]                   # ...from the revert worktree
  run bash -c "sed -n 's/^subject=//p' '$REC/ship.argv' | head -1 | grep -c '^Revert '"
  [ "$output" = "1" ]
  git -C "$R" fetch -q origin
  run bash -c "git -C '$R' log -1 --format=%s origin/main | grep -c '^Revert '"
  [ "$output" = "1" ]                                          # trunk actually HEALED
  [ -f "$CC_POSTLAND_DIR/reverts/$culprit" ]                   # marker, keyed on the culprit
  run grep -c '^land_exit=0$' "$CC_POSTLAND_DIR/reverts/$culprit"
  [ "$output" = "1" ]
  [ "$(cells_n)" = "0" ]                                       # both cells torn down
}

@test "C20: NEVER TWICE — a culprit with a marker is refused on every later encounter" {
  ship_stub
  culprit="$(arv_red)"
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed
  [ -s "$REC/ship.argv" ]                                      # control: the first one DID revert
  [ -f "$CC_POSTLAND_DIR/reverts/$culprit" ]
  # re-present the SAME culprit as trunk, unstamped, so everything but the marker says "revert it"
  git -C "$R" push -qf origin "$culprit:main"
  rm -f "$CC_POSTLAND_DIR/stamps"/*.json
  : > "$REC/ship.argv"
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed
  [ ! -s "$REC/ship.argv" ]                                    # ZERO land-lane invocations
}

@test "C20: a culprit that is ITSELF a revert is refused (that is how a revert war starts)" {
  ship_stub
  culprit="$(arv_red 'Revert "an earlier commit"')"
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed
  [ ! -f "$REC/ship.argv" ]                                    # nothing landed
  [ -z "$(find "$CC_POSTLAND_DIR/reverts" -type f 2>/dev/null)" ]
  [ "$(pages_n)" = "1" ]                                       # ...but the RED is still paged
}

@test "C20: POSTLAND_AUTOREVERT=off refuses the revert while still paging and backlogging" {
  ship_stub
  arv_red >/dev/null
  run env POSTLAND_AUTOREVERT=off bash "$SUT" --run-if-needed
  [ ! -f "$REC/ship.argv" ]                                    # the kill switch holds
  [ -z "$(find "$CC_POSTLAND_DIR/reverts" -type f 2>/dev/null)" ]
  [ "$(pages_n)" = "1" ]                                       # the net still reports
  [ -f "$REC/cc-backlog.argv" ]
}

@test "C20: the per-run cap refuses once it is reached (and does NOT refuse below it)" {
  # At most one culprit is convicted per run_target, so the cap is exercised at its BOUNDARY:
  # 0 must refuse the very first attempt, 1 must allow it. Same fixture, same wiring, so the
  # refusal below can only be the cap — the default (2) is exercised by the happy path above.
  ship_stub
  arv_red >/dev/null
  run env POSTLAND_AUTOREVERT=on POSTLAND_MAX_REVERTS=0 bash "$SUT" --run-if-needed
  [ ! -f "$REC/ship.argv" ]                                    # capped ⇒ no attempt
  [ -z "$(find "$CC_POSTLAND_DIR/reverts" -type f 2>/dev/null)" ]
  # POSITIVE CONTROL at the other side of the boundary
  rm -f "$CC_POSTLAND_DIR/stamps"/*.json
  # TWO WINDOWS AGAIN (C29), because this is a SECOND red EPISODE, not a continuation of the first.
  # The verdict above spent the candidate ledger (conviction_clear runs beside cut_clear at every
  # verdict), so wiping the stamps restarts this tree at window 1 — one sweep here would cut and
  # revert nothing, and the control would fail while the cap it is controlling for works fine.
  run env POSTLAND_AUTOREVERT=on POSTLAND_MAX_REVERTS=1 bash "$SUT" --run-if-needed   # window 1
  run env POSTLAND_AUTOREVERT=on POSTLAND_MAX_REVERTS=1 bash "$SUT" --run-if-needed   # window 2
  [ -s "$REC/ship.argv" ]                                      # under the cap ⇒ it reverts
}

# A FAILED auto-revert's page was the ONE page class the green path did not retract, so it stood
# forever — and its `do:` line kept telling the operator to hand-land a revert whose red may since
# have been fixed forward, i.e. the remedy outlived the symptom (memory:
# work-item-remedy-can-become-forbidden). Measured on the live box 2026-08-06: 5 standing
# postland-revert pages, oldest a week, against 0 red/cut/hung — the retracted classes had none.
@test "C20: a green retracts a standing FAILED-REVERT page (its remedy has gone stale)" {
  ship_stub
  culprit="$(arv_red_unrevertable)"
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed
  # PRECONDITIONS, from the REAL producer — the page under test only exists if the revert failed at
  # the revert STEP. Asserted, never assumed: had it landed (or been skipped) there would be no page
  # and the retraction below would pass vacuously.
  run grep -c '^land_exit=90$' "$CC_POSTLAND_DIR/reverts/$culprit"
  [ "$output" = "1" ]
  [ ! -f "$REC/ship.argv" ]                              # rc 90 stops BEFORE the land lane
  [ "$(rev_pages_n)" = "1" ]
  # Now fix the red FORWARD, the way a human does: the culprit stays on trunk and the page's
  # remedy becomes the wrong action. REPAIR the suite rather than deleting it — deleting restores
  # the byte-identical tree of the green base, and this verifier is TREE-keyed, so the sweep
  # abstains "already-stamped" and never reaches the green branch at all (it exits 0 either way,
  # which is why the verdict below is asserted from the STAMP and not from $status).
  printf '@test "fixed forward" { true; }\n' > "$R/tests/bad.bats"
  push_commit "the red fixed forward — the standing revert page's remedy is now stale"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  tree="$(origin_tree)"
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "green" ]                                # the green actually happened...
  [ "$(rev_pages_n)" = "0" ]                             # ...and the stale page is retracted
  [ "$(pages_n)" = "0" ]                                 # (its RED sibling too, as before)
  [ -f "$CC_POSTLAND_DIR/reverts/$culprit" ]             # never-twice marker SURVIVES (not a page)
}

# ── C27 the FAILED page's remedy must match the failure it reports (item 1fa1e874c098) ───────────
# Filed by a1743ffebd35: `AUTO-REVERT FAILED(step=revert rc=90): tests/bats-assert-liveness.bats
# (revert none ...)`. auto_revert's rc-90 half never applies a revert, so its branch is a bare copy
# of origin/main — and yet the page printed the step=land remedy, `worktree add <br> && ship-land`,
# which hands the land lane a branch with ZERO commits on it: it lands nothing, exits clean, and
# reads as "the revert is in". The page's own `branch:` line said `revert commit none` two lines
# above it. Live on the box 2026-08-07: postland-revert-13bfa557db3a, standing page from 03:40Z,
# `git rev-list --count origin/main..postland-revert-13bfa557db3a` = 0. rc 90 is the COMMON half —
# 4 of the 5 FAILED attempts all-time (13bfa557db3a, 57e162494c10, d25c4dd47384, a1743ffebd35) —
# so this was every rc-90 page ever written, and the one arm where it was right (rc 6, 47a5350498ee)
# is the minority.
# THE TWO TESTS ARE EACH OTHER'S CONTROL. They differ in exactly one fact — whether a revert commit
# exists — and each pins BOTH the branch and the remedy, so a fix that dropped both arms' branches,
# or printed the conflict remedy for both, reddens the other one.
@test "C27: a revert that never APPLIED drops its empty branch and stops prescribing it" {
  ship_stub
  culprit="$(arv_red_unrevertable)"
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed
  # PRECONDITIONS, from the REAL producer — asserted, never assumed: with any other outcome there is
  # no empty branch and no rc-90 page, and every claim below would pass vacuously.
  [ "$(mk_get "$culprit" land_exit)" = "90" ]
  [ "$(mk_get "$culprit" step)" = "revert" ]
  [ "$(mk_get "$culprit" revert)" = "none" ]             # nothing was ever committed
  [ ! -f "$REC/ship.argv" ]                              # rc 90 stops BEFORE the land lane
  [ "$(rev_pages_n)" = "1" ]
  # CLAIM 1: the branch that held nothing is gone, so nothing can be handed it by mistake later.
  run git -C "$R" branch --list "postland-revert-${culprit:0:12}"
  [ -z "$output" ]
  # CLAIM 2: the remedy no longer routes a branch into the land lane at all...
  run do_has "${culprit:0:12}" "$STUB/ship-land"
  [ "$output" = "0" ]
  # ...it tells the operator to MAKE the revert that does not exist yet, on the culprit named.
  run do_has "${culprit:0:12}" "git revert $culprit"
  [ "$output" = "1" ]
}

@test "C27: a revert that APPLIED but did not land keeps its branch, and its page still ships it" {
  ship_stub_fail
  culprit="$(arv_red)"
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed
  # PRECONDITIONS: the revert COMMITTED and the land lane refused it — the other arm entirely.
  [ "$(mk_get "$culprit" step)" = "land" ]
  [ "$(mk_get "$culprit" land_exit)" = "6" ]
  [ "$(mk_get "$culprit" revert)" != "none" ]
  [ -s "$REC/ship.argv" ]                                # the land lane WAS reached
  [ "$(rev_pages_n)" = "1" ]
  # THE CONTROL: the branch survives AND really is the only copy of a real commit — which is the
  # premise the old rc-keyed rule asserted for rc 90 too, where it was false.
  run git -C "$R" rev-list --count "origin/main..postland-revert-${culprit:0:12}"
  [ "$output" = "1" ]
  # ...so hand-landing that branch is the right remedy here, and must survive the fix above.
  run do_has "${culprit:0:12}" "$STUB/ship-land"
  [ "$output" = "1" ]
  run do_has "${culprit:0:12}" "postland-revert-${culprit:0:12}"
  [ "$output" = "1" ]
}

# ── C31 the culprit must be IN the trunk the revert is taken from (item a31d1fe3de3d) ───────────
# A $BATS_BIN wrapper that fires the LAND-LANE RACE exactly once, mid-sweep, then delegates to the
# real bats. The timing is the whole fixture: --run-if-needed captures target=origin/main at entry
# and auto_revert re-fetches only after the corpus, the ladder and the bisect are done, so a rewrite
# that lands in between orphans the sha the sweep is standing on. Rewriting from the test BEFORE the
# sweep would simply make the sweep capture the new trunk and the test would pass vacuously.
# The twin is the culprit's OWN tree on the culprit's OWN parent — the same patch under a different
# sha, which is what a rebase-land produces and is why `--is-ancestor` is the discriminator rather
# than any diff of content.
# It RECORDS the twin it minted. The test reads its preconditions from that record and never from
# live origin/main: an UNGUARDED auto_revert lands its revert and moves trunk a second time, so a
# precondition read after the sweep describes the SUT's own response rather than the race — it
# holds only in the arm that already passed, and the control then dies on a precondition instead of
# on a claim, proving nothing. Measured, not theorised: the first mutation run of this test failed
# exactly there.
orphan_culprit_bats() {   # <culprit> → echoes the wrapper's path
  local real; real="$(command -v bats)"
  { printf '#!/bin/bash\n'
    printf 'if [ ! -e "%s" ]; then\n' "$REC/orphaned"
    printf '  tw="$(git -C "%s" commit-tree "%s^{tree}" -p "%s~1" -m "re-landed by the land lane")"\n' "$R" "$1" "$1"
    printf '  git -C "%s" push -qf origin "$tw:main"\n' "$R"
    printf '  printf "%%s" "$tw" > "%s"\n' "$REC/orphaned"
    printf 'fi\n'
    printf 'exec "%s" "$@"\n' "$real"
  } > "$STUB/bats-orphan"
  chmod +x "$STUB/bats-orphan"
  printf '%s' "$STUB/bats-orphan"
}
# Everything under auto_revert reverts FROM origin/main, and nothing checked the culprit was
# REACHABLE from there. Live on this box: the 2026-08-01T04:29Z run measured 86774743ffcd, not an
# ancestor of trunk (its patch is in trunk as fa78e662); the bisect off it named 57e162494c10, also
# not in trunk (in trunk as 28949c7b, with five commits on top including the current last-green
# 71e96bcbc825). `git revert` asked a tree that never had that commit applied from that parent to
# un-apply it — rc 90, revert=none, and a page prescribing the same impossible revert by hand.
#
# rc 90 is the MILD outcome and must not be read as the guard's purpose: the conflict is the only
# thing that stopped it. A culprit whose lines have not moved reverts CLEANLY and the land lane puts
# it on trunk — 47a5350498ee is the live proof (not in trunk, revert APPLIED, rc 6 at the land step
# only). THE POSITIVE CONTROL IS PRE-EXISTING AND NOT OPTIONAL: C20 above lands a revert off an
# ordinary in-trunk culprit, so a guard that over-fired — refusing every culprit, or failing closed
# on a healthy tip — reddens C20 rather than passing quietly here.
@test "C31: a culprit orphaned by a rebase-land is refused before the revert lane is entered" {
  ship_stub
  culprit="$(arv_red)"
  CC_POSTLAND_BATS="$(orphan_culprit_bats "$culprit")"; export CC_POSTLAND_BATS
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed
  # PRECONDITIONS — facts about the RACE, read from the twin the wrapper recorded. Every one of
  # these was true when auto_revert made its decision, and stays true whatever the SUT did next.
  twin="$(cat "$REC/orphaned" 2>/dev/null || true)"
  [ -n "$twin" ]                                                  # the wrapper fired
  [ "$(git -C "$R" rev-parse "$twin^{tree}")" = "$(git -C "$R" rev-parse "$culprit^{tree}")" ]
  run git -C "$R" merge-base --is-ancestor "$culprit" "$twin"      # a TWIN, not a rewind: same tree...
  [ "$status" -ne 0 ]                                             # ...and the culprit is off that trunk
  # CLAIM 1: refused, with the token that names why — not the generic skip, and not rc 90.
  run grep -c 'AUTOREVERT verdict=skipped reason=culprit-not-in-trunk' "$CC_POSTLAND_DIR/runner.log"
  [ "$output" = "1" ]
  # CLAIM 2: refused BEFORE anything was attempted. No marker means the retry ladder records no
  # attempt against a culprit nothing tried to revert, so the budget stays with the real ones.
  [ ! -f "$CC_POSTLAND_DIR/reverts/$culprit" ]
  # CLAIM 3: the revert lane was never entered at all — no branch, no page, no land.
  run git -C "$R" branch --list "postland-revert-${culprit:0:12}"
  [ -z "$output" ]
  [ "$(rev_pages_n)" = "0" ]
  [ ! -f "$REC/ship.argv" ]
  # CLAIM 4 — THE HARM ITSELF, and the reason rc 90 must not be read as this guard's purpose. In
  # this fixture the reverse patch applies CLEANLY (the twin carries the culprit's tree, so the file
  # the culprit added is right there to delete), so without the guard the revert lands and takes the
  # patch off trunk — the f323b427 shape. Trunk must still carry it, and trunk must still be the
  # twin rather than a revert commit pushed on top of it.
  run git -C "$R" cat-file -e "origin/main:tests/bad.bats"
  [ "$status" -eq 0 ]
  [ "$(git -C "$R" rev-parse origin/main)" = "$twin" ]
}

# ── C34 the ARTIFACTS A HUMAN READS must say the culprit is orphaned too (item 6e1361f39202) ────
# C31 above proves the ACTUATOR refuses an orphaned culprit. It runs at the BOTTOM of red_actions,
# and the page, the backlog item and the peer ping are all written ABOVE it — so every artifact a
# human opens went on naming the sha as the thing to act on while auto_revert had already decided
# it was not actionable. That asymmetry is the whole item: measured 2026-08-09, item a31d1fe3de3d
# named 57e162494c10, whose patch is on trunk as 28949c7b with five commits on top.
#
# The BACKLOG TITLE is the one that matters most and is asserted for that reason: the page is
# state-keyed and the next green deletes it, so a worker who opens the row a day later has only the
# title — and a title naming a non-ancestor sha, with nothing saying so, is what sends them to a
# revert against a tree that never had the commit applied.
#
# SAME FIXTURE AS C31, deliberately — one race, two consumers — but run at the suite default
# POSTLAND_AUTOREVERT=off. The revert lane is not the subject here, and leaving it off keeps trunk
# parked on the twin, so the twin the assertions read is the twin the SUT saw.
#
# THE TWIN IS FOUND BY PATCH-ID, WHICH IS WHY THIS FIXTURE PROVES IT: the wrapper mints the twin as
# the culprit's OWN tree on the culprit's OWN parent, i.e. the same diff under a different sha —
# precisely what a rebase-land produces, and precisely what patch-id equates and --is-ancestor does
# not. A twin minted any other way would pass the orphan half and prove nothing about the locator.
@test "C34: an orphaned culprit is named as orphaned in the page and the backlog title, with its patch-id twin" {
  ship_stub
  culprit="$(arv_red)"
  CC_POSTLAND_BATS="$(orphan_culprit_bats "$culprit")"; export CC_POSTLAND_BATS
  run bash "$SUT" --run-if-needed
  # PRECONDITIONS — facts about the RACE, read from the record the wrapper wrote, never from live
  # origin/main (C31's own comment explains why: a precondition read after the sweep describes the
  # SUT's response rather than the race).
  twin="$(cat "$REC/orphaned" 2>/dev/null || true)"
  [ -n "$twin" ]                                                     # the wrapper fired
  [ "$(git -C "$R" rev-parse "$twin^{tree}")" = "$(git -C "$R" rev-parse "$culprit^{tree}")" ]
  run git -C "$R" merge-base --is-ancestor "$culprit" "$twin"         # a TWIN, not a rewind...
  [ "$status" -ne 0 ]                                                # ...and the culprit is off trunk
  page="$CC_PAGES_DIR/postland-red-${culprit:0:12}.page"
  [ -f "$page" ]
  # CONTROL — the bisect CONVICTED. Every claim below lives on the convicted branch, so an abstained
  # run would satisfy them vacuously by never reaching it. Pinned as its own line so that failure
  # reports "the bisect abstained" instead of "the page lacks a string" (memory:
  # harness-default-collapses-the-states-under-test).
  run grep -c 'NO VERDICT' "$page"
  [ "$output" = "0" ]
  # CLAIM 1: the page says the convicted sha is not in trunk, and says not to revert it.
  run grep -c 'CONVICTED BUT NOT IN TRUNK' "$page"
  [ "$output" = "1" ]
  run grep -c 'Do NOT revert it' "$page"
  [ "$output" = "1" ]
  # CLAIM 2: the page names the TWIN — the operator's real next move. Counted, never `grep -q`:
  # under pipefail a matching -q makes the producer take SIGPIPE and the pipeline adopts it
  # (memory: grep-q-under-pipefail-inverts-the-verdict).
  run grep -c "its patch IS on trunk as ${twin:0:12}" "$page"
  [ "$output" = "1" ]
  # CLAIM 3: THE DURABLE ARTIFACT. The title outlives the page, so it carries the same warning.
  [ -f "$REC/cc-backlog.argv" ]
  run grep -c 'culprit NOT in trunk' "$REC/cc-backlog.argv"
  [ "$output" -ge 1 ]
  run grep -c "act on THAT, not on this sha" "$REC/cc-backlog.argv"
  [ "$output" -ge 1 ]
  # CLAIM 4: the sha is still IN the title. Naming the orphan state must not cost the identifier —
  # a worker needs the sha to find the twin's neighbourhood at all, and the fix would otherwise be
  # a subtraction dressed as a warning.
  run grep -c "@ ${culprit:0:12}" "$REC/cc-backlog.argv"
  [ "$output" -ge 1 ]
}

# ── C35 the ordinary in-trunk culprit is UNCHANGED (the too-wide half of C34's guard) ────────────
# A guard that fired on every culprit would satisfy every claim in C34 and be catastrophically
# wrong: every page and every backlog row on this box would tell the operator not to act on a sha
# that is perfectly actionable. C31's positive control is C20 (a real revert lands), which proves
# the ACTUATOR still permits the healthy case; nothing proved the RENDERING still does, because
# C20 never reads the page text. This is that control, and it is the half a `[ "$orphan" = 1 ]`
# mutated to a constant-true reds (memory: guard-proxy-fails-in-both-directions).
@test "C35: an in-trunk culprit is still named plainly — no orphan warning in the page or the title" {
  ship_stub
  culprit="$(arv_red)"
  run bash "$SUT" --run-if-needed
  page="$CC_PAGES_DIR/postland-red-${culprit:0:12}.page"
  [ -f "$page" ]
  # PRECONDITION, and the exact inverse of C34's: this culprit IS reachable from trunk. Asserted
  # rather than assumed — with no race fired the only way it could be false is a broken fixture,
  # and then every negative below would pass for the wrong reason.
  run git -C "$R" merge-base --is-ancestor "$culprit" origin/main
  [ "$status" -eq 0 ]
  run grep -c 'NO VERDICT' "$page"
  [ "$output" = "0" ]                                    # control: convicted, as in C34
  # CLAIM: the plain rendering, and NOT the orphan one, in both artifacts.
  run grep -c "culprit: ${culprit:0:12} (bisected from last-green" "$page"
  [ "$output" = "1" ]
  run grep -c 'CONVICTED BUT NOT IN TRUNK' "$page"
  [ "$output" = "0" ]
  [ -f "$REC/cc-backlog.argv" ]
  run grep -c 'culprit NOT in trunk' "$REC/cc-backlog.argv"
  [ "$output" = "0" ]
}

# The rc-90 remedy is the ONE that asks the operator for hand-work — resolving a revert conflict —
# and it used to park that work at $WT_ROOT/wt-revert-manual, inside the glob
# reap_stale_worktrees deletes (`wt-run-*` -o `wt-revert-*`, older than WT_STALE_S). That reaper is
# deliberately blind to ownership, so the next sweep after 8h would take the cell and the
# half-resolved conflict with it. Replayed against the REAL reaper, never a spelling check on the
# name: a `-name` assertion would go stale the moment the reaper's globs change, and a path is only
# safe against the reaper that actually runs.
@test "C27: the manual cell the rc-90 page names survives the worktree reaper" {
  ship_stub
  culprit="$(arv_red_unrevertable)"
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed
  [ "$(mk_get "$culprit" land_exit)" = "90" ]           # precondition: this IS the rc-90 page
  # The path the page ACTUALLY printed — read out of the remedy, never a literal, so this tracks
  # whatever the remedy says rather than agreeing with a copy of it.
  cell="$(sed -n 's/^do: .*worktree add -b [^ ]* \([^ ]*\) .*/\1/p' "$CC_PAGES_DIR/postland-revert-${culprit:0:12}.page")"
  [ -n "$cell" ]
  mkdir -p "$cell"
  printf 'a half-resolved conflict\n' > "$cell/CONFLICT"
  # The CONTROL cell: same root, same age, but inside the machine's own namespace. Without it a
  # dead reaper would pass this test — which is the exact failure being guarded.
  mkdir -p "$CC_POSTLAND_WT_ROOT/wt-revert-control"
  touch -t 202001010000 "$cell" "$CC_POSTLAND_WT_ROOT/wt-revert-control"
  # One sweep, and a GREEN one: the reaper runs from prepare_worktree, before any verdict, so
  # fixing the red forward exercises it on the cheapest path instead of re-bisecting.
  printf '@test "fixed forward" { true; }\n' > "$R/tests/bad.bats"
  push_commit "the red fixed forward"
  run env CC_POSTLAND_WT_STALE_S=60 bash "$SUT" --run-if-needed
  [ ! -d "$CC_POSTLAND_WT_ROOT/wt-revert-control" ]     # CONTROL: the reaper really did fire...
  [ -f "$cell/CONFLICT" ]                               # THE CLAIM: ...and it did not take this
}

@test "C20: an UNDECIDABLE bisect pages and backlogs but attempts ZERO reverts" {
  # The pin: red_actions falls back to the TARGET sha for paging when bisect cannot decide, and
  # reverting that fallback would revert a tip nothing convicted. With no last-green there is no
  # bisect floor, which is exactly the first-ever-run shape.
  ship_stub
  base="$(origin_head)"
  printf '@test "f" { false; }\n' > "$R/tests/bad.bats"
  push_commit "red, with no green floor to bisect from"
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]                       # precondition, asserted not assumed
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed   # C29 window 1 — candidate only
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed   # C29 window 2 — now it reds
  [ "$(pages_n)" = "1" ]                                       # it PAGES...
  [ -f "$REC/cc-backlog.argv" ]                                # ...and BACKLOGS...
  [ ! -f "$REC/ship.argv" ]                                    # ...and reverts NOTHING
  [ -z "$(find "$CC_POSTLAND_DIR/reverts" -type f 2>/dev/null)" ]
  # POSITIVE CONTROL: the same red, now WITH a green floor, must revert — otherwise this test
  # would pass identically if auto-revert were dead in every case, which is the failure it guards.
  git -C "$R" reset -q --hard "$base"
  git -C "$R" push -qf origin HEAD:main
  bash "$SUT" --run-if-needed >/dev/null 2>&1 || true          # green ⇒ last-green exists
  [ -f "$CC_POSTLAND_DIR/last-green" ]
  printf '@test "f2" { false; }\n' > "$R/tests/bad2.bats"
  push_commit "the control culprit"
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed   # C29 window 1
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed   # C29 window 2
  [ -s "$REC/ship.argv" ]                                      # decidable ⇒ a revert IS attempted
}

# ── C26 the never-twice marker is BOUNDED (item 8e8a306f6dc0) ────────────────────
# Census of the live host's runner.log, all-time to 2026-08-07: 25 AUTOREVERT encounters — landed=3,
# FAILED=5, skipped=17, and all 17 skips read `reason=already-attempted`. 12% effective. The skips
# were four culprits (a1743ffebd35 ×3, 47a5350498ee ×3, 57e162494c10 ×3, b3f728858a6f ×8), not one
# as first filed — but the shape is identical in each: "attempted once" is a STATE, it outlives the
# premise that produced it, and it then governs forever from INSIDE the safety mechanism. That is
# Law 2 of docs/research/inertness-generator-2026-08-07.md living in the very thing §3 prescribes as
# its replacement, and §9 files it as the blocker on the pure-veto tier: a veto that cannot actuate
# is a permission gate in disguise.
#
# The fix is asymmetric because the two markers record different facts, and these four tests pin
# both arms plus both re-arm triggers. Every one carries the control that stops it passing on a dead
# actuator — the failure mode being guarded here is precisely "the mechanism silently does nothing".
inert_pages_n() { find "$CC_PAGES_DIR" -name 'postland-revert-inert-*.page' 2>/dev/null | wc -l | tr -d ' '; }
mk_get()        { sed -n "s/^$2=//p" "$CC_POSTLAND_DIR/reverts/$1" | head -1; }

@test "C26: a revert that never LANDED re-arms at a new trunk tip and this time actuates" {
  ship_stub
  culprit="$(arv_red_unrevertable)"
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed
  # PRECONDITIONS from the real producer: the first attempt failed at the revert STEP, so nothing
  # reached the land lane. Asserted, never assumed — had it landed, the re-arm below would be
  # exercising the permanent arm instead and this test would prove the opposite of its title.
  [ "$(mk_get "$culprit" land_exit)" = "90" ]
  [ "$(mk_get "$culprit" attempts)" = "1" ]
  [ ! -f "$REC/ship.argv" ]
  [ "$(inert_pages_n)" = "0" ]                           # a bounded skip is not yet terminal
  # NEW EVIDENCE: trunk moves back to the culprit itself, so the follow-on commit whose edit to the
  # culprit's own file caused rc 90 is no longer in the way. Nothing about the marker changed; the
  # only new fact is the tip — which is exactly the fact the old guard could not read.
  git -C "$R" push -qf origin "$culprit:main"
  rm -f "$CC_POSTLAND_DIR/stamps"/*.json
  # A SECOND red EPISODE ⇒ its own two windows (C29). The verdict above spent the candidate ledger,
  # so this tree starts again at window 1; one sweep would cut, never reach red_actions, and the
  # re-arm under test would look broken when it is not. Window 1 also logs no `AUTOREVERT rearm`
  # line (no red ⇒ no red_actions), so the `= 1` count below still measures exactly one re-arm.
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed   # C29 window 1 => cut
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed   # window 2 => red => the re-arm fires
  [ -s "$REC/ship.argv" ]                                # THE CLAIM: the veto ACTUATED on retry
  [ "$(mk_get "$culprit" attempts)" = "2" ]
  [ "$(mk_get "$culprit" land_exit)" = "0" ]
  run grep -c 'AUTOREVERT rearm .* why=new-tip' "$CC_POSTLAND_DIR/runner.log"
  [ "$output" = "1" ]
}

@test "C26: a LANDED revert is still never twice — but the skip PAGES instead of going silent" {
  ship_stub
  culprit="$(arv_red)"
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed
  [ "$(mk_get "$culprit" land_exit)" = "0" ]             # control: it really did land
  [ "$(inert_pages_n)" = "0" ]                           # ...and one attempt is not yet inert
  : > "$REC/ship.argv"
  # Convicted AGAIN — and deliberately at a tip that is NOT the recorded one, so every input the
  # bounded arm reads says "re-arm" and only the outcome arm says otherwise. Without the innocuous
  # follow-on the tip would be restored to the culprit itself, i.e. identical to the recorded tip,
  # and the test would pass just as well against a fix that had merely forgotten to check outcome.
  git -C "$R" push -qf origin "$culprit:main"
  git -C "$R" fetch -q origin && git -C "$R" reset -q --hard origin/main
  printf '#!/bin/bash\nexit 0\n' > "$R/innocuous.sh"
  push_commit "an innocuous follow-on — the trunk tip now differs from the recorded one"
  [ "$(origin_head)" != "$(mk_get "$culprit" tip)" ]     # the control, asserted not assumed
  rm -f "$CC_POSTLAND_DIR/stamps"/*.json
  # A SECOND red EPISODE ⇒ its own two windows (C29) — and here the one-window version is worse than
  # a plain failure: `! -s ship.argv` passes VACUOUSLY on a cut (a cut reverts nothing), so only the
  # page count below would have caught it. The claim is about a TERMINAL SKIP, which requires
  # actually reaching red_actions.
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed   # C29 window 1 => cut
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed   # window 2 => red => the skip pages
  [ ! -s "$REC/ship.argv" ]                              # SAFETY UNCHANGED: never a second revert
  [ "$(inert_pages_n)" = "1" ]                           # THE CLAIM: it is no longer silent
  # ...and DURABLY so — a page dies on the next green, a backlog item does not — with the damper
  # stated as an INVARIANT and never as an absolute count: one item per fresh EDGE, never one per
  # encounter. b3f728858a6f was convicted 8 times in 2.5 days, and 8 items would be exactly the
  # always-fires alarm this class exists to avoid (memory: alarm-polarity).
  #
  # WHY AN INVARIANT AND NOT `= 1`. How many terminal encounters ONE sweep reaches is not fixed:
  # `do_run_if_needed` self-requeues when the trunk tip moves under it, so `red_actions` can run more
  # than once per invocation. Two runs of this exact fixture disagreed (1, then 2) — an absolute
  # count is a load-dependent tripwire, which is the same defect as the mechanism under test. The
  # equality holds for any number of encounters; `edges >= 1` keeps it from holding vacuously at
  # 0 == 0 on a sweep that never convicted.
  #
  # Deliberately NOT pinning a `fresh=0` control here: forcing a re-encounter needs a third full
  # sweep, and each sweep carries its own `git bisect run`. Measured on this box, that third sweep
  # sat 13m+ inside the bisect's own 900s bound under load 20 — a test that expensive is flaky by
  # construction in a load-shed corpus, and the damping it would pin is a refinement, not the item's
  # claim. The two claims above are what 8e8a306f6dc0 asked for.
  edges="$(grep -c 'terminal=1 fresh=1' "$CC_POSTLAND_DIR/runner.log" || true)"
  items="$(grep -c 'AUTO-REVERT INERT (already-reverted)' "$REC/cc-backlog.argv" || true)"
  [ "$edges" -ge 1 ]                                     # control: it filed at all (never vacuous)
  [ "$items" = "$edges" ]                                # one item per EDGE, not per encounter
  run grep -c 'reason=already-reverted .*terminal=1' "$CC_POSTLAND_DIR/runner.log"
  [ "$output" -ge 1 ]
}

@test "C26: the retry budget is FINITE — spent, the skip is terminal and pages" {
  ship_stub
  culprit="$(arv_red_unrevertable)"
  run env POSTLAND_AUTOREVERT=on POSTLAND_REVERT_RETRY_MAX=1 bash "$SUT" --run-if-needed
  [ "$(mk_get "$culprit" attempts)" = "1" ]              # control: attempt 1 of a budget of 1...
  [ ! -f "$REC/ship.argv" ]                              # ...which failed at the revert step
  git -C "$R" push -qf origin "$culprit:main"            # new evidence — enough to re-arm, if budget
  rm -f "$CC_POSTLAND_DIR/stamps"/*.json                 # remained. It does not.
  # EVERY red EPISODE gets its own two windows (C29): a verdict spends the candidate ledger, so each
  # stamp-wipe restarts this tree at window 1. The log-count assertions below stay exact because a
  # window-1 cut never reaches red_actions and so emits none of the lines they count.
  run env POSTLAND_AUTOREVERT=on POSTLAND_REVERT_RETRY_MAX=1 bash "$SUT" --run-if-needed  # window 1
  run env POSTLAND_AUTOREVERT=on POSTLAND_REVERT_RETRY_MAX=1 bash "$SUT" --run-if-needed  # window 2
  [ ! -f "$REC/ship.argv" ]                              # budget spent ⇒ no attempt
  [ "$(mk_get "$culprit" attempts)" = "1" ]              # ...and the marker is untouched
  [ "$(inert_pages_n)" = "1" ]                           # ...and it PAGED rather than skipping mute
  run grep -c 'reason=retry-budget-spent' "$CC_POSTLAND_DIR/runner.log"
  [ "$output" = "1" ]
  # ...and BOTH terminal surfaces name the SUITE the veto was for (2026-08-10, item 50af9e4a4258).
  # A page and a durable item that carry only a sha, a reason and a count cannot be adjudicated: the
  # first question — is it still red? — is unaskable, and the archaeology it forces is exactly what
  # made an unattributed RED unactionable one arm over. Live proof that the omission inverts the
  # remedy: f60b7ca220ee's suite was fixed FORWARD, so by the time a human read the item the revert
  # it argued for would have deleted a live dependency.
  #
  # DERIVED from the marker, never a literal. A hardcoded 'tests/bad.bats' would keep passing if the
  # fixture's culprit file were renamed — the same vacuity as a control that cannot fail — so the
  # marker field is asserted first (it is the producer's own record) and then required to appear in
  # both surfaces. Fail the first assertion and the other two are known to be measuring nothing.
  ftest="$(mk_get "$culprit" failing)"
  [ "$ftest" = "tests/bad.bats" ]                        # control: the producer recorded a suite...
  run grep -cF "$ftest" "$CC_PAGES_DIR/postland-revert-inert-${culprit:0:12}.page"
  [ "$output" -ge 1 ]                                    # ...the page names it...
  run grep -cF "AUTO-REVERT INERT (retry-budget-spent): $ftest @ ${culprit:0:12}" "$REC/cc-backlog.argv"
  [ "$output" = "1" ]                                    # ...and so does the one that survives a green
  # BOUNDARY CONTROL at the other side: the identical state with one more unit of budget ATTEMPTS.
  # Without this the test would pass just as well against an actuator that never retries at all.
  rm -f "$CC_POSTLAND_DIR/stamps"/*.json
  run env POSTLAND_AUTOREVERT=on POSTLAND_REVERT_RETRY_MAX=2 bash "$SUT" --run-if-needed  # window 1
  run env POSTLAND_AUTOREVERT=on POSTLAND_REVERT_RETRY_MAX=2 bash "$SUT" --run-if-needed  # window 2
  [ -s "$REC/ship.argv" ]
  [ "$(mk_get "$culprit" attempts)" = "2" ]
}

@test "C26: an UNMOVED tip inside the decay window skips quietly; the decay alone re-arms it" {
  ship_stub
  culprit="$(arv_red_unrevertable)"
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed
  [ "$(mk_get "$culprit" land_exit)" = "90" ]            # control: a FAILED marker, so the bounded
  [ "$(mk_get "$culprit" attempts)" = "1" ]              # arm is the one under test
  # SAME tip, re-presented: no new evidence exists, so re-arming would be a retry loop on a fact
  # that cannot have changed. This is the only non-terminal skip and it stays log-only — a page
  # here would fire every sweep and train the operator to ignore the class (memory: alarm-polarity).
  rm -f "$CC_POSTLAND_DIR/stamps"/*.json
  : > "$CC_POSTLAND_DIR/runner.log"
  # Two windows per red episode (C29). The log was just truncated, and a window-1 cut writes only
  # CUT lines — none of the `reason=` lines counted below — so the exact counts still hold.
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed   # window 1 => cut
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed   # window 2 => red => the quiet skip
  [ ! -f "$REC/ship.argv" ]
  [ "$(mk_get "$culprit" attempts)" = "1" ]              # untouched — no attempt was spent
  [ "$(inert_pages_n)" = "0" ]                           # NOT terminal, so NOT paged
  run grep -c 'reason=failed-at-this-tip' "$CC_POSTLAND_DIR/runner.log"
  [ "$output" = "1" ]
  # THE SECOND RE-ARM TRIGGER, isolated: same tip, same marker, nothing moved — only the decay
  # window collapses. It must attempt, which also proves the skip above was the DECAY and not some
  # other refusal silently standing in for it.
  rm -f "$CC_POSTLAND_DIR/stamps"/*.json
  run env POSTLAND_AUTOREVERT=on POSTLAND_REVERT_RETRY_DECAY_S=0 bash "$SUT" --run-if-needed # window 1
  run env POSTLAND_AUTOREVERT=on POSTLAND_REVERT_RETRY_DECAY_S=0 bash "$SUT" --run-if-needed # window 2
  [ "$(mk_get "$culprit" attempts)" = "2" ]
  run grep -c 'AUTOREVERT rearm .* why=decay-' "$CC_POSTLAND_DIR/runner.log"
  [ "$output" = "1" ]
}

# ── C25 the adjudicator's env ───────────────────────────────────────────────────
@test "C25: the bisect PROBE runs under the very TMPDIR the corpus measured under" {
  # THE 2026-08-06 FALSE ATTRIBUTION at its mechanism. do_bisect ran `git bisect run` under the
  # INHERITED launchd TMPDIR while the corpus ran under TMPDIR=$RUN_TMP (…/postland-run.XXXXXX,
  # +20 bytes), so a red that exists only at the longer prefix — a kitty fixture against Darwin's
  # 104-byte sun_path cap — could not reproduce at any probe. Recorded PER INVOCATION, so the
  # assertion is about the string the probe actually received, not about the line that sets it.
  bash "$SUT" --run-if-needed >/dev/null 2>&1 || true          # a green floor ⇒ a bisect range exists
  printf '@test "rec" { printf "%%s\\n" "$TMPDIR" >> "%s/tmpdirs.txt"; false; }\n' "$REC" \
    > "$R/tests/bad.bats"
  push_commit "the culprit"
  run bash "$SUT" --run-if-needed                               # C29 window 1 — a cut, so NO bisect
  # TRUNCATE between windows, deliberately. Each sweep mints its OWN $RUN_TMP (a fresh mktemp -d
  # suffix), so leaving window 1's rows in place would compare window 2's probe against window 1's
  # corpus — two different directories that SHOULD differ, turning the claim into a guaranteed
  # failure about the wrong thing. Everything below is one window's invocations.
  : > "$REC/tmpdirs.txt"
  run bash "$SUT" --run-if-needed                               # C29 window 2 — reds, so it bisects
  [ -s "$REC/tmpdirs.txt" ]
  [ "$(wc -l < "$REC/tmpdirs.txt" | tr -d ' ')" -ge 2 ]         # corpus, then ladder, then the probe
  corpus="$(head -1 "$REC/tmpdirs.txt")"                        # invocation 1 IS the corpus run
  probe="$(tail -1 "$REC/tmpdirs.txt")"                         # the LAST is do_bisect's (auto-revert
                                                                # is off by default, so nothing runs
                                                                # bats after it)
  case "$corpus" in */postland-run.??????) ;; *) false ;; esac   # control: the corpus really is $RUN_TMP
  [ "$probe" = "$corpus" ]                                      # THE CLAIM (C25)
}

@test "C25: an env-dependent RED reverts the commit that CAUSED it, never the innocent tip" {
  # The incident end-to-end, minimised. e80c85aa — a correct, unrelated cc-queue fix — was reverted
  # as f323b427 purely for being the newest commit when a kitty fixture blew the 104-byte sun_path
  # budget under the corpus's longer TMPDIR; re-landed by 12549d8b. Here the failure is
  # length-dependent in exactly that way (it passes at the daemon's prefix, fails at the corpus's)
  # and the tip is INNOCENT.
  #
  # WHAT THIS ADDS OVER B10/B13, which already stop the wrong revert: without the env fix the walk
  # cannot reproduce the red anywhere, so it names NOBODY and the red stays permanently
  # unattributed — safe, but never diagnosed. This asserts the walk reaches the RIGHT commit.
  ship_stub
  export TMPDIR="$BATS_TEST_TMPDIR"                             # a KNOWN prefix to derive from
  bash "$SUT" --run-if-needed >/dev/null 2>&1 || true
  [ -f "$CC_POSTLAND_DIR/last-green" ]
  # $RUN_TMP adds exactly 20 bytes ("/postland-run." + 6), so a threshold of +5 sits strictly between
  # the two prefixes. DERIVED from the live string — a hardcoded byte count is how a threshold
  # silently stops separating the two things it was chosen to separate.
  printf '@test "len" { [ "${#TMPDIR}" -le %s ]; }\n' "$(( ${#TMPDIR} + 5 ))" > "$R/tests/bad.bats"
  push_commit "THE CULPRIT — fails only at the corpus prefix"
  culprit="$(origin_head)"
  printf 'unrelated\n' > "$R/innocent.txt"
  push_commit "the innocent tip"
  tip="$(origin_head)"
  [ "$culprit" != "$tip" ]                                      # precondition of the entire test
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed    # C29 window 1 — candidate only
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed    # C29 window 2 — reds, then reverts
  [ -s "$REC/ship.argv" ]                                       # something WAS reverted...
  [ "$(ship_field branch)" = "postland-revert-${culprit:0:12}" ] # ...and it was the CULPRIT...
  [ "$(ship_field branch)" != "postland-revert-${tip:0:12}" ]    # ...never the innocent tip
}

@test "C25: the bisect VERB mints its own probe TMPDIR from the corpus template, and leaks neither" {
  # The `bisect` verb (C1) runs with NO corpus, so $RUN_TMP is empty and do_bisect takes its other
  # branch: mint a probe dir from the SHARED template and own the teardown. That branch is reachable
  # only through this verb, so without this test it ships unexercised — and a minted-but-unremoved
  # dir is the leak class this file has already paid for once (the `$( )` worktree-cell leak
  # recorded at BISECT_CULPRIT, which leaked on every call including success and alarmed nothing).
  export TMPDIR="$BATS_TEST_TMPDIR/tb"; mkdir -p "$TMPDIR"
  good="$(origin_head)"
  printf '@test "rec" { printf "%%s\\n" "$TMPDIR" >> "%s/verbtmp.txt"; false; }\n' "$REC" \
    > "$R/tests/bad.bats"
  push_commit "the culprit"
  bad="$(origin_head)"
  rm -rf "${TMPDIR:?}"/*                                        # everything below here is the VERB's
  run bash "$SUT" bisect tests/bad.bats "$good" "$bad"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | tail -1)" = "$bad" ]           # range 1 ⇒ git probes the tip, it
                                                                # reproduces, so a culprit IS named
  probe="$(tail -1 "$REC/verbtmp.txt")"
  case "$probe" in */postland-run.??????) ;; *) false ;; esac    # the corpus's template, not the
  [ "$probe" != "$TMPDIR" ]                                     # bare inherited prefix
  [ -z "$(find "$TMPDIR" -maxdepth 1 -name 'postland-run.*' 2>/dev/null)" ]      # probe dir removed
  [ -z "$(find "$TMPDIR" -maxdepth 1 -name 'postland-bisect.*' 2>/dev/null)" ]   # runner + records too
  [ "$(cells_n)" = "0" ]                                        # ...and the verb's worktree cell
}

# ── C22 pre-corpus whole-tree meta-lints ────────────────────────────────────────
prelint_stub() { # <body> — installs it as the tree's walltime lint and lands it
  mkdir -p "$R/scripts"
  printf '#!/bin/bash\n%s\n' "$1" > "$R/scripts/test-walltime-lint.sh"
  chmod +x "$R/scripts/test-walltime-lint.sh"
  push_commit "prelint fixture"
}

@test "C22: a whole-tree lint RED is a named RED that OUTRANKS a cut, and skips the corpus" {
  prelint_stub 'echo "  RATCHET stale entry"; exit 1'
  tree="$(origin_tree)"
  # a bats stub whose own shape is a CUT (plan, partial progress, SIGKILL): were the lint verdict
  # dropped, this run would be filed "cut" — nothing proven — instead of a named red.
  b="$(stub_bats cutter "printf '1..3\nok 1 a\n'; exit 137")"
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "red" ]
  run jq -r '.failing[0]' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "scripts/test-walltime-lint.sh" ]              # the stamp NAMES the lint
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]
}

@test "C22: OUR OWN lint bound firing is a CUT — a timeout we imposed proves nothing" {
  prelint_stub 'sleep 30'
  tree="$(origin_tree)"
  run env CC_POSTLAND_LINT_TIMEOUT_S=1 bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                                        # never a RED: it forges no finding
  [ "$(pages_n)" = "0" ]
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]                       # ...and never a GREEN either
  # POSITIVE CONTROL: the same lint, failing FAST, is a red — so "cut" above is a statement about
  # the BOUND, not evidence that a lint can never redden a verdict.
  prelint_stub 'exit 1'
  tree2="$(origin_tree)"
  run env CC_POSTLAND_LINT_TIMEOUT_S=30 bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree2.json"
  [ "$output" = "red" ]
}

@test "C22: a lint exit 2 is a NON-VERDICT, never a RED (a check that could not run must not revert)" {
  # Backlog b4e49b4b5014. Both lints publish `0 clean · 1 violation · 2 unusable`, and only 1 is a
  # claim about the TREE. Exit 2 is the fork-pressure case afaf40de carved out INSIDE the lint: a
  # `grep` that cannot run is not a leak. Filing it as FAILING re-creates that conflation one layer
  # out, and here it reaches red_actions — so a check that never ran could auto-revert a good trunk
  # commit. RED-proved: before the fix this stamped `red` naming the lint.
  prelint_stub 'echo "test-walltime-lint: ⛔ UNUSABLE — a predicate failed to run" >&2; exit 2'
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                                        # not a red: it forges no finding
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]                       # ...and not a green either
  # The revert consequence is deliberately NOT asserted here: a revert additionally needs the C20
  # scaffolding (ship_stub + a green baseline, without which there is no bisected culprit and so no
  # revert at all), so a `ship.argv` assertion in THIS fixture would pass whatever the mapping does
  # — vacuous. `verdict != red` is the load-bearing claim; C20 owns "a red reaches the land lane".
  # POSITIVE CONTROL: the same lint exiting 1 IS a red naming it — so "cut" above is a statement
  # about the exit CODE, not evidence that a lint can never redden a verdict.
  prelint_stub 'echo "  RATCHET stale entry"; exit 1'
  tree2="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree2.json"
  [ "$output" = "red" ]
  run jq -r '.failing[0]' "$CC_POSTLAND_DIR/stamps/$tree2.json"
  [ "$output" = "scripts/test-walltime-lint.sh" ]
}

@test "C22: an unexpected lint exit (127 — not executable) is a NON-VERDICT too, never a RED" {
  # The `*)` arm. 126/127/137 are all "the check could not be MADE"; only 1 is a verdict. Without
  # this arm a lint that lost its interpreter would revert a commit for the tree's sins.
  prelint_stub 'exit 127'
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ] || false
  [ ! -f "$CC_POSTLAND_DIR/last-green" ] || false
}

# ── C22b THE INSTRUMENT CHECK — `--selftest` runs here, in its OWN verdict column ─────────────────
# Backlog 76644e76aaae. The prelint used to run the whole-tree SCAN only, so the ~130 cases proving
# these ratchets actually go RED on a new leak and on a stuck entry gated nothing: the bats wrappers
# are partitioned to host-suites.manifest (post-deploy, lagging) and nightly-regression.sh's launchd
# job is staged-not-loaded. The reason it could not simply be added is the whole point of this block:
# a scan's exit 1 means THE TREE is dirty (attributable, revert-eligible) while a selftest's exit 1
# means THE LINT is broken — and mapping the second onto the first lets a broken lint auto-revert a
# commit that never touched it.
selftest_stub() { # <selftest-body> <scan-body> — one stub that answers --selftest and the scan
  # DIFFERENTLY, which is the only shape that can tell the two verdict columns apart. A stub that
  # behaved identically either way would pass whatever the mapping does.
  prelint_stub "if [ \"\${1:-}\" = \"--selftest\" ]; then $1; fi
printf scan >> \"\$PLREC\"; $2"
}

@test "C22b: a lint whose --selftest FAILS is a CUT naming the LINT, and its scan never runs" {
  # The load-bearing case. The scan here would exit 0 — a clean tree by a ratchet that cannot fire,
  # which is the exact shape of a vacuous green. Pre-fix the run stamps GREEN off that scan; the
  # instrument check is what makes "the ratchet does not discriminate" reachable at all.
  selftest_stub 'echo "SELFTEST FAIL: the ratchet does not discriminate"; exit 1' 'exit 0'
  tree="$(origin_tree)"
  run env PLREC="$REC/scanran.txt" bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                                    # never a RED: the tree was not convicted
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]                   # ...and never a GREEN: nothing was proven
  [ ! -f "$REC/scanran.txt" ]                              # the scan was SKIPPED — no red to mint
}

@test "C22b: the CUT says the LINT is broken, not that the TREE is dirty" {
  # The verdict CATEGORY the item asked for. Both halves of the split reach the operator through the
  # same `cut` verdict, so the reason string is the only thing that tells them apart — and the two
  # need opposite responses (fix the lint vs fix the tree). Asserted on the reason, not the verdict.
  selftest_stub 'echo "SELFTEST FAIL: the ratchet does not discriminate"; exit 1' 'exit 0'
  run env PLREC="$REC/scanran.txt" bash "$SUT" --run-if-needed
  [ "${output#*the LINT is broken, not the tree}" != "$output" ]
  # CONTROL — the OTHER cut population must NOT claim the lint is broken. Without this the assertion
  # above could be satisfied by a string emitted on every cut, which would carry no information.
  prelint_stub 'exit 2'
  run bash "$SUT" --run-if-needed
  [ "${output#*the LINT is broken, not the tree}" = "$output" ]
}

@test "C22b: a PASSING --selftest leaves the scan's RED intact (the positive control)" {
  # Without this, "cut" above could mean the instrument check disabled prelint reds altogether
  # rather than routing one specific outcome away from them.
  selftest_stub 'exit 0' 'echo "  RATCHET stale entry"; exit 1'
  tree="$(origin_tree)"
  run env PLREC="$REC/scanran.txt" bash "$SUT" --run-if-needed
  [ -f "$REC/scanran.txt" ]                                # the scan DID run
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "red" ]
  run jq -r '.failing[0]' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "scripts/test-walltime-lint.sh" ]
}

@test "C22b: a --selftest that could not RUN still lets the scan judge — pressure may not disarm the ratchet" {
  # DELIBERATELY NOT SYMMETRIC with the exit-1 case. Exit 2 is the fork-exhaustion case (b4e49b4b5014):
  # if an unrunnable instrument check suppressed the scan, then load — the very condition that
  # produces exit 2 — would silently switch the ratchet off, which is the one failure direction this
  # mechanism exists to prevent. Unproven-but-scanned is fail-closed toward MORE proof.
  selftest_stub 'echo "⛔ UNUSABLE — a predicate failed to run" >&2; exit 2' 'echo "  RATCHET stale entry"; exit 1'
  tree="$(origin_tree)"
  run env PLREC="$REC/scanran.txt" bash "$SUT" --run-if-needed
  [ -f "$REC/scanran.txt" ]                                # the scan ran anyway
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "red" ]                                    # ...and a real violation still convicts
}

@test "C22b: a lint carrying NO --selftest dispatch is scanned as before, never deadlocked" {
  # Same rule as an absent lint: a tree cannot be judged by a check it does not carry. Inventing a
  # non-verdict here would make every custom CC_POSTLAND_PRELINTS list a permanent CUT — no green
  # ever claimable — which is the deadlock shape this file has already paid for twice.
  prelint_stub 'printf scan >> "$PLREC"; echo "  RATCHET stale entry"; exit 1'
  tree="$(origin_tree)"
  run env PLREC="$REC/scanran.txt" bash "$SUT" --run-if-needed
  [ -f "$REC/scanran.txt" ]
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "red" ]                                    # judged on its scan, not stalled
}

# The two halves of the seam are SEPARATE tests, one fixture each, because `--run-if-needed` is
# idempotent on a tree: a second invocation inside one test sees the stamp the first one wrote and
# skips the prelint entirely, so the record reads EMPTY and the assertion fails for a reason that
# has nothing to do with the seam. Both assert on which TOKENS appear rather than on the exact
# string — the requeue loop calls run_target twice in one process, so an `= "scan"` equality reads
# "scanscan". `st` and `scan` share no substring, so presence/absence is exact.
@test "C22b: CC_POSTLAND_PRELINT_SELFTEST=off disables the instrument check" {
  selftest_stub 'printf st >> "$PLREC"; exit 1' 'printf scan >> "$PLREC"; exit 0'
  tree="$(origin_tree)"
  run env PLREC="$REC/off.txt" CC_POSTLAND_PRELINT_SELFTEST=off bash "$SUT" --run-if-needed
  rec="$(cat "$REC/off.txt" 2>/dev/null || true)"
  [ "${rec#*scan}" != "$rec" ] || { echo "off.txt=[$rec] — the scan did not run"; false; }
  [ "${rec#*st}" = "$rec" ] || { echo "off.txt=[$rec] — the selftest ran despite the seam being off"; false; }
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" != "cut" ]                                   # ...so the broken instrument cut nothing
}

@test "C22b: the instrument check is ON by default — the seam must be SET to lose it" {
  # The half that actually matters. A sensor whose shipping path is "off" ships blindness, and this
  # one exists precisely because the proof was running nowhere; the test above would be satisfied by
  # a check that never runs at all.
  selftest_stub 'printf st >> "$PLREC"; exit 1' 'printf scan >> "$PLREC"; exit 0'
  run env PLREC="$REC/on.txt" bash "$SUT" --run-if-needed
  rec="$(cat "$REC/on.txt" 2>/dev/null || true)"
  [ "${rec#*st}" != "$rec" ] || { echo "on.txt=[$rec] — the selftest did NOT run by default"; false; }
  [ "${rec#*scan}" = "$rec" ] || { echo "on.txt=[$rec] — the scan ran after a failed selftest"; false; }
}

@test "C22: the lint runs whole-tree STRICT — an inherited own-set cannot narrow it" {
  # Both lints distinguish own-set ABSENT (judge the whole tree) from set-but-EMPTY (judge
  # nothing) via ${VAR+set}. If the verifier leaked its own environment through, a lander's
  # own-set would silently reduce the trunk verdict to that lander's diff.
  prelint_stub 'printf "own=%s herm=%s scope=%s argv=%s\n" "${CC_WALLTIME_OWN+SET}" "${CC_HERM_OWN+SET}" "${SHIP_LAND_HERM_OWN_SCOPE+SET}" "$*" > "$PLREC"; exit 0'
  run env PLREC="$REC/lintenv.txt" CC_WALLTIME_OWN=tests/someone-elses.bats \
      CC_HERM_OWN=tests/someone-elses.bats SHIP_LAND_HERM_OWN_SCOPE=off \
      bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ -f "$REC/lintenv.txt" ]
  # All three arrived UNSET — that is this test's claim. `argv=` is incidental to it but pinned
  # deliberately: fc2dae62 stopped passing the literal `tests` positional (git-identity-lint resolves
  # its own scan root from $0 and exits 2 "nothing to scan" when handed `tests`, which would turn
  # EVERY run into a CUT). That commit updated the runner, tests/git-identity-lint.bats and the
  # --selftest's "invoked with NO positional" check, but not this line, so trunk went red here.
  [ "$(cat "$REC/lintenv.txt")" = "own= herm= scope= argv=" ]
}

@test "C22: the prelints run in the UTILITY band — a background-clamped parent cannot drag them to PRI 4" {
  # THE DEADLOCK THIS STANDS AGAINST (2026-07-30): the launchd job is ProcessType Background, so
  # absent an EXPLICIT band the prelints inherit PRI 4 (E-core confined) and a ~3s whole-tree lint
  # becomes load-proportional — measured 41s @ load 14.8, against a bound that was then 60s — until
  # it times out and the run logs "nothing proven … no green may be claimed". The green stamp then
  # cannot advance at all, which is the deadlock, and NO test failure ever names it.
  # Reproduced faithfully by running the SUT under `taskpolicy -c background`, exactly as launchd does.
  [ -x /usr/sbin/taskpolicy ] || skip "taskpolicy(8) absent — no bands to assert"
  prelint_stub 'ps -o pri= -p $$ | tr -d " \n" > "$PLREC"; exit 0'
  run env PLREC="$REC/lintpri.txt" /usr/sbin/taskpolicy -c background bash "$SUT" --run-if-needed
  [ -f "$REC/lintpri.txt" ]
  [ "$(cat "$REC/lintpri.txt")" = "20" ]        # utility. PRE-FIX this reads 4 — the inherited band.
  # CONTROL ON THE INSTRUMENT — same reader, same background-clamped parent, WITHOUT the band fix.
  # It must read 4. Absent this, "20" above could be a probe that simply cannot observe a demotion
  # (a green that proves only that ps and tr ran), and the assertion would pass vacuously.
  run /usr/sbin/taskpolicy -c background bash -c 'ps -o pri= -p $$ | tr -d " \n"'
  [ "$output" = "4" ]
}

@test "C22: the taskpolicy-absent path still RUNS the prelint (bash 3.2 empty-array guard)" {
  # LINT_QOS is EMPTY whenever the shared seam is set-but-empty or taskpolicy(8) is missing. This is
  # bash 3.2 under `set -u`, where expanding an empty array unguarded is an unbound-variable DEATH —
  # which would not read as a crash but as rc!=1, i.e. a permanent NON-VERDICT: every prelint
  # "unproven", no green ever claimable. The same deadlock, arriving through the fallback path.
  prelint_stub 'printf ran > "$PLREC"; exit 0'
  run env PLREC="$REC/lintran.txt" CC_POSTLAND_TASKPOLICY_BIN= bash "$SUT" --run-if-needed
  [ -f "$REC/lintran.txt" ]                     # it ran at all
  [ "$(cat "$REC/lintran.txt")" = "ran" ]
  # substring assertion as a LIVE `[ ]` — a non-final `[[ ]]` here would be errexit-exempt and dead
  [ "${output#*unbound variable}" = "$output" ]
}

# ── the retry ladder: a re-run KILLED by a signal is a CUT, never a RED ───────────────────────────
# THE 0-GREEN DEADLOCK, second half (2026-07-31). The 124 case was already handled here; the SIGNAL
# case was not, and it is the one that actually fired. Of 35 flake rows, 34 are `pass-on-retry` or
# `1-of-3`, dominated by `exit 143` (x8) and `exit 137` (x3) at median loadavg 13.9 — suites killed
# by machine pressure on a box with no quiet window. Each kill scored as a genuine failure, two on
# one file minted a "reproducible RED", and 40 of 42 stamps went red with the last green 24h stale,
# so deploy-live sat fail-closed and the live layer fell behind trunk.
#
# Distinct from the C13 cut tests above: those kill the WHOLE corpus run with ZERO `not ok`. This
# drives the LADDER — a real `not ok` engages the retry, and the RETRY is what dies.
stub_ladder_kill() {   # $1 = rc the retries die with; the CORPUS run emits a REAL not ok
  # KEYED ON ARGV, NOT ON A CALL COUNTER — and the counter it replaces was load-bearing, so this is
  # worth stating. The old form latched on "n == 1", which worked only because exactly one call ever
  # needed the corpus TAP. C29 makes the rc-1 case below a TWO-sweep test and the state file persists
  # across sweeps, so window 2 got no TAP at all and cut on `notok == 0` — the right verdict for the
  # wrong reason. The obvious repair (n % 3 == 1, "one corpus + two retries per window") is ALSO
  # wrong, and measured so: the real sequence is FOUR calls, not three —
  #     1: tests/ok.bats              (corpus)
  #     2: -f ^beta$ tests/probe.bats (retry 1, test-granular)
  #     3: tests/probe.bats           (retry 1's WHOLE-FILE fallback — the -f run planned 0 tests)
  #     4: -f ^beta$ tests/probe.bats (retry 2)
  # so `n % 3` re-emitted the TAP at call 4 and turned the rc-0 FLAKE control into a conviction: the
  # control stopped being able to fail for its own reason. Any arithmetic over call counts encodes
  # the ladder's internal fallback behaviour, which is not this fixture's subject and is free to
  # change. What IS stable is what each call is ASKED to run: the corpus runs the tree's suites, and
  # every retry names probe.bats (with -f or, on fallback, without). Discriminating on that is
  # window-agnostic and count-agnostic, and it is the same shape multi_red_bats already uses.
  stub_bats "ladder$1" "
case \"\$1\" in --count) echo 1; exit 0 ;; esac
case \"\$*\" in *probe.bats*) exit $1 ;; esac
printf '1..2\nok 1 alpha\nnot ok 2 beta\n# (in test file tests/probe.bats, line 3)\n'
exit 1"
}

@test "ladder: a retry killed by SIGKILL (137) is a CUT, not a RED" {
  b="$(stub_ladder_kill 137)"
  export CC_POSTLAND_BATS="$b"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                     # THE regression: this read "red"
  [ "$(pages_n)" = "0" ]                    # and a RED page can auto-revert an innocent commit
  run jq -r '.failing | length' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "0" ]                       # nothing may be NAMED as failing on a kill
}

@test "ladder: a retry killed by SIGTERM (143) is a CUT, not a RED" {
  b="$(stub_ladder_kill 143)"
  export CC_POSTLAND_BATS="$b"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]
  [ "$(pages_n)" = "0" ]
}

@test "ladder: a retry that FAILS (rc 1) is still a RED — the fix must not blind the verifier" {
  # The control that keeps the widening honest. If a kill and a genuine failure both became cuts,
  # nothing could ever go red again and the verifier would be decorative.
  b="$(stub_ladder_kill 1)"
  export CC_POSTLAND_BATS="$b"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed           # C29 window 1 — a candidate, not yet a verdict
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                     # rc 1 IS a tree verdict, but one window does not prove it
  second_window                             # window 2 re-convicts the same file
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "red" ]                     # a reproducible failure still convicts
  run jq -r '.failing | length' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" != "0" ]                      # and it NAMES the file
}

@test "ladder: a retry that PASSES (rc 0) is a flake, not a RED (control)" {
  b="$(stub_ladder_kill 0)"
  export CC_POSTLAND_BATS="$b"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "green" ]                   # 1-of-3 ⇒ flake ⇒ the tree is not convicted
}

# ── the retry ladder's BAND — the third site of the same band oversight ───────────────────────────
# C24 band: the ladder's re-run is elevated OUT of the corpus's background clamp into utility. The
# ladder is a DECISION PROCEDURE on a single named test ("costs seconds"), not bulk throughput, and
# it sits on the critical path to a green stamp — the identical argument the prelints already won
# (C22 band, PRI 20 vs 4). Running it in the corpus band de-prioritises rather than de-contends it,
# which moves the environment the WRONG WAY for the failure mode this file measures as dominant:
# 34 of 35 flake rows are pressure kills (exit 143 x8, 137 x3) at median loadavg 13.9. Starved at
# PRI 4 the ladder cannot render a verdict at all — post the signal-widening above those kills
# correctly ABSTAIN, so every run takes the cut path and NO GREEN IS EVER CLAIMABLE. Measured
# 2026-07-31: 45 of 46 stamps carried no green, and the one green was 2 days stale and 318 commits
# behind trunk, so deploy-live sat fail-closed and the live layer froze 122 commits back.
stub_ladder_band() {   # first corpus run emits a REAL not ok; the RETRY records its own PRI
  stub_bats "ladderband" "
case \"\$1\" in --count) echo 1; exit 0 ;; esac
n=\$(cat '$REC/band.n' 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > '$REC/band.n'
if [ \"\$n\" = 1 ]; then
  printf '1..2\nok 1 alpha\nnot ok 2 beta\n# (in test file tests/probe.bats, line 3)\n'
  exit 1
fi
ps -o pri= -p \$\$ | tr -d ' \n' > '$REC/bandpri.txt'
printf '1..1\nok 1 beta\n'
exit 0"
}

@test "C24: the ladder's RETRY runs in the UTILITY band — a background-clamped parent cannot drag it to PRI 4" {
  # Reproduced faithfully by running the SUT under `taskpolicy -c background`, exactly as launchd
  # does (the plist is ProcessType Background), because that inherited clamp IS the defect: absent
  # an explicit band the retry runs at PRI 4 and gets starved into a non-verdict.
  [ -x /usr/sbin/taskpolicy ] || skip "taskpolicy(8) absent — no bands to assert"
  b="$(stub_ladder_band)"
  export CC_POSTLAND_BATS="$b"
  run /usr/sbin/taskpolicy -c background bash "$SUT" --run-if-needed
  [ -f "$REC/bandpri.txt" ]                     # the ladder actually engaged (else vacuous)
  [ "$(cat "$REC/bandpri.txt")" = "20" ]        # utility. PRE-FIX this reads 4 — the inherited band.
  # CONTROL ON THE INSTRUMENT — same reader, same background-clamped parent, WITHOUT the band fix.
  # It must read 4. Absent this, "20" above could be a probe that cannot observe a demotion at all
  # (a green proving only that ps and tr ran), and the assertion would pass vacuously.
  run /usr/sbin/taskpolicy -c background bash -c 'ps -o pri= -p $$ | tr -d " \n"'
  [ "$output" = "4" ]
}

@test "C24: the taskpolicy-absent retry path still RUNS the ladder (bash 3.2 empty-array guard)" {
  # RETRY_QOS must never expand EMPTY: this is bash 3.2 under `set -u`, where an unguarded empty
  # array expansion is an unbound-variable DEATH — which would not read as a crash but as rc!=1,
  # i.e. a permanent NON-VERDICT, the same deadlock arriving through the fallback path. The array
  # therefore keeps `nice` as its floor even when taskpolicy(8) is gone.
  b="$(stub_ladder_band)"
  export CC_POSTLAND_BATS="$b" CC_POSTLAND_TASKPOLICY_BIN=
  run bash "$SUT" --run-if-needed
  [ -f "$REC/bandpri.txt" ]                     # the retry ran at all
  # substring assertion as a LIVE `[ ]` — a non-final `[[ ]]` here would be errexit-exempt and dead
  [ "${output#*unbound variable}" = "$output" ]
}

# ── C28 ADMISSION: the verifier is EXEMPT from cc-bats' EX_TEMPFAIL deferral ─────────────────────
# $BATS_BIN defaults to the bare name `bats`, which PATH-resolves to ~/.claude/bin/cc-bats — an
# ADMISSION WRAPPER that runs NOTHING and exits 75 when >=CC_BATS_MAX_ROOTS other bats roots are live
# AND load/core is over the ceiling. 75 is outside the {0,1} set that speaks about the tree, so the
# ladder abstains, LADDER_UNPROVEN fires, and the ENTIRE sweep stamps `cut` — no green stamp, so
# deploy-live stays fail-closed. MEASURED on the live host, runner.log 2026-08-07T23:29:53Z:
#   `ladder UNPROVEN for tests/cc-backlog-compact-race.bats — the re-run exited 75` then
#   `CUT 488742fcb66a ... consecutive=2`. A ~3.4h sweep discarded to skip ONE ~1s re-run.
#
# Distinct from every non-verdict above it: 124/137/143/126/127 are facts about the MACHINE that a
# re-run cannot undo, so abstaining is correct. 75 means NOTHING WAS ATTEMPTED — the one abstaining
# code the verifier can cure, and it cures it by declaring itself exempt (R7: the singleton verifier
# is the one party that may never wait; it deleted its OWN gate_admit() for that reason, then reached
# admission control anyway through a bare NAME nothing in the file accounted for).
#
# The stub refuses EXACTLY as cc-bats does — unless the exemption is in its environment. That makes
# this its own mutation control: delete the `export CC_BATS_MAX_ROOTS=0` from the SUT and the stub
# refuses, the ladder abstains, and the verdict flips green -> cut. Nothing else in the fixture moves.
stub_ladder_admit() {   # refuses with 75 on the RETRY unless CC_BATS_MAX_ROOTS=0 reaches it
  stub_bats "ladderadmit" "
case \"\$1\" in --count) echo 1; exit 0 ;; esac
n=\$(cat '$REC/admit.n' 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > '$REC/admit.n'
if [ \"\$n\" = 1 ]; then
  printf '1..2\nok 1 alpha\nnot ok 2 beta\n# (in test file tests/probe.bats, line 3)\n'
  exit 1
fi
printf '%s' \"\${CC_BATS_MAX_ROOTS-UNSET}\" > '$REC/admit.seen'
if [ \"\${CC_BATS_MAX_ROOTS-UNSET}\" != \"0\" ]; then
  echo 'cc-bats: REFUSED — 2 concurrent bats execution root(s)' >&2
  exit 75
fi
printf '1..1\nok 1 beta\n'
exit 0"
}

@test "C28: the ladder's re-run is EXEMPT from cc-bats admission — a deferral cannot cut the sweep" {
  b="$(stub_ladder_admit)"
  export CC_POSTLAND_BATS="$b"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  [ -f "$REC/admit.seen" ]                      # the ladder actually engaged (else vacuous)
  [ "$(cat "$REC/admit.seen")" = "0" ]          # PRE-FIX this reads UNSET — the whole defect
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "green" ]                       # PRE-FIX: "cut" — the retry was refused, never run
  [ "$(pages_n)" = "0" ]
}

# ── THE CUT MESSAGE MUST NAME THE BOUND THAT ACTUALLY FIRED (2026-08-16) ─────────────────────────
# retry_once runs under TWO bounds — FILE_TO (300 s) for the single named test, RETRY_TO (5400 s)
# for the whole-file fallback — and rc 124 is identical from either. The message named RETRY_TO
# unconditionally, so on the common path it reported a bound that had never run: sixteen consecutive
# live cuts logged "our own 5400s bound fired" for tests/autonomy-sweep.bats inside runs whose OWN
# totals were run_s=3364 and run_s=3538. A 5400 s bound cannot fire in a 3364 s run, and the wrong
# figure is not cosmetic — 5400 s says "a suite far too slow to re-run" and sent a session hunting a
# 90-minute suite that measures 77 s / 55 green at that exact band, while 300 s says "one test
# overran", which is a different investigation entirely.
#
# TWO cases, because ONE would pass against a constant just as well as against the out-parameter.
# The stubs differ in exactly one property — whether the `-f` leg PLANS a test — which is precisely
# what decides whether retry_once returns on the test leg or falls through to the file leg.
stub_ladder_124() {   # $1=plan-on-filter (1 = the -f leg returns a verdict, 0 = it falls through)
  stub_bats "ladder124$1" "
case \"\$1\" in --count) echo 1; exit 0 ;; esac
case \"\$*\" in
  *-f*probe.bats*) [ '$1' = 1 ] && printf '1..1\n'; exit 124 ;;
  *probe.bats*)    exit 124 ;;
esac
printf '1..2\nok 1 alpha\nnot ok 2 beta\n# (in test file tests/probe.bats, line 3)\n'
exit 1"
}
stub_ladder_slow() {   # the -f leg PLANS, then outlives the bound ⇒ OUR timeout really does cut it
  stub_bats "ladderslow" "
case \"\$1\" in --count) echo 1; exit 0 ;; esac
case \"\$*\" in *probe.bats*) printf '1..1\n'; sleep 30 ;; esac
printf '1..2\nok 1 alpha\nnot ok 2 beta\n# (in test file tests/probe.bats, line 3)\n'
exit 1"
}

@test "the ladder's cut names the LEG, and a fast 124 is the CHILD's code, not our bound" {
  b="$(stub_ladder_124 1)"
  export CC_POSTLAND_BATS="$b"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                                        # unchanged: 124 still proves nothing
  grep -q 'the single named test' "$CC_POSTLAND_DIR/runner.log"
  grep -q "CHILD's own exit code" "$CC_POSTLAND_DIR/runner.log"
  # THE REGRESSION, pinned as an absence: our bound never came due, so it may not be claimed —
  # and the 5400s file bound never ran at all. Sixteen live cuts asserted exactly that sentence.
  run grep -qE 'our own (300|5400)s bound fired' "$CC_POSTLAND_DIR/runner.log"
  [ "$status" -ne 0 ]
}

@test "the ladder's cut names the LEG: the FILE leg once the test leg falls through" {
  b="$(stub_ladder_124 0)"                                     # `1..0` ⇒ no verdict ⇒ fall through
  export CC_POSTLAND_BATS="$b"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]
  grep -q 'the whole file' "$CC_POSTLAND_DIR/runner.log"
  run grep -q 'the single named test' "$CC_POSTLAND_DIR/runner.log"
  [ "$status" -ne 0 ]
}

@test "…and when our bound REALLY fires, it is claimed — with the elapsed that earns the claim" {
  # The other half of the discriminator. Without this case the two above are satisfied by a message
  # that can never claim the bound at all, which would be the same blindness pointing the other way.
  b="$(stub_ladder_slow)"
  export CC_POSTLAND_BATS="$b"
  export POSTLAND_FILE_TIMEOUT_S=2                             # so the cut costs 2s, not 300
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]
  grep -q 'our own 2s bound fired on the re-run of the single named test' "$CC_POSTLAND_DIR/runner.log"
  run grep -q "CHILD's own exit code" "$CC_POSTLAND_DIR/runner.log"
  [ "$status" -ne 0 ]
}

stub_ladder_admit75() {   # refuses with 75 on the RETRY whatever the environment says
  # A HELPER, not an inline heredoc in the test body, for a mechanical reason: the stub's own source
  # contains `n=$((n+1))`, and the bats dead-assertion ratchet reads any arithmetic inside an @test
  # block as a statement whose exit status errexit cannot reach. Inside a quoted stub string it is
  # neither — but the lint scans text, not scope, so the fix is to put it where its two siblings
  # already live (stub_ladder_kill, stub_ladder_admit). The ratchet's suggested fixer is the WRONG
  # remedy here: it rewrites assertions, and this line is stub source code, not an assertion.
  stub_bats "ladderadmit75" "
case \"\$1\" in --count) echo 1; exit 0 ;; esac
n=\$(cat '$REC/a75.n' 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > '$REC/a75.n'
if [ \"\$n\" = 1 ]; then
  printf '1..2\nok 1 alpha\nnot ok 2 beta\n# (in test file tests/probe.bats, line 3)\n'
  exit 1
fi
exit 75"
}

@test "C28: POSITIVE CONTROL — an UNCONDITIONAL 75 still abstains, and names itself a DEFERRAL" {
  # The exemption must not blind the runner to a refusal it genuinely could not prevent. A stub that
  # refuses whatever the environment says stands in for the exemption failing to reach the child; the
  # run must still take the CUT path (never a RED — nothing ran, so nothing was proven) AND the log
  # must NAME it. Without the naming arm this falls into the generic "exited 75" message, which is
  # exactly what sent the 2026-08-07 investigation hunting a slow test that had never been slow.
  b="$(stub_ladder_admit75)"
  export CC_POSTLAND_BATS="$b"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                         # nothing ran ⇒ nothing proven; never a RED
  [ "$(pages_n)" = "0" ]
  run grep -c "ADMISSION DEFERRAL" "$CC_POSTLAND_DIR/runner.log"
  [ "$output" != "0" ]                          # PRE-FIX: the generic "exited 75 — not a tree verdict"
}

stub_admit_corpus() {   # records what EVERY call site sees; refuses unless the exemption reached it
  stub_bats "admitcorpus" "
case \"\$1\" in --count) echo 1; exit 0 ;; esac
printf '%s\n' \"\${CC_BATS_MAX_ROOTS-UNSET}\" >> '$REC/corpus.seen'
if [ \"\${CC_BATS_MAX_ROOTS-UNSET}\" != \"0\" ]; then exit 75; fi
printf '1..1\nok 1 alpha\n'
exit 0"
}

@test "C28: the exemption is EXPORTED, so it reaches the corpus and do_bisect, not just the ladder" {
  # Scope assertion. SIX executing $BATS_BIN sites exist — the corpus in both shapes (bounded, and the
  # stall-watched leg), confirm_hang's per-file re-run, both retry_once legs, and do_bisect's generated
  # probe runner — so a per-prefix fix would immunise only the ones someone remembered. The corpus run
  # is the one that matters most: refused THERE, the TAP holds cc-bats' stderr, the `not ok` count is
  # 0, and C13 case (a) cuts the sweep before the ladder ever engages.
  b="$(stub_admit_corpus)"
  export CC_POSTLAND_BATS="$b"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  [ -f "$REC/corpus.seen" ]
  run grep -c 'UNSET' "$REC/corpus.seen"
  [ "$output" = "0" ]                           # NO call site saw it unset
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "green" ]                       # PRE-FIX: "cut" — the corpus itself was refused
}

# ── C4b: the stamp carries the DENOMINATOR of the population it judged ────────────────────────────
stub_pass() { stub_bats "pass" "
case \"\$1\" in --count) echo 1; exit 0 ;; esac
printf '1..1\nok 1 alpha\n'
exit 0"; }

@test "C4b: a stamp records the corpus SIZE, so a verdict cannot hide a collapsed corpus" {
  # A verdict without the size of the population it judged is not auditable:
  # {"verdict":"green","failing":[]} reads identically whether the whole corpus passed or the corpus
  # collapsed to a handful and passed BY ABSENCE. Measured cost 2026-07-31: clearing the single green
  # stamp in 46 of being a vacuous partial run required cross-reading runner.log for its `corpus:`
  # line — a file rotated on a different schedule from the stamps it is needed to explain.
  b="$(stub_pass)"
  export CC_POSTLAND_BATS="$b"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "green" ]
  run jq -r '.suites' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" != "null" ]                       # PRE-FIX: the field does not exist at all
  [ "$output" -ge 1 ]                           # and it counts something real
}

# ── C9b: last-green is rendered WITH its tree-keyed stamp resolved ────────────────────────────────
# THE MISDIAGNOSIS THIS STANDS AGAINST (2026-07-31). `last-green` holds a COMMIT sha; the stamp store
# is keyed by TREE sha. Printing the commit alone invites the one wrong inference the store's shape
# makes available: a reader looks for stamps/<that-sha>.json, does not find it, and concludes the
# pointer is DANGLING. That inference was drawn and acted on — it became the headline finding of a
# diagnosis doc and was filed as a standalone bug — when the pointer was correct, the stamp existed,
# and it was green under its TREE name. No test could fail, because nothing asserted the rendering.
@test "C9b: status resolves last-green to its TREE-keyed stamp, so a commit sha cannot read as dangling" {
  b="$(stub_pass)"
  export CC_POSTLAND_BATS="$b"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  [ -f "$CC_POSTLAND_DIR/stamps/$tree.json" ]
  run bash "$SUT" status
  [ "$status" -eq 0 ]
  # the COMMIT (what the pointer holds) and the TREE (what the stamp is named) must BOTH appear, or
  # the reader is left to guess the hop that produced the whole misdiagnosis. Both needles are
  # computed into variables and quoted INSIDE the ${..} pattern: an unquoted expansion there is
  # taken as a GLOB (SC2295), which for a hex sha happens to be harmless and would rot the moment
  # the needle carried a metachar.
  commit12="$(git -C "$CC_POSTLAND_REPO" rev-parse origin/main | cut -c1-12)"
  tree12="$(printf '%s' "$tree" | cut -c1-12)"
  [ "${output#*"$commit12"}" != "$output" ]
  [ "${output#*"$tree12"}" != "$output" ]
  [ "${output#*green}" != "$output" ]           # and the verdict READ OFF DISK, not implied
}

@test "C9b: a GC'd stamp renders MISSING — status verifies the file instead of implying health" {
  # Verify-before-print, not decorate-before-print. If the stamp is gone, a plausible-looking sha
  # must not be allowed to stand in for a record that no longer exists — that is the difference
  # between a claimed outcome and a checked one.
  b="$(stub_pass)"
  export CC_POSTLAND_BATS="$b"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  rm -f "$CC_POSTLAND_DIR/stamps/$tree.json"    # GC, exactly as the real store ages out
  run bash "$SUT" status
  [ "$status" -eq 0 ]
  [ "${output#*MISSING}" != "$output" ]         # PRE-FIX: prints the bare sha and reads healthy
  # Must NOT claim a verdict off a deleted record. Asserted on the verdict IN POSITION (".json
  # green") rather than the bare word: the field LABEL is `last-green`, so a substring test for
  # "green" can never be absent and would fail this test no matter how the SUT behaves — an
  # assertion that cannot pass is as useless as one that cannot fail.
  [ "${output#*.json green}" = "$output" ]
}

# ── C30 ONE TAP grammar: `notok > 0` must IMPLY `tap_done > 0` ───────────────────────────────────
# tap_done required the result line's <N> (`^(ok|not ok) [0-9]+`); classify_failures' failure count
# did not (`^not ok`); the awk pairing a failure with its file diagnostic required neither. Three
# spellings of one grammar, and the loosest decided whether the tree was RED. So one TAP could read
# as BOTH "0 tests completed" — which is what the stall watcher cuts on — AND "a not-ok exists",
# which is what branch (b) convicts on. runner.log 2026-07-30T05:47:21Z (9586f1ac51f5) and 06:04:21Z
# (4399852f21c2) are that pair: `STALL … at test 0` then `RED failing=tests/ retries=0`, an item
# pointing at a DIRECTORY and a bisect that can hand auto_revert a culprit off a run in which no
# test failed. AUTOREVERT defaults on.
#
# THE rc AXIS IS DELIBERATELY HELD AT 1. C13c already routes rc∉{0,1} to a cut, so a fixture that
# stalled or was killed would pass here through THAT fix and prove nothing about this one. At rc 1
# /Users/chrisren/.claude/bin/cc-bats is genuinely saying "something failed", the C13c guard is inert by construction, and the ONLY
# thing standing between these four shapes and `failing=tests/` is the grammar.
#
# THE DISCRIMINATING CONTROL IS ALREADY IN THIS SUITE and must stay green: "C13b: a not-ok with NO
# file diagnostic stays RED and carries the test NAME" drives `not ok 1 boom` at rc 1 — a WELL-FORMED
# result line, same branch, same rc, and it reds in ONE sweep (branch (b) returns before the ladder,
# so C29's two-window rule never applies to it). The <N> is the only axis between it and the four
# below, so a fix that merely stopped convicting would take C13b red.

# `not ok` truncated mid-write · a torn digit · a PREFIX OF A WORD · stderr spliced into the line
# (the TAP is captured `2>&1`, so an unprefixed write from a test's background child lands raw).
# The payload goes through a QUOTED heredoc so a shape carrying `:` or spaces reaches the TAP
# verbatim — an approximation mangled by the fixture would test a shape the defect never saw.
c30_shape_is_not_a_verdict() {   # $1 = the TAP line to plant, verbatim
  fake="$BATS_TEST_TMPDIR/bats-c30"
  { printf '#!/bin/bash\n[ "$1" = "--version" ] && { echo "Bats 1.13.0"; exit 0; }\necho "1..1"\n'
    printf 'cat <<%sTAPEOF%s\n' "'" "'"
    printf '%s\n' "$1"
    printf 'TAPEOF\nexit 1\n'
  } > "$fake"
  chmod +x "$fake"
  tree="$(origin_tree)"
  run env CC_POSTLAND_BATS="$fake" bash "$SUT" --run-if-needed
  s="$CC_POSTLAND_DIR/stamps/$tree.json"
  [ -f "$s" ]                                              # a stamp must exist either way
  run jq -r '.verdict' "$s"
  [ "$output" != "red" ]                                   # THE defect: this was `red`
  run grep -c 'failing=tests/' "$CC_POSTLAND_DIR/runner.log"
  [ "$output" = "0" ]                                      # reachable from branch (b) and nowhere else
  [ "$(pages_n)" = "0" ]                                   # C10: pages are RED-only
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]                   # and a non-verdict earns nothing either
}

@test "C30: a TAP line truncated mid-write (\`not ok\`) is not a failing test" {
  c30_shape_is_not_a_verdict 'not ok'
}

@test "C30: a torn digit (\`not ok3 …\`) is not a failing test" {
  c30_shape_is_not_a_verdict 'not ok3 squashed'
}

@test "C30: \`not okay …\` is a PREFIX OF A WORD, not a failing test" {
  c30_shape_is_not_a_verdict 'not okay then'
}

@test "C30: stderr spliced into the line (\`not okcorpus: …\`) is not a failing test" {
  c30_shape_is_not_a_verdict 'not okcorpus: 3 tree suites, 0 host'
}

# The INVARIANT itself, read LIVE off the SUT — not a copy of it. Recording only the four
# consequences above would leave "one definition" unfalsifiable: a future edit could re-diverge the
# two readers on a FIFTH shape and every test here would stay green. This asserts the structural
# property that makes the whole class unreachable — every line the failure pattern matches is a line
# the completed-test pattern matches too, so `notok > 0` implies `tap_done > 0`.
@test "C30: the failure grammar is a strict SUBSET of the completed-test grammar" {
  done_re="$(sed -n "s/^TAP_DONE_RE='\(.*\)'.*/\1/p" "$SUT" | head -1)"
  notok_re="$(sed -n "s/^TAP_NOTOK_RE='\(.*\)'.*/\1/p" "$SUT" | head -1)"
  [ -n "$done_re" ]                       # absent ⇒ fail by NAME, never vacuously
  [ -n "$notok_re" ]
  corpus="$BATS_TEST_TMPDIR/c30-corpus.tap"
  printf '1..6\nok 1 healthy pass\nnot ok 2 healthy fail\nnot ok\nnot ok3 squashed\nnot okay then\nnot okcorpus: 3 suites\n' > "$corpus"
  # Every NOTOK line must also be a DONE line ⇒ subtracting DONE from NOTOK leaves nothing.
  run bash -c "grep -aE \"\$1\" \"\$2\" | grep -avE \"\$3\" | wc -l | tr -d ' '" _ "$notok_re" "$corpus" "$done_re"
  [ "$output" = "0" ]
  # ...and the control: the corpus DOES contain lines the loose old pattern would have counted,
  # so a SUT that simply matched nothing at all could not pass the assertion above by vacancy.
  run bash -c "grep -acE \"\$1\" \"\$2\"" _ "$notok_re" "$corpus"
  [ "$output" = "1" ]                     # exactly the ONE well-formed `not ok 2 …`
  run bash -c "grep -ac '^not ok' \"\$1\"" _ "$corpus"
  [ "$output" = "5" ]                     # the old pattern counted FIVE — four of them torn
}

# ── C18b: the host-manifest SPAN CLAUSE of --falsify-red, at the size where its old spelling broke ──
# WHY BEHAVIOURAL ARMS AND NOT SPELLING ONES: a test that greps the SUT for `case`, or for the
# ABSENCE of `grep -q`, dies the day someone rewords the fix and says nothing about the property
# that matters (memory: control-calibrated-to-implementation-decays). These two drive the REAL
# `--falsify-red` verb end to end and assert its ANSWER, so any implementation that answers
# correctly passes and any early-exiting consumer inside that pipeline fails.
#
# THE FIXTURE SIZE IS TAKEN FROM A MEASUREMENT, NOT PICKED — and it is taken on the quantity that
# actually decides. Measured 2026-08-27, 20 trials per cell on the real extracted line: holding the
# PRODUCER constant at 199,968 B and varying only the fraction of lines surviving `sed`+`tr`, the
# clause answers correctly 20/20 at 2,157 / 4,110 / 12,015 B of POST-REDUCTION stream and wrongly
# 20/20 at 21,873 B and above. So the manifest built below is sized by what reaches grep, not by its
# own byte count: the same clause is correct 20/20 on a 200,000-byte RAW manifest that is 96% header
# comment. It normalises to >=60,000 B here, nearly 3x into the always-wrong band, so a re-introduced
# `grep -q` fails this EVERY run rather than one in twenty. The needle is the FIRST entry, which is
# where an early-exiting grep exits soonest and the producer has most left to write.
mk_big_manifest() {                       # $1 = repo-relative suite to place FIRST (the needle)
  local i n=3000
  mkdir -p "$R/scripts"                   # setup() mints only $R/tests; the manifest lives elsewhere
  { printf '# host suites — %s padding entries follow the needle\n' "$n"
    printf '%s\n' "$1"
    for (( i=0; i<n; i++ )); do printf 'tests/pad-%04d-aaaaaaaaaaaaaaaaaaaa.bats\n' "$i"; done
  } > "$R/scripts/host-suites.manifest"
}

@test "C18b: a host suite IN the manifest answers 'could not ask' (2) at a normalised feed past the measured SIGPIPE floor" {
  local red lg norm
  red="$(origin_head)"                                     # the accused commit
  printf '@test "h" { true; }\n' > "$R/tests/hostonly.bats"
  mk_big_manifest tests/hostonly.bats
  push_commit big-manifest
  lg="$(origin_head)"
  mkdir -p "$CC_POSTLAND_DIR"; printf '%s' "$lg" > "$CC_POSTLAND_DIR/last-green"
  # The fixture must reach the regime it claims to, and the assertion is on the NORMALISED size —
  # the quantity the measurement above says decides — never on the file size, which does not.
  norm="$(git -C "$R" show "$lg:scripts/host-suites.manifest" | sed 's/#.*//' | tr -d '[:blank:]' | wc -c | tr -d ' ')"
  [ "$norm" -ge 60000 ]
  # Pin the branch under test: without ancestry the verb returns 1 for an unrelated reason and this
  # arm would pass while never reaching the span clause at all.
  git -C "$R" merge-base --is-ancestor "$red" "$lg"
  run bash "$SUT" --falsify-red tests/hostonly.bats "$red"
  [ "$status" -eq 2 ]        # C18: excluded from the corpus ⇒ the green cannot speak about it
}

@test "C18b control: a suite ABSENT from that same large manifest still retracts (0), so the arm above cannot pass by always answering 2" {
  local red lg
  red="$(origin_head)"
  printf '@test "t" { true; }\n' > "$R/tests/treeonly.bats"
  mk_big_manifest tests/hostonly.bats                      # the needle is a DIFFERENT suite
  push_commit big-manifest-neg
  lg="$(origin_head)"
  mkdir -p "$CC_POSTLAND_DIR"; printf '%s' "$lg" > "$CC_POSTLAND_DIR/last-green"
  git -C "$R" merge-base --is-ancestor "$red" "$lg"
  run bash "$SUT" --falsify-red tests/treeonly.bats "$red"
  [ "$status" -eq 0 ]        # in the corpus AND present at the green ⇒ the premise really is gone
}
