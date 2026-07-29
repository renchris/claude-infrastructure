# NOTICE — vendored `openai/codex-security` plugin content

This directory contains **unmodified** content from OpenAI's `codex-security`
plugin, redistributed under the Apache License 2.0 (see `LICENSE`).

| Field | Value |
|---|---|
| Upstream | <https://github.com/openai/codex-security> |
| Upstream path | `sdk/typescript/_bundled_plugin/` |
| Upstream commit | `f22d4a36f26d16287bcdfd707b369116e02a08c3` (2026-07-28) |
| npm package | `@openai/codex-security@0.1.1` |
| Plugin version | `codex-security@0.1.14` (`.codex-plugin/plugin.json`) |
| License | Apache-2.0 (declared in both the repo root and `plugin.json`) |
| Vendored | 2026-07-28 |

## Why vendored rather than installed

The npm package `@openai/codex-security` depends on `@openai/codex` and
`@openai/codex-sdk` — it *is* a launcher that spawns the Codex agent runtime.
Running the CLI therefore requires Codex and an OpenAI credential, which is
exactly what we are avoiding. The **content** below, however, carries the
security methodology and is agent-agnostic, so it is vendored and driven by
Claude instead.

## What was vendored (verbatim, no edits)

| Path | Contents |
|---|---|
| `skills/` | 13 workflow skills (`SKILL.md` + per-skill `references/`) |
| `references/` | 9 shared contract/guidance documents |
| `schemas/` | `findings`, `coverage`, `scan-manifest` JSON Schemas |
| `scripts/` | 28 Python modules — the deterministic scan-contract layer |
| `examples/` | A completed-scan example bundle |
| `preflight/` | `capability-profiles.toml` |

## What was deliberately excluded

| Path | Reason |
|---|---|
| `mcp/` | The Codex **desktop-app** MCP runtime (~300 KB Brotli blobs). Its 20 tools drive the Codex app workspace UI and spawn Codex threads via `codex-sdk`. Unusable without Codex, and the skills already define a prompt-only fallback for exactly this case. |
| `.mcp.json`, `.app.json`, `.codex-plugin/` | Codex plugin/app manifests and connector ids. |
| `assets/` | Branding. |

## Verified properties of the vendored content

Established by inspection at the commit above:

- **No network egress.** No OpenAI/ChatGPT endpoint appears anywhere in the
  vendored tree. The only `urllib` imports are `urllib.parse.quote` /
  `urlsplit` (string handling) in `finalize_scan_contract.py` and
  `workbench_scan_history.py`.
- **Standard library only.** All 28 Python modules import solely from the
  stdlib (`argparse`, `json`, `sqlite3`, `pathlib`, `re`, `hashlib`,
  `subprocess` for `git`). No third-party packages, no virtualenv.
- **Runs standalone.** Verified on stock Python 3.11.4.
- **Skills are already host-portable.** Every workflow skill documents a
  "prompt-only" path for when the app MCP tools are unavailable, and the
  `name` + `description` YAML frontmatter matches Claude Code's Agent Skills
  format exactly.

No file in this directory has been altered. All adaptation to Claude Code lives
outside it, in `skills/codex-security/SKILL.md`.
