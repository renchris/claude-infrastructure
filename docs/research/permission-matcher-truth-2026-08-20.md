# Permission-matcher ground truth — Claude Code 2.1.220

**Date:** 2026-08-20 · **Author:** `matcher-truth` research subagent
**Binary inspected:** `/Users/chrisren/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe`
— `package.json` version **2.1.220** (Bun SEA, 256,908,272 bytes). This is the binary every live
session on this box runs (`ps aux` → all 15 sessions are `.claude-220/node_modules/.bin/claude`).
`~/.claude-versions/current` → 2.1.114 is **stale and not what runs**; 2.1.183 is also installed.
Method: `strings -a -n 6` → 412,384 lines (the minified JS payload is present in the clear);
byte-window extraction around identifiers. Docs read as a *claim*; every conflict resolved by
measurement.

**Probes:** 7 headless runs in `/private/tmp/permprobe` (throwaway git repo), each
`claude -p … --settings <crafted> --output-format stream-json`. No real settings file touched.
Raw transcripts: `/private/tmp/permprobe/run{A..I}.jsonl`.
🚨 **Probe-reading correction that matters:** the `result` line's `permission_denials[]` array does
**not** capture every refusal. Hard denies surface only as a `tool_result` with
`is_error: true` (`<tool_use_error>File is in a directory that is denied…</tool_use_error>`).
An early read of run E/F using `permission_denials` alone showed "everything allowed" and was
**wrong**. All verdicts below are re-derived from the `is_error` channel.

---

## Map of the code (identifier → role)

| Minified symbol | Role |
|---|---|
| `sW_(input, ctx, classifier)` | **main Bash permission evaluator** |
| `Knr` / `tPt` | tree-sitter parse → `{kind:"simple"\|"too-complex", commands[], bareAssignmentNames[]}` |
| `MT(cmd)` | splits a command string into leaf sub-commands |
| `wEd` / `gEd` | per-sub-command evaluation |
| `Rko` | whole-command **exact**-mode rule check |
| `v7e` | runs deny → ask → allow rule sets for Bash |
| **`ALs`** | **the Bash rule matcher** (the thing this document is about) |
| `Cko`=`OTo` | rule-value parser → `{type:"exact"\|"prefix"\|"wildcard"}` |
| `mtn` | `/^(.+):\*$/` → prefix extraction |
| `tCs` | is-wildcard test (unescaped `*` present, and does *not* end in `:*`) |
| `ffe` / `t2t` | glob→regex matcher |
| `iae` | command normalisation (comments, env prefixes, wrapper stripping, first-token unquoting) |
| `$fe` / `XTe` | rule collection by tool + behaviour (this is where union-vs-override lives) |
| `pme` / `gL` / `jfe` | allow / deny / ask rule producers |
| `gsn`/`_sn`/`qNt` | **auto-mode "dangerous allow rule" drop predicate** |
| `Tap` / `k$y` / `_4r` | file-rule path anchoring |
| `$A` | file-path rule matcher (gitignore engine) |
| `aBc` | permission-mode resolution + precedence |
| `j2s` / `W2t` / `XOd` | **PowerShell** matcher (`Vi="PowerShell"`) — *not* Bash. Do not confuse. |

---

## 1. `Bash(<x>)` rule syntax

> **VERDICT:** There are exactly **three** rule types, chosen by the rule *string*, not by the tool:
> `<x>` ending in `:*` → **prefix**; `<x>` containing an unescaped `*` anywhere else → **wildcard
> glob**; otherwise → **exact literal**. Matching is against the *sub-command* string (never the raw
> compound string, except one narrow exact-mode pass), is **case-SENSITIVE** for Bash, is
> **whitespace-normalised for prefix and wildcard rules but NOT for exact rules**, and runs after a
> normalisation pass that strips comments, wrappers, redirections and a fixed env-var allowlist.

### The parser (`OTo`, offset 17820883)

```js
function OTo(e){
  let t = mtn(e);                       // /^(.+):\*$/
  if (t !== null) return {type:"prefix",   prefix: t};
  if (tCs(e))     return {type:"wildcard", pattern: e};
  return                 {type:"exact",    command: e};
}
function mtn(e){ return e.match(/^(.+):\*$/)?.[1] ?? null }
function tCs(e){ if(e.endsWith(":*")) return false;
                 /* true iff some `*` has an even number of preceding backslashes */ }
```

### The matcher (`ALs`, offset 19883790) — the authoritative text

```js
case "exact":    return f.command === m;                       // strict ===, no normalisation
case "prefix": {
  let g = f.prefix.replace(/[ \t]+/g," "), _ = m.replace(/[ \t]+/g," ");
  if (r === "exact")  return g === _;
  if (d.get(m))       return false;                            // ← COMPOUND ⇒ no match (see §2)
  if (_ === g)                 return true;
  if (_.startsWith(g + " "))   return true;
  let y = "xargs " + g;
  if (_ === y)                 return true;
  return _.startsWith(y + " ");
}
case "wildcard":
  if (r === "exact") return false;                             // wildcards never match in exact pass
  if (d.get(m))      return false;                             // ← COMPOUND ⇒ no match
  if (t2t(f.pattern, m)) return true;
  if (s !== "deny" && s !== "ask" && !ped(f.pattern)) return false;
  return t2t(`xargs ${f.pattern}`, m);
```

`t2t(p,m) = ffe(p, m, /*caseInsensitive*/ false, /*collapseWhitespace*/ true)`.
`ffe` builds `^…$` from the pattern by escaping regex metachars, mapping `*`→`.*`, `/**/`→`/(?:.*/)?`,
then one special case:

```js
if (p.endsWith(" .*") && starCount === 1) p = p.slice(0,-3) + "( .*)?";
```

⇒ **`Bash(git status *)` also matches bare `git status`.** Same for `Bash(ls *)` matching `ls`.

### The five forms in the brief

| Rule | Type | Matches | Evidence |
|---|---|---|---|
| `Bash(git status)` | exact | **only** the literal string `git status`. Not `git status --short`. Not `git status` with a double space. | `f.command===m`; probe C#11 `/usr/bin/basename  foo` **DENIED** under exact rule `Bash(/usr/bin/basename foo)` |
| `Bash(git status:*)` | prefix | `git status`, `git status --short`, `git status  --short` (ws-normalised), `xargs git status …` | probe A#3,#4 ALLOW; probe D#1 `/bin/date  +%s` ALLOW under `Bash(/bin/date:*)` |
| `Bash(git:*)` | prefix | any command whose normalised text is `git` or starts with `git ` | same code path |
| `Bash(*)` | wildcard `*` | **equivalent to bare `Bash`** — docs `/permissions` line 106: *"`Bash(*)` is equivalent to `Bash` and matches all Bash commands."* See §6 for what bare `Bash` actually bypasses. | docs + probe G |
| `Bash(curl -s:*)` | prefix `curl -s` | `curl -s …`. **Not** `curl -sS …`, not `curl --silent …`, not `curl -s` with the flag after the URL. | prefix is a literal string prefix with a space boundary |

### Normalisation applied to the *command* before matching (`ALs` lines 1–8 + `iae`)

Candidate strings tried, in order: the trimmed command; the command **with output redirections
stripped** (`k$e(...).commandWithoutRedirections`); and `iae(...)` of each.

`iae` (offset 19879929) does, to a fixed point:
1. **Strips comment lines** (`Sko`: drops any line whose trimmed form starts with `#`). Probe D#12
   `/bin/date +%s # hello` → **ALLOW**.
2. **Strips a leading `VAR=value ` assignment — but only if `VAR` is in a 38-name allowlist** (`qsn`):
   `GOEXPERIMENT GOOS GOARCH CGO_ENABLED GO111MODULE RUST_BACKTRACE RUST_LOG NODE_ENV
   PYTHONUNBUFFERED PYTHONDONTWRITEBYTECODE PYTEST_DISABLE_PLUGIN_AUTOLOAD PYTEST_DEBUG
   ANTHROPIC_API_KEY LANG LANGUAGE LC_ALL LC_CTYPE LC_TIME CHARSET TERM COLORTERM NO_COLOR
   FORCE_COLOR TZ LS_COLORS LSCOLORS GREP_COLOR GREP_COLORS GCC_COLORS TIME_STYLE BLOCK_SIZE
   BLOCKSIZE COLUMNS LINES CLICOLOR CLICOLOR_FORCE CI DEBIAN_FRONTEND GIT_TERMINAL_PROMPT`.
   Probe A#14/D#4 `LC_ALL=C …` **ALLOW**; probe A#15/D#5 `FOO=1 …` **DENY**.
   ⚠️ **Asymmetric:** `v7e` passes `stripAllEnvVars: true` for **deny and ask** rules and *not* for
   allow rules — a deny rule matches past *any* leading assignment. Docs confirm:
   *"`Bash(rm *)` in deny still matches `FOO=bar rm -rf tmp/`"*.
3. **Strips wrapper commands:** `timeout`, `time`, `nice`, `stdbuf`, `nohup`, `command`, `builtin`,
   `noglob`. Probe D#13 `timeout 5 /bin/date +%s` → **ALLOW** under `Bash(/bin/date:*)`.
   Not stripped: `env`, `xargs -n1`, `watch`, `setsid`, `ionice`, `flock`, `sudo`, `npx`,
   `docker exec`, `devbox run`, `mise exec`, `direnv exec`.
4. **Unquotes the first token only.**

**Case sensitivity — measured:** probe A#7 `LS -la` under `Bash(ls:*)` → **DENIED**
(`This command requires approval`). Bash rules are **case-sensitive**.
(The case-*insensitive* comparator `i(f,m){return f.toLowerCase()===m.toLowerCase()}` at offset
20824847 belongs to `j2s`, the **PowerShell** matcher — `Vi="PowerShell"` at offset 14199329.
Do not generalise it to Bash.)

---

## 2. Compound commands — the crux

> **VERDICT:** The harness **parses the command with tree-sitter and requires EVERY sub-command to
> match independently**. It splits on `&&  ||  ;  |  |&  &` and newlines. Prefix and wildcard rules
> therefore **DO work on compound commands** — that was the open question and the answer is yes.
> But five constructs are hard-gated and **no allow rule of any specifier form can approve them**:
> `$( )` / backticks, `( … )` subshells, `{ …; }` command groups, a trailing `&`, and any output
> redirection to a file. `bash -c '…'` is not decomposed and is refused.

### Mechanism

`MT(e)` (offset 22917672) parses with tree-sitter and walks the tree, recursing into
`D8s = {program, list, pipeline}` and skipping operator/comment nodes
`prp = {"&&","||","|",";","&","|&","\n"}`, pushing each remaining node's text.
Docs `/permissions` line 204 states exactly the same separator set.

`sW_` then evaluates each sub-command with `wEd`, and combines:

```js
if (D.find(r => r.behavior==="deny"))      return deny;         // any deny wins
…
if (D.every(r => r.behavior==="allow"))    return allow;        // all must allow
…                                                              // otherwise → ask / classifier
```

`P8_` (the pipe layer) is the same shape: *any* deny → deny; *all* allow → allow; else **ask**.

The **compound guard inside `ALs`**:

```js
let d = new Map();
if (r === "prefix" && !skipCompoundCheck)
  for (let p of u) d.set(p, MT(p).length > 1);   // candidate is itself compound?
…
case "prefix":  if (d.get(m)) return false;
case "wildcard": if (d.get(m)) return false;
```

`skipCompoundCheck` is `true` exactly when an `astCommand` is supplied — i.e. when `sW_` is
evaluating an already-split single sub-command. So the guard's real job is: **a prefix or wildcard
rule can never match a still-compound string**; only the per-sub-command pass can approve it.
Corollary: an **exact** rule *can* match a whole compound string (`Rko` runs `v7e(…, "exact")` on the
untrimmed full command) — but that is a literal, byte-for-byte match of the entire line, so it is
useless as a general pattern.

### Measured behaviour (probes C and D, ruleset `["Bash(/bin/date:*)","Bash(/usr/bin/basename foo)"]`)

`/bin/date` is a deliberate probe subject: probe B proved `/bin/date +%s` is **denied** with an empty
allowlist (the built-in read-only set keys on the bare command name, so an absolute path escapes it).
That removes the read-only auto-allow as a confounder — which silently contaminated probe A, where
`echo hello world`, `git log`, `whoami` and `head` all ran with no matching rule.

| Command | Verdict | Error text |
|---|---|---|
| `/bin/date +%s && /bin/date -u` | **ALLOW** | — every sub matches the prefix rule |
| `/bin/date +%s ; /bin/date -u` | **ALLOW** | — |
| `/bin/date +%s \|\| /bin/date -u` | **ALLOW** | — |
| `/bin/date +%s \| /bin/date -u` | **ALLOW** | — |
| `/bin/date +%s && /bin/hostname` | **DENY** | `This Bash command contains multiple operations. The following part requires approval: /bin/hostname` |
| `/bin/date +%s \| /usr/bin/head -1` | **DENY** | same — `/usr/bin/head` is not covered |
| `echo $(/bin/date +%s)` | **DENY** | `Contains command_substitution` |
| `( /bin/date +%s )` | **DENY** | `This command uses shell operators that require approval for safety` |
| `{ /bin/date +%s; }` | **DENY** | `Contains compound_statement` |
| `/bin/date +%s &` | **DENY** | `This command uses the & background operator, which defers execution past approval-time safety checks` |
| `bash -c '/bin/date +%s'` | **DENY** | `This command requires approval` |
| `for i in 1 2; do /bin/date; done` | **ALLOW** | ← loops **are** decomposed |
| `if true; then /bin/date; fi` | **ALLOW** | ← so are conditionals |
| `while false; do /bin/date; done` | **ALLOW** | |
| `/bin/date +%s > /tmp/…/o2.txt` | **DENY** | `Output redirection to '…' was blocked. For security, Claude Code may only write to …` |
| `/bin/date +%s # hello` | **ALLOW** | comment stripped |
| `timeout 5 /bin/date +%s` | **ALLOW** | wrapper stripped |
| `LC_ALL=C /bin/date +%s` | **ALLOW** | allowlisted env prefix |
| `FOO=1 /bin/date +%s` | **DENY** | non-allowlisted env prefix |

The subshell / command-group refusal is `L8_` (offset 19876799):

```js
if (s ? s.compoundStructure.hasSubshell || s.compoundStructure.hasCommandGroup
      : MT(e.command).length > 1)
  return {behavior:"ask", decisionReason:{…, bashMissKind:"shell-operators"}};
```

### Other hard gates in `sW_` no allow rule survives

* **`too-complex`** — `tPt` returns `kind:"too-complex"` for AST shapes the analysis won't model.
  Telemetry `tengu_bash_ast_too_complex`. → **ask**.
* **Commands longer than `CIe = 10,000` characters** — `MT` returns `[e]` unsplit, and the
  read-only analysis bails. Docs: *"Commands longer than 10,000 characters always prompt."*
* **Multiple `cd`s** — `> 1` normalised `cd` sub-commands → ask,
  `bashMissKind:"multi-cd"`, *"Multiple directory changes in one command require approval for clarity"*.
* **`cd` + `git` in one command** → ask, `bashMissKind:"cd-git-compound"` (a `cd` whose target
  resolves to the current cwd is exempt).
* **Output redirection** — the target is checked as a **file write** against `Edit` rules,
  protected paths and the working directories. `/dev/null` is exempt. A target starting with `~`
  or containing a glob char always needs approval.
* **`&` background operator** — `jsn` raises
  `{circuitBreaker:"backgroundOperator", classifierApprovable:false}`. **Not even the auto-mode
  classifier can approve it.**

### The full `bashMissKind` taxonomy (grep of the binary)

`no-rule-match` · `shell-operators` · `shell-expansion` · `process-substitution` · `too-complex` ·
`semantics` · `multi-cd` · `cd-git-compound` · `cd-multi-positional` · `cd-compound-write` ·
`cd-compound-redirect` · `sed-dangerous` · `flag-validation`.
Only `no-rule-match` is fixable by writing a better allow pattern. **Everything else is structural.**

### Heredocs

Not directly probed (UNVERIFIED by measurement). Code path `$8_` (offset ~19879500) splits on the
first `<<` and derives a two-token prefix from the text *before* it, and `K8_` explicitly refuses the
sandbox fast-path when `/(?<!<)<<(?!<)/` matches. Treat `cat > f <<'EOF'` as **not allowlistable**.

---

## 3. `defaultMode: "auto"` semantics

> **VERDICT:** Yes — auto mode runs a **second model (the classifier, Sonnet 5 by default)** that
> auto-approves actions matching **no static rule**, including things `default` mode hard-refuses.
> Measured. And yes, it can **raise** a prompt over a matching allow rule (protected-path writes,
> `rm` at a critical path, `requiresUserInteraction` MCP tools). 🚨 **The finding that dominates
> pattern design: on entering auto mode, Claude Code DELETES your broad Bash allow rules.**

### Measured (probe I — `--model claude-opus-5 --permission-mode auto`, `init` line confirms `permissionMode: auto`)

Ruleset: `["Bash(/bin/date:*)"]` only.

| Command | Verdict in `auto` | Verdict in `default` (probe C/H) |
|---|---|---|
| `/bin/date +%s` | ALLOW | ALLOW (rule) |
| `/usr/bin/basename /a/b` | **ALLOW** | **DENY** |
| `/usr/bin/wc -l /etc/hosts` | **ALLOW** | (n/a) |
| `echo $(/bin/date +%s)` | **ALLOW** | **DENY — `Contains command_substitution`** |
| `/usr/bin/env` | **ALLOW** | (n/a) |

⇒ In auto mode the classifier approves commands with no rule **and overrides the static
command-substitution gate**. Static allow rules are therefore largely *redundant* for ordinary
read-only work in auto mode.

⚠️ **Probe-methodology trap, worth recording:** the same probe run on `--model haiku` reported
`permissionMode: "default"` in its `init` line despite `--permission-mode auto` on the command line.
Auto mode **silently falls back to `default`** when the model doesn't support it
(`gk()`/`xae()` → reason `"model"`). A probe that doesn't read back `init.permissionMode` measures
the wrong mode. My first auto probe did exactly that and produced a false negative.

### Decision order (docs `/permission-modes`, "How the classifier evaluates actions")

1. Actions matching **allow / ask / deny rules resolve immediately** — *except*: protected-path
   writes route to the classifier **even when an allow rule matches**; `rm`/`rmdir` at a critical
   path likewise (v2.1.218+); org-`ask` connector tools and `requiresUserInteraction` MCP tools
   prompt directly even with an allow rule; **content-scoped ask rules like `Bash(git push *)` fall
   back to a real permission prompt.**
2. Read-only actions and file edits inside the working directory are auto-approved (except
   protected paths).
3. **Everything else goes to the classifier.**
4. If the classifier blocks, Claude gets the reason — usually the fixed string `Blocked by classifier`.

### 🚨 Auto mode drops broad allow rules — the exact predicate

`pme()` (offset 22935790):

```js
function pme(e){
  if (z8s(e.mode)) {                        // z8s: mode==="auto" || (mode==="plan" && autoActive)
    …for each allow rule: if (qNt(toolName, ruleContent)) continue;   // ← DROPPED
  }
  …
}
function qNt(e,t){ if ((e===Bash || e===PowerShell) && bsn()) return true; return Ssn(e,t) }
function bsn(){ return ZLi() }             // any settings source with autoMode.classifyAllShell===true
function gsn(e,t){ if(e!==Bash) return false;
                   if(t===undefined||t==="") return true;
                   if(/^[\s*]+$/.test(t))    return true;
                   return _sn(t, iSd) }
```

`iSd` (offset 19668065) — the dangerous-command list, verbatim:

```
python  python3  python2  node  deno  tsx  ruby  perl  php  lua
npx  bunx  "npm run"  "yarn run"  "pnpm run"  "bun run"
bash  sh  ssh  zsh  fish  eval  exec  env  xargs  sudo
```
plus a network/cloud subset `nSd = {curl, wget, kubectl, aws, gcloud, gsutil}` with special handling.

`_sn(ruleContent, iSd)` returns **true (⇒ rule dropped)** when the lowercased, trimmed rule content is:
* `*`, or
* exactly `<cmd>`, `<cmd>:*`, `<cmd> *`, or `<cmd>*` for any `<cmd>` in the list, or
* `<cmd> …*` where the tail **starts with a flag** (`-…`) — e.g. `Bash(node -e *)`, `Bash(sudo -u *)`.
  Exception: `Bash(python -m pkg.module *)` survives (`/^-m\s+\w+\.[\w.]+(\s*:|\s+)$/`).
* For `nSd` members: dropped if the tail contains `$` or a backtick; for `kubectl`, dropped if the
  first non-flag arg is one of `exec apply create delete run cp port-forward proxy patch edit
  replace attach debug scale rollout drain cordon taint`; dropped if there is no positional arg at
  all (except `curl`/`wget` whose args contain `://`).

`PHs(e,t){ return s9(e)===Agent }` — **every `Agent` allow rule is dropped in auto mode**, whatever
its specifier.

**What survives:** anything narrower. `Bash(npm run test:*)` survives (tail `test:*` doesn't start
with `-`, and `npm run` only matches the bare forms). `Bash(python3 scripts/foo.py *)` survives.
`Bash(git status:*)`, `Bash(rg:*)`, `Bash(jq:*)` — never on the list, always survive.

Dropped rules are **restored when you leave auto mode**. The drop is *code-and-doc verified*
(`pme`/`gsn`/`_sn` + docs `/permission-modes` "On entering auto mode, broad allow rules that grant
arbitrary code execution are dropped") but **NOT probe-verified** — I could not construct an
observable that distinguishes "allowed by rule" from "allowed by classifier" in auto mode from the
stream-json surface. Flagged as the one load-bearing claim resting on two non-probe sources.

### Mode resolution + precedence (`aBc`, offset 13408952)

Candidate list `p`, first survivor wins:
1. `--dangerously-skip-permissions` → `bypassPermissions`
2. `--permission-mode <x>` (CLI flag)
3. agent frontmatter `permissionMode`
4. `settings.permissions.defaultMode`
5. fallback: may auto-enable `auto` when gated on (`tengu_harbor_willow` / `meadow_lantern`) and
   `permissions.disableAutoMode !== "disable"` and the session is interactive.

🚨 **`defaultMode: "auto"` is only honoured from `policySettings`, `userSettings`, or
`flagSettings`.** Verbatim from the binary:

> `settings defaultMode "auto" ignored — only policy/user/flag settings may grant auto mode
> (projectSettings and localSettings are repo-controllable)`
> — telemetry `tengu_settings_auto_mode_untrusted_source_ignored`

So `auto` in `.claude/settings.json` or `.claude/settings.local.json` is a **silent no-op**, and per
docs the session then uses the built-in default rather than falling back to `~/.claude/settings.json`.

Other kill switches: `permissions.disableAutoMode: "disable"` (or top-level `disableAutoMode`) ·
a circuit breaker (`tengu_auto_mode_config.enabled === "disabled"`) · unsupported provider without
`CLAUDE_CODE_ENABLE_AUTO_MODE` (pre-2.1.207 only) · unsupported model ·
`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` forces `default` outright.

### PreToolUse hooks vs rules

* `hookSpecificOutput.permissionDecision` accepts `"allow" | "deny" | "ask" | "defer"`
  (`defer` is print-mode only; an interactive session logs
  *"returned permissionDecision=defer in interactive mode; ignoring"*).
* **Hook `"allow"` does NOT bypass rules.** Docs `/permissions` line 442: *"Claude Code evaluates
  deny and ask rules regardless of what a PreToolUse hook returns."* Confirmed in code by `Mfr`,
  which re-checks the tool after a hook allow and returns the deny/ask if one matches.
* **A hook exiting 2 blocks *before* rules are evaluated** — it beats an allow rule.
* Anthropic's own recommended shape for prompt-free operation is exactly this:
  **`"allow": ["Bash"]` + a PreToolUse hook that rejects the specific commands you want blocked.**

**Full precedence, worst-to-best:**
`PreToolUse hook exit-2` → **deny rules (any scope)** → **ask rules** → `bypassPermissions` mode →
protected-path / critical-path circuit breakers (`classifierApprovable:false`) → **allow rules** →
mode auto-approvals (`acceptEdits`, read-only set) → **auto-mode classifier** → prompt.

---

## 4. Non-Bash rules

> **VERDICT:** `Read`/`Edit` rules use **gitignore pattern syntax**, evaluated by the bundled
> `ignore` npm package, anchored to a root that depends on **which settings file the rule came from**.
> `//abs/path` = filesystem-absolute · `~/x` = home · **a single leading `/` is NOT filesystem
> root — it anchors to the settings source's own directory** (the single biggest footgun here) ·
> bare/relative = the session cwd. `WebFetch` requires the literal `domain:` prefix.
> A bare tool name with **no parentheses** covers the whole tool unconditionally.

### Path anchoring (`Tap`, offset 23274839 · `k$y` · `_4r`, offset 12195539)

```js
function Tap(e,t){
  if (e.startsWith("//"))  return {relativePattern: e.slice(1), root: "/"};
  if (e.startsWith("~/"))  return {relativePattern: e.slice(1), root: os.homedir()};
  if (e.startsWith("/"))   return {relativePattern: e,          root: t};   // ← t = SOURCE root
  if (e.startsWith("./"))  e = e.slice(2);
  return {relativePattern: e, root: null};                                  // null ⇒ cwd at match time
}
function _4r(source){ switch(source){
  case "userSettings":   return resolve(claudeConfigDir());   // ~/.claude
  case "policySettings":
  case "projectSettings":return resolve(cwd);
  case "localSettings":  return gitRoot(cwd) ?? cwd;
  case "flagSettings":   return dirname(resolve(flagPath));
}}
// cliArg / command / session / toolsNarrowing / mcpServerPolicy → originalCwd
```

Matching is `ignore().add(patterns).test(relPath).ignored` — i.e. **gitignore semantics**, including
"a bare filename matches at any depth". `Read(.env)` ≡ `Read(**/.env)`.

One asymmetry from `vap`: a pattern ending `/**` has the suffix stripped; if what remains is a single
segment with no `/`, an **allow** rule gets a leading `/` prepended (anchored to the root) while
**deny/ask** rules do not (match at any depth).

### Measured (probe F — deny rules, `--settings` ⇒ source is `flagSettings`, root `/private/tmp/permprobe`)

| Deny rule | Read target | Result |
|---|---|---|
| `Read(//private/tmp/permread/a.txt)` | `/private/tmp/permread/a.txt` | **DENIED** ✅ `//` works |
| `Read(/private/tmp/permread/b.txt)` | `/private/tmp/permread/b.txt` | **ALLOWED** ❌ **single `/` anchored to the settings dir and did not match** |
| `Read(//private/tmp/permread/sub/**)` | `/private/tmp/permread/sub/c.txt` | **DENIED** ✅ absolute glob works |
| `Read(~/.claude-probe-marker.txt)` | `/Users/chrisren/.claude-probe-marker.txt` | **DENIED** ✅ `~/` works |
| `Read(other/**)` | `/private/tmp/permprobe/other/e.txt` | **DENIED** ✅ relative → cwd |
| *(no rule)* | `/private/tmp/permprobe/rel/d.txt` | ALLOWED — control |
| *(no rule)* | `/etc/hosts` | ALLOWED — control |

Error text: `<tool_use_error>File is in a directory that is denied by your permission settings.</tool_use_error>`

### `Read`/`Write` **allow** rules are near-useless in `default` mode

Probe E: with an empty-ish allowlist, `Read` succeeded on `/etc/hosts` and on every out-of-cwd path;
probe F: `Write` succeeded to `/private/tmp/permwrite2/y.txt` with **no matching rule**. Reads are
ungated in this build; edits are gated by the **working-directory** check, not by allow rules.
⇒ **For file tools, spend your rule budget on `deny`/`ask`, not `allow`.**

### Other tools

| Form | Meaning | Source |
|---|---|---|
| `Read` / `Bash` / `WebFetch` (no parens) | **the whole tool, unconditionally** — `N5t` renders *"Any use of the X tool"*; `$fe` filters out `ruleContent===undefined` from the content matchers entirely, so these are matched at the tool level and skip all specifier logic | `N5t` offset 27518643 + probe G |
| `Bash(*)` | identical to bare `Bash` | docs `/permissions` line 106 |
| `WebFetch(domain:example.com)` | exact host | validator: *"WebFetch permissions must use `domain:` prefix"* |
| `WebFetch(domain:*.google.com)` | any subdomain at any depth — **but not `google.com` itself** | docs line 389 |
| `WebFetch(domain:*)` | ≡ bare `WebFetch` | docs line 390 |
| `WebFetch(domain:example.*)` | `*` in a non-leading position matches only between two dots — matches `example.org`, not `example.evil.com` | docs line 392 |
| `WebSearch(claude ai)` | exact terms, **no wildcards** — validator: *"WebSearch does not support wildcards"* | binary offset 8109858 |
| `mcp__server__tool` | exact tool. `mcp__puppeteer__*` allowed (server segment must be glob-free). `mcp__*` works for **deny/ask only** — an unanchored allow glob (`"*"`, `"B*"`, `"mcp__*"`) is **skipped with a warning and approves nothing** | docs line ~176 |
| `Tool(param:value)` | matches a top-level scalar input param. **deny/ask only** — allow rules must use the tool's own specifier | docs line ~118 |
| `Cd(~/code/*)` | a real rule type; `*` = one path segment, `**` = across segments, trailing `/**` also matches its root | docs line 430 |

---

## 5. Precedence and scope across settings files

> **VERDICT:** Rule lists **UNION** across every source — nothing is overridden or shadowed.
> Behaviour classes are then applied **deny → ask → allow**, so a deny anywhere beats an allow
> everywhere. Managed/policy settings sit at the top and cannot be overridden by anything,
> including CLI flags.

`$fe` (offset 22940243) — the collector:

```js
function $fe(e,t,r){
  let n = new Map(), o = [];
  switch(r){ case "allow": o = pme(e); case "deny": o = gL(e); case "ask": o = jfe(e); }
  for (let i of o)
    if (i.ruleValue.toolName===t && i.ruleValue.ruleContent!==undefined && i.ruleBehavior===r)
      n.set(i.ruleValue.ruleContent, i);      // keyed by rule STRING ⇒ union; identical strings dedupe
  return n;
}
```

Source order (`VN`, offset 12058230):
`["userSettings", "projectSettings", "localSettings", "flagSettings", "policySettings"]`
(`wC()` always force-adds `flagSettings` + `policySettings`). Rule producers also read `cliArg` and
`session` scopes (`Dq_ = [userSettings, projectSettings, localSettings, flagSettings, cliArg, session]`).

Docs `/permissions` §Settings precedence, verbatim:
> *"managed settings highest: no other level, including command line arguments, can override a
> managed permission rule."*
> *"If a tool is denied at any level, no other level can allow it… a user-level deny blocks a
> project-level allow, because deny rules from any scope are evaluated before allow rules."*
> *"A broad deny rule like `Bash(aws *)` blocks every matching call, including calls that also match
> a narrower allow rule like `Bash(aws s3 ls)`, so a deny rule can't carry allowlist exceptions.
> The same precedence applies between ask and allow."*

**Scope traps:**
* `permissions.allow` and `additionalDirectories` in a project `.claude/settings.json` **do not
  apply until you accept the workspace-trust dialog** for that folder. `deny`/`ask` are unaffected.
* `~/.claude/settings.local.json` is **local scope** — read only in sessions started *in your home
  directory*, not in every project. Cross-project rules must go in `~/.claude/settings.json`.
* Managed `allowManagedPermissionRulesOnly: true` discards every non-policy rule
  (*"permission rules are restricted to managed settings"*, 8 occurrences in the binary).
* `--allowedTools` is parsed by `JB()` (offset 23298741), which splits on spaces **and commas that
  are outside parentheses** — so `Bash(git status)` survives but you cannot pass a rule whose
  specifier contains an unparenthesised space-separated list.

---

## 6. Footguns, no-ops, and caps

| # | Footgun | Evidence |
|---|---|---|
| F1 | **`:*` is recognised only at the END.** `Bash(git:* push)` treats the colon as a literal char and matches nothing. | `mtn` regex `/^(.+):\*$/`; docs line 163 |
| F2 | **A single leading `/` in a file rule is not filesystem root.** `Read(/etc/**)` in `~/.claude/settings.json` anchors at `~/.claude/etc/**` and silently never matches. Use `//etc/**`. | `Tap` + probe F row 2 |
| F3 | **`Tool(param:value)` on a primary content field is ignored.** `Bash(command:rm *)` is dropped with a startup warning. | docs line 138 |
| F4 | **Exact rules are not whitespace-normalised.** `Bash(npm run test)` fails against `npm run  test`. Prefix/wildcard rules *are* normalised. | probe C#11 DENY |
| F5 | **Bash rules are case-sensitive** (PowerShell rules are not). | probe A#7 `LS -la` DENY |
| F6 | **An allow rule stops at any env assignment outside the 38-name allowlist.** `FOO=1 ls` defeats `Bash(ls:*)`. Deny rules are immune. | probe A#15, D#5 |
| F7 | **Unanchored allow globs are silently skipped**: `"*"`, `"B*"`, `"mcp__*"` in `allow` approve nothing (warning only). They *do* work in deny/ask. | docs line ~176 |
| F8 | **`defaultMode: "auto"` in project/local settings is a silent no-op**, and the session then ignores `~/.claude/settings.json`'s `defaultMode` too. | binary warning string + docs line 303 |
| F9 | **Auto mode deletes your broad Bash/PowerShell/Agent allow rules.** Anything matching `iSd` in bare/`:*`/`*`/flag-tail form is gone for the whole auto session. | `pme`/`qNt`/`gsn`/`_sn`; docs |
| F10 | **`autoMode.classifyAllShell: true` in ANY settings source drops *every* Bash and PowerShell allow rule in auto mode.** | `ZLi()` offset 12224748 |
| F11 | **Argument-constraining patterns are structurally fragile.** `Bash(curl http://github.com/ *)` misses `curl -X GET …`, `https://`, `curl  http://…`, and `URL=… && curl $URL`. | docs Warning block |
| F12 | **Environment runners are not wrappers.** `Bash(devbox run *)` / `npx *` / `docker exec *` approve *whatever follows*, including `devbox run rm -rf .`. | docs Wrappers |
| F13 | **Exec wrappers can never be prefix-approved**: `watch`, `setsid`, `ionice`, `flock`, and `find` with `-exec`/`-delete` always prompt under a prefix rule. | docs Wrappers |
| F14 | **`xargs` with flags is not stripped.** `Bash(grep *)` covers `xargs grep p` but not `xargs -n1 grep p`. | docs + `ALs` xargs branch |
| F15 | **Redirection targets need Edit permission, not Bash permission.** `Bash(ls:*)` does not authorise `ls > out.txt`. `/dev/null` is exempt; `~`-prefixed or glob targets always prompt. | probe A#12, C#12 |
| F16 | **Bare-name deny removes the tool from Claude's context entirely** (it never sees it) — different from a scoped deny, which leaves the tool available. | docs line 68 |
| F17 | **Symlinks:** allow rules require **both** the link path and its target to match; deny rules block if **either** matches. | docs line 377 |
| F18 | Rules generated by "Yes, and don't ask again" for a **file path** are gitignore-escaped; hand-written rules are not — so a hand-written `Read([2024] Reports/**)` behaves as a character class. | docs line 375 |
| F19 | Approving a compound command saves **up to 5** separate rules (`B8_ = 5`), one per unapproved sub-command — not one rule for the whole line. | `B8_=5` + docs line 207 |
| F20 | Tool **labels ≠ canonical names**. A rule written `Stop Task` never matches `TaskStop`. Deny/ask typos raise a startup warning; **allow typos do not**. | docs line ~186 |

### Allow-list size — is 339 entries a problem?

> **VERDICT: No cap and no cliff at this scale.** No `MAX_*_RULES` constant governs
> `permissions.allow` anywhere in the binary (the only hit, `MAX_ACCESS_BOUNDARY_RULES_COUNT`, is an
> unrelated subsystem). `ALs` is `O(rules × candidateVariants)` of plain string ops per sub-command,
> run once per behaviour class; `Ssn` memoises the auto-mode drop predicate in `sSd`; file rules
> cache their compiled `ignore` instance per root (`tVs`/`XGs`, LRU of 16).
> One small note: `I$y = 1`, so the `ignore` object for file rules is rebuilt roughly every other
> call — irrelevant at 339 entries, worth remembering if the file-rule count grows by an order of
> magnitude. **The real cost of 339 entries is not CPU — it is that most of them cannot fire.**

---

## WHAT THIS MEANS FOR PATTERN DESIGN

### First, re-frame the measurement

The corpus is "~21,600 Bash invocations matching no allow rule" and "1,757 prompts". Those are two
very different numbers and the gap is explained by two mechanisms that are **not** the allowlist:

1. **The built-in read-only set.** Probe B: with an *empty* allowlist, `date`, `uname -a`,
   `hostname`, `id`, `true`, `printf hi`, `sleep 0`, `git rev-parse HEAD`, `git status` all ran with
   no prompt. Docs list `ls cat echo pwd head tail grep find wc which diff stat du cd` plus
   read-only `git`. **A large share of the 21,600 never needed a rule.**
2. **The auto-mode classifier.** Every live session on this box runs `--permission-mode auto`
   (`ps aux`). Probe I proved the classifier approves unmatched commands *and* overrides the static
   `$( )` gate. **Most of the remainder never needed a rule either.**

⇒ Do **not** write patterns against the 21,600. Write them against the **1,757**, and first bucket
those by `bashMissKind` / error text. Only `no-rule-match` is addressable by a pattern.

### DO

1. **Prefer `Bash(<cmd> <subcmd>:*)` — two tokens, then `:*`.** It is the only form that is
   whitespace-tolerant, survives the auto-mode drop filter, and composes across compound commands.
   Examples that all survive: `Bash(git status:*)`, `Bash(rg:*)`, `Bash(jq:*)`, `Bash(gh pr view:*)`,
   `Bash(npm run test:*)`, `Bash(pnpm build:*)`.
2. **Enumerate sub-commands rather than reaching for the parent.** `Bash(npm run:*)` is deleted in
   auto mode; `Bash(npm run build:*)` + `Bash(npm run test:*)` + `Bash(npm run lint:*)` are kept.
   Same for `python3` → `Bash(python3 scripts/gen.py *)`.
3. **Write one rule per sub-command you actually chain**, because every sub-command is matched
   independently. A `cd x && pnpm test` line needs `cd` to qualify on its own (it does, inside the
   working directory) *and* `Bash(pnpm test:*)`.
4. **Spend the file-rule budget on `deny`/`ask`, not `allow`** — allow rules for `Read`/`Write` are
   effectively inert in this build, while `deny` demonstrably bites.
5. **Use `//` for every absolute file path.** `Read(//etc/**)`, `Edit(//Users/chrisren/.ssh/**)`.
6. **If the goal is genuinely "stop prompting for shell",** the sanctioned shape is
   `"allow": ["Bash"]` + a `PreToolUse` hook that rejects the specific things you want blocked.
   Bare `Bash` was measured to allow `$( )`, subshells, redirects, `&`, and `bash -c` — nothing else
   does. (Note it is *also* on the auto-mode drop list via `gsn`'s empty-content branch, so under
   auto it buys you nothing; it is a `default`/`acceptEdits`-mode lever.)
7. **Put `defaultMode` and any `auto`-related key in `~/.claude/settings.json`**, never in a project
   or `.local` file.
8. **Audit existing rules against the drop list** — now `cc-permission-audit --prune`, which
   emits an `AUTO-MODE DROP LIST` section implementing `gsn`/`_sn`/`iSd`/`nSd`/`PHs` above
   verbatim, alongside its existing redundancy audit.

   > ⚠️ **DO NOT use the grep this item used to recommend**
   > (`python|python3|node|…|sudo|curl|wget|kubectl|aws|gcloud|gsutil` over the 339 entries,
   > struck 2026-08-28). It was landed here as the remedy and it is wrong in **both**
   > directions. **False positives:** a substring match sweeps `shellcheck`, `nodemon`,
   > `sudoku`, `envsubst`, `execa` and `npm run-script`, every one of which survives auto mode
   > — a token-boundary test is what separates them, and all six are pinned as arms in
   > `tests/cc-permission-dropped.bats`. **False negatives:** it cannot see bare `Bash`, an
   > all-wildcard specifier, an `Agent(…)` rule (dropped whatever the specifier), or
   > `autoMode.classifyAllShell`, which drops *every* Bash and PowerShell allow rule from any
   > settings source. The predicate is a rule **algebra**, not a spelling — the same lesson
   > THE DEAD-ENTRY PREDICATE already learned for `--prune`.

   The audit **reports and never removes**, not even under `CONFIRM=1`: a dropped rule is
   restored the moment a session leaves auto mode, so it is dead *weight*, not a dead *entry*,
   and deleting it is a real semantic change under `default`/`acceptEdits`. Rewrite each hit
   narrower per DO #1–#2 instead.

### DON'T

1. **Don't write exact rules.** They are byte-exact, whitespace-sensitive, and match roughly nothing
   in a real corpus. `Bash(git status)` will not fire on `git status --short`.
2. **Don't write mid-pattern colons.** `Bash(git:* push)` matches nothing.
3. **Don't try to constrain arguments.** `Bash(curl https://api.github.com/*)`,
   `Bash(rm -rf ./build*)` — both are trivially side-stepped and give false assurance. Use a deny
   rule plus a hook.
4. **Don't expect a pattern to rescue a structural refusal.** `$( )`, backticks, `( … )`, `{ …; }`,
   trailing `&`, `bash -c`, heredocs, >10 000-char commands, multi-`cd`, `cd`+`git`, and file
   redirects are gated *before* rule matching. In `default` mode no allow rule reaches them; the
   only fixes are (a) auto mode's classifier, or (b) rewriting how the agent forms commands.
5. **Don't rely on `Bash(*)` or `mcp__*` in an allow list.** The first is bare `Bash` (and is
   dropped in auto); the second is skipped with a warning.
6. **Don't put allow rules in a project `.claude/settings.json`** and expect them to work before the
   workspace-trust dialog is accepted.
7. **Don't add a deny rule expecting a narrower allow to carve an exception.** Deny beats allow at
   every scope, unconditionally.

### The highest-leverage single change

Given every session already runs `auto`, the allowlist's remaining job is small and specific:
**cover the command families the classifier declines, and stop paying for the ones it doesn't.**
Bucket the 1,757 prompts by their error text first — `no-rule-match` vs `shell-operators` vs
`too-complex` vs redirect-blocked vs `backgroundOperator` — and only the first bucket is worth a
pattern. The `&`-background and critical-path-`rm` buckets carry `classifierApprovable: false` and
**cannot be fixed by any rule or hook at all.**

---

## Open / UNVERIFIED

* The auto-mode allow-rule drop (§3) is code-and-doc verified, **not probe verified** — no observable
  in `stream-json` distinguishes rule-allow from classifier-allow.
* **Heredocs** (`cat > f <<'EOF'`) were not probed; treat as not-allowlistable (code suggests refusal).
* `cd`-compound behaviour was not cleanly probed — the model rewrote the command in both attempts
  (probes C#13, D#3). Claims about `cd` rest on the binary and docs.
* Whether `permissions.allow` from `cliArg`/`--allowedTools` is also subject to the auto-mode drop:
  `pme` iterates `rfn` (source list) uniformly, so **likely yes**, but the `rfn` contents were not
  extracted.
* The exact contents of the built-in read-only command set were sampled, not enumerated; the regex
  set `E8_`/`v8_`/`CLs` at offset 19874769 is the authoritative source if a full list is needed.
