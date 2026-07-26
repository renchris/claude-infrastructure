---
status: in-progress
---

# /relogin — fully autonomous account re-authentication

> **State 2026-07-26:** all code LANDED and gate-green (see the last section). Deliberately NOT
> `complete`: the autonomous loop is not yet *live*. Three C10 operator steps remain — warm each
> auth-profile once, run E1-E3 (`CONFIRM=1`), load the LaunchAgent. Kept `in-progress` so it stays
> on the open list until the cadence actually ticks; marking it complete would assert an
> unattended re-auth that has never run.

**Goal.** Turn `skills/account-relogin` (a human-followed runbook) into a command that
re-authenticates one Claude Max account end-to-end with no human step, and wire it to the
login-cliff detection that `claude-accounts --login-status` now provides.

**Why now.** The login cliff is real, hard, and roughly monthly per account
(`refreshTokenExpiresAt`, anchored to the last interactive login; no refresh extends it —
see `docs/research/` + the `feat/accounts-login-cliff` branch). Today the *detection* is
automated and the *fix* is a human typing `/login`. That is the last manual step in the
account layer, and it recurs ~4×/month across the fleet.

---

## Phase 0 — Agent Team Orchestration

Two code-writing surfaces + one verification surface. Sized for **2 teammates**; the lead
does the live E2E itself (it needs the real keychain and cannot run in a worktree sandbox).

| Teammate | Owns | Deliverable | blockedBy |
|---|---|---|---|
| `relogin-driver` | `bin/cc-relogin` — the CDP + fifo driver | ≤400 LOC + `tests/cc-relogin.bats` | — |
| `relogin-wire` | `commands/relogin.md`, `skills/account-relogin` update, `--login-status` → autofix hook | command + doc + wiring | driver's CLI contract frozen first |

Lead: freeze the `bin/cc-relogin` CLI contract (flags + exit codes) BEFORE spawning, so
`relogin-wire` is not blocked on the driver's internals. Both in their own worktrees.

---

## Verified facts (established 2026-07-25 — do NOT re-derive)

These were measured on this machine this session. They are the load-bearing premises.

1. **All four Dia profiles hold warm `claude.ai` session cookies, valid to 2027-08-14.**
   Read from each profile's `Cookies` SQLite DB under
   `~/Library/Application Support/Dia/User Data/<profile-dir>/Cookies`:

   | account | Dia profile | claude.ai cookies | latest expiry |
   |---|---|---|---|
   | next | Personaly | 20 (3 session-ish) | 2027-08-14 |
   | next2 | Claude2 | 21 (4 session-ish) | 2027-08-14 |
   | next3 | Claude3 | 18 (3 session-ish) | 2027-08-14 |
   | next4 | Claude4 | 18 (3 session-ish) | 2027-08-14 |

   **⇒ Phase 2b (the email-code fallback) is NOT on the main path.** A warm claude.ai session
   means the OAuth authorize page renders an Authorize button directly. The email leg is the
   rare fallback (profile session ALSO logged out), not the common case. This is the single
   most important finding: it removes the mail dependency from the critical path.

2. **Dia is running with CDP reachable on port 9222.**
   `~/Library/Application Support/Dia/User Data/DevToolsActivePort` → `9222` +
   `/devtools/browser/<id>`. (The `dia-agent` skill documents this as an *ephemeral* port —
   here it is the standard one. Read the file, never assume either.)

3. **The headless login surface exists on the live binary** (2.1.215):
   `claude auth login [--claudeai] [--console] [--email <email>] [--sso]`.
   Confirmed by `--help`, not by memory.

4. **The MS Graph token cache covers exactly ONE mailbox** —
   `~/.cache/outlook-cleanup-token.json` → `ren.chris@outlook.com`, which is **next3's**
   mailbox. The other three need a one-time device-code sign-in before any headless mail
   read works for them. Given (1), this only matters for the fallback.

5. **There is NO MS365 / Microsoft MCP server configured.** The only MCP server in
   `~/.claude.json` is `browsermcp`. The Anthropic-hosted MCPs available are Google
   (Gmail / Calendar / Drive) and all are UNAUTHENTICATED — and every account mailbox is
   `@outlook.com` / `@hotmail.com`, so the Gmail MCP could not serve them even authenticated.
   Do not design around an MS365 MCP; it does not exist here.

6. **`/login` is not callable by an agent.** It is an interactive TUI slash command inside a
   running Claude Code session; an agent cannot type into its own TUI. The automatable
   surface is the `claude auth login` subprocess with piped stdin — a different mechanism,
   already documented in `skills/account-relogin` Phase 2.

---

## Design

`bin/cc-relogin <acct> [--dry-run] [--no-browser]`, driving the existing runbook:

1. **Precondition gate.** `claude-accounts --relogin-info <acct>` → refuse unless the account
   genuinely needs it; refuse when `k > 0` (a live CC owns the token lifecycle — the same
   invariant `heal()` enforces); take `/tmp/claude-accounts-heal-<acct>.lock` so this can
   never race the auto-heal. **These three guards are non-negotiable.**
2. **Phase 1 first** when `refresh_token_expired: false` — the headless refresh grant is
   cheaper and browser-free. Skip straight to Phase 2 when the stamp has passed (it cannot
   succeed by construction) or when `auth == login-required` from a *rejected* grant.
3. **Phase 2**: `mkfifo` + held-open writer → `claude auth login --claudeai --email <e>` →
   poll stdout for the OAuth URL (≤30s, fail loud) → CDP `Target.createTarget` in the
   account's `browserContextId` (resolved by profile NAME via `chrome://version` →
   `#profile_path`; dirs drift) → click Authorize via AX tree + `Input.dispatchMouseEvent`
   (isTrusted; `el.click()` is the documented fallback) → scrape `code#state` if the CLI is on
   the paste path → write to the fifo.
4. **Verify by EFFECT, never by report**: `claude-accounts --fresh --json` must show
   `auth: ok` AND a `login_expires_at` further out than before. A "Login successful." string
   is a claim; the new expiry stamp is the proof.
5. **Fallback (rare)**: profile session cold → Graph device-code path for next3's mailbox,
   else surface to the operator with the exact remaining step.

**Wiring**: `claude-accounts --login-status` exit 2 → offer/auto-run `cc-relogin`. Keep the
autofire behind a flag until it has succeeded manually several times.

---

## bin/cc-relogin — CLI contract (FROZEN 2026-07-24, pre-spawn)

`cc-relogin <acct> [--dry-run] [--no-browser] [--json] [--url-timeout N] [--debug]`
Python 3, one executable file. Deps: stdlib + `websocket-client` (1.6.1).

> **Correction 2026-07-26 — "installed system-wide" was false where it matters.** The Framework
> 3.11, Homebrew and `/usr/local` interpreters all carry `websocket-client`, which is why the
> claim read as true; `/usr/bin/python3` does NOT. The shebang is `#!/usr/bin/env python3`, so
> PATH decides — and under **launchd**, which is how the staged poller will run this, PATH carries
> neither Homebrew nor the Framework and resolves exactly the one interpreter without the dep.
> Before activating the LaunchAgent, either install the dep for `/usr/bin/python3` or pin the
> interpreter in the plist. A missing dep is now reported as exit **1** naming the interpreter and
> the `pip install` (see the exit table), not as `browser-failed`.

**Exit codes** (consumers key on these — frozen):

| exit | name | meaning |
|---|---|---|
| 0 | PROVEN | re-auth verified by EFFECT (below), never by the binary's report |
| 1 | ERROR | unexpected failure · **also: `websocket-client` absent for the running interpreter** — a dependency fault in this driver's own environment, deliberately NOT `browser-failed` (nothing was asked of the browser); the detail names `sys.executable` and the `pip install` |
| 2 | REFUSED | gate: unknown acct · account healthy · `k > 0` · heal lock busy |
| 3 | HEADLESS-EXHAUSTED | `--no-browser` given and Phase 1 impossible or failed |
| 4 | BROWSER-FAILED | Phase 2 mechanics: no OAuth URL within `--url-timeout` (default 30s) · CDP unreachable · profile ctx unmatched · no Authorize control · callback timeout. **Not** a missing local dep (→ 1) and **not** a blocked consent (→ 7) |
| 5 | UNVERIFIED | binary claimed success but the effect check failed — treat as NOT re-authed |
| 6 | FALLBACK-REQUIRED | authorize URL landed on claude.ai `/login` (web session cold) — email-code leg not automated; stdout carries the exact remaining human step incl. mailbox |
| 7 | CONSENT-GATE | CDP blocked: `DevToolsActivePort` absent (toggle off) or WS handshake hung >8s (consent dialog pending); stdout names the recovery: cycle `dia://inspect#remote-debugging` off→on, re-run — first connect after a cycle is consent-free |

> ⚠️ **Rows 4 and 7 are superseded as of 2026-07-26 — the table stays for provenance, not as
> current behaviour.** The dedicated-browser substrate removed the Dia dependency, so **nothing
> emits 7** any more (it is retained only so consumers keying on it still compile), and row 4's
> "profile ctx unmatched" is gone with it — a 4 now means `cc-authbrowser --start` failed, emitted
> no `ws_url`, CDP was unreachable, no Authorize control, or the callback deadline passed.
> Likewise `CC_RELOGIN_DEVTOOLS_PORT_FILE` below no longer exists (no consumer ever passed it);
> the substrate's seam is `CC_RELOGIN_AUTHBROWSER_BIN`. See the 2026-07-26 section for why.

**`--json`** → single object on stdout:
`{"acct","result":"proven|refused|headless-exhausted|browser-failed|unverified|fallback-required|consent-gate|error","exit":N,"phase_reached":"gate|phase1|phase2|verify","before":{"auth","has_refresh_token","login_expires_at"},"after":{…},"detail":"…"}`

**Test-injection env**: `CC_RELOGIN_ACCOUNTS_BIN` (default `claude-accounts`),
`CC_RELOGIN_DEVTOOLS_PORT_FILE` (default Dia's `DevToolsActivePort`), `CC_RELOGIN_TMP`
(default `/tmp`), `CC_RELOGIN_WARN_H` (default 72). claude binary, config dir, email,
scopes come ONLY from `--relogin-info` (SSOT; scopes passed verbatim, never widened).

**Gate**: relogin-info → identity; need-relogin predicate from `--fresh --json` row —
`auth ∈ LOGIN_FIXABLE {logged-out, token-invalid, no-oauth-blob, login-required}` OR
`login_expired` OR `login_expires_h ≤ warn` (fields absent on a pre-cliff claude-accounts →
fall back to keychain/has_refresh_token/auth-actionable); `k == 0`; then
`flock(LOCK_EX|LOCK_NB)` on `/tmp/claude-accounts-heal-<acct>.lock` HELD for the whole run,
with k re-checked UNDER the lock via `ps -wwEo command=` (argv[0]==claude_bin +
`CLAUDE_CONFIG_DIR`, skip `-p/--print` — mirrors `concurrency()`).

**Phase 1** iff `has_refresh_token && refresh_token_expired != true`: RT from
`security find-generic-password -s <keychain_service> -a <keychain_account> -w` →
`claudeAiOauth.refreshToken`; `CLAUDE_CONFIG_DIR` + `CLAUDE_CODE_OAUTH_REFRESH_TOKEN` +
`CLAUDE_CODE_OAUTH_SCOPES` → `<claude_bin> auth login`, 90s timeout (mirrors `heal()`).

**Phase 2**: fifo `/tmp/cc-relogin-<acct>.in` opened **O_RDWR by the driver** (never blocks,
never EOFs) → `<claude_bin> auth login --claudeai --email <email>` stdin=fifo,
out→`/tmp/cc-relogin-<acct>.out` → poll for the printed manual OAuth URL (the CLI also
auto-opens a localhost variant in the default browser — ignore, shared state+PKCE) →
ONE raw WS to `ws://127.0.0.1:<port><path>` from the port file, `suppress_origin=True`,
handshake timeout 8s (WS-only endpoint — NO `/json` discovery) → flat sessions
(`Target.attachToTarget flatten:true`): map browserContextId→profile by `createTarget
chrome://version` + `#profile_path` endswith `dia_profile_dir`, close probe tab →
`createTarget(<oauth url>, ctx)` → find Authorize button → `DOM.getBoxModel` +
`Input.dispatchMouseEvent` press/release (`el.click()` fallback). Outcomes: (a) child
prints success (warm session, localhost callback) → verify; (b) page shows `code#state` →
scrape → write to fifo → wait child → verify; (c) lands on `/login` → exit 6.
Cleanup ALWAYS: kill child, close WS, rm fifo; keep `.out` on failure (path printed).

**Verify by EFFECT**: `--fresh --json` row `auth == "ok"` AND relogin-info
`has_refresh_token == true` AND (`before.login_expires_at` null OR
`after.login_expires_at > before.login_expires_at`) → 0, else 5.

**`--dry-run`**: gate reads + phase plan printed, lock probed (take+release), nothing mutated.

---

## Hard constraints

- **Never `/logout`** as a "fix" — it revokes the grant and deletes the keychain item.
- **Never raw-POST a refresh token and discard the response** — tokens may rotate
  (GH anthropics/claude-code#54443) and a discarded rotation IS a logout. Only the official
  binary touches tokens.
- **Never relogin an account with live sessions** (`k > 0`).
- **Never widen `oauth_scopes`** beyond the SSOT value in `accounts.json`.
- Work in your OWN worktree on your OWN branch; land via the project-local `/ship`. This repo
  is the symlink source for `~/.claude` — never commit in the shared checkout.
- The `dia://inspect` remote-debugging toggle is a **security surface**: if you turn it on,
  turn it off at the end and verify no ephemeral-port Dia listener remains.

---

## Live test cases (in order)

1. **next3** — `auth: login-required` (refresh grant rejected, HTTP 400), `k = 0`, mailbox
   covered by the Graph cache. The ideal first target: it needs re-auth anyway, it cannot be
   fixed headlessly, and every fallback is available for it.
2. **next4** — login expires **2026-07-25 12:39 local** (~18h from this plan's writing) and it
   is currently the router's pick for BOTH general and Fable lanes. If cc-relogin is not
   proven by then, do it manually rather than let it lapse — a lapsed next4 leaves `next`
   alone as the routable fleet (`next2` is at ~97% weekly).

## Status log

- **2026-07-25** — plan created. Feasibility established (facts 1-6 above); the decisive
  finding is (1): warm profile sessions remove the mail dependency from the critical path, so
  the missing MS365 MCP does not block the design. Nothing built yet.
- **2026-07-24 (build session)** — branch `relogin` rebased onto `feat/accounts-login-cliff`
  (the wiring consumes its `--login-status` / `refresh_token_expires_*` surfaces; that branch
  also already updated `skills/account-relogin/SKILL.md`, avoiding a land-time conflict — the
  chain lands together via `/ship`). CLI contract frozen above. Two live findings beyond the
  plan's facts: (a) the 9222 CDP endpoint is the **WS-only** flavor — no `/json` HTTP
  discovery, everything rides one raw WS to `/devtools/browser/<id>` with flat sessions;
  (b) a fresh WS connect **hangs in handshake on the Dia consent dialog** (CAUSE UNATTRIBUTED —
  see the 2026-07-25 correction below) → exit 7 CONSENT-GATE added to
  the contract; recovery = toggle off→on cycle, then ONE persistent connection per batch
  (dia-agent skill, verified 2026-06-17). Live fleet re-check: next3 `k=0`,
  `has_refresh_token: false`, keychain present → Phase 2 is the only path (as designed);
  next4 `k=4` → cc-relogin's k-guard rightly refuses it, operator handles next4 manually
  before its 2026-07-25 12:39 deadline.

---

## 2026-07-25 correction + session post-mortem (from the originator, F598FC1F)

**The consent-gate CAUSE was misattributed.** The entry above originally read "the plan's
feasibility session consumed the consent-free first connect". That is false. The feasibility
session never opened a CDP or WebSocket connection at all — its only Dia reads were `cat` of
`DevToolsActivePort` and `sqlite3` reads of each profile's `Cookies` file, neither of which
touches CDP. `DevToolsActivePort` still held `9222` with an mtime PREDATING those reads.

The CONSENT-GATE finding itself stands and exit 7 should be kept — a fresh WS connect really
does hang in handshake. Only its cause is unknown. **Do not design the recovery around a
consumer that has not been identified**: establish who or what actually holds the consent
state first. (A correction was sent to the fired session's inbox via `cc-notify` but the
session ended before draining it — hence this durable edit.)

**Session outcome: the build did NOT happen.** The fired session (`relogin-9BFAFBBB`,
Fable 5 @ xhigh) produced this plan's contract section and then ended without a completion
ping — no `bin/cc-relogin`, no `commands/relogin.md`, no tests. What survives is real and
worth keeping: the frozen CLI contract, the result-JSON shape, and the two CDP findings.
Everything downstream of "freeze the contract" is still TODO.

**The deadline resolved WITHOUT this automation.** By 2026-07-25 22:35 all four accounts read
`auth: ok` and `claude-accounts --login-status` exits 0, with next4 and next3 both carrying
refresh-token expiries ~28 days out. There are NO heal or login events in
`~/.claude/logs/claude-accounts.log` for that window and `cc-relogin` was never built, so this
was an operator-driven interactive `/login`, not an automated re-auth. The cliff is closed
until roughly 2026-08-23 — which is the next natural window to prove cc-relogin against, with
no deadline pressure.

**Re-entry note:** next3 was the intended first live test and is now `auth: ok`, so the
convenient always-broken test target is gone. Either wait for the next cliff, or test against
a deliberately-staled account with the k-guard and the heal lock both exercised.

---

## 2026-07-25 — BUILT (`feat/cc-relogin`)

`bin/cc-relogin` implements the frozen contract; `/relogin` (`commands/relogin.md`) is the
command surface; `skills/account-relogin` now points at the tool and keeps ownership of the two
human-gated exits; `commands/accounts.md` step 4 routes to it. 13 new tests
(`tests/cc-relogin.bats`), 81/81 across the four affected suites.

**Proven:** the gate end-to-end against the REAL fleet — all four live accounts refuse with
exit 2 ("does not need a relogin"), reading the real dashboard and real `--relogin-info`. The
k>0 guard, the shared heal-lock interlock, verify-by-effect and the CONSENT-GATE classification
are each RED-proofed (each guard removed in turn ⇒ its test fails; restored ⇒ passes).

**NOT proven — the honest gap:** no account has needed a real re-auth since the tool existed,
so **Phase 2 has never driven a live OAuth flow**. Unexercised: the CDP context→profile match,
the Authorize click, the `code#state` scrape, and the fifo hand-back. Treat the first real run
as a supervised test, not a routine one. Next natural window is the ~2026-08-23 cliff.

**Fixed on the way:** `tests/handoff-fire-account-sweep.bats`'s lock-contention test used a
fixed `sleep 0.5` before asserting the contended path. On a loaded machine python had not yet
acquired the lock, so the sweep healed instead of deferring and the test failed — it asserted
the outcome without asserting its own precondition. Now the holder writes a marker on
acquisition and the test waits for it, then asserts it. A concurrency test that does not
confirm the contended state is testing the uncontended one.

**Deliberately NOT done:** `--login-status` exit 2 does not auto-fire `cc-relogin`. Credentials
are the one place an unattended retry loop must not be invented; the wiring offers it, a human
or an explicit `/relogin` pulls the trigger. Revisit only after several unattended successes.

---

## 2026-07-26 — CONVERGED + LANDED (backlog item `38a8fdc28453`)

**Scope (frozen):** drive this ONE backlog item to finished-verified-landed.

The item's work existed but sat **unlanded across 10 branches**. This session adjudicated them
and landed the union: `feat/relogin-build` (19 commits), `feat/relogin-executor`'s 3 unique
commits, `docs/relogin-research`, `relogin-design2`, plus the 3 new commits below. 229 tests
green across the 9 affected suites (0 not-ok, 0 skipped, every TAP plan complete — no truncation).

**The decisive finding — the consent gate is gone, and that is what makes this autonomous.**
The 2026-07-25 build drives the *shared warm Dia* over CDP on 9222, so it depends on the
`dia://inspect` consent dialog — a human action, and precisely why exit 7 CONSENT-GATE had to be
invented. `feat/relogin-executor` + `bin/cc-authbrowser` replace that with a **dedicated
per-account Chrome**: persistent profile `~/.claude/auth-profiles/<acct>`, frozen port,
direct-exec (survives a launchd context, unlike `open -n`), detached TTL watchdog with a
pid-recycle guard. A dedicated profile has **no per-connection consent dialog**, so exit 7 became
structurally unreachable (retained for consumers; a suite assertion pins that nothing emits it).
That is the difference between a tool a human must babysit and one a LaunchAgent can run.

**Now on trunk beyond the old build:** the cadence layer (`cc-relogin-poll` — hourly, ≤1 account
per tick, fires at **T−7d** because the `k == 0` window needs days of chances rather than hours,
escalates to the operator board at **T−48h**), the substrate (`cc-authbrowser`),
`claude-accounts --relogin-status`, the class-C blocker row, log rotation, `cc-config-slot`
(inert Variant-A token de-sharing), the E1-E3 probe harness,
`docs/runbooks/RELOGIN_ACTIVATION.md`, and the staged `launchd/com.claude.relogin.plist`.

**Two defects found in the convergence itself** — both would have shipped silently:

1. **The executor rewrite dropped trunk's `b6961d5`.** `phase2()`'s broad `except Exception`
   swallowed a missing-`websocket-client` `ImportError` into exit **4 BROWSER-FAILED**, sending
   the operator to fix a browser that had started perfectly, for a pip problem — the exact
   misdirection `b6961d5` was written to end. Fixed by raising a named `Bail(EXIT_ERROR)` at the
   import and giving a NAMED fault precedence over the broad catch. RED-proofed both ways (drop
   the `except Bail`, drop the `ImportError` catch → the test fails each time); the dep is
   stubbed absent on `PYTHONPATH`, never skipped on, so the test is machine-independent.
2. **All three consumer surfaces advertised a FALSE human gate.** `/relogin`, `/accounts` step 4
   and the skill still told the operator to cycle `dia://inspect` on exit 7 — a hand-step for a
   path that can no longer fire, on the surfaces read while an account is locked out. Rewritten
   to name the real substrate, keep **exit 6 as the one genuine human gate**, and mark 7
   retained-but-unreachable. The Dia route survives in the skill, relabelled as the by-hand
   fallback it now is.

**The interpreter prerequisite is already satisfied — measured, not assumed.** The contract note
at §CLI contract says to install `websocket-client` for `/usr/bin/python3` or pin the interpreter
before activating the LaunchAgent. Probed directly: the plist invokes `/bin/zsh -lc`, and a login
shell picks up `/etc/zprofile`'s `path_helper`, which puts the Framework 3.11 on PATH ahead of
`/usr/bin/python3` — and that interpreter HAS the dep. Re-verify with:

```bash
/bin/zsh -lc 'export PATH="$HOME/.claude/bin:$PATH"; command -v python3; python3 -c "import websocket"'
```

⚠️ This is a property of the **login shell**, not of launchd. Do not "simplify" the plist to a
bare `ProgramArguments` exec or drop `-l` — that reintroduces the `/usr/bin/python3` fault the
contract warns about. Recorded so the operator does not do unnecessary work, and so nobody
removes the thing that is silently load-bearing.

**Corrected a false verdict in my own triage** (`docs/research/STRANDED_EXPOSURE_2026-07-26.md`):
it listed `feat/relogin-executor` as "wholly contained in `feat/relogin-build`" and slated it for
deletion. `feat/relogin-build` does not touch `bin/cc-relogin` **at all**, so it cannot contain a
rewrite of it — the row was generalised from the shared *stem* commit. Deleting it would have
reverted the item to human-gated while every doc claimed autonomy. Inverted too:
`feat/relogin-observability`, slated to LAND, is the genuinely redundant one (build is strictly
newer on the same lines). **Rule: patch-id is a SCREEN, not a verdict** — for a claimed superset,
confirm by content that it even *touches* the file the subset's headline patch modifies.

**Newly proven against the REAL fleet this session** (beyond the stub suites — these are live
reads, no mutation):

- `claude-accounts --relogin-status` reads all four accounts with real deadlines and states.
- `cc-relogin-poll --dry-run --json` → `{"detection":"login-status","trigger_days":7,
  "candidates":0,"action":"none","exit":0}`. That resolves the cadence layer's detection against
  the live SSOT — **not** the `DETECTION-UNAVAILABLE` degradation — plus the T−7d arithmetic and
  the no-op path. The step-5 landing dependency in the activation runbook is therefore CLOSED:
  `feat/accounts-login-cliff` has landed and the branch is gone (verified by content on `main`).

**Still NOT proven — unchanged and honest.** No live OAuth flow has ever run. Every account reads
`auth: ok`, so the gate correctly refuses all four (exit 2), and the CDP drive, the Authorize
click, the `code#state` scrape and the fifo hand-back remain exercised only against stubs.
`scripts/relogin-probes/e3-warm-profile-authorize.sh` is the harness built to settle exactly this
and is deliberately `CONFIRM=1`-gated and **unrun** — it spends a real re-auth.

🚨 **The next cliff is much sooner than this plan assumed — correct the date.** Earlier entries
say "~2026-08-23". Live `--relogin-status` on 2026-07-26 says otherwise:

| acct | refresh-token deadline | hours out | at T−7d trigger? |
|---|---|---|---|
| **next** | **2026-08-02T20:21Z** | **175** | **~7h away** |
| next2 | 2026-08-17T19:52Z | 534 | no |
| next4 | 2026-08-23T20:24Z | 679 | no |
| next3 | 2026-08-24T02:22Z | 685 | no |

`next` is ~7 hours from becoming the poller's first candidate — which is why `candidates` reads 0
right now and would not tomorrow. So the supervised first run has a **natural target within a
week, not a month**: warm `next`'s auth-profile and run E3 against it before 2026-08-02. The
2026-08-23 window is next4/next3, not the first opportunity.

**Remaining work is operator-only (C10) by construction — not an agent gap:**

1. **Warm each auth-profile once.** A fresh `~/.claude/auth-profiles/<acct>` has no claude.ai
   cookies, so phase 2 lands on `/login` → exit 6. One interactive sign-in per account converts
   this from "works when warm" to unattended. The profile is persistent by design, so it is once
   per account, not once per run. (Fact 1 above — the warm cookies to 2027-08-14 — is about the
   **Dia** profiles, which the substrate no longer uses. It does not transfer.)
2. **Run E1-E3** with `CONFIRM=1`, E3 last — the only thing that proves the pieces compose.
3. **Load the LaunchAgent** per `docs/runbooks/RELOGIN_ACTIVATION.md`. `launchctl` activation is
   classifier-blocked from agents; the poller ships inert until a human loads it. No landing
   dependency remains, and the interpreter prerequisite is already satisfied (both above).

Target window: **before 2026-08-02** (`next`'s deadline), not 2026-08-23 — see the table above.
