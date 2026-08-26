# A11 — Integration surface: how a CV capability actually reaches a Claude Code session

**Date:** 2026-08-26 · **Axis:** integration surface, data contract, token/latency economics
**Method:** every machine claim is a `path:line` I read; every product claim is a documentation URL
I fetched today. Verdicts are stated before their evidence.

---

## The answer, first

**Build the perception layer as a plain CLI that writes two artifacts to disk — a JSON findings file
and an annotated PNG — and let the agent `Read` the PNG. Do not build an MCP server.**

Three facts settle it, and the first is the one that surprised me:

1. **An MCP tool CAN return image content to Claude Code.** This is not a gap. The MCP spec defines
   an `image` content block, and Claude Code's own MCP page states the limit that applies to it:
   *"Tools that return image data are still subject to `MAX_MCP_OUTPUT_TOKENS`"*
   ([code.claude.com/docs/en/mcp](https://code.claude.com/docs/en/mcp), § MCP output limits and
   warnings). So the design question is **not** "can MCP show the model a picture" — it can. The
   question is what that costs and what it buys.
2. **What it costs is the whole budget.** `MAX_MCP_OUTPUT_TOKENS` defaults to **25,000**, with a
   fixed warning at 10,000, and image data is charged against it. A single 1456×816 screenshot is
   ~1,120 image tokens, so tokens are not the binding constraint — but the *same* doc says the
   `anthropic/maxResultSizeChars` escape hatch **"has no effect on tools that return image
   content"**. An MCP image tool has exactly one lever, a global env var, and it is set per-session
   rather than per-tool. The `Read` path has no such coupling.
3. **The `Read` path already works, is already the fleet's habit, and is already governed.** The
   sibling A9 finding — Read clamps to 2000×2000 px / ~3.75 MiB and degrades through palette-PNG →
   descending-quality JPEG → resize, and >20 image blocks in one request tightens the cap and
   *rejects* rather than downscales — describes a ladder that a file-writing CLI can stay
   comfortably inside by construction, because the CLI chooses the output resolution.

The adversarial pass at the end argues the opposite case as hard as I can make it, and concedes one
condition under which MCP wins.

---

## 1. The delivery surfaces compared

Five surfaces are available. They are not interchangeable, and only two of them can put pixels in
front of the model at all.

| | **MCP server** | **Plain CLI via Bash** | **Skill** | **Hook (PreToolUse/PostToolUse/Stop)** | **Subagent** |
|---|---|---|---|---|---|
| **Can deliver an image to the model** | **Yes** — `{"type":"image","data":…,"mimeType":…}` in the tool result ([MCP spec, Tool Result § Image Content](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)) | **Only indirectly** — writes a PNG, model then calls `Read` on the path | No — a Skill is instructions; it *tells* the agent to run something | **No** — hook output reaches the model as text (`additionalContext`), never as an image block | Yes, but **only into the subagent's own context**; its report back to the lead is text |
| **Token cost of the delivery mechanism itself** | tool schema resident in every request (~150-400 tok/tool) | **~0 when idle** — `Bash` is already loaded | ~50 tok for the name+description line until invoked, then the SKILL.md body | ~0 in-band; the hook's text output is charged on the turn it fires | a whole extra context window |
| **Latency** | server process warm; per-call JSON-RPC ≈ few ms + work | process spawn ≈ 20-80 ms + work | none (dispatch only) | fires on the tool event, in-band, blocking | seconds to minutes |
| **Discoverability to the model** | **highest** — tools appear in the tool list unprompted | lowest — the model must already know the command exists | **good and cheap** — auto-loads on trigger phrases | n/a — the model does not choose a hook | n/a |
| **Dominant failure mode** | server dead ⇒ tool silently absent from the list; the model does not know to miss it | non-zero exit + stderr, **visible to the model in the same turn** | skill not triggered ⇒ capability never used | fires on the wrong occasion, or is a `\|\| true` that deletes its own message | report is prose; provenance is lost |
| **Maintenance burden** | a process, a transport, a config scope, a reconnect policy, an idle timeout, a protocol revision | one executable + `--help` | one markdown file | a settings.json entry + a bounded-failure discipline | none |
| **Blast radius when it breaks** | every session that loads it | the one call | one turn | **every turn of every session** | one wave |

**Reading of the table.** MCP buys exactly one thing the CLI cannot: the model *discovers the
capability without being told*. Everything else on the row is cost. The CLI's apparent weakness —
"the model must know the command exists" — is precisely what a **Skill** is for, and a Skill costs
one markdown file rather than a daemon. So the strongest configuration is not "MCP vs CLI"; it is
**CLI + Skill**, which buys MCP's discoverability at a fraction of MCP's failure surface.

**On hooks, specifically: a hook cannot show the model a picture.** The Stop-hook feedback channel
is `hookSpecificOutput.additionalContext`, and this repo has already measured what it is and is not
— `/Users/chrisren/Development/claude-infrastructure/CLAUDE.md:520-529` records that
`additionalContext` *does* reach the model but is not advisory (it forces a turn and increments the
consecutive-block counter capped by `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`), and that `systemMessage` is
the only field that does not extend the turn and *"provably cannot reach the model"*. Both channels
are text. A perception hook could therefore inject *findings JSON* into a turn, and could never
inject the annotated overlay. That asymmetry matters for §5.

---
