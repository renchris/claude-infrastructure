---
status: in-progress
interfaces: FROZEN by lead 2026-07-25 pre-spawn — do not renegotiate mid-build
spec: docs/research/autonomous-relogin-100pct-design-2026-07-25.md (branch relogin-design2)
inherits: docs/plans/RELOGIN_AUTOMATION_PLAN.md (branch relogin — the frozen cc-relogin contract)
scope: Phases 0-4 CODE ONLY. No live sign-in, no account mutation, no launchd job loaded.
---

# Relogin build — frozen interface contract (Phases 0-4)

Lead freezes every cross-teammate interface HERE so no teammate blocks on another's
internals. **If reality contradicts this doc, STOP and message lead — do not improvise.**

## LANDING STATUS (read this first if you are picking this up)

**Build: COMPLETE. Landing: BLOCKED on fleet conditions, not on this code.**

State as of 2026-07-25 ~21:45: 19 commits on `feat/relogin-build` in
`/private/tmp/wt-relogin-build`, tree clean, all five teammates delivered/reviewed/merged
and shut down. **Nothing is on `origin/main` yet** — verify with
`git cat-file -e origin/main:bin/cc-relogin`.

**To finish — one command, after the box is calm:**

```bash
cd /private/tmp/wt-relogin-build
git fetch origin main && git rebase origin/main
scripts/ship-land.sh            # ONCE. Do not retry-spam.
```

Then **verify by CONTENT, never by count**: every changed path present on trunk
(`git ls-tree`) *and* `git diff <your-sha> origin/main -- <paths>` empty.

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

- `d158011` (fork-retry on the `cc-authbrowser` spawns) is committed but **not
  independently verified** — the box was too saturated to trust a local run. The ship gate
  is its verification; if it reddens, fix it there.
- `tests/cc-authbrowser.bats` binds **frozen, un-overridable ports 9341-9344**, so it is
  structurally **non-concurrent**: never run it beside itself, and after killing a run
  reap the `PPID 1` orphan stubs still holding the port
  (`ps -eo pid,ppid,command | awk '$2==1' | grep foreign-listener`). A leaked listener makes
  the *next* run fail on assertions that look unrelated to it (`argv.log: No such file`),
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
`CC_AUTHBROWSER_ACCOUNTS_BIN` (default `claude-accounts`). Tests MUST drive a fake
chrome-bin stub — **never launch real Chrome in `bats`.**

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

## 5. `bin/cc-relogin-poll` + `launchd/com.claude.relogin.plist` — cadence

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
