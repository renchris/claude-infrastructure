# G2-keychain-acl-write-feasibility

Slot: G2-keychain-acl-write-feasibility. Date: 2026-10-25, about 02:50-03:05 CDT. Read-only.
Question: can an outside process running as the same user atomically rewrite the `claudeAiOauth` field of a config dir's keychain item without a GUI authorization prompt? What write contract would an external mover have to honor?

## Answer (short)

**Yes, with conditions.** All four live items, and all 35 `Claude Code-credentials*` items in the login keychain, carry the same ACL. That ACL is app-scoped, but **the trusted app is `/usr/bin/security`, not claude.exe**: identifier `com.apple.security`, anchor apple, partition_id `apple-tool:`.

Claude Code never touches the keychain through Security.framework. Every read and write runs the `/usr/bin/security` CLI as a child process. securityd therefore sees `/usr/bin/security` as the client, whichever process launched it. An outside mover that also runs `/usr/bin/security` looks exactly like Claude Code to the ACL check, so no dialog is raised.

`add-generic-password -U` without `-T` or `-A` calls only `SecKeychainItemModifyContent` on the existing item. It never calls `SecKeychainItemSetAccess`, which is the call Apple's own source comments as "will prompt". The ACL is preserved, and the measured items confirm this: they were created months ago, rewritten tonight, and still carry the original ACL.

The login keychain is set to `no-timeout`, with no lock-on-sleep shown. So the write is feasible unattended **provided all of the following hold**:

- (a) The mover uses `/usr/bin/security`, not a Security.framework client such as Python keyring or a Swift tool. A different client is not on the ACL and is not in the `apple-tool:` partition, so it would prompt.
- (b) The mover runs in the user's GUI security session (an Aqua LaunchAgent or a terminal), not as a LaunchDaemon.
- (c) The mover honors the read-modify-write contract below.

**The rewrite is atomic per item, but the field swap is not atomic.** The keychain replaces the whole blob in one operation. Rewriting only `claudeAiOauth` is a read-modify-write of one JSON blob that is shared with mcpOAuth and pluginSecrets. That swap is safe against Claude Code's own writers only when the mover holds `<configDir>/.storage-write.lock`. Nothing outside Claude Code takes that lock today.

## Method and commands (key output)

1. Suffix hashes. Ran `printf '%s' "$d" | shasum -a 256 | cut -c1-8`. Measured:
   - next = `~/.claude-next` = 2be71cf3
   - next2 = `~/.claude-secondary` = 0503d474
   - next3 = `~/.claude-tertiary` = 6a49a3e4
   - next4 = `~/.claude-quaternary` = 136fa815
   - `~/.claude` = 7b461744

   `security list-keychains` shows login.keychain-db and System.keychain.
2. ACL dump. Ran `timeout 250 security dump-keychain -a /Users/chrisren/Library/Keychains/login.keychain-db > /tmp/mtam/G2-keychain-acl-write-feasibility/raw_dump_noData.txt`. This used no `-d`, so nothing was decrypted. The first attempt hit a 55 s timeout under load 742. Run in the background, it finished with exit 0.
   - The file has 304 `keychain:` blocks and **0 `data:` lines** (measured with grep -c).
   - No authorization dialog was triggered. The dump ran unattended to completion, and ACL reading is not gated.
   - `filter.py` kept only the blocks containing `Claude Code` and wrote them to `claude_acl_blocks.txt`: 35 blocks. `summ.py` summarized them.
3. Measured ACL of the four live items. All are acct="chrisren" and class genp in login.keychain-db. All four have the identical 5-entry ACL below; only the integrity hash differs.
   ```
   entry: authorizations (1): encrypt            don't-require-password  applications: <null>   (any app)
   entry: authorizations (6): decrypt derive export_clear export_wrapped mac sign  don't-require-password
          applications (1): 0: /usr/bin/security (OK)  requirement: identifier "com.apple.security" and anchor apple
   entry: authorizations (1): integrity          applications: <null>
   entry: authorizations (1): partition_id       description: apple-tool:
   entry: authorizations (1): change_acl         applications (0):      (nobody: changing the ACL would prompt)
   ```
   | item | acct | cdat (Z) | mdat (Z) |
   |---|---|---|---|
   | -2be71cf3 (next) | chrisren | 20261021093957 | 20261025043330 |
   | -0503d474 (next2) | chrisren | 20260804101707 | 20261025071848 |
   | -6a49a3e4 (next3) | chrisren | 20261011223324 | 20261025063946 |
   | -136fa815 (next4) | chrisren | 20260625193904 | 20261025073624 |

   All 35 `Claude Code-credentials*` items have the same structure: decrypt trusted only for `/usr/bin/security`, partition `apple-tool:`, and an empty change_acl list. The difference between cdat and mdat on the live items (created June to October, modified tonight) shows that Claude Code's repeated `-U` rewrites left the ACL unchanged (measured).
4. **Trap found:** there is a **second `Claude Code-credentials-136fa815` item with acct="unknown"** (cdat and mdat 20260911231348Z/…401Z). There is also a second unsuffixed `Claude Code-credentials` item with acct="unknown".
   - Claude Code always passes `-a "$USER"` (FT(), offset 3738005: `process.env.USER||l().username`, else `"claude-code-user"`), so it addresses the chrisren item.
   - A mover that uses `-s` alone could read or update the wrong item, and next4 is the move target. The mover must pass `-a chrisren`.
5. Lock settings. `security show-keychain-info login.keychain-db` returned `no-timeout`, rc=0. rc 36 would mean locked. No lock-on-sleep is printed.
6. Per-dir files. Ran `ls -lad <dir> <dir>/.credentials.json <dir>/.storage-write.lock <dir>/.oauth_refresh.lock`.
   - All four config dirs are real directories, not symlinks, so each has its own lock path.
   - No `.storage-write.lock` or `.oauth_refresh.lock` existed at that moment. Locks are transient.
   - Only `~/.claude-tertiary/.credentials.json` exists: 1923 B, mode 0600, mtime Oct 11 22:47. It is a stale plaintext copy; the keychain is read first, so it is ignored for data but still serves as the wA mtime signal. **Its content was not read.**
7. Debug logs. `grep -rhoE 'Keychain payload \([0-9]+B JSON\) exceeds' ~/.claude*/debug` returned no hits in any of the 5 dirs (measured). The current blob size is unknown.
8. Apple `security` tool source. Fetched `gh api repos/apple-oss-distributions/Security/contents/SecurityTool/macOS/keychain_add.c` from the main branch; the last commit to the file is 154ef3d9d6f5, 2022-02-07. Saved to /tmp/mtam/G2-keychain-acl-write-feasibility/keychain_add.c.
   - `case 'U': update_item = TRUE;` (line 649). Only `-A` and `-T` set `access_specified` (lines 654, 683). Without them `access` stays NULL.
   - `do_update_generic_password` (line 50) runs `find_first_generic_password(...serviceName,accountName)`, then `SecKeychainItemModifyContent(itemRef,&attrList,passwordLength,passwordData)`.
   - It reaches `SecKeychainItemSetAccess(itemRef, curAccess); // will prompt` only `if (!status && access)`.
   - So a `-U` rewrite without `-T`/`-A` changes the data and keeps the ACL, and does not take the documented prompt path.

## Claude Code 2.1.293 write contract (source /tmp/mtam/cc293-src.js, byte offsets)

- **Naming** (3737556-3738141): `A_e="-credentials"`. `uw()` is `CLAUDE_SECURESTORAGE_CONFIG_DIR` if set, else `we()`, the config dir. `FF()` is `"Claude Code"+OAUTH_FILE_SUFFIX+"-credentials"+"-"+sha256(dir)[:8]`. `FT()` is `$USER`. The keychain read cache is `cPt=30000` ms per host (`PK()`). `p0()` clears it.
- **Lock** `ryo(e)` (3741539; `.storage-write` literal at 3741544, the only occurrence):
  ```
  async function ryo(e){if(I.getStore())return e();let r=x,a;x=new Promise(...);try{await r;let s=uw();await se().mkdir(s);
  let n=await Ra(Q(s,".storage-write"),{realpath:!1,retries:{retries:10,minTimeout:100,maxTimeout:1000},stale:15000,onCompromised:...});
  try{return await I.run(!0,e)}finally{await n()...}}finally{a()}}
  ```
  - The lock combines an in-process promise chain with a cross-process proper-lockfile `Ra`.
  - From the proper-lockfile code (3731740 area): the on-disk lock is the **directory** `<uw()>/.storage-write.lock`, created with `mkdir` (`ne(e,r){return r.lockfilePath||`${e}.lock`}`). On EEXIST, a lock whose mtime is older than `stale` (15000 ms) is removed with rmdir and the mkdir is retried. The holder refreshes the lock's mtime, by default every stale/2.
  - Claude Code gives up after 10 retries with 100-1000 ms backoff, which is a few seconds, and then throws ELOCKED.
  - **An outsider can take the same lock** by doing the following:
    - mkdir `<dir>/.storage-write.lock`
    - treat an existing lock as stale only after its mtime is more than 15 s old
    - touch its mtime at least every 7.5 s while holding it
    - hold it for less than about 5 s, so Claude Code's own writers do not time out
    - rmdir it when done
  - Nothing outside Claude Code takes this lock today.
- **Read-modify-write** `d(e,r,a)` (just after ryo, about 3741900), quoted exactly:
  ```
  return ryo(async()=>{e.invalidateCache?.();let s=await(e.readAsyncStrict?.(a,{inaccessibleAs:"failureIfTransient"})??e.readAsync(a));
  if(s===Sa)return ...{success:!1,transient:!0};let n=s??{},o=r(n);return o===n?{success:!0}:await e.update(o,a)})
  ```
  - Every Claude Code write is mutate(fn). It locks, drops the cache, reads the whole blob fresh, applies fn, and writes the **whole blob**.
  - No `zn().update(`/`zn().delete(` caller and no aliased `x=zn();x.update(` was found (measured: 0 hits). Writes go through the lock.
- **Keychain write** `b.update` (about 3745480):
  ```
  i=`add-generic-password -U -a "${s}" -s "${a}" -X "${o}"\n`; if(i.length<=ee) c=await bg("security",["-i"],{input:i,...timeout:f})
  else ... c=await bg("security",["add-generic-password","-U","-a",s,"-s",a,"-X",o],...)
  ```
  - The constants are `ee=4032`, `f=2000` ms and `U=36` (locked).
  - The payload goes in as a hex blob on `security -i` stdin. **Above 4032 chars of command it falls back to argv, which exposes the hex secret in `ps`.**
  - No `-T`/`-A` is passed, so the ACL is never altered.
  - Reads use `security find-generic-password -a <user> -w -s <svc>`, both synchronously (KTe, 3744216) and asynchronously (v(), 3746553).
- **Blob is shared.** The top-level keys written by `zn().mutate((x)=>({...x,KEY:` include:
  - claudeAiOauth (28149165)
  - gatewayTrust (4019016)
  - enterpriseGateway (4613391)
  - trustedDeviceToken (7978815)
  - mcpXaaIdp and mcpXaaIdpConfig (38103609, 38104046)
  - mcpOAuth (38159619, 38163403)
  - mcpOAuthClientConfig (38178855)

  mutate sites also touch pluginSecrets, designOauth, coworkRemoteDevice and mcpDiscoveryCacheKey. There are 69 `.mutate(` hits in total, some unrelated to storage.

  A mover must therefore read the whole blob, replace **only** `claudeAiOauth`, preserve every other key byte-for-byte as JSON, and write the whole blob back, all under the lock.
- **The claudeAiOauth value shape** `aA()` (about 4651600) is `{accessToken, refreshToken, expiresAt, refreshTokenExpiresAt, scopes, subscriptionType, rateLimitTier, clientId}`.
- **Refresh CAS** `$hr` (about 4651826):
  ```
  zn().mutate((U)=>{let G=U.claudeAiOauth?.refreshToken;if(!(U.claudeAiOauth!==void 0&&U.claudeAiOauth!==null&&(G===""||G===n)))return w=!0,U;...
  ```
  - If a mover has swapped in a different refresh token while a Claude Code refresh POST was in flight, Claude Code **adopts the mover's write** (`tengu_oauth_refresh_save_adopted_newer_write`, `adopted_sibling`) and does not overwrite it. This holds only if the mover's write lands before Claude Code's locked mutate.
  - **Hazard:** the old account's freshly rotated refresh token returned by that POST is then discarded. If the server rotates refresh tokens single-use, the old account's other copies may go dead. Bhr (about 4654138), used on non-CAS paths, writes unconditionally, but still under the lock and after a fresh read.
  - `.oauth_refresh.lock` (refresh serialization, about 4670300) is a separate lock. A mover that wants no in-flight refresh to be discarded should also take it.
- **Dead-token clear** `jhr` (about 4654300) mutates `claudeAiOauth` to empty tokens only if the stored refresh token equals the dead one. A mover's new refresh token is not cleared by a late invalid_grant on the old one.

## External-mover write contract (derived)

1. Use `/usr/bin/security` only, with `-a "$USER"` (chrisren) and `-s "Claude Code-credentials-<hash>"`.
2. mkdir `<configDir>/.storage-write.lock`, refresh its mtime, and hold it for less than about 5 s. Optionally also take `.oauth_refresh.lock`.
3. Inside the lock, read the blob with `find-generic-password -a … -w -s …`. This prints the secret to the mover's pipe and must never be logged.
4. Parse the JSON, replace `claudeAiOauth` only, and write it back with `security -i` stdin `add-generic-password -U -a … -s … -X <hex>\n`. Never use argv, never use `-T`/`-A`, and never use `-p`/`-w` on argv.
5. Release the lock.
6. Adoption by the live process is covered by other slots (wA/.credentials.json mtime, the 30 s PK cache, the y$ 401 path), not here.

## Caveats and confidence

- I did **not** perform a write or a `-w` read; both are forbidden here. "No prompt" is inferred from the measured ACL, from Apple's tool source and from Claude Code itself rewriting these items unattended tonight (mdat). It was not observed on a write by an outside process.
- Expected behavior for an outside process: a LaunchDaemon, or an ssh session without an unlocked login keychain, gets exit 36 or errSecInteractionNotAllowed instead of a prompt. This is general macOS knowledge and was not measured here.
- Two items have acct="unknown" (unsuffixed and -136fa815). Their origin is unknown; Claude Code ignores them.

Sources:
- [apple-oss-distributions/Security keychain_add.c](https://github.com/apple-oss-distributions/Security/blob/main/SecurityTool/macOS/keychain_add.c), lines 50-160, 649-683
- [opensource.apple.com keychain_add.c (Security-57336.1.9)](https://opensource.apple.com/source/Security/Security-57336.1.9/SecurityTool/keychain_add.c.auto.html), found in search; it returned 404 when fetched
