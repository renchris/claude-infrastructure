# A07 — the binding clean-code checklist for `bin/cc-lr`, `scripts/limit-recover/*`, `scripts/handoff-fire.sh`

Derived 2026-09-22 by reading the enforcing code, not by generalising shell advice. Every item
names its source and the ONE command that proves compliance. **ENFORCED** = a gate arm, hook or
bats case refuses; **ADVICE** = written down, nothing executes it.

Citations prefer `file` + a unique symbol over `file:NNN` where the line is likely to move
(lesson `a-record-correction-wave-breaks-the-record.md`). Line numbers given were measured today.

---

## 0. The single command that covers most of this list

```
bash scripts/ship-land.sh --precheck --working
```

`--precheck` runs **the same `run_gate()` the land runs** — same lints, same own-scope sets, same
`gate_red` arms — taking no lock, writing no `land.log` row, touching no ref
(`scripts/ship-land.sh:6-15`). `--working` gates `base..worktree` (uncommitted edits included),
which is the true commit-time position. Exit **0** = the land gate would go green · **6** = RED,
and it names the arm · **9** = GATE-KILLED (a lint could not run; retry, do not "fix" anything).

It does **not** run the bats smoke phase (`ship-land.sh:18-19`). Run your own suites separately —
see §4.

---

## 1. Question (a): what the land gate literally runs, in order

`run_gate()` begins at `scripts/ship-land.sh:3183`. Population: `git diff --name-only -z <range>`,
with paths **removed at HEAD skipped** via `[[ -e "$p" ]] || continue` (:3210) so a file-deletion
land is not reddened by linting an absent path.

File classification (`is_shell_file()` / `is_python_file()`, `scripts/ship-land.sh`): `*.sh`/`*.bash`
**or a shell shebang**; `*.py` **or a python shebang**. `bin/cc-lr` is extensionless and is caught
**by its shebang**, not by a glob.

### 1.1 Statics phase (`gate_statics_s`)

| # | Literal invocation | Source | Notes |
|---|---|---|---|
| 1 | `shellcheck "${sc_todo[@]}"` | `ship-land.sh:3258` | **BARE.** No `-S`, no `-x`, no `-e`. Whole set in one call; a red records nothing, so every file re-runs next round (:3260-3263). |
| 2 | `bash -n "$p"` per file | `ship-land.sh:3273` | Whatever `bash` is on the gate's PATH — *not* a 3.2 parse check (see item 6). |
| 3 | `python3 -m py_compile "${py_todo[@]}"` | `ship-land.sh:3280` | **The only Python static check anywhere in the pipeline.** |

Verified absent: `ruff`, `mypy`, `pyflakes`, `shfmt` — zero hits across `ship-land.sh`,
`nightly-regression.sh`, `postland-verify.sh`.

`shellcheck` **not installed** is a NON-VERDICT, not a red: `GATE_KILLED=1` ⇒ exit 9
(`ship-land.sh:3240-3256`).

Per-file memo: verdicts are keyed on blob sha + checker version (`scripts/lib/gate-memo.sh`).
Subsetting is sound **only because shellcheck runs without `-x`** (`ship-land.sh:3220-3226`) — a
future `-x` would have to re-key the memo.

### 1.2 Ratchet-arm phase — 21 arms, in this order

The header at `ship-land.sh:17` says **"all fifteen ratchet arms"**. Counted today between the
statics boundary (:3290) and the smoke phase (:4521) there are **21**. Treat the number in the
header as stale; treat the list below as the population.

| # | Arm (`# ──` header line) | Lint | Binds our 3 paths? |
|---|---|---|---|
| 1 | test-hermeticity :3294 | `scripts/test-hermeticity-lint.sh` | only via `tests/` |
| 2 | wall-clock time-bomb :3382 | `scripts/test-walltime-lint.sh` | only via `tests/` |
| 3 | AF_UNIX absolute-bind :3405 | `scripts/test-afunix-path-lint.sh` | only via `tests/` |
| 4 | moving-ref pre-fix control :3444 | `scripts/moving-ref-control-lint.sh` | only via `tests/` |
| 5 | git-identity escape :3481 | `scripts/git-identity-lint.sh` | **`bin/cc-lr` YES · `handoff-fire.sh` YES · `scripts/limit-recover/*` NO** (glob is `"$root"/scripts/*.sh`, non-recursive — :398, :465) |
| 6 | UTC timestamp contract :3529 | `scripts/utc-stamp-lint.sh` | **ALL THREE** (`SCAN_LAYERS="bin hooks scripts"` :83, walked by `find -type f` :217 ⇒ recursive) |
| 7 | rules hook budget :3583 | `scripts/rules-hook-budget-lint.sh` | only if you touch `.claude/rules/agent-operating-lessons.md` |
| 8 | pipefail/SIGPIPE :3630 | `scripts/pipefail-sigpipe-lint.sh` | **ALL THREE** (`SCAN_PATHSPECS='*.sh *.bats bin/* hooks/* scripts/*'` :436; matched as `case` patterns, so `*` crosses `/`) |
| 9 | bats dead-assertion :3703 | `scripts/bats-assert-liveness.py` | only via `tests/` |
| 10 | script-dir ($0) resolution :3794 | `scripts/self-path-lint.sh` | **NEW code in `bin`/`scripts`/`hooks`** (26 files grandfathered by path) |
| 11 | pane-spawn coverage :3850 | `scripts/pane-spawn-coverage-lint.sh` | **`handoff-fire.sh` YES** (`PSC_LAYERS="bin scripts hooks commands"` :152) |
| 12 | unattended-PATH :3923 | `scripts/unattended-path-lint.sh` | plists + hook paths — see item 22 |
| 13 | permission-gate :4014 | `scripts/permission-gate-lint.sh` | **NO** — actuation set is `install.sh scripts/deploy-* scripts/*land* scripts/ship-* scripts/postland-*` (:104) |
| 14 | Chromium-bundle :4074 | `scripts/chromium-bundle-lint.sh` | no |
| 15 | TSV field-collapse :4120 | `scripts/tsv-pad-lint.sh` | **ALL THREE** (`CC_TSVPAD_DIRS` default `bin hooks scripts`, scanned with `grep -rlF` ⇒ recursive, :209-216) |
| 16 | `.bats` shellcheck :4181 | `scripts/bats-shellcheck-lint.sh` | only via `tests/` |
| 17 | unguarded-kill :4261 | `scripts/bats-kill-guard-lint.sh` | only via `tests/*.bats` |
| 18 | `@test`-name EVAL :4320 | `scripts/bats-testname-eval-lint.sh` | only via `tests/` |
| 19 | LOADED-BUT-UNTRACKED :4352 | `scripts/loaded-untracked-lint.sh` | **whole tree**, not diff-scoped |
| 20 | fleet-manifest coverage :4410 | `scripts/fleet-manifest-lint.sh` | **NO** — scope is `launchd/com.claude.*.plist` + `launchd/com.chrisren.*.plist` (:4) |
| 21 | off-box ADMISSION :4475 | — | last arm, the only expensive one |

**Own-scope is the rule for most arms** (`own_run()`, `ship-land.sh:3027-3036`): the arm exports
`CC_<X>_OWN=<your diff's paths>` and the lint **blocks on findings inside your diff and prints
everything else as `advisory:`**. Three states matter: variable **ABSENT** ⇒ strict whole-tree ·
**SET-BUT-EMPTY** ⇒ "I changed none of these", nothing blocks · **SET** ⇒ block on those only.
Consequence for you: a pre-existing finding in `handoff-fire.sh` will not block your land; a line
**you touch** will.

**Every arm answers three codes** — `0` clean · `1` findings · `2` I-COULD-NOT-RUN — and a `2` is
converted to `GATE_KILLED` (exit 9, retryable) by `arm_nonverdict`, never to `gate_red`
(`ship-land.sh` above `bats_sc_nonverdict`, :3038-3060). Preserve that contract in anything you add.

---

## 2. The checklist

### Statics

**1. Run `shellcheck` BARE, exactly as the gate does — never `-S warning`, never `-x`.**
Source: `scripts/ship-land.sh:3258`; lesson `docs/lessons/a-gates-invocation-is-part-of-its-contract.md`
(measured 2026-09-21: three land attempts, ~3 h of gate time, one root cause; the two concrete
victims were **`bin/cc-lr`** on `SC2016` — an `info`-level code `-S warning` suppresses — and
`tests/lr-drill.sh:574`, which passed under `-x` and failed the bare gate with `SC1091`, a finding
that **only exists when you do not follow sources**). More-thorough is not a superset.
**ENFORCED** (gate arm, statics).
Verify: `shellcheck bin/cc-lr scripts/limit-recover/*.sh scripts/handoff-fire.sh`

**2. Annotate every code a line can emit, or use `source=/dev/null`.**
A `# shellcheck disable=SC1090` tuned under `-x` is inert under the bare gate, which emits `SC1091`
for the same line. Source: same lesson, rule 4. The repo's own idiom is
`# shellcheck source=/dev/null` immediately above the `.` (e.g. `ship-land.sh:265, :859, :867`),
which is invocation-independent. File-wide disables carry a stated reason in the header — see
`scripts/test-afunix-path-lint.sh:2-5`, `scripts/handoff-fire.sh:2-3` (`SC2009`),
`scripts/tsv-pad-lint.sh:2-7` (`SC2016`).
**ENFORCED** (the code fires; the *reason comment* is ADVICE).
Verify: same as item 1.

**3. Python files get `py_compile` and nothing else — do not assume `ruff`/`mypy` will catch you,
and do not add a formatter run.**
Source: `scripts/ship-land.sh:3280`; zero hits for `ruff|mypy|pyflakes` in `ship-land.sh`,
`nightly-regression.sh`, `postland-verify.sh`. Corollary lesson:
`docs/lessons/a-whole-tree-formatter-is-sized-by-the-vendored-tree-not-by-your.md` — this repo
vendors (`vendor/`, `node_modules/`).
**ENFORCED** (py_compile) / the rest is **ADVICE**.
Verify: `python3 -m py_compile scripts/limit-recover/*.py`

**4. `bash -n` must pass — and that is a *different* check from item 6.**
Source: `scripts/ship-land.sh:3273`.
Verify: `for f in bin/cc-lr scripts/limit-recover/*.sh scripts/handoff-fire.sh; do bash -n "$f" || echo "RED $f"; done`

### The interpreter

**5. Assume `/bin/bash` 3.2.57 for anything a scheduler runs.**
`#!/usr/bin/env bash` resolves against the **caller's** PATH: the operator's shell has brew bash 5.x
first, launchd and the GitHub `macos-*` runner do not. Source: `scripts/bash32-parse-lint.sh:4-8`;
lesson `docs/lessons/the-deployment-interpreter-is-not-the-one-on-your-path.md`. Concretely in this
subsystem: `scripts/limit-recover/com.reso.lr-reset-poller.plist` executes
`~/.claude/scripts/limit-recover/lr-reset-poller.sh` by absolute path.
Idioms 3.2 forbids that the repo has already been bitten by: `declare -A`, `mapfile`, `"${arr[@]}"`
on an **empty** array under `set -u` (`permission-gate-lint.sh:412-414` documents the workaround),
and a heredoc body lexed for parens/apostrophes inside `$( )`
(`docs/lessons/bash-32-counts-parens-inside-a-heredoc-it-never-runs.md`;
`scripts/bash32-parse-lint.sh:9-20` records the `mcp-ssot-wire.sh` scar: 2 ok / 10 not ok off-box).
**ENFORCED — but NOT by the land gate.** `scripts/bash32-parse-lint.sh` is wired into **no**
`run_gate` arm (grepped: `ship-land.sh`, `gate-select.sh`, `postland-verify.sh`, `githooks/` — the
only in-tree reference is a comment at `hooks/recover-inject.sh:161`). It reaches you via
`tests/bash32-parse-lint.bats` in the corpus and via the nightly `*lint*.sh` glob.
Verify: `bash scripts/bash32-parse-lint.sh` *(it controls itself: a file is reported only when it
fails under 3.2 **and** parses clean under a modern bash — :31-35)*

**6. Do not let a local `bash -n` stand in for item 5.**
The gate's `bash -n` uses the gate's PATH. Run the 3.2 binary explicitly.
Verify: `/bin/bash -n bin/cc-lr && /bin/bash --version | head -1`

### Naming and switch polarity

**7. A new behaviour ships ON by default with an `=off` kill switch. Never an enable-flag.**
Source: lesson `conservative-branch-gated-on-a-manual-flag.md`
(`~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/`) — *"a branch gated
on a flag no automation passes is permanent inaction"*; the in-file statement of the rule is
`bin/cc-lr` `cl_refuse_not_limited()`: *"KILL SWITCH, never an ENABLE flag … the default has to BE
the correct behaviour, with the escape explicit and named."*
Measured house shape (census over the three paths): `${CC_LR_ROUTE_REFUSAL:-on}`,
`${CC_COMPOSER_SCRUB:-on}`, `${LR_HUSK_RETIRE:-on}`, `${CC_FIRE_OCCUPANCY:-on}`,
`${CC_RECYCLE_GOAL_INHERIT:-1}` — default-on, disabled with `=off`/`=0`. The `:-off`/`:-0` spellings
that exist (`LR_LOAD_TERM`, `LR_POLLER_AUTOFIRE`, `FIRE_ALLOW_SLASH_HEAD`) are all **widening**
escapes, i.e. opt-in to do *more*, never opt-in to be correct.
**ADVICE** (no lint reads switch polarity) — but the bats case is house standard: 165 of the
`tests/*.bats` files carry a "kill switch" case, and `tests/cc-lr-front.bats:175` is the pattern
(*"`CC_LR_ROUTE_REFUSAL=off` restores the pre-routing refusal byte-for-byte"*).
Verify: `grep -nE '\$\{(CC|LR|FIRE)_[A-Z0-9_]+:-(on|1)\}' <your file>` and confirm each has a
`=off` case in the suite.

**8. Env-var prefixes: `CC_*` for machine-wide seams, `LR_*` for limit-recover state,
`FIRE_*` for handoff-fire, `SHIP_LAND_*` for gate seams.**
Source: the census above; `bin/cc-lr:41-49` names `LR_STATE_DIR` as the one spelling
`lr-fleet.sh:69`, `lr-fire-resume.sh:244`, `lr-lib.sh:511` and `bin/cc-limited:88` all honour.
**ADVICE.** Verify: `grep -oE '\$\{?(CC|LR|FIRE|SHIP_LAND)_[A-Z0-9_]+' <your file> | sort -u`

**9. A new `bin/` tool must be named `cc-*` or it is never deployed.**
`install.sh:995` globs exactly `"$REPO_DIR"/bin/cc-* "$REPO_DIR"/bin/desk-* "$REPO_DIR"/bin/ms365-*`
into `$CONFIG_DIR/bin/`. Anything else is tracked, lint-covered, and linked nowhere — the defect
`install.sh:540-548` records five times.
**ENFORCED** by consequence (it simply will not exist at runtime), not by refusal.
Verify: `bash install.sh --dry-run 2>&1 | grep '<your tool>'` *(or `grep -n 'bin/cc-\*' install.sh`)*

**10. A new file under `scripts/limit-recover/` deploys automatically — but only if it is a
regular file.** `install.sh:818-828` globs `scripts/limit-recover/*` (every file, not just `*.sh`)
and symlinks it under `$CONFIG_DIR/scripts/limit-recover/`.
**ENFORCED**: `tests/install-wire-hooks.bats:68` asserts a one-to-one mapping of that directory into
a fresh config dir, and `:86` asserts idempotence. Moreover `scripts/gate-select.sh:122` lists
`scripts/limit-recover/.+` and `bin/cc-[^/]+` in `INSTALL_RE`, so **any** edit to either path makes
`tests/install-wire-hooks.bats` a DIRECT suite of your land.
Verify: `bash scripts/gate-select.sh --direct --explain origin/main..HEAD`

### Refusal, rc taxonomy, mutex

**11. Actuator rc taxonomy: `0` ok · `1` nothing matched · `2` REFUSED (nothing created) · `3` usage.**
Source: `bin/cc-lr:35` and its usage block `:91`; identical in `bin/cc-find:45, :82`
(`rc 0 resolved · 1 no match · 2 AMBIGUOUS · 3 usage`). `lr-fleet.sh` refuses `--detach` with
`exit 2` when it cannot reach `detach.sh` (`:1055`).
**ENFORCED for `cc-lr`** by `tests/cc-lr-front.bats` (rc-2 cases at :91, :107, :118, :188, :526,
:534; rc-3 at :626; rc-1 relay at :199).
Verify: `bats tests/cc-lr-front.bats -f 'rc|REFUS|usage'`

**12. Lint/detector rc taxonomy is DIFFERENT: `0` clean · `1` findings · `2` NON-VERDICT.**
A `2` is never dressed up as a claim about the tree. Sources: `scripts/test-walltime-lint.sh:37`,
`scripts/bats-kill-guard-lint.sh:108`, `scripts/bg-fd-inherit-lint.sh:44`,
`scripts/tsv-pad-lint.sh:84`, `scripts/rules-hook-budget-lint.sh:38`;
`scripts/nightly-regression.sh:174` states it outright — *"rc 2 is this repo's lint convention for
'could not run'"*. Consumer side: `arm_nonverdict` ⇒ `GATE_KILLED` ⇒ exit 9.
**ENFORCED** at the consumer (an arm that collapses 2 into 1 is the defect `ship-land.sh:3055-3060`
measured: 9 of 16 arms did it).
Verify: `bash scripts/<your-lint>.sh /nonexistent; echo "rc=$?"` → must be `2`.

**13. A refusal exits **before** any mutex, request file, or child process is created.**
Source: `bin/cc-lr:20-22` — *"each refuses with rc 2 BEFORE any mutex is created — a refusal that
leaves a lock behind is a refusal that blocks the next correct attempt"*; `cmd_recover()` orders
RULE 0 (teammate) → RULE 2 (not limited) → `cl_mutex_take` (`bin/cc-lr:262-276`).
Symmetrically, **a failure after the mutex releases it**: `bin/cc-lr` releases on an unreachable
`lr-fleet` (:279) and on a non-zero `--one` (:288).
**ENFORCED**: `tests/cc-lr-front.bats` "…and creates no mutex" (:91, :107, :118, :188) and
"recover RELEASES the mutex when lr-fleet refuses" (:265), "repair REFUSES and RELEASES nothing…"
(:476), "repair leaves NO request behind when the write itself fails" (:486).
Verify: `bats tests/cc-lr-front.bats -f 'mutex|RELEAS|leaves NO'`

**14. A refusal bounds the TOOL, never the world — name the next command.**
Source: `bin/cc-lr` `cl_refuse_not_limited()` header (the 2026-09-22 correction: the old text said
*"there is nothing to recover"*, which was false for a context-death session on pane 500); lessons
`reference-a-refusal-bounds-the-tool-not-the-world` and `detector-with-no-owner-is-not-an-actuator`.
**ENFORCED**: `tests/cc-lr-front.bats:140` — *"recover REFUSES a context-death session by NAMING
the api error and the next command"*, with `:159` and `:175` as the controls.
Verify: `bats tests/cc-lr-front.bats -f 'context-death|NAMING'`

**15. Mutex liveness is READ, never assumed: alive ⇒ refuse · dead ⇒ steal loudly · unlabelled ⇒
steal only past the TTL.** Source: `bin/cc-lr:108-119` and `cl_mutex_take()`. `mkdir` is the atomic
primitive. Re-stamp the holder with the **driver's** pid before exiting (`bin/cc-lr:294-297`) — a
mutex naming a dead pid is stolen by the next caller.
**ENFORCED**: `tests/cc-lr-front.bats:226, :236, :253`.
Related traps to not re-introduce: `docs/lessons/a-stale-pid-does-not-decay-into-harmlessness…md`
and `census-matches-itself.md` (never `pgrep -f <name>` for a census — argv carries whole briefs).
Verify: `bats tests/cc-lr-front.bats -f 'mutex'`

### The `cc-lr` iron rule

**16. `bin/cc-lr` may never type into a pane, kill, ship, deploy, or mutate git; `launchctl` only
as `kickstart`, never with `-k`.**
Source: `bin/cc-lr:24-29`; the ratchet is `iron_rule()` in `tests/cc-lr-front.bats:565-594`.
**ENFORCED, with a positive control** (`tests/cc-lr-front.bats:603` mutates the file with each of
eight banned verbs and asserts the ratchet trips on every one).
🚨 **The `kill` clause counts lines in the WHOLE FILE, comments included**
(`tests/cc-lr-front.bats:599`: `grep -cE '(^|[^a-zA-Z_.-])kill[[:space:]]' "$LR"` must equal
`grep -cE 'kill -0' "$LR"`). So writing `kill -9` **in a comment** in `bin/cc-lr` reddens the suite.
`kill -0` is the one allowed spelling, and only as the mutex's liveness read.
Verify: `bats tests/cc-lr-front.bats -f 'iron rule'`

### The lints that bind the source files

**17. Any `date` format string ending in a literal `Z` must carry `-u`.**
Rule: *"a stamp whose format string ends in `Z` is ASSERTING UTC; if the `date` call has no `-u`
the assertion is FALSE on any box not set to UTC"* — `scripts/utc-stamp-lint.sh:17-20`. The scar is
`cc-reaper`'s `log()`, fixed in `b4e3c355`. The embedded allowlist is **EMPTY** (:88) — the tree was
swept clean, so this lint can only go red on something you wrote. Correct sites in `bin/cc-lr`:
`date -u +%Y-%m-%dT%H:%M:%SZ` at the two holder writes.
Not flagged (deliberately): `date '+…%z'` and plain human-facing `date '+%Y-%m-%d %H:%M:%S'` (:26-31).
**ENFORCED** (arm 6, recursive over `bin hooks scripts`).
Verify: `bash scripts/utc-stamp-lint.sh`

**18. `producer | early-exit-consumer` under `set -o pipefail` is a violation.**
`grep -q` exits on match, the producer takes SIGPIPE, `pipefail` promotes 141, and the `if` reads
FALSE for a flag that is plainly advertised. Measured failure rate on `/bin/bash 3.2.57`: **95/100**
at 8 KiB still to write, **100/100** at ≥32 KiB (`scripts/pipefail-sigpipe-lint.sh:18-28`; the scar
is `ec9a43a9` in `cc-relogin-poll`). Drained consumers (`grep PAT >/dev/null`, `awk 'NR<=N'`) are
0/400 and are the cure.
Note the coupling: **adding `set -o pipefail` to a file activates this lint over every pipeline in
it.** All three subject files already run pipefail (`bin/cc-lr:36`, `lr-fleet.sh:30`,
`lr-reset-poller.sh:40`, `lr-predicate.sh:14`; `lr-handoff.sh:63` and `lr-transplant.sh:14` use
`set -euo pipefail`).
**ENFORCED** (arm 8).
Verify: `bash scripts/pipefail-sigpipe-lint.sh --census`

**19. An `IFS=<tab> read` in `bin/`, `hooks/` or `scripts/` needs a greppable statement that the
author considered field collapse.** TAB is IFS *whitespace*, so a run of tabs collapses and every
later field shifts LEFT at exit 0. Four accepted discharges (`scripts/tsv-pad-lint.sh:45-52`):
(1) a padding def at the emitter (`def cell(ph):` / `_cell`) · (2) an un-pad (`unpad()`, `TSV_PAD`)
· (3) another spelling of the same guarantee — `norm()`/`dash()` awk right-fill, **or `${var:--}`**
· (4) the reviewed exemption table, with a reason.
`bin/cc-lr` discharges via clause 3 (`"${pane:--}"` at the mutex take and the `--source-pane` arm);
`scripts/limit-recover/lr-reset-poller.sh` is exempted by name with a reason at
`scripts/tsv-pad-lint.sh:132`. **The ratchet runs both ways** — an exemption naming a file that no
longer reads TSV is itself a violation (:55-56).
**ENFORCED** (arm 15, own-scoped; bare-basename own-matching, so a file you just added *is* in your
blocking set).
Verify: `bash scripts/tsv-pad-lint.sh`

**20. Resolve `$0` through `readlink` before deriving any sibling path.**
`~/.claude/{bin,scripts,hooks}` are **per-file symlink farms** into this checkout, so `dirname "$0"`
is `~/.claude/scripts`, and `dirname "$0"/..` is `~/.claude` — no `tests/`, no `docs/`, no `.git`.
Three incidents, one root cause (`scripts/self-path-lint.sh:9-19`); the 2026-07-26 machine-wide gate
runaway is one of them. 26 files are grandfathered **by path** and the list may only SHRINK — fix one
and forget to delete its allowlist line and the lint fails.
The sanctioned shape is in `bin/cc-lr:52-56`:
`_CL_SELF="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"`, then `cd "$(dirname "$_CL_SELF")"`.
`scripts/handoff-fire.sh` and `gate-select.sh` use the `BASH_SOURCE[0]` + readlink-loop form
(`utc-stamp-lint.sh:70-78` shows the loop).
**ENFORCED** (arm 10) for NEW code. Companion lesson:
`docs/lessons/symlinked-0-splits-sibling-sources.md` (one invocation splits into a half that
resolves and a half that dies).
Verify: `bash scripts/self-path-lint.sh`

**21. Every line issuing a terminal-surface primitive must log a pane-spawn row within
`CC_PSC_WINDOW` (12) lines.** Three primitive families: `launch --type=`/`--location=`;
`create tab with` / `create window with` / `split vertically with` / `split horizontally with`;
`detach-window` **without** `--target-tab` (`scripts/pane-spawn-coverage-lint.sh:18-27`). Tier 1
(a primitive in a file with **no** logger call anywhere) blocks; tier 2 is proximity and advises.
The argv-list form (`["kitty","@","launch","--type=…"]`) is caught by **adjacency**; a list split
across lines is a stated blind spot (:56-62).
Binds `scripts/handoff-fire.sh` directly. Logger: `scripts/lib/pane-spawn-log.sh` /
`cc_log_pane_spawn`.
**ENFORCED** (arm 11).
Verify: `bash scripts/pane-spawn-coverage-lint.sh && bash scripts/pane-spawn-coverage-lint.sh --print-scope`

**22. No bare-name binary on an unattended path.**
A bare command name resolves against the caller's PATH; on launchd or inside a hook-spawned session
it may not exist, and the 127 is unchecked. Five recurrences, all failing **open**
(`scripts/unattended-path-lint.sh:4-24`): a safety refusal that permitted the removal it blocks, a
load shed that never shed, an alarm that went silent, a pane close that left a 653 MB `claude.exe`
resident for 3 h 09 m.
Directly relevant here: `scripts/limit-recover/com.reso.lr-reset-poller.plist` is a **loaded launchd
job**, so anything it reaches must use absolute paths or an explicitly exported PATH.
**ENFORCED** (arm 12) — read its scope before assuming, because the populations are plists + hooks,
not "every script".
Verify: `bash scripts/unattended-path-lint.sh --print-scope && bash scripts/unattended-path-lint.sh`

**23. `git -C "$var"` for an identity write is a violation when `$var` is a bare expansion.**
`git -C ""` is a documented **no-op** that writes to the current repo; with ~100 linked worktrees
sharing one `.git/config`, one such call re-authors every session on the machine (9 commits here,
214 on `reso-management-app` authored `t <t@t>`). Accepted forms carry a token that cannot be empty:
`"${1:?}"`, `"${d:-/some/path}"`, a literal path, `"$d/repo"` (`scripts/git-identity-lint.sh:16-27`).
Rule 2 covers the no-`-C` case after an unguarded `cd`.
Binds `bin/cc-lr` and `scripts/handoff-fire.sh`; **not** `scripts/limit-recover/*` (non-recursive
glob). **ENFORCED** (arm 5), and separately by `githooks/pre-commit` + `githooks/pre-push`.
Verify: `bash scripts/git-identity-lint.sh`

**24. Detach with `scripts/lib/detach.sh`, never `nohup … &`.**
When a typed `/exit` interrupts the in-flight Bash tool call, Claude Code SIGKILLs the whole process
**group**; a `nohup`'d child shares that pgid and dies with a 0-byte log and no error (observed 2×
2026-07-13). `start_new_session=True` gives the child its own session+pgid and PPID 1 immediately —
no race. Source: `scripts/lib/detach.sh:1-18`. `lr-fleet.sh:1051-1055` resolves it through the
three-path ladder and **refuses `--detach` rather than silently running blocking** if it cannot.
`handoff-fire.sh` keeps its own copy for a stated reason (`detach.sh:19-22`).
**ADVICE** (no lint; the refusal at `lr-fleet.sh:1055` is the only enforcement, and it is local).
Verify: `grep -n 'detach\|nohup' <your file>`

**25. Do not let a backgrounded child inherit stdout on a hook path.**
A hook's stdout is a pipe the harness reads to EOF; backgrounding closes no descriptor and `disown`
does not either. Measured: pane 113 wedged **54 minutes** with zero hook children
(`scripts/bg-fd-inherit-lint.sh:4-15`). `hooks/session-beat.sh` is the standing positive control
(backgrounds and redirects **both** descriptors).
**ENFORCED for `hooks/` only** (`--dir hooks` default, `:43`) — for `bin/`/`scripts/` this is ADVICE,
but the mechanism is identical wherever a parent's stdout is a pipe someone waits on.
Verify: `bash scripts/bg-fd-inherit-lint.sh --dir hooks`

**26. Build a pattern for *another* program under **that** program's decoding.**
A locale pin protects the process that sets it and reaches no further. Incident: `lr_wrap_re` in
`scripts/limit-recover/lr-fire-resume.sh` builds a **Tcl** regex for `expect`; the same backslash is
a literal-escape under UTF-8 and an invalid escape under C. Source:
`docs/lessons/a-locale-pin-protects-only-the-process-that-sets-it.md` (post-land RED,
`tests/lr-resume-answer-width.bats` @ `cde5cbfa0a08`, 8 of 11; write-up
`docs/research/lr-resume-expect-encoding-2026-09-20.md`).
**ENFORCED** only by that suite. Verify: `bats tests/lr-resume-answer-width.bats`

**27. Every harness-loaded file you add must be `git add`ed (or explicitly ignored).**
Scope is "loaded AND not ignored AND not tracked"; it is a **whole-tree** predicate, deliberately not
diff-scoped, because a never-`git add`ed file appears in no diff (`ship-land.sh:4367-4371`). Baseline
is ZERO offenders.
**ENFORCED** (arm 19). Verify: `bash scripts/loaded-untracked-lint.sh`

### Tests you add

**28. Name the suite so `gate-select` can reach it: `tests/<stem>.bats` or `tests/<stem>-*.bats`.**
Clause (b), `scripts/gate-select.sh:411-416` (`naming(stem)`): `bin/cc-lr` → `tests/cc-lr.bats` or
`tests/cc-lr-*.bats`; `scripts/limit-recover/lr-handoff.sh` → `tests/lr-handoff-*.bats`. The
selector's `lint` mode asserts **every** `tests/*.bats` is reachable from ≥1 non-test tracked file;
an unreachable suite is one the selector can never pick, and `ship-land` falls back to `FULL`
whenever that lint fails (`gate-select.sh:37-41`).
**ENFORCED** (`gate-select.sh lint`, consumed by the land).
Verify: `bash scripts/gate-select.sh lint`

**29. A DIRECT edge needs evidence in the suite's EXECUTABLE text, not in a comment.**
`cited_only` (`gate-select.sh:280`): a path a suite merely *cites* in a comment selects the suite but
never makes its failure un-exonerable. This is precisely why `tests/tsv-field-collapse.bats` blocked
none of the lands it should have (`scripts/tsv-pad-lint.sh:33-40`). Put
`LR="$REPO/bin/cc-lr"` in `setup()`, as `tests/cc-lr-front.bats:19` does.
**ENFORCED.** Verify: `bash scripts/gate-select.sh --direct --explain origin/main..HEAD`

**30. `setup()` must set a fixture `HOME` (and every other ambient seam the subject reads).**
RULE 1, `scripts/test-hermeticity-lint.sh:18`. Rules 2, 3, 5, 6 extend it to the fire capacity gate,
the orphan-close lever, non-`$HOME` seams and **inherited values**. The house shape is
`tests/cc-lr-front.bats:21-33`: fixture `HOME`, fixture `LR_STATE_DIR`, stubbed `CC_LR_FIND_BIN` /
`CC_LR_FLEET_BIN`, a `STUBBIN` prepended to `PATH` — with the reason stated in-file (*"a case that
reached the real lr-fleet would RECOVER A PANE from a test run"*).
**ENFORCED** (arm 1). Also see `docs/lessons/a-fixture-s-hermeticity-ends-where-its-subject-spawns-a-third-tool.md`:
a subject that **spawns** a third program resolves its own paths under its OWN variable names.
Verify: `bash scripts/test-hermeticity-lint.sh tests`

**31. Give every stub a shebang.**
bash runs an ENOEXEC file as a script, but CPython's `subprocess` reads it as not-executable and
keeps walking PATH to the real binary — so Python callers read the real machine while the stub looks
sealed. Source: `docs/lessons/a-shebang-less-stub-seals-only-the-shell-arm.md`. (`cc-lr-front.bats`
writes `#!/usr/bin/env bash` into every stub — :39, :50.)
**ADVICE.** Verify: `head -1 <stub>`

**32. Non-final `[[ ]]` is errexit-EXEMPT under bats — use `[[ … ]] || { …; false; }`.**
A bare mid-test `[[ ]]` is a DEAD assertion that can never fail. Source:
`tests/typed-send-lint.bats:33-35`; memory `bats-dead-assertions-errexit-exemptions`; same class for
`! cmd` (`negated-assertion-dead-unless-final`).
**ENFORCED** (arm 9, `scripts/bats-assert-liveness.py`; and `gate-select.sh` clause (g) forces
`tests/bats-assert-liveness.bats` onto **any** `.bats` edit, `:117-121`).
Verify: `python3 scripts/bats-assert-liveness.py tests`

**33. No absolute-path AF_UNIX bind in a fixture — chdir and bind the BASENAME.**
Darwin caps `sun_path` at 104 bytes against the string handed to `bind(2)`; under launchd's
`/var/folders/…` prefix plus postland's run dir it does not fit, and **the polarity is the worst
available**: green in every hand-check, red only inside `postland-verify`, including green under the
repro postland itself prints. `tests/boot-resume-launch.bats` was in 17 of 17 postland reds over 40 h
(`scripts/test-afunix-path-lint.sh:8-25`).
**ENFORCED** (arm 3). Verify: `bash scripts/test-afunix-path-lint.sh tests`

**34. No FUTURE absolute date literal in non-comment test code.**
`scripts/test-walltime-lint.sh:13`. **ENFORCED** (arm 2). Verify: `bash scripts/test-walltime-lint.sh tests`

**35. A pre-fix CONTROL must not replay from a MOVING ref.**
`git show origin/main:<path>` is the pre-fix artifact only until the fix lands; after that the
control compares the fix to itself. Two outcomes, and the silent one is why it is a lint
(`scripts/moving-ref-control-lint.sh:6-24`). Pin the sha (`<fix>^`).
**ENFORCED** (arm 4). Verify: `bash scripts/moving-ref-control-lint.sh tests`

**36. `kill` in a `.bats` file must be guarded; a `@test` name must not EXPAND.**
`scripts/bats-kill-guard-lint.sh` (arm 17) and `scripts/bats-testname-eval-lint.sh` (arm 18). The
kill-guard lint is careful about `@test` **titles** containing the words (`:661-668`), so state the
rule in the title freely.
**ENFORCED.** Verify: `bash scripts/bats-kill-guard-lint.sh tests && bash scripts/bats-testname-eval-lint.sh tests`

**37. `.bats` files are shellchecked, own-scoped to the lines your land WROTE.**
Arm 16, `ship-land.sh:4235` (*"blocking on N changed line(s); pre-existing findings advisory"*).
A suite that **aborts** shellcheck entirely also reds (`:4254-4255`).
**ENFORCED.** Verify: `bash scripts/bats-shellcheck-lint.sh tests`

**38. Build a positive control for any grep-shaped ratchet you add.**
*"A grep that has never once gone red is a grep nobody has shown to be live"* —
`tests/cc-lr-front.bats:566-568`, with `:603` as the worked example (eight mutants, each asserted to
trip, plus the unmutated copy asserted clean). Lessons:
`green-in-both-arms-is-an-equivalence-guard-not-a-red-proof.md`,
`one-dead-assertion-class-found-is-not-the-last-one.md`,
`a-mutation-control-anchors-on-the-subjects-source-text.md` (a refactor can disarm the control).
**ADVICE**, universally practised here.
Verify: mutate, run, assert non-zero; then run the unmutated copy.

**39. Run suites through `cc-bats`, and never make it wait.**
`bin/cc-bats` sheds with **rc 75** (`EX_TEMPFAIL`, `:438`) under load; that is a deferral, not a red,
and it is distinguishable from bats' own 0/1 and from 127. The land gate itself is
admission-exempt (`docs/lessons/the-land-gate-is-admission-exempt.md`).
Related: assert the plan line `1..N` before believing a filtered TAP result — a gate that REFUSES to
run emits no `not ok` and exits 0 (`docs/lessons/a-gate-refusal-is-not-a-gate-result.md`).
Verify: `cc-bats tests/cc-lr-front.bats; echo "rc=$?"`

### New lints / gates, if the work adds one

**40. Anything you name `*lint*.sh` or `*gate*.sh` under `scripts/` is auto-conscripted into the
nightly.** `scripts/nightly-regression.sh:72` (`LINT_GLOB="${CC_NIGHTLY_LINT_GLOB:-$REPO/scripts/*lint*.sh}"`)
runs `--selftest` where supported, else a bare read-only run, over whatever it finds (:255, :617). So
a new lint must (a) support `--selftest`, (b) be **green on the tree as it stands** — a lint that
ships standing-red poisons the whole nightly signal (`tests/typed-send-lint.bats:27-29`), and (c) be
side-effect-free. Lesson: `filename-glob-conscripts-into-a-sibling-gate.md` — grep the globs before
naming a file.
**ENFORCED** (by the nightly, and by `transitive_e2e_assert`).
Verify: `bash scripts/nightly-regression.sh --list 2>/dev/null || grep -n 'LINT_GLOB\|GATE_GLOB' scripts/nightly-regression.sh`

**41. Any direct `*-e2e.sh` invocation from inside a declared gate/lint needs an inline
`# e2e:reviewed-hermetic` marker.** Step 4 skips `*-e2e.sh` wholesale, **but the skip is not
transitive** (`scripts/nightly-regression.sh:485-490`). Unmarked ⇒ RED, fail-closed.
**ENFORCED.**

**42. Enforce at the chokepoint, not in a sibling suite.**
*"A lint only its own suite runs is DETECTION, not enforcement"* (`ship-land.sh:4362-4365`;
memory `enforcement-must-live-at-the-chokepoint`). The measured proof is `tsv-pad-lint.sh:17-40`: the
repo-wide bats guard re-reddened with a **completely different offender set** three times because
`cited_only` kept it off the direct-suite list of the lands that added the offenders.
**ADVICE** (it is a design rule for you, enforced on nobody).

### Commit / land path

**43. Never bypass a hook; never commit in the shared checkout.**
`githooks/pre-commit` refuses a commit authored by anyone but the operator (allowlist of ONE address,
derived from a live GitHub API measurement, re-derivable via
`scripts/git-identity-assert.sh verify-attribution`); `githooks/pre-push` is the real chokepoint
because `rebase`, `cherry-pick`, `merge`, `am` and `commit-tree` **do not run `pre-commit`** and
`ship-land` rebases immediately before pushing. `githooks/commit-msg` rejects AI-authorship trailers.
Project rule: work in a dedicated worktree, commit on your own branch, land via the project-local
`/ship`; verify landings **by content** (`git ls-tree origin/main -- <paths>`), never by count
(`.claude/CLAUDE.md` § "Never commit or land in the shared checkout").
**ENFORCED** (git hooks + `ship-land` preflight's shared-checkout refusal).

**44. Do not write `DELETE FROM` / `DROP TABLE` / `TRUNCATE TABLE` / a PEM header into the diff —
including in prose.** `esc_scan` (`ship-land.sh:497-580`) parks a decision packet and exits 3.
The EFFECT class is exemptible per path via `scripts/esc-exempt.manifest`, **read from the BASE
revision** so a land cannot widen its own exemption (:549-556); the DISCLOSURE class (private-key
header) scans every changed file and is never exemptible.
**ENFORCED.** Verify: `grep -inE 'DELETE[[:space:]]+FROM|DROP[[:space:]]+TABLE|BEGIN[[:space:]A-Z]*PRIVATE[[:space:]]+KEY' <your diff>`

**45. If you add a bullet to `.claude/rules/agent-operating-lessons.md`, the body goes to
`docs/lessons/<slug>.md` and the hook links it.**
Two mechanical refusals: a **bodyless** bullet (link target `.`) and an **over-budget** bullet
(`scripts/rules-hook-budget-lint.sh:16-22`). Own-scoped by `--own-range`, fails **closed** if the
diff cannot be read (:28-36).
⚠️ **The enforced budget is 420 chars** (`scripts/rules-hook-budget-lint.sh:45`,
`BUDGET="${RULES_HOOK_BUDGET:-420}"`), while the rules file's own header says *"≤ ~350 chars per
bullet"*. Write to 350 and you are safe under both; write to 420 and you are only safe under the
one that executes.
**ENFORCED** (arm 7). Verify: `bash scripts/rules-hook-budget-lint.sh --own-range origin/main..HEAD`

---

## 3. Question (d): ENFORCED vs ADVICE, at a glance

| Item | Enforced by | Kind |
|---|---|---|
| 1, 2 (bare shellcheck, annotate every code) | gate statics `ship-land.sh:3258` | **gate** |
| 3 (py_compile only) | gate statics `:3280` | **gate** |
| 4 (`bash -n`) | gate statics `:3273` | **gate** |
| 5, 6 (bash 3.2) | `tests/bash32-parse-lint.bats` + nightly glob — **NOT a gate arm** | **test/nightly** |
| 7 (`=off` kill switch) | nothing | advice (+ per-suite case) |
| 8 (env prefixes) | nothing | advice |
| 9, 10 (deploy wiring) | `tests/install-wire-hooks.bats`, forced DIRECT by `gate-select.sh:122` | **test, gate-selected** |
| 11 (actuator rc) | `tests/cc-lr-front.bats` | **test** |
| 12 (lint rc 2 = non-verdict) | consumer arms via `arm_nonverdict` | **gate** |
| 13, 14, 15 (refuse-before-mutex, refusal bounds the tool, mutex liveness) | `tests/cc-lr-front.bats` | **test** |
| 16 (iron rule) | `tests/cc-lr-front.bats` `iron_rule()` + positive control | **test** |
| 17 (UTC `-u`) | arm 6 | **gate** |
| 18 (pipefail/SIGPIPE) | arm 8 | **gate** |
| 19 (TSV padding) | arm 15 | **gate** |
| 20 (`$0` via readlink) | arm 10 | **gate** (new code only) |
| 21 (pane-spawn logging) | arm 11 | **gate** |
| 22 (unattended PATH) | arm 12 | **gate** |
| 23 (git identity) | arm 5 + `githooks/pre-commit`/`pre-push` | **gate + hook** |
| 24 (detach.sh) | `lr-fleet.sh:1055` refusal only | advice |
| 25 (bg fd inherit) | arm? no — `tests/bg-fd-inherit-lint.bats`, scope `hooks/` | **test, hooks only** |
| 26 (consumer decoding) | `tests/lr-resume-answer-width.bats` | **test** |
| 27 (loaded-but-untracked) | arm 19 | **gate** |
| 28, 29 (suite naming, direct edge) | `gate-select.sh lint`, consumed by the land | **gate** |
| 30 (hermetic `setup()`) | arm 1 | **gate** |
| 31 (stub shebang) | nothing | advice |
| 32 (dead assertions) | arm 9 + `gate-select` clause (g) | **gate** |
| 33, 34, 35, 36, 37 (afunix, walltime, moving-ref, kill-guard, testname-eval, bats-shellcheck) | arms 3, 2, 4, 17, 18, 16 | **gate** |
| 38 (positive control) | nothing | advice |
| 39 (`cc-bats`, rc 75) | `bin/cc-bats:438` | **tooling contract** |
| 40, 41 (new lint conscription, e2e marker) | `scripts/nightly-regression.sh` | **nightly** |
| 42 (chokepoint) | nothing | advice |
| 43 (hooks, shared checkout) | `githooks/*` + `ship-land` preflight | **hook + gate** |
| 44 (escalation scan) | `ship-land.sh` preflight | **gate** |
| 45 (rules hook budget) | arm 7 | **gate** |

Arms that **do not** bind these three paths, so do not over-apply them: **permission-gate**
(actuation set is `install.sh scripts/deploy-* scripts/*land* scripts/ship-* scripts/postland-*`,
`permission-gate-lint.sh:104`), **fleet-manifest** (`launchd/com.claude.*.plist` +
`launchd/com.chrisren.*.plist` only), **Chromium-bundle**.

---

## 4. Adversarial pass — what a hostile reviewer would catch

Three checks run against the obvious reading, each with a real finding:

**(a) "the gate runs fifteen ratchet arms."** It runs **21** (`ship-land.sh` `# ──` headers between
:3294 and :4475; the claim is at :17). The header has not tracked the arms added since. If you plan
gate time from that sentence, you are planning against a six-arm-stale number. The honest way to
enumerate is `grep -n '^  # ── ' scripts/ship-land.sh`, not the header.

**(b) "the bash-3.2 ratchet gates the land."** It does **not**. `scripts/bash32-parse-lint.sh` is
referenced by no `run_gate` arm, by `gate-select.sh`, or by `postland-verify.sh` — the only in-tree
mention is a comment at `hooks/recover-inject.sh:161`. It reaches a land only if
`tests/bash32-parse-lint.bats` is selected **and** the smoke actually runs — and the smoke is
`none`/`skipped` on **84.8%** of invocations that record the field (`ship-land.sh:18-19`), plus
load-shed above `CC_GATE_MAX_LOAD`. So the interpreter rule most likely to kill this subsystem
off-box (the poller plist executes by absolute path) is enforced by the arm most likely to be
skipped. **Run it by hand before landing; do not rely on the gate for item 5.**

**(c) "the documented per-bullet budget is the enforced one."** `.claude/rules/agent-operating-lessons.md`
says ≤ ~350 chars; `scripts/rules-hook-budget-lint.sh:45` enforces 420. Same class as
`wrong-cause-corroborated-by-true-metric` — two numbers, one executed, and the prose one reads as
authoritative. Write to the stricter (350).

Two further gaps worth naming, neither of which is a checklist item because neither can be fixed
inside this work:

- **`scripts/limit-recover/com.reso.lr-reset-poller.plist` is invisible to the fleet chokepoint.**
  `scripts/fleet-manifest-lint.sh:4` scopes to `launchd/com.claude.*.plist` and
  `launchd/com.chrisren.*.plist`; this plist is in the wrong directory **and** carries the wrong label
  prefix (`com.reso.`), and `launchd/fleet.manifest` has no row for it. So a loaded daemon in this
  subsystem is outside `cc-fleet`'s unit of coverage (DAEMON_FLEET_V2 §4.1 — "an undeclared label is
  unreachable by every leg of the tool"). If the work touches the poller's lifecycle, say so in the
  close rather than assuming the fleet tooling sees it.
- **`bin/cc-lr:41-49` already documents a split store**: `LR_STATE_DIR` is honoured by
  `lr-fleet.sh:69`, `lr-fire-resume.sh:244`, `lr-lib.sh:511`, `bin/cc-limited:88`, while
  `lr-handoff.sh:479` and `lr-reset-poller.sh:127` hardcode `$HOME/.reso/limit-recover`. Any new verb
  that writes state inherits that divergence. Do not "fix" it silently inside another change — a
  front end that scanned two roots would hide it (`bin/cc-lr:47-49` states exactly this).

---

## 5. Question (c): concrete copy-able shapes

```bash
#!/usr/bin/env bash                       # and still parse under /bin/bash 3.2 (item 5)
# <tool> — one line saying what it is, then WHY, then the rc line.
#
#   <tool> <verb> <args>      one line per verb
#
# rc 0 ok · 1 no match · 2 REFUSED (nothing created) · 3 usage
set -uo pipefail                          # -e only where the file already uses it

# resolve self THROUGH the symlink before any sibling lookup (item 20)
_X_SELF="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
_X_BIN="$(cd "$(dirname "$_X_SELF")" && pwd)"

usage() { cat >&2 <<'USAGE'
…verb lines…

rc 0 ok · 1 no match · 2 REFUSED (nothing created) · 3 usage
USAGE
}
x_die() { echo "<tool>: $1" >&2; exit "${2:-2}"; }

cmd_<verb>() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --flag) [ $# -ge 2 ] || { usage; exit 3; }; v="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      --*) echo "<tool> <verb>: unknown option $1" >&2; usage; exit 3 ;;
      *)  … ;;
    esac
  done
  # REFUSE FIRST — before any mutex, request file or child (item 13)
  # then take the mutex, then act; release it on every failure path
}

# a new behaviour: default ON, escape named (item 7)
if [ "${CC_<TOOL>_<FEATURE>:-on}" = off ]; then …pre-change behaviour, byte-for-byte… ; fi

# UTC (item 17)
date -u +%Y-%m-%dT%H:%M:%SZ

# TSV read (item 19): every non-last cell discharged with ${var:--}
IFS=$'\t' read -r a b c <<EOF
$row
EOF
printf '%s\n' "${b:--}"
```

Lint entry-point shape (items 12, 40):

```bash
# Exit: 0 clean · 1 finding(s) · 2 could not run (a NON-VERDICT, never a clean claim).
# Usage: <name>-lint.sh [ROOT] [--selftest] [--print-scope]
# Env seams: CC_<X>_OWN (own-scope) · CC_<X>_ALLOWLIST (ratchet) · CC_<X>=off (kill switch)
```
— with an embedded allowlist that **can only shrink**, an own-scope that distinguishes
ABSENT / SET-BUT-EMPTY / SET, and a `--selftest` that red-proves **both** directions.

---

## 6. Sources read

`scripts/ship-land.sh` (:1-60, :265-600, :3027-3300, :3294-4530) · `scripts/gate-select.sh`
(:1-200, :411-416) · `install.sh` (:500-600, :805-830, :988-1000) · `bin/cc-lr` (whole) ·
`bin/cc-find` (:1-90, :130-260) · `tests/cc-lr-front.bats` (whole) · `tests/install-wire-hooks.bats`
· `tests/typed-send-lint.bats` (:1-45) · `scripts/nightly-regression.sh` (:1-80, :170-180, :480-500,
:540-620) · `githooks/{pre-commit,pre-push,commit-msg}` · `bin/cc-bats` (:438) ·
`scripts/lib/detach.sh` · lints: `utc-stamp`, `pipefail-sigpipe`, `tsv-pad`, `self-path`,
`pane-spawn-coverage`, `unattended-path`, `permission-gate`, `git-identity`, `bash32-parse`,
`test-hermeticity`, `test-walltime`, `test-afunix-path`, `moving-ref-control`, `bats-kill-guard`,
`bats-testname-eval`, `bg-fd-inherit`, `fleet-manifest`, `rules-hook-budget` ·
`docs/lessons/a-gates-invocation-is-part-of-its-contract.md` ·
`docs/lessons/a-locale-pin-protects-only-the-process-that-sets-it.md` ·
`.claude/rules/agent-operating-lessons.md` · `.claude/CLAUDE.md`.
