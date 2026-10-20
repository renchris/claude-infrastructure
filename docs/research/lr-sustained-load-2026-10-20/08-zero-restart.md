# 08 — Zero-restart recovery: can a capped session continue on another account without /exit + relaunch?

Date: 2026-10-20 (UTC). Axis 08 of the lr-sustained-load study. Read-only investigation: no credential
was read, written or copied, no pane was typed into, no process was signalled. All binary reads are
of the installed bundle, using two helper scripts I wrote (`/tmp/zr08/ctx.py`: regex plus byte
context; `/tmp/zr08/at.py`: bytes at an offset).

Tags: **MEASURED** = a command I ran, with its output. **READ** = vendor doc, changelog, repo file or
the installed binary's JS. **HYPOTHESIS** = not verified; it needs the prototype test in §7.

Binary under study: `~/.claude/bin/cc-claude-bin --explain` => `/Users/chrisren/.claude-293/node_modules/.bin/claude  zshrc claude() _bin pin`,
`--version` => `2.1.293 (Claude Code)` (MEASURED). Upstream changelog head is 2.1.304
(`curl -sL .../anthropics/claude-code/main/CHANGELOG.md` => 9276 lines, MEASURED). Changelog lines
cited below as "CL vX" were mapped to versions with `head -n L | grep '^## ' | tail -1`.

---

## 0. Verdict

1. **Mechanically, yes.** A running 2.1.293 session re-reads its config dir's keychain item without
   a restart. Three paths do it: the OAuth refresh check (`Pl` → `wA`), the 401 handler (`y$`) and the
   storage cache (30 s TTL). If another process rewrites that item, the session sends its next
   requests with the new token. The binary has code for this case: the events
   `tengu_oauth_401_recovered_from_keychain` and `tengu_oauth_token_refresh_race_resolved`, and a
   "sibling login" watcher (§2). A third-party MIT tool, **claude-swap**, ships this exact mechanism
   and documents macOS pickup "once that cache expires (about 30 seconds)" (§4).
2. **The granularity is the config dir, not the session.** One keychain item exists per config dir,
   or per `CLAUDE_SECURESTORAGE_CONFIG_DIR` (§2.2; that variable is undocumented). For a **cap**,
   that is the wanted unit. When next3 hits weekly 100%, **every** next3 session must move. One item
   rewrite moves all 9 together, with no pane I/O, no boot, no admission and no transplant.
3. **The blocker is not the client. It is the refresh token.** Refresh tokens rotate (repo-measured,
   §5). The refresh lock is per credential dir (`.oauth_refresh.lock` under `uw()`, §2.3). If two dirs
   hold copies of one account's grant, their refreshers do not serialize. The loser gets
   `invalid_grant`, which (repo-documented, 2.1.220 binary) **erases the stored credential**. Only an
   interactive `/login` then recovers it. So a naive "copy next4's blob into next3's item" works for
   up to about 8 h. It then strands a whole account. This is the failure the repo spent August
   fixing.
4. **Three shapes avoid the refresh race. Each has an unmet precondition:**
   - **(B) independent grant bank.** Each dir holds its *own* grant for every account. This needs
     the repo's still-**UNRUN** experiment E1 ("do two full-scope logins of one account coexist?",
     `docs/research/RELOGIN_E1_E3_VERDICT_TEMPLATE.md:59`).
   - **(C) refresh-less tokens** (setup-token) in the item. This shape is undocumented, and the
     tokens are inference-only: Remote Control and claude.ai connectors are lost. The fleet uses
     Remote Control: transcripts carry `bridge-session` lines.
   - **(D) single-writer copy-back** (claude-swap's approach). A supervisor holds the dir's
     credential lock while writing and copies rotated tokens back. It narrows the race but cannot
     close it across two locks.
5. **A flip alone does not restart a capped turn.** A 429 usage-limit refusal does not trigger a
   credential re-read. With "Continue automatically at usage limit" on, the turn enters a wait
   timed to the *old* account's reset (§2.6). A nudge is still needed. The repo already owns a
   **kitty-free** nudge transport: Claude Code's own messaging socket (`bin/cc-wake`). Today its
   W3b gate refuses limited sessions until reset; a flip mode would need its own gate.
6. **Recommendation:** do not build a flip yet. First run the operator-only prototype in §7 (one
   throwaway account dir and one idle session). It settles pickup latency under load 150+, capped-turn
   behaviour after flip + socket nudge, and E1. Every number that would justify the build is
   currently a hypothesis. The upside is large (§6: about 30–60 s per *account*, against 1 h 43 m for
   5 of 9 sessions). The downside of building it on unverified premises is a stranded account,
   which needs interactive `/login`.

---

## 1. What restart costs today, and what zero-restart removes

From the incident brief (2026-10-20, next3 weekly cap at about 02:31Z, 9 sessions, load 150–375 on
10 cores):

| blocker observed | in the relaunch path? | in a credential flip + socket nudge? |
|---|---|---|
| reconciler CPU brake / capacity probe timeout (admit.py) | yes: a relaunch is a new process boot | **no**: no new process, so nothing to admit |
| placer `rc=124 timeout=120s` → WAIT_DATA ~30 min | yes: picks a target per session | partly: one account-level target choice, made once |
| idle-move lane `HELD:load … 20/core recycle bound` | yes | **no**: nothing is recycled |
| kitty RC socket silent → `HELD:pane:resolver-unavailable`, composer unreadable, post-transplant rollback | yes: `/exit` is typed into the pane | **no**: the CC messaging socket is not kitty (`bin/cc-wake:14-20`) |
| transcript transplant / clone (`lr-transplant.sh`) | yes | **no**: transcript stays in place; the conversation is not bound to the account (§2.8) |
| post-transplant rollback leaving PRE-MOVE/None | yes | no transplant, so no rollback of one |

Live state at writing time: `sysctl -n vm.loadavg` => `{ 201.41 179.90 178.44 }`. Live sessions per
dir, counted by existence of a pid listed in `<dir>/sessions/*.json` (`kill -0`, which delivers no
signal): `~/.claude 13, ~/.claude-secondary 16, ~/.claude-tertiary 4, ~/.claude-quaternary 2`
(MEASURED). `~/.claude-next/sessions` is a symlink to `~/.claude/sessions` (`ls -ld`, MEASURED), so
the 13 are next's.

---

## 2. How Claude Code 2.1.293 reads credentials (installed binary + docs)

### 2.1 Precedence (READ, code.claude.com/docs/en/iam "Authentication precedence")
1 cloud provider → 2 `ANTHROPIC_AUTH_TOKEN` → 3 `ANTHROPIC_API_KEY` → 4 `apiKeyHelper` → 5
`CLAUDE_CODE_OAUTH_TOKEN` → 6 Anthropic profile/federation → 7 subscription OAuth from `/login`
(keychain). The fleet runs on rung 7: `grep -n -i 'apiKeyHelper\|OAUTH' ~/.claude*/settings.json` =>
no hit, and prior research `limit-cascade-2026-09-10.md:41` says "no live claude process carries
CLAUDE_CODE_OAUTH_TOKEN".

### 2.2 Where the credential lives: one keychain item per *secure-storage dir*
READ (bundle at offset ~186154000, the chunk exporting `uw, FF, PK, p0`):
```
function uw(){let e=process.env.CLAUDE_SECURESTORAGE_CONFIG_DIR;if(e!==void 0)return(e||u(o(),".claude")).normalize("NFC");return we()}
function FF(e=""){let n=process.env.CLAUDE_SECURESTORAGE_CONFIG_DIR,t=n!==void 0?!n:!process.env.CLAUDE_CONFIG_DIR,
  r=n!==void 0?n.normalize("NFC"):we(),c=t?"":`-${i("sha256").update(r).digest("hex").substring(0,8)}`;
  return`Claude Code${cn().OAUTH_FILE_SUFFIX}${e}${c}`}
```
- The service name is `Claude Code-credentials-<sha256(dir)[:8]>`, or unsuffixed when no
  `CLAUDE_CONFIG_DIR` is set. This matches the iam doc: "keys the macOS Keychain entry to that
  directory". `security dump-keychain | grep -c 'Claude Code-credentials'` => `70` (MEASURED, a count
  of attribute lines only; no secret was read).
- **`CLAUDE_SECURESTORAGE_CONFIG_DIR` is an undocumented variable** that decouples the credential
  item and its lock dir from `CLAUDE_CONFIG_DIR`, which holds transcripts and settings. It is set at
  launch, so it cannot re-point a live process. It is the enabler for a "credential lane" design
  (§3, option B/C).
- Two dirs also hold a `.credentials.json`: `stat` => `~/.claude-tertiary/.credentials.json size=1923
  mtime=Oct 11 22:47:52 2026` and `~/.claude-next/.credentials.json size=565 mtime=Aug 11` (MEASURED,
  metadata only). The doc says this is the fallback when a keychain write is rejected. CL v2.1.286
  "Fixed macOS sessions still showing 'Not logged in' … when a leftover `.credentials.json` exists".
  A flip design must say which store wins in these two dirs (open question).

### 2.3 The read path and its caches (READ, offsets 186161510 and 187075205)
- **Storage-layer cache: 30 s.** `var cPt=30000` and, in the keychain backend,
  `read(){… if(Date.now()-r.cachedAt<cPt)return r.data; … KTe(\`security find-generic-password -a "${n}" -w -s "${s}"\`,{timeout:f})`
  with `f=2000`. **Under load, a `security` spawn that exceeds 2 s** takes the
  `"[keychain] read failed; serving stale cache"` branch. That branch *re-stamps* the stale data as
  fresh for another 30 s (`e.cache={data:r.data,cachedAt:Date.now()}`). At load 15–37 per core,
  pickup latency could therefore stretch in 30 s steps (HYPOTHESIS; the async `readAsync` path calls
  `v(e)`, whose timeout I did not extract).
- **Change detection `wA(e,n)`.** On the storage-v5 path it compares `probeCredentials().version`. On
  the legacy path it `stat`s `<uw()>/.credentials.json` mtime. A changed version or mtime runs `ox()`
  (clear the token memos) and `Xf(e)` (emit `credentialsChangedOnDisk`). With no file, `catch{return
  Jf(e,n)}`: clear, re-read through `Ya` and the 30 s cache, and if `accessToken !== lastKeychainAccessToken`,
  run `sp()` and emit. So **with the keychain as the store, each `wA` call costs one cache-bounded
  keychain read and adopts a changed token.**
- **The refresh check runs `wA` first.** `async function Pl(e,n,r,s,g,h,b,w,k=!1,T=!1){await wA(e,b);let M=await Ya(b);…`.
  `Pl` is reached from `Li()` (`checkAndRefreshOAuthTokenIfNeeded`), which is called before
  first-party API calls in many places (12 call sites sampled with `ctx.py 'await Li\('`). I did
  **not** prove that the main `/v1/messages` path calls `Li` before every request (HYPOTHESIS; the
  prototype measures it directly).
- **Refresh race resolution.** Inside `Pl`, after `ox()` and re-read:
  `if(U.accessToken!==N)return kn(),i("tengu_oauth_token_refresh_race_resolved",{}),"refreshed"`.
  If the stored token is no longer the one this process holds, the process adopts the stored one.
  The refresh lock is `bDn(e)` → `rp(e,".oauth_refresh.lock")`, with `e = uw()`, stale 60 s. **It is
  per secure-storage dir.** Two dirs never serialize their refreshes against each other.

### 2.4 The 401 path re-reads the keychain (READ, offset ~187079000)
`async function y$(e,n,r,s=!1,g){ox();let h=await Ya(n); … if(h.accessToken!==e)return kn(),i("tengu_oauth_401_recovered_from_keychain",{}) … }`.
On a 401 the process clears its caches and re-reads. If the stored token differs, it takes it.
Otherwise it forces a refresh. (Changelog trail: CL v2.1.117 "token is now refreshed reactively on
401"; CL v2.1.178 "auth errors after credentials were refreshed outside the session"; CL v2.1.281
"logging in from another Claude Code process"; CL v2.1.282 refresh-lock holder killed mid-refresh.)

### 2.5 The sibling-login watcher (READ, offset ~214820899)
`_startSiblingLoginWatch` subscribes to `credentialsChangedOnDisk` (`Dco(this.session.host,()=>{… this._adoptSiblingLogin()})`).
It also polls `lqe` on a 1 s / 3 s / 10 s ladder (`var Ukt=[1000,3000,1e4]`) **only while the session
shows a login notice**. `_adoptSiblingLogin` refreshes managed settings and connectors. It does
**not** run the account-change reset `vun()`. That reset (it clears caches, increments the
rate-limit `accountEpoch` via `l_n()`, and fires `account_switch`) is called only from the
logout/login path `Zoe` (offset ~205938303). Consequence (HYPOTHESIS): after an external flip, the
session's rate-limit tracker and limit banner keep describing the *old* account until a fresh
response overwrites them.

### 2.6 A usage-limit 429 does not re-read credentials
`extractQuotaStatusFromError` (offset ~192190603) records `status:"rejected"` from the 429 headers.
The query loop registers a wait: `bnt({route,…,rateLimitType,retryAtMs:zo.retryAtMs,attempt,maxRetries})`
(offset ~194878126). No credential re-read sits on this path. With "Continue automatically at usage
limit" (CL v2.1.234, default on), the turn waits for the old account's reset. For a weekly cap, that
is days. CL v2.1.284: "typing a message during an automatic usage-limit wait …" shows that a new
user message during the wait starts a new attempt. HYPOTHESIS: a socket-queued message (cc-wake's
frame) does the same, and the new attempt then carries the flipped token.

### 2.7 Credentials that cannot be swapped under a live process
- `CLAUDE_CODE_OAUTH_TOKEN`: a process env var. On 401 the binary deliberately keeps it:
  `"OAuth 401: keeping the user-supplied CLAUDE_CODE_OAUTH_TOKEN instead of adopting the stored credential …"`
  (`Pfs()`, offset ~187079000). The docs say: "uses the token you set for the whole session"
  (prior slot `q3a-product-permits.md:16`). The only rotation hooks are `CLAUDE_CODE_OAUTH_401_WAIT_MS`
  / `BRs` ("waiting up to …ms for a rotated env token"). They poll `process.env` and default on only
  for remote sessions (`h$(){… return Il()?cp:0}`), and no outside process can write another
  process's env.
- `CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR`: read once and cached (`eM(){… getCached:Ez,setCached:J2 …}`,
  offset ~186262520).
- SDK `getOAuthToken` callback (`oSe()`, "sdk_host_refresh"): only for Agent-SDK hosts, not
  interactive TUI sessions.

### 2.8 Is the account bound into the session?
- **Conversation: no.** The top-level keys over the newest `~/.claude-secondary` transcript
  (`python3 -I` key census, MEASURED) include no account field on message lines.
- **Remote Control bridge: yes.** `bridge-session` lines carry `ownerAccountUuid` and
  `ownerOrganizationUuid` (MEASURED: `bridge-session ['bridgeSessionId','lastSequenceNum','ownerAccountUuid','ownerOrganizationUuid','sessionId','type']`).
  The binary has `tengu_bg_rv_auth_mismatch` and "deferred auth-mismatch re-key" (offset ~72382976).
  A flip would put an RC-attached session's bridge under a mismatched account. HYPOTHESIS: the bridge
  re-keys or drops; it does not lose the conversation.
- **Per-dir profile:** `<dir>/.claude.json` `oauthAccount` (accountUuid, …) exists in all 5 dirs
  (key census only, MEASURED). After a flip it names the wrong account until a profile refetch.
- **Prompt cache: account-scoped.** The first request after a flip re-ingests the whole context,
  billed to the new account (claude-swap README: "may use extra usage as its conversation cache
  rebuilds"; the repo's q3a 1.3 says the same). A relaunch pays this too, so it is not an added cost.

### 2.9 apiKeyHelper (READ, settings-reference §apiKeyHelper, fetched to /tmp/zr08/settings-ref.md:5620-5640)
"sends its output as both the `X-Api-Key` and `Authorization: Bearer` headers … caches the value and
reruns the command … After the cache lifetime, five minutes by default or … `CLAUDE_CODE_API_KEY_HELPER_TTL_MS`
… When a request … fails with `401` or `403` … Before sending … when the cached output is a JWT that
expired". There is **no rerun on 429**. It is an API-key-class credential: CL v2.1.139 (changelog line
5643) "Remote Control, `/schedule`, claude.ai MCP connectors … are now disabled when …
`apiKeyHelper` … is set". The prior repo verdict stands (`autonomous-relogin-methods-2026-07-25.md:233`
"Inapplicable", `union-alpha-drain…/A9-throughput.md:178` "money trap"). Feeding a subscription
OAuth token (`sk-ant-oat01-…`) through it is unsupported. A public feature request reports the
Messages API rejecting OAuth tokens with "OAuth authentication is currently not supported"
(claudeissues.com/issue/37205). **Rejected** as a zero-restart path. It is also the one per-request
hook in the product, which is why it looks tempting.

---

## 3. Design space

| # | Shape | Granularity | Refresh-token safety | Precondition | Capability cost | Verdict |
|---|---|---|---|---|---|---|
| A | Copy the target account's full-scope blob into the capped dir's keychain item | whole dir (all N sessions) | **unsafe**: one grant in two items, two locks; rotation → `invalid_grant` → erase (§5) | none | none | **Reject as-is.** Works until the next 8 h refresh boundary, then strands an account |
| B | **Independent grant bank**: for every (credential dir × account) pair, a separately minted full-scope grant held dormant; a flip writes the dir's *own* grant for the target account | whole dir | **safe by construction**: no grant is ever in two items | **E1 = COEXIST** (UNRUN); a dormant-grant keeper (heal) for 12 extra grants; operator logins: 12 one-time | none | **Best if E1 passes.** Blocked on E1 |
| C | Refresh-less credential (setup-token, 1 year, `refreshToken:null`) written into the item | whole dir | safe: nothing to rotate | undocumented item shape (a malformed write is a logout: `autonomous-relogin-100pct-design-2026-07-25.md:152`) | **inference-only**: no Remote Control or connectors in flipped sessions | Fallback if E1 fails; costs RC, which the fleet uses (§2.8) |
| D | claude-swap style: hold the dir's `.oauth_refresh.lock` while writing; copy rotated tokens back | whole dir | **narrowed, not closed**: the two dirs' refreshers still race at expiry | none | none | Reject for 24/7 unattended use: an 8 h race on every boundary |
| E | Credential lanes: launch every session with `CLAUDE_SECURESTORAGE_CONFIG_DIR=~/.cc-lanes/<lane>` (transcripts stay in their `CLAUDE_CONFIG_DIR`); flip a lane | per lane (choose lane size: 1 session up to a whole account) | same as the grant source used (B or C) | launcher change (operator `~/.zshrc`); undocumented variable | as B or C | Enabler for finer granularity *later*; not needed for the whole-account cap case |
| F | `/login` inside the pane | whole dir | product-supported | pane I/O and a browser | none | Fails the brief: needs the kitty I/O that failed in the incident |
| G | apiKeyHelper with a per-session token | per process | n/a | OAuth via helper unsupported (§2.9) | RC and connectors disabled | Reject |

**Why the cap case wants whole-dir (A/B/C).** The incident is "account next3 is at 100%". Every next3
session is a mover, so per-session targeting adds nothing. The placer's 120 s timeouts and per-session
WAIT_DATA disappear into one choice: which account has the most headroom for N sessions.

**Target choice under sustained load.** The flip moves load between *accounts*, not CPU. Under the
operator's premise, CPU load is irrelevant to the flip. The only gate is quota headroom on the
target, read from the existing usage sweep. A flip **must not** sit behind the reconciler's CPU brake.
That brake guards process boots, and a flip boots nothing.

---

## 4. Prior art outside this repo

- **claude-swap** (github.com/realiti4/claude-swap, MIT; pypi `claude-swap` 0.20–0.23). Quoted from
  the README via WebFetch: on macOS "Claude Code caches Keychain credentials for about 30 seconds,
  so a running session switches once that cache expires"; "Switches … hold Claude Code's own
  credential locks while writing, so a swap never interleaves with a token refresh"; "A session
  refreshes its own copy of the token. After it exits, the rotated credential is copied back";
  "Do not run `/logout` first: current Claude Code may revoke the refresh token". Auto mode: poll
  60 s, switch at 90% 5 h or 7 d, cooldown 5 min. It confirms §2.3 independently. It also shows the
  author met the refresh-copy problem (D) and handled it with copy-back, not by eliminating it.
- **anthropics/claude-code #64376** (no way to switch to a secondary account in-session; asks for an
  automatic fallback account) and **#34341** (one active token per keychain; asks for named profiles
  and opt-in automatic failover on rate limit). Both are open feature requests, so there is **no
  vendor contract** for a mid-session account change other than `/login`.

---

## 5. Repo history that bounds the design (READ)

- **Refresh tokens rotate:** `docs/research/forced-relogin-rootcause-2026-08-02.md:47-49`, "REFRESH
  TOKENS ROTATE. `next` rt `0023ef9690b1 → a9f8aadf29eb` … across a single grant. … what makes a
  *shared* credential across N concurrent sessions genuinely hazardous".
- **invalid_grant erases the item:** same file, `:89-95`: "on a single `invalid_grant` response to a
  refresh grant, the CLI erases the stored credential … only an interactive `/login` recovers it".
  The 8 h access-token TTL is in the same passage. (Measured on 2.1.220. The 2.1.293 bundle now has a
  `known_dead_refresh_token` set (`Oi.has(M.refreshToken)`) and an `account_on_hold` path in `Pl`.
  Whether it still erases is HYPOTHESIS: unchanged.)
- **E1 is UNRUN:** `RELOGIN_E1_E3_VERDICT_TEMPLATE.md:59` "`UNRUN`". Same file `:67-69` records that
  COEXIST would mean "The token race is eliminated by construction". There is also a stated fear that
  minting a new same-account grant might evict a live one server-side
  (`forced-relogin-rootcause-2026-08-02.md:399-401`). That fear is unmeasured.
- **setup-token is inference-only:** `forced-relogin-rootcause-2026-08-02.md:404-415`;
  the iam doc says "It can only make model requests, so it can't establish Remote Control sessions
  or fetch claude.ai connectors".
- **The heal machinery assumes one account per item:** `bin/claude-accounts` keys everything by
  config dir (`keychain_service(config_dir)` at `:518`; "persists whatever (possibly rotated) tokens
  come back to the same keychain item" at `:29`), and `lr_recon` maps account ↔ `config_dir` from
  `~/.claude/accounts.json` (`lr_recon/__main__.py:151`). A flipped dir would make heal refresh the
  *target* account's grant from the *capped* account's item. That is the rotation race of option A,
  triggered by our own tool.
- **Prior ruling:** `limit-recover-zero-memory-2026-10-06/slots/synthesis-draft.md:73` lists "build
  rotation on a credential swap or scripted `/login`" under "Not to do (85, q3a)", on the q3a grounds
  that it is undocumented and pickup is untested. This axis adds the binary evidence that pickup
  exists (§2.3–2.5), the third-party confirmation (§4) and the precise reason it is unsafe (§2.3 lock
  scope + §5 rotation). The ruling's caution holds for A/D. B and C were not considered there.
- **Nudge transport exists:** `bin/cc-wake:14-20` delivers through CC's messaging socket
  (`/tmp/cc-socks/<pid>.sock`, `{"type":"user",…,"priority":"next"}`, queued as an isMeta prompt, not
  the composer). `:33-42` W3b refuses `limited` sessions until reset + grace. A flip needs a new,
  separately gated mode ("account flipped under you").

---

## 6. Expected effect (ESTIMATED, not measured)

Per capped account, if B or C is in place and §7 confirms the hypotheses:
- write 1 keychain item (one `security add-generic-password -U`, about 0.1 s idle; under load,
  seconds), plus
- pickup ≤ 30 s storage cache (§2.3), possibly in multiples of 30 s if `security` spawns time out
  under load, plus
- one socket nudge per session that sits in a limit wait (cc-wake transport, no kitty).

Estimate: **about 30–120 s for all N sessions of the account together**, flat in N and independent
of the CPU brake, the placer and kitty. The incident took 1 h 43 m to recover 5 of 9 (brief). The
remaining cost is the full-context re-ingest on the first request per session (§2.8), which relaunch
pays too.

---

## 7. Prototype test (operator-run only; it writes credentials, so no agent may run it)

Use a **throwaway** dir (for example `~/.claude-flipprobe`), never one of the 5 live dirs, and an
account the operator can afford to re-`/login` if it is stranded.

- **T1 Pickup latency (idle).** `CLAUDE_CONFIG_DIR=~/.claude-flipprobe claude`, `/login` as account
  X, send one prompt, then leave it idle. From outside, overwrite that dir's item with **an
  independent grant for account Y** minted in another throwaway dir (this is the E1 setup itself).
  Send a prompt through the messaging socket every 10 s. Measure the time until `/status` (operator
  view) or the response headers' account switch from X to Y. Repeat at idle load and at load ≥ 150.
  Pass: ≤ 60 s at ≥ 150 load.
- **T2 Capped turn.** Same, but with X at a real usage limit (or wait for a natural cap). Confirm the
  turn is in the auto-continue wait. Flip to Y, deliver one socket frame, and check that the next
  request succeeds on Y with no `/exit`. Also record whether the limit banner stays stale (§2.5).
- **T3 E1 coexistence (the gate for B).** Two dirs, two independent `/login`s of the same account Z.
  Force a refresh in each, in either order (an expiresAt-past state, or 8 h natural). Pass: both
  dirs keep working for 48 h and the first grant is never evicted when the second is minted.
- **T4 Shared-grant race (expected failure; proves A/D unsafe).** Copy dir-1's Z grant into dir-2's
  item and wait across one access-token expiry with a live session in each. Expected: one dir gets
  `invalid_grant`, and the item is erased or marked dead. Run it only with a sacrificial account.
- **T5 Setup-token-in-item shape (the gate for C).** Write `{claudeAiOauth:{accessToken:<setup-token>,refreshToken:null,expiresAt:null,scopes:["user:inference"]}}`
  into a throwaway item. Check that a live session adopts it, keeps working past 8 h and never
  rewrites or erases it. Record which features drop (RC and connectors are expected to drop).
- **Instrumentation:** the binary's own events (`tengu_oauth_401_recovered_from_keychain`,
  `tengu_oauth_token_refresh_race_resolved`, `tengu_oauth_refresh_token_marked_dead_invalid_grant`)
  are telemetry-side. Locally, record the keychain item's access-token *hash* (never the value)
  before and after, as the repo's rotation instrument did (`forced-relogin-rootcause:253`).

If T1, T2 and T3 pass, the build is: a "flip" verb in the reconciler (target = most-headroom account,
no CPU gate); a dir→billing-account indirection table consumed by `claude-accounts`, `lr_recon` and
cc-wake; heal disabled for or redirected away from flipped items; a cc-wake flip mode; and a
flip-back at the capped account's reset. If only T5 passes, the same build applies, minus RC in
flipped sessions.

---

## 8. Failure modes to design against

1. **Rotation race / erase** (A, D): §5. It is fatal to unattended operation, so it is the reason A
   and D are rejected.
2. **Split usage accounting.** After a flip, dir `~/.claude-tertiary` bills next4. `claude-accounts
   --rank/--place`, the usage sweep (`/api/oauth/usage` read per item), the reconciler's
   `account ↔ config_dir` map, cc-wake W3b and the `.claude.json oauthAccount` would all misattribute.
   It needs one SSOT table "dir → account now", written atomically with the item.
3. **Our own heal rotating the target's grant** (§5). It must be fenced before any flip.
4. **Keychain read timeouts under load** (§2.3: a 2 s `security` timeout serves stale data for
   another 30 s). Pickup may lag. Worse, a refresh decision may be made on a stale read; the
   refresh path's `readAsyncStrict` under lock mitigates this.
5. **Flip-back.** When next3 resets, its sessions are on next4. Flipping back is a second flip. Under
   B it is safe. Under C it is trivial. Never "restore" by copying blobs between items.
6. **Mixed dirs.** A dir that carries both a keychain item and a leftover `.credentials.json`
   (tertiary, next today) has two stores, and `wA` keys change detection on the file's mtime when the
   file exists. Clean this up before any flip on that dir (operator action).
7. **Remote Control bridge owner mismatch** (§2.8). An RC-attached session may lose its bridge after
   a flip.
8. **Stale limit UI / rate-limit tracker** (§2.5). It may suppress auto-continue or show wrong
   banners. Harmless to correctness if the nudge path does not read it. cc-wake's W3b reads the
   *transcript's* death record, so it must learn about flips.
9. **Policy posture.** The same as today's relaunch-based moves between the operator's own accounts.
   A flip changes the mechanism, not the practice. (Stated for completeness; not a technical
   blocker.)

---

## 9. Evidence index (commands run)

- `~/.claude/bin/cc-claude-bin --explain`; `<bin> --version` => 2.1.293.
- `LC_ALL=C grep -a -o -E 'CLAUDE_CODE_API_KEY_HELPER[A-Z_]*|CLAUDE_CODE_OAUTH[A-Z_]*|apiKeyHelper[A-Za-z]*|ANTHROPIC_CUSTOM_HEADERS|oauth-2025-04-20' <bin> | sort | uniq -c`
  => `CLAUDE_CODE_OAUTH_TOKEN 127`, `CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR 27`, `apiKeyHelper 113`,
  `CLAUDE_CODE_API_KEY_HELPER_TTL_MS 7`, … (44.9 s wall).
- The env-var registry at offset 184215743 lists, among others, `CLAUDE_CODE_OAUTH_401_WAIT_MS`,
  `CLAUDE_CODE_AUTH_FAIL_EXIT_MS`, `CLAUDE_CODE_SDK_HAS_OAUTH_REFRESH`, `CLAUDE_CODE_HOST_CREDS_FILE`
  and `CLAUDE_CODE_SESSION_ACCESS_TOKEN` (all undocumented; none gives an outside writer a way in for
  an interactive session).
- `python3 -I /tmp/zr08/ctx.py <bin> 'function lqe\('` → offset 187076133 (`wA`/`Jf`/`KS`/`y$`);
  `/tmp/zr08/at.py <bin> 187079000 9000` → the `y$` and `Pl` bodies; `ctx.py 'cachedAt<cPt|…'` →
  keychain backend at 186160973; `at.py 186151000 4500` → `uw`/`FF`/`cPt=30000`;
  `ctx.py '[^a-zA-Z0-9_$.]Dco\('` → the sibling-login watch at 214820899;
  `ctx.py 'beginUsageLimitWait\('` → 192190603; `ctx.py '[^a-zA-Z0-9_$.]vun\('` → login-only callers;
  `ctx.py 'function eM\(\)'` → the FD token is cached.
- `curl -sL https://code.claude.com/docs/en/settings-reference.md` → `/tmp/zr08/settings-ref.md`, apiKeyHelper at `:5620-5640`.
- Changelog `/tmp/zr08/changelog.md`: v2.1.117 (401 reactive refresh), v2.1.178 (outside-refresh stale
  config), v2.1.234 (auto-continue at usage limit), v2.1.281/2.1.286 (login from another process
  picked up), v2.1.282 (refresh lock holder killed), v2.1.284 (typing during the limit wait),
  v2.1.301 (`CLAUDE_CODE_RETRY_WATCHDOG_MAX_USAGE_LIMIT_WAIT_MS`; newer than installed).
- Live: `sysctl -n vm.loadavg` => 201.41; the session counts in §1; `stat` of the two
  `.credentials.json` files (metadata only); `~/.claude/accounts.json` name→config_dir (next →
  ~/.claude-next, next2 → ~/.claude-secondary, next3 → ~/.claude-tertiary, next4 → ~/.claude-quaternary).

Web sources: https://code.claude.com/docs/en/iam ; https://code.claude.com/docs/en/settings-reference ;
https://github.com/realiti4/claude-swap ; https://github.com/anthropics/claude-code/issues/64376 ;
https://github.com/anthropics/claude-code/issues/34341 ;
https://claudeissues.com/issue/37205-feature-allow-oauth-tokens-for-anthropic-messages-api-enable-subscription-based ;
https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md

---

## Skeptic review

Adversarial re-check, 2026-10-20 UTC. Read-only: no credential value was read or written, no pane
was typed into, no process was signalled. Binary =
`/Users/chrisren/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (236330608 B, 2.1.293),
scanned with my own `/tmp/skep08/multi.py` (regex + context) and the author's `/tmp/zr08/at.py`. Every
number below is tagged MEASURED (command named) or ESTIMATED (method named).

### Three findings the original doc did not have

**S1. Two of the four accounts cannot be flipped by a keychain write alone today, and next3 (the
incident account) is one of them.** `wA` (offset 187076133) checks for a change in one of two
ways. It reads `probeCredentials().version` (the storage-v5 path), or it `stat`s
`<uw()>/.credentials.json` (the legacy path). The v5 probe (offset 187650889) also `lstat`s
`<uw()>/.credentials.json`, with version `dev:ino:size:mtimeNs`. If the file exists and is
unchanged, `wA` calls `Nk`:
`if(r!==null&&!Ml(r))return` re-reads the store only when the in-memory token is "unusable"
(`Ml`: `refreshToken===""` or known-dead, offset 187071669). If the file is absent, `wA` reaches `Jf`
through the `catch` / `state!=="present"` branch and re-reads the keychain (the case §2.3 described). The storage
selector is keychain-first: `zn(){…return M(b,T)}` with `b={name:"keychain",…}`, under the name
`keychain-with-plaintext-fallback` (offsets 186168203, 186875563). So in a dir that holds a leftover
`.credentials.json`, a keychain-only flip is invisible to the per-request check. It is picked up only
at the next refresh boundary (`Pl`: `ox()` then re-read, then `U.accessToken!==N` → adopt; ≤ 8 h) or on a 401.
- `stat` (MEASURED) → `~/.claude-next/.credentials.json size=565 mtime=Aug 11 03:32:56 2026` and
  `~/.claude-tertiary/.credentials.json size=1923 mtime=Oct 11 22:47:52 2026`. There is no file in
  `~/.claude`, `~/.claude-secondary` or `~/.claude-quaternary`.
- Live config dirs. For every pid whose executable ends in `claude`/`claude.exe`, I ran
  `ps -p <pid> -E -ww -o command= | grep -o ' CLAUDE_CONFIG_DIR=[^ ]*'` (MEASURED, 40 processes). Result:
  `13 ~/.claude-next, 21 ~/.claude-secondary, 4 ~/.claude-tertiary, 2 ~/.claude-quaternary`.
  0 processes set `CLAUDE_SECURESTORAGE_CONFIG_DIR`. **17 of 40 live sessions sit in "mixed" dirs.**
- Workaround (HYPOTHESIS, from the code above): change the file's mtime in the same step as the item
  write (`wA` → `ox()` + `Xf`), or have the operator remove the file first. The doc's failure mode
  §8.6 points at this, but the code shows it is a **blocker** for next and next3, not an open
  question.

**S2. The per-request trigger is real, which answers the doc's open question 1.** The client
builder runs `let Se=await j7({credentials:M,storageV5:N}),Te=mn()` just before
`"[API:request] Creating client"` builds the SDK client (offset 191060393). The chain is
`j7` → `Pl(b,…)` (offset 187085043) and `Pl` → `await wA(e,b)` first (offset 187085593), so every
client construction runs the change check. The token memo is `mn()` = `Hye.value`, cleared by
`e9()` / `Jf`'s `e.clear()` (offset 187073269). For keychain-only dirs (secondary, quaternary), a
flip is therefore adopted on the **first request after** the ≤ 30 s storage cache lapses. That is a
request, not a timer. An idle session never adopts a flip until something sends a request.

**S3. In the incident the capped turns *ended*; they did not wait.** I parsed the next3 transcripts
of the reconciler's incident records (`recon/sessions/*.json`, `source_acct=next3`, detected ≥ 02:31Z).
In 5 of 5 that had a cap record, the `isApiErrorMessage` `error:"rate_limit"` record is followed by
`system/turn_duration` (MEASURED: python3 -I, record types only). Example: db755a94, 02:31:39Z,
`"You've hit your weekly limit · resets 7am (America/Chicago)"`, then `system/informational`
`"Goal paused · usage limit reached · send a message after it resets to continue"`, then
`turn_duration`. The same holds for 7aae55e1, d7eb73d2, e80b61f4, 769b7294 and 3d1d988a. The sessions are
idle, so the nudge only needs to *start a new turn*. Nothing has to "break an auto-continue wait".
The setting is `autoContinueAtUsageLimit` with default `??!0`, behind gate `Ve` (offset 206144503). It
is absent from all 5 `.claude.json` and from `~/.claude/settings.json` (MEASURED, key read only).

### Verdicts on key findings

| # | Claim (short) | Verdict | Evidence |
|---|---|---|---|
| F1 | A live session re-reads its keychain item without restart (refresh check / 401 / 30 s cache) | **WEAKENED** | The code is confirmed and stronger than claimed: `j7`→`Pl`→`wA` on every client build (S2). It is false for dirs holding a leftover `.credentials.json`: `wA` keys on file mtime/version and `Nk` re-reads only for an unusable token (S1). That is next (13 live) and **next3, the incident account** (4 live). claude-swap README re-fetched: "a running session picks up the switch once that cache expires" (it never mentions `.credentials.json`). |
| F2 | One keychain item per secure-storage dir; one rewrite moves all of a dir's sessions | **CONFIRMED** | `uw`/`FF` at offsets 186154470/186154605 verbatim. `printf %s <dir> \| shasum -a 256 \| cut -c1-8` against `security dump-keychain \| grep '"svce"'` (MEASURED, metadata only): next-2be71cf3 1 item, secondary-0503d474 1, tertiary-6a49a3e4 1, **quaternary-136fa815 2**. The quaternary pair is `acct="unknown"` (cdat 2026-09-11) plus `acct="chrisren"` (mdat 2026-10-20T04:23Z), and CC reads `-a "$USER"` (`FT()`), so a flip writer must pass `-a chrisren`. "All 9 at once" is still subject to S1 for tertiary. |
| F3 | Copying one grant into a second dir's item is unsafe unattended | **CONFIRMED** | The lock is `bDn(e,n){return{lockfilePath:rp(e,".oauth_refresh.lock"),…stale:60000,update:5000…}}` (offset 187082656), so it is per dir. 2.1.293 still erases on `invalid_grant`: `jhr()` → `refreshToken:"",accessToken:"",expiresAt:0` and `tengu_oauth_refresh_token_cleared_on_disk` (offset 187071016). That answers open question 4. Nuance: the erase is compare-and-clear (`if(!h\|\|h.refreshToken!==e)return g`), so it skips an item that has already changed. forced-relogin-rootcause:47-49 and :89-95 re-read and verbatim. |
| F4 | A 429 does not re-read credentials; the auto-continue turn waits for the old reset; a nudge is needed; cc-wake's socket is kitty-free | **WEAKENED** | Conclusion holds (a nudge is needed, and the transport is kitty-free: `bin/cc-wake:14-20`, python `AF_UNIX` with `settimeout(5)` at :291-294). The mechanism is wrong for the incident: the turns *ended* (S3), so there is no wait to break. cc-wake is not process-free: it runs `ps -o lstart= -p` (:138), measured p50 0.008 s / max 0.033 s over 15 runs at load1 184-195. |
| F5 | Conversation is not account-bound; Remote Control is (`ownerAccountUuid`) | **CONFIRMED** | Re-measured key set `['bridgeSessionId','lastSequenceNum','ownerAccountUuid','ownerOrganizationUuid','sessionId','type']`. Incident sessions 7aae55e1 and d7eb73d2 wrote `bridge-session` lines right after their cap record, so RC-attached sessions are in the incident set. Nuance: tertiary transcripts already carry 4 distinct `ownerAccountUuid` prefixes (`grep -o` count: d0955289 32441, ac8c0b73 1689, d5f84d93 475, 76570e6e 339) because transplants already mix owners. What is new under a flip is only the *live* bridge. |
| F6 | An external change skips the `vun`/`l_n`/`accountEpoch++` reset | **CONFIRMED** | `vun(` callers (MEASURED, multi.py): the logout path (offsets 205938303, 205939688), which exports `Zoe,vun`, and the login path `Mxr` (offset 208710300, `artifactAccount:"same_account"`). Hits 1-2 are an unrelated zod `vun` in another chunk. The tracker has `accountEpoch=0` and `isFromPreviousAccount(e)`. The impact stays HYPOTHESIS. |
| F7 | Env token / FD token / apiKeyHelper give no zero-restart path | **CONFIRMED** | `Pfs()` / `BRs` / `h$()` verbatim at offset ~187077000. settings-ref:5620-5640 re-read: the rerun triggers are the TTL, 401/403 and an expired JWT, with no 429. CL line 5643 verbatim. `CLAUDE_CODE_HOST_CREDS_FILE` also checked: it requires `CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST` and gateway lineage (offsets 184514580, 187655665), so it is not applicable. |
| F8 | Under load the 2 s `security` timeout may fire, delaying pickup in 30 s steps | **WEAKENED** | The mechanism is confirmed on both paths: async `v(e)` also uses `timeout:f` (=2000), and `readAsync` re-stamps stale data on failure (offsets 186161513, ~186163000), which closes the doc's gap. The risk is smaller than implied: 20× `security find-generic-password -s skeptic08-nonexistent-probe` at load1 212-218 (21/core) gave p50 0.037 s, max 0.339 s, **0 over 2 s** (MEASURED, python3 subprocess timing). Caveat: spawned from python, not from a busy Bun process; 37/core not measured. |

### Verdicts on levers (would it work at a permanent 15-40/core, and is it safe?)

| Lever | Verdict | Evidence |
|---|---|---|
| L1 Operator prototype T1-T5 | **WEAKENED** | It is the right next step, and it is safe because it runs on a throwaway dir by the operator. Three defects as written: (a) T2 tests "a turn in the auto-continue wait", but incident turns end (S3), so T2 should test an *idle-after-cap* session plus a flip plus one socket frame. (b) T1 must include a **mixed dir** (`.credentials.json` present), or it will pass on a shape that 17/40 live sessions do not have (S1). (c) T3's 48 h window is underpowered. The repo's base rate on multi-grant `next` was "~8 incidents in 30 days ≈ one per 3.75 days" (forced-relogin-rootcause:282), so P(no incident in 48 h) ≈ e^(−2/3.75) ≈ 0.59 (ESTIMATED, Poisson). A pass needs ≥ 2 weeks and several refresh boundaries. |
| L2 Design B (independent grant bank + socket nudge) | **WEAKENED** | Load-independence is plausible: no boot; `security` p50 0.037 s at 21/core; `ps -p` p50 0.008 s; cc-wake log shows 27 `sent`, **0 `rc:4` transport failures** (MEASURED, `grep -c '"rc":4'` → 0). Four things are against it. (1) The repo's own production evidence leans *against* E1=COEXIST: "`next` is the only account with multiple grants … next4 — one store — has had zero forced re-logins in 30 days" (forced-relogin-rootcause:287-300; "collapse `next` to ONE grant", :381-384). Design B gives *every* account 4 grants, which replicates the strongest correlate fleet-wide. The doc cites this file but omits this passage. (2) Pickup fails in next and next3 without the S1 workaround. (3) Latency is gated by the nudge reaching every idle session (S2/S3), not by the 30 s cache, so the 30-120 s figure holds only if every capped session is nudgeable. (4) The flip must capture the *current* (possibly rotated) source grant from the item under that dir's `.oauth_refresh.lock`, or the flip-back writes a rotated-away refresh token → `invalid_grant` → erase. Also, a whole-dir flip moves N sessions onto one target at once (cascade risk, ESTIMATED). |
| L3 Design C (setup-token written into the item) | **WEAKENED** | The read path tolerates the shape in code (`Ml`: `refreshToken:null` → not unusable; `Pl` → `"no_refresh_token"`, no refresh; `JP(null)` → false). The doc omits a repo-measured cost: a setup-token gets **HTTP 403 at `/api/oauth/usage`** where a keychain token gets 200 (docs/research/setup-token-scope-refutation-2026-09-08.md:100). `bin/claude-accounts` bearers the keychain item, so the quota spine is blind for every flipped dir unless usage is re-keyed to the account's home dir. Org/profile resolution and Claude in Chrome are also off (:85-87). RC is lost, and RC-attached sessions are in the incident set (F5). |
| L4 dir→billing-account table + heal fence | **WEAKENED** | Needed for accounting: `keychain_service(config_dir)` (`bin/claude-accounts:518-521`) and `lr_recon/__main__.py:146-156` (name→config_dir) both re-read. The heal-race rationale is mostly moot: heal "runs ONLY when the account has zero live sessions (no rotation race with a running CC) and under a per-account lock" (`bin/claude-accounts:30-31`), and under B no grant sits in two items. Effort is underestimated: `grep -rl config_dir bin scripts hooks` → 68 files and `grep -rl accounts.json` → 51 (MEASURED), so effort is closer to L than M. |
| L5 cc-wake "flipped" mode | **CONFIRMED** | The transport works and is kitty-free (27 `sent`, 0 transport failures in `~/.claude/logs/cc-wake.jsonl`, 2026-10-03 → now). Because capped sessions are idle (S3), one frame starts a new turn, whose client build runs `j7`→`wA` (S2). Amendment: a flip mode must bypass **W3** as well as W3b. The incident's own wake was refused at W3: `2026-10-20T04:14:54Z … 7aae55e1 … "refused-busy","reason":"presence beat names a different pid (beat=limited)"` (log line, MEASURED). It is safe only behind S1 (a mixed dir would wake the session on the *old*, capped token and simply re-hit the limit). |

### Net

Zero-restart remains the only lever on this axis whose cost does not scale with CPU load. My
measurements at 18-22/core found no spawn-latency obstacle. Before any build the doc must absorb:
S1 (the incident account cannot be flipped by an item write alone), S3 (nudge an idle session; do not
break a wait), the forced-relogin multi-grant correlate against design B, and the `/api/oauth/usage`
403 against design C. All verdicts above are read-only; the T1-T5 tests remain operator-only.
