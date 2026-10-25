# G1: credential-store topology of next / next2 / next3 / next4 (2026-10-25, about 02:29 to 02:37 CDT)

Slot: G1-credential-store-topology. The run was read-only. No secret value was printed, copied or written by me.

## 0. The rule that shaped the method (deviation from the brief, stated up front)

The brief asked me to parse each keychain item's JSON blob. Its own hard rule forbids `security find-generic-password` with `-w` or `-g`, and those flags are the only CLI paths to the blob. So **I did not read any keychain secret.** I also did not run any tool that reads one internally: `bin/claude-accounts` and `bin/cc-relogin` both call `-w`, so I did not invoke them.

Here is what I used instead. Every source is read-only and on disk.

1. **Fingerprints already on disk.** The fleet's own `claude-accounts --local-refresh` pass reads each account's keychain item every ~20 s. It persists only `sha256(token)[:16]` fingerprints (`_rt_fingerprint` at `bin/claude-accounts:2186-2191`, `_at_fp` at `:7915-7916`, `_creds_item` at `:8064-8073`). It writes them to `~/.claude/logs/claude-accounts-lastgood.local-state.json` (`items`) and `/tmp/claude-accounts-cache.json` (`rows[].rt_fp`). I compared those fingerprints and printed only equality booleans, never the fingerprints.
2. **Keychain attributes only.** I enumerated every item with `security dump-keychain`, run without `-d`/`-a`, so no data is decrypted. I printed only svce/acct/cdat/mdat.
3. **`~/.claude-tertiary/.credentials.json`**, a plain file. I parsed it in `python3 -I` and printed key names, the non-secret fields, and equality booleans of its token fingerprints against the four live ones. I used the same sha256[:16] scheme so the values are comparable.
4. **`oauthAccount` in each config dir's `.claude.json`**. This holds identity metadata, not credential material.

Scripts are in `/tmp/mtam/G1/` (`a.py`, `kc.py`, `h.py`, `oa.py`, `oa2.py`, `tf.py`, `g.py`). Every command ran under `timeout`.

## 1. Which keychain item belongs to which account (measured: `python3 -I /tmp/mtam/G1/h.py`, `/tmp/mtam/G1/kc.py`)

`sha256(abs config dir)[:8]` and the matching items from `dump-keychain` (35 `Claude Code*` items in total):

| account | config dir | service suffix | item acct | cdat (UTC) | mdat (UTC) |
|---|---|---|---|---|---|
| next  | ~/.claude-next | 2be71cf3 | chrisren | 2026-10-21 09:39:57 | 2026-10-25 04:33:30 |
| next2 | ~/.claude-secondary | 0503d474 | chrisren | 2026-08-04 10:17:07 | 2026-10-25 07:18:48 |
| next3 | ~/.claude-tertiary | 6a49a3e4 | chrisren | 2026-10-11 22:33:24 | 2026-10-25 06:39:46 |
| next4 | ~/.claude-quaternary | 136fa815 | chrisren | 2026-06-25 19:39:04 | 2026-10-25 06:53:55 |
| (dup) | ~/.claude-quaternary | 136fa815 | **unknown** | 2026-09-11 23:13:48 | 2026-09-11 23:14:01 |
| ~/.claude (explicit CLAUDE_CONFIG_DIR) | ~/.claude | 7b461744 | chrisren | 2026-04-15 | 2026-09-24 15:49:19 |
| unset CLAUDE_CONFIG_DIR | (default) | (none) | chrisren | 2026-03-24 | 2026-10-10 22:37:15 |
| unset (dup) | (default) | (none) | unknown | 2026-09-09 | 2026-09-09 |
| 27 others (35 - 8 attributed above, counted by hand from the kc.py listing) | probe/scratch dirs (no match among ~/.claude-*, ~/.claude-NNN version dirs, ~/.claude-next4) | various | chrisren | 2026-06-10 .. 2026-10-04 | mdat equals cdat (within 1 s) for all but `1a7eb3a0` (+8 h) and `c6a8dd0d` (+9 s): never refreshed |

- The cdat/mdat of the four `chrisren` items match the `cdat`/`mdat` stored in local-state `items` exactly. The fingerprints below therefore describe the item contents as they are now: no write happened between the fingerprinting at 02:29 CDT and my dump.
- `~/.claude-next4` (created 2026-10-23 21:29) hashes to `2f6a5160`. No keychain item has that suffix, the dir has no `.credentials.json`, and its `.claude.json` has `oauthAccount=null`. It is not a credential store.
- The duplicate `136fa815`/acct=unknown item is documented in `bin/cc-relogin:446-455` (measured there 2026-09-16) as holding `{mcpOAuth}` only, with no `claudeAiOauth`. Its mdat has not moved since 2026-09-11. **I did not re-verify its contents (that would need `-w`).**

## 2. The four live grants are independent (measured: `python3 -I /tmp/mtam/G1/a.py`)

Source: local-state `items` (checked_at 1792913340 = 02:29:00 CDT, src=keychain for all four) and the cache rows (ts 02:31:50 CDT).

| account | email (accounts.json) | has_rt | access-token expiresAt (local) | refreshTokenExpiresAt (local) | auth |
|---|---|---|---|---|---|
| next  | <redacted: see accounts.json> | True | 2026-10-25 03:51:33 CDT | 2026-11-19 15:04 CST | ok |
| next2 | <redacted: see accounts.json> | True | 2026-10-25 07:01:04 CDT | 2026-10-31 06:33 CDT | ok |
| next3 | <redacted: see accounts.json> | True | 2026-10-25 04:02:37 CDT | 2026-11-19 19:28 CST | ok |
| next4 | <redacted: see accounts.json> | True | 2026-10-25 06:38:40 CDT | 2026-11-02 10:48 CST | ok |

Pairwise equality, over all 6 pairs:

- refresh-token fingerprint equal: **False for every pair** (local-state).
- access-token fingerprint equal: False for every pair.
- the cache `rt_fp` agrees with local-state `rt_fp` for each account: True for all four.
- `refreshTokenExpiresAt` is distinct for each account. A refresh does not extend that value (`bin/claude-accounts:35-38`: "A refresh grant renews the ACCESS token but does NOT extend the refresh token's expiry"), so four distinct values also mean four distinct grants.
- The rejected-grant ledger `~/.claude/logs/claude-accounts-lastgood-rejected.json` is `{}` (2 bytes, mtime 2026-10-24 12:07; measured with `ls -la`). No live refresh token is currently recorded as rejected.

**Conclusion: the four live stores hold four independent refresh-token grants, and no refresh token is shared between them.** One caveat: a sha256 prefix collision is not ruled out, but at 64 bits it is negligible.

The account each dir's credential belongs to comes from `oauthAccount`, which Claude Code (CC) writes from a profile fetch made with that dir's token (`profileFetchedAt`). Measured with `python3 -I /tmp/mtam/G1/oa.py`:

| dir | accountUuid | org type / tier | profileFetchedAt |
|---|---|---|---|
| ~/.claude-next | d5f84d93… | claude_max / default_claude_max_20x | 1792817922608 (about 26 h before 02:31) |
| ~/.claude-secondary | 76570e6e… | claude_max / max_20x | 1792906820311 (about 1.9 h) |
| ~/.claude-tertiary | d0955289… | claude_max / max_20x | 1792861653618 (about 14.4 h) |
| ~/.claude-quaternary | ac8c0b73… | claude_max / max_20x | 1792896591285 (about 4.7 h) |
| ~/.claude (.claude.json, mtime Oct 18) | d5f84d93-… (= next) | none recorded | none |
| ~/.claude.json (default, mtime Oct 10) | d5f84d93-… (= next) | claude_max / max_20x | 1786427179814 (2026-08-11) |

The four accountUuids and four orgUuids are distinct. `subscriptionType` and `scopes` of the live keychain blobs are **not observable** without `-w`. The org-level `organizationType=claude_max` and `organizationRateLimitTier=default_claude_max_20x` hold for all four.

## 3. `~/.claude-tertiary/.credentials.json` (measured: `python3 -I /tmp/mtam/G1/tf.py`)

- File: 1,923 bytes, mode 0600, mtime 2026-10-11 22:47. It is the only `.credentials.json` under any `~/.claude*` dir (`find /Users/chrisren -maxdepth 2 -name .credentials.json -path '*/.claude*'`).
- Top keys: `claudeAiOauth`, `mcpOAuth` (one server entry, `motion-plus|…`).
- `claudeAiOauth` keys: accessToken, expiresAt, rateLimitTier, refreshToken, refreshTokenExpiresAt, scopes, subscriptionType. It has no `tokenAccount` or `profile` field, so the file does not record which account it belongs to.
- `subscriptionType=max`, `rateLimitTier=default_claude_max_20x`.
- scopes: user:file_upload, user:inference, user:mcp_servers, user:plugins, user:profile, user:sessions:claude_code.
- `expiresAt` 2026-10-12 01:33:24 CDT, so the access token is long expired. `refreshTokenExpiresAt` is 2026-11-09 21:02 CST, so the grant's hard cliff has not passed.
- Refresh-token fingerprint equals a live store's: **False for all four accounts.** Access-token fingerprint equal: False for all four.
- Its refreshTokenExpiresAt (11-09) differs from next3's live grant (11-20). It is therefore a **different, older grant**. It is most likely next3's pre-relogin grant: next3's keychain item cdat is 2026-10-11 22:33Z, and the 2026-10-11 ~22:12Z next3 keychain-vanish incident is in `bin/claude-accounts:576-578`. The token was probably rotated away or superseded. I did not test whether it is still accepted, because testing needs an outbound call.

What this means for cleanup: the leftover file shares no refresh token with any live store, so deleting it cannot strand a live account. S14 §5 (lines 109-116) documents why it still matters. It pins tertiary's in-memory memo, because the `wA` stat succeeds. It is also a stale fallback that would be used, and would hit `invalid_grant`, if the keychain read ever returned null.

## 4. Is any account present in more than one store?

- **By refresh token, among the stores I could fingerprint** (the 4 live items and the tertiary file): no. Each account's live refresh token is in exactly one store.
- **By identity metadata: yes, account `next` (d5f84d93).** Three config dirs carry next's `oauthAccount`: ~/.claude-next, ~/.claude, and the default ~/.claude.json. Two further keychain items correspond to the latter two dirs: `7b461744` (mdat 2026-09-24) and the unsuffixed `Claude Code-credentials`/chrisren (mdat 2026-10-10). Their contents are **unverified** because reading them needs `-w`. Their mdat values predate next's live item (cdat 2026-10-21, refreshTokenExpiresAt 11-19), so whatever they hold is an older grant or an already-rotated refresh token. It cannot equal next's current refresh token: a refresh token that rotated after 10-10 is not the one in an item last written on 10-10. Refresh tokens rotate (repo-measured: `docs/research/scaling-bottlenecks-2026-08-09/08-platform-terms.md:80`, "`next` rt `0023ef9690b1 → a9f8aadf29eb` across one grant"). CC's refresh code keeps the old refresh token only if the server omits a new one (`refresh_token:G=e`, cc293-src.js offset 4,700,476).
- The 27 orphan probe items were never refreshed (mdat equals cdat, apart from `1a7eb3a0` at +8 h and `c6a8dd0d` at +9 s). Any real-account refresh token copied into them would have been rotated out long ago. Their contents are unverified.
- The repo already flags one residual risk for these stale stores (`docs/research/token-efficiency…` fixture text, not a measurement of Anthropic): replaying a rotated refresh token could revoke the whole token family. That would happen only if some process launched against `~/.claude` or with CLAUDE_CONFIG_DIR unset tried to refresh. I found no evidence either way that such reuse detection exists at Anthropic's token endpoint.

## 5. What this decides for the design

- A **keychain-swap move**, meaning "write account B's live blob into store D", **creates** sharing that does not exist today. Today every account has exactly one live refresh-token holder. After a copy, two stores hold B's refresh token. Their `.oauth_refresh.lock` files are per-dir, so the two refreshers do not serialize. The first refresh rotates the token, the other store gets `invalid_grant`, and `jhr` clears that store's credential. Repo-measured transients consistent with this: "access token has been revoked" 7 s after an item's mdat moved (`docs/plans/MASTER_ACCOUNT_FACTS.md:117-124`). So a copy-swap is self-destructive. That follows from the independence measured here combined with rotation.
- A swap is safe only if account B's grant ends up with **exactly one** live holder. Three ways to get there:
  - (a) Move it instead of copying it, so the source store no longer refreshes it. That logs out every other session on B's dir.
  - (b) Give the moved session a **separate grant** for B, from a second `/login` or `setup-token`, so B holds more than one grant at once. This is not yet measured: E1 was never run (`MASTER_ACCOUNT_FACTS.md:112`).
  - (c) Give the moved session a **non-refreshable** credential (no refreshToken), as S14 §7 proposes.
- Leftover-file cleanup: `~/.claude-tertiary/.credentials.json` is the only plaintext store, and it shares no live refresh token. The cleanup list is complete for plaintext files. It is **not** complete for keychain items: `7b461744`, the two unsuffixed items, the `136fa815`/unknown duplicate and 27 probe items remain, all with unverified contents.

## 6. Commands run (key output)

1. `ls` of the notes dir; read S02 and grep of S14 (context).
2. `git grep` of scripts/bin for keychain handling. Found `bin/claude-accounts` fingerprint persistence.
3. `sed -n` over `bin/claude-accounts` lines 240-300, 505-680, 2186-2290, 7900-8100 and 28-48.
4. `python3 -I /tmp/mtam/G1/a.py`: the tables in §2. Every pairwise rt/at equality was False.
5. `ls -lad ~/.claude*`; `find … -name .credentials.json`: only the tertiary file. `~/.claude-next4` holds just .claude.json, backups, projects and sessions.
6. `timeout 60 python3 -I /tmp/mtam/G1/kc.py` (`security dump-keychain`, attributes only): rc 0, 785,184 bytes, 35 Claude items (§1).
7. `python3 -I /tmp/mtam/G1/h.py`: suffix map (§1).
8. `python3 -I /tmp/mtam/G1/oa.py` and `oa2.py`: oauthAccount identity and tiers (§2).
9. `python3 -I /tmp/mtam/G1/tf.py`: tertiary file structure and equality booleans (§3).
10. `python3 -I /tmp/mtam/G1/g.py 'refresh_token_expires_in' 400 6`: refresh code at offset 4,700,476 (`refresh_token:G=e`) and `formatTokens` at 23,637,260. `formatTokens` builds a `tokenAccount` field that the Oct 11 file does not have.
11. `git grep` of docs for rotation evidence (§4) and the E1 verdict (§5).

## 7. Open

- What the live keychain blobs record for `subscriptionType` and `scopes`, and whether they carry `tokenAccount`. Answering needs a `-w` read, done by the operator or by a slot permitted to read secrets and print only structure.
- What `7b461744`, the two unsuffixed items and `136fa815`/unknown hold now, and whether any running process uses them (CLAUDE_CONFIG_DIR=~/.claude or unset).
- Whether Anthropic's token endpoint allows several concurrent grants per account (the E1 question), and whether it revokes a token family when a rotated refresh token is replayed.
