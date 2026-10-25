# G2-org-identity-from-disk: are next/next2/next3/next4 four organizations?

Slot: G2-org-identity-from-disk. Date: 2026-10-25 (~02:50 CDT). Method: disk reads only. No keychain call,
no live probe, no pane interaction. Scripts are in `/tmp/mtam/G2-org-identity-from-disk/`. Emails are
masked in this file (the `organizationName` values embed the account email; the masked form is kept).

## Answer

**There are four distinct organizations. No two accounts share an `organizationUuid`.** Each account is the
sole `admin` of its own personal `claude_max` org: `organizationType=claude_max`,
`organizationRateLimitTier=default_claude_max_20x`, `billingType=stripe_subscription`, and
`hasExtraUsageEnabled=False` on all four. The name→dir mapping comes from `~/.claude/accounts.json`. The
org fields come from each dir's `.claude.json` `oauthAccount`:

| account | config dir | sha256(dir)[:8] | accountUuid | organizationUuid | organizationName (masked) | role | type / tier | accountCreatedAt | subscriptionCreatedAt | profileFetchedAt (ms) |
|---|---|---|---|---|---|---|---|---|---|---|
| next  | ~/.claude-next       | 2be71cf3 | d5f84d93… | **260ebc56…** | "ich…<redacted: see accounts.json>'s Organization" | admin | claude_max / default_claude_max_20x | 2024-09-25 | 2025-04-10 | 1792817922608 |
| next2 | ~/.claude-secondary  | 0503d474 | 76570e6e… | **fb09ef51…** | "chr…<redacted: see accounts.json>'s Organization" | admin | claude_max / default_claude_max_20x | 2026-01-14 | 2026-01-14 | 1792906820311 |
| next3 | ~/.claude-tertiary   | 6a49a3e4 | d0955289… | **1a71eca0…** | "ren…<redacted: see accounts.json>'s Organization" | admin | claude_max / default_claude_max_20x | 2026-06-11 | 2026-06-11 | 1792861653618 |
| next4 | ~/.claude-quaternary | 136fa815 | ac8c0b73… | **c570be13…** | "chr…@outlook.com's Organization" | admin | claude_max / default_claude_max_20x | 2026-06-25 | 2026-06-25 | 1792896591285 |

`seatTier`, `userRateLimitTier` and `workspaceRole` are `None` for all four. The four `organizationName` strings
embed four different emails. Each one is the default "<email>'s Organization" name that a personal
consumer org gets, so none of these is a Team or Enterprise seat inside a shared org.

There are two other records, and neither is a fifth account. Both are copies of `next`:
- `~/.claude/.claude.json` (mtime 2026-10-18): accountUuid d5f84d93…, org 260ebc56… (= next). This is an
  older schema with no `organizationType`/`organizationRateLimitTier`/`profileFetchedAt` and with
  `hasExtraUsageEnabled=True`, unlike next's current `False`. It is stale.
- `~/.claude.json` (mtime 2026-10-10): accountUuid d5f84d93…, org 260ebc56… (= next). Its profileFetchedAt is
  1786427179814 (2026-08-11).

## Cross-check against the claude-accounts state file

`~/.claude/logs/claude-accounts-lastgood.local-state.json` (1,259 bytes, mtime 02:51) was walked with
values redacted by key name. **It has no org or account-uuid field**, so it cannot confirm the
organizationUuid mapping directly. It does show:
- `items.{next,next2,next3,next4}` all `present=True, src='keychain', has_creds=True, has_rt=True`.
- Four distinct refresh-token fingerprints (`rt_fp`: 07206aa4…, cf5e74ef…, 4fba4c79…, 242ee0a8…) and four
  distinct access-token fingerprints (`at_fp`). That means four independent grants, which matches G1.
- The keychain item `cdat` for next4 is `20260625193904Z`. That is 3 min 16 s after next4's
  `accountCreatedAt` (2026-06-25T19:35:47Z) and 1 min 23 s after its `subscriptionCreatedAt`
  (19:37:41Z). The creation dates of the keychain item and the account line up. The `cdat` values for
  next2 (2026-08-04), next3 (2026-10-11) and next (2026-10-21) are later than their account creation, so
  those items were re-created at re-logins and do not cross-check.
- `kc_ident = [2326293788, 1792913784307410000]`. bin/claude-accounts:7996-8001 defines `_kc_ident()` as
  `[st_ino, st_mtime_ns]` of the login keychain DB. It identifies the keychain file, not an account.
  `stat ~/Library/Keychains/login.keychain-db` now gives inode 2326631956 and mtime 1792914696, so the
  DB file has been rewritten since `last_attr_check`. That is expected churn and has nothing to do with
  org identity.

## Corroboration from earlier repo research (read-only `git grep`)

- `docs/research/sonnet55-utilization-2026-09-28/notes/harness-hazards-a.md:110`: "Our accounts are 4
  distinct organizations … secondary `fb09ef51`, tertiary `1a71eca0`, quaternary `c570be13`, next `260ebc56`".
  These are the same four prefixes I read today.
- `docs/research/cloud-post-eval-2026-10-06/d2-terms-primary.md:70`: hashed accountUuid/organizationUuid/
  emailAddress were "4 distinct each".
- `docs/research/cloud-lane-redesign-2026-09-10/C1-quota-pool.md:24`: "Four distinct `organizationUuid`s
  verified, so the accounts are genuinely separate meters". The per-account replication there showed
  independent quota draw.
- Correction to the brief: `notes/G1-credential-store-topology.md:70` does say "The four accountUuids and four
  orgUuids are distinct". G1 asserted it but did not tabulate the values. This slot tabulates them.

## Implications for downstream slots

- The premise holds. The quota meter is per-org on consumer Max (organizationRateLimitTier is an org
  field), and these are four separate orgs. Moving a session to next4 really moves its spend onto a
  different meter. The earlier C1-quota-pool measurement supports separate meters empirically.
- Every cross-org penalty still applies: prompt-cache rebuild (S05/S09), message-thread 404+replay
  (S09), and the thinking-block-signature drop (S09). Caches and signatures are org-scoped, and any
  move here is always a cross-org move.
- A stale `account_uuid` in `metadata.user_id` next to a new bearer (S01/S03/G4) is a genuine
  cross-account and cross-org mismatch, not a benign intra-org one. Its consequences have to be
  assessed and cannot be assumed away.
- One side note for G4/S09 (#41886, "oauthAccount leaked across CLAUDE_CONFIG_DIRs"): today, each of the
  four dirs holds its own org record. Only the two non-account files (`~/.claude/.claude.json`,
  `~/.claude.json`) hold next's identity, and they are stale.

## Caveats

- These are **cached profile snapshots** (`profileFetchedAt` is between ~1.9 h and ~26 h old). They are not a
  live server read. An org cannot change its UUID, and an account moving between orgs would be unusual for
  consumer Max. Even so, this read cannot exclude a server-side change after `profileFetchedAt`.
- Disk evidence cannot tell whether Anthropic pools anything across the operator's orgs (for example a
  per-person or per-payment-method limit). The org records show no linkage. Pooling is ruled out only
  to the extent of the earlier C1 replication measurement.
- I did not verify that each dir's keychain token actually authenticates as the org recorded in its
  `.claude.json`. That would need `-w` or a live call, and both are forbidden. The four distinct rt_fp and the
  next4 cdat/accountCreatedAt alignment are consistent with it.

## Commands run (all read-only, each under `timeout`)

1. `mkdir -p /tmp/mtam/G2-org-identity-from-disk`, then `ls` of rules/notes and `ls -la` of the six
   `.claude.json` files and the state file. Sizes: next 327,471 B, secondary 410,274, tertiary 403,090,
   quaternary 342,830, ~/.claude 60,433, ~/.claude.json 132,605, state 1,259. None is a symlink.
2. `timeout 60 python3 -I /tmp/mtam/G2-org-identity-from-disk/read_org.py`: loads each `.claude.json` and
   prints `oauthAccount` keys and values (key names matching token/secret/refresh redacted, email masked),
   plus `sha256(configdir)[:8]`. Output is the table above.
3. `timeout 60 python3 -I /tmp/mtam/G2-org-identity-from-disk/read_state.py`: walks the state file and
   redacts any key matching token/secret/refresh/access. Output is summarised in the cross-check section.
4. `stat -f '%i %m %N' ~/Library/Keychains/login.keychain-db` → `2326631956 1792914696`. Also
   `git grep -n kc_ident` and `git grep -nE 'organizationUuid|…'`. I read bin/claude-accounts:7990-8012
   and G1 notes lines 60-75.
5. `python3 -I` over `~/.claude/accounts.json` `accounts[]` (scalar non-secret fields only): next→~/.claude-next,
   next2→~/.claude-secondary, next3→~/.claude-tertiary, next4→~/.claude-quaternary.
