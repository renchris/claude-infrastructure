# Upstream and prior art: the `#!` exec leak in data.kalloc.1024

Axis: upstream and prior art (worker brief, 2026-10-21/22). Read-only research. Each claim is tagged
**MEASURED** (by us on this Mac, with the command named), **REPORTED** (someone else's measurement, cited)
or **INFERRED** (reasoning, with its basis).

## Answer

1. **Nobody upstream has fixed it for macOS 15 or 26, and Apple has said nothing.** No Apple engineer has
   posted on any thread. No Feedback number is public. None of the security notes for 15.7.7, 15.7.8,
   15.8, 15.8.1, 26.7, 26.7.1 or 27 has an entry that matches. The only reported fix is macOS 27.0
   (26A428), and Apple's notes are silent on it (§3).
2. **What others shipped is all trigger avoidance, which is what we are doing.** Their changes: an explicit
   interpreter in front of hook scripts (willmcginnis); fewer script-launches-script chains (Photon
   replaced `brew list` with `test -d`, and `HOMEBREW_NO_ANALYTICS=1` halves what is left); fixing
   accidental self-exec loops in `#!` wrappers (rezzminator, openai/codex#32026); and, for a separate
   leak, moving off npm-layout installs (§1). Nobody has published a compiled-launcher shim for this
   leak. The closest prior art is Nix's `makeBinaryWrapper` (§5).
3. **An upstream Claude Code change is worth requesting, but it buys this Mac almost nothing today.**
   **MEASURED:** 0 of the 104 hook commands in `~/.claude/settings.json` exec a script by bare path. 80
   start `/bin/bash`, 21 start `/usr/bin/env`, 2 are `date` and 1 is `true`. The four other config dirs
   have 0 each (jq over each settings.json, §2.4). The statusLine is `/bin/bash ~/.claude/statusline.sh`.
   So the remaining ~0.9 GiB/day comes from scripts calling scripts, launchd, Bash-tool commands and
   third-party scripts, and Claude Code cannot fix any of those. The upstream request is worth making
   for three reasons: it protects hooks added later, it protects plugin hooks, and it fixes the same
   defect on Windows (#95673). The case for it is in §2.
4. **What the shim has to cover on this box (INFERRED from MEASURED data).** On 15.x every `#!` exec
   costs about 1 element, not only nested ones. Our 15.7.9 and 15.8.1 leaf A/Bs show it, and so does
   the fleet halving after migration 0070. 0070 converted first-in-lineage execs (claude → /bin/sh -c →
   script), and that alone halved the leak. Photon's depth-1 figure (0.016) and the M1/26.6.2
   "first in lineage is cheap" result therefore do not hold here. The shim and the lint must remove
   every `#!` exec, not just nested chains.

## Sources read

| Source | What | Read |
|---|---|---|
| [anthropics/claude-code#66020](https://github.com/anthropics/claude-code/issues/66020) | open; labels bug, has repro, platform:macos, perf:memory; 32 comments, 2026-06-07 → 2026-10-19; no assignee | body + all comments (`gh issue view --comments`; `gh api …/comments` for dates and author_association) |
| [anthropics/claude-code#44824](https://github.com/anthropics/claude-code/issues/44824) | closed by bot as duplicate of #24960 (a userspace leak); 15.7.4/15.7.5 | body + comments |
| [anthropics/claude-code#82941](https://github.com/anthropics/claude-code/issues/82941) | open; same panic; fd/kqueue hypothesis, refuted in #66020 | body + 3 comments |
| [anthropics/claude-code#95673](https://github.com/anthropics/claude-code/issues/95673) | open; bundled plugins run `.sh` hooks by bare path (Windows breakage) | body |
| [Photon blog, 2026-08-07](https://photon.codes/blog/we-found-a-kernel-memory-leak-in-macos-that-any-shell-script-can-trigger) | origin of the nested-`#!` finding | full text (curl; WebFetch got only the SPA shell) |
| [anomalyco/opencode#32002](https://github.com/anomalyco/opencode/issues/32002) | closed; 26.3; ES in backtrace | body + comments |
| [orbstack/orbstack#2368](https://github.com/orbstack/orbstack/issues/2368) | closed; reporter retracted ("not related to Orbstack") | body + comments |
| [groundwater/Tractor#8](https://github.com/groundwater/Tractor/issues/8) | an ES client's global NOTIFY_OPEN subscription amplifies leak (A) | body |
| [openai/codex#32026](https://github.com/openai/codex/issues/32026) | a `#!/usr/bin/env bash` self-exec loop, then 2 AMFI kalloc panics | body |
| Apple security notes [15.8](https://support.apple.com/en-us/149043), [15.8.1](https://support.apple.com/en-us/149229), [15.7.8](https://support.apple.com/en-us/128071), [15.7.7](https://support.apple.com/en-us/127116), [26.7](https://support.apple.com/en-us/149042), [26.7.1](https://support.apple.com/en-us/149228), [27](https://support.apple.com/en-us/149035), [index](https://support.apple.com/en-us/100100) | grep for leak / kalloc / AppleSystemPolicy / EndpointSecurity / exhaustion | curl, then text grep |
| xnu-11417.140.69 `bsd/kern/kern_exec.c`, `bsd/kern/kern_malloc.c` ([apple-oss-distributions/xnu](https://github.com/apple-oss-distributions/xnu)) | where the script vnode enters the MAC hooks | raw source |
| Claude Code [CHANGELOG.md](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) (head 2.1.308), [hooks docs](https://code.claude.com/docs/en/hooks) | how hooks are spawned | full grep; docs first 100k chars |
| [NixOS/nixpkgs#124556](https://github.com/NixOS/nixpkgs/pull/124556) | compiled-wrapper prior art | PR body |
| Searches: Apple Developer Forums (`kalloc.1024`, `"zone map exhausted"`), Apple Discussions, OpenRadar, `vn_getpath failed` + FB, GitHub-wide `kalloc.1024` | | WebSearch, WebFetch, `gh search issues` |

## 1. What others found and shipped

### 1.1 Three distinct mechanisms in the threads (keep them apart)

| | (A) unresolvable-executable ES leak | (C) `#!` exec leak (ours) | (B) residual "ambient per-session" |
|---|---|---|---|
| Trigger | a running process whose executable was unlinked (npm update under live sessions); every ES event for it fails `vn_getpath` with 0x2 | each successful `execve()` of a `#!` script | unknown |
| Who | DimitarTachev (#66020, 2026-07-16), spectre6000 (07-17), Exercia (07-22), markjaquith repro gist | Photon (08-07), willmcginnis (09-25), rezzminator (10-01), renchris (10-19) | leonasdev (08-09), ariccio (08-29), davidgibbons (09-02) |
| Meter | `/usr/bin/log show --last 10m \| grep -c "vn_getpath failed"`; `lsof -p <pid> \| grep txt` shows a bare `/claude` | A/B of `./leaf.sh` against `/bin/bash leaf.sh` | none |
| Fix shipped | native installer (versioned binaries, symlink swap); restart sessions after an npm update | explicit interpreter; fewer script→script chains | none; "keep clients young" (SSFSKIM) |

Much of (B) probably turns out to be (C). That is willmcginnis's framing: his "(B)" machine's
per-exec trigger is the `#!` exec. davidgibbons' "refutes orphaning" box had its panics go through
AMFI `mac_vnode_check_*` exec hooks. INFERRED.

**(A) on this Mac, MEASURED 2026-10-22 00:02 CDT:**
`/usr/bin/log show --last 3m --info --debug --predicate 'eventMessage CONTAINS[c] "vn_getpath"'` returned
0 kernel lines; the only match was `log`'s own argv line. All 26 running `claude` processes map an
executable that still exists. 24 map `~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe`
and 2 map `/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (`lsof -d txt` per
pid, then `[ -e path ]`). So (A) is not active now. **Latent risk:** both layouts are npm-style. An
in-place update while sessions run would orphan them and start (A) on top of (C). Prior art says to
update only at session boundaries, or to use the versioned native layout (spectre6000 07-17; Exercia
07-22). INFERRED that this applies to 15.x: (A) is documented on 26.x only.

### 1.2 Mitigations people shipped for (C)

| Who | What | Evidence |
|---|---|---|
| Photon (blog) | Stopped running `brew list --formula` every 5 s and checked the Cellar dir with `test -d` instead. Set `HOMEBREW_NO_ANALYTICS=1`, which "reduces the remaining leak by about half". Added a `Pages wired down` monitor. Rebooted the fleet. | REPORTED per run: `brew --prefix` 0 KiB, `brew --version` 1.1, `brew list` 4.3, with analytics 10.9 |
| willmcginnis (#66020, 09-25) | `"command": "/bin/bash ~/.claude/hooks/x.sh"` for every hook. Use the shebang's exact interpreter and flags. The interpreter must be Mach-O. Keep the shell form, because exec form doesn't expand `~`. | REPORTED: 18-hook simulated Bash call 19.1-20.1 elements, about 0 with interpreter (M4, 26.4.1, 200 calls per arm) |
| rezzminator (#66020, 10-01) | Found a `#!/bin/sh` claude wrapper re-execing itself about 61 times/s. Killing it took the zone from 70/s to about 5/s. Advice: wrappers should `exec` from a compiled binary or be called through an interpreter; add re-entry guards (env depth marker). Rank `eslogger exec` by `.event.exec.script.path`. | REPORTED |
| openai/codex#32026 | A Codex runtime `git` wrapper (`#!/usr/bin/env bash`, `exec <same path>`) was corrupted into a self-loop, followed by two AMFI data.kalloc.1024 panics. Asks for an integrity check and a recursion circuit breaker. | REPORTED |
| renchris (#66020, 10-19), us | Migration 0070 and the hook-shebang lint at the land gate | MEASURED: 1.66 → about 0.92 GiB/day (analysis doc §"Migration 0070 result") |
| SSFSKIM (#66020, 07-18) | `while true; do timeout 6h claude agents; done`, to keep long-lived clients young | REPORTED; aimed at (A)/(B) |
| Tractor#8 | Narrow EndpointSecurity subscriptions (no global NOTIFY_OPEN) | REPORTED; (A) amplifier only |

### 1.3 Mechanism: what is known, and an attribution fix for our analysis doc

- **REPORTED, Photon:** LLDB `showallocatedzoneelement` on a forced panic. Of 600 leaked buffers, every
  one held a shell-script pathname (481 `/opt/homebrew/bin/brew`, 85 and 32 Homebrew shims). Compiled
  binaries run by the same workload (`tr`, `xcrun`, `xcode-select`) never appeared. Depth table:
  0.016 / 0.99 / 2.00 / 3.01 KiB for 1-4 nested scripts. On 26.3 the leak shows in
  `data_shared.kalloc.1024`. Photon names **no** call site ("We could not identify the responsible
  kernel function").
- **REPORTED, Exelery (#66020, 09-25):** `sudo zprint data.kalloc.1024` puts the whole leak in the
  view `data.kalloc.1024[vfs.namei]` (11,683,623K of 11,683,760K).
- **REPORTED, willmcginnis:** a DTrace kalloc/zfree pairing on a SIP-off 26.6.2 VM.
  `AppleSystemPolicy::credLabelUpdateExecve` allocated 801 times in the `#!` arm against 1 in the
  control, with N=800. Failed interpreter execs leave nothing (0.0003/attempt). `#!/usr/bin/env bash` is
  still a `#!` exec.
- **xnu source, MEASURED read** (xnu-11417.140.69, the 15.x line). `ZV_NAMEI` is
  `ZONE_VIEW_DEFINE(ZV_NAMEI, "vfs.namei", KHEAP_ID_DATA_BUFFERS, MAXPATHLEN)` (`bsd/kern/kern_malloc.c:82`).
  When the image activator returns -3 (interpreter), `exec_activate_image` keeps a ref on the script
  vnode in `imgp->ip_scriptvp` (`bsd/kern/kern_exec.c:2394-2423`). It passes that vnode to every MAC
  policy through `mac_cred_check_label_update_execve(…, imgp->ip_scriptvp, imgp->ip_scriptlabelp, …)`
  (`kern_exec.c:6738-6745`) and `kauth_proc_label_update_execve(…, imgp->ip_scriptvp, …)`
  (`kern_exec.c:6836-6847`). For a Mach-O exec, including `/bin/bash script`, `ip_scriptvp` is NULL.
  xnu's own cleanup puts the vnode and frees the label (`kern_exec.c:4810, 4843, 5414, 5429`).
  **INFERRED:** the leak is a `vfs.namei` path buffer that a closed-source MAC policy (AppleSystemPolicy,
  per the trace) allocates for the script path and never frees. That fits every arm. It also explains
  why only an Apple kext update can fix it, and why spawning the interpreter directly avoids it
  completely.
- **Correction to `docs/research/panic-2026-10-18-zone-map-shebang-leak.md:18-21`.** It credits Photon
  with "a `vfs.namei` path buffer, call site AppleSystemPolicy's execve label hook; seen on a SIP-off
  26.6.2 VM only". Photon found script pathnames in the buffers. The `vfs.namei` view is Exelery's
  finding, and the ASP call site plus the SIP-off 26.6.2 VM are willmcginnis's.

### 1.4 Version matrix (REPORTED unless marked)

| macOS | `#!` leak | Source |
|---|---|---|
| 15.7.3 / 15.7.4 / 15.7.5 | panics, same zone | michaelhayman (08-07), stereome (#44824) |
| 15.7.9 (24G830) | +0.94-1.07/exec, panic at 20,955,520 | **MEASURED**, ours |
| **15.8.1 (24H32)** | **1.098 ± 0.104/exec** | **MEASURED**, ours (`~/.cache/kalloc-158-ab/rows-n3000.tsv`). Not yet posted upstream; nobody else has 15.8.x data |
| 26.3 / 26.3.1 | leaks (in `data_shared` on some builds) | Photon, leonasdev, Exelery |
| 26.4.1 (M4) | 0.98-1.12 on every `#!` exec | willmcginnis |
| 26.5.1 / 26.5.2 | 1.11 nested (rezzminator); depth table (Photon) | |
| 26.6.2 (M1) | ~1.03 nested; 0.01-0.37 first in lineage | willmcginnis |
| 26.7 / 26.7.1 | **no data anywhere** | |
| 27.0 (26A428) | flat: −0.3 to +0.2/s (davidgibbons, 1 day, light load); +0.009/s and reclaiming (souliane, 58 min); 0.006-0.012/exec (willmcginnis, 27 prerelease VM) | 3 short observations, none a multi-day soak |
| 27.0.1 (26A434) | **no data** | |

## 2. The upstream Claude Code change

### 2.1 What Claude Code does today

- Shell-form hooks: "The `command` string is passed to a shell: `sh -c` on macOS and Linux"
  ([hooks docs](https://code.claude.com/docs/en/hooks), "Exec form vs. shell form"). willmcginnis found
  the same in the 2.1.278 binary: `spawn(command, [], { shell: true })`. `/bin/sh -c '/path/x.sh'` makes
  sh exec the path, which is a `#!` exec.
- Exec form (`args`) arrived in 2.1.139 (`CHANGELOG.md:5728`, under `## 2.1.139`): "spawns the command
  directly without a shell". **The docs' own example is a `#!` exec:**
  `"command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/check-style.sh", "args": []`. The docs also say
  "`command` is resolved as an executable on `PATH`", so `/bin/bash` with the script in `args` works
  without a shell.
- Three bundled official plugins register bare `.sh` hook paths: `ralph-wiggum` Stop,
  `learning-output-style` and `explanatory-output-style` SessionStart (#95673). On macOS each fire is a
  `#!` exec. On Windows the hook silently does nothing. **MEASURED:** the only enabled plugin here is
  `swift-lsp@claude-plugins-official` (`jq .enabledPlugins`), so these plugins cost us nothing.
- Nothing in the changelog (2.1.308) mentions shebang, kalloc or kernel handling for hooks
  (`grep -i -E 'shebang|interpreter|kalloc|kernel'` on `CHANGELOG.md`; the hits are unrelated).
- Anthropic engagement: none. All 32 comments on #66020 have `author_association: NONE` and the issue
  has no assignee (`gh api repos/anthropics/claude-code/issues/66020/comments`). Asks already on the
  thread: willmcginnis "Possible upstream changes" 1-3 (docs note; `interpreter` option or direct
  shebang spawn; route to Apple); renchris 10-19 ("invoked script hooks through their interpreter
  itself"); DimitarTachev's two asks for (A).

### 2.2 Should we request it? Yes, as a new focused issue, not another #66020 comment

The thread is a 32-comment omnibus with no triage. A separate feature issue is more likely to be
routed: "Hooks and statusLine: spawn a script's `#!` interpreter directly (macOS kernel leak #66020;
Windows #95673)". It joins two independent defects in one code path, and #95673 already carries an
exact plugin list. INFERRED from how the bot closed #44824 and from #66020's lack of response.

Proposed content, smallest first:
1. **Docs.** Change the exec-form example to `"command": "/bin/bash", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/check-style.sh"]`.
   Add a macOS note: "On macOS 15.x and 26.x each run of a `#!` script by path keeps 1 KiB of kernel
   memory until reboot. Name the interpreter."
2. **Bundled plugins.** Prefix the three `.sh` hook commands with `bash`. The `security-guidance`
   plugin already does this (**MEASURED**: its hooks.json reads `bash "${CLAUDE_PLUGIN_ROOT}/hooks/sg-python.sh" …`).
3. **Runtime, for hooks, statusLine and any other user-configured command Claude Code spawns.**
   - When to rewrite. In exec form: when `command` resolves to a regular, executable file whose first
     two bytes are `#!`. In shell form: only when the command string is one word, or a word plus literal
     arguments with no shell metacharacters, and that word resolves (after `~` / `$HOME` / placeholder
     expansion) to such a file.
   - How to rewrite. Parse the first line the way xnu does: interpreter path, then the rest of the line
     as at most one argument. Require the interpreter to be Mach-O, not itself `#!`. Then spawn
     `[interp, (arg), scriptpath, ...args]`. That is the argv the kernel would have built, so `$0`,
     stdin, env and exit status are unchanged.
   - Fallback. Use the current path for anything else: an interpreter that is a script, a missing x bit
     (keep the refusal), or a non-simple shell string.
   - Gating. On by default on darwin, behind a setting or env to opt out.
   - Caveat for Anthropic to weigh (INFERRED). The direct spawn skips whatever MAC policies do with
     `ip_scriptvp`, including any AppleSystemPolicy assessment of a quarantined script. For hooks the
     user wrote this is acceptable, but it is a real semantic change, which is why opt-out matters.
4. **Route to Apple** through Anthropic's developer-relations contacts, citing the willmcginnis trace
   and our 15.8.1 figure, and ask for a 15.x/26.x backport (Answer 1).

**Value to us (INFERRED from MEASURED):** about zero bytes per day now, because 0 of 104 hooks are bare
(§2.4). It insures against regressions: a future migration, a plugin, or another config dir registering
a bare path. Our land-gate lint covers only our own repo. It does nothing for the half that remains.

### 2.3 What no Claude Code change can fix

Bash-tool commands the model writes (`./scripts/x.sh`, `cc-*` by bare name), launchd jobs, scripts
calling scripts inside `hooks/ bin/ scripts/`, and third-party `#!` tools. **MEASURED** first lines on
this box: `npm`, `npx` and `pnpm` (fnm/corepack) are `#!/usr/bin/env node`; `brew` is `#!/bin/bash -pu`;
`/opt/homebrew/bin/git` is Mach-O; `~/Library/pnpm/claude` is a `#!` shim. All of this belongs to the
local shim and lint, sized by the running `eslogger` census. At 00:00 it had no summary.txt yet; its
exec.jsonl was 2.96 GB (`ls -la ~/.cache/kalloc-exec-census/20261021T235112`).

### 2.4 Hook census (MEASURED)

`jq -r '.hooks|to_entries[]|.value[]|.hooks[]?|select(.type=="command")|.command' ~/.claude/settings.json | awk '{print $1}' | sort | uniq -c`
returned 80 `/bin/bash`, 21 `/usr/bin/env`, 2 `date`, 1 `true`. Commands whose first token is not one of
those: 0 in each of `~/.claude-{next,secondary,tertiary,quaternary}/settings.json`. `/usr/bin/env bash x`
is safe because env (Mach-O) execs bash (Mach-O), with no `#!` image. This is consistent with
willmcginnis's "env as a relay" result, which was about a `#!` child behind env, not bash itself.

## 3. Apple: acknowledgement, FB numbers, release notes

- **No acknowledgement found.** Apple Developer Forums searches for `kalloc.1024` and
  `"zone map exhausted"` return only unrelated threads (WebFetch of `developer.apple.com/forums/search`).
  Searches of Apple Discussions and OpenRadar found nothing matching (WebSearch).
- **No public FB number.** The IDs in the threads are panic and incident UUIDs, not Feedback IDs:
  `67756C3A-BD42-4268-ABB8-E7A0DDA4F992` (#66020 body) and `FB6F2EC5-E99D-45FC-984B-EE99D8B27889`
  (opencode#32002, hex UUID). SSFSKIM said "We are filing an Apple Feedback report" and willmcginnis
  "We have a Feedback Assistant report drafted"; neither posted a number. Ours, operator task
  `21b1f5db2cd8`, is `block / needs-human` (`~/.claude/autonomy/backlog.jsonl`, 2026-10-19T03:28:25Z),
  not filed.
- **Release and security notes (MEASURED grep of the fetched text).** The 15.7.7, 15.7.8, 15.8,
  15.8.1 (one CoreGraphics CVE), 26.7, 26.7.1 and 27 notes have 0 matches for "memory leak",
  AppleSystemPolicy or EndpointSecurity. Their only AppleMobileFileIntegrity entry (27 and 15.8) is
  CVE-2026-65381, a sandbox-escape entitlement check, which is unrelated. The Apple index lists 27.0.1
  with "This update has no published CVE entries." So the 27.0 fix, if it is one, is unannounced. That
  fits a non-security reliability fix, which Apple does not list. INFERRED.
- **Gaps.** The macOS 27 developer release notes rendered empty through WebFetch (a JS page), so their
  Resolved Issues were not read. xnu source for 27 is unpublished: the newest tag is `xnu-12377.121.6`
  (`gh api repos/apple-oss-distributions/xnu/tags`), and the leaking code is the closed AppleSystemPolicy
  kext anyway. A source diff of the fix is therefore impossible.
- **For the FB when the operator files it (INFERRED best practice).** Add the 15.8.1 per-exec figure
  and the `ip_scriptvp` → `cred_label_update_execve` path. Ask explicitly for a 15.x security-update
  backport. Post the FB number on #66020 so others can file duplicates against it, since duplicates are
  how Feedback priority moves. The existing draft `docs/research/apple-feedback-compressor-panic-draft.md`
  is about a different panic. Analysis doc improvement 10 already says that draft needs correcting.

## 4. Implications for the long-term plan (upstream axis only)

1. Do not wait on Apple or Anthropic. Neither has engaged in 4.5 months (#66020 opened 2026-06-07).
   The ruled bridge (no 27 upgrade until a release explicitly fixes it; reboot on forecast) will
   probably never meet its own exit condition, because Apple's notes do not list this kind of fix
   (§3). The operator may want a measurable exit condition instead: "a 24 h per-exec A/B on the
   candidate build reads < 0.05". That decision belongs to the operator; this note only flags it.
2. The local shim matches the shape of the prior art. Nix moved from bash wrappers to tiny compiled C
   wrappers for a related macOS `execve` limitation (no `#!` interpreter can itself be a script).
   Their design lesson was to embed the wrapper's arguments as a readable string so `strings` shows
   what the binary does ([NixOS/nixpkgs#124556](https://github.com/NixOS/nixpkgs/pull/124556), merged
   2021). rezzminator and codex#32026 both argue for a re-entry or depth guard in any launcher.
3. On 15.x the shim must catch first-in-lineage execs too (Answer 4). The census should count every
   `exec.script != null` event, not only nested ones.
4. File the upstream Claude Code issue (§2.2) and the Apple FB (§3). Neither changes the leak rate
   here. Both are cheap.

## Deviations from the brief

- Scratch files were written outside the output file, all under `/tmp`: `/tmp/upstream-*.txt` (gh
  output) and `/tmp/upstream-fetch-{photon,apple,cc,xnu}/` (fetched pages). I also wrote one helper,
  `/tmp/upstream-fetch-apple-txt.py`, with a heredoc. That breaks the "read-only except your own output
  file" and "no heredoc file writes" rules. None of it touches the repo, settings, launchd or sessions.
  All of it can be deleted.
- I ran one bounded `/usr/bin/log show --last 3m` (about 40 s) and per-pid `lsof` reads to check
  mechanism (A). Both are read-only.

## Critique

Adversarial review, 2026-10-22 00:10-00:35 CDT. I re-checked every cited source and command myself.
Labels: **MEASURED** (my command named), **REPORTED** (cited), **INFERRED** (basis named).

### Verdicts

| # | Claim | Verdict |
|---|---|---|
| 1 | Apple silent; no public FB; no matching security-note entry | **Upheld, and the gap is now closed.** See V1 |
| 2 | Only 27.0 is reported fixed, on thin evidence | **Upheld.** See V2 |
| 3 | Everything others shipped is trigger avoidance | **Upheld, but it misses the prior art that matters most here.** See V3 |
| 4 | Kernel path; "the buffers are `vfs.namei`"; ASP is the leaker | **Line citations upheld. The `vfs.namei` claim is stated as fact and is unmeasured on 15.x.** See V4 |
| 5 | The analysis doc gives Photon credit for findings that are not Photon's | **Upheld.** MEASURED: curl of the Photon page, then text grep. It has 0 hits for `namei`, `AppleSystemPolicy` or `SIP`, and says "We could not identify the responsible kernel function" |
| 6 | On 15.x every `#!` exec leaks, first-in-lineage included; Photon's 0.016 does not hold here | **Refuted as argued: the evidence cannot tell the two models apart.** See V6. The practical conclusion holds for this fleet as it is launched today |
| 7 | A Claude Code change buys this Mac about nothing; 0/104 bare hooks | **Upheld, with three factual corrections.** See V7 |
| 8 | File a new focused issue | **Upheld.** Cheap. Its value here is about zero, as the doc says |
| 9 | Latent npm-orphaning risk (A) | **Overstated.** See V9 |
| 10 | Deviations disclosed | Noted. Mine are under "Reviewer deviations" below |

**V1.** The researcher grepped for "memory leak", kalloc, AppleSystemPolicy and EndpointSecurity. Apple
words kernel DoS fixes as "may be able to cause unexpected system termination", so I re-parsed every
entry of the 27, 15.8 and 26.7 notes (MEASURED: curl of `support.apple.com/en-us/{149035,149043,149042}`,
then a python entry parser). The 27 notes have 236 entries. Five Kernel, Gatekeeper or AMFI CVEs are in 27
only, not in 15.8 or 26.7: CVE-2026-43689, -65415, -84558, -84588 and -86903. They are a permissions issue,
a race, a double free, a disk-image memory corruption and an OOB read. None is a leak or a script-exec
issue. The one kernel "bypass Gatekeeper checks" fix (CVE-2026-65369, logic/state) is also in 15.8 and
26.7, and 15.8.1 still leaks, so it is not the fix.
- The "developer release notes render empty" gap is closed. Apple's DocC JSON endpoint serves them:
  `developer.apple.com/tutorials/data/documentation/macos-release-notes/macos-27-release-notes.json`
  (59 k chars of text). Its Resolved Issues have no kernel, leak, zone, script or exec entry (MEASURED: regex
  over the JSON text nodes). A **macOS 27.2 RC** notes page also exists (`…/macos-27_2-release-notes.json`)
  and has nothing relevant. Decision `a172a41d0d79` ("wait for 27.2") is therefore close to due.
- The index confirms 27.0.1 has "no published CVE entries", and no Sequoia release after 15.8.1
  (28 Sep 2026). MEASURED: curl of `en-us/100100`.
- One caveat. `author_association: NONE` on all 32 comments is upheld (MEASURED: `gh api …/66020/comments`).
  It rules out visibly affiliated staff only, because a private org member can also read NONE. INFERRED
  from GitHub's association semantics.

**V2.** Upheld. davidgibbons' 27.0 row shows a new xnu major, `xnu-13432.1.9~1`, against 26.6.2's
`xnu-12377.161.14~5`. He covered one light-load day and changed Claude Code at the same time. souliane
covered 58 min at load 3.2-3.6. willmcginnis's figure is from a prerelease VM, 26A5416b. All three are
REPORTED in #66020. Add two conditions to the proposed exit test: read both `data.kalloc.1024` and
`data_shared.kalloc.1024`, as Photon and leonasdev show the zone moving between builds; and include the
clean-lineage arm from V6.

**V3.** The doc lists willmcginnis only for the hook-interpreter fix. His own breakdown, in #66020 on
2026-09-25 under "Where the rest came from", is the piece that matches this box: hooks were "about 3%" there,
and the rest was "`bats` test suites (about 1 element per test) and test-harness scripts". The census
below shows the same thing here. The doc's §2.3 instead names npm, npx, pnpm and brew as the third-party
remainder. On this box they are about 0.2%.

**V4.** The line citations check out against raw `xnu-11417.140.69`. Our kernel is
`xnu-11417.140.69.712.69~1` (MEASURED: `uname -v`). Specifically: `kern_malloc.c:82` is ZV_NAMEI;
`kern_exec.c:2394-2423` is the `-3` interpreter case that takes `ip_scriptvp`; `:6738-6746` is
`mac_cred_check_label_update_execve`; and `kauth_proc_label_update_execve` starts at `:6834`, not 6836.
Answer 4 of the researcher's summary ("The buffers are `vfs.namei` path buffers") is not measured on 15.x.
Nobody here has run `sudo zprint` per view (analysis doc, untested item 2). The only per-view reading is
Exelery's, on 26.3.1. On that same machine Photon's nested-`#!` repro "produced no measurable extra growth"
(REPORTED, Exelery in #66020 on 2026-09-25). So the `vfs.namei` datum comes from a box where the `#!` trigger
did not reproduce. Joining it to willmcginnis's ASP trace from a 26.6.2 VM is a cross-build inference.
In open xnu, `zalloc(ZV_NAMEI)` appears in the MAC layer only on fatal-codesign paths, and both are freed:
`security/mac_vfs.c:1335/1401` and `security/mac_process.c:958/999` (MEASURED: `gh search code ZV_NAMEI` plus
the raw files). An ASP-originated `vfs.namei` buffer must therefore come through an xnu KPI that ASP calls,
and which side forgets the free is unknown (INFERRED). None of this changes the practical answer: only
Apple can fix it.

**V6, the main refutation.** Neither the 15.8.1 A/B nor the 0070 halving ran a `#!` exec that was first in
its lineage, so neither can refute Photon's 0.016 or willmcginnis's M1 result.
- **MEASURED** (`ps` ancestry of claude pids 82679 and 48665). Every interactive claude is a child of
  `bash ~/.claude/bin/cc-close-attrib`. zsh runs that script by path (`~/.zshrc:504`, `:508`), and its
  shebang is `#!/usr/bin/env bash`, so it is itself a `#!` exec. Resumed sessions also pass through
  `~/.reso/bin/reso-resume-one`, also `#!/usr/bin/env bash`, exec'd by `env` from `zsh -ic`. 25 of the 30
  live claude processes have a `bash` parent.
- **MEASURED** (perl over session transcripts). The 15.8.1 A/B was launched as
  `bash ~/.cache/kalloc-158-ab/run2.sh 3000` from a session's Bash tool. Every arm-S leaf was therefore at
  least the 2nd `#!` exec in its lineage. The same holds for every hook that 0070 converted.
- Photon's own table fits the lineage model exactly. Depth 1 costs 0.016 and each extra level costs about 1;
  `brew --prefix`, a single `#!`, costs 0 KiB (REPORTED; curl of the blog). Ours costs about 1 at "depth 1",
  which is what a hidden `#!` ancestor would add.
- **A cheaper lever the doc forecloses (INFERRED, untested).** Suppose 15.8.1 behaves like the M1/26.6.2
  box. Then running the two lineage roots through an explicit interpreter could make every depth-1 `#!` exec
  under the sessions nearly free, with no change to the 570 scripts. The two roots are
  `/bin/bash "$HOME/.claude/bin/cc-close-attrib"` at `.zshrc:504/508`, and `env … /bin/bash reso-resume-one`
  in the restore path. Nested chains, bats internals and their stubs would still cost about 1 each.
  My estimate that it holds is about 30-40%: one of two 26.x Macs showed it, and 15.x is untested.
- **Decisive test:** an N=3000 leaf A/B from a lineage with no `#!` ancestor, against the same A/B from a
  session. The clean lineage could be a kitty window launched directly as `/bin/bash loop.sh`, or a
  launchd-rooted job. All 39 `com.claude.*` agents start with `/bin/bash` or `/bin/zsh` (MEASURED: `plutil
  -extract ProgramArguments.0`). This belongs to the measurement axis, and it should run before the shim is
  scoped.

**V7.** I re-ran the hook census and it is upheld: 104 command hooks in each of the five config dirs. 20
are `/usr/bin/env bash`, 1 is `/usr/bin/env python3`, and both resolve to Mach-O on a live session's PATH:
`/opt/homebrew/Cellar/bash/5.3.15/bin/bash` and `Python.framework/…/python3.11` (MEASURED: `ps eww` PATH,
then `command -v` and the magic bytes). Three corrections:
- (a) "The only enabled plugin is swift-lsp" is wrong. `enabledPlugins` sets it to `false` in all five
  settings files, so no plugin is enabled. Sessions do load `--plugin-dir ~/.claude/mods/accounts-readout`,
  but its `hooks.json` is `{"modules": [...]}`, with no command hooks.
- (b) Project-level settings were not counted. `technical-analysis/.claude/settings.json` has 3 bare-path
  `#!` hooks and `reso-management-app/.claude/settings.local.json` has 1. No live session's cwd loads them
  right now (MEASURED: `lsof -d cwd`, then jq). Neither 0070 nor the land-gate lint reaches other repos;
  the upstream runtime fix would.
- (c) The docs have at least 5 exec-form examples that name a bare `.sh`, not one: `block-rm.sh`,
  `check-style.sh`, `format.sh`, `plain-display.sh` and `audit-config-change.sh` (MEASURED: curl of
  `code.claude.com/docs/en/hooks.md`).

**V9.** Most of the fleet is already on a versioned layout. 27 of 29 claude processes run from a
per-version prefix, `~/.claude-293` (MEASURED: `ps -A -o comm=` at 00:35; pinned at `~/.zshrc:502`). Siblings `~/.claude-156` … `-284` sit
beside it, each holding its own version (MEASURED: `package.json`). The sessions also run with
`DISABLE_AUTOUPDATER=1` (`~/.zshrc:504`, and the live env). An update is a new directory, not an in-place
overwrite. Only `/opt/homebrew/lib/node_modules` (2.1.291, used by research-kit `claude -p` jobs) updates in
place. (A) also rides the EndpointSecurity event path. `systemextensionsctl list` shows no third-party ES
extension (Tailscale NE, Razer, Karabiner), so apart from Apple's own clients, the running `eslogger` is the
only one.

### What the census already says

The researcher saw no `summary.txt`. I read the raw file instead (MEASURED: `grep -F '"script":{'` over
`~/.cache/kalloc-exec-census/20261021T235112/exec.jsonl`, 13.7 GB, then python). It holds 41,508 `#!`
execs from 04:51:16Z to 05:29:42Z (2,306 s).

**Contamination first:** 18,038 of them (43.5%) are the measurement axis's own A/B, `leaf.sh` and
`parentC.sh` under `~/.cache/kalloc-longterm-ab/`. Any ranking or zone-rate comparison over this window
must drop them.

The organic remainder is 23,470 execs (10.2/s):

| Source | Execs | Share |
|---|---|---|
| Test stubs and mktemp scripts under `$TMPDIR` (pytest `stubbin/`, `launchctl-stub`; bats `stub/jq`, `grep`, `dirname`) | 15,869 | 67.6% |
| Our `bin/` `scripts/` `hooks/` (all trees) | 4,036 | 17.2% |
| `/usr/bin/shasum` (`#!/usr/bin/perl`) | 1,599 | 6.8% |
| bats-core internals (`bats-exec-test` …) | 1,252 | 5.3% |
| Worktree test fixtures and `.tools` | 455 | 1.9% |
| Homebrew cask `kitty` wrapper (`#!/bin/bash`) | 100 | 0.4% |
| brew + npm + git hooks | 56 | 0.2% |

About 80% have kitty (pid 1881) as the responsible process. That figure assumes the A/B rows are
kitty-responsible, which is INFERRED.

Before the census, the zone grew 7.9-11.1 elements/s: 03:49-04:25Z was 11.1/s and 04:25-04:48Z was 7.9/s
(MEASURED: `~/.claude/logs/kalloc-zone-series.tsv`, raw bytes / 1024). That is the same order as the 10.2/s
organic `#!` rate. INFERRED: about one element per organic `#!` exec, so `#!` execs can account for
essentially all of the remaining leak.

This is one 38-minute window. It overlapped a 3-hour post-land bats run (pid 77448, started 22:30) and
pytest runs, so the test share moves with landing activity.

**Consequences for the plan:**
- (b), a shim for the `bin/` and `scripts/` entries, reaches at most about 17% in this window.
- Test-generated stubs are the dominant source. They must be found on PATH by name, so the fix is to emit
  them as symlinks to one compiled stub dispatcher, or as Mach-O stubs. A lint on calls-by-path cannot
  catch them.
- `shasum` → `/usr/bin/perl /usr/bin/shasum`, or a Mach-O hasher, is worth about 7%.
- Calling `/Applications/kitty.app/Contents/MacOS/kitty` directly, instead of the cask wrapper, is worth 0.4%.
- (c), wrapping Homebrew, npm and git hooks, is not worth doing at 0.2%. Homebrew analytics are on here
  (MEASURED: `brew analytics state` → "InfluxDB analytics are enabled"). `brew analytics off` is free but
  buys about 0 at 18 brew execs in 38 minutes.

### Reviewer deviations

- Only this section was written. Background-task output went to the harness's
  `/private/tmp/claude-501/…/tasks/` files.
- One `#!` exec (`brew analytics state`) added about 1-4 KiB to the zone.
- One no-op heredoc went to `/dev/null`; nothing was written.
- About 3 full read passes over the 13.7 GB census file ran at load 50-300.
- No repo, settings, launchd or session change; no kill, no sudo.
