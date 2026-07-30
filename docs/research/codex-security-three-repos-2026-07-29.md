# Running Codex Security against our three repositories

**Date:** 2026-07-29 · **Repos:** `claude-infrastructure`, `reso-management-app`, `doc_classifier`

**Verdict: both paths work, and the choice is not about capability — it is about a content
classifier and a price tag.** The upstream OpenAI CLI is fully runnable here (previously believed
unusable) and produces excellent findings, but it costs **~$14 and ~17 minutes per single 170-line
file**, and OpenAI's cyber classifier **refuses outright** on the exact file class this
infrastructure repo is made of. The Claude-native port is free, unrefusable, and emits the same
sealed contract.

Supersedes the "honest limits" of
[`codex-security-in-claude-code-2026-07-29.md`](codex-security-in-claude-code-2026-07-29.md) §6,
which assumed the npm CLI was out of reach.

---

## 1. The two paths, as they actually stand today

| | **Path A — Claude-native** | **Path B — upstream Codex CLI** |
|---|---|---|
| Driver | Claude Code + `skills/codex-security` | `npx @openai/codex-security@0.1.4` |
| Methodology layer | `vendor/codex-security/` (plugin `0.1.14`) | bundled plugin **`0.1.14` — byte-identical version** |
| Engine | Claude (this session) | `gpt-5.6-sol` @ `xhigh`, ≤8 delegated workers |
| Credential | none | Codex CLI `0.142.2`, **ChatGPT login** (no API key) |
| Marginal cost | **$0** | **~$14.22 / 170-LOC file** (measured, §4) |
| Cyber-policy gate | none | **refuses on security-control source** (§3) |
| Orchestration | manual phase discipline + `Agent` subagents | automatic worker fan-out, resumable, `bulk-scan` |
| Output | same 3 canonical JSON + `report.md` + SARIF | same, plus `exports/results.sarif` |

**The methodology is not the variable.** `codex-security info` reports
`bundledPluginVersion: 0.1.14`, and our `vendor/NOTICE.md` records the same `0.1.14` vendored from
upstream `f22d4a36`. Both paths run identical skills, references, schemas, and the same
deterministic finalizer. The only differences are the reasoning engine and the orchestration.

## 2. Path B is runnable — the prior doc was wrong about this

The earlier conclusion ("the npm CLI needs Codex and a credential, which is exactly what we are
avoiding") was reasoned from the dependency graph, never tested against this machine. On this
machine Codex is already present:

```
codex-cli 0.142.2  (standalone, ~/.local/bin/codex)   codex doctor: all ✓
codex login status → "Logged in using ChatGPT"        ~/.codex/auth.json: tokens, no OPENAI_API_KEY
```

`@openai/codex-security@0.1.4` pins its own `@openai/codex@0.144.6` + `codex-sdk@0.144.6`, so `npx`
supplies the runtime regardless of the older local binary. `scan --auth <auto|chatgpt|api-key>`
accepts the ChatGPT credential — **no API key and no separate subscription were needed.**

All three repos clear preflight identically:

```
$ cd <repo> && npx -y @openai/codex-security@0.1.4 scan . --dry-run
dryRun: true · target.kind: repository · mode: standard
authentication.method: stored_credentials · model: gpt-5.6-sol · reasoningEffort: xhigh
```

## 3. The blocker that decides repo #1: OpenAI's cyber classifier

Scanning `hooks/validate-bash.sh` (this repo's catastrophic-command denylist) **was refused
mid-scan**, after ~2 minutes of real work:

```
[01:08] Preflight: worker delegation supported (up to 8 worker slots).
codex-security: This content was flagged for possible cybersecurity risk. …
  To get authorized for security work, join the Trusted Access for Cyber program:
  https://chatgpt.com/cyber
codex-security: Partial output was kept at <output-dir>.
```

**This refusal is content-triggered, not account-gated** — proven by a control on the same account
minutes later: `doc_classifier/reviewapp/api/auth.py` scanned **to completion**, sealed, 3 findings.
So the same credential is simultaneously allowed and refused depending on the file under review.

The mechanism is unsurprising once named: a hook whose body is a denylist of `rm -rf /`, fork bombs,
and process-kill patterns reads to a cyber classifier exactly like the thing it exists to prevent.
**The most security-relevant file in `claude-infrastructure` is the file Path B cannot look at.**

What the refusal cost and what survived — the run is resumable and partial output is kept:

| Phase | State at refusal |
|---|---|
| `01_context/threat_model.md` | **written, and genuinely good** — correctly identifies hooks as runtime controls, `tool_input` as lower-trust, and calibrates severity to the local-user boundary |
| `02_discovery/candidate_ledger.jsonl` | **10 candidates** |
| `03_coverage/`, `05_findings/` | **empty** — killed before validation and severity calibration |

The 10 candidates are unvalidated leads, not findings (validation is precisely the pass that
suppresses plausible-sounding false positives) — but they are a strong calibration signal, because
one of them is `rm-equivalent-option-spellings`, i.e. **Path B independently rediscovered the exact
defect Path A found yesterday**, then went further:

| Candidate | CWE | Novel vs Path A? |
|---|---|---|
| `rm-equivalent-option-spellings` | CWE-184 | no — corroborates the known `-rf` gap |
| `database-ddl-obfuscation` (`sqlite3 app.db 'DR''OP TABLE users'`) | CWE-184 | **yes** |
| `drizzle-push-obfuscation` (`drizzle-kit pu''sh`) | CWE-184 | **yes** |
| `git-force-add` (`git -C /tmp add -f`) | CWE-184 | **yes** |
| `git-precommit-bypass`, `git-signing-bypass` | CWE-184 | **yes** |
| `unscoped-gate-process-kill` | CWE-184 | **yes** |
| `rm-safe-prefix-path-traversal` | CWE-22 | **yes** |
| `bash-audit-log-injection` (newline in session id forges log records) | CWE-117 | **yes** |
| `literal-command-secret-logging` | CWE-532 | **yes** |

The unifying insight in 6 of 10 — **shell token concatenation defeats every raw-text matcher**
(`pu''sh` executes as `push`) — is a whole bypass family our own denylist does not model. That is
worth acting on regardless of which path we adopt, and it is the single most valuable output of this
investigation.

## 4. What Path B actually costs — measured, not estimated

The one scan that completed, on **one 170-line file**:

```
[16:42] Scan complete
Findings: 3 (1 medium, 2 low). Coverage: complete.
Elapsed: 998s.
Tokens: 17,202,589 input, 16,460,800 cached, 75,991 output.
Estimated cost: $14.219075 USD
```

**17.2M input tokens for 170 lines of source.** The cost is dominated by whole-repo context
exploration and 8-way worker fan-out, not by the target's size — so it does *not* scale linearly
with LOC, but it also does not shrink much for small targets. Read the dollar figure carefully:
under `--auth chatgpt` this is the CLI's own **API-equivalent estimate**, and the actual draw is
against ChatGPT/Codex plan rate limits rather than an invoice. Either way it is the correct
order-of-magnitude signal, and `--max-cost` exists precisely because of it.

Extrapolating to whole repos is not defensible from one data point, but the shape is clear: a
per-shard scan of the surfaces mapped in §6 is a **multi-hour, plan-quota-consuming** exercise per
repo, and a whole-repo `scan .` at `xhigh` on 100k+ LOC is not something to launch casually.

Quality, though, is high — these are not pattern matches. The medium finding was proven by an
executed PoC (`poc_jwks_fetch_count.py` observed 4 JWKS fetches from 2 rejected tokens), and the
scan ran 24 of the repo's own tests as supporting evidence:

| Finding | Severity | Confidence |
|---|---|---|
| Fresh JWKS client per token → pre-authentication fetch amplification | medium | high |
| DNS rebinding can inherit the local launcher's all-role principal | low | medium |
| UPN local-part mapping merges distinct reviewer identities | low | high |

All three sit exactly on the surfaces an independent recon pass had flagged as highest-value
(`auth.py`'s loopback `local_principal` bypass, JWT validation, identity keying) — mutual
corroboration that the shard plan in §6 points at real defects.

## 5. Recommendation

**Per repo, split by the classifier and by cost:**

| Repo | Path | Why |
|---|---|---|
| `claude-infrastructure` | **A (Claude-native)** | Path B is refused on its core security surface (§3). Not a preference — a hard block. |
| `doc_classifier` | **B for 1–2 highest-value shards, A for the rest** | Path B is proven end-to-end here and its findings are strong. Rich untrusted-input surface (request→`Popen`, unconfined `Path(path)`, loopback auth bypass, document→prompt injection) rewards the spend. |
| `reso-management-app` | **A first, B for shard S3 only** | 61 interpolated `` sql` `` templates in the Replicache builders is the one surface where an executed-PoC engine earns its cost; the other 6 shards are cheaper on Path A. |

**Do not run `scan .` on a whole repo.** Always `--path`-scope to a shard from §6. Rationale: cost
(§4), and coverage honesty — a scoped scan that reports `completeness: complete` is worth more than
a whole-repo scan that silently defers.

Path A remains the default for breadth because it is free, unrefusable, and produces a bundle sealed
by the same upstream validator. Path B is the escalation for a shard where an executed proof-of-
concept changes the verdict.

**One thing to do irrespective of path:** fix the token-concatenation bypass family (§3). It is
already 6 of 10 candidates against our own guard.

## 6. Per-repo scan surface and shards

Measured tracked-code LOC (excluding `node_modules`, `dist`, generated, and test trees):

| Repo | Tracked files | Security-relevant code LOC |
|---|---|---|
| `claude-infrastructure` | 926 | 122,190 (239 `.sh`, 204 `.bats`, 50 `.py`) |
| `reso-management-app` | 3,886 | 314,085 total → **~52k genuinely server-side** |
| `doc_classifier` | 1,735 | 184,689 total → **~102k non-test** |

### `claude-infrastructure` — Path A only

Threat model is **not** web-app vulnerability classes. The live risk is shell that runs
automatically as Claude Code hooks over model-influenced `tool_input`: command injection, unquoted
expansion, path traversal, `eval` on attacker-influenced data, and **denylist bypass by equivalent
spelling or token concatenation**. Priority order: `hooks/` (69 files, 10.4k lines — already scanned
on Path A, now with 9 fresh candidate classes to run down) → `bin/` and `scripts/` (~39k lines,
never scanned) → `install.sh` + deploy path.

### `reso-management-app` — 7 shards

Next.js 16.2.6 / React 19.2.4 / drizzle+Turso (libSQL) / pnpm 11.9.0. Auth is **passkey/WebAuthn
only** (`iron-session-v8@8.0.0-renchris-v8` fork + SimpleWebAuthn). Critically,
`middleware.ts` is **CSP-nonce injection only, not auth**, and its matcher **excludes `/api`** — so
every authorization decision is per-handler, which is the dominant scan implication.

| # | Shard | ~LOC | Focus |
|---|---|---|---|
| S1 | Auth & session — `lib/auth/**`, `src/app/actions/auth/**`, 5 auth routes | 7.5k | passkey ceremonies, iron-session fork, `dev-login` + `load-test-login` bypass-shaped routes |
| S2 | Multi-tenant authz — `venue-authz`, `roleHelpers`, `lib/config/tenants.ts`, admin | 8k | cross-tenant IDOR across 4 DB regions; 38 authz consumers |
| **S3** | **Replicache sync ingress** — `src/app/actions/replicache/**` | **12.6k** | **61 interpolated `` sql` `` templates — the #1 injection target** |
| S4 | Route handlers + CSP + rate limiting — 15 `api/**/route.ts`, `middleware.ts` | 6k | unauthenticated surfaces, `/api` outside middleware, `api/debug/vapid` |
| S5 | Data layer + fleet migration — `drizzle/**`, 5 region configs, `pre-build/**` | 7k | region credential handling, prod-vs-dev DB fallback (`oregon-harbourtwo` config is `0644`, siblings `0600`) |
| S6 | Remaining server actions + validators (hand-rolled, no zod) | 12k | missing action-level authz |
| S7 | Infra + secrets pipeline + integrations + CI | 12k | `infrastructure/reso-deploy/server.ts` (a second HTTP server that shells out to deploy runners), `amplify.yml` secret extraction via `grep '^X=' .env`, Square webhook HMAC, `spikes/stripe/**` live-key Python probes |

Existing coverage to credit, not re-derive: `SECURITY.md` (pnpm `allowBuilds` allowlist, SHA-pinned
Actions, frozen lockfiles), `.audit-ci.json`, and a dependency-audit-only CI workflow — **no SAST,
no secret scanning, no CodeQL**. Out of scope: `src/app/(preview)` (59.8k, static),
`drizzle/migrations` (280.8k), `styled-system`, `public/`.

### `doc_classifier` — 5 shards

Python ≥3.12 / uv / FastAPI + React 19 ReviewApp / Azure-Government posture / synthetic data only.
Credentials are `DefaultAzureCredential` through a single documented constructor, no API keys. A
homegrown gate suite already enforces `no_secrets`, `no_text_leak`, `one_azure_choke_point`.

| # | Shard | ~LOC | Focus |
|---|---|---|---|
| **A** | **Web attack surface** — `reviewapp/api/**` | **9.0k** | `auth.py` loopback `local_principal` bypass · `routers/run.py` (1,117 LOC: request body → argv → `Popen`, `run_id` as path segment with an in-code traversal note at :192) · `routers/corpus.py` unconfined `Path(path)` ("there is no root to confine") · `routers/audit.py` `ld_id` → blob stream · `main.py` has **no CORS or security middleware** |
| B | Azure/LLM egress + credentials | 6.4k | `azure_client.py` choke point, endpoint construction/SSRF, `az` subprocess argv, retry/DoS |
| C | Untrusted document ingestion + **prompt injection** | 8.5k | PDF parsers (pdfplumber, pdfjs) · filename → URI by string concat (`freezer.py:176`) · `ch_p/assemble.py` passes raw DI text into prompts "UNTOUCHED" by design · model-output schema enforcement in `harness.py` |
| D | Data handling, redaction, config plumbing | 7.5k | `config/loader.py` (`yaml.safe_load` only — correctly), artifact path derivation, redaction/leak-scan correctness |
| E | Build, CI, provisioning, IaC, frontend | 11.5k | 9 Bicep templates, `hardening.sh`/`rbac.sh`, workflow permissions, `pdfjs-dist` untrusted-PDF rendering |

Shard A is where the completed Path B scan already landed 3 findings — **it is the highest-yield
shard across all three repos.** Defer `s6_calibration`, `s8_eval`, `s3_families`,
`s5_verify_reduce`, `s2_segmentation` (~25k LOC): pure numeric transforms over already-validated
typed records, no I/O, credential, or path surface. Notably **no `SECURITY.md`**, and no
`gitleaks`/`pip-audit`/CodeQL/Trivy in CI.

## 7. Path B operating notes — the preflight guards, in the order they bite

Three separate refusals before any model work, each costing a round trip. All are cheap to
pre-satisfy:

1. **`--format md` is rejected for scan results** — `"Markdown output is not supported"`. Use the
   default (`toon`), or `--format json`. `report.md` is written to the output dir regardless.
2. **The output dir must be `chmod 700`** — `"Scan output directory must not be accessible to other
   users"`. `mkdir -p "$out" && chmod 700 "$out"`.
3. **The output dir must be outside the repository** (and is required for `bulk-scan` with a CSV).

Then:

- **Keep HEAD still.** A concurrent land during the scan produced `warning: Repository HEAD changed
  while the scan was running; results were saved for the original revision.` On this machine, with a
  fleet that lands continuously, scan from a **dedicated worktree** pinned to a fixed revision.
- **`echo $?` after a pipe lies** — it reports the tail's status. Use `${PIPESTATUS[0]}`, or
  `--fail-on-severity` for a meaningful exit code.
- **Scans are CLI-only** (`scanMcp: false`) — "the MCP transport cannot cancel active commands".
- Useful flags: `--effort minimal…xhigh` (default `xhigh`), `--mode standard|deep`,
  `--max-cost <usd>`, `--fail-on-severity`, `--knowledge-base <path>` (feed it `SECURITY.md` and the
  repo's threat notes), `--archive-existing`.
- Review loop: `scans list|show|rerun|match|compare`, `findings false-positive` (persists FP
  suppression across scans), `patch`, `export --format csv|json|sarif`.
- `install-hook` adds a **pre-commit** security scan (`--fail-on-severity high` by default). At ~17
  minutes and ~$14 per file, **do not install this** on these repos.

### Canonical invocations

```bash
# Path A — any repo, free, no credential. From the target repo:
#   load the codex-security skill; it resolves plugin_dir to
#   $CLAUDE_CONFIG_DIR/vendor/codex-security (deployed in .claude, -next,
#   -secondary, -tertiary — verified) and seals with the upstream finalizer.

# Path B — one shard, bounded:
out="$HOME/codex-security-runs/<repo>-<shard>"; mkdir -p "$out"; chmod 700 "$out"
cd <repo-worktree-pinned-to-a-revision>
npx -y @openai/codex-security@0.1.4 scan . \
  --path <shard-path> [--path <more>] \
  --output-dir "$out" --effort medium \
  --max-cost 25 --fail-on-severity high
echo "rc=${PIPESTATUS[0]}"

# Path B — all three repos in one resumable run (only if the classifier and
# the cost are both acceptable; claude-infrastructure will refuse):
printf 'repository,mode\n%s,standard\n%s,standard\n' \
  "$HOME/Development/doc_classifier" "$HOME/Development/reso-management-app" > repos.csv
npx -y @openai/codex-security@0.1.4 bulk-scan repos.csv \
  --output-dir "$HOME/codex-security-runs/bulk" --workers 2 --max-attempts 3
```

## 8. Open questions

- **Trusted Access for Cyber** (<https://chatgpt.com/cyber>) is the named remedy for the §3
  refusal. Whether this account qualifies, and whether approval would unblock
  `hooks/validate-bash.sh` specifically, is untested — it requires an application, so it is an
  operator decision, not an agent action.
- Whether the refusal generalizes beyond hook-denylist source (e.g. to
  `reso`'s `lib/square/verify-signature.ts` or `doc_classifier`'s `scripts/gates/no_secrets.sh`,
  which also contains credential-shaped constants) is unmeasured. One refusal and one success is
  enough to prove content-dependence, not enough to predict which files trip it.
- Per-shard cost at `--effort medium` vs `xhigh` is unmeasured; the single data point is `medium`.
- The 9 novel bypass candidates from §3 are **unvalidated**. Running them down on Path A — where
  there is no classifier and no cost — is the obvious next step.
