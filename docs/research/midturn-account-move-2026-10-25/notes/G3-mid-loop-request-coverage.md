# G3: which request paths run the credential change-check, and what happens to a request already in flight

Slot: G3-mid-loop-request-coverage. Date: 2026-10-25. This was a read-only study of `/tmp/mtam/cc293-src.js` (Claude Code 2.1.293,
extracted Bun bundle). I ran no claude process, read no keychain item, printed no token, and touched no pane. Helper scripts are
in `/tmp/mtam/G3/` (`g.py` greps with byte offsets and prints context, `encl.py` finds the enclosing function, `chunk.py` resolves
whether a name is local to its chunk or imported). Every offset below is a byte offset into cc293-src.js. Every command was wrapped in
`timeout 60`.

## 0. Method caveat: the source is about 2,290 concatenated ESM chunks

`re.finditer(rb'// Version: 2\.1\.293')` found 2290 chunk headers. Minified names repeat across chunks. For example, `EN` @4363453 is an
unrelated model-picker helper, and `Pl` inside the auto-mode chunk is a different import. So I checked which chunk exports each name used on
the auth path:
- `export{…EN…}` appears only at 8990592. That is the chunk 8047779-8995499 that holds the client factory `EN({apiKey,…})` @8641537.
- `mn`, `j7` and `KS` are exported only at 4710337. That is the auth chunk 3983836-4716360, holding `mn` @4656339, `j7` @4668113,
  `Pl` @4668663, `wA` @4658281 and `Jf` @4659248.
- The query chunk (9694469-14392306) imports `EN` and `mn` (chunk.py output: `EN … imported_from=['/$bunfs/root/chunk-zwe9vtev.js']`,
  `mn … imported_from=['…chunk-gcyvvtkw.js']`). The EN chunk imports `j7` and `mn` from chunk-gcyvvtkw. The policy-limits chunk header @16167331
  imports `j7` and `mn` from chunk-gcyvvtkw too. I treat chunk-gcyvvtkw.js as the auth chunk at 3983836 because it is the only chunk that
  exports these names.

## 1. Building blocks: what EN and Khe do

- **EN() @8641537 is the factory for every Messages API client.** It runs `let Se=await j7({credentials:M,storageV5:N}),Te=mn()` (inside
  @8641537..8643000). On the first-party path it ends with `Ne=Xcs({isSubscriber:Me,apiKey:Ye,oauthAccessToken:Te?.accessToken})` …
  `new Zme({apiKey:Ne.apiKey,authToken:Ne.authToken,…})` (around @8650400). The OAuth access token is therefore **copied into the client
  object when the client is built**.
- **j7 → Pl → wA.** `j7` @4668113 calls `Pl(b,…)` and shares the result with concurrent checks through `pendingRefreshChecks`. `Pl` @4668663
  starts with `await wA(e,b)` unconditionally. S01 has the details. Without `.credentials.json` (on macOS the credential lives in the
  keychain), wA → `Jf` @4659248 clears the bA cache and re-reads the store through the 30 s keychain cache. If the token differs, it sets
  `lastKeychainAccessToken`, `sp()` and `Xf()` (emit credentialsChangedOnDisk).
- **mn() @4656339 is one cache per host:** `let e=Hye.of(F().host);if(e.value!==void 0)return e.value;let n=m$();return e.value=n,n`.
  Every in-process caller shares this one slot: main thread, subagents, classifier and side endpoints. **Any** caller that runs wA updates it for
  everyone after it.
- **Khe @12387081, the retry generator around a single request.** It builds the client only
  `if(b===null||Jn||Dnn(M,h.model)||Jt||zn)`, i.e. on the first attempt, after a 401 or other auth error (`Dnn` @12385357), after a
  stale connection, or when a remote session rotated its credential (`Jn` needs `CLAUDE_CODE_REMOTE_SESSION_ID` and `jur` @12385192). It
  then records `b=await e(),Ze=rl()?mn()?.accessToken:void 0`. **Retries for 429, 529 or 5xx inside one Khe call reuse the client `b`, and with it
  the old bearer.**

## 2. Coverage, path by path

| # | Path | How the client or token is obtained | Change-check (j7→Pl→wA) before each send? | Evidence |
|---|---|---|---|---|
| 1 | Main model loop | query loop `L0` @18136472 → `q=Pi(Qks(Kd(e.deps??Sl(),…)))` @18139345; `Sl()` @18123372 = `{callModel:sSt,…}`; per step `Cd=q.callModel;for await(… Cd({…}))` @18163096 → `sSt` @12419093 → `Son` @12433083 → `Khe(()=>EN({…}))` @12502370 | **Yes, on every model request (every tool-loop step)** | S01 confirmed this; I re-traced it |
| 2 | In-process subagents (Agent tool, background agents, forks, teammates) | runner passes `runQuery:n.options.runQuery` @17500150 and calls `ze.options.runQuery({messages,…,toolUseContext:ze,querySource:M,…})` @17507136. runQuery is `L0` (main session sets `runQuery:L0` @33415715; headless @26616944). No caller passes `deps` (checked every `deps:` hit 9.69M-45M; none is a query deps override), so `Sl()`→`sSt`→`Son`→`Khe(EN)` | **Yes, the same code as the main loop** | @17500150, @17507136, @18139345 |
| 3 | Auto-mode classifier | `querySource:"auto_mode"` @10805856 / @10807857 → `nIt` @10814710 → `ANe` @10813314 → `nG({...n,credentials:r,…})` (sideQuery @10683632). nG: `it=()=>EN({…source:"side_query"…}),vt=await it()`, which builds a new client on every nG call. Its 401 path calls `KS(Rt,Ye)` and then `Or(await it())` to rebuild. `agent_classifier` @34050883 and `auto_mode_critique` @28535772 also call nG | **Yes, a new EN per classifier call** | @10683626-10688000 |
| 4a | Background or auxiliary model calls inside the process (compact, hooks, away summary, web search, artifact replies…) | `pee` @12418787 and `sSt` both → `Son` → `Khe(EN)`. Examples: compact @12247700, stop-hook @12560283, web search @17815390, artifacts @17136249… Side queries use `nG`. quota_check `mnt` @9759366, count_tokens @10134255/@10135135, model_config @12308301, `/v1/me` warm @18314980 and models.list @19381167 all call `EN` per call | **Yes** | listed offsets |
| 4b | **cache_touch keepalive (the exception)** | `YLn` @9784883: `if(s===void 0||g-s.builtAt>=jLn){s={value:await EN({…source:"cache_touch"…}),builtAt:g}… e.client=s}` with `jLn=240000` @9777402. **The client is cached for up to 240 s**, and the cache is dropped only when a touch throws (`catch(h){throw e.client=void 0,h}`) | **No.** The check runs only when the cached client is rebuilt, so a POST can carry the old bearer for up to 4 min after a swap | @9784883, @9777402 |
| 4c | Out-of-process background sessions / bg jobs | Separate OS processes, each with its own `Hye` cache. Each runs the same EN path per request against **its own** config dir's store | Yes, per process, against that process's config dir | inferred from the per-host cache (`Hye.of(F().host)`). I did not trace the bg daemon |
| 5a | firstPartyApi (`zt` @4429987 → `gr`) side endpoints | `gr` @~4424500: for `auth:"claude-ai-oauth"` it runs `await iS(s);let ee=mn()…Authorization:Bearer ${Q}`. Default auth runs `await iS(s)` then `ece()` @4096729, which also reads `mn()` at send time. `iS` @4428676: `if(!e.refreshOAuth)return; await Li({credentials,storageV5})`, and Li is j7 | **Only when the caller passes `refreshOAuth:true`.** Otherwise the call reads the shared mn() cache with no check of its own. The bearer is always read **at send time** and never cached per client | @4428676, @4096729 |
| 5b | `/api/oauth/usage` (`zF` @~8976200) | `zt.get(r,{…refreshOAuth:!0,credentials:e…})` | **Yes** (refreshOAuth:true) | @8976900 |
| 5c | policy_limits | `R=await j7({credentials:n});let N=await O()` (O → `cF()` → `ece()` → `mn()`) @16185509. On the startup load it also calls `e9()` + `lqe()→wA` @16202316 | **Yes** | @16185509, @16202316 |
| 5d | `/api/oauth/profile` (`qVe` @4582533) | Takes an explicit token. Bootstrap callers pass `mn()?.accessToken` directly (@4705840, @4706558, @42411700). The login path passes the new token (@26291033) | **No separate check.** It uses whatever the mn() cache holds | listed |
| 5e | Remote-control bridge (`bIr` @~27700000) | `getAccessToken:Le` with `Le`=`getBridgeAccessToken`=`Kv` @9565659: `return mn()?.accessToken`, read on every request. 401 → `onAuth401` (handleOAuth401Error = KS→y$ re-read/adopt). Some session-ingress helpers capture a token once (`getAccessToken:()=>a` @25255377, `()=>Ht` @27752756) | **No check of its own.** It reads mn() per request, so it follows the shared cache. Captured-token helpers keep the old token for their lifetime | @9565659, @27791029 |
| 5f | GrowthBook | `refreshOAuthToken()` → `deps.refreshOAuthTokenIfNeeded` (S01: Pl at 4497664), then `getAuthHeaders()` on each refresh @4144787 | Yes, at each feature refresh | @4132315, @4144787 |

**Net result:** every **inference** path (main loop, subagents, auto-mode classifier, side queries, compaction, hooks, quota/count_tokens)
builds a new client through EN for each request, and so runs j7→Pl→wA first. The only inference-adjacent request that holds a cached client is
the **cache_touch keepalive (≤240 s)**. It is a POST to the keepalive endpoint `FLn`, not a model generation, so it is a billing/attribution
leak only in the sense of an old-account keepalive. Side endpoints read `mn()` at send time. Some (usage, policy_limits, GrowthBook) run the
check first. Others (profile, bridge, firstPartyApi calls without `refreshOAuth`) just read the shared cache. That cache is refreshed by the
next check from any path, which in an active session means the next model request.

## 3. A request already in flight when the store changes

- **The bearer is captured once per client and sent once per HTTP request.** In SDK class `Zme`, `authHeaders(n)` @8223264 uses
  `tokenCache` only when no `authToken` was supplied. Otherwise `bearerAuth(n){…Authorization:Bearer ${this.authToken}}` @8223710, and
  `this.authToken=s` is set only in the constructor @8219958. Headers are assembled per request in `buildHeaders` (`await this.authHeaders(n)`
  @8231807). CC always passes a static `authToken` string (EN, §1).
- **No auth logic runs per chunk.** The fetch wrapper `i7` @8658399 only *logs* a redacted Authorization (`a7()` @~8660400) and wraps the
  body for chunk timing (`s7(...)`, `_chunkTimes`). It never reads `mn()`, `accessToken`, `j7` or `Li` (python scan of i7's 6 KB body: the
  only hit is the log helper).
- **Therefore a streaming `/v1/messages` that has already sent its headers finishes on the old account's bearer.** Nothing aborts it on a
  credential change: `Xf()` emits credentialsChangedOnDisk, whose only subscriber is the sibling-login watcher @32402506, and that watcher
  acts only while the login notice is shown (`recheckAfterCredentialsChange` @32221018: `if(!this.showsLoginNotice())return!1`).
- **What happens next.** The next model request in the same turn (the next tool-loop step) builds a new client and carries the new bearer,
  provided wA noticed the change: ≤30 s keychain-cache lag (Case A), and never noticed through mtime for config dirs that have a
  `.credentials.json` (Case B, next3; see S01). If the in-flight stream fails and CC falls back to non-streaming (`xet` @12497614 →
  `Efr` @12420763 → `Khe(()=>EN(...))` @12420834), that re-send uses a **new** client and so the new account. Retries *inside* one Khe call
  (429/529/5xx/backoff) reuse the old client and bearer, unless the error is a 401 or auth-class error (`Dnn`) or a stale connection.
- **Billing attribution (inference).** The server can attribute a request only to the bearer on its HTTP request. One turn that spans a swap is
  therefore billed old-account up to and including the in-flight request, and new-account from the next client build on. The
  client source cannot verify server-side metering. This is a client-side inference.

## 4. In-process account state a silent bearer swap does NOT move (found on the way)

The full in-process account-switch routine is `vun` @23522838. It runs `e9()`, clears provider caches, model configs and
validated models, calls `bR(d,"account_change")` (GrowthBook), `Qls` (artifact roster / accountEpoch++), and finally
`l_n()`→`Iu.resetCurrentLimits()` (@9768410, increments the rate-limit `accountEpoch`, resets limits to `allowed`). It is called only from logout
(`Zoe` @23520439/@23521824) and login completion (`Mxr` @26292168). **A keychain swap detected by wA/Jf does not call vun.** Jf calls only
`sp()` = `y6()` (betas), `XCe()` (emit), `Ok()` (drop in-flight composes) @4657361.

As a result, after a silent swap:
- Rate-limit state `Iu` (current limits, overage, usage-limit waits) still describes the old account until new response headers overwrite it.
  cache_touch checks `accountEpoch` (`tq()` @~9784600, "account_changed"), but that epoch does not change on a silent swap.
- `metadata.user_id.account_uuid` comes from `KWe` @8876304: `iL()?.accountUuid||Mn()?.accountUuid`. `iL`=`credentialSlots.authenticatedAccount()`
  @1634249 is cleared by `kn()` (aSe(null)) only in Pl's refresh-race branch and y$, and is re-stamped by `ot()` @~18239236 from a server
  response. `Mn()` @4676059 = `ce().oauthAccount` (the config dir's .claude.json). After a silent swap through the Jf path, requests can
  therefore carry the new bearer with the **old** account_uuid in metadata until something re-stamps it. I did not trace when `ot()` runs.
  Confidence moderate.

## 5. Commands run (all `timeout 60`, from /tmp/mtam/G3)

- `python3 -I g.py f '[^A-Za-z0-9_$.]EN\(' 100` gave the EN definition and its callers (8641537, 9759366, 9784883, 10134255, 10135135, 10684081,
  12308301, 12416421, 12420834, 12502370, 18314980, 19381167, plus unrelated same-named functions at 4363453 and 30170644/30170861).
- `g.py c 8641537 0 6000` / `g.py c 8647537 0 5000` printed the EN body (j7, mn and `new Zme({authToken})`).
- `g.py c 12387075 0 7000` printed Khe. `g.py f 'function jur\('` etc. found jur @12385192, Dnn @12385357 and Gur @12385571.
- `encl.py`, then a scan of async generators found the main sender `Son` @12433077, `pee`/`sSt` @12418795/@12419225 and xet/Efr.
- `g.py f 'callModel'` found `Sl()={callModel:sSt}` @18123372 and the query loop's use @18163096 / @18139345.
- I scanned for `L0` imports and uses (`runQuery:L0` @26616944, @26919235, @30442922, @33415715) and `g.py f '\.runQuery\b'` (subagent runner
  @17500150, @17507136; hook agents @12214662, @12573205; other @13872862).
- I scanned for `deps:` 9.69M-45M: no query deps override.
- `g.py f 'querySource:"auto_mode[a-z_]*"'` → @10805856/@10807857/@24702167/@28535772. I printed nIt @10814710 and ANe @10813314.
  `g.py c 10683626 0 3500` + `g.py c 10687126 0 2500` printed nG.
- `g.py c 9784883 900 1600` and `g.py f 'jLn='` showed cache_touch and jLn=240000 @9777402.
- I located `accountEpoch` writes (9167942, 9768410), callers of `resetCurrentLimits` / `l_n` (23523442, 28336080) and the `vun` callers.
- I printed `Jf`, `sp`, `Xf`, `Dco`, `lqe`, the sibling-login watch @32402506 and `recheckAfterCredentialsChange` @32221018.
- I printed `KWe` @8876304, `iL`/`Mn` @4676059/@4676110, `BEo`/`aSe` @1634249 and the `aSe` callers.
- I grepped for usage/profile/policy/bridge endpoint strings, then printed `gr`/`iS` @4428676, `zt` @4429987, `ece`/`cF` @4096243/@4096729,
  zF @8976200, policy @16185329-16185509 and @16202316, `qVe` callers, the `bIr` header code and `Kv` @9565659.
- I printed the SDK auth code (`authHeaders` @8223264, `bearerAuth` @8223710, the constructor @8219958, `buildHeaders` @8231807) and scanned
  i7's body for auth reads (hits: `uthorization` at +2279, the log-only `a7`).

No keychain reads, no processes started, no repo files touched besides this note.

## 6. Answer (short)

1. Main loop: yes. One `Khe(()=>EN())` per model request, so j7→Pl→wA runs before every tool-loop step.
2. In-process subagents: yes. They go through the same `runQuery=L0` → `Sl().callModel=sSt` → `Son` → `Khe(EN)` path and pass no deps override.
3. Auto-mode classifier (and agent_classifier, auto_mode_critique): yes. `nIt`→`ANe`→`nG` calls `EN` on every call.
4. Background model calls in the process (compact, hooks, side queries, quota_check, count_tokens): yes, EN per call. **Exception:
   the cache_touch keepalive caches its client for ≤240 s (`jLn=240000`).** Out-of-process bg sessions each run their own check against
   their own config dir.
5. Side endpoints: the bearer is read from the shared `mn()` cache **at send time**, never cached per client. usage, policy_limits and
   GrowthBook run j7 first. profile, bridge and firstPartyApi calls without `refreshOAuth` do not, and follow the shared cache, which the next
   model request refreshes. Some bridge or session-ingress helpers capture a token string once.
6. In flight: per-request capture. A streaming request finishes on the bearer it was sent with; there is no per-chunk re-read and no abort
   on change. Retries inside one Khe call keep the old client unless the error is 401/auth-class. The next client build, including the
   non-streaming fallback, uses the new token.
7. A silent swap does not run the account-switch routine `vun`. Rate-limit state and the stamped account_uuid in request metadata can stay
   on the old account.
