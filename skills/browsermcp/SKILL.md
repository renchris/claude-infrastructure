---
name: browsermcp
description: >-
  Browser-automation setup + tooling reference — RETIRED SERVER, LIVE DECISION TREE: the BrowserMCP server was eliminated 2026-08-11 and the agent-browser CLI is now the primary path; the mcp__browsermcp__* sections below are history. Load when automating a browser (navigating, clicking, filling forms, taking screenshots, extracting page data) or when BrowserMCP tools fail. Covers the mcp__browsermcp__* tool list and the navigate → snapshot → use-ref → click/type workflow, the wrapper-script + Chrome-extension setup, the .mcp.json project config, and the troubleshooting decision tree (tools unavailable after /compact → start a fresh session; wrapper script fails → remove + re-add the server; extension not connecting → reinstall, pin, connect per tab); the agent-browser CLI commands for when MCP is unavailable; and the react-best-practices / vercel-design-guidelines auto-triggering knowledge skills. Triggers: "automate the browser", "take a screenshot of the page", "fill this form", "navigate to", BrowserMCP tool errors, "No such tool available" for browser tools. This is the MCP-primary path (prefer BrowserMCP over Playwright); NOT the standalone agent-browser skill (the CLI fallback this skill points to when MCP is unavailable).
---

> 🚨 **BrowserMCP was RETIRED on 2026-08-11.** No `mcp__browsermcp__*` tool exists in any session any
> more — the server is gone from every config site and `bin/browsermcp-wrapper.sh` is `git rm`'d. It
> was not merely unused but unusable: **0 invocations across 3,504 transcripts / 30 days**, upstream
> frozen 2025-04-11, and a port-9009 `kill -9` singleton that makes per-session spawning invalid by
> construction. **Use the `agent-browser` CLI** (§ agent-browser below) — or attach
> `chrome-devtools-mcp --browserUrl` to a running Chrome when a task genuinely needs the MCP tool
> surface (skills: `dia-agent`, `autonomous-authenticated-web-access`). Everything in the next
> section is kept as history: it is how the tool surface was shaped, not what you can call today.

## BrowserMCP (historical — server retired 2026-08-11)

Use BrowserMCP (not Playwright) for browser automation:

```
mcp__browsermcp__browser_navigate   - Navigate to URL
mcp__browsermcp__browser_snapshot   - Get page accessibility tree (use for element refs)
mcp__browsermcp__browser_click      - Click element by ref
mcp__browsermcp__browser_type       - Type into element
mcp__browsermcp__browser_screenshot - Capture screenshot
mcp__browsermcp__browser_press_key  - Press keyboard key
mcp__browsermcp__browser_hover      - Hover over element
mcp__browsermcp__browser_wait       - Wait for time (seconds)
```

Workflow: `navigate` → `snapshot` → use `ref` from snapshot → `click`/`type`

**Setup**: Wrapper script (`~/bin/browsermcp-wrapper.sh`) ensures NVM/PATH consistency. Chrome extension 1.3.4+ required (install from [Chrome Web Store](https://chromewebstore.google.com/detail/browser-mcp-automate-your/bjfgambnhccakkhmkepdoekmckoijdlc), connect per tab).

**Project Config** (`.mcp.json`):
```json
{
  "mcpServers": {
    "browsermcp": {
      "command": "/Users/chrisren/bin/browsermcp-wrapper.sh",
      "timeout": 15000
    }
  }
}
```

**Troubleshooting Decision Tree:**

| Symptom | Solution |
|---------|----------|
| Tools unavailable after `/compact` (GitHub #3426) | Start fresh session (`/exit` then `claude`) |
| Wrapper script fails | `claude mcp remove browsermcp -s project && claude mcp add browsermcp -s project -- npx -y @browsermcp/mcp` |
| Extension not connecting | Reinstall, pin to toolbar, click "Connect" per tab |

See [BrowserMCP Docs](https://docs.browsermcp.io/setup-server), [Issue #3426](https://github.com/anthropics/claude-code/issues/3426), [Issue #1611](https://github.com/anthropics/claude-code/issues/1611), [Issue #723](https://github.com/anthropics/claude-code/issues/723) for details.

### agent-browser (CLI Fallback)

When BrowserMCP unavailable, use `agent-browser`:

```bash
agent-browser open <url>                    # Navigate
agent-browser snapshot -i                   # Get interactive elements
agent-browser click @e1                     # Click by ref
agent-browser fill @e2 "text"               # Fill input
agent-browser close                         # Close browser
```

For existing browsers via Chrome DevTools Protocol: `agent-browser --cdp 9222 snapshot -i`

**Troubleshooting**: `agent-browser install` (missing Chromium), `--headed` flag (debug), `--cdp 9222` (connect to running browser).

### Vercel Agent Skills (Knowledge-Based)

Two auto-triggering knowledge skills from `vercel-labs/agent-skills`:

| Skill | Auto-Triggers On | Provides |
|-------|------------------|----------|
| `react-best-practices` | "optimize performance", "review React code", "check for waterfalls" | 45+ performance rules (Promise.all, barrel imports, React.cache, dynamic imports) |
| `vercel-design-guidelines` | "review my UI", "check accessibility", "audit design" | 8 audit categories with file:line references |

For explicit invocation: describe what you want ("review my component for performance issues"). Deep dives: reference rule files in `~/.claude/skills/react-best-practices/references/rules/`.
