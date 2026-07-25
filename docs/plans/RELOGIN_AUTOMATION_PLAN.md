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
