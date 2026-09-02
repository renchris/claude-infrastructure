#!/bin/bash
# unattended-path-lint — a RATCHET on bare-name binary resolution along the UNATTENDED paths.
#
# THE CLASS. A bare command name resolves against whatever PATH the caller happens to have. In the
# operator's shell that is a rich PATH with Homebrew on it, so the name always resolves and the code
# always looks right. On a path nobody watches — a launchd job, a hook fired inside a spawned
# session — the same name may not exist, and the failure is a 127 that most call sites never check.
# That is the worst available polarity: GREEN where a human tests it, DEAD where it runs.
#
# It has now recurred five times, each time fixed as an instance:
#   · e6de2e15 — four sites at once (git-worktree-guard lsof, ship-land sysctl, capacity-alarm's
#     other sysctl, cc-authbrowser lsof). All four failed OPEN: a safety refusal that permitted the
#     removal it exists to block, a load shed that never shed, an alarm that went silent, an
#     adoption check that never recognised its own browser.
#   · 86588cbf / bin/cc-kitty-bin — `${CC_TERM_KITTY:-kitty}` in six files. Measured 2026-08-01: a
#     teammate pane close from a hook exited `kitty: command not found` rc=1 and the pane survived
#     3h09m with its 653 MB claude.exe resident; the identical command from the operator's shell
#     closed it, rc=0.
#   · tests/capacity-alarm-launchd-path.bats (2026-07-30) calls itself "the recurrence guard for the
#     CLASS, not just for sysctl" — but it is scoped to ONE script and ONE plist, and within three
#     days the identical defect existed at four other sites. Fixing instances is O(n) forever;
#     asserting the invariant is O(1). That suite is this lint's ancestor and its RED-control shape
#     is reused below.
#
# ── WHY THE POPULATION IS BOTH PLISTS AND HOOKS ──────────────────────────────────────────────────
# The generator item for this lint (cb6701bf2217) specified the trigger as "each plist under
# launchd/ that EXPORTS its own PATH ... read FROM THE PLIST". Measured 2026-08-06, that trigger
# selects almost nothing and MISSES the exposed surface entirely:
#
#   (A) Only ONE plist sets PATH through the <EnvironmentVariables> dict. The rest set it INLINE
#       inside a ProgramArguments string (`/bin/bash -c 'export PATH="$HOME/.claude/bin:..."; exec
#       ...'`) or run under a login shell (`zsh -lc`, inheriting ~/.zprofile) or not at all. A lint
#       reading the plist's PATH *key* therefore judges one job and calls the corpus clean. So the
#       plist half here parses all four shapes — see plist_effective_path().
#
#   (B) Hooks were out of that spec's scope, and hooks are where the class actually survives. No
#       hook hardens PATH (`grep -l 'export PATH=' hooks/*.sh` was EMPTY) and settings.json declares
#       no PATH env, so a hook simply inherits the PATH of the Claude Code process that fired it.
#
# ── WHAT A HOOK'S PATH ACTUALLY IS, AND WHY THIS LINT ASSERTS THE FLOOR ──────────────────────────
# Do not read "hooks run with PATH=/usr/bin:/bin:/usr/sbin:/sbin" as uniformly true — it is not, and
# assuming it was is how the generating report acquired a false instance. Measured 2026-08-06:
# ~/.claude/logs/sessions.log holds 7,420 "MCP Status (attempt" entries, most recent that same day.
# That line is only reachable PAST `command -v claude` in hooks/session-start.sh, and `claude`
# resolves nowhere but an fnm multishell directory — i.e. those hooks ran with the operator's full
# interactive PATH, and the report's claim that this probe "is always skipped" is refuted.
#
# Both observations are true because a hook inherits its CC process's PATH, and that PATH is a
# function of how the session was STARTED — operator shell, spawn script, or launchd. So the honest
# invariant is not "every hook runs stock"; it is that a hook MAY run stock and cannot tell. This
# lint therefore asserts the FLOOR (the stock macOS PATH) rather than the lucky case, for the same
# reason cc-kitty-bin exists: the population you cannot see is the one that breaks.
#
# ── WHY THE bats CORPUS IS A THIRD POPULATION ────────────────────────────────────────────────────
# Measured 2026-08-06: this lint scanned ZERO test files, and tests/*.bats is an unattended
# population by exactly the definition above. com.claude.nightly-regression and
# com.claude.postland-verify both exec a script whose whole job is to run the corpus, under an inline
# `export PATH="$HOME/.claude/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"`.
#
# THAT PATH IS NOT A SUPERSET OF THE STOCK FLOOR. It ADDS Homebrew and DROPS /usr/sbin and /sbin. So
# the corpus fell in a gap no other half covers: the hook half judges against the stock floor (which
# HAS /sbin), and the launchd half follows a plist only as far as the ONE script it names —
# plist_target_scripts() matches `/(scripts|bin|hooks)/` — so a .bats file was in neither population.
#
# What shipped through the gap: tests/cc-queue.bats C12 ("a full render mutates NOTHING") hashed the
# tree before and after through a bare `md5`, and md5 on macOS exists ONLY at /sbin/md5. On the two
# scheduled runners that name is a 127, and under bats' errexit a failed command substitution in an
# assignment kills the test — so C12 was a HARD, reproducible RED on com.claude.postland-verify from
# 2026-08-01 to 2026-08-06 while reading green in every session shell, which carries /sbin. A sibling
# session fixed the instance in parallel (12549d8b — `find | sort` + `cksum`, POSIX and in /usr/bin)
# and measured the consequence harder than this one did; the comment at tests/cc-queue.bats:250 is
# the reference account, including the second, independent defect it also closed: `find | md5` hashed
# the path LIST, so it was structurally blind to the MODIFY verb C12's own clause freezes.
#
# BOTH POLARITIES ARE LIVE, and it is worth being exact about which, because the first draft of this
# comment asserted the wrong one. Inside bats the shape is a loud red. In a plain shell without
# errexit — a hook, a wrapper, any `$( )` whose status nobody reads — the identical line yields "" on
# both sides and `[ "" = "" ]` passes: an instrument reading HEALTHY when dead, the sysctl-loadavg
# shape below that produced this lint's ancestor. What is invariant across both, and all this lint
# asserts, is that the verdict depends on the PATH the runner happens to have and the code cannot
# tell which it got.
#
# The runners are NAMED (CORPUS_RUNNERS) rather than inferred, because both inferences were tried and
# neither is honest. A word-grep for `bats` selects 9 of 22 plist targets, 7 of which only mention it
# in prose; judging the corpus against those PATHs too collapses the effective floor to /usr/bin:/bin
# and reports 25 findings, mostly Homebrew tools the real runners resolve perfectly. COMMAND-position
# detection fails the other way: it sees nightly-regression's `command -v bats` but misses
# postland-verify entirely, whose every call site spells the binary `"$BATS_BIN"`. So the runners are
# listed, and the listing is self-policing in both directions — their PATHs are read from their own
# plists at scan time (widen a runner's PATH and this half stops reporting, with no edit here), and a
# tree that HAS a corpus but none of the named runners exits 2, a NON-VERDICT, never a clean bill.
#
# ── THE RULE ─────────────────────────────────────────────────────────────────────────────────────
# A file on an unattended path may not invoke, at COMMAND POSITION and by BARE NAME, a binary that
# is unreachable on that path's own PATH. Two kinds are reported, deliberately distinguished:
#   bare    — no `command -v` guard anywhere in the file. A miss is a 127 and a fabricated verdict.
#   guarded — the file tests for the binary. It will not crash, but the capability is silently lost,
#             which for a gate or an actuator is failing OPEN.
# Both are findings; the allowlist decides what BLOCKS, exactly as self-path-lint does.
#
# ── WHY A RATCHET ────────────────────────────────────────────────────────────────────────────────
# The corpus carries a small, tractable set today. Grandfathering them BY FILE+BINARY keeps the rule
# free on new code while the existing set is fixed on its own schedule, and the list can only
# SHRINK: fixing a site while leaving its allowlist line is itself RED (a stuck entry), which is
# what stops a ratchet from silently becoming a permanent exemption list.
#
# ── WHY THE SCANNER IS A STATE MACHINE AND NOT A GREP ────────────────────────────────────────────
# Both cheap spellings were tried and both produced a wrong corpus:
#   · A grep for a name after a command-position delimiter reported every binary named inside
#     completion-assert.sh's CA_CMD_RE — a single-quoted REGEX listing cc-backlog|claude|npx|pnpm as
#     PROSE — as four invocations.
#   · A tokenizer that treated a double-quoted string as one opaque token MISSED the highest-severity
#     real site in the corpus, `out="$(shellcheck ...)"` at hooks/task-quality-gate.sh:164, because
#     the `"` swallowed the `$(`. A command substitution INSIDE double quotes is still a command.
# Only the second failure was survivable to find, and only because a known-true site was held back
# as a control. scan_shell() below tracks quote state properly; --selftest pins both shapes.
#
# The scanner runs on /usr/bin/python3 — deliberately, since a lint that forbids depending on a
# non-stock binary must not itself depend on one. /usr/bin/jq and /usr/libexec/PlistBuddy are stock
# for the same reason; there is no yq, no shellcheck, no coreutils here.
#
# Exit: 0 = clean · 1 = violation · 2 = bad usage / unusable scan tree / unrunnable scanner (LOUD,
# never silent-green — a check that could not run has nothing to say about the tree).
#
# Env seams: CC_UNATTENDED_ALLOWLIST overrides the embedded allowlist (used by --selftest) ·
#            CC_UNATTENDED_OWN narrows which findings BLOCK to the caller's own files ·
#            CC_UNATTENDED_INVENTORY overrides the embedded binary inventory (used by --selftest).

set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/$(basename "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "$SELF")/.." 2>/dev/null && pwd -P)" || ROOT=""

STOCK_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
PY="/usr/bin/python3"

# ── THE THREE POPULATIONS, EACH NAMED ONCE ───────────────────────────────────────────────────────
# This lint judges three disjoint file sets (see the header's "WHY THE bats CORPUS IS A THIRD
# POPULATION"), and each is declared here so the collector below and `--print-scope` read the SAME
# declaration rather than two spellings of it.
#
#   HOOK_GLOB           — hook_population's whole-directory glob.
#   PLIST_TARGET_LAYERS — the dirs a launchd plist may execute a script out of. It is what builds the
#                         alternation inside plist_target_scripts' grep/sed, so widening it moves the
#                         matcher and the printed scope in one edit. Kept as a space-separated list
#                         rather than as the regex because a list is what --print-scope needs; the
#                         regex is derived FROM it, never beside it.
#   BATS_GLOB           — bats_population's whole-directory glob.
HOOK_GLOB='hooks/*.sh'
PLIST_TARGET_LAYERS='scripts bin hooks'
BATS_GLOB='tests/*.bats'
# `scripts|bin|hooks`, for the two ERE call sites. Parameter expansion rather than `tr` on purpose:
# this file is itself scanned by the launchd half whenever a plist executes it, and a bare-name
# subprocess here would be the lint minting its own finding.
PLIST_TARGET_ALT="${PLIST_TARGET_LAYERS// /|}"

# ── The ratchet ──────────────────────────────────────────────────────────────────────────────────
# One "<repo-relative-file>:<binary>" per line. Entries are grandfathered SITES, not blanket
# exemptions for the binary: the same binary in a new file is still RED. Delete a line the moment
# its site is fixed — a stuck entry is reported and fails the run.
# WHY 37 AND NOT ZERO. These are the sites measured on 2026-08-06, grandfathered by CLASS so a later
# reader can retire them on evidence rather than guessing:
#   · timeout / gtimeout (12 sites) — almost all are `command -v timeout || command -v gtimeout` with
#     an ELSE that runs the same command unbounded. The bound degrades; the verdict does not change.
#     Both names are listed per site because the guard tries them in turn and either can be the one
#     that resolves.
#   · ~/.claude/bin siblings — cc-backlog, cc-decide, cc-do, cc-blockers, cc-notify, cc-teardown.
#     These sit behind resolver ladders that already prefer an absolute path, so the bare name is the
#     ladder's LAST rung rather than its only one.
#     TWO ROWS WERE DELETED FROM THIS CLASS as scanner artifacts, not as fixes —
#     hooks/completion-assert.sh:cc-backlog and hooks/dispatch-assert.sh:cc-dispatch. Neither file
#     ever invoked those names: every occurrence is a comment, the single-quoted CA_CMD_RE, an
#     absolute-path resolver ladder, or the body of a double-quoted operator message. They were
#     reported because both files build a JSON payload as `"$(jq -cn … --argjson n "$((N+1))" …)"`,
#     and the arithmetic-expansion bug fixed in scan() let those `))` close the ENCLOSING `$(` — so
#     the prose that followed was read as code. Deleting them is the ratchet doing its job: an entry
#     that stops being reported must be removed, whichever end of the detector changed.
#   · claude / agent-browser / npx / ruff — these live only in fnm and framework directories whose
#     names carry a pid, so no fixed prefix can reach them and PATH hardening cannot fix them.
#     bin/cc-claude-bin is the right resolver for `claude`, and the right separate change.
#   · sysctl (postland-verify, qos-census) — ALREADY REMEDIED, 4c58eaf5, by a sibling session working
#     the same class in parallel. sysctl lives in /usr/sbin and both plists' PATHs stop at
#     /usr/bin:/bin, so a scheduled run fed `${x:-0}` and recorded loadavg 0 — an unreadable
#     instrument rendering as the HEALTHY value, the exact shape that produced this lint's ancestor.
#     That session measured the consequence harder than this one did: 859 of 867 qos-census rows
#     carried a blank loadavg. Both sites now resolve /usr/sbin/sysctl absolutely and keep the bare
#     name only as a fallback, so they still appear here as `guarded` — correctly, since the name IS
#     still tried — and their entries stay.
#   · lsof (team-orphan-reaper) — NOT a defect, and the earlier revision of this comment was wrong to
#     call it one. procs_cwd_under() already does `bin=/usr/sbin/lsof` first and only falls back to
#     `command -v lsof`, then returns 2 (UNRESOLVED, never "nobody there") when neither resolves.
#     That is the e6de2e15 remedy already applied, not the defect. It is listed because the bare name
#     is still reachable as a fallback rung — which is what this lint reports, not what it condemns.
#
#     A note on how those two rows got mis-stated together: they were filed as one backlog item on a
#     SOURCE reading, before the call sites around them were read. The sysctl half was real, the lsof
#     half was already fixed, and only reading procs_cwd_under() separated them. Grandfathering by
#     CLASS is what makes that survivable — the entries are correct either way; only the rationale
#     needed the correction.
#
#     Neither is fixed by a PLIST edit here, and that constraint still stands for anything that would
#     be: launchd-parity-lint asserts live `plutil -p` == repo SSOT, so editing a repo plist without
#     the operator's launchctl reload turns that gate RED for every session in the fleet until they
#     act. A plist change and its reload have to land together.
#   · it2 (teammate-auto-shutdown) — `command -v it2 || echo "$HOME/.claude/bin/it2"`. It is not
#     repo-provided (a real file in ~/.claude/bin, not a symlink into bin/), and the guard already
#     carries the ABSOLUTE fallback this lint asks for. Listed because the name is still tried
#     first, not because the site is wrong — it is the exemplar of the correct shape.
#   · bun / cargo (cc-dispatch) — a project-type ladder wrapped in `|| true`, explicitly best-effort
#     ("install failure does NOT fail provisioning"). Genuinely benign.
#   · lsof (tests/cc-teardown-assignee-adopt.bats) — the ONE corpus entry, and it is the exemplar
#     rather than a defect. That suite is the regression guard for the bare-`lsof` class itself: it
#     builds a hostile PATH with every lsof-holding dir removed BY PROBING (path_without_lsof(), so a
#     box that ships lsof in Homebrew is still covered), and the flagged occurrence is its CONTROL
#     asserting `command -v lsof` finds nothing under that PATH. Every place the suite needs the real
#     binary already spells it /usr/sbin/lsof absolutely. It is listed because the bare name is
#     reachable at command position — which is what this lint reports, not what it condemns.
#     (Read the call sites before writing a rationale here: d2300b1b had to correct two of the rows
#     above that were filed from a SOURCE reading, one already fixed in parallel and one never broken.)
# The launchd half's entries are grandfathered for a REASON OF BLAST RADIUS, not of severity. The
# two `sysctl` sites are the same defect that produced this lint's ancestor: sysctl lives in
# /usr/sbin, those two plists' PATHs stop at /usr/bin:/bin, and both call sites feed a `${x:-0}` /
# `${x:-}` default — so a scheduled run records loadavg 0 rather than failing. An unreadable
# instrument rendering as the HEALTHY value is the worst shape available, and it is now the THIRD
# recurrence. They are not fixed HERE because the fix is a plist edit, and launchd-parity-lint
# asserts live `plutil -p` == repo SSOT: editing the repo plist without the operator's launchctl
# reload would turn that gate RED for every session in the fleet until they acted. Filed separately
# so the repo edit and the reload land together.
#
# ── RESTORED 2026-08-29: `scripts/autonomy-sweep.sh:timeout`, retired by a6449cebc and put back the
#    same hour, because ONE SOURCE LINE NAMES TWO BINARIES AND THE RATCHET COUNTS THEM SEPARATELY. ──
# a6449cebc deleted that one row on the ratchet's say-so ("the ratchet says no longer violates") and
# deliberately kept `scripts/autonomy-sweep.sh:gtimeout` beside it, reporting `--selftest 44/44`.
# The tree now runs 46 arms and the 46th is "GREEN on the real tree": with the row gone the bare
# lint reports the site, that arm goes red, and the selftest's failure BLOCKS EVERY LAND IN THIS
# REPO — not just the author's. Measured one-variable, 2026-08-29T07:2xZ, on clean `git archive`
# extractions: a6449cebc^ (109fa07c8) selftest rc 0 / bare rc 0; a6449cebc selftest rc 1 / bare
# rc 1; the commit changed this file only, by exactly one deleted line.
# THE ROW WAS NEVER STALE. autonomy-sweep.sh:158 (and again :505) is
#   TIMEOUT_BIN="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"
# — ONE line naming BOTH bare binaries, so any argument that `timeout` no longer violates applies
# verbatim to `gtimeout`, which that same commit says still violates. The allowlist is keyed on
# (file, binary), so a paired idiom needs a paired pair of rows, and every other file carrying this
# idiom holds both: hooks/lead-crash-watchdog.sh, hooks/notify.sh, hooks/waiting-recycle.sh,
# scripts/lead-supervisor.sh, scripts/watch-claude-code-2118-hold.sh. Deleting one of the two made
# autonomy-sweep.sh the only unpaired member of a five-file population.
# ⚠️ THE REAL DEFECT UNDERNEATH IS STILL OPEN AND IS NOT AN ALLOWLIST QUESTION: on the plist's own
# PATH neither name resolves, TIMEOUT_BIN goes empty, and sweep_bounded()'s guard falls through to
# running the command UNBOUNDED — inside the launchd sweep whose own header calls an unbounded call
# the machine-wide wedge class it exists to prevent. Fixing THAT (resolve absolutely, per
# bin/cc-kitty-bin / bin/cc-claude-bin) retires BOTH rows honestly. Retiring either one alone does
# not, and the ratchet cannot see the difference because it counts names, not lines.
EMBEDDED_ALLOWLIST="$(cat <<'ALLOW'
bin/cc-dispatch:bun
bin/cc-dispatch:cargo
bin/screenshot-to-clipboard.sh:timeout
hooks/anti-deference-nudge.sh:cc-decide
hooks/completion-assert.sh:timeout
hooks/lead-crash-watchdog.sh:cc-teardown
hooks/lead-crash-watchdog.sh:gtimeout
hooks/lead-crash-watchdog.sh:timeout
hooks/teammate-auto-shutdown.sh:it2
hooks/notify.sh:gtimeout
hooks/notify.sh:timeout
hooks/operator-readout.sh:cc-blockers
hooks/operator-readout.sh:cc-do
hooks/post-file-edit.sh:npx
hooks/post-file-edit.sh:ruff
hooks/pre-session-validate.sh:timeout
hooks/session-register.sh:cc-backlog
hooks/session-register.sh:timeout
hooks/session-start.sh:agent-browser
hooks/waiting-recycle.sh:gtimeout
hooks/waiting-recycle.sh:timeout
scripts/autonomy-sweep.sh:gtimeout
scripts/autonomy-sweep.sh:timeout
scripts/lead-supervisor.sh:cc-notify
scripts/lead-supervisor.sh:gtimeout
scripts/lead-supervisor.sh:timeout
scripts/postland-verify.sh:sysctl
scripts/qos-census.sh:sysctl
scripts/qos-census.sh:taskpolicy
scripts/team-orphan-reaper.sh:lsof
scripts/watch-claude-code-2118-hold.sh:gh
scripts/watch-claude-code-2118-hold.sh:gtimeout
scripts/watch-claude-code-2118-hold.sh:timeout
scripts/worktree-gc-infra-run.sh:timeout
tests/cc-teardown-assignee-adopt.bats:lsof
ALLOW
)"

# ── The bats corpus and the jobs that run it ─────────────────────────────────────────────────────
# One launchd plist basename per line. See "WHY THE bats CORPUS IS A THIRD POPULATION" above for why
# this is a list and not a detector. Only their PATHS matter here; both are read live from the plist,
# so this list pins WHO runs the corpus, never WHAT PATH they run it with.
CORPUS_RUNNERS="com.claude.nightly-regression.plist
com.claude.postland-verify.plist"

# ── The binary inventory: an UPWARD ratchet that de-environments the new-finding arm ──────────────
# One binary NAME per line. Every name here was observed, on some box that ran `--emit-inventory`, to
# resolve to an executable FILE. `installed_somewhere` UNIONS this list with today's live probe.
#
# WHY THIS EXISTS. `installed_somewhere` searches the CALLER'S live inherited PATH, and a NO DROPS
# the finding — so before this list, the lint's finding set was a function of the invoker's tool
# inventory rather than of the tree. The ORDERING rule at the three call sites already immunised the
# STUCK-ratchet arm against exactly this (an allowlist entry counts as USED whether or not the binary
# is visible from here), but the NEW-finding arm was left environment-sensitive: a file in the
# AUTHOR'S OWN DIFF whose finding exists only because the landing box installs a binary the author's
# box lacks blocks that author on a red they cannot reproduce. Measured on this tree 2026-08-13:
# `bun`, `cargo`, `ruff` and `agent-browser` are reported under a rich PATH and silently dropped
# under `PATH=/usr/bin:/bin`, and the drop is strictly one-way (nothing appears only on the lean box).
# That is the sibling defect `test-hermeticity-lint.sh` RULE 5 names in its own header: a lint that
# resolves the operator's PATH to reach a verdict is committing the defect it exists to catch.
#
# WHY A UNION AND NOT A NARROWING. The tempting fix — skip the installability filter for files in the
# own-set — was REFUTED BY MEASUREMENT, not by argument. Mutating `installed_somewhere` over the real
# tree: real 35 findings, always-YES 975, always-NO 0. The filter drops 940 of 975 (96.4%); it is the
# load-bearing noise filter, not a nicety, and skipping it floods the author with ~96% noise on their
# own files. A union can only ever ADD a finding relative to today's probe, so unlike a narrowing it
# cannot manufacture a false negative in the direction that matters — a suite silently reading the
# live box. A box missing `gtimeout` now reports it anyway, so the author sees locally what the
# landing box will see.
#
# 🚨 THIS RATCHET ONLY GROWS, which is the opposite direction from EMBEDDED_ALLOWLIST and is why
# there is no stuck-entry check for it. A name that was ever a real binary stays one; retiring a name
# because today's box happens not to install it would restore the very environment-sensitivity this
# list removes. Regenerate with `--emit-inventory`, which UNIONS with what is already here and never
# subtracts — run it on a box with a rich toolchain and paste the output back over this heredoc.
EMBEDDED_BINARY_INVENTORY="$(cat <<'INVENTORY'
afplay
agent-browser
awk
basename
bash
bats
bun
cargo
cat
cc-backlog
cc-blockers
cc-decide
cc-do
cc-idl
cc-notify
cc-sessions
cc-teardown
chmod
cksum
cmp
codesign
cp
curl
cut
date
dd
diff
dirname
du
find
getconf
gh
git
grep
gtimeout
gunzip
gzip
head
hostname
id
it2
jq
kitty
ln
ls
lsof
mkdir
mkfifo
mktemp
mv
nice
node
npm
npx
osacompile
osascript
paste
perl
pgrep
pkill
plutil
pnpm
ps
python3
readlink
rm
rmdir
ruff
say
script
sed
seq
SEQ
sh
shasum
shellcheck
sleep
sort
sqlite3
stat
stty
swift
swiftc
sysctl
tail
tar
taskpolicy
tee
timeout
tmux
touch
tput
tr
uniq
uuidgen
uv
vm_stat
wc
yarn
yes
yq
zsh
INVENTORY
)"

# Is this name a known-real binary by the checked-in inventory? Kept whole-line so `jq` cannot match
# inside `jqx`. Deliberately a global (lint_tree's own `has_line` is local to it) and deliberately
# bash pattern-matching rather than `printf | grep`, which forks once per scanned word.
in_inventory() { # $1=binary
  local inv="${CC_UNATTENDED_INVENTORY-$EMBEDDED_BINARY_INVENTORY}"
  case $'\n'"$inv"$'\n' in *$'\n'"$1"$'\n'*) return 0 ;; esac
  return 1
}

usage() {
  cat >&2 <<'USAGE'
usage: unattended-path-lint.sh [ROOT]        scan a repo root (default: this script's repo)
       unattended-path-lint.sh --selftest    prove the detector still discriminates, both directions
       unattended-path-lint.sh --print-scope name the three populations it judges, as git pathspecs
       unattended-path-lint.sh --list        print the scanned populations and their PATHs, then exit
       unattended-path-lint.sh --emit-inventory [ROOT]
                                             print EMBEDDED_BINARY_INVENTORY unioned with every
                                             scanned word this box resolves — paste it back in.
                                             UNIONS, never subtracts: the inventory only grows.

exit 0 clean · 1 finding · 2 unusable (a NON-VERDICT, never a clean bill)
USAGE
}

die2() { echo "unattended-path-lint: $*" >&2; exit 2; }

# ── The scanner ──────────────────────────────────────────────────────────────────────────────────
# stdin: nothing. argv: shell files. stdout: "<file>\t<line>\t<word>" for every unquoted word in
# command position. Quote state is tracked; `$(...)` and backticks re-open command position even
# inside double quotes; single quotes and heredoc bodies are opaque; comments are dropped.
# ── The language guard ───────────────────────────────────────────────────────────────────────────
# A file whose SHEBANG names python is not shell, and scanning it as shell reads its PROSE as code.
# Measured 2026-08-24 on bin/claude-accounts (4,605 lines, `#!/usr/bin/env python3`): of 62 bare-word
# `claude` occurrences, python's own tokenize classifies 40 as string/docstring, 22 as comment and
# 0 as CODE — most are path segments inside `~/.claude/...` in prose. The two findings it actually
# emitted were `:17`, a docstring quoting `claude auth login`, and `:203`, the literal text
# `def log_event(msg):` — i.e. a python function PARAMETER read as a bare invocation of `msg`. A
# "binary unreachable on PATH" finding that a parameter rename erases was never about a binary.
#
# THE GUARD LIVES HERE, at the one chokepoint all three halves funnel through (hooks :1077, launchd
# targets :1124, bats corpus :1158), and not at the three call sites. A language test that held for
# one population and not the others would be exactly the silent per-population asymmetry this lint
# exists to end — and the file has been bitten by that shape before (see the sed-BRE note above
# plist_target_scripts, where the launchd half scanned NOTHING while reporting a clean corpus).
#
# KEYED ON THE SHEBANG, NEVER ON THE EXTENSION. bin/ ships python wearing no suffix — bin/claude-accounts
# is the motivating case — so an extension test would miss precisely the population that prompted this.
# A file with NO shebang is still scanned: dropping those would silently exempt the 2 tracked
# hooks/*.sh that carry none, which is a widening this guard has no business making.
#
# LATENT, NOT LIVE, and deliberately landed anyway. Censused on this tree at fix time: 0 of the 24
# in-tree launchd targets, 0 of 101 tracked hooks/*.sh and 0 of 536 tests/*.bats carry a python
# shebang, and 0 of the 35 resolvable EMBEDDED_ALLOWLIST sites sit in a python file — so this changes
# no verdict today and cannot strand a ratchet entry. It goes live the moment any plist names a
# python script, and the latent surface is the 50 python-shebang files under bin/ + scripts/.
is_python_shebang() { # $1=file -> 0 when its shebang names a python interpreter
  local first=""
  IFS= read -r first < "$1" 2>/dev/null || return 1
  case "$first" in
    '#!'*python*) return 0 ;;
    *) return 1 ;;
  esac
}

scan_shell() {
  [ -x "$PY" ] || die2 "$PY is not executable — the scanner cannot run (NON-VERDICT)"
  local shell_files=() f
  for f in "$@"; do
    is_python_shebang "$f" && continue
    shell_files+=("$f")
  done
  # Every argument was python. That is a clean "no shell here", not a NON-VERDICT: the caller's
  # population is genuinely empty of the language this scanner reads, and exit 2 would convert a
  # correct abstention into an unusable-tree verdict.
  [ "${#shell_files[@]}" -eq 0 ] && return 0
  "$PY" - "${shell_files[@]}" <<'PY'
import sys

KEYWORDS = {
    "if","then","else","elif","fi","for","while","until","do","done","case","esac","function",
    "select","time","in","return","break","continue","exit","shift","local","declare","typeset",
    "readonly","export","unset","eval","exec","source","set","trap","wait","echo","printf","read",
    "cd","pwd","test","true","false","let","alias","unalias","builtin","command","type","hash",
    "umask","ulimit","jobs","kill","getopts","shopt","enable","mapfile","readarray","pushd","popd",
    "caller","compgen","complete","disown","logout","suspend","times","and","or","not","fg","bg",
}
# Words that KEEP command position open for the token after them. `if`/`while`/`until`/`elif` belong
# here and not in KEYWORDS-that-close: `if command -v claude` is a COMMAND after `if`, and treating
# `if` as closing the position meant every `if command -v <tool>` guard in the corpus went unseen —
# 19 further real sites, including the entire guarded class this lint claims to report.
# `run` is bats' own wrapper and the corpus's dominant idiom — 1,385 `run bash`, 471 `run env`, 164
# `run jq` in tests/*.bats today. Without it here the bats half would be blind to the ONE spelling
# most of its population uses to invoke anything, which is most of the way back to scanning nothing.
# It changes no verdict on the corpus as it stands (measured both ways, 2026-08-06) — it is here so a
# LATER `run <bare-binary>` cannot land unseen. Outside bats the word is rare and harmless: the only
# non-test sites are self-test blocks in bats-shellcheck-lint.sh and cc-announce, where the following
# word is a keyword, a locally-defined function, or a bare word no box installs — all already dropped.
TRANSPARENT = {"then", "else", "do", "elif", "if", "while", "until", "!", "time", "exec",
               "command", "xargs", "builtin", "nohup", "env", "run"}


def scan(text):
    """Yield (lineno, word) for each unquoted command-position word."""
    i, n = 0, len(text)
    line = 1
    at_cmd = True
    dq_depth = 0          # inside "..."
    sub_stack = []        # open $( / ` contexts
    # Open `case` blocks, one entry each: "await_in" -> "label" -> "body" -> "label" ...
    #
    # WITHOUT THIS THE SCANNER READ A CASE STATEMENT EXACTLY BACKWARDS: it reported the LABELS as
    # commands and was BLIND to the BODIES. Both halves are one missing state. A label word ends at
    # `)`, which never opened command position, so the body's first command was never at_cmd — while
    # `|` between two label arms DID reopen it, so the second arm was emitted as a command. Measured
    # on `case "$d" in githooks|launchd) head -1 x | launchd --body ;; *) md5 y ;; esac`: the old
    # scanner emitted `githooks launchd *` (three labels, one a glob) and NOT ONE of `head`,
    # `launchd`, `md5`.
    #
    # The false POSITIVE is what got filed: `githooks|launchd)` reported "`launchd` is unreachable
    # (bare)" and took the land gate red, so tests/deploy-parity.bats:1049 was written as
    # `[ "$d" = githooks ] || [ "$d" = launchd ]` with a comment explaining the detour. Real code
    # contorted around a scanner bug is the visible cost; the invisible one is larger.
    #
    # 🚨 THE ROW'S PREMISE WAS WRONG IN THE SAFE-LOOKING DIRECTION, and it matters. Both the filing
    # and that comment say "the lint already suppresses a plain single-word case label; the
    # ALTERNATION form is the gap." There was never any label suppression. `launchd)` on its own
    # emits identically — verified against this scanner. Single-word labels merely LOOK handled
    # because the usual ones (`githooks`, `start`, `*`) name no installed binary, so
    # installed_somewhere drops them downstream as scanner noise. Any single-word label that happens
    # to name a real binary — `install)`, `test)`, `find)`, `time)` — false-positives just the same.
    # Fixing only the alternation arm would have left that live and looked complete.
    #
    # Corpus delta, measured over tests/*.bats + scripts/*.sh + hooks/*.sh: 11337 -> 10266 emissions.
    # ~1100 removed are labels the downstream predicate was already discarding (`*`, `*[!0-9]*`, `0`,
    # `/*`, `124`, `137`, `claude-*`) — noise this scanner should never have produced. 6 are newly
    # visible because a case BODY is finally read: osascript x2, cat, touch, rm, and one local
    # function. NONE becomes a finding — every one is reachable on STOCK_PATH — so this restores
    # coverage without minting a single new red. A real pipeline is untouched: `head -1 x | launchd`
    # still reports both, because that `|` is not between label arms.
    case_stack = []
    out = []

    while i < n:
        c = text[i]

        if c == "\n":
            line += 1
            i += 1
            if dq_depth == 0:
                at_cmd = True
            continue

        if c in " \t":
            i += 1
            continue

        # comment: only outside quotes and only at a token boundary
        if c == "#" and dq_depth == 0 and (i == 0 or text[i - 1] in " \t\n;|&("):
            while i < n and text[i] != "\n":
                i += 1
            continue

        # line continuation
        if c == "\\" and i + 1 < n:
            if text[i + 1] == "\n":
                line += 1
            i += 2
            continue

        # single quotes are opaque everywhere except inside double quotes (where ' is literal)
        if c == "'" and dq_depth == 0:
            i += 1
            while i < n and text[i] != "'":
                if text[i] == "\n":
                    line += 1
                i += 1
            i += 1
            at_cmd = False
            continue

        if c == '"':
            dq_depth = 1 - dq_depth if dq_depth in (0, 1) else dq_depth
            i += 1
            if dq_depth == 0:
                at_cmd = False
            continue

        # command substitution re-opens command position even inside double quotes
        if c == "$" and i + 1 < n and text[i + 1] == "(":
            # $(( arithmetic )) is NOT a command substitution, and it must be consumed WHOLE — to the
            # matching `))`, counting nesting. Merely stepping over the opening `$((` (the first
            # spelling) left its two closing parens to be read as ordinary `)`, and a `)` POPS
            # sub_stack: so an arithmetic expansion nested inside a command substitution — e.g.
            # `ts="$(date -u -r "$((NOW - age))" ...)"` at tests/cc-inbox-guard.bats:42 — closed the
            # ENCLOSING `$(` early and left dq_depth stuck at 1 for the rest of the file.
            # The damage runs in BOTH directions, which is why it was invisible: while dq_depth is
            # stuck the scanner sees no command positions at all (silent blindness, the vacuous
            # direction), and when a later quote flips it back it reports PROSE as invocations — it
            # named `it2` inside a comment on line 287 and inside a @test title on line 335. A
            # tokenizer that can be desynced by one line is not a corpus this lint can stand on.
            if i + 2 < n and text[i + 2] == "(":
                j, depth = i + 3, 2
                while j < n and depth > 0:
                    if text[j] == "(":
                        depth += 1
                    elif text[j] == ")":
                        depth -= 1
                    elif text[j] == "\n":
                        line += 1
                    j += 1
                i = j
                continue
            sub_stack.append(dq_depth)
            dq_depth = 0
            at_cmd = True
            i += 2
            continue

        if c == "`":
            sub_stack.append(dq_depth)
            dq_depth = 0
            at_cmd = True
            i += 1
            continue

        if c == ")" and sub_stack:
            dq_depth = sub_stack.pop()
            at_cmd = False
            i += 1
            continue

        if dq_depth:
            i += 1
            continue

        # heredoc: skip the body wholesale
        if c == "<" and text.startswith("<<", i):
            j = i + 2
            if j < n and text[j] == "-":
                j += 1
            while j < n and text[j] in " \t":
                j += 1
            q = ""
            if j < n and text[j] in "'\"":
                q = text[j]
                j += 1
            tag = ""
            while j < n and (text[j].isalnum() or text[j] in "_-"):
                tag += text[j]
                j += 1
            if q and j < n and text[j] == q:
                j += 1
            if not tag:
                i += 2
                continue
            # advance to end of this line, then consume until a line that is exactly the tag
            while j < n and text[j] != "\n":
                j += 1
            while j < n:
                j += 1
                line += 1
                k = j
                while k < n and text[k] in " \t":
                    k += 1
                if text.startswith(tag, k):
                    e = k + len(tag)
                    while e < n and text[e] in " \t":
                        e += 1
                    if e >= n or text[e] == "\n":
                        j = e
                        break
                while j < n and text[j] != "\n":
                    j += 1
            i = j
            at_cmd = True
            continue

        # A bare `)` closes a case LABEL and opens its BODY at command position. Gated on the label
        # state, so a subshell's `)` and a `$(`/backtick close (handled above, which owns sub_stack)
        # are unaffected.
        if c == ")" and case_stack and case_stack[-1] == "label":
            case_stack[-1] = "body"
            at_cmd = True
            i += 1
            continue

        # `;;` ends a body and returns to label position. Checked before the single-`;` arm below,
        # which would otherwise consume the first `;` and leave the second to open a command
        # position on the next label.
        if c == ";" and text.startswith(";;", i) and case_stack and case_stack[-1] == "body":
            case_stack[-1] = "label"
            at_cmd = True
            i += 2
            continue

        if c in ";|&(){}":
            if c in ";|&({":
                at_cmd = True
            i += 1
            continue

        if c in "<>":
            # a redirection and its target are not a command
            i += 1
            at_cmd = False
            continue

        # a word
        start = i
        while i < n and text[i] not in " \t\n;|&()<>\"'`#\\":
            i += 1
        word = text[start:i]
        if not word:
            i += 1
            continue

        # ── the case-block state machine ──────────────────────────────────────────────────────────
        # Driven from every word, not only command-position ones: `in` follows the case SUBJECT, so
        # at_cmd is already closed by the time it is read. `case`/`esac`/`in` are all in KEYWORDS and
        # so were never emitted — this reads them for their structure alone.
        if word == "case":
            case_stack.append("await_in")
        elif word == "esac":
            if case_stack:
                case_stack.pop()
        elif word == "in" and case_stack and case_stack[-1] == "await_in":
            case_stack[-1] = "label"
            at_cmd = False
            continue

        # A LABEL word is a pattern, never a command — whichever arm of an alternation it sits in.
        if case_stack and case_stack[-1] == "label":
            at_cmd = False
            continue

        if at_cmd:
            if word in TRANSPARENT:
                at_cmd = True
                continue
            # A FLAG or an env-style assignment belongs to the transparent word before it and must
            # not consume the command position. Without this, `command -v claude` yields `-v` as the
            # command and `claude` is never seen at all — which silently exempted every
            # `command -v <tool>` guard in the corpus, i.e. precisely the "guarded" half this lint
            # claims to report. Same for `env -u VAR cmd` and `FOO=bar cmd`.
            if word.startswith("-") or ("=" in word and not word.startswith("=")):
                at_cmd = True
                continue
            if word not in KEYWORDS:
                out.append((line, word))
            at_cmd = False
        else:
            at_cmd = False

    return out


import re

# A name DEFINED as a function in the same file is not an external binary, however bare it looks.
# Without this the scan reports helpers like `emit` and `log` — and it reports them as MISSING, which
# is the most confusing possible finding, since the definition is a few lines up.
FUNCDEF = re.compile(r"^[ \t]*(?:function[ \t]+)?([A-Za-z_][A-Za-z0-9_:.-]*)[ \t]*\(\)[ \t]*\{?",
                     re.MULTILINE)

# ── SECOND PRODUCER: a bare name hiding in a VARIABLE DEFAULT ────────────────────────────────────
# scan() answers "what word sits at command position", and that is structurally blind to the one
# spelling this repo actually writes. Measured 2026-08-20 on a fixture through the live scanner:
# `${V:-name}`, `${V:=name}` and `${V-name}` all emit NOTHING, while a bare `name` on its own line
# emits normally. The live instance was scripts/assignee-pane-residency.sh's
# `IT2_BIN="${CC_RESIDENCY_IT2_BIN:-it2}"` … `"$IT2_BIN" …`, which sat in the tree for the whole
# life of the defect with `unattended-path-lint.sh` exiting 0 on a clean tree — and the lint only
# ever spoke once a FIX moved the bare name to command position. A detector that reports the remedy
# and not the defect (backlog bfd2e4eaaf2f; memory guard-proxy-fails-in-both-directions).
#
# WHY A SEPARATE PASS AND NOT A CHANGE TO scan(). The command-position machine drops a DOUBLE-QUOTED
# word before a word ever forms, so reaching `"$IT2_BIN"` means editing the quote state itself — on
# a lint that GATES EVERY LAND in this repo, where a widened emission reds every in-flight lander at
# once. This pass adds emissions and removes none, so every verdict scan() produces today is
# bit-identical, and everything downstream (plausible_binary, reachable_on, file_guards, the
# allowlist, the inventory) applies to these words UNCHANGED — no second reporting path to drift.
#
# THE DISCRIMINATOR IS REACHABILITY TO COMMAND POSITION, not the `:-` spelling. A default is only a
# binary reference if something eventually RUNS it. `${1:-}`, `${x:-0}`, `${2:-$ROOT}` and
# `${PS_BIN:-/bin/ps}` are the corpus's dominant shapes and none of them is a bare-name command:
# the first three are excluded by DEFAULT_RE (empty, digit-initial, `$`-bearing), the fourth by its
# slash. What survives must then be shown to reach a command position — either the expansion IS the
# command, or it is assigned to a holder that is one. Without that second half this fires on every
# `${FMT:-json}` in the tree.
VAR_DEFAULT = re.compile(
    r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-|:=|-)([A-Za-z_][A-Za-z0-9_.+-]*)\}")
# `local X=`, `declare -g X=`, `X=`, `X+=` — the holder is the last name before the `=`.
HOLDER = re.compile(r"(?:^|[;&|(]|\b(?:local|declare|typeset|readonly|export)\s+(?:-\w+\s+)*)"
                    r"([A-Za-z_][A-Za-z0-9_]*)\+?=")


def _decomment(line):
    """Blank out single-quoted spans and a trailing # comment. One-sided: when the quote state is
    ambiguous the span is dropped, so this can only ever SILENCE a finding, never invent one."""
    out, i, n, sq = [], 0, len(line), False
    while i < n:
        c = line[i]
        if c == "'":
            sq = not sq
            out.append(" ")
        elif sq:
            out.append(" ")
        elif c == "#" and (i == 0 or line[i - 1] in " \t;|&("):
            break
        else:
            out.append(c)
        i += 1
    return "".join(out)


def scan_var_defaults(text):
    """Yield (lineno, word) for a bare-name default that reaches a command position."""
    lines = [_decomment(l) for l in text.split("\n")]
    body = "\n".join(lines)
    hits = []
    for lineno, line in enumerate(lines, 1):
        for m in VAR_DEFAULT.finditer(line):
            hits.append((lineno, line, m))
    if not hits:
        return []
    out = []
    for lineno, line, m in hits:
        default = m.group(2)
        pre = line[:m.start()].rstrip()
        # (a) the expansion IS the command — bare or double-quoted, at the head of a command.
        direct = re.search(r'(?:^|[;&|]|\$\(|\bthen\b|\belse\b|\bdo\b|\bexec\b|\btime\b)'
                           r'[ \t]*"?$', pre) is not None
        if direct:
            out.append((lineno, default))
            continue
        # (b) the expansion is assigned to a holder that is run somewhere in the file.
        holders = HOLDER.findall(pre)
        if not holders:
            continue
        holder = holders[-1]
        used = re.search(r'(?:^|[;&|]|\$\(|\bthen\b|\belse\b|\bdo\b|\bexec\b|\btime\b)'
                         r'[ \t]*"?\$\{?' + re.escape(holder) + r'\}?"?[ \t]',
                         body, re.MULTILINE)
        if used:
            out.append((lineno, default))
    return out


for path in sys.argv[1:]:
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    local_funcs = set(FUNCDEF.findall(text))
    # One line per (file, word), at its FIRST occurrence. Everything downstream — reachability, the
    # guard scan, installability, the report itself — is a function of (file, word) alone, so a
    # repeat can only re-derive the verdict the first one already produced; the shell loop was
    # already collapsing them, just after paying for them. The bats corpus emits 31,594 words that
    # reduce to 3,912 distinct pairs (hooks: 4,296 → 1,196), and that 8x was most of a 19s run
    # against sibling ratchets that are sub-second. Deduping here rather than in bash keeps the work
    # in the process that already holds the text, and needs no cache in a shell without hashes.
    emitted = set()
    # scan() first, so a name that is ALSO at command position keeps its command-position line
    # number — the more actionable of the two for a reader opening the file.
    for lineno, word in list(scan(text)) + scan_var_defaults(text):
        if word in local_funcs or word in emitted:
            continue
        emitted.add(word)
        print("%s\t%d\t%s" % (path, lineno, word))
PY
}

# A word is only a candidate if it LOOKS like a bare command name: no slash (a path resolves on its
# own), no variable expansion, no assignment, not numeric (redirection operands like `2` reach here).
plausible_binary() {
  case "$1" in
    */*|*'$'*|*=*|*'['*|*'*'*|*'!'*|'') return 1 ;;
    [0-9]*) return 1 ;;
  esac
  case "$1" in
    [A-Za-z_]*) : ;;
    *) return 1 ;;
  esac
  return 0
}

# Reachability is resolved IN-PROCESS, never by forking `env -i sh -c 'command -v'`. That spelling is
# the obvious one and it cost 41s on this corpus — a fork per (file, word) pair, thousands of them —
# against sibling ratchets that are sub-second. A gate nobody can afford to run is a gate that gets
# turned off. `command -v` on a given PATH is exactly "the first executable FILE of that name in one
# of its directories", which is a loop, so this computes the same answer with no process at all.
# No memo table: /bin/bash on macOS is 3.2, which has no associative arrays, and the loop is already
# fast enough that one would buy nothing (0.19s for the whole corpus). `declare -A` here failed LOUDLY
# under 3.2 rather than silently — but the arithmetic that followed it did not, so a cache-shaped
# optimisation nearly turned the scan into a syntax error that still exited non-zero for the wrong reason.
# Expand the variables a PATH string can legitimately contain, as the shell that runs it will.
#
# `$HOME/.claude/bin` maps to the SCANNED TREE'S OWN bin/, not to the operator's real one, because
# ~/.claude/bin is a directory of per-file SYMLINKS into a checkout — whether cc-sessions is present
# there today is a DEPLOY-STATE question, not a fact about the tree. Keying on it made the verdict
# differ between a real and a fixtured $HOME (4 sites flipped), which is the same mistake
# self-path-lint calls out by name: a rule whose answer depends on what is currently symlinked makes
# a file go red or green without changing. Judging against the repo's bin/ is tree-derived, stable,
# and answers the question actually being asked — will this name resolve for the job that runs it.
expand_path_string() { # $1=PATH string, $2=repo root
  local p="$1" root="$2"
  p="${p//\$\{HOME\}/$HOME}"
  p="${p//\$HOME\/.claude\/bin/$root/bin}"
  p="${p//\$HOME/${HOME:-/tmp}}"
  p="${p//\$\{PATH\}/$STOCK_PATH}"
  p="${p//\$PATH/$STOCK_PATH}"
  printf '%s\n' "$p"
}

reachable_on() { # $1=PATH $2=binary
  local d rc=1 oldifs="$IFS"
  IFS=':'
  for d in $1; do
    [ -n "$d" ] || d="."
    if [ -x "$d/$2" ] && [ ! -d "$d/$2" ]; then rc=0; break; fi
  done
  IFS="$oldifs"
  return $rc
}

# Is the binary a real FILE anywhere this box installs one? A word that resolves nowhere is scanner
# noise (a case label, a bare word), not a dependency — reporting it would be a finding nobody can act on.
#
# Deliberately NOT `command -v` in the current shell. The operator's zsh carries functions and
# aliases — `claude` is a shell function, `print` is a zsh builtin — so an interactive `command -v`
# answers "is this a word my shell knows", which is a different question and says yes to things that
# are not binaries at all. An earlier revision used it and reported `emit`, a function defined inside
# the very file being scanned, as a missing binary. Test for an executable FILE only.
installed_somewhere() {
  # Search the inherited PATH for an executable FILE — deliberately NOT `command -v`, which in the
  # operator's zsh also answers yes to functions, builtins and aliases. `claude` is a shell function
  # and `print` is a zsh builtin; an earlier revision used `command -v` and duly reported `emit`, a
  # function defined inside the very file being scanned, as a missing binary. The inherited PATH is
  # searched rather than a fixed prefix list because npx/claude/ruff live in per-shell fnm and
  # framework directories whose names carry a pid — no static list can enumerate them, and dropping
  # them would silently narrow the lint.
  #
  # /usr/sbin:/sbin ARE in the static suffix, and their absence was a real blind spot rather than an
  # oversight of taste. This predicate answers "does this box install such a binary at all", so a NO
  # DROPS the finding — which makes it the one place where a too-narrow PATH removes true positives
  # silently. The inherited PATH is the caller's, and the callers that matter run lean: ship-land's
  # gate PATH carries no /sbin, so `md5` (a /sbin-only stock binary) read as "installed nowhere" and
  # every /sbin-only finding was dropped before it could be reported. That is the lint's own founding
  # example — tests/cc-queue.bats hashing with a bare `md5` that resolves nowhere on either scheduled
  # runner — made invisible to the lint by the environment it is gated from. It surfaced as
  # `--selftest` FAILING 2/23 (cases 14 and 17, both /sbin-only fixtures) for any caller without
  # /sbin, and passing 23/23 for one with it: a detector whose verdict came from the invoker's
  # environment instead of from the tree. These two are stock macOS locations, as static and
  # enumerable as the /usr/local/bin already here — the fnm/pid argument above is why the INHERITED
  # PATH stays in the union, and is not a reason to omit the fixed directories it may lack.
  #
  # UNIONED with the checked-in inventory (see EMBEDDED_BINARY_INVENTORY above), which is what makes
  # this predicate's answer a property of the TREE rather than of the invoker's tool inventory. The
  # inventory arm is tested FIRST because it is a string match and the probe is a stat loop over
  # every PATH entry — and because a name the inventory already knows needs no probe at all.
  in_inventory "$1" && return 0
  reachable_on "${PATH}:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/sbin:/sbin:$HOME/.claude/bin:$HOME/.local/bin:$HOME/bin" "$1"
}

# File-level guard detection. `command -v X` / `type -p X` / `hash X` anywhere in the file means the
# author considered absence; the capability is still lost, but it will not 127.
file_guards() { # $1=file $2=binary
  grep -qE "(command[[:space:]]+-v|type[[:space:]]+-[pP]|hash)[[:space:]]+(--[[:space:]]+)?${2}([[:space:]]|\$|\"|')" "$1" 2>/dev/null
}

# ── The launchd half ─────────────────────────────────────────────────────────────────────────────
# Four shapes, because reading only the EnvironmentVariables key judges ONE job in this corpus.
#
# Read through PlistBuddy, one ProgramArguments element at a time, NOT `plutil -extract ... json`.
# plutil's JSON escapes every `/` as `\/` and every `"` as `\"`, so the obvious extraction
# (`s/.*export PATH="\([^"]*\)".*/\1/p`) silently matches nothing and every inline-PATH plist reports
# as bucket 4 — the near-vacuous verdict this lint was built to end, reproduced in the lint itself.
# It was caught only because --list prints the per-plist PATH and a known inline-PATH job read
# "default". PlistBuddy prints the element raw, which is also what the ancestor suite does.
#
# ── WHY THERE IS A SECOND READER, AND WHY IT IS plistlib AND NOT A PARSER ─────────────────────────
# PlistBuddy ships with macOS and exists nowhere else. Every read below FAILED on a non-Darwin box,
# and each failure is indistinguishable from "the key is absent": `plist_arg_strings` returned an
# empty list, so `plist_effective_path` fell through its four arms to the last one and answered
# STOCK_PATH for EVERY plist in the tree — including the ones whose whole point is an inline
# `export PATH=` that cannot reach Homebrew. That is the near-vacuous verdict this lint was built to
# end, silently reinstated by the absence of one binary, with no message and no non-verdict.
#
# The fallback is python3's `plistlib` — stdlib, an exact XML/binary plist reader, already a hard
# dependency of this script (`PY` is checked with `die2` before the scanner runs) and present at
# /usr/bin/python3 on macOS as well. It is deliberately NOT a sed/grep parse of the XML: the comment
# above records what happened the last time this file read a plist through a text transform, when
# plutil's JSON escaping made the extraction match nothing and every inline-PATH job read "default".
# A reader that is wrong in the SAFE direction is the failure mode, not the safeguard.
#
# PlistBuddy stays FIRST so nothing about a Darwin run changes: same reader, same order, same output.
plist_reader() { # -> stdout: buddy | py ; rc 1 if neither is available
  [ -x /usr/libexec/PlistBuddy ] && { printf 'buddy\n'; return 0; }
  [ -x "$PY" ] && { printf 'py\n'; return 0; }
  return 1
}

plist_arg_strings() { # $1=plist -> one ProgramArguments element per line, unescaped
  local pl="$1" i=0 s
  if [ "$(plist_reader)" = "py" ]; then
    # The 32-element cap is PlistBuddy's, mirrored here so the two readers cannot disagree about a
    # pathological plist. `or []` keeps a missing key an empty list rather than a traceback.
    "$PY" - "$pl" <<'PY' 2>/dev/null
import plistlib, sys
try:
    with open(sys.argv[1], 'rb') as fh:
        d = plistlib.load(fh)
except Exception:
    sys.exit(1)
for s in (d.get('ProgramArguments') or [])[:33]:
    print(s)
PY
    return 0
  fi
  while :; do
    s="$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:$i" "$pl" 2>/dev/null)" || break
    printf '%s\n' "$s"
    i=$((i + 1))
    [ "$i" -gt 32 ] && break
  done
}

plist_env_path() { # $1=plist -> the EnvironmentVariables:PATH string, or empty
  local pl="$1"
  if [ "$(plist_reader)" = "py" ]; then
    "$PY" - "$pl" <<'PY' 2>/dev/null
import plistlib, sys
try:
    with open(sys.argv[1], 'rb') as fh:
        d = plistlib.load(fh)
except Exception:
    sys.exit(1)
v = (d.get('EnvironmentVariables') or {}).get('PATH')
if v:
    print(v)
PY
    return 0
  fi
  /usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:PATH' "$pl" 2>/dev/null || true
}

plist_effective_path() { # $1=plist -> stdout: a PATH string, or the LOGIN_SHELL sentinel
  local pl="$1" p="" args

  # 0. NO READER, NO VERDICT. Falling through to arm 4 with an unreadable plist would answer
  #    STOCK_PATH for a job that declares something else — a fabricated verdict in the safe
  #    direction, which is the one this file's header names as how a lint goes quietly useless.
  plist_reader >/dev/null || die2 "no plist reader: neither /usr/libexec/PlistBuddy nor $PY is executable, so this plist's PATH cannot be read (NON-VERDICT)"

  # 1. EnvironmentVariables:PATH
  p="$(plist_env_path "$pl")" || p=""
  if [ -n "$p" ]; then printf '%s\n' "$p"; return 0; fi

  args="$(plist_arg_strings "$pl")"
  if [ -n "$args" ]; then
    # 2. an inline `export PATH="..."` / `PATH=...` anywhere in ProgramArguments
    p="$(printf '%s\n' "$args" | /usr/bin/sed -n 's/.*export PATH="\([^"]*\)".*/\1/p' | head -1)"
    [ -z "$p" ] && p="$(printf '%s\n' "$args" | /usr/bin/sed -n "s/.*export PATH='\([^']*\)'.*/\1/p" | head -1)"
    if [ -n "$p" ]; then printf '%s\n' "$p"; return 0; fi
    # 3. a LOGIN shell inherits the operator's ~/.zprofile PATH — not assertable from the plist, and
    #    deliberately NOT treated as stock: claiming a floor we cannot read would be a fabricated
    #    verdict in the SAFE direction, which is how a lint goes quietly useless.
    #
    #    Detect it by the -l FLAG, never by the interpreter path. The first spelling here tested the
    #    shell name and so matched the string "/bin/bash" itself — every plist that runs a plain
    #    `/bin/bash -c` was classified LOGIN_SHELL and skipped ENTIRELY, i.e. the largest at-risk
    #    bucket was exempted by the check meant to be conservative. A `-l` appears only as its own
    #    argument or inside a combined flag cluster (-lc, -cl).
    # DRAINED, never `grep -q`: this classifier decides whether a bucket is EXEMPTED, so an
    # inversion re-creates the over-exemption the comment above records. See
    # scripts/pipefail-sigpipe-lint.sh.
    if printf '%s\n' "$args" | grep -E '^-[a-zA-Z]*l[a-zA-Z]*$|^--login$' >/dev/null; then
      printf 'LOGIN_SHELL\n'; return 0
    fi
  fi

  # 4. nothing declared => launchd's own default
  printf '%s\n' "$STOCK_PATH"
}

# NOTE the `sed -E`. The first spelling used BRE with `\|` alternation, which GNU sed accepts and
# BSD sed — the sed on this box — treats as a LITERAL pipe. So the prefix was never stripped, every
# target came back as `$HOME/scripts/foo.sh`, the `[ -f "$root/$HOME/..."]` test failed for all of
# them, and the whole launchd half scanned NOTHING while reporting a clean corpus. It survived a
# full run against the real tree looking exactly like "the plists are fine". Only the plist positive
# control caught it, which is why the generating item made that control mandatory.
plist_target_scripts() { # $1=plist -> repo-relative script paths it executes
  plist_arg_strings "$1" \
    | grep -oE '[A-Za-z0-9_./$-]*/('"$PLIST_TARGET_ALT"')/[A-Za-z0-9_.-]+' \
    | sed -E 's#.*/('"$PLIST_TARGET_ALT"')/#\1/#' \
    | sort -u
}

# A hook that hardens its OWN PATH is judged against what it hardened to — the same courtesy the
# plist half extends to an inline `export PATH=`. Without this the lint would keep reporting a site
# after the prescribed fix was applied, which makes the fix unverifiable and the lint unusable.
# Only assignments in the file's opening section count: a PATH set half way down does not protect
# the calls above it, and treating it as though it did would be a fabricated clean verdict.
file_effective_path() { # $1=file $2=repo root -> stdout: PATH string ('' if it hardens nothing)
  local head p=""
  head="$(/usr/bin/sed -n '1,60p' "$1" 2>/dev/null)"
  p="$(printf '%s\n' "$head" | /usr/bin/sed -n 's/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}PATH="\([^"]*\)".*/\2/p' | tail -1)"
  [ -z "$p" ] && p="$(printf '%s\n' "$head" | /usr/bin/sed -n "s/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}PATH='\([^']*\)'.*/\2/p" | tail -1)"
  [ -n "$p" ] || return 0
  expand_path_string "$p" "${2:-$ROOT}"
}

# ── The hook half ────────────────────────────────────────────────────────────────────────────────
# The population is what settings.json actually fires, not everything in hooks/. A file nobody
# invokes is not on an unattended path, and judging it would inflate the ratchet with dead weight.
#
# The population is EVERY hooks/*.sh in the scanned tree — deliberately NOT the subset named by the
# live ~/.claude/settings.json, which is what this function did first. Intersecting with settings.json
# made the verdict a function of the OPERATOR'S MACHINE rather than of the tree:
#   · under a fixtured $HOME the file is unreadable, so every --selftest fixture scanned an EMPTY
#     population and passed vacuously — the same shape as a hermetic $HOME routing tests into a
#     branch production never takes;
#   · and reading the operator's real settings.json from a test suite is itself the live-state leak
#     that test-hermeticity-lint exists to stop. It caught this, correctly, at the gate.
# Scanning the directory is deterministic, hermetic, and strictly WIDER. A hook that settings.json
# does not currently fire is still a hook, and wiring one up must not be the act that first exposes
# a latent bare-name call.
hook_population() { # $1=root
  # shellcheck disable=SC2086  # HOOK_GLOB is a GLOB and must stay unquoted; ls is what expands it
  ( cd "$1" 2>/dev/null && ls $HOOK_GLOB 2>/dev/null )
}

# ── The bats-corpus half ─────────────────────────────────────────────────────────────────────────
# The population is every tests/*.bats in the scanned tree — the same whole-directory rule the hook
# half uses, and for the same reason: the alternative is a manifest, and a file a manifest forgets is
# still executed by `bats tests/`. Both runners take the DIRECTORY, not a file list.
bats_population() { # $1=root
  # shellcheck disable=SC2086  # BATS_GLOB is a GLOB and must stay unquoted; ls is what expands it
  ( cd "$1" 2>/dev/null && ls $BATS_GLOB 2>/dev/null )
}

# The PATHs the corpus actually runs under: one "<plist>\t<expanded PATH>" line per runner PRESENT in
# the tree. A runner that is missing contributes nothing; the caller decides whether "no runner at
# all" is a skip or a non-verdict, since only it knows whether a corpus exists to judge.
corpus_runner_paths() { # $1=root
  local root="$1" name pl p
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    pl="$root/launchd/$name"
    [ -f "$pl" ] || continue
    p="$(plist_effective_path "$pl")"
    # A login-shell runner inherits the operator's ~/.zprofile PATH, which is not assertable from the
    # plist — same conservative skip the launchd half makes, for the same reason.
    [ "$p" = "LOGIN_SHELL" ] && continue
    printf '%s\t%s\n' "$name" "$(expand_path_string "$p" "$root")"
  done <<< "$CORPUS_RUNNERS"
}

# ── The scan ─────────────────────────────────────────────────────────────────────────────────────
# $1=root  $2=allowlist  $3=own-set (optional; presence carried by arity, see the entrypoint)
lint_tree() {
  local root="$1" allow="${2-}" own="${3-}" have_own="${3+set}"
  [ -n "$root" ] && [ -d "$root" ] || { echo "unattended-path-lint: scan root '$root' is not a directory (NON-VERDICT)" >&2; return 2; }
  [ -d "$root/hooks" ] || [ -d "$root/launchd" ] || { echo "unattended-path-lint: '$root' has neither hooks/ nor launchd/ — nothing this lint governs (NON-VERDICT)" >&2; return 2; }

  local findings=0 blocking=0 used_allow="" report=""
  # `scanned_paths` — every repo-relative file this run actually handed to the scanner. An allowlist
  # row whose path is NOT in here was never exercised, so its unusedness is a fact about THIS RUN's
  # reach and says nothing whatever about the tree. See the stuck branch.
  local scanned_paths=""
  # `still_invoked` — every (path, binary) whose SITE still names that binary at command position,
  # recorded BEFORE any box-dependent filter runs. It is what lets the stuck-ratchet branch below
  # tell the file's own two cases apart, and it exists for the reason the ordering comment in the
  # hook half already gives: "A stuck entry must mean 'this site was FIXED', never 'I could not see
  # the binary from here'." That rule was enforced against `installed_somewhere` and NOT against
  # `reachable_on`, which is the other box probe and sits one line earlier — see the stuck branch.
  local still_invoked=""

  # Newline-delimited membership, tested with bash's own pattern match rather than `printf | grep`.
  # The grep spelling forks once per SCANNED WORD — thousands of forks — and was most of a 16s run
  # against sibling ratchets that are sub-second. Both operands are newline-wrapped so a match is
  # whole-line and `foo` cannot match inside `foobar`.
  has_line() { # $1=haystack $2=exact line
    case $'\n'"$1"$'\n' in *$'\n'"$2"$'\n'*) return 0 ;; esac
    return 1
  }

  emit() { # $1=file $2=line $3=bin $4=kind $5=whichPATH
    local key="$1:$3"
    if has_line "$allow" "$key"; then
      used_allow="$used_allow$key"$'\n'
      return 0
    fi
    findings=$((findings + 1))
    local mark="  "
    if [ -z "$have_own" ] || has_line "$own" "$1"; then
      blocking=$((blocking + 1)); mark="✗ "
    else
      mark="· "
    fi
    report="${report}${mark}${1}:${2}: \`${3}\` is unreachable on ${5} (${4})"$'\n'
  }

  # -- hooks --
  local hooks_list; hooks_list="$(hook_population "$root")"
  if [ -n "$hooks_list" ]; then
    local files=()
    while IFS= read -r f; do [ -n "$f" ] && { files+=("$root/$f"); scanned_paths="$scanned_paths$f"$'\n'; }; done <<< "$hooks_list"
    if [ "${#files[@]}" -gt 0 ]; then
      local out; out="$(scan_shell "${files[@]}")" || return 2
      local seen="" hardened_cache=""
      while IFS=$'\t' read -r f l w; do
        [ -n "$w" ] || continue
        plausible_binary "$w" || continue
        local rel="${f#"$root"/}"
        has_line "$seen" "$rel:$w" && continue
        # The PATH this file will actually run with: its own hardening if it has any, else the floor.
        local tgt="" desc="the stock PATH a hook may inherit"
        case "$hardened_cache" in
          *"|$rel="*) tgt="${hardened_cache#*"|$rel="}"; tgt="${tgt%%|*}" ;;
          *) tgt="$(file_effective_path "$f" "$root")"; hardened_cache="$hardened_cache|$rel=$tgt|" ;;
        esac
        if [ -n "$tgt" ]; then desc="the PATH this hook hardens to"; else tgt="$STOCK_PATH"; fi
        has_line "$still_invoked" "$rel:$w" || still_invoked="$still_invoked$rel:$w"$'\n'
        reachable_on "$tgt" "$w" && continue
        seen="$seen$rel:$w"$'\n'
        # ORDER MATTERS. The allowlist is consulted BEFORE the is-it-installed-anywhere filter, so an
        # entry counts as USED whenever its site still invokes the binary — even on a box where that
        # binary is not installed at all. Filtering first made the ratchet environment-sensitive in
        # the fail-CLOSED direction: strip Homebrew and fnm from PATH and every non-stock finding
        # vanishes, so all eight hook entries read as STUCK and the gate goes RED over a machine's
        # tool inventory rather than over the land. A stuck entry must mean "this site was FIXED",
        # never "I could not see the binary from here".
        if has_line "$allow" "$rel:$w"; then used_allow="$used_allow$rel:$w"$'\n'; continue; fi
        installed_somewhere "$w" || continue
        local kind="bare"; file_guards "$f" "$w" && kind="guarded"
        emit "$rel" "$l" "$w" "$kind" "$desc"
      done <<< "$out"
    fi
  fi

  # -- launchd --
  if [ -d "$root/launchd" ]; then
    local pl
    for pl in "$root"/launchd/*.plist; do
      [ -f "$pl" ] || continue
      local ppath; ppath="$(plist_effective_path "$pl")"
      [ "$ppath" = "LOGIN_SHELL" ] && continue
      # Expand the two variables a wrapper's PATH can legitimately contain, the way the wrapper's own
      # shell will at runtime. `$PATH` inside a launchd wrapper is launchd's DEFAULT PATH — several
      # jobs spell their PATH as `$HOME/.claude/bin:$PATH`, and leaving it literal would test a
      # directory named '$PATH' and report the whole job unreachable.
      ppath="$(expand_path_string "$ppath" "$root")"
      local tgt
      while IFS= read -r tgt; do
        [ -n "$tgt" ] || continue
        [ -f "$root/$tgt" ] || continue
        has_line "$scanned_paths" "$tgt" || scanned_paths="$scanned_paths$tgt"$'\n'
        local out; out="$(scan_shell "$root/$tgt")" || return 2
        local seen=""
        while IFS=$'\t' read -r f l w; do
          [ -n "$w" ] || continue
          plausible_binary "$w" || continue
          has_line "$seen" "$tgt:$w" && continue
          has_line "$still_invoked" "$tgt:$w" || still_invoked="$still_invoked$tgt:$w"$'\n'
          reachable_on "$ppath" "$w" && continue
          seen="$seen$tgt:$w"$'\n'
          # Same ordering rule as the hook half above — allowlist before installability.
          if has_line "$allow" "$tgt:$w"; then used_allow="$used_allow$tgt:$w"$'\n'; continue; fi
          installed_somewhere "$w" || continue
          local kind="bare"; file_guards "$root/$tgt" "$w" && kind="guarded"
          emit "$tgt" "$l" "$w" "$kind" "$(basename "$pl")'s own PATH"
        done <<< "$out"
      done <<< "$(plist_target_scripts "$pl")"
    done
  fi

  # -- the bats corpus, judged against the PATHs of the jobs that run it --
  local bats_list; bats_list="$(bats_population "$root")"
  if [ -n "$bats_list" ]; then
    local runners; runners="$(corpus_runner_paths "$root")"
    if [ -z "$runners" ]; then
      # A corpus with no readable runner is the one state that must NOT read as clean: it is exactly
      # the "scans 0 test files" condition this half was added to end, wearing a green badge.
      echo "unattended-path-lint: '$root' ships tests/*.bats but none of its corpus-runner plists" >&2
      printf '%s\n' "$CORPUS_RUNNERS" | sed 's/^/    /' >&2
      echo "  is present, so the PATH the corpus runs under cannot be read. NON-VERDICT (exit 2)." >&2
      echo "  Fix: update CORPUS_RUNNERS in $SELF to the plists that run the suite today." >&2
      return 2
    fi
    local bfiles=()
    while IFS= read -r f; do [ -n "$f" ] && { bfiles+=("$root/$f"); scanned_paths="$scanned_paths$f"$'\n'; }; done <<< "$bats_list"
    if [ "${#bfiles[@]}" -gt 0 ]; then
      local out; out="$(scan_shell "${bfiles[@]}")" || return 2
      local seen=""
      while IFS=$'\t' read -r f l w; do
        [ -n "$w" ] || continue
        plausible_binary "$w" || continue
        local rel="${f#"$root"/}"
        has_line "$seen" "$rel:$w" && continue
        has_line "$still_invoked" "$rel:$w" || still_invoked="$still_invoked$rel:$w"$'\n'
        # Unreachable on ANY runner's PATH is a finding. A test cannot tell which job fired it, so it
        # has to hold for all of them — the same "MAY run stock and cannot tell" logic as the hook
        # half, applied to a floor that is narrower than stock in the /sbin dimension and wider in
        # the Homebrew one.
        local rname="" rpath="" hit=""
        while IFS=$'\t' read -r rname rpath; do
          [ -n "$rname" ] || continue
          reachable_on "$rpath" "$w" && continue
          hit="$rname"; break
        done <<< "$runners"
        [ -n "$hit" ] || continue
        seen="$seen$rel:$w"$'\n'
        # Same ordering rule as both halves above — allowlist before installability.
        if has_line "$allow" "$rel:$w"; then used_allow="$used_allow$rel:$w"$'\n'; continue; fi
        installed_somewhere "$w" || continue
        local kind="bare"; file_guards "$f" "$w" && kind="guarded"
        emit "$rel" "$l" "$w" "$kind" "$hit's own PATH"
      done <<< "$out"
    fi
  fi

  # -- stuck ratchet entries: a site fixed but never de-listed --
  local stuck=""
  # OWN-SCOPED, as of land-architecture-100p §5 P2 — this branch was the one place in this lint
  # where own-scope was simply not consulted, and it is the arm's largest taxing leak.
  #
  # An allowlist entry goes "stuck" when its site stops violating, and the three ways that happens
  # are: (1) THE AUTHOR fixed it — their file is in their own diff, so it must block them, because
  # the ratchet only shrinks if the person who shrank it also lowers the line; (2) A SIBLING fixed
  # it, or deleted or renamed that file, in a land of their own; (3) NOBODY changed anything and
  # the BOX did — `installed_somewhere` searches the caller's live `$PATH` plus Homebrew, so an
  # entry stops counting as "used" the moment `gtimeout`/`lsof`/`sysctl` becomes unreachable on
  # this machine (see reachable_on). Unscoped, cases 2 and 3 refused EVERY land on the box, named
  # a file the author had never opened, and told them to edit an allowlist that was not theirs —
  # measured on a fixture: rc 1 in all three own-set states, including one that explicitly named a
  # different file. Case 3 is the worst of them, because the tree was never wrong at all.
  #
  # So: a stuck entry BLOCKS when its path is own (or when no own-set was supplied ⇒ strict), and
  # is ADVISORY otherwise. Case 1 — the only case with an author who can act — is unchanged. This
  # is the same treatment self-path-lint already gives its own stuck-ratchet branch.
  #
  # 🚨 CASE 3 IS NOW SEPARATED BY CONSTRUCTION, AND OWN-SCOPE NEVER COULD DO IT. Own-scope answers
  # "is this the author's file", which is the right question for cases 1 and 2 and the WRONG one for
  # case 3: an author whose diff legitimately touches a file the BOX changed under is convicted of a
  # ratchet they did not shrink. Measured 2026-09-01 in a cloud (Linux) venue, on a `git worktree`
  # of origin/main with no local change at all: `bin/cc-dispatch:bun` and `:cargo` read STUCK,
  # because the dispatcher plist's PATH is `$HOME/.claude/bin:/opt/homebrew/bin:/usr/local/bin:
  # /usr/bin:/bin` and this container ships `/usr/local/bin/bun` — reachable HERE, and not on the
  # operator's Mac where bun lives in `~/.bun/bin`. Nothing about the tree differed. The first land
  # to touch `bin/cc-dispatch` from a cloud worker was refused with a verdict that named no defect,
  # and deleting the rows on the ratchet's say-so would have re-broken the gate on the box — which
  # is exactly a6449cebc, whose retraction is written out at the top of this file.
  #
  # THE DISCRIMINATOR IS THE SITE, NOT THE BOX. `still_invoked` holds every (path, binary) whose
  # site still names that binary at command position, recorded before `reachable_on` — so a key in
  # it CANNOT have been fixed by anybody: the bare invocation is right there. That is the file's own
  # invariant ("a stuck entry must mean 'this site was FIXED'") applied to the second box probe. The
  # ordering comment in the hook half enforced it against `installed_somewhere` and stopped one line
  # short of `reachable_on`, which is the other half of the same question.
  #
  # It does NOT weaken case 1. An author who really fixes a site — deletes the call, or resolves it
  # absolutely — removes the word, so the key leaves `still_invoked` and the row blocks exactly as
  # before. What it stops blocking is a row the tree never changed.
  #
  # 🚨 AND CASE 4 — THE RUN NEVER READ THE FILE AT ALL, which is not a case about the tree either.
  # An allowlist row is marked used by the scan of its own file; if that file was never handed to
  # the scanner, the row is unused for a reason that has nothing to do with whether its site still
  # violates. Measured 2026-09-01 on a pristine-trunk worktree: `bin/cc-dispatch` is reached ONLY
  # through `launchd/com.claude.dispatcher.plist`, and `plist_target_scripts` returns EMPTY for it,
  # so the file is in no population, its two rows are never exercised, and they read STUCK.
  #
  # ⚠️ THE CAUSE IS NOT THE PLATFORM — IT IS THAT THE PLIST IS NOT WELL-FORMED XML, and this arm
  # could not say so. Its header comment (line 4) contains `cc-dispatch --once`, and `--` is
  # ILLEGAL inside an XML comment: expat rejects the file at line 4 col 87, so `plist_arg_strings`'
  # python reader exits 1 and yields nothing. Verified by removing that one `-`: the same file then
  # parses and returns its ProgramArguments. PlistBuddy (the Darwin reader) is more lenient, so this
  # is invisible on the operator's box and total on every box that takes the python path — the two
  # readers this file's own header insists "cannot disagree about a pathological plist" do disagree
  # about this one. The plist is NOT fixed here: it is a launchd file (C10), and per the note above
  # `plist_target_scripts` a repo plist edit without the operator's reload turns launchd-parity-lint
  # red fleet-wide. Filed for the operator instead; this branch makes the lint HONEST about it
  # meanwhile, which is the part that does not need the box.
  #
  # A ROW WHOSE FILE WAS NEVER READ CANNOT CONVICT ANYBODY. This is the same shape as the row that
  # found it (backlog e981656df348): a reader that cannot report its own absence is not a reader —
  # here, a scan that could not reach a file reported "that file's allowlist row is stale" rather
  # than "I never looked". Checked FIRST, before both other classes, because it is the only one
  # that is not a claim about the tree at all.
  local stuck_other="" stuck_box="" stuck_unscanned=""
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    has_line "$used_allow" "$key" && continue
    # The allowlist key is `<path>:<binary>`; own-sets hold PATHS, so scope on the path half.
    # `%:*` and not `%%:*` — a path may contain a colon, the binary name may not.
    if ! has_line "$scanned_paths" "${key%:*}"; then
      stuck_unscanned="$stuck_unscanned  $key"$'\n'
    elif has_line "$still_invoked" "$key"; then
      stuck_box="$stuck_box  $key"$'\n'
    elif [ -z "$have_own" ] || has_line "$own" "${key%:*}"; then
      stuck="$stuck  $key"$'\n'
    else
      stuck_other="$stuck_other  $key"$'\n'
    fi
  done <<< "$allow"

  if [ -n "$report" ]; then
    echo "unattended-path-lint: bare-name binaries on unattended paths" >&2
    printf '%s' "$report" >&2
    echo "  Fix: resolve it absolutely (bin/cc-kitty-bin / bin/cc-claude-bin are the precedents), or" >&2
    echo "  harden PATH at the top of the file the way the launchd wrappers already do." >&2
  fi
  if [ -n "$stuck_other" ]; then
    # SURFACED, never blocking: the debt is real and someone should discharge it, but the author
    # standing here is not that someone and refusing them buys nothing. Same disposition every
    # other non-own finding in this lint already gets.
    echo "unattended-path-lint: stuck ratchet entries OUTSIDE this land's diff — advisory, not blocking:" >&2
    printf '%s' "$stuck_other" >&2
    echo "  (whoever fixed or removed those sites owes the allowlist line; it is not this land's.)" >&2
  fi
  if [ -n "$stuck_unscanned" ]; then
    # NON-VERDICT, never blocking and never "stale": this run could not read the file the row is
    # about. Deleting these rows would retire a guard nobody measured — a6449cebc, at the top.
    echo "unattended-path-lint: allowlist rows whose FILE THIS RUN NEVER SCANNED — a non-verdict," >&2
    echo "  not a stuck ratchet. Nothing here READ the file the row is about — commonly a plist" >&2
    echo "  whose ProgramArguments do not parse, so the scripts it runs are in no population:" >&2
    printf '%s' "$stuck_unscanned" >&2
    echo "  Do NOT delete these rows — nothing here measured them. Re-run on the box that owns" >&2
    echo "  those jobs to get a real verdict." >&2
  fi
  if [ -n "$stuck_box" ]; then
    # SURFACED, never blocking, and named for what it is so nobody discharges it by deleting a row.
    # These sites STILL invoke the binary; only this machine's inventory changed. On another box the
    # row is load-bearing, so retiring it here would break the gate there (a6449cebc, at the top).
    echo "unattended-path-lint: allowlist rows unused ON THIS BOX ONLY — the site still invokes the" >&2
    echo "  binary; it is merely reachable on this machine's PATH. Advisory, and NOT a stuck ratchet:" >&2
    printf '%s' "$stuck_box" >&2
    echo "  Do NOT delete these rows to clear this notice — retire the SITE (resolve it absolutely)," >&2
    echo "  which retires the row honestly on every box at once." >&2
  fi
  if [ -n "$stuck" ]; then
    echo "unattended-path-lint: STUCK RATCHET — these sites are allowlisted but no longer violate:" >&2
    printf '%s' "$stuck" >&2
    echo "  Fix: delete their lines from EMBEDDED_ALLOWLIST in $SELF — the ratchet only shrinks." >&2
    return 1
  fi
  [ "$blocking" -gt 0 ] && return 1
  [ "$findings" -gt 0 ] && echo "unattended-path-lint: $findings finding(s), none in this land's own files — advisory." >&2
  return 0
}

# ── --emit-inventory ─────────────────────────────────────────────────────────────────────────────
# Regenerate EMBEDDED_BINARY_INVENTORY. Walks the same three populations lint_tree does — hooks/*.sh,
# tests/*.bats, and the scripts each launchd plist executes — and keeps every plausible command-
# position word this box can resolve to an executable FILE. The result is UNIONED with what is
# already embedded and sorted; nothing is ever dropped, so running this on a lean box is a no-op
# rather than a silent retirement of names a richer box contributed. That one-way property is the
# whole point: it is what stops the inventory from re-acquiring the environment-sensitivity it exists
# to remove.
#
# A superset of what any single arm could ask about is deliberate and harmless — each arm asks
# `installed_somewhere` only about words it scanned from these same files, and a name that resolves
# to a real binary is truthfully a real binary whichever arm asks.
if [ "${1:-}" = "--emit-inventory" ]; then
  root="${2:-$ROOT}"
  [ -n "$root" ] && [ -d "$root" ] || die2 "--emit-inventory: '$root' is not a directory (NON-VERDICT)"
  emit_files=""
  while IFS= read -r f; do [ -n "$f" ] && emit_files="$emit_files$root/$f"$'\n'; done <<< "$(hook_population "$root")"
  while IFS= read -r f; do [ -n "$f" ] && emit_files="$emit_files$root/$f"$'\n'; done <<< "$(bats_population "$root")"
  if [ -d "$root/launchd" ]; then
    for pl in "$root"/launchd/*.plist; do
      [ -f "$pl" ] || continue
      while IFS= read -r tgt; do
        [ -n "$tgt" ] && [ -f "$root/$tgt" ] && emit_files="$emit_files$root/$tgt"$'\n'
      done <<< "$(plist_target_scripts "$pl")"
    done
  fi
  emit_words=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    out="$(scan_shell "$f")" || die2 "--emit-inventory: the scanner failed on $f (NON-VERDICT)"
    while IFS=$'\t' read -r _sf _sl w; do
      [ -n "$w" ] || continue
      plausible_binary "$w" || continue
      emit_words="$emit_words$w"$'\n'
    done <<< "$out"
  done <<< "$emit_files"
  # The probe runs ONCE per distinct name, not once per site — the corpus repeats names heavily.
  kept=""
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    reachable_on "${PATH}:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/sbin:/sbin:$HOME/.claude/bin:$HOME/.local/bin:$HOME/bin" "$w" || continue
    kept="$kept$w"$'\n'
  done <<< "$(printf '%s' "$emit_words" | sort -u)"
  printf '%s%s' "$kept" "${CC_UNATTENDED_INVENTORY-$EMBEDDED_BINARY_INVENTORY}" | grep -v '^$' | sort -u
  exit 0
fi

# ── --list ───────────────────────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--list" ]; then
  [ -n "$ROOT" ] || die2 "cannot resolve repo root"
  # "the whole hooks/ directory", not "settings.json-invoked" — hook_population() stopped
  # intersecting with the live settings.json deliberately (see its comment); this label had not
  # caught up, and a label naming a narrower population than the code scans is the kind of thing a
  # later reader trusts over the code.
  echo "HOOK POPULATION (every hooks/*.sh in the tree), judged against: $STOCK_PATH"
  hook_population "$ROOT" | sed 's/^/  /'
  echo
  echo "LAUNCHD POPULATION (per-plist effective PATH):"
  for pl in "$ROOT"/launchd/*.plist; do
    [ -f "$pl" ] || continue
    printf '  %-46s %s\n' "$(basename "$pl")" "$(plist_effective_path "$pl")"
  done
  echo
  # Printed with its runner PATHs because that is the pair a reader has to see together: the corpus
  # is only as unattended as the jobs that run it, and it was the per-plist PATH line in this very
  # listing that exposed the near-vacuous BSD-sed bug in the launchd half.
  echo "BATS-CORPUS POPULATION ($(bats_population "$ROOT" | grep -c . ) file(s)), judged against:"
  corpus_runner_paths "$ROOT" | while IFS=$'\t' read -r rname rpath; do
    [ -n "$rname" ] || continue
    printf '  via %-42s %s\n' "$rname" "$rpath"
  done
  exit 0
fi

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then usage; exit 0; fi

# ── --selftest ───────────────────────────────────────────────────────────────────────────────────
# Every case proves a RED path FIRES or a GREEN path does NOT. The generating item made a positive
# control mandatory for BOTH halves — "positive control required for both halves or the lint is
# vacuous" — so the plist half is exercised with a real plist fixture, not only the hook half.
# The fixture bodies below are SHELL SOURCE held as data — every `$` in them must reach the
# scanner unexpanded, so SC2016 is the intended spelling for this whole block, not a slip.
# shellcheck disable=SC2016
if [ "${1:-}" = "--selftest" ]; then
  checks=0; fails=0; skips=0
  d="$(mktemp -d)" || die2 "mktemp failed"
  trap 'rm -rf "$d"' EXIT

  expect() { # $1=want $2=got $3=label
    checks=$((checks + 1))
    if [ "$1" != "$2" ]; then echo "SELFTEST FAIL: $3 (want $1, got $2)"; fails=$((fails + 1)); fi
  }

  mk() { # $1=dir-under-d $2=relpath $3=body
    mkdir -p "$d/$1/$(dirname "$2")"
    printf '%s\n' "$3" > "$d/$1/$2"
  }

  # A tree with hooks/ so lint_tree accepts it. No settings.json is readable under this $HOME, so
  # hook_population falls back to the whole directory — the widening direction, asserted below.
  newtree() { mkdir -p "$d/$1/hooks" "$d/$1/launchd"; }

  # ── THE TWO FIXTURE BINARIES, AND WHY NO CASE BELOW MAY NAME A REAL ONE ───────────────────────
  # A finding needs BOTH halves of a conjunction: `installed_somewhere` says the name is a real
  # binary somewhere, AND `reachable_on` says it is NOT on the PATH the job actually runs with. Both
  # halves stat the LIVE FILESYSTEM, so a fixture spelled with a real binary name asks a question
  # about THE BOX RUNNING THE SELFTEST and not about the scanner. Every RED control below then fires
  # only where the author happens not to have that tool installed.
  #
  # THIS IS MEASURED, NOT FEARED. On a Linux box, `apt-get install shellcheck` — which touches no
  # file in this repository — moved this selftest from 11 failures to 14, because three RED controls
  # spelled with `shellcheck` found /usr/bin/shellcheck reachable on STOCK_PATH and stopped firing.
  # Fourteen of 42 cases were decided by the invoker's tool inventory: `tmux`, `yq` and `shellcheck`
  # are Homebrew-only on the operator's Mac and stock on Linux, and `md5` is /sbin-only on macOS and
  # absent from Linux entirely. A detector whose own controls answer to the box cannot certify
  # anything about the tree, and scripts/ship-land.sh gate-reds on this exit code — so off Darwin
  # the arm refused every land, including a docs-only one, with a verdict that named no defect.
  # (backlog f85fce7c26f5: eight cloud dispatches, eight branches, nothing landed.)
  #
  # The idiom that fixes it was already in this file, at cases 20a-21i, with its reasoning written
  # out: `zzunobtainium` is "chosen precisely because no box installs it — the live probe CANNOT be
  # the thing that makes this red". Case 19a says the same thing from the other side: "Only a binary
  # the stock floor CANNOT reach makes the label position load-bearing here" — and then spells the
  # fixture `shellcheck`, which the stock floor reaches on any Linux. Generalised here:
  #
  #   zzunobtainium  vouched for by CC_UNATTENDED_INVENTORY, installed NOWHERE. `installed_somewhere`
  #                  answers yes through the inventory arm alone and `reachable_on` answers no on
  #                  every PATH there is. A RED control spelled with it fires on every box or the
  #                  SCANNER is broken, which is the only thing these cases are entitled to measure.
  #   zzreachable    the same, plus a real executable FILE at $ZR_DIR (inside the sandbox). A GREEN
  #                  control puts $ZR_DIR on the fixture's declared PATH, so "reachable" is a fact
  #                  about the fixture. This also DE-VACUOUSES the green half: cases 11 and 15 used
  #                  to pass off Darwin because their word resolved nowhere and was dropped as
  #                  scanner noise, i.e. for the opposite of the reason they claim to assert.
  #
  # The GREEN controls are converted too, and that is not tidiness. A green case spelled with a name
  # the stock floor reaches can never be reported by any scanner, so it passes on a lint that has
  # stopped scanning altogether — the exact vacuity the RED controls beside them exist to exclude.
  #
  # THE ONE CASE THAT STAYS ENVIRONMENTAL IS CASE 19, and it is gated rather than converted: see it.
  INV_Z="zzunobtainium"
  INV_BOTH="zzunobtainium
zzreachable"
  ZR_DIR="$d/refbin"
  mkdir -p "$ZR_DIR"
  printf '#!/bin/sh\nexit 0\n' > "$ZR_DIR/zzreachable"
  chmod +x "$ZR_DIR/zzreachable"

  # 1. RED — the unguarded shape, and specifically the one a greedy tokenizer MISSED: a command
  #    substitution inside double quotes. If this ever goes green the scanner has regressed to the
  #    version that called task-quality-gate.sh:164 clean.
  newtree t1
  mk t1 hooks/a.sh 'out="$(zzunobtainium foo.sh 2>&1)"'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t1" >/dev/null 2>&1 ); expect 1 "$?" 'a bare binary inside "$( )" was not detected'

  # 2. RED — the plainest shape, bare at line start.
  newtree t2; mk t2 hooks/a.sh 'zzunobtainium kill-pane -t "$p"'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t2" >/dev/null 2>&1 ); expect 1 "$?" 'a bare binary at command position was not detected'

  # 3. GREEN — an absolute path is the fix, and must not be reported. Spelled with the fixture binary
  #    so the case still discriminates: a scanner that stripped the directory would report the tail.
  newtree t3; mk t3 hooks/a.sh 'out="$(/opt/homebrew/bin/zzunobtainium foo.sh)"'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t3" >/dev/null 2>&1 ); expect 0 "$?" 'an absolute path was reported as a violation'

  # 4. GREEN — the false positive that killed the grep version: a binary NAME inside a single-quoted
  #    regex is prose. completion-assert.sh's CA_CMD_RE is the real line this replays.
  newtree t4
  mk t4 hooks/a.sh "CA_CMD_RE='^(cc-backlog|claude|npx|pnpm|zzunobtainium)([[:space:]]|\$)'"
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t4" >/dev/null 2>&1 ); expect 0 "$?" 'a binary name inside a single-quoted regex was reported as an invocation'

  # 5. GREEN — a name in a comment is prose.
  newtree t5; mk t5 hooks/a.sh '# we deliberately do not call zzunobtainium here
true'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t5" >/dev/null 2>&1 ); expect 0 "$?" 'a binary name in a comment was reported'

  # 6. GREEN — a heredoc body is data.
  newtree t6; mk t6 hooks/a.sh 'cat <<'"'"'EOF'"'"'
zzunobtainium
EOF'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t6" >/dev/null 2>&1 ); expect 0 "$?" 'a heredoc body was scanned as code'

  # 7. GREEN — a stock binary is not this lint's business, however bare. `sed` and `awk` are the one
  #    pair that may stay spelled for real: /usr/bin/sed and /usr/bin/awk are on STOCK_PATH on every
  #    box this lint has ever run on, so the case asks the same question everywhere. That is the
  #    property the rest of the fixtures had to be given by construction.
  newtree t7; mk t7 hooks/a.sh 'sed -n 1p "$f" | awk "{print}"'
  ( CC_UNATTENDED_ALLOWLIST="" "$SELF" "$d/t7" >/dev/null 2>&1 ); expect 0 "$?" 'a stock-PATH binary was reported'

  # 8. GREEN — grandfathered by the allowlist, and the entry is USED so it is not stuck.
  newtree t8; mk t8 hooks/a.sh 'zzunobtainium kill-pane'
  ( CC_UNATTENDED_ALLOWLIST="hooks/a.sh:zzunobtainium" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t8" >/dev/null 2>&1 ); expect 0 "$?" 'an allowlisted site still blocked'

  # 9. RED — a STUCK entry: allowlisted but the site is clean. This is the property that stops the
  #    ratchet becoming a permanent exemption list.
  newtree t9; mk t9 hooks/a.sh 'true'
  ( CC_UNATTENDED_ALLOWLIST="hooks/a.sh:zzunobtainium" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t9" >/dev/null 2>&1 ); expect 1 "$?" 'a stuck ratchet entry did not fail'

  # 9a. GREEN — an allowlist row whose FILE THIS RUN NEVER SCANNED is a NON-VERDICT, never stuck.
  #     Case 9 above is its paired RED and the two differ in exactly one thing: there the row names
  #     a file the run DID read and found clean (a real fix, the ratchet must shrink); here it names
  #     a path in no population at all, so nothing measured it. Before this case the two were one
  #     verdict, and the arm told an author to delete a row it had never exercised.
  #
  #     WHY IT IS NOT HYPOTHETICAL (backlog e981656df348, 2026-09-01): `bin/cc-dispatch` is reached
  #     only through launchd/com.claude.dispatcher.plist, whose header comment contains `--` and is
  #     therefore not well-formed XML — the python reader yields nothing, the file lands in no
  #     population, and its two rows read STUCK on a pristine origin/main worktree with no local
  #     change of any kind. That refused the first cloud land to touch the file, naming no defect,
  #     and the instruction it printed ("delete their lines") would have retired a guard that is
  #     load-bearing on the box. Deleting a row on this arm's say-so is a6449cebc exactly.
  newtree t9a; mk t9a hooks/a.sh 'true'
  ( CC_UNATTENDED_ALLOWLIST="bin/never-in-any-population.sh:zzunobtainium" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t9a" >/dev/null 2>&1 ); expect 0 "$?" 'an allowlist row whose file was never scanned was reported as a stuck ratchet'

  # 10. RED CONTROL on the PLIST half — a plist whose own PATH cannot reach the binary, running a
  #     script that calls it bare. Without this the plist half is vacuous, which is exactly the
  #     failure mode the generating item named. The fixture PATH is the stock floor and the binary is
  #     installed nowhere, so "cannot reach" holds on every box rather than on Homebrew-less ones.
  newtree t10
  mk t10 scripts/j.sh 'zzunobtainium eval .a "$f"'
  cat > "$d/t10/launchd/com.test.j.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.test.j</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>-c</string>
    <string>export PATH="/usr/bin:/bin"; exec "\$HOME/scripts/j.sh"</string>
  </array>
</dict></plist>
PLIST
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t10" >/dev/null 2>&1 ); expect 1 "$?" 'the plist half did not fire on an INLINE export PATH (the near-vacuous trigger this lint exists to fix)'

  # 11. GREEN on the plist half — the same script under a plist whose inline PATH DOES reach the
  #     binary. The reaching directory is $ZR_DIR, a real directory holding a real executable inside
  #     this sandbox, standing where /opt/homebrew/bin stood before. That substitution is the whole
  #     point of the case: spelled with a Homebrew binary, it passed off Darwin because the word
  #     resolved NOWHERE and was dropped as scanner noise — green through the filter this case is
  #     supposed to be proving it gets past. Now the word is inventory-vouched, so the only thing
  #     that can make it green is the reachability the fixture declares.
  newtree t11
  mk t11 scripts/j.sh 'zzreachable eval .a "$f"'
  cat > "$d/t11/launchd/com.test.j.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.test.j</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>-c</string>
    <string>export PATH="$ZR_DIR:/usr/bin:/bin"; exec "\$HOME/scripts/j.sh"</string>
  </array>
</dict></plist>
PLIST
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_BOTH" "$SELF" "$d/t11" >/dev/null 2>&1 ); expect 0 "$?" 'a plist whose inline PATH DOES reach the binary was still reported'

  # 11b. RED CONTROL for 11 — the SAME fixture with $ZR_DIR taken off the plist's PATH. Without it,
  #      11 is satisfied by a lint that reports nothing at all, which is the failure every green case
  #      in this file is paired against. It is also the one case that proves $ZR_DIR is what 11 is
  #      resting on: delete the directory from 11's PATH string and this is what 11 becomes.
  newtree t11b
  mk t11b scripts/j.sh 'zzreachable eval .a "$f"'
  cat > "$d/t11b/launchd/com.test.j.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.test.j</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>-c</string>
    <string>export PATH="/usr/bin:/bin"; exec "\$HOME/scripts/j.sh"</string>
  </array>
</dict></plist>
PLIST
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_BOTH" "$SELF" "$d/t11b" >/dev/null 2>&1 ); expect 1 "$?" 'the reachable fixture binary went unreported when the declared PATH could NOT reach it'

  # 12. LOUD — a non-verdict must never read as clean.
  ( CC_UNATTENDED_ALLOWLIST="" "$SELF" "$d/nope" >/dev/null 2>&1 ); expect 2 "$?" 'a missing scan root did not exit 2'
  mkdir -p "$d/bare"
  ( CC_UNATTENDED_ALLOWLIST="" "$SELF" "$d/bare" >/dev/null 2>&1 ); expect 2 "$?" 'a root with neither hooks/ nor launchd/ did not exit 2'

  # 13. own-scope: a finding OUTSIDE the own-set is advisory (exit 0); INSIDE it blocks (exit 1).
  #     Set-but-empty must not collapse to "unset" — that would silently reinstate the hard stop.
  newtree t13; mk t13 hooks/a.sh 'zzunobtainium kill-pane'
  ( CC_UNATTENDED_OWN="hooks/a.sh" CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t13" >/dev/null 2>&1 ); expect 1 "$?" 'own-scope did not block on a file INSIDE the own-set'
  ( CC_UNATTENDED_OWN="hooks/other.sh" CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t13" >/dev/null 2>&1 ); expect 0 "$?" 'own-scope blocked on a file OUTSIDE the own-set'
  ( CC_UNATTENDED_OWN="" CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t13" >/dev/null 2>&1 ); expect 0 "$?" 'own-scope set-but-empty blocked'
  ( unset CC_UNATTENDED_OWN; CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t13" >/dev/null 2>&1 ); expect 1 "$?" 'own-scope UNSET did not block'

  # A runner plist for the bats-corpus half. The NAME must be one of CORPUS_RUNNERS, and that
  # coupling is deliberate: rename the real plist without updating the list and case 18's real-tree
  # run goes NON-VERDICT rather than quietly green.
  mkrunner() { # $1=dir-under-d $2=PATH string
    cat > "$d/$1/launchd/com.claude.nightly-regression.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.claude.nightly-regression</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>-c</string>
    <string>export PATH="$2"; exec "\$HOME/scripts/nightly-regression.sh" --run</string>
  </array>
</dict></plist>
PLIST
  }

  # 14. RED CONTROL on the BATS-CORPUS half — the exact shape that shipped. A bare unreachable binary
  #     in a test, under a runner whose inline PATH stops at /bin. Before this half existed the lint
  #     scanned ZERO test files and called this tree clean, which is how tests/cc-queue.bats C12
  #     hashed with a `md5` that resolves nowhere on either scheduled runner. The fixture used to be
  #     spelled `md5` after that instance; `md5` is /sbin-only on macOS and absent from Linux
  #     ENTIRELY, so off Darwin `installed_somewhere` dropped it as noise and this control went
  #     silent — a RED case whose polarity was set by the operating system it ran on.
  newtree t14; mkrunner t14 "/usr/bin:/bin"
  mk t14 tests/a.bats 'before="$(find . | sort | zzunobtainium)"'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t14" >/dev/null 2>&1 ); expect 1 "$?" 'the bats-corpus half did not fire on a bare unreachable binary'

  # 15. GREEN on the same half — the identical corpus file under a runner whose PATH DOES reach the
  #     binary. Proves the half discriminates on the runner's PATH and not merely on the population,
  #     which an always-red control could not tell apart. The reaching directory is $ZR_DIR for the
  #     reason case 11 gives: spelled `md5` with a /sbin-carrying PATH, this passed off Darwin
  #     because the word resolved nowhere and was dropped — never because the PATH reached it.
  newtree t15; mkrunner t15 "/usr/bin:/bin:$ZR_DIR"
  mk t15 tests/a.bats 'before="$(find . | sort | zzreachable)"'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_BOTH" "$SELF" "$d/t15" >/dev/null 2>&1 ); expect 0 "$?" 'a corpus binary reachable on the runner PATH was still reported'

  # 16. LOUD — a corpus with no runner plist present is a NON-VERDICT, never a clean bill. Without
  #     this, deleting or renaming a runner silently restores the scans-nothing state with a green
  #     badge on it: the failure this whole half exists to end.
  newtree t16
  mk t16 tests/a.bats 'before="$(find . | sort | zzunobtainium)"'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t16" >/dev/null 2>&1 ); expect 2 "$?" 'a corpus with no runner plist did not exit 2'

  # 17. RED through bats' own `run` wrapper — the corpus's dominant idiom (1,385 `run bash` alone).
  #     Without "run" in TRANSPARENT the scanner reports `run` itself, which no box installs so it is
  #     dropped, and the binary after it is never seen — leaving the half blind to the spelling most
  #     of its population uses. This case fails on that revision and passes on this one.
  newtree t17; mkrunner t17 "/usr/bin:/bin"
  mk t17 tests/a.bats 'run zzunobtainium -q "$f"'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t17" >/dev/null 2>&1 ); expect 1 "$?" 'the bats `run` wrapper hid a bare binary from the scanner'

  # 17b. THE INVARIANCE CASE — the SAME fixture under a deliberately hostile CALLER PATH must return
  #      the SAME verdict. `installed_somewhere` searches the inherited PATH and a NO there DROPS the
  #      finding, so a lean caller silently deletes true positives: ship-land's gate PATH carries no
  #      /sbin, and cases 14/17 — then spelled `md5` — duly reported "want 1, got 0" on every land
  #      while passing for an interactive shell that had it.
  #
  #      WHAT IT ASSERTS CHANGED WITH THE FIXTURE, AND THE NOTE IS THE POINT. It used to pin one
  #      REPAIR: /usr/sbin:/sbin joining the static suffix, so that a /sbin-only binary survived a
  #      /sbin-less caller. Vouching the fixture through the inventory makes the caller's PATH
  #      irrelevant BY CONSTRUCTION — `in_inventory` returns before the probe is reached — so the
  #      case now pins the PROPERTY that repair was serving, which is the one the header claims:
  #      the verdict comes from the tree, never from whoever invoked it. Case 17c below is what still
  #      pins the static suffix itself, on the population where it is load-bearing.
  ( PATH="/usr/bin:/bin" CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t17" >/dev/null 2>&1 )
  expect 1 "$?" 'a hostile caller PATH changed the verdict on an unchanged tree'

  # 17c. THE STATIC SUFFIX, pinned hermetically — the arm 17b used to carry. A binary the inventory
  #      does NOT vouch for, absent from the caller's PATH and from STOCK_PATH, installed ONLY in
  #      $HOME/.local/bin — one of the fixed directories `installed_somewhere` appends. The finding
  #      can therefore be reached by exactly one route, and drops the moment that suffix narrows.
  #      $HOME is redirected into the sandbox for this one invocation, so the case writes nothing
  #      outside it and reads the same on a box where /sbin is unwritable (every macOS since SIP).
  newtree t17c; mk t17c hooks/a.sh 'zzsuffixonly --check "$f"'
  mkdir -p "$d/hm17c/.local/bin"
  printf '#!/bin/sh\nexit 0\n' > "$d/hm17c/.local/bin/zzsuffixonly"
  chmod +x "$d/hm17c/.local/bin/zzsuffixonly"
  ( HOME="$d/hm17c" PATH="/usr/bin:/bin" CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="somethingelse" "$SELF" "$d/t17c" >/dev/null 2>&1 )
  expect 1 "$?" 'a binary installed ONLY in a static-suffix directory was dropped as scanner noise'

  # 17d. GREEN CONTROL for 17c — identical in every respect except that the binary is not installed
  #      at all. Without it, 17c would be satisfied by an `installed_somewhere` that had stopped
  #      filtering, which is the failure case 20b names for the inventory arm.
  newtree t17d; mk t17d hooks/a.sh 'zzsuffixonly --check "$f"'
  mkdir -p "$d/hm17d/.local/bin"
  ( HOME="$d/hm17d" PATH="/usr/bin:/bin" CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="somethingelse" "$SELF" "$d/t17d" >/dev/null 2>&1 )
  expect 0 "$?" 'a word installed nowhere and vouched for by nothing was reported as a finding'

  # 17e. THE /sbin ARM, kept EXACTLY as it was and gated on the box that can answer it. 17c pins the
  #      static suffix through $HOME/.local/bin, which is writable inside the sandbox; `/usr/sbin` and
  #      `/sbin` are not writable on any macOS since SIP, so the only way to assert them is with a
  #      binary the OS already put there. `md5` is that binary, it is /sbin-only, and it is NOT in
  #      EMBEDDED_BINARY_INVENTORY — so on Darwin this finding survives a /sbin-less caller through
  #      the static suffix and through nothing else, which is the original assertion verbatim.
  #      Off Darwin `md5` exists nowhere at all, which is why this case USED to report "want 1, got
  #      0" on every Linux box and take the whole gate red. Restoring it as a skip rather than
  #      deleting it is the point: the coverage is not lost, it is scoped to where it is a fact.
  if [ "$(uname -s 2>/dev/null || echo unknown)" = "Darwin" ]; then
    newtree t17e; mkrunner t17e "/usr/bin:/bin"
    mk t17e tests/a.bats 'run md5 -q "$f"'
    ( PATH="/usr/bin:/bin" CC_UNATTENDED_ALLOWLIST="" "$SELF" "$d/t17e" >/dev/null 2>&1 )
    expect 1 "$?" 'a caller PATH without /sbin silently dropped a /sbin-only finding'
  else
    skips=$((skips + 1))
    echo "unattended-path-lint --selftest: SKIP (/sbin static-suffix arm) — needs a /sbin-only stock binary (md5), which exists on Darwin only. Case 17c pins the same suffix hermetically through \$HOME/.local/bin."
  fi

  # 18. GREEN — prose AFTER an arithmetic expansion nested in a command substitution. This replays
  #     hooks/dispatch-assert.sh:222-225 in two lines: `$((` used to be stepped over without a push,
  #     so its `))` closed the enclosing `$(`, dq_depth stuck at 1, and the operator message below it
  #     was read as code. It is a GREEN case because the visible symptom was a FALSE POSITIVE — it
  #     reported `cc-dispatch` and `cc-backlog` out of prose, and two allowlist rows were minted to
  #     silence them. The silent half was worse: while dq_depth is stuck the scanner sees no command
  #     positions at all. VERIFIED TO DISCRIMINATE — on the pre-fix scanner this fixture reports the
  #     binary from inside the message; the `(` before it is what re-opens command position, which is
  #     why a fixture without one passes on both revisions and proves nothing. The word is the
  #     fixture binary rather than `tmux` so that "would have been reported" stays true on a box
  #     where /usr/bin/tmux exists — otherwise this case is green on a scanner that reports nothing.
  newtree t18
  mk t18 hooks/a.sh 'payload="$(jq -cn --argjson n "$((N+1))" x)"
reason="see \`x\` (zzunobtainium kill-pane) now"'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t18" >/dev/null 2>&1 ); expect 0 "$?" 'prose after a nested $(( )) was reported as an invocation (the quote machine desynced)'

  # 19a. GREEN — a case LABEL is a pattern, not a command, in EITHER arity. The filed symptom was
  #      `githooks|launchd)` reporting "`launchd` is unreachable (bare)", which took the land gate
  #      red and made tests/deploy-parity.bats:1049 write `[ "$d" = githooks ] || [ "$d" = launchd ]`
  #      with a comment explaining the detour.
  #      🚨 BOTH ARITIES ARE ASSERTED BECAUSE THE FILING'S PREMISE WAS WRONG. It, and that comment,
  #      say the single-word label "is already suppressed" and only the ALTERNATION form leaks.
  #      Nothing suppressed either: `launchd)` alone emitted identically. Single-word labels merely
  #      LOOK handled because the usual ones (`githooks`, `start`, `*`) name no installed binary and
  #      installed_somewhere drops them downstream — so any label that happens to name a real binary
  #      (`install)`, `test)`, `find)`, `time)`) false-positived just the same. A fix scoped to the
  #      alternation arm would have left that live and looked complete, which is why the one-arm
  #      fixture is here and not folded into the two-arm one.
  #      THE LABEL WORDS ARE THE FIXTURE BINARY, NOT the `launchd` of the filed symptom, and that is
  #      the difference between a case and a decoration. This half is judged against the STOCK floor,
  #      where /usr/sbin/launchd and /usr/bin/osascript both resolve — so a fixture spelled with the
  #      real symptom's words is GREEN whether or not the label state exists, and proves nothing.
  #      Written that way first and caught by mutation: neutering the state left it passing. Only a
  #      binary the stock floor CANNOT reach makes the label position load-bearing here.
  #      IT WAS SPELLED `shellcheck` FOR THAT REASON AND THE REASON DID NOT TRAVEL: shellcheck is
  #      Homebrew-only on the operator's Mac and stock at /usr/bin on Linux, so on Linux this case
  #      re-acquired exactly the vacuity the paragraph above rules out — and the mutation that once
  #      caught it would no longer. `zzunobtainium` is the property the paragraph was reaching for,
  #      stated as a fact about the fixture instead of a fact about one box's package manager.
  newtree t19a
  mk t19a hooks/a.sh 'case "$1" in
  githooks|zzunobtainium) : ;;
  zzunobtainium) : ;;
esac'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t19a" >/dev/null 2>&1 ); expect 0 "$?" 'a case LABEL (one-arm or alternation) was reported as an invocation'

  # 19b. RED on the SAME shape — the case BODY is still read. This is the half that makes 19a mean
  #      something, and it is not symmetry for its own sake: the missing state made the scanner wrong
  #      in BOTH directions at once, and the silent direction was the worse one. A label ends at `)`,
  #      which never opened command position, so the body's first command was never at_cmd — every
  #      bare binary invoked inside any `case` body was INVISIBLE to this lint for its whole life.
  #      Measured on the old scanner, this fixture reports nothing at all.
  newtree t19b
  mk t19b hooks/a.sh 'case "$1" in
  githooks|launchd) zzunobtainium foo.sh ;;
esac'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t19b" >/dev/null 2>&1 ); expect 1 "$?" 'a bare binary inside a case BODY was not detected'

  # 19c. RED — a REAL pipeline is untouched. The fix turns `|` transparent only BETWEEN LABEL ARMS;
  #      an ordinary `foo | bar` must still put `bar` at command position, or 19a would have been
  #      bought by blinding the scanner to every piped invocation in the tree.
  newtree t19c
  mk t19c hooks/a.sh 'head -1 x | zzunobtainium -'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t19c" >/dev/null 2>&1 ); expect 1 "$?" 'a bare binary after a real pipe was not detected'

  # 20a. RED — a bare binary that resolves NOWHERE on this box is reported anyway when the checked-in
  #      inventory vouches for it. This is the case the union arm exists for: on the AUTHOR'S box the
  #      binary is absent, on the LANDING box it is present, and before the inventory the author got
  #      a green their landing would turn red. `zzunobtainium` is chosen precisely because no box
  #      installs it — the live probe CANNOT be the thing that makes this red, so the case can only
  #      pass through `in_inventory`. Revert the `in_inventory "$1" && return 0` line and this fails.
  newtree t20a; mk t20a hooks/a.sh 'zzunobtainium --check "$f"'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="zzunobtainium" "$SELF" "$d/t20a" >/dev/null 2>&1 )
  expect 1 "$?" 'a binary vouched for by the inventory but absent from this box was not detected'

  # 20b. GREEN — the CONTROL that stops 20a being vacuous. Same fixture, same PATH, inventory that
  #      does NOT list the word: it must still be dropped as scanner noise. Without this pair, a
  #      change that simply stopped filtering on installability at all would pass 20a and look like
  #      the fix, while flooding every author with the 96.4% of findings the filter exists to drop.
  newtree t20b; mk t20b hooks/a.sh 'zzunobtainium --check "$f"'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="somethingelse" "$SELF" "$d/t20b" >/dev/null 2>&1 )
  expect 0 "$?" 'a word no box installs and no inventory vouches for was reported as a finding'

  # 20c. GREEN — whole-line membership. `zzunobtainium` must not be vouched for by an inventory that
  #      merely CONTAINS it as a substring, or the union arm would silently vouch for every name
  #      sharing a prefix with a real binary.
  newtree t20c; mk t20c hooks/a.sh 'zzunobtainium --check "$f"'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="zzunobtainiumx" "$SELF" "$d/t20c" >/dev/null 2>&1 )
  expect 0 "$?" 'the inventory matched a name as a SUBSTRING rather than a whole line'

  # ── 21. THE VARIABLE-DEFAULT CLASS (backlog bfd2e4eaaf2f) ──────────────────────────────────────
  # Every 21x case below was measured RED-first against the pre-fix scanner: all three spellings
  # exited 0 (silent) while the bare-name control on the same fixture exited 1, which is a detector
  # reporting the REMEDY and not the DEFECT. The live instance was
  # scripts/assignee-pane-residency.sh's `IT2_BIN="${CC_RESIDENCY_IT2_BIN:-it2}"` — invisible for
  # the whole life of the defect, and it spoke only once a fix moved `it2` to command position.
  # `zzunobtainium` is the inventory-vouched word cases 20a-20c already use, so these arms test the
  # SCANNER and inherit a settled answer for everything downstream of it. INV_Z is now declared once
  # at the top of this block, with the two fixture binaries, because every case above uses it too.

  # 21a/b/c. RED — one per spelling. Separate fixtures, because a single file would let ONE working
  #          spelling carry the other two (memory: per-site-mutation-attributes-coverage).
  newtree t21a; mk t21a hooks/a.sh 'Z="${CC_Z_BIN:-zzunobtainium}"
"$Z" --check "$f"'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t21a" >/dev/null 2>&1 )
  expect 1 "$?" 'a bare binary in a ${VAR:-name} default was not detected'

  newtree t21b; mk t21b hooks/a.sh 'Z="${CC_Z_BIN:=zzunobtainium}"
"$Z" --check "$f"'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t21b" >/dev/null 2>&1 )
  expect 1 "$?" 'a bare binary in a ${VAR:=name} default was not detected'

  newtree t21c; mk t21c hooks/a.sh 'Z="${CC_Z_BIN-zzunobtainium}"
"$Z" --check "$f"'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t21c" >/dev/null 2>&1 )
  expect 1 "$?" 'a bare binary in a ${VAR-name} default was not detected'

  # 21d. RED — the expansion IS the command, with no holder variable at all.
  newtree t21d; mk t21d hooks/a.sh '"${CC_Z_BIN:-zzunobtainium}" --check "$f"'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t21d" >/dev/null 2>&1 )
  expect 1 "$?" 'a bare-name default AT command position was not detected'

  # 21e. GREEN — THE TOO-WIDE CONTROL THAT MATTERS MOST, and the reason this pass is gated on
  #      reachability rather than on the `:-` spelling. An ABSOLUTE default is the FIX for this
  #      class (it is what both site fixes in this land use), so a pass that reported it would
  #      forbid its own remedy — the both-directions failure of memory
  #      guard-proxy-fails-in-both-directions. `PS_BIN=${CC_RESIDENCY_PS_BIN:-/bin/ps}` is the live
  #      neighbour this is modelled on, sitting one line below the defect it must not resemble.
  newtree t21e; mk t21e hooks/a.sh 'Z="${CC_Z_BIN:-/opt/homebrew/bin/zzunobtainium}"
"$Z" --check "$f"'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t21e" >/dev/null 2>&1 )
  expect 0 "$?" 'an ABSOLUTE default was reported — the pass forbids its own remedy'

  # 21f. GREEN — a default that no one ever RUNS is not a binary reference. This is the arm that
  #      keeps the pass off the corpus's dominant shapes; `${FMT:-json}`, `${MODE:-auto}` and every
  #      other value-shaped default live here, and without it the lint reds the whole tree at once.
  newtree t21f; mk t21f hooks/a.sh 'Z="${CC_Z_BIN:-zzunobtainium}"
printf %s "$Z"'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t21f" >/dev/null 2>&1 )
  expect 0 "$?" 'a default that never reaches command position was reported as a binary'

  # 21g. GREEN — a default inside a COMMENT. This file itself carries `${CC_TERM_KITTY:-kitty}` in
  #      its own header prose, so a pass blind to comments would convict the lint on its own text.
  newtree t21g; mk t21g hooks/a.sh '# Z="${CC_Z_BIN:-zzunobtainium}" and then "$Z" runs it
true'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t21g" >/dev/null 2>&1 )
  expect 0 "$?" 'a bare-name default inside a COMMENT was reported'

  # 21h. GREEN — a default inside a single-quoted string does not expand, matching case 4's rule for
  #      the command-position scanner. Two producers, one rule about quoting.
  newtree t21h; mk t21h hooks/a.sh 'grep -q '"'"'${CC_Z_BIN:-zzunobtainium}'"'"' "$f"'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t21h" >/dev/null 2>&1 )
  expect 0 "$?" 'a bare-name default inside SINGLE QUOTES was reported'

  # 21i. GREEN — the ONE-SIDED control on the holder rule: a DIFFERENT variable being run must not
  #      convict this default. Without it the "is the holder ever a command" test could degrade into
  #      "does this file ever run anything", which is true of every file in the corpus.
  newtree t21i; mk t21i hooks/a.sh 'Z="${CC_Z_BIN:-zzunobtainium}"
Y=/bin/ls
"$Y" -l'
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t21i" >/dev/null 2>&1 )
  expect 0 "$?" 'running an UNRELATED variable convicted a default that is never run'

  # 19. GREEN on the real tree with the shipped allowlist — the ratchet must be satisfiable today,
  #     or it cannot be wired into the gate at all.
  #
  # ── THE ONE CASE THAT IS A FACT ABOUT THE BOX, AND IS THEREFORE GATED ON DARWIN ────────────────
  # Every other case above was converted to fixture binaries so that its verdict is a property of the
  # tree. THIS one cannot be, and must not be faked into one. It asks whether the shipped allowlist
  # covers the findings the REAL tree produces — and the findings depend on which binaries the box
  # has and where, because that is the question this lint exists to ask. The subject it asks it about
  # is the operator's Mac: `launchd` is a macOS-only supervisor, LAUNCHD_GLOB judges .plist files
  # that only macOS executes, and CORPUS_RUNNERS names a launchd job. There is no launchd job to be
  # unattended on off Darwin, so the tree-level question has no referent there.
  #
  # MEASURED, off Darwin, on an unmodified trunk checkout: 13 fabricated findings (`swift`, `swiftc`,
  # `plutil`, `sqlite3`, `node`, `gtimeout` — every one present on the Mac and absent from Linux) AND
  # 23 STUCK-RATCHET rows (`timeout`, `lsof`, `sysctl`, `taskpolicy`, `gh`, `bun`, `cargo` — every one
  # allowlisted because it is unreachable on the Mac and reachable at /usr/bin here). Both directions
  # at once, from a tree nobody had touched. That is an INERT SENSOR, and the repo's own law is that a
  # sensor which cannot run yields a NON-VERDICT and never a verdict: this case used to return one of
  # those 13-plus-23 as `fails=1`, which took the whole --selftest to exit 1, which took
  # scripts/ship-land.sh's gate arm to `gate_red unattended-path-selftest` for ANY diff on any
  # non-Darwin box — a docs-only one included: backlog f85fce7c26f5, eight dispatches, eight pushed
  # branches, zero lands, each one re-deriving an answer that the arm beside this one then refused
  # to let it deliver.
  #
  # ⚠️ THIS ARM WAS NOT THE WHOLE CAUSE, and the sentence that used to stand here said it was.
  # RETRACTED 2026-08-29, measured on a live Claude-Code-on-the-web VM (Ubuntu 24.04) running this
  # file at the fixing commit. With this arm GREEN (44/44, exit 0, the two non-verdict skips named),
  # ship-land STILL refuses the land, one arm over:
  #
  #   scripts/bats-shellcheck-lint.sh --selftest  →  exit 2, "shellcheck not installed"
  #   ship-land.sh:3444  scrc==2  →  bats_sc_nonverdict  →  GATE_KILLED=1  →  exit 9
  #
  # That arm is entered on EVERY land in this repo — its condition is `[[ -d tests ]] && ls
  # tests/*.bats`, which is a property of the repo and not of the diff — so a docs-only land is
  # refused too, exactly as this one was. Cloud VMs ship no shellcheck; the operator's Mac has it
  # from Homebrew, which is why the arm is invisible on the box that writes these comments.
  # It went blocking at fe6540a6 (2026-08-11, "a missing shellcheck silently deleted the .bats
  # ratchet — now a loud non-verdict"), whose own body measured the new behaviour as exit 9 — the
  # change was deliberate and is CORRECT as a gate; what nobody costed is that it is also a total
  # land-block for every box without the tool, which is every cloud VM.
  # Verified both ways on that VM: `apt-get install shellcheck` moves that selftest 2 → 0 (19/19)
  # and nothing else changes. So the cloud return/land arm needs the tool PROVISIONED, not the gate
  # weakened — the gate is doing its job. Do not read this file's fix as the end of f85fce7c26f5.
  #
  # SKIPPED IS NOT PASSED. The skip is counted and printed, the summary line names it, and the
  # detector's 40-odd hermetic cases still run and still gate — which is what ship-land's arm reads
  # this exit code FOR ("the detector no longer discriminates" is a claim about the detector). The
  # tree-level question is not lost either: the very next thing ship-land does is run this lint over
  # the real tree in own-scope, which asks it directly, of the diff, on whatever box is landing.
  if [ "$(uname -s 2>/dev/null || echo unknown)" != "Darwin" ]; then
    skips=$((skips + 1))
    echo "unattended-path-lint --selftest: SKIP (real-tree arm) — $(uname -s 2>/dev/null || echo unknown), not Darwin."
    echo "  The tree arm judges bare names against the binaries THIS box installs; the unattended jobs"
    echo "  it judges them for are launchd jobs, which exist only on macOS. Off Darwin it fabricates"
    echo "  findings for Mac-only binaries and drops the allowlist rows for Linux-stock ones, in both"
    echo "  directions at once — a NON-VERDICT. The detector cases above ran and are unaffected."
  elif [ -n "$ROOT" ] && [ -d "$ROOT/hooks" ]; then
    ( unset CC_UNATTENDED_OWN; "$SELF" "$ROOT" >/dev/null 2>&1 ); expect 0 "$?" 'the real tree is not clean under the shipped allowlist'
  fi

  # 20. THE LANGUAGE GUARD, both directions. The two files below are byte-identical except for their
  #     SHEBANG, so the only thing either arm can be measuring is the shebang — a one-armed GREEN
  #     here would be satisfied by a scanner that had simply stopped reporting, which is the failure
  #     this pair exists to exclude.
  #
  #     The body replays the real false positive verbatim in shape: `def log_event(zzunobtainium):`
  #     puts the name inside what a SHELL scanner reads as a subshell, i.e. at command position,
  #     which is exactly why bin/claude-accounts:203 rendered a python parameter as an unreachable
  #     binary. The live instance was spelled `yq`; the fixture is not, because `yq` is Homebrew-only
  #     on the Mac and stock at /usr/bin on Linux, which made the RED control below fire on one box
  #     and go silent on the other while the GREEN beside it passed on both.
  pybody='#!/usr/bin/env python3
zzunobtainium = 1
def log_event(zzunobtainium):
    return zzunobtainium'
  shbody='#!/bin/bash
zzunobtainium = 1
def log_event(zzunobtainium):
    return zzunobtainium'

  mkplist() { # $1=tree $2=target-relpath — a plist whose own PATH cannot reach Homebrew
    cat > "$d/$1/launchd/com.test.j.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.test.j</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>-c</string>
    <string>export PATH="/usr/bin:/bin"; exec "\$HOME/$2"</string>
  </array>
</dict></plist>
PLIST
  }

  # THE TREES ARE t22*, NOT t20* — the names these three cases used to carry. `newtree` is mkdir -p,
  # so re-using t20a/t20b/t20c laid the language fixtures ON TOP of the inventory cases' surviving
  # hooks/a.sh. It was green only because those three invocations passed no inventory, leaving the
  # stale hook's word unvouched and dropped; the moment one of them vouched for it — which is what
  # the fixture-binary conversion does everywhere else — 22a would have gone red on the wrong file
  # and 22b red outright. Separate trees make the fixture the only thing in the tree, which is what
  # every other case here already relies on.

  # 22a. RED CONTROL — the identical body under a BASH shebang must still be reported. Without this
  #      the GREEN below proves nothing: it would pass just as well on a lint that scanned nothing.
  newtree t22a; mk t22a scripts/j.sh "$shbody"; mkplist t22a scripts/j.sh
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t22a" >/dev/null 2>&1 ); expect 1 "$?" 'the RED control for the language guard did not fire — a shell file with the same body must still be reported'

  # 22b. GREEN — the same bytes under a PYTHON shebang are prose, not command positions.
  newtree t22b; mk t22b scripts/j.py "$pybody"; mkplist t22b scripts/j.py
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t22b" >/dev/null 2>&1 ); expect 0 "$?" 'a python-shebang file was scanned as shell and its prose reported as a bare binary'

  # 22c. RED — a file with NO shebang is still scanned as shell. The guard must skip python, never
  #      widen into "anything I cannot positively identify as shell", which would silently exempt the
  #      tracked hooks/*.sh that carry no shebang at all.
  newtree t22c; mk t22c scripts/j.sh 'zzunobtainium eval .a "$f"'; mkplist t22c scripts/j.sh
  ( CC_UNATTENDED_ALLOWLIST="" CC_UNATTENDED_INVENTORY="$INV_Z" "$SELF" "$d/t22c" >/dev/null 2>&1 ); expect 1 "$?" 'a shebang-less file stopped being scanned — the guard widened past python'

  # The certificate may only claim what actually ran. `GREEN on the real tree` was a fixed clause in
  # this line; on a platform where case 19 is a non-verdict it would have been a fabricated claim
  # sitting inside the very message that certifies the detector.
  real_tree_clause="; GREEN on the real tree"
  [ "$skips" -gt 0 ] && real_tree_clause=""

  if [ "$fails" -eq 0 ]; then
    echo "unattended-path-lint --selftest: $checks/$checks — RED on a bare binary inside \"\$( )\" (the shape a greedy tokenizer missed), on a bare binary at command position, on a stuck ratchet entry, on a plist whose INLINE export PATH cannot reach the binary, on a /sbin-only binary in the bats corpus under a runner whose PATH stops at /bin, on that binary reached through bats' own \`run\` wrapper, on a bare binary inside a case BODY (invisible to this lint for its whole life, until the label state landed) and on one after a REAL pipe (so the label fix was not bought by blinding the scanner to piped invocations); GREEN on a case LABEL in EITHER arity — the shape that minted two allowlist rows and contorted a real test into \`[ = ] || [ = ]\`, and whose one-arm form was wrongly believed already handled — on an absolute path, a name inside a single-quoted regex, a name in a comment, a heredoc body, a stock binary, a grandfathered site, an allowlist row whose FILE this run never scanned (a non-verdict about this run's reach, never a stale row — the shape that refused the first cloud land to touch bin/cc-dispatch), a plist whose inline PATH does reach, the same corpus file under a runner whose PATH carries /sbin, and prose following an arithmetic expansion nested in a command substitution (the desync that minted two allowlist rows out of nothing); LOUD on a missing root, a root with no governed layers, and a corpus with no runner plist; own-scope blocks INSIDE / advises OUTSIDE across all three arity states; GREEN on a python-shebang file whose prose sits where a shell scanner reads command position, against a RED control of the SAME BYTES under a bash shebang and a RED control on a shebang-less file (so the language guard is keyed on the shebang and did not widen into scanning nothing)${real_tree_clause}. EVERY fixture above names a binary installed NOWHERE (zzunobtainium) or one installed only inside the sandbox (zzreachable), so each verdict is a property of the fixture and not of the invoker's tool inventory — the defect that made this arm answer to \`apt-get install shellcheck\`."
    [ "$skips" -gt 0 ] && echo "unattended-path-lint --selftest: $skips arm(s) SKIPPED as a NON-VERDICT on this platform (named above) — the detector's own cases all ran, and the tree-level question is asked directly by ship-land's own-scope run."
    exit 0
  fi
  echo "unattended-path-lint --selftest: FAILED ($fails of $checks) — the detector does not discriminate."
  exit 1
fi

# ── --print-scope: the population this lint JUDGES, as git pathspecs, one per line ────────────────
# Printed from the SAME three declarations lint_tree collects with — PLIST_TARGET_LAYERS (which also
# builds plist_target_scripts' regex), HOOK_GLOB and BATS_GLOB — so widening any population moves the
# scan and this answer in one edit.
#
# WHY IT EXISTS (backlog 5fc8ff411a7c, extending 0be0bd2c0b65 to the six arms left out of it).
# scripts/ship-land.sh built this lint's own-scope set — the files allowed to BLOCK a land — from a
# `-- 'bin/*' 'hooks/*' 'scripts/*' 'launchd/*' 'tests/*'` pathspec RESTATED in ship-land, under a
# comment reading "the pathspec must list every population the lint judges, or a land that adds a
# bare-name call to one of them produces an own-set without it and the finding degrades to advisory".
# Nothing executes a comment — and this arm is the one that had already needed the comment honoured
# once, when the bats corpus became a third population and `tests/*` had to be added by hand.
#
# TWO DELIBERATE DIFFERENCES FROM THAT RESTATED PATHSPEC, both in the safe direction:
#
#   · `launchd/*` IS GONE, and it never judged anything. The launchd half reads a plist to learn the
#     PATH a job runs with, then scans the SCRIPTS that plist executes — so every path this lint can
#     report is a hooks/*.sh, a plist_target_scripts result (scripts/ bin/ hooks/), or a tests/*.bats.
#     `emit` is called with nothing else, so a plist sitting in an own-set can never match a finding:
#     it was inert, not protective. Printing a population this lint does not judge would make the
#     flag's contract false at its first use.
#
#   · `tests/*.bats`, not `tests/*`. The corpus half judges .bats files; the narrowing is exact
#     rather than approximate, because bats_population is `ls tests/*.bats` and a git pathspec's `*`
#     matches `/` unless `:(glob)` magic is asked for.
#
# `hooks/*.sh` is printed BESIDE `hooks/*` rather than folded into it. The two come from different
# declarations — one from HOOK_GLOB, one from PLIST_TARGET_LAYERS — and dropping the narrower on the
# grounds that today's wider one contains it would make the hook half's scope depend on a subset
# relation nothing checks. git resolves the overlap by listing each path once.
#
# Consumed BEFORE the entrypoint below, which reads `${1:-$ROOT}` as a scan root: past that line the
# flag resolves to a directory named "--print-scope" and the lint answers exit 2 to a question about
# its own scope.
if [ "${1:-}" = "--print-scope" ]; then
  _ps_restore_f=0; case "$-" in *f*) _ps_restore_f=1 ;; esac
  # Globbing OFF for the split AND for the two globs: unquoted, they would PATHNAME-EXPAND against
  # the caller's CWD and print real repo paths instead of the pathspecs — the failure mode that
  # dropped six sites from a sibling lint's census while exiting 0 (see pipefail-sigpipe-lint.sh).
  set -f
  for _ps_l in $PLIST_TARGET_LAYERS; do printf '%s/*\n' "$_ps_l"; done
  printf '%s\n' "$HOOK_GLOB" "$BATS_GLOB"
  [ "$_ps_restore_f" -eq 1 ] || set +f
  exit 0
fi

# ── entrypoint ───────────────────────────────────────────────────────────────────────────────────
# CC_UNATTENDED_OWN — newline-delimited repo-relative paths the caller is answerable for. UNSET ⇒
# every finding blocks. SET-BUT-EMPTY ⇒ nothing blocks (a docs-only land). `${VAR+set}` separates
# those two; `${VAR:-}` would collapse them and silently reinstate the hard stop.
if [ -n "${CC_UNATTENDED_OWN+set}" ]; then
  lint_tree "${1:-$ROOT}" "${CC_UNATTENDED_ALLOWLIST-$EMBEDDED_ALLOWLIST}" "$CC_UNATTENDED_OWN"
else
  lint_tree "${1:-$ROOT}" "${CC_UNATTENDED_ALLOWLIST-$EMBEDDED_ALLOWLIST}"
fi
