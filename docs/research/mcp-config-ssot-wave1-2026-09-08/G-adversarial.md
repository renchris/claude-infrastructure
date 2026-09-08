# G — adversarial, baseline-blind. MCP_CONFIG_SSOT

CONTAMINATION NOTED: the brief states the design as "`--mcp-config <SSOT>` appended in
lib/claude-launcher.zsh + strip mcpServers from six .claude.json". That framing is STALE.
I derived independently, then found the repo has already ABANDONED the flag design for the
same reason I derived (sensor blindness). Convergence is the lead's evidence, not mine.
Probes spent: 14.

## 0. PREMISE CHALLENGE (highest-value, answered first)

**The six copies are NOT peers, and the plan's own table conflated two different files.**
Measured on 2.1.260 under a throwaway `HOME` (probe: `mcp add -s user` then observe which
file gained the key):

| CLAUDE_CONFIG_DIR | file the binary reads/writes for user scope |
|---|---|
| unset | **`$HOME/.claude.json`** |
| set | **`$CLAUDE_CONFIG_DIR/.claude.json`** |

`$HOME/.claude/.claude.json` is reached ONLY when something sets `CLAUDE_CONFIG_DIR=$HOME/.claude`
— on this box that is `claude-prev` alone (`~/.zshrc:165`). The live `claude()` at `~/.zshrc:460`
defaults to `$HOME/.claude-next`, so the plan's row "`~/.claude` | default/unpinned" names a file
the default path never touches, and omits the file it does.

**This is not vestigial — `$HOME/.claude.json` is live**, because `lib/claude-launcher.zsh:230`
skips routing on `--resume/-c` and on all six router fallbacks, and any non-shell entry point
that execs `claude.exe` without `CLAUDE_CONFIG_DIR` lands there too.

**And it is where the real divergence sits, right now.** `mcpServers` hashes:
`~/.claude.json` = `164b0329600a` (`ms365` = `npx -y @softeria/ms-365-mcp-server@latest`);
all five config dirs = `01fe19e516bb` (`ms365` = the fnm binary). One file out of six, drifted
on the exact axis the plan calls Divergence #1.

**Divergence #2's evidence no longer exists.** `mac-messages` is in ZERO user-scope dirs; it now
lives only in `~/Development/personal/.mcp.json`. The motivating "missed one of five dirs" is
stale — the server moved to project scope entirely.

**Population is otherwise exactly right.** Every file on disk holding `oauthAccount` is one of
the six; there is no seventh. (REFUTES my "the loop misses a dir" derivation.)

## 1. DERIVED FAILURE MODES — ranked

### F1 · CONFIRMED · CRITICAL — a missing/malformed/zero-byte SSOT is FATAL to every launch
`--mcp-config` validation refuses the process, it does not degrade:

```
--mcp-config /nope/ssot.json      -> rc=1  "Error: Invalid MCP configuration: MCP config file not found"
--mcp-config <truncated json>     -> rc=1  "MCP config is not a valid JSON"
--mcp-config <0-byte file>        -> rc=1  "MCP config is not a valid JSON"
```
Injected at the launcher, this converts today's worst case — ONE account silently lacks ONE
server, degraded — into **every session on every account refuses to start**, during any window
where the file is absent or mid-write (non-atomic editor save, a `git checkout` of the branch,
a worktree that lacks it). The plan's own Landmines section says you then cannot start a session
to fix it. This alone disqualifies "one file, injected by flag, at every launch" unless the
launcher first stats-and-validates and falls open.

### F2 · CONFIRMED · CRITICAL — `--mcp-config <configs...>` is VARIADIC and eats following argv
```
claude --mcp-config SSOT mcp list
  -> Error: MCP config file not found: <cwd>/mcp
     Error: MCP config file not found: <cwd>/list      # subcommand never ran
claude -p --mcp-config SSOT 'say OK'
  -> Error: MCP config file not found: <cwd>/say OK    # the prompt was eaten
```
"**Appending** `--mcp-config <SSOT>`" — the plan's literal word — is the one placement that
breaks. The current launcher ends `… --effort "$_eff" "$@"`, so appending the flag last means
every `claude mcp …`, `claude doctor`, `claude agents` and every bare positional prompt through
the wrapper dies. It is safe ONLY if followed by another dash-flag, or written `--mcp-config=…`
(the form `scripts/lib/mcp-noinherit.sh` already uses). A one-token difference with a
total-outage failure mode, invisible in review.

### F3 · CONFIRMED · HIGH — the flag would make BOTH of this machine's MCP sensors lie
`hooks/session-start.sh:270,272` runs `"$CLAUDE_BIN" mcp list` as a bare child, with no flag and
no way to pass one (F2). `lib/cc-upgrade-gate/check13_mcp.sh:14` reads the same command. Strip
user scope + inject by flag and the probe counts `✔ Connected` = 0 while the session has 3.
Worse than a wrong number: `session-start.sh:286` only breaks the retry loop when
`CONNECTED_COUNT > 0`, so every session start would burn the full 15 s probe budget
(`PROBE_BUDGET`) and then cache `state=ok, connected=0` for 300 s. Cache:
`${CLAUDE_CONFIG_DIR}/.mcp-probe-cache` (`session-start.sh:141`), per-config-dir, TSV `v1`.

### F4 · CONFIRMED · HIGH — the design has ALREADY been replaced, and the replacement's two
named safety mechanisms are PROSE-ONLY
`mcp-servers.json` (repo root) + `scripts/mcp-ssot-wire.sh` render the SSOT into all six files.
Its header names the answer to the live-session write-back race: *"re-assertion (install.sh) and
detection (`--check`, and tests/mcp-ssot-wire.bats) are the design"*. On disk:
- `rg mcp-ssot-wire install.sh hooks/ bin/ scripts/` → **zero call sites**. install.sh does not
  re-assert. The renderer is a manual one-shot.
- `tests/mcp-ssot-wire.bats` → **does not exist**.
Both cited mechanisms are unbuilt. The residual race is therefore undefended in fact.

### F5 · CONFIRMED · HIGH — the SSOT is UNTRACKED and exists in exactly one worktree
`git status` → `?? mcp-servers.json`; absent from `origin/main`; absent from
`~/Development/claude-infrastructure/`; absent from `~/.claude/`. The renderer resolves
`$REPO_ROOT/mcp-servers.json` then `$HOME/.claude/mcp-servers.json` — neither exists outside this
worktree. Delete the worktree and the single source of truth is gone. An untracked SSOT is a
seventh copy with no backup.

### F6 · CONFIRMED · MEDIUM — the SSOT cannot express DELETION
`mcp-ssot-wire.sh` merges (`cfg["mcpServers"].update(want)`) and its header states it "never
DELETES a server it does not know about". The frozen scope claims "adding, changing, or
**removing** a server is a one-file edit that cannot diverge". Removal is the one operation the
mechanism structurally cannot perform — and removal is exactly how `mac-messages` got into its
current half-state.

### F7 · CONFIRMED · MEDIUM — new in 260, invisible to the 220-era ruled-out table
Strings in the 2.1.260 binary carry an MCP source vocabulary the plan never saw:
`managedServers`, `pluginServer`, `sdkServers`, and scope tokens `local·user·project·dynamic·
plugin·managed·policy·flag`. Concretely:
- **Plugin/marketplace MCP is real**: `CLAUDE_CODE_SKIP_PLUGIN_MCP_SERVERS`,
  `..._EXCEPT`, `CLAUDE_CODE_SYNC_PLUGINS_MCP_TIMEOUT_MS`, "from a plugin" / "from a marketplace".
  A plugin can inject a server that no SSOT and no `--check` sees. **A seventh scope.**
- **Managed settings**: `/Library/Application Support/ClaudeCode/managed-settings.json` and a
  *remote* managed-settings fetch (`claude doctor`: "Managed settings (remote): not fetched — no
  usable credentials"). The plan ruled this out because the local path does not exist; the REMOTE
  fetch is new and is credential-gated, not absent.
- **`--mcp-config` is silently IGNORED in cloud sessions**: *"MCP servers from --mcp-config
  ignored — MCP servers for this session run in the cloud container"*. `claude --cloud` is used
  by `bin/cc-notify:734`.
- **Per-entry validation failures are SKIPPED, not fatal**: *"MCP server config entries from
  --mcp-config that failed validation and were skipped (e.g. a `url` entry with no `type`).
  Affected servers are absent from `mcp_servers[]`."* Verified: a config with one good and one
  bad entry does NOT error. So the flag design keeps the plan's own headline failure mode
  (silent absent capability) and merely centralises its blast radius.
- A second `--mcp-config` exists on the dispatched-sessions surface ("MCP server configuration to
  apply to dispatched sessions (repeatable)") — a different code path from the session flag.

### F8 · UNVERIFIED — merge-vs-replace could not be decided from outside a logged-in session
`claude mcp list` is structurally blind to the flag (confirmed: with the flag set and both scopes
populated, `mcp list` reports the scopes and never the flag's servers). `--debug -p` needs auth.
The `--strict-mcp-config` help text implies non-strict merges, and `mcp-noinherit.sh`'s measured
table (strict alone drops user-scope; strict + passthrough restores it) implies the same, but I
did not observe a merge directly.
**Probe that settles it:** in a real logged-in config dir,
`claude --mcp-config=/tmp/x.json --permission-mode auto --debug -p 'exit'` and grep stderr for
both the flag server's name and a user-scope name. Threshold: both present ⇒ merge.

## 2. REFUTED (so nobody re-runs these)

- `mcpServers` in `settings.json` — still unsupported on 2.1.260. A `$CLAUDE_CONFIG_DIR/settings.json`
  carrying `mcpServers` yields "No MCP servers configured". Plan's row stands.
- `claude mcp add --scope` — still exactly `local|user|project` on 260. No wider scope.
- "the renderer's population misses a config dir" — it does not; the six oauth-holding files on
  disk are exactly the six it targets, and it correctly distinguishes `$HOME/.claude.json` from
  `$HOME/.claude/.claude.json` (`mcp-ssot-wire.sh:93,158-160`).
- "`--check` compares only server NAMES, so the npx/fnm endpoint drift passes green" — it
  deep-compares (`have[n] != want[n]`) and reports `drift:`.
- "fired sessions filter the stdio servers back out" — `CC_MCP_USERSCOPE_STDIO_ALLOW` is present
  in both the worktree and the deployed `~/.claude` copy of `mcp-noinherit.sh`.
- "the renderer writes non-atomically" — it uses `mkstemp` in the same dir + `os.replace`.

## 3. SINGLE STRONGEST OBJECTION

**"N copies with no SSOT" is the wrong problem statement, and solving it as stated buys almost
nothing while risking a fleet-wide launch outage.** The measured divergence is ONE file
(`~/.claude.json`) differing on ONE server's endpoint, on a code path (`CLAUDE_CONFIG_DIR` unset)
that the interactive launcher never takes. The plan's second piece of evidence (`mac-messages`
missing from `~/.claude-next`) is stale — that server is in no user-scope file at all now.
Against that, the flag design (F1) makes a zero-byte file a total outage and (F3) blinds both
existing MCP sensors, and the renderer design (F4, F5) currently rests on an untracked file plus
two mechanisms that exist only in a comment.

**The strongest case AGAINST doing this at all:** the accounts SHOULD arguably differ, and the
cheapest correct fix is not an SSOT. Four of the six files are per-account state deliberately in
`config-mirror.zsh`'s `_CC_ISOLATE` set; the fifth (`~/.claude/.claude.json`) belongs to a
different binary track (2.1.114 `claude-prev`) that may legitimately want different servers; and
the sixth (`~/.claude.json`) is reached only by unrouted launches. A one-line
`_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"` already exists — making the *unset* case
impossible would retire `~/.claude.json` from the population entirely and delete the only
measured divergence, with no new file, no new flag and no new sensor.

## 4. CHEAPEST EXPERIMENT THAT SETTLES IT

Run the renderer's own detector before building anything else:

```
bash scripts/mcp-ssot-wire.sh --check
```

Threshold: if it prints `✗` on exactly one file (`~/.claude.json`, drift: ms365) and `✓` on the
other five, the entire motivating problem is one stale file on a path the launcher does not use —
the plan is UNNECESSARY as scoped, and the work reduces to (a) `git add mcp-servers.json`,
(b) one call site in `install.sh`, (c) the missing bats file. If it prints `✗` on three or more,
the divergence thesis survives and the renderer (not the flag) is the right mechanism.

## 5. NEGATIVE SPACE — adjacent axes nobody is watching

- **Plugin-scope MCP servers.** 2.1.260 loads them from a marketplace with its own sync timeout;
  no SSOT, no `--check`, and no sensor on this box enumerates them. A plugin install silently adds
  a seventh scope that every one of these designs is blind to.
- **The 2.1.114 / `claude-prev` track.** `~/.claude-versions/current -> 2.1.114`, and
  `claude-prev` is the only consumer of `~/.claude/.claude.json`. Wiring an SSOT measured on 260
  into a config a 114 binary reads assumes schema stability nobody checked.
- **OAuth token stores are keyed per ENDPOINT.** Correcting `~/.claude.json`'s ms365 from `npx` to
  the fnm binary does not migrate its token — it silently de-authenticates that path. A "fixed the
  drift" render can present as "ms365 stopped working".

## 6. FALSIFIABLE RUNTIME PREDICTIONS

1. `bash scripts/mcp-ssot-wire.sh --check` → exactly ONE `✗`, on `~/.claude.json`, naming
   `drift: ms365`. **Refuted if** ≥2 files are ✗ (divergence is broader than measured) or 0
   (something already re-rendered, and F4's "no call site" is wrong).
2. `cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.mcp-probe-cache"` → a `v1<TAB>…<TAB>ok<TAB>3<TAB>…`
   record. **Refuted if** connected ≠ 3 — the sensor is already lying, before any change.
3. With the flag injected last: `claude mcp list` errors with "MCP config file not found:
   <cwd>/mcp". **Threshold: any non-error output refutes F2** and means commander's variadic
   binding differs from my sandbox measurement.
4. `mv ~/x.json /tmp && claude -p hi` with the launcher injecting `--mcp-config ~/x.json` → rc=1,
   zero sessions start. **Refuted if** it degrades instead of refusing.
5. `strings claude.exe | grep -c SKIP_PLUGIN_MCP_SERVERS` > 0 on 260 and `= 0` on the 2.1.114
   binary at `~/.claude-versions/2.1.114/...` → confirms plugin MCP is a 260-era surface the
   ruled-out table could not have seen.

## 7. CAMPAIGN CANDIDATE

**"Make `CLAUDE_CONFIG_DIR` unset unreachable."** Every entry point that execs `claude.exe`
(launcher, `handoff-fire.sh`, `cc-notify`, `reso-resume-one`, cron, hooks' probe children) either
sets it or is a bug. If a single chokepoint guaranteed it, then: `~/.claude.json` leaves the
population (the only measured divergence disappears), the renderer's six targets become five,
the per-config-dir `.mcp-probe-cache` can never be served across accounts, and the resume-path
account-identity class of bug loses its root cause. Three ledger items become no-ops because the
file they are about stops being read.
