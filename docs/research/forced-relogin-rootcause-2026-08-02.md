<!-- Persisted from a session scratchpad 2026-08-02. The instrument referenced throughout is
     committed alongside this doc at tools/auth/auth-timeseries.sh — the original lived in a
     session-scoped scratchpad that does not survive the session. Backlog items 8af0d2e65920,
     69cff24e0ec7, 23eccae755a9, bbad96d163ab and 0fa7d7512a3c reference this investigation. -->

# Forced re-authentication — root cause, per account

> ## ✅ ROOT CAUSE FOUND AND FIXED — 2026-08-02T20:1xZ
>
> **`.oauth_refresh.lock` was a DANGLING SYMLINK in all four account config dirs**, pointing at
> `~/.claude/.oauth_refresh.lock`, which does not exist. Claude Code's in-session token refresh
> must take that lock first; on a dangling symlink proper-lockfile gets `mkdir`→EEXIST and
> `stat`→ENOENT and concludes **ELOCKED, permanently** (the staleness check can never read an
> mtime, so it can never age the lock out). The refresh therefore returned `lock_timeout`
> **before it ever requested a token**, and the 8h access token simply ran out — every time.
>
> Verified three independent ways: the dangling links on disk; the OS-level probe reproducing
> EEXIST/ENOENT then `mkdir`→OK after removal; and the erase-site offset in the 2.1.220 binary
> sitting inside the *locked* refresh function.
>
> **Why it felt like "logged out whenever I'm working."** `claude-accounts`' `heal()` bypasses the
> lock entirely — but refuses to run while an account has live sessions. So an account died while
> being USED and was quietly rescued while IDLE. Your own tooling was the only thing keeping the
> fleet logged in.
>
> **Origin — and the Aug-1 trigger the git archaeology could not find.** `lib/config-mirror.zsh`
> shares everything in `~/.claude` not on an isolate list, on the header's premise that *"Auth is
> NOT here — it lives in the macOS Keychain."* The credential is; the lock guarding its refresh is
> a file in the config dir. The mirror caught the lock during the instant it existed and symlinked
> it four ways — symlinks born **2026-07-31 14:58:12 / 15:13:45 / 16:11:07 / 16:36:18**, first
> forced `/login` at **17:46 local**, seventy minutes after the last. It was never a commit; it was
> a runtime race, which is why no commit at that boundary touched auth.
>
> **Fixed:** four dangling symlinks removed (immediate); `fix(config-mirror)` landed as
> **`1677218f`** on origin/main — never share `*.lock`/`*.lock.d`/`*.pid`/`*.sock`, and reap
> symlinks into `~/.claude` whose target has vanished (the share loop only walks names that still
> exist in `$src`, so an already-dangling link was unreachable by every existing code path).
> 4 tests, RED-proved. Live layer content-verified identical to trunk.
>
> **CONTROL ARM FIRED 2026-08-02T22:06:02Z — and it does NOT verify the fix.** `next` and `next2`
> (both **zero** live sessions) got new access AND refresh tokens one minute after their 22:04:45 /
> 22:04:57 expiry. The discriminator says this was `heal()`, not an in-session refresh:
> `heal next: OK` at 22:05:12Z and `heal next2: OK` at 22:05:29Z in `claude-accounts.log`. Exactly
> what the control was designed to show — heal covers an IDLE account — so it is not evidence about
> the lock. Recorded rather than banked.
>
> **It did settle one thing that was inference all session: REFRESH TOKENS ROTATE.**
> `next` rt `0023ef9690b1 → a9f8aadf29eb`, `next2` rt `26fc87c99eba → 87163b4d1b78` across a single
> grant. So the C2 rotation premise is now measured, not cited — which is what makes a *shared*
> credential across N concurrent sessions genuinely hazardous, and why collapsing `next` to one
> grant matters independently of the lock.
>
> **Still to verify by effect:** next3/next4 access tokens expire 02:31Z/02:33Z with live sessions.
> A new access-token hash recorded *before* expiry = a successful in-session refresh, which has not
> happened on this machine since Jul 31. Instrument + watcher are armed.
>
> Everything below was written before the root cause was found. Corrections that supersede it:
>
> * the credential-erase path is real but only ever reached `~/.claude` — the one dir whose lock
>   worked. Your four accounts were never erased; they simply could never refresh.
> * **2.1.220 is exonerated.** The version comparison that indicted it confounded build with
>   calendar; controlled to the window where both ran, 220 is *better* (0.126 vs 0.184 err/session).
> * **`setup-token` — sharper than "it never ran".** No token was ever produced or wired (no
>   `~/.claude/oauth-tokens/`, no env var, no launcher patch) — that stands. But it *did* write a
>   credential: `mint()` calls `$BIN setup-token`, the RAW binary, bypassing the `claude()` zsh
>   function that is the only thing exporting `CLAUDE_CONFIG_DIR`. Unset ⇒ the **unsuffixed**
>   keychain item, written 2026-08-01T06:46:00Z. The operator's "we dont get a key" at 06:46:25 is
>   what a normal login write looks like, not a mint. [INFERRED on the final link — the bypass
>   mechanism and the second-level timing coincidence, not a logged execution.]
> * **The orphan `1a7eb3a0` is `~/.cc-firewall`** — not deleted, still on disk, `.claude.json`
>   carrying `accountUuid d5f84d93` = account **next**. So `next` holds FOUR independent credential
>   stores (`.claude-next`, unsuffixed, `~/.claude` erased, `~/.cc-firewall`), one of them outside
>   `accounts.json` entirely. Strengthens the collapse-to-one-grant recommendation below.
> * **Keychain naming, from the binary:** the suffix is gated on whether `CLAUDE_CONFIG_DIR` is
>   *set*, not on its value (`!process.env.CLAUDE_CONFIG_DIR`), and the hash input is the RAW env
>   string — no realpath, no trailing-slash strip. So `~/.claude`, `/Users/chrisren/.claude` and a
>   trailing slash are three different credentials, and setting it explicitly to the default path
>   still splits you off the unsuffixed item. Proactive refresh margin is exactly 300000 ms.
> * **12 genuine `/login` events is a ceiling, not just a floor** — `.claude-156/161/170/183/219/220`
>   hold zero transcripts.

Investigation 2026-08-02. All figures measured on this machine unless marked otherwise.

## The answer in one paragraph

The ~30-day cadence you remember is the **refresh-token calendar cliff**
(`refreshTokenExpiresAt`), and it is **healthy on all four accounts — 27–29 days out**.
It is not what is biting you. What bites you is the **8-hour access-token TTL** combined
with a Claude Code behaviour confirmed in the 2.1.220 binary: **on a single `invalid_grant`
response to a refresh grant, the CLI erases the stored credential** — it writes
`{accessToken:"", refreshToken:"", expiresAt:0}` into the Keychain. An erased credential
cannot be repaired by any automation you own (`heal()` needs a refresh token and returns
*"skipped: no refresh token in keychain"*), so **only an interactive `/login` recovers it**.
The 30-day cliff is therefore only a *floor*: any transient refresh failure, at any 8-hour
boundary, produces exactly the same outcome as hitting the cliff.

And the fix you thought was deployed — `claude setup-token` for a 1-year token — **was never
deployed at all**. Zero tokens were ever minted.

## Evidence

### 1. Access-token TTL is exactly 8h (5 independent samples)

Keychain item `mdat` (write time) vs the `expiresAt` in its payload:

| item | config dir | written | expiresAt | delta |
|---|---|---|---|---|
| `…-2be71cf3` | `.claude-next` (next) | 2026-08-02T14:04:45Z | 22:04:45Z | 8h 00m |
| `…-0503d474` | `.claude-secondary` (next2) | 2026-08-02T14:04:58Z | 22:04:57Z | 8h 00m |
| `…-136fa815` | `.claude-quaternary` (next4) | 2026-08-02T18:33:07Z | 2026-08-03T02:33:06Z | 8h 00m |
| `…-1a7eb3a0` | *(orphan, no live dir)* | 2026-06-11T07:46:55Z | 15:46:55Z | 8h 00m |
| `Claude Code-credentials` | *(unsuffixed)* | 2026-08-01T06:46:00Z | 14:46:00Z | 8h 00m |

Your "every 6 hours or so" is this 8-hour boundary.

### 2. The calendar cliff is NOT the problem

`refreshTokenExpiresAt`, all four accounts, measured 2026-08-02T19:02Z:

| account | cliff | away |
|---|---|---|
| next | 2026-08-30T15:03Z | 27d 20h |
| next2 | 2026-08-31T17:10Z | 28d 22h |
| next3 | 2026-08-30T17:19Z | 27d 22h |
| next4 | 2026-08-30T15:36Z | 27d 20h |

Because the cliff anchors to the **last interactive login** and is *not* extended by a refresh,
these dates prove a negative. All four cliffs fall in a 26-hour band (Aug 30 15:03 → Aug 31 17:10).
Had you re-authenticated ~8 times over the last three days, the cliffs would be spread across
those three days and end near today; instead the most recent maps to **~26 hours ago**. That
inference needs only that the cliff period is *constant* — not that it is exactly 30 days.

**So whatever you have been re-authenticating every ~6 hours, it was not these four accounts'
Keychain credentials.** Two other credential surfaces on this machine ARE erased and would prompt:
`~/.claude` (§4, erased today 06:42:30Z) and the unsuffixed `Claude Code-credentials` item (access
token expired 2026-08-01T14:46Z, never renewed since). **The one fact I cannot read off disk is
which command you run when the prompt appears** — that pins which surface.

### 3. The erase, quoted from the 2.1.220 binary

`~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe`:

```js
if(bst(d)&&c){                                    // d = invalid_grant response
  Sno.add(c), M("tengu_oauth_refresh_token_marked_dead_invalid_grant",{});
  let m = await zs().mutate((g)=>{
    let _ = g.claudeAiOauth;
    if(!_ || _.refreshToken!==c) return g;         // CAS — don't clobber a sibling's newer token
    return {...g, claudeAiOauth:{..._, refreshToken:"", accessToken:"", expiresAt:0}};
  });
  if(f&&m.success) M("tengu_oauth_refresh_token_cleared_on_disk",{});
}
return bst(d) ? "known_dead_refresh_token" : "refresh_failed";
```

A live instance of the result — `Claude Code-credentials-7b461744` (= `~/.claude`), right now:

```json
{"claudeAiOauth":{"accessToken":"","refreshToken":"","expiresAt":0,
  "scopes":[...5 scopes retained...],"subscriptionType":"max","rateLimitTier":"default_claude_max_20x"}}
```

Tokens blanked, metadata retained — the exact signature of that mutate. `mdat` = 2026-08-02T06:42:30Z.

### 4. `~/.claude` is logged out RIGHT NOW, and a launcher still points at it

`claude-prev` (bare, no `CLAUDE_CONFIG_DIR`) resolves `local _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"`
— i.e. the erased credential above. Every bare `claude-prev` launch is a `/login` prompt.
`claude-prev2/3/4` are fine (they pin their own dirs).

### 5. The setup-token fix was never deployed

- `~/.claude/oauth-tokens/` **does not exist** — and both `mint()` and `save()` create it with
  `mkdir -p -m 700` before writing, so its absence proves no token was ever stored.
- `grep -c CLAUDE_CODE_OAUTH_TOKEN ~/.zshrc` → **0**. The step-4 launcher patch was never applied.
- `env | grep -c CLAUDE_CODE_OAUTH_TOKEN` → **0**.
- The 2026-08-01 06:42–06:50 attempts all ran through the agent's `!` prefix, which redirects
  stdin; `setup-token` is an Ink TUI and requires a real TTY, so every attempt was refused by the
  script's own guard or killed by pid. Step 2 then aborted with *"no canary token — run step1 first"*.

This is why it kept being reported "resolved": nothing was ever actually in effect.

### 6. Historical hard logouts are already in your logs

`heal <acct>: FAIL — Login failed: Request failed with status code 400` = `invalid_grant`.

| account | burst | count |
|---|---|---|
| next2 | 2026-07-13T15:36 | 1 |
| next2 | 2026-07-19T10:11 → 11:13 | 11 consecutive |
| next3 | 2026-07-24T17:29 → 2026-07-25T01:11 | 24 consecutive |
| next2 | 2026-07-28T15:00 | 1 |

next3 was down from Jul 24 17:29 until its next success on Jul 28 14:59 — roughly four days.
**Open question with the audit agent:** whether each of those FAILs also *erased* the credential
(if `claude auth login` shares the clear path), which would make a 24-attempt retry burst
actively destructive rather than merely futile.

## What is NOT the cause (ruled out with evidence)

- **The 30-day cliff.** 27–29 days out on all four. §2.
- **`setup-token` having broken something.** It never ran to completion. §5.
- **A stray `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY`.** Not set anywhere — env, `~/.zshrc`,
  settings files, or plists.
- **Our own `heal()` racing live sessions.** `heal()` refuses when the account has live sessions,
  and re-checks under its lock. It is *designed* rotation-safe.
- **The naive N-concurrent-sessions rotation race.** 2.1.220 ships real hardening against it:
  a single-flight lock with `isCompromised()`, a compare-and-swap on the stored refresh token
  (`tengu_oauth_refresh_compromised_cas_adopted_sibling` / `..._cas_saved`), and 401-recovery by
  re-reading a sibling's newer token from disk (`tengu_oauth_401_recovered_from_disk`).

## One real defect found in our own tooling

`concurrency()` in `bin/claude-accounts` matches argv[0] against
`t0=="claude" or t0.endswith("/claude") or "cli.js" in t0`. The native binary is **`claude.exe`**,
so any session launched by its real path is **invisible** to the rotation-safety gate. Measured
live: next3 showed **10 sessions to the gate, 15 actually running — 5 invisible**. The gate fires
only at a count of 0, so this is a live path to healing an account that is not actually idle.
(Present since 2.1.156 / May, so it is not the recent regression — but it is real.)

**Which sessions are invisible is the sharp part.** Interactive sessions launched through the
`claude` shell function exec `~/.claude-220/node_modules/.bin/claude` — a symlink whose path ends
in `/claude`, so the matcher sees them. **Subagents and teammates are spawned with argv[0] set to
the resolved real path**, `…/bin/claude.exe`, and the matcher misses every one. Verified on this
session's own five research agents:

```
7325  env-audit          …/bin/claude.exe --agent-id env-audit@session-625efe2a  …
13385 cli-internals       …/bin/claude.exe --agent-id cli-internals@…            …
22008 timeline-forensics  …/bin/claude.exe --agent-id timeline-forensics@…       …
31335 heal-race-audit     …/bin/claude.exe --agent-id heal-race-audit@…          …
39282 vendor-research     …/bin/claude.exe --agent-id vendor-research@…          …
```

All five run on `.claude-tertiary` (next3) and all five are invisible to the gate. So the counter
is blind **exactly** to the population that makes an account busy — agent teams and research
waves — which is precisely the case the rotation-safety gate exists to protect. An account
running nothing but a research wave reads as *idle*.

## Live experiment running

`auth-timeseries.sh` samples all 6 credential items every 60s, recording sha256-prefixes of the
access and refresh tokens (never the values), plus a correct per-credential live-session count.
It is a natural A/B:

| account | live sessions | access token expires | what it tests |
|---|---|---|---|
| next | 0 | 2026-08-02T22:04:45Z | **control** — nothing should refresh it; expect stale, not erased |
| next2 | 0 | 2026-08-02T22:04:57Z | **control** |
| next3 | 15 | 2026-08-03T02:31:39Z | **test** — does in-session refresh succeed, or erase? |
| next4 | 3 | 2026-08-03T02:33:06Z | **test** |

A changed refresh-token hash proves rotation. A `state=EMPTY` transition catches the erase live.
This is the instrument backlog item `f272b30e66f5` says does not exist ("No instrument records a
forced logout").

## UPDATE — the forced-relogin rate, actually measured

I said earlier that no instrument records a forced logout. **That was wrong**, and so was a prior
session's "36 forced re-logins": every `/login` you type is recorded in the transcript as a
`type:"user"` record whose content *starts with* `<command-name>/login</command-name>`.

Both wrong counts came from the same trap: the string `<command-name>/login</command-name>`
also appears **inside our own investigation's grep commands**, which are themselves recorded.
Filtering on the string alone counts the investigation. The correct filter requires
`type=="user"` **and** `message.content` to be a *string* that starts with the tag (tool traffic
carries content as a *list*), then dedupes by `uuid` — necessary because
**`.claude-next/projects` is a symlink to `.claude/projects`** (verified: same inode), so those
two dirs are one store and a naive count double-reports every event.

**Result: 12 genuine `/login` events, ever.** Grouped into incidents (three `/login`s 18 seconds
apart is one incident, not three), over the last 30 days:

| account | credential stores | incidents |
|---|---|---|
| **next** (ichris96) | **2–3** | **4** — Jul 3, Jul 31 17:24, Jul 31 23:36, Aug 2 05:55 |
| next3 (ren.chris) | 1 | 2 — Jul 10, Aug 2 18:30 |
| next2 (chris.swe) | 1 | 2 — Jul 10, Jul 28 15:24 |
| next4 (chris.claudecode) | 1 | **0** |

Two caveats, stated plainly:
- **~8 incidents in 30 days ≈ one per 3.75 days — this is not "every 6 hours."** The closest
  real match to that description is the **Jul 31 17:24 → 23:36 gap of +6.21h**, on `next`.
- This instrument only sees `/login` typed **inside a running session**. A re-auth performed at a
  fresh shell before any transcript exists would not appear. So 12 is a **floor, not a ceiling**.

### The strongest correlate: `next` is the only account with multiple grants

```
Claude Code-credentials            GRANT rt=ed24d0510b   unsuffixed
Claude Code-credentials-7b461744   EMPTY (erased)        ~/.claude
Claude Code-credentials-2be71cf3   GRANT rt=0023ef9690   ~/.claude-next
Claude Code-credentials-1a7eb3a0   GRANT rt=0ec16821e6   orphan — no live config dir
```

`~/.claude`, `~/.claude.json` and `~/.claude-next` **all carry `accountUuid d5f84d93`** — one
Anthropic account, two-to-three independent OAuth grants. Every other account has exactly one
store, and **next4 — one store — has had zero forced re-logins in 30 days.**

This is the repo's open **E1** question ("do concurrent same-account logins coexist?") showing up
as production evidence rather than a probe result.

### A correction that narrows the blast radius

The heal FAIL bursts (next2 Jul 19, 11 consecutive; next3 Jul 24–25, 24 consecutive) were **not**
caused by the erase path, and this is provable from their own shape: if the child binary had
erased the credential on the first `invalid_grant`, the *second* heal would have logged
`skipped: no refresh token in keychain` — not another `FAIL 400`. Eleven and twenty-four
consecutive 400s mean a token was **present and being rejected** every time.

So **`claude auth login` with `CLAUDE_CODE_OAUTH_REFRESH_TOKEN` does not appear to take the
clear-on-invalid_grant path.** The erase is an **in-session** behaviour — which matches your own
report that the prompt appears mid-work, and it means your own `heal()` has not been destroying
credentials. What those bursts *do* show is a retry ladder hammering a grant the server had
already rejected 24 times in a row.

## UPDATE 2 — the "every 6 hours" reconciled, with the denominator controlled

Typing `/login` (12 times ever) and *being told to* `/login` are different events, and the second
is the one you experience. Counting harness-authored errors only — `isApiErrorMessage:true` AND
the auth string inside the error text — gives **74 events**, and the message is always:

> `Please run /login · API Error: 401 OAuth access token has expired. Re-authenticate to continue.`

| day | sessions | auth errors | errors/session |
|---|---|---|---|
| 2026-07-25 | 190 | 4 | 0.021 |
| 2026-07-26 | 123 | 1 | 0.008 |
| 2026-07-27 | 61 | 0 | 0.000 |
| 2026-07-28 | 22 | 1 | 0.045 |
| 2026-07-29 | 101 | 0 | 0.000 |
| 2026-07-30 | 270 | **0** | 0.000 |
| 2026-07-31 | 171 | 2 | 0.012 |
| **2026-08-01** | 182 | **18** | **0.099** |
| **2026-08-02** | 74 | **18** | **0.243** |

**This is a real ~20× regression, not more sessions**: Jul 30 ran 270 sessions with zero auth
errors; Aug 2 ran 74 with eighteen.

**Why it feels like every 6 hours.** On Aug 2 the errors arrive in clusters — 04:51–06:42, then
14:04–14:27, then 15:51–18:01. The 05:49 → 14:04 spacing is **8h15m**: the access-token TTL. And
because 11–15 sessions share one credential, a single expiry throws the prompt in **six or seven
panes at once**. One 8-hourly event, multiplied by your session count, reads as constant.

### It is NOT a client-version regression, and 2.1.220 is NOT implicated

The regression **began 2026-08-01T00:46Z on 2.1.219**, about 11.5 hours before 2.1.220 was
installed (Aug 1 12:15Z). Twelve of the thirteen pre-install errors are 2.1.219 — a build running
since Jul 24 that produced zero errors across 270 sessions on Jul 30.

**A correction to my own first pass.** Pooling all sessions since Jul 25 gave 2.1.219 = 0.028 and
2.1.220 = 0.096 err/session, which reads as "220 is 3.4× worse." **That comparison is invalid**:
2.1.220 only ever existed *during* the bad period, while 2.1.219's denominator includes the clean
days before it. The versions were being compared across different time windows, so the ratio
measured the calendar, not the build.

Controlled to the window where **both** versions actually ran (sessions starting after
2026-08-01T12:15Z):

| version | sessions | auth errors | errors/session |
|---|---|---|---|
| 2.1.219 | 49 | 9 | **0.184** |
| 2.1.220 | 119 | 15 | **0.126** |

**Ratio 220/219 = 0.69× — 2.1.220 is slightly *better*, not worse.** Rolling back to 2.1.219
would not help and would probably hurt. The version axis is exonerated; whatever changed on
Aug 1 is not the client build.

### What I could NOT determine — stated rather than guessed

**The trigger for the 2026-08-01T00:46Z onset is unresolved.** I checked the repo's commits
across that boundary: they are nightly-regression, hermeticity-lint and kitty work — nothing
touching auth, launchers, config dirs, or the credential path. The launcher consolidation
(`23551b01`) landed 2026-08-01T20:29Z, *after* the onset. I am not going to name a cause I
cannot evidence. The strongest remaining candidates, both untested:
- a **server-side** change to refresh behaviour for these grants, and
- the same-account **multi-grant** condition on `next` (see above), which is the E1 question.

## What to do

### Highest-value fix, and it needs no setup-token at all: collapse `next` to ONE grant

`next` carries 2–3 independent OAuth grants; every other account carries one; the account with
one and only one (`next4`) has not been logged out once in 30 days. Collapsing `next` to a single
credential store is the cheapest change with the best evidence behind it, and it is independent
of the setup-token decision.

Three things create the duplication, all fixable:

1. **`~/.claude` is a second store for the same account.** Its credential is already erased, and
   bare `claude-prev` still resolves `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` to it. Either repoint
   `claude-prev` at `~/.claude-next` (one line), or give `~/.claude` an account of its own.
2. **The unsuffixed `Claude Code-credentials` item** holds a live grant that no config dir maps
   to — dormant since its access token expired 2026-08-01T14:46Z and was never renewed.
3. **`Claude Code-credentials-1a7eb3a0`** is an orphan: created 2026-06-10, no config dir hashes
   to it, and it predates next3's account creation so it is not next3's.

Removing (2) and (3) deletes keychain items — destructive and on the auth surface — so that is
your call, not mine. Note the sequencing risk: if same-account grants *do* evict each other
server-side, deleting a dormant grant is harmless, but **minting a new one is what would evict a
live one** — which is the real argument for doing the collapse *before* any setup-token work.

### The one thing that unblocks everything (operator, ~5 minutes, needs a real terminal tab)

`claude setup-token` is **structurally immune to this failure**, and not by luck: a
setup-token has no refresh token, so the binary's own code takes the
`if(!e.refreshToken||!e.expiresAt) return M("tengu_oauth_tokens_inference_only")` branch —
it is never persisted to the Keychain, never refreshed, and therefore **can never be erased
by the invalid_grant path**. It lasts a year.

The cost is real and is why this needs your call, not mine: a setup-token carries
**`user:inference` only** — 1 of the 5 scopes a normal login has. The binary states the
casualty outright: *"Remote Control requires a full-scope login token. Long-lived tokens
(from `claude setup-token` or CLAUDE_CODE_OAUTH_TOKEN) are limited to inference-only for
security reasons."* You lose Remote Control, claude.ai-hosted MCP connectors, and file
upload in any session that runs on one. `hasUsedRemoteControl: true` on next3 and
`hasRemoteEnvironment: true` on next4, so this is not hypothetical for you.

There is exactly one unanswered question that decides whether it is adoptable at all, and it
is **one curl**: does an inference-only bearer still get HTTP 200 from
`https://api.anthropic.com/api/oauth/usage`? That endpoint is the entire quota spine —
`/accounts`, the router, `limit-recover` and the desk all read it. 200 ⇒ adoptable. 401/403
⇒ adopting it fleet-wide blinds all of them, and the answer is no.

`/tmp/setup-token-4accounts.sh` already implements exactly this: `step1` mints one canary
token, `step2` runs that curl **with a full-scope positive control alongside it**, so a
failure is attributable rather than ambiguous. It has never been run to completion — the
attempts on 2026-08-01 all went through the agent's `!` prefix, which redirects stdin, and
`setup-token` is an Ink TUI that requires a real TTY.

### Two things that are true regardless of that decision

1. **`~/.claude` is logged out and a launcher still points at it.** Bare `claude-prev` will
   prompt every time until it is re-authenticated or repointed. Same for the unsuffixed
   `Claude Code-credentials` item.
2. **`concurrency()` cannot see `claude.exe` sessions** (§ *One real defect*). Worth fixing on
   its own merits — it is a one-line matcher change — because it is the gate that decides
   whether a headless heal is safe to run.

### Proposed, NOT built — it touches the auth surface, so it is your call

A **credential backup**: snapshot each Keychain payload whenever it changes, into a sibling
Keychain item (not a file — no security downgrade), and restore the last-good refresh token
when the CLI erases one. This is the only measure that makes an erase *recoverable*; today it
is terminal. It would have turned every event in §6 into a self-healing blip. I have not built
it because duplicating credentials is an auth-surface decision that belongs to you.


---

# UPDATE 3 — 2026-08-04: the second mechanism, found and fixed

Session brief: *"the symptom survived the lock fix, so a second mechanism is live."* It was,
and it is not the one the questions anticipated. Everything below is measured on this machine
between 2026-08-04T01:27Z and 05:10Z unless marked INFERRED.

## The answer to Q1, plainly: **(b), caused by (c). Not (a), not (d).**

**(a) — the login cliff — is REFUTED, and this is the load-bearing measurement.** On
2026-08-03 next2's refresh grant answered `400` twenty times between 14:04:57Z and 15:40:05Z.
Its own `refreshTokenExpiresAt` at that moment read **674.6 hours away — 28 days**. A grant
can be dead long before its calendar cliff, so the cliff cannot be the thing biting. The
`/login` is not expected, and re-anchoring on a schedule would not have prevented it.

**(d) — a genuinely revoked grant — is refuted by recovery.** next2 came back **without a
human**: a live session refreshed it successfully at 01:20:28Z on 2026-08-04, and the
transcript record shows the session emitting one auth error at 01:00:18Z and resuming normal
work at 01:20:33Z with no typed `/login`. A revoked grant does not do that.

**(b) is the shape of the failure and (c) is why it keeps happening here.** The store holds a
refresh token the server has already retired, so every later attempt replays a corpse. The
2.1.220 binary makes that reachable by construction, and our own tooling makes it likely.

## Why the cliff looks unextendable, settled by measurement rather than citation

Two oracles disagreed, and both turned out to be right. The binary computes
`refreshTokenExpiresAt` **client-side on every refresh** —
`ano(e,t){ if(typeof e==="number") return Date.now()+e*1000; ... }`, fed by the token
response's `refresh_token_expires_in` — so the source says a plain refresh *does* rewrite the
field, refuting "only an interactive login re-anchors it" as a statement about mechanism.

But the instrument caught two live rotations and measured what the rewrite actually does:

| account | rotation | live sessions | cliff moved by |
|---|---|---|---|
| next3 | 2026-08-04T03:11:41Z | 19 | **+115 ms** |
| next4 | 2026-08-04T03:40:30Z | 0 | **−10 ms** |

The server returns the **remaining** life of the same underlying grant, so the recomputed
value lands on the same absolute instant to within sub-second rounding. **A refresh rewrites
the cliff and cannot move it.** The operational rule in memory was right; its stated mechanism
was wrong, and the distinction matters because it means no amount of successful refreshing
buys calendar — but also that a cliff observed weeks out is real, which is what refutes (a).

Corroboration across a 30-hour window: next / next3 / next4 held their cliffs to the second
(`Aug 30 15:03:18` / `17:19:43` / `15:36:28`) across multiple rotations. next2 alone moved
(+5h24m, to `Aug 31 22:33:45Z`) — a jump no refresh can produce, so next2 received a **new
grant** on Aug 3. No `/login` appears in any transcript that day, and the transcript
instrument only sees `/login` typed *inside* a session, so an out-of-session re-auth is the
consistent explanation. [INFERRED — the anchor time is derived from the cliff, not observed.]

## Q4 — YES. In-session refresh works now the lock is gone.

This is the control the prior investigation could not fire, and it fired three times. The
discriminator is the prior doc's own: a credential change with **no adjacent
`claude-accounts.log` heal line** is an in-session refresh; one within seconds of a
`heal <acct>: OK` is not.

| account | token minted | heal line? | verdict |
|---|---|---|---|
| next | 2026-08-03T22:35:33Z | `heal next: OK` at 22:35:35Z | heal |
| next2 | 2026-08-04T01:20:28Z | none since 15:40:05Z (−9h40m) | **in-session ✓** |
| next3 | 2026-08-04T03:11:41Z | none on 2026-08-04 before it | **in-session ✓, 19 live sessions** |
| next4 | 2026-08-04T03:40:30Z | `heal next4: OK` at 03:40:31Z | heal |

**`1677218f` is confirmed by effect.** The mechanism it unblocked is now demonstrably firing,
including on an account with 19 concurrent sessions. It was never the whole cure, because it
was never the only mechanism.

## Q2 — heal retried a terminal 400 forever because the verdict had nowhere to live

`_heal_rejected()` classified the very first 400 correctly. The verdict was then written to
two keys on an in-memory row behind a 90-second cache and discarded. Nothing persisted it, so
every later sweep recomputed `stale` from `expiresAt`, found no memory of the rejection, and
burned another 90-second `auth login` against a token already proven dead — **20 times in 95
minutes**, with no backoff, no counter, and no circuit breaker.

**Q3 — one account, not a rotating victim.** Every one of the 20 failures was next2. The
historical bursts have the same single-account shape (next2 ×11 on Jul 19; next3 ×24 on
Jul 24–25).

## The defect that actually explains "it just comes up daily, with no warning"

The escalation path exists, fired correctly, and was **refused by its own remedy**:

```
14:34:26Z  cc-relogin-poll  ESCALATED next2 … recover=cc-relogin next2
14:34:33Z  cc-relogin       next2 refused exit=2 phase=gate ::
                            no re-auth needed — healthy (auth=stale, login_expires_h=674.6)
15:34:55Z  … the identical pair again, one hour later
```

`cc-relogin` measures with `--no-heal` **on purpose** — a heal inside a measurement is not a
measurement. But `--no-heal` skips the only branch that calls `_heal_rejected()`, so the row
reads `auth="stale"`, whose documented meaning is *benign*, and `need_relogin()` answers
"healthy" and exits 2. **The trigger and its own remedy were asking different questions about
the same account at the same instant** — one asked "is this account working?", the other "is
the calendar cliff near?". Automation gave up; the operator became the fallback. Daily.

Note the second-order damage: the poller escalated with a **fabricated `T-0h` deadline**
(`dl=$NOW` for a row carrying no deadline columns) while the true cliff was 674h out, so the
board told the operator the wrong thing about the wrong failure mode.

## What landed

| commit | change |
|---|---|
| `f8178bfe` | the mechanism fix — three defects below, six red-proved tests |
| `31e76310` | the suite was appending to the production log (found by this work, see below) |
| `7954996f` | `auth-timeseries.sh` records the keychain write time |

**1. The rejection is now durable**, keyed on the refresh token's **fingerprint** (sha256
prefix — never a token value). The record means "THIS grant was rejected", so it self-clears
the moment the store holds a different token. A boolean would have pinned a false
`login-required` on an account that fixed itself, which is precisely what next2 did.

This one change closes both halves: the read side sits *before* the heal, so a proven-dead
grant is never re-redeemed on a timer (Q2), and because the state is now visible to
`--no-heal` readers, `cc-relogin` sees `auth=login-required` — already in its
`LOGIN_FIXABLE` set — and acts instead of refusing. **`cc-relogin` needed no change at all**;
the state it had always been willing to act on was simply unreachable from the only code path
it runs.

**2. `heal()` now verifies by effect.** Success was `rc==0` plus `"Login successful"` on
stdout, and 2.1.220 emits both when the credential was never stored — its persist helper
returns `{success:false}` on a keychain write failure and the caller discards that verdict
(`return await Wer(f),wq(),"refreshed"` — a comma expression). Worse, that path **wipes the
stored credential before writing the replacement**, so a lost write leaves nothing on disk
while the server has already retired the old token. A false OK would have cleared the record
above and re-armed the retry loop, so the claim is now checked against the store.

**3. The rotation-safety gate can finally see the sessions it protects.** `concurrency()`
matched `claude` and `*/claude` but not `claude.exe` — argv[0] for every `cc-pane-runner`
worker, teammate and research subagent. Measured while writing this:

```
.claude-secondary   counted  2   actual 10     ← 8 invisible
.claude-tertiary    counted 10   actual 13
.claude-next        counted  1   actual  3
```

That count *is* the `k_live > 0` refusal, so a heal read a busy account as idle and redeemed
its refresh token alongside eight invisible sessions that rotate the same credential. This is
the (c) that produces the (b): the loser of that race holds a retired token. Six sibling tools
already matched both spellings; this was one of the last two.

## Two corrections to earlier work in this document

* **"The cliff anchors to the last interactive login and no refresh extends it"** — right
  about the outcome, wrong about the mechanism. The field is rewritten on *every* refresh and
  lands on the same instant (±115 ms, measured).
* **The `mdat` anomaly is not a writer race.** Keychain items were written hours after their
  access token was minted, which looks like a second writer. The item is CC's **entire**
  secure-storage blob — `mcpOAuth`, `pluginSecrets`, `gatewayTrust` and more — so an MCP token
  refresh rewrites it and moves `mdat` while `claudeAiOauth` is untouched. Control: next4 and
  the unsuffixed item, both with zero live sessions, went 6h and 14h with no write while 25
  writes landed on the three accounts that had sessions.

## Known-open, filed rather than fixed

* **The write-loss window is upstream and we cannot close it.** Between the token POST
  returning and the keychain write completing, the new refresh token exists only in process
  memory; the write is a `security(1)` subprocess with a **2-second timeout**, and a timeout is
  classified `transient:true`, which *skips* the plaintext fallback entirely. Both the
  in-session and `auth login` paths report success regardless. Our fixes reduce exposure (fewer
  concurrent grants) and make the outcome detectable and escalatable — they cannot make the
  vendor's write atomic.

  **2026-08-08 — converted from prose to a tracked condition** (backlog `4adbeab56aa7`). Every
  clause above was re-verified against the shipped `2.1.220` bundle rather than recalled, and two
  details this paragraph did not have turned out to matter: the write is attempted **exactly once**
  (`Hcg()` retries only the lock, never the write), and `auth login` **deletes the stored credential
  before** writing the replacement — so a lost write there leaves the machine logged out while the
  CLI prints `Login successful.` and exits 0. The submittable write-up, with the verbatim code and
  the ranked fixes, is `vendor-report-cc-authstore-write-loss.md`; a secondary finding lives there
  too (above 4 032 command characters the credential blob moves onto `security`'s **argv** — not
  reached on this machine, but the largest account measured 3 906, i.e. 126 characters below it).

  The tracking is mechanical, because a known-open fact that lives only in prose has no way to learn
  it changed: `scripts/cc-authstore-probe.sh <binary>` reads any candidate bundle and answers
  FIXED / STATUS-QUO / WORSE / UNREADABLE, resolving the 2 000 ms timeout and the 4 032-character
  threshold from the candidate's own use-sites instead of trusting the numbers written here. It runs
  as check **#14** of `cc-upgrade-gate.sh`, where STATUS-QUO deliberately SKIPs — an upstream defect
  we cannot fix, unchanged from the binary we already run, is not grounds to park an upgrade, and a
  check that went red on every candidate forever would carry no information. WORSE (the plaintext
  tier removed) and UNREADABLE (the storage layer no longer introspectable) fail the gate; FIXED is
  the signal to close `4adbeab56aa7` and revisit the compensations landed in `f8178bfe`.
* ~~**The fabricated `T-0h` deadline** in `cc-relogin-poll` (defect D5) — the escalation fires,
  but names a calendar deadline that is not the reason.~~ **FIXED 2026-08-09** (backlog
  `8e394583d5d4`). `$DL` was serving two jobs at once: an ORDERING position (which account is most
  urgent — for which `NOW` is the correct answer on a REQUIRED row) and a PUBLISHED deadline (for
  which `NOW` was never measured). They are now separated by a `deadline_src` provenance tag, and
  only a measured deadline is published: the escalation still fires, and it names the state plus
  the cause `claude-accounts` published beside it (`login state is REQUIRED now (cause:
  token-invalid) and claude-accounts published NO deadline for it`) instead of a clock.
  `deadline` is empty, `hours_left` is JSON `null` — not `0`, which a consumer would compare — and
  `deadline_known:false` keeps the emptiness from having to mean both "no deadline exists" and
  "the field went missing".

  **The damage was worse than the wrong text, and that half was not in this list.** A class-C row
  whose `deadline` is `NOW` is EARLIER than the account's live `login_expires_at`, which is exactly
  `cc-blockers`' stale-drop predicate (`drop_stale_relogin`) — so the loudest surface the poller
  has discarded the row **by construction**. Measured on next2's own 2026-08-03 shape (grant
  rejected, cliff 674h out): **1 row raised, 0 rendered**. Publishing no deadline lands in that
  file's documented fail-open (`$d == null … keep`) on the polarity its author chose — *"a stale
  row is noise, a dropped live one is silence"* — and the row now renders. Pinned by a mutation
  control in `tests/cc-relogin-status.bats` that replays the pre-fix row byte-for-byte and asserts
  it is still dropped, with `CC_BLOCKERS_ACCOUNTS_BIN` armed at a present stub (the suite's default
  is a deliberately ABSENT binary, under which both arms would pass vacuously).

  Root cause, for the next reader: the producer blanks both deadline columns **on purpose** —
  `bin/claude-accounts:2284`, *"An account can need /login for a reason that is NOT its deadline …
  printing that stamp beside REQUIRED read as 'required, and it expires in 14 days'. The deadline
  columns are therefore filled only when the deadline is what is driving the verdict; otherwise the
  reason column carries the cause"*. The poller read that deliberate `—` as a deadline of `NOW` and
  discarded the `reason` column into an unused `_reason`, re-manufacturing the exact misreading the
  producer had removed, in the opposite direction. It now carries that cause through to the board.
* `~/.claude` remains logged out with `claude-prev` still pointing at it; `next` still carries
  multiple grants. Both unchanged from UPDATE 2.

## Three fabricated log entries, disclosed

`heal next3: UNPROVEN — reported success but the stored refresh token did not change` appears
in `~/.claude/logs/claude-accounts.log` at **04:58:58Z, 04:59:45Z and 05:00:54Z on
2026-08-04**. These are **not** fleet events. They are this session's own test suite: the new
log line sits outside the stubbed `heal()`, and `LOG_PATH` resolved from `$HOME`, so three
test cases wrote to the production log. Fixed in `31e76310` (control: the log's line count is
identical across a full 87-test run). Left in place rather than edited out, and recorded here
so a future investigator is not misled by them.


---

# UPDATE 4 — 2026-08-07: the trigger question, closed by effect

Backlog item `23eccae755a9` — *"Auth-error rate regressed ~20x from 2026-08-01T00:46Z — TRIGGER
UNRESOLVED"* — was filed at **2026-08-02T19:49:55Z**, twenty minutes before the root-cause block
at the top of this document was written. Nothing connected the two, so the item outlived its own
answer and was re-dispatched five days later. This update adjudicates it against the evidence
neither could have: **five days of post-fix data.**

**Verdict, three parts.**

* The headline **"TRIGGER UNRESOLVED" is superseded.** The trigger is the config-mirror race
  already described at the top of this document, and it is now confirmed **by effect** — which
  the 2026-08-02 session could assert only by mechanism.
* Candidate **(b), the same-account multi-grant condition on `next` (the E1 question), is
  REFUTED** by the data. It should not be carried forward as an explanation for this regression.
* Candidate **(a), a server-side change to refresh behaviour, is unnecessary and unsupported.**
  No evidence contradicts it outright, but nothing requires it and its central prediction fails
  (below).

## What made the question adjudicable: there were two failure classes, not one

The original measurement pooled every `isApiErrorMessage` carrying an auth string. That is what
kept the picture muddy for five days, because two unrelated failures share the phrase
*"Please run /login"*:

| class | text | meaning |
|---|---|---|
| **A** | `Please run /login · API Error: 401 OAuth access token has expired.` | the 8h access token ran out because the in-session **refresh could not run**. Credential intact, refresh path broken. |
| **B** | `Not logged in` / `Login expired` | the stored credential is **empty or the grant is dead**. No refresh helps; only an interactive login does. |

Class A is the regression. Class B is a pre-existing, separate phenomenon that runs from Jul 9 to
the present. Pooled, class A's cure is invisible — **2026-08-04 shows 13 auth errors, which reads
as "still broken", and every one of them is class B.**

## Class A is a bounded event — all 35 of them

Measured with `tools/auth/auth-error-rate.py` (committed alongside this update):

| period | class-A errors | sessions | per session |
|---|---|---|---|
| before onset (all history) | **0** | 1727 | 0.0000 |
| onset → lock fix | **35** | 224 | 0.1562 |
| since the lock fix | **0** | 899 | 0.0000 |

Every class-A error **ever recorded on this machine** falls inside one 41.2-hour window:
**2026-08-01T00:46:55Z → 2026-08-02T18:01:42Z**. The window opens at the onset the backlog item
names and closes before `1677218f` landed (2026-08-02T20:05:18Z).

Daily, with the two classes separated — the same rows that read as an unresolved regression when
pooled:

| day | sessions | A | B |
|---|---|---|---|
| 2026-07-30 | 270 | 0 | 0 |
| 2026-07-31 | 171 | 0 | 2 |
| **2026-08-01** | 182 | **18** | 0 |
| **2026-08-02** | 79 | **17** | 1 |
| 2026-08-03 | 123 | 0 | 0 |
| 2026-08-04 | 113 | **0** | 13 |
| 2026-08-05 | 89 | 0 | 0 |
| 2026-08-06 | 92 | 0 | 0 |
| 2026-08-07 | 466 | 0 | 1 |

## Why candidate (b) — the multi-grant condition — is refuted

**The first error of the regression, at 2026-08-01T00:46:55Z, is on `next4`** — the
*single*-grant account this document named as the clean control ("next4 — one store — has had
zero forced re-logins in 30 days"). It is not an outlier: next4 carries **8 of Aug 1's 18**
class-A errors, more than any other account.

And the onset is **simultaneous across all four accounts** — next(6), next2(3), next3(1),
next4(8) on Aug 1 alone. An account-scoped grant condition cannot do that. A machine-wide mirror
that symlinked one lock into all four config dirs is precisely what does.

The multi-grant observation itself stands — `next` really does carry 2-4 grants and that is still
worth collapsing, for the rotation reasons in UPDATE 3. It is simply **not the cause of this
regression**, and E1 remains genuinely open rather than answered-in-the-negative.

## Why candidate (a) — a server-side change — is unnecessary

Its central prediction fails: a server-side change to refresh behaviour would not **stop** when a
local symlink was deleted. The cessation is bracketed by the deletion, on the same client build,
with no other auth-touching change in between.

One honest caveat that cuts the other way, and it is why this section says *unnecessary* rather
than *refuted*: the class-A text is **server-authored**. Checked with `strings` against the
running 2.1.220 binary, `Please run /login` and `API Error` are client literals, but
`access token has expired` and `Re-authenticate to continue` are **not present in the binary at
all**. So the body could in principle be reworded upstream. That loophole is closed by measurement
rather than assumption — see the third control below.

## Four controls, because each alternative reading has one

1. **The instrument reproduces the published artifact.** `auth-error-rate.py --active-denominator`
   returns the 2026-08-02 table in this document row for row — 190/123/61/22/101/270/171/182
   sessions and 4/1/0/1/0/0/2/18 errors. (Aug 2 reads 79 sessions against the published 74: that
   table was written at 19:49Z and five more sessions started before midnight.)
2. **Not a denominator artifact.** The quietest days are the busiest: **2026-08-07 ran 466
   sessions — the highest in the window — with zero class-A.**
3. **Not a server rewording.** Every `isApiErrorMessage` record in the 899 post-fix sessions was
   read, not just the ones that classify. **None pairs the client literal `Please run /login` with
   `API Error`.** The remainder are `Overloaded` (8), stalled/closed streams (7), `ECONNRESET` (2)
   and weekly-limit (2). A reworded 401 body would still have carried the client frame.
4. **Not heal masking a still-broken refresh.** `heal` did not become more active — 2/day on Aug 1,
   5 on Aug 2, 3 on Aug 3, 2 on Aug 4, 1 on Aug 7. Decisively, **2026-08-05 and 08-06 ran 162
   sessions with zero heal events and zero auth errors of any class.** Each account's 8h token
   expired ~3× per day across those two days with nothing rescuing it out of band, and no session
   ever saw a 401 — which requires in-session refresh to be working. This is the same conclusion
   item `8af0d2e65920` reached from the credential side, by a disjoint route.

Two smaller readings, disposed of: the **client build is controlled** — 2.1.220 ran on *both*
sides of the boundary (848 of the 899 post-fix sessions), so this is a within-build before/after,
which is exactly the comparison correction `bbad96d163ab` said the original version claim never
had. And the **~2h gap between the last class-A (18:01Z) and the fix (20:05Z)** is not an early
cure: class-A arrives in clusters 4-10h apart (7 clusters over the 41.2h window, tracking each
account's own 8h expiry), so the fix landed in an ordinary trough. **15.7 TTL cycles per account
have elapsed since, and no cluster ever came again.**

## What this does NOT establish

**The four symlink birth times — 2026-07-31 14:58:12 / 15:13:45 / 16:11:07 / 16:36:18 — rest on a
single source**, the measurement recorded in `1677218f`'s own commit message. The symlinks were
deleted the same day, so the timestamps are not re-verifiable now, and the bash logs hold no
record of the removal. Treat "70 minutes before the first forced login" as attested, not
reproducible.

The causal case does not depend on them. What is independently re-checkable is stronger:

* **The mechanism, from the diff.** The pre-fix share loop is `for e in "$src"/*(ND)` — the `D`
  glob qualifier includes dotfiles — so `.oauth_refresh.lock` was in scope and would be symlinked
  into every account dir, dangling the moment the real lock released
  (`git show 1677218f -- lib/config-mirror.zsh`).
* **The arithmetic.** This machine is PDT (UTC-7) in August, so the "17:46 local" first forced
  login is **exactly 2026-08-01T00:46Z** — the onset timestamp in the backlog item, derived from a
  different instrument by a different session.
* **The bracket**, above.

## The instrument, committed rather than scratchpadded

`tools/auth/auth-error-rate.py` — READ-ONLY, harness-side companion to `auth-timeseries.sh`
(which samples the credential store; this reads what the operator was actually shown). It exists
because this investigation's *first* instrument died with its session, which is why the question
had to be re-measured from scratch to close a five-day-old item. It carries the class split, the
realpath dedupe (`~/.claude-next/projects` is a symlink to `~/.claude/projects`), datetime rather
than string boundary compares, and `--all-errors` so that an absence can be distinguished from a
blind spot.

## Filed, not fixed here

* **The class-B daily pattern on `next`** — `Not logged in` at ~11:17-11:38Z on Jul 11-20, 26, 28
  and 31, then stopping. A daily scheduled job hitting the erased `~/.claude` credential is the
  obvious shape (this document's §4: bare `claude-prev` resolves there), but it is a different
  phenomenon from the class-A regression and was not chased.
* **A research subagent can take its own lead's work lease.** Closing this item, two read-only
  subagents spawned by the lead claimed item `23eccae755a9` and the claim gate then refused the
  *lead's* writes as a duplicate worker. The gate walks the ancestor chain to a `claude` pid, so a
  subagent's tool call claims under the subagent's pid. It self-released when the children exited
  and no override was used — but a read-only research subagent should never take a work lease.
