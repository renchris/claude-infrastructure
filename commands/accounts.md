---
name: accounts
description: "Cross-account Claude Max status: 5-hour, weekly and weekly-Fable limits and resets, auth state, live sessions, and which of next/next2/next3/next4 to route work to. Flags logged-out accounts for account-relogin. Use to check the quotas."
allowed-tools: Bash, Read, Skill
argument-hint: "[route desk|general|fable — just the routing answer] [relogin <acct> — jump to re-login] [--fresh]"
---

# /accounts — cross-account usage, auth state + routing

One entrypoint over the 4-account fleet. The mechanism is `~/bin/claude-accounts`
(repo: `claude-infrastructure/bin/claude-accounts`); the account map SSOT is
`~/.claude/accounts.json` (launcher → config dir → email → mailbox → Dia profile).

**"How much weekly limit did we leave on the table / did we waste quota last week?"** is one command, not this dashboard: `claude-accounts --stranded [acct]` (acct `next`..`next4` or `1`-`4`; `--json` for data) lists every closed weekly window, newest first, with its final %, the pp stranded, when it reached 100%, and a per-account total.

## Steps

1. **Run the dashboard** (default; pass `--fresh` to bypass the 90s shared cache):

   ```bash
   claude-accounts            # human table + Fable window + route hints
   claude-accounts --json     # when you need fields (auth, k, percents, resets, scores, reasons)
   ```

2. **Render the canonical readout — run the renderer, do not rebuild it.**

   ```bash
   claude-accounts --readout   # router headline + fenced grid + flag lines + drain line + read-time line + provider lines
   ```

   🚨 **Paste that output VERBATIM into chat — every row and column, before any commentary.**
   Not a style preference, and CLAUDE.md § Communication Discipline's conciseness rule does NOT
   override it (that rule governs your prose — see its "brevity governs YOUR prose, never a
   rendered artifact" clause). A summary like "all 4 accounts healthy, router says next" is a
   FAILED `/accounts`: the operator runs this to READ the reset times, not to be told they exist.
   Observed 2026-08-01 — the readout rendered correctly and was then dissolved into three bullets.

   It IS the canonical structure (user directive 2026-07-11: the readout
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
   | The desk / general / fable answer LEADS, above the grid; the desk clause is `desk_plain` — the rung in plain words plus the weekly countdown, and "favored because your last `claude` opened here" on incumbency (the board and `claude-accounts` keep `desk_why`'s codes) | 2026-10-18 |
   | A ```text grid in the SessionStart board's visual language (mark column, weekly bar), fixed columns: live, 5h used + reset, weekly used + bar, fable, weekly reset, login | 2026-07-11, 2026-07-24, 2026-10-18 |
   | Each reset is `countdown clock` (`3h 29m Sun 03:59`): countdown first, two units (`fmt_board_t`), re-derived from `*_reset_at`; clock in LOCAL `EEE HH:MM`, dated past ~6 days | 2026-07-11, 2026-07-30, 2026-10-18 |
   | `➤` in the mark column on the **desk** pick (what bare `claude` launches onto); `➤ᵍ`/`➤ᶠ` when the general / Fable pick differs; `←` from `is_self` (spelled `← you` on the headline) | 2026-07-30, re-pointed 2026-08-11 |
   | Login is a countdown, re-derived from `login_expires_at`; `⚠` inside `login_warn_h` (the date rides the ⚠ line); `⊘ EXPIRED` once it has passed, even since the sweep; `⊘ REQUIRED` on a `login-required` row | 2026-07-24, 2026-07-30, 2026-10-18 |
   | `*` on every percent of an inherited row, + the age/exclusion line | 2026-07-19 |
   | ONE weekly-resets column (tolerance compare, footnote a genuine split) | 2026-07-11 |
   | Flags are glyph-led lines (never columns) in severity order: 🚨/⚠ money, ○/⊘ auth, ✖ out and `· Skipped by the general router:`, △ near (weekly), ▲/△ 5h cutoff, ⚠ login cliff, ↻ stale, ○ Fable exhausted / ¢ authorized spend, · footnote; `¢` keyed on SPEND and rendered in DOLLARS | 2026-07-26, 2026-10-18 |
   | Every general-lane exclusion is on screen: the ↻, ▲, ✖, ⊘/⚠ login and △ "the router still holds it back" lines cover theirs, and the Skipped line names the rest (live-session cap, uncountable sessions, weekly room under the router floor with no server refusal, a login drain past the warn band) | 2026-10-18 |
   | The weekly-drain block is ONE line in plain words: "Give heavy work to **X** or **Y**: at the last 2 days' pace, 83% and 43% of their weekly limits go unused at reset", the general pick named first; when the general pick is not among them the line states the forecast with no directive; smaller strands ride as `also …`; no reading at all says so rather than "nothing"; ⚠ wall rows stay verbatim and count down like the grid | 2026-10-18 |
   | `—` for a null or elapsed stamp; the last line says when the quota was READ (`Quota read at 07:49, 28 seconds ago`); the Fable window prints only when it is news (inactive, dated or unknown), never for a permanent, active one | 2026-07-20, 2026-10-18 |
   | Other agents: line 1 names only backends that are signed in, installed and known to bill inside a plan, with the cause for the rest (not installed / not signed in); 🚨 or ⚠ only for a routable backend that bills outside a plan or might, or one on a metered API key; the standing not-wired set closes it with no alarm glyph | 2026-10-18 |
   | Every `/login` line carries its mailbox + Dia profile | 2026-07-30 |

   **What is still yours** — the renderer prints facts; these bind how you may USE them:
   - 🚨 **Never state or imply a starred number is current, and never rank or recommend on
     one.** A `*` row is inherited history AND router-excluded. `poll_throttled` is a 90s
     endpoint throttle — ALWAYS transient, NEVER a usage cap (a real cap is HTTP 200 with
     percent ≈ 100). Never report a throttle as a limit.
   - 🚨 **Never re-derive the routed account yourself from `score_*`.** The headline (the `➤` lines above the grid) is the
     adversarially-verified router; point at it, never re-derive or restate it. For wave spread use
     `claude-accounts --rank general|fable` and assign round-robin.
   - 🚨 **Three lanes, and they are NOT interchangeable — say which one you are answering.**
     `desk` is what bare `claude` will do (the human's own next session); `general` is what
     `handoff-fire` will do; `fable` is the frontier lane. They are different objectives over
     the same eligibility and they diverge in practice — replayed on two accounts they invert
     completely, and the 2026-08-11 surprise ("routed me to Account3 when /accounts recommends
     Account1") was exactly this: both answers were correct, for different questions, and only
     one of them was on screen. If the operator asks "which account do I use", the answer is
     the **desk** line.
   - 🚨 **Every re-login instruction you write names the MAILBOX it authenticates** — email
     and Dia profile, on the SAME line as the command (operator directive 2026-07-30: *"so we
     don't accidentally authenticate a different account to a wrong profile"*). `next` /
     `next3` are slot numbers, not identities; a mis-paired credential works, so nothing
     errors, while the account you meant keeps expiring. The renderer already emits this —
     so if you paraphrase a cliff bullet, carry the identity with it.
   - A row's `←`/`➤` markers and lines 1-2 are ONE answer from ONE ranking pass; do not restate
     the pick at all (step 3).

3. **After the paste: add nothing, unless one of the cases below is on screen.** The readout leads
   with its own answer — line 1 is the desk pick (what bare `claude` opens on) and why, line 2 the
   general and fable picks — and it prints what will go unused at the weekly reset, when the quota
   was read, and which other agents are ready. Restating any of that is a second renderer in prose:
   on 2026-10-17 the model followed the paste with two paragraphs ("For your own next session, use
   next4 …", "Most of next3's and next2's weekly quota is on track to go unused …") that repeated
   line 1 and the drain line. Never restate a pick (line 1's desk, line 2's general and fable), a
   percent, a reset, the drain line (`Give heavy work to …` / `At the last 2 days' pace …`), the
   Fable / `Quota read` line or the other-agents lines, and never re-explain the desk pick in
   general's vocabulary.

   Add at most 3 lines in total, answer first, and only for these cases — the same list, in the
   same words, that `hooks/relay-verbatim.sh` repeats at the moment of the paste (change the two
   together):
   - **A ↻ line or a `Skipped by the general router:` line**: the picks are "best of what we could
     see", not "best". Say so once, naming the accounts and whether the cause is data (we could not
     see it) or policy (we saw it and it is unusable) — read `route_reason_class` in `--json`, not
     the prose. Every general-lane exclusion has a line of its own (a ↻ line, a ▲ 5h line or an
     "out of 5-hour quota" sentence, an "out of weekly quota" sentence, a △ sentence ending "the
     router still holds it back from new work", a ⊘/⚠ login line, or the Skipped line), so with
     none of those on screen the general router excluded no account.
   - **A ⊘/⚠ login or ○ auth line**: hand over the one fix, `/relogin <acct>`, with the mailbox and
     Dia profile on the same line (step 2's rule; operator directive 2026-07-30).
   - **A 🚨 spend or ⚠ extra-usage toggle line**: say the spend is not authorized and name the
     toggle to turn off; `accounts.json spend.usage_credits_authorized=false` is the standing answer.
   - **A lane reading `→ none`**: say whether it is policy (`--route` exit 2: quota, 5h cutoff,
     window) or data (exit 3: the fleet was not seen) — step 5's table — and never substitute a
     remembered account.
   - **A 🚨/⚠ line about another agent (a routable backend that bills outside a plan or might, or one on a metered API key)**:
     it is metered money or may be; say it must be unwired or moved onto a plan.
   - **A direct question from the operator** the readout does not answer outright (e.g. "can I
     start a Fable wave now?"): one sentence, naming the lane (desk, general or fable) and quoting
     the readout's own numbers. "Which account do I use" is line 1 — point at it, do not reword it.

   NOT triggers: the standing `Not wired, because … would bill outside our plans` line, the ⚠ WALL /
   LATE / START SOON pace rows and the ⚠ fleet-burn line. Each already says everything it has to
   say, and they print often enough that commenting on them is the habit this rule removes.

   The bullets below are reference for those cases, not prompts to narrate:
   - **Routing**: lines 1-2 (`➤ desk → D` / `➤ general → X` / `➤ fable → Y`) are the
     adversarially-verified router (use-it-or-lose-it × Fable-sub-cap coupling ×
     5h-safety × concurrency-spread). The **desk** clause states the rung of the desk lane's
     two-key ladder in words: "room in both its 5-hour and weekly limits" (both keys met), "on pace
     to stay under its 5-hour limit, but weekly room is thin" (the weekly key degraded away), or
     "every usable account is on pace to hit its 5-hour limit" (both degraded). It claims nothing
     about the other accounts beyond that rung being the highest any eligible account reached:
     inside a rung the order also carries the login soft band and the incumbent margin, so "the
     soonest weekly reset" is not a safe paraphrase. "favored because your last `claude` opened
     here" names the incumbent margin, which is applied whether or not it changed the pick. The
     board and plain `claude-accounts` print the same rung as codes (`desk_why`): `safe set`,
     `5h-safe only`, `no floor met`, and `sticky` for the incumbent.
   - **Excluded accounts — read them on EVERY invocation, not just when routing fails.**
     `route_reasons` (per row, in `--json`) names why each account was dropped; the readout's
     lines cover the general lane's (case 1 above), and the desk and fable lanes' reasons are in
     `--json` only. An account excluded for a TRANSIENT reason
     (`poll throttled`, `no-*-data`) may well hold more headroom than the winner, so a bare
     "→ X" is "best of what we could see", not "best". Say which accounts were excluded and
     why whenever any were. `route_reason_class` classifies each as `data` (we could not see
     it) vs `policy` (we saw it and it is genuinely unusable) — that distinction, not the
     prose string, is what to reason from.
   - **auth state** (`auth` in `--json`; ○/⊘ lines in the readout): `ok` fine · `healed` was stale, self-repaired via headless
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
     A `stale` row whose keychain holds no refresh token can never heal, so it is now reported
     as `login-required`; `stale` (even at `k=0`) stays benign only when a refresh token exists.
     **But read `heal_note` before calling any `stale` row benign.** That benign reading holds
     for a heal that was *skipped* (`heal_note` starts with `skipped:`). A heal that RAN and
     FAILED is a different fact on an identical-looking row — plain `claude-accounts` says
     `heal FAILED` rather than `heal skipped`, and a rejected grant is promoted out of `stale` to
     `login-required` outright. A residual `stale` + `heal FAILED` (a timeout or a 5xx) is
     transient: say so, and that `--fresh` retries it. Never restate it as the designed state.
   - **Fable window** comes LIVE from `~/.claude/model-config.yaml frontier_access`
     — if the readout says `Fable window: **unknown**`, fix the SSOT parse before trusting any
     Fable routing. `window.permanent: true` means Fable is a standing plan inclusion with NO
     expiry — the readout prints nothing about a permanent, active window (it is not news); never
     quote a countdown or a remaining time for it. An inactive, dated or unknown window prints a
     Fable clause in front of the `Quota read` line. The `end` date
     is a far-future sentinel kept only so date-based consumers never raise a false expiry;
     `permanent` is the truth. A null `window.deadline` with `permanent: false` means the
     SSOT date was unparseable — that is the UNKNOWN case, not an open one.
   - **`route → none`**: the reasons are printed (stderr / `route_reasons` in
     `--json`) — distinguish window-inactive/ended vs exhausted vs all-excluded;
     never fall back to a remembered static account order (both historical static
     lists went stale within 48h — endpoint data is the only SSOT).

4. **Account needs a login?** The ⊘/⚠ login line prints its email + Dia profile. Get the full
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

   `<kind>` must be exactly `general`, `fable` or `interactive` — the CLI rejects anything else
   rather than silently returning the general pick. `interactive` is the DESK lane (the name the
   launcher uses at `lib/claude-launcher.zsh`); it is the one the operator means by "which account
   do I use", and every `--route interactive` decision — pick, runner-up, rung, and an abstention —
   is appended to `~/.claude/route/route.jsonl` with `slot":"interactive"`, so a past launch can be
   replayed rather than reconstructed.

## Non-Claude agent backends (the provider section)

`/accounts` answers two questions now. The table above answers *"which of my 4 Claude Max accounts
has headroom"*. The provider section answers *"what else can I route to, and does using it cost
money outside a plan I already hold"*.

`claude-accounts --readout` **appends a short summary of it**: who is ready now (signed in,
installed, and known to bill inside a plan we hold), a 🚨 or ⚠ line only for a routable backend
that bills outside a plan or might, or one on a metered API key, and the standing set that is not
wired because it would bill outside our plans — same single-renderer rule, so paste the whole thing
verbatim. The full table below is `--agents`, which prints that section alone (add `--json` for the
rows as data; `--no-agents` returns the historical Claude-only readout). `--agents` deliberately
skips the keychain read and the usage sweep, so it costs nothing and cannot be blocked by a
4-account sweep.

Registry SSOT: `~/.claude/providers.json` (separate from `accounts.json`, which declares itself the
SSOT for the Claude accounts and whose every field is Anthropic-specific).

**Reading the table — three columns carry the judgment:**

- **`routable`** — ✅ only when the backend has a **non-interactive agent mode** *and* cleared the
  cost gate. 🚨 **Presence is not routability.** Antigravity is installed, authenticated, and on
  `PATH`, and is still ✖: its binary is the VS Code editor launcher with no headless mode, so no
  work can ever be sent to it. grok-wiki's picker reported it `ready` on `command -v` alone. When a
  row is not ✅, the bullet under the table names *which* gate it failed — trust that bullet over
  the shape of the row.
- **`bills outside it?`** — the cost gate, and a **different question from `plan`**. A backend can
  authenticate against a subscription we hold and still meter separately: `pi-claude` logs into
  Claude Pro/Max and then bills per token through *extra usage*, which
  `accounts.json spend.usage_credits_authorized=false` forbids. A **YES** row is documented so the
  refusal survives the next reader — never wire one, never `/login` it.
- **`model pinned`** — `✓proven` means the agent was **run** and reported that model id back
  (`codex exec` prints `model: gpt-5.6-sol` in its header). `⚠unproven` means a config file says so
  and nothing has confirmed it. A `--model`/`--reasoning` flag through a wrapper can be silently
  ignored — no error, just quietly worse output — so treat `⚠unproven` as *not yet a pin*.

**UNKNOWN is a real value here, not a gap to fill.** A cell that could not be measured says
`UNKNOWN` and the provider is skipped on that basis. Do not resolve one by inferring from a
vendor's marketing; re-measure, or leave it.

**Before adding a provider,** measure the three independent facts separately — binary present /
authenticated / has a headless mode — and answer *what does using it BILL* from a source that
discusses billing. A subscription **login list** only ever answers whether auth works. Full
measurements and the reasoning: `docs/plans/MULTI_PROVIDER_PLANS.md` § W1 RESULT.

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
