---
name: accounts
description: Cross-account Claude Max status — per-account 5-hour / weekly / weekly-Fable limits + resets, auth state, live session counts, and optimal work routing across the 4 accounts (next/next2/next3/next4). Detects logged-out accounts with their email + Dia profile mapping and hands off to the account-relogin skill. Use for "which account should I use", "check the quotas", "view usage across accounts", "is any account logged out", or /accounts.
allowed-tools: Bash, Read, Skill
argument-hint: "[route general|fable — just the routing answer] [relogin <acct> — jump to re-login] [--fresh]"
---

# /accounts — cross-account usage, auth state + routing

One entrypoint over the 4-account fleet. The mechanism is `~/bin/claude-accounts`
(repo: `claude-infrastructure/bin/claude-accounts`); the account map SSOT is
`~/.claude/accounts.json` (launcher → config dir → email → mailbox → Dia profile).

## Steps

1. **Run the dashboard** (default; pass `--fresh` to bypass the 90s shared cache):

   ```bash
   claude-accounts            # human table + Fable window + route hints
   claude-accounts --json     # when you need fields (auth, k, percents, resets, scores, reasons)
   ```

2. **Interpret** — report to the user, answer-first:
   - **Routing**: the footer's `→ GENERAL work → X / → FABLE work → Y` is the
     adversarially-verified router (use-it-or-lose-it × Fable-sub-cap coupling ×
     5h-safety × concurrency-spread). For wave spread across several sessions use
     `claude-accounts --rank general|fable` (best-first list) and assign round-robin.
   - **`auth` column**: `ok` fine · `healed` was stale, self-repaired via headless
     `claude auth login` (logged to `~/.claude/logs/claude-accounts.log`) · `stale`
     expired access token, heal skipped (live sessions own the token lifecycle) ·
     `logged-out` / `token-invalid` / `keychain-error` → step 3.
   - **Fable window** comes LIVE from `~/.claude/model-config.yaml frontier_access`
     — if it reads `UNKNOWN`, fix the SSOT parse before trusting any Fable routing.
   - **`route → none`**: the reasons are printed (stderr / `route_reasons` in
     `--json`) — distinguish window-inactive/ended vs exhausted vs all-excluded;
     never fall back to a remembered static account order (both historical static
     lists went stale within 48h — endpoint data is the only SSOT).

3. **Logged-out account?** The table prints its email + Dia profile. Get the full
   identity block and invoke the re-login runbook:

   ```bash
   claude-accounts --relogin-info <acct>   # email, mailbox, Dia profile+dir, keychain, RT presence
   ```

   Then use the **account-relogin skill** (Skill tool: `account-relogin`) — it
   covers the headless refresh-token path (no browser) and the browser-assisted
   OAuth path via the account's Dia profile, including the email-code fallback.

4. **Routing-only asks** (`/accounts route fable`, "which account for X"): run
   `claude-accounts --route <kind>` and answer with the account + one line of why
   (its weekly %, reset, k from the table).

## Consumers (do not duplicate their logic here)

- `/handoff` (`scripts/handoff-fire.sh --account auto`) consumes
  `claude-accounts --rank` as its primary account ranking; its transcript-activity
  heuristic is only the degraded fallback when the endpoint sweep fails.
- `/resume-sessions` Phase 5 uses the same tool (formerly `reso-quota`, now a shim).

## Safety rails

- The CLI never mints/persists tokens; healing is delegated to the official
  binary (headless `claude auth login`) and only runs when the account has ZERO
  live sessions — never trigger a manual refresh loop against a busy account.
- Both oauth endpoints rate-limit under load: prefer the cache (default) over
  `--fresh` in loops; never poll tighter than the 90s TTL.
- Never run two re-logins concurrently (per-account lock exists, respect it).
