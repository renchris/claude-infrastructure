# S14: credential store and "storage v5" mode in CC 2.1.293 (macOS)

Slot: S14-credential-store-v5. Date: 2026-10-25. Source: `/tmp/mtam/cc293-src.js` (52,710,919 bytes, CC 2.1.293 plaintext bundle).
All offsets are **byte offsets** into that file, measured with `python3 -I` + `re.finditer` over `open(...,'rb').read()`.
No token or credential value was printed, copied or written. Keychain checks used `security find-generic-password -a $USER -s <svc>` **without** `-w`/`-g`, with output filtered to the `svce`/`cdat`/`mdat` attribute lines only.

## Method

- Helper scripts in `/tmp/s14/` (g.py, v.py, v2.py, v3.py): byte-offset regex search, then printing `d[s-N:s+M]` windows.
- Searched for: `plaintext_fallback_used`, `cPt=`, `fyo=`, `A_e=`, `function FF(`, `function PK(`, `deviceKeyStore`, `storageV5`, `fromStoreCopy`, `[secureStorage]`, `-credentials`, `probeCredentials`, `function Cst(`, `function ySr(`, `function zn(`, `function wA(`, `function Jf(`, `function Nk(`, `function Pl(`, `function j7(`, `function mn(`, `.credentials.json`, `pinStorageV5`, `credentialsStoreFor`, `tryCreateV5Backend`, `CLAUDE_SECURESTORAGE_CONFIG_DIR`, `zn().mutate(`.
- Minified names repeat across chunks. The ones that matter are in these chunks: secure-storage naming chunk `chunk-ayvdek13` (~3,737,500), secure-storage backend chunk `chunk-07wdw7m0` (~3,738,500 to 3,750,500), auth module (~4,650,000 to 4,710,337, export list at 4,710,337), v5 credentials-store chunk `chunk-xny9qenm` (~5,229,893 to 5,234,700), the B() pin chunk `chunk-a48152q4` (1,323,537) and the hover-rest pin chunks (~5,305,431 to 5,307,143).

## 1. Keychain service naming (offset 3,737,556 to 3,738,141)

```
var A_e="-credentials";
function uw(){let e=process.env.CLAUDE_SECURESTORAGE_CONFIG_DIR;if(e!==void 0)return(e||u(o(),".claude")).normalize("NFC");return we()}
function FF(e=""){let n=process.env.CLAUDE_SECURESTORAGE_CONFIG_DIR,t=n!==void 0?!n:!process.env.CLAUDE_CONFIG_DIR,r=n!==void 0?n.normalize("NFC"):we(),c=t?"":`-${i("sha256").update(r).digest("hex").substring(0,8)}`;return`Claude Code${cn().OAUTH_FILE_SUFFIX}${e}${c}`}
function FT(){... e=process.env.USER||l().username ... }   // keychain account (-a)
var cPt=30000;  ... var fyo=1000;
```

- `we()` (1,666,918 area): `var we=bo(()=>(o()??u(R(),".claude")).normalize("NFC"),o)`, where `o()` is `process.env.CLAUDE_CONFIG_DIR`. No realpath and no trailing-slash normalisation is applied. The hash covers the env string exactly as given, after NFC normalisation.
- `OAUTH_FILE_SUFFIX:""` in the production config (1,672,974).
- **Service name** = `"Claude Code-credentials"`, plus `-<sha256(dir)[:8]>` when `CLAUDE_CONFIG_DIR` (or a non-empty `CLAUDE_SECURESTORAGE_CONFIG_DIR`) is set. **Keychain account** = `$USER`.
- **`CLAUDE_SECURESTORAGE_CONFIG_DIR`** overrides both the keychain item name and `uw()`, the directory that holds `.credentials.json`, `.oauth_refresh.lock`, `.storage-write.lock` and the `mcp-refresh-*.lock` files. It does not change `we()`, so transcripts, projects/ and `.claude.json` stay under `CLAUDE_CONFIG_DIR`. If it is set to the empty string, the code uses `~/.claude` with no suffix. The variable is first-class: it is in the propagated env allowlists at 2,534,127, 5,255,079 and 9,569,145, and teammate spawning explicitly forwards it, even when empty, at 16,379,035 and 36,021,704.
- **Measured on this machine** (`printf '%s' "$p" | shasum -a 256 | cut -c1-8` plus attribute-only `security find-generic-password`): every predicted item exists.
  - `~/.claude`: `7b461744`, mdat 2026-09-24.
  - `~/.claude-next`: `2be71cf3`, mdat 2026-10-25 04:33Z.
  - `~/.claude-secondary`: `0503d474`, mdat 2026-10-25 04:01Z.
  - `~/.claude-tertiary`: `6a49a3e4`, mdat 2026-10-25 06:39Z.
  - `~/.claude-quaternary`: `136fa815`, mdat 2026-10-25 06:53Z.
  - There is also an unsuffixed `Claude Code-credentials` item, mdat 2026-10-10.

## 2. Backends and `zn()` (offset ~3,738,500 to 3,750,500, chunk-07wdw7m0)

- **`b` = keychain backend**, `name:"keychain"`, `osGuarded:!0`.
  - `read()` is synchronous: it uses `KTe("security find-generic-password -a … -w -s …",{timeout:2000})`.
  - `readAsync()` is async: it goes through `v(e)`, which calls `tt("security",["find-generic-password",…])`.
  - `readAsyncStrict`, `update` and `delete` are the other operations. `update` writes `security -i` stdin `add-generic-password -U -a … -s … -X <hex>`, falling back to argv when the payload is over 4,032 bytes.
- **Cache: `PK()` returns a per-host object** `class a{cache={data:null,cachedAt:0};generation=0;readInFlight=null;lastReadFailure=null;keychainHoldsItem=!1;…}`. The host key is `PK(){return d.of(F().host)}`.
  - Both `read()` and `readAsync()` start with `if(Date.now()-r.cachedAt<cPt)return r.data;`, so **each process caches keychain reads for 30 s (`cPt=30000`, offset 3,738,141)**.
  - After a failed read, the backend backs off for `fyo=1000` ms (3,738,365) and serves stale data.
  - `p0()` sets `cache={data:null,cachedAt:0}` and increments `generation`, so the next read goes to the keychain again.
- **`T` = plaintext backend**, `name:"plaintext"`. It reads `uw()/.credentials.json` (the `u()` helper, ~3,747,428) and writes it with mode 0600 (384).
  - `read(e)`: `let a=B()&&e?.fromStoreCopy===!0?h().copy:void 0; if(a!==void 0&&a.storagePath===r){…return JSON.parse(a.text)} let s=se().readFileSync(r)…`
  - `h().copy` is filled only by the v5 store wrapper `ce(e)`, through `H()`/`w()`. `R(e){return B()&&e!==void 0?ce(e):oe}`.
- **`M(primary,fallback)`** returns `{name:"keychain-with-plaintext-fallback", read, readAsync, readAsyncStrict, invalidateCache, mutate, update, delete}` (offset 3,743,527 area).
  - The read order is **keychain first**: `let o=await e.readAsync();if(o!==null&&o!==void 0)return o;return a(await r.readAsync(n))||{}`. The plaintext file is consulted only when the keychain returns null.
  - `update` writes the keychain. On success, `if(i===null)await r.delete(o)`: if the keychain had no item before, **the plaintext file is deleted**, which migrates the store to the keychain.
  - On a non-transient keychain failure, `update` writes the plaintext file instead. That is the `plaintext_fallback_used` event at 3,743,527. A transient or locked keychain gets `primary_transient_skip_fallback` / `keychain_locked_skip_fallback`.
- **`zn(){if(K)return K;return M(b,T)}`** (3,751,307; `rwr(){return"keychain"}`). On this darwin build, every credential read and write goes through keychain-with-plaintext-fallback.
- **`[secureStorage]` write lock**: `ryo(e)` at ~3,741,600 is a process-local promise chain plus `Ra(Q(uw(),".storage-write"),{realpath:!1,retries:{retries:10,minTimeout:100,maxTimeout:1000},stale:15000,…})`.
  - `Ra` is proper-lockfile. Its default `lockfilePath` is `${file}.lock` (3,731,740), so the lock on disk is the directory `uw()/.storage-write.lock`.
  - `mutate(fn)` = lock, then `invalidateCache()`, then a fresh strict read, then `fn(blob)`, then a write of the **whole JSON blob**.
- **The blob is shared by many features.** `zn().mutate(` appears at 54 call sites (measured, v2.py). They write `claudeAiOauth`, `mcpOAuth` (144 hits for `mcpOAuth`), `gatewayTrust`, `enterpriseGateway`, and other keys, all into the same keychain item.
- **deviceKeyStore** (24,446,751 onwards) is a separate keychain item with the constant service name `"Claude Code-device-keys"` (not per config dir). It has its own `.device-keys` lock. It is unrelated to OAuth inference credentials.

## 3. "store"/`B()` mode and storageV5: inert in this build

- `B()` at 1,323,537 (chunk-a48152q4) is `var t;function B(){return t===!0}function KEs(n){…if(t===void 0)return t=e,"pinned";…}`. The value is pinned once per process.
- The pin is set from the GrowthBook flag `tengu_hover_rest` or the env var `CLAUDE_CODE_HOVER_REST` (5,305,431 to 5,307,143): `zL(e){if(xmr(a.CLAUDE_CODE_HOVER_REST??C("tengu_hover_rest",!1)),e===void 0)return B()?Pmr():void 0;return Sao(e)}`. It is exported as `pinStorageV5` (16,434,693).
- **`Pmr` is exported as `tryCreateV5Backend` (21,342,243), and its body is `function Pmr(){if(!B())return;return}`.** It returns `undefined` unconditionally. `_ao`/`Sao` (pinStorageV5FromEnv/adoptStorageV5EnvPin) also return `B()?Pmr():undefined`, which is likewise undefined.
- `credentialsStoreFor` = `oA(e,r=y){return B()&&e!==void 0?W(r):void 0}` (5,234,456), so with `storageV5===undefined` the `credentials` value is also undefined.
- The v5 store object `y` (5,229,893 to 5,234,456) does exist in the code. It has `readCredentials`, `readCredentialsStrict`, `writeCredentials`, `deleteCredentials`, `readHandoffCredential`, `writeHandoffCredential` and `probeCredentials()`. `probeCredentials()` returns `{state:"present",version:`${dev}:${ino}:${size}:${mtimeNs}`}` from an `lstat` of `uw()/.credentials.json`, but no running process gets that object.
- **Consequence:** in 2.1.293, `EN({credentials:M,storageV5:N})`, `j7`, `Pl` and `wA` all receive `undefined`. Every `B()&&n!==void 0` branch is dead: the probeCredentials version check, `yDn` priming, `ySr`'s handoff read and the `fromStoreCopy` copy. Whatever value `tengu_hover_rest` has, the **legacy mtime path** runs.

## 4. Where a running interactive session reads its OAuth credential

The auth module starts around 4,655,000. These are the functions involved, with offsets.

- `mn()` (4,657,0xx): `if(S6())return null;let e=Hye.of(F().host);if(e.value!==void 0)return e.value;let n=m$();return e.value=n,n`. This is an **in-memory memo** in class `bA` (`value`, `promise`, `lastCredentialsMtimeMs`, `lastCredentialsVersion`, `lastKeychainAccessToken`, `lastUnusableTokenRecheckAt`, …).
- `m$()` reads sources in this order:
  1. `CLAUDE_CODE_OAUTH_TOKEN` env (refreshToken:null).
  2. The fd/bg-snapshot token `eM()`. It is cached once per process via `Ez/J2` (3,845,608). Its well-known path is `/home/claude/.claude/remote/.oauth_token`, which only applies to CCR.
  3. Otherwise `zn().read({fromStoreCopy:!0})?.claudeAiOauth`. That is a synchronous keychain read served from the 30 s PK cache, with fallback to a `.credentials.json` readFileSync. Because B()-copy is always undefined, `fromStoreCopy` has no effect.
- `Ya(e)` / `b$(e)`: the async equivalent. It memoises a promise in `e.promise` and calls `zn().readAsync(e)`.
- The API client factory `EN` (8,641,523) does `let Se=await j7({credentials:M,storageV5:N}),Te=mn(),Me=U0n({anthropicAuthEnabled:rl(),oauthScopes:Te?.scopes})`. On firstParty it then calls `Xcs({isSubscriber:Me,…oauthAccessToken:Te?.accessToken})`, which builds `new Zme({authToken:…})`.
  - `U0n` requires the scopes to include `xA="user:inference"` (1,671,564).
  - The token is fixed per client object, so an in-flight request keeps the token it started with.

So on macOS today, a session reads keychain item `Claude Code-credentials-<sha256(CLAUDE_CONFIG_DIR)[:8]>` (account `$USER`) through `security find-generic-password` subprocesses. There are two cache layers:

1. The `PK` keychain cache, 30 s TTL (`cPt`).
2. The `Hye` memo (`value`/`promise`), which has no TTL. `Jf`, `ox()`/`EA()`/`e9()` or `SA()` clear it.

`.credentials.json` is read only when the keychain returns null.

## 5. What triggers a re-read: `j7` → `Pl` → `wA` / `Nk` / `Jf`

- `j7` (4,668,113) dedupes concurrent checks per mode ("bare"/"store"/"backend"). With undefined credentials the mode is "bare". It then calls `Pl(…)`.
- `Pl` (4,668,669) starts with `await wA(e,b); let M=await Ya(b); if(!g){ if(M&&!JP(M.expiresAt)) return "not_needed"; if(!M?.refreshToken) return "no_refresh_token" } …`.
  - `JP(e)` (4,704,535) is `n+300000>=e`, a 5-minute expiry window. `null` counts as never expired.
- `wA` (4,658,281) in the legacy branch:
  ```
  let r; try{ r=(await np(rp(uw(),".credentials.json"))).mtimeMs }catch{ return Jf(e,n) }
  if(r!==e.lastCredentialsMtimeMs){ e.lastCredentialsMtimeMs=r, ox(), Xf(e); return }
  await Nk(e,n)
  ```
  The v5 branch (`probeCredentials` version vs `lastCredentialsVersion`) is dead in this build.
- `Jf` (4,659,254) is `e.clear(); if(B())CTe(); let s=(await Ya(n))?.accessToken??null; if(s!==e.lastKeychainAccessToken){ e.lastKeychainAccessToken=s, sp(), Xf(e) }`. It clears the memo and re-reads through `readAsync`, which still honours the 30 s keychain cache. `sp()` resets betas and emits the credential-change event.
- `Nk` (4,658,678) is `if(!Kn())return; r=promise||value; if(r===void 0)return; if(r!==null&&!Ml(r))return; if(now-e.lastUnusableTokenRecheckAt<cPt)return; …; await Jf(e,n)`. It re-reads only when the memoised token is **missing or dead**, and then at most once per 30 s (`cPt` = 30,000 ms). `Ml` treats `refreshToken===""` or a refresh token in the dead set `Oi` as dead.
- `ox()` = `EA()` = `e9()` (clears the memo) + `p0()` (zeroes the keychain cache) + `sp()`.
- Other re-read triggers:
  - `Pl`'s refresh path inside the expiry window, which calls `ox()` before and after taking the lock. If the access token changed, it returns "refreshed" (`tengu_oauth_token_refresh_race_resolved`).
  - The 401 handler `KS` → `y$`, which starts with `ox()`.
  - `lqe(host)`, which is `p0()+wA` and is called by the policy-limits/settings prefetch and the sibling-login watch (32,403,235). The sibling-login watch runs only while a login notice is shown.

**Two regimes, depending on whether `uw()/.credentials.json` exists (measured: it exists only in `~/.claude-tertiary`, mtime Oct 11):**

- **File absent** (next, secondary, quaternary, ~/.claude): the `stat` throws ENOENT, so **every `Pl` call runs `Jf`**: memo cleared, keychain read through the 30 s cache. A keychain change is adopted at the first client build after the cache entry ages past 30 s. Worst case is about 30 s plus the gap to the next API request.
- **File present** (tertiary): `stat` succeeds, and while the mtime is unchanged control goes to `Nk`, which returns immediately for a usable token. **The memo is held indefinitely.** A keychain-only change is not adopted until one of these happens:
  - the file's mtime changes;
  - the token enters the 5-minute expiry window;
  - a 401.

## 6. If an external process changes (a) the keychain item or (b) `.credentials.json`

- **(a) Keychain item changed.**
  - File absent: adopted within ≤30 s (cPt) at the next `EN` client build, which is the next API request in the turn.
  - File present: not adopted until the file's mtime changes, the token nears expiry, or a 401 occurs.
  - The request already streaming keeps its old token.
- **(b) `.credentials.json` changed.**
  - Any mtime change, or creating the file where there was none, triggers `ox()` on the next `Pl` call: memo cleared, keychain cache zeroed, immediate re-read.
  - But the content is ignored whenever the keychain item exists, because the keychain wins. Writing only the file therefore does not switch accounts in any of the 5 config dirs today. It only busts the cache, and that is a usable trick.
  - If the keychain item for that dir is absent, the file content is adopted on the next client build after the mtime change, which is effectively immediate.
  - A CC-side `mutate` (MCP OAuth save, gatewayTrust, …) on a file-only store writes to the keychain and then deletes the file (`if(i===null)await r.delete(o)`). After that, later file-only swaps are silently ignored.

## 7. Can a session-private credential be swapped mid-turn without refresh-rotation hazard?

Mostly yes, with this design:

1. Launch the session once with `CLAUDE_CONFIG_DIR=<the dir that holds the transcript>` (unchanged, so no transcript fork) and `CLAUDE_SECURESTORAGE_CONFIG_DIR=<session-private dir S>`.
   - The keychain item becomes `Claude Code-credentials-<sha256(S)[:8]>`. `.credentials.json`, `.oauth_refresh.lock` and `.storage-write.lock` live in S.
   - This needs one relaunch to adopt. Env cannot be changed in a running process.
2. Put an **inference-only** `claudeAiOauth` in S:
   - `accessToken` from a per-account long-lived token (`claude setup-token`);
   - `refreshToken` **absent/null, not `""`**, because `""` makes `Ml`/`_A` treat the session as logged out;
   - `expiresAt:null` (JP → never expiring);
   - `scopes` including `"user:inference"` (U0n);
   - `subscriptionType`/`rateLimitTier` set.
3. Swap: take the proper-lockfile lock `S/.storage-write.lock`. Read the blob, replace **only** `claudeAiOauth` (the blob also carries mcpOAuth and gateway keys), and write it back with `security add-generic-password -U`. Then touch or rewrite `S/.credentials.json` (0600, same JSON) so `wA` sees an mtime change and runs `ox()` on the next client build. That gives immediate adoption instead of ≤30 s. Release the lock.

Why there is no rotation hazard:

- With no refresh token, `Pl` returns `not_needed` or `no_refresh_token` before any lock or token POST.
- `Bhr` refuses to persist inference-only tokens (`tengu_oauth_tokens_inference_only`).
- The dead-token clear `jhr` and the CAS save `$hr` happen only after a refresh POST.
- So CC never rotates or writes `claudeAiOauth` in S, and the swapper is its sole writer.

The hazard appears only if a **refreshable** credential (refresh token) is copied into S while the same refresh token also lives in the account's own dir. Whichever refreshes first rotates it. The other side then gets `invalid_grant`, `jhr` blanks its token (`refreshToken:""`) and it is logged out.

`CLAUDE_CODE_OAUTH_TOKEN` is not swappable: it is pinned. `y$` logs "keeping the user-supplied CLAUDE_CODE_OAUTH_TOKEN" (Pfs()) and never adopts the stored credential locally.

Caveats:

- The account identity (`oauthAccount`/org in `$CLAUDE_CONFIG_DIR/.claude.json`) is not part of the credential and stays the original account's.
- With 401 and no refresh token, `y$` returns false (`oauth_401_no_refresh_token_interactive`) after clearing caches. Whether the turn then retries or surfaces an error depends on the caller.
- Inference-only scope may break profile and usage calls.
- Retry-on-429 reuse of the old client object was not verified here.

## Side finding

`~/.claude-tertiary/.credentials.json` (1,923 bytes, mtime 2026-10-11 22:47, measured with `ls -la`, contents not read) is a stale plaintext fallback next to a live keychain item (mdat 2026-10-25). It has two effects:

- (i) Sessions on tertiary do not notice external keychain swaps until expiry or 401, because the memo is pinned.
- (ii) If the keychain read ever returns null with no cached data, CC would fall back to the Oct 11 credential, whose refresh token has likely been rotated already. A refresh would then hit `invalid_grant` and `jhr` would blank the stored credential.

Deleting or renaming that file is a candidate operator action. It was not done here: this slot is read-only.
