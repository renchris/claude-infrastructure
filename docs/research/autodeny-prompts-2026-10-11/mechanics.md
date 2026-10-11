# Timed auto-deny permission prompts in Claude Code 2.1.293: how they work

Source: /tmp/cc293-strings.txt (2.1.293 strings dump), read with python. Names are minified. The working dumps are in /tmp/autodeny-census/*.txt.

## Summary
- **Two producers.** Two code paths add the "will automatically deny this request in M:SS" timer to a dialog:
  - **(1) `autoDenyWindow`**, from `wln()`. Only the `dangerousRemoval` circuit breaker reaches it.
  - **(2) `denialLimitFallback` with a timer**, from `iTr()`. This only happens after 3 consecutive classifier blocks, and only when `tengu_ticklish_whisper` is on.
- **Timer UI.** Both use the same timer, armed in `lo()` (offset about 40800500): `setTimeout` → `be({behavior:"deny",message:Se.message})`. The countdown text is at offset 40486210: `` `${Bh} Claude Code will automatically deny this request in ${oe}:${pad(j)}, to avoid blocking progress on an unattended session` ``.
- **What stops them.**
  - Neither `permissions.allow` nor a PreToolUse `allow` stops (1).
  - A **PermissionRequest hook that returns `allow` without `updatedInput` does resolve both dialogs.**

## a) The `lt` circuit-breaker table (offset 11390133)
| breaker | bypassImmune | classifierRouted | autoModeDeny | hostPersonOnly | other |
|---|---|---|---|---|---|
| dangerousRemoval | **T** | **T** | **T** | F | |
| backgroundOperator | F | T | F | F | |
| suspiciousWindowsPath | F | T | F | F | |
| isolatePeerMachines | T | F | F | F | |
| restrictedMode | T | F | F | F | |
| outsideReadsBlocked | T | F | F | F | |
| claudeSettingsFile | F | F | F | **T** | |
| internalHardDeny | F | F | F | F | servedUnplaceable:T |

**Path into `wln()`.** The selector is `mJt(e){return e.circuitBreaker!==void 0&&lt[e.circuitBreaker]?.autoModeDeny===!0}`. **Only `dangerousRemoval` qualifies.** `wln` has two call sites:
- **Auto mode** (offset 22142472): `Jn=$d(ke.decisionReason,mJt),$n=Jn!==void 0&&LLe(Te)&&!Vt?q5():void 0; if(Jn!==void 0&&$n?.enabled){let ds=wln(ke,Jn,M,$n);...}`. Here `Vt=rG(ke)`, which is true when an explicit **ask rule** matched. In that case the code skips `wln` and shows a normal prompt that waits indefinitely.
- **bypassPermissions** (offset 22167137): `if(Ce==="bypassPermissions"&&!rG(ke)&&Dln(M)){...wln(...)}`.

The `wln` function:
```
function wln(e,n,r,s){let g=(b)=>({behavior:"deny",message:Gln(oTr(e,n),b),decisionReason:n,decideLocation:"pre-ask"});
 if(!s.showDialog||!Dln(r))return g();
 let h=C5t(); if(s.maxDialogTimeouts>0&&h>=s.maxDialogTimeouts) return i("tengu_safety_check_dialog_capped",...),g(h);
 return{...e,autoDenyWindow:Han({autoDenyAfterMs:s.timeoutMs,resolution:g()})}}
Dln(e)= e.requestDialog!==void 0&&!bz()&&!de(e).shouldAvoidPermissionPrompts&&!WYt(e)
WYt(e)= teammate || (subagent && isAsync) || forRemoteExecution || fA(e)
```
- **No timer for headless or background agents.** In headless runs, async/background subagents, teammates and remote execution, the command is denied **immediately**, with no dialog and no timer.
- **Unanswered-prompt counter.** The `spe` counter (`C5t`/`_Ko`) goes up each time a timer expires. `VJe()` resets it when the user answers a dialog or types a human prompt.
- **After 3 expired timers** in a session, every later dangerous rm is denied with no dialog (`tengu_safety_check_dialog_capped`).

**Detector.** `hb()` builds `{type:"safetyCheck",classifierApprovable:!1,circuitBreaker:"dangerousRemoval"}`. It is called from:
- `$W()` for literal rm/rmdir targets
- `Xye()` for variable targets
- the substitution check (`tengu_iridescent_boot`)
- `h_e()` for `sh -c` scripts it cannot check

**Command shapes that trigger it:**
1. **Variable followed by `/` and then a glob, `$`, `/`, a quote or end of word** (regex `Jsn`). This matches whether or not the variable is set: `rm -rf "$DIR"/*`, `rm -rf $DIR/`, `rm -rf "$DIR/"*`, `rm -rf "${DIR}/$X"`, `rm -rf "${DIR:-}/"`. With the `n` flag, positionals also match (`zyr`): `rm -rf "$1"/*`.
2. **Variable followed by a top-level directory name** (`Kyr`/`Zsn` list: bin, etc, home, tmp, usr, var, Users, Library, System, Volumes, Applications, private, ...). Example: `rm -rf "$PREFIX/usr"`. This only fires when `mayBeUnset(VAR)` is true (`Zin`):
   - true if the variable is unset or empty in Claude Code's own `process.env`, unless the settings env knows it
   - HOME and PWD are never treated as possibly unset
   - TMPDIR/TMP/TEMP are treated as possibly unset (TMPDIR is exempt under the sandbox)
3. **Variable derived from `cd`, `pwd`, `dirname` or `git rev-parse`** in the same command. Example: `R=$(git rev-parse --show-toplevel); rm -rf "$R"`. A `${R:?}` guard does not help here.
4. **Command substitution as the target** of `rm -r`. Examples: `rm -rf "$(mktemp -d)"`, `` rm -rf `cat list` ``. `CLAUDE_CODE_DISABLE_SUBSTITUTION_RM_PROMPT` turns this one check off.
5. **Critical literal paths** (`Nae`/`Jne`):
   - `/`, `*`, anything ending `/*` at the root
   - the home directory (`~`, `$HOME`, `/Users/chrisren`)
   - **any direct child of `/`** (`mx(h)==="/"`): `/tmp`, `/Users`, `/usr`, and `/private/tmp` (normalised on macOS)
   - drive roots
6. **The workspace or one of its ancestors** (`Hd(cwdOrAddDir, target)`):
   - `rm -rf .`, `rm -rf ..`
   - **`rm -rf *` or `./*` run in the cwd** (the glob resolves to the cwd)
   - the absolute path of the current worktree or of any parent, e.g. `~/Development`
7. **Globs it cannot resolve:**
   - more than one glob level (`build/*/*`)
   - a glob after `..` (`a/../*`)
   - `~/x/*`
   - `cd X && rm -rf ./*` (a relative glob after a cd)
   - `rmdir -p a/*`
8. **Shell scripts:** `bash -c '...rm...'` that cannot be parsed, or one containing a command that a deny rule matches (`h_e`).

**Rewrites that do not trigger it:**
- **`"${DIR:?}"/*` or `"${DIR:?}/build"`.** The regexes accept only `${N}`, `${N:-}` and `${N:-$M}`, so `:?` does not match. `Xye`'s own remediation text recommends this form. Exceptions:
  - variables listed in `Byr` (HOME, PWD, TMPDIR, XDG_*, ...): the advice there is "use a literal absolute path"
  - text that is re-parsed (inside eval or a nested quote)
- **`"$DIR/build"`**, i.e. a variable followed by a literal segment that is not a top-level name.
- **Literal absolute paths below top level that are neither the workspace nor one of its ancestors.** Examples: `rm -rf /tmp/autodeny-census/x`, or another worktree's directory.
- **Plain relative names** such as `rm -rf build node_modules`.
- **Non-rm tools** (`git worktree remove`, `git clean`, `trash`). These are not checked by this detector, though the classifier still applies.

## b) Classifier denial limit
- **Limits.** `TW={maxConsecutive:3,maxTotal:20}` and `cJt=120000`.
  - `Cqe(e)= consecutiveDenials>=3 || totalDenials>=20`.
  - Every classifier block runs `CF(M,Eqe)`, which adds 1 to both counters.
- **Default timeout.** `jvr(){return Bn.CLAUDE_CODE_TICKLISH_WHISPER_TIMEOUT_MS??cJt}`, so **120 s**.
- **When the timer applies** (`iTr`): `ke = f1(...) && !total && mode is auto && dialog surface && !WYt && consecutive>=3 && timedFallbackShown!==true`.
  - `f1 = (env CLAUDE_CODE_TICKLISH_WHISPER ?? flag tengu_ticklish_whisper default false) && hasDialog && !bz()`.
  - Cached flag values: **true** in ~/.claude-secondary, ~/.claude-tertiary and ~/.claude-quaternary (`.claude.json`); **false** in ~/.claude.json.
- **One timed dialog per streak.** After the first timed dialog, `timedFallbackShown=true`. Later limit hits show a **blocking** `denialLimitFallback` with no timer. The flag is cleared by `$M` (an allow) or by a total-limit reset.
- **Total limit (20).** This always produces the legacy fallback, with no timer, and both counters go back to 0.
- **Counter reset on allows (my reading of the code).** When `f1` is on, fast-path and allowlist allows do **not** reset the consecutive counter (`if(!f1(...))CF(M,$M)`). Only classifier allows reset it.
- **Deny text when the timer expires.** The resolution is `nTr(...)`, which is the ordinary classifier denial: `"Permission for this action was denied by the Claude Code auto mode classifier. Reason: <reason>. If you have other tasks that don't depend on this action, continue working on those. "+xUr`. `toolDenialKind` is "automode-blocked". **This text is the same as a normal classifier block.**
- **Telemetry events.**
  - `tengu_auto_mode_denial_limit_exceeded{fallbackShape:"timed"|"blocking"|"legacy"}`
  - `tengu_auto_mode_denial_dialog_auto_denied`
  - local `permission_auto_mode_denial_fallback{autoDenied}`
- **Headless.** When `shouldAvoidPermissionPrompts` is set, it throws `Ve("Agent aborted: too many classifier denials in headless mode")`. The agent is **aborted**, not prompted.

## c) What prevents each dialog
| Mechanism | (1) rm safety timer | (2) denial-limit timer |
|---|---|---|
| permissions.allow (Bash(...) or the whole tool) | **No.** In `Uln`, an ask whose reason is a safety check is returned before the allow rule is consulted. `kSr` runs the rm check before an exact-match allow. Message: "cannot be auto-allowed by permission rules". | **Indirectly.** Actions that match an allow rule skip the classifier and never count as denials. |
| permissions.deny rule | Yes, but it becomes a plain deny (`Jin` runs first). | Same. |
| PreToolUse `allow` | **No.** `T0o`→`KA()` returns the safety-check ask, logs "a safety check ... requires the full permission pipeline" and goes on to `wln`. | In auto mode, a hook allow is funnelled to the classifier with `hookAllowVouched` (`tengu_auto_mode_hook_allow_funneled`). That does not reliably avoid denials. |
| PermissionRequest hook `allow` | **Yes (interactive).** `runHooks` runs for every ask that is not `personOnly`. It runs before the dialog when `awaitAutomatedChecksBeforeDialog` is set, otherwise in parallel with it. `handleHookAllow` then allows, with no `mre` check. **Return no `updatedInput`**: with it, `KA` re-checks, the safety ask comes back and the dialog re-prompts. In headless or async contexts, `wln` denies before any hook runs. | Yes, by the same path. |
| bypassPermissions | **Immune.** `Ce=$d(q.decisionReason,mre)` returns the ask, then `wln` applies in bypass mode too. | Not applicable (auto mode only). |
| `CLAUDE_CODE_DISABLE_DANGEROUS_RM_TIMEOUT` | Sets `q5().enabled=false`, so `wln` is skipped. In auto mode, `Ft` excludes classifier-routed breakers, so I infer that dangerousRemoval is **sent to the classifier**. In bypass mode it is a normal prompt that waits indefinitely. Headless denies through `RF`. It does **not** allow outright. | — |
| `showDialog:false` (server flag only) | **Denies immediately** with the `Gln` text. | — |

**Flag details.** `tengu_splendid_horizon.enabled` is honoured only from a server payload, so the default is on. No cached value was found in any profile.

## d) Hook events
- **PermissionRequest fires for both timed dialogs**, through `m2e`/`runHooks`. It also fires headless through `Sln`→`RQn`→`Jvr`, but `wln` denies before `Sln` is reached.
- **PermissionDenied exists in 2.1.293** (`eVr`), described as "After auto mode classifier denies a tool call". It fires only when `decisionReason.type==="classifier"&&classifier==="auto-mode"`. It **does** fire on a denial-limit timeout. It does **not** fire on the rm safety-check deny (decisionReason type `safetyCheck`). It can return `retry:true`.

## e) First installed version with each feature
| Version (folder) | "automatically deny this request" | autoDenyWindow / safety_check_dialog_auto_denied | denialLimitFallback / TICKLISH_TIMEOUT | "Classifier denial limit" |
|---|---|---|---|---|
| 156, 161, 170, 183 (=2.1.215), 219, 220 | 0 | 0 | 0 | yes |
| **260**, 280 | yes | 0 | **yes** | yes |
| **284**, 293 | yes | **yes** | yes | yes |

Counts measured with `grep -a -c -F` on each claude.exe.
- **Timed classifier fallback:** first seen in 2.1.260.
- **Timed rm safety dialog:** first seen in 2.1.284, along with `CLAUDE_CODE_DISABLE_DANGEROUS_RM_TIMEOUT`.
- **"Classifier denial limit":** present in 2.1.156 and later.
- Versions between these were not installed, so these are lower bounds only.

## Markers for the transcript census
- **(1) rm safety check:** a tool_result containing `Permission for this command was denied by a built-in Claude Code safety check, not by the user.` This one string covers three cases:
  - a timer that expired
  - an immediate deny in headless or async runs
  - the capped case, which adds "has already gone unanswered N times"
- **(2) denial limit:** cannot be told apart by text. Look for a 4th or later consecutive "denied by the Claude Code auto mode classifier" result about 120 s after the previous one, in a profile where `tengu_ticklish_whisper` is on.
