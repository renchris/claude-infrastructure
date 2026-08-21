# The enforcing store for Claude Code permission settings on this box

Read-only investigation, 2026-08-20. Nothing was modified. Binary evidence read from
`~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (CC 2.1.220, the version
every live `claude.exe` on this box is running).

**The one-line answer.** There is no single enforcing store. There are **five independent
`settings.json` files** — one per config dir, all REAL files, none symlinked, already forked — and
the mirror that is supposed to unify them is *structurally incapable* of healing them. Of the three
permission arrays, **`deny` and `ask` have a git-backed sanctioned edit path and are in perfect
parity; `allow` has neither** and has drifted to 339/339/338/338/338.

---

## 0. The 339-vs-255 discrepancy — RESOLVED FIRST

**VERDICT: not a fork, not a dedupe, not a second `permissions` block. `255` is the count of
`Bash(...)` rules; `339` is the count of ALL rules. Both reads are correct and they measure
different populations.**

```
prefix breakdown of ~/.claude/settings.json .permissions.allow (339 entries):
  Bash       255   ← the audit tool's number
  WebFetch    74
  Skill        2
  Edit/Glob/Grep/MultiEdit/Read/SendMessage/WebSearch/Write   1 each  (8)
                   ---
                   339
```

Every hypothesis in the brief was tested and refuted:

| Hypothesis | Test | Result |
|---|---|---|
| duplicate entries in `allow` | `len(list)` vs `len(set(list))` | 339 vs 339 — **zero duplicates** |
| `permissions` block appearing twice | `raw.count('"permissions"')` | **1** in all five files |
| comments / non-JSON | `json.load()` | parses clean, no JSONC |
| tool deduping/filtering | prefix census | **filtering — to `Bash(` only** |

So the audit tool is filtering to Bash rules (correct for a Bash-prompt audit) and the raw read is
counting the whole array. `255 + 74 + 10 = 339` closes exactly. No file is lying.

---

## 1. INVENTORY

**VERDICT: 5 live permission stores, all REAL files (zero symlinks), all with distinct inodes and
distinct bytes. `deny` (41) and `ask` (6) are IDENTICAL across all five. `allow` has DIVERGED —
one named rule is missing from three of the five. Enterprise/managed policy does not exist on this
box. No `settings.local.json` exists in any config dir.**

### 1a. User-level config dirs

| Path | symlink? | bytes | mtime | allow | deny | ask |
|---|---|---|---|---|---|---|
| `~/.claude/settings.json` | **NO** (real) | 36496 | 2026-08-18 18:24:58 | **339** | 41 | 6 |
| `~/.claude-next/settings.json` | **NO** (real) | 35530 | 2026-08-20 15:58:08 | **339** | 41 | 6 |
| `~/.claude-secondary/settings.json` | **NO** (real) | 36483 | 2026-08-20 15:58:08 | **338** | 41 | 6 |
| `~/.claude-tertiary/settings.json` | **NO** (real) | 36513 | 2026-08-20 15:58:09 | **338** | 41 | 6 |
| `~/.claude-quaternary/settings.json` | **NO** (real) | 36527 | 2026-08-20 15:58:09 | **338** | 41 | 6 |

`realpath == path` for all five — **not one of them is a symlink into the repo.** This is the
central fact of this whole report.

### 1b. The divergence, shown

```
.claude  −  .claude-secondary  =  ['Bash(kitten @ send-text:*)']
.claude-secondary  −  .claude  =  []
.claude  −  .claude-next       =  []      ← .claude and .claude-next are permission-identical
```

One rule, `Bash(kitten @ send-text:*)`, is present in `~/.claude` and `~/.claude-next` and **absent
from secondary, tertiary and quaternary**. It is a strict-subset fork, not a two-way divergence.
`deny` and `ask` are set-identical across all five (verified by symmetric difference — empty both
directions, all four comparisons).

Non-permission divergence also exists and is worth knowing before any edit:

```
only in .claude-next : ['enableAllProjectMcpServers']
DIFF effortLevel : .claude='medium'   .claude-next='low'
DIFF tui         : .claude='default'  .claude-next='fullscreen'
DIFF attribution : .claude-next carries an extra 'sessionUrl': False
```

`defaultMode` is `auto` in **all five**, with a 30-entry `autoMode.soft_deny` block in all five.
This matters for the lead's plan: under `defaultMode=auto` an allowlist entry is not the only thing
standing between a command and a prompt — the auto classifier is also in the path.

### 1c. Version dirs — NOT permission stores

`~/.claude-156 · -161 · -170 · -183 · -219 · -220` each contain exactly
`node_modules/ package-lock.json package.json` — they are **binary version pins, not config dirs**.
No `settings.json` in any of them. `~/.claude-versions/` holds `2.1.113 2.1.114 2.1.183 current
MANIFEST.jsonl` — same story. Rule them out entirely.

### 1d. Project layer (claude-infrastructure)

| Path | tracked? | allow | deny | ask |
|---|---|---|---|---|
| `.claude/settings.json` | **YES** (`git ls-files`) | 35 | 0 | 0 |
| `.claude/settings.local.json` | **NO** — gitignored (`.gitignore:20`) | 92 | 0 | 0 |
| `settings-templates/settings.example.json` | **YES** | 17 | **41** | **6** |

The template's `deny`=41 and `ask`=6 match the live dirs **exactly**. That is not a coincidence —
see §3.

### 1e. Worktrees

`git worktree list` reports 88 worktrees, **63 of them under `/Users/chrisren/Development/.worktrees/`**.
Their `.claude/settings.json` is a *tracked* file, so each carries whatever its branch had:

```
wt-cb6701bf2217  (claude-infrastructure)  allow=5   ← main currently has 35
wt-cc-224603-79662 (reso-management-app)  allow=78
wt-pool-1          (reso-management-app)  allow=82
```

Verified by `git config --get remote.origin.url` per worktree — the 78/82-allow files belong to
**reso**, not this repo. Stale claude-infrastructure worktrees carry stale *project* permissions
(5 vs 35), but this layer is git-tracked and therefore self-healing on rebase. It is not the
problem surface.

### 1f. Enterprise / managed policy

```
ls: /Library/Application Support/ClaudeCode/: No such file or directory
ls: /Library/Application Support/ClaudeCode/managed-settings.json: No such file or directory
```

**Absent.** No managed policy layer exists on this box. The binary does support one — it carries a
`"policySettings"` source label (154 occurrences) alongside `"userSettings"` (201),
`"projectSettings"` (111), `"localSettings"` (148), `"flagSettings"` (79) and `"cliArg"` (24) —
so the layer is available if we ever want a truly un-forkable store. **It is currently unused.**

### 1g. `settings.local.json` in config dirs

`ls ~/.claude*/settings*.json` returns **exactly five files**, all named `settings.json`. No
`settings.local.json` exists at the user level anywhere. One less fork surface.

---

## 2. THE MIRROR

**VERDICT: the mirror is `lib/config-mirror.zsh`, function `_cc_sync_account` / `_cc_sync_config_mirror`.
It is a SYMLINK-ONLY mirror running one-way `~/.claude` → each `~/.claude-*`. It would NOT overwrite
a hand-edit — because in its normal (safe) mode it refuses to touch a forked real file AT ALL. That
refusal is the bug: `settings.json` is a forked real file in all four mirror dirs, so the mirror
walks past it on every single run, forever. The known open item is REAL, filed, and the durable
half of it is UNFIXED.**

### 2a. What it is

| | |
|---|---|
| SSOT | `/Users/chrisren/Development/claude-infrastructure/lib/config-mirror.zsh` (264 lines) |
| Live path | `~/.claude/lib/config-mirror.zsh` → symlink into the repo (verified) |
| Entry points | `~/.zshrc` (every interactive launch) **and** `hooks/config-mirror-assert.sh` (SessionStart) |
| Direction | **one-way, `~/.claude` → `~/.claude-{next,secondary,tertiary,quaternary}`** |
| Mechanism | `ln -sfn` — it creates **symlinks**, it never copies file content |

`hooks/config-mirror-assert.sh:13` is the "knowledge-layer mirror re-asserted" message the lead saw:

```bash
zsh -fc "source \"$HOME/.claude/lib/config-mirror.zsh\"; _cc_sync_account \"$cfg\"" ...
printf '{"hookSpecificOutput":{... "knowledge-layer mirror re-asserted for %s ..."}}\n' "${cfg##*/}"
```

Note `config-mirror-assert.sh:11` — `[ "$cfg" = "$HOME/.claude" ] && exit 0   # the source itself`.
`~/.claude` is the designated source; the other four are the mirrors.

### 2b. Why it can never heal a forked settings.json

`lib/config-mirror.zsh:111-115` is the whole story:

```zsh
if [[ -e "$dst/$name" && ! -L "$dst/$name" ]]; then   # a forked real file/dir
  (( convert )) || continue                           # safe mode: don't touch it
  mv -f "$dst/$name" "$dst/$name.premirror-bak" 2>/dev/null
fi
ln -sfn "$e" "$dst/$name"
```

Every mirror dir's `settings.json` **is** "a forked real file". Both live callers — the zshrc
launcher and the SessionStart hook — run in **safe mode** (`config-mirror-assert.sh:6-7` says so
explicitly: *"runs the mirror in default (no --convert) mode"*). So the branch taken is `continue`.
The mirror sees the fork, correctly declines to destroy it, prints "re-asserted", and moves on.

**It has been printing a success message about a file it structurally cannot reach.** The message
is true (the *mirror* was re-asserted) and useless (settings.json was never in scope).

The only thing `config-mirror.zsh` does with `settings.json` is a **read-only grep** at line 148:

```zsh
grep -qE '"(ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN|CLAUDE_CODE_OAUTH_TOKEN|apiKeyHelper|forceLoginMethod|forceLoginOrgUUID)"' "$src/settings.json" \
  && print -u2 "⚠️  config-mirror: shared settings.json has an account-pinning auth key ..."
```

The comment calls it *"the SHARED settings.json"*. **It is not shared.** That comment encodes the
design intent; the five distinct inodes are the measured reality. The intent-vs-reality gap is the
finding.

`--convert` mode *would* heal it — by `mv`-ing each dir's real settings.json to `.premirror-bak` and
symlinking. It is invoked only by a manual, `lsof`-guarded one-shot that requires all of that
account's panes closed, and it has evidently never been run against settings.json.

### 2c. The OTHER writer — `kitty-setup.sh`, and it churns

The 15:58:08/09 mtimes on the four mirror dirs are not the mirror. They are
`scripts/kitty-setup.sh`, identified by the backup files it leaves:

```
~/.claude-next/settings.json.bak-kitty-20260820155714
~/.claude-next/settings.json.bak-kitty-20260820155721
~/.claude-next/settings.json.bak-kitty-20260820155727   ... (11 in a 2-minute window)
```

Backup census across the five dirs:

```
.claude: 167 · .claude-next: 347 · .claude-secondary: 364 · .claude-tertiary: 384 · .claude-quaternary: 393
                                                                        = 1,655 backup files
```

A `python3 -m json.tool` diff of the 15:57:14 backup against the current file is **empty** — it
rewrote the file with zero semantic change. So `kitty-setup.sh`:

- **is a live writer of all five settings.json files** (via a jq round-trip; it normalises
  `teammateMode`, `kitty-setup.sh:438`),
- **is content-preserving** — a hand-edit survives its round-trip,
- **does NOT propagate** — it rewrites each dir independently and so cannot heal the fork,
- **litters 1,655 stale backups**, which is its own (minor, separable) problem.

It is not the source of the `kitten @ send-text` rule — `grep "kitten @ send-text" scripts/kitty-setup.sh`
returns nothing. That rule was added by hand or via the `update-config` skill, to two dirs only.

### 2d. The open item — found, and its status is split

Prose reference: `docs/plans/START_LATENCY_ROUTER.md:93` —
*"Related known item: config-mirror never heals a forked settings.json."*

The backlog row is **`4ce34a4f703c`** (`~/.claude/autonomy/backlog.jsonl`):

> *"LIVE EXPOSURE: hook-wiring parity across the 5 config dirs has NO checker, and a PERMISSION RAIL
> is missing from 2 of 5. … the fleet picks a config dir BY ACCOUNT at fire time, so the guardrail
> set a session gets is a side effect of quota routing — **what a session MAY DO depends on which
> account fired it.**"*

```
status : done          (first 2026-07-30T04:07:15Z, last 2026-08-11T06:55:55Z)
needs  : "persistent thrash — 2 fast claim→reopen cycle(s) (spawn-fail / land-conflict rebase-exit-5);
          the worker cannot land. Investigate the root cause, then `cc-backlog unblock 4ce34a4f703c`."
```

**Read that carefully — `status:done` is misleading and the `needs` field contradicts it.** The
item is done-latched *and* carries an unresolved thrash note. Its evidence field is explicit that
the premise was **partly refuted**:

> *"the checker already existed (`scripts/settings-drift-assert.sh`, correct, with a selftest) and had
> ZERO callers, so 'no checker' was functionally right but pointed at the wrong fix; drift was 1-of-5
> not 2-of-5 … **Root cause found and filed: `.claude-next/hooks` is the only forked real hooks dir;
> the other 3 account dirs symlink and converge for free.** Operator step filed 2d37bafcf65f (run 0009)."*

So: the **detection** half shipped (`e24906da` `--file` mode, `75f04db8` the caller in
`autonomy-sweep`, `a19e3d9c` migration 0009). The **healing** half did not, and migration 0009 is
an unrun operator step (`2d37bafcf65f`).

Running the checker right now confirms the hooks half is still open:

```
$ bash scripts/settings-drift-assert.sh
DRIFT [hooks] "PreToolUse|cc-unattended-ask-guard.sh"      — missing in: .claude-next
DRIFT [hooks] "PreToolUse|coldcompile-admit.sh"            — missing in: .claude-next
DRIFT [hooks] "SessionEnd|session-deregister.sh"           — missing in: .claude-next
DRIFT [hooks] "SessionStart|desk-brief-inject.sh"          — missing in: .claude-next
DRIFT [hooks] "Stop|session-beat.sh stop"                  — missing in: .claude-next
DRIFT [hooks] "UserPromptSubmit|handed-off-session-guard.sh" — missing in: .claude-next
DRIFT [hooks] "UserPromptSubmit|session-beat.sh prompt"    — missing in: .claude-next
settings-drift-assert: DRIFT — 7 divergence(s) across 5 config dirs
```

**7 hook divergences, all in `.claude-next`, all still live today.** And note what the checker does
NOT report: **zero `deny` drift, zero `ask` drift** — consistent with §1b.

🚨 **The checker is blind to the `allow` fork.** `scripts/settings-drift-assert.sh:31-32` defines
only `sig_deny()` and `sig_ask()`; there is no `sig_allow()`. That is why our one-rule `allow`
divergence does not appear above. It is a deliberate-looking omission (an `allow` diff is noisy and
low-risk relative to a missing `deny`), but it means **no automated sensor on this box is watching
the array the lead wants to change.**

And the checker itself is **UNWIRED at the settings layer**: `grep -c settings-drift-assert` returns
**0** in all five `settings.json` files. Its only caller is `autonomy-sweep` (per the backlog
evidence), not a SessionStart hook.

---

## 3. THE SANCTIONED EDIT PATH

**VERDICT: it depends entirely on WHICH array. For `deny` and `ask` there is a real, git-backed,
all-accounts sanctioned path — `settings-templates/settings.example.json` + `install.sh --wire-hooks`.
For `allow` there is NO sanctioned path at all: `install.sh` unions `deny` and `ask` and pointedly
does not union `allow`. That is exactly why deny/ask are at perfect parity and allow has forked.**

### 3a. The symlink chain — there isn't one

The brief asks to "show the symlink chain for the settings file(s)." **There is no chain.** All five
are real files whose `os.path.realpath()` equals their own path. `~/.claude` is a per-file symlink
layer for `hooks/ bin/ scripts/ commands/ lib/` — `~/.claude/lib/config-mirror.zsh` really does point
at the repo — but **`settings.json` was never included in that layer.** Editing a repo file cannot
reach any of the five.

### 3b. The path that works, for deny/ask

`install.sh:987-1025` is the mechanism:

```
# The FULL live hook roster lives in settings-templates/settings.example.json (G-P6-7) …
# This ADDITIVELY merges the template's .hooks (adds missing EVENTS only — never clobbers a
# populated event) + unions .permissions.deny/.ask into $CONFIG_DIR/settings.json.
# (Merging settings.json is the OPERATOR's hand via this installer — never an agent Write; the
#  C10 ceiling holds.)
```

```jq
.hooks = ($t.hooks + (.hooks // {}))
| .permissions = (.permissions // {})
| .permissions.deny = (((.permissions.deny // []) + ($t.permissions.deny // [])) | unique)
| .permissions.ask  = (((.permissions.ask  // []) + ($t.permissions.ask  // [])) | unique)
```

`install.sh:1023-1024`. **`.permissions.allow` does not appear.** The template's 17 `allow` entries
are seeded only on a *fresh* dir, where `install.sh:1018` sets `base="$clean_tmpl"` because no
target exists. On every subsequent run, `base` is the existing file and `allow` is never touched.

Targeting is per-dir: `install.sh:28` — `--config-dir) CONFIG_DIR="$2"`, default `$HOME/.claude`
(`install.sh:20`), opt-in merge via `--wire-hooks` (`install.sh:29`). So all-accounts coverage is
five invocations, one per dir, each with `--config-dir`.

This checks all three of the lead's boxes for deny/ask:

| Requirement | Met? | How |
|---|---|---|
| (a) applies to all 4 accounts | ✅ | `--config-dir` once per dir; union is idempotent |
| (b) survives the mirror | ✅ | the mirror never touches settings.json (§2b); kitty-setup round-trips content-preservingly (§2c) |
| (c) lands in git | ✅ | `settings-templates/settings.example.json` is a tracked file |

**Evidence it works: template `deny`=41/`ask`=6 vs live `deny`=41/`ask`=6 in all five dirs, zero
drift reported by the checker.** This path is not theoretical; it is the reason the safety arrays
are healthy.

### 3c. The gap, stated plainly

To add an **`allow`** rule that satisfies (a)+(b)+(c) today, **one of these must happen first**:

1. **Extend the union** — add
   `.permissions.allow = (((.permissions.allow // []) + ($t.permissions.allow // [])) | unique)`
   to the `install.sh:1020-1025` jq, and move the 322 organically-grown rules into the tracked
   template. Smallest diff, reuses a proven mechanism, immediately gives `allow` the same
   git-backed store `deny`/`ask` already have. **This is the recommended path.**
2. **Symlink settings.json into the repo layer** — the mirror's *original* intent (`config-mirror.zsh:146`
   still calls it "the SHARED settings.json"). Requires `--convert` with all panes closed, and it
   would forcibly unify the four non-permission divergences in §1b (`effortLevel`, `tui`,
   `enableAllProjectMcpServers`), which are plausibly intentional. Higher blast radius.
3. **Managed policy** (`/Library/Application Support/ClaudeCode/managed-settings.json`) — the binary
   supports it (`"policySettings"`, §1f) and it is the only layer a per-dir fork cannot override.
   Needs root, is invisible to git, and is the right tool for rules that must be *un-revertable*
   rather than merely *consistent*.

Per this repo's `.claude/CLAUDE.md`: whichever is chosen, the edit is made **in a dedicated worktree
on its own branch and landed via the project-local `/ship`** — never committed in the shared
checkout. And per `install.sh:993-994`, running the installer is **the operator's hand, not an agent
Write** (the C10 ceiling) — an agent must not directly `Write` a live `settings.json`.

---

## 4. LIVE RELOAD

**VERDICT: YES — a running session DOES re-read settings.json on change. CC 2.1.220 ships a settings
watcher. The critical constraint: it only watches directories that already contained a settings file
when that session started. All five config dirs qualify, so an edit to any of them reaches every
live session on that dir WITHOUT a recycle.**

Verbatim string from `claude.exe` (2.1.220):

> **"If proof fails but pipe-test passed and `jq -e` passed: the settings watcher isn't watching
> `.claude/` — it only watches directories that had a settings file when this session started. The
> hook is written correctly. Tell the user to open `/hooks` once (reloads config) or restart — you
> can't do this yourself; `/hooks` is a user UI menu and opening it ends this turn."**

Reproduce: `strings -a ~/.claude-220/.../bin/claude.exe | grep -a "settings watcher"` → exactly 1 hit.

Three things follow, and the second is the one that decides the lead's plan:

1. **A settings watcher exists.** The sentence is a troubleshooting branch for the *failure* case,
   which means the success case — watcher picks up the change — is the norm.
2. **The watch set is fixed at session start, by directory.** The failure mode described is a
   *project* `.claude/` that did not exist when the session began. Every one of our five user config
   dirs has had a `settings.json` continuously for months, so **every live session is watching its
   own config dir.** An edit propagates.
3. **`/hooks` is the manual reload**, and it is operator-only — an agent cannot self-trigger it
   ("you can't do this yourself … opening it ends this turn"). That is the fallback if a watcher
   miss is ever suspected.

**Honest limits on this evidence.** The string is an internal troubleshooting instruction, not a
spec, and it is stated in terms of *hooks* reloading. I did not find a separate string proving the
**permissions** array specifically is re-read on the same event, and I did not run an empirical
A/B — doing so would have required writing to a settings file, which the brief forbids. Treat
"permissions reload live" as **strongly indicated, not proven.** If the lead needs certainty before
relying on it, the cheap decisive test is a scratch `CLAUDE_CONFIG_DIR` in `/tmp` with its own
`settings.json`, which touches no live store.

Corroborating repo note, for the config-*dir* layer (a different thing, and here the answer is the
opposite): `hooks/config-mirror-assert.sh:6-7` —

> *"A hook fires AFTER config is loaded, so it fixes the NEXT session, not the running one — the
> launcher wrapper is the primary mechanism; this is belt-and-suspenders."*

**Live session census.** Unreliable and I will not quote a number as fact: three consecutive
`ps`/`pgrep` passes returned 3, 6 and 9 `claude.exe` processes. `pgrep` structurally excludes the
caller's own ancestors (a known lesson in this repo's memory index), and `ps eww` cannot read env
for every process. Directionally, live sessions sit on `~/.claude` (majority, `CLAUDE_CONFIG_DIR`
unset) and `~/.claude-next`, with secondary/tertiary/quaternary quiet at the time of measurement.
**Whichever dirs are live, the fix must be applied to all five** — the fleet picks a config dir by
account at fire time, so tomorrow's routing changes which one matters.

---

## 5. HOOK LAYER

**VERDICT: three of the four permission hooks are WIRED + ACTIVE and identically wired in all five
dirs. `model-permission-decider.py` is UNWIRED — zero references in any settings.json — and that is
DELIBERATE, documented, not an oversight. And yes: `validate-bash.sh`'s `ask` verdicts are
indistinguishable from ordinary permission prompts in beacon data.**

Wiring census — `grep -c <hook> ~/.claude*/settings.json`, identical in **all five** dirs:

| Hook | refs/dir | Status |
|---|---|---|
| `smart-bash-allowlist.sh` | 1 | **WIRED + ACTIVE** |
| `validate-bash.sh` | 1 | **WIRED + ACTIVE** |
| `ship-rail-push-allow.sh` | 1 | **WIRED + ACTIVE** |
| `cc-permission-beacon.sh` | 4 | **WIRED + ACTIVE** (4 events) |
| `model-permission-decider.py` | **0** | **UNWIRED — deliberately** |

Exact registrations (from `~/.claude/settings.json` `.hooks`):

```
PreToolUse        matcher='Bash'  timeout=5   ~/.claude/hooks/smart-bash-allowlist.sh
PreToolUse        matcher='Bash'  timeout=10  ~/.claude/hooks/validate-bash.sh
PreToolUse        matcher='Bash'  timeout=5   ~/.claude/hooks/ship-rail-push-allow.sh
PostToolUse       matcher=''      timeout=5   ~/.claude/hooks/cc-permission-beacon.sh clear
SessionEnd        matcher='*'     timeout=5   ~/.claude/hooks/cc-permission-beacon.sh clear
Stop              matcher='*'     timeout=5   ~/.claude/hooks/cc-permission-beacon.sh clear
PermissionRequest matcher=''      timeout=5   ~/.claude/hooks/cc-permission-beacon.sh write
```

### 5a. `model-permission-decider.py` — UNWIRED, and that is the intended state

`docs/research/model-in-the-loop-permissions-2026-08-12.md:223` — **`## 6. Status — SHADOW by
default, not wired`**, and `:229` — *"It is deliberately not wired. Arming an auto-approver whose
`allow` bypasses the permission system…"*.

It **would** auto-approve via `PreToolUse permissionDecision` if armed —
`hooks/model-permission-decider.py:421-429` emits `allow` or `ask`, and `:516`
`return finish("allow", detail or "model approved", consulted=True)`. Its own header (`:13-17`) is
emphatic that **`deny` is deliberately unreachable** — "a wrong `deny` wedges the session with no
human in the loop; a wrong `ask` costs one prompt."

Its header also carries the single most important measured fact for anything the lead does here
(CC 2.1.220, nine isolated arms):

> **"A hook emitting `allow` BYPASSES the permission system COMPLETELY. In the experiment an `allow`
> sailed past the allowed-working-directory write guard, which is a hard rule and not merely an
> `ask` entry."**

And a second, for any hook we touch:

> *"A PreToolUse hook that exceeds its `timeout` has its verdict DISCARDED and the harness falls
> through to the normal permission flow … the timeout is SILENT: nothing on stderr, nothing in the
> transcript, no notice to the model."* Under `defaultMode=auto` (which is our state, §1b) *"a
> timeout degrades to AUTO-MODE'S CLASSIFIER"*, not to the human.

Only one non-research reference to the file exists anywhere outside `docs/research/`
(`docs/research/workflows-vs-teams-2026-08-20/W6:167` confirms it is a permission passthrough, not a
gate). Its single commit is `112323297`. There is **no activation script** for it in
`docs/activation/pending-activation/` — the only permission-adjacent one there is
`17-permission-beacon-wire-activate.sh`.

### 5b. `smart-bash-allowlist.sh` — WIRED + ACTIVE, and it is an auto-approver

`hooks/smart-bash-allowlist.sh:91-94` emits `"permissionDecision": "allow"`. Its own header
(`:24`) repeats the warning: *"A PreToolUse hook emitting 'allow' BYPASSES the permission system."*
It runs **first** in the Bash chain (`:8` — *"Runs BEFORE validate-bash.sh in the hooks array"*) and
`:6` says it *"refuses to emit 'allow' if any match"* against a guard set. Kill switch:
`SMART_ALLOWLIST_DISABLED=1`.

**This is a second, parallel allowlist** — a rule can be auto-approved here without appearing in any
`settings.json` `allow` array. Any measurement of "which commands still prompt" must account for it.
Per `docs/research/model-in-the-loop-permissions-2026-08-12.md:155`, it already auto-allows **38
(3.5%)** of the sampled prompt population.

Backlog `ae0025d4bacc` ("wire the committed-but-INERT allow hooks: ship-rail-push-allow.sh +
smart-bash-allowlist.sh … referenced in ZERO settings.json PreToolUse configs") is **`status: done`,
`wasDone: true`, evidence `65e1d6e`, closed 2026-07-19T11:15:29Z** — and the live census above
independently confirms the closure. Both are wired now.

### 5c. `validate-bash.sh` — WIRED + ACTIVE, and YES it pollutes the prompt data

1,184 lines. Two emitters, `hooks/validate-bash.sh:101-115`:

```bash
deny() { ... "permissionDecision": "deny"  ... exit 0; }   # 29 call sites (+ deny_catastrophic_rm ×2)
warn() { ... "permissionDecision": "ask"   ... exit 0; }
```

**≈31 distinct deny paths.** Direct answer to the lead's question:

- **`ask` verdicts → YES, they look exactly like permission prompts.** `warn()` emits the same
  `permissionDecision: "ask"` the permission system emits, it reaches the human under
  `defaultMode=auto` (measured, per §5a), and it will fire the `PermissionRequest` event that
  `cc-permission-beacon.sh write` is registered on. **Beacon-derived prompt data contains
  validate-bash `ask` events that no `settings.json` `allow` rule can ever suppress** — they are
  emitted before, and independently of, the allowlist.
- **`deny` verdicts → NO.** A `deny` short-circuits the tool call; there is no `PermissionRequest`
  and the beacon never writes.

**Implication for the lead's allowlist plan:** any prompt in the data whose cause is a
`validate-bash.sh` `warn()` will **not** be fixed by adding an `allow` rule. Those need a
`validate-bash.sh` change instead. Segment the data by cause before sizing the allowlist diff, or
the change will under-deliver and the miss will look like the allowlist "not taking effect" — which
would send the next investigation straight back to the mirror.

### 5d. `cc-permission-beacon.sh` — WIRED + ACTIVE, observer only

254 lines, **zero** `permissionDecision` emissions — it decides nothing. It is the instrument:
`write` on `PermissionRequest`, `clear` on `PostToolUse`/`Stop`/`SessionEnd`. It is the most heavily
wired of the four (4 events × 5 dirs) and is presumably the source of the prompt data in play.

---

## 6. Adversarial pass — what I checked because it would have been easy to miss

| Assumption worth attacking | Checked | Outcome |
|---|---|---|
| "339 vs 255 is a fork" | prefix census | **Refuted** — same file, different populations (§0) |
| "the mirror overwrites hand-edits" | read `config-mirror.zsh:111-115` | **Refuted, and inverted** — it can't even *reach* settings.json |
| "the 15:58 mtimes are the mirror" | `.bak-kitty-*` files | **Refuted** — `kitty-setup.sh`, a separate undocumented writer (§2c) |
| "the drift checker covers this" | read `settings-drift-assert.sh:31-32` | **Confirmed gap** — no `sig_allow()`; blind to the exact fork we care about |
| "`allow` and `deny` share an edit path" | read `install.sh:1020-1025` | **Refuted** — deny/ask unioned, allow excluded. Root cause of the fork (§3c) |
| "the settings file is a repo symlink" | `os.path.realpath` ×5 | **Refuted** — zero symlinks |
| "version dirs might carry settings" | `ls ~/.claude-1??` | **Refuted** — binary pins only |
| "worktree settings are our fork surface" | `remote.origin.url` per worktree | **Refuted** — 78/82-allow files are reso's; ours are tracked and self-healing |
| "only settings.json gates permissions" | read `smart-bash-allowlist.sh` | **Confirmed second allowlist** outside settings.json entirely (§5b) |
| "an allowlist entry prevents the prompt" | read validate-bash emitters + defaultMode | **Partly false** — validate-bash `ask` and the `autoMode` classifier both sit upstream (§5c) |
| "backlog `status:done` means resolved" | read the `needs` field | **Refuted** — done-latched *with* an unresolved thrash note (§2d) |

**Named uncertainties, not papered over:**

1. **Permissions-specific live reload is indicated, not proven** (§4). The watcher string is stated
   in terms of hooks. A scratch-dir A/B would settle it without touching a live store.
2. **Live session count is not a number I can defend** (§4) — three passes gave 3/6/9.
3. **Who added `Bash(kitten @ send-text:*)` to two dirs only is unresolved.** Not `kitty-setup.sh`
   (grep is empty). Most likely a hand-edit or the `update-config` skill applied without the
   five-dir loop — which is precisely the failure mode this whole report describes.
4. **`autoMode.soft_deny` (30 entries, all five dirs) is unexamined.** Under `defaultMode=auto` it is
   in the decision path and could independently explain prompts an allowlist won't touch.
