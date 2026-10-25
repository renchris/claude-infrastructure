# G2: bootstrap re-sync trigger and clientDataCacheSlots suppression (Claude Code 2.1.293)

Slot: G2-bootstrap-resync-trigger. Date: 2026-10-25. This is a read-only study of `/tmp/mtam/cc293-src.js`
(52,710,919 bytes) plus non-secret metadata reads of the four `<configDir>/.claude.json` files. I wrote, typed
and launched nothing: no pane, keychain, git, settings or claude interaction. Byte offsets are `re.finditer`
match starts in that file. Account/org UUIDs are truncated to 8 hex characters, and no credential was read or
printed.

## Answer

**Which bootstrap trigger can be induced externally.** Exactly one trigger is both unattended and free of side
effects: the per-iteration slot-key check `_ut -> O0o`. It runs before **every API call of a tool loop** after
the first (and on every REPL submit). It refetches `/api/claude_cli/bootstrap` when the current slot key has
(a) no in-memory `clientDataFetches` entry **and** (b) no on-disk slot (`Oqe()` false). The slot key contains
`ce().oauthAccount.organizationUuid`, which comes from the session's own `<configDir>/.claude.json`, and
external writes to that file are picked up by a 1 s `fs.watchFile`. So an external rewrite of
`oauthAccount` to the target org makes the next loop iteration refetch bootstrap with the live bearer, and
`tCs` then calls `ot(o.oauth_account)`, which stamps the server's account for that bearer into
`authenticatedAccount`. That is the account G4 found feeding `metadata.user_id.account_uuid`.

The other triggers do not qualify:
- Typed into the pane: /login (`Hxr`/`Mxr`), /model, the model picker, slash-command flag settings.
- Launch only: startup prefetch, `Olo`, resume model restore.
- Change the model, which is a disruption: the `aan` mainLoopModel change, the SDK/bridge `set_model`, and the
  in-loop availability/refusal fallbacks.
- Dead here: the ATIS pin (`tengu_expressive_whistle`=false in all 4 cached flag sets; also dead behind a
  non-first-party `ANTHROPIC_BASE_URL`).
- Not a trigger: settings hot-reload. `YHt` updates only `settings`, permissions and `awaySummaryEnabled`, not
  `mainLoopModel`.

**Whether suppression applies.** On disk, every slot in each dir is keyed to that dir's own org. All
**33/33** slot keys reproduce exactly from `[entrypoint, model, ccVersion, org]`. Per dir: next 6/6 org
260ebc56, next2 12/12 fb09ef51, next3 3/3 1a71eca0, next4 12/12 c570be13. `Oqe()` reads the **session's own**
`.claude.json`. So for the **first** cross-account rewrite of a dir, no target-org slot exists there, and
`Oqe()` does **not** suppress: the refetch fires. The next4 dir does hold `bi1-32f9077e892043f9` (cli, opus-5-5,
2.1.293, org c570be13), but it lives in next4's file, which a session in another dir never reads.

Three hazards follow:
1. **Write-once suppression.** The first session in the dir that refetches writes the target-org slot. From
   then on `Oqe()` is true for every other session in that dir with the same (entrypoint, model). It is also
   true for every later move of that dir to the same org, because `Oqe()`/`Va()` has **no age check** and
   slots live in a 12-entry LRU. Those sessions keep the old stamp with no upper bound.
2. **Poisoning.** If the rewrite becomes visible before the swapped token has been adopted, the bootstrap fetch
   runs with the **old** bearer. `ot()` restamps the old account, the target-org slot is written anyway, and
   the in-memory entry becomes "over". The refetch is then suppressed for good.
3. **Workable design.** An unattended re-sync is possible, but only as an ordered protocol:
   - swap the token;
   - wait for adoption: one or more API requests starting more than 30 s after the swap;
   - under the `.claude.json.lock` lock, rewrite `oauthAccount` **and delete every target-org `bi1-` slot** in
     that dir;
   - keep deleting those slots until every live session in the dir has iterated.

   Otherwise the design must rewrite the body `account_uuid` or accept the mismatch.

## Method

The helper scripts in `/tmp/mtam/G2-bootstrap-resync-trigger/` were all run as `timeout 60 python3 -I <script>`.
`find.py REGEX N W` and `ctx.py OFF A B` are copies of G4's. `encl.py OFFS` names the nearest enclosing
functions, `back.py` finds the enclosing generator and loop, and `lastdef.py` finds a local's definition.
`slots.py` lists slot metadata and recomputes keys, `flags.py` reads cached GrowthBook values for named flags
only, and `envchk.py` reports whether named env vars are set in settings.json (set/unset only).

## Evidence: source

### Slot key and suppressor
- `Vyr` @4518220: `JSON.stringify([e.entrypoint??null,e.model,e.ccVersion,e.organizationUuid])`, then
  `"bi1-"+sha256(..).hex.slice(0,16)`. Constants are set at @4518391: `oB=12` (slot cap), `rgs=86400000`
  (24 h stale, used only inside `tCs`), `iB=604800000` (7 d, stale-match reads only).
- `ogs` @4518526 keeps the 11 newest other `bi1-` slots plus the new one.
- `R()` (bootstrap chunk, @~18237900) builds `{entrypoint, model:Dn(nt()), ccVersion:"2.1.293",
  organizationUuid: ce().oauthAccount?.organizationUuid??null}`. `tt()` registers the getter
  `uuo((e)=>Vyr(R(...)))`.
- `Oqe` @4581182:
  `function Oqe(){let e=re();if(!e.clientDataCacheKeyGetter)return!1;let n=ce().clientDataCacheSlots;return Va(n,e.clientDataCacheKeyGetter())!==null}`.
  `Va` @~4518700 checks only `pRt` (object with `data` and numeric `at`). There is **no age check**.
- `O0o` @18006715:
  `let t=n_r();if(t===void 0||!SOr()||Oqe())return;let o=Nr().providerCache.clientDataFetches.get(t);if(o!==void 0)return o==="over"?void 0:o;return i(n,e,t_r())`.
  `i()` dynamic-imports `refreshBootstrapData` (= `tCs`, export list @22869634).
- `Zut` @18006406 records the promise per key. On settle it sets "over" when the epoch `Lde()` is unchanged, and
  **deletes** the entry when the epoch changed. A successful cross-account `ot()` bumps the epoch, so the entry
  is deleted, but by then the disk slot exists and `Oqe()` suppresses further fetches.
- `SOr()` = `Nr().fetchesClientData && Pe()==="firstParty"`. `fetchesClientData` is set only by
  `P0o(!yr())` @19441284, where `yr()` = `CLAUDE_CODE_SIMPLE` or `--bare`.

### `_ut` call frequency
- `_ut` @18070424 calls `O0o(storageV5,credentials)`. If a fetch is pending and `tengu_deep_shore` (cached
  `true` in all 4 dirs) is set, it waits up to `ic=1500` ms. It never blocks the turn beyond that.
- In the query generator `ed` @18138874, `while(!0)` @18142475 is followed by `Hs` @18146250:
  `let se=js(h,A),Q=Co;if(Co=void 0,...)...let re=Q?.model===se?Q:await _ut(se,f)`. The first iteration reuses
  the prefetched `modelFacts`, and **every later iteration (each API call in a tool loop) calls `_ut`**. This is
  mid-turn and needs no input.
- REPL submit @33432219 (`gn=Q?await _ut(...)`, where `Q` is the shouldQuery argument of `_runImpl` @33430635)
  and SDK @26625262 also call it.

### Bootstrap fetch and stamping (`tCs` @18241823)
- `rt()` sends `Bearer ${mn()?.accessToken}` through `dS` @4097657. That is the **memoised** credential;
  `dS` does no `wA`/`Pl` freshness check.
- After the fetch, `A!==Lde()` discards the response (superseded credential). Otherwise it calls
  `ot(o.oauth_account)` (`aSe({accountUuid,...})`), which stamps unconditionally from the server's answer.
- It writes the slot under `Vyr({...r, organizationUuid: q(C.oauthAccount, o.oauth_account)?.organizationUuid})`.
  `q()` returns the on-disk record unchanged when `account_uuid` differs. So with a stale bearer the
  **target-org key still gets written** (with the old account's data). This is the poisoning hazard.
- The config write goes through `Ae` @4540884, then `kB`, then `Ai` @4554288: a proper-lockfile lock on
  `<configDir>/.claude.json.lock` and a **re-read of disk under the lock** (`af(e,n)`) before the mutate. An
  external writer that takes the same lock is merged and not clobbered.

### Config freshness (so an external rewrite is seen)
- The watcher at @4544430: `if(fw()) zc event-watch else HPt(n,{interval:Xc=1000,persistent:!1},r)`. It is
  skipped only when `Qr()` = `B()&&!fileWatchFallback`. `fileWatchFallback` defaults to `!0` (@4521893) and is
  cleared only with a v5 backend (`BB` @4564254). `tengu_hover_rest` is cached `false` in all 4 dirs, and S14
  shows the v5 backend is always undefined. So on macOS the 1 s `fs.watchFile` path is live.

### Credential adoption timing (for the ordering rule)
- `wA` @4658281 stats `<configDir>/.credentials.json`. If it is absent (next, next2, next4, measured with
  `ls`), it runs `Jf` (clear and re-read through the 30 s keychain cache, per S14). `wA` runs from `Pl` at
  client build, i.e. **after** `_ut` in the same iteration. So the bootstrap fetch in iteration N uses the
  token memoised at iteration N-1's request.
- next3 has a stale `.credentials.json` (Oct 11, contents not read). Its mtime regime does not adopt a keychain
  swap until the token goes dead (S14 §"Two regimes"). That is a separate blocker for next3 as a **source**.

### Trigger enumeration and classification
| # | Site (offset) | Path | Class |
|---|---|---|---|
| 1 | `_ut`->`O0o` @18070432 / @18006806; callers @18146315 (loop), @33432219 (REPL submit), @26625262 (SDK) | slot-key miss, i.e. org (oauthAccount on disk), model or entrypoint change | **Externally inducible** via an `oauthAccount.organizationUuid` rewrite in `<configDir>/.claude.json`. Unattended, fires at the next loop iteration. Suppressed if a disk slot for the key exists |
| 2 | `aan` in `Lon` @18400845 (app-state onChange, `e.mainLoopModel!==i.mainLoopModel`) | refreshBootstrapData | Pane (/model @23167471, picker @32931507, fast-mode toggle @23483840) or model fallback inside the loop (@18157389 switch_default, @18169874 availability, @18175775 fallback). Changes the model, so it is disruptive |
| 3 | SDK `set_model` @26083209 (`if(nt()!==N)aan(...)`) | refreshBootstrapData | SDK/bridge control request (Remote Control's `set_model` is in the allowed set @7960991). Changes the model. Not usable for an interactive pane without RC; disruptive |
| 4 | `xnn` ATIS pin @12383907 (main-query response header `x-cc-atis-current`) | refreshBootstrapData `keepRenderCaches` | Server-driven. Flag `tengu_expressive_whistle` default `!1` and cached **false** in all 4 dirs. Needs `Sl()` = firstParty plus a first-party base URL, so a localhost proxy disables it. **Dead** |
| 5 | `Ipe` model-access overturn @18250087 (`dse`) | fetchBootstrapData | Model switch, resume restore or startup (callers @23163234, @18265465, @19367058, @26081190). Pane, launch or SDK |
| 6 | `mwe` model validation @23165160 (`dse` when a fable-absent probe is valid) | fetchBootstrapData | `/model` inline @23185698, SDK set_model @26082086, bridge picker @43015568/@43017083. Pane or remote |
| 7 | Resume restore `ee` @18267653 (`Sxe`) | fetchBootstrapData | Launch/resume only (@18277961, @26757840, @32395297, @40299459) |
| 8 | Model picker effect @32662614 | fetchBootstrapData | Pane UI |
| 9 | Startup prefetch @19441514 / @19441745 (`!Oqe()`) | dse | Launch only |
| 10 | Login `Mxr` @26292286 (`vun` then `dse`) | dse plus M8t | Pane (/login) or `claude auth login` |
| 11 | `Olo` @4705992 (`populateOAuthAccountInfoIfNeeded`, M8t from the live token profile only if >24 h stale or fields missing) | oauthAccount writer (not bootstrap) | Launch only (@18471944, @16524449) |
| 12 | `M8t` | oauthAccount writer | Only `Olo` and `Hxr` (G4 measured 5 call sites) |
| 13 | Settings hot-reload: `u1e` -> `YHt` @19649656 | none | `YHt` sets `settings`, `toolPermissionContext`, `awaySummaryEnabled`. **No `mainLoopModel` and no bootstrap.** `apply_flag_settings` (`hXe` @23480767, which can set `model`) comes only from slash commands (@3144152) or Remote Control, and RC is restricted to effortLevel/ultracode (@7954235) |

## Evidence: disk (measured, `timeout 60 python3 -I /tmp/mtam/G2-bootstrap-resync-trigger/slots.py`)
Per dir: oauthAccount account/org (8 hex), then each slot `key ep model org at ver(recomputed)`.
- **next** (`~/.claude-next`), acct d5f84d93, org 260ebc56, 6 slots, all org 260ebc56:
  - `bi1-09867af54c5dba61` sdk-cli/opus-5-5/2.1.293
  - `bi1-d507e1ffd038c65c` sdk-cli/haiku-4-5
  - `bi1-88c48757c10dd45a` cli/opus-5-5/2.1.293
  - `bi1-a50125c9b8510ed6` sdk-cli/opus-5-5/2.1.291
  - `bi1-c4020f7ee0453d3e` cli/haiku-5-5
  - `bi1-e1e62fe06b62140a` sdk-cli/sonnet-5-5/2.1.291
- **next2** (`~/.claude-secondary`), acct 76570e6e, org fb09ef51, 12 slots (LRU full), all org fb09ef51.
  This includes `bi1-3af083c12b3f5143` cli/opus-5-5/2.1.293.
- **next3** (`~/.claude-tertiary`), acct d0955289, org 1a71eca0, 3 slots, all org 1a71eca0. This includes
  `bi1-84fcc89cf7f1b097` cli/opus-5-5/2.1.293.
- **next4** (`~/.claude-quaternary`), acct ac8c0b73, org c570be13, 12 slots (LRU full), all org c570be13. This
  includes `bi1-32f9077e892043f9` cli/opus-5-5/2.1.293 (at 2026-10-24T21:50) and `bi1-ca561515d3b06558`
  sdk-cli/opus-5-5/2.1.293.
- Key recomputation: 33/33 keys matched exactly one `2.1.2xx` version, so the formula is verified. No dir
  holds a slot for any org other than its own. **No cross-account slot exists anywhere.**

Flags (`flags.py`, cachedGrowthBookFeatures, same in all 4): `tengu_expressive_whistle=false`,
`tengu_deep_shore=true`, `tengu_hover_rest=false`.

Settings (`envchk.py`): every per-dir settings.json is a symlink to `~/.claude/settings.json`. Its env sets
none of `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` (which would skip bootstrap via `Tt()` @1776587),
`ANTHROPIC_UNIX_SOCKET`, `ANTHROPIC_BASE_URL`, `CLAUDE_CODE_SIMPLE` or `CLAUDE_CODE_ENTRYPOINT`. There is no
`model` key. The per-process env of live sessions was not inspected.

## Answer to the suppression question, worked
Take a session in `~/.claude-next` on cli/opus-5-5 moved to next4. After `oauthAccount` (org c570be13) is
written into `~/.claude-next/.claude.json`, the key becomes
`Vyr(["cli","claude-opus-5-5","2.1.293","c570be13…"])` = `bi1-32f9077e892043f9` (the key next4 itself uses).
`Oqe()` looks it up in **`~/.claude-next/.claude.json`**, which has no such key, so the refetch is **not
suppressed** on the first move. The slot in `~/.claude-quaternary/.claude.json` is irrelevant, because
`Oqe()` reads only the session's own config. Suppression appears after that:
- The first session to refetch writes `bi1-32f9077e892043f9` into next's file. Every other next session on
  cli/opus-5-5 that has not yet iterated then sees `Oqe()` true, does not refetch, and keeps its launch-time
  stamp (d5f84d93).
- Any later next->next4 rewrite within that slot's LRU lifetime is suppressed for every session.
- A session on a different model or entrypoint (sdk-cli/haiku, …) has a different key and refetches on its own.

## Mechanisms (candidates)
- R1 (ordered unattended re-sync): (1) swap the source dir's credential; (2) wait for adoption; (3) under
  `.claude.json.lock`, rewrite `oauthAccount` to the target and delete every `bi1-` slot whose `org` is the
  target org; (4) keep re-deleting those slots until each live session in the dir has run a loop iteration or
  submit. Each session then refetches once, and `ot()` stamps the server's account for the live bearer.
- R2 (naive rewrite): works for the first session per (dir, entrypoint, model) and silently fails for the
  rest. Not acceptable alone.
- R3 (model nudge): any mainLoopModel change runs `aan`, but it changes the model. Disruptive.
- R4 (do nothing / proxy body rewrite): G4's M5. Needed if R1's ordering cannot be guaranteed.

## Open questions
- Adoption is not observable from outside except indirectly (S14's 30 s cache, request timing). A wrong
  ordering poisons the slot permanently. Can adoption be confirmed by observation without a token read? One
  candidate is the `[Bootstrap]` debug log, if the session runs with debug on.
- Does deleting slots externally under the lock interact badly with `GB()`/`Iw()` reads for the current
  window? I expect a fallback to the window seed or legacy `clientDataCache` (it is present in next, next2 and
  next4), but this was not traced to the effect on the system prompt.
- `fetchesClientData` is set at @19441284. I did not prove that this is on the interactive REPL path; I
  inferred it because it is the only `P0o` caller (confidence about 85%).
- Server side: does a body `account_uuid` mismatch matter at all? (G4/S03.)
