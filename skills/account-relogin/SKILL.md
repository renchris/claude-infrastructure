---
name: account-relogin
description: Agentically re-authenticate a logged-out Claude Max account (next/next2/next3/next4) — headless refresh-token path first, then browser-assisted OAuth in the account's mapped Dia profile, with the outlook email-code fallback. Use when claude-accounts / /accounts reports auth logged-out, token-invalid, or keychain-error; when a launcher greets with "Not logged in · Please run /login"; or when the user says "re-login next3", "fix the logged-out account", "re-auth the account".
---

# account-relogin — re-authenticate one account, most-automated path first

Identity comes from the SSOT: `claude-accounts --relogin-info <acct>` → email, base
mailbox, Dia profile name + live-resolved profile dir, keychain service, whether a
refresh token survives. All commands below use `$CFG` (config_dir), `$EMAIL`,
`$BIN` (claude_bin) from that JSON. **Serialize: one re-login per account at a time,
never while another heal/login is in flight** (`/tmp/claude-accounts-heal-<acct>.lock`).

## Phase 0 — Confirm the state (never re-login a healthy account)

```bash
claude-accounts --relogin-info <acct>          # keychain_state + has_refresh_token
CLAUDE_CONFIG_DIR=$CFG $BIN auth status        # "Not logged in..." = confirmed
```

- `keychain_state: present` + `has_refresh_token: true` → Phase 1 (no browser needed).
- `no-keychain-item` (a real `/logout` deletes the item) or Phase 1 fails
  `invalid_grant` → Phase 2.
- A false "logged-out" can be a transient rotation race — if the account has live
  sessions (`k > 0` in `claude-accounts`), re-check once before acting; a working
  session refutes logged-out.

## Phase 1 — Headless re-login (refresh token still valid; fully scriptable)

```bash
CLAUDE_CONFIG_DIR=$CFG \
CLAUDE_CODE_OAUTH_REFRESH_TOKEN=$(security find-generic-password -s "<keychain_service>" -a chrisren -w | python3 -c "import json,sys; print(json.load(sys.stdin)['claudeAiOauth']['refreshToken'])") \
CLAUDE_CODE_OAUTH_SCOPES="user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload" \
$BIN auth login
```

The binary performs the refresh grant (1-year expiry), persists the (possibly
rotated) tokens to the SAME keychain item — item names are a pure function of the
config-dir path, they never change across logout/login — and prints
`Login successful.`. Verify: `claude-accounts --fresh` shows `ok`. This is exactly
what the CLI's auto-heal does; running it manually is for accounts auto-heal
skipped (it only runs at k==0).

## Phase 2 — Browser-assisted OAuth (true logout / revoked RT)

The flow: run login headless with pipes, open its printed URL in the RIGHT Dia
profile, click Authorize there, feed the code back. No TUI pane scraping.

1. **Start login as a subprocess with pipes** (stdout gives the URL; stdin takes
   the code):

   ```bash
   CLAUDE_CONFIG_DIR=$CFG $BIN auth login --claudeai --email $EMAIL \
     > /tmp/relogin-<acct>.out 2>&1 < /tmp/relogin-<acct>.in &   # mkfifo the .in first
   grep -o 'https://[^ ]*oauth[^ ]*' /tmp/relogin-<acct>.out     # the MANUAL-redirect URL
   ```

   Notes: `--email` pre-fills login_hint. The CLI ALSO auto-opens the
   localhost-variant URL in the default browser — close/ignore that tab (harmless;
   both variants share state+PKCE). The printed manual URL is the automation surface.

2. **Open the URL in the account's Dia profile.** ⚠ `open -na Dia --args
   --profile-directory=…` is BROKEN while Dia runs (instance-guard stray, verified
   2026-07-09). Use the **dia-agent skill** (Skill tool: `dia-agent`) CDP recipe:
   - Human gate (one per batch): check `dia://inspect#remote-debugging`; if already
     on, cycle off→on (first connect after a cycle is consent-free).
   - Read `~/Library/Application Support/Dia/User Data/DevToolsActivePort` →
     `ws://127.0.0.1:<port><path>`; ONE persistent raw-WS connection (suppress the
     Origin header), do everything inside it.
   - Map browserContextId → profile dir: `Target.createTarget({url:"chrome://version",
     browserContextId})` → read `#profile_path`; skip ctxs that throw -32602/-32000.
     Match against `dia_profile_dir` from relogin-info (resolved live by NAME —
     dirs drift; never a remembered dir).
   - `Target.createTarget({url:<oauth url>, browserContextId:<ctx>})` → click
     Authorize via AX tree → `DOM.getBoxModel` → `Input.dispatchMouseEvent`
     (isTrusted=true; `el.click()` is the fallback).
   - Semi-manual fallback (no CDP): activate Dia, `osascript key code 19/20/21
     using control down` (⌃2=Claude2 ⌃3=Claude3 ⌃4=Claude4) to front the profile
     window, `open -a Dia "<url>"`, human clicks Authorize — screenshot-verify the
     tab landed in the right profile window.

3. **Complete.** If the profile's claude.ai session is warm, Authorize → the
   localhost callback finishes the CLI login automatically. If the CLI is on the
   paste path, the callback page shows a `code#state` blob — scrape it
   (`Runtime.evaluate document.body.innerText`) and write it + newline to the
   fifo (`/tmp/relogin-<acct>.in`).

4. **Verify + teardown**: `claude-accounts --fresh` shows `ok`; `$BIN auth status`
   (with `CLAUDE_CONFIG_DIR=$CFG`) shows the email. Human unchecks the
   `dia://inspect` toggle; verify no ephemeral-port Dia listener remains
   (`lsof -nP -iTCP -sTCP:LISTEN | grep -i dia`; the fixed :54271 agent-server is
   expected — ignore it).

## Phase 2b — claude.ai web session ALSO logged out (email-code fallback)

The authorize URL lands on claude.ai `/login`: enter `$EMAIL` → Continue with
email → Anthropic mails a one-time code + magic link to the account's **base
mailbox** (plus-addresses fold: e.g. `ren.chris+claude@` → `ren.chris@outlook.com`
— the `mailbox` field in relogin-info). Prefer typing the CODE over clicking the
link (one tab of truth). Fetch it, most-automated first:

1. **Same-profile webmail**: in the SAME CDP connection open
   `https://outlook.live.com/mail/` in the SAME browserContextId (the profile's
   warm outlook session) → read the newest Anthropic message's preview/body →
   extract the code (regex generously: sender Anthropic/Claude, 6-8 char code).
2. **MS Graph** (headless): the outlook-cleanup pipeline's device-code flow
   (`~/Development/personal/outlook-cleanup/`, Graph PowerShell client id,
   `Mail.Read`) — its token cache currently covers ONE mailbox; the other three
   need a one-time device-code sign-in each before this path works headlessly.
3. **Human**: "code sent to `<mailbox>` — paste it here."

If outlook in that profile is also logged out and Graph has no token: stop and
hand to the human (MS password/2FA is out of scope, never automate it).

## Hard rules

- Never `/logout` anything as a "fix" — it revokes + deletes the keychain item.
- Never run a raw refresh-token POST yourself and discard the response — refresh
  tokens may rotate; only the official binary (Phase 1) or CC itself touches them.
- Only re-login an account with zero live sessions when possible; if sessions are
  live and healthy, the account is NOT logged out — re-check Phase 0.
- One human gate per batch is expected (the Dia remote-debugging consent); batch
  all pending re-logins inside one toggle cycle / one WS connection.
