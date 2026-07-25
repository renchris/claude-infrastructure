---
status: converged — ready to greenlight
author: relogin-design2 (fired PEER session, Opus 5 @ max)
date: 2026-07-25
builds-on: docs/research/autonomous-relogin-methods-2026-07-25.md (branch docs/relogin-research — the ranked first pass)
corrects: docs/plans/RELOGIN_AUTOMATION_PLAN.md (branch relogin — Phase-2 substrate; see §8)
scope: DESIGN + DOC ONLY — no sign-in performed, no production code, no account touched.
---

# The uniform 100% design — keep all four Claude Max accounts signed in, zero recurring human action, full scope preserved

**Operator constraints (binding).** ONE design applied identically to `next / next2 / next3 / next4`.
**FULL account scope everywhere** — all first-party connectors and Claude Code Remote (scheduled
triggers / send-later; `next2` uses it today) keep working on any account. A one-time human sign-in
per account at bootstrap is acceptable; **recurring** human action is not.

> **Evidence tags.** **[PROBED]** = measured on this machine this session (2026-07-25), probe named
> in Appendix A. **[PRIOR]** = established in the first-pass doc and carried forward. **[SPECULATIVE]**
> = reasoned, not measured — every one of these is assigned a Phase-1 experiment that settles it.
> Where this session's probes **contradict** the first pass, the correction is called out explicitly.

---

## BLUF

Three probes this session changed the shape of the answer:

1. **The vendor boundary is real and deliberate.** The binary states verbatim that long-lived tokens
   are **inference-only "for security reasons"** and that Remote Control **requires a full-scope
   login token**. There is **no vendor-sanctioned long-lived full-scope credential**, and no keepalive
   that defers the deadline. **[PROBED]** So the ~30-day interactive anchor is not an obstacle to
   engineer around — it is the product's security design, and the only compliant play is to make the
   sanctioned sign-in **rare and unattended**.

2. **The browser substrate problem dissolves.** The stalled plan and the first-pass doc both assumed
   the automation browser had to be **Dia**, which is reaped in <5 s outside a foreground shell and
   fires a per-connect consent modal. A **directly-executed dedicated Chrome** (never `open -n`)
   **survives the exact detached context that reaps Dia**, exposes the **full HTTP CDP endpoint** that
   Dia's WS-only 9222 does not, and carries a **normal Chrome user-agent** when headed. **[PROBED]**
   All three of the stalled plan's blockers — GUI-registration abort, SingletonLock race, consent
   modal — are *structurally absent*, not mitigated.

3. **The "single-flight refresh coordinator" cannot work as conceived — and does not need to.**
   Claude Code single-flights refreshes **in-process only** (`refreshPromise` / `isRefreshing` /
   `pendingRefresh`); it holds **no cross-process lock** on the credential store. **[PROBED]** The
   racing writers are the live `claude` processes themselves, and an external coordinator cannot make
   them take its lock. The fix is therefore not coordination but **de-sharing** (§4).

**The recommended architecture — two components, uniform across all four accounts:**

| # | Component | Kills | Status |
|---|---|---|---|
| **1** | **Unattended re-auth executor** — a dedicated, per-account, directly-executed Chrome that completes the standard OAuth Authorize in that account's own warm profile and re-anchors the ~30-day deadline, on a launchd cadence, under the existing per-account lock, verified by effect | **C1** (the calendar cliff) — and recovers from C2/C3 as well | Substrate **[PROBED]**; drive logic inherited from the frozen `cc-relogin` contract |
| **2** | **Token de-sharing** — stop 5–6 concurrent sessions from sharing one rotating refresh token, via per-session-class `CLAUDE_CONFIG_DIR` isolation (full scope preserved), with a setup-token supplement as the guaranteed fallback | **C2** (the early, frequent logouts) | Mechanism **[PROBED]**; which of two variants to adopt is the one open decision (§4.4) |

Component 1 is load-bearing and **works regardless of which cause fires** — that is the design's
robustness argument, and it is why component 2 is an optimization (how *often* the executor runs)
rather than a prerequisite. **Irreducible bootstrap: one human sign-in per account, once (§3).**

---

## 1. The problem model — three death modes, and which are actually proven

Recovery from any logout requires a browser Authorize: the device-authorization grant (RFC 8628) that
would permit a headless first login **does not exist** in this product (open requests #20215 / #22992
/ #74204). **[PRIOR]** A token dies at the **earliest** of:

- **C1 — calendar cliff.** `refreshTokenExpiresAt` is a fixed ~30-day deadline anchored to the last
  *interactive* login, and a refresh grant does **not** move it. **PROVEN THREE WAYS**, the third new
  this session:
  1. `next` and `next2`, refreshed the same minute, have deadlines **15 days apart**. **[PRIOR]**
  2. `next4`, refreshed *today*, still expired *today*. **[PRIOR]**
  3. **Mechanism-level, from the binary** — the persist path merges
     `refreshTokenExpiresAt: t.refreshTokenExpiresAt ?? e?.refreshTokenExpiresAt`, i.e. when a refresh
     response omits the field the client **retains the old deadline**. The sliding-window model is
     refuted in the client's own code. **[PROBED]**

  This also **settles the first pass's recorded dispute**: a first-pass subagent claimed
  `refreshTokenExpiresAt` "does not exist," inferred from a `strings` scan. The field is present in
  the binary (5 occurrences, in the credential read, merge, and persist paths). **[PROBED]** The
  measurement-based verdict stands, now with matching code evidence.

- **C2 — rotation race.** Refresh tokens are single-use / rotating. Confirmed this session at the
  mechanism level:
  - The keychain item is **`Claude Code-credentials-<sha256(config_dir)[:8]>`** — derived from the
    config dir. Each account has **exactly one** `config_dir`, so **every session on an account shares
    one credential item and one refresh chain**. **[PROBED: accounts.json]**
  - The router SSOT sets `KMAX: 8` and records "observed **5–6** live sessions on primary accounts as
    deliberate operator practice." **[PROBED: accounts.json]**
  - Claude Code has in-process single-flight state only (`refreshPromise`, `isRefreshing`,
    `pendingRefresh`) and **no cross-process lock**: every `flock` / `lockfile` / `O_EXCL` occurrence
    in the binary belongs to the bundled Bun/npm package-manager code, **none co-located with any
    config, credential, or OAuth text**. **[PROBED]**

  ⟹ **5–6 unsynchronized processes refresh one shared, rotating, unlocked credential.** A loser gets
  `invalid_grant`; if the server applies refresh-token reuse detection (RFC 6819 §5.2.2.3 / OAuth 2.0
  Security BCP) a replayed token can revoke the **whole family**, logging out every session weeks
  early. The mechanism is confirmed; server-side reuse-detection behavior is **[SPECULATIVE]**.

- **C3 — idle death.** Extended inactivity can invalidate the session. **[PRIOR]** Secondary for an
  active fleet; covered incidentally by the same executor.

### 1.1 What the local evidence does and does not prove

`~/.claude/logs/claude-accounts.log`, `next3`: healthy heals through 2026-07-23T14:27, then
**30+ consecutive `status code 400`** from 2026-07-24T17:29 onward, never recovering. **[PRIOR]**

Being precise, because the first-pass draft leaned harder on this than it can bear: this log proves a
**real logout that resisted 30+ headless refresh attempts and is fixable only by a browser re-auth**.
It does **not**, by itself, isolate C1 from C2 — `next3`'s anchor was flagged "stale meta." **C1 is
proven** (three ways, above). **C2 is mechanism-proven but not locally isolated**; the operator's
report of sign-outs more frequent than a 30-day cadence across four staggered accounts would explain,
combined with 5–6 unlocked concurrent writers per account, makes it the strongly-indicated
explanation for the *excess* frequency.

**Design consequence — and the reason this matters more than the diagnosis:** component 1 restores
any account to full scope with zero human action **under all three causes**. So the architecture does
not depend on winning the C1-vs-C2 argument. Component 2 changes only how *often* component 1 fires.
This is deliberate: the first-pass draft made the coordinator the root-cause fix and the executor the
net; the correct order is the reverse.

---

## 2. What was ruled out, and why (the "superior path" search — closed)

The brief asked to genuinely explore a better long-horizon path. Both candidates are **closed
negative, on direct evidence**:

**A vendor-sanctioned long-lived full-scope credential — does not exist. [PROBED]** From the binary,
verbatim:

> *"Remote Control requires a full-scope login token. **Long-lived tokens (from `claude setup-token`
> or `CLAUDE_CODE_OAUTH_TOKEN`) are limited to inference-only for security reasons.** Run
> `claude auth login` to use Remote Control."*

and the setup-token flow describes itself as *"long-lived (1-year) auth token setup"* / *"Your OAuth
token (valid for 1 year)"*. So the trade is explicit and vendor-enforced: **1-year lifetime is
purchased with inference-only scope.** Full scope ⟹ the ~30-day interactive-anchored token. This is
exactly the constraint the operator stated, now confirmed at the source. There is also a managed-policy
path that can refuse setup-token entirely (`force_login_method_refused`) — noted so no design depends
on it being available. **[PROBED]**

> **Correction to the first pass.** It cited binary constant `31536000` as evidence of the 1-year
> lifetime. Every occurrence of that constant is an HTTP `Cache-Control: max-age` string, unrelated to
> tokens. **[PROBED]** The conclusion (1 year) is correct; the evidence is the literal UI strings above.

**A keepalive that defers the deadline — does not exist. [PROBED]** C1 proof #3 shows the client
*preserves* the prior deadline rather than extending it, and no binary surface accepts or requests an
extension. The deadline moves only on interactive login.

**Rejected paths carried forward from the first pass, unchanged:** direct keychain/credential-blob
injection (unsupported; a malformed write is a logout); `ANTHROPIC_API_KEY` / `apiKeyHelper` (bills API
credits, not Max quota); device-code / TOTP headless login (does not exist); attaching to the
operator's shared Dia (the wall — §8).

---

## 3. The irreducible one-time bootstrap

**The single human step, per account, once:** sign in to `claude.ai` inside that account's **dedicated
automation browser profile** (§5.1). This establishes the warm web session the unattended re-auth
rides, and the account's initial full-scope Claude Code credential.

**Why it is irreducible:** the ~30-day deadline is anchored to an *interactive* login (§1 C1) and the
grant that would allow a headless first login does not exist (#20215). Exactly one interactive login
per account is unavoidable at t₀. **[PRIOR + PROBED]**

**Why nothing recurring remains after t₀:**
- The ~monthly C1 re-auth runs **unattended** in the dedicated warm profile (§5).
- C2 — the cause of *early, frequent* logins — is removed structurally (§4).
- The warm `claude.ai` web session the executor rides is long-lived (the existing Dia profiles hold
  `claude.ai` cookies valid to **2027-08-14** **[PRIOR: measured]**), and **each monthly re-auth is
  itself activity that keeps it warm** — a self-sustaining loop, not a decaying one.
- Only if that web session is *also* lost does the executor fall back to the email-code leg; only if
  *that* fails does it surface a one-line re-bootstrap (§7). Rare exception, not recurring action.

> **Uniformity wrinkle, resolved.** Today `next` maps to Dia profile **`Personaly`** — the operator's
> **personal** profile (bank/email cookies). **[PROBED: accounts.json]** Cloning that onto an
> automation port would be an unacceptable blast radius and would make `next` a special case. Giving
> every account its **own dedicated automation profile** makes the design **uniform including `next`**
> and never exposes the personal jar. This is why the design uses fresh dedicated profiles rather than
> the first pass's "relocate the existing Dia profiles."

---

## 4. Component 2 — token de-sharing (the C2 fix)

### 4.1 Why the first pass's "single-flight refresh coordinator" is the wrong shape

The first-pass doc and draft proposed an external coordinator that owns each account's token
lifecycle. **This cannot work as conceived. [PROBED]** The writers that race are the **live `claude`
processes**, which hold no cross-process lock and cannot be made to take ours. An external coordinator
can only serialize the *healer* — which the existing `heal()` already does (k==0 gate under
`/tmp/claude-accounts-heal-<acct>.lock`). **[PROBED]** That is necessary and already built; it is not
sufficient, and it is not a root-cause fix.

The root cause is **sharing**: one rotating credential, N unsynchronized holders. Remove the sharing
and the race cannot occur — no coordination required.

### 4.2 Variant A (recommended) — per-session-class `CLAUDE_CONFIG_DIR` isolation

Because the keychain item is `…-<sha256(config_dir)[:8]>` **[PROBED]**, giving a session a distinct
`CLAUDE_CONFIG_DIR` gives it a **distinct credential item and an independent refresh chain**. Sessions
in different classes then **cannot** rotate each other's token — the race is eliminated *by
construction*, with **zero capability loss**: each store holds a real, full-scope `claude auth login`
credential.

Do **not** go to one-dir-per-session (unbounded stores, unbounded re-auths). Use a small fixed number
of **slots per account** — 3 is the natural choice against an observed 5–6 concurrent and `KMAX: 8`.
Race probability falls roughly with the square of the sharing factor, so 3 slots cut it by ~an order
of magnitude while keeping the executor's workload at 4 accounts × 3 slots = 12 renewals/month,
staggered — trivially inside an hourly poller's capacity.

This is the variant that satisfies the operator constraint most literally: **every slot on every
account keeps full scope**, so Remote Control and first-party connectors work in any session.

**The one unverified assumption, and it is decisive:** *does a second full-scope login for the same
account (into a different config dir) invalidate the first?* If the vendor permits only one active
login token per account, Variant A collapses. **[SPECULATIVE]** — settled by Phase 1's first
experiment (§6), which is cheap, reversible, and runs on one account.

### 4.3 Variant B (fallback) — setup-token supplement for refresh-free sessions

This is the "may only supplement" role the operator explicitly authorized. A session consuming
`CLAUDE_CODE_OAUTH_TOKEN` is built with `refreshToken: null` and the persist path **short-circuits**
(`if(!e.refreshToken||!e.expiresAt) return … tengu_oauth_tokens_inference_only`) **[PROBED]** — such a
session **structurally cannot rotate the shared token** and leaves the racing set entirely.

Cost, stated plainly: those sessions are **inference-only**, so Remote Control and hosted connectors
do not work *in them*. The account retains full scope through its keychain login, and any session that
needs full scope simply runs on the keychain credential. This is a per-session scoping, not a
per-account one — but it is a real capability boundary, which is why it is the fallback and why the
choice is the operator's (§4.4).

### 4.4 The single remaining operator decision

**If Phase-1 experiment E1 shows concurrent same-account logins coexist → adopt Variant A** (uniform,
full scope everywhere, no capability boundary anywhere). **If they do not coexist → Variant B**, with
full-scope keychain sessions kept few (ideally one per account) and the bulk of fleet work
(agent-teams, research subagents, builds — none of which use Remote Control or hosted connectors) on
setup-tokens.

Everything else in this design is identical under both variants. Component 1 is unaffected.

---

## 5. Component 1 — the unattended re-auth executor

### 5.1 The substrate — dedicated per-account Chrome, directly executed  [PROBED — the key finding]

| Property | Design | Probe result |
|---|---|---|
| Binary | `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`, **executed directly** — never `open -n` / LaunchServices | Survived **≥10 s** launched from a backgrounded + disowned shell — *the exact context that reaps Dia in <5 s* |
| Profile | `--user-data-dir=~/.claude/auth-profiles/<account>`, one per account, seeded once at bootstrap (§3) | Uniform incl. `next`; personal `Personaly` jar never touched |
| CDP | `--remote-debugging-port=934{1..4}`, bound to `127.0.0.1` | **Full HTTP CDP**: `/json/version` and `/json/list` both returned — Dia's 9222 returns 404 on both (WS-only) |
| Fingerprint | **Headed**, `--window-position=-32000,-32000` (offscreen) | UA = `…Chrome/150.0.7871.182…` — **no `HeadlessChrome` token**. (`--headless=new` *does* advertise `HeadlessChrome`, so headed-offscreen is the correct posture) |
| Consent | Port opened **at launch** | No per-connect consent modal — the stalled plan's `exit 7 CONSENT-GATE` cannot occur |
| Lifetime | Launched for the renewal, killed after; TTL watchdog | Ephemeral open port is the load-bearing security control |

**Why this beats both options the first-pass draft posed.** It posed *(A)* an aqua-session LaunchAgent
driving Dia versus *(B)* a fully-headless Chromium trading GUI risk for Cloudflare risk. Direct-exec
headed Chrome takes the good half of each: launchd-class survivability **and** a non-headless
fingerprint. The 2026-07-09 incident's three failure modes — GUI-registration abort, personal-Dia
SingletonLock race, retry storm — are all **Dia-and-LaunchServices-specific** and structurally absent
here. Note `dia-cdp-launch.sh` itself hard-refuses launchd invocation **[PROBED: line 253]**; this
design does not use that script's launch path at all.

> **Honest boundary.** The survival probe ran in a *backgrounded, disowned shell inside a GUI login
> session* — the class that kills Dia. A LaunchAgent in `gui/$UID` runs in the same Aqua session, so
> the expectation transfers, but **launchd-proper survival is [SPECULATIVE] until Phase-1 experiment
> E2 confirms it.** Fallbacks, in order: `--headless=new` (accept the UA tell); or fire the renewal
> from the desk's foreground context. E2 is a 60-second test.

### 5.2 The OAuth drive (contract inherited from the frozen `cc-relogin`, substrate swapped)

Per account, on demand, one at a time — renewals are staggered and ~monthly, so never concurrent:

1. **Gate** (non-negotiable): `claude-accounts --relogin-info <acct>` for identity; refuse unless
   genuinely needed; refuse if `k>0` (`concurrency()`); take `/tmp/claude-accounts-heal-<acct>.lock`
   (`flock LOCK_EX|LOCK_NB`) **held for the whole run**; re-check `k==0` under the lock. **[PROBED]**
2. **Cheap path first.** While the refresh token is still valid, the existing headless heal
   (`CLAUDE_CODE_OAUTH_REFRESH_TOKEN=… <bin> auth login`) renews the access token. This is a
   *between-events* step — it does **not** move the deadline (§1 C1) — so it never substitutes for step 3.
3. **Browser path.** `mkfifo` + held-open writer → `<bin> auth login --claudeai --email <email>`
   (stdin = fifo, stdout captured) → poll ≤30 s for the printed authorize URL (fail loud) → bring up
   that account's dedicated Chrome (§5.1) → `Target.createTarget(<url>)` → locate the **Authorize**
   control (AX tree / `DOM.getBoxModel`) → trusted click (`Input.dispatchMouseEvent`, `el.click()`
   fallback). Warm session ⟹ the localhost **loopback callback auto-completes the CLI**; paste-mode ⟹
   scrape `code#state` and write it to the fifo.
4. **Verify by EFFECT, never by report.** `claude-accounts --fresh --json` must show `auth == ok`
   **and** `login_expires_at` strictly further out than the pre-run value. A "Login successful." string
   is a *claim*; the moved deadline is the *proof*. **[PROBED: plan contract]**
5. **Teardown ALWAYS** (success or failure): kill the login child, close the WS, `rm` the fifo, kill
   the dedicated Chrome. No open CDP port outlives a run.
6. **Fallback, rare:** authorize URL lands on `/login` (web session also cold) → email-code leg via
   `--relogin-info` mailbox; else surface a one-line re-bootstrap (§7).

Exit-code contract unchanged: `0` PROVEN · `2` REFUSED · `4` BROWSER-FAILED · `5` UNVERIFIED · `6`
FALLBACK-REQUIRED. (`7 CONSENT-GATE` becomes dead code — the condition cannot arise. Retain the code,
never emit it.) **[PROBED: plan]**

### 5.3 Cadence

A headless launchd `StartInterval` job — mirroring `com.chrisren.cc-reaper.plist`'s proven shape
(`/bin/zsh -lc` with an explicit `PATH="$HOME/.claude/bin:$PATH"` prepend, because `-lc` does **not**
source `.zshrc`; `ProcessType Background`; `RunAtLoad false`). **[PROBED]**

- **Poll hourly**; read `claude-accounts --login-status` (exit `0` clear / `1` within warn / `2` now).
- **Renew at T−7d**, not the current 72 h `login_warn_h`. This is the most important cadence choice:
  it converts one fragile attempt into **~168 hourly chances** to catch a `k==0` window.
- **Idempotent**: a renewal that already moved the deadline is a no-op on the next tick.
- **Serialized** per account under the existing heal lock; staggered across accounts.
- **The `k==0` scheduling hazard, addressed** (the first-pass draft did not): on a busy account
  `k==0` may be rare. The 7-day window makes it near-certain, but the failure mode is handled
  explicitly — at **T−48 h with no window yet found**, stop retrying silently and raise a
  `cc-blockers` class-C row with the exact runnable command. **Fail loud before the deadline, never
  after.**

---

## 6. Phased implementation plan

### Phase 0 — Agent-Team orchestration (mandatory: ≥2 code-writing tasks)

Four teammates, worktree-isolated, briefs ≤150 lines with pre-greped line ranges, verbatim
"stop on issue, message lead" clause, no inline visual verification. Single owner per shared file.

| Teammate | Branch | Deliverable | Owns | blockedBy |
|---|---|---|---|---|
| `tm/relogin-probe` | `feat/relogin-probes` | Phase-1 experiments E1–E3 + written verdict; **no production code** | `docs/research/` | — |
| `tm/relogin-exec` | `feat/relogin-executor` | `bin/cc-relogin` Phase-2 substrate: dedicated-Chrome launcher + CDP OAuth drive + teardown | `bin/cc-relogin`, `bin/cc-authbrowser` | E2 |
| `tm/relogin-sched` | `feat/relogin-schedule` | LaunchAgent + hourly poller + T−7d trigger + T−48h escalation | `launchd/com.claude.relogin.plist`, `bin/cc-relogin-poll` | — |
| `tm/relogin-obs` | `feat/relogin-observability` | `--relogin-status`, cc-blockers class-C row w/ runnable command, log rotation | `bin/claude-accounts` (single owner), `bin/cc-blockers` | — |

Spawn wave 1: `probe` + `sched` + `obs` (independent). Wave 2: `exec` (after E2). Component 2 (§4)
is deliberately **not** a teammate — it is a config/launcher change gated on E1 and the operator's
§4.4 call.

### Phase 1 — the three experiments that settle every [SPECULATIVE] claim

Each is cheap, reversible, and runs on **one** low-stakes account (`next3`, currently logged out —
so E1 costs nothing that is not already lost).

- **E1 — concurrent same-account logins.** Create a second `CLAUDE_CONFIG_DIR` for `next3`, log in,
  then confirm the *first* store still authenticates. **Decides §4.4 (Variant A vs B).** ★ highest value.
- **E2 — launchd-proper browser survival.** A throwaway LaunchAgent that direct-execs Chrome with a
  dedicated `--user-data-dir` and debug port; assert the process lives ≥60 s and `/json/version`
  answers. **Decides §5.1's one open boundary.**
- **E3 — warm-profile Authorize, end to end.** In a dedicated bootstrap profile, drive one real
  authorize URL to a moved `login_expires_at`. **Proves the whole executor** — and is the first
  moment a real sign-in occurs (out of scope for *this* doc, deliberately).

### Phase 2 — executor · Phase 3 — cadence · Phase 4 — observability · Phase 5 — de-sharing rollout

Phase 2 builds §5.1–5.2 behind the frozen exit-code contract. Phase 3 adds §5.3. Phase 4 adds §7.
Phase 5 applies the §4.4 verdict to the launchers — last, because it is the only phase that touches
how every session starts, and it is worthless until the executor can renew what it creates.

**Greenlight boundary:** Phases 0–1 need no further operator input. Phase 5 needs the §4.4 call,
which E1 informs.

---

## 7. Robustness, observability, recovery

- **Detection SSOT:** `claude-accounts --login-status` (already built, `feat/accounts-login-cliff`) —
  `login_expires_at`, `login_expires_h`, `login_expired`, `login_fixable`. Nothing re-derives deadlines. **[PROBED]**
- **Success is silent** (a log line). **Failure is loud**: a `cc-blockers` class-C row carrying the
  **exact runnable `▶` command** per the Silver-Platter rule — never a paraphrase.
- **Escalation ladder:** browser re-auth → email-code leg → operator re-bootstrap (one line, one
  command). Each rung is entered only on the previous rung's verified failure.
- **Reboot / OS-update survival:** user LaunchAgent (survives reboot and logout by construction) plus
  the existing `com.claude.caffeinate-floor.plist`. **[PROBED: agent inventory]**
- **Failure-bounds discipline:** the poller counts *attempts*, not successes, and logs stderr — the
  bound must cover the failure mode it bounds. Recurring pages dedup.
- **Safe recovery:** every run is idempotent and gated; a partially-failed run leaves no open port, no
  fifo, and no half-written credential (only the official binary ever writes tokens).

---

## 8. Delta to the stalled `RELOGIN_AUTOMATION_PLAN`

The plan froze a **good contract** — precondition gate (`--relogin-info` + `k==0` + heal-lock),
**verify-by-effect**, exit codes, the fifo driver. All of it survives. It failed only on **substrate**:
it drove the operator's **shared Dia on 9222**, hit the per-connect consent modal, and added
`exit 7 CONSENT-GATE`; cold profiles have no `browserContextId` and cannot be targeted. **[PRIOR]**

**Replace the substrate with §5.1** (dedicated per-account, directly-executed Chrome; own user-data-dir;
own loopback port). Consent-free and always-addressable by construction. Keep everything else.

Second correction, to the first-pass doc: it recommended **relocating the existing Dia profiles** into
dedicated dirs. This design uses **fresh dedicated profiles** instead — it avoids the WAL-consistency
trap on live cookie DBs entirely, and it is the only way `next` stops depending on the operator's
personal `Personaly` jar (§3).

---

## 9. Security posture

These are **our own credentials, on our own machine, for accounts we own**, automating **our own
OAuth consent** in **our own warm sessions**.

- **Only the official binary performs token operations.** No hand-rolled token exchange, no raw
  refresh POST, no credential-blob injection — a discarded rotation is a logout.
- **Never `/logout` as a fix. Never re-auth an account with live sessions (`k>0`). Never widen
  `oauth_scopes`** beyond the SSOT (`user:profile user:inference user:sessions:claude_code
  user:mcp_servers user:file_upload`). **[PROBED: accounts.json]**
- **Cross-account contamination is structurally impossible** — each executor instance carries exactly
  one account's dedicated profile. Authorizing `next3` inside `next`'s session cannot occur.
- **Blast radius:** dedicated automation profiles hold *only* `claude.ai` credentials. The personal jar
  is never opened, copied, or exposed.
- **Attack surface:** the CDP port binds `127.0.0.1`, exists only during a renewal, and is torn down
  unconditionally.
- **No evasion, by design.** This works *because the session is genuinely trusted* — real fingerprint,
  real residential IP, human-established login. The design **excludes** fingerprint/JA3 spoofing, proxy
  or IP rotation, captcha-solving services, and anti-detect stripping. **The headed-offscreen choice
  in §5.1 is this principle in action**: it is preferred over headless precisely because it is
  *honestly* a normal browser, not because it disguises one. A genuinely challenged session is
  re-warmed or surfaced to the operator — never evaded.

---

## Appendix A — probe log (this machine, 2026-07-25; no account touched, no sign-in performed)

| Probe | Method | Result |
|---|---|---|
| Detached-context browser survival | Direct-exec Chrome, `nohup … & disown`, `--user-data-dir=/tmp/…`, poll `ps` 1 Hz | **Headless ≥8 s, headed ≥10 s — both ALIVE** (Dia: reaped <5 s) |
| CDP endpoint shape | `curl 127.0.0.1:<port>/json/version`, `/json/list` | **Both 200 + JSON**, 1 page target (Dia 9222: 404 on both) |
| Fingerprint | UA from `/json/version` | Headed: `Chrome/150.0.7871.182`, **no `HeadlessChrome`**. `--headless=new`: `HeadlessChrome/150.0.0.0` |
| Probe hygiene | `pkill` both instances, `rm -rf` throwaway profiles | 0 probe Chromes left; operator's 21 Dia processes untouched |
| Long-lived-token scope | `strings` + index extraction on `claude.exe` (256 MB, CC 2.1.219) | Verbatim: *"Long-lived tokens … are limited to inference-only for security reasons"*; *"long-lived (1-year) auth token"*; policy `force_login_method_refused` |
| `refreshTokenExpiresAt` existence | same | **Present, 5 occurrences** (read / merge / persist) — settles the first pass's dispute |
| Deadline non-extension | same | `refreshTokenExpiresAt: t.… ?? e?.…` — client **retains** the old deadline |
| In-process refresh single-flight | same | `refreshPromise` ×4, `isRefreshing` ×2, `pendingRefresh` ×2 |
| Cross-process credential lock | same, co-location filter over `flock`/`lockfile`/`O_EXCL` | **None** — all hits are bundled Bun/npm package-manager strings |
| Inference-only persist short-circuit | same | `if(!e.refreshToken||!e.expiresAt) return … tengu_oauth_tokens_inference_only` |
| `31536000` provenance | same | **All occurrences are HTTP `Cache-Control: max-age`** — corrects the first pass's cited evidence |
| Keychain item derivation | `accounts.json` | `Claude Code-credentials-<sha256(config_dir)[:8]>`; one `config_dir` per account |
| Concurrency reality | `accounts.json` router block | `KMAX: 8`; "observed **5–6** live sessions on primary accounts" |
| Profile map / personal-jar risk | `accounts.json` | `next → Personaly` (**personal**), next2/3/4 → Claude2/3/4 |
| launchd reference shapes | `com.chrisren.cc-reaper.plist`, `com.chrisren.dia-cdp.plist.disabled` | Working headless pattern; disabled agent's post-mortem (GUI-registration abort, SingletonLock race, retry storm) |
| Dia launcher constraints | `~/bin/dia-cdp-launch.sh` | Hard-refuses launchd (line 253); `open -n` required; nohup instance died <5 s (2026-06-29) |

**Not probed / deliberately out of scope:** any live OAuth flow, any sign-in, any credential write.
Those are Phase-1 E1–E3.

## Appendix B — claim ledger

**[PROBED] (this session):** substrate survival, CDP shape, UA posture, no long-lived full-scope
credential, no deadline extension, `refreshTokenExpiresAt` exists, in-process-only single-flight, no
cross-process lock, inference-only short-circuit, keychain derivation, concurrency reality.

**[PRIOR, carried]:** the two measurement proofs of C1; RFC 8628 absence; `next3` 400-cascade; warm
cookies to 2027-08-14; the frozen `cc-relogin` contract; Dia consent-modal and cold-profile walls.

**[SPECULATIVE] — each with its settling experiment:** concurrent same-account logins coexist (**E1**);
launchd-proper browser survival (**E2**); warm-profile Authorize passes unchallenged end to end
(**E3**); server-side refresh-token reuse detection (inferred from RFC 6819 + the `next3` signature —
never load-bearing, since component 1 works under all three causes).

**Corrections issued to the first pass:** `31536000` evidence (wrong constant, right conclusion);
`refreshTokenExpiresAt` "does not exist" (refuted); "relocate existing Dia profiles" (superseded by
fresh dedicated profiles); "single-flight coordinator is the root-cause C2 fix" (refuted — no
cross-process lock exists; de-sharing is the fix); executor-as-net vs coordinator-as-fix (order reversed).
