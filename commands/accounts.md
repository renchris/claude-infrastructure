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

2. **Render the canonical readout — run the renderer, do not rebuild it.**

   ```bash
   claude-accounts --readout   # the finished markdown table + flag bullets + router footer
   ```

   Paste that output. It IS the canonical structure (user directive 2026-07-11: the readout
   must always answer "when does the 5h limit expire" and "when does the weekly limit expire"
   at a glance). **Never hand-assemble this table from `--json`, and never improvise columns.**

   **Why it moved into code (2026-07-30).** Every formatting rule below used to live here as
   prose that the model re-executed each invocation — which meant two renderers for one table,
   kept in sync by discipline alone. Changing the relative format (`2.3d` → `2d 6h`) had to be
   made in both places on the same turn, and nothing but care stopped them drifting. Prose
   cannot be tested; `render_readout` can, and its rules are pinned by `tests/claude-accounts-core.bats`.
   The renderer now owns, with the directive that produced each preserved at the code:

   | Rule | Directive it encodes |
   |---|---|
   | Fixed column set, both reset columns + `login expires` in every row | 2026-07-11, 2026-07-24 |
   | Absolutes in LOCAL `EEE HH:MM`, dated past ~6 days; derived from `*_reset_at`, never `now + *_reset_h` | 2026-07-11 |
   | Relatives past 24h as `Xd Yh` (never decimal days, never 25+ hours) | 2026-07-30 |
   | `➤` + bold on the routed account; `➤ᶠ` when the Fable pick differs; `← you` from `is_self` | 2026-07-30 |
   | `⚠` + bold on a `login expires` inside `login_warn_h`; `⊘ REQUIRED` on a `login-required` row | 2026-07-24, 2026-07-30 |
   | `*` on every percent of an inherited row, + the age/exclusion bullet | 2026-07-19 |
   | ONE weekly-resets column (tolerance compare, footnote a genuine split) | 2026-07-11 |
   | Flags as bullets never columns; `¢` keyed on SPEND and rendered in DOLLARS | 2026-07-26 |
   | `—` for a null or elapsed stamp; `permanent` Fable window gets no countdown | 2026-07-20 |
   | Every `/login` line carries its mailbox + Dia profile | 2026-07-30 |

   **What is still yours** — the renderer prints facts; these bind how you may USE them:
   - 🚨 **Never state or imply a starred number is current, and never rank or recommend on
     one.** A `*` row is inherited history AND router-excluded. `poll_throttled` is a 90s
     endpoint throttle — ALWAYS transient, NEVER a usage cap (a real cap is HTTP 200 with
     percent ≈ 100). Never report a throttle as a limit.
   - 🚨 **Never re-derive the routed account yourself from `score_*`.** The footer is the
     adversarially-verified router; report its answer. For wave spread use
     `claude-accounts --rank general|fable` and assign round-robin.
   - 🚨 **Every re-login instruction you write names the MAILBOX it authenticates** — email
     and Dia profile, on the SAME line as the command (operator directive 2026-07-30: *"so we
     don't accidentally authenticate a different account to a wrong profile"*). `next` /
     `next3` are slot numbers, not identities; a mis-paired credential works, so nothing
     errors, while the account you meant keeps expiring. The renderer already emits this —
     so if you paraphrase a cliff bullet, carry the identity with it.
   - A row's `←`/`➤` markers and the footer are ONE answer from ONE ranking pass. If you
     summarise, do not restate the pick in a way that could disagree with the footer.

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
     expired access token, not healed (live sessions own the token lifecycle) ·
     `login-required` the refresh token is past its expiry, or the refresh grant was
     REJECTED — no headless path can recover this one, only an interactive `/login` ·
     `logged-out` / `token-invalid` / `keychain-error` / `no-oauth-blob` (item present but
     carries no OAuth credentials) → step 4.
     Filter on **`auth_actionable`** (needs an operator action) and **`login_fixable`**
     (an interactive `/login` is what fixes it — excludes `keychain-error` and `probe-error`,
     which are not credential states). Never re-derive either from a list of auth strings:
     a hand-copied list in `handoff-fire.sh` had already drifted to 3 of 5 states.
     `probe-error` means that one account's probe raised unexpectedly and was contained; the
     traceback is in `~/.claude/logs/claude-accounts.log` and the other rows are unaffected.
   - **`stale` with live sessions is NOT a problem** — it is the designed state. The heal is
     deliberately skipped while `k > 0` because the running CC owns the token lifecycle and a
     concurrent refresh could rotate the token out from under it. Report it as benign; do not
     recommend a relogin for it. Only the step-4 states need action.
     **But read `heal_note` before calling any `stale` row benign.** That benign reading holds
     for a heal that was *skipped* (`heal_note` starts with `skipped:`). A heal that RAN and
     FAILED is a different fact on an identical-looking row — the table now says `heal FAILED`
     rather than `heal skipped`, and a rejected grant is promoted out of `stale` to
     `login-required` outright. A residual `stale` + `heal FAILED` (a timeout or a 5xx) is
     transient: say so, and that `--fresh` retries it. Never restate it as the designed state.
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

4. **Account needs a login?** The table prints its email + Dia profile. Get the full
   identity block and invoke the re-login runbook:

   ```bash
   claude-accounts --relogin-info <acct>   # email, mailbox, Dia profile+dir, keychain, RT state
   claude-accounts --login-status          # every account needing /login now or soon
   claude-accounts --relogin-status        # per-account countdown + what the poller would do
   ```

   Then run **`/relogin <acct>`** (`bin/cc-relogin`) — the automated ladder: headless refresh
   grant, else unattended OAuth in a dedicated per-account Chrome (`cc-authbrowser`), proven by
   effect. Its exit code is the answer: `0` proven · `2` refused by the gate (already healthy /
   live sessions / lock held — the guard working, not a failure) · `5` the binary CLAIMED success
   but the effect check failed, so treat it as NOT re-authed · `6` that account's auth-profile has
   no live claude.ai session, email leg needed — **the one human gate**. Exit `7` (Dia consent) is
   retained for consumers but unreachable: the tool no longer drives Dia. Do NOT auto-fire it from
   a `--login-status` exit 2; credentials are the one place a retry loop must not be invented.
   Fall back to the **account-relogin skill** (Skill tool: `account-relogin`) for the manual
   and email-code paths — it stays the reference for exit 6.
   **Check `refresh_token_expired` first.** Phase 1 (the headless refresh-token grant)
   cannot succeed once that stamp has passed — go straight to Phase 2 (browser OAuth)
   rather than spending 90s proving what the keychain already stated. The same is true for
   `auth: login-required` reached via a rejected grant, where the stamp still looks healthy.

   `--login-status` is the surface for hooks and pollers: TSV lines
   (`acct · REQUIRED|EXPIRING · reason · expiry · remaining · launcher`) and the **exit code
   is the answer** — `0` all clear (and it prints nothing), `1` a login expires within
   `login_warn_h`, `2` action required now. It reads the shared cache, so it is safe to call
   on a cadence; it never forces a sweep.

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
