# G2: CLAUDE_SECURESTORAGE_CONFIG_DIR lane semantics (CC 2.1.293)

Slot: G2-securestorage-lane-semantics. Date: 2026-10-25. Read-only.
Source: `/tmp/mtam/cc293-src.js`, 52,710,919 bytes (measured with `ls -la`). All offsets are byte offsets into that file.
I printed, copied and wrote no credential or token. I made no keychain calls and launched no claude process. I did not touch any pane.

## Method

- Helper: `/tmp/mtam/G2/g.py`, run as `timeout 60 python3 -I`. It has three modes:
  - `find PATTERN` prints the byte offset and ±100 bytes of context for each regex hit.
  - `show OFF A B` prints `d[OFF-A:OFF+B]`.
  - `count PATTERN` counts regex hits.
- Commands run, with their key output:
  1. `find 'CLAUDE_SECURESTORAGE_CONFIG_DIR'` → 10 hits (measured).
     - 1838809: env registry.
     - 2534127: `Sl` set.
     - 3624787: `vo` list.
     - 3737607 and 3737746: `uw`/`FF`.
     - 5255079: `_fr` set.
     - 9569145: `GWe` set.
     - 16379035: `pHt()`.
     - 36021704 and 36021758: `H()`.
     The variable appears nowhere else, so any deny or strip set that does not spread one of these lists cannot contain it.
  2. `find '[^A-Za-z0-9_$.]uw\(\)'` → every `uw()` caller (other `uw` symbols at 32.3M+ are an unrelated UI chunk).
     - 3741498: `.storage-write` lock.
     - 3747419: plaintext backend path.
     - 4594800 and 4595151: lock and outcome files.
     - 4658522: `wA` stat.
     - 4667516 and 4669314: OAuth refresh lock.
     - 5230374: v5 file store path.
     - 7102054, 8237076 and 8386996: path lists.
     - 23639948: design lock.
     - 38172551 and 38511948: `mcp-refresh-*.lock`.
  3. `find '\.credentials\.json'` → 3747428, 4658529, 5230413, 7101804, 27914537 (the SDK exception, see (a4)), 14613933, 19117792 (changelog text) and 36848353 (deny-rule text).
  4. `show 3742279`: the composite `M(e,r)`. `show 3744023`: the keychain backend `b`. `show 3751307`: `zn(){...return M(b,T)}`.
  5. `find 'providerEnv'` and `find '[^A-Za-z0-9_$.]pHt\('` → background-job env capture at 16302339, 16303651, 16307321, 16336209 and 16337709. The env is consumed at 16341286.
  6. `show 38373663`: the MCP stdio spawn. `show 3826344`: `as()`, the child-env builder. `show 3825373`: `nSr()`. `show 2243154`: `FKe`. `show 3628063`: `rat()`.
  7. `find 'authenticatedAccount'`, `find 'function Mn\(\)\{'`, `find 'function iL\(\)\{'`, `find '[^A-Za-z0-9_$.]aSe\('`, `find 'account_uuid:[^,]{0,120}iL\(\)'` and `find '\.oauth_account'`. These show the identity path.
  8. `show 1789184` (`UEr()`, the global config path) and `find 'we=bo'` → 1666864.
  9. `find 'Object\.assign\(process\.env'`, `show 5272319` (settings env applier), `show 18402674` (settings-change handler) and `show 6038092` (watcher file set).
  10. `timeout 20 ls -la ~/.claude-{next,secondary,tertiary,quaternary}/settings.json ~/.claude-{next,quaternary}/.claude.json` (measured):
      - All four `settings.json` are symlinks to `/Users/chrisren/.claude/settings.json`.
      - `.claude.json` is a real file in each config dir: 327,376 B (next) and 342,838 B (quaternary).
      - I also listed `~/.claude-quaternary/projects` by accident. It is a real directory. The output went to a tool-results file and I did not read it further.

## (a) Does the lane also move the plaintext `.credentials.json` fallback? YES, for every live CLI read and write path.

- `uw()` at 3737607: `let e=process.env.CLAUDE_SECURESTORAGE_CONFIG_DIR;if(e!==void 0)return(e||u(o(),".claude")).normalize("NFC");return we()`. The env var is read **on every call**; nothing is memoized.
- Plaintext backend `T`, at 3747419: `function u(){let e=uw(),r=".credentials.json";return{storageDir:e,storagePath:re(e,".credentials.json")}}`. `read`, `readStrict`, `write` and `remove` all use `u()`.
- v5 file store, at 5230374 (chunk imports `uw` from chunk-ayvdek13): `function f(){let e=uw();return{storeDir:e,storePath:D(e,".credentials.json")}}`. It opens the file with `O_NOFOLLOW`. **A symlinked `.credentials.json` in the lane dir is refused** (`refused-symlink`).
- Composite store `zn()` = `M(b,T)` (3751307, 3742279), i.e. keychain item `FF("-credentials")` first, then `T`.
  - When the keychain item is null, the store reads `uw()/.credentials.json`.
  - A successful keychain write deletes that file if the keychain had no item before.
  - A failed keychain write falls back to writing the file.
  - Both legs resolve through the lane.
- Change detection `wA()` at 4658522: `r=(await np(rp(uw(),".credentials.json"))).mtimeMs`. The mtime probe is in the lane too.
- Locks also follow the lane:
  - `uw()/.storage-write` (3741498).
  - The OAuth refresh lock (4667516, 4669314).
  - `mcp-refresh-<server>.lock` (38172551).
- (a4) **One exception, not on the interactive CLI path.** The Agent SDK SessionStore resume helper at 27914537 builds a temp config with `k=r?.CLAUDE_CONFIG_DIR??process.env.CLAUDE_CONFIG_DIR, P=k??~/.claude; C=readFile(P/.credentials.json)`. It reads the keychain via `kn()` (`FF(A_e)`) only when `CLAUDE_CONFIG_DIR` is unset.
  - In that path the fallback FILE is read from `CLAUDE_CONFIG_DIR`, not from the lane.
  - It is used only by SDK `SessionStore.load()`.
- Subtlety: an empty value (`CLAUDE_SECURESTORAGE_CONFIG_DIR=""`) maps to `~/.claude` with NO hash suffix. That is the unsuffixed `Claude Code-credentials` item (3737746: `t=n!==void 0?!n:...`).

## (b) Does it reach the whole process tree? YES on every channel I traced. One caveat: the binding is a launch-time snapshot.

- **In-process subagents and in-process teammates.** They share `process.env`, and `uw()`/`FF()` read `process.env` on every call. There is no per-agent override of either variable anywhere in the 10 occurrences.
  - The keychain cache `PK()` is `d.of(F().host)` (3737607 onward). Even if a context has a different host, it re-reads the same lane item.
  - This is inference from the code structure; I did not trace each agent runner.
- **Pane teammates (agent teams).** `H()` at 36021704 builds the env prefix `CLAUDECODE=1 CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 …`. It forwards `CLAUDE_CONFIG_DIR` (in list `re`) and then adds `if(o!==void 0)e.push("CLAUDE_SECURESTORAGE_CONFIG_DIR=…")`, so the variable is forwarded even when empty.
- **Background jobs (`--bg`, fork-to-bg, routines).**
  - `pHt()` at 16378899 copies every key in `GWe` (9569145; it includes `CLAUDE_CONFIG_DIR` and `CLAUDE_SECURESTORAGE_CONFIG_DIR`) from `process.env`. It keeps an empty lane value: `if(o===""&&n!=="CLAUDE_SECURESTORAGE_CONFIG_DIR")continue`.
  - The result is stored as `providerEnv` in job `state.json` (schema at 9599002; `AYo` re-filters it to `GWe` on load).
  - The job is spawned with `env:{...ae,…}`, where `ae=r?.providerEnv??pHt()` (16337709, 16341286).
  - A bg job therefore binds to the SAME lane as its creator. The binding is a snapshot taken at job creation and survives job respawn.
  - `CLAUDE_BG_AUTH_SNAPSHOT_PATH` (3843264) is a separate one-shot handoff that appears to carry a gateway token. It does not bypass the lane for OAuth. I am moderately sure of that and did not trace it fully.
- **MCP stdio servers.**
  - `new pt({command,args,env:{...Ue,CLAUDE_PROJECT_DIR,CLAUDE_CODE_SESSION_ID,CLAUDECODE:"1",...r.env}})` at 38373663, where `Ue` comes from `as()` (3826344).
  - `as()` starts from `process.env`. It strips the `nSr()`/`Je` sets (OAuth token vars, `FKe`, OTEL and similar), none of which contain the lane variable.
  - It strips `rat()` = `vo` (which DOES list both `CLAUDE_CONFIG_DIR` and `CLAUDE_SECURESTORAGE_CONFIG_DIR`) only when `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` is set, or under GitHub Actions or the `local-agent` entrypoint (`J_r()` 3822153, `vSr()` 3628186).
  - Default local sessions: MCP children and Bash-tool children inherit the lane. Any nested `claude` started from a tool therefore uses the same lane item.
  - MCP servers do not use CC's Anthropic OAuth, but **MCP OAuth tokens live inside the same blob** (`mcpOAuth`, 144 hits; e.g. 38138265 `zn().readAsync()?.mcpOAuth`). A fresh lane item starts with no MCP OAuth, so HTTP/SSE MCP servers that use OAuth would need re-auth or a copied `mcpOAuth` key.
- **Settings cannot set the lane per project.** `_fr` (5251422 / 5255079) is the set project and local settings may not set: "project-scoped settings can't set this key. Set it in ~/.claude/settings.json". User settings and `--settings` (flag) env CAN set it.
- **Live rebind via settings (a mechanism, not a per-session one here).**
  - On a settings change whose `env` differs and with trust accepted, `zP()` runs (18402674).
  - `zP()` calls `applyConfigEnvironmentVariables`, which does `Object.assign(process.env, filterSettingsEnv(...))` for every source (5273605). That can change `CLAUDE_SECURESTORAGE_CONFIG_DIR` inside a running process.
  - Limits:
    - The watcher skips `flagSettings` (6038092: `if(J==="flagSettings")continue`), so only `userSettings` is live.
    - On this machine all four config dirs' `settings.json` symlink to `~/.claude/settings.json` (measured). An edit there rebinds EVERY session on every account.
    - The keychain cache `PK()` is keyed by host, not by item name. The old blob can be served for up to `cPt=30000` ms unless `p0()` runs.
    - `Object.assign` never deletes a key, so a value can be changed but not removed.
  - Not a per-session lever as configured.

## (c) Identity: still keyed on CLAUDE_CONFIG_DIR. A lane-only flip leaves `metadata.user_id.account_uuid` on the old account.

- `metadata.user_id` at 8876661: `account_uuid: (CLAUDE_CODE_REMOTE && CLAUDE_CODE_ACCOUNT_UUID) || iL()?.accountUuid || Mn()?.accountUuid || ""`.
- `Mn(){return rl()?ce().oauthAccount:void 0}` (4676110). `ce()` is the global config at `UEr()` = `join(process.env.CLAUDE_CONFIG_DIR||homedir(), ".claude"+jK()+".json")` (1789184). `uw()` does not appear in that path.
- `iL()` → `BEo()` → `credentialSlots.authenticatedAccount()` (1634296, 1601937). It is in memory and set only by `aSe()`:
  - from bootstrap `ot(o.oauth_account)` (18239236, applied at 18242651);
  - cleared at login (23521808, 26291000);
  - cleared by `kn(){aSe(null)}` (4661628).
- **The 401 adoption path clears the in-memory identity and does not restamp it.** In `y$()` (4661628), every recovery branch (`recovered_from_keychain`, `_from_disk`, `_from_rotation`, `_sdk_callback_refreshed`) calls `kn()`. Right after a lane flip is adopted through a 401, `iL()` is undefined, and `account_uuid` falls back to `Mn()`: the OLD account's `oauthAccount` from `$CLAUDE_CONFIG_DIR/.claude.json`.
- Bootstrap (`dse`/`tCs`, 18241784) is what restamps `authenticatedAccount` from the server, i.e. by the bearer. It runs at startup prefetch (19441514, 19441745), on model validation (23165160), on a model-access probe (18250087) and after login (26292286). It does not run on credential adoption.
  - When it does run, it fixes only the in-memory identity. The on-disk merge `q()` refuses a mismatched uuid: `if(n.account_uuid!=null&&n.account_uuid!==e.accountUuid)return e`.
- Writing a new `oauthAccount` (login, `M8t`) targets `$CLAUDE_CONFIG_DIR/.claude.json`, which is shared by every session on that config dir. It is not lane-scoped.
- `CLAUDE_CODE_ACCOUNT_UUID` is honoured only when `CLAUDE_CODE_REMOTE` is set, which flips the session into remote mode. It is not a local lever.

## Answer

- The lane is complete for the CREDENTIAL. It covers the keychain item, the plaintext fallback, the mtime probe and all locks, and it binds the whole local process tree: subagents, pane teammates, bg jobs, MCP and Bash children.
- It is NOT a complete account move:
  1. The identity records stay on `CLAUDE_CONFIG_DIR`, so `metadata.user_id.account_uuid` keeps naming the old account. After a 401-driven adoption it actively falls back to the on-disk old `oauthAccount`, until a rare bootstrap restamps the in-memory value.
  2. The lane needs a launch-time env (one relaunch) to adopt. A live per-session rebind is impossible: flag settings are not watched, and user settings are shared by all sessions here.
  3. The lane blob must also carry `mcpOAuth`, and it must not share a rotating refresh token with any other item (see S14 §7).
- Verdict: the lane is the right primary mechanism for moving ONE session's billing bearer without touching siblings. Identity is a residual leak to handle separately, by accepting the mismatch or by giving each session its own `CLAUDE_CONFIG_DIR`.

## Corrections to S14

S14 calls 2534127 and 5255079 "propagated env allowlists". They are not:

- 5255079 is the project/local-settings DENY set `_fr`.
- 2534127 (`Sl`) feeds `bl()`, which filters `env` keys out of what looks like an unverified remote or managed settings view. I am less sure of this one.

The actual propagation sets are `GWe` (9569145, bg jobs), `H()`'s explicit push (36021704, teammates) and plain `process.env` inheritance via `as()`.
