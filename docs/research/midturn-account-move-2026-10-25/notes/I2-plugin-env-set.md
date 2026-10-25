# I2 — plugin `$.env.set` as a client-native per-request account switch

Scope: can a hooks-module plugin loaded at session start change the running process's billing
account mid-turn by writing `CLAUDE_CODE_OAUTH_TOKEN` (or `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_BASE_URL`)
via `$.env.set`? All offsets are byte offsets in `/tmp/mtam/cc293-src.js` (CC 2.1.293), measured with
`python3 -I` + `re.finditer` windows. READ-ONLY; no settings/keychain/git writes.

## TL;DR verdict

**Viable, client-native, per-request — for sessions launched WITH the plugin.** A hooks-module
plugin can call `$.env.set("CLAUDE_CODE_OAUTH_TOKEN", <token>)`, which writes `process.env` directly
(`EIo` @11552107). Because the CC env object `a` is a live getter over `process.env` (`Elt` @1852061),
`m$()` re-reads the new value the next time the `bA` memo is cleared. In the operator's env-token mode
(no `.credentials.json` in the config dir, which is the normal state when `CLAUDE_CODE_OAUTH_TOKEN` is
set), **the memo is cleared on every request** by `wA()`→`Jf()` (ENOENT on the store file), so the new
token is adopted on the **next API request with no 401 needed**. This is stronger than SmelterLabs'
"per request" claim.

**But three hard limits:**
1. **No retrofit.** Plugins load only at session start (`session.start` fires per load). A plugin
   added now does NOT attach to the ~36 already-running sessions. "existing sessions do not load the
   plugin" (S09). So this moves *future* launches, not tonight's live panes — same gap as the
   base-URL-proxy route.
2. **Needs a credential source.** The plugin only writes a string into `process.env`. It must get a
   valid inference token from somewhere (a broker / file / socket). The env token has
   `refreshToken:null`, `expiresAt:null`, so the client never refreshes it; at real expiry the server
   401s and the plugin must have pushed a fresh token in time (see §3).
3. **Metadata unchanged.** Same P6 caveat as every bearer-swap: `metadata.user_id.account_uuid` keeps
   the launch account (`kn()`/`aSe` only re-keyed on 401 recovery and refresh-race, not on a silent
   env rewrite — G4). Bearer-account ≠ metadata-account without a restart.

Net: a true client-native per-request switch is possible, but it is **per-launch + needs a credential
broker**, so it is architecturally the same class as the P4/P5 store-rewrite and the P3 proxy: it
requires one launch under the mechanism. It does not beat the "idle never happens / retrofit live
panes" wall on its own.

---

## (1) The plugin/mod API surface for `env.set`, events, and loading

**`env.set` is a first-class op.**
- Op handler `EIo` @11552107: `function EIo(e){if(e.value===void 0)return delete process.env[e.name],Promise.resolve();return process.env[e.name]=e.value,Promise.resolve()}`. Writes `process.env` directly.
- Op table entry @12029422: `"env.set":{check:A1t,run:EIo}` (and `"env.get":{check:A1t,run:vIo}` @11551485).
- `$` wrapper `Ew` @5158980: `var Ew=(e)=>E_({get:(t)=>e("env.get",{name:t}),set:async(t,o)=>{await e("env.set",o===void 0?{name:t}:{name:t,value:o})}})`. So a module calls `$.env.set("CLAUDE_CODE_OAUTH_TOKEN", tok)`.
- Arg validator `A1t` @11551611: name must be a plain string, no `=`, no NUL, value a string or undefined.
- `env.set` is in the op list `xHn` @4918035 and the validator map `Md` @5063420 (`"env.set":xi`).

**Host rule — the module must statically name the variable.** `GUt` @11528430: a module may only
`env.set` a name it literally names in a `$.env.set("<name>", …)` call; the static scan records
`env.writes` and refuses an undeclared name ("its hooks module does not name <name> in a
`$.env.set(\"<name>\")` call"). The name must be a literal (`Ht` @4925773, scanner at `sus` /
`Pt=["env.get","env.set"]` @4923292). `claude plugin validate` prints `<mod> env writes: …` (@31564685).
Practical effect: the plugin source must contain the literal string `CLAUDE_CODE_OAUTH_TOKEN` (and/or
`ANTHROPIC_BASE_URL`) in an `$.env.set(...)` call — trivial, but not dynamic/obfuscatable.

**Which events a plugin can run on (per request / per tool / timer).** Registered event list `jVe`
@~4918700 includes `turn.start`, `turn.step`, `turn.complete`, `tool.call`, `tool.check`,
`prompt.submit`, `session.start`, `session.measure`, `session.end`, `clock.now/sleep/after/every`,
plus all 33 `classic.*`. `env.set` is an *op*, callable from inside ANY of these hook handlers.
Granularity that matters here:
- `turn.step` — a streaming generator fired **per model request** (main or subagent `agentId`). This
  is the true per-request hook: a `turn.step` handler can `await $.env.set(...)` before the request
  goes out. (`hgr=["turn.step","process.spawn"]` marks it as a streaming event, @~4918900.)
- `tool.call` — per tool.
- `clock.every` — a timer (a broker can re-push the token on a cadence).
- `session.measure` — pushed after each main turn and on every whole-point rate-limit move
  (`rateLimits[{kind,percentUsed,resetsAt}]`) — a natural trigger to switch at a wall.
- There is **no session-idle event** (U-api); the closest live signals are `turn.complete` and
  `session.measure`.

**How plugins load (no settings.json edit required).**
- `--plugin-dir <dir>` flag (repeatable). **This is exactly what the repo already does**:
  `lib/cc-mod-argv.sh` emits one `--plugin-dir` per `~/.claude/mods/<name>/` and
  `lib/claude-launcher.zsh` (and the two expect resume wrappers) pass them at launch. No settings edit.
  Only one mod is live today: `~/.claude/mods/accounts-readout` (symlink into the repo).
- `CLAUDE_CODE_PLUGIN_DIRS` env (acts like `--plugin-dir`; schema key @1812631). The repo deliberately
  avoids this (an exported var reaches every `claude -p` child; `~50-60 MB` RSS per loaded mod — comment in cc-mod-argv.sh).
- `enabledPlugins` / `/plugin` (marketplace install).
- **Gate flag `tengu_plugin_hooks_modules` (`AP`, default `AD=!0`) — ON by default in 2.1.293**
  (`jir()` @9138821 returns the flag with default true; computed default `AD=!0` @9138558).
  `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` overrides it (schema @2251829, @5252824). The "early access"
  gate `m()` @9137325 only forces the off-path under API-key / gateway modes
  (`a.ANTHROPIC_API_KEY`, `Yf()` apiKeyHelper, etc.) — not under subscription OAuth. So on the fleet's
  2.1.293, a hooks module loads via `--plugin-dir` at launch without the env var and without a
  settings.json edit. (Consistent with the 2.1.289 measurement in U-api: default on since 289.)

---

## (2) Does `m$()`/`mn()` see the `process.env` change given the `bA` memo?

**Yes, via two independent paths; one of them needs no 401.**

The env object. `a = Elt(bx, p)` @1852398 where `Elt` @1852061 defines each key as a getter:
`get:()=>{let C=process.env[r]; if(C!==n)e=s.parse(C),n=C; return e}`. So `a.CLAUDE_CODE_OAUTH_TOKEN`
is a **live read of `process.env`** — after `EIo` writes `process.env.CLAUDE_CODE_OAUTH_TOKEN`, the
getter returns the new value immediately. (`Elt` also exposes `.set`/`.unset` that write `process.env`,
but the hooks op uses `EIo` directly.)

The memo. `mn()` @~4657050: `if(e.value!==void 0)return e.value; let n=m$(); return e.value=n,n`
(class `bA` @4655727; `Hye=new z(()=>new bA)`). `m$()` @~4655116 reads
`a.CLAUDE_CODE_OAUTH_TOKEN` FIRST (returns `{accessToken:…, refreshToken:null, expiresAt:null, …}`),
before any store read. So the question is purely: when is `e.value` cleared so `mn()` recomputes?

**Path A — no 401 (env-token mode, no store file): memo cleared EVERY request.**
- Request path: `EN()` @8641537 does `await j7({...})` then `mn()`. `j7`→`Pl` @4668663, and `Pl`
  starts `await wA(e,b)` unconditionally.
- `wA()` @4658275: with storageV5 `n` undefined (S14: `EN` passes `N=undefined` in 2.1.293), it takes
  the file branch: `r=(await np(rp(uw(),".credentials.json"))).mtimeMs`. On a config dir with **no**
  `.credentials.json` (the env-token case — next/secondary/quaternary/`~/.claude` all have no file,
  S14:111) this throws ENOENT → `return Jf(e,n)`.
- `Jf()` (auth variant, called from `wA`) @~4659248: **`e.clear()` at the top (unconditional)**, then
  compares the keychain token. `e.clear()` drops `bA.value`/`promise`.
- Back in `EN`, the following `mn()` → `m$()` re-reads the live `a.CLAUDE_CODE_OAUTH_TOKEN`.
  ⇒ **A plugin `env.set` is adopted on the very next client build / API request, no 401 required**,
  whenever the session is in env-token mode with no store file (the operator's normal state).
- (If a `.credentials.json` DOES exist and its mtime is unchanged, `wA` takes the `Nk()` branch
  @~4658500, which only reaches `Jf` when the cached token is unusable + past the `cPt` recheck
  interval — so the memo would persist and the env change would wait for a 401. Pure env-token mode
  does not have this file.)

**Path B — 401 recovery explicitly re-reads `process.env` and even assigns it.** `y$()` @4661639
(the 401 handler, via `KS`) begins `ox()` (clears memo + zeroes keychain cache), then:
- SDK-callback branch @4661771: `process.env.CLAUDE_CODE_OAUTH_TOKEN=M, ox(), kn()` — it *writes*
  `process.env` from the callback and re-keys the account.
- recovered-from-disk branches @4662707 / @4663017: `if(a.CLAUDE_CODE_OAUTH_TOKEN) process.env.CLAUDE_CODE_OAUTH_TOKEN=M.accessToken`.
- **rotated-env-token branch** @~4663017+: `P=Boolean(process.env.CLAUDE_CODE_OAUTH_TOKEN)||Boolean(eM())`;
  if set, it logs "OAuth 401 recovery: waiting up to <ms> for a rotated env token" and calls
  `BRs({failedAccessToken:e, timeoutMs:M})`. `BRs()` @4660424 polls
  `a.CLAUDE_CODE_OAUTH_TOKEN ?? eM()` every 2000 ms until it sees a token different from the failed
  one, then `ox(), kn()`, success. So **a plugin that pushes a fresh token into `process.env` during
  that window recovers the 401 as a first-class, instrumented path** (`tengu_oauth_401_*`).

So to the brief's sub-question: yes, a path clears the memo when the env changes (Path A, `wA`→`Jf`
`e.clear()` every request in env mode), AND the 401/`Pl` path re-reads `process.env.CLAUDE_CODE_OAUTH_TOKEN`
and even assigns it (`y$`). Both confirmed.

`ANTHROPIC_BASE_URL`: read live through `a.ANTHROPIC_BASE_URL` (33 hits, incl. the client base
@8640047/8651490). But the first-party vs proxy gates (`Sl()`/`pi()`/`Of()`, @2000799/2000869) are
evaluated at client build; a mid-session flip to a non-`api.anthropic.com` base inherits P2's
tool-search drop / account_uuid blanking and does NOT re-enable `Of()`-gated features. So `env.set`
on BASE_URL in-process is possible but carries the same P2 degradation as launching behind a proxy.

---

## (3) Env token has `refreshToken:null` — expiry behaviour

- `m$()` stamps an env token `{accessToken:…, refreshToken:null, expiresAt:null, …}` (@~4655133).
- Proactive refresh never fires: `Pl` returns `"no_refresh_token"` when `!M?.refreshToken`, and with
  `expiresAt:null` the `JP()` 5-minute pre-expiry window (`now+300000 >= expiresAt`) is never entered.
  So the client just keeps sending the env token until the server rejects it.
- At real expiry → **401** → `y$`: no `refreshToken`, (no SDK callback) → it falls to the
  rotated-env-token wait (`BRs`, §2 Path B), polling `process.env.CLAUDE_CODE_OAUTH_TOKEN` up to
  `h$()` ms. If no fresh token appears, recovery fails; the session exits after
  `CLAUDE_CODE_...AUTH_FAIL_EXIT_MS` (default 600000, @4661771 window).
- ⇒ The plugin (or its broker) must push a fresh, unexpired token into `process.env` **before or
  within the 401 window**. A `clock.every` or `turn.step` hook re-pushing the current token is the
  natural keep-alive. This is the same "broker must re-copy before the source refreshes" hazard as
  the store-rewrite routes (brief Retry loop / Refresh hazard), with the bonus that `env.set` costs no
  file I/O.

---

## (4) Official / repo plugin-authoring skill

- **`~/.claude/skills/plugin-authoring/SKILL.md` does NOT exist** (measured: `ls` ENOENT; the skills
  dir has ~60 skills, none named plugin-authoring). So there is no repo-local authoring skill to cite.
- There IS a **built-in CC mod** `cc-plugin-plugin-authoring@builtin` (strings list, U-api §2) — an
  Anthropic-shipped mod, not a repo skill, and not readable as a file here.
- `env.get`/`env.set` IS a **documented official mods API**: U-api §4 (from code.claude.com/docs mods
  reference) — "`env.get` / `env.set`. Names must be literals. `set` changes the env of the CC process
  and of every child started afterwards." So the capability is public and documented; it is not a
  repo-internal skill.
- Repo prior art on packaging/loading: `docs/research/plugin-packaging-2026-09-26/`,
  `docs/research/claude-code-mods-2026-10-03/` (U-api.md is the ground-truth API map used above),
  `docs/research/accounts-responsive-mod-2026-10-19/` (why `--plugin-dir`, not `CLAUDE_CODE_PLUGIN_DIRS`).

---

## What a viable client-native per-request switch needs (summary)

1. A hooks-module plugin shipped as `~/.claude/mods/<name>/` and loaded via the existing
   `--plugin-dir` launch wiring (`cc-mod-argv.sh` + `claude-launcher.zsh`). No settings.json edit.
   Hooks modules are on by default in 2.1.293.
2. A `turn.step` (per request) or `clock.every` / `session.measure` hook that calls
   `$.env.set("CLAUDE_CODE_OAUTH_TOKEN", <token>)` with the literal name in source.
3. A **credential source / broker** that hands the plugin a valid inference-only token (refreshToken
   null) for the target account, and re-hands a fresh one before expiry (the plugin cannot mint or
   refresh on its own).
4. Launched under the plugin — **cannot retrofit the ~36 live panes**; same one-launch requirement as
   the P3 proxy and P4/P5 store rewrite.
5. Accepts the P6 metadata caveat (account_uuid stays the launch account on a silent env rewrite;
   only a 401 recovery or refresh-race re-keys it via `kn()`/`aSe`, G4).

Policy framing is out of scope here (see S08); this note is mechanism only.

## Measured-vs-inferred

- Measured (named `python3 -I` reads of `/tmp/mtam/cc293-src.js`): all byte offsets above; the
  `Elt` live-getter, `EIo`/`Ew`/op table, `wA`→`Jf` `e.clear()`, `y$` env-token branches and `BRs`,
  the flag default `AD=!0`.
- Measured (`ls`): absence of `~/.claude/skills/plugin-authoring`; the single live mod `accounts-readout`.
- Inferred: that the operator's target dirs are in env-token-no-store-file mode when
  `CLAUDE_CODE_OAUTH_TOKEN` is set (from S14:111 and P4/P5); the exact `h$()` wait budget value
  (not read); whole-fleet behaviour under a real authenticated interactive session (not run — brief
  forbids launching claude).
