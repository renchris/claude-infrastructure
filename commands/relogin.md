---
name: relogin
description: Re-authenticate one Claude Max account (next/next2/next3/next4) through the automated ladder — headless refresh grant first, then browser-assisted OAuth in the account's own Dia profile — and prove it by effect. Use when /accounts reports login-required / logged-out / token-invalid, when `claude-accounts --login-status` exits non-zero, or when the user says "re-login next3", "fix the logged-out account", "the login expired".
allowed-tools: Bash, Read, Skill
argument-hint: "<acct> [--dry-run] [--no-browser]"
---

# /relogin — re-authenticate one account, most-automated path first

Mechanism: `~/.claude/bin/cc-relogin` (repo `bin/cc-relogin`; `install.sh` symlinks every
`bin/cc-*` there, and it is on PATH). It is the executable form of the
**account-relogin** skill; the skill remains the reference for the manual and fallback paths.
`/accounts` DETECTS the login cliff — this closes it.

## Steps

1. **Confirm who needs it** (never re-login a healthy account — the tool refuses anyway):

   ```bash
   claude-accounts --login-status     # exit 0 clear · 1 expiring · 2 action required
   ```

2. **Dry-run first** on anything you did not just diagnose. It prints the gate reads and the
   phase plan, takes and releases the lock, and mutates nothing:

   ```bash
   cc-relogin <acct> --dry-run
   ```

3. **Run it.** `--json` when you need to branch on the result:

   ```bash
   cc-relogin <acct>            # human line
   cc-relogin <acct> --json     # {acct,result,exit,phase_reached,before,after,detail}
   ```

## Reading the exit code — it IS the answer

| exit | result | what it means / what to do |
|---|---|---|
| 0 | `proven` | re-authed AND verified by effect. Nothing further. |
| 1 | `error` | unexpected. One-line reason on stdout; never a traceback. Includes **`websocket-client` not installed for this interpreter** — a dep fault in the driver, not the browser; the reason names the interpreter and the exact `pip install`. Run it and re-run. |
| 2 | `refused` | the GATE declined: unknown account · already healthy · `k > 0` live sessions · another heal in flight · `--dry-run`. **Not a failure** — the guard working. |
| 3 | `headless-exhausted` | `--no-browser` and the refresh grant could not run or failed. Re-run without `--no-browser`. |
| 4 | `browser-failed` | Phase-2 mechanics broke (no OAuth URL, profile context unmatched, no Authorize control). The child's output path is printed — read it. Never a missing local dep (→ 1); never a pending consent (→ 7). |
| 5 | `unverified` | 🚨 the binary CLAIMED success but the effect check failed. **Treat as NOT re-authenticated.** Investigate before re-running. |
| 6 | `fallback-required` | that Dia profile's claude.ai session is cold, so the email-code leg is needed. stdout names the mailbox and the remaining step. |
| 7 | `consent-gate` | CDP is blocked — remote debugging off, or Dia's consent dialog pending. Recovery: cycle `dia://inspect#remote-debugging` off→on (the first connect after a cycle is consent-free), then re-run. **A human action, not a code fix.** |

**Exit 5 is the one to never wave through.** "Login successful." is a claim the child process
makes about itself; the tool only reports `proven` when `auth` came back `ok` AND the
refresh-token expiry moved FORWARD. A 5 means those disagreed.

## What it will not do

- **Never `/logout`** as a fix — that revokes the grant and deletes the keychain item.
- **Never raw-POST a refresh token.** Tokens may rotate, and a discarded rotation IS a logout;
  only the official binary is allowed to touch them.
- **Never act on an account with live sessions.** Checked twice — once at the gate, once again
  under the lock, because a session can start in between.
- **Never widen `oauth_scopes`** — passed verbatim from the SSOT.
- It holds `/tmp/claude-accounts-heal-<acct>.lock`, the SAME lock `claude-accounts` heal()
  takes, so the two can never race.

## When it hands back

Exit **6** (cold web session) and exit **7** (consent gate) are the two genuine human gates.
For 6, use the **account-relogin skill** (Skill tool: `account-relogin`) — Phase 2b covers the
email-code fetch, including which mailbox the plus-address folds into. For 7, the operator
cycles the Dia toggle; nothing in software can approve that dialog.

## Not yet automatic

`claude-accounts --login-status` exit 2 does NOT auto-fire this. That stays deliberate until
the browser leg has succeeded unattended several times — an auto-relogin that misfires touches
credentials, which is the one place a retry loop must never be invented. Offer it; let the
operator or an explicit `/relogin` pull the trigger.
