SWITCH FOUND: `{"deniedMcpServers":[{"serverName":"claude.ai Claude Docs"}]}`

# R25: turning off only the Claude Docs connector (Claude Code 2.1.280)

Measured 2026-09-24 against `~/.claude-280/.../claude-code/bin/claude.exe` (2.1.280, native Mach-O; read with `strings`).
Every run was headless `claude -p` from `/tmp/r25-scratch`, with `--model claude-opus-5-5 --effort low --max-turns 1
--output-format stream-json --verbose`. Candidate settings went in through the per-run `--settings '<json>'` flag, so no
config file was written. Each run also carried `"disableAllHooks":true`, and `ITERM_SESSION_ID` was unset (see caveat 5).
Raw streams are in `/tmp/r25-*.jsonl`; the driver is `/tmp/r25-run.sh`. 8 headless runs in total.

The connector's name as the harness sees it: in the init event, `mcp_servers` lists `{"name":"claude.ai Claude Docs","source":"claudeai"}`.
Its tools use the prefix `mcp__claude_ai_Claude_Docs__` (batch, create, delete, export, guide, query, read, update).

## Evidence, per arm (account next3 = `CLAUDE_CONFIG_DIR=~/.claude-tertiary` unless noted)

The instruction probe prompt was: *list every heading in "MCP Server Instructions", then quote the first 25 words under
the heading containing "Claude Docs", or write NONE*.

| run | `--settings` (besides disableAllHooks) | mcp_servers (claude.ai part) | claude_ai tools | tools total | Claude Docs instructions |
|---|---|---|---|---|---|
| 02 control | none | `claude.ai Claude Docs` connected, `claude.ai uidotsh` connected | 8 Docs + `uidotsh_fetch` | 230 | **PRESENT**: "Claude Docs: living docs you create and edit here. A docs skill your client lists → load it before any docs call…" |
| 03 cand. 1 | `"permissions":{"deny":["mcp__claude_ai_Claude_Docs"]}` | Docs **still connected**, uidotsh connected | `uidotsh_fetch` only | 222 | **STILL PRESENT** (same quote, verbatim) |
| 04 cand. B | `"deniedMcpServers":[{"serverName":"claude.ai Claude Docs"}]` | Docs **absent**, uidotsh connected | `uidotsh_fetch` only | 222 | **NONE**: headings were only motion, motion-plus, ms365 |
| 06 B + skill | B plus `"skillOverrides":{"anthropic-skills:docs":"off"}` | Docs absent, uidotsh connected | `uidotsh_fetch` only | 222 | (not probed) skills 70 → 69, `anthropic-skills:docs` gone |
| 08 next4 control | none (`~/.claude-quaternary`) | `claude.ai Claude Docs` connected (next4 has no other connectors) | 8 Docs | 229 | — |
| 07 next4 B | cand. B (`~/.claude-quaternary`) | Docs absent | none | 221 | — |

The control shows the instructions, so the instrument works and the NONE in run 04 counts as a real negative. Run 04's
stderr carried one line: `Warning: claude.ai MCP server blocked by enterprise policy: claude.ai Claude Docs`.

**Candidate 1, `permissions.deny` at server level: tools only. It is not a sufficient switch.** The 8 tools leave the
tool list, but the server still connects and its instructions (about 1,895 chars) stay in the system prompt. It would
recover the ~629 tool tokens and keep the instruction cost.

**Candidate B, `deniedMcpServers`: removes the whole server, tools and instructions.** The connector is dropped before it
connects (it is absent from `mcp_servers`, not listed as failed). `claude.ai uidotsh` on next3 stays connected, with its
tool. The match is by exact name (binary: `for(let s of r.deniedMcpServers)if(VPt(s)&&s.serverName===e)return!0`), so no
other connector ("claude.ai Google Drive", "claude.ai Gmail", "claude.ai Google Calendar", "claude.ai uidotsh") can match
it. Neither next3 nor next4 has the Google connectors, so their survival rests on this exact-name match plus uidotsh's
survival. next2 was not used, per the brief.

**Candidate 2, `/mcp disable` → `disabledMcpServers`: it applies to claude.ai connectors, but only per project. There is
no user-level form.** From the binary:
`function es(e){let n=Qo();if(y6(e))return!S6(n.enabledMcpServers).includes(e);return S6(n.disabledMcpServers).includes(e)}`,
and `Qo()` returns `projects[<cwd>]` from `~/.claude.json`. The claude.ai merge path calls `es(gt)` on each connector and
turns a disabled one into `{type:"disabled"}`. The binary's own help text says: *"The `/mcp disable` toggle is per-project:
even for a user-scope server it applies to the current project only."* (`enabledMcpServers` covers only the built-in
server, `y6(e)` is `e===hD`.) It could not be tested live: a throwaway `CLAUDE_CONFIG_DIR=/tmp/cd-throwaway` (holding a
copied `.claude.json` and settings) returned `Not logged in`, because credentials are keyed to the config dir. This
finding therefore comes from reading the code. It is also the wrong tool here, since it would need one entry per project
in each account's `.claude.json`.

**Candidate 3, a claude.ai-specific allow/deny list: none exists.** Enumerating `[a-zA-Z]*ClaudeAi[a-zA-Z]*` in the binary
finds only `disableClaudeAiConnectors` (forbidden: it switches off all connectors), `allowAllClaudeAiMcps` (managed-only,
and only relaxes the managed-mcp.json lockdown), plus runtime/state names (`suppressedClaudeAiConnectors` covers
duplicate suppression, and the others are OAuth, listing and sync). `deniedMcpServers` is the general mechanism, and it
covers `source:"claudeai"` servers.

## Where it lives: a user settings file, so it can be staged as a migration on the shared `~/.claude/settings.json`

- Key: top-level `deniedMcpServers`, an array of `{serverName}` / `{serverCommand}` / `{serverUrl}` objects. The schema
  for denied entries accepts spaces and dots in `serverName`. It rejects only empty names, whitespace-only names, and
  names with leading or trailing whitespace ("names are compared verbatim"). The allow-list schema's
  `^[a-zA-Z0-9_-]+$` regex does NOT apply to denied entries.
- It is read from every settings source and merged, not only from managed settings. The binary's schema text says:
  *"deniedMcpServers still merges from all sources, so users can deny servers for themselves."* The lookup reads
  `Ye().deniedMcpServers` (`Ye()` is `Sb().settings`, the merged settings) and appends the admin tiers. Arrays
  concatenate across sources and are deduplicated (`See=["disabledMcpjsonServers","deniedMcpServers",…]`).
- The shared `~/.claude/settings.json` has no `deniedMcpServers` today. `~/.claude-tertiary/settings.json` is a symlink
  to it, so one edit covers every account that links it. Check that each config dir's `settings.json` is that symlink
  before calling it fleet-wide.
- Caveat on the evidence: the live proof is for the `--settings` flag source. The user-file source is established from
  the code quoted above; an authenticated run from a user file was not possible without editing real config. After the
  migration, verify with `claude -p 'Reply OK.' --output-format stream-json --verbose` and check that the init event's
  `mcp_servers` has no `claude.ai Claude Docs`.

Suggested migration payload (JSON merge into `~/.claude/settings.json`):

```json
{"deniedMcpServers":[{"serverName":"claude.ai Claude Docs"}],
 "skillOverrides":{"anthropic-skills:docs":"off"}}
```

## Caveats

1. **The `anthropic-skills:docs` skill breaks.** It stays listed after the deny (70 skills in both arms 02 and 04), and
   its body tells the model to call the docs connector's `guide` tool, which will not exist. Pair the deny with
   `"skillOverrides":{"anthropic-skills:docs":"off"}`. Run 06 verified that this removes it from the listing (70 → 69),
   which also saves that skill's description tokens. The operator loses Claude Docs from Claude Code entirely. Nothing
   changes on claude.ai itself: the deny is client-side.
2. **The deny is reported as a policy block.** Headless runs print
   `Warning: claude.ai MCP server blocked by enterprise policy: claude.ai Claude Docs` to stderr on every start. `/mcp`
   will show it as policy-blocked, and the interactive UI may show a startup notice. This is cosmetic, but anything that
   greps stderr for "Warning" will see it.
3. **The name is the connector's display name.** If Anthropic renames the connector (for example to "claude.ai Docs"),
   the deny silently stops matching and the server comes back. A re-check is one headless init read (above).
4. **Candidate 1 recovers only tools.** Use it only if the connector should stay connected but its tools should be
   hidden. It is not the answer to this finding.
5. **Side effect in the first run, now fixed.** Run 01 (hooks on, `ITERM_SESSION_ID` inherited) cost $1.07 and ran the
   operator's SessionStart and mailbox machinery inside the child. That machinery SIGTERMed a cc-await-ping watcher
   bound to pane [719]. The fleet's own classifier then judged it `B-BENIGN`, because the sender had exited. Every later
   run used `disableAllHooks` and unset `ITERM_SESSION_ID`, at about $0.50 each. Future headless probes should do the
   same.
