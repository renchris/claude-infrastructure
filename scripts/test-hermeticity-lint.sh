#!/bin/bash
# test-hermeticity-lint — a RATCHET on test-suite hermeticity.
#
# WHY: a bats suite that does not fixture $HOME runs its subject against the OPERATOR'S REAL state —
# ~/.claude/autonomy/idl.jsonl, ~/.reso ledgers, ~/.claude/mailbox. Two costs, both observed
# (2026-07-25 flaky-gate sweep): the suite MUTATES live state (404 stray idl.jsonl lines traced to
# one unfixtured suite), and it READS live state, so its result depends on whatever the desk happens
# to be doing — the textbook flake. $HOME is the single highest-leverage seam because nearly every
# tool in this repo resolves its state dir under it.
#
# WHY A RATCHET AND NOT A FLAG-DAY: 109 of 118 suites are unfixtured today. Fixing them all at once
# is a bigger change than anyone will review honestly, and a lint nobody can turn on is worth zero.
# So: the existing 109 are grandfathered by name, and the rule binds only where it is free — NEW
# suites. The list can only SHRINK. Fixing a suite is therefore a two-line change (fixture $HOME,
# delete its allowlist line) and the lint FAILS if you fixture one and forget to delete the line,
# which is what stops a ratchet from silently becoming a permanent exemption list.
#
# RULE 1 ($HOME): a suite is hermetic iff its setup() or setup_file() body sets a fixture HOME
# (`export HOME=` or `HOME="$BATS...`). Per-test HOME does not count — it leaves every OTHER test
# in the file pointed at live state, which is exactly the failure this catches.
#
# RULE 2 (the fire capacity gate) — the SAME CLASS, found 2026-07-29 and folded into this ratchet
# rather than given a guard of its own, because the failure, the remedy and the ratchet contract are
# identical; only the seam differs. handoff-fire.sh's `capacity_gate()` (scripts/handoff-fire.sh,
# `CC_FIRE_CAPACITY_GATE`) reads LIVE `sysctl vm.loadavg` and REFUSES a net-new fire at >= 2.0
# load/core (exit 9). This box sits permanently at 3.4-7.3/core. So a suite that exercises a net-new
# fire WITHOUT pinning the gate off does not test its subject at all: it reads AMBIENT MACHINE LOAD
# and goes red-by-load — the same "result depends on whatever the desk happens to be doing" flake
# that rule 1 exists to kill. Proven two-sided at 3.39/core on tests/fire-engagement.bats (ambient ->
# `not ok 14`; `CC_FIRE_CAPACITY_GATE=off` -> `ok 14`).
#   A suite is compliant iff it does NOT reference handoff-fire at all (out of scope — never
#   flagged), or its setup()/setup_file() BODY contains `CC_FIRE_CAPACITY_GATE=off` (export or
#   inline env). Per-test pinning does NOT count, for rule 1's reason verbatim: it leaves every
#   other test in the file reading ambient state.
#   Rule 2 carries its OWN grandfather list (EMBEDDED_FIRE_ALLOWLIST), separate from rule 1's and
#   under the same contract — ONLY EVER DELETE LINES; pinning a suite without deleting its line is
#   a RED, which is what stops a ratchet from decaying into a permanent exemption list.
#
# RULE 3 (the orphan-close arming lever) — the SAME CLASS AGAIN, found 2026-07-30. Rule 2 taught
# that a lever the OPERATOR flips machine-wide silently rewrites what a suite is testing; rule 3 is
# that lesson applied to the one other such lever in this tree. `~/.zshrc` sources
# `~/.claude/autonomy/watchdog.env`, which carries `export LCW_ORPHAN_CLOSE=1` (armed
# 2026-07-29T20:35) — the lever that ARMS lead-crash-watchdog.sh's orphaned-pane close leg. Every
# shell that sources the profile, bats included, therefore hands an ARMED actuator to any suite
# exercising that leg, and its DEFAULT-OFF tests stop testing the default and start testing this
# box. Proven two-sided on tests/lead-crash-close-panes.bats: ambient -> `not ok 4` and `not ok 5`
# (4/4, foreground and background band alike); `unset LCW_ORPHAN_CLOSE` in setup() -> 18/18.
#   ASYMMETRY WITH RULE 2, deliberate: rule 2 demands one specific value (`=off`) because only that
#   value detaches the subject from live load. Here ANY deterministic position in setup() — `unset`,
#   `=0`, or a fixture's own `=1` — detaches it; what is forbidden is INHERITING one. So the
#   predicate asks whether the suite took a position at all, not which.
#   SCOPED BY THE LEG the lever gates (`--close-panes`), never by whether the suite happens to
#   mention the lever: a suite that never names LCW_ORPHAN_CLOSE is precisely the one that goes
#   ambient-red, so keying on the mention would exempt the worst case.
#   Rule 3's grandfather list (EMBEDDED_ORPHAN_ALLOWLIST) ships EMPTY — the tree was measured at the
#   last possible moment and exactly one suite is in scope, and it pins. A ratchet that starts empty
#   can only stay empty.
#
# RULE 4 (the embedded selftest) — not a fourth ambient INPUT but a fourth POPULATION, and the one
# rules 1-3 are structurally blind to. Their scan is `for f in "$dir"/*.bats`, so the only test
# harness this file has ever judged is a bats suite. Roughly fifty tools in bin/, scripts/ and
# hooks/ ship an EMBEDDED selftest instead of (or as well as) a suite — `cc-dispatch selftest`
# RED-proves 142 branches and owns no .bats file of its own — and every one of them was outside the
# ratchet entirely. Reported 2026-07-30 as a spillover from backlog f7abcbdee98c, where a selftest
# went RED in 2 of 4 CONCURRENT runs: two runs of the same harness collided on a scratch path that
# was the same string both times.
#   That is rule 1's failure with the seam moved: the result depends on what else is running. The
#   difference is only that a bats suite inherits an ambient $HOME while a selftest names its own
#   scratch dir — so the compliant position is not "fixture $HOME" but "make the path PER-RUN
#   UNIQUE", which on this box means `mktemp`.
#   A selftest is compliant iff its region (a) names no CONSTANT /tmp-family path in a
#   state-bearing position — an assignment, a redirect target, or an argument to mkdir/touch/tee/
#   install/cp/mv/rm — and (b) if it creates scratch state at all, obtains that state from
#   `mktemp`. (b) is what catches a constant path that does not live under /tmp; (a) is what
#   catches a `mktemp` that is present but bypassed. A selftest that creates nothing cannot
#   collide and is never flagged — that scoping is why the "creates" probe exists.
#   MEASURED BEFORE IT WAS WRITTEN, against trunk at the last possible moment, for the reason rules
#   2-3 record: 45 extractable selftest regions, ZERO violations of either half. So RULE 4's
#   grandfather list (EMBEDDED_SELFTEST_ALLOWLIST) ships EMPTY and, like rule 3's, should never
#   gain a line — a NEW selftest is one that can `mktemp` from the start.
#   ACCEPTED FLOOR, stated rather than hidden. The scan set is exactly `bin/*`, `scripts/*.sh` and
#   `hooks/*.sh` — flat globs, so a selftest that lands in `tools/` or in a subdirectory is not
#   reached (measured 2026-07-31: no shell file under tools/ ships one). A region is recognised in
#   three shapes — a `selftest()` / `cmd_selftest()` function, and the
#   `if [ "${1:-}" = "--selftest" ]` block. A tool that instead sets a flag
#   (`--selftest) MODE=selftest`) has no delimited region to read and is not matched; a tool that
#   `exec bats <suite>` (bin/cc-classify, bin/cc-reaper) is already covered by rules 1-3 through
#   that suite.
#   THE FLOOR IS GUARDED, NOT MERELY DOCUMENTED — by a positive control on the extractor rather
#   than by a count. THIS script ships an embedded selftest by construction, so wherever it sits
#   inside the scanned root the extractor must find it; if it cannot see its own, it is broken and
#   the pass is a LOUD non-verdict instead of a vacuous green. A COUNT cannot say that: the first
#   version of this guard was `seen < 20`, calibrated against the 45 measured here, and it turned
#   every SMALLER tree into a non-verdict — including the fixture repos ship-land's own tests land,
#   whose scripts/ holds a single file. That collides with this repo's standing rule that a tree is
#   judged by the ratchet it SHIPS and must never become unlandable for being small. Absent the
#   anchor, `seen` may legitimately be 0 and "clean" is the honest answer. Partial collapse — one
#   of the three shapes breaking while another still matches — is caught where it belongs, by the
#   per-shape fixtures in --selftest, which is also calibration-free.
#
# RULE 5 (the non-$HOME seam) — rule 1's failure with the seam moved, and the one rule 1 is blind to
# BY CONSTRUCTION. Rule 1 asks a single question: does setup() fixture $HOME? A suite can answer YES
# from the day it was written and STILL run against the operator's live machine, because a subject's
# state does not have to resolve under ~. Two shapes do not, and both are measured, not supposed:
#
#   5a  an ABSOLUTE /tmp-family default.  bin/cc-blockers has PERMPEND_DIR="${CC_PERMPEND_DIR:-
#       /tmp/cc-permission-pending}". A fixtured $HOME does not redirect that one character.
#   5b  a BARE NAME resolved on PATH, in command position.  bin/cc-blockers has
#       ACCOUNTS_BIN="${CC_BLOCKERS_ACCOUNTS_BIN:-claude-accounts}" and then runs "$ACCOUNTS_BIN" —
#       so the suite EXECUTES the operator's DEPLOYED tool (memory
#       unfixtured-sensor-executes-the-deployed-subject).
#
# THE INCIDENT THAT GENERATED IT (a514d3b0, 2026-08-06): tests/cc-relogin-status.bats fixtured $HOME
# in setup() from birth. It nonetheless counted the operator's LIVE pending approvals — every
# session waiting on a permission prompt added a `permission-pending` row to the same --json array
# tests 21/22/23 asserted `length == 2` on, and a board with rows has no all-clear path, which is
# 27. Four tests red on trunk, reproduced on a pristine detached origin/main with no local diff. The
# same setup() had a second, latent breach of shape 5b: it EXECUTED the deployed claude-accounts
# once per test. THIS LINT REPORTED THAT SUITE CLEAN BEFORE AND AFTER THE FIX — rule 1 asks about
# $HOME and nothing else, so neither seam was inside anything it could see.
#
# WHY THE REMEDY IS ALWAYS SAFE, which is what makes an imprecise rule affordable here. Rules 2-4
# demand a specific position because a wrong one changes what the suite tests. Rule 5's remedy is to
# point a seam at a scratch path under $BATS_TEST_TMPDIR, and that is never WRONG — at worst it
# pins a seam the suite would not have reached. a514d3b0's second seam is the argument in one line:
# it was latent that day (the fixtures wrote `login_expires_at` while the gate read `.deadline`, so
# it failed open) and one field away from deciding the suite's verdict by live login state. A pin
# costs one line and converts "latent" into "cannot".
#
# MEASURED BEFORE IT WAS ARMED — the backlog item that filed this rule made that a precondition,
# citing b59eb997d035, where ONE over-broad hermeticity assertion kept 14 consecutive green stamps
# red and fail-closed deploy-live. Against trunk, 299 suites — every figure below read back out of
# THIS file's own extractor, not out of the survey script that proposed the rule (they disagreed:
# the survey missed the anchor seam and predated 14 commits of trunk):
#   * the seam table is 19 seams of shape 5a and 7 of shape 5b, over 18 tools;
#   * 61 suites violate — 39 of which are $HOME-hermetic today, i.e. exactly the blind spot;
#   * ONE tool dominates: scripts/handoff-fire.sh accounts for 126 of the 154 (suite,seam) pairs.
# That last figure was checked rather than accepted, because a rule that is 82% one tool is usually
# measuring the tool and not the class. It is not: handoff-fire.sh:2842-2849 READS
# ACCOUNT_SWEEP_STAMP (default /tmp/handoff-account-sweep.json) and, when it is younger than the
# 60s throttle, REUSES the operator's live sweep instead of running its own. So which branch 44
# suites take depends on whether the operator happened to fire a handoff in the last minute. That is
# rule 1's non-determinism precisely, on a path reached by default (only HANDOFF_ACCOUNT_SWEEP=off
# skips it).
#
# CORRECTION TO THE FILING, recorded because the ledger should not keep a wrong citation: the item
# also offered fe21305312ec (tests/cc-inbox-guard.bats forking the real it2) as this class. It is
# not. bin/cc-inbox-guard:45 reads IT2="${CC_INBOX_GUARD_IT2:-$HOME/.claude/bin/it2}" — a $HOME
# default, so a fixtured $HOME already absents it. That suite forks the real it2 because it is
# grandfathered under RULE 1, and rule 1 is the rule that fixes it.
#
#   SCOPE, and it is deliberately the WEAKER of the two available tests. A suite is in scope for
#   tool T iff its COMMENT-STRIPPED text names T's path (`/bin/T`, `/scripts/T.sh`, `/hooks/T.sh`);
#   it is then required to assign each of T's 5a/5b seams in setup()/setup_file(). Textual, exactly
#   like references_fire() — no reachability analysis, so the rule OVER-fires where a seam sits
#   behind a precondition the suite has already fixtured. That is not a hypothetical: this rule
#   reports tests/cc-relogin-status.bats — the suite a514d3b0 FIXED — still violating, on
#   CC_DISPATCH_LOG, which bin/cc-blockers reaches only via a `cc-dispatch` actor row the suite's
#   already-fixtured CC_REAPER_IDL cannot contain. It is grandfathered below as the KNOWN over-fire
#   and named here so the floor is a stated property and not a surprise.
#   Comment-stripping is the one place scope is TIGHTENED relative to rule 2, and it is free: a
#   suite that only NAMES a tool in prose executes nothing.
#   Per-test assignment does NOT count, for rule 1's reason verbatim — it leaves every other test in
#   the file pointed at live state.
#
#   THE SEAM TABLE IS TREE-DERIVED AND THE EXTRACTOR NEVER READS THE MACHINE. No `command -v`, no
#   PATH resolution, no stat of an absolute default: shape 5b is recognised by the default matching
#   a tool THIS REPO SHIPS (bin/<d>, scripts/<d>[.sh], hooks/<d>[.sh]). A lint that resolved the
#   operator's PATH to reach a verdict would be committing the defect it exists to catch — and it
#   would also be wrong, since `timeout` is /usr/bin on one box and Homebrew coreutils on the next.
#   The HOLDER matters, not just the seam: cc-blockers assigns the seam to ACCOUNTS_BIN and runs
#   "$ACCOUNTS_BIN", so 5b requires the ASSIGNMENT TARGET to appear in command position. Without
#   that test, `STRICT_TOOLS="${CC_PARITY_STRICT:-claude-accounts}"` (a LIST of tool names) and
#   `PAGE_KEY="${CC_NIGHTLY_PAGE_KEY:-nightly-regression}"` (a string) both read as executions —
#   measured, they were 9 of the 16 shape-5b candidates before the holder test was added.
#
#   THE EXTRACTOR IS ANCHORED, not counted — rule 4's argument, and its wording, apply unchanged.
#   THIS script carries CC_HERM_SEAM_SELFPROBE below, a real shape-5a seam that exists for no other
#   purpose, so wherever this file sits inside the scanned seam root the extractor must find it. If
#   it cannot see its own, it is broken and the run is a LOUD non-verdict instead of a vacuous
#   green. A floor (`seams < 20`) could not say that without making every smaller tree unlandable.
#
#   Rule 5's grandfather list (EMBEDDED_SEAM_ALLOWLIST) ships with the 61 measured above, under the
#   same contract as rules 1-2 — ONLY EVER DELETE LINES; pinning a suite's seams without deleting
#   its line is a RED. 61 of 299 is a fifth of the tree, against rule 1's 109 of 118 when it landed.
#
# RULE 6 (the INHERITED-VALUE seam) — rule 5's blind spot, and it is blind BY CONSTRUCTION for the
# same reason rule 1 was blind to rule 5. Rule 5 asks where a subject's state RESOLVES, so it can
# only see a seam whose DEFAULT betrays it: an absolute /tmp path (5a) or a bare name this repo
# ships (5b). Every other default is skipped. But a default is IRRELEVANT when a VALUE is already in
# the environment — the fallback never runs at all. That is a different question, so it needs a
# different rule.
#
# THE INCIDENT THAT GENERATED IT (0588d255, 2026-08-07): bin/cc-pane-runner selects its launch
# branch on CC_PANE_CMD_INTERACTIVE, whose default is the plain value `0`. scripts/handoff-fire.sh
# and bin/it2-kitty INJECT that variable into every argv-launched pane, so every DESCENDANT of a
# fired pane carries it — including bats, when an agent runs a suite from the pane that fired it.
# tests/handoff-fire-argv-launch.bats and tests/it2-kitty-argv-spawn.bats went 5-RED on a PRISTINE
# `git archive origin/main` tree, and green the moment one inherited variable was unset. One of the
# five was the negative CONTROL "the SAME launcher DIES under the eval path" — i.e. the assertion
# whose whole job is to show that branch is not decoration. The shape a feature's own suite can
# least afford: red exactly when run from inside a pane that feature created, green everywhere
# else, so it reads as a genuine trunk red and the BOX decides the verdict. THIS LINT REPORTED BOTH
# SUITES CLEAN THROUGHOUT — rule 5 saw `:-0` and moved on.
#
# WHY IT IS A SIXTH RULE AND NOT A THIRD SHAPE OF RULE 5, which was the filing's first instinct and
# is wrong on a MEASURED point, not a stylistic one. Rule 5's position predicate is
# is_seam_assigned(), which requires `VAR=`. The compliant fix for an inherited value is very often
# `unset`, and 0588d255 used exactly that — so a bolted-on shape 5c would report the very fix that
# generated this rule STILL VIOLATING, forever. Rule 6 therefore takes rule 3's asymmetry instead:
# ANY deterministic position clears it (`unset`, `=`, `export …=`), because what is forbidden is
# INHERITING one, not choosing the "wrong" one. A separate list follows for rule 2's reason verbatim
# — the rules are independent, and one shared list could only shrink when every rule was satisfied
# at once.
#
#   THE TABLE IS AN INTERSECTION, and that is the whole design. The filing's candidate rule was "for
#   each tool F, collect the CC_* vars F reads; any suite naming F must pin them". Measured, that is
#   1047 seam assignments across the tool tree and it would oblige most of 324 suites — a lint
#   nobody can turn on is worth zero (rule 1's founding argument). The narrowing is the MECHANISM
#   itself: a variable can only be INHERITED if something PUTS it there, and this repo puts a
#   variable into a descendant environment in exactly one way — the explicit pane-launch API
#   `--env NAME=VALUE` (bin/it2-kitty, scripts/handoff-fire.sh). A pane is a long-lived interactive
#   shell, which is precisely why the value survives to reach a later bats run. So:
#
#       rule 6's table  =  PROPAGATED (some tool injects it)  ∩  READ (this tool reads `${NAME:-`)
#
#   EACH HALF ALONE IS WRONG, and both failures are measured rather than imagined:
#     * READ alone is the filing's naive rule — most of 324 suites, above.
#     * PROPAGATED alone convicts scripts/handoff-fire.sh, which injects a runner variable it never
#       READS (its only mention outside the injection is inside SINGLE QUOTES, expanded by the
#       PANE's shell, not this one; the two `…_BIN` reads near it are a DIFFERENT variable). 51
#       suites name handoff-fire.sh and 49 would have been grandfathered for a variable their
#       subject does not read. That is rule 6's mandatory INJECT-ONLY scope control, and it is worth
#       more than every other control here put together.
#
#   COST, measured rather than assumed, because this lint is ship-land's FAIL-FAST gate and every
#   land pays it: rule 6 adds ~5.7s to a 19.6s whole-tree run (274 tools, 324 suites) — one bulk
#   pre-filter for the table plus the same one-grep-per-suite scope test every other rule here uses,
#   i.e. in line with their per-rule cost. The naive shape of the same code cost +10s, by stripping
#   and extracting all 274 tools instead of the 3 that carry either shape.
#
#   TREE-DERIVED, COMMENT-STRIPPED, AND THE EXTRACTOR NEVER READS THE MACHINE — rule 5's law, and
#   here the comment strip is load-bearing in a way it is not there: rule 5's table pattern is
#   ^-anchored so a `#` excludes itself, while `--env NAME=` and `${NAME:-` match anywhere on a
#   line. Unstripped, THIS FILE's own header would mint phantom propagated variables out of the
#   prose you are reading. Rules 2, 3 and 4 were each shipped VACUOUS by a predicate that matched
#   prose; this is that lesson applied before the fact rather than after.
#
#   SCOPE is rule 5's, verbatim: a suite is in scope for tool T iff its COMMENT-STRIPPED text names
#   T's path. Per-test assignment does NOT count, for rule 1's reason verbatim.
#
#   THE EXTRACTOR IS ANCHORED, not counted — rules 4 and 5's argument and wording apply unchanged.
#   THIS script carries CC_HERM_ENV_SELFPROBE below in BOTH halves — a real injection argument and a
#   real read — so wherever this file sits inside the scanned root the extractor must find it. An
#   anchor that exercised only one half could not tell a broken intersection from an empty tree.
#
#   ONE EXCLUSION — and it was TWO until 2026-08-21, when the second was measured and deleted
#   (backlog b2775a8bbc3a). What survives is in build_env_table() with its numbers:
#     * a variable this repo also EXPORTS as a plain session setting is a CONFIGURED input, not
#       leaked pane state. CC_PANE_CMD / _DIR / _INTERACTIVE are exported NOWHERE — they exist only
#       as pane-launch arguments — while CLAUDE_CONFIG_DIR is exported by a launcher and is ambient
#       in every session by design.
#
#   THE DELETED ONE WAS "a $HOME-ROOTED default is RULE 1's business", and its removal is worth
#   recording because of HOW it survived scrutiny for twelve days. The pair was credited JOINTLY —
#   "between them these took a first run against the new base from 123 suites to 1" — so neither
#   number attributed to either line, and the blanket drew its whole justification from a total its
#   sibling had earned. A/B'd against this tree with only that line differing: it claims THREE
#   suites, all for CC_PANE_CMD_DIR, and ZERO for CLAUDE_CONFIG_DIR, which the EXPORTED test above
#   already removes unaided. Its entire remaining effect was to hide CC_PANE_CMD_DIR — injected at
#   bin/it2-kitty:989 in the SAME `--env` block as CC_PANE_CMD_INTERACTIVE, i.e. the direct sibling
#   of this rule's founding incident, missed only because its default happens to mention $HOME.
#   A JOINT FIGURE IS NOT AN ATTRIBUTION: if two guards are justified by one number, at most one of
#   them has been measured.
#
#   MEASURED AGAINST TRUNK, every figure read back out of THIS file's own extractor rather than out
#   of the survey that proposed the rule — and the two DISAGREED, worth recording because the survey
#   was the looser instrument, not the subject: it matched a tool by BASENAME where the rule (through
#   the shared seam_names_tool) matches the repo-relative PATH, so it counted three suites that only
#   stub their own `it2-kitty` in $BATS_TEST_TMPDIR or name a TEST FILE of that name.
#   The table is 2 tools (bin/cc-pane-runner, bin/it2-kitty) × 3 variables. 8 suites violated and
#   ALL 8 ARE FIXED IN THIS DIFF rather than grandfathered, so the list below ships EMPTY: 6 take the
#   pane variables, 2 name this script and take its anchor. The suites that PASSED throughout are
#   exactly the two 0588d255 fixed — the rule is green on the artifact that generated it and red only
#   on what is still ambient, which is the pair of facts that makes a new ratchet worth landing.
#   The 8th is tests/spawn-wedge-watchdog.bats, which origin/main added WHILE THIS WAS BEING WRITTEN
#   and which inherits all three: the rule caught a genuine new instance on its first run against a
#   base it had never seen, which is the only demonstration that matters for a ratchet.
#
# RULE 7 (the capacity-ADMIT gate) — rule 2's TWIN at the other gate, and the same class arriving
# through a seam rule 2 is blind to by construction. Rule 2 knows exactly one lever,
# `CC_FIRE_CAPACITY_GATE`, because scripts/handoff-fire.sh's capacity_gate() is the only gate it was
# written against. scripts/lib/capacity-admit.sh is a SECOND gate with its OWN namespace
# (`CC_ADMIT_*`, deliberately separate — see that file's WHY ITS OWN NAMESPACE block), its own
# callers, and the same failure: it reads live machine state and REFUSES with exit 9, so a suite
# that reaches it without pinning decides its verdict on whatever the desk happens to be doing.
#
# THE INCIDENT THAT FILED IT (backlog 5ef0dcb22aec, 2026-08-10): tests/kitty-recovery-launch.bats
# went red-by-LOAD three times inside a 228-test sweep and green in isolation. It drives
# scripts/boot-resume-launch.sh, which calls cc_capacity_admit at :265. Rule 2 reported that suite
# CLEAN throughout — it names no handoff-fire, so it was never in rule 2's scope, and rule 2's pin
# predicate greps for a variable this gate does not read.
#
# 🚨 THE FILING'S REMEDY IS INCOMPLETE, AND THE GAP IS THE WHOLE REASON THIS RULE IS NOT THREE LINES
# OF rule 2. The item describes the fix as adding `CC_ADMIT_GATE` as a second seam, i.e. rule 2's
# two sufficient forms with the names swapped: form 1 the kill switch, form 2 the pair of
# instrument overrides (`CC_ADMIT_LOADAVG_OVERRIDE` + `CC_ADMIT_HEADROOM_OVERRIDE`). That was TRUE
# WHEN FILED and is false now. 450a47c50 (2026-08-12, two days later) added a THIRD term — the
# operator RESERVE — which runs over an otherwise-ADMITTING box and can still refuse. It reads two
# live instruments that neither override touches: cc_sp_operator_state (the operator's presence) and
# cc_sp_trees (a live `ps -eo` census of session trees). A fixtured $HOME does not absent either;
# _cc_admit_load_presence resolves spawn-presence.sh RELATIVE TO capacity-admit.sh's own directory
# first, so a suite pointing $HOME at a tmpdir still loads the REAL library.
#   Proven two-sided, on the gate's OWN suite, which pins exactly the two variables the filing names:
#   `bats tests/capacity-admit.bats` is 20/20 green ambient, and 17/20 under
#   `CC_SP_TREES_OVERRIDE=999` — tests 13, 14 and P3 flip on the census alone. Had form 2 been ported
#   verbatim, this rule would have certified the one suite whose subject IS this gate as PINNED while
#   it read the live box. That is a FALSE NEGATIVE minted by the rule that exists to prevent it, and
#   it is the general lesson (memory reassurance-clause-is-the-untested-half): a filing's account of
#   what is already handled is its least-tested sentence, and it errs toward making the fix look
#   smaller.
#
#   A suite is compliant iff it does NOT name capacity-admit or one of its gate callers (out of
#   scope — never flagged), or its setup()/setup_file() BODY closes the gate by one of two forms:
#     FORM 1  `CC_ADMIT_GATE=off` — the kill switch, checked at capacity-admit.sh:373 before any
#             term is evaluated, so one line closes all three.
#     FORM 2  `CC_ADMIT_LOADAVG_OVERRIDE` AND `CC_ADMIT_HEADROOM_OVERRIDE` AND a reserve closure —
#             either `CC_ADMIT_RESERVE_TERM=off` (skips the term outright) or `CC_SP_TREES_OVERRIDE`
#             (pins the only live-machine probe inside it; the presence read behind it resolves from
#             CC_BEAT_DIR, whose default is $HOME-rooted and therefore RULE 1's business, the same
#             split rule 5 makes). Form 2 exists for rule 2's reason exactly: a suite whose SUBJECT
#             is this gate cannot use form 1 without deleting what it tests. Three clauses, not two,
#             and the third is the correction above.
#   Per-test pinning does NOT count, for rule 1's reason verbatim.
#
#   SCOPE IS BARE-NAME AND DELIBERATELY BROAD, which is rule 2's settled asymmetry and not a fresh
#   judgment: a false negative is a suite silently reading the live box, a false positive is one
#   harmless export. So scope matches the STEM of the library or any of its three gate callers
#   (scripts/boot-resume-launch.sh:265, scripts/limit-recover/lr-fire-resume.sh:318,
#   hooks/agent-teams-enforce.sh:203) with comments and PROSE stripped — the shared strip_prose,
#   which this rule generalised from rule 2's hardcoded `handoff-fire` to a parameter so the twins
#   cannot drift. scripts/handoff-fire.sh SOURCES capacity-admit.sh but never calls the gate (it
#   reuses only the shared cc_hw_* terms under CC_FIRE_*), so it is NOT a caller and the two rules'
#   populations do not overlap by construction — checked, because a rule that silently duplicated
#   rule 2's population would be measuring the same suites twice.
#
#   MEASURED AGAINST TRUNK before it was armed, out of this file's own predicates: 20 suites in
#   scope, 4 pinned (3 by form 1, tests/spawn-presence.bats by form 2), 16 violating. ONE of those 16
#   is FIXED in this diff rather than grandfathered — tests/capacity-admit.bats, because it is the
#   one whose ambience was measured rather than inferred (20/20 green, 17/20 under
#   CC_SP_TREES_OVERRIDE=999) and because its own header already claimed the property it had lost.
#   The remaining 15 ship in EMBEDDED_ADMIT_ALLOWLIST under the same contract as rules 1-2 and 5 —
#   ONLY EVER DELETE LINES.
#   Grandfathered rather than fixed in the landing diff (rules 3, 4 and 6's better outcome) because
#   15 suites is too wide a behavioural change to review inside a lint's own diff, and because
#   several are static text-analysis suites that grep a caller's SOURCE and execute nothing — a
#   position neither strip_comments nor strip_prose can distinguish, and the broad-scope asymmetry
#   says keep them in and let the ratchet retire them one at a time.
#
# Exit: 0 = clean · 1 = violation · 2 = bad usage / unreadable scan dir (LOUD, never silent-green)
#
# Env seams (selftest / escape hatch):
#   CC_HERM_ALLOWLIST          overrides rule 1's embedded allowlist (set-but-empty = no grandfathering)
#   CC_HERM_FIRE_ALLOWLIST     overrides rule 2's embedded allowlist (same set-but-empty semantics)
#   CC_HERM_FIRE_RULE=off      kill switch — disables rule 2 entirely, leaving rule 1 exactly as it was
#   CC_HERM_ORPHAN_ALLOWLIST   overrides rule 3's embedded allowlist (same set-but-empty semantics)
#   CC_HERM_ORPHAN_RULE=off    kill switch — disables rule 3 entirely, leaving rules 1-2 untouched
#   CC_HERM_SELFTEST_ALLOWLIST overrides rule 4's embedded allowlist (same set-but-empty semantics)
#   CC_HERM_SELFTEST_RULE=off  kill switch — disables rule 4 entirely, leaving rules 1-3 untouched
#   CC_HERM_SELFTEST_ROOT      overrides the repo root rule 4 scans (default: this script's ROOT)
#   CC_HERM_SEAM_ALLOWLIST     overrides rule 5's embedded allowlist (same set-but-empty semantics)
#   CC_HERM_SEAM_RULE=off      kill switch — disables rule 5 entirely, leaving rules 1-4 untouched
#   CC_HERM_SEAM_ROOT          overrides the repo root rule 5 derives its SEAM TABLE from
#                              (default: this script's ROOT). The scan dir stays lint_dir's
#                              positional argument — the table's population and the suites' are
#                              different sets, exactly as for rule 4.
#   CC_HERM_ENV_ALLOWLIST      overrides rule 6's embedded allowlist (same set-but-empty semantics)
#   CC_HERM_ENV_RULE=off       kill switch — disables rule 6 entirely, leaving rules 1-5 untouched
#   CC_HERM_ENV_ROOT           overrides the repo root rule 6 derives its INHERITED-VALUE table from
#                              (default: this script's ROOT), for CC_HERM_SEAM_ROOT's reason
#   CC_HERM_ADMIT_ALLOWLIST    overrides rule 7's embedded allowlist (same set-but-empty semantics)
#   CC_HERM_ADMIT_RULE=off     kill switch — disables rule 7 entirely, leaving rules 1-6 untouched
set -uo pipefail
# Resolve $0 THROUGH symlinks before deriving ROOT. Everything under ~/.claude/scripts/ is a per-file
# symlink into this checkout, so a bare `dirname "$0"` yields ~/.claude — which has no tests/ — and the
# --selftest case that lints the real tree then fails for a reason that has nothing to do with the
# ratchet. Observed 2026-07-26 running the DEPLOYED path right after landing it. (No `readlink -f`:
# that is GNU-only and this box ships the BSD userland.)
SELF="$0"
while [ -L "$SELF" ]; do
  _link="$(readlink "$SELF")"
  case "$_link" in
    /*) SELF="$_link" ;;
    *)  SELF="$(dirname "$SELF")/$_link" ;;
  esac
done
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
# ABSOLUTE, because $0 is routinely relative (`./scripts/test-hermeticity-lint.sh`) and the symlink
# loop above preserves that. Anything that resolves $SELF from a DIFFERENT working directory — the
# memo's own key, below — silently gets nothing from a relative one. ROOT is already absolutised
# by its `cd … && pwd`; this is the same treatment for the file itself.
#
# Derived from $SELF's OWN directory, NOT as "$ROOT/scripts/$(basename …)". The second form assumes
# this file sits in the scripts/ dir of its root, which is true of the checkout and false of every
# copy — and the failure is silent, because a path that does not resolve simply makes the memo key
# unobtainable and the memo turns itself off. Caught by tests/herm-suite-memo.bats, which proves a
# revised lint invalidates its carried verdicts by running a COPY.
SELF_ABS="$(cd "$(dirname "$SELF")" && pwd)/$(basename "$SELF")"

# ── THE PER-SUITE MEMO (land-arch P3 follow-on, backlog cf440684e0e1) ─────────────────────────────
# This lint is the land gate's most expensive arm by a wide margin — 46.0s of the ~135s the fifteen
# ratchet arms cost, measured 2026-08-13 with the own-set exported exactly as ship-land's own_run
# does. Every optimistic round that a sibling invalidates (exit 42) re-pays all of it over a tree
# that is byte-identical except for the sibling's delta.
#
# Measured shape, by scaling the corpus (ENV_ROOT is $ROOT regardless of the dir argument, so the
# table build is a constant and the two costs separate): 10.4s fixed + 0.069s per suite, linear
# across n=0/60/120/240/467. So 32s of the 46s is the per-suite loop below, and that is what this
# memoizes. The fixed 10.4s is the seam/env table build over bin+scripts+hooks; caching a table's
# CONTENT needs a value store, which scripts/lib/gate-memo.sh deliberately does not have (it stores
# only "this green was earned"), so it is left alone rather than widened for.
#
# WHAT IS CACHED, AND WHY IT IS OWN-SET-INDEPENDENT. The cached fact is "this suite emitted
# nothing" — no leak, no ratchet, no advisory, under all seven rules. Every printf in lint_dir sits
# inside a finding branch, and in_own only chooses which WORDING a finding gets (LEAK vs leak?), so
# a suite that emits nothing emits nothing for every land regardless of its own-set. That keeps
# gate-memo's one invariant unwidened: only an earned green is ever stored, and a finding is never
# replayed from a cache.
#
# THE READ SET, declared mechanically rather than asserted — this is the per-lint locality proof the
# P3 note asks for, and HERM_READSET below is it in executable form. A suite's verdict is a function
# of exactly: its own bytes · this script's own bytes (every predicate and every embedded allowlist)
# · the six allowlists actually in force (the CC_HERM_*_ALLOWLIST overrides can change them without
# changing this file) · the five rule switches · and the seam/env TABLES, which rules 5 and 6
# consult per suite and which are built from bin+scripts+hooks, a different population entirely.
# Rules 1, 2, 3, 4 and 7 are file-local; rule 4's per-file-ness is not assumed here — §5.P3 claimed
# it was a CROSS-FILE rule and that claim was refuted by reading the scan (`for f in …`, both
# predicates take ONE file; the "collides" wording is about two runs of the same tool).
#
# Kill switch: CC_HERM_MEMO=off. SHIP_LAND_MEMO=off also disables it, via memo_init.
HERM_MEMO_OK=0
if [ "${CC_HERM_MEMO:-on}" != "off" ] && [ -r "$ROOT/scripts/lib/gate-memo.sh" ]; then
  # shellcheck source=/dev/null
  . "$ROOT/scripts/lib/gate-memo.sh" 2>/dev/null || true
fi

# ── the ratchet: suites grandfathered as non-hermetic. ONLY EVER DELETE LINES FROM THIS LIST. ──
# ONE recorded exception to "only delete", and it is a RENAME, not an addition (2026-07-31):
# `deploy-parity.bats` left this list because it was genuinely fixed — it now exports a fixture HOME
# in setup() — and `deploy-parity-live.bats` took its place. That is the SAME grandfathered
# non-hermeticity under a new file name: tests/deploy-parity.bats was split so that the two tests
# which must resolve the real ~/bin and ~/.claude live in their own file (scripts/host-suites.manifest
# explains why the split was forced — the corpus partition is per FILE, so those two rode 29 hermetic
# tests out of the land gate). The count is unchanged and the substance strictly improved: 29 tests
# that were exempt are now held to the rule. Anything that is NOT a split of an already-listed suite
# is still an addition, and additions are still forbidden.
EMBEDDED_ALLOWLIST="$(cat <<'ALLOW'
activation-watch.bats
anti-deference-nudge.bats
boot-resume-launch.bats
boot-resume.bats
boundary-handoff.bats
cc-announce.bats
cc-audit.bats
cc-await-ping.bats
cc-backlog.bats
cc-blockers.bats
cc-classify.bats
cc-crash-report.bats
cc-decide.bats
cc-digest.bats
cc-discover.bats
cc-dispatch.bats
cc-idl.bats
cc-inbox-guard.bats
cc-permission-beacon.bats
cc-reconcile.bats
cc-recover-safeguard.bats
cc-route.bats
cc-run.bats
cc-teardown-safety-gate.bats
cc-teardown.bats
cc-unattended-ask-guard.bats
cc-upgrade-gate.bats
cc-wave-plan.bats
claude-accounts-core.bats
claude-accounts.bats
claude-kimi.bats
completion-assert.bats
completion-push.bats
context-econ.bats
delivery-verify.bats
deploy-parity-live.bats
desk-assert-wiring.bats
desk-assert.bats
desk-brief-ssot.bats
desk-invariant.bats
desk-land.bats
desk-register.bats
dod-persist.bats
effort-parity.bats
exit-deadline.bats
find-plan-list-open.bats
fire-autonomy.bats
fire-engagement.bats
gate-classify.bats
gate-manifest.bats
handoff-disposition.bats
handoff-fire-completion-push.bats
handoff-fire-focus.bats
handoff-fire-inject.bats
handoff-fire-payload-lint.bats
handoff-fire-tab-window-typing.bats
handoff-fire-validate.bats
handoff-selfclose.bats
handoff-splitright.bats
idl-abstain-alarm.bats
install-wire-hooks.bats
kimi-frontend-ab.bats
land-gate-cas.bats
land-lock.bats
land-verify.bats
lead-crash-watchdog.bats
lead-deathwatch.bats
lead-supervisor.bats
mail-ack-consume.bats
mailbox-forward.bats
notify-back.bats
operator-readout.bats
page-damp.bats
payload-lint-tool-parity.bats
payload-lint.bats
plan-index.bats
power-policy.bats
pre-session-validate.bats
reap-guard.bats
reset-hard-shadow-allow.bats
rm-safe-allowlist.bats
rotate-autonomy-logs.bats
session-registry.bats
settings-dedup-stop.bats
ship-land.bats
ship-rail-push-allow.bats
stranded-sweep.bats
task-helpers-scope.bats
task-quality-gate.bats
validate-plan-structure.bats
wait-contract-lint.bats
wrap-ledger.bats
ALLOW
)"

# ── RULE 2's ratchet: suites that exercise handoff-fire WITHOUT pinning CC_FIRE_CAPACITY_GATE=off in
# setup(). ONLY EVER DELETE LINES FROM THIS LIST. Deliberately a SECOND list and not a merge with the
# one above: the two rules are independent (a suite can be $HOME-hermetic and load-exposed, or the
# reverse), so one shared list could only shrink when BOTH were fixed — which is a ratchet that
# ratchets half as often. Derived by reading the tree, not handed down: for every tests/*.bats that
# mentions handoff-fire, the setup()/setup_file() body was checked for the pin. Four of these
# (handoff-fire-capacity-gate, handoff-fire-failed-cleanup, handoff-fire-repo-resolution,
# handoff-recycle-engagement) DO pin the gate, but per-test only — which is exactly the shape the
# rule rejects, so they are grandfathered like the rest until the pin moves into setup().
# The list was derived AGAINST TRUNK at the last possible moment, which is the only way it can be
# right: while this rule was being written, three suites (fire-engagement, handoff-fire-focus,
# handoff-fire-payload-lint) were pinned and landed by a sibling — listing them from an earlier
# reading would have shipped a ratchet that was stale on arrival, i.e. RED on its first run.
#
# 2026-08-08 — THE LIST IS NOW EMPTY, and that is the ratchet arriving at its terminus, not a bypass.
# All 37 remaining entries were pinned in setup() in one pass (LOAD_INSENSITIVE_VERIFY_V2 C1), which
# closes A1: every suite that reaches a net-new fire now pins the gate, so rule 2 binds on the whole
# tree with nothing exempt. The four named above (account-sweep, failed-cleanup, repo-resolution,
# recycle-engagement) were the per-test-only cases; their setup() now carries the pin and the older
# per-test ones are left in place as redundant-but-harmless. An empty list is STRICTLY stronger than
# a populated one — `-` not `:-` on the seam below keeps "set but empty" meaning "grandfather
# nothing", which is exactly this state. Re-populating it is an ADDITION, and additions are forbidden.
EMBEDDED_FIRE_ALLOWLIST="$(cat <<'FIREALLOW'
FIREALLOW
)"

# Rule 2's runtime knobs. Globals rather than lint_dir parameters ON PURPOSE: lint_dir's ARITY is
# load-bearing — `[ "$#" -ge 3 ]` is what separates "no own-set supplied ⇒ strict" from "own-set
# supplied but empty ⇒ nothing blocks", so a 4th positional would force every caller that wants a
# fire allowlist to also invent an own-set, silently flipping the own-scope state it never meant to
# touch. `-` not `:-` on the seam, so set-but-EMPTY legitimately means "grandfather nothing".
FIRE_ALLOW="${CC_HERM_FIRE_ALLOWLIST-$EMBEDDED_FIRE_ALLOWLIST}"
FIRE_RULE="${CC_HERM_FIRE_RULE:-on}"

# ── RULE 3's ratchet: suites that exercise the watchdog's orphaned-pane close leg WITHOUT pinning
# LCW_ORPHAN_CLOSE in setup(). Ships EMPTY, and that is a measurement, not an aspiration: on
# 2026-07-30 exactly one suite in tests/ invokes `--close-panes` (lead-crash-close-panes.bats) and
# it pins the lever. Derived against trunk at the last possible moment, for the reason rule 2's list
# records — a ratchet listed from an earlier reading ships stale, i.e. RED on its first run.
# ONLY EVER DELETE LINES FROM THIS LIST. It should never gain one: a NEW suite in scope is a suite
# that can pin from the start.
EMBEDDED_ORPHAN_ALLOWLIST=""

# Rule 3's runtime knobs. Globals rather than lint_dir parameters for rule 2's reason verbatim:
# lint_dir's ARITY is load-bearing. `-` not `:-` on the seam, so set-but-EMPTY legitimately means
# "grandfather nothing" — which is also the shipped default, so the two agree by construction.
ORPHAN_ALLOW="${CC_HERM_ORPHAN_ALLOWLIST-$EMBEDDED_ORPHAN_ALLOWLIST}"
ORPHAN_RULE="${CC_HERM_ORPHAN_RULE:-on}"

# ── RULE 4's ratchet: tools whose EMBEDDED selftest names a scratch path that is the same string on
# every run. Ships EMPTY, and that is a measurement: on 2026-07-31 all 45 extractable regions under
# bin/, scripts/ and hooks/ obtain their scratch dir from `mktemp` and none names a constant
# /tmp-family path. Derived against trunk at the last possible moment, for the reason rules 2-3
# record — a list read earlier ships stale, i.e. RED on its first run.
# ONLY EVER DELETE LINES FROM THIS LIST. It should never gain one.
EMBEDDED_SELFTEST_ALLOWLIST=""

# Rule 4's runtime knobs. Globals rather than parameters for rules 2-3's reason verbatim (arity is
# load-bearing on the own-scope seam). `-` not `:-`, so set-but-EMPTY means "grandfather nothing" —
# which is also the shipped default, so the two agree by construction.
SELFTEST_ALLOW="${CC_HERM_SELFTEST_ALLOWLIST-$EMBEDDED_SELFTEST_ALLOWLIST}"
SELFTEST_RULE="${CC_HERM_SELFTEST_RULE:-on}"
SELFTEST_ROOT="${CC_HERM_SELFTEST_ROOT:-$ROOT}"

# A CONSTANT /tmp-family path in a STATE-BEARING position: an assignment (`tmp=/tmp/x`,
# `d="/tmp/x"`), a redirect target (`> /tmp/x`), or an argument to a create/destroy verb
# (`mkdir -p /tmp/x`). Anchored at a statement boundary — `(^|[[:space:];&|(])` — and that anchor is
# not cosmetic: without it `<string>/tmp/$label.sh</string>` matches on the tag's own `>`, and a
# /tmp literal quoted INSIDE an argument to something else (`arow s3 "rm -rf /tmp/x"`, four such
# lines in tests/) reads as a write. All four shapes were checked against this pattern and none
# matches. The narrow miss it buys — `printf x>/tmp/f`, with no space before the redirect — is the
# same accepted floor rules 2-3 take: the ratchet binds where the evidence is plain.
SELFTEST_CONST_RE='(^|[[:space:];&|(])((>>?[[:space:]]*"?|(mkdir|touch|tee|install|cp|mv|rm)([[:space:]]+-[a-zA-Z-]+)*[[:space:]]+"?)|[A-Za-z_][A-Za-z0-9_]*="?)(/private)?/(var/)?tmp/'
# Does the region create scratch state AT ALL? This is rule 4's SCOPE probe, and it exists for the
# reason references_fire()/references_close_leg() exist: a selftest that writes nothing cannot
# collide with a concurrent copy of itself, so demanding `mktemp` of it would be a rule firing on
# everything — which passes every RED assertion while proving nothing.
SELFTEST_CREATES_RE='(^|[[:space:];&|(])(>>?[[:space:]]|mkdir([[:space:]]|$)|touch([[:space:]]|$)|tee([[:space:]]|$))'

# ── RULE 5's ratchet: suites naming a tool that carries a non-$HOME seam, without assigning it in
# setup(). ONLY EVER DELETE LINES FROM THIS LIST. Derived AGAINST TRUNK at the last possible moment,
# for the reason rules 2-4 record — a list read earlier ships stale, i.e. RED on its first run.
# A THIRD list rather than a merge, for rule 2's reason verbatim: the rules are independent (a suite
# can be $HOME-hermetic and seam-exposed, or the reverse), and one shared list could only shrink
# when every rule was satisfied at once — a ratchet that ratchets a quarter as often.
# tests/cc-relogin-status.bats is the KNOWN OVER-FIRE, kept deliberately and named in RULE 5's
# header: a514d3b0 fixed it, and it is listed here only because CC_DISPATCH_LOG sits behind a
# precondition its already-fixtured CC_REAPER_IDL cannot satisfy. A rule with a stated floor needs
# its false positive PINNED as a control, not quietly excluded (memory
# threshold-must-separate-fatal-from-survived).
EMBEDDED_SEAM_ALLOWLIST="$(cat <<'SEAMALLOW'
cc-backlog.bats
cc-blockers-fleet.bats
cc-blockers-teammate-reap.bats
cc-blockers.bats
cc-classify.bats
cc-relogin-status.bats
claude-accounts-core.bats
ctx-recycle-record.bats
desk-invariant.bats
desk-land.bats
dispatch-cadence.bats
fire-autonomy.bats
fire-engagement.bats
handoff-anchor-third-state.bats
handoff-close-mail-guard.bats
handoff-engage-scan-window.bats
handoff-fire-capacity-gate.bats
handoff-fire-completion-push.bats
handoff-fire-failed-cleanup.bats
handoff-fire-focus.bats
handoff-fire-inject.bats
handoff-fire-it2-bound.bats
handoff-fire-kitty-daemon.bats
handoff-fire-kitty.bats
handoff-fire-pane-parked.bats
handoff-fire-pane-proof.bats
handoff-fire-payload-lint.bats
handoff-fire-repo-resolution.bats
handoff-fire-stamp-daemon-path.bats
handoff-fire-tab-window-typing.bats
handoff-fire-typed-cmd-correctable.bats
handoff-fire-validate.bats
handoff-lifecycle-record.bats
handoff-orphaned-assignee.bats
handoff-payload-gates.bats
handoff-recycle-durable-cwd.bats
handoff-recycle-engagement.bats
handoff-selfclose-kitty-identity.bats
handoff-selfclose-session-pin.bats
handoff-selfclose-teammate-gate.bats
handoff-selfclose-terminal-pin-order.bats
handoff-selfclose.bats
handoff-splitright.bats
handoff-teardown-marker.bats
it2-kitty-argv-spawn.bats
it2-wrapper.bats
kitty-divert-real-it2.bats
kitty-split-launch-stamp.bats
launcher-temp-hardening.bats
lead-supervisor-page-verdict.bats
lead-supervisor.bats
notify-back.bats
operator-surface-scope.bats
settings-dedup-stop.bats
settings-drift.bats
settings-hook-timeouts.bats
ship-land.bats
tsv-field-collapse.bats
SEAMALLOW
)"

# Rule 5's runtime knobs. Globals rather than lint_dir parameters for rule 2's reason verbatim —
# lint_dir's ARITY is load-bearing on the own-scope seam. `-` not `:-`, so set-but-EMPTY means
# "grandfather nothing".
SEAM_ALLOW="${CC_HERM_SEAM_ALLOWLIST-$EMBEDDED_SEAM_ALLOWLIST}"
SEAM_RULE="${CC_HERM_SEAM_RULE:-on}"
SEAM_ROOT="${CC_HERM_SEAM_ROOT:-$ROOT}"

# THE EXTRACTOR'S ANCHOR — a real shape-5a seam this script carries BY CONSTRUCTION, so that
# whenever this file sits inside the scanned seam root the extractor must find it. It is read by
# nothing: its whole job is to be found (rule 4's anchor argument, applied to rule 5's extractor).
# A count could not do this work — see RULE 5's header and rule 4's THE EXTRACTOR CONTROL.
# shellcheck disable=SC2034  # deliberately inert — the extractor's positive control, not a setting
SEAM_SELF_ANCHOR="${CC_HERM_SEAM_SELFPROBE:-/tmp/cc-herm-seam-anchor}"
SEAM_ANCHOR_VAR="CC_HERM_SEAM_SELFPROBE"

# An assignment that opens a seam: HOLDER="${SEAM:-DEFAULT}" at the head of a line, `export`
# tolerated. Anchored at ^ because a seam that decides a tool's state is a top-level assignment;
# a `${VAR:-x}` used inline as an argument is a fallback, not a configured state root.
SEAM_ASSIGN_RE='^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*="?\$\{[A-Za-z_][A-Za-z0-9_]*:-[^}]*\}'

SEAM_TABLE=""          # tool <TAB> seam-var <TAB> 5a|5b <TAB> default — built once per ROOT
SEAM_TABLE_ROOT=""     # the root the cached table was built FROM. Keying the cache on the root and
                       # not on a bare built-flag is what stops a second lint_dir call, against a
                       # different SEAM_ROOT, from silently reusing the first one's table — which is
                       # exactly what --selftest does (fixture root, then the real one).
SEAM_TOOLS=""          # the DISTINCT repo-relative tool paths in the table, space-separated
SEAM_TOOLS_RE=""       # those same paths as ONE anchored alternation, for the per-suite pre-filter
SEAM_ANCHOR_SEEN=0

# ── RULE 6's ratchet: suites naming a tool that READS a variable this repo INJECTS into a launched
# pane, without taking a position on it in setup(). ONLY EVER DELETE LINES FROM THIS LIST. Derived
# AGAINST TRUNK at the last possible moment, for the reason rules 2-5 record — a list read earlier
# ships stale, i.e. RED on its first run. A FOURTH list rather than a merge, for rule 2's reason
# verbatim: the rules are independent, and one shared list could only shrink when every rule was
# satisfied at once.
# Ships EMPTY, and that is an OUTCOME rather than an aspiration: the rule was measured at 7 in-scope
# violations against trunk and all 7 were FIXED in the landing diff rather than grandfathered,
# because rule 6's remedy is a single `unset` in setup() that is a NO-OP in an ordinary shell and a
# fix only inside a fired pane — so the usual reason to grandfather (the fix is a change of
# behaviour someone must review) does not apply here. A ratchet that starts empty can only stay
# empty, which is rules 3 and 4's argument and the better artifact where it is affordable.
# ONLY EVER DELETE LINES FROM THIS LIST. It should never gain one.
EMBEDDED_ENV_ALLOWLIST=""

# Rule 6's runtime knobs. Globals rather than lint_dir parameters for rule 2's reason verbatim —
# lint_dir's ARITY is load-bearing on the own-scope seam. `-` not `:-`, so set-but-EMPTY means
# "grandfather nothing".
ENV_ALLOW="${CC_HERM_ENV_ALLOWLIST-$EMBEDDED_ENV_ALLOWLIST}"
ENV_RULE="${CC_HERM_ENV_RULE:-on}"
ENV_ROOT="${CC_HERM_ENV_ROOT:-$ROOT}"

# ── RULE 7's ratchet: suites naming scripts/lib/capacity-admit.sh or one of its three gate callers,
# without closing the gate in setup(). ONLY EVER DELETE LINES FROM THIS LIST. A FIFTH list rather
# than a merge with rule 2's, for the reason rule 6's list records: the rules are independent, and
# one shared list could only shrink when every rule was satisfied at once — and these two rules
# genuinely disagree about several suites (tests/spawn-lineage.bats pins BOTH gates; the four `lr-*`
# suites pin neither and are in only this one).
# Derived AGAINST TRUNK at the last possible moment, out of this file's own predicates rather than
# out of the survey that proposed the rule — rules 2-6's discipline, and it mattered here: a survey
# scoped on "names a capacity-admit caller" reported 22 suites and 17 violations, against this
# rule's measured 20 and 16, because it counted scripts/capacity-alarm.sh, scripts/lib/spawn-
# presence.sh and scripts/lib/worker-claim-gate.sh as callers. All three merely SOURCE the library
# or name CC_ADMIT_BUDGET in a comment; none calls cc_capacity_admit. A list built from the looser
# instrument would have shipped four lines that no predicate can ever retire.
EMBEDDED_ADMIT_ALLOWLIST="$(cat <<'ADMITALLOW'
boot-resume-launch.bats
capacity-admit-coverage.bats
handoff-fire-capacity-gate.bats
iterm2-appname-lint.bats
lr-fire-resume-model-ssot.bats
lr-handoff-close-source.bats
lr-handoff-launcher-quoting.bats
lr-reset-poller.bats
lr-resume-answer-width.bats
lr-resume-tombstone-guard.bats
test-afunix-path-lint.bats
typed-send-shared-discipline.bats
unattended-path-lint.bats
worker-claim-gate-coverage.bats
worker-claim-gate.bats
ADMITALLOW
)"

# Rule 7's runtime knobs. Globals rather than lint_dir parameters for rule 2's reason verbatim —
# lint_dir's ARITY is load-bearing on the own-scope seam. `-` not `:-`, so set-but-EMPTY means
# "grandfather nothing".
ADMIT_ALLOW="${CC_HERM_ADMIT_ALLOWLIST-$EMBEDDED_ADMIT_ALLOWLIST}"
ADMIT_RULE="${CC_HERM_ADMIT_RULE:-on}"

# THE EXTRACTOR'S ANCHOR, and it must exercise BOTH halves of the intersection or it cannot tell a
# broken extractor from an empty tree. These two lines are read by nothing: the first is a literal
# pane-injection argument (the PROPAGATED half), the second a literal seam read (the READ half), and
# together they make this script a rule-6 tool by construction. They are real CODE, not comments, on
# purpose — the table build strips comments, so an anchor in prose would be invisible to the very
# extractor it exists to prove. (Rules 4 and 5's anchor argument; a count could not do this work.)
# shellcheck disable=SC2034  # deliberately inert — the extractor's positive control, not a setting
ENV_SELF_ANCHOR_ARGV="--env CC_HERM_ENV_SELFPROBE=1"
# shellcheck disable=SC2034  # ditto — the READ half of the same anchor
ENV_SELF_ANCHOR="${CC_HERM_ENV_SELFPROBE:-0}"
ENV_ANCHOR_VAR="CC_HERM_ENV_SELFPROBE"

# ONE scan pattern for BOTH halves, so a tool is comment-stripped ONCE. grep -oE yields tokens that
# are self-classifying by their first character — `--env NAME=` is an injection, `${NAME:-` a read.
#
# The injection half is `--env NAME=`: the ONE way this repo puts a variable into a descendant's
# environment, and an explicit API rather than an inference. `export NAME=…; <term> session split`
# is deliberately NOT counted — it configures the CLI wrapper, whose environment does not reach the
# new pane (that is precisely why --env exists), and measured, the two pane-destined variables those
# sites carry already appear in an --env argument elsewhere, so keying on --env loses nothing today.
# The read half carries the DEFAULT as well as the name, because rule 6 must be able to SKIP a
# $HOME-rooted one — see build_env_table(). `[^}]*` stops at the first `}`, so a nested default
# (`${A:-${B:-}/x}`) yields a truncated but still $HOME-bearing string, which is all the test needs.
# The third token class is `export NAME=` at the head of a line — a variable this repo sets as a
# general SESSION SETTING. See build_env_table() for why that disqualifies it from rule 6.
ENV_SCAN_RE='(--env[[:space:]]+"?[A-Za-z_][A-Za-z0-9_]*=|\$\{[A-Za-z_][A-Za-z0-9_]*:-[^}]*\}?|^[[:space:]]*export[[:space:]]+[A-Za-z_][A-Za-z0-9_]*=)'

ENV_TABLE=""           # tool <TAB> inherited-var — built once per ROOT
ENV_TABLE_ROOT=""      # the root the cached table was built FROM (SEAM_TABLE_ROOT's reason verbatim)
ENV_TOOLS=""           # the DISTINCT repo-relative tool paths in the table, space-separated
ENV_TOOLS_RE=""        # the seam-bearing tool paths as ONE alternation, for the per-suite pre-filter
ENV_ANCHOR_SEEN=0

# Build the seam table from <root>'s tool dirs. TREE-DERIVED ONLY — no `command -v`, no PATH read,
# no stat of a default: see RULE 5's header for why a lint that resolves the operator's PATH is
# committing the defect it lints. Sets SEAM_ANCHOR_SEEN when it finds its own anchor.
build_seam_table() {
  local root="$1" f holder rest n d line rel contributed
  SEAM_TABLE=""; SEAM_TOOLS=""; SEAM_TOOLS_RE=""; SEAM_ANCHOR_SEEN=0; SEAM_TABLE_ROOT="$root"
  for f in "$root"/bin/* "$root"/scripts/*.sh "$root"/hooks/*.sh; do
    [ -f "$f" ] || continue
    contributed=0
    # A heredoc-fed `while` is NOT a subshell, so `contributed` (and SEAM_TABLE) survive the loop.
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      line="${line#"${line%%[![:space:]]*}"}"; line="${line#export }"
      holder="${line%%=*}"
      rest="${line#*=}"; rest="${rest#\"}"; rest="${rest#\$\{}"; rest="${rest%\}}"
      n="${rest%%:-*}"; d="${rest#*:-}"
      [ "$n" = "$SEAM_ANCHOR_VAR" ] && SEAM_ANCHOR_SEEN=1
      # shellcheck disable=SC2016  # the patterns match the LITERAL strings $HOME / ~/ ; expansion would break them
      case "$d" in
        # A $HOME-rooted default is RULE 1's business and must never be claimed by rule 5 —
        # double-reporting one breach under two rules teaches nobody anything and inflates two
        # ratchets at once.
        *'$HOME'*|*'~/'*) continue ;;
        /private/tmp/*|/tmp/*|/var/tmp/*)
          SEAM_TABLE="$SEAM_TABLE${SEAM_TABLE:+
}$f	$n	5a	$d"; contributed=1 ;;
        # Absolute-but-not-/tmp (/bin/launchctl, /usr/bin/python3) is a SYSTEM tool on a read-only
        # volume, not live operator state; a default reached through another variable is that
        # variable's seam, judged where IT is assigned.
        /*|*'$'*|'') continue ;;
        */*) continue ;;
        *[!a-zA-Z0-9._-]*) continue ;;
        *)
          # shape 5b: the default names a tool THIS REPO SHIPS, and the HOLDER is used in command
          # position. Both halves are required — see RULE 5's header on STRICT_TOOLS/PAGE_KEY.
          { [ -f "$root/bin/$d" ] || [ -f "$root/scripts/$d" ] || [ -f "$root/scripts/$d.sh" ] ||
            [ -f "$root/hooks/$d" ] || [ -f "$root/hooks/$d.sh" ]; } || continue
          # shellcheck disable=SC2016  # the quoted halves are a LITERAL pattern; only $holder interpolates
          grep -qE '(^|[[:space:];&|(]|\$\()[[:space:]]*"\$(\{)?'"$holder"'(\})?"?[[:space:]]' "$f" 2>/dev/null || continue
          SEAM_TABLE="$SEAM_TABLE${SEAM_TABLE:+
}$f	$n	5b	$d"; contributed=1 ;;
      esac
    done <<EOF
$(grep -oE "$SEAM_ASSIGN_RE" "$f" 2>/dev/null | sort -u)
EOF
    # Record the tool only if it CONTRIBUTED a row — SEAM_TOOLS is the pre-filter's population, so
    # a seamless tool must not appear in it or the filter stops filtering anything.
    if [ "$contributed" = 1 ]; then
      rel="${f#"$root/"}"
      SEAM_TOOLS="$SEAM_TOOLS $rel"
      SEAM_TOOLS_RE="$SEAM_TOOLS_RE${SEAM_TOOLS_RE:+|}$(printf '%s' "$rel" | sed 's/\./\\./g')"
    fi
  done
  SEAM_TOOLS="${SEAM_TOOLS# }"
  # One alternation over every seam-bearing tool, and DELIBERATELY WITHOUT the trailing boundary
  # class the exact scope test applies. A cost gate must be STRICTLY WEAKER than the test it gates,
  # on every axis, or it stops being a filter and starts being the answer. Two ways that bit here,
  # both measured on the first version, which did carry the boundary:
  #   * CORRECTNESS — grep matches within a line and the line excludes its newline, so `[^A-Za-z0-9_-]`
  #     had nothing to match for a suite naming a tool at END OF LINE, and the suite was skipped
  #     entirely. The exact test does not have that problem (it appends a newline to the whole text).
  #   * PROVABILITY — carrying the same rule made the gate equal-strength on that axis, so it
  #     SHADOWED the exact test: deleting the boundary from seam_names_tool changed no verdict and
  #     the name-boundary control passed against a mutant it was written to kill.
  # `.` is still escaped, so `handoff-fire.sh` cannot match `handoff-fireXsh` — that is not a
  # narrowing, just an escape.
  [ -n "$SEAM_TOOLS_RE" ] && SEAM_TOOLS_RE="/($SEAM_TOOLS_RE)"
  return 0
}

# Build rule 6's INHERITED-VALUE table from <root>'s tool dirs: the INTERSECTION of the variables
# this repo injects into a launched pane and the variables each tool READS as a `${NAME:-` seam.
# TREE-DERIVED ONLY — no `command -v`, no PATH read, no environment read: rule 5's law, and doubly
# binding here, since the whole subject is what the environment happens to carry.
#
# ONE pass and ONE comment strip per tool. The propagated set is not known until every tool has been
# read, so the reads are banked as CANDIDATES and filtered afterwards; running it as two literal
# passes would strip every file twice, and this file's PREDICATE RETRY block is a standing record of
# what fork pressure does to a lint on this box.
#
# COMMENT-STRIPPED through the SHARED strip_comments(), never a private sed — and unlike rule 5's
# ^-anchored table pattern, here it is load-bearing rather than free: `--env NAME=` and `${NAME:-`
# both match anywhere on a line, so unstripped, THIS FILE's own RULE 6 header would mint phantom
# propagated variables out of its prose. Sets ENV_ANCHOR_SEEN when it finds its own anchor.
build_env_table() {
  local root="$1" f rel tok v d rest props="" cands="" exported=""
  local -a files=()
  ENV_TABLE=""; ENV_TOOLS=""; ENV_TOOLS_RE=""; ENV_ANCHOR_SEEN=0; ENV_TABLE_ROOT="$root"
  for f in "$root"/bin/* "$root"/scripts/*.sh "$root"/hooks/*.sh; do
    [ -f "$f" ] && files+=("$f")
  done
  [ "${#files[@]}" -gt 0 ] || return 0
  # A BULK PRE-FILTER, then the real read only for files that can possibly contribute. Stripping and
  # extracting every tool cost 2 forks each — 548 on this tree, and a measured +10s on a 19.5s run,
  # paid by ship-land's fail-fast gate on every land. This narrows it to one bulk grep plus a
  # handful of real reads (measured: 3 files of 274 carry either shape).
  # STRICTLY WEAKER than the extraction it gates, on both axes: it matches the same two shapes on
  # RAW text, so it can only OVER-select — a file it excludes contains neither shape anywhere,
  # comments included, and would have contributed nothing after stripping either. That is the
  # discipline seam_referenced()/env_referenced() already carry, and the reason the strip stays
  # WHOLE-FILE: filtering on grep's own `path:line:` output instead would leave a column-0 comment
  # unstripped (strip_comments' `^#` rule cannot fire behind a path prefix), and THIS FILE's RULE 6
  # header is exactly that shape — it would mint a phantom propagated variable out of its own prose.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    # A heredoc-fed `while` is NOT a subshell, so `props`/`cands` survive the loop.
    while IFS= read -r tok; do
      tok="${tok#"${tok%%[![:space:]]*}"}"     # the `export` arm is ^-anchored, so it carries indent
      [ -n "$tok" ] || continue
      case "$tok" in
        export[[:space:]]*)
          v="${tok#export}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%=}"
          case " $exported " in *" $v "*) ;; *) exported="$exported $v" ;; esac ;;
        --env*)
          v="${tok#*--env}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v#\"}"; v="${v%=}"
          case " $props " in *" $v "*) ;; *) props="$props $v" ;; esac ;;
        \$\{*)
          rest="${tok#\$\{}"; v="${rest%%:-*}"; d="${rest#*:-}"; d="${d%\}}"
          # THERE IS NO $HOME-ROOTED EXCLUSION HERE, AND ITS REMOVAL IS THE WHOLE OF backlog
          # b2775a8bbc3a (2026-08-21). One stood here, reading
          # `case "$d" in *'$HOME'*|*'${HOME'*|*'~/'*) continue ;; esac`, on the argument that a
          # $HOME-rooted default is RULE 1's business. That argument is FALSE for this rule's class,
          # and the row that filed it says why: a $HOME-rooted default is only the FALLBACK, so an
          # ambient value overrides it outright and rule 1's remedy — fixture $HOME in setup() —
          # never touches it. It was not double-reporting a breach rule 1 catches; rule 1 never
          # caught it. The line's own comment conceded exactly this ("That gap is real and is filed
          # SEPARATELY") and then let the gap ride anyway.
          #
          # WHY IT LOOKED LOAD-BEARING AND WAS NOT — the header credited the two exclusions JOINTLY
          # ("between them ... from 123 suites to 1"), so neither figure attributed, and the blanket
          # inherited the pair's whole justification. Separated by A/B against this tree
          # (2026-08-21, both arms the same lint, only this line differing): removing it claims
          # THREE more suites, all for ONE variable — CC_PANE_CMD_DIR — and ZERO more for
          # CLAUDE_CONFIG_DIR, because the EXPORTED test below already removes that one on its own.
          # So the sibling exclusion was doing all the work the pair was credited with, and the
          # blanket's entire remaining effect was to blind rule 6 to CC_PANE_CMD_DIR: injected by
          # bin/it2-kitty:989, in the SAME `--env` block as CC_PANE_CMD_INTERACTIVE, which is rule
          # 6's own founding variable (0588d255). The rule was blind to the sibling of the incident
          # it was built for, and only because that sibling's default happens to mention $HOME.
          #
          # THE HARM WAS MEASURED BEFORE THIS CHANGED, behaviourally rather than by grep: each
          # unpinned in-scope suite run twice, once with CC_PANE_CMD_DIR unset and once pointed at a
          # fresh EMPTY canary dir, comparing verdict AND files created under the canary. 4 of 4
          # clean (rc 0 throughout, no timeouts), so nothing is red today — this is prophylaxis, and
          # it earns its place the way ship-land.sh:1696 argues: it costs no standing list. The
          # probe was positive-controlled first, by deleting the pin from tests/it2-kitty-argv-
          # spawn.bats in a scratch tree — pinned 21/21 both arms with an empty canary, unpinned
          # 13-ok/8-not-ok vs 18-ok/3-not-ok WITH 2 files in the canary. An instrument that cannot
          # fail cannot acquit, and every zero above would otherwise have been a shrug.
          cands="$cands$f	$v
" ;;
      esac
    done <<EOF
$(strip_comments < "$f" 2>/dev/null | grep -oE -- "$ENV_SCAN_RE" | sort -u)
EOF
  done <<EOF
$(grep -lE -- "$ENV_SCAN_RE" "${files[@]}" 2>/dev/null)
EOF
  # Nothing is injected anywhere ⇒ nothing can be inherited ⇒ the rule has no population. That is
  # the honest answer for a tree that launches no panes, and the ANCHOR (not a count) is what tells
  # it apart from an extractor that has simply stopped working.
  [ -n "$props" ] || return 0
  while IFS='	' read -r f v; do
    [ -n "$f" ] || continue
    # THE INTERSECTION. Dropping this test is the filing's naive rule — 1047 seam assignments and
    # most of 324 suites in scope. Dropping the other half instead convicts a tool for a variable it
    # only INJECTS (49 suites, measured); that half is the `case` on $props being reached at all.
    case " $props " in *" $v "*) ;; *) continue ;; esac
    # A variable this repo also EXPORTS as a plain session setting is a CONFIGURED input, not leaked
    # pane state, and is out of rule 6's class. The tree draws this line by itself and it is exactly
    # the line that matters: CC_PANE_CMD / _DIR / _INTERACTIVE are exported NOWHERE — they exist only
    # as pane-launch arguments, so bats seeing one means a fired pane put it there. CLAUDE_CONFIG_DIR
    # is `export`ed by a launcher (bin/claude-kimi), i.e. it is ambient in EVERY session by design;
    # its `--env` site (added 2026-08-08) merely forwards it to one child. Without this test rule 6
    # claimed 72 suites for a variable whose ambience has nothing to do with pane leakage — a
    # different, real gap (does a $HOME fixture cover a config-dir override? it does not), filed as
    # backlog 7c05d45796d8 with its numbers. Not this rule's class, and not something to smuggle in
    # behind it: a naive version of THAT rule hits 123 of 355 suites and needs its own measurement.
    case " $exported " in *" $v "*) continue ;; esac
    [ "$v" = "$ENV_ANCHOR_VAR" ] && ENV_ANCHOR_SEEN=1
    ENV_TABLE="$ENV_TABLE${ENV_TABLE:+
}$f	$v"
    rel="${f#"$root/"}"
    case " $ENV_TOOLS " in
      *" $rel "*) ;;
      *) ENV_TOOLS="$ENV_TOOLS $rel"
         ENV_TOOLS_RE="$ENV_TOOLS_RE${ENV_TOOLS_RE:+|}$(printf '%s' "$rel" | sed 's/\./\\./g')" ;;
    esac
  done <<EOF
$cands
EOF
  ENV_TOOLS="${ENV_TOOLS# }"
  # DELIBERATELY WITHOUT the trailing boundary class the exact scope test applies — a cost gate must
  # be STRICTLY WEAKER than the test it gates, on every axis, or it shadows it. Rule 5's build
  # records both ways that bit (end-of-line misses, and a mutation control passing vacuously).
  [ -n "$ENV_TOOLS_RE" ] && ENV_TOOLS_RE="/($ENV_TOOLS_RE)"
  return 0
}

# The body of a tool's EMBEDDED selftest, comments stripped. Three shapes, matching what the tree
# actually uses: a `selftest()` / `cmd_selftest()` function terminated by a bare `}` at column 0
# (the same convention setup_bodies() relies on), and the `if [ "${1:-}" = "--selftest" ]` block
# terminated by a bare `fi`. COMMENT-STRIPPED for setup_statements()'s reason — a predicate must
# key on what the selftest DOES, never on what it says about itself — using that function's exact
# sed, so the two cannot drift.
selftest_region() {
  awk '/^[[:space:]]*(_?cmd_)?(selftest|_selftest|run_selftest)\(\)[[:space:]]*\{/{inf=1;next}
       inf && /^\}[[:space:]]*$/{inf=0;next}
       inf{print;next}
       /^if \[ "\$\{1:-\}" = "--selftest" \]/{ini=1;next}
       ini && /^fi[[:space:]]*$/{ini=0;next}
       ini{print}' "$1" 2>/dev/null | sed 's/[[:space:]]#.*$//; s/^#.*$//'
}

# The setup()/setup_file() bodies of a suite. Terminator is a bare `}` at column 0 — the convention
# every suite in tests/ follows; the extraction was verified against all 118 before this landed.
setup_bodies() {
  awk '/^[[:space:]]*(setup|setup_file)\(\)[[:space:]]*\{/{inb=1;next}
       inb && /^\}[[:space:]]*$/{inb=0;next}
       inb{print}' "$1" 2>/dev/null
}

# ── COULD-NOT-CHECK is a THIRD state, never a verdict ─────────────────────────────────────────
# Both predicates below are `… | grep -q …`, and grep answers 0=found / 1=not-found / >1=I FAILED.
# Collapsing >1 into "not found" makes a grep that could not RUN indistinguishable from a real
# answer — so under fork pressure (a loaded box, or another session's unscoped pkill reaping this
# lint's children) the ratchet FABRICATES leaks for whichever suites were mid-check.
#
# Measured 2026-07-26 on an unchanged tree: ship-land's ratchet named cc-reconcile.bats +
# kimi-frontend-ab.bats as new leaks while both were allowlisted on that exact tree AND on trunk,
# and 3 direct runs of this same lint reported clean. Earlier the same day it produced four other
# disjoint subsets of already-allowlisted suites (rotate-autonomy-logs; cc-idl+gate-manifest+…;
# cc-crash-report+fire-engagement; find-plan-list-open+lead-crash-watchdog+rm-safe-allowlist).
#
# This is worse than a bare non-verdict because the message NAMES FILES: it reads as an
# attributable RED and sends people to "fix" suites that were never broken (it nearly cost a
# 14-file migration of other streams' tests). ship-land runs this fail-fast BEFORE bats, so one
# fabricated leak kills a land in seconds — repeatedly, and invisibly.
#
# Fix: keep 0 and 1 as answers, and make >1 set CHECK_FAILED so the run exits 2 (LOUD, unusable)
# instead of reporting a violation. Same discipline as the unusable-scan-dir path already here,
# and the repo's standing rule that gate-never-ran is not gate-red.
#
# PREDICATE RETRY. Exiting 2 is honest but still stops a land, and measured over 14 consecutive
# ship-land attempts at load 46-88 EVERY one died here — an honest non-verdict is no more landable
# than a fabricated leak. Both predicates are PURE and CHEAP (a grep over a string / a small file),
# so re-running one is free and side-effect-free, and the failure being retried is transient by
# definition. Three tries, 1s apart, before the run is condemned: that turns the common case
# (a momentarily unavailable fork) into a correct answer, and reserves CHECK_FAILED for a box
# genuinely unable to run a grep three times in a row.
CHECK_FAILED=0

# 0 = hermetic (fixtures $HOME in setup) · 1 = not · sets CHECK_FAILED if the check could not run
# shellcheck disable=SC2016  # the pattern matches the LITERAL string $BATS…; expansion would break it
is_hermetic() {
  local rc bodies
  for _ in 1 2 3; do
    # NOT `setup_bodies "$1" | grep -q …` — see RULE 4's HERE-STRINGS block, whose hazard this
    # predicate was believed too small to hit ("the predicates above pipe from awk over inputs small
    # enough that it has never been observed"). That assumption is REFUTED: the trigger is WHERE the
    # match sits, not how big the input is. grep -q exits at the FIRST match, so a suite whose
    # setup() pins $HOME early leaves awk still writing — SIGPIPE, 141, promoted by
    # `set -o pipefail` into the rc>1 the retry loop reads as "could not RUN".
    #
    # Measured on this tree, 5 consecutive probes per file: tests/cc-notify.bats 5/5 rc=141 ·
    # tests/postland-verify.bats 5/5 rc=141 · tests/handoff-fire-kitty.bats 1/5. The first two are
    # DETERMINISTIC, which is what makes this worse than a flake: the 3-try retry above cannot
    # convert a permanent SIGPIPE into an answer, so CHECK_FAILED latches and ship-land exits 9
    # GATE-KILLED on an unchanged tree — every run, on an idle box, while the banner blames load
    # and says "re-run when the box is quieter". A land that can never be earned by waiting.
    bodies="$(setup_bodies "$1")"
    grep -qE '(export[[:space:]]+HOME=|HOME="\$BATS)' <<< "$bodies"; rc=$?
    case "$rc" in
      0) return 0 ;;
      1) return 1 ;;
    esac
    sleep 1                       # transient fork pressure — see PREDICATE RETRY above
  done
  CHECK_FAILED=1
  echo "test-hermeticity-lint: ⛔ hermeticity check could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
  return 0                        # fail-SAFE: 'hermetic' cannot fabricate a LEAK
}

# ── RULE 2's two predicates. Same shape as is_hermetic(): the same 3-try retry, the same
# CHECK_FAILED third state, and a fail-SAFE direction chosen so a check that could not RUN can never
# fabricate a violation naming a good suite (the 2026-07-26 incident this file's PREDICATE RETRY
# block documents). CHECK_FAILED still forces exit 2, so fail-safe never becomes a silent green.

# strip_comments — the ONE comment-stripping sed, as a stdin filter. Every predicate that must key
# on what a file DOES rather than what it SAYS calls this, so the halves of a rule cannot drift.
strip_comments() { sed 's/[[:space:]]#.*$//; s/^#.*$//'; }

# code_lines <file> — the whole file with comments stripped. The SCOPE predicates' analogue of
# setup_statements(): same sed, whole file rather than the setup() bodies.
code_lines() { strip_comments < "$1"; }

# strip_prose — blank out occurrences of a lever's name that sit MID-SENTENCE, as a stdin filter.
# The one sed for it, for strip_comments' reason: the halves of a rule must not drift.
#
# THE THIRD POSITION A LEVER'S NAME CAN OCCUPY. strip_comments already separated what a suite SAYS
# ABOUT ITSELF (a comment) from what it DOES (code). It cannot separate the remaining pair, because
# both live in code: a PATH to the script, and the same characters inside a STRING the suite is
# merely handling as DATA. tests/cc-eligible-history.bats is the measured case — its only code
# mention is the backlog-row TITLE `"patch scripts/handoff-fire.sh so the recycle inherits the
# goal"`, a fixture specifying an item cc-eligible must REFUSE. The suite fires nothing; it was
# convicted for a sentence, took the prescribed pin as a no-op, and said so in a comment. Same class
# as pgrep-f-matches-agent-briefs: argv carried whole briefs, so a name-match counted every session
# that MENTIONED the subject. Anchor on POSITION, not presence.
#
# 🚨 WHY THIS EXCLUDES PROSE RATHER THAN REQUIRING AN INVOCATION — the narrowing that looks right is
# the one that breaks the rule. Keying scope on an EXECUTION position (the sibling ratchet's `_fires`
# shape, `bash "$HF"`) was built and measured first: it drops 21 suites, and one of them is
# tests/spawn-presence.bats, which EXTRACTS capacity_gate out of the real script and runs it under
# `bash -c`. It is load-sensitive, it pins with form 2, and its setup() cites this rule by name — an
# execution-position predicate cannot see that indirection, so the pin would go unenforced by both
# this lint AND the sibling ratchet. A false negative here is a suite silently reading the live box;
# a false positive is one harmless export. The asymmetry decides it: stay BROAD, and subtract only
# what is provably a sentence. Measured over tests/: 4 suites leave scope, all four prose-only, none
# executing anything (cc-dispatch's stub stderr line, cc-eligible-history's fixture title,
# cc-recover-safeguard's @test name — which literally reads "handoff-fire never invoked" — and
# claude-accounts-fresh-lock-bound's error string). Every executing suite stays in scope, unchanged.
#
# THE PREDICATE: a name followed by TWO consecutive bare lowercase words is prose. A real reference
# is followed by a quote, a path, end-of-line, or a `-`-led flag — never by `so the`. `self-close
# --terminal` survives (the hyphen breaks the second word), which is why spawn-lineage and
# worker-claim-gate-coverage stay in. The bound is deliberately two words, not one: one lowercase
# word after a path is a plausible subcommand, two is a sentence.
#
# PARAMETERISED as of rule 7 (2026-08-13), and by the argument this file has now made five times:
# a hole patched in one twin and left in the other is how the fire half came to be hardened on its
# pin side alone. Rule 7 needs the identical subtraction over four different names, and a private
# copy of this sed is exactly the drift strip_comments exists to prevent. $1 is a lever STEM and is
# interpolated into an ERE — every name this file passes is `[a-z-]+`, which carries no metachar.
strip_prose() { sed -E "s#${1}(\\.sh)?[[:punct:]]?[[:space:]]+[a-z]+[[:space:]]+[a-z]+#<prose>#g"; }

# Is this suite in scope for rule 2 at all? 0 = it references handoff-fire · 1 = it does not.
# Fail-SAFE = 1 (out of scope): an unreadable scope check must not pull a suite INTO the rule.
# Textual by design — a suite that reaches the fire only through some other wrapper is not matched,
# which is a known and accepted floor: the ratchet binds where the evidence is unambiguous.
#
# COMMENT-STRIPPED, and the asymmetry it fixes is the point. This pair's PIN half was hardened for
# exactly this reason ("a predicate must key on what the suite DOES, never on what it says about
# itself") and the SCOPE half was left matching raw prose — so the two halves of one rule disagreed
# about what counts as evidence. It failed in the direction a scope check must never fail: a suite
# that merely NAMES handoff-fire in a comment was pulled INTO the rule and then convicted for not
# pinning a lever it never reads. Measured across tests/ at the time of the fix: 71 suites matched
# the raw grep, 15 of them in prose ONLY, and 9 of those were latent blockers — advisory until
# someone touched the file, then a hard land-block prescribing a meaningless `export` (which, once
# added, would make the suite look permanently in-scope-and-compliant and dilute a real finding).
# One of the 9 was tests/bats-assert-liveness.bats, whose only sin was a comment citing the suite
# that motivated it. A rule that fires on prose is the same defect as one that cannot fire.
# PROSE-STRIPPED as well, since 2026-08-13, and for the same asymmetry the comment fix turned on:
# the name inside a sentence the suite HANDLES is evidence of nothing, exactly as the name inside a
# sentence the suite WRITES was not. See strip_prose above for why this subtracts prose rather than
# demanding an invocation — the invocation form was built, measured, and rejected for a false
# negative on tests/spawn-presence.bats.
references_fire() {
  local rc code
  code="$(code_lines "$1" 2>/dev/null | strip_prose handoff-fire)"
  for _ in 1 2 3; do
    grep -qF 'handoff-fire' <<<"$code"; rc=$?
    case "$rc" in
      0) return 0 ;;
      1) return 1 ;;
    esac
    sleep 1                       # transient fork pressure — see PREDICATE RETRY above
  done
  CHECK_FAILED=1
  echo "test-hermeticity-lint: ⛔ fire-scope check could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
  return 1                        # fail-SAFE: 'not in scope' cannot fabricate an AMBIENT violation
}

# 0 = pins CC_FIRE_CAPACITY_GATE=off in setup() · 1 = does not.
# Fail-SAFE = 0 (pinned): 'pinned' cannot fabricate an AMBIENT violation. It COULD in principle
# fabricate a stuck-ratchet line for an allowlisted suite — but CHECK_FAILED makes the whole run
# exit 2 with an explicit "this is NOT a violation report", exactly as is_hermetic already does.
# COMMENT-STRIPPED for rule 3's reason, retrofitted here: rule 3's bare substring match was proven
# VACUOUS by a suite that merely NAMED its lever in a setup() comment, and this predicate had the
# identical hole — a suite documenting `CC_FIRE_CAPACITY_GATE=off` without setting it would have
# read as pinned. Measured before changing it: across every handoff-fire suite in the tree, ZERO
# verdicts flip, so this closes a latent hole and grandfathers nobody new.
#
# TWO SUFFICIENT FORMS since 2026-08-08, when tests/handoff-fire-cloud.bats (G5, the off-box venue
# branch) became the SECOND suite whose SUBJECT is this gate. Form 1 — the kill switch — is
# unavailable to such a suite BY CONSTRUCTION: pinning the gate off deletes the only thing it
# tests, which is why the incumbent gate suite sits on the allowlist above rather than passing this
# predicate. Sitting on that list is not a form, it is a debt, and this rule's own header says the
# list may only ever shrink.
#
# Form 2 reaches the property this rule actually protects — that the gate cannot read AMBIENT
# machine load — by the other available route. A setup() exporting CC_FIRE_SYSCTL (load and core
# count become stub output) AND CC_FIRE_HEADROOM_OVERRIDE (the memory term becomes a literal) has
# closed BOTH paths by which the real box reaches the gate, so those fires are exactly as
# load-insensitive as form 1's while the coverage survives. Comment-stripped like form 1, and for
# form 1's reason. A suite with NEITHER form is still AMBIENT and still blocks: a second door, not
# a hole.
is_fire_pinned() {
  local rc st
  for _ in 1 2 3; do
    st="$(setup_statements "$1")"
    grep -qF 'CC_FIRE_CAPACITY_GATE=off' <<< "$st"; rc=$?
    if [ "$rc" -eq 1 ] \
       && grep -qF 'CC_FIRE_SYSCTL=' <<< "$st" \
       && grep -qF 'CC_FIRE_HEADROOM_OVERRIDE=' <<< "$st"; then rc=0; fi
    case "$rc" in
      0) return 0 ;;
      1) return 1 ;;
    esac
    sleep 1                       # transient fork pressure — see PREDICATE RETRY above
  done
  CHECK_FAILED=1
  echo "test-hermeticity-lint: ⛔ capacity-pin check could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
  return 0                        # fail-SAFE: 'pinned' cannot fabricate an AMBIENT violation
}

# ── RULE 7's two predicates. Rule 2's pair with the other gate's names, the same 3-try retry, the
# same CHECK_FAILED third state and the same two fail-SAFE directions — deliberately the same shape,
# so the twins can be read side by side and a hole found in one can be checked for in the other.

# The four stems rule 7 scopes on: the library plus its three GATE callers. Kept as one string so
# the scope predicate and this file's header cannot drift about which callers exist. NOT
# handoff-fire: it sources capacity-admit.sh for the shared cc_hw_* terms and evaluates them under
# CC_FIRE_*, never calling cc_capacity_admit — that is rule 2's population, and overlapping the two
# would double-count the same suites under two rules with two remedies.
ADMIT_STEMS="capacity-admit boot-resume-launch lr-fire-resume agent-teams-enforce"

# Is this suite in scope for rule 7 at all? 0 = it names the gate or a gate caller · 1 = it does not.
# Fail-SAFE = 1 (out of scope): an unreadable scope check must not pull a suite INTO the rule.
# COMMENT-STRIPPED and PROSE-STRIPPED through the SHARED filters, for references_fire()'s reasons
# verbatim: a suite that only NAMES a tool in a comment executes nothing, and neither does one
# handling the name inside a sentence. Textual by design, with rule 2's accepted floor — a suite
# reaching the gate only through some other wrapper is not matched.
references_admit() {
  local rc code stem
  code="$(code_lines "$1" 2>/dev/null)"
  for stem in $ADMIT_STEMS; do code="$(printf '%s\n' "$code" | strip_prose "$stem")"; done
  for _ in 1 2 3; do
    grep -qE 'capacity-admit|boot-resume-launch|lr-fire-resume|agent-teams-enforce' <<<"$code"; rc=$?
    case "$rc" in
      0) return 0 ;;
      1) return 1 ;;
    esac
    sleep 1                       # transient fork pressure — see PREDICATE RETRY above
  done
  CHECK_FAILED=1
  echo "test-hermeticity-lint: ⛔ admit-scope check could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
  return 1                        # fail-SAFE: 'not in scope' cannot fabricate an AMBIENT violation
}

# 0 = closes the capacity-ADMIT gate in setup() · 1 = does not.
# Fail-SAFE = 0 (pinned): 'pinned' cannot fabricate an AMBIENT violation. Comment-stripped through
# setup_statements(), so a setup() that merely DOCUMENTS the pin does not read as pinned — the
# prose-match regression rule 3 was proven vacuous by, and rule 2 was retrofitted against.
#
# THREE CLAUSES IN FORM 2, and the third is this rule's whole reason for existing separately from a
# name-swap of is_fire_pinned — see RULE 7's header. The operator RESERVE term (450a47c50) runs over
# an otherwise-admitting box and refuses on a live `ps` census that neither instrument override
# touches. Either spelling closes it: CC_ADMIT_RESERVE_TERM=off skips the term before the presence
# read, and CC_SP_TREES_OVERRIDE pins the census itself.
is_admit_pinned() {
  local rc st
  for _ in 1 2 3; do
    st="$(setup_statements "$1")"
    printf '%s\n' "$st" | grep -qF 'CC_ADMIT_GATE=off'; rc=$?
    if [ "$rc" -eq 1 ] \
       && printf '%s\n' "$st" | grep -qF 'CC_ADMIT_LOADAVG_OVERRIDE=' \
       && printf '%s\n' "$st" | grep -qF 'CC_ADMIT_HEADROOM_OVERRIDE=' \
       && { printf '%s\n' "$st" | grep -qF 'CC_ADMIT_RESERVE_TERM=off' \
            || printf '%s\n' "$st" | grep -qF 'CC_SP_TREES_OVERRIDE='; }; then rc=0; fi
    case "$rc" in
      0) return 0 ;;
      1) return 1 ;;
    esac
    sleep 1                       # transient fork pressure — see PREDICATE RETRY above
  done
  CHECK_FAILED=1
  echo "test-hermeticity-lint: ⛔ admit-pin check could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
  return 0                        # fail-SAFE: 'pinned' cannot fabricate an AMBIENT violation
}

# ── RULE 3's two predicates. Same shape, same retry, same CHECK_FAILED third state, same fail-SAFE
# directions as rule 2's pair above — and same accepted floor: textual, so a suite that reaches the
# close leg through some other wrapper is not matched. The ratchet binds where evidence is plain.

# Is this suite in scope for rule 3? 0 = it invokes the close leg · 1 = it does not.
# Fail-SAFE = 1 (out of scope): an unreadable scope check must not pull a suite INTO the rule.
# COMMENT-STRIPPED for references_fire()'s reason. Rule 3 had ZERO prose-only matches in tests/ when
# that was measured, so this changes no verdict today — it is fixed anyway because the two rules are
# deliberately the same shape, and a hole patched in one twin and left in the other is how the fire
# half came to be hardened on its pin side alone.
references_close_leg() {
  local rc code
  code="$(code_lines "$1" 2>/dev/null)"
  for _ in 1 2 3; do
    grep -qF -- '--close-panes' <<<"$code"; rc=$?
    case "$rc" in
      0) return 0 ;;
      1) return 1 ;;
    esac
    sleep 1                       # transient fork pressure — see PREDICATE RETRY above
  done
  CHECK_FAILED=1
  echo "test-hermeticity-lint: ⛔ close-leg scope check could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
  return 1                        # fail-SAFE: 'not in scope' cannot fabricate an AMBIENT violation
}

# setup_statements <file> — setup bodies with COMMENTS STRIPPED, so a predicate keys on what the
# suite DOES, never on what it says about itself.
#
# Not a refinement: a bare `grep -F LCW_ORPHAN_CLOSE` over the raw body made rule 3 VACUOUS on the
# exact suite it was written for. tests/lead-crash-close-panes.bats documents the lever in its own
# setup() comment ("…carries `export LCW_ORPHAN_CLOSE=1`"), so deleting the actual `unset` left the
# mention behind and the lint stayed GREEN on a genuinely ambient suite — caught only by replaying
# the REAL file instead of the hand-made fixture, which passed either way (memory:
# control-must-replay-the-real-artifact). Same `${line%%#*}` shape scripts/test-walltime-lint.sh
# already uses; a '#' inside a string is over-stripped, which can only ever cost a MENTION, never a
# statement, so the fail direction stays safe.
setup_statements() { setup_bodies "$1" | strip_comments; }

# 0 = takes a deterministic position on LCW_ORPHAN_CLOSE in setup() · 1 = inherits the operator's.
# Any position counts (see RULE 3's ASYMMETRY note) — the violation is inheriting one, not choosing
# the "wrong" one — but it must be a STATEMENT: an assignment (`LCW_ORPHAN_CLOSE=`, with or without
# `export`) or an `unset`, which is why the pattern is anchored rather than a substring match.
# Fail-SAFE = 0 (pinned): 'pinned' cannot fabricate an AMBIENT violation.
is_orphan_pinned() {
  local rc st
  for _ in 1 2 3; do
    # Pipe-free for is_hermetic()'s reason — same producer (`setup_bodies` via `setup_statements`),
    # same early-exit match, same pipefail promotion. Not yet observed firing here only because the
    # pin it looks for is rarer than a $HOME pin; the shape is identical and so is the fix.
    st="$(setup_statements "$1")"
    grep -qE '(^|[[:space:];&|(])(export[[:space:]]+)?LCW_ORPHAN_CLOSE=|(^|[[:space:];&|(])unset([[:space:]]+-[a-zA-Z]+)?([[:space:]]+[A-Za-z_][A-Za-z0-9_]*)*[[:space:]]+LCW_ORPHAN_CLOSE([[:space:]]|$)' <<< "$st"; rc=$?
    case "$rc" in
      0) return 0 ;;
      1) return 1 ;;
    esac
    sleep 1                       # transient fork pressure — see PREDICATE RETRY above
  done
  CHECK_FAILED=1
  echo "test-hermeticity-lint: ⛔ orphan-close pin check could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
  return 0                        # fail-SAFE: 'pinned' cannot fabricate an AMBIENT violation
}

# ── RULE 4's three predicates. Same shape as rules 2-3's pairs: the same 3-try retry, the same
# CHECK_FAILED third state, and fail-SAFE directions chosen so a check that could not RUN can never
# fabricate a violation naming a good tool.
#
# HERE-STRINGS, not `selftest_region "$f" | grep -q …`. This file runs under `set -o pipefail`, and
# a `producer | grep -q` probe returns the PIPELINE's status: grep -q exits the instant it matches,
# the producer takes SIGPIPE, and 141 is promoted — so a MATCH reads as rc>1, which these
# predicates are built to interpret as "the check could not run". Measured elsewhere in this fleet
# at 66% of runs on a hot pipe (memory: pipefail-inverts-early-exit-probe); rule 4's largest
# region is 502 lines and new code should not inherit a hazard it can trivially avoid.
#
# 🚨 **AND THE BET THIS NOTE MADE ABOUT THE OTHER PREDICATES LOST — 2026-08-13.** It used to read
# "the predicates above pipe from awk over inputs small enough that it has never been observed",
# and that clause is why rules 1-3 kept their pipes. **Observed.** `is_hermetic()` reported
# `could not RUN` for 2-3 suites on EVERY run, at load **0.31** on an idle box, taking a `/ship`
# to exit 9 (GATE-KILLED) three times in a row. The set varied run to run (cc-reaper,
# postland-verify, cc-notify) — the signature of a pipe-buffer race, not of a loaded box.
#
# Head-to-head RED-proof, both forms over the same producer and the same suite, 40 trials each:
#   OLD  `setup_bodies "$f" | grep -qE …`  → rc>1 on **36/40** (90%)
#   NEW  `grep -qE … <<< "$bodies"`        → rc>1 on **0/40**
# and the whole-tree effect of the one-line change: the lint went from exiting 2 with no rule-1
# verdict at all, to `clean — 465 suite(s) … 0 new leaks` on 3 consecutive runs.
#
# Two things make this worse than the rule-4 hazard it was compared against:
#   · **It fires BECAUSE the suite is correct.** grep exits early only when it MATCHES, i.e. only
#     when the suite IS hermetic. The more compliant the tree, the likelier the non-verdict.
#   · **The diagnostic sends you the wrong way.** CHECK_FAILED prints "Re-run when the box is
#     quieter; do not 'fix' any suite" — advice that is exactly right for fork pressure and
#     useless here, because there is nothing to wait for. Three honest re-runs bought nothing.
#     The PREDICATE RETRY block above assumes "the failure being retried is transient by
#     definition"; a SIGPIPE race on the same inputs is deterministic enough to exhaust all three.
#
# Whether the race is reachable depends on the platform's pipe buffering and on awk's write
# pattern, which is why macOS never showed it and a Linux container shows it every run. That
# asymmetry is the load-bearing part: **this gate arm is fail-fast and runs BEFORE the smoke, so
# on any box where the race is reachable it makes the repo structurally unlandable** — no amount of
# waiting, and no state of the tree, produces a verdict. Every CHECK_FAILED-bearing predicate in
# this file is now a here-string; none of them pipes into `grep -q`.

# Is this tool in scope for rule 4 at all? 0 = it ships an embedded selftest · 1 = it does not.
# Fail-SAFE = 1 (out of scope): an unreadable scope check must not pull a tool INTO the rule.
has_selftest() {
  local rc
  for _ in 1 2 3; do
    grep -qE '^[[:space:]]*(_?cmd_)?(selftest|_selftest|run_selftest)\(\)[[:space:]]*\{|^if \[ "\$\{1:-\}" = "--selftest" \]' "$1" 2>/dev/null; rc=$?
    case "$rc" in
      0) return 0 ;;
      1) return 1 ;;
    esac
    sleep 1                       # transient fork pressure — see PREDICATE RETRY above
  done
  CHECK_FAILED=1
  echo "test-hermeticity-lint: ⛔ selftest-scope check could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
  return 1                        # fail-SAFE: 'not in scope' cannot fabricate a COLLISION
}

# 0 = the selftest names a CONSTANT /tmp-family path (VIOLATION) · 1 = it names none.
# Fail-SAFE = 1: 'names none' cannot fabricate a violation.
selftest_names_const_path() {
  local rc region
  region="$(selftest_region "$1")"
  for _ in 1 2 3; do
    grep -qE "$SELFTEST_CONST_RE" <<<"$region"; rc=$?
    case "$rc" in
      0) return 0 ;;
      1) return 1 ;;
    esac
    sleep 1                       # transient fork pressure — see PREDICATE RETRY above
  done
  CHECK_FAILED=1
  echo "test-hermeticity-lint: ⛔ constant-path check could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
  return 1                        # fail-SAFE: 'names none' cannot fabricate a COLLISION
}

# 0 = the selftest creates scratch state but never obtains it from mktemp (VIOLATION) · 1 = it
# either creates nothing (out of scope — it cannot collide) or it mktemps.
# Fail-SAFE = 1 in BOTH halves: a check that could not run must not fabricate a violation.
selftest_state_unconfined() {
  local rc region
  region="$(selftest_region "$1")"
  for _ in 1 2 3; do              # SCOPE: does it create scratch state at all?
    grep -qE "$SELFTEST_CREATES_RE" <<<"$region"; rc=$?
    case "$rc" in
      0) break ;;
      1) return 1 ;;              # writes nothing ⇒ nothing to collide on ⇒ never flagged
    esac
    sleep 1                       # transient fork pressure — see PREDICATE RETRY above
  done
  if [ "$rc" -gt 1 ]; then
    CHECK_FAILED=1
    echo "test-hermeticity-lint: ⛔ selftest-writes check could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
    return 1
  fi
  for _ in 1 2 3; do              # POSITION: is that state per-run unique?
    grep -qF 'mktemp' <<<"$region"; rc=$?
    case "$rc" in
      0) return 1 ;;              # mktemp ⇒ a different path every run ⇒ compliant
      1) return 0 ;;              # creates state, never mktemps ⇒ the same path every run
    esac
    sleep 1                       # transient fork pressure — see PREDICATE RETRY above
  done
  CHECK_FAILED=1
  echo "test-hermeticity-lint: ⛔ mktemp check could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
  return 1                        # fail-SAFE: 'confined' cannot fabricate a COLLISION
}

# RULE 5's SCOPE MATCH, factored out so the pre-filter and the real test cannot drift apart —
# a superset filter that used a DIFFERENT boundary rule from the thing it filters for would drop
# suites the rule was meant to judge, silently and only for whichever names disagreed.
# 0 = $1 names $2 (a repo-relative tool path) · 1 = it does not. Pure bash: no fork, so no failure
# mode, so no third state — which is why rule 5 needs only ONE retrying predicate, not two.
# The trailing class-exclusion is what stops `bin/cc-context` matching `bin/cc-context-extra`; the
# appended newline is what lets the same pattern also match at end-of-line.
seam_names_tool() {
  case "$1
" in
    *"/$2"[!A-Za-z0-9_-]*) return 0 ;;
  esac
  return 1
}

# Is this suite in scope for rule 5 AT ALL? 0 = it names some seam-bearing tool · 1 = it does not.
# Purely a COST GATE in front of the per-suite comment strip and setup extraction: it is a strict
# SUPERSET of the exact scope test (stripping comments only ever REMOVES text), so skipping on a
# miss cannot hide a violation. One grep over the raw file beats matching ~16 bash globs against a
# 20-60KB string per suite — measured, the bash form made a full run SLOWER than no filter at all.
# Fail-SAFE = 0 (in scope): an unreadable scope check must leave the suite to the exact predicates
# below rather than silently excusing it, and CHECK_FAILED still forces exit 2.
seam_referenced() {
  local rc
  for _ in 1 2 3; do
    grep -qE "$SEAM_TOOLS_RE" "$1" 2>/dev/null; rc=$?
    case "$rc" in
      0) return 0 ;;
      1) return 1 ;;
    esac
    sleep 1                       # transient fork pressure — see PREDICATE RETRY above
  done
  CHECK_FAILED=1
  echo "test-hermeticity-lint: ⛔ seam scope check could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
  return 0
}

# Does the setup() text in $1 assign seam variable $2? 0 = yes · 1 = no.
#
# NOTE the asymmetry with rules 2-4's position predicates, which is deliberate: this one takes the
# already-extracted setup TEXT rather than a filename, and matches it with bash's own `=~`. It forks
# nothing, so it cannot fail, so it needs no retry and no third state — strictly better than a retry
# loop. That is affordable only because the caller hoists the extraction: a suite is judged on
# several seams, and re-running awk+sed once per seam (rather than once per suite) was the rule's
# largest cost by a wide margin.
is_seam_assigned() {
  [[ "$1" =~ (^|[[:space:]\;\&])(export[[:space:]]+)?"$2"= ]]
}

# Is this suite in scope for rule 6 AT ALL? 0 = it names some tool that reads an injected variable ·
# 1 = it does not. Purely a COST GATE in front of the comment strip and setup extraction, and a
# strict SUPERSET of the exact scope test for seam_referenced()'s reason verbatim (stripping
# comments only ever REMOVES text), so skipping on a miss cannot hide a violation.
# Fail-SAFE = 0 (in scope): an unreadable scope check must leave the suite to the exact predicate
# rather than silently excusing it, and CHECK_FAILED still forces exit 2.
env_referenced() {
  local rc
  for _ in 1 2 3; do
    grep -qE "$ENV_TOOLS_RE" "$1" 2>/dev/null; rc=$?
    case "$rc" in
      0) return 0 ;;
      1) return 1 ;;
    esac
    sleep 1                       # transient fork pressure — see PREDICATE RETRY above
  done
  CHECK_FAILED=1
  echo "test-hermeticity-lint: ⛔ inherited-value scope check could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
  return 0
}

# Does the setup() text in $1 take a DETERMINISTIC POSITION on injected variable $2? 0 = yes · 1 = it
# inherits the operator's.
#
# RULE 3's ASYMMETRY, and here it is FORCED rather than chosen. Rule 5's is_seam_assigned() demands
# `VAR=`; the compliant fix for an inherited value is very often `unset`, and 0588d255 — the fix that
# generated this rule — used exactly that. A predicate that accepted only assignment would report
# that fix still violating, forever, which is the measured reason rule 6 is its own rule (see the
# header). So any position clears it: an assignment (`VAR=`, with or without `export`) or an
# `unset`. What is forbidden is INHERITING one, not choosing the "wrong" one.
#
# Forks nothing, so it cannot fail, so it needs no retry and no third state — is_seam_assigned()'s
# note applies verbatim, including why the caller hoists the setup extraction out of the seam loop.
# Both arms require a BOUNDARY after the name, which is not cosmetic: CC_PANE_CMD is a strict prefix
# of CC_PANE_CMD_DIR and CC_PANE_CMD_INTERACTIVE, so without it a suite pinning only the longer name
# would read as having pinned the shorter one too. Pinned as a control in --selftest.
#
# THE TRAILING CLASS IS WIDER THAN RULE 3'S, and deliberately so — found by MUTATION, not by review.
# Rule 3's is_orphan_pinned() closes its unset arm with `([[:space:]]|$)`, and this predicate was
# written from it. That misses a statement-terminated unset — `unset CC_PANE_CMD;` or
# `unset CC_PANE_CMD && …` — for the LAST name in the list only, since every earlier one is followed
# by a space. The fail direction is the bad one: too NARROW on a PIN test is a false RED, i.e. a
# compliant suite blocked for a position it did in fact take. Rule 3 is left alone (its verdicts are
# measured against its own tree and changing them is not this rule's business), but the divergence is
# recorded here rather than silently inherited, and (o6) pins the widened half.
is_env_pinned() {
  [[ "$1" =~ (^|[[:space:]\;\&\(])(export[[:space:]]+)?"$2"= ]] && return 0
  [[ "$1" =~ (^|[[:space:]\;\&\(])unset([[:space:]]+-[a-zA-Z]+)?([[:space:]]+[A-Za-z_][A-Za-z0-9_]*)*[[:space:]]+"$2"([[:space:]]|[\;\&\)]|$) ]]
}

# 0 = present · 1 = absent · sets CHECK_FAILED if the check could not run
in_allowlist() {
  local rc
  for _ in 1 2 3; do
    grep -qxF "$1" <<< "$2"; rc=$?
    case "$rc" in
      0) return 0 ;;
      1) return 1 ;;
    esac
    sleep 1                       # transient fork pressure — see PREDICATE RETRY above
  done
  CHECK_FAILED=1
  echo "test-hermeticity-lint: ⛔ allowlist check could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
  return 0                        # fail-SAFE: 'allowlisted' cannot fabricate a LEAK
}

# OWN-SCOPE (2026-07-27) — which violations may BLOCK, as distinct from which are REPORTED.
#
# WHY: the ratchet's rule is "do not ADD a leak". Enforcing it over the WHOLE tree makes every
# lander answerable for every other lander's suite, and because trunk is shared that is a
# FLEET-WIDE hard stop. Measured this session: a DOCS-ONLY land (one .md file) was refused by five
# leaking suites it does not touch — cc-close-attrib, claude-accounts-core, claude-kimi,
# completion-assert, fire-autonomy. The lander cannot fix what it did not break, so its only moves
# are "wait for someone else" or "fix five unrelated suites mid-land". One author's omission
# becomes everyone's outage; GATE_ARCHITECTURE_PLAN §9 measures the cost (66% -> 30% land rate).
#
# WHY IT IS NOW SAFE TO SCOPE. The original whole-tree fail-fast had a real premise: an unfixtured
# suite reads AND writes the operator's live ~/, contaminating every other result in the same run.
# Phase 2a (`d9b934ee`, per-gate $HOME isolation via APFS clonefile) removed that premise — the
# gate's bats children run under a CLONED $HOME, so a leak now dirties the clone, not the operator.
# That argument was load-bearing until 2a landed, and is not after. This change is therefore a
# COMPOSITION with 2a, not a weakening of the ratchet.
#
# WHAT DOES NOT CHANGE: the full tree is still scanned and every violation still printed — a leak
# outside the set is LABELLED, never hidden, so "advisory" can never be misread as "clean". Only
# the EXIT CODE narrows. With no own-set the behaviour is byte-identical to before (every violation
# blocks), so --selftest, the postland net, and a bare human invocation are untouched. ship-land is
# the sole opt-in caller. Kill switch: SHIP_LAND_HERM_OWN_SCOPE=off restores whole-tree blocking.
# THREE states, not two — and `${VAR:-}` cannot express them, which is the bug this comment exists
# to prevent recurring. An own-set that is ABSENT means "strict, judge the whole tree" (postland, a
# bare human run). An own-set that is PRESENT BUT EMPTY means "this land changes no suite at all",
# so NOTHING may block — the docs-only land that motivated the fix. Collapsing them with `${3:-}`
# reinstates the exact hard stop being removed, silently and only for the docs-only case. Presence
# is therefore carried by ARGUMENT COUNT here and by `${CC_HERM_OWN+set}` at the entrypoint.
#
# THE BASENAME COLLAPSE, FIXED (2026-08-15, backlog c1a29f8ee045; land-arch §5.P2 arm 1 filed it as
# latent). The old body was `grep -qxF "$1" <<< "$(sed 's:.*/::' <<< "$2")"`: it BASENAMED both
# sides, so an own-set entry `scripts/foo.sh` matched a judged `tests/foo.sh` and the land blocked
# over a file it never touched — the exact fleet-wide-hard-stop direction this whole mechanism
# exists to remove, arriving through the matcher instead of through the scope. Latent only because
# no basename collides across bin/ scripts/ hooks/ tests/ TODAY, which is a property of the tree and
# not of the code (memory: latent-defect-guarded-only-by-a-tree-property).
#
# THE CONTRACT, shared verbatim by test-hermeticity / git-identity / utc-stamp / tsv-pad (four
# copies, one body — they source nothing, and a lint whose correctness-critical predicate arrives
# through an optional `. lib/… || true` degrades SILENTLY when the live layer has not converged):
#   a PATHED entry (contains `/`) matches the judged path exactly, or as a suffix on a COMPONENT
#     boundary — so `tests/foo.bats` matches `/abs/root/tests/foo.bats` and `tests/foo.bats`, and
#     never `scripts/foo.bats`;
#   a BARE entry (no `/`) is a basename by construction and matches in any directory — the width is
#     deliberate and is what callers who pass bare names still rely on.
# Callers therefore pass the PATH, never the basename. Direction on a miss is unchanged and
# fail-PERMISSIVE (not own ⇒ excluded from blocking ⇒ advisory), so this can never fabricate a leak.
# No fork, no pipe: the old spelling paid three processes per call — and per call is ten times per
# suite here — and needed a paragraph about `pipefail` turning a MATCH into 141.
in_own() {  # $1=path the lint knows · $2=own-set text · $3=1 if an own-set was supplied at all
  [ "${3:-0}" = "1" ] || return 0          # no own-set supplied ⇒ everything is own ⇒ strict
  [ -n "$2" ] || return 1                  # supplied but empty ⇒ nothing is own ⇒ nothing blocks
  local e
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    case "$e" in
      */*) [ "$1" = "$e" ] && return 0
           case "$1" in */"$e") return 0 ;; esac ;;
      *)   [ "${1##*/}" = "$e" ] && return 0 ;;
    esac
  done <<< "$2"
  return 1
}

# ── HERM_READSET: the read-set declaration, in executable form ────────────────────────────────────
# Everything a per-suite verdict depends on EXCEPT the suite's own bytes (memo_file_key adds that).
# Called AFTER the seam/env tables are built, because they are part of the read set — building them
# is exactly what makes rules 5 and 6 answerable, and a key computed before them would be keyed on
# the empty string and would carry a verdict earned under a different table.
#
# ANY of these changing must miss. That is why the ALLOWLISTS are hashed by VALUE rather than left
# to the script blob: `CC_HERM_SEAM_ALLOWLIST=…` changes six suites' verdicts without changing one
# byte of this file, and a key that only fingerprinted the file would serve a stale green to the
# next caller who set it. Same for the five rule switches and the two table roots.
herm_memo_arm() {  # $1 = rule 1's allowlist text · $2… = the EXACT ordered suite population
  HERM_MEMO_OK=0
  [ "${CC_HERM_MEMO:-on}" != "off" ] || return 1
  command -v memo_init >/dev/null 2>&1 || return 1
  command -v memo_batch_arm >/dev/null 2>&1 || return 1   # an older lib ⇒ memo OFF, today's behaviour
  memo_init || return 1                    # dirty tree · no git dir · unwritable store ⇒ memo OFF
  local selfblob readset
  selfblob="$(git hash-object -- "$SELF_ABS" 2>/dev/null)" || return 1
  [ -n "$selfblob" ] || return 1
  readset="$(
    printf 'herm-readset/v1\n'
    printf 'lint=%s\n'        "$selfblob"
    printf 'rules=%s|%s|%s|%s|%s\n' "$FIRE_RULE" "$ORPHAN_RULE" "$SEAM_RULE" "$ENV_RULE" "$ADMIT_RULE"
    printf 'allow=%s\n'       "$1"
    printf 'fire_allow=%s\n'  "$FIRE_ALLOW"
    printf 'orph_allow=%s\n'  "$ORPHAN_ALLOW"
    printf 'seam_allow=%s\n'  "$SEAM_ALLOW"
    printf 'env_allow=%s\n'   "$ENV_ALLOW"
    printf 'admit_allow=%s\n' "$ADMIT_ALLOW"
    printf 'seam_root=%s\n'   "$SEAM_ROOT"
    printf 'env_root=%s\n'    "$ENV_ROOT"
    printf 'seam_table=%s\n'  "$SEAM_TABLE"
    printf 'env_table=%s\n'   "$ENV_TABLE"
  )" || return 1
  # The checker-id carries the read set, so gate-memo's audited per-file primitives can be reused
  # unchanged: memo_file_key already folds in its own salt (the interpreters' versions) and the
  # file's blob sha, and an exact literal match of the whole entry is already what a hit requires.
  HERM_CHECKER="herm/$(printf '%s' "$readset" | git hash-object --stdin 2>/dev/null)"
  [ "$HERM_CHECKER" != "herm/" ] || return 1
  # THE BATCH: one `git hash-object` fork for all 468 suites instead of three forks per suite. The
  # per-file API this replaces cost 16.8 ms per lookup against a 69 ms per-suite check — real, but
  # it was quietly spending a quarter of what it saved. memo_batch_arm refuses (⇒ memo OFF ⇒
  # today's behaviour) on an empty population or a short batch; see gate-memo.sh's alignment control.
  shift
  memo_batch_arm "$HERM_CHECKER" "$@" || return 1
  HERM_MEMO_OK=1
  return 0
}

# THE EMIT DETECTOR. Every branch in lint_dir that prints a finding also increments exactly one of
# these thirteen counters, so their sum is unchanged across a suite IFF that suite emitted nothing.
# Two lines instead of an `emitted=1` on twenty printf sites — but it is only true while it stays
# true, so --selftest pins a violating suite under EVERY rule as never-memoized (herm_memo cases
# below). A new rule that prints without counting would be caught there, not here.
herm_emit_sum() {
  printf '%s' "$(( new_leak + stuck + other + fire_leak + fire_stuck + orphan_leak + orphan_stuck \
                 + seam_leak + seam_stuck + env_leak + env_stuck + admit_leak + admit_stuck ))"
}

HERM_CHECKER=""
HERM_MEMO_HITS=0
HERM_MEMO_RAN=0
HERM_FILES=()      # the suite population, built once per lint_dir call — see the note at its build

# lint <tests-dir> <allowlist-text> [own-set-text] — 0 clean · 1 violations · 2 unusable scan dir
lint_dir() {
  local dir="$1" allow="$2" own="${3:-}" own_scoped=0 f base new_leak=0 stuck=0 seen=0 other=0
  local fire_allow="$FIRE_ALLOW" fire_leak=0 fire_stuck=0
  local orphan_allow="$ORPHAN_ALLOW" orphan_leak=0 orphan_stuck=0
  local seam_allow="$SEAM_ALLOW" seam_leak=0 seam_stuck=0
  local seam_text="" seam_setup="" seam_why="" s_tool s_var s_cls s_def
  local env_allow="$ENV_ALLOW" env_leak=0 env_stuck=0
  local env_text="" env_setup="" env_why="" env_seen="" e_tool e_var
  local admit_allow="$ADMIT_ALLOW" admit_leak=0 admit_stuck=0
  local _herm_emit0=0
  [ "$#" -ge 3 ] && own_scoped=1
  CHECK_FAILED=0
  [ -d "$dir" ] || { echo "test-hermeticity-lint: ⛔ not a directory: $dir" >&2; return 2; }
  # RULE 5's seam table, built ONCE per run off SEAM_ROOT — not off "$dir". The two populations are
  # different sets (tools vs suites), the same split rule 4's own pass exists to keep.
  if [ "$SEAM_RULE" = on ] && [ "$SEAM_TABLE_ROOT" != "$SEAM_ROOT" ]; then
    build_seam_table "$SEAM_ROOT"
    # THE EXTRACTOR CONTROL, and deliberately NOT a count — rule 4's argument verbatim. This script
    # carries SEAM_SELF_ANCHOR by construction, so if it is inside the scanned root the extractor
    # must have found it. Absent the anchor, an empty table is the honest answer for a small tree.
    if [ -f "$SEAM_ROOT/scripts/$(basename "$SELF")" ] && [ "$SEAM_ANCHOR_SEEN" -eq 0 ]; then
      echo "test-hermeticity-lint: ⛔ the seam extractor did not detect its OWN anchor ($SEAM_ANCHOR_VAR) in $SEAM_ROOT/scripts/$(basename "$SELF")" >&2
      echo "  That file carries a shape-5a seam by construction, so this is the EXTRACTOR failing, not a clean tree." >&2
      echo "  Every rule-5 verdict in this run is therefore void; do not read it as a clean bill." >&2
      return 2
    fi
  fi
  # RULE 6's inherited-value table, built ONCE per run off ENV_ROOT — rule 5's split verbatim: the
  # tools and the suites are different populations.
  if [ "$ENV_RULE" = on ] && [ "$ENV_TABLE_ROOT" != "$ENV_ROOT" ]; then
    build_env_table "$ENV_ROOT"
    # THE EXTRACTOR CONTROL, and deliberately NOT a count — rules 4 and 5's argument verbatim. This
    # script declares the anchor in BOTH halves by construction, so if it is inside the scanned root
    # the extractor must have found it. Absent the anchor, an empty table is the honest answer for a
    # tree that launches no panes.
    if [ -f "$ENV_ROOT/scripts/$(basename "$SELF")" ] && [ "$ENV_ANCHOR_SEEN" -eq 0 ]; then
      echo "test-hermeticity-lint: ⛔ the inherited-value extractor did not detect its OWN anchor ($ENV_ANCHOR_VAR) in $ENV_ROOT/scripts/$(basename "$SELF")" >&2
      echo "  That file declares it as BOTH an injection and a read by construction, so this is the EXTRACTOR failing, not a clean tree." >&2
      echo "  Every rule-6 verdict in this run is therefore void; do not read it as a clean bill." >&2
      return 2
    fi
  fi
  # THE POPULATION, BUILT EXACTLY ONCE. The batch memo is INDEX-KEYED, so the list it arms on and
  # the list this loop walks must be the same list — not two globs written to look alike. Building
  # it twice is the only way this API can serve one suite's verdict for another, so it is built
  # once and both the arm and the loop consume THIS array. (Repo memory: assertion-span-must-equal-
  # its-subject — the span of the key has to equal the span of the walk.)
  HERM_FILES=()
  for f in "$dir"/*.bats; do
    [ -e "$f" ] || continue
    HERM_FILES[${#HERM_FILES[@]}]="$f"
  done
  # ARMED HERE, after both tables exist — they are part of the read set (see herm_memo_arm).
  HERM_MEMO_HITS=0; HERM_MEMO_RAN=0
  if [ "${#HERM_FILES[@]}" -gt 0 ]; then
    herm_memo_arm "$allow" "${HERM_FILES[@]}" || true
  fi
  for f in ${HERM_FILES[@]+"${HERM_FILES[@]}"}; do
    seen=$((seen + 1)); base="$(basename "$f")"
    # ── THE MEMO HIT: this exact content already emitted nothing under this exact read set. ──
    # `seen` is incremented above regardless, so the census the run reports is the whole corpus and
    # never the miss-list — a count that shrank with the cache would be the memo lying about scope.
    # THE INDEX IS `seen - 1`, DERIVED AND NEVER PARALLEL. `seen` is incremented exactly once per
    # iteration, as the first statement of the body and before any `continue`, so it cannot drift
    # from the position in HERM_FILES the way a second counter could. One counter, one source of
    # truth — a separate index variable is the shape that eventually gets incremented in the wrong
    # branch and quietly serves suite N's verdict for suite N+1.
    if [ "$HERM_MEMO_OK" = "1" ] && memo_batch_hit "$((seen - 1))"; then
      HERM_MEMO_HITS=$((HERM_MEMO_HITS + 1))
      continue
    fi
    _herm_emit0="$(herm_emit_sum)"
    HERM_MEMO_RAN=$((HERM_MEMO_RAN + 1))
    if is_hermetic "$f"; then
      if in_allowlist "$base" "$allow"; then
        if in_own "$f" "$own" "$own_scoped"; then
          printf '  RATCHET  %s is hermetic now — delete its allowlist line\n' "$base"
          stuck=$((stuck + 1))
        else
          printf '  ratchet? %s is hermetic but still grandfathered (NOT in your diff — advisory)\n' "$base"
          other=$((other + 1))
        fi
      fi
    elif ! in_allowlist "$base" "$allow"; then
      if in_own "$f" "$own" "$own_scoped"; then
        # shellcheck disable=SC2016  # "$HOME" is prose here — the message names the variable, not its value
        printf '  LEAK     %s: setup() does not fixture $HOME — it runs against the live ~/\n' "$base"
        new_leak=$((new_leak + 1))
      else
        # shellcheck disable=SC2016  # ditto — prose naming the variable, not an expansion
        printf '  leak?    %s does not fixture $HOME (NOT in your diff — advisory, not blocking)\n' "$base"
        other=$((other + 1))
      fi
    fi
    # ── RULE 2, applied INDEPENDENTLY of rule 1 (a suite can violate either, both, or neither) and
    # ONLY to suites that reference handoff-fire. A suite that never touches the fire is out of
    # scope and must never appear here — that scoping is the whole reason references_fire() exists.
    if [ "$FIRE_RULE" = on ] && references_fire "$f"; then
      if is_fire_pinned "$f"; then
        if in_allowlist "$base" "$fire_allow"; then
          if in_own "$f" "$own" "$own_scoped"; then
            printf '  RATCHET-CAP  %s pins the capacity gate now — delete its FIRE allowlist line\n' "$base"
            fire_stuck=$((fire_stuck + 1))
          else
            printf '  ratchet-cap? %s pins the gate but is still grandfathered (NOT in your diff — advisory)\n' "$base"
            other=$((other + 1))
          fi
        fi
      elif ! in_allowlist "$base" "$fire_allow"; then
        if in_own "$f" "$own" "$own_scoped"; then
          printf '  AMBIENT  %s: setup() does not pin CC_FIRE_CAPACITY_GATE=off — its fires read live machine load\n' "$base"
          fire_leak=$((fire_leak + 1))
        else
          printf '  ambient? %s does not pin CC_FIRE_CAPACITY_GATE=off (NOT in your diff — advisory, not blocking)\n' "$base"
          other=$((other + 1))
        fi
      fi
    fi
    # ── RULE 7, applied INDEPENDENTLY of rules 1-6 and placed HERE rather than after rule 6 so it
    # sits beside the twin it was cloned from. ONLY to suites naming capacity-admit or a gate caller;
    # a suite that never reaches that gate is out of scope and must never appear here — that scoping
    # is the whole reason references_admit() exists. Rule 2's population and this one are disjoint by
    # construction (handoff-fire is not a caller), so a suite listed under both is genuinely
    # violating both, not double-counted.
    if [ "$ADMIT_RULE" = on ] && references_admit "$f"; then
      if is_admit_pinned "$f"; then
        if in_allowlist "$base" "$admit_allow"; then
          if in_own "$f" "$own" "$own_scoped"; then
            printf '  RATCHET-ADM  %s closes the capacity-admit gate now — delete its ADMIT allowlist line\n' "$base"
            admit_stuck=$((admit_stuck + 1))
          else
            printf '  ratchet-adm? %s closes the admit gate but is still grandfathered (NOT in your diff — advisory)\n' "$base"
            other=$((other + 1))
          fi
        fi
      elif ! in_allowlist "$base" "$admit_allow"; then
        if in_own "$f" "$own" "$own_scoped"; then
          printf '  AMBIENT  %s: setup() does not close capacity-admit — its gate reads live load, memory and session census\n' "$base"
          admit_leak=$((admit_leak + 1))
        else
          printf '  ambient? %s does not close capacity-admit (NOT in your diff — advisory, not blocking)\n' "$base"
          other=$((other + 1))
        fi
      fi
    fi
    # ── RULE 3, applied INDEPENDENTLY of rules 1 and 2 (a suite can violate any, all, or none) and
    # ONLY to suites that invoke the close leg. A suite that never drives `--close-panes` is out of
    # scope and must never appear here — that scoping is why references_close_leg() exists.
    if [ "$ORPHAN_RULE" = on ] && references_close_leg "$f"; then
      if is_orphan_pinned "$f"; then
        if in_allowlist "$base" "$orphan_allow"; then
          if in_own "$f" "$own" "$own_scoped"; then
            printf '  RATCHET-ORPH %s pins LCW_ORPHAN_CLOSE now — delete its ORPHAN allowlist line\n' "$base"
            orphan_stuck=$((orphan_stuck + 1))
          else
            printf '  ratchet-orph? %s pins the lever but is still grandfathered (NOT in your diff — advisory)\n' "$base"
            other=$((other + 1))
          fi
        fi
      elif ! in_allowlist "$base" "$orphan_allow"; then
        if in_own "$f" "$own" "$own_scoped"; then
          printf '  AMBIENT  %s: setup() does not pin LCW_ORPHAN_CLOSE — its close leg inherits this box'"'"'s arming\n' "$base"
          orphan_leak=$((orphan_leak + 1))
        else
          printf '  ambient? %s does not pin LCW_ORPHAN_CLOSE (NOT in your diff — advisory, not blocking)\n' "$base"
          other=$((other + 1))
        fi
      fi
    fi
    # ── RULE 5, applied INDEPENDENTLY of rules 1-3 (a suite can violate any, all, or none) and ONLY
    # to suites naming a tool that HAS a non-$HOME seam. A suite naming no such tool is out of scope
    # and must never appear here — that scoping is the whole reason the seam table is consulted
    # per-tool rather than the rule simply demanding a pin of everyone.
    if [ "$SEAM_RULE" = on ] && [ -n "$SEAM_TABLE" ]; then
      seam_why=""
      # The pre-filter runs FIRST and everything below it is hoisted behind it: ~4 of every 5 suites
      # name no seam-bearing tool, and those now cost one grep instead of a comment strip plus a
      # setup extraction. Both of the remaining extractions are done ONCE per suite, not once per
      # seam — a suite is judged on several seams, and re-running awk+sed for each was the rule's
      # dominant cost.
      if seam_referenced "$f"; then
      # Comment-stripped through the SHARED code_lines(), never a private sed. A suite that only
      # NAMES a tool in prose executes nothing — the lesson b00a5010 landed for rules 2 and 3's
      # scope halves after their pin halves had been hardened alone, and the reason that fix
      # introduced one filter for every predicate to call: the halves of a rule must not be able to
      # disagree about what counts as evidence, and neither must the rules.
      seam_text="$(code_lines "$f" 2>/dev/null)"
      seam_setup="$(setup_statements "$f")"
      while IFS='	' read -r s_tool s_var s_cls s_def; do
        [ -n "$s_tool" ] || continue
        seam_names_tool "$seam_text" "${s_tool#"$SEAM_ROOT/"}" || continue
        is_seam_assigned "$seam_setup" "$s_var" && continue
        # BRACED deliberately: a bare `$s_cls→` makes bash read the arrow's first UTF-8 byte as part
        # of the NAME, and under `set -u` that is an unbound-variable abort which kills this loop
        # mid-suite — silently, because the rule's only output is the line it never reaches.
        seam_why="$seam_why${seam_why:+, }${s_var} (${s_cls}→${s_def})"
      done <<EOF
$SEAM_TABLE
EOF
      fi
      if [ -z "$seam_why" ]; then
        if in_allowlist "$base" "$seam_allow"; then
          if in_own "$f" "$own" "$own_scoped"; then
            # shellcheck disable=SC2016  # "$HOME" is prose here — the message names the variable, not its value
            printf '  RATCHET-SEAM %s pins its non-$HOME seams now — delete its SEAM allowlist line\n' "$base"
            seam_stuck=$((seam_stuck + 1))
          else
            printf '  ratchet-seam? %s pins its seams but is still grandfathered (NOT in your diff — advisory)\n' "$base"
            other=$((other + 1))
          fi
        fi
      elif ! in_allowlist "$base" "$seam_allow"; then
        if in_own "$f" "$own" "$own_scoped"; then
          # shellcheck disable=SC2016  # ditto — prose naming the variable, not an expansion
          printf '  SEAM     %s: setup() leaves a non-$HOME seam unpinned — %s\n' "$base" "$seam_why"
          seam_leak=$((seam_leak + 1))
        else
          # shellcheck disable=SC2016  # ditto
          printf '  seam?    %s leaves a non-$HOME seam unpinned (NOT in your diff — advisory, not blocking)\n' "$base"
          other=$((other + 1))
        fi
      fi
    fi
    # ── RULE 6, applied INDEPENDENTLY of rules 1-5 (a suite can violate any, all, or none) and ONLY
    # to suites naming a tool that READS a variable this repo INJECTS into a launched pane. A suite
    # naming no such tool is out of scope and must never appear here — and neither must a suite
    # naming a tool that only INJECTS one, which is why the table is an INTERSECTION rather than
    # either half (see RULE 6's header: that control alone is worth 49 suites).
    if [ "$ENV_RULE" = on ] && [ -n "$ENV_TABLE" ]; then
      env_why=""; env_seen=""
      # The pre-filter runs FIRST and both extractions are hoisted behind it, ONCE per suite rather
      # than once per variable — rule 5's cost argument verbatim.
      if env_referenced "$f"; then
      # Comment-stripped through the SHARED code_lines(), and matched with the SHARED
      # seam_names_tool(): rules 5 and 6 must not be able to disagree about what counts as naming a
      # tool, for the same reason the halves of ONE rule must not (b00a5010).
      env_text="$(code_lines "$f" 2>/dev/null)"
      env_setup="$(setup_statements "$f")"
      while IFS='	' read -r e_tool e_var; do
        [ -n "$e_tool" ] || continue
        seam_names_tool "$env_text" "${e_tool#"$ENV_ROOT/"}" || continue
        is_env_pinned "$env_setup" "$e_var" && continue
        # Two tools can read the SAME injected variable (the pane runner and the terminal shim both
        # do), so a suite naming both would otherwise report it twice. Delimited, never a substring
        # test: CC_PANE_CMD is a strict prefix of two of its siblings.
        case " $env_seen " in *" $e_var "*) continue ;; esac
        env_seen="$env_seen $e_var"
        env_why="$env_why${env_why:+, }$e_var"
      done <<EOF
$ENV_TABLE
EOF
      fi
      if [ -z "$env_why" ]; then
        if in_allowlist "$base" "$env_allow"; then
          if in_own "$f" "$own" "$own_scoped"; then
            printf '  RATCHET-ENV  %s pins its inherited-value seams now — delete its ENV allowlist line\n' "$base"
            env_stuck=$((env_stuck + 1))
          else
            printf '  ratchet-env? %s pins its inherited seams but is still grandfathered (NOT in your diff — advisory)\n' "$base"
            other=$((other + 1))
          fi
        fi
      elif ! in_allowlist "$base" "$env_allow"; then
        if in_own "$f" "$own" "$own_scoped"; then
          printf '  INHERIT  %s: setup() takes no position on a variable its subject READS and this repo INJECTS into every pane — %s\n' "$base" "$env_why"
          env_leak=$((env_leak + 1))
        else
          printf '  inherit? %s inherits an injected variable (NOT in your diff — advisory, not blocking)\n' "$base"
          other=$((other + 1))
        fi
      fi
    fi
    # ── THE RECORD, and it is the ONLY place a green is earned. Two vetoes, both fail-safe: ──
    # (1) the suite emitted something under some rule ⇒ it is a finding, and a finding is never
    #     cached (gate-memo invariant 1) — it must re-print itself on every run, from the file.
    # (2) CHECK_FAILED is set ⇒ a predicate somewhere in this run could not RUN. is_hermetic's third
    #     state returns fail-SAFE 'hermetic' precisely so a dead grep cannot fabricate a leak, which
    #     means a non-verdict LOOKS exactly like a clean suite here. Caching that would freeze a
    #     could-not-check into a permanent green keyed on the file's content — the one way this memo
    #     could turn "I don't know" into "green", which is the invariant it exists under.
    #
    #     🚨 ABSOLUTE, not a per-suite delta, and the difference is a bug this file shipped for one
    #     iteration. A delta (`CHECK_FAILED != $_herm_cf0`) vetoes only the FIRST suite whose
    #     predicate dies: every suite after it compares 1-to-1, comes out equal, and is recorded —
    #     out of a run that exits 2 and whose whole point is that it produced no verdict. Selftest
    #     case (a6) is what caught it, on the unmutated file.
    if [ "$HERM_MEMO_OK" = "1" ] \
       && [ "$(herm_emit_sum)" = "$_herm_emit0" ] \
       && [ "$CHECK_FAILED" -eq 0 ]; then
      memo_batch_record "$((seen - 1))"
    fi
  done
  if [ "$HERM_MEMO_OK" = "1" ]; then
    echo "test-hermeticity-lint: per-suite memo — $HERM_MEMO_HITS suite verdict(s) carried, $HERM_MEMO_RAN proven fresh." >&2
  fi
  [ "$seen" -gt 0 ] || { echo "test-hermeticity-lint: ⛔ no .bats suites under $dir" >&2; return 2; }
  [ "$other" -eq 0 ] || echo "test-hermeticity-lint: $other pre-existing violation(s) NOT in your diff — reported, not blocking (own-scope)."
  # A run whose own predicates could not execute has no verdict to give. Exit 2 (unusable), the
  # same code as a bad scan dir — NOT 1, which a caller reads as "your tree is dirty". Checked
  # AFTER the own-scope report so a killed predicate cannot masquerade as a clean own-scope pass:
  # own-scope narrows WHICH violations block, it does not make an unrunnable check trustworthy.
  if [ "$CHECK_FAILED" -ne 0 ]; then
    echo "test-hermeticity-lint: ⛔ UNUSABLE — a predicate failed to run (see above); no verdict." >&2
    echo "  This is NOT a leak report. Re-run when the box is quieter; do not 'fix' any suite on it." >&2
    return 2
  fi

  if [ "$new_leak" -gt 0 ]; then
    echo "test-hermeticity-lint: ⛔ $new_leak new non-hermetic suite(s) above."
    echo "  Fix: in setup(), \`export HOME=\"\$BATS_TEST_TMPDIR/home\"; mkdir -p \"\$HOME\"\`, then"
    echo "       seed whatever fixture state the subject reads under it. Do NOT add to the allowlist."
  fi
  if [ "$stuck" -gt 0 ]; then
    echo "test-hermeticity-lint: ⛔ $stuck suite(s) above are fixed but still grandfathered."
    echo "  Fix: delete their lines from EMBEDDED_ALLOWLIST in $0 — the ratchet only shrinks."
  fi
  if [ "$fire_leak" -gt 0 ]; then
    echo "test-hermeticity-lint: ⛔ $fire_leak suite(s) above exercise handoff-fire against AMBIENT machine load."
    echo "  WHY: handoff-fire's capacity_gate() refuses a net-new fire above ${CC_FIRE_MAX_LOAD_PER_CORE:-2.0}/core"
    echo "       and this box lives well above that, so the suite goes red-by-load, not by its subject."
    echo "  Fix: in setup(), \`export CC_FIRE_CAPACITY_GATE=off\`. Do NOT add to the fire allowlist."
  fi
  if [ "$fire_stuck" -gt 0 ]; then
    echo "test-hermeticity-lint: ⛔ $fire_stuck suite(s) above pin the capacity gate but are still grandfathered."
    echo "  Fix: delete their lines from EMBEDDED_FIRE_ALLOWLIST in $0 — the ratchet only shrinks."
  fi
  if [ "$admit_leak" -gt 0 ]; then
    echo "test-hermeticity-lint: ⛔ $admit_leak suite(s) above reach scripts/lib/capacity-admit.sh against AMBIENT machine state."
    echo "  WHY: that gate refuses with exit 9 above ${CC_ADMIT_MAX_LOAD_PER_CORE:-2.0}/core, below"
    echo "       ${CC_ADMIT_MIN_HEADROOM_GB:-4}GB reclaimable, or — since 450a47c50 — when a LIVE \`ps\` census of"
    echo "       session trees plus the operator's presence says autonomy must yield. This box trips all"
    echo "       three, so the suite goes red-by-desk, not by its subject (backlog 5ef0dcb22aec:"
    echo "       tests/kitty-recovery-launch.bats, red 3x in a 228-test sweep and green in isolation)."
    echo "  Fix: in setup(), \`export CC_ADMIT_GATE=off\`. If the gate IS your subject, pin all three"
    echo "       terms instead: CC_ADMIT_LOADAVG_OVERRIDE + CC_ADMIT_HEADROOM_OVERRIDE + either"
    echo "       CC_ADMIT_RESERVE_TERM=off or CC_SP_TREES_OVERRIDE. Do NOT add to the admit allowlist."
  fi
  if [ "$admit_stuck" -gt 0 ]; then
    echo "test-hermeticity-lint: ⛔ $admit_stuck suite(s) above close the capacity-admit gate but are still grandfathered."
    echo "  Fix: delete their lines from EMBEDDED_ADMIT_ALLOWLIST in $0 — the ratchet only shrinks."
  fi
  if [ "$orphan_leak" -gt 0 ]; then
    echo "test-hermeticity-lint: ⛔ $orphan_leak suite(s) above drive the orphaned-pane close leg against an AMBIENT arming lever."
    echo "  WHY: ~/.zshrc sources ~/.claude/autonomy/watchdog.env, which exports LCW_ORPHAN_CLOSE=1, so"
    echo "       every bats run inherits an ARMED actuator and the suite's DEFAULT-OFF tests test this box."
    echo "  Fix: in setup(), \`unset LCW_ORPHAN_CLOSE\` (or pin whatever value the fixture needs)."
    echo "       Do NOT add to the orphan allowlist — it ships empty and is meant to stay that way."
  fi
  if [ "$orphan_stuck" -gt 0 ]; then
    echo "test-hermeticity-lint: ⛔ $orphan_stuck suite(s) above pin LCW_ORPHAN_CLOSE but are still grandfathered."
    echo "  Fix: delete their lines from EMBEDDED_ORPHAN_ALLOWLIST in $0 — the ratchet only shrinks."
  fi
  if [ "$seam_leak" -gt 0 ]; then
    # shellcheck disable=SC2016  # "$HOME" is prose here — the message names the variable, not its value
    echo "test-hermeticity-lint: ⛔ $seam_leak suite(s) above name a tool whose state does NOT resolve under \$HOME."
    # shellcheck disable=SC2016
    echo "  WHY: fixturing \$HOME does not redirect an ABSOLUTE /tmp default (5a) or a BARE NAME the"
    echo "       subject then EXECUTES off the operator's PATH (5b). tests/cc-relogin-status.bats"
    echo "       fixtured \$HOME from birth and still counted the operator's live pending approvals"
    echo "       and ran their deployed claude-accounts once per test (a514d3b0)."
    echo "  Fix: in setup(), \`export <SEAM>=\"\$BATS_TEST_TMPDIR/<name>\"\` for each seam named above —"
    echo "       an ABSENT path is usually right, since these sensors fail open on one. Do NOT add to"
    echo "       the seam allowlist."
  fi
  if [ "$seam_stuck" -gt 0 ]; then
    echo "test-hermeticity-lint: ⛔ $seam_stuck suite(s) above pin their non-\$HOME seams but are still grandfathered."
    echo "  Fix: delete their lines from EMBEDDED_SEAM_ALLOWLIST in $0 — the ratchet only shrinks."
  fi
  if [ "$env_leak" -gt 0 ]; then
    echo "test-hermeticity-lint: ⛔ $env_leak suite(s) above INHERIT a variable their subject reads."
    echo "  WHY: this repo injects those variables into every pane it launches, so every DESCENDANT of"
    echo "       a fired pane carries them — including bats, when an agent runs the suite from the pane"
    echo "       that fired it. The suite then goes red exactly THERE and green everywhere else, so it"
    echo "       reads as a genuine trunk red (0588d255: 5 failures, one of them a negative CONTROL)."
    echo "  Fix: in setup(), \`unset <VAR>\` — or assign it, if the suite needs a value. Either counts;"
    echo "       what is forbidden is inheriting one. Do NOT add to the inherited-value allowlist."
  fi
  if [ "$env_stuck" -gt 0 ]; then
    echo "test-hermeticity-lint: ⛔ $env_stuck suite(s) above pin their inherited-value seams but are still grandfathered."
    echo "  Fix: delete their lines from EMBEDDED_ENV_ALLOWLIST in $0 — the ratchet only shrinks."
  fi
  [ $((new_leak + stuck + fire_leak + fire_stuck + orphan_leak + orphan_stuck + seam_leak + seam_stuck + env_leak + env_stuck + admit_leak + admit_stuck)) -eq 0 ] || return 1
  # The summary must say what was ENFORCED, not what is merely on disk: with rule 2 killed, printing
  # its grandfather count would read as "43 suites checked and grandfathered" when zero were checked.
  local fire_note orphan_note
  if [ "$FIRE_RULE" = on ]; then
    fire_note="$(printf '%s\n' "$fire_allow" | grep -c .) grandfathered (capacity gate)"
  else
    fire_note="capacity-gate rule OFF (CC_HERM_FIRE_RULE)"
  fi
  if [ "$ORPHAN_RULE" = on ]; then
    orphan_note="$(printf '%s\n' "$orphan_allow" | grep -c .) grandfathered (orphan-close lever)"
  else
    orphan_note="orphan-close rule OFF (CC_HERM_ORPHAN_RULE)"
  fi
  local seam_note env_note
  if [ "$SEAM_RULE" = on ]; then
    seam_note="$(printf '%s\n' "$seam_allow" | grep -c .) grandfathered (non-\$HOME seam)"
  else
    seam_note="non-\$HOME seam rule OFF (CC_HERM_SEAM_RULE)"
  fi
  if [ "$ENV_RULE" = on ]; then
    env_note="$(printf '%s\n' "$env_allow" | grep -c .) grandfathered (inherited value)"
  else
    env_note="inherited-value rule OFF (CC_HERM_ENV_RULE)"
  fi
  local admit_note
  if [ "$ADMIT_RULE" = on ]; then
    admit_note="$(printf '%s\n' "$admit_allow" | grep -c .) grandfathered (capacity-admit gate)"
  else
    admit_note="capacity-admit rule OFF (CC_HERM_ADMIT_RULE)"
  fi
  echo "test-hermeticity-lint: clean — $seen suite(s); $(printf '%s\n' "$allow" | grep -c .) grandfathered (\$HOME), $fire_note, $orphan_note, $seam_note, $env_note, $admit_note, 0 new leaks."
  return 0
}

# lint_selftests <repo-root> <allowlist-text> [own-set-text] — 0 clean · 1 violations · 2 unusable
#
# RULE 4's pass, and a SEPARATE pass rather than a fourth rule inside lint_dir() on purpose: its
# population is not the one lint_dir walks. lint_dir globs `*.bats` under ONE directory; rule 4
# walks the repo's TOOL directories. Folding it in would have forced every existing caller — and
# every fixture assertion in --selftest that lints a temp dir — to start caring about the real
# bin/, which is precisely how an assertion stops measuring what it claims to.
lint_selftests() {
  local root="$1" allow="$2" own="${3:-}" own_scoped=0 f base seen=0 collide=0 stuck=0 other=0 why
  local anchor anchor_seen=0
  [ "$#" -ge 3 ] && own_scoped=1
  CHECK_FAILED=0
  [ -d "$root" ] || { echo "test-hermeticity-lint: ⛔ not a directory: $root" >&2; return 2; }
  # The extractor's POSITIVE CONTROL: this script's own copy under the scanned root. It ships an
  # embedded selftest by construction, so if it is there the extractor must see it.
  anchor="$root/scripts/$(basename "$SELF")"
  for f in "$root"/bin/* "$root"/scripts/*.sh "$root"/hooks/*.sh; do
    [ -f "$f" ] || continue
    has_selftest "$f" || continue
    [ "$f" = "$anchor" ] && anchor_seen=1
    seen=$((seen + 1)); base="$(basename "$f")"
    why=""
    if   selftest_names_const_path "$f"; then why="names a CONSTANT /tmp path"
    elif selftest_state_unconfined "$f"; then why="creates scratch state without mktemp"
    fi
    if [ -z "$why" ]; then
      if in_allowlist "$base" "$allow"; then
        if in_own "$f" "$own" "$own_scoped"; then
          printf '  RATCHET-SELF %s confines its selftest now — delete its SELFTEST allowlist line\n' "$base"
          stuck=$((stuck + 1))
        else
          printf '  ratchet-self? %s confines its selftest but is still grandfathered (NOT in your diff — advisory)\n' "$base"
          other=$((other + 1))
        fi
      fi
    elif ! in_allowlist "$base" "$allow"; then
      if in_own "$f" "$own" "$own_scoped"; then
        printf '  COLLIDES %s: its embedded selftest %s — two concurrent runs share it\n' "$base" "$why"
        collide=$((collide + 1))
      else
        printf '  collides? %s: its embedded selftest %s (NOT in your diff — advisory, not blocking)\n' "$base" "$why"
        other=$((other + 1))
      fi
    fi
  done
  # THE EXTRACTOR CONTROL, and deliberately NOT a count. `seen` comes from a TEXTUAL extractor:
  # rename the convention and it matches nothing, and a rule that inspected zero tools would still
  # print "clean" — an alarm carrying the same zero bits as one that cannot fire. A floor cannot
  # express that, because a floor is calibration: `seen < 20`, sized against the 45 measured here,
  # made a NON-VERDICT of every smaller tree — the fixture repos ship-land lands included, against
  # this repo's rule that a tree is judged by the ratchet it SHIPS and never becomes unlandable for
  # being small. So the guard asks the one question that needs no calibration: when this script is
  # itself inside the scanned root, did the extractor find IT? If not, the extractor is broken.
  # If the anchor simply is not there, `seen` may honestly be 0 and the tree is clean.
  if [ -f "$anchor" ] && [ "$anchor_seen" -eq 0 ]; then
    echo "test-hermeticity-lint: ⛔ the region extractor did not detect its own selftest in $anchor" >&2
    echo "  That file ships one by construction, so this is the EXTRACTOR failing, not a clean tree." >&2
    echo "  Every rule-4 verdict in this run is therefore void; do not read it as a clean bill." >&2
    return 2
  fi
  [ "$other" -eq 0 ] || echo "test-hermeticity-lint: $other pre-existing selftest violation(s) NOT in your diff — reported, not blocking (own-scope)."
  # Same ordering as lint_dir: the own-scope report first, so a killed predicate cannot masquerade
  # as a clean own-scope pass.
  if [ "$CHECK_FAILED" -ne 0 ]; then
    echo "test-hermeticity-lint: ⛔ UNUSABLE — a rule-4 predicate failed to run (see above); no verdict." >&2
    echo "  This is NOT a collision report. Re-run when the box is quieter; do not 'fix' any tool on it." >&2
    return 2
  fi

  if [ "$collide" -gt 0 ]; then
    echo "test-hermeticity-lint: ⛔ $collide embedded selftest(s) above name a scratch path that is the SAME STRING every run."
    echo "  WHY: the gate, the nightly and a sibling session all run these concurrently, so two copies"
    echo "       of one selftest meet on that path and the loser goes RED for a reason that is not its"
    echo "       subject — 2 of 4 concurrent runs, measured (backlog f7abcbdee98c spillover)."
    echo "  Fix: \`d=\"\$(mktemp -d \"\\\${TMPDIR:-/tmp}/<tool>-selftest.XXXXXX\")\"; trap 'rm -rf \"\$d\"' EXIT\`"
    echo "       and hang every fixture off \$d. Do NOT add to the selftest allowlist."
  fi
  if [ "$stuck" -gt 0 ]; then
    echo "test-hermeticity-lint: ⛔ $stuck tool(s) above confine their selftest but are still grandfathered."
    echo "  Fix: delete their lines from EMBEDDED_SELFTEST_ALLOWLIST in $0 — the ratchet only shrinks."
  fi
  [ $((collide + stuck)) -eq 0 ] || return 1
  echo "test-hermeticity-lint: clean — $seen embedded selftest(s); $(printf '%s\n' "$allow" | grep -c .) grandfathered (scratch path), 0 collisions."
  return 0
}

# ── THE --selftest's THIRD STATE, as two PURE functions.
#
# lint_dir exits 2 for FIVE reasons and they are not one class. FOUR are STRUCTURAL — not a
# directory, no .bats suites under it, and the two extractors that cannot find their own anchor —
# and each says something true about the tree or about the instrument, so each must stay a FAIL.
# The FIFTH is CHECK_FAILED: a predicate could not RUN (a lost fork on a loaded box), which says
# nothing whatever about the tree. Collapsing the fifth into the other four is what made a busy
# box file a HOST RED against a clean tree — case (e) is the only assertion in this selftest that
# judges the REAL tree, so it is the one a machine hiccup can break.
#
# CHECK_FAILED is readable by the caller ONLY because case (e) invokes lint_dir with a plain
# REDIRECT. A redirect is not a subshell; `$( )` would be, and would discard the assignment before
# anyone could read it — the exact defect this row's sibling was (backlog 57ff249657e0, where
# `hits="$(scan)"` swallowed four honest `exit 2`s). The selftest case below pins that property
# directly, so a future refactor to `$( )` reds here instead of silently re-conflating the states.
#
# Both are PURE and both are driven by the production arms AND by the cases that prove them, so a
# test cannot drift from the arm it certifies (memory: make-the-actuator-the-arbiter).
selftest_realtree_disposition() { # <lint_dir rc> <CHECK_FAILED read after it> → 0 clean · 1 FAIL · 2 NON-VERDICT
  case "$1" in
    0) return 0 ;;
    2) if [ "$2" -ne 0 ]; then return 2; else return 1; fi ;;
    *) return 1 ;;
  esac
}
# A real FAIL outranks a NON-VERDICT. A discriminating case that actually failed is positive
# evidence that the instrument is broken; a non-verdict is only the ABSENCE of evidence about the
# box, and absence must never suppress a finding that is present.
selftest_exit_code() { # <fails> <nonverdict> → 0 green · 1 FAIL · 2 NON-VERDICT
  if [ "$1" -ne 0 ]; then return 1; fi
  if [ "$2" -ne 0 ]; then return 2; fi
  return 0
}

# ── --selftest: PROVE both RED paths fire and both GREEN paths don't (harness law: every assertion
# traps). Case (e) lints the REAL tree with the REAL allowlist, so a stale ratchet is caught here too.
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  mkdir -p "$d/leak" "$d/herm"
  cat >"$d/leak/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}
@test "x" { true; }
F
  # THE PATH-FORM own-scope fixture, and it has to live under a directory actually NAMED `tests`.
  # Case (j) used to lint $d/leak with the own-set `tests/zz-fixture.bats` and pass — because the
  # matcher basenamed both sides, so the directory in the entry was decoration. That is the whole
  # defect (backlog c1a29f8ee045): a control that cannot tell `tests/x` from `scripts/x` cannot
  # catch a matcher that cannot either. With the real directory in place, (j) proves the path form
  # matches and (j2) proves a DIFFERENT directory does not.
  mkdir -p "$d/pathown/tests"
  cp "$d/leak/zz-fixture.bats" "$d/pathown/tests/zz-fixture.bats"
  cat >"$d/herm/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
}
@test "x" { true; }
F
  # ── RULE 2 fixtures. All four are $HOME-hermetic on purpose, so a rule-2 verdict can never be
  # rule 1 leaking through: the ONLY axis that varies is the handoff-fire reference and the pin.
  # nofire is byte-identical to fireleak MINUS the reference — the scope control for case (r).
  mkdir -p "$d/nofire" "$d/fireleak" "$d/firepin" "$d/firepertest"
  cat >"$d/nofire/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  SUBJECT="$REPO/scripts/some-other-tool.sh"
}
@test "x" { run bash "$SUBJECT" --dry-run; }
F
  cat >"$d/fireleak/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  SUBJECT="$REPO/scripts/handoff-fire.sh"
}
@test "x" { run bash "$SUBJECT" --dry-run; }
F
  cat >"$d/firepin/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off
  SUBJECT="$REPO/scripts/handoff-fire.sh"
}
@test "x" { run bash "$SUBJECT" --dry-run; }
F
  # Rule 2's copy of rule 3's prose-match regression control — the hole was found there, and this
  # pins that the retrofit here actually took.
  mkdir -p "$d/firecomment"
  cat >"$d/firecomment/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # NOTE: the capacity gate is pinned with CC_FIRE_CAPACITY_GATE=off — but this suite never does it.
  SUBJECT="$REPO/scripts/handoff-fire.sh"
}
@test "x" { run bash "$SUBJECT" --dry-run; }
F
  # SCOPE-side prose control, the twin of firecomment's PIN-side one. This suite drives some other
  # tool and only MENTIONS handoff-fire in a comment, so rule 2's premise — "its fires read live
  # machine load" — is false for it and it must be OUT of scope. Byte-identical to nofire except
  # for that comment, which is the only axis under test.
  mkdir -p "$d/firementiononly"
  cat >"$d/firementiononly/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  SUBJECT="$REPO/scripts/some-other-tool.sh"
}
# NOTE: the regression this pins was first seen in tests/handoff-fire-capacity-gate.bats.
@test "x" { run bash "$SUBJECT" --dry-run; }
F
  # The same control for rule 3's scope predicate — no verdict rides on it today, but the twins are
  # asserted together so a future hardening cannot land on one side only again.
  mkdir -p "$d/closementiononly"
  cat >"$d/closementiononly/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  SUBJECT="$REPO/scripts/some-other-tool.sh"
}
# NOTE: unlike the watchdog, this suite never passes --close-panes.
@test "x" { run bash "$SUBJECT" --dry-run; }
F
  # ── RULE 7 fixtures. Rule 2's set with the other gate's names, and every one is $HOME-hermetic AND
  # names no handoff-fire, so a rule-7 verdict can be neither rule 1 nor rule 2 leaking through: the
  # only axis that varies is the capacity-admit reference and its closure. `noadmit` is byte-
  # identical to `admitleak` MINUS the reference — the scope control, without which every assertion
  # below would be consistent with a rule that reds on everything.
  mkdir -p "$d/noadmit" "$d/admitleak" "$d/admitpin" "$d/admitform2" "$d/admitform2short" \
           "$d/admitpertest" "$d/admitcomment" "$d/admitproseonly"
  cat >"$d/noadmit/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  SUBJECT="$REPO/scripts/some-other-tool.sh"
}
@test "x" { run bash "$SUBJECT" --dry-run; }
F
  cat >"$d/admitleak/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  SUBJECT="$REPO/scripts/boot-resume-launch.sh"
}
@test "x" { run bash "$SUBJECT" --dry-run; }
F
  cat >"$d/admitpin/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ADMIT_GATE=off
  SUBJECT="$REPO/scripts/boot-resume-launch.sh"
}
@test "x" { run bash "$SUBJECT" --dry-run; }
F
  # FORM 2, complete: both instrument overrides AND a reserve closure. The suite whose SUBJECT is the
  # gate cannot use form 1 without deleting what it tests, so this path has to exist and has to pass.
  cat >"$d/admitform2/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ADMIT_LOADAVG_OVERRIDE=1.0
  export CC_ADMIT_HEADROOM_OVERRIDE=64
  export CC_ADMIT_RESERVE_TERM=off
  LIB="$REPO/scripts/lib/capacity-admit.sh"
}
@test "x" { run bash -c '. "$1"; cc_capacity_admit x y' _ "$LIB"; }
F
  # 🚨 THE CONTROL THAT PINS THIS RULE'S ONE CORRECTION, and the only assertion here whose absence
  # would silently return rule 7 to the filing's remedy. This fixture is admitform2 MINUS the reserve
  # closure — i.e. EXACTLY what backlog 5ef0dcb22aec prescribed, and exactly what
  # tests/capacity-admit.bats does today. It must go RED. Measured, not argued: that real suite is
  # 20/20 ambient and 17/20 under CC_SP_TREES_OVERRIDE=999, so a rule certifying this shape as pinned
  # would mint a false negative on the one suite whose subject IS this gate. If a later hand
  # "simplifies" form 2 back to two clauses to match the sibling rule, this is what stops it.
  cat >"$d/admitform2short/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ADMIT_LOADAVG_OVERRIDE=1.0
  export CC_ADMIT_HEADROOM_OVERRIDE=64
  LIB="$REPO/scripts/lib/capacity-admit.sh"
}
@test "x" { run bash -c '. "$1"; cc_capacity_admit x y' _ "$LIB"; }
F
  cat >"$d/admitpertest/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  SUBJECT="$REPO/scripts/boot-resume-launch.sh"
}
@test "a" { CC_ADMIT_GATE=off run bash "$SUBJECT" --dry-run; }
@test "b" { run bash "$SUBJECT" --dry-run; }
F
  # Rule 2's PIN-side prose control, cloned: a setup() that merely DOCUMENTS the pin is not pinned.
  cat >"$d/admitcomment/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # NOTE: the admit gate is closed with CC_ADMIT_GATE=off — but this suite never does it.
  SUBJECT="$REPO/scripts/boot-resume-launch.sh"
}
@test "x" { run bash "$SUBJECT" --dry-run; }
F
  # SCOPE-side control for the shared strip_prose, now that it is parameterised. This suite drives
  # some other tool and handles the caller's name only inside a SENTENCE it carries as data — the
  # tests/cc-eligible-history.bats shape that convicted a suite for a fixture title. It must be OUT
  # of scope, and it is the only fixture here that exercises the generalisation itself.
  cat >"$d/admitproseonly/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  SUBJECT="$REPO/scripts/some-other-tool.sh"
  ROW_TITLE="patch boot-resume-launch so the resume inherits the goal"
}
@test "x" { run bash "$SUBJECT" --dry-run "$ROW_TITLE"; }
F
  cat >"$d/firepertest/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  SUBJECT="$REPO/scripts/handoff-fire.sh"
}
@test "a" { CC_FIRE_CAPACITY_GATE=off run bash "$SUBJECT" --dry-run; }
@test "b" { run bash "$SUBJECT" --dry-run; }
F
  # ── RULE 3 fixtures. All three are $HOME-hermetic AND fire-free on purpose, so a rule-3 verdict
  # can never be rules 1-2 leaking through: the ONLY axis that varies is the `--close-panes` call and
  # the setup() position on the lever. noclose is byte-identical to orphleak MINUS the close leg —
  # the scope control, without which "orphleak went red" proves nothing about SCOPING.
  mkdir -p "$d/noclose" "$d/orphleak" "$d/orphpin" "$d/orphpertest"
  cat >"$d/noclose/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  WD="$REPO/hooks/lead-crash-watchdog.sh"
}
@test "x" { run bash "$WD" --harvest-team "$TEAM" sid-1; }
F
  cat >"$d/orphleak/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  WD="$REPO/hooks/lead-crash-watchdog.sh"
}
@test "x" { run bash "$WD" --close-panes "$TEAM" sid-1; }
F
  cat >"$d/orphpin/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset LCW_ORPHAN_CLOSE
  WD="$REPO/hooks/lead-crash-watchdog.sh"
}
@test "x" { run bash "$WD" --close-panes "$TEAM" sid-1; }
F
  # The REGRESSION control. A hand-made fixture passed either way while the predicate was a bare
  # substring match, and the bug only surfaced against the real suite — which documents the lever in
  # its own setup() comment. This fixture replays that shape: the MENTION is present, the STATEMENT
  # is not, and it must be RED. Without it, is_orphan_pinned could silently revert to matching prose.
  mkdir -p "$d/orphcomment"
  cat >"$d/orphcomment/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # ~/.claude/autonomy/watchdog.env carries `export LCW_ORPHAN_CLOSE=1`, which arms the close leg.
  WD="$REPO/hooks/lead-crash-watchdog.sh"
}
@test "x" { run bash "$WD" --close-panes "$TEAM" sid-1; }
F
  cat >"$d/orphpertest/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  WD="$REPO/hooks/lead-crash-watchdog.sh"
}
@test "a" { LCW_ORPHAN_CLOSE=1 run bash "$WD" --close-panes "$TEAM" sid-1; }
@test "b" { run bash "$WD" --close-panes "$TEAM" sid-1; }
F
  # ── RULE 4 fixtures: TOOL trees, not suite dirs, because rule 4's population is bin/scripts/hooks.
  #
  # THE SELF-REFERENCE TRAP, and why three fixture lines are spliced in with printf. This block is
  # INSIDE the `if [ "${1:-}" = "--selftest" ]` region, which is exactly what selftest_region()
  # extracts from THIS file — so a heredoc line reading `tmp=<constant>` would be read as this
  # script's OWN violation and the real tree would go RED on its own fixture, with rule 4 accusing
  # the file that defines it. Splicing those lines through constant_line() keeps the assignment and
  # the path from ever being adjacent here, while the fixture on disk is byte-for-byte the shape
  # under test. Every other line comes from a quoted heredoc, which cannot expand and cannot lie.
  mkdir -p "$d/s_collide/bin" "$d/s_ok/bin" "$d/s_nostate/bin" "$d/s_nomktemp/bin" \
           "$d/s_prose/bin" "$d/s_scope/bin" "$d/s_bypass/bin"
  # constant_line <printf-fmt> — emits ONE fixture line carrying a literal /tmp path. The format
  # string never places the path next to the assignment or redirect, so this file never contains the
  # shape it is asserting about; the fixture on disk does. Quoted heredocs supply every other line
  # (and, unlike the equivalent `echo '…$x…'`, do not trip SC2016, which this repo does not waive).
  # shellcheck disable=SC2059  # the format string IS the payload here — the caller supplies a
  # literal, and the whole point is that this file never spells the path inside it.
  constant_line() { printf "$1" /tmp; }
  { cat <<'F'
#!/bin/bash
selftest() {
F
    constant_line '  tmp=%s/zz-tool-selftest\n'
    cat <<'F'
  mkdir -p "$tmp"; echo ok > "$tmp/f"
}
F
  } >"$d/s_collide/bin/zz-tool"
  # The GREEN twin: same shape, same writes, differing only in where the scratch dir comes from.
  cat >"$d/s_ok/bin/zz-tool" <<'F'
#!/bin/bash
selftest() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/zz-tool-selftest.XXXXXX")"
  mkdir -p "$tmp"; echo ok > "$tmp/f"
}
F
  # mktemp PRESENT but BYPASSED — the fixture that isolates the const-path half. It exists because
  # mutation proved (a4) could not: s_collide also creates state without mktemp, so stubbing the
  # const-path probe out left it RED via the OTHER half and the whole probe read as load-bearing
  # when it was not. Here the mktemp half is satisfied by construction, so only the const-path probe
  # can produce the verdict.
  { cat <<'F'
#!/bin/bash
selftest() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/zz-bypass.XXXXXX")"
F
    constant_line '  echo ok > %s/zz-tool-selftest.log\n'
    echo '}'
  } >"$d/s_bypass/bin/zz-tool"
  # Creates NOTHING: it cannot collide with a concurrent copy of itself, so rule 4 must not reach
  # it. Without this control the "creates" probe could be inert and every RED below would still pass.
  cat >"$d/s_nostate/bin/zz-tool" <<'F'
#!/bin/bash
selftest() {
  [ "$(echo hi)" = hi ] || return 1
}
F
  # Creates state at a constant path that is NOT under /tmp — the half the const-path probe alone
  # would miss, and the reason rule 4 asks for mktemp rather than only banning one prefix.
  cat >"$d/s_nomktemp/bin/zz-tool" <<'F'
#!/bin/bash
selftest() {
  scratch="$HOME/.cache/zz-tool-selftest"
  mkdir -p "$scratch"; echo ok > "$scratch/f"
}
F
  # The PROSE-MATCH regression control. Rules 2 and 3 were each shipped VACUOUS by a predicate that
  # matched a setup() comment naming the lever; this is the same shape one rule later — the word
  # mktemp is present, the CALL is not, and it must be RED.
  cat >"$d/s_prose/bin/zz-tool" <<'F'
#!/bin/bash
selftest() {
  # scratch is obtained with mktemp -d, per the ratchet
  scratch="$HOME/.cache/zz-tool-selftest"
  mkdir -p "$scratch"; echo ok > "$scratch/f"
}
F
  # SCOPE CONTROL: zz-plain names a constant path in a state-bearing position but ships NO selftest,
  # so it is out of rule 4 entirely. Paired with a compliant tool so the denominator floor is met —
  # a dir of one out-of-scope file would exit 2 and prove nothing about scoping.
  cat >"$d/s_scope/bin/zz-ok" <<'F'
#!/bin/bash
selftest() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/zz-ok.XXXXXX")"
  echo ok > "$tmp/f"
}
F
  { cat <<'F'
#!/bin/bash
main() {
F
    constant_line '  tmp=%s/zz-plain-state\n'
    cat <<'F'
  mkdir -p "$tmp"
}
F
  } >"$d/s_scope/bin/zz-plain"
  # THE EXTRACTOR CONTROL's pair. s_anchor carries a file at the anchor path that ships NO selftest
  # — which is what a broken extractor looks like from the inside: the anchor is present and
  # undetected. s_anchor_ok carries a REAL copy of this script, so the two differ only in whether
  # the extractor can see the anchor, and the second also proves the IFBLOCK shape is detectable at
  # all (every other rule-4 fixture uses the function shape).
  mkdir -p "$d/s_anchor/scripts" "$d/s_anchor/bin" "$d/s_anchor_ok/scripts" "$d/s_anchor_ok/bin"
  cat >"$d/s_anchor/scripts/$(basename "$SELF")" <<'F'
#!/bin/bash
echo "a lint that ships no embedded selftest at all"
F
  cp "$SELF" "$d/s_anchor_ok/scripts/$(basename "$SELF")"
  for _r in s_anchor s_anchor_ok; do
    cat >"$d/$_r/bin/zz-tool" <<'F'
#!/bin/bash
selftest() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/zz-anchor.XXXXXX")"
  echo ok > "$tmp/f"
}
F
  done
  # ── RULE 5 fixtures: a fixture SEAM ROOT (tools) plus suite dirs that name into it. Two
  # populations again, so both are fixtured — a rule-5 assertion must never be answerable by the
  # real checkout, which is what would happen if the seam table were left pointing at $ROOT.
  #
  # THE SELF-REFERENCE TRAP, rule 4's verbatim and one rule later: this block is inside the region
  # whose lines the SEAM extractor reads, so a heredoc line spelling `NAME="${SEAM:-/tmp/…}"` would
  # be harvested as a REAL seam of THIS script — permanently, and it would then oblige every suite
  # naming this script to pin a variable that exists only as a fixture. seam_line() keeps the holder
  # and the default from ever being adjacent here; the fixture on disk is the exact shape under test.
  # shellcheck disable=SC2059  # the format string IS the payload — see constant_line() above
  seam_line() { printf "$1" "$2" "$3" "$4"; }
  mkdir -p "$d/r5root/bin" "$d/r5root/scripts" "$d/r5root/hooks" \
           "$d/r5leak" "$d/r5execleak" "$d/r5pin" "$d/r5scope" "$d/r5pertest" \
           "$d/r5comment" "$d/r5prefix" "$d/r5holder"
  # Every non-seam line comes from a QUOTED heredoc, exactly as rule 4's fixtures do: it cannot
  # expand, it cannot lie, and — unlike the equivalent `echo '…$x…'` — it does not trip SC2016,
  # which this repo does not waive and ship-land's gate enforces at `info`.
  # shape 5a: an ABSOLUTE /tmp default nothing about $HOME can redirect.
  { cat <<'F'
#!/bin/bash
F
    # shellcheck disable=SC2016  # the format string IS the payload — see seam_line() above
    seam_line '%s="${%s:-%s/zz-seam-state}"\n' DIR ZZ_SEAM_DIR /tmp
    cat <<'F'
echo "$DIR"
F
  } >"$d/r5root/bin/zz-seamtool"
  # shape 5b: a BARE NAME the fixture root SHIPS (bin/zz-seamtool, above), with the HOLDER in
  # command position. Both halves are required, and the holder half is what the r5holder control
  # below isolates.
  { cat <<'F'
#!/bin/bash
F
    # shellcheck disable=SC2016  # the format string IS the payload — see seam_line() above
    seam_line '%s="${%s:-%s}"\n' BIN ZZ_SEAM_BIN zz-seamtool
    cat <<'F'
"$BIN" --probe
F
  } >"$d/r5root/bin/zz-exectool"
  # THE HOLDER CONTROL: same bare name, same shipped tool — but the holder is only ever PRINTED, so
  # nothing is executed and rule 5 must not reach it. Without this, the holder test could be inert
  # and every 5b RED above would still pass (`STRICT_TOOLS`/`PAGE_KEY` in the real tree, measured).
  { cat <<'F'
#!/bin/bash
F
    # shellcheck disable=SC2016  # the format string IS the payload — see seam_line() above
    seam_line '%s="${%s:-%s}"\n' LABEL ZZ_SEAM_LABEL zz-seamtool
    cat <<'F'
printf '%s\n' "$LABEL"
F
  } >"$d/r5root/bin/zz-labeltool"
  # THE SCOPE CONTROL: a tool with NO seam at all. A suite naming only this must stay GREEN, without
  # which "r5leak went red" proves nothing about scoping.
  cat >"$d/r5root/bin/zz-noseam" <<'F'
#!/bin/bash
echo no-seam
F
  # Every rule-5 suite fixture is $HOME-hermetic, fire-free and close-leg-free on purpose, so a
  # rule-5 verdict can never be rules 1-3 leaking through: the only axis that varies is which tool
  # the suite names and where the seam is assigned.
  cat >"$d/r5leak/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  T="$REPO/bin/zz-seamtool"
}
@test "x" { run bash "$T"; }
F
  cat >"$d/r5execleak/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  T="$REPO/bin/zz-exectool"
}
@test "x" { run bash "$T"; }
F
  cat >"$d/r5pin/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export ZZ_SEAM_DIR="$BATS_TEST_TMPDIR/seam"
  T="$REPO/bin/zz-seamtool"
}
@test "x" { run bash "$T"; }
F
  cat >"$d/r5scope/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  T="$REPO/bin/zz-noseam"
}
@test "x" { run bash "$T"; }
F
  # Per-test assignment does NOT count — rule 1's reason verbatim: it leaves every OTHER test in the
  # file pointed at live state.
  cat >"$d/r5pertest/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  T="$REPO/bin/zz-seamtool"
}
@test "a" { ZZ_SEAM_DIR="$BATS_TEST_TMPDIR/seam" run bash "$T"; }
@test "b" { run bash "$T"; }
F
  # THE COMMENT-STRIP CONTROL. Rule 5 strips comments before the SCOPE test — a suite that only
  # NAMES a tool in prose executes nothing — so this must be GREEN. It is the mirror of rule 2's and
  # rule 4's prose-match regressions: there a comment must not satisfy a POSITION test, here a
  # comment must not trigger a SCOPE test.
  cat >"$d/r5comment/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # unrelated: the roster this suite asserts on is also read by $REPO/bin/zz-seamtool
  T="$REPO/bin/zz-noseam"
}
@test "x" { run bash "$T"; }
F
  cat >"$d/r5holder/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  T="$REPO/bin/zz-labeltool"
}
@test "x" { run bash "$T"; }
F
  # THE NAME-BOUNDARY CONTROL: `zz-seamtool-extra` must not be matched by `zz-seamtool`'s seams.
  # Without the trailing class-exclusion in the scope pattern, every tool whose name PREFIXES
  # another would drag the other's suites into scope.
  cat >"$d/r5prefix/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  T="$REPO/bin/zz-seamtool-extra"
}
@test "x" { run bash "$T"; }
F
  # RULE 5's ANCHOR fixtures, rule 4's pair verbatim: r5anchor carries a file at this script's own
  # path that does NOT declare the anchor seam — which is what a broken extractor looks like from
  # the inside (the anchor is present and undetected) — and r5anchor_ok carries a REAL copy, so the
  # two differ only in whether the extractor can see it.
  mkdir -p "$d/r5anchor/bin" "$d/r5anchor/scripts" "$d/r5anchor_ok/bin" "$d/r5anchor_ok/scripts"
  cat >"$d/r5anchor/scripts/$(basename "$SELF")" <<'F'
#!/bin/bash
echo "a lint that declares no seam anchor at all"
F
  cp "$SELF" "$d/r5anchor_ok/scripts/$(basename "$SELF")"
  # ── RULE 6 fixtures: a fixture TOOL ROOT plus suite dirs naming into it, rule 5's two populations
  # verbatim — a rule-6 assertion must never be answerable by the real checkout.
  #
  # THE SELF-REFERENCE TRAP, one rule later and now on BOTH halves: this block sits inside the region
  # build_env_table() reads, so a heredoc line spelling an injection argument would add a phantom
  # variable to the REAL propagated set, and one spelling a read would make THIS script a reader of
  # it — permanently obliging every suite that names this script to pin a fixture variable.
  # env_line() keeps the variable NAME from ever being adjacent to either shape here (`%s` is not a
  # valid identifier start, so neither extractor pattern matches), while the fixture on disk is the
  # exact shape under test. The ANCHOR above is spelled for real, deliberately — that is its job.
  # shellcheck disable=SC2059  # the format string IS the payload — see constant_line()/seam_line()
  env_line() { printf "$@"; }
  mkdir -p "$d/r6root/bin" "$d/r6root/scripts" "$d/r6root/hooks" \
           "$d/r6leak" "$d/r6unset" "$d/r6assign" "$d/r6inject" "$d/r6unprop" "$d/r6scope" \
           "$d/r6pertest" "$d/r6comment" "$d/r6prefix" "$d/r6semi"
  # THE INJECTOR: puts two variables onto a launched pane and READS NEITHER. This is
  # scripts/handoff-fire.sh's exact shape, and a suite naming it must stay GREEN — see (d6).
  { cat <<'F'
#!/bin/bash
F
    # shellcheck disable=SC2016  # the format string IS the payload — see env_line() above
    env_line 'exec term --env "%s=1" --env "%s=/x" -- "$SHELL"\n' ZZ_ENV_MODE ZZ_ENV_MODE_DIR
  } >"$d/r6root/bin/zz-launcher"
  # THE READER: reads both injected variables. ZZ_ENV_MODE is a strict PREFIX of ZZ_ENV_MODE_DIR,
  # which is what the (i6) boundary control needs — the real tree has the same collision.
  { cat <<'F'
#!/bin/bash
F
    # shellcheck disable=SC2016  # the format string IS the payload — see env_line() above
    env_line 'MODE="${%s:-0}"\n' ZZ_ENV_MODE
    # shellcheck disable=SC2016  # ditto
    env_line 'DIR="${%s:-/tmp/zz-env}"\n' ZZ_ENV_MODE_DIR
    cat <<'F'
echo "$MODE $DIR"
F
  } >"$d/r6root/bin/zz-panetool"
  # THE NON-PROPAGATED CONTROL: reads a `${NAME:-plain}` seam that NOTHING injects. This is the
  # filing's naive rule — "every CC_* var a tool reads" — and it is what would have put most of 324
  # suites in scope. A suite naming this must be GREEN.
  { cat <<'F'
#!/bin/bash
F
    # shellcheck disable=SC2016  # ditto — the format string IS the payload
    env_line 'LVL="${%s:-0}"\n' ZZ_ENV_UNPROP
    cat <<'F'
echo "$LVL"
F
  } >"$d/r6root/bin/zz-plainseam"
  cat >"$d/r6root/bin/zz-noseam" <<'F'
#!/bin/bash
echo no-seam
F
  # Every rule-6 suite fixture is $HOME-hermetic, fire-free and close-leg-free on purpose, so a
  # rule-6 verdict can never be rules 1-3 leaking through.
  # Quoted heredocs for every fixed line and an escaped-`\$` printf for the varying one — the same
  # discipline rules 4-5's fixture writers use, and not only style: `echo '…$x…'` trips SC2016,
  # which this repo does not waive and ship-land's gate enforces at `info`.
  mk6() {  # mk6 <dir> <extra-setup-line> <tool>
    { cat <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
F
      [ -n "$2" ] && printf '  %s\n' "$2"
      printf "  T=\"\$REPO/bin/%s\"\n" "$3"
      cat <<'F'
}
@test "a" { run bash "$T"; }
@test "b" { run bash "$T"; }
F
    } > "$d/$1/zz-fixture.bats"
  }
  mk6 r6leak   ''                                              zz-panetool
  mk6 r6unset  'unset ZZ_ENV_MODE ZZ_ENV_MODE_DIR'             zz-panetool
  # shellcheck disable=SC2016  # the literal must reach the FIXTURE FILE, not expand here
  mk6 r6assign 'export ZZ_ENV_MODE=0 ZZ_ENV_MODE_DIR="$BATS_TEST_TMPDIR/d"' zz-panetool
  mk6 r6inject ''                                              zz-launcher
  mk6 r6unprop ''                                              zz-plainseam
  mk6 r6scope  ''                                              zz-noseam
  # THE BOUNDARY CONTROL: pins ONLY the longer name. ZZ_ENV_MODE must still be reported — without a
  # boundary after the name, `ZZ_ENV_MODE_DIR=` would read as having pinned `ZZ_ENV_MODE` too.
  # shellcheck disable=SC2016  # ditto — the literal must reach the FIXTURE FILE
  mk6 r6prefix 'export ZZ_ENV_MODE_DIR="$BATS_TEST_TMPDIR/d"'  zz-panetool
  # A STATEMENT-TERMINATED unset — the shape rule 3's narrower trailing class misses for the LAST
  # name in the list, found by mutation rather than review. Must be GREEN: the position was taken.
  mk6 r6semi   'unset ZZ_ENV_MODE ZZ_ENV_MODE_DIR;'            zz-panetool
  # Per-test position does NOT count — rule 1's reason verbatim.
  cat >"$d/r6pertest/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  T="$REPO/bin/zz-panetool"
}
@test "a" { unset ZZ_ENV_MODE ZZ_ENV_MODE_DIR; run bash "$T"; }
@test "b" { run bash "$T"; }
F
  # THE COMMENT-STRIP CONTROL: a tool named only in PROSE executes nothing.
  cat >"$d/r6comment/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # unrelated: the pane this suite asserts on is also launched by $REPO/bin/zz-panetool
  T="$REPO/bin/zz-noseam"
}
@test "x" { run bash "$T"; }
F
  # RULE 6's ANCHOR fixtures, rules 4-5's pair verbatim.
  mkdir -p "$d/r6anchor/bin" "$d/r6anchor/scripts" "$d/r6anchor_ok/bin" "$d/r6anchor_ok/scripts"
  cat >"$d/r6anchor/scripts/$(basename "$SELF")" <<'F'
#!/bin/bash
echo "a lint that declares no inherited-value anchor at all"
F
  cp "$SELF" "$d/r6anchor_ok/scripts/$(basename "$SELF")"
  fails=0
  # Counted SEPARATELY from `fails` on purpose: a case that could not RUN is not a case that
  # failed, and folding the two loses the only distinction the exit code exists to carry.
  nonverdict=0
  # Pin BOTH rule-2 knobs for the duration of the selftest: an ambient CC_HERM_FIRE_RULE=off or a
  # stray CC_HERM_FIRE_ALLOWLIST in the caller's environment would otherwise make every rule-2
  # assertion below pass VACUOUSLY, which is the one way a discrimination proof can lie.
  FIRE_RULE=on
  FIRE_ALLOW=""
  # Rule 3's knobs, pinned for that same reason. The rule-1/rule-2 fixtures are out of rule 3's
  # scope, so this cannot perturb their verdicts — but an ambient CC_HERM_ORPHAN_RULE=off would make
  # every rule-3 assertion below pass vacuously, which is exactly what pinning forecloses.
  ORPHAN_RULE=on
  ORPHAN_ALLOW=""
  # Rule 4's knobs, pinned for that same reason.
  SELFTEST_RULE=on
  SELFTEST_ALLOW=""
  # NOTE the matching `CC_HERM_SEAM_RULE=off` on every rules-1-4 ENTRYPOINT assertion below. Pinning
  # the in-process global is not enough: those cases re-exec "$SELF" as a child, which re-reads the
  # env and defaults rule 5 back ON against the REAL $ROOT. Measured while writing this — three
  # rule-1/2 assertions went RED because their fixtures name handoff-fire.sh, whose three non-$HOME
  # seams they of course do not pin. A rule-5 verdict was answering a rule-2 question, through the
  # one door the in-process pin does not cover.
  #
  # Rule 5's knobs are pinned the OTHER way — OFF — and that asymmetry is load-bearing. Rules 1-4's
  # fixtures name real tools (handoff-fire.sh, lead-crash-watchdog.sh), and handoff-fire.sh carries
  # three non-$HOME seams, so an ON rule 5 would convict those fixtures and every rule-1/2/3 GREEN
  # assertion below would go RED for a reason that is not its subject — this file's own §RULE 4
  # warning about a rule-4 verdict answering a rule-1 question, one rule later. Each rule-5
  # assertion turns it on IN A SUBSHELL, against the FIXTURE seam root, so nothing leaks either way.
  SEAM_RULE=off
  SEAM_ALLOW=""
  # Rule 6's knobs, pinned OFF for rule 5's reason verbatim and with the same NOTE about the
  # entrypoint: the rules-1-5 fixtures name real tools, and a rule-6 verdict about the real $ROOT
  # must never become the answer to a rule-1/2/3/4/5 assertion about a two-file fixture. Every
  # entrypoint assertion below therefore also carries CC_HERM_ENV_RULE=off, because a child re-reads
  # the environment and would default the rule back ON. Rule 6's own assertions turn it on IN A
  # SUBSHELL, against the FIXTURE tool root, so nothing leaks either way.
  ENV_RULE=off
  ENV_ALLOW=""
  # Rule 7's knobs, pinned ON+empty like its twin rule 2 rather than OFF like rules 5-6, and the
  # difference is the same one that decided rules 2-3: rule 7's scope is four NAMED stems, and no
  # rules-1-6 fixture names any of them, so an ON rule 7 cannot convict a fixture whose subject is
  # another rule. Verified by running the selftest with this pin in place — the entrypoint cases
  # therefore need no `CC_HERM_ADMIT_RULE=off` companion, unlike rules 5 and 6's.
  ADMIT_RULE=on
  ADMIT_ALLOW=""
  lint_dir "$d/leak" ""               >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a NEW non-hermetic suite did not go RED"; fails=1; }
  lint_dir "$d/herm" "zz-fixture.bats" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a fixed-but-still-allowlisted suite did not go RED (ratchet not shrinking)"; fails=1; }
  lint_dir "$d/herm" ""                >/dev/null 2>&1 || { echo "SELFTEST FAIL: a hermetic suite did not go GREEN"; fails=1; }
  lint_dir "$d/leak" "zz-fixture.bats"  >/dev/null 2>&1 || { echo "SELFTEST FAIL: a grandfathered suite did not go GREEN"; fails=1; }
  # Case (e) must tell its two failure codes APART. A stale allowlist is a VERDICT about the tree
  # (exit 1). An unscannable dir is a NON-VERDICT (exit 2) and says nothing whatever about the
  # allowlist. Collapsing them is how the ROOT bug above surfaced as "your ratchet is stale" —
  # the same verdict/non-verdict conflation ship-land keeps apart as gate-red 6 vs gate-killed 9.
  # Both embedded allowlists are judged here, so a stale entry in EITHER ratchet is caught by (e).
  FIRE_ALLOW="$EMBEDDED_FIRE_ALLOWLIST"
  ORPHAN_ALLOW="$EMBEDDED_ORPHAN_ALLOWLIST"
  SEAM_RULE=on; SEAM_ALLOW="$EMBEDDED_SEAM_ALLOWLIST"; SEAM_ROOT="$ROOT"
  ENV_RULE=on; ENV_ALLOW="$EMBEDDED_ENV_ALLOWLIST"; ENV_ROOT="$ROOT"; ENV_TABLE_ROOT=""
  ADMIT_ALLOW="$EMBEDDED_ADMIT_ALLOWLIST"
  lint_dir "$ROOT/tests" "$EMBEDDED_ALLOWLIST" >/dev/null 2>&1; rc_real=$?
  # Read CHECK_FAILED on the very next line. It is a global that the NEXT lint_dir call resets, so
  # anything between the call and this read is a chance to lose the one bit that tells a lost fork
  # from a bad ROOT.
  cf_real=$CHECK_FAILED
  FIRE_ALLOW=""
  ORPHAN_ALLOW=""
  SEAM_RULE=off; SEAM_ALLOW=""
  ENV_RULE=off; ENV_ALLOW=""
  ADMIT_ALLOW=""
  selftest_realtree_disposition "$rc_real" "$cf_real"; disp_real=$?
  if [ "$disp_real" -eq 2 ]; then
    echo "SELFTEST NON-VERDICT: a predicate could not RUN while scanning $ROOT/tests — a fact about this BOX (a lost fork under load), NOT a claim about the tree or about either allowlist"
    nonverdict=1
  elif [ "$disp_real" -eq 1 ]; then
    if [ "$rc_real" -eq 2 ]; then
      echo "SELFTEST FAIL: could not scan $ROOT/tests — a NON-VERDICT (bad ROOT?), NOT a stale allowlist"; fails=1
    else
      echo "SELFTEST FAIL: an embedded allowlist is stale (\$HOME, capacity-gate, orphan-close, inherited-value and/or capacity-admit) — the real tree is not clean"; fails=1
    fi
  fi
  # ── (e2) and (e3): the two halves that keep case (e)'s third state DISCRIMINATING. A guard that
  # only ever widens is how detection disappears with nothing naming the loss, so both directions
  # are asserted — and each is asserted through selftest_realtree_disposition, the same function
  # the arm above calls, so neither can certify a mapping the arm does not use.
  #
  # (e2) A PREDICATE THAT CANNOT RUN. A `grep` that exits 2 is exactly what fork exhaustion looks
  # like to the pure predicates. Two things are proved at once: lint_dir answers 2, and CHECK_FAILED
  # is still readable HERE, in the caller's shell — the property a `$( )` would silently destroy.
  mkdir -p "$d/cfstub"
  { echo '#!/bin/bash'; echo 'exit 2'; } > "$d/cfstub/grep"; chmod +x "$d/cfstub/grep"
  cf_oldpath="$PATH"; PATH="$d/cfstub:$PATH"
  lint_dir "$d/herm" "" >/dev/null 2>&1; rc_lost=$?
  cf_lost=$CHECK_FAILED
  PATH="$cf_oldpath"
  [ "$rc_lost" -eq 2 ] && [ "$cf_lost" -ne 0 ] || { echo "SELFTEST FAIL: a predicate that could not RUN did not leave CHECK_FAILED readable in the caller's shell — case (e) can no longer tell a lost fork from a bad ROOT (a \$( ) around lint_dir does exactly this)"; fails=1; }
  selftest_realtree_disposition "$rc_lost" "$cf_lost"; [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: a lost fork on the real-tree scan was not mapped to a NON-VERDICT — a busy box will file a HOST RED against a clean tree"; fails=1; }
  # (e3) THE TOO-WIDE HALF, and the reason this is not simply "exit 2 ⇒ abstain". A bad ROOT also
  # exits 2, for a STRUCTURAL reason that must stay a FAIL — f37a84cf shipped a `dirname "$0"` that
  # resolved to ~/.claude, which has no tests/, and an abstain here would have hidden it.
  lint_dir "$d/definitely-absent" "" >/dev/null 2>&1; rc_bad=$?
  cf_bad=$CHECK_FAILED
  [ "$rc_bad" -eq 2 ] && [ "$cf_bad" -eq 0 ] || { echo "SELFTEST FAIL: a bad ROOT did not exit 2 with CHECK_FAILED clear — the two exit-2 reasons are indistinguishable again"; fails=1; }
  selftest_realtree_disposition "$rc_bad" "$cf_bad"; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a bad ROOT was excused as a NON-VERDICT — the abstain has grown over the structural failure it exists beside"; fails=1; }
  # ── RULE 3's four-way discrimination. Each assertion is paired with the one that proves it fired
  # for the RIGHT reason: red without the scope control is a rule that reds on everything.
  lint_dir "$d/orphleak" ""  >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a close-leg suite inheriting LCW_ORPHAN_CLOSE did not go RED"; fails=1; }
  lint_dir "$d/orphpin"  ""  >/dev/null 2>&1 || { echo "SELFTEST FAIL: a close-leg suite that PINS the lever did not go GREEN"; fails=1; }
  lint_dir "$d/noclose"  ""  >/dev/null 2>&1 || { echo "SELFTEST FAIL: a suite that never drives --close-panes was pulled INTO rule 3 (scoping broken)"; fails=1; }
  lint_dir "$d/orphpertest" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a PER-TEST pin was accepted — it leaves every other test on ambient state"; fails=1; }
  lint_dir "$d/orphcomment" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a setup() COMMENT naming the lever was accepted as a pin — the predicate is matching prose"; fails=1; }
  # Rule 3's grandfathering rides ORPHAN_ALLOW, NOT lint_dir's $2 (which is rule 1's list) — passing
  # $2 here would grandfather the wrong rule and, worse, make these two cases pass for rule 1's
  # reasons. Both fixtures are $HOME-hermetic, so $2 stays empty on purpose.
  ORPHAN_ALLOW="zz-fixture.bats"
  lint_dir "$d/orphleak" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a grandfathered close-leg suite did not go GREEN"; fails=1; }
  lint_dir "$d/orphpin"  "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a pinned-but-still-grandfathered suite did not go RED (rule-3 ratchet not shrinking)"; fails=1; }
  ORPHAN_ALLOW=""
  # The kill switch must actually kill: with rule 3 off, the RED fixture above must go green.
  ORPHAN_RULE=off
  lint_dir "$d/orphleak" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: CC_HERM_ORPHAN_RULE=off did not disable rule 3"; fails=1; }
  ORPHAN_RULE=on
  lint_dir "$d/nope" ""               >/dev/null 2>&1; [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: a missing scan dir did not exit 2 (LOUD)"; fails=1; }
  # ── OWN-SCOPE: both directions, because a scope that can only PASS is not a scope ────────────
  # (g) a leak OUTSIDE the own-set must not block — the fleet-wide-hard-stop fix itself.
  lint_dir "$d/leak" "" "some-other-suite.bats" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a leak OUTSIDE the own-set blocked (own-scope not applied)"; fails=1; }
  # (h) the SAME leak INSIDE the own-set must still block — proves (g) passed for the right reason
  #     and not because own-scope simply disables the rule.
  lint_dir "$d/leak" "" "zz-fixture.bats" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a leak INSIDE the own-set did not block — own-scope disabled the ratchet"; fails=1; }
  # (i) a stuck ratchet entry outside the own-set is advisory; inside it still blocks.
  lint_dir "$d/herm" "zz-fixture.bats" "other.bats" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a stuck entry OUTSIDE the own-set blocked"; fails=1; }
  lint_dir "$d/herm" "zz-fixture.bats" "zz-fixture.bats" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a stuck entry INSIDE the own-set did not block"; fails=1; }
  # (j) an own-set given as a PATH must match that path — ship-land passes `tests/x.bats`, and the
  #     suite really is under a directory named `tests`, so the entry matches on a component
  #     boundary (the scan dir is a temp prefix; the entry is its suffix).
  lint_dir "$d/pathown/tests" "" "tests/zz-fixture.bats" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: own-set given as a path did not match the judged path"; fails=1; }
  # (j2) THE BASENAME COLLAPSE, and it is the direction (j) alone cannot see. The SAME basename under
  #      a DIFFERENT directory must NOT block: the author who changed scripts/zz-fixture.bats is not
  #      answerable for tests/zz-fixture.bats, and convicting them is the fleet-wide hard stop
  #      own-scope exists to remove, re-entering through the matcher. RED before the fix.
  lint_dir "$d/pathown/tests" "" "scripts/zz-fixture.bats" >/dev/null 2>&1 || { echo "SELFTEST FAIL: an own-set naming the SAME basename in ANOTHER directory blocked — the basename collapse is back"; fails=1; }
  # (j3) …and a BARE entry is still deliberately wide: no directory was spelled, so it matches in
  #      any. (j2) and (j3) differ only in whether the entry carries a `/`, which is the whole rule.
  lint_dir "$d/pathown/tests" "" "zz-fixture.bats" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a BARE own-set entry did not match — the basename form is not optional, ship-land's siblings pass it"; fails=1; }
  # (k) THE DOCS-ONLY CASE — an own-set SUPPLIED BUT EMPTY means "I change no suite": nothing may
  #     block. This is the whole point of the fix and the one `${VAR:-}` would silently break.
  lint_dir "$d/leak" "" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: an EMPTY own-set blocked — set-empty was collapsed into unset, docs-only lands still hard-stop"; fails=1; }
  # (l) …while omitting the argument entirely still means STRICT. (k) and (l) differ ONLY in arity,
  #     so together they prove the three states are really distinguished.
  lint_dir "$d/leak" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: an ABSENT own-set did not block — strict default lost"; fails=1; }
  # (m) entrypoint-level parity for the same distinction, via the real CC_HERM_OWN seam.
  # Rule 4 is pinned OFF in every entrypoint sub-invocation below: those spawn a fresh process, so
  # unlike the in-process lint_dir cases they would ALSO run rule 4 against the real $ROOT, and a
  # rule-4 verdict about the checkout would silently become this rule-1/2 assertion's answer.
  # Rule 4 gets its own entrypoint parity pair at (a4)-(m4), where it is pinned ON.
  ( unset CC_HERM_OWN; CC_HERM_SELFTEST_RULE=off CC_HERM_ALLOWLIST="" CC_HERM_ENV_RULE=off "$SELF" "$d/leak" >/dev/null 2>&1 ); [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: CC_HERM_OWN unset did not block at the entrypoint"; fails=1; }
  ( CC_HERM_SEAM_RULE=off CC_HERM_OWN="" CC_HERM_SELFTEST_RULE=off CC_HERM_ALLOWLIST="" CC_HERM_ENV_RULE=off "$SELF" "$d/leak" >/dev/null 2>&1 ) || { echo "SELFTEST FAIL: CC_HERM_OWN set-but-empty blocked at the entrypoint"; fails=1; }
  # (n) COULD-NOT-CHECK is a non-verdict, not a leak — and own-scope must not paper over it.
  # Simulates the real incident: a `grep` that cannot RUN (rc>1). Shadowing grep in a subshell
  # reproduces exactly what fork exhaustion / a reaped child does to these predicates. Before the
  # fix this reported a LEAK naming a perfectly good suite; the contract is exit 2 and no leak line.
  # The output test is a `case`, not a grep — for (x)'s reason, which applies here FIRST: grep is the
  # very thing stubbed above, so `… | grep -q LEAK` inherits the stub's rc=2 and can never fire. That
  # spelling left this leg with NO live guard: under it the selftest stayed a green 38/38 even with the
  # 2026-07-26 incident reinstated in the source.
  # RED-PROOF (it takes a DOUBLE mutant — a single one is too weak to reach the LEAK line, so a control
  # that reverts only one fail-SAFE proves nothing and reads as "the fix didn't work"): revert BOTH
  # fail-SAFE returns in series — is_hermetic() `return 0`→1 (~line 324) AND in_allowlist() `return 0`→1
  # (~line 443). Either one alone still short-circuits the printf at line ~504. With both reverted this
  # case fires and the selftest exits 1; with the old grep spelling it stayed silent at rc=0.
  ( grep() { return 2; }
    out="$(lint_dir "$d/leak" "" 2>&1)"; rc=$?
    [ "$rc" -eq 2 ] || { echo "SELFTEST FAIL: an unrunnable predicate did not exit 2 (got $rc) — a killed check must never be a verdict"; exit 1; }
    case "$out" in *LEAK*) echo "SELFTEST FAIL: an unrunnable predicate still fabricated a LEAK line"; exit 1 ;; esac
    exit 0
  ) || fails=1
  # (o) …and it stays a non-verdict WITH an own-set supplied: own-scope narrows which violations
  # BLOCK, it never makes an unrunnable check trustworthy. Guards the composition of the two fixes.
  ( grep() { return 2; }
    lint_dir "$d/leak" "" "zz-fixture.bats" >/dev/null 2>&1
    [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: an unrunnable predicate under own-scope did not exit 2"; exit 1; }
    exit 0
  ) || fails=1

  # ── RULE 2 (capacity gate) — the same two-sided discipline, plus a SCOPE control, because a rule
  # that fires on everything would pass every RED assertion below while being worthless. ──────────
  # (p) RED: a suite that drives handoff-fire without pinning the gate reads AMBIENT machine load.
  lint_dir "$d/fireleak" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: an UNPINNED handoff-fire suite did not go RED (rule 2 is inert)"; fails=1; }
  # (q) GREEN: the same suite with the pin in setup() — the fix the RED prescribes actually clears it.
  lint_dir "$d/firepin" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a suite pinning CC_FIRE_CAPACITY_GATE=off in setup() did not go GREEN"; fails=1; }
  # (r) SCOPE CONTROL for (p): the same suite MINUS the handoff-fire reference must be GREEN. Without
  #     this, (p) could be passing because rule 2 flags every suite, not because that suite fires.
  lint_dir "$d/nofire" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a suite that never mentions handoff-fire was flagged — rule 2 is not scoped"; fails=1; }
  # (s) RED: pinned but STILL on the fire allowlist — the second ratchet may only ever shrink.
  FIRE_ALLOW="zz-fixture.bats"
  lint_dir "$d/firepin" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a pinned-but-still-grandfathered suite did not go RED (fire ratchet is not shrinking)"; fails=1; }
  # (t) GREEN: unpinned but grandfathered — today's list must not block anybody. Pairs with (s):
  #     together they show the fire allowlist is consulted in BOTH directions, not just one.
  lint_dir "$d/fireleak" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a grandfathered unpinned suite did not go GREEN"; fails=1; }
  FIRE_ALLOW=""
  # (u) per-TEST pinning does NOT count — rule 1's reason verbatim: every OTHER test in the file is
  #     still on ambient load. Four suites in the tree are grandfathered for exactly this shape.
  lint_dir "$d/firepertest" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a per-TEST CC_FIRE_CAPACITY_GATE counted as pinned"; fails=1; }
  lint_dir "$d/firecomment" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a setup() COMMENT naming CC_FIRE_CAPACITY_GATE=off counted as pinned — rule 2 is matching prose"; fails=1; }
  # (v2) the SCOPE half of the same prose discipline, and the direction the pair was asymmetric in:
  #      a suite that merely MENTIONS handoff-fire in a comment must be OUT of scope, not convicted
  #      for failing to pin a lever it never reads. Pairs with (r): (r) shows an unrelated suite is
  #      not flagged, this shows that naming the subject in prose does not make it related.
  lint_dir "$d/firementiononly" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a suite mentioning handoff-fire only in a COMMENT was pulled into rule 2 — the scope predicate is matching prose"; fails=1; }
  lint_dir "$d/closementiononly" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a suite mentioning --close-panes only in a COMMENT was pulled into rule 3 — the scope predicate is matching prose"; fails=1; }
  # (w) own-scope governs rule 2 as well: advisory OUTSIDE the lander's diff, blocking INSIDE it.
  lint_dir "$d/fireleak" "" "some-other-suite.bats" >/dev/null 2>&1 || { echo "SELFTEST FAIL: an AMBIENT violation OUTSIDE the own-set blocked"; fails=1; }
  lint_dir "$d/fireleak" "" "zz-fixture.bats" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: an AMBIENT violation INSIDE the own-set did not block"; fails=1; }
  # (x) COULD-NOT-CHECK survives rule 2: an unrunnable predicate is a NON-VERDICT (exit 2) and must
  #     never print an AMBIENT line naming a suite nobody was able to check. The output test is a
  #     `case`, not a grep — grep is the very thing stubbed here, so a grep-based assertion would be
  #     structurally incapable of failing (a dead assertion wearing an assertion's clothes).
  ( grep() { return 2; }
    out="$(lint_dir "$d/fireleak" "" 2>&1)"; rc=$?
    [ "$rc" -eq 2 ] || { echo "SELFTEST FAIL: an unrunnable rule-2 predicate did not exit 2 (got $rc)"; exit 1; }
    case "$out" in *AMBIENT*) echo "SELFTEST FAIL: an unrunnable rule-2 predicate still fabricated an AMBIENT line"; exit 1 ;; esac
    exit 0
  ) || fails=1
  # (y) entrypoint parity for the CC_HERM_FIRE_ALLOWLIST seam, both directions — the RED half is
  #     also the positive control for the kill switch in (z), which is the identical command + one
  #     variable. Rule 1's allowlist is emptied in both so only rule 2 can produce the verdict.
  #     CC_HERM_FIRE_RULE=on is passed explicitly so an ambient kill switch in the CALLER's
  #     environment cannot neuter the child and turn (y)'s RED half into an unexplained failure.
  ( CC_HERM_SEAM_RULE=off CC_HERM_ALLOWLIST="" CC_HERM_FIRE_ALLOWLIST="" CC_HERM_FIRE_RULE=on CC_HERM_SELFTEST_RULE=off CC_HERM_ENV_RULE=off "$SELF" "$d/fireleak" >/dev/null 2>&1 ); [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: CC_HERM_FIRE_ALLOWLIST set-but-empty did not block at the entrypoint"; fails=1; }
  ( CC_HERM_SEAM_RULE=off CC_HERM_ALLOWLIST="" CC_HERM_FIRE_ALLOWLIST="zz-fixture.bats" CC_HERM_FIRE_RULE=on CC_HERM_SELFTEST_RULE=off CC_HERM_ENV_RULE=off "$SELF" "$d/fireleak" >/dev/null 2>&1 ) || { echo "SELFTEST FAIL: CC_HERM_FIRE_ALLOWLIST did not grandfather at the entrypoint"; fails=1; }
  # (z) the kill switch turns rule 2 off — and ONLY rule 2 (rule 1 still judges the same tree).
  ( CC_HERM_SEAM_RULE=off CC_HERM_ALLOWLIST="" CC_HERM_FIRE_ALLOWLIST="" CC_HERM_FIRE_RULE=off CC_HERM_SELFTEST_RULE=off CC_HERM_ENV_RULE=off "$SELF" "$d/fireleak" >/dev/null 2>&1 ) || { echo "SELFTEST FAIL: CC_HERM_FIRE_RULE=off did not disable rule 2"; fails=1; }

  # ── RULE 7 (the capacity-ADMIT gate) — rule 2's discrimination set at the other gate, plus one
  # case rule 2 has no analogue for: the SHORT form 2, which is the filing's own remedy and must go
  # RED. Every RED below is paired with the GREEN that proves it fired for its own reason. ────────
  # (a7) RED: a suite driving a capacity-admit caller without closing the gate. The rule is not inert.
  lint_dir "$d/admitleak" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: an UNPINNED capacity-admit suite did not go RED (rule 7 is inert)"; fails=1; }
  # (b7) GREEN: form 1 — the identical suite plus the one-line kill switch. The fix the RED prescribes.
  lint_dir "$d/admitpin" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a suite pinning CC_ADMIT_GATE=off in setup() did not go GREEN"; fails=1; }
  # (c7) GREEN: form 2 complete — both instrument overrides AND a reserve closure.
  lint_dir "$d/admitform2" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a suite closing all THREE admit terms did not go GREEN — form 2 is unreachable"; fails=1; }
  # (d7) 🚨 RED: form 2 MINUS the reserve closure — backlog 5ef0dcb22aec's remedy verbatim, and what
  #      tests/capacity-admit.bats does today. Proven ambient two-sided: that suite is 20/20 green and
  #      17/20 under CC_SP_TREES_OVERRIDE=999. This is the one assertion whose loss returns rule 7 to
  #      a false negative on the very suite whose subject is this gate.
  lint_dir "$d/admitform2short" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: the two-variable form 2 counted as PINNED — the reserve term (450a47c50) is unguarded"; fails=1; }
  # (e7) SCOPE CONTROL: byte-identical to admitleak minus the reference. Without it every case above
  #      is consistent with a rule that reds on everything.
  lint_dir "$d/noadmit" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a suite naming no capacity-admit caller went RED (rule 7 fires on everything)"; fails=1; }
  # (f7) RED: a per-TEST close leaves every OTHER test reading the live box — rule 1's reason verbatim.
  lint_dir "$d/admitpertest" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a per-TEST CC_ADMIT_GATE counted as pinned"; fails=1; }
  # (g7) RED: a setup() COMMENT that merely names the pin — rule 3's prose regression, two rules on.
  lint_dir "$d/admitcomment" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a setup() COMMENT naming CC_ADMIT_GATE=off counted as pinned — rule 7 is matching prose"; fails=1; }
  # (h7) GREEN: the SCOPE half of the same discipline — a caller named only inside a sentence the
  #      suite carries as DATA. This is the only case that exercises strip_prose's generalisation, so
  #      it is also the proof that parameterising it did not silently disarm the subtraction.
  lint_dir "$d/admitproseonly" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a caller named only in PROSE pulled a suite INTO rule 7 — strip_prose is not parameterised correctly"; fails=1; }
  # (i7) the ratchet, both directions.
  ADMIT_ALLOW="zz-fixture.bats"
  lint_dir "$d/admitleak" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a grandfathered unclosed admit suite did not go GREEN"; fails=1; }
  lint_dir "$d/admitpin"  "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a closed-but-still-grandfathered suite did not go RED (admit ratchet is not shrinking)"; fails=1; }
  ADMIT_ALLOW=""
  # (j7) own-scope, both ways — a violation OUTSIDE the diff advises, INSIDE it blocks.
  lint_dir "$d/admitleak" "" "some-other-suite.bats" >/dev/null 2>&1 || { echo "SELFTEST FAIL: an admit violation OUTSIDE the own-set blocked"; fails=1; }
  lint_dir "$d/admitleak" "" "zz-fixture.bats" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: an admit violation INSIDE the own-set did not block"; fails=1; }
  # (k7) entrypoint parity for both env seams, all three directions — rule 2's (y)/(z) verbatim.
  ( CC_HERM_SEAM_RULE=off CC_HERM_ALLOWLIST="" CC_HERM_ADMIT_ALLOWLIST="" CC_HERM_ADMIT_RULE=on CC_HERM_SELFTEST_RULE=off CC_HERM_ENV_RULE=off "$SELF" "$d/admitleak" >/dev/null 2>&1 ); [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: CC_HERM_ADMIT_ALLOWLIST set-but-empty did not block at the entrypoint"; fails=1; }
  ( CC_HERM_SEAM_RULE=off CC_HERM_ALLOWLIST="" CC_HERM_ADMIT_ALLOWLIST="zz-fixture.bats" CC_HERM_ADMIT_RULE=on CC_HERM_SELFTEST_RULE=off CC_HERM_ENV_RULE=off "$SELF" "$d/admitleak" >/dev/null 2>&1 ) || { echo "SELFTEST FAIL: CC_HERM_ADMIT_ALLOWLIST did not grandfather at the entrypoint"; fails=1; }
  ( CC_HERM_SEAM_RULE=off CC_HERM_ALLOWLIST="" CC_HERM_ADMIT_ALLOWLIST="" CC_HERM_ADMIT_RULE=off CC_HERM_SELFTEST_RULE=off CC_HERM_ENV_RULE=off "$SELF" "$d/admitleak" >/dev/null 2>&1 ) || { echo "SELFTEST FAIL: CC_HERM_ADMIT_RULE=off did not disable rule 7"; fails=1; }

  # ── RULE 4 (the embedded selftest) — the same two-sided discipline with TWO scope controls,
  # because rule 4 has two independent ways to be worthless: firing on tools that ship no selftest,
  # and firing on selftests that create no state. Each RED below is paired with the GREEN that
  # proves it fired for its own reason. ─────────────────────────────────────────────────────────
  # (a4) RED: a selftest whose scratch dir is the same string on every run.
  lint_selftests "$d/s_collide" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a selftest naming a CONSTANT scratch path did not go RED (rule 4 is inert)"; fails=1; }
  # (b4) GREEN: the identical selftest with mktemp — the fix the RED prescribes actually clears it.
  lint_selftests "$d/s_ok" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: an mktemp-confined selftest did not go GREEN"; fails=1; }
  # (n4) RED: mktemp is present but BYPASSED. The ISOLATING case for the const-path half — (a4)
  #      alone cannot prove that half fires, because s_collide violates both. Mutation found it.
  lint_selftests "$d/s_bypass" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a selftest that mktemps and then writes a constant path anyway did not go RED — the const-path probe is inert"; fails=1; }
  # (c4) SCOPE CONTROL 1 — zz-plain names a constant path in a state-bearing position but ships NO
  #      selftest, so rule 4 must neither FLAG it nor COUNT it. Without this, (a4) could be passing
  #      because rule 4 flags every file in bin/.
  #      THE COUNT IS THE LOAD-BEARING HALF, and that is a mutation result rather than a hunch: the
  #      verdict-only form of this case was a DEAD assertion. Stubbing has_selftest() to match every
  #      file killed nothing, because selftest_region() yields an empty body for a file with no
  #      opener and both violation probes then correctly find nothing in it — so the exit code was 0
  #      either way. The denominator is the only observable that moves, and a wrong denominator is
  #      what silently dilutes the floor guard below.
  ( out="$(lint_selftests "$d/s_scope" "" 2>&1)"; rc=$?
    [ "$rc" -eq 0 ] || { echo "SELFTEST FAIL: a file with no embedded selftest was FLAGGED by rule 4 (scoping broken)"; exit 1; }
    case "$out" in
      *"1 embedded selftest(s)"*) ;;
      *) echo "SELFTEST FAIL: a file with no embedded selftest was COUNTED in rule 4's denominator (scoping broken)"; exit 1 ;;
    esac
    exit 0
  ) || fails=1
  # (d4) SCOPE CONTROL 2 — a selftest that creates nothing cannot collide, so it is never flagged.
  #      This is what keeps the mktemp half from becoming a blanket mandate.
  lint_selftests "$d/s_nostate" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a selftest that creates NO state was flagged — the creates-probe is not scoping"; fails=1; }
  # (e4) RED: creates state at a constant path that is NOT under /tmp. The const-path probe alone is
  #      blind here, so this is the assertion that earns the second half of the rule.
  lint_selftests "$d/s_nomktemp" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a selftest creating state without mktemp did not go RED"; fails=1; }
  # (f4) RED: the PROSE-MATCH regression, one rule later. The word is in a comment; the call is not
  #      there. Rules 2 and 3 both shipped vacuous on exactly this shape.
  lint_selftests "$d/s_prose" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a COMMENT naming mktemp counted as confinement — rule 4 is matching prose"; fails=1; }
  # (g4)/(h4) the ratchet is consulted in BOTH directions: grandfathered ⇒ green, fixed-but-listed ⇒ red.
  lint_selftests "$d/s_collide" "zz-tool" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a grandfathered colliding selftest did not go GREEN"; fails=1; }
  lint_selftests "$d/s_ok" "zz-tool" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a confined-but-still-grandfathered tool did not go RED (rule-4 ratchet not shrinking)"; fails=1; }
  # (i4) own-scope governs rule 4 too: advisory OUTSIDE the lander's diff, blocking INSIDE it.
  lint_selftests "$d/s_collide" "" "some-other-tool" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a COLLIDES violation OUTSIDE the own-set blocked"; fails=1; }
  lint_selftests "$d/s_collide" "" "bin/zz-tool"    >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a COLLIDES violation INSIDE the own-set did not block (path form not matched against the judged path)"; fails=1; }
  # (i4b) …and the collapse direction, which rule 4 can state more sharply than rule 1 because its
  #       population really does span three directories: the tool is bin/zz-tool, so an author who
  #       changed scripts/zz-tool must NOT be refused over it (backlog c1a29f8ee045). RED pre-fix.
  lint_selftests "$d/s_collide" "" "scripts/zz-tool" >/dev/null 2>&1 || { echo "SELFTEST FAIL: an own-set naming the same tool basename under ANOTHER dir blocked — the basename collapse is back"; fails=1; }
  # (j4) COULD-NOT-CHECK survives rule 4: a NON-VERDICT (exit 2) and no COLLIDES line naming a tool
  #      nobody was able to check. The output test is a `case`, not a grep — grep is what is stubbed.
  ( grep() { return 2; }
    out="$(lint_selftests "$d/s_ok" "" 2>&1)"; rc=$?
    [ "$rc" -eq 2 ] || { echo "SELFTEST FAIL: an unrunnable rule-4 predicate did not exit 2 (got $rc)"; exit 1; }
    case "$out" in *COLLIDES*) echo "SELFTEST FAIL: an unrunnable rule-4 predicate still fabricated a COLLIDES line"; exit 1 ;; esac
    exit 0
  ) || fails=1
  # (k4) THE EXTRACTOR CONTROL. An extractor blind to its own anchor is a NON-VERDICT, never the
  #      "clean" it would otherwise print — the assertion that stops rule 4 going silently inert if
  #      the region convention ever changes. It replaced a numeric floor, which could only express
  #      this as "the tree looks small" and so condemned every tree smaller than the one it was
  #      calibrated on (ship-land's fixture repos among them, caught by their own suite).
  ( out="$(lint_selftests "$d/s_anchor" "" 2>&1)"; rc=$?
    [ "$rc" -eq 2 ] || { echo "SELFTEST FAIL: an extractor blind to its OWN anchor did not exit 2 — a vacuous rule would read as clean (got $rc)"; exit 1; }
    # The token, not the word: the guard's own explanation contains "clean" ("do not read it as a
    # clean bill"), so a bare *clean* glob matches the very message that proves the case passed.
    case "$out" in *"lint: clean"*) echo "SELFTEST FAIL: an extractor blind to its own anchor still printed a clean summary"; exit 1 ;; esac
    exit 0
  ) || fails=1
  # (k4b) THE PAIRED GREEN, and the IFBLOCK SHAPE COVERAGE in one. Same root shape, but the anchor
  #      is a real copy of THIS script — so the control fires on the extractor's blindness rather
  #      than on the anchor merely being present, AND the `if [ "${1:-}" = "--selftest" ]` shape is
  #      proved detectable (every other rule-4 fixture uses the `selftest()` function shape, so
  #      without this one a broken IFBLOCK arm would go unnoticed here).
  lint_selftests "$d/s_anchor_ok" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a WORKING anchor (this script itself, IFBLOCK shape) was not detected — shape coverage or the anchor control is broken"; fails=1; }
  # (l4) the REAL tree: it must be clean under the embedded allowlist, and its anchor must be found.
  #      Rule 4's analogue of case (e) — a stale rule-4 ratchet is caught here.
  lint_selftests "$ROOT" "$EMBEDDED_SELFTEST_ALLOWLIST" >/dev/null 2>&1; rc_real4=$?
  case "$rc_real4" in
    0) ;;
    2) echo "SELFTEST FAIL: could not scan $ROOT for embedded selftests — a NON-VERDICT (bad ROOT? extractor broken?), NOT a stale allowlist"; fails=1 ;;
    *) echo "SELFTEST FAIL: EMBEDDED_SELFTEST_ALLOWLIST is stale, or a tool's selftest collides — the real tree is not clean"; fails=1 ;;
  esac
  # (m4) entrypoint parity for rule 4's two seams, and the kill switch with its positive control.
  #      The scan dir is the hermetic fixture with rule 1's allowlist emptied, so rule 1 contributes
  #      0 and only rule 4 can produce the verdict.
  ( CC_HERM_SEAM_RULE=off CC_HERM_ALLOWLIST="" CC_HERM_SELFTEST_ROOT="$d/s_collide" CC_HERM_SELFTEST_ALLOWLIST="" CC_HERM_SELFTEST_RULE=on CC_HERM_ENV_RULE=off "$SELF" "$d/herm" >/dev/null 2>&1 ); [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: CC_HERM_SELFTEST_ALLOWLIST set-but-empty did not block at the entrypoint"; fails=1; }
  ( CC_HERM_SEAM_RULE=off CC_HERM_ALLOWLIST="" CC_HERM_SELFTEST_ROOT="$d/s_collide" CC_HERM_SELFTEST_ALLOWLIST="zz-tool" CC_HERM_SELFTEST_RULE=on CC_HERM_ENV_RULE=off "$SELF" "$d/herm" >/dev/null 2>&1 ) || { echo "SELFTEST FAIL: CC_HERM_SELFTEST_ALLOWLIST did not grandfather at the entrypoint"; fails=1; }
  ( CC_HERM_SEAM_RULE=off CC_HERM_ALLOWLIST="" CC_HERM_SELFTEST_ROOT="$d/s_collide" CC_HERM_SELFTEST_ALLOWLIST="" CC_HERM_SELFTEST_RULE=off CC_HERM_ENV_RULE=off "$SELF" "$d/herm" >/dev/null 2>&1 ) || { echo "SELFTEST FAIL: CC_HERM_SELFTEST_RULE=off did not disable rule 4"; fails=1; }

  # ── RULE 5's assertions. Every one runs in a SUBSHELL that turns the rule on against the FIXTURE
  # seam root: the globals stay off outside, so a rule-5 verdict can never answer a rule-1/2/3
  # question and the real checkout can never answer a rule-5 one.
  r5() { ( SEAM_RULE=on; SEAM_ROOT="$d/r5root"; SEAM_TABLE_ROOT=""; SEAM_ALLOW="$2"
           lint_dir "$d/$1" "" >/dev/null 2>&1 ) }
  # (a5) RED: a suite naming a tool with an ABSOLUTE /tmp seam, unpinned — a514d3b0's shape 5a.
  r5 r5leak ""; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: an unpinned shape-5a seam did not go RED"; fails=1; }
  # (b5) RED: shape 5b — the subject EXECUTES a bare name off the operator's PATH.
  r5 r5execleak ""; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: an unpinned shape-5b seam did not go RED"; fails=1; }
  # (c5) GREEN: the seam is assigned in setup().
  r5 r5pin "" || { echo "SELFTEST FAIL: a suite pinning its seam did not go GREEN"; fails=1; }
  # (d5) RED: per-test assignment leaves every OTHER test pointed at live state (rule 1's law).
  r5 r5pertest ""; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a PER-TEST seam assignment was accepted as a pin"; fails=1; }
  # (e5) THE SCOPE CONTROL: a suite naming only a seamless tool. Without this, every RED above could
  #      be a rule that simply fires on everything.
  r5 r5scope "" || { echo "SELFTEST FAIL: a suite naming a tool with NO seam was dragged into scope"; fails=1; }
  # (f5) THE COMMENT-STRIP CONTROL: a tool named only in PROSE executes nothing (rule 2's and rule
  #      4's prose-match regressions, applied here to the SCOPE test).
  r5 r5comment "" || { echo "SELFTEST FAIL: a tool named only in a COMMENT pulled the suite into scope"; fails=1; }
  # (g5) THE NAME-BOUNDARY CONTROL: zz-seamtool's seams must not reach zz-seamtool-extra.
  r5 r5prefix "" || { echo "SELFTEST FAIL: a tool name matched as a PREFIX of a different tool"; fails=1; }
  # (g5b) THE HOLDER CONTROL: same bare name, same shipped tool, but the holder is only PRINTED. If
  #       this goes red the holder test is inert and every shape-5b RED above is proving nothing —
  #       the STRICT_TOOLS/PAGE_KEY false positives measured in the real tree.
  r5 r5holder "" || { echo "SELFTEST FAIL: a bare-name seam whose holder is never EXECUTED was flagged as shape 5b"; fails=1; }
  # (h5) GREEN when grandfathered, and (i5) RED when grandfathered AFTER being fixed — the two
  #      halves of the ratchet contract, the second being what stops it decaying into an exemption list.
  r5 r5leak "zz-fixture.bats" || { echo "SELFTEST FAIL: a grandfathered seam leak did not go GREEN"; fails=1; }
  r5 r5pin "zz-fixture.bats"; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a pinned-but-still-allowlisted suite did not go RED (seam ratchet not shrinking)"; fails=1; }
  # (j5) THE ANCHOR CONTROL, calibration-free: a seam root carrying this script's own path WITHOUT
  #      the anchor seam is an EXTRACTOR failure, so the run is a NON-VERDICT (exit 2), never a
  #      clean bill. (k5) is its paired GREEN — a real copy, whose anchor must be found.
  ( SEAM_RULE=on; SEAM_ROOT="$d/r5anchor"; SEAM_TABLE_ROOT=""; SEAM_ALLOW=""
    lint_dir "$d/herm" "" >/dev/null 2>&1 ); [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: a seam extractor blind to its OWN anchor did not produce a NON-VERDICT"; fails=1; }
  ( SEAM_RULE=on; SEAM_ROOT="$d/r5anchor_ok"; SEAM_TABLE_ROOT=""; SEAM_ALLOW=""
    lint_dir "$d/herm" "" >/dev/null 2>&1 ) || { echo "SELFTEST FAIL: a WORKING seam anchor (this script itself) was not detected"; fails=1; }
  # (l5) entrypoint parity for all three of rule 5's env seams, with the kill switch's positive
  #      control. The scan dir is the hermetic fixture with rule 1's allowlist emptied, so rule 1
  #      contributes 0 and only rule 5 can produce the verdict.
  ( CC_HERM_ALLOWLIST="" CC_HERM_SELFTEST_RULE=off CC_HERM_SEAM_ROOT="$d/r5root" CC_HERM_SEAM_ALLOWLIST="" CC_HERM_SEAM_RULE=on CC_HERM_ENV_RULE=off "$SELF" "$d/r5leak" >/dev/null 2>&1 ); [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: CC_HERM_SEAM_ALLOWLIST set-but-empty did not block at the entrypoint"; fails=1; }
  ( CC_HERM_ALLOWLIST="" CC_HERM_SELFTEST_RULE=off CC_HERM_SEAM_ROOT="$d/r5root" CC_HERM_SEAM_ALLOWLIST="zz-fixture.bats" CC_HERM_SEAM_RULE=on CC_HERM_ENV_RULE=off "$SELF" "$d/r5leak" >/dev/null 2>&1 ) || { echo "SELFTEST FAIL: CC_HERM_SEAM_ALLOWLIST did not grandfather at the entrypoint"; fails=1; }
  ( CC_HERM_ALLOWLIST="" CC_HERM_SELFTEST_RULE=off CC_HERM_SEAM_ROOT="$d/r5root" CC_HERM_SEAM_ALLOWLIST="" CC_HERM_SEAM_RULE=off CC_HERM_ENV_RULE=off "$SELF" "$d/r5leak" >/dev/null 2>&1 ) || { echo "SELFTEST FAIL: CC_HERM_SEAM_RULE=off did not disable rule 5"; fails=1; }

  # ── RULE 6's assertions. Every one runs in a SUBSHELL that turns the rule on against the FIXTURE
  # tool root — rule 5's discipline verbatim: the globals stay off outside, so a rule-6 verdict can
  # never answer a rules-1-5 question and the real checkout can never answer a rule-6 one.
  r6() { ( ENV_RULE=on; ENV_ROOT="$d/r6root"; ENV_TABLE_ROOT=""; ENV_ALLOW="$2"
           lint_dir "$d/$1" "" >/dev/null 2>&1 ) }
  # (a6) RED: the subject READS a variable this repo injects into every pane, and setup() takes no
  #      position on it — 0588d255's shape exactly.
  r6 r6leak ""; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: an unpinned inherited-value seam did not go RED"; fails=1; }
  # (b6) GREEN via unset — the remedy 0588d255 actually used, and the one rule 5's assignment-only
  #      predicate REJECTS. If this goes red, rule 6 has collapsed into rule 5 and the very fix that
  #      generated the rule reads as violating it.
  r6 r6unset "" || { echo "SELFTEST FAIL: an 'unset' in setup() did not clear the rule — rule 6 has collapsed into rule 5's assignment-only predicate"; fails=1; }
  # (c6) GREEN via ASSIGNMENT — rule 3's asymmetry: ANY deterministic position counts, because what
  #      is forbidden is INHERITING one, not choosing the "wrong" one.
  r6 r6assign "" || { echo "SELFTEST FAIL: an ASSIGNED inherited-value seam did not go GREEN"; fails=1; }
  # (d6) THE INJECT-ONLY SCOPE CONTROL, and the most load-bearing assertion rule 6 has. A tool that
  #      puts a variable on a pane and never READS it is not exposed to it. Drop this half of the
  #      intersection and scripts/handoff-fire.sh joins the table, grandfathering 49 suites for a
  #      variable their subject does not read (measured, not supposed).
  r6 r6inject "" || { echo "SELFTEST FAIL: a suite naming an INJECT-ONLY tool was pulled into scope — the intersection collapsed to its PROPAGATED half"; fails=1; }
  # (e6) THE NON-PROPAGATED SCOPE CONTROL, the other half. A plain-valued seam that NOTHING injects
  #      cannot be inherited. Drop this half and the rule is the filing's naive version — 1047 seam
  #      assignments and most of 324 suites in scope.
  r6 r6unprop "" || { echo "SELFTEST FAIL: a plain-valued seam that NOTHING injects was flagged — the intersection collapsed to its READ half (the naive rule)"; fails=1; }
  # (f6) the ordinary scope control: a suite naming a tool with no seam of any kind.
  r6 r6scope "" || { echo "SELFTEST FAIL: a suite naming a tool with NO inherited-value seam was dragged into scope"; fails=1; }
  # (g6) RED: a per-test position leaves every OTHER test inheriting — rule 1's law.
  r6 r6pertest ""; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a PER-TEST unset was accepted as a position"; fails=1; }
  # (h6) THE COMMENT-STRIP CONTROL: a tool named only in PROSE executes nothing.
  r6 r6comment "" || { echo "SELFTEST FAIL: a tool named only in a COMMENT pulled the suite into rule 6"; fails=1; }
  # (i6) THE NAME-BOUNDARY CONTROL: pinning ZZ_ENV_MODE_DIR must NOT count as pinning ZZ_ENV_MODE.
  #      The real tree carries the same collision (CC_PANE_CMD strictly prefixes two siblings), so
  #      without a boundary after the name one pin would excuse all three.
  r6 r6prefix ""; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: pinning a LONGER variable counted as pinning the one it prefixes"; fails=1; }
  # (o6) GREEN: a STATEMENT-TERMINATED unset is still a position. Rule 3's narrower trailing class
  #      misses this for the LAST name in the list, so the predicate would report a suite that DID
  #      take a position as violating — a false RED, the fail direction a pin test must never have.
  #      Found by mutation (judging the whole file instead of setup() failed to flip (g6), because
  #      the fixture's unset ended in `;` and neither name matched).
  r6 r6semi "" || { echo "SELFTEST FAIL: a statement-terminated 'unset FOO;' was not accepted as a position — the trailing boundary is too narrow and compliant suites go falsely RED"; fails=1; }
  # (j6)/(k6) the ratchet consulted in BOTH directions — grandfathered ⇒ green, fixed-but-listed ⇒ red.
  r6 r6leak "zz-fixture.bats" || { echo "SELFTEST FAIL: a grandfathered inherited-value leak did not go GREEN"; fails=1; }
  r6 r6unset "zz-fixture.bats"; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a pinned-but-still-allowlisted suite did not go RED (inherited-value ratchet not shrinking)"; fails=1; }
  # (l6) THE ANCHOR CONTROL, calibration-free: a tool root carrying this script's own path WITHOUT
  #      the anchor is an EXTRACTOR failure, so the run is a NON-VERDICT (exit 2), never a clean
  #      bill. (m6) is its paired GREEN — a real copy, whose anchor must be found through BOTH
  #      halves of the intersection at once.
  ( ENV_RULE=on; ENV_ROOT="$d/r6anchor"; ENV_TABLE_ROOT=""; ENV_ALLOW=""
    lint_dir "$d/herm" "" >/dev/null 2>&1 ); [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: an inherited-value extractor blind to its OWN anchor did not produce a NON-VERDICT"; fails=1; }
  ( ENV_RULE=on; ENV_ROOT="$d/r6anchor_ok"; ENV_TABLE_ROOT=""; ENV_ALLOW=""
    lint_dir "$d/herm" "" >/dev/null 2>&1 ) || { echo "SELFTEST FAIL: a WORKING inherited-value anchor (this script itself) was not detected"; fails=1; }
  # (n6) entrypoint parity for all three of rule 6's env seams, with the kill switch's positive
  #      control. Rule 1's allowlist is emptied and rules 4-5 pinned off, so only rule 6 can produce
  #      the verdict.
  ( CC_HERM_ALLOWLIST="" CC_HERM_SELFTEST_RULE=off CC_HERM_SEAM_RULE=off CC_HERM_ENV_ROOT="$d/r6root" CC_HERM_ENV_ALLOWLIST="" CC_HERM_ENV_RULE=on "$SELF" "$d/r6leak" >/dev/null 2>&1 ); [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: CC_HERM_ENV_ALLOWLIST set-but-empty did not block at the entrypoint"; fails=1; }
  ( CC_HERM_ALLOWLIST="" CC_HERM_SELFTEST_RULE=off CC_HERM_SEAM_RULE=off CC_HERM_ENV_ROOT="$d/r6root" CC_HERM_ENV_ALLOWLIST="zz-fixture.bats" CC_HERM_ENV_RULE=on "$SELF" "$d/r6leak" >/dev/null 2>&1 ) || { echo "SELFTEST FAIL: CC_HERM_ENV_ALLOWLIST did not grandfather at the entrypoint"; fails=1; }
  ( CC_HERM_ALLOWLIST="" CC_HERM_SELFTEST_RULE=off CC_HERM_SEAM_RULE=off CC_HERM_ENV_ROOT="$d/r6root" CC_HERM_ENV_ALLOWLIST="" CC_HERM_ENV_RULE=off "$SELF" "$d/r6leak" >/dev/null 2>&1 ) || { echo "SELFTEST FAIL: CC_HERM_ENV_RULE=off did not disable rule 6"; fails=1; }

  # ── (a) THE PER-SUITE MEMO (cf440684e0e1). Five cases, and (a1) is the one without which the
  #      other four could every one of them pass vacuously: a memo that never HITS satisfies "no
  #      stale green was served" and "the kill switch works" perfectly, while doing nothing at all.
  #      An empty result from a matcher is not evidence of absence until the matcher is shown able
  #      to return a hit (repo memory: control-must-replay-the-real-artifact, and the standing rule
  #      that every detector needs a positive control on a REAL artifact).
  #
  #      The fixtures live in their OWN git repo because memo_init keys its store on the git common
  #      dir and refuses on a dirty tree — so this exercises the real gate, not a stub, and cannot
  #      write an entry into this checkout's store.
  memo_repo="$d/memorepo"
  mkdir -p "$memo_repo/tests"
  # Multi-line setup() deliberately: setup_bodies() extracts a BLOCK, so the one-line brace form is
  # invisible to it and a fixture written that way reads as a leak — which is how this case first
  # failed, and a fixture the rule cannot see would have made (a1) assert the wrong number forever.
  { echo '#!/usr/bin/env bats'
    echo 'setup() {'
    # shellcheck disable=SC2016  # the fixture must contain the LITERAL text; expansion would break it
    echo '  export HOME="$BATS_TEST_TMPDIR/home"'
    # shellcheck disable=SC2016  # ditto
    echo '  mkdir -p "$HOME"'
    echo '}'
    echo '@test "clean" { true; }'; } > "$memo_repo/tests/zz-memo-clean.bats"
  { echo '#!/usr/bin/env bats'
    echo 'setup() {'
    echo '  :'
    echo '}'
    echo '@test "leak" { true; }'; } > "$memo_repo/tests/zz-memo-leak.bats"
  ( cd "$memo_repo" && git init -q . && git add -A \
      && git -c user.email=selftest@example.invalid -c user.name=selftest commit -q -m fixture
  ) >/dev/null 2>&1
  # Only rule 1 is left on: the other five need roots outside this fixture repo, and a case that
  # must isolate the MEMO should not also be re-testing five rules that have their own cases above.
  memo_run() {  # $1=rule-1 allowlist → combined output; runs inside the fixture repo
    ( cd "$memo_repo" || exit 2
      FIRE_RULE=off; ORPHAN_RULE=off; SEAM_RULE=off; ENV_RULE=off; ADMIT_RULE=off
      lint_dir tests "$1" 2>&1 )
  }
  # (a1) POSITIVE CONTROL — the memo can actually carry a verdict on a real, committed corpus.
  memo_run "zz-memo-leak.bats" >/dev/null 2>&1
  memo_a1="$(memo_run "zz-memo-leak.bats")"
  case "$memo_a1" in
    *"memo — 2 suite verdict(s) carried, 0 proven fresh"*) : ;;
    *) echo "SELFTEST FAIL: the per-suite memo carried NOTHING on a second run of an unchanged committed corpus — every other memo case below can pass vacuously against a memo that never hits"; fails=1 ;;
  esac
  # (a2) A FINDING IS NEVER CACHED. The leak must re-print itself on the second run, from the file.
  #      Both directions are failures: suppressed (the memo swallowed a live violation) and
  #      replayed-from-cache (gate-memo invariant 1 — the operator never reads a cached finding).
  memo_run "" >/dev/null 2>&1
  memo_a2="$(memo_run "")"
  case "$memo_a2" in
    *"LEAK     zz-memo-leak.bats"*) : ;;
    *) echo "SELFTEST FAIL: a suite with a live rule-1 finding did not report it on the memoized run — the memo cached a violation"; fails=1 ;;
  esac
  case "$memo_a2" in
    *"memo — 1 suite verdict(s) carried"*) : ;;
    *) echo "SELFTEST FAIL: the clean suite beside a violating one was not carried — the memo is all-or-nothing per RUN instead of per SUITE"; fails=1 ;;
  esac
  # (a3) THE READ SET BINDS. An allowlist change alters verdicts without touching one byte of any
  #      scanned file or of this script, so a key that fingerprinted only file content would serve
  #      the green earned in (a1) and the leak would vanish. This is the stale-verdict generator the
  #      whole item exists to avoid, asserted rather than argued.
  memo_run "zz-memo-leak.bats" >/dev/null 2>&1
  memo_a3="$(memo_run "")"
  case "$memo_a3" in
    *"LEAK     zz-memo-leak.bats"*) : ;;
    *) echo "SELFTEST FAIL: a green earned under one allowlist was served under a DIFFERENT allowlist — the read set does not bind the memo key"; fails=1 ;;
  esac
  # (a4) THE KILL SWITCH, with (a1) as its positive control: CC_HERM_MEMO=off must leave no memo.
  memo_a4="$( CC_HERM_MEMO=off memo_run "zz-memo-leak.bats" )"
  case "$memo_a4" in
    *"per-suite memo"*) echo "SELFTEST FAIL: CC_HERM_MEMO=off did not disable the per-suite memo"; fails=1 ;;
  esac
  # (a6) A NON-VERDICT IS NEVER CACHED — the veto that matters most, and the one three mutants
  #      showed was the only uncovered branch here. is_hermetic()'s third state returns fail-SAFE
  #      'hermetic' so a dead grep cannot fabricate a LEAK, which means a suite whose predicate
  #      COULD NOT RUN is byte-for-byte indistinguishable from a clean one at the record site.
  #      Without the CHECK_FAILED veto the run below would freeze "I could not check this" into a
  #      permanent green keyed on the file's content, and the real leak beside it would never be
  #      reported again on any tree where those bytes recur — the memo turning "I don't know" into
  #      "green", which is the single thing gate-memo.sh's invariant forbids.
  #      The store is cleared first so the stubbed run is the one that would do the recording.
  #      THE STUB IS NARROW ON PURPOSE. Killing grep outright kills in_allowlist() too, and its own
  #      fail-SAFE ('allowlisted') then makes every suite print a RATCHET line — so the run emits,
  #      the EMIT veto blocks the record, and the case passes for a reason that has nothing to do
  #      with CHECK_FAILED. Verified: under a blanket stub, dropping the CHECK_FAILED veto changed
  #      nothing. Only is_hermetic()'s predicate is failed here — its pattern is the one naming
  #      BATS — so in_allowlist answers normally, the suite emits NOTHING, and the sole thing
  #      standing between a could-not-check and a cached green is the veto this case is for.
  rm -rf "$memo_repo/.git/ship-land-memo" 2>/dev/null
  # shellcheck disable=SC2329  # invoked indirectly — it shadows the predicates' grep inside lint_dir
  ( grep() {
      case " $* " in *BATS*) return 2 ;; esac
      command grep "$@"
    }
    memo_run "" >/dev/null 2>&1 )
  memo_a6="$(memo_run "")"
  case "$memo_a6" in
    *"LEAK     zz-memo-leak.bats"*) : ;;
    *) echo "SELFTEST FAIL: a suite whose predicate COULD NOT RUN was cached as green — a non-verdict became a permanent verdict and the live leak beside it is now invisible"; fails=1 ;;
  esac
  # (a7) THE CROSS-POPULATION TABLE IS IN THE KEY — the case the whole per-file design turns on.
  #      Rules 1-4 and 7 are file-local, so for them a blob key is obviously exact. Rules 5 and 6
  #      are not: they judge a suite against a TABLE extracted from bin+scripts+hooks, a population
  #      no scanned suite belongs to. A key blind to that table would serve a rule-6 green earned
  #      when no tool injected the variable, on a tree where one now does — the suite's bytes never
  #      changed, and the violation would be invisible forever. Found by mutation: dropping
  #      env_table from HERM_READSET left every other memo case green.
  #      THE ROOT PATH IS HELD CONSTANT AND ONLY ITS CONTENTS MOVE. A first attempt used two
  #      different root DIRECTORIES and passed while the mutant stayed green — env_root is in the
  #      read set in its own right, so the keys differed by path and the table was never being
  #      tested at all. Here the table changes because a THIRD file appears in a population the
  #      suite is not part of: rule 6's table is an INTERSECTION (a variable some tool INJECTS and
  #      the named tool READS), so a root holding only the reader yields an empty table and a clean
  #      suite, and dropping the injector in convicts it — with the suite's bytes, the tool it
  #      names, and the root path all byte-identical across the two runs.
  mkdir -p "$memo_repo/tests6" "$d/memo_emptyroot/bin" "$d/memo_emptyroot/scripts" "$d/memo_emptyroot/hooks"
  cp "$d/r6root/bin/zz-panetool" "$d/memo_emptyroot/bin/" 2>/dev/null
  cp "$d"/r6leak/zz-fixture.bats "$memo_repo/tests6/" 2>/dev/null
  ( cd "$memo_repo" && git add -A \
      && git -c user.email=selftest@example.invalid -c user.name=selftest commit -q -m r6fixture
  ) >/dev/null 2>&1
  memo_run6() {  # $1=ENV_ROOT → combined output, rule 6 the only rule left on
    ( cd "$memo_repo" || exit 2
      FIRE_RULE=off; ORPHAN_RULE=off; SEAM_RULE=off; ADMIT_RULE=off
      ENV_RULE=on; ENV_ROOT="$1"; ENV_TABLE_ROOT=""; ENV_ALLOW=""
      lint_dir tests6 "" 2>&1 )
  }
  memo_run6 "$d/memo_emptyroot" >/dev/null 2>&1          # reader only ⇒ empty table ⇒ green earned
  cp "$d/r6root/bin/zz-launcher" "$d/memo_emptyroot/bin/" 2>/dev/null   # the injector arrives
  memo_a7="$(memo_run6 "$d/memo_emptyroot")"             # SAME root path — only its table moved
  case "$memo_a7" in
    *INHERIT*) : ;;
    *) echo "SELFTEST FAIL: a rule-6 green earned under one inherited-value TABLE was served under a table that convicts the same suite — the cross-population read set does not bind the memo key"; fails=1 ;;
  esac
  # (a5) A DIRTY TREE DISABLES IT. memo_init hashes the COMMITTED tree for its population
  #      fingerprint, so a worktree that does not match HEAD is exactly the state in which a cached
  #      verdict could describe bytes nobody ran the check on.
  echo '# dirty' >> "$memo_repo/tests/zz-memo-clean.bats"
  memo_a5="$(memo_run "zz-memo-leak.bats")"
  case "$memo_a5" in
    *"per-suite memo"*) echo "SELFTEST FAIL: the per-suite memo stayed armed on a DIRTY worktree"; fails=1 ;;
  esac
  ( cd "$memo_repo" && git checkout -q -- tests/zz-memo-clean.bats ) >/dev/null 2>&1

  # ── THE EXIT CODE ITSELF, all four combinations. This selftest cannot re-invoke itself to prove
  # its own exit (one run is >2 minutes), so the arm below is a single call to a pure function and
  # THESE are that function's cases — the same call, not a re-implementation of it. The one that
  # matters is (0,1) ⇒ 2: before it, a lost fork left `fails=1` and this script exited 1, which
  # tests/test-hermeticity-lint.bats reads as "the instrument is broken" and postland-verify reads
  # as INSTRUMENT-BROKEN — a clean tree convicted by a busy box.
  # Tested directly rather than through `$?` — the three cases below compare against 1 and 2, which
  # `$?` is the only way to express, but a comparison against 0 is just the command's own status.
  selftest_exit_code 0 0 || { echo "SELFTEST FAIL: a clean run did not exit 0"; fails=1; }
  selftest_exit_code 0 1; [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: a run whose ONLY blemish is a non-verdict did not exit 2 — the third state has no way out of this script"; fails=1; }
  selftest_exit_code 1 0; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a real FAIL did not exit 1"; fails=1; }
  selftest_exit_code 1 1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a real FAIL beside a non-verdict was reported as a non-verdict — absence of evidence suppressed evidence that was present"; fails=1; }

  selftest_exit_code "$fails" "$nonverdict"; sx=$?
  if [ "$sx" -eq 2 ]; then
    echo "test-hermeticity-lint --selftest: ⛔ NON-VERDICT — a predicate could not RUN on this box and NO case failed." >&2
    echo "  This says nothing about the tree or about either allowlist. Re-run when the box is quieter;" >&2
    echo "  do not 'fix' a suite, a ratchet or this lint on the strength of it." >&2
    exit 2
  fi
  if [ "$sx" -eq 0 ]; then
    echo "test-hermeticity-lint --selftest: 128/128 — THE THIRD STATE OF THE REAL-TREE SCAN (case e): a lost fork proved to leave CHECK_FAILED READABLE in the caller's shell (the property a \$( ) around lint_dir destroys, and the whole reason the two exit-2 reasons can be told apart at all) and proved to map to a NON-VERDICT, with a bad ROOT as its paired too-wide control — still exit 2, but CHECK_FAILED clear, so it stays a FAIL and cannot be excused by an abstain that has grown over it; and this script's own exit code proved on all four (fails, nonverdict) combinations, including the one that is the point — no failure beside a non-verdict exits 2, and a real FAIL beside a non-verdict still exits 1, so absence of evidence can never suppress evidence that is present. THE PER-SUITE MEMO: a positive control proving it CARRIES on an unchanged committed corpus (without which every case below it passes vacuously), a live finding re-reported rather than cached in EITHER direction, per-SUITE rather than per-run granularity beside a violating neighbour, the read set proved binding in BOTH of its halves — by changing an allowlist that touches no scanned byte, and by moving the cross-population inherited-value TABLE that rules 5-6 judge against while the suite's own bytes stay identical, a suite whose predicate could not RUN proved never cached (the fail-SAFE third state is indistinguishable from clean at the record site — the only branch three mutants left uncovered), and both OFF states (CC_HERM_MEMO=off, dirty worktree) proved to disarm it. RULE 1 (\$HOME): RED on a new leak + on a stuck ratchet entry, GREEN on hermetic + grandfathered, GREEN on the real tree, LOUD on a bad dir, own-scope blocks INSIDE / advises OUTSIDE for both violation kinds (the PATH form matched against the judged path, a BARE entry matched in any directory, and the SAME basename under a DIFFERENT directory proved NOT to block — the collapse control), NON-VERDICT on an unrunnable check (with and without an own-set). RULE 2 (capacity gate): RED on an unpinned handoff-fire suite + on a per-test pin + on a stuck fire-ratchet entry, GREEN on a setup()-pinned suite + on a grandfathered one + on a suite that never mentions handoff-fire (the scope control) + on one that names handoff-fire ONLY in a comment (the scope half of the prose discipline), RED on a setup() COMMENT that merely names the pin (the prose-match regression), own-scope honoured both ways, NON-VERDICT on an unrunnable fire predicate, and both env seams (CC_HERM_FIRE_ALLOWLIST, CC_HERM_FIRE_RULE=off) proved at the entrypoint. RULE 3 (orphan-close lever): RED on a close-leg suite that inherits LCW_ORPHAN_CLOSE + on a per-test pin + on a stuck orphan-ratchet entry, GREEN on a setup()-pinned suite + on a grandfathered one + on a suite that never drives --close-panes (the scope control) + on one that names it ONLY in a comment (rule 2's scope-half control, asserted here so the twins cannot be hardened one side at a time again), and CC_HERM_ORPHAN_RULE=off proved to actually disable it. RULE 4 (embedded selftests): RED on a selftest naming a CONSTANT scratch path + on one that creates state without mktemp + on a COMMENT that merely names mktemp (the prose-match regression, one rule later) + on a stuck selftest-ratchet entry, GREEN on an mktemp-confined selftest + on a grandfathered one + on a file that ships NO selftest and on a selftest that creates NO state (the two scope controls, without which the rule could be flagging everything), own-scope honoured both ways incl. the path form and its collapse control (the same tool basename under another dir must not block), NON-VERDICT on an unrunnable rule-4 predicate AND on an extractor blind to its own anchor (the calibration-free control that stops a broken extractor reading as clean, with a working anchor as its paired GREEN and as the IFBLOCK shape's coverage), the REAL tree proved clean under the embedded allowlist, and all three env seams (CC_HERM_SELFTEST_ALLOWLIST, CC_HERM_SELFTEST_ROOT, CC_HERM_SELFTEST_RULE=off) proved at the entrypoint. RULE 5 (non-\$HOME seams): RED on an unpinned ABSOLUTE /tmp default (shape 5a) + on a BARE NAME the subject EXECUTES (shape 5b) + on a per-test assignment + on a pinned-but-still-grandfathered suite, GREEN on a setup()-assigned seam + on a grandfathered one + on a suite naming a SEAMLESS tool + on a tool named only in a COMMENT + on a tool whose name merely PREFIXES the seam-bearing one + on a bare-name seam whose holder is never executed (the four scope controls, without which the rule could be firing on everything), NON-VERDICT on an extractor blind to its own seam anchor with a working anchor as its paired GREEN, and all three env seams (CC_HERM_SEAM_ALLOWLIST, CC_HERM_SEAM_ROOT, CC_HERM_SEAM_RULE=off) proved at the entrypoint. RULE 6 (inherited values): RED on a suite whose subject READS a variable this repo INJECTS into every pane it launches + on a per-test unset + on a pin of a variable that merely PREFIXES the unpinned one (the boundary control) + on a pinned-but-still-grandfathered suite, GREEN when the position is taken by \`unset\` (the remedy rule 5's assignment-only predicate REJECTS — this is what makes rule 6 a rule and not a shape of rule 5) or by ASSIGNMENT (rule 3's asymmetry) or by a STATEMENT-TERMINATED unset (the too-narrow trailing boundary inherited from rule 3, found by mutation — its fail direction is a false RED on a compliant suite), on a grandfathered suite, and on the THREE scope controls that carry the whole design: a tool that INJECTS a variable it never reads (scripts/handoff-fire.sh's shape — worth 49 suites), a plain-valued seam that NOTHING injects (the filing's naive rule — worth most of 324), and a tool named only in a COMMENT; NON-VERDICT on an extractor blind to its own anchor with a real copy as its paired GREEN, proving BOTH halves of the intersection at once; and all three env seams (CC_HERM_ENV_ALLOWLIST, CC_HERM_ENV_ROOT, CC_HERM_ENV_RULE=off) proved at the entrypoint. RULE 7 (the capacity-ADMIT gate): RED on a suite driving a capacity-admit caller without closing the gate + on a per-test close + on a setup() COMMENT that merely names the pin + on a closed-but-still-grandfathered suite, GREEN on FORM 1 (CC_ADMIT_GATE=off) + on the COMPLETE FORM 2 (both instrument overrides AND a reserve closure) + on a grandfathered one + on the two scope controls — a suite naming no caller at all, and one naming a caller only inside a SENTENCE it carries as data (the case that proves parameterising the shared strip_prose did not disarm the subtraction); and the one case rule 2 has no analogue for, RED on the TWO-VARIABLE form 2 — the filing's own remedy, which the reserve term (450a47c50) made incomplete two days after it was written and which tests/capacity-admit.bats still runs today (20/20 green ambient, 17/20 under CC_SP_TREES_OVERRIDE=999), so a rule certifying it would mint a false negative on the one suite whose subject IS this gate; own-scope honoured both ways, and both env seams (CC_HERM_ADMIT_ALLOWLIST, CC_HERM_ADMIT_RULE=off) proved at the entrypoint."
    exit 0
  fi
  echo "test-hermeticity-lint --selftest: FAILED — the ratchet does not discriminate."
  exit 1
fi

# CC_HERM_OWN — newline-delimited suite names the caller is answerable for. A PATHED entry
# (`tests/x.bats`, which is what ship-land's `git diff --name-only` produces) is matched against the
# judged path on a component boundary; a BARE entry (`x.bats`) is matched as a basename in any
# directory. See in_own's header for why the two forms are not the same thing (backlog c1a29f8ee045).
# UNSET ⇒ strict whole-tree blocking, exactly as before. SET (including set to EMPTY) ⇒ own-scope,
# where an empty value legitimately means "I change no suite, so nothing may block me". `+set` is
# the only test that separates those; `${CC_HERM_OWN:-}` would collapse them and silently reinstate
# the hard stop for precisely the docs-only land this fixes.
rc_bats=0 rc_self=0
if [ -n "${CC_HERM_OWN+set}" ]; then
  lint_dir "${1:-$ROOT/tests}" "${CC_HERM_ALLOWLIST-$EMBEDDED_ALLOWLIST}" "$CC_HERM_OWN"; rc_bats=$?
else
  lint_dir "${1:-$ROOT/tests}" "${CC_HERM_ALLOWLIST-$EMBEDDED_ALLOWLIST}"; rc_bats=$?
fi

# RULE 4's pass. Its population is the repo's TOOL dirs, so it is driven off $SELFTEST_ROOT and NOT
# off the positional scan dir — a caller that says "judge tests/" (ship-land does exactly that) must
# still have its embedded selftests judged, or the rule is detection rather than a gate.
if [ "$SELFTEST_RULE" = on ]; then
  if [ -n "${CC_HERM_OWN+set}" ]; then
    lint_selftests "$SELFTEST_ROOT" "$SELFTEST_ALLOW" "$CC_HERM_OWN"; rc_self=$?
  else
    lint_selftests "$SELFTEST_ROOT" "$SELFTEST_ALLOW"; rc_self=$?
  fi
fi

# 2 (NON-VERDICT) dominates 1 (violation) dominates 0. A pass that could not RUN must never be
# softened into "your tree is dirty" by the other pass, nor into a green by it — the same
# verdict/non-verdict split lint_dir keeps internally, lifted to the composition of the two.
if [ "$rc_bats" -eq 2 ] || [ "$rc_self" -eq 2 ]; then exit 2; fi
if [ "$rc_bats" -ne 0 ] || [ "$rc_self" -ne 0 ]; then exit 1; fi
exit 0
