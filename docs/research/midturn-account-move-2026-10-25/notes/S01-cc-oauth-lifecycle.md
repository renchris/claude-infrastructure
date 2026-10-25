# S01 — Claude Code 2.1.293 OAuth credential lifecycle (mid-turn account move study)

Slot: S01-cc-oauth-lifecycle. Date: 2026-10-25. Read-only study of `/tmp/mtam/cc293-src.js`
(52,710,919 bytes, extracted plaintext of `~/.claude-293/.../claude.exe`). All offsets are byte
offsets into that file, measured with `python3 -I` `bytes.find`/`re.finditer` (helper scripts in
`/tmp/mtam/S01-cc-oauth-lifecycle/{g.py,offs.py,flags.py}`). No credential, token or keychain
secret was read or printed; no keychain call was made; no session was touched.

Note on names: the bundle is many Bun chunks concatenated, each with its own minified
namespace, so a short name (mn, Ya, Li, zn, B, we...) is defined several times. Every offset
below is the definition actually imported by the OAuth chunk (around 4.64-4.71 MB) or the API
client chunk, confirmed from the surrounding code.

## Method / commands run (key output)

1. `python3 -I g.py f 'not_needed'` / `'no_refresh_token'`: found Pl() at 4668663 and its return codes.
2. `g.py r 4646000 9000`, `g.py r 4655000 14000`, `g.py r 4669000 8500`: read $hr, Bhr, jhr, m$, bA, mn,
   wA, Nk, Jf, KS, BRs, y$, Ya, b$, j7, Pl in full.
3. `g.py f 'function zn\('` → the credential-store zn() is at 3751307 (`function rwr(){return"keychain"}function zn(){if(K)return K;return M(b,T)}`).
   `g.py r 3738000 14500`: read the whole secure-storage chunk (keychain backend `b`, plaintext backend `T`,
   fallback combinator `M`, write lock `ryo`, cache class `a`, `cPt=30000`).
4. `g.py f 'function B\(\)\{'` → B() at 1323537 `function B(){return t===!0}` (pinned flag); `g.py r 5304600 2600`
   showed it is pinned by `tengu_hover_rest` (5307027) and that `Pmr()` (5306156) always returns undefined.
5. Callers: `g.py f '[^A-Za-z0-9_$.]j7\('` and `'[^A-Za-z0-9_$.]Li\('` (≈30 OAuth-relevant hits, listed below);
   `g.py f '[^A-Za-z0-9_$.]EN\(\{'` (client constructor callers); read EN 8641200-8651200 and the retry
   generator Khe 12387075-12394000 and the main query site 12502356.
6. Account caches: read Olo/M8t 4704900-4709100, request metadata KWe 8876300, bootstrap merge q()/ot()
   18238300, credentialSlots 1601900 and 1633700, in-process login Hxr/Mxr 26289700, sibling-login watch 32401200.
7. Writers: `g.py f 'zn\(\)\.(mutate|delete|update)\('` (30+ hits) and revoke `dA` 4702543 + callers.
8. Filesystem stat only (no content):
   `ls -la ~/.claude*/{.credentials.json,.claude.json,.oauth_refresh.lock,...}` →
   `.credentials.json` is ABSENT in ~/.claude, ~/.claude-next, ~/.claude-secondary, ~/.claude-quaternary;
   PRESENT in **~/.claude-tertiary** (regular file, `-rw------- 1923 B, Oct 11 22:47`).
9. `python3 -I flags.py` (reads only `cachedGrowthBookFeatures.tengu_hover_rest` and the key NAMES of
   `oauthAccount` in each `<configDir>/.claude.json`): `tengu_hover_rest = False` in all five configs;
   every per-account config has `oauthAccount` with `profileFetchedAt` present.
10. `git grep` of bin/ and scripts/ for `CLAUDE_CODE_OAUTH_TOKEN|CLAUDE_SECURESTORAGE_CONFIG_DIR`: only comments
    (bin/cc-config-slot:40, scripts/relogin-desharing-activate.sh:13); no launcher in the repo sets them.
    (The live launchers are ~/.zshrc functions, not read.)

## (1) Storage backend on macOS, and caching

- `zn()` @3751307 = `K ?? M(b,T)`: keychain backend `b` (name "keychain", @3744007) with plaintext backend `T`
  ("plaintext", `<uw()>/.credentials.json`, @3749914) as FALLBACK. `rwr(){return"keychain"}` @3751275. `K` is a
  module `var K;` never assigned in the chunk (test hook). So on macOS interactive: **keychain via the `security`
  CLI, plaintext file only as fallback.**
- Item identity: service `FF(A_e)` @3737710 = `"Claude Code"+OAUTH_FILE_SUFFIX("")+"-credentials"+"-"+sha256(configDir NFC)[:8]`
  (hash suffix only when CLAUDE_CONFIG_DIR or CLAUDE_SECURESTORAGE_CONFIG_DIR is set); account `FT()` = $USER.
  Directory `uw()` @3737575 = `CLAUDE_SECURESTORAGE_CONFIG_DIR` else config dir `we()`.
- Reads: sync `b.read()` runs `security find-generic-password -a "$USER" -w -s "<svc>"` via execSync (@3744207);
  async `readAsync()` @3744562 spawns `security find-generic-password ... -w` (function `v`).
- **Cache**: per-host `class a { cache={data,cachedAt}; generation; readInFlight; lastReadFailure; keychainHoldsItem }`
  (just after `var cPt=30000` @3738137). Both read() and readAsync() return `cache.data` if
  `Date.now()-cachedAt < cPt` → **30 s TTL**; after a failed read they serve the stale copy for `fyo=1000` ms;
  a failing sync read "serving stale cache" re-stamps cachedAt. `p0()` @3738497 drops the cache (data=null,
  generation++); `FSs()` expires it but keeps data. Writes (`b.update`) set the cache to the written blob.
- On top of that, the OAuth layer keeps an in-memory copy: `class bA` @4655727 (`value`, `promise`,
  `lastCredentialsMtimeMs`, `lastCredentialsVersion`, `lastKeychainAccessToken`, `lastUnusableTokenRecheckAt`,
  `lastOwnSavedAccessToken`, `credentialsChangedOnDisk` emitter, pending-401/refresh maps). `mn()` @4656339 returns
  `bA.value` if set, else `m$()` @4655116 (env CLAUDE_CODE_OAUTH_TOKEN → FD token eM() → `zn().read({fromStoreCopy:!0}).claudeAiOauth`).
  `Ya()` @4664097 caches the async read promise in `bA.promise` (`b$` @4664282). The value persists until
  `e9()`/`ox()`/`Jf()` clear it.
- **"store"/v5 mode and fromStoreCopy are inert here.** `B()` @1323537 is a pinned boolean set from
  `CLAUDE_CODE_HOVER_REST ?? GrowthBook tengu_hover_rest (default false)` (zL @5307027). Measured: tengu_hover_rest=False
  in all configs. Even with B() true, `Pmr()` @5306156 is `if(!B())return;return` → backend always undefined in this
  build, so `oA(n)` @5234456 → credentials handle undefined → wA takes the mtime path and `TA()` returns "bare".
  `fromStoreCopy` only affects the plaintext leg when B() and a store copy exist (@3749986). probeCredentials()
  versioning (@4658332 branch) is unreachable for these sessions.

## (2) When Pl()/wA() run

- `Pl()` @4668663 starts with `await wA(e,b)` unconditionally, THEN checks expiry (`if(M&&!JP(M.expiresAt))return"not_needed"`).
  `JP()` @4704535 = `now+300000 >= expiresAt` (5-minute window). So the change-check runs on every Pl call even when no
  refresh is needed.
- `Pl` is only reached through `j7()` @4668113 (dedupes concurrent checks per kind in `pendingRefreshChecks`) and
  `Li()` = `j7().then(r=>r==="refreshed")`.
- **Request path**: the Anthropic client constructor `EN()` @8641537 does `let Se=await j7({credentials:M,storageV5:N}),Te=mn()`
  (@8642899) and bakes `Te.accessToken` into the client (`Xcs({...oauthAccessToken:Te?.accessToken})` @8649845,
  `new Zme({authToken})`). The retry generator `Khe` @12387075 builds a client when `b===null` (first attempt of every
  call) or after a 401/stale connection (`if(b===null||Jn||Dnn(M,h.model)||Jt||zn)` @12388136; `b=await e(),Ze=mn()?.accessToken`
  @12389390). The main query site calls `Khe(()=>EN({...}))` per model request (@12502356). ⇒ **wA() runs before every
  model API request (every step of a tool loop), not once per turn and not on a timer.**
- Other callers also hit Pl→wA: count_tokens (10134255), side_query (10684081), quota_check (9759366), cache_touch
  (9784883, client cached by builtAt), GrowthBook client `refreshOAuthTokenIfNeeded` (4497664), 1P event logging (4485177),
  policy limits (16185334), bootstrap/profile (4706118), MCP/claude.ai connectors (11810263), plugins (7858316), etc.
  No dedicated refresh timer for the claude.ai OAuth token was found (searched proactiveRefresh/refreshTimer; hits are
  policy-settings and remote-bridge only).

## (3) Live swap of the keychain item: when does the process send the new token?

`wA()` @4658275 (non-store path): `stat(<uw()>/.credentials.json).mtimeMs`; **on stat failure → `Jf(e,n)`** (@4658510);
if mtime changed → `ox()` + emit (@4658580); else `Nk()`.

Case A — no `.credentials.json` in the config dir (measured: ~/.claude-next, ~/.claude-secondary, ~/.claude-quaternary):
every Pl call runs `Jf()` @4659248: `e.clear()` (drops bA.value and promise), `Ya()` → `zn().readAsync()` → keychain
readAsync (30 s cache) → compare to `lastKeychainAccessToken`, and if different `sp()` + emit credentialsChangedOnDisk.
Then `EN` calls `mn()` → `m$()` → keychain `read()` (same cache). ⇒ **the new token is used on the first API request
(client build) made after the keychain cache entry ages past 30 s** — i.e. within ≤30 s of the swap plus the gap to
the next request. Requests already streaming keep the old bearer (nothing aborts them). Mid-tool-loop: the next model
call of the same turn picks it up. No 401 or refresh is needed.

Case B — `.credentials.json` present and unchanged (measured: **~/.claude-tertiary = next3**): mtime equal → `Nk()`
@4658672: `if(r!==null&&!Ml(r))return` — a valid cached token short-circuits, so **the swap is NOT noticed** on the
request path. The old token keeps going out until one of: (a) a 401 → `KS`→`y$` @4661639: `ox()` (clears bA and the
keychain cache), re-read, `if(h.accessToken!==e)` → "tengu_oauth_401_recovered_from_keychain" (@4663817) and the Khe
loop rebuilds the client; (b) the cached token comes within 5 min of expiry → Pl does `ox(); U=await Ya(b); if(U.accessToken!==N)`
→ "refresh_race_resolved", adopted without a refresh (@4669173); (c) the file's mtime changes (any touch) → `ox()` on the
next request, which bypasses the 30 s keychain cache; (d) incidental `e9()` callers, e.g. policy-limits load
`if(v!=="store")e9()` (@16202281, cadence not measured). The plaintext file contents are never used while the keychain
item exists (keychain leg first in `M.read`).

cPt throttle in Nk: it only rate-limits re-reads (one per 30 s) when the cached credential is null or "dead"
(`Ml`: refreshToken "" or in the in-memory dead set). It does not matter for a healthy swapped token. The same
constant `cPt=30000` IS the keychain read-cache TTL, and that is what bounds Case A latency.

Store mode (`probeCredentials` version) would adopt on the next request via `lastCredentialsVersion` change, but is
inactive (see 1).

## (4) Ways credentials get destroyed when two items share one refresh token

1. **Refresh rotation without cross-item coordination.** Refresh (`aye` @4699900) POSTs the stored RT; response
   `refresh_token:G=e` (@4700414) — a new RT if the server sends one. `$hr` @4651282 writes only THIS config dir's item.
   The refresh lock is per directory (`bDn` → `<uw()>/.oauth_refresh.lock` @4665726), so processes on two different
   config dirs holding the same RT do not serialize. If the server makes the old RT single-use (the code's race/adoption
   paths assume it does; not verified server-side here), the other item is left with a dead RT.
2. **jhr dead-token clearing** @4654023: on invalid_grant (`if(lye(ee)&&Y)await jhr(Y,b)` @4672495) it adds the RT to the
   process-lifetime dead set `Oi` and CAS-mutates the item: if the stored RT still equals the dead one, it writes
   `refreshToken:"",accessToken:"",expiresAt:0` (@4654231) — **it wipes the still-valid access token too**, so that dir's
   sessions show as logged out. CAS guard: if the item was already swapped to a different RT, it is left alone. The
   in-memory `Oi` set then makes that process refuse ("known_dead_refresh_token") any credential carrying that RT, even
   one restored later.
3. **$hr CAS sibling adoption** @4651282: inside `zn().mutate`, if the stored RT is neither "" nor the RT that was
   posted, it sets w=true and keeps the stored blob (@4651959; "tengu_oauth_refresh_save_adopted_newer_write" @4652543).
   ⇒ If an external writer swaps the item while a refresh is in flight (POST timeout 30 s), the freshly minted tokens
   for the OLD account are thrown away. If the server rotated that RT, the old account's only valid RT is now lost.
4. **Logout / console login revoke server-side**: logout reads the item and POSTs `${TOKEN_URL}/revoke` for the RT
   (`dA` @4702543; call @23520626), then deletes `claudeAiOauth` (@23521291). Console-login replacement revokes the
   old RT (@28149119). Revocation kills every item that shares that RT.
5. **Fallback-write side effects** (`M.update` @3742935): if the keychain write fails non-transiently, the blob goes to
   plaintext `.credentials.json` and the keychain item is deleted; if the keychain had no item and the write succeeds,
   the plaintext file is deleted (`if(i===null)await r.delete(o)` @3743013).
6. **Whole-blob item + lost update**: the keychain item is one JSON blob holding `claudeAiOauth` AND mcpOAuth,
   pluginSecrets, trustedDeviceToken, designOauth, coworkRemoteDevice, enterpriseGateway, mcpXaaIdp... (writers at
   4019016-38153130). CC's read-modify-write goes through `d()`/`ryo()` under `<uw()>/.storage-write` (@3741539),
   a lock an external swapper does not take → a concurrent CC mutate (e.g. an MCP token save) can write back the old
   `claudeAiOauth` and undo a swap. Copying a whole item between dirs also copies/overwrites the other secrets.

## (5) Per-account state that goes stale after a token swap

- `oauthAccount` in `<configDir>/.claude.json` (accountUuid, emailAddress, organizationUuid, billingType,
  organizationRole, seatTier, rate-limit tiers, ccOnboardingFlags...). Written by `M8t` @4707491. At startup `Olo`
  @4705896 (called @18471945) refetches the profile only if `profileFetchedAt` is older than `I$=86400000` (24 h, @4698112)
  or fields are missing (@4706265). Bootstrap merge `q()` @18238697 **ignores** a response whose account_uuid differs from
  the stored one. Refresh (`aye`) merges profile fields into the existing oauthAccount without checking the account, only
  when fields are missing. Nothing on the Jf/401 adoption path rewrites oauthAccount.
  Used by: `Mn()` @4676059 → request `metadata.user_id` `account_uuid` on every API call (`KWe` @8876661:
  `iL()?.accountUuid||Mn()?.accountUuid`), extra-usage/billing gates (WRs, billingType), org-role messaging, `iF()` org uuid.
- `credentialSlots.authenticatedAccount` (in memory, @1601937): set from bootstrap `oauth_account` (`ot` @18239195);
  cleared by `kn()=aSe(null)` @4661615 only on the 401-recovery and refresh-race paths, **not by Jf()**. It wins over
  `Mn()` in the request metadata.
- `subscriptionType` / `rateLimitTier` come from the credential blob itself (`dr()` @4677058 `e.subscriptionType??BA()`),
  so they DO follow the swap once mn() re-reads.
- GrowthBook user attributes (account/org) are cached; re-read only via `rereadUserAttributes` (@4497664 deps).
- The sibling-login watch (`_startSiblingLoginWatch` @32402429, flag tengu_streamed_thimble default true) reacts to
  credentialsChangedOnDisk only to clear a "login needed" notice; it does not re-key the session.
- The correct in-process account switch exists: `h1e`→`Hxr` @26290508 / `Mxr` — computes same_account vs account_switch,
  runs `Zoe` cache clear, `aSe(null)`, writes a fresh oauthAccount via M8t, `vun` refresh. It is reached only from
  /login flows and the SDK `claude_authenticate` control request (@26906187), all of which run a browser OAuth flow.

## Answer (summary)

(1) macOS interactive: keychain via the `security` CLI (`Claude Code-credentials-<sha8>`), plaintext `.credentials.json`
only as fallback; 30 s read cache (cPt) plus the in-memory bA.value/promise; store/v5 probeCredentials and fromStoreCopy
are inactive (tengu_hover_rest=false, Pmr() returns undefined). (2) Pl→wA runs inside every Anthropic client build, i.e.
before every model API request (and many side calls); refresh itself only happens within 5 min of expiry. (3) In a dir
WITHOUT .credentials.json (next, next2, next4) a replaced keychain item is sent on the first request after the 30 s cache
expires; no 401 needed, no disruption to the in-flight stream. In a dir WITH an unchanged .credentials.json (next3/tertiary
today) the swap is invisible until a 401, the 5-minute-to-expiry check, or an mtime change of that file. The Nk cPt throttle
matters only for null/dead cached tokens. (4) Shared RTs: rotation in one dir strands the other; invalid_grant → jhr wipes
the item (access token included) and blacklists the RT in-process; $hr discards freshly minted tokens if the item changed
mid-refresh; logout revokes server-side; whole-blob writes under a lock external writers skip can undo a swap. (5)
oauthAccount (24 h profile TTL, bootstrap refuses a mismatched uuid) and the in-memory authenticatedAccount stay on the
old account, so request metadata account_uuid goes stale; subscriptionType/rateLimitTier follow the token.

## Open questions

- Server side: is an OAuth refresh token single-use after rotation (and is there a grace window)? Determines whether
  hazards 1 and 3 really strand an account.
- Does the API bill or rate-limit by bearer only, or does a stale metadata.user_id account_uuid / org matter?
- Cadence of incidental `e9()` callers (policy limits etc.) for Case B: not measured.
- What the 1923-byte ~/.claude-tertiary/.credentials.json holds (not read on purpose); if the tertiary keychain item
  ever disappears, CC falls back to it (possibly stale RT from Oct 11).
