# Can we employ `openai/codex-security` within Claude Code, without Codex?

**Date:** 2026-07-29 · **Verdict: YES — for the methodology layer, which is where essentially
all the value lives.** Demonstrated end-to-end on this repository.

Upstream: <https://github.com/openai/codex-security> @ `f22d4a36` · `@openai/codex-security@0.1.1`
· plugin `0.1.14` · **Apache-2.0**.

---

## 1. The question

Can we run OpenAI's Codex Security against our repos *with and within Claude Code*, with no Codex
application and no Codex/ChatGPT subscription?

## 2. What the product actually is

The decisive finding: **there is no Codex Security backend.** The scan is *agentic*, performed
locally. `grep` over the entire TypeScript SDK finds exactly one external host —
`registry.npmjs.org`, for update checks. Nothing calls OpenAI.

The product decomposes into three layers, and only the first is genuinely Codex-bound:

| Layer | Upstream form | Codex-bound? |
|---|---|---|
| Agent runtime | `@openai/codex` + `@openai/codex-sdk` (hard npm deps) | **Yes** — the CLI is a launcher that spawns the Codex agent |
| Desktop-app workspace | `mcp/server.mjs`, 20 `*_codex_security_*` MCP tools | **Yes** — but optional; see below |
| **Methodology + contract** | 13 skills, 9 references, 3 JSON Schemas, 28 Python modules | **No** — fully portable |

So the CLI needs Codex. The *intelligence* does not.

## 3. Why the methodology layer ports cleanly

Four properties, each verified rather than assumed:

1. **The skills are already host-portable.** Every workflow skill documents a prompt-only
   fallback — verbatim: *"In Codex CLI or when those tools are unavailable, use the prompt-only
   path."* The MCP app tools are an optimisation for the desktop workspace UI, not the engine.
2. **The skill format is Claude Code's format.** `name` + `description` YAML frontmatter, same
   shape as Agent Skills. No translation needed at the file level.
3. **The deterministic layer is stdlib-only and offline.** All 28 Python modules import solely
   from the standard library. The only `urllib` uses are `urllib.parse.quote` / `urlsplit`
   (string handling). Verified running standalone on stock Python 3.11.4 — no venv, no deps.
4. **Apache-2.0**, declared in both the repo root and `plugin.json`. Redistribution with
   attribution is permitted.

The MCP server itself is a local SQLite workbench plus app-UI bridge — it contains **no OpenAI
hosts** either. It is excluded only because its tools drive the Codex desktop workspace and it
spawns Codex threads via `codex-sdk`.

## 4. What was built

| Path | Purpose |
|---|---|
| `vendor/codex-security/` | The portable layer, **verbatim**, + `NOTICE.md` provenance |
| `skills/codex-security/SKILL.md` | The Claude Code adapter — routing table, Codex→Claude translation table, sealing procedure, hard rules |

The adapter is the only original work. It maps `$skill-name` → read that `SKILL.md`; the
`*_codex_security_*` MCP tools → the documented prompt-only path; Codex worker fan-out → Claude
`Agent` subagents; `complete_codex_security_scan` → a direct `finalize_scan_contract.py` call.

Nothing under `vendor/` is edited — adaptation lives entirely in the adapter.

## 5. Proof: a real sealed scan of this repo

Scope `hooks/` — 69 files, 10,459 lines. Chosen because these scripts run automatically on every
tool call and receive model-influenced `tool_input`, making them the genuine untrusted-input
boundary.

The bundle was sealed by the **upstream, unmodified** `finalize_scan_contract.py` (`rc=0`), which
validates all three canonical documents against the upstream JSON Schemas and deterministically
generates `report.md` + SARIF 2.1.0. **That is the un-fakeable part**: a bundle Claude produced
passes OpenAI's own validator. The validator is real — it rejected three separate malformed
drafts first (non-canonical scan path, `remediationTests` as string rather than array,
`explicitExclusions` needing `pattern` not `path`).

### Findings

| # | Finding | Severity | Confidence |
|---|---|---|---|
| 1 | Catastrophic-command denylist bypassed by equivalent flag spellings (`hooks/validate-bash.sh:94`) | medium | high |
| 2 | Notification hook appends to fixed paths in world-writable `/tmp` (`hooks/notify.sh:35,88`) | low | high |

**Finding 1 is a genuine defect, reproduced by execution, not inference.** Feeding crafted
payloads to the hook and reading the emitted `permissionDecision`:

| Command | Decision |
|---|---|
| `rm -rf /*` | `deny` ✅ |
| `rm -fr /*` | `ask` ⚠️ downgraded |
| `rm -r -f /*` | `ask` ⚠️ downgraded |
| `rm --recursive --force /*` | **no decision at all** ❌ |
| `rm -rf /` (bare, at end of input) | `ask` ⚠️ downgraded |

Root cause is precise: the deny regex hardcodes the `-rf` bundle, and its slash branch ends in
`[^a-zA-Z]`, which must *consume* a character — so the bare form cannot match. The sibling tilde
branch **in the same alternation** is written `~(/|$|[[:space:]])` and does accept end-of-input.
That internal inconsistency is what proves this is an oversight rather than a deliberate choice.

Severity was held at **medium**, not critical, because `rm-safe-allowlist.sh` was checked and
found sound — it defers rather than auto-allowing, so the command still falls through to the base
`Bash(rm:*)` ask rule. Honest calibration over a scary headline is the point of the methodology.

Five other surfaces were reviewed and closed as `no_issue_found` / `not_applicable` with recorded
reasons — no `eval` with interpolation anywhere in scope, decision JSON correctly escaped, no
network egress from any hook.

### Reproduce

```bash
scan_dir="${TMPDIR:-/tmp}/codex-security-scans/claude-infrastructure/<scan_id>"
python3 vendor/codex-security/scripts/finalize_scan_contract.py \
  --scan-dir "$scan_dir" --source-root "$(git rev-parse --show-toplevel)"
```

## 6. Honest limits

- ~~**The upstream npm CLI remains unusable** without Codex, by design.~~ **CORRECTED later the
  same day — see §8.** The CLI runs fine on this machine. We reuse the methodology, not the
  launcher, but that is now a *choice*, not a constraint. Anything the *desktop workspace* adds
  (scan history UI, cross-repo finding tracking, the deep-scan MCP fan-out orchestrator) is still
  not ported.
- **Quality is now a function of Claude, not of a vendored scanner.** The skills are phase
  discipline and contracts; they constrain and structure the reasoning, they do not perform it.
- **`bin/` and `scripts/` (~39k lines) were not scanned** — out of scope for this demonstration.
- The scan did not audit the `settings.json` permission arrays, which is what would settle whether
  Finding 1 is medium or critical in unattended operation. Recorded as an open question in
  `coverage.json`.

## 7. Bottom line

Employable today, at zero marginal cost, with no OpenAI relationship of any kind. The thing worth
having was never the binary — it was ~2,300 lines of scan methodology, a 3-schema evidence
contract, and a deterministic finalizer that refuses to seal sloppy work. All three are Apache-2.0
and now vendored.

The first real scan found a reproducible bypass in our own command-safety guard, which is a
reasonable argument that the methodology earns its place.

## 8. Update — the CLI *is* runnable, and it was measured

Later on 2026-07-29 the untested premise behind §6's first bullet was checked against this machine
rather than against the dependency graph. Codex CLI `0.142.2` is installed and **logged in via
ChatGPT**, so `npx @openai/codex-security@0.1.4` runs end-to-end with `--auth chatgpt` — no API key,
no separate subscription. §6's first bullet is struck above.

Both paths were then run against the *same* file to calibrate them. The full write-up, the
three-repo runbook, and the shard plans live in
[`codex-security-three-repos-2026-07-29.md`](codex-security-three-repos-2026-07-29.md). The three
findings that change how this port should be used:

1. **OpenAI's cyber classifier refuses `hooks/validate-bash.sh` mid-scan** ("flagged for possible
   cybersecurity risk… join the Trusted Access for Cyber program"), while the same credential
   completed a scan of an ordinary auth module minutes later. The refusal is **content-triggered,
   not account-gated** — and it lands on precisely the file class this repo is made of. For
   `claude-infrastructure`, the Claude-native path is not the cheap option, it is the *only* option.
2. **Cost: ~$14.22 and ~17 minutes for one 170-line file** (17.2M input tokens, 8-way worker
   fan-out). Path A's "zero marginal cost" is therefore the headline advantage, not a footnote.
3. **Path B independently rediscovered Finding 1** (`rm-equivalent-option-spellings`) and added 9
   more candidate classes on the same file — 6 of them one family: **shell token concatenation
   defeats every raw-text matcher** (`drizzle-kit pu''sh` executes as `push`; `sqlite3 'DR''OP TABLE
   users'`). Our denylist does not model it. That family is now the highest-value open item against
   this repo's own guard, and it is validatable on Path A for free.
