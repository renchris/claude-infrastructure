# G4 — In-process account-identity re-sync on credential adoption (Claude Code 2.1.293)

Slot: G4-in-process-account-identity-resync. Date 2026-10-25. Read-only source study of
`/tmp/mtam/cc293-src.js` (52,710,919 bytes, extracted from the 2.1.293 Bun binary). No keychain, pane,
claude, git or settings interaction. Every byte offset below is a `re.finditer` match start in that file
(measured with the helper scripts named in "Method").

## Answer (short)

**Only the login path re-syncs identity. None of the credential-adopt paths short of /login rewrites
`oauthAccount` or stamps `authenticatedAccount` with the new account.** What they do:

| Adopt path | What it does to identity | Offset |
|---|---|---|
| `y$` 401: SDK getOAuthToken callback | `ox(), kn()` (kn = `aSe(null)`: authenticatedAccount := null) | @4661813 |
| `y$` 401: recovered_from_disk (env/FD token mode) | `ox(), kn()` | @4662837 |
| `y$` 401: recovered_from_rotation (after `BRs` poll) | `ox(), kn()` | @4663305 |
| `y$` 401: recovered_from_keychain (`h.accessToken!==e`) | `kn()` | @4663844 |
| `Pl` refresh_race_resolved (two sites) | `kn()` | @4669200, @4670932 |
| `Pl` refresh_race_recovered (two catch sites) | `kn()` | @4672109, @4672428 |
| `$hr` CAS save, adopted_sibling | `kn()` | @4652612 |
| `wA` change-check (version/mtime changed) | `ox(), Xf(e)` — **no kn()**; authenticatedAccount untouched | @4658275-4658510 |
| `Jf` clear-and-re-read | `e.clear()`, `Ya()`, `sp()`, `Xf(e)` — **no kn()** | @4659248 |
| `BRs` env/FD poll | pure poll, returns bool; caller `y$` does the `kn()` | @4660424 |
| `jhr` invalid_grant | marks refresh token dead, blanks stored credential; no identity effect | @4654029 |
| `_adoptSiblingLogin` (credentialsChangedOnDisk subscriber) | only when the session already shows a login-needed notice; refreshes managed settings, bumps a `loginCompleted` counter; no identity stamp | @32402465-32403900 |

`kn()` only **nulls** the in-memory record; it never writes the new identity. Nothing in any of these
paths calls `M8t` (the oauthAccount writer), `ot` (the authenticatedAccount stamper), or the bootstrap
fetch `dse`/`tCs`.

**Which variable supplies `metadata.user_id.account_uuid`:** `KWe` @8876312 (field at @8876727) computes, on
every request build (no memo):

```
account_uuid: Le(a.CLAUDE_CODE_REMOTE)&&a.CLAUDE_CODE_ACCOUNT_UUID || iL()?.accountUuid || Mn()?.accountUuid || ""
```

- `iL()` @4676146 = `rl() ? BEo() : undefined`, and `BEo()` = `credentialSlots.authenticatedAccount()` (in-memory,
  class `Ke` @1601937). It is **set only** by bootstrap `ot(o.oauth_account)` @18239236 (stamped from the server's
  `/api/claude_cli/bootstrap` response for whatever bearer that fetch used), and **nulled** by `kn()` (the adopt
  paths above) or by `/login` `Hxr` and logout (@23521808). `stampAuthenticatedAccount` has exactly one caller,
  `aSe` @1634360 (measured: `find.py 'stampAuthenticatedAccount'` → 2 hits, the definition and `aSe`).
- `Mn()` @4676090 = `rl() ? ce().oauthAccount : undefined`, i.e. `oauthAccount` from `<configDir>/.claude.json`
  via the global-config cache. That cache is live-watched for other processes' writes (macOS: `fs.watchFile`
  with `interval: Xc = 1000` ms, @4544408).

So account_uuid is **neither re-derived from the credential on adoption nor fixed at launch**. It is cached
in-memory from the *last bootstrap fetch* (normally the launch-time one), falling back to the on-disk
config record when that is null.

**Consequence for the three adopt shapes:**

1. Silent swap picked up by the change-check (`Pl`→`wA`→`ox()`; a non-forced `Pl` then returns
   `"not_needed"` with no `kn()`, @4668663): authenticatedAccount keeps the **old** account stamped at launch
   → body account_uuid = old account while the bearer is the new one.
2. Adoption via any `kn()` path (401 recovery, refresh race, CAS sibling): authenticatedAccount := null →
   account_uuid falls back to `oauthAccount` in `.claude.json`, which nothing on these paths rewrites → still
   the **old** account (the config dir did not change).
3. Header-only bearer swap by a proxy: the client never notices; authenticatedAccount stays old → old
   account_uuid in the body.

All three yield a bearer/body-account mismatch **until a bootstrap refresh happens to run**. That refresh is
the only self-heal short of /login: `tCs` calls `ot(o.oauth_account)` @18242651, which stamps the server's
answer for the live bearer, i.e. the *new* account. Triggers found (none is a credential change):
model change in app state (`aan` @18400845), SDK model switch (@26083209), ATIS-pin header mismatch
(`xnn` @12383907, flag `tengu_expressive_whistle`, ≥300 s default interval), resume model restore
(@18267653), model picker effect (@32662614), model validation (@23165160), model-access overturn
(@18250087), and the per-query `_ut`→`O0o` check (@18070432/@18006806), which refetches only when the
client-data slot key (it includes `ce().oauthAccount?.organizationUuid`) has no in-memory entry **and** no
on-disk `clientDataCacheSlots` slot (`Oqe()`).

**/login (`Hxr` @26290727, in `h1e` @26289494)**: `Zoe(...)`, `aSe(null)`, `M8t(profile of the new token)`
(writes oauthAccount with the new accountUuid, email, org and profileFetchedAt), then `Mxr` → `vun` → `dse`
bootstrap → `ot()` stamps the new account. This is the only in-process path that rewrites both records.
Every caller of `h1e`/`Hxr`/`Mxr` is a login flow: @26907487, @28148322/@28148855, @28167901 (login UI),
@28716762 and @28718024 (`claude auth login`).

**Is a body rewrite unavoidable?** Within the stock client, every no-restart swap emits a stale body
account_uuid until a bootstrap refresh restamps it. A proxy that swaps only the bearer must either rewrite
`metadata.user_id` (a JSON string inside the body; whether the `cch`/billing-header attestation covers it is
S03's question and was not checked here) or accept a mismatch window. There is one **client-side
non-/login re-sync route** in source (see Mechanisms M2): an external write of `oauthAccount` into the session's
`<configDir>/.claude.json` (picked up within ~1 s), combined with either a `kn()` (null in-memory) or a
bootstrap refresh. Of all the triggers, only the bootstrap refresh is server-derived and therefore
guaranteed consistent with the bearer.

## Method and commands

Helper scripts, written to `/tmp/mtam/G4/`:
- `ctx.py OFF A B`: print bytes [OFF-A, OFF+B).
- `find.py REGEX N W`: first N regex matches with ±W context.
- `chunks.py OFFS...`: map offsets to Bun chunk boundaries (`// @bun` markers, 2290 measured).
- `imex.py A B names`: imports/exports of a chunk restricted to names.
- `importers.py names`: every `import{...}from` statement that imports a name, with its chunk.
- `inchunk.py A B REGEX W`: regex hits inside one chunk.
- `callers.py REGEX W`: hits with their chunk and nearest enclosing `function NAME(`.

All were run as `timeout 60 python3 -I /tmp/mtam/G4/<script> ...`.

Key commands and their output (summarized):

1. `find.py 'authenticatedAccount'` returned 4 hits, all in class `Ke` @1601937/@1601975 or wrappers @1634296/@1634436:
   `BEo()`=get, `aSe(e)`=stamp, `Lde()`=epoch. `stampAuthenticatedAccount(e)`: if e and current both non-null with the same
   accountUuid, email and org it is a no-op; otherwise epoch+=1 and `#a=e`.
2. `find.py '[^A-Za-z0-9_$.]aSe\('` returned these real callers: `kn(){aSe(null)}` @4661628, `ot()` @18239236 (bootstrap),
   logout `aSe(null)` @23521808, `Hxr` `aSe(null)` @26291000. (@33192575 is an unrelated local `aSe` for the AFK timer, a
   different chunk scope.)
3. `importers.py 'dse,tCs,aSe,ot'` showed that `aSe` is imported by only 5 chunks (auth @3983241, bootstrap @18233623, the state facade
   @21248341 that re-exports it as `setAuthenticatedAccount` with no dynamic caller found, logout @23509782, and login @26287142).
   (`ot` imports from chunk-tnh13g2g are a different binding.)
4. `find.py '[^A-Za-z0-9_$.]kn\(\)'` (the auth-chunk hits) returned @4652612 ($hr), @4661813, @4662837, @4663305, @4663844 (y$),
   @4669200, @4670932, @4672109, @4672428 (Pl). The other `kn` hits are unrelated locals in other chunks.
5. `ctx.py 8876727` gave the full `KWe` (quoted above). `find.py '[^A-Za-z0-9_$.]KWe\('` showed it is called inline at every
   request build: main loop @12469510, sideQuery @10686136, quota check @9759565, model check @8878109, key verify
   @12416698. There is no memo.
6. `find.py '[^A-Za-z0-9_$.]iL\(\)'` found these readers of the in-memory identity: KWe @8876727, user-attributes memo keyed
   `${e}|${Lde()}` @4128355/@4129460, OTel resource @7355816, a cache-key helper @23502185, bridge owner-pin @25248164, and
   Hxr @26290727.
7. `ctx.py 4651959` for `$hr`: a CAS mutate keeps the sibling's credential if the refresh token moved (`w=!0`). On
   `adopted_sibling` it calls `kn()` and returns. It does not write oauthAccount.
8. `ctx.py 4658510` for `wA`/`Jf`/`Nk`/`Xf`: on a version or mtime change it calls `ox(); Xf(e)`. `Jf` calls `e.clear()`, `Ya()`,
   and on a token change `sp()` and `Xf(e)`. `ox()` = `EA()` (+`CTe()`), `EA()` = `e9(), p0(), sp()`,
   `sp()` = `y6(), XCe(), Ok()` @4657361. None of these touches credentialSlots.
9. `python3 -I -c ... d[4661639:4664700]` printed `y$` in full. It has four recovery exits, each `ox()?,kn()`, plus a
   `_Dn` zombie-exit timer. There is no M8t/ot/dse.
10. `d[4660424:...]` printed `BRs` (polls `CLAUDE_CODE_OAUTH_TOKEN ?? eM()` every 2000 ms until the deadline) and
    `kn(){aSe(null)}`.
11. `d.find(b'function Li(')` @4668055 showed `j7` (retry 0, not forced) calls `Pl(b,e,0,void 0,n,void 0,...)`, so
    `h` (entryAccessToken) is undefined and `N=M.accessToken` is already the adopted token. The race branch therefore
    cannot fire, and the function returns `not_needed` if the token is unexpired. No `kn()`.
12. `d.find(b'function jhr(')` shows it blanks `claudeAiOauth` access/refresh/expiry. No identity effect.
13. `find.py 'function Olo\('` and `callers.py 'M8t\('` returned exactly 5 `M8t` call sites. Three are in `Olo`
    (@4706108, @4706713) and `M8t` itself (@4707499). `Olo` = `populateOAuthAccountInfoIfNeeded`: it writes oauthAccount from
    `qVe(mn().accessToken)` (the live token's profile) **only** when the profile is older than `I$=86400000` ms
    (24 h, @4698116) or fields are missing. Its only callers are startup @18471944 and a second entrypoint's startup
    @16524449. The other two `M8t` call sites are in `Hxr` (@26291082, @26291808).
14. `callers.py 'oauthAccount:'` found these writers: `aye` refresh merge @4701715 (displayName, fullName, hasExtraUsageEnabled,
    billingType, accountCreatedAt, subscriptionCreatedAt, ccOnboardingFlags, trial fields, seatTier, planDisplayName,
    profileFetchedAt; **never accountUuid/emailAddress/organizationUuid**), `H8t` roles @4703411, `M8t` @4708931,
    bootstrap `tCs` @18244327 (via `q()`, which returns the record unchanged when `account_uuid` differs, @18239236
    region), trial-end @27517615, extra-usage flag @33043827.
15. `ctx.py 18239236` printed bootstrap `q`/`ot`/`rt`/`tCs`. `rt` fetches `/api/claude_cli/bootstrap` with
    `Bearer ${mn()?.accessToken}`. `tCs` discards the response if `Lde()` (epoch) changed during the fetch, then calls
    `ot(o.oauth_account)`.
16. `find.py 'fetchBootstrapData|refreshBootstrapData'` and `importers.py` listed the bootstrap trigger sites given in the
    answer. `find.py 'clientDataFetches'` and `O0o` @18006806 show that `_ut` @18070432, called from the query loop @18146315,
    the SDK @26625262 and REPL submit @33432219, refetches only on a slot-key miss.
17. `find.py '_adoptSiblingLogin|_siblingLoginWatchEnabled'` and `ctx.py 32221018` show that
    `recheckAfterCredentialsChange` returns false unless `showsLoginNotice()` (state `missing`/`invalid`) and `_t()`.
    Gate flag `tengu_streamed_thimble` (default true).
18. `ctx.py 4548406` and `inchunk.py ... 'function of\('` show that the config freshness watcher is
    `HPt(n,{interval:Xc=1000})` (fs.watchFile) on macOS; Linux opt-in event watch; or a storage-interface subscription.
    External writes trigger `cw`/`vi` re-read unless own writes are pending.
19. `find.py 'x-organization-uuid'` returned hits only on CCR/bridge/environment endpoints (@4425372, @7761905, @7763563,
    @7766490, @9415736). Not seen on the `/v1/messages` builder. (Not exhaustive. S03 owns header identity.)

## Mechanisms noticed (candidate ways to change a live session's account)

- M1 (keychain swap, no identity work): the bearer follows on the next `Pl`/`wA` check, but the body account_uuid stays
  the old account (stamped at launch) until some bootstrap refresh restamps it. A mismatch window of unbounded length.
- M2 (keychain swap + external `oauthAccount` rewrite in `<configDir>/.claude.json`): within ~1 s `Mn()` returns the new
  account, but `iL()` (old, non-null) still wins in KWe. It becomes consistent only once something nulls it (`kn()` on a 401 /
  race / CAS adopt) or restamps it (bootstrap). Side effects: the slot-key org change may itself trigger a bootstrap refresh on
  the next query iteration via `_ut`→`O0o` (if no on-disk slot exists for that org), which would restamp from the server.
  The rewrite affects every other session sharing that config dir.
- M3 (force a bootstrap refresh): any trigger that runs `tCs` after the swap (model switch, SDK `set_model`, resume
  restore) makes `ot()` stamp the server's account for the live bearer. This is the only no-/login path where the identity is
  derived from the token itself. The disk `oauthAccount` still stays old (`q()` refuses a mismatched uuid).
- M4 (in-process /login, `h1e`/`Hxr`): full re-sync of both records plus bootstrap. It needs an interactive OAuth flow or
  `claude auth login` with a refresh token (@28716762, which is a separate process writing the store, not the live session).
- M5 (proxy header-only bearer swap): the client never sees a change, so the body account_uuid is permanently the launch
  account. Consistency requires a body rewrite of `metadata.user_id` (attestation interaction unverified here).
- M6 (`_adoptSiblingLogin`): it adopts a sibling's credential only for sessions that are currently logged-out or invalid. It is not a
  move mechanism for a working session.

## Open questions

- Does the server actually compare `metadata.user_id.account_uuid` with the bearer's account, or is it informational
  only? Source cannot answer. This decides whether the mismatch window matters.
- Does the `cch`/`x-anthropic-billing-header` attestation cover `metadata.user_id`? (S03.)
- Do the per-account `.claude.json` files already hold `clientDataCacheSlots` for the target org? If so, `Oqe()` suppresses the
  `_ut`→`O0o` refetch in M2. (A non-secret read of slot keys would settle it. Not done, to stay strictly in scope.)
- Is the subscription/rate-limit tier used for client-side gating (from the token's `subscriptionType`/`rateLimitTier`)
  consistent with the stale identity record? S01 says these follow the token. Not re-verified here.
