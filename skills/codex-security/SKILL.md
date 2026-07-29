---
name: codex-security
description: >-
  Run OpenAI's Codex Security methodology natively inside Claude Code — no Codex CLI, no Codex desktop app, no ChatGPT/Codex subscription, no OpenAI API key. Drives the Apache-2.0 plugin vendored at vendor/codex-security/: repository security scans, PR/commit/branch diff scans, deep multi-pass scans, threat modeling, candidate validation, attack-path analysis and severity calibration, finding triage, fixes, vulnerability write-ups, hardening proposals, and issue tracking — all producing the upstream canonical artifact bundle (findings.json, coverage.json, scan-manifest.json, report.md, SARIF) sealed by the upstream deterministic finalizer. Load when asked to "security scan this repo", "review this PR/diff for security", "threat model this", "triage these findings", "deep security scan", "write up this vulnerability", "propose security hardening", or when a security audit needs evidence-backed findings rather than pattern-matched guesses. NOT a linter or secret-scanner (use dedicated tools), and NOT for running the upstream `codex-security` npm CLI (that path requires Codex and is explicitly out of scope here).
---

# Codex Security in Claude Code

Runs OpenAI's Codex Security workflows with **Claude as the reasoning agent**. The
methodology, contracts, schemas, and deterministic tooling are vendored verbatim under
`vendor/codex-security/` (Apache-2.0 — see its `NOTICE.md`). Nothing here calls OpenAI,
Codex, or the network.

## Why this works

Codex Security splits cleanly into three layers. Only the first is Codex-bound:

| Layer | Upstream form | Portable? |
|---|---|---|
| Agent runtime | `@openai/codex` + `@openai/codex-sdk` spawned by the npm CLI | ❌ Replaced by Claude |
| Desktop-app workspace | `mcp/server.mjs`, 20 `*_codex_security_*` MCP tools | ❌ Not vendored — skills define a prompt-only fallback for exactly this |
| **Methodology + contract** | `skills/`, `references/`, `schemas/`, `scripts/` | ✅ **Vendored and used as-is** |

The scan is agentic, not server-side: there is no Codex Security backend to call. The
"scanner" is the phase discipline in the skills plus a stdlib-only Python layer that
validates and seals artifacts. Swap the agent, keep everything else.

## Resolve these before starting

```
plugin_dir  = <repo_root>/vendor/codex-security
python_cmd  = python3
repo_root   = git rev-parse --show-toplevel
repo_name   = basename of repo_root
scan_id     = <short_commit>_<UTC timestamp>          # e.g. dc12c8db_20260728T2240Z
scan_dir    = ${TMPDIR:-/tmp}/codex-security-scans/<repo_name>/<scan_id>
```

Artifact subdirectories, threat-model paths, and per-phase outputs are defined in
`vendor/codex-security/references/scan-artifacts.md`. **Follow that file** — do not
invent paths. Note it deliberately says to use `$TMPDIR`, not a hardcoded `/tmp`.

## Pick the workflow

Read the chosen `SKILL.md` in full and follow it. Route by intent:

| Ask | Skill |
|---|---|
| Audit a repo, or a scoped path/package/folder | `skills/security-scan/` |
| Review a PR, commit, branch diff, or working-tree patch | `skills/security-diff-scan/` |
| Exhaustive / variance-reducing multi-pass scan | `skills/deep-security-scan/` |
| Build or refresh a repository threat model | `skills/threat-model/` |
| Decide whether candidates are real | `skills/validation/` |
| Trace source→sink, calibrate severity | `skills/attack-path-analysis/` |
| Triage findings imported from scanners/tickets | `skills/triage-finding/` |
| Fix and verify a finding | `skills/fix-finding/` |
| Polished disclosure-grade write-up | `skills/vulnerability-writeup/` |
| Structural/architectural hardening portfolio | `skills/propose-security-hardening/` |
| File findings to Linear/Jira/GitHub | `skills/track-findings/` |
| Author or review `SECURITY.md` | `skills/define-security-policy/` |

`vendor/codex-security/references/shared-hard-rules.md` binds **every** workflow. Read it
first. The rule that matters most in practice: *do not emit a finding unless it survives
the final policy-adjustment pass* — this methodology is built to suppress plausible-sounding
false positives, which is the entire reason to prefer it over grep-driven auditing.

## Translating Codex conventions to Claude Code

The vendored skills are written for Codex. Apply these substitutions as you read them —
they are the only adaptations required.

| In the vendored text | Do this instead |
|---|---|
| `$skill-name` (e.g. `$validation`, `$threat-model`) | Read `vendor/codex-security/skills/<skill-name>/SKILL.md` and follow it as the current phase |
| `open_codex_security_workspace`, `await_codex_security_scan_start`, `get_codex_security_scan_context`, `start_codex_security_deep_scan`, `complete_codex_security_scan`, and every other `*_codex_security_*` MCP tool | **Unavailable by construction.** Take the documented prompt-only path. The skills already branch on this — "In Codex CLI or when those tools are unavailable, use the prompt-only path." |
| "In the Codex desktop app…" / setup workspace / **Continue in Codex** / "press Start scan" | Skip entirely. You are never the app host. |
| `complete_codex_security_scan` for sealing | Run the finalizer directly (see below) |
| Codex subagent fan-out, workers, per-candidate agents | Claude `Agent` subagents — `Explore` for read-only file sweeps, `general-purpose` for candidate work. One subagent per shard/candidate, same phase boundaries |
| `<python_command>` | `python3` |
| `<plugin_dir>` | `vendor/codex-security` |
| `fail_codex_security_scan` | No terminal-fail tool exists. Record progress and leave the bundle resumable — never discard a scan because work remains |
| `config_preflight.py` / capability profiles | Codex-runtime capability probing; **not applicable**. Proceed as a prompt-only host with subagent fan-out available |

## Sealing the scan — the deterministic gate

Author the three canonical JSON files per
`vendor/codex-security/references/final-report.md`, then seal:

```bash
python3 vendor/codex-security/scripts/finalize_scan_contract.py \
  --scan-dir "$scan_dir" --source-root "$(git rev-parse --show-toplevel)"
```

This validates `scan-manifest.json`, `findings.json`, and `coverage.json` against the
upstream JSON Schemas and deterministically generates `report.md` and SARIF.

**Never hand-author `report.md` or the SARIF.** They are projections. If the finalizer
rejects your JSON, the JSON is wrong — fix it, do not edit the output. Export with
`--export-format {csv,json,sarif}`.

Because the finalizer is the *upstream, unmodified* validator, a bundle that seals is
un-fakeable evidence that Claude produced a contract-conformant Codex Security scan.

## Hard rules for this port

- **Never invoke `codex`, `npx codex-security`, or `@openai/codex*`.** That path needs a
  Codex runtime and credential and is out of scope. If a user wants it, say so plainly
  rather than silently shelling out.
- **Do not edit anything under `vendor/codex-security/`.** It is redistributed verbatim
  under Apache-2.0. Adaptations belong in this file. Re-vendoring is a clean re-copy plus
  a `NOTICE.md` provenance update.
- **Findings need evidence, not vibes.** Keep the source, the broken control, the sink,
  and the reaching path. A safe neighbouring path does not prove this path is safe.
- **Report the gaps.** Do not claim complete coverage while any file or candidate is
  unresolved — coverage outcomes exist precisely so partial scans stay honest.
- Scan bundles land in `$TMPDIR`, outside the repo, so scan state is never committed.

## Scope note

Scanning **this** repository means auditing shell that runs automatically as Claude Code
hooks on untrusted tool input — command injection, unquoted expansion, path traversal, and
`eval` on attacker-influenced data are the live risks, not web-app vulnerability classes.
Let the threat model reflect that before discovery starts.
