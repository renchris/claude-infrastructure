# R8 — entrypoint split: completeness & edge-case audit

**Verdict: the split is correct on every caller that reaches it, but it SILENTLY UN-INSTALLS ITSELF
when `~/.zshrc` is re-sourced** — a one-command operator action the activation script itself
recommends. Everything else degrades safely; 7 failure modes measured, all fall back to pinned.

Read-only audit. No file outside this deliverable was written. No quota-consuming session launched;
every router probe used a stub binary (`/tmp/r8home/router`) except three read-only
`claude-accounts --route` calls (no `--assign`).

---

## 1. Caller table

Legend: **R** routes · **P** pins · **N/A** never reaches the router.

| # | Caller | file:line | R/P | Correct? | Risk if wrong |
|---|---|---|---|---|---|
| 1 | bare `claude` (operator) | `~/.zshrc:451` body, wrapped at `claude-launcher.zsh:100-124` | **R** | ✅ by design | — |
| 2 | `claude1` | `claude-launcher.zsh:128` | **P** `~/.claude-next` | ✅ | frozen-body staleness → **D2** |
| 3 | `claude2` | `~/.zshrc:235` | **P** | ✅ measured | — |
| 4 | `claude3` | `~/.zshrc:251` | **P** | ✅ measured | — |
| 5 | `claude4` | `~/.zshrc:264` | **P** | ✅ measured | — |
| 6 | `claude-x` / `claude-h` | `~/.zshrc:191-192` | **R** | ✅ intended — interactive tier variants, no account intent | — |
| 7 | `claude-plan` (alias) | `~/.zshrc:183` | **R** | ✅ same as 6 | — |
| 8 | `claude-prev`, `claude-prev2/3/4` | `~/.zshrc:151, 179-181` | **N/A** | ✅ separate function, never wrapped | stable track untouched |
| 9 | `cc` (resumer) | `~/.zshrc:510-541`; launches at `:523`, `:532` | **P** ×2 (`CLAUDE_CONFIG_DIR=` prefix **and** `--resume`) | ✅ double-guarded | — |
| 10 | `cc2` / `cc3` / `cc4` | `~/.zshrc:327, 252, 265` | **P** | ✅ | — |
| 11 | `cc-prev` | `~/.zshrc:298-325` | **N/A** | ✅ calls `claude-prev` | — |
| 12 | `ccr` (cross-worktree picker) | `~/.zshrc:638` | **P** (resume guard **only** — no `CLAUDE_CONFIG_DIR`) | ✅ but single-guarded | if the resume guard ever misses a spelling, `ccr` re-routes a resume → "No conversation found" |
| 13 | `claude-desk` | `~/.claude/lib/desk.zsh:67` — `claude "$kickoff" "$@"` | **R** | ⚠️ **unverified intent** → **D-obs** | the machine-wide desk pane's account now varies per launch |
| 14 | `claude-desk2/3/4` | `desk.zsh:71-73` | **P** | ✅ | — |
| 15 | `handoff-fire.sh` — all 6 typed shapes | `scripts/handoff-fire.sh:6770-6771` → `:7139, 7142, 7254, 7256, 7262, 7266` | **P** via `CC_ACCOUNT_PINNED=1 ` env prefix | ✅ **measured, see §2** | a fire assigned to X landing on Y → spread math inverted |
| 16 | `cc-pane-runner` (kitty transport) | `bin/cc-pane-runner:76-85` (`$SHELL -l -i -c`) | **P** | ✅ transports handoff's `$CMD` verbatim, prefix included | this is the only path where an *interactive* zsh runs a scripted launcher line |
| 17 | Agent-Teams teammate panes | verb is `claude.exe` (a binary path) | **N/A** | ✅ never resolves the function | — |
| 18 | Hooks / launchd / `claude -p` inside scripts | non-interactive shell | **N/A** | ✅ `claude` resolves to `/Users/chrisren/Library/pnpm/claude` (binary); `whence -w claude` under `zsh -f` = `command` | would silently consume a routing decision + write a phantom `--assign` |
| 19 | Nested `claude` inside a session's Bash tool | inherits exported `CLAUDE_CONFIG_DIR` | **P** | ✅ measured | a nested launch re-routing away from its parent's account |
| 20 | `limit-recover` (`lr-handoff.sh`, `lr-reset-poller.sh`), `boot-resume-launch.sh` | all launch with `--resume` | **P** | ✅ | — |

**Ordering invariant: HOLDS.** `claude()` is defined at `~/.zshrc:451`; the `source` is at `~/.zshrc:701`,
which is the **last line of the file** (`wc -l` = 701). Nothing redefines `claude()` after it:
`desk.zsh` (sourced at `:672`) composes `claude` but does not define it; `~/.zlogin` does not exist;
`claude-launcher.zsh` is the only file under `~/.claude/lib/` that defines `claude()`; and no script
in `bin|scripts|hooks|lib` re-sources `~/.zshrc`. Live confirmation — `zsh -ic` on a fresh shell:
`whence -w claude` = function, `_claude_pinned` = function, `claude1` = function, and the live
`claude` body contains `_CC_ROUTED_DIR` (2 matches).

---

## 2. The `CC_ACCOUNT_PINNED` pin — measured, not assumed

The brief flagged that a non-exported var in a parent script would be invisible to the launched
shell. That concern does not apply: the pin is **not** a variable set in a parent process, it is an
**env prefix on the typed command line** (`handoff-fire.sh:6770`), evaluated by the target pane's own
shell. Measured on zsh (`zsh -f -c`):

```
f() { echo "in-func CC_ACCOUNT_PINNED=[${CC_ACCOUNT_PINNED:-UNSET}]"; env | grep -c '^CC_ACCOUNT_PINNED='; }
CC_ACCOUNT_PINNED=1 f          → in-func CC_ACCOUNT_PINNED=[1]   /  env count 1
after call, caller sees:       → UNSET
```

Three facts fall out, all favourable:
- The var **is visible inside the function** → `claude-launcher.zsh:109`'s guard fires. Pin works.
- It **is exported to children** → the CC process and every Bash tool inside that session inherit it,
  so a nested launch is pinned twice over (with `CLAUDE_CONFIG_DIR`). No wrong-pin leak: the
  descendants that see it are exactly the ones that *should* pin.
- It **does not persist in the caller's shell** → a `--recycle` typed into the same pane does not
  inherit a stale pin from the previous fire. The launcher's own routed launch is likewise a prefix
  assignment (`:116`, deliberately not `export`), so a second launch in the same shell re-routes.

`accounts.json` `accounts[0].launcher` is back to **`claude`** (`088875158` reverted `edceb29a6`), so
account 1 fires as `CC_ACCOUNT_PINNED=1 claude …` → routing blocked → `_cfg` defaults to
`~/.claude-next` = account 1. Correct.

---

## 3. Degradation matrix — all 7 modes measured, all fall back to pinned

Stub router + fixture `$HOME`, so no live quota was read.

| Condition | `_CC_ROUTE_NOTE` | Result |
|---|---|---|
| normal | `routed → next3` | routes ✅ |
| `CC_CLAUDE_ROUTE=off` | `routing off (CC_CLAUDE_ROUTE)` | pinned ✅ |
| `claude-accounts` absent / not executable | `router absent` | pinned ✅ |
| map file missing | `pinned — account map unreadable` | pinned ✅ |
| map symlink dangling (repo moved) | `pinned — account map unreadable` | pinned ✅ |
| map declares no dir for the named account | `pinned — map declares no dir for '…'` | pinned ✅ |
| map names a dir that does not exist | `pinned — '…' dir absent` | pinned ✅ |
| router exit 2 / 3 / 5 / empty stdout | `pinned — every account capped` / `no fresh quota data` / `router rc=5` | pinned ✅ |

**All five resume spellings guarded** (stub-router harness, each printing the config dir the pinned
body saw). The shipped /Users/chrisren/.claude/bin/cc-bats suite covers only `--resume <id>` and `-c`; I measured the other three:

```
claude --resume abc   → cfg=unset      claude --resume=abc → cfg=unset
claude -r             → cfg=unset      claude --continue   → cfg=unset
claude -c             → cfg=unset      claude --resume     → cfg=unset
claude -p hello       → cfg=…tertiary  (ROUTES — see D7)
```

**Router latency and stream hygiene** (3 read-only live calls): `real 0.19 / 0.08 / 0.08 s`. stdout is
a single clean token with **zero** trailing newlines (`STDOUT-ONLY=[next]`); all diagnostics
(`claude-accounts: interactive excluded — …`, `route-meta: …`) are on stderr, which the launcher
discards. `--max-wait 0` genuinely bounds the call — no sweep observed.

**The "every local declared ONCE" hazard is not live today.** `_cc_route_config_dir` declares
`local bin acct rc dir note` once at the top (`:46`). It calls two helpers: `_cc_launcher_map`
(declares no locals) and `cc_acct_dir_for_name` (declares none — it *sets globals*
`CC_ACCT_DIR` / `CC_ACCT_IS_FABLE`). Neither is captured with `$( )` — `cc_acct_dir_for_name`'s
stdout is sent to `/dev/null` at `:73` and the value is read from the global at `:76`. Only the
external binary is captured (`:59`), and it is captured directly, not piped. Safe. Residue: those two
globals are left set in the operator's interactive shell after every routed launch (non-exported,
harmless — nothing else reads them expecting freshness).

**`emulate -L zsh` in the wrapper (`:101`) is benign.** It now applies to the *original* body on
every call, including resumes. Diffing `zsh -ic 'setopt'` against `emulate -L zsh; setopt`, the only
options dropped are interactive/history/completion (`autocd`, `correct`, `sharehistory`,
`histverify`, `interactivecomments`, `promptsubst`, `zle`, …). None is one the launch path relies on
— no globbing option (`nomatch`, `extendedglob`) differs, and `claude()`'s body contains no globs.

---

## 4. Ranked defect list

### D1 — HIGH · silently inert · **re-sourcing `~/.zshrc` un-installs the router, permanently, for that shell**

`~/.zshrc:451` redefines `claude()` to the raw pinned body. `~/.zshrc:701` then re-sources the lib,
but `_cc_install_router` returns early at `claude-launcher.zsh:97` — `(( ${+functions[_claude_pinned]} )) && return 0`
— because `_claude_pinned` survived the re-source. The wrapper is never re-applied. **Bare `claude`
silently reverts to pinned account 1, with no notice line**, which is indistinguishable from "the
router legitimately chose account 1" — the exact dark-feature failure the `:119-121` fallback notice
was written to prevent.

Measured on the operator's real rc:

```
zsh -ic 'functions claude | grep -c _CC_ROUTED_DIR'                       → 2   (router installed)
zsh -ic 'source ~/.zshrc; functions claude | grep -c _CC_ROUTED_DIR'      → 0   (router GONE)
         claude body after re-source: "claude () { local _arg _resume=0 …"      (the raw rc body)
         _claude_pinned still defined? 1
```

Confirmed independently on a hermetic fixture (`V1`/`V2` marker bodies, stub router):

```
install:   claude -> V1 cfg=/tmp/r8home/.claude-tertiary   claude1 -> V1 cfg=/tmp/r8home/.claude-next
re-source: claude -> V2 cfg=unset                          claude1 -> V1 cfg=/tmp/r8home/.claude-next
```

Why this is not theoretical: the activation script's own closing line
(`docs/activation/pending-activation/36-start-latency-router-activate.sh:116`) tells the operator
*"Open a NEW shell (or: `source $ZSHRC`)"*. The first re-source works (the shell predates the lib
line); every subsequent one silently disarms the feature. Editing `~/.zshrc` and re-sourcing is the
standard way this operator changes launcher defaults.

The shipped suite misses it: `tests/claude-launcher-router.bats:124` tests
`source LIB; source LIB; claude1` — double-sourcing the **lib**, which is genuinely idempotent. It
never re-defines `claude()` between the two sources, which is what the real rc does.

**Fix shape** (one line, in the lib): make the guard test whether the *current* `claude` is already
the router rather than whether `_claude_pinned` merely exists — e.g. re-install whenever
`functions[claude]` does not contain the router's marker, and refresh `_claude_pinned` from the new
body at that point. That also fixes D2.

### D2 — MEDIUM · silently wrong under a condition that will occur · **`claude1` is a frozen snapshot**

`_claude_pinned` is a **copy** of `claude()` taken at first source (`:98`). `claude1` (`:128`) calls
that copy forever. `claude2/3/4` call `claude`, which the rc redefines on every re-source. So after
any `~/.zshrc` edit + re-source, **`claude1` runs the OLD launcher body while `claude2/3/4` run the
new one** — different binary path, different model, different effort, silently. Proven above: after
re-source, `claude1 -> V1` while `claude -> V2`. Same root cause and same fix as D1.

This bites hardest on exactly the fields that change: `~/.zshrc:496` currently pins
`~/.claude-220/node_modules/.bin/claude` while the block header at `:424` still says `.claude-219` —
that field has moved at least once since the header was written, and a frozen `claude1` would keep
launching the previous binary.

### D3 — MEDIUM-LOW · wrong only under a condition that has not occurred · **a refused launch is still charged**

`_cc_route_config_dir` backgrounds `claude-accounts --assign "$acct"` at `claude-launcher.zsh:84`,
*before* control reaches the pinned body. The pinned body then calls `_cc_route_check`
(`~/.zshrc:456`), which returns non-zero when a worktree claim fails (`~/.zshrc:118, 121, 128`), and
`:457` refuses the launch. **The account has already been charged a phantom working session
(`ASSIGN_TTL_MIN`) for a session that never started.** Same for a Ctrl-C during the worktree claim.
Low frequency, but it skews the very spread math the assign exists to protect. Fix: charge after the
pinned body commits to exec, or emit a compensating record on refusal.

### D4 — LOW-MEDIUM · latent · **the account map is cached for the life of the shell**

`_cc_launcher_map` returns immediately if `cc_acct_dir_for_name` is already defined
(`claude-launcher.zsh:34`). It is sourced lazily on the first routed launch and then never re-read.
A pane that has routed once will use that snapshot for days. Regenerating
`lib/account-map.generated.sh` (adding, removing, or re-homing an account) reaches **new shells
only**. A *removed* account is the bad case: the router may still name it, the stale map still
declares a dir, and the dir still exists → the launch lands on a decommissioned account with no
warning. This is precisely the class `~/.zshrc:392-416`'s `_cc_lib` was written to close for other
libs; the launcher does not use it.

### D5 — LOW · pre-existing, not introduced by the split · **double `_cc_sync_account`**

Measured (`zsh -f -c` with `zmodload zsh/datetime`, 10 calls each, warm):

| target dir | per call |
|---|---|
| `~/.claude-next` | **25.8 ms** |
| `~/.claude-tertiary` | **48.3 ms** |
| `~/.claude-quaternary` | **49.5 ms** |
| `~/.claude-secondary` | **52.6 ms** |

`claude3` (`~/.zshrc:251`) syncs `~/.claude-tertiary`, then the pinned body syncs the *same* dir again
at `~/.zshrc:479` → **~48 ms wasted per launch** (claude2 ~53 ms, claude4 ~50 ms). `cc3` is worse:
`cc3` (`:252`) → `cc()` (`:517`) → `claude --resume` (`:479`) = **three** calls, ~97 ms wasted.

**Attribution matters here**: this predates migration 0009. `claude2/3/4` already called `claude()`,
which already synced; the router adds no fourth call and no new sync. It is a pre-existing ~50 ms
tax on accounts 2/3/4, not a regression from the split. Removing it means dropping the wrapper-side
call (the pinned body's `:479` covers it) — but note the wrapper's call is what makes `_cc_oauth_token_env`
run before `_cc_route_check` forks git, so verify that ordering before deleting.

### D6 — LOW · documentation overclaim · **the kill switch is not silent**

`CC_CLAUDE_ROUTE=off` sets `_CC_ROUTE_NOTE='routing off (CC_CLAUDE_ROUTE)'` (`:49`), and `:121` prints
it on every launch when stderr is a TTY. Behaviour is identical to the pinned path, but the lib
header (`:29`) and the migration (`:38`) both say **"byte-identical pinned behaviour"** — it is not
byte-identical on stderr. Trivial to fix (return before setting the note, or exclude the off-note
from the print), or just correct the two comments.

### D7 — LOW · observation · **`claude -p` typed at an interactive zsh prompt routes**

`claude -p hello` → routes and fires a phantom `--assign`, because `-p` is not in the resume set.
Reachable only from an interactive zsh; hooks, launchd jobs and scripts all get
`/Users/chrisren/Library/pnpm/claude` (the binary), so the automated fleet cannot hit it. Rate is
whatever the operator/agent types by hand. If it matters, add `-p`/`--print` to the non-routing set.

### D-obs — needs an intent ruling, not a fix · **`claude-desk` now routes**

`desk.zsh:67` calls bare `claude`, so `claude-desk` (unlike `claude-desk2/3/4`) picks a different
account per launch. `desk-register` claims `~/.claude/cc-roles/desk` *before* the launch
(`desk.zsh:51` notes the ordering is load-bearing), so the role file is written without knowing which
account will win. If any consumer of the desk role assumes the desk lives on account 1, this is now
false. Not a launcher bug — a scope question the split's design did not state either way.

---

## 5. Corroboration for the "unexpected account" agent (measured, not my finding to own)

Three consecutive read-only `claude-accounts --route interactive --max-wait 0 --max-age 600` calls
returned **`next2`**, then **`next`** — with stderr reading
`interactive excluded — next=poll throttled ↻ (cached usage); next4=poll throttled ↻ (cached usage); next3=kmax-concurrency`
and, on the later call, `interactive excluded — next3=poll throttled …; next2=poll throttled …`.
The pick is dominated by **exclusions** (poll-throttle staleness + concurrency), not by runway, and it
flips between adjacent invocations. The launcher is faithfully reporting what the router returns;
the surprise lives in the exclusion logic, not in `claude-launcher.zsh`.

---

## 6. What I checked and cleared (so it is not re-audited)

- Ordering invariant, including `.zlogin`/`.zprofile`/`.zshenv` and every lib under `~/.claude/lib/`.
- Nothing in `bin|scripts|hooks|lib` re-sources `~/.zshrc` (so D1 has no automated trigger — only the operator).
- All five resume spellings; both `cc` strategies; `ccr`'s version-matched resume; `cc-prev`.
- `CC_ACCOUNT_PINNED` visibility, export semantics, and non-persistence in the caller.
- Every `CMD=` shape in `handoff-fire.sh` carries `${PREFIX}` (6/6).
- Teammate panes (`claude.exe`) and hook/launchd paths cannot reach the function.
- `emulate -L zsh` option delta.
- Router stdout/stderr separation and `--max-wait 0` bounding.
