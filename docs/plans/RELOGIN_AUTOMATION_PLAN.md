---
status: open
---

# /relogin — fully autonomous account re-authentication

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
Python 3, one executable file. Deps: stdlib + `websocket-client` (1.6.1, installed system-wide).

**Exit codes** (consumers key on these — frozen):

| exit | name | meaning |
|---|---|---|
| 0 | PROVEN | re-auth verified by EFFECT (below), never by the binary's report |
| 1 | ERROR | unexpected failure |
| 2 | REFUSED | gate: unknown acct · account healthy · `k > 0` · heal lock busy |
| 3 | HEADLESS-EXHAUSTED | `--no-browser` given and Phase 1 impossible or failed |
| 4 | BROWSER-FAILED | Phase 2 mechanics: no OAuth URL within `--url-timeout` (default 30s) · CDP unreachable · profile ctx unmatched · no Authorize control · callback timeout |
| 5 | UNVERIFIED | binary claimed success but the effect check failed — treat as NOT re-authed |
| 6 | FALLBACK-REQUIRED | authorize URL landed on claude.ai `/login` (web session cold) — email-code leg not automated; stdout carries the exact remaining human step incl. mailbox |
| 7 | CONSENT-GATE | CDP blocked: `DevToolsActivePort` absent (toggle off) or WS handshake hung >8s (consent dialog pending); stdout names the recovery: cycle `dia://inspect#remote-debugging` off→on, re-run — first connect after a cycle is consent-free |

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
