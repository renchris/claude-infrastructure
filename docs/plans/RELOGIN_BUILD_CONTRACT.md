---
status: complete
landed: 2026-07-26 — Phases 0-4 on origin/main (tip 174a27e0) · re-verified 2026-07-30
interfaces: FROZEN by lead 2026-07-25 pre-spawn — do not renegotiate mid-build
spec: docs/research/autonomous-relogin-100pct-design-2026-07-25.md (branch relogin-design2)
inherits: docs/plans/RELOGIN_AUTOMATION_PLAN.md (branch relogin — the frozen cc-relogin contract)
scope: Phases 0-4 CODE ONLY. No live sign-in, no account mutation, no launchd job loaded.
---

# Relogin build — frozen interface contract (Phases 0-4)

Lead freezes every cross-teammate interface HERE so no teammate blocks on another's
internals. **If reality contradicts this doc, STOP and message lead — do not improvise.**

## LANDING STATUS (read this first if you are picking this up)

**Build: COMPLETE. Landing: DONE — Phases 0-4 are on `origin/main`.**

Landed 2026-07-26. Branch tip **`174a27e0`** ("test(relogin): re-seed two status cases
against trunk's derived login countdown") is an **ancestor of `origin/main`**, and the
content diff over every deliverable path is **empty**. All five teammate branches
(`feat/relogin-{browser,executor,observability,probes,schedule}`) are **content**-upstream.
`/private/tmp/wt-relogin-build` is gone — nothing is stranded there.

> Read `git cherry` carefully here: it marks two commits `+` (`3ced668b` executor
> phase A, `7765814` observability) that ARE fully landed. A `+` means "no upstream
> commit with this patch-id", and a later phase-B commit touching the same files
> changes the patch-id of the squashed result. **Patch-id is not a landing oracle for
> a branch that was built in phases** — the deliverable-path content diff is, and it
> is empty. Cross-checked independently: `--relogin-status` and `relogin-blocked`
> both grep positive on trunk, which is `7765814`'s payload.

Re-verify by CONTENT, never by count (this is the check that was run 2026-07-30):

```bash
git merge-base --is-ancestor feat/relogin-build origin/main && echo ANCESTOR
git diff feat/relogin-build origin/main -- \
  bin/cc-relogin bin/cc-authbrowser bin/cc-relogin-poll bin/claude-accounts \
  bin/cc-blockers launchd/staged/com.claude.relogin.plist scripts/relogin-probes \
  tests/cc-relogin.bats tests/cc-authbrowser.bats tests/cc-relogin-poll.bats \
  tests/cc-relogin-status.bats        # must print nothing
git cherry -v origin/main feat/relogin-executor   # corroboration ONLY — see the
                                                  # patch-id caveat above; '+' here
                                                  # does NOT mean unlanded
```

> ⚠️ **This section previously read "Landing: BLOCKED … nothing is on `origin/main` yet"
> and shipped a `cd /private/tmp/wt-relogin-build && ship-land.sh` recipe.** That was true
> on 2026-07-25 and false from 2026-07-26 onward; the worktree it names no longer exists.
> A stale landing verdict is worse than no verdict — the next reader either re-lands
> already-landed work or mis-diagnoses the subsystem as unbuilt. **When a landing
> completes, the status line is part of the landing.**

**Runtime evidence the landed code actually works** (live logs, 2026-07-30):

- §4 precondition gate refuses correctly rather than authenticating:
  `next refused exit=2 phase=gate :: no re-auth needed — healthy (auth=ok, login_expires_h=88.7)`
- §2 degradation is LOUD rather than a confident wrong "OK":
  `WINDOW-CAPPED --window-h unsupported … this verdict does NOT cover T-7d`. ⚠️ **The
  degradation machinery worked; its trigger was a lie.** The deployed `claude-accounts` DID
  support `--window-h` — the probe that said otherwise was the `pipefail`/SIGPIPE race fixed in
  `ec9a43a9` (see the re-verification section below). Recorded because the first reading of this
  line blamed pre-M2 deploy lag, which was wrong and would have closed the investigation.
- All five bins (`cc-relogin`, `cc-relogin-poll`, `cc-authbrowser`, `claude-accounts`,
  `cc-blockers`) are symlinks into the checkout and content-match trunk — no deploy lag.

**Cadence is live** (C10 activation was done by the operator on 2026-07-30 via
`pending-activation/21-relogin-poll-activate.sh`; Phases 0-4 only ever **stage** the
plist per §0/§5 — loading it was never in this contract's scope). `com.claude.relogin`
is loaded and `enabled`, and a tick was caught live at `2026-07-30T16:31:29Z` doing
exactly the frozen thing:

```
SKIP next k=3 (>0) — cc-relogin would refuse; deadline=2026-08-02T21:19:15Z T-76h attempts=0
```

That single line confirms four §5 clauses at once against the real daemon: the k>0
cheap pre-filter, nearest-deadline selection, `attempts`-not-successes counting, and
the T−7d window being live (T−76h is inside it).

> ⚠️ **Near-miss worth keeping — an inert-daemon alarm that was WRONG.** A first pass
> read `launchctl print` as `runs = 0`, `last exit code = (never exited)`, with no
> launchd out/err logs, and was one step from filing "loaded but never fires". It had
> simply been sampled mid-interval. What broke the tie was a **positive control on a
> sibling job** — `com.chrisren.cc-reaper` showed `runs = 7` over the same ~7.2 h
> window, proving the *measurement* worked — and then catching the live tick. **A
> zero-count on a slow-cadence daemon is not evidence of death; sample it twice and
> control it against a known-live sibling before alarming.** (Open, minor, and
> downstream of this contract: relogin showed 1 run to cc-reaper's 7 on the same
> `StartInterval 3600` — cadence-lag worth a look, NOT inertness.)

## RE-VERIFICATION 2026-07-30 — suites green, and one real defect found

Behavioural gate re-run on trunk this session (not recalled):

| suite | result |
|---|---|
| `tests/cc-authbrowser.bats` | **35/35**, rc 0 |
| `tests/cc-relogin.bats` | **48/48**, rc 0 |
| `tests/cc-relogin-status.bats` | **30/30**, rc 0 |
| `tests/cc-relogin-poll.bats` | **46/46**, rc 0 — after the fix below; three consecutive runs |

Static conformance was checked clause-by-clause against §3/§4/§5/§6/§7. The safety-critical
surface holds: `--no-heal` is on **every** `claude-accounts` read in `cc-relogin`
(`fresh_row()`, the only `--fresh` call) and in `cc-relogin-poll` (both read sites); the poller
**never** acquires the heal lock (the only two mentions are comments forbidding it); exit 7
`CONSENT_GATE` is defined once and never raised ("retain, never emit"); all three probes under
`scripts/relogin-probes/` carry real executable `CONFIRM=1` guards (e1:99, e2:65, e3:78), not
just usage text; and `CC_AUTHBROWSER_PORT_BASE` correctly separates unset from set-but-empty
(`raw is None` → default; `""` falls into `not raw.isdigit()` → `EXIT_REFUSED`).

### 🚨 The defect: `pipefail` inverted the §2 detection probe (fixed, `ec9a43a9`)

```bash
if "$ACCOUNTS_BIN" -h 2>/dev/null | grep -q -- '--login-status'; then   # WRONG
```

`grep -q` exits the instant it matches, so the producer is SIGPIPEd on the **next** line it
writes; `set -o pipefail` promotes that 141 to the pipeline's status; the `if` reads FALSE for a
flag that is plainly advertised. **Measured on bash 3.2, 3-line help with the match on line 2:
FALSE 263/400 (66%); with pipefail off, 0/400.** The real `--help` prints many more lines after
the match, so production was worse.

Both §2 probes used this form, so the poller could (a) exit 3 DETECTION-UNAVAILABLE with the
surface right there, and (b) claim a spurious `WINDOW-CAPPED` and silently narrow the declared
T−7d window to 72 h. **This retro-explains the `WINDOW-CAPPED` line in the live poll log** —
earlier in this document that line is attributed to pre-M2 deploy lag; the deployed
`claude-accounts` did support `--window-h`, so the real cause was this race.

Fix: read the help **once** into a variable and match with `case` — no pipe, no SIGPIPE, one
fewer fork. `case` on a captured string is bash-3.2 safe (the known trap is `case` inside `$( )`).

**Three lessons worth carrying:**

- **It presents as flake, not failure.** Exposure needs the producer *still writing* when the
  consumer exits, so a match on the last line is safe and a match early in long output is nearly
  always wrong — which is why this suite failed a **different subset every run** (40,43 then
  38,40,42,43). A varying failing subset means collision or race, never logic.
  **Sharpened 2026-08-08:** the discriminator is not output SIZE and not "the match is not on the
  last line" — it is whether the producer makes **more than one write** after the match. A single
  `write(2)` under the 64 KiB pipe buffer lands before the consumer is scheduled, so
  `printf '%s' "$BIG"` is safe at 4 KiB (0/200) while a *streaming* producer fails **85/100 at one
  kilobyte** and 100/100 at ≥32 KiB. A four-line separate process fails 44/400. That is why the
  ratchet below exempts `echo`/`printf` producers and flags external ones.
- **Instrumentation HIDES it.** `bash -x` made it pass; wrapping the producer in a logging shim
  made it pass. Anything that slows the pipe closes the window. "Works when traced" is not
  evidence.
- **Reproduce under the shipping interpreter.** The first repro loop showed 0/300 — the lesson
  holds, but ~~because it ran under `zsh`, which does not share bash's pipefail/SIGPIPE
  interaction. The 66% only appeared under `/bin/bash`.~~ **CORRECTED 2026-08-08 — the stated
  cause is wrong. zsh is NOT immune:** re-measured, `zsh -c 'set -uo pipefail; { echo MATCH; seq
  1 200000; } | grep -q MATCH'` is **400/400 FALSE**, identical to bash. That 0/300 was a
  *single-write* producer, i.e. the safe shape, so the repro was testing the wrong thing and
  agreeing with itself. The real discriminator is below.

The new `M2c` test makes the probabilistic defect deterministic (large payload after the match)
and was RED-proven against the **exact** artifact restored from `git show`, not a hand-written
approximation.

**Same class, repo-wide — ~~NOT fixed here~~ CLOSED 2026-08-08 (backlog `791345455b58`).** The
original note read: *358 candidate sites across 102 files … candidates, not confirmed defects:
each needs triage on whether its producer keeps writing after the match. Deliberately left alone —
102 files including live hooks is far outside this contract's blast radius.* That framing was
right, and the triage it asked for has now been done.

**What the sweep actually found.** Re-derived on the current tree: 615 early-exit pipe consumers
live in the 315 files that enable `pipefail`; **367** sit in a status-consuming position; of those,
**138** have an external producer. Four parallel triage passes then *measured* each one on this box
rather than reasoning about it, and the honest answer is that **most are latent, not live** — a
`git status --porcelain` is 345 B in one flush (0/300), a `find -maxdepth 1 -name <exact>` emits
≤1 line (0/200). They flip only at volume (~1,700 dirty paths), which is why this class survived so
long: it is invisible until it isn't.

**22 sites were misfiring, several of them permanently:**

| site | measured | consequence |
|---|---|---|
| `bin/cc-cloud:244` | **5/5 FALSE** (`strings` over a 245 MB binary) | the O3 trailer version gate had been failing **100% of the time**, silently disabling session-trailer routing |
| `hooks/git-worktree-guard.sh:100` | **60/60 FALSE** | the cwd liveness leg never fired, inverting a SAFETY refusal whose own header says it can only fail OPEN |
| `bin/dia-cdp-launch.sh:123` | 79% FALSE | doctor reports "LaunchAgent not loaded" while it IS |
| `scripts/never-stuck-gate.sh:135,138` · `docs/activation/wiring-all.sh:116-128` | ~100% (`launchctl list`, 20 KiB) | launchd jobs reported NOT loaded while loaded |
| `scripts/worktree-gc.sh:596,663,730` | — | a live worktree reads idle ⇒ removable; a preserved branch reads unpreserved ⇒ never reclaimed |
| `scripts/wrap-ledger.sh:179` | — | `git cherry` ⇒ CHERRY=0 ⇒ **the wrap ledger reports "nothing unlanded" while commits are unlanded** |
| `scripts/restore-file.sh:27` | — | dies 141 before reaching `exit 0` |
| + `nightly-regression.sh`, `reaper-e2e.sh`, `cc-pane-redproof.sh`, 4 activation scripts | — | gates run their live path instead of `--selftest`; false red-proof failures |

`scripts/ship-land.sh` and `scripts/postland-verify.sh` were swept individually and are **clean**.

**One site needed a different fix, and it matters.** `git-worktree-guard.sh:100` is *not* a SIGPIPE
race: `lsof -p <list>` exits **1 on its own** whenever any pid in a ~120-pid `pgrep -f claude`
snapshot has gone away, which is the permanent steady state here. Draining the consumer does not
repair it (measured 60/60 still FALSE) — the producer's own status has to be dropped, so only
CAPTURE works. A remedy prescribed for the class would have been applied, verified by eye, and left
the guard just as broken.

**The remedy is a ratchet, not a flag-day** — the same judgment `self-path-lint.sh` made for its 26,
and now backed by measurement rather than assumption: rewriting 138 mostly-latent sites across 71
files is a larger and less reversible change than the bug. So: the 22 live sites are fixed, the
remaining 30 are grandfathered **by file with their count** in `scripts/pipefail-sigpipe-allow.txt`,
and `scripts/pipefail-sigpipe-lint.sh` (+ `tests/pipefail-sigpipe-lint.bats`, 14 tests) blocks new
ones at `run_gate` in `ship-land.sh` — the fifth deterministic blocker class. The count, rather than
a bare path exemption, is what keeps protecting files edited every week; the list can only SHRINK,
and the lint goes RED both when a file gains a violation and when one is fixed without lowering the
number.

**Known limit of the rule, stated because it is not statically fixable.** Clause 3 exempts
`echo`/`printf` producers on the measurement that a single write under the 64 KiB pipe buffer is
safe (0/200 at 4 KiB). That exemption **fails above ~64 KiB**: `printf '%s' "$V"` at 200 KB measures
0/200 TRUE — always broken. A lint cannot know a variable's runtime size, so this is a deliberate
false-negative class. Two known instances:

- `scripts/gate-cleanup.sh:84` — `$PS_SNAPSHOT` measured **237 KiB**, 3.7× the buffer. Hardened
  here with `|| true`; safe today only because no caller reads `ppid_of`'s status.
- `scripts/cloud-ceiling-probe.sh:167-168` — `$out` is an unbounded PTY capture of `claude --cloud`
  (180 s timeout) whose status IS consumed under `set -euo pipefail`. Measured 200/200 TRUE below
  64 KiB, 1/100 at 64 KiB, 0/200 at 200 KB. **NOT fixed here, deliberately:** it is hardening rather
  than one of the 22 live sites, and touching that file pulls `tests/tsv-field-collapse.bats` — red
  on trunk for an unrelated unpadded-TSV finding in the same file — into this land's own-scope.
  Carrying optional hardening at the cost of a fifth subsystem's ratchet is the wrong trade; filed
  separately instead.

If either file ever gains `set -e` on the wrong path, or a new large-variable producer appears, the
lint will not catch it.

**Landing history — three attempts, three different causes (all diagnosed):**

| # | Result | Cause |
|---|---|---|
| 1 | `SHIP_EXIT=6` | **Real gate-red in our own file** — a hardcoded `skipped=4` vs a sibling's newly-landed 6th default. Fixed `295851a`, sabotage-proven. The CAS re-gate caught a composed-tree defect neither branch had alone. |
| 2 | `SHIP_EXIT=6` | **458 ok, 0 fail** — `bats` SIGKILLed (`Killed: 9`) under load 47. Not OOM (67% mem free), not proc-cap (9%), no repo `pkill`. Cause unattributed; saturation is the fleet-wide explanation. |
| 3 | stopped by us | Fleet coordinator called a fleet-wide landing storm and asked all sessions to stand down. |

**Triage rule earned here — an exit 6 has (at least) three distinct causes.** Grep the log
before attributing: `'✗ gate: bats RED'` **with** `^not ok` lines = a real test failure;
the same message with **zero** `^not ok` plus `Killed:` = an external kill under load, not
code; a land-lock failure never presents as "bats RED" at all.

**Two caveats to carry:**

- ~~`d158011` (fork-retry on the `cc-authbrowser` spawns) is committed but **not
  independently verified**~~ — **NOW VERIFIED, and it was BROKEN. Fixed here.**
  Running the suite alone (ports free, load ~13) hung at test 13 and was killed by
  `timeout` at 300s: `EXIT=124`, 12/26 done, **0 failures** — a hang, not a test failure.
  Cause: `d158011` replaced `cmd & ; PID=$!` with `PID=$(spawn_bg cmd)`, and a **command
  substitution blocks until every holder of its stdout pipe closes it** — the backgrounded
  child inherits that pipe. So `FOREIGN=$(spawn_bg "$D/foreign-listener" 9341)` blocked for
  the listener's full `time.sleep(600)`, and each `spawn_bg sleep 4x` for its own lifetime:
  ~825 s of dead wait injected across the six call sites. Proven in isolation —
  `X=$(spawn_bg sleep 6)` takes 6 s, the same with the child's stdout redirected takes 0 s.
  Fix: redirect the child's stdout inside `spawn_bg` (no test reads it). After: **26/26 ok,
  0 not ok**, ports released, no orphans. **The lesson generalises:** this suite's own
  header now carries it, because the obvious "cleanup" is to drop the redirect.
  Note the failure *shape* — rc≠0 with **zero `not ok` lines** — is the SAME signature as
  the fleet's `cc-inbox-guard` hang and as an external SIGKILL. Three distinct causes, one
  indistinguishable surface; always separate them by `grep -ac '^not ok'` plus `Killed:`.
- ~~`tests/cc-authbrowser.bats` binds **frozen, un-overridable ports 9341-9344**, so it is
  structurally **non-concurrent**: never run it beside itself~~ — **FIXED 2026-07-26, and the
  "un-overridable" premise was the bug.** The suite was never non-concurrent by nature; it was
  non-concurrent because the port had no seam while state and profiles had two. Proven on
  pristine `main`: two simultaneous copies went **20 ok/6 not ok** and **21 ok/5 not ok**, a
  *different* failing subset each time (collision, not logic), against **26/26** solo. Because
  gate-select returns FULL for unrelated diffs, that redded **every** land on the box.
  `bin/cc-authbrowser` now resolves its block through **`CC_AUTHBROWSER_PORT_BASE`** (§1) and
  the suite leases a private block per run — **4 concurrent copies now go 32/32 each**. Still
  true and still worth doing after killing a run: reap the `PPID 1` orphan stubs
  (`ps -eo pid,ppid,command | awk '$2==1' | grep foreign-listener`), since a leaked listener
  makes the *next* run fail on assertions that look unrelated to it (`argv.log: No such file`),
  which reads as "my newest edit broke it".

## Phase 0 — Agent Team orchestration

Five worktree-isolated teammates. Wave 1 = all five (see the de-block note). Single
owner per shared file. Briefs ≤150 lines with pre-greped ranges.

| Teammate | Branch | Worktree | Deliverable | Owns (exclusive) |
|---|---|---|---|---|
| `tm/relogin-browser` | `feat/relogin-browser` | `/private/tmp/wt-rl-browser` | §3 substrate | `bin/cc-authbrowser`, `tests/cc-authbrowser.bats` |
| `tm/relogin-exec` | `feat/relogin-executor` | `/private/tmp/wt-rl-exec` | §4 OAuth executor | `bin/cc-relogin`, `tests/cc-relogin.bats` |
| `tm/relogin-sched` | `feat/relogin-schedule` | `/private/tmp/wt-rl-sched` | §5 cadence | `bin/cc-relogin-poll`, `launchd/com.claude.relogin.plist`, `tests/cc-relogin-poll.bats` |
| `tm/relogin-obs` | `feat/relogin-observability` | `/private/tmp/wt-rl-obs` | §6 observability | `bin/claude-accounts`, `bin/cc-blockers`, `tests/cc-relogin-status.bats` |
| `tm/relogin-probe` | `feat/relogin-probes` | `/private/tmp/wt-rl-probe` | §7 probe harness | `scripts/relogin-probes/`, `docs/research/RELOGIN_E1_E3_VERDICT_TEMPLATE.md` |

**Dependency graph.** `exec` consumes `browser`'s CLI — de-blocked by freezing that
contract in §3 *before* spawn (the proven pattern from the inherited plan). `sched` and
`obs` consume only exit codes and log paths, both frozen here. `probe` is independent.

**Design deviation (recorded).** The spec puts `exec` in wave 2, `blockedBy: E2`. E2
cannot run in this build (it loads a LaunchAgent — C10 operator activation), so blocking
on it would deliver nothing. Instead the substrate's launch posture is **parameterized**
(`--headless`, §3), making E2's verdict a config flip rather than a rewrite. `exec`
therefore ships in wave 1. This preserves the spec's fallback ladder (§5.1) exactly.

## 0. Universal rules (every teammate)

- **NO live sign-in. NO account mutation. NO `launchctl load`.** Nothing in this build
  may authenticate, refresh, revoke, or write a credential. Staging a plist is in scope;
  loading it is C10 operator activation.
- **Never `/logout`. Never raw-POST a refresh token. Never widen `oauth_scopes`.**
  Only the official `claude` binary performs token operations.
- Gate before commit (this repo's `/ship` runs exactly these):
  `shellcheck` (shell) · `bash -n` (shell) · `py_compile` (python, incl. extensionless
  by shebang) · `bats tests/`. Never `--no-verify`.
- Shell: `#!/usr/bin/env bash` + `set -uo pipefail`; `-h|--help` prints a leading
  comment block. Python: `#!/usr/bin/env python3`, stdlib only unless named below,
  type hints on new functions.
- Commit style: Conventional Commits, lowercase, no redundant verbs.
- Every new script must be **executable** (`chmod +x`) and **testable without side
  effects** via the env-injection knobs named in its section.

## 1. Account SSOT — read, never hardcode

`accounts.json` (repo root) is the SSOT. `claude-accounts --relogin-info <acct>` emits
the per-account identity block. Fields available (verified on `origin/main`,
`bin/claude-accounts:1237-1256`):

```
name · config_dir · launcher · email · dia_profile · dia_profile_dir
keychain_service · keychain_state · claude_bin · oauth_scopes · has_refresh_token
```

Accounts: `next` (~/.claude-next) · `next2` (~/.claude-secondary) ·
`next3` (~/.claude-tertiary) · `next4` (~/.claude-quaternary).

**Frozen port map** (explicit — NOT accounts.json file order):

| acct | CDP port | profile dir |
|---|---|---|
| next | 9341 | `~/.claude/auth-profiles/next` |
| next2 | 9342 | `~/.claude/auth-profiles/next2` |
| next3 | 9343 | `~/.claude/auth-profiles/next3` |
| next4 | 9344 | `~/.claude/auth-profiles/next4` |

> ⚠️ **Still frozen, but as a DEFAULT rather than a literal, since 2026-07-26.** The table above
> is exactly what every caller gets and the ports are unchanged — but a TCP port is a machine-wide
> singleton, and freezing it *as a constant* made the suite that exercises it unrunnable beside
> itself, which redded every land on this box (see the second caveat above). `bin/cc-authbrowser`
> now derives the block as **base + the account's index in this table**, with the base read from
> **`CC_AUTHBROWSER_PORT_BASE`** (unset ⇒ `9341`, so the frozen map is byte-identical). The
> ordering here is therefore load-bearing in a way it was not before: it is the offset contract,
> not just documentation. **Set-but-EMPTY is REFUSED (exit 2), never laundered into the default** —
> `os.environ.get(X) or DEFAULT` cannot tell unset from set-empty, and silently serving `9341` to
> a caller that asked to be moved is exactly how a run that believes it is isolated ends up on the
> real account's port. Junk and out-of-range are refused the same way, on `--stop`/`--status` too.
> **Production callers pass nothing and are unaffected**; the seam is for test isolation.

## 2. ⚠️ Version tolerance — `--login-status` is NOT on `main`

`claude-accounts --login-status` and the `login_expires_at` / `login_expires_h` /
`login_expired` / `login_fixable` fields exist ONLY on the unlanded local branch
`feat/accounts-login-cliff`. **Consumers MUST degrade explicitly, never silently:**

1. Try `claude-accounts --login-status` (TSV, exit 0 clear / 1 expiring / 2 required).
2. Absent/unsupported → `claude-accounts --fresh --no-heal --json`, read the login_* fields.
3. Fields absent too → **exit 3 DETECTION-UNAVAILABLE** with a loud log line naming
   the missing surface. Never treat "cannot detect" as "nothing to do".

`--login-status` TSV columns (when present):
`acct \t state(REQUIRED|EXPIRING) \t reason \t when \t hours \t launcher`

### 🚨 AMENDMENT (lead, 2026-07-25) — `--no-heal` is MANDATORY on every read

The originally-frozen ladder-2 string `claude-accounts --fresh --json` was **wrong and
unsafe**. Verified: `get_data(fresh, no_heal)` → `collect` → `probe_account` →
`if stale and not no_heal:` → `heal()`, and `heal()` (`bin/claude-accounts:345`) runs
`subprocess.run([cbin, "auth", "login"], ...)` — **a real credential write** — and takes
`/tmp/claude-accounts-heal-<acct>.lock`.

So the literal frozen command could (a) authenticate and rotate a token, violating §0
outright, and (b) make the poller hold the very lock §5 forbids it to hold, arriving
through the detection side door. **Every read in this build — poller detection,
`--relogin-status`, and `cc-relogin`'s before/after verify reads — uses `--no-heal`.**

For `cc-relogin` specifically this also protects the *proof*: verify-by-effect is only
evidence if the measuring read cannot itself move the state being measured.

Surfaced by `tm/relogin-sched`, which flagged rather than silently complying. Enforced by
regression tests in each consumer's suite.

**Probe detection support POSITIVELY, from the help text — never from an exit code.** On
`main` an unknown flag falls through to the human table with **exit 0**, which an
exit-code check reads as "all clear" — exactly the silent-inert failure this section
exists to prevent.

## 3. `bin/cc-authbrowser` — the substrate (FROZEN by lead)

Owner: `tm/relogin-browser`. Python 3, stdlib only. The dedicated per-account Chrome.

```
cc-authbrowser <acct> --start [--ttl N] [--headless] [--json]
cc-authbrowser <acct> --stop
cc-authbrowser <acct> --status [--json]
```

- **`--start`** — direct-exec `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`
  (**never** `open -n` / LaunchServices) with, at minimum:
  `--user-data-dir=<profile dir §1>` · `--remote-debugging-port=<port §1>` ·
  `--remote-debugging-address=127.0.0.1` · `--window-position=-32000,-32000`
  (headed-offscreen — the correct posture; `--headless=new` advertises a
  `HeadlessChrome` UA) · `--no-first-run` · `--no-default-browser-check`.
  Poll `http://127.0.0.1:<port>/json/version` until it answers (≤15 s) then print JSON:
  `{"acct","pid","port","ws_url","profile_dir","user_agent","headless":bool}`.
- **`--headless`** — opt-in `--headless=new` fallback for the §5.1 E2 ladder. **Default
  is headed-offscreen.** This flag is the entire E2-verdict surface: if launchd-proper
  survival fails, the operator flips this on — no code rewrite.
- **`--stop`** — kill the recorded pid, remove the state file. **Idempotent**: exit 0
  when nothing is running. Must leave **no** listening port.
- **TTL watchdog** — `--start` also arms a detached watchdog that hard-kills the browser
  after `--ttl` seconds (default 300) **even if the caller dies**. An open CDP port must
  never outlive a run. The watchdog must not kill a *different* process if the pid was
  recycled — re-verify the pid's command line before killing.
- **Port safety** — if the port is already listening and is NOT our recorded pid, exit 4
  (never adopt a foreign browser; never kill it).
- State file: `<CC_AUTHBROWSER_STATE_DIR>/cc-authbrowser-<acct>.json`.

**Exit codes (frozen):** `0` OK · `1` ERROR · `2` REFUSED (unknown acct / bad args) ·
`4` BROWSER-FAILED (chrome binary missing · CDP not up in time · port held by a
foreign process).

**Ratified during the build (lead, 2026-07-25) — six points §3 left underspecified:**

1. 🚨 **`--status` exits 0 whether or not a browser is running.** A successful query is
   exit 0; the frozen codes reserve nonzero for failure. **Consumers MUST read `.running`
   (bool) from `--status --json` and MUST NOT branch on the exit status.**
2. `--start` **always** emits the frozen JSON; `--json` is accepted as a no-op there and
   is meaningful on `--status`. Both call shapes therefore agree.
3. Hidden internal subcommand `--watchdog --pid N --ttl S --match STR` (argparse-suppressed,
   absent from `--help`). The TTL watchdog is a **detached re-exec of the script itself** —
   that is how it survives the caller's death — and it makes the pid-recycle guard directly
   testable. Not part of the frozen `--start|--stop|--status` surface.
4. (a) If the watchdog fails to arm, `--start` tears the browser down and exits 4 rather
   than leave an unbounded CDP port. (b) If CDP answers but our direct child has exited
   (re-exec / hand-off), the port-holding pid is re-resolved via `lsof` — otherwise
   `--stop` would leave a listening port, which §3 forbids.
5. `--start` when the port is held by **our own** recorded pid → idempotent re-emit of the
   state JSON, exit 0. Exit 4 is for a **foreign** holder only.
6. SSOT validation is `--start`-only: `--stop`/`--status` validate against the frozen port
   map alone, so a browser can always be shut down even if `claude-accounts` is broken. A
   missing/erroring `claude-accounts` on `--start` is exit 2 (fail-closed).

### Test discipline — bare `!` assertions are DEAD (repo-wide defect, verified)

A bare `! cmd` in a bats `@test` is a **silent no-op unless it is the last statement** —
POSIX exempts `!`-inverted pipelines from errexit. 89 such assertions across 28 files in
this repo are structurally dead. Use `refute() { run "$@"; [ "$status" -ne 0 ]; }`, and
prove the fix by breaking the implementation and confirming the test goes RED. Full
finding + reproduction + file list: `docs/research/BATS_DEAD_ASSERTIONS_2026-07-25.md`.

**Test-injection env:** `CC_AUTHBROWSER_CHROME_BIN` · `CC_AUTHBROWSER_PROFILE_ROOT`
(default `~/.claude/auth-profiles`) · `CC_AUTHBROWSER_STATE_DIR` (default `/tmp`) ·
`CC_AUTHBROWSER_PORT_BASE` (default `9341` — see §1; set-but-empty/junk/out-of-range is
REFUSED, never defaulted) · `CC_AUTHBROWSER_ACCOUNTS_BIN` (default `claude-accounts`).
Tests MUST drive a fake chrome-bin stub — **never launch real Chrome in `bats`**, and
never bind a frozen 934x port: `tests/cc-authbrowser.bats` leases a private block per run.

## 4. `bin/cc-relogin` — the OAuth executor

Owner: `tm/relogin-exec`. Contract inherited VERBATIM from
`docs/plans/RELOGIN_AUTOMATION_PLAN.md` (branch `relogin`, § "CLI contract (FROZEN
2026-07-24)") with exactly ONE change: **the substrate is `cc-authbrowser` (§3), not
Dia on 9222.**

```
cc-relogin <acct> [--dry-run] [--no-browser] [--json] [--url-timeout N] [--debug]
```

**Exit codes (frozen, unchanged):** `0` PROVEN · `1` ERROR · `2` REFUSED ·
`3` HEADLESS-EXHAUSTED · `4` BROWSER-FAILED · `5` UNVERIFIED · `6` FALLBACK-REQUIRED ·
`7` CONSENT-GATE — **retain the code, NEVER emit it** (the dedicated-profile substrate
makes the condition structurally impossible; it is dead code kept for consumer
compatibility).

Substrate delta vs the inherited contract: replace "one raw WS to Dia's WS-only 9222 +
`browserContextId`→profile mapping" with `cc-authbrowser <acct> --start` → use the
returned `ws_url` → **full HTTP CDP is available** (`/json/version`, `/json/list`) →
`Target.createTarget(<oauth url>)` (no browserContextId mapping needed — the profile IS
the browser) → Authorize via `DOM.getBoxModel` + `Input.dispatchMouseEvent`
(`el.click()` fallback) → **`cc-authbrowser <acct> --stop` in a `finally`, always.**

Everything else is unchanged and non-negotiable: the precondition gate
(`--relogin-info` identity · refuse unless genuinely needed · refuse `k>0` ·
`flock(LOCK_EX|LOCK_NB)` on `/tmp/claude-accounts-heal-<acct>.lock` **held for the whole
run** · re-check `k==0` UNDER the lock), Phase 1 headless-first, **verify by EFFECT**
(`--fresh --json` `auth=="ok"` AND `after.login_expires_at > before.login_expires_at`),
the `--json` result object, and cleanup-always.

## 5. `bin/cc-relogin-poll` + `launchd/staged/com.claude.relogin.plist` — cadence

Owner: `tm/relogin-sched`.

```
cc-relogin-poll [--json] [--dry-run] [--once] [--trigger-days N] [--escalate-hours N]
```

- Hourly. **Trigger at T−7d** (`--trigger-days`, default 7) — not the 72 h warn — so one
  fragile attempt becomes ~168 chances to catch a `k==0` window.
- **Escalate at T−48h** (`--escalate-hours`, default 48) with no window yet found: stop
  retrying silently, raise the class-C row (§6). **Fail loud BEFORE the deadline.**
- **Idempotent** — a deadline already moved is a no-op next tick.
- **At most ONE account per tick**, nearest-deadline first (staggering).
- 🚨 **The poller NEVER takes the heal lock.** `cc-relogin` holds
  `/tmp/claude-accounts-heal-<acct>.lock` for its whole run; a poller that took it would
  deadlock its own child. The poller MAY read `k` as a cheap pre-filter to skip a doomed
  invocation — the authoritative gate stays inside `cc-relogin`.
- Count **attempts, not successes**, and log stderr — the bound must cover the failure
  mode it bounds. Log: `~/.claude/logs/cc-relogin-poll.log`.
- Exit: `0` nothing due / renewed · `1` error · `3` DETECTION-UNAVAILABLE (§2) ·
  `5` ESCALATED (class-C row raised).

**Plist** — mirror the proven `com.chrisren.cc-reaper.plist` shape verbatim:
`/bin/zsh -lc` + **`export PATH="$HOME/.claude/bin:$PATH";`** (`-lc` does NOT source
`.zshrc`) · `StartInterval 3600` · **`RunAtLoad false`** · `ProcessType Background` ·
`StandardOutPath`/`StandardErrorPath` under `~/.claude/logs/`. **Stage the file only —
never `launchctl load` it.** Add a leading XML comment naming the C10 activation step.

## 6. Observability

Owner: `tm/relogin-obs`. **Single owner of `bin/claude-accounts` and `bin/cc-blockers`
— no other teammate edits these two files.**

- **`claude-accounts --relogin-status`** — one row per account: acct · state
  (`OK|DUE|ESCALATED|UNKNOWN`) · login_expires_at · hours · last attempt (ts+result from
  the poll log) · next action. `--json` variant. Exit `0` all clear · `1` a renewal is
  due · `2` escalated/overdue. Must honor §2 version tolerance (`UNKNOWN`, never a
  confident wrong "OK"). Reads the shared cache like every other mode — a recurring
  check must never force an endpoint sweep.
- **class-C row** — `cc-blockers` currently renders only `kind=="safeguard-blocked"` from
  the IDL board (`$CC_REAPER_IDL`, default `~/.claude/autonomy/idl.jsonl`). Extend it to
  ALSO render `kind=="relogin-blocked"` rows, each carrying `recover_cmd` = the **exact
  runnable command** (Silver-Platter rule — never a paraphrase). Keep cc-blockers
  READ-ONLY and robust to malformed lines (`fromjson?`). Dedup: latest row per acct.
- **Log rotation** — add `cc-relogin*.log` to the existing autonomy log rotation.

## 7. Probes (harness only — NOT run)

Owner: `tm/relogin-probe`. Deliverable = the E1/E2/E3 **experiment scripts + a written
verdict template**. 🚨 **DO NOT RUN THEM.** E1 and E3 require a real browser Authorize
(human-gated); E2 loads a LaunchAgent (C10 operator activation). Each script must
**refuse to run without an explicit `CONFIRM=1`** and print exactly what it will do and
what it will touch. No production code.

## 8. Phase 5 — de-sharing (lead-owned, DEFAULT OFF)

Built behind a flag, inert by default, **not activated**. Gated on E1's verdict and the
operator's §4.4 Variant-A-vs-B call. No teammate implements this.
