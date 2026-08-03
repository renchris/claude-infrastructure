---
status: research-complete
author: relogin-research (fired PEER session)
date: 2026-07-25
supersedes-input: docs/plans/RELOGIN_AUTOMATION_PLAN.md (Phase-2 mechanism correction below)
---

# Fully-autonomous Claude Max relogin — ranked methods

**Goal:** relogin (recover a logged-out Claude Max account across `next/next2/next3/next4`)
that needs **zero human clicks**, robust across all 4 accounts.

Every feasibility claim below is tagged **[PROBED]** (measured on this machine 2026-07-25),
**[SUBAGENT]** (web/binary research, source cited), or **[SPECULATION]**. Confidence is
`CONFIRMED / LIKELY / SPECULATION`.

---

## BLUF — the recommended method

> **The interactive browser "Authorize" consent is irreducible — it cannot be prevented
> headlessly. So the winning strategy is not to *avoid* it but to (a) make it *rare* and
> (b) *execute it autonomously* when it is needed.**

**RECOMMENDED (Method A) — two layers:**

1. **Frequency-killer: `claude setup-token` → `CLAUDE_CODE_OAUTH_TOKEN` per launcher.**
   A 1-year, Max-quota bearer token that is **structurally immune to all three
   refresh-token death modes** (it has `refreshToken:null` → no cliff, no rotation race,
   no idle-death). Cuts interactive relogin from **~monthly-or-worse per account to ~once
   a year per account**, and eliminates the concurrent-session logout race that is the
   *likely* cause of today's frequent logouts. **[SUBAGENT: CONFIRMED, binary + docs]**

2. **Zero-human executor: a dedicated, per-account, consent-free CDP browser.**
   One Dia instance **per account**, seeded from that account's warm claude.ai profile,
   launched with its **own `--remote-debugging-port`** (consent-free by construction) and
   `navigator.webdriver=false`. It completes the (now yearly) Authorize consent — and any
   full-scope recovery — with no human: navigate the OAuth URL in the warm profile → the
   session is already trusted so Cloudflare passes and the Authorize renders directly →
   click via trusted CDP event → the loopback callback auto-completes the CLI. **The
   infrastructure already exists** (`~/bin/dia-cdp-launch.sh` `DIA_SEED_FROM_DEFAULT`).
   **[PROBED + SUBAGENT: LIKELY]**

**RUNNER-UP (Method B)** — if setup-token's *inference-only scope* turns out to break the
fleet (Remote Control / MCP connectors / file-upload): apply **layer 2 alone** to the
existing monthly `/login` path, paired with a **single-flight refresh coordinator** to kill
the rotation race. Zero-human, full-scope, but fires ~monthly instead of ~yearly.

**The one decision that gates Method A vs Method B:** *does any fleet workflow need a
full-scope login token* (Remote Control, claude.ai-hosted MCP connectors, file upload,
`user:sessions:claude_code`)? If **no** → Method A. If **yes** → Method B (or Method A for
inference sessions + full-scope login only where required). This is the single operator
call surfaced by this research (see §7).

> ## ⛔ MEASURED 2026-08-03 — METHOD A IS DEAD. Do not re-run this experiment.
>
> The gating curl was finally run against a real minted token (canary on `next2`,
> `chris.swe+claude@outlook.com`), with a full-scope keychain bearer alongside it as a positive
> control so the result is attributable rather than ambiguous:
>
> ```
> setup-token (user:inference only)  -> HTTP 403
> keychain    (full 5 scopes)        -> HTTP 200   <- positive control
> ```
>
> `https://api.anthropic.com/api/oauth/usage` **rejects the inference-only scope.** The control
> proves the endpoint is healthy, so the scope is the cause and nothing else. Adopting Method A
> fleet-wide blinds the whole quota spine — `/accounts`, the router, `limit-recover`, the desk.
>
> **The split does NOT rescue it.** Method A for inference + full-scope login where required still
> needs a live full-scope keychain login per account for quota reads, and that login still carries
> the ~30-day `refreshTokenExpiresAt` cliff. The monthly interactive `/login` survives either way,
> while every token session gives up four scopes. The 1-year token buys nothing that was actually
> being bought.
>
> **Two of this document's own premises, corrected by measurement:**
> * §4A.1's "IT STORES NOTHING" is **false**. The mint wrote a keychain credential — the
>   *unsuffixed* `Claude Code-credentials` item's access AND refresh tokens both rotated at
>   00:47:14Z, the exact minute it ran. `mint()` calls the raw binary, bypassing the `claude()`
>   shell function that is the only thing exporting `CLAUDE_CONFIG_DIR`; the keychain suffix is
>   gated on that var being *set*, so an unset var writes the unsuffixed item.
> * The premise that made Method A look necessary — "the concurrent-session logout race is the
>   *likely* cause of today's frequent logouts" — is **refuted**. The real cause was a dangling
>   `.oauth_refresh.lock` symlink this repo's own `config-mirror.zsh` created, making every
>   in-session refresh read as permanently ELOCKED. Fixed in `1677218f`; evidence in
>   `docs/research/forced-relogin-rootcause-2026-08-02.md`. With that fixed the residual is the
>   ordinary ~30-day cliff, which Method A cannot remove anyway.
>
> **Standing recommendation: keep the full-scope keychain logins.** Method B's single-flight refresh
> coordinator is also moot for the observed failure — 2.1.220 already ships CAS + a single-flight
> lock + sibling adoption. Refresh-token ROTATION is now confirmed by direct observation (`next` rt
> `0023ef9690b1 → a9f8aadf29eb`, `next2` `26fc87c99eba → 87163b4d1b78` across one grant), so C2 is
> real in principle — but the mitigation worth doing is collapsing account `next` from its FOUR
> credential stores to one, not adopting setup-token.

---

## 1. What changed vs the problem statement (verified, then extended)

The launch brief's six facts were re-verified; the important corrections:

| Brief premise | Verdict after probing | Evidence |
|---|---|---|
| Consent sits behind Cloudflare + **hCaptcha** | Edge is Cloudflare **Managed Challenge / Turnstile**, not hCaptcha. The challenge is on the **/login** step; a warm session **skips /login** → Authorize renders directly. The local "hCaptcha" sighting was a Turnstile widget or a login-step captcha hit from a *non-warm* profile. | [SUBAGENT: CONFIRMED] claude-code#33269, #68674 |
| CDP 9222 is "bound to the Default profile" | More precise: CDP sees **only profiles with an open window**. `Local State.last_active_profiles=['Default']` → the other three simply had no window. You **cannot** `createTarget` into a cold on-disk profile (no `browserContextId` exists for it). | [PROBED] + [SUBAGENT: CONFIRMED] |
| Prevent the cliff by re-minting the refresh token headlessly (seed direction #1, "likely the winner") | **Refuted for the calendar cliff.** A refresh grant renews the *access* token but does **not** move `refreshTokenExpiresAt`. See §2 — this is the decisive finding. | [PROBED: CONFIRMED] |
| Warm profile passes the consent without challenge | **Likely yes** — the warm profiles already hold `cf_clearance` (proof they cleared Cloudflare) + anthropic session cookies. A CDP-*attached* (not automation-*launched*) warm browser on the same residential IP passes silently. | [PROBED] + [SUBAGENT: LIKELY] |

**New wall discovered (the real one):** the operator's single Dia exposes CDP on a
**WS-only** port (`/json/version` + `/json/list` both 404 [PROBED]), and every *new* WS
attach fires a **per-connect consent modal** (stock Chromium 144+, non-persistable by
design [SUBAGENT: CONFIRMED, chrome-devtools-mcp#825]). Combined with "cold profiles are
invisible," the shared-Dia path (the stalled plan's Phase 2) **cannot** be made autonomous.
That is exactly the human gate the live session hit. The fix is a **dedicated per-account
instance** (Method A layer 2), which sidesteps *both* the consent modal (own port = no
runtime-request gate) *and* the cold-profile problem (its profile is always the live one).

---

## 2. Decisive finding — the "cliff" is a 3-cause refresh-token death, and none of the three is preventable headlessly for recovery

The keychain OAuth blob (read live, secrets redacted) **[PROBED]**:

```
fields = [accessToken, expiresAt, refreshToken, refreshTokenExpiresAt, scopes,
          subscriptionType(=max), rateLimitTier]
```

| acct | access-token expiry | refreshTokenExpiresAt | RT window |
|---|---|---|---|
| next  | 2026-07-25 04:18 (refreshed) | 2026-08-02 13:21 | ~8d |
| next2 | 2026-07-25 04:18 (refreshed) | 2026-08-17 12:52 | ~23d |
| next3 | (logged out, no tokens) | 2026-08-08 01:07 (stale meta) | — |
| next4 | 2026-07-25 07:13 (refreshed today) | **2026-07-25 12:39** | **~0d (at cliff today)** |

**Two independent proofs that a refresh grant does NOT extend `refreshTokenExpiresAt`:**

1. **next & next2** were refreshed at the *same minute* (access expiry 04:18) yet their
   `refreshTokenExpiresAt` are **15 days apart** (Aug 2 vs Aug 17). If refresh slid the
   window, both would land at `now + window`. They don't → the field is anchored to each
   account's **last interactive `/login`**, ~15 days apart.
2. **next4** was refreshed **today** (access expiry 07:13) yet its `refreshTokenExpiresAt`
   expires **today** at 12:39. A today-refresh under a sliding model would push the window
   ~30 days out; it left it at today → the window is a **fixed ~30-day deadline** anchored
   to interactive login (~Jun 25 for next4), untouched by the refresh.

This confirms the `claude-accounts` login-cliff model (`feat/accounts-login-cliff`,
`bin/claude-accounts:577` reads `refreshTokenExpiresAt`; `:582-587` skips heal past the
cliff because "every refresh grant answers `invalid_grant`") **[PROBED]**, and refutes seed
direction #1 for the **calendar** cause.

> **Adversarial note (a subagent disputed this).** One research subagent, working from
> binary `strings`, reported that `refreshTokenExpiresAt` "does not exist" and that expiry
> is idle-based/sliding. **The direct keychain read above overrides it:** the field is
> present in the live blob on this machine, with values that exactly match the tool's
> `--login-status` output (next4 "EXPIRING Sat 12:39"). The subagent's method (strings scan)
> misses server-supplied JSON keys that have no client-side string literal; the field almost
> certainly arrives in the OAuth token response and is persisted. **But the subagent surfaced
> two real *additional* death modes**, integrated below.

### The unified model: the refresh token dies at the EARLIEST of

- **C1 — calendar cliff:** `refreshTokenExpiresAt`, ~30 days, anchored to last interactive
  login, **not** extended by refresh. **[PROBED: CONFIRMED]**
- **C2 — rotation race:** refresh tokens are **single-use**; with N concurrent sessions per
  account, session B's refresh rotates the token, session A's stale token → **HTTP 400
  `invalid_grant`** → forced `/login`, *before* the calendar deadline, unpredictably.
  **[SUBAGENT: CONFIRMED]** claude-code#54443, #24317, #48786.
- **C3 — idle-death:** extended inactivity invalidates the refresh/session. **[SUBAGENT:
  LIKELY]** opencode#9111. Secondary for an active fleet.

**Recovery from any of the three requires a browser Authorize** (device-authorization grant
RFC 8628 is an *open, unimplemented* request — #20215/#22992 [SUBAGENT: CONFIRMED]).
Therefore **zero-human relogin ⟺ autonomous browser-Authorize**. Everything else is about
making that event *rarer* (setup-token dodges C1/C2/C3; a single-flight refresh coordinator
mitigates C2/C3; Phase-1 refresh-first keeps the access token fresh between events).

---

## 3. Method ranking

Scored on **robustness × autonomy × safety**, with implementation effort. "Autonomy" =
fraction of relogins needing zero human action.

| # | Method | Autonomy | Robustness | Safety | Effort | Verdict |
|---|---|---|---|---|---|---|
| **A** | **setup-token (1yr) + dedicated per-account consent-free CDP browser** | **~100%** (1 automated mint/acct/yr) | **High** — dodges C1/C2/C3; browser step rare | High (genuine-trust only) | **M** (both layers; infra exists) | **★ RECOMMENDED** |
| **B** | Dedicated per-account CDP browser on the `/login` path + single-flight refresh coordinator | ~100% (but fires ~monthly) | Med-High — full scope kept; race fixed by coordinator | High | M–L | **Runner-up** (use if scope gates A) |
| C | setup-token with a **human** yearly mint (drop layer 2) | ~99% of *time*, but not zero-click | High | Highest (no automation surface) | S | Good fallback / interim |
| D | Phase-1 headless refresh-first (existing heal) | Partial — access only; can't survive C1/C2/C3 | — | High | (built) | **Keep as a precondition gate, not a relogin method** |
| E | Attach to the operator's shared warm Dia via 9222 (stalled plan's Phase 2) | ~0% autonomous | Low | Med (exposes all Spaces) | — | **Blocked** — consent modal + cold-profile invisibility |
| F | Prevent the calendar cliff by headless re-mint (seed #1) | — | — | — | — | **Refuted** (§2) |
| G | Direct keychain/`.credentials.json` blob injection | High | Low-Med | **Low** (unsupported; a bad write = logout) | S | Rejected — community hack, not Anthropic-supported |
| H | `ANTHROPIC_API_KEY` / `apiKeyHelper` | High | — | — | S | **Inapplicable** — bills API credits, not Max quota |
| I | OAuth device-code / TOTP headless login | — | — | — | — | **Does not exist** (open requests #20215/#22992/#74204) |

---

## 4. Recommended method — deep dive

### 4A.1 Layer 1 — setup-token as the frequency-killer  [SUBAGENT: CONFIRMED]

`claude setup-token` mints a **1-year** OAuth token (`sk-ant-oat01-…`, binary constant
`31536000`), authenticated by the **Max subscription** (not API credits), consumed via the
env var **`CLAUDE_CODE_OAUTH_TOKEN`** (or the leak-averse `CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR`).
It sits at credential precedence **position 5** — above the keychain blob, below API keys —
so a launcher that exports it runs with **no keychain read and no browser**.

**Why it dodges all three death modes:** when consumed, Claude Code builds the identity as
`{accessToken, refreshToken:null, expiresAt:null, scopes:['user:inference']}`. With
`refreshToken:null` the client **never runs a refresh grant** → no rotation (no C2 race), no
`refreshTokenExpiresAt` (no C1 cliff), and it is presented until the server 401s (no local
idle check; C3 N/A). It **coexists with** the keychain token (different storage) and does not
disturb the existing auto-heal.

**Per-account:** it's a plain env var, so each launcher (`claude-nextN`) exports its own token
→ effectively per-account. Mint 4 tokens (one Authorize each), store them (Keychain or an
`0600` file / FD), inject per launcher.

**The gating caveat — inference-only scope.** setup-token carries **only `user:inference`**;
it lacks `user:profile`, `user:sessions:claude_code`, `user:mcp_servers`, `user:file_upload`,
`org:create_api_key`. The binary refuses Remote Control ("*Long-lived tokens … are limited to
inference-only … Run `claude auth login` to use Remote Control*"). **Impact must be verified
before fleet-wide adoption** (§7): local stdio MCP servers (browsermcp, uidotsh) are spawned
locally and *likely* unaffected by the missing `user:mcp_servers` scope (that scope is for
claude.ai-hosted connectors), but Remote Control / connectors / file-upload **do** break.
Also **`--bare` ignores `CLAUDE_CODE_OAUTH_TOKEN`** — audit launcher flags.

**Residual:** 1 year is a *ceiling*, not a floor — server-side rotation/revocation or a
same-account interactive re-login can invalidate early (answeroverflow: "1-year token rotated
3×"), and there is **no `--list`/`--revoke` tooling** yet (#48373). Mitigation: re-mint on
detected 401, via layer 2 (below), so an early revocation self-heals with no human.

### 4A.2 Layer 2 — dedicated per-account consent-free CDP browser (the zero-human executor)

This is the load-bearing new capability. It completes the OAuth Authorize (whether the
yearly setup-token mint, or a full-scope `/login` recovery) with **no human**, and it is the
*correct fix to the wall the live session hit*.

**Mechanism, and why each leg defeats the wall:**

| Leg | Mechanism | Why it works | Evidence |
|---|---|---|---|
| Reach the right account's warm session | A **dedicated Dia instance per account**, `--user-data-dir` = that account's profile (copied, or canonically relocated), one per account | Its profile is *the* live profile of that instance → always CDP-addressable; no cold-profile invisibility | [SUBAGENT: CONFIRMED] |
| No consent modal | Launch with **`--remote-debugging-port=<unique>`** (9223/24/25/26) | A port you *open at launch* has **no runtime-request gate** — consent-free end-to-end (unlike `dia://inspect`) | [SUBAGENT + skill: CONFIRMED] |
| Warm cookies survive the copy | macOS "Dia Safe Storage" Keychain key is **binary-bound (per code-signature), not path-bound** — probed present | Any Dia instance with any `--user-data-dir` decrypts the copied profile with no re-login; app-bound/"v20" encryption is **Windows-only** | [PROBED: key present] + [SUBAGENT: CONFIRMED] |
| Pass Cloudflare | Warm profile already holds a valid `cf_clearance` (zone-wide pre-clearance of `/oauth/authorize`); CDP-**attach** keeps `navigator.webdriver=false`; same residential IP + real fingerprint | A genuinely trusted session is *served directly* — the JS env-probe doesn't even run while `cf_clearance` is valid | [PROBED: cf_clearance present] + [SUBAGENT: LIKELY] |
| Click Authorize | CDP `Input.dispatchMouseEvent` (isTrusted=true), `el.click()` fallback | Trusted event; robust to bot heuristics; the plan already specifies this | [SUBAGENT: CONFIRMED] |
| Capture the code | Prefer the **loopback** redirect (`localhost:{PORT}/callback`) → the warm session **auto-completes the CLI**; `code=true` display-mode scrape (`code#state`) is the cross-host fallback | Co-located browser+CLI → intercept the callback at the CDP Network layer, no DOM scrape | [SUBAGENT: CONFIRMED] |

**The infrastructure already exists.** `~/bin/dia-cdp-launch.sh` `DIA_SEED_FROM_DEFAULT=1`
already rsyncs a profile into a dedicated `--user-data-dir` and launches Dia with a debug
port, stating verbatim that the "Dia Safe Storage" key is *binary-bound, not path-bound, so
copied cookies decrypt without re-login.* Method A layer 2 is a **generalization** of this
from "clone Default" to "clone (or relocate) each account's profile," plus the OAuth-drive.

**The two real (operational) risks, both mitigable** [SUBAGENT: CONFIRMED]:

- **WAL-consistent copy.** Dia's `Cookies` DB is WAL-mode; a live copy must take `Cookies` +
  `Cookies-wal` + `Cookies-shm` **atomically**, or the source profile must be quit /
  checkpointed first. (`dia-cdp-launch.sh`'s rsync *excludes* `-wal/-shm`, so it currently
  assumes a closed source — for a live warm copy, copy all three.)
- **Concurrent second-Dia-instance flakiness on macOS** (reaped if shell-backgrounded;
  window buries; the keep-warm LaunchAgent is permanently disabled after a July-2026 profile
  wipe). Mitigation: launch on-demand per relogin via `open -n` from a foreground shell +
  `supervise <ttl>` for guaranteed teardown; fixed port per account.

**Architectural upgrade (recommended):** instead of a per-run *copy* (a drifting snapshot +
the WAL trap), **permanently relocate** each account to its own dedicated `--user-data-dir`
(canonical, not a copy). Then there's no per-run copy, no WAL race, and each account is
independently CDP-addressable at a fixed port. **Do not seed from `Default`** — `Default` is
`Personaly` = next's **personal** profile (bank/email cookies); migrate next (Claude1) into
its own dedicated profile rather than exposing the personal jar. **[PROBED: profile map]**

### 4A.3 Layer 0 — keep Phase-1 refresh-first + add a single-flight refresh coordinator

Retain the existing headless refresh-first heal (`CLAUDE_CODE_OAUTH_REFRESH_TOKEN` +
`CLAUDE_CODE_OAUTH_SCOPES` → `claude auth login`) as the cheap between-events access renewal
for any **full-scope** (non-setup-token) sessions. Add a **single-flight refresh coordinator**
per account (a `flock`'d refresh so only one process ever rotates the single-use token) to
eliminate the **C2 rotation race** for those sessions. Sessions on a setup-token don't need
this (no refresh token). **[SUBAGENT: LIKELY beneficial]**

---

## 5. Runner-up (Method B) and the rejected paths

**Method B — CDP browser on the `/login` path + single-flight coordinator.** Identical layer-2
executor, but driving `claude auth login --claudeai` (full scope) instead of a setup-token
mint. Use when the fleet needs full-scope tokens. Zero-human, full-scope; costs are (a) it
fires at the ~monthly C1 cadence (not yearly), and (b) it stays on the refresh model, so the
single-flight coordinator is *required* to prevent C2. This is the direct evolution of the
stalled `RELOGIN_AUTOMATION_PLAN` with its Phase-2 mechanism corrected (§7).

**Rejected / inapplicable** (see the ranking table): **E** shared-Dia attach (consent modal +
cold-profile invisibility — the wall); **F** prevent-calendar-cliff-headlessly (refuted §2);
**G** direct blob injection (works but unsupported; a malformed write is a logout — violates
the "only the official binary touches tokens" rail); **H** API-key/apiKeyHelper (bills API
credits, not Max quota — precedence positions 1–4); **I** device-code/TOTP (do not exist).

---

## 6. Safety-rail compliance + legitimacy framing

**Every method above honors the non-negotiable rails** (`RELOGIN_AUTOMATION_PLAN` "Hard
constraints", `account-relogin` "Hard rules", `reference-claude-accounts-tooling`):

- **Never `/logout`** as a fix — none of the methods log out. ✅
- **Never raw-POST a refresh token and discard the (rotated) response** — the design uses the
  **official binary** for every token operation (setup-token mint, refresh grant). It does
  **not** hand-roll the token exchange. (This also correctly rejects a subagent's "roll your
  own refresh keep-alive daemon" suggestion, which would risk discarding a rotation = a
  logout.) ✅
- **Never relogin an account with live sessions (`k>0`)** — the existing gate holds; layer 2
  fires only when a relogin is genuinely needed, under the per-account
  `/tmp/claude-accounts-heal-<acct>.lock` interlock. ✅
- **Never authorize in a context logged into a DIFFERENT account** — the *entire point* of the
  dedicated-per-account instance is that its profile is that one account's — the
  cross-account contamination trap (authorizing next3 inside next's Default) is
  **structurally impossible**, because each instance carries exactly one account's cookies. ✅
- **Never widen `oauth_scopes`** — setup-token *narrows* scope (inference-only); the `/login`
  path passes the SSOT scopes verbatim. ✅
- **`dia://inspect` toggle hygiene** — Method A/B use their **own** `--remote-debugging-port`
  and never touch the operator's `dia://inspect` toggle; teardown via `supervise`/`kill` +
  the `lsof` verify. ✅

**Legitimacy framing (important — 4 of 6 research subagents were auto-flagged for
"bot-detection bypass" reconnaissance).** This design is **authorized self-automation of the
user's own OAuth consent, in the user's own warm sessions, on the user's own machine and
residential IP.** It succeeds **because the session is genuinely trusted** — real fingerprint,
real residential IP, human-established login — which Cloudflare's Managed Challenge is
*designed* to pass. **The design explicitly EXCLUDES the adversarial-evasion techniques the
subagents surfaced** (fingerprint/JA3 spoofing, proxy rotation to defeat IP reputation,
`Runtime.enable` stripping / anti-detect browsers, captcha-solving services). If a genuine
warm session is ever challenged, the correct response is to **re-warm the profile or surface
to the human — never to deploy evasion.** Genuine trust is both the right posture and the more
robust engineering (evasion is an arms race; trust is stable).

---

## 7. Delta to the stalled `RELOGIN_AUTOMATION_PLAN`, and the one operator decision

**Actionable correction to the existing plan.** The plan's Phase 2 drives the OAuth consent by
**attaching to the operator's shared Dia** and mapping `browserContextId → profile`. This
research shows that path is **not autonomous**: (1) the shared 9222 is WS-only and every new
attach fires a human consent modal [PROBED], and (2) cold profiles have no `browserContextId`
and cannot be targeted [SUBAGENT: CONFIRMED] — exactly the wall the live session hit. **Switch
Phase 2 to the dedicated-per-account instance (Method A/B layer 2):** own `--user-data-dir` +
own port = consent-free and always-addressable. Everything else in the plan (fifo driver,
`Input.dispatchMouseEvent`, verify-by-effect, the k-guard + heal-lock, exit-code contract)
stays valid.

**The single operator call (surfaced, not decided here):**
**Does any fleet workflow require a full-scope login token** (Remote Control; claude.ai-hosted
MCP connectors; file upload; `user:sessions:claude_code`)?
- **No →** adopt **Method A** (setup-token everywhere) — the biggest, most-supported win: the
  monthly dance and the concurrency-race logouts both disappear; the browser step goes yearly.
- **Yes →** **Method B** for the full-scope sessions (+ single-flight coordinator), Method A for
  inference-only sessions. Verify with a one-shot test: mint a setup-token on one account, run
  a normal fleet session (agent-teams, handoff/cc-notify, local MCP, a build), and confirm
  nothing breaks.

---

## 8. Effort + recommended sequence

1. **[S] Verify the scope gate.** Mint one setup-token on a low-stakes account; run a full
   representative session; confirm MCP/agent-teams/handoff/Remote-Control status. Decides A vs B.
2. **[S] setup-token rollout (if A).** Per-launcher `CLAUDE_CODE_OAUTH_TOKEN` injection
   (mirror the existing secret-injection launchers); document the yearly re-mint; add a
   `sk-ant-oat01-` presence + expiry check to `claude-accounts`.
3. **[M] Generalize `dia-cdp-launch.sh` into a per-account relogin executor.** Canonically
   relocate 13/15/17 (and migrate next off `Default`) to dedicated dirs + fixed ports;
   WAL-atomic copy or relocation; the OAuth-drive (createTarget → trusted click → loopback
   auto-complete / `code#state` scrape → verify-by-effect).
4. **[M] Wire it as the corrected Phase 2** of `RELOGIN_AUTOMATION_PLAN`'s `bin/cc-relogin`,
   behind the existing k-guard + heal-lock; keep the exit-code contract.
5. **[S] Add the single-flight refresh coordinator** for any full-scope sessions (C2 fix).
6. **[S] Auto-heal on 401**: on a detected setup-token 401 (early revocation), fire the layer-2
   executor to re-mint — so even the yearly event is hands-off.

---

## 9. Residual risks / open questions (named, not hidden)

- **[GATE] Inference-only scope** (Method A) — must be verified against real fleet workflows
  (§7 step 1). The single highest-value unknown.
- **cf_clearance staleness** — a copied profile's `cf_clearance` may be >30 min old; a fresh
  Managed Challenge then runs and *could* sample a CDP `Runtime.enable` leak. Mitigation:
  pre-warm (navigate to claude.ai chat first to re-clear) and rely on the real residential
  fingerprint; do **not** add evasion. [SUBAGENT: LIKELY]
- **CLI-side token exchange is a *separate* Cloudflare gate** (`platform.claude.com/v1/oauth/token`)
  the browser's clearance doesn't cover — fine on the local residential IP, would 403/429 on a
  datacenter IP. Keep all token ops on the local machine. [SUBAGENT: CONFIRMED]
- **setup-token 1-year is a ceiling** — early server-side revocation possible; no list/revoke
  tooling; self-heal via layer-2 re-mint on 401.
- **Second-Dia-instance flakiness + WAL copy** — the load-bearing *operational* risks (§4A.2);
  mitigable, but the reason to prefer canonical relocation over per-run copy.
- **Cookie-copy portability is decrypt-*reasoned*, not decrypt-*proven* here** — the inline
  decrypt probe was blocked by the auto-mode security classifier (not worked around). Grounding:
  "Dia Safe Storage" key present [PROBED] + macOS v10 path-independent encryption + the
  already-working `dia-cdp-launch.sh` implementation. Impl-phase confirmation = launch a
  dedicated instance from a copy and observe a warm claude.ai render. [PROBED partial + SUBAGENT: CONFIRMED-by-analogy]
- **Version drift** — endpoints are migrating (`console.anthropic.com` → `platform.claude.com`;
  authorize host varies by CC version). Read them from `--relogin-info`/the binary at run time,
  never hardcode. [SUBAGENT]

---

## Appendix — probe log (this machine, 2026-07-25; secrets redacted)

- **Keychain blob shape + expiries** — `security find-generic-password -s <svc> -a chrisren -w`
  → `json.load`; printed only field names + epoch→date (never token values). §2 table.
- **login-cliff code** — `git show feat/accounts-login-cliff:bin/claude-accounts` grep:
  `refreshTokenExpiresAt` read `:577`; heal-skip-past-cliff `:582-587`; HTTP 400/401/403 terminal
  `:373-406`.
- **Dia topology** — `ps -Awwo pid,command` (all Dia procs share `--user-data-dir=…/Dia/User Data`,
  ArcCore/Chromium 150); `lsof -nP -iTCP -sTCP:LISTEN` → `Dia … 127.0.0.1:9222 (LISTEN)`;
  `DevToolsActivePort` present (9222 + `/devtools/browser/<uuid>`); `Local State.profile.info_cache`
  → Default=Personaly, Profile 13=Claude2, 15=Claude3, 17=Claude4; `last_used=Default`;
  `os_crypt` absent (macOS Keychain-based).
- **Live 9222 discovery** — `urllib` GET `/json/version` + `/json/list` → both HTTP 404 (WS-only).
- **Keychain key** — `security find-generic-password -s "Dia Safe Storage"` → present (also
  "Chromium Safe Storage", "Arc Safe Storage").
- **Per-profile claude.ai cookies** — read-only immutable SQLite; counts next=20/next2=21/next3=18/
  next4=18; `cf_clearance` present in next2/next3/next4 (next likely, list truncated).
- **CLI surface** — `claude-latest auth --help` (login/logout/status), `setup-token --help`
  ("long-lived authentication token (requires Claude subscription)").
- **Blocked (not worked around)** — inline cookie-decrypt portability proof (auto-mode classifier).

*Research corpus: 6 deep-research subagents (setup-token, RT-semantics, Cloudflare-on-warm,
CDP-multiprofile, non-interactive-auth, prior-art) + the machine probes above. Full source
citations inline. Two subagents' verdicts (RT-"sliding-window", "field-absent") were overridden
by direct measurement — recorded in §2 for auditability.*
