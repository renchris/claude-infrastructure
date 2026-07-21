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

2. **Render the canonical readout — EXACTLY this structure, every invocation.** The CLI table
   is the DATA SOURCE, not the chat format; never improvise columns (user directive 2026-07-11:
   the readout must always answer "when does the 5h limit expire" and "when does the weekly
   limit expire" at a glance). Compute from `claude-accounts --json` → `.rows[]`; absolutes in
   LOCAL time as `EEE HH:MM` + coarse relative in parens. Every reset has an ISO `*_reset_at`
   field — `session_reset_at`, `weekly_reset_at`, `fable_reset_at`. Convert those; never do
   `now + *_reset_h` arithmetic (the `_h` countdowns decay from the moment the sweep was
   cached, and go NEGATIVE on an inherited stamp):

   | account | live | 5h used | 5h resets | weekly used | Fable used | weekly resets |
   |---|---|---|---|---|---|---|
   | next4 ← you | 6 | 8% | Sat 07:21 (in 4.7h) | 25% | 22% | Sat 02:00 (in 23.4h) |

   - Column set is FIXED — both reset columns present in EVERY row, absolute first.
   - Absolutes beyond ~6 days carry the DATE (`EEE MMM D HH:MM`, e.g. `Sat Jul 18 03:59`) —
     a bare weekday a week out is ambiguous with today.
   - ONE weekly-resets column: the weekly and weekly-Fable buckets reset at the same instant —
     compare `weekly_reset_at`/`fable_reset_at` at MINUTE precision (the CLI stamps them
     microseconds apart; exact string compare false-diverges). Genuinely different minutes →
     footnote it — never add a column.
   - Mark the row whose **`is_self: true`** with `← you`; if no row has it, omit the marker.
     NEVER derive this from `$CLAUDE_CONFIG_DIR` yourself — that is the reader's env, not the
     row's, and hand-derivation marked the wrong account on 2026-07-21. The CLI resolves it
     per invocation.

   **🚨 Staleness — the numbers are not always live.** A row is showing INHERITED history,
   not a fresh reading, whenever **`error` is present** or **`stale_quota: true`** (the
   `error` field is the by-construction test: the CLI only assigns live percentages on a
   clean 200, so every percent on an error row came from the last-good ledger). Such a row is
   also **excluded from routing**. For each one you MUST:
   - suffix every percent cell with `*`, and
   - add a bullet naming the age and the exclusion, using `quota_as_of` (ISO) — e.g.
     `↻ next4 — last-known, as of Sun 19 Jul; not polled this sweep, excluded from routing`.
   - `poll_throttled: true` is the TRANSIENT case (a 90s endpoint throttle, never a usage
     cap): say so, and note `--fresh` retries. Do not report it as a limit.
   - `rolled_since: [...]` names buckets whose reset has ELAPSED since that reading. Those
     percents are withheld (null) because the window has rolled — render `—`, and say the
     account is likely fresh again. Never present a withheld bucket as 0% or as last-known.
   - Never state or imply a stale number is current, and never rank or recommend on one.
   - A `*_reset_at` that is null or in the PAST renders `—`, never a past absolute and never
     a negative relative. Cause depends on the row: on a stale/error row it is
     `resets unknown (row not live)`; on a clean live row it means no reset stamp was
     returned for that limit (bucket unused / at 0%).
   - Flags are bullets BELOW the table, never extra columns. Enumerate by SOURCE, not by
     literal: ▲ 5h at/over the routing cutoff (the cutoff is `s_cut` in `--json` — never
     assume 85) · weekly at 100% **LIMITED** · Fable exhausted
     (`route_reasons.fable == "fable-exhausted"`) · `¢` extra-usage credits ON (+ `credits_used`)
     · `auth` ≠ ok · stale/throttled rows per the rule above. Row order = the CLI's own order.
   - Close with the router footer (`➤ general → X` · `➤ fable → Y`) + the Fable window line.
     When the window is **permanent**, there is no countdown to report — say "permanent",
     never a date-derived time remaining.

3. **Interpret** — report to the user, answer-first:
   - **Routing**: the footer's `➤ general → X` / `➤ fable → Y` is the
     adversarially-verified router (use-it-or-lose-it × Fable-sub-cap coupling ×
     5h-safety × concurrency-spread). Report its answer; never re-rank the accounts
     yourself from the `score_*` fields. For wave spread across several sessions use
     `claude-accounts --rank general|fable` (best-first list) and assign round-robin.
   - **Excluded accounts — read them on EVERY invocation, not just when routing fails.**
     `route_reasons` (per row, in `--json`) names why each account was dropped, and the
     footer/stderr report the count. An account excluded for a TRANSIENT reason
     (`poll throttled`, `no-*-data`) may well hold more headroom than the winner, so a bare
     "→ X" is "best of what we could see", not "best". Say which accounts were excluded and
     why whenever any were. `route_reason_class` classifies each as `data` (we could not see
     it) vs `policy` (we saw it and it is genuinely unusable) — that distinction, not the
     prose string, is what to reason from.
   - **`auth` column**: `ok` fine · `healed` was stale, self-repaired via headless
     `claude auth login` (logged to `~/.claude/logs/claude-accounts.log`) · `stale`
     expired access token, heal skipped (live sessions own the token lifecycle) ·
     `logged-out` / `token-invalid` / `keychain-error` / `no-oauth-blob` (item present but
     carries no OAuth credentials) → step 4. `probe-error` means that one account's probe
     raised unexpectedly and was contained; the traceback is in
     `~/.claude/logs/claude-accounts.log` and the other rows are unaffected.
   - **`stale` with live sessions is NOT a problem** — it is the designed state. The heal is
     deliberately skipped while `k > 0` because the running CC owns the token lifecycle and a
     concurrent refresh could rotate the token out from under it. Report it as benign; do not
     recommend a relogin for it. Only the step-4 states need action.
   - **Fable window** comes LIVE from `~/.claude/model-config.yaml frontier_access`
     — if it reads `UNKNOWN`, fix the SSOT parse before trusting any Fable routing.
     `window.permanent: true` means Fable is a standing plan inclusion with NO expiry —
     report it as permanent and never quote a countdown or a remaining time. The `end` date
     is a far-future sentinel kept only so date-based consumers never raise a false expiry;
     `permanent` is the truth. A null `window.deadline` with `permanent: false` means the
     SSOT date was unparseable — that is the UNKNOWN case, not an open one.
   - **`route → none`**: the reasons are printed (stderr / `route_reasons` in
     `--json`) — distinguish window-inactive/ended vs exhausted vs all-excluded;
     never fall back to a remembered static account order (both historical static
     lists went stale within 48h — endpoint data is the only SSOT).

4. **Logged-out account?** The table prints its email + Dia profile. Get the full
   identity block and invoke the re-login runbook:

   ```bash
   claude-accounts --relogin-info <acct>   # email, mailbox, Dia profile+dir, keychain, RT presence
   ```

   Then use the **account-relogin skill** (Skill tool: `account-relogin`) — it
   covers the headless refresh-token path (no browser) and the browser-assisted
   OAuth path via the account's Dia profile, including the email-code fallback.

5. **Routing-only asks** (`/accounts route fable`, "which account for X"): run
   `claude-accounts --route <kind>` — it stays the authoritative router; never re-derive the
   winner from `score_*`. It prints ONLY the bare account name on stdout, so pair it with the
   `--json` row for that account to give the one line of why (weekly %, reset, k).

   **A non-zero exit from `--route`/`--rank` is an ANSWER, not a tool failure:**

   | exit | meaning | how to report |
   |---|---|---|
   | 0 | routable | the account + why; also name any excluded accounts (step 3) |
   | 2 | data was fine, nothing routable by POLICY | quote the stderr reasons (exhausted / 5h cutoff / window). Do NOT fire blind, do NOT substitute a remembered account |
   | 3 | data unavailable for every account | report the auth/throttle state; the fleet was never seen, so say so rather than implying it is exhausted |

   `<kind>` must be exactly `general` or `fable` — the CLI rejects anything else rather than
   silently returning the general pick.

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
  `--fresh` in loops; never poll tighter than the 90s TTL. A 429 surfaces as
  `poll_throttled`, which is ALWAYS a transient poll failure and NEVER a usage cap —
  a real cap returns HTTP 200 with percent ≈ 100. Never report a throttle as a limit.
- Never run two re-logins concurrently (per-account lock exists, respect it).
- `~/bin/claude-accounts` is a SYMLINK into the repo, so a repo edit is live immediately.
  If it is ever a copy again it will silently drift — `scripts/deploy-parity-assert.sh`
  exits non-zero on that, and `./install.sh` restores the link.
