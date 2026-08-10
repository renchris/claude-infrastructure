---
status: open
---

# MULTI-PROVIDER PLANS — equip claude-infrastructure with every agent plan we already pay for

**Created:** 2026-08-10 · **Branch:** `feat/multi-provider-plans` · **Base:** `origin/main` @ `81163762`

**Scope (frozen):** make every AI coding plan the operator ALREADY pays for reachable and visible
from claude-infrastructure — install/update each covered CLI to latest, pin each to its latest model,
and extend `/accounts` + `bin/claude-accounts` from a Claude-only readout to a multi-provider one.
**HARD COST CONSTRAINT: wire up NOTHING that bills outside an existing plan.** A provider requiring a
new subscription is documented and SKIPPED, never signed up for.

**Why now:** grok-wiki's local-agent picker surfaced six agent backends on this machine, four of
which ride plans we already hold, and none of which `/accounts` can see. `/accounts` today answers
"which of my 4 Claude Max accounts has headroom" — it cannot answer "what agent capacity do I have
across all my plans", which is the question that actually governs routing now.

---

## Phase 0 — Agent Team Orchestration

**EXECUTION LOCUS PER WAVE:**

| Wave | Locus | Why |
|---|---|---|
| W1 Cost gate + inventory | **S** (dispatched session) | default for an implementation wave |
| W2 Install/update + model pins | **S** | default |
| W3 `/accounts` multi-provider readout | **S** | default; largest deliverable, own session |
| W4 Docs + tests | **T** (teammates inside W3's session) | two independent files, must be synthesised against W3's schema immediately, combined output small |

**Lead context budget:** hold ≥50% for deciding; each wave is one dispatched session, fired and awaited.

**Dependency graph:** W1 → W2 → W3 → W4. W1 gates everything (it decides WHICH providers are in
scope at all), so it must not be parallelised with W2.

**Single owner per shared file:** `bin/claude-accounts` and `~/.claude/accounts.json` are owned by
W3 exclusively. W2 touches only per-provider config files.

---

## Live state at plan creation (measured 2026-08-10, not recalled)

| Backend | Installed | Version | Plan it rides | In scope? |
|---|---|---|---|---|
| **Codex CLI** | ✅ `~/.local/bin/codex` | **0.147.0** (updated this session, was 0.142.2) | ChatGPT/Codex plan | ✅ already covered |
| **Claude Code** | ✅ | — | 4× Claude Max | ✅ already covered, already in `/accounts` |
| **Antigravity CLI** | ✅ `~/.antigravity/antigravity/bin/antigravity` | 1.107.0 | Google — **auth/plan UNVERIFIED** | ⚠️ W1 must verify |
| **Grok CLI** | ❌ MISSING | — | xAI — **likely needs SuperGrok** | ⚠️ W1 cost gate; SKIP if it needs a new sub |
| **Pi · Codex** | ❌ MISSING | — | rides **existing** ChatGPT Plus/Pro | ✅ highest-value gap — zero new cost |
| **Pi · Claude Code** | ❌ MISSING | — | rides **existing** Claude Pro/Max | ✅ highest-value gap — zero new cost |

**Why Pi is the headline:** `pi-codex` and `pi-claude` are wrappers that authenticate against plans
already held (`/login` → ChatGPT Plus/Pro, or Claude Pro/Max). Installing Pi adds two more agent
backends at **zero marginal subscription cost** — exactly what the frozen scope asks for. Install:
`npm install -g --ignore-scripts @earendil-works/pi-coding-agent`, then `pi` → `/login`.

**Codex config already updated this session** (`~/.codex/config.toml`): `model = "gpt-5.6-sol"`
(priority 1, "latest frontier agentic coding model"), `model_reasoning_effort = "xhigh"`. Effort
ladder reaches `ultra`; `xhigh` chosen as the global default so trivial calls stay responsive, with
`--reasoning ultra` passed per-invocation where earned.

---

## W1 — Cost gate + capability inventory (do this FIRST; it scopes everything else)

For **each** backend above, establish from live reads, never assumption:

1. Is it authenticated, and **against which plan**? (`antigravity` especially — it reports `ready`
   to grok-wiki but that only proves a binary exists on PATH.)
2. Does using it bill **outside** an existing subscription? Any provider whose answer is yes, or
   whose answer cannot be established, is **SKIPPED and documented** — never signed up for.
3. What is its latest CLI version and latest model, and how is each pinned?

**Deliverable:** a table appended to this doc, one row per backend, with the exact command run to
establish each cell. A cell you could not measure reads `UNKNOWN`, never a guess.

**Landmine (measured this session):** a stale model cache can hide newer models *and* be unreadable
by an old client simultaneously — `~/.codex/models_cache.json` failed to parse with
`missing field supports_reasoning_summaries`, so only ONE hidden `gpt-5.6` alias was visible until
the CLI was updated; the refresh then revealed `gpt-5.6-sol`/`terra`/`luna`. **Update the CLI
first, then read its model list.** Reading the list first gives a confidently wrong answer.

### W1 RESULT — verified inventory (measured 2026-08-10, live reads only)

Every cell below was established by running the command in its row. A cell that could not be
measured reads `UNKNOWN` and says which command failed to establish it.

| # | Backend | Authenticated? | Which plan | Bills outside that plan? | In scope | Command that established it |
|---|---|---|---|---|---|---|
| 1 | **Codex CLI** 0.147.0 | ✅ yes | **ChatGPT Plus** | **No** — `stored API key false`, transport is `wss://chatgpt.com/backend-api` | ✅ **IN** | `codex doctor` → `stored auth mode chatgpt` · `stored API key false` · websocket `HTTP 101`; `chatgpt_plan_type:"plus"` decoded from `~/.codex/auth.json` id_token |
| 2 | **Claude Code** 2.1.220 | ✅ yes, all 4 | **4× Claude Max** | **No** — OAuth via keychain, `usage_credits_authorized:false` guards PAYG | ✅ **IN** (already) | `claude-accounts --login-status` → exit 0 (silent = its contract); `--readout` renders 4 rows; version from `~/.claude-220/node_modules/.bin/claude --version` |
| 3 | **Antigravity** 1.107.0 | ✅ yes (Google OAuth, `ichris96@hotmail.com`) | **UNKNOWN** | **UNKNOWN** | ❌ **OUT — no headless mode** | `antigravity --help` → pure VS Code option surface (`--install-extension`, `--user-data-dir`, `--add-mcp`); **no exec/agent/headless subcommand exists**. Auth shared from `~/.gemini/oauth_creds.json`; id_token carries **no** plan/tier claim, and `grep -rE '"(tier\|plan\|subscription)"' ~/.gemini/` returns nothing |
| 4 | **Grok CLI** | ❌ not installed | **none held** | **YES — metered xAI API** | ❌ **OUT — cost gate** | `npm view @xai/grok-cli` / `@x-ai/grok-cli` → **404, no official xAI CLI on npm**. Community `@vibe-kit/grok-cli@0.0.34` README: *"Get your Grok API key from X.AI"*, endpoint `https://api.x.ai/v1`, flag `-k, --api-key`. **No OAuth/subscription login path exists** |
| 5 | **Pi · Codex backend** | ❌ not installed | **ChatGPT Plus** (held) | **No** | ✅ **IN — install** | `npm view @earendil-works/pi-coding-agent` → `0.84.1`, MIT, published 2026-08-07, bin `pi`. README § Providers & Models, **Subscriptions:** `OpenAI ChatGPT Plus/Pro (Codex)` |
| 6 | **Pi · Claude backend** | ❌ not installed, **and must stay that way** | Claude Pro/Max auth works, but usage does **not** draw on the plan | **🚨 YES — per-token "extra usage"** | ❌ **OUT — cost gate FAIL** | `docs/providers.md` § Claude Pro/Max (shipped inside the installed package): *"Third-party harness usage draws from **extra usage** and is **billed per token, not against Claude plan limits**."* Cross-checked against `~/.claude/accounts.json` → `spend.usage_credits_authorized: false` |
| 7 | **Gemini CLI** 0.29.5 *(7th backend — not in the original six)* | ✅ yes, but token stale | **UNKNOWN** (free Code Assist individual vs paid Google AI — not establishable from disk) | **No metered path wired** — every API-key env var is unset | ⚠️ **DEFER** — plan tier UNKNOWN | `~/.gemini/settings.json` → `auth.selectedType: "oauth-personal"`, `model.name: "gemini-3-pro-preview"`; `printenv` → `GEMINI_API_KEY`/`GOOGLE_API_KEY`/`GOOGLE_CLOUD_PROJECT` all unset; `oauth_creds.json` access_token expired **2026-02-23** (refresh_token present) |

**Verdict: 3 routable agents IN (Codex CLI, Claude Code, Pi·Codex), 3 OUT, 1 DEFERRED.**
Nothing was signed up for; no payment details were entered anywhere.

**🚨 The correction this gate exists to catch — `pi-claude` FAILS, and the README is why it nearly
didn't.** Row 6 first read ✅ IN on the strength of Pi's README, which lists under **Subscriptions:**
`Anthropic Claude Pro/Max` — a true statement about *authentication*, and silent about *billing*.
The package's own `docs/providers.md` supplies the missing half: *"Third-party harness usage draws
from extra usage and is **billed per token, not against Claude plan limits**."* So `pi-claude`
authenticates against a plan we hold and then spends money **outside** it — the exact shape the
frozen scope forbids. This repo already had the standing answer on disk: `accounts.json` →
`spend.usage_credits_authorized: false`, whose own note calls any nonzero `extra_usage.used_credits`
*"a BREACH to surface, not a stat to render"*. **Verdict: SKIP, do not wire, do not `/login claude`
from pi.**

**Why:** "which subscriptions can this tool log into" and "what does using it bill" are two
different questions, and a subscription *login list* answers only the first. The gate has to ask
the second explicitly, of a source that discusses billing — a feature list will never volunteer it.
Had the README been the only source consulted, this session would have wired a per-token meter into
a fleet whose standing policy is that per-token spend is unauthorised.

**Consequence — Pi's headline value collapses under the gate, and the plan should say so.** The plan
called Pi *"the highest-value gap … two more agent backends at zero marginal subscription cost"*.
After measurement, exactly one of the two survives, and it is the one with the least to add:
`pi-codex` rides **the same ChatGPT Plus subscription the Codex CLI already rides**, so it is an
*alternative harness over capacity we already have*, not new capacity. The backend that would have
added genuinely new capacity — Claude-backed — is precisely the one that bills outside the plan.
Pi is still worth having installed (a second harness, MIT, `--print` non-interactive mode, its own
skills/extensions), but it is **not** a capacity win, and `/accounts` must not imply it is.

**Finding that corrects the plan's own premise — Antigravity is not an agent backend at all.**
The plan (and grok-wiki's picker) counted six *agent backends*. Antigravity's `--help` is byte-for-byte
a VS Code launcher: it opens the editor GUI and has no non-interactive invocation path. So it cannot
be routed to from claude-infrastructure whatever its plan turns out to be — its auth question is
**moot, not merely unmeasured**. This is the *"a binary exists on PATH"* → *"it is an agent backend"*
conflation: grok-wiki reported `ready` on the strength of `command -v antigravity` alone. Three
separate facts — **binary present**, **authenticated**, **has a headless agent mode** — and only the
third decides routability. W3's detector must test the third, never the first.

**Landmine 1 reproduced live, not taken on faith.** `~/.codex/models_cache.json` on disk was written
by the OLD client (`client_version: 0.142.2`) and listed 5 models — **not including `gpt-5.6-sol`,
the very model already pinned in `config.toml`**. Running the 0.147.0 client refreshed it to 8 and
revealed `gpt-5.6-sol` (priority 1, `visibility: list`), `gpt-5.6-terra` (2), `gpt-5.6-luna` (3).
Reading the list before updating would have concluded the pin was invalid. Order is load-bearing.

**Note for W2 — Pi ships this discipline as a command:** `pi update --models` forces a catalog
refresh, so the landmine-1 order (update CLI → refresh catalog → read list → pin) is executable
rather than manual.

**A subscription window inside a token is a snapshot, not a live entitlement.** Codex's id_token
carries `chatgpt_subscription_active_until: 2025-12-05`, stamped at the last interactive login
(`auth_time` = 2025-12-01) — eight months stale, while the token itself was refreshed 2026-08-10.
The live proof of entitlement is the successful `HTTP 101` handshake to the ChatGPT backend, not the
embedded date. Same shape as the Claude login-cliff lesson in `accounts.json § _login`: a refresh
renews the access token and does **not** restate the subscription claim.

## W2 — Update every in-scope CLI to latest + pin latest model

Only for backends W1 cleared. Per backend: update the CLI, refresh its model list, pin the best
model + a sane global reasoning/effort default, then **prove the pin with a real invocation that
prints the model id** — never trust a config write.

**Landmine (measured this session):** passing a `--reasoning`/`--model` flag through a wrapper can
be silently ignored — no error, just quietly worse output. The governing value was the provider's
own config file the whole time. **Verify by running the agent and reading the model/effort it
reports**, exactly as `codex exec` prints `model: gpt-5.6-sol`.

## W3 — Extend `/accounts` from Claude-only to multi-provider

Today `~/.claude/accounts.json` declares itself *"SSOT for the 4 Claude Max accounts"* and every
field is Anthropic-specific (`keychain_account`, `oauth_client_id`, `usage_endpoint`,
`token_endpoint`). Consumers: `bin/claude-accounts`, `/accounts`, `scripts/handoff-fire.sh`,
`skills/account-relogin`.

**Design constraint — do NOT break the existing contract.** The Claude rows, the router footer, the
`--json` field names, `--rank`, `--route`, `--login-status` exit codes, and the canonical readout
columns are consumed by four callers and pinned by `tests/claude-accounts-core.bats`. Extend
additively: a **separate provider section**, not new columns grafted onto the Claude table.

Open design question for the wave lead (decide with evidence, record the why here): does the
multi-provider view belong in `claude-accounts` itself, or in a sibling `cc-agents` that composes
it? Weigh against the renderer rule — there must remain exactly ONE renderer per artifact.

## W4 — Docs + tests

- `/accounts` command doc gains the multi-provider section (INTEGRATE, never overwrite).
- A bats suite per new surface. **Pin the terminal and the provider env** in `setup()` — this repo
  has been bitten repeatedly by suites that silently become a function of the developer's
  environment (see backlog item on `KITTY_WINDOW_ID` inheritance).

---

## Status log

- **2026-08-10** — Plan created. Codex CLI updated 0.142.2 → 0.147.0 and pinned to `gpt-5.6-sol` @
  `xhigh` (verified live). Six backends inventoried; Pi (×2) identified as the zero-marginal-cost
  gap. Grok CLI and Antigravity flagged for the W1 cost gate. No other change landed yet.
- **2026-08-10 — W1 DONE.** All six backends verified from live reads (+ a 7th, Gemini CLI, found
  installed and folded in). Verdict **3 IN / 2 OUT / 1 DEFERRED**; nothing signed up for.
  Learnings that change later waves:
  (a) **Antigravity is not an agent backend** — its CLI is the VS Code launcher, no headless mode,
  so W3's detector must test *"has a non-interactive agent mode"*, never *"binary is on PATH"*
  (the exact conflation that made grok-wiki report it `ready`).
  (b) **Landmine 1 reproduced live** — the on-disk model cache was written by the old client and
  omitted the very model already pinned; only the updated client's refresh revealed it.
  (c) **Pi clears the cost gate on primary-source evidence** — its README lists ChatGPT **Plus**/Pro
  and Claude Pro/**Max** as subscription logins, and we hold Plus + 4× Max. The plan's original
  wording ("ChatGPT Plus/Pro") left open whether Plus specifically qualified; it does.
  (d) **Grok has no official CLI on npm at all** (`@xai/*`, `@x-ai/*` → 404) and every community
  one is API-key-only against `api.x.ai` ⇒ SKIP, documented, never signed up for.
  (e) **A subscription window embedded in a token is a stale snapshot** — Codex's id_token claims a
  window that closed 2025-12-05 while the account is demonstrably live; entitlement is proven by
  the transport handshake, not the claim.
- **2026-08-10 — W1 CORRECTED after installing Pi (same day, before any wiring).** Row 6
  (`pi-claude`) flipped ✅ IN → ❌ **OUT**. The README's subscription list is an *authentication*
  list; the package's `docs/providers.md` states the *billing* term — Claude Pro/Max via a
  third-party harness bills **per token from extra usage, not against plan limits** — which
  `accounts.json spend.usage_credits_authorized:false` forbids. **Lesson: ask what it BILLS, not
  just what it can LOG INTO, and ask a source that discusses billing.** Net effect: Pi contributes
  one backend (`pi-codex`), riding the same ChatGPT Plus the Codex CLI already uses, so it is a
  second harness rather than added capacity. The plan's "highest-value gap" framing does not
  survive measurement.
- **2026-08-10 — W2.** `@earendil-works/pi-coding-agent@0.84.1` installed globally
  (`--ignore-scripts`; the package has no install scripts, only `prepublishOnly`, so the flag is
  harmless). Codex CLI already latest (0.147.0) + pinned (`gpt-5.6-sol` @ `xhigh`) + **proven by
  invocation**. Claude Code deliberately NOT touched: its version is governed by this repo's own
  `cc-version-audit` / MANIFEST discipline and it is the binary running this session — bumping it
  from inside a plan about provider inventory would be scope-metastasis.
  **⛔ `pi-codex`'s model pin is BLOCKED on an operator-only step:** `pi` ships no headless login
  (`pi auth` only *prints/checks*; `/login` is interactive-mode only), its credential store is its
  own (`pi auth check --provider openai` → `credentials_not_configured` — it does **not** inherit
  Codex's tokens), and **the model catalog itself is gated behind auth** (`pi --list-models` → *"No
  models available. Use /login"*). So the latest model cannot be read, let alone pinned or proven,
  until the operator runs `pi` → `/login` → **OpenAI Codex**. Transplanting Codex's tokens into
  `~/.pi/agent/auth.json` by hand was rejected: improvising an auth path around a vendor's own
  login flow is exactly the unproven-mechanism risk this plan's landmines warn about.
- **2026-08-10 — W3 DONE** (`513224f9`). Provider section shipped **inside** `bin/claude-accounts`,
  not as a sibling `cc-agents`. **Open design question from the plan, now decided with evidence:**
  `render_readout`'s own docstring records that it exists *to be* the single renderer, having
  replaced ~200 lines of prose in `commands/accounts.md` that made the model rebuild the table by
  hand — so a second program rendering "what agent capacity do I have" would recreate precisely the
  drift that function was written to delete. `render_providers()` is therefore the ONE formatter,
  and both entry points (`--readout` appends, `--agents` prints alone) call it.
  Registry is a **separate tracked file** `providers.json` (symlinked to `~/.claude/providers.json`
  by `install.sh`): `accounts.json` declares itself SSOT for the 4 Claude Max accounts and is
  gitignored for real emails, so provider facts would have been both misplaced and unversioned
  there — and the cost verdicts are exactly what must survive in history, so a SKIP stays skipped
  for a recorded reason.
  **Contract held:** Claude rows, router footer, `--json` field names and the
  `--rank`/`--route`/`--login-status` exit codes untouched; `providers` rides as a sibling key;
  `--no-agents` returns the historical readout; an unreadable registry appends nothing.
  **110 tests green across 5 suites, 0 failures.**
- **2026-08-10 — W4 DONE** (`7962af94`). `commands/accounts.md` extended additively;
  `tests/claude-accounts-providers.bats` = 10 tests with TERM/NO_COLOR/provider-API-key env and
  **PATH itself** pinned in `setup()` (so `installed` is decided by the fixture, never by what the
  developer has globally). **Mutation-verified:** swapping the routability rule for `bool(exe)` —
  the presence-equals-routable defect — turns tests 2 and 4 red while the positive control (test 3)
  stays green, so the suite discriminates for the stated reason instead of passing vacuously.

## Remaining / known open

1. **⛔ `pi-codex` is installed and cleared but UNAUTHENTICATED** — operator-only browser OAuth
   (`pi` → `/login` → **OpenAI Codex**). Filed: backlog `c85038c4434f`. Until it runs, `pi` has no
   model catalog, so W2's pin+prove cannot complete for this backend. **Do NOT select
   `Claude Pro/Max` in that menu** (per-token extra-usage billing — see the W1 correction).
2. **Gemini CLI plan tier UNKNOWN** — free Code Assist individual and a paid Google AI subscription
   are indistinguishable from disk. Resolving it needs an authenticated Google account check the
   operator owns. Until then it stays DEFERRED, which is the cost gate working, not a gap.
3. **`~/.claude/providers.json` symlink is dangling until this branch lands** — it points at the
   shared checkout, where the file only appears on the fast-forward. Degrades to "no provider
   registry" meanwhile (pinned by test 1). *A file a diff ADDS is absent, not stale — it gets no
   converge budget; re-verify the link resolves after landing.*
4. **Antigravity's plan stays UNKNOWN by design.** Its routability is already settled by the
   absence of a headless mode, so measuring the tier would change no decision — recorded rather
   than chased.
